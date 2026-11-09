-- Panneau de drapeaux du joueur : décisions pures, aucun dessin. Priorité : rouge, noir et pénalités d'AC, tour de
-- relance (lancé ou arrêté), voiture de sécurité, FCY ou VSC (et sa fin), départ arrêté (place, voie des stands, feux,
-- extinction, faux départ), jaune, jaune natif d'AC, reprise jusqu'à la ligne, damier, véhicule lent, place à rendre,
-- avertissement, piste glissante, bleu (de l'app, puis natif), voiture endommagée, tour, DRS, dernier tour, vert,
-- départ, arrêt obligatoire, mise à jour disponible (Beta 1.33, aux stands, une fois par lancement). Textes reconstruits seulement quand le drapeau ou sa
-- valeur arrondie change. Le temps delta lui-même est lu à chaque image par l'interface (module delta).
local U=require('src/util')
local C=require('src/config')
local L=require('src/lang')
local P=require('src/perception')
local Classes=require('src/classes')
local K=C.K
local M={}
function M.new() return {kind='none',key='',title='',detail='',raw='',noPass=false,passed=false,drsBlocked=false,drsUsed=false,short='',passOk='',passBad='',infractions=-1,infractionMax=-1,notice='',noticeUntil=-math.huge,at=-math.huge,
 changedAt=-math.huge,double=false,explain='',finish=false,lapCode='',info=nil,drsText='',drsLaps=-1,drsLapsText='',redPit=false,blueGap=nil,giveBackDue=false,warnPending=false,warnUntil=-math.huge,updateUntil=-math.huge,updateVersion='',rel={index=0,long=0,lat=0,gap=0,sa=0,ttc=math.huge,same=false,alongside=false}} end
-- Drapeau bleu du joueur, en course : une voiture plus rapide qui lui prend au moins un tour arrive derrière. Renvoie
-- son écart en secondes (distance à sa vitesse), sinon nil. rel : table de travail ; held : bleu déjà montré
-- (hystérésis). Partagé avec les panneaux lumineux du circuit (Beta 1.32).
local function blue(rel,frame,p,profile,held)
 if profile~='C' or not p.blueFlagEnabled or frame.player==0 or frame.length<=0 then return nil end
 local a=frame.cars[frame.player]
 if not a.valid or a.pit or not a.splineValid then return nil end
 local best=nil
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=frame.player and b.valid and not b.pit and b.splineValid then
   local r=P.relative(a,b,frame.length,rel)
   -- Hystérésis : un drapeau bleu affiché reste tant que la voiture qui double ne s'éloigne pas, même collée derrière.
   if r.same and r.long<0 and r.gap>=0 and r.gap<=p.blueFlagRange and (r.sa>=K.lapSpeed or held and r.sa>-K.lapSpeed) and Classes.laps(a,b,r,frame.length)>0 then
    local gap=r.gap/math.max(1,b.speed)
    if not best or gap<best then best=gap end
   end
  end
 end
 return best
end
M.blue=blue
-- Drapeaux et pénalités natifs d'AC (Beta 1.11) : repris par le panneau, leur affichage d'origine étant masqué dans
-- CSP. Renvoie le genre et sa valeur (tours ou secondes), ou nil ; le jaune que l'app impose au joueur n'est pas repris.
local function native(panel,frame,now)
 -- Drapeau imposé par l'app (jaune, rouge, bleu, vert... des panneaux lumineux) : aucun drapeau natif lisible ;
 -- seules les pénalités d'AC, propres à la voiture, restent lues.
 local f=frame.flagOwned and K.flagNone or frame.flag
 -- Départ : levé toute la session en hotlap ; repris quelques secondes à son apparition seulement.
 if f~=K.flagStart then panel.startSeen=nil elseif not panel.startSeen then panel.startSeen=now end
 local a=frame.player>0 and frame.cars[frame.player] or nil
 local penalty=a and a.penaltyType or 0; local n=a and a.penaltyParam or 0
 if f==K.flagStop or penalty==K.penaltyBlackFlag then return 'black',0 end
 if penalty==K.penaltyMandatoryPits and n>0 then return 'penaltyDrive',n end
 if penalty==K.penaltyTeleportToPits and n>0 then return 'penaltyTeleport',n end
 if penalty==K.penaltySlowDown and n>0 then return 'penaltySlow',n end
 if penalty>0 or f==K.flagReturnToPits then return 'penalty',0 end
 if f==K.flagFinished then return panel.info and panel.info.finished and 'finish' or 'checkered',0 end
 if f==K.flagCaution then return 'native',0 end
 if f==K.flagFasterCar then return 'nativeBlue',0 end
 if f==K.flagOneLapLeft then return 'white',0 end
 if f==K.flagStart and now-panel.startSeen<K.greenShow then return 'start',0 end
 return nil,0
end
-- Genre affiché (couleur, sigle, titre) de chaque genre décidé.
local shownKinds={scCall='sc',penaltyDrive='penalty',penaltyTeleport='penalty',penaltySlow='penalty',nativeBlue='blue',start='green',finish='checkered',giveBack='warning',
 rollingIn='rolling',rollingGreen='rolling',standingLap='standing',standingPit='standing'}
-- Drapeau retenu : genre affiché, horodatage du changement, textes refaits seulement quand le genre ou la valeur change.
-- profile : essais et qualifications parlent de séance, pas de course (drapeau rouge, reprise).
-- Beta 1.49 : textes de l'arrêt obligatoire en F1 (composés nommés), refaits seulement quand ils changent.
local function joinOr(list,word)
 local n=#list
 if n==0 then return '' elseif n==1 then return list[1] end
 return table.concat(list,', ',1,n-1)..word..list[n]
end
local function pitTexts(panel,t,extra,value)
 local others=t.playerTyreOthers or {}
 local tyre=t.playerTyre or ''
 local sig=extra..'|'..value..'|'..tyre..'|'..#others..'|'..(t.playerPitFrom or '')..'|'..(t.playerPitTo or '')..'|'..(t.playerPlan or '')..'|'..(t.playerPlanned or '')
 if sig==panel.pitSig then return end
 panel.pitSig=sig
 local H=L.pitHint; local short,detail
 local fitted=tyre~='' and tyre or '?'
 local planSame=string.format(H.planSame,fitted)
 local planSameDetail=#others>0 and string.format(H.planSameDetail,fitted,joinOr(others,H.orWord)) or string.format(H.planSameDetailAny,fitted)
 if extra==1 then short=L.flagShort.pitCompound; detail=string.format(L.flagDetails.pitCompound,value)
 elseif extra==2 then
  if t.playerPlan=='same' then short=planSame; detail=planSameDetail
  elseif t.playerPlan=='ok' and (t.playerPlanned or '')~='' then short=string.format(H.planOk,t.playerPlanned); detail=short
  elseif tyre~='' and #others>0 then short=string.format(H.change,tyre,joinOr(others,H.orWord)); detail=short
  else short=H.generic; detail=short end
 elseif extra==3 then short=string.format(H.same,t.playerPitFrom or '?',t.playerPitTo or '?'); detail=string.format(H.sameDetail,t.playerPitFrom or '?',t.playerPitTo or '?')
 elseif extra==4 then short=string.format(H.counted,t.playerPitFrom or '?',t.playerPitTo or '?'); detail=short
 elseif extra==6 then short=string.format(H.planFixed,(t.playerPlanned or '')~='' and t.playerPlanned or '?'); detail=short
 else short=planSame; detail=planSameDetail end
 panel.pitShort=short; panel.pitDetail=detail; panel.pitExplain=extra==4 and '' or L.flagExplain.pitCompound
end
-- Texte d'une annonce de l'arrêt F1 (pont des apps compagnes), celui de la consigne du panneau ; nil pour une autre.
local announceExtra={pitCompound=2,pitPlanSame=5,pitNotCounted=3,pitValidated=4,pitPlanOk=6}
function M.pitAnnounce(t,kind)
 local extra=announceExtra[kind]
 if not extra then return nil end
 local scratch={}
 local saved=t.playerPlan
 if kind=='pitCompound' then t.playerPlan='' end
 pitTexts(scratch,t,extra,t.playerPitDue or 0)
 t.playerPlan=saved
 return scratch.pitDetail or ''
end
local function show(panel,kind,value,double,gap,now,profile,extra)
 extra=extra or 0
 local shown=shownKinds[kind] or kind
 if shown~=panel.kind then panel.changedAt=now end
 panel.decided=kind; panel.kind=shown; panel.double=double; panel.blueGap=gap; panel.redPit=kind=='red' and value==1; panel.finish=kind=='finish'
 -- Feux de départ (Beta 1.34) : nombre de feux allumés.
 panel.lit=kind=='lights' and value or 0
 -- Passage de la ligne et fin de course (Beta 1.25) : textes tenus par les informations de l'overlay.
 local info=panel.info
 if kind=='lap' and info then value=info.lapSerial elseif kind=='finish' and info then value=info.recapSerial end
 local session=profile=='P' or profile=='Q'
 -- Beta 1.39 : drapeau noir de l'app (infractions au-delà du nombre toléré) : nombre d'infractions dans la consigne.
 local ours=kind=='black' and panel.infractionMax>=0 and panel.infractions>panel.infractionMax
 local key=kind..'|'..value..'|'..extra..'|'..(double and 1 or 0)..(session and '|s' or '')..(ours and '|'..panel.infractions or '')
 if kind=='pit' and extra>0 then key=key..'|'..(panel.pitSig or '') end
 if key~=panel.key then
  panel.key=key
  -- Départ arrêté (Beta 1.35) : place et distance lues par la case de l'overlay.
  if kind=='standing' and value>0 then panel.slotText='P'..value; panel.slotDistance=extra else panel.slotText=nil; panel.slotDistance=nil end
  if kind=='lap' and info then
   panel.title=info.lapTitle; panel.raw=info.lapDetail; panel.detail=info.lapDetail; panel.short=info.lapDetail; panel.explain=''; panel.lapCode=info.lapCode; panel.lapRecord=info.lapRecord==true
  elseif kind=='finish' and info then
   panel.title=L.flagTitles.finish; panel.raw=info.recap[1] or ''; panel.detail=panel.raw; panel.short=panel.raw; panel.explain=''
  elseif kind~='none' then
   -- Départ (Beta 1.38) : vert, titre « DÉPART » de la maquette.
   panel.title=kind=='yellow' and double and L.flagTitles.yellow2 or kind=='start' and L.flagTitles.start or L.flagTitles[panel.kind]
   local detail
   if kind=='drs' then detail=L.flagDetails.drs
   elseif kind=='yellow' then detail=string.format(double and L.flagDetails.yellow2 or L.flagDetails.yellow,value)
   elseif kind=='red' then detail=value==1 and (session and L.flagDetails.redSessionPit or L.flagDetails.redPit) or (session and L.flagDetails.redSession or L.flagDetails.red)
   elseif kind=='green' and session then detail=L.flagDetails.greenSession
   else detail=string.format(L.flagDetails[kind],value,extra) end
   panel.raw=detail; panel.detail=U.wrapText(detail,K.panelWrap)
   -- Consigne courte du bandeau (une ligne).
   local short=kind=='red' and (value==1 and (session and 'redSessionPit' or 'redPit') or (session and 'redSession' or 'red'))
    or kind=='green' and session and 'greenSession' or kind=='yellow' and double and 'yellow2'
    -- Beta 1.38 : départ hors course (séance), cinq feux allumés : consignes propres (maquette).
    or kind=='start' and profile~=nil and profile~='C' and 'startSession' or kind=='lights' and value>=K.gridLights and 'lightsAll'
    or kind=='black' and ours and 'blackCount' or kind
   panel.short=string.format(L.flagShort[short],short=='blackCount' and panel.infractions or value,extra)
   -- Explication de ce qui se passe (Beta 1.25), sous la consigne : jaune, double jaune, neutralisations, rouge...
   local explain=kind=='yellow' and double and 'yellow2' or kind=='red' and (session and 'redSession' or 'red') or kind
   panel.explain=L.flagExplain[explain] or ''
   if kind=='pit' and extra>0 and panel.pitShort then panel.raw=panel.pitDetail; panel.detail=U.wrapText(panel.pitDetail,K.panelWrap); panel.short=panel.pitShort; panel.explain=panel.pitExplain end
  else panel.explain='' end
 end
end
-- Panneau réduit aux drapeaux d'AC : onglet Règles ou panneau décoché, app à l'arrêt (aucune commande, session finie,
-- panique, pause, hotlap). Ni dépassement interdit ni règles du DRS ; badge DRS du joueur si sa préférence est cochée.
-- profile (Beta 1.38) : profil en cours (consigne du départ, course ou séance) ; absent : course.
function M.native(panel,frame,now,p,profile)
 if now<panel.at then return end
 panel.at=now+K.panelPeriod
 local kind,value=native(panel,frame,now)
 local a=frame.player>0 and frame.cars[frame.player] or nil
 if a and a.drsActive then panel.drsUsed=true elseif not (a and a.drsAvailable) then panel.drsUsed=false end
 if not kind and panel.info and panel.info.finished then kind='finish' end
 if not kind and panel.info and now<panel.info.lapUntil then kind='lap' end
 if not kind and (not p or p.drsAssist~=false) and a and a.valid and a.drsPresent and a.drsAvailable and not a.drsActive and not panel.drsUsed then kind='drs'; value=1 end
 if not kind and now<panel.updateUntil then kind='update'; value=panel.updateVersion end
 show(panel,kind or 'none',value,false,nil,now,profile)
 panel.noPass=false; panel.drsBlocked=false; panel.warnPending=false
end
-- Informations non urgentes : effacées après la durée réglée (0 : tant qu'elles durent) ; les drapeaux restent.
local infoKinds={green=true,drs=true,white=true,checkered=true,slippery=true,lap=true,update=true}
-- Overlay à afficher : un drapeau ou une information encore dans sa durée d'affichage.
function M.visible(panel,g,now)
 if panel.kind=='none' then return false end
 local hold=g and g.panelInfoTime or 0
 return not (infoKinds[panel.kind] and not panel.finish and hold>0 and now-panel.changedAt>=hold)
end
-- Ligne « Dépassement interdit » avec le compteur d'infractions du joueur (textes refaits seulement s'il change).
function M.infractions(panel,count,max)
 if count==panel.infractions and max==panel.infractionMax then return end
 panel.infractions=count; panel.infractionMax=max
 local suffix=count>0 and string.format(L.infractionCount,count,max) or ''
 panel.passOk=L.noPassing..suffix; panel.passBad=L.passMade..suffix
end
-- Dernière infraction tolérée (la suivante disqualifie, Beta 1.32) : drapeau noir et blanc dès qu'aucun drapeau de
-- régime n'est montré, K.warningShow s.
function M.warn(panel) panel.warnPending=true end
-- Pénalité du joueur : ligne rouge sous la consigne pendant quelques secondes.
function M.notice(panel,reason,seconds,now) panel.notice=string.format(L.penaltyNotice[reason],seconds); panel.noticeUntil=now+K.noticeTime end
-- Nom abrégé (« D. Ferro ») : première lettre (UTF-8 entier) du premier mot et derniers mots.
local function initials(name)
 if type(name)~='string' then return '' end
 local first,rest=name:match('^%s*(%S+)%s+(.-)%s*$')
 if not first or rest=='' then return name end
 return (first:match('^[%z\1-\127\194-\244][\128-\191]*') or '')..'. '..rest
end
M.initials=initials
-- Beta 1.48 : indicateur de reprise après un drapeau rouge (place de l'ordre figé, voiture à suivre) : case « REPRISE »
-- aux stands, consigne de la bande (rester, attendre, sortir), pastille en piste (place tenue ou à reprendre). Textes
-- refaits seulement quand l'état ou le drapeau change ; une consigne remplacée est rendue au drapeau d'abord.
local function restartInfo(panel,t,frame,kind)
 local r=t.restartRank or 0
 local key=r>0 and (t.restartState..'|'..r..'|'..t.restartAhead..'|'..t.restartTarget..'|'..tostring(panel.key)) or ''
 if key==panel.restartKey then return end
 if panel.restartShort then panel.restartShort=false; panel.key=nil; panel.restartKey=nil; return end
 panel.restartKey=key; panel.restartPill=nil; panel.restartRetake=false; panel.restartBox=nil
 if r==0 then return end
 local R=L.restart; local st=t.restartState
 local ahead=t.restartAhead>0 and frame.cars[t.restartAhead] or nil
 local name=ahead and ahead.name or ''
 local first=t.safety>0 and R.behindSc or R.leading
 if st=='pit' and panel.redPit or st=='wait' or st=='go' then panel.restartBox='P'..r end
 local short
 if st=='pit' and kind=='red' and panel.redPit then short=r>1 and string.format(R.pit,r,name) or string.format(R.pitFirst,first)
 elseif st=='wait' then short=ahead and string.format(R.wait,name) or string.format(R.waitFirst,first)
 elseif st=='go' then short=r>1 and string.format(R.go,r,name) or string.format(R.goFirst,first)
 elseif st=='retake' then local b=frame.cars[t.restartTarget]; panel.restartRetake=true; panel.restartPill=string.format(R.retake,r,initials(b and b.name or ''))
 elseif st=='ok' then panel.restartPill=r>1 and string.format(R.pill,r,initials(name)) or string.format(R.pillFirst,first) end
 if short then panel.short=short; panel.restartShort=true end
 if kind=='red' then panel.explain=string.format(t.safety>0 and R.explainSc or R.explain,r); panel.restartShort=true end
end
-- lights : état des panneaux lumineux (véhicule lent devant, dégâts du joueur), facultatif.
function M.update(panel,t,frame,p,profile,now,lights)
 if not p.flagPanel then return M.native(panel,frame,now,p,profile) end
 if now<panel.at then return end
 panel.at=now+K.panelPeriod
 local kind,value,double='none',0,false
 local a=frame.player>0 and frame.cars[frame.player] or nil
 local reason=t.drsReason or ''
 local present=p.drsAssist and a and a.valid and a.drsPresent or false
 -- DRS : badge tant qu'il est disponible et fermé ; effacé dès l'ouverture, jusqu'à la fin de la zone (l'aileron se
 -- referme au freinage alors que la zone est encore active).
 if a and a.drsActive then panel.drsUsed=true elseif not (a and a.drsAvailable) then panel.drsUsed=false end
 local drs=present and reason=='' and a.drsAvailable and not a.drsActive and not panel.drsUsed or false
 local gap=nil
 local nk,nv=native(panel,frame,now)
 local extra=0
 if t.red then kind='red'; value=a and a.pit and 1 or 0
 -- Drapeau noir et pénalités d'AC : propres au joueur, avant toute neutralisation.
 elseif nk=='black' or nk=='penalty' or nk=='penaltyDrive' or nk=='penaltyTeleport' or nk=='penaltySlow' then kind=nk; value=nv
 -- Tour de relance d'un drapeau rouge (Beta 1.34) : départ lancé (RS) ou arrêté (SS) annoncé, voiture de sécurité qui
 -- rentre ce tour, dépassement à la ligne ou dès le vert.
 elseif t.neutral and t.relaunch and profile=='C' then
  if p.redRestart=='standing' and t.gridReady then kind='standingLap'
  else kind=t.safetyPhase~='in' and 'rolling' or p.restartOvertake=='scIn' and 'rollingGreen' or 'rollingIn' end
 elseif t.neutral then
  if t.neutralMode=='sc' then
   local merging=t.safetyPhase=='call' or t.safetyPhase=='exit' or t.safetyPhase=='place' or t.safetyPhase=='out' and t.safety>0 and frame.cars[t.safety].pit
   kind=t.safetyPhase=='in' and 'scIn' or merging and 'scCall' or 'sc'
  elseif t.neutralMode=='vsc' then kind=t.ending and 'vscEnd' or 'vsc'; value=p.vscDeltaPct
  else kind='fcy'; value=p.fcyDeltaPct end
 -- Départ arrêté (Beta 1.34) : place et distance du joueur, feux, extinction, faux départ.
 elseif t.standing=='grid' then
  if t.gridPit then kind='standingPit' else kind='standing'; value=t.gridSlot or 0; extra=t.gridGap or 0 end
 elseif t.standing=='lights' then kind='lights'; value=t.gridLit or 0
 elseif t.standing=='go' then kind='go'
 elseif now<(t.jumpUntil or -math.huge) then kind='jump'
 elseif t.playerZone then
  -- Double jaune : incident en piste (delta de zone) ; simple jaune : incident hors piste.
  double=t.playerZoneDouble==true
  if t.playerInside then kind=double and 'zone' or 'zone1' else kind='yellow'; value=math.floor((t.playerToZone or 0)/10+0.5)*10 end
 -- Drapeau jaune natif d'AC (voiture lente ou arrêtée qu'il signale sans incident de l'app) : affiché aussi, jamais
 -- le drapeau que l'app impose elle-même au joueur.
 elseif nk=='native' then kind='native'
 -- Reprise derrière la voiture de sécurité : vert, dépassement interdit jusqu'à la ligne.
 elseif t.playerRestart then kind='restart'
 -- Course terminée (Beta 1.25) : damier et récapitulatif du joueur, jusqu'à la fin de la session.
 elseif panel.info and panel.info.finished and profile=='C' then kind='finish'
 elseif nk=='checkered' or nk=='finish' then kind='checkered'
 -- Beta 1.32 : véhicule lent devant (drapeau blanc, distance arrondie à 10 m), dépassement permis.
 elseif lights and lights.slowSlot>0 then kind='slow'; value=math.floor(lights.slowGap/10+0.5)*10
 -- Avertissement (drapeau noir et blanc) : place à rendre après un dépassement sous drapeau, une fois le drapeau levé ;
 -- dernière infraction tolérée avant la disqualification.
 elseif panel.giveBackDue then kind='giveBack'
 elseif panel.warnPending or now<panel.warnUntil then
  kind='warning'; if panel.warnPending then panel.warnPending=false; panel.warnUntil=now+K.warningShow end
 elseif now<(t.slipperyUntil or -math.huge) then kind='slippery'
 else
  gap=blue(panel.rel,frame,p,profile,panel.kind=='blue')
  if gap then kind='blue'
  elseif nk=='nativeBlue' then kind='nativeBlue'
  -- Voiture endommagée (drapeau noir à disque orange) : à l'apparition du dégât, quelques secondes.
  elseif lights and now<lights.meatballUntil then kind='meatball'
  -- Passage de la ligne (Beta 1.25) : tour suivant et temps, quelques secondes.
  elseif panel.info and now<panel.info.lapUntil then kind='lap'
  elseif drs then kind='drs'; value=1
  elseif nk=='white' then kind='white'
  elseif now<t.greenUntil then kind='green'
  elseif nk=='start' then kind='start'
  -- Rappel d'arrêt obligatoire : jamais à la place d'un drapeau, du bleu ou du DRS.
  -- Beta 1.49 : avis après l'arrêt (validé, ou même composé), stratégie des stands au même composé, rappel avant
  -- l'entrée des stands, dans la voie et à l'emplacement (F1) ; consigne « changez de composé » du rappel en F1.
  elseif t.playerPitNotice~=nil and t.playerPitNotice~='' then kind='pit'; value=t.playerPitDue or 0; extra=t.playerPitNotice=='same' and 3 or 4
  elseif t.playerPlanNotice then kind='pit'; value=t.playerPitDue or 0; extra=5
  elseif t.playerPitHint then kind='pit'; value=t.playerPitDue or 0; extra=2
  elseif t.playerPitRemind then kind='pit'; value=t.playerPitDue or 0; extra=t.playerPitCompound and 1 or 0
  -- Mise à jour disponible (Beta 1.33) : la plus basse des informations, aux stands seulement.
  elseif now<panel.updateUntil then kind='update'; value=panel.updateVersion end
 end
 if kind=='pit' and extra>0 then pitTexts(panel,t,extra,value) end
 show(panel,kind,value,double,gap,now,profile,extra)
 restartInfo(panel,t,frame,kind)
 -- Départ arrêté (Beta 1.35) : joueur à sa place (à l'arrêt) ou au-delà, lus par la case de l'overlay.
 panel.slotPlaced=kind=='standing' and t.gridPlaced==true; panel.slotPassed=kind=='standing' and t.gridPassed==true
 -- Drapeau et zone DRS en même temps : le drapeau reste affiché, avec une ligne « DRS interdit sous drapeau ».
 local calm=kind=='none' or kind=='green' or kind=='blue' or kind=='pit' or kind=='slippery' or kind=='nativeBlue' or kind=='white' or kind=='start' or kind=='checkered' or kind=='finish' or kind=='lap'
  or kind=='slow' or kind=='giveBack' or kind=='warning' or kind=='meatball' or kind=='update' or kind=='go'
 -- Règles de course : pluie et premiers tours affichés avec tout drapeau ; sinon « DRS interdit sous drapeau ».
 panel.drsBlocked=kind~='none' and kind~='drs' and (reason~='' and present and (reason~='flag' or not calm) or reason=='' and drs and not calm)
 if reason=='wet' then panel.drsText=L.drsWet
 elseif reason=='laps' then
  if t.drsLapsLeft~=panel.drsLaps then panel.drsLaps=t.drsLapsLeft; panel.drsLapsText=string.format(L.drsLapsLeft,t.drsLapsLeft) end
  panel.drsText=panel.drsLapsText
 else panel.drsText=L.drsBlocked end
 -- Régimes où doubler est interdit : ligne dédiée, verte, rouge si le joueur a doublé.
 -- Drapeaux d'AC propres au joueur (noir, pénalité) : pas de ligne de dépassement de l'app.
 panel.noPass=not calm and kind~='drs' and kind~='native' and panel.kind~='black' and panel.kind~='penalty' and (kind~='yellow' or t.playerNoPass==true)
end
return M
