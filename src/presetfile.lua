-- Beta 1.59 (décision du pilote) : préréglages personnels et réglages des cinq profils exportés dans un fichier
-- (Documents\Assetto Corsa\AdvancedIA\AdvancedIA-presets.ini, à partager), puis importés. Repli : dossier de l'app dans
-- CSP (cfg\extension\state\lua\app\…) si CSP refuse l'écriture dans Documents. Le fichier reprend le format des
-- préréglages (src/presets.lua) : chaque section est relue par Presets.decode (validation et migrations), clé inconnue
-- ignorée, valeur hors plage remplacée par le défaut et comptée. Jamais exportés ni importés : la graine, le journal
-- détaillé, et tout réglage hors des préréglages (mise à jour, sécurité, langue, fenêtre). L'import est d'abord
-- préparé en entier (rien n'est changé), puis appliqué sur confirmation.
local C=require('src/config')
local Presets=require('src/presets')
local Adapter=require('src/applier')
local K=C.K
local M={}
-- Clés globales qui voyagent : celles des préréglages, sans la graine ni le journal détaillé.
local excluded={seed=true,debugLog=true}
M.globalKeys={}
for _,key in ipairs(Presets.globalKeys) do if not excluded[key] then M.globalKeys[#M.globalKeys+1]=key end end
-- Chaîne écrite telle quelle, sauf %, caractères de contrôle et espaces en bord (codés %XX) : une ligne par valeur.
local function escape(s)
 s=s:gsub('[%%%c]',function(ch) return string.format('%%%02X',ch:byte()) end)
 s=s:gsub('^ ','%%20'):gsub(' $','%%20')
 return s
end
local function unescape(s)
 if s:find('%%%X') or s:find('%%%x%X') or s:find('%%$') or s:find('%%%x$') then return nil end
 return (s:gsub('%%(%x%x)',function(h) return string.char(tonumber(h,16)) end))
end
local function value(v)
 if type(v)=='boolean' then return v and 'true' or 'false' end
 if type(v)=='number' then local t=tostring(v); if tonumber(t)~=v then t=string.format('%.17g',v) end return t end
 if type(v)=='string' then return escape(v) end
 return nil
end
-- Valeur lue rendue au type du défaut ; type inconnu : chaîne laissée (la validation la refuse et la compte).
local function typed(text,default)
 if type(default)=='boolean' then if text=='true' then return true elseif text=='false' then return false end return text end
 if type(default)=='number' then return tonumber(text) or text end
 return text
end
local function section(out,name,fields)
 out[#out+1]='['..name..']'
 local keys={}
 for key in pairs(fields) do keys[#keys+1]=key end
 table.sort(keys)
 for _,key in ipairs(keys) do local v=value(fields[key]); if v then out[#out+1]=key..'='..v end end
 out[#out+1]=''
end
-- Texte du fichier : en-tête, profils (format d'un préréglage nommé « profile X »), options globales, préréglages.
function M.build(profiles,g,presets)
 local out={'; AdvancedIA: custom presets and profile settings ('..C.release..'). Import them from the HOME tab.',''}
 section(out,'AdvancedIA',{format=K.presetFileFormat,release=C.release,schemaVersion=C.version,revision=Presets.revision})
 local nProfiles,nPresets=0,0
 for _,profile in ipairs(C.profiles) do
  if profiles[profile] then
   local fields=Presets.encode({name='profile '..profile,profile=profile,p=profiles[profile],g=g})
   for _,key in ipairs(Presets.globalKeys) do fields['g_'..key]=nil end
   section(out,'profile.'..profile,fields); nProfiles=nProfiles+1
  end
 end
 local globals={}
 for _,key in ipairs(M.globalKeys) do globals[key]=g[key] end
 section(out,'globals',globals)
 for i=1,K.maxPresets do
  local entry=presets[i]
  if entry then
   local fields=Presets.encode(entry)
   for key in pairs(excluded) do fields['g_'..key]=nil end
   nPresets=nPresets+1; section(out,'preset.'..nPresets,fields)
  end
 end
 return table.concat(out,'\n'),nPresets,nProfiles
end
-- Lecture brute : sections et leurs clés (chaînes), ou nil et la raison ('corrupt', 'big', 'format').
function M.parse(text)
 if type(text)~='string' then return nil,'corrupt' end
 if #text>K.presetFileMaxBytes then return nil,'big' end
 -- Relecture 1.59 : marque d'ordre des octets UTF-8 en tête (fichier repris par un éditeur de texte).
 if text:sub(1,3)=='\239\187\191' then text=text:sub(4) end
 local doc={sections={},order={}}
 local current=nil
 for line in (text..'\n'):gmatch('([^\n]*)\n') do
  line=line:gsub('\r$',''):gsub('^%s+',''):gsub('%s+$','')
  if line=='' or line:sub(1,1)==';' or line:sub(1,1)=='#' then
  elseif line:match('^%[[%w%._]+%]$') then
   local name=line:sub(2,-2)
   current=doc.sections[name]
   if not current then current={}; doc.sections[name]=current; doc.order[#doc.order+1]=name end
  else
   local key,raw=line:match('^([%w_]+)%s*=%s*(.-)$')
   if not key or not current then return nil,'corrupt' end
   local v=unescape(raw)
   if not v then return nil,'corrupt' end
   current[key]=v
  end
 end
 local head=doc.sections.AdvancedIA
 if not head or tonumber(head.format)~=K.presetFileFormat then return nil,'format' end
 return doc
end
-- Section d'un préréglage rendue aux types attendus par Presets.decode ; clés globales exclues prises dans g.
local function store(fields,g)
 local profile=fields.profile
 local defaults=C.defaults((profile=='J' or profile=='P' or profile=='Q' or profile=='C' or profile=='H') and profile or 'J')
 local out={name=fields.name,profile=profile,schemaVersion=tonumber(fields.schemaVersion),revision=tonumber(fields.revision)}
 for key,default in pairs(defaults) do
  local raw=fields['p_'..key]; if raw~=nil then out['p_'..key]=typed(raw,default) end
 end
 for _,key in ipairs(Presets.globalKeys) do
  local raw=fields['g_'..key]
  if excluded[key] or raw==nil then out['g_'..key]=g[key] else out['g_'..key]=typed(raw,C.globalDefaults[key]) end
 end
 return out
end
-- Import préparé, rien n'est changé : profils validés, options globales, préréglages relus ; valeurs corrigées et
-- préréglages ignorés comptés. nil et la raison si le fichier ne contient rien d'utilisable.
function M.prepare(doc,g)
 local staged={profiles={},globals=nil,presets={},corrected=0,skipped=0,nProfiles=0}
 for _,profile in ipairs(C.profiles) do
  local fields=doc.sections['profile.'..profile]
  if fields then
   fields.profile=profile; fields.name=fields.name or ('profile '..profile)
   local ok,entry,errors=pcall(Presets.decode,store(fields,g))
   if ok and entry and entry.profile==profile then staged.profiles[profile]=entry.p; staged.nProfiles=staged.nProfiles+1; staged.corrected=staged.corrected+errors
   else staged.skipped=staged.skipped+1 end
  end
 end
 local globals=doc.sections.globals
 if globals then
  local copy={}
  for key,v in pairs(g) do copy[key]=v end
  local present=0
  for _,key in ipairs(M.globalKeys) do if globals[key]~=nil then copy[key]=typed(globals[key],C.globalDefaults[key]); present=present+1 end end
  local ok,checked,errors=pcall(C.validateGlobals,copy)
  if ok and present>0 then staged.globals={}; for _,key in ipairs(M.globalKeys) do staged.globals[key]=checked[key] end; staged.corrected=staged.corrected+errors end
 end
 for _,name in ipairs(doc.order) do
  if name:match('^preset%.%d+$') then
   local ok,entry,errors=pcall(Presets.decode,store(doc.sections[name],g))
   if ok and entry and #staged.presets<K.maxPresets then staged.presets[#staged.presets+1]=entry; staged.corrected=staged.corrected+errors
   else staged.skipped=staged.skipped+1 end
  end
 end
 if staged.nProfiles==0 and not staged.globals and #staged.presets==0 then return nil,'empty' end
 return staged
end
-- Import appliqué (après confirmation) : réglages des profils et options globales, puis préréglages enregistrés (un
-- nom existant est remplacé ; plus de place : ignoré). Rend le nombre de préréglages enregistrés.
function M.apply(staged,profiles,g,host,save)
 for profile,p in pairs(staged.profiles) do
  local target=profiles[profile]
  if target then C.validate(profile,p,target); target.configured=true end
 end
 if staged.globals then for key,v in pairs(staged.globals) do g[key]=v end end
 local saved=0
 for _,entry in ipairs(staged.presets) do
  if save(host,entry) then saved=saved+1 else staged.skipped=staged.skipped+1 end
 end
 return saved
end
-- Fichier : écrit, relu et cherché par l'applicateur (seul accès aux fichiers ; Adapter.presetFile*).
function M.exported() return Adapter.presetFileExported() end
function M.write(text) return Adapter.presetFileWrite(text) end
function M.read() return Adapter.presetFileRead() end
-- Actions de l'accueil. io_ : état gardé par la fenêtre {pending, staged, where} ; L : textes de la langue en cours ;
-- note(level,text) : journal. Rendent le message à afficher et son genre.
local function place(L,where) return where=='docs' and L.presetIOFolderDocs or L.presetIOFolderState end
local function logPlace(where) return where=='docs' and 'Documents\\Assetto Corsa\\AdvancedIA' or 'dossier de l app dans CSP' end
local function export(io_,e,host,L,note)
 io_.pending=nil
 local ok,text,nPresets,nProfiles=pcall(M.build,e.profiles,e.g,host.presets)
 local where=ok and M.write(text) or nil
 if not where then
  note('WARN','export des prereglages impossible: ecriture refusee (Documents\\Assetto Corsa\\AdvancedIA et dossier de l app dans CSP)')
  return L.presetIOExportFailed,'er'
 end
 if where=='docs' then
  note('INFO',string.format('prereglages exportes: %d prereglage(s), %d profils (Documents\\Assetto Corsa\\AdvancedIA)',nPresets,nProfiles))
  return string.format(L.presetIOExported,nPresets,nProfiles,place(L,where)),'ok'
 end
 note('WARN',string.format('prereglages exportes: %d prereglage(s), %d profils (dossier de l app dans CSP, repli : ecriture refusee dans Documents\\Assetto Corsa\\AdvancedIA)',nPresets,nProfiles))
 return string.format(L.presetIOExportedFallback,nPresets,nProfiles),'wn'
end
local reasons={none='aucun fichier trouve',corrupt='fichier illisible ou abime',big='fichier trop gros',format='fichier illisible ou abime',empty='rien a importer'}
function M.ask(io_,action,e,host,L,note)
 io_.pending=nil; io_.staged=nil
 if action=='export' then
  if M.exported() then io_.pending='export'; return L.presetIOAskExport,'wn' end
  return export(io_,e,host,L,note)
 end
 local text,where=M.read()
 local doc,reason=nil,'none'
 if text then doc,reason=M.parse(text) end
 local staged
 if doc then staged,reason=M.prepare(doc,e.g) end
 if not staged then
  note('WARN','import des prereglages refuse: '..reasons[reason or 'corrupt']..', rien n a change')
  return L.presetIOImportFailed..(L.presetIOReasons[reason or 'corrupt'] or ''),'er'
 end
 io_.pending='import'; io_.staged=staged; io_.where=where
 return string.format(L.presetIOAskImport,#staged.presets,staged.nProfiles,place(L,where)),'wn'
end
function M.confirm(io_,e,host,L,note,save)
 local action=io_.pending; io_.pending=nil
 if action=='export' then return export(io_,e,host,L,note) end
 local staged=io_.staged; io_.staged=nil
 if action~='import' or not staged then return '','mut' end
 local saved=M.apply(staged,e.profiles,e.g,host,save)
 note('INFO',string.format('prereglages importes: %d prereglage(s), %d profil(s), %d valeur(s) corrigee(s), %d ignore(s) (%s)',saved,staged.nProfiles,staged.corrected,staged.skipped,logPlace(io_.where)))
 local text=string.format(L.presetIOImported,saved,staged.nProfiles)
 if staged.corrected>0 or staged.skipped>0 then text=text..string.format(L.presetIOImportedNotes,staged.corrected,staged.skipped) end
 return text,(staged.corrected>0 or staged.skipped>0) and 'wn' or 'ok'
end
function M.cancel(io_) io_.pending=nil; io_.staged=nil; return '','mut' end
return M
