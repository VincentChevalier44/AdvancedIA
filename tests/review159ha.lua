-- Beta 1.59 (H-A, décision du pilote) : vrais passages en piste des IA en essais et qualifications (src/runs.lua),
-- carburant du passage posé à l'emplacement (applier), audit des entrées aux stands sans demande (course, journal
-- détaillé). Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local R=require('src/runs')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Voiture 2 : pneus SS/S/M/H, consommation connue, à son emplacement (voie des stands).
local function scene(profile,on,left)
 local e,f=F.scene(profile,3)
 e.profiles[profile].qualiRuns=on; E.changed(e)
 f.left=left or 1000
 local a=f.cars[2]
 a.id='lotus_exos'; a.tyresKnown=true; a.compoundIndex=1
 a.tyreNames={[0]='H',[1]='M',[2]='S',[3]='SS'}; a.tyreLongNames={[0]='Slick Hard',[1]='Slick Medium',[2]='Slick Soft',[3]='Slick SuperSoft'}
 a.dryCompounds={[0]=true,[1]=true,[2]=true,[3]=true}
 a.fuel=40; a.maxFuel=60; a.fuelPerLap=2.5; a.lastLap=90; a.bestLap=88
 a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0
 return e,f,a
end
local function track(a,lap) a.pit=false; a.inPitBox=false; a.kmh=150; a.speed=150/3.6; a.lap=lap end
tests.RUNS_RANK_159HA=function()
 local a={tyreNames={[0]='HS',[1]='US',[2]='SS',[3]='S',[4]='M',[5]='H',[6]='X'},tyreLongNames={[6]='Slick Super Hard'}}
 assert(R.rank(a,0)==0 and R.rank(a,1)==1 and R.rank(a,2)==2 and R.rank(a,3)==3 and R.rank(a,4)==4 and R.rank(a,5)==5,'short names ranked')
 assert(R.rank(a,6)==6,'super hard from the long name (same ranks as the starting strategies)')
 assert(R.rank({tyreNames={[0]='Q1'}},0)==nil,'unknown compound: no rank')
end
tests.RUNS_SETTING_159HA=function()
 assert(C.hidden('Q','qualiRuns')==false and C.hidden('P','qualiRuns')==false,'shown in practice and qualifying')
 assert(C.hidden('C','qualiRuns') and C.hidden('J','qualiRuns') and C.hidden('H','qualiRuns'),'hidden elsewhere')
 for _,profile in ipairs({'J','P','Q','C','H'}) do assert(C.defaults(profile).qualiRuns==false,'off by default in '..profile) end
 local p=C.defaults('Q'); p.qualiRuns=true; p.section_yield=false
 assert(C.effective('Q',p).qualiRuns==false,'Yielding section off: runs off')
end
tests.RUNS_OFF_BY_DEFAULT_159HA=function()
 local e,f=scene('Q',false)
 F.tick(e,f,1)
 local cmd=e.commands[2]
 assert(cmd.runFuelSet==-1 and cmd.pitCompound==-1 and not cmd.rulePit and not cmd.pitHold,'nothing commanded')
 assert(count(e,'passage en piste')==0,'no line')
end
tests.RUNS_QUALIFYING_CYCLE_159HA=function()
 local e,f,a=scene('Q',true)
 F.tick(e,f,0.2)
 local cmd=e.commands[2]
 -- Premier passage : composé le plus tendre (SS), juste assez de carburant (sortie, un tour, rentrée, réserve), pas d'attente.
 assert(cmd.pitCompound==3,'softest dry compound')
 assert(math.abs(cmd.runFuelSet-(1+2+K.runsFuelReserveLaps)*2.5)<1e-6,'low fuel for one flying lap')
 assert(not cmd.pitHold,'no wait before the first run (staggered exits handle it)')
 assert(count(e,'passage en piste: Driver_2, tour rapide, 1 tour(s) prevu(s), pneu SS')==1,'run logged')
 -- Tour de sortie, tour lancé, puis tour de rentrée : arrêt demandé.
 track(a,5); F.tick(e,f,K.qualiOutGrace+1); assert(not cmd.rulePit,'out-lap (line well after the pit exit)')
 a.lap=6; F.tick(e,f,0.2); assert(not cmd.rulePit,'flying lap')
 a.lap=7; F.tick(e,f,0.2); assert(cmd.rulePit,'in-lap: pit requested')
 -- Retour à l'emplacement : nouveau passage prévu, avec attente.
 a.pit=true; F.tick(e,f,0.2); a.inPitBox=true; a.kmh=0; a.speed=0; F.tick(e,f,0.2)
 assert(not cmd.rulePit,'request dropped once in the pits')
 assert(cmd.pitHold,'waits in the box before the next run')
 assert(count(e,'passage en piste: Driver_2, tour rapide')==2,'second run planned')
 local wait=e.runs.cars[2].waitUntil-e.time
 assert(wait>=K.runsBoxQMin-1 and wait<=K.runsBoxQMax,'qualifying wait within bounds')
