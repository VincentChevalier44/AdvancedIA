local F=require('tests/fixture')
local C=require('src/config')
local U=require('src/util')
local E=require('src/engine')
local D=require('src/director')
local P=require('src/perception')
local Flash=require('src/flash')
local Classes=require('src/classes')
local Zones=require('src/zones')
local Persona=require('src/persona')
local Snapshot=require('src/snapshot')
local Applier=require('src/applier')
local Caps=require('src/caps')
local Calibration=require('src/calibration')
local tests={}
local function yielding(e,i) assert(F.yielding(e.states[i or 2].state),'expected yield, got '..e.states[i or 2].state) end
local function notYielding(e,i) assert(not F.yielding(e.states[i or 2].state),'unexpected yield') end
local function setup(profile,count) local e,f=F.scene(profile or 'J',count); e.p.personalLineJitter=0; return e,f end
local function flashEvent(flash,now)
 assert(not Flash.step(flash,true,now)); assert(not Flash.step(flash,false,now+0.2))
 assert(not Flash.step(flash,true,now+0.4)); assert(Flash.step(flash,false,now+0.6))
end
local function request(e,f,count)
 local flash=e.flash; flash.eventId=flash.eventId+1; flash.eventCount=count or 2
 F.tick(e,f,0.15)
 return Flash.dispatch(flash,f.cars,f.count,1,e.perception,e.states,e.p,e.g,e.profile,e.time)
end
tests.T01=function()
 local e,f=setup(); F.rear(e,f,45,30); F.tick(e,f,4); yielding(e); assert(e.states[2].offset>0.05)
 F.place(f,3,40,130); F.tick(e,f,10); assert(e.states[2].state=='DRIVE'); assert(math.abs(e.states[2].offset)<0.02)
end
tests.T02=function()
 local e,f=setup(); F.rear(e,f,45,30); f.cars[2].yawRate=0.5; F.tick(e,f,4); notYielding(e); assert(e.states[2].pendingAt>0)
 f.cars[2].yawRate=0; F.tick(e,f,2); yielding(e)
end
tests.T03=function()
 local e,f=setup('J',4); F.rear(e,f,45,30); F.place(f,4,0,100,2); F.tick(e,f,5); assert(math.abs(e.states[2].offset)<1e-9)
end
tests.T04=function()
 local e,f=setup(); F.rear(e,f,20,15); F.tick(e,f,5); yielding(e); local early=e.commands[2].level
 F.tick(e,f,14); assert(e.commands[2].level<early-0.02)
 F.tick(e,f,11); assert(e.states[2].ignoreUntil>e.time); assert(e.states[2].state=='YIELD_OUT' or e.states[2].state=='DRIVE')
end
tests.T05=function()
 local e,f=setup(); F.rear(e,f,8,0); F.tick(e,f,3); notYielding(e); F.tick(e,f,4); yielding(e)
end
tests.T06=function()
 local e,f=setup(); F.front(e,f,35,30); F.tick(e,f,1); assert(F.passing(e.states[2].state)); assert(e.states[2].targetSide==-1)
 F.place(f,3,-40,100); F.tick(e,f,8); assert(e.states[2].state=='DRIVE'); assert(math.abs(e.states[2].offset)<0.02)
end
tests.T07=function()
 local e,f=setup(); F.front(e,f,35,30); e.states[3].state='YIELD_HOLD'; e.states[3].targetSide=1
 F.tick(e,f,1); assert(F.passing(e.states[2].state)); assert(e.states[2].targetSide==-1)
end
tests.T08=function()
 local e,f=setup('J',6); F.front(e,f,35,30)
 for i=4,6 do F.place(f,i,(i-2)*50,100) end
 F.tick(e,f,1); local side=e.states[2].targetSide
 F.place(f,3,-40,100); for i=4,6 do F.place(f,i,35+(i-4)*40,100) end; F.tick(e,f,1); assert(e.states[2].target==4); assert(e.states[2].targetSide==side)
