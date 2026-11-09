local U=require('src/util')
local K=require('src/config').K
local M={}
local function hexByte(c) return string.format('%02x',string.byte(c)) end
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
 local size=ac.getCar(a.index).aabbSize
 a.length=size and U.finite(size.z) and size.z>=K.minLength and size.z<=K.maxLength and size.z or K.length
 a.width=size and U.finite(size.x) and size.x>=K.minWidth and size.x<=K.maxWidth and size.x or K.width
end
local function damageRead(a,raw)
 a.damageBody,a.damageSuspension,a.engineLife,a.damageGearbox=damageValues(raw); a.repairingNative=raw.isRepairing==true
end
-- Dégâts du joueur (Beta 1.32, drapeau noir à disque orange) : rangés à part (ceux des IA ne sont lus qu'à leur
-- emplacement), avec le taux de dégâts mécaniques de la session (0 : dégâts désactivés).
local function playerDamage(s,a)
 local raw=ac.getCar(a.index)
 s.playerBody,s.playerSuspension,s.playerEngine,s.playerGearbox=damageValues(raw)
 local blown=false; local wheels=raw.wheels
 if wheels then for w=0,3 do local wheel=wheels[w]; if wheel and wheel.isBlown==true then blown=true end end end
 s.playerBlown=blown; s.damageRate=U.number(ac.getSim().mechanicalDamageRate,0,1000,1); s.playerDamageSlot=a.slot
