-- Beta 1.59 (fourche H-B, décisions du pilote) : stratégies de départ variées (src/startvar.lua) et arrêt aux stands
-- pour dégâts (src/damagepit.lua). Les deux réglages sont coupés par défaut. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local A=require('src/applier')
local C=require('src/config')
local K=C.K
local E=require('src/engine')
local SV=require('src/startvar')
local tests={}
local function tyreCar(index,position,short,long,current)
 return {valid=true,control=true,player=false,safetyCar=false,finished=false,pit=false,kmh=0,tyresKnown=true,index=index,position=position,
  id='lotus_test',identity='lotus_test#'..index,dryPrimary={0,1,2},tyreNames=short,tyreLongNames=long,compoundIndex=current or 1}
end
local SHORT={[0]='SS',[1]='S',[2]='M'}
local LONG={[0]='Slick SuperSoft',[1]='Slick Soft',[2]='Slick Medium'}
tests.START_HARDNESS_RANK_159HB=function()
 local a=tyreCar(0,1,{[0]='S',[1]='M',[2]='H'},{})
 assert(SV.hardness(a,0)<SV.hardness(a,1) and SV.hardness(a,1)<SV.hardness(a,2),'S < M < H (short names)')
 local b=tyreCar(0,1,{[0]='A',[1]='B',[2]='C'},LONG)
 assert(SV.hardness(b,0)<SV.hardness(b,1) and SV.hardness(b,1)<SV.hardness(b,2),'SuperSoft < Soft < Medium (long names)')
 local both=tyreCar(0,1,{[0]='H',[1]='M',[2]='S'},LONG)
 assert(SV.hardness(both,0)<SV.hardness(both,2),'the long name wins over the short one')
 local p=tyreCar(0,1,{[0]='C5',[1]='C3',[2]='C1'},{})
 assert(SV.hardness(p,0)<SV.hardness(p,1) and SV.hardness(p,1)<SV.hardness(p,2),'Pirelli C5 softer than C3, C3 softer than C1')
 local u=tyreCar(0,1,{[0]='Mi',[1]='X',[2]='Y'},{[0]='Michelin Pilot Sport Cup 2R'})
 assert(SV.hardness(u,0)==nil and SV.ranks(u)==nil,'unknown names: not ranked')
 local d=tyreCar(0,1,{[0]='S',[1]='S2',[2]='M'},{[0]='Soft',[1]='Soft B',[2]='Medium'})
 assert(SV.ranks(d)==nil,'two compounds of the same rank: not ranked')
 local hidden=tyreCar(0,1,SHORT,LONG); hidden.tyresKnown=false
 assert(SV.ranks(hidden)==nil,'unreadable tyres: not ranked')
end
-- Grille de n voitures (aucune joueur, aucune voiture de sécurité), piste sèche, avant le départ.
local function grid(n,current)
 local frame={count=n,cars={},started=false,startIn=5}; local commands={}
 for i=1,n do frame.cars[i]=tyreCar(i-1,i,SHORT,LONG,current); commands[i]={weatherManaged=false,weatherCompound=-1} end
 return frame,commands
end
local function choices(seed,n,p,w,current)
 local frame,commands=grid(n,current); w=w or {}
 local lines={}; local log={}
 SV.step(w,frame,commands,p or {section_strategy=true,strategyStartVariety=true},seed,true,nil,0)
 for i=1,n do lines[i]=commands[i].startCompound end
 return lines,commands,frame,w
