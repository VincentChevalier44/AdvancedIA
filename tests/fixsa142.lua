-- Beta 1.42, relecture adverse STRATÉGIE et AERO (scratchpad/n142/review_strategy_aero.md) : un test par constat, repris
-- des simulations du relecteur (scratchpad/adv142t), par le vrai chemin Engine.step. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Pits=require('src/pits')
local Strategy=require('src/strategy')
local Journal=require('src/journal')
local K=C.K
local tests={}
local function logged(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function with(values,fn)
 local saved={}; for k,v in pairs(values) do saved[k]=K[k]; K[k]=v end
 local ok,err=pcall(fn)
 for k,v in pairs(saved) do K[k]=v end
 if not ok then error(err,0) end
end
local function race(count,laps,lap,settings,trusted)
 local e,f=F.scene('C',count or 4)
 f.sessionLaps=laps or 20; f.leaderLaps=lap or 2; f.timedRace=false; f.sessionMinutes=0; f.started=true; f.fuelRate=1
 for i=1,f.count do f.cars[i].lap=lap or 2 end
 if trusted~=false then e.strategy.wearTrust='trusted' end
 if settings then for k,v in pairs(settings) do e.p[k]=v end; E.changed(e) end
 F.tick(e,f,1/60)
 return e,f
end
local function worn(a,w) a.wearKnown=true; a.tyreWear={w,w,w,w}; a.tyreKm={10,10,10,10}; a.tyreTemp={90,90,90,90}; a.tyreOptimum={90,90,90,90} end
local function arm(e,i,lap,nextLap,wear)
 local c=e.strategy.cars[i]; c.lap=lap; c.lapWear=wear or 0.5; c.wearRate=0.05; c.wearLaps=3; c.planned=true; c.stops=1; c.nextLap=nextLap; c.limit='tyres'
 return c
end
-- Carte des lignes droites : tout le tour en ligne droite sauf de from à to.
local function straightMap(e,f)
 F.tick(e,f,1/60)
 local m=e.aero
 for b=1,m.bins do local x=(b-0.5)/m.bins; local corner=x>=0.5 and x<0.55; m.st[b]=corner and 0 or 1; m.seen[b]=K.towMapSeen end
 m.at=-math.huge
 return m
end
-- Meneur (2) et suiveur (3) en ligne droite, cinématique simple (décalage converti en mètres, 6 m par unité).
local function towRun(gap,followerX,followerKmh,seconds,setup)
 local e,f=F.scene('C',3); e.p.personalLineJitter=0
 if setup then setup(e,f) end
 E.changed(e)
 F.place(f,1,-4000,100); F.place(f,2,1000,200); F.place(f,3,1000-gap-4.4,followerKmh or 200,followerX)
 straightMap(e,f)
 local s2,s3=e.states[2],e.states[3]
 local towed,minDx,defendAfter=false,math.huge,false
 local out=false
 for t=1,math.floor((seconds or 8)*60) do
  for i=2,3 do local a=f.cars[i]; a.z=a.z+a.speed/60; a.spline=(a.z/f.length)%1 end
  E.step(e,f,1/60)
  f.cars[2].x=s2.offset*6; f.cars[3].x=(followerX or 0)+s3.offset*6; f.cars[2].splineLat=f.cars[2].x; f.cars[3].splineLat=f.cars[3].x
  -- Suiveur sorti pour dépasser à l'image précédente : la cassure est déjà finie (une image de décalage entre voitures).
  if s2.state=='DEFEND' and s2.reason=='tow' then towed=true; assert(not out,'tow never held while the follower pulls out') end
  out=s3.state=='OVT_IN' or s3.state=='OVT_HOLD'
  if towed and s2.state=='DEFEND' and s2.reason=='attacker' then defendAfter=true end
  local gapNow=f.cars[2].z-f.cars[3].z
  if towed and math.abs(gapNow)<6 then minDx=math.min(minDx,math.abs(f.cars[2].x-f.cars[3].x)) end
 end
 return e,f,towed,minDx,defendAfter
end

-- S-B1 : jamais d'arrêt carburant au dernier tour quand l'essence finit la course ; arrêt gardé sinon.
tests.FIXSA_LAST_LAP_FUEL_142=function()
 local function last(fuelLaps,lap)
  local e,f=race(3,20,lap or 19,{pitFuel='refuel'})
  local a=f.cars[2]; e.states[2].persona.strategyRisk=0.5
  a.maxFuel=60; a.fuelPerLap=3; a.fuel=3*fuelLaps
  F.tick(e,f,K.strategyRetry+0.5)
  return e.strategy.cars[2],e
 end
 for _,laps in ipairs({1.2,1.4,1.8,2.6}) do local c,e=last(laps); assert(c.stops==0 and not c.wanted and not e.commands[2].rulePit,'last lap, fuel for '..laps..' laps: no stop') end
 local c=last(1.4,17); assert(c.wanted and c.cause=='fuel','3 laps left, fuel for 1.4 laps: stop kept')
end
-- S-B2 : arrêt de stratégie sans règles d'arrêt : pneus neufs posés par l'app ; pneus non changés : plus d'arrêt pour
-- les pneus (jamais un arrêt à chaque tour).
tests.FIXSA_NO_STOP_LOOP_142=function()
 local e,f=race(4,20,2,nil,false)
 local a=f.cars[2]; e.states[2].persona.strategyRisk=0.5; a.tyresKnown=true; a.compoundIndex=0
 local w=0
 for lap=2,8 do a.lap=lap; w=0.1*(lap-1); worn(a,w); f.leaderLaps=lap; F.tick(e,f,0.2) end
 assert(e.strategy.wearTrust=='trusted','wear scale verified on the way')
 local visits,compound=0,-1
 for lap=8,16 do
  if e.commands[2].rulePit then
   a.pit=true; F.tick(e,f,0.2); a.inPitBox=true; a.kmh=0; F.tick(e,f,0.5)
   if visits==0 then compound=e.commands[2].pitCompound end
   a.inPitBox=false; a.kmh=60; F.tick(e,f,0.2); a.pit=false; a.kmh=100; visits=visits+1
  end
  a.lap=lap+1; f.leaderLaps=lap+1; w=math.min(1,w+0.02); worn(a,w); F.tick(e,f,1)
 end
 assert(compound==0,'new tyres fitted by the app at the strategy stop: '..compound)
 assert(visits==1,'tyres not changed: no stop every lap ('..visits..' visits)')
 assert(logged(e,'pneus non changes a l arret')==1,'logged once')
end
-- S-M1 : appels tenus : une IA déjà appelée garde sa place ; la stratégie et les règles partagent la même limite.
tests.FIXSA_CALL_SLOTS_142=function()
 local e,f=race(9,30,10)
 for i=1,f.count do worn(f.cars[i],0.5) end
 for _,i in ipairs({5,6,7,8}) do arm(e,i,10,10) end
 for _,i in ipairs({2,3,4}) do arm(e,i,10,12) end
 F.tick(e,f,0.1)
 local function called() local n=0; for i=2,9 do if e.commands[i].rulePit then n=n+1 end end return n end
 assert(e.commands[5].rulePit and e.commands[6].rulePit and e.commands[7].rulePit and not e.commands[8].rulePit,'three called, the fourth waits')
 e.strategy.cars[3].nextLap=10; F.tick(e,f,0.1)
 e.strategy.cars[2].nextLap=10; F.tick(e,f,0.1)
 assert(e.commands[5].rulePit and e.commands[6].rulePit and e.commands[7].rulePit,'called cars keep their slot')
 assert(called()==K.pitConcurrent,'never more than the limit: '..called())
 -- Règles d'arrêt (arrêt obligatoire) : pas de place de plus que la stratégie n'en tient déjà.
 e.p.mandatoryStops=1; e.p.pitWindowOpenPct=0; e.p.pitWindowClosePct=100; E.changed(e); F.tick(e,f,0.1); F.tick(e,f,0.1)
 assert(not e.commands[9].rulePit and called()==K.pitConcurrent,'rules share the same limit: '..called())
 -- Carburant critique : appelé malgré la limite.
 local b=f.cars[9]; b.maxFuel=100; b.fuelPerLap=4; b.fuel=2; e.strategy.cars[9].replan=true; F.tick(e,f,0.1)
 assert(e.strategy.cars[9].critical and e.commands[9].rulePit,'critical fuel: called despite the limit')
end
-- S-M2 : arrêt non critique retenu tant que la fenêtre obligatoire n'est pas ouverte ; tranche de chaque arrêt respectée.
tests.FIXSA_WINDOW_HOLD_142=function()
 local e,f=race(4,20,4,{mandatoryStops=1,pitWindowOpenPct=50,pitWindowClosePct=100})
 local a=f.cars[2]; worn(a,0.5)
 arm(e,2,4,4); F.tick(e,f,0.2)
 assert(not e.strategy.cars[2].wanted and not e.commands[2].rulePit,'held until the window opens')
 assert(logged(e,'arret retenu jusqu a l ouverture de la fenetre obligatoire')==1,'logged once')
 a.maxFuel=100; a.fuelPerLap=4; a.fuel=2; e.strategy.cars[2].replan=true; F.tick(e,f,0.2)
 assert(e.strategy.cars[2].wanted and e.strategy.cars[2].cause=='fuel','critical fuel: never held')
 -- Relecture 1.52 : un seul arrêt obligatoire depuis la 1.51 (fenêtre 10 à 90 %, tour 79 / 100) : arrêt aligné sur le
 -- plan seulement s'il tombe avant la fin de la fenêtre moins la marge de la stratégie (avant : tranche du premier de
 -- deux arrêts, code mort retiré).
 local function ruled(nextLap)
  -- Plan connu (cmd.stratPlanAt) avant que les règles d'arrêt ne jugent l'appel.
  local x,fx=race(3,100,79)
  worn(fx.cars[2],0.3); arm(x,2,79,nextLap,0.3)
  F.tick(x,fx,0.1)
  x.p.mandatoryStops=1; x.p.pitWindowOpenPct=10; x.p.pitWindowClosePct=90; E.changed(x)
  F.tick(x,fx,0.1); F.tick(x,fx,0.1)
  return x.commands[2].rulePit
 end
 assert(not ruled(81),'plan inside the window: rules wait for it')
 assert(ruled(85),'plan beyond the end of the window (less the margin): the rules call the stop')
