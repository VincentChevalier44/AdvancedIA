-- Beta 1.42, fourche STRATEGY : stratégie individuelle des arrêts, caractère des stratèges, réactions aux arrêts des
-- rivaux, arrêt obligatoire aligné, carburant du relais, tour de sortie, blocages liés à l'usure, pannes progressives.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Strategy=require('src/strategy')
local Persona=require('src/persona')
local K=C.K
local tests={}
local function logged(e,prefix)
 local n=0
 for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(prefix,1,true)==1 then n=n+1 end end
 return n
end
-- Réglages du profil (repris par la configuration suivante), puis une image pour les appliquer.
local function set(e,f,settings)
 for k,v in pairs(settings) do e.p[k]=v end
 E.changed(e); F.tick(e,f,1/60)
end
local function race(count,laps,lap,settings)
 local e,f=F.scene('C',count or 4)
 -- Beta 1.47 : seuil d'usure de la 1.42 (75 %) gardé pour ces tests (nouveau défaut : 30 %, testé à part).
 e.profiles.C.strategyTyreWearPct=75; e.run.strategyTyreWearPct=75
 f.sessionLaps=laps or 20; f.leaderLaps=lap or 2; f.timedRace=false; f.sessionMinutes=0; f.started=true
 for i=1,f.count do f.cars[i].lap=lap or 2 end
 -- Relecture 1.42 : échelle de l'usure supposée vérifiée en jeu (sa vérification est testée à part, FIXSA_WEAR_TRUST_142).
 e.strategy.wearTrust='trusted'
 if settings then set(e,f,settings) end
 return e,f
end
local function worn(a,w,fl,fr)
 a.wearKnown=true; a.tyreWear={fl or w,fr or w,w,w}; a.tyreKm={10,10,10,10}; a.tyreTemp={90,90,90,90}; a.tyreOptimum={90,90,90,90}
