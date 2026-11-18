-- Beta 1.61 (tranche D, réglage startRealism : section Départ, course seulement, coupé par défaut). Départs plus vrais,
-- sans aucune écriture nouvelle : plafonds d'accélérateur (cmd.throttleLimit, par minimum), décalage latéral du tour de
-- formation (s.formOffset, lu par src/director.lua ; champ absent : neutre), tirages reproductibles (graine, numéro du
-- départ). Appelé par src/engine.lua :
--  - M.draw, avant le pilotage : repère chaque départ (feu vert d'AC, extinction des feux de la grille de l'app, drapeau
--    vert d'un départ lancé, relance derrière la voiture de sécurité) et tire, une fois par départ, le temps de
--    réaction de chaque IA, les quelques envols manqués (K.anticPoorMax au plus, jamais deux dans la même colonne sur
--    deux rangées qui se suivent) et, à l'allumage des feux de la grille de l'app, l'IA qui volera le départ (une au
--    plus, seulement avec la sanction du faux départ : sanJumpStart) ;
--  - M.weave, avant le pilotage : zigzag de chauffe des pneus pendant le tour de formation et derrière la voiture de
--    sécurité (ligne droite, personne à moins de K.weaveClear m, hors zone sans manœuvre, loin de la ligne), puis deux
--    files à l'appel du départ lancé. Le joueur n'est jamais déplacé (IA pilotées seulement) ;
--  - M.launch, après le pilotage : plafonds d'accélérateur du départ. Jamais de voiture tenue à l'arrêt : le plafond le
--    plus bas est K.throttleMin, et un envol manqué est relevé à K.anticBogFloor avec une voiture collée derrière.
-- M.grade, M.lower : grades d'un faux départ sur la grille de l'app (src/grid.lua, moteur, sanctions).
local U=require('src/util')
local C=require('src/config')
local Snapshot=require('src/snapshot') -- Beta 2.0.4 : courbure de la piste et écart latéral réel (zigzag, deux files)
local K=C.K
local min,max,abs,sin,floor=math.min,math.max,math.abs,math.sin,math.floor
local M={}
-- Affinage 1.63 (demande du pilote, 13 novembre : « je ne les vois pas zigzaguer ; ils doivent laisser de l'espace avec
-- celui de devant pour des accélérations franches, des freinages francs, des zigzags ») : pendant le tour de formation,
-- chaque IA (sauf la tête de file) se laisse décrocher de temps en temps (toutes les cycleMin à cycleMax s, graine) :
-- levée de pied progressive (dropRate km/h par seconde, au plus dropKmh sous la voiture de devant, jamais sous
-- K.formBrakeFloor) jusqu'à un écart de gapMin à gapMax m (3 à 6 longueurs), dropMax s au plus, interrompue si une voiture
-- arrive à moins de dropBehind m derrière ; l'écart sert ensuite à l'accélération franche (rattrapage de la file), au
-- freinage de chauffe et au zigzag. Garde du zigzag du tour de formation : weaveAhead m devant, weaveBehind m derrière,
-- personne à moins de alongside m (à côté) ; freinage de chauffe : brakeAhead m devant, brakeBehind m derrière.
local AK={cycleMin=10,cycleMax=18,dropKmh=22,dropRate=6,gapMin=14,gapMax=28,dropMax=9,dropBehind=6,
 weaveAhead=9,weaveBehind=6,alongside=6.5,brakeAhead=16,brakeBehind=10,playerClear=60,dropStopBefore=1700,salt=731,
 -- Affinage 1.63 (pilote, 13 novembre : « zigzags beaucoup trop petits, quasiment 80 % de la largeur » ; « les freins,
 -- c'est des attitudes de tour de chauffe ») : zigzag du tour de formation plus lent et plus ample (période weavePeriodMin
 -- à weavePeriodMax s, rampe weaveRate) : pleine amplitude (K.formWeaveAmp de la place permise, environ 80 % de la
 -- largeur) jusqu'à weaveFullKmh, K.formWeaveFastShare à weaveFastKmh ; freinage de chauffe franc (brakeTime s,
 -- brakeDrop km/h sous la vitesse du moment).
 weavePeriodMin=2.6,weavePeriodMax=3.4,weaveRate=4,weaveFullKmh=130,weaveFastKmh=200,brakeTime=0.9,brakeDrop=45,
 -- Zigzag interdit (voiture devant trop près, à côté, virage) : retour vers la file returnMult fois plus vite.
 returnMult=3,
 -- Beta 2.0.4 (pilote, 17 novembre : « les zigzags sont trop minuscules », 90 % de la largeur) : gardes devant et derrière
 -- réduites (weaveAhead, weaveBehind : la file roule à 16-28 m), période plus longue (l'IA suit mieux le décalage), part de
 -- l'amplitude gardée à weaveFastKmh : fastShare.
 fastShare=0.6,weaveSettle=0.4,returnRate=3,closingWatch=30,closingSa=8,
 -- 2.0.4 : jamais de mouvement latéral du zigzag avec une voiture à sa hauteur (sideClear m de marge, sideRange m).
 sideClear=3,sideRange=25}
-- Le joueur juste derrière (à moins de playerClear m) : jamais de décrochage, et le freinage de chauffe garde l'ancienne
-- distance (K.formBrakeClear) : on ne surprend jamais le joueur.
M.AK=AK
function M.new()
 local t={session=-1,serial=0,kind='',at=-math.huge,window=0,react={},bog={},poor={},rowDelay={},list={},names={},
  form={},period={},weaving=false,synced=false,launchSeen=nil,restartSeen=0,standingSeen='none',jumper=0,poorCount=0,active=false,
  brakeAt={},brakeUntil={},dropAt={},drop={},dropCap={},dropGap={},dropLogged={},dropCount=0,
  -- Beta 2.0.4 : courbure de la piste vue par chaque IA (ici et devant), écart latéral réel mesuré (m) et mesure du zigzag.
  bend={},sampleAt={},lat={},latOk={},wMin={},wMax={},wWidth={},wOn={},wAll={},okSince={},measured=false}
 for i=1,K.maxCars do t.bend[i]=-1; t.sampleAt[i]=-math.huge; t.lat[i]=0; t.latOk[i]=false; t.wMin[i]=math.huge; t.wMax[i]=-math.huge; t.wWidth[i]=0; t.wOn[i]=0; t.wAll[i]=0 end
 for i=1,K.maxCars do t.react[i]=0; t.bog[i]=0; t.poor[i]=false; t.rowDelay[i]=0; t.form[i]=0; t.period[i]=0; t.brakeAt[i]=0; t.brakeUntil[i]=-math.huge; t.dropAt[i]=0; t.drop[i]=0; t.dropCap[i]=0; t.dropGap[i]=0; t.dropLogged[i]=false end
 return t