end
tests.T09=function()
 local e,f=setup('J',4); F.front(e,f,35,30); F.tick(e,f,1); F.place(f,4,-20,180)
 F.tick(e,f,4); assert(e.states[2].aborts>0 or F.yielding(e.states[2].state))
end
tests.T10=function()
 local e,f=setup(); F.front(e,f,35,30); F.tick(e,f,2)
 local s=e.states[2]; local old=s.offset
 F.place(f,3,0,100,2); F.tick(e,f,1); assert(s.offset<=old+1e-9); assert(s.state=='OVT_HOLD')
end
tests.T11=function()
 local e,f=setup(); F.rear(e,f,45,30); e.zones={{from=0.99,to=0.01,noYield=true,noOvertake=true,maxOffset=0.2,note=''}}
 F.tick(e,f,5); notYielding(e); assert(math.abs(e.states[2].offset)<=0.2)
end
tests.T12=function()
 local p=C.defaults('J'); p.section_human=true; local slow,fast={},{}
 for i=1,100 do
  local a={}; Persona.fill(a,123,i,'J',p)
  if not slow.paceRank or a.paceRank<slow.paceRank then slow=a end
  if not fast.paceRank or a.paceRank>fast.paceRank then fast=a end
 end
 assert(slow.laneBias>fast.laneBias); assert(slow.laneBias>0); assert(slow.laneBias<=p.laneBiasMax)
end
tests.T13=function()
 local e,f=setup(); e.states[2].lapseAt=e.time+0.1; local normal=e.commands[2].level
 F.tick(e,f,1); assert(e.commands[2].level<normal*0.97); assert(e.states[2].lapseUntil>e.time)
 F.tick(e,f,4); assert(e.states[2].lapseUntil==0)
end
tests.T14=function()
 local e,f=setup(); F.front(e,f,40,80); f.cars[3].kmh=0; f.cars[3].speed=0; f.cars[3].stopped=5
 F.tick(e,f,1); assert(e.states[2].state=='AVOID'); assert(e.commands[2].level<0.9); assert(math.abs(e.states[2].offset)>0)
end
tests.T15=function()
 local e,f=setup(); F.front(e,f,30,20); f.cars[3].slip=50; F.tick(e,f,1); assert(e.states[2].state=='AVOID')
 F.place(f,3,4,100,2); F.tick(e,f,0.4); F.place(f,2,0,60); F.tick(e,f,0.4); assert(e.states[2].state=='CALM')
end
tests.F01=function()
 local e,f=setup(); e.p.flashObliviousPct=0; e.p.yieldBehindMargin=30; F.rear(e,f,40,15,1)
 request(e,f); F.tick(e,f,1.6); yielding(e)
end
tests.F02=function()
 -- Beta 1.29 : à moins de 60 m, un joueur retenu derrière est compris ; F02 se joue donc à 100 m.
 local e,f=setup(); e.p.flashObliviousPct=0; F.rear(e,f,100,2,1); request(e,f); F.tick(e,f,3); notYielding(e); assert(e.flash.requests[2].untilTime>e.time)
end
tests.F03=function()
 local e,f=setup(); e.p.flashObliviousPct=0; F.rear(e,f,20,20,1); request(e,f,3); F.tick(e,f,2); yielding(e); assert(e.states[2].urgent)
end
tests.F04=function()
 local e,f=setup('J',6); e.p.flashObliviousPct=0; F.place(f,1,-50,140)
 for i=2,6 do F.place(f,i,(i-2)*15,100) end
 assert(request(e,f)==3); local a,b,c=e.flash.requests[2],e.flash.requests[3],e.flash.requests[4]
 assert(math.abs(b.readyAt-a.readyAt-0.5)<1e-9); assert(math.abs(c.readyAt-b.readyAt-0.5)<1e-9); assert(e.flash.requests[5].event==0)
