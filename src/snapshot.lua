local U=require('src/util')
local K=require('src/config').K
local TrackFile=require('src/trackfile') -- Beta 1.61 : clé des fichiers par circuit
local M={}
local function hexByte(c) return string.format('%02x',string.byte(c)) end
-- Beta 1.60 (lot 3) : Content Manager écrit le niveau et l'agressivité de la liste des engagés à la fin du nom du pilote
-- (« G. Tsaknis (100%, 100%) », parfois coupé par AC : « P. Müller (100% »). L'app applique ensuite ses propres valeurs :
-- ce suffixe est faux. Nom sans ce suffixe, ou nil s'il n'en porte pas (nom laissé tel quel).
local function stripName(name)
 -- Relecture (N4) : suffixe de Content Manager seulement après une espace (« Team(2) » reste un nom).
 local base=name:match('^(.-)%s+%(%d+%%,%s*%d+%%%)$')
 if not base then base=name:match('^(.-)%s+%(%d[%d%%,%s]*$') end
 if base and base~='' then return base end
 return nil
end
-- Beta 1.57 (Ved, Overtake : CSP 0.3.0-preview212, « en ligne » hors connexion) : une version de CSP plus ancienne n'a
-- pas tous les champs d'ac.getSim() et d'ac.getCar() ; lire un champ absent d'une structure FFI lève une erreur, et un
-- seul champ absent faisait échouer toute la lecture (session suspendue pour toujours, voitures jamais lues). Au premier
-- échec, chaque champ connu est essayé une fois sous protection ; les absents sont retenus pour tout le lancement et lus
-- ensuite comme absents (valeur neutre) par une vue de la structure, sans protection à chaque image. Version complète :
-- aucune vue, lecture directe comme avant.
local simFields={'isOnlineRace','isAltOnlineRace','isReplayActive','isReplayOnlyMode','isPaused','isInMainMenu','isSessionStarted',
 'isSessionFinished','raceSessionType','currentSessionIndex','trackLengthM','currentSessionTime','gameTime','timeToSessionStart',
 'sessionTimeLeft','rainWetness','rainIntensity','rainWater','carsCount','pitsSpeedLimit','raceFlagType','pitWindowStartTime',
 'pitWindowEndTime','time','leaderLapCount','fuelConsumptionRate','mechanicalDamageRate'}
local carFields={'position','look','speedKmh','side','isConnected','isActive','isUserControlled','isAIControlled','isRemote',
 'physicsAvailable','isInPit','isInPitlane','compoundIndex','isAIUsingRainTyres','drsPresent','drsAvailable','drsActive',
 'currentPenaltyType','currentPenaltyParameter','fuel','maxFuel','fuelPerLap','wheelsOutside','splinePosition','lapCount',
 'isLapValid','currentSector','lapTimeMs','bestLapTimeMs','previousLapTimeMs','brake','gas','aiLevel','aiAggression','velocity',
 'isRaceFinished','racePosition','highBeams','headlightsActive','lowBeams','flashingLightsActive','hornActive','aabbSize','wheels','waterTemperature','kersCharge'}
-- Beta 1.59 : champ du journal détaillé seulement (demande d'arrêt d'AC), hors de la liste des champs des voitures.
local requestingKnown=nil
local function readRequesting(raw) return raw.isRequestingPitStop end
local function requestingPit(raw)
 if requestingKnown==nil then local ok,value=pcall(readRequesting,raw); requestingKnown=ok; return ok and value==true end
 return requestingKnown and raw.isRequestingPitStop==true
end
-- Sans eux, rien à lire de la session : une vraie erreur de lecture (garde « online », genre « read »).
local essentialSim={'carsCount','currentSessionIndex'}
local safe={}
local function fieldOf(raw,name) return raw[name] end
local function viewMeta(kind) return {__index=function(t,k) if safe[kind].missing[k] then return nil end return rawget(t,'raw')[k] end} end
-- État par structure : champs absents (ensemble et liste), vue active, essai déjà fait ; vues réutilisées.
function M.resetFields()
 safe.sim={missing={},list={},on=false,probed=false}; safe.car={missing={},list={},on=false,probed=false}
 safe.simView=setmetatable({},viewMeta('sim')); safe.carViews={}; safe.carMeta=viewMeta('car'); safe.serial=(safe.serial or 0)+1
end
M.resetFields()
-- Champs essayés une fois : vrai si un nouveau champ absent a été trouvé (la vue s'active).
local function probe(kind,raw,names)
 local st=safe[kind]; local found=false
 st.probed=true
 for _,name in ipairs(names) do
  if not st.missing[name] and not pcall(fieldOf,raw,name) then st.missing[name]=true; st.list[#st.list+1]=name; found=true end
 end
 if found then st.on=true; safe.serial=safe.serial+1 end
 return found
end
local function simGet()
 local r=ac.getSim()
 if r~=nil and safe.sim.on then safe.simView.raw=r; return safe.simView end
 return r
end
local function carGet(index)
 local raw=ac.getCar(index)
 if raw==nil or not safe.car.on then return raw end
 local view=safe.carViews[index]
 if not view then view=setmetatable({},safe.carMeta); safe.carViews[index]=view end
 view.raw=raw
 return view
end
-- Champs absents pour le journal et le diagnostic ; numéro de version de la liste (changé à chaque nouveau champ).
-- Champ absent de certaines versions de CSP : lu sous protection, sans fermeture créée à chaque image.
local function collidedWith(raw) return raw.collidedWith end
-- Dégâts d'une IA à son emplacement (Beta 1.20) : carrosserie (somme des quatre côtés, km/h), suspension la plus
-- touchée (0 à 1), vie du moteur (1000 : neuf) ; réparation faite par AC lui-même (journal). Lus sous protection.
-- Carrosserie, suspension, moteur, boîte : une seule lecture pour les IA et le joueur (aucune table créée).
local function damageValues(raw)
 local d,sd=raw.damage,raw.suspensionDamage
 return d and U.number(d[0],0,1000,0)+U.number(d[1],0,1000,0)+U.number(d[2],0,1000,0)+U.number(d[3],0,1000,0) or 0,
  sd and math.max(U.number(sd[0],0,1,0),U.number(sd[1],0,1,0),U.number(sd[2],0,1,0),U.number(sd[3],0,1,0)) or 0,
  U.number(raw.engineLifeLeft,0,K.engineLifeNew,K.engineLifeNew),U.number(raw.gearboxDamage,0,1,0)
end
local function sizeRead(a)
 local size=carGet(a.index).aabbSize
 a.length=size and U.finite(size.z) and size.z>=K.minLength and size.z<=K.maxLength and size.z or K.length
 a.width=size and U.finite(size.x) and size.x>=K.minWidth and size.x<=K.maxWidth and size.x or K.width
end
local function damageRead(a,raw)
 a.damageBody,a.damageSuspension,a.engineLife,a.damageGearbox=damageValues(raw); a.repairingNative=raw.isRepairing==true
end
-- Dégâts du joueur (Beta 1.32, drapeau noir à disque orange) : rangés à part (ceux des IA ne sont lus qu'à leur
-- emplacement), avec le taux de dégâts mécaniques de la session (0 : dégâts désactivés).
local function playerDamage(s,a)
 local raw=carGet(a.index)
 s.playerBody,s.playerSuspension,s.playerEngine,s.playerGearbox=damageValues(raw)
 local blown=false; local wheels=raw.wheels
 if wheels then for w=0,3 do local wheel=wheels[w]; if wheel and wheel.isBlown==true then blown=true end end end
 s.playerBlown=blown; s.damageRate=U.number(simGet().mechanicalDamageRate,0,1000,1); s.playerDamageSlot=a.slot
end
function M.new()
 local s={cars={},count=0,player=0,errors=0,invalid=0,track='',layout='',trackKey='',trackName='',patch='',conflict='',metaAt=-1,session=-1,
  online=true,onlineKind='',readError='',missingSim='',missingCar='',replay=false,paused=false,menu=false,started=false,finished=false,length=0,time=0,startIn=0,left=0,wet=0,rain=0,water=0,type=1,stamp=-1,configType=0,configTrackDay=false,configSession=-1,
  flag=0,fuelRate=1,pitWindowStart=0,pitWindowEnd=0,simTime=0,sessionLaps=0,sessionMinutes=0,timedRace=false,leaderLaps=0,
  playerDamageSlot=0,playerDamageAt=-1,playerBody=0,playerSuspension=0,playerEngine=1000,playerGearbox=0,playerBlown=false,damageRate=1}
 for i=1,K.maxCars do s.cars[i]={slot=i,index=i-1,valid=false,control=false,player=false,pit=false,offtrack=false,
 x=0,y=0,z=0,lx=0,lz=1,speed=0,kmh=0,yaw=0,corner=1,cornerYaw=1,spline=0,splineValid=false,lap=0,lapValid=false,
 length=K.length,width=K.width,brake=0,gas=0,aiLevel=1,aiAggression=0.5,stopped=0,slip=0,leftWidth=0,rightWidth=0,leftAhead=0,rightAhead=0,leftAhead2=0,rightAhead2=0,trackLat=0,trackLatValid=false,trackLatAge=math.huge,
 highBeams=false,headlightsActive=false,lowBeams=false,flashingLightsActive=false,hornActive=false,
 id='',name='',skin='',skinKnown=false,skinSafety=false,position=0,teleport=false,previousX=0,previousZ=0,initialized=false} end
 return s
end
local function vector(v) return v and U.finite(v.x) and U.finite(v.z) and math.abs(v.x)<10000000 and math.abs(v.z)<10000000 end
-- Point de la trajectoire IA (maintien de ligne au départ), alloué une fois.
local laneVec
local function laneProbe()
 if laneVec==nil then local ok,v=pcall(function() return vec3() end); laneVec=ok and v or false end
 return laneVec
end
-- Beta 1.59.1 : longueur du circuit de la lecture en cours (sens de la piste d'une voiture lente).
local trackLength=0
-- Beta 1.60 : jugement des collisions en service pour la lecture en cours (écart latéral de toutes les voitures).
local blameWanted=false
-- Affinage 1.62 (coût, AUDIT_FPS cause 1) : sens latéral de la voiture (raw.side, une référence cdata par voiture) lu
-- seulement quand l'hôte en a besoin (recherche ou mesure du sens latéral, src/calibration.lua) ; vrai par défaut.
M.sideWanted=true
local sideWanted=true
-- Affinage 1.62 (coût) : collision lue sous protection une seule fois par lancement (comme isRequestingPitStop) ; ensuite
-- lecture directe, ou valeur neutre sur un CSP sans ce champ.
local collidedKnown=nil
local function collidedValue(raw)
 if collidedKnown==nil then local ok,value=pcall(collidedWith,raw); collidedKnown=ok; return ok and value or nil end
 return collidedKnown and raw.collidedWith or nil
end
local function readCar(a,index,dt,lane)
 a.valid=false; a.control=false; a.player=false; a.teleport=false
 local raw=carGet(index)
 -- Champs vectoriels lus une fois : chaque lecture d'un champ structuré d'une cdata crée une référence (déchet).
 local position,look=raw and raw.position,raw and raw.look
 -- Affinage 1.62 (coût) : chaque champ lu une seule fois par image (avant : vitesse lue cinq fois, roues hors piste,
 -- spline, tours… plusieurs fois) ; valeurs et ordre des tests inchangés.
 local kmh=raw and raw.speedKmh
 if not raw or not vector(position) or not vector(look) or not U.finite(kmh) then return false end
 local norm=math.sqrt(look.x*look.x+look.z*look.z)
 if norm<0.1 or kmh<0 or kmh>1000 then return false end
 local x,z=position.x,position.z
 -- Relecture du lot 3 (S10) : une image très longue n'est pas une téléportation : saut d'au moins 1,5 fois le chemin
 -- parcouru à la vitesse lue pendant dt (une voiture lancée à 300 km/h fait 8 m en 0,1 s).
 local jump=math.max(K.teleport,K.teleportPath*kmh/3.6*(dt or 0))
 a.teleport=a.initialized and (x-a.previousX)^2+(z-a.previousZ)^2>jump*jump
 a.previousX=x; a.previousZ=z; a.x=x; a.z=z; a.y=U.number(position.y,-10000,10000,0)
 local lx,lz=look.x/norm,look.z/norm; local yaw=math.atan2(lx,lz)
 local angular=a.initialized and U.wrap(yaw-a.yaw)/math.max(0.001,dt) or 0
 a.yawRate=U.ema(a.yawRate or 0,angular,dt,K.yawTau); a.yaw=yaw; a.lx=lx; a.lz=lz
 if sideWanted then
  local side=raw.side
  a.sideDot=side and U.finite(side.x) and U.finite(side.z) and (-side.x*lz+side.z*lx) or 0
 else a.sideDot=0 end
 a.kmh=kmh; a.speed=U.ema(a.speed,kmh/3.6,dt,K.speedTau)
 if not a.initialized or a.teleport then a.speed=kmh/3.6; a.yawRate=0 end
 a.initialized=true; a.valid=raw.isConnected~=false and raw.isActive~=false
 local player=raw.isUserControlled==true
 a.player=player
 local control=raw.isAIControlled==true and not player and not raw.isRemote and raw.physicsAvailable~=false
 a.control=control
 local inPit=raw.isInPit==true
 a.pit=inPit or raw.isInPitlane==true
 a.inPitBox=inPit
 -- Beta 1.58 : demande d'arrêt d'AC (journal détaillé, arrivée à l'emplacement). Beta 1.59 (relecture) : lue à part,
 -- essayée une seule fois par lancement : sur un CSP sans ce champ, elle n'envoie plus toutes les lectures des voitures par
 -- le chemin des champs absents.
 a.requestingPit=requestingPit(raw)
 local compound=raw.compoundIndex
 a.compoundIndex=U.finite(compound) and compound>=0 and math.floor(compound) or nil
 a.currentTyreIsDry=a.compoundIndex~=nil and a.dryCompounds~=nil and a.dryCompounds[a.compoundIndex]==true
 local rainTyres=raw.isAIUsingRainTyres
 a.nativeRainTyres=rainTyres==true
 -- DRS natif d'AC (zones du circuit, règle de la seconde) : seulement lu, pour le bip et le panneau du joueur.
 a.drsPresent=raw.drsPresent==true; a.drsAvailable=raw.drsAvailable==true; a.drsActive=raw.drsActive==true
 -- Pénalité native d'AC en cours (renseignée pour la voiture du joueur seulement) : reprise par le panneau.
 a.penaltyType=player and math.floor(U.number(raw.currentPenaltyType,0,16,0)) or 0
 a.penaltyParam=player and math.floor(U.number(raw.currentPenaltyParameter,-1,100000,0)) or 0
 -- Carburant des IA (litres ; -1 inconnu) et estimation d'AC par tour (0 tant qu'elle n'est pas disponible).
 if control then a.fuel=U.number(raw.fuel,0,10000,-1); a.maxFuel=U.number(raw.maxFuel,0,10000,-1); a.fuelPerLap=U.number(raw.fuelPerLap,0,1000,0)
 else a.fuel=-1; a.maxFuel=-1; a.fuelPerLap=0 end
 -- Dégâts lus seulement à l'emplacement ; un champ absent laisse la voiture valide, sans dégât connu.
 -- Beta 1.24 : aussi sur une IA lente ou arrêtée (voiture cassée à évacuer aussitôt).
 -- Beta 1.28 : aussi sur une IA anormalement lente surveillée par le moteur (diagnostic).
 if not (control and (inPit or kmh<K.damageReadSpeed or a.watchDamage or a.damageScan) and pcall(damageRead,a,raw)) then a.damageBody=0; a.damageSuspension=0; a.engineLife=K.engineLifeNew; a.repairingNative=false; a.damageGearbox=0 end
 a.nativeRainTyresKnown=type(rainTyres)=='boolean'
 local outside=raw.wheelsOutside
 local outsideOK=U.finite(outside)
 a.offtrack=not outsideOK or outside>2
 local spline=raw.splinePosition
 a.splineValid=U.finite(spline) and spline>=0 and spline<=1
 a.spline=a.splineValid and spline or 0
 local laps=raw.lapCount
 a.lapValid=U.finite(laps) and laps>=0 and laps%1==0
 a.lap=a.lapValid and laps or 0
 -- Beta 1.42 : roues hors des limites (0 à 4), validité du tour en cours, secteur et temps du tour (sanctions des IA).
 a.wheelsOut=outsideOK and math.max(0,math.min(4,math.floor(outside))) or 0
 local sector=raw.currentSector
 a.lapNowValid=raw.isLapValid~=false; a.sector=U.finite(sector) and math.max(0,math.floor(sector)) or 0
 a.lapTimeMs=U.number(raw.lapTimeMs,0,1e9,0)
 -- Meilleur et dernier tour (Beta 1.25, overlay et récapitulatif de course), en secondes ; 0 : aucun.
 a.bestLap=U.number(raw.bestLapTimeMs,0,1e8,0)/1000; a.lastLap=U.number(raw.previousLapTimeMs,0,1e8,0)/1000
 -- Beta 1.52 : longueur et largeur (raw.aabbSize) lues avec les métadonnées (sizeRead, toutes les K.metaPeriod s),
 -- plus à chaque image.
 a.brake=U.number(raw.brake,0,1,0); a.gas=U.number(raw.gas,0,1,0)
 a.aiLevel=U.number(raw.aiLevel,0,2,K.defaultLevel); a.aiAggression=U.number(raw.aiAggression,0,1,K.defaultAggression)
 a.stopped=0
 a.slip=0
 local velocity=raw.velocity
 if vector(velocity) and a.speed>1 then a.slip=math.abs(U.wrap(math.atan2(velocity.x,velocity.z)-yaw))*180/math.pi end
 a.finished=raw.isRaceFinished==true
 -- Position au classement de la course (CSP) ; 0 si inconnue.
 local place=raw.racePosition
 a.position=U.finite(place) and place>=1 and math.floor(place) or 0
 local collided=collidedValue(raw)
 a.collided=U.finite(collided) and collided>=0
 -- Voiture touchée (Beta 1.24) : 0 = décor, sinon numéro de la voiture plus 1, soit sa case dans la liste.
 a.collidedWith=a.collided and math.floor(collided) or -1
 -- Affinage 1.62 (coût) : feux et klaxon lus pour le joueur seulement (et la première voiture, place du joueur quand un
 -- mode ne publie pas isUserControlled) : seuls lecteurs, l'apprentissage et l'appel de phares du joueur (src/flash.lua,
 -- src/engine.lua) ; les appels de phares entre IA sont commandés par l'app, jamais lus.
 if player or index==0 then
  a.highBeams=raw.highBeams==true; a.headlightsActive=raw.headlightsActive==true; a.lowBeams=raw.lowBeams==true
  a.flashingLightsActive=raw.flashingLightsActive==true; a.hornActive=raw.hornActive==true
 else a.highBeams=false; a.headlightsActive=false; a.lowBeams=false; a.flashingLightsActive=false; a.hornActive=false end
 a.leftWidth=0; a.rightWidth=0
 if a.splineValid and ac.getTrackAISplineSides then
  local ok,sides=pcall(ac.getTrackAISplineSides,a.spline)
  if ok and sides then a.leftWidth=U.number(sides.x,0,100,0); a.rightWidth=U.number(sides.y,0,100,0) end
 end
 -- Beta 1.60 : largeurs K.reachLook1 et K.reachLook2 s plus loin (K.reachLookMin m au moins par pas), pour les IA
 -- pilotées : la borne de décalage du grand côté (src/director.lua, M.reachable) se referme avant que la trajectoire
 -- ne traverse la piste. Lecture manquée : 0, la borne reste celle d'avant.
 -- Relecture (coût) : relues toutes les K.reachLookPeriod s par voiture, décalées d'une voiture à l'autre (une image
 -- par indice, six groupes) ; la dernière lecture reste valable entre deux.
 if a.control and a.leftWidth>0 and a.rightWidth>0 and trackLength>0 then
  a.aheadAge=a.aheadAge==nil and K.reachLookPeriod-(index%6)*K.reachLookStagger or a.aheadAge+dt
  if a.aheadAge>=K.reachLookPeriod then
   a.aheadAge=0
   a.leftAhead=0; a.rightAhead=0; a.leftAhead2=0; a.rightAhead2=0
   local d1=math.max(a.speed*K.reachLook1,K.reachLookMin); local d2=math.max(a.speed*K.reachLook2,K.reachLookMin*2)
   local ok,sides=pcall(ac.getTrackAISplineSides,(a.spline+d1/trackLength)%1)
   if ok and sides then a.leftAhead=U.number(sides.x,0,100,0); a.rightAhead=U.number(sides.y,0,100,0) end
   ok,sides=pcall(ac.getTrackAISplineSides,(a.spline+d2/trackLength)%1)
   if ok and sides then a.leftAhead2=U.number(sides.x,0,100,0); a.rightAhead2=U.number(sides.y,0,100,0) end
  end
 else a.leftAhead=0; a.rightAhead=0; a.leftAhead2=0; a.rightAhead2=0; a.aheadAge=nil end
 -- Écart à la trajectoire IA (m, repère latéral interne : positif à droite), lu seulement pendant le départ.
 a.splineLat=0; a.splineLatValid=false
 -- Beta 1.59.1 : voiture lente ou arrêtée hors des stands, dans toutes les sessions (src/incidents.lua) : distance à la
 -- trajectoire IA (m ; voiture arrêtée hors piste loin de la trajectoire, dégagée) et écart latéral selon le sens de la
 -- PISTE (m ; drapeau rouge, piste vraiment bloquée : l'écart du départ suit le cap de la voiture, faux pour une voiture
 -- en travers). Sens de la piste : second point K.lineAheadMeters m plus loin.
 local prevDist,prevDistValid,prevLat,prevLatValid=a.lineDist,a.lineDistValid,a.lineLat,a.lineLatValid
 a.lineDist=0; a.lineDistValid=false; a.lineLat=0; a.lineLatValid=false
 local slow=not a.pit and a.kmh<K.offLineKmh
 -- Beta 1.60 (relecture : deux lectures par voiture lente et par image, grille entière arrêtée avant les feux) : voiture
 -- qui n'a pas bougé de K.lineStill m depuis sa dernière lecture réussie : valeurs gardées, aucune lecture.
 local still=slow and prevDistValid==true and prevLatValid==true and a.lineX~=nil and math.abs(x-a.lineX)<K.lineStill and math.abs(z-a.lineZ)<K.lineStill
 if still then a.lineDist=prevDist; a.lineDistValid=true; a.lineLat=prevLat; a.lineLatValid=prevLatValid; slow=false end
 -- Beta 1.60 (relecture : le jugement des collisions lisait l'écart du départ, jamais mesuré hors du départ ni pour le
 -- joueur) : écart latéral selon le sens de la piste (a.trackLat, m) pour TOUTE voiture hors des stands, joueur
 -- compris, quand le jugement est en service (s.blameWanted, src/engine.lua) ; relu toutes les K.blameLatPeriod s par
 -- voiture, la dernière valeur restant valable entre deux lectures.
 local trackDue=false
 if blameWanted and not a.pit and a.splineValid then
  -- Relecture (coût) : premières lectures décalées d'une voiture à l'autre (une image par indice, six groupes).
  if a.trackLatAge==nil or a.trackLatAge==math.huge then a.trackLatAge=K.blameLatPeriod-(index%6)*K.reachLookStagger else a.trackLatAge=a.trackLatAge+dt end
  trackDue=a.trackLatAge>=K.blameLatPeriod
 else a.trackLatValid=false; a.trackLatAge=math.huge end
 if (lane and a.control or slow or trackDue) and a.splineValid then
  local probe=laneProbe()
  if probe and pcall(ac.trackProgressToWorldCoordinateTo,a.spline,probe) and U.finite(probe.x) and U.finite(probe.z) then
   if lane and a.control then a.splineLat=(x-probe.x)*lz-(z-probe.z)*lx; a.splineLatValid=true end
   if slow or trackDue then
    local px,pz=probe.x,probe.z
    if slow then a.lineDist=math.sqrt((x-px)^2+(z-pz)^2); a.lineDistValid=true; a.lineX=x; a.lineZ=z end
    local step=trackLength and trackLength>0 and K.lineAheadMeters/trackLength or 0
    local lat=nil
    if step>0 and pcall(ac.trackProgressToWorldCoordinateTo,(a.spline+step)%1,probe) and U.finite(probe.x) and U.finite(probe.z) then
     local tx,tz=probe.x-px,probe.z-pz; local n=math.sqrt(tx*tx+tz*tz)
     if n>K.lineAheadMeters*0.5 and n<K.lineAheadMeters*2 then lat=((x-px)*tz-(z-pz)*tx)/n end
    end
    if slow and lat then a.lineLat=lat; a.lineLatValid=true end
    if trackDue then a.trackLatValid=lat~=nil; a.trackLat=lat or 0; a.trackLatAge=0 end
   end
  elseif trackDue then a.trackLatValid=false end
 end
 return a.valid
end
-- Beta 1.61 (tranche E, réglage weatherLive) : prévision météo de CSP (type en cours, type à venir, transition de 0 à 1),
-- lue sous protection une fois par K.wxPeriod s au plus, et seulement quand le réglage est en service (M.wxWanted, posé par
-- l'hôte) ; lecture ratée (champs absents, CSP plus ancien) : prévision inconnue, nouvel essai K.wxRetry s plus tard.
M.wxWanted=false
local wxAt,wxRetryAt=-math.huge,-math.huge
local function wxFields() local c=ac.getSim().weatherConditions; return c.currentType,c.upcomingType,c.transition end
local function wxRead(s)
 if not M.wxWanted then return end
 if math.abs(s.time-wxAt)<K.wxPeriod then return end
 if s.wxKnown==false and math.abs(s.time-wxRetryAt)<K.wxRetry then return end
 wxAt=s.time
 local ok,cur,upc,tr=pcall(wxFields)
 if ok and type(tr)=='number' and tonumber(upc)~=nil then
  s.wxKnown=true; s.wxCurrent=tonumber(cur) or -1; s.wxUpcoming=tonumber(upc); s.wxTransition=U.number(tr,0,1,0)
 else wxRetryAt=s.time; s.wxKnown=false; s.wxCurrent=-1; s.wxUpcoming=-1; s.wxTransition=-1 end
end
M.wxRead=wxRead
local function simRead(s)
 local r=simGet()
 s.online=r.isOnlineRace==true or r.isAltOnlineRace==true
 -- Beta 1.57 (Ved, Overtake : « en ligne » hors connexion) : genre de la suspension, pour l'affichage et le journal
 -- seulement (s.online reste le seul drapeau qui suspend) : vraie course en ligne, mode alt-online d'un script New
 -- Modes de CSP (annoncé même hors connexion), ou lecture impossible (M.read).
 s.onlineKind=r.isOnlineRace==true and 'online' or r.isAltOnlineRace==true and 'alt' or ''
 s.replay=r.isReplayActive==true or r.isReplayOnlyMode==true
 -- Le menu setup/garage n'arrête pas la session : seules les fenêtres en dépendent, le moteur continue.
 s.paused=r.isPaused==true; s.menu=s.paused or r.isInMainMenu==true
 s.started=r.isSessionStarted==true; s.finished=r.isSessionFinished==true
 s.type=U.number(r.raceSessionType,0,20,1); s.session=U.number(r.currentSessionIndex,0,1000,0)
 s.length=U.number(r.trackLengthM,0,1000000,0)
 s.time=U.number(r.currentSessionTime,0,1e12,0)/1000
 s.stamp=U.number(r.gameTime,0,1e12,-1)
 s.startIn=U.number(r.timeToSessionStart,-1e9,1e9,0)/1000
 s.left=U.number(r.sessionTimeLeft,0,1e12,0)/1000
 s.wet=U.number(r.rainWetness,0,1,0)
 s.rain=U.number(r.rainIntensity,0,1,0); s.water=U.number(r.rainWater,0,1,0)
 wxRead(s)
 s.count=math.floor(U.number(r.carsCount,0,K.maxCars,0))
 -- 1.42 SANCTIONS : vitesse limite des stands (excès de vitesse des IA) ; nombre de secteurs (dernier secteur : tour
 -- suivant invalidé aussi), lu une fois par session.
 s.pitsSpeedLimit=U.number(r.pitsSpeedLimit,10,400,K.sanPitLimitDefault)
 if s.sectorsSession~=s.session or s.sectorsLength~=s.length then
  s.sectorsSession=s.session; s.sectorsLength=s.length
  local ok,n=pcall(function() return #r.lapSplits end); s.sectorCount=ok and U.number(n,0,64,0) or 0
  -- Beta 1.56 : pénalités d'AC (lecture seule, une fois par session) : vos limites de piste gérées par l'app préviennent
  -- d'une double sanction. Champ absent : inconnu (nil).
  local okP,pen=pcall(function() return r.penaltiesEnabled end); s.penaltiesEnabled=okP and type(pen)=='boolean' and pen or nil
  local okT,out=pcall(function() return r.allowedTyresOut end); s.allowedTyresOut=okT and U.finite(out) and math.floor(out) or nil
 end
end
-- Drapeau, fenêtre d'arrêt et tours du leader (1.3.0), lus à part : un champ indisponible les laisse neutres.
local function raceRead(s)
 local r=simGet()
 s.flag=math.floor(U.number(r.raceFlagType,0,64,0))
 s.pitWindowStart=U.number(r.pitWindowStartTime,0,1e13,0); s.pitWindowEnd=U.number(r.pitWindowEndTime,0,1e13,0)
 s.simTime=U.number(r.time,0,1e13,0); s.leaderLaps=math.floor(U.number(r.leaderLapCount,0,100000,0))
 -- Consommation de carburant de la session (0 : coupée, rien à gérer) ; champ absent : comptée.
 s.fuelRate=U.number(r.fuelConsumptionRate,0,100,1)
end
local conflictPeriod=30
local function conflictingApp(app)
 if type(app)~='table' then return nil end
 local name=tostring(app.name or ''):sub(1,K.metadataLength)..' '..tostring(app.title or ''):sub(1,K.metadataLength)
 local id=name:lower():gsub('[^%w]','')
 if id:find('realistictrackday',1,true) or id:find('fullsendai',1,true) or id:find('aiwhisperer',1,true) or id:find('verve',1,true) then return name:lower():gsub('^%s+',''):gsub('%s+$','') end
 return nil
end
-- Beta 1.42 : usure, distance virtuelle et températures des pneus, eau et batterie d'une IA (une fois par seconde) ;
-- tables créées une fois par voiture.
local function wearRead(a)
 local raw=carGet(a.index)
 local wheels=raw and raw.wheels
 if not wheels then a.wearKnown=false; return end
 if not a.tyreWear then a.tyreWear={0,0,0,0}; a.tyreKm={0,0,0,0}; a.tyreTemp={0,0,0,0}; a.tyreOptimum={0,0,0,0} end
 for w=1,4 do
  local wheel=wheels[w-1]
  if wheel then
   a.tyreWear[w]=U.number(wheel.tyreWear,0,1,0); a.tyreKm[w]=U.number(wheel.tyreVirtualKM,0,100000,0)
   a.tyreTemp[w]=U.number(wheel.tyreCoreTemperature,-50,400,0); a.tyreOptimum[w]=U.number(wheel.tyreOptimumTemperature,0,400,0)
  end
 end
 a.waterTemp=U.number(raw.waterTemperature,-50,300,-1); a.kers=U.number(raw.kersCharge,0,1,-1); a.wearKnown=true
end
local function tyres(a)
 a.tyresID=a.identity or ''; a.tyresKnown=false; a.dryCompound=-1; a.wetCompound=-1; a.interCompound=-1; a.dryCompounds={}; a.dryList={}; a.tyreNames={}; a.tyreLongNames={}; a.dryPrimary={}; a.tyreClass={}
 if not ac.getTyresName then return end
 local any=false; local primary={}
 for index=0,K.maxTyreCompounds-1 do
  local ok,short=pcall(ac.getTyresName,a.index,index)
  if not ok or type(short)~='string' or short=='' then break end
  local name=short
  if ac.getTyresLongName then local good,long=pcall(ac.getTyresLongName,a.index,index,false); if good and type(long)=='string' then name=name..' '..long; a.tyreLongNames[index]=long end end
  a.tyreNames[index]=short; name=name:lower(); any=true
  local legal=true
  if ac.areTyresLegal then local good,allowed=pcall(ac.areTyresLegal,short); if good and allowed==false then legal=false end end
  if legal then
   if short:upper()=='I' or short:upper()=='INT' or name:find('intermediate',1,true) or name:find('intermedia',1,true) then a.interCompound=index; a.tyreClass[index]='intermediaire'
   elseif short:upper()=='W' or name:find('wet',1,true) or name:find('rain',1,true) or name:find('pluie',1,true) then a.wetCompound=index; a.tyreClass[index]='pluie'
   else
    a.tyreClass[index]='sec'
    a.dryCompounds[index]=true; a.dryList[#a.dryList+1]=index; if a.dryCompound<0 or index==a.compoundIndex then a.dryCompound=index end
    if not primary[short:upper()] then primary[short:upper()]=true; a.dryPrimary[#a.dryPrimary+1]=index end
   end
  else a.tyreClass[index]='non autorise' end
 end
 a.tyresKnown=any
 a.currentTyreIsDry=a.compoundIndex~=nil and a.dryCompounds[a.compoundIndex]==true
end
-- Beta 1.55 : lecture des gommes exposée aux tests (classes retenues).
M.tyres=tyres
-- Beta 1.57 : texte d'erreur de CSP ou de Lua pour le journal : une ligne, sans dossier (seul le nom du fichier reste),
-- au plus K.readErrorChars caractères.
function M.cleanError(err)
 -- Chemin d'un fichier Lua avant « fichier:ligne: » (espaces permis, « Assetto Corsa »), puis tout autre dossier.
 local text=tostring(err or ''):gsub('[\r\n]+',' '):gsub('%a:[\\/][^:]*[\\/]([^\\/:]+:)','%1'):gsub('%S*[\\/]','')
 if #text>K.readErrorChars then text=text:sub(1,K.readErrorChars) end
 return text
end
-- Métadonnées d'une voiture (identifiant, nom, taille, livrée, usure) : une tranche de n voitures à partir de s.metaNext.
local function metaCars(s,n)
 local last=math.min(s.count,(s.metaNext or 1)+n-1)
 for i=s.metaNext or 1,last do
  local a=s.cars[i]
  local oldID,oldName=a.id,a.name
  local idOK,id=pcall(ac.getCarID,a.index); if idOK and type(id)=='string' then a.id=id:sub(1,K.metadataLength) end
  -- Beta 1.60 (lot 3) : nom brut gardé (identité de la voiture, inchangée) ; nom affiché sans le suffixe de Content
  -- Manager (le moteur y ajoute le niveau et l'agressivité appliqués, src/engine.lua).
  local oldRaw=a.rawName or oldName
  local nameOK,name=pcall(ac.getDriverName,a.index)
  if nameOK and type(name)=='string' then
   name=name:sub(1,K.metadataLength)
   if name~=a.rawName then
    local base=stripName(name)
    a.rawName=name; a.cmSuffix=base~=nil; a.baseName=base or name; a.name=a.baseName; a.nameLv=nil; a.nameAg=nil
   end
  end
  if a.id~=oldID or (a.rawName or a.name)~=oldRaw then a.identity=(a.id..'\0'..(a.rawName or a.name)):gsub('.',hexByte) end
  if not pcall(sizeRead,a) then a.length=K.length; a.width=K.width end
  -- Livrée (dossier du skin) : une livrée « safety » désigne la voiture de sécurité parmi celles du modèle.
  local skinOK,skin=pcall(ac.getCarSkinID,a.index)
  if a.valid and a.control and not pcall(wearRead,a) then a.wearKnown=false end
  if skinOK and type(skin)=='string' and (skin~=a.skin or not a.skinKnown) then a.skin=skin:sub(1,K.metadataLength); a.skinKnown=true; a.skinSafety=a.skin:lower():find(K.safetySkinPattern,1,true)~=nil end
 end
 s.metaNext=last+1
end
-- Affinage 1.62 (mesure fine, AUDIT_FPS §7) : horloge de l'hôte (secondes, nil sans chronomètre) et coût cumulé des
-- sous-postes de la lecture : 1 session, 2 voitures, 3 métadonnées, 4 gommes ; remis à zéro par l'hôte (journal).
M.clock=nil
M.cost={0,0,0,0}
local function tick(i,at)
 if not at then return nil end
 local now=M.clock(); if not now then return nil end
 M.cost[i]=M.cost[i]+(now-at); return now
end
function M.read(s,dt,now,light)
 local at=M.clock and M.clock() or nil
 local ok,err=pcall(simRead,s)
 -- Beta 1.57 : premier échec : champs de la session essayés un par un (version de CSP plus ancienne), puis relecture
 -- par la vue ; seul un champ essentiel absent reste une erreur de lecture.
 if not ok and not safe.sim.probed then
  local got,r=pcall(ac.getSim)
  if got and r~=nil and probe('sim',r,simFields) then ok,err=pcall(simRead,s) end
 end
 -- Champs absents recopiés dans l'instantané (journal, diagnostic) seulement quand la liste change.
 if s.fieldsSerial~=safe.serial then s.fieldsSerial=safe.serial; s.missingSim=table.concat(safe.sim.list,', '); s.missingCar=table.concat(safe.car.list,', ') end
 if ok and safe.sim.on then for _,name in ipairs(essentialSim) do if safe.sim.missing[name] then ok=false; err='champ de CSP essentiel absent: '..name; break end end end
 -- Beta 1.57 : lecture impossible, toujours suspendue comme une session en ligne, mais nommée (texte de l'erreur sans
 -- chemin, raccourci).
 if not ok then s.online=true; s.onlineKind='read'; s.readError=M.cleanError(err); s.count=0; s.errors=math.min(K.counterMax,s.errors+1); return false end
 if not pcall(raceRead,s) then
  -- Beta 1.57 : même essai champ par champ si la session a pu être lue sans lui.
  local retried=false
  if not safe.sim.probed then local got,r=pcall(ac.getSim); if got and r~=nil and probe('sim',r,simFields) then retried=pcall(raceRead,s) end end
  if not retried then s.flag=0; s.pitWindowStart=0; s.pitWindowEnd=0; s.errors=math.min(K.counterMax,s.errors+1) end
 end
 -- Beta 1.52 : première lecture toujours complète (place du joueur connue avant toute lecture légère).
 at=tick(1,at)
 if light and not s.playerSlot then light=false end
 if not light and s.lightLast then s.metaAt=-1; s.configSession=-1 end
 s.lightLast=light==true
 s.player=0
 trackLength=s.length; blameWanted=s.blameWanted==true; sideWanted=M.sideWanted~=false
 if not light then for i=1,s.count do
  local a=s.cars[i]; local good,result=pcall(readCar,a,i-1,dt,s.laneWanted)
  -- Beta 1.57 : premier échec d'une voiture : champs des voitures essayés un par un, puis relecture par la vue.
  if not good and not safe.car.probed then
   local got,raw=pcall(ac.getCar,i-1)
   if got and raw~=nil and probe('car',raw,carFields) then good,result=pcall(readCar,a,i-1,dt,s.laneWanted) end
  end
  if not good or not result then a.valid=false; a.control=false; s.invalid=math.min(K.counterMax,s.invalid+1) end
  if a.player and a.valid then s.player=i end
 end
 -- L'indice zéro est réservé au joueur si un mode ne publie pas isUserControlled.
 s.playerFallback=s.player==0 and s.count>0
 if s.playerFallback then s.player=1; s.cars[1].player=true; s.cars[1].control=false end
 s.playerSlot=s.player; s.lightPlayer=0
 else
  -- Beta 1.52 : lecture légère (rien à piloter ni à rendre) : seule la voiture du joueur est relue (place trouvée à la
  -- dernière lecture complète), dans s.lightPlayer (s.player reste à 0 : le moteur et l'overlay, qui n'ont pas les
  -- autres voitures, font comme avant) ; les autres sont marquées invalides. Avant : la mise à jour se croyait en
  -- conduite aux stands, et le pont publiait les voitures d'une image ancienne comme valides.
  local k=s.playerSlot; s.lightPlayer=0
  for i=1,s.count do if i~=k then local a=s.cars[i]; a.valid=false; a.control=false end end
  if k>0 and k<=s.count then
   local a=s.cars[k]; local good,result=pcall(readCar,a,k-1,dt,false)
   if good and result and (a.player or s.playerFallback) then s.lightPlayer=k; if s.playerFallback then a.player=true; a.control=false end
   else a.valid=false; a.control=false end
  end
 end
 at=tick(2,at)
 if not light and s.player>0 and now>=s.playerDamageAt then
  s.playerDamageAt=now+K.playerDamagePeriod
  if not pcall(playerDamage,s,s.cars[s.player]) then s.playerDamageSlot=0 end
 end
 -- Affinage 1.61 (coût en jeu) : passe complète (première lecture, changement de session)
 -- dans la même image ; relecture périodique par tranches de K.metaCarsPerFrame voitures (suite dans les images suivantes).
 local metaFull=s.metaAt<0 or s.configSession~=s.session
 if now>=s.metaAt or s.configSession~=s.session then
  s.metaAt=now+K.metaPeriod
  -- race.ini est fixe pendant le processus : relu au changement de session, ou de nouveau après un échec.
  if s.configSession~=s.session then
   s.configType=0; s.configTrackDay=false
   local configOK,kind,name=pcall(function()
    if not ac.INIConfig or not ac.INIConfig.raceConfig then return 0,'' end
    local config=ac.INIConfig.raceConfig(); local section='SESSION_'..s.session
    return config:get(section,'TYPE',0),config:get(section,'NAME','')
   end)
   if configOK then
    s.configSession=s.session
    if U.finite(kind) and kind>=1 and kind<=7 then s.configType=kind end
    -- Content Manager nomme « Track Day » la session de son mode Journée circuit.
    if type(name)=='string' then s.configTrackDay=name:sub(1,K.metadataLength):lower():gsub('[^%w]',''):find('trackday',1,true)~=nil end
   end
  end
  local sessionOK,laps,minutes,timed=pcall(function()
   if not ac.getSession then return 0,0,false end
   local info=ac.getSession(s.session); if not info then return 0,0,false end
   return info.laps,info.durationMinutes,info.isTimedRace
  end)
  if sessionOK then s.sessionLaps=math.floor(U.number(laps,0,100000,0)); s.sessionMinutes=U.number(minutes,0,100000,0); s.timedRace=timed==true end
  local patchOK,patch=pcall(ac.getPatchVersion); if patchOK and type(patch)=='string' then s.patch=patch:sub(1,K.metadataLength) end
  local trackOK,track=pcall(ac.getTrackID); if trackOK and type(track)=='string' then s.track=track end
  -- Beta 1.61 : tracé du circuit et clé des fichiers par circuit (src/trackfile.lua) ; clé vide : rien n'est lu ni écrit.
  local layoutOK,layout=pcall(ac.getTrackLayout); s.layout=layoutOK and type(layout)=='string' and layout or ''
  s.trackKey=TrackFile.key(s.track,s.layout) or ''
  -- Beta 1.39 : nom affiché du circuit (en-tête de la fenêtre) ; l'identifiant reste pour le diagnostic.
  local nameOK,name=pcall(ac.getTrackName); if nameOK and type(name)=='string' then s.trackName=name:sub(1,K.metadataLength) end
  s.metaNext=1
  if not light then metaCars(s,metaFull and s.count or K.metaCarsPerFrame) end
  -- Affinage 1.62 (coût, AUDIT_FPS cause 8) : fenêtres des apps (jusqu'à 256, noms recopiés et convertis) cherchées au
  -- changement de session puis toutes les conflictPeriod s, plus à chaque relecture des métadonnées (chaque seconde) ;
  -- l'avertissement garde sa valeur entre deux recherches.
  local scan=metaFull or now>=(s.conflictAt or -math.huge)
  if scan then s.conflictAt=now+conflictPeriod; s.conflict='' end
  if scan and ac.getAppWindows then
   local appsOK,apps=pcall(ac.getAppWindows)
   if appsOK and type(apps)=='table' then
    for j=1,math.min(#apps,K.maxAppWindows) do
     local good,name=pcall(conflictingApp,apps[j])
     if good and name then s.conflict=name; break end
    end
   end
  end
 elseif not light and s.metaNext and s.metaNext<=s.count then metaCars(s,K.metaCarsPerFrame) end
 at=tick(3,at)
 local budget=K.tyreCatalogBudget
 if not light then for i=1,s.count do
  local a=s.cars[i]
  -- Beta 1.49 : le joueur aussi (noms de ses composés : arrêt obligatoire F1, stratégie des stands).
  if a.valid and (a.control or a.player) and a.tyresID~=(a.identity or '') and budget>0 then tyres(a); budget=budget-1 end
 end end
 tick(4,at)
 return true
end
function M.zones(track)
 if type(track)~='string' or #track>128 or not track:match('^[%w_%-]+$') then return nil,'track' end
 if not ac.FolderID or ac.FolderID.ScriptOrigin==nil then return nil,'path' end
 local ok,root=pcall(ac.getFolder,ac.FolderID.ScriptOrigin)
 if not ok or type(root)~='string' or #root==0 then return nil,'path' end
 local readOK,data=pcall(ac.readDataFile,root..'/tracks/'..track..'.lua')
 -- Fichier absent : CSP rend une chaîne vide ; ce n'est pas une erreur de syntaxe.
 if readOK and data=='' then return nil,'absent' end
 if not readOK or type(data)~='string' or #data>K.maxZoneBytes then return nil,'read' end
 return data
end
-- Dossiers de content/cars (base des voitures), noms sûrs seulement ; liste vide si l'API est absente.
-- Chaîne JSON qui suit la première clé "name" : guillemets et barres échappés, \uXXXX converti en UTF-8 ; nil si elle
-- est trop longue, mal formée ou contient une demi-paire UTF-16.
local jsonEscapes={b=' ',f=' ',n=' ',r=' ',t=' '}
local function utf8Char(code)
 if code<0x80 then return string.char(code) end
 if code<0x800 then return string.char(0xC0+math.floor(code/64),0x80+code%64) end
 return string.char(0xE0+math.floor(code/4096),0x80+math.floor(code/64)%64,0x80+code%64)
end
local function jsonName(data)
 local _,i=data:find('"name"%s*:%s*"')
 if not i then return nil end
 local out,n={},0; i=i+1
 while i<=#data and n<=K.carNameMax do
  local c=data:sub(i,i)
  if c=='"' then return table.concat(out) end
  if c=='\\' then
   i=i+1; local e=data:sub(i,i)
   if e=='u' then
    local code=tonumber(data:sub(i+1,i+4),16)
    if not code or #data:sub(i+1,i+4)<4 or code>=0xD800 and code<=0xDFFF then return nil end
    c=utf8Char(code); i=i+4
   else c=jsonEscapes[e] or e end
  end
  n=n+1; out[n]=c; i=i+1
 end
 return nil
end
-- Nom d'une voiture tel que Content Manager l'affiche (ui/ui_car.json), sinon le nom de son dossier.
local function carName(root,folder)
 if type(io.load)~='function' then return folder end
 local ok,data=pcall(io.load,root..'/'..folder..'/ui/ui_car.json')
 local name=ok and type(data)=='string' and jsonName(data)
 if name and name:find('%S') and not name:find('%c') then return name end
 return folder
end
-- Voitures installées (content/cars) : dossier, nom affiché et clé de recherche, triées par nom affiché. Beta 1.39 :
-- lues par étapes (347 dossiers lus d'un coup figeaient la fenêtre 2,2 s en jeu) : dossiers listés au premier pas, puis
-- au plus K.carReadMax noms affichés par pas, et pas au-delà de K.carReadBudget s lues par clock(arg) (au moins un ;
-- sans horloge, le nombre seul) ; triées à la fin.
function M.carLoader() return {folders={},list={},read=0,started=false,done=false,root=''} end
local function byName(a,b) return a.sort<b.sort or a.sort==b.sort and a.id<b.id end
function M.carStep(loader,clock,arg)
 if loader.done then return true end
 local ok=pcall(function()
  local folders=loader.folders
  if not loader.started then
   loader.started=true
   if not io or type(io.scanDir)~='function' or not ac.getFolder or not ac.FolderID or not ac.FolderID.ContentCars then loader.done=true; return end
   local root=ac.getFolder(ac.FolderID.ContentCars)
   if type(root)~='string' then loader.done=true; return end
   loader.root=root
   io.scanDir(root,'*',function(name,attributes)
    -- Attributs : structure FFI de CSP, lue directement (pas une table Lua).
    if type(name)=='string' and attributes~=nil and attributes.isDirectory==true and #folders<K.maxCarList and name:match('^[%w_%-%.]+$') then folders[#folders+1]=name end
   end)
   return
  end
  local started=clock and clock(arg); local list=loader.list
  for _=1,K.carReadMax do
   local i=loader.read+1; local folder=folders[i]
   if not folder then break end
   local name=carName(loader.root,folder)
   list[i]={id=folder,name=name,key=(name..' '..folder):lower(),sort=name:lower()}
   loader.read=i
   local now=started and clock(arg)
   if now and now-started>=K.carReadBudget then break end
  end
  if loader.read>=#folders then table.sort(list,byName); loader.done=true end
 end)
 if not ok then loader.list={}; loader.done=true end
 return loader.done
end
local function menuVisible() local sim=simGet(); return sim.isPaused==true or sim.isInMainMenu==true end
function M.menu()
 local ok,visible=pcall(menuVisible)
 return ok and visible==true
end
M.stripName=stripName
return M
