-- Beta 1.61 (étape de base) : les quatre réglages (déclarés, coupés, masqués tant que leur tranche manque), le codec
-- des fichiers par circuit (src/trackfile.lua), leur lecture et leur écriture par l'applicateur, la clé du circuit,
-- les modules vides et le bus des modificateurs du directeur. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local G=require('src/groups')
local T=require('src/trackfile')
local D=require('src/director')
local K=C.K
local tests={}
local profileKeys={'classNuance','startRealism','weatherLive'}
tests.SETTINGS_DECLARED_OFF_161=function()
 local byKey={}; for _,s in ipairs(C.schema) do byKey[s.key]=s end
 for _,key in ipairs(profileKeys) do
  local s=assert(byKey[key],key); assert(C.isNewKey(key),key..': new key')
  for _,profile in ipairs(C.profiles) do assert(s.defaults[profile]==false,key..' '..profile) end
  for name,preset in pairs(C.rulePresets or {}) do if type(preset)=='table' then assert(preset[key]==nil,key..' in rule set '..tostring(name)) end end
 end
 assert(byKey.classNuance.group=='blue' and byKey.startRealism.group=='start' and byKey.weatherLive.group=='weather','sections')
 assert(C.globalDefaults.trackMemory==false and byKey.trackMemory==nil,'track memory: global, off')
 assert(C.raceKeys.startRealism,'realistic starts: race only')
end
tests.SETTINGS_SECTIONS_AND_PENDING_161=function()
 local saved={}; for key in pairs(C.pendingKeys) do saved[key]=true end
 for key in pairs(saved) do C.pendingKeys[key]=nil end
 local savedGlobal=C.pendingGlobals.trackMemory; C.pendingGlobals.trackMemory=nil
 local ok,err=pcall(function()
  assert(not C.hidden('C','startRealism'),'realistic starts shown in the race')
  for _,profile in ipairs({'J','P','Q','H'}) do assert(C.hidden(profile,'startRealism'),'realistic starts hidden in '..profile) end
  local p=C.defaults('C')
  for _,g in ipairs(C.sections) do p['section_'..g]=true end
  for _,key in ipairs(profileKeys) do p[key]=true end
  local out=C.effective('C',p)
  for _,key in ipairs(profileKeys) do assert(out[key]==true,key..' kept') end
  p.section_start=false; out=C.effective('C',p); assert(out.startRealism==false,'off with the Start section'); p.section_start=true
  p.section_weather=false; out=C.effective('C',p); assert(out.weatherLive==false,'off with the Weather section'); p.section_weather=true
  -- Règle générale des sections (M.effective) : section décochée, réglage à son défaut.
  p.section_blue=false; out=C.effective('C',p); assert(out.classNuance==false,'off with the Blue flags section'); p.section_blue=true
  local g={}; for key,value in pairs(C.globalDefaults) do g[key]=value end
  g.trackMemory=true
  assert(C.effectiveGlobals(g,p).trackMemory==true,'track memory live once delivered')
 end)
 for key in pairs(saved) do C.pendingKeys[key]=true end
 C.pendingGlobals.trackMemory=savedGlobal
 assert(ok,err)
 -- Tranche non livrée : masqué et tenu à son défaut, même allumé dans un fichier de réglages.
 local p=C.defaults('C')
 for _,g in ipairs(C.sections) do p['section_'..g]=true end
 for _,key in ipairs(profileKeys) do p[key]=true end
 local out=C.effective('C',p)
 for _,key in ipairs(profileKeys) do
  if C.pendingKeys[key] then assert(G.hidden[key] and out[key]==false,key..' pending: hidden and off')
  else assert(not G.hidden[key] and out[key]==true,key..' live') end
 end
 local g={}; for key,value in pairs(C.globalDefaults) do g[key]=value end
 g.trackMemory=true
 assert(C.effectiveGlobals(g,p).trackMemory==(not C.pendingGlobals.trackMemory),'track memory held off while pending')
end
tests.TRACKFILE_KEY_161=function()
 assert(T.key('imola','')=='imola' and T.key('imola',nil)=='imola','no layout')
 assert(T.key('ks_nordschleife','touristenfahrten')=='ks_nordschleife__touristenfahrten','layout')
 assert(T.key('','x')==nil and T.key('a/b','')==nil and T.key('..','')==nil and T.key('a','..\\b')==nil and T.key('a b','')==nil and T.key('a.b','')==nil,'refused')
 assert(T.key(string.rep('a',K.trackKeyMax),'')~=nil and T.key(string.rep('a',K.trackKeyMax),'b')==nil and T.key(string.rep('a',K.trackKeyMax+1),'')==nil,'length cap')
 assert(T.key(42,'')==nil and T.key('a',7)==nil,'types')