end
local function clearStart(t)
 t.kind=''; t.at=-math.huge; t.window=0; t.poorCount=0
 for i=1,K.maxCars do t.react[i]=0; t.bog[i]=0; t.poor[i]=false; t.rowDelay[i]=0 end
end
function M.reset(t)
 t.session=-1; t.serial=0; clearStart(t); t.synced=false; t.launchSeen=nil; t.restartSeen=0; t.standingSeen='none'; t.jumper=0
 t.weaving=false; t.active=false
 for i=1,K.maxCars do t.form[i]=0; t.period[i]=0; t.brakeAt[i]=0; t.brakeUntil[i]=-math.huge; t.dropAt[i]=0; t.drop[i]=0; t.dropLogged[i]=false end
end
function M.rebase(t,amount)
 if U.finite(t.at) then t.at=t.at-amount end
 if t.launchSeen then t.launchSeen=t.launchSeen-amount end
 for i=1,K.maxCars do t.brakeAt[i]=t.brakeAt[i]-amount; if U.finite(t.brakeUntil[i]) then t.brakeUntil[i]=t.brakeUntil[i]-amount end; t.dropAt[i]=t.dropAt[i]-amount; if t.drop[i]>0 then t.drop[i]=t.drop[i]-amount end end
end
-- Grade d'un faux départ sur la grille de l'app. moved : avance depuis l'arrêt (m) ; kmh : vitesse la plus haute avant
-- l'extinction ; lead : avance du départ sur l'extinction (s, 0 sans départ franc) ; still : à l'arrêt à l'extinction ;
-- jumped : le critère d'avant la 1.61 (K.jumpDistance, K.jumpSpeed) a été franchi.
function M.grade(moved,kmh,lead,still,jumped)
 if jumped then
  if moved>=K.jumpFlagrantMeters or lead>K.jumpFlagrantLead then return 'flagrant' end
  return 'jump'
 end
 if moved>=K.jumpCreepMin and moved<=K.jumpCreepMeters and kmh<K.jumpCreepKmh and still then return 'creep' end
 return 'none'
end
-- Un cran plus bas (avantage rendu) : flagrant → jump → creep → none.
function M.lower(grade) return grade=='flagrant' and 'jump' or grade=='jump' and 'creep' or 'none' end
local function eligible(a) return a.valid and a.control and not a.player and not a.pit and not a.finished and not a.safetyCar end
-- Place de départ : classement de l'image, sinon l'indice (ordre stable).
local function place(a,i) local p=a.position or 0; return p>=1 and p or i end
-- Tirage d'un départ (kind : 'ac', 'grid' : départs arrêtés ; 'roll', 'restart' : départs lancés, simple accordéon à
-- partir de la troisième rangée ; 'form' : envol du tour de formation, rangée par rangée).
function M.start(t,e,frame,now,kind,seed)
 clearStart(t)
 t.serial=t.serial+1; t.kind=kind; t.at=now
 local p=e.run; local wet=U.clamp(frame.wet or 0,0,1); local base=t.serial*K.maxCars
 local lo,hi=math.huge,0; local n=0; local list=t.list
 for i=1,frame.count do
  local a=frame.cars[i]
  if eligible(a) then
   local row=floor((place(a,i)+1)/2)
   if kind=='form' then t.rowDelay[i]=(row-1)*K.formLaunchGap; t.window=max(t.window,t.rowDelay[i]); t.dropLogged[i]=false
   elseif kind=='ac' or kind=='grid' or row>=K.anticAccordionRow then
    local r=U.lerp(K.anticReactMin,K.anticReactMax,U.unit(seed,base+i,K.anticSalt))
    t.react[i]=r; lo=min(lo,r); hi=max(hi,r); n=n+1; list[n]=i
   end
  end
 end
 for k=#list,n+1,-1 do list[k]=nil end
 local poorCount=0
 if kind=='ac' or kind=='grid' then
  -- Envols manqués : part du plateau (plus sous la pluie, plus pour un pilote sous pression : humeur de la 1.60),
  -- dans l'ordre des tirages les plus bas ; jamais deux dans la même colonne sur deux rangées qui se suivent.
  local share=K.anticPoorShare*(1+K.anticWetGain*wet)
  local mood=p.dynamicPersona and e.mood and e.mood.cars or nil
  for _=1,K.anticPoorMax do
   local best,bestU=0,math.huge
   for k=1,n do
    local i=list[k]
    if not t.poor[i] then
     local u=U.unit(seed,base+i,K.anticSalt+1)
     local stress=mood and mood[i] and U.clamp(mood[i].stress or 0,0,1) or 0
     local chance=share*(1+stress)
     if u<chance and u<bestU then
      local pi=place(frame.cars[i],i); local stacked=false
      for kk=1,n do local j=list[kk]; if t.poor[j] and abs(place(frame.cars[j],j)-pi)==2 then stacked=true; break end end
      if not stacked then best=i; bestU=u end
     end
    end
   end
   if best==0 then break end
   t.poor[best]=true; poorCount=poorCount+1
   t.bog[best]=U.lerp(K.anticBogTimeMin,K.anticBogTimeMax,U.unit(seed,base+best,K.anticSalt+2))
   t.window=max(t.window,t.react[best]+t.bog[best])
  end
 end
 t.poorCount=poorCount
 if n>0 then t.window=max(t.window,hi) end
 if kind~='form' and n>0 then
  local names=t.names; local m=0
  for i=1,frame.count do if t.poor[i] then m=m+1; names[m]=frame.cars[i].name end end
  for k=#names,m+1,-1 do names[k]=nil end
  U.log(e.log,now,'INFO',string.format('depart: reactions %.2f a %.2f s, %d depart(s) manque(s) (%s)',lo,hi,poorCount,m>0 and table.concat(names,', ') or 'aucun'),-1)
 end
