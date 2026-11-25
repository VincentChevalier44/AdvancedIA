-- Beta 1.63 (demandes du pilote, 12 novembre au soir) : tour de décélération après le drapeau à damier
-- (src/cooldown.lua, src/applier.lua M.cooldown), IA accidentée qui peut encore rouler (src/incidents.lua rejoin,
-- src/applier.lua M.rejoin), zones jaunes au journal. Noms terminés par _163A. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local A=require('src/applier')
local Cooldown=require('src/cooldown')
local K=C.K
local tests={}
local function logged(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end

tests.K_163A=function()
 assert(K.rejoinStill==3 and K.rejoinWedged==8 and K.rejoinTries==3 and K.rejoinGap==6 and K.rejoinMaxTime==40)
 assert(K.coolPace==0.70 and K.coolDecel==3 and K.coolMinKmh==50 and K.coolRoomRange==150 and K.coolOffset==0.5 and K.coolOffsetRate==0.3)
 assert(C.release=='Beta 2.0.5')
end

-- Tour de décélération : IA arrivée, en course : plafond à 70 % de son allure apprise, atteint sans freinage brusque ;
-- une ligne au journal ; jamais le joueur, jamais aux stands, jamais hors course.
tests.COOLDOWN_PACE_163A=function()
 local e,f=F.scene('C',3)
 local a=F.place(f,2,0,200); a.finished=true
 local s=e.states[2]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=200/3.6 end
 local t=Cooldown.new(); local lines=0
 local function note() lines=lines+1 end
 local dt=1/60; local last=200
 for _=1,60*30 do
  Cooldown.step(t,f,e.states,e.delta.bins,true,dt,note,e.runtimeG)
  local cap=t.cars[2].cap
  if last then assert(last-cap<=K.coolDecel*3.6*dt+1e-6,'no harsh braking ('..last..' -> '..cap..')') end
  last=cap
 end
 assert(t.cars[2].on and math.abs(t.cars[2].cap-0.70*200)<1e-6,'70 % of the learned pace ('..t.cars[2].cap..')')
 assert(lines==1,'one journal line per car')
 assert(not t.cars[1].on and not t.cars[3].on,'cars not finished are never touched')
 a.pit=true; Cooldown.step(t,f,e.states,e.delta.bins,true,dt,note,e.runtimeG); assert(not t.cars[2].on,'pit lane: given back')
 a.pit=false; Cooldown.step(t,f,e.states,e.delta.bins,false,dt,note,e.runtimeG); assert(not t.cars[2].on,'not a race: nothing')
 local p=F.place(f,1,100,200); p.finished=true; p.player=true; p.control=true; p.valid=true
 Cooldown.step(t,f,e.states,e.delta.bins,true,dt,note,e.runtimeG); assert(not t.cars[1].on,'never the player')
 assert(lines==1,'no second line when the same car starts again')
end

-- Sans allure apprise : 70 % de la vitesse au moment de l'arrivée, jamais sous K.coolMinKmh.
tests.COOLDOWN_FALLBACK_163A=function()
 local e,f=F.scene('C',2)
 local a=F.place(f,2,0,60); a.finished=true; e.states[2].paceCount=0
 local t=Cooldown.new()
 for _=1,600 do Cooldown.step(t,f,e.states,e.delta.bins,true,1/60,nil,e.runtimeG) end
 assert(t.cars[2].cap==K.coolMinKmh,'floor ('..t.cars[2].cap..')')
end

-- Voiture encore en course juste derrière : décalage vers le côté libre le plus large (rampe), rendu ensuite.
tests.COOLDOWN_ROOM_163A=function()
 for _,sign in ipairs({-1,1}) do
  local e,f=F.scene('C',3); e.runtimeG.offsetSign=sign; e.runtimeG.sideSign=sign
  for i=1,3 do f.cars[i].sideDot=sign end
  local a=F.place(f,2,0,150); a.finished=true; a.leftWidth=4; a.rightWidth=7
  F.place(f,3,-60,200)
  local t=Cooldown.new()
  for _=1,300 do Cooldown.step(t,f,e.states,e.delta.bins,true,1/60,nil,e.runtimeG) end
  assert(math.abs(t.cars[2].offset-K.coolOffset)<1e-6,sign..': towards the wider side ('..t.cars[2].offset..')')
  F.place(f,3,-3000,200)
  for _=1,300 do Cooldown.step(t,f,e.states,e.delta.bins,true,1/60,nil,e.runtimeG) end
  assert(t.cars[2].offset==0,sign..': back to the line once nobody is behind')
 end
end

-- Applier : plafond écrit, gardé par la restitution pendant le tour, rendu aux stands.
tests.COOLDOWN_APPLIER_163A=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C',3)
 local a=A.new(); assert(A.access(a))
 local t=Cooldown.new(); local c=t.cars[2]; c.on=true; c.cap=140; c.offset=0
 local car=f.cars[2]; car.finished=true
 A.cooldown(a,f,t,e.runtimeG,10)
 assert(host.speedLimits[car.index]==140,'cap written')
 a.cars[2].reset=true; A.restore(a,f,true,10.1)
 assert(host.speedLimits[car.index]==140 and a.cars[2].owned,'restoration leaves the cool-down cap alone')
 c.on=false; A.cooldown(a,f,t,e.runtimeG,11)
 assert(host.speedLimits[car.index]>=K.unlimitedSpeed and a.cars[2].speed==nil,'given back when the lap is over')
end

-- IA accidentée qui peut rouler : redémarrage demandé (une fois par essai), repartie : continue ; jamais dépannée tant
-- qu'elle essaie.
local function stopped(profile)
 local e,f=F.scene(profile or 'C',3); F.place(f,2,-4000,120); F.place(f,3,1000,0); F.tick(e,f,3)
 return e,f,e.incidents.cars[3]
end
tests.REJOIN_RESTART_163A=function()
 local e,f,c=stopped('P')
 assert(c.incident,'scene: stopped')
 F.tick(e,f,1)
 assert(c.rejoining and c.rejoinTries==1 and c.rejoinId==1,'restart requested ('..tostring(c.rejoinTries)..')')
 assert(logged(e,'IA accidentee: redemarrage demande (essai 1)')==1,'journal')
 F.tick(e,f,2); assert(c.rejoinTries==1,'one request per K.rejoinGap s')
 F.place(f,3,1030,40); F.tick(e,f,0.5)
 assert(not c.rejoining and logged(e,'IA accidentee repart (redemarree, 1 essai(s))')==1,'moved off: keeps lapping')
end
tests.REJOIN_GIVES_UP_163A=function()
 local e,f,c=stopped('P')
 local t=0; local last=0
 while t<K.rejoinMaxTime+5 do F.tick(e,f,0.5); t=t+0.5; if c.rejoinTries>last then last=c.rejoinTries end end
 assert(last==K.rejoinTries,'K.rejoinTries attempts ('..last..')')
 assert(not c.rejoining and c.cannot and logged(e,'IA accidentee ne peut plus rouler: ne repart pas apres 3 essai(s)')==1,'gives up once, towed as before')
 assert(e.commands[3].recover,'the ordinary recovery takes over')
end
tests.REJOIN_BROKEN_163A=function()
 local e,f=F.scene('P',3); F.place(f,2,-4000,120); local car=F.place(f,3,1000,0); car.engineLife=0
 F.tick(e,f,4)
 local c=e.incidents.cars[3]
 assert(not c.rejoining and c.rejoinTries==0,'never restarted with a dead engine')
 assert(logged(e,'IA accidentee ne peut plus rouler: moteur casse')==1,'reason logged once')
end
tests.REJOIN_APPLIER_163A=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C',3)
 local a=A.new(); assert(A.access(a))
 local inc={cars={}}; for i=1,f.count do inc.cars[i]={rejoining=false,rejoinId=0} end
 inc.cars[3].rejoining=true; inc.cars[3].rejoinId=1; e.commands[3].recover=true
 local index=f.cars[3].index
 A.rejoin(a,f,inc,e.commands)
 assert(not e.commands[3].recover,'not towed while it tries')
 assert(host.stops[index]==0 and (host.awakes[index] or 0)==1,'restart served once')
 A.rejoin(a,f,inc,e.commands); assert((host.awakes[index] or 0)==1,'never twice for the same request')
end

-- Zones jaunes : une ligne à l'ouverture, une à la fermeture.
tests.YELLOW_ZONE_JOURNAL_163A=function()
 local e,f=F.scene('P',3); e.run.yellowEnabled=true; F.place(f,2,-4000,120); F.place(f,3,1000,0)
 F.tick(e,f,3)
 assert(logged(e,'zone jaune ouverte: ')==1,'opened once')
 local c=e.incidents.cars[3]; local at=c.zoneOpenAt; F.tick(e,f,1); assert(c.zoneOpen and c.zoneOpenAt==at,'opened once, not every frame')
 F.place(f,3,1000,150); F.tick(e,f,e.run.yellowHold+K.rejoinStill+5)
 assert(logged(e,'zone jaune fermee: ')==1,'closed once')
end
return tests
