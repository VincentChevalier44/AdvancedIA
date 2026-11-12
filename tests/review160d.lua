-- Beta 1.60, tranche D : tests de la tranche (noms terminés par _160D). Chargé par tests/extended.lua.
-- Rythme selon l'usure, la gomme et le carburant (src/wear.lua, réglage wearPace) ; stratégie avancée (src/pitloss.lua,
-- src/strategy.lua, réglage strategySmart) ; conseil de stratégie de SpotterEnginer lu pour l'affichage et le journal.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local J=require('src/journal')
local Strategy=require('src/strategy')
local Pitloss=require('src/pitloss')
local Wear=require('src/wear')
local Panel=require('src/panel')
local K=C.K
local tests={}
local function logged(e,text)
 local n=0
 for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end
 return n
end
local function near(a,b,eps) return math.abs(a-b)<=(eps or 1e-9) end
local function set(e,f,settings)
 for k,v in pairs(settings) do e.p[k]=v end
 E.changed(e); F.tick(e,f,1/60)
end
local function race(count,laps,lap,settings)
 local e,f=F.scene('C',count or 4)
 e.profiles.C.strategyTyreWearPct=75; e.run.strategyTyreWearPct=75
 f.sessionLaps=laps or 20; f.leaderLaps=lap or 2; f.timedRace=false; f.sessionMinutes=0; f.started=true
 for i=1,f.count do f.cars[i].lap=lap or 2 end
 e.strategy.wearTrust='trusted'
 if settings then set(e,f,settings) end
 return e,f
end
local function worn(a,w)
 a.wearKnown=true; a.tyreWear={w,w,w,w}; a.tyreKm={10,10,10,10}; a.tyreTemp={90,90,90,90}; a.tyreOptimum={90,90,90,90}
end
local smartOn={strategyEnabled=true,strategySmart=true}
-- Temps perdu connu sans passer par les stands : voie 30 s pour 20 % du tour, tours de 100 s.
local function known(e,f,lane,frac,lapTime)
 local t=e.pitloss; t.laneTime=lane or 30; t.frac=frac or 0.2; t.samples=1; t.known=true
 for i=1,f.count do e.pits.cars[i].lapTime=lapTime or 100 end
end
local function strat(e,f) Strategy.update(e.strategy,e,f,e.time,1/60) end
-- Un passage par la voie des stands vu par Pitloss.update (appels directs, horloge fournie).
local function lane(e,f,i,seconds,opts)
 opts=opts or {}
 local t=e.pitloss; local a=f.cars[i]; local now=opts.from or 1000
 a.pit=false; a.spline=0.88; Pitloss.update(t,e,f,now)
 a.pit=true; a.spline=0.9; Pitloss.update(t,e,f,now+1)
 if opts.during then opts.during(a) end
 if not opts.noBox then a.inPitBox=true; a.kmh=0 end
 Pitloss.update(t,e,f,now+2)
 a.inPitBox=false; a.kmh=60; a.pit=false; a.spline=opts.exit or 0.05
 Pitloss.update(t,e,f,now+1+seconds)
 if opts.after then opts.after(a) end
end

-- Temps perdu appris : entrée et sortie de la voie, formule, journal une fois ; dépannage, drapeau rouge, passage sans
-- arrêt à l'emplacement et temps hors bornes rejetés.
tests.PITLOSS_LEARN_160D=function()
 local e,f=race(4,20,2,smartOn)
 for i=1,f.count do e.pits.cars[i].lapTime=100 end
 lane(e,f,3,30)
 local t=e.pitloss
 assert(t.known and t.samples==1 and near(t.laneTime,30) and near(t.frac,0.15,1e-9),'lane 30 s over 15 % of the lap: '..t.laneTime..' / '..t.frac)
 assert(near(Pitloss.loss(t,100),15),'loss = lane - frac x lap: '..Pitloss.loss(t,100))
 assert(logged(e,'stands: temps perdu appris 15.0 s (voie 30.0 s, 1 passage(s))')==1,'learnt loss logged once')
 -- Second passage : moyenne glissante.
 lane(e,f,3,40,{from=2000})
 assert(t.samples==2 and near(t.laneTime,30+10*K.pitLossAlpha),'moving average: '..t.laneTime)
 assert(logged(e,'stands: temps perdu appris')==2,'logged again after a change above the step')
 -- Rejets.
 local n=t.samples
 lane(e,f,3,30,{from=3000,during=function(a) a.teleport=true end,after=function(a) a.teleport=false end}); assert(t.samples==n,'towed or moved car: no sample')
 f.cars[3].teleport=false
 e.incidents.red=true; lane(e,f,3,30,{from=4000}); e.incidents.red=false; assert(t.samples==n,'red flag: no sample')
 lane(e,f,3,30,{from=5000,noBox=true}); assert(t.samples==n,'no stop at the box (penalty pass): no sample')
 lane(e,f,3,K.pitLossMax+10,{from=6000}); assert(t.samples==n,'lane time out of bounds: no sample')
 lane(e,f,3,K.pitLossMin-3,{from=7000}); assert(t.samples==n,'lane time too short: no sample')
 -- Voiture déjà dans la voie à la première image : jamais chronométrée.
 local e2,f2=race(4,20,2,smartOn)
 f2.cars[3].pit=true; Pitloss.update(e2.pitloss,e2,f2,1000); f2.cars[3].inPitBox=true; f2.cars[3].kmh=0; Pitloss.update(e2.pitloss,e2,f2,1001)
 f2.cars[3].pit=false; f2.cars[3].inPitBox=false; Pitloss.update(e2.pitloss,e2,f2,1030)
 assert(e2.pitloss.samples==0,'entry never seen: no sample')
 -- Avant le premier échantillon : inconnu.
 assert(Pitloss.loss(e2.pitloss,100)==-1 and Pitloss.rejoin(e2.pitloss,e2,f2,2)==nil,'unknown before the first sample')
