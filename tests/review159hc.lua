-- Beta 1.59 (export/import, décision du pilote) : préréglages personnels et réglages des profils exportés dans
-- Documents\Assetto Corsa\AdvancedIA\AdvancedIA-presets.ini, puis importés après confirmation (src/presetfile.lua).
-- Chargé par tests/extended.lua.
local A=require('src/applier')
local C=require('src/config')
local K=C.K
local L=require('src/lang')
local PF=require('src/presetfile')
local Presets=require('src/presets')
local Journal=require('src/journal')
local tests={}
local DOCS='DOCS\\'..K.presetFolder
local STATE='STATE'
-- Fichiers en mémoire ; refused[dossier]=true : écriture refusée dans ce dossier. Rend l'état et la fonction qui rend
-- les fonctions d'origine de ac et io.
local function files(refused)
 local fs={files={},dirs={},writes=0}
 local ac0,io0=rawget(_G,'ac'),rawget(_G,'io')
 local saved={getFolder=ac0 and ac0.getFolder,FolderID=ac0 and ac0.FolderID,save=io0.save,load=io0.load,fileExists=io0.fileExists,createDir=io0.createDir}
 if not ac0 then rawset(_G,'ac',{}) end
 ac.FolderID={ACDocuments=1001,ScriptConfig=1002}
 ac.getFolder=function(id) return id==1001 and 'DOCS' or id==1002 and STATE or nil end
 io.createDir=function(dir) fs.dirs[dir]=true; return true end
 io.save=function(path,data,ensure)
  assert(type(data)=='string' and ensure==true,'safe write')
  local dir=path:match('^(.*)\\[^\\]+$')
  if (refused or {})[dir] then return false end
  fs.files[path]=data; fs.writes=fs.writes+1; return true
 end
 io.load=function(path) return fs.files[path] end
 io.fileExists=function(path) return fs.files[path]~=nil end
 local function restore()
  io.save,io.load,io.fileExists,io.createDir=saved.save,saved.load,saved.fileExists,saved.createDir
  if ac0 then ac0.getFolder,ac0.FolderID=saved.getFolder,saved.FolderID else rawset(_G,'ac',nil) end
 end
 return fs,restore
