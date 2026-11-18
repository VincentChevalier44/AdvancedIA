-- Relecture adversariale 2.0.4, domaine C (moteur, liaisons, fichiers) : verrous LOCK_REVIEW204C_<n>. Chargé par
-- tests/extended.lua. LOCK_REVIEW204C_2 (clé de session fermée après une erreur du pont) est dans
-- tests/integration_cases.lua (cas « Beta 1.63 : cle de session pour SetupLab… »).
local C=require('src/config')
local K=C.K
local tests={}

-- Banc de fichiers factice (comme TRACKFILE_IO_161) : io.save(…, true) laisse l'ancien contenu en <fichier>.bak.
local function fakeFiles(run)
 local saved={save=io.save,load=io.load,fileExists=io.fileExists,createDir=io.createDir,fileSize=io.fileSize,deleteFile=io.deleteFile}
 local savedAc={getFolder=ac.getFolder,FolderID=ac.FolderID}
 local fs={files={},refuse={}}
 ac.FolderID={ACDocuments=1001,ScriptConfig=1002}
 ac.getFolder=function(id) return id==1001 and 'DOCS' or id==1002 and 'STATE' or 'other' end
 io.createDir=function() return true end
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
 local ok,err=pcall(run,fs)
 io.save,io.load,io.fileExists,io.createDir,io.fileSize,io.deleteFile=saved.save,saved.load,saved.fileExists,saved.createDir,saved.fileSize,saved.deleteFile
 ac.getFolder,ac.FolderID=savedAc.getFolder,savedAc.FolderID
 assert(ok,err)
end

-- LOCK_REVIEW204C_1 : l'export des préréglages remplacé ne laisse plus de reste <fichier>.bak dans Documents (ni dans le
-- dossier de repli) ; le fichier exporté et sa relecture sont inchangés.
tests.LOCK_REVIEW204C_1=function()
 local A=require('src/applier')
 fakeFiles(function(fs)
  local docs='DOCS\\'..K.presetFolder..'\\'..K.presetFileName
  assert(A.presetFileWrite('one')=='docs' and fs.files[docs]=='one','first export')
  assert(A.presetFileWrite('two')=='docs' and fs.files[docs]=='two','second export replaces')
  assert(fs.files[docs..'.bak']==nil,'no .bak left in Documents')
  local text,place=A.presetFileRead(); assert(text=='two' and place=='docs','read back')
  fs.refuse['DOCS']=true
  local state='STATE\\'..K.presetFileName
  assert(A.presetFileWrite('s1')=='state' and A.presetFileWrite('s2')=='state' and fs.files[state]=='s2','fallback folder')
  assert(fs.files[state..'.bak']==nil,'no .bak left in the fallback folder')
 end)
end

return tests