end
-- Sous neutralisation, la même formule donne une perte plus faible.
tests.PITLOSS_NEUTRAL_SMALLER_160D=function()
 local e,f=race(4,20,2,smartOn); known(e,f,30,0.2,100)
 local t=e.pitloss
 local slow=Pitloss.neutralLapTime(t,e,100)
 assert(near(slow,100*(1+e.run.fcyDeltaPct/100)),'neutral lap from the FCY reference: '..slow)
 t.neutralLap=160
 assert(Pitloss.neutralLapTime(t,e,100)==160,'learnt neutral lap preferred')
 assert(near(Pitloss.loss(t,100),10) and near(Pitloss.loss(t,160),0),'smaller loss under neutralisation (never negative)')
 t.neutralLap=140
 assert(near(Pitloss.neutralSaving(t,e,100),8),'saving = green loss - neutral loss: '..Pitloss.neutralSaving(t,e,100))
 t.known=false; assert(Pitloss.neutralSaving(t,e,100)==-1,'unknown loss: unknown saving')
end
-- Écart en temps : avancement × temps au tour de la voiture de derrière.
tests.GAP_TIME_160D=function()
 local e,f=race(4,20,5,smartOn)
 F.place(f,2,0,150); F.place(f,3,200,150); f.cars[2].lap=5; f.cars[3].lap=5
 assert(Pitloss.gap(e,f,2,3)==nil,'lap time unknown: no time gap')
 e.pits.cars[2].lapTime=100; e.pits.cars[3].lapTime=90
 assert(near(Pitloss.gap(e,f,2,3),2,1e-9),'3 is 2 % of a lap ahead of 2: 2 s at the follower pace: '..Pitloss.gap(e,f,2,3))
 assert(near(Pitloss.gap(e,f,3,2),-0.02*100,1e-9),'signed, same follower lap time')
 f.cars[3].lap=6; assert(near(Pitloss.gap(e,f,2,3),102,1e-9),'laps counted')
end
-- Arrêt dû, voiture plus lente juste devant le point de sortie : retardé d'un tour, puis demandé ; jamais au-delà de la
-- limite dure (pneus ou carburant qui ne tiennent pas deux tours).
local function stint(e,f,i,first,last)
 local a=f.cars[i]
 for lap=first,last do a.lap=lap; worn(a,0.1*(lap-1)); F.tick(e,f,0.2) end
end
tests.REJOIN_DELAY_160D=function()
 local e,f=race(5,20,2,smartOn); known(e,f,30,0.1,100)
 e.states[2].persona.strategyRisk=0.5
 -- Voiture 2 à 0 : point de sortie 20 s derrière (0,8) ; voiture 4 plus lente 2 s devant ce point.
 F.place(f,4,8200,100); f.cars[4].lap=2; e.pits.cars[4].lapTime=103
 stint(e,f,2,2,8)
 local c=e.strategy.cars[2]
 assert(not c.wanted and c.rejoinDelay==1,'stop due but traffic at the exit: delayed one lap')
 assert(logged(e,'strategie: Driver_2 arret retarde d un tour (trafic a la sortie : Driver_4 a 2.0 s)')==1,'delay logged once')
 F.tick(e,f,1); assert(not c.wanted and logged(e,'arret retarde')==1,'held for the whole lap, no repeat')
 stint(e,f,2,9,9)
 assert(c.wanted and c.cause=='tyres','next lap: the hard limit is near, stop requested')
 -- Réglage coupé : demandé au premier tour dû.
 local o,fo=race(5,20,2,{strategyEnabled=true}); known(o,fo,30,0.1,100)
 o.states[2].persona.strategyRisk=0.5
 F.place(fo,4,8200,100); fo.cars[4].lap=2; o.pits.cars[4].lapTime=103
 stint(o,fo,2,2,8)
 assert(o.strategy.cars[2].wanted and logged(o,'arret retarde')==0,'switch off: no delay')
 -- Sortie libre : aucun retard.
 local q,fq=race(5,20,2,smartOn); known(q,fq,30,0.1,100); q.states[2].persona.strategyRisk=0.5
 stint(q,fq,2,2,8)
 assert(q.strategy.cars[2].wanted and logged(q,'arret retarde')==0,'clean air: stop as planned')
 -- File de K.rejoinTrain voitures dans K.rejoinTrainSpan s, même aussi rapides.
 local r,fr=race(6,20,2,smartOn); known(r,fr,30,0.1,100); r.states[2].persona.strategyRisk=0.5
 F.place(fr,4,8100,100); F.place(fr,5,8300,100); F.place(fr,6,8500,100); for i=4,6 do fr.cars[i].lap=2 end
 stint(r,fr,2,2,8)
 assert(not r.strategy.cars[2].wanted and logged(r,'trafic a la sortie : une file a')==1,'train at the exit: delayed')
