-- Incidents de piste, drapeaux jaunes et neutralisations : décisions pures. Lecture dans snapshot, écritures dans applier.
local U=require('src/util')
local K=require('src/config').K
local Delta=require('src/delta')
local Grid=require('src/grid')
local min,max=math.min,math.max
local M={}
local function clearCar(c)
 c.incident=false; c.dismissed=false; c.since=0; c.spline=0; c.onTrack=false; c.clearedAt=-math.huge; c.wrong=0; c.spin=0; c.contact=false; c.lastSpline=-1; c.calm=0
 c.still=0; c.halt=0; c.moved=false; c.fresh=true; c.slow=0; c.counted=false; c.lastCrash=-math.huge; c.window=0; c.windowStart=-math.huge; c.crashAt=-math.huge; c.holding=false; c.holdUntil=0; c.holdMax=0; c.announced=false
 c.restart=false; c.restartLast=0; c.stuckFor=0; c.anchorX=math.huge; c.anchorZ=math.huge
 -- Beta 1.59 : vitesse au début de la glissade, tête-à-queue confirmé (perte de vitesse), zone double (arrêtée ou au pas).
 c.spinFrom=0; c.spun=false; c.double=false; c.backOn=0; c.hotspotFed=false
end
function M.new()
 local t={cars={},zones={},zoneCount=0,activeCount=0,holdCount=0,neutral=false,neutralMode='local',neutralSince=0,neutralUntil=0,
  safety=0,safetyPhase='none',safetySince=0,safetyStill=0,safetyFailed=false,safetyLeft=false,started=0,held=0,onTrack=0,red=false,redSince=0,redCancelled=false,reds=0,redTotal=0,redInPits=0,
  greenUntil=-math.huge,playerZone=false,playerInside=false,playerToZone=0,playerLead=0,playerNoPass=false,playerZoneSlot=0,suppressed={queue=0,spawn=0,crawl=0},playerDistance=0,freshOnTrack=0,redEnd=-math.huge,redMax=0,neutralEnd=-math.huge,frameId=0,messagePriority=0,messageFrame=-1,
  playerFlag=false,playerYellow=false,playerZoneDouble=false,slipperyUntil=-math.huge,messageId=0,messageKind='',messageValue=0,messageExtra=0,messageText='',
  standing='none',gridReady=false,gridWhy='',gridLit=0,gridSlot=0,gridGap=0,gridPit=false,gridPlaced=false,gridPassed=false,jumpUntil=-math.huge,
  relaunchLeader=0,relaunchSpline=0,relaunchTravel=0,relaunchSpanUntil=-math.huge,
  relaunch=false,escalated=false,ending=false,endingUntil=0,restart=false,restartSince=0,playerRestart=false,pitsClosed=false,releaseAt={},
  gate={},gateSince={},openedAt={},releaseList={},releaseN=0,redOrder={},redRank={},redOrderN=0,restored={},junction=-1,
  safetyPlaceSince=-math.huge,safetyTarget=-1,safetyRef=0,safetyFrom='',safetySlow=false,safetyLastSpline=-1,parkingSince=-math.huge,firstOut=0,firstOutSpline=0,
  restartRank=0,restartAhead=0,restartState='',restartTarget=0,
  -- Beta 1.59 : incidents récents (point difficile) et points difficiles armés.
  recent={},recentN=0,hotspots={},hotspotN=0,hotspotSeen={},hotspotPause=false,hotspotForget=K.hotspotForget}
 for i=1,K.maxCars do
  t.releaseAt[i]=-math.huge; t.gate[i]=false; t.gateSince[i]=-math.huge; t.openedAt[i]=-math.huge
  local c={identity=''}; clearCar(c); c.crashes=0; t.cars[i]=c
  t.zones[i]={slot=0,spline=0,onTrack=false}
 end
 for k=1,K.hotspotRecent do t.recent[k]={spline=0,at=-math.huge} end
 return t
