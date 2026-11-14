-- Beta 1.63 (accord avec la session de SetupLab, décision du pilote du 12 novembre) : clé annexe en lecture seule
-- « AdvancedIA.session » pour SetupLab (réglages du joueur). Hors de la structure v1 du pont (SpotterEnginer inchangé).
-- Écrite au plus toutes les SK.period s, seulement quand le texte change, tant que le pont est ouvert (hello v1 vivant).
-- Format « k=v;k=v… », champs inconnus à ignorer par le lecteur, `v=1` en tête :
--   session  profil de l'app (P essais, Q qualifications, C course, J journée circuit, H hotlap ; voir README) ;
--   rules    jeu de règles (nom écrit au journal « regles: … ») ;
--   playerLapId    car.lapCount du joueur pendant le tour en cours (tours bouclés avant ce tour) ;
--   playerLapClean faux dès qu'un événement touche le tour en cours, remis à vrai à la ligne ;
--   reason   dernier événement qui a sali le tour : red, sc, vsc, fcy, formation, blackflag, slowdown, delta, yellow ;
--   lastLapId / lastLapClean  le tour que le joueur vient de boucler (son playerLapId), gardé jusqu'à la ligne suivante ;
--   drsAllowed     faux quand les règles de l'app coupent le DRS du joueur ;
--   compoundChange vrai seulement en course, changement de gomme obligatoire encore dû (ni fait ni levé) ;
--   compoundsAllowed indices de composés de CSP permis par une règle de la séance, séparés par des virgules ; vide :
--                  aucune restriction (aucun jeu de règles de l'app n'en impose aujourd'hui) ;
--   wetWaived      obligation levée (arrêt obligatoire ou changement de composé) : pluie ou course trop courte (la levée sprint
--                  de la 1.64 est coupée : décision du pilote du 14 novembre 2026) ;
--   costMs         coût moyen de l'app par image (ms) ;
--   aiLapMean / aiLapCount  temps moyen (s) des tours propres des IA de la séance (ni tour de sortie ni de rentrée, ni
--                  neutralisation ni drapeau rouge, ni incident, ni premier tour d'une course) et leur nombre.
-- Lecture seule du moteur et de l'image : aucune commande, rien d'écrit ailleurs que cette clé.
local C=require('src/config')
local K=C.K
local M={}
local SK={period=0.5,lapMin=10,lapMax=3600}
M.K=SK
M.key='AdvancedIA.session'
local EMPTY={}

function M.new() return {at=-math.huge,written=nil,logged=false,session=nil,lapId=nil,clean=true,reason='',
 lastId=-1,lastClean=true,cars={},sum=0,count=0} end

local neutralNames={sc=true,vsc=true,fcy=true}
-- Événement qui salit le tour du joueur à cette image, ou nil.
local function dirt(e,frame)
 local t=e.incidents or EMPTY
 if t.red then return 'red' end
 if t.formation then return 'formation' end
 if t.neutral then local m=t.neutralMode; if m=='local' then return 'yellow' end; return neutralNames[m] and m or 'fcy' end
 local slot=frame.player or 0
 local player=slot>0 and (frame.cars or EMPTY)[slot] or EMPTY
 local pen=player.penaltyType or 0
 if (e.penalties or EMPTY).disqualified==true or pen==K.penaltyBlackFlag then return 'blackflag' end
 if pen>0 then return 'slowdown' end
 local d=(e.delta or EMPTY).value
 if type(d)=='number' and d==d and d~=math.huge and d~=-math.huge then return 'delta' end
 if t.playerYellow or t.playerInside then return 'yellow' end
 return nil
end
M.dirt=dirt

local function reset(s,session)
 s.session=session; s.lapId=nil; s.clean=true; s.reason=''; s.lastId=-1; s.lastClean=true
 for k in pairs(s.cars) do s.cars[k]=nil end
 s.sum=0; s.count=0
end

-- À chaque image (joueur seulement, quelques lectures) : tour en cours et tour bouclé.
function M.player(s,e,frame)
 if s.session~=frame.session then reset(s,frame.session) end
 local slot=frame.player or 0
 local a=slot>0 and (frame.cars or EMPTY)[slot] or nil
 if not a or not a.lapValid then return end
 if s.lapId==nil then s.lapId=a.lap end
 if a.lap~=s.lapId then
  s.lastId=s.lapId; s.lastClean=s.clean; s.lapId=a.lap; s.clean=true
 end
 local r=dirt(e,frame)
 if r then s.clean=false; s.reason=r end
end

-- Toutes les SK.period s : tours des IA (sale si stands, neutralisation, rouge ou incident pendant le tour).
local function ai(s,e,frame)
 local t=e.incidents or EMPTY
 local ic=t.cars or EMPTY
 local whole=t.red or t.neutral or t.formation
 local race=e.profile=='C'
 local cars=frame.cars or EMPTY
 for i=1,frame.count or 0 do
  local a=cars[i]
  if a and a.valid and a.control and a.lapValid and not a.safetyCar then
   local c=s.cars[i]
   if not c or c.lap==nil then c=c or {}; s.cars[i]=c; c.lap=a.lap; c.dirty=true
   elseif a.lap~=c.lap then
    local first=race and c.lap==0
    local time=a.lastLap or 0
    if a.lap==c.lap+1 and not c.dirty and not first and time>=SK.lapMin and time<=SK.lapMax then s.sum=s.sum+time; s.count=s.count+1 end
    c.lap=a.lap; c.dirty=false
   end
   if a.pit or whole or (ic[i] and ic[i].incident) then c.dirty=true end
  end
 end
end
M.ai=ai

local function flag(x) return x and '1' or '0' end
local function num(x,fmt) if type(x)=='number' and x==x and x~=math.huge and x~=-math.huge then return string.format(fmt,x) end return '0' end

function M.text(s,e,frame)
 local slot=frame.player or 0
 local cmd=slot>0 and (e.commands or EMPTY)[slot] or EMPTY
 local pits=e.pits or EMPTY
 local p=e.run or EMPTY
 local own=slot>0 and (pits.cars or EMPTY)[slot] or EMPTY
 local change=e.profile=='C' and p.pitCompoundChange==true and (p.mandatoryStops or 0)>0 and not pits.waived
  and (own.windowStops or 0)<(p.mandatoryStops or 0) and pits.state~='closed'
 return string.format('v=1;session=%s;rules=%s;playerLapId=%d;playerLapClean=%s;reason=%s;lastLapId=%d;lastLapClean=%s;drsAllowed=%s;compoundChange=%s;compoundsAllowed=;wetWaived=%s;costMs=%s;aiLapMean=%s;aiLapCount=%d',
  tostring(e.profile or ''),(tostring(e.rulesLogged or ''):gsub('[;=]',' ')),s.lapId or -1,flag(s.clean),s.reason,s.lastId,flag(s.lastClean),
  flag(cmd.drsBlock~=true),flag(change),flag(pits.waived==true),num(e.meanFrame,'%.3f'),
  s.count>0 and string.format('%.3f',s.sum/s.count) or '0',s.count)
end

-- Appelé à chaque image pont ouvert : renvoie le texte à écrire (changé et dû) ou nil.
function M.step(s,e,frame,now)
 M.player(s,e,frame)
 if now<s.at+SK.period and now>=s.at then return nil end
 s.at=now
 ai(s,e,frame)
 local text=M.text(s,e,frame)
 if text==s.written then return nil end
 s.written=text
 return text
end

M.closedText='v=1;closed=1'
return M
