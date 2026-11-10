-- Arrêts réglementaires en course : décisions pures. Demande et pneus écrits par applier, météo comprise.
local U=require('src/util')
local K=require('src/config').K
local M={}
local function clear(c)
 c.stops=0; c.windowStops=0; c.boxed=false; c.boxSince=0; c.visit=0; c.wanted=false; c.redVisit=false; c.pendingCompound=nil; c.pendingUntil=nil; c.wasPit=nil
 c.fuelLap=-1; c.fuelAt=-1; c.lapAt=0; c.pitLap=false; c.perLap=0; c.lapTime=0; c.repairVisit=-1; c.repairTime=0; c.towedAt=nil
 -- Relecture 1.42 (après correctifs) : passage de pénalité en cours à l'emplacement, arrêt des règles retenu par la limite
 -- d'appels (lu par sanctions.lua : la pénalité attend cet arrêt).
 c.passBox=false; c.deferred=false
 -- Beta 1.58 (course du pilote, fn_imola, 10 novembre) : composés secs déjà roulés en course (règle F1 des deux composés),
 -- passages servis sans arrêt compté pendant une même demande d'arrêt obligatoire (borne : jamais redemandée en boucle),
 -- premier passage à l'emplacement de ce passage dans la voie des stands (un seul service par passage), dépannage de l'app.
 c.usedDry={}; c.usedCount=0; c.requestServices=0; c.requestAbandoned=false; c.laneVisit=nil; c.laneStopped=false; c.reboxLogged=false; c.appTowAt=nil
end
function M.new()
 local t={cars={},entrySpline=-1,playerNotice='',playerNoticeUntil=-math.huge,playerNoticeFrom='',playerNoticeTo='',hintFor=-2,hintTyre='',hintOthers={},opened=false,openedAt=-math.huge,justClosed=false,stopAwait=false,wasStarted=false,progress=-1,position=-1,open=-1,close=-1,csp=false,state='off',done=0,total=0,restored={},models={},restoredSession=-1,dirty=false,wetRace=false,waived=false}
 for i=1,K.maxCars do local c={identity='',lastStop=0}; clear(c); t.cars[i]=c end
 return t
end
function M.reset(t,now)
 for i=1,K.maxCars do local c=t.cars[i]; clear(c); c.identity=''; c.lastStop=now end
 t.opened=false; t.openedAt=-math.huge; t.justClosed=false; t.state='off'; t.dirty=true; t.wetRace=false; t.waived=false
 -- Relecture 1.52 : pénalité du joueur en attente du composé (engine.lua) et départ vu, oubliés avec la session.
 t.stopAwait=false; t.wasStarted=false
 t.entrySpline=-1; t.playerNotice=''; t.playerNoticeUntil=-math.huge; t.hintFor=-2
 -- Beta 1.59 : rappel et avis par tour du joueur oubliés avec la session.
 t.remindLap=nil; t.remindAt=nil; t.hintLap=nil; t.hintAt=nil
end
function M.rebase(t,amount)
 -- Relecture 1.52 : dépannage récent (towedAt) décalé aussi.
 for i=1,K.maxCars do local c=t.cars[i]; c.boxSince=c.boxSince-amount; c.lastStop=c.lastStop-amount; c.lapAt=c.lapAt-amount; if c.pendingUntil then c.pendingUntil=c.pendingUntil-amount end; if c.towedAt then c.towedAt=c.towedAt-amount end end
 if t.playerNoticeUntil>-math.huge then t.playerNoticeUntil=t.playerNoticeUntil-amount end
 if t.openedAt>-math.huge then t.openedAt=t.openedAt-amount end
 if t.remindAt then t.remindAt=t.remindAt-amount end; if t.hintAt then t.hintAt=t.hintAt-amount end
