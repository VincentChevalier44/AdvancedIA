-- Beta 1.61 (étape de base) : codec des fichiers par circuit (zones : src/zones.lua, tranche A ; allure gardée d'une
-- session à l'autre : src/pacemap.lua, tranche B). Texte seulement : aucun accès aux fichiers ici (l'applicateur
-- lit et écrit, Adapter.trackFileRead / trackFileWrite). Format INI comme le fichier des préréglages (Beta 1.59) :
-- une section d'en-tête [AdvancedIA] (format, kind, release, track, layout, length, serial), puis des sections
-- nommées dans l'ordre du fichier. Rien de ce qui est lu n'est cru : taille bornée, nombre de sections et de clés
-- borné, chaque valeur rendue par un lecteur typé et borné (M.number, M.integer, M.boolean, M.text) ; rien n'est
-- exécuté. Une clé inconnue est ignorée par l'appelant, qui ne lit que les clés qu'il connaît.
local C=require('src/config')
local K=C.K
local M={}
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
 if type(v)=='number' then
  if v~=v or v==math.huge or v==-math.huge then return nil end
  local t=tostring(v); if tonumber(t)~=v then t=string.format('%.17g',v) end
  return t
 end
 if type(v)=='string' then return escape(v) end
 return nil
end
M.headKeys={format=true,kind=true,release=true,track=true,layout=true,length=true,serial=true}
-- Identifiant de circuit ou de tracé acceptable dans un nom de fichier.
local function plain(s,allowEmpty)
 if type(s)~='string' or #s>K.trackKeyMax then return false end
 if s=='' then return allowEmpty==true end
 return s:match('^[%w_%-]+$')~=nil
end
-- Clé de fichier d'un circuit et de son tracé (« imola », « ks_nordschleife__touristenfahrten ») ; nil si l'un des
-- deux identifiants ne peut pas servir de nom de fichier.
function M.key(track,layout)
 if not plain(track,false) or not plain(layout or '',true) then return nil end
 local key=(layout==nil or layout=='') and track or track..'__'..layout
 if #key>K.trackKeyMax then return nil end
 return key