end
tests.F05=function()
 local e,f=setup(); F.rear(e,f,40,20,1); e.p.flashObliviousPct=40
 local id=1; while U.unit(e.g.seed,2,id)>=0.4 do id=id+1 end
 e.flash.eventId=id-1; assert(request(e,f)==0); F.tick(e,f,0.5); assert(request(e,f)==1); assert(e.flash.requests[2].second)
end
tests.F06=function()
 local e,f=setup(); e.p.flashObliviousPct=0; F.rear(e,f,40,20,1); f.cars[2].yawRate=0.5
 request(e,f); F.tick(e,f,3); notYielding(e); f.cars[2].yawRate=0; F.tick(e,f,1); yielding(e)
end
tests.F07=function()
 local e,f=setup(); F.place(f,1,0,130,2); F.place(f,2,0,100); assert(request(e,f)==0)
end
tests.F08=function() local a=Flash.new(); Flash.step(a,true,0); assert(not Flash.step(a,false,5)); assert(a.eventId==0) end
tests.F09=function()
 local e,f=setup('J',4); e.p.flashObliviousPct=0; F.front(e,f,30,25); F.tick(e,f,1)
 F.place(f,3,0,100,2); F.place(f,1,-45,150); request(e,f); local offset=e.states[2].offset; F.tick(e,f,1)
 assert(e.states[2].state=='OVT_HOLD'); assert(math.abs(e.states[2].offset-offset)<1e-9)
 F.place(f,3,-50,100,2); F.tick(e,f,1.5); yielding(e)
end
tests.F10=function()
 local a=Flash.new(); Flash.learn(a,0); local sig={}; assert(Flash.sampleLearn(a,sig,7)=='')
 local e,f=setup(); e.g.flashField=''; F.rear(e,f,40,30); F.tick(e,f,4); yielding(e)
end
tests.F11=function()
 local e,f=setup('C'); e.p.flashObliviousPct=0; F.rear(e,f,40,30,1); assert(request(e,f)==0); F.tick(e,f,4); notYielding(e)
end
tests.F12=function()
 local e,f=setup('C'); e.p.flashObliviousPct=0; F.rear(e,f,40,30,1); f.cars[1].lap=2; assert(request(e,f)==1); F.tick(e,f,2); yielding(e)
end
tests.Q01=function() local e,f=setup('Q'); F.rear(e,f,150,70,1); F.tick(e,f,6); yielding(e); assert(e.p.yieldOffset==0.8 and e.p.yieldDetectBehind==200) end
tests.Q02=function()
 local e,f=setup('Q',5); F.place(f,1,-40,150); for i=2,5 do F.place(f,i,(i-2)*30,100) end
 F.tick(e,f,5); for i=2,5 do assert(e.states[i].targetSide==1); assert(e.states[i].offset>=0) end
end
tests.Q03=function() local e,f=setup('Q'); F.rear(e,f,25,30); f.cars[2].lap=0; F.tick(e,f,4); yielding(e); assert(e.states[2].targetSide==1) end
tests.R01=function()
 -- Pas de manœuvre pendant l'attente du départ (1 s par défaut depuis la Beta 1.27), prudence et agressivité de départ ensuite.
 local e,f=setup('C',21); e.startedAt=e.time; F.tick(e,f,e.run.startDelay*0.8); for i=2,21 do assert(e.states[i].state=='IDLE'); assert(math.abs(e.commands[i].offset)<1e-9) end
 F.tick(e,f,e.run.startDelay+3); assert(e.commands[2].caution>e.p.caution); assert(e.commands[2].aggression<e.p.aggressionPct/100*0.95)
end
tests.R02=function()
 local e,f=setup('C'); F.rear(e,f,25,30); F.tick(e,f,5); notYielding(e)
 local a,b=setup('C'); F.front(a,b,35,25); F.tick(a,b,1); assert(a.states[2].state=='OVT_ARM')
