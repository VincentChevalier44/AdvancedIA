-- Beta 1.52 (relecture de la couche hôte) : voiture de sécurité et voitures garées après un changement de session ou une
-- reprise, réparations et plein de course à chaque session, sorties de la voiture de sécurité recomptées, point de
-- reprise étendu, décalage rendu au déchargement, lecture légère, copie de l'ancienne mise à jour. Chargé par
-- tests/extended.lua.
local A=require('src/applier')
local C=require('src/config')
local H=require('tests/host')
local K=C.K
local tests={}
-- Banc de l'applicateur : écritures natives notées dans l'ordre ({nom,indice,valeur}), stockage de la partie en mémoire.
local recorded={setAITimeToStart='startDelay',setAIStopCounter='stop',setAINoInput='park',setAILevel='level',setAIAggression='aggression',
 setAITopSpeed='speed',teleportCarTo='teleport',awakeCar='awake',setAIPitStopRequest='pit',setCarBodyDamage='repairBody',setSuspensionDamage='repairSuspension',
 setCarEngineLife='repairEngine',setCarFuel='fuelSet',overrideAIRequestedFuel='fuel',setAISplineOffset='offset',setAICaution='caution'}
local function bench()
 H.create(true)
 local writes={}
 for fname,label in pairs(recorded) do physics[fname]=function(i,v) writes[#writes+1]={label,i,v}; return true end end
 physics.allowed=function() return true end
 local stored={}
 ac.store=function(key,value) stored[key]=value end; ac.load=function(key) return stored[key] end
 local a=A.new(); assert(A.access(a)); local notes={}; a.note=function(_,text) notes[#notes+1]=text end
 return a,writes,notes,stored
end
local function aiCar(id,box)
 return {index=1,valid=true,control=true,player=false,pit=box,inPitBox=box,offtrack=false,identity=id,id=id,kmh=0,aiLevel=1,aiAggression=0.5,damageBody=0,damageSuspension=0,engineLife=K.engineLifeNew}
end
local function command(over)
 local c={active=false,offset=0,level=1,aggression=0.5,caution=1,brake=0,speedLimit=K.unlimitedSpeed,yellowLimit=K.unlimitedSpeed,stopHold=false,recover=false,flashEvent=0,
  rulePit=false,pitHold=false,pitCompound=-1,pitVisit=0,scPark=false,parkReason='sc',scSpeed=K.unlimitedSpeed,mistakeId=0,fuelTarget=-1,fuelLaps=0,fuelSet=-1,pitRepair=false,
  startDelay=-1,startDelayFor='',levelScale=1,throttleLimit=1,wearId=0}
 for k,v in pairs(over or {}) do c[k]=v end
 return c
end
local function frameOf(car) return {count=1,online=false,replay=false,paused=false,session=0,cars={car}} end
local g={offsetSign=-1,sideSign=-1,useBrakeAssist=false,useGripBoost=false}
-- Une image de l'applicateur dans l'ordre du fichier d'entrée : restitution en attente, puis commandes.
local function step(a,frame,cmd,t) A.restore(a,frame,true,t); A.apply(a,frame,{cmd},g,t) end
local function count(list,text) local n=0; for _,v in ipairs(list) do if v:find(text,1,true) then n=n+1 end end return n end
-- Majeur 1 : voiture de sécurité retenue, puis changement de session : plus aucune écriture après le premier cycle.
tests.REVIEW152C_SC_HELD_NO_LOOP_SESSION=function()
 local a,writes,notes=bench(); local car=aiCar('sc',true); local frame=frameOf(car); local cmd=command({scPark=true})
 local t=0; for _=1,3 do t=t+1/60; step(a,frame,cmd,t) end
 assert(a.cars[1].scHeld,'held at its pit box')
 A.nextSession(a,frame)
 assert(not a.cars[1].reset,'held car: no restoration pending after the session change')
 for _=1,2 do t=t+1/60; step(a,frame,cmd,t) end
 local settled=#writes; local held=count(notes,'retenue a son emplacement')
 for _=1,10 do t=t+1/60; step(a,frame,cmd,t) end
 assert(#writes==settled,'no write after the first cycle ('..(#writes-settled)..')')
 assert(count(notes,'retenue a son emplacement')==held and held<=2 and not a.cars[1].reset,'one hold note at most')
end
-- Majeur 1 : même chose après une reprise (rechargement de l'app), voiture de sécurité retenue puis IA disqualifiée garée.
tests.REVIEW152C_PARKED_NO_LOOP_RECOVER=function()
 for _,reason in ipairs({'sc','dq'}) do
  local a,writes,notes,stored=bench(); local car=aiCar('car'..reason,true); local frame=frameOf(car); local cmd=command({scPark=true,parkReason=reason})
  local t=0; for _=1,3 do t=t+1/60; step(a,frame,cmd,t) end
  assert(reason=='sc' and a.cars[1].scHeld or reason=='dq' and a.cars[1].parked,reason..': held or parked')
  A.checkpoint(a,frame,true)
  local b=A.new(); assert(A.access(b)); b.note=a.note; A.recover(b,frame)
  assert(b.cars[1].owned and b.cars[1].reset,reason..': recovered, restoration pending')
  for _=1,2 do t=t+1/60; step(b,frame,cmd,t) end
  local settled=#writes; local n=#notes
  for _=1,10 do t=t+1/60; step(b,frame,cmd,t) end
  assert(#writes==settled and #notes==n,reason..': no write nor note after the first cycle ('..(#writes-settled)..')')
  assert(not b.cars[1].reset and (reason=='sc' and b.cars[1].scHeld or reason=='dq' and b.cars[1].parked),reason..': kept')
 end
end
-- Majeur 2 : réparations faites au premier arrêt de la session suivante (compteur de visites remis à 0).
tests.REVIEW152C_REPAIR_NEXT_SESSION=function()
 local a,writes=bench(); local car=aiCar('x',true); car.damageBody=50; local frame=frameOf(car); local cmd=command({pitRepair=true,pitVisit=1})
 A.apply(a,frame,{cmd},g,1)
 local function repairs() local n=0; for _,w in ipairs(writes) do if w[1]=='repairBody' then n=n+1 end end return n end
 assert(repairs()==1,'repaired at visit 1')
 frame.session=1; A.nextSession(a,frame); step(a,frame,cmd,2)
 assert(repairs()==2,'repaired again at visit 1 of the next session')
end
-- Majeur 3 : retenue levée sans libération : attente native et freinage forcé rendus à AC.
tests.REVIEW152C_SC_HOLD_LIFTED=function()
 local a,writes=bench(); local car=aiCar('sc',true); local frame=frameOf(car); local cmd=command({scPark=true})
 local t=0; for _=1,3 do t=t+1/60; step(a,frame,cmd,t) end
 local before=#writes
 cmd.scPark=false; cmd.scRelease=false; t=t+1/60; step(a,frame,cmd,t)
 local delay,stop=false,false
 for k=before+1,#writes do local w=writes[k]; if w[1]=='startDelay' and w[3]==0 then delay=true elseif w[1]=='stop' and w[3]==0 then stop=true end end
 assert(delay and stop and not a.cars[1].scHeld,'native wait and forced braking handed back')
end
-- Majeur 4 : plein de course refait quand la course est recommencée (même indice de session).
tests.REVIEW152C_FUEL_SET_RESTART=function()
 local a,writes=bench(); local car=aiCar('x',false); car.pit=false; local frame=frameOf(car); local cmd=command({fuelSet=50})
 local function fills() local n=0; for _,w in ipairs(writes) do if w[1]=='fuelSet' then n=n+1 end end return n end
 A.apply(a,frame,{cmd},g,1); A.apply(a,frame,{cmd},g,2); assert(fills()==1,'once per session')
 A.nextSession(a,frame); A.apply(a,frame,{cmd},g,3); assert(fills()==2,'again after a restart at the same index')
end
-- Majeur 5 : sorties de la voiture de sécurité recomptées à chaque session ; garée sans pilote, retenue de nouveau.
tests.REVIEW152C_SC_ESCAPES_NEXT_SESSION=function()
 local a,writes=bench(); local car=aiCar('sc',true); local frame=frameOf(car); local cmd=command({scPark=true,scHideWait=true})
 local t=1; step(a,frame,cmd,t)
 for k=1,K.scEscapeMax do
  car.inPitBox=false; car.pit=true; t=t+K.scHoldPeriod+1; step(a,frame,cmd,t)
  car.inPitBox=true; t=t+K.scHoldPeriod+1; step(a,frame,cmd,t)
  assert(a.cars[1].scEscapes==k,'escape '..k)
 end
 assert(a.cars[1].parked and not a.cars[1].scHeld,'parked without a driver after the escapes')
 frame.session=1; A.nextSession(a,frame); assert(a.cars[1].scEscapes==nil,'escapes forgotten')
 local before=#writes; t=t+1; step(a,frame,cmd,t)
 local unparked,delay=false,false
 for k=before+1,#writes do local w=writes[k]; if w[1]=='park' and w[3]==false then unparked=true elseif w[1]=='startDelay' and w[3]==K.scHoldTime then delay=true end end
 assert(unparked and delay and a.cars[1].scHeld and not a.cars[1].parked,'held by the AC wait again in the next session')
 -- Autre voiture dans l'emplacement : sorties oubliées aussi.
 a.cars[1].scEscapes=1; car.identity='other'; car.id='other'; step(a,frame,cmd,t+1); assert(a.cars[1].scEscapes==nil,'other car: escapes forgotten')
end
-- Mineur 13 : point de reprise avec le carburant demandé et la retenue ; ligne d'une version plus ancienne lue.
tests.REVIEW152C_CHECKPOINT_COLUMNS=function()
 local a,_,_,stored=bench(); local car=aiCar('x',false); local frame=frameOf(car)
 local s=a.cars[1]; s.owned=true; s.id='x'; s.fuelRequested=42; s.scHeld=true; a.recoveryDirty=true
 A.checkpoint(a,frame,true)
 local b=A.new(); A.recover(b,frame); assert(b.cars[1].owned and b.cars[1].fuelRequested==42 and b.cars[1].scHeld==true,'new columns read back')
 s.fuelRequested=-1; s.scHeld=false; A.checkpoint(a,frame,true)
 local c=A.new(); A.recover(c,frame); assert(c.cars[1].fuelRequested==-1 and c.cars[1].scHeld==false,'no request, no hold')
 stored['humanai:recovery']='0\n1,x,1,0.5,0,1,0,0,0,0,0,0,0,0,0,0,1'
 local d=A.new(); A.recover(d,frame); assert(d.cars[1].owned and d.cars[1].parked and d.cars[1].fuelRequested==-1 and not d.cars[1].scHeld,'older row: defaults')
 -- Demande reprise : rendue à AC (math.huge) par la restitution.
 local e,writes=bench()
 local f=frameOf(aiCar('x',false)); e.cars[1].owned=true; e.cars[1].id='x'; e.cars[1].fuelRequested=42; A.checkpoint(e,f,true)
 local r=A.new(); assert(A.access(r)); A.recover(r,f); local before=#writes; A.restore(r,f,true,1)
 local handed=false; for k=before+1,#writes do if writes[k][1]=='fuel' and writes[k][3]==math.huge then handed=true end end
 assert(handed and r.cars[1].fuelRequested==-1,'fuel request handed back after a reload')
end
-- Mineur 11 : au déchargement, décalage rendu à 0 même aux stands.
tests.REVIEW152C_FINAL_OFFSET=function()
 local a,writes=bench(); local car=aiCar('x',true); local frame=frameOf(car)
 local s=a.cars[1]; s.owned=true; s.id='x'; s.offset=0.5; s.offsetReset=false
 A.restore(a,frame,false,1,true)
 local zero=false; for _,w in ipairs(writes) do if w[1]=='offset' and w[3]==0 then zero=true end end
 assert(zero and not s.owned,'offset handed back at unload, in the pits')
end
-- Mineur 25 : drapeau de l'app resté affiché : restitution renvoyée toutes les K.flagLeftoverDelay s (temps du moteur).
tests.REVIEW152C_FLAG_LEFTOVER_SECONDS=function()
 local a=bench(); local sends=0; physics.overrideRacingFlag=function() sends=sends+1; return true end
 a.flagLast=K.flagStop; A.flagReleased(a); local frame=frameOf(aiCar('x',false)); frame.flag=K.flagStop
 for k=1,30 do A.flag(a,frame,false,nil,nil,nil,k/60) end
 assert(sends==0,'nothing before the delay')
 local at=1/60+K.flagLeftoverDelay+0.01
 A.flag(a,frame,false,nil,nil,nil,at); assert(sends==1 and a.flagLeftoverTries==1,'first re-send after the delay')
 A.flag(a,frame,false,nil,nil,nil,at+0.5); assert(sends==1,'not before the next delay')
 A.rebase(a,100); assert(math.abs(a.flagLeftoverAt-(at+K.flagLeftoverDelay-100))<1e-9,'rebased')
end
-- Mineur 12 : champs recalés.
tests.REVIEW152C_REBASE_FIELDS=function()
 local a=bench(); a.hiddenReadAt=50; a.windowCheckAt=60; a.cars[1].scReleasedAt=70
 A.rebase(a,10); assert(a.hiddenReadAt==40 and a.windowCheckAt==60 and a.cars[1].scReleasedAt==60,'window clock never rebased')
 a.hiddenReadAt=nil; a.cars[1].scReleasedAt=nil; A.rebase(a,10); assert(a.hiddenReadAt==nil and a.cars[1].scReleasedAt==nil)
end
-- Mineur 17 : compteur d'échecs des capacités.
tests.REVIEW152C_CAPS_FAILURE_COUNT=function()
 local a=bench(); physics.setAILevel=function() error('refused') end
 local b=A.new(); local before=b.caps.failureCount
 local Caps=require('src/caps'); Caps.call(b.caps,'level',1,0.9); assert(b.caps.failureCount==before+1)
 Caps.call(b.caps,'caution',1,1); assert(b.caps.failureCount==before+1,'success: unchanged')
 assert(a~=nil)
end
-- Mineur 19 : fenêtre ouverte hors des menus refermée au plus toutes les K.windowCheckPeriod s.
tests.REVIEW152C_WINDOW_CHECK_PERIOD=function()
 local a=bench(); local checks=0; local open=ac.isWindowOpen; ac.isWindowOpen=function(id) checks=checks+1; return open(id) end
 A.menu(a,false,0); local first=checks; assert(first==1,'checked on the change')
 for k=1,30 do A.menu(a,false,k/60) end; assert(checks==first,'not every frame')
 A.menu(a,false,K.windowCheckPeriod+0.01); assert(checks==first+1,'checked again after the period')
 A.menu(a,false); assert(checks==first+1,'draw callback (no time): no check')
end
-- Mineur 8 : lecture légère : joueur relu, autres voitures invalides.
tests.REVIEW152C_LIGHT_READ_PLAYER=function()
 local host=H.create(true); local Snapshot=require('src/snapshot'); local f=Snapshot.new()
 Snapshot.read(f,1/60,0,true); assert(f.player==1 and f.cars[2].valid,'first read always complete')
 host.cars[0].isInPit=true; host.cars[0].speedKmh=0
 Snapshot.read(f,1/60,1/60,true)
 assert(f.player==0 and f.lightPlayer==1 and f.cars[1].inPitBox and f.cars[1].kmh==0,'player read apart in a light read')
 local Update=require('src/update'); assert(Update.stopped(f,f.cars[f.lightPlayer]),'update: stopped at the pit box')
 assert(not f.cars[2].valid and not f.cars[3].valid and not f.cars[4].valid,'other cars invalid')
 Snapshot.read(f,1/60,2/60); assert(f.cars[2].valid and f.player==1 and f.lightPlayer==0,'full read again')
end
-- Mineur 20 : taille des voitures lue avec les métadonnées.
tests.REVIEW152C_SIZE_WITH_META=function()
 local host=H.create(true); local Snapshot=require('src/snapshot'); local f=Snapshot.new()
 Snapshot.read(f,1/60,0); assert(math.abs(f.cars[2].length-4.4)<1e-6)
 host.cars[1].aabbSize={x=1.9,z=5}
 Snapshot.read(f,1/60,0.1); assert(math.abs(f.cars[2].length-4.4)<1e-6,'not every frame')
 Snapshot.read(f,1/60,K.metaPeriod+0.2); assert(math.abs(f.cars[2].length-5)<1e-6,'read again with the metadata')
end
-- Mineur 27 : réglage absent : valeurs du schéma.
tests.REVIEW152C_FLOOD_FALLBACK=function()
 local Flood=require('src/flood')
 assert(Flood.decide({},45)==(C.defaults('C').spawnMode=='native' and 'restore' or 'off'))
 assert(Flood.decide({spawnMode='track'},C.defaults('C').spawnMinCars)=='off' and Flood.decide({spawnMode='track'},C.defaults('C').spawnMinCars-1)=='on')
end
-- Mineur 29 : copie de la mise à jour de l'ancienne version effacée, ce seul dossier ; rien si l'ancienne app est là.
tests.REVIEW152C_OLD_WORK_LEFTOVER=function()
 H.create(true)
 local files,dirs={},{}
 local function reset()
  files={}; dirs={}
  for _,d in ipairs({'state','state/ACAdvancedIA-update','state/ACAdvancedIA-update/next','state/ACAdvancedIA-update/next/src','state/ACAdvancedIA-update/backup','state/AdvancedIA-update','apps'}) do dirs[d]=true end
  for _,p in ipairs({'state/ACAdvancedIA-update/installing.txt','state/ACAdvancedIA-update/next/src/ui.lua','state/ACAdvancedIA-update/backup/manifest.ini','state/AdvancedIA-update/boot.txt','state/ACAdvancedIA-cspgui.ini'}) do files[p]='x' end
 end
 ac.FolderID.ACAppsLua=30; ac.FolderID.ExtCfgState=25
 local getFolder=ac.getFolder
 ac.getFolder=function(id) if id==30 then return 'apps' elseif id==25 then return 'state' end return getFolder(id) end
 io.fileExists=function(p) return files[p]~=nil end
 io.dirExists=function(p) return dirs[p]==true end
 io.deleteFile=function(p) files[p]=nil; return true end
 io.deleteDir=function(p) for q in pairs(files) do if q:sub(1,#p+1)==p..'/' then return false end end; for q in pairs(dirs) do if q:sub(1,#p+1)==p..'/' then return false end end; dirs[p]=nil; return true end
 io.scanDir=function(root,mask,cb)
  local seen={}
  for q in pairs(files) do local name=q:sub(1,#root+1)==root..'/' and q:sub(#root+2) or nil; if name and not name:find('/',1,true) then cb(name,{isDirectory=false}) end end
  for q in pairs(dirs) do local name=q:sub(1,#root+1)==root..'/' and q:sub(#root+2) or nil; if name and not name:find('/',1,true) and not seen[name] then seen[name]=true; cb(name,{isDirectory=true}) end end
 end
 reset(); files['apps/ACAdvancedIA/manifest.ini']='x'
 assert(not A.oldWorkLeftover('ACAdvancedIA','ACAdvancedIA-update') and dirs['state/ACAdvancedIA-update'],'old app installed: untouched')
 reset()
 assert(A.oldWorkLeftover('ACAdvancedIA','ACAdvancedIA-update'),'removed')
 assert(not dirs['state/ACAdvancedIA-update'] and not files['state/ACAdvancedIA-update/installing.txt'] and not dirs['state/ACAdvancedIA-update/next/src'])
 assert(files['state/AdvancedIA-update/boot.txt'] and dirs['state/AdvancedIA-update'] and files['state/ACAdvancedIA-cspgui.ini'],'siblings kept')
 assert(not A.oldWorkLeftover('ACAdvancedIA','ACAdvancedIA-update'),'once: nothing left to do')
 -- Nom douteux dans la copie : rien n'est effacé.
 reset(); files['state/ACAdvancedIA-update/a..b']='x'
 assert(not A.oldWorkLeftover('ACAdvancedIA','ACAdvancedIA-update') and files['state/ACAdvancedIA-update/installing.txt'],'doubtful name: nothing removed')
 assert(not A.oldWorkLeftover('../x','ACAdvancedIA-update') and not A.oldWorkLeftover('ACAdvancedIA','../state'),'names checked')
end
return tests
