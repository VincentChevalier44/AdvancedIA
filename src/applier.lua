local ffi=require('ffi')
local U=require('src/util')
local C=require('src/config')
local Caps=require('src/caps')
local Lights=require('src/lights')
local Perception=require('src/perception')
local Presets=require('src/presets')
local K=C.K
local M={}
local setters={level='setAILevel',aggression='setAIAggression',caution='setAICaution',offset='setAISplineOffset',grip='setExtraAIGrip',speed='setAITopSpeed',rain='setAIRainTyres',tyres='setAITyres',pit='setAIPitStopRequest',
 stop='setAIStopCounter',flag='overrideRacingFlag',park='setAINoInput',teleport='teleportCarTo',penalty='setCarPenalty',drs='allowCarDRS',drsActive='setCarDRS',brakeMistake='setAIBrakeMistake',tractionMistake='setAITractionMistake',fuel='overrideAIRequestedFuel',startDelay='setAITimeToStart',awake='awakeCar',position='setCarPosition',velocity='setCarVelocity',repairBody='setCarBodyDamage',repairSuspension='setSuspensionDamage',repairEngine='setCarEngineLife',fuelSet='setCarFuel',throttle='setAIThrottleLimit',tyreKm='setTyresVirtualKM'}
local windowIDs={'main'}
-- Événements de l'applicateur vers le journal du moteur (relié par le fichier d'entrée).
local function note(a,level,text,index) if a.note then a.note(level,text,index) end end
-- Résultat mémorisé par fonction cdata (son type ne change jamais) : ni texte du type ni motif à chaque appel.
local callableCdata=setmetatable({},{__mode='k'})
local function callable(f)
 if type(f)=='function' then return true end
 if type(f)~='cdata' or f==nil then return false end
 local known=callableCdata[f]
 if known==nil then local name=tostring(ffi.typeof(f)); known=not name:find('[',1,true) and name:match('%b()%s*>$')~=nil; callableCdata[f]=known end
 return known
end
M.callable=callable
local function nativeClock()
 -- Compteur Windows en lecture seule, sans chargement de DLL.
 pcall(ffi.cdef,'int QueryPerformanceCounter(int64_t*); int QueryPerformanceFrequency(int64_t*);')
 local counter,frequency=ffi.C.QueryPerformanceCounter,ffi.C.QueryPerformanceFrequency
 local buffer=ffi.new('int64_t[1]')
 if frequency(buffer)==0 or tonumber(buffer[0])<=0 then return nil end
 local scale=tonumber(buffer[0])
 return {read=function() if counter(buffer)==0 then return nil end return tonumber(buffer[0])/scale end,source='compteur Windows',failures=0}
end
-- Beta 1.41 (journaux du 3 novembre : « cout non mesure » à chaque résumé, CSP n'expose pas le compteur Windows) : repli
-- sur os.preciseClock s'il avance pendant une image (vérifié une fois, au lancement), sinon os.clock (pas d'une
-- milliseconde : la moyenne reste juste, le maximum est arrondi à la milliseconde).
local function osClock()
 if type(os)~='table' then return nil end
 local precise=os.preciseClock
 if callable(precise) then
  local first=precise(); local spin=0
  for k=1,K.clockProbeLoops do spin=spin+k%7 end
  if type(first)=='number' and spin>=0 and precise()>first then return {read=precise,source='os.preciseClock',failures=0} end
 end
 if callable(os.clock) then return {read=os.clock,source='os.clock (1 ms)',failures=0} end
 return nil
end
M.osClock=osClock
local function initClock()
 local ok,timer=pcall(nativeClock)
 if ok and timer then return timer end
 local fallback,clock=pcall(osClock)
 return fallback and clock or nil
end
local function present(name)
 local controls=name=='brake' or name=='flash'
 return controls and callable(ac.overrideCarControls) or not controls and physics~=nil and callable(physics[setters[name]])
