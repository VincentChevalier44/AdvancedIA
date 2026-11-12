-- Beta 1.59 (décision du pilote, 10 novembre) : vrais passages en piste des IA, en essais et en qualifications
-- (réglage qualiRuns, coupé par défaut). Décisions pures : demande d'arrêt (cmd.rulePit), pneus (cmd.pitCompound),
-- carburant à l'emplacement (cmd.runFuelSet) et attente à l'emplacement (cmd.pitHold), écrits par applier.
--   Qualifications : « on sort, on fait chauffer les pneus, on fait notre tour rapide, on re-rentre et on recommence » :
--     tour de sortie, un tour lancé (un second, rarement, quand le premier a été gâché), tour de rentrée, attente à
--     l'emplacement ; composé sec le plus tendre et peu de carburant ; aucun passage qui ne tiendrait plus avant le drapeau.
--   Essais : « on peut tout essayer » : pour chaque IA et chaque passage, un programme tiré au sort (simulation de
--     qualification, long relais, essai de pneus, essai de carburant, essai de réglages : rythme sorties-arrêts seulement,
--     aucune allure inventée) ; chaque passage finit aux stands, aucun ne déborde la fin de la session.
-- Un seul service par passage dans la voie des stands (règle de la 1.58, src/pits.lua : visit, laneVisit).
-- Aussi : course, entrée aux stands d'une IA sans demande de l'app (journal détaillé seulement).
local U=require('src/util')
local K=require('src/config').K
-- Relecture 1.59 : rangs des gommes partagés avec les stratégies de départ (C1 à C6, extra tendre…).
local StartVar=require('src/startvar')
local max,min,floor=math.max,math.min,math.floor
local M={}
local programs={'quali','long','tyre','fuel','setup'}
local programNames={quali='simulation de qualification',long='long relais',tyre='essai de pneus',fuel='essai de carburant',setup='essai de reglages',flying='tour rapide'}
local function car() return {phase='',program='',planned=0,lapStart=-1,exitAt=-math.huge,waitUntil=-math.huge,visit=-1,run=0,spoiled=false,second=false,
 stay=false,stayLogged=false,compound=-1,fuel=-1,wasBox=false,wasPit=false,identity='',lanePlanned=false,called=false} end
function M.new()
 local t={cars={},session=-1,last=-math.huge,unranked={}}
 for i=1,K.maxCars do t.cars[i]=car() end
 return t
end
function M.reset(t)
 for i=1,K.maxCars do t.cars[i]=car() end
 t.unranked={}
end
-- Tendreté d'un composé sec d'après ses noms (CSP ne la donne pas) : 0 le plus tendre ; nil inconnue.
function M.rank(a,index)
 -- Relecture 1.59 : même classement que les stratégies de départ (src/startvar.lua), Pirelli C1 à C6 compris.
 local short=a.tyreNames and a.tyreNames[index]
 if type(short)=='string' and short:upper()=='HYS' then return 0 end
 return StartVar.hardness(a,index)
end
-- Composé sec le plus tendre ; autre composé sec classé (essai de pneus, tiré au sort) ; -1 sans classement.
local function softest(a)
 if not (a.tyresKnown and a.dryCompounds) then return -1 end
 local best,bestRank=-1,math.huge
 for index=0,K.maxTyreCompounds-1 do
  if a.dryCompounds[index] then local r=M.rank(a,index); if r and r<bestRank then best,bestRank=index,r end end
 end
 return best
