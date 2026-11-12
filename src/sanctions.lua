-- Sanctions des IA (Beta 1.42, demande du pilote) : mêmes règles que pour le joueur. Limites de piste (tour invalidé en
-- essais et qualifications, avertissements puis pénalité de temps en course), virage coupé avec gain (coupure des gaz
-- progressive), faux départ, excès de vitesse et ligne de sortie des stands (drive-through, stop-and-go ou pénalité de
-- temps), contresens (drapeau noir), pénalité non purgée (drapeau noir après sanServeLaps tours, ou ajoutée au résultat
-- à l'arrivée), place à rendre après un dépassement hors piste (pénalité de temps sinon).
-- Décisions pures ; écritures par les commandes (cmd.throttleLimit, yellowLimit, rulePit, pitHold, pitCompound,
-- pitRepair, scPark avec parkReason 'dq'). AC ne permet pas de modifier son classement ni ses pénalités pour une IA :
-- pénalités de temps et pénalités non purgées vont au classement corrigé de l'app (overlay, Diagnostic, journal).
-- Jamais le joueur (AC le sanctionne lui-même ; les pénalités sous drapeau de l'app sont inchangées), jamais la voiture
-- de sécurité, jamais en ligne ni en relecture (le moteur ne tourne pas).
-- Beta 1.56 (décision du pilote), trois options coupées par défaut : vos limites de piste gérées par l'app (mêmes règles
-- que les IA, sans la règle des zones ignorées ; jamais votre voiture pilotée : du temps au classement corrigé ou la
-- coupure des gaz native d'AC), pénalités de limites de piste croissantes (IA et joueur), rapport de course en CSV.
local U=require('src/util')
local C=require('src/config')
local L=require('src/lang')
local Delta=require('src/delta')
local Incidents=require('src/incidents')
local Penalties=require('src/penalties')
local K=C.K
local abs,max,min,floor=math.abs,math.max,math.min,math.floor
local M={}
local function car()
 return {identity='',lastLap=-1,
  -- Sortie des limites en cours : durée, point et instant de départ, vitesse la plus basse, incident, déjà comptée.
  outFor=0,outFrom=0,outAt=0,outMin=0,outIncident=false,outCounted=false,outBin=0,lastStrikeAt=-math.huge,strikes=0,
  -- Essais et qualifications : tour invalidé (numéro), tour suivant aussi (dernier secteur), nombre.
  invalidLap=-1,invalidNext=-1,invalid=0,
  -- Coupure des gaz à purger (s de ligne droite), limite en cours, attente sans occasion sûre.
  cutLeft=0,cutLimit=1,cutWait=0,cutSeconds=0,
  -- Pénalité à purger aux stands ('drive', 'stopgo'), raison, tours écoulés, purge possible pendant ce tour.
  pending='',pendingReason='',pendingLaps=0,could=false,asked=false,entry=false,boxAt=-1,held=false,
  -- Classement corrigé : temps ajouté, pénalités, drapeau noir, arrivée.
  time=0,count=0,dq=false,finishAt=-1,finishLaps=0,finishPos=0,corrected=0,
  wrongFor=0,lastSpline=-1,rejoinAt=-math.huge,cutBlocked=false,outApp=false,issueLap=-1,askedLap=false,askedLaps=0,laneOff=0,exitSpline=-1,lineHits={},
  laneFor=0,speedFor=0,speedDone=false,wasPit=false,noOutUntil=-math.huge,noOutSet=false,
  -- Place à rendre : voiture à laisser repasser, échéance, levée de pied ; voitures devant au début de la sortie.
  owedTo=0,owedUntil=0,owedFrom=-1,owedAt=0,owedOther=0,watchUntil=-math.huge,watch={},
  -- Beta 1.56 : pénalités de limites de piste de temps données (rang de la récidive) et leur total ; coupure des gaz
  -- demandée à AC pour vos limites de piste (décision, instant) ; compteurs du rapport de course (jamais lus par une
  -- décision) : avertissements, coupures des gaz, drive-through, stop-and-go, purgées, places dues et rendues, temps non
  -- purgé, drapeau noir ; nom et modèle relevés pendant la course.
  trackN=0,trackTime=0,cutRequest=0,cutAt=0,
  -- Beta 1.60 : collisions (src/blame.lua) : contacts en tort, avertissements, coupure des gaz demandée à AC (vous).
  contacts=0,contactWarn=0,contactRequest=0,contactAt=0,lastX=0,lastZ=0,
  -- Beta 1.62 (décision 5 du pilote) : drapeaux bleus ignorés de suite (remis à zéro quand elle cède), drapeaux de
  -- l'épisode en cours déjà comptés.
  blueN=0,blueEpN=0,blueBy=0,blueDone=false,
  rWarn=0,rCut=0,rDrive=0,rStopgo=0,rServed=0,rOwed=0,rGiven=0,rUnserved=0,rBlack='',rName='',rModel=''}
end
local function clearCar(c,identity)
 local watch,hits=c.watch,c.lineHits
 for k,v in pairs(car()) do if k~='watch' and k~='lineHits' then c[k]=v end end
 for j in pairs(watch) do watch[j]=nil end
 for b in pairs(hits) do hits[b]=nil end
 c.identity=identity or ''
end
function M.new()
 local t={rows={},events={},classRows={},cars={},dirty=false,lastAt=nil,order=0,classDirty=false,line={},lineIgnored={},lineBins=0,
  rel={index=0,long=0,lat=0,gap=0,sa=0,ttc=math.huge,same=false,alongside=false},noticeAt=-math.huge,list={},pending=nil,junction=-1,junctionSamples=0,
  -- Beta 1.43 (maquette) : dernière annonce à l'écran, en panneau dédié de l'overlay (sigle, pilote, sanction,
  -- étiquette) ; numéro gardé au changement de session (l'overlay ne la reprend qu'à un numéro nouveau).
  aiSerial=0,aiCode='',aiTitle='',aiShort='',aiLabel='',aiBlack=false,aiFallback=''}
 for i=1,K.maxCars do t.cars[i]=car() end
 return t
end
local function rebuild(t)
 local rows=t.rows; for k=#rows,1,-1 do rows[k]=nil end
 for k=1,#t.events do rows[#rows+1]=t.events[k] end
 for k=1,#t.classRows do rows[#rows+1]=t.classRows[k] end
 t.dirty=true
end
-- Changement de session : avertissements, pénalités et classement corrigé oubliés.
function M.reset(t,now)
 for i=1,K.maxCars do clearCar(t.cars[i]) end
 for k=#t.events,1,-1 do t.events[k]=nil end
 for k=#t.classRows,1,-1 do t.classRows[k]=nil end
 t.order=0; t.classDirty=false; t.classText=nil; t.lastAt=nil; t.noticeAt=-math.huge; t.resetAt=now; t.junction=-1; t.junctionSamples=0
 t.pitSeen=false; t.off=false
 -- Beta 1.56 : rapport de course de la session suivante (une fois par course), votre arrivée oubliée.
 t.reportDone=false; t.raceSeen=false; t.playerDoneAt=nil
 -- Relecture : point de reprise réécrit (un redémarrage de la course ne garde aucune pénalité d'avant).
 rebuild(t); t.dirty=true
end
function M.rebase(t,amount)
 if t.resetAt then t.resetAt=t.resetAt-amount end
 if t.lastAt then t.lastAt=t.lastAt-amount end
 t.noticeAt=t.noticeAt-amount
 for b,v in pairs(t.lineIgnored) do t.lineIgnored[b]=v-amount end
 for _,seen in pairs(t.line) do for k,v in pairs(seen) do seen[k]=v-amount end end
 for i=1,K.maxCars do
  local c=t.cars[i]
  c.outAt=c.outAt-amount; c.lastStrikeAt=c.lastStrikeAt-amount; c.owedUntil=c.owedUntil-amount; c.owedAt=c.owedAt-amount; c.watchUntil=c.watchUntil-amount
  if c.boxAt>=0 then c.boxAt=c.boxAt-amount end
  c.noOutUntil=c.noOutUntil-amount; c.rejoinAt=c.rejoinAt-amount
 end
end
-- App à l'arrêt un moment (pause du moteur, panique, aucun onglet) : états passagers oubliés (sortie en cours, rampe
-- de l'accélérateur, place à rendre, contresens, passage dans la voie des stands) ; pénalités et classement gardés.
local function dropTransient(t)
 for i=1,K.maxCars do
  local c=t.cars[i]
  c.outFor=0; c.outCounted=false; c.cutLimit=1; c.cutWait=0; c.owedTo=0; c.owedFrom=-1; c.watchUntil=-math.huge
  for j in pairs(c.watch) do c.watch[j]=nil end
  c.wrongFor=0; c.lastSpline=-1; c.speedFor=0; c.cutBlocked=false
  -- Relecture : passage de pénalité en cours gardé (sinon l'arrêt à l'emplacement compterait comme un arrêt).
  if not c.entry then c.laneFor=0; c.wasPit=false; c.laneOff=0; c.boxAt=-1; c.asked=false end
 end
end
local function reasonText(key) return L.sanctionTexts.reasons[key] or L.sanctions142.reasons[key] or key end
-- Raison au journal (sans accents, comme le reste du journal).
local journalReasons={trackLimits='limites de piste',cut='virage coupe',jumpStart='faux depart',pitSpeed='exces de vitesse dans les stands',
 pitExit='ligne de sortie des stands',wrongWay='contresens',ignored='penalite non purgee',giveBack='place non rendue',repeated='trop d infractions',
 contact='contact',blueFlags='drapeaux bleus ignores'}
local kindJournal={drive='drive-through',stopgo='stop-and-go'}
-- Réglage de la source d'une pénalité aux stands (coupé : pénalité annulée).
local sourceOff={jumpStart='sanJumpStart',pitSpeed='sanPitSpeed',pitExit='sanPitExit',contact='sanContact'}
local function event(t,text,kind)
 local list=t.events
 table.insert(list,1,{text=text,kind=kind or 'text'})
 while #list>K.sanRowsMax do list[#list]=nil end
 rebuild(t)
end
-- Panneau dédié de l'overlay (Beta 1.43, maquette) : sigle (DT, SG, +N, CUT, POS ; aucun pour le drapeau noir),
-- nom du pilote, sanction et sa raison, étiquette de la ligne de session ; repli (titre · texte) quand un drapeau
-- occupe le bandeau.
function M.aiNotice(t,kind,text,what,driver,x,y)
 local N=L.aiNotices
 local short=what=='stopgo' and string.format(N.stopgo,x,y) or what=='time' and string.format(N.time,x,y)
  or what=='throttle' and string.format(N.throttle,x) or string.format(N[what],x)
 t.aiCode=what=='time' and string.format(N.codes.time,x) or N.codes[what] or ''
 t.aiTitle=driver; t.aiShort=short; t.aiBlack=what=='blackFlag'
 t.aiLabel=what=='giveBack' and N.labels.giveBack or what=='blackFlag' and N.labels.blackFlag or N.labels.sanction
 local m=L.messages[kind]; t.aiFallback=m and m[1]..' · '..text or text
 t.aiSerial=t.aiSerial%K.counterMax+1
end
-- Annonce à l'écran : une à la fois (au plus une toutes les K.sanNoticeGap s), drapeau noir toujours.
local function notice(t,e,kind,text,now,force,what,driver,x,y)
 -- Beta 1.56 : vos limites de piste toujours annoncées (sanMessages : annonces des IA seulement).
 if kind~='playerContact' then -- Beta 1.60 : vos contacts en tort toujours annoncés, comme vos limites de piste
 if not e.run.sanMessages and kind~='playerSanction' then return end
 end
 if not force and now-t.noticeAt<K.sanNoticeGap then return end
 Incidents.message(e.incidents,kind,0,0,text)
 if e.incidents.messageKind==kind and e.incidents.messageText==text then
  t.noticeAt=now
  if what then M.aiNotice(t,kind,text,what,driver,x,y) end
 end
end
local function name(a) return a.name~='' and a.name or a.id or '?' end
-- Drapeau noir : IA ramenée à son stand et garée jusqu'à la fin de la session (chemin de la disqualification existant :
-- e.penalties.ai.dq, lu par le moteur, les arrêts et la grille).
local function blackFlag(t,e,frame,i,reason,now)
 local c=t.cars[i]; local a=frame.cars[i]
 if c.dq then return end
 c.dq=true; c.pending=''; c.cutLeft=0; c.cutLimit=1; c.owedTo=0; c.rBlack=reason
 -- Garée par le moteur dès l'image suivante (cmd.scPark, parkReason 'dq'), comme une IA disqualifiée sous drapeau.
 e.penalties.ai.dq[i]=true; e.states[i].disqualified=true
 U.log(e.log,now,'WARN',string.format('sanction IA: %s drapeau noir (%s)',name(a),journalReasons[reason] or reason),i)
 local text=string.format(L.sanctionTexts.blackFlag,name(a),reasonText(reason))
 event(t,text,'warn'); notice(t,e,'aiBlackFlag',text,now,true,'blackFlag',name(a),reasonText(reason))
 t.classDirty=true
end
-- Pénalités de la session (temps, drive-through, stop-and-go ; jamais les avertissements ni la coupure des gaz) et
-- dépassements sous drapeau : au-delà du nombre toléré (penaltyDisqualify), drapeau noir.
local function escalate(t,e,frame,i,now)
 local c=t.cars[i]
 if c.count+(e.penalties.ai.count[i] or 0)>e.run.penaltyDisqualify then blackFlag(t,e,frame,i,'repeated',now) end
end
local function addTime(t,e,frame,i,seconds,reason,now,why)
 local c=t.cars[i]; local a=frame.cars[i]
 c.time=c.time+seconds; t.classDirty=true
 -- Relecture : les limites de piste ne comptent pas vers le drapeau noir (penaltyDisqualify).
 local counted=reason~='trackLimits' and reason~='blueFlags'
 if counted then c.count=c.count+1 end
 -- Beta 1.56 : rang de la pénalité de limites de piste (récidive) et total, rendus avec une zone ignorée.
 if reason=='trackLimits' then c.trackN=c.trackN+1; c.trackTime=c.trackTime+seconds end
 local text=string.format(L.sanctionTexts.time,name(a),seconds,reasonText(reason))
 -- Beta 1.56 : vos limites de piste (seul cas où le joueur reçoit du temps de l'app), annoncées comme les vôtres.
 if a.player then
  -- Beta 1.60 : vos contacts en tort (sanPlayerContact) : même chemin, annoncés sous leur propre titre.
  local contact=reason=='contact'
  U.log(e.log,now,'WARN',string.format('%s: penalite de temps +%.0f s%s, total +%.0f s',contact and 'contact joueur' or 'limites de piste joueur',seconds,why or '',c.time),i)
  -- Ligne de session de l'overlay (comme vos autres pénalités), jamais le panneau des sanctions des IA.
  event(t,text,'warn'); notice(t,e,contact and 'playerContact' or 'playerSanction',text,now,true)
  return
 end
 U.log(e.log,now,'WARN',string.format('sanction IA: %s penalite de temps +%.0f s (%s%s), total +%.0f s',name(a),seconds,journalReasons[reason] or reason,why or '',c.time),i)
 event(t,text,'warn'); notice(t,e,'aiSanction',text,now,false,'time',name(a),seconds,reasonText(reason))
 if counted then escalate(t,e,frame,i,now) end
end
-- Beta 1.56 : durée d'une pénalité de limites de piste. Pénalités croissantes (sanEscalation) : la n-ième d'une même
-- voiture vaut sanTimeSeconds+(n-1)*sanEscalationStep, au plus sanEscalationMax (jamais moins que sanTimeSeconds) ;
-- suffixe du journal « , recidive n ». Coupées : sanTimeSeconds, sans suffixe (comme avant).
local function trackSeconds(p,c)
 if not p.sanEscalation then return p.sanTimeSeconds,nil end
 local n=c.trackN+1
 return min(max(p.sanEscalationMax,p.sanTimeSeconds),p.sanTimeSeconds+(n-1)*p.sanEscalationStep),string.format(', recidive %d',n)
end
local function unservedSeconds(e,kind) return kind=='stopgo' and e.run.sanStopGoSeconds+K.sanDriveTime or K.sanDriveTime end
-- Infraction de procédure ou pénalité aux stands : drive-through, stop-and-go ou temps (réglage). Une seule pénalité
-- aux stands en attente : une autre devient une pénalité de temps ; trop tard pour la purger (moins de tours restants
-- que le délai), ajoutée au résultat si le réglage le veut.
local function issue(t,e,frame,i,kind,reason,now)
 local c=t.cars[i]; local a=frame.cars[i]; local p=e.run
 if kind=='time' then addTime(t,e,frame,i,p.sanTimeSeconds,reason,now); return end
 if kind=='stopgo' and e.stopCap==false then kind='drive' end
 if c.pending~='' then addTime(t,e,frame,i,p.sanTimeSeconds,reason,now,', penalite aux stands deja en attente'); return end
 if e.race.known and e.race.lapsLeft<p.sanServeLaps then
  if p.sanUnservedTime then addTime(t,e,frame,i,unservedSeconds(e,kind),reason,now,', trop tard pour la purger'); return end
 end
 if e.pitCap==false then addTime(t,e,frame,i,unservedSeconds(e,kind),reason,now,', arret aux stands impossible (CSP)'); return end
 c.pending=kind; c.pendingReason=reason; c.pendingLaps=0; c.could=false; c.count=c.count+1; c.issueLap=a.lap or 0; c.askedLaps=0; c.askedLap=false; t.dirty=true
 if kind=='stopgo' then c.rStopgo=c.rStopgo+1 else c.rDrive=c.rDrive+1 end
 if kind=='stopgo' then U.log(e.log,now,'WARN',string.format('sanction IA: %s stop-and-go %.0f s (%s), a purger en %d tours',name(a),p.sanStopGoSeconds,journalReasons[reason] or reason,p.sanServeLaps),i)
 else U.log(e.log,now,'WARN',string.format('sanction IA: %s drive-through (%s), a purger en %d tours',name(a),journalReasons[reason] or reason,p.sanServeLaps),i) end
 local text=kind=='stopgo' and string.format(L.sanctionTexts.stopgo,name(a),p.sanStopGoSeconds,reasonText(reason)) or string.format(L.sanctionTexts.drive,name(a),reasonText(reason))
 event(t,text,'warn')
 if kind=='stopgo' then notice(t,e,'aiSanction',text,now,false,'stopgo',name(a),p.sanStopGoSeconds,reasonText(reason))
 else notice(t,e,'aiSanction',text,now,false,'drive',name(a),reasonText(reason)) end
 escalate(t,e,frame,i,now)
end
-- Sorties au même endroit par plusieurs IA : la trajectoire des IA y sort elle-même des limites (circuit, ligne IA) ;
-- l'endroit est ignoré (aucun avertissement, aucun tour invalidé), noté une fois au journal.
local function lineBin(t,spline) return min(t.lineBins,floor((spline%1)*t.lineBins)+1) end
local function ignoredAt(t,b,now) local at=t.lineIgnored[b]; return at~=nil and now-at<K.sanLineDecay end
local function lineIgnored(t,b,now)
 local n=t.lineBins
 return ignoredAt(t,b,now) or ignoredAt(t,(b-2)%n+1,now) or ignoredAt(t,b%n+1,now)
end
-- Sanction déjà donnée à un endroit devenu zone ignorée : rendue (avertissement, temps, tour invalidé).
local function refund(t,e,frame,k,b,now)
 local c=t.cars[k]; local hit=c.lineHits[b]
 if not hit then return end
 c.lineHits[b]=nil
 if hit.kind=='strike' then c.strikes=max(0,c.strikes-1); c.rWarn=max(0,c.rWarn-1)
 elseif hit.kind=='time' then
  c.strikes=max(0,c.strikes-1); c.time=max(0,c.time-hit.seconds); t.classDirty=true; t.dirty=true
  c.trackN=max(0,c.trackN-1); c.trackTime=max(0,c.trackTime-hit.seconds)
 elseif hit.kind=='invalid' then
  c.invalid=max(0,c.invalid-hit.count)
  if c.invalidLap==hit.lap then c.invalidLap=-1 end
  if c.invalidNext==hit.lap+1 then c.invalidNext=-1 end
 end
 U.log(e.log,now,'INFO',string.format('limites de piste IA: %s, sanction annulee (zone ignoree)',frame.cars[k] and name(frame.cars[k]) or '?'),k)
end
-- Relecture : seules comptent des sorties propres (course lancée, sans drapeau jaune) de K.sanLineCars IA différentes
-- en K.sanLineWindow s ; zone oubliée K.sanLineDecay s après sa dernière sortie ; sanctions déjà données rendues.
local function lineSeen(t,e,frame,i,b,now)
 if t.lineIgnored[b] then if ignoredAt(t,b,now) then t.lineIgnored[b]=now; return end; t.lineIgnored[b]=nil end
 local seen=t.line[b]; if not seen then seen={}; t.line[b]=seen end
 local n=0
 for k,at in pairs(seen) do if now-at>K.sanLineWindow then seen[k]=nil elseif k~=i then n=n+1 end end
 seen[i]=now; n=n+1
 if n>=K.sanLineCars then
  t.lineIgnored[b]=now
  for k in pairs(seen) do refund(t,e,frame,k,b,now); seen[k]=nil end
  U.log(e.log,now,'INFO',string.format('limites de piste IA: zone ignoree a %.0f m (trajectoire des IA hors des limites, %d voitures)',(b-0.5)/t.lineBins*frame.length,n),-1)
 end
end
-- Temps gagné sur la portion hors des limites : temps de référence (allure apprise de la voiture, ou de sa classe) sur
-- la distance parcourue, moins le temps réellement mis ; nil si la portion est trop courte, trop longue ou inconnue.
local function cutGain(e,frame,i,c,a,now)
 local length=frame.length
 local ds=U.spline(a.spline-c.outFrom)*length
 if ds<K.sanCutMinDist or ds>K.sanCutMaxDist then return nil end
 local bins=e.delta.bins; local seg=length/bins
 local b,last=Delta.bin(c.outFrom,bins),Delta.bin(a.spline,bins)
 local need,visited=0,0; local multi=e.run.multiClass==true
 while true do
  local v=Delta.pace(e.delta,e.states,i,b,multi)
  if v<=0 then return nil end
  need=need+seg/v; visited=visited+1
  if b==last or visited>=K.sanCutBinsMax then break end
  b=b%bins+1
 end
 -- Endroits entamés : temps ramené à la distance réelle.
 need=need*ds/(visited*seg)
 return need-(now-c.outAt)
end
-- Voiture proche derrière (dans la même file) : jamais de coupure des gaz devant elle.
local function behind(e,i,c)
 local row=e.perception.rows[i]
 -- Relecture : distance de sécurité selon la vitesse d'approche, temps avant collision, reprise au-delà de K.sanCutResume m.
 local range=c.cutBlocked and K.sanCutResume or K.sanCutBehind
 for k=1,row.count do
  local r=row.neighbors[k]
  if r.same and r.long<0 and abs(r.lat)<=K.latPass then
   local closing=max(0,r.sa or 0)/3.6
   if r.gap<max(range,K.sanCutBehindTime*closing) or (r.ttc or math.huge)<K.sanCutTtc then c.cutBlocked=true; return true end
  end
 end
 c.cutBlocked=false
 return false
end
local function strike(t,e,frame,i,a,c,now)
 local p=e.run
 c.strikes=c.strikes+1; c.lastStrikeAt=now
 -- Beta 1.56 : temps réellement ajouté gardé (une zone ignorée rend exactement la pénalité, croissante comprise).
 local seconds,why=trackSeconds(p,c)
 c.lineHits[c.outBin]={kind=c.strikes<=p.sanTrackWarnings and 'strike' or 'time',seconds=seconds,lap=a.lap}
 if c.strikes<=p.sanTrackWarnings then
  c.rWarn=c.rWarn+1
  U.log(e.log,now,'INFO',string.format('limites de piste IA: %s avertissement %d / %d',name(a),c.strikes,p.sanTrackWarnings),i)
  event(t,string.format(L.sanctionTexts.warning,name(a),c.strikes,p.sanTrackWarnings),'text')
 else addTime(t,e,frame,i,seconds,'trackLimits',now,why) end
end
local function invalidate(t,e,frame,i,a,c,now)
 if c.invalidLap==a.lap then return end
 local sectors=frame.sectorCount or 0
 local sector=a.sector or 0
 local last=sectors>=2 and sector>=sectors-1 or sectors<2 and a.spline>=2/3
 c.invalidLap=a.lap; c.invalid=c.invalid+1
 if last then c.invalidNext=a.lap+1; c.invalid=c.invalid+1 end
 c.lineHits[c.outBin]={kind='invalid',count=last and 2 or 1,lap=a.lap}
 -- Beta 1.56 : votre tour invalidé dans l'app (temps et grille d'AC inchangés), annoncé à l'écran.
 if a.player then
  U.log(e.log,now,'INFO',string.format('tour invalide joueur (app): secteur %d%s',sector+1,last and ', dernier secteur : tour suivant aussi' or ''),i)
  local text=string.format(L.sanctionTexts.lapInvalid,name(a))
  event(t,text,'text'); notice(t,e,'playerSanction',text,now,true)
  return
 end
 U.log(e.log,now,'INFO',string.format('tour invalide IA: %s (secteur %d%s)',name(a),sector+1,last and ', dernier secteur : tour suivant aussi' or ''),i)
 event(t,string.format(L.sanctionTexts.lapInvalid,name(a)),'text')
end
-- Début d'une sortie (course) : voitures devant dans la même file, à suivre jusqu'à quelques secondes après le retour
-- en piste ; une voiture doublée pendant ce temps doit retrouver sa place.
local function progress(a) return (a.lap or 0)+(a.spline or 0) end
local function watchStart(e,i,c)
 for j in pairs(c.watch) do c.watch[j]=nil end
 local row=e.perception.rows[i]; local cars=e.frame and e.frame.cars
 local a=cars and cars[i]
 for k=1,row.count do
  local r=row.neighbors[k]
  local b=cars and cars[r.index]
  -- Relecture : seulement une voiture du même tour (jamais une attardée ni une voiture qui prend un tour).
  if r.same and r.long>0 and r.long<=K.passWatch and a and b and abs(progress(b)-progress(a))<0.5 then c.watch[r.index]=true end
 end
end
-- Manœuvre de l'app en cours (cession, dépassement, évitement, défense, décalage) : une sortie n'est pas une infraction.
local manoeuvres={YIELD_IN=true,YIELD_HOLD=true,YIELD_OUT=true,OVT_IN=true,OVT_HOLD=true,OVT_OUT=true,AVOID=true,DEFEND=true}
local function appManoeuvre(e,i)
 return manoeuvres[e.states[i].state]==true or abs(e.commands[i].offset or 0)>K.sanAppOffset
end
local function trackLimits(t,e,frame,i,a,c,now,dt,race,ready)
 local p=e.run; local inc=e.incidents
 local out=(a.wheelsOut or 0)>=3 and a.splineValid and not a.pit
 if out then
  if c.outFor==0 then
   c.outFrom=a.spline; c.outAt=now; c.outMin=a.kmh; c.outIncident=false; c.outCounted=false; c.outBin=lineBin(t,a.spline); c.outApp=false
   if race and ready and p.sanGiveBack and c.owedTo==0 then watchStart(e,i,c); c.watchUntil=math.huge end
  end
  c.outFor=c.outFor+dt; c.outMin=min(c.outMin,a.kmh)
  if inc.cars[i].incident then c.outIncident=true end
  -- Beta 1.47 : sortie dans les K.sanContactGrace s d'un contact (voiture poussée dehors) : comme un incident.
  local contactAt=e.lastContactAt and e.lastContactAt[i]
  if contactAt and now>=contactAt and now-contactAt<=K.sanContactGrace then c.outIncident=true end
  if e.states[i].yellow or appManoeuvre(e,i) then c.outApp=true end
  if not c.outCounted and c.outFor>=K.sanOutDwell then
   c.outCounted=true
   local clean=not c.outIncident and c.outMin>=K.sanOutKmh and not c.outApp
   if clean and p.sanTrackLimits and ready then
    lineSeen(t,e,frame,i,c.outBin,now)
    -- Essais et qualifications : tour invalidé aussitôt (comme le bandeau d'AC pour le joueur).
    if not race and not lineIgnored(t,c.outBin,now) then invalidate(t,e,frame,i,a,c,now) end
   end
  end
 elseif c.outFor>0 then
  -- Retour en piste : gain de temps jugé (course), sinon une sortie des limites comptée.
  local judged=c.outCounted and not c.outIncident and not c.outApp and c.outMin>=K.sanOutKmh and not lineIgnored(t,c.outBin,now)
  c.rejoinAt=now
  if race and ready and judged and not inc.red and not inc.neutral then
   local gain=p.sanCutPenalty and cutGain(e,frame,i,c,a,now) or nil
   if gain and gain>=K.sanCutGain and c.cutLeft<=0 then
    c.cutLeft=p.sanCutSeconds; c.cutSeconds=p.sanCutSeconds; c.cutWait=0; c.rCut=c.rCut+1
    U.log(e.log,now,'WARN',string.format('sanction IA: %s coupure des gaz %.0f s (virage coupe, gain %.2f s)',name(a),p.sanCutSeconds,gain),i)
    local text=string.format(L.sanctionTexts.throttle,name(a),p.sanCutSeconds)
    event(t,text,'warn'); notice(t,e,'aiSanction',text,now,false,'throttle',name(a),p.sanCutSeconds)
   elseif p.sanTrackLimits and now-c.lastStrikeAt>=K.sanStrikeGap then strike(t,e,frame,i,a,c,now) end
  end
  c.outFor=0; c.outCounted=false
  if c.watchUntil==math.huge then
   -- Relecture : après un tête-à-queue, aucune place à rendre (une place prise hors piste pendant une manœuvre de l'app
   -- reste due : la rendre ne coûte rien à personne).
   if c.outIncident then c.watchUntil=-math.huge; for j in pairs(c.watch) do c.watch[j]=nil end
   else c.watchUntil=now+K.sanGiveBackWindow end
  end
 end
end
-- Beta 1.56 (décision du pilote) : vos limites de piste gérées par l'app (sanPlayerTrackLimits). Mêmes règles que les
-- IA (au moins trois roues dehors K.sanOutDwell s, à K.sanOutKmh km/h au moins, ni incident, ni contact juste avant,
-- ni drapeau jaune, rouge ou neutralisation, rien dans les premières secondes de la course) ; jamais la règle des zones
-- ignorées (votre trajectoire est la vôtre) et vos sorties ne la nourrissent jamais. Essais et qualifications : tour
-- invalidé dans l'app, ou avertissement seulement (sanPlayerSession). Course : avertissements, puis pénalité de temps au
-- classement corrigé, ou coupure des gaz native d'AC (sanPlayerPenalty), remplacée par du temps si AC ne l'écrit pas.
local function playerStrike(t,e,frame,i,a,c,now)
 local p=e.run
 c.strikes=c.strikes+1; c.lastStrikeAt=now
 local warning=c.strikes<=p.sanTrackWarnings
 if warning then
  c.rWarn=c.rWarn+1
  U.log(e.log,now,'INFO',string.format('limites de piste joueur: avertissement %d / %d',c.strikes,p.sanTrackWarnings),i)
  local text=string.format(L.sanctionTexts.warning,name(a),c.strikes,p.sanTrackWarnings)
  event(t,text,'text'); notice(t,e,'playerSanction',text,now,true)
  return
 end
 local seconds,why=trackSeconds(p,c)
 if p.sanPlayerPenalty=='throttle' then
  -- Coupure des gaz d'AC (durée de la pénalité de temps, jamais croissante : c'est la pénalité d'AC elle-même).
  local id=e.penaltyCap and Penalties.requestTrackLimits(e.penalties,p.sanTimeSeconds,now)
  if id then
   c.cutRequest=id; c.cutAt=now; c.rCut=c.rCut+1
   U.log(e.log,now,'WARN',string.format('limites de piste joueur: coupure des gaz %.0f s demandee a AC',p.sanTimeSeconds),i)
   event(t,string.format(L.sanctionTexts.throttle,name(a),p.sanTimeSeconds),'warn')
   return
  end
  why=', coupure des gaz refusee par AC'..(why or '')
 end
 addTime(t,e,frame,i,seconds,'trackLimits',now,why)
end
local function playerNotice(t,e,i,a,c,now)
 U.log(e.log,now,'INFO',string.format('limites de piste joueur: sortie au secteur %d (avertissement seulement)',(a.sector or 0)+1),i)
 c.rWarn=c.rWarn+1
 local text=string.format(L.sanctionTexts.lapNotice,name(a))
 event(t,text,'text'); notice(t,e,'playerSanction',text,now,true)
end
local function playerLimits(t,e,frame,i,a,c,now,dt,race,ready)
 local p=e.run; local inc=e.incidents
 -- Coupure des gaz demandée : écrite par l'applicateur (confirmée), sinon du temps à la place, jamais les deux.
 if c.cutRequest>0 then
  if e.penaltyWritten==c.cutRequest then c.cutRequest=0
  elseif not e.penaltyCap or now-c.cutAt>=K.sanPlayerCutConfirm then
   e.penalties.cancelled=c.cutRequest; c.cutRequest=0; c.rCut=max(0,c.rCut-1)
   local seconds,why=trackSeconds(p,c)
   addTime(t,e,frame,i,seconds,'trackLimits',now,', coupure des gaz refusee par AC'..(why or ''))
  end
 end
 local out=(a.wheelsOut or 0)>=3 and a.splineValid and not a.pit
 if out then
  if c.outFor==0 then c.outFrom=a.spline; c.outAt=now; c.outMin=a.kmh; c.outIncident=false; c.outCounted=false; c.outApp=false end
  c.outFor=c.outFor+dt; c.outMin=min(c.outMin,a.kmh)
  if inc.cars[i].incident then c.outIncident=true end
  local hit=e.lastContactAt and e.lastContactAt[i]
  if hit and now>=hit and now-hit<=K.sanContactGrace then c.outIncident=true end
  -- Drapeau jaune du joueur (le pilotage des IA ne le suit pas pour vous), rouge ou neutralisation : pas une infraction.
  if inc.playerYellow or inc.red or inc.neutral then c.outApp=true end
  if not c.outCounted and c.outFor>=K.sanOutDwell then
   c.outCounted=true
   local fair=not c.outIncident and c.outMin>=K.sanOutKmh and not c.outApp
   if fair and ready and not race then
    if p.sanPlayerSession=='notice' then playerNotice(t,e,i,a,c,now) else invalidate(t,e,frame,i,a,c,now) end
   end
  end
 elseif c.outFor>0 then
  local judged=c.outCounted and not c.outIncident and not c.outApp and c.outMin>=K.sanOutKmh
  c.rejoinAt=now
  if race and ready and judged and not inc.red and not inc.neutral and now-c.lastStrikeAt>=K.sanStrikeGap then playerStrike(t,e,frame,i,a,c,now) end
  c.outFor=0; c.outCounted=false
 end
end
-- Coupure des gaz servie en ligne droite seulement : jamais en virage, au freinage, sous drapeau ou neutralisation,
-- dans la voie des stands, sous K.sanCutMinKmh km/h, ni avec une voiture à moins de K.sanCutBehind m derrière ; rampe
-- vers K.sanCutThrottle (jamais une coupure franche), puis retour. Sans occasion sûre pendant K.sanCutDeferMax s :
-- pénalité de temps à la place.
local function throttle(t,e,frame,i,a,c,cmd,now,dt)
 local target=1
 -- Relecture : réglage coupé en cours de séance, coupure abandonnée.
 if c.cutLeft>0 and not e.run.sanCutPenalty then c.cutLeft=0 end
 if c.cutLeft>0 then
  local inc=e.incidents
  -- Ligne droite : accélération latérale d'au plus K.sanStraightLat m/s² ; jamais juste après un retour en piste, une
  -- sortie des stands ou le départ.
  local safe=not a.pit and not a.offtrack and not e.states[i].yellow and not inc.neutral and not inc.red and a.kmh>=K.sanCutMinKmh
   and abs(a.yawRate or 0)*max(a.speed,1)<=K.sanStraightLat and (a.brake or 0)<K.sanCutBrake
   and now-c.rejoinAt>=K.sanCutAfterRejoin and now>=(e.states[i].pitExitUntil or 0) and now-e.startedAt>=K.sanCutAfterStart
   and not behind(e,i,c)
  if safe then target=K.sanCutThrottle; c.cutLeft=max(0,c.cutLeft-dt)
  elseif not a.pit and not inc.neutral and not inc.red then c.cutWait=c.cutWait+dt end
  if c.cutLeft<=0 then
   U.log(e.log,now,'INFO',string.format('sanction IA purgee: %s coupure des gaz',name(a)),i); c.rServed=c.rServed+1
   event(t,string.format(L.sanctionTexts.served,name(a)),'text')
  elseif c.cutWait>=K.sanCutDeferMax then
   c.cutLeft=0; target=1
   addTime(t,e,frame,i,e.run.sanTimeSeconds,'cut',now,', coupure des gaz impossible en securite')
  end
 end
 if c.cutLimit>target then c.cutLimit=max(target,c.cutLimit-K.sanCutRampDown*dt) else c.cutLimit=min(target,c.cutLimit+K.sanCutRampUp*dt) end
 if c.cutLimit<1 then cmd.throttleLimit=min(cmd.throttleLimit,c.cutLimit) end
end
local function wrongWay(t,e,frame,i,a,c,now,dt)
 local p=e.run
 -- Relecture : jamais hors piste ni pendant un tête-à-queue ou un arrêt (le contresens lui-même est aussi un incident).
 local ic=e.incidents.cars[i]
 if a.splineValid and not a.pit and not a.offtrack and not (ic.incident and (ic.wrong or 0)<K.wrongWayTime) and a.kmh>=K.sanWrongWayKmh and c.lastSpline>=0 and U.spline(a.spline-c.lastSpline)<0
  -- Beta 1.60 (correctif) : nez en premier seulement (une IA qui recule pour quitter un mur n'est pas à contresens).
  and Incidents.noseFirst(a,c.lastX,c.lastZ) then c.wrongFor=c.wrongFor+dt
 else c.wrongFor=max(0,c.wrongFor-2*dt) end
 c.lastSpline=a.splineValid and not a.pit and a.spline or -1; c.lastX=a.x; c.lastZ=a.z
 if p.sanWrongWay and c.wrongFor>=p.sanWrongWaySeconds and not e.incidents.red then blackFlag(t,e,frame,i,'wrongWay',now) end
end
-- Voie des stands : excès de vitesse (après K.sanPitSpeedGrace s dans la voie, au-delà de la marge, K.sanPitSpeedDwell
-- s de suite, une fois par passage), ligne de sortie franchie (sortie de la voie plus de K.sanPitExitMargin m avant la
-- jonction apprise, au moins K.sanPitExitSamples sorties relevées ; jonction de l'image précédente, avant que cette
-- sortie ne la déplace), pénalité purgée à la sortie de la voie.
local function pitLane(t,e,frame,i,a,c,now,dt,ready)
 local p=e.run
 -- Relecture : drapeau « dans la voie » d'AC instable : sortie confirmée après K.sanLaneDebounce s hors de la voie.
 if a.pit then c.laneOff=0 elseif c.wasPit then if c.laneOff==0 then c.exitSpline=a.spline; c.exitJunction=t.junction; c.exitSamples=t.junctionSamples end; c.laneOff=c.laneOff+dt end
 local lane=a.pit or c.wasPit and c.laneOff<K.sanLaneDebounce
 if lane then
  if not c.wasPit then c.laneFor=0; c.speedFor=0; c.speedDone=false; c.entry=c.asked and c.pending~='' and not a.teleport; c.boxAt=-1; c.held=false end
  c.laneFor=c.laneFor+dt
  if a.pit and not a.inPitBox then
   local limit=frame.pitsSpeedLimit or K.sanPitLimitDefault
   if limit<K.sanPitLimitMin then limit=K.sanPitLimitDefault end
   if p.sanPitSpeed and ready and not c.speedDone and c.laneFor>=K.sanPitSpeedGrace and a.kmh>limit+K.sanPitSpeedMargin then c.speedFor=c.speedFor+dt else c.speedFor=0 end
   if c.speedFor>=K.sanPitSpeedDwell then
    c.speedDone=true
    U.log(e.log,now,'INFO',string.format('stands IA: %s a %.0f km/h dans la voie (limite %.0f km/h)',name(a),a.kmh,limit),i)
    issue(t,e,frame,i,p.sanProcedureKind,'pitSpeed',now)
   end
  end
 elseif c.wasPit then
  -- Jonction connue à la sortie de la voie (avant que cette sortie ne la déplace).
  local junction,samples=c.exitJunction or t.junction,c.exitSamples or t.junctionSamples
  if p.sanPitExit and ready and not a.teleport and c.laneFor>=K.sanPitExitLane and junction>=0 and samples>=K.sanPitExitSamples then
   local d=U.spline(junction-(c.exitSpline>=0 and c.exitSpline or a.spline))*frame.length
   if d>K.sanPitExitMargin and d<frame.length*0.5 then
    U.log(e.log,now,'INFO',string.format('stands IA: %s sortie de la voie %.0f m avant la jonction',name(a),d),i)
    issue(t,e,frame,i,p.sanProcedureKind,'pitExit',now)
   end
  end
  -- Pénalité purgée : drive-through à la sortie de la voie, stop-and-go après l'arrêt complet à l'emplacement.
  if c.entry and c.pending~='' and (c.pending=='drive' or c.held) then
   U.log(e.log,now,'INFO',string.format('sanction IA purgee: %s %s',name(a),kindJournal[c.pending]),i); c.rServed=c.rServed+1
   event(t,string.format(L.sanctionTexts.served,name(a)),'text')
   c.pending=''; t.dirty=true
  end
  -- Sortie d'un passage de pénalité : pas de tour de sortie (pneus ni changés ni refroidis), le temps que la stratégie
  -- voie la sortie.
  if c.entry then c.noOutUntil=now+K.sanNoOutLap end
  c.entry=false; c.boxAt=-1; c.held=false; c.exitSpline=-1; c.exitJunction=nil; c.exitSamples=nil
 end
 c.wasPit=lane
end
-- Pénalité aux stands : arrêt demandé dès que possible (course lancée, stands ouverts, ni drapeau rouge ni
-- neutralisation) ; jamais avec un autre arrêt voulu (règles, stratégie, météo : la pénalité attend le suivant).
-- Passage de pénalité : ni pneus ni réparations ; aucune attente (drive-through) ou l'attente du stop-and-go ; l'arrêt
-- n'est pas un arrêt obligatoire. Le carburant reste celui d'AC (une demande de l'app fixerait aussi le tour d'un
-- arrêt natif).
local function serve(e,i,a,c,cmd,now,servable)
 local p=e.run; local inc=e.incidents
 if c.pending=='' then c.asked=false; return end
 if not a.pit then
  if c.entry then return end
  if servable and c.asked then c.could=true end
  if c.asked then c.askedLap=true end
  -- Relecture 1.42 (après correctifs) : la pénalité attend aussi un arrêt de la stratégie voulu (pas encore appelé) ou
  -- un arrêt des règles retenu par la limite d'appels ; une nouvelle demande prend une place d'appel (limite partagée).
  local st=e.strategy and e.strategy.cars[i]; local pc=e.pits.cars[i]; local t=e.sanctions
  if not servable then c.asked=false
  elseif cmd.rulePit or cmd.weatherManaged and cmd.weatherPit or st and st.wanted or pc and pc.deferred then c.asked=false
  elseif not c.asked and t.calls>=K.pitConcurrent then
  else if not c.asked then t.calls=t.calls+1 end; cmd.rulePit=true; c.asked=true end
  cmd.sanCalled=c.asked
  return
 end
 if not c.entry or inc.red or now<(inc.releaseAt[i] or -math.huge) or inc.gate and inc.gate[i] then return end
 -- Relecture 1.42 (après correctifs) : ni pneus, ni réparations, ni carburant demandé pendant un passage de pénalité
 -- (un arrêt des règles ou de la stratégie dû le remet sinon dès l'entrée dans la voie).
 cmd.rulePit=true; cmd.pitCompound=-1; cmd.pitRepair=false; cmd.fuelTarget=-1; cmd.fuelLaps=0
 if a.inPitBox then
  if c.boxAt<0 and a.kmh<=K.tyreStopSpeed then
   c.boxAt=now
  end
  if c.pending=='stopgo' then
   local waited=c.boxAt>=0 and now-c.boxAt or 0
   cmd.pitHold=c.boxAt<0 or waited<p.sanStopGoSeconds
   if c.boxAt>=0 and waited>=p.sanStopGoSeconds then c.held=true end
  else cmd.pitHold=false end
 end
end
-- Place à rendre : levée de pied sous l'allure de la voiture doublée (comme la place à rendre sous drapeau) jusqu'à ce
-- qu'elle repasse ; annulée si elle rentre aux stands, sort, abandonne, ou sous drapeau rouge ou neutralisation ;
-- pénalité de temps à l'échéance.
local function giveBack(t,e,frame,i,a,c,cmd,now)
 local p=e.run; local inc=e.incidents
 if not p.sanGiveBack then
  if c.owedTo~=0 then c.owedTo=0; c.owedFrom=-1 end
  if next(c.watch)~=nil then for j in pairs(c.watch) do c.watch[j]=nil end end
  return
 end
 -- Sortie en cours ou toute récente : voiture devant doublée hors des limites, place due.
 if now<c.watchUntil and c.owedTo==0 then
  for j in pairs(c.watch) do
   local b=frame.cars[j]
   if not b.valid or b.pit or b.offtrack or b.finished then c.watch[j]=nil
   else
    if (progress(a)-progress(b))*frame.length>(a.length+b.length)*0.5 then
     c.watch[j]=nil
     if c.owedTo==0 and (e.penalties.ai.giveBack[i] or 0)==0 then
      c.owedTo=j; c.owedUntil=now+p.sanGiveBackSeconds; c.owedFrom=-1
      U.log(e.log,now,'INFO',string.format('place a rendre IA: %s doit rendre la place a %s (%.0f s)',name(a),name(b),p.sanGiveBackSeconds),i); c.rOwed=c.rOwed+1
      local text=string.format(L.sanctionTexts.giveBack,name(a),name(b))
      event(t,text,'warn'); notice(t,e,'aiSanction',text,now,false,'giveBack',name(a),name(b))
     end
    end
   end
  end
 elseif now>=c.watchUntil and next(c.watch)~=nil then for j in pairs(c.watch) do c.watch[j]=nil end end
 if c.owedTo==0 then return end
 local j=c.owedTo; local b=frame.cars[j]
 -- Relecture : annulée aussi sous drapeau jaune, pour une voiture doublée accidentée, attardée, sous drapeau bleu ou qui se
 -- traîne (jamais une IA à 30 km/h sur la trajectoire pour l'attendre).
 local multi=e.run.multiClass==true
 local slow=b.valid and Delta.pace(e.delta,e.states,j,Delta.bin(b.spline,e.delta.bins),multi)*K.sanGiveBackSlowPace>b.speed
 local why=inc.red and 'drapeau rouge' or inc.neutral and 'neutralisation' or (e.states[i].yellow or e.states[j].yellow) and 'drapeau jaune'
  or (not b.valid or b.pit or b.finished or e.penalties.ai.dq[j] or t.cars[j].dq) and name(b)..' hors course ou aux stands'
  or inc.cars[j].incident and name(b)..' accidentee' or abs(progress(b)-progress(a))>=0.5 and name(b)..' attardee'
  or (e.states[j].yieldBlue or e.states[j].bluePending) and 'drapeau bleu' or slow and name(b)..' trop lente'
 if why then
  U.log(e.log,now,'INFO',string.format('place a rendre IA: %s, annulee (%s)',name(a),why),i)
  c.owedTo=0; c.owedFrom=-1; return
 end
 if (progress(b)-progress(a))*frame.length>(a.length+b.length)*0.5 then
  U.log(e.log,now,'INFO',string.format('place rendue IA: %s a %s',name(a),name(b)),i); c.rGiven=c.rGiven+1
  event(t,string.format(L.sanctionTexts.given,name(a)),'text')
  c.owedTo=0; c.owedFrom=-1; return
 end
 if now>=c.owedUntil then
  c.owedTo=0; c.owedFrom=-1
  addTime(t,e,frame,i,p.sanTimeSeconds,'giveBack',now)
  return
 end
 if c.owedFrom<0 then c.owedFrom=a.kmh; c.owedAt=now; c.owedOther=b.kmh end
 -- Plancher : allure de la voiture doublée au début moins K.sanGiveBackFloorDrop km/h, au moins K.sanGiveBackPaceFloor
 -- fois l'allure apprise ici.
 local pace=Delta.pace(e.delta,e.states,i,Delta.bin(a.spline,e.delta.bins),multi)*3.6
 local floor=max(c.owedOther-K.sanGiveBackFloorDrop,pace*K.sanGiveBackPaceFloor)
 cmd.yellowLimit=min(cmd.yellowLimit,max(floor,Penalties.giveBackLimit(c.owedFrom,c.owedAt,now,b.kmh,p.yellowDecel)))
end
-- Tour bouclé : tours écoulés pour purger une pénalité (un tour sans aucun moment où elle était possible ne compte pas) ; au-delà
-- de sanServeLaps, drapeau noir. Tour invalidé d'avance (dernier secteur du tour précédent).
-- Beta 1.62 (décision 5 du pilote, course) : drapeaux bleus ignorés. Une IA qui garde derrière elle une voiture qui lui
-- prend un tour (journal des drapeaux bleus entre IA de src/director.lua : s.blueAiLate après K.blueLogTime s) reçoit un
-- drapeau de plus toutes les K.blueIgnoreStep s ; au K.blueIgnoreMax-ième de suite, pénalité de temps (comptée vers
-- le drapeau noir). Elle cède : compte remis à zéro. Sous l'option des sanctions des IA (sanContact), sans nouveau
-- réglage.
local function blueFlags(t,e,frame,i,a,c,now)
 local s=e.states[i]
 if not e.run.sanContact or not s then c.blueN=0; c.blueEpN=0; c.blueBy=0; c.blueDone=false; return end
 if s.blueAiYield then c.blueN=0; c.blueEpN=0; c.blueDone=false; return end
 -- Beta 1.62 (relecture M1) : un épisode = la même voiture qui prend un tour ; une seule pénalité par épisode, hors du
 -- compte du drapeau noir ; seul le temps passé sans veto du directeur (s.blueAiFree) compte.
 if (s.blueAiBy or 0)~=(c.blueBy or 0) then c.blueBy=s.blueAiBy or 0; c.blueN=0; c.blueEpN=0; c.blueDone=false end
 if c.blueDone then return end
 if not s.blueAiLate then c.blueEpN=0; return end
 local free=s.blueAiFree or 0
 if free<K.blueLogTime then return end
 local n=1+floor((free-K.blueLogTime)/K.blueIgnoreStep)
 if n<=c.blueEpN then return end
 c.blueN=min(K.blueIgnoreMax,c.blueN+(n-c.blueEpN)); c.blueEpN=n
 -- Beta 1.62 (dernier lot) : une seule ligne par épisode, au drapeau qui donne la pénalité (33 lignes par minute à 60 IA
 -- avec « Realistic race » quand chaque drapeau était journalisé).
 if c.blueN>=K.blueIgnoreMax then
  local by=frame.cars[s.blueAiBy or 0]
  U.log(e.log,now,'INFO',string.format('drapeau bleu IA ignore: %s (%d / %d) devant %s',name(a),c.blueN,K.blueIgnoreMax,by and name(by) or '?'),i)
  c.blueN=0; c.blueDone=true; e.stats.blueIgnored=(e.stats.blueIgnored or 0)+1
  addTime(t,e,frame,i,e.run.sanTimeSeconds,'blueFlags',now)
 end
end
local function lap(t,e,frame,i,a,c,now)
 local p=e.run
 if c.pending~='' then
  -- Relecture : le tour de l'annonce ne compte pas ; point de reprise réécrit à chaque tour compté.
  if c.could and (a.lap or 0)-1>c.issueLap then c.pendingLaps=c.pendingLaps+1; t.dirty=true end
  c.could=false
  if c.askedLap then c.askedLaps=c.askedLaps+1 end
  c.askedLap=false
  -- Relecture : appelée K.sanNoPitLaps tours sans qu'aucune IA n'entre aux stands de la séance (voie des stands sans
  -- ligne IA) : pénalité de temps à la place.
  if c.askedLaps>=K.sanNoPitLaps and not t.pitSeen then
   local kind=c.pending; c.pending=''; c.asked=false
   addTime(t,e,frame,i,unservedSeconds(e,kind),c.pendingReason,now,', voie des stands jamais prise par les IA')
   return
  end
  if c.pendingLaps>=p.sanServeLaps and not a.pit and not (e.race.known and e.race.lapsLeft<=0) then blackFlag(t,e,frame,i,'ignored',now) end
 end
 if c.invalidNext==a.lap then c.invalidLap=a.lap; c.invalidNext=-1 end
end
-- Données gardées par un rechargement de l'app (même session) : rendues à la voiture de même identité, même index.
local function resume(t,e,frame)
 local pending=t.pending
 if not pending or frame.count==0 then return end
 t.pending=nil
 if frame.session~=pending.session then return end
 for _,r in ipairs(pending.rows) do
  local a=frame.cars[r.index]; local c=t.cars[r.index]
  if a and a.valid and (a.identity or a.id)==r.identity then
   c.identity=r.identity; c.time=r.time; c.count=r.count; c.pending=r.kind; c.pendingLaps=r.laps; c.strikes=r.strikes
   if r.dq then c.dq=true; e.penalties.ai.dq[r.index]=true; e.states[r.index].disqualified=true end
  end
 end
 t.classDirty=true
end
-- Beta 1.60 (src/blame.lua) : voiture jugée en tort dans un contact. serious : contact grave (l'autre voiture a perdu
-- le contrôle, est sortie ou a perdu K.blamePlaces places) ; out : l'autre voiture est restée arrêtée K.blameOutTime s.
-- IA (sanContact) : léger, K.blameWarnings avertissements puis pénalité de temps ; grave, pénalité de temps ; grave et
-- l'autre hors course, drive-through (ou son équivalent en temps, règles existantes) ; essais et qualifications :
-- avertissements seulement. Vous (sanPlayerContact, course seulement) : K.blameWarnings avertissements, puis la
-- pénalité choisie pour vos limites de piste (sanPlayerPenalty) : du temps au classement corrigé, ou la coupure des gaz
-- native d'AC ; jamais de drapeau noir, jamais de disqualification, rien d'autre sur votre voiture.
function M.contact(t,e,frame,i,serious,out,now)
 local c=t.cars[i]; local a=frame.cars[i]; local p=e.run
 if not a or not a.valid or c.dq or a.finished or a.safetyCar or t.off then return end
 local race=e.profile=='C'
 if a.player then
  if not race or not p.sanPlayerContact then return end
  c.contacts=c.contacts+1
  if c.contactWarn<K.blameWarnings then
   c.contactWarn=c.contactWarn+1
   U.log(e.log,now,'INFO',string.format('contact joueur: avertissement %d / %d',c.contactWarn,K.blameWarnings),i)
   local text=string.format(L.sanctionTexts.contactWarning,name(a),c.contactWarn,K.blameWarnings)
   event(t,text,'text'); notice(t,e,'playerContact',text,now,true)
   return
  end
  local why=nil
  if p.sanPlayerPenalty=='throttle' then
   local id=e.penaltyCap and Penalties.requestContact(e.penalties,p.sanTimeSeconds,now)
   if id then
    c.contactRequest=id; c.contactAt=now
    U.log(e.log,now,'WARN',string.format('contact joueur: coupure des gaz %.0f s demandee a AC',p.sanTimeSeconds),i)
    event(t,string.format(L.sanctionTexts.contactThrottle,name(a),p.sanTimeSeconds),'warn')
    return
   end
   why=', coupure des gaz refusee par AC'
  end
  addTime(t,e,frame,i,p.sanTimeSeconds,'contact',now,why)
  return
 end
 if not p.sanContact or not a.control or e.penalties.ai.dq[i] then return end
 c.contacts=c.contacts+1
 if not race or not serious and c.contactWarn<K.blameWarnings then
  c.contactWarn=c.contactWarn+1
  local of=max(c.contactWarn,K.blameWarnings)
  U.log(e.log,now,'INFO',string.format('sanction IA: %s avertissement contact %d / %d',name(a),c.contactWarn,of),i)
  event(t,string.format(L.sanctionTexts.contactWarning,name(a),c.contactWarn,of),'text')
  return
 end
 if serious and out then issue(t,e,frame,i,'drive','contact',now) else addTime(t,e,frame,i,p.sanTimeSeconds,'contact',now) end
end
-- Coupure des gaz demandée à AC pour un contact : écrite par l'applicateur (confirmée), sinon du temps à la place,
-- jamais les deux (comme pour vos limites de piste).
local function contactConfirm(t,e,frame,i,c,now)
 if e.penaltyWritten==c.contactRequest then c.contactRequest=0
 elseif not e.penaltyCap or now-c.contactAt>=K.sanPlayerCutConfirm then
  e.penalties.cancelled=c.contactRequest; c.contactRequest=0
  addTime(t,e,frame,i,e.run.sanTimeSeconds,'contact',now,', coupure des gaz refusee par AC')
 end
end
-- À chaque image, à la fin de Engine.step (après les sanctions sous drapeau). Essais et qualifications : tours
-- invalidés et contresens ; course : tout. Journée circuit et hotlap : rien (section masquée).
function M.update(t,e,frame,now,dt)
 if frame.length<=0 then return end
 local profile=e.profile
 local race=profile=='C'; local practice=profile=='P' or profile=='Q'
 if not race and not practice then t.lastAt=nil; return end
 -- Relecture : section décochée en cours de séance : plus rien en cours (pénalités à purger, coupure des gaz, place à
 -- rendre, passage de pénalité) ; temps déjà ajoutés gardés (classement corrigé plus émis).
 if not C.on(e.p,'sanctions') then
  if not t.off then
   t.off=true
   for i=1,K.maxCars do
    local c=t.cars[i]; local cmd=e.commands[i]
    c.pending=''; c.asked=false; c.entry=false; c.cutLeft=0; c.cutLimit=1; c.owedTo=0; c.owedFrom=-1; c.watchUntil=-math.huge
    for j in pairs(c.watch) do c.watch[j]=nil end
    if cmd then cmd.penaltyPass=false; cmd.sanCalled=false; if c.noOutSet then cmd.noOutLap=false; c.noOutSet=false end end
   end
   t.dirty=true
  end
  t.lastAt=nil; return
 end
 t.off=false
 if t.lastAt and now-t.lastAt>K.sanIdleGap then dropTransient(t) end
 t.lastAt=now
 resume(t,e,frame)
 local bins=U.clamp(math.ceil(frame.length/K.sanLineMeters),1,K.sanLineBinsMax)
 if bins~=t.lineBins or frame.track~=t.lineTrack then t.lineBins=bins; t.lineTrack=frame.track; for b in pairs(t.line) do t.line[b]=nil end; for b in pairs(t.lineIgnored) do t.lineIgnored[b]=nil end end
 local p=e.run; local inc=e.incidents
 local since=now-e.startedAt
 -- Course : rien de jugé dans les premières secondes (premier virage) ; arrêt de pénalité une fois la course lancée,
 -- stands ouverts, sans drapeau rouge ni neutralisation, hors départ arrêté.
 local ready=not race or frame.started and since>=K.sanGraceStart
 local servable=race and frame.started and since>=K.sanServeAfterStart and not inc.red and not inc.neutral and not inc.pitsClosed and (inc.standing=='none' or inc.standing=='go')
 -- Faux départs d'un départ arrêté de l'app (relevés par la grille).
 local jumps=e.grid.aiJump
 if jumps then
  for i=1,K.maxCars do
   if jumps[i]==true then jumps[i]='taken'; if race and p.sanJumpStart and i<=frame.count and not frame.cars[i].player then
     issue(t,e,frame,i,p.sanProcedureKind,'jumpStart',now)
     -- Beta 1.61 (tranche D) : faux départ flagrant, compté deux fois vers le drapeau noir.
     if p.startRealism and e.grid.aiJumpGrade[i]=='flagrant' then t.cars[i].count=t.cars[i].count+1; escalate(t,e,frame,i,now) end
    end end
  end
 end
 -- Relecture 1.42 (après correctifs) : appels aux stands déjà donnés (règles, stratégie, pénalités tenues) : même limite
 -- K.pitConcurrent pour une nouvelle demande de passage de pénalité.
 local calls=0
 for i=1,frame.count do local cmd=e.commands[i]; local ci=t.cars[i]; if not frame.cars[i].pit and (cmd.rulePit or ci.asked and ci.pending~='') then calls=calls+1 end end
 t.calls=calls
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]
  local identity=a.identity or a.id or ''
  if c.identity~=identity then clearCar(c,identity) end
  e.commands[i].sanCalled=false
  if a.teleport then c.outFor=0; c.outCounted=false; c.wrongFor=0; c.lastSpline=-1; c.watchUntil=-math.huge end
  e.commands[i].penaltyPass=false
  if a.valid and a.pit and not a.player and not a.teleport and frame.started then t.pitSeen=true end
  -- Relecture : réglage de la source coupé en cours de séance, pénalité à purger annulée (jamais un passage en cours).
  if c.pending~='' and not c.entry and sourceOff[c.pendingReason] and not p[sourceOff[c.pendingReason]] then
   U.log(e.log,now,'INFO',string.format('sanction IA: %s %s annule (reglage coupe)',name(a),kindJournal[c.pending] or c.pending),i)
   c.pending=''; c.asked=false; t.dirty=true
  end
  -- Beta 1.56 : rapport de course : nom et modèle relevés pendant la course (gardés après un changement de session).
  if race and p.sanReport and a.valid then c.rName=a.baseName or name(a); c.rModel=a.id or '' end
  if a.valid and a.control and not a.player and not a.safetyCar and not a.finished and not c.dq and not e.penalties.ai.dq[i] then
   local cmd=e.commands[i]
   if c.lastLap>=0 and a.lap>c.lastLap then lap(t,e,frame,i,a,c,now) end
   c.lastLap=a.lap
   if not c.dq then trackLimits(t,e,frame,i,a,c,now,dt,race,ready) end
   if not c.dq then wrongWay(t,e,frame,i,a,c,now,dt) end
   if race and not c.dq then
    pitLane(t,e,frame,i,a,c,now,dt,ready)
    serve(e,i,a,c,cmd,now,servable)
    -- Passage de pénalité (drive-through, stop-and-go) : aucun tour de sortie à pneus froids ensuite (cmd.noOutLap de la
    -- stratégie), seulement levé s'il vient d'ici.
    if c.entry and a.pit or now<c.noOutUntil then cmd.noOutLap=true; c.noOutSet=true elseif c.noOutSet then cmd.noOutLap=false; c.noOutSet=false end
    -- Passage de pénalité en cours dans la voie : pits.lua ne le compte ni comme arrêt ni comme visite.
    cmd.penaltyPass=c.entry and a.pit==true
    throttle(t,e,frame,i,a,c,cmd,now,dt)
    giveBack(t,e,frame,i,a,c,cmd,now)
    blueFlags(t,e,frame,i,a,c,now)
   end
  elseif a.player and a.valid and p.sanPlayerTrackLimits and not a.finished and not c.dq then
   -- Beta 1.56 : vos limites de piste (option), jamais le chemin des IA ; votre voiture n'est jamais pilotée.
   if c.lastLap>=0 and a.lap>c.lastLap then lap(t,e,frame,i,a,c,now) end
   c.lastLap=a.lap
   playerLimits(t,e,frame,i,a,c,now,dt,race,ready)
  else c.cutLimit=1; c.outFor=0; c.wasPit=a.pit==true end
  if c.contactRequest>0 then contactConfirm(t,e,frame,i,c,now) end
 end
 if race and p.sanReport and frame.started then t.raceSeen=true end
 t.junction=e.merge.spline; t.junctionSamples=e.merge.samples
end
-- Classement corrigé (course) : à chaque arrivée, voitures arrivées classées par tours puis par heure d'arrivée plus
-- le temps ajouté ; une IA disqualifiée par l'app à la fin. Pénalité aux stands encore due à l'arrivée : ajoutée au
-- résultat si le réglage le veut. Appelé à chaque image par l'overlay (même course finie, moteur arrêté).
local function better(t,x,y)
 local a,b=t.cars[x],t.cars[y]
 if a.finishLaps~=b.finishLaps then return a.finishLaps>b.finishLaps end
 local ta,tb=a.finishAt+a.time,b.finishAt+b.time
 if ta~=tb then return ta<tb end
 return a.finishPos<b.finishPos
end
local function classify(t,e,frame,now)
 local list=t.list; for k=#list,1,-1 do list[k]=nil end
 local slots=t.slots; if not slots then slots={}; t.slots=slots end; for k=#slots,1,-1 do slots[k]=nil end
 local any=false
 for i=1,frame.count do
  local c=t.cars[i]
  if c.finishAt>=0 and not c.dq and not e.penalties.ai.dq[i] then list[#list+1]=i; slots[#slots+1]=c.finishPos; if c.time>0 then any=true end end
 end
 table.sort(list,function(x,y) return better(t,x,y) end); table.sort(slots)
 local rows=t.classRows; for k=#rows,1,-1 do rows[k]=nil end
 local parts={}
 -- Relecture : places d'AC des voitures arrivées redistribuées dans l'ordre corrigé (les autres places ne bougent pas) ;
 -- rien sans pénalité de temps.
 for rank=1,#list do
  local i=list[rank]; local c=t.cars[i]
  local place=any and slots[rank] or c.finishPos; c.corrected=place
  if any and (place~=c.finishPos or c.time>0) then
   if #rows<K.sanClassRows then rows[#rows+1]={text=string.format(L.sanctions142.classRow,place,name(frame.cars[i]),c.time,c.finishPos),kind=place~=c.finishPos and 'warn' or 'text'} end
   if #parts<K.sanClassLog then parts[#parts+1]=string.format('P%d %s%s',place,name(frame.cars[i]),c.time>0 and string.format(' (+%.0f s, AC P%d)',c.time,c.finishPos) or string.format(' (AC P%d)',c.finishPos)) end
  end
 end
 local text=table.concat(parts,', ')
 if any and text~=t.classText then t.classText=text; U.log(e.log,now,'INFO','classement corrige (le classement d AC reste inchange): '..text,-1) end
 rebuild(t)
end
function M.watch(t,frame,e,now)
 if e.profile~='C' or frame.count==0 or not C.on(e.p,'sanctions') then return end
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]
  if a.valid and a.finished and c.finishAt<0 and not a.safetyCar then
   c.finishAt=frame.time; c.finishLaps=a.lap; t.order=t.order+1; c.finishPos=(a.position or 0)>0 and a.position or t.order
   if c.pending~='' and not a.player then
    local kind=c.pending; c.pending=''
    if e.run.sanUnservedTime then
     c.time=c.time+unservedSeconds(e,kind)
     c.rUnserved=c.rUnserved+unservedSeconds(e,kind)
     U.log(e.log,now,'WARN',string.format('sanction IA: %s %s non purge a l arrivee, +%.0f s au resultat',name(a),kindJournal[kind] or kind,unservedSeconds(e,kind)),i)
     event(t,string.format(L.sanctionTexts.time,name(a),unservedSeconds(e,kind),reasonText('ignored')),'warn')
    end
   end
   t.classDirty=true; t.dirty=true
   if a.player then t.playerDoneAt=now end
  end
 end
 if t.classDirty then t.classDirty=false; classify(t,e,frame,now) end
 -- Beta 1.56 : rapport de course (option) une fois par course : toutes les voitures en course arrivées, ou
 -- K.sanReportAfterFinish s après votre arrivée ; lignes reprises par AdvancedIA.lua (écriture par l'applicateur).
 if e.run.sanReport and not t.reportDone and t.raceSeen and t.order>0 then
  local done=true
  for i=1,frame.count do
   local a=frame.cars[i]; local c=t.cars[i]
   if a.valid and not a.safetyCar and c.finishAt<0 and not c.dq and not e.penalties.ai.dq[i] then done=false; break end
  end
  if done or t.playerDoneAt and now-t.playerDoneAt>=K.sanReportAfterFinish then t.reportDone=true; e.reportLines=M.report(t,e,frame,true) end
 end
end
-- Place corrigée d'une voiture arrivée (0 : inconnue).
function M.position(t,i) local c=t.cars[i]; return c and c.finishAt>=0 and c.corrected or 0 end
-- Beta 1.56 : vos limites de piste au récapitulatif de course (nil sans avertissement ni pénalité de l'app).
function M.playerSummary(t,i)
 local c=t.cars[i]
 if not c or c.rWarn+c.trackN==0 then return nil end
 return string.format(L.recapTrackLimits,c.rWarn,c.trackTime)
end
-- Beta 1.56 : rapport de course en CSV (RFC 4180 : champ avec virgule, guillemet ou retour à la ligne entre
-- guillemets, guillemets doublés). Première ligne « # » d'information, en-tête, puis une ligne par voiture dans l'ordre
-- corrigé (voitures non arrivées ensuite, dans l'ordre d'AC). complete : course finie (1) ou interrompue (0).
local reportHeader='corrected_pos,ac_pos,driver,car,class,laps,finished,player,track_warnings,track_penalties,track_time_s,laps_invalidated,'
 ..'throttle_cuts,drive_throughs,stop_and_gos,served,unserved_added_s,give_back_owed,give_back_given,time_added_s,black_flag,contacts'
local function csv(v)
 v=tostring(v)
 if v:find('[,"\r\n]') then return '"'..(v:gsub('"','""'))..'"' end
 return v
end
local function seconds(x) return string.format('%.1f',x) end
function M.report(t,e,frame,complete)
 local order={}
 for i=1,math.min(frame.count,K.maxCars) do
  local a=frame.cars[i]; local c=t.cars[i]
  if (a.valid or c.finishAt>=0) and not a.safetyCar then order[#order+1]=i end
 end
 table.sort(order,function(x,y)
  local a,b=t.cars[x],t.cars[y]
  local fa,fb=a.finishAt>=0 and not a.dq,b.finishAt>=0 and not b.dq
  if fa~=fb then return fa end
  if fa then if a.corrected~=b.corrected then return a.corrected<b.corrected end; return x<y end
  local pa,pb=frame.cars[x].position or 0,frame.cars[y].position or 0
  if pa~=pb then return pa>0 and (pb==0 or pa<pb) end
  return x<y
 end)
 local length=frame.timedRace and string.format('%.0f min',frame.sessionMinutes or 0) or string.format('%d laps',frame.sessionLaps or 0)
 local lines={string.format('# AdvancedIA %s, {date}, %s, %s, complete=%d',C.release,
  csv(frame.track or ''),length,complete and 1 or 0),reportHeader}
 for _,i in ipairs(order) do
  local a=frame.cars[i]; local c=t.cars[i]
  local finished=c.finishAt>=0 and not c.dq
  local driver=c.rName~='' and c.rName or name(a)
  local model=c.rModel~='' and c.rModel or a.id or ''
  -- Classe : rang de la classe des IA (1 la plus rapide) seulement en multiclasse, une fois la classe reconnue.
  local st=e.states[i]; local class=e.run.multiClass and st and st.classified and tostring(st.class) or ''
  lines[#lines+1]=table.concat({finished and c.corrected or '',finished and c.finishPos or (a.position or ''),csv(driver),csv(model),class,
   finished and c.finishLaps or a.lap or 0,finished and 1 or 0,a.player and 1 or 0,c.rWarn,c.trackN,seconds(c.trackTime),c.invalid,
   c.rCut,c.rDrive,c.rStopgo,c.rServed,seconds(c.rUnserved),c.rOwed,c.rGiven,seconds(c.time),csv(c.rBlack~='' and (journalReasons[c.rBlack] or c.rBlack) or ''),c.contacts},',')
 end
 return lines
end
-- Beta 1.56 : course commencée sans rapport (changement de session, déchargement de l'app) : rapport partiel, une fois.
function M.flushReport(t,e,frame)
 if not e.run or not e.run.sanReport or t.reportDone or not t.raceSeen then return nil end
 t.reportDone=true
 return M.report(t,e,frame,false)
end
-- Point de reprise (rechargement de l'app en pleine course) : texte vide tant qu'il n'y a rien à garder.
function M.serialize(t,session)
 local rows=nil
 for i=1,K.maxCars do
  local c=t.cars[i]
  if (c.time>0 or c.count>0 or c.pending~='' or c.strikes>0 or c.dq) and c.identity:match('^[%w_%-]+$') then
   rows=rows or {tostring(session)}
   rows[#rows+1]=string.format('%d,%s,%.1f,%d,%s,%d,%d,%d',i,c.identity,c.time,c.count,c.pending~='' and c.pending or '-',c.pendingLaps,c.strikes,c.dq and 1 or 0)
  end
 end
 return rows and table.concat(rows,'\n') or ''
end
function M.restore(t,text,session)
 t.pending=nil
 if type(text)~='string' or text=='' or #text>K.maxZoneBytes then return end
 local pending={session=session,rows={}}; local first=true
 for line in text:gmatch('[^\n]+') do
  if first then first=false; if line~=tostring(session) then return end
  else
   local index,identity,time,count,kind,laps,strikes,dq=line:match('^(%d+),([%w_%-]+),([%d%.]+),(%d+),([%a%-]+),(%d+),(%d+),([01])$')
   index=tonumber(index)
   if index and index>=1 and index<=K.maxCars and (kind=='-' or kind=='drive' or kind=='stopgo') then
    pending.rows[#pending.rows+1]={index=index,identity=identity,time=math.min(tonumber(time),K.counterMax),count=math.min(tonumber(count),K.counterMax),
     kind=kind=='-' and '' or kind,laps=math.min(tonumber(laps),K.counterMax),strikes=math.min(tonumber(strikes),K.counterMax),dq=dq=='1'}
   end
  end
 end
 if not first then t.pending=pending end
end
return M