end
-- Avancement de la course de 0 à 1 : tours du leader, sinon temps d'une course chronométrée ; -1 inconnu.
function M.progress(frame)
 if frame.sessionLaps>0 and not frame.timedRace then return frame.leaderLaps/frame.sessionLaps end
 if frame.sessionMinutes>0 then return U.clamp(1-frame.left/(frame.sessionMinutes*60),0,1) end
 return -1
end
-- Pneus posés à l'arrêt : la météo prime si elle exige un autre pneu (pluie, retour au sec) ; sinon un autre
-- composé sec (F1), sinon un train neuf du même composé.
-- Beta 1.58 : used (composés secs déjà roulés en course), usedCount (leur nombre) : tant que moins de deux composés secs
-- différents ont été roulés, un composé pas encore roulé d'abord (jamais un retour au composé de départ après un
-- dépannage) ; ensuite, comme avant : un autre que celui monté.
function M.compound(a,cmd,p,used,usedCount)
 -- Relecture 1.42 (après correctifs) : météo non gérée par l'app et piste mouillée : aucun pneu imposé (choix d'AC).
 if not cmd.weatherManaged and cmd.weatherRain then return -1 end
 if cmd.weatherManaged and cmd.weatherCompound>=0 and (cmd.weatherRain or cmd.weatherCompound~=a.compoundIndex) then return cmd.weatherCompound end
 if not a.tyresKnown or a.compoundIndex==nil then return -1 end
 if p.pitCompoundChange and a.dryCompounds then
  if used and (usedCount or 0)<2 then for index=0,K.maxTyreCompounds-1 do if a.dryCompounds[index] and index~=a.compoundIndex and not used[index] then return index end end end
  for index=0,K.maxTyreCompounds-1 do if a.dryCompounds[index] and index~=a.compoundIndex then return index end end
 end
 return a.compoundIndex
end
-- Temps de réparation (Beta 1.20) : quelques secondes, puis selon la carrosserie, la suspension la plus touchée et
-- l'usure du moteur, au plus K.repairMax ; 0 sans dégât notable.
function M.repairTime(a)
 local body,suspension,engine=a.damageBody or 0,a.damageSuspension or 0,a.engineLife or K.engineLifeNew
 if body<K.repairBodyMin and suspension<K.repairSuspensionMin and engine>=K.repairEngineMin then return 0 end
 return math.min(K.repairMax,K.repairBase+body*K.repairBodyRate+suspension*K.repairSuspensionRate+(K.engineLifeNew-engine)/K.engineLifeNew*K.repairEngineTime)