end
-- Plan : usure apprise par tour, arrêts jusqu'à l'arrivée, demande au bout du relais, oubliée au passage à l'emplacement.
tests.STRATEGY_142_PLAN_TYRES=function()
 local e,f=race(4,20,2)
 local a=f.cars[2]; e.states[2].persona.strategyRisk=0.5
 for lap=2,4 do a.lap=lap; worn(a,0.1*(lap-1)); F.tick(e,f,0.2) end
 local c=e.strategy.cars[2]
 assert(math.abs(c.wearRate-0.1)<1e-6,'wear rate learnt per lap: '..c.wearRate)
 assert(c.planned and c.stops==2 and c.nextLap==8,'two stops, next around lap 8: '..c.stops..' / '..c.nextLap)
 assert(logged(e,'strategie: Driver_2 plan 2 arret(s), prochain vers le tour 8 (pneus), risque 50 %')==1,'plan logged once')
 assert(#e.strategy.rows==1 and e.strategy.rows[1].kind=='soft','one Diagnostic row')
 assert(e.commands[2].stratLaps>0 and e.commands[2].stratPlanAt>0 and e.commands[2].stratPlanAt<1,'plan handed to pits.lua')
 assert(not e.commands[2].rulePit,'no stop before the end of the stint')
 for lap=5,8 do a.lap=lap; worn(a,0.1*(lap-1)); F.tick(e,f,0.2) end
 assert(c.wanted and c.cause=='tyres' and e.commands[2].rulePit,'stop requested at the end of the stint')
 assert(logged(e,'strategie: Driver_2 arret demande (pneus 70 %)')==1,'stop logged once')
 F.tick(e,f,1); assert(logged(e,'strategie: Driver_2 arret demande')==1,'no repeat')
 -- Emplacement : demande servie, oubliée ; nouveau relais appris de zéro.
 a.pit=true; a.inPitBox=true; a.kmh=0; F.tick(e,f,0.5)
 a.pit=false; a.inPitBox=false; a.kmh=100; worn(a,0); F.tick(e,f,0.2)
 assert(not c.wanted and not e.commands[2].rulePit,'request served at the box')
 -- Aucun effet hors course, en ligne, ni stratégie coupée.
 local j,fj=F.scene('P',3); fj.sessionLaps=20; fj.leaderLaps=2; set(j,fj,{strategyEnabled=true})
 for lap=2,9 do fj.cars[2].lap=lap; worn(fj.cars[2],0.1*(lap-1)); F.tick(j,fj,0.2) end
 assert(not j.commands[2].rulePit and not j.strategy.cars[2].planned,'practice: no strategy')
 local o,fo=race(3,20,2); fo.online=true
 for lap=2,9 do fo.cars[2].lap=lap; worn(fo.cars[2],0.1*(lap-1)); F.tick(o,fo,0.2) end
 assert(not o.commands[2].rulePit and not o.strategy.cars[2].planned,'online: nothing')
 -- Module seul (le moteur ne pilote pas en ligne) : rien non plus.
 for lap=2,9 do fo.cars[2].lap=lap; worn(fo.cars[2],0.1*(lap-1)); Strategy.update(o.strategy,o,fo,o.time+lap,1/60) end
 assert(not o.strategy.cars[2].planned and not o.commands[2].rulePit,'online: the module itself does nothing')
 local n,fn=race(3,20,2,{strategyEnabled=false})
 for lap=2,9 do fn.cars[2].lap=lap; worn(fn.cars[2],0.1*(lap-1)); F.tick(n,fn,0.2) end
 assert(not n.commands[2].rulePit,'switched off: nothing')
end
-- Carburant : relais limité par la réserve ; le ravitaillement de l'arrêt couvre le relais suivant (marge comprise).
tests.STRATEGY_142_FUEL=function()
 local e,f=race(3,30,5,{pitFuel='refuel'}); f.fuelRate=1
 local a=f.cars[2]; e.states[2].persona.strategyRisk=0.5
 a.fuel=4; a.maxFuel=60; a.fuelPerLap=3
 -- Carburant lu après le premier plan : nouvel essai au plus tard K.strategyRetry s après.
 F.tick(e,f,K.strategyRetry+0.2)
 local c=e.strategy.cars[2]
 -- 25 tours à faire, relais de 18 tours au plus avec un plein : arrêt maintenant, puis un second.
 assert(c.planned and c.limit=='fuel' and c.stops==2,'fuel-limited plan: '..c.stops)
 assert(c.wanted and c.cause=='fuel' and e.commands[2].rulePit,'fuel stop requested')
 local cmd=e.commands[2]
 assert(cmd.stratLaps==13,'next stint: half of the 25 laps left: '..cmd.stratLaps)
 local expected=math.min(60,(13+1)*3*K.fuelMargin+3*K.fuelReserveLaps)
 assert(math.abs(cmd.fuelTarget-expected)<1e-6,'refuel for the next stint and its margin: '..cmd.fuelTarget..' / '..expected)
end
-- Caractère : tiré de la graine, stable, dispersé autour de la prise de risque réglée ; seuil d'usure et marge suivent.
tests.STRATEGY_142_TEMPERAMENT=function()
 local p=C.defaults('C'); p.strategyRiskPct=50; p.strategySpreadPct=60
 local seen,lo,hi={},1,0
 for i=1,40 do
  local out=Persona.fill({},1234,i,'C',p,0); local again=Persona.fill({},1234,i,'C',p,0)
  assert(out.strategyRisk==again.strategyRisk,'reproducible')
  assert(out.strategyRisk>=0.2-1e-9 and out.strategyRisk<=0.8+1e-9,'within the spread')
  lo=math.min(lo,out.strategyRisk); hi=math.max(hi,out.strategyRisk); seen[#seen+1]=out.strategyRisk
 end
 assert(hi-lo>0.3,'strategists differ')
 p.strategySpreadPct=0; assert(Persona.fill({},1234,7,'C',p,0).strategyRisk==0.5,'no spread: the average')
 -- Audacieux : relais plus long que le prudent, mêmes pneus.
 local function stopLap(risk)
  local e,f=race(3,30,2); local a=f.cars[2]; e.states[2].persona.strategyRisk=risk
  for lap=2,4 do a.lap=lap; worn(a,0.08*(lap-1)); F.tick(e,f,0.2) end
  return e.strategy.cars[2].nextLap
 end
 assert(stopLap(1)>stopLap(0),'bold strategist stays out longer')
end
-- Rivaux : arrêt du rival derrière (couverture d'un prudent), du rival devant (overcut), undercut d'un audacieux.
tests.STRATEGY_142_RIVALS=function()
 local e,f=race(4,30,10)
 F.place(f,2,0,150); F.place(f,3,-60,150); f.cars[2].lap=10; f.cars[3].lap=9
 local a=f.cars[2]; worn(a,0.3); e.states[2].persona.strategyRisk=0.3
 local c=e.strategy.cars[2]; c.lap=10; c.lapWear=0.3; c.wearRate=0.1; c.wearLaps=3; c.planned=true; c.stops=1; c.nextLap=12
 e.states[2].nextPerception=0; e.states[3].nextPerception=0; F.tick(e,f,0.2)
 f.cars[3].pit=true; F.tick(e,f,0.2)
 assert(c.wanted and c.cause=='cover','covering the undercut of the car behind')
 assert(logged(e,'strategie: Driver_2 arret demande (couverture d un undercut)')==1)
 -- Overcut : rival devant aux stands, pneus encore bons : deux tours de plus.
 local o,fo=race(4,30,10)
 F.place(fo,2,0,150); F.place(fo,3,60,150); fo.cars[2].lap=10; fo.cars[3].lap=10
 worn(fo.cars[2],0.3); o.states[2].persona.strategyRisk=0.5
 local co=o.strategy.cars[2]; co.lap=10; co.lapWear=0.3; co.wearRate=0.1; co.wearLaps=3; co.planned=true; co.stops=1; co.nextLap=14
 o.states[2].nextPerception=0; o.states[3].nextPerception=0; F.tick(o,fo,0.2)
 fo.cars[3].pit=true; F.tick(o,fo,0.2)
 assert(co.shift==K.strategyOvercutLaps and co.reaction and not co.wanted,'overcut: stays out')
 -- Undercut : audacieux, arrêt dans trois tours, collé au rival devant : il s'arrête le premier.
 local u,fu=race(4,30,10)
 F.place(fu,2,0,150); F.place(fu,3,50,150); fu.cars[2].lap=10; fu.cars[3].lap=10
 worn(fu.cars[2],0.5); u.states[2].persona.strategyRisk=0.8
 local cu=u.strategy.cars[2]; cu.lap=9; cu.lapWear=0.4; cu.wearRate=0.1; cu.wearLaps=3
 u.states[2].nextPerception=0; F.tick(u,fu,0.2)
 assert(cu.wanted and cu.cause=='undercut' and u.commands[2].rulePit,'undercut on the car ahead')
 -- Option coupée : aucune réaction.
 local n,fn=race(4,30,10,{strategyUndercut=false})
 F.place(fn,2,0,150); F.place(fn,3,50,150); fn.cars[2].lap=10; fn.cars[3].lap=10
 worn(fn.cars[2],0.5); n.states[2].persona.strategyRisk=0.8
 local cn=n.strategy.cars[2]; cn.lap=9; cn.lapWear=0.4; cn.wearRate=0.1; cn.wearLaps=3
 F.tick(n,fn,0.2); assert(not cn.wanted,'undercut off: no reaction')
end
-- Arrêt obligatoire aligné sur l'arrêt prévu par le stratège, s'il tombe plus tard dans la fenêtre.
tests.STRATEGY_142_MANDATORY_ALIGNED=function()
 local function scene(strategy)
  local e,f=race(3,20,16,{mandatoryStops=1,pitWindowOpenPct=10,pitWindowClosePct=100,strategyEnabled=strategy})
  local a=f.cars[2]; e.states[2].persona.strategyRisk=0.5
  local c=e.strategy.cars[2]; c.lap=15; c.lapWear=0.3; c.wearRate=0.15; c.wearLaps=3
  -- Plan fait avant l'ouverture de la fenêtre (leader au premier tour), puis fenêtre ouverte.
  f.leaderLaps=1; a.lap=16; worn(a,0.45); F.tick(e,f,0.2)
  f.leaderLaps=16; F.tick(e,f,0.5)
  return e,f,c
 end
 local off=scene(false); assert(off.commands[2].rulePit,'precondition: mandatory stop called by the rules')
 local e,_,c=scene(true)
 -- Lot 5 (N7) : plan limité par les pneus : avancé de 0 à K.planSpreadLaps tours selon la voiture, jamais avant le tour suivant.
 local at=math.max(17,18-(2%(K.planSpreadLaps+1)))
 assert(c.planned and c.nextLap==18 and math.abs(e.commands[2].stratPlanAt-at/20)<1e-9,'planned around lap 18, brought forward for this car: '..tostring(e.commands[2].stratPlanAt))
 assert(not e.commands[2].rulePit,'mandatory stop waits for the planned stop')
end
-- Tour de sortie : après un vrai passage à l'emplacement, niveau abaissé jusqu'à la ligne, puis rendu en douceur ;
-- jamais après un passage sans arrêt ni au départ d'une course depuis la voie des stands.
tests.STRATEGY_142_OUT_LAP=function()
 local e,f=F.scene('P',3); local a=f.cars[2]; local cmd=e.commands[2]
 F.tick(e,f,K.outLapSummaryTime+1)
 a.pit=true; a.inPitBox=true; a.kmh=0; F.tick(e,f,1)
 a.inPitBox=false; a.kmh=60; F.tick(e,f,0.5)
 a.pit=false; a.kmh=120; F.tick(e,f,0.5)
 assert(math.abs(cmd.levelScale-(1-e.run.outLapLevelPct/100))<1e-9,'level lowered on the out-lap: '..cmd.levelScale)
 assert(logged(e,'tour de sortie: Driver_2 pneus a chauffer (niveau -7 %)')==1,'logged once')
 F.tick(e,f,30); assert(cmd.levelScale<1,'still warming up before the line')
 a.lap=a.lap+1; F.tick(e,f,4); assert(cmd.levelScale>1-e.run.outLapLevelPct/100 and cmd.levelScale<1,'given back progressively')
 F.tick(e,f,5); assert(cmd.levelScale==1,'given back')
 -- Pneus à température : fin du tour de sortie avant la ligne.
 a.pit=true; a.inPitBox=true; a.kmh=0; F.tick(e,f,1); a.inPitBox=false; a.pit=false; a.kmh=120
 a.wearKnown=true; a.tyreTemp={50,50,50,50}; a.tyreOptimum={90,90,90,90}; a.tyreWear={0,0,0,0}; a.tyreKm={0,0,0,0}
 F.tick(e,f,2); assert(cmd.levelScale<1,'cold tyres')
 a.tyreTemp={88,88,88,88}; F.tick(e,f,9); assert(cmd.levelScale==1,'warm tyres: given back')
 -- Passage sans arrêt (drive-through) : rien.
 a.pit=true; a.kmh=0; F.tick(e,f,2); a.kmh=60; F.tick(e,f,0.5); a.pit=false; a.kmh=120; F.tick(e,f,0.5)
 assert(cmd.levelScale==1,'stopped in the lane but not at the box: no out-lap')
 -- Course : sortie de la voie des stands au départ, rien ; après un arrêt en course, oui.
 local r,fr=race(3,20,0); fr.started=false; local b=fr.cars[2]
 b.pit=true; b.inPitBox=true; b.kmh=0; F.tick(r,fr,1); fr.started=true; b.inPitBox=false; b.pit=false; b.kmh=100; F.tick(r,fr,0.5)
 assert(r.commands[2].levelScale==1,'race start from the pit lane: no out-lap')
 -- Option coupée.
 local n,fn=F.scene('P',3); set(n,fn,{outLapEnabled=false}); local d=fn.cars[2]
 d.pit=true; d.inPitBox=true; d.kmh=0; F.tick(n,fn,1); d.inPitBox=false; d.pit=false; d.kmh=120; F.tick(n,fn,0.5)
 assert(n.commands[2].levelScale==1,'option off')
end
-- Départs des stands de la première minute (essais) : une seule ligne de journal.
tests.STRATEGY_142_OUT_LAP_SUMMARY=function()
 local e,f=F.scene('Q',6)
 for i=2,6 do local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0 end
 F.tick(e,f,1)
 for i=2,6 do local a=f.cars[i]; a.pit=false; a.inPitBox=false; a.kmh=120 end
 F.tick(e,f,K.outLapSummaryTime+1)
 assert(logged(e,'tour de sortie: Driver_')==0,'no line per car at the session start')
 assert(logged(e,'tour de sortie: 5 IA pneus a chauffer au depart des stands (niveau -7 %)')==1,'one summary line')
end
-- Blocages et usure : fréquence plus forte avec des pneus avant usés et asymétriques ; un blocage use le pneu avant le
-- plus usé, borné par relais ; option coupée : aucune usure ajoutée.
tests.STRATEGY_142_LOCK_WEAR=function()
 local function run(fl,fr,enabled,seconds,flat)
  local e,f=race(3,30,5,{mistakesEnabled=true,mistakeRate=600,lockWearEnabled=enabled,lockFlatSpotKm=flat or 1})
  local a=f.cars[2]; worn(a,0.5,fl,fr); a.brake=1; a.gas=0; a.kmh=180; a.speed=50
  local events,wheel,km=0,-1,0; local last=0
  for _=1,math.floor((seconds or 120)*10) do
   F.tick(e,f,0.1)
   local cmd=e.commands[2]
   if (cmd.wearId or 0)~=last then last=cmd.wearId; events=events+1; wheel=cmd.wearWheel; km=km+cmd.wearKm end
  end
  return e,events,wheel,km
 end
 local e,events,wheel,km=run(0.9,0.6,true,400)
 assert(events>=1 and wheel==0,'front-left (more worn) gets the flat spot')
 assert(km<=K.lockWearMaxKm+1e-9 and e.mistakes.cars[2].lockKm<=K.lockWearMaxKm+1e-9,'bounded per stint')
 local big,bigEvents,_,bigKm=run(0.9,0.6,true,900,4)
 assert(bigEvents>=4 and bigKm<=K.lockWearMaxKm+1e-9 and big.mistakes.cars[2].lockKm<=K.lockWearMaxKm+1e-9,'large flat spots: still bounded ('..bigKm..' km, '..bigEvents..' events)')
 assert(logged(e,'usure: Driver_2 blocage, pneu avant gauche +1.0 km (usure 90 %, asymetrie 33 %)')>=1,'wear logged')
 assert(logged(e,'erreur de pilotage: blocage des roues au freinage')>=1)
 local _,off=run(0.9,0.6,false,400); assert(off==0,'option off: no wear added')
 -- Fréquence : même graine, pneus usés et asymétriques contre pneus neufs.
 local function mistakes(fl,fr)
  local x,fx=race(3,30,5,{mistakesEnabled=true,mistakeRate=30,lockWearEnabled=true,lockFlatSpotKm=0})
  local a=fx.cars[2]; worn(a,0.2,fl,fr); a.brake=1; a.gas=0; a.kmh=180; a.speed=50
  F.tick(x,fx,900,false)
  return logged(x,'erreur de pilotage:')
 end
 assert(mistakes(0.95,0.5)>mistakes(0,0),'worn and asymmetric tyres lock more often')
end
-- Pannes : jamais au premier tour ni en fin de course, perte montée en douceur et bornée, arrêt demandé, réparée à
-- l'emplacement ; stands fermés : la demande attend ; jamais hors course ; une seule panne par IA.
tests.STRATEGY_142_FAILURE=function()
 local e,f=race(3,50,10,{failureRate=3600*100,failureLossPct=20})
 local a=f.cars[2]; local cmd=e.commands[2]; local c=e.strategy.cars[2]
 F.tick(e,f,12)
 assert(c.failState==1,'failure started')
 assert(logged(e,'panne: Driver_2')==1,'logged once')
 assert(#e.strategy.rows>=1 and e.strategy.rows[1].kind=='warn','Diagnostic row')
 local early=cmd.levelScale
 assert(early<1 and early>1-c.failLoss*0.5,'pace loss starting progressively: '..early)
 F.tick(e,f,c.failRamp)
 assert(math.abs(cmd.levelScale-(1-c.failLoss))<1e-6,'full loss reached: '..cmd.levelScale)
 assert(c.failLoss<=0.2+1e-9 and c.failLoss>=0.1-1e-9,'bounded by the setting')
 assert(cmd.throttleLimit>=K.failureThrottleMin-1e-9 and cmd.throttleLimit<1,'throttle limited, never below 0.8')
 assert(cmd.rulePit and c.wanted and c.cause=='failure','heading to the pits')
 -- Stands fermés : demande retenue.
 local inc=e.incidents; inc.pitsClosed=true; cmd.rulePit=false; Strategy.update(e.strategy,e,f,e.time,1/60)
 assert(not cmd.rulePit,'pits closed: waits'); inc.pitsClosed=false
 Strategy.update(e.strategy,e,f,e.time,1/60); assert(cmd.rulePit,'pits open again')
 -- Emplacement : retenue le temps de la réparation, puis rythme rendu.
 a.pit=true; a.inPitBox=true; a.kmh=0; F.tick(e,f,1)
 assert(cmd.pitHold,'held for the repair')
 F.tick(e,f,c.failRepair)
 assert(c.failState==2 and cmd.levelScale==1 and cmd.throttleLimit==1,'repaired: pace given back')
 assert(logged(e,'panne: Driver_2 reparee aux stands')==1)
 a.pit=false; a.inPitBox=false; a.kmh=100; F.tick(e,f,60)
 assert(c.failState==2 and logged(e,'panne: Driver_2')==2,'one failure per AI')
 -- Fin de course, premier tour, journée circuit, option coupée : jamais.
 local late,fl=race(3,50,46,{failureRate=3600*100}); F.tick(late,fl,30); assert(late.strategy.cars[2].failState==0,'last 10 %: never')
 local first,ff=race(3,50,0,{failureRate=3600*100}); F.tick(first,ff,30); assert(first.strategy.cars[2].failState==0,'first lap: never')
 local j,fj=F.scene('J',3); fj.sessionLaps=50; fj.leaderLaps=10; set(j,fj,{failureRate=3600*100,failuresEnabled=true}); F.tick(j,fj,30); assert(j.strategy.cars[2].failState==0,'track day: never')
 local n,fn=race(3,50,10,{failureRate=3600*100,failuresEnabled=false}); F.tick(n,fn,30); assert(n.strategy.cars[2].failState==0,'option off')
end
-- Reprise de l'app : une panne faite ou en cours n'est jamais retirée pour la même IA ; changement de session : tout oublié.
tests.STRATEGY_142_CHECKPOINT=function()
 local e,f=race(3,50,10,{failureRate=3600*100})
 F.tick(e,f,12); assert(e.strategy.cars[2].failState==1)
 local text=Strategy.serialize(e.strategy,f.session)
 assert(text:find('\ncar_2,1',1,true),'failure kept: '..text)
 local r,fr=race(3,50,10,{failureRate=3600*100})
 Strategy.restore(r.strategy,text,fr.session)
 r.strategy.cars[2].identity=''; F.tick(r,fr,30)
 assert(r.strategy.cars[2].failState==2,'restored: no second failure')
 local before=r.strategy.restoredSession
 Strategy.restore(r.strategy,text,fr.session+1); assert(r.strategy.restoredSession==before,'another session: ignored')
 Strategy.reset(e.strategy,e.time)
 assert(#e.strategy.rows==0 and e.strategy.cars[2].failState==0 and e.strategy.cars[2].identity=='','session change: forgotten')
end
return tests
