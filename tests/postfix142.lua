-- Beta 1.42, relecture adverse des correctifs (scratchpad/n142/review_postfix.md) : un test par constat, repris des
-- simulations du relecteur (scratchpad/adv142f), par le vrai chemin Engine.step. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Pits=require('src/pits')
local Strategy=require('src/strategy')
local A=require('src/applier')
local K=C.K
local tests={}
local function logged(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function tyres(a,w) a.wearKnown=true; a.tyreWear={w,w,w,w}; a.tyreKm={1,1,1,1}; a.tyreTemp={90,90,90,90}; a.tyreOptimum={90,90,90,90}; a.tyresKnown=true; a.compoundIndex=1 end
local function arm(e,i,lap,nextLap,limit)
 local c=e.strategy.cars[i]; c.lap=lap; c.lapWear=0.5; c.wearRate=0.05; c.wearLaps=3; c.planned=true; c.stops=1; c.nextLap=nextLap; c.limit=limit or 'tyres'
 return c
end
local function pit(f,i,e,laneBefore,box,laneAfter)
 local a=f.cars[i]
 a.pit=true; F.tick(e,f,laneBefore or 2); a.inPitBox=true; a.kmh=0; a.speed=0; F.tick(e,f,box or 1)
 a.inPitBox=false; a.kmh=60; a.speed=60/3.6; F.tick(e,f,laneAfter or 2); a.pit=false; a.kmh=100; a.speed=100/3.6
end
local function penalty(e,i,f) local s=e.sanctions.cars[i]; s.pending='drive'; s.pendingReason='pitSpeed'; s.issueLap=f.cars[i].lap; return s end

-- M1 : un passage de pénalité ne remet pas le relais maximal à zéro.
tests.POSTFIX_STINT_PASS_142=function()
 local e,f=F.scene('C',4)
 e.profiles.C.maxStintMin=1; e.profiles.C.mandatoryStops=0; E.changed(e)
 F.tick(e,f,0.5)
 local a=f.cars[2]; local pc=e.pits.cars[2]
 pc.lastStop=e.time-50
 penalty(e,2,f)
 F.tick(e,f,0.2)
 assert(e.sanctions.cars[2].asked,'penalty pass requested')
 a.pit=true; F.tick(e,f,6); a.inPitBox=true; a.kmh=0; a.speed=0; F.tick(e,f,1)
 assert(pc.passBox and pc.visit==0 and pc.stops==0,'a penalty pass is neither a visit nor a stop')
 a.inPitBox=false; a.kmh=60; a.speed=60/3.6; F.tick(e,f,4); a.pit=false; a.kmh=100; a.speed=100/3.6; F.tick(e,f,2)
 assert(e.sanctions.cars[2].pending=='','drive-through served')
 assert(not pc.passBox,'pass flag cleared at the exit')
 assert(e.time-pc.lastStop>60,'the stint age keeps counting from the last real stop')
 assert(pc.wanted and e.commands[2].rulePit,'the maximum stint still calls the car after the pass')
end

-- M2 (a) : aucun carburant demandé pendant un passage de pénalité, même si un arrêt des règles devient dû dans la voie.
tests.POSTFIX_PASS_NO_FUEL_142=function()
 local e,f=F.scene('C',4)
 local p=e.profiles.C
 p.pitFuel='plan'; p.strategyEnabled=false; p.mandatoryStops=1; p.pitWindowOpenPct=50; p.pitWindowClosePct=99; p.maxStintMin=0; E.changed(e)
 f.sessionLaps=30; f.leaderLaps=10; f.timedRace=false; f.sessionMinutes=0; f.fuelRate=1
 for i=1,f.count do local a=f.cars[i]; a.lap=10; a.fuel=10; a.maxFuel=100; a.fuelPerLap=2 end
 F.tick(e,f,0.5)
 assert(e.pits.state=='pending','window not yet open')
 local a=f.cars[2]; local s=penalty(e,2,f)
 F.tick(e,f,0.2)
 assert(s.asked,'penalty pass requested while nothing else is due')
 a.pit=true; F.tick(e,f,0.5)
 assert(s.entry,'the lane entry is a penalty pass')
 -- La fenêtre s'ouvre pendant le passage : l'arrêt obligatoire est voulu dans la voie (sans limite d'appels).
 f.leaderLaps=28; for i=1,f.count do f.cars[i].lap=28 end
 F.tick(e,f,1)
 assert(e.pits.cars[2].wanted,'the rules want a stop while the car is in the lane')
 assert(e.commands[2].fuelTarget<0 and e.commands[2].fuelLaps==0,'no fuel requested during a penalty pass')
 assert(e.commands[2].pitCompound<0 and not e.commands[2].pitRepair,'no tyres nor repairs during a penalty pass')
end

-- M2 (b) : la pénalité attend un arrêt des règles retenu par la limite d'appels ; l'arrêt est servi normalement.
tests.POSTFIX_PASS_WAITS_DEFERRED_142=function()
 local e,f=F.scene('C',5)
 local p=e.profiles.C
 p.pitFuel='plan'; p.strategyEnabled=false; p.mandatoryStops=1; p.pitWindowOpenPct=20; p.pitWindowClosePct=95; p.maxStintMin=0; p.pitTyres=true; E.changed(e)
 f.sessionLaps=30; f.leaderLaps=27; f.timedRace=false; f.sessionMinutes=0; f.fuelRate=1
 for i=1,f.count do local a=f.cars[i]; a.lap=27; a.fuel=10; a.maxFuel=100; a.fuelPerLap=2 end
 F.tick(e,f,0.5)
 assert(e.pits.cars[5].deferred and not e.pits.cars[5].wanted,'car 5 waits for a call slot')
 local s=penalty(e,5,f)
 F.tick(e,f,0.2)
 assert(not s.asked and not e.commands[5].rulePit and not e.commands[5].sanCalled,'the penalty waits for the deferred rule stop')
 pit(f,5,e)
 F.tick(e,f,2)
 assert(e.pits.cars[5].windowStops==1,'the rule stop is served and counted')
 assert(s.pending=='drive','the penalty stays to serve afterwards')
end

-- M2 (b) : la pénalité attend aussi un arrêt de la stratégie voulu, pas encore appelé.
tests.POSTFIX_PASS_WAITS_STRATEGY_142=function()
 local e,f=F.scene('C',6)
 e.profiles.C.pitFuel='ac'; e.profiles.C.strategyEnabled=true; e.profiles.C.mandatoryStops=0; e.profiles.C.maxStintMin=0; e.profiles.C.pitTyres=true; E.changed(e)
 f.sessionLaps=30; f.leaderLaps=10; f.timedRace=false; f.sessionMinutes=0
 e.strategy.wearTrust='trusted'
 for i=1,f.count do local a=f.cars[i]; a.lap=10; a.fuel=60; a.maxFuel=100; a.fuelPerLap=2; tyres(a,0.5) end
 for _,i in ipairs({3,4,5,6}) do arm(e,i,10,10) end
 F.tick(e,f,0.2)
 local c6=e.strategy.cars[6]
 assert(c6.wanted and not c6.called,'car 6 waits for a call slot')
 local s=penalty(e,6,f)
 F.tick(e,f,0.2)
 assert(not s.asked and not e.commands[6].rulePit,'the penalty waits for the strategy stop')
 local called=0; for i=1,f.count do if e.commands[i].rulePit and not f.cars[i].pit then called=called+1 end end
 assert(called<=K.pitConcurrent,'never more calls than the shared limit')
end

-- m3 : une nouvelle demande de passage de pénalité respecte la limite d'appels partagée.
tests.POSTFIX_PASS_CALL_LIMIT_142=function()
 local e,f=F.scene('C',6)
 e.profiles.C.pitFuel='ac'; e.profiles.C.strategyEnabled=true; e.profiles.C.mandatoryStops=0; e.profiles.C.maxStintMin=0; E.changed(e)
 f.sessionLaps=30; f.leaderLaps=10; f.timedRace=false; f.sessionMinutes=0
 e.strategy.wearTrust='trusted'
 for i=1,f.count do local a=f.cars[i]; a.lap=10; a.fuel=60; a.maxFuel=100; a.fuelPerLap=2; tyres(a,0.5) end
 for _,i in ipairs({2,3,4}) do arm(e,i,10,10) end
 F.tick(e,f,0.2)
 for _,i in ipairs({2,3,4}) do assert(e.strategy.cars[i].called,'strategy call '..i) end
 local s=penalty(e,5,f)
 F.tick(e,f,0.2)
 assert(not s.asked and not e.commands[5].rulePit,'no fourth call while three cars are called')
 -- Une place se libère : la pénalité est appelée et prend la place (comptée par pits.lua et strategy.lua).
 pit(f,2,e); F.tick(e,f,0.5)
 assert(s.asked and e.commands[5].rulePit and e.commands[5].sanCalled,'the penalty takes the free slot')
 arm(e,6,10,10); F.tick(e,f,0.3)
 assert(e.strategy.cars[6].wanted and not e.strategy.cars[6].called,'a new strategy stop counts the penalty call in the shared limit')
end

-- m1 : carburant critique jugé après le contrôle d'après l'arrêt, jamais rappelé dès la sortie des stands.
tests.POSTFIX_CRITICAL_AFTER_CHECK_142=function()
 local e,f=F.scene('C',4)
 e.profiles.C.pitFuel='ac'; e.profiles.C.strategyEnabled=true; E.changed(e)
 f.sessionLaps=30; f.leaderLaps=1; f.timedRace=false; f.sessionMinutes=0
 for i=1,f.count do local a=f.cars[i]; a.fuel=60; a.maxFuel=100; a.fuelPerLap=2 end
 local a=f.cars[2]; a.fuel=2
 F.tick(e,f,6)
 local c=e.strategy.cars[2]
 assert(c.critical,'critical fuel')
 pit(f,2,e,3,5,3)
 F.tick(e,f,0.1)
 assert(c.checkAfter and not c.wanted and not e.commands[2].rulePit,'no new call during the after-stop check')
 F.tick(e,f,24)
 assert(c.noFuelStop and not c.wanted and not c.called,'no useless extra stop when AC adds no fuel')
end

-- m2 : après un arrêt pour une panne, le carburant n'est pas jugé (aucun ravitaillement voulu).
tests.POSTFIX_NOFUEL_FAILURE_142=function()
 local e,f=F.scene('C',4)
 e.profiles.C.pitFuel='refuel'; e.profiles.C.strategyEnabled=true; e.profiles.C.mandatoryStops=0; e.profiles.C.maxStintMin=0; E.changed(e)
 f.sessionLaps=30; f.leaderLaps=20; f.timedRace=false; f.sessionMinutes=0; f.fuelRate=1
 for i=1,f.count do local a=f.cars[i]; a.lap=20; a.fuel=60; a.maxFuel=100; a.fuelPerLap=2 end
 local a=f.cars[2]; a.fuel=23
 F.tick(e,f,6)
 local c=e.strategy.cars[2]; local pc=e.pits.cars[2]
 c.wanted=true; c.cause='failure'; c.visit=pc.visit; c.stopWear=-1; c.stopFuel=a.fuel; c.stopLimit=c.limit; c.stopTarget=-1; c.called=true
 c.failState=1; c.failAt=e.time; c.failVisit=pc.visit; c.failRepair=2; c.failRamp=10; c.failLoss=0.05
 F.tick(e,f,0.1)
 pit(f,2,e,2,4,2)
 F.tick(e,f,5)
 assert(not c.noFuelStop,'a failure stop does not judge the fuel')
 assert(logged(e,'pas de carburant ajoute')==0,'no misleading line')
end

-- m4 : aucune sauvegarde du point de reprise à chaque écriture de l'accélérateur.
tests.POSTFIX_CHECKPOINT_THROTTLE_142=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C')
 local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false end
 local cmd=e.commands[2]; cmd.active=true; cmd.offset=0; cmd.levelOwned=true; cmd.aggressionOwned=false; cmd.cautionOwned=false; cmd.level=0.9; cmd.speedLimit=K.unlimitedSpeed
 local t=1; local lim=1; local dirty=0
 local function frame(target)
  if lim>target then lim=math.max(target,lim-K.sanCutRampDown/60) else lim=math.min(target,lim+K.sanCutRampUp/60) end
  cmd.throttleLimit=lim; t=t+1/60
  A.apply(a,f,e.commands,e.g,t)
  if a.recoveryDirty then dirty=dirty+1; A.checkpoint(a,f) end
 end
 for _=1,60 do frame(1) end
 dirty=0
 local w0,s0=host.throttleWrites,host.storeWrites
 for _=1,360 do frame(K.sanCutThrottle) end
 for _=1,90 do frame(1) end
 assert(host.throttleWrites-w0>10,'the throttle cut is written')
 assert(host.storeWrites==s0,'no checkpoint store per throttle write')
 assert(dirty==0,'a throttle-only write never marks the checkpoint dirty ('..dirty..' frames)')
 assert(host.throttleLimits[f.cars[2].index]==1,'throttle back to exactly 1')
end

-- m5 : sonde de l'usure jugée sur les tours observés, pas sur le numéro du tour (rechargement en pleine course).
tests.POSTFIX_WEAR_PROBE_RELOAD_142=function()
 local e,f=F.scene('C',6)
 f.sessionLaps=30; f.leaderLaps=10; f.timedRace=false; f.sessionMinutes=0
 for i=1,f.count do local a=f.cars[i]; a.lap=10; tyres(a,0.5) end
 F.tick(e,f,0.1)
 assert(e.strategy.wearTrust=='unknown','not judged unreliable on the first frame after a reload')
 for lap=11,14 do for i=1,f.count do f.cars[i].lap=lap end; F.tick(e,f,0.1) end
 assert(e.strategy.wearTrust=='unknown','still waiting before five observed laps')
 for i=1,f.count do f.cars[i].lap=15 end; F.tick(e,f,0.1)
 assert(e.strategy.wearTrust=='unreliable','unreliable after five observed laps without any rise')
end

-- m6 : overcut et réaction oubliés après un arrêt qui n'a pas été demandé par la stratégie.
tests.POSTFIX_SHIFT_RESET_142=function()
 local e,f=F.scene('C',4)
 e.profiles.C.pitFuel='refuel'; e.profiles.C.strategyEnabled=true; e.profiles.C.mandatoryStops=1; e.profiles.C.pitWindowOpenPct=20; e.profiles.C.pitWindowClosePct=80; E.changed(e)
 f.sessionLaps=30; f.leaderLaps=12; f.timedRace=false; f.sessionMinutes=0
 e.strategy.wearTrust='trusted'
 for i=1,f.count do local a=f.cars[i]; a.lap=12; a.fuel=60; a.maxFuel=100; a.fuelPerLap=2; tyres(a,0.4) end
 F.tick(e,f,6)
 local c=e.strategy.cars[2]; local a=f.cars[2]
 c.shift=2; c.reaction=true
 a.pit=true; F.tick(e,f,2); a.inPitBox=true; a.kmh=0; a.speed=0; F.tick(e,f,3)
 a.tyreWear={0,0,0,0}; a.inPitBox=false; a.kmh=60; a.speed=60/3.6; F.tick(e,f,2); a.pit=false; a.kmh=100; a.speed=100/3.6; F.tick(e,f,2)
 assert(e.pits.cars[2].visit>=1,'a box visit happened')
 assert(c.shift==0 and not c.reaction,'overcut and reaction reset at any box visit')
end

-- Pneus sans gestion météo sous la pluie : aucun pneu imposé ; au sec, un train neuf du même composé.
tests.POSTFIX_WET_NO_COMPOUND_142=function()
 local a={tyresKnown=true,compoundIndex=2,dryCompounds={[2]=true}}
 local p={pitCompoundChange=false}
 assert(Pits.compound(a,{weatherManaged=false,weatherRain=true,weatherCompound=-1},p)==-1,'no compound forced in the wet without weather management')
 assert(Pits.compound(a,{weatherManaged=false,weatherRain=false,weatherCompound=-1},p)==2,'same compound in the dry')
 assert(Pits.compound(a,{weatherManaged=true,weatherRain=true,weatherCompound=4},p)==4,'weather compound when managed')
end

-- Course chronométrée : tours restants de la stratégie au rythme propre de la voiture, comme pits.lua.
tests.POSTFIX_TIMED_LAPS_142=function()
 local e,f=F.scene('C',4)
 f.sessionLaps=0; f.timedRace=true; f.sessionMinutes=30; f.left=600
 F.tick(e,f,0.1)
 local a=f.cars[2]; e.pits.cars[2].lapTime=95
 local own=Pits.lapsLeft(f,a,95)
 assert(own==math.ceil(600/95)+1,'pits formula')
 assert(Strategy.lapsLeft(e,f,a,2)==own,'strategy uses the same laps left as pits.lua')
end

-- Drapeau rouge pendant l'arrêt (sans travail permis) : pneus non posés, mais la cause « pneus » n'est pas abandonnée.
tests.POSTFIX_RED_KEEPS_TYRE_STOPS_142=function()
 local function run(red)
  local e,f=F.scene('C',4)
  e.profiles.C.pitFuel='ac'; e.profiles.C.strategyEnabled=true; e.profiles.C.mandatoryStops=0; e.profiles.C.maxStintMin=0; e.profiles.C.pitTyres=true; E.changed(e)
  f.sessionLaps=30; f.leaderLaps=10; f.timedRace=false; f.sessionMinutes=0
  e.strategy.wearTrust='trusted'
  for i=1,f.count do local a=f.cars[i]; a.lap=10; a.fuel=60; a.maxFuel=100; a.fuelPerLap=2; tyres(a,0.6) end
  arm(e,2,10,10)
  F.tick(e,f,0.2)
  local c=e.strategy.cars[2]; local a=f.cars[2]
  assert(c.wanted,'tyre stop wanted')
  a.pit=true; F.tick(e,f,2); a.inPitBox=true; a.kmh=0; a.speed=0; F.tick(e,f,0.5)
  if red then c.stopRed=true end
  F.tick(e,f,0.5)
  a.inPitBox=false; a.kmh=60; a.speed=60/3.6; F.tick(e,f,2); a.pit=false; a.kmh=100; a.speed=100/3.6; F.tick(e,f,5)
  return c.noTyreStop
 end
 assert(run(false)==true,'tyres not changed at a normal stop: tyre stops abandoned')
 assert(run(true)==false,'a stop under red flag never abandons tyre stops')
end

-- Demande pas encore appelée devenue inutile : retirée hors de la voie ; un appel déjà donné est gardé.
tests.POSTFIX_STALE_WITHDRAW_142=function()
 local e,f=F.scene('C',6)
 e.profiles.C.pitFuel='ac'; e.profiles.C.strategyEnabled=true; e.profiles.C.mandatoryStops=0; e.profiles.C.maxStintMin=0; E.changed(e)
 f.sessionLaps=30; f.leaderLaps=10; f.timedRace=false; f.sessionMinutes=0
 e.strategy.wearTrust='trusted'
 for i=1,f.count do local a=f.cars[i]; a.lap=10; a.fuel=60; a.maxFuel=100; a.fuelPerLap=2; tyres(a,0.5) end
 for _,i in ipairs({3,4,5,6}) do arm(e,i,10,10) end
 F.tick(e,f,0.2)
 local c6,c3=e.strategy.cars[6],e.strategy.cars[3]
 assert(c6.wanted and not c6.called and c3.called,'car 6 waits, car 3 called')
 c6.stops=0; c3.stops=0
 F.tick(e,f,0.1)
 assert(not c6.wanted,'an uncalled request no longer needed is withdrawn')
 assert(c3.wanted and c3.called and e.commands[3].rulePit,'a call already given is never withdrawn')
 assert(logged(e,'arret retire')>=1,'logged once')
end

return tests
