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
local K=C.K
local min,max,abs,sin,floor=math.min,math.max,math.abs,math.sin,math.floor
local M={}
function M.new()
 local t={session=-1,serial=0,kind='',at=-math.huge,window=0,react={},bog={},poor={},rowDelay={},list={},names={},
  form={},period={},weaving=false,synced=false,launchSeen=nil,restartSeen=0,standingSeen='none',jumper=0,poorCount=0,active=false,
  brakeAt={},brakeUntil={}}
 for i=1,K.maxCars do t.react[i]=0; t.bog[i]=0; t.poor[i]=false; t.rowDelay[i]=0; t.form[i]=0; t.period[i]=0; t.brakeAt[i]=0; t.brakeUntil[i]=-math.huge end
 return t
end
local function clearStart(t)
 t.kind=''; t.at=-math.huge; t.window=0; t.poorCount=0
 for i=1,K.maxCars do t.react[i]=0; t.bog[i]=0; t.poor[i]=false; t.rowDelay[i]=0 end
end
function M.reset(t)
 t.session=-1; t.serial=0; clearStart(t); t.synced=false; t.launchSeen=nil; t.restartSeen=0; t.standingSeen='none'; t.jumper=0
 t.weaving=false; t.active=false
 for i=1,K.maxCars do t.form[i]=0; t.period[i]=0; t.brakeAt[i]=0; t.brakeUntil[i]=-math.huge end
end
function M.rebase(t,amount)
 if U.finite(t.at) then t.at=t.at-amount end
 if t.launchSeen then t.launchSeen=t.launchSeen-amount end
 for i=1,K.maxCars do t.brakeAt[i]=t.brakeAt[i]-amount; if U.finite(t.brakeUntil[i]) then t.brakeUntil[i]=t.brakeUntil[i]-amount end end
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
   if kind=='form' then t.rowDelay[i]=(row-1)*K.formLaunchGap; t.window=max(t.window,t.rowDelay[i])
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
 for i=1,K.maxCars do t.form[i]=0; e.states[i].formOffset=nil; e.states[i].formWeave=nil; e.grid.aiRelease[i]=nil; t.brakeAt[i]=0; t.brakeUntil[i]=-math.huge end
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
   if now<t.brakeUntil[i] then
    local cmd=e.commands[i]; cmd.speedLimit=min(cmd.speedLimit or K.unlimitedSpeed,max(K.formBrakeFloor,a.kmh-K.formBrakeDrop))
   elseif now>=t.brakeAt[i] then
    local row=e.perception and e.perception.rows[i]
    local back=row and row.back>0 and row.neighbors[row.back] or nil
    if M.mayWeave(e,frame,i,true) and not (back and back.gap<K.formBrakeClear) and a.kmh>K.formBrakeFloor+K.formBrakeDrop then
     t.brakeUntil[i]=now+K.formBrakeTime
    end
    t.brakeAt[i]=now+U.lerp(K.formBrakeEveryMin,K.formBrakeEveryMax,U.unit(seed,i*31+floor(now),K.anticSalt+8))
   end
  end
 end
end
-- Après le pilotage : plafonds d'accélérateur du départ en cours.
function M.launch(t,e,frame,now)
 warm(t,e,frame,now)
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
 local row=e.perception and e.perception.rows[i]
 if not row then return false end
 for j=1,row.count do
  local n=row.neighbors[j]
  if abs(n.long)<K.weaveClear then return false end
  if lap and n.long>0 and n.long<K.weaveClear+(a.speed or 0)*K.formAheadBrakeTime then
   local b=frame.cars[n.index]; if b and (b.brake or 0)>K.formAheadBrake then return false end
  end
 end
 return true
end
-- Avant le pilotage : décalage latéral du tour de formation (zigzag, puis deux files à l'appel du départ lancé) et
-- zigzag derrière la voiture de sécurité.
function M.weave(t,e,frame,now,dt)
 if not t.active then return end
 local inc=e.incidents
 local lap=inc.formation==true
 local on=lap or inc.neutral and inc.neutralMode=='sc' and inc.safetyPhase=='out' and not inc.relaunch
 if not on then
  if t.weaving then t.weaving=false; for i=1,K.maxCars do t.form[i]=0; e.states[i].formOffset=nil; e.states[i].formWeave=nil end end
  return
 end
 t.weaving=true
 local seed=e.runtimeG.seed or 0; local sign=(e.g.offsetSign or 0)<0 and -1 or 1
 local files=lap and inc.rollCall==true
 -- Correctif 1.61 (décision du pilote, 11 novembre) : pendant le tour de formation, zigzag très marqué, d'un bord à
 -- l'autre (K.formWeaveAmp, rampe K.formWeaveRate) ; borne latérale propre au zigzag (src/director.lua, s.formWeave).
 -- Derrière la voiture de sécurité : zigzag d'avant.
 local weave=lap and not files
 local step=(weave and K.formWeaveRate or K.formOffsetRate)*(dt or 0)
 for i=1,frame.count do
  local a=frame.cars[i]; local target=0
  if eligible(a) then
   if files then
    -- Places impaires du côté de la pole (colonne des places impaires de la grille calculée : src/grid.lua).
    target=(place(a,i)%2==1 and -1 or 1)*K.gridColumn*sign
   elseif M.mayWeave(e,frame,i,lap,weave) then
    local period=t.period[i]
    if period<=0 then period=U.lerp(K.weavePeriodMin,K.weavePeriodMax,U.unit(seed,i,K.anticSalt+6)); t.period[i]=period end
    -- Relecture 1.62 (S6) : amplitude du tour de formation réduite avec la vitesse (pleine sous K.formWeaveFullKmh,
    -- K.formWeaveFastShare à K.formWeaveFastKmh et au-delà) ; accélération latérale du zigzag lui-même : la cible du
    -- moment est tenue (pas de retour brusque à zéro).
    local amp=K.weaveAmp
    if weave then amp=K.formWeaveAmp*U.lerp(1,K.formWeaveFastShare,U.clamp((a.kmh-K.formWeaveFullKmh)/(K.formWeaveFastKmh-K.formWeaveFullKmh),0,1)) end
    target=amp*sin(2*math.pi*now/period)
    if weave and abs(a.yawRate or 0)*(a.speed or 0)>K.weaveLatAccel then target=t.form[i] end
   end
  end
  local v=t.form[i]
  if v<target then v=min(target,v+step) elseif v>target then v=max(target,v-step) end
  t.form[i]=v
  e.states[i].formOffset=v~=0 and v or nil
  e.states[i].formWeave=weave and v~=0 or nil
 end
end
return M