end
-- S-M3 : un tour neutralisé n'apprend pas la consommation (pits.lua).
tests.FIXSA_FUEL_NEUTRAL_142=function()
 local t=Pits.new()
 local a={valid=true,control=true,player=false,safetyCar=false,finished=false,fuel=80,maxFuel=100,lap=1,pit=false,id='car',fuelPerLap=0}
 local frame={count=1,cars={a},sessionLaps=30,timedRace=false,started=true,fuelRate=1,online=false,replay=false,track='x',left=0,sessionMinutes=0}
 local commands={{rulePit=false,weatherManaged=false}}
 local p={pitFuel='refuel',mandatoryStops=0,maxStintMin=0}
 local now=0
 local function lap(used,neutral)
  t.neutral=neutral; now=now+90
  Pits.fuel(t,frame,commands,p,'C',now,false)
  a.fuel=a.fuel-used; a.lap=a.lap+1
 end
 for _=1,4 do lap(4,false) end
 lap(4,false); local learnt=t.cars[1].perLap
 lap(1.6,true); lap(1.6,true); lap(4,false); Pits.fuel(t,frame,commands,p,'C',now+90,false)
 assert(math.abs(t.cars[1].perLap-learnt)<1e-6,'neutralised laps not learnt: '..t.cars[1].perLap..' vs '..learnt)
