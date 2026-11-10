-- Options de CSP tenues par l'app (Beta 1.40, demande du pilote : « toutes les fonctions de base d'Assetto Corsa que
-- nous reprenons, il faut les désactiver »). Tant que l'app est active, le bandeau des messages système d'AC (CUT
-- DETECTED, aides…) et les drapeaux d'origine d'AC (coin haut gauche) sont masqués par les options de CSP de
-- cfg/extension/gui.ini, section [HIDE] ; l'overlay les reprend. ac.blockSystemMessages seul ne suffit pas : le bandeau
-- « CUT DETECTED » restait affiché (journal du pilote, Beta 1.39).
-- Règles :
--  * une option déjà masquée par le pilote n'est jamais touchée (ni écrite, ni rétablie) ;
--  * le fichier d'origine (texte entier, ou absent) et la valeur d'origine de chaque option sont gardés dans le fichier
--    d'état (cfg/extension/state, que CSP ne relit pas) AVANT d'écrire gui.ini : ils survivent à un plantage ;
--  * Beta 1.47 (demande du pilote : cases cochées dans Content Manager tant que l'app est installée et active) : options
--    cochées tant que l'app est active et que l'overlay reprend l'affichage (M.want), et LAISSÉES cochées à la
--    fermeture du jeu, au déchargement de l'app, pendant la panique et après un plantage ; valeurs d'origine rendues
--    seulement quand l'app est coupée (bouton APP), l'interrupteur de l'option coupé, ou l'affichage repris par l'overlay
--    coupé (panneau de drapeaux de l'app, messages repris et masqués), ou par le témoin des messages (messages perdus) ;
--    retour à une version d'avant la Beta 1.40 : rendues aussi (elle ne les rendrait jamais) ; tout rendu, fichier
--    inchangé depuis l'écriture de l'app : fichier d'origine à l'octet près ;
--  * une valeur changée par le pilote pendant que l'app la tenait est laissée telle quelle ;
--  * aucune écriture quand gui.ini porte déjà la valeur voulue (l'app relancée ne réécrit rien), au plus
--    K.cspWritesMax écritures par partie (jamais de boucle d'écritures).
-- État appliqué par CSP : option lue par CSP au premier lancement de l'app dans la partie (mémoire de la partie,
-- ac.store), relue à chaque relecture de gui.ini par CSP ; entre une écriture de l'app et cette relecture, la valeur
-- d'avant reste la bonne (jamais le rouge des panneaux, drapeau noir d'AC, avant que CSP ait masqué ses drapeaux).
-- Texte pur : fichiers, mémoire de la partie et lecture des options de CSP passent par le port (src/applier.lua en jeu,
-- imitation dans les tests).
local Flood=require('src/flood')
local K=require('src/config').K
local M={}
M.section='HIDE'
M.keys={'HIDE_SYSTEM_MESSAGES','HIDE_RACE_FLAGS'}
M.names={HIDE_SYSTEM_MESSAGES='messages systeme',HIDE_RACE_FLAGS='drapeaux'}
local known={HIDE_SYSTEM_MESSAGES=true,HIDE_RACE_FLAGS=true}
local function hidden(value) return Flood.truthy(value)==true end
local function list(keys)
 local out={}
 for i,key in ipairs(keys) do out[i]=M.names[key] end
 return table.concat(out,', ')
end
local function heldKeys(owned)
 local out={}
 for _,key in ipairs(M.keys) do if owned[key]~=nil then out[#out+1]=key end end
 return out
end
-- Fichier d'état : « v1 », une ligne par option tenue (CLÉ=valeur d'origine, ou CLÉ seule si elle était absente),
-- puis le fichier d'origine et le dernier fichier écrit par l'app (« nom longueur », contenu ; « nom - » : absent).
-- Texte vide quand l'app ne tient plus rien.
local function block(name,text) if text==false or text==nil then return name..' -' end return name..' '..#text..'\n'..text end
function M.serialize(owned,original,written)
 local out={'v1'}
 for _,key in ipairs(M.keys) do
  local o=owned[key]
  if o==false then out[#out+1]=key elseif o~=nil then out[#out+1]=key..'='..o end
 end
 if #out==1 then return '' end
 out[#out+1]=block('original',original); out[#out+1]=block('written',written)
 return table.concat(out,'\n')..'\n'
end
-- Lecture du fichier d'état : options tenues, fichier d'origine, dernier fichier écrit ; nil si illisible.
function M.parse(text)
 if type(text)~='string' or text:sub(1,3)~='v1\n' then return nil end
 local at=text:find('\noriginal ',1,true)
 if not at then return nil end
 local owned={}
 for line in text:sub(4,at):gmatch('([^\n]*)\n') do
  local key,value=line:match('^([%u_]+)=(.*)$')
  if key and known[key] then owned[key]=value elseif known[line] then owned[line]=false else return nil end
 end
 local function read(pos,name)
  local head=name..' '
  if text:sub(pos,pos+#head-1)~=head then return nil end
  local n,after=text:match('^([%-%d]+)()',pos+#head)
  if n=='-' and text:sub(after,after)=='\n' then return false,after+1 end
  local len=tonumber(n)
  if not len or text:sub(after,after)~='\n' then return nil end
  local value=text:sub(after+1,after+len)
  if #value~=len or text:sub(after+len+1,after+len+1)~='\n' then return nil end
  return value,after+len+2
 end
 local original,pos=read(at+1,'original')
 if original==nil then return nil end
 local written=read(pos,'written')
 if written==nil or not next(owned) then return nil end
 return owned,original,written
end
function M.new()
 return {owned={},original=nil,written=nil,applied={},want={},started=false,frozen=false,writes=0,live=false,
  writable=true,ready=false,capped=false,waitUntil=nil,reloadedAt=nil,events={}}
end
local function note(c,level,text) c.events[#c.events+1]={level,'options CSP: '..text} end
-- Événements du journal, versés par le script principal.
function M.take(c,out) for i=1,#c.events do out[#out+1]=c.events[i]; c.events[i]=nil end; return out end
local function session(c)
 return string.format('v1|%d|%d|%d|%d',c.writes,c.frozen and 1 or 0,c.applied.HIDE_SYSTEM_MESSAGES==true and 1 or 0,c.applied.HIDE_RACE_FLAGS==true and 1 or 0)
end
-- Lancement de l'app : mémoire de la partie (écritures, état appliqué figé), puis options tenues par un lancement
-- précédent (plantage, ou options gardées jusqu'au lancement du jeu).
function M.start(c,port)
 c.ready=port.ready==true
 if not c.ready then c.writable=false; return end
 local writes,frozen,sys,flags
 local mem=port.loadSession()
 if type(mem)=='string' then writes,frozen,sys,flags=mem:match('^v1|(%d+)|([01])|([01])|([01])$') end
 c.writes=tonumber(writes) or 0; c.frozen=frozen=='1'
 if c.frozen then c.applied.HIDE_SYSTEM_MESSAGES=sys=='1'; c.applied.HIDE_RACE_FLAGS=flags=='1'
 else for _,key in ipairs(M.keys) do c.applied[key]=port.loaded(key) end end
 local state=port.loadState()
 if state=='' then return end
 local owned,original,written=M.parse(state)
 if not owned then c.writable=false; note(c,'WARN','fichier d etat illisible (cfg/extension/state), gui.ini laisse tel quel'); return end
 c.owned,c.original,c.written=owned,original,written
 note(c,'INFO','valeurs d origine reprises du lancement precedent ('..list(heldKeys(owned))..')')
end
-- CSP a relu gui.ini (ac.onCSPConfigChanged) : état appliqué relu ; une écriture de l'app en attente est prise en compte
-- en cours de partie (au déchargement, les valeurs d'origine pourront être rendues).
function M.reloaded(c,port,now)
 if not c.ready then return end
 for _,key in ipairs(M.keys) do c.applied[key]=port.loaded(key) end
 c.frozen=false; c.reloadedAt=now; port.saveSession(session(c))
 if c.waitUntil then c.waitUntil=nil; c.live=true; note(c,'INFO','gui.ini relu par CSP en cours de partie') end
end
-- Valeur appliquée par CSP tant qu'une écriture de l'app n'est pas relue (nil : l'option de CSP se lit normalement).
function M.frozen(c,key) if c.frozen then return c.applied[key]==true end return nil end
function M.applied(c,key) return c.applied[key]==true end
-- Option masquée par l'app dans gui.ini, pas encore appliquée par CSP.
function M.pending(c,key) return c.owned[key]~=nil and c.want[key]==true and c.applied[key]~=true end
-- État affiché : off (sans accès aux fichiers), readonly, capped, waiting (écrites, relecture de CSP attendue),
-- pending (effet au prochain lancement du jeu), applied (options tenues appliquées), idle (rien de tenu).
function M.view(c)
 if not c.ready then return 'off' end
 if not c.writable then return c.capped and 'capped' or 'readonly' end
 local held=false
 for _,key in ipairs(M.keys) do
  if c.owned[key]~=nil then held=true; if M.pending(c,key) then return c.waitUntil and 'waiting' or 'pending' end end
 end
 return held and 'applied' or 'idle'
end
local function stop(c,text) c.writable=false; note(c,'WARN',text) end
-- Beta 1.47 : ce que l'app veut masquer maintenant, rempli dans out (g : réglages globaux, profile : réglages du profil
-- en cours tels que réglés par le pilote, panic : panique). Messages système : app active, messages d'AC repris et
-- masqués par l'overlay, interrupteur coché, messages arrivés à l'overlay (témoin) ; drapeaux d'AC : app active,
-- interrupteur coché, panneau de drapeaux de l'app laissé coché dans le profil en cours. Le réglage du pilote, pas sa
-- valeur effective : onglets décochés (journée circuit par défaut), l'overlay montre les drapeaux d'AC à leur place
-- (src/panel.lua), ceux d'AC restent masqués. nil : rien ne change (panique passagère, profil pas encore lu).
function M.want(g,profile,panic,out)
 if panic or type(g)~='table' or type(profile)~='table' then return nil end
 -- Beta 1.59 : overlay coupé (overlayEnabled) : options rendues, AC dessine ses drapeaux et ses messages.
 local on=g.enabled==true and g.overlayEnabled~=false
 out.HIDE_SYSTEM_MESSAGES=on and g.overlayMessages==true and g.overlayBlockMessages==true and g.cspHideMessages==true and not g.cspMessagesLost
 out.HIDE_RACE_FLAGS=on and g.cspHideFlags==true and profile.flagPanel~=false
 return out
end
-- want : {HIDE_SYSTEM_MESSAGES=bool, HIDE_RACE_FLAGS=bool}, ce que l'app veut masquer maintenant (M.want) ; nil : rien
-- ne change. Agit au premier appel et à chaque changement de want ; sinon dit seulement, une fois, qu'une écriture n'a
-- pas été relue par CSP.
function M.step(c,port,want,now)
 if not c.writable then return end
 if want==nil then if not c.started then return end; want=c.want end
 local same=c.started
 for _,key in ipairs(M.keys) do if c.want[key]~=(want[key]==true) then same=false end end
 if same then
  if c.waitUntil and now>=c.waitUntil then c.waitUntil=nil; note(c,'INFO','gui.ini pas relu par CSP en cours de partie: effet au prochain lancement du jeu') end
  return
 end
 c.started=true
 for _,key in ipairs(M.keys) do c.want[key]=want[key]==true end
 local text,exists=port.read()
 if text==nil then stop(c,'cfg/extension/gui.ini illisible, options inchangees'); return end
 local values,owned,union,added,restored={},{},{},{},{}
 for _,key in ipairs(M.keys) do owned[key]=c.owned[key]; union[key]=c.owned[key] end
 for _,key in ipairs(M.keys) do
  local current=Flood.get(text,M.section,key)
  local origin=owned[key]
  if want[key] then
   -- Option masquée par le pilote : dans gui.ini, ou appliquée par CSP sans y être (état appliqué à jour : aucune
   -- écriture de l'app en attente de relecture) ; jamais touchée.
   if not hidden(current) and not (origin==nil and c.applied[key]==true and not c.frozen) then
    if origin==nil then owned[key]=current or false; union[key]=owned[key] end
    values[key]='1'; added[#added+1]=key
   end
  elseif origin~=nil then
   owned[key]=nil
   if current=='1' then values[key]=origin; restored[#restored+1]=key
   elseif current~=(origin or nil) then note(c,'INFO',M.names[key]..' modifie par vous pendant que l app le tenait, laisse tel quel') end
  end
 end
 local held=next(owned)~=nil
 local original=c.original
 if original==nil then original=exists and text or false end
 if #added==0 and #restored==0 then
  -- Option laissée au pilote (changée par lui) : elle n'est plus tenue.
  local dropped=false
  for _,key in ipairs(M.keys) do if owned[key]~=c.owned[key] then dropped=true end end
  if dropped then
   c.owned=owned
   if not held then c.original,c.written=nil,nil end
   port.saveState(M.serialize(c.owned,c.original,c.written))
  end
  return
 end
 if c.writes>=K.cspWritesMax then
  c.capped=true; stop(c,string.format('%d ecritures de gui.ini dans cette partie, options laissees telles quelles jusqu au prochain lancement',c.writes)); return
 end
 -- Tout rendu, fichier inchangé depuis la dernière écriture de l'app : fichier d'origine tel quel (ou effacé s'il
 -- n'existait pas). Sinon, seules les options concernées changent.
 local out
 if not held and c.written~=nil and text==c.written then out=original
 else out=Flood.edit(text,M.section,values,M.keys) end
 -- Valeurs d'origine gardées avant d'écrire gui.ini (options tenues avant et après) : un plantage entre les deux ne
 -- perd rien.
 local before=c.owned
 if not port.saveState(M.serialize(union,original,out)) then stop(c,'fichier d etat non modifiable (cfg/extension/state), gui.ini laisse tel quel'); return end
 local ok
 if out==false then ok=port.remove() else ok=port.write(out) end
 if not ok then
  port.saveState(M.serialize(before,c.original,c.written))
  stop(c,'ecriture de cfg/extension/gui.ini impossible, options inchangees'); return
 end
 c.owned=owned
 if held then c.original,c.written=original,out else c.original,c.written=nil,nil end
 port.saveState(M.serialize(c.owned,c.original,c.written))
 c.writes=c.writes+1; c.frozen=true; c.waitUntil=now+K.cspLiveWait; port.saveSession(session(c))
 if #added>0 then note(c,'INFO',list(added)..' masques (valeurs d origine gardees)') end
 if #restored>0 then note(c,'INFO','valeurs d origine rendues ('..list(restored)..')'..(held and '' or out==original and ', fichier d origine' or '')) end
end
local NONE={}
-- Déchargement de l'app (fermeture du jeu, relance de l'app) : Beta 1.47, options laissées cochées, valeurs d'origine
-- gardées dans le fichier d'état pour être rendues plus tard. force : retour à une version d'avant la Beta 1.40, qui
-- ne les rendrait jamais : rendues.
function M.release(c,port,now,force)
 if not c.writable or not next(c.owned) then return end
 if not force then note(c,'INFO','options laissees cochees ('..list(heldKeys(c.owned))..'), valeurs d origine gardees'); return end
 M.step(c,port,NONE,now)
end
return M