end
-- Seul le frein est imposé : les autres champs reçoivent la valeur neutre documentée par le SDK
-- (direction et pédales d'origine, rapport, mode MGU-H et KERS conservés), quelle que soit leur valeur initiale.
local function setBrake(controls,value)
 controls.combineAxis=true; controls.steer=math.huge; controls.gas=0; controls.handbrake=0; controls.clutch=1; controls.requestedGearIndex=0; controls.mguhMode=-1; controls.kers=-1
 controls.brake=value
end
-- Appel de phares d'une IA : mêmes valeurs neutres, frein additionnel en cours conservé, impulsion d'une image.
local function setFlash(controls,brake) setBrake(controls,brake); controls.headlightsFlash=true end
local function write(name,index,value,extra)
 if name=='brake' or name=='flash' then
  local ok,controls=pcall(ac.overrideCarControls,index)
  if not ok or not controls then return false end
  return pcall(name=='flash' and setFlash or setBrake,controls,value)
 end
 local f=physics and physics[setters[name]]
 if not callable(f) then return false end
 if name=='flag' then return pcall(f,value) end -- Drapeau du joueur : sans indice de voiture.
 -- Pénalité du joueur : coupure des gaz pendant value secondes, sans indice de voiture.
 if name=='penalty' then return pcall(f,extra or ac.PenaltyType and ac.PenaltyType.SlowDown or K.penaltySlowDown,value) end
 if name=='offset' then return pcall(f,index,value,extra) end
 if name=='position' then return pcall(f,index,value,extra) end -- position, puis direction
 if name=='tractionMistake' then return pcall(f,index,value,extra) end -- durée, puis sévérité (multiplicateur des gaz)
 if name=='fuel' then return pcall(f,index,value,extra) end -- litres demandés, puis tours avant un arrêt natif
 if name=='tyreKm' then return pcall(f,index,value,extra) end -- Beta 1.42 : roue (0 à 3), puis distance virtuelle (km)
 -- Réparations (Beta 1.20) : carrosserie à value sur ses quatre côtés ; suspensions des quatre roues (défaut du SDK).
 if name=='repairBody' then return pcall(function() return f(index,vec4(value,value,value,value)) end) end
 if name=='repairSuspension' then return pcall(f,index,nil,value) end
 return pcall(f,index,value)
end
function M.new()
 local a={cars={},allowed=false,errors=0,rejected=0,stores={},dirtyAt=0,dirty=false,lastSave=-math.huge,recoveryDirty=false,storageErrors=0,
  port={present=present,write=write},releaseToken=nil,sessionToken=nil,safety={left=false,right=false,nearest=0},offsetSign=0,aiFunctions={},presets={},presetStores={},menuVisible=false,menuLast=nil,
  flagOverride=false,flagValue=0,flagAt=-math.huge,trackLights=nil,trackLightsSource='',trackLightsFor=nil}
 for i=1,K.maxCars do a.cars[i]={owned=false,reset=false,level=nil,aggression=nil,caution=nil,offset=0,brake=0,grip=nil,
  originalLevel=1,originalAggression=0.5,lastWrite=-math.huge,id='',readAt=0,speed=nil,offsetReset=true,rainHint=nil,originalRain=false,pitRequest=false,weatherAt=-math.huge,tyreAt=-math.huge,
  levelAt=-math.huge,recovered=false,drsBlocked=false,drsAt=-math.huge,stop=false,stopAt=-math.huge,flashEvent=0,flashPulses=0,flashAt=-math.huge,pitAt=-math.huge,tyreVisit=-1,repairVisit=-1,teleportAt=-math.huge,startDelayFor='',placeFor='',placeAt=-math.huge,launchPending=false,launchAt=-math.huge,fuelRequested=-1,fuelSetFor='',fuelBoxed=false,fuelBefore=-1,parked=false,parkAt=-math.huge,teleported=false,redTeleported=false} end
 a.caps=Caps.new(a.port); a.clipboard=M.clipboard
 local ok,timer=pcall(initClock); if ok then a.timer=timer end
 pcall(function()
  if type(physics)=='table' then
   for name,f in pairs(physics) do
    if type(name)=='string' and name:find('AI',1,true) and callable(f) and #a.aiFunctions<K.maxCapabilities then a.aiFunctions[#a.aiFunctions+1]=name end
   end
   table.sort(a.aiFunctions)
  end
 end)
 return a
end
function M.clock(a)
 local timer=a.timer
 if not timer then return nil end
 local ok,result=pcall(timer.read)
 if not ok or type(result)~='number' then
  timer.failures=timer.failures+1; if timer.failures>=K.capabilityFailures then a.timer=nil end
  return nil
 end
 -- Source du chronomètre au journal, une fois (le journal est relié après la création de l'applicateur).
 if not timer.announced and a.note then timer.announced=true; note(a,'INFO','cout par image mesure par: '..timer.source,-1) end
 timer.failures=0; return result
end
function M.access(a)
 a.allowed=false
 if not physics or not callable(physics.allowed) then return false end
 local ok,allowed=pcall(physics.allowed); a.allowed=ok and allowed==true
 if not ok then a.errors=a.errors+1 end
 return a.allowed
end
function M.openStore(a)
 local layout={}; for k,v in pairs(C.globalDefaults) do layout[k]=v end
 local ok,store=pcall(ac.storage,layout,'humanai:g:'); if ok then a.stores.g=store end
 local valid,g,errors=pcall(C.validateGlobals,ok and store or C.globalDefaults)
 if not valid then g=C.validateGlobals(C.globalDefaults); errors=1 end
 a.storageErrors=errors+(ok and 0 or 1)
 local profiles={}
 for _,p in ipairs(C.profiles) do
  local defaults=C.defaults(p); local good,s=pcall(ac.storage,defaults,'humanai:p:'..p..':')
  if good then a.stores[p]=s end
  local accepted,normalized,n=pcall(C.validate,p,good and s or defaults)
  profiles[p]=accepted and normalized or defaults
  a.storageErrors=a.storageErrors+(accepted and n or 1)+(good and 0 or 1)
 end
 -- Données 1.2.0 : migration unique, sauvegardée à la première occasion.
 local migrated,upgraded,fresh,restored=pcall(C.migrate,g,profiles)
 if migrated and upgraded then a.upgraded=upgraded; a.firstInstall=fresh==true; a.signsRestored=restored==true; a.dirty=true; a.dirtyAt=0 end
 for i=1,K.maxPresets do
  local opened,slot=pcall(ac.storage,Presets.layout(),'humanai:custom:'..i..':')
  if opened then
   a.presetStores[i]=slot
   local good,entry,errors=pcall(Presets.decode,slot)
   if good then a.presets[i]=entry; if entry and errors>0 then a.storageErrors=a.storageErrors+errors end end
  end
 end
 return g,profiles
end
function M.savePreset(a,entry)
 local at
 for i=1,K.maxPresets do if a.presets[i] and a.presets[i].name==entry.name then at=i; break end end
 if not at then for i=1,K.maxPresets do if not a.presets[i] then at=i; break end end end
 if not at or not a.presetStores[at] then return false end
 local values=Presets.encode(entry)
 local ok=pcall(function()
  a.presetStores[at].name=''
  for key,value in pairs(values) do if key~='name' then a.presetStores[at][key]=value end end
  a.presetStores[at].name=entry.name
 end)
 if ok then a.presets[at]=entry end
 return ok
end
function M.deletePreset(a,index)
 if not U.finite(index) or index%1~=0 or index<1 or index>K.maxPresets or not a.presets[index] or not a.presetStores[index] then return false end
 local ok=pcall(function() a.presetStores[index].name='' end)
 if ok then a.presets[index]=nil end
 return ok
end
-- Options CSP de gui.ini, section [HIDE] (« Hide race flags » : HIDE_RACE_FLAGS) : true ou false, nil si illisible.
local function readOption(key)
 return ac.INIConfig.cspModule(ac.CSPModuleID.GUI):get('HIDE',key,false)
end
-- Beta 1.40 : option masquée par l'app et pas encore relue par CSP : la valeur appliquée par CSP reste celle d'avant
-- (a.cspFrozen, src/cspgui.lua) ; jamais celle du fichier, que CSP n'applique pas encore.
local function readRaceFlagsHidden(a)
 local frozen=a.cspFrozen and a.cspFrozen('HIDE_RACE_FLAGS')
 if frozen~=nil then return frozen end
 return readOption('HIDE_RACE_FLAGS')
end
function M.readFlagsHidden(a)
 local ok,value=pcall(readRaceFlagsHidden,a)
 if ok and type(value)=='boolean' then a.raceFlagsHidden=value elseif ok and type(value)=='number' then a.raceFlagsHidden=value~=0 else a.raceFlagsHidden=nil end
end
function M.menu(a,visible)
 a.menuVisible=visible
 if visible~=a.menuLast then
  a.menuLast=visible
  -- Relue à chaque ouverture du menu (réglage CSP modifiable en cours de partie).
  if visible then M.readFlagsHidden(a) end
  if callable(ac.setWindowOpen) then pcall(ac.setWindowOpen,'main',visible) end
 end
 if not visible and callable(ac.isWindowOpen) and callable(ac.setWindowOpen) then
  for _,id in ipairs(windowIDs) do local ok,opened=pcall(ac.isWindowOpen,id); if ok and opened then pcall(ac.setWindowOpen,id,false) end end
 end
end
-- Beta 1.14 : fenêtre de réglages ramenée une fois à la taille compacte (target) si elle est plus large. Renvoie true
-- quand c'est fait ou impossible (fonction ou fenêtre absente : noté au journal), pour ne jamais réessayer.
function M.compactWindow(a,target)
 if not callable(ac.accessAppWindow) then return true end
 local ok,w=pcall(ac.accessAppWindow,'IMGUI_LUA_AdvancedIA_main')
 if not ok or not w then note(a,'WARN','fenetre de reglages introuvable: taille laissee telle quelle',-1); return true end
 local good,size=pcall(function() return w:size() end)
 if good and size and size.x>target.x+1 then
  local done=pcall(function() w:resize(target) end)
  note(a,'INFO',string.format('fenetre de reglages %s: %.0f x %.0f -> %.0f x %.0f',done and 'compactee' or 'non compactee',size.x,size.y,target.x,target.y),-1)
 end
 return true
end
function M.baselines(a,frame)
 for i=1,frame.count do
  local car,s=frame.cars[i],a.cars[i]; local known=s.owned and s.id==(car.identity or car.id)
  car.baseLevel=known and s.originalLevel or car.aiLevel; car.baseAggression=known and s.originalAggression or car.aiAggression
 end
end
function M.dirty(a,now) a.dirtyAt=now+K.saveDelay; a.dirty=true end
function M.rebase(a,amount)
 if a.dirty then a.dirtyAt=a.dirtyAt-amount end
 a.lastSave=a.lastSave-amount
 a.caps.probeAt=a.caps.probeAt-amount
 if a.flagAt>-math.huge then a.flagAt=a.flagAt-amount end
 for i=1,K.maxCars do
  local s=a.cars[i]; s.lastWrite=s.lastWrite-amount; s.readAt=s.readAt-amount; s.weatherAt=s.weatherAt-amount; s.tyreAt=s.tyreAt-amount; s.levelAt=s.levelAt-amount
  s.pitAt=s.pitAt-amount; s.stopAt=s.stopAt-amount; s.parkAt=s.parkAt-amount; s.teleportAt=s.teleportAt-amount; s.flashAt=s.flashAt-amount; s.drsAt=s.drsAt-amount
  if U.finite(s.placeAt) then s.placeAt=s.placeAt-amount end; if U.finite(s.launchAt) then s.launchAt=s.launchAt-amount end; if U.finite(s.scKickAt) then s.scKickAt=s.scKickAt-amount end
 end
end
function M.save(a,g,profiles,now,replay,force)
 if replay or not a.dirty or not force and (now<a.dirtyAt or now-a.lastSave<K.saveDelay) then return end
 local valid=C.validateGlobals(g)
 local ok=pcall(function()
  if a.stores.g then for k in pairs(C.globalDefaults) do a.stores.g[k]=valid[k] end end
  for _,p in ipairs(C.profiles) do
   local v=C.validate(p,profiles[p]); local store=a.stores[p]
   if store then for k in pairs(v) do store[k]=v[k] end end
  end
 end)
 if ok then a.lastSave=now; a.dirtyAt=0; a.dirty=false else a.errors=math.min(K.counterMax,a.errors+1) end
end
-- final : déchargement de l'app, sans image suivante. Restitution aussi en pause, en replay, aux stands et hors piste ;
-- seul l'offset reste soumis à la piste et à l'occupation, jamais d'après des positions de replay.
-- Stratégie pluie native rendue à son état d'origine.
local function restoreRain(a,s,car)
 if s.rainHint~=nil and Caps.restoreCall(a.caps,'rain',car.index,s.originalRain) then s.rainHint=nil; a.recoveryDirty=true end
end
-- Livrée d'origine rendue à une voiture habillée en voiture de sécurité (elle ne l'est plus, ou l'app se décharge).
local function restoreSkin(s,car)
 if not s.skinOriginal then return end
 local original=s.skinOriginal; s.skinOriginal=nil; s.skinApplied=nil
 if car.valid and callable(ac.findNodes) and callable(ac.getFolder) then
  pcall(function() ac.findNodes('carRoot:'..car.index):applySkin(ac.getFolder(ac.FolderID.ContentCars)..'/'..car.id..'/skins/'..original) end)
 end
end
-- keepParked : fin de session, les voitures garées restent garées (rendues à la session suivante ou au déchargement).
function M.restore(a,frame,pendingOnly,now,final,keepParked)
 if not a.allowed or frame.online or not final and (frame.replay or frame.paused) then for i=1,K.maxCars do if a.cars[i].owned then a.cars[i].reset=true end end; return end
 if not pendingOnly and a.flagOverride and Caps.restoreCall(a.caps,'flag',-1,K.flagNone) then a.flagOverride=false; a.flagValue=K.flagNone; a.recoveryDirty=true; M.flagReleased(a); note(a,'INFO','panneaux lumineux du circuit: rendus a AC (commandes rendues)',-1) end
 if final then M.releaseBlackFlag(a) end
 if not pendingOnly then M.releaseDrs(a,frame) end
 for i=1,frame.count do
  local car=frame.cars[i]; local s=a.cars[i]
  if final then restoreSkin(s,car) end
  -- Attente de sortie des stands en cours (essais, qualifications) : annulée à la restitution, l'IA part aussitôt.
  if not pendingOnly and s.startDelayFor~='' then
   if car.valid and car.control and not car.player and car.inPitBox then Caps.restoreCall(a.caps,'startDelay',car.index,0) end
   s.startDelayFor=''
  end
  if s.owned and (not pendingOnly or s.reset) then
   s.reset=true
   if car.valid and s.id~=(car.identity or car.id) then s.owned=false; s.reset=false; s.offset=0; s.recovered=false; a.recoveryDirty=true end
   local mine=s.owned and car.valid and car.control and not car.player and (car.identity or car.id)==s.id
   if mine and s.stop and Caps.restoreCall(a.caps,'stop',car.index,0) then s.stop=false; a.recoveryDirty=true end
   if mine and s.parked and not keepParked and Caps.restoreCall(a.caps,'park',car.index,false) then s.parked=false; s.parkAt=-math.huge; a.recoveryDirty=true end
   -- Beta 1.50 : voiture de sécurité retenue par l'attente d'AC : attente levée à la restitution.
   if mine and s.scHeld and not keepParked then Caps.restoreCall(a.caps,'startDelay',car.index,0); Caps.restoreCall(a.caps,'stop',car.index,0); s.scHeld=false; s.scHoldAt=-math.huge; a.recoveryDirty=true end
   -- Frein additionnel relâché aussi hors conduite (stands, hors piste) : seule écriture de frein admise aux stands.
   if mine and s.brake~=0 and Caps.restoreCall(a.caps,'brake',car.index,0) then s.brake=0; a.recoveryDirty=true end
   if mine and (final or not car.offtrack) then
    restoreRain(a,s,car)
    -- Dans la voie des stands, l'annulation attend la sortie : false bloquerait l'arrêt en cours (SDK).
    if s.pitRequest and (final or not car.pit) and Caps.restoreCall(a.caps,'pit',car.index,false) then s.pitRequest=false; a.recoveryDirty=true end
   end
   -- Demande de carburant rendue à AC (math.huge : plus de remplacement).
   if mine and s.fuelRequested>=0 and Caps.restoreCall(a.caps,'fuel',car.index,math.huge) then s.fuelRequested=-1; s.fuelLogged=nil; a.recoveryDirty=true end
   local driving=mine and not car.pit and not car.offtrack
   if driving or final and mine then
    local good=s.offsetReset==true and s.offset==0
    if not good and driving and not frame.replay then
     Perception.occupancy(frame.cars,frame.count,i,a.g or C.globalDefaults,a.safety)
     local canonical=s.offset*(a.offsetSign==0 and 1 or a.offsetSign)
     local safe=not (canonical>0 and a.safety.left or canonical<0 and a.safety.right)
     if a.offsetSign==0 then safe=not a.safety.left and not a.safety.right end
     if safe then good=Caps.restoreCall(a.caps,'offset',car.index,0,false); s.offsetReset=good end
    end
    if s.level~=nil then if Caps.restoreCall(a.caps,'level',car.index,s.originalLevel) then s.level=nil else good=false end end
    if s.aggression~=nil then if Caps.restoreCall(a.caps,'aggression',car.index,s.originalAggression) then s.aggression=nil else good=false end end
    if s.caution~=nil then if Caps.restoreCall(a.caps,'caution',car.index,K.defaultCaution) then s.caution=nil else good=false end end
    if s.grip~=nil then if Caps.restoreCall(a.caps,'grip',car.index,K.gripBase) then s.grip=nil else good=false end end
    if s.brake~=0 then good=false end
    if s.speed~=nil then if Caps.restoreCall(a.caps,'speed',car.index,K.unlimitedSpeed) then s.speed=nil else good=false end end
    if s.throttle~=nil then if Caps.restoreCall(a.caps,'throttle',car.index,1) then s.throttle=nil else good=false end end
    if s.rainHint~=nil or s.pitRequest or s.stop or s.parked or s.fuelRequested>=0 then good=false end
    if good then s.owned=false; s.reset=false; s.offset=0; s.level=nil; s.aggression=nil; s.caution=nil; s.grip=nil; s.brake=0; s.speed=nil; s.recovered=false; s.restoredAt=now; s.justRestored=true; a.recoveryDirty=true end
   end
  end
 end
end
local function send(a,s,name,index,value,epsilon)
 if not U.finite(value) then a.rejected=a.rejected+1; return false end
 local old=s[name]
 if old==nil or math.abs(value-old)>=epsilon then
  if Caps.call(a.caps,name,index,value) then if old==nil then a.recoveryDirty=true end; s[name]=value; return true end
 end
 return false
end
local function field(a,s,name,index,owned,value,epsilon,original)
 if owned~=false then
  if a.caps[name].available then send(a,s,name,index,value,epsilon) end
 elseif s[name]~=nil and Caps.restoreCall(a.caps,name,index,original) then s[name]=nil; a.recoveryDirty=true end
end
local function claim(a,s,car,now)
 if s.owned and s.id==(car.identity or car.id) then return end
 s.id=car.identity or car.id
 if s.restoredAt~=now then s.originalLevel=car.aiLevel; s.originalAggression=car.aiAggression end
 s.owned=true; s.recovered=false; a.recoveryDirty=true
 s.offset=0; s.level=nil; s.aggression=nil; s.caution=nil; s.brake=0; s.grip=nil; s.speed=nil; s.offsetReset=true
 s.rainHint=nil; if s.restoredAt~=now then s.originalRain=car.nativeRainTyres==true end; s.pitRequest=false; s.weatherAt=-math.huge; s.tyreAt=-math.huge; s.stop=false; s.stopAt=-math.huge
 s.pitAt=-math.huge; s.tyreVisit=-1
end
local function weather(a,s,car,cmd,now)
 if not car.valid or not car.control or car.player or car.offtrack then return end
 if cmd.weatherManaged and (not s.reset or car.pit) then
  claim(a,s,car,now)
  -- Tant que l'état natif correspond déjà à la décision, la stratégie pluie de CSP n'est pas forcée.
  local native=car.nativeRainTyresKnown and s.rainHint==nil and car.nativeRainTyres==cmd.weatherRain
  if a.caps.rain.available and s.rainHint~=cmd.weatherRain and not native and Caps.call(a.caps,'rain',car.index,cmd.weatherRain) then s.rainHint=cmd.weatherRain; a.recoveryDirty=true end
  -- Gomme inadaptée dans la voie des stands : changée aussitôt, même en roulant (les IA apparaissent souvent aux stands
  -- en intermédiaires sur piste sèche et repartent avant le contrôle suivant).
  local lane=car.pit and cmd.weatherCompound>=0 and car.compoundIndex~=cmd.weatherCompound
  if now>=s.weatherAt or lane then
   s.weatherAt=now+K.weatherPeriod
   if cmd.weatherCompound>=0 and (car.pit or cmd.weatherGrid and car.kmh<=K.tyreStopSpeed) and car.compoundIndex~=cmd.weatherCompound and now>=s.tyreAt and a.caps.tyres.available then
    local before=car.compoundIndex
    if Caps.call(a.caps,'tyres',car.index,cmd.weatherCompound) then
     s.tyreAt=now+5
     local names=car.tyreNames or {}
     note(a,'INFO',string.format('pneus adaptes a la meteo %s: %s -> %s (%s)',car.inPitBox and 'aux stands' or car.pit and 'dans la voie des stands' or 'a l arret au depart',
      tostring(names[before] or before),tostring(names[cmd.weatherCompound] or cmd.weatherCompound),cmd.weatherRain and 'pluie' or 'sec'),car.index+1)
    end
   end
  end
 elseif s.owned and s.id==(car.identity or car.id) then
  restoreRain(a,s,car)
 end
end
-- Nom d'une gomme pour le journal : nom court et nom long (Beta 1.24).
local function tyreLabel(car,index)
 if index==nil then return '?' end
 return ((car.tyreNames and car.tyreNames[index]) or '?')..((car.tyreLongNames and car.tyreLongNames[index]) and ' '..car.tyreLongNames[index] or '')
end
-- Demande de passage aux stands, seul arbitre de la météo et des règles. Elle reste active dans la voie des stands
-- jusqu'à l'arrêt ; false n'est envoyé que pour une demande de l'app, car il bloquerait aussi un arrêt natif (SDK).
local function pitRequest(a,s,car,cmd,now)
 if not car.valid or not car.control or car.player or car.offtrack then return end
 local managed=(cmd.weatherManaged or cmd.rulePit) and (not s.reset or car.pit)
 if managed then
  claim(a,s,car,now)
  if now>=s.pitAt then
   s.pitAt=now+K.weatherPeriod
   if (cmd.weatherManaged and cmd.weatherPit or cmd.rulePit) and a.caps.pit.available then
    if not car.pit and Caps.call(a.caps,'pit',car.index,true) then s.pitRequest=true; a.recoveryDirty=true end
   elseif s.pitRequest and not car.pit and Caps.restoreCall(a.caps,'pit',car.index,false) then s.pitRequest=false; a.recoveryDirty=true end
  end
 elseif s.pitRequest and s.owned and s.id==(car.identity or car.id) and not car.pit and Caps.restoreCall(a.caps,'pit',car.index,false) then s.pitRequest=false; a.recoveryDirty=true end
 -- Arrêt réglementaire : un train de pneus par passage à l'emplacement. Une autre voiture dans l'emplacement de la
 -- liste (changement de pilote ou de voiture) repart de zéro.
 if s.tyreVisit>=0 and s.id~=(car.identity or car.id) then s.tyreVisit=-1 end
 if cmd.pitCompound>=0 and car.inPitBox and car.kmh<=K.tyreStopSpeed and s.tyreVisit~=cmd.pitVisit and now>=s.tyreAt and a.caps.tyres.available then
  claim(a,s,car,now)
  -- Journal (Beta 1.24) : gomme posée et gomme d'avant, avec leurs noms (variantes d'adhérence d'un même mod).
  if Caps.call(a.caps,'tyres',car.index,cmd.pitCompound) then s.tyreVisit=cmd.pitVisit; s.tyreAt=now+5; note(a,'INFO',string.format('pneus poses: composé %d (%s), avant %s (%s)',cmd.pitCompound,tyreLabel(car,cmd.pitCompound),tostring(car.compoundIndex or '?'),tyreLabel(car,car.compoundIndex)),car.index+1) end
 end
 -- Réparations (Beta 1.20) : une fois par passage à l'emplacement, voiture arrêtée ; seuls les dégâts lus sont réparés.
 if s.repairVisit>=0 and s.id~=(car.identity or car.id) then s.repairVisit=-1 end
 if cmd.pitRepair and car.inPitBox and car.kmh<=K.tyreStopSpeed and s.repairVisit~=cmd.pitVisit then
  claim(a,s,car,now); s.repairVisit=cmd.pitVisit
  local damage,worn,life=car.damageBody or 0,car.damageSuspension or 0,car.engineLife or K.engineLifeNew
  local body=damage>0 and Caps.call(a.caps,'repairBody',car.index,0)
  local suspension=worn>0 and Caps.call(a.caps,'repairSuspension',car.index,0)
  local engine=life<K.engineLifeNew and Caps.call(a.caps,'repairEngine',car.index,K.engineLifeNew)
  -- Journal (Beta 1.23) : seulement si quelque chose a été réparé (sans dégât lu à l'arrêt : déjà réparé par AC).
  if body or suspension or engine then
   note(a,'INFO',string.format('reparations: carrosserie %.0f km/h%s, suspensions %.2f%s, moteur %.0f%s ; reparation AC en cours: %s',damage,body and ' (reparee)' or '',
    worn,suspension and ' (reparees)' or '',life,engine and ' (neuf)' or '',car.repairingNative and 'oui' or 'non'),car.index+1)
  end
 end
 -- Carburant demandé à l'arrêt forcé (écrit avant l'emplacement, au litre près), rendu à AC sans demande de l'app.
 if cmd.fuelTarget>=0 and a.caps.fuel.available then
  local liters=math.floor(cmd.fuelTarget+0.5)
  if liters~=s.fuelRequested and not car.inPitBox then
   claim(a,s,car,now)
   if Caps.call(a.caps,'fuel',car.index,liters,cmd.fuelLaps) then
    s.fuelRequested=liters; a.recoveryDirty=true
    -- Beta 1.47 : au journal seulement quand la demande change d'au moins K.fuelLogStep L (avant : une ligne par litre).
    if not s.fuelLogged or math.abs(liters-s.fuelLogged)>=K.fuelLogStep then
     s.fuelLogged=liters
     note(a,'INFO',string.format('carburant demande: %d L (%.1f L a bord), %d tour(s) avant un arret natif',liters,car.fuel or -1,cmd.fuelLaps),car.index+1)
    end
   end
  end
 elseif s.fuelRequested>=0 and s.owned and s.id==(car.identity or car.id) and not car.inPitBox and Caps.restoreCall(a.caps,'fuel',car.index,math.huge) then s.fuelRequested=-1; s.fuelLogged=nil; a.recoveryDirty=true end
 -- Plein de course avant le départ (sans ravitaillement prévu) : une fois par voiture et par session.
 local fuelKey=cmd.fuelSet>=0 and (car.identity or car.id)..'|'..(a.session or 0)
 if fuelKey and s.fuelSetFor~=fuelKey and a.caps.fuelSet.available then
  claim(a,s,car,now)
  if Caps.call(a.caps,'fuelSet',car.index,cmd.fuelSet) then s.fuelSetFor=fuelKey; note(a,'INFO',string.format('carburant au depart: %.1f L (%.1f L avant)',cmd.fuelSet,car.fuel or -1),car.index+1) end
 end
 -- Journal : carburant à l'entrée et à la sortie de l'emplacement (sens de la demande vérifié en jeu).
 if car.inPitBox and not s.fuelBoxed then s.fuelBoxed=true; s.fuelBefore=car.fuel or -1
 elseif not car.inPitBox and s.fuelBoxed then
  s.fuelBoxed=false
  if s.fuelRequested>=0 then note(a,'INFO',string.format('carburant: %.1f L avant l arret, %.1f L apres (demande %d L)',s.fuelBefore,car.fuel or -1,s.fuelRequested),car.index+1) end
 end
end
-- Essais et qualifications (Beta 1.22) : attente native d'AC à l'emplacement avant la sortie, écrite une fois par
-- voiture et par tirage ; 0 l'annule (voiture sortie de son emplacement avant son tour), où qu'elle soit.
local function startDelay(a,s,car,cmd)
 local wait=cmd.startDelay or -1
 if wait<0 or s.startDelayFor==cmd.startDelayFor or not car.valid or not car.control or car.player or wait>0 and not car.inPitBox then return end
 s.startDelayFor=cmd.startDelayFor
 if Caps.call(a.caps,'startDelay',car.index,wait) and wait==0 then note(a,'WARN','sortie des stands etalee: attente annulee (voiture sortie de son emplacement)',car.index+1) end
end
-- Répartition sur le circuit (Beta 1.26) : IA posée sur la trajectoire de l'IA à la progression voulue, alignée par CSP
-- sur cette trajectoire (direction absente), attente native d'AC annulée d'abord ; élan de K.spreadSpeed km/h donné
-- ensuite, une fois le saut de position vu, dans l'axe réel de la voiture (jamais de glissade, jamais arrêtée en
-- piste) ; nouvel essai toutes les K.spreadRetry s tant que le moteur la demande (pas encore à sa place).
local function place(a,s,car,cmd,now)
 if s.launchPending and car.valid and (car.teleport or now>=s.launchAt) then
  s.launchPending=false
  -- Beta 1.48 : voiture de sécurité posée en piste : son élan propre (cmd.placeKmh).
  local kmh=s.launchKmh or K.spreadSpeed
  if car.teleport and car.kmh<kmh then Caps.call(a.caps,'velocity',car.index,vec3(car.lx,0,car.lz)*(kmh/3.6)) end
 end
 if (cmd.place or -1)<0 or not car.valid or not car.control or car.player then return end
 if s.placeFor==cmd.placeFor and now<s.placeAt then return end
 s.placeFor=cmd.placeFor; s.placeAt=now+K.spreadRetry
 local ok,pos=pcall(ac.trackProgressToWorldCoordinate,cmd.place)
 if not ok or not pos then if not a.placeWarned then a.placeWarned=true; note(a,'WARN','repartition: position sur le circuit indisponible',car.index+1) end return end
 Caps.call(a.caps,'startDelay',car.index,0)
 if Caps.call(a.caps,'position',car.index,pos,nil) then s.launchPending=true; s.launchAt=now+K.spreadLaunchWait; s.launchKmh=cmd.placeKmh
 elseif not a.placeWarned then a.placeWarned=true; note(a,'WARN','repartition: placement des IA indisponible (CSP)',car.index+1) end
end
-- IA accidentée retenue par impulsions courtes du compteur d'arrêt natif : un rechargement ou une coupure
-- la libère d'elle-même ; 0 la relâche dès que la piste derrière est libre.
local function hold(a,s,car,cmd,now)
 if not car.valid or not car.control or car.player then return end
 -- Beta 1.41 : retenue au bout de la voie des stands (sortie, module merge), seule exception à la règle D12 avec la
 -- retenue à l'emplacement.
 if cmd.stopHold and not car.pit or cmd.pitHold and car.inPitBox or cmd.mergeHold and car.pit and not car.inPitBox then
  -- Retenue en cours : une restitution en attente (voiture sortie de la conduite, hors piste) est annulée, sinon elle
  -- lèverait l'arrêt à chaque image.
  claim(a,s,car,now); s.reset=false
  if now-s.stopAt>=K.stopPulsePeriod and a.caps.stop.available and Caps.call(a.caps,'stop',car.index,K.stopPulse) then
   if not s.stop then a.recoveryDirty=true end; s.stop=true; s.stopAt=now
  end
 elseif s.stop and Caps.restoreCall(a.caps,'stop',car.index,0) then s.stop=false; s.stopAt=-math.huge; a.recoveryDirty=true end
end
-- Drapeau du joueur imposé (ac.FlagType) : wanted vrai ou faux (jaune natif du HUD, préférence d'origine), ou une
-- valeur des panneaux lumineux du circuit (Beta 1.32 ; reason : sa raison au journal ; now : tenue minimale).
-- Changement écrit aussitôt vers plus important, vers moins important ou rendu à AC après K.lightsHold s (les
-- configurations des circuits ignorent un état trop bref) ; sans now, aussitôt.
local function flagText(value,reason) return string.format('panneaux lumineux du circuit: %s (%s)',Lights.names[value] or tostring(value),reason~='' and reason or 'drapeau du HUD') end
-- Beta 1.34 : drapeau voulu mais non écrit (capacité absente ou en échec, drapeau natif d'AC à respecter) : noté une
-- fois par valeur et par cause, pour que la vérification en jeu dise pourquoi les panneaux restent éteints.
-- Beta 1.35 : aucune chaîne construite tant que la même cause dure (comparaison de la valeur, de la cause et de son
-- détail) ; oublié à chaque nouvelle session.
local function unwritten(a,value,cause,detail,lights)
 if a.flagBlocked and a.flagBlockedValue==value and a.flagBlockedCause==cause and a.flagBlockedDetail==detail then return end
 a.flagBlocked=true; a.flagBlockedValue=value; a.flagBlockedCause=cause; a.flagBlockedDetail=detail
 note(a,'INFO',string.format('%s: %s voulu, non ecrit (%s %s)',lights and 'panneaux lumineux du circuit' or 'drapeau HUD du joueur',Lights.names[value] or tostring(value),cause,tostring(detail)),-1)
end
-- Rouge (5, le drapeau noir de l'affichage d'AC) écrit seulement avec les drapeaux d'AC masqués : réglage de CSP relu
-- au moment d'écrire (au plus toutes les K.flagsHiddenRead s), jamais une valeur périmée.
local function redHidden(a,now)
 local t=now or 0
 if t>=(a.hiddenReadAt or -math.huge) then
  a.hiddenReadAt=t+K.flagsHiddenRead
  local ok,value=pcall(readRaceFlagsHidden,a)
  if ok and type(value)=='boolean' then a.raceFlagsHidden=value elseif ok and type(value)=='number' then a.raceFlagsHidden=value~=0 end
 end
 return a.raceFlagsHidden==true
end
-- Drapeau natif libre : aucun, ou le drapeau de départ d'AC, qu'AC peut tenir longtemps (toute la session en hotlap) ;
-- en 1.32, seul « aucun » l'était et un départ tenu bloquait les panneaux toute la course sans rien dire.
local function nativeFree(f) return f==K.flagNone or f==K.flagStart end
-- Beta 1.47 (Monza, 4 novembre, 17:26) : après « rendus a AC » à la relance d'une session, CSP affichait encore le rouge
-- écrit par l'app (5, le noir d'AC) ; l'app le prenait pour un drapeau noir natif : plus rien n'était écrit (« drapeau
-- natif 5 ») et l'overlay restait sur le drapeau noir. Après une restitution, une valeur affichée égale à la dernière
-- écrite par l'app est la sienne : restitution renvoyée (toutes les K.flagLeftoverEvery images, K.flagLeftoverTries
-- fois), jamais lue comme un drapeau natif ; au bout des essais, laissée à AC (un vrai drapeau noir d'AC reste donc
-- respecté) ; oubliée dès que la valeur affichée change.
function M.flagReleased(a)
 if a.flagLast and a.flagLast~=K.flagNone and a.flagLast~=K.flagStart then a.flagLeftover=true; a.flagLeftoverTries=0; a.flagLeftoverFrames=0 end
end
function M.flagMine(a,frame) return a.flagOverride or a.flagLeftover==true and frame.flag==a.flagLast end
local function leftover(a,frame,value)
 if not a.flagLeftover then return end
 if frame.flag~=a.flagLast then a.flagLeftover=false; return end
 if value~=K.flagNone then return end
 a.flagLeftoverFrames=(a.flagLeftoverFrames or 0)+1
 if a.flagLeftoverFrames<K.flagLeftoverEvery then return end
 a.flagLeftoverFrames=0; a.flagLeftoverTries=(a.flagLeftoverTries or 0)+1
 if a.flagLeftoverTries==1 then note(a,'INFO',string.format('panneaux lumineux du circuit: drapeau %d de l app encore affiche apres restitution, restitution renvoyee',a.flagLast),-1) end
 Caps.restoreCall(a.caps,'flag',-1,K.flagNone)
 -- Au bout des essais : AC garde sa dernière valeur tant qu'il ne la change pas lui-même (blanc, 6, resté affiché à Spa
 -- le 4 novembre à 11:24) ; le drapeau de départ d'AC (celui qu'AC tient en course) est écrit puis rendu : jamais un
 -- rouge ou un noir laissé à l'écran.
 if a.flagLeftoverTries>=K.flagLeftoverTries then
  a.flagLeftover=false
  if Caps.call(a.caps,'flag',-1,K.flagStart) then Caps.restoreCall(a.caps,'flag',-1,K.flagNone) end
  note(a,'WARN',string.format('panneaux lumineux du circuit: drapeau %d toujours affiche apres %d restitutions, remplace par le drapeau de depart d AC',a.flagLast,a.flagLeftoverTries),-1)
  a.flagLast=K.flagStart
 end
