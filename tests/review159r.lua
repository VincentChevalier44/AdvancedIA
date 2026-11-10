-- Beta 1.59 : relecture indépendante des tranches H fusionnées (S/b159/h_merged.diff). Places d'appel tenues et
-- carburant des vrais passages, appels pour dégâts encore en cours comptés, blocs de clés nouvelles imbriqués,
-- boîte de vitesses hors des appels pour dégâts, pas de composé sec sous la pluie, passage de pénalité à l'emplacement.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local R=require('src/runs')
local DP=require('src/damagepit')
local U=require('src/util')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function tyres(a)
 a.id='lotus_exos'; a.tyresKnown=true; a.compoundIndex=1
 a.tyreNames={[0]='H',[1]='M',[2]='S',[3]='SS'}; a.tyreLongNames={[0]='Slick Hard',[1]='Slick Medium',[2]='Slick Soft',[3]='Slick SuperSoft'}
 a.dryCompounds={[0]=true,[1]=true,[2]=true,[3]=true}
 a.fuel=40; a.maxFuel=60; a.fuelPerLap=2.5; a.lastLap=90; a.bestLap=88
end
-- 1. Places d'appel tenues : trois IA appelées gardent leur place ; une quatrième (d'indice plus petit) attend.
tests.RUNS_CALL_SLOTS_STICKY_159R=function()
 local e,f=F.scene('Q',6)
 e.profiles.Q.qualiRuns=true; E.changed(e)
 for i=2,6 do tyres(f.cars[i]) end
 F.tick(e,f,0.2)
 for i=3,5 do local c=e.runs.cars[i]; c.phase='in'; c.wasBox=false; c.wasPit=false end
 F.tick(e,f,0.1)
 for i=3,5 do assert(e.commands[i].rulePit and e.runs.cars[i].called,'car '..i..' called') end
 local c2=e.runs.cars[2]; c2.phase='in'; c2.wasBox=false; c2.wasPit=false
 F.tick(e,f,0.1)
 assert(not e.commands[2].rulePit,'a new call waits: the three slots are held')
 for i=3,5 do assert(e.commands[i].rulePit,'car '..i..' keeps its slot ('..tostring(e.commands[i].rulePit)..')') end
 -- Voie des stands : la place se libère, la quatrième IA est appelée.
 f.cars[3].pit=true; F.tick(e,f,0.1)
 assert(not e.runs.cars[3].called,'slot released in the pit lane')
 assert(e.commands[2].rulePit,'the waiting AI gets the free slot')
end
-- 1. Carburant d'un passage : consommation apprise d'abord, réserve d'un tour et demi.
-- Le passage est prévu à l'arrivée à l'emplacement (appel direct du module, après une image du moteur pour les réglages).
local function boxScene()
 local e,f=F.scene('Q',3)
 e.profiles.Q.qualiRuns=true; E.changed(e)
 local a=f.cars[2]; tyres(a)
 F.tick(e,f,0.1)
 a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0
 e.commands[2].pitCompound=-1; e.commands[2].runFuelSet=-1
 return e,f,a
end
tests.RUNS_FUEL_LEARNT_159R=function()
 local e,f,a=boxScene()
 a.fuelPerLap=2.0; e.pits.cars[2].perLap=3.0
 R.update(e,f,e.time)
 local expected=(1+2+K.runsFuelReserveLaps)*3.0
 assert(K.runsFuelReserveLaps>=1.5,'reserve of at least a lap and a half')
 assert(math.abs(e.commands[2].runFuelSet-expected)<1e-6,'learnt consumption used ('..tostring(e.commands[2].runFuelSet)..')')
end
-- 5. Piste mouillée : aucun composé sec imposé par un passage ; piste sèche : le plus tendre.
tests.RUNS_WET_NO_DRY_COMPOUND_159R=function()
 local e,f=boxScene()
 e.weather.wet=true
 R.update(e,f,e.time)
 assert(e.commands[2].pitCompound==-1,'wet track: no dry compound from the run')
 e,f=boxScene()
 e.weather.wet=false
 R.update(e,f,e.time)
 assert(e.commands[2].pitCompound==3,'dry track: softest compound ('..tostring(e.commands[2].pitCompound)..')')
end
-- 7. Passage de pénalité à l'emplacement : aucun passage prévu, aucun carburant écrit.
tests.RUNS_PENALTY_PASS_159R=function()
 local e,f=boxScene()
 local before=count(e,'passage en piste: Driver_2')
 e.commands[2].penaltyPass=true
 R.update(e,f,e.time)
 assert(e.commands[2].runFuelSet==-1 and e.commands[2].pitCompound==-1,'nothing written during a penalty pass')
 assert(count(e,'passage en piste: Driver_2')==before,'no run planned')
end
-- Moteur réduit pour src/damagepit.lua seul (comme tests/review159hb.lua).
local function bench(profile,n)
 local e={run={damagePit=true,section_accidents=true},profile=profile or 'C',commands={},states={},incidents={neutral=false,pitsClosed=false},
  race={lapsLeft=-1},log=U.newLog(100,100,0)}
 local frame={count=n or 3,started=true,session=0,cars={}}
 for i=1,frame.count do
  frame.cars[i]={valid=true,control=i~=1,player=i==1,finished=false,safetyCar=false,pit=false,inPitBox=false,kmh=100,id='car_'..i,identity='car_'..i,name='Driver_'..i,
   damageBody=0,damageSuspension=0,damageGearbox=0,engineLife=K.engineLifeNew}
  e.commands[i]={}; e.states[i]={yellow=false}
 end
 return e,frame
