-- Pont vers les apps compagnes (SpotterEnginer : spotter et ingénieur à la voix) : l'état du moteur recopié à chaque
-- image dans une structure partagée (ac.connect, ouverte par Applier.bridgeOpen). Décisions pures, aucune fonction de
-- CSP ici ; le format est décrit par src/bridge_layout.lua, identique dans l'app lectrice. Lecture seule du moteur :
-- rien n'est écrit dans engine, frame ou les réglages, aucune décision ne change (empreintes tests/golden.lua).
-- Publié depuis script.HUMANAI__UPDATE après update(), à chaque image, y compris en pause, en replay, en ligne ou moteur
-- arrêté (champs ready, guard, online, replay, paused) : le battement ne s'arrête qu'au déchargement (closed).
local Layout=require('src/bridge_layout')
-- Relecture 1.59 (signalé par la session SpotterEnginer) : seuils des décisions d'incident pour les valeurs publiées.
local K=require('src/config').K
local M={}
M.layout=Layout
local maxCars=Layout.maxCars
local huge=math.huge
-- Capacité de chaque champ texte (fin de chaîne comprise).
local caps={}
for _,list in ipairs({Layout.hello,Layout.fields}) do for k=1,#list do local f=list[k]; if f[2]=='string' then caps[f[1]]=f[3] end end end
local function finite(x) return type(x)=='number' and x==x and x~=huge and x~=-huge end
local function num(x) if finite(x) then return x end return 0 end
local function int(x,default) if finite(x) then return math.floor(x+0.5) end return default or 0 end
local function bool(x) return x==true end
-- Indice d'AC d'un emplacement du moteur (1..maxCars) ; -1 : aucun.
local function index(slot) if finite(slot) and slot>=1 then return math.floor(slot)-1 end return -1 end
-- Secondes restantes jusqu'à un instant du moteur (0 si passé ou inconnu).
local function left(untilAt,now) if finite(untilAt) and finite(now) and untilAt>now then return untilAt-now end return 0 end
-- Texte coupé à la capacité, jamais au milieu d'un caractère UTF-8.
local function fit(s,cap)
 if #s<cap then return s end
 local n=cap-1
 while n>0 do local c=s:byte(n+1); if not c or c<128 or c>=192 then break end; n=n-1 end
 return s:sub(1,n)
end
function M.new(release)
 return {release=type(release)=='string' and release or '',heartbeat=0,serial=0,texts={},panelDecided=nil,panelKind=nil,
  panelSerial=0,infractions=0,pitClosed=0,wet=nil,wetSerial=0}
end
-- Texte écrit seulement quand il change (la structure garde la valeur précédente).
local function text(b,out,name,value)
 if type(value)~='string' then value='' end
 if b.texts[name]~=value then b.texts[name]=value; out[name]=fit(value,caps[name] or 32) end
end
local EMPTY={}
local function code(list,name) return Layout.code(list,name) end
-- Battement de la structure figée : version du pont, version de l'app, compteur d'images.
function M.beat(b,hello)
 b.heartbeat=b.heartbeat%2147483647+1
 hello.bridgeVersion=Layout.version; hello.heartbeat=b.heartbeat; hello.closed=false
 text(b,hello,'release',b.release)