end
tests.RUNS_QUALIFYING_NO_TIME_159HA=function()
 -- Plus assez de temps pour un tour de sortie et un tour lancé : l'IA reste à son stand (le dernier essai compte).
 local e,f=scene('Q',true,120)
 F.tick(e,f,0.5)
 assert(e.commands[2].pitHold,'stays in the box')
 assert(count(e,'reste aux stands (plus assez de temps avant la fin)')==1,'logged once')
 -- Essais : programme raccourci, mais jamais un passage sans tour ; l'IA reste aussi à son stand.
 e,f=scene('P',true,120)
 F.tick(e,f,0.5)
 assert(e.commands[2].pitHold and e.runs.cars[2].planned==0,'practice: stays in the box too')
end
tests.RUNS_PRACTICE_PROGRAMME_159HA=function()
 local names={'simulation de qualification','long relais','essai de pneus','essai de carburant','essai de reglages'}
 local seen={}
 for seed=1,40 do
  local e,f=scene('P',true,1000); e.runtimeG.seed=seed; e.g.seed=seed
  F.tick(e,f,0.1)
  local c=e.runs.cars[2]
  assert(c.program~='flying' and c.program~='','practice programme drawn')
  seen[c.program]=true
  -- Jamais au-delà de la fin de la session : sortie, tours prévus et rentrée tiennent dans le temps restant.
  local fit=math.floor(1000/(90*K.runsTimeMargin))-1
  assert(c.planned>=1 and c.planned<=fit,'run fits before the end')
  if c.program=='long' then assert(e.commands[2].pitCompound==-1,'long run: tyre kept') end
  if c.program=='tyre' then assert(e.commands[2].pitCompound>=0 and e.commands[2].pitCompound~=1,'tyre test: another compound') end
 end
 local kinds=0; for _ in pairs(seen) do kinds=kinds+1 end
 assert(kinds>=4,'programmes are varied across the field')
 for _,n in ipairs(names) do assert(type(n)=='string') end
end
tests.RUNS_NOT_IN_RACE_159HA=function()
 local e,f=scene('C',true)
 F.tick(e,f,0.2)
 assert(e.commands[2].runFuelSet==-1 and count(e,'passage en piste')==0,'never in a race')
end
tests.RUNS_NATIVE_PIT_AUDIT_159HA=function()
 local e,f=F.scene('C',3); local a=f.cars[2]
 F.tick(e,f,0.1)
 a.pit=true; F.tick(e,f,0.1)
 assert(count(e,'entree aux stands sans demande de l app')==0,'nothing without the detailed log')
 a.pit=false; F.tick(e,f,0.1)
 e.g.debugLog=true; E.changed(e); F.tick(e,f,0.1)
 a.pit=true; F.tick(e,f,0.1)
 assert(count(e,'entree aux stands sans demande de l app: Driver_2')==1,'logged with the detailed log')
end
tests.RUNS_ONE_SERVICE_PER_LANE_159HA=function()
 -- Règle de la 1.58 : une deuxième arrivée à l'emplacement sans sortir de la voie des stands n'est pas un nouveau passage.
 local e,f,a=scene('Q',true)
 F.tick(e,f,0.2)
 assert(count(e,'passage en piste: Driver_2')==1,'first run planned')
 a.inPitBox=false; a.kmh=20; a.speed=20/3.6; F.tick(e,f,0.2)
 a.inPitBox=true; a.kmh=0; a.speed=0; F.tick(e,f,0.2)
 assert(count(e,'passage en piste: Driver_2')==1,'no second plan in the same lane pass')
 assert(e.commands[2].pitCompound==-1 and e.commands[2].runFuelSet==-1,'no second service')
end
return tests