end
function M.flag(a,frame,wanted,reason,now,hold)
 if not a.allowed or frame.online or frame.replay or frame.paused then return end
 local value=wanted==true and K.flagCaution or type(wanted)=='number' and wanted or K.flagNone
 local lights=reason~=nil and reason~=''
 -- Tenue réglée dans la section Panneaux lumineux (Beta 1.37) ; K.lightsHold sans réglage.
 local held=now==nil or now-a.flagAt>=(hold or K.lightsHold)
 local cap=a.caps.flag
 if value==K.flagStop and lights and not redHidden(a,now) then value=K.flagCaution end
 if value==K.flagNone then a.flagBlocked=nil end
 leftover(a,frame,value)
 if value~=K.flagNone and not a.flagOverride then
  -- Jamais par-dessus un drapeau natif (bleu, blanc, damier, noir, pénalité) : sur le jaune natif, seulement le jaune ou
  -- le rouge.
  local free=nativeFree(frame.flag) or a.flagLeftover==true and frame.flag==a.flagLast
   or frame.flag==K.flagCaution and (value==K.flagCaution or value==K.flagStop)
  if not cap.available then unwritten(a,value,'capacite',cap.reason,lights)
  elseif not free then unwritten(a,value,'drapeau natif',frame.flag,lights)
  elseif Caps.call(a.caps,'flag',-1,value) then
   a.flagOverride=true; a.flagValue=value; a.flagAt=now or -math.huge; a.recoveryDirty=true; a.flagBlocked=nil; a.flagLast=value; a.flagEver=true; a.flagLeftover=false
   note(a,'INFO',lights and flagText(value,reason) or 'drapeau HUD du joueur: jaune',-1)
  else unwritten(a,value,'echec:',cap.error,lights) end
 elseif value~=K.flagNone and a.flagOverride and value~=a.flagValue then
  if held or (Lights.rank[value] or 0)>(Lights.rank[a.flagValue] or 0) then
   if Caps.call(a.caps,'flag',-1,value) then a.flagValue=value; a.flagAt=now or -math.huge; a.flagBlocked=nil; a.flagLast=value; a.flagEver=true; note(a,'INFO',flagText(value,reason or ''),-1)
   else unwritten(a,value,cap.available and 'echec:' or 'capacite',cap.available and cap.error or cap.reason,lights) end
  end
 elseif value==K.flagNone and a.flagOverride and held and Caps.restoreCall(a.caps,'flag',-1,K.flagNone) then
  a.flagOverride=false; a.flagValue=K.flagNone; a.flagAt=now or -math.huge; a.recoveryDirty=true; M.flagReleased(a)
  note(a,'INFO',now and 'panneaux lumineux du circuit: rendus a AC' or 'drapeau HUD du joueur: rendu a AC',-1)
 end