end
-- Déchargement de l'app : les lecteurs passent aussitôt à « absent ».
function M.close(b,hello) if hello then hello.closed=true; hello.heartbeat=b.heartbeat end end
local function cars(out,e,frame,now)
 local list=out.cars
 local count=math.min(int(frame.count),maxCars)
 local incidents=(e.incidents or EMPTY).cars or EMPTY
 local sanctions=(e.sanctions or EMPTY).cars or EMPTY
 local ai=(e.penalties or EMPTY).ai or EMPTY
 local aiCount,aiDq=ai.count or EMPTY,ai.dq or EMPTY
 local strategy=(e.strategy or EMPTY).cars or EMPTY
 local pits=(e.pits or EMPTY).cars or EMPTY
 local commands=e.commands or EMPTY
 local states=e.states or EMPTY
 local fcars=frame.cars or EMPTY
 for i=1,maxCars do
  local c=list[i-1]
  local a=i<=count and fcars[i] or nil
  if not a or not a.valid then
   c.valid=false
  else
   c.valid=true; c.safety=bool(a.safetyCar); c.pit=bool(a.pit)
   local ic=incidents[i] or EMPTY
   -- Relecture 1.59 : spin, wrong et halt sont des durées (secondes) dans src/incidents.lua : publiés avec les seuils de
   -- la décision d'incident (tête-à-queue : décision c.spun de la 1.59, perte de vitesse comprise). onTrack : voiture en
   -- piste à cette image, pour toutes les voitures (le c.onTrack interne n'est tenu que pendant un incident).
   c.incident=bool(ic.incident); c.onTrack=not bool(a.offtrack); c.still=num(ic.still)
   c.halt=num(ic.halt)>=K.obstacleTime; c.spin=bool(ic.spun); c.wrong=num(ic.wrong)>=K.wrongWayTime
   local sc=sanctions[i] or EMPTY
   c.strikes=int(sc.strikes); c.sanctions=int(sc.count); c.timeAdded=num(sc.time); c.pending=code(Layout.pending,sc.pending)
   c.pendingLaps=int(sc.pendingLaps); c.cutLeft=num(sc.cutLeft); c.sanctionDq=bool(sc.dq); c.owedTo=index(sc.owedTo)
   c.flagOffences=int(aiCount[i]); c.flagDq=bool(aiDq[i])
   local st=strategy[i] or EMPTY
   c.planned=bool(st.planned); c.plannedStops=int(st.stops,-1); c.nextStopLap=int(st.nextLap,-1); c.stopCause=code(Layout.causes,st.cause)
   c.stopLimit=code(Layout.limits,st.limit); c.failure=code(Layout.failures,st.failKind); c.critical=bool(st.critical)
   local cmd=commands[i] or EMPTY
   c.called=bool(st.wanted) or bool(cmd.stratCalled)
   local pc=pits[i] or EMPTY
   c.stops=int(pc.stops); c.boxed=bool(pc.boxed); c.stintFor=finite(pc.lastStop) and pc.lastStop>0 and math.max(0,now-pc.lastStop) or -1
   c.mistakeId=int(cmd.mistakeId); c.mistakeKind=code(Layout.mistakes,cmd.mistakeKind)
   c.overtake=bool((states[i] or EMPTY).overtakeArmed)
  end
 end
end
-- Recopie de l'état : e moteur, frame image lue, appelé une fois par image (après update()).
function M.publish(b,out,e,frame)
 if not out or not e or not frame then return end
 local g=e.g or EMPTY; local p=e.run or EMPTY; local now=num(e.time)
 b.serial=b.serial%2147483647+1
 out.serial=b.serial
 out.enabled=bool(g.enabled); out.ready=e.guard=='ready'; out.panic=bool(e.panic)
 out.online=bool(frame.online); out.replay=bool(frame.replay); out.paused=bool(frame.paused)
 text(b,out,'guard',e.guard); text(b,out,'profile',e.profile); text(b,out,'language',g.language)
 out.session=int(e.session,-1); out.sessionType=int(e.sessionType,-1); out.clock=now
 local slot=int(frame.player); out.player=index(slot); out.carCount=int(frame.count)
 local player=slot>0 and (frame.cars or EMPTY)[slot] or EMPTY
 -- Feux et drapeau du joueur
 local l=e.lights or EMPTY
 out.flagOwned=bool(frame.flagOwned); out.lightsValue=int(l.value); text(b,out,'lightsReason',l.reason); out.nativeFlag=int(frame.flag)
 out.slowCar=index(l.slowSlot); out.slowGap=num(l.slowGap); out.meatballLeft=left(l.meatballUntil,now); out.damaged=bool(l.damaged)
 -- Panneau : compteur avancé à chaque changement de ce qui est décidé ou montré
 local panel=e.panel or EMPTY
 if panel.decided~=b.panelDecided or panel.kind~=b.panelKind then
  b.panelDecided=panel.decided; b.panelKind=panel.kind; b.panelSerial=b.panelSerial%2147483647+1
 end
 text(b,out,'panelDecided',panel.decided); text(b,out,'panelKind',panel.kind); out.panelSerial=b.panelSerial
 text(b,out,'panelTitle',panel.title); text(b,out,'panelShort',panel.short)
 out.panelDouble=bool(panel.double); out.panelBlueGap=num(panel.blueGap); out.panelNoPass=bool(panel.noPass)
 out.panelLit=int(panel.lit); out.panelInfractions=int(panel.infractions); out.panelInfractionMax=int(panel.infractionMax)
 out.warnLeft=left(panel.warnUntil,now)
 -- Direction de course
 local t=e.incidents or EMPTY
 out.neutral=bool(t.neutral); text(b,out,'neutralMode',t.neutral and t.neutralMode or '')
 out.neutralFor=t.neutral and finite(t.neutralSince) and math.max(0,now-t.neutralSince) or 0
 out.escalated=bool(t.escalated); out.relaunch=bool(t.relaunch); out.ending=bool(t.ending); out.endingLeft=left(t.endingUntil,now)
 -- Beta 1.48 : pose en piste annoncée comme l'appel (vocabulaire du pont v1 inchangé).
 text(b,out,'safetyPhase',(t.safetyPhase=='place' or t.safetyPhase=='exit') and 'call' or t.safetyPhase); out.safetyFailed=bool(t.safetyFailed); out.safetyCar=index(t.safety)
 out.red=bool(t.red); out.reds=int(t.reds); out.greenLeft=left(t.greenUntil,now)
 out.restart=bool(t.restart); out.playerRestart=bool(t.playerRestart)
 -- Beta 1.60 (tranche E) : tour de formation du départ ('form'), appel du départ lancé ('roll') ; sinon comme avant.
 -- Beta 1.60 (contrat avec SpotterEnginer, qui juge sur les fronts) : « form » (puis « roll » à l'appel du départ lancé)
 -- monte dans la même image que neutral et relaunch, et ne retombe jamais avant eux : un tour de formation abandonné
 -- sur incident reste « form » tant que sa neutralisation dure (FCY, puis départ lancé au drapeau vert).
 text(b,out,'standing',(t.formation or t.formationAborted and t.neutral) and (t.rollCall and 'roll' or 'form') or t.standing); out.gridLit=int(t.gridLit); out.gridSlot=int(t.gridSlot); out.gridGap=num(t.gridGap)
 out.gridPlaced=bool(t.gridPlaced); out.gridPassed=bool(t.gridPassed); out.jumpLeft=left(t.jumpUntil,now)
 out.pitsClosed=bool(t.pitsClosed); out.slipperyLeft=left(t.slipperyUntil,now)
 out.zone=bool(t.playerZone); out.zoneInside=bool(t.playerInside); out.zoneDouble=bool(t.playerZoneDouble)
 out.zoneCar=index(t.playerZoneSlot); out.zoneDistance=num(t.playerToZone); out.incidentDistance=num(t.playerDistance)
 out.noPass=bool(t.playerNoPass); out.yellow=bool(t.playerYellow); out.zoneCount=int(t.zoneCount)
 text(b,out,'drsReason',t.drsReason); out.drsLapsLeft=int(t.drsLapsLeft,-1); out.pitDue=int(t.playerPitDue); out.pitRemind=bool(t.playerPitRemind)
 -- Dernière annonce (texte prêt, celui de l'overlay)
 out.messageId=int(t.messageId); text(b,out,'messageKind',t.messageKind); out.messageValue=num(t.messageValue); out.messageExtra=num(t.messageExtra)
 text(b,out,'messageTitle',e.ownTitle); text(b,out,'messageText',e.ownText)
 -- Delta
 local d=e.delta or EMPTY
 out.deltaOn=finite(d.value); out.deltaValue=num(d.value); text(b,out,'deltaKind',d.kind)
 if d.infraction then b.infractions=b.infractions%2147483647+1 end
 out.deltaInfraction=b.infractions; text(b,out,'deltaInfractionKind',d.infractionKind); out.deltaInfractionValue=num(d.infractionValue)
 out.deltaBeep=int((e.deltaBeep or EMPTY).beepId)
 -- Pénalités du joueur
 local pen=e.penalties or EMPTY
 out.penaltyId=int(pen.requestId); text(b,out,'penaltyReason',pen.reason); out.penaltyCount=int(pen.count); out.penaltySeconds=num(pen.seconds)
 text(b,out,'penaltyKind',pen.kind); out.disqualified=bool(pen.disqualified); out.penaltyPassed=index(pen.passed)
 out.giveBack=index(pen.giveBack); out.giveBackLeft=left(pen.giveBackUntil,now)
 out.redPending=bool(pen.redPending); out.stopPending=bool(pen.stopPending); out.jumpPending=bool(pen.jumpPending)
 out.penaltyLimit=int(p.penaltyDisqualify); out.nativePenalty=int(player.penaltyType); out.nativePenaltyParam=int(player.penaltyParam)
 -- DRS, appel de phares
 out.drsBeep=int((e.drs or EMPTY).beepId); out.playerDrs=int(e.playerDrs,-1)
 out.drsBlocked=slot>0 and bool(((e.commands or EMPTY)[slot] or EMPTY).drsBlock) or false
 local fl=e.flash or EMPTY; out.flashId=int(fl.eventId); out.flashHeard=int(fl.heard)
 -- Arrêts
 local pits=e.pits or EMPTY
 text(b,out,'pitState',pits.state)
 if pits.justClosed then b.pitClosed=b.pitClosed%2147483647+1 end
 out.pitClosedSerial=b.pitClosed; out.pitCsp=bool(pits.csp); out.pitPosition=num(pits.position); out.pitOpen=num(pits.open); out.pitClose=num(pits.close)
 out.pitDone=int(pits.done); out.pitTotal=int(pits.total); out.pitWaived=bool(pits.waived)
 out.mandatoryStops=int(p.mandatoryStops); out.maxStintMin=num(p.maxStintMin); out.minPitTime=num(p.minPitTime)
 local own=slot>0 and (pits.cars or EMPTY)[slot] or EMPTY
 out.playerStops=int(own.stops); out.playerStintFor=finite(own.lastStop) and own.lastStop>0 and math.max(0,now-own.lastStop) or -1
 -- Course
 local race=e.race or EMPTY
 out.raceProgress=num(race.progress); out.raceLapsLeft=num(race.lapsLeft); out.raceKnown=bool(race.known)
 local wet=bool((e.weather or EMPTY).wet)
 if b.wet~=nil and wet~=b.wet then b.wetSerial=b.wetSerial%2147483647+1 end
 b.wet=wet; out.wet=wet; out.wetSerial=b.wetSerial
 local hud=e.hud or EMPTY
 out.finished=bool(hud.finished); out.dnf=bool(hud.dnf); out.dq=bool(hud.dq)
 out.finalPosition=int(hud.final); out.gridPosition=int(hud.grid); out.correctedPosition=int(hud.corrected)
 out.aiSerial=int(hud.aiSerial); text(b,out,'aiCode',hud.aiCode); text(b,out,'aiTitle',hud.aiTitle); text(b,out,'aiShort',hud.aiShort); out.aiBlack=bool(hud.aiBlack)
 if out.cars then cars(out,e,frame,now) end
end
return M