end
tests.REJOIN_NEVER_PAST_HARD_LIMIT_160D=function()
 local e,f=race(5,20,2,smartOn); known(e,f,30,0.1,100)
 e.states[2].persona.strategyRisk=0.5
 F.place(f,4,8200,100); f.cars[4].lap=2; e.pits.cars[4].lapTime=103
 -- Usure de 20 % par tour : au tour dû, il reste moins de deux tours avant l'usure maximale.
 local a=f.cars[2]
 for lap=2,4 do a.lap=lap; worn(a,0.2*(lap-1)); F.tick(e,f,0.2) end
 local c=e.strategy.cars[2]
 assert(c.wanted and c.rejoinDelay==0 and c.room<2,'no room to stretch: never delayed (room '..c.room..')')
 assert(logged(e,'arret retarde')==0)
 -- Au plus K.rejoinDelayMax retards par relais.
 local m,fm=race(5,60,2,smartOn); known(m,fm,30,0.1,100); m.states[2].persona.strategyRisk=0.5
 F.place(fm,4,8200,100); fm.cars[4].lap=2; m.pits.cars[4].lapTime=103
 local b=fm.cars[2]
 for lap=2,40 do b.lap=lap; worn(b,0.05*(lap-1)); F.tick(m,fm,0.2); if m.strategy.cars[2].wanted then break end end
 assert(m.strategy.cars[2].wanted and m.strategy.cars[2].rejoinDelay==K.rejoinDelayMax,'at most rejoinDelayMax delays: '..m.strategy.cars[2].rejoinDelay)
 assert(logged(m,'arret retarde')>=1)
end
-- Arrêt dû au tour suivant, sortie libre et une voiture juste derrière le point de sortie : pris maintenant.
tests.REJOIN_ADVANCE_160D=function()
 local function scene(settings,behind)
  local e,f=race(5,20,2,settings); known(e,f,30,0.1,100)
  e.states[2].persona.strategyRisk=0.5
  if behind then F.place(f,4,7800,100); f.cars[4].lap=2 end
  stint(e,f,2,2,7)
  return e,e.strategy.cars[2]
 end
 local e,c=scene(smartOn,true)
 assert(c.nextLap==8 and c.wanted and c.cause=='tyres','stop brought forward by one lap (next '..c.nextLap..')')
 assert(logged(e,'strategie: Driver_2 arret avance (piste libre a la sortie)')==1)
 local _,c2=scene(smartOn,false); assert(not c2.wanted,'nobody behind the exit point: stop as planned')
 local _,c3=scene({strategyEnabled=true},true); assert(not c3.wanted,'switch off: stop as planned')
end
-- Neutralisation : arrêt peu coûteux (pneus assez usés, gain suffisant), stands ouverts.
local function scScene(risk,wear,nextLap)
 local e,f=race(5,30,10,smartOn); known(e,f,30,0.2,100); e.pitloss.neutralLap=160
 for i=2,5 do F.place(f,i,(i-2)*1000,100); f.cars[i].lap=10 end
 local a=f.cars[2]; worn(a,wear); e.states[2].persona.strategyRisk=risk
 local c=e.strategy.cars[2]; c.lap=10; c.lapWear=wear; c.wearRate=0.02; c.wearLaps=3; c.planned=true; c.stops=1; c.nextLap=nextLap; c.limit='tyres'
 F.tick(e,f,1/60)
 c.planned=true; c.stops=1; c.nextLap=nextLap; c.limit='tyres'
 return e,f,c
end
tests.SC_CHEAP_STOP_160D=function()
 local e,f,c=scScene(0.3,0.5,20)
 strat(e,f); assert(not c.wanted,'green: no stop')
 e.incidents.neutral=true; strat(e,f)
 assert(c.wanted and c.cause=='neutral','cheap stop under neutralisation')
 assert(logged(e,'strategie: Driver_2 arret sous neutralisation (gain 10 s)')==1,'saving logged')
 -- Pneus trop neufs : pas d'arrêt.
 local n,fn,cn=scScene(0.3,0.2,20); n.incidents.neutral=true; strat(n,fn); assert(not cn.wanted,'fresh tyres: no cheap stop')
 -- Gain insuffisant : pas d'arrêt.
 local g,fg,cg=scScene(0.3,0.5,20); g.pitloss.neutralLap=110; g.incidents.neutral=true; strat(g,fg); assert(not cg.wanted,'saving under the threshold: no stop')
 -- Temps perdu inconnu : règle d'avant (arrêt loin : rien).
 local u,fu,cu=scScene(0.3,0.5,20); u.pitloss.known=false; u.incidents.neutral=true; strat(u,fu); assert(not cu.wanted,'unknown loss: today rule')
 -- Réglage coupé : règle d'avant.
 local o,fo,co=scScene(0.3,0.5,20); o.run.strategySmart=false; o.incidents.neutral=true; strat(o,fo); assert(not co.wanted,'switch off: today rule')
end
-- Audacieux dont l'arrêt est loin : reste en piste quand la moitié des voitures devant lui s'arrêtent.
tests.SC_STAY_OUT_160D=function()
 local e,f,c=scScene(0.9,0.5,20)
 e.incidents.neutral=true; strat(e,f)
 assert(not c.wanted and c.scCand,'bold strategist: waits for the others')
 f.cars[3].pit=true; f.cars[4].pit=true
 e.time=e.time+K.scDecideDelay+0.1; strat(e,f)
 assert(not c.wanted and not c.scCand,'two of three cars ahead stop: stays out')
 assert(logged(e,'strategie: Driver_2 reste en piste sous neutralisation (position en piste)')==1)
 -- Personne ne s'arrête devant : il prend l'arrêt peu coûteux.
 local n,fn,cn=scScene(0.9,0.5,20)
 n.incidents.neutral=true; strat(n,fn); n.time=n.time+K.scDecideDelay+0.1; strat(n,fn)
 assert(cn.wanted and cn.cause=='neutral','nobody stops ahead: cheap stop')
 -- Arrêt proche : la règle d'avant le prend dès le début.
 local d,fd,cd=scScene(0.9,0.5,12); d.incidents.neutral=true; strat(d,fd); assert(cd.wanted and cd.cause=='neutral','stop due soon: taken at once')