end
-- Capacités en échec (Beta 1.34) : première erreur et coupure (après K.capabilityFailures échecs) notées une fois
-- par capacité et par lancement ; jusque-là, un échec ne laissait aucune trace.
function M.reportCaps(a)
 local caps=a.caps
 for _,name in ipairs(Caps.names) do
  local cap=caps[name]
  if cap.failures>0 and not cap.noted then cap.noted=true; note(a,'WARN',string.format('capacite %s: echec (%s)',name,cap.error),-1) end
  if cap.reason=='failures' and not cap.notedOff then cap.notedOff=true; note(a,'WARN',string.format('capacite %s: coupee apres %d echecs',name,cap.failures),-1) end
 end
end
-- Places de la grille du circuit (Beta 1.34) : nœuds AC_START_0.. du modèle 3D ; abscisse sur la piste et position
-- latérale normalisée (+1 à droite), une fois par circuit, rien d'écrit. nil si CSP ne les donne pas.
local function gridNode(k)
 local ref=ac.findNodes('AC_START_'..k)
 if not ref or not callable(ref.size) or ref:size()<1 then return nil end
 local m=ref:getWorldTransformationRaw(); if not m then return nil end
 local p=ac.worldCoordinateToTrack(m.position)
 return p and U.finite(p.x) and U.finite(p.z) and {spline=p.z%1,lateral=p.x} or nil