end
tests.START_VARIETY_CHOICE_159HB=function()
 local first=choices(42,20); local again=choices(42,20)
 local changed=0
 for i=1,20 do
  assert(first[i]==again[i],'deterministic for one seed')
  if first[i]>=0 then changed=changed+1; assert(first[i]==0 or first[i]==2,'one step from the fitted S: SS or M') end
 end
 assert(changed>0 and changed<20,'part of the grid only')
 -- Fin de grille plutôt plus dure, tête plutôt plus tendre (sur de nombreuses graines).
 local frontHard,frontSoft,backHard,backSoft=0,0,0,0
 for seed=1,300 do
  local c=choices(seed,20)
  for i=1,20 do
   if c[i]==2 then if i<=10 then frontHard=frontHard+1 else backHard=backHard+1 end
   elseif c[i]==0 then if i<=10 then frontSoft=frontSoft+1 else backSoft=backSoft+1 end end
  end
 end
 assert(backHard>frontHard and frontSoft>backSoft,'grid bias: back harder, front softer')
 -- Quatre gommes (SS, S, M, H), départ en S : un cran au plus, jamais H ni deux crans plus tendre.
 local seenFour={}
 for seed=1,200 do
  local frame,commands=grid(20)
  for i=1,20 do local a=frame.cars[i]; a.dryPrimary={0,1,2,3}; a.tyreNames={[0]='SS',[1]='S',[2]='M',[3]='H'}; a.tyreLongNames={} end
  SV.step({},frame,commands,{section_strategy=true,strategyStartVariety=true},seed,true,nil,0)
  for i=1,20 do local c=commands[i].startCompound; assert(c==-1 or c==0 or c==2,'one step from S: SS or M, never H'); seenFour[c]=true end
 end
 assert(seenFour[0] and seenFour[2],'both directions used')
 -- Déjà sur la gomme la plus dure : jamais deux crans, jamais une gomme absente.
 local hardest=choices(7,20,nil,nil,2)
 for i=1,20 do assert(hardest[i]==-1 or hardest[i]==1,'from M: only S (one step softer) or nothing') end
end
tests.START_VARIETY_GUARDS_159HB=function()
 local on={section_strategy=true,strategyStartVariety=true}
 local function any(list) for _,v in ipairs(list) do if v and v>=0 then return true end end return false end
 assert(any((choices(42,20,on))),'baseline: some cars change')
 assert(not any((choices(42,20,{section_strategy=true,strategyStartVariety=false}))),'switch off: no change')
 assert(not any((choices(42,20,{section_strategy=false,strategyStartVariety=true}))),'AI strategy section off: no change')
 assert(not any((choices(42,20,on,{wet=true}))),'wet track: no change')
 -- Après le départ : aucune commande.
 local frame,commands=grid(20)
 frame.started=true; frame.startIn=0
 SV.step({},frame,commands,on,42,true,nil,0)
 for i=1,20 do assert((commands[i].startCompound or -1)<0,'after the start: no change') end
 -- Hors course : aucune commande.
 frame,commands=grid(20)
 SV.step({},frame,commands,on,42,false,nil,0)
 for i=1,20 do assert((commands[i].startCompound or -1)<0,'not a race: no change') end
 -- Joueur, voiture de sécurité, gommes illisibles : jamais ; gommes non classées notées une fois par modèle.
 frame,commands=grid(20)
 for i=1,20 do frame.cars[i].player=i==1; frame.cars[i].safetyCar=i==2; frame.cars[i].tyresKnown=i>3 end
 local w={}; SV.step(w,frame,commands,on,42,true,nil,0); for i=1,3 do assert(commands[i].startCompound==-1,'player, Safety Car, unread tyres '..i) end
 -- Gommes lues plus tard (lecture étalée) : décision prise à ce moment-là, jamais figée avant.
 assert(w.start[3]==nil,'no decision before the tyres are read')
 frame.cars[3].tyresKnown=true; SV.step(w,frame,commands,on,42,true,nil,0); assert(w.start[3]~=nil,'decided once the tyres are read')
 local log=require('src/util').newLog(50,50,0)
 frame,commands=grid(5)
 for i=1,5 do frame.cars[i].tyreNames={[0]='A',[1]='B',[2]='C'}; frame.cars[i].tyreLongNames={} end
 SV.step({},frame,commands,on,42,true,log,0)
 local n=0; for i=1,log.limit do if log[i].message:find('strategie de depart: gommes de lotus_test non classees',1,true) then n=n+1 end end
 assert(n==1,'one line per model')
 for i=1,5 do assert(commands[i].startCompound==-1,'not ranked: unchanged') end
 -- Météo prioritaire : la gomme voulue par la météo n'est jamais remplacée.
 frame,commands=grid(20)
 for i=1,20 do commands[i].weatherManaged=true; commands[i].weatherCompound=2 end
 SV.step({},frame,commands,on,42,true,nil,0)
 for i=1,20 do assert(commands[i].startCompound==-1,'weather decision kept') end