end
-- Beta 1.48 : ordre figé au drapeau rouge (sortie des stands, grille, overlay, dépassements permis pour reprendre sa
-- place) : effacé quand toutes les voitures ont franchi la ligne, à l'extinction des feux ou au drapeau rouge suivant.
local function clearOrder(t)
 t.redOrderN=0; for i=1,K.maxCars do t.redRank[i]=nil end
 for key in pairs(t.restored) do t.restored[key]=nil end
 t.restartRank=0; t.restartAhead=0; t.restartState=''; t.restartTarget=0
end
M.clearOrder=clearOrder
-- Relecture 1.52 : rappels et avis des stands du joueur (écrits par engine.lua, lus par le panneau et le pont) vidés au
-- changement de session et app à l'arrêt (jamais ceux de la session précédente).
local noTyres={}
function M.clearPlayerPit(t)
 t.playerPitDue=0; t.playerPitRemind=false; t.playerPitShowRemind=false; t.sePlanMode=nil; t.playerPitCompound=false; t.playerPitHint=false; t.playerTyre=''; t.playerTyreOthers=noTyres
 t.playerPlan=''; t.playerPlanned=''; t.playerPlanNotice=false; t.playerPitNotice=''; t.playerPitFrom=''; t.playerPitTo=''
end
function M.reset(t)
 t.heldKind=nil
 M.clearPlayerPit(t)
 for i=1,K.maxCars do clearCar(t.cars[i]) end
 t.zoneCount=0; t.activeCount=0; t.holdCount=0; t.neutral=false; t.neutralUntil=0; t.playerFlag=false; t.playerYellow=false; t.safetyPhase='none'; t.red=false; t.onTrack=0; t.playerZone=false; t.playerInside=false; t.slipperyUntil=-math.huge
 t.safetyStill=0; t.safetyFailed=false; t.safetyLeft=false; t.exitLeftAt=-math.huge; t.safetyReturnAt=-math.huge; t.safetyHide=false; t.scLeadAnnounced=false; t.restartWas=''; t.restartTargetWas=0; t.escalated=false; t.relaunch=false; t.ending=false; t.restart=false; t.playerRestart=false; t.pitsClosed=false
 for i=1,K.maxCars do t.releaseAt[i]=-math.huge; t.gate[i]=false; t.gateSince[i]=-math.huge; t.openedAt[i]=-math.huge end
 t.releaseN=0; clearOrder(t); t.safetyPlaceSince=-math.huge; t.safetyTarget=-1; t.safetySlow=false; t.safetyLastSpline=-1; t.parkingSince=-math.huge; t.firstOut=0
 t.standing='none'; t.gridLit=0; t.jumpUntil=-math.huge; t.gridPlaced=false; t.gridPassed=false
 t.relaunchLeader=0; t.relaunchTravel=0; t.relaunchSpanUntil=-math.huge
 t.recentN=0; for k=1,K.hotspotRecent do t.recent[k].at=-math.huge end; t.hotspotN=0
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
 for i=1,K.maxCars do
  local c=t.cars[i]
  for _,key in ipairs({'since','clearedAt','windowStart','crashAt','holdUntil','holdMax','lastCrash','holdStart'}) do if U.finite(c[key]) then c[key]=c[key]-amount end end
  if U.finite(t.releaseAt[i]) then t.releaseAt[i]=t.releaseAt[i]-amount end
  if U.finite(t.gateSince[i]) then t.gateSince[i]=t.gateSince[i]-amount end
  if U.finite(t.openedAt[i]) then t.openedAt[i]=t.openedAt[i]-amount end
 end