end
-- Texte d'un fichier. head : kind, track, layout, length, serial (format et release ajoutés ici), plus les autres
-- clés de head (triées) ; sections : liste de {name=<nom>, <clé>=<valeur>, …}, écrites dans l'ordre, clés triées
-- (name à part). title : première ligne. Nom de section : lettres, chiffres, « . », « _ », « : » et « - ».
function M.build(title,head,sections)
 local out={}
 if type(title)=='string' and title~='' then out[1]='; '..title:gsub('%c',' ') end
 out[#out+1]='[AdvancedIA]'
 out[#out+1]='format='..K.trackFileFormat
 out[#out+1]='kind='..escape(tostring(head.kind or ''))
 out[#out+1]='release='..escape(C.release)
 out[#out+1]='track='..escape(tostring(head.track or ''))
 out[#out+1]='layout='..escape(tostring(head.layout or ''))
 out[#out+1]='length='..string.format('%.0f',M.number(head.length,0,1e9) or 0)
 out[#out+1]='serial='..string.format('%.0f',M.number(head.serial,0,1e9) or 0)
 local keys={}
 for key in pairs(head) do if type(key)=='string' and key:match('^[%w_]+$') and not M.headKeys[key] then keys[#keys+1]=key end end
 table.sort(keys)
 for _,key in ipairs(keys) do local v=value(head[key]); if v then out[#out+1]=key..'='..v end end
 out[#out+1]=''
 for _,section in ipairs(sections or {}) do
  if type(section.name)=='string' and section.name:match('^[%w%._:%-]+$') and section.name~='AdvancedIA' then
   out[#out+1]='['..section.name..']'
   for k=#keys,1,-1 do keys[k]=nil end
   for key in pairs(section) do if key~='name' and type(key)=='string' and key:match('^[%w_]+$') then keys[#keys+1]=key end end
   table.sort(keys)
   for _,key in ipairs(keys) do local v=value(section[key]); if v then out[#out+1]=key..'='..v end end
   out[#out+1]=''
  end
 end
 return table.concat(out,'\n')
end
-- Lecture brute : {head=<clés de l'en-tête>, sections={ {name=…, values={clé=chaîne}} … }, dropped=<lignes ou
-- sections écartées>}, ou nil et la raison ('corrupt', 'big', 'format'). maxBytes : taille maximale du texte ;
-- maxSections : nombre maximal de sections gardées (le reste est compté dans dropped).
function M.parse(text,maxBytes,maxSections)
 if type(text)~='string' then return nil,'corrupt' end
 if #text>(maxBytes or K.trackFileMaxBytes) then return nil,'big' end
 if text:sub(1,3)=='\239\187\191' then text=text:sub(4) end
 local doc={head=nil,sections={},dropped=0}
 local limit=maxSections or K.trackFileMaxSections
 local current=nil
 local count=0
 for line in (text..'\n'):gmatch('([^\n]*)\n') do
  line=line:gsub('\r$',''):gsub('^%s+',''):gsub('%s+$','')
  if line=='' or line:sub(1,1)==';' or line:sub(1,1)=='#' then
  elseif line:match('^%[[%w%._:%-]+%]$') then
   local name=line:sub(2,-2)
   count=0
   if name=='AdvancedIA' then
    if doc.head then return nil,'corrupt' end
    doc.head={}; current=doc.head
   elseif #doc.sections>=limit then current=false; doc.dropped=doc.dropped+1
   else current={}; doc.sections[#doc.sections+1]={name=name,values=current} end
  else
   local key,raw=line:match('^([%w_]+)%s*=%s*(.-)$')
   if not key or current==nil then return nil,'corrupt' end
   if current then
    local v=unescape(raw)
    count=count+1
    if not v or count>K.trackFileMaxKeys or #v>K.trackFileMaxValue then doc.dropped=doc.dropped+1 else current[key]=v end
   end
  end
 end
 if not doc.head or tonumber(doc.head.format)~=K.trackFileFormat then return nil,'format' end
 return doc
end
-- En-tête contre la session : true et lengthOK (longueur à K.trackLengthTol près), ou false et la raison ('kind',
-- 'track', 'layout'). Un fichier copié d'un autre circuit est refusé ; une longueur différente est signalée à
-- l'appelant, qui décide (les zones apprises sont alors écartées, celles du pilote gardées).
function M.check(doc,kind,track,layout,length)
 local head=doc and doc.head
 if type(head)~='table' or head.kind~=kind then return false,'kind' end
 if head.track~=track then return false,'track' end
 if (head.layout or '')~=(layout or '') then return false,'layout' end
 local stored=M.number(head.length,0,1e6)
 local lengthOK=stored~=nil and type(length)=='number' and length>0 and math.abs(stored-length)<=K.trackLengthTol*length
 return true,lengthOK
end
-- Lecteurs typés et bornés : nil si la valeur n'est pas du type attendu ou sort de la plage.
function M.number(text,min,max)
 local v=tonumber(text)
 if type(v)~='number' or v~=v or v==math.huge or v==-math.huge then return nil end
 if min and v<min or max and v>max then return nil end
 return v
end
function M.integer(text,min,max)
 local v=M.number(text,min,max)
 if not v or v%1~=0 then return nil end
 return v
end
function M.boolean(text)
 if text=='true' then return true elseif text=='false' then return false end
 return nil
end
-- Texte libre (note du pilote) : caractères de contrôle retirés, coupé à max caractères.
function M.text(text,max)
 if type(text)~='string' then return nil end
 return (text:gsub('%c','')):sub(1,max or K.trackFileMaxValue)
end
-- Numéro de série lu (0 si absent ou faux) : vieillissement par nombre d'écritures, jamais par l'horloge.
function M.serial(doc) return doc and doc.head and M.integer(doc.head.serial,0,1e9) or 0 end
return M