end
tests.START_TYRE_WRITTEN_ONCE_159HB=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C'); local a=A.new(); assert(A.access(a))
 local lines={}; a.note=function(level,text) lines[#lines+1]=level..' '..text end
 for _,cmd in ipairs(e.commands) do cmd.active=false; cmd.weatherManaged=false; cmd.startCompound=-1 end
 host.sim.isSessionStarted=false; f.started=false
 local car=f.cars[2]; car.kmh=0; host.cars[1].speedKmh=0
 host.tyreCatalog[1]={{short='SS',name='Super Soft'},{short='S',name='Slick Soft'},{short='M',name='Medium'}}; host.cars[1].compoundIndex=1; car.compoundIndex=1; car.tyreNames={[0]='SS',[1]='S',[2]='M'}; car.tyreLongNames={}
 local cmd=e.commands[2]; cmd.startCompound=2; cmd.startDir='plus dure'; cmd.startPlace=12
 A.apply(a,f,e.commands,e.g,1)
 assert(host.cars[1].compoundIndex==2,'harder compound fitted on the grid')
 local n=0; for _,l in ipairs(lines) do if l:find('strategie de depart: '..car.name..' part en M au lieu de S (plus dure, place 12)',1,true) then n=n+1 end end
 assert(n==1,'one line')
 -- Une fois posée : plus aucune écriture, même si la gomme du cadre ne suit pas encore (lue à l'image suivante).
 local calls=host.calls
 for t=2,12,0.5 do A.apply(a,f,e.commands,e.g,t) end
 assert(host.calls==calls,'written once per car and session')
 -- Sans gomme visée : rien.
 cmd.startCompound=-1; car.compoundIndex=1; host.cars[1].compoundIndex=1
 A.apply(a,f,e.commands,e.g,6); assert(host.cars[1].compoundIndex==1,'nothing without a target')
end
-- Scène de course, réglage allumé, IA 2 endommagée à pleine allure (dégâts lus seulement quand elle est lue en roulant).
local function damageScene(profile,count)
 local e,f=F.scene(profile or 'C',count)
 e.profiles[profile or 'C'].damagePit=true; E.changed(e); F.tick(e,f,0.1)
 return e,f
end
local function lines(e,text) local n=0; for i=1,e.log.limit do if e.log[i].message:find(text,1,true) then n=n+1 end end return n end
tests.DAMAGE_PIT_CALL_159HB=function()
 local e,f=damageScene()
 local a=f.cars[2]; a.damageBody=120; a.damageSuspension=0.1
 F.tick(e,f,1)
 assert(not e.commands[2].damageCalled,'not before the confirmation time')
 F.tick(e,f,K.damagePitConfirm+K.damagePitScanPeriod+0.5)
 assert(e.commands[2].rulePit and e.commands[2].damageCalled and e.commands[2].slowCalled,'called, counted in the shared pit-call limit')
 assert(lines(e,'degats: '..a.name..' appelee aux stands (carrosserie 120 km/h, suspension 0.10')==1,'one line')
 assert(not e.commands[3].damageCalled,'an undamaged AI is not called')
 -- Arrivée à l'emplacement : réparée (même sans réparations réglementaires), puis plus appelée au même niveau.
 e.profiles.C.pitRepair=false; E.changed(e); F.tick(e,f,0.1)
 a.pit=true; a.inPitBox=true; a.kmh=0; F.tick(e,f,0.2)
 assert(e.commands[2].pitRepair and not e.commands[2].damageCalled,'repaired at its box')
 a.inPitBox=false; a.kmh=60; F.tick(e,f,0.2); a.pit=false; a.kmh=100; F.tick(e,f,K.damagePitConfirm+K.damagePitScanPeriod+1)
 assert(not e.commands[2].damageCalled and lines(e,'degats: '..a.name..' appelee aux stands')==1,'not called again at the same level')
 -- Dégâts encore aggravés : nouvel épisode.
 a.damageBody=120+K.damagePitRegrowBody+5; F.tick(e,f,K.damagePitConfirm+K.damagePitScanPeriod+1)
 assert(e.commands[2].damageCalled and lines(e,'degats: '..a.name..' appelee aux stands')==2,'called again after more damage')
end
-- Moteur réduit pour src/damagepit.lua seul : drapeaux, stands fermés et tours restants posés à la main.
local DP=require('src/damagepit')
local function bench(profile,n)
 local U=require('src/util')
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
-- Avance de seconds s, une image tous les 1/60 s ; renvoie la dernière commande de l'IA i.
local function run(e,frame,from,seconds,red)
 local t=from
 for _=1,math.floor(seconds*60+0.5) do
  for i=1,frame.count do local c=e.commands[i]; c.rulePit=false; c.slowCalled=false; c.stratCalled=false; c.sanCalled=false; c.recover=false; c.penaltyPass=false; c.pitRepair=false end
  DP.step(e,frame,t,red); t=t+1/60
 end
 return t
end
local WAIT=K.damagePitConfirm+K.damagePitScanPeriod+0.5
tests.DAMAGE_PIT_THRESHOLDS_159HB=function()
 -- Relecture 1.59 : la boîte de vitesses n'a pas de réparation, elle n'appelle plus (journal seulement).
 local cases={{body=K.damagePitBody},{susp=K.damagePitSuspension},{engine=K.damagePitEngine}}
 for _,c in ipairs(cases) do
  local e,f=bench(); local a=f.cars[2]
  a.damageBody=c.body or 0; a.damageSuspension=c.susp or 0; a.damageGearbox=c.gear or 0; a.engineLife=c.engine or K.engineLifeNew
  run(e,f,0,WAIT)
  assert(e.commands[2].damageCalled and e.commands[2].rulePit,'threshold reached')
 end
 local e,f=bench(); local a=f.cars[2]
 a.damageBody=K.damagePitBody-1; a.damageSuspension=K.damagePitSuspension-0.01; a.damageGearbox=K.damagePitGearbox-0.01; a.engineLife=K.damagePitEngine+1
 run(e,f,0,WAIT)
 assert(not e.commands[2].damageCalled,'below every threshold: not called')
 -- Confirmation : pas avant K.damagePitConfirm s au-dessus du seuil.
 e,f=bench(); f.cars[2].damageBody=120
 run(e,f,0,K.damagePitConfirm-0.5)
 assert(not e.commands[2].damageCalled,'not before the confirmation time')
end
tests.DAMAGE_PIT_GUARDS_159HB=function()
 local function lines(e,text) local n=0; for i=1,e.log.limit do if e.log[i].message:find(text,1,true) then n=n+1 end end return n end
 -- Neutralisation : elle attend (une ligne) ; voiture dangereuse : appelée quand même.
 local e,f=bench(); local a=f.cars[2]; a.damageBody=120
 e.incidents.neutral=true
 local t=run(e,f,0,WAIT)
 assert(not e.commands[2].damageCalled and lines(e,'degats: Driver_2 attend la fin du drapeau pour rentrer')==1,'waits under a neutralisation, one line')
 a.damageSuspension=K.damagePitUnsafe; t=run(e,f,t,K.damagePitScanPeriod+0.5)
 assert(e.commands[2].damageCalled,'unsafe car called even under a neutralisation')
 -- Drapeau jaune local, stands fermés : attend ; drapeau rouge : jamais (le drapeau rouge rappelle tout le monde).
 e,f=bench(); f.cars[2].damageBody=120; e.states[2].yellow=true; run(e,f,0,WAIT); assert(not e.commands[2].damageCalled,'local yellow: waits')
 e,f=bench(); f.cars[2].damageBody=120; e.incidents.pitsClosed=true; run(e,f,0,WAIT); assert(not e.commands[2].damageCalled,'pits closed: waits')
 e,f=bench(); f.cars[2].damageBody=120; run(e,f,0,WAIT,true); assert(not e.commands[2].damageCalled,'red flag: never')
 -- Derniers tours de la course : jamais ; hors course, sans condition de tours.
 e,f=bench(); f.cars[2].damageBody=120; e.race.lapsLeft=K.damagePitMinLapsLeft-1; run(e,f,0,WAIT)
 assert(not e.commands[2].damageCalled,'not in the last laps')
 e,f=bench('P'); f.cars[2].damageBody=120; e.race.lapsLeft=0; run(e,f,0,WAIT)
 assert(e.commands[2].damageCalled,'practice: called')
 e,f=bench('J'); f.cars[2].damageBody=120; run(e,f,0,WAIT); assert(not e.commands[2].damageCalled,'track day: never')
 -- Limite d'appels partagée : trois IA déjà appelées hors de la voie des stands.
 e,f=bench(nil,6); f.cars[2].damageBody=120
 local tt=0
 for _=1,math.floor(WAIT*60) do
  for i=1,6 do local c=e.commands[i]; c.rulePit=i>=4; c.slowCalled=false; c.stratCalled=false; c.sanCalled=false; c.recover=false; c.penaltyPass=false end
  DP.step(e,f,tt,false); tt=tt+1/60
 end
 assert(not e.commands[2].damageCalled,'shared pit-call limit respected')
 -- Déjà appelée par une autre raison (règles, stratégie…) : pas de second appel.
 e,f=bench(); f.cars[2].damageBody=120
 tt=0
 for _=1,math.floor(WAIT*60) do e.commands[2].stratCalled=true; e.commands[3].rulePit=false; DP.step(e,f,tt,false); tt=tt+1/60 end
 assert(not e.commands[2].damageCalled,'already called for another reason')
 -- Joueur, voiture arrivée, voiture de sécurité : jamais.
 e,f=bench(); f.cars[1].damageBody=200; f.cars[2].damageBody=200; f.cars[2].finished=true; f.cars[3].damageBody=200; f.cars[3].safetyCar=true
 run(e,f,0,WAIT)
 for i=1,3 do assert(not e.commands[i].damageCalled,'never the player, a finished car or the Safety Car '..i) end
 -- Visibilité : arrêt pour dégâts masqué en journée circuit et hotlap ; départs variés en course seulement.
 assert(C.hidden('J','damagePit') and C.hidden('H','damagePit') and not C.hidden('C','damagePit') and not C.hidden('P','damagePit'),'hidden on track days and hotlap only')
 assert(C.hidden('P','strategyStartVariety') and not C.hidden('C','strategyStartVariety'),'starting strategies: race only')
end
tests.DAMAGE_PIT_SCAN_159HB=function()
 -- Réglage coupé : jamais de lecture en roulant, jamais d'appel.
 local e,f=F.scene('C',6)
 f.cars[2].damageBody=200
 for _=1,120 do F.tick(e,f,1/60); for i=1,6 do assert(not f.cars[i].damageScan,'no scan when off') end end
 assert(not e.commands[2].damageCalled and lines(e,'degats:')==0,'no call, no line when off')
 -- Allumé : une IA lue par image au plus, chacune au plus toutes les K.damagePitScanPeriod s.
 e,f=damageScene('C',6)
 local seen={}
 for frame=1,240 do
  F.tick(e,f,1/60)
  local n=0; for i=1,6 do if f.cars[i].damageScan then n=n+1; seen[i]=(seen[i] or 0)+1 end end
  assert(n<=1,'one car per frame')
 end
 assert(not seen[1],'never the player')
 for i=2,6 do assert(seen[i] and seen[i]<=math.floor(4/K.damagePitScanPeriod)+1,'each AI scanned, at most every period '..i) end
end
-- Beta 1.59 (undercut arret obligatoire, décision du pilote) : l'undercut, la couverture et l'overcut agissent aussi sur
-- l'arrêt obligatoire encore dû, fenêtre ouverte ; une demande qui le sert n'est jamais retirée dans la même image.
local function mandatoryRace(openPct)
 local e,f=F.scene('C',4); local rp=e.profiles.C
 rp.strategyEnabled=true; rp.strategyUndercut=true; rp.mandatoryStops=1; rp.pitWindowOpenPct=openPct or 0; rp.pitWindowClosePct=100; E.changed(e)
 f.sessionLaps=30; f.leaderLaps=10; f.timedRace=false; f.sessionMinutes=0; f.started=true
 for i=1,f.count do f.cars[i].lap=10 end
 e.strategy.wearTrust='trusted'
 for i=2,4 do local a=f.cars[i]; a.wearKnown=true; a.tyreWear={0.02,0.02,0.02,0.02}; a.tyreKm={5,5,5,5}; a.tyreTemp={90,90,90,90}; a.tyreOptimum={90,90,90,90}; a.fuel=100; a.maxFuel=110; a.fuelPerLap=1 end
 return e,f
end
local function withdrawn(e,name) return lines(e,'strategie: '..name..' arret retire (plus necessaire)') end
tests.MANDATORY_UNDERCUT_REAL_159HB=function()
 local e,f=mandatoryRace()
 F.place(f,1,-5000,100); F.place(f,2,0,200); F.place(f,3,20,200); F.place(f,4,5000,200)
 e.states[2].persona.strategyRisk=0.95
 F.tick(e,f,0.2); e.states[2].persona.strategyRisk=0.95; F.tick(e,f,K.strategyRetry+0.5)
 for i=1,f.count do f.cars[i].lap=11 end; f.leaderLaps=11; F.tick(e,f,0.5)
 local c=e.strategy.cars[2]
 assert(e.pits.opened and e.pits.cars[2].windowStops==0 and c.planned and c.stops==0,'mandatory stop still owed, no strategy stop of its own')
 assert(c.wanted and c.cause=='undercut' and c.mandatoryReq,'bold strategist undercuts on its mandatory stop')
 assert(lines(e,'strategie: Driver_2 arret obligatoire avance (undercut)')==1 and withdrawn(e,'Driver_2')==0,'requested once, never withdrawn in the same frame')
 F.tick(e,f,2)
 assert(c.wanted and e.commands[2].rulePit and withdrawn(e,'Driver_2')==0,'request held until its stop')
 -- Arrêt dans la fenêtre : compté comme l'arrêt obligatoire, demande oubliée.
 local a=f.cars[2]; a.pit=true; F.tick(e,f,0.2); a.inPitBox=true; a.kmh=0; F.tick(e,f,0.5)
 assert(e.pits.cars[2].windowStops==1,'the undercut stop counts as the mandatory stop')
 a.inPitBox=false; a.kmh=60; F.tick(e,f,0.2); a.pit=false; a.kmh=200; F.tick(e,f,1)
 assert(not c.wanted and lines(e,'strategie: Driver_2 arret obligatoire avance')==1,'one request, never again')
 -- Mandat rempli : plus de demande au titre de l'arrêt obligatoire, et une demande marquée devient retirable.
 assert(not c.mandatoryReq or not c.wanted,'no mandatory request left')
end
tests.MANDATORY_COVER_REAL_159HB=function()
 local e,f=mandatoryRace()
 F.place(f,1,-5000,100); F.place(f,2,0,150); F.place(f,3,-60,150); F.place(f,4,5000,150); for i=1,4 do f.cars[i].lap=10 end; f.cars[3].lap=9
 for i=2,3 do local a=f.cars[i]; a.tyreWear={0.3,0.3,0.3,0.3} end
 e.states[2].persona.strategyRisk=0.3
 F.tick(e,f,0.5)
 local c=e.strategy.cars[2]; c.planned=true; c.stops=0; c.nextLap=-1; c.reaction=false
 e.states[2].nextPerception=0; e.states[3].nextPerception=0; F.tick(e,f,0.2)
 assert(not c.wanted,'nothing before the rival stops')
 f.cars[3].pit=true; F.tick(e,f,0.2)
 assert(c.wanted and c.cause=='cover' and c.mandatoryReq,'cautious strategist covers the rival behind on its mandatory stop')
 assert(lines(e,'strategie: Driver_2 arret obligatoire avance (couverture de Driver_3)')==1,'one line')
 F.tick(e,f,2)
 assert(c.wanted and withdrawn(e,'Driver_2')==0,'never withdrawn while the mandatory stop is owed')
 -- Rival dépanné jusqu'à son stand : pas un arrêt, aucune réaction.
 local d,fd=mandatoryRace()
 F.place(fd,1,-5000,100); F.place(fd,2,0,150); F.place(fd,3,-60,150); F.place(fd,4,5000,150); for i=1,4 do fd.cars[i].lap=10 end; fd.cars[3].lap=9
 for i=2,3 do fd.cars[i].tyreWear={0.3,0.3,0.3,0.3} end
 d.states[2].persona.strategyRisk=0.3; F.tick(d,fd,0.5)
 local cd=d.strategy.cars[2]; cd.planned=true; cd.stops=0; cd.nextLap=-1; cd.reaction=false
 d.pits.cars[3].towedAt=d.time; fd.cars[3].pit=true; F.tick(d,fd,0.2)
 assert(not cd.wanted and not cd.reaction,'no reaction to a towed car')
end
tests.MANDATORY_OVERCUT_REAL_159HB=function()
 local e,f=mandatoryRace(30)
 F.place(f,1,-5000,100); F.place(f,2,0,150); F.place(f,3,60,150); F.place(f,4,5000,150); for i=1,4 do f.cars[i].lap=10 end
 e.states[2].persona.strategyRisk=0.5
 F.tick(e,f,0.5)
 local c=e.strategy.cars[2]; c.planned=true; c.stops=0; c.nextLap=-1; c.reaction=false
 e.states[2].nextPerception=0; e.states[3].nextPerception=0; F.tick(e,f,0.2)
 local pitsWanted=e.pits.cars[2].wanted
 f.cars[3].pit=true; F.tick(e,f,0.2)
 assert(not pitsWanted,'scene: the rules have not called it yet')
 assert(c.mandShiftLap==10+K.strategyOvercutLaps and c.reaction and not c.wanted,'good tyres, rival ahead pits: mandatory stop delayed')
 assert(lines(e,'strategie: Driver_2 arret obligatoire retarde (overcut sur Driver_3)')==1,'one line')
 F.tick(e,f,0.2)
 assert(e.commands[2].stratPlanAt>e.race.progress and not e.pits.cars[2].wanted,'plan point handed to the rules: no call before it')
 -- Le tour visé atteint : l'arrêt obligatoire n'est plus retenu (les règles reprennent leur propre placement).
 for i=1,4 do f.cars[i].lap=10+K.strategyOvercutLaps end; f.leaderLaps=10+K.strategyOvercutLaps; F.tick(e,f,1)
 assert(e.commands[2].stratPlanAt<=e.race.progress+1e-9,'no longer held once the delayed lap is reached')
end
return tests