end
local function other(a,u)
 if not (a.tyresKnown and a.dryCompounds) then return -1 end
 local list={}
 for index=0,K.maxTyreCompounds-1 do if a.dryCompounds[index] and index~=a.compoundIndex and M.rank(a,index) then list[#list+1]=index end end
 if #list==0 then return -1 end
 return list[min(#list,1+floor(u*#list))]
end
local function draw(u)
 local total=0
 for _,name in ipairs(programs) do total=total+K.runsWeights[name] end
 local x=u*total
 for _,name in ipairs(programs) do x=x-K.runsWeights[name]; if x<0 then return name end end
 return programs[#programs]
end
local function between(lo,hi,u) return lo+floor(u*(hi-lo+1)) end
-- Durée estimée d'un tour (meilleur ou dernier tour, au moins K.qualiCoolLapMin s).
local function lapTime(a) return max(K.qualiCoolLapMin,a.lastLap or 0,a.bestLap or 0) end
local function name(a) return a and a.name or '?' end
-- Prochain passage d'une IA à son emplacement : programme, tours lancés prévus, pneus, carburant, attente. Renvoie faux
-- si plus aucun passage ne tient avant la fin de la session (l'IA reste à son stand).
local function plan(t,e,frame,a,i,c,profile,now,first)
 local seed=e.runtimeG.seed or 0
 c.run=c.run+1
 local u1,u2,u3,u4=U.unit(seed,i,K.runsSalt+c.run),U.unit(seed,i,K.runsSalt+97+c.run),U.unit(seed,i,K.runsSalt+193+c.run),U.unit(seed,i,K.runsSalt+389+c.run)
 local program=profile=='Q' and 'flying' or draw(u1)
 local laps=program=='flying' and 1 or program=='quali' and 1 or program=='long' and between(K.runsLongMin,K.runsLongMax,u2)
  or program=='tyre' and between(K.runsTyreMin,K.runsTyreMax,u2) or program=='fuel' and between(K.runsFuelMin,K.runsFuelMax,u2) or between(K.runsSetupMin,K.runsSetupMax,u2)
 local lap=lapTime(a)
 -- Temps restant : le tour de sortie et les tours prévus doivent tenir avant le drapeau (qualifications : le dernier
 -- essai compte) ; en essais, le programme est raccourci, au moins un tour, sinon l'IA reste à son stand.
 if frame.left and frame.left>0 then
  local fit=floor(frame.left/(lap*K.runsTimeMargin))-1
  if fit<1 then return false end
  if laps>fit then if profile=='Q' then return false end; laps=fit end
 end
 c.program=program; c.planned=laps; c.spoiled=false; c.second=false; c.redone=0
 -- Pneus : le plus tendre (qualification, simulation, carburant, réglages), un autre composé classé (essai de pneus),
 -- celui monté (long relais) ; sans classement des gommes, celui monté (une ligne par modèle).
 local compound=-1
 if program=='tyre' then compound=other(a,u3) elseif program~='long' then compound=softest(a) end
 if compound<0 and program~='long' and a.tyresKnown and a.dryCompounds and not t.unranked[a.id or ''] then
  t.unranked[a.id or '']=true
  if e.note then e.note('INFO',string.format('passages en piste: gommes non classees pour le modele %s, pneu laisse tel quel',a.id or '?'),i) end
 end
 c.compound=compound
 -- Carburant (consommation connue seulement) : juste assez pour le passage (sortie, tours prévus, rentrée, réserve) ;
 -- essai de carburant : lourd ou léger, tiré au sort ; long relais : celui d'une course.
 -- Relecture 1.59 : consommation apprise d'abord (src/pits.lua), jamais moins que celle annoncée par CSP.
 local pc=e.pits and e.pits.cars[i]
 local perLap=max(pc and pc.perLap or 0,a.fuelPerLap or 0)
 c.fuel=-1
 if perLap>0 and (a.maxFuel or 0)>0 then
  local need=(laps+2+K.runsFuelReserveLaps)*perLap
  if program=='fuel' and u4<0.5 then need=need+K.runsHeavyLaps*perLap end
  if program=='long' then need=need*K.runsLongFuelMargin end
  c.fuel=U.clamp(need,perLap*(2+K.runsFuelReserveLaps),a.maxFuel)
 end
 -- Attente à l'emplacement : jamais au premier passage de la session (les sorties étalées s'en chargent).
 local wait=0
 if not first then
  if profile=='Q' then wait=K.runsBoxQMin+u3*(K.runsBoxQMax-K.runsBoxQMin) else wait=K.runsBoxPMin+u3*(K.runsBoxPMax-K.runsBoxPMin) end
  if frame.left and frame.left>0 then wait=min(wait,max(0,frame.left-(laps+1)*lap*K.runsTimeMargin)) end
 end
 -- Relecture 1.59 : passage prévu sous drapeau rouge ou pendant la sortie conditionnée : aucune attente ajoutée.
 local inc=e.incidents
 if inc and (inc.red or inc.gate and inc.gate[i]) then wait=0 end
 c.waitUntil=now+wait
 if e.note then
  e.note('INFO',string.format('passage en piste: %s, %s, %d tour(s) prevu(s), pneu %s, carburant %s, attente %.0f s',name(a),programNames[program],laps,
   compound>=0 and ((a.tyreNames and a.tyreNames[compound]) or tostring(compound)) or '-',c.fuel>=0 and string.format('%.0f L',c.fuel) or '-',wait),i)
 end
 return true
end
-- Une fois par image, après src/pits.lua et la stratégie (qui remettent les demandes d'arrêt à zéro).
function M.update(e,frame,now)
 local t=e.runs; if not t then t=M.new(); e.runs=t end
 local profile=e.profile; local p=e.run
 if t.session~=frame.session or now<t.last then M.reset(t); t.session=frame.session end
 t.last=now
 -- Carburant d'un passage : demandé à nouveau à chaque image (jamais une valeur d'une autre session ou d'un autre profil).
 for i=1,K.maxCars do e.commands[i].runFuelSet=-1 end
 if profile=='C' then
  -- Course : entrée aux stands d'une IA sans demande de l'app (règles, météo, stratégie, sanction, appel d'une IA lente,
  -- passage de pénalité, dépannage), au journal détaillé seulement.
  for i=1,frame.count do
   local a=frame.cars[i]; local c=t.cars[i]; local cmd=e.commands[i]
   local entered=a.pit and not c.wasPit
   c.wasPit=a.pit==true
   if entered and e.runtimeG.debugLog and frame.started and a.valid and a.control and not a.player and not a.safetyCar and not a.finished
    and not (cmd.rulePit or cmd.weatherPit or cmd.stratCalled or cmd.sanCalled or cmd.slowCalled or cmd.penaltyPass or cmd.recover) then
    U.log(e.log,now,'DEBUG',string.format('entree aux stands sans demande de l app: %s, demande d arret AC %s',name(a),a.requestingPit and 'oui' or 'non'),i)
   end
  end
  return
 end
 local inc=e.incidents
 local active=(profile=='P' or profile=='Q') and p.qualiRuns==true and not frame.online and not frame.replay
 if not active then
  for i=1,frame.count do local c=t.cars[i]; c.phase=''; c.wasBox=frame.cars[i].inPitBox==true; c.wasPit=frame.cars[i].pit==true end
  return
 end
 local calm=not inc.red and not inc.neutral
 -- Appels simultanés limités (comme en course) : les IA déjà appelées gardent leur place.
 -- Relecture 1.59 : place d'appel tenue (c.called) jusqu'à la voie des stands ; src/pits.lua remet cmd.rulePit à zéro
 -- avant ce module, donc les appels des autres modules encore en cours (IA lente, sanctions) sont comptés à part.
 local requested=0
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]; local cmd=e.commands[i]
  if a.pit then c.called=false end
  if not a.pit and (c.called or cmd.slowCalled or cmd.sanCalled) then requested=requested+1 end
 end
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]; local cmd=e.commands[i]
  local identity=a.identity or a.id or ''
  if c.identity~=identity then t.cars[i]=car(); c=t.cars[i]; c.identity=identity end
  if a.valid and a.control and not a.player and not a.safetyCar and not a.finished then
   local pc=e.pits.cars[i]
   local lap=a.lap or 0
   -- Un seul passage prévu par passage dans la voie des stands (même une voiture déjà à son emplacement à la première vue).
   if not a.pit then c.lanePlanned=false end
   if a.inPitBox and cmd.penaltyPass then
    -- Relecture 1.59 : passage de pénalité à l'emplacement : aucun passage prévu, aucun carburant écrit.
    c.phase='box'
   elseif a.inPitBox then
    -- Arrivée à l'emplacement (un seul service par passage dans la voie des stands) : prochain passage prévu.
    local first=pc.laneVisit==nil or pc.laneVisit==pc.visit
    if not c.lanePlanned and first then
     local opening=c.phase==''
     c.visit=pc.visit; c.lanePlanned=true
     c.stay=not plan(t,e,frame,a,i,c,profile,now,opening)
     if c.stay and not c.stayLogged then c.stayLogged=true; if e.note then e.note('INFO',string.format('passage en piste: %s reste aux stands (plus assez de temps avant la fin)',name(a)),i) end end
    end
    c.phase='box'
    if first and c.visit==pc.visit and not c.stay then
     -- Relecture 1.59 : piste mouillée ou pneus choisis par la météo : aucun composé sec imposé.
     local weatherTyres=(e.weather and e.weather.wet) or (cmd.weatherManaged and (cmd.weatherCompound or -1)>=0)
     if c.compound>=0 and c.compound~=a.compoundIndex and not weatherTyres then cmd.pitCompound=c.compound end
     if c.fuel>=0 then cmd.runFuelSet=c.fuel; cmd.runFuelVisit=pc.visit end
    end
    if c.stay or now<c.waitUntil then cmd.pitHold=true end
   elseif a.pit then
    -- Voie des stands : rien à demander (la demande d'arrêt est levée par applier une fois servie).
    if c.phase=='in' then c.phase='lane' end
   else
    if c.wasBox or c.wasPit or c.phase=='' then
     -- Sortie des stands, ou première vue en piste : tour de sortie jusqu'à la ligne.
     if c.phase=='' and not c.wasPit then
      c.visit=pc.visit; plan(t,e,frame,a,i,c,profile,now,true)
     end
     c.phase='out'; c.lapStart=lap; c.exitAt=now
    end
    -- Ligne passée juste après la sortie (ligne placée après la sortie des stands) : le tour de sortie continue.
    if c.phase=='out' and lap>c.lapStart and now-c.exitAt<K.qualiOutGrace then c.lapStart=lap end
    local done=c.lapStart>=0 and lap-c.lapStart or 0
    if c.phase=='out' and done>=1 then c.phase='run' end
    -- Tour lancé gâché (qualifications) : la voiture n'était plus lancée en piste pendant ce tour.
    if c.phase=='run' and e.quali and e.quali.active and not e.quali.push[i] then c.spoiled=true end
    if c.phase=='run' and done>=1+c.planned then
     -- Beta 1.62 (décision 3 du pilote) : dernier tour lancé fautif (src/quali.lua : limites de piste ou drapeau jaune) :
     -- toujours refait (au plus K.runsRedoMax fois par passage), sans tirage ; le temps reste au classement d'AC.
     local qc=e.quali and e.quali.cars[i]
     local faulty=profile=='Q' and qc and qc.faultyLap>=0 and qc.faultyLap==lap-1
     if faulty and (c.redone or 0)<K.runsRedoMax then
      c.redone=(c.redone or 0)+1; c.planned=c.planned+1; c.spoiled=false
      if e.note then e.note('INFO',string.format('passage en piste: %s, tour rapide refait (tour fautif)',name(a)),i) end
     elseif profile=='Q' and c.spoiled and not c.second and U.unit(e.runtimeG.seed or 0,i,K.runsSalt+701+c.run)<K.runsSecondChance then
      c.second=true; c.planned=c.planned+1; c.spoiled=false
      if e.note then e.note('INFO',string.format('passage en piste: %s, second tour rapide (premier tour gache)',name(a)),i) end
     else c.phase='in' end
    end
    -- Tour de rentrée : arrêt demandé jusqu'à la voie des stands (jamais sous drapeau rouge ni neutralisation).
    if c.phase=='in' and calm then
     if c.called then cmd.rulePit=true
     elseif not cmd.rulePit and requested<K.runsConcurrent then requested=requested+1; c.called=true; cmd.rulePit=true end
    elseif c.called and not calm then c.called=false end
   end
  else c.phase='' end
  c.wasBox=a.inPitBox==true; c.wasPit=a.pit==true
 end
end
-- Relecture 1.59 : horloge du moteur recalée (src/engine.lua, M.rebase).
function M.rebase(t,amount)
 if not t then return end
 if t.last>-math.huge then t.last=t.last-amount end
 for _,c in ipairs(t.cars) do
  if c.exitAt>-math.huge then c.exitAt=c.exitAt-amount end
  if c.waitUntil>-math.huge then c.waitUntil=c.waitUntil-amount end
 end
end
return M