end
-- IA qui vole le départ de la grille de l'app : une au plus par départ, seulement avec la sanction du faux départ ; le
-- pilote le plus sous pression d'abord (humeur de la 1.60), sinon tiré de la graine. Sa retenue est levée
-- K.anticJumpLeadMin à K.anticJumpLeadMax s avant l'extinction (src/grid.lua : g.aiRelease).
function M.jumper(t,e,frame,seed)
 local g=e.grid; local p=e.run
 for i=1,K.maxCars do g.aiRelease[i]=nil end
 t.jumper=0
 if not p.sanJumpStart then return 0 end
 local serial=t.serial+1
 if U.unit(seed,serial,K.anticSalt+3)>=K.anticJumpChance then return 0 end
 local mood=p.dynamicPersona and e.mood and e.mood.cars or nil
 local best,bestV=0,-1
 for i=1,frame.count do
  local a=frame.cars[i]
  if eligible(a) and g.slotOf[i]>0 and g.held[i] then
   local v=mood and mood[i] and (mood[i].stress or 0)>0 and 1+mood[i].stress or U.unit(seed,serial*K.maxCars+i,K.anticSalt+4)
   if v>bestV then best=i; bestV=v end
  end
 end
 if best>0 then
  g.aiRelease[best]=U.lerp(K.anticJumpLeadMin,K.anticJumpLeadMax,U.unit(seed,serial,K.anticSalt+5)); t.jumper=best
 end
 return best
end
local function off(t,e)
 if not t.active then return end
 t.active=false; clearStart(t); t.weaving=false
 for i=1,K.maxCars do t.form[i]=0; e.states[i].formOffset=nil; e.states[i].formWeave=nil; e.states[i].formFiles=nil; e.states[i].formLat=nil; e.grid.aiRelease[i]=nil; t.brakeAt[i]=0; t.brakeUntil[i]=-math.huge; t.dropAt[i]=0; t.drop[i]=0 end
 e.grid.realism=false
end
-- Avant le pilotage : départs repérés, tirages.
function M.draw(t,e,frame,now)
 local p=e.run; local inc=e.incidents
 if not p.startRealism or e.profile~='C' or frame.online or frame.replay then
  off(t,e); t.synced=false
  return
 end
 -- Première image (nouvelle session, app rechargée en pleine course, réglage tout juste coché) : l'état du départ est
 -- seulement relevé, rien n'est tiré (jamais de plafond de départ en pleine course) ; le feu vert d'AC de cette image
 -- compte (front noté par le moteur : e.startedAt).
 if not t.synced then t.synced=true; t.launchSeen=e.launchAt; t.restartSeen=inc.restartSerial or 0; t.standingSeen=inc.standing end
 t.active=true; e.grid.realism=true
 local seed=e.runtimeG.seed or 0
 -- Course relancée par AC : plus rien du départ précédent.
 if not frame.started then if t.kind~='' then clearStart(t) end; t.launchSeen=e.launchAt end
 -- Feu vert d'AC : départ arrêté d'AC, ou envol du tour de formation (réglage raceStart de la 1.60).
 if frame.started and e.startedAt==now then M.start(t,e,frame,now,inc.formation and 'form' or 'ac',seed) end
 -- Allumage des feux de la grille de l'app : l'IA qui volera le départ.
 if inc.standing=='lights' and t.standingSeen~='lights' then M.jumper(t,e,frame,seed) end
 t.standingSeen=inc.standing
 -- Extinction des feux de la grille de l'app, drapeau vert d'un départ lancé (e.launchAt, posé par le moteur).
 if e.launchAt and e.launchAt~=t.launchSeen then M.start(t,e,frame,now,e.grid.phase=='go' and 'grid' or 'roll',seed) end
 t.launchSeen=e.launchAt
 -- Relance derrière la voiture de sécurité ou après le tour de relance : accordéon à partir de la troisième rangée.
 local serial=inc.restartSerial or 0
 if serial~=t.restartSeen then t.restartSeen=serial; if frame.started and t.kind=='' then M.start(t,e,frame,now,'restart',seed) end end
 if t.kind~='' and now-t.at>t.window+K.anticTail then clearStart(t) end
