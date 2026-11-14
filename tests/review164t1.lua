-- Beta 1.64 (Monza, 13 novembre : carambolages du premier tour à la Prima Variante, session S11 arrêtée par le pilote) :
-- IA accidentée relancée au milieu du peloton du premier tour (src/incidents.lua, traffic large), zones dangereuses
-- jamais enregistrées (src/applier.lua, trackPath refusait le dossier « danger »). Noms LOCK_*_164 (tests/LOCKS.md) et
-- *_164T1. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local A=require('src/applier')
local K=C.K
local tests={}
local function logged(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end

tests.K_164T1=function()
 assert(K.dangerFolder=='danger' and K.rejoinLap1Gap==500 and K.rejoinLap1Speed==5 and K.rejoinSideGap==15 and K.rejoinLap1Wait==25)
 assert(require('src/dangerfile').DF.folder==K.dangerFolder,'danger file folder accepted by trackPath')
end

-- S11 : Lopez arrêté en piste à 983 m, relancé à 41,5 s, percuté 0,5 s plus tard ; Haulle relancé à 41,6 s puis 3 contacts.
local function stopped(profile,behindAt,kmh)
 local e,f=F.scene(profile,3); F.place(f,1,-4000,120); F.place(f,2,behindAt,kmh); F.place(f,3,983,0); F.tick(e,f,3)
 return e,f,e.incidents.cars[3]
end
tests.LOCK_LAP1_REJOIN_WAIT_164=function()
 -- Premier tour (course, début) : une voiture à 60 km/h 300 m derrière : attente, une ligne au journal.
 local e,f,c=stopped('C',683,60)
 assert(e.incidents.hotspotPause==true,'scene: first lap')
 assert(c.incident,'scene: stopped')
 F.place(f,2,683,60); F.tick(e,f,1)
 assert(c.rejoinTries==0,'no restart with the field 300 m behind on the first lap')
 assert(logged(e,'IA accidentee: attend le passage du peloton avant de repartir (premier tour)')==1,'journal')
 -- Lente (15 km/h, sous K.rejoinSpeed) 200 m derrière, dans la file du premier tour : attente aussi.
 F.place(f,2,783,15); F.tick(e,f,0.5); assert(c.rejoinTries==0,'no restart with a slow car in the queue behind')
 -- À sa hauteur (8 m devant, encore lancée) : attente aussi.
 F.place(f,2,991,40); F.tick(e,f,0.5); assert(c.rejoinTries==0,'no restart with a car alongside')
 -- Lente sous 5 km/h (arrêtée elle aussi) : ne compte pas ; peloton passé : redémarrage.
 F.place(f,2,1200,120); F.tick(e,f,1)
 assert(c.rejoinTries==1,'restart once the field has passed ('..tostring(c.rejoinTries)..')')
 assert(logged(e,'IA accidentee: attend le passage du peloton avant de repartir (premier tour)')==1,'one line per incident')
end
-- Retenue hors piste (accident) au premier tour : prolongée tant que le peloton passe (300 m derrière), bornée comme avant.
tests.LOCK_LAP1_HOLD_WAIT_164=function()
 local function crash(e,f,i)
  F.tick(e,f,0.5); f.cars[i].collided=true; f.cars[i].offtrack=true; f.cars[i].kmh=8; f.cars[i].speed=8/3.6; F.tick(e,f,0.5); f.cars[i].collided=false
 end
 local e,f=F.scene('C',3); local p=e.run; p.incidentStop=true
 F.place(f,1,-4000,120); F.place(f,2,0,150); F.place(f,3,-300,60)
 crash(e,f,2)
 local c=e.incidents.cars[2]
 assert(e.incidents.hotspotPause==true,'scene: first lap')
 assert(c.holding,'scene: crashed AI held off track')
 F.place(f,3,-300,60); F.tick(e,f,c.holdUntil-e.time+0.5)
 assert(c.holding,'still held with the field 300 m behind on the first lap')
 F.place(f,3,400,120); F.tick(e,f,0.5)
 assert(not c.holding,'released once the field has passed')
end
tests.REJOIN_NORMAL_UNCHANGED_164T1=function()
 -- Hors départ et premier tour : règle d'avant (K.rejoinSpeed km/h, p.rejoinGap m) : 300 m derrière : redémarrage.
 local e,f,c=stopped('P',683,60)
 assert(e.incidents.hotspotPause~=true,'scene: not the first lap')
 F.place(f,2,683,60); F.tick(e,f,1)
 assert(c.rejoinTries==1,'restart with a car 300 m behind outside the first lap')
end
tests.LOCK_DANGER_FILE_SAVE_164=function()
 local saved={save=io.save,load=io.load,fileExists=io.fileExists,createDir=io.createDir,fileSize=io.fileSize,deleteFile=io.deleteFile}
 local savedAc={getFolder=ac.getFolder,FolderID=ac.FolderID}
 local fs={files={},dirs={}}
 ac.FolderID={ACDocuments=1001,ScriptConfig=1002}
 ac.getFolder=function(id) return id==1001 and 'DOCS' or id==1002 and 'STATE' or 'other' end
 io.createDir=function(dir) fs.dirs[dir]=true; return true end
 io.fileExists=function(path) return fs.files[path]~=nil end
 io.fileSize=function(path) return fs.files[path] and #fs.files[path] or -1 end
 io.load=function(path) return fs.files[path] end
 io.deleteFile=function(path) fs.files[path]=nil; return true end
 io.save=function(path,data,ensure) fs.files[path]=data; return true end
 local ok,err=pcall(function()
  local DF=require('src/dangerfile').DF
  assert(A.trackFileWrite(DF.folder,'monza','zones')=='docs','danger zones written (S1-S11 : « enregistrement impossible »)')
  assert(fs.files['DOCS\\'..K.presetFolder..'\\danger\\monza.ini']=='zones','under Documents, danger folder')
  local text=A.trackFileRead(DF.folder,'monza'); assert(text=='zones','read back at the next launch')
  assert(A.trackFileWrite('logs','monza','x')==nil,'other folders still refused')
 end)
 for k,v in pairs(saved) do io[k]=v end
 ac.getFolder=savedAc.getFolder; ac.FolderID=savedAc.FolderID
 if not ok then error(err,0) end
end
return tests
