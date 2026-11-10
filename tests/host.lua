-- Intégration complète : même fichier d'entrée, callbacks et stockage que CSP.
local U=require('src/util')
local M={}
-- options.rightHanded : repère direct d'AC (+X à gauche quand la voiture regarde +Z) ; offset SDK positif vers la droite.
function M.create(native110,options)
 local right=options and options.rightHanded==true
 local h={offsets={},drsBlocks={},drsOpen={},mistakes={},releasing=false,calls=0,carReads=0,offsetCalls=0,storeWrites=0,sim={carsCount=4,raceSessionType=1,currentSessionIndex=0,trackLengthM=10000,
  currentSessionTime=100000,timeToSessionStart=0,sessionTimeLeft=600000,isSessionStarted=true,isSessionFinished=false,
  isOnlineRace=false,isAltOnlineRace=false,isReplayActive=false,isReplayOnlyMode=false,isPaused=false,isInMainMenu=false,gameTime=1,rainWetness=0,leaderLapCount=0},
  cars={},values={},storage={},releases={},sessions={},controls={},clicked='',clip='',windows={},sameLines=0,extraGrip=0,grips={},tyreCatalog={},rainHints={},pitRequests={},nativeRainSupport=false,stops={},awakes={},positions={},velocities={},hudHidden={},transparent={},messageListeners={},blocked=0,messages={},flag=0,nativeFlag=0,flagOverrides=0,parked={},teleports=0,files={},
  throttleLimits={},throttleWrites=0,tyreKmWrites={},sliderLabels={},sliderEdits={},checkboxLabels={},checkboxValues={},buttons={},accented={},pitRequested={},startDelays={},startDelayWrites=0,bodyRepairs={},suspensionRepairs={},engineRepairs={},penalties={},penaltyKinds={},badgeTexts={},wrappedPanel={},sounds={},played=0,disposed=0,draws=0,fontDepth=0,panelTexts={},wrappedTexts={},panelColors={},styleDepth=0,styleMax=0,hoverAll=false,tooltips={},missingTips={},pendingWidget=nil,pendingTipped=true,inputEdits={},comboEdits={},comboValues={},windowOpen={},speedLimits={},laneWrites=0,laneBase={},fuelRequests={},fuelSets={},width=420,cursor=0,lastRight=0,categoryRows=1,overflow=false,tabHeightMax=0,fontScale=1,rendered=0,accessCalls=0}
 for i=0,3 do
  h.cars[i]={index=i,position={x=0,y=0,z=i==0 and -1000 or (i-1)*120},look={x=0,z=1},side={x=right and 1 or -1,z=0},velocity={x=0,z=30},speedKmh=108,
   isConnected=true,isActive=true,isAIControlled=i~=0,isUserControlled=i==0,isRemote=false,physicsAvailable=true,
   isInPit=false,isInPitlane=false,wheelsOutside=0,splinePosition=i==0 and 0.9 or (i-1)*0.012,lapCount=i==0 and 0 or 1,
   aabbSize={x=1.85,z=4.4},collidedWith=-1,brake=0,gas=1,aiLevel=0.9,aiAggression=0.45,compoundIndex=0,isAIUsingRainTyres=false,highBeams=false,headlightsActive=false,lowBeams=false,flashingLightsActive=false,hornActive=false}
  h.tyreCatalog[i]={{short='S',name='Slick Soft'}}
  local raw={brake=0}; local car=i
  -- Aux stands, la seule écriture de frein admise est son relâchement.
  h.controls[i]=setmetatable({},{__index=raw,__newindex=function(_,key,value)
   if key=='brake' and not h.releasing and (h.cars[car].isInPit or h.cars[car].isInPitlane) then assert(value==0,'brake override in pits') end
   raw[key]=value
  end})
 end
 -- Pendant le déchargement seulement (h.releasing), restitution admise en pause, en replay et aux stands.
 -- Beta 1.58 : aux stands, seules les valeurs rendues à AC sont admises (restore) : décalage ramené vers 0, vitesse
 -- illimitée, niveau et agressivité d'avant la première écriture de l'app, prudence 1, grip de base, accélérateur 1.
 local function verify(index,value,restore)
  assert(U.finite(value)); assert(index~=0 and h.cars[index].isAIControlled and not h.cars[index].isUserControlled)
  local pits=h.cars[index].isInPit or h.cars[index].isInPitlane
  assert(h.releasing or restore or not pits,'command written in the pits')
  if pits and restore and not h.releasing then h.laneWrites=h.laneWrites+1 end
  assert(not h.sim.isOnlineRace and not h.sim.isAltOnlineRace and (h.releasing or not h.sim.isReplayActive and not h.sim.isPaused))
  h.calls=h.calls+1
 end
 ac.getCar=function(index) h.carReads=h.carReads+1; return h.cars[index] end
 ac.getSim=function() return h.sim end
 ac.getSession=function() return h.session end
 -- h.raceIni : sessions déclarées {SESSION_n={NAME=...,TYPE=...}} ; sinon une session de Journée circuit
 -- Content Manager (« Track Day »), de type h.configType ou raceSessionType.
 ac.CSPModuleID={GUI='gui'}
 -- Fenêtres d'apps : taille de la fenêtre de réglages, redimensionnements comptés.
 h.mainWindow={x=1000,y=780}; h.resizes=0
 ac.accessAppWindow=function(name) if name~='IMGUI_LUA_AdvancedIA_main' then return nil end
  return {size=function() return {x=h.mainWindow.x,y=h.mainWindow.y} end,resize=function(_,v) h.resizes=h.resizes+1; h.mainWindow={x=v.x,y=v.y} end} end
 -- Options de gui.ini telles que CSP les applique (Beta 1.40 : aussi HIDE_SYSTEM_MESSAGES) ; h.guiWatchers : relecture.
 ac.INIConfig={cspModule=function(id) assert(id=='gui'); return {get=function(_,section,key,fallback)
  assert(section=='HIDE' and (key=='HIDE_RACE_FLAGS' or key=='HIDE_SYSTEM_MESSAGES'))
  local value; if key=='HIDE_RACE_FLAGS' then value=h.hideRaceFlags else value=h.hideSystemMessages end
  if value==nil then return fallback end return value end} end,
  raceConfig=function() return {get=function(_,section,key,fallback)
  if h.raceIni then local entry=h.raceIni[section]; return entry and entry[key] or fallback end
  -- Beta 1.19 : nom de Content Manager selon le type (« Track Day » pour les essais par défaut, comme une journée circuit).
  if key=='NAME' then return h.sessionName or ({[2]='Qualifying',[3]='Race',[4]='Hotlap'})[h.configType or h.sim.raceSessionType] or 'Track Day' end
  return h.configType or h.sim.raceSessionType or fallback end} end}
 ac.setWindowOpen=function(id,opened) h.windowOpen[id]=opened end; ac.isWindowOpen=function(id) return h.windowOpen[id]==true end
 ac.getTrackID=function() return 'test' end
 ac.getTrackName=function() return 'Test Raceway' end
 ac.getTrackLayout=function() return h.trackLayout or '' end
 ac.getCarID=function(index) return 'model_'..index end
 ac.getDriverName=function(index) return 'Driver '..index end
 ac.getTyresName=function(index,compound) local t=h.tyreCatalog[index][compound+1]; return t and t.short or nil end
 ac.getTyresLongName=function(index,compound) local t=h.tyreCatalog[index][compound+1]; return t and t.name or nil end
 ac.getTrackAISplineSides=function() return {x=6,y=6} end
 -- Trajectoire IA de l'hôte : axe X = 0, progression le long de Z.
 ac.trackProgressToWorldCoordinateTo=function(v,r) r.x=0; r.y=0; r.z=v*h.sim.trackLengthM end
 rawset(_G,'vec3',function(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end)
 rawset(_G,'vec4',function(x,y,z,w) return {x=x or 0,y=y or 0,z=z or 0,w=w or 0} end)
 ac.getAppWindows=function() return h.windows end
 ac.FolderID={ScriptOrigin=1,Logs=7,ContentCars=13,ContentTracks=15,ExtCfgSys=17,ExtCfgUser=18,ExtCfgState=25}; ac.getFolder=function(id) return id==7 and 'logs' or id==13 and 'cars' or id==15 and 'tracks' or id==17 and 'cfgsys' or id==18 and 'cfgext' or id==25 and 'cfgstate' or 'local' end
 h.guiWatchers={}
 ac.onCSPConfigChanged=function(id,fn) assert(id=='gui' and type(fn)=='function'); h.guiWatchers[#h.guiWatchers+1]=fn
  return function() for k,f in ipairs(h.guiWatchers) do if f==fn then table.remove(h.guiWatchers,k) end end end end
 io.scanDir=function(root,mask,callback)
  assert(type(root)=='string' and mask=='*' and type(callback)=='function')
  local model=root:match('^cars/(.+)/skins$')
  if model then for _,name in ipairs((h.skinFolders or {})[model] or {}) do callback(name,{isDirectory=true}) end; return end
  assert(root=='cars'); for _,name in ipairs(h.carFolders or {}) do callback(name,{isDirectory=true}) end
 end
 ac.getCarSkinID=function(index) return (h.skins or {})[index] or 'default' end
 ac.findNodes=function(query) assert(type(query)=='string'); return {applySkin=function(self,skin) assert(type(skin)=='string'); h.appliedSkins=h.appliedSkins or {}; h.appliedSkins[query]=skin; return self end} end
 io.load=function(path) assert(type(path)=='string'); return h.files[path] end
 -- Réglage d'AI flood de CSP (Beta 1.26) : seule écriture permise hors du dossier des journaux.
 -- Beta 1.40 : aussi gui.ini (options de CSP) et le fichier d'état de l'app (cfg/extension/state) ; h.guiReadonly,
 -- h.stateReadonly : écriture refusée.
 -- Fichier d'état dans le dossier d'état du moment (aussi celui de l'imitation de la mise à jour, tests/updatefake.lua).
 local gui='cfgext\\gui.ini'
 local function isState(path) local root=ac.getFolder(ac.FolderID.ExtCfgState); return root~=nil and (path==root..'\\ACAdvancedIA-cspgui.ini' or path==root..'\\ACAdvancedIA-cspgui.ini.bak') end
 io.save=function(path,data,ensure)
  assert((path=='cfgext\\new_behaviour.ini' or path==gui or isState(path)) and type(data)=='string' and ensure==true,'write outside the CSP user config: '..tostring(path))
  if path==gui and h.guiReadonly or isState(path) and h.stateReadonly then return false end
  if ensure and h.files[path]~=nil then h.files[path..'.bak']=h.files[path] end; h.files[path]=data
  if path==gui then h.guiWrites=(h.guiWrites or 0)+1 elseif isState(path) then h.stateWrites=(h.stateWrites or 0)+1 else h.cfgWrites=(h.cfgWrites or 0)+1 end
  return true
 end
 -- Comme io.replaceFile de CSP : l'ancien contenu reste en .bak ; seul ce reste peut être effacé (Beta 1.38).
 io.deleteFile=function(path)
  assert(path=='cfgext\\new_behaviour.ini.bak' or path==gui or path==gui..'.bak' or isState(path),'delete outside the CSP user config: '..tostring(path))
  h.files[path]=nil
  if path=='cfgext\\new_behaviour.ini.bak' then h.bakDeleted=(h.bakDeleted or 0)+1 end
  return true
 end
 -- Journal de session : fichiers en mémoire, seulement dans le dossier des journaux.
 io.open=function(path,mode)
  assert(type(path)=='string' and path:sub(1,5)=='logs/','journal outside the logs folder: '..tostring(path))
  if mode=='w' then h.files[path]='' elseif mode=='a' then h.files[path]=h.files[path] or '' else return nil end
  return {write=function(_,text) h.files[path]=h.files[path]..text end,close=function() end}
 end
 io.fileExists=function(path) return h.files[path]~=nil end
 io.move=function(from,to) h.files[to]=h.files[from]; h.files[from]=nil; return true end
 ac.readDataFile=function(path) assert(path=='local/tracks/test.lua'); return 'return {zones={}}' end
 -- Comme CSP : une clé absente du stockage vaut la valeur du gabarit.
 ac.storage=function(layout,prefix)
  if not h.storage[prefix] then h.storage[prefix]=layout
  elseif h.storage[prefix]~=layout and getmetatable(h.storage[prefix])==nil then setmetatable(h.storage[prefix],{__index=layout}) end
  return h.storage[prefix]
 end
 ac.store=function(key,value) h.values[key]=value; h.storeWrites=h.storeWrites+1 end
 ac.load=function(key) return h.values[key] end
 ac.setClipboardText=function(text) h.clip=text end
 ac.onRelease=function(fn) h.releases[fn]=true; return function() h.releases[fn]=nil end end
 ac.onSessionStart=function(fn) h.sessions[fn]=true; return function() h.sessions[fn]=nil end end
 ac.overrideCarControls=function(index)
  assert(index~=0 and h.cars[index].isAIControlled and not h.cars[index].isUserControlled)
  assert(not h.sim.isOnlineRace and not h.sim.isAltOnlineRace and (h.releasing or not h.sim.isReplayActive and not h.sim.isPaused))
  h.calls=h.calls+1; return h.controls[index]
 end
 physics.allowed=function() h.accessCalls=h.accessCalls+1; return true end
 local function base(index,key,value) local b=h.laneBase[index] or {}; h.laneBase[index]=b; if b[key]==nil then b[key]=value end; return b[key] end
 physics.setAILevel=function(index,value) local b=base(index,'level',h.cars[index].aiLevel); verify(index,value,math.abs(value-b)<1e-9); h.cars[index].aiLevel=math.min(native110 and not h.clampLevel and 2 or 1,value) end
 physics.setAIAggression=function(index,value) local b=base(index,'aggression',h.cars[index].aiAggression); verify(index,value,math.abs(value-b)<1e-9); h.cars[index].aiAggression=value end
 physics.setAICaution=function(index,value) verify(index,value,value==1) end
 physics.setExtraAIGrip=function(index,value) verify(index,value,math.abs(value-1.2)<1e-9); h.extraGrip=value; h.grips[index]=value end
 physics.setAIBrakeMistake=function(index,time) assert(type(index)=='number' and type(time)=='number' and time>0); h.mistakes[#h.mistakes+1]={index=index,kind='brake',time=time} end
 physics.setAITractionMistake=function(index,time,severity) assert(type(index)=='number' and time>0 and severity>0); h.mistakes[#h.mistakes+1]={index=index,kind='traction',time=time,severity=severity} end
 physics.setCarDRS=function(index,active) assert(type(index)=='number' and type(active)=='boolean'); h.drsOpen[index]=active end
 physics.allowCarDRS=function(index,disable) assert(type(index)=='number' and type(disable)=='boolean'); h.drsBlocks[index]=disable end
 physics.setAITopSpeed=function(index,value) verify(index,value,value>=1e9); h.speedLimits[index]=value end
 -- Beta 1.42 : limite d'accélérateur et distance virtuelle d'un pneu.
 physics.setAIThrottleLimit=function(index,value) verify(index,value,value==1); assert(value>=0 and value<=1); h.throttleLimits[index]=value; h.throttleWrites=h.throttleWrites+1 end
 physics.setTyresVirtualKM=function(index,wheel,km) verify(index,km); assert(wheel>=0 and wheel<=3); h.tyreKmWrites[#h.tyreKmWrites+1]={index=index,wheel=wheel,km=km} end
 local function weatherVerify(index)
  assert(index~=0 and h.cars[index].isAIControlled and not h.cars[index].isUserControlled)
  assert(not h.sim.isOnlineRace and not h.sim.isAltOnlineRace and (h.releasing or not h.sim.isReplayActive and not h.sim.isPaused))
  h.calls=h.calls+1
 end
 physics.setCarPenalty=function(kind,seconds)
  h.penaltyKinds[#h.penaltyKinds+1]=kind
  if kind==ac.PenaltyType.BlackFlag then assert(seconds==-1)
  elseif kind==ac.PenaltyType.ReleaseBlackFlag then h.blackFlagReleases=(h.blackFlagReleases or 0)+1 else assert(kind==ac.PenaltyType.SlowDown and seconds>=1); h.penalties[#h.penalties+1]=seconds end
 end
 ac.dirname=function() return 'apps/lua/AdvancedIA' end
 ac.AudioEvent={fromFile=function(params,reverb)
  assert(params.use3D==false and params.loop==false and reverb==false); h.sounds[#h.sounds+1]=params.filename
  return {volume=1,cameraInteriorMultiplier=0.25,setVolumeChannel=function(self,channel) h.beepChannel=channel; return self end,
   start=function(self) h.played=h.played+1; h.beepVolume=self.volume; h.beepInterior=self.cameraInteriorMultiplier; return self end,dispose=function() h.disposed=h.disposed+1 end}
 end}
 ac.AudioChannel={Main='main'}
 ac.PenaltyType={None=0,MandatoryPits=1,TeleportToPits=2,SlowDown=3,BlackFlag=4,ReleaseBlackFlag=5}
 physics.setAIRainTyres=function(index,value) weatherVerify(index); h.rainHints[index]=value; if h.nativeRainSupport then h.cars[index].isAIUsingRainTyres=value end end
 physics.setAIPitStopRequest=function(index,value) weatherVerify(index); h.pitRequests[index]=value; if value then h.pitRequested[index]=true end end
 -- Arrêt forcé : admis hors piste (voiture accidentée), jamais au-delà d'une impulsion courte.
 physics.setAIStopCounter=function(index,value) weatherVerify(index); assert(value>=0 and value<=2,'stop pulse'); h.stops[index]=value end
 -- Drapeau du joueur : global, reflété par raceFlagType comme dans CSP.
 physics.overrideRacingFlag=function(flag) assert(not h.sim.isOnlineRace and (h.releasing or not h.sim.isReplayActive and not h.sim.isPaused)); h.flagOverrides=h.flagOverrides+1
  -- Beta 1.47 : h.stickyFlag restitutions ignorées (CSP qui garde la valeur imposée, Monza 17:26).
  if flag==0 and (h.stickyFlag or 0)>0 then h.stickyFlag=h.stickyFlag-1; h.flag=flag; return end
  h.sim.raceFlagType=flag==0 and h.nativeFlag or flag; h.flag=flag end
 -- Comme CSP : les écouteurs reçoivent aussi les messages de l'app ; h.blockSwallows : un masquage les leur retire.
 ac.setMessage=function(title,text,kind,time)
  h.messages[#h.messages+1]=title..' | '..text
  -- Beta 1.40 : h.hideSwallows : l'option de CSP « Hide system messages » appliquée les leur retire aussi.
  if not (h.blockSwallows and h.blocked>0) and not (h.hideSwallows and h.hideSystemMessages) then for _,fn in ipairs(h.messageListeners) do fn(title,text,kind,time or 5) end end
 end
 -- Voiture garée sans pilote et retour au stand : IA seulement, jamais en ligne.
 physics.setAINoInput=function(index,value) weatherVerify(index); h.parked[index]=value end
 physics.teleportCarTo=function(index,spawn) weatherVerify(index); assert(spawn=='PIT'); h.teleports=h.teleports+1; h.cars[index].isInPit=true; h.cars[index].isInPitlane=true; h.cars[index].speedKmh=0; h.cars[index].velocity={x=0,z=0} end
 -- Répartition sur le circuit (Beta 1.26) : trajectoire de l'IA le long de z, vecteurs minimaux ; IA seulement.
 local V3={}; V3.__index=V3
 local function v3(x,y,z) return setmetatable({x=x,y=y,z=z},V3) end
 V3.__sub=function(a,b) return v3(a.x-b.x,a.y-b.y,a.z-b.z) end
 V3.__mul=function(a,k) return v3(a.x*k,a.y*k,a.z*k) end
 function V3:normalize() local l=math.sqrt(self.x^2+self.y^2+self.z^2); if l>0 then self.x=self.x/l; self.y=self.y/l; self.z=self.z/l end; return self end
 rawset(_G,'vec3',v3)
 ac.trackProgressToWorldCoordinate=function(v) assert(type(v)=='number' and v>=0 and v<1); return v3(0,0,v*h.sim.trackLengthM) end
 physics.setCarPosition=function(index,pos,dir)
  assert(index~=0 and h.cars[index].isAIControlled and getmetatable(pos)==V3 and dir==nil,'aligned by CSP along the AI spline')
  h.positions[index]={pos=pos,dir=dir}; h.positionWrites=(h.positionWrites or 0)+1
  if not h.positionsIgnored then local car=h.cars[index]; car.isInPit=false; car.isInPitlane=false; car.splinePosition=pos.z/h.sim.trackLengthM; car.position={x=0,y=0,z=pos.z}; car.look={x=0,z=1}; car.velocity={x=0,y=0,z=0}; car.speedKmh=0 end
 end
 physics.setCarVelocity=function(index,velocity) assert(index~=0 and h.cars[index].isAIControlled and getmetatable(velocity)==V3); h.velocities[index]=velocity; h.cars[index].speedKmh=velocity.z*3.6; h.cars[index].velocity={x=0,y=0,z=velocity.z} end
 -- Carburant des IA : demande pour le prochain arrêt (math.huge : rendu à AC), plein avant le départ seulement.
 physics.overrideAIRequestedFuel=function(index,fuel,laps) weatherVerify(index); assert(index~=0 and h.cars[index].isAIControlled and (fuel==math.huge or fuel>=0 and fuel<=1000) and (laps==nil or laps>=1)); h.calls=h.calls+1; h.fuelRequests[index]={fuel=fuel,laps=laps} end
 -- Beta 1.22 : attente native à l'emplacement (IA seulement ; 0, annulation, partout) ; Beta 1.20 : réparations d'une IA à son emplacement.
 physics.setAITimeToStart=function(index,time) weatherVerify(index); assert(index~=0 and h.cars[index].isAIControlled and time>=0 and time<1000 and (time==0 or h.cars[index].isInPit)); h.startDelays[index]=time; h.startDelayWrites=h.startDelayWrites+1 end
 physics.awakeCar=function(index) assert(h.cars[index] and h.cars[index].isAIControlled); h.awakes[index]=(h.awakes[index] or 0)+1 end
 local function repairable(index) weatherVerify(index); assert(index~=0 and h.cars[index].isAIControlled and h.cars[index].isInPit,'repair in the pit box only') end
 physics.setCarBodyDamage=function(index,damage) repairable(index); assert(damage~=nil); h.bodyRepairs[index]=(h.bodyRepairs[index] or 0)+1; h.cars[index].damage={[0]=0,[1]=0,[2]=0,[3]=0,[4]=0} end
 physics.setSuspensionDamage=function(index,wheels,damage) repairable(index); assert(wheels==nil and damage==0); h.suspensionRepairs[index]=(h.suspensionRepairs[index] or 0)+1; h.cars[index].suspensionDamage={[0]=0,[1]=0,[2]=0,[3]=0} end
 physics.setCarEngineLife=function(index,life) repairable(index); assert(life==1000); h.engineRepairs[index]=(h.engineRepairs[index] or 0)+1; h.cars[index].engineLifeLeft=1000 end
 physics.setCarFuel=function(index,fuel) weatherVerify(index); assert(index~=0 and not h.sim.isSessionStarted and fuel>=0); h.calls=h.calls+1; h.fuelSets[index]=fuel; h.cars[index].fuel=fuel end
 physics.setAITyres=function(index,compound)
  -- Dans la voie des stands (même en roulant), ou à l'arrêt sur la grille avant le départ ou au début de la session.
  weatherVerify(index)
  assert(h.cars[index].isInPit or h.cars[index].isInPitlane or (not h.sim.isSessionStarted or h.sim.currentSessionTime<15000) and h.cars[index].speedKmh<=1)
  assert(h.tyreCatalog[index][compound+1]); h.cars[index].compoundIndex=compound
  local short=h.tyreCatalog[index][compound+1].short; h.cars[index].isAIUsingRainTyres=short=='W' or short=='I'
 end
 physics.setAISplineOffset=function(index,value,override)
  verify(index,value,math.abs(value)<=math.abs(h.offsets[index] or 0)+1e-9); assert(override==nil or type(override)=='boolean')
  h.cars[index].position.x=(right and -value or value)*5; h.offsets[index]=value; h.offsetCalls=h.offsetCalls+1
 end
 -- Couverture des infobulles : chaque commande doit être suivie d'une infobulle avant la commande suivante.
 local function widget(label)
  h.lastItemKind='native'
  if h.hoverAll then
   if h.pendingWidget and not h.pendingTipped then h.missingTips[#h.missingTips+1]=h.pendingWidget end
   h.pendingWidget=label; h.pendingTipped=false
  end
 end
 h.flushTips=function() if h.pendingWidget and not h.pendingTipped then h.missingTips[#h.missingTips+1]=h.pendingWidget end; h.pendingWidget=nil; h.pendingTipped=true end
 rgbm=function(r,g,b,m) return {r=r,g=g,b=b,m=m} end
 vec2=function(x,y) return {x=x,y=y} end
 ui.Font={Main=4,Title=6,Huge=7}
 ui.drawRect=function(p1,p2,color) assert(p1.x and p2.y and color.r); h.outlines=(h.outlines or 0)+1 end
 ui.Alignment={Start=-1,Center=0,End=1}
 ui.dwriteDrawTextClipped=function(text,size,p1,p2,hAlign,vAlign,wrap,color)
  assert(type(text)=='string' and type(size)=='number' and size>0 and type(p1)=='table' and p1.x and p1.y and type(p2)=='table'
   and p2.x>=p1.x and p2.y>=p1.y and type(hAlign)=='number' and type(vAlign)=='number' and type(wrap)=='boolean'
   and type(color)=='table' and color.r,'dwriteDrawTextClipped arguments')
  h.panelTexts[#h.panelTexts+1]=text; h.panelColors[#h.panelColors+1]=color; h.textTop=math.min(h.textTop or math.huge,p1.y)
  if wrap then h.wrappedPanel[#h.wrappedPanel+1]=text end
 end
 -- Mesure : 0,5 em par octet (défaut) ; h.realMeasure : largeur moyenne de la police poussée (condensée, chasse fixe,
 -- Segoe UI, gras), caractères UTF-8 comptés une fois.
 ui.measureDWriteText=function(text,size)
  assert(type(text)=='string' and type(size)=='number' and size>0)
  h.measures=(h.measures or 0)+1
  if not h.realMeasure then return {x=#text*size*0.5,y=size*1.2} end
  local name=h.fontStack[#h.fontStack] or ''
  local k=name:find('Condensed',1,true) and 0.43 or (name:find('Mono',1,true) or name:find('Consolas',1,true)) and 0.6 or name:find('Segoe',1,true) and 0.56 or 0.5
  if name:find('Bold',1,true) then k=k*1.06 end
  local n=0; for _ in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do n=n+1 end
  return {x=n*size*k*(h.measureScale or 1),y=size*1.2}
 end
 ui.drawCircleFilled=function(p,r,color,segments) assert(p.x and type(r)=='number' and r>0 and color.r and type(segments)=='number'); h.circles=(h.circles or 0)+1 end
 ui.drawCircle=function(p,r,color,segments,thickness) assert(p.x and type(r)=='number' and r>0 and color.r and type(segments)=='number' and type(thickness)=='number'); h.circles=(h.circles or 0)+1 end
 ui.drawText=function(text,pos,color) assert(type(text)=='string' and pos.x and color.r); h.badgeTexts[#h.badgeTexts+1]=text end
 ui.windowSize=function() if h.windowOverride then return h.windowOverride end return {x=620,y=h.windowHeight or 170} end
 ui.transparentWindow=function(id,pos,size,noPadding,inputs,content)
  assert(type(id)=='string' and pos.x and size.x>0 and size.y>0 and type(content)=='function')
  h.transparent[id]={x=pos.x,y=pos.y,w=size.x,h=size.y,inputs=inputs==true}
  local before=h.windowOverride; h.windowOverride={x=size.x,y=size.y}; local saved=h.titleBar; h.titleBar=0
  content(); h.windowOverride=before; h.titleBar=saved
 end
 ac.getUI=function() return {windowSize={x=1920,y=1080}} end
 ui.mouseDelta=function() return h.mouseDelta or {x=0,y=0} end
 ui.windowHovered=function() return h.windowHovered==true end
 ui.drawTriangleFilled=function(a,b,c,color) assert(a.x and b.x and c.x and color.r) end
 ui.drawQuadFilled=function(a,b,c,d,color) assert(a.x and b.x and c.x and d.x and color.r); h.quads=(h.quads or 0)+1 end
 -- Beta 1.35 UI/updater fixes : image (logo de l'en-tête), hauteur des cadres natifs, marges des commandes natives.
 ui.drawImage=function(path,p1,p2) assert(type(path)=='string' and p1.x and p2.x and p2.x>p1.x and p2.y>p1.y); h.images=(h.images or 0)+1 end
 ui.frameHeight=function() return h.frameHeight or 22 end
 ui.textLineHeight=function() return h.lineHeight or 15 end
 ui.StyleVar={FramePadding=18}
 ui.pushStyleVar=function(id,value) assert(type(id)=='number' and value~=nil); h.varDepth=(h.varDepth or 0)+1; h.varPushes=(h.varPushes or 0)+1 end
 ui.popStyleVar=function(count) h.varDepth=(h.varDepth or 0)-(count or 1); assert(h.varDepth>=0,'unbalanced popStyleVar') end
 ac.disableExtraHUDElements=function(id,disable) assert(id=='sessionTime'); h.hudHidden[id]=disable~=false end
 ac.onMessage=function(fn) h.messageListeners[#h.messageListeners+1]=fn; return function() for k,f in ipairs(h.messageListeners) do if f==fn then table.remove(h.messageListeners,k) end end end end
 ac.blockSystemMessages=function(regex) assert(type(regex)=='string'); h.blocked=h.blocked+1; return function() h.blocked=h.blocked-1 end end
 ui.drawRectFilled=function(p1,p2,color) assert(p1.x and p2.y and color.r); h.draws=h.draws+1; if h.rects then h.rects[#h.rects+1]={p1.x,p1.y,p2.x,p2.y} end end
 ui.setCursor=function(v) assert(v.x and v.y); h.panelCursor=v; h.cursorTop=math.min(h.cursorTop or math.huge,v.y) end
 ui.getCursor=function() return {x=8,y=h.titleBar or 34} end
 ui.textColored=function(text,color) assert(type(text)=='string' and color.r); h.panelTexts[#h.panelTexts+1]=text; h.panelColors[#h.panelColors+1]=color end
 ui.pushFont=function() h.fontDepth=h.fontDepth+1 end
 ui.popFont=function() h.fontDepth=h.fontDepth-1; assert(h.fontDepth>=0,'unbalanced popFont') end
 ui.StyleColor={Text=0,Border=5,FrameBg=7,PopupBg=4,Button=21,ButtonHovered=22,ButtonActive=23}
 ui.pushStyleColor=function(id,color) assert(type(id)=='number' and type(color)=='table'); h.styleDepth=h.styleDepth+1; h.styleMax=math.max(h.styleMax,h.styleDepth); if id==ui.StyleColor.Text then h.textColor=color end end
 ui.popStyleColor=function(count) h.styleDepth=h.styleDepth-(count or 1); assert(h.styleDepth>=0,'unbalanced popStyleColor') end
 ui.ButtonFlags={Active=0x200000}; ui.text=function() h.rendered=h.rendered+1 end; ui.separator=function() h.cursor=0; h.lastRight=0 end
 ui.sameLine=function() h.sameLines=h.sameLines+1; h.cursor=h.lastRight end
 ui.measureText=function(text,wrap)
  local width=#text*7*h.fontScale
  if wrap and wrap>0 and width>wrap then return {x=wrap,y=18*h.fontScale*math.ceil(width/wrap)} end
  return {x=width,y=18*h.fontScale}
 end
 ui.availableSpaceX=function() return h.width-h.cursor end
 ui.newLine=function() h.cursor=0; h.categoryRows=h.categoryRows+1 end
 ui.checkbox=function(label,value)
  widget(label)
  h.checkboxLabels[label]=true
  h.checkboxValues[label]=value
  h.lastRight=h.cursor+#label*7+32; h.cursor=0
  if h.clicked==label then h.clicked=''; return true end return false
 end
 ui.button=function(label,size,flags)
  widget(label)
  h.buttons[label]=flags or 0; h.accented[label]=h.styleDepth>=4 or nil
  if label:find('###tab_',1,true) then h.tabHeightMax=math.max(h.tabHeightMax,size and size.y>0 and size.y or 18*h.fontScale) end
  local width=size and size.x or #(label:gsub('###.*$',''))*7+32
  h.lastRight=h.cursor+width; h.cursor=0
  if size and h.lastRight>h.width then h.overflow=true end
  if h.clicked==label then h.clicked=''; return true end return false
 end
 ui.textWrapped=function(text) h.wrappedTexts[#h.wrappedTexts+1]=text end; ui.setNextItemWidth=function() end
 ui.slider=function(label,value)
  widget(label)
  h.sliderLabels[label]=true; local edit=h.sliderEdits[label]; h.sliderEdits[label]=nil
  if edit~=nil then return edit,true end; return value,false
 end
 ui.inputText=function(label,value) widget(label); local edit=h.inputEdits[label]; h.inputEdits[label]=nil; if edit~=nil then return edit,true end; return value,false end
 ui.combo=function(label,index,_flags,labels)
  widget(label)
  assert(labels[index]~=nil,'combo index must refer to an existing Lua item: '..label)
  h.comboValues[label]=labels[index]; h.comboLists=h.comboLists or {}; h.comboLists[label]=labels
  local edit=h.comboEdits[label]; h.comboEdits[label]=nil
  if edit~=nil then assert(labels[edit]~=nil); return edit,edit~=index end
  return index,false
 end
 -- Commandes dessinées (Beta 1.9) : boutons invisibles par identifiant, souris simulée, glisser par proportion de la
 -- largeur (h.drags[id]=0..1), clic droit (h.rightClick=id, souris sur la commande), molette (h.wheel).
 h.hits={}; h.hitOrder={}; h.drawnTexts={}; h.drags={}; h.mouse={x=-1e6,y=-1e6}; h.clipDepth=0; h.dwriteDepth=0; h.fontStack={}; h.space={x=1000,y=780}
 ui.availableSpace=function() return {x=h.space.x,y=h.space.y} end
 ui.invisibleButton=function(id,size)
  assert(type(id)=='string' and id:sub(1,2)=='##' and size.x>0 and size.y>0,'invisible button')
  local c=h.panelCursor or {x=0,y=0}
  if not h.hits[id] then h.hitOrder[#h.hitOrder+1]=id end
  h.hits[id]={x=c.x,y=c.y,w=size.x,h=size.y}
  h.lastItemKind='hit'; h.lastHit=id
  local m=h.mouse; h.lastItemHovered=m.x>=c.x and m.x<c.x+size.x and m.y>=c.y and m.y<c.y+size.y
  local ratio=h.drags[id]; h.activeHit=nil
  if ratio then h.drags[id]=nil; h.activeHit=id; h.dragPos={x=c.x+ratio*size.x,y=c.y+size.y/2} end
  if h.clicked==id then h.clicked=''; return true end
  return false
 end
 ui.itemHovered=function() if h.lastItemKind=='hit' then return h.lastItemHovered end return h.hoverAll end
 ui.itemActive=function() return h.activeHit~=nil and h.activeHit==h.lastHit end
 ui.mouseDown=function() return h.activeHit~=nil end
 ui.mouseLocalPos=function() if h.activeHit and h.activeHit==h.lastHit then return h.dragPos end return h.mouse end
 ui.mouseClicked=function(button) if button==1 and h.rightClick and h.rightClick==h.lastHit then h.rightClick=nil; return true end return false end
 ui.mouseWheel=function() local w=h.wheel or 0; h.wheel=0; return w end
 -- h.textBoxes (facultatif) : position et largeur de chaque texte dessiné, mesurée avec la police poussée.
 ui.dwriteDrawText=function(text,size,pos,color) assert(type(text)=='string' and type(size)=='number' and size>0 and pos.x and color.r); h.drawnTexts[#h.drawnTexts+1]=text
  if h.textBoxes then local m=ui.measureDWriteText(text,size); h.measures=h.measures-1; h.textBoxes[#h.textBoxes+1]={text=text,x=pos.x,y=pos.y,size=size,w=m.x} end end
 -- Même police repoussée aussitôt (rien gagné) et profondeur la plus haute de la pile : comptées.
 ui.pushDWriteFont=function(name) assert(type(name)=='string'); h.dwriteDepth=h.dwriteDepth+1; h.fontStack[#h.fontStack+1]=name; h.fontPushes=(h.fontPushes or 0)+1
  if h.lastPushed==name then h.repeatPushes=(h.repeatPushes or 0)+1 end; h.lastPushed=name; h.fontDepthMax=math.max(h.fontDepthMax or 0,h.dwriteDepth) end
 ui.popDWriteFont=function() h.dwriteDepth=h.dwriteDepth-1; h.fontStack[#h.fontStack]=nil; assert(h.dwriteDepth>=0,'unbalanced popDWriteFont') end
 ui.drawLine=function(a,b,color,th) assert(a.x and b.y and color.r and type(th)=='number') end
 ui.pushClipRect=function(a,b) assert(a.x and b.y); h.clipDepth=h.clipDepth+1 end
 ui.popClipRect=function() h.clipDepth=h.clipDepth-1; assert(h.clipDepth>=0,'unbalanced popClipRect') end
 ui.setTooltip=function(text) assert(type(text)=='string' and text~=''); h.pendingTipped=true; h.lastTooltip=text; h.tooltips[#h.tooltips+1]=text end
 return h
end
-- CSP relit gui.ini (Beta 1.40) : écouteurs de ac.onCSPConfigChanged appelés.
function M.reloadGui(h) for _,fn in ipairs(h.guiWatchers) do fn() end end
function M.tick(h,seconds)
 for _=1,math.floor(seconds*60+0.5) do
  h.sim.gameTime=h.sim.gameTime+1/60; h.sim.currentSessionTime=h.sim.currentSessionTime+1000/60
  script.update(1/60)
  assert(HUMANAI.engine.errors==0,'entry callback error')
  assert(HUMANAI.host.errors==0,'host error (stop, release, session, UI)')
 end
end
return M