end
-- Beta 1.49 : nom court d'un composé (journal, avis du joueur) ; son numéro sans nom connu.
local function tyreShort(a,index) return index~=nil and (a.tyreNames and a.tyreNames[index] or tostring(index)) or '?' end
local function notice(t,kind,from,to,untilAt,fromIndex,toIndex) t.playerNotice=kind; t.playerNoticeFrom=from; t.playerNoticeTo=to; t.playerNoticeUntil=untilAt; t.playerNoticeFromIndex=fromIndex or -1; t.playerNoticeToIndex=toIndex or -1 end
-- closed : entrée des stands fermée (neutralisation, règles GT et Endurance) : aucune IA appelée, un arrêt n'y compte pas.
function M.update(t,frame,commands,p,profile,now,seed,announce,red,dq,closed)
 local active=profile=='C' and (p.mandatoryStops>0 or p.maxStintMin>0 or p.minPitTime>0)
 local progress=M.progress(frame); t.progress=progress
 -- Fenêtre déclarée par CSP (serveur, mode de course) prioritaire ; sinon celle des règles, en part de course.
 local csp=frame.pitWindowStart>0 and frame.pitWindowEnd>frame.pitWindowStart
 local position,opening,closing
 if csp then position=frame.simTime; opening=frame.pitWindowStart; closing=frame.pitWindowEnd
 else position=progress; opening=p.pitWindowOpenPct/100; closing=p.pitWindowClosePct/100 end
 t.csp=csp; t.position=position; t.open=opening; t.close=closing
 -- F1 : deux composés secs obligatoires, sauf course mouillée (pneus pluie ou intermédiaires montés).
 local waived=p.pitCompoundChange and t.wetRace
 if waived and not t.waived and active and p.mandatoryStops>0 then
  if t.note then t.note('INFO','arret obligatoire leve: course mouillee',-1) end
  if p.pitMessage and announce then announce('pitWaived') end
 end
 t.waived=waived
 local mandatory=active and p.mandatoryStops>0 and position>=0 and not waived
 local before=t.state
 t.state=not mandatory and 'off' or position<opening and 'pending' or position<=closing and 'open' or 'closed'
 t.justClosed=before=='open' and t.state=='closed'
 if t.state=='open' and not t.opened then
  t.opened=true; t.openedAt=now
  if t.note then t.note('INFO',csp and 'fenetre d arret ouverte (CSP)' or string.format('fenetre d arret ouverte: %.0f a %.0f %% de la course',opening*100,closing*100),-1) end
  if p.pitMessage and announce then if csp then announce('pitOpenCsp') else announce('pitOpen',opening*100,closing*100) end end
 end
 t.done=0; t.total=0
 -- Relecture 1.52 : relais maximal compté depuis le départ (front montant de frame.started), jamais depuis l'attente sur
 -- la grille.
 local started=frame.started==true
 if started and not t.wasStarted then for i=1,K.maxCars do t.cars[i].lastStop=now end end
 t.wasStarted=started
 -- Appels simultanés limités : les IA déjà appelées gardent leur place, les nouvelles attendent.
 local requested=0
 -- Relecture 1.42 : la stratégie (image précédente, cmd.stratCalled) partage la même limite d'appels. Relecture 1.52 :
 -- l'appel d'une IA lente et endommagée (engine.lua, cmd.slowCalled) aussi.
 for i=1,frame.count do local a=frame.cars[i]; if (t.cars[i].wanted and t.cars[i].identity==(a.identity or a.id) or commands[i].stratCalled or commands[i].sanCalled or commands[i].slowCalled) and not a.pit then requested=requested+1 end end
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]; local cmd=commands[i]
  local identity=a.identity or a.id
  if c.identity~=identity then
   clear(c); c.identity=identity; c.lastStop=now; c.boxed=a.inPitBox==true; c.boxSince=now
   c.windowStops=frame.session==t.restoredSession and t.restored[identity] or 0
  end
  -- Dépannage demandé par l'app (image précédente) ou saut de position : l'arrivée à l'emplacement dans les
  -- K.towWindow s suivantes n'est pas un arrêt (AC peut signaler l'emplacement une image après le saut).
  if cmd.recover or a.teleport then c.towedAt=now end
  -- Beta 1.58 : dépannage de l'app (jamais compté comme l'arrêt demandé, contrairement à un déplacement par AC ou CSP).
  if cmd.recover then c.appTowAt=now end
  -- Beta 1.58 : composé sec roulé en piste, course lancée (règle F1 : un composé différent de ceux déjà roulés).
  if frame.started and not a.pit and a.compoundIndex~=nil and a.dryCompounds and a.dryCompounds[a.compoundIndex] and not c.usedDry[a.compoundIndex] then c.usedDry[a.compoundIndex]=true; c.usedCount=c.usedCount+1 end
  -- Beta 1.58 : un passage dans la voie des stands finit à sa sortie (un nouveau service redevient possible).
  if not a.pit then c.laneVisit=nil; c.laneStopped=false end
  -- Beta 1.59 (relecture de la 1.58) : passage servi seulement une fois la voiture vraiment arrêtée à son emplacement.
  if a.pit and a.inPitBox and (a.kmh or 0)<=K.tyreStopSpeed and c.laneVisit~=nil then c.laneStopped=true end
  local towed=c.towedAt~=nil and now>=c.towedAt and now-c.towedAt<=K.towWindow
  -- Un passage à l'emplacement compte une fois, quelle qu'en soit la raison (météo comprise).
  -- Passage de pénalité d'une IA (drive-through, stop-and-go ; cmd.penaltyPass mis par sanctions.lua, Beta 1.42) : ni
  -- visite (la stratégie et les réparations la prendraient pour leur arrêt), ni arrêt compté, ni arrêt obligatoire.
  local pass=cmd.penaltyPass==true
  -- Beta 1.48 : passage aux stands commencé sous drapeau rouge (mémorisé jusqu'à la sortie de la voie des stands) :
  -- une voiture arrivée à son emplacement après la reprise reste sous la règle du drapeau rouge.
  if a.pit and red then c.redVisit=true elseif not a.pit then c.redVisit=false end
  local underRed=red or c.redVisit==true
  -- Beta 1.49 : entrée de la voie des stands relevée au premier passage d'une voiture venue de la piste (rappel du
  -- joueur avant l'entrée) ; une voiture déjà aux stands à la première image ne compte pas.
  if a.pit and c.wasPit==false and t.entrySpline<0 and a.splineValid and not a.safetyCar and (a.kmh or 0)>=K.pitEntryMinKmh then t.entrySpline=a.spline end
  c.wasPit=a.pit==true
  if a.inPitBox and not c.boxed and pass then
   c.boxed=true; c.boxSince=now; c.passBox=true
   if t.note and not a.player then t.note('INFO',string.format('passage de penalite a l emplacement: %s, non compte comme arret',a.name),i) end
  elseif a.inPitBox and not c.boxed then
   c.boxed=true; c.boxSince=now; c.visit=c.visit+1
   -- Beta 1.58 : deuxième arrivée à l'emplacement sans être sortie de la voie des stands (demande d'arrêt d'AC restée
   -- active, déplacement) : ni arrêt compté, ni nouveau service (pneus, réparations) ; une ligne par voiture.
   local rebox=c.laneVisit~=nil
   -- Beta 1.59 (relecture de la 1.58) : emplacement perdu un instant en y roulant encore (jamais arrêtée depuis l'entrée
   -- de la voie) : même arrivée, service encore permis, jamais un arrêt compté deux fois.
   local flicker=rebox and not c.laneStopped
   if flicker then c.laneVisit=c.visit end
   if not rebox then c.laneVisit=c.visit end
   if (a.kmh or 0)<=K.tyreStopSpeed then c.laneStopped=true end
   local appTowed=c.appTowAt~=nil and now>=c.appTowAt and now-c.appTowAt<=K.towWindow
   if t.note and active and not a.player then t.note('DEBUG',string.format('arrivee a l emplacement: %s, passage %d, demande d arret AC %s, demande de l app %s, deplacee %s',a.name,c.visit,a.requestingPit and 'oui' or 'non',c.wanted and 'oui' or 'non',towed and 'oui' or 'non'),i) end
   if rebox and not flicker and not c.reboxLogged and t.note and not a.player then c.reboxLogged=true; t.note('INFO',string.format('emplacement de nouveau sans sortie de la voie des stands: %s, aucun nouveau service',a.name),i) end
   -- Voiture ramenée à son stand par l'app (dépannage, Beta 1.24) ou voiture de sécurité : aucun arrêt compté ; sous
   -- drapeau rouge, toutes les voitures rentrent aux stands : compté comme avant.
   -- Beta 1.58 (course du pilote, fn_imola) : une IA dont l'arrêt est demandé, ramenée à son emplacement (déplacée par
   -- AC ou CSP, dépannée), y est servie (pneus, carburant, réparations) : l'arrêt demandé compte. Avant, il n'était jamais
   -- compté, la demande restait et l'IA était servie en boucle jusqu'à l'arrivée. Sans demande, un dépannage ne compte pas.
   local countedNow=false
   if not rebox and not a.safetyCar and (not towed or red or c.wanted and not appTowed) then
    c.stops=c.stops+1
    -- Arrêt sous drapeau rouge : compté seulement si les règles y permettent un changement de pneus (F1), même avant
    -- l'ouverture de la fenêtre (Beta 1.48 : la F1 n'en a pas) ; jamais sinon. Joueur et changement de composé
    -- obligatoire : compté à la sortie de l'emplacement, seulement si le composé a changé. Relecture 1.52 : jamais après
    -- la fermeture de la fenêtre.
    local counts=mandatory and position<=closing and (underRed and p.redFlagWork or not underRed and position>=opening) and not closed and not (dq and dq[i])
    c.pendingCompound=nil; c.pendingUntil=nil
    if counts and a.player and p.pitCompoundChange and a.compoundIndex~=nil then c.pendingCompound=a.compoundIndex
    elseif counts then c.windowStops=c.windowStops+1; t.dirty=true end
    countedNow=counts
    if t.note and active then t.note('INFO',string.format('arret aux stands%s: %d (dont %d dans la fenetre)%s, %s',a.player and ' du joueur' or '',c.stops,c.windowStops,c.pendingCompound and ', compte au changement de compose (arrivee en '..tyreShort(a,c.pendingCompound)..')' or '',a.name),i) end
   end
   -- Beta 1.58 : demande d'arrêt obligatoire servie sans compter (dépannage de l'app, règles fermées…) : comptée pour la
   -- borne, seulement si du travail y est fait (pneus ; jamais un garage sous drapeau rouge sans travail).
   if c.wanted and not rebox and not countedNow and not a.player and p.pitTyres and (not underRed or p.redFlagWork) then c.requestServices=c.requestServices+1 end
  end
  -- Relecture 1.42 (après correctifs) : un passage de pénalité ne remet pas le relais à zéro (relais maximal).
 if not a.inPitBox and c.boxed then
  c.boxed=false; if not c.passBox then c.lastStop=now end; c.passBox=false
 end
 -- Beta 1.49 (Monza, 5 novembre, 09:55) : composé du joueur suivi de l'arrivée à l'emplacement jusqu'à la sortie de la
 -- voie des stands plus K.pitCompoundGrace s (AC peut mettre le composé à jour après la sortie de l'emplacement) ;
 -- compté dès qu'il diffère du composé d'arrivée, refusé seulement à la fin de ce délai ; composés nommés au journal,
 -- avis du joueur sur l'overlay (arrêt validé, ou même composé).
 if c.pendingCompound~=nil then
  local changed=a.compoundIndex~=nil and a.compoundIndex~=c.pendingCompound
  if changed then
   c.windowStops=c.windowStops+1; t.dirty=true
   local from,to=tyreShort(a,c.pendingCompound),tyreShort(a,a.compoundIndex)
   if t.note and active then t.note('INFO',string.format('arret aux stands du joueur compte: compose change (%s -> %s, %d dans la fenetre)',from,to,c.windowStops),i) end
   notice(t,'counted',from,to,now+K.pitNoticeCounted,c.pendingCompound,a.compoundIndex)
   if announce then announce('pitValidated',c.pendingCompound,a.compoundIndex) end
   c.pendingCompound=nil; c.pendingUntil=nil
  elseif a.pit or a.inPitBox or c.boxed then c.pendingUntil=nil
  elseif not c.pendingUntil then c.pendingUntil=now+K.pitCompoundGrace
  elseif now>=c.pendingUntil then
   local from=tyreShort(a,c.pendingCompound)
   if t.note and active then t.note('INFO',string.format('arret aux stands du joueur non compte: compose inchange (%s -> %s)',from,from),i) end
   notice(t,'same',from,from,now+K.pitNoticeSame,c.pendingCompound,c.pendingCompound)
   if announce then announce('pitNotCounted',c.pendingCompound,c.pendingCompound) end
   c.pendingCompound=nil; c.pendingUntil=nil
  end
 end
  cmd.rulePit=false; cmd.pitHold=false; cmd.pitCompound=-1; cmd.pitVisit=c.visit; cmd.pitRepair=false
  -- Beta 1.58 : servie dans ce passage de la voie et sortie de l'emplacement (la demande d'arrêt d'AC peut y être levée).
  local served=c.laneVisit~=nil and c.laneStopped and a.pit and not a.inPitBox
  cmd.laneServed=served
  local first=c.laneVisit==nil or c.laneVisit==c.visit
  -- IA disqualifiée (garée à son stand), arrivée ou hors course : ni comptée ni appelée, aucune place d'appel retenue.
  if active and a.valid and a.control and not a.player and not a.finished and not a.safetyCar and not (dq and dq[i]) then
   local want=false
   if mandatory then
    t.total=t.total+1
    if c.windowStops>=p.mandatoryStops then t.done=t.done+1
    -- Relecture 1.52 : appel seulement fenêtre ouverte (jamais une fois fermée) ; un seul arrêt obligatoire depuis la
    -- 1.51, placé dans la fenêtre selon la graine.
    elseif t.state=='open' then
     local span=closing-opening
     want=position>=opening+span*K.pitSpread*U.unit(seed,i,K.pitSalt)
     -- Beta 1.42 (stratégie individuelle) : arrêt obligatoire aligné sur l'arrêt prévu par le stratège s'il tombe plus
     -- tard dans la fenêtre (avancement relu de l'image précédente) ; jamais au-delà de la fin de la fenêtre (moins la
     -- marge de la stratégie).
     local planAt=cmd.stratPlanAt or -1
     if want and not csp and not c.wanted and planAt>position and planAt<closing-span*K.strategyWindowMargin then want=false end
    end
   end
   -- Beta 1.58 : borne propre à la demande d'arrêt obligatoire (jamais la fin de relais) : servie K.pitRequestServiceMax
   -- fois sans être comptée, elle est abandonnée pour la session (une ligne d'avertissement), avant la limite d'appels
   -- (aucune place d'appel retenue, aucune pénalité retardée).
   if want and c.requestServices>=K.pitRequestServiceMax and not a.inPitBox then
    if not c.requestAbandoned and t.note then t.note('WARN',string.format('arret demande abandonne: %s, servie %d fois sans arret compte',a.name,c.requestServices),i) end
    c.requestAbandoned=true
   end
   if c.requestAbandoned then want=false end
   if p.maxStintMin>0 and not c.boxed and now-c.lastStop>=p.maxStintMin*60 and (progress<0 or progress<K.pitLastStint) then want=true end
   if closed and not a.pit then want=false end
   -- Beta 1.58 : servie dans ce passage de la voie et sortie de l'emplacement : plus d'arrêt demandé avant la sortie de la
   -- voie (sinon AC la ramène à l'emplacement en boucle) ; redemandé en piste si l'arrêt n'a pas compté.
   if served then want=false end
   -- Au plus quelques IA appelées en même temps hors de la voie des stands : pas de bouchon à l'entrée.
   c.deferred=false
   if want and not a.pit and not c.wanted then if requested<K.pitConcurrent then requested=requested+1 else want=false; c.deferred=true end end
   if want and not c.wanted and t.note then t.note('INFO',string.format('arret demande: %s, %s',mandatory and c.windowStops<p.mandatoryStops and 'obligatoire' or 'fin de relais',a.name),i) end
   c.wanted=want
   if not want and not served then c.requestServices=0 end
   cmd.rulePit=want
   cmd.pitHold=a.inPitBox and p.minPitTime>0 and now-c.boxSince<p.minPitTime
   if a.inPitBox and first and p.pitTyres and (not underRed or p.redFlagWork) then cmd.pitCompound=M.compound(a,cmd,p,c.usedDry,c.usedCount) end
  else c.wanted=false; c.deferred=false end
  -- Réparations (Beta 1.20) : en course, à chaque passage d'une IA endommagée à son emplacement (arrêt des règles ou
  -- arrêt natif) ; elle y reste le temps de la réparation. Sous drapeau rouge, seulement si les règles y permettent le
  -- travail (F1), comme les pneus.
  if profile=='C' and p.pitRepair and not pass and first and a.inPitBox and a.valid and a.control and not a.player and not a.safetyCar and (not underRed or p.redFlagWork) and not (dq and dq[i]) then
   if c.repairVisit~=c.visit then c.repairVisit=c.visit; c.repairTime=M.repairTime(a) end
   if c.repairTime>0 then cmd.pitRepair=true; if now-c.boxSince<c.repairTime then cmd.pitHold=true end end
  end
 end
end
-- Carburant (Beta 1.12). Consommation et durée du tour apprises sur chaque tour complet sans passage aux stands ;
-- gardées par modèle et par circuit pour les sessions suivantes (plein du départ) ; sinon l'estimation d'AC.
-- Relecture 1.52 : clé du modèle (circuit|voiture) gardée par voiture, refaite seulement quand l'un ou l'autre change
-- (jamais une chaîne par IA et par image).
local function modelKey(c,frame,a)
 if c.keyTrack~=frame.track or c.keyId~=a.id then c.keyTrack=frame.track; c.keyId=a.id; c.key=frame.track..'|'..a.id end
 return c.key
end
-- Relecture 1.52 : durée du tour apprise quel que soit le réglage du carburant (fuel faux : carburant laissé à AC,
-- consommation coupée ou inconnue) ; la consommation seulement avec fuel.
local function learn(t,c,a,frame,now,fuel)
 if a.lap~=c.fuelLap then
  if c.fuelLap>=0 and a.lap==c.fuelLap+1 and not c.pitLap and not a.pit then
   if fuel and c.fuelAt>0 then
    local used=c.fuelAt-a.fuel
    if used>0 and used<a.maxFuel*K.fuelLapShare then c.perLap=c.perLap>0 and c.perLap+(used-c.perLap)*K.fuelAlpha or used end
   end
   local lap=now-c.lapAt
   if lap>=K.fuelLapTimeMin then c.lapTime=c.lapTime>0 and c.lapTime+(lap-c.lapTime)*K.fuelAlpha or lap end
   if fuel and c.perLap>0 and c.lapTime>0 then
    local key=modelKey(c,frame,a); local model=t.models[key]
    if not model then model={}; t.models[key]=model end
    model.perLap=c.perLap; model.lapTime=c.lapTime
   end
  end
  -- Relecture 1.42 : un tour neutralisé (voiture de sécurité, VSC, FCY, drapeau rouge ; t.neutral mis par strategy.lua)
  -- n'apprend rien : sa consommation ferait arriver l'arrêt trop tard ensuite.
  c.fuelLap=a.lap; c.fuelAt=fuel and a.fuel or -1; c.lapAt=now; c.pitLap=a.pit==true or t.neutral==true
 elseif a.pit or t.neutral then c.pitLap=true end
end
-- Tours restants de la voiture : course aux tours, sinon temps restant au rythme appris (+1 tour : la ligne après la
-- fin du temps) ; -1 inconnu.
local function lapsLeft(frame,a,lapTime)
 if frame.sessionLaps>0 and not frame.timedRace then return math.max(0,frame.sessionLaps-a.lap) end
 if frame.sessionMinutes>0 and lapTime>0 then return math.ceil(frame.left/lapTime)+1 end
 return -1
end
M.lapsLeft=lapsLeft
-- Ravitaillement : tours jusqu'au prochain arrêt prévu (relais maximal), sinon jusqu'à l'arrivée. Relecture 1.52 : un
-- seul arrêt obligatoire depuis la 1.51, aucune tranche suivante à viser.
local function stintLaps(p,lapTime,left)
 local laps=left
 if p.maxStintMin>0 and lapTime>0 then laps=math.min(laps,math.max(1,math.floor(p.maxStintMin*60/lapTime))) end
 return laps
end
-- Décisions : cmd.fuelSet (plein de course avant le départ, sans ravitaillement prévu), cmd.fuelTarget (carburant
-- demandé à un arrêt forcé : règles, météo, drapeau rouge) et cmd.fuelLaps (tours avant un arrêt natif de secours).
-- Sous drapeau rouge, rien n'est ajouté sauf pour finir (ravitaillement interdit en F1 et en WEC).
function M.fuel(t,frame,commands,p,profile,now,red)
 local mode=p.pitFuel
 local learning=profile=='C' and not frame.online and not frame.replay
 local on=learning and mode~='ac' and frame.fuelRate>0
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]; local cmd=commands[i]
  cmd.fuelTarget=-1; cmd.fuelLaps=0; cmd.fuelSet=-1
  local eligible=learning and a.valid and a.control and not a.player and not a.safetyCar and not a.finished
  local fuel=eligible and (a.fuel or -1)>=0 and (a.maxFuel or -1)>0
  -- Relecture 1.52 : durée du tour apprise pour toute IA en course (tours restants d'une course chronométrée, ici et
  -- dans strategy.lua), même carburant laissé à AC ou consommation coupée.
  if eligible and not (on and fuel) then learn(t,c,a,frame,now,false) end
  if on and fuel then
   learn(t,c,a,frame,now,true)
   local model=t.models[modelKey(c,frame,a)]
   local perLap=c.perLap>0 and c.perLap or model and model.perLap or a.fuelPerLap or 0
   local lapTime=c.lapTime>0 and c.lapTime or model and model.lapTime or 0
   local left=lapsLeft(frame,a,lapTime)
   if perLap>0 and left>=0 then
    local reserve=perLap*K.fuelReserveLaps
    if not frame.started then
     if mode=='plan' then
      local full=math.min(a.maxFuel,left*perLap*K.fuelMargin+reserve)
      if full>a.fuel+K.fuelStep then cmd.fuelSet=full end
     end
    elseif cmd.rulePit or cmd.weatherManaged and cmd.weatherPit then
     local laps=left
     if mode=='refuel' and not red then laps=stintLaps(p,lapTime,left) end
     -- Beta 1.42 : arrêt du stratège, carburant pour son relais suivant (marge réglée comprise), au plus jusqu'à l'arrivée.
     if mode=='refuel' and not red and (cmd.stratLaps or 0)>0 then laps=math.min(left,cmd.stratLaps+math.ceil(p.strategyFuelMarginLaps or 0)) end
     local target=U.clamp(laps*perLap*K.fuelMargin+reserve,a.fuel,a.maxFuel)
     cmd.fuelTarget=target; cmd.fuelLaps=math.max(1,math.floor((target-reserve)/perLap))
    end
   end
  end
 end
end
-- Arrêts obligatoires déjà faits, conservés à travers un rechargement de l'app au cours de la même session.
function M.serialize(t,session)
 local rows={tostring(session)}
 for i=1,K.maxCars do local c=t.cars[i]; if c.identity~='' and c.windowStops>0 and c.identity:match('^[%w_%-]+$') then rows[#rows+1]=c.identity..','..c.windowStops end end
 return table.concat(rows,'\n')
end
-- Redémarrage de la session : les arrêts mémorisés avant le rechargement ne valent plus.
function M.forget(t) t.restored={}; t.restoredSession=-1 end
function M.restore(t,text,session)
 if type(text)~='string' or #text>K.maxZoneBytes or tonumber(text:match('^(%d+)'))~=session then return end
 t.restoredSession=session
 -- Relecture 1.52 : un seul arrêt obligatoire depuis la 1.51.
 for identity,stops in text:gmatch('\n([%w_%-]+),(%d+)') do t.restored[identity]=math.min(1,tonumber(stops)) end
end
return M