end
tests.TRACKFILE_ROUND_TRIP_161=function()
 local text=T.build('AdvancedIA track zones',{kind='zones',track='imola',layout='',length=4909,serial=12,bins=400},{
  {name='zone.1',kind='nomove',from=0.123,to=0.131,noYield=true,note=' Narrow 100% section\n'},
  {name='model.player:ks_porsche-911',sessions=3,data='2A12B0'},
  {name='AdvancedIA',kind='forged'},{name='bad name',x=1}})
 assert(text:sub(1,1)==';' and text:find('[AdvancedIA]\nformat='..K.trackFileFormat..'\nkind=zones\nrelease='..C.release,1,true),'header')
 assert(not text:find('forged',1,true) and not text:find('bad name',1,true),'reserved or invalid section names never written')
 local doc=assert(T.parse(text))
 assert(doc.head.kind=='zones' and doc.head.track=='imola' and doc.head.layout=='' and doc.head.length=='4909' and doc.head.bins=='400','head')
 assert(T.serial(doc)==12 and #doc.sections==2 and doc.dropped==0,'sections')
 local z=doc.sections[1]
 assert(z.name=='zone.1' and z.values.kind=='nomove' and T.number(z.values.from,0,1)==0.123 and T.boolean(z.values.noYield)==true,'zone values')
 assert(z.values.note==' Narrow 100% section\n' and T.text(z.values.note,8)==' Narrow ','escaped text comes back, then cut without control characters')
 assert(doc.sections[2].name=='model.player:ks_porsche-911' and doc.sections[2].values.data=='2A12B0','model section name')
 local ok,lengthOK=T.check(doc,'zones','imola','',4909)
 assert(ok and lengthOK,'same track')
 ok,lengthOK=T.check(doc,'zones','imola','',4909*(1+K.trackLengthTol*2)); assert(ok and not lengthOK,'length changed: told, not refused')
 local refused,why=T.check(doc,'pace','imola','',4909); assert(not refused and why=='kind')
 refused,why=T.check(doc,'zones','monza','',4909); assert(not refused and why=='track','file copied from another track')
 refused,why=T.check(doc,'zones','imola','gp',4909); assert(not refused and why=='layout')
end
tests.TRACKFILE_NEVER_TRUSTED_161=function()
 local head='[AdvancedIA]\nformat='..K.trackFileFormat..'\nkind=zones\n'
 local doc,why=T.parse(42); assert(not doc and why=='corrupt')
 doc,why=T.parse(string.rep('x',K.trackFileMaxBytes+1)); assert(not doc and why=='big')
 doc,why=T.parse(head,10); assert(not doc and why=='big','caller cap')
 doc,why=T.parse('[zone.1]\nkind=nomove\n'); assert(not doc and why=='format','no header')
 doc,why=T.parse('[AdvancedIA]\nformat=99\n'); assert(not doc and why=='format')
 doc,why=T.parse('kind=zones\n'..head); assert(not doc and why=='corrupt','key before any section')
 doc,why=T.parse(head..'[AdvancedIA]\nformat=1\n'); assert(not doc and why=='corrupt','two headers')
 doc,why=T.parse(head..'[zone.1]\nthis is not a key\n'); assert(not doc and why=='corrupt')
 -- Marque d'ordre des octets, fins de ligne Windows, commentaires, espaces : lus.
 doc=assert(T.parse('\239\187\191; note\r\n'..head:gsub('\n','\r\n')..'# x\r\n [zone.1] \r\n from = 0.5 \r\n'))
 assert(doc.sections[1].values.from=='0.5','tolerant read')
 -- Valeur mal codée, trop longue, ou clé en trop : écartée et comptée, le reste gardé.
 local many={}; for k=1,K.trackFileMaxKeys+3 do many[#many+1]='k'..k..'=1' end
 doc=assert(T.parse(head..'[a]\nbad=%ZZ\nlong='..string.rep('y',K.trackFileMaxValue+1)..'\nok=1\n[b]\n'..table.concat(many,'\n')..'\n'))
 assert(doc.sections[1].values.bad==nil and doc.sections[1].values.long==nil and doc.sections[1].values.ok=='1','bad values dropped')
 local kept=0; for _ in pairs(doc.sections[2].values) do kept=kept+1 end
 assert(kept==K.trackFileMaxKeys and doc.dropped==2+3,'keys capped, drops counted: '..kept..' '..doc.dropped)
 -- Sections en trop : écartées avec leurs clés, sans erreur.
 local text={head}; for k=1,5 do text[#text+1]='[s'..k..']\nv='..k end
 doc=assert(T.parse(table.concat(text,'\n'),nil,3))
 assert(#doc.sections==3 and doc.dropped==2 and doc.sections[3].values.v=='3','section cap')
 -- Lecteurs typés.
 assert(T.number('nan')==nil and T.number('inf')==nil and T.number('1e999')==nil and T.number('x')==nil and T.number(nil)==nil,'finite numbers only')
 assert(T.number('0.5',0,1)==0.5 and T.number('1.5',0,1)==nil and T.number('-1',0,1)==nil,'range')
 assert(T.integer('12',0,100)==12 and T.integer('12.5',0,100)==nil and T.integer('101',0,100)==nil,'integers')
 assert(T.boolean('true')==true and T.boolean('false')==false and T.boolean('1')==nil and T.boolean(nil)==nil,'booleans')
 assert(T.text(12)==nil and T.serial(nil)==0 and T.serial({head={serial='-3'}})==0 and T.serial({head={serial='7'}})==7,'text and serial')
 -- Nombre non fini jamais écrit.
 local built=T.build(nil,{kind='pace',track='t',layout='',length=1/0,serial=0/0},{{name='a',x=0/0,y=1/0,z=2}})
 assert(not built:find('nan',1,true) and not built:find('inf',1,true) and built:find('z=2',1,true),'non-finite values left out')
end
tests.TRACKFILE_IO_161=function()
 local A=require('src/applier')
 local saved={save=io.save,load=io.load,fileExists=io.fileExists,createDir=io.createDir,fileSize=io.fileSize,deleteFile=io.deleteFile}
 local savedAc={getFolder=ac.getFolder,FolderID=ac.FolderID}
 local fs={files={},dirs={},refuse={}}
 ac.FolderID={ACDocuments=1001,ScriptConfig=1002}
 ac.getFolder=function(id) return id==1001 and 'DOCS' or id==1002 and 'STATE' or 'other' end
 io.createDir=function(dir) fs.dirs[dir]=true; return true end
 io.fileExists=function(path) return fs.files[path]~=nil end
 io.fileSize=function(path) return fs.files[path] and #fs.files[path] or -1 end
 io.load=function(path) return fs.files[path] end
 io.deleteFile=function(path) fs.files[path]=nil; return true end
 io.save=function(path,data,ensure)
  assert(ensure==true and type(data)=='string')
  for prefix in pairs(fs.refuse) do if path:sub(1,#prefix)==prefix then return false end end
  if fs.files[path] then fs.files[path..'.bak']=fs.files[path] end
  fs.files[path]=data; return true
 end
 local ok,err=pcall(function()
  local zones,pace=K.zoneFolder,K.paceFolder
  assert(A.trackFileRead(zones,'imola')==nil,'nothing yet')
  assert(A.trackFileWrite(zones,'imola','one')=='docs' and fs.files['DOCS\\'..K.presetFolder..'\\tracks\\imola.ini']=='one','written under Documents')
  assert(fs.dirs['DOCS\\'..K.presetFolder] and fs.dirs['DOCS\\'..K.presetFolder..'\\tracks'],'folders created')
  assert(A.trackFileWrite(zones,'imola','two')=='docs' and fs.files['DOCS\\'..K.presetFolder..'\\tracks\\imola.ini.bak']==nil,'leftover .bak removed')
  local text,place=A.trackFileRead(zones,'imola'); assert(text=='two' and place=='docs','read back')
  assert(A.trackFileWrite(pace,'imola','p')=='docs' and fs.files['DOCS\\'..K.presetFolder..'\\pace\\imola.ini']=='p' and A.trackFileRead(pace,'imola')=='p','pace folder apart')
  -- Dossier, clé ou texte refusés : rien d'écrit, rien de lu.
  local count=0; for _ in pairs(fs.files) do count=count+1 end
  for _,key in ipairs({'','..','a/b','a\\b','a.b','a b',string.rep('k',K.trackKeyMax+1)}) do
   assert(A.trackFileWrite(zones,key,'x')==nil and A.trackFileRead(zones,key)==nil,'key refused: '..key)
  end
  assert(A.trackFileWrite('logs','imola','x')==nil and A.trackFileWrite('..','imola','x')==nil and A.trackFileRead('cfg','imola')==nil,'only the two folders')
  assert(A.trackFileWrite(zones,'imola',string.rep('x',K.trackFileMaxBytes+1))==nil and A.trackFileWrite(zones,'imola',42)==nil,'text refused')
  local after=0; for _ in pairs(fs.files) do after=after+1 end
  assert(after==count,'no file created by a refused call')
  -- Fichier trop gros : refusé avant ou après la lecture.
  fs.files['DOCS\\'..K.presetFolder..'\\tracks\\big.ini']=string.rep('x',200)
  local big,why=A.trackFileRead(zones,'big',100); assert(big==nil and why=='big','size asked first')
  io.fileSize=nil
  big,why=A.trackFileRead(zones,'big',100); assert(big==nil and why=='big','checked on the text without io.fileSize')
  -- Documents refusé par CSP : repli sur le dossier de l'app, relu de là.
  fs.refuse['DOCS']=true
  assert(A.trackFileWrite(zones,'spa','s')=='state' and fs.files['STATE\\tracks\\spa.ini']=='s','fallback folder')
  text,place=A.trackFileRead(zones,'spa'); assert(text=='s' and place=='state','read from the fallback')
  fs.refuse['STATE']=true
  assert(A.trackFileWrite(zones,'spa','t')==nil,'no place accepts the write')
 end)
 io.save,io.load,io.fileExists,io.createDir,io.fileSize,io.deleteFile=saved.save,saved.load,saved.fileExists,saved.createDir,saved.fileSize,saved.deleteFile
 ac.getFolder,ac.FolderID=savedAc.getFolder,savedAc.FolderID
 assert(ok,err)
end
tests.STUBS_AND_HOOKS_161=function()
 for _,name in ipairs({'zonelearn','pacemap','nuance','antics','wx'}) do
  local m=require('src/'..name); local t=m.new()
  assert(type(t)=='table' and t.session==-1,name..' state'); t.session=4; m.reset(t,0); assert(t.session==-1,name..' reset'); m.rebase(t,10)
 end
 assert(require('src/zones').nextBrake({},0.5)==nil and require('src/pacemap').status({})==nil,'neutral entry points')
 local e,f=F.scene('C',4)
 assert(e.zonelearn and e.pacemap and e.nuance and e.antics and e.wx and type(e.sideText)=='table' and next(e.sideText)==nil,'engine states')
 e.passDone=3; F.tick(e,f,0.1); assert(e.passDone==nil,'pass flag cleared before each drive loop')
 for i=2,4 do local s=e.states[i]; assert(s.wxWet==nil and s.formOffset==nil and s.prior==nil and s.zone.caution==nil and s.zone.passWait==nil and s.zone.passMargin==nil and s.zone.lineOffset==nil,'bus empty by default') end
 E.rebase(e,5); assert(e.zonelearn.session==-1,'rebase harmless')
end
tests.MODIFIER_BUS_161=function()
 -- Allure gardée : dernier repli de l'allure libre, jamais devant ce que la voiture a appris ni l'allure de sa classe.
 local e,f=F.scene('P',3)
 F.tick(e,f,0.2)
 local s=e.states[2]; local bin=7
 for j=1,K.paceBins do s.pace[j]=0 end
 s.paceRatioCount=0
 assert(D.freeAt(e,s,bin,e.run)==0,'unknown')
 s.prior={}; s.prior[bin]=40; s.priorRatio=0.9
 assert(math.abs(D.freeAt(e,s,bin,e.run)-36)<1e-9,'prior × ratio as the last fallback')
 assert(D.freeAt(e,s,bin+1,e.run)==0,'place unknown in the prior too')
 s.priorRatio=nil; assert(D.freeAt(e,s,bin,e.run)==40,'ratio absent: 1')
 s.pace[bin]=55; assert(D.freeAt(e,s,bin,e.run)==55,'own pace first')
 s.pace[bin]=0; s.prior=nil; assert(D.freeAt(e,s,bin,e.run)==0,'no prior: unknown as before')
 -- Humidité effective par voiture : lue à la place de celle de la piste.
 e,f=F.scene('P',3); e.profiles.P.section_weather=true; e.profiles.P.weatherAdaptation=true; E.changed(e)
 f.wet=0; F.tick(e,f,3)
 local dry=e.commands[2].level
 e.states[2].wxWet=1; F.tick(e,f,0.1)
 assert(f.cars[2].wet==1 and f.cars[3].wet==0,'effective wetness per car')
 local slowed=e.commands[2].level
 assert(slowed<dry-1e-6,'a car on the wrong tyres is slower: '..dry..' -> '..slowed)
 e.states[2].wxWet=nil; F.tick(e,f,3); assert(f.cars[2].wet==0,'field absent: track wetness')
 assert(e.commands[2].level>slowed+1e-6,'and the pace comes back: '..slowed..' -> '..e.commands[2].level)
 -- Point difficile du fichier de zones : même effet qu'un point difficile appris.
 e,f=F.scene('C',3); F.tick(e,f,0.5)
 assert(not e.states[2].hotspot,'no difficult spot')
 local at=require('src/zones').at
 require('src/zones').at=function(zones,progress,out) out=at(zones,progress,out); out.caution=true; return out end
 local ok,err=pcall(function() F.tick(e,f,0.1); assert(e.states[2].hotspot==true,'zone caution arms the difficult-spot state') end)
 require('src/zones').at=at
 assert(ok,err)
end
return tests