end
tests.R03=function()
 local found=false
 for seed=1,20 do
  local e,f=setup('C'); e.g.seed=seed; E.changed(e); F.tick(e,f,0.1); e.returning=false
  -- Beta 1.47 : suiveur nettement d'un côté (la défense ne se décide plus sur un écart latéral quasi nul).
  F.rear(e,f,8,8); f.cars[3].x=0.8; f.cars[3].splineLat=0.8; F.tick(e,f,1)
  if e.states[2].state=='DEFEND' then found=true; assert(math.abs(e.states[2].offset)<=0.35); F.tick(e,f,4); assert(e.states[2].state~='DEFEND'); assert(e.states[2].defendUsed); break end
 end
 assert(found)
end
tests.R04=function() local e,f=setup('C'); F.place(f,3,0,110,2); F.place(f,2,0,100); F.tick(e,f,4); assert(e.states[2].state~='DEFEND'); assert(e.states[2].offset==0) end
tests.R05=function()
 local e,f=setup('C'); e.p.overtakeSide='auto'; F.front(e,f,10,25); f.cars[2].yawRate=0.1; f.cars[3].yawRate=0.1; F.tick(e,f,1); assert(e.states[2].targetSide==1)
end
tests.R06=function()
 local e,f=setup('C',5); F.front(e,f,35,25); F.tick(e,f,0.7); assert(e.states[2].state=='OVT_ARM')
 F.place(f,4,0,125,-2); F.place(f,5,0,125,2); local offset=e.states[2].offset; F.tick(e,f,1); assert(e.states[2].offset==offset)
end
tests.R07=function()
 local e,f=setup('C'); F.place(f,3,4,100,2); F.tick(e,f,0.4); F.place(f,2,0,60); F.tick(e,f,0.4); assert(e.states[2].state=='CALM')
 F.tick(e,f,2); assert(e.states[2].state=='CALM'); F.tick(e,f,3); assert(e.states[2].state~='CALM')
