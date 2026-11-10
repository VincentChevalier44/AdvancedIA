-- Beta 1.59 (décision du pilote, réglage strategyStartVariety, course seulement, coupé par défaut) : stratégies de
-- départ variées. Avant le départ, à l'arrêt sur la grille et sur piste sèche, une part des IA part sur une gomme
-- sèche plus tendre ou plus dure que celle montée : la fin de grille plutôt plus dure (arrêt plus tard), la tête
-- plutôt plus tendre. Un cran au plus. Leurs arrêts suivent leur propre usure (src/strategy.lua) ; carburant, arrêt
-- obligatoire et règle F1 des deux gommes sèches inchangés (src/pits.lua). Décision pure, une fois par voiture et par
-- session (état gardé dans l'état météo, remis à zéro à chaque session) ; l'écriture reste dans l'applicateur.
local K=require('src/config').K
local U=require('src/util')
local M={}
-- Rang de dureté d'une gomme d'après ses noms (le SDK n'en donne aucun) : nom long d'abord, puis nom court ; nil si
-- inconnu. Plus le rang est bas, plus la gomme est tendre.
function M.hardness(a,index)
 local long=a.tyreLongNames and a.tyreLongNames[index]
 if type(long)=='string' then
  local text=long:lower():gsub('[%s%-_]','')
  for _,entry in ipairs(K.compoundHardnessLong) do if text:find(entry[1],1,true) then return entry[2] end end
 end
 local short=a.tyreNames and a.tyreNames[index]
 if type(short)=='string' then
  local key=short:upper()
  if K.compoundHardnessShort[key] then return K.compoundHardnessShort[key] end
  -- Gommes Pirelli C1 (la plus dure) à C6 (la plus tendre).
  local n=tonumber(key:match('^C(%d)$'))
  if n then return K.compoundPirelliBase-n end
 end
 return nil
end
-- Rangs des gommes sèches principales d'un modèle (une par nom court), ou nil : moins de deux gommes, une gomme
-- inconnue ou deux gommes de même rang (ordre douteux).
function M.ranks(a)
 local list=a.dryPrimary
 if not a.tyresKnown or not list or #list<2 then return nil end
 local ranks,seen={},{}
 for _,index in ipairs(list) do
  local r=M.hardness(a,index)
  if r==nil or seen[r] then return nil end
  ranks[index]=r; seen[r]=true
 end
 return ranks
end
-- Choix d'une IA : gomme visée (-1 : aucun changement), sens et place sur la grille. Déterministe (graine, voiture et
-- place), un cran au plus, jamais quand la météo veut une autre gomme.
local function choose(w,a,cmd,seed,count,log,now)
 if cmd.weatherManaged and (cmd.weatherCompound or -1)>=0 and cmd.weatherCompound~=a.compoundIndex then return -1 end
 local model=a.id or ''
 local ranks=w.startRank[model]
 if ranks==nil then
  ranks=M.ranks(a) or false; w.startRank[model]=ranks
  if not ranks and log then U.log(log,now,'INFO',string.format('strategie de depart: gommes de %s non classees, aucun changement',model),-1) end
 end
 if not ranks then return -1 end
 local current=a.compoundIndex
 if current==nil or ranks[current]==nil then return -1 end
 local place=(a.position or 0)>0 and a.position or 0
 local key=(a.index or 0)*K.startVarietyPlaces+place
 if U.unit(seed or 0,key,K.startVarietySalt)>=K.startVarietyShare then return -1 end
 local grid=place>0 and count>1 and (place-1)/(count-1) or 0.5
 local harder=U.unit(seed or 0,key,K.startVarietySalt+1)<0.5+K.startVarietyBias*(grid-0.5)*2
 local best,bestRank=-1,nil
 for _,index in ipairs(a.dryPrimary) do
  local r=ranks[index]
  if harder and r>ranks[current] or not harder and r<ranks[current] then
   if bestRank==nil or harder and r<bestRank or not harder and r>bestRank then best,bestRank=index,r end
  end
 end
 return best,harder and 'plus dure' or 'plus tendre',place
end
-- À chaque image : cmd.startCompound (gomme à poser, -1 sinon), cmd.startDir, cmd.startPlace. Rien hors course, sous la
-- pluie, après le départ ou réglage coupé (aucune commande touchée tant que rien n'a été posé).
function M.step(w,frame,commands,p,seed,race,log,now)
 local on=race and p.section_strategy and p.strategyStartVariety and not w.wet and (not frame.started or (frame.startIn or 0)>0)
 if not on then
  if w.startSet then for i=1,frame.count do commands[i].startCompound=-1 end; w.startSet=false end
  return
 end
 w.start=w.start or {}; w.startRank=w.startRank or {}; w.startSet=true
 local count=0
 for i=1,frame.count do local a=frame.cars[i]; if a.valid and not a.safetyCar then count=count+1 end end
 for i=1,frame.count do
  local a=frame.cars[i]; local cmd=commands[i]
  cmd.startCompound=-1
  -- Gommes pas encore lues (lecture étalée sur les premières images, ou données chiffrées) : décision remise à plus tard ;
  -- une voiture dont les gommes restent illisibles ne change jamais.
  if a.valid and a.control and not a.player and not a.safetyCar and not a.finished and not a.pit and (a.kmh or 0)<=K.tyreStopSpeed and a.tyresKnown then
   local id=a.identity or a.id
   local d=w.start[i]
   if not d or d.id~=id then
    d={id=id}; d.target,d.dir,d.place=choose(w,a,cmd,seed,count,log,now); w.start[i]=d
   end
   if d.target>=0 then cmd.startCompound=d.target; cmd.startDir=d.dir; cmd.startPlace=d.place end
  end
 end
end
return M