end
-- Affinage 1.63 : le joueur juste derrière (voisin de derrière, à moins de clear m).
-- Affinage 2.0.4 (banc du tour de formation : le joueur heurtait une IA qui zigzaguait et décrochait ; à l'écart de sa
-- file, le joueur n'était plus son « voisin de derrière ») : aussi le joueur derrière sur la piste, quel que soit l'écart
-- latéral (i donné).
local function playerBehind(frame,back,clear,i)
 if back~=nil and back.index==frame.player and back.gap<clear then return true end
 local pl=frame.player or 0
 if not i or pl<=0 or pl==i or (frame.length or 0)<=0 then return false end
 local a,b=frame.cars[i],frame.cars[pl]
 if not (a and b and a.splineValid and b.splineValid and b.valid and not b.pit) then return false end
 local gap=U.spline(a.spline-b.spline)*frame.length
 return gap>0 and gap<clear+(a.length or K.length)
end
-- Correctif 1.61 (demande du pilote, 11 novembre) : freinages appuyés de chauffe pendant le tour de formation (IA
-- seulement) : brefs (K.formBrakeTime s), en ligne droite là où le zigzag est permis, jamais avec une voiture à moins de
-- K.formBrakeClear m derrière (ni ailleurs dans le voisinage : K.weaveClear), un toutes les K.formBrakeEveryMin à
-- K.formBrakeEveryMax s (graine). Une baisse de la limite d'allure de K.formBrakeDrop km/h, jamais sous K.formBrakeFloor.
local function warm(t,e,frame,now)
 local inc=e.incidents
 if not (t.active and inc.formation==true and not inc.rollCall) then return end
 local seed=e.runtimeG.seed or 0
 for i=1,frame.count do
  local a=frame.cars[i]
  if eligible(a) then
   if t.brakeAt[i]<=0 then t.brakeAt[i]=now+U.lerp(K.formBrakeEveryMin,K.formBrakeEveryMax,U.unit(seed,i,K.anticSalt+7)) end
   -- Relecture 2.0.4 : jamais un freinage de chauffe dans la zone des burnouts (src/antics.lua, burn) : un seul à la fois.
   local d=a.splineValid and (frame.length or 0)>0 and ((-a.spline)%1)*frame.length or 0
   if inc.formationKind=='formation' and d<=K.burnFrom and d>=K.burnTo then t.brakeAt[i]=math.max(t.brakeAt[i],now+1); t.brakeUntil[i]=math.min(t.brakeUntil[i],now) end
   if now<t.brakeUntil[i] then
    local cmd=e.commands[i]; cmd.speedLimit=min(cmd.speedLimit or K.unlimitedSpeed,max(K.formBrakeFloor,a.kmh-AK.brakeDrop))
   elseif now>=t.brakeAt[i] then
    local row=e.perception and e.perception.rows[i]
    local back=row and row.back>0 and row.neighbors[row.back] or nil
    -- Correctif 1.63 (Montréal, 12 novembre : accrochages en file pendant le tour de formation) : jamais avec une voiture
    -- à moins de K.formBrakeClear m devant non plus (file en accordéon).
    local front=row and row.front>0 and row.neighbors[row.front] or nil
    -- Affinage 1.63 : gardes du tour de formation (AK.brakeAhead, AK.brakeBehind) ; l'écart ouvert par le décrochage
    -- (plus bas) les rend atteignables dans une file.
    if M.mayWeave(e,frame,i,true) and not (back and back.gap<AK.brakeBehind) and not playerBehind(frame,back,K.formBrakeClear,i) and not (front and front.gap<AK.brakeAhead) and a.kmh>K.formBrakeFloor+K.formBrakeDrop then
     t.brakeUntil[i]=now+AK.brakeTime
    end
    t.brakeAt[i]=now+U.lerp(K.formBrakeEveryMin,K.formBrakeEveryMax,U.unit(seed,i*31+floor(now),K.anticSalt+8))
   end
  end
 end
end
-- Affinage 1.63 : décrochage de chauffe (AK) ; une ligne au journal par voiture et par tour de formation.
local function dropBack(t,e,frame,now,dt)
 local inc=e.incidents
 if not (t.active and inc.formation==true and not inc.rollCall) then
  for i=1,K.maxCars do t.drop[i]=0 end
  return
 end
 local seed=e.runtimeG.seed or 0
 for i=1,frame.count do
  local a=frame.cars[i]
  if eligible(a) then
   local row=e.perception and e.perception.rows[i]
   local front=row and row.front>0 and row.neighbors[row.front] or nil
   local back=row and row.back>0 and row.neighbors[row.back] or nil
   -- Plus de décrochage sur la fin du tour (regroupement serré avant la grille : src/formation.lua, FK.compactFrom).
   local near=((-a.spline)%1)*frame.length<=AK.dropStopBefore
   if t.dropAt[i]<=0 then t.dropAt[i]=now+U.lerp(AK.cycleMin,AK.cycleMax,U.unit(seed,i,AK.salt)) end
   if t.drop[i]>0 then
    -- En cours : levée progressive vers dropKmh sous la voiture de devant ; fin à l'écart voulu, au délai, près de la
    -- grille, sans voiture devant, ou avec une voiture trop près derrière.
    local b=front and frame.cars[front.index]
    if not front or not b or near or now>=t.drop[i] or front.gap>=t.dropGap[i] or (back and back.gap<AK.dropBehind) or playerBehind(frame,back,AK.playerClear,i) then
     t.drop[i]=0; t.dropAt[i]=now+U.lerp(AK.cycleMin,AK.cycleMax,U.unit(seed,i*17+floor(now),AK.salt+1))
    else
     local want=max(K.formBrakeFloor,b.kmh-AK.dropKmh)
     t.dropCap[i]=max(want,t.dropCap[i]-AK.dropRate*(dt or 0))
     local cmd=e.commands[i]; cmd.speedLimit=min(cmd.speedLimit or K.unlimitedSpeed,t.dropCap[i])
    end
   elseif now>=t.dropAt[i] then
    -- Départ d'un décrochage : une voiture devant, pas de tête de file, loin de la grille, rien de collé derrière.
    if front and front.gap<AK.gapMin and not near and not (back and back.gap<AK.dropBehind) and not playerBehind(frame,back,AK.playerClear,i) and a.kmh>K.formBrakeFloor then
     t.drop[i]=now+AK.dropMax; t.dropCap[i]=a.kmh; t.dropGap[i]=U.lerp(AK.gapMin,AK.gapMax,U.unit(seed,i*29+floor(now),AK.salt+2))
     t.dropCount=t.dropCount+1; e.stats.formationDrop=(e.stats.formationDrop or 0)+1
     if not t.dropLogged[i] then t.dropLogged[i]=true; U.log(e.log,now,'INFO',string.format('tour de formation: %s laisse un ecart pour chauffer (%.0f m)',a.name,t.dropGap[i]),i) end
    end
    t.dropAt[i]=now+U.lerp(AK.cycleMin,AK.cycleMax,U.unit(seed,i*13+floor(now),AK.salt+3))
   end
  end
 end
end
M.dropBack=dropBack
-- Affinage 2.0.4 (décision du pilote, 17 novembre : « avant de se positionner en grille, toutes les IA ralentissent pour
-- faire un, deux ou trois burnouts et de gros freinages, comme dans la réalité ») : tour de formation d'un départ arrêté,
-- de K.burnFrom à K.burnTo m de la ligne (tête du tour au-delà de la moitié du tour, jamais à l'entrée des stands), chaque
-- IA sauf la tête fait 1 à 3 cycles (graine) : ralentit (K.burnSlowKmh km/h) jusqu'à K.burnGap m d'écart (K.burnSlowMax s
-- au plus), repart à fond (K.burnGoMax s au plus, ou K.burnGoGap m de la voiture de devant), puis gros freinage
-- (K.burnBrake pendant K.burnBrakeTime s, jamais avec une voiture à moins de AK.brakeBehind m derrière). Jamais avec le
-- joueur juste derrière (AK.playerClear m). Une ligne au journal par voiture.
-- Relecture 2.0.4 : place libre derrière pour ralentir ou freiner fort : rien à moins de K.burnClearBehind m, ni une voiture
-- qui arrive à moins de K.burnClearTime s.
local function clearBehind(back)
 if not back then return true end
 if back.gap<K.burnClearBehind then return false end
 local closing=(back.sa or 0)/3.6
 return not (closing>0 and back.gap/closing<K.burnClearTime)
end
local function burn(t,e,frame,now)
 local inc=e.incidents
 local on=t.active and inc.formation==true and inc.formationKind=='formation' and not inc.rollCall and (inc.relaunchTravel or 0)>=K.relaunchTravel
 t.burnPhase=t.burnPhase or {}; t.burnUntil=t.burnUntil or {}; t.burnLeft=t.burnLeft or {}; t.burnLogged=t.burnLogged or {}
 if not on then
  if t.burnOn then t.burnOn=false; for i=1,K.maxCars do t.burnPhase[i]=nil; t.burnLeft[i]=nil; t.burnLogged[i]=nil end end
  return
 end
 t.burnOn=true
 local seed=e.runtimeG.seed or 0
 for i=1,frame.count do
  local a=frame.cars[i]
  local d=a.splineValid and frame.length>0 and ((-a.spline)%1)*frame.length or 0
  local zone=eligible(a) and d<=K.burnFrom and d>=K.burnTo and i~=(inc.relaunchLeader or 0) and not M.nearPitEntry(e,frame,a)
  if t.burnLeft[i]==nil then t.burnLeft[i]=1+floor(U.unit(seed,i,K.anticSalt+11)*3) end
  local row=e.perception and e.perception.rows[i]
  local front=row and row.front>0 and row.neighbors[row.front] or nil
  local back=row and row.back>0 and row.neighbors[row.back] or nil
  local cmd=e.commands[i]; local phase=t.burnPhase[i]
  -- Affinage 2.0.4 : burnout en cours, jamais pris pour un arrêt (src/incidents.lua, c.burnUntil).
  local ic=inc.cars and inc.cars[i]; if ic and phase and phase~='rest' then ic.burnUntil=now+K.burnIncidentGrace end
  if not zone then t.burnPhase[i]=nil
  elseif phase=='slow' then
   cmd.speedLimit=min(cmd.speedLimit or K.unlimitedSpeed,K.burnSlowKmh)
   if not front or front.gap>=K.burnGap or now>=t.burnUntil[i] then t.burnPhase[i]='go'; t.burnUntil[i]=now+K.burnGoMax end
  elseif phase=='go' then
   if now>=t.burnUntil[i] or front and front.gap<K.burnGoGap then
    -- Relecture 2.0.4 : gros freinage seulement avec K.burnClearBehind m libres derrière (ou K.burnClearTime s à l'écart
    -- de vitesse), arrêté dès K.burnBrakeDrop km/h perdus (jamais une F1 presque arrêtée sur un délai fixe).
    if clearBehind(back) and not playerBehind(frame,back,AK.playerClear,i) then t.burnPhase[i]='brake'; t.burnUntil[i]=now+K.burnBrakeTime; t.burnFrom=t.burnFrom or {}; t.burnFrom[i]=a.kmh
    else t.burnPhase[i]='rest'; t.burnUntil[i]=now+K.burnRest end
   end
  elseif phase=='brake' then
   cmd.brake=max(cmd.brake or 0,K.burnBrake)
   if now>=t.burnUntil[i] or a.kmh<=(t.burnFrom and t.burnFrom[i] or a.kmh)-K.burnBrakeDrop or a.kmh<=K.burnSlowKmh+10 or not clearBehind(back) then t.burnPhase[i]='rest'; t.burnUntil[i]=now+K.burnRest end
  elseif phase=='rest' then
   if now>=t.burnUntil[i] then t.burnPhase[i]=nil end
  elseif t.burnLeft[i]>0 and clearBehind(back) and not playerBehind(frame,back,AK.playerClear,i) then
   t.burnLeft[i]=t.burnLeft[i]-1; t.burnPhase[i]='slow'; t.burnUntil[i]=now+K.burnSlowMax
   cmd.speedLimit=min(cmd.speedLimit or K.unlimitedSpeed,K.burnSlowKmh)
   e.stats.formationBurn=(e.stats.formationBurn or 0)+1
   if not t.burnLogged[i] then t.burnLogged[i]=true; U.log(e.log,now,'INFO',string.format('tour de formation: %s burnout et gros freinage avant la grille',a.name),i) end
  end
 end
end
M.burn=burn
-- Après le pilotage : plafonds d'accélérateur du départ en cours.
function M.launch(t,e,frame,now,dt)
 dropBack(t,e,frame,now,dt)
 warm(t,e,frame,now)
 burn(t,e,frame,now)
 if t.kind=='' then return end
 local since=now-t.at
 if since<0 then return end
 for i=1,frame.count do
  local a=frame.cars[i]
  if eligible(a) then
   local ceiling=1
   if t.kind=='form' then
    if since<t.rowDelay[i] then ceiling=K.throttleMin end
   else
    local r=t.react[i]
    if r>0 and since<r then
     -- Départ lancé : simple rampe (l'accordéon), jamais un plancher de gaz en pleine vitesse.
     ceiling=(t.kind=='roll' or t.kind=='restart') and U.lerp(K.anticRollThrottle,1,since/r) or K.throttleMin
    elseif t.poor[i] and since<r+t.bog[i] then
     ceiling=U.lerp(K.anticBogThrottle,1,(since-r)/t.bog[i])
     -- Voiture collée derrière (toujours vrai sur une grille) : plancher, comme le régulateur de la 1.60.
     if e.states[i].rearClose then ceiling=max(ceiling,K.anticBogFloor) end
    end
   end
   if ceiling<1 then local cmd=e.commands[i]; cmd.throttleLimit=min(cmd.throttleLimit or 1,ceiling) end
  end
 end
end
-- Zigzag permis pour l'IA i : ligne droite, personne à moins de K.weaveClear m (devant, derrière ou à côté, joueur
-- compris), hors zone sans manœuvre, à plus de K.weaveStopBefore m de la ligne (la grille est juste avant elle).
-- Correctif 1.61 (tour de formation, lap vrai) : plus de zigzag dans les K.formWeaveStopBefore derniers mètres (approche
-- de la grille), ni à moins de K.formAheadBrakeTime s d'une voiture devant qui freine.
function M.mayWeave(e,frame,i,lap,skipLat)
 local a=frame.cars[i]; local s=e.states[i]
 if not a.splineValid or a.kmh<K.weaveMinKmh then return false end
 if not skipLat and abs(a.yawRate or 0)*(a.speed or 0)>K.weaveLatAccel then return false end
 if s.zone and (s.zone.noYield or s.zone.noOvertake) then return false end
 if ((-a.spline)%1)*frame.length<=(lap and K.formWeaveStopBefore or K.weaveStopBefore) then return false end
 -- Beta 2.0.4 : jamais dans la zone de l'entrée des stands.
 if lap and M.nearPitEntry(e,frame,a) then return false end
 local row=e.perception and e.perception.rows[i]
 if not row then return false end
 for j=1,row.count do
  local n=row.neighbors[j]
  -- Affinage 1.63 : tour de formation : gardes devant, derrière et à côté (AK) ; derrière la voiture de sécurité : comme avant.
  if lap then
   if abs(n.long)<AK.alongside or (n.long>0 and n.long<AK.weaveAhead) or (n.long<0 and -n.long<AK.weaveBehind) then return false end
  elseif abs(n.long)<K.weaveClear then return false end
  if lap and n.long>0 and n.long<K.weaveClear+(a.speed or 0)*K.formAheadBrakeTime then
   local b=frame.cars[n.index]; if b and (b.brake or 0)>K.formAheadBrake then return false end
  end
 end
 return true
end
-- Beta 2.0.4 (pilote, 17 novembre : départs avortés à l'entrée des stands) : zone de l'entrée des stands (début de
-- pit_lane.ai, lu par src/applier.lua) de K.pitEntryBefore m avant à K.pitEntryAfter m après ; inconnue : jamais.
function M.nearPitEntry(e,frame,a)
 local entry=e.pitEntry or -1
 if entry<0 or not a.splineValid or (frame.length or 0)<=0 then return false end
 local d=U.spline(a.spline-entry)*frame.length
 return d>=-K.pitEntryBefore and d<=K.pitEntryAfter
end
-- Beta 2.0.4 (pilote, 17 novembre : « les zigzags sont trop minuscules ») : la garde du virage lisait le lacet de la
-- voiture, que le zigzag lui-même produit (8 m d'amplitude en 4 s, c'est plusieurs m/s²) : le zigzag se figeait vers
-- 0,6 m. Elle lit maintenant la trajectoire : courbure de la piste ici et K.formWeaveLook s devant (t.bend, 1/m, la plus
-- forte des deux), et l'écart latéral réel de la voiture à la trajectoire (t.lat, m, mesure du zigzag et des deux
-- files), au plus une fois par K.formWeaveMeasure s par voiture. Fonctions de CSP absentes : t.bend=-1 (garde d'avant).
function M.sample(t,frame,i,now)
 if now<t.sampleAt[i]+K.formWeaveMeasure then return end
 t.sampleAt[i]=now
 local a=frame.cars[i]
 local bend,lat=Snapshot.bendLat(a,frame.length)
 t.bend[i]=bend; t.latOk[i]=lat~=nil; t.lat[i]=lat or 0
end
-- Beta 2.0.4 : place latérale (m, + à droite réelle, depuis la trajectoire) vers décalage (fraction du côté, repère
-- calibré : sign).
local function toOffset(pos,lw,rw,sign) return sign*(pos>=0 and pos/rw or pos/lw) end
-- Beta 2.0.4 : mesure du zigzag, une ligne par IA à la fin de chaque tour de formation (ampleur réelle, part de la
-- largeur, part du temps où le zigzag était permis).
-- Tables de la mesure créées au besoin (état d'antics construit à la main par d'anciens appelants).
local function ensure(t)
 if t.wMin then return end
 t.bend,t.sampleAt,t.lat,t.latOk,t.wMin,t.wMax,t.wWidth,t.wOn,t.wAll,t.okSince={},{},{},{},{},{},{},{},{},{}
 for i=1,K.maxCars do t.bend[i]=-1; t.sampleAt[i]=-math.huge; t.lat[i]=0; t.latOk[i]=false; t.wMin[i]=math.huge; t.wMax[i]=-math.huge; t.wWidth[i]=0; t.wOn[i]=0; t.wAll[i]=0 end
end
local function measureReset(t) t.measured=false; for i=1,K.maxCars do t.wMin[i]=math.huge; t.wMax[i]=-math.huge; t.wWidth[i]=0; t.wOn[i]=0; t.wAll[i]=0 end end
local function measureLog(t,e,frame,now)
 if t.measured then return end
 t.measured=true
 -- Une seule ligne (la limite de lignes par seconde du journal chassait les dernières voitures) : moyenne, plus petite et
 -- plus grande ampleur (écart latéral réel de part et d'autre, voiture comprise), part du temps où le zigzag était permis.
 local n,sum,lo,hi,share=0,0,math.huge,0,0
 for i=1,frame.count do
  local a=frame.cars[i]
  if t.wAll[i]>0 and t.wMax[i]>t.wMin[i] and t.wWidth[i]>0 then
   local pct=100*(t.wMax[i]-t.wMin[i]+(a.width or K.width))/t.wWidth[i]
   n=n+1; sum=sum+pct; lo=min(lo,pct); hi=max(hi,pct); share=share+t.wOn[i]/t.wAll[i]
  end
 end
 if n>0 then U.log(e.log,now,'INFO',string.format('zigzag mesure: %d IA, ampleur %.0f %% de la largeur en moyenne (%.0f a %.0f %%), zigzag permis %.0f %% du temps',n,sum/n,lo,hi,100*share/n),-1) end
end
-- Beta 1.64 (lot 5, décision du pilote : zigzags derrière la voiture de sécurité seulement pneus froids) : un pneu à plus
-- de K.outLapTempMargin °C sous sa température idéale (définition du tour de sortie, src/strategy.lua) ; donnée inconnue :
-- froid (comme avant).
local function cold(a)
 if not (a.wearKnown and a.tyreTemp and a.tyreOptimum and (a.tyreOptimum[1] or 0)>0) then return true end
 for w=1,4 do if (a.tyreTemp[w] or 0)<(a.tyreOptimum[w] or 0)-K.outLapTempMargin then return true end end
 return false
end
-- Avant le pilotage : décalage latéral du tour de formation (zigzag, puis deux files à l'appel du départ lancé) et
-- zigzag derrière la voiture de sécurité.
-- 2.0.4 : une autre voiture en piste à la hauteur de la voiture i (repère de la voiture, tout écart latéral jusqu'à
-- AK.sideRange m) : recouvrement à moins de AK.sideClear m près.
function M.beside(frame,i)
 local a=frame.cars[i]
 if not (a and U.finite(a.x) and U.finite(a.lx)) then return false end
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=i and b.valid and not b.pit and U.finite(b.x) then
   local dx,dz=b.x-a.x,b.z-a.z
   if dx*dx+dz*dz<AK.sideRange*AK.sideRange and abs(dx*a.lx+dz*a.lz)<((a.length or K.length)+(b.length or K.length))*0.5+AK.sideClear then return true end
  end
 end
 return false
end
function M.weave(t,e,frame,now,dt)
 if not t.active then return end
 local inc=e.incidents
 local lap=inc.formation==true
 local on=lap or inc.neutral and inc.neutralMode=='sc' and inc.safetyPhase=='out' and not inc.relaunch
 if not on then
  if t.weaving then t.weaving=false; if t.lapWeave then t.lapWeave=false; measureLog(t,e,frame,now) end; for i=1,K.maxCars do t.form[i]=0; e.states[i].formOffset=nil; e.states[i].formWeave=nil; e.states[i].formFiles=nil; e.states[i].formLat=nil end end
  return
 end
 t.weaving=true; ensure(t)
 local seed=e.runtimeG.seed or 0; local sign=(e.g.offsetSign or 0)<0 and -1 or 1
 local files=lap and inc.rollCall==true
 -- Correctif 1.61 (décision du pilote, 11 novembre) : pendant le tour de formation, zigzag très marqué, d'un bord à
 -- l'autre (K.formWeaveAmp, rampe K.formWeaveRate) ; borne latérale propre au zigzag (src/director.lua, s.formWeave).
 -- Derrière la voiture de sécurité : zigzag d'avant.
 local weave=lap and not files
 -- Beta 2.0.4 : mesure du zigzag (remise à zéro au début du tour, ligne au journal à sa fin ou à l'appel des files).
 if weave and not t.lapWeave then t.lapWeave=true; measureReset(t) elseif not weave and t.lapWeave then t.lapWeave=false; measureLog(t,e,frame,now) end
 local step=(weave and AK.weaveRate or K.formOffsetRate)*(dt or 0)
 -- Affinage 2.0.4 (Monza, 16 h 29 : rangées de tête jamais formées ; la voiture de sécurité et le joueur aux stands
 -- comptaient dans le classement, la tête prenait une place paire et cherchait sa voisine aux stands) : places des deux
 -- files comptées parmi les voitures en piste seulement (ni stands, ni voiture de sécurité), dans l'ordre du classement ;
 -- publiées pour la file du directeur (s.rollPlace).
 if files then
  -- Affinage 2.0.4 (relecture : deux voitures d'une paire à 2,6 m l'une de l'autre échangent leur place au classement
  -- d'AC, d'où un changement de file à pleine vitesse et une tête qui s'échappe) : ordre figé à l'appel, voitures sorties
  -- (stands, abandon) retirées, ordre relatif gardé.
  local list=t.rankList or {}; t.rankList=list; local n=0
  if not t.rankFrozen then
   for i=1,frame.count do local a=frame.cars[i]; if a.valid and not a.pit and not a.safetyCar and not a.finished then n=n+1; list[n]=i end end
   for k=n+1,#list do list[k]=nil end
   table.sort(list,function(p,q) local ap,aq=place(frame.cars[p],p),place(frame.cars[q],q); if ap~=aq then return ap<aq end return p<q end)
   t.rankFrozen=true
  else
   for k=1,#list do local i=list[k]; local a=frame.cars[i]; if a and a.valid and not a.pit and not a.safetyCar and not a.finished then n=n+1; list[n]=i end end
   for k=n+1,#list do list[k]=nil end
  end
  for i=1,frame.count do if e.states[i] then e.states[i].rollPlace=nil end end
  for k=1,n do e.states[list[k]].rollPlace=k end
  -- Affinage 2.0.4 (pilote, 17 h 40 : tête partie devant, retardataires pas recollés au drapeau vert) : peloton groupé
  -- quand chaque voiture est à moins de K.rollCompactMax m (centre à centre, sur la piste) de la place d'avant ; plus
  -- grand écart publié (inc.rollSpread) pour le meneur (src/incidents.lua) et le drapeau vert.
  -- Les IA seulement (le joueur tient sa place lui-même ; s'il traîne, le vert vient quand même à K.rollGreenLast m).
  local spread=0; local prevAi=nil
  for k=1,n do
   local a=frame.cars[list[k]]
   if not a.player and a.splineValid then
    if prevAi and (frame.length or 0)>0 then local d=U.spline(prevAi.spline-a.spline)*frame.length; if d>spread then spread=d end end
    prevAi=a
   end
  end
  -- Hystérésis : groupé à K.rollCompactMax m au plus, plus groupé seulement au-delà de K.rollCompactOff m, et jamais
  -- deux changements en moins de K.rollCompactHold s (la tête ne passe pas d'une allure à l'autre à chaque image).
  inc.rollSpread=spread; inc.rollFirst=n>0 and list[1] or 0
  local want=inc.rollCompact
  if want==nil then want=spread<=K.rollCompactMax elseif want and spread>K.rollCompactOff then want=false elseif not want and spread<=K.rollCompactMax then want=true end
  if inc.rollCompact==nil or (want~=inc.rollCompact and now-(t.compactAt or -math.huge)>=K.rollCompactHold) then if want~=inc.rollCompact then t.compactAt=now end; inc.rollCompact=want end
 else for i=1,frame.count do if e.states[i] then e.states[i].rollPlace=nil end end; inc.rollSpread=nil; inc.rollCompact=nil; inc.rollFirst=nil; t.rankFrozen=false; t.compactAt=nil end
 for i=1,frame.count do
  local a=frame.cars[i]; local target=0; local back=false
  if lap and (a.valid and not a.pit) then M.sample(t,frame,i,now); e.states[i].formLat=t.latOk[i] and t.lat[i] or nil end
  if eligible(a) then
   back=weave
   -- Affinage 2.0.4 : début de la permission continue du zigzag (AK.weaveSettle).
   if weave then
    local ok=M.mayWeave(e,frame,i,lap,weave) and not (t.bend[i]>K.formWeaveBend)
    if ok then t.okSince[i]=t.okSince[i] or now else t.okSince[i]=nil end
    if t.period[i]<=0 then t.period[i]=U.lerp(AK.weavePeriodMin,AK.weavePeriodMax,U.unit(seed,i,K.anticSalt+6)) end
   end
   local lw,rw=a.leftWidth or 0,a.rightWidth or 0
   if files then
    -- Places impaires du côté de la pole (colonne des places impaires de la grille calculée : src/grid.lua).
    -- Beta 2.0.4 (décision du pilote, 17 novembre) : deux files de part et d'autre du milieu de la piste (un quart de la
    -- largeur), jamais dans la zone de l'entrée des stands (la file y reste sur la trajectoire).
    local left=(e.states[i].rollPlace or place(a,i))%2==1
    if M.nearPitEntry(e,frame,a) then target=0
    elseif K.rollPairs and lw>0 and rw>0 then target=toOffset((rw-lw)*0.5+(left and -1 or 1)*(lw+rw)*0.25,lw,rw,sign)
    else target=(left and -1 or 1)*K.gridColumn*sign end
   elseif M.mayWeave(e,frame,i,lap,weave) and (lap or cold(a) and (inc.unlapState or 'none')=='none') and not (weave and t.bend[i]>K.formWeaveBend)
    and not (weave and t.bend[i]>=0 and now-(t.okSince[i] or now)<AK.weaveSettle) then
    local period=t.period[i]
    if period<=0 then period=weave and U.lerp(AK.weavePeriodMin,AK.weavePeriodMax,U.unit(seed,i,K.anticSalt+6)) or U.lerp(K.weavePeriodMin,K.weavePeriodMax,U.unit(seed,i,K.anticSalt+6)); t.period[i]=period end
    -- Relecture 1.62 (S6) : amplitude du tour de formation réduite avec la vitesse (pleine sous K.formWeaveFullKmh,
    -- K.formWeaveFastShare à K.formWeaveFastKmh et au-delà) ; accélération latérale du zigzag lui-même : la cible du
    -- moment est tenue (pas de retour brusque à zéro).
    -- Affinage 2.0.4 (pilote, 17 novembre : un droite franc, un gauche franc, enchaînés) : vague en trapèze (sinus
    -- multiplié par K.formWeaveFlat, borné à 1) : la voiture tient chaque côté puis traverse d'un coup ; seulement après
    -- AK.weaveSettle s de zigzag permis sans interruption (plus de petits coups de volant quand une voiture passe dans la garde).
    local wave=sin(2*math.pi*now/period)
    if weave then wave=U.clamp(wave*K.formWeaveFlat,-1,1) end
    if weave and lw>0 and rw>0 then
     -- Beta 2.0.4 (décision du pilote : 90 % de la largeur) : zigzag centré sur le milieu de la piste, voiture comprise
     -- sur K.formWeaveShare de la largeur, part AK.fastShare à AK.weaveFastKmh.
     local share=U.lerp(1,AK.fastShare,U.clamp((a.kmh-AK.weaveFullKmh)/(AK.weaveFastKmh-AK.weaveFullKmh),0,1))
     local ampM=max(0,K.formWeaveShare*(lw+rw)*0.5-(a.width or K.width)*0.5)*share
     target=toOffset((rw-lw)*0.5+ampM*wave,lw,rw,sign)
    else
     local amp=K.weaveAmp
     if weave then amp=K.formWeaveAmp*U.lerp(1,K.formWeaveFastShare,U.clamp((a.kmh-AK.weaveFullKmh)/(AK.weaveFastKmh-AK.weaveFullKmh),0,1)) end
     target=amp*wave
    end
    -- Garde d'avant (lacet de la voiture) seulement quand la trajectoire n'a pas pu être lue.
    if weave and t.bend[i]<0 and abs(a.yawRate or 0)*(a.speed or 0)>K.weaveLatAccel then target=t.form[i] end
    back=false
    if weave then
     t.wOn[i]=t.wOn[i]+(dt or 0)
     if t.latOk[i] then local c=t.lat[i]; t.wMin[i]=min(t.wMin[i],c); t.wMax[i]=max(t.wMax[i],c); t.wWidth[i]=max(t.wWidth[i],lw+rw) end
    end
   end
   if weave then t.wAll[i]=t.wAll[i]+(dt or 0) end
  end
  -- Affinage 2.0.4 (pilote, vidéo de 17 h 34 : « droite, droite, droite, puis gauche, gauche, gauche » par petits coups) :
  -- zigzag interrompu par une voiture proche seulement (ligne droite lue, hors entrée des stands et approche de la grille) :
  -- l'écart latéral est tenu, jamais un retour vers la file suivi d'une reprise (deux petits coups de volant).
  if weave and back and eligible(a) and t.bend[i]>=0 and t.bend[i]<=K.formWeaveBend and not M.nearPitEntry(e,frame,a)
   and a.splineValid and ((-a.spline)%1)*frame.length>K.formWeaveStopBefore then target=t.form[i]; back=false end
  -- Affinage 2.0.4 (banc : le joueur, 25 km/h plus vite, heurtait une IA qui revenait dans sa file en zigzaguant) :
  -- zigzag du tour de formation, voiture plus rapide qui arrive derrière (AK.closingWatch m, AK.closingSa km/h) : écart
  -- latéral tenu, ni zigzag ni retour vers la file tant qu'elle approche.
  if weave and eligible(a) then
   local row=e.perception and e.perception.rows[i]
   if row then for j=1,row.count do local n=row.neighbors[j]; if n.long<0 and -n.long<AK.closingWatch and (n.sa or 0)>AK.closingSa then target=t.form[i]; break end end end
  end
  -- Relecture 2.0.4 : retour vers la file borné à AK.returnRate par seconde (zigzag à AK.weaveRate 4 : jamais un coup de
  -- volant à l'entrée d'un virage).
  -- 2.0.4 (pilote, Monza, 18 novembre 11:47 : deux IA à la même hauteur, l'une zigzague dans l'autre : accrochage et
  -- tête-à-queue) : une voiture à sa hauteur sur la piste (à moins de AK.sideClear m de recouvrement, quel que soit
  -- l'écart latéral) : écart latéral tenu, ni zigzag ni retour vers la file.
  if weave and eligible(a) and M.beside(frame,i) then target=t.form[i]; back=false end
  local v=t.form[i]; local st=back and math.min(step*AK.returnMult,(weave and AK.returnRate or math.huge)*(dt or 0)) or step
  if v<target then v=min(target,v+st) elseif v>target then v=max(target,v-st) end
  t.form[i]=v
  e.states[i].formOffset=v~=0 and v or nil
  e.states[i].formWeave=weave and v~=0 or nil
  -- Beta 2.0.4 : les deux files du départ lancé ont la borne du zigzag (au quart de la largeur, au-delà de K.baseMax).
  e.states[i].formFiles=files and v~=0 or nil
 end
end
return M