end
-- Réglages des cinq profils, options globales et applicateur avec ses préréglages (stockage en mémoire).
local function scene()
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.validate(x,C.defaults(x)) end
 local g=C.validateGlobals(C.globalDefaults)
 local a=A.new(); for i=1,K.maxPresets do a.presetStores[i]={} end
 local lines={}; a.note=function(level,text) lines[#lines+1]=level..' '..text end
 local e={profiles=profiles,g=g}
 local function note(level,text) a.note(level,text,-1) end
 return e,a,note,lines
end
local function signatures(e,a)
 local out={}
 for _,x in ipairs(C.profiles) do out[#out+1]=Presets.signature(x,e.profiles[x],e.g) end
 for i=1,K.maxPresets do local entry=a.presets[i]; if entry then out[#out+1]=entry.name..'|'..Presets.signature(entry.profile,entry.p,entry.g) end end
 return table.concat(out,'\n')
end
local function setup(e,a)
 e.profiles.C.levelPct=103; e.profiles.C.section_overtake=true; e.profiles.C.classPatterns='lmp1:1,gt3:3'
 e.profiles.J.aggressionPct=62; e.profiles.P.section_yield=false
 e.g.levelMode='native'; e.g.seed=123; e.g.debugLog=true
 local one=assert(Presets.capture('Course rapide','C',e.profiles.C,e.g)); assert(A.savePreset(a,one))
 local p=C.validate('J',C.defaults('J')); p.levelPct=88
 local two=assert(Presets.capture('Balade % 50','J',p,e.g)); assert(A.savePreset(a,two))
end
tests.PRESET_FILE_ROUND_TRIP_159HC=function()
 local fs,restore=files()
 local ok,err=pcall(function()
  local e,a,note,lines=scene(); setup(e,a)
  local before=signatures(e,a)
  local pio={}
  local msg,kind=PF.ask(pio,'export',e,a,L,note)
  assert(kind=='ok' and not pio.pending and msg:find('AdvancedIA',1,true),'exported to Documents: '..msg)
  local text=fs.files[DOCS..'\\'..K.presetFileName]; assert(text and fs.dirs[DOCS],'file in Documents\\Assetto Corsa\\AdvancedIA')
  assert(not text:find('seed=',1,true) and not text:find('debugLog',1,true),'seed and detailed log never exported')
  assert(text:find('[preset.2]',1,true) and text:find('[profile.H]',1,true) and text:find('name=Balade %25 50',1,true),'presets, profiles and an escaped name')
  assert(lines[#lines]:find('^INFO prereglages exportes: 2 prereglage%(s%), 5 profils %(Documents'),lines[#lines])
  -- Tout changé, puis importé : identique à l'export (graine et journal détaillé : PRESET_FILE_UNKNOWN_AND_RANGE_159HC).
  for _,x in ipairs(C.profiles) do e.profiles[x]=C.validate(x,C.defaults(x)) end
  e.g.levelMode='auto'
  for i=1,K.maxPresets do if a.presets[i] then assert(A.deletePreset(a,i)) end end
  local unchanged=signatures(e,a)
  msg,kind=PF.ask(pio,'import',e,a,L,note)
  assert(pio.pending=='import' and kind=='wn' and signatures(e,a)==unchanged,'import waits for confirmation, nothing changed yet')
  msg,kind=PF.confirm(pio,e,a,L,note,A.savePreset)
  assert(kind=='ok' and not pio.pending,'imported: '..msg)
  assert(e.g.levelMode=='native','global option imported')
  assert(signatures(e,a)==before,'round trip: same settings and presets')
  assert(lines[#lines]:find('^INFO prereglages importes: 2 prereglage%(s%), 5 profil%(s%), 0 valeur%(s%) corrigee%(s%), 0 ignore%(s%)'),lines[#lines])
 end)
 restore(); assert(ok,err)
end
tests.PRESET_FILE_UNKNOWN_AND_RANGE_159HC=function()
 local fs,restore=files()
 local ok,err=pcall(function()
  local e,a,note,lines=scene(); setup(e,a)
  local pio={}
  PF.ask(pio,'export',e,a,L,note)
  local path=DOCS..'\\'..K.presetFileName
  local text=fs.files[path]
  -- Clé et section inconnues ignorées ; niveau hors plage remplacé par le défaut du profil et compté.
  text=text:gsub('p_levelPct=103','p_levelPct=999',1)..'\n[future]\nwhatever=1\n'
  text=text:gsub('%[profile%.J%]','[profile.J]\np_unknownSetting=42\nlanguage=fr',1)
  -- Graine, journal détaillé et langue jamais importés, même écrits à la main dans le fichier.
  text=text:gsub('%[globals%]','[globals]\nseed=5\ndebugLog=false\nlanguage=fr',1):gsub('%[preset%.1%]','[preset.1]\ng_seed=7\ng_debugLog=false',1)
  fs.files[path]=text
  e.profiles.C.levelPct=100; e.g.language='en'; e.g.seed=999; e.g.debugLog=true
  PF.ask(pio,'import',e,a,L,note)
  local msg,kind=PF.confirm(pio,e,a,L,note,A.savePreset)
  assert(kind=='wn' and msg:find('1',1,true),'corrected value reported: '..msg)
  assert(e.profiles.C.levelPct==C.defaults('C').levelPct,'out-of-range value replaced by the default')
  assert(e.profiles.J.unknownSetting==nil and e.profiles.J.language==nil,'unknown keys ignored')
  assert(e.g.language=='en' and e.g.seed==999 and e.g.debugLog==true,'language, seed and detailed log never imported')
  for i=1,K.maxPresets do local entry=a.presets[i]; if entry then assert(entry.g.seed==999 and entry.g.debugLog==true,'preset keeps your own seed and log setting') end end
  assert(lines[#lines]:find('1 valeur%(s%) corrigee%(s%)'),lines[#lines])
 end)
 restore(); assert(ok,err)
end
tests.PRESET_FILE_FALLBACK_159HC=function()
 local fs,restore=files({[DOCS]=true})
 local ok,err=pcall(function()
  local e,a,note,lines=scene(); setup(e,a)
  local pio={}
  local msg,kind=PF.ask(pio,'export',e,a,L,note)
  assert(kind=='wn' and msg==string.format(L.presetIOExportedFallback,2,5),'fallback said: '..msg)
  assert(fs.files[STATE..'\\'..K.presetFileName] and not fs.files[DOCS..'\\'..K.presetFileName],'written to the CSP app folder')
  assert(lines[#lines]:find('^WARN prereglages exportes: .*repli'),lines[#lines])
  local en=Journal.english(lines[#lines]:sub(6))
  assert(en:find('^presets exported: 2 preset%(s%), 5 profiles %(app folder in CSP, fallback'),en)
  -- Import relu dans le dossier de repli.
  e.profiles.C.levelPct=100
  PF.ask(pio,'import',e,a,L,note)
  assert(pio.pending=='import' and pio.where=='state','read from the fallback folder')
  PF.confirm(pio,e,a,L,note,A.savePreset)
  assert(e.profiles.C.levelPct==103,'imported from the fallback')
  -- Les deux dossiers refusés : échec annoncé, rien d'écrit.
  local fs2,restore2=files({[DOCS]=true,[STATE]=true})
  local ok2,err2=pcall(function()
   msg,kind=PF.ask(pio,'export',e,a,L,note)
   assert(kind=='er' and msg==L.presetIOExportFailed and fs2.writes==0,'both refused')
   assert(lines[#lines]:find('^WARN export des prereglages impossible'),lines[#lines])
  end)
  restore2(); assert(ok2,err2)
 end)
 restore(); assert(ok,err)
end
tests.PRESET_FILE_CORRUPT_159HC=function()
 local fs,restore=files()
 local ok,err=pcall(function()
  local e,a,note,lines=scene(); setup(e,a)
  local pio={}
  PF.ask(pio,'export',e,a,L,note)
  local path=DOCS..'\\'..K.presetFileName
  local good=fs.files[path]
  e.profiles.C.levelPct=100
  local before=signatures(e,a)
  for _,bad in ipairs({good..'\nthis is not a setting\n',good:gsub('format=1','format=9',1),good:gsub('p_levelPct=103','p_levelPct=1%%G3',1),'',string.rep('x',K.presetFileMaxBytes+1)}) do
   fs.files[path]=bad
   local msg,kind=PF.ask(pio,'import',e,a,L,note)
   assert(kind=='er' and not pio.pending and not pio.staged and msg:find(L.presetIOImportFailed,1,true),'refused: '..msg)
   assert(signatures(e,a)==before,'nothing changed')
   assert(lines[#lines]:find('^WARN import des prereglages refuse: .*, rien n a change'),lines[#lines])
   assert(Journal.english(lines[#lines]:sub(6)):find('^preset import refused: '),'english pattern')
  end
  fs.files[path]=nil
  local msg,kind=PF.ask(pio,'import',e,a,L,note)
  assert(kind=='er' and msg:find(L.presetIOReasons.none,1,true),'no file')
 end)
 restore(); assert(ok,err)
end
tests.PRESET_FILE_EXPORT_CONFIRM_159HC=function()
 local fs,restore=files()
 local ok,err=pcall(function()
  local e,a,note=scene(); setup(e,a)
  local pio={}
  PF.ask(pio,'export',e,a,L,note)
  local path=DOCS..'\\'..K.presetFileName
  local first=fs.files[path]; local writes=fs.writes
  e.profiles.C.levelPct=90
  local msg,kind=PF.ask(pio,'export',e,a,L,note)
  assert(pio.pending=='export' and kind=='wn' and msg==L.presetIOAskExport and fs.writes==writes,'existing file: confirmation first')
  PF.cancel(pio); assert(not pio.pending and fs.files[path]==first,'cancel keeps the file')
  PF.ask(pio,'export',e,a,L,note); msg,kind=PF.confirm(pio,e,a,L,note,A.savePreset)
  assert(kind=='ok' and fs.files[path]~=first and fs.files[path]:find('p_levelPct=90',1,true),'confirmed: replaced')
 end)
 restore(); assert(ok,err)
end
tests.PRESET_FILE_TEXTS_159HC=function()
 local en=require('src/lang_en')
 for _,key in ipairs({'presetIOExport','presetIOImport','presetIOConfirm','presetIOCancel','presetIOAskExport','presetIOAskImport','presetIOExported',
  'presetIOExportedFallback','presetIOExportFailed','presetIOImportFailed','presetIOImported','presetIOImportedNotes','presetIOFolderDocs','presetIOFolderState'}) do
  assert(type(L[key])=='string' and type(en[key])=='string',key)
 end
 for reason in pairs({none=1,corrupt=1,big=1,format=1,empty=1}) do assert(L.presetIOReasons[reason] and en.presetIOReasons[reason],reason) end
 local T=require('src/tips'); local TE=require('src/tips_en')
 assert(T.ui.presetExport and T.ui.presetImport and TE.ui.presetExport and TE.ui.presetImport,'tooltips')
 for _,line in ipairs({'prereglages exportes: 3 prereglage(s), 5 profils (Documents\\Assetto Corsa\\AdvancedIA)',
  'prereglages importes: 3 prereglage(s), 5 profil(s), 0 valeur(s) corrigee(s), 1 ignore(s) (dossier de l app dans CSP)',
  'export des prereglages impossible: ecriture refusee (Documents\\Assetto Corsa\\AdvancedIA et dossier de l app dans CSP)'}) do
  local out=Journal.english(line); assert(out~=line and not out:find('prereglage',1,true),out)
 end
end
return tests
