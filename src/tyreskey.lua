-- Beta 2.0.3 (accord avec la session de SpotterEngineer, décision du pilote du 16 novembre) : clé annexe en lecture
-- seule « AdvancedIA.tyres » pour SpotterEngineer (règle F1 des deux gommes sèches). Hors du pont (bridge_layout inchangé).
-- Même mécanisme que AdvancedIA.session (src/sessionkey.lua) : construite au plus toutes les TK.period s, écrite
-- seulement quand le texte change, et au moins toutes les TK.refresh s (horodatage vivant), tant que le pont est ouvert.
-- Format « v=1;rule=0|1;used=<court>,<court>|-;stamp=<s> », champs inconnus à ignorer par le lecteur :
--   rule  1 : en course, changement de composé sec obligatoire réglé (pitCompoundChange, arrêt obligatoire) et non levé
--         (course mouillée, course courte, distance de la 2.0.3) ; 0 sinon et hors course ;
--   used  composés secs roulés par le joueur pendant la course (src/pits.lua usedDry), noms courts de ac.getTyresName,
--         8 caractères au plus, « ; » « = » « , » remplacés par _, séparés par des virgules ; « - » si aucun ;
--   stamp temps du moteur (s) à l'écriture.
-- Lecture seule du moteur et de l'image : aucune commande, rien d'écrit ailleurs que cette clé.
local C=require('src/config')
local K=C.K
local M={}
local TK={period=0.5,refresh=5,bytes=160,nameChars=8}
M.K=TK
M.key='AdvancedIA.tyres'
local EMPTY={}

function M.new() return {at=-math.huge,writtenAt=-math.huge,body=nil} end

-- Nom court nettoyé pour la clé.
function M.clean(name)
 return (tostring(name or ''):sub(1,TK.nameChars):gsub('[;=,]','_'))
end

-- Relecture 2.0.4 (B8, signalé par la session de SpotterEngineer) : vraie session de course (type de session d'AC ou de
-- race.ini, comme le choix automatique du profil) ; un profil Course choisi à la main en essais ou en qualifications ne
-- publie jamais rule=1 ni de composés roulés (contrat v1 : 0 hors course).
local function raceSession(frame) return frame~=nil and C.autoProfile(frame)=='C' end
M.raceSession=raceSession
-- La règle des deux composés secs s'applique-t-elle au joueur dans cette course ?
function M.rule(e,frame)
 local p=e.run or EMPTY
 local pits=e.pits or EMPTY
 return e.profile=='C' and raceSession(frame) and p.pitCompoundChange==true and (p.mandatoryStops or 0)>0 and pits.waived~=true
end

-- Corps de la clé sans horodatage (comparé d'une écriture à l'autre).
function M.body(e,frame)
 local slot=frame.player or 0
 local rule=M.rule(e,frame)
 local names={}
 if e.profile=='C' and raceSession(frame) and slot>0 then
  local own=((e.pits or EMPTY).cars or EMPTY)[slot] or EMPTY
  local a=(frame.cars or EMPTY)[slot] or EMPTY
  local used=own.usedDry or EMPTY
  local tyreNames=a.tyreNames or EMPTY
  for index=0,K.maxTyreCompounds-1 do
   if used[index] then local n=M.clean(tyreNames[index] or tostring(index)); if n~='' then names[#names+1]=n end end
  end
 end
 local head='v=1;rule='..(rule and '1' or '0')..';used='
 -- Borne : la liste est coupée (noms entiers) pour que la clé complète tienne en TK.bytes octets.
 local room=TK.bytes-#head-#';stamp=' - 12
 local list=''
 for _,n in ipairs(names) do
  local cand=list=='' and n or list..','..n
  if #cand>room then break end
  list=cand
 end
 return head..(list=='' and '-' or list)
end

function M.text(body,now) return body..';stamp='..string.format('%.1f',now) end

-- Appelé à chaque image pont ouvert : texte à écrire (changé, ou horodatage à rafraîchir) ou nil.
function M.step(s,e,frame,now)
 if now<s.at+TK.period and now>=s.at then return nil end
 s.at=now
 local body=M.body(e,frame)
 if body==s.body and now<s.writtenAt+TK.refresh and now>=s.writtenAt then return nil end
 s.body=body; s.writtenAt=now
 return M.text(body,now)
end

-- Texte écrit à la fermeture du pont : règle coupée.
function M.closedText(now) return M.text('v=1;rule=0;used=-',now or 0) end
return M
