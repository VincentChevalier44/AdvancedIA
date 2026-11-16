-- Incidents de piste, drapeaux jaunes et neutralisations : décisions pures. Lecture dans snapshot, écritures dans applier.
local U=require('src/util')
local K=require('src/config').K
local Delta=require('src/delta')
local Grid=require('src/grid')
local min,max=math.min,math.max
local M={}
-- Beta 1.63 (course du pilote à Suzuka : 70 incidents au même virage, point difficile armé mais IA toujours trop
-- rapides ; carnage sans drapeau rouge, « piste encore passable »). Zone dangereuse : un point difficile armé plafonne
-- la vitesse des IA de dangerBefore m avant à K.hotspotMeters m après lui, à (1 - dangerPct[niveau]) fois leur allure
-- apprise à chaque endroit ; niveau relevé après dangerRaise nouveaux incidents tout près. Drapeau rouge sur carnage :
-- au moins carnageCars voitures accidentées ou arrêtées dans les mêmes carnageSpan m en moins de carnageWindow s.
-- Correctif 1.63 (relance après drapeau rouge, Suzuka du 13 novembre) : releaseDist / releaseMax : IA retenues aux stands
-- jusqu'à ce que la voiture de sécurité ait roulé releaseDist m en piste (au plus releaseMax s).
-- leaveStill : tour de relance : encore immobile à son emplacement ce délai (s) après sa libération : posée (Imola, 13
-- novembre : 10 s à 0 km/h pendant que les IA sortaient avant elle).
-- calm : voie des stands calme ce délai (s) avant la reprise.
local RK={releaseDist=150,releaseMax=30,leaveStill=4,calm=3}
local DK={dangerBefore=150,dangerPct={0.04,0.07},dangerRaise=2,carnageCars=5,carnageSpan=200,carnageWindow=60,carnageStill=10}
M.DK=DK
-- Beta 1.64, lot 5 (décisions du pilote du 13 novembre : procédures de la voiture de sécurité). Dédoublement : settle
-- s entre la file formée et la première autorisation (zigzags éteints avant) ; une attardée a un tour de voiture de
-- sécurité à K.scNominalKmh (borné à passMin..passMax s) pour la doubler ; budget s au plus depuis la file formée ; au
-- moins minLaps tours restants ; la voiture de sécurité attend son passage de la ligne au plus doneLaps tours ;
-- l'autorisée roule au plus rel km/h plus vite que la voiture qu'elle double. Arrivée neutralisée : damier attendu
-- finalCross s au passage du meneur ; borne lointaine finalMax tours mesurés ; tenue après le damier du meneur au plus
-- holdLaps tour à K.scNominalKmh.
local SK={settle=2,passMin=60,passMax=180,budget=600,minLaps=3,doneLaps=1.5,rel=30,finalCross=3,finalMax=3,holdLaps=1}
M.SK=SK
-- Beta 1.60 (correctif, pont) : une voiture roule à contresens quand elle avance nez en premier contre le sens de la
-- piste : son déplacement depuis l'image précédente (lastX, lastZ) va dans le sens de son cap. Une voiture qui recule
-- (quitte un mur en marche arrière) est dans le bon sens. Utilisé ici et par src/sanctions.lua (drapeau noir).
function M.noseFirst(a,lastX,lastZ) return (a.x-lastX)*a.lx+(a.z-lastZ)*a.lz>0 end
local function clearCar(c)
 c.incident=false; c.dismissed=false; c.since=0; c.spline=0; c.onTrack=false; c.clearedAt=-math.huge; c.wrong=0; c.spin=0; c.contact=false; c.lastSpline=-1; c.calm=0
 c.still=0; c.halt=0; c.moved=false; c.fresh=true; c.slow=0; c.counted=false; c.lastCrash=-math.huge; c.window=0; c.windowStart=-math.huge; c.crashAt=-math.huge; c.holding=false; c.holdUntil=0; c.holdMax=0; c.announced=false
 c.restart=false; c.restartLast=0; c.stuckFor=0; c.anchorX=math.huge; c.anchorZ=math.huge
 -- Beta 1.63 : redémarrage d'une IA accidentée qui peut encore rouler (rejoin).
 c.zoneOpen=false; c.zoneOpenAt=0; c.zoneDouble=false
 c.rejoining=false; c.rejoinTries=0; c.rejoinId=c.rejoinId or 0; c.rejoinNext=-math.huge; c.rejoinSince=nil; c.rejoinX=0; c.rejoinZ=0; c.cannot=nil; c.noRetireNoted=false
 -- Beta 1.60 : surveillance de la voiture de sécurité (derrière elle, l'a doublée, vue devant elle).
 c.scBehind=false; c.scPassed=false; c.scPassedAt=-math.huge; c.scAhead=false; c.scLift=false
 -- Beta 1.60 : voiture en difficulté sous drapeau (src/director.lua) : dépassement permis.
 c.trouble=false
 -- Beta 1.59 : vitesse au début de la glissade, tête-à-queue confirmé (perte de vitesse), zone double (arrêtée ou au pas).
 c.spinFrom=0; c.spun=false; c.double=false; c.backOn=0; c.hotspotFed=false; c.dangerFed=false
 -- Beta 1.63 : début du dernier accident (tête-à-queue ou arrêt) et endroit, pour le drapeau rouge sur carnage.
 c.wreckAt=-math.huge; c.wreckSpline=0
 -- Beta 1.64 (lot 2) : départ avorté : voiture à l'origine (marque), place de la grille avortée, retenue sur place.
 c.abortMark=false; c.abortSlot=0; c.abortHold=false; c.abortHoldAt=0
 -- Beta 1.64 (lot 5) : autorisée ou dédoublée pendant le dédoublement ; exemptée des règles à cette image (recalculé).
 c.unlapOut=false; c.scFree=false
end
-- Beta 1.64 (lot 5) : dédoublement remis à zéro (aucune autorisée, aucune exemptée).
local function unlapClear(t)
 t.unlapState='none'; t.unlapCar=0; t.unlapN=0; t.unlapK=0; t.unlapRelease=false
 t.unlapTail=0
 for i=1,K.maxCars do t.cars[i].unlapOut=false; t.cars[i].scFree=false end
end
function M.new()
 local t={cars={},zones={},zoneCount=0,activeCount=0,holdCount=0,neutral=false,neutralMode='local',neutralSince=0,neutralUntil=0,
  safety=0,safetyPhase='none',safetySince=0,safetyStill=0,safetyFailed=false,safetyLeft=false,started=0,held=0,onTrack=0,red=false,redSince=0,redCancelled=false,reds=0,redTotal=0,redInPits=0,
  greenUntil=-math.huge,playerZone=false,playerInside=false,playerToZone=0,playerLead=0,playerNoPass=false,playerZoneSlot=0,suppressed={queue=0,spawn=0,crawl=0},playerDistance=0,freshOnTrack=0,redEnd=-math.huge,redMax=0,neutralEnd=-math.huge,frameId=0,messagePriority=0,messageFrame=-1,
  playerFlag=false,playerYellow=false,focusYellow=false,playerWarn=false,playerWarnDistance=0,playerWarnSlot=0,playerZoneDouble=false,slipperyUntil=-math.huge,messageId=0,messageKind='',messageValue=0,messageExtra=0,messageText='',
  standing='none',gridReady=false,gridWhy='',gridLit=0,gridSlot=0,gridGap=0,gridPit=false,gridPlaced=false,gridPassed=false,jumpUntil=-math.huge,
  relaunchLeader=0,relaunchSpline=0,relaunchTravel=0,relaunchSpanUntil=-math.huge,
  formation=false,formationKind='',formationAborted=false,formationExtra=0,formationKmh=0,rollGo=false,rollCall=false,relaunchToLine=math.huge,
  relaunch=false,escalated=false,ending=false,endingUntil=0,restart=false,restartSince=0,playerRestart=false,pitsClosed=false,releaseAt={},
  gate={},gateSince={},openedAt={},releaseList={},releaseN=0,redOrder={},redRank={},redOrderN=0,restored={},junction=-1,
  safetyPlaceSince=-math.huge,safetyTarget=-1,safetyRef=0,safetyFrom='',safetySlow=false,safetyLastSpline=-1,parkingSince=-math.huge,firstOut=0,firstOutSpline=0,
  restartRank=0,restartAhead=0,restartState='',restartTarget=0,
  -- Beta 1.59 : incidents récents (point difficile) et points difficiles armés.
  recent={},recentN=0,hotspots={},hotspotN=0,hotspotSeen={},hotspotPause=false,hotspotForget=K.hotspotForget}
 -- Beta 1.64 (lot 2) : départs avortés de suite, tour en plus à armer, départ lancé imposé, marques et retenues.
 t.startAborts=0; t.startAbortPending=false; t.startAbortRoll=false; t.abortMarks=0; t.abortHolds=0
 -- Beta 1.64 (lot 5) : dédoublement (liste figée préallouée) et arrivée neutralisée.
 t.unlapList={}; t.unlapTried=false; t.unlapDone=0; t.unlapAt=-math.huge; t.unlapNext=-math.huge; t.unlapUntil=-math.huge; t.unlapDoneAt=-math.huge; t.unlapLast=-1
 t.scFinal=false; t.scFinalOff=false; t.scFinalAt=-math.huge; t.scFinalLaps=0; t.scCrossAt=-math.huge; t.scCrossLeft=0; t.scExtra=false; t.scFlagAt=-math.huge; t.leadLaps=-1; t.leadLapAt=-math.huge; t.leadLapDur=0
 -- Relecture 164e : tours du meneur au temps écoulé (course au temps, -1 : du temps reste), dernière voiture de la file.
 t.zeroLaps=-1; t.unlapTail=0
 for i=1,K.maxCars do
  t.unlapList[i]=0
  t.releaseAt[i]=-math.huge; t.gate[i]=false; t.gateSince[i]=-math.huge; t.openedAt[i]=-math.huge
  local c={identity=''}; clearCar(c); c.crashes=0; t.cars[i]=c
  t.zones[i]={slot=0,spline=0,onTrack=false}
 end
 for k=1,K.hotspotRecent do t.recent[k]={spline=0,at=-math.huge} end
 unlapClear(t)
 return t
end
-- Beta 1.48 : ordre figé au drapeau rouge (sortie des stands, grille, overlay, dépassements permis pour reprendre sa
-- place) : effacé quand toutes les voitures ont franchi la ligne, à l'extinction des feux ou au drapeau rouge suivant.
local function clearOrder(t)
 t.redOrderN=0; for i=1,K.maxCars do t.redRank[i]=nil end
 for key in pairs(t.restored) do t.restored[key]=nil end
 if t.restoreBehind then for key in pairs(t.restoreBehind) do t.restoreBehind[key]=nil end end
 t.restartRank=0; t.restartAhead=0; t.restartState=''; t.restartTarget=0
end
M.clearOrder=clearOrder
-- Relecture 1.52 : rappels et avis des stands du joueur (écrits par engine.lua, lus par le panneau et le pont) vidés au
-- changement de session et app à l'arrêt (jamais ceux de la session précédente).
local noTyres={}
function M.clearPlayerPit(t)
 t.playerPitDue=0; t.playerPitRemind=false; t.playerPitShowRemind=false; t.playerPitCompound=false; t.playerPitHint=false; t.playerTyre=''; t.playerTyreOthers=noTyres
 t.playerPlan=''; t.playerPlanned=''; t.playerPlanNotice=false; t.playerPitNotice=''; t.playerPitFrom=''; t.playerPitTo=''
end
function M.reset(t)
 t.heldKind=nil
 M.clearPlayerPit(t)
 for i=1,K.maxCars do clearCar(t.cars[i]) end
 t.zoneCount=0; t.activeCount=0; t.holdCount=0; t.neutral=false; t.neutralUntil=0; t.playerFlag=false; t.playerYellow=false; t.playerWarn=false; t.playerWarnSlot=0; t.playerWarnDistance=0; t.safetyPhase='none'; t.red=false; t.onTrack=0; t.playerZone=false; t.playerInside=false; t.slipperyUntil=-math.huge
 t.safetyStill=0; t.safetyFailed=false; t.safetyLeft=false; t.exitLeftAt=-math.huge; t.safetyReturnAt=-math.huge; t.safetyHide=false; t.scLeadAnnounced=false; t.restartWas=''; t.restartTargetWas=0; t.escalated=false; t.relaunch=false; t.ending=false; t.restart=false; t.playerRestart=false; t.pitsClosed=false
 for i=1,K.maxCars do t.releaseAt[i]=-math.huge; t.gate[i]=false; t.gateSince[i]=-math.huge; t.openedAt[i]=-math.huge end
 t.releaseN=0; clearOrder(t); t.safetyPlaceSince=-math.huge; t.safetyTarget=-1; t.safetySlow=false; t.safetyLastSpline=-1; t.parkingSince=-math.huge; t.firstOut=0
 t.standing='none'; t.gridLit=0; t.jumpUntil=-math.huge; t.gridPlaced=false; t.gridPassed=false
 t.relaunchLeader=0; t.relaunchTravel=0; t.relaunchSpanUntil=-math.huge
 t.formation=false; t.formationKind=''; t.formationAborted=false; t.formationExtra=0; t.rollGo=false; t.rollCall=false; t.relaunchToLine=math.huge
 t.recentN=0; for k=1,K.hotspotRecent do t.recent[k].at=-math.huge end; t.hotspotN=0; t.pausedRecent=nil
 t.startAborts=0; t.startAbortFrom=nil; t.startAbortPending=false; t.startAbortRoll=false; t.abortMarks=0; t.abortHolds=0
 -- Beta 1.64 (lot 5) : dédoublement et arrivée neutralisée oubliés.
 unlapClear(t); t.unlapTried=false; t.scFinal=false; t.scFinalOff=false; t.scFlagAt=-math.huge; t.scCrossAt=-math.huge; t.scExtra=false; t.leadLaps=-1; t.leadLapAt=-math.huge; t.leadLapDur=0
 t.zeroLaps=-1
end
function M.rebase(t,amount)
 t.neutralSince=t.neutralSince-amount; t.neutralUntil=t.neutralUntil-amount; t.safetySince=t.safetySince-amount; t.redSince=t.redSince-amount
 if U.finite(t.redEnd) then t.redEnd=t.redEnd-amount end
 for k=1,K.hotspotRecent do local r=t.recent[k]; if U.finite(r.at) then r.at=r.at-amount end end
 for k=1,t.hotspotN do local h=t.hotspots[k]; h.at=h.at-amount end
 if U.finite(t.neutralEnd) then t.neutralEnd=t.neutralEnd-amount end
 if U.finite(t.greenUntil) then t.greenUntil=t.greenUntil-amount end
 if U.finite(t.slipperyUntil) then t.slipperyUntil=t.slipperyUntil-amount end
 t.endingUntil=t.endingUntil-amount; t.restartSince=t.restartSince-amount
 if U.finite(t.jumpUntil) then t.jumpUntil=t.jumpUntil-amount end
 if U.finite(t.relaunchSpanUntil) then t.relaunchSpanUntil=t.relaunchSpanUntil-amount end
 if U.finite(t.safetyPlaceSince) then t.safetyPlaceSince=t.safetyPlaceSince-amount end
 if U.finite(t.exitLeftAt) then t.exitLeftAt=t.exitLeftAt-amount end
 if U.finite(t.safetyReturnAt) then t.safetyReturnAt=t.safetyReturnAt-amount end
 if U.finite(t.parkingSince) then t.parkingSince=t.parkingSince-amount end
 -- Relecture 1.52 : annonce de l'arrêt F1 en attente (M.flushHeld) décalée aussi.
 if U.finite(t.heldAt) then t.heldAt=t.heldAt-amount end
 -- Relecture 164d : heure du dernier message (attente du message de la course sprint, engine.lua) décalée aussi.
 if U.finite(t.messageAt) then t.messageAt=t.messageAt-amount end
 -- Beta 1.64 (lot 5) : heures du dédoublement et de l'arrivée neutralisée décalées aussi.
 if U.finite(t.unlapAt) then t.unlapAt=t.unlapAt-amount end
 if U.finite(t.unlapNext) then t.unlapNext=t.unlapNext-amount end
 if U.finite(t.unlapUntil) then t.unlapUntil=t.unlapUntil-amount end
 if U.finite(t.unlapDoneAt) then t.unlapDoneAt=t.unlapDoneAt-amount end
 if U.finite(t.scFinalAt) then t.scFinalAt=t.scFinalAt-amount end
 if U.finite(t.scCrossAt) then t.scCrossAt=t.scCrossAt-amount end
 if U.finite(t.scFlagAt) then t.scFlagAt=t.scFlagAt-amount end
 if U.finite(t.leadLapAt) then t.leadLapAt=t.leadLapAt-amount end
 for i=1,K.maxCars do
  local c=t.cars[i]
  for _,key in ipairs({'since','clearedAt','windowStart','crashAt','wreckAt','holdUntil','holdMax','lastCrash','holdStart','abortHoldAt'}) do if U.finite(c[key]) then c[key]=c[key]-amount end end
  if U.finite(t.releaseAt[i]) then t.releaseAt[i]=t.releaseAt[i]-amount end
  if U.finite(t.gateSince[i]) then t.gateSince[i]=t.gateSince[i]-amount end
  if U.finite(t.openedAt[i]) then t.openedAt[i]=t.openedAt[i]-amount end
 end
end
-- Un seul message affiché par image : le plus important l'emporte (rouge, neutralisation, vert, jaune, stands, météo).
local priorities={penaltyDq=5,aiDq=4,aiBlackFlag=4,aiSanction=2,playerSanction=3,penaltyDelta=5,penaltyPass=5,penaltyRed=5,penaltyStop=5,red=5,redSession=5,sessionResume=3,redRestartSc=4,standing=4,penaltyJump=5,redRestartVsc=4,redRestartFcy=4,sc=4,fcy=4,vsc=4,vscEnd=4,scIn=3,green=3,restart=3,yellow=2,pitOpen=1,pitOpenCsp=1,pitCompound=1,pitPlanSame=1,pitPlanOk=1,fastCar=1,pitNotCounted=2,pitValidated=1,wet=1,dry=1,drsLaps=1,drsOn=1,drsWet=1,scOut=3,scLeading=2,restartPlace=2,restartRetake=2,formation=4,rollStart=2,rollGreen=3}
priorities.jumpWarn=3; priorities.jumpFlagrant=5 -- Beta 1.61 : faux départs gradués (startRealism)
priorities.playerContact=3 -- Beta 1.60 : vos contacts en tort (sanPlayerContact), comme vos limites de piste
priorities.pitSprint=1 -- Beta 1.64, lot 4 : course sprint, aucun arrêt obligatoire (dit au départ)
priorities.startDelayed=4 -- Beta 1.64 : départ avorté (comme formation)
priorities.scUnlap=3; priorities.scFinish=4 -- Beta 1.64, lot 5 : attardée autorisée à se dédoubler, arrivée neutralisée
-- Beta 1.49 : annonces de l'arrêt F1 du joueur (lues par SpotterEnginer) : jamais perdues. Écartées par une annonce plus
-- importante de la même image, ou remplacées par elle, elles attendent (une seule place, la dernière l'emporte) la
-- première image suivante sans annonce (M.flushHeld, en fin d'image), au plus K.heldMessageMax s.
local held={pitCompound=true,pitPlanSame=true,pitPlanOk=true,pitNotCounted=true,pitValidated=true,scOut=true,scLeading=true,restartPlace=true,restartRetake=true,rollStart=true}
held.scUnlap=true; held.scFinish=true -- Beta 1.64, lot 5 : jamais perdues (overlay, SpotterEnginer)
-- Beta 1.64, lot 4 (relecture 164d) : la course sprint n'attend pas ici (message affiché à l'écran) : elle est émise hors
-- des annonces du départ et redemandée si elle est écartée (src/pits.lua, M.confirmSprint).
-- Ordre d'émission (seq) : la place d'attente garde la dernière émise.
local function hold(t,kind,value,extra,text,seq)
 if t.heldKind and (t.heldSeq or 0)>seq then return end
 t.heldKind=kind; t.heldValue=value or 0; t.heldExtra=extra or 0; t.heldText=text or ''; t.heldFrame=t.frameId; t.heldAt=t.now or 0; t.heldSeq=seq
end
local function message(t,kind,value,extra,text)
 local priority=priorities[kind] or 0
 t.messageSeq=(t.messageSeq or 0)+1
 if t.messageFrame==t.frameId and priority<t.messagePriority then
  if held[kind] then hold(t,kind,value,extra,text,t.messageSeq) end
  return
 end
 if t.messageFrame==t.frameId and held[t.messageKind] then hold(t,t.messageKind,t.messageValue,t.messageExtra,t.messageText,t.messageSeqShown or 0) end
 t.messageId=t.messageId%K.counterMax+1; t.messageKind=kind; t.messageValue=value or 0; t.messageExtra=extra or 0; t.messageText=text or ''
 t.messageFrame=t.frameId; t.messagePriority=priority; t.messageSeqShown=t.messageSeq
 -- Relecture 164d : heure du dernier message publié (t.now de l'image, nil avant la première).
 t.messageAt=t.now
end
-- Annonce de l'arrêt F1 en attente : publiée à la première image suivante qui n'en a aucune ; oubliée après
-- K.heldMessageMax s.
function M.flushHeld(t,now)
 if not t.heldKind then return end
 if now-(t.heldAt or now)>K.heldMessageMax then t.heldKind=nil; return end
 if t.heldFrame==t.frameId or t.messageFrame==t.frameId then return end
 local kind,value,extra,text=t.heldKind,t.heldValue,t.heldExtra,t.heldText
 t.heldKind=nil
 message(t,kind,value,extra,text~='' and text or nil)
end
local function note(t,level,text,index) if t.note then t.note(level,text,index) end end
-- Voiture de sécurité indisponible (immobilisée en piste, ou jamais sortie de la voie des stands) : ramenée à son stand,
-- la neutralisation continue en FCY.
local function unavailable(t,text)
 t.safetyStill=0; t.safetyPhase='parked'; note(t,'WARN',text,t.safety)
 if t.neutral and t.neutralMode=='sc' then t.safetyFailed=true; t.neutralMode='fcy'; note(t,'INFO','neutralisation: fcy (voiture de securite indisponible)',-1) end
end
M.message=message
-- Reprise derrière la voiture de sécurité (et après le tour de relance d'un drapeau rouge) : dépassement interdit pour
-- chaque voiture en piste jusqu'à son passage de la ligne.
local function restart(t,frame,now,p)
 t.restart=false; t.restartSince=now
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]
  c.restart=a.valid and not a.pit and not a.finished and a.splineValid; c.restartLast=a.spline
  t.restart=t.restart or c.restart
 end
 if p.yellowMessage then message(t,'restart') end
end
-- Extinction des feux d'un départ arrêté (Beta 1.36) : dépassement permis aussitôt pour toutes les voitures, joueur
-- compris, comme à un vrai départ arrêté ; la règle « jusqu'à la ligne » ne vaut que pour un départ lancé.
-- Beta 1.64 (lot 2) : fin de tout départ avorté (compteur, origine, marques, retenues) ; rien à faire le plus souvent.
function M.clearStartAbort(t)
 if (t.startAborts or 0)==0 and (t.abortMarks or 0)==0 and (t.abortHolds or 0)==0 and not t.startAbortFrom and not t.startAbortPending and not t.startAbortRoll then return end
 t.startAborts=0; t.startAbortFrom=nil; t.startAbortPending=false; t.startAbortRoll=false; t.abortMarks=0; t.abortHolds=0
 if t.cars then for i=1,#t.cars do local c=t.cars[i]; c.abortMark=false; c.abortSlot=0; c.abortHold=false end end
end
function M.lightsOut(t)
 M.clearStartAbort(t)
 if t.redOrderN>0 then clearOrder(t); note(t,'INFO','reprise: ordre du drapeau rouge leve (extinction des feux)',-1) end
 if not t.restart then return end
 for i=1,#t.cars do t.cars[i].restart=false end
 t.restart=false; t.playerRestart=false
 note(t,'INFO','reprise: depassement permis a l extinction des feux',-1)
end
-- Fin du tour de relance d'un drapeau rouge en course (Beta 1.34) : départ arrêté si les règles le demandent et que
-- tout est prêt (t.gridReady, décidé par le moteur : capacités, sens latéral, piste), sinon départ lancé (raison au
-- journal). Dépassement interdit jusqu'à la ligne, juste devant la grille.
-- Beta 1.60 (tranche E) : force (fin du tour de formation du départ de la course) : true = départ arrêté quelles que
-- soient les règles de relance ; false = jamais (départ lancé choisi, ou tour de formation abandonné) ; nil = relance
-- d'un drapeau rouge, comme avant.
local function standing(t,frame,now,p,profile,force)
 if force==false then return false end
 if force~=true then
 if profile~='C' or p.redRestart~='standing' then return false end
 -- Beta 1.64 (lot 2) : au-delà de K.startAbortMax départs avortés après un drapeau rouge : départ lancé à la fin du tour.
 if t.startAbortRoll then note(t,'INFO',string.format('relance: depart lance apres %d departs avortes',t.startAborts or 0),-1); return false end
 -- Correctif 1.64 (décision du pilote, 13 novembre) : reprise forcée au délai maximal, obstacle encore en piste à la fin du
 -- tour de relance : départ lancé (jamais une grille devant une voiture arrêtée) ; parti entre-temps : départ arrêté.
 local obstacle=t.redObstacle==true and t.onTrack>0; t.redObstacle=false
 if obstacle then note(t,'INFO','relance arretee indisponible (piste non degagee): depart lance',-1); return false end
 end
 if not t.gridReady then note(t,'INFO','relance arretee indisponible ('..(t.gridWhy~='' and t.gridWhy or '?')..'): depart lance',-1); return false end
 t.standing='grid'; t.gridLit=0; note(t,'INFO',force and 'depart: depart arrete (SS) apres le tour de formation' or 'relance: depart arrete (SS)',-1)
 -- Beta 1.64 (lot 2) : origine de la grille (lue une fois par src/grid.lua) : un départ avorté y refait un tour.
 t.startAbortFrom=force==true and 'start' or 'red'
 restart(t,frame,now,p)
 if p.yellowMessage then message(t,'standing') end
 return true
end
-- Dépassement après une relance (Beta 1.34) : à la ligne de contrôle (défaut), ou dès le drapeau vert.
local function restartRule(t,frame,now,p) if p.restartOvertake=='scIn' then if p.yellowMessage then message(t,'green') end else restart(t,frame,now,p) end end
-- Meneur du tour de relance (Beta 1.35) : la mieux classée des voitures en piste, suivie une fois toutes les IA
-- sorties des stands ; distance parcourue vers l'avant cumulée. Vrai quand elle a bouclé son tour.
local function leaderLap(t,frame,now)
 if now<t.relaunchSpanUntil or frame.length<=0 then return false end
 local i=t.relaunchLeader; local a=i>0 and frame.cars[i] or nil
 if not a or not a.valid or a.pit or a.finished or not a.splineValid then
  i=0; local best=math.huge
  for j=1,frame.count do
   local b=frame.cars[j]
   -- Beta 1.60 (tranche E) : tour de formation du départ : la meilleure IA (le joueur en pole qui s'échappe ne donne
   -- ni la grille ni le drapeau vert : ils viennent avec le peloton).
   if b.valid and not b.pit and not b.finished and not b.safetyCar and b.splineValid and (b.control or b.player) and not (t.cars[j] and t.cars[j].abortMark) and not (b.player and (t.formation or t.formationAborted)) then
    local pos=(b.position or 0)>=1 and b.position or math.huge
    if i==0 or pos<best then best=pos; i=j end
   end
  end
  t.relaunchLeader=i; t.relaunchToLine=math.huge
  if i>0 then t.relaunchSpline=frame.cars[i].spline end
  return false
 end
 local step=U.spline(a.spline-t.relaunchSpline); t.relaunchSpline=a.spline
 if step>0 then t.relaunchTravel=t.relaunchTravel+step end
 -- Beta 1.60 (tranche E) : distance de la tête à la ligne (appel du départ lancé) ; vert du départ lancé à
 -- K.rollGreenBefore m de la ligne, grille formée à K.gridFormFrom m comme avant.
 t.relaunchToLine=((-a.spline)%1)*frame.length
 return t.relaunchTravel>=K.relaunchTravel and ((-a.spline)%1)*frame.length<=(t.formation and t.formationKind~='formation' and (t.rollGreenAt or K.rollGreenBefore) or K.gridFormFrom)
end
-- Sortie des stands après un drapeau rouge : ordre figé au drapeau rouge (Beta 1.48, joueur compris ; sinon ordre du
-- classement), une IA toutes les deux secondes après un court délai, chacune seulement quand la voiture qui la précède
-- dans l'ordre a quitté son emplacement et dépassé le sien (au plus K.redExitWait s, K.redExitWaitPlayer s derrière le
-- joueur). Renvoie la durée de la sortie.
local order={}
local function rankOf(t,frame,i)
 local r=t.redRank[i]
 if r then return r end
 local pos=frame.cars[i].position or 0
 return K.maxCars+(pos>=1 and pos or K.maxCars)
end
local rankFrame,rankT
local function byRank(x,y)
 local rx,ry=rankOf(rankT,rankFrame,x),rankOf(rankT,rankFrame,y)
 if rx~=ry then return rx<ry end
 return x<y
end
local function release(t,frame,now,race)
 local n=0
 for i=1,frame.count do
  local a=frame.cars[i]; t.releaseAt[i]=now; t.gate[i]=false; t.gateSince[i]=-math.huge; t.openedAt[i]=-math.huge
  -- Joueur compris en course seulement (en essais et qualifications, il peut rester au garage).
  if a.valid and not a.finished and not a.safetyCar and (a.control and not a.player or a.player and race) then n=n+1; order[n]=i end
 end
 for k=#order,n+1,-1 do order[k]=nil end
 rankT=t; rankFrame=frame; table.sort(order,byRank); rankT=nil; rankFrame=nil
 local list=t.releaseList
 for k=#list,n+1,-1 do list[k]=nil end
 for rank=1,n do
  local i=order[rank]; list[rank]=i
  t.releaseAt[i]=now+K.redReleaseFirst+(rank-1)*K.redReleaseGap
  t.gate[i]=not frame.cars[i].player
 end
 t.releaseN=n
 return K.redReleaseFirst+n*K.redReleaseGap
end
-- Voiture j (la précédente dans l'ordre) partie de son emplacement et passée devant celui de la voiture i : i peut sortir.
local function ahead(frame,j,i)
 local b=frame.cars[j]
 if not b.valid or b.finished or not b.pit then return true end
 if b.inPitBox or not b.splineValid or frame.length<=0 then return false end
 return U.spline(b.spline-frame.cars[i].spline)*frame.length>K.redExitClear
end
-- Sortie conditionnée (chaque image tant qu'une IA attend) ; hold : voiture de sécurité pas encore posée (jonction
-- connue), personne ne sort.
local function gates(t,frame,now,hold)
 local waiting=0
 for k=1,t.releaseN do
  local i=t.releaseList[k]
  if t.gate[i] then
   local a=frame.cars[i]; local open=false
   if not a.valid or not a.inPitBox then open=true
   elseif now>=t.releaseAt[i] and not hold then
    local j=k>1 and t.releaseList[k-1] or 0
    if j==0 or ahead(frame,j,i) then open=true
    elseif not t.gate[j] then
     local from=max(t.releaseAt[i],frame.cars[j].player and t.releaseAt[j] or t.openedAt[j])
     if not U.finite(t.gateSince[i]) then t.gateSince[i]=from; note(t,'INFO','sortie des stands: '..a.name..' attend '..frame.cars[j].name,i) end
     if now-from>=(frame.cars[j].player and K.redExitWaitPlayer or K.redExitWait) then open=true; note(t,'INFO','sortie des stands: '..a.name..' attente maximale ('..frame.cars[j].name..')',i) end
    end
   end
   if open then t.gate[i]=false; t.openedAt[i]=now else waiting=waiting+1 end
  end
 end
 if waiting==0 then t.releaseN=0 end
end
-- Ordre figé au drapeau rouge : joueur compris ; voiture de sécurité, voitures arrivées et IA disqualifiées exclues.
local function freeze(t,frame)
 clearOrder(t)
 local n=0
 for i=1,frame.count do
  local a=frame.cars[i]
  if a.valid and not a.finished and not a.safetyCar and (a.control or a.player) and not (t.dq and t.dq[i]) then n=n+1; order[n]=i end
 end
 for k=#order,n+1,-1 do order[k]=nil end
 Grid.sortByPosition(order,n,frame.cars)
 for k=1,n do t.redOrder[k]=order[k]; t.redRank[order[k]]=k end
 for k=#t.redOrder,n+1,-1 do t.redOrder[k]=nil end
 t.redOrderN=n
 local r=frame.player>0 and t.redRank[frame.player] or nil
 local who=''
 if r then who=string.format(', joueur P%d %s',r,r>1 and 'derriere '..frame.cars[t.redOrder[r-1]].name or t.safety>0 and 'derriere la voiture de securite' or 'en tete') end
 note(t,'INFO',string.format('drapeau rouge: ordre fige (%d voitures)%s',n,who),-1)
end
-- Beta 1.48 : la voiture i reprend sa place sur j (mieux classée que j dans l'ordre figé au drapeau rouge), pendant la
-- sortie des stands, le tour de relance et jusqu'à la ligne : dépassement permis. Jamais la voiture de sécurité.
function M.restoring(t,i,j)
 -- Beta 1.64 (lot 2) : voiture à l'origine d'un départ avorté : jamais « reprend sa place » de l'ordre du drapeau rouge.
 local ci=t.cars and t.cars[i]; if ci and ci.abortMark then return false end
 if (t.redOrderN or 0)==0 or not (t.relaunch or t.restart or (t.releaseN or 0)>0 or t.standing~='none') then return false end
 local ri,rj=t.redRank[i],t.redRank[j]
 return ri~=nil and rj~=nil and ri<rj
end
-- Dépassement permis noté une fois par paire.
-- Correctif 1.63 (Suzuka, 13 novembre : des dizaines de lignes « reprend sa place » pour des voitures déjà dans l'ordre) :
-- noté seulement quand i, vue derrière j (long > 0 : j devant), passe ensuite devant elle (long < 0) ; long et half
-- viennent de l'appelant (src/penalties.lua, position de j vue de i). Sans long : comme avant.
function M.restored(t,frame,i,j,long,half)
 local key=i*(K.maxCars+1)+j
 if t.restored[key] then return end
 if long then
  t.restoreBehind=t.restoreBehind or {}
  if long>(half or 0) then t.restoreBehind[key]=true; return end
  if not t.restoreBehind[key] or long>=-(half or 0) then return end
 end
 t.restored[key]=true
 note(t,'INFO',string.format('reprise: %s reprend sa place sur %s (ordre du drapeau rouge), depassement permis',frame.cars[i].name,frame.cars[j].name),i)
end
-- Une voiture lancée arrive derrière : l'IA arrêtée attend avant de repartir.
-- Beta 1.64 (Monza S11 : IA accidentées relancées au milieu du peloton du premier tour à la Prima Variante, puis
-- percutées ou percutant 3 voitures) : wide (départ, premier tour, relance) : toute voiture qui roule (au moins
-- K.rejoinLap1Speed km/h) à moins de K.rejoinLap1Gap m derrière, ou à sa hauteur (moins de K.rejoinSideGap m devant).
local function traffic(frame,i,p,wide,t)
 local a=frame.cars[i]; local length=frame.length
 if length<=0 or not a.splineValid then return false end
 local speed=wide and K.rejoinLap1Speed or K.rejoinSpeed
 local reach=wide and math.max(p.rejoinGap,K.rejoinLap1Gap) or p.rejoinGap
 for j=1,frame.count do
  local b=frame.cars[j]
  -- 2.0.2 g (Monza, 15 novembre, 90 à 125 s : IA accidentées reparties dans une file arrêtée sous double jaune, contacts
  -- à 0-28 km/h) : une voiture en course toute proche (K.rejoinNearBehind m derrière, ou à hauteur à K.rejoinSideGap m
  -- devant) compte comme trafic quelle que soit sa vitesse, sauf une autre voiture accidentée (t.cars[j].incident) ;
  -- seulement pour la reprise et la retenue d'une IA accidentée (t donné), jamais pour la grille du départ retardé.
  if t and K.rejoinNear and j~=i and b.valid and not b.pit and b.splineValid and not (t.cars[j] and t.cars[j].incident) then
   local d=U.spline(a.spline-b.spline)*length
   if d>0 and d<K.rejoinNearBehind or d<=0 and d>-K.rejoinSideGap then return true end
  end
  if j~=i and b.valid and not b.pit and b.splineValid and b.kmh>=speed then
   local behind=U.spline(a.spline-b.spline)*length
   -- Affinage 1.64 (Monza S12) : hors départ, portée en temps : une voiture lancée qui la rejoindrait en moins de
   -- K.rejoinRaceTime s (au plus K.rejoinRaceReachMax m).
   local far=wide and reach or math.max(reach,math.min(K.rejoinRaceReachMax,b.kmh/3.6*K.rejoinRaceTime))
   if behind>0 and behind<far or wide and behind<=0 and behind>-K.rejoinSideGap then return true end
  end
 end
 return false
end
-- Beta 1.63 (demande du pilote) : IA accidentée qui peut encore rouler. Arrêtée en incident (K.rejoinStill s, ou K.rejoinWedged
-- s sans s'éloigner, contre un mur), ni cassée (moteur, suspension, boîte : mêmes seuils que le dépannage « cassee »), ni
-- sous drapeau rouge (affinage 1.63, lot 3 : neutralisation permise) : redémarrage demandé (attente d'AC levée, voiture réveillée, src/applier.lua
-- M.rejoin) quand la piste est libre derrière (règle de reprise), K.rejoinTries fois au plus, toutes les K.rejoinGap s, en
-- K.rejoinMaxTime s au plus. Tant qu'elle essaie (c.rejoining), elle n'est pas dépannée ; repartie (à plus de
-- K.stuckRadius m du point d'essai), elle continue de tourner (l'arrêt pour dégâts la fait rentrer si besoin). Cassée ou
-- sans réussite : « ne peut plus rouler », dépannée comme avant.
local function brokenReason(a)
 if (a.engineLife or K.engineLifeNew)<=K.brokenEngine then return 'moteur casse' end
 if (a.damageSuspension or 0)>=K.brokenSuspension then return 'suspension cassee' end
 if (a.damageGearbox or 0)>=K.brokenGearbox then return 'boite cassee' end
 return nil
end
M.brokenReason=brokenReason
M.trafficTest=traffic -- 2.0.2 g : banc (tests/review202g.lua)
-- Affinage 1.63 (lot 3, Red Bull Ring : trois IA intactes dépannées sous la voiture de sécurité) : aussi sous VSC, FCY et
-- voiture de sécurité (elle repart prudemment et suit les règles de la neutralisation) ; jamais sous drapeau rouge.
local function rejoin(t,frame,p,c,a,i,now,ready)
 local eligible=ready and a.valid and a.control and not a.player and not a.pit and not a.finished and not a.safetyCar and a.splineValid
  and c.incident and not c.holding and not t.red and p.section_accidents
 -- Beta 1.64 (lot 2) : voiture retenue sur place après un départ avorté : aucun redémarrage demandé.
 if c.abortHold then eligible=false end
 if not eligible then
  if not c.incident then c.cannot=nil end
  c.rejoining=false; c.rejoinTries=0; c.rejoinSince=nil; c.rejoinMoved=false; c.rejoinWaitNoted=nil; return
 end
 -- Affinage 1.63 (lot 3, Hungaroring : « ne peut plus rouler » puis « repart » 1 s plus tard) : une voiture déjà jugée
 -- incapable n'est plus dite repartie (verdict gardé jusqu'à la fin de l'incident) ; le dernier essai a K.rejoinLastWait s
 -- de plus avant le verdict.
 -- Relecture 1.63 (S2) : essais comptés par incident (jamais remis à zéro tant que l'incident dure) ; une voiture qui
 -- s'arrête de nouveau reprend le compte là où il en était, puis est dépannée.
 if c.rejoinTries>0 and not c.cannot and not c.rejoinMoved and (a.x-c.rejoinX)^2+(a.z-c.rejoinZ)^2>K.stuckRadius^2 then
  note(t,'INFO',string.format('IA accidentee repart (redemarree, %d essai(s)), %s',c.rejoinTries,a.name),i)
  c.rejoining=false; c.rejoinMoved=true; return
 end
 if c.rejoinMoved and c.still<K.rejoinStill then c.rejoining=false; return end
 local reason=brokenReason(a)
 if reason and c.cannot~=reason then c.cannot=reason; note(t,'INFO',string.format('IA accidentee ne peut plus rouler: %s, %s',reason,a.name),i) end
 if c.cannot then c.rejoining=false; return end
 local stopped=c.still>=K.rejoinStill or (c.stuckFor or 0)>=K.rejoinWedged
 if not stopped and c.rejoinTries==0 then c.rejoining=false; c.rejoinSince=nil; return end
 c.rejoining=true; c.rejoinSince=c.rejoinSince or now
 if now<c.rejoinNext then return end
 if c.rejoinTries>=K.rejoinTries and now<c.rejoinNext+K.rejoinLastWait and now-c.rejoinSince<K.rejoinMaxTime then return end
 if c.rejoinTries>=K.rejoinTries or now-c.rejoinSince>=K.rejoinMaxTime then
  c.cannot=string.format('ne repart pas apres %d essai(s)',c.rejoinTries)
  note(t,'INFO',string.format('IA accidentee ne peut plus rouler: %s, %s',c.cannot,a.name),i)
  c.rejoining=false; return
 end
 local wide=t.hotspotPause==true
 if traffic(frame,i,p,wide,t) then
  -- Beta 1.64 (Monza S11) : départ, premier tour, relance : attente du passage du peloton, une ligne par incident.
  if wide and not c.rejoinWaitNoted then c.rejoinWaitNoted=true; note(t,'INFO',string.format('IA accidentee: attend le passage du peloton avant de repartir (premier tour), %s',a.name),i) end
  -- Relecture 1.63 (S2) : en piste, trafic continu sans aucun essai possible : dépannage au délai d'avant (K.trackRecoverTime s ;
  -- K.rejoinLap1Wait s au départ, au premier tour et à la relance).
  if c.onTrack and c.rejoinTries==0 and now-c.rejoinSince>=(wide and K.rejoinLap1Wait or math.max(K.trackRecoverTime,K.rejoinRaceWait)) then
   c.cannot='piste jamais libre'; note(t,'INFO',string.format('IA accidentee ne peut plus rouler: %s, %s',c.cannot,a.name),i); c.rejoining=false
  end
  return
 end
 c.rejoinMoved=false; c.rejoinTries=c.rejoinTries+1; c.rejoinId=(c.rejoinId+1)%K.counterMax; c.rejoinNext=now+K.rejoinGap; c.rejoinX=a.x; c.rejoinZ=a.z
 note(t,'INFO',string.format('IA accidentee: redemarrage demande (essai %d), %s',c.rejoinTries,a.name),i)
end
-- File d'attente : une voiture lente juste devant (même sens de piste) ; la voiture de derrière attend, ce n'est pas
-- un incident. Seule la voiture de tête de file l'est.
local function queued(frame,i,p)
 local a=frame.cars[i]; local length=frame.length
 if length<=0 then return false end
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=i and b.valid and not b.pit and b.splineValid and b.kmh<p.obstacleSpeedKmh+K.queueSpeedMargin and a.lx*b.lx+a.lz*b.lz>K.sameDirection then
   local ahead=U.spline(b.spline-a.spline)*length
   if ahead>0 and ahead<K.queueGap then return true end
  end
 end
 return false
end
-- Beta 1.47 (décision du pilote : drapeau rouge seulement si la piste est vraiment bloquée) : la piste est bloquée quand,
-- à l'endroit d'une voiture accidentée immobilisée en piste, les voitures accidentées immobilisées à moins de
-- K.redBlockSpan m (gabarit plus K.redBlockMargin m de chaque côté) ne laissent aucun passage de K.redPassWidth m sur la
-- largeur de la piste. Le côté de l'écart à la trajectoire n'est pas connu ici : bloquée seulement si elle l'est dans
-- les deux sens ; largeur inconnue : K.redTrackHalf m de chaque côté.
local function passable(frame,list,count,lo,hi,sign)
 local iv={}
 for k=1,count do
  -- Beta 1.59.1 : écart selon le sens de la piste (lu pour toute voiture lente, dans toutes les sessions) ; l'écart du
  -- départ n'existait que pendant le départ d'une course : ailleurs, toutes les voitures étaient comptées sur la trajectoire.
  local a=frame.cars[list[k]]; local lat=(a.lineLatValid and a.lineLat or a.splineLatValid and a.splineLat or 0)*sign; local half=a.width*0.5+K.redBlockMargin
  iv[#iv+1]={lat-half,lat+half}
 end
 table.sort(iv,function(x,y) return x[1]<y[1] end)
 local edge=lo
 for k=1,#iv do if iv[k][1]-edge>=K.redPassWidth then return true end; edge=max(edge,iv[k][2]) end
 return hi-edge>=K.redPassWidth
end
local function blocked(t,frame)
 local length=frame.length
 for n=1,t.redCount do
  local a=frame.cars[t.redCars[n]]
  if not a.offtrack and a.splineValid and length>0 then
   local near,count={},0
   for m=1,t.redCount do
    local b=frame.cars[t.redCars[m]]
    if not b.offtrack and b.splineValid and math.abs(U.spline(b.spline-a.spline))*length<=K.redBlockSpan then count=count+1; near[count]=t.redCars[m] end
   end
   local left=a.leftWidth>0 and a.leftWidth or K.redTrackHalf; local right=a.rightWidth>0 and a.rightWidth or K.redTrackHalf
   if not passable(frame,near,count,-left,right,1) and not passable(frame,near,count,-left,right,-1) then return true end
  end
 end
 return false
end
-- Beta 1.63 (décision du pilote, carnage de Suzuka) : plus grand nombre de voitures (joueur exclu) dont l'accident a
-- commencé depuis moins de DK.carnageWindow s, après le dernier drapeau rouge, groupées dans DK.carnageSpan m de piste
-- (de la plus en arrière à la plus en avant).
-- Relecture 1.63 (S1) : seulement une voiture encore à terre au moment du verdict (en incident, arrêtée ou immobilisée) ;
-- un tête-à-queue qui repart ne compte plus.
-- Correctif 1.63 (décision du pilote, 13 novembre : drapeaux rouges trop fréquents en course courte) : seulement une
-- voiture encore immobilisée depuis DK.carnageStill s au moins (une voiture qui repart ou rejoint ne compte plus).
-- Correctif 1.64 : reprise forcée au délai maximal du drapeau rouge, piste non dégagée : première IA en cause et
-- endroit au journal (aucune table) ; t.redObstacle : obstacle laissé en piste (relance arrêtée, standing).
local function obstacleNote(t,frame,elapsed)
 local first=0
 for i=1,frame.count do local c=t.cars[i]; if c.incident and c.onTrack and not frame.cars[i].player then first=i; break end end
 local a=first>0 and frame.cars[first] or nil
 local name=a and a.name or '?'; local m=first>0 and t.cars[first].spline*math.max(frame.length,0) or 0
 t.redObstacle=true
 if t.teleportCap==true then note(t,'INFO',string.format('drapeau rouge: piste non degagee %.0f s apres le delai maximal, %d IA en piste (%s a %.0f m), depannage sans effet, reprise forcee',elapsed-t.redMax,t.onTrack,name,m),first>0 and first or -1)
 else note(t,'INFO',string.format('drapeau rouge: piste non degagee au delai maximal, %d IA en piste (%s a %.0f m), depannage impossible, reprise forcee',t.onTrack,name,m),first>0 and first or -1) end
end
local function down(c,now) return now-c.wreckAt<=DK.carnageWindow and c.incident and (c.still or 0)>=DK.carnageStill end
local function carnage(t,frame,now)
 local length=frame.length
 if length<=0 then return 0 end
 -- Peu d'accidents récents (cas courant) : pas de recherche par paires.
 local recent=0
 for i=1,frame.count do local c=t.cars[i]; if down(c,now) and c.wreckAt>t.redEnd and not frame.cars[i].player then recent=recent+1 end end
 if recent<DK.carnageCars then return recent end
 local best=0
 for i=1,frame.count do
  local c=t.cars[i]
  if not frame.cars[i].player and down(c,now) and c.wreckAt>t.redEnd then
   local n=0
   for j=1,frame.count do
    local d=t.cars[j]
    if not frame.cars[j].player and down(d,now) and d.wreckAt>t.redEnd then
     local ahead=U.spline(d.wreckSpline-c.wreckSpline)*length
     if ahead>=0 and ahead<=DK.carnageSpan then n=n+1 end
    end
   end
   if n>best then best=n end
  end
 end
 return best
end
M.carnageTest=carnage
-- Beta 1.48 : voiture de sécurité posée en piste par l'applicateur (comme la répartition des IA, Beta 1.26) : elle ne
-- sortait jamais seule de son emplacement. Point libre (aucune voiture à moins de K.scPlaceFree m le long de la piste)
-- à partir de spline, par pas de K.scPlaceStep m ; -1 si aucun.
local function free(t,frame,spline)
 local length=frame.length
 for step=0,K.scPlaceSteps do
  local s=(spline+step*K.scPlaceStep/length)%1; local ok=true
  for j=1,frame.count do
   local b=frame.cars[j]
   if j~=t.safety and b.valid and not b.pit and b.splineValid and math.abs(U.spline(b.spline-s))*length<K.scPlaceFree then ok=false; break end
  end
  if ok then return s end
 end
 return -1
end
local function toPlace(t,now)
 t.scLeadAnnounced=false
 t.safetyPhase='place'; t.safetySince=now; t.safetyLeft=false; t.safetyPlaceSince=-math.huge; t.safetyTarget=-1; t.firstOut=0
 t.unlapTried=false -- Beta 1.64 (lot 5) : un dédoublement au plus par déploiement
 t.placeSerial=(t.placeSerial or 0)%K.counterMax+1; t.placeToken='sc'..t.placeSerial
end
-- Beta 1.50 : voiture de sécurité libérée à son emplacement (attente native d'AC levée ; jamais garée sans pilote) :
-- elle sort d'elle-même par la voie des stands et entre en piste, vue du joueur ; repli sur la pose en piste (hors de
-- sa vue) si elle ne quitte pas son emplacement en K.scLeaveMax s, ou la voie des stands en K.scLaneMax s.
local function toExit(t,now)
 t.safetyPhase='exit'; t.safetySince=now; t.safetyLeft=false; t.exitLeftAt=-math.huge; t.safetyPlaceSince=-math.huge
 t.safetyTarget=-1; t.firstOut=0; t.scLeadAnnounced=false; t.exitLogAt=-math.huge
 t.unlapTried=false -- Beta 1.64 (lot 5) : un dédoublement au plus par déploiement
end
-- Point de la piste (spline) en vue du joueur : moins de K.scHideAhead m devant lui ou K.scHideBehind m derrière, joueur
-- en piste (jamais dans la voie des stands).
local function seen(frame,spline,length)
 local pl=frame.player>0 and frame.cars[frame.player] or nil
 if not pl or not pl.valid or pl.pit or not pl.splineValid or length<=0 then return false end
 local d=U.spline(spline-pl.spline)*length
 return d>=0 and d<K.scHideAhead or d<0 and -d<K.scHideBehind
end
-- Meneur en piste (le mieux classé, hors voie des stands) ; 0 si aucun.
local function leaderOf(t,frame)
 local best,ref=math.huge,0
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=t.safety and b.valid and not b.pit and not b.finished and b.splineValid and (b.control or b.player) then
   local pos=(b.position or 0)>=1 and b.position or math.huge
   if ref==0 or pos<best then best=pos; ref=j end
  end
 end
 return ref
end
-- Première voiture en piste derrière la voiture de sécurité (indice, distance en m) ; 0 si aucune.
local function queueHead(t,frame,sc,length)
 local near,who=math.huge,0
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=t.safety and b.valid and not b.pit and b.splineValid then local d=U.spline(sc.spline-b.spline)*length; if d>0 and d<near then near=d; who=j end end
 end
 return who,near
end
-- Beta 1.60 (Bakou, 11 novembre : rentrée après 60 s, peloton coupé en deux, puis un tour entier sans dépassement ni
-- drapeau bleu pour les voitures loin de la ligne) : file derrière le point ref (spline de la voiture de sécurité) :
-- de proche en proche, chaque voiture à K.scBunchGap m au plus de la précédente (lead m d'avance tolérés pour la
-- première : au vert, la voiture de sécurité ralentit dans l'entrée des stands). Voitures comptées : en piste, en
-- course, hors incident. Marque c.inTrain ; renvoie le nombre de voitures dans la file et le total.
local function train(t,frame,ref,length,lead,p)
 local total=0
 for j=1,frame.count do
  local b=frame.cars[j]; local c=t.cars[j]
  c.inTrain=false; c.trainD=nil
  -- Relecture du lot 3 (S4) : jamais comptée une voiture qui ne peut pas rejoindre la file (incident écarté, retenue,
  -- en difficulté, hors piste, presque arrêtée) : le regroupement n'aboutissait jamais.
  -- Beta 1.64 (lot 5) : autorisées et dédoublées (c.unlapOut) jamais comptées : elles ne retiennent pas la rentrée.
  if j~=t.safety and b.valid and not b.pit and not b.finished and b.splineValid and (b.control or b.player) and not c.incident and not c.unlapOut
   and not c.dismissed and not c.holding and not c.trouble and not b.offtrack and not (p and b.kmh<p.obstacleSpeedKmh) then
   total=total+1; c.trainD=((ref-b.spline)*length+lead)%length-lead
  end
 end
 local edge,count=0,0
 while true do
  local best,bj=math.huge,0
  for j=1,frame.count do local c=t.cars[j]; if c.trainD and not c.inTrain and c.trainD<best then best=c.trainD; bj=j end end
  if bj==0 or best-edge>K.scBunchGap then break end
  t.cars[bj].inTrain=true; edge=max(edge,best); count=count+1
 end
 return count,total
end
-- Annonce « voiture de sécurité en piste » (pont des apps compagnes) : valeur = indice AC (0) de la voiture juste
-- derrière elle (-1 si aucune), extra = écart en m (-1 si aucune).
local function scOut(t,frame,sc,length,p)
 local who,near=queueHead(t,frame,sc,length)
 if p.yellowMessage then message(t,'scOut',who>0 and who-1 or -1,who>0 and near or -1) end
 return who,near
end
-- Pose impossible dans le délai : neutralisation (ou tour de relance) sous VSC ou FCY, voiture de sécurité gardée à
-- son emplacement.
local function placeFailed(t,frame,now,p)
 local mode=t.relaunch and p.neutralization=='vsc' and 'vsc' or 'fcy'
 note(t,'WARN',string.format('voiture de securite: pose en piste impossible (%s), %s sous %s',U.finite(t.safetyPlaceSince) and 'aucun point libre' or 'aucune reference',t.relaunch and 'tour de relance' or 'neutralisation',mode),t.safety)
 t.safetyPhase='parked'; t.safetyTarget=-1; t.safetyPlaceSince=-math.huge
 if t.neutral and t.neutralMode=='sc' then
  t.safetyFailed=true; t.neutralMode=mode
  if t.relaunch then
   t.neutralUntil=max(t.neutralUntil,now+frame.length/(p.fcySpeedKmh/3.6))
   if p.yellowMessage then message(t,mode=='vsc' and 'redRestartVsc' or 'redRestartFcy') end
  elseif p.yellowMessage then message(t,'fcy',p.fcyDeltaPct) end
 end
end
-- Beta 1.64, lot 5 (décision du pilote du 13 novembre) : tours de retard de b sur le meneur L : écart des tours moins
-- l'écart physique sur le cercle du tour (exact partout) ; une voiture du même tour est derrière le meneur au
-- classement, donc toute voiture physiquement devant lui dans la file a un tour de moins. Donnée invalide : 0.
-- Relecture 164e (A8) : phys (part de tour, positive derrière le meneur), écart pris le long de la file quand il est
-- connu : une voiture du même tour à plus d'un demi-tour derrière le meneur n'est plus comptée attardée (le repli sur
-- un demi-tour la comptait). Inconnu : écart sur le cercle du tour, comme avant.
function M.lapsDown(L,b,phys)
 if not (L.lapValid and b.lapValid and L.splineValid and b.splineValid) then return 0 end
 if phys then return math.floor((L.lap+L.spline)-(b.lap+b.spline)-phys+0.5) end
 return math.floor((L.lap+L.spline)-(b.lap+b.spline)-U.spline(L.spline-b.spline)+0.5)
end
-- Voiture i autorisée à se dédoubler à cette image (une seule à la fois).
function M.unlapping(t,i)
 return i>0 and i==t.unlapCar and t.unlapState=='run' and t.neutral and t.neutralMode=='sc' and t.safetyPhase=='out' and not t.red and not t.safetyFailed and not t.relaunch and not t.scFinal
end
local function zoneOnTrack(t) for k=1,t.zoneCount do if t.zones[k].onTrack then return true end end return false end
-- Relecture 164e (A1, A10) : tours restants du meneur ; course au temps : temps restant en tours de voiture de sécurité,
-- plus le tour supplémentaire de la session ; format inconnu : nil.
local function lapsLeft(frame)
 if (frame.sessionLaps or 0)>0 and not frame.timedRace then return frame.sessionLaps-(frame.leaderLaps or 0) end
 if frame.timedRace==true and frame.length>0 then return (frame.left or 0)/(frame.length/(K.scNominalKmh/3.6))+(frame.extraLap==true and 1 or 0) end
 return nil
end
-- Relecture 164e (A10) : assez de tours pour n attardées (au lancement et avant chaque autorisation) : au moins
-- SK.minLaps, et plus que n délais par voiture (un tour de voiture de sécurité borné) plus 2 tours de voiture de sécurité
-- (attente de la ligne, tour de rentrée), comptés en tours de voiture de sécurité, plus 1 : jamais une course finie
-- sous voiture de sécurité à cause du dédoublement.
local function unlapRoom(laps,n,scLap)
 return laps>=SK.minLaps and laps>(n*U.clamp(scLap,SK.passMin,SK.passMax)+2*scLap)/scLap+1
end
-- Beta 1.64, lot 5 : dédoublement comme en F1. File formée derrière la voiture de sécurité (format de course connu,
-- une classe, au moins SK.minLaps tours restants, aucun incident en piste) : les attardées de la file (liste figée,
-- de l'avant vers l'arrière) doublent une par une la file et la voiture de sécurité ; elle rentre ensuite à la fin du
-- tour suivant. Vrai : la voiture de sécurité reste en piste.
local function unlapHold(t,frame,now,p,profile,car,inTrain,total,late)
 if t.unlapState=='run' then return true end
 if t.unlapState=='done' then
  if not t.unlapRelease then return true end
  unlapClear(t); return false
 end
 if t.unlapTried or inTrain<total or late or not (car.valid and not car.pit and car.splineValid and frame.length>0) then return false end
 t.unlapTried=true
 if profile~='C' or t.relaunch or t.formation or t.scFinal then return false end
 local laps=lapsLeft(frame)
 if not laps then return false end
 local lead=leaderOf(t,frame); if lead==0 then return false end
 local L=frame.cars[lead]; local nLapped=0
 -- Relecture 164e (A8) : meneur dans la file : écart de chaque voiture pris le long de la file (trainD).
 local lt=t.cars[lead].inTrain and t.cars[lead].trainD or nil
 local scLap=frame.length/(K.scNominalKmh/3.6)
 for j=1,frame.count do
  local b=frame.cars[j]; local c=t.cars[j]
  if j~=lead and c.inTrain and not (t.dq and t.dq[j]) and M.lapsDown(L,b,lt and c.trainD and (c.trainD-lt)/frame.length)>=1 then
   local k=nLapped
   while k>0 and t.cars[t.unlapList[k]].trainD>c.trainD do t.unlapList[k+1]=t.unlapList[k]; k=k-1 end
   t.unlapList[k+1]=j; nLapped=nLapped+1
  end
 end
 if nLapped==0 then return false end
 local why=p.multiClass==true and (t.classes or 0)>1 and 'course multi-classe' or not unlapRoom(laps,nLapped,scLap) and 'fin de course proche' or zoneOnTrack(t) and 'incident en piste'
 if why then note(t,'INFO',string.format('voiture de securite: dedoublement non lance (%s, %d attardee(s))',why,nLapped),t.safety); return false end
 t.unlapState='run'; t.unlapN=nLapped; t.unlapK=0; t.unlapCar=0; t.unlapDone=0; t.unlapRelease=false
 t.unlapNext=now+SK.settle; t.unlapUntil=now+SK.budget
 note(t,'INFO',string.format('voiture de securite: file formee, %d attardee(s) autorisee(s) a se dedoubler une par une',nLapped),t.safety)
 return true
end
-- Beta 1.64, lot 5 : dédoublement à chaque image : interrompu (drapeau rouge, fin de neutralisation, voiture de
-- sécurité indisponible ou plus en piste, dernier tour), autorisation suivante quand la précédente a doublé la voiture
-- de sécurité (ou n'a pas pu), libération mémorisée au passage de la ligne de la voiture de sécurité ; exemptées (scFree)
-- recalculées : l'autorisée, et les voitures arrivées pendant une arrivée neutralisée.
local function unlapStep(t,frame,now,p,length)
 local sc=t.safety>0 and frame.cars[t.safety] or nil
 local scLap=length>0 and length/(K.scNominalKmh/3.6) or 0
 if t.unlapState~='none' then
  local why=t.red and 'drapeau rouge' or not t.neutral and 'fin de neutralisation' or (t.neutralMode~='sc' or t.safetyFailed) and 'voiture de securite indisponible' or t.scFinal and 'dernier tour'
   or (t.relaunch or t.safetyPhase~='out' or not sc or not sc.valid or sc.pit or not sc.splineValid or length<=0) and 'voiture de securite plus en piste'
  if why then note(t,'INFO','voiture de securite: dedoublement interrompu ('..why..')',-1); unlapClear(t) end
 end
 if t.unlapState=='run' then
  local i=t.unlapCar
  if i>0 then
   local b=frame.cars[i]; local c=t.cars[i]
   local half=((b.length or K.length)+(sc.length or K.length))*0.5
   local d=b.splineValid and U.spline(sc.spline-b.spline)*length or 0
   local why=(not b.valid or b.finished) and 'hors course' or b.pit and 'aux stands' or (c.incident or c.holding) and 'accidentee' or now-t.unlapAt>=U.clamp(scLap,SK.passMin,SK.passMax) and 'delai depasse'
   if not why and d<-2*half then
    t.unlapDone=t.unlapDone+1; t.unlapCar=0; c.scBehind=false; c.scPassed=false; c.scLift=false; c.scAhead=true
    note(t,'INFO',string.format('voiture de securite: %s s est dedoublee (%d / %d)',b.name,t.unlapDone,t.unlapN),i)
   elseif why then
    t.unlapCar=0; c.unlapOut=false
    note(t,'INFO',string.format('voiture de securite: %s ne se dedouble pas (%s), reste dans la file',b.name,why),i)
   end
  end
  if t.unlapCar==0 then
   -- Relecture 164e (A10) : avant chaque autorisation, assez de tours pour les attardées restantes, sinon arrêté (la
   -- voiture de sécurité rentre ensuite comme d'habitude).
   local stop=zoneOnTrack(t) and 'incident en piste' or now>=t.unlapUntil and 'delai maximal'
    or t.unlapK<t.unlapN and not unlapRoom(lapsLeft(frame) or math.huge,t.unlapN-t.unlapK,scLap) and 'fin de course proche'
   if stop and t.unlapK<t.unlapN then note(t,'INFO',string.format('voiture de securite: dedoublement arrete (%s), %d attardee(s) restent dans la file',stop,t.unlapN-t.unlapK),t.safety); t.unlapK=t.unlapN end
   while t.unlapCar==0 and t.unlapK<t.unlapN and now>=t.unlapNext do
    t.unlapK=t.unlapK+1
    local j=t.unlapList[t.unlapK]; local b=frame.cars[j]; local c=t.cars[j]
    local why=(not b.valid or b.finished) and 'hors course' or b.pit and 'aux stands' or (c.incident or c.holding or c.trouble or b.offtrack) and 'accidentee'
    if why then note(t,'INFO',string.format('voiture de securite: %s ne se dedouble pas (%s), reste dans la file',b.name,why),j)
    else
     t.unlapCar=j; t.unlapAt=now; c.unlapOut=true
     note(t,'INFO',string.format('voiture de securite: %s autorisee a se dedoubler (%d / %d)',b.name,t.unlapK,t.unlapN),j)
     if p.yellowMessage then message(t,'scUnlap',j-1,t.unlapN-t.unlapK,b.name) end
    end
   end
   if t.unlapCar==0 and t.unlapK>=t.unlapN then
    t.unlapState='done'; t.unlapDoneAt=now; t.unlapRelease=t.unlapDone==0
    note(t,'INFO',string.format('voiture de securite: dedoublement termine (%d / %d), %s',t.unlapDone,t.unlapN,t.unlapDone>0 and 'rentre au prochain passage de la ligne' or 'rentre ce tour'),t.safety)
   end
  end
 end
 if t.unlapState=='done' and not t.unlapRelease and sc and sc.splineValid then
  if t.unlapLast>0.5 and sc.spline<0.5 and U.spline(sc.spline-t.unlapLast)>=0 or now-t.unlapDoneAt>=SK.doneLaps*scLap then t.unlapRelease=true end
 end
 t.unlapLast=sc and sc.splineValid and sc.spline or -1
 -- Relecture 164e (A11) : dernière voiture de la file derrière la voiture de sécurité (dédoublées comprises hors file),
 -- seulement une fois une voiture dédoublée (allure des dédoublées, M.cap).
 t.unlapTail=0
 if t.unlapState~='none' and t.unlapDone>0 and sc and sc.valid and not sc.pit and sc.splineValid and length>0 then
  train(t,frame,sc.spline,length,0,p)
  local far=-1
  for j=1,frame.count do local c=t.cars[j]; if c.inTrain and c.trainD>far then far=c.trainD; t.unlapTail=j end end
 end
 for j=1,frame.count do t.cars[j].scFree=M.unlapping(t,j) or t.scFinal and frame.finished and frame.cars[j].finished==true end
 -- Relecture 164e (A9) : sous neutralisation par la voiture de sécurité, elle ni en tête de la file ni en train de
 -- rentrer (appelée, sortie, pose, rappelée ou garée, arrivée neutralisée) : jamais une cible de la file, la doubler
 -- n'est pas une faute.
 if t.safety>0 then local c=t.cars[t.safety]; c.scFree=c.scFree or t.neutral and t.neutralMode=='sc' and not t.safetyFailed and t.safetyPhase~='out' and t.safetyPhase~='in' end
end
-- Beta 1.64, lot 5 : dernier tour du meneur (même formule que le drapeau blanc de src/panel.lua) ; format inconnu : jamais.
-- Relecture 164e (A1) : course au temps avec un tour supplémentaire (frame.extraLap) : le dernier tour est celui qui suit
-- le passage du meneur après le temps écoulé (t.zeroLaps : ses tours au temps écoulé), jamais le tour où le temps
-- s'écoule (la voiture de sécurité rentrait un tour trop tôt).
local function lastLap(t,frame)
 if (frame.sessionLaps or 0)>0 and not frame.timedRace then return (frame.leaderLaps or 0)+1>=frame.sessionLaps end
 return frame.timedRace==true and (frame.left or 1)<=0 and (frame.extraLap~=true or (frame.leaderLaps or 0)>t.zeroLaps)
end
-- Beta 1.64, lot 5 : arrivée neutralisée. Dernier tour sous voiture de sécurité (course) : elle rentre sans relance
-- (appelée, elle ne sort pas), la file franchit le damier dans l'ordre, sans dépassement. Durée du tour du meneur
-- mesurée à chaque image (borne lointaine). Levée par un drapeau rouge ou la fin de la neutralisation.
local function finalLatch(t,frame,now,p,profile)
 local laps=frame.leaderLaps or 0
 if laps~=t.leadLaps then
  if t.leadLaps>=0 and U.finite(t.leadLapAt) then t.leadLapDur=now-t.leadLapAt end
  t.leadLaps=laps; t.leadLapAt=now
 end
 -- Relecture 164e (A1) : noté à chaque image, neutralisation ou non (voiture de sécurité appelée pendant le tour
 -- supplémentaire, temps écoulé sous drapeau vert).
 if frame.timedRace~=true or (frame.left or 1)>0 then t.zeroLaps=-1 elseif t.zeroLaps<0 then t.zeroLaps=laps end
 if t.scFinal then if t.red or not t.neutral or t.safety==0 then t.scFinal=false end; return end
 -- Annulée (preuve) : jamais réaccrochée pendant la même neutralisation (sinon le vert ne venait jamais).
 if t.scFinalOff then if not t.neutral then t.scFinalOff=false end; return end
 if profile~='C' or not frame.started or not t.neutral or t.neutralMode~='sc' or t.safety==0 or t.safetyFailed or t.relaunch or t.formation or t.red or not lastLap(t,frame) then return end
 -- Relecture 164e (A1) : accrochée au tour supplémentaire : il est déjà compté (jamais un second tour de plus).
 t.scFinal=true; t.scFinalAt=now; t.scFinalLaps=laps; t.scCrossAt=-math.huge; t.scExtra=frame.extraLap==true; t.scFlagAt=-math.huge
 local ph=t.safetyPhase
 if ph=='out' or ph=='in' then
  if ph=='out' then t.safetySince=now end
  t.safetyPhase='in'; note(t,'INFO','voiture de securite: dernier tour, rentre sans relance (arrivee neutralisee)',t.safety)
 else
  -- Relecture 164e (A9) : en sortie aussi, ramenée à son stand (jamais « rentrée » par la piste devant des voitures
  -- lancées).
  t.safetyPhase='parked'; note(t,'INFO','voiture de securite: dernier tour, reste aux stands (arrivee neutralisee)',t.safety)
 end
 if p.yellowMessage then message(t,'scFinish') end
end
-- Beta 1.64, lot 5 : arrivée neutralisée tenue (aucun nouvel incident, aucun vert, aucune levée au délai). Annulée sur
-- preuve : le meneur franchit la ligne sans damier (SK.finalCross s ; course au temps : une fois, le tour de plus
-- d'AC), ou borne lointaine. Après le damier : tenue jusqu'au passage de toutes les voitures (au plus SK.holdLaps tour).
local function finalStep(t,frame,now,p)
 local car=frame.cars[t.safety]; local scLap=frame.length/(K.scNominalKmh/3.6)
 if t.safetyPhase=='in' then
  local crossed=car.valid and not car.pit and car.splineValid and t.safetyLastSpline>0.5 and car.spline<0.5 and U.spline(car.spline-t.safetyLastSpline)>=0
  if car.pit then t.safetyPhase='parking'; note(t,'INFO','arrivee neutralisee: voiture de securite aux stands, file jusqu au damier',t.safety)
  elseif crossed or now-t.safetySince>=K.scInMax then t.safetyPhase='parked'; t.safetyReturnAt=now; note(t,'INFO','arrivee neutralisee: voiture de securite rappelee a son stand, file jusqu au damier',t.safety) end
 end
 if not frame.finished then
  local why=nil
  if (frame.leaderLaps or 0)>t.scFinalLaps then
   if not U.finite(t.scCrossAt) then t.scCrossAt=now; t.scCrossLeft=frame.left or 0 end
   if now-t.scCrossAt>=SK.finalCross then
    if frame.timedRace==true and t.scCrossLeft<=0 and not t.scExtra then
     t.scExtra=true; t.scFinalLaps=frame.leaderLaps or 0; t.scCrossAt=-math.huge
     note(t,'INFO','arrivee neutralisee: tour de plus apres la fin du temps, neutralisation tenue',-1)
    else why='pas de drapeau a damier au passage du meneur' end
   end
  end
  if not why and now-t.scFinalAt>=SK.finalMax*math.max(scLap,t.leadLapDur) then why='delai depasse' end
  if why then
   t.scFinal=false; t.scFinalOff=true
   if car.pit and t.safetyPhase~='in' then t.safetyPhase='in'; t.safetySince=now end
   note(t,'WARN','arrivee neutralisee annulee ('..why..'), relance normale',-1)
   -- Relecture 164e (A6) : voiture de sécurité déjà rappelée ou garée hors de la voie des stands (jamais de retour par
   -- le chemin vert ordinaire) : drapeau vert aussitôt, avec la règle de reprise (jamais un vert sans « pas de
   -- dépassement jusqu'à la ligne », ni une file sans voiture de sécurité jusqu'au délai).
   if t.safetyPhase~='in' then
    t.neutral=false; t.ending=false; t.restartSerial=(t.restartSerial or 0)+1; t.greenUntil=now+K.greenShow
    note(t,'INFO','drapeau vert: arrivee neutralisee annulee, voiture de securite rappelee a son stand'..(p.restartOvertake=='scIn' and ', depassement permis' or ''),t.safety)
    restartRule(t,frame,now,p)
   end
  end
  return
 end
 local left=0
 for j=1,frame.count do local b=frame.cars[j]; if j~=t.safety and b.valid and not b.pit and not b.finished and b.splineValid and (b.control or b.player) and not b.safetyCar and not t.cars[j].incident then left=left+1 end end
 if not U.finite(t.scFlagAt) then t.scFlagAt=now; note(t,'INFO',string.format('arrivee neutralisee: drapeau a damier, %d voiture(s) encore en piste',left),-1) end
 if left==0 or now-t.scFlagAt>=SK.holdLaps*scLap then
  t.neutral=false; t.scFinal=false; t.ending=false
  note(t,'INFO',left==0 and 'arrivee neutralisee: toutes les voitures ont franchi la ligne' or string.format('arrivee neutralisee: levee apres %.0f s (%d voiture(s) encore en piste)',now-t.scFlagAt,left),-1)
 end
end
-- ready : session lancée, hors grille de départ. Une voiture arrêtée, en tête-à-queue ou à contresens est un incident ;
-- hors piste depuis longtemps, elle est considérée comme dégagée par les commissaires.
function M.update(t,frame,p,profile,now,dt,ready,seed)
 -- Beta 1.59 (relecture) : point difficile oublié plus vite en course (2 x K.hotspotWindow s).
 t.hotspotForget=profile=='C' and K.hotspotForgetRace or K.hotspotForget
 t.frameId=(t.frameId+1)%K.counterMax; t.now=now
 t.zoneCount=0; t.activeCount=0; t.holdCount=0; t.onTrack=0; t.freshOnTrack=0
 t.redCount=0; t.redStopped=0; t.redQueued=0; t.redCars=t.redCars or {}
 local major=false
 -- Escalade vers la voiture de sécurité : incidents majeurs en même temps, immobilisation la plus longue.
 local majors,longest=0,0
 -- Départ arrêté en cours (Beta 1.34) : une voiture qui s'arrête à sa place n'est pas un incident.
 local gridStop=t.standing~='none'
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]
  local identity=a.identity or a.id
  if c.identity~=identity or a.teleport then clearCar(c); c.identity=identity end
  if a.valid and a.splineValid and not a.pit then
   if c.lastSpline>=0 and a.kmh>=K.wrongWaySpeed and U.spline(a.spline-c.lastSpline)<0 and M.noseFirst(a,c.lastX,c.lastZ) then c.wrong=min(K.wrongWayTime*2,c.wrong+dt) else c.wrong=max(0,c.wrong-dt) end
   c.lastSpline=a.spline; c.lastX=a.x; c.lastZ=a.z
  else c.lastSpline=-1; c.wrong=0 end
  if a.valid and a.slip>K.slipDegrees and a.kmh>=K.spinSpeed then
   -- Beta 1.59 : vitesse la plus haute de la glissade, pour juger la perte de vitesse d'un vrai tête-à-queue.
   c.spinFrom=c.spin>0 and max(c.spinFrom,a.kmh) or a.kmh
   c.spin=min(K.spinTime*2,c.spin+dt)
  else c.spin=max(0,c.spin-dt) end
  -- Beta 1.59 (course de 10 tours du 10 novembre ; MJFox : peloton freiné pour une voiture à peine dans l'herbe) : une
  -- glissade de plus de K.slipDegrees degrés n'est un tête-à-queue que si la voiture perd au moins K.contactDrop km/h,
  -- ou roule déjà au pas ; une glissade rattrapée en gardant sa vitesse n'est pas un incident.
  c.spun=c.spin>=K.spinTime and (c.spinFrom-a.kmh>=K.contactDrop or a.kmh<p.obstacleSpeedKmh)
  local eligible=ready and a.valid and not a.pit and not a.finished and a.splineValid and not a.safetyCar
  -- Voiture réellement arrêtée (drapeau rouge, incident majeur) : un tête-à-queue qui roule encore n'en est pas une.
  if eligible and a.kmh<K.redStopSpeed then c.still=c.still+dt else c.still=0 end
  -- Beta 1.29 (séance d'essais du pilote) : voiture qui n'avance plus (bac à sable : elle patine, avance et recule sur
  -- place, au-delà du seuil d'arrêt par moments) : temps passé sans s'éloigner de plus de K.stuckRadius m.
  if ready and a.valid and not a.pit and not a.finished and not a.safetyCar then
   if (a.x-c.anchorX)^2+(a.z-c.anchorZ)^2>K.stuckRadius^2 then c.anchorX=a.x; c.anchorZ=a.z; c.stuckFor=0 else c.stuckFor=c.stuckFor+dt end
  else c.stuckFor=0; c.anchorX=math.huge; c.anchorZ=math.huge end
  -- Relecture 1.64 (lot 2) : fautive d'un départ avorté retenue : voiture lancée qui arrive derrière (src/grid.lua).
  c.abortTraffic=c.abortHold==true and traffic(frame,i,p)
  -- Arrêt : voiture presque arrêtée (moins de 10 km/h, pas un bouchon qui avance au pas) qui roulait déjà (pas un départ
  -- arrêté en début de session ni une sortie des stands) et qui n'attend pas simplement derrière une autre voiture
  -- lente, sauf si elle vient de heurter quelque chose. Une voiture découverte plus tard dans la session (rechargement de
  -- l'app) est supposée avoir roulé.
  if c.fresh then c.fresh=false; c.moved=frame.time>=K.spawnWindow end
  if a.pit or not a.valid then c.moved=false elseif a.kmh>=K.rejoinSpeed then c.moved=true end
  if eligible and c.moved and a.kmh<K.incidentStopSpeed and (now-c.lastCrash<=K.crashWindow or not gridStop and not queued(frame,i,p)) then c.halt=c.halt+dt else c.halt=0 end
  -- Journal : voitures lentes que les règles d'arrêt écartent (départ ou sortie des stands, voiture au pas, file).
  if eligible and a.kmh<p.obstacleSpeedKmh then c.slow=c.slow+dt else c.slow=0; c.counted=false end
  if c.slow>=K.obstacleTime and c.halt==0 and not c.counted then
   c.counted=true; local reason=not c.moved and 'spawn' or a.kmh>=K.incidentStopSpeed and 'crawl' or 'queue'
   t.suppressed[reason]=t.suppressed[reason]+1
  end
  local raw=eligible and (c.halt>=K.obstacleTime or c.spun or c.wrong>=K.wrongWayTime)
  if raw then c.calm=0 else c.calm=c.calm+dt end
  -- Fin confirmée après quelques secondes de conduite normale : une glissade qui se stabilise reste un seul incident,
  -- et le délai d'incident majeur n'est pas remis à zéro.
  -- Une voiture encore lente après un tête-à-queue reste le même incident jusqu'à ce qu'elle reparte.
  local incident=raw or eligible and c.incident and (c.calm<K.incidentClear or a.kmh<p.obstacleSpeedKmh)
  -- Beta 1.59 (relecture) : dégagement tenu tant que la voiture reste arrêtée (pas d'incident neuf à chaque sautillement
  -- de la lecture hors piste) ; levé quand elle repart ou revient en piste plus de K.offClearBack s.
  if a.offtrack then c.backOn=0 else c.backOn=(c.backOn or 0)+dt end
  if not incident or c.still==0 or (c.backOn or 0)>K.offClearBack then c.dismissed=false end
  if c.still==0 then c.hotspotFed=false; c.dangerFed=false end
  if incident and not c.incident then
   c.since=now; c.announced=false
   if not c.dismissed then
    t.started=t.started+1
    note(t,'INFO',string.format('incident: %s, %s, %.0f m, %.0f km/h, %s',c.halt>=K.obstacleTime and 'arret' or c.spun and 'tete-a-queue' or 'contresens',
     a.offtrack and 'hors piste' or 'en piste',a.spline*frame.length,a.kmh,a.name),i)
    -- Correctif 1.63 (Suzuka, 13 novembre : carnage du premier tour au même virage) : départ, premier tour et relance
    -- comptés aussi, seulement pour les zones dangereuses gardées par circuit (aucun point difficile armé là).
    if t.hotspotPause then if not c.dangerFed then c.dangerFed=true; M.hotspotNote(t,a.spline,frame.length,now,i,true) end
    elseif not c.hotspotFed then c.hotspotFed=true; M.hotspotNote(t,a.spline,frame.length,now,i) end
    -- Beta 1.63 : accident pour le carnage : tête-à-queue, arrêt hors piste ou avec des dégâts ; jamais une voiture
    -- intacte arrêtée en piste dans la file derrière un accident (un freinage brusque dans la file y ressemble à un choc).
    local hurt=(a.damageSuspension or 0)>=K.slowPitSuspension or (a.damageBody or 0)>=K.slowPitBody
    if c.spun or c.halt>=K.obstacleTime and (a.offtrack or hurt) then c.wreckAt=now; c.wreckSpline=a.spline end
   end
  end
  -- Beta 1.59 : voiture arrêtée hors piste, loin de la trajectoire (plus de K.offClearLat m) depuis K.offClearTime s :
  -- dégagée comme par les commissaires (sinon au bout de K.incidentMaxAge s hors piste, comme avant).
  local edge=math.max(a.leftWidth or 0,a.rightWidth or 0)
  -- Beta 1.59.1 : hors du départ d'une course, l'écart latéral n'est pas lu : distance à la trajectoire (instantané).
  local lat=a.splineLatValid and math.abs(a.splineLat) or a.lineDistValid and a.lineDist or nil
  local beyond=(a.wheelsOut or 0)>=4 or edge>0 and lat~=nil and lat>edge+K.offClearEdge
  local clear=incident and not c.dismissed and a.offtrack and beyond and c.still>=K.offClearTime and lat~=nil and lat>K.offClearLat
  if incident and (c.dismissed or clear or a.offtrack and now-c.since>K.incidentMaxAge) then
   if not c.dismissed then note(t,'INFO',clear and 'incident ecarte: arretee hors piste, loin de la trajectoire depuis '..K.offClearTime..' s' or 'incident ecarte: hors piste depuis plus de '..K.incidentMaxAge..' s',i) end
   c.dismissed=true; incident=false
  end
  if incident then
   c.spline=a.spline; c.onTrack=not a.offtrack; t.activeCount=t.activeCount+1
   -- Beta 1.59 : double jaune pour une voiture en piste arrêtée, lente (moins de obstacleSpeedKmh km/h, jamais moins de
   -- K.doubleFloorKmh) ou à contresens ; une voiture qui roule encore à bonne allure en piste : jaune simple. Jugé en
   -- direct, gardé pendant la tenue de la zone.
   c.double=c.onTrack and (a.kmh<math.max(p.obstacleSpeedKmh,K.doubleFloorKmh) or c.halt>0 or c.wrong>=K.wrongWayTime)
   if c.onTrack and not a.player then t.onTrack=t.onTrack+1; if c.since>t.redEnd and c.still>=K.redStopTime then t.freshOnTrack=t.freshOnTrack+1 end end
   if c.spun then c.spunIncident=true end
   -- Incident majeur : voiture immobile en piste (pas une voiture qui roule au pas), apparue depuis la dernière
   -- neutralisation levée au délai maximal.
   if c.onTrack and c.still>=p.majorIncidentTime and c.since>t.neutralEnd then major=true; majors=majors+1; longest=max(longest,c.still) end
  elseif c.incident then c.clearedAt=now; note(t,'INFO',string.format('incident termine apres %.1f s',now-c.since),i) end
  if not incident then c.spunIncident=false end
  -- Beta 1.47 (décision du pilote) : voiture arrêtée depuis K.redIncidentStill s. Comptée pour le drapeau rouge si elle
  -- l'est à cause d'un incident (dégâts, tête-à-queue, arrêt hors de la trajectoire ou hors piste, arrêt seule en
  -- pleine piste) ; une voiture intacte, sur la trajectoire, qui attend derrière une voiture arrêtée est dans la file :
  -- jamais comptée.
  if eligible and not a.player and c.still>=K.redIncidentStill and now-c.still>t.redEnd then
   t.redStopped=t.redStopped+1
   local damaged=(a.damageSuspension or 0)>=K.slowPitSuspension or (a.damageBody or 0)>=K.slowPitBody
   local offLine=a.offtrack or a.lineLatValid and math.abs(a.lineLat)>K.redOffLine or not a.lineLatValid and a.splineLatValid and math.abs(a.splineLat)>K.redOffLine
   if queued(frame,i,p) and not damaged and not c.spunIncident and not offLine then t.redQueued=t.redQueued+1
   elseif incident or damaged or c.spunIncident or offLine then t.redCount=t.redCount+1; t.redCars[t.redCount]=i end
  end
  c.incident=incident
  if incident or now-c.clearedAt<p.yellowHold then
   t.zoneCount=t.zoneCount+1; local z=t.zones[t.zoneCount]; z.slot=i; z.spline=c.spline; z.onTrack=c.double
  end
  -- Beta 1.63 (demande du pilote : jaunes de secteur invisibles en course d'IA seules) : ouverture et fermeture d'une
  -- zone jaune notées au journal (voiture, endroit, simple ou double), seulement drapeaux jaunes en service.
  local zone=p.yellowEnabled and (incident or now-c.clearedAt<p.yellowHold)
  if zone and not c.zoneOpen then
   c.zoneOpen=true; c.zoneOpenAt=now; c.zoneDouble=c.double==true
   note(t,'INFO',string.format('zone jaune ouverte: %s a %.0f m (%s)',a.name,c.spline*math.max(frame.length,0),c.double and 'double' or 'simple'),i)
  elseif zone and c.double and not c.zoneDouble then
   c.zoneDouble=true; note(t,'INFO',string.format('zone jaune: %s passe en double',a.name),i)
  elseif not zone and c.zoneOpen then
   c.zoneOpen=false; note(t,'INFO',string.format('zone jaune fermee: %s apres %.0f s',a.name,now-c.zoneOpenAt),i)
  end
  -- Accident d'une IA : forte décélération avec contact, sortie de piste ou tête-à-queue, puis quasi-arrêt.
  c.contact=c.contact or a.collided or a.offtrack or a.slip>K.slipDegrees
  if now-c.windowStart>=K.contactWindow then
   if c.window-a.kmh>=K.contactDrop and c.contact then c.crashAt=now; c.lastCrash=now end
   c.window=a.kmh; c.windowStart=now; c.contact=false
  end
  local candidate=p.incidentStop and ready and a.valid and a.control and not a.player and not a.pit and not a.finished and not a.safetyCar
  -- Retenue hors piste seulement : en piste, l'IA repart aussitôt, jamais immobilisée sur la trajectoire.
  if candidate and not c.holding and a.offtrack and now-c.crashAt<=K.crashSettle and a.kmh<p.obstacleSpeedKmh then
   c.crashes=(c.crashes+1)%K.counterMax; c.holding=true; c.crashAt=-math.huge
   c.holdUntil=now+U.lerp(p.incidentStopMin,p.incidentStopMax,U.unit(seed,i,K.crashSalt+c.crashes)); c.holdMax=c.holdUntil+(profile=='J' and K.rejoinWaitMaxJ or K.rejoinWaitMax)
   c.holdStart=now; t.held=t.held+1; note(t,'INFO',string.format('IA accidentee arretee %.1f s, %s',c.holdUntil-now,a.name),i)
  end
  -- Beta 1.62 (règles de la journée circuit) : en journée circuit, elle attend la piste libre derrière plus longtemps
  -- (K.rejoinWaitMaxJ s au plus) avant de repartir.
  -- Libérée : un choc relevé pendant la retenue (fin de glissade) appartient au même accident, jamais une nouvelle
  -- retenue aussitôt.
  if c.holding and (not candidate or now>=c.holdMax or now>=c.holdUntil and not traffic(frame,i,p,t.hotspotPause==true,t)) then
   c.holding=false; c.crashAt=-math.huge
   note(t,'INFO',string.format('IA accidentee repart apres %.1f s (%s)',now-(c.holdStart or now),not candidate and 'retenue annulee' or now>=c.holdMax and 'attente maximale' or 'piste libre'),i)
  end
  if c.holding then t.holdCount=t.holdCount+1 end
  rejoin(t,frame,p,c,a,i,now,ready)
 end
 for i=frame.count+1,K.maxCars do local c=t.cars[i]; c.incident=false; c.holding=false end
 -- Voiture de sécurité immobilisée en piste pendant son intervention : ramenée à son stand ; la neutralisation se
 -- poursuit en FCY (jamais un peloton bloqué derrière elle).
 if not t.neutral then t.safetyFailed=false; t.escalated=false end
 local sc=t.safety>0 and frame.cars[t.safety] or nil
 if sc and (t.safetyPhase=='out' or t.safetyPhase=='in' or t.safetyPhase=='parking') and sc.valid and not sc.pit and sc.kmh<K.redStopSpeed then t.safetyStill=t.safetyStill+dt else t.safetyStill=0 end
 if t.safetyStill>=K.scStuckTime then unavailable(t,'voiture de securite immobilisee en piste: ramenee a son stand') end
 -- Libérée, elle n'est annoncée « rentre ce tour » qu'une fois sortie de la voie des stands ; encore dedans longtemps
 -- après, elle est indisponible.
 if sc and t.safetyPhase=='out' and not t.safetyLeft then
  if sc.valid and not sc.pit then t.safetyLeft=true; note(t,'INFO',string.format('voiture de securite: en piste apres %.0f s',now-t.safetySince),t.safety)
  elseif now-t.safetySince>=K.scExitMax then unavailable(t,'voiture de securite restee dans la voie des stands: ramenee a son stand') end
 end
 local mode=profile=='C' and p.neutralization or 'local'
 -- Voiture de sécurité absente de la grille (ou indisponible pendant cette neutralisation) : Full Course Yellow.
 if mode=='sc' and (t.safety==0 or t.safetyFailed) then mode='fcy' end
 -- Correctif 1.63 (tour de formation, règlement) : un incident pendant le tour de formation donne des jaunes locaux,
 -- jamais de VSC, FCY ou voiture de sécurité, et le tour de formation continue.
 if t.formation then mode='local' end
 -- Voiture de sécurité en escalade (Beta 1.18) : une VSC ou une FCY en cours devient une intervention de la voiture de
 -- sécurité quand l'incident s'aggrave (plusieurs voitures immobilisées en piste, ou dépannage long), comme le décide
 -- la direction de course ; elle le reste tant que les règles le permettent (FCY si elle devient indisponible). Zone
 -- jaune locale seule (règles de base, Beta 1.19) : la voiture de sécurité sort directement.
 if t.neutral and t.escalated then
  if profile=='C' and p.safetyCarEscalation then mode=t.safetyFailed and 'fcy' or 'sc' else t.escalated=false end
 elseif (t.neutral and not t.relaunch and mode==t.neutralMode and (mode=='vsc' or mode=='fcy') or not t.neutral and mode=='local' and profile=='C') and not t.red and p.safetyCarEscalation
  and t.safety>0 and not t.safetyFailed and (majors>=K.scEscalateCars or longest>=p.majorIncidentTime+K.scEscalateTime) then
  local from=t.neutral and mode or 'local'
  t.escalated=true; t.neutral=true; t.relaunch=false; t.neutralMode='sc'; mode='sc'; t.ending=false; t.neutralSince=now; t.neutralUntil=max(t.neutralUntil,now+p.neutralizationHold)
  t.safetyPhase='call'; t.safetySince=now; t.safetyLeft=false
  note(t,'INFO',string.format('neutralisation: sc (escalade apres %s, %d voiture(s) immobilisee(s) en piste, %.0f s au plus)',from,majors,longest),-1)
  if p.yellowMessage then message(t,'sc') end
 end
 -- Tour de relance d'un drapeau rouge : neutralisation propre, quelles que soient les règles du profil.
 local relaunch=t.neutral and t.relaunch
 -- Beta 1.35 (relecture) : sous VSC ou FCY, le tour de relance d'un départ arrêté finit quand le meneur boucle son tour
 -- (à K.gridFormFrom m de la ligne, au moins K.relaunchTravel tour parcouru depuis la sortie des stands), jamais sur un
 -- délai : la grille se serait formée n'importe où sur le circuit, des voitures retenues en pleine piste.
 -- Beta 1.60 (tranche E) : le tour de formation du départ de la course finit de la même façon, quelles que soient les
 -- règles de relance ; abandonné (incident), il finit au délai comme une neutralisation ordinaire.
 local formLap=relaunch and t.neutralMode~='sc' and not t.formationAborted and (t.formation or profile=='C' and p.redRestart=='standing')
 local lapDone=formLap and leaderLap(t,frame,now)
 if t.formation then
  local roll=t.formationKind~='formation'
  t.rollCall=roll and t.relaunchTravel>=K.relaunchTravel and t.relaunchToLine<=K.rollCallDistance
  -- Départ lancé : aucun vert avec un incident juste après la ligne ; un tour de plus (K.formationExtraLaps au plus).
  if lapDone and roll and t.formationExtra<K.formationExtraLaps then
   local near=math.huge
   for k=1,t.zoneCount do local d=t.zones[k].spline*frame.length; if d<near then near=d end end
   if near<=K.rollClearAhead then
    t.formationExtra=t.formationExtra+1; t.relaunchTravel=0; t.rollCall=false; lapDone=false
    note(t,'INFO',string.format('depart lance: un tour de plus (incident a %.0f m apres la ligne)',near),-1)
   end
  end
 end
 -- Beta 1.64 (lot 5) : arrivée neutralisée : accrochée au dernier tour, puis tenue seule (aucun nouvel incident, aucun
 -- vert, aucune levée au délai) jusqu'au passage de la file.
 finalLatch(t,frame,now,p,profile)
 if t.scFinal and t.neutral then finalStep(t,frame,now,p)
 elseif mode~='local' and major and not t.red and not (t.neutral and now-t.neutralSince>=K.neutralMax) then
  if not t.neutral then
   t.neutral=true; t.neutralMode=mode; t.neutralSince=now; t.relaunch=false; t.ending=false
   -- Voiture de sécurité appelée : peloton d'abord sous FCY, elle reste garée le temps qu'il ralentisse.
   if mode=='sc' then t.safetyPhase='call'; t.safetySince=now end
   note(t,'INFO','neutralisation: '..mode,-1)
   if p.yellowMessage then message(t,mode,mode=='vsc' and p.vscDeltaPct or p.fcyDeltaPct) end
  elseif t.ending then
   -- Nouvel incident pendant la fin de VSC : la VSC continue.
   t.ending=false; note(t,'INFO','fin de VSC annulee: nouvel incident',-1)
  end
  -- Beta 1.60 (tranche E) : incident pendant le tour de formation : formation abandonnée, neutralisation ordinaire
  -- (FCY, delta jugé), puis départ lancé au drapeau vert, dépassement interdit jusqu'à la ligne.
  if t.formation then
   t.formation=false; t.formationAborted=true; t.rollCall=false; t.neutralSince=now
   note(t,'INFO','depart: tour de formation abandonne (incident), neutralisation '..t.neutralMode,-1)
   if p.yellowMessage then message(t,'fcy',p.fcyDeltaPct) end
  end
  -- Nouvel incident pendant le tour de rentrée : la voiture de sécurité reste en piste.
  if t.neutral and t.safetyPhase=='in' then
   t.safetyPhase='out'; t.safetySince=now; note(t,'INFO','voiture de securite: reste en piste',t.safety)
   if p.yellowMessage then message(t,'sc') end
  end
  t.neutralUntil=max(t.neutralUntil,now+p.neutralizationHold)
 elseif t.neutral and t.neutralMode=='sc' and t.safety>0 and (mode=='sc' or relaunch) and (t.safetyPhase=='exit' or t.safetyPhase=='place' or t.safetyPhase=='out' or t.safetyPhase=='in') and (now-t.neutralSince<K.neutralMax or t.safetyPhase=='in' or t.safetyPhase=='out' and t.safetyLeft and frame.cars[t.safety].valid and not frame.cars[t.safety].pit) then
  -- Incident dégagé : la voiture de sécurité rentre ce tour ; drapeau vert quand elle entre dans la voie des stands,
  -- dépassement interdit jusqu'à la ligne.
  local car=frame.cars[t.safety]
  -- Relecture du lot 3 (S4) : délai maximal de la neutralisation atteint, voiture de sécurité en piste : elle rentre
  -- d'abord (vert à son entrée dans la voie des stands), jamais de vert avec elle en piste parmi des voitures lancées.
  if t.safetyPhase=='out' and t.safetyLeft and (now>=t.neutralUntil and now-t.safetySince>=K.scMinOut or now-t.neutralSince>=K.neutralMax) then
   -- Beta 1.60 : elle ne rentre qu'une fois le peloton regroupé derrière elle (au plus K.scBunchLaps tour(s) à
   -- K.scNominalKmh d'attente : une voiture qui se traîne ne la retient pas indéfiniment).
   local inTrain,total=0,0
   local known=car.valid and not car.pit and car.splineValid and frame.length>0
   if known then inTrain,total=train(t,frame,car.spline,frame.length,0,p) end
   local late=now-t.safetySince>=K.scMinOut+min(K.scBunchMax,K.scBunchLaps*frame.length/(K.scNominalKmh/3.6)) or now-t.neutralSince>=K.neutralMax
   if not known or inTrain>=total or late then
    -- Beta 1.64 (lot 5) : file formée, attardées dans la file : dédoublement d'abord, rentrée à la fin du tour suivant.
    if not unlapHold(t,frame,now,p,profile,car,inTrain,total,late) then
    if known and inTrain<total then note(t,'INFO',string.format('voiture de securite: peloton non regroupe (%d / %d dans la file), rentre apres %.0f s',inTrain,total,now-t.safetySince),t.safety) end
    t.safetyPhase='in'; t.safetySince=now; note(t,'INFO','voiture de securite: rentre ce tour',t.safety); if p.yellowMessage then message(t,'scIn') end
    end
   end
  end
  -- Beta 1.48 : ligne franchie sans rentrer (entrée des stands manquée) : drapeau vert, rappel à son stand.
  local crossed=t.safetyPhase=='in' and car.valid and not car.pit and car.splineValid and t.safetyLastSpline>0.5 and car.spline<0.5 and U.spline(car.spline-t.safetyLastSpline)>=0
  if t.safetyPhase=='in' and (car.pit or crossed or now-t.safetySince>=K.scInMax) then
   local relaunched=t.relaunch
   if now-t.neutralSince>=K.neutralMax then t.neutralEnd=now end
   t.neutral=false; t.relaunch=false; t.safetyPhase=car.pit and 'parking' or 'parked'
   if not car.pit then t.safetyReturnAt=now end
   if not car.pit then note(t,'INFO',crossed and 'voiture de securite: ligne franchie sans rentrer, rappel a son stand apres le vert' or 'voiture de securite: rappel a son stand apres le vert',t.safety) end
   if relaunched and standing(t,frame,now,p,profile) then
    note(t,'INFO',car.pit and 'voiture de securite aux stands: formation de la grille' or 'voiture de securite non rentree, delai depasse: formation de la grille',t.safety)
   else
    -- Beta 1.47 : relance derrière la voiture de sécurité : premier tour attentif (moteur).
    t.restartSerial=(t.restartSerial or 0)+1
    t.greenUntil=now+K.greenShow; note(t,'INFO',(car.pit and 'drapeau vert: voiture de securite aux stands' or 'drapeau vert: voiture de securite non rentree, delai depasse')..(p.restartOvertake=='scIn' and ', depassement permis' or ''),t.safety)
    restartRule(t,frame,now,p)
    -- Beta 1.60 : « dépassement interdit jusqu'à la ligne » pour la file derrière la voiture de sécurité seulement ;
    -- une voiture ailleurs sur le circuit court aussitôt (avant : jusqu'à un tour entier sans dépassement ni drapeau
    -- bleu, le meneur bloqué derrière une attardée).
    local ref=car.valid and car.splineValid and car.spline or t.safetyLastSpline
    if t.restart and ref and ref>=0 and frame.length>0 then
     train(t,frame,ref,frame.length,K.scBunchGap,p)
     local freed,any=0,false
     for j=1,frame.count do local c=t.cars[j]; if c.restart and not c.inTrain then c.restart=false; freed=freed+1 end; any=any or c.restart end
     t.restart=any
     if freed>0 then note(t,'INFO',string.format('reprise: %d voiture(s) hors de la file, depassement permis aussitot',freed),-1) end
    end
   end
  end
 elseif t.neutral and (not relaunch and (mode=='local' or mode~=t.neutralMode) or (formLap and lapDone or not formLap and now>=t.neutralUntil) or now-t.neutralSince>=K.neutralMax) then
  local forced=now-t.neutralSince>=K.neutralMax or not relaunch and (mode=='local' or mode~=t.neutralMode)
  -- Fin de VSC (F1) : « VSC ENDING », drapeau vert quelques secondes plus tard, delta toujours jugé ; levée immédiate
  -- si les règles changent ou au délai maximal.
  if t.neutralMode=='vsc' and not forced and not t.ending and not formLap then
   t.ending=true; t.endingUntil=now+K.vscEnding; note(t,'INFO','fin de VSC annoncee',-1)
   if p.yellowMessage then message(t,'vscEnd') end
  elseif forced or not t.ending or now>=t.endingUntil then
   -- Délai maximal : les incidents encore en piste ne relancent pas de neutralisation sans fin.
   if now-t.neutralSince>=K.neutralMax then t.neutralEnd=now; note(t,'INFO','neutralisation levee: delai maximal',-1) end
   -- Lot 5 (course du 11 novembre : appelée à 1460 s, « rentrée à son stand » 35 s plus tard sans autre ligne) :
   -- neutralisation levée avant sa sortie : dit au journal.
   if t.neutralMode=='sc' and (t.safetyPhase=='call' or t.safetyPhase=='exit' or t.safetyPhase=='place') then note(t,'INFO','voiture de securite: rappelee avant sa sortie (neutralisation levee)',t.safety) end
   t.neutral=false; t.ending=false; if t.safetyPhase=='call' or t.safetyPhase=='exit' or t.safetyPhase=='place' or t.safetyPhase=='out' or t.safetyPhase=='in' then t.safetyPhase='parking' end
   -- Beta 1.60 (tranche E) : fin du tour de formation du départ : grille (départ arrêté), sinon départ lancé.
   local start=t.formation or t.formationAborted
   local force=nil; if start then force=t.formation and t.formationKind=='formation' end
   if relaunch and not forced and standing(t,frame,now,p,profile,force) then t.relaunch=false; t.formation=false; note(t,'INFO',start and 'fin du tour de formation: formation de la grille' or 'fin du tour de relance: formation de la grille',-1)
   else
    -- Beta 1.64 (lot 2) : départ lancé après des départs avortés (ou fin de neutralisation) : compteur remis à zéro.
    M.clearStartAbort(t)
    t.greenUntil=now+K.greenShow; note(t,'INFO','drapeau vert: fin de neutralisation',-1)
    -- Tour de relance terminé : dépassement interdit jusqu'à la ligne (ou dès le vert, Beta 1.34) ; fin de FCY ou de
    -- VSC : on court aussitôt.
    -- Beta 1.60 (tranche E) : départ lancé de la course : règle « jusqu'à la ligne » imposée (quel que soit
    -- restartOvertake) ; le moteur lance le départ (t.rollGo : journal du départ, premier virage attentif).
    if relaunch and start then
     t.relaunch=false; t.formation=false; t.formationAborted=false; t.rollCall=false; t.rollGo=true
     restart(t,frame,now,p); message(t,'rollGreen',0,-1)
     note(t,'INFO','depart lance: drapeau vert a la ligne, depassement interdit jusqu a la ligne, premier virage attentif',-1)
    elseif relaunch then t.relaunch=false; t.restartSerial=(t.restartSerial or 0)+1; restartRule(t,frame,now,p) elseif p.yellowMessage then message(t,'green') end
   end
  end
 end
 -- Reprise : une voiture qui franchit la ligne retrouve le droit de dépasser (délai maximal de sécurité).
 if t.restart then
  local any=false
  for i=1,frame.count do
   local a=frame.cars[i]; local c=t.cars[i]
   if c.restart then
    if not a.valid or a.pit or a.finished or not a.splineValid or now-t.restartSince>=K.restartMax then c.restart=false
    else
     if c.restartLast>0.5 and a.spline<0.5 and U.spline(a.spline-c.restartLast)>=0 then c.restart=false end
     c.restartLast=a.spline
    end
   end
   any=any or c.restart
  end
  t.restart=any
  if not any then note(t,'INFO','reprise: toutes les voitures ont franchi la ligne',-1) end
 end
 -- Entrée des stands fermée (règles GT et Endurance) : sous FCY, et pendant les premiers tours de voiture de sécurité.
 local closure=profile=='C' and t.neutral and p.pitsClosed or 'open'
 local scLap=frame.length/(K.scNominalKmh/3.6)
 local closed=closure~='open' and (t.neutralMode=='fcy' or closure=='pitFcySc' and t.neutralMode=='sc' and now-t.neutralSince<K.scClosedLaps*scLap)
 if closed~=t.pitsClosed then t.pitsClosed=closed; note(t,'INFO',closed and 'stands fermes: neutralisation' or 'stands rouverts',-1) end
 -- Drapeau rouge (essais, qualifications, course) : accident grave, plusieurs voitures immobilisées en piste en même
 -- temps, joueur exclu.
 -- Course suspendue : neutralisation levée, toutes les IA rentrent aux stands et y restent ; drapeau vert une fois
 -- toutes les IA rentrées, la piste dégagée et l'interruption minimale écoulée. Délai maximal tiré du circuit : un
 -- tour et quart à la vitesse de retour, la voie des stands et l'interruption minimale (5 à 30 minutes).
 -- Beta 1.47 (décision du pilote) : au moins redFlagCars voitures immobilisées à cause d'un incident et la piste
 -- vraiment bloquée ; sinon, jaunes, VSC ou voiture de sécurité comme avant (escalade selon la gravité), et le refus est
 -- noté une fois par épisode.
 local redAllowed=(profile=='C' or profile=='P' or profile=='Q') and p.redFlagEnabled
 -- Beta 1.64 (lot 5) : jamais de drapeau rouge après le damier (tenue de l'arrivée neutralisée).
 if frame.finished then redAllowed=false end
 -- Correctif 1.63 : pas de drapeau rouge décidé pendant le tour de formation.
 local redWanted=redAllowed and not t.red and not t.formation and t.redCount>=p.redFlagCars and blocked(t,frame)
 -- Beta 1.63 : drapeau rouge aussi sur carnage (DK.carnageCars voitures accidentées dans DK.carnageSpan m en moins de
 -- DK.carnageWindow s), même piste encore passable ; premier tour compris, jamais pendant le tour de formation.
 local wreck=0
 if redAllowed and not t.red and not t.formation and not redWanted then
  wreck=carnage(t,frame,now)
  if wreck>=DK.carnageCars then redWanted=true end
 end
 if redAllowed and not t.red and not redWanted and t.redStopped>=p.redFlagCars then
  if not t.redRefused then
   t.redRefused=true
   note(t,'INFO',string.format('pas de drapeau rouge: %d voitures arretees dont %d dans la file%s',t.redStopped,t.redQueued,t.redCount>=p.redFlagCars and ', piste encore passable' or ''),-1)
  end
 elseif t.redStopped<p.redFlagCars then t.redRefused=false end
 if redWanted then
  t.red=true; t.redSince=now; t.reds=(t.reds+1)%K.counterMax; t.redCancelled=false; t.standing='none'; t.gridLit=0; t.redRefused=false
  M.clearStartAbort(t)
  t.releaseN=0; for i=1,K.maxCars do t.gate[i]=false end
  t.redClearNoted=false; t.redObstacle=false
  freeze(t,frame)
  t.redMax=U.clamp(p.redFlagHold+K.redLapFactor*frame.length/(p.redFlagSpeedKmh/3.6)+K.redPitMargin,K.redFlagMax,K.redFlagMaxCap)
  if wreck>=DK.carnageCars then note(t,'INFO',string.format('drapeau rouge: carnage, %d voitures accidentees en %.0f m en moins de %.0f s',wreck,DK.carnageSpan,DK.carnageWindow),-1)
  else note(t,'INFO',string.format('drapeau rouge: %d voitures accidentees immobilisees %.0f s, piste bloquee',t.redCount,K.redIncidentStill),-1) end
  if t.neutral then t.neutral=false; if t.safetyPhase=='call' or t.safetyPhase=='exit' or t.safetyPhase=='place' or t.safetyPhase=='out' or t.safetyPhase=='in' then t.safetyPhase='parking' end end
  if p.yellowMessage then message(t,profile=='C' and 'red' or 'redSession') end
 end
 if t.red then
  local total,inPits=0,0
  local calm=true
  for i=1,frame.count do
   local a=frame.cars[i]
   if a.valid and a.control and not a.player and not a.finished and not a.safetyCar then
    total=total+1; if a.inPitBox then inPits=inPits+1 end
    if not a.inPitBox or (a.kmh or 0)>=K.redStopSpeed then calm=false end
   end
  end
  -- Correctif 1.63 (Imola, 13 novembre : voiture de sécurité retenue par AC à son emplacement, une IA arrivait encore à
  -- son stand) : reprise seulement après RK.calm s de voie des stands calme (toutes les IA arrêtées à leur emplacement).
  if calm then t.redCalmSince=t.redCalmSince or now else t.redCalmSince=nil end
  local settled=t.redCalmSince~=nil and now-t.redCalmSince>=RK.calm
  t.redTotal=total; t.redInPits=inPits
  -- Joueur aussi dans la voie des stands, sauf arrivé ou disqualifié ; au plus jusqu'au délai maximal.
  local player=frame.player>0 and frame.cars[frame.player] or nil
  t.redPlayerIn=not player or not player.valid or player.pit or player.finished or t.playerExcluded==true
  local elapsed=now-t.redSince
  -- Correctif 1.64 (décision du pilote, 13 novembre ; situations 03-10, 06-10, 06-11) : délai maximal atteint avec des IA
  -- encore en incident en piste : dépannées jusqu'à leur stand (src/engine.lua, t.redClear), reprise dès la piste vide,
  -- au plus K.redClearWait s de plus. Dépannage impossible (capacité absente ou coupée) ou sans effet : reprise forcée
  -- notée au journal (course : tour de relance sous SC, sinon VSC ou FCY ; essais, qualifications : session relancée).
  -- IA pas à leur emplacement, voie des stands agitée, joueur dehors : reprise au délai maximal, comme avant.
  local late=redAllowed and elapsed>=t.redMax and t.onTrack>0
  local hold=late and t.teleportCap==true and elapsed<t.redMax+K.redClearWait
  t.redClear=hold
  if hold and not t.redClearNoted then t.redClearNoted=true; note(t,'INFO',string.format('drapeau rouge: delai maximal atteint, piste non degagee, %d IA en piste depannees vers leur stand (attente au plus %.0f s)',t.onTrack,K.redClearWait),-1) end
  if not redAllowed or inPits>=total and settled and t.onTrack==0 and t.redPlayerIn and elapsed>=p.redFlagHold or elapsed>=t.redMax and not hold then
   t.redCalmSince=nil
   t.red=false; t.redEnd=now; t.redCancelled=not redAllowed
   if late then obstacleNote(t,frame,elapsed) end
   if not redAllowed then
    -- Annulé (règles décochées) : personne n'avait à attendre dans la voie des stands.
    t.greenUntil=now+K.greenShow; note(t,'INFO','drapeau rouge leve: regles inactives',-1)
    if p.yellowMessage then message(t,'green') end
   elseif profile~='C' then
    -- Essais et qualifications : session reprise au drapeau vert, sans tour de relance ; les IA quittent les stands
    -- l'une après l'autre (pas de bouchon à la sortie).
    release(t,frame,now,false); t.greenUntil=now+K.greenShow
    note(t,'INFO',string.format('reprise apres drapeau rouge%s: session relancee',elapsed>=t.redMax and ' (delai maximal)' or ''),-1)
    if p.yellowMessage then message(t,'sessionResume') end
   else
    -- Reprise réelle (F1, WEC, GT) : IA libérées des stands dans l'ordre du classement, tour de relance derrière la
    -- voiture de sécurité (sans elle : sous VSC ou FCY), dépassement interdit, puis jusqu'à la ligne.
    local relaunchMode=t.safety>0 and not t.safetyFailed and 'sc' or p.neutralization=='vsc' and 'vsc' or 'fcy'
    local span=release(t,frame,now,true); t.playerPit=frame.player>0 and frame.cars[frame.player].pit==true
    t.relaunchSpanUntil=now+span; t.relaunchLeader=0; t.relaunchTravel=0
    t.neutral=true; t.relaunch=true; t.ending=false; t.neutralMode=relaunchMode; t.neutralSince=now
    -- Correctif 1.64 (décision du pilote, 13 novembre) : reprise forcée, obstacle encore en piste : tour de relance de durée
    -- normale, l'obstacle sous jaune ne prolonge plus la neutralisation (comme après une neutralisation levée au délai maximal).
    if late then t.neutralEnd=now end
    t.neutralUntil=now+span+(relaunchMode=='sc' and p.neutralizationHold or frame.length/(p.fcySpeedKmh/3.6))
    if relaunchMode=='sc' then toExit(t,now); note(t,'INFO','voiture de securite: liberee pour le tour de relance, sort par la voie des stands',t.safety) end
    note(t,'INFO',string.format('reprise apres drapeau rouge%s: tour de relance sous %s',elapsed>=t.redMax and ' (delai maximal)' or '',relaunchMode),-1)
    if p.yellowMessage then message(t,relaunchMode=='sc' and 'redRestartSc' or relaunchMode=='vsc' and 'redRestartVsc' or 'redRestartFcy') end
   end
  end
 end
 -- Sortie après le temps d'appel, que l'incident soit encore en piste ou non.
 -- Beta 1.50 : libérée pour sortir juste devant le meneur : jonction des stands connue, quand le meneur en est à moins
 -- de K.scExitLead s (au plus K.scCallMaxWait s d'appel) ; jonction inconnue, après le temps d'appel.
 local length=frame.length
 if t.neutral and t.safetyPhase=='call' and now-t.safetySince>=K.scCallTime then
  local go=t.junction<0 or length<=0 or now-t.safetySince>=K.scCallMaxWait
  if not go then
   local ref=leaderOf(t,frame)
   if ref==0 then go=true
   else local b=frame.cars[ref]; go=((t.junction-b.spline)%1)*length/math.max(b.speed or 0,K.scLeaderMinSpeed)<=K.scExitLead end
  end
  if go then toExit(t,now); note(t,'INFO','voiture de securite: liberee, sort par la voie des stands',t.safety) end
 end
 if t.safety>0 and t.safetyPhase=='exit' then
  local sc=frame.cars[t.safety]
  -- Beta 1.60 (Bakou : 40 s à 0 km/h à son emplacement, peloton sous FCY) : toujours immobile à son emplacement
  -- K.scLeaveStill s après sa libération : posée en piste sans attendre K.scLeaveMax s.
  local still=t.relaunch and RK.leaveStill or K.scLeaveStill
  local stuck=not U.finite(t.exitLeftAt) and (now-t.safetySince>=K.scLeaveMax or now-t.safetySince>=still and sc.valid and sc.inPitBox and (sc.kmh or 0)<K.redStopSpeed)
  if sc.valid and not sc.inPitBox and not U.finite(t.exitLeftAt) then t.exitLeftAt=now; note(t,'INFO',string.format('voiture de securite: sortie de son stand apres %.1f s',now-t.safetySince),t.safety) end
  if sc.valid and not sc.pit and not sc.inPitBox and sc.splineValid and length>0 then
   t.safetyPhase='out'; t.safetySince=now; t.safetyLeft=true; t.scOutAt=now; t.scOutSpline=sc.spline; t.scReleaseNoted=false
   local who,near=scOut(t,frame,sc,length,p)
   note(t,'INFO',string.format('voiture de securite: sortie en piste%s',who>0 and string.format(' devant %s (%.0f m)',frame.cars[who].name,near) or ''),t.safety)
  elseif sc.valid and now>=(t.exitLogAt or -math.huge) and not (stuck or U.finite(t.exitLeftAt) and now-t.exitLeftAt>=K.scLaneMax) then
   -- Beta 1.50 : état de la voiture de sécurité libérée, toutes les K.scExitLogPeriod s (audit de la sortie en jeu).
   t.exitLogAt=now+K.scExitLogPeriod
   note(t,'INFO',string.format('voiture de securite: sortie en cours %.0f s (%.0f km/h, emplacement %s, voie des stands %s)',now-t.safetySince,sc.kmh or 0,sc.inPitBox and 'oui' or 'non',sc.pit and 'oui' or 'non'),t.safety)
  elseif stuck or U.finite(t.exitLeftAt) and now-t.exitLeftAt>=K.scLaneMax then
   note(t,'WARN',string.format('voiture de securite: %s, posee en piste hors de la vue du joueur',U.finite(t.exitLeftAt) and 'restee dans la voie des stands' or 'ne quitte pas son emplacement'),t.safety)
   toPlace(t,now)
  end
 end
 -- Beta 1.48 : pose de la voiture de sécurité en piste : jonction des stands connue, K.scPlaceJunction m après elle (IA
 -- retenues à leur emplacement jusqu'à la pose) ; inconnue, K.scPlaceFirstOut m devant la première voiture sortie de
 -- la voie des stands, une fois à K.scPlaceOnTrack m en piste ; neutralisation, K.scPlaceLeader m devant le meneur.
 -- Pose vue (voiture hors de la voie des stands) : en piste ; au plus K.scPlaceMax s une fois le point connu
 -- (K.scExitMax s en tout), sinon VSC ou FCY.
 local hold=false
 if t.safety>0 and t.safetyPhase=='place' then
  local sc=frame.cars[t.safety]
  -- Pose vue seulement près du point commandé à l'image précédente (jamais là où elle se trouvait déjà).
  if sc.valid and not sc.pit and not sc.inPitBox and sc.splineValid and t.safetyTarget>=0 and math.abs(U.spline(sc.spline-t.safetyTarget))*length<=K.scPlaceReach then
   local ref=t.safetyRef>0 and frame.cars[t.safetyRef] or nil
   t.safetyPhase='out'; t.safetySince=now; t.safetyLeft=true; t.safetyTarget=-1; t.scOutAt=now; t.scReleaseNoted=false
   -- Posée près de la sortie des stands (jonction, hauteur de son emplacement) : IA retenues jusqu'à RK.releaseDist m.
   t.scOutSpline=(t.safetyFrom:sub(1,8)=='jonction' or t.safetyFrom:sub(1,5)=='stand') and sc.spline or -1
   note(t,'INFO',string.format('voiture de securite: posee en piste a %.0f m%s (%s)',sc.spline*length,ref and string.format(', %.0f m devant %s',U.spline(sc.spline-ref.spline)*length,ref.name) or '',t.safetyFrom),t.safety)
   scOut(t,frame,sc,length,p)
  elseif length>0 then
   local base,ref,from=nil,0,''
   if t.relaunch and t.junction>=0 then base=t.junction+K.scPlaceJunction/length; from='jonction'; hold=true
   elseif t.relaunch then
    if t.firstOut>0 then local b=frame.cars[t.firstOut]; if not b.valid or b.pit or not b.splineValid then t.firstOut=0 end end
    -- Correctif 1.63 (Imola, 13 novembre : jonction inconnue, IA sorties avant elle) : personne encore sorti : posée
    -- K.scPlaceJunction m devant la hauteur de son emplacement (près de la sortie des stands), IA retenues.
    local own=frame.cars[t.safety]
    if t.firstOut==0 and own.valid and own.splineValid then base=own.spline+K.scPlaceJunction/length; from='stand'; hold=true end
    if t.firstOut==0 then
     for j=1,frame.count do
      local b=frame.cars[j]
      if t.firstOut==0 and j~=t.safety and b.valid and not b.pit and b.splineValid and (U.finite(t.openedAt[j]) and not b.player or b.player and t.playerPit) then t.firstOut=j; t.firstOutSpline=b.spline end
     end
    end
    if not base and t.firstOut>0 then
     local b=frame.cars[t.firstOut]
     if U.spline(b.spline-t.firstOutSpline)*length>=K.scPlaceOnTrack then base=b.spline+K.scPlaceFirstOut/length; ref=t.firstOut; from='premiere sortie' end
    end
   else
    local best=math.huge
    for j=1,frame.count do
     local b=frame.cars[j]
     if j~=t.safety and b.valid and not b.pit and not b.finished and b.splineValid and (b.control or b.player) then
      local pos=(b.position or 0)>=1 and b.position or math.huge
      if ref==0 or pos<best then best=pos; ref=j end
     end
    end
    if ref>0 then base=frame.cars[ref].spline+K.scPlaceLeader/length; from='meneur' end
   end
   -- Beta 1.50 : jamais en vue du joueur : point repoussé K.scHideAhead m devant lui.
   if base and seen(frame,base%1,length) then base=frame.cars[frame.player].spline+K.scHideAhead/length; from=from..', hors de vue du joueur' end
   if base then
    if not U.finite(t.safetyPlaceSince) then t.safetyPlaceSince=now end
    t.safetyTarget=free(t,frame,base%1); t.safetyRef=ref; t.safetyFrom=from
   else t.safetyTarget=-1 end
   if U.finite(t.safetyPlaceSince) and now-t.safetyPlaceSince>=K.scPlaceMax or now-t.safetySince>=K.scExitMax then placeFailed(t,frame,now,p); hold=false end
  end
 end
 -- Beta 1.50 : tour de relance : IA retenues à leur emplacement jusqu'à K.scExitGap s après la sortie de la voiture de
 -- sécurité de son emplacement (elle mène la file dans la voie des stands).
 -- Correctif 1.63 (Suzuka, 13 novembre : IA sorties des stands avant la voiture de sécurité, encore dans la voie des
 -- stands 14 s après sa sortie d'emplacement) : tour de relance : IA retenues tant que la voiture de sécurité n'est pas
 -- en piste et à RK.releaseDist m de son entrée en piste (au plus RK.releaseMax s après), comme la procédure réelle.
 if t.relaunch and t.safety>0 and not t.safetyFailed and t.releaseN>0 then
  if t.safetyPhase=='exit' then hold=true
  elseif t.safetyPhase=='out' and U.finite(t.scOutAt) and now-t.scOutAt<RK.releaseMax then
   local sc=frame.cars[t.safety]
   if sc.valid and not sc.pit and sc.splineValid and length>0 and (t.scOutSpline or -1)>=0 then
    local run=U.spline(sc.spline-t.scOutSpline)*length
    if run<RK.releaseDist then hold=true elseif not t.scReleaseNoted then t.scReleaseNoted=true; note(t,'INFO',string.format('reprise: voiture de securite en piste a %.0f m, IA liberees dans l ordre',run),-1) end
   end
  end
 end
 -- Relecture : retenue levée : départs de nouveau espacés de K.redReleaseGap s à partir de maintenant (après une longue
 -- retenue, toutes les heures de départ étaient passées).
 if t.holdAll and not hold and t.releaseN>0 and not t.red then
  for k=1,t.releaseN do local i=t.releaseList[k]; if t.gate[i] then t.releaseAt[i]=max(t.releaseAt[i],now+(k-1)*K.redReleaseGap) end end
 end
 t.holdAll=hold
 -- Sortie des stands dans l'ordre figé (Beta 1.48).
 if t.releaseN>0 and not t.red then gates(t,frame,now,hold) end
 -- Rentrée aux stands trop longue (entrée manquée, IA d'AC qui ne rentre pas) : rappel à son stand.
 if t.safetyPhase=='parking' then
  if not U.finite(t.parkingSince) then t.parkingSince=now end
  if now-t.parkingSince>=K.scParkingMax and t.safety>0 and not frame.cars[t.safety].inPitBox then t.safetyPhase='parked'; note(t,'INFO','voiture de securite: rappel a son stand (non rentree)',t.safety) end
 else t.parkingSince=-math.huge end
 -- Allure de la voiture de sécurité : K.scLeadKmh km/h tant que la première voiture derrière elle est à plus de
 -- K.scLeadGap m, puis son allure réglée.
 t.scWasSlow=t.safetySlow; t.safetySlow=false; t.safetyLastSpline=-1; t.scHead=0
 local scar=t.safety>0 and frame.cars[t.safety] or nil
 if scar and scar.valid and not scar.pit and scar.splineValid and length>0 then
  t.safetyLastSpline=scar.spline
  if t.safetyPhase=='out' or t.safetyPhase=='in' then
   local who,near=queueHead(t,frame,scar,length)
   -- Relecture du lot 3 (S2) : hystérésis (lente au-delà de K.scLeadGap m, libre en deçà de K.scFreeGap m) : sans
   -- elle, la limite et la main de l'applicateur basculaient à chaque passage des 120 m.
   t.safetySlow=near>(t.scWasSlow and K.scFreeGap or K.scLeadGap); t.scHead=who
   -- Beta 1.50 : file formée derrière elle (première voiture à moins de K.scLeadGap m) : notée et annoncée une fois.
   if not t.safetySlow and who>0 and not t.scLeadAnnounced then
    t.scLeadAnnounced=true; note(t,'INFO',string.format('voiture de securite: en tete de la file (%s a %.0f m)',frame.cars[who].name,near),t.safety)
    if p.yellowMessage then message(t,'scLeading',who-1,near) end
   end
  end
 end
 -- Beta 1.60 (Bakou, 11 novembre : le meneur a doublé la voiture de sécurité avant sa rentrée, sans une ligne au
 -- journal) : surveillance sur la position le long de la piste (jamais sur le cap des voitures : dans un virage serré
 -- la perception oublie la voiture de devant). Voiture vue derrière elle à moins de K.scWatch m, puis entièrement
 -- devant : doublée (journal, sanction des IA par le moteur, place à rendre : limite de vitesse dans M.cap, au plus
 -- K.scPassedMax s). Voiture devant elle sans l'avoir doublée (pose en piste derrière elle) : notée une fois.
 -- Beta 1.64 (lot 5) : dédoublement, exemptées.
 unlapStep(t,frame,now,p,length)
 local watching=scar~=nil and scar.valid and not scar.pit and scar.splineValid and length>0 and (t.safetyPhase=='out' or t.safetyPhase=='in')
 -- Relecture du lot 3 (S1) : voiture de sécurité arrêtée, en tête-à-queue ou hors piste : la doubler n'est pas une
 -- faute (ni ligne, ni sanction, voitures « vues derrière » oubliées).
 if watching and (scar.kmh<K.scDownKmh or scar.offtrack or t.safetyStill>0) then watching=false end
 t.scPasses=t.scPasses or {}
 for j=1,frame.count do
  local c=t.cars[j]; local b=frame.cars[j]
  if not watching or j==t.safety then c.scBehind=false; c.scPassed=false; c.scAhead=false; c.scLift=false
  elseif not b.valid or b.pit or b.finished or not b.splineValid or c.incident then c.scBehind=false; c.scPassed=false; c.scLift=false
  -- Beta 1.64 (lot 5) : l'autorisée qui la double, une dédoublée devant elle : ni « doublée par », ni place à rendre.
  elseif M.unlapping(t,j) or c.unlapOut and U.spline(scar.spline-b.spline)*length<0 then c.scBehind=false; c.scPassed=false; c.scLift=false; c.scAhead=U.spline(scar.spline-b.spline)*length<0
  else
   local half=((b.length or K.length)+(scar.length or K.length))*0.5
   local d=U.spline(scar.spline-b.spline)*length
   if d>half and d<=K.scWatch then
    if c.scPassed then c.scPassed=false; note(t,'INFO','voiture de securite: place rendue par '..b.name,j) end
    c.scAhead=false; c.scLift=false
    c.scBehind=true
   elseif d<-half and d>=-K.scWatch then
    if c.scBehind then
     c.scBehind=false; c.scPassed=true; c.scPassedAt=now; c.scAhead=true
     if b.control and not b.player then t.scPasses[#t.scPasses+1]=j end
     note(t,'WARN',string.format('voiture de securite: doublee par %s a %.0f m, place a rendre',b.name,scar.spline*length),j)
    elseif not c.scPassed and not c.scAhead then
     c.scAhead=true; c.scLift=true; c.scPassedAt=now; note(t,'INFO',string.format('voiture de securite: %s roule devant elle (%.0f m) sans l avoir doublee',b.name,-d),j)
    end
   elseif d>K.scWatch or d<-K.scWatch then c.scBehind=false end
   -- Relecture du lot 3 (N1) : voiture de sécurité retenue juste derrière celle qui l'a doublée (piste étroite, elle ne
   -- peut pas repasser) : après K.scGiveStuck s, la place est laissée, plus de limite (les deux tombaient à 30 km/h).
   -- Correctif 1.63 : de même pour une voiture devant elle sans l'avoir doublée (c.scLift : elle lève le pied).
   if (c.scPassed or c.scLift) and d<-half and d>-half-K.scGiveNear and scar.kmh<K.scLeadKmh then c.scStuck=(c.scStuck or 0)+dt else c.scStuck=0 end
   if c.scLift and not c.scPassed and (c.scStuck>=K.scGiveStuck or now-c.scPassedAt>=K.scPassedMax) then c.scLift=false; c.scStuck=0 end
   if c.scPassed and c.scStuck>=K.scGiveStuck then c.scPassed=false; c.scLift=false; c.scStuck=0; note(t,'INFO','voiture de securite: retenue derriere '..b.name..' qui l a doublee, place laissee',j) end
   if c.scPassed and now-c.scPassedAt>=K.scPassedMax then c.scPassed=false; note(t,'INFO','voiture de securite: place non rendue par '..b.name..' (delai depasse)',j) end
  end
 end
 -- Ordre figé levé : reprise finie (ligne franchie par tous, vert sans règle jusqu'à la ligne, séance reprise).
 if t.redOrderN>0 and not t.red and not t.relaunch and not t.restart and t.releaseN==0 and t.standing=='none' then clearOrder(t); note(t,'INFO','reprise: ordre du drapeau rouge leve',-1) end
 -- Indicateur de reprise du joueur (overlay, Beta 1.48) : place, voiture à suivre, état (pit, wait, go, ok, retake).
 local pl=frame.player
 t.restartRank=0; t.restartAhead=0; t.restartState=''; t.restartTarget=0
 -- Course seulement : en essais et qualifications, la séance reprend sans place à tenir.
 local r=profile=='C' and t.redOrderN>0 and pl>0 and t.redRank[pl] or nil
 if r then
  local a=frame.cars[pl]
  t.restartRank=r; t.restartAhead=r>1 and t.redOrder[r-1] or 0
  if t.red then t.restartState='pit'
  elseif a.pit then
   local j=t.restartAhead
   -- Beta 1.50 : la voiture de sécurité sort d'abord (tour de relance) : le joueur attend aussi.
   t.restartState=a.inPitBox and (t.holdAll or now<t.releaseAt[pl] or j>0 and (t.gate[j] or not ahead(frame,j,pl))) and 'wait' or 'go'
  else
   local best=math.huge
   if a.splineValid and length>0 then
    for j=1,frame.count do
     local b=frame.cars[j]; local rj=t.redRank[j]
     if j~=pl and rj and rj>r and b.valid and not b.pit and b.splineValid then
      local d=U.spline(b.spline-a.spline)*length
      if d>0 and d<K.restartRetakeRange and d<best then best=d; t.restartTarget=j end
     end
    end
   end
   t.restartState=t.restartTarget>0 and 'retake' or 'ok'
   -- Relecture 1.64 (lot 2) : joueur à l'origine d'un départ avorté : jamais « place à reprendre » pendant le tour en plus.
   if t.restartState=='retake' and t.cars[pl] and t.cars[pl].abortMark then t.restartState='ok'; t.restartTarget=0 end
  end
 end
 -- Beta 1.50 : annonces de reprise du joueur (pont) : sa place au drapeau rouge et à la sortie de la voie des stands
 -- (valeur = place, extra = indice AC (0) de la voiture à suivre, -1 en tête), une place à reprendre (valeur = indice AC
 -- de la voiture à doubler, extra = place).
 local was=t.restartWas or ''
 if t.restartState~=was then
  if t.restartState=='pit' or (was=='go' or was=='wait') and (t.restartState=='ok' or t.restartState=='retake') then
   message(t,'restartPlace',t.restartRank,t.restartAhead>0 and t.restartAhead-1 or -1)
  end
 end
 if t.restartState=='retake' and t.restartTarget>0 and (was~='retake' or t.restartTarget~=(t.restartTargetWas or 0)) then message(t,'restartRetake',t.restartTarget-1,t.restartRank) end
 t.restartWas=t.restartState; t.restartTargetWas=t.restartTarget
 if t.safety>0 and t.safetyPhase=='parking' and frame.cars[t.safety].inPitBox then note(t,'INFO','voiture de securite: rentree a son stand',t.safety) end
 -- Beta 1.50 : rappelée à son stand après le vert (ligne franchie sans rentrer, délai) : ramenée seulement hors de la
 -- vue du joueur (au plus K.scHideMax s), jamais immobilisée ni à son stand déjà.
 t.safetyHide=false
 if t.safety>0 and t.safetyPhase=='parked' and U.finite(t.safetyReturnAt or -math.huge) and now-t.safetyReturnAt<K.scHideMax then
  local sc=frame.cars[t.safety]
  if sc.valid and not sc.pit and not sc.inPitBox and sc.splineValid and sc.kmh>K.redStopSpeed and seen(frame,sc.spline,length) then t.safetyHide=true end
  if sc.inPitBox then t.safetyReturnAt=-math.huge end
 elseif t.safetyPhase~='parked' then t.safetyReturnAt=-math.huge end
 if t.safety>0 and (t.safetyPhase=='none' or t.safetyPhase=='parking' and frame.cars[t.safety].inPitBox) then t.safetyPhase='parked' end
 if t.safety==0 then t.safetyPhase='none' end
end
-- Commandes de la voiture de sécurité : garée sans pilote, libérée à vitesse limitée, rappelée aux stands.
function M.safety(t,commands,p,frame,d,states)
 if t.safety==0 then return end
 local cmd=commands[t.safety]
 -- Beta 1.48 : garée (à son emplacement, ramenée d'abord si elle est en piste) tant que son point n'est pas connu ;
 -- ensuite rendue et posée par la commande de position, d'où qu'elle soit (jamais ramenée à son stand pendant que la
 -- pose s'applique : un indicateur de stands relu avant sa position la renverrait au stand).
 cmd.scPark=t.safetyPhase=='parked' or t.safetyPhase=='call' or t.safetyPhase=='place' and not U.finite(t.safetyPlaceSince)
 -- Beta 1.48 : allure réduite tant que le peloton est loin derrière elle.
 -- Beta 1.60 (décision du pilote, 11 novembre : « elle essaye toujours d'aller le plus vite possible ») : en tête de
 -- la file, son allure libre (plus de vitesse réglée) ; jamais plus vite que le peloton ne peut la suivre : allure
 -- de référence de la voiture juste derrière elle, plus lente de K.scPacePct % (inconnue : libre). Retour au stand
 -- après le vert : allure nominale.
 local out=t.safetyPhase=='out' or t.safetyPhase=='in'
 local free=K.unlimitedSpeed
 if out and frame and d and states and (t.scHead or 0)>0 then
  local sc=frame.cars[t.safety]
  if sc.valid and sc.splineValid then
   local v=Delta.reference(d,states,t.scHead,Delta.bin(sc.spline,d.bins),p.multiClass==true,K.scPacePct,0)
   -- Relecture du lot 3 (S2) : allure du suiveur inconnue (premiers tours) : nombre fini, sous le rattrapage du
   -- peloton (K.scNominalKmh+K.scCatchUp), jamais « sans limite ».
   -- Correctif 1.63 (le pilote, 13 novembre : « elle plafonne à 160–180 km/h en ligne droite, elle doit tourner le plus
   -- vite possible ») : allure du suiveur connue : elle au plus ; inconnue : sans limite (la voiture de sécurité, plus
   -- lente qu'une voiture de course, regroupe d'elle-même la file).
   if v>0 then free=max(K.scLeadKmh,v*3.6) end
  end
 end
 -- Relecture du lot 3 (S3) : dans une zone d'incident en piste ou à son approche : allure nominale au plus (le
 -- directeur ne la pilote pas, la limite de zone ne lui était jamais appliquée).
 if out and frame and p.yellowEnabled and frame.length>0 and frame.cars[t.safety].valid and frame.cars[t.safety].splineValid then
  local sc=frame.cars[t.safety]
  for z=1,t.zoneCount do
   local zone=t.zones[z]
   if zone.onTrack and zone.slot~=t.safety then
    local at=U.spline(sc.spline-zone.spline)*frame.length+p.yellowBefore
    if at>=-K.yellowApproach and at<=p.yellowBefore+p.yellowAfter then free=min(free,K.scNominalKmh); break end
   end
  end
 end
 -- Correctif 1.63 : plus d'allure réduite fixe quand la file est loin derrière elle : la file la rattrape (rattrapage
 -- borné), et sa rentrée attend le regroupement (K.scBunchLaps tours au plus).
 cmd.scSpeed=out and free or (t.safetyPhase=='parking' or t.safetyHide) and K.scNominalKmh or K.unlimitedSpeed
 cmd.rulePit=t.safetyPhase=='in' or t.safetyPhase=='parking' or t.safetyHide==true
 -- Beta 1.50 : rappel à son stand différé tant qu'elle est en vue du joueur (elle roule vers l'entrée des stands).
 cmd.scHideWait=t.safetyHide==true
 -- Libérée (Beta 1.25) : l'applicateur la fait sortir de son emplacement.
 cmd.scRelease=t.safetyPhase=='out' or t.safetyPhase=='exit'
 -- Beta 1.48 : posée en piste au point libre (applicateur : position, puis élan de K.scLeadKmh km/h).
 if t.safetyPhase=='place' and t.safetyTarget>=0 then cmd.place=t.safetyTarget; cmd.placeFor=t.placeToken; cmd.placeKmh=K.scLeadKmh else cmd.placeKmh=nil end
end
-- Position de la voiture depuis le début de la zone jaune de l'incident (négative avant la zone).
local function position(a,zone,length,p) return U.spline(a.spline-zone.spline)*length+p.yellowBefore end
-- Beta 1.60 (Bakou, 11 novembre) : voiture de sécurité en piste : jamais doublée. Derrière elle ou à sa hauteur (pas
-- encore entièrement devant) : rattrapage borné puis son allure (à sa hauteur : K.scOverlapDrop km/h de moins, elle
-- repasse devant ; la file du directeur lâchait une voiture dès 1 m de recouvrement). Voiture qui l'a doublée : sous son
-- allure jusqu'à ce qu'elle soit de nouveau devant (c.scPassed, src/incidents.lua, M.update).
local function scGuard(t,frame,i,a,target,p)
 local sc=t.safety>0 and i~=t.safety and (t.safetyPhase=='out' or t.safetyPhase=='in') and frame.cars[t.safety] or nil
 if not sc or not sc.valid or sc.pit or not sc.splineValid then return target end
 if t.cars[i].scPassed then return min(target,max(K.scGiveFloor,sc.kmh-K.giveBackDrop)) end
 local half=((a.length or K.length)+(sc.length or K.length))*0.5
 local gap=U.spline(sc.spline-a.spline)*frame.length-half
 -- Correctif 1.63 (Suzuka, 13 novembre) : voiture devant elle sans l'avoir doublée (sortie des stands avant elle) :
 -- comme une voiture qui l'a doublée, elle lève le pied jusqu'à ce que la voiture de sécurité repasse devant, puis
 -- prend la file ; jamais elle ne s'échappe.
 if t.cars[i].scLift and gap<-2*half and gap>-K.scWatch then return min(target,max(K.scGiveFloor,sc.kmh-K.giveBackDrop)) end
 if gap>-2*half and gap<K.scQueueGap then
  if gap<0 then return min(target,max(K.trafficMinSpeed,sc.kmh-K.scOverlapDrop)) end
  return min(target,max(K.trafficMinSpeed,sc.kmh+max(0,gap-K.queueKeep)*K.queueClose))
 end
 -- Relecture du lot 3 (S6) : enveloppe de freinage du rattrapage, de K.scQueueGap à K.scWatch m derrière elle.
 if p and gap>=K.scQueueGap and gap<K.scWatch then
  local v=sc.kmh/3.6
  return min(target,max(K.trafficMinSpeed,math.sqrt(v*v+2*p.yellowDecel*(gap-K.queueKeep))*3.6))
 end
 return target
end
-- Limite de vitesse (km/h) et régime de drapeau jaune de la voiture i (IA) : la même référence que le temps delta du
-- joueur (son allure libre, sinon celle de sa classe, plus lente du pourcentage du régime ; vitesse de repli si
-- aucune n'est connue), moins une petite marge propre au pilote : les IA restent dans le vert.
-- Double jaune (incident en piste) : delta de zone ; simple jaune (hors piste) : allure un peu réduite.
function M.cap(t,frame,i,p,d,states,margin)
 local a=frame.cars[i]; local cap=K.unlimitedSpeed; local yellow=false; local length=frame.length
 local multi=p.multiClass==true
 local slow=(1-(margin or 0))*3.6
 local b=Delta.bin(a.spline,d.bins)
 if p.yellowEnabled and length>0 and a.splineValid then
  for z=1,t.zoneCount do
   local zone=t.zones[z]
   if zone.slot~=i then
    local at=position(a,zone,length,p)
    if at>=-K.yellowApproach and at<=p.yellowBefore+p.yellowAfter then
     -- Double jaune : delta de zone (ou Slow Zone à vitesse fixe) ; simple jaune : allure un peu réduite. Approche :
     -- référence au début de la zone.
     local rb=at>=0 and b or Delta.bin(zone.spline-p.yellowBefore/length,d.bins)
     local v
     -- Beta 1.47 (départs de Monza : peloton entier à 50 km/h derrière un carambolage au premier tour) : allure inconnue,
     -- repli relatif à la voiture (K.yellowUnknownPct de sa vitesse maximale vue), jamais sous yellowSpeedKmh : le même
     -- ralentissement pour une F1, une GT ou une voiture de route.
     if zone.onTrack then v=Delta.zoneReference(d,states,i,rb,multi,p,max(p.yellowSpeedKmh,K.yellowUnknownPct*(states[i].topKmh or 0))) else v=Delta.reference(d,states,i,rb,multi,K.singleYellowPct,t.cars[zone.slot].onTrack and max(p.yellowSpeedKmh,(states[i].topKmh or 0)*K.yellowUnknownPct) or 0) end
     if at>=0 then
      if v>0 then cap=min(cap,v*slow) end
      yellow=true
     else
      -- Approche : freinage jusqu'à la référence au début de la zone, à la décélération d'approche.
      if v>0 then cap=min(cap,math.sqrt(v*v+2*p.yellowDecel*(-at))*slow) end
      if -at<K.yellowNoPass then yellow=true end
     end
    end
   end
  end
 end
 local zoneYellow=yellow
 if t.neutral then
  yellow=true
  -- Voiture de sécurité appelée ou encore dans la voie des stands : delta FCY, jamais plus vite qu'elle moins une
  -- marge (elle rejoint un peloton déjà ralenti) ; en piste : son allure plus un rattrapage, puis la file (directeur).
  local merging=t.neutralMode=='sc' and (t.safetyPhase=='call' or t.safetyPhase=='exit' or t.safetyPhase=='place' or t.safety>0 and frame.cars[t.safety].pit)
  -- Beta 1.64 (lot 5) : arrivée neutralisée : jamais l'allure de la sortie (90 km/h) au dernier tour.
  if t.scFinal then merging=false end
  local target
  if t.neutralMode=='sc' and not merging then
   -- Beta 1.60 : voiture de sécurité à son allure libre : rattrapage à l'allure propre de la voiture, plus lente de
   -- K.scCatchPct % (inconnue : l'ancienne limite fixe) ; derrière elle, garde propre (scGuard), puis la file (directeur).
   -- Correctif 1.63 (voiture de sécurité sans plafond fixe) : allure propre inconnue (relance après un drapeau rouge du
   -- premier tour) : rattrapage borné (l'ancienne limite fixe) loin d'elle seulement ; à moins de K.scWatch m, son
   -- allure à elle (file, enveloppe de freinage), sinon la file plafonnée à 160 km/h la perdait.
   local known=Delta.pace(d,states,i,b,multi)>0
   -- Relecture : rattrapage inconnu relatif à elle (son allure plus K.scCatchUp), jamais sous l'ancienne limite fixe.
   local scKmh=t.safety>0 and frame.cars[t.safety].valid and frame.cars[t.safety].kmh or 0
   local catch=known and Delta.reference(d,states,i,b,multi,K.scCatchPct,0)*slow or max(K.scNominalKmh,scKmh)+K.scCatchUp
   local g=scGuard(t,frame,i,a,K.unlimitedSpeed,p)
   target=g<K.unlimitedSpeed and (known and min(g,catch) or g) or catch
   -- Beta 1.64 (lot 5) : autorisée à se dédoubler : son allure de rattrapage, sans garde de la voiture de sécurité.
   if M.unlapping(t,i) then target=catch end
   -- Relecture 164e (A11) : dédoublée encore loin de la dernière voiture de la file : allure proche de la course (plus
   -- lente de K.unlapRacePct %) jusqu'à K.unlapTailGap m d'elle, puis la file (directeur) ; allure inconnue : le
   -- rattrapage, comme avant. Le moment de la rentrée de la voiture de sécurité ne change pas.
   local tail=t.unlapTail or 0
   if known and tail>0 and tail~=i and t.cars[i].unlapOut and not M.unlapping(t,i) and a.splineValid and frame.cars[tail].splineValid and ((frame.cars[tail].spline-a.spline)%1)*length>K.unlapTailGap then target=Delta.reference(d,states,i,b,multi,K.unlapRacePct,0)*slow end
   -- Beta 1.64 (lot 5) : arrivée neutralisée, voiture de sécurité aux stands : allure de la file derrière elle.
   if t.scFinal and t.safetyPhase~='out' and t.safetyPhase~='in' then target=Delta.reference(d,states,i,b,multi,K.scPacePct,K.scNominalKmh)*slow end
  else
   target=Delta.reference(d,states,i,b,multi,t.neutralMode=='vsc' and p.vscDeltaPct or p.fcyDeltaPct,p.fcySpeedKmh)*slow
   -- Beta 1.60 (tranche E) : tour de formation : allure fixe de la tête (aucune allure apprise au départ).
   if t.formation then
    -- Relecture 1.62 (S2) : file étirée : seules les voitures devant le plus grand écart ralentissent.
    local kmh=t.formationKmh
    -- Correctif 1.63 (src/formation.lua) : voitures de devant repérées sur le cercle du tour (abscisse de la voiture
    -- devant l'écart, part de tour jusqu'à la tête), jamais par tours + abscisse (ligne franchie ou non).
    if t.formationSlowFrom and ((a.spline or 0)-t.formationSlowFrom)%1<=(t.formationSlowSpan or 0)+1e-6 then kmh=t.formationSlowKmh or kmh end
    target=kmh*(1-(margin or 0))
   end
   if merging then target=min(target,K.scNominalKmh-K.scMergeMargin) end
  end
  cap=min(cap,max(K.trafficMinSpeed,target))
 end
 if t.red then yellow=true; cap=min(cap,max(K.trafficMinSpeed,Delta.reference(d,states,i,b,multi,p.redDeltaPct,p.redFlagSpeedKmh)*slow)) end
 -- Reprise : dépassement interdit jusqu'à la ligne (file derrière la voiture de devant), sans limite de vitesse.
 if t.restart and t.cars[i].restart then yellow=true end
 -- Beta 1.64 (lot 5) : autorisée à se dédoubler : dépassement permis (une zone jaune locale reste respectée).
 if M.unlapping(t,i) then yellow=zoneYellow end
 return cap,yellow
end
-- Beta 1.59 (idée d'Artood2s, décision du pilote) : point difficile appris en direct. K.hotspotCount incidents à moins de
-- K.hotspotMeters m les uns des autres en K.hotspotWindow s : armé, noté une fois ; oublié après K.hotspotForget s sans
-- nouvel incident tout près. Les IA y sont plus prudentes et n'y commencent aucun dépassement (src/director.lua).
-- U.spline ramène déjà l'écart dans [-0,5 ; 0,5[ (tour bouclé).
local function gapMeters(s1,s2,length) return math.abs(U.spline(s1-s2))*length end
-- Correctif 1.63 : chaque point difficile armé ou relevé est aussi poussé dans t.dangerEvents (zones dangereuses gardées
-- par circuit, src/dangerfile.lua, lues par le moteur) ; paused : départ, premier tour ou relance : seulement cela.
local function dangerEvent(t,spline,level)
 t.dangerEvents=t.dangerEvents or {}
 local ev=t.dangerEvents; ev[#ev+1]={spline=spline,level=level}
end
function M.hotspotNote(t,spline,length,now,index,paused)
 if length<=0 then return end
 -- Départ, premier tour, relance : liste à part (le comptage des points difficiles reste celui d'avant) ; au moins
 -- K.hotspotCount voitures distinctes à moins de K.hotspotMeters m en K.hotspotWindow s : zone gardée pour le circuit
 -- (appliquée dès maintenant par le moteur), aucun point difficile armé ; liste vidée à cet endroit (une fois).
 if paused then
  local list=t.pausedRecent or {}; t.pausedRecent=list
  list[#list+1]={spline=spline,at=now,index=index}
  if #list>K.hotspotRecent then table.remove(list,1) end
  local count=0; local seen=t.hotspotSeen; for key in pairs(seen) do seen[key]=nil end
  for _,q in ipairs(list) do if now-q.at<=K.hotspotWindow and gapMeters(q.spline,spline,length)<=K.hotspotMeters and not seen[q.index] then seen[q.index]=true; count=count+1 end end
  if count>=K.hotspotCount then
   for k=#list,1,-1 do if gapMeters(list[k].spline,spline,length)<=K.hotspotMeters then table.remove(list,k) end end
   dangerEvent(t,spline,1); note(t,'INFO',string.format('zone dangereuse gardee: %.0f m (%d incidents au depart, au premier tour ou a la relance)',spline*length,count),-1)
  end
  return
 end
 local k=t.recentN%K.hotspotRecent+1; t.recentN=t.recentN+1
 local r=t.recent[k]; r.spline=spline; r.at=now; r.index=index or -k
 for h=1,t.hotspotN do
  local spot=t.hotspots[h]
  if gapMeters(spot.spline,spline,length)<=K.hotspotMeters then
   spot.at=now
   -- Beta 1.63 : zone dangereuse relevée d'un cran après DK.dangerRaise nouveaux incidents tout près (une ligne).
   spot.hits=(spot.hits or 0)+1
   if (spot.level or 1)<#DK.dangerPct and spot.hits>=DK.dangerRaise then
    spot.level=#DK.dangerPct; spot.hits=0
    note(t,'INFO',string.format('zone dangereuse relevee: %.0f m, vitesse des IA plafonnee a -%.0f %% de leur allure',spot.spline*length,DK.dangerPct[spot.level]*100),-1)
    dangerEvent(t,spot.spline,spot.level)
   end
   return
  end
 end
 -- Voitures distinctes (une voiture qui s'arrête deux fois au même endroit compte une fois).
 local count=0; local seen=t.hotspotSeen; for key in pairs(seen) do seen[key]=nil end
 for j=1,K.hotspotRecent do local q=t.recent[j]; if now-q.at<=K.hotspotWindow and gapMeters(q.spline,spline,length)<=K.hotspotMeters and not seen[q.index] then seen[q.index]=true; count=count+1 end end
 if count<K.hotspotCount or t.hotspotN>=K.hotspotMax or (t.hotspotN+1)*2*K.hotspotMeters>K.hotspotLengthShare*length then return end
 t.hotspotN=t.hotspotN+1
 local spot=t.hotspots[t.hotspotN]; if not spot then spot={}; t.hotspots[t.hotspotN]=spot end
 spot.spline=spline; spot.at=now; spot.level=1; spot.hits=0
 t.hotspotArmedN=(t.hotspotArmedN or 0)+1; t.hotspotArmedAt=spline -- Beta 1.61 : lu par src/zonelearn.lua
 note(t,'INFO',string.format('point difficile: %.0f m (%d incidents en %.0f s au plus), prudence accrue pour les IA, aucun depassement commence',spline*length,count,K.hotspotWindow),-1)
 note(t,'INFO',string.format('zone dangereuse: %.0f m, vitesse des IA plafonnee a -%.0f %% de leur allure de %.0f m avant a %.0f m apres',spline*length,DK.dangerPct[1]*100,DK.dangerBefore,K.hotspotMeters),-1)
 dangerEvent(t,spline,1)
end
-- Beta 1.63 : part de vitesse retirée à l'endroit spline (0 : hors de toute zone dangereuse). Zone d'un point difficile
-- encore armé : de DK.dangerBefore m avant lui (dans le sens de la piste) à K.hotspotMeters m après ; un point gardé
-- par circuit (zone « prudence », src/zones.lua) vaut le premier niveau. Les points oubliés sont retirés par nearHotspot.
function M.dangerCut(t,spline,length,now,keptZone)
 local cut=keptZone and DK.dangerPct[1] or 0
 if t.hotspotN==0 or length<=0 then return cut end
 local forget=t.hotspotForget or K.hotspotForget
 for h=1,t.hotspotN do
  local spot=t.hotspots[h]
  if now-spot.at<=forget then
   local ahead=U.spline(spot.spline-spline)*length -- positif : le point est devant
   if ahead<=DK.dangerBefore and ahead>=-K.hotspotMeters then cut=max(cut,DK.dangerPct[spot.level or 1]) end
  end
 end
 return cut
end
-- Point difficile armé à moins de K.hotspotMeters m (devant ou derrière) ; les points oubliés sont retirés ici.
function M.nearHotspot(t,spline,length,now)
 if t.hotspotN==0 or length<=0 then return false end
 local h=1
 while h<=t.hotspotN do
  local spot=t.hotspots[h]
  if now-spot.at>(t.hotspotForget or K.hotspotForget) then
   t.hotspots[h]=t.hotspots[t.hotspotN]; t.hotspots[t.hotspotN]=spot; t.hotspotN=t.hotspotN-1
  else
   if gapMeters(spot.spline,spline,length)<=K.hotspotMeters then return true end
   h=h+1
  end
 end
 return false
end
-- Drapeau jaune affiché au joueur dans une zone, à son approche ou sous neutralisation ; annonce unique par incident.
function M.player(t,frame,p,now)
 local i=frame.player
 t.focusYellow=false
 if i==0 then t.playerFlag=false; t.playerYellow=false; t.playerZone=false; t.playerInside=false; t.playerRestart=false; return false end
 t.playerRestart=t.restart and t.cars[i].restart
 -- Correctif 1.63 (tour de formation, règlement : pas de neutralisation, panneaux sans FCY) : seule une zone jaune
 -- locale met le joueur sous drapeau jaune pendant le tour de formation.
 local a=frame.cars[i]; local flag=t.neutral and not t.formation or t.red
 -- Zone jaune devant le joueur (panneau) : distance à l'incident le plus proche ; vert bref à la sortie de zone.
 local inZone,distance,inside,toZone,noPass=false,math.huge,false,math.huge,false
 -- Double jaune (incident en piste) : zone où le joueur se trouve, sinon la plus proche devant lui.
 local insideDouble,nearDouble,nearest=false,false,math.huge
 t.playerZoneSlot=0
 -- Panneau d'approche avancé selon la vitesse du joueur : temps de réaction et freinage jusqu'à la limite à la
 -- décélération d'approche (150 à 800 m) ; jamais raccourci pendant l'approche d'une même zone (freinage).
 local v,vy=a.speed or 0,p.yellowSpeedKmh/3.6
 local lead=U.clamp(v*K.flagLeadTime+max(0,v*v-vy*vy)/(2*p.yellowDecel),K.playerFlagLead,K.playerFlagLeadMax)
 if t.playerZone then lead=max(lead,t.playerLead) end
 -- Voie des stands : pas de zone jaune pour le joueur (rien n'y est jugé).
 if p.yellowEnabled and frame.length>0 and a.splineValid and not a.pit then
  for z=1,t.zoneCount do
   local zone=t.zones[z]
   if zone.slot~=i then
    local at=position(a,zone,frame.length,p)
    if at>=-lead and at<=p.yellowBefore+p.yellowAfter then
     flag=true; inZone=true; distance=min(distance,max(0,p.yellowBefore-at)); toZone=min(toZone,max(0,-at))
     -- Dépassement interdit à l'approche, à la même distance que pour les IA.
     if at>=-K.yellowNoPass then noPass=true end
     -- Dans la zone elle-même (pas seulement à son approche) : vitesse limitée pour le joueur aussi.
     if at>=0 then inside=true; t.playerZoneSlot=zone.slot; insideDouble=insideDouble or zone.onTrack
     elseif -at<nearest then nearest=-at; nearDouble=zone.onTrack end
     local c=t.cars[zone.slot]
     if c.incident and not c.announced then
      c.announced=true
      -- Beta 1.59 : une seule annonce par groupe d'incidents : rien de plus quand une zone déjà annoncée, encore active
      -- ou tenue, est à moins de yellowBefore + yellowAfter m (zones, vitesses, delta et panneaux inchangés).
      local merged=false
      for k=1,t.zoneCount do
       local other=t.zones[k]
       if other.slot~=zone.slot and other.slot~=i and t.cars[other.slot].announced and (other.onTrack or not zone.onTrack) then
        local gap=gapMeters(other.spline,zone.spline,frame.length)
        if gap<=p.yellowBefore+p.yellowAfter then merged=true; break end
       end
      end
      if not merged then
       note(t,'INFO',string.format('drapeau jaune au joueur: incident a %.0f m',math.max(0,p.yellowBefore-at)),zone.slot)
       if p.yellowMessage then message(t,'yellow',math.max(0,p.yellowBefore-at)) end
      end
     end
    end
   end
  end
 end
 if t.playerZone and not inZone then t.greenUntil=max(t.greenUntil,now+K.greenZoneShow) end
 t.playerZone=inZone; t.playerInside=inside; t.playerDistance=inZone and distance or 0; t.playerToZone=inZone and toZone or 0
 t.playerLead=inZone and lead or 0; t.playerNoPass=noPass
 t.playerZoneDouble=inZone and (inside and insideDouble or not inside and nearDouble)
 -- Beta 1.32 : drapeau jaune du joueur pour les panneaux lumineux du circuit ; le HUD natif seulement sur demande.
 t.playerYellow=flag; t.playerFlag=flag and p.yellowHud
 -- Affinage 1.64 s1 (Monza S21, pilote : « une voiture part en tête-à-queue, d'autres passent, les panneaux du secteur
 -- ne passent pas au jaune ») : les panneaux du circuit ne connaissent qu'un drapeau, celui du joueur (FLAG_TYPE) ;
 -- joueur resté aux stands (il regarde la course), ils suivent la voiture que suit la caméra : jaune à l'approche
 -- d'une zone jaune et dedans, comme pour le joueur. Aucune règle, aucun delta, aucune pénalité : panneaux seulement.
 local fs=frame.focus or 0
 if not flag and fs>0 and fs~=i and fs<=frame.count and a.pit and p.yellowEnabled and frame.length>0 then
  local b=frame.cars[fs]
  if b.valid and b.splineValid and not b.pit then
   local bv=b.speed or 0
   local blead=U.clamp(bv*K.flagLeadTime+max(0,bv*bv-vy*vy)/(2*p.yellowDecel),K.playerFlagLead,K.playerFlagLeadMax)
   for z=1,t.zoneCount do
    local zone=t.zones[z]
    if zone.slot~=fs then
     local at=position(b,zone,frame.length,p)
     if at>=-blead and at<=p.yellowBefore+p.yellowAfter then t.focusYellow=true; break end
    end
   end
  end
 end
 return t.playerFlag
end
-- Affinage 1.63 (décision du pilote du 13 novembre : « jaune d'avertissement seul ») : IA anormalement lente tenue au
-- bord (s.edgePin, src/director.lua) devant le joueur, au plus K.slowWarnLead m devant ou K.slowWarnAfter m derrière :
-- drapeau jaune d'avertissement (panneau de l'overlay, panneaux lumineux du circuit, champ yellow du pont). Jamais de
-- limite de vitesse, de delta, d'interdiction de doubler ni de pénalité, pour personne ; aucune zone (ni zone
-- dangereuse, ni compte du drapeau rouge, du carnage ou de la neutralisation). Fin quand elle retrouve son allure,
-- rentre aux stands ou s'arrête (une voiture arrêtée garde la logique d'incident). Une ligne au journal par voiture.
function M.warn(t,frame,p,states)
 local was=t.playerWarnSlot or 0
 t.playerWarn=false; t.playerWarnDistance=0; t.playerWarnSlot=0
 local i=frame.player
 if i~=0 and p.yellowEnabled and frame.length>0 and not t.red and not t.neutral and not t.formation and not t.playerYellow and states then
  local a=frame.cars[i]
  if a.valid and a.splineValid and not a.pit then
   local best=math.huge
   for j=1,frame.count do
    local s=states[j]; local b=frame.cars[j]
    if j~=i and s and s.edgePin and s.abnormal and b.valid and b.splineValid and not b.pit and not b.offtrack and not b.safetyCar and not t.cars[j].incident and b.kmh>=K.incidentStopSpeed then
     local d=U.spline(b.spline-a.spline)*frame.length
     if d>=-K.slowWarnAfter and d<=K.slowWarnLead and math.abs(d)<best then best=math.abs(d); t.playerWarnSlot=j; t.playerWarnDistance=math.max(0,d) end
    end
   end
   t.playerWarn=t.playerWarnSlot>0
  end
 end
 if t.playerWarn and t.playerWarnSlot~=was then
  local b=frame.cars[t.playerWarnSlot]
  note(t,'INFO',string.format('jaune d avertissement: %s roule lentement au bord, %.0f m devant le joueur (%.0f km/h)',b.name,t.playerWarnDistance,b.kmh),t.playerWarnSlot)
 end
 return t.playerWarn
end
return M