end
tests.R08=function() local e,f=setup('C',4); F.rear(e,f,25,20); f.cars[3].lap=2; F.place(f,4,10,102); F.tick(e,f,4); yielding(e); assert(e.states[2].directionCount<=2) end
tests.R09=function() local e,f=setup('C'); f.finished=true; F.tick(e,f,1); for i=1,f.count do assert(not e.commands[i].active) end end
tests.R10=function() local e,f=setup('C'); F.front(e,f,10,30); F.tick(e,f,1); f.session=1; f.started=false; F.tick(e,f,0.2); assert(e.states[2].state=='IDLE'); assert(e.states[2].target==0); assert(e.states[2].pendingAt==0) end
tests.E01=function()
 local e,f=setup('C',41); e.p.enduranceOverlay=true
 for _=1,360 do F.tick(e,f,1); e.time=e.time+59 end
 assert(e.time>=21600); assert(#e.states==61); assert(#e.states[2].pace==400); assert(e.log.count<=200); assert(e.errors==0)
end
tests.E02=function()
 local e,f=setup('C'); e.p.enduranceOverlay=true; local reaction=e.states[2].persona.reaction; local level=e.states[2].persona.stintSwing; local team=e.states[2].persona.levelSpread
 f.cars[2].pit=true; F.tick(e,f,1); f.cars[2].pit=false; F.tick(e,f,0.1)
 assert(e.states[2].stint==1); assert(e.states[2].persona.reaction~=reaction); assert(e.states[2].persona.stintSwing~=level); assert(e.states[2].persona.levelSpread==team)
end
tests.E03=function()
 local e,f=setup('C'); e.p.enduranceOverlay=true; F.rear(e,f,35,30); f.cars[3].lap=2
 f.cars[2].pit=true; F.tick(e,f,0.1); f.cars[2].pit=false; F.tick(e,f,2); assert(e.states[2].state=='IDLE')
 e.pitSpline=-1; F.tick(e,f,4); yielding(e)
end
tests.E04=function()
 local e,f=setup('C'); e.p.enduranceOverlay=true; F.tick(e,f,2); local level,caution=e.commands[2].level,e.commands[2].caution
 f.wet=1; F.tick(e,f,2); assert(e.commands[2].level<level*0.95); assert(e.commands[2].caution>caution*1.3)
end
tests.E05=function()
 local e,f=setup('C'); e.p.enduranceOverlay=true; e.time=5500; F.tick(e,f,0.1); assert(e.states[2].fatigue==1.3); assert(e.states[2].fatigue<=2)
end
tests.E06=function() local e,f=setup('C',61); F.tick(e,f,1); assert(e.activeCount==60); assert(#e.commands==61) end
tests.M01=function() local e,f=setup('C'); e.p.multiClass=true; F.rear(e,f,80,20); e.states[2].class=3; e.states[3].class=1; e.states[2].classified=true; e.states[3].classified=true; F.tick(e,f,3); yielding(e) end
tests.M02=function() local e,f=setup('C'); e.p.multiClass=true; F.rear(e,f,30,20); e.states[2].class=1; e.states[3].class=3; e.states[2].classified=true; e.states[3].classified=true; F.tick(e,f,5); notYielding(e) end
tests.M03=function()
 local e,f=setup('C',4); e.p.multiClass=true; F.rear(e,f,40,10); F.place(f,4,20,101); e.states[2].class=3; e.states[3].class=1; e.states[4].class=3; for k=2,4 do e.states[k].classified=true end
 F.tick(e,f,3); notYielding(e); f.cars[3].speed=130/3.6; f.cars[3].kmh=130; F.tick(e,f,3); yielding(e)
end
tests.M04=function()
 local e,f=setup('C'); local classes=Classes.new(); e.p.classPatterns='car_2:1,car_3:4'; assert(Classes.configure(classes,e.p))
 e.states[2].class=4; Classes.update(classes,f.cars,e.states,f.count,e.p,0); assert(e.states[2].class==1 and e.states[3].class==4)
end
tests.M05=function()
 for class=2,3 do local e,f=setup('C'); e.p.multiClass=true; F.rear(e,f,60,20); e.states[2].class=class; e.states[3].class=class-1; e.states[2].classified=true; e.states[3].classified=true; F.tick(e,f,3); yielding(e) end
end
tests.M06=function()
 local e,f=setup('C'); e.p.multiClass=true; F.front(e,f,15,25); e.states[2].class=1; e.states[3].class=3; e.states[2].classified=true; e.states[3].classified=true; f.cars[2].yawRate=0.4
 F.tick(e,f,2); assert(not F.passing(e.states[2].state)); f.cars[2].yawRate=0; F.tick(e,f,1); assert(F.passing(e.states[2].state))
end
tests.L01=function() local e,f=setup('C'); F.rear(e,f,100,20); f.cars[3].lap=2; F.tick(e,f,3); yielding(e); assert(e.states[2].state~='DEFEND') end
tests.L02=function() local e,f=setup('C'); F.rear(e,f,210,20); f.cars[3].lap=3; F.tick(e,f,3); yielding(e) end
tests.L03=function()
 local e,f=setup('C'); F.rear(e,f,60,20); f.cars[3].lap=2; f.cars[2].yawRate=0.4; F.tick(e,f,3); assert(e.states[2].bluePending); assert(e.states[2].offset==0)
 -- Beta 1.62 (« sans freiner sur la trajectoire ») : en attente dans le virage, plus de lever de pied sur la ligne.
 local level=e.commands[2].level; f.cars[3].lap=0; F.tick(e,f,2); assert(e.commands[2].level<=level*1.04)
end
tests.L04=function() local e,f=setup('C'); F.rear(e,f,8,10); f.cars[3].lap=2; F.tick(e,f,2); assert(e.states[2].state~='DEFEND') end
tests.L05=function()
 local e,f=setup('C',4); F.front(e,f,15,3); f.cars[3].lap=2; F.place(f,4,25,102); f.cars[4].lap=2; F.tick(e,f,4); assert(not F.passing(e.states[2].state))
end
tests.L06=function() local e,f=setup('C'); F.rear(e,f,40,20); f.cars[3].lapValid=false; F.tick(e,f,4); notYielding(e); assert(e.states[2].state~='YIELD_HOLD') end
tests.L07=function() local e,f=setup('C'); F.rear(e,f,30,20); f.cars[2].lap=2; f.cars[3].lap=1; F.tick(e,f,4); notYielding(e) end
tests.P01=function() local e,f=setup(); F.front(e,f,40,30); F.place(f,1,35,0); f.cars[1].stopped=10; F.tick(e,f,1); assert(e.states[2].state=='AVOID'); assert(e.states[2].target==1) end
tests.P02=function() local e,f=setup(); F.rear(e,f,20,50,1); f.cars[1].pit=true; F.tick(e,f,5); notYielding(e); assert(e.states[2].target~=1) end
tests.P03=function() local e,f=setup(); F.place(f,1,0,100,2); F.place(f,2,0,100); F.tick(e,f,3); assert(e.states[2].offset==0) end
tests.P04=function() local e,f=setup(); f.replay=true; F.tick(e,f,1); assert(e.guard=='replay'); assert(not e.commands[2].active) end
tests.P05=function() local e,f=setup(); F.rear(e,f,30,30,1); f.cars[1].lz=-1; F.tick(e,f,4); notYielding(e) end
tests.S01=function() local e,f=setup(); f.length=0; F.tick(e,f,1); assert(e.guard=='spline'); assert(not e.commands[2].active) end
tests.S02=function() local e,f=setup(); f.online=true; F.tick(e,f,1); assert(e.guard=='online'); assert(not e.commands[2].active) end
tests.S03=function() local e,f=setup(); F.rear(e,f,30,30); F.tick(e,f,4); f.cars[2].teleport=true; F.tick(e,f,0.1); assert(e.states[2].target==0); assert(e.states[2].offset==0) end
tests.S04=function() local e,f=setup(); for _,dt in ipairs({0,-1,10,0/0,math.huge}) do assert(not E.step(e,f,dt)); assert(not e.commands[2].active); assert(e.states[2].velocity==0) end end
tests.S05=function()
 local e,f=setup(); local a=Applier.new(); a.allowed=true; local stores={}; ac.store=function(k,v) stores[k]=v end; ac.load=function(k) return stores[k] end
 a.cars[2].owned=true; a.cars[2].id=f.cars[2].id; a.cars[2].offset=0.6; a.cars[2].originalLevel=0.85
 Applier.checkpoint(a,f,true); local other=Applier.new(); Applier.recover(other,f); assert(other.cars[2].reset and other.cars[2].offset==0.6); assert(other.cars[2].originalLevel==0.85)
end
tests.S06=function()
 local p,errors=C.validate('J',{levelPct=0/0,aggressionPct='100',caution=math.huge,unknown=123,classPatterns='../../evil:1'})
 assert(errors>0 and p.levelPct==95 and p.aggressionPct==55 and p.caution==1.6 and p.classPatterns==''); assert(p.unknown==nil)
 local g,n=C.validateGlobals({seed=math.huge,enabled='yes',offsetSign=0.5}); assert(n>0 and g.enabled==true and g.offsetSign==0)
end
tests.S07=function()
 local calls=0; local cap=Caps.new({present=function() return true end,write=function() calls=calls+1; return false end})
 for _=1,10 do Caps.call(cap,'offset',1,0) end; assert(calls==3 and not cap.offset.available and cap.offset.reason=='failures')
end
tests.S08=function()
 local s=Snapshot.new(); ac.getSim=function() return {carsCount=0} end; ac.getTrackID=function() return 'test' end
 ac.getAppWindows=function() return {{name='AI Whisperer',visible=true}} end
 Snapshot.read(s,1/60,1); assert(s.conflict=='ai whisperer')
end
tests.S09=function()
 local e,f=setup(); F.rear(e,f,30,30); F.tick(e,f,5); local old=e.states[2].offset; assert(old>0.1)
 E.select(e,'Q'); F.tick(e,f,1/60); assert(e.states[2].target==0); assert(math.abs(e.states[2].offset-old)<0.02); assert(e.states[2].pendingAt==0)
end
tests.S10=function()
 for _,profile in ipairs(C.profiles) do for _,extreme in ipairs({'min','max'}) do
  local input=C.defaults(profile); for _,s in ipairs(C.schema) do if s.min then input[s.key]=s[extreme] end end
  local p=C.validate(profile,input); for _,s in ipairs(C.schema) do if s.min then assert(p[s.key]>=s.min and p[s.key]<=s.max) end end
  local e,f=setup(profile); e.profiles[profile]=p; E.changed(e); F.rear(e,f,30,30); F.tick(e,f,3)
 end end
end
local function rawCar()
 return {position={x=0,y=0,z=0},look={x=0,z=1},side={x=-1,z=0},velocity={x=0,z=30},speedKmh=108,
 isConnected=true,isActive=true,isAIControlled=true,isUserControlled=false,isRemote=false,physicsAvailable=true,
 wheelsOutside=0,splinePosition=0,lapCount=0,aabbSize={x=1.85,z=4.4},brake=0,gas=1,aiLevel=0.9,aiAggression=0.5}
end
local function mockSnapshot(raw,count)
 ac.getCar=function(i) return i<count and raw or nil end
 ac.getSim=function() return {carsCount=count,trackLengthM=10000,isSessionStarted=true,gameTime=1} end
 ac.getTrackAISplineSides=function() return {x=6,y=6} end
 ac.getTrackID=function() return 'test' end; ac.getCarID=function() return 'car' end; ac.getDriverName=function() return 'driver' end
 ac.getAppWindows=function() return {} end
end
tests.S11=function()
 local raw=rawCar(); raw.aabbSize={x=1e20,z=-5}; mockSnapshot(raw,2); local s=Snapshot.new(); Snapshot.read(s,1/60,0)
 assert(s.cars[2].length==4.4 and s.cars[2].width==1.85)
end
tests.S12=function()
 local e,f=setup(); F.rear(e,f,30,30); f.cars[3].lz=-1; F.tick(e,f,4); notYielding(e)
 f.cars[3].lz=1; f.cars[3].spline=0.5; F.tick(e,f,4); notYielding(e)
end
tests.S13=function() local e,f=setup('J',61); F.tick(e,f,0.2); f.count=0; F.tick(e,f,0.2); assert(e.activeCount==0); f.count=5; F.tick(e,f,1); assert(e.errors==0) end
tests.S14=function()
 local raw=rawCar(); mockSnapshot(raw,2); local frame=Snapshot.new(); Snapshot.read(frame,1/60,0)
 frame.cars[1].valid=false
 local calls=0; physics.allowed=function() return true end
 physics.setAISplineOffset=function(i,value) assert(i==1 and value==0); calls=calls+1 end
 local a=Applier.new(); a.allowed=true; local s=a.cars[2]; s.owned=true; s.id=frame.cars[2].identity; s.offset=0.5
 Applier.restore(a,frame); Applier.restore(a,frame); assert(calls==1 and not s.owned)
end
tests.ZONES_SECURITY=function()
 local text='return {{from=0.9,to=0.1,noYield=true,maxOffset=0.3,note="épingle"}}'; local z=assert(Zones.parse(text)); local o={}
 assert(Zones.at(z,0.95,o).noYield); assert(Zones.at(z,0.05,o).maxOffset==0.3); assert(not Zones.at(z,0.5,o).noYield)
 assert(Zones.parse(Zones.export(z)))
 for _,bad in ipairs({'return (function() return {} end)()', 'return {{from=0,to=1,x=1}}','return {{from=0/0,to=1}}','return {{from=0,to=1,note="\\x"}}',string.rep(' ',65537),'return {} evil()'}) do assert(not Zones.parse(bad)) end
end
tests.RNG_DETERMINISM=function()
 local a,b={},{}; local p=C.defaults('J'); Persona.fill(a,42,4,'J',p); Persona.fill(b,42,4,'J',p)
 for k,v in pairs(a) do assert(b[k]==v) end
 assert(U.imul(2147483647,2147483647)==1); assert(U.unit(42,4,5)>=0 and U.unit(42,4,5)<1)
end
tests.FLASH_CALIBRATION=function()
 local a=Flash.new(); Flash.learn(a,0); local signals={highBeams=false}
 for i=1,360 do signals.highBeams=i%30<10; Flash.sampleLearn(a,signals,i/60) end
 assert(a.learned=='highBeams')
 local b=Flash.new(); flashEvent(b,1); assert(b.eventId==1)
end
tests.CALIBRATION_SAFETY=function()
 local e,f=setup('J',3); F.place(f,1,-1000,100); F.place(f,2,0,100); F.place(f,3,120,100)
 local cap=Caps.new({present=function() return true end,write=function(_,index,value) assert(index~=0); assert(math.abs(value)<=0.5); return true end})
 local c=Calibration.new(); e.g.offsetSign=0; e.g.sideSign=0
 Calibration.step(c,f,cap,e.g,0); assert(c.index==2); f.cars[2].x=0.5; f.cars[2].sideDot=1
 Calibration.step(c,f,cap,e.g,3.1); assert(c.phase=='ready' and e.g.offsetSign==1 and e.g.sideSign==1)
end
tests.APPLIER_FILTERS=function()
 local e,f=setup(); local writes={}; physics.setAILevel=function(i,v) writes[#writes+1]={i=i,v=v} end
 physics.setAIAggression=function() end; physics.setAICaution=function() end; physics.setAISplineOffset=function() end
 local a=Applier.new(); a.allowed=true
 e.commands[2].active=true; e.commands[2].offset=0.3
 for i=1,60 do Applier.apply(a,f,e.commands,e.g,i/60) end
 assert(#writes<=5); for _,w in ipairs(writes) do assert(w.i~=0 and w.v<=1) end
 f.replay=true; local old=#writes; Applier.apply(a,f,e.commands,e.g,2); assert(#writes==old)
end
tests.APPLIER_CDATA=function()
 local ffi=require('ffi'); local f=ffi.cast('int(*)(int)',function(x) return x end)
 assert(Applier.callable(f)); assert(not Applier.callable(ffi.new('int',3))); assert(not Applier.callable(ffi.cast('int(*)(int)',nil))); f:free()
end
tests.LOG_BOUNDS=function()
 local q=U.newLog(200,20,5)
 for i=1,1000 do U.log(q,0,'WARN','flood'..i,0) end
 assert(q.count==20)
 for i=1,300 do U.log(q,i,'INFO','row',0) end
 assert(q.count<=200)
end
tests.FUZZ_10000=function()
 local raw=rawCar(); mockSnapshot(raw,61); local frame=Snapshot.new(); local g=C.validateGlobals(C.globalDefaults)
 g.offsetSign=1; g.sideSign=1; local e=E.new(g,{J=C.defaults('J'),P=C.defaults('P'),Q=C.defaults('Q'),C=C.defaults('C')})
 for _,profile in pairs(e.profiles) do for _,group in ipairs(C.sections) do profile['section_'..group]=true end end
 local rng=777
 for step=1,10000 do
  local r; rng,r=U.random(rng)
  raw.position.x=r<0.01 and 0/0 or r<0.02 and math.huge or r*100
  raw.position.z=r*1000; raw.speedKmh=r<0.03 and -1 or r*300; raw.splinePosition=r<0.04 and 5 or r
  raw.lapCount=r<0.05 and -1 or math.floor(r*10); raw.aabbSize.x=r*50; raw.wheelsOutside=r>0.9 and 4 or 0
  Snapshot.read(frame,1/60,step/60); E.step(e,frame,step%100==0 and 10 or 1/60)
  assert(e.errors==0); for i=1,frame.count do assert(e.states[i].offset==e.states[i].offset and math.abs(e.states[i].offset)<=0.95) end
 end
end
return tests