end
local function run(e,frame,from,seconds,red,check)
 local t=from
 for _=1,math.floor(seconds*60+0.5) do
  -- Comme le moteur : les demandes d'arrêt sont remises à zéro à chaque image avant ce module.
  for i=1,frame.count do local c=e.commands[i]; c.rulePit=false; c.slowCalled=false; c.stratCalled=false; c.sanCalled=false; c.recover=false; c.penaltyPass=false; c.pitRepair=false end
  DP.step(e,frame,t,red); t=t+1/60
  if check then check() end
 end
 return t
end
local WAIT=K.damagePitConfirm+K.damagePitScanPeriod+0.5
-- 2. Appels pour dégâts encore en cours comptés : jamais plus que la limite partagée en même temps.
tests.DAMAGE_PIT_OUTSTANDING_CALLS_159R=function()
 local e,f=bench('C',7)
 for i=2,7 do f.cars[i].damageBody=150 end
 local worst=0
 run(e,f,0,WAIT*3,false,function()
  local n=0; for i=2,7 do if e.commands[i].damageCalled then n=n+1 end end
  if n>worst then worst=n end
 end)
 assert(worst>0 and worst<=K.pitConcurrent,'at most the shared limit at once ('..worst..')')
end
-- 4. Boîte de vitesses : aucune réparation possible, donc jamais un appel (ni une voiture dite dangereuse).
tests.DAMAGE_PIT_GEARBOX_LOG_ONLY_159R=function()
 local e,f=bench()
 f.cars[2].damageGearbox=0.9
 run(e,f,0,WAIT)
 assert(not e.commands[2].damageCalled,'gearbox damage alone: not called')
 e,f=bench(); f.cars[2].damageGearbox=0.9; f.cars[2].damageBody=150; e.incidents.neutral=true
 run(e,f,0,WAIT)
 assert(not e.commands[2].damageCalled,'gearbox does not make the car unsafe under a neutralisation')
 e,f=bench(); f.cars[2].damageGearbox=0.9; f.cars[2].damageBody=150
 run(e,f,0,WAIT)
 assert(e.commands[2].damageCalled and count(e,'boite 0.90')==1,'bodywork call, gearbox kept in the log line')
end
-- 3. Blocs de clés nouvelles : les clés des règles et des sanctions restent nouvelles (un bloc imbriqué refermait trop tôt).
tests.CONFIG_NEW_KEYS_BLOCKS_159R=function()
 for _,key in ipairs({'damagePit','noMoveBraking','neutralization','predictableSlowClass','strategyStartVariety','sanTrackLimits','sanTrackWarnings','sanReport'}) do
  assert(C.isNewKey(key),key..' is a new key')
 end
 assert(not C.isNewKey('levelPct'),'an original key is not new')
end
-- Pont (relecture 1.59, signalé par la session SpotterEnginer) : spin, wrong et halt publiés avec les seuils de la
-- décision d'incident (ce sont des durées dans src/incidents.lua) ; onTrack pour toutes les voitures, à chaque image.
tests.BRIDGE_INCIDENT_VALUES_159R=function()
 local B=require('src/bridge')
 local e,f=F.scene('C',4)
 F.tick(e,f,0.2)
 local out={cars={}}
 for k=0,B.layout.maxCars-1 do out.cars[k]={} end
 local b=B.new('Beta 1.59')
 local ic=e.incidents.cars
 -- Voiture 2 en tête-à-queue (décision 1.59), voiture 3 à contresens au-delà du seuil, voiture 4 arrêtée au-delà du seuil.
 ic[2].spin=K.spinTime*2; ic[2].spun=true
 ic[3].wrong=K.wrongWayTime+0.1
 ic[4].halt=K.obstacleTime+0.1
 B.publish(b,out,e,f)
 assert(out.cars[1].spin==true,'spinning car: spin=true')
 assert(out.cars[2].wrong==true,'wrong-way car past the threshold: wrong=true')
 assert(out.cars[3].halt==true,'stopped car past the threshold: halt=true')
 -- Voiture normale en piste (joueur compris) : onTrack vrai, rien d'autre.
 assert(out.cars[0].onTrack==true and out.cars[0].spin==false and out.cars[0].wrong==false and out.cars[0].halt==false,'player on track at normal speed')
 for k=0,3 do assert(out.cars[k].onTrack==true,'car '..k..' on track') end
 -- Sous les seuils : faux ; hors piste : onTrack faux.
 ic[2].spun=false; ic[3].wrong=K.wrongWayTime-0.1; ic[4].halt=K.obstacleTime-0.1; f.cars[2].offtrack=true
 B.publish(b,out,e,f)
 assert(out.cars[1].spin==false and out.cars[2].wrong==false and out.cars[3].halt==false,'below the thresholds: false')
 assert(out.cars[1].onTrack==false,'off track: onTrack=false')
end
return tests
