local U=require('src/util')
local C=require('src/config')
local K=C.K
local M={}
-- Grammaire de données seulement : return { {from=...,to=...,...}, ... }.
-- Aucun environnement Lua ni exécution de texte utilisateur.
function M.parse(text)
 if type(text)~='string' or #text>K.maxZoneBytes then return nil,'size' end
 local pos,len=1,#text
 local function skip()
  while pos<=len do
   local a,b=text:find('^%s+',pos)
   if a then pos=b+1 elseif text:sub(pos,pos+1)=='--' then
    local e=text:find('\n',pos+2,true); pos=e and e+1 or len+1
   else break end
  end
 end
 local function token(s) skip(); if text:sub(pos,pos+#s-1)==s then pos=pos+#s; return true end return false end
 local function value()
  skip(); local c=text:sub(pos,pos)
  if c=='"' or c=="'" then
   pos=pos+1; local start=pos
   while pos<=len and text:sub(pos,pos)~=c do
    if text:sub(pos,pos)=='\\' or text:byte(pos)<32 then return nil end
    pos=pos+1
   end
   if pos>len or pos-start>256 then return nil end
   local s=text:sub(start,pos-1); pos=pos+1; return s
  end
  if token('true') then return true end
  if token('false') then return false end
  skip(); local a,b=text:find('^[%+%-]?%d*%.?%d+[eE]?[%+%-]?%d*',pos)
  if not a then return nil end
  local n=tonumber(text:sub(a,b)); pos=b+1
  if not U.finite(n) then return nil end
  return n
 end
 token('return')
 if not token('{') then return nil,'syntax' end
 local wrapped=token('zones')
 if wrapped and (not token('=') or not token('{')) then return nil,'wrapper' end
 local out={}
 while true do
  if token('}') then break end
  if #out>=K.maxZones or not token('{') then return nil,'count' end
  local zone={noYield=false,noOvertake=false,maxOffset=1,note=''}; local seen={}
  while not token('}') do
   skip(); local a,b=text:find('^[%a_][%w_]*',pos)
   if not a then return nil,'key' end
   local key=text:sub(a,b); pos=b+1
   if not ({from=true,to=true,noYield=true,noOvertake=true,maxOffset=true,note=true})[key] or seen[key] or not token('=') then return nil,'key' end
   local v=value(); if v==nil then return nil,'value' end
   if key=='from' or key=='to' or key=='maxOffset' then
    if not U.finite(v) or v<0 or v>1 then return nil,'range' end
   elseif key=='note' then if type(v)~='string' then return nil,'type' end
   elseif type(v)~='boolean' then return nil,'type' end
   zone[key]=v; seen[key]=true
   if not token(',') and not token(';') then skip(); if text:sub(pos,pos)~='}' then return nil,'separator' end end
  end
  if not seen.from or not seen.to then return nil,'endpoints' end
  out[#out+1]=zone
  if not token(',') and not token(';') then skip(); if text:sub(pos,pos)~='}' then return nil,'separator' end end
 end
 if wrapped and not token('}') then return nil,'wrapper' end
 skip(); if pos<=len then return nil,'trailing' end
 return out
end
-- Beta 1.61 (tranche A) : un seul modèle de zone par circuit. La liste (tableau) porte les zones du circuit qui sont
-- lues à chaque image : fichier d'origine tracks/<circuit>.lua (source file, jamais écrit), zones du pilote (source
-- user) et zones apprises confirmées (source learnt). Champs à côté du tableau : learnt (toutes les zones apprises,
-- confirmées ou non, points de freinage compris), brakes (points de freinage connus, fractions de tour triées),
-- extra (au moins une zone qui n'est pas « sans manœuvre »), cautionN / attackN / lineN, attackFrom (débuts triés des
-- zones d'attaque), serial (numéro de série du fichier), cautionPause (pause du départ, posée par
-- src/zonelearn.lua). Genres : nomove (ou absent : fichier d'origine), caution, attack, line, brake (point : from).
local TrackFile=require('src/trackfile')
local function inside(z,progress) return (z.from<=z.to and progress>=z.from and progress<=z.to) or (z.from>z.to and (progress>=z.from or progress<=z.to)) end
function M.at(zones,progress,out)
 out.noYield=false; out.noOvertake=false; out.maxOffset=1
 if not zones.extra then
  -- Liste d'origine (aucune zone d'un genre nouveau) : comme avant la 1.61 ; champs nouveaux effacés une fois.
  if out.zoned then out.zoned=nil; out.caution=nil; out.passMargin=nil; out.attack=nil; out.line=nil; out.passWait=nil; out.lineOffset=nil; out.waitNext=nil; out.lineNext=nil; out.noBoost=nil end
  for i=1,#zones do
   local z=zones[i]
   if not z.off and inside(z,progress) and z.kind~='brake' then
    out.noYield=out.noYield or z.noYield; out.noOvertake=out.noOvertake or z.noOvertake; out.maxOffset=math.min(out.maxOffset,z.maxOffset)
   end
  end
  return out
 end
 out.zoned=true; out.caution=nil; out.passMargin=nil; out.attack=nil; out.line=nil
 for i=1,#zones do
  local z=zones[i]
  if not z.off and inside(z,progress) then
   local kind=z.kind
   if kind==nil or kind=='nomove' then
    out.noYield=out.noYield or z.noYield; out.noOvertake=out.noOvertake or z.noOvertake; out.maxOffset=math.min(out.maxOffset,z.maxOffset)
   elseif kind=='caution' then out.caution=true
   elseif kind=='attack' then out.attack=true
   elseif kind=='line' then out.line=z end
  end
 end
 -- Priorités à un même endroit : la pause du départ suspend les points difficiles ; « sans manœuvre » et point
 -- difficile passent devant la zone d'attaque ; une voiture déjà attaquée par une autre ne donne pas la marge.
 if out.caution and zones.cautionPause then out.caution=nil end
 if out.attack and not out.noOvertake and not out.caution and not out.noBoost then out.passMargin=K.attackMargin end
 -- Attente d'une zone d'attaque et ligne de la zone : décidées par src/zonelearn.lua après le pilotage (image d'avant).
 out.passWait=out.waitNext; out.lineOffset=out.lineNext
 return out
end
-- Écart (fraction de tour, de 0 à 1) jusqu'à la première valeur de la liste triée après progress, et cette valeur ;
-- nil si la liste est vide.
local function ahead(list,progress)
 local n=list and #list or 0
 if n==0 then return nil end
 local lo,hi=1,n+1
 while lo<hi do local mid=math.floor((lo+hi)/2); if list[mid]>progress then hi=mid else lo=mid+1 end end
 local v=list[lo] or list[1]
 return (v-progress)%1,v
end
M.ahead=ahead
-- Prochain point de freinage connu après progress (fraction de tour) ; nil sans point (lu par la tranche C).
function M.nextBrake(zones,progress)
 local _,v=ahead(zones and zones.brakes,progress)
 return v
end
-- Début de la prochaine zone d'attaque après progress (fraction de tour, de 0 à 1) ; nil sans zone d'attaque (lu par
-- la tranche C : la cession sous drapeau bleu attend la zone toute proche).
function M.nextAttack(zones,progress)
 local _,v=ahead(zones and zones.attackFrom,progress)
 return v
end
-- Écart (fraction de tour) jusqu'au prochain point de freinage connu ; nil sans point.
function M.brakeAhead(zones,progress) return (ahead(zones and zones.brakes,progress)) end
-- Écart (fraction de tour) jusqu'au début de la prochaine zone d'attaque ; nil sans zone.
function M.attackAhead(zones,progress) return (ahead(zones and zones.attackFrom,progress)) end
local kinds={nomove=true,caution=true,brake=true,attack=true,line=true}
local learnable={caution=true,brake=true,attack=true}
M.kinds=kinds
-- Une zone est-elle appliquée ? Zone apprise : K.zoneConfirmSessions sessions au moins ; jamais une zone refusée.
function M.confirmed(z) return not z.off and (z.source~='learnt' or (z.sessions or 0)>=K.zoneConfirmSessions) end
-- Champs calculés de la liste, après tout changement (chargement, marquage, apprentissage, bascule d'une zone).
function M.index(zones)
 -- Zones apprises : retirées du tableau, puis remises si elles sont confirmées.
 local w=0
 for i=1,#zones do local z=zones[i]; if z.source~='learnt' then w=w+1; zones[w]=z end end
 for i=#zones,w+1,-1 do zones[i]=nil end
 local learnt=zones.learnt; if not learnt then learnt={}; zones.learnt=learnt end
 local brakes=zones.brakes; if not brakes then brakes={}; zones.brakes=brakes end
 for i=#brakes,1,-1 do brakes[i]=nil end
 local attackFrom=zones.attackFrom; if not attackFrom then attackFrom={}; zones.attackFrom=attackFrom end
 for i=#attackFrom,1,-1 do attackFrom[i]=nil end
 for i=1,#learnt do
  local z=learnt[i]
  if M.confirmed(z) then
   if z.kind=='brake' then if #brakes<K.zoneBrakeMax then brakes[#brakes+1]=z.from end else zones[#zones+1]=z end
  end
 end
 local caution,attack,line,extra=0,0,0,false
 for i=1,#zones do
  local z=zones[i]
  if not z.off then
   if z.kind=='caution' then caution=caution+1; extra=true
   elseif z.kind=='attack' then attack=attack+1; extra=true; attackFrom[#attackFrom+1]=z.from
   elseif z.kind=='line' then line=line+1; extra=true
   elseif z.kind=='brake' and z.source~='learnt' then if #brakes<K.zoneBrakeMax then brakes[#brakes+1]=z.from end end
  end
 end
 table.sort(brakes); table.sort(attackFrom)
 zones.cautionN=caution; zones.attackN=attack; zones.lineN=line; zones.extra=extra
 return zones
end
-- Zone lue d'un fichier : jamais crue. Rend la zone validée, ou nil (zone ignorée).
local zoneKeys={
 nomove={kind=true,from=true,to=true,source=true,off=true,noYield=true,noOvertake=true,maxOffset=true,note=true},
 caution={kind=true,from=true,to=true,source=true,off=true,note=true,hits=true,sessions=true,last=true},
 brake={kind=true,from=true,source=true,off=true,note=true,hits=true,sessions=true,last=true},
 attack={kind=true,from=true,to=true,source=true,off=true,note=true,hits=true,sessions=true,last=true},
 line={kind=true,from=true,to=true,source=true,off=true,note=true,side=true,share=true,wet=true},
}
function M.validate(values,serial)
 if type(values)~='table' then return nil end
 local kind=values.kind
 if type(kind)~='string' or not kinds[kind] then return nil end
 local known=zoneKeys[kind]
 for key in pairs(values) do if not known[key] then return nil end end
 local source=values.source
 if source~='user' and source~='learnt' then return nil end
 if source=='learnt' and not learnable[kind] then return nil end
 local z={kind=kind,source=source,noYield=false,noOvertake=false,maxOffset=1,note=''}
 z.from=TrackFile.number(values.from,0,1); if not z.from then return nil end
 if kind=='brake' then z.to=z.from
 else z.to=TrackFile.number(values.to,0,1); if not z.to then return nil end end
 if values.off~=nil then local off=TrackFile.boolean(values.off); if off==nil then return nil end; z.off=off or nil end
 if values.note~=nil then z.note=TrackFile.text(values.note,K.zoneNote) or '' end
 if kind=='nomove' then
  if values.noYield~=nil then local b=TrackFile.boolean(values.noYield); if b==nil then return nil end; z.noYield=b end
  if values.noOvertake~=nil then local b=TrackFile.boolean(values.noOvertake); if b==nil then return nil end; z.noOvertake=b end
  if values.maxOffset~=nil then z.maxOffset=TrackFile.number(values.maxOffset,0,1); if not z.maxOffset then return nil end end
 elseif kind=='line' then
  z.side=TrackFile.number(values.side,-1,1); if not z.side then return nil end
  z.share=K.lineShareDefault
  if values.share~=nil then z.share=TrackFile.number(values.share,0,1); if not z.share then return nil end end
  if values.wet~=nil then local b=TrackFile.boolean(values.wet); if b==nil then return nil end; z.wet=b or nil end
 end
 if source=='learnt' then
  z.hits=TrackFile.integer(values.hits or '0',0,100000); z.sessions=TrackFile.integer(values.sessions or '0',0,100000); z.last=TrackFile.integer(values.last or '0',0,100000)
  if not z.hits or not z.sessions or not z.last or z.last>(serial or 0) then return nil end
 elseif values.hits~=nil or values.sessions~=nil or values.last~=nil then return nil end
 return z
end
-- Fichier des zones du circuit (Documents\Assetto Corsa\AdvancedIA\tracks\<clé>.ini) : {user=…, learnt=…, serial=…,
-- ignored=…, lengthOK=…}, ou nil et la raison (taille, format, circuit, syntaxe). Longueur du circuit changée :
-- zones apprises écartées, zones du pilote gardées (lengthOK faux, l'appelant le note).
function M.decode(text,track,layout,length)
 if type(text)~='string' or #text>K.maxZoneBytes then return nil,'taille' end
 local doc,why=TrackFile.parse(text,K.maxZoneBytes,K.maxZones+K.zoneLearntMax)
 if not doc then return nil,why=='big' and 'taille' or why=='format' and 'format' or 'syntaxe' end
 if doc.head.kind~='zones' then return nil,'format' end
 local ok,lengthOK=TrackFile.check(doc,'zones',track,layout,length)
 if not ok then return nil,'circuit' end
 local out={user={},learnt={},serial=TrackFile.serial(doc),ignored=doc.dropped,lengthOK=lengthOK}
 local brakes,attacks=0,0
 for _,section in ipairs(doc.sections) do
  local z=section.name:match('^zone%.%d+$') and M.validate(section.values,out.serial) or nil
  if z and z.kind=='brake' then brakes=brakes+1; if brakes>K.zoneBrakeMax then z=nil end end
  if z and z.kind=='attack' then attacks=attacks+1; if attacks>K.attackMax then z=nil end end
  if z and z.source=='learnt' then
   if not lengthOK or #out.learnt>=K.zoneLearntMax then z=nil else out.learnt[#out.learnt+1]=z end
  elseif z then
   if #out.user>=K.maxZones then z=nil else out.user[#out.user+1]=z end
  end
  if not z then out.ignored=out.ignored+1 end
 end
 return out
end
-- Liste appliquée : zones du fichier d'origine (toutes « sans manœuvre », source file), puis zones du pilote, puis
-- zones apprises (confirmées : appliquées ; les autres attendent dans learnt).
function M.merge(fileZones,decoded)
 local zones={}
 for i=1,#(fileZones or {}) do local z=fileZones[i]; z.kind='nomove'; z.source='file'; zones[#zones+1]=z end
 zones.learnt={}; zones.serial=0
 if decoded then
  for i=1,#decoded.user do zones[#zones+1]=decoded.user[i] end
  for i=1,#decoded.learnt do zones.learnt[#zones.learnt+1]=decoded.learnt[i] end
  zones.serial=decoded.serial or 0
 end
 return M.index(zones)
end
-- Texte du fichier des zones et nombre de zones écrites : zones du pilote, et zones apprises comptées au moins une
-- session ou refusées ; jamais une zone du fichier d'origine. meta : track, layout, length, serial.
function M.encode(zones,meta)
 local sections={}
 local function add(z)
  local s={name='zone.'..(#sections+1),kind=z.kind or 'nomove',from=z.from,source=z.source}
  if s.kind~='brake' then s.to=z.to end
  if z.off then s.off=true end
  if z.note and z.note~='' then s.note=z.note:sub(1,K.zoneNote) end
  if s.kind=='nomove' then s.noYield=z.noYield==true; s.noOvertake=z.noOvertake==true; s.maxOffset=z.maxOffset or 1
  elseif s.kind=='line' then s.side=z.side or 0; s.share=z.share or K.lineShareDefault; if z.wet then s.wet=true end end
  if z.source=='learnt' then s.hits=z.hits or 0; s.sessions=z.sessions or 0; s.last=z.last or 0 end
  sections[#sections+1]=s
 end
 for i=1,#zones do if zones[i].source=='user' then add(zones[i]) end end
 for i=1,#(zones.learnt or {}) do local z=zones.learnt[i]; if (z.sessions or 0)>0 or z.off then add(z) end end
 return TrackFile.build('AdvancedIA track zones ('..C.release..'). Edit with the game closed.',
  {kind='zones',track=meta.track,layout=meta.layout or '',length=meta.length,serial=meta.serial or 0},sections),#sections
end
function M.export(zones)
 local lines={'return { zones = {'}
 for i=1,math.min(#zones,K.maxZones) do
  local z=zones[i]
  if z.kind==nil or z.kind=='nomove' then lines[#lines+1]=string.format('  { from=%.6f, to=%.6f, noYield=%s, noOvertake=%s, maxOffset=%.3f, note="%s" },',z.from,z.to,tostring(z.noYield),tostring(z.noOvertake),z.maxOffset,(z.note or ''):gsub('["\\%c]','')) end
 end
 lines[#lines+1]='} }'; return table.concat(lines,'\n')
end
return M