end
function M.new()
 local s={cars={},count=0,player=0,errors=0,invalid=0,track='',trackName='',patch='',conflict='',metaAt=-1,session=-1,
  online=true,replay=false,paused=false,menu=false,started=false,finished=false,length=0,time=0,startIn=0,left=0,wet=0,rain=0,water=0,type=1,stamp=-1,configType=0,configTrackDay=false,configSession=-1,
  flag=0,fuelRate=1,pitWindowStart=0,pitWindowEnd=0,simTime=0,sessionLaps=0,sessionMinutes=0,timedRace=false,leaderLaps=0,
  playerDamageSlot=0,playerDamageAt=-1,playerBody=0,playerSuspension=0,playerEngine=1000,playerGearbox=0,playerBlown=false,damageRate=1}
 for i=1,K.maxCars do s.cars[i]={slot=i,index=i-1,valid=false,control=false,player=false,pit=false,offtrack=false,
 x=0,y=0,z=0,lx=0,lz=1,speed=0,kmh=0,yaw=0,corner=1,spline=0,splineValid=false,lap=0,lapValid=false,
 length=K.length,width=K.width,brake=0,gas=0,aiLevel=1,aiAggression=0.5,stopped=0,slip=0,leftWidth=0,rightWidth=0,
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
local function readCar(a,index,dt,lane)
 a.valid=false; a.control=false; a.player=false; a.teleport=false
 local raw=ac.getCar(index)
 -- Champs vectoriels lus une fois : chaque lecture d'un champ structuré d'une cdata crée une référence (déchet).
 local position,look=raw and raw.position,raw and raw.look
 if not raw or not vector(position) or not vector(look) or not U.finite(raw.speedKmh) then return false end
 local norm=math.sqrt(look.x*look.x+look.z*look.z)
 if norm<0.1 or raw.speedKmh<0 or raw.speedKmh>1000 then return false end
 local x,z=position.x,position.z
 a.teleport=a.initialized and (x-a.previousX)^2+(z-a.previousZ)^2>K.teleport^2
 a.previousX=x; a.previousZ=z; a.x=x; a.z=z; a.y=U.number(position.y,-10000,10000,0)
 local lx,lz=look.x/norm,look.z/norm; local yaw=math.atan2(lx,lz)
 local angular=a.initialized and U.wrap(yaw-a.yaw)/math.max(0.001,dt) or 0
 a.yawRate=U.ema(a.yawRate or 0,angular,dt,K.yawTau); a.yaw=yaw; a.lx=lx; a.lz=lz
 local side=raw.side
 a.sideDot=side and U.finite(side.x) and U.finite(side.z) and (-side.x*lz+side.z*lx) or 0
 a.kmh=raw.speedKmh; a.speed=U.ema(a.speed,a.kmh/3.6,dt,K.speedTau)
 if not a.initialized or a.teleport then a.speed=a.kmh/3.6; a.yawRate=0 end
 a.initialized=true; a.valid=raw.isConnected~=false and raw.isActive~=false
 a.player=raw.isUserControlled==true
 a.control=raw.isAIControlled==true and not a.player and not raw.isRemote and raw.physicsAvailable~=false
 a.pit=raw.isInPit==true or raw.isInPitlane==true
 a.inPitBox=raw.isInPit==true
 a.compoundIndex=U.finite(raw.compoundIndex) and raw.compoundIndex>=0 and math.floor(raw.compoundIndex) or nil
 a.currentTyreIsDry=a.compoundIndex~=nil and a.dryCompounds~=nil and a.dryCompounds[a.compoundIndex]==true
 a.nativeRainTyres=raw.isAIUsingRainTyres==true
 -- DRS natif d'AC (zones du circuit, règle de la seconde) : seulement lu, pour le bip et le panneau du joueur.
 a.drsPresent=raw.drsPresent==true; a.drsAvailable=raw.drsAvailable==true; a.drsActive=raw.drsActive==true
 -- Pénalité native d'AC en cours (renseignée pour la voiture du joueur seulement) : reprise par le panneau.
 a.penaltyType=a.player and math.floor(U.number(raw.currentPenaltyType,0,16,0)) or 0
 a.penaltyParam=a.player and math.floor(U.number(raw.currentPenaltyParameter,-1,100000,0)) or 0
 -- Carburant des IA (litres ; -1 inconnu) et estimation d'AC par tour (0 tant qu'elle n'est pas disponible).
 if a.control then a.fuel=U.number(raw.fuel,0,10000,-1); a.maxFuel=U.number(raw.maxFuel,0,10000,-1); a.fuelPerLap=U.number(raw.fuelPerLap,0,1000,0)
 else a.fuel=-1; a.maxFuel=-1; a.fuelPerLap=0 end
 -- Dégâts lus seulement à l'emplacement ; un champ absent laisse la voiture valide, sans dégât connu.
 -- Beta 1.24 : aussi sur une IA lente ou arrêtée (voiture cassée à évacuer aussitôt).
 -- Beta 1.28 : aussi sur une IA anormalement lente surveillée par le moteur (diagnostic).
 if not (a.control and (a.inPitBox or a.kmh<K.damageReadSpeed or a.watchDamage) and pcall(damageRead,a,raw)) then a.damageBody=0; a.damageSuspension=0; a.engineLife=K.engineLifeNew; a.repairingNative=false; a.damageGearbox=0 end
 a.nativeRainTyresKnown=type(raw.isAIUsingRainTyres)=='boolean'
 a.offtrack=not U.finite(raw.wheelsOutside) or raw.wheelsOutside>2
 a.splineValid=U.finite(raw.splinePosition) and raw.splinePosition>=0 and raw.splinePosition<=1
 a.spline=a.splineValid and raw.splinePosition or 0
 a.lapValid=U.finite(raw.lapCount) and raw.lapCount>=0 and raw.lapCount%1==0
 a.lap=a.lapValid and raw.lapCount or 0
 -- Beta 1.42 : roues hors des limites (0 à 4), validité du tour en cours, secteur et temps du tour (sanctions des IA).
 a.wheelsOut=U.finite(raw.wheelsOutside) and math.max(0,math.min(4,math.floor(raw.wheelsOutside))) or 0
 a.lapNowValid=raw.isLapValid~=false; a.sector=U.finite(raw.currentSector) and math.max(0,math.floor(raw.currentSector)) or 0
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
 a.position=U.finite(raw.racePosition) and raw.racePosition>=1 and math.floor(raw.racePosition) or 0
 local collidedOK,collided=pcall(collidedWith,raw)
 a.collided=collidedOK and U.finite(collided) and collided>=0
 -- Voiture touchée (Beta 1.24) : 0 = décor, sinon numéro de la voiture plus 1, soit sa case dans la liste.
 a.collidedWith=a.collided and math.floor(collided) or -1
 a.highBeams=raw.highBeams==true; a.headlightsActive=raw.headlightsActive==true; a.lowBeams=raw.lowBeams==true
 a.flashingLightsActive=raw.flashingLightsActive==true; a.hornActive=raw.hornActive==true
 a.leftWidth=0; a.rightWidth=0
 if a.splineValid and ac.getTrackAISplineSides then
  local ok,sides=pcall(ac.getTrackAISplineSides,a.spline)
  if ok and sides then a.leftWidth=U.number(sides.x,0,100,0); a.rightWidth=U.number(sides.y,0,100,0) end
 end
 -- Écart à la trajectoire IA (m, repère latéral interne : positif à droite), lu seulement pendant le départ.
 a.splineLat=0; a.splineLatValid=false
 if lane and a.control and a.splineValid then
  local probe=laneProbe()
  if probe and pcall(ac.trackProgressToWorldCoordinateTo,a.spline,probe) and U.finite(probe.x) and U.finite(probe.z) then
   a.splineLat=(x-probe.x)*lz-(z-probe.z)*lx; a.splineLatValid=true
  end
 end
 return a.valid
end
local function simRead(s)
 local r=ac.getSim()
 s.online=r.isOnlineRace==true or r.isAltOnlineRace==true
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
 s.count=math.floor(U.number(r.carsCount,0,K.maxCars,0))
 -- 1.42 SANCTIONS : vitesse limite des stands (excès de vitesse des IA) ; nombre de secteurs (dernier secteur : tour
 -- suivant invalidé aussi), lu une fois par session.
 s.pitsSpeedLimit=U.number(r.pitsSpeedLimit,10,400,K.sanPitLimitDefault)
 if s.sectorsSession~=s.session or s.sectorsLength~=s.length then
  s.sectorsSession=s.session; s.sectorsLength=s.length
  local ok,n=pcall(function() return #r.lapSplits end); s.sectorCount=ok and U.number(n,0,64,0) or 0
 end
end
-- Drapeau, fenêtre d'arrêt et tours du leader (1.3.0), lus à part : un champ indisponible les laisse neutres.
local function raceRead(s)
 local r=ac.getSim()
 s.flag=math.floor(U.number(r.raceFlagType,0,64,0))
 s.pitWindowStart=U.number(r.pitWindowStartTime,0,1e13,0); s.pitWindowEnd=U.number(r.pitWindowEndTime,0,1e13,0)
 s.simTime=U.number(r.time,0,1e13,0); s.leaderLaps=math.floor(U.number(r.leaderLapCount,0,100000,0))
 -- Consommation de carburant de la session (0 : coupée, rien à gérer) ; champ absent : comptée.
 s.fuelRate=U.number(r.fuelConsumptionRate,0,100,1)
end
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
 local raw=ac.getCar(a.index)
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
 a.tyresID=a.identity or ''; a.tyresKnown=false; a.dryCompound=-1; a.wetCompound=-1; a.interCompound=-1; a.dryCompounds={}; a.dryList={}; a.tyreNames={}; a.tyreLongNames={}; a.dryPrimary={}
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
   if short:upper()=='I' or short:upper()=='INT' or name:find('intermediate',1,true) or name:find('intermedia',1,true) then a.interCompound=index
   elseif short:upper()=='W' or name:find('wet',1,true) or name:find('rain',1,true) or name:find('pluie',1,true) then a.wetCompound=index
   else
    a.dryCompounds[index]=true; a.dryList[#a.dryList+1]=index; if a.dryCompound<0 or index==a.compoundIndex then a.dryCompound=index end
    if not primary[short:upper()] then primary[short:upper()]=true; a.dryPrimary[#a.dryPrimary+1]=index end
   end
  end
 end
 a.tyresKnown=any
 a.currentTyreIsDry=a.compoundIndex~=nil and a.dryCompounds[a.compoundIndex]==true
end
function M.read(s,dt,now,light)
 local ok=pcall(simRead,s)
 if not ok then s.online=true; s.count=0; s.errors=math.min(K.counterMax,s.errors+1); return false end
 if not pcall(raceRead,s) then s.flag=0; s.pitWindowStart=0; s.pitWindowEnd=0; s.errors=math.min(K.counterMax,s.errors+1) end
 -- Beta 1.52 : première lecture toujours complète (place du joueur connue avant toute lecture légère).
 if light and not s.playerSlot then light=false end
 if not light and s.lightLast then s.metaAt=-1; s.configSession=-1 end
 s.lightLast=light==true
 s.player=0
 if not light then for i=1,s.count do
  local a=s.cars[i]; local good,result=pcall(readCar,a,i-1,dt,s.laneWanted)
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
 if not light and s.player>0 and now>=s.playerDamageAt then
  s.playerDamageAt=now+K.playerDamagePeriod
  if not pcall(playerDamage,s,s.cars[s.player]) then s.playerDamageSlot=0 end
 end
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
  -- Beta 1.39 : nom affiché du circuit (en-tête de la fenêtre) ; l'identifiant reste pour le diagnostic.
  local nameOK,name=pcall(ac.getTrackName); if nameOK and type(name)=='string' then s.trackName=name:sub(1,K.metadataLength) end
  if not light then for i=1,s.count do
   local a=s.cars[i]
   local oldID,oldName=a.id,a.name
   local idOK,id=pcall(ac.getCarID,a.index); if idOK and type(id)=='string' then a.id=id:sub(1,K.metadataLength) end
   local nameOK,name=pcall(ac.getDriverName,a.index); if nameOK and type(name)=='string' then a.name=name:sub(1,K.metadataLength) end
   if a.id~=oldID or a.name~=oldName then a.identity=(a.id..'\0'..a.name):gsub('.',hexByte) end
   if not pcall(sizeRead,a) then a.length=K.length; a.width=K.width end
   -- Livrée (dossier du skin) : une livrée « safety » désigne la voiture de sécurité parmi celles du modèle.
   local skinOK,skin=pcall(ac.getCarSkinID,a.index)
   if a.valid and a.control and not pcall(wearRead,a) then a.wearKnown=false end
   if skinOK and type(skin)=='string' and (skin~=a.skin or not a.skinKnown) then a.skin=skin:sub(1,K.metadataLength); a.skinKnown=true; a.skinSafety=a.skin:lower():find(K.safetySkinPattern,1,true)~=nil end
  end end
  s.conflict=''
  if ac.getAppWindows then
   local appsOK,apps=pcall(ac.getAppWindows)
   if appsOK and type(apps)=='table' then
    for j=1,math.min(#apps,K.maxAppWindows) do
     local good,name=pcall(conflictingApp,apps[j])
     if good and name then s.conflict=name; break end
    end
   end
  end
 end
 local budget=K.tyreCatalogBudget
 if not light then for i=1,s.count do
  local a=s.cars[i]
  -- Beta 1.49 : le joueur aussi (noms de ses composés : arrêt obligatoire F1, stratégie des stands).
  if a.valid and (a.control or a.player) and a.tyresID~=(a.identity or '') and budget>0 then tyres(a); budget=budget-1 end
 end end
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
local function menuVisible() local sim=ac.getSim(); return sim.isPaused==true or sim.isInMainMenu==true end
function M.menu()
 local ok,visible=pcall(menuVisible)
 return ok and visible==true
end
return M