end
-- Stands fermés par les règles : l'arrêt attend leur ouverture, pendant la même neutralisation.
tests.SC_PITS_CLOSED_160D=function()
 local e,f,c=scScene(0.3,0.5,20)
 e.incidents.neutral=true; e.incidents.pitsClosed=true; strat(e,f)
 assert(not c.wanted and c.scCand,'pits closed: no call')
 e.incidents.pitsClosed=false; strat(e,f)
 assert(c.wanted and c.cause=='neutral','pits open: cheap stop')
 -- Neutralisation finie avant l'ouverture : oublié.
 local n,fn,cn=scScene(0.3,0.5,20)
 n.incidents.neutral=true; n.incidents.pitsClosed=true; strat(n,fn); n.incidents.neutral=false; n.incidents.pitsClosed=false; strat(n,fn)
 assert(not cn.wanted and not cn.scCand,'neutralisation over: forgotten')
end
-- Rival proche jugé en temps ; undercut avec gain estimé (usure qui agit sur le rythme) et sortie libre.
tests.UNDERCUT_GAIN_160D=function()
 local function scene(settings,gapM,wear,lapTime)
  local e,f=race(4,30,10,settings); known(e,f,30,0.1,lapTime or 100)
  F.place(f,2,0,150); F.place(f,3,gapM,150); f.cars[2].lap=10; f.cars[3].lap=10
  worn(f.cars[2],wear or 0.5); e.states[2].persona.strategyRisk=0.8
  -- Plus d'une seconde d'abord : la perte due à l'usure (revue une fois par seconde, après la stratégie) est connue
  -- avant la décision.
  F.tick(e,f,1.1)
  local c=e.strategy.cars[2]; c.lap=9; c.lapWear=(wear or 0.5)-0.1; c.wearRate=0.1; c.wearLaps=3
  e.states[2].nextPerception=0; F.tick(e,f,0.2)
  return e,c
 end
 -- 50 m à 150 km/h : 1,2 s en mètres (règle d'avant : proche) mais 0,5 % du tour = 0,5 s en temps.
 local e,c=scene(smartOn,50); assert(c.wanted and c.cause=='undercut','0.5 s behind: undercut')
 -- 120 m : proche en mètres (moins de K.strategyRivalGap s à cette vitesse ?), mais 1,2 % du tour = 1,2 s : proche aussi.
 local _,c2=scene(smartOn,200); assert(not c2.wanted,'2 s behind in time: too far for an undercut')
 -- Tour de 400 s : 50 m valent 2 s (trop loin en temps), alors que la règle en mètres les dit proches.
 local _,c4=scene(smartOn,50,nil,400); assert(not c4.wanted,'judged in time, not in metres')
 local _,c5=scene({strategyEnabled=true},50,nil,400); assert(c5.wanted and c5.cause=='undercut','switch off: metres rule as before')
 -- Usure qui agit : gain estimé dans le journal ; gain négatif (pneus encore bons, tour de sortie cher) : pas d'undercut.
 local both={strategyEnabled=true,strategySmart=true,wearPace=true,outLapEnabled=true,outLapLevelPct=3}
 local g,cg=scene(both,50,0.9)
 assert(cg.wanted and cg.cause=='undercut','worn tyres: positive gain, undercut: '..tostring(cg.wanted)..' '..cg.cause..' loss '..Wear.lossOf(g.wear,2)..' planned '..tostring(cg.planned)..' stops '..cg.stops..' next '..cg.nextLap)
 assert(logged(g,'strategie: Driver_2 undercut sur Driver_3 (ecart 0.5 s, gain estime')==1,'gap and gain logged')
 local n,cn=scene(both,50,0.5)
 assert(cn.planned and cn.nextLap-10<=K.strategyUndercutLaps,'stop close enough for an undercut: next '..cn.nextLap)
 assert(Wear.lossOf(n.wear,2)>0 and not cn.wanted,'small wear loss against the out-lap: no undercut')
 assert(e~=nil)
end
-- Tour de formation (état publié « form », tranche E) : usure par tour non apprise sur ce tour.
tests.WEAR_RATE_SKIPS_FORMATION_160D=function()
 local e,f=race(4,20,2)
 local a=f.cars[2]; local c=e.strategy.cars[2]
 a.lap=2; worn(a,0.10); F.tick(e,f,0.2)
 a.lap=3; worn(a,0.20); F.tick(e,f,0.2)
 assert(near(c.wearRate,0.1,1e-9) and c.wearLaps==1)
 c.lapForm=true; a.lap=4; worn(a,0.22); F.tick(e,f,0.2)
 assert(near(c.wearRate,0.1,1e-9) and c.wearLaps==1 and not c.lapForm,'formation lap: rate not learnt, flag cleared')
 a.lap=5; worn(a,0.32); F.tick(e,f,0.2)
 assert(c.wearLaps==2,'next lap learnt again')
end
-- Conseil de SpotterEnginer : lecture du contrat v1.
tests.SE_STRATEGY_PARSE_160D=function()
 local p=E.parseStrategy('v=1;mode=undercut;rival=2;gain=1.4;lap=12;stamp=10;future=x;state=advice')
 assert(p and p.mode=='undercut' and p.rival==2 and p.lap==12 and near(p.gain,1.4) and p.stamp==10 and p.state==nil,'valid text, unknown fields ignored')
 p=E.parseStrategy('v=1;mode=none;rival=-1;gain=-1.0;lap=0;stamp=7'); assert(p and p.mode=='none' and p.rival==-1 and near(p.gain,-1) and p.lap==0,'nothing to advise')
 assert(E.parseStrategy('v=1;mode=stayout;rival=-1;gain=-1.0;lap=0;stamp=7')==nil,'mode outside the contract refused')
 assert(#('v=1;mode=undercut;rival=22;gain=-12.5;lap=9999;stamp=99999999')<=K.seStrategyBytes and K.seStrategyBytes==160 and K.seStrategyStale==6,'contract sizes')
 local q,why=E.parseStrategy('v=2;mode=undercut;stamp=1'); assert(q==nil and why=='version','other version')
 q,why=E.parseStrategy('v=1;mode=undercut;stamp=1;x='..string.rep('a',200)); assert(q==nil and why=='trop longue','too long')
 q,why=E.parseStrategy('v=1;mode=attack;stamp=1'); assert(q==nil and why=='illisible','unknown mode')
 q=E.parseStrategy('v=1;mode=cover'); assert(q==nil,'no stamp')
 q=E.parseStrategy('v=1;mode=cover;stamp=nan'); assert(q==nil,'bad stamp')
 q=E.parseStrategy(nil); assert(q==nil)
 p=E.parseStrategy('v=1;mode=overcut;rival=999;lap=-4;gain=1e9;stamp=3.7')
 assert(p.rival==K.maxCars and p.lap==0 and p.gain==K.seStrategyMax and p.stamp==3,'numbers bounded, whole seconds')
 -- Fraîcheur : figé après K.seStrategyStale s, repris avec un nouvel horodatage, horodatage qui recule accepté.
 local e,f=race(4,20,5)
 local player=f.cars[1]
 e.seStrategy={raw='v=1;mode=undercut;rival=2;gain=1.4;lap=6;stamp=10'}
 E.seStrategy(e,f,player,100)
 assert(e.incidents.seStrategyMode=='undercut' and e.incidents.seStrategyTarget=='Driver_3','advice shown, target named')
 assert(logged(e,'SpotterEnginer strategie: undercut (rival Driver_3, tour 6, gain 1.4 s ; notre temps perdu aux stands -1.0 s)')==1,'one line per change')
 E.seStrategy(e,f,player,101); assert(logged(e,'SpotterEnginer strategie: undercut')==1,'no repeat')
 E.seStrategy(e,f,player,100+K.seStrategyStale+1)
 assert(e.incidents.seStrategyMode=='' and logged(e,'SpotterEnginer strategie: ignoree (figee)')==1,'stale: forgotten, logged once')
 E.seStrategy(e,f,player,100+K.seStrategyStale+2); assert(logged(e,'ignoree (figee)')==1)
 e.seStrategy.raw='v=1;mode=undercut;rival=2;gain=1.4;lap=6;stamp=2'
 E.seStrategy(e,f,player,200); assert(e.incidents.seStrategyMode=='undercut','stamp going backwards: a reset, fresh again')
 e.seStrategy.raw='v=1;mode=none;rival=-1;gain=-1.0;lap=0;stamp=3'
 E.seStrategy(e,f,player,201); assert(e.incidents.seStrategyMode=='','mode none: nothing shown')
 e.seStrategy.raw='v=3;mode=undercut;stamp=4'
 E.seStrategy(e,f,player,202); assert(e.incidents.seStrategyMode=='' and logged(e,'SpotterEnginer strategie: ignoree (version)')==1,'other version ignored, logged')
 -- Notre temps perdu à côté du sien.
 known(e,f,30,0.2,100); e.seStrategy.raw='v=1;mode=cover;rival=-1;gain=0.0;lap=7;stamp=5'
 E.seStrategy(e,f,player,203)
 assert(logged(e,'SpotterEnginer strategie: cover (rival -, tour 7, gain 0.0 s ; notre temps perdu aux stands 10.0 s)')==1,'our learnt pit loss in the line')
 assert(e.incidents.seStrategyMode=='cover' and e.incidents.seStrategyTarget=='')
 -- Hors course : rien.
 local j,fj=F.scene('P',3); j.seStrategy={raw='v=1;mode=undercut;rival=2;gain=1.0;lap=6;stamp=10'}
 E.seStrategy(j,fj,fj.cars[1],100); assert(j.incidents.seStrategyMode=='' and logged(j,'SpotterEnginer strategie')==0,'race only')
end
-- Affichage et journal seulement : les commandes de toutes les IA sont identiques avec et sans la clé ; la raison
-- suit le rappel d'arrêt du panneau, jamais le texte des annonces du pont.
tests.SE_STRATEGY_DISPLAY_ONLY_160D=function()
 local function run(raw)
  local e,f=race(5,20,5,smartOn); known(e,f,30,0.2,100)
  for i=2,5 do worn(f.cars[i],0.4) end
  if raw then e.seStrategy={raw=raw} end
  F.tick(e,f,2,true)
  return e,f
 end
 local a=run(nil)
 local b=run('v=1;mode=undercut;rival=2;gain=1.4;lap=6;stamp=10')
 assert(b.incidents.seStrategyMode=='undercut','advice read')
 for i=2,5 do
  local ca,cb=a.commands[i],b.commands[i]
  for _,key in ipairs({'level','levelScale','throttleLimit','aggression','caution','rulePit','stratLaps','stratPlanAt','offset','topSpeed','brake'}) do
   assert(ca[key]==cb[key],'command '..key..' of car '..i..' identical with and without the key')
  end
  assert(a.states[i].offset==b.states[i].offset and a.strategy.cars[i].wanted==b.strategy.cars[i].wanted,'state of car '..i..' identical')
 end
 -- Panneau : rappel d'arrêt obligatoire suivi de la raison.
 local t=b.incidents
 t.playerPitShowRemind=true; t.playerPitDue=1
 local function show() b.panel.at=-math.huge; if b.panel.info then b.panel.info.lapUntil=-math.huge end; Panel.update(b.panel,t,b.frame,b.run,'C',b.time) end
 show()
 assert(b.panel.kind=='pit' and b.panel.raw:find('undercut sur Driver_3',1,true),'reason after the reminder: '..tostring(b.panel.raw))
 t.seStrategyTarget=''; show()
 assert(b.panel.raw:find(' — undercut',1,true) and not b.panel.raw:find('undercut sur',1,true),'no target: the mode alone')
 t.seStrategyMode=''; show()
 assert(not b.panel.raw:find('undercut',1,true),'no advice: the reminder alone')
 t.seStrategyMode='undercut'; t.seStrategyTarget='Driver_3'
 local announce=Panel.pitAnnounce(t,'pitCompound'); assert(announce and not announce:find('undercut',1,true),'bridge announcement text unchanged')
end
-- Réglage coupé : aucun apprentissage, aucune ligne, aucune clé publiée ; allumé : la clé publiée suit le contrat v1.
tests.SMART_OFF_IDENTICAL_160D=function()
 local e,f=race(4,20,2,{strategyEnabled=true})
 for i=1,f.count do e.pits.cars[i].lapTime=100 end
 lane(e,f,3,30)
 assert(not e.pitloss.known and e.pitloss.samples==0 and e.pitloss.text=='','switch off: nothing learnt, nothing published')
 assert(logged(e,'stands: temps perdu')==0)
 local o,fo=race(4,20,2,smartOn)
 for i=1,fo.count do o.pits.cars[i].lapTime=100 end
 Pitloss.update(o.pitloss,o,fo,900)
 assert(o.pitloss.text:find('^v=1;pitLoss=%-1%.0;pitLossNeutral=%-1%.0;laneTime=%-1%.0;samples=0;stamp=[%d%.]+$'),'unknown published as -1: '..o.pitloss.text)
 lane(o,fo,3,30)
 Pitloss.update(o.pitloss,o,fo,1100)
 local text=o.pitloss.text
 assert(text:find('^v=1;pitLoss=15%.0;pitLossNeutral=[%d%.]+;laneTime=30%.0;samples=1;stamp=1031%.0$'),'side key format: '..text)
 assert(#text<=160,'short text')
 Pitloss.update(o.pitloss,o,fo,1105); assert(o.pitloss.text==text,'same numbers: same text, same stamp')
 -- Coupé en cours de session : clé vidée (l'hôte n'écrit plus), rien d'appris ensuite.
 set(o,fo,{strategySmart=false}); assert(o.pitloss.text=='','switch off again: nothing more to publish')
 -- Hors course : rien.
 local p,fp=F.scene('P',3); set(p,fp,smartOn); F.tick(p,fp,1)
 assert(p.pitloss.text=='' and not p.pitloss.on,'practice: nothing')
end

-- Rythme : courbe de l'usure en trois segments.
tests.WEAR_CURVE_160D=function()
 assert(Wear.curve(0,0.75)==0 and Wear.curve(K.wearPaceStart,0.75)==0,'no loss below the start')
 assert(near(Wear.curve(0.75,0.75),K.wearPaceAtThreshold),'loss at the threshold')
 assert(near(Wear.curve((K.wearPaceStart+0.75)/2,0.75),K.wearPaceAtThreshold/2),'linear up to the threshold')
 assert(near(Wear.curve(1,0.75),K.wearPaceCliff) and near(Wear.curve(1.5,0.75),K.wearPaceCliff),'cliff at 100 %, bounded')
 assert(near(Wear.curve(0.875,0.75),(K.wearPaceAtThreshold+K.wearPaceCliff)/2),'linear on the cliff')
 -- Seuil de la stratégie sous le départ réglé (défaut 30 %) : la perte commence à la moitié du seuil, sans marche.
 assert(Wear.curve(0.15,0.3)==0 and near(Wear.curve(0.225,0.3),K.wearPaceAtThreshold/2) and near(Wear.curve(0.3,0.3),K.wearPaceAtThreshold),'low threshold: no step')
 assert(Wear.curve(0.5,0.2)>K.wearPaceAtThreshold,'above a low threshold: on the cliff')
end
local function tyres(a,current)
 a.tyresKnown=true; a.dryPrimary={0,1,2}; a.tyreNames={[0]='S',[1]='M',[2]='H'}; a.tyreLongNames={}; a.compoundIndex=current
end
-- Gomme : un cran plus tendre ou plus dure que la gomme du milieu ; modèle non classé : rien.
tests.COMPOUND_PACE_160D=function()
 local StartVar=require('src/startvar')
 local a={}; tyres(a,0)
 local ranks=StartVar.ranks(a)
 assert(near(Wear.compound(a,ranks),K.compoundPaceStep),'soft: one step up')
 a.compoundIndex=1; assert(Wear.compound(a,ranks)==0,'medium: neutral')
 a.compoundIndex=2; assert(near(Wear.compound(a,ranks),-K.compoundPaceStep),'hard: one step down')
 a.compoundIndex=5; assert(Wear.compound(a,ranks)==0,'wet tyre: neutral')
 assert(Wear.compound(a,false)==0 and Wear.compound(a,nil)==0,'unranked model: neutral')
 local b={tyresKnown=true,dryPrimary={0,1,2,3,4,5,6},tyreNames={[0]='HS',[1]='US',[2]='ES',[3]='S',[4]='M',[5]='H',[6]='EH'},tyreLongNames={},compoundIndex=0}
 assert(near(Wear.compound(b,StartVar.ranks(b)),K.compoundPaceMax),'three steps softer: bounded by the maximum')
 b.compoundIndex=6; assert(near(Wear.compound(b,StartVar.ranks(b)),-K.compoundPaceMax),'three steps harder: bounded too')
 -- Dans une scène : gomme tendre plus rapide que la dure, modèle aux gommes inconnues inchangé.
 local e,f=race(4,20,2,{wearPace=true})
 for i=2,4 do f.cars[i].fuel=50; f.cars[i].maxFuel=100 end
 tyres(f.cars[2],0); tyres(f.cars[3],2)
 F.tick(e,f,3)
 assert(e.commands[2].levelScale>1 and e.commands[3].levelScale<1 and e.commands[4].levelScale==1,'soft faster, hard slower, unknown tyres unchanged')
end
-- Carburant : réservoir à moitié neutre, léger plus vite, lourd moins vite, centré.
tests.FUEL_PACE_CENTRED_160D=function()
 assert(Wear.fuel({fuel=50,maxFuel=100})==0,'half tank: neutral')
 assert(near(Wear.fuel({fuel=0,maxFuel=100}),K.fuelPace/2) and near(Wear.fuel({fuel=100,maxFuel=100}),-K.fuelPace/2),'empty and full, symmetric')
 assert(Wear.fuel({fuel=-1,maxFuel=100})==0 and Wear.fuel({fuel=10,maxFuel=0})==0 and Wear.fuel({})==0,'unknown: neutral')
 assert(near(Wear.fuel({fuel=300,maxFuel=100}),-K.fuelPace/2),'bounded')
end
-- Total borné ; usure non fiable : ni perte, ni freinage prudent.
tests.WEAR_CLAMP_160D=function()
 local e,f=race(4,20,2,{wearPace=true})
 local a=f.cars[2]; worn(a,1); a.fuel=100; a.maxFuel=100; tyres(a,2)
 a.tyreTemp={120,120,120,120}
 F.tick(e,f,K.wearHotTime+8)
 assert(near(e.wear.target[2],1-K.wearScaleMaxLoss),'worst case bounded: '..e.wear.target[2])
 assert(near(e.commands[2].levelScale,1-K.wearScaleMaxLoss,1e-6),'applied to the level')
 local b=f.cars[3]; worn(b,0); b.fuel=0; b.maxFuel=100; tyres(b,0)
 F.tick(e,f,3)
 assert(near(e.wear.target[3],1+math.min(K.wearScaleMaxGain,K.fuelPace/2+K.compoundPaceStep)),'best case bounded: '..e.wear.target[3])
 assert(e.wear.target[3]<=1+K.wearScaleMaxGain+1e-12)
 -- Surchauffe seule.
 local h,fh=race(4,20,2,{wearPace=true})
 local c=fh.cars[2]; worn(c,0); c.tyreTemp={110,110,110,110}
 F.tick(h,fh,K.wearHotTime-2); assert(h.wear.target[2]==1,'hot, but not long enough')
 F.tick(h,fh,4); assert(near(h.wear.target[2],1-K.wearHotPct),'overheated tyres: small loss')
 c.tyreTemp={90,90,90,90}; F.tick(h,fh,2); assert(h.wear.target[2]==1,'cooled: given back')
end
tests.WEAR_UNTRUSTED_160D=function()
 local e,f=race(4,20,2,{wearPace=true})
 e.strategy.wearTrust='unknown'
 worn(f.cars[2],0.9); F.tick(e,f,3)
 assert(e.wear.target[2]==1 and e.commands[2].levelScale==1 and e.states[2].wearBrake==nil and Wear.lossOf(e.wear,2)==0,'wear scale not verified: no effect')
 e.strategy.wearTrust='trusted'; F.tick(e,f,3)
 assert(e.wear.target[2]<1 and e.states[2].wearBrake>1,'verified: acts')
 e.strategy.wearTrust='unreliable'; F.tick(e,f,2)
 assert(e.wear.target[2]==1 and e.states[2].wearBrake==nil,'unreliable: given back')
 -- Jamais le joueur.
 worn(f.cars[1],0.9); e.strategy.wearTrust='trusted'; F.tick(e,f,2)
 assert(e.wear.target[1]==1 and e.states[1].wearBrake==nil,'never the player')
end
-- Pneus usés : prudence au freinage seulement (champ lu dans le bloc du freinage du directeur), remise des gaz.
tests.WEAR_BRAKE_ONLY_BRAKING_160D=function()
 local e,f=race(4,20,2,{wearPace=true})
 worn(f.cars[2],1); worn(f.cars[3],K.wearPaceStart); f.cars[4].wearKnown=false
 F.tick(e,f,2)
 assert(near(e.states[2].wearBrake,1+K.wearBrakeCaution) and near(e.states[2].wearExit,1+K.wearExitGain),'worn out: full margin')
 assert(e.states[3].wearBrake==1,'at the start of the curve: neutral')
 assert(e.states[4].wearBrake==nil and e.states[4].wearExit==nil,'wear unknown: field absent')
 -- En ligne droite sans freinage, la prudence commandée ne dépend pas de l'usure.
 local o,fo=race(4,20,2,{wearPace=true}); worn(fo.cars[2],0); F.tick(o,fo,2)
 assert(e.commands[2].caution==o.commands[2].caution,'no braking: same caution, worn or not')
end
-- Variation du niveau étalée ; rendue de la même façon.
tests.WEAR_RAMP_160D=function()
 local e,f=race(4,20,2,{wearPace=true})
 worn(f.cars[2],1); F.tick(e,f,1)
 local s1=e.wear.scale[2]
 assert(s1<1 and s1>=1-K.wearScaleRate*1.05,'at most wearScaleRate per second: '..s1)
 F.tick(e,f,1); assert(e.wear.scale[2]<s1 and e.wear.scale[2]>=1-K.wearScaleRate*2.1,'still going down')
 F.tick(e,f,10); assert(near(e.wear.scale[2],e.wear.target[2]),'target reached')
 assert(logged(e,'rythme: Driver_2 pneus au bout (100 %)')==1,'cliff logged once')
 assert(logged(e,'rythme: Driver_2 -')==1,'pace line logged once in the gap')
 worn(f.cars[2],0); F.tick(e,f,1)
 assert(e.wear.scale[2]>e.wear.target[2]-1 and e.wear.scale[2]<1,'given back progressively')
end
-- Réglage coupé : aucun effet ; coupé en cours de route : tout est rendu.
tests.WEAR_OFF_IDENTICAL_160D=function()
 local e,f=race(4,20,2)
 worn(f.cars[2],1); f.cars[2].fuel=0; f.cars[2].maxFuel=100; F.tick(e,f,3)
 assert(not e.run.wearPace and e.commands[2].levelScale==1 and e.states[2].wearBrake==nil and not e.wear.on,'off by default: nothing')
 assert(logged(e,'rythme:')==0)
 set(e,f,{wearPace=true}); F.tick(e,f,3)
 assert(e.commands[2].levelScale<1 and e.states[2].wearBrake>1,'wearPace acts')
 set(e,f,{wearPace=false}); F.tick(e,f,0.1)
 assert(e.commands[2].levelScale==1 and e.states[2].wearBrake==nil and e.states[2].wearExit==nil,'switched off: given back')
 -- Tous les profils : essais aussi.
 local p,fp=F.scene('P',3); p.strategy.wearTrust='trusted'; set(p,fp,{wearPace=true})
 worn(fp.cars[2],1); F.tick(p,fp,3); assert(p.commands[2].levelScale<1,'practice too')
end
-- Journal en anglais des lignes de la tranche.
tests.JOURNAL_EN_160D=function()
 local function en(fr,expected) local got=J.english(fr); assert(got==expected,got) end
 en('stands: temps perdu appris 15.0 s (voie 30.0 s, 1 passage(s))','pits: learnt pit loss 15.0 s (lane 30.0 s, 1 stop(s))')
 en('strategie: Driver_2 arret retarde d un tour (trafic a la sortie : Driver_4 a 2.0 s)','strategy: Driver_2 stop delayed one lap (traffic at the exit: Driver_4 at 2.0 s)')
 en('strategie: Driver_2 arret retarde d un tour (trafic a la sortie : une file a 6.0 s)','strategy: Driver_2 stop delayed one lap (traffic at the exit: a train at 6.0 s)')
 en('strategie: Driver_2 arret avance (piste libre a la sortie)','strategy: Driver_2 stop brought forward (clean air at the exit)')
 en('strategie: Driver_2 arret sous neutralisation (gain 12 s)','strategy: Driver_2 stop under neutralisation (saving 12 s)')
 en('strategie: Driver_2 reste en piste sous neutralisation (position en piste)','strategy: Driver_2 stays out under neutralisation (track position)')
 en('strategie: Driver_2 undercut sur Driver_3 (ecart 0.5 s, gain estime 0.42 s par tour)','strategy: Driver_2 undercut on Driver_3 (gap 0.5 s, estimated gain 0.42 s per lap)')
 en('SpotterEnginer strategie: undercut (rival Driver_3, tour 6, gain 1.4 s ; notre temps perdu aux stands -1.0 s)','SpotterEnginer strategy: undercut (rival Driver_3, lap 6, gain 1.4 s; our pit-loss time -1.0 s)')
 en('SpotterEnginer strategie: ignoree (figee)','SpotterEnginer strategy: ignored (stale)')
 en('SpotterEnginer strategie: ignoree (version)','SpotterEnginer strategy: ignored (version)')
 en('SpotterEnginer strategie: ignoree (trop longue)','SpotterEnginer strategy: ignored (too long)')
 en('SpotterEnginer strategie: ignoree (illisible)','SpotterEnginer strategy: ignored (unreadable)')
 en('rythme: Driver_2 -4.0 % (pneus 100 %, gomme S, carburant 50 %)','pace: Driver_2 -4.0% (tyres 100%, compound S, fuel 50%)')
 en('rythme: Driver_2 pneus au bout (100 %), rythme -4.0 %','pace: Driver_2 tyres finished (100%), pace -4.0%')
end

-- Relecture de la fusion : pas d'arrêt opportuniste pendant le tour de relance d'un drapeau rouge (ni appel groupé).
tests.SC_NO_STOP_ON_RELAUNCH_160M2=function()
 local e,f,c=scScene(0.3,0.5,20)
 e.incidents.neutral=true; e.incidents.relaunch=true; strat(e,f)
 assert(not c.wanted,'relaunch lap after a red flag: no cheap stop')
 local g,fg,cg=scScene(0.3,0.5,20)
 g.incidents.neutral=true; g.incidents.relaunch=false; strat(g,fg)
 assert(cg.wanted and cg.cause=='neutral','ordinary neutralisation: cheap stop as before')
end
-- Relecture de la fusion : arrêt obligatoire dû (fenêtre ouverte, arrêt pas encore compté) : jamais retardé pour le
-- trafic à la sortie des stands.
tests.REJOIN_NO_DELAY_MANDATORY_160M2=function()
 local function run(due)
  local e,f=race(5,20,2,smartOn); known(e,f,30,0.1,100)
  e.states[2].persona.strategyRisk=0.5
  F.place(f,4,8200,100); f.cars[4].lap=2; e.pits.cars[4].lapTime=103
  local a=f.cars[2]
  for lap=2,8 do
   a.lap=lap; worn(a,0.1*(lap-1))
   for _=1,12 do
    if due then e.run.mandatoryStops=1; e.pits.state='open'; e.pits.cars[2].windowStops=0 end
    strat(e,f)
   end
  end
  return e.strategy.cars[2],e
 end
 local c,e=run(false)
 assert(not c.wanted and c.rejoinDelay==1,'scene: without a mandatory stop due, the stop is delayed for traffic')
 c,e=run(true)
 assert(c.rejoinDelay==0 and logged(e,'arret retarde')==0,'mandatory stop due: never delayed for traffic')
end
return tests
