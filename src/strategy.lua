-- Stratégie individuelle des IA (Beta 1.42, demande du pilote) : arrêts aux stands selon l'usure des pneus, le carburant
-- et l'avancement de la course, caractère de chaque stratège (prise de risque tirée de la graine, persona.lua), tour de
-- sortie à pneus froids, pannes progressives jusqu'aux stands, journal des blocages qui usent un pneu (mistakes.lua).
-- Décisions pures : écritures par les commandes (cmd.rulePit, pitHold, levelScale en produit, throttleLimit en minimum,
-- stratLaps et stratPlanAt pour pits.lua). Course seulement pour les arrêts et les pannes ; tour de sortie dans tout
-- profil où il est coché. Jamais le joueur, la voiture de sécurité, une IA arrivée ou disqualifiée, ni en ligne ou en
-- relecture. Plan revu au plus une fois par tour et par IA (ou à un arrêt, une neutralisation, un arrêt d'un rival).
local U=require('src/util')
local C=require('src/config')
local K=C.K
local L=require('src/lang')
local Locale=require('src/locale')
local Pits=require('src/pits')
local floor,max,min,abs=math.floor,math.max,math.min,math.abs
local M={}
local function car()
 return {identity='',lap=-1,lapWear=-1,wearRate=0,wearLaps=0,lastWear=0,planned=false,stops=-1,nextLap=-1,limit='',planLoggedAt=-math.huge,
  shift=0,reaction=false,wanted=false,cause='',wantSince=0,visit=-1,inLane=false,replan=false,retryAt=0,
  boxSeen=false,outLap=false,outFrom=0,outLap0=-1,outEnd=-math.huge,outLogged=false,
  failState=0,failKind='',failAt=0,failRamp=0,failLoss=0,failChecks=0,failNext=0,failVisit=-1,failRepair=0,failAsked=false,
  wearSeen=0,rivalLane=false,
  -- Relecture 1.42 : appel tenu (place d'appel gardée), arrêt servi, contrôle après l'arrêt (pneus posés, carburant
  -- ajouté), causes abandonnées pour le reste de la session, batterie vue (hybride), carburant critique, usure de sonde.
  called=false,serving=false,servedVisit=-1,stopWear=-1,stopFuel=-1,stopCause='',stopLimit='',checkAfter=false,checkAt=0,
  noTyreStop=false,noFuelStop=false,kersSeen=false,critical=false,hardTyres=false,deferLogged=false,wearLow=-1,wearLowLap=-1,blockOut=false,
  -- Relecture 1.42 (après correctifs) : premier tour vu par la sonde de l'usure, dernier passage à l'emplacement vu,
  -- carburant demandé avant l'emplacement, arrêt servi sous drapeau rouge.
  probeFrom=-1,lastVisit=-1,stopTarget=-1,stopRed=false}
end
local function clear(list) for k=#list,1,-1 do list[k]=nil end end
function M.new()
 local t={cars={},rows={},events={},head=0,lang='',dirty=false,resetAt=0,outCount=0,outSummary=false,neutralWas=false,wearTrust='unknown'}
 for i=1,K.maxCars do t.cars[i]=car() end
 for k=1,K.strategyRows do t.events[k]={what='',kind='soft',args={},text=''} end
 return t
end
-- Changement de session : plans, caractères et pannes oubliés.
function M.reset(t,now)
 for i=1,K.maxCars do t.cars[i]=car() end
 clear(t.rows); t.head=0; for k=1,K.strategyRows do t.events[k].what='' end
 t.dirty=false; t.resetAt=now; t.outCount=0; t.outSummary=false; t.neutralWas=false
 -- Échelle de l'usure vérifiée une fois pour toutes (même jeu) ; sinon revue à chaque session.
 if t.wearTrust~='trusted' then t.wearTrust='unknown' end
end
-- Redémarrage d'une session de même indice : pannes mémorisées avant un rechargement oubliées (comme Pits.forget).
function M.forget(t) t.restored=nil; t.restoredSession=-1 end
function M.rebase(t,amount)
 if t.resetAt then t.resetAt=t.resetAt-amount end
 for i=1,K.maxCars do
  local c=t.cars[i]
  c.planLoggedAt=c.planLoggedAt-amount; c.wantSince=c.wantSince-amount; c.outFrom=c.outFrom-amount; c.retryAt=c.retryAt-amount
  c.failAt=c.failAt-amount; c.failNext=c.failNext-amount; c.checkAt=c.checkAt-amount
  -- Relecture 1.52 : fin du tour de sortie décalée aussi (repère -math.huge : pas encore finie).
  if U.finite(c.outEnd) then c.outEnd=c.outEnd-amount end
 end
end
-- Lignes du Diagnostic (bloc « Course des IA ») : les K.strategyRows derniers événements, du plus récent au plus ancien,
-- textes construits à l'événement, refaits seulement au changement de langue.
local function render(ev)
 local T=L.strategyTexts; local X=T; local a=ev.args
 if ev.what=='plan' then ev.text=a[2]>0 and string.format(T.plan,a[1],a[2],a[3]) or string.format(X.planNone,a[1])
 elseif ev.what=='stop' then ev.text=string.format(T.stop,a[1],X.causes[a[2]] or T.causes[a[2]] or a[2])
 elseif ev.what=='failure' then ev.text=string.format(T.failure,a[1],T.kinds[a[2]] or a[2])
 elseif ev.what=='repaired' then ev.text=string.format(X.repaired,a[1]) end
end
local function rebuild(t)
 clear(t.rows)
 for k=0,K.strategyRows-1 do
  local ev=t.events[(t.head-k-1)%K.strategyRows+1]
  if ev.what~='' then t.rows[#t.rows+1]=ev end
 end
end
local function event(t,what,a1,a2,a3)
 t.head=t.head%K.strategyRows+1
 local ev=t.events[t.head]; ev.what=what; ev.args[1]=a1; ev.args[2]=a2; ev.args[3]=a3
 ev.kind=what=='failure' and 'warn' or what=='repaired' and 'text' or 'soft'
 render(ev); rebuild(t)
end
local function relang(t)
 if t.lang==Locale.current then return end
 t.lang=Locale.current
 for k=1,K.strategyRows do local ev=t.events[k]; if ev.what~='' then render(ev) end end
end
-- Usure la plus forte des quatre pneus (0 neuf, 1 usé), -1 inconnue.
local function wearOf(a)
 if not a.wearKnown or not a.tyreWear then return -1 end
 local w=a.tyreWear; return max(w[1] or 0,w[2] or 0,w[3] or 0,w[4] or 0)
end
local function name(a) return a.name or ('#'..tostring(a.index or '?')) end
-- Relecture 1.42 : échelle de l'usure lue (SDK : 0 neuf, 1 usé) vérifiée en jeu avant de s'en servir. Une IA vue sous
-- K.wearTrustLow (pneus neufs ou presque) dont l'usure monte ensuite d'au moins K.wearTrustRise sur un tour suivant :
-- échelle vérifiée. Avant cela, ni arrêt pour les pneus, ni blocages liés à l'usure (mistakes.lua) ; une ligne si aucune
-- IA ne l'a montrée après K.wearProbeLaps tours.
local function wearUse(t,a) if t.wearTrust~='trusted' then return -1 end return wearOf(a) end
local function probe(t,e,a,c,i,now)
 if t.wearTrust=='trusted' then return end
 local w=wearOf(a); if w<0 then return end
 local lap=a.lap or 0
 -- Relecture 1.42 (après correctifs) : tours observés depuis le début de la sonde (rechargement de l'app en pleine course).
 if c.probeFrom<0 then c.probeFrom=lap end
 if w<=K.wearTrustLow and (c.wearLow<0 or w<c.wearLow) then c.wearLow=w; c.wearLowLap=lap end
 if c.wearLow>=0 and w>=c.wearLow+K.wearTrustRise and lap>c.wearLowLap then
  t.wearTrust='trusted'
  U.log(e.log,now,'INFO',string.format('usure des pneus: echelle verifiee sur %s (%.1f %% a %.1f %% en %d tour(s))',name(a),c.wearLow*100,w*100,lap-c.wearLowLap),i)
 elseif t.wearTrust=='unknown' and lap-c.probeFrom>=K.wearProbeLaps then
  t.wearTrust='unreliable'
  U.log(e.log,now,'INFO',string.format('usure des pneus non fiable ici (%s : %.1f %% apres %d tours) : ni arret pour les pneus, ni blocages lies a l usure',name(a),w*100,lap),i)
 end
end
-- Tours restants de la voiture : course aux tours, sinon estimation du leader (e.race), plus le tour qui suit la fin du
-- temps (comme pits.lua) ; -1 inconnus. Aussi pour l'urgence des derniers tours (director.lua), voiture par voiture.
local function lapsLeft(e,frame,a,i)
 if frame.sessionLaps>0 and not frame.timedRace then return max(0,frame.sessionLaps-(a.lap or 0)) end
 -- Relecture 1.42 (après correctifs) : course chronométrée au rythme propre de la voiture, comme pits.lua.
 local pc=i and e.pits.cars[i]
 if pc and (pc.lapTime or 0)>0 and frame.sessionMinutes>0 then return Pits.lapsLeft(frame,a,pc.lapTime) end
 return e.race.known and e.race.lapsLeft+1 or -1
end
M.lapsLeft=lapsLeft
-- Plan du relais : tours encore possibles avant le seuil d'usure (ajusté par la prise de risque) et avant la réserve de
-- carburant (marge réglée, plus courte pour un stratège audacieux) ; nombre d'arrêts jusqu'à l'arrivée.
local function plan(t,c,e,frame,a,p,i,risk)
 local left=lapsLeft(e,frame,a,i)
 local wear=c.noTyreStop and -1 or wearUse(t,a)
 local threshold=U.clamp(p.strategyTyreWearPct/100*(1+(risk-0.5)*K.strategyRiskWear),K.strategyWearMin,K.strategyWearMax)
 local tyreLaps,fullTyre,tyreHard=math.huge,math.huge,math.huge
 if wear>=0 and c.wearRate>0 then tyreLaps=(threshold-wear)/c.wearRate; fullTyre=threshold/c.wearRate; tyreHard=(K.strategyWearMax-wear)/c.wearRate end
 local pc=e.pits.cars[i]
 -- Relecture 1.42 : consommation la plus forte de celle apprise et de l'estimation d'AC (une neutralisation fausse la
 -- première) ; aucune si la consommation est coupée ou si un arrêt n'a pas ajouté de carburant.
 local perLap=max(pc and pc.perLap or 0,a.fuelPerLap or 0)
 if (frame.fuelRate or 1)<=0 or c.noFuelStop then perLap=0 end
 local margin=p.strategyFuelMarginLaps*(1-(risk-0.5)*K.strategyRiskFuel)
 local fuelLaps,fullFuel=math.huge,math.huge
 if perLap>0 and (a.fuel or -1)>=0 and (a.maxFuel or 0)>0 then
  fuelLaps=a.fuel/perLap-K.fuelReserveLaps-margin; fullFuel=a.maxFuel/perLap-K.fuelReserveLaps-margin
 end
 local laps=min(tyreLaps,fuelLaps)
 c.limit=tyreLaps<=fuelLaps and 'tyres' or 'fuel'
 -- Carburant pour moins de K.strategyCriticalFuel tours sans pouvoir finir : arrêt sans attendre (stands fermés et limite
 -- d'appels comprises) ; pneus au bout de l'usure maximale dans le tour : jamais retenus par la fenêtre obligatoire.
 local raw=perLap>0 and (a.fuel or -1)>=0 and a.fuel/perLap or math.huge
 c.critical=left>=0 and raw<K.strategyCriticalFuel and raw<left
 c.hardTyres=tyreHard<=1
 if laps==math.huge or left<0 then c.stops=-1; c.nextLap=-1; c.planned=false; return left,laps,threshold end
 -- Fin de course : aucun arrêt si le carburant couvre l'arrivée avec la réserve et si les pneus tiennent jusqu'à
 -- l'usure maximale, au plus K.strategyStretchLaps tours (selon la prise de risque) au-delà du seuil réglé ; la marge de
 -- carburant ne sert qu'à placer un arrêt nécessaire (sinon un ravitaillement jusqu'à l'arrivée en redemanderait un).
 -- Relecture 1.42 : dans les K.strategyLastLaps derniers tours, réserve réduite à K.strategyEndReserve et aucun arrêt pour
 -- les pneus (un arrêt y coûte plus qu'il ne rapporte).
 local endRun=left<=K.strategyLastLaps
 local finishFuel=perLap>0 and (a.fuel or -1)>=0 and a.fuel/perLap-(endRun and K.strategyEndReserve or K.fuelReserveLaps) or math.huge
 if finishFuel>=left and (endRun or tyreHard>=left and tyreLaps+K.strategyStretchLaps*(0.5+risk)>=left) then
  c.stops=0; c.nextLap=-1; c.planned=true; return left,laps,threshold
 end
 -- Overcut : tours de plus, jamais au-delà de la réserve de carburant ni de l'usure maximale.
 if c.shift~=0 then laps=min(laps+c.shift,fuelLaps,tyreHard) end
 local stint=max(1,min(fullTyre,fullFuel))
 if laps>=left then c.stops=0; c.nextLap=-1
 else
  local rest=left-max(0,laps)
  c.stops=1+max(0,math.ceil(rest/stint)-1)
  c.nextLap=(a.lap or 0)+max(0,floor(laps))
 end
 c.planned=true
 return left,laps,threshold
end
local function eligible(a,s,e,i)
 return a.valid and a.control and not a.player and not a.finished and not a.safetyCar and not s.disqualified and not (e.penalties.ai.dq and e.penalties.ai.dq[i])
end
-- Demande d'arrêt de la stratégie (journal une fois par demande).
local function want(t,e,c,a,i,cause,now)
 if c.wanted then return end
 c.wanted=true; c.cause=cause; c.wantSince=now; c.visit=e.pits.cars[i].visit
 c.stopWear=wearOf(a); c.stopFuel=a.fuel or -1; c.stopLimit=c.limit; c.stopTarget=-1; c.stopRed=false
 U.log(e.log,now,'INFO',string.format('strategie: %s arret demande (%s)',name(a),cause=='tyres' and string.format('pneus %.0f %%',max(0,wearOf(a))*100) or K.strategyCauseLog[cause] or cause),i)
 event(t,'stop',name(a),cause)
end
-- Arrêt d'un rival proche (même tour, moins de K.strategyRivalGap s) : le stratège derrière qui a de bons pneus reste
-- dehors (overcut), celui devant couvre l'undercut au tour suivant s'il était prudent ; un audacieux à quelques tours de
-- son arrêt devance le rival devant lui (undercut). Une seule réaction par relais.
-- Beta 1.47 : arrêt obligatoire encore dû, fenêtre ouverte (course à arrêts obligatoires, plan de la stratégie à 0 arrêt).
local function mandatoryDue(e,i,p)
 local pits=e.pits; local pc=pits and pits.cars[i]
 -- Relecture 1.52 : fenêtre ouverte en ce moment (pits.opened reste vrai après sa fermeture).
 return (p.mandatoryStops or 0)>0 and pits~=nil and pits.state=='open' and pc~=nil and pc.windowStops<p.mandatoryStops
end
local function rivals(t,e,frame,j,now,p)
 local row=e.perception.rows[j]; if not row then return end
 local b=frame.cars[j]
 local sj=e.sanctions and e.sanctions.cars[j]
 -- Ni voiture de sécurité, ni voiture arrivée, disqualifiée, en panne ou qui purge une pénalité : pas un arrêt de rival.
 if b.safetyCar or b.finished or e.commands[j].penaltyPass or sj and sj.asked and sj.pending~='' or e.states[j].disqualified or e.penalties.ai.dq[j] or t.cars[j].failState==1 then return end
 for k=1,row.count do
  local r=row.neighbors[k]; local i=r.index; local a=frame.cars[i]; local c=t.cars[i]
  if a and i~=j and c.planned and not c.reaction and not c.wanted and eligible(a,e.states[i],e,i) and not a.pit
   and abs((a.lap or 0)+(a.spline or 0)-(b.lap or 0)-(b.spline or 0))<K.strategyRivalLap and r.gap<=K.strategyRivalGap*max(K.strategyRivalMinSpeed,a.speed or 0) then
   local risk=e.states[i].persona.strategyRisk or 0.5
   local w=wearUse(t,a)
   if r.long<0 and c.stops>0 and w>=0 and w<U.clamp(p.strategyTyreWearPct/100,0,1)*K.strategyOvercutWear then
    -- Rival devant qui s'arrête : on reste dehors un ou deux tours (piste libre).
    c.shift=K.strategyOvercutLaps; c.reaction=true
    U.log(e.log,now,'INFO',string.format('strategie: %s reste dehors (overcut sur %s)',name(a),name(b)),i)
   elseif r.long>=0 and (c.stops>0 and c.nextLap>=0 and c.nextLap-(a.lap or 0)<=K.strategyCoverLaps or mandatoryDue(e,i,p)) and risk<K.strategyBoldRisk
    and w>=U.clamp(p.strategyTyreWearPct/100,0,1)*K.strategyCoverWear then
    -- Rival derrière qui s'arrête : couverture au plus tôt.
    c.reaction=true; want(t,e,c,a,i,'cover',now)
   end
  end
 end
end
-- Tour de sortie : après un vrai passage à l'emplacement (pas un drive-through), jusqu'à la ligne ou aux pneus chauds ;
-- jamais au départ d'une course. Niveau abaissé de outLapLevelPct %, rendu en douceur.
local function outLap(t,e,frame,a,c,i,p,now)
 local inLane=a.pit==true
 -- Relecture 1.42 : pas de tour de sortie après un drapeau rouge passé dans la voie, un saut de position ou un dépannage
 -- (Pits towedAt), ni au premier tour d'une course (départ des stands), ni après un passage de pénalité (cmd.noOutLap).
 local pc=e.pits.cars[i]
 local towed=pc.towedAt~=nil and now>=pc.towedAt and now-pc.towedAt<=K.towWindow
 if a.teleport or towed or inLane and e.incidents.red then c.blockOut=true end
 -- cmd.noOutLap (autre module, par exemple un drive-through servi à l'emplacement) : pas un arrêt qui refroidit les pneus.
 if inLane and a.inPitBox and (a.kmh or 0)<=K.tyreStopSpeed and (e.profile~='C' or frame.started and (a.lap or 0)>=1) and not e.commands[i].noOutLap then c.boxSeen=true end
 if c.inLane and not inLane then
  if c.boxSeen and not c.blockOut and p.outLapEnabled and p.outLapLevelPct>0 then
   c.outLap=true; c.outFrom=now; c.outLap0=a.lap or 0; c.outEnd=-math.huge
   if now-t.resetAt<K.outLapSummaryTime then t.outCount=t.outCount+1
   else U.log(e.log,now,'INFO',string.format('tour de sortie: %s pneus a chauffer (niveau -%.0f %%)',name(a),p.outLapLevelPct),i) end
  end
  c.boxSeen=false; c.blockOut=false
 elseif not inLane and not a.teleport and not towed then c.blockOut=false end
 c.inLane=inLane
 if not c.outLap then return 1 end
 if not p.outLapEnabled then c.outLap=false; return 1 end
 -- Fin : ligne passée, pneus à température, ou durée maximale ; puis retour progressif.
 if not U.finite(c.outEnd) then
  local warm=false
  if a.wearKnown and a.tyreTemp and a.tyreOptimum and (a.tyreOptimum[1] or 0)>0 then
   warm=true
   for w=1,4 do if (a.tyreTemp[w] or 0)<(a.tyreOptimum[w] or 0)-K.outLapTempMargin then warm=false end end
  end
  if (a.lap or 0)>c.outLap0 or warm or now-c.outFrom>=K.outLapMax then c.outEnd=now end
 end
 local drop=p.outLapLevelPct/100
 if U.finite(c.outEnd) then
  local f=(now-c.outEnd)/K.outLapRelease
  if f>=1 then c.outLap=false; return 1 end
  drop=drop*(1-f)
 end
 return 1-drop
end
-- Pannes progressives (rares) : tirées de la graine toutes les K.failureCheck s, jamais au premier tour, ni dans les
-- derniers K.failureLateRace de la course, ni aux stands, ni sous drapeau ; perte de rythme montée en douceur jusqu'à
-- failureLossPct %, arrêt demandé, réparée à l'emplacement (quelques secondes), puis rythme rendu. Jamais garée en piste.
local kindsHybrid={'leak','battery','overheat','puncture'}
local kindsPlain={'leak','overheat','puncture'}
local function failure(t,e,frame,a,c,i,p,now,seed,racing,cmd)
 local inc=e.incidents
 if c.failState==0 then
  if not (racing and p.failuresEnabled and p.failureRate>0) then return end
  if now<c.failNext then return end
  c.failNext=now+K.failureCheck
  local progress=e.race.progress
  if (a.lap or 0)<1 or progress<0 or progress>=K.failureLateRace or a.pit or inc.red or inc.neutral or (a.kmh or 0)<K.failureMinKmh then return end
  c.failChecks=c.failChecks+1
  -- Tirage propre à chaque session (même graine tout le week-end) : pas la même panne à chaque course.
  local salt=K.failureSalt+(frame.session or 0)*K.failureSessionSalt
  if U.unit(seed,i,salt+c.failChecks)>=p.failureRate/3600*K.failureCheck then return end
  local kinds=c.kersSeen and kindsHybrid or kindsPlain
  c.failKind=kinds[min(#kinds,floor(U.unit(seed,i,salt+K.counterMax)*#kinds)+1)]
  c.failState=1; c.failAt=now; c.failAsked=false; c.failVisit=e.pits.cars[i].visit
  c.failRamp=U.lerp(K.failureRampMin,K.failureRampMax,U.unit(seed,i,salt+K.counterMax+1))
  c.failLoss=p.failureLossPct/100*U.lerp(K.failureLossMin,1,U.unit(seed,i,salt+K.counterMax+2))
  c.failRepair=U.lerp(K.failureRepairMin,K.failureRepairMax,U.unit(seed,i,salt+K.counterMax+3))
  U.log(e.log,now,'INFO',string.format('panne: %s %s (perte %.0f %% sur %.0f s), retour aux stands',name(a),K.failureKindLog[c.failKind] or c.failKind,c.failLoss*100,c.failRamp),i)
  event(t,'failure',name(a),c.failKind)
  t.dirty=true
 end
 if c.failState~=1 or not racing then return end
 -- Réparation : à l'emplacement, voiture arrêtée, le temps tiré ; puis rythme rendu.
 local pc=e.pits.cars[i]
 if a.inPitBox and pc.visit~=c.failVisit then
  cmd.pitHold=true
  if now-pc.boxSince>=c.failRepair then
   c.failState=2; t.dirty=true
   U.log(e.log,now,'INFO',string.format('panne: %s reparee aux stands',name(a)),i)
   event(t,'repaired',name(a))
   return
  end
 end
 local f=U.clamp((now-c.failAt)/max(1,c.failRamp),0,1)
 local loss=c.failLoss*f
 cmd.levelScale=cmd.levelScale*(1-loss)
 cmd.throttleLimit=min(cmd.throttleLimit,max(K.failureThrottleMin,1-loss*K.failureThrottleShare))
 if racing and now-c.failAt>=K.failurePitDelay and not a.pit and not inc.red and not inc.pitsClosed then
  if not c.wanted then want(t,e,c,a,i,'failure',now) end
  c.failAsked=true
 end
end
-- À chaque image, après Pits.update et Merge.update (engine.lua).
function M.update(t,e,frame,now,_dt)
 local p=e.run; local profile=e.profile
 relang(t)
 for i=1,frame.count do local cmd=e.commands[i]; cmd.stratLaps=0; cmd.stratPlanAt=-1 end
 if frame.online or frame.replay then for i=1,frame.count do e.commands[i].stratCalled=false end return end
 local inc=e.incidents
 local racing=profile=='C' and frame.started==true and not frame.finished
 local active=racing and p.strategyEnabled and not inc.red
 local seed=e.runtimeG.seed
 -- Neutralisation : un stratège dont l'arrêt est proche s'arrête sous voiture de sécurité (arrêt moins coûteux).
 local neutral=inc.neutral and not inc.red
 local neutralStart=neutral and not t.neutralWas; t.neutralWas=neutral
 -- Pour pits.lua (apprentissage du carburant) : tours neutralisés exclus.
 e.pits.neutral=inc.neutral or inc.red
 -- Appels simultanés : une seule limite pour les règles (pits.lua, image en cours) et la stratégie ; les IA déjà appelées
 -- gardent leur place (un appel retiré bloque l'entrée des stands un instant), les nouvelles attendent.
 local requested=0
 -- Relecture 1.52 : appel d'une IA lente et endommagée (engine.lua, cmd.slowCalled, image précédente) compté aussi.
 for i=1,frame.count do local a=frame.cars[i]; local c=t.cars[i]; if not a.pit and (e.commands[i].rulePit or c.called and c.wanted or e.commands[i].sanCalled or e.commands[i].slowCalled) then requested=requested+1 end end
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]; local cmd=e.commands[i]; local s=e.states[i]
  local identity=a.identity or a.id or ''
  if c.identity~=identity then
   local fresh=car(); for k,v in pairs(fresh) do c[k]=v end; c.identity=identity; c.failNext=now+K.failureCheck*i/max(1,frame.count)
   -- Blocage déjà journalisé avant le changement de session : pas une nouvelle ligne « usure: ».
   c.wearSeen=cmd.wearId or 0
   if t.restored and t.restoredSession==frame.session and t.restored[identity] then c.failState=2 end
  end
  if eligible(a,s,e,i) then
   if (a.kers or 0)>K.kersSeenMin then c.kersSeen=true end
   -- Relecture 1.42 (après correctifs) : overcut et réaction oubliés à chaque passage à l'emplacement (arrêt des règles,
   -- arrêt natif), pas seulement à l'arrêt demandé par la stratégie.
   local visitNow=e.pits.cars[i].visit
   if visitNow~=c.lastVisit then if c.lastVisit>=0 then c.shift=0; c.reaction=false end; c.lastVisit=visitNow end
   probe(t,e,a,c,i,now)
   -- Blocage qui use un pneu (mistakes.lua) : une ligne de journal par blocage.
   if (cmd.wearId or 0)~=c.wearSeen then
    c.wearSeen=cmd.wearId or 0
    local m=e.mistakes.cars[i]
    if (cmd.wearKm or 0)>0 and m then U.log(e.log,now,'INFO',string.format('usure: %s blocage, pneu %s +%.1f km (usure %.0f %%, asymetrie %.0f %%)',name(a),K.wheelNames[(cmd.wearWheel or 0)+1] or '?',cmd.wearKm,(m.lockWear or 0)*100,(m.lockAsym or 0)*100),i) end
   end
   local scale=outLap(t,e,frame,a,c,i,p,now)
   if scale<1 then cmd.levelScale=cmd.levelScale*scale end
   failure(t,e,frame,a,c,i,p,now,seed,racing,cmd)
   if active then
    -- Plan revu à chaque tour, à la sortie des stands (pneus neufs), et toutes les K.strategyRetry s tant que les
    -- données manquent (usure et carburant lus chaque seconde) ; jamais dans la voie des stands.
    local retry=not c.planned and now>=c.retryAt
    if ((a.lap or 0)~=c.lap or c.replan or retry) and not a.pit then
     c.replan=false; c.retryAt=now+K.strategyRetry
     -- Usure par tour, apprise sur chaque tour complet sans changement de pneus.
     local wear=wearOf(a)
     local sameLap=(a.lap or 0)==c.lap
     if not sameLap and c.lap>=0 and (a.lap or 0)==c.lap+1 and c.lapWear>=0 and wear>=c.lapWear and not a.pit then
      local rate=wear-c.lapWear
      if rate>0 and rate<K.strategyWearRateMax then c.wearRate=c.wearLaps>0 and c.wearRate+(rate-c.wearRate)*K.strategyWearAlpha or rate; c.wearLaps=c.wearLaps+1 end
     end
     if not sameLap or c.lapWear<0 then c.lap=a.lap or 0; c.lapWear=wear end
     local risk=s.persona.strategyRisk or 0.5
     local before=c.stops
     local left=plan(t,c,e,frame,a,p,i,risk)
     if c.planned and c.stops~=before and now-c.planLoggedAt>=K.strategyPlanLogGap then
      c.planLoggedAt=now
      U.log(e.log,now,'INFO',string.format('strategie: %s plan %d arret(s), prochain vers le tour %d (%s), risque %.0f %%',name(a),c.stops,c.stops>0 and c.nextLap or -1,c.limit=='tyres' and 'pneus' or 'carburant',risk*100),i)
      event(t,'plan',name(a),c.stops,c.stops>0 and c.nextLap or -1)
     end
     -- Undercut : un audacieux à quelques tours de son arrêt, collé au rival devant, s'arrête le premier.
     -- Beta 1.47 : aussi pour l'arrêt obligatoire encore dû, fenêtre ouverte (l'arrêt de la stratégie y compte).
     if p.strategyUndercut and c.planned and not c.reaction and not c.wanted and risk>=K.strategyBoldRisk
      and (c.stops>0 and c.nextLap-(a.lap or 0)<=K.strategyUndercutLaps or mandatoryDue(e,i,p)) then
      local row=e.perception.rows[i]
      local r=row and row.front>0 and row.neighbors[row.front]
      local b=r and frame.cars[r.index]
      if b and not b.pit and r.gap<=K.strategyRivalGap*max(K.strategyRivalMinSpeed,a.speed or 0) and abs((a.lap or 0)+(a.spline or 0)-(b.lap or 0)-(b.spline or 0))<K.strategyRivalLap then
       c.reaction=true; want(t,e,c,a,i,'undercut',now)
      end
     end
     if left>=0 and left<=K.strategyLastLaps then c.shift=0 end
    end
    -- Arrêt : relais au bout (pneus ou carburant), carburant critique, neutralisation favorable.
    if c.planned and not c.wanted and not a.pit then
     local stintLeft=c.nextLap>=0 and c.nextLap-(a.lap or 0) or math.huge
     -- Relecture 1.42 : arrêt non critique retenu tant que la fenêtre obligatoire n'est pas ouverte (il n'y compterait pas,
     -- d'où deux arrêts rapprochés).
     local pc=e.pits.cars[i]
     local hold=p.mandatoryStops>0 and e.pits.state=='pending' and pc.windowStops<p.mandatoryStops and not c.critical and not c.hardTyres
     -- Arrêt en cours de service ou contrôle d'après l'arrêt pas encore fait (pneus posés ? carburant ajouté ?) : pas de
     -- nouvelle demande, carburant critique compris (relecture 1.42 après correctifs : jugé après le contrôle).
     if c.serving or c.checkAfter then
     elseif c.critical then want(t,e,c,a,i,'fuel',now)
     elseif c.stops>0 and stintLeft<=0 then
      if not hold then want(t,e,c,a,i,c.limit,now)
      elseif not c.deferLogged then c.deferLogged=true; U.log(e.log,now,'INFO',string.format('strategie: %s arret retenu jusqu a l ouverture de la fenetre obligatoire',name(a)),i) end
     elseif neutralStart and not hold and c.stops>0 and stintLeft<=K.strategyNeutralLaps*(0.5+(s.persona.strategyRisk or 0.5)) and not inc.pitsClosed then want(t,e,c,a,i,'neutral',now) end
    end
   end
   -- Demande tenue jusqu'au passage à l'emplacement ; oubliée hors course ou stratégie coupée (sauf une panne).
   if c.wanted then
    local pc=e.pits.cars[i]
    -- Carburant demandé dans la voie avant l'emplacement (image précédente) : contrôle d'après l'arrêt.
    if a.pit and (cmd.fuelTarget or -1)>c.stopTarget then c.stopTarget=cmd.fuelTarget end
    -- Relecture 1.42 (après correctifs) : demande pas encore appelée devenue inutile (plan à zéro arrêt, neutralisation
    -- finie, cause abandonnée) : retirée tant que la voiture n'est pas dans la voie (jamais un appel déjà donné).
    local stale=not a.pit and not c.called and c.cause~='failure' and not c.critical
     and (c.cause=='neutral' and not inc.neutral or c.cause=='fuel' and c.noFuelStop or c.cause=='tyres' and c.noTyreStop or c.planned and c.stops==0)
    if pc.visit~=c.visit then
     c.wanted=false; c.called=false; c.shift=0; c.reaction=false; c.lap=-1; c.lapWear=-1; c.replan=true
     c.serving=true; c.servedVisit=pc.visit; c.stopCause=c.cause; c.deferLogged=false
    elseif not (active or c.failState==1 and racing) or inc.red then c.wanted=false; c.called=false
    elseif stale then
     c.wanted=false
     U.log(e.log,now,'INFO',string.format('strategie: %s arret retire (plus necessaire)',name(a)),i)
    elseif not a.pit and inc.pitsClosed and not c.critical then
     -- Stands fermés : la demande attend leur réouverture (sauf carburant critique).
    elseif a.pit or c.called or requested<K.pitConcurrent or c.cause=='failure' or c.critical then
     if not c.called and not a.pit then requested=requested+1 end
     c.called=true
     cmd.rulePit=true
    end
   end
   -- Relecture 1.42 : arrêt servi, pneus neufs posés par l'app (règles d'arrêt inactives, pits.lua ne les pose pas) ;
   -- après l'arrêt, contrôle que les pneus ont bien été changés et le carburant ajouté, sinon la cause est abandonnée
   -- (jamais un arrêt à chaque tour).
   if c.serving then
    if a.inPitBox and inc.red then c.stopRed=true end
    if a.inPitBox and p.pitTyres and (not inc.red or p.redFlagWork) and (cmd.pitCompound or -1)<0 and e.pits.cars[i].visit==c.servedVisit then cmd.pitCompound=Pits.compound(a,cmd,p) end
    if not a.pit then c.serving=false; c.checkAfter=true; c.checkAt=now+K.strategyCheckDelay end
   end
   if c.checkAfter and now>=c.checkAt and not a.pit then
    c.checkAfter=false
    local w=wearOf(a)
    if c.stopCause~='fuel' and not c.stopRed and not c.noTyreStop and t.wearTrust=='trusted' and c.stopWear>=K.strategyTyreCheckMin and w>=0 and w>c.stopWear-K.lockWearReset then
     c.noTyreStop=true; c.replan=true
     U.log(e.log,now,'INFO',string.format('strategie: %s pneus non changes a l arret (usure %.0f %%) : plus d arret pour les pneus',name(a),w*100),i)
    end
    -- Relecture 1.42 (après correctifs) : carburant jugé seulement pour un arrêt carburant, ou si l'app en a demandé plus
    -- qu'il n'y en avait (pas après une panne ou un arrêt pour les pneus sans ravitaillement voulu).
    if (c.stopCause=='fuel' or c.stopTarget>c.stopFuel+K.strategyFuelGainMin) and not c.noFuelStop and c.stopFuel>=0 and (a.fuel or -1)>=0 and a.fuel<c.stopFuel+K.strategyFuelGainMin then
     c.noFuelStop=true; c.replan=true
     U.log(e.log,now,'INFO',string.format('strategie: %s pas de carburant ajoute a l arret : plus d arret pour le carburant',name(a)),i)
    end
   end
   -- Pour pits.lua : tours du relais à ravitailler et avancement de l'arrêt prévu (arrêt obligatoire aligné).
   if active and c.planned and c.stops>0 and c.nextLap>=0 then
    local left=lapsLeft(e,frame,a,i)
    local total=(a.lap or 0)+max(0,left)
    if total>0 then cmd.stratPlanAt=c.nextLap/total end
    cmd.stratLaps=max(1,floor(min(left,c.stops>1 and math.ceil(max(1,left)/(c.stops)) or left)))
   end
  else
   if c.wanted then c.wanted=false end
   c.called=false; c.serving=false; c.checkAfter=false
  end
  cmd.stratCalled=c.called and c.wanted and not a.pit
 end
 -- Rivaux : à l'entrée d'un rival dans la voie des stands (image où il y entre).
 -- Jamais une voiture déjà dans la voie au départ (départ des stands), ni avant le premier tour.
 for j=1,frame.count do
  local b=frame.cars[j]; local cj=t.cars[j]
  if active and p.strategyUndercut and b.pit and not cj.rivalLane and b.valid and (b.lap or 0)>=1 then rivals(t,e,frame,j,now,p) end
  cj.rivalLane=b.pit==true
 end
 -- Tours de sortie du départ des stands (essais, qualifications) : une seule ligne.
 if not t.outSummary and now-t.resetAt>=K.outLapSummaryTime then
  t.outSummary=true
  if t.outCount>0 then U.log(e.log,now,'INFO',string.format('tour de sortie: %d IA pneus a chauffer au depart des stands (niveau -%.0f %%)',t.outCount,p.outLapLevelPct),-1) end
 end
end
-- Point de reprise (rechargement de l'app en pleine course) : pannes faites ou en cours, par voiture.
function M.serialize(t,session)
 local rows={tostring(session)}
 for i=1,K.maxCars do local c=t.cars[i]; if c.identity~='' and c.failState>0 and c.identity:match('^[%w_%-]+$') then rows[#rows+1]=c.identity..','..c.failState end end
 if #rows==1 then return '' end
 return table.concat(rows,'\n')
end
-- Une panne en cours au rechargement est comptée comme faite : jamais une seconde panne pour la même IA.
function M.restore(t,text,session)
 if type(text)~='string' or #text>K.maxZoneBytes or tonumber(text:match('^(%d+)'))~=session then return end
 t.restored={}; t.restoredSession=session
 for identity,state in text:gmatch('\n([%w_%-]+),(%d+)') do t.restored[identity]=tonumber(state) end
 for i=1,K.maxCars do local c=t.cars[i]; if c.identity~='' and t.restored[c.identity] then c.failState=2 end end
end
return M