end
-- S-M5 : échelle de l'usure vérifiée avant usage : usure constante (jamais vue neuve) : non fiable ; usure qui monte depuis
-- un pneu neuf : vérifiée.
tests.FIXSA_WEAR_TRUST_142=function()
 local e,f=race(3,20,1,nil,false)
 assert(e.strategy.wearTrust=='unknown','unknown at the start')
 -- Voiture 2 : usure qui monte sans jamais avoir été vue neuve ; voiture 3 : usure figée.
 for lap=1,6 do f.cars[2].lap=lap; f.cars[3].lap=lap; worn(f.cars[2],0.3+0.05*lap); worn(f.cars[3],0.3); f.leaderLaps=lap; F.tick(e,f,0.5) end
 assert(e.strategy.wearTrust=='unreliable' and logged(e,'usure des pneus non fiable ici')==1,'never seen new: unreliable, logged once')
 assert(e.strategy.cars[2].stops<=0,'no tyre plan from unverified wear')
 worn(f.cars[3],0.02); F.tick(e,f,0.5); f.cars[3].lap=7; worn(f.cars[3],0.05); F.tick(e,f,0.5)
 assert(e.strategy.wearTrust=='trusted' and logged(e,'usure des pneus: echelle verifiee')==1,'rising from new tyres: verified')
 -- Gardée à la session suivante.
 f.session=f.session+1; F.tick(e,f,0.2); assert(e.strategy.wearTrust=='trusted','kept across sessions')
