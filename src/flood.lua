-- AI flood de CSP (Beta 1.26, demande du pilote) : en journée circuit, CSP fait apparaître et disparaître les IA autour
-- du joueur (à moins de 1 km par défaut), sur les circuits assez longs. Réglage de l'utilisateur dans
-- Documents/Assetto Corsa/cfg/extension/new_behaviour.ini, section [AI_FLOOD] ; valeurs par défaut de CSP dans
-- extension/config/new_behaviour.ini. Texte pur, sans accès au jeu : seules les clés gérées de la section changent, le
-- reste du fichier (sections, commentaires, fins de ligne) est conservé tel quel.
local C=require('src/config')
local K=C.K
local M={}
M.section='AI_FLOOD'
M.keys={'ENABLED','SPAWN_MIN_DISTANCE_TO_PLAYER','SPAWN_DISTANCE','SPAWN_RANGE','SPAWN_DESPAWN'}
-- Distances de CSP pour 1 km de portée (une voie, plusieurs voies), mises à l'échelle de la portée choisie.
M.spawn={SPAWN_MIN_DISTANCE_TO_PLAYER={400,200},SPAWN_DISTANCE={600,300},SPAWN_RANGE={200,100},SPAWN_DESPAWN={1000,400}}
local function trim(s) return (s:gsub('^%s+',''):gsub('%s+$','')) end
local function lines(text)
 local out={}
 local normalized=(text or ''):gsub('\r\n','\n')
 if normalized~='' and normalized:sub(-1)~='\n' then normalized=normalized..'\n' end
 for line in normalized:gmatch('([^\n]*)\n') do out[#out+1]=line end
 return out
end
local function header(line) local name=line:match('^%s*%[([^%]]+)%]'); return name and trim(name):upper() or nil end
local function keyOf(line) local k=line:match('^%s*([^=;%[]+)=') ; return k and trim(k):upper() or nil end
-- Valeur d'une clé (dernière occurrence dans la section), commentaire « ; » retiré ; nil si absente.
function M.get(text,section,key)
 local current,value=nil,nil
 section=section:upper(); key=key:upper()
 for _,line in ipairs(lines(text)) do
  local name=header(line)
  if name then current=name
  elseif current==section and keyOf(line)==key then value=trim((line:match('=(.*)$') or ''):gsub(';.*$','')) end
 end
 return value
end
-- Clés de values (texte, ou false pour la retirer) écrites dans la section, dans l'ordre de order (M.keys par défaut ;
-- Beta 1.40 : aussi pour les options de CSP de gui.ini) ; les autres lignes restent intactes. Section ajoutée en fin de
-- fichier si elle manque.
function M.edit(text,section,values,order)
 text=text or ''
 local eol=text:find('\r\n',1,true) and '\r\n' or '\n'
 local target=section:upper()
 local out,done={},{}
 local current,last=nil,nil
 for _,line in ipairs(lines(text)) do
  local name=header(line)
  if name then
   current=name; out[#out+1]=line
   if current==target and not last then last=#out end
  else
   local key=current==target and keyOf(line) or nil
   if key and values[key]~=nil then
    if values[key]~=false and not done[key] then out[#out+1]=key..'='..values[key]; done[key]=true end
   else out[#out+1]=line end
   if current==target and last and trim(line)~='' and #out>last then last=#out end
  end
 end
 local add={}
 for _,key in ipairs(order or M.keys) do if values[key] and not done[key] then add[#add+1]=key..'='..values[key] end end
 if #add>0 then
  if last then for k=#add,1,-1 do table.insert(out,last+1,add[k]) end
  else
   if #out>0 and trim(out[#out])~='' then out[#out+1]='' end
   out[#out+1]='['..section..']'
   for _,line in ipairs(add) do out[#out+1]=line end
  end
 end
 if #out==0 then return '' end
 return table.concat(out,eol)..eol
end
-- Booléen d'une valeur d'INI (nil si absente) ; aussi pour les options de CSP de gui.ini (Beta 1.40).
function M.truthy(v) if v==nil then return nil end v=v:lower(); return not (v=='0' or v=='false' or v=='no' or v=='off') end
-- État d'AI flood : actif ou non, longueur minimale du circuit (m) ; réglage de l'utilisateur, sinon défaut de CSP.
function M.state(user,system)
 local enabled=M.truthy(M.get(user,M.section,'ENABLED'))
 if enabled==nil then enabled=M.truthy(M.get(system,M.section,'ENABLED')) end
 if enabled==nil then enabled=true end
 local length=tonumber(M.get(user,M.section,'MIN_TRACK_LENGTH') or '') or tonumber(M.get(system,M.section,'MIN_TRACK_LENGTH') or '') or K.floodMinLength
 return enabled,length
end
local function round(v) return math.floor(v/K.floodRound+0.5)*K.floodRound end
-- Valeurs voulues : désactivé (portée inchangée), ou activé avec la portée en km.
function M.values(on,range)
 local out={ENABLED=on and '1' or '0'}
 if on then
  for key,pair in pairs(M.spawn) do out[key]=string.format('%d, %d',round(pair[1]*range),round(pair[2]*range)) end
 end
 return out
end
-- Sauvegarde des clés gérées telles qu'avant la première écriture de l'app (clé absente : nom seul).
function M.backup(text)
 local parts={'v1'}
 for _,key in ipairs(M.keys) do
  local v=M.get(text,M.section,key)
  parts[#parts+1]=v and key..'='..v:gsub('|','') or key
 end
 return table.concat(parts,'|')
end
function M.restore(backup)
 local out={}
 for part in (backup or ''):gmatch('[^|]+') do
  local key,value=part:match('^([%u_]+)=(.*)$')
  if key then out[key]=value elseif part:match('^[%u_]+$') and part~='v1' then out[part]=false end
 end
 return out
end
-- Décision pour une journée circuit : 'restore' (départ laissé au jeu : réglage d'origine rendu), 'off' (assez d'IA
-- pour les répartir sur tout le circuit), 'on' (sous le seuil : AI flood avec la portée choisie).
-- Beta 1.52 : réglage absent : valeur du schéma (profil Course : départ laissé au jeu), au lieu de valeurs répétées ici.
local fallback=C.defaults('C')
function M.decide(p,count)
 if (p.spawnMode or fallback.spawnMode)=='native' then return 'restore' end
 return count>=(p.spawnMinCars or fallback.spawnMinCars) and 'off' or 'on'
end
return M