end
-- Un seul message affiché par image : le plus important l'emporte (rouge, neutralisation, vert, jaune, stands, météo).
local priorities={penaltyDq=5,aiDq=4,aiBlackFlag=4,aiSanction=2,playerSanction=3,penaltyDelta=5,penaltyPass=5,penaltyRed=5,penaltyStop=5,red=5,redSession=5,sessionResume=3,redRestartSc=4,standing=4,penaltyJump=5,redRestartVsc=4,redRestartFcy=4,sc=4,fcy=4,vsc=4,vscEnd=4,scIn=3,green=3,restart=3,yellow=2,pitOpen=1,pitOpenCsp=1,pitCompound=1,pitPlanSame=1,pitPlanOk=1,fastCar=1,pitNotCounted=2,pitValidated=1,wet=1,dry=1,drsLaps=1,drsOn=1,drsWet=1,scOut=3,scLeading=2,restartPlace=2,restartRetake=2}
-- Beta 1.49 : annonces de l'arrêt F1 du joueur (lues par SpotterEnginer) : jamais perdues. Écartées par une annonce plus
-- importante de la même image, ou remplacées par elle, elles attendent (une seule place, la dernière l'emporte) la
-- première image suivante sans annonce (M.flushHeld, en fin d'image), au plus K.heldMessageMax s.
local held={pitCompound=true,pitPlanSame=true,pitPlanOk=true,pitNotCounted=true,pitValidated=true,scOut=true,scLeading=true,restartPlace=true,restartRetake=true}
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
function M.lightsOut(t)
 if t.redOrderN>0 then clearOrder(t); note(t,'INFO','reprise: ordre du drapeau rouge leve (extinction des feux)',-1) end
 if not t.restart then return end
 for i=1,#t.cars do t.cars[i].restart=false end
 t.restart=false; t.playerRestart=false
 note(t,'INFO','reprise: depassement permis a l extinction des feux',-1)
end
-- Fin du tour de relance d'un drapeau rouge en course (Beta 1.34) : départ arrêté si les règles le demandent et que
-- tout est prêt (t.gridReady, décidé par le moteur : capacités, sens latéral, piste), sinon départ lancé (raison au
-- journal). Dépassement interdit jusqu'à la ligne, juste devant la grille.
local function standing(t,frame,now,p,profile)
 if profile~='C' or p.redRestart~='standing' then return false end
 if not t.gridReady then note(t,'INFO','relance arretee indisponible ('..(t.gridWhy~='' and t.gridWhy or '?')..'): depart lance',-1); return false end
 t.standing='grid'; t.gridLit=0; note(t,'INFO','relance: depart arrete (SS)',-1)
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
   if b.valid and not b.pit and not b.finished and not b.safetyCar and b.splineValid and (b.control or b.player) then
    local pos=(b.position or 0)>=1 and b.position or math.huge
    if i==0 or pos<best then best=pos; i=j end
   end
  end
  t.relaunchLeader=i
  if i>0 then t.relaunchSpline=frame.cars[i].spline end
  return false
 end
 local step=U.spline(a.spline-t.relaunchSpline); t.relaunchSpline=a.spline
 if step>0 then t.relaunchTravel=t.relaunchTravel+step end
 return t.relaunchTravel>=K.relaunchTravel and ((-a.spline)%1)*frame.length<=K.gridFormFrom
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
 if (t.redOrderN or 0)==0 or not (t.relaunch or t.restart or (t.releaseN or 0)>0 or t.standing~='none') then return false end
 local ri,rj=t.redRank[i],t.redRank[j]
 return ri~=nil and rj~=nil and ri<rj
end
-- Dépassement permis noté une fois par paire.
function M.restored(t,frame,i,j)
 local key=i*(K.maxCars+1)+j
 if t.restored[key] then return end
 t.restored[key]=true
 note(t,'INFO',string.format('reprise: %s reprend sa place sur %s (ordre du drapeau rouge), depassement permis',frame.cars[i].name,frame.cars[j].name),i)
end
-- Une voiture lancée arrive derrière : l'IA arrêtée attend avant de repartir.
local function traffic(frame,i,p)
 local a=frame.cars[i]; local length=frame.length
 if length<=0 or not a.splineValid then return false end
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=i and b.valid and not b.pit and b.splineValid and b.kmh>=K.rejoinSpeed then
   local behind=U.spline(a.spline-b.spline)*length
   if behind>0 and behind<p.rejoinGap then return true end
  end
 end
 return false
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
 t.placeSerial=(t.placeSerial or 0)%K.counterMax+1; t.placeToken='sc'..t.placeSerial
end
-- Beta 1.50 : voiture de sécurité libérée à son emplacement (attente native d'AC levée ; jamais garée sans pilote) :
-- elle sort d'elle-même par la voie des stands et entre en piste, vue du joueur ; repli sur la pose en piste (hors de
-- sa vue) si elle ne quitte pas son emplacement en K.scLeaveMax s, ou la voie des stands en K.scLaneMax s.
local function toExit(t,now)
 t.safetyPhase='exit'; t.safetySince=now; t.safetyLeft=false; t.exitLeftAt=-math.huge; t.safetyPlaceSince=-math.huge
 t.safetyTarget=-1; t.firstOut=0; t.scLeadAnnounced=false; t.exitLogAt=-math.huge
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
   if c.lastSpline>=0 and a.kmh>=K.wrongWaySpeed and U.spline(a.spline-c.lastSpline)<0 then c.wrong=min(K.wrongWayTime*2,c.wrong+dt) else c.wrong=max(0,c.wrong-dt) end
   c.lastSpline=a.spline
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
  if c.still==0 then c.hotspotFed=false end
  if incident and not c.incident then
   c.since=now; c.announced=false
   if not c.dismissed then
    t.started=t.started+1
    note(t,'INFO',string.format('incident: %s, %s, %.0f m, %.0f km/h, %s',c.halt>=K.obstacleTime and 'arret' or c.spun and 'tete-a-queue' or 'contresens',
     a.offtrack and 'hors piste' or 'en piste',a.spline*frame.length,a.kmh,a.name),i)
    if not t.hotspotPause and not c.hotspotFed then c.hotspotFed=true; M.hotspotNote(t,a.spline,frame.length,now,i) end
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
   c.holdUntil=now+U.lerp(p.incidentStopMin,p.incidentStopMax,U.unit(seed,i,K.crashSalt+c.crashes)); c.holdMax=c.holdUntil+K.rejoinWaitMax
   c.holdStart=now; t.held=t.held+1; note(t,'INFO',string.format('IA accidentee arretee %.1f s, %s',c.holdUntil-now,a.name),i)
  end
  -- Libérée : un choc relevé pendant la retenue (fin de glissade) appartient au même accident, jamais une nouvelle
  -- retenue aussitôt.
  if c.holding and (not candidate or now>=c.holdMax or now>=c.holdUntil and not traffic(frame,i,p)) then
   c.holding=false; c.crashAt=-math.huge
   note(t,'INFO',string.format('IA accidentee repart apres %.1f s (%s)',now-(c.holdStart or now),not candidate and 'retenue annulee' or now>=c.holdMax and 'attente maximale' or 'piste libre'),i)
  end
  if c.holding then t.holdCount=t.holdCount+1 end
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
 local formLap=relaunch and t.neutralMode~='sc' and profile=='C' and p.redRestart=='standing'
 local lapDone=formLap and leaderLap(t,frame,now)
 if mode~='local' and major and not t.red and not (t.neutral and now-t.neutralSince>=K.neutralMax) then
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
  -- Nouvel incident pendant le tour de rentrée : la voiture de sécurité reste en piste.
  if t.neutral and t.safetyPhase=='in' then
   t.safetyPhase='out'; t.safetySince=now; note(t,'INFO','voiture de securite: reste en piste',t.safety)
   if p.yellowMessage then message(t,'sc') end
  end
  t.neutralUntil=max(t.neutralUntil,now+p.neutralizationHold)
 elseif t.neutral and t.neutralMode=='sc' and t.safety>0 and (mode=='sc' or relaunch) and (t.safetyPhase=='exit' or t.safetyPhase=='place' or t.safetyPhase=='out' or t.safetyPhase=='in') and now-t.neutralSince<K.neutralMax then
  -- Incident dégagé : la voiture de sécurité rentre ce tour ; drapeau vert quand elle entre dans la voie des stands,
  -- dépassement interdit jusqu'à la ligne.
  local car=frame.cars[t.safety]
  if t.safetyPhase=='out' and t.safetyLeft and now>=t.neutralUntil and now-t.safetySince>=K.scMinOut then
   t.safetyPhase='in'; t.safetySince=now; note(t,'INFO','voiture de securite: rentre ce tour',t.safety); if p.yellowMessage then message(t,'scIn') end
  end
  -- Beta 1.48 : ligne franchie sans rentrer (entrée des stands manquée) : drapeau vert, rappel à son stand.
  local crossed=t.safetyPhase=='in' and car.valid and not car.pit and car.splineValid and t.safetyLastSpline>0.5 and car.spline<0.5 and U.spline(car.spline-t.safetyLastSpline)>=0
  if t.safetyPhase=='in' and (car.pit or crossed or now-t.safetySince>=K.scInMax) then
   local relaunched=t.relaunch
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
   t.neutral=false; t.ending=false; if t.safetyPhase=='call' or t.safetyPhase=='exit' or t.safetyPhase=='place' or t.safetyPhase=='out' or t.safetyPhase=='in' then t.safetyPhase='parking' end
   if relaunch and not forced and standing(t,frame,now,p,profile) then t.relaunch=false; note(t,'INFO','fin du tour de relance: formation de la grille',-1)
   else
    t.greenUntil=now+K.greenShow; note(t,'INFO','drapeau vert: fin de neutralisation',-1)
    -- Tour de relance terminé : dépassement interdit jusqu'à la ligne (ou dès le vert, Beta 1.34) ; fin de FCY ou de
    -- VSC : on court aussitôt.
    if relaunch then t.relaunch=false; t.restartSerial=(t.restartSerial or 0)+1; restartRule(t,frame,now,p) elseif p.yellowMessage then message(t,'green') end
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
 local scLap=frame.length/(p.safetyCarSpeedKmh/3.6)
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
 local redWanted=redAllowed and not t.red and t.redCount>=p.redFlagCars and blocked(t,frame)
 if redAllowed and not t.red and not redWanted and t.redStopped>=p.redFlagCars then
  if not t.redRefused then
   t.redRefused=true
   note(t,'INFO',string.format('pas de drapeau rouge: %d voitures arretees dont %d dans la file%s',t.redStopped,t.redQueued,t.redCount>=p.redFlagCars and ', piste encore passable' or ''),-1)
  end
 elseif t.redStopped<p.redFlagCars then t.redRefused=false end
 if redWanted then
  t.red=true; t.redSince=now; t.reds=(t.reds+1)%K.counterMax; t.redCancelled=false; t.standing='none'; t.gridLit=0; t.redRefused=false
  t.releaseN=0; for i=1,K.maxCars do t.gate[i]=false end
  freeze(t,frame)
  t.redMax=U.clamp(p.redFlagHold+K.redLapFactor*frame.length/(p.redFlagSpeedKmh/3.6)+K.redPitMargin,K.redFlagMax,K.redFlagMaxCap)
  note(t,'INFO',string.format('drapeau rouge: %d voitures accidentees immobilisees %.0f s, piste bloquee',t.redCount,K.redIncidentStill),-1)
  if t.neutral then t.neutral=false; if t.safetyPhase=='call' or t.safetyPhase=='exit' or t.safetyPhase=='place' or t.safetyPhase=='out' or t.safetyPhase=='in' then t.safetyPhase='parking' end end
  if p.yellowMessage then message(t,profile=='C' and 'red' or 'redSession') end
 end
 if t.red then
  local total,inPits=0,0
  for i=1,frame.count do
   local a=frame.cars[i]
   if a.valid and a.control and not a.player and not a.finished and not a.safetyCar then total=total+1; if a.inPitBox then inPits=inPits+1 end end
  end
  t.redTotal=total; t.redInPits=inPits
  -- Joueur aussi dans la voie des stands, sauf arrivé ou disqualifié ; au plus jusqu'au délai maximal.
  local player=frame.player>0 and frame.cars[frame.player] or nil
  t.redPlayerIn=not player or not player.valid or player.pit or player.finished or t.playerExcluded==true
  local elapsed=now-t.redSince
  if not redAllowed or inPits>=total and t.onTrack==0 and t.redPlayerIn and elapsed>=p.redFlagHold or elapsed>=t.redMax then
   t.red=false; t.redEnd=now; t.redCancelled=not redAllowed
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
  if sc.valid and not sc.inPitBox and not U.finite(t.exitLeftAt) then t.exitLeftAt=now; note(t,'INFO',string.format('voiture de securite: sortie de son stand apres %.1f s',now-t.safetySince),t.safety) end
  if sc.valid and not sc.pit and not sc.inPitBox and sc.splineValid and length>0 then
   t.safetyPhase='out'; t.safetySince=now; t.safetyLeft=true
   local who,near=scOut(t,frame,sc,length,p)
   note(t,'INFO',string.format('voiture de securite: sortie en piste%s',who>0 and string.format(' devant %s (%.0f m)',frame.cars[who].name,near) or ''),t.safety)
  elseif sc.valid and now>=(t.exitLogAt or -math.huge) and not (not U.finite(t.exitLeftAt) and now-t.safetySince>=K.scLeaveMax or U.finite(t.exitLeftAt) and now-t.exitLeftAt>=K.scLaneMax) then
   -- Beta 1.50 : état de la voiture de sécurité libérée, toutes les K.scExitLogPeriod s (audit de la sortie en jeu).
   t.exitLogAt=now+K.scExitLogPeriod
   note(t,'INFO',string.format('voiture de securite: sortie en cours %.0f s (%.0f km/h, emplacement %s, voie des stands %s)',now-t.safetySince,sc.kmh or 0,sc.inPitBox and 'oui' or 'non',sc.pit and 'oui' or 'non'),t.safety)
  elseif not U.finite(t.exitLeftAt) and now-t.safetySince>=K.scLeaveMax or U.finite(t.exitLeftAt) and now-t.exitLeftAt>=K.scLaneMax then
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
   t.safetyPhase='out'; t.safetySince=now; t.safetyLeft=true; t.safetyTarget=-1
   note(t,'INFO',string.format('voiture de securite: posee en piste a %.0f m%s (%s)',sc.spline*length,ref and string.format(', %.0f m devant %s',U.spline(sc.spline-ref.spline)*length,ref.name) or '',t.safetyFrom),t.safety)
   scOut(t,frame,sc,length,p)
  elseif length>0 then
   local base,ref,from=nil,0,''
   if t.relaunch and t.junction>=0 then base=t.junction+K.scPlaceJunction/length; from='jonction'; hold=true
   elseif t.relaunch then
    if t.firstOut>0 then local b=frame.cars[t.firstOut]; if not b.valid or b.pit or not b.splineValid then t.firstOut=0 end end
    if t.firstOut==0 then
     for j=1,frame.count do
      local b=frame.cars[j]
      if t.firstOut==0 and j~=t.safety and b.valid and not b.pit and b.splineValid and (U.finite(t.openedAt[j]) and not b.player or b.player and t.playerPit) then t.firstOut=j; t.firstOutSpline=b.spline end
     end
    end
    if t.firstOut>0 then
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
 if t.relaunch and t.safetyPhase=='exit' and not (U.finite(t.exitLeftAt) and now-t.exitLeftAt>=K.scExitGap) then hold=true end
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
 t.safetySlow=false; t.safetyLastSpline=-1
 local scar=t.safety>0 and frame.cars[t.safety] or nil
 if scar and scar.valid and not scar.pit and scar.splineValid and length>0 then
  t.safetyLastSpline=scar.spline
  if t.safetyPhase=='out' or t.safetyPhase=='in' then
   local who,near=queueHead(t,frame,scar,length)
   t.safetySlow=near>K.scLeadGap
   -- Beta 1.50 : file formée derrière elle (première voiture à moins de K.scLeadGap m) : notée et annoncée une fois.
   if not t.safetySlow and who>0 and not t.scLeadAnnounced then
    t.scLeadAnnounced=true; note(t,'INFO',string.format('voiture de securite: en tete de la file (%s a %.0f m)',frame.cars[who].name,near),t.safety)
    if p.yellowMessage then message(t,'scLeading',who-1,near) end
   end
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
function M.safety(t,commands,p)
 if t.safety==0 then return end
 local cmd=commands[t.safety]
 -- Beta 1.48 : garée (à son emplacement, ramenée d'abord si elle est en piste) tant que son point n'est pas connu ;
 -- ensuite rendue et posée par la commande de position, d'où qu'elle soit (jamais ramenée à son stand pendant que la
 -- pose s'applique : un indicateur de stands relu avant sa position la renverrait au stand).
 cmd.scPark=t.safetyPhase=='parked' or t.safetyPhase=='call' or t.safetyPhase=='place' and not U.finite(t.safetyPlaceSince)
 -- Beta 1.48 : allure réduite tant que le peloton est loin derrière elle.
 local lead=(t.safetyPhase=='out' or t.safetyPhase=='in') and t.safetySlow and min(K.scLeadKmh,p.safetyCarSpeedKmh)
 cmd.scSpeed=lead or (t.safetyPhase=='out' or t.safetyPhase=='in' or t.safetyPhase=='parking' or t.safetyHide) and p.safetyCarSpeedKmh or K.unlimitedSpeed
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
 if t.neutral then
  yellow=true
  -- Voiture de sécurité appelée ou encore dans la voie des stands : delta FCY, jamais plus vite qu'elle moins une
  -- marge (elle rejoint un peloton déjà ralenti) ; en piste : son allure plus un rattrapage, puis la file (directeur).
  local merging=t.neutralMode=='sc' and (t.safetyPhase=='call' or t.safetyPhase=='exit' or t.safetyPhase=='place' or t.safety>0 and frame.cars[t.safety].pit)
  local target
  if t.neutralMode=='sc' and not merging then target=p.safetyCarSpeedKmh+K.scCatchUp
  else
   target=Delta.reference(d,states,i,b,multi,t.neutralMode=='vsc' and p.vscDeltaPct or p.fcyDeltaPct,p.fcySpeedKmh)*slow
   if merging then target=min(target,p.safetyCarSpeedKmh-K.scMergeMargin) end
  end
  cap=min(cap,max(K.trafficMinSpeed,target))
 end
 if t.red then yellow=true; cap=min(cap,max(K.trafficMinSpeed,Delta.reference(d,states,i,b,multi,p.redDeltaPct,p.redFlagSpeedKmh)*slow)) end
 -- Reprise : dépassement interdit jusqu'à la ligne (file derrière la voiture de devant), sans limite de vitesse.
 if t.restart and t.cars[i].restart then yellow=true end
 return cap,yellow
end
-- Beta 1.59 (idée d'Artood2s, décision du pilote) : point difficile appris en direct. K.hotspotCount incidents à moins de
-- K.hotspotMeters m les uns des autres en K.hotspotWindow s : armé, noté une fois ; oublié après K.hotspotForget s sans
-- nouvel incident tout près. Les IA y sont plus prudentes et n'y commencent aucun dépassement (src/director.lua).
-- U.spline ramène déjà l'écart dans [-0,5 ; 0,5[ (tour bouclé).
local function gapMeters(s1,s2,length) return math.abs(U.spline(s1-s2))*length end
function M.hotspotNote(t,spline,length,now,index)
 if length<=0 then return end
 local k=t.recentN%K.hotspotRecent+1; t.recentN=t.recentN+1
 local r=t.recent[k]; r.spline=spline; r.at=now; r.index=index or -k
 for h=1,t.hotspotN do local spot=t.hotspots[h]; if gapMeters(spot.spline,spline,length)<=K.hotspotMeters then spot.at=now; return end end
 -- Voitures distinctes (une voiture qui s'arrête deux fois au même endroit compte une fois).
 local count=0; local seen=t.hotspotSeen; for key in pairs(seen) do seen[key]=nil end
 for j=1,K.hotspotRecent do local q=t.recent[j]; if now-q.at<=K.hotspotWindow and gapMeters(q.spline,spline,length)<=K.hotspotMeters and not seen[q.index] then seen[q.index]=true; count=count+1 end end
 if count<K.hotspotCount or t.hotspotN>=K.hotspotMax or (t.hotspotN+1)*2*K.hotspotMeters>K.hotspotLengthShare*length then return end
 t.hotspotN=t.hotspotN+1
 local spot=t.hotspots[t.hotspotN]; if not spot then spot={}; t.hotspots[t.hotspotN]=spot end
 spot.spline=spline; spot.at=now
 note(t,'INFO',string.format('point difficile: %.0f m (%d incidents en %.0f s au plus), prudence accrue pour les IA, aucun depassement commence',spline*length,count,K.hotspotWindow),-1)
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
 if i==0 then t.playerFlag=false; t.playerYellow=false; t.playerZone=false; t.playerInside=false; t.playerRestart=false; return false end
 t.playerRestart=t.restart and t.cars[i].restart
 local a=frame.cars[i]; local flag=t.neutral or t.red
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
 return t.playerFlag
end
return M