end
function M.gridNodes(a,track)
 if a.gridNodesFor==track then return a.gridNodes end
 a.gridNodesFor=track; a.gridNodes=nil
 if not callable(ac.findNodes) or not callable(ac.worldCoordinateToTrack) then return nil end
 local list={}
 for k=0,K.maxCars-1 do
  local ok,slot=pcall(gridNode,k)
  if not ok or not slot then break end
  list[#list+1]=slot
 end
 if #list>0 then a.gridNodes=list end
 return a.gridNodes
end
-- Panneaux lumineux du circuit (Beta 1.32) : configuration du circuit (ext_config.ini du circuit et de sa variante,
-- fichiers inclus voisins) et celles de CSP (config/tracks/<circuit>.ini, loaded/<circuit>.ini), une fois par
-- circuit. Détecté : une section active s'allume sur une condition lue sur FLAG_TYPE. Rien d'écrit.
local function folder(id) if not ac.FolderID or not ac.FolderID[id] then return nil end local ok,root=pcall(ac.getFolder,ac.FolderID[id]); return ok and type(root)=='string' and root~='' and root or nil end
-- Beta 1.41 (Melbourne, layout_f1_2026 : « [INCLUDE: ../../common/...] » ignorées, panneaux non détectés) : fichiers
-- inclus résolus comme CSP, par rapport au dossier du fichier qui les inclut (segments « .. » résolus), « common/... »
-- dans la configuration des circuits de CSP, « extension/... » aussi depuis le dossier d'AC ; seulement dans le dossier
-- du circuit ou dans la configuration de CSP (jamais un chemin absolu ni une sortie de ces dossiers).
local function normalPath(path)
 local parts={}
 for part in path:gsub('/','\\'):gmatch('[^\\]+') do
  if part=='..' then if #parts<=1 then return nil end; parts[#parts]=nil
  elseif part~='.' then parts[#parts+1]=part end
 end
 return #parts>0 and table.concat(parts,'\\') or nil
end
local function inside(path,roots) local low=path:lower(); for _,r in ipairs(roots) do if low:sub(1,#r)==r then return true end end return false end
local function lightsLoad(path)
 local ok,text=pcall(io.load,path)
 if ok and type(text)=='string' and text~='' and #text<=K.lightsBytes then return text end
 return nil
end
local function lightsRead(track)
 if type(track)~='string' or track=='' or not track:match('^[%w_%-%.]+$') or track:find('..',1,true) or not io or type(io.load)~='function' then return nil,'' end
 local tracks,config=folder('ContentTracks'),folder('ExtCfgSys')
 local root=folder('Root') or tracks and tracks:match('^(.*)\\[Cc][Oo][Nn][Tt][Ee][Nn][Tt]\\[Tt][Rr][Aa][Cc][Kk][Ss]$') or config and config:match('^(.*)\\[Ee][Xx][Tt][Ee][Nn][Ss][Ii][Oo][Nn]\\[Cc][Oo][Nn][Ff][Ii][Gg]$')
 local okLayout,layout=pcall(ac.getTrackLayout); if not okLayout or type(layout)~='string' or not layout:match('^[%w_%-%.]*$') or layout:find('..',1,true) then layout='' end
 local list,roots={},{}
 if tracks then
  list[#list+1]=tracks..'\\'..track..'\\extension\\ext_config.ini'
  if layout~='' then list[#list+1]=tracks..'\\'..track..'\\'..layout..'\\extension\\ext_config.ini' end
  local r=normalPath(tracks..'\\'..track); if r then roots[#roots+1]=r:lower()..'\\' end
 end
 if config then
  list[#list+1]=config..'\\tracks\\'..track..'.ini'; list[#list+1]=config..'\\tracks\\loaded\\'..track..'.ini'
  local r=normalPath(config); if r then roots[#roots+1]=r:lower()..'\\' end
 end
 -- Conditions communes de CSP (RACING_FLAG) : définitions seulement, jamais une section allumée à elles seules.
 local out={defs={},uses={},includes={}}; local found,seen='',{}
 local info={read=0,bytes=0,missing=0,outside=0,limit=0}
 if config then local text=lightsLoad(config..'\\tracks\\common\\conditions.ini'); if text then Lights.scan(text,{defs=out.defs,uses={},includes={}}) end end
 -- File : fichiers à lire ; chaque inclusion forme un groupe de chemins possibles (le premier lu suffit).
 local queue,groups={},{}
 for _,path in ipairs(list) do queue[#queue+1]={path=normalPath(path) or path} end
 local k=1
 while k<=#queue and found=='' do
  local item=queue[k]; k=k+1
  local g=item.group; local key=item.path:lower()
  if g and g.hit then g.pending=g.pending-1
  elseif seen[key]~=nil then if g then g.pending=g.pending-1; g.tried=true; g.hit=seen[key] end
  elseif info.read<K.lightsFiles and info.bytes<K.lightsTotalBytes then
   local text=lightsLoad(item.path)
   seen[key]=text~=nil
   if g then g.pending=g.pending-1; g.tried=true; g.hit=text~=nil end
   if text then
    info.read=info.read+1; info.bytes=info.bytes+#text
    local before=#out.includes
    Lights.scan(text,out)
    if Lights.equipped(out) then found=item.path:match('[^\\]+\\[^\\]+$') or item.path end
    local dir=item.path:match('^(.*)\\[^\\]+$') or ''
    for n=before+1,#out.includes do
     local name=(out.includes[n]:gsub('/','\\'))
     local group={pending=0,hit=false}; groups[#groups+1]=group
     if not name:find(':',1,true) and name:sub(1,1)~='\\' then
      local low=name:lower(); local candidates
      if low:find('^common\\') then candidates={config and config..'\\tracks\\'..name}
      else candidates={dir..'\\'..name,low:find('^extension\\') and root and root..'\\'..name or nil} end
      for c=1,2 do
       local p=candidates[c] and normalPath(candidates[c])
       if p and inside(p,roots) then group.pending=group.pending+1; queue[#queue+1]={path=p,group=group} end
      end
     end
    end
   end
  end
 end
 -- Diagnostic (journal, circuit non détecté) : inclusions jamais lues, et pourquoi.
 for _,g in ipairs(groups) do
  if not g.hit then
   if g.pending>0 then info.limit=info.limit+1 elseif g.tried then info.missing=info.missing+1 else info.outside=info.outside+1 end
  end
 end
 return Lights.equipped(out),found,info
end
function M.trackLights(a,track)
 if a.trackLightsFor==track then return a.trackLights end
 a.trackLightsFor=track
 local ok,detected,source,info=pcall(lightsRead,track)
 if ok then a.trackLights=detected; a.trackLightsSource=source or '' else a.trackLights=nil; a.trackLightsSource='' end
 -- Beta 1.41 : non détecté, ce qui a été lu (texte construit une fois par circuit).
 a.trackLightsDetail=ok and detected==false and type(info)=='table' and string.format(' (%d fichier(s) lu(s), inclusions non lues : %d introuvable(s), %d hors du circuit et de CSP, %d au-dela de la limite)',info.read,info.missing,info.outside,info.limit) or ''
 M.readFlagsHidden(a)
 return a.trackLights
end
-- Double appel de phares visible, jamais aux stands ; rien à restituer (impulsions d'une image).
local function flash(a,s,car,cmd,now)
 local event=cmd.flashEvent or 0
 if event~=s.flashEvent then s.flashEvent=event; s.flashPulses=K.aiFlashPulses; s.flashAt=now end
 if s.flashPulses>0 and now>=s.flashAt then
  if car.valid and car.control and not car.player and not car.pit and a.caps.flash.available and Caps.call(a.caps,'flash',car.index,s.brake or 0) then
   s.flashPulses=s.flashPulses-1; s.flashAt=now+K.aiFlashInterval
  else s.flashPulses=0 end
 end
end
-- Voiture de sécurité : ramenée une fois à son stand si elle est en piste, garée sans pilote par impulsions,
-- rendue à l'IA dès qu'elle est libérée.
-- Dossier de la livrée « safety » du modèle (content/cars/<modèle>/skins), cherché une fois par modèle.
local function safetySkin(a,model)
 a.skinFolders=a.skinFolders or {}
 if a.skinFolders[model]==nil then
  a.skinFolders[model]=false
  pcall(function()
   local root=ac.getFolder(ac.FolderID.ContentCars)..'/'..model..'/skins'
   io.scanDir(root,'*',function(name,attributes)
    if not a.skinFolders[model] and type(name)=='string' and attributes~=nil and attributes.isDirectory==true and name:lower():find(K.safetySkinPattern,1,true) then a.skinFolders[model]={path=root..'/'..name,name=name} end
   end)
  end)
 end
 return a.skinFolders[model]
end
local function safety(a,s,car,cmd,now)
 if not car.valid or not car.control or car.player then return end
 -- Voiture de sécurité sans sa livrée (grille tirée au sort) : la livrée « safety » du modèle lui est appliquée, une fois.
 local identity=car.identity or car.id
 if cmd.scSkin and s.skinApplied~=identity and callable(ac.findNodes) then
  s.skinApplied=identity
  local skin=safetySkin(a,car.id)
  if skin then
   local ok=pcall(function() ac.findNodes('carRoot:'..car.index):applySkin(skin.path) end)
   if ok and car.skin~='' then s.skinOriginal=car.skin end
   note(a,ok and 'INFO' or 'WARN',ok and 'voiture de securite: livree '..skin.name..' appliquee' or 'voiture de securite: livree '..skin.name..' non appliquee',car.index+1)
  end
 elseif not cmd.scSkin and s.skinOriginal then restoreSkin(s,car) end
 if cmd.scPark or cmd.scSpeed<K.unlimitedSpeed then claim(a,s,car,now) end
 if cmd.scPark then
  -- Ramenée à son emplacement depuis la piste comme depuis la voie des stands (jamais garée en travers) ; de nouveau si
  -- elle en ressort (Beta 1.22 : garée sans pilote, une IA peut quitter son emplacement, Content Manager la placer en
  -- piste), au plus toutes les K.parkReturnPeriod s.
  if not car.inPitBox and not cmd.scHideWait and now>=s.teleportAt and a.caps.teleport.available and Caps.call(a.caps,'teleport',car.index,'PIT') then s.teleported=true; s.teleportAt=now+K.parkReturnPeriod; note(a,'INFO',cmd.parkReason=='dq' and 'IA disqualifiee: ramenee a son stand' or cmd.parkReason=='spare' and 'voiture de securite en reserve: ramenee a son stand' or 'voiture de securite: ramenee a son stand',car.index+1) end
  -- Relecture : une IA disqualifiée n'est garée qu'aux stands (ramenée par le moteur si le déplacement échoue).
  -- Beta 1.48 : voiture de sécurité (ou de réserve) garée seulement à son emplacement (jamais en travers de la piste
  -- après un retour au stand manqué), sauf retour au stand impossible (CSP) ; IA disqualifiée : aux stands.
  local where=cmd.parkReason=='dq' and (car.pit or car.inPitBox) or cmd.parkReason~='dq' and (car.inPitBox or not a.caps.teleport.available)
  -- Beta 1.50 : voiture de sécurité en service retenue à son emplacement par l'attente native d'AC (départ différé de
  -- K.scHoldTime s, freinage forcé de K.scHoldStop s, renouvelés toutes les K.scHoldPeriod s), jamais garée sans pilote : libérée, elle
  -- repart d'elle-même par la voie des stands (garée sans pilote, elle n'en sortait jamais). Garée sans pilote seulement
  -- après K.scEscapeMax sorties de son emplacement malgré l'attente.
  if cmd.parkReason=='sc' and (s.scEscapes or 0)<K.scEscapeMax and not s.parked then
   if car.inPitBox then
    if now>=(s.scHoldAt or -math.huge) or s.scHoldAt-now>K.scHoldPeriod then
     s.scHoldAt=now+K.scHoldPeriod; Caps.call(a.caps,'startDelay',car.index,K.scHoldTime); Caps.call(a.caps,'stop',car.index,K.scHoldStop)
     if not s.scHeld then s.scHeld=true; a.recoveryDirty=true; note(a,'INFO','voiture de securite: retenue a son emplacement (attente d AC), prete a sortir par la voie des stands',car.index+1) end
    end
   elseif s.scHeld then
    s.scHeld=false; s.scEscapes=(s.scEscapes or 0)+1
    note(a,'WARN',string.format('voiture de securite: a quitte son emplacement malgre l attente (%d / %d)%s',s.scEscapes,K.scEscapeMax,s.scEscapes>=K.scEscapeMax and ', garee sans pilote desormais' or ''),car.index+1)
   end
  elseif now>=s.parkAt and a.caps.park.available and where and Caps.call(a.caps,'park',car.index,true) then
   if not s.parked then a.recoveryDirty=true; note(a,'INFO',cmd.parkReason=='dq' and 'IA disqualifiee: garee jusqu a la fin de la session' or cmd.parkReason=='spare' and 'voiture de securite en reserve: garee sans pilote' or 'voiture de securite: garee sans pilote',car.index+1) end; s.parked=true; s.parkAt=now+K.parkPeriod
  end
 else
  s.teleported=false; s.teleportAt=-math.huge; s.scHeld=false; s.scHoldAt=-math.huge
  if s.parked and Caps.restoreCall(a.caps,'park',car.index,false) then s.parked=false; s.parkAt=-math.huge; a.recoveryDirty=true end
  -- Beta 1.25 : libérée mais encore à son emplacement (en course, elle n'en sortait jamais seule) : réveillée, départ
  -- immédiat, aucun freinage forcé, aucun arrêt demandé, toutes les K.scKickPeriod s tant qu'elle y reste ; sa sortie
  -- est notée.
  if cmd.scRelease and car.inPitBox then
   if now>=(s.scKickAt or -math.huge) then
    s.scKickAt=now+K.scKickPeriod
    if not s.scReleasedAt then s.scReleasedAt=now; Caps.call(a.caps,'pit',car.index,false) end
    Caps.call(a.caps,'awake',car.index); Caps.call(a.caps,'startDelay',car.index,0); Caps.call(a.caps,'stop',car.index,0)
   end
  elseif cmd.scRelease and s.scReleasedAt then
   note(a,'INFO',string.format('voiture de securite: sortie de son stand apres %.1f s',now-s.scReleasedAt),car.index+1); s.scReleasedAt=nil
  elseif not cmd.scRelease then s.scReleasedAt=nil; s.scKickAt=-math.huge end
 end
 -- Aucune commande dans la voie des stands (règle D12) : le limiteur natif s'y applique déjà.
 -- Garée, sa limite reste posée (sans effet à l'arrêt) jusqu'à la restitution générale.
 if cmd.scSpeed<K.unlimitedSpeed and not car.pit then send(a,s,'speed',car.index,cmd.scSpeed,K.levelEpsilon) end
end
-- Dépannage : une IA immobile en piste est ramenée une seule fois jusqu'à son stand (jamais le joueur).
local function recover(a,s,car,cmd)
 if not cmd.recover then s.redTeleported=false; return end
 if car.valid and car.control and not car.player and not car.pit and not s.redTeleported and a.caps.teleport.available then
  if Caps.call(a.caps,'teleport',car.index,'PIT') then
   s.redTeleported=true
   -- Relecture : une IA lente et endommagée roule encore (jamais « immobile ») ; le déplacement la répare.
   if cmd.recoverReason=='lente et endommagee' then note(a,'INFO',string.format('IA lente et endommagee depannee a son stand, reparee par le deplacement (lente depuis %.0f s)',cmd.recoverStill or 0),car.index+1)
   else note(a,'INFO',string.format('IA immobile depannee a son stand (%s, immobile depuis %.0f s)',cmd.recoverReason or '?',cmd.recoverStill or 0),car.index+1) end
  end
 end
end
-- Drapeau noir du joueur levé (déchargement, désactivation, nouvelle session) ; jamais pendant une simple pause des
-- commandes (recalibration, sécurité).
function M.releaseBlackFlag(a)
 if a.blackFlag and Caps.restoreCall(a.caps,'penalty',-1,0,ac.PenaltyType and ac.PenaltyType.ReleaseBlackFlag or K.penaltyReleaseBlackFlag) then
  a.blackFlag=false; note(a,'INFO','drapeau noir leve',-1)
 end
end
-- Pénalité du joueur décidée par le moteur : écrite une seule fois par décision ; une écriture refusée est retentée à
-- l'image suivante tant que la capacité reste disponible (trois échecs la désactivent).
function M.penalty(a,frame,t)
 if t.requestId==(a.penaltyServed or 0) then return end
 if not a.allowed or frame.online or frame.replay or frame.paused or frame.player==0 then return end
 local written
 if t.kind=='dq' then
  written=Caps.call(a.caps,'penalty',-1,-1,ac.PenaltyType and ac.PenaltyType.BlackFlag or K.penaltyBlackFlag)
  if written then a.blackFlag=true; note(a,'INFO','drapeau noir applique',frame.player) end
 else
  written=Caps.call(a.caps,'penalty',-1,t.seconds)
  if written then note(a,'INFO',string.format('penalite appliquee: coupure des gaz %.0f s',t.seconds),frame.player) end
 end
 if written or not a.caps.penalty.available then a.penaltyServed=t.requestId end
end
-- Bip « DRS disponible » : fichier son de l'app, joué sans effet 3D ; un événement par bip, le précédent libéré.
local function disposeBeep(a) if a.beepEvent then pcall(function() a.beepEvent:dispose() end); a.beepEvent=nil end end
function M.beep(a,frame,d)
 if d.beepId==(a.beepServed or 0) then return end
 a.beepServed=d.beepId
 if frame.online or frame.replay or frame.paused or not ac.AudioEvent or not callable(ac.dirname) then return end
 disposeBeep(a)
 local ok,event=pcall(ac.AudioEvent.fromFile,{filename=ac.dirname()..'/'..K.drsBeepFile,use3D=false,loop=false},false)
 -- Même niveau quelle que soit la caméra (CSP réduit par défaut à 25 % un son d'app entendu depuis le cockpit), sur le
 -- canal principal : seul le volume général du jeu s'applique.
 local function play()
  event.cameraInteriorMultiplier=1; event.cameraExteriorMultiplier=1; event.cameraTrackMultiplier=1; event.volume=d.volume or 1
  if event.setVolumeChannel and ac.AudioChannel then event:setVolumeChannel(ac.AudioChannel.Main) end
  event:start()
 end
 if ok and event and pcall(play) then a.beepEvent=event
 else
  if ok and event then a.beepEvent=event; disposeBeep(a) end
  if not a.beepFailed then a.beepFailed=true; note(a,'WARN','bip DRS: son indisponible',-1) end
 end
end
-- Bips du temps delta : fichier son de l'app, un seul événement créé une fois et relancé à chaque bip (jusqu'à
-- plusieurs par seconde), même niveau quelle que soit la caméra, canal principal.
function M.deltaBeep(a,frame,d)
 if d.beepId==(a.deltaServed or 0) then return end
 a.deltaServed=d.beepId
 if frame.online or frame.replay or frame.paused or a.deltaFailed or not ac.AudioEvent or not callable(ac.dirname) then return end
 if not a.deltaEvent then
  local ok,event=pcall(ac.AudioEvent.fromFile,{filename=ac.dirname()..'/'..K.deltaBeepFile,use3D=false,loop=false},false)
  if ok and event then a.deltaEvent=event
   pcall(function() if event.setVolumeChannel and ac.AudioChannel then event:setVolumeChannel(ac.AudioChannel.Main) end end)
  else a.deltaFailed=true; note(a,'WARN','bip delta: son indisponible',-1); return end
 end
 local event=a.deltaEvent
 local function play()
  event.cameraInteriorMultiplier=1; event.cameraExteriorMultiplier=1; event.cameraTrackMultiplier=1; event.volume=d.volume or 1
  if event.stop then event:stop() end
  event:start()
 end
 if not pcall(play) then a.deltaFailed=true; pcall(function() event:dispose() end); a.deltaEvent=nil; note(a,'WARN','bip delta: son indisponible',-1) end
end
-- DRS coupé par les règles de course (toutes les voitures, joueur compris), rendu dès que la règle le permet ; une
-- instance précédente arrêtée net (repère ;D de la reprise) : tout est rendu une fois. Sans commandes (app inactive,
-- aucune voiture suivie) : tout est rendu.
function M.drs(a,frame,commands,now)
 if not a.allowed or frame.online or frame.replay or frame.paused then return end
 if a.drsRelease and frame.count>0 then
  for i=1,frame.count do Caps.restoreCall(a.caps,'drs',frame.cars[i].index,false) end
  a.drsRelease=false; a.recoveryDirty=true
 end
 local any=false
 for i=1,frame.count do
  local car=frame.cars[i]; local s=a.cars[i]; local cmd=commands and commands[i]
  local want=cmd~=nil and cmd.drsBlock==true
  if want~=s.drsBlocked then
   if want then if Caps.call(a.caps,'drs',car.index,true) then s.drsBlocked=true; a.recoveryDirty=true end
   elseif Caps.restoreCall(a.caps,'drs',car.index,false) then s.drsBlocked=false; a.recoveryDirty=true end
  end
  any=any or s.drsBlocked
  -- DRS des IA : ouverture demandée par le moteur au plus une fois par seconde par voiture ; fermeture au freinage
  -- aussitôt (quelques essais par seconde au plus).
  local open=cmd and cmd.drsWant
  if open~=nil and car.valid and car.control and not car.player and now>=s.drsAt+(open and K.drsAiRetry or K.drsAiCloseRetry) then
   if Caps.call(a.caps,'drsActive',car.index,open) then s.drsAt=now end
  end
 end
 a.drsAny=any
end
local function releaseDrs(a,frame)
 for i=1,frame.count do local s=a.cars[i]; if s.drsBlocked and Caps.restoreCall(a.caps,'drs',frame.cars[i].index,false) then s.drsBlocked=false; a.recoveryDirty=true end end
 a.drsAny=false
end
M.releaseDrs=releaseDrs
-- Overlay en jeu (Beta 1.25) : case de session d'AC (tour, temps restant, RACE OVER) masquée ou rendue ; taille de
-- l'écran ; messages d'AC écoutés et, sur demande, masqués. Un Disposable de CSP s'appelle pour être annulé.
function M.sessionBox(hide) return callable(ac.disableExtraHUDElements) and pcall(ac.disableExtraHUDElements,'sessionTime',hide)==true end
function M.screen()
 if not callable(ac.getUI) then return nil end
 local ok,s=pcall(ac.getUI)
 if ok and s and s.windowSize and U.finite(s.windowSize.x) and s.windowSize.x>0 then return s.windowSize end
 return nil
end
function M.listenMessages(fn)
 if not callable(ac.onMessage) then return nil end
 local ok,d=pcall(ac.onMessage,fn); return ok and d or nil
end
function M.blockMessages()
 if not callable(ac.blockSystemMessages) then return nil end
 local ok,d=pcall(ac.blockSystemMessages,'.'); return ok and d or nil
end
function M.dispose(d) if type(d)=='function' or callable(d) then pcall(d) end end
-- Refonte Racing 26 (Beta 1.35) : polices livrées avec l'app (fonts/, licence OFL) et icône de l'en-tête. Dossier des
-- polices relatif à l'app (« fonts ») s'il est complet, sinon nil (Segoe UI, noté une fois au journal) ; chemin
-- complet de l'icône, ou nil.
local fontFiles={'barlow/Barlow-Regular.ttf','barlow/Barlow-SemiBold.ttf','barlowcondensed/BarlowCondensed-SemiBold.ttf',
 'barlowcondensed/BarlowCondensed-Bold.ttf','barlowcondensed/BarlowCondensed-ExtraBoldItalic.ttf','jetbrainsmono/JetBrainsMono-Medium.ttf'}
local function scriptFolder()
 if not callable(ac.getFolder) or not ac.FolderID or not ac.FolderID.ScriptOrigin then return nil end
 local ok,dir=pcall(ac.getFolder,ac.FolderID.ScriptOrigin)
 return ok and type(dir)=='string' and dir~='' and dir or nil
end
function M.fontDir(a)
 local dir=scriptFolder()
 local ok,present=pcall(function()
  if not dir or not io or type(io.fileExists)~='function' then return false end
  for _,file in ipairs(fontFiles) do if not io.fileExists(dir..'/fonts/'..file) then return false end end
  return true
 end)
 if ok and present==true then return 'fonts' end
 if a then note(a,'WARN','polices de l interface absentes (fonts/) : Segoe UI',-1) end
 return nil
end
function M.appFile(name)
 local dir=scriptFolder()
 if not dir or not io or type(io.fileExists)~='function' then return nil end
 local ok,present=pcall(io.fileExists,dir..'/'..name)
 return ok and present==true and dir..'/'..name or nil
end
-- Journal de session sur disque (Documents/Assetto Corsa/logs) : un fichier par lancement du jeu, trois précédents
-- conservés. Un rechargement de l'app dans le même lancement (repère dans ac.store) poursuit le même fichier.
function M.journalOpen(a)
 a.journalPath=nil; a.journalBytes=0
 local ok=pcall(function()
  if not io or type(io.open)~='function' or not ac.getFolder or not ac.FolderID or not ac.FolderID.Logs then return end
  local root=ac.getFolder(ac.FolderID.Logs)
  if type(root)~='string' or root=='' then return end
  local base=root..'/AdvancedIA'
  local continued=M.loadText(K.journalMarker)=='1' and type(io.fileExists)=='function' and io.fileExists(base..'.log')
  if not continued and type(io.fileExists)=='function' and type(io.move)=='function' then
   for n=K.journalKeep-1,1,-1 do local from=base..'.'..n..'.log'; if io.fileExists(from) then io.move(from,base..'.'..(n+1)..'.log',true) end end
   if io.fileExists(base..'.log') then io.move(base..'.log',base..'.1.log',true) end
  end
  local f=io.open(base..'.log',continued and 'a' or 'w'); if not f then return end
  if continued and f.seek then a.journalBytes=tonumber(f:seek('end')) or 0 end
  f:close(); a.journalPath=base..'.log'; M.storeText(K.journalMarker,'1')
 end)
 return ok and a.journalPath~=nil
end
function M.clockText()
 if not os or type(os.date)~='function' then return '----------' end
 local ok,text=pcall(os.date,'%Y-%m-%d %H:%M:%S')
 return ok and type(text)=='string' and text or '----------'
end
function M.journalWrite(a,text)
 if not a.journalPath or type(text)~='string' or text=='' then return false end
 local full=a.journalBytes+#text>K.journalMaxBytes
 if full then text='=== journal limite a '..K.journalMaxBytes..' octets pour ce lancement ===\n' end
 local ok=pcall(function() local f=io.open(a.journalPath,'a'); f:write(text); f:close() end)
 if ok then a.journalBytes=a.journalBytes+#text else a.journalFailures=(a.journalFailures or 0)+1 end
 if full or not ok and a.journalFailures>=K.capabilityFailures or a.journalBytes>=K.journalMaxBytes then a.journalPath=nil end
 return ok
end
function M.storeText(key,text) if ac.store then return pcall(ac.store,key,text) end return false end
function M.loadText(key) if not ac.load then return nil end local ok,text=pcall(ac.load,key); return ok and text or nil end
function M.message(title,text) if callable(ac.setMessage) then return pcall(ac.setMessage,title,text) end return false end
-- Message témoin du masquage des messages d'AC (Beta 1.26), le plus bref possible.
function M.probeMessage(title) if callable(ac.setMessage) then return pcall(ac.setMessage,title,'',nil,K.probeTime) end return false end
-- Fichier d'un dossier de CSP (cfg/extension, cfg/extension/state, extension/config) ; nil sans ce dossier.
local function folderFile(id,name)
 if not ac.getFolder or not ac.FolderID or not ac.FolderID[id] then return nil end
 local ok,root=pcall(ac.getFolder,ac.FolderID[id])
 return ok and type(root)=='string' and root~='' and root..'\\'..name or nil
end
-- AI flood de CSP (Beta 1.26) : réglage de l'utilisateur (cfg/extension/new_behaviour.ini, absent tant qu'il n'a rien
-- changé) et défauts de CSP (extension/config/new_behaviour.ini) ; écriture sûre (fichier temporaire, puis remplacement).
local function floodPath(id) return folderFile(id,'new_behaviour.ini') end
function M.floodRead()
 if not io or type(io.load)~='function' then return nil,nil,false end
 local user,system=floodPath('ExtCfgUser'),floodPath('ExtCfgSys')
 if not user then return nil,nil,false end
 local ok,text=pcall(io.load,user)
 local okSystem,defaults=false,nil
 if system then okSystem,defaults=pcall(io.load,system) end
 return ok and type(text)=='string' and text or '',okSystem and type(defaults)=='string' and defaults or nil,ok and type(io.save)=='function'
end
-- Beta 1.39 : reste new_behaviour.ini.bak laissé dans cfg/extension par les versions d'avant la 1.38 (io.replaceFile),
-- effacé au lancement ; ce seul fichier. Vrai s'il a été effacé.
function M.floodLeftover()
 local path=floodPath('ExtCfgUser')
 if not path or not io or type(io.fileExists)~='function' or type(io.deleteFile)~='function' then return false end
 local bak=path..'.bak'
 local okExists,present=pcall(io.fileExists,bak)
 if not (okExists and present==true) then return false end
 pcall(io.deleteFile,bak)
 local okAfter,still=pcall(io.fileExists,bak)
 return okAfter and still~=true
end
-- Écriture sûre d'un fichier de cfg/extension. Beta 1.38 : io.save(…, true) passe par io.replaceFile, qui laisse
-- l'ancien contenu en <fichier>.bak : ce reste est effacé après chaque écriture.
local function saveClean(path,text)
 if not path or not io or type(io.save)~='function' or type(text)~='string' then return false end
 local ok,done=pcall(io.save,path,text,true)
 if type(io.fileExists)=='function' and type(io.deleteFile)=='function' then
  local bak=path..'.bak'
  local okExists,present=pcall(io.fileExists,bak)
  if okExists and present==true then pcall(io.deleteFile,bak) end
 end
 return ok and done~=false
end
function M.floodWrite(text) return saveClean(floodPath('ExtCfgUser'),text) end
-- Options de CSP de gui.ini tenues par l'app (Beta 1.40, src/cspgui.lua) : réglage de l'utilisateur
-- (cfg/extension/gui.ini, absent tant qu'il n'a rien changé), fichier d'état de l'app (cfg/extension/state, que CSP ne
-- relit pas, hors du dossier de la mise à jour), mémoire de la partie (ac.store) et options appliquées par CSP.
local function fileText(path)
 local okExists,present=pcall(io.fileExists,path)
 if not okExists then return nil,false end
 if present~=true then return '',false end
 local ok,text=pcall(io.load,path)
 return ok and type(text)=='string' and text or nil,true
end
local function removeFile(path)
 pcall(io.deleteFile,path)
 local ok,present=pcall(io.fileExists,path)
 return ok and present~=true
end
function M.cspPort()
 local gui,state=folderFile('ExtCfgUser','gui.ini'),folderFile('ExtCfgState','ACAdvancedIA-cspgui.ini')
 local ready=gui~=nil and state~=nil and io~=nil and callable(io.load) and callable(io.save) and callable(io.fileExists) and callable(io.deleteFile)
  and ac.INIConfig~=nil and callable(ac.INIConfig.cspModule) and ac.CSPModuleID~=nil
 return {ready=ready,
  read=function() return fileText(gui) end,
  write=function(text) return saveClean(gui,text) end,
  remove=function() return removeFile(gui) end,
  loadState=function() return (fileText(state)) end,
  saveState=function(text) if text=='' then return removeFile(state) end return saveClean(state,text) end,
  loadSession=function() return M.loadText('humanai:cspgui') end,
  saveSession=function(text) M.storeText('humanai:cspgui',text) end,
  loaded=function(key)
   local ok,value=pcall(readOption,key)
   if ok and type(value)=='boolean' then return value elseif ok and type(value)=='number' then return value~=0 end
   return nil
  end}
end
-- Relecture de gui.ini par CSP (réglage changé en jeu, ou écrit par l'app).
function M.watchGui(fn)
 if not callable(ac.onCSPConfigChanged) or not ac.CSPModuleID then return nil end
 local ok,d=pcall(ac.onCSPConfigChanged,ac.CSPModuleID.GUI,fn)
 return ok and d or nil
end
function M.apply(a,frame,commands,g,now)
 if not a.allowed or frame.online or frame.replay or frame.paused then return end
 a.g=g; a.offsetSign=g.offsetSign
 for i=1,frame.count do
  local car=frame.cars[i]; local cmd=commands[i]; local s=a.cars[i]
  -- Erreur de pilotage décidée par le moteur : servie une seule fois, à une IA en piste, qu'elle soit commandée ou non
  -- (rien à rendre : la fonction native agit pendant la durée donnée).
  local mistake=(cmd.mistakeId or 0)~=(s.mistakeServed or 0); s.mistakeServed=cmd.mistakeId or 0
  if mistake and car.valid and car.control and not car.player and not car.pit and not car.offtrack and i~=a.caps.probeIndex then
   if cmd.mistakeKind=='brake' then Caps.call(a.caps,'brakeMistake',car.index,cmd.mistakeTime)
   else Caps.call(a.caps,'tractionMistake',car.index,cmd.mistakeTime,cmd.mistakeSeverity) end
  end
  -- Beta 1.42 : usure ajoutée à un pneu (méplat après un blocage), servie une seule fois à une IA en piste.
  local wear=(cmd.wearId or 0)~=(s.wearServed or 0); s.wearServed=cmd.wearId or 0
  if wear and car.valid and car.control and not car.player and not car.pit and (cmd.wearKm or 0)>0 and car.tyreKm then
   local wheel=math.floor(U.number(cmd.wearWheel,0,3,0))
   Caps.call(a.caps,'tyreKm',car.index,wheel,(car.tyreKm[wheel+1] or 0)+cmd.wearKm)
  end
  weather(a,s,car,cmd,now)
  pitRequest(a,s,car,cmd,now)
  safety(a,s,car,cmd,now)
  startDelay(a,s,car,cmd)
  place(a,s,car,cmd,now)
  recover(a,s,car,cmd)
  hold(a,s,car,cmd,now)
  -- Départ arrêté (Beta 1.34) : extinction des feux, IA réveillées (aux stands : départ immédiat).
  if cmd.gridWake and car.valid and car.control and not car.player then Caps.call(a.caps,'awake',car.index); if car.pit then Caps.call(a.caps,'startDelay',car.index,0) end end
  flash(a,s,car,cmd,now)
  local limit=math.min(cmd.speedLimit or K.unlimitedSpeed,cmd.yellowLimit or K.unlimitedSpeed)
  local wanted=(cmd.throttleLimit or 1)<1 or cmd.weatherManaged or cmd.rulePit or cmd.stopHold or cmd.pitHold or cmd.scPark or cmd.scSpeed<K.unlimitedSpeed or s.stop or s.parked or cmd.active and (cmd.levelOwned~=false or cmd.aggressionOwned~=false or cmd.cautionOwned~=false or math.abs(cmd.offset)>=K.offsetEpsilon or (g.useBrakeAssist and (cmd.brake or 0)>0) or limit<K.unlimitedSpeed)
  if not wanted and s.owned and i~=a.caps.probeIndex and i~=a.calibrationIndex then s.reset=true end
  local driven=car.valid and car.control and not car.player and not car.pit and not car.offtrack and cmd.active and wanted and i~=a.caps.probeIndex and not s.reset
  if driven then
   claim(a,s,car,now)
   if U.finite(cmd.offset) and g.offsetSign~=0 then
    local offset=U.clamp(cmd.offset,-1,1)*g.offsetSign
    if math.abs(offset-s.offset)>=K.offsetEpsilon or s.reset then
     if Caps.call(a.caps,'offset',car.index,offset,offset~=0 and g.overrideAwareness) then if U.sign(s.offset)~=U.sign(offset) then a.recoveryDirty=true end; s.offset=offset; s.reset=false; s.offsetReset=offset==0 end
    end
   elseif not U.finite(cmd.offset) then a.rejected=a.rejected+1 end
   if now-s.lastWrite>=K.writePeriod then
    if not U.finite(cmd.level) or not U.finite(cmd.aggression) or not U.finite(cmd.caution) then a.rejected=math.min(K.counterMax,a.rejected+1) end
    -- Beta 1.42 : facteur de niveau des modules (tour de sortie, panne) ; 1 = niveau du directeur inchangé.
    local scale=cmd.levelScale or 1
    local level=U.number(scale~=1 and U.finite(cmd.level) and cmd.level*math.max(K.levelScaleMin,scale) or cmd.level,0,a.caps.levelMode=='native' and 1.1 or 1,s.level or car.aiLevel)
    local previous=s.level
    field(a,s,'level',car.index,cmd.levelOwned,level,K.levelEpsilon,s.originalLevel)
    if s.level~=previous then s.levelAt=now end
    field(a,s,'aggression',car.index,cmd.aggressionOwned,U.number(cmd.aggression,0,K.maxAggression,car.aiAggression),K.aggrEpsilon,s.originalAggression)
    field(a,s,'caution',car.index,cmd.cautionOwned,U.number(cmd.caution,0.5,K.maxCaution,K.defaultCaution),K.cautionEpsilon,K.defaultCaution)
    local grip=K.gripBase; local gripOwned=false
    if g.useGripBoost and a.caps.levelMode=='grip' then grip=grip*(1+math.max(0,U.number(cmd.level,0,1.1,1)*100-100)*g.gripPerLevelPct); gripOwned=true end
    if cmd.weatherManaged and (cmd.weatherGrip or 1)>1 then grip=grip*U.number(cmd.weatherGrip,1,1.3,1); gripOwned=true end
    if gripOwned and a.caps.grip.available then
     send(a,s,'grip',car.index,grip,K.gripEpsilon)
    elseif s.grip then if Caps.restoreCall(a.caps,'grip',car.index,K.gripBase) then s.grip=nil; a.recoveryDirty=true end end
    s.lastWrite=now
   end
   local brake=g.useBrakeAssist and U.number(cmd.brake,0,K.brakeMax,0) or 0
   if a.caps.brake.available and (brake>0 or s.brake>0) then if Caps.call(a.caps,'brake',car.index,brake) then s.brake=brake end end
   local speed=U.number(limit,0,K.unlimitedSpeed,K.unlimitedSpeed)
   if speed<K.unlimitedSpeed then send(a,s,'speed',car.index,speed,K.levelEpsilon)
   elseif s.speed~=nil and Caps.restoreCall(a.caps,'speed',car.index,K.unlimitedSpeed) then s.speed=nil; a.recoveryDirty=true end
   -- Beta 1.42 : limite d'accélérateur (coupure des gaz d'une sanction, air sale, panne) ; 1 = aucune, rendue une fois.
   local throttle=U.number(cmd.throttleLimit,K.throttleMin,1,1)
   -- Relecture : rendu exactement à 1 dès qu'il revient au-dessus de 1 - K.throttleEpsilon (jamais laissé à 0,99).
   if throttle>1-K.throttleEpsilon then throttle=1 end
   if a.caps.throttle.available and (throttle<1 or (s.throttle or 1)<1) and (throttle==1 or math.abs(throttle-(s.throttle or 1))>=K.throttleEpsilon) then
    -- Relecture 1.42 (après correctifs) : pas de sauvegarde du point de reprise à chaque écriture (la reprise rend
    -- l'accélérateur à 1 pour chaque voiture reprise ; la prise en main marque déjà le point de reprise).
    if Caps.call(a.caps,'throttle',car.index,throttle) then s.throttle=throttle<1 and throttle or nil end
   end
   -- L'instantané précède les écritures : seul un niveau écrit lors d'une image précédente est relu,
   -- et seulement s'il dépasse nettement 1 ; un écrêtage se distingue alors de la tolérance de lecture.
   if now>=s.readAt and s.levelAt~=now then s.readAt=now+K.readbackPeriod
    if s.level and s.level>1+K.probeTolerance and car.aiLevel<1+K.probeTolerance then a.caps.native110=false; a.caps.probeDone=true end
   end
  elseif s.brake>0 and a.caps.brake.available and car.valid and car.control and not car.player then
   -- Frein additionnel relâché dès que la voiture n'est plus commandée (stands, hors piste, fin de manœuvre).
   if Caps.restoreCall(a.caps,'brake',car.index,0) then s.brake=0 end
  end
  -- Beta 1.42 : accélérateur rendu dès que la voiture n'est plus commandée (stands, hors piste, fin de sanction).
  if s.throttle and not driven and car.valid and car.control and not car.player then
   if not (a.caps.throttle and a.caps.throttle.available) then s.throttle=nil
   elseif Caps.restoreCall(a.caps,'throttle',car.index,1) then s.throttle=nil end
  end
 end
end
function M.register(a,release,session)
 if ac.onRelease and not a.releaseToken then local ok,t=pcall(ac.onRelease,release); if ok then a.releaseToken=t or true end end
 if ac.onSessionStart and not a.sessionToken then local ok,t=pcall(ac.onSessionStart,session); if ok then a.sessionToken=t or true end end
end
function M.unregister(a)
 disposeBeep(a)
 if a.deltaEvent then pcall(function() a.deltaEvent:dispose() end); a.deltaEvent=nil end
 if callable(a.sessionToken) then pcall(a.sessionToken) end
 if callable(a.releaseToken) then pcall(a.releaseToken) end
 a.sessionToken=nil; a.releaseToken=nil
end
function M.nextSession(a,frame)
 M.releaseBlackFlag(a); M.releaseDrs(a,frame); a.flagBlocked=nil
 -- Beta 1.47 : drapeau écrit pendant ce lancement : restitution redemandée à chaque nouvelle session (CSP a gardé le
 -- rouge, 5, après la relance d'une session à Monza ; plus rien ne le levait).
 if a.flagEver and a.allowed and not frame.online and not frame.replay and Caps.restoreCall(a.caps,'flag',-1,K.flagNone) then
  a.flagOverride=false; a.flagValue=K.flagNone; a.recoveryDirty=true; M.flagReleased(a)
 end
 for i=1,frame.count do
  local s=a.cars[i]; local car=frame.cars[i]
  if s.owned then
   if s.id~=(car.identity or car.id) then s.owned=false; s.reset=false; s.recovered=false
   else
    -- Une entrée récupérée ne connaît pas la valeur commandée : ses originaux restent ceux sauvegardés.
    if s.level and not s.recovered and math.abs(car.aiLevel-s.level)>K.levelEpsilon then s.originalLevel=car.aiLevel end
    if s.aggression and not s.recovered and math.abs(car.aiAggression-s.aggression)>K.aggrEpsilon then s.originalAggression=car.aiAggression end
    -- Voiture garée (voiture de sécurité, réserve, disqualifiée) : gardée sous l'ordre de garage, que le moteur lève
    -- lui-même ; la restituer la libérerait puis la regarerait à chaque image.
    s.reset=not s.parked; s.tyreVisit=-1
   end
  end
  -- Nouvelle session ou course recommencée : AC replace les voitures sur la grille ; une voiture à garer (voiture de
  -- sécurité, réserve) ou à dépanner est de nouveau ramenée à son stand.
  s.lastWrite=-math.huge; s.readAt=0; s.teleported=false; s.teleportAt=-math.huge; s.redTeleported=false
 end
 a.session=frame.session
end
function M.clipboard(text) if ac.setClipboardText then return pcall(ac.setClipboardText,text) end return false end
function M.checkpoint(a,frame,force)
 if not ac.store or not (a.recoveryDirty or force) or frame.replay then return end
 local rows={tostring(frame.session)..(a.flagOverride and ';F' or '')..(a.drsAny and ';D' or '')}
 for i=1,K.maxCars do
  local s=a.cars[i]
  if s.owned and s.id:match('^[%w_%-]*$') then
   rows[#rows+1]=string.format('%d,%s,%.9g,%.9g,%.9g,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d',i,s.id,s.originalLevel,s.originalAggression,s.offset,s.level and 1 or 0,s.aggression and 1 or 0,s.caution and 1 or 0,s.grip and 1 or 0,s.brake>0 and 1 or 0,s.speed and 1 or 0,s.rainHint~=nil and 1 or 0,s.rainHint==true and 1 or 0,s.originalRain and 1 or 0,s.pitRequest and 1 or 0,s.stop and 1 or 0,s.parked and 1 or 0)
  end
 end
 local ok=pcall(ac.store,'humanai:recovery',table.concat(rows,'\n')); if ok then a.recoveryDirty=false end
end
function M.recover(a,frame)
 if not ac.load then return end
 local ok,text=pcall(ac.load,'humanai:recovery')
 if not ok or type(text)~='string' or #text>K.maxZoneBytes then return end
 -- Drapeau laissé par une instance précédente : rendu à AC quelle que soit la session.
 local head=text:match('^[^\n]*') or ''
 if head:find(';F',1,true) then a.flagOverride=true end
 -- DRS laissé coupé par une instance précédente : rendu à toutes les voitures.
 if head:find(';D',1,true) then a.drsRelease=true end
 local session=text:match('^(%d+)')
 if tonumber(session)~=frame.session then return end
 for slot,id,level,aggression,offset,lc,ag,ca,gr,br,sp,rh,rv,ro,pr,st,pk in text:gmatch('\n(%d+),([%w_%-]*),([%d.eE+%-]+),([%d.eE+%-]+),([%d.eE+%-]+),([01]),([01]),([01]),([01]),([01]),?([01]?),?([01]?),?([01]?),?([01]?),?([01]?),?([01]?),?([01]?)') do
  local i=tonumber(slot); local l,aggressionValue,o=tonumber(level),tonumber(aggression),tonumber(offset)
  if i and i>=1 and i<=K.maxCars and U.finite(l) and l>=0 and l<=2 and U.finite(aggressionValue) and aggressionValue>=0 and aggressionValue<=1 and U.finite(o) and math.abs(o)<=1 then
   local s=a.cars[i]; s.owned=true; s.reset=true; s.recovered=true; s.id=id; s.originalLevel=l; s.originalAggression=aggressionValue; s.offset=o
   s.level=lc=='1' and l or nil; s.aggression=ag=='1' and aggressionValue or nil; s.caution=ca=='1' and 1 or nil; s.grip=gr=='1' and K.gripBase or nil; s.brake=br=='1' and K.brakeMax or 0
   s.speed=sp=='1' and K.unlimitedSpeed or nil
   s.offsetReset=o==0
   -- Relecture : accélérateur peut-être laissé limité par l'instance d'avant (coupure des gaz) : rendu.
   s.throttle=K.throttleMin
   if rh=='1' then s.rainHint=rv=='1' end; s.originalRain=ro=='1'; s.pitRequest=pr=='1'; s.stop=st=='1'; s.parked=pk=='1'
  end
 end
end
-- Pont vers les apps compagnes (Beta 1.46, SpotterEnginer, src/bridge.lua). App lectrice installée : dossier
-- apps/lua/<nom> avec son manifest.ini, lu une fois au lancement ; toute erreur vaut « absente » (pont jamais ouvert).
-- Beta 1.49 : réglages du menu Quick Pitstop d'AC (CSP 0.2.7 et plus) et préréglage choisi (0 = premier) ; nil et la
-- raison sinon. Lecture seule : le préréglage du joueur n'est jamais modifié.
function M.pitSpinners()
 if not ac or not callable(ac.getPitstopSpinners) then return nil,'CSP sans getPitstopSpinners' end
 local ok,out,preset=pcall(function()
  local list=ac.getPitstopSpinners()
  if type(list)~='table' then return nil,0 end
  local result={}
  for k=1,#list do
   local s=list[k]
   if s then
    local values={}
    if type(s.values)=='table' then for j=1,#s.values do values[j]=s.values[j] end end
    result[#result+1]={name=s.name,type=s.type,min=s.min,max=s.max,value=s.value,values=values}
   end
  end
  local index=0
  if callable(ac.getSim) then local sim=ac.getSim(); if sim and tonumber(sim.currentQuickPitPreset) then index=tonumber(sim.currentQuickPitPreset) end end
  return result,index
 end)
 if not ok or type(out)~='table' then return nil,'lecture refusee' end
 return out,preset
end
-- Beta 1.49 : réglages de l'ancienne app (ac.storage de apps/lua/ACAdvancedIA) présents alors que ceux d'AdvancedIA
-- n'existent pas encore (première ouverture après le changement de nom) : rien n'est copié ici (CSP lit et écrit ce
-- fichier lui-même), le pilote est seulement averti de la marche à suivre, jeu fermé.
function M.oldSettings()
 local ok,yes=pcall(function()
  if not ac or not callable(ac.getFolder) or type(ac.FolderID)~='table' or not ac.FolderID.ExtCfgState then return false end
  if not io or not callable(io.fileExists) then return false end
  local root=ac.getFolder(ac.FolderID.ExtCfgState)
  if type(root)~='string' or root=='' then return false end
  local sep=string.char(92); local dir=root..sep..'lua'..sep..'app'..sep
  return io.fileExists(dir..'ACAdvancedIA.ini')==true and io.fileExists(dir..'AdvancedIA.ini')~=true
 end)
 return ok and yes==true
end
function M.companionInstalled(name)
 if type(name)~='string' or not name:match('^[%w_%-]+$') then return false end
 local ok,yes=pcall(function()
  if not ac or not callable(ac.getFolder) or type(ac.FolderID)~='table' or not ac.FolderID.ACAppsLua then return false end
  if not io or not callable(io.fileExists) then return false end
  local root=ac.getFolder(ac.FolderID.ACAppsLua)
  if type(root)~='string' or root=='' then return false end
  return io.fileExists(root..'\\'..name..'\\manifest.ini')==true
 end)
 return ok and yes==true
end
-- Deux structures partagées entre apps Lua (ac.connect), décrites par src/bridge_layout.lua ; la clé de chacune (champ
-- « key ») évite toute collision. Sans ac.connect (autre version de CSP, bancs de mesure) : nil et la raison, rien n'est
-- publié.
local function bridgeItem(f)
 local S=ac.StructItem; local kind=f[2]
 if kind=='bool' then return S.boolean() elseif kind=='int' then return S.int32() elseif kind=='uint' then return S.uint32()
 elseif kind=='float' then return S.float() elseif kind=='double' then return S.double() elseif kind=='string' then return S.string(f[3]) end
 error('pont: type inconnu '..tostring(kind),0)
end
local function bridgeStruct(key,list)
 local t={}
 if key then t.key=ac.StructItem.key(key) end
 for k=1,#list do t[list[k][1]]=bridgeItem(list[k]) end
 return t
end
function M.bridgeOpen(layout)
 if not ac or not callable(ac.connect) or type(ac.StructItem)~='table' or type(layout)~='table' then return nil,'ac.connect absent' end
 local ok,port=pcall(function()
  local hello=ac.connect(bridgeStruct(layout.helloKey,layout.hello))
  local data=bridgeStruct(layout.dataKey,layout.fields)
  data.cars=ac.StructItem.array(ac.StructItem.struct(bridgeStruct(nil,layout.car)),layout.maxCars)
  return {hello=hello,data=ac.connect(data)}
 end)
 if ok and type(port)=='table' and port.hello and port.data then return port end
 return nil,tostring(port):sub(1,160)
end
return M