end
-- Mineurs de la stratégie.
tests.FIXSA_STRATEGY_MINORS_142=function()
 -- Course chronométrée : le tour qui suit la fin du temps compte.
 local e,f=race(3,0,5); f.timedRace=true; f.sessionLaps=0; f.sessionMinutes=30; f.left=600; F.tick(e,f,0.1)
 assert(e.race.known and Strategy.lapsLeft(e,f,f.cars[2])==e.race.lapsLeft+1,'timed race: the lap after the end of the time')
 -- Consommation coupée : jamais un arrêt carburant.
 local x,fx=race(3,20,5); fx.fuelRate=0; local a=fx.cars[2]; a.maxFuel=100; a.fuelPerLap=4; a.fuel=4
 F.tick(x,fx,K.strategyRetry+0.5)
 assert(not x.strategy.cars[2].wanted,'fuel consumption off: no fuel stop')
 -- Panne « batterie » seulement sur une voiture hybride (charge de batterie vue).
 with({failureCheck=1},function()
  local y,fy=race(12,30,5,{failuresEnabled=true,failureRate=3600,strategyEnabled=true})
  for i=2,fy.count do local b=fy.cars[i]; b.kers=0; b.kmh=150; b.speed=150/3.6 end
  F.tick(y,fy,3)
  local n=0
  for i=2,fy.count do local c=y.strategy.cars[i]; if c.failState==1 then n=n+1; assert(c.failKind~='battery','no battery failure without a battery') end end
  assert(n>=3,'failures drawn: '..n)
 end)
 -- Blocage déjà journalisé : pas de ligne « usure: » fantôme au changement de session.
 local w,fw=race(3,20,5)
 local cmd=w.commands[2]; w.mistakes.cars[2].lockWear=0.6; w.mistakes.cars[2].lockAsym=0.2
 cmd.wearId=(cmd.wearId or 0)+1; cmd.wearWheel=0; cmd.wearKm=1; F.tick(w,fw,0.1)
 local before=logged(w,'usure:'); fw.session=fw.session+1; F.tick(w,fw,0.5)
 assert(before==1 and logged(w,'usure:')==1,'no ghost wear line after a session change')
 -- Tour de sortie : jamais après un saut de position jusqu'à l'emplacement (dépannage).
 local o,fo=F.scene('P',3); local d=fo.cars[2]; local dc=o.commands[2]
 F.tick(o,fo,K.outLapSummaryTime+1)
 d.teleport=true; d.pit=true; d.inPitBox=true; d.kmh=0; F.tick(o,fo,1/60); d.teleport=false; F.tick(o,fo,1)
 d.inPitBox=false; d.kmh=60; F.tick(o,fo,0.5); d.pit=false; d.kmh=120; F.tick(o,fo,0.5)
 assert(dc.levelScale==1,'no out-lap after a recovery teleport to the box')
 -- Course : arrêt au premier tour (départ des stands après l'extinction des feux) : pas de tour de sortie.
 local r,fr=race(3,20,0,{outLapEnabled=true}); local b=fr.cars[2]
 b.pit=true; b.inPitBox=true; b.kmh=0; F.tick(r,fr,1); b.inPitBox=false; b.pit=false; b.kmh=100; F.tick(r,fr,0.5)
 assert(r.commands[2].levelScale==1,'race lap 0 from the pits: no out-lap')
 -- Redémarrage d'une session de même indice : pannes mémorisées oubliées.
 local t=Strategy.new(); Strategy.restore(t,'0\nDriver_2,2',0); assert(t.restored and t.restored.Driver_2==2,'restored')
 Strategy.forget(t); assert(t.restored==nil and t.restoredSession==-1,'forgotten')
end
-- Blocages : méplats bornés par relais, remis à zéro à chaque passage à l'emplacement.
tests.FIXSA_LOCK_KM_PER_STINT_142=function()
 -- Échelle de l'usure pas encore vérifiée : aucun méplat ajouté.
 local u,fu=race(3,30,5,{mistakesEnabled=true,mistakeRate=600,lockWearEnabled=true,lockFlatSpotKm=4},false)
 local b=fu.cars[2]; worn(b,0.9); b.brake=1; b.gas=0; b.kmh=180; b.speed=50
 local first=u.commands[2].wearId
 F.tick(u,fu,300,false)
 assert(u.strategy.wearTrust~='trusted' and u.commands[2].wearId==first,'unverified wear scale: no flat spot')
 local e,f=race(3,30,5,{mistakesEnabled=true,mistakeRate=600,lockWearEnabled=true,lockFlatSpotKm=4})
 local a=f.cars[2]; worn(a,0.9); a.tyreWear[2]=0.6; a.brake=1; a.gas=0; a.kmh=180; a.speed=50
 for _=1,9000 do F.tick(e,f,0.1); if e.mistakes.cars[2].lockKm>=K.lockWearMaxKm then break end end
 assert(e.mistakes.cars[2].lockKm>=K.lockWearMaxKm-1e-9,'cap reached in the stint')
 -- Relecture des correctifs : un passage à l'emplacement sans pneus neufs garde les méplats du relais (plafond tenu).
 e.pits.cars[2].visit=e.pits.cars[2].visit+1
 local last=e.commands[2].wearId; local more=false
 for _=1,3000 do F.tick(e,f,0.1); if e.commands[2].wearId~=last then more=true; break end end
 assert(not more,'a visit without new tyres keeps the stint flat spots')
 -- Pneus neufs (usure retombée) : nouveau relais, méplats comptés de nouveau.
 e.pits.cars[2].visit=e.pits.cars[2].visit+1
 worn(a,0.78); a.tyreWear[2]=0.5; a.brake=1; a.gas=0; a.kmh=180; a.speed=50
 for _=1,9000 do F.tick(e,f,0.1); if e.commands[2].wearId~=last then more=true; break end end
 assert(more,'new tyres: flat spots counted again')
end
-- A-B1 : cassure loin du suiveur et de son côté de dépassement ; jamais face à un suiveur rapide, déjà en dépassement ou
-- au joueur.
tests.FIXSA_TOW_SIDE_142=function()
 with({towChance=1},function()
  local e,_,towed,minDx=towRun(14,-0.8,212)
  assert(towed,'tow broken')
  assert(e.states[2].targetSide>0,'away from the follower (on the left) and from its forced passing side (left)')
  assert(minDx>=2.5,'never into the follower: lateral gap '..minDx..' m when level')
  local _,_,fast=towRun(28,-0.6,240); assert(not fast,'never against a follower arriving fast')
  local _,_,right=towRun(25,0.8,200); assert(not right,'follower already on the side to move to: no tow')
 end)
end
-- A-M1 : un seul mouvement par ligne droite : pas de défense après la cassure contre le même attaquant.
tests.FIXSA_TOW_THEN_DEFENCE_142=function()
 with({towChance=1,defenseChance=1},function()
  local e,_,towed,_,defendAfter=towRun(28,-0.5,206,25,function(x) x.profiles.C.overtakeEnabled=false end)
  assert(towed,'tow broken')
  assert(not defendAfter,'no defence move after the tow on the same straight')
  assert(e.states[2].directionCount<=1,'one side change: '..e.states[2].directionCount)
 end)
end
-- A-M2 : une zone de freinage n'est pas de la ligne droite (carte apprise).
tests.FIXSA_TOW_MAP_BRAKING_142=function()
 local e,f=F.scene('C',3); E.changed(e)
 F.place(f,1,-4000,100); F.place(f,2,1000,200); F.place(f,3,-2000,100)
 F.tick(e,f,1/60)
 local m=e.aero; local a=f.cars[2]
 local b=require('src/delta').bin(a.spline,m.bins)
 for _=1,120 do a.yawRate=0; a.brake=0.9; E.step(e,f,1/60) end
 assert(m.st[b]<K.towStraightShare,'braking zone not learnt as straight: '..m.st[b])
end
-- A-M3 : urgence tenue jusqu'à l'arrivée de chaque voiture (leader arrivé ; course chronométrée).
tests.FIXSA_URGENCY_PER_CAR_142=function()
 local function scene(timed)
  local e,f=F.scene('C',3); e.p.personalLineJitter=0; E.changed(e)
  if timed then f.timedRace=true; f.sessionLaps=0; f.sessionMinutes=10; f.left=0 else f.sessionLaps=10; f.timedRace=false end
  f.leaderLaps=timed and 5 or 10
  F.place(f,1,-4000,100); F.place(f,2,1000,200); F.place(f,3,1000-25-4.4,200)
  for k=2,3 do f.cars[k].lap=timed and 5 or 9 end
  F.tick(e,f,3)
  return e
 end
 assert(scene(false).states[2].urgency>0,'leader finished: the others still race their last lap')
 assert(scene(true).states[2].urgency>0,'timed race: last lap after the end of the time')
end
-- Mineurs AERO.
tests.FIXSA_AERO_MINORS_142=function()
 -- Résumé de la minute : compteurs de l'aspiration et de l'air sale, écrits seulement s'il y en a eu.
 local e,f=F.scene('C',3); F.tick(e,f,0.1)
 e.stats.tow=2; e.stats.tow_end=2; e.stats.dirtyAir=5
 assert(Journal.summary(e):find('aspiration cassee 2 (finies 2), air sale 5',1,true),'tow and dirty-air counters in the summary')
 assert(not Journal.summary(e):find('aspiration cassee',1,true),'nothing when there were none')
 -- Libellés des raisons (Diagnostic).
 assert(require('src/lang_en').reasons.tow and require('src/lang_en').reasons.tow_end,'EN reason labels')
 with({towChance=1},function()
  -- Jamais près de la sortie des stands (jonction apprise juste derrière).
  local _,_,nearPit=towRun(14,-0.8,212,8,function(x,fx) x.merge.spline=((1000-150)/fx.length)%1 end)
  assert(not nearPit,'no tow just after the pit exit')
  -- Jamais au premier tour de la course.
  local function firstLap(x,fx) fx.leaderLaps=0 end
  local x,fx=F.scene('C',3); x.p.personalLineJitter=0; E.changed(x)
  F.place(fx,1,-4000,100); F.place(fx,2,1000,200); F.place(fx,3,1000-14-4.4,212,-0.8); firstLap(x,fx)
  for k=1,3 do fx.cars[k].lap=0 end
  straightMap(x,fx)
  for _=1,120 do for i=2,3 do local c=fx.cars[i]; c.z=c.z+c.speed/60; c.spline=(c.z/fx.length)%1; c.lap=0 end; E.step(x,fx,1/60) end
  assert(x.states[2].reason~='tow' and (x.stats.tow or 0)==0,'no tow on the first lap')
 end)
 -- Carte réapprise à chaque session.
 local y,fy=F.scene('C',3); local m=straightMap(y,fy); fy.session=fy.session+1; F.tick(y,fy,1/60)
 assert(y.aero.seen[1]<=1,'map relearnt in a new session')
 -- Urgence : pas d'agressivité en plus avec le joueur juste devant.
 local function aggression(enabled)
  local z,fz=F.scene('C',3); z.p.personalLineJitter=0; z.profiles.C.finalLapsEnabled=enabled; E.changed(z)
  fz.sessionLaps=10; fz.leaderLaps=8; fz.timedRace=false
  F.place(fz,2,1000,200); F.place(fz,1,1000+30,200); F.place(fz,3,1000-25-4.4,200)
  for k=1,3 do fz.cars[k].lap=8 end
  F.tick(z,fz,3)
  return z.commands[2].aggression,z.states[2].urgency
 end
 local base=aggression(false); local boosted,urgency=aggression(true)
 assert(urgency>0 and math.abs(boosted-base)<1e-9,'player just ahead: no extra aggression')
end
return tests
