local F=require('tests/fixture')
local E=require('src/engine')
local D=require('src/director')
local C=require('src/config')
local Caps=require('src/caps')
local A=require('src/applier')
local Cal=require('src/calibration')
local P=require('src/perception')
local Flash=require('src/flash')
local Z=require('src/zones')
local tests={}
tests.GEOMETRY_FIXTURES=function()
 local e,f=F.scene('J',4); local r={}
 F.place(f,2,0,100); F.place(f,3,40,120)
 P.relative(f.cars[2],f.cars[3],f.length,r); assert(r.same and math.abs(r.gap-35.6)<1e-8)
 -- Bouclage : les positions physiques restent cohérentes de part et d'autre du zéro.
 f.cars[2].spline=0.999; f.cars[3].spline=0.003
 P.relative(f.cars[2],f.cars[3],f.length,r); assert(r.same)
 -- Ovale : cap tournant et voisin dans le même virage.
 f.cars[2].spline=0; f.cars[3].spline=0.004; f.cars[3].lx=math.sin(0.1); f.cars[3].lz=math.cos(0.1)
 P.relative(f.cars[2],f.cars[3],f.length,r); assert(r.same)
 -- Épingle : tronçon géographiquement voisin, progression incohérente.
 f.cars[3].spline=0.5; P.relative(f.cars[2],f.cars[3],f.length,r); assert(not r.same)
 -- Piste étroite : borne géométrique effective.
 local a,s=f.cars[2],e.states[2]; a.leftWidth=1.2; a.rightWidth=1.2; a.corner=1; s.zone.maxOffset=1
 for _=1,600 do D.lateral(s,0.95,e.perception.rows[2],a,e.p,e.g,1/60,e.time); e.time=e.time+1/60 end
 assert(math.abs(s.offset)<0.24)
end
tests.RESET_OCCUPIED_SIDE=function()
 local e,f=F.scene('J',4); F.place(f,2,0,100); F.place(f,3,0,100,-2); F.place(f,4,1000,100)
 local calls=0; physics.setAISplineOffset=function(_,v) assert(v==0); calls=calls+1 end
 local a=A.new(); a.allowed=true; a.g=e.g; a.offsetSign=1
 local s=a.cars[2]; s.owned=true; s.id=f.cars[2].id; s.offset=0.6
 A.restore(a,f); assert(calls==0 and s.owned)
 f.cars[3].valid=false; A.restore(a,f); A.restore(a,f); assert(calls==1 and not s.owned)
end
tests.CALIBRATION_ABORT_OCCUPIED=function()
 local e,f=F.scene('J',4); F.place(f,1,-1000,100); F.place(f,2,0,100); F.place(f,3,120,100); F.place(f,4,1000,100)
 local writes=0; local cap=Caps.new({present=function() return true end,write=function(_,_,v) writes=writes+1; assert(v==0 or v==0.5); return true end})
 local c=Cal.new(); e.g.offsetSign=0; e.g.sideSign=0
 Cal.step(c,f,cap,e.g,0); assert(writes==1)
 f.cars[2].x=0.5; F.place(f,4,0,100,-1.5)
 Cal.step(c,f,cap,e.g,1); assert(writes==1 and c.index==2 and c.phase=='waiting_reset')
 assert(not Cal.cancel(c,f,cap,e.g)); assert(writes==1)
 f.cars[4].valid=false; Cal.step(c,f,cap,e.g,4); assert(writes==2 and c.index==0)
end
tests.TIME_WRAP=function()
 local e,f=F.scene('C'); e.time=86399.99; local s=e.states[2]
 s.lastContact=e.time-6000; s.stintStart=e.time-2000; s.errorUntil=e.time+3; s.lapseAt=e.time+50
 E.step(e,f,1/60)
 assert(e.time<1 and e.rebaseDelta==86400); assert(s.errorUntil>2 and s.errorUntil<4)
 assert(math.abs((e.time-s.lastContact)-6000-1/60)<1e-6)
 assert(math.abs((e.time-s.stintStart)-2000-1/60)<1e-6)
 assert(s.lapseAt>49)
end
tests.PROFILE_ISOLATION=function()
 local e,f=F.scene('J'); e.profiles.J.levelPct=73; e.profiles.Q.levelPct=108
 E.select(e,'Q'); F.tick(e,f,0.1); assert(e.p.levelPct==108 and e.profiles.J.levelPct==73)
 f.session=1; f.type=3; f.time=0; F.tick(e,f,0.1); assert(e.profile=='Q' and e.p.levelPct==108)
 e.g.autoProfile=true; F.tick(e,f,0.1); assert(e.profile=='C' and e.p.levelPct==100)
end
tests.CAR_QUARANTINE=function()
 local e,f=F.scene('J'); local original=D.step
 D.step=function(engine,i,dt,now) if i==2 then error('injected per-car fault') end return original(engine,i,dt,now) end
 for attempt=1,3 do E.step(e,f,1/60); e.time=e.time+5.1 end
 assert(e.states[2].excluded and e.states[2].errorCount==3); assert(e.commands[3].active)
 E.changed(e); E.step(e,f,1/60); assert(e.states[2].excluded)
 D.step=original; f.session=1; E.step(e,f,1/60); assert(not e.states[2].excluded)
 -- Beta 1.4 : toutes les voitures pilotées en un seul appel protégé (cache JIT agrandi) : même isolation, dans le même
 -- ordre ; les voitures suivantes sont pilotées dans la même image.
 local e2,f2=F.scene('J',4); e2.batchCars=true; local order={}
 D.step=function(engine,i,dt,now) order[#order+1]=i; if i==2 then error('injected per-car fault') end return original(engine,i,dt,now) end
 for attempt=1,3 do for k=#order,1,-1 do order[k]=nil end; E.step(e2,f2,1/60); e2.time=e2.time+5.1 end
 D.step=original
 assert(e2.states[2].excluded and e2.states[2].errorCount==3 and e2.errors==3,'faulty car quarantined, one error per frame')
 assert(#order==4 and order[1]==1 and order[2]==2 and order[3]==3 and order[4]==4 and e2.commands[3].active and e2.commands[4].active,'driving resumes with the next car, same frame, same order')
end
tests.SCHEMA_MIGRATION=function()
 local p=C.defaults('J'); p.schemaVersion=0; p.levelPct=80; assert(C.validate('J',p).levelPct==80)
 -- Beta 1.35 : version future (retour à une version précédente) : réglages gardés, numéro le plus haut gardé.
 p.schemaVersion=999; local q,n=C.validate('J',p); assert(q.levelPct==80 and n==0 and q.schemaVersion==999)
 p.schemaVersion=2.5; q,n=C.validate('J',p); assert(q.levelPct==95 and n>0)
 p.schemaVersion=-1; q,n=C.validate('J',p); assert(q.levelPct==95 and n>0)
 local g=C.globalDefaults; local newer={}; for k,v in pairs(g) do newer[k]=v end; newer.schemaVersion=C.version+1; newer.enabled=false
 local gq,gn=C.validateGlobals(newer); assert(gq.enabled==false and gn==0 and gq.schemaVersion==C.version+1)
 local _,valid=C.patterns('bad.path:1'); assert(not valid)
 local text=''; for i=1,9 do text=text..'car'..i..':1,' end
 _,valid=C.patterns(text); assert(not valid)
end
tests.FLASH_URGENT_DETECTOR=function()
 local f=Flash.new()
 for n=0,2 do Flash.step(f,true,n*0.5); Flash.step(f,false,n*0.5+0.2) end
 assert(f.eventId==2 and f.eventCount==3)
end
tests.ZONE_SPEC_FORMAT=function()
 local zones=assert(Z.parse('return { zones = { {from=0.1,to=0.2,noYield=true,noOvertake=true,maxOffset=0.4,note="v1"} } }'))
 assert(#zones==1 and zones[1].noOvertake and zones[1].maxOffset==0.4)
 assert(not Z.parse('return { zones={},extra=true }'))
end
tests.SESSION_DIRECTION_RESET=function()
 local e,f=F.scene('J'); local s=e.states[2]
 for i=1,6 do s.directions[i]=e.time end
 s.directionCount=6; s.driveUntil=e.time+20
 f.session=1; E.step(e,f,1/60)
 assert(s.driveUntil==0 and s.directionCount<=1); for i=2,6 do assert(s.directions[i]==-math.huge) end
end
tests.PLAYER_NONZERO_INDEX=function()
 local host=require('tests/host').create(true); host.cars[0].isUserControlled=false; host.cars[0].isAIControlled=true
 host.cars[2].isUserControlled=true; host.cars[2].isAIControlled=false
 local Snapshot=require('src/snapshot'); local f=Snapshot.new(); Snapshot.read(f,1/60,0)
 assert(f.player==3 and not f.cars[3].control and f.cars[1].control)
end
tests.OBSTACLE_CONFIGURED_THRESHOLD=function()
 local e,f=F.scene('J'); F.front(e,f,40,40); e.p.obstacleSpeedKmh=50
 f.cars[3].speed=35/3.6; f.cars[3].kmh=35; f.cars[3].stopped=0
 F.tick(e,f,1); assert(e.states[2].state~='AVOID')
 F.tick(e,f,2); assert(e.states[2].state=='AVOID')
end
tests.FLASH_LOST_ADVANTAGE=function()
 local e,f=F.scene('J'); F.rear(e,f,40,20,1); e.p.yieldBehindMargin=30; e.p.pressureEnabled=false; e.p.flashObliviousPct=0
 F.tick(e,f,0.2); e.flash.eventId=1; e.flash.eventCount=2
 Flash.dispatch(e.flash,f.cars,f.count,1,e.perception,e.states,e.p,e.g,e.profile,e.time)
 -- Beta 1.29 : resté juste derrière à la même allure, le joueur est retenu (appel compris) ; il doit donc lâcher prise.
 F.tick(e,f,0.1); f.cars[1].kmh=90; f.cars[1].speed=90/3.6; e.states[2].nextPerception=0
 F.tick(e,f,2); assert(not F.yielding(e.states[2].state)); assert(e.states[2].pendingAt==0)
end
tests.FLASH_ALWAYS_RACE=function()
 local e,f=F.scene('C'); e.p.flashMode='always'; e.p.flashObliviousPct=0; F.rear(e,f,40,20,1)
 F.tick(e,f,0.2); e.flash.eventId=1; e.flash.eventCount=2
 assert(Flash.dispatch(e.flash,f.cars,f.count,1,e.perception,e.states,e.p,e.g,e.profile,e.time)==1)
 F.tick(e,f,2); assert(F.yielding(e.states[2].state))
end
tests.HORN_WITHOUT_FLASH_CALIBRATION=function()
 local e,f=F.scene('J'); e.p.hornEnabled=true; e.g.flashField=''; e.p.flashObliviousPct=0; F.rear(e,f,40,20,1)
 for _=1,2 do f.cars[1].hornActive=true; F.tick(e,f,0.2); f.cars[1].hornActive=false; F.tick(e,f,0.3) end
 assert(e.flash.eventId>=1 and e.flash.requests[2].event>=1)
end
tests.ENDURANCE_PRESET_TRACKDAY=function()
 local p={}; C.preset('Endurance','J',p)
 assert(p.enduranceOverlay and p.multiClass and p.yieldEnabled and p.yieldSide=='right')
end
tests.BUILTIN_PRESET_ACTIVATIONS=function()
 local cases={{'Nordschleife','J'},{'Course','C'},{'Endurance','J'},{'Endurance','C'}}
 for _,entry in ipairs(cases) do
  local name,profile=entry[1],entry[2]; local p=C.preset(name,profile,{})
  -- 1.3.0 : tout onglet qui agit dans la session est coché ; Départ en course seulement, classes partout.
  for _,group in ipairs({'general','flash','overtake','lateral','human','accidents','rules','endurance','weather'}) do assert(C.on(p,group),name..':'..group) end
  assert(C.on(p,'yield')==(profile=='J') and C.on(p,'traffic')==(profile=='J') and C.on(p,'start')==(profile=='C'))
  assert(C.on(p,'blue')==(profile=='C'))
  assert(not C.on(p,'globals'))
  local effective=C.effective(profile,p)
  assert(effective.overtakeEnabled and effective.obstacleEnabled and effective.multiClass and effective.yellowEnabled and effective.weatherTyresEnabled)
  assert(effective.enduranceOverlay==(name=='Endurance'))
  if profile=='C' then assert(effective.blueFlagEnabled and effective.defenseEnabled and effective.slipstreamEnabled and effective.overtakeSide=='auto') end
  if name=='Endurance' then assert(effective.multiClass and effective.lapseEnabled) end
 end
 for _,profile in ipairs(C.profiles) do assert(profile=='H' or not C.any(C.defaults(profile))) end
end
tests.SECTIONS_DEFAULT_OFF=function()
 for _,profile in ipairs(C.profiles) do
  local p=C.defaults(profile); assert(profile=='H' or not C.any(p))
  -- Beta 1.37 : Panneaux lumineux cochés dans chaque profil (comportement de la 1.36), jamais un onglet « qui pilote ».
  for _,group in ipairs(C.sections) do assert(not C.on(p,group) or profile=='H' and group=='rules' or group=='lights') end
  assert(C.on(p,'lights') and (profile=='H' or not C.anySection(p)))
  p.schemaVersion=1; p.section_general=true; local migrated=C.validate(profile,p); assert(not migrated.section_general and migrated.levelPct==p.levelPct)
 end
end
tests.OPTIONS_FALSE_PRESERVED=function()
 for _,profile in ipairs(C.profiles) do
  local p=C.defaults(profile)
  for _,group in ipairs(C.sections) do p['section_'..group]=true end
  for _,s in ipairs(C.schema) do
   if type(p[s.key])=='boolean' then p[s.key]=false end
  end
  local checked=C.validate(profile,p); local run=C.effective(profile,checked)
  -- Jaune des panneaux : toujours actif (Beta 1.37).
  assert(run.lightsYellow==true,'yellow always on')
  for _,s in ipairs(C.schema) do
   if type(p[s.key])=='boolean' and s.key~='lightsYellow' then assert(run[s.key]==false,profile..':'..s.key) end
  end
 end
end
tests.REQUESTED_DEFAULTS=function()
 for _,profile in ipairs(C.profiles) do
  local p=C.defaults(profile)
  assert(p.yieldSide=='right' and p.overtakeSide=='left' and p.slipstreamEnabled and p.defenseEnabled)
  assert(profile=='H' or not C.any(p)); local run=C.effective(profile,p)
  assert(not run.slipstreamEnabled and not run.defenseEnabled)
 end
end
tests.AUTO_YIELD_FREE_SIDE=function()
 for _,occupied in ipairs({'none','right','left','both'}) do
  local e,f=F.scene('J',5); e.p.yieldSide='auto'; e.p.personalLineJitter=0; e.p.laneBiasEnabled=false; E.changed(e)
  F.rear(e,f,45,30)
  -- Les coordonnées monde +x sont à droite pour le cap +z de la fixture.
  F.place(f,4,10,100,(occupied=='right' or occupied=='both') and 2 or 1000)
  F.place(f,5,10,100,(occupied=='left' or occupied=='both') and -2 or -1000)
  F.tick(e,f,4)
  if occupied=='both' then assert(not F.yielding(e.states[2].state) and e.states[2].offset==0)
  else assert(F.yielding(e.states[2].state)); assert(e.states[2].targetSide==(occupied=='right' and -1 or 1)) end
 end
end
tests.SECTIONS_EFFECT_ISOLATION=function()
 local raw=C.defaults('J'); raw.levelPct=40; raw.yieldEnabled=true; raw.blueFlagEnabled=true; raw.overtakeEnabled=true; raw.enduranceOverlay=true; raw.hornEnabled=true
 local run=C.effective('J',raw)
 assert(not run.yieldEnabled and not run.blueFlagEnabled and not run.overtakeEnabled and not run.obstacleEnabled and not run.weatherAdaptation and not run.enduranceOverlay and run.flashMode=='never' and not run.hornEnabled)
 raw.section_blue=true; run=C.effective('J',raw,run); assert(run.blueFlagEnabled and not run.yieldEnabled and not run.overtakeEnabled)
 assert(raw.levelPct==40 and raw.hornEnabled and raw.enduranceOverlay)
 local e,f=F.scene('J'); for _,group in ipairs(C.sections) do e.p['section_'..group]=false end
 e.p.section_blue=true; e.p.levelPct=40; E.changed(e); F.tick(e,f,3)
 assert(math.abs(e.commands[2].level-f.cars[2].aiLevel)<0.01 and not e.commands[2].levelOwned)
 assert(not e.commands[2].aggressionOwned and not e.commands[2].cautionOwned)
end
tests.AUTO_PROFILE_SELECTION=function()
 -- Modes Content Manager : Journée circuit (« Track Day »), Essai, week-end (essais, qualifications, course), Course.
 local e,f=F.scene('C'); E.select(e,'C'); f.type=3; f.configType=1; f.configTrackDay=true; e.g.autoProfile=true; E.step(e,f,1/60); assert(e.profile=='J')
 f.configTrackDay=false; E.step(e,f,1/60); assert(e.profile=='P')
 -- Beta 1.19 : journée circuit déclarée en qualifications (TYPE 2) par Content Manager : toujours Journée circuit.
 f.type=2; f.configType=2; f.configTrackDay=true; E.step(e,f,1/60); assert(e.profile=='J','track day declared as qualifying')
 f.configTrackDay=false; E.step(e,f,1/60); assert(e.profile=='Q','real qualifying')
 f.type=3; f.configType=1; f.configTrackDay=false
 f.configType=2; E.step(e,f,1/60); assert(e.profile=='Q')
 f.configType=3; E.step(e,f,1/60); assert(e.profile=='C')
 f.configType=0; f.type=1; E.step(e,f,1/60); assert(e.profile=='J','practice without race.ini keeps Journée circuit')
 f.configType=0; f.type=3; E.step(e,f,1/60); assert(e.profile=='C')
 E.select(e,'J'); f.session=f.session+1; E.step(e,f,1/60); assert(e.profile=='J' and not e.g.autoProfile)
 e.g.manualProfile='C'; local fresh=E.new(e.g,e.profiles); assert(fresh.profile=='C' and fresh.p==e.profiles.C)
end
tests.TRAFFIC_DENSITY_RANDOMIZATION=function()
 local Traffic=require('src/traffic')
 local function mean(count,length)
  local e,f=F.scene('J',count+1); f.length=length; e.p.section_traffic=true; local t=Traffic.new(); local sum,minimum,maximum=0,math.huge,0
  for i=2,f.count do local a=f.cars[i]; a.spline=(i-2)/count; a.lx=0; a.lz=1 end
  Traffic.update(t,f,e.states,e.p,e.g,'J',e.time)
  assert(t.count==count and t.connected==count)
  for i=2,f.count do local target=e.states[i].trafficTarget; sum=sum+target; minimum=math.min(minimum,target); maximum=math.max(maximum,target); assert(target<=length/count*C.K.trafficMaxCapacity+1e-9) end
  return sum/count,maximum-minimum,e,f,t
 end
 local nine=mean(9,25000); local fifty,spread,e,f,t=mean(50,25000)
 assert(fifty>nine*1.5 and spread>30)
 local _,shortSpread=mean(50,2000); assert(shortSpread>5)
 f.cars[2].pit=true; Traffic.update(t,f,e.states,e.p,e.g,'J',e.time+1); assert(t.count==49 and t.connected==50 and e.states[2].trafficLimit==C.K.unlimitedSpeed)
 Traffic.update(t,f,e.states,e.p,e.g,'C',e.time+2); for i=2,f.count do assert(e.states[i].trafficLimit==C.K.unlimitedSpeed) end
end
tests.TRAFFIC_PROGRESSIVE_LIMIT=function()
 local e,f=F.scene('J'); for _,group in ipairs(C.sections) do e.p['section_'..group]=false end
 e.p.section_traffic=true; E.changed(e); F.place(f,2,0,100); F.place(f,3,10,100)
 local old=100; local limited=false
 for _=1,C.K.trafficCycle*60 do E.step(e,f,1/60); local speed=e.commands[2].speedLimit; assert(speed>=C.K.trafficMinSpeed and speed>=old-C.K.trafficDecelKmh/60-1e-7); old=math.min(speed,100); limited=limited or speed<100 end
 assert(limited)
 e.p.section_traffic=false; E.changed(e); E.step(e,f,1/60); assert(not e.commands[2].active)
end
tests.CUSTOM_PRESET_VALIDATION=function()
 local Presets=require('src/presets'); local p=C.defaults('J'); local g=C.validateGlobals(C.globalDefaults); g.debugLog=true
 assert(not Presets.capture('', 'J',p,g)); assert(not Presets.capture(string.rep('a',65),'J',p,g)); assert(not Presets.capture('bad\nname','J',p,g))
 p.section_general=true; p.levelPct=78
 local entry=assert(Presets.capture('Mon programme','J',p,g)); local encoded=Presets.encode(entry); local decoded=assert(Presets.decode(encoded))
 assert(decoded.p.section_general and decoded.p.levelPct==78 and decoded.name=='Mon programme' and decoded.g.debugLog)
 encoded.g_debugLog=nil; encoded.p_flashMaxReactors=6
 local legacy=assert(Presets.decode(encoded)); assert(not legacy.g.debugLog and legacy.p.flashMaxReactors==3)
 p.levelPct=100; assert(entry.p.levelPct==78)
 encoded.p_levelPct=0/0; local kept,n=Presets.decode(encoded)
 assert(kept and n>0 and kept.p.levelPct==C.defaults('J').levelPct,'invalid value replaced, preset kept')
end
tests.TRAFFIC_NATIVE_RECOVERY=function()
 local host=require('tests/host').create(true); local e,f=F.scene('J')
 local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false end
 local cmd=e.commands[2]; cmd.active=true; cmd.levelOwned=false; cmd.aggressionOwned=false; cmd.cautionOwned=false; cmd.speedLimit=80; cmd.offset=0
 A.apply(a,f,e.commands,e.g,e.time); assert(a.cars[2].speed==80 and host.speedLimits[1]==80)
 A.checkpoint(a,f,true)
 local recovered=A.new(); assert(A.access(recovered)); A.recover(recovered,f)
 assert(recovered.cars[2].owned and recovered.cars[2].speed~=nil)
 A.restore(recovered,f,false,e.time); assert(not recovered.cars[2].owned and host.speedLimits[1]==C.K.unlimitedSpeed)
 -- Le format rc.1, sans drapeau de vitesse, reste lisible.
 host.values['humanai:recovery']='0\n2,car_2,1,0.5,0,1,0,0,0,0'
 local legacy=A.new(); A.recover(legacy,f); assert(legacy.cars[2].owned and legacy.cars[2].speed==nil)
end
-- Beta 1.35 (fusion) : sonde interrompue (désactivation) rendue par Caps.cancelProbe, voiture changée oubliée,
-- pause sans écriture.
tests.PROBE_CANCEL_SHARED=function()
 local e,f=F.scene('J'); F.place(f,1,-1000,100); F.place(f,2,0,100); F.place(f,3,120,100)
 local writes={}; local cap=Caps.new({present=function() return true end,write=function(name,index,value) writes[#writes+1]=name..':'..index..':'..tostring(value); return true end})
 Caps.probe(cap,f,0,e.g); assert(cap.probeIndex>0); local at=cap.probeIndex; local original=cap.probeOriginal
 f.paused=true; local before=#writes; Caps.cancelProbe(cap,f); assert(#writes==before and cap.probeIndex==at,'paused: nothing written')
 f.paused=false; Caps.cancelProbe(cap,f)
 assert(writes[#writes]=='level:'..f.cars[at].index..':'..tostring(original) and cap.probeIndex==0 and cap.probeDone,'original level restored')
 local cap2=Caps.new({present=function() return true end,write=function() writes[#writes+1]='w'; return true end})
 Caps.probe(cap2,f,0,e.g); local at2=cap2.probeIndex; assert(at2>0); f.cars[at2].id='replacement'; before=#writes
 Caps.cancelProbe(cap2,f); assert(#writes==before and cap2.probeIndex==0 and not cap2.probeDone,'swapped car: probe forgotten')
end
tests.TRANSIENT_IDENTITY_GUARDS=function()
 local e,f=F.scene('J'); F.place(f,1,-1000,100); F.place(f,2,0,100); F.place(f,3,120,100)
 local writes=0; local cap=Caps.new({present=function() return true end,write=function() writes=writes+1; return true end})
 Caps.probe(cap,f,0,e.g); assert(cap.probeIndex>0); local at=cap.probeIndex
 f.cars[at].id='replacement'; local before=writes
 Caps.probe(cap,f,1,e.g); assert(writes==before and cap.probeIndex==0 and not cap.probeDone)
 local c=Cal.new(); e.g.offsetSign=0; e.g.sideSign=0
 Cal.step(c,f,cap,e.g,2); assert(c.index>0); at=c.index; before=writes
 f.cars[at].id='another_replacement'; Cal.step(c,f,cap,e.g,6)
 assert(c.index==0 and c.phase=='aborted' and writes==before)
end
tests.DEBUG_LOG_OPTION=function()
 local e,f=F.scene('J'); e.p.personalLineJitter=0; F.rear(e,f,45,30); F.tick(e,f,4)
 for i=1,e.log.count do assert(e.log[i].level~='DEBUG') end
 e.g.debugLog=true; E.changed(e); F.tick(e,f,4)
 local found=false; for i=1,e.log.count do if e.log[i].level=='DEBUG' then found=true end end; assert(found)
end
tests.BRAKE_ONLY_OWNERSHIP=function()
 local host=require('tests/host').create(true); local e,f=F.scene('J'); local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false; cmd.weatherManaged=false end
 local cmd=e.commands[2]; cmd.active=true; cmd.offset=0; cmd.brake=0.3; cmd.speedLimit=C.K.unlimitedSpeed
 cmd.levelOwned=false; cmd.aggressionOwned=false; cmd.cautionOwned=false; e.g.useBrakeAssist=true
 A.apply(a,f,e.commands,e.g,1); assert(a.cars[2].owned and host.controls[1].brake==0.3)
 cmd.active=false; A.apply(a,f,e.commands,e.g,2); A.restore(a,f,true,2)
 assert(host.controls[1].brake==0 and not a.cars[2].owned)
end
tests.SLIPSTREAM_CONTINUOUS_TIME=function()
 local e,f=F.scene('C'); e.p.overtakeEnabled=false; e.p.defenseEnabled=false; e.p.startDelay=0; e.p.startRelax=0; E.changed(e)
 F.place(f,2,0,180); F.place(f,3,35,180); F.tick(e,f,0.5); assert(e.states[2].slipTime>0)
 F.place(f,3,500,180); F.tick(e,f,0.2); assert(e.states[2].slipTime==0)
 F.place(f,3,35,180); F.tick(e,f,0.2); assert(e.states[2].slipTime<C.K.slipTime)
end
tests.PARAMETER_BOUNDARY_ENGINE=function()
 local U=require('src/util')
 for _,profile in ipairs(C.profiles) do
  local e,f=F.scene(profile,10)
  for _,s in ipairs(C.schema) do
   local choices=s.choices or (s.min and {s.min,s.max} or {true,false})
   for _,value in ipairs(choices) do
    C.validate(profile,C.defaults(profile),e.p)
    for _,group in ipairs(C.sections) do e.p['section_'..group]=true end
    e.p[s.key]=value; C.validate(profile,e.p,e.p); E.changed(e)
    F.front(e,f,20,40); F.place(f,4,-25,160,2)
    F.tick(e,f,0.2)
    for i=1,f.count do
     local cmd=e.commands[i]
     for _,key in ipairs({'offset','level','aggression','caution','brake','speedLimit'}) do assert(U.finite(cmd[key]),profile..':'..s.key..':'..key) end
    end
   end
  end
 end
end
tests.FAILED_OFFSET_RESTORE_RETAINED=function()
 local host=require('tests/host').create(true); local e,f=F.scene('J'); local a=A.new(); assert(A.access(a))
 local s=a.cars[2]; s.owned=true; s.id=f.cars[2].id; s.offset=0.4; s.offsetReset=false; a.caps.offset.available=false
 A.restore(a,f,false,1); assert(s.owned and s.reset and s.offset==0.4)
 A.checkpoint(a,f,true); assert(host.values['humanai:recovery']:find('car_2',1,true))
 a.caps.offset.available=true; A.restore(a,f,false,2); assert(not s.owned and s.offset==0)
end
tests.SWITCHES_DISABLE_BEHAVIOR=function()
 local e,f=F.scene('J'); e.p.yieldEnabled=false; e.p.pressureEnabled=false; E.changed(e)
 F.rear(e,f,30,40); F.tick(e,f,5); assert(not F.yielding(e.states[2].state))
 e,f=F.scene('J'); e.p.overtakeEnabled=false; E.changed(e); F.front(e,f,25,40); F.tick(e,f,5)
 assert(not F.passing(e.states[2].state))
 e,f=F.scene('J'); e.p.obstacleEnabled=false; e.p.overtakeEnabled=false; E.changed(e)
 F.front(e,f,25,40); f.cars[3].kmh=0; f.cars[3].speed=0; f.cars[3].stopped=10; F.tick(e,f,5)
 assert(e.states[2].state~='AVOID')
 e,f=F.scene('C'); e.p.blueFlagEnabled=false; e.p.flashMode='never'; E.changed(e)
 F.rear(e,f,80,30); f.cars[3].lap=3; F.tick(e,f,5); assert(not F.yielding(e.states[2].state))
end
tests.WEATHER_SWITCH_PHYSICS=function()
 local function run(enabled)
  local e,f=F.scene('C')
  for _,group in ipairs(C.sections) do e.p['section_'..group]=false end
  e.p.section_general=true; e.p.section_endurance=true; e.p.section_weather=true
  e.p.paceSpreadPct=0; e.p.aggrSpreadPct=0; e.p.cautSpreadPct=0; e.p.weatherAdaptation=enabled
  E.changed(e); f.wet=1; F.tick(e,f,5)
  return e.commands[2].level,e.commands[2].caution
 end
 local dryLevel,dryCaution=run(false); local wetLevel,wetCaution=run(true)
 assert(math.abs(dryLevel-1)<0.001 and math.abs(dryCaution-1.2)<0.001)
 assert(math.abs(wetLevel-0.9)<0.001 and math.abs(wetCaution-1.68)<0.001)
end
tests.LAPSE_SWITCH_ENDURANCE=function()
 local function run(enabled,human)
  local e,f=F.scene('C'); e.p.enduranceOverlay=true; e.p.lapseEnabled=enabled; e.p.section_human=human
  E.changed(e); F.tick(e,f,0.1); e.states[2].lapseAt=e.time-1; F.tick(e,f,0.1)
  return e.states[2].lapseCount
 end
 assert(run(false,true)==0,'Endurance must respect the concentration switch')
 assert(run(true,false)==0,'Endurance must respect the disabled personality section')
 assert(run(true,true)>0,'Enabled concentration must still run in Endurance')
end
tests.WEATHER_SWITCH_DETECTION=function()
 local function run(wet,enabled,section)
  local e,f=F.scene('J'); e.p.weatherAdaptation=enabled; e.p.section_weather=section; e.p.lapseEnabled=false
  f.wet=wet; F.rear(e,f,40,20); E.changed(e); F.tick(e,f,4)
  assert(F.yielding(e.states[2].state))
  return e.states[2].yieldDetection
 end
 local dry=run(0,false,true)
 assert(run(1,false,true)==dry,'Disabled weather adaptation must not extend detection')
 assert(run(1,true,false)==dry,'Disabled weather section must not extend detection')
 assert(math.abs(run(1,true,true)-dry*1.3)<1e-8,'Enabled weather must extend detection')
end
tests.CONFIG_SEED_INACTIVE_ISOLATION=function()
 local function run(seed,active)
  local e,f=F.scene('J'); e.g.seed=seed; e.p.section_globals=active; e.p.lapseEnabled=false
  F.rear(e,f,40,20); E.changed(e)
  for _=1,180 do
   F.tick(e,f,1/60)
   if e.states[2].pendingAt>0 then return e.states[2].pendingAt end
  end
  error('No pending reaction')
 end
 assert(run(1,false)==run(999,false),'Inactive global seed must not affect reaction delay')
 assert(math.abs(run(1,true)-run(999,true))>1e-6,'Active seed must affect reaction delay')
end
tests.MULTICLASS_SWITCH_ENDURANCE=function()
 local function run(enabled)
  local e,f=F.scene('C'); e.p.enduranceOverlay=true; e.p.multiClass=enabled; e.p.flashMode='never'; e.p.blueFlagEnabled=false; e.p.lapseEnabled=false
  F.rear(e,f,60,25); E.changed(e); F.tick(e,f,0.1)
  e.states[2].class=3; e.states[3].class=1; e.states[2].classified=true; e.states[3].classified=true; e.classes.nextAt=e.time+60
  F.tick(e,f,4)
  return F.yielding(e.states[2].state)
 end
 assert(not run(false),'Endurance must respect the multiclass switch')
 assert(run(true),'Enabled multiclass must still yield in Endurance')
 local p=C.defaults('C'); p.section_endurance=true; p.enduranceOverlay=true
 assert(not C.needsOffset(C.effective('C',p,{})),'Stints alone must not request lateral calibration')
end
tests.STINT_PERSONALITY_SWITCH=function()
 local function run(enabled)
  local e,f=F.scene('C'); e.p.enduranceOverlay=enabled; E.changed(e); F.tick(e,f,0.1)
  local reaction=e.states[2].persona.reaction
  f.cars[2].pit=true; F.tick(e,f,0.1); f.cars[2].pit=false; F.tick(e,f,0.1)
  return e.states[2].persona.reaction-reaction
 end
 assert(run(false)==0,'Pit exit must preserve personality without Endurance overlay')
 assert(math.abs(run(true))>1e-6,'Endurance must still renew stint traits')
end
tests.BLUE_SIDE_AND_OVERTAKE_CHOICES=function()
 for _,profile in ipairs(C.profiles) do
  for _,side in ipairs({'left','right'}) do
   local e,f=F.scene(profile); e.p.overtakeSide=side; e.p.personalLineJitter=0; e.p.laneBiasEnabled=false; E.changed(e)
   F.front(e,f,15,35); F.tick(e,f,2)
   assert(F.passing(e.states[2].state) and e.states[2].targetSide==(side=='left' and -1 or 1),profile..':'..side)
  end
 end
 for _,profile in ipairs({'Q','C'}) do
  local e,f=F.scene(profile); e.p.blueFlagSide='left'; e.p.personalLineJitter=0; e.p.laneBiasEnabled=false; E.changed(e)
  F.rear(e,f,50,35); f.cars[3].lap=3; F.tick(e,f,4)
  assert(F.yielding(e.states[2].state) and e.states[2].targetSide==-1)
 end
end
tests.PRESET_ALL_FIELDS_ROUNDTRIP=function()
 local Presets=require('src/presets')
 for _,profile in ipairs(C.profiles) do
  local p=C.defaults(profile); local g=C.validateGlobals(C.globalDefaults)
  for index,s in ipairs(C.schema) do
   if s.choices then p[s.key]=s.choices[#s.choices]
   elseif s.min then p[s.key]=index%2==0 and s.min or s.max
   else p[s.key]=false end
  end
  for index,group in ipairs(C.sections) do p['section_'..group]=index%2==0 end
  p.classPatterns='lmp1:1,gt3:3'; p=C.validate(profile,p)
  for _,key in ipairs(Presets.globalKeys) do
   if type(g[key])=='boolean' then g[key]=true end
  end
  local entry=assert(Presets.capture('Tous les champs',profile,p,g))
  local restored=assert(Presets.decode(Presets.encode(entry)))
  assert(Presets.signature(profile,p,g)==Presets.signature(profile,restored.p,restored.g))
  local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.defaults(x) end; local globals=C.validateGlobals(C.globalDefaults)
  assert(Presets.apply(restored,profiles,globals)==profile)
  assert(Presets.signature(profile,p,g)==Presets.signature(profile,profiles[profile],globals))
 end
end
tests.PRESET_DELETE_FAILURE=function()
 local a=A.new(); a.presets[1]={name='Conserver'}
 a.presetStores[1]=setmetatable({},{__newindex=function() error('storage unavailable') end})
 assert(not A.deletePreset(a,1) and a.presets[1].name=='Conserver')
 assert(not A.deletePreset(a,0) and not A.deletePreset(a,1.5) and not A.deletePreset(a,17))
end
tests.TRAFFIC_NO_SPEED_RATCHET=function()
 local e,f=F.scene('J',41)
 for _,group in ipairs(C.sections) do e.p['section_'..group]=false end
 e.p.section_traffic=true; E.changed(e)
 for i=2,f.count do F.place(f,i,(i-2)*10,100) end
 local slowest=100
 for _=1,120*60 do
  E.step(e,f,1/60)
  for i=2,f.count do
   local a=f.cars[i]; a.kmh=math.min(100,e.commands[i].speedLimit); a.speed=a.kmh/3.6; slowest=math.min(slowest,a.kmh)
  end
 end
 assert(slowest>=100*(1-e.p.trafficMaxReduction/100)-0.01,'traffic cascaded to '..slowest..' km/h')
end
tests.WEATHER_DECISIONS=function()
 local W=require('src/weather'); local e,f=F.scene('J'); local a=f.cars[2]; local w=W.new()
 a.tyresKnown=true; a.dryCompound=0; a.interCompound=1; a.wetCompound=2; a.compoundIndex=0; a.nativeRainTyresKnown=true; a.nativeRainTyres=false
 W.step(w,f,e.commands,e.p,0); assert(not w.wet and e.commands[2].weatherCompound==0)
 f.wet=0.4; f.rain=0.2; W.step(w,f,e.commands,e.p,1); W.step(w,f,e.commands,e.p,17)
 assert(w.wet and e.commands[2].weatherCompound==1 and e.commands[2].weatherPit and e.commands[2].weatherGrip==1)
 f.wet=1; W.step(w,f,e.commands,e.p,18); assert(e.commands[2].weatherCompound==2)
 a.wetCompound=-1; a.interCompound=-1; W.step(w,f,e.commands,e.p,19); assert(math.abs(e.commands[2].weatherGrip-1.15)<1e-9)
 a.nativeRainTyres=true; W.step(w,f,e.commands,e.p,20); assert(e.commands[2].weatherGrip==1)
 a.nativeRainTyresKnown=false; a.nativeRainTyres=false; W.step(w,f,e.commands,e.p,21); assert(e.commands[2].weatherGrip==1)
 f.wet=0; f.rain=0; W.step(w,f,e.commands,e.p,22); W.step(w,f,e.commands,e.p,38); assert(not w.wet and e.commands[2].weatherCompound==0)
 e.p.weatherTyresEnabled=false; W.step(w,f,e.commands,e.p,40); assert(not e.commands[2].weatherManaged)
end
tests.WEATHER_SCHEMA_MIGRATION=function()
 local p=C.defaults('J'); p.schemaVersion=2; p.section_endurance=true; p.weatherAdaptation=true; p.weatherTyresEnabled=nil; p.rainGripBoostPct=nil
 local migrated,errors=C.validate('J',p)
 assert(errors==0 and migrated.section_endurance and migrated.section_weather and migrated.weatherTyresEnabled and migrated.rainGripBoostPct==15)
end
tests.TRAFFIC_FREE_PHASE_RECOVERS_PACE=function()
 local e,f=F.scene('J',10); local fastest={}
 for _,group in ipairs(C.sections) do e.p['section_'..group]=false end
 e.p.section_traffic=true; E.changed(e)
 for i=2,f.count do F.place(f,i,(i-2)*10,60); fastest[i]=0 end
 for frame=1,60*60 do
  E.step(e,f,1/60); local native=math.min(200,60+frame/10)
  for i=2,f.count do local a=f.cars[i]; a.kmh=math.min(native,e.commands[i].speedLimit); a.speed=a.kmh/3.6; fastest[i]=math.max(fastest[i],a.kmh) end
 end
 for i=2,f.count do assert(fastest[i]>190,'car remained stuck at pit exit pace') end
end
tests.PERCEPTION_SHARED_ORDER_EQUIVALENCE=function()
 local U=require('src/util'); local e,f=F.scene('J',61); local p=e.perception
 for sample=1,80 do
  local count=sample%61+1; f.count=count
  local order={}
  for i=1,count do f.cars[i].spline=math.floor(U.unit(42,i,sample)*30)/30; order[i]=i end
  table.sort(order,function(a,b) return f.cars[a].spline<f.cars[b].spline or f.cars[a].spline==f.cars[b].spline and a<b end)
  for i=1,count do
   P.refresh(p,f.cars,count,i,f.length,sample)
   local at; for rank,slot in ipairs(order) do if slot==i then at=rank end end
   local expected={}; local r={}
   for rank,slot in ipairs(order) do
    local d=math.abs(rank-at)
    if slot~=i and (f.cars[slot].player or d<=8 or count-d<=8) then
     P.relative(f.cars[i],f.cars[slot],f.length,r); if r.same then expected[slot]=true end
    end
   end
   for j=1,p.rows[i].count do assert(expected[p.rows[i].neighbors[j].index]); expected[p.rows[i].neighbors[j].index]=nil end
   assert(next(expected)==nil)
  end
 end
end
tests.NATIVE_SETTER_ARITY=function()
 local ffi=require('ffi'); local value=0; local rainy=false
 local level=ffi.cast('void (*)(int, float)',function(index,v) assert(index==1); value=v end)
 local rain=ffi.cast('void (*)(int, bool)',function(index,v) assert(index==1); rainy=v end)
 local oldLevel,oldRain=physics.setAILevel,physics.setAIRainTyres
 physics.setAILevel=level; physics.setAIRainTyres=rain
 local a=A.new(); assert(Caps.call(a.caps,'level',1,0.9) and math.abs(value-0.9)<1e-6)
 assert(Caps.call(a.caps,'rain',1,true) and rainy)
 physics.setAILevel=oldLevel; physics.setAIRainTyres=oldRain; level:free(); rain:free()
end
tests.PASS_BLOCK_TIMER_INDEPENDENT=function()
 local e,f=F.scene('J',4); e.p.personalLineJitter=0; e.p.laneBiasEnabled=false; E.changed(e)
 F.front(e,f,15,30); F.tick(e,f,1); assert(F.passing(e.states[2].state))
 F.place(f,4,30,100,-2) -- Bloque le corridor gauche, sans occuper le côté immédiat.
 F.tick(e,f,1); assert(e.states[2].aborts>0)
end
-- Côtés de l'interface = convention SDK (+1 droite) quel que soit le signe calibré ; offset natif = interne × signe.
tests.SIDE_ORIENTATION_CALIBRATED_SIGN=function()
 for _,sign in ipairs({1,-1}) do
  for _,profile in ipairs(C.profiles) do
   for _,side in ipairs({'left','right'}) do
    local e,f=F.scene(profile); e.g.offsetSign=sign; e.p.overtakeSide=side; e.p.personalLineJitter=0; e.p.laneBiasEnabled=false; E.changed(e)
    F.front(e,f,15,35); F.tick(e,f,2)
    assert(F.passing(e.states[2].state) and e.states[2].targetSide*sign==(side=='left' and -1 or 1),'overtake '..profile..':'..side..':'..sign)
   end
  end
  local e,f=F.scene('J'); e.g.offsetSign=sign; e.p.yieldSide='right'; e.p.personalLineJitter=0; e.p.laneBiasEnabled=false; E.changed(e)
  F.rear(e,f,50,35); F.tick(e,f,4)
  assert(F.yielding(e.states[2].state) and e.states[2].targetSide*sign==1,'yield right:'..sign)
  e,f=F.scene('Q'); e.g.offsetSign=sign; e.p.blueFlagSide='left'; e.p.personalLineJitter=0; e.p.laneBiasEnabled=false; E.changed(e)
  F.rear(e,f,50,35); f.cars[3].lap=3; F.tick(e,f,4)
  assert(F.yielding(e.states[2].state) and e.states[2].targetSide*sign==-1,'blue left:'..sign)
  e,f=F.scene('J'); e.g.offsetSign=sign; e.p.yieldSide='right'; e.p.laneBiasEnabled=true; e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,0.5)
  assert(e.states[2].persona.laneBias>0 and e.states[2].base*sign>0,'lane bias side:'..sign)
 end
end
-- Épisode d'espacement à travers un virage : écart dynamique, vrai traffic.lua et vrai plafond du director.
tests.TRAFFIC_CORNER_EXIT_NO_RATCHET=function()
 local Traffic=require('src/traffic'); local K=C.K
 local L,C0,C1,vmax,vc,dec,acc,dt=20000,1500,1570,200/3.6,80/3.6,10,15/3.6,1/60
 local function env(s)
  if s>=C0 and s<=C1 then return vc,0.2 end
  if s<C0 then return math.min(vmax,math.sqrt(vc*vc+2*dec*(C0-s))),1 end
  return vmax,1
 end
 local function step(v,s,cap)
  local target=math.min(env(s),cap/3.6)
  if target>=v then return math.min(v+acc*dt,target) end
  return math.max(v-dec*dt,target)
 end
 local function simulate(enabled,origin)
  local e,f=F.scene('J',2); for _,group in ipairs(C.sections) do e.p['section_'..group]=false end
  e.p.section_traffic=enabled; e.p.trafficVariation=0; f.length=L
  local states={D.newState(),D.newState()}; states[1].state='DRIVE'; states[2].state='DRIVE'
  for i=1,2 do local a=f.cars[i]; a.valid=true; a.control=true; a.player=false; a.lx=0; a.lz=1 end
  local t=Traffic.new(); local cmd={speedLimit=K.unlimitedSpeed}; local s1,s2,v1,v2=1000,1030,vmax,vmax; local trace={}
  for frame=0,30*60 do
   local a,b=f.cars[1],f.cars[2]; local _,corner=env(s1)
   a.spline=s1/L; b.spline=s2/L; a.kmh=v1*3.6; a.speed=v1; b.kmh=v2*3.6; b.speed=v2; a.corner=corner; b.corner=1
   Traffic.update(t,f,states,e.p,e.g,'J',origin+frame*dt)
   D.trafficCap(cmd,states[1],a,e.p,'J',dt)
   if states[1].trafficLimit<K.unlimitedSpeed and corner>=e.p.cornerMin then assert(cmd.speedLimit>=states[1].trafficLimit-1e-9,'cap below target') end
   v1=step(v1,s1,cmd.speedLimit); v2=step(v2,s2,K.unlimitedSpeed); s1=s1+v1*dt; s2=s2+v2*dt
   trace[#trace+1]={s=s1,v=v1*3.6}
  end
  return trace
 end
 local base=simulate(false,0)
 local function baseAt(s) for i=1,#base do if base[i].s>=s then return base[i].v end end return base[#base].v end
 local worst=0
 for phase=0,17 do
  for _,r in ipairs(simulate(true,phase)) do if r.s<C1+1500 then worst=math.max(worst,baseAt(r.s)-r.v) end end
 end
 -- Au plus la réduction configurée (10 %) de la vitesse de pointe libre, plus la rampe de 4 km/h/s.
 assert(worst<=200*0.1+1,'traffic deficit '..worst..' km/h')
end
-- Remise à zéro pendant un épisode (sortie des stands à 70 km/h, réglage modifié) : référence vide,
-- aucune retenue à la vitesse du moment ; le suiveur reste au plus à la réduction près du rythme natif.
tests.TRAFFIC_RESET_DURING_EPISODE=function()
 local Traffic=require('src/traffic'); local K=C.K; local dt=1/60
 local e,f=F.scene('J',2); for _,group in ipairs(C.sections) do e.p['section_'..group]=false end
 e.p.section_traffic=true; e.p.trafficVariation=0; f.length=20000
 local states={D.newState(),D.newState()}; states[1].state='DRIVE'; states[2].state='DRIVE'
 for i=1,2 do local a=f.cars[i]; a.valid=true; a.control=true; a.player=false; a.lx=0; a.lz=1; a.corner=1 end
 local random=require('src/util').unit(e.g.seed,0,2)
 local origin=K.trafficCycle-random*K.trafficCycle -- épisode actif dès t=0
 local t=Traffic.new(); local cmd={speedLimit=K.unlimitedSpeed}
 local s1,s2,v1,v2,native=1000,1030,70,70,70; local worst,limited=0,false
 for frame=0,5*60 do
  local a,b=f.cars[1],f.cars[2]
  a.spline=s1/f.length; b.spline=s2/f.length; a.kmh=v1; a.speed=v1/3.6; b.kmh=v2; b.speed=v2/3.6
  Traffic.update(t,f,states,e.p,e.g,'J',origin+frame*dt); D.trafficCap(cmd,states[1],a,e.p,'J',dt)
  limited=limited or cmd.speedLimit<K.unlimitedSpeed
  native=math.min(native+15*dt,200); v2=math.min(v2+15*dt,200); v1=math.min(v1+15*dt,200,cmd.speedLimit)
  s1=s1+v1/3.6*dt; s2=s2+v2/3.6*dt; worst=math.max(worst,native-v1-0.1*native)
 end
 assert(limited,'episode never limited the follower')
 assert(worst<=8,'follower held below its native pace: '..worst)
end
tests.QUALIFICATIONS_PRESET_AND_AUTO=function()
 local Presets=require('src/presets')
 local p=C.preset('Qualifications','Q',{})
 for _,group in ipairs({'general','yield','flash','overtake','lateral','human','accidents','rules','endurance','weather'}) do assert(C.on(p,group),group) end
 for _,group in ipairs({'blue','start','traffic','globals'}) do assert(not C.on(p,group),group) end
 assert(p.configured and C.effective('Q',p).yieldEnabled and C.recommended.Q=='Qualifications')
 local function scene(used,kind)
  local e,f=F.scene('J'); e.g.presetsUsed=used; e.g.autoProfile=true
  C.preset('Nordschleife','J',e.profiles.J); C.preset('Course','C',e.profiles.C); C.validate('Q',C.defaults('Q'),e.profiles.Q)
  f.configType=kind; return e,f
 end
 local e,f=scene(false,2); E.step(e,f,1/60); assert(e.profile=='Q' and not C.anySection(e.profiles.Q),'first install must stay neutral')
 e,f=scene(true,2); local j=Presets.signature('J',e.profiles.J,e.g); local c=Presets.signature('C',e.profiles.C,e.g)
 E.step(e,f,1/60)
 assert(e.profile=='Q' and e.profiles.Q.configured and e.profiles.Q.section_yield and e.g.loadedPreset=='' and e.settingsChanged)
 assert(Presets.signature('Q',e.profiles.Q,e.g)==Presets.signature('Q',p,e.g))
 assert(Presets.signature('J',e.profiles.J,e.g)==j and Presets.signature('C',e.profiles.C,e.g)==c,'configured profiles changed')
 e,f=scene(true,2); e.profiles.Q.configured=true; E.step(e,f,1/60); assert(not C.anySection(e.profiles.Q),'cleared profile reapplied')
 e,f=scene(true,1); f.configTrackDay=true; C.validate('J',C.defaults('J'),e.profiles.J); E.step(e,f,1/60)
 assert(e.profile=='J' and e.profiles.J.section_traffic and e.g.loadedPreset=='')
 -- Essai seul ou essais d'un week-end : profil Essais et son préréglage, sans Espacement ni drapeau bleu.
 e,f=scene(true,1); C.validate('P',C.defaults('P'),e.profiles.P); E.step(e,f,1/60)
 assert(e.profile=='P' and e.profiles.P.section_yield and not e.profiles.P.section_traffic and not e.profiles.P.section_blue and e.g.loadedPreset=='')
 assert(Presets.signature('P',e.profiles.P,e.g)==Presets.signature('P',C.preset('Essais','P',{}),e.g) and not e.profiles.P.enduranceOverlay)
end
tests.CONFIGURED_AND_PRESETS_USED_MIGRATION=function()
 local p=C.defaults('J'); p.section_yield=true; p.configured=false
 assert(C.validate('J',p).configured and not C.validate('Q',C.defaults('Q')).configured)
 local g=C.validateGlobals(C.globalDefaults); assert(not g.presetsUsed)
 local old={}; for k,v in pairs(C.globalDefaults) do old[k]=v end; old.loadedPreset='builtin:Nordschleife'
 assert(C.validateGlobals(old).presetsUsed)
end
tests.BRAKE_NEUTRAL_AND_PIT_RELEASE=function()
 local host=require('tests/host').create(true); local e,f=F.scene('J')
 local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false end
 local g=C.validateGlobals(C.globalDefaults); g.useBrakeAssist=true; g.offsetSign=1
 local cmd=e.commands[2]; cmd.active=true; cmd.levelOwned=false; cmd.aggressionOwned=false; cmd.cautionOwned=false; cmd.offset=0; cmd.brake=0.4
 A.apply(a,f,e.commands,g,e.time)
 local controls=host.controls[1]
 assert(math.abs(controls.brake-0.4)<1e-9 and controls.steer==math.huge and controls.gas==0 and controls.handbrake==0)
 assert(controls.clutch==1 and controls.requestedGearIndex==0 and controls.mguhMode==-1)
 f.cars[2].pit=true; host.cars[1].isInPitlane=true; cmd.active=false
 A.apply(a,f,e.commands,g,e.time+0.1)
 assert(controls.brake==0 and a.cars[2].brake==0,'brake kept in the pit lane')
end
-- 1.3.0 : un profil identique à un préréglage 1.2.0 reçoit une fois sa version 1.3.0 ; un profil retouché est conservé.
tests.LEGACY_PRESET_MIGRATION=function()
 local legacy=require('tests/legacy_presets')
 local Presets=require('src/presets')
 for key,values in pairs(legacy) do
  local name,profile=key:match('^(%a+):(%a)$')
  local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.defaults(x) end
  local p=C.validate(profile,C.defaults(profile),{}); for k,v in pairs(values) do p[k]=v end; profiles[profile]=p
  local g=C.validateGlobals(C.globalDefaults); assert(g.dataRevision==0)
  local upgraded=C.migrate(g,profiles)
  local listed=0; for _,u in ipairs(upgraded) do if not u:find(':delta$') then listed=listed+1 end end
  assert(g.dataRevision==C.dataRevision and listed==1 and upgraded[1]==profile..':'..name,key)
  assert(Presets.signature(profile,p,g)==Presets.signature(profile,C.preset(name,profile,{}),g),key)
  assert(C.migrate(g,profiles)==nil,'migration runs once')
  local q=C.validate(profile,C.defaults(profile),{}); for k,v in pairs(values) do q[k]=v end; q.levelPct=q.levelPct-1
  profiles[profile]=q; g.dataRevision=0; C.migrate(g,profiles)
  assert(q.levelPct==values.levelPct-1 and q.section_accidents==values.section_start and not q.section_rules and not q.multiClass==not values.multiClass,key)
  assert(not q.yellowEnabled and not q.incidentStop and C.effective(profile,q).obstacleEnabled and C.effective(profile,q).contactRecovery,key)
 end
end
tests.CUSTOM_PRESET_BEFORE_1_3=function()
 local Presets=require('src/presets')
 local store=Presets.layout(); store.name='Ancien'; store.profile='C'
 for k,v in pairs(C.preset('Course','C',{})) do store['p_'..k]=v end
 store.revision=0; store.p_section_accidents=false; store.p_section_rules=false; store.p_section_start=true
 local entry=Presets.decode(store)
 assert(entry and entry.p.section_accidents and not entry.p.yellowEnabled and not entry.p.incidentStop and entry.p.obstacleEnabled)
 local saved=Presets.encode(entry); assert(saved.revision==14)
 saved.p_yellowEnabled=true; local again=Presets.decode(saved); assert(again.p.section_accidents and again.p.yellowEnabled)
end
tests.RULE_CATEGORIES=function()
 local Presets=require('src/presets')
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.preset(C.recommended[x],x,{}) end
 local before=Presets.signature('J',profiles.J,C.globalDefaults)
 for _,x in ipairs(C.ruleProfiles) do assert(C.ruleCategory(x,profiles[x])=='base') end
 assert(C.applyRules('F1',profiles))
 for _,x in ipairs(C.ruleProfiles) do
  local p=profiles[x]
  assert(C.ruleCategory(x,p)=='F1' and p.section_rules and p.neutralization=='vsc' and p.mandatoryStops==1 and not p.overtakeMode and p.pitCompoundChange and p.yellowSpeedKmh==50
   and p.zoneDeltaPct==15 and p.pitWindowClosePct==95 and p.redFlagWork and p.rulesDrs and p.rulesDrsLaps==1 and p.pitsClosed=='open','F1 2025: DRS, no Overtake Mode')
 end
 assert(Presets.signature('J',profiles.J,C.globalDefaults)==before,'track day untouched')
 C.applyRules('F1_2026',profiles)
 assert(C.ruleCategory('C',profiles.C)=='F1_2026' and profiles.C.overtakeMode and profiles.C.rulesDrsLaps==0 and profiles.C.neutralization=='vsc','F1 2026: Overtake Mode, active aero without waiting')
 C.applyRules('GT',profiles)
 assert(profiles.C.fcyDeltaPct==150 and profiles.C.pitWindowOpenPct==42 and profiles.C.pitWindowClosePct==58 and profiles.C.minPitTime==0 and profiles.C.pitsClosed=='open' and not profiles.C.redFlagWork,'GT Sprint: 80 km/h FCY as a delta, 25-35 min window, pits open under FCY (SRO 2026 art. 39.4)')
 C.applyRules('Endurance',profiles)
 assert(profiles.C.yellowSpeedKmh==80 and profiles.C.slowZoneKmh==80 and profiles.C.fcyDeltaPct==150 and profiles.C.pitsClosed=='pitFcySc' and profiles.C.predictableSlowClass and profiles.C.maxStintMin==50 and not profiles.C.overtakeMode and profiles.C.mandatoryStops==0)
 C.applyRules('base',profiles); assert(profiles.C.yellowSpeedKmh==50 and C.ruleCategory('C',profiles.C)=='base')
 profiles.C.fcySpeedKmh=90; assert(C.ruleCategory('C',profiles.C)==nil)
 assert(not C.applyRules('IndyCar',profiles))
 local p=C.preset('Course','C',{}); C.applyRules('GT',{P=C.defaults('P'),Q=C.defaults('Q'),C=p}); p.section_rules=false
 local eff=C.effective('C',p); assert(eff.mandatoryStops==0 and eff.neutralization=='local' and not eff.bopEnabled and not eff.noMoveBraking and eff.minPitTime==0 and eff.pitsClosed=='open' and not eff.redFlagWork and not eff.rulesDrs and not eff.aiDrs)
 p.section_accidents=false; eff=C.effective('C',p); assert(not eff.yellowEnabled and not eff.incidentStop and not eff.obstacleEnabled and not eff.contactRecovery)
 p.section_flash=false; assert(not C.effective('C',p).aiFlashEnabled)
end
-- Zone jaune : vitesse limitée avec descente bornée, aucune manœuvre de dépassement ; levée après dégagement.
local function fallback(v,ref) return v<=ref+1e-6 and v>=ref*(1-C.K.aiDeltaMarginMax)-1e-6 end
tests.YELLOW_ZONE_SPEED_AND_NO_PASS=function()
 local e,f=F.scene('J',4)
 F.place(f,4,600,0); F.place(f,2,350,150); F.place(f,3,410,100)
 F.tick(e,f,2.5)
 assert(e.incidents.cars[4].incident and e.incidents.zoneCount==1,'stopped car is an incident')
 local s=e.states[2]; local cmd=e.commands[2]
 assert(s.yellow and cmd.yellowLimit<150 and cmd.yellowLimit>=50,'speed limited progressively')
 -- Beta 1.47 : repli relatif à la voiture (K.yellowUnknownPct de sa vitesse maximale vue, 150 km/h), au moins 50 km/h.
 F.tick(e,f,6); assert(fallback(cmd.yellowLimit,math.max(50,C.K.yellowUnknownPct*150)),'zone fallback speed reached while the pace is unknown, driver margin included')
 assert(not F.passing(s.state),'no overtake under yellow')
 -- Approche : limite fonction de la distance, jamais un échelon brutal.
 local e2,f2=F.scene('J',4); F.place(f2,4,600,0); F.place(f2,2,-200,150); F.place(f2,3,5000,100)
 F.tick(e2,f2,2.5)
 local expected=math.sqrt((50/3.6)^2+2*5*500)*3.6
 assert(e2.commands[2].yellowLimit>=expected*(1-C.K.aiDeltaMarginMax)-1 and e2.commands[2].yellowLimit<=expected+1e-6 and not e2.states[2].yellow,'approach cap')
 -- Dégagement : zone maintenue yellowHold puis levée.
 F.place(f,4,600,100); F.tick(e,f,3); assert(e.incidents.zoneCount==1 and e.states[2].yellow)
 -- Fin d'incident confirmée après 2 s de conduite normale, puis zone maintenue 10 s.
 F.tick(e,f,10); assert(e.incidents.zoneCount==0 and not e.states[2].yellow and e.commands[2].yellowLimit==C.K.unlimitedSpeed)
end
tests.YELLOW_BLOCKS_OVERTAKE=function()
 local function run(stopped)
  local e,f=F.scene('J',4)
  -- Incident établi avant que les deux voitures n'arrivent à son approche.
  F.place(f,2,-3000,100); F.place(f,3,-2000,100); F.place(f,4,stopped and 400 or 4000,stopped and 0 or 100); F.tick(e,f,2.5)
  F.place(f,2,0,130); F.place(f,3,30,100); e.states[2].nextPerception=0
  local passed=false
  for _=1,8*60 do F.tick(e,f,1/60); if F.passing(e.states[2].state) then passed=true end end
  return passed,e
 end
 local free=run(false); local blocked,e=run(true)
 assert(free,'reference overtake happens without incident')
 assert(not blocked and e.states[2].yellow,'overtake forbidden in the yellow zone')
end
-- Voiture en travers, hors du voisinage de même sens : évitée par le côté opposé.
tests.SPUN_CAR_AVOIDANCE=function()
 local e,f=F.scene('J',3)
 F.place(f,2,0,120); local spun=F.place(f,3,90,0,1.5); spun.lx=1; spun.lz=0; spun.slip=90
 F.tick(e,f,3)
 local s=e.states[2]
 assert(e.incidents.cars[3].incident and s.state=='AVOID' and s.target==3,'spun car avoided: '..s.state)
 F.tick(e,f,2); assert(s.offset<-0.05,'moves away from the spun car side')
end
tests.WRONG_WAY_INCIDENT=function()
 local e,f=F.scene('J',3)
 local w=F.place(f,3,2000,40); w.lz=-1
 for _=1,3*60 do w.z=w.z-40/3.6/60; w.spline=(w.z/f.length)%1; E.step(e,f,1/60) end
 assert(e.incidents.cars[3].incident and e.incidents.cars[3].wrong>=C.K.wrongWayTime,'wrong-way car detected')
 local e2,f2=F.scene('J',3); local ok=F.place(f2,3,2000,40)
 for _=1,3*60 do ok.z=ok.z+40/3.6/60; ok.spline=(ok.z/f2.length)%1; E.step(e2,f2,1/60) end
 assert(not e2.incidents.cars[3].incident,'normal car is not an incident')
end
-- IA accidentée hors piste : arrêt court, prolongé tant qu'une voiture lancée arrive derrière, borné ; en pleine piste
-- (Beta 1.7), jamais immobilisée sur la trajectoire.
tests.INCIDENT_STOP_HOLD=function()
 local function crash(e,f,i,onTrack)
  F.tick(e,f,0.5); f.cars[i].collided=true; f.cars[i].offtrack=not onTrack; f.cars[i].kmh=8; f.cars[i].speed=8/3.6; F.tick(e,f,0.5); f.cars[i].collided=false
 end
 local e,f=F.scene('J',3); F.place(f,2,0,150); F.place(f,3,5000,100)
 crash(e,f,2)
 local c=e.incidents.cars[2]
 assert(c.holding and e.commands[2].stopHold,'crashed AI held')
 local duration=c.holdUntil-e.time
 assert(duration>=2 and duration<=8,'hold within min/max')
 F.tick(e,f,duration+0.5); assert(not c.holding and not e.commands[2].stopHold,'released when the track behind is clear')
 local e2,f2=F.scene('J',3); F.place(f2,2,0,150); F.place(f2,3,-60,150)
 crash(e2,f2,2)
 local c2=e2.incidents.cars[2]; F.tick(e2,f2,c2.holdUntil-e2.time+1)
 assert(c2.holding,'waits while a car arrives behind')
 F.tick(e2,f2,C.K.rejoinWaitMax+1); assert(not c2.holding,'hold bounded')
 -- Sans l'option : aucune retenue.
 local e3,f3=F.scene('J',3); e3.profiles.J.incidentStop=false; E.changed(e3); F.place(f3,2,0,150)
 crash(e3,f3,2); assert(not e3.incidents.cars[2].holding)
 local e4,f4=F.scene('J',3); F.place(f4,2,0,150); F.place(f4,3,5000,100)
 crash(e4,f4,2,true); assert(not e4.incidents.cars[2].holding and not e4.commands[2].stopHold,'on the racing line: never held')
end
tests.NEUTRALIZATION_FCY_VSC=function()
 local e,f=F.scene('C',4); e.profiles.C.neutralization='fcy'; E.changed(e)
 F.place(f,2,0,150); F.place(f,3,3000,150); F.place(f,4,6000,0)
 F.tick(e,f,10); assert(not e.incidents.neutral,'not yet a major incident')
 F.tick(e,f,8); assert(e.incidents.neutral and e.incidents.messageKind=='fcy','FCY after the major incident time')
 F.tick(e,f,8); assert(fallback(e.commands[2].yellowLimit,80) and e.states[2].yellow and fallback(e.commands[3].yellowLimit,80),'whole field at the FCY fallback speed (pace unknown)')
 F.place(f,4,6000,120); F.tick(e,f,20); assert(e.incidents.neutral,'minimum neutralization time')
 F.tick(e,f,14); assert(not e.incidents.neutral and e.incidents.messageKind=='green','green flag')
 local e2,f2=F.scene('C',3); e2.profiles.C.neutralization='vsc'; E.changed(e2)
 local s2=e2.states[2]; for b=1,#s2.pace do s2.pace[b]=150/3.6 end; s2.paceCount=400; s2.paceMean=150/3.6
 F.place(f2,2,0,150); F.place(f2,3,6000,0); F.tick(e2,f2,25)
 assert(e2.incidents.neutral and fallback(e2.commands[2].yellowLimit,150/1.3),'VSC: learned pace, reference time +30 %')
 local e3,f3=F.scene('Q',3); e3.profiles.Q.neutralization='fcy'; E.changed(e3)
 F.place(f3,2,0,150); F.place(f3,3,6000,0); F.tick(e3,f3,25); assert(not e3.incidents.neutral,'neutralization only in race')
end
tests.INCIDENT_DEBOUNCE=function()
 -- Pic de dérive d'une ou deux images (vibreur) : aucune zone jaune ; vrai tête-à-queue confirmé.
 local e,f=F.scene('J',3); F.place(f,3,500,120); F.tick(e,f,0.5)
 f.cars[3].slip=80; F.tick(e,f,2/60); f.cars[3].slip=0; F.tick(e,f,3)
 assert(e.incidents.zoneCount==0 and not e.states[2].yellow,'short slip spike ignored')
 f.cars[3].slip=90; f.cars[3].kmh=60; F.tick(e,f,1); assert(e.incidents.cars[3].incident,'real spin flagged')
 -- Contact d'une ou deux images : retenu sur toute la fenêtre de mesure, l'IA accidentée est arrêtée.
 for offset=0,17 do
  local e2,f2=F.scene('J',3); F.place(f2,2,0,150); F.place(f2,3,5000,100); F.tick(e2,f2,0.5+offset/60)
  f2.cars[2].collided=true; f2.cars[2].kmh=8; f2.cars[2].speed=8/3.6; F.tick(e2,f2,2/60); f2.cars[2].collided=false
  -- Sortie de piste après la fenêtre de mesure : seul le contact bref, retenu, désigne l'accident (retenue hors piste).
  F.tick(e2,f2,0.4); f2.cars[2].offtrack=true; F.tick(e2,f2,0.2); assert(e2.incidents.cars[2].holding,'brief contact latched, phase '..offset)
 end
end
tests.GRID_IS_NOT_AN_INCIDENT=function()
 local e,f=F.scene('C',3)
 e.startedAt=e.time; for i=2,3 do F.place(f,i,(i-2)*20,0) end
 F.tick(e,f,5); assert(e.incidents.activeCount==0,'standing grid is not a yellow zone')
 -- Accrochage au premier virage : drapeau jaune dès les premières secondes de course.
 F.tick(e,f,4); assert(e.incidents.activeCount==2,'first-corner incident flagged')
 -- Avant le feu vert : jamais d'incident.
 local e2,f2=F.scene('C',3); f2.started=false; for i=2,3 do F.place(f2,i,(i-2)*20,0) end
 F.tick(e2,f2,20); assert(e2.incidents.activeCount==0,'no incident before the start')
end
tests.ACCIDENT_WRITES_AND_RESTORE=function()
 local host=require('tests/host').create(true); local e,f=F.scene('J'); local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false; cmd.stopHold=false end
 local cmd=e.commands[2]; cmd.stopHold=true; f.cars[2].offtrack=true
 A.apply(a,f,e.commands,e.g,10); assert(a.cars[2].stop and host.stops[1]==C.K.stopPulse,'pulse written off track')
 local n=host.calls; A.apply(a,f,e.commands,e.g,10.2); assert(host.calls==n,'pulses throttled')
 local c3=e.commands[3]; c3.active=true; c3.levelOwned=false; c3.aggressionOwned=false; c3.cautionOwned=false; c3.offset=0; c3.speedLimit=120; c3.yellowLimit=50
 A.apply(a,f,e.commands,e.g,11); assert(host.speedLimits[2]==50,'lowest limit applied')
 c3.yellowLimit=C.K.unlimitedSpeed; A.apply(a,f,e.commands,e.g,11.5); assert(host.speedLimits[2]==120,'traffic limit kept')
 f.flag=12; A.flag(a,f,true); assert(not a.flagOverride and host.flagOverrides==0,'never over a native flag')
 f.flag=0; A.flag(a,f,true); assert(a.flagOverride and host.flag==C.K.flagCaution)
 A.checkpoint(a,f,true); assert(host.values['humanai:recovery']:match('^0;F'))
 local b=A.new(); assert(A.access(b)); A.recover(b,f); assert(b.flagOverride and b.cars[2].stop,'recovered flag and hold')
 A.restore(b,f,false,12); assert(not b.flagOverride and host.flag==0 and not b.cars[2].stop and host.stops[1]==0,'handed back after reload')
 cmd.stopHold=false; host.stops[1]=nil; A.apply(a,f,e.commands,e.g,13); assert(not a.cars[2].stop and host.stops[1]==0,'explicit release')
 f.flag=C.K.flagCaution; A.flag(a,f,false); assert(not a.flagOverride and host.flag==0)
end
-- IA rapide retenue derrière une IA plus lente, à vitesse égale : appel de phares et cession de la voiture de devant.
local function held(profile,patterns,enabled)
 local e,f=F.scene(profile,3); local p=e.profiles[profile]
 p.aiFlashEnabled=enabled~=false; p.pressureEnabled=false; p.multiClass=patterns~=nil; p.classPatterns=patterns or ''; E.changed(e)
 F.place(f,2,0,100); F.place(f,3,29.4,100)
 local s=e.states[2]; for b=1,C.K.paceBins do s.pace[b]=50 end; s.paceCount=C.K.paceBins; s.paceMean=50
 local yielded=false
 for _=1,8*60 do F.tick(e,f,1/60); if F.yielding(e.states[3].state) then yielded=true end end
 return e,yielded
end
tests.AI_FLASH_BETWEEN_AI=function()
 local e,yielded=held('J')
 assert(e.commands[2].flashEvent>0 and yielded,'faster AI flashes and the car ahead lets it by')
 local _,without=held('J',nil,false); assert(not without,'no yield without AI flashes')
 local same,sameYield=held('C'); assert(same.commands[2].flashEvent==0 and not sameYield,'race: no flash between equals')
 local class,classYield=held('C','car_2:1,car_3:2')
 assert(class.commands[2].flashEvent>0 and classYield,'race: faster class flashes the slower class aside')
end
tests.AI_FLASH_VISUAL_PULSES=function()
 local host=require('tests/host').create(true); local e,f=F.scene('J'); local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false end
 local cmd=e.commands[2]; cmd.flashEvent=1
 local controls=host.controls[1]
 A.apply(a,f,e.commands,e.g,1); assert(controls.headlightsFlash==true and controls.steer==math.huge and controls.gas==0 and controls.clutch==1 and controls.kers==-1)
 controls.headlightsFlash=false; A.apply(a,f,e.commands,e.g,1.2); assert(controls.headlightsFlash==false,'pulses spaced')
 A.apply(a,f,e.commands,e.g,1.45); assert(controls.headlightsFlash==true,'second pulse')
 controls.headlightsFlash=false; A.apply(a,f,e.commands,e.g,2); assert(controls.headlightsFlash==false,'two pulses only')
 cmd.flashEvent=2; f.cars[2].pit=true; A.apply(a,f,e.commands,e.g,3); assert(controls.headlightsFlash==false,'never in the pits')
end
tests.NO_MOVE_UNDER_BRAKING=function()
 local function run(rule,brake)
  local e,f=F.scene('J'); e.profiles.J.noMoveBraking=rule; E.changed(e); F.rear(e,f,60,40); f.cars[2].brake=brake
  F.tick(e,f,3); return e
 end
 assert(F.yielding(run(true,0).states[2].state),'reference yield')
 local braking=run(true,0.6); assert(not F.yielding(braking.states[2].state) and math.abs(braking.states[2].offset)<1e-9,'no move under braking')
 assert(F.yielding(run(false,0.6).states[2].state),'rule disabled')
 local e,f=F.scene('J'); F.rear(e,f,60,40); F.tick(e,f,1.2)
 local before=e.states[2].offset; f.cars[2].brake=0.6; F.tick(e,f,1); assert(e.states[2].offset==before,'move frozen while braking')
end
tests.OVERTAKE_MODE_BOOST=function()
 local function run(mode)
  local e,f=F.scene('C',3); e.profiles.C.overtakeMode=mode; e.profiles.C.overtakeEnabled=false; E.changed(e)
  F.place(f,2,0,100); F.place(f,3,24.4,100); f.cars[2].yawRate=1; F.tick(e,f,0.2); f.cars[2].yawRate=0; F.tick(e,f,2)
  return e
 end
 -- F1 2026 : détection au point de fin de tour, moins d'une seconde derrière la voiture de devant ; gain de niveau dans
 -- les lignes droites du tour suivant ; coupé sous la pluie et avant le passage du leader au point de détection.
 local function lap(mode,gap,setup)
  local e,f=F.scene('C',3); e.profiles.C.overtakeMode=mode; e.profiles.C.overtakeEnabled=false; E.changed(e)
  F.place(f,2,9450,100); F.place(f,3,9450+gap,100); F.place(f,1,2000,100)
  if setup then setup(e,f) end
  F.tick(e,f,3,true)
  return e
 end
 local on,off=lap(true,24.4),lap(false,24.4)
 assert(on.states[2].overtakeArmed and math.abs(on.commands[2].level/off.commands[2].level-1.02)<0.003,'armed at the detection point: boost on the straight')
 assert(not lap(true,60).states[2].overtakeArmed,'more than a second behind: none')
 assert(not lap(true,24.4,function(e) e.weather.wet=true end).states[2].overtakeArmed,'low grip (wet): none')
 assert(not lap(true,24.4,function(e) e.drsRule.restart=true end).states[2].overtakeArmed,'after a restart, until the leader reaches the detection point: none')
 -- Une détection par tour, au point de fin de tour : rien en milieu de tour ; armée, aucun gain dans un virage.
 local e,f=F.scene('C',3); e.profiles.C.overtakeMode=true; e.profiles.C.overtakeEnabled=false; E.changed(e)
 F.place(f,2,3000,100); F.place(f,3,3024.4,100); F.place(f,1,8000,100); F.tick(e,f,3,true)
 assert(not e.states[2].overtakeArmed,'no detection mid-lap')
 local turning=function(_,f2) f2.cars[2].yawRate=1 end
 local onC,offC=lap(true,24.4,turning),lap(false,24.4,turning)
 assert(onC.states[2].overtakeArmed and math.abs(onC.commands[2].level/offC.commands[2].level-1)<0.003,'no gain in a corner')
end
tests.PREDICTABLE_SLOW_CLASS=function()
 local function run(rule)
  local e,f=F.scene('C',3); local p=e.profiles.C
  p.multiClass=true; p.classPatterns='car_2:2,car_3:1'; p.predictableSlowClass=rule; E.changed(e)
  F.rear(e,f,60,25); F.tick(e,f,4); return e
 end
 local free,steady=run(false),run(true)
 assert(F.yielding(free.states[2].state) and math.abs(free.states[2].offset)>0.1,'reference: slower class moves aside')
 assert(F.yielding(steady.states[2].state) and math.abs(steady.states[2].offset)<0.02,'endurance: slower class keeps its line')
 assert(steady.commands[2].level<free.commands[2].level+1e-9,'and lifts')
end
tests.BOP_AND_PRO_AM=function()
 local Classes=require('src/classes'); local Persona=require('src/persona')
 local p=C.effective('C',C.preset('Course','C',{})); p.bopEnabled=true; p.bopStrengthPct=2
 local states,cars={},{}
 for i=1,3 do states[i]={class=1,paceCount=100,paceMean=40+i*5,bop=0}; cars[i]={valid=true,player=false} end
 local k=Classes.new(); for t=0,600,60 do Classes.balance(k,cars,states,3,p,t) end
 assert(states[1].bop>0 and states[3].bop<0 and math.abs(states[2].bop)<1e-9 and states[1].bop<=0.02 and states[3].bop>=-0.02,'converges within the bound')
 p.bopEnabled=false; Classes.balance(k,cars,states,3,p,700); assert(states[1].bop==0)
 local q=C.effective('Q',C.preset('Qualifications','Q',{})); q.proAmEnabled=true
 local a,b={},{}; Persona.fill(a,19731019,5,'Q',q,0); Persona.fill(b,19731019,5,'C',q,0)
 assert(a.grade==b.grade and a.gradeLevel==C.K.gradeLevel[a.grade],'grade stable across the weekend')
 q.proAmEnabled=false; Persona.fill(a,19731019,5,'Q',q,0); assert(a.gradeLevel==1 and a.gradeCaution==1)
 local counts={0,0,0,0}; for i=1,400 do Persona.fill(a,19731019,i,'C',q,0); counts[a.grade]=counts[a.grade]+1 end
 for g=1,4 do assert(counts[g]>60,'four grades represented') end
end
-- Arrêt obligatoire en course : chaque IA à son moment dans la fenêtre, pas plus de trois appelées à la fois,
-- arrêt compté au passage à l'emplacement, pneus neufs ; rien hors course ni sans règles.
local function race(count,profile)
 local e,f=F.scene(profile or 'C',count); local p=e.profiles[profile or 'C']
 p.mandatoryStops=1; p.pitWindowOpenPct=25; p.pitWindowClosePct=75; E.changed(e)
 f.sessionLaps=20; f.leaderLaps=0; f.timedRace=false
 for i=2,count do local a=f.cars[i]; a.tyresKnown=true; a.compoundIndex=0; a.dryCompound=0; a.dryCompounds={[0]=true,[1]=true}; F.place(f,i,(i-2)*500,150) end
 return e,f,p
end
local function wanting(e,f) local n=0; for i=2,f.count do if e.commands[i].rulePit then n=n+1 end end return n end
-- 1.8.0 (relecture) : une IA arrivée ne garde pas sa place d'appel ; une IA disqualifiée n'est plus comptée.
tests.PIT_CALLS_RELEASED=function()
 local e,f=race(8); f.leaderLaps=15; F.tick(e,f,1)
 assert(wanting(e,f)==C.K.pitConcurrent)
 for i=2,f.count do if e.commands[i].rulePit then f.cars[i].finished=true end end
 F.tick(e,f,0.5)
 assert(wanting(e,f)==C.K.pitConcurrent,'finished cars no longer hold call slots')
 local k; for i=2,f.count do if not f.cars[i].finished then k=i; break end end
 local total=e.pits.total; e.penalties.ai.dq[k]=true; F.tick(e,f,0.5)
 assert(e.pits.total==total-1 and not e.commands[k].rulePit,'disqualified AI neither counted nor called')
end
tests.MANDATORY_PIT_WINDOW=function()
 local e,f,p=race(4)
 f.leaderLaps=4; F.tick(e,f,1); assert(wanting(e,f)==0 and e.pits.state=='pending','before the window')
 f.leaderLaps=14; F.tick(e,f,1); assert(wanting(e,f)==3 and e.pits.state=='open' and e.incidents.messageKind=='pitOpen','every AI called inside the window')
 local a=f.cars[2]; a.pit=true; a.inPitBox=true; a.kmh=0; F.tick(e,f,0.5)
 assert(e.pits.cars[2].stops==1 and e.commands[2].pitCompound==0,'stop counted, fresh tyres of the same compound')
 a.inPitBox=false; a.pit=false; a.kmh=150; F.tick(e,f,0.5); assert(not e.commands[2].rulePit and e.pits.done==1)
 p.pitCompoundChange=true; E.changed(e); local b=f.cars[3]; b.pit=true; b.inPitBox=true; b.kmh=0; F.tick(e,f,0.5)
 assert(e.commands[3].pitCompound==1,'F1: another dry compound')
 -- Fenêtre en deux arrêts : le second dans la seconde moitié.
 local e2,f2,p2=race(3); p2.mandatoryStops=2; E.changed(e2); f2.leaderLaps=9; F.tick(e2,f2,1)
 local first=wanting(e2,f2)
 f2.cars[2].inPitBox=true; f2.cars[2].pit=true; F.tick(e2,f2,0.2); f2.cars[2].inPitBox=false; f2.cars[2].pit=false; F.tick(e2,f2,0.2)
 assert(e2.pits.cars[2].stops==1 and not e2.commands[2].rulePit,'second stop not yet due')
 f2.leaderLaps=15; F.tick(e2,f2,0.5); assert(e2.commands[2].rulePit and first>=0,'second stop due later')
 -- Concurrence : au plus trois IA appelées hors des stands.
 local e3,f3=race(8); f3.leaderLaps=15; F.tick(e3,f3,1); assert(wanting(e3,f3)==C.K.pitConcurrent,'at most three at once')
 -- Hors course, sans règles ou sans arrêt demandé : rien.
 local e4,f4=race(4,'Q'); f4.leaderLaps=15; F.tick(e4,f4,1); assert(wanting(e4,f4)==0)
 local e5,f5,p5=race(4); p5.section_rules=false; E.changed(e5); f5.leaderLaps=15; F.tick(e5,f5,1); assert(wanting(e5,f5)==0)
 local e6,f6,p6=race(4); p6.mandatoryStops=0; E.changed(e6); f6.leaderLaps=15; F.tick(e6,f6,1); assert(wanting(e6,f6)==0 and e6.pits.state=='off')
 -- Course chronométrée : avancement par le temps restant.
 local e7,f7=race(3); f7.sessionLaps=0; f7.sessionMinutes=60; f7.left=600; F.tick(e7,f7,1); assert(e7.pits.progress>0.8 and wanting(e7,f7)==2)
end
tests.STINT_AND_MIN_PIT_TIME=function()
 local e,f,p=race(3); p.mandatoryStops=0; p.maxStintMin=1; p.minPitTime=10; E.changed(e)
 F.tick(e,f,30); assert(not e.commands[2].rulePit,'stint not over')
 F.tick(e,f,31); assert(e.commands[2].rulePit,'end of stint')
 local a=f.cars[2]; a.pit=true; a.inPitBox=true; a.kmh=0; F.tick(e,f,1)
 assert(e.commands[2].pitHold and not e.commands[2].rulePit,'held in the box')
 F.tick(e,f,9.5); assert(not e.commands[2].pitHold,'released after the minimum time')
 a.inPitBox=false; a.pit=false; a.kmh=150; F.tick(e,f,30); assert(not e.commands[2].rulePit,'new stint')
end
tests.PIT_STOPS_SURVIVE_RELOAD=function()
 local Pits=require('src/pits')
 local e,f=race(3); f.cars[2].identity='abc'; f.cars[3].identity='def'; F.tick(e,f,0.2)
 -- Arrêt avant la fenêtre : ne compte pas pour l'obligation.
 f.cars[2].inPitBox=true; F.tick(e,f,0.2); f.cars[2].inPitBox=false; F.tick(e,f,0.2)
 assert(e.pits.cars[2].stops==1 and e.pits.cars[2].windowStops==0,'stop before the window does not count')
 f.leaderLaps=14; f.cars[2].inPitBox=true; F.tick(e,f,0.2)
 local text=Pits.serialize(e.pits,f.session); assert(text:find('abc,1',1,true))
 -- Rechargement pendant l'arrêt : le passage en cours n'est pas compté une seconde fois.
 local inBox=Pits.new(); Pits.restore(inBox,text,f.session); e.pits=inBox; F.tick(e,f,0.5)
 assert(inBox.cars[2].windowStops==1,'no double count after a reload in the box')
 f.leaderLaps=0
 local again=Pits.new(); Pits.restore(again,text,f.session); local e2,f2=race(3); e2.pits=again
 f2.cars[2].identity='abc'; f2.cars[3].identity='def'; f2.leaderLaps=15; F.tick(e2,f2,0.5)
 assert(again.cars[2].windowStops==1 and not e2.commands[2].rulePit and e2.commands[3].rulePit,'stop kept across a reload')
 local other=Pits.new(); Pits.restore(other,text,f.session+1); assert(other.restoredSession==-1,'other session ignored')
end
tests.PIT_REQUEST_ARBITER=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C'); local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false end
 local cmd=e.commands[2]; cmd.rulePit=true; cmd.weatherManaged=true; cmd.weatherPit=false; cmd.weatherCompound=-1
 A.apply(a,f,e.commands,e.g,1); assert(host.pitRequests[1]==true,'rule stop not cancelled by dry weather')
 cmd.rulePit=false; A.apply(a,f,e.commands,e.g,2.5); assert(host.pitRequests[1]==false,'released by the app that asked')
 host.pitRequests[1]=nil; A.apply(a,f,e.commands,e.g,4); assert(host.pitRequests[1]==nil,'never false for a native stop')
 local car=f.cars[2]; car.pit=true; car.inPitBox=true; car.kmh=0; host.cars[1].isInPit=true; host.cars[1].speedKmh=0
 cmd.rulePit=true; cmd.pitCompound=0; cmd.pitVisit=1; A.apply(a,f,e.commands,e.g,5); assert(host.cars[1].compoundIndex==0 and a.cars[2].tyreVisit==1,'fresh tyres')
 local calls=host.calls; A.apply(a,f,e.commands,e.g,11); assert(a.cars[2].tyreVisit==1 and host.calls==calls,'one set per visit')
end
-- Voiture de sécurité : garée, sortie sur incident majeur, peloton limité et en file, rentrée, drapeau vert, garée.
tests.SAFETY_CAR_CYCLE=function()
 local e,f=F.scene('C',5); e.profiles.C.neutralization='sc'; e.g.safetyCarModel='sc_car'; E.changed(e)
 f.cars[5].id='sc_car'
 for i=2,4 do F.place(f,i,(i-2)*400,150) end
 F.place(f,5,7000,0); f.cars[5].pit=true; f.cars[5].inPitBox=true
 F.tick(e,f,1)
 assert(e.incidents.safety==5 and e.incidents.safetyPhase=='parked' and e.commands[5].scPark,'parked in the pits')
 assert(not e.commands[5].active and not e.commands[5].rulePit,'never managed as a competitor')
 F.place(f,4,5000,0); F.tick(e,f,18)
 assert(e.incidents.neutral and e.incidents.neutralMode=='sc' and e.incidents.safetyPhase=='call','called on the major incident')
 assert(e.commands[5].scPark and e.incidents.messageKind=='sc','still parked while the field slows down')
 F.tick(e,f,6); assert(fallback(e.commands[2].yellowLimit,80) and e.states[2].yellow,'field under the FCY delta before the release')
 -- Beta 1.48 : libérée, elle est posée en piste devant le meneur (commande de position), jamais conduite hors de son
 -- emplacement ; le peloton reste sous le delta FCY tant qu'elle n'est pas en piste.
 F.tick(e,f,5); assert(e.incidents.safetyPhase=='place' and not e.commands[5].scPark and e.commands[5].scSpeed==C.K.unlimitedSpeed,'released after the call time, its point known: unparked, to be placed on track')
 local at=e.commands[5].place; assert(at>=0 and e.commands[5].placeFor~=nil and e.commands[5].placeKmh==C.K.scLeadKmh,'position command')
 for j=1,4 do local b=f.cars[j]; if not b.pit then assert(math.abs(((b.spline-at+0.5)%1)-0.5)*f.length>=C.K.scPlaceFree,'free point '..j) end end
 F.tick(e,f,2); assert(fallback(e.commands[2].yellowLimit,80),'FCY kept until it is on track')
 assert(e.incidents.safetyPhase=='place' and e.commands[5].place>=0,'nothing moved it: still to be placed')
 f.cars[5].pit=false; f.cars[5].inPitBox=false; F.place(f,5,at*f.length,120); F.tick(e,f,1)
 assert(e.incidents.safetyPhase=='out' and e.commands[5].place<0 and e.incidents.safetyLeft and not e.commands[5].scPark,'placed: on track, no more position command')
 F.place(f,5,1000,120); F.tick(e,f,0.1)
 assert(math.abs(e.commands[2].yellowLimit-160)<1e-6,'then safety car pace plus catch-up')
 F.place(f,3,20,150); e.states[2].nextPerception=0; F.tick(e,f,4)
 assert(e.commands[2].yellowLimit>=150-1e-6 and e.commands[2].yellowLimit<=150+(20-4.4-C.K.queueKeep)*C.K.queueClose+1e-6,'queue: never faster than the car ahead, beyond a slight closing')
 F.place(f,4,5000,150)
 F.tick(e,f,62); assert(e.incidents.safetyPhase=='in' and e.commands[5].rulePit and e.incidents.neutral and e.incidents.messageKind=='scIn','in this lap')
 f.cars[5].pit=true; F.tick(e,f,0.5)
 assert(not e.incidents.neutral and e.incidents.messageKind=='restart' and e.incidents.safetyPhase=='parking','green at the pit entry')
 assert(e.fl.kind=='relance','Beta 1.47: careful first lap armed at the green flag')
 assert(e.incidents.restart and e.incidents.cars[2].restart and e.states[2].yellow,'no overtaking until the line')
 f.cars[5].inPitBox=true; f.cars[5].kmh=0; F.tick(e,f,0.5); assert(e.incidents.safetyPhase=='parked' and e.commands[5].scPark)
 local e2,f2=F.scene('C',4); e2.profiles.C.neutralization='sc'; e2.g.safetyCarModel='missing'; E.changed(e2)
 F.place(f2,2,0,150); F.place(f2,3,6000,0); F.tick(e2,f2,20)
 assert(e2.incidents.neutral and e2.incidents.neutralMode=='fcy' and e2.incidents.safety==0,'no safety car on the grid: FCY')
 local e3,f3=F.scene('Q',4); e3.profiles.Q.neutralization='sc'; e3.g.safetyCarModel='sc_car'; E.changed(e3); f3.cars[4].id='sc_car'
 F.place(f3,4,7000,0); f3.cars[4].pit=true; f3.cars[4].inPitBox=true; F.tick(e3,f3,1)
 assert(e3.commands[4].scPark,'parked in every session, deployed only in the race')
end
tests.SAFETY_CAR_WRITES=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C'); local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false end
 local cmd=e.commands[3]; cmd.scPark=true; cmd.scSpeed=C.K.unlimitedSpeed
 -- Beta 1.50 : garée sans pilote seulement en repli (sorties de son emplacement malgré l'attente d'AC, SC_HOLD_150).
 a.cars[3].scEscapes=C.K.scEscapeMax
 -- Beta 1.48 : jamais garée hors de son emplacement (retour au stand manqué : en travers de la piste).
 A.apply(a,f,e.commands,e.g,1); assert(host.teleports==1 and host.parked[2]==nil,'brought back to its pit, not parked on track')
 f.cars[3].pit=true; f.cars[3].inPitBox=true; A.apply(a,f,e.commands,e.g,1.2); assert(host.teleports==1 and host.parked[2]==true,'parked in its box')
 host.parked[2]=nil; A.apply(a,f,e.commands,e.g,1.5); assert(host.teleports==1 and host.parked[2]==nil,'teleported once, pulses spaced')
 A.apply(a,f,e.commands,e.g,3.3); assert(host.parked[2]==true,'parking renewed')
 cmd.scPark=false; cmd.scSpeed=120; f.cars[3].pit=true; A.apply(a,f,e.commands,e.g,3.5); assert(host.parked[2]==false and host.speedLimits[2]==nil and a.caps.speed.failures==0,'no command in the pit lane')
 f.cars[3].pit=false; f.cars[3].inPitBox=false; host.cars[2].isInPit=false; host.cars[2].isInPitlane=false; A.apply(a,f,e.commands,e.g,4)
 assert(host.parked[2]==false and host.speedLimits[2]==120,'released at limited speed')
 cmd.scPark=true; cmd.scSpeed=C.K.unlimitedSpeed; A.apply(a,f,e.commands,e.g,5); assert(host.parked[2]==false and host.teleports==2,'on track: sent back, not parked there')
 f.cars[3].pit=true; f.cars[3].inPitBox=true; A.apply(a,f,e.commands,e.g,5.1); assert(host.parked[2]==true,'parked again in its box')
 A.checkpoint(a,f,true); local b=A.new(); assert(A.access(b)); A.recover(b,f); assert(b.cars[3].parked)
 host.releasing=true; A.restore(b,f,false,6,true); host.releasing=false
 assert(host.parked[2]==false and host.speedLimits[2]==C.K.unlimitedSpeed and not b.cars[3].owned,'handed back on unload')
end
-- Journal de session : chaque ligne du journal circulaire reprise une seule fois, dans l'ordre, même après un tour complet.
tests.JOURNAL_COLLECT=function()
 local U=require('src/util'); local J=require('src/journal')
 local log=U.newLog(5,100,0); local j=J.new()
 for t=1,3 do U.log(log,t,'INFO','ligne '..t,-1) end
 J.collect(j,log,'H'); local first=J.take(j)
 assert(first:find('ligne 1',1,true) and first:find('ligne 3',1,true) and first:find('ligne 1',1,true)<first:find('ligne 3',1,true),'oldest first')
 J.collect(j,log,'H'); assert(J.take(j)==nil,'nothing twice')
 for t=4,9 do U.log(log,t,'INFO','ligne '..t,-1) end
 J.collect(j,log,'H'); local second=J.take(j)
 assert(not second:find('ligne 3',1,true) and second:find('ligne 9',1,true) and select(2,second:gsub('\n',''))==5,'ring wrap keeps the last lines once')
 local e=F.scene('C',4); local summary=J.summary(e)
 assert(summary:find('resume: profil C',1,true) and summary:find('IA 3',1,true),'summary')
end
-- Une IA seule en ligne droite, sans manœuvre : la variation de trajectoire ne déclenche jamais le plafond anti-zigzag.
tests.DRIVE_JITTER_NOT_COUNTED=function()
 -- Variation par défaut, puis variation maximale qui fait changer la ligne de côté.
 for _,jitter in ipairs({0.05,0.15}) do
  local e,f=F.scene('C',3); local p=e.profiles.C; C.preset('Course','C',p); p.personalLineJitter=jitter; E.changed(e)
  F.place(f,2,0,150); F.place(f,3,3000,150)
  local frozen,low,high=0,math.huge,-math.huge
  for _=1,120*60 do
   F.tick(e,f,1/60,true); local s=e.states[2]
   if e.time<s.driveUntil then frozen=frozen+1 end
   if e.time>10 then low=math.min(low,s.offset); high=math.max(high,s.offset) end
  end
  assert(frozen==0,'isolated AI frozen '..frozen..' frames by its own line variation')
  assert(high-low>0.01,'line variation still applied')
 end
end
-- Les manœuvres restent plafonnées : six changements en une minute, puis repos ; un seul avertissement par déclenchement.
tests.MANEUVER_ZIGZAG_CAPPED=function()
 local D=require('src/director'); local e,f=F.scene('J',3); local s=e.states[2]; local a=f.cars[2]; local row=e.perception.rows[2]
 s.state='YIELD_IN'; row.left=false; row.right=false
 local now=100; local logs=0
 for n=1,8 do
  for _=1,120 do
   now=now+1/60; D.lateral(s,(n%2==0 and 1 or -1)*0.6,row,a,e.run,e.runtimeG,1/60,now)
   if s.newDirectionLimit then logs=logs+1; s.newDirectionLimit=false end
  end
 end
 assert(s.driveUntil>now and s.directionCount<=C.K.directionLimit,'sixth change starts the rest')
 assert(logs==1,'one warning per trigger, got '..logs)
end
tests.ZONES_FILE_ABSENT=function()
 require('tests/host').create(true)
 local Snapshot=require('src/snapshot')
 ac.readDataFile=function() return '' end
 local data,reason=Snapshot.zones('spa'); assert(data==nil and reason=='absent','missing zone file is not a syntax error')
end
-- Glissade qui se stabilise : un seul incident, délai d'incident majeur conservé ; fin après 2 s de conduite normale.
tests.INCIDENT_CLEAR_HYSTERESIS=function()
 local e,f=F.scene('J',3); local car=F.place(f,3,500,60)
 car.slip=90; F.tick(e,f,1); local c=e.incidents.cars[3]; local since=c.since
 assert(c.incident and e.incidents.started==1)
 car.slip=0; F.tick(e,f,1.2); assert(c.incident and c.since==since,'brief recovery keeps the incident')
 car.slip=90; F.tick(e,f,1); assert(c.since==since and e.incidents.started==1,'same incident, major timer kept')
 car.slip=0; F.tick(e,f,3); assert(not c.incident and e.incidents.zoneCount==1,'ends after calm driving, zone held')
end
-- Résumé du journal : événements comptés sur la minute, puis remis à zéro.
tests.JOURNAL_MINUTE_COUNTERS=function()
 local J=require('src/journal')
 local e,f=F.scene('J',4)
 F.place(f,2,0,130); F.place(f,3,30,100); F.place(f,4,4000,100)
 for _=1,8*60 do F.tick(e,f,1/60) end
 local first=J.summary(e)
 local tried=tonumber(first:match('depassements tentes (%d+)'))
 assert(tried and tried>=1,'overtake attempts counted: '..first)
 local second=J.summary(e)
 assert(second:match('depassements tentes (%d+)')=='0' and second:match('incidents (%d+), IA')=='0','counters reset after each summary')
 F.place(f,4,60,0); F.tick(e,f,3); assert(J.summary(e):match('sur la minute.*incidents (%d+)')=='1','incident counted')
end
-- Dépassement lent (5 km/h d'écart) : après le côte à côte, l'IA termine et le dépassement est compté réussi.
local function slowPass(after)
 local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); e.profiles.C.defenseEnabled=false; E.changed(e)
 local a=F.place(f,2,0,105); local b=F.place(f,3,30,100); F.place(f,4,5000,100)
 -- Fin du premier dépassement seulement (un éventuel dépassement enchaîné ensuite n'est pas jugé ici).
 local reasons={}; local first
 for _=1,40*60 do
  if after then after(e,f,a,b) end
  F.tick(e,f,1/60,true); local s=e.states[2]
  if not first and (s.state=='OVT_OUT' or s.reason=='chain') then first=s.reason; reasons[first]=true end
 end
 return e,reasons,a,b
end
tests.OVERTAKE_FINISHES_AFTER_ALONGSIDE=function()
 local e,reasons,a,b=slowPass()
 local function aborted(r) return r.abort_blocked or r.abort_slow or r.abort_follower end
 assert(reasons.clear and not aborted(reasons) and a.z>b.z,'slow pass completed and counted as a success')
 assert((e.stats.clear or 0)>=1 and (e.stats.abort_blocked or 0)+(e.stats.abort_slow or 0)+(e.stats.abort_follower or 0)==0)
 -- Couloir fermé par une troisième voiture après le côte à côte : l'IA termine quand même.
 local _,closed=slowPass(function(e,f,_,b)
  local s=e.states[2]
  if s.passAlongside and f.cars[4].z>1000 then F.place(f,4,b.z+40,100,s.offset*5) end
 end)
 assert((closed.clear or closed.chain) and not aborted(closed),'no abort once side by side (success, possibly chained)')
 -- La cible repasse devant et s'éloigne : abandon réel.
 local _,lost=slowPass(function(e,f,a)
  if e.states[2].passAlongside then a.kmh=85; a.speed=85/3.6 end
 end)
 assert(lost.abort_slow,'abort when the target pulls away again')
end
-- Pendant le retour, une voiture à hauteur : l'IA reste en retour (pas de nouveau maintien) et ne se rabat pas vers elle.
tests.OVT_OUT_NO_REENTRY=function()
 local e,f=F.scene('C',3); local s=e.states[2]; local a=F.place(f,2,0,120); F.place(f,3,1000,100)
 s.state='OVT_OUT'; s.target=3; s.targetSide=1; s.offset=0.5; s.filtered=0.5; s.base=0
 local side=F.place(f,3,0,120,-2.5)
 F.tick(e,f,0.5)
 assert(s.state=='OVT_OUT','no return to OVT_HOLD while returning')
 assert(s.offset>=0.5-1e-9 or not e.perception.rows[2].left,'never moves towards the occupied side')
end
-- Repos anti-zigzag en cours et voiture arrêtée devant : l'évitement s'applique pleinement, sans bascule.
tests.AVOID_BEATS_DIRECTION_REST=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e)
 F.place(f,2,0,60); F.place(f,3,120,0); F.tick(e,f,2.5)
 local s=e.states[2]; s.driveUntil=e.time+20
 local reached=0
 for _=1,4*60 do F.tick(e,f,1/60); reached=math.max(reached,math.abs(s.offset)) end
 assert((e.stats.obstacle or 0)<=2,'no AVOID/DRIVE flapping: '..tostring(e.stats.obstacle))
 assert(s.state=='AVOID' and reached>=e.run.avoidOffset-0.02,'full avoidance offset during the rest: '..reached)
 -- Plafond déjà atteint : un évitement n'est jamais refusé.
 local e2,f2=F.scene('C',3); C.preset('Course','C',e2.profiles.C); E.changed(e2)
 F.place(f2,2,0,60); F.place(f2,3,5000,60); F.tick(e2,f2,0.2)
 local s2=e2.states[2]; for j=1,C.K.directionLimit do s2.directions[j]=e2.time end; s2.direction=-1
 F.place(f2,3,120,0); F.tick(e2,f2,5)
 assert(s2.directionCount<=C.K.directionLimit)
 assert(s2.state=='AVOID' and math.abs(s2.offset)>0.3,'avoidance never refused by the zigzag cap')
end
-- Tête-à-queue puis arrêt lent : un seul incident.
tests.SPIN_THEN_STOP_ONE_INCIDENT=function()
 -- Décélération relevée dans le journal : encore au-dessus de 25 km/h juste après la glissade, puis arrêt.
 local e,f=F.scene('J',3); local car=F.place(f,3,500,50)
 car.slip=90; F.tick(e,f,1)
 car.slip=0; car.kmh=30; car.speed=30/3.6; F.tick(e,f,1)
 car.kmh=15; car.speed=15/3.6; F.tick(e,f,1.5)
 car.kmh=0; car.speed=0; F.tick(e,f,2.5)
 assert(e.incidents.started==1 and e.incidents.cars[3].incident,'spin then stop is one incident')
end
-- Virages enchaînés : rotation variable et bruitée, lissée comme dans l'instantané du jeu.
local function cornerYaw(cars,period,noise)
 local seed,smooth=7,0
 return function(time)
  seed=(seed*1103515245+12345)%2147483648
  local yaw=(period>0 and 0.3*math.sin(time/period*2*math.pi) or 0)+noise*(seed/2147483648-0.5)*2
  smooth=smooth+(yaw-smooth)*(1-math.exp(-(1/60)/C.K.yawTau))
  for _,a in ipairs(cars) do a.yawRate=smooth end
 end
end
-- Écart de cession réduit en virage : la cession va à son terme, sans être comptée comme un zigzag (relevé en jeu).
tests.CORNER_YIELD_COMPLETES=function()
 for _,case in ipairs({{0,0.1},{3,0.05},{6,0.1}}) do
  local e,f=F.scene('P',3); C.preset('Essais','P',e.profiles.P); E.changed(e)
  local slow=F.place(f,2,0,100); local fast=F.place(f,3,-150,125)
  local turn=cornerYaw({slow,fast},case[1],case[2])
  for _=1,40*60 do turn(e.time); F.tick(e,f,1/60,true) end
  assert((e.stats.passed or 0)==1 and (e.stats.direction_limit or 0)==0 and (e.stats.limit or 0)==0,'yield completed in corners '..case[1]..'/'..case[2])
 end
end
-- Même garde pour un dépassement en virages.
tests.CORNER_OVERTAKE_COMPLETES=function()
 for _,case in ipairs({{3,0.05},{6,0.1}}) do
  local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); e.profiles.C.defenseEnabled=false; E.changed(e)
  local me=F.place(f,2,0,115); local other=F.place(f,3,30,100)
  local turn=cornerYaw({me,other},case[1],case[2])
  for _=1,40*60 do turn(e.time); F.tick(e,f,1/60,true) end
  assert((e.stats.clear or 0)>=1 and (e.stats.direction_limit or 0)==0,'overtake completed in corners')
 end
end
-- Cession demandée par un appel de phares d'IA en virage : jamais interrompue par le plafond (relevé : voitures 7 et 8).
tests.CORNER_FLASH_YIELD_HELD=function()
 local e,f=F.scene('J',3); local p=e.profiles.J
 p.aiFlashEnabled=true; p.pressureEnabled=false; p.multiClass=false; E.changed(e)
 local a=F.place(f,2,0,100); local b=F.place(f,3,29.4,100)
 local s=e.states[2]; for k=1,C.K.paceBins do s.pace[k]=50 end; s.paceCount=C.K.paceBins; s.paceMean=50
 local turn=cornerYaw({a,b},3,0.05); local yielded=0
 for _=1,20*60 do turn(e.time); F.tick(e,f,1/60); if F.yielding(e.states[3].state) then yielded=yielded+1 end end
 assert(e.commands[2].flashEvent>0 and yielded>10*60,'flash-requested yield held in corners: '..yielded)
 assert((e.stats.direction_limit or 0)==0,'never interrupted by the zigzag cap')
end
-- Journal : manœuvre interrompue par le plafond comptée sur la minute.
tests.JOURNAL_INTERRUPTED_COUNTER=function()
 local J=require('src/journal')
 local e,f=F.scene('C',3); F.place(f,2,0,100); F.place(f,3,4000,100)
 local s=e.states[2]; s.state='YIELD_HOLD'; s.driveUntil=e.time+20
 F.tick(e,f,0.1)
 assert(s.state=='DRIVE' and J.summary(e):match('interrompues par blocage (%d+)')=='1','interrupted maneuver counted')
end
-- Infobulles : une explication propre à chaque réglage et à chaque option globale, en français, découpée en lignes.
tests.TIPS_COMPLETE=function()
 local T=require('src/tips')
 local seen={}
 local function check(text,name)
  assert(type(text)=='string' and #text>=40,'tooltip missing or too short: '..name)
  assert(not seen[text],'tooltip duplicated: '..name); seen[text]=true
  assert(text:find('[éèàêùç’]') or text:find(' de ',1,true) and text:find(' la ',1,true),'tooltip not French: '..name)
  for _,word in ipairs({' the ',' and ',' when ',' with ',' default '}) do assert(not text:lower():find(word,1,true),'English word in '..name) end
 end
 for _,s in ipairs(C.schema) do check(T.settings[s.key],s.key) end
 for _,key in ipairs({'levelMode','useGripBoost','useBrakeAssist','overrideAwareness','debugLog','occLatMin','occLatMax','occMargin','occSpeedGain','gripPerLevelPct','seed'}) do check(T.globals[key],key) end
 for _,group in ipairs(C.sections) do assert(T.tabs[group] and T.sections[group],'tab tooltips: '..group) end
 for _,profile in ipairs(C.profiles) do assert(T.profiles[profile],'profile tooltip: '..profile) end
 for _,name in ipairs(C.ruleCategories) do assert(T.rules[name],'rule tooltip: '..name) end
 local count=0; for key in pairs(T.settings) do count=count+1; local found=false; for _,s in ipairs(C.schema) do if s.key==key then found=true end end; assert(found,'tooltip for unknown setting: '..key) end
 assert(count==#C.schema)
 local wrap=require('src/ui').wrap
 local wrapped=wrap(T.settings.lateralCooldown)
 for line in (wrapped..'\n'):gmatch('(.-)\n') do assert(#line<=C.K.uiTipWidth or not line:find(' '),'line too long') end
 assert(wrapped:gsub('\n',' ')==T.settings.lateralCooldown,'wrapping keeps every word')
end
-- Drapeau rouge (course) : trois voitures immobilisées en piste, joueur exclu ; retour aux stands, dépannage, reprise.
tests.RED_FLAG_PROCEDURE=function()
 local Panel=require('src/panel')
 local e,f=F.scene('C',6); C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagHold=20; E.changed(e)
 for i=2,6 do F.place(f,i,(i-1)*300,120) end
 -- Beta 1.47 : trois voitures arrêtées en travers de la piste (piste bloquée), immobilisées K.redIncidentStill s.
 F.block(f,{3,4,5},600)
 -- Beta 1.48 : classement au drapeau rouge (figé) : la voiture 6 mène, la 2 est cinquième, le joueur sixième.
 f.cars[6].position=1; f.cars[5].position=2; f.cars[4].position=3; f.cars[3].position=4; f.cars[2].position=5; f.cars[1].position=6
 F.tick(e,f,C.K.redIncidentStill+3)
 local t=e.incidents
 assert(t.red and t.onTrack==3,'red flag on three immobilised cars')
 assert(t.redOrderN==6 and t.redRank[6]==1 and t.redRank[2]==5 and t.redRank[1]==6,'order frozen, player included')
 assert(e.commands[2].rulePit and e.commands[6].rulePit,'every AI called to the pits')
 assert(e.commands[6].yellowLimit<=e.run.redFlagSpeedKmh+20 and e.states[6].yellow,'slowed down outside any yellow zone, no overtaking')
 assert(e.panel.kind=='red' and e.panel.title==require('src/lang').flagTitles.red,'red flag panel')
 F.tick(e,f,3); assert(e.commands[3].recover and not e.commands[2].recover,'immobilised AI recovered, moving AI drives in')
 F.tick(e,f,15); assert(t.red and t.reds==1,'no restart while AI are still out on track, even after the hold')
 for _,i in ipairs({2,6}) do local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0 end
 F.tick(e,f,1); assert(t.red and e.commands[2].pitHold and not e.commands[2].rulePit,'held in the pit box while others are recovered')
 for i=3,5 do local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0; F.place(f,i,200+i*100,0); a.pit=true; a.inPitBox=true end
 F.place(f,6,1500,0); f.cars[6].pit=true; f.cars[6].inPitBox=true; F.place(f,2,100,0); f.cars[2].pit=true; f.cars[2].inPitBox=true
 F.tick(e,f,5); assert(t.red,'restart waits for the player too')
 f.cars[1].pit=true; f.cars[1].inPitBox=true
 -- Beta 1.48 : une IA encore en route vers son emplacement : pas de reprise.
 f.cars[4].inPitBox=false; F.tick(e,f,30); assert(t.red,'no restart while an AI still drives in the pit lane')
 -- Beta 1.48 : indicateur de reprise : case « REPRISE », consigne avec la voiture à suivre, ligne de session.
 local L=require('src/lang'); local LE=require('src/lang_en')
 F.tick(e,f,0.6)
 assert(e.panel.restartBox=='P6' and e.panel.short==string.format(L.restart.pit,6,'Driver_2') and t.restartState=='pit' and t.restartAhead==2,'red flag in the pits: restart P6 behind Driver_2 / '..tostring(e.panel.restartBox)..' / '..tostring(e.panel.short)..' / '..tostring(t.restartState)..' / '..tostring(t.restartAhead)..' / '..tostring(e.panel.kind))
 assert(e.panel.explain==string.format(L.restart.explain,6),'explanation: restart in the red-flag order')
 for k,v in pairs(L.restart) do assert(type(LE.restart[k])=='string' and select(2,v:gsub('%%[ds]',''))==select(2,LE.restart[k]:gsub('%%[ds]','')),'EN text '..k) end
 f.cars[1].position=2; e.hud.stripAt=-math.huge; F.tick(e,f,1)
 local shown=false; for k=1,e.hud.stripCount do if e.hud.strip[k].label==L.hudPosition and e.hud.strip[k].value:match('^6/') then shown=true end end
 assert(shown,'session line: frozen rank')
 f.cars[4].inPitBox=true
 -- Classement d'AC mélangé après le drapeau rouge : sans effet, l'ordre figé reste.
 f.cars[6].position=5; f.cars[5].position=4; f.cars[4].position=3; f.cars[3].position=2; f.cars[2].position=1
 for _=1,80 do if not t.red then break end; F.tick(e,f,0.5) end
 F.tick(e,f,0.3) -- panneau rafraîchi tous les quarts de seconde
 assert(t.restartState=='wait' and e.panel.short==string.format(L.restart.wait,'Driver_2'),'Beta 1.48: wait for the car ahead in the order')
 -- Beta 1.34 : tour de relance annoncé comme un départ lancé (RS), sous FCY faute de voiture de sécurité.
 assert(not t.red and t.neutral and t.relaunch and t.neutralMode=='fcy' and e.panel.kind=='rolling','relaunch lap under FCY (no safety car) once everyone is in and the hold is over')
 assert(e.commands[2].pitHold and e.commands[6].pitHold,'held until their turn')
 F.tick(e,f,C.K.redReleaseFirst); assert(not e.commands[6].pitHold and e.commands[2].pitHold,'race leader released first')
 -- Chacune attend que la précédente ait quitté son emplacement et dépassé le sien (au plus K.redExitWait s).
 F.tick(e,f,C.K.redReleaseGap+0.1); assert(e.commands[5].pitHold,'second car 5 waits for the leader to leave its box')
 f.cars[6].inPitBox=false; F.tick(e,f,0.1); assert(not e.commands[5].pitHold,'then leaves')
 f.cars[5].inPitBox=false; F.tick(e,f,0.1); assert(e.commands[4].pitHold,'one every 2 s, even with the way clear')
 F.tick(e,f,C.K.redReleaseGap); assert(not e.commands[4].pitHold,'car 4 at its turn')
 F.tick(e,f,C.K.redReleaseGap); assert(e.commands[3].pitHold,'car 3 waits for car 4, still in its box')
 F.tick(e,f,C.K.redExitWait); assert(not e.commands[3].pitHold,'maximum wait')
 f.cars[4].inPitBox=false; f.cars[3].inPitBox=false; F.place(f,3,2000,60); f.cars[3].pit=true
 F.tick(e,f,4*C.K.redReleaseGap); assert(not e.commands[2].pitHold,'fifth released last')
 for i=2,6 do local a=f.cars[i]; a.pit=false; a.inPitBox=false; F.place(f,i,(i-1)*300,120) end; f.cars[1].pit=false
 for _=1,2000 do if not t.neutral then break end; F.tick(e,f,0.5) end
 assert(not t.neutral and not t.relaunch and t.restart and t.messageKind=='restart','green after the relaunch lap, no overtaking until the line')
 assert(e.fl.kind=='relance','Beta 1.47: careful first lap armed after the relaunch lap')
 -- Reprise forcée au délai maximal avec des voitures encore bloquées : pas de nouveau drapeau rouge sur les mêmes incidents.
 local e4,f4=F.scene('C',5); C.preset('Course','C',e4.profiles.C); E.changed(e4)
 F.block(f4,{2,3,4},600); F.place(f4,5,3000,120)
 F.tick(e4,f4,C.K.redIncidentStill+1); assert(e4.incidents.red)
 -- Délai maximal tiré du circuit (10 km de piste au banc) : une IA qui roule encore vers les stands n'est pas lâchée au vert.
 local expected=e4.run.redFlagHold+C.K.redLapFactor*f4.length/(e4.run.redFlagSpeedKmh/3.6)+C.K.redPitMargin
 assert(math.abs(e4.incidents.redMax-expected)<1e-6 and expected>C.K.redFlagMax,'maximum derived from the lap length')
 F.tick(e4,f4,C.K.redFlagMax+20); assert(e4.incidents.red,'still red after 320 s on a long lap')
 F.tick(e4,f4,expected-C.K.redFlagMax-20+1); assert(not e4.incidents.red and e4.incidents.reds==1,'no endless red flag on the same stuck cars')
 -- Une IA qui roule au pas derrière l'accident n'est jamais dépannée ; seule une voiture réellement arrêtée l'est.
 local e6,f6=F.scene('C',6); C.preset('Course','C',e6.profiles.C); E.changed(e6)
 F.block(f6,{2,3,4},600); F.place(f6,5,1250,15); F.place(f6,6,4000,120)
 F.tick(e6,f6,C.K.redIncidentStill+1); assert(e6.incidents.red)
 F.tick(e6,f6,10); assert(e6.commands[2].recover and not e6.commands[5].recover,'crawling AI drives in, stopped AI is recovered')
 -- Joueur exclu : deux IA et le joueur immobilisés ne suffisent pas.
 local e2,f2=F.scene('C',4); C.preset('Course','C',e2.profiles.C); E.changed(e2)
 F.block(f2,{2,1,3},600); F.place(f2,4,1200,120)
 F.tick(e2,f2,C.K.redIncidentStill+1); assert(not e2.incidents.red,'player not counted')
 -- Trois têtes-à-queue simultanés qui roulent encore : pas de drapeau rouge.
 local e5,f5=F.scene('C',5); C.preset('Course','C',e5.profiles.C); E.changed(e5)
 -- Beta 1.47 : en travers de la piste (elle serait bloquée), mais elles roulent encore : jamais immobilisées.
 for k,i in ipairs({2,3,4}) do local car=F.place(f5,i,600,40,-4+(k-1)*4); car.slip=90 end; F.place(f5,5,3000,120)
 F.tick(e5,f5,C.K.redIncidentStill+2); assert(e5.incidents.onTrack>=3 and not e5.incidents.red,'spinning cars still moving: no red flag')
 -- Hors course : jamais de drapeau rouge.
 local e3,f3=F.scene('J',5); C.preset('Nordschleife','J',e3.profiles.J); E.changed(e3)
 for i=2,4 do F.place(f3,i,(i-1)*300,0) end; F.place(f3,5,1500,120)
 F.tick(e3,f3,7); assert(not e3.incidents.red,'race only')
end
-- Panneau : priorités et textes.
tests.FLAG_PANEL_PRIORITY=function()
 local Panel=require('src/panel'); local L=require('src/lang')
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e)
 local p=e.run; local panel=Panel.new()
 local t={red=false,neutral=false,neutralMode='fcy',safetyPhase='none',playerZone=false,playerDistance=0,greenUntil=-math.huge}
 local now=100
 local function at(state) for k,v in pairs(state) do t[k]=v end; now=now+1; Panel.update(panel,t,f,p,'C',now); return panel.kind end
 assert(at({playerZone=true,playerToZone=243,playerInside=false})=='yellow' and panel.detail:find('240 m',1,true) and not panel.raw:find('km/h',1,true) and panel.title==L.flagTitles.yellow,'yellow with the rounded distance to the zone start, no fixed speed')
 assert(at({playerZoneDouble=true})=='yellow' and panel.title==L.flagTitles.yellow2 and panel.double,'double yellow ahead')
 assert(at({playerToZone=0,playerInside=true})=='zone' and panel.title==L.flagTitles.zone,'inside the double yellow: zone delta')
 assert(at({playerZoneDouble=false})=='zone1' and panel.title==L.flagTitles.zone1 and panel.noPass,'inside a single yellow')
 assert(at({neutral=true,neutralMode='vsc'})=='vsc' and panel.detail:find('30 %',1,true),'VSC above yellow')
 assert(at({neutralMode='sc',safetyPhase='call'})=='sc' and panel.raw==L.flagDetails.scCall,'safety car called')
 assert(at({red=true})=='red','red above everything')
 assert(at({red=false,neutral=false,playerZone=false,greenUntil=now+5})=='green')
 assert(at({greenUntil=-math.huge})=='none')
 for line in (panel.detail..'\n'):gmatch('(.-)\n') do assert(#line<=C.K.panelWrap or not line:find(' '),'panel lines bounded') end
 p.flagPanel=false; assert(at({red=true})=='none','panel disabled')
end
-- Drapeau bleu du joueur : une voiture plus rapide qui lui prend un tour arrive derrière, en course seulement.
tests.FLAG_PANEL_BLUE_PLAYER=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e)
 local player=F.place(f,1,10000+500,100); player.lap=2
 local fast=F.place(f,2,10000+420,150); fast.lap=3; fast.spline=(fast.z/f.length)%1
 F.place(f,3,10000+4000,100)
 player.spline=(player.z/f.length)%1; player.lapValid=true; fast.lapValid=true
 F.tick(e,f,0.5); assert(e.panel.kind=='blue','blue flag for the player being lapped')
 fast.lap=2; F.tick(e,f,0.5); assert(e.panel.kind~='blue','no blue flag for a car on the same lap')
end
-- Migration 1.5.0 : panneau seul, le drapeau jaune natif n'est plus imposé ; une seule fois, rien d'autre ne change.
tests.MIGRATION_PANEL_ONLY=function()
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.preset(({J='Nordschleife',P='Essais',Q='Qualifications',C='Course'})[x],x,{}); profiles[x].yellowHud=true; profiles[x].levelPct=88 end
 local g=C.validateGlobals(C.globalDefaults); g.dataRevision=1
 local upgraded=C.migrate(g,profiles)
 assert(upgraded and #upgraded==0 and g.dataRevision==C.dataRevision)
 for _,x in ipairs(C.profiles) do assert(profiles[x].yellowHud==false and profiles[x].levelPct==88 and profiles[x].flagPanel==true,x) end
 profiles.C.yellowHud=true; assert(C.migrate(g,profiles)==nil and profiles.C.yellowHud,'runs once')
 local Presets=require('src/presets'); local store=Presets.layout(); store.name='Ancien'; store.profile='C'; store.revision=1
 for k,v in pairs(C.preset('Course','C',{})) do store['p_'..k]=v end; store.p_yellowHud=true
 assert(Presets.decode(store).p.yellowHud==false,'older custom preset: panel only')
end
-- Sous drapeau rouge, un passage au stand ne compte pas comme arrêt obligatoire.
tests.RED_FLAG_STOP_NOT_COUNTED=function()
 local Pits=require('src/pits')
 local e,f=F.scene('C',3); local p=e.run; p.mandatoryStops=1; p.pitWindowOpenPct=5; p.pitWindowClosePct=95
 f.sessionLaps=20; f.leaderLaps=10; f.timedRace=false; f.sessionMinutes=0; f.pitWindowStart=0; f.pitWindowEnd=0
 local t=Pits.new(); Pits.update(t,f,e.commands,p,'C',100,1,nil,false)
 f.cars[2].inPitBox=true; Pits.update(t,f,e.commands,p,'C',101,1,nil,true)
 assert(t.cars[2].windowStops==0,'red flag stop not counted')
 f.cars[2].inPitBox=false; Pits.update(t,f,e.commands,p,'C',102,1,nil,false)
 f.cars[2].inPitBox=true; Pits.update(t,f,e.commands,p,'C',103,1,nil,false)
 assert(t.cars[2].windowStops==1,'ordinary stop counted')
end
-- Lecture du jeu : cap et glissement ramenés dans [-π, π[ quand le cap d'une voiture franchit ±180°
-- (régression 1.5.0 : la normalisation des angles avait été masquée par une fonction de texte de même nom).
tests.SNAPSHOT_ANGLE_WRAP=function()
 local U=require('src/util')
 assert(type(U.wrap(3*math.pi))=='number' and math.abs(math.abs(U.wrap(3*math.pi))-math.pi)<1e-9 and math.abs(U.wrap(-3.2)-(2*math.pi-3.2))<1e-9,'angle wrap')
 assert(U.wrapText('un deux trois',7)=='un deux\ntrois','text wrap')
 local host=require('tests/host').create(true)
 local Snapshot=require('src/snapshot'); local f=Snapshot.new()
 local car=host.cars[1]
 local function heading(angle) car.look={x=math.sin(angle),z=math.cos(angle)}; car.velocity={x=30*math.sin(angle),z=30*math.cos(angle)} end
 heading(math.pi-0.01); Snapshot.read(f,1/60,0)
 for n=1,30 do heading(math.pi-0.01+n*0.002); Snapshot.read(f,1/60,n/60) end
 local a=f.cars[2]
 assert(math.abs(a.yawRate)<0.5,'yaw rate continuous across ±180°: '..tostring(a.yawRate))
 assert(a.slip<5,'no false slip across ±180°: '..tostring(a.slip))
 -- Vitesse dirigée juste de l'autre côté de ±180° : glissement minime, pas 360°.
 car.look={x=math.sin(math.pi-0.005),z=math.cos(math.pi-0.005)}; car.velocity={x=30*math.sin(-math.pi+0.005),z=30*math.cos(-math.pi+0.005)}
 Snapshot.read(f,1/60,1)
 assert(f.cars[2].slip<5,'velocity and heading straddling ±180°: '..tostring(f.cars[2].slip))
end
-- Diagnostic : chaque capacité CSP a un libellé (lu dynamiquement), chaque état d'IA et chaque raison un texte.
tests.DIAGNOSTIC_LABELS=function()
 local L=require('src/lang'); local Caps=require('src/caps')
 for _,name in ipairs(Caps.names) do assert(type(L[name..'Label'] or L[name])=='string','capability label: '..name) end
 for _,state in ipairs({'IDLE','DRIVE','YIELD_IN','YIELD_HOLD','YIELD_OUT','OVT_ARM','OVT_IN','OVT_HOLD','OVT_OUT','DEFEND','AVOID','CALM'}) do assert(L.states[state],'state label: '..state) end
 for _,reason in ipairs({'abort_blocked','abort_slow','abort_follower','direction_limit','passed','clear','chain','yellow','obstacle','contact','invited','yielded'}) do assert(L.reasons[reason],'reason label: '..reason) end
end
-- 1.6.0 : un seul message par image, le plus important l'emporte.
tests.MESSAGE_PRIORITY=function()
 local I=require('src/incidents'); local t=I.new()
 t.frameId=1; I.message(t,'yellow',1); I.message(t,'fcy',80); assert(t.messageKind=='fcy','higher priority replaces')
 local id=t.messageId; I.message(t,'pitOpen'); assert(t.messageKind=='fcy' and t.messageId==id,'lower priority ignored in the same frame')
 t.frameId=2; I.message(t,'pitOpen'); assert(t.messageKind=='pitOpen','next frame: shown')
end
-- 1.6.0 : voitures qui démarrent en début de session, file d'attente derrière une voiture lente : pas d'incident.
tests.INCIDENT_SPAWN_AND_QUEUE=function()
 local e,f=F.scene('J',4); f.time=2
 for i=2,4 do f.cars[i].id='spawn_'..i; F.place(f,i,(i-2)*300,5) end
 F.tick(e,f,4); assert(e.incidents.activeCount==0,'cars pulling away at the start of a track day are not incidents')
 F.place(f,2,0,60); F.tick(e,f,1); F.place(f,2,0,0); F.tick(e,f,3)
 assert(e.incidents.cars[2].incident,'a car that was moving and stops is an incident')
 local e2,f2=F.scene('J',4)
 F.place(f2,3,5000,0); F.place(f2,4,4990,0); F.tick(e2,f2,4)
 assert(e2.incidents.cars[3].incident and not e2.incidents.cars[4].incident,'only the head of a queue is an incident')
 -- Rechargement de l'app en pleine session : une voiture déjà arrêtée reste un incident.
 local e3,f3=F.scene('J',3); f3.cars[3].id='reloaded'; F.place(f3,3,5000,0); F.tick(e3,f3,4)
 assert(e3.incidents.cars[3].incident,'stopped car found after a reload')
end
-- 1.6.0 : incident majeur seulement pour une voiture immobile ; neutralisation limitée dans le temps ; dépannage.
tests.NEUTRALIZATION_STILL_AND_MAX=function()
 local e,f=F.scene('C',4); e.profiles.C.neutralization='fcy'; E.changed(e)
 F.place(f,2,0,150); F.place(f,3,3000,150); F.place(f,4,6000,8)
 F.tick(e,f,30); assert(e.incidents.cars[4].incident and not e.incidents.neutral,'a crawling car is not a major incident')
 F.place(f,4,6000,0); F.tick(e,f,18); assert(e.incidents.neutral,'stationary car: neutralization')
 F.tick(e,f,10); assert(e.commands[4].recover and not e.commands[1].recover,'stationary AI recovered under neutralization, never the player')
 F.tick(e,f,C.K.neutralMax); assert(not e.incidents.neutral,'neutralization lifted after the maximum')
 F.tick(e,f,60); assert(not e.incidents.neutral,'the same incident does not trigger it again')
 -- Beta 1.7 : hors piste aussi, une IA immobile est dépannée après le court délai tant que la neutralisation dure.
 local e2,f2=F.scene('C',4); e2.profiles.C.neutralization='fcy'; E.changed(e2)
 F.place(f2,2,0,150); F.place(f2,4,6000,0); F.place(f2,3,3000,0); f2.cars[3].offtrack=true
 F.tick(e2,f2,C.K.neutralRecoverTime+5)
 assert(e2.incidents.neutral and e2.commands[3].recover and e2.commands[3].recoverReason=='neutralisation','off the track under neutralization: short delay')
end
-- 1.6.0 : nouvel incident pendant le tour de rentrée de la voiture de sécurité : elle reste en piste.
tests.SAFETY_CAR_STAYS_OUT=function()
 local e,f=F.scene('C',5); e.profiles.C.neutralization='sc'; e.g.safetyCarModel='sc_car'; E.changed(e)
 f.cars[5].id='sc_car'
 for i=2,4 do F.place(f,i,(i-2)*400,150) end
 F.place(f,5,7000,0); f.cars[5].pit=true; f.cars[5].inPitBox=true; F.tick(e,f,1)
 F.place(f,4,5000,0); F.tick(e,f,29)
 -- Beta 1.48 : posée à son point (commande de position), puis en piste.
 assert(e.incidents.safetyPhase=='place' and e.commands[5].place>=0)
 f.cars[5].pit=false; f.cars[5].inPitBox=false; F.place(f,5,e.commands[5].place*f.length,120); F.tick(e,f,0.1)
 F.place(f,5,1000,120); F.tick(e,f,0.9)
 F.place(f,4,5000,150); F.tick(e,f,62); assert(e.incidents.safetyPhase=='in','in this lap')
 F.place(f,3,8000,0); F.tick(e,f,18)
 assert(e.incidents.safetyPhase=='out' and e.incidents.neutral and e.incidents.messageKind=='sc','new major incident: safety car stays out')
end
-- 1.6.0 : VSC sans allure apprise : référence figée au début, jamais la vitesse du moment (pas de spirale).
tests.VSC_REFERENCE_LATCHED=function()
 local e,f=F.scene('C',3); e.profiles.C.neutralization='vsc'; E.changed(e)
 local s=e.states[2]; for b=1,#s.pace do s.pace[b]=0 end; s.paceMean=0
 F.place(f,2,0,150); F.place(f,3,6000,0); F.tick(e,f,18)
 assert(e.incidents.neutral and e.incidents.neutralMode=='vsc')
 for b=1,#s.pace do s.pace[b]=0 end; s.paceMean=0
 for _=1,20 do local limit=e.commands[2].yellowLimit; F.place(f,2,0,math.min(150,limit)); F.tick(e,f,0.5) end
 assert(e.commands[2].yellowLimit>=e.run.fcySpeedKmh*(1-C.K.aiDeltaMarginMax)-1e-6,'VSC limit does not spiral down (fallback while the pace is unknown): '..e.commands[2].yellowLimit)
end
-- 1.6.0 : allure habituelle apprise seulement en conduite libre, jamais sous neutralisation.
tests.PACE_NOT_LEARNED_UNDER_YELLOW=function()
 local e,f=F.scene('C',3); e.profiles.C.neutralization='fcy'; E.changed(e)
 F.place(f,2,0,150); F.place(f,3,6000,150); F.tick(e,f,5,true)
 local s=e.states[2]; local before={}; for b=1,#s.pace do before[b]=s.pace[b] end
 F.place(f,3,6000,0); F.tick(e,f,18)
 assert(e.incidents.neutral)
 for _=1,40 do F.place(f,2,f.cars[2].z,80); F.tick(e,f,0.5,true) end
 for b=1,#s.pace do assert(s.pace[b]==before[b] or before[b]==0 and s.pace[b]==0,'pace bin '..b..' learned under FCY') end
end
-- 1.6.0 : drapeau bleu du joueur maintenu tant que la voiture qui double reste collée derrière.
tests.FLAG_PANEL_BLUE_HYSTERESIS=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e)
 local player=F.place(f,1,10000+500,100); player.lap=2
 local fast=F.place(f,2,10000+420,150); fast.lap=3
 F.place(f,3,10000+4000,100); player.lapValid=true; fast.lapValid=true
 F.tick(e,f,0.5); assert(e.panel.kind=='blue')
 F.place(f,2,10000+480,100); fast.lap=3; F.tick(e,f,1); assert(e.panel.kind=='blue','blue kept while the leader is held behind')
 F.place(f,2,10000+300,60); fast.lap=3; F.tick(e,f,1); assert(e.panel.kind~='blue','blue dropped once the leader falls back')
end
-- 1.6.0 : la voiture de sécurité n'est jamais gérée par la météo.
tests.WEATHER_SKIPS_SAFETY_CAR=function()
 local e,f=F.scene('C',3); e.profiles.C.neutralization='sc'; e.g.safetyCarModel='sc_car'; E.changed(e); f.cars[3].id='sc_car'; f.cars[3].tyresKnown=true; f.cars[3].compoundIndex=0; f.cars[3].dryCompounds={[0]=true}; f.cars[3].dryList={0}
 F.tick(e,f,0.1); assert(not e.commands[3].weatherManaged,'safety car never managed by the weather')
end
-- 1.6.0 : onglet Accidents décoché, Règles coché : neutralisations et drapeau rouge restent signalés au joueur.
tests.RULES_SIGNAL_WITHOUT_ACCIDENTS=function()
 local p=C.preset('Course','C',{}); p.section_accidents=false
 local run=C.effective('C',p); assert(run.flagPanel and run.yellowMessage,'panel and messages kept for neutralizations')
 assert(not run.yellowEnabled and not run.yellowHud,'local yellow zones stay off')
 p.section_rules=false; run=C.effective('C',p); assert(not run.flagPanel and not run.yellowMessage,'both tabs off: nothing shown')
end
-- 1.6.0 : décalage d'horloge : minuteries du panneau et des écritures suivies déplacées.
tests.REBASE_TIMERS=function()
 local e,f=F.scene('C',3); e.panel.at=500; E.rebase(e,100); assert(e.panel.at==400,'panel timer rebased')
 local a=A.new(); local s=a.cars[2]; s.pitAt=300; s.stopAt=300; s.parkAt=300; s.flashAt=300
 A.rebase(a,100); assert(s.pitAt==200 and s.stopAt==200 and s.parkAt==200 and s.flashAt==200,'applier timers rebased')
end
-- 1.6.0 : frein additionnel relâché aussi dans la voie des stands.
tests.BRAKE_RELEASED_IN_PITS=function()
 local host=require('tests/host').create(true); local e,f=F.scene('J'); local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false; cmd.weatherManaged=false end
 local cmd=e.commands[2]; cmd.active=true; cmd.offset=0; cmd.brake=0.3; cmd.speedLimit=C.K.unlimitedSpeed
 cmd.levelOwned=false; cmd.aggressionOwned=false; cmd.cautionOwned=false; e.g.useBrakeAssist=true
 A.apply(a,f,e.commands,e.g,1); assert(host.controls[1].brake==0.3)
 f.cars[2].pit=true; host.cars[1].isInPitlane=true; A.restore(a,f,false,2)
 assert(a.cars[2].brake==0 and host.controls[1].brake==0,'brake released in the pit lane')
end
-- 1.6.0 : une voiture à côté n'empêche pas d'éviter un obstacle par le côté libre.
tests.AVOID_NOT_FROZEN_BY_ALONGSIDE=function()
 local e,f=F.scene('J',4); e.p.personalLineJitter=0
 F.place(f,2,-2000,100); F.place(f,3,-2000,100,6); F.place(f,4,80,0); F.tick(e,f,3)
 F.place(f,2,0,100); F.place(f,3,0,100,3); e.states[2].nextPerception=0; F.tick(e,f,2)
 local s=e.states[2]
 assert(s.state=='AVOID' and s.alongside,'avoiding with a car alongside: '..s.state)
 assert(math.abs(s.offset)>0.1,'moves to the free side: '..s.offset)
end
-- 1.6.0 : cible repartie à vive allure après un écart d'une image : l'évitement s'achève.
tests.AVOID_ENDS_WHEN_TARGET_MOVES=function()
 local e,f=F.scene('J',3); e.p.personalLineJitter=0
 F.place(f,2,0,100); F.place(f,3,60,100); F.tick(e,f,0.5)
 f.cars[3].slip=80; F.tick(e,f,2/60); f.cars[3].slip=0
 assert(e.states[2].state=='AVOID','one-frame slip: avoidance starts')
 F.tick(e,f,1.5); assert(e.states[2].state~='AVOID','target back at speed: avoidance ends ('..e.states[2].state..')')
end
-- 1.6.0 : recherche d'obstacles sans écraser la position relative de la cible suivie.
tests.AVOID_TARGET_NOT_ALIASED=function()
 local e,f=F.scene('J',4); e.p.personalLineJitter=0
 F.place(f,2,0,100); F.place(f,3,40,0,-5); f.cars[3].lx=1; f.cars[3].lz=0; F.place(f,4,600,0)
 F.tick(e,f,3)
 local s=e.states[2]; s.state='AVOID'; s.target=3
 F.tick(e,f,1/60)
 assert(s.hazardRel.index==3 or s.state~='AVOID','tracked target data intact: '..tostring(s.hazardRel.index))
end
-- 1.6.0 : compteur de cession bloquée remis à zéro hors conduite libre.
tests.BLOCKED_YIELD_RESET=function()
 local e,f=F.scene('J',3); e.p.personalLineJitter=0
 F.place(f,2,0,100); F.place(f,3,-2000,100); F.tick(e,f,0.5)
 local s=e.states[2]; s.blockedYield=10; F.place(f,3,60,100); F.tick(e,f,0.5); f.cars[3].slip=80; F.tick(e,f,2/60)
 assert(s.state=='AVOID' and s.blockedYield==0,'stale blocked-yield counter cleared')
end
-- 1.6.0 : retour à la ligne terminé même si le décalage visé est hors d'atteinte (largeurs inconnues).
tests.RETURNING_CLEARS_WHEN_UNREACHABLE=function()
 local e,f=F.scene('J',3); local s=e.states[2]
 f.cars[2].leftWidth=0; f.cars[2].rightWidth=0; s.base=0.25; s.persona.laneBias=0.25; s.returning=true; s.offset=0
 F.tick(e,f,0.2); assert(not s.returning,'returning flag cleared at the reachable line')
end
-- 1.6.0 : une IA en attente derrière sa cible ne saute pas l'attente de déboîtement ; déboîtement en ligne droite.
tests.OVT_ARM_WAITS=function()
 local e,f=F.scene('C',4); e.p.personalLineJitter=0
 F.place(f,2,0,150); F.place(f,3,20,100); F.place(f,4,-2000,100); F.tick(e,f,0.1)
 local s=e.states[2]; s.state='OVT_ARM'; s.target=3; s.targetSide=1; s.passAlongside=false
 F.place(f,4,0,150,3); e.states[2].nextPerception=0; F.tick(e,f,1/60)
 assert(s.state=='OVT_ARM','a car alongside does not skip the pull-out wait: '..s.state)
 F.place(f,4,-2000,100); f.cars[2].yawRate=1.5; e.states[2].nextPerception=0; F.tick(e,f,0.2)
 assert(s.state=='OVT_ARM','no pull-out in a corner: '..s.state)
end
-- 1.6.0 : la prudence ne remonte jamais dans l'aspiration (plancher de 0,6 seulement pour une baisse).
tests.SLIPSTREAM_NEVER_RAISES_CAUTION=function()
 local e,f=F.scene('J',3); e.profiles.J.caution=0.5; e.profiles.J.cautSpreadPct=0; E.changed(e); F.tick(e,f,1/60); e.p.personalLineJitter=0
 for i=1,3 do e.states[i].persona.cautSpread=0; e.states[i].persona.brakeMargin=1 end
 F.place(f,2,0,200); F.place(f,3,25,200); F.tick(e,f,4)
 assert(e.commands[2].caution<0.595,'slipstream never raises caution to its floor: '..e.commands[2].caution)
end
-- 1.6.0 : une voiture hors piste juste à côté occupe ce côté (elle rejoint la piste).
tests.OFFTRACK_CAR_OCCUPIES_SIDE=function()
 local e,f=F.scene('J',3); F.place(f,2,0,100); F.place(f,3,0,100,3); f.cars[3].offtrack=true
 local r={}; P.occupancy(f.cars,f.count,2,e.g,r)
 assert(r.left or r.right,'rejoining car beside counts for side occupancy')
end
-- 1.6.0 : défense jamais pendant le repos anti-zigzag (l'attaquant n'est pas consommé).
-- Beta 1.47 : défense seulement contre un suiveur nettement d'un côté (K.defenseLatMin) : suiveur à 0,8 m ; témoin sans
-- repos : défense envisagée.
tests.NO_DEFENSE_DURING_REST=function()
 for _,rest in ipairs({false,true}) do
  local e,f=F.scene('C',3); e.p.personalLineJitter=0
  local s=e.states[2]; s.persona.assertiveness=1; if rest then s.driveUntil=e.time+30 end
  F.place(f,2,0,150); F.place(f,3,-15,160,0.8); s.nextPerception=0; F.tick(e,f,1)
  if rest then assert(not s.defendUsed and s.defendAttacker~=3,'attacker not consumed during the rest')
  else assert(s.defendAttacker==3,'reference: defence considered without the rest') end
 end
end
-- 1.6.0 : relâchement d'urgence jamais retenu par le délai entre deux changements, même avec un facteur de 1.
tests.EMERGENCY_RELEASE_FACTOR_ONE=function()
 local e,f=F.scene('J',3); local s=e.states[2]; local a=f.cars[2]
 e.p.emergencyReleaseFactor=1; e.p.lateralCooldown=5; s.state='YIELD_HOLD'; s.offset=0.5; s.filtered=0.5; s.direction=1; s.lastDirectionAt=e.time
 local row={left=false,right=true}
 for _=1,90 do D.lateral(s,0.8,row,a,e.p,e.g,1/60,e.time); e.time=e.time+1/60 end
 assert(s.offset<0.49,'released towards the free side: '..s.offset)
end
-- 1.6.0 : patience faible : le gain potentiel compte dès le seuil de patience.
tests.PATIENCE_CONSISTENT=function()
 local e,f=F.scene('J',3); e.p.personalLineJitter=0
 F.place(f,2,0,100); F.place(f,3,30,100); F.tick(e,f,0.1)
 local s=e.states[2]; s.persona.patience=0.5; for b=1,#s.pace do s.pace[b]=150/3.6 end
 s.stuck=e.p.stuckTime*0.7; F.tick(e,f,0.2)
 assert(s.passConfirm>0 or F.passing(s.state),'held behind past its patience: pass considered')
end
-- 1.6.0 : valeurs par défaut du profil : onglets cochés et règles de course conservés.
tests.RESTORE_KEEPS_TABS_AND_RULES=function()
 local profiles={J=C.defaults('J'),P=C.defaults('P'),Q=C.defaults('Q'),C=C.defaults('C')}
 C.preset('Course','C',profiles.C); C.applyRules('F1',profiles)
 local p=profiles.C; local tabs={}; for _,group in ipairs(C.sections) do tabs[group]=p['section_'..group] end
 p.levelPct=70; p.classPatterns=''
 C.restore('C',p)
 assert(p.levelPct==C.defaults('C').levelPct,'values back to their defaults')
 for _,group in ipairs(C.sections) do assert(p['section_'..group]==tabs[group],'tab kept: '..group) end
 assert(C.ruleCategory('C',p)=='F1','race rules kept')
end
-- 1.6.0 : boutons de règles sur une première installation : chaque profil reçoit aussi son préréglage recommandé.
tests.RULES_ON_FRESH_PROFILES=function()
 local profiles={J=C.defaults('J'),P=C.defaults('P'),Q=C.defaults('Q'),C=C.defaults('C')}
 assert(C.applyRules('GT',profiles))
 for _,x in ipairs({'P','Q','C'}) do
  assert(profiles[x].section_general and profiles[x].section_rules and C.ruleCategory(x,profiles[x])=='GT','recommended tabs and GT rules: '..x)
 end
 assert(not profiles.J.configured and not C.anySection(profiles.J),'track day untouched')
end
-- 1.6.0 : réglages entiers arrondis.
tests.INTEGER_SETTINGS_ROUNDED=function()
 local p=C.defaults('C'); p.redFlagCars=2.6; p.mandatoryStops=1.4; p.flashMaxReactors=2.5
 local out=C.validate('C',p); assert(out.redFlagCars==3 and out.mandatoryStops==1 and out.flashMaxReactors==3)
end
-- 1.6.0 : défense jamais au freinage, même sans l'onglet Règles.
tests.NO_DEFENSE_UNDER_BRAKING=function()
 for _,brake in ipairs({0,0.8}) do
  local e,f=F.scene('C',3); e.profiles.C.noMoveBraking=false; E.changed(e); F.tick(e,f,1/60); e.p.personalLineJitter=0
  local s=e.states[2]; s.persona.assertiveness=1; f.cars[2].brake=brake
  F.place(f,2,0,150); F.place(f,3,-15,160,0.8); s.nextPerception=0; F.tick(e,f,1)
  if brake==0 then assert(s.defendAttacker==3,'defense considered off the brakes')
  else assert(s.defendAttacker~=3,'never under braking') end
 end
end
-- 1.6.0 : dépassement annulé par un drapeau jaune compté à part.
tests.ABORT_YELLOW_REASON=function()
 local e,f=F.scene('J',4); e.p.personalLineJitter=0
 F.place(f,2,-5000,100); F.place(f,3,-4900,100); F.place(f,4,250,0); F.tick(e,f,3)
 assert(e.incidents.cars[4].incident,'incident ahead')
 F.place(f,2,-100,120); F.place(f,3,-60,100); local s=e.states[2]; s.nextPerception=0
 s.state='OVT_IN'; s.target=3; s.targetSide=1; e.stats={}
 F.tick(e,f,1/60)
 assert(not F.passing(s.state) and e.stats.abort_yellow==1 and not e.stats.yellow,'overtake abandoned under yellow, counted apart')
end
-- 1.6.0 : restitution tentée même après une série d'échecs d'écriture.
tests.RESTORE_AFTER_CAPABILITY_FAILURES=function()
 local fail=true
 local cap=Caps.new({present=function() return true end,write=function() return not fail end})
 for _=1,C.K.capabilityFailures do Caps.call(cap,'level',1,0.9) end
 assert(not cap.level.available and cap.level.reason=='failures')
 fail=false; assert(Caps.restoreCall(cap,'level',1,0.8) and cap.level.available,'restore written and capability back')
end
-- 1.6.0 : stratégie pluie d'origine jamais relue sur la valeur que l'app vient de rendre.
tests.ORIGINAL_RAIN_NOT_RECAPTURED=function()
 local host=require('tests/host').create(true); local e,f=F.scene('J'); local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false; cmd.weatherManaged=false end
 local s=a.cars[2]; s.restoredAt=10; s.originalRain=false; f.cars[2].nativeRainTyres=true; f.cars[2].nativeRainTyresKnown=true
 local cmd=e.commands[2]; cmd.weatherManaged=true; cmd.weatherRain=false; cmd.weatherCompound=-1
 A.apply(a,f,e.commands,e.g,10); assert(s.owned and s.originalRain==false,'original rain strategy kept')
end
-- 1.6.0 : appels aux stands limités sans retirer l'appel d'une IA déjà en route.
tests.PIT_CALLS_NEVER_WITHDRAWN=function()
 local e,f=F.scene('C',9); local p=e.profiles.C
 p.mandatoryStops=1; p.pitWindowOpenPct=25; p.pitWindowClosePct=75; E.changed(e)
 f.sessionLaps=20; f.leaderLaps=0; f.timedRace=false
 for i=2,9 do local a=f.cars[i]; a.tyresKnown=true; a.compoundIndex=0; a.dryCompound=0; a.dryCompounds={[0]=true}; F.place(f,i,(i-2)*500,150) end
 local was={}; local flaps=0
 for lap=4,16 do
  f.leaderLaps=lap
  for _=1,6 do
   F.tick(e,f,0.25)
   for i=2,9 do local want=e.commands[i].rulePit; if was[i] and not want then flaps=flaps+1 end; was[i]=want end
  end
 end
 assert(flaps==0,'pit calls withdrawn: '..flaps)
end
-- Branchement : portée du drapeau bleu (la simulation réaliste ne le mesure pas).
tests.BLUE_FLAG_RANGE_WIRED=function()
 local function yields(range)
  local e,f=F.scene('C',3); e.profiles.C.blueFlagRange=range; E.changed(e); F.tick(e,f,1/60); e.p.personalLineJitter=0
  F.rear(e,f,120,35); f.cars[3].lap=3; F.tick(e,f,4)
  return F.yielding(e.states[2].state)
 end
 assert(yields(400) and not yields(50),'blue flag only within its range')
end
-- Branchement : durée d'arrêt d'une IA accidentée et écart de trafic avant de repartir.
tests.INCIDENT_STOP_TIMES_WIRED=function()
 local function held(min,max,gap,traffic)
  local e,f=F.scene('J',3); local p=e.profiles.J; p.incidentStopMin=min; p.incidentStopMax=max; p.rejoinGap=gap; E.changed(e)
  F.place(f,2,0,150); F.place(f,3,5000,100); F.tick(e,f,0.5)
  f.cars[2].collided=true; f.cars[2].offtrack=true; f.cars[2].kmh=8; f.cars[2].speed=8/3.6; F.tick(e,f,2/60); f.cars[2].collided=false; F.tick(e,f,0.6)
  local c=e.incidents.cars[2]; assert(c.holding)
  local length=c.holdUntil-e.time
  if traffic then F.place(f,3,-40,120); F.tick(e,f,max+0.5) else F.tick(e,f,0.1) end
  return length,c.holding
 end
 local short=held(1,1,50); local long=held(15,15,50)
 assert(short<2 and long>13,'hold time follows the settings: '..short..' / '..long)
 local _,still=held(1,1,200,true); assert(still,'waits while traffic arrives within the rejoin gap')
end
-- 1.6.0 : passage aux stands déjà servi oublié à la session suivante (pneus du premier arrêt posés).
tests.TYRE_VISIT_RESET=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C'); local a=A.new(); assert(A.access(a))
 local s=a.cars[2]; s.owned=true; s.id=f.cars[2].id; s.tyreVisit=1
 A.nextSession(a,f); assert(s.tyreVisit==-1,'visit forgotten on a new session')
 -- Visite servie à la voiture précédente de cet emplacement : la nouvelle voiture repart de zéro.
 local t=a.cars[3]; t.owned=false; t.id='previous_car'; t.tyreVisit=1
 for _,cmd in ipairs(e.commands) do cmd.active=false; cmd.weatherManaged=false end
 e.commands[3].pitCompound=0; e.commands[3].pitVisit=1; f.cars[3].inPitBox=true; f.cars[3].kmh=0; f.cars[3].pit=true
 host.cars[2].isInPit=true; host.cars[2].isInPitlane=true; host.cars[2].speedKmh=0; host.cars[2].compoundIndex=5
 A.apply(a,f,e.commands,e.g,1); assert(t.tyreVisit==1 and host.cars[2].compoundIndex==0,'claim starts a fresh visit count, tyres fitted')
end
-- 1.6.0 : voiture lapée derrière deux leaders en lutte rapprochée : elle reste derrière.
tests.LAPPED_CAR_STAYS_BEHIND_FIGHT=function()
 local e,f=F.scene('C',4); e.p.personalLineJitter=0
 F.place(f,2,0,150); F.place(f,3,30,120); F.place(f,4,55,121)
 f.cars[2].lap=1; f.cars[3].lap=2; f.cars[4].lap=2
 for i=2,4 do e.states[i].nextPerception=0 end
 F.tick(e,f,3)
 assert(not F.passing(e.states[2].state),'lapped car waits behind the fighting leaders: '..e.states[2].state)
 -- Leaders éloignés l'un de l'autre : plus de lutte, le dépassement reste permis.
 local e2,f2=F.scene('C',4); e2.p.personalLineJitter=0
 F.place(f2,2,0,150); F.place(f2,3,30,120); F.place(f2,4,600,121)
 f2.cars[2].lap=1; f2.cars[3].lap=2; f2.cars[4].lap=2
 F.tick(e2,f2,3); assert(F.passing(e2.states[2].state),'no fight: the lapped car may pass')
end
-- 1.6.0 : pénalité du joueur pour excès de vitesse dans une zone jaune ; tolérance ; jamais en journée circuit.
tests.PLAYER_PENALTY_SPEED=function()
 local function run(profile,kmh)
  local e,f=F.scene(profile,3); e.profiles[profile].playerPenalties=true; E.changed(e); F.place(f,3,5000,0); F.tick(e,f,3)
  assert(e.incidents.cars[3].incident)
  -- Traversée du double jaune à vitesse constante : delta de zone, jugé aux mini-secteurs et à la sortie.
  local z=4300
  while z<5300 do z=z+kmh/3.6/60; F.place(f,1,z,kmh); F.tick(e,f,1/60) end
  return e
 end
 local e=run('C',120)
 assert(e.penalties.count==1 and e.penalties.reason=='delta' and e.penalties.deltaKind=='zone' and e.incidents.messageKind=='penaltyDelta' and e.panel.notice:find('delta',1,true),'too fast through the double yellow: delta penalty')
 assert(run('C',45).penalties.count==0,'slower than the zone reference: no penalty')
 assert(run('J',120).penalties.count==0,'never on a track day')
 -- Onglet Accidents décoché : pas de pénalité, même sous FCY (règles actives).
 local e2,f2=F.scene('C',3); e2.profiles.C.section_accidents=false; e2.profiles.C.neutralization='fcy'; E.changed(e2)
 F.place(f2,3,6000,0); local z=0
 for _=1,60*35 do z=z+150/3.6/60; F.place(f2,1,z,150); F.tick(e2,f2,1/60) end
 assert(e2.incidents.neutral and e2.penalties.count==0,'Accidents tab off: no penalty')
end
-- 1.6.0 : pénalité du joueur pour un dépassement sous drapeau jaune ; doubler une voiture au pas reste permis.
tests.PLAYER_PENALTY_PASS=function()
 local function run(otherKmh,giveBack)
  local e,f=F.scene('C',3); F.place(f,3,5000,0); F.place(f,2,4850,60); F.place(f,1,4800,45); F.tick(e,f,3)
  -- La voiture doublée vient de ralentir (pas encore un incident) ou roule normalement.
  F.place(f,2,4850,otherKmh)
  for step=1,10 do F.place(f,1,4800+step*10,45); F.tick(e,f,0.1) end
  -- Dépassement pendant la transition : en attente ; place rendue (la voiture repasse devant) ou gardée.
  if giveBack then F.place(f,2,4920,otherKmh) end
  F.tick(e,f,C.K.passGiveBack+1)
  return e
 end
 local e=run(40); assert(e.penalties.count==1 and e.penalties.reason=='pass' and e.incidents.messageKind=='penaltyPass','overtake under yellow, place kept: penalty at the deadline')
 assert(run(40,true).penalties.count==0,'place given back: no penalty')
 assert(run(10).penalties.count==0,'passing a crawling car is allowed')
end
-- 1.6.0 : FCY : délai pour ralentir avant de compter un excès de vitesse.
tests.PLAYER_PENALTY_NEUTRAL_GRACE=function()
 -- Cas relevé en jeu : FCY déclenchée à 250 km/h. Freinage à la décélération d'approche après 1 s de réaction, puis
 -- allure un peu sous la référence : jamais de pénalité, allure apprise ou non, quel que soit le premier mini-secteur
 -- (30 m ou 230 m plus loin) ; à fond : pénalité de temps delta.
 local function run(learned,brake,offset)
  local e,f=F.scene('C',3); e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
  if learned then local ps=e.states[1]; for b=1,#ps.pace do ps.pace[b]=280/3.6 end; ps.paceCount=400; ps.paceMean=280/3.6 end
  local z=1000-offset
  F.place(f,3,6000,0); F.place(f,1,z,250)
  for _=1,40*10 do F.tick(e,f,0.1); if e.incidents.neutral then break end end
  assert(e.incidents.neutral and e.delta.kind=='fcy','FCY started')
  local kmh,elapsed=250,0
  local target=(learned and 280/(1+e.run.fcyDeltaPct/100) or e.run.fcySpeedKmh)*0.95
  for _=1,60*40 do
   elapsed=elapsed+1/60
   if brake and elapsed>1 then kmh=math.max(target,kmh-e.run.yellowDecel*3.6/60) end
   z=z+kmh/3.6/60; F.place(f,1,z,kmh); F.tick(e,f,1/60)
  end
  return e
 end
 for _,learned in ipairs({false,true}) do for _,offset in ipairs({30,230}) do
  local e=run(learned,true,offset)
  assert(e.penalties.count==0,string.format('braking from 250 km/h at the FCY call: no penalty (learned %s, first sector at %d m)',tostring(learned),offset))
 end end
 local e=run(true,false,30); assert(e.penalties.count>=1 and e.penalties.reason=='delta' and e.penalties.deltaKind=='fcy','flat out under FCY: delta penalty')
end
-- 1.6.0 : IA bloquée longtemps en piste (contre un mur, en travers) dépannée par les commissaires, onglet Accidents coché.
tests.STUCK_AI_RECOVERED=function()
 for _,accidents in ipairs({true,false}) do for _,off in ipairs({false,true}) do
  local e,f=F.scene('J',3); e.profiles.J.section_accidents=accidents; E.changed(e)
  F.place(f,3,5000,0); f.cars[3].offtrack=off
  -- Beta 1.7 : en pleine piste, dépannée vite ; hors piste, après un délai plus long (Beta 1.24 : 8 s et 30 s).
  local delay=off and C.K.stuckRecoverTime or C.K.trackRecoverTime
  F.tick(e,f,delay-5); assert(not e.commands[3].recover,'not before the delay')
  F.tick(e,f,10); assert(e.commands[3].recover==accidents,'recovered only with the Accidents tab')
  if accidents then assert(e.commands[3].recoverReason==(off and 'bloquee' or 'en piste'),e.commands[3].recoverReason) end
  assert(not e.commands[1].recover,'never the player')
 end end
end
-- 1.6.0 : bouchon qui avance au pas : ni incident ni évitement ; une voiture approchée vite reste un obstacle.
tests.JAM_IS_NOT_AN_INCIDENT=function()
 local e,f=F.scene('J',4); e.p.personalLineJitter=0
 F.place(f,2,0,18); F.place(f,3,30,15); F.place(f,4,2000,15); F.tick(e,f,4)
 assert(e.states[2].state~='AVOID','following a slow car in a jam: no swerve ('..e.states[2].state..')')
 assert(not e.incidents.cars[4].incident and not e.incidents.cars[3].incident,'cars crawling at 15 km/h are not stopped-car incidents')
 F.place(f,2,-100,100); e.states[2].nextPerception=0; F.tick(e,f,0.5)
 assert(e.states[2].state=='AVOID','slow car approached at speed: obstacle')
 F.place(f,4,2000,3); F.tick(e,f,3); assert(e.incidents.cars[4].incident,'a nearly stopped car is an incident')
end
-- 1.6.0 : incident juste devant le joueur lancé : le temps de freiner avant de compter un excès de vitesse.
tests.PLAYER_PENALTY_BRAKING_GRACE=function()
 local function run(brake)
  local e,f=F.scene('C',3); F.place(f,1,-3000,200); F.place(f,3,5000,0); F.tick(e,f,3)
  assert(e.incidents.cars[3].incident)
  local kmh,z,seen=200,3800,nil
  while z<5200 do
   if e.incidents.playerZone and not seen then seen=e.time end
   if brake and seen and e.time-seen>1 then kmh=math.max(e.run.yellowSpeedKmh*0.95,kmh-e.run.yellowDecel*3.6/60) end
   z=z+kmh/3.6/60; F.place(f,1,z,kmh); F.tick(e,f,1/60)
  end
  return e
 end
 assert(run(true).penalties.count==0,'braking from the warning panel at the approach deceleration: no penalty')
 local e=run(false); assert(e.penalties.count==1 and e.penalties.reason=='delta','holding 200 km/h through the double yellow: penalty')
 local found=false; for n=0,e.log.count-1 do local r=e.log[(e.log.head-n-1)%200+1]; if r.message:find('delta negatif (zone',1,true) then found=true end end
 assert(found,'penalty journal names the double yellow zone')
end
-- 1.6.0 : dépassement déjà côte à côte quand le drapeau jaune s'impose : il peut s'achever.
tests.PLAYER_PENALTY_PASS_IN_PROGRESS=function()
 -- Le joueur rattrape la voiture 2 et arrive à sa hauteur avant l'incident ; le drapeau s'impose côte à côte.
 local e,f=F.scene('C',3); F.place(f,3,5000,100); F.place(f,2,4710,40); F.place(f,1,4700,45); F.tick(e,f,0.5)
 F.place(f,1,4710,45); F.tick(e,f,0.1)
 F.place(f,3,5000,0); F.tick(e,f,3); assert(e.incidents.cars[3].incident and e.incidents.playerInside,'flag imposed alongside')
 for step=1,6 do F.place(f,1,4710+step*5,45); F.tick(e,f,0.1) end
 F.tick(e,f,C.K.passGiveBack+1)
 assert(e.penalties.count==0,'overtake already alongside at the flag: allowed, even after the give-back deadline')
end
-- 1.6.0 : dépannage réservé aux IA en incident : la tête d'une file est dépannée, pas la voiture qui attend derrière,
-- ni une voiture qui n'a jamais roulé.
tests.RECOVER_ONLY_INCIDENTS=function()
 local e,f=F.scene('J',4); F.place(f,3,5000,0); F.place(f,4,4990,0); F.tick(e,f,C.K.stuckRecoverTime+5)
 assert(e.commands[3].recover and not e.commands[4].recover,'head of the queue recovered, the car behind waits')
 local e2,f2=F.scene('J',3); f2.time=2; f2.cars[3].id='spawned'; F.place(f2,3,5000,0); F.tick(e2,f2,C.K.stuckRecoverTime+5)
 assert(not e2.commands[3].recover,'a car that never moved is not recovered')
end
-- 1.6.0 : journal : arrêts écartés et bouchons suivis sans évitement comptés chaque minute.
tests.JOURNAL_SUPPRESSED_COUNTERS=function()
 local e,f=F.scene('J',4); e.p.personalLineJitter=0; e.stats={}
 F.place(f,2,0,18); F.place(f,3,30,15); F.place(f,4,2000,15); F.tick(e,f,4)
 local J=require('src/journal'); local text=J.summary(e)
 assert(text:find('au pas 3',1,true) or text:find('au pas 2',1,true),'crawling cars counted: '..text:match('arrets ecartes[^|]*'))
 assert(text:find('bouchons suivis sans evitement 1',1,true),'jam followed counted')
end
-- 1.6.0 : DRS du joueur : bip à chaque ouverture de zone, panneau « disponible » effacé dès l'ouverture (Beta 1.14 :
-- jusqu'à la fin de la zone, même si l'aileron se referme au freinage), drapeaux prioritaires.
tests.DRS_BEEP_AND_PANEL=function()
 local L=require('src/lang')
 local e,f=F.scene('C',3); local me=f.cars[1]; me.drsPresent=true; f.leaderLaps=5; F.tick(e,f,0.5)
 assert(e.drs.beepId==0 and e.panel.kind=='none')
 me.drsAvailable=true; F.tick(e,f,0.5); assert(e.drs.beepId==1 and e.panel.kind=='drs' and e.panel.title==L.flagTitles.drs,'available: one beep, panel')
 F.tick(e,f,1); assert(e.drs.beepId==1,'one beep per zone')
 me.drsActive=true; F.tick(e,f,0.5); assert(e.panel.kind=='none','badge cleared once DRS is opened')
 me.drsActive=false; F.tick(e,f,0.5); assert(e.panel.kind=='none','not back at the braking point while the zone is still active')
 me.drsAvailable=false; me.drsActive=false; F.tick(e,f,0.5); assert(e.panel.kind=='none')
 me.drsAvailable=true; F.tick(e,f,0.5); assert(e.drs.beepId==2,'next zone: beep again')
 e.profiles.C.drsAssist=false; E.changed(e); me.drsAvailable=false; F.tick(e,f,0.5); me.drsAvailable=true; F.tick(e,f,0.5)
 assert(e.drs.beepId==2 and e.panel.kind~='drs','option off: no beep, no panel')
 local e2,f2=F.scene('C',3); f2.cars[1].drsPresent=false; f2.cars[1].drsAvailable=true; F.tick(e2,f2,0.5)
 assert(e2.drs.beepId==0 and e2.panel.kind=='none','car without DRS: nothing')
 -- Aide au pilote hors des jeux de règles : la décocher ne rend pas les règles « personnalisées ».
 local profiles={J=C.defaults('J'),P=C.defaults('P'),Q=C.defaults('Q'),C=C.defaults('C')}; C.applyRules('F1',profiles)
 profiles.C.drsAssist=false; assert(C.ruleCategory('C',profiles.C)=='F1','F1 rules still recognised')
end
-- 1.6.0 : dépassement sous drapeau jaune signalé en rouge sur le panneau, même sans pénalité (journée circuit).
tests.PASS_SHOWN_ON_PANEL=function()
 local e,f=F.scene('J',3); C.preset('Nordschleife','J',e.profiles.J); E.changed(e)
 F.place(f,3,5000,0); F.place(f,2,4850,40); F.place(f,1,4800,45); F.tick(e,f,3)
 assert(e.panel.noPass and not e.panel.passed,'no overtaking line, not yet passed')
 for step=1,10 do F.place(f,1,4800+step*10,45); F.tick(e,f,0.1) end
 assert(e.panel.passed and e.penalties.count==0,'pass shown in red, no penalty on a track day')
 F.place(f,1,6000,45); F.place(f,3,5000,120); F.tick(e,f,15)
 assert(not e.panel.passed,'cleared once the flag is over')
end
-- 1.7.0 : escalade du joueur : coupures des gaz jusqu'au nombre toléré, puis drapeau noir ; plus rien ensuite.
tests.PLAYER_DISQUALIFIED_AFTER_LIMIT=function()
 local e,f=F.scene('C',3); e.profiles.C.penaltyDisqualify=2; e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
 F.place(f,3,6000,0); local z=0
 for _=1,60*90 do z=z+150/3.6/60; F.place(f,1,z,150); F.tick(e,f,1/60) end
 local t=e.penalties
 assert(t.count==3 and t.kind=='dq' and t.disqualified,'third infraction: disqualified ('..t.count..')')
 assert(e.incidents.messageKind=='penaltyDq' and e.panel.notice:find('DRAPEAU NOIR',1,true),'black flag announced')
 assert(e.panel.passOk:find('3 / 2',1,true),'counter on the panel')
 local id=t.requestId; for _=1,60*45 do z=z+150/3.6/60; F.place(f,1,z,150); F.tick(e,f,1/60) end; assert(t.requestId==id,'nothing after the disqualification, even still too fast')
end
-- 1.7.0 : sanctions des IA : dépassement sous drapeau jaune, pied levé, puis disqualification (retour au stand, garée).
tests.AI_SANCTIONS_ESCALATE=function()
 local e,f=F.scene('C',4); e.profiles.C.penaltyDisqualify=1; E.changed(e); e.p.personalLineJitter=0
 F.place(f,1,-3000,100); F.place(f,3,5000,0); F.place(f,4,4800,40); F.place(f,2,4780,45); F.tick(e,f,3)
 assert(e.states[2].yellow,'AI under the yellow regime')
 local function pass() for step=1,8 do F.place(f,2,4780+step*5,45); e.states[2].nextPerception=0; F.tick(e,f,0.15) end end
 pass(); local ai=e.penalties.ai
 F.tick(e,f,2); assert(ai.count[2]==1 and not ai.dq[2] and e.commands[2].yellowLimit<=ai.slowKmh[2]+1e-6,'first pass: slowed down progressively')
 F.place(f,2,4780,45); e.states[2].nextPerception=0; F.tick(e,f,C.K.penaltyCooldown); pass()
 assert(ai.dq[2] and e.commands[2].scPark and e.commands[2].parkReason=='dq' and e.states[2].disqualified,'second pass: disqualified, parked')
 assert(e.incidents.messageKind=='aiDq' and e.incidents.messageText==f.cars[2].name,'disqualification announced with the name')
 F.tick(e,f,1); assert(e.states[2].state=='IDLE','no longer driven by the app')
 local e2,f2=F.scene('J',4); e2.profiles.J.aiPenalties=true; E.changed(e2); F.place(f2,3,5000,0); F.place(f2,4,4800,40); F.place(f2,2,4780,45); F.tick(e2,f2,3)
 for step=1,8 do F.place(f2,2,4780+step*5,45); e2.states[2].nextPerception=0; F.tick(e2,f2,0.15) end
 assert((e2.penalties.ai.count[2] or 0)==0,'never on a track day')
end
-- 1.7.2 : sous la pluie, une IA en intermédiaires ou en pneus pluie les garde (relevé à Spa : 178 changements
-- « W -> I » en quelques minutes, la logique pluie de CSP remettant les pneus pluie à chaque fois).
tests.RAIN_COMPOUND_KEPT=function()
 local W=require('src/weather'); local e,f=F.scene('J'); local a=f.cars[2]; local w=W.new()
 a.tyresKnown=true; a.dryCompound=0; a.interCompound=1; a.wetCompound=2; a.nativeRainTyresKnown=true; a.nativeRainTyres=true
 f.wet=0.4; f.rain=0.2; W.step(w,f,e.commands,e.p,0); assert(w.wet)
 a.compoundIndex=2; W.step(w,f,e.commands,e.p,1)
 assert(e.commands[2].weatherCompound==2 and not e.commands[2].weatherPit,'full wets kept in moderate rain')
 f.wet=1; a.compoundIndex=1; W.step(w,f,e.commands,e.p,2)
 assert(e.commands[2].weatherCompound==1 and not e.commands[2].weatherPit,'intermediates kept in heavy rain')
 a.compoundIndex=0; W.step(w,f,e.commands,e.p,3)
 assert(e.commands[2].weatherCompound==2 and e.commands[2].weatherPit,'dry tyres in the rain: changed')
end
-- 1.8.0 : journée circuit, le joueur veut laisser passer une IA qui le suit à sa vitesse (relevé en jeu : l'IA restait
-- derrière). Écarté en ligne droite, il l'invite à passer, du côté qu'il libère, même si elle n'a rien appris à cet
-- endroit ; jamais en virage, ni quand il double lui-même, ni sans écart ; en course aussi depuis la Beta 1.7.
tests.LET_PASS_INVITATION=function()
 local function run(profile,playerX,yaw,third,thirdKmh)
  local e,f=F.scene(profile,3); C.preset(profile=='C' and 'Course' or 'Nordschleife',profile,e.profiles[profile]); E.changed(e); F.tick(e,f,1/60)
  e.p.personalLineJitter=0
  F.place(f,1,20,100,playerX); F.place(f,2,0,100); F.place(f,3,third or 5000,third and (thirdKmh or 80) or 100,third and playerX or 0)
  f.cars[1].yawRate=yaw or 0; f.cars[2].yawRate=yaw or 0
  local s=e.states[2]; s.nextPerception=0; for b=1,#s.pace do s.pace[b]=0 end; s.paceCount=0; s.paceMean=0
  local first
  for n=1,8*60 do F.tick(e,f,1/60); if not first and F.passing(s.state) then first=n/60 end end
  return first,s
 end
 local first,s=run('J',3); assert(first and first<2.5,'player aside on the right: pass engaged')
 assert(s.ignoreTarget==1,'no immediate yield back to the player who invited')
 local side=s.targetSide
 local first2,s2=run('J',-3); assert(first2 and s2.targetSide==-side,'player aside on the left: pass on the other side')
 assert(not run('J',0),'player centred, nothing learned: no forced pass')
 assert(not run('C',3,0.1),'race, long curve: invitation on straights only')
 -- Beta 1.44 : hors course, courbe douce, écart net (3 m pour 0,7 m dû à la courbure) : invitation.
 assert(run('J',3,0.1),'track day, gentle curve with a clear offset: invitation')
 assert(not run('J',3,0,50),'player catching another car: not an invitation')
 assert(run('J',3,0,50,100),'car ahead of the player at its pace (an AI that already passed): invitation still possible')
 local first3,s3=run('C',3); assert(first3 and first3<2.5 and s3.targetSide==side,'race: invitation too, on the freed side ('..s3.state..')')
 local first4,s4=run('J',5); assert(first4 and s4.targetSide==side,'player at the edge, outside the AI lane: still an invitation')
 local first5,s5=run('C',5); assert(first5 and s5.targetSide==side,'race, player at the edge: still an invitation')
end
-- 1.8.0 : sortie des stands (relevé en jeu : les IA fonçaient dans la voiture de devant dès la fin du limiteur) :
-- rattrapage borné de la voiture de devant, joueur compris, puis liberté une fois loin ou après le délai.
tests.PIT_EXIT_GUARD=function()
 local e,f=F.scene('J',3); C.preset('Nordschleife','J',e.profiles.J); E.changed(e); F.tick(e,f,1/60)
 local ai=f.cars[2]; F.place(f,1,20,60); F.place(f,2,0,60); F.place(f,3,5000,100); ai.pit=true; F.tick(e,f,0.2)
 ai.pit=false; F.place(f,2,0,90); e.states[2].nextPerception=0; F.tick(e,f,0.5)
 local bound=60+C.K.pitGuardAllowance
 assert(e.commands[2].speedLimit<=bound+1e-6,'held near the player after the pit exit: '..e.commands[2].speedLimit)
 F.place(f,2,12,90); e.states[2].nextPerception=0; F.tick(e,f,0.2)
 assert(e.commands[2].speedLimit<=60-C.K.pitGuardBack+1e-6,'too close: slower than the car ahead')
 F.place(f,1,600,60); e.states[2].nextPerception=0; F.tick(e,f,0.5)
 assert(e.commands[2].speedLimit>bound,'free once the car ahead is far')
 F.place(f,1,30,60); e.states[2].nextPerception=0; F.tick(e,f,C.K.pitGuardTime)
 assert(e.commands[2].speedLimit>bound,'free after the guard time')
 local found=false; for _,key in ipairs(C.timerFields) do if key=='pitGuardUntil' then found=true end end
 assert(found,'guard timer rebased with the engine clock')
end
-- 1.8.0 : drapeau jaune et zone DRS en même temps (relevé en jeu : seul le DRS s'affichait) : le drapeau reste affiché
-- avec « DRS interdit sous drapeau », pas de bip ; drapeau jaune natif d'AC repris par le panneau.
tests.FLAG_OVER_DRS=function()
 local e,f=F.scene('C',3); local me=f.cars[1]; me.drsPresent=true; me.drsAvailable=true; f.flag=C.K.flagCaution; f.leaderLaps=5
 F.tick(e,f,0.5)
 assert(e.panel.kind=='native' and not e.panel.noPass and e.panel.drsBlocked and e.drs.beepId==0,'native yellow shown, DRS blocked, no beep, no unenforced no-pass line')
 f.flag=0; F.tick(e,f,0.5)
 assert(e.panel.kind=='drs' and not e.panel.drsBlocked and e.drs.beepId==1,'flag over: DRS badge and beep')
 f.flag=C.K.flagCaution; f.flagOwned=true; F.tick(e,f,0.5)
 assert(e.panel.kind=='drs','yellow flag written by the app itself: never taken for a native one')
 f.flag=0; f.flagOwned=false
 local e2,f2=F.scene('C',3); F.place(f2,3,5000,0); F.tick(e2,f2,3); F.place(f2,1,4900,40)
 f2.cars[1].drsPresent=true; f2.cars[1].drsAvailable=true; F.tick(e2,f2,0.5)
 assert((e2.panel.kind=='yellow' or e2.panel.kind=='zone') and e2.panel.drsBlocked and e2.drs.beepId==0,'app yellow zone keeps priority over DRS')
end
-- 1.8.0 (relecture) : attente derrière la cible jamais sautée par une voiture collée derrière ; pas de déboîtement au
-- freinage ni vers une cible déjà de ce côté.
tests.OVT_ARM_PULL_OUT_RULES=function()
 local e,f=F.scene('C',3); e.p.personalLineJitter=0
 F.place(f,2,0,150); F.place(f,3,6,140,0.5); F.tick(e,f,0.1)
 local s=e.states[2]; s.state='OVT_ARM'; s.target=3; s.targetSide=1; s.passAlongside=false; e.states[2].nextPerception=0; F.tick(e,f,1/60)
 assert(s.state=='OVT_ARM','nose to tail: still waiting ('..s.state..')')
 F.place(f,3,20,100,0); f.cars[2].brake=0.5; e.states[2].nextPerception=0; F.tick(e,f,0.2)
 assert(s.state=='OVT_ARM','no pull-out under braking ('..s.state..')')
 f.cars[2].brake=0; F.place(f,3,20,100,2); e.states[2].nextPerception=0; F.tick(e,f,0.2)
 assert(s.state=='OVT_ARM','no pull-out towards a target already on that side ('..s.state..')')
 F.place(f,3,20,100,0); e.states[2].nextPerception=0; F.tick(e,f,0.2)
 assert(s.state=='OVT_IN','pull-out once clear ('..s.state..')')
end
-- 1.8.0 (relecture) : dépassement sans rapprochement abandonné au lieu de rester déboîté indéfiniment.
tests.PASS_STALL_ABORT=function()
 local e,f=F.scene('J',3); e.p.personalLineJitter=0
 F.place(f,2,0,100); F.place(f,3,20,100); F.tick(e,f,0.1)
 local s=e.states[2]; s.state='OVT_IN'; s.target=3; s.targetSide=1; s.passAlongside=false; s.restUntil=0
 e.states[2].nextPerception=0; F.tick(e,f,9)
 assert(not (s.state=='OVT_IN' or s.state=='OVT_HOLD'),'no progress: pass abandoned ('..s.state..')')
end
-- 1.8.0 (relecture) : évitement jamais vers un obstacle décalé, côté fermé : ralentir.
tests.AVOID_NEVER_TOWARDS_OBSTACLE=function()
 local e,f=F.scene('J',4); e.p.personalLineJitter=0
 F.place(f,2,0,100); F.place(f,3,60,0,-2); F.place(f,4,0,100,3)
 F.tick(e,f,4)
 local s=e.states[2]
 assert(s.state=='AVOID' and s.offset>-0.05,'right side closed: no swerve towards the obstacle ('..s.state..', '..s.offset..')')
end
-- 1.8.0 (relecture) : défense interrompue au freinage même sans l'onglet Règles.
tests.DEFEND_ENDS_UNDER_BRAKING=function()
 local e,f=F.scene('C',3); e.p.personalLineJitter=0; e.p.noMoveBraking=false
 F.place(f,2,0,150); F.place(f,3,-10,160); F.tick(e,f,0.1)
 local s=e.states[2]; s.state='DEFEND'; s.targetSide=1; s.defendUntil=e.time+5
 f.cars[2].brake=0.5; e.states[2].nextPerception=0; F.tick(e,f,0.1)
 assert(s.state~='DEFEND','defence ends under braking ('..s.state..')')
end
-- 1.8.0 (relecture) : voiture accidentée proche dans l'espace mais ailleurs sur la spline (pont, croisement) : pas
-- d'évitement fantôme.
tests.INCIDENT_SCAN_SPLINE_COHERENCE=function()
 local e,f=F.scene('J',3); e.p.personalLineJitter=0
 F.place(f,2,0,100); local b=F.place(f,3,60,0); b.lx=1; b.lz=0; b.spline=((60+2500)/f.length)%1
 F.tick(e,f,4)
 assert(e.states[2].state~='AVOID','car on a crossing track section: no phantom avoidance ('..e.states[2].state..')')
end
-- 1.8.0 (relecture) : arrivée à pleine vitesse dans une zone jaune sanctionnée (avant, plus l'arrivée était rapide,
-- plus le délai de freinage accordé dépassait la traversée de la zone) ; freinage à la décélération d'approche toléré.
tests.PENALTY_FAST_ENTRY=function()
 local function run(decel)
  local e,f=F.scene('C',3); F.place(f,1,-3000,250); F.place(f,3,5000,0); F.tick(e,f,3)
  assert(e.incidents.cars[3].incident)
  local z,kmh=4500,250
  while z<5040 do
   kmh=math.max(e.run.yellowSpeedKmh,kmh-decel*3.6/60); z=z+kmh/3.6/60
   F.place(f,1,z,kmh); F.tick(e,f,1/60)
  end
  return e
 end
 local e=run(0); assert(e.penalties.count==1 and e.penalties.reason=='delta','250 km/h through the zone: delta penalty')
 assert(run(e.run.yellowDecel+1).penalties.count==0,'braking from the warning panel: no penalty')
end
-- 1.8.0 (relecture) : pas de sanction pour une IA qui double une voiture sortie de piste ; voie des stands ignorée ;
-- une seule sanction par délai ; une voiture qui purge une sanction peut être doublée.
tests.AI_PENALTY_FAIRNESS=function()
 local Pe=require('src/penalties')
 local e,f=F.scene('C',4); e.run.aiPenalties=true
 local st={}; for i=1,4 do st[i]={yellow=true} end
 local function step(t,za,zb,offtrack)
  F.place(f,2,za,100); F.place(f,3,zb,100); f.cars[3].offtrack=offtrack or false; F.place(f,4,5000,100)
  e.states[2].nextPerception=0; F.tick(e,f,1/60)
  return Pe.ai(t,f,e.run,'C',e.incidents,st,e.perception.rows,e.time)
 end
 local t=Pe.new()
 step(t,0,20); step(t,10,20,true); step(t,30,20,true)
 assert(not step(t,30,20,false) and not t.ai.count[2],'passed while the other car was off track: no sanction')
 local t2=Pe.new(); step(t2,0,20); assert(step(t2,30,20),'real pass under yellow: sanctioned')
 step(t2,30,50); assert(not step(t2,60,50),'second pass inside the cooldown: no second sanction')
 local t3=Pe.new(); t3.ai.slowUntil[3]=e.time+10; step(t3,0,20); assert(not step(t3,30,20),'car serving a sanction: may be passed')
 local before=t3.ai.slowUntil[3]; Pe.rebase(t3,5); assert(math.abs(t3.ai.slowUntil[3]-(before-5))<1e-9,'sanction timer rebased')
end
-- 1.8.0 (relecture) : joueur — dépassement interdit dès le panneau d'approche ; limite FCY tant que la voiture de
-- sécurité est dans la voie des stands ; voie des stands sans jugement.
tests.PLAYER_PENALTY_REGIMES=function()
 local Pe=require('src/penalties')
 local e,f=F.scene('C',3); local p=e.run
 local inc={cars=e.incidents.cars,playerZone=true,playerNoPass=true,playerInside=false,playerToZone=100,neutral=false,red=false,neutralMode='',safetyPhase='none',safety=0}
 local t=Pe.new()
 F.place(f,1,0,100); F.place(f,3,10,100); Pe.update(t,f,p,'C',inc,0,1/60)
 F.place(f,1,20,100); Pe.update(t,f,p,'C',inc,1/60,1/60)
 assert(t.passedUnder and t.count==0 and t.giveBack==3,'pass in the approach to a yellow zone: place to give back')
 local now=1/60; while now<C.K.passGiveBack+1 do now=now+0.1; Pe.update(t,f,p,'C',inc,now,0.1) end
 assert(t.count==1 and t.reason=='pass','place kept: infraction at the deadline')
 local Delta=require('src/delta')
 local t2=Pe.new(); local d=Delta.new(); local sc={cars=e.incidents.cars,playerZone=false,playerInside=false,zoneCount=0,zones={},neutral=true,red=false,neutralMode='sc',safetyPhase='out',safety=3}
 F.place(f,3,-3000,0); f.cars[3].pit=true
 local z=1000; now=0
 for _=1,30*60 do now=now+1/60; z=z+150/3.6/60; F.place(f,1,z,150); Delta.update(d,f,p,sc,e.states,now,1/60,false); Pe.update(t2,f,p,'C',sc,now,1/60,d) end
 assert(d.kind=='scCall' and t2.count>=1 and t2.reason=='delta' and t2.deltaKind=='scCall','safety car still in the pit lane: FCY delta enforced')
 local t3=Pe.new(); F.place(f,1,0,100); F.place(f,3,10,100); f.cars[3].pit=false; Pe.update(t3,f,p,'C',inc,0,1/60)
 f.cars[1].pit=true; Pe.update(t3,f,p,'C',inc,1/60,1/60); f.cars[1].pit=false; F.place(f,1,20,100); Pe.update(t3,f,p,'C',inc,2/60,1/60)
 assert(not t3.passedUnder,'places gained through the pit lane: not a pass')
end
-- 1.8.0 (relecture) : arrêt réel non compté comme arrêt écarté ; incident écarté hors piste de nouveau signalé s'il
-- revient en piste sans repartir.
tests.INCIDENT_COUNTS_AND_DISMISSAL=function()
 local e,f=F.scene('J',3); F.place(f,3,5000,100); F.tick(e,f,1)
 for n=1,120 do F.place(f,3,5000,math.max(0,30-n*0.5)); F.tick(e,f,1/60) end
 F.tick(e,f,3)
 assert(e.incidents.cars[3].incident and e.incidents.suppressed.queue==0 and e.incidents.suppressed.crawl==0,'real stop not counted as a suppressed one')
 f.cars[3].offtrack=true; F.tick(e,f,C.K.incidentMaxAge+5)
 assert(not e.incidents.cars[3].incident,'off track for long: dismissed')
 f.cars[3].offtrack=false; F.tick(e,f,3)
 assert(e.incidents.cars[3].incident,'back on track while still stopped: hazard again')
end
-- 1.8.0 (relecture des réglages) : voiture de sécurité garée hors course même si le profil n'utilise pas la voiture de
-- sécurité ; panneau et messages au choix du pilote quand Accidents est décoché ; préréglage intégré sans perte des
-- préférences ni des motifs de classes ; préréglage personnel ancien ou invalide jamais perdu.
tests.CONFIG_REVIEW_180=function()
 local e,f=F.scene('Q',4); e.g.safetyCarModel='sc_car'; E.changed(e); f.cars[4].id='sc_car'
 F.place(f,4,7000,0); f.cars[4].pit=true; f.cars[4].inPitBox=true; F.tick(e,f,1)
 assert(e.profiles.Q.neutralization~='sc' and e.commands[4].scPark,'safety car parked in qualifying with the default neutralization')
 local p=C.defaults('C'); C.validate('C',p,p); p.section_accidents=false; p.section_rules=true; p.flagPanel=false; p.yellowMessage=false
 local out=C.effective('C',p)
 assert(out.flagPanel==false and out.yellowMessage==false,'driver choice kept with Accidents unticked')
 p.flagPanel=true; p.yellowMessage=true; out=C.effective('C',p); assert(out.flagPanel and out.yellowMessage)
 local q=C.defaults('C'); C.validate('C',q,q); q.drsBeepVolume=350; q.flagPanel=false; q.classPatterns='lmp1:1,gt3:3'
 local candidate=C.defaults('C'); C.preset('Course','C',candidate)
 local kept={}; for key in pairs(C.keptKeySet) do kept[key]=q[key] end
 C.preset('Course','C',q); for key in pairs(C.keptKeySet) do q[key]=kept[key] end
 assert(q.drsBeepVolume==350 and q.flagPanel==false and q.classPatterns=='lmp1:1,gt3:3','preferences and class patterns kept')
 local Pr=require('src/presets')
 assert(Pr.signature('C',q,e.g,{},C.keptKeySet)==Pr.signature('C',candidate,e.g,{},C.keptKeySet),'preset still recognised with personal preferences')
 local store=Pr.layout(); store.name='Ancien'; store.profile='C'; store.revision=2
 local entry,errors=Pr.decode(store)
 assert(entry and entry.p.playerPenalties==true and entry.p.aiPenalties==true and errors==0,'pre-1.8.0 race preset: penalties back to the profile default')
 store.revision=3; entry=Pr.decode(store); assert(entry.p.playerPenalties==false,'current preset: stored choice kept')
 store.p_levelPct=9999; local bad,n=Pr.decode(store)
 assert(bad and n>0 and bad.p.levelPct==C.defaults('C').levelPct,'invalid value replaced, preset kept')
 assert(Pr.encode(entry).revision==14)
end
-- 1.8.0 (relecture des écritures) : drapeau rendu à AC même capacité suspendue ; drapeau noir levé à la restitution ;
-- journal limité pour de bon ; bip non joué libéré ; sanctions conservées à travers un rechargement.
tests.IO_REVIEW_180=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C'); local a=A.new(); assert(A.access(a))
 a.flagOverride=true; a.caps.flag.available=false; a.caps.flag.reason='failures'; local writes=host.flagOverrides
 A.flag(a,f,false); assert(not a.flagOverride and host.flagOverrides==writes+1,'flag handed back although the capability was suspended')
 a.caps.flag.available=false; A.flag(a,f,true); assert(not a.flagOverride and host.flagOverrides==writes+1,'never imposed while suspended')
 local t={requestId=1,kind='dq',seconds=0}; f.player=1; A.penalty(a,f,t); assert(a.blackFlag,'black flag applied')
 A.restore(a,f,false,0,true); assert(not a.blackFlag and host.penaltyKinds[#host.penaltyKinds]==5,'black flag released on unload')
 a.journalPath='logs/test.log'; host.files['logs/test.log']=''; a.journalBytes=C.K.journalMaxBytes-200
 A.journalWrite(a,string.rep('x',300)); assert(a.journalPath==nil,'journal closed after the size notice')
 local Pe=require('src/penalties'); local p=Pe.new(); p.count=3; p.disqualified=true
 p.ai.count[2]=2; p.ai.dq[2]=true; f.cars[2].identity='model_2'
 f.session=7; local text=Pe.serialize(p,f,7); local q=Pe.new(); Pe.restore(q,text,7); Pe.reset(q); Pe.resume(q,f)
 assert(q.count==3 and q.disqualified and q.ai.dq[2] and q.ai.count[2]==2,'sanctions restored in the same session')
 local r=Pe.new(); Pe.restore(r,text,8); Pe.resume(r,f); assert(r.count==0 and not r.ai.dq[2],'another session: nothing restored')
 f.cars[2].identity='other'; local s=Pe.new(); Pe.restore(s,text,7); Pe.resume(s,f); assert(not s.ai.dq[2],'another car at that index: nothing restored')
end
-- 1.8.0 (seconde relecture) : réglages sans effet ramenés au défaut ; Restaurer garde les préférences ; Départ sans
-- effet sur l'évitement hors course.
tests.WIRING_REVIEW_180=function()
 local p=C.defaults('J'); p.aiPenalties=true; p.playerPenalties=true; C.validate('J',p,p)
 assert(not p.aiPenalties and not p.playerPenalties,'penalties never kept in track day')
 local q=C.defaults('Q'); q.stintLevelSwing=8; C.validate('Q',q,q); assert(q.stintLevelSwing==C.defaults('Q').stintLevelSwing,'endurance overlay values back to default in qualifying')
 local c=C.defaults('C'); C.validate('C',c,c); c.drsBeepVolume=350; c.classPatterns='lmp1:1,gt3:3'; C.restore('C',c)
 assert(c.drsBeepVolume==350 and c.classPatterns=='lmp1:1,gt3:3','restore keeps preferences and class patterns')
 local e,f=F.scene('J',3); e.profiles.J.section_start=true; e.profiles.J.startDelay=30; E.changed(e); e.p.personalLineJitter=0; e.startedAt=e.time
 F.place(f,2,0,100); F.place(f,3,60,0); F.tick(e,f,4)
 assert(e.states[2].state=='AVOID','start delay never delays avoidance outside the race ('..e.states[2].state..')')
end
-- 1.8.0 (seconde relecture) : zone jaune du joueur jugée comme les IA (selon la distance au début de la zone), panneau
-- d'approche avancé selon la vitesse ; freinage normal jamais sanctionné, arrivée lancée sanctionnée.
tests.PLAYER_ZONE_ENVELOPE=function()
 local function run(kmh,decel,react)
  local e,f=F.scene('P',3); F.place(f,1,-3000,kmh); F.place(f,3,6000,0); F.tick(e,f,3)
  assert(e.incidents.cars[3].incident)
  local z,v,seen,t0,shown=2000,kmh,false,nil,nil
  while z<6060 do
   if e.incidents.playerZone and not seen then seen=true; t0=0; shown=e.panel.kind end
   if seen then t0=t0+1/60; if t0>react then v=math.max(e.run.yellowSpeedKmh,v-decel*3.6/60) end end
   z=z+v/3.6/60; F.place(f,1,z,v); F.tick(e,f,1/60)
  end
  return e
 end
 assert(run(280,8,0.8).penalties.count==0,'280 km/h, braking at 8 m/s² from the panel: no penalty')
 assert(run(150,6,0.8).penalties.count==0,'150 km/h, braking at 6 m/s² from the panel: no penalty')
 assert(run(280,0,99).penalties.count==1,'280 km/h without braking: penalty')
 assert(run(200,2,0.8).penalties.count==1,'braking too gently to reach the limit at the zone: penalty')
 local e,f=F.scene('P',3); F.place(f,3,6000,0); F.tick(e,f,3); F.place(f,1,5500,150); F.tick(e,f,0.5)
 assert(e.panel.kind=='yellow' and e.incidents.playerToZone>0,'approach: distance to the zone start')
 F.place(f,1,5800,50); F.tick(e,f,0.5); assert(e.panel.kind=='zone','inside the zone')
 f.cars[1].pit=true; F.tick(e,f,0.5); assert(not e.incidents.playerZone,'no yellow zone in the pit lane')
end
-- 1.8.0 (seconde relecture) : pied levé progressif d'une IA sanctionnée ; joueur aux gaz coupés dépassable.
tests.SANCTION_RAMP_AND_SERVING_PLAYER=function()
 local Pe=require('src/penalties')
 local e,f=F.scene('C',4); e.run.aiPenalties=true
 local st={}; for i=1,4 do st[i]={yellow=true} end
 local function step(t,za,zp)
  F.place(f,2,za,100); F.place(f,1,zp,40); F.place(f,4,5000,100)
  e.states[2].nextPerception=0; F.tick(e,f,1/60)
  return Pe.ai(t,f,e.run,'C',e.incidents,st,e.perception.rows,e.time)
 end
 local t=Pe.new(); t.kind='slow'; t.lastAt=e.time; t.seconds=5
 step(t,0,20); assert(not step(t,30,20),'player serving a throttle cut: may be passed')
 local t2=Pe.new(); step(t2,0,20); assert(step(t2,30,20),'player at 40 km/h, not serving: sanction')
 e.penalties=t2; e.penalties.ai.slowUntil[2]=e.time+5; e.penalties.ai.slowKmh[2]=70; e.penalties.ai.slowFrom[2]=100; e.penalties.ai.slowAt[2]=e.time
 F.tick(e,f,1/60); assert(e.commands[2].yellowLimit>95,'no sudden braking: '..e.commands[2].yellowLimit)
end
-- 1.8.0 (seconde relecture) : voiture de sécurité dans la voie des stands, limite affichée ; drapeau noir remis après
-- un rechargement ; attente derrière la cible bornée.
tests.REVIEW2_MISC=function()
 local Panel=require('src/panel'); local Pe=require('src/penalties')
 local e,f=F.scene('C',3); local t=e.incidents; t.neutral=true; t.neutralMode='sc'; t.safetyPhase='out'; t.safety=3; f.cars[3].pit=true
 local panel=Panel.new(); Panel.update(panel,t,f,e.run,'C',0)
 assert(panel.kind=='sc' and panel.raw==require('src/lang').flagDetails.scCall,'safety car still in the pit lane: called, FCY delta')
 local p=Pe.new(); p.count=6; p.disqualified=true; f.session=4; local text=Pe.serialize(p,f,4)
 local q=Pe.new(); Pe.restore(q,text,4); Pe.reset(q); Pe.resume(q,f)
 assert(q.disqualified and q.kind=='dq' and q.requestId==1,'black flag imposed again after a reload')
 local e2,f2=F.scene('C',3); e2.p.personalLineJitter=0; F.place(f2,2,0,100); F.place(f2,3,15,100); F.tick(e2,f2,0.1)
 local s=e2.states[2]; s.state='OVT_ARM'; s.since=e2.time; s.target=3; s.targetSide=1; s.passAlongside=false; f2.cars[2].yawRate=1.5
 e2.states[2].nextPerception=0; F.tick(e2,f2,10); assert(s.state=='OVT_ARM','waiting behind in corners: no early abort ('..s.state..')')
 F.tick(e2,f2,12); assert(s.state~='OVT_ARM','wait bounded ('..s.state..')')
end
-- 1.8.0 (relecture d'hygiène) : une IA pas encore classée n'est comparée à aucune classe (avant, prise pour une classe
-- plus lente, elle ne pouvait doubler personne, pas même le joueur qui l'invitait).
tests.UNCLASSIFIED_NOT_SLOWER=function()
 local e,f=F.scene('J',3); C.preset('Nordschleife','J',e.profiles.J); E.changed(e); F.tick(e,f,1/60); e.p.personalLineJitter=0
 assert(e.run.multiClass,'multi-class active in the built-in preset')
 F.place(f,1,20,100,3); F.place(f,2,0,100); F.place(f,3,5000,100)
 e.states[1].class=1; e.states[1].classified=true; e.states[2].class=2
 local s=e.states[2]; s.nextPerception=0; for b=1,#s.pace do s.pace[b]=0 end; s.paceCount=0; s.paceMean=0
 local engaged=false
 for _=1,4*60 do F.tick(e,f,1/60); if F.passing(s.state) then engaged=true end end
 assert(engaged,'unclassified AI invited by a classified player: pass engaged')
 e.states[2].classified=true; e.states[1].class=1; e.states[2].class=2
 local P=require('src/perception'); F.place(f,2,0,100); F.place(f,3,30,100,2)
 assert(P.corridor(f.cars,f.count,2,1,50,1,0.1) and not P.corridor(f.cars,f.count,2,1,50,1,5.5),'corridor uses the configured lateral reach')
 local Pr=require('src/presets'); local store=Pr.layout(); store.name='Futur'; store.profile='C'; store.schemaVersion=C.version+1
 assert(not Pr.decode(store),'preset from a future version: never loaded')
end
-- 1.8.0 (relecture finale) : panneau d'approche avancé à haute vitesse pour freiner, mais dépassement interdit seulement
-- à 150 m de la zone, comme pour les IA.
tests.PLAYER_NO_PASS_DISTANCE=function()
 local Pe=require('src/penalties')
 local e,f=F.scene('C',3); local p=e.run
 local far={cars=e.incidents.cars,playerZone=true,playerNoPass=false,playerInside=false,playerToZone=400,neutral=false,red=false,neutralMode='',safetyPhase='none',safety=0}
 local t=Pe.new()
 F.place(f,1,0,250); F.place(f,3,10,240); Pe.update(t,f,p,'C',far,0,1/60)
 F.place(f,1,20,250); Pe.update(t,f,p,'C',far,1/60,1/60)
 assert(not t.passedUnder and t.count==0,'pass 400 m before the zone: allowed')
 local e2,f2=F.scene('C',3); F.place(f2,3,6000,0); F.tick(e2,f2,3); F.place(f2,1,5300,280); F.tick(e2,f2,0.5)
 assert(e2.incidents.playerZone and not e2.incidents.playerNoPass and not e2.panel.noPass,'early panel at speed: no no-pass line yet')
 F.place(f2,1,5600,120); F.tick(e2,f2,0.5)
 assert(e2.incidents.playerNoPass and e2.panel.noPass,'150 m before the zone: no passing, line shown')
end
-- Beta 1.0 : décisions du pilote. Drapeau rouge : reprise hors des stands pénalisée ; VSC : vitesse cible du joueur ;
-- arrêts obligatoires du joueur ; file sous neutralisation ; voiture de sécurité de modèle unique.
tests.PILOT_DECISIONS=function()
 local Pe=require('src/penalties')
 local e,f=F.scene('C',3); local p=e.run
 local inc={cars=e.incidents.cars,red=true,neutral=false,playerZone=false,playerNoPass=false,playerInside=false,playerToZone=0,neutralMode='',safetyPhase='none',safety=0}
 local t=Pe.new(); F.place(f,1,1000,60); Pe.update(t,f,p,'C',inc,0,1/60)
 inc.red=false; Pe.update(t,f,p,'C',inc,1/60,1/60); local reason=Pe.update(t,f,p,'C',inc,2/60,1/60)
 assert(t.count==1 and t.reason=='red','restart outside the pit lane: penalty')
 local t2=Pe.new(); inc.red=true; f.cars[1].pit=true; Pe.update(t2,f,p,'C',inc,0,1/60); inc.red=false; Pe.update(t2,f,p,'C',inc,1/60,1/60); f.cars[1].pit=false; Pe.update(t2,f,p,'C',inc,2/60,1/60)
 assert(t2.count==0,'player waiting in the pit lane: no penalty')
 -- VSC : cible connue seulement là où l'allure est apprise ; pénalité au-delà de la marge.
 local e2,f2=F.scene('C',3); e2.profiles.C.neutralization='vsc'; E.changed(e2)
 local ps=e2.states[1]; for b=1,#ps.pace do ps.pace[b]=200/3.6 end; ps.paceCount=400; ps.paceMean=200/3.6
 F.place(f2,1,0,200); F.place(f2,2,-500,150); F.place(f2,3,6000,0)
 while not e2.incidents.neutral do F.tick(e2,f2,0.5) end
 F.tick(e2,f2,0.3) -- panneau rafraîchi tous les quarts de seconde
 assert(e2.delta.kind=='vsc' and e2.panel.kind=='vsc','VSC delta shown on the panel')
 local z=0; for _=1,60*15 do z=z+200/3.6/60; F.place(f2,1,z,200); F.tick(e2,f2,1/60) end
 assert(e2.penalties.count==1 and e2.penalties.reason=='delta' and e2.penalties.deltaKind=='vsc','200 km/h under VSC (reference about 154 km/h): delta penalty')
 F.place(f2,1,0,100); F.tick(e2,f2,3)
 assert(math.abs(ps.pace[1]-200/3.6)<1e-9,'player pace never learned under a flag')
 -- Arrêt obligatoire du joueur : rappel, puis pénalité à la fermeture de la fenêtre.
 local e3,f3=F.scene('C',3); local p3=e3.profiles.C; p3.mandatoryStops=1; p3.pitWindowOpenPct=25; p3.pitWindowClosePct=75; E.changed(e3)
 f3.sessionLaps=20; f3.leaderLaps=10; f3.timedRace=false; F.tick(e3,f3,1)
 assert(e3.incidents.playerPitDue==1 and e3.panel.kind=='pit','reminder when the window opens')
 F.tick(e3,f3,20); assert(e3.panel.kind~='pit','reminder hidden in the middle of the window')
 f3.leaderLaps=14; F.tick(e3,f3,0.5); assert(e3.panel.kind=='pit','reminder near the end of the window')
 f3.leaderLaps=16; F.tick(e3,f3,1); assert(e3.penalties.count==1 and e3.penalties.reason=='stop','missed stop: penalty')
 -- File sous VSC : jamais plus vite que la voiture de devant.
 local e4,f4=F.scene('C',4); e4.profiles.C.neutralization='vsc'; E.changed(e4)
 F.place(f4,2,0,150); F.place(f4,3,20,60); F.place(f4,4,6000,0); F.tick(e4,f4,25)
 assert(e4.incidents.neutral and e4.commands[2].yellowLimit<=60+(20-4.4-C.K.queueKeep)*C.K.queueClose+1e-6,'queue under VSC: capped at the car ahead, below its own target ('..e4.commands[2].yellowLimit..')')
 -- Voiture de sécurité : modèle porté par deux voitures, aucune garée.
 local e5,f5=F.scene('Q',4); e5.g.safetyCarModel='sc_car'; e5.g.safetyCarPicked=true; E.changed(e5); f5.cars[3].id='sc_car'; f5.cars[4].id='sc_car'; F.tick(e5,f5,1)
 assert(e5.incidents.safety==3 and e5.safetyAmbiguous and e5.commands[3].scPark and e5.commands[4].scPark and e5.commands[4].parkReason=='spare' and not e5.commands[4].active and f5.cars[4].safetyCar,'several cars of the model: the first is the safety car, the others parked, never racing')
end
-- Beta 1.0 : panneau de drapeaux redessiné. Disposition sans chevauchement à toutes les tailles, avec ou sans barre de
-- titre de CSP, cadre du temps delta et pastilles.
tests.FLAG_PANEL_LAYOUT=function()
 -- Beta 1.14 : bandeau compact. Dans la fenêtre, drapeau à gauche du texte, version en petit sans rien recouvrir,
 -- titre sur au moins un tiers de la largeur, consigne sous le titre, delta lisible dès qu'il y a la place,
 -- pastilles sous la bande ; de 360 × 80 à 900 × 220, haut du contenu à 0, 30 ou 40.
 local UI=require('src/ui')
 local function inside(r,w,h,top) return r[1]>=0 and r[3]<=w+1e-6 and r[2]>=top-1e-6 and r[4]<=h+1e-6 and r[3]>=r[1] and r[4]>=r[2] end
 local function apart(a,b) return a[3]<=b[1]+1e-6 or b[3]<=a[1]+1e-6 or a[4]<=b[2]+1e-6 or b[4]<=a[2]+1e-6 end
 for _,w in ipairs({360,480,620,760,900}) do for _,h in ipairs({80,110,150,220}) do for _,top in ipairs({0,30,40}) do
  for _,boxed in ipairs({false,true}) do for _,pills in ipairs({false,true}) do
   local l=UI.flagLayout(w,h,top,boxed,pills); local id=w..'x'..h..'@'..top..(boxed and 'd' or '')..(pills and 'p' or '')
   assert(inside(l.flag,w,h,top) and inside(l.title,w,h,top) and inside(l.version,w,h,top),'inside the window '..id)
   assert(l.flag[3]<l.title[1] and apart(l.version,l.title) and apart(l.version,l.flag),'flag left of the text, version clear '..id)
   local right=w
   if l.delta then
    assert(inside(l.delta,w,h,top) and l.title[3]<l.delta[1] and apart(l.delta,l.version),'text then delta box, inside '..id); right=l.delta[1]
    assert(l.delta[4]-l.delta[2]>=2*C.K.deltaBoxMin-1e-6,'delta box legible '..id)
   end
   assert(boxed or not l.delta,'no delta box without a delta '..id)
   assert(l.title[3]<=right and l.title[3]-l.title[1]>=w*0.32-1e-6,'title never under the delta box, a third of the width at least '..id)
   if l.detail then assert(l.detail[2]>=l.title[4]-1e-6 and l.detail[3]<=right and inside(l.detail,w,h,top),'one-line instruction below the title '..id) end
   if pills then assert(l.pills and inside(l.pills,w,h,top) and l.pills[2]>=l.title[4]-1e-6 and (not l.detail or l.detail[4]<=l.pills[2]+1e-6) and (not l.delta or l.delta[4]<=l.pills[2]+1e-6),'pills under the band '..id) end
   if boxed and h-top>=(pills and 90 or 70) then assert(l.delta,'delta box whenever there is room '..id) end
   if h-top>=60 then assert(l.detail,'instruction shown whenever there is room '..id) end
  end end
 end end end
end
-- Beta 1.2 : temps delta. Départ à +1 s, référence de repli, plafond, saut, voie des stands, infraction au passage d'un
-- mini-secteur, nouveau départ après une pénalité, file derrière la voiture de sécurité, drapeau rouge jusqu'aux stands.
tests.DELTA_CORE=function()
 local Delta=require('src/delta')
 local e,f=F.scene('C',3); local p=e.run
 local inc={cars=e.incidents.cars,red=false,neutral=true,neutralMode='fcy',safetyPhase='none',safety=0,playerZone=false,playerInside=false,playerZoneSlot=0,playerZoneDouble=false,zoneCount=0,zones={}}
 local d=Delta.new(); local now=0; local z=1000
 local function step(kmh,seconds,pit,queued)
  for _=1,math.floor(seconds*60+0.5) do now=now+1/60; z=z+kmh/3.6/60; F.place(f,1,z,kmh); f.cars[1].pit=pit==true; Delta.update(d,f,p,inc,e.states,now,1/60,queued==true) end
 end
 step(80,0.1); assert(d.kind=='fcy' and math.abs(d.value-C.K.deltaStart)<0.05,'starts at +1 s')
 step(80,5); assert(math.abs(d.value-C.K.deltaStart)<0.05,'at the reference speed (fallback while the pace is unknown): unchanged '..d.value)
 step(20,20); assert(math.abs(d.value-C.K.deltaCap)<1e-9,'capped at +3 s: no credit to drive flat out afterwards')
 local before=d.value; z=z+3000; step(80,0.1); assert(math.abs(d.value-before)<0.1,'jump (teleport): resync only')
 step(60,2,true); assert(d.value==nil,'not shown in the pit lane')
 step(80,0.1); assert(math.abs(d.value-C.K.deltaStart)<0.05,'fresh start after the pit lane')
 local infraction=false
 for _=1,60*20 do now=now+1/60; z=z+160/3.6/60; F.place(f,1,z,160); Delta.update(d,f,p,inc,e.states,now,1/60,false); if d.infraction then infraction=true; break end end
 assert(infraction and d.infractionKind=='fcy' and d.infractionValue<-p.deltaTolerance,'negative at a mini-sector boundary: infraction')
 Delta.penalized(d); assert(d.course.delta==C.K.deltaStart,'fresh start after a penalty')
 -- Voiture de sécurité en piste : delta jusqu'à la file, figé (jamais jugé) une fois la file rejointe.
 inc.neutralMode='sc'; inc.safetyPhase='out'; inc.safety=3; f.cars[3].pit=false
 step(80,0.1); assert(d.kind=='sc','safety car on track: delta until the queue')
 step(200,10,false,true); assert(d.value>=C.K.deltaStart and not d.infraction,'in the queue: frozen, never judged')
 -- Drapeau rouge : delta jusqu'à la voie des stands, puis plus rien.
 inc.neutral=false; inc.red=true; step(70,0.5); assert(d.kind=='red','red flag: delta to the pits')
 step(50,0.5,true); assert(d.value==nil and d.kind=='' and not d.course.on,'in the pit lane: done')
 inc.red=false; step(80,0.1); assert(d.value==nil and not d.course.on,'regime over')
end
-- Double drapeau jaune : delta remis à zéro à l'entrée, figé double à l'entrée, zone disparue jamais jugée, sortie
-- jugée ; simple jaune : pas de delta.
tests.DELTA_ZONE=function()
 local Delta=require('src/delta')
 local e,f=F.scene('C',3); local p=e.run
 local zones={{slot=3,spline=0.5,onTrack=true}}
 local inc={cars=e.incidents.cars,red=false,neutral=false,neutralMode='',safetyPhase='none',safety=0,playerZone=true,playerInside=false,playerZoneSlot=0,playerZoneDouble=true,zoneCount=1,zones=zones}
 local d=Delta.new(); local now=0; local z=4500
 local function step(kmh,seconds) for _=1,math.floor(seconds*60+0.5) do now=now+1/60; z=z+kmh/3.6/60; F.place(f,1,z,kmh); Delta.update(d,f,p,inc,e.states,now,1/60,false) end end
 step(40,1); assert(d.value==nil,'approach: no delta yet')
 inc.playerInside=true; inc.playerZoneSlot=3; step(40,0.1); assert(d.kind=='zone' and math.abs(d.value)<0.05,'zone entry: delta reset to zero')
 zones[1].onTrack=false; inc.playerZoneDouble=false; step(40,1); assert(d.kind=='zone','double yellow latched at the entry')
 d.zone.delta=-2; inc.zoneCount=0; inc.playerInside=false; inc.playerZone=false; step(40,1/60)
 assert(not d.infraction and d.value==nil,'zone gone before the exit (incident cleared): never judged')
 inc.zoneCount=1; inc.playerZone=true; inc.playerInside=true; inc.playerZoneDouble=true; zones[1].onTrack=true; step(40,0.1)
 assert(math.abs(d.value)<0.05,'entering again: reset to zero again')
 d.zone.delta=-1; inc.playerInside=false; step(40,1/60); assert(d.infraction and d.infractionKind=='zone','exit with a negative zone delta: infraction')
 local d2=Delta.new(); inc.playerInside=false; Delta.update(d2,f,p,inc,e.states,now,1/60,false)
 inc.playerInside=true; inc.playerZoneDouble=false; Delta.update(d2,f,p,inc,e.states,now+1/60,1/60,false)
 assert(d2.value==nil and not d2.zone.on,'single yellow (incident off track): no delta')
end
-- Référence : allure de la flotte (médiane, par classe en multi-classes), jamais plus sévère que la flotte.
tests.DELTA_FLEET_REFERENCE=function()
 local Delta=require('src/delta')
 local e,f=F.scene('C',5); local d=Delta.new()
 local paces={[2]=120,[3]=125,[4]=200,[5]=210}
 for i=2,5 do local s=e.states[i]; for b=1,#s.pace do s.pace[b]=paces[i]/3.6 end; s.paceCount=400 end
 for _=1,C.K.paceBins/C.K.fleetBinsPerFrame+1 do Delta.refresh(d,f,e.states,false) end
 assert(math.abs(Delta.pace(d,e.states,1,10,false)-200/3.6)<1e-9,'player without learned pace: fleet median')
 local ps=e.states[1]; for b=1,#ps.pace do ps.pace[b]=230/3.6 end; ps.paceCount=400
 assert(math.abs(Delta.pace(d,e.states,1,10,false)-230/3.6)<1e-9,'faster own pace kept')
 ps.pace[10]=60/3.6; assert(math.abs(Delta.pace(d,e.states,1,10,false)-200/3.6)<1e-9,'a bad own sample never makes a place harsher than the fleet')
 e.states[2].class=2; e.states[3].class=2; e.states[4].class=1; e.states[5].class=1; ps.class=2; ps.pace[10]=0
 for _=1,C.K.paceBins/C.K.fleetBinsPerFrame+1 do Delta.refresh(d,f,e.states,true) end
 assert(math.abs(Delta.pace(d,e.states,1,10,true)-125/3.6)<1e-9,'multi-class: median of the player class only')
 assert(math.abs(Delta.reference(d,e.states,1,10,true,30,80)-125/3.6/1.3)<1e-9,'reference time +30 %')
 assert(math.abs(Delta.reference(d,e.states,1,10,true,30,80)-Delta.reference(d,e.states,4,10,true,30,80))>1,'each class its own reference')
 local d3=Delta.new(); assert(math.abs(Delta.reference(d3,{{paceCount=0,pace={},class=1}},1,10,false,50,80)-80/3.6)<1e-9,'unknown pace: fallback speed')
end
-- Voiture de sécurité appelée : delta FCY, mais jamais plus vite qu'elle moins une marge (elle rattrape le peloton).
tests.DELTA_SC_MERGE=function()
 local e,f=F.scene('C',5); e.profiles.C.neutralization='sc'; e.g.safetyCarModel='sc_car'; E.changed(e)
 f.cars[5].id='sc_car'; F.place(f,5,7000,0); f.cars[5].pit=true; f.cars[5].inPitBox=true
 local s=e.states[2]; for b=1,#s.pace do s.pace[b]=300/3.6 end; s.paceCount=400
 F.place(f,2,0,250); F.place(f,4,5000,0); F.tick(e,f,35)
 assert(e.incidents.neutral and e.incidents.neutralMode=='sc' and f.cars[5].pit,'called, safety car still in the pit lane')
 assert(e.commands[2].yellowLimit<=e.run.safetyCarSpeedKmh-C.K.scMergeMargin+1e-6,'pack slower than the safety car: '..e.commands[2].yellowLimit)
end
-- Relevé en jeu : 8 sanctions d'IA juste après une zone jaune. La plus proche de la zone ralentissait d'abord, celle de
-- derrière (limite d'approche plus haute) la rattrapait et la doublait. En file : jamais plus vite que la voiture de
-- devant, au-delà d'un léger rapprochement ; jamais de file derrière une voiture qu'il est permis de doubler.
tests.AI_ZONE_QUEUE=function()
 local e,f=F.scene('C',4)
 F.place(f,4,6000,0); F.place(f,3,5600,90); F.place(f,2,5570,150); F.tick(e,f,8)
 assert(e.incidents.cars[4].incident and e.states[2].yellow,'zone and approach regime')
 local allowed=90+math.max(0,30-4.4-C.K.queueKeep)*C.K.queueClose
 assert(e.commands[2].yellowLimit<=allowed+1e-6,'follower capped at the car ahead: '..e.commands[2].yellowLimit)
 F.place(f,3,5600,10); F.tick(e,f,1)
 assert(e.commands[2].yellowLimit>allowed+10,'no queue behind a crawling car: '..e.commands[2].yellowLimit)
end
-- Une IA qui double pendant la transition (début de FCY) lève le pied pour rendre la place : rendue, rien ; gardée,
-- sanction à l'échéance.
tests.AI_GIVE_BACK=function()
 local function run(giveBack)
  local e,f=F.scene('C',4); e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
  F.place(f,4,6000,0); F.place(f,2,1000,150); F.place(f,3,1010,150)
  -- Allure connue et élevée : la levée de pied pour rendre la place est la seule limite sous la vitesse du moment.
  local s=e.states[2]; for b=1,#s.pace do s.pace[b]=400/3.6 end; s.paceCount=400
  for _=1,40*10 do F.tick(e,f,0.1); if e.incidents.neutral then break end end
  F.tick(e,f,0.2)
  F.place(f,2,1020,150); F.place(f,3,1000,120); e.states[2].nextPerception=0; F.tick(e,f,0.5)
  assert(e.penalties.ai.giveBack[2]==3 and (e.penalties.ai.count[2] or 0)==0,'pass during the transition: place to give back')
  F.tick(e,f,1); assert(e.commands[2].yellowLimit<150,'lifting to let it by: '..e.commands[2].yellowLimit)
  if giveBack then F.place(f,3,1040,120); e.states[2].nextPerception=0; F.tick(e,f,0.5); assert(e.penalties.ai.giveBack[2]==0,'given back') end
  F.tick(e,f,C.K.passGiveBack+1)
  return e
 end
 assert((run(true).penalties.ai.count[2] or 0)==0,'place given back: no sanction')
 assert(run(false).penalties.ai.count[2]==1,'place kept: sanction at the deadline')
end
-- Cas relevé en jeu (FCY à 250 km/h) : l'IA juste devant freine plus fort, le joueur la double en freinant ; place
-- rendue : rien ; gardée : pénalité de dépassement à l'échéance.
tests.PLAYER_GIVE_BACK_ONSET=function()
 local function run(giveBack)
  local e,f=F.scene('C',3); e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
  local zp,za=1000,1035
  F.place(f,3,6000,0); F.place(f,1,zp,250); F.place(f,2,za,250)
  for _=1,40*10 do F.tick(e,f,0.1); if e.incidents.neutral then break end end
  local vp,va,elapsed,passed=250,250,0,false
  for _=1,60*14 do
   elapsed=elapsed+1/60
   va=math.max(80,va-8*3.6/60)
   if elapsed>1 then vp=math.max(76,vp-e.run.yellowDecel*3.6/60) end
   if zp>za+5 then passed=true end
   -- Place rendue : une fois passé devant, le joueur ralentit jusqu'à ce que l'IA soit nettement devant.
   if giveBack and passed and zp>za-10 then vp=math.min(vp,va-30) end
   zp=zp+vp/3.6/60; za=za+va/3.6/60
   F.place(f,1,zp,vp); F.place(f,2,za,va); F.tick(e,f,1/60)
  end
  return e,passed
 end
 local e,passed=run(false); assert(passed and e.penalties.count==1 and e.penalties.reason=='pass','place kept: pass penalty at the deadline')
 local e2,passed2=run(true); assert(passed2 and e2.penalties.count==0,'place given back: no penalty')
end
-- Beta 1.2 : règles du DRS (F1 : un tour du leader après le départ et chaque reprise ; coupé sous la pluie et sous
-- drapeau), pour toutes les voitures ; jamais en journée circuit ; essais et qualifications : pluie et drapeaux.
tests.DRS_RULES=function()
 local L=require('src/lang')
 local e,f=F.scene('C',4); f.length=2000; for i=1,4 do f.cars[i].drsPresent=true; F.place(f,i,(i-1)*30,100) end
 -- Départ vu par l'app : tours mesurés depuis le départ ; le compteur du jeu (grille avant la ligne) est ignoré.
 e.drsRule={restart=false,started=false,seen=false,travel={},last={},leader=0,reason=''}; f.started=false; f.time=0; F.tick(e,f,0.1)
 f.started=true; f.leaderLaps=1; F.tick(e,f,0.5)
 assert(e.commands[1].drsBlock and e.commands[2].drsBlock and e.incidents.drsReason=='laps' and e.incidents.drsLapsLeft==1,'start: DRS off for everyone, even if the game counter already shows a lap')
 assert(e.incidents.messageKind=='drsLaps','player told when DRS opens')
 F.tick(e,f,60,true); assert(e.commands[1].drsBlock,'not yet a full lap of the leader')
 F.tick(e,f,20,true); assert(not e.commands[1].drsBlock and not e.commands[2].drsBlock and e.incidents.drsReason=='' and e.incidents.messageKind=='drsOn','after one measured lap of the leader: allowed')
 local found=false; for n=0,e.log.count-1 do local r=e.log[(e.log.head-n-1)%200+1]; if r.message:find('DRS autorise',1,true) then found=true end end
 assert(found,'journal line when DRS opens')
 -- Saut (téléportation, retour au stand) : jamais compté comme un tour.
 e.drsRule.restart=true; F.tick(e,f,0.1); assert(e.commands[1].drsBlock,'restart: off again')
 for i=1,4 do F.place(f,i,f.cars[i].z+600,100) end; F.tick(e,f,0.1)
 assert(e.commands[1].drsBlock and e.drsRule.leader<0.1,'jump never counted as a lap')
 -- Pluie.
 e.profiles.C.rulesDrsLaps=0; E.changed(e); F.tick(e,f,0.5); assert(not e.commands[1].drsBlock,'no lap rule: allowed')
 f.wet=1; f.rain=0.5; F.tick(e,f,20)
 assert(e.weather.wet and e.commands[1].drsBlock and e.commands[3].drsBlock and e.incidents.drsReason=='wet','wet track: DRS off')
 f.wet=0; f.rain=0; F.tick(e,f,20); assert(not e.weather.wet and not e.commands[1].drsBlock,'dry again: allowed')
 -- Neutralisation : coupé ; reprise : un tour mesuré du leader de plus.
 e.profiles.C.rulesDrsLaps=1; e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
 e.drsRule.travel[1]=5; F.place(f,4,1500,0); F.tick(e,f,18)
 assert(e.incidents.neutral and e.commands[2].drsBlock and e.incidents.drsReason=='flag','neutralised: DRS off')
 F.place(f,4,1500,100); while e.incidents.neutral do F.tick(e,f,1) end; F.tick(e,f,0.5)
 assert(not e.commands[2].drsBlock and e.incidents.drsReason=='','after a FCY: DRS at once (F1: a wait only after the start, a safety car or a red flag)')
 -- Reprise derrière la voiture de sécurité ou après un drapeau rouge : un tour mesuré du leader de plus.
 e.drsRule.restart=true; F.tick(e,f,0.5)
 assert(e.commands[2].drsBlock and e.incidents.drsReason=='laps','restart: one more lap before DRS')
 F.tick(e,f,80,true); assert(not e.commands[2].drsBlock,'one measured lap after the restart: allowed')
 -- Zone jaune propre à la voiture : coupé pour elle seulement.
 e.profiles.C.rulesDrsLaps=0; e.profiles.C.yellowEnabled=true; E.changed(e)
 F.place(f,4,1000,0); F.place(f,3,800,120); F.place(f,2,1500,120); F.place(f,1,1700,120); F.tick(e,f,4)
 assert(e.states[3].yellow and e.commands[3].drsBlock and not e.commands[2].drsBlock,'yellow zone of the car: DRS off for it only')
 -- Règles décochées, journée circuit, qualifications : jamais d'attente de tours.
 e.profiles.C.rulesDrs=false; E.changed(e); e.drsRule.restart=true; F.tick(e,f,0.5); assert(not e.commands[1].drsBlock and not e.commands[3].drsBlock,'rules off: never')
 local e2,f2=F.scene('J',3); for i=1,3 do f2.cars[i].drsPresent=true end; f2.wet=1; f2.rain=1; F.tick(e2,f2,20); assert(not e2.commands[1].drsBlock,'never on a track day')
 local e3,f3=F.scene('Q',3); for i=1,3 do f3.cars[i].drsPresent=true end; e3.drsRule.restart=true; F.tick(e3,f3,0.5); assert(not e3.commands[1].drsBlock,'qualifying: no lap rule')
 -- App chargée en pleine course : pas d'attente.
 local e5,f5=F.scene('C',3); for i=1,3 do f5.cars[i].drsPresent=true end; F.tick(e5,f5,0.5); assert(not e5.commands[1].drsBlock,'app loaded in a running race: no wait')
 -- Panneau : raison affichée en pastille avec un drapeau ; jamais « DRS disponible » quand il est coupé.
 local e4,f4=F.scene('C',3); f4.cars[1].drsPresent=true; f4.cars[1].drsAvailable=true; e4.drsRule.restart=true; F.tick(e4,f4,1)
 assert(e4.panel.kind~='drs' and e4.drs.beepId==0,'never shown available while the rules forbid it')
 local Panel=require('src/panel'); local panel=Panel.new(); local t=e4.incidents; t.greenUntil=e4.time+5
 Panel.update(panel,t,f4,e4.run,'C',e4.time); assert(panel.kind=='green' and panel.drsBlocked and panel.drsText==string.format(L.drsLapsLeft,1),'laps left shown with the green flag')
end
-- Piste glissante (bandes jaunes et rouges) au passage du sec à la pluie, quelques secondes ; jamais au lancement d'une
-- session déjà mouillée.
tests.SLIPPERY_FLAG=function()
 local L=require('src/lang')
 local e,f=F.scene('C',3); F.tick(e,f,0.5); assert(e.panel.kind=='none')
 f.wet=1; f.rain=0.5; F.tick(e,f,C.K.weatherConfirm+1)
 assert(e.weather.wet and e.panel.kind=='slippery' and e.panel.title==L.flagTitles.slippery and not e.panel.noPass,'dry to wet: slippery track flag')
 F.tick(e,f,C.K.slipperyShow+1); assert(e.panel.kind~='slippery','shown a few seconds only')
 local e2,f2=F.scene('C',3); f2.wet=1; f2.rain=1; e2.weather=require('src/weather').new(); F.tick(e2,f2,C.K.weatherConfirm+2)
 assert(e2.weather.wet and e2.panel.kind~='slippery','wet from the start: no slippery flag')
end
-- Drapeau bleu : écart en secondes de la voiture qui prend un tour (distance à sa vitesse).
tests.BLUE_GAP=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e)
 local player=F.place(f,1,10000+500,100); player.lap=2
 local fast=F.place(f,2,10000+420,150); fast.lap=3; fast.spline=(fast.z/f.length)%1
 F.place(f,3,10000+4000,100)
 player.spline=(player.z/f.length)%1; player.lapValid=true; fast.lapValid=true
 F.tick(e,f,0.5); assert(e.panel.kind=='blue','blue flag')
 local gap=(80-4.4)/(150/3.6)
 assert(e.panel.blueGap and math.abs(e.panel.blueGap-gap)<0.3,'gap of the lapping car in seconds: '..tostring(e.panel.blueGap))
end
-- Bips du temps delta : rien loin de zéro, de plus en plus rapprochés près de zéro, très rapides en négatif ; option.
tests.DELTA_BEEPS=function()
 local e,f=F.scene('C',3); e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
 F.place(f,3,6000,0); while not e.incidents.neutral do F.tick(e,f,0.5) end
 local function count(value,seconds)
  local before=e.deltaBeep.beepId
  for _=1,math.floor(seconds*60+0.5) do e.delta.course.delta=value; F.tick(e,f,1/60) end
  return e.deltaBeep.beepId-before
 end
 assert(count(2,3)==0,'far from zero: silent')
 local slow,fast,negative=count(0.8,3),count(0.1,3),count(-0.3,3)
 assert(slow>=2 and slow<=3 and fast>slow and negative>fast and negative>=15,'closer to zero: faster beeps ('..slow..', '..fast..', '..negative..')')
 e.profiles.C.deltaBeeps=false; E.changed(e); assert(count(-0.3,2)==0,'option off: silent')
end
-- Beta 1.2 : erreurs de pilotage des IA. Pilote faible, distrait, sous la pluie : erreur au prochain gros freinage
-- (blocage) ou à la réaccélération en virage (patinage) ; une seule par délai ; jamais sous drapeau ni juste après,
-- près du joueur, option ou onglet Personnalité décochés.
tests.MISTAKES=function()
 local Mistakes=require('src/mistakes')
 local function run(setup,seconds)
  local e,f=F.scene('C',3); local p=e.profiles.C
  p.mistakesEnabled=true; p.mistakeRate=6; p.levelPct=40; E.changed(e)
  F.place(f,2,3000,150); f.cars[2].brake=1; f.rain=1; e.startedAt=-1000
  if setup then setup(e,f) end
  local s=e.states[2]
  for _=1,math.floor((seconds or 120)*2) do s.lapseUntil=e.time+10; F.tick(e,f,0.5); if e.commands[2].mistakeId>0 then break end end
  return e,f
 end
 local e,f=run()
 local cmd=e.commands[2]
 assert(cmd.mistakeId==1 and cmd.mistakeKind=='brake' and cmd.mistakeTime>=C.K.mistakeBrakeMin and cmd.mistakeTime<=C.K.mistakeBrakeMax and cmd.mistakeCause=='inattention','weak, distracted, wet: brake lock at the next heavy braking')
 local found=false; for n=0,e.log.count-1 do local r=e.log[(e.log.head-n-1)%200+1]; if r.message:find('erreur de pilotage: blocage des roues au freinage',1,true) then found=true end end
 assert(found,'mistake written to the journal')
 local s=e.states[2]; for _=1,200 do s.lapseUntil=e.time+10; F.tick(e,f,0.5) end
 assert(cmd.mistakeId==1,'never twice within the cooldown')
 e=run(function(_,f2) f2.cars[2].brake=0; f2.cars[2].gas=1; f2.cars[2].yawRate=0.5 end)
 assert(e.commands[2].mistakeId==1 and e.commands[2].mistakeKind=='traction' and e.commands[2].mistakeSeverity==C.K.mistakeSeverity,'traction mistake out of a corner')
 assert(run(function(_,f2) F.place(f2,1,3020,150) end).commands[2].mistakeId==0,'never within 40 m of the player')
 assert(run(function(e2) e2.profiles.C.mistakesEnabled=false; E.changed(e2) end).commands[2].mistakeId==0,'option off: none')
 assert(run(function(e2) e2.profiles.C.section_human=false; E.changed(e2) end).commands[2].mistakeId==0,'Driving tab off: none')
 assert(run(function(e2) e2.mistakes.calmUntil=1e9 end).commands[2].mistakeId==0,'none in the minutes after a neutralisation')
 -- Neutralisation : aucune, ni pendant les minutes qui suivent.
 local e3,f3=F.scene('C',3); local p3=e3.run; p3.mistakesEnabled=true; p3.section_human=true; p3.mistakeRate=6
 e3.incidents.neutral=true; assert(Mistakes.update(e3.mistakes,e3,f3,p3,'C',e3.time)==nil and e3.mistakes.calmUntil>e3.time,'none under a flag')
 e3.incidents.neutral=false; assert(Mistakes.update(e3.mistakes,e3,f3,p3,'C',e3.time+C.K.mistakeCalm-1)==nil,'none shortly after a neutralisation')
end
-- DRS des IA : ouvert dans la zone (disponible), en ligne droite et hors freinage, refermé au freinage ; jamais quand
-- les règles le coupent ; ouvertures comptées au journal.
tests.AI_DRS=function()
 local J=require('src/journal')
 local e,f=F.scene('C',3); f.leaderLaps=5; local b=f.cars[2]; b.drsPresent=true; F.place(f,2,2000,250); F.tick(e,f,0.5)
 assert(e.commands[2].drsWant==nil,'outside a DRS zone: nothing')
 b.drsAvailable=true; F.tick(e,f,0.1); assert(e.commands[2].drsWant==true,'in the zone, on a straight: open')
 b.drsActive=true; F.tick(e,f,0.1); assert(e.commands[2].drsWant==nil,'already open: nothing')
 b.brake=1; F.tick(e,f,0.1); assert(e.commands[2].drsWant==false,'braking: closed')
 assert(J.summary(e):find('DRS des IA : ouvertures 1, dont demandees par l app 1',1,true),'openings counted in the journal')
 b.brake=0; b.drsActive=false; b.yawRate=1; F.tick(e,f,0.1); assert(e.commands[2].drsWant==nil,'in a corner: not opened')
 b.yawRate=0; e.drsRule.restart=true; F.tick(e,f,0.1); assert(e.commands[2].drsBlock and e.commands[2].drsWant==nil,'forbidden by the rules: never opened')
 e.profiles.C.rulesDrsLaps=0; e.profiles.C.aiDrs=false; E.changed(e); F.tick(e,f,0.1); assert(e.commands[2].drsWant==nil,'option off: nothing')
end
-- Zone jaune signalée depuis longtemps : un dépassement est sanctionné aussitôt, sans attente.
tests.PLAYER_PENALTY_PASS_LATE=function()
 local e,f=F.scene('C',3); F.place(f,3,5000,0); F.place(f,2,4850,60); F.place(f,1,4800,45); F.tick(e,f,3+C.K.passGiveBack)
 F.place(f,2,4850,40)
 for step=1,10 do F.place(f,1,4800+step*10,45); F.tick(e,f,0.1) end
 assert(e.penalties.count==1 and e.penalties.reason=='pass','pass long after the flag: immediate penalty')
end
-- Beta 1.3 : livrée de la voiture de sécurité. Parmi les voitures du modèle (grille tirée au sort), celle qui porte la
-- livrée « safety » est la voiture de sécurité ; sinon la première, à habiller.
tests.SAFETY_CAR_SKIN=function()
 local e,f=F.scene('Q',5); e.g.safetyCarModel='sc_car'; e.g.safetyCarPicked=true; E.changed(e)
 for i=3,5 do f.cars[i].id='sc_car'; f.cars[i].skinKnown=true end
 f.cars[3].skin='1white'; f.cars[4].skin='Safety_Car'; f.cars[4].skinSafety=true; f.cars[5].skin='2black'
 F.tick(e,f,1)
 assert(e.incidents.safety==4 and not e.commands[4].scSkin and e.commands[3].parkReason=='spare' and e.commands[5].parkReason=='spare','the one in the safety car livery is the safety car')
 f.cars[4].skinSafety=false; F.tick(e,f,0.5)
 assert(e.incidents.safety==3 and e.commands[3].scSkin and not e.commands[4].scSkin,'none in the livery: the first, to be dressed')
end
-- Beta 1.4 : dépassement fait dans les premières secondes d'une zone jaune, zone quittée avant l'échéance : la place
-- gardée est sanctionnée à l'échéance (l'attente survit à la fin du régime).
tests.PASS_PENDING_SURVIVES_ZONE_EXIT=function()
 local e,f=F.scene('C',3)
 local c3=F.place(f,3,5000,0); c3.offtrack=true
 F.place(f,1,1000,100); F.place(f,2,1100,100)
 F.tick(e,f,4); assert(e.incidents.cars[3].incident,'incident')
 local zp,za=4500,4650; local pending,exited=false,false
 for _=1,60*25 do
  zp=zp+220/3.6/60; za=za+80/3.6/60
  F.place(f,1,zp,220); F.place(f,2,za,80); F.tick(e,f,1/60)
  if e.penalties.giveBack==2 then pending=true end
  if pending and not e.incidents.playerNoPass then exited=true end
 end
 assert(pending and exited,'pass pending, then zone left before the deadline')
 assert(e.penalties.count==1 and e.penalties.reason=='pass','kept place sanctioned at the deadline')
end
-- Beta 1.4 : zone simple (incident hors piste) qui chevauche une zone double : delta de zone dès l'entrée dans la double.
tests.DELTA_ZONE_OVERLAP=function()
 local e,f=F.scene('C',4)
 local c3=F.place(f,3,5000,0); c3.offtrack=true; F.place(f,4,5200,0)
 F.place(f,1,1000,100); F.place(f,2,1500,100)
 F.tick(e,f,4)
 local zp=4500; local blind=0; local shown=false
 for _=1,60*20 do
  zp=zp+150/3.6/60; F.place(f,1,zp,150); F.tick(e,f,1/60)
  if e.incidents.playerInside and e.incidents.playerZoneDouble and e.delta.value==nil then blind=blind+1 end
  if e.delta.kind=='zone' then shown=true end
 end
 assert(blind==0 and shown,'delta measured in the double zone reached from the single one')
 assert(e.penalties.count>=1 and e.penalties.deltaKind=='zone','150 km/h through the double zone judged')
end
-- Beta 1.4 : place rendue entre IA (dynamique) : la voiture doublée n'est jamais en file derrière celle qui lui doit la
-- place ; elle repasse, sans spirale de ralentissement ni sanction.
tests.AI_GIVE_BACK_DYNAMIC=function()
 local e,f=F.scene('C',4); e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
 F.place(f,4,6000,0); F.place(f,2,1000,150); F.place(f,3,1010,150); F.place(f,1,9000,100)
 for i=2,3 do local s=e.states[i]; for b=1,#s.pace do s.pace[b]=400/3.6 end; s.paceCount=400 end
 for _=1,400 do F.tick(e,f,0.1); if e.incidents.neutral then break end end
 F.tick(e,f,0.2)
 F.place(f,2,1020,150); F.place(f,3,1000,140); e.states[2].nextPerception=0; e.states[3].nextPerception=0; F.tick(e,f,0.3)
 assert(e.penalties.ai.giveBack[2]==3,'car 2 owes car 3 its place')
 local z2,z3,v2,v3=f.cars[2].z,f.cars[3].z,150,140; local back=false; local slowest=math.huge
 for _=1,60*20 do
  local t2,t3=math.min(150,e.commands[2].yellowLimit),math.min(150,e.commands[3].yellowLimit)
  local function go(v,t) if t>v then return math.min(t,v+5*3.6/60) end return math.max(t,v-10*3.6/60) end
  v2=go(v2,t2); v3=go(v3,t3); z2=z2+v2/3.6/60; z3=z3+v3/3.6/60
  F.place(f,2,z2,v2); F.place(f,3,z3,v3); F.tick(e,f,1/60)
  if z3>z2+4.4 then back=true end
  slowest=math.min(slowest,v2,v3)
 end
 assert(back and slowest>100 and (e.penalties.ai.count[2] or 0)==0,'place given back without a slowdown spiral ('..slowest..' km/h)')
 -- IA bien plus rapide (+30 km/h) qui double le joueur 3 s après le déclenchement : elle lève le pied assez franchement
 -- pour rendre la place avant l'échéance (joueur à allure constante, IA qui obéit à sa limite).
 local e3,f3=F.scene('C',3); e3.profiles.C.neutralization='fcy'; e3.profiles.C.yellowEnabled=false; E.changed(e3)
 F.place(f3,3,6000,0); F.place(f3,1,1000,150); F.place(f3,2,990,150)
 for i=1,2 do local s=e3.states[i]; for b=1,#s.pace do s.pace[b]=400/3.6 end; s.paceCount=400 end
 for _=1,400 do F.tick(e3,f3,0.1); if e3.incidents.neutral then break end end
 F.tick(e3,f3,3)
 local p1,p2,v2=f3.cars[1].z,f3.cars[2].z-8,180; local passed,returned=false,false
 for _=1,60*25 do
  if passed then local lim=e3.commands[2].yellowLimit; if lim<v2 then v2=math.max(lim,v2-8*3.6/60) else v2=math.min(lim,180,v2+4*3.6/60) end end
  p1=p1+150/3.6/60; p2=p2+v2/3.6/60; F.place(f3,1,p1,150); F.place(f3,2,p2,v2,2.5); e3.states[2].nextPerception=0
  F.tick(e3,f3,1/60)
  if not passed and p2>p1+4.5 then passed=true end
  if passed and p1>p2+4.5 then returned=true end
 end
 assert(passed and returned and (e3.penalties.ai.count[2] or 0)==0 and e3.penalties.count==0,'+30 km/h: place given back in time, nobody sanctioned')
end
-- Beta 1.4 : reprendre la place qu'une IA rend n'est pas un dépassement (joueur comme IA) ; l'IA qui doit la place au
-- joueur ne reste pas en file derrière lui : le joueur peut la rendre à son tour.
tests.GIVE_BACK_NOT_A_PASS=function()
 for _,delay in ipairs({0.5,6.5,8}) do
  local e,f=F.scene('C',3); e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
  F.place(f,3,6000,0); F.place(f,1,1000,150); F.place(f,2,990,150)
  for i=1,2 do local s=e.states[i]; for b=1,#s.pace do s.pace[b]=400/3.6 end; s.paceCount=400 end
  for _=1,400 do F.tick(e,f,0.1); if e.incidents.neutral then break end end
  F.tick(e,f,delay)
  local z1,z2=f.cars[1].z,f.cars[2].z; local v2=180; local passed,back=false,false
  for _=1,60*20 do
   if passed and not back then v2=110 elseif back then v2=140 end
   z1=z1+150/3.6/60; z2=z2+v2/3.6/60; F.place(f,1,z1,150); F.place(f,2,z2,v2,2.5); e.states[2].nextPerception=0
   F.tick(e,f,1/60)
   if not passed and z2>z1+6 then passed=true end
   if passed and not back and z1>z2+6 then back=true; assert(e.penalties.waiting[2]==nil and e.penalties.giveBack==0,'retaking the place owes nothing') end
  end
  assert(back and e.penalties.count==0 and (e.penalties.ai.count[2] or 0)==0,'no penalty either way ('..delay..' s)')
 end
 -- Entre IA : l'IA 3 reprend sa place, elle ne la doit pas à son tour.
 local e,f=F.scene('C',4); e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
 F.place(f,4,6000,0); F.place(f,2,1000,150); F.place(f,3,1010,150); F.place(f,1,9000,100)
 for _=1,400 do F.tick(e,f,0.1); if e.incidents.neutral then break end end
 F.tick(e,f,0.2)
 F.place(f,2,1020,150); F.place(f,3,1000,150); e.states[2].nextPerception=0; e.states[3].nextPerception=0; F.tick(e,f,0.3)
 assert(e.penalties.ai.giveBack[2]==3)
 F.place(f,3,1040,150); e.states[2].nextPerception=0; e.states[3].nextPerception=0; F.tick(e,f,0.3)
 assert(e.penalties.ai.giveBack[2]==0 and e.penalties.ai.giveBack[3]==0,'nothing owed after the place is back')
 F.tick(e,f,C.K.passGiveBack+1)
 assert((e.penalties.ai.count[2] or 0)==0 and (e.penalties.ai.count[3] or 0)==0,'no sanction')
 -- Le joueur double pendant la transition puis se cale sous l'allure de l'IA : elle repasse (aucune file derrière lui).
 local e2,f2=F.scene('C',3); e2.profiles.C.neutralization='fcy'; e2.profiles.C.yellowEnabled=false; E.changed(e2)
 F.place(f2,3,6000,0); F.place(f2,1,990,150); F.place(f2,2,1000,150)
 for i=1,2 do local s=e2.states[i]; for b=1,#s.pace do s.pace[b]=400/3.6 end; s.paceCount=400 end
 for _=1,400 do F.tick(e2,f2,0.1); if e2.incidents.neutral then break end end
 F.tick(e2,f2,0.5)
 local p1,p2,w1,w2=f2.cars[1].z,f2.cars[2].z,170,150; local ahead,again=false,false
 for _=1,60*20 do
  local limit=math.min(150,e2.commands[2].yellowLimit)
  w2=limit>w2 and math.min(limit,w2+5*3.6/60) or math.max(limit,w2-10*3.6/60)
  if ahead then w1=math.max(0,w2-20) end
  p1=p1+w1/3.6/60; p2=p2+w2/3.6/60; F.place(f2,1,p1,w1); F.place(f2,2,p2,w2,2.5); e2.states[2].nextPerception=0
  F.tick(e2,f2,1/60)
  if not ahead and p1>p2+6 then ahead=true end
  if ahead and p2>p1+6 then again=true end
 end
 assert(ahead and again and e2.penalties.count==0,'the AI takes its place back, no penalty for the player')
end
-- Beta 1.4 : pénalité « reprise hors des stands » décidée dans l'image du drapeau vert : son message l'emporte.
tests.RED_PENALTY_MESSAGE=function()
 local e,f=F.scene('C',5); C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagHold=20; E.changed(e)
 F.block(f,{2,3,4},600); F.place(f,5,3000,120); F.place(f,1,5000,100)
 F.tick(e,f,C.K.redIncidentStill+1); assert(e.incidents.red,'red')
 for i=2,5 do local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0 end
 local seen=false
 for _=1,60*700 do F.tick(e,f,1/60); if e.incidents.messageKind=='penaltyRed' then seen=true end; if e.penalties.count>0 then break end end
 assert(e.penalties.reason=='red' and seen,'penalty message shown')
 -- Drapeau rouge annulé (règles décochées) : personne ne devait être dans la voie des stands.
 local e2,f2=F.scene('C',5); C.preset('Course','C',e2.profiles.C); E.changed(e2)
 F.block(f2,{2,3,4},600); F.place(f2,5,3000,120); F.place(f2,1,5000,100)
 F.tick(e2,f2,C.K.redIncidentStill+1); assert(e2.incidents.red,'red')
 e2.profiles.C.redFlagEnabled=false; E.changed(e2); F.tick(e2,f2,1)
 assert(not e2.incidents.red and e2.penalties.count==0 and not e2.penalties.redPending,'cancelled red: no penalty')
end
-- Beta 1.4 : place rendue : la pastille « vous avez doublé » repasse au vert ; panneau recalé avec le temps moteur.
tests.PASS_PILL_AND_PANEL_REBASE=function()
 local e,f=F.scene('C',3); e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
 F.place(f,3,6000,0); F.place(f,1,1000,150); F.place(f,2,1010,150)
 for _=1,400 do F.tick(e,f,0.1); if e.incidents.neutral then break end end
 F.tick(e,f,0.5)
 F.place(f,1,1030,150); e.states[2].nextPerception=0; F.tick(e,f,0.2)
 assert(e.penalties.passedUnder and e.penalties.waiting[2],'pending pass shown')
 F.place(f,1,990,140); F.tick(e,f,0.2)
 assert(not e.penalties.passedUnder and e.penalties.waiting[2]==nil,'place given back: pill green again')
 local changed=e.panel.changedAt; local at=e.panel.at
 E.rebase(e,1000)
 assert(e.panel.changedAt==changed-1000 and e.panel.at==at-1000,'panel times rebased')
end
-- Beta 1.4 : une IA qui sort de piste garde le régime de toute la piste (neutralisation) : sa place prise en
-- coupant est sanctionnée.
tests.AI_OFFTRACK_KEEPS_REGIME=function()
 local e,f=F.scene('C',4); e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
 F.place(f,4,6000,0); F.place(f,2,1000,120); F.place(f,3,1010,120); F.place(f,1,9000,100)
 for _=1,400 do F.tick(e,f,0.1); if e.incidents.neutral then break end end
 F.tick(e,f,C.K.passGiveBack+1)
 e.states[2].nextPerception=0; e.states[3].nextPerception=0; F.tick(e,f,0.3)
 f.cars[2].offtrack=true; F.tick(e,f,0.2)
 assert(e.penalties.ai.regime[2],'regime kept off track')
 F.place(f,2,1040,120); f.cars[2].offtrack=false; e.states[2].nextPerception=0; F.tick(e,f,0.3)
 assert((e.penalties.ai.count[2] or 0)==1,'pass made by cutting the track sanctioned')
end
-- Beta 1.4 : voiture de sécurité immobilisée en piste : ramenée à son stand, la neutralisation continue en FCY.
tests.SAFETY_CAR_STUCK=function()
 local e,f=F.scene('C',5); C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; E.changed(e)
 e.g.safetyCarModel='car_5'; F.place(f,5,0,0); f.cars[5].pit=true; f.cars[5].inPitBox=true
 F.place(f,4,6000,0); F.place(f,2,1000,120); F.place(f,1,2000,120)
 for _=1,600 do F.tick(e,f,0.1); if e.incidents.safetyPhase=='place' then break end end
 assert(e.incidents.neutral and e.incidents.neutralMode=='sc' and e.incidents.safetyPhase=='place','safety car released, to be placed')
 F.tick(e,f,0.1); f.cars[5].pit=false; f.cars[5].inPitBox=false; F.place(f,5,e.commands[5].place*f.length,0)
 F.tick(e,f,C.K.scStuckTime+1)
 assert(e.incidents.safetyPhase=='parked' and e.commands[5].scPark,'stuck safety car taken back to its pit')
 assert(e.incidents.neutral and e.incidents.neutralMode=='fcy','neutralisation continues as FCY')
end
-- Beta 1.4 : jamais d'erreur de pilotage dans la première minute de course, même sans l'onglet Départ.
tests.MISTAKE_START_WINDOW=function()
 local e,f=F.scene('C',3); local p=e.profiles.C
 p.mistakesEnabled=true; p.mistakeRate=6; p.levelPct=40; p.section_start=false; E.changed(e)
 F.place(f,2,3000,150); f.cars[2].brake=1; f.rain=1; e.startedAt=e.time
 local s=e.states[2]
 for _=1,100 do s.lapseUntil=e.time+10; F.tick(e,f,0.5) end
 assert(e.commands[2].mistakeId==0,'none in the first minute without the start tab')
 for _=1,240 do s.lapseUntil=e.time+10; F.tick(e,f,0.5); if e.commands[2].mistakeId>0 then break end end
 assert(e.commands[2].mistakeId==1,'possible afterwards')
end
-- Beta 1.4 : fin de VSC (F1) annoncée, drapeau vert quelques secondes plus tard ; un nouvel incident l'annule.
tests.VSC_ENDING=function()
 local e,f=F.scene('C',4); e.profiles.C.neutralization='vsc'; e.profiles.C.yellowEnabled=false; E.changed(e)
 F.place(f,4,6000,0); F.tick(e,f,18); assert(e.incidents.neutral and e.incidents.neutralMode=='vsc','VSC')
 F.place(f,4,6000,100)
 for _=1,600 do F.tick(e,f,0.1); if e.incidents.ending then break end end
 assert(e.incidents.neutral and e.incidents.ending and e.incidents.messageKind=='vscEnd','VSC ENDING announced, still neutralised')
 F.tick(e,f,0.3); assert(e.panel.kind=='vscEnd' and e.panel.noPass,'panel: end of VSC, no overtaking yet')
 F.tick(e,f,C.K.vscEnding-1); assert(e.incidents.neutral,'green only after the announced delay')
 F.tick(e,f,1.5); assert(not e.incidents.neutral and not e.incidents.ending and e.incidents.messageKind=='green','green')
 -- Nouvel incident majeur pendant la fin de VSC : la VSC continue.
 local e2,f2=F.scene('C',4); e2.profiles.C.neutralization='vsc'; e2.profiles.C.yellowEnabled=false; e2.profiles.C.majorIncidentTime=5; E.changed(e2)
 F.place(f2,4,6000,0); F.tick(e2,f2,8); F.place(f2,4,6000,100)
 for _=1,600 do F.tick(e2,f2,0.1); if e2.incidents.ending then break end end
 assert(e2.incidents.ending)
 F.place(f2,3,3000,0); F.tick(e2,f2,e2.run.majorIncidentTime+1.5)
 assert(e2.incidents.neutral and not e2.incidents.ending,'new incident: VSC goes on')
end
-- Beta 1.4 : après la voiture de sécurité, dépassement interdit jusqu'à la ligne, pour le joueur comme pour les IA.
tests.RESTART_UNTIL_LINE=function()
 local Incidents=require('src/incidents')
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e)
 F.place(f,1,9000,150); F.place(f,2,9010,150); F.place(f,3,5100,150)
 F.tick(e,f,0.5)
 local t=e.incidents; t.safetyPhase='parking'; t.greenUntil=e.time+5
 -- Reprise déclenchée comme à l'entrée de la voiture de sécurité dans la voie des stands.
 t.neutral=true; t.neutralMode='sc'; t.relaunch=true; t.neutralUntil=e.time; t.neutralSince=e.time
 F.tick(e,f,1/60)
 assert(not t.neutral and t.restart and t.playerRestart and t.cars[2].restart and t.cars[3].restart,'restart: every car on track until the line')
 F.tick(e,f,0.3); assert(e.panel.kind=='restart' and e.panel.noPass,'panel: green, no overtaking until the line')
 assert(e.states[3].yellow and e.commands[3].yellowLimit>=C.K.unlimitedSpeed,'AI: no overtaking, no speed limit')
 -- Le joueur double avant la ligne : sanction (le régime dure depuis plus de 10 s).
 e.penalties.regimeAt=e.time-20
 F.place(f,1,9020,150); F.tick(e,f,0.2)
 assert(e.penalties.count==1 and e.penalties.reason=='pass','pass before the line sanctioned')
 -- Ligne franchie : course libre.
 F.place(f,1,10000+50,150); F.place(f,2,10000+30,150); F.place(f,3,10000+20,150); F.tick(e,f,0.2)
 assert(not t.cars[1].restart and not t.cars[2].restart and not t.restart and not t.playerRestart,'line crossed: racing')
 assert(Incidents.cap(t,f,3,e.run,e.delta,e.states,0)==C.K.unlimitedSpeed)
end
-- Beta 1.4 : reprise après drapeau rouge derrière la voiture de sécurité : elle sort la première, les IA suivent dans
-- l'ordre du classement ; rentrée, vert et dépassement interdit jusqu'à la ligne.
tests.RED_FLAG_RELAUNCH_SC=function()
 -- Beta 1.48 : la voiture de sécurité est posée en piste (commande de position, jamais déplacée par le banc avant) :
 -- jonction des stands inconnue, devant la première voiture sortie ; connue, après elle, IA retenues jusqu'à la pose.
 local function scene(junction)
  local e,f=F.scene('C',6); C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagHold=20; e.g.safetyCarModel='car_6'; E.changed(e)
  F.place(f,6,0,0); f.cars[6].pit=true; f.cars[6].inPitBox=true
  F.block(f,{3,4,5},600); F.place(f,2,3000,120)
  for i=1,5 do f.cars[i].position=i end
  F.tick(e,f,C.K.redIncidentStill+1); local t=e.incidents; assert(t.red and t.safety==6)
  for i=2,5 do local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0; F.place(f,i,100+i*20,0); a.pit=true; a.inPitBox=true end
  f.cars[1].pit=true; F.place(f,1,100,0); f.cars[1].pit=true; f.cars[1].inPitBox=true
  if junction then e.merge.spline=junction/f.length end
  for _=1,200 do if not t.red then break end; F.tick(e,f,0.5) end
  return e,f,t
 end
 local e,f,t=scene(nil)
 assert(t.neutral and t.relaunch and t.neutralMode=='sc' and t.safetyPhase=='place' and e.commands[6].scPark,'safety car to be placed first, kept in its box until then')
 assert(e.commands[2].pitHold and e.commands[5].pitHold,'field held in the pit boxes')
 assert(e.commands[6].place==nil or e.commands[6].place<0,'junction unknown: no point before the first car is out')
 -- Joueur P1 : il sort le premier ; la voiture de sécurité est posée devant lui, une fois à K.scPlaceOnTrack m en piste.
 f.cars[1].pit=false; f.cars[1].inPitBox=false; F.place(f,1,500,60); F.tick(e,f,0.1)
 assert(e.commands[6].place==nil or e.commands[6].place<0,'just out: not yet')
 F.place(f,1,500+C.K.scPlaceOnTrack+1,60); F.tick(e,f,0.1)
 local at=e.commands[6].place
 assert(at and math.abs(at*f.length-(531+C.K.scPlaceFirstOut))<1e-6,'placed ahead of the first car out')
 f.cars[6].pit=false; f.cars[6].inPitBox=false; F.place(f,6,at*f.length,80); F.tick(e,f,0.1)
 assert(t.safetyPhase=='out' and t.neutral and t.relaunch,'on track for the relaunch lap')
 local L=require('src/lang'); F.tick(e,f,0.3)
 assert(t.restartState=='ok' and e.panel.restartPill==string.format(L.restart.pillFirst,L.restart.behindSc),'on track: P1 behind the safety car')
 -- Sortie dans l'ordre : chacune une fois la précédente partie de son emplacement et passée devant le sien.
 local released={}
 for _=1,40 do F.tick(e,f,0.25); if not e.commands[2].pitHold then break end end
 assert(not e.commands[2].pitHold and e.commands[3].pitHold,'car 2 first, car 3 after it')
 f.cars[2].inPitBox=false; released[1]=2; F.tick(e,f,C.K.redReleaseGap+0.5)
 assert(e.commands[3].pitHold,'car 2 out of its box but still upstream of the box of car 3: car 3 waits')
 F.place(f,2,f.cars[2].z+60,60); f.cars[2].pit=true
 for _=1,200 do
  F.tick(e,f,0.25)
  for i=2,5 do local a=f.cars[i]; if not e.commands[i].pitHold and a.inPitBox then a.inPitBox=false; released[#released+1]=i; F.place(f,i,a.z+60,60); a.pit=true end end
  if #released==4 then break end
 end
 assert(table.concat(released,',')=='2,3,4,5','pit exit in the frozen order')
 for i=2,5 do local a=f.cars[i]; a.pit=false; F.place(f,i,700+i*20,120) end
 for _=1,2000 do if t.safetyPhase=='in' then break end; F.tick(e,f,0.5) end
 assert(t.safetyPhase=='in','in this lap')
 f.cars[6].pit=true; F.tick(e,f,0.5)
 assert(not t.neutral and not t.relaunch and t.restart and t.messageKind=='restart','green behind the safety car, no overtaking until the line')
 -- Jonction connue : IA retenues jusqu'à la pose, K.scPlaceJunction m après la jonction.
 local e2,f2,t2=scene(400)
 f2.cars[1].inPitBox=false; F.place(f2,1,450,60); f2.cars[1].pit=true
 F.tick(e2,f2,C.K.redReleaseFirst+3*C.K.redReleaseGap)
 for i=2,5 do assert(e2.commands[i].pitHold,'held until the safety car is placed '..i) end
 assert(math.abs(e2.commands[6].place*f2.length-(400+C.K.scPlaceJunction))<1e-6,'after the pit exit junction')
 f2.cars[6].pit=false; f2.cars[6].inPitBox=false; F.place(f2,6,600,80); F.tick(e2,f2,0.5)
 assert(t2.safetyPhase=='out','placed')
 F.tick(e2,f2,0.5); assert(not e2.commands[2].pitHold,'then the first AI leaves')
 -- Joueur encore à son emplacement devant elle : l'IA suivante l'attend jusqu'à K.redExitWaitPlayer s.
 local e4,f4=scene(nil)
 F.tick(e4,f4,C.K.redReleaseFirst+C.K.redReleaseGap+C.K.redExitWait+1)
 assert(e4.commands[2].pitHold,'behind the player still in its box: waits beyond K.redExitWait s')
 F.tick(e4,f4,C.K.redExitWaitPlayer-C.K.redExitWait); assert(not e4.commands[2].pitHold,'at most K.redExitWaitPlayer s')
 -- Personne ne sort de la voie des stands (jonction inconnue, aucun point) : VSC ou FCY au plus tard après K.scExitMax s.
 local t4=e4.incidents; assert(t4.safetyPhase=='place','still to be placed')
 F.tick(e4,f4,C.K.scExitMax-C.K.redExitWaitPlayer-C.K.redReleaseFirst); assert(t4.safetyPhase=='parked' and t4.safetyFailed and t4.relaunch,'never a point: relaunch under VSC or FCY')
 -- Voiture de sécurité encore en piste au début de la relance : ramenée à son stand, jamais acceptée là où elle est.
 -- Point pas encore connu (jonction inconnue) : garée, ramenée à son stand si elle est en piste.
 local e6,f6,t6=scene(nil)
 f6.cars[6].pit=false; f6.cars[6].inPitBox=false; F.place(f6,6,5000,100); F.tick(e6,f6,0.5)
 assert(t6.safetyPhase=='place' and e6.commands[6].scPark,'on track, no point yet: not accepted, sent back to its box')
 -- Point connu : jamais renvoyée à son stand pendant la pose ; acceptée seulement à son point.
 local e5,f5,t5=scene(400)
 assert(t5.safetyPhase=='place')
 f5.cars[6].pit=false; f5.cars[6].inPitBox=false; F.place(f5,6,5000,100); F.tick(e5,f5,0.5)
 assert(t5.safetyPhase=='place' and not e5.commands[6].scPark and e5.commands[6].place>=0,'on track far from its point: not accepted, the position command brings it there')
 F.place(f5,6,600,80); f5.cars[6].pit=true; F.tick(e5,f5,0.1); assert(t5.safetyPhase=='place','in the pit lane beside its point: not on track')
 f5.cars[6].pit=false; F.tick(e5,f5,0.1); assert(t5.safetyPhase=='out','accepted at its point')
 -- Pose impossible : tour de relance sous VSC (F1) ou FCY dès K.scPlaceMax s.
 local e3,f3,t3=scene(400)
 f3.cars[1].inPitBox=false; F.place(f3,1,450,60); f3.cars[1].pit=true
 F.tick(e3,f3,C.K.scPlaceMax+0.5)
 assert(t3.relaunch and t3.neutral and t3.safetyPhase=='parked' and t3.safetyFailed and (t3.neutralMode=='fcy' or t3.neutralMode=='vsc'),'never placed: relaunch under VSC or FCY')
 F.tick(e3,f3,0.5); assert(not e3.commands[2].pitHold,'and the field released')
end
-- Beta 1.4 : stands fermés sous FCY (GT) : aucune IA appelée, un arrêt fait stands fermés ne compte pas ; WEC : aussi
-- pendant les premiers tours de voiture de sécurité.
tests.PITS_CLOSED=function()
 local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); local P=e.profiles
 C.applyRules('GT',P); P.C.pitsClosed='pitFcy'; P.C.pitWindowOpenPct=5; P.C.pitWindowClosePct=95; P.C.yellowEnabled=false; E.changed(e)
 f.sessionLaps=10; f.leaderLaps=5
 F.place(f,4,6000,0); F.tick(e,f,18)
 assert(e.incidents.neutral and e.incidents.pitsClosed,'FCY: pits closed')
 F.tick(e,f,0.3); assert(not e.commands[2].rulePit and not e.commands[3].rulePit,'nobody called in')
 local c=e.pits.cars[2]; local before=c.windowStops
 f.cars[2].pit=true; f.cars[2].inPitBox=true; F.tick(e,f,0.5)
 assert(c.windowStops==before,'stop made with the pits closed: not counted')
 f.cars[2].pit=false; f.cars[2].inPitBox=false
 F.place(f,4,6000,100); for _=1,600 do F.tick(e,f,0.1); if not e.incidents.neutral then break end end
 assert(not e.incidents.pitsClosed,'open again at the green flag')
 -- Endurance (WEC) : stands fermés pendant trois tours de voiture de sécurité, ouverts ensuite.
 local e2,f2=F.scene('C',4); f2.length=2000; C.applyRules('Endurance',e2.profiles); E.changed(e2)
 local t=e2.incidents; t.neutral=true; t.relaunch=true; t.neutralMode='sc'; t.neutralSince=e2.time; t.neutralUntil=e2.time+1e4; t.safetyPhase='out'
 F.tick(e2,f2,1); assert(t.pitsClosed,'WEC: closed in the first laps behind the safety car')
 t.neutralSince=e2.time-C.K.scClosedLaps*f2.length/(e2.run.safetyCarSpeedKmh/3.6)-1; F.tick(e2,f2,0.1)
 assert(not t.pitsClosed,'open after three laps')
end
-- Beta 1.4 : drapeau rouge : pneus changés et arrêt compté en F1 ; aucune intervention en GT. F1 : course mouillée, le
-- changement de composé n'est plus obligatoire.
tests.RED_FLAG_WORK_AND_WET_RACE=function()
 local function red(category)
  local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); C.applyRules(category,e.profiles); e.profiles.C.pitWindowOpenPct=5; E.changed(e)
  f.sessionLaps=10; f.leaderLaps=5
  local a=f.cars[2]; a.tyresKnown=true; a.compoundIndex=0; a.dryCompounds={[0]=true,[1]=true}
  F.tick(e,f,0.5); e.incidents.red=true; e.incidents.redSince=e.time; e.incidents.redMax=1e4
  a.pit=true; a.inPitBox=true; a.kmh=0; F.tick(e,f,0.5)
  return e
 end
 local f1=red('F1'); assert(f1.commands[2].pitCompound==1 and f1.pits.cars[2].windowStops==1,'F1: tyres changed under red, stop counted')
 local gt=red('GT'); assert(gt.commands[2].pitCompound==-1 and gt.pits.cars[2].windowStops==0,'GT: no work under red')
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); C.applyRules('F1',e.profiles); E.changed(e)
 f.sessionLaps=10; f.leaderLaps=5; F.tick(e,f,0.5); assert(e.pits.state=='open','window open in the dry')
 f.wet=1; f.rain=0.5; F.tick(e,f,C.K.weatherConfirm+2)
 assert(e.pits.wetRace and e.pits.state=='off' and e.incidents.playerPitDue==0,'wet race: two-compound rule waived')
 f.leaderLaps=10; F.tick(e,f,0.5); assert(not e.penalties.stopPending,'no penalty at the end')
end
-- Beta 1.4 : Slow Zone d'endurance : temps de référence à vitesse fixe dans une zone de double jaune.
tests.SLOW_ZONE=function()
 local Delta=require('src/delta'); local Incidents=require('src/incidents')
 local e,f=F.scene('C',3); C.applyRules('Endurance',e.profiles); E.changed(e)
 F.place(f,3,5000,0); F.place(f,2,4900,150); F.tick(e,f,4)
 for b=1,C.K.paceBins do e.states[2].pace[b]=250/3.6 end; e.states[2].paceCount=C.K.paceBins
 assert(math.abs(Delta.zoneReference(e.delta,e.states,2,1,false,e.run)-80/3.6)<1e-9,'reference at 80 km/h')
 local cap=Incidents.cap(e.incidents,f,2,e.run,e.delta,e.states,0)
 assert(math.abs(cap-80)<1e-6,'AI held to 80 km/h in the zone')
 e.profiles.C.slowZoneKmh=0; E.changed(e); F.tick(e,f,0.1)
 assert(math.abs(Delta.zoneReference(e.delta,e.states,2,1,false,e.run)-250/3.6/1.15)<1e-9,'otherwise the zone delta (+15 %)')
end
-- Beta 1.4 : profils et préréglages personnels enregistrés avant la Beta 1.4 : jeux de règles de la Beta 1.3 mis à jour,
-- règles personnalisées gardées (double jaune quitté de l'ancien défaut) ; préréglage des Beta 1.0 et 1.1 complété.
tests.MIGRATION_BETA_1_4=function()
 local Presets=require('src/presets')
 local old={F1={neutralization='vsc',mandatoryStops=1,pitWindowOpenPct=20,pitWindowClosePct=80,pitCompoundChange=true,overtakeMode=true},
  GT={neutralization='fcy',mandatoryStops=1,pitWindowOpenPct=30,pitWindowClosePct=70,minPitTime=50,bopEnabled=true,proAmEnabled=true},
  Endurance={neutralization='fcy',yellowSpeedKmh=80,maxStintMin=50,bopEnabled=true,proAmEnabled=true,predictableSlowClass=true}}
 for name,values in pairs(old) do
  local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.preset(C.recommended[x],x,{}); profiles[x].zoneDeltaPct=70 end
  for _,x in ipairs(C.ruleProfiles) do for k,v in pairs(values) do profiles[x][k]=v end end
  local g=C.validateGlobals(C.globalDefaults); g.dataRevision=2
  local upgraded=C.migrate(g,profiles)
  local listed=0; for _,u in ipairs(upgraded) do if not u:find(':delta$') then listed=listed+1 end end
  assert(g.dataRevision==C.dataRevision and listed==3,name)
  for _,x in ipairs(C.ruleProfiles) do assert(C.ruleCategory(x,profiles[x])==name,name..' '..x) end
  assert(profiles.J.zoneDeltaPct==15,'track day: old default left')
 end
 -- Règles personnalisées : seules les valeurs encore à l'ancien défaut changent.
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.preset(C.recommended[x],x,{}) end
 profiles.C.zoneDeltaPct=70; profiles.C.fcySpeedKmh=90; profiles.Q.zoneDeltaPct=40
 local g=C.validateGlobals(C.globalDefaults); g.dataRevision=2; C.migrate(g,profiles)
 assert(profiles.C.zoneDeltaPct==15 and profiles.C.fcySpeedKmh==90 and profiles.Q.zoneDeltaPct==40,'custom rules kept')
 -- Préréglage personnel des Beta 1.0 et 1.1 (révision 3, sans les clés de la Beta 1.2) : défaut du profil Course.
 local store=Presets.layout(); store.name='Ancien'; store.profile='C'; store.revision=3
 for k,v in pairs(C.preset('Course','C',{})) do if k~='rulesDrs' and k~='mistakesEnabled' and k~='zoneDeltaPct' then store['p_'..k]=v end end
 store.p_rulesDrs=false; store.p_mistakesEnabled=false; store.p_zoneDeltaPct=15
 local entry=Presets.decode(store)
 assert(entry.p.rulesDrs and entry.p.mistakesEnabled,'Beta 1.2 keys back to the race defaults')
 -- Préréglage de la Beta 1.3 aux règles F1 : règles F1 2025 de la Beta 1.4.
 local store2=Presets.layout(); store2.name='F1'; store2.profile='C'; store2.revision=3
 for k,v in pairs(C.preset('Course','C',{})) do store2['p_'..k]=v end
 store2.p_zoneDeltaPct=70; for k,v in pairs(old.F1) do store2['p_'..k]=v end
 local entry2=Presets.decode(store2)
 assert(C.ruleCategory('C',entry2.p)=='F1' and not entry2.p.overtakeMode and entry2.p.zoneDeltaPct==15,'F1 1.3 preset becomes F1 2025')
end
-- Beta 1.4 : drapeau jaune natif d'AC montré au joueur : son DRS est coupé par les règles, comme en zone jaune.
tests.NATIVE_YELLOW_DRS=function()
 local e,f=F.scene('C',3); for i=1,3 do f.cars[i].drsPresent=true end
 e.profiles.C.rulesDrsLaps=0; E.changed(e); F.tick(e,f,0.5)
 assert(not e.commands[1].drsBlock)
 f.flag=C.K.flagCaution; f.flagOwned=false; F.tick(e,f,0.2)
 assert(e.commands[1].drsBlock and not e.commands[2].drsBlock,'player DRS off under the native yellow flag')
 f.flagOwned=true; F.tick(e,f,0.2); assert(not e.commands[1].drsBlock,'never for the flag the app sets itself')
end
-- Beta 1.4 : annonce du DRS retenue seulement si elle est affichée (un message plus important de la même image
-- l'emporte), sinon retentée à l'image suivante.
tests.DRS_MESSAGE_RETRIED=function()
 local e,f=F.scene('C',3); f.cars[1].drsPresent=true
 e.drsRule.announced=''; e.drsRule.restart=true
 -- Message plus important dans l'image du changement.
 local t=e.incidents; t.messageFrame=(t.frameId+1)%C.K.counterMax; t.messagePriority=9; t.messageKind='red'
 F.tick(e,f,1/60)
 assert(t.messageKind=='red' and e.drsRule.announced=='','DRS message not shown: not marked as announced')
 F.tick(e,f,1/60)
 assert(t.messageKind=='drsLaps' and e.drsRule.announced=='laps','shown on the next frame')
end
-- Beta 1.4 (couverture) : temps delta en marche arrière, appel de la voiture de sécurité plafonné pour le joueur, delta
-- de zone relancé après une pénalité.
tests.DELTA_REVERSE_SC_CALL_ZONE_PENALTY=function()
 local Delta=require('src/delta')
 local e,f=F.scene('C',3); local p=e.run
 local inc={cars=e.incidents.cars,red=false,neutral=true,neutralMode='fcy',safetyPhase='none',safety=0,playerZone=false,playerInside=false,playerZoneSlot=0,playerZoneDouble=false,zoneCount=0,zones={}}
 local d=Delta.new(); local now=0; local z=1000
 local function step(kmh,seconds) for _=1,math.floor(seconds*60+0.5) do now=now+1/60; z=z+kmh/3.6/60; F.place(f,1,z,math.abs(kmh)); Delta.update(d,f,p,inc,e.states,now,1/60,false) end end
 step(80,0.1); local before=d.value
 step(-10,1); assert(d.value>before+0.9,'reversing: time passes without progress, delta grows')
 -- Voiture de sécurité appelée : jamais plus vite qu'elle moins la marge, même si l'allure connue est bien plus haute.
 local s=e.states[1]; for b=1,#s.pace do s.pace[b]=400/3.6 end; s.paceCount=400
 inc.neutralMode='sc'; inc.safetyPhase='call'; inc.safety=3
 local d2=Delta.new(); now=0; z=1000
 for _=1,60*30 do now=now+1/60; z=z+(p.safetyCarSpeedKmh-C.K.scMergeMargin+15)/3.6/60; F.place(f,1,z,p.safetyCarSpeedKmh-C.K.scMergeMargin+15); Delta.update(d2,f,p,inc,e.states,now,1/60,false); if d2.infraction then break end end
 assert(d2.kind=='scCall' and d2.infraction,'safety car called: reference capped below its speed')
 -- Pénalité de zone : le delta de zone repart à +1 s.
 local d3=Delta.new(); d3.zone.on=true; d3.zone.delta=-2; Delta.penalized(d3)
 assert(d3.zone.delta==C.K.deltaStart,'zone delta: fresh start after a penalty')
end
-- Beta 1.4 (couverture) : tous les instants des règles recalés au rebouclage du temps du moteur.
tests.REBASE_RULE_TIMERS=function()
 local e,f=F.scene('C',3); F.tick(e,f,0.5)
 local d,t,inc=e.delta,e.penalties,e.incidents; local now=e.time
 d.onsetAt=now-3; d.signalAt=now-4
 t.regimeAt=now-5; t.waiting[2]=now+6; t.ai.waiting[2]={[3]=now+7}
 inc.slipperyUntil=now+8; inc.endingUntil=now+9; inc.restartSince=now-10; inc.releaseAt[2]=now+11
 E.rebase(e,1000)
 assert(d.onsetAt==now-3-1000 and d.signalAt==now-4-1000,'delta timers')
 assert(t.regimeAt==now-5-1000 and t.waiting[2]==now+6-1000 and t.ai.waiting[2][3]==now+7-1000,'penalty timers')
 assert(inc.slipperyUntil==now+8-1000 and inc.endingUntil==now+9-1000 and inc.restartSince==now-10-1000 and inc.releaseAt[2]==now+11-1000,'incident timers')
end
-- Beta 1.4 (couverture) : app vue au départ d'une course (moins d'une minute de session) : l'attente du DRS s'applique ;
-- file derrière la voiture de sécurité : delta figé, seul à l'écart il est jugé.
tests.DRS_LATE_LOAD_AND_SC_QUEUE=function()
 local e,f=F.scene('C',3); for i=1,3 do f.cars[i].drsPresent=true end
 e.drsRule={restart=false,started=false,seen=false,travel={},last={},leader=0,reason=''}; f.time=30; F.tick(e,f,0.5)
 assert(e.commands[1].drsBlock and e.incidents.drsReason=='laps','seen 30 s into the race: the lap rule applies')
 local function queue(gap)
  local e2,f2=F.scene('C',5); e2.profiles.C.neutralization='sc'; e2.g.safetyCarModel='sc_car'; e2.profiles.C.yellowEnabled=false; E.changed(e2)
  f2.cars[5].id='sc_car'; F.place(f2,5,7000,0); f2.cars[5].pit=true; f2.cars[5].inPitBox=true
  F.place(f2,4,5000,0); F.place(f2,1,0,80); F.place(f2,2,gap+4.4,80); f2.cars[3].pit=true
  for _=1,600 do F.tick(e2,f2,0.1); if e2.incidents.safetyPhase=='place' then break end end
  assert(e2.incidents.safetyPhase=='place')
  F.tick(e2,f2,0.1); f2.cars[5].pit=false; f2.cars[5].inPitBox=false; F.place(f2,5,e2.commands[5].place*f2.length,100); F.tick(e2,f2,0.1)
  assert(e2.incidents.safetyPhase=='out')
  F.place(f2,5,3000,100); F.tick(e2,f2,20)
  for _=1,60*20 do
   F.place(f2,1,f2.cars[1].z+250/3.6/60,250); F.place(f2,2,f2.cars[1].z+gap+4.4,250); e2.states[1].nextPerception=0
   F.tick(e2,f2,1/60); if e2.penalties.count>0 then break end
  end
  return e2
 end
 assert(queue(20).penalties.count==0,'in the queue behind the safety car: never judged')
 assert(queue(300).penalties.count==1,'alone, far from the queue: judged')
end
-- Beta 1.4 (couverture) : une place prise juste avant la fin de la transition se rend dans au moins 5 s ; une attente
-- d'IA survit à la fin de la neutralisation et la place gardée est sanctionnée.
tests.GIVE_BACK_DELAY_AND_PENDING_END=function()
 local e,f=F.scene('C',4); e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; e.profiles.C.neutralizationHold=10; E.changed(e)
 F.place(f,4,6000,0); F.place(f,2,1000,150); F.place(f,3,1010,150); F.place(f,1,9000,100)
 for _=1,400 do F.tick(e,f,0.1); if e.incidents.neutral then break end end
 local onset=e.penalties.wholeAt
 F.place(f,4,6000,100)
 F.tick(e,f,7.5-(e.time-onset))
 F.place(f,2,1020,150); F.place(f,3,1000,150); e.states[2].nextPerception=0; e.states[3].nextPerception=0; F.tick(e,f,0.3)
 local due=e.penalties.ai.waiting[2][3]
 assert(due and due>=e.time-0.3+C.K.giveBackMin-0.05,'at least 5 s to give the place back')
 for _=1,60*12 do F.place(f,2,1020,150); F.place(f,3,1000,150); F.tick(e,f,1/60) end
 assert(not e.incidents.neutral,'neutralisation over before the deadline')
 assert((e.penalties.ai.count[2] or 0)==1,'place kept: sanctioned at the deadline even after the green flag')
end
-- Beta 1.5 : départ d'une grille placée avant la ligne. lapCount compte les tours terminés : franchir la ligne au départ
-- n'en termine aucun, et une voiture encore avant la ligne paraissait avoir un tour d'avance sur celle qui venait de la
-- franchir (drapeau bleu du joueur, cession et appel des IA). Aucun tour pris avant que le doubleur en ait terminé un.
tests.START_LINE_NO_FALSE_LAP=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e)
 local player=F.place(f,1,20000+5,100); local fast=F.place(f,2,20000-80,150); F.place(f,3,24000,100)
 player.lap=0; fast.lap=0
 F.tick(e,f,0.5); assert(e.panel.kind~='blue','no blue flag at the start from a car still behind the line')
 player.lap=1; fast.lap=1
 F.tick(e,f,0.5); assert(e.panel.kind=='blue','one lap later, same places: the car behind is a lap ahead')
 F.place(f,1,25000,100); F.place(f,2,24920,150); player.lap=0; fast.lap=1
 F.tick(e,f,0.5); assert(e.panel.kind=='blue','first lapping: the leader has completed one lap, the player none')
 -- IA qui vient de franchir la ligne, IA plus rapide encore avant : aucune cession au départ.
 local e2,f2=F.scene('C'); e2.p.personalLineJitter=0; e2.p.laneBiasEnabled=false; E.changed(e2)
 F.rear(e2,f2,50,35); f2.cars[2].lap=0; f2.cars[3].lap=0
 F.tick(e2,f2,4); assert(not F.yielding(e2.states[2].state),'no AI yield at the start: '..e2.states[2].state)
 f2.cars[3].lap=1; e2.states[2].nextPerception=0
 F.tick(e2,f2,4); assert(F.yielding(e2.states[2].state),'AI yields once the car behind has completed a lap more')
 -- Joueur encore avant la ligne derrière une IA qui vient de la franchir : l'IA n'est pas prise d'un tour par lui.
 local e3,f3=F.scene('C',3); E.changed(e3)
 local me=F.place(f3,1,20000-60,150); local ai=F.place(f3,2,20000+5,100); F.place(f3,3,24000,100)
 me.lap=0; ai.lap=0; e3.states[2].nextPerception=0
 F.tick(e3,f3,0.5); assert(not e3.states[2].lappedByPlayer,'AI not lapped by a player still behind the line')
 me.lap=1; e3.states[2].nextPerception=0
 F.tick(e3,f3,0.5); assert(e3.states[2].lappedByPlayer,'AI lapped once the player has completed a lap more')
end
-- Beta 1.5 : voiture de sécurité libérée mais encore dans la voie des stands au bout du temps minimal : elle ne rentrait
-- pas, le vert tombait aussitôt en pleine piste (relevé en course à Spa). « Rentre ce tour » seulement une fois en piste,
-- vert à son entrée dans la voie des stands ; toujours dedans au-delà du délai, la neutralisation finit en FCY.
tests.SAFETY_CAR_PIT_EXIT=function()
 -- Beta 1.48 : la voiture de sécurité ne sortait jamais seule de son emplacement : posée en piste (commande de position)
 -- ; jamais posée : neutralisation en FCY après K.scPlaceMax s, notée au journal.

 local function deploy(e,f)
  F.place(f,4,6000,0)
  for _=1,900 do F.tick(e,f,0.1); if e.incidents.safetyPhase=='place' then break end end
  assert(e.incidents.neutral and e.incidents.safetyPhase=='place','safety car released, to be placed')
  F.place(f,4,6000,150)
 end
 local function scene()
  local e,f=F.scene('C',5); C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; E.changed(e)
  e.g.safetyCarModel='car_5'; F.place(f,5,0,0); f.cars[5].pit=true; f.cars[5].inPitBox=true
  F.place(f,2,1000,120); F.place(f,1,2000,120); f.cars[2].position=1; f.cars[1].position=2
  deploy(e,f)
  return e,f
 end
 local e,f=scene(); local t=e.incidents
 -- Devant le meneur (voiture 2, 1000 m), K.scPlaceLeader m plus loin.
 assert(math.abs(e.commands[5].place*f.length-(1000+C.K.scPlaceLeader))<1e-6,'placed ahead of the leader')
 F.tick(e,f,C.K.scPlaceMax-1)
 assert(t.neutral and t.safetyPhase=='place' and not t.restart and e.commands[5].place>=0,'not on track yet: no in-lap, no green')
 local function logged(x,text) for n=0,x.log.count-1 do local row=x.log[(x.log.head-n-1)%x.log.limit+1]; if row.message:find(text,1,true) then return true end end return false end
 F.place(f,5,1000+C.K.scPlaceLeader,80); f.cars[5].pit=false; f.cars[5].inPitBox=false; F.tick(e,f,0.5)
 assert(t.safetyPhase=='out' and t.safetyLeft and logged(e,'voiture de securite: posee en piste a 1200 m, 200 m devant Driver_2 (meneur)'),'on track, logged')
 assert(e.commands[5].scSpeed==C.K.scLeadKmh,'Beta 1.48: slow while the field is far behind')
 F.place(f,2,1150,120); F.tick(e,f,0.5); assert(e.commands[5].scSpeed==e.run.safetyCarSpeedKmh,'its pace once the field is close')
 F.tick(e,f,C.K.scMinOut+5)
 assert(t.safetyPhase=='in' and t.neutral,'on track: in this lap')
 -- Ligne franchie sans rentrer : drapeau vert, rappel à son stand.
 F.place(f,5,f.length-50,120); F.tick(e,f,0.1); F.place(f,5,f.length+20,120); F.tick(e,f,0.1)
 assert(not t.neutral and t.restart and t.safetyPhase=='parked' and e.commands[5].scPark,'line crossed without pitting: green, sent back to its box')
 -- Seconde intervention : délai de pose reparti de zéro.
 F.place(f,5,0,0); f.cars[5].pit=true; f.cars[5].inPitBox=true; F.tick(e,f,1)
 deploy(e,f); F.tick(e,f,1)
 assert(t.safetyPhase=='place' and e.commands[5].place>=0,'second deployment: to be placed again')
 -- Jamais posée : FCY.
 local e2,f2=scene(); local t2=e2.incidents
 F.tick(e2,f2,C.K.scPlaceMax+0.5)
 assert(t2.safetyPhase=='parked' and e2.commands[5].scPark and t2.safetyFailed and t2.neutral and t2.neutralMode=='fcy','never placed: FCY, kept in its box')
 assert(logged(e2,'pose en piste impossible'),'logged')
 -- Point occupé : le suivant libre plus loin.
 local e3,f3=F.scene('C',5); C.preset('Course','C',e3.profiles.C); e3.profiles.C.neutralization='sc'; E.changed(e3)
 e3.g.safetyCarModel='car_5'; F.place(f3,5,0,0); f3.cars[5].pit=true; f3.cars[5].inPitBox=true
 F.place(f3,2,1000,120); F.place(f3,1,1230,120); f3.cars[2].position=1; f3.cars[1].position=2
 deploy(e3,f3)
 local at=e3.commands[5].place*f3.length
 assert(at>=1230+C.K.scPlaceFree and math.abs((at-1200)%C.K.scPlaceStep)<1e-6,'occupied point: next free one')
 for j=1,4 do F.place(f3,j,at,100) end; F.tick(e3,f3,0.1); assert(e3.commands[5].place~=at/f3.length,'never placed on a car')
end
-- Beta 1.6 : IA accidentée : une glissade relevée pendant sa retenue appartient au même accident ; libérée, elle n'est
-- pas retenue une seconde fois (journal réel : « repart apres 3.2 s » puis aussitôt « arretee 5.0 s »).
tests.INCIDENT_HOLD_ONCE=function()
 local e,f=F.scene('J',3); e.profiles.J.incidentStopMin=3; e.profiles.J.incidentStopMax=3; E.changed(e)
 F.place(f,2,0,150); F.place(f,3,5000,100)
 F.tick(e,f,0.5); f.cars[2].collided=true; f.cars[2].offtrack=true; f.cars[2].kmh=8; f.cars[2].speed=8/3.6; F.tick(e,f,0.5); f.cars[2].collided=false
 local c=e.incidents.cars[2]; local t=e.incidents
 assert(c.holding and t.held==1,'crashed AI held')
 f.cars[2].kmh=40; f.cars[2].speed=40/3.6; F.tick(e,f,0.4)
 f.cars[2].collided=true; f.cars[2].kmh=0; f.cars[2].speed=0; F.tick(e,f,0.4); f.cars[2].collided=false
 assert(c.holding,'still held during the slide')
 F.tick(e,f,c.holdUntil-e.time+1)
 assert(not c.holding and t.held==1,'released once, never held again for the same accident')
end
-- Beta 1.6 : avertissement du plafond anti-zigzag : changements retenus (état, côté visé, âge), puis le refusé.
tests.DIRECTION_LIMIT_DIAGNOSTIC=function()
 local D=require('src/director'); local e,f=F.scene('J',3); local s=e.states[2]; local a=f.cars[2]; local row=e.perception.rows[2]
 s.state='YIELD_IN'; row.left=false; row.right=false
 local now=100; local text=nil
 for n=1,8 do
  for _=1,120 do
   now=now+1/60; D.lateral(s,(n%2==0 and 1 or -1)*0.6,row,a,e.run,e.runtimeG,1/60,now)
   if s.newDirectionLimit and not text then text=D.limitText(s,now) end
  end
 end
 assert(text and text:find('^direction_limit: YIELD_IN>%-1 %-%d+s'),'oldest change first: '..tostring(text))
 local _,count=text:gsub('YIELD_IN>[%+%-]%d',''); assert(count==C.K.directionLimit+1,'six changes kept, then the refused one: '..text)
 assert(text:find('; refuse YIELD_IN>[%+%-]1 %(voulu [%+%-]0%.60%)$'),'refused change: '..text)
 -- Diagnostic : cible voulue avant la borne de largeur.
 assert(text:find('YIELD_IN>%-1 %-%d+s %(voulu %-0%.60%)') and text:find('YIELD_IN>%+1 %-%d+s %(voulu %+0%.60%)'),'wanted target noted: '..text)
 -- Borne de largeur effondrée (trajectoire le long d'un bord) et cible figée sur le décalage du moment : notées.
 local s3=e.states[3]; local a3=f.cars[3]; s3.state='YIELD_HOLD'; s3.offset=-0.5; s3.filtered=-0.5; s3.direction=-1
 -- Beta 1.29 : la borne effondrée n'est plus un changement de côté (côté visé compté) : rien n'est noté.
 local h=s3.directionHead
 a3.leftWidth=0.95; a3.rightWidth=11; D.lateral(s3,s3.offset,row,a3,e.run,e.runtimeG,1/60,now+60)
 assert(s3.directionHead==h and s3.direction==-1 and not s3.newDirectionLimit,'collapse of the width bound is not a change of side')
 -- Beta 1.41 : cible figée sur le décalage du moment (bornée par la largeur) : jamais notée, le côté gardé reste celui
 -- de la dernière vraie manœuvre (avant : notée et marquée figée, un changement de plus).
 s3.direction=0; s3.offset=-0.5; s3.filtered=-0.5; s3.velocity=0; s3.lastDirectionAt=-math.huge; for j=1,C.K.directionLimit do s3.directions[j]=-math.huge end
 local h3=s3.directionHead
 D.lateral(s3,s3.offset,row,a3,e.run,e.runtimeG,1/60,now+120)
 assert(s3.directionHead==h3 and s3.direction==0,'frozen target never noted')
 -- Vraie manœuvre bornée par la largeur (bord proche) : notée avec la cible voulue, avant la borne.
 s3.offset=0; s3.filtered=0; s3.velocity=0; s3.lastDirectionAt=-math.huge; a3.leftWidth=2.6
 local bound=D.reachable(s3,a3,e.run,e.runtimeG,-0.6)
 assert(bound>-0.55 and bound<-0.06,'width bound partial: '..bound)
 D.lateral(s3,-0.6,row,a3,e.run,e.runtimeG,1/60,now+180)
 assert(s3.directionHead~=h3 and s3.directionSides[s3.directionHead]==-1 and s3.directionIntended[s3.directionHead]==-0.6,'wanted target noted, not the bound')
 -- Moteur : la ligne du journal porte le détail.
 local e2,f2=F.scene('J',3); local s2=e2.states[2]
 for j=1,C.K.directionLimit do s2.directions[j]=e2.time-j; s2.directionStates[j]='OVT_IN'; s2.directionSides[j]=j%2==0 and 1 or -1 end
 s2.directionHead=1; s2.newDirectionLimit=true; s2.limitState='YIELD_IN'; s2.limitSide=1
 F.tick(e2,f2,1/60)
 local found=false
 for n=0,e2.log.count-1 do local r=e2.log[(e2.log.head-n-1)%200+1]; if r.level=='WARN' and r.message:find('^direction_limit: OVT_IN') and r.message:find('; refuse YIELD_IN>%+1$') then found=true end end
 assert(found,'journal line detailed')
end
-- Beta 1.6 : départ (PDR R01, « prudence ↑ » pendant l'attente) : prudence et agressivité de départ dès la grille et
-- jusqu'au premier virage, puis détente ; onglet Départ décoché : aucun effet, aucune valeur invalide.
tests.START_MODULATORS_FROM_GRID=function()
 local preset=C.defaults('C'); C.preset('Course','C',preset)
 local delay,relax=preset.startDelay,preset.startRelax
 -- Beta 1.25 : à fond en ligne droite ; la prudence et l'agressivité de départ ne viennent qu'au freinage (premier virage).
 local function run(mult,section,seconds,straight,grid)
  local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); local p=e.profiles.C
  if grid then f.started=false end
  if not mult then p.startCautionMult=1; p.startAggrMult=1 end
  p.section_start=section; E.changed(e); e.startedAt=e.time
  if not straight then f.cars[2].brake=1 end
  F.tick(e,f,seconds)
  return e.commands[2].caution,e.commands[2].aggression
 end
 local function ratios(section,seconds,straight,grid)
  local c1,a1=run(true,section,seconds,straight,grid); local c0,a0=run(false,section,seconds,straight,grid)
  assert(c1==c1 and a1==a1,'finite commands'); return c1/c0,a1/a0
 end
 -- Sur la grille, avant le feu vert : prudence et agressivité de départ déjà en place (attente d'une seconde depuis la
 -- Beta 1.27 : la grille est le seul moment qui les distingue d'une application après l'attente).
 local c,a=ratios(true,3,true,true)
 assert(math.abs(c-preset.startCautionMult)<0.02 and math.abs(a-preset.startAggrMult)<0.02,'grid: start caution and aggression ('..c..', '..a..')')
 c,a=ratios(true,3,true)
 assert(math.abs(c-1)<0.01 and math.abs(a-1)<0.01,'launch straight: flat out, no start caution ('..c..', '..a..')')
 c,a=ratios(true,3)
 assert(math.abs(c-preset.startCautionMult)<0.02 and math.abs(a-preset.startAggrMult)<0.02,'first corner: start caution and aggression ('..c..', '..a..')')
 c,a=ratios(true,delay+relax/2)
 assert(math.abs(c-(1+preset.startCautionMult)/2)<0.03 and math.abs(a-(1+preset.startAggrMult)/2)<0.03,'half relaxed ('..c..', '..a..')')
 c,a=ratios(true,delay+relax+2)
 assert(math.abs(c-1)<0.01 and math.abs(a-1)<0.01,'back to normal')
 c,a=ratios(false,3)
 assert(math.abs(c-1)<1e-9 and math.abs(a-1)<1e-9,'start tab unticked: no effect')
end
-- Beta 1.6 : première installation comme « Règles de base » (Essais, Qualifications, Course : préréglage recommandé
-- et règles de base ; Journée circuit sans commande) ; une installation existante n'est jamais modifiée.
tests.MIGRATION_FIRST_INSTALL=function()
 local function fresh() local profiles={}; for _,profile in ipairs(C.profiles) do profiles[profile]=C.defaults(profile) end; return profiles end
 local g=C.validateGlobals(C.globalDefaults); local profiles=fresh()
 local upgraded,first=C.migrate(g,profiles)
 assert(first and #upgraded==0 and g.dataRevision==C.dataRevision,'first install detected')
 assert(not C.anySection(profiles.J) and not profiles.J.configured,'track day untouched')
 for _,profile in ipairs(C.ruleProfiles) do
  local p=profiles[profile]
  assert(p.configured and C.on(p,'rules') and C.on(p,'accidents') and C.ruleCategory(profile,p)=='base',profile)
 end
 -- Installation existante jamais réglée, ou préréglage déjà utilisé : rien ne change.
 for _,setup in ipairs({{revision=3,used=false},{revision=0,used=true}}) do
  local g2=C.validateGlobals(C.globalDefaults); g2.dataRevision=setup.revision; g2.presetsUsed=setup.used; local p2=fresh()
  local _,first2=C.migrate(g2,p2)
  assert(not first2 and g2.dataRevision==C.dataRevision,'not a first install')
  for _,profile in ipairs(C.profiles) do assert(not C.sectionsChanged(profile,p2[profile]) and not p2[profile].configured,profile) end
 end
 -- Révision 3 : la migration des jeux de règles ne se rejoue pas (réglage du pilote conservé).
 local g3=C.validateGlobals(C.globalDefaults); g3.dataRevision=3; local p3=fresh(); C.applyRules('base',p3); p3.C.zoneDeltaPct=70
 C.migrate(g3,p3); assert(p3.C.zoneDeltaPct==70,'driver setting kept at revision 3')
end
-- Beta 1.7 : en course, une IA qui cède (drapeau bleu, appel de phares) est doublée aussitôt du côté qu'elle libère, même
-- sans avance de vitesse (relevé à Spa : les IA restaient en file derrière la voiture qui s'écartait).
tests.RACE_PASS_ON_YIELD=function()
 -- Voiture qui cède légèrement décalée d'un côté puis de l'autre : le côté de passage suit sa cession, pas sa position.
 for _,x in ipairs({1.5,-1.5}) do
  local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,1/60); e.p.personalLineJitter=0
  F.place(f,1,-2000,100); F.place(f,2,0,104); F.place(f,3,30,100,x); f.cars[2].lap=f.cars[3].lap+1
  local s2,s3=e.states[2],e.states[3]; s2.nextPerception=0; s3.nextPerception=0
  local yieldSide,passed
  for _=1,8*60 do
   F.tick(e,f,1/60)
   if F.yielding(s3.state) then yieldSide=s3.targetSide end
   if yieldSide and (s2.state=='OVT_IN' or s2.state=='OVT_HOLD') then passed=s2.targetSide; break end
  end
  assert(yieldSide,'lapped car yields to the blue flag')
  assert(passed==-yieldSide,'pass engaged at once on the freed side ('..s2.state..', x '..x..')')
 end
end
-- Beta 1.7 : une cession ou un dépassement ne commence que si le plafond anti-zigzag permet encore un changement de
-- côté (relevé à Spa : « cède » puis « direction_limit » dans la même image, la cession annulée aussitôt).
tests.NO_MANEUVER_WITHOUT_DIRECTION_BUDGET=function()
 local function full(s,now) for j=1,C.K.directionLimit do s.directions[j]=now-j end end
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,1/60)
 F.place(f,1,-2000,100); F.place(f,2,0,104); F.place(f,3,30,100); f.cars[2].lap=f.cars[3].lap+1
 local s3=e.states[3]; full(s3,e.time); s3.nextPerception=0; F.tick(e,f,3)
 -- Beta 1.47 : drapeau bleu (voiture prise d'un tour) : la cession passe avant le plafond, ni refusée ni comptée.
 assert(F.yielding(s3.state) and s3.yieldBlue and s3.driveUntil<=e.time,'blue flag: yield started, never refused ('..s3.state..')')
 local e2,f2=F.scene('C',3); C.preset('Course','C',e2.profiles.C); E.changed(e2); F.tick(e2,f2,1/60)
 F.place(f2,1,-2000,100); F.place(f2,2,0,140); F.place(f2,3,15,100)
 local s2=e2.states[2]; full(s2,e2.time); s2.nextPerception=0; F.tick(e2,f2,3)
 assert(not F.passing(s2.state) and s2.driveUntil<=e2.time,'no pass started then refused ('..s2.state..')')
 -- Beta 1.47 : cession ordinaire (journée circuit, même tour) : toujours soumise au plafond, ni commencée ni annulée ;
 -- témoin, plafond libre : cède.
 for _,limited in ipairs({false,true}) do
  local e4,f4=F.scene('J',3); E.changed(e4); F.tick(e4,f4,1/60); F.rear(e4,f4,40,20)
  local s4=e4.states[2]; if limited then full(s4,e4.time) end; F.tick(e4,f4,4)
  if limited then assert(not F.yielding(s4.state) and s4.driveUntil<=e4.time,'ordinary yield: not started then refused ('..s4.state..')')
  else assert(F.yielding(s4.state),'reference: ordinary yield ('..s4.state..')') end
 end
end
-- Beta 1.7 : en course, une attaque n'est pas abandonnée pour une voiture du même tour qui arrive vite derrière (elle
-- freine plus tard) ; elle l'est pour une voiture qui prend un tour.
tests.RACE_FAST_FOLLOWER_NO_ABORT=function()
 local function aborted(lapping)
  local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,1/60); e.p.personalLineJitter=0
  F.place(f,1,-3000,100); F.place(f,2,0,140); F.place(f,3,15,100); F.place(f,4,-2000,200)
  local s=e.states[2]; s.nextPerception=0
  for _=1,3*60 do F.tick(e,f,1/60); if F.passing(s.state) then break end end
  assert(F.passing(s.state),'pass started ('..s.state..')')
  F.place(f,4,-25,200); if lapping then f.cars[4].lap=f.cars[2].lap+1 end; s.nextPerception=0
  F.tick(e,f,1)
  return (e.stats.abort_follower or 0)>0
 end
 assert(not aborted(false),'same lap: the attack goes on')
 assert(aborted(true),'lapping car behind: the attack is given up')
end
-- Beta 1.7 : résumé minute : IA non gérées et leur raison.
tests.JOURNAL_UNMANAGED=function()
 local J=require('src/journal'); local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); E.changed(e)
 f.cars[3].pit=true; f.cars[4].offtrack=true; F.tick(e,f,0.5)
 local text=J.summary(e)
 assert(text:find('hors gestion : 3 stands, 4 hors piste',1,true),text)
end
-- Beta 1.8 : une voiture doublée illégalement reprend sa place sans sanction (relevé à Spa : Gryc sanctionné pour avoir
-- repassé le joueur 0,9 s après sa coupure des gaz) ; le droit tombe dès la place reprise et à la fin du drapeau.
tests.PENALTY_RETAKE=function()
 local e,f=F.scene('C',4); e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
 F.place(f,4,6000,0); F.place(f,2,1000,150); F.place(f,3,3000,150); F.place(f,1,990,150)
 for _=1,400 do F.tick(e,f,0.1); if e.incidents.neutral then break end end
 assert(e.incidents.neutral,'neutralisation')
 F.tick(e,f,C.K.passGiveBack+1)
 local t=e.penalties
 -- Le joueur double l'IA 2 sous neutralisation : pénalité ; l'IA 2 la reprend après la coupure des gaz, sans sanction.
 F.place(f,1,1010,150); F.tick(e,f,0.5)
 assert(t.count==1 and t.reason=='pass','player penalised for the pass')
 F.tick(e,f,e.p.penaltySeconds+1)
 F.place(f,2,1025,150); e.states[2].nextPerception=0; F.tick(e,f,0.5)
 assert((t.ai.count[2] or 0)==0,'AI retakes its place from the player without sanction')
 assert(not (t.retake[2] and t.retake[2][1]),'right dropped once the place is retaken')
 -- Entre IA : l'IA 3 double l'IA 2 (sanctionnée), puis l'IA 2 reprend sa place sans sanction.
 F.place(f,3,1020,150); e.states[3].nextPerception=0; F.tick(e,f,0.5)
 F.place(f,3,1035,150); e.states[3].nextPerception=0; F.tick(e,f,0.5)
 assert((t.ai.count[3] or 0)==1,'AI 3 sanctioned for the pass')
 -- Après le pied levé de l'IA 3 (pendant lequel elle peut être doublée de toute façon).
 F.tick(e,f,e.p.penaltySeconds+1)
 F.place(f,2,1045,150); e.states[2].nextPerception=0; F.tick(e,f,0.5)
 assert((t.ai.count[2] or 0)==0,'AI 2 retakes its place from AI 3 without sanction')
 -- Fin du drapeau : un droit encore ouvert (voiture toujours derrière) tombe.
 t.retake[3]={[2]=true}
 F.place(f,4,6000,150); for _=1,1200 do F.tick(e,f,0.1); if not e.incidents.neutral and not e.incidents.restart then break end end
 F.tick(e,f,1)
 assert(not e.incidents.neutral and not (t.retake[3] and t.retake[3][2]),'right dropped at the end of the flag')
end
-- Beta 1.8 : temps delta assoupli (choix du pilote) : tolérance 0,50 s, 2,5 s de réaction ; migration des profils restés
-- sur l'ancien défaut, réglage du pilote gardé.
tests.MIGRATION_DELTA_SOFTER=function()
 assert(C.defaults('C').deltaTolerance==0.5 and C.K.penaltyBrakeMargin==2.5,'new defaults')
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.defaults(x) end
 C.applyRules('base',profiles); profiles.C.deltaTolerance=0.1; profiles.Q.deltaTolerance=0.3; profiles.P.deltaTolerance=0.1
 local g=C.validateGlobals(C.globalDefaults); g.dataRevision=4
 C.migrate(g,profiles)
 assert(g.dataRevision==C.dataRevision and profiles.C.deltaTolerance==0.5 and profiles.P.deltaTolerance==0.5 and profiles.Q.deltaTolerance==0.3,'old default raised, driver setting kept')
end
-- Beta 1.8 : temps de réaction de 2,5 s au signal (relevé à Spa : -1,41 s à l'appel de la voiture de sécurité et -1,57 s
-- en double jaune pour un pied levé environ 2 s après le signal) ; au-delà, toujours sanctionné.
tests.DELTA_REACTION=function()
 local Delta=require('src/delta')
 local function run(kind,react,entry)
  local e,f=F.scene('C',3); local p=e.run
  local zones={{slot=3,spline=0.5,onTrack=true}}
  local inc={cars=e.incidents.cars,red=false,neutral=kind~='zone',neutralMode=kind=='scCall' and 'sc' or kind=='fcy' and 'fcy' or '',safetyPhase=kind=='scCall' and 'call' or 'none',safety=0,
   playerZone=kind=='zone',playerInside=false,playerZoneSlot=0,playerZoneDouble=true,zoneCount=kind=='zone' and 1 or 0,zones=zones}
  local target=kind=='zone' and p.yellowSpeedKmh or p.fcySpeedKmh
  local d=Delta.new(); local now=0; local z=1000; local v=250; local infraction=false; local seen=''
  for _=1,60*30 do
   now=now+1/60
   if kind=='zone' then
    if now>=entry and now<entry+12 then inc.playerInside=true; inc.playerZoneSlot=3 else inc.playerInside=false end
   end
   if now>react then v=math.max(target,v-p.yellowDecel*3.6/60) end
   z=z+v/3.6/60; F.place(f,1,z,v); Delta.update(d,f,p,inc,e.states,now,1/60,false)
   if d.kind~='' then seen=d.kind end
   if d.infraction then infraction=true end
  end
  assert(seen==kind,kind..' regime seen ('..seen..')')
  return infraction
 end
 for _,kind in ipairs({'fcy','scCall'}) do
  assert(not run(kind,2.2),kind..': lift 2.2 s after the signal, normal braking: no penalty')
  assert(run(kind,4),kind..': lift 4 s after the signal: still a penalty')
 end
 for _,entry in ipairs({2,6}) do
  assert(not run('zone',2.2,entry),'double yellow: lift 2.2 s after the panel: no penalty (entry '..entry..' s)')
  assert(run('zone',3.5,entry),'double yellow: lift 3.5 s after the panel: still a penalty')
 end
end
-- Beta 1.8 : maintien de ligne au départ. Sur la grille, chaque IA relève son écart à la trajectoire (décalé à
-- l'opposé du voisin) et le commande tel quel ; après le feu vert, il est tenu tant qu'une voiture roule à côté et pendant
-- un freinage, puis rendu à la trajectoire ; dans les deux repères latéraux, avec la largeur du côté de la voiture.
tests.START_LANE_HOLD=function()
 local half=1.85*0.5
 local function grid(sign)
  -- Beta 1.27 : coupé par défaut (départ du pilote), essayé ici activé.
  local e,f=F.scene('C',5); C.preset('Course','C',e.profiles.C); assert(not e.profiles.C.startLaneHold,'off by default in race')
  e.profiles.C.startLaneHold=true; e.profiles.C.startDelay=12; e.profiles.C.startRelax=12; E.changed(e); E.configure(e); e.g.offsetSign=sign
  assert(e.run.startLaneHold,'on when ticked')
  f.started=false
  F.place(f,1,-3000,0); F.place(f,2,0,0,3); F.place(f,3,0,0,-1.5); F.place(f,4,-60,0,4.5); F.place(f,5,-120,0,0.2)
  for i=2,5 do f.cars[i].leftWidth=5; f.cars[i].rightWidth=7 end
  F.tick(e,f,2)
  return e,f
 end
 for _,sign in ipairs({1,-1}) do
  local e,f=grid(sign)
  local s2,s3,s4,s5=e.states[2],e.states[3],e.states[4],e.states[5]
  -- Droite interne : côté SDK du signe calibré ; largeur de ce côté (7 m à droite SDK, 5 m à gauche SDK).
  local wr=sign>0 and 7 or 5; local wl=sign>0 and 5 or 7
  assert(math.abs(s2.lane-(3+C.K.laneBias)/wr)<1e-6,'grid: lane latched away from the neighbour ('..s2.lane..', sign '..sign..')')
  assert(math.abs(s3.lane-(-1.5-C.K.laneBias)/wl)<1e-6,'grid: neighbour latched on its own side ('..s3.lane..')')
  -- Côté large, sans voisin : borne de son côté (la borne symétrique, 0,58, la ramènerait vers la trajectoire).
  local expected4=math.min(4.5/wr,(wr-half)/wr,C.K.laneMaxOffset)
  assert(math.abs(s4.lane-expected4)<1e-6 and s4.lane>0.6,'grid: wide side, bound of its own side ('..s4.lane..')')
  assert(s5.lane==0,'car on the line: nothing to hold')
  assert(math.abs(e.commands[2].offset-s2.lane)<1e-6 and math.abs(e.commands[3].offset-s3.lane)<1e-6 and math.abs(e.commands[4].offset-s4.lane)<1e-6,'commanded on the grid')
  -- Feu vert : voisins côte à côte, ligne tenue ; voiture seule au freinage, tenue elle aussi.
  f.started=true
  for i=2,5 do F.place(f,i,f.cars[i].z,120,f.cars[i].x) end
  f.cars[4].brake=0.6
  F.tick(e,f,4,true)
  assert(math.abs(e.commands[2].offset-s2.lane)<1e-6 and math.abs(e.commands[3].offset-s3.lane)<1e-6,'held while alongside after the start')
  assert(math.abs(e.commands[4].offset-expected4)<1e-6,'held while braking, wide side kept ('..e.commands[4].offset..')')
  f.cars[4].brake=0
  -- Voisin parti devant, IA au freinage : toujours tenue ; freinage fini : rendue à la trajectoire, progressivement.
  F.place(f,3,f.cars[2].z+150,120,-1.5); f.cars[2].brake=0.6
  F.tick(e,f,2,true)
  -- Voisin parti : la marge de 0,3 m tombe, la position relevée reste tenue.
  assert(s2.lane~=0 and math.abs(e.commands[2].offset-3/wr)<0.01,'held while braking ('..e.commands[2].offset..')')
  f.cars[2].brake=0
  F.tick(e,f,1.5,true)
  assert(s2.lane==0 and e.commands[2].offset>0 and e.commands[2].offset<3/wr,'released: ramps back, not a jump')
  F.tick(e,f,8,true)
  assert(math.abs(e.commands[2].offset)<0.02 and math.abs(e.commands[4].offset)<0.02,'back on the line ('..e.commands[2].offset..')')
 end
 -- Réglage décoché, ou onglet Départ décoché : rien n'est retenu.
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); e.profiles.C.startLaneHold=false; E.changed(e)
 f.started=false; F.place(f,1,-3000,0); F.place(f,2,0,0,3); F.place(f,3,0,0,-1.5); F.tick(e,f,2)
 assert(e.states[2].lane==0 and math.abs(e.commands[2].offset)<1e-6,'disabled: no lane hold')
 local e3,f3=F.scene('C',3); C.preset('Course','C',e3.profiles.C); e3.profiles.C.startLaneHold=true; e3.profiles.C.section_start=false; E.changed(e3)
 f3.started=false; F.place(f3,1,-3000,0); F.place(f3,2,0,0,3); F.place(f3,3,0,0,-1.5); F.tick(e3,f3,2)
 assert(not e3.run.startLaneHold and e3.states[2].lane==0,'start tab off: no lane hold')
 -- Fin du départ (attente plus détente) : une ligne encore tenue est rendue.
 local e2,f2=grid(1)
 f2.started=true; for i=2,5 do F.place(f2,i,f2.cars[i].z,120,f2.cars[i].x) end
 F.tick(e2,f2,e2.run.startDelay+e2.run.startRelax+1,true)
 assert(e2.states[2].lane==0 and not e2.states[2].laneActive,'released at the end of the start window')
end
-- Beta 1.9 : préréglage personnel enregistré avant la Beta 1.8 (révision 4) : delta assoupli et maintien de ligne de
-- la course, comme les profils enregistrés ; un réglage du pilote est gardé.
tests.CUSTOM_PRESET_REVISION_6=function()
 local Pr=require('src/presets')
 local p=C.defaults('C'); p.deltaTolerance=0.1; p.startLaneHold=false
 local store=Pr.encode({name='Avant 1.8',profile='C',p=p,g=C.validateGlobals(C.globalDefaults)}); store.revision=4
 local entry=Pr.decode(store)
 assert(entry.p.deltaTolerance==0.5 and entry.p.startLaneHold==C.defaults('C').startLaneHold,'old preset: softer delta and lane hold of the race')
 local mine=C.defaults('C'); mine.deltaTolerance=0.3
 local kept=Pr.decode(Pr.encode({name='Mien',profile='C',p=mine,g=C.validateGlobals(C.globalDefaults)}))
 assert(kept.p.deltaTolerance==0.3,'current preset untouched')
end
-- Beta 1.9 : règles GT conformes au règlement SRO 2026 (stands ouverts sous FCY) ; seuls les profils qui portaient les
-- anciennes règles GT changent, et le changement est signalé.
tests.MIGRATION_GT_PITS_OPEN=function()
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.defaults(x) end
 C.applyRules('GT',profiles); for _,x in ipairs(C.ruleProfiles) do profiles[x].pitsClosed='pitFcy' end
 profiles.Q.fcyDeltaPct=120
 local g=C.validateGlobals(C.globalDefaults); g.dataRevision=5
 local upgraded=C.migrate(g,profiles)
 assert(g.dataRevision==C.dataRevision and profiles.C.pitsClosed=='open' and profiles.P.pitsClosed=='open' and C.ruleCategory('C',profiles.C)=='GT','old GT rules updated')
 assert(profiles.Q.pitsClosed=='pitFcy','edited rules kept')
 local seen=0; for _,u in ipairs(upgraded) do if u:find(':regles GT$') then seen=seen+1 end end
 assert(seen==2,'GT update reported')
end
-- Beta 1.9 : Journée circuit restaurée : ses réglages de règles reviennent aussi au défaut (aucun jeu de règles ne la
-- règle) ; les autres profils gardent leurs règles de championnat ; préférences du pilote gardées partout.
tests.RESTORE_TRACK_DAY_RULES=function()
 local j=C.defaults('J'); j.zoneDeltaPct=120; j.noMoveBraking=false; j.redFlagHold=500; j.yellowMessage=false
 C.restore('J',j)
 assert(j.zoneDeltaPct==C.defaults('J').zoneDeltaPct and j.noMoveBraking==C.defaults('J').noMoveBraking and j.redFlagHold==C.defaults('J').redFlagHold,'track day rules restored')
 assert(j.yellowMessage==false,'driver preference kept')
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.defaults(x) end
 C.applyRules('F1',profiles); C.restore('C',profiles.C); assert(C.ruleCategory('C',profiles.C)=='F1','race keeps its championship rules')
 -- Message de fenêtre d'arrêt : préférence du pilote, gardée par un jeu de règles.
 profiles.C.pitMessage=false; C.applyRules('F1_2026',profiles); assert(profiles.C.pitMessage==false,'pit window message kept')
end
-- Beta 1.9 : onglet Personnalité décoché : erreurs de pilotage coupées dans les valeurs effectives.
tests.EFFECTIVE_HUMAN_OFF=function()
 local p=C.defaults('C'); p.section_human=false; p.mistakesEnabled=true
 local out=C.effective('C',p,{})
 assert(out.mistakesEnabled==false,'no mistakes with the personality tab unticked')
end
-- Beta 1.9 : obstacle qui glisse vers le côté d'évitement retenu : côté réévalué, jamais vers lui.
tests.AVOID_OBSTACLE_SLIDES=function()
 local P=require('src/perception')
 local e,f=F.scene('J',3); e.p.personalLineJitter=0
 F.place(f,2,0,100); F.place(f,3,80,0,-2); F.tick(e,f,3)
 local s=e.states[2]; assert(s.state=='AVOID' and s.avoidSide~=0,'avoiding')
 local first=s.avoidSide
 F.place(f,3,80,0,3); s.nextPerception=0; F.tick(e,f,3)
 local r=P.find(e.perception.rows[2],3)
 assert(s.avoidSide==-first and r.lat*s.avoidSide>0,'side changed away from the sliding car')
 assert(s.offset*s.avoidSide>=0,'moving away from it')
end
-- Beta 1.9 : côte à côte achevé sans marge (cible devant ou juste derrière à la même allure) : retour, jamais décalée
-- indéfiniment.
tests.PASS_HOLD_ENDS=function()
 for _,case in ipairs({{'J',20},{'J',-15},{'C',-12},{'C',15}}) do
  local e,f=F.scene(case[1],3); e.p.personalLineJitter=0
  F.place(f,2,0,100); F.place(f,3,case[2],100); F.tick(e,f,0.1)
  local s=e.states[2]; s.state='OVT_HOLD'; s.since=e.time; s.target=3; s.targetSide=1; s.passAlongside=true; s.restUntil=0; s.offset=0.4; s.filtered=0.4
  s.nextPerception=0
  F.tick(e,f,20,true)
  assert(s.state~='OVT_HOLD' and s.state~='OVT_IN','pass ended: '..case[1]..' '..case[2]..' '..s.state)
 end
end
-- Beta 1.9 : défense refusée par le plafond anti-zigzag : elle ne commence pas, la cession au drapeau bleu suit.
-- Beta 1.47 : suiveur nettement d'un côté (K.defenseLatMin, 0,8 m) ; témoin, plafond libre : défense envisagée.
tests.DEFEND_NEEDS_DIRECTION_BUDGET=function()
 do
  local e,f=F.scene('C',4); e.profiles.C.noMoveBraking=false; E.changed(e); F.tick(e,f,1/60); e.p.personalLineJitter=0
  local s=e.states[2]; s.persona.assertiveness=1
  F.place(f,4,3000,100); F.place(f,2,0,150); F.place(f,3,-15,160,0.8); s.nextPerception=0
  for _=1,30 do F.tick(e,f,1/60); F.place(f,2,0,150); F.place(f,3,-15,160,0.8) end
  assert(s.defendAttacker==3,'reference: defence considered with the budget free')
 end
 local e,f=F.scene('C',4); e.profiles.C.noMoveBraking=false; E.changed(e); F.tick(e,f,1/60); e.p.personalLineJitter=0
 local s=e.states[2]; s.persona.assertiveness=1
 F.place(f,4,3000,100)
 s.directions[1]=e.time-59; for j=2,6 do s.directions[j]=e.time-10-j end; s.lastDirectionAt=e.time-12
 F.place(f,2,0,150); F.place(f,3,-15,160,0.8); s.nextPerception=0
 for _=1,30 do F.tick(e,f,1/60); F.place(f,2,0,150); F.place(f,3,-15,160,0.8) end
 assert(s.state~='DEFEND' and (e.stats.limit or 0)==0,'no defence started against the budget')
 F.place(f,3,3500,100); s.nextPerception=0
 local at
 for k=1,10*60 do
  F.place(f,2,0,150); F.place(f,4,-60,175); f.cars[4].lap=f.cars[4].lap+1
  F.tick(e,f,1/60); if not at and F.yielding(s.state) then at=k/60 end
 end
 assert(at and at<3,'blue-flag yield not frozen ('..tostring(at)..')')
end
-- Beta 1.9 : retour après un abandon sous drapeau jaune : la marge atteinte n'enchaîne pas un nouveau dépassement.
tests.NO_CHAIN_FROM_OVT_OUT=function()
 local e,f=F.scene('J',5); e.p.personalLineJitter=0
 F.place(f,2,-5000,100); F.place(f,3,-4900,100); F.place(f,5,-4800,100); F.place(f,4,250,0); F.tick(e,f,3)
 assert(e.incidents.cars[4].incident,'incident ahead')
 local s=e.states[2]
 F.place(f,2,-100,120); F.place(f,3,-130,100); F.place(f,5,-60,100); s.nextPerception=0
 s.state='OVT_HOLD'; s.since=e.time; s.target=3; s.targetSide=1; s.passAlongside=true; s.offset=0.5; s.filtered=0.5; e.stats={}
 for _=1,240 do
  F.tick(e,f,1/60)
  F.place(f,2,-100,120); F.place(f,3,-130,100); F.place(f,5,-60,100)
 end
 assert((e.stats.chain or 0)==0 and (e.stats.abort_yellow or 0)<=1,'no chained pass from the return, one abort')
end
-- Beta 1.9 : le joueur doublé illégalement par une IA reprend sa place sans pénalité, même quand l'IA est dans son délai
-- entre deux sanctions ou que les sanctions des IA sont coupées.
tests.PLAYER_RETAKE_ALWAYS=function()
 local Pe=require('src/penalties'); local P=require('src/perception')
 local function run(setup)
  local e,f=F.scene('C',3); local p=e.run
  p.playerPenalties=true; p.aiPenalties=true
  local inc={cars=e.incidents.cars,playerNoPass=true,neutral=false,red=false,neutralMode='fcy',safetyPhase='none',safety=0,playerRestart=false}
  e.states[2].yellow=true
  F.place(f,3,5000,100)
  local t=Pe.new(); setup(t,p)
  local function frame(now,pz,az)
   F.place(f,1,pz,100); F.place(f,2,az,100)
   for i=1,3 do P.refresh(e.perception,f.cars,f.count,i,f.length) end
   Pe.update(t,f,p,'C',inc,now,0.1,nil); Pe.ai(t,f,p,'C',inc,e.states,e.perception.rows,now)
  end
  frame(0,20,0)
  for now=1,11 do frame(now,20,0) end
  frame(12,20,30); frame(13,20,30); frame(14,40,30)
  return t
 end
 assert(run(function() end).count==0,'baseline: no penalty for the retake')
 assert(run(function(t) t.ai.lastAt[2]=4 end).count==0,'AI within its cooldown: retake still free')
 assert(run(function(_,p) p.aiPenalties=false end).count==0,'AI sanctions off: retake still free')
end
-- Beta 1.9 : une IA qui double en coupant la piste sous drapeau jaune est sanctionnée, comme sur la piste.
tests.AI_PASS_BY_CUTTING=function()
 local function run(cut)
  local e,f=F.scene('C',4); e.profiles.C.neutralization='local'; e.profiles.C.yellowEnabled=true; E.changed(e)
  F.place(f,4,6000,0); F.place(f,2,5800,60); F.place(f,3,5810,60); F.place(f,1,9000,100)
  for _=1,100 do F.tick(e,f,0.1); if e.states[2].yellow and e.states[3].yellow then break end end
  F.tick(e,f,C.K.passGiveBack+1)
  e.states[2].nextPerception=0; e.states[3].nextPerception=0; F.tick(e,f,0.3)
  if cut then f.cars[2].offtrack=true; F.tick(e,f,0.2) end
  F.place(f,2,5840,60); f.cars[2].offtrack=false; e.states[2].nextPerception=0; F.tick(e,f,0.3)
  return e.penalties.ai.count[2] or 0
 end
 assert(run(false)==1,'pass on track sanctioned')
 assert(run(true)==1,'pass by cutting the track sanctioned too')
end
-- Beta 1.9 : file sous drapeau : jamais derrière une voiture qui purge une sanction (elle peut être doublée).
tests.QUEUE_NOT_BEHIND_SERVING=function()
 local function run(serving)
  local e,f=F.scene('C',3)
  e.p.neutralization='fcy'
  F.place(f,1,-3000,100); F.place(f,2,0,100); F.place(f,3,30,60)
  F.tick(e,f,0.2)
  local inc=e.incidents; inc.neutral=true; inc.neutralMode='fcy'; inc.neutralSince=e.time; inc.neutralUntil=1e9
  if serving then local s=e.penalties.ai; s.slowUntil[3]=e.time+100; s.slowKmh[3]=60; s.slowFrom[3]=60; s.slowAt[3]=e.time end
  for _=1,600 do F.place(f,2,0,100); F.place(f,3,30,60); F.tick(e,f,1/60) end
  return e.commands[2].yellowLimit
 end
 local queued,free=run(false),run(true)
 -- Beta 1.50 (voiture de sécurité du 5 novembre) : sous neutralisation, file derrière la voiture la plus proche devant,
 -- sanction en cours comprise ; seule une voiture accidentée se double (Penalties.mayPass, neutral). Test aligné en 1.51.
 assert(math.abs(free-queued)<1,'under a neutralisation, queued even behind a car serving a sanction ('..queued..' / '..free..')')
 -- Hors neutralisation (drapeau jaune local), la voiture qui purge une sanction reste dépassable.
 local e,f=F.scene('C',3); local s=e.penalties.ai; s.slowUntil[3]=e.time+100
 local Pen=require('src/penalties')
 assert(Pen.mayPass(e.penalties,2,3,e.time,1,false) and not Pen.mayPass(e.penalties,2,3,e.time,1,true),'serving car passable outside a neutralisation only')
end
-- Beta 1.10 : profil Hotlap : choisi en hotlap, time attack, drift et drag ; neutre (aucun préréglage recommandé) ;
-- pénalités masquées et règles de championnat sans objet, comme en journée circuit.
tests.HOTLAP_PROFILE=function()
 for kind=4,7 do assert(C.autoProfile({configType=kind})=='H','session '..kind..' -> Hotlap') end
 assert(C.autoProfile({configType=1,configTrackDay=true})=='J' and C.autoProfile({configType=3})=='C','other sessions unchanged')
 assert(C.hidden('H','playerPenalties') and C.hidden('H','enduranceOverlay') and C.solo('H'),'penalties hidden')
 local e,f=F.scene('J',3); e.g.presetsUsed=true; e.g.autoProfile=false; e.profiles.H=C.defaults('H'); E.select(e,'H'); F.tick(e,f,0.5)
 assert(e.profile=='H' and not e.profiles.H.configured and e.guard=='ready','Hotlap active with its default')
 for _,group in ipairs(C.sections) do assert(C.on(e.profiles.H,group)==(group=='rules' or group=='lights'),'only the rules tab (and the track light panels): '..group) end
 -- Hotlap décoché par le pilote : aucun préréglage recommandé ne vient le remplir.
 e.profiles.H.section_rules=false; E.changed(e); F.tick(e,f,0.5)
 assert(not C.anySection(e.profiles.H) and not e.profiles.H.configured,'an unticked Hotlap stays empty')
 e.profiles.H.section_rules=true; E.changed(e)
 local base=C.defaults('H'); for _,s in ipairs(C.ruleSchema) do assert(base[s.key]==s.defaults.H,'base rules: '..s.key) end
 -- Révision 8 : profil Hotlap vide et jamais réglé (Beta 1.10 à 1.14) : onglet Règles ; un profil réglé reste tel quel.
 local old={}; for _,x in ipairs(C.profiles) do old[x]=C.defaults(x) end; old.H.section_rules=false
 local g=C.validateGlobals(C.globalDefaults); g.dataRevision=7; C.migrate(g,old); assert(old.H.section_rules,'old empty Hotlap gets the rules tab')
 local kept={}; for _,x in ipairs(C.profiles) do kept[x]=C.defaults(x) end; kept.H.section_rules=false; kept.H.configured=true
 local g2=C.validateGlobals(C.globalDefaults); g2.dataRevision=7; C.migrate(g2,kept); assert(not kept.H.section_rules,'a configured Hotlap is kept')
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.defaults(x) end
 C.applyRules('F1',profiles); assert(not profiles.H.configured and C.ruleCategory('H',profiles.H)~='F1' and C.ruleCategory('C',profiles.C)=='F1','championship rules do not touch Hotlap')
end
-- Beta 1.10 : aucune barre de titre CSP (ni croix) sur les fenêtres de l'app.
-- Lecture du vrai manifeste : io.open capturé au chargement, avant que le banc ne le remplace.
local openFile=io.open
tests.NO_TITLE_BAR=function()
 local root=package.path:match('^([^;]+)/%?%.lua'); local file=assert(openFile(root..'/manifest.ini','rb')); local text=file:read('*a'); file:close()
 local windows=0
 for flags in text:gmatch('\nFLAGS=([^\r\n]*)') do windows=windows+1; assert(flags:find('NO_TITLE_BAR',1,true),'title bar shown: '..flags) end
 -- Beta 1.25 : l'overlay en jeu n'est plus une fenêtre d'app mais le rappel IN_GAME (fenêtre transparente dessinée).
 assert(windows==1 and text:find('\n%[UI_CALLBACKS%]%s*\r?\nIN_GAME=HUMANAI__HUD'),'settings window only, overlay drawn in game')
end
-- Beta 1.45 : fenêtre de réglages sans fond ni marge de CSP (plus de cadre gris autour), comme SetupLab ; W.begin
-- peint le fond de l'app sur toute la fenêtre.
tests.WINDOW_EDGE_145=function()
 local root=package.path:match('^([^;]+)/%?%.lua'); local file=assert(openFile(root..'/manifest.ini','rb')); local text=file:read('*a'); file:close()
 local w=text:match('%[WINDOW_0%][^\n]*\n(.-)\r?\n%s*\r?\n'); assert(w,'settings window section')
 local flags=w:match('FLAGS=([^\r\n]*)') or ''
 assert((','..flags..','):find(',NO_BACKGROUND,',1,true),'no CSP background: '..flags)
 assert(w:find('PADDING=0,0',1,true),'no CSP padding')
 assert(not w:find('BACKGROUND_COLOR=',1,true),'no CSP background colour')
end
-- Beta 1.11 : drapeaux et pénalités natifs d'AC repris par le panneau (affichage d'origine masqué dans CSP), y compris
-- onglet Règles décoché et app à l'arrêt ; le jaune imposé par l'app n'est jamais repris comme drapeau du jeu.
tests.NATIVE_FLAGS_MIRRORED=function()
 local L=require('src/lang')
 local e,f=F.scene('C',3); local me=f.cars[1]
 f.flag=C.K.flagStop; F.tick(e,f,0.5); assert(e.panel.kind=='black' and e.panel.title==L.flagTitles.black,'black flag')
 f.flag=C.K.flagNone; me.penaltyType=C.K.penaltyMandatoryPits; me.penaltyParam=2; F.tick(e,f,0.5)
 assert(e.panel.kind=='penalty' and e.panel.raw==string.format(L.flagDetails.penaltyDrive,2),'drive-through with laps left')
 assert(not e.panel.noPass,'no overtaking line of the app on a game penalty')
 me.penaltyParam=1; F.tick(e,f,0.5); assert(e.panel.raw==string.format(L.flagDetails.penaltyDrive,1),'laps left refreshed')
 me.penaltyType=C.K.penaltySlowDown; me.penaltyParam=5; F.tick(e,f,0.5); assert(e.panel.raw==string.format(L.flagDetails.penaltySlow,5),'gas cut')
 me.penaltyType=0; me.penaltyParam=0
 f.flag=C.K.flagFinished; F.tick(e,f,0.5); assert(e.panel.kind=='checkered','checkered flag')
 f.flag=C.K.flagOneLapLeft; F.tick(e,f,0.5); assert(e.panel.kind=='white','last lap')
 f.flag=C.K.flagFasterCar; F.tick(e,f,0.5); assert(e.panel.kind=='blue' and e.panel.blueGap==nil and e.panel.raw==L.flagDetails.nativeBlue,'native blue')
 -- Panneau de l'app coupé (onglets Accidents et Règles décochés) : drapeaux d'AC seulement.
 e.profiles.C.section_rules=false; e.profiles.C.section_accidents=false; E.changed(e); F.tick(e,f,0.1); assert(not e.run.flagPanel)
 f.flag=C.K.flagStop; F.tick(e,f,0.5); assert(e.panel.kind=='black','mirrored with the rules tab unticked')
 f.flag=C.K.flagCaution; f.flagOwned=true; F.tick(e,f,0.5); assert(e.panel.kind=='none','own yellow never mirrored')
 f.flagOwned=false; F.tick(e,f,0.5); assert(e.panel.kind=='native','game yellow mirrored')
 -- App coupée : les drapeaux du jeu restent affichés.
 e.g.enabled=false; f.flag=C.K.flagNone; me.penaltyType=C.K.penaltyMandatoryPits; me.penaltyParam=3; F.tick(e,f,0.5)
 assert(e.guard=='disabled' and e.panel.kind=='penalty','mirrored with the app off')
 me.penaltyType=0; F.tick(e,f,0.5); assert(e.panel.kind=='none','cleared when the penalty is served')
end
-- Beta 1.12 : Hotlap choisi à la main conservé à la validation des options globales.
tests.HOTLAP_MANUAL_KEPT=function()
 local g=C.validateGlobals(C.globalDefaults); g.manualProfile='H'
 local out,errors=C.validateGlobals(g); assert(out.manualProfile=='H' and errors==0,'manual Hotlap kept')
end
-- Beta 1.12 : erreurs de pilotage dans toutes les sessions ; migration de l'ancien défaut hors course.
tests.MISTAKES_ALL_SESSIONS=function()
 for _,profile in ipairs(C.profiles) do assert(C.defaults(profile).mistakesEnabled,profile) end
 assert(C.defaults('J').mistakeRate==1 and C.defaults('Q').mistakeRate==0.5 and C.defaults('C').mistakeRate==0.5,'rates')
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.defaults(x); profiles[x].mistakesEnabled=false; profiles[x].mistakeRate=0.5; profiles[x].configured=true end
 local g=C.validateGlobals(C.globalDefaults); g.dataRevision=6; C.migrate(g,profiles)
 assert(profiles.J.mistakesEnabled and profiles.P.mistakesEnabled and profiles.Q.mistakesEnabled and not profiles.C.mistakesEnabled,'old default raised, race setting kept')
 assert(profiles.J.mistakeRate==1 and profiles.Q.mistakeRate==0.5,'track day rate raised')
 local e=F.scene('Q',3); assert(e.run.mistakesEnabled,'active in qualifying')
end
-- Beta 1.12 : drapeau rouge en qualifications : toutes les IA rentrent, reprise sans tour de relance, sortie échelonnée ;
-- jamais en journée circuit.
tests.RED_FLAG_QUALIFYING=function()
 local e,f=F.scene('Q',6); e.profiles.Q.redFlagHold=20; E.changed(e)
 for i=2,6 do F.place(f,i,(i-1)*300,120) end
 F.block(f,{3,4,5},600)
 F.tick(e,f,C.K.redIncidentStill+1)
 local t=e.incidents
 assert(t.red and e.commands[2].rulePit and e.commands[6].rulePit,'red flag in qualifying, everyone called in')
 local L=require('src/lang')
 assert(t.messageKind=='redSession' and e.panel.raw==L.flagDetails.redSession,'session suspended, not the race')
 for i=2,6 do local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0 end; f.cars[1].pit=true
 for _=1,120 do if not t.red then break end; F.tick(e,f,0.5) end
 assert(not t.red and not t.neutral and not t.relaunch,'session resumed without a relaunch lap')
 F.tick(e,f,0.3); assert(t.messageKind=='sessionResume' and e.panel.kind=='green' and e.panel.raw==L.flagDetails.greenSession,'session resumes')
 assert(e.commands[2].pitHold or e.commands[6].pitHold,'staggered pit exit')
 assert(t.restartRank==0 and e.panel.restartBox==nil and e.panel.restartPill==nil,'Beta 1.48: no restart position outside the race')
 -- Beta 1.48 : joueur resté au garage : hors de l'ordre de sortie (personne ne l'attend).
 f.cars[1].pit=true; f.cars[1].inPitBox=true
 for _=1,4*(C.K.redReleaseFirst+6*C.K.redReleaseGap) do
  F.tick(e,f,0.25)
  for i=2,6 do local a=f.cars[i]; if not e.commands[i].pitHold and a.inPitBox then a.inPitBox=false; F.place(f,i,3000,60); a.pit=true end end
 end
 assert(not e.commands[2].pitHold and not e.commands[6].pitHold,'all released')
 local e2,f2=F.scene('J',6); for i=2,6 do F.place(f2,i,(i-1)*300,120) end; F.block(f2,{3,4,5},600)
 F.tick(e2,f2,C.K.redIncidentStill+2); assert(not e2.incidents.red,'never on a track day, even on a blocked track')
end
-- Beta 1.12 : carburant des arrêts forcés : ravitaillement juste pour le relais ou l'arrivée, plein de course avant le
-- départ, rien sans consommation connue ni hors course, jamais le joueur ; consommation apprise tour par tour.
tests.FUEL_STRATEGY=function()
 local Pits=require('src/pits')
 local e,f=F.scene('C',3); local p=e.run; local t=Pits.new()
 local function setup(mode,started)
  f.started=started; f.sessionLaps=30; f.timedRace=false; f.fuelRate=1; f.track='test'
  for i=1,3 do local a=f.cars[i]; a.fuel=8; a.maxFuel=100; a.fuelPerLap=2; a.lap=10; a.pit=false end
  p.pitFuel=mode; p.mandatoryStops=0; p.maxStintMin=0
  for i=1,3 do e.commands[i].rulePit=i~=3 end
 end
 local reserve=2*C.K.fuelReserveLaps; local want=20*2*C.K.fuelMargin+reserve
 local function close(x,y) return math.abs(x-y)<1e-6 end
 setup('refuel',true); Pits.fuel(t,f,e.commands,p,'C',100,false)
 assert(close(e.commands[2].fuelTarget,want) and e.commands[2].fuelLaps==math.floor((want-reserve)/2),'refuel to the finish')
 assert(e.commands[3].fuelTarget<0 and e.commands[1].fuelTarget<0,'only the called AI, never the player')
 p.maxStintMin=30; t.cars[2].lapTime=100; Pits.fuel(t,f,e.commands,p,'C',100,false)
 assert(close(e.commands[2].fuelTarget,18*2*C.K.fuelMargin+reserve),'fuel for the stint')
 Pits.fuel(t,f,e.commands,p,'C',100,true); assert(close(e.commands[2].fuelTarget,want),'red flag: only to finish')
 setup('plan',true); f.cars[2].fuel=60; Pits.fuel(t,f,e.commands,p,'C',100,false)
 assert(e.commands[2].fuelTarget==60,'no refuel when enough to finish')
 f.cars[2].fuel=8; Pits.fuel(t,f,e.commands,p,'C',100,false); assert(close(e.commands[2].fuelTarget,want),'only what is missing to finish')
 setup('plan',false); f.cars[2].lap=0; Pits.fuel(t,f,e.commands,p,'C',0,false)
 assert(close(e.commands[2].fuelSet,math.min(100,30*2*C.K.fuelMargin+reserve)),'race fuel before the start')
 setup('refuel',false); f.cars[2].lap=0; Pits.fuel(t,f,e.commands,p,'C',0,false); assert(e.commands[2].fuelSet<0,'no grid fuel when refuelling')
 setup('ac',true); Pits.fuel(t,f,e.commands,p,'C',100,false); assert(e.commands[2].fuelTarget<0,'left to AC')
 setup('refuel',true); f.fuelRate=0; Pits.fuel(t,f,e.commands,p,'C',100,false); assert(e.commands[2].fuelTarget<0,'no fuel consumption')
 setup('refuel',true); Pits.fuel(t,f,e.commands,p,'Q',100,false); assert(e.commands[2].fuelTarget<0,'race only')
 local t3=Pits.new(); setup('refuel',true); f.cars[2].fuelPerLap=0; Pits.fuel(t3,f,e.commands,p,'C',100,false)
 assert(e.commands[2].fuelTarget<0,'unknown consumption: nothing imposed')
 local t2=Pits.new(); setup('refuel',true); e.commands[2].rulePit=false; local a=f.cars[2]; a.fuelPerLap=0; a.lap=5; a.fuel=50
 Pits.fuel(t2,f,e.commands,p,'C',100,false); a.lap=6; a.fuel=47.5; Pits.fuel(t2,f,e.commands,p,'C',190,false)
 assert(close(t2.cars[2].perLap,2.5) and close(t2.cars[2].lapTime,90),'consumption and lap time learned')
 assert(t2.models['test|'..a.id].perLap==2.5,'kept for the next session')
end
-- Beta 1.12 : demande de carburant écrite au litre près, une fois, rendue à AC ; plein de départ une fois par session.
tests.FUEL_WRITES_AND_RESTORE=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C'); local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false; cmd.fuelTarget=-1; cmd.fuelSet=-1 end
 local car=f.cars[2]; car.fuel=8; car.inPitBox=false
 local cmd=e.commands[2]; cmd.fuelTarget=42.4; cmd.fuelLaps=20
 A.apply(a,f,e.commands,e.g,10); assert(host.fuelRequests[1] and host.fuelRequests[1].fuel==42 and host.fuelRequests[1].laps==20,'request written to the litre')
 local n=host.calls; A.apply(a,f,e.commands,e.g,10.2); assert(host.calls==n,'not rewritten')
 cmd.fuelTarget=-1; A.apply(a,f,e.commands,e.g,11); assert(host.fuelRequests[1].fuel==math.huge,'handed back to AC')
 cmd.fuelTarget=30; A.apply(a,f,e.commands,e.g,12); assert(host.fuelRequests[1].fuel==30)
 A.restore(a,f,false,13,true); assert(host.fuelRequests[1].fuel==math.huge,'handed back on unload')
 local b=A.new(); assert(A.access(b)); host.sim.isSessionStarted=false; cmd.fuelTarget=-1; cmd.fuelSet=55
 A.apply(b,f,e.commands,e.g,14); assert(host.fuelSets[1]==55,'race fuel set before the start')
 host.fuelSets[1]=nil; A.apply(b,f,e.commands,e.g,15); assert(host.fuelSets[1]==nil,'once per session')
end
-- Beta 1.12 : règles F1 et GT sans ravitaillement ; migration des jeux de règles enregistrés avant la Beta 1.12.
tests.FUEL_RULES_MIGRATION=function()
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.defaults(x) end
 C.applyRules('F1',profiles); assert(profiles.C.pitFuel=='plan' and profiles.Q.pitFuel=='plan','F1: race fuel planned')
 C.applyRules('Endurance',profiles); assert(profiles.C.pitFuel=='refuel','endurance: refuelling')
 local old={}; for _,x in ipairs(C.profiles) do old[x]=C.defaults(x); old[x].configured=true end
 C.applyRules('GT',old); old.C.pitFuel='refuel'; old.P.pitFuel='refuel'; C.applyRules('base',{P=old.Q,Q=old.Q,C=old.Q})
 local g=C.validateGlobals(C.globalDefaults); g.dataRevision=6; C.migrate(g,old)
 assert(old.C.pitFuel=='plan' and C.ruleCategory('C',old.C)=='GT','old GT rules follow')
 assert(old.Q.pitFuel=='refuel' and C.ruleCategory('Q',old.Q)=='base','base rules keep refuelling')
end
-- Beta 1.12 : audit des préréglages intégrés : comportement observé dans le moteur contre le comportement attendu
-- (documentation et règlements) : cession et son côté, dépassement et son côté, appels de phares, enchaînement,
-- pénalités, drapeaux bleus, drapeau rouge, espacement, départ, multi-classes, surcouche Endurance, carburant.
tests.PRESET_BEHAVIOUR_MATRIX=function()
 local function scene(preset,profile)
  local e,f=F.scene(profile,3)
  for _,x in ipairs({'J','P','Q','C'}) do for _,g in ipairs(C.sections) do e.profiles[x]['section_'..g]=false end end
  C.preset(preset,profile,e.profiles[profile]); e.g.autoProfile=false; e.g.manualProfile=profile; E.select(e,profile); E.changed(e)
  for i=1,3 do e.states[i].persona.laneBias=0 end
  e.p.personalLineJitter=0
  return e,f
 end
 local function observe(preset,profile)
  local e,f=scene(preset,profile); F.rear(e,f,45,30); F.tick(e,f,4)
  local s=e.states[2]
  local yield=F.yielding(s.state) and (s.offset>0.05 and 'right' or s.offset<-0.05 and 'left' or 'place') or 'no'
  e,f=scene(preset,profile); F.front(e,f,35,30); local pass='no'
  for _=1,40 do F.tick(e,f,0.1); local st=e.states[2]; if F.passing(st.state) then pass=st.targetSide<0 and 'left' or st.targetSide>0 and 'right' or 'yes'; break end end
  local p=e.run
  return {yield=yield,pass=pass,flash=p.flashMode,chain=p.overtakeChain,penalties=p.playerPenalties and not C.solo(profile),blue=p.blueFlagEnabled and profile=='C',
   red=p.redFlagEnabled and (profile=='C' or profile=='P' or profile=='Q'),traffic=p.section_traffic and profile=='J',start=profile=='C' and p.startLaneHold,
   multi=p.multiClass,overlay=p.enduranceOverlay,mistakes=p.mistakesEnabled}
 end
 local expected={
  {'Nordschleife','J',{yield='right',pass='left',flash='always',chain=true,penalties=false,blue=false,red=false,traffic=true,start=false,multi=true,overlay=false,mistakes=true}},
  {'Essais','P',{yield='right',pass='left',flash='always',chain=true,penalties=true,blue=false,red=true,traffic=false,start=false,multi=true,overlay=false,mistakes=true}},
  {'Qualifications','Q',{yield='right',pass='left',flash='always',chain=false,penalties=true,blue=false,red=true,traffic=false,start=false,multi=true,overlay=false,mistakes=true}},
  {'Course','C',{yield='no',flash='lapped',chain=true,penalties=true,blue=true,red=true,traffic=false,start=false,multi=true,overlay=false,mistakes=true}},
  {'Endurance','C',{yield='no',flash='lapped',chain=true,penalties=true,blue=true,red=true,traffic=false,start=false,multi=true,overlay=true,mistakes=true}},
  {'Endurance','J',{yield='right',pass='left',flash='always',penalties=false,red=false,traffic=true,multi=true,overlay=true,mistakes=true}},
 }
 for _,row in ipairs(expected) do
  local got=observe(row[1],row[2])
  for key,value in pairs(row[3]) do assert(got[key]==value,row[1]..'/'..row[2]..' '..key..': '..tostring(got[key])..' instead of '..tostring(value)) end
  if row[2]=='C' then assert(got.pass~='no',row[1]..': overtakes in a race') end
 end
 -- Règles de championnat : carburant et pneus de chaque catégorie.
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.defaults(x) end
 local rules={base={'refuel',false},F1={'plan',true},F1_2026={'plan',true},GT={'plan',false},Endurance={'refuel',false}}
 for name,v in pairs(rules) do
  C.applyRules(name,profiles); local p=profiles.C
  assert(p.pitFuel==v[1] and p.pitCompoundChange==v[2] and p.pitTyres,name..': fuel and tyres')
 end
end
-- Beta 1.12 : hotlap : drapeau de départ d'AC levé toute la session repris 5 s seulement ; badge DRS du joueur dans le
-- panneau réduit aux drapeaux d'AC ; disponibilité du DRS notée au journal.
tests.HOTLAP_START_FLAG_AND_DRS=function()
 local L=require('src/lang')
 local e,f=F.scene('J',1); e.profiles.H=C.defaults('H'); e.profiles.H.section_rules=false; e.g.autoProfile=false; e.g.manualProfile='H'; E.select(e,'H'); E.changed(e)
 f.flag=C.K.flagStart; F.tick(e,f,1); assert(e.guard=='nosections' and e.panel.kind=='green' and e.panel.raw==L.flagDetails.start and e.panel.title==L.flagTitles.start and e.panel.short==L.flagShort.startSession,'start flag shown (hotlap: session text)')
 F.tick(e,f,C.K.greenShow+1); assert(e.panel.kind=='none','start flag cleared while AC keeps it raised')
 local me=f.cars[1]; me.drsPresent=true; me.drsAvailable=true; F.tick(e,f,0.5)
 assert(e.panel.kind=='drs' and e.panel.short==L.flagShort.drs,'DRS available badge in hotlap')
 me.drsActive=true; F.tick(e,f,0.5); assert(e.panel.kind=='none','cleared once DRS is opened')
 assert(e.drs.beepId==1 and e.drs.volume==e.profiles.H.drsBeepVolume/100,'DRS beep in hotlap')
 me.drsAvailable=false; F.tick(e,f,0.5); me.drsAvailable=true; F.tick(e,f,0.5); assert(e.drs.beepId==2,'beep again at the next zone')
 e.g.enabled=false; me.drsAvailable=false; F.tick(e,f,0.5); me.drsAvailable=true; F.tick(e,f,0.5); assert(e.drs.beepId==2,'no beep with the app off')
 e.g.enabled=true; me.drsAvailable=false; F.tick(e,f,0.5); me.drsAvailable=true
 local logged=false
 for k=1,e.log.count do local r=e.log[k]; if r and r.message=='DRS joueur: disponible (AC)' then logged=true end end
 assert(logged,'availability logged')
 e.profiles.H.drsAssist=false; E.changed(e); me.drsActive=false; F.tick(e,f,0.5); assert(e.panel.kind=='none','no badge when the preference is off')
end
-- Beta 1.13 : allure libre estimée là où l'IA n'a jamais roulé seule (allure médiane de sa classe × son rythme relatif) :
-- une IA prise dans le trafic se sait retenue derrière une plus lente ; sans rythme relatif appris, rien n'est estimé.
tests.STUCK_WITHOUT_OWN_PACE=function()
 local D=require('src/director')
 local e,f=F.scene('C',3); local s=e.states[2]; local a=f.cars[2]; local row=e.perception.rows[2]; local p=e.run
 local fleet={}; for b=1,C.K.paceBins do fleet[b]=50 end
 for b=1,C.K.paceBins do s.pace[b]=0 end; s.paceCount=0; s.paceRatio=0; s.paceRatioCount=0; s.stuck=0
 -- Rythme relatif appris en conduite libre : 10 % plus rapide que la médiane.
 s.state='DRIVE'; row.free=true; s.lapseUntil=0; s.yellow=false; s.trafficApplied=false; a.pit=false; a.offtrack=false; a.splineValid=true
 for k=1,60 do a.spline=(k-0.5)/C.K.paceBins; a.speed=55; D.pace(s,a,row,1/60,p,fleet) end
 assert(math.abs(s.paceRatio-1.1)<1e-6 and s.paceRatioCount==60,'relative pace learned')
 -- Plus loin, jamais parcouru seul : derrière une voiture plus lente, à 45 m/s.
 row.free=false; a.spline=0.5; a.speed=45
 for _=1,120 do D.pace(s,a,row,1/60,p,fleet) end
 assert(math.abs(s.freePace-55)<1e-6 and s.stuck>1.9,'held up although never driven alone there')
 -- Sans rythme relatif appris : aucune estimation, jamais « retenue ».
 s.paceRatioCount=0; s.stuck=0; for _=1,120 do D.pace(s,a,row,1/60,p,fleet) end
 assert(s.freePace==0 and s.stuck==0,'no estimate without a learned relative pace')
end
-- Beta 1.13 : cycle de vie des drapeaux d'AC dans chaque profil (et app coupée) : titre juste à l'apparition, panneau
-- vide au plus 1 s après la chute du drapeau ; le drapeau de départ s'efface de lui-même.
tests.FLAG_LIFECYCLE_ALL_PROFILES=function()
 local L=require('src/lang')
 local flags={{C.K.flagStop,'black'},{C.K.flagReturnToPits,'penalty'},{C.K.flagFinished,'checkered'},{C.K.flagOneLapLeft,'white'},{C.K.flagFasterCar,'blue'},{C.K.flagCaution,'native'}}
 local presets={J='Nordschleife',P='Essais',Q='Qualifications',C='Course'}
 for _,profile in ipairs({'J','P','Q','C','H','off'}) do
  local e,f=F.scene(profile=='off' and 'C' or profile=='H' and 'J' or profile,3)
  e.profiles.H=C.defaults('H')
  if presets[profile] then C.preset(presets[profile],profile,e.profiles[profile]) end
  local use=profile=='off' and 'C' or profile
  e.g.autoProfile=false; e.g.manualProfile=use; E.select(e,use); E.changed(e)
  if profile=='off' then e.g.enabled=false end
  for i=2,3 do F.place(f,i,(i-1)*800,100) end
  for _,item in ipairs(flags) do
   f.flag=item[1]; F.tick(e,f,0.5)
   local kind=e.panel.kind
   assert(kind==item[2] and e.panel.title==L.flagTitles[kind],profile..': '..item[2]..' shown, got '..kind)
   f.flag=C.K.flagNone; F.tick(e,f,1)
   assert(e.panel.kind=='none' or e.panel.kind=='drs',profile..': '..item[2]..' cleared, still '..e.panel.kind)
  end
  -- Beta 1.38 (maquette) : vert, titre « DÉPART », consigne de la course ou de la séance.
  f.flag=C.K.flagStart; F.tick(e,f,0.5); assert(e.panel.kind=='green' and e.panel.title==L.flagTitles.start and e.panel.short==(use=='C' and L.flagShort.start or L.flagShort.startSession),profile..': start shown')
  F.tick(e,f,C.K.greenShow+1); assert(e.panel.kind=='none',profile..': start cleared although still raised')
  f.flag=C.K.flagNone; F.tick(e,f,0.5)
 end
end
-- Beta 1.14 : consigne courte pour chaque drapeau ; informations non urgentes effacées après la durée réglée, drapeaux
-- jamais ; réglages de l'overlay validés.
tests.OVERLAY_OPTIONS=function()
 local L=require('src/lang'); local Panel=require('src/panel')
 for key in pairs(L.flagDetails) do assert(L.flagShort[key] or key=='scCall' and L.flagShort.scCall,'short instruction for '..key) end
 for _,key in ipairs({'redSession','redSessionPit','greenSession','yellow2','clear'}) do assert(L.flagShort[key],'short '..key) end
 local e,f=F.scene('C',3); local me=f.cars[1]; me.drsPresent=true; f.leaderLaps=5
 e.g.panelInfoTime=3; me.drsAvailable=true; F.tick(e,f,0.5)
 assert(e.panel.kind=='drs' and Panel.visible(e.panel,e.g,e.time),'DRS shown')
 F.tick(e,f,3); assert(e.panel.kind=='drs' and not Panel.visible(e.panel,e.g,e.time),'information hidden after its time')
 me.drsAvailable=false; f.flag=C.K.flagStop; F.tick(e,f,5); assert(e.panel.kind=='black' and Panel.visible(e.panel,e.g,e.time),'flags never hidden')
 e.g.panelInfoTime=0; f.flag=C.K.flagNone; me.drsAvailable=true; F.tick(e,f,10); assert(Panel.visible(e.panel,e.g,e.time),'0: as long as it lasts')
 local g=C.validateGlobals(C.globalDefaults); g.panelOpacity=150; g.panelShow='never'; g.panelInfoTime=-2
 local out,errors=C.validateGlobals(g); assert(out.panelOpacity==86 and out.panelShow=='info' and out.panelInfoTime==0 and errors==3,'invalid values back to defaults')
end
-- Beta 1.15 : Hotlap par défaut (onglet Règles seul) : moteur actif, bip du DRS et badge par le chemin normal.
tests.HOTLAP_DEFAULT_RULES=function()
 local e,f=F.scene('J',1); e.profiles.H=C.defaults('H'); e.g.autoProfile=false; e.g.manualProfile='H'; E.select(e,'H'); E.changed(e)
 local me=f.cars[1]; me.drsPresent=true; F.tick(e,f,0.5); assert(e.guard=='ready','active')
 me.drsAvailable=true; F.tick(e,f,0.5); assert(e.drs.beepId==1 and e.panel.kind=='drs','beep and badge')
 me.drsActive=true; F.tick(e,f,0.5); assert(e.panel.kind=='none','cleared once opened')
 f.flag=C.K.flagCaution; me.drsActive=false; me.drsAvailable=false; F.tick(e,f,0.5); assert(e.panel.kind=='native','game yellow shown')
end
-- Beta 1.16 : interface en français et en anglais. Mêmes clés dans les deux langues (indices et [0] compris), mêmes
-- formats (%d, %s, %.0f, %%) pour chaque texte, mêmes valeurs chiffrées dans chaque infobulle ; toute clé lue par le
-- code existe dans les deux langues.
local function formats(text) local out={}; for spec in text:gmatch('%%[-+#0]*%d*%.?%d*[%a%%]') do out[#out+1]=spec end; return table.concat(out,' ') end
local function sameShape(a,b,path,compare)
 for key,value in pairs(a) do
  local other=b[key]; local where=path..'.'..tostring(key)
  assert(type(other)==type(value),'missing or different type in the other language: '..where)
  if type(value)=='table' then sameShape(value,other,where,compare) elseif compare then compare(value,other,where) end
 end
 for key in pairs(b) do assert(a[key]~=nil,'extra key in the other language: '..path..'.'..tostring(key)) end
end
local function englishTexts() local out={}; for key,value in pairs(require('src/lang_en')) do if key~='labels' then out[key]=value end end; return out end
tests.LANG_PARITY=function()
 assert(require('src/locale').current=='fr','unit tests run in French')
 local L=require('src/lang'); local en=require('src/lang_en')
 sameShape(L,englishTexts(),'lang',function(fr,other,where)
  assert(type(fr)~='string' or formats(fr)==formats(other),'format specifiers differ: '..where..' ('..formats(fr)..' / '..formats(other)..')')
 end)
 -- Niveaux du journal comparés à celui de chaque ligne : seul « tous » se traduit.
 for i=2,5 do assert(en.logLevels[i]==L.logLevels[i],'log level kept: '..i) end
 assert(L.decimalMark==',' and en.decimalMark=='.','decimal separator')
 local root=package.path:match('^([^;]+)/%?%.lua')
 for _,name in ipairs({'AdvancedIA.lua','src/ui.lua','src/panel.lua'}) do
  local file=assert(openFile(root..'/'..name,'rb')); local text=file:read('*a'); file:close()
  for key in text:gmatch('%f[%w_]L%.([%a_][%w_]*)') do assert(L[key]~=nil and en[key]~=nil,'text key used but missing: '..name..': '..key) end
  for key in text:gmatch('%f[%w_]Lang%.([%a_][%w_]*)') do assert(L[key]~=nil and en[key]~=nil,'text key used but missing: '..name..': '..key) end
 end
end
local function numbers(text)
 local out={}
 for n in text:gsub('(%d),(%d)','%1.%2'):gmatch('%d[%d%.]*') do out[(n:gsub('%.$',''))]=true end
 return out
end
tests.TIPS_PARITY=function()
 assert(require('src/locale').current=='fr','unit tests run in French')
 sameShape(require('src/tips'),require('src/tips_en'),'tips',function(fr,en,where)
  local a,b=numbers(fr),numbers(en)
  for n in pairs(a) do assert(b[n],'number '..n..' missing in English: '..where) end
  for n in pairs(b) do assert(a[n],'number '..n..' added in English: '..where) end
 end)
end
-- Textes anglais : aucune lettre ni mot français, une infobulle propre et un libellé pour chaque réglage.
tests.TIPS_COMPLETE_EN=function()
 local T=require('src/tips_en'); local en=require('src/lang_en')
 local accents={'é','è','à','ê','ù','ç','â','î','ô','û','œ','É','È','À','«','»'}
 local function english(text,name)
  for _,ch in ipairs(accents) do assert(not text:find(ch,1,true),'French letter in English text: '..name..' ('..ch..')') end
  for _,word in ipairs({' les ',' des ',' une ',' pour ',' avec ',' dans ',' est ',' sur '}) do assert(not text:lower():find(word,1,true),'French word in '..name..': '..word) end
 end
 local function walk(t,path) for key,value in pairs(t) do local where=path..'.'..tostring(key); if type(value)=='table' then walk(value,where) else english(value,where) end end end
 walk(T,'tips'); walk(en,'lang')
 local seen={}
 for _,s in ipairs(C.schema) do
  local text=T.settings[s.key]
  assert(type(text)=='string' and #text>=40 and not seen[text],'English tooltip missing, short or duplicated: '..s.key); seen[text]=true
  assert(type(en.labels[s.key])=='string' and en.labels[s.key]~='','English label missing: '..s.key)
 end
 local count=0
 for key in pairs(en.labels) do count=count+1; local found=false; for _,s in ipairs(C.schema) do if s.key==key then found=true end end; assert(found,'label for unknown setting: '..key) end
 assert(count==#C.schema,'one English label per setting')
end
-- Bascule en place : les modules qui tiennent les tables voient la nouvelle langue ; retour au français à l'identique.
tests.LOCALE_ROUND_TRIP=function()
 local Locale=require('src/locale'); local L=require('src/lang'); local T=require('src/tips')
 assert(Locale.current=='fr','unit tests run in French')
 local function copy(t) if type(t)~='table' then return t end; local out={}; for k,v in pairs(t) do out[k]=copy(v) end; return out end
 local function equal(a,b)
  if type(a)~='table' or type(b)~='table' then return a==b end
  for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
 end
 local lang,tips,labels=copy(L),copy(T),{}; for i,s in ipairs(C.schema) do labels[i]=s.label end
 local tabs,flags,settings=L.tabs,L.flagTitles,T.settings
 local ok,err=pcall(function()
  assert(Locale.set('en') and Locale.current=='en' and not Locale.set('en'),'switched once')
  assert(L.tabs==tabs and L.flagTitles==flags and T.settings==settings,'same tables, filled in place')
  assert(L.tabs.home=='HOME' and L.flagTitles.red=='RED FLAG' and L.decimalMark=='.' and T.settings.levelPct:find('Content Manager',1,true) and C.schema[1].label=='Level (%)','English filled in place')
  assert(L.labels==nil,'English labels never copied into the texts')
  assert(not Locale.set('de') and Locale.current=='en','unknown language refused')
  assert(Locale.set('fr') and Locale.current=='fr')
 end)
 if Locale.current~='fr' then Locale.set('fr') end
 assert(ok,err)
 assert(equal(L,lang) and equal(T,tips),'French restored exactly')
 for i,s in ipairs(C.schema) do assert(s.label==labels[i],'French label restored: '..s.key) end
end
-- Langue enregistrée : anglais à la première installation, français gardé pour une installation existante.
tests.MIGRATION_LANGUAGE=function()
 local function run(stored)
  local profiles={}; for _,p in ipairs(C.profiles) do profiles[p]=C.validate(p,C.defaults(p)) end
  local g=C.validateGlobals(stored); C.migrate(g,profiles); return g
 end
 assert(C.globalDefaults.language=='en' and run({}).language=='en','first install in English')
 assert(run({schemaVersion=3,dataRevision=8,presetsUsed=true}).language=='fr','Beta 1.15 install kept in French')
 assert(run({schemaVersion=3,dataRevision=3}).language=='fr','older install kept in French')
 assert(run({schemaVersion=3,dataRevision=9,language='en'}).language=='en','choice kept once migrated')
 assert(C.validateGlobals({language='de'}).language=='en','unknown language replaced')
 for _,key in ipairs(C.globalRuntimeKeys) do assert(key~='language','language never carried by a custom preset') end
end
-- Beta 1.18 : voiture de sécurité en escalade. VSC sur l'incident majeur ; deuxième voiture immobilisée en piste, ou
-- dépannage long : la voiture de sécurité est appelée puis sort ; sans l'option ou sans voiture de sécurité sur la
-- grille, la VSC reste ; voiture de sécurité immobilisée en piste : la neutralisation continue en FCY.
tests.SAFETY_CAR_ESCALATION=function()
 local function scene(escalate,model,neutralization)
  local e,f=F.scene('C',6); local p=e.profiles.C
  p.neutralization=neutralization or 'vsc'; p.safetyCarEscalation=escalate; p.redFlagEnabled=false; e.g.safetyCarModel=model or 'sc_car'; E.changed(e)
  f.cars[6].id='sc_car'
  for i=2,5 do F.place(f,i,(i-2)*400,150) end
  F.place(f,6,7000,0); f.cars[6].pit=true; f.cars[6].inPitBox=true
  F.tick(e,f,1)
  F.place(f,4,5000,0); F.tick(e,f,18)
  return e,f,e.incidents
 end
 local e,f,t=scene(true)
 assert(t.neutral and t.neutralMode=='vsc' and t.safetyPhase=='parked' and t.safety==6,'one car stopped on track: VSC first')
 F.place(f,5,3000,0); F.tick(e,f,17)
 assert(t.neutral and t.neutralMode=='sc' and t.escalated and t.safetyPhase=='call' and t.messageKind=='sc' and not t.ending,'second car stopped: safety car called')
 F.tick(e,f,11); assert(t.safetyPhase=='place' and not e.commands[6].scPark and e.commands[6].place>=0,'released after the call time, placed on track')
 -- Piste dégagée : la voiture de sécurité reste en piste, rentre au tour suivant, drapeau vert à l'entrée des stands.
 f.cars[6].pit=false; f.cars[6].inPitBox=false; F.place(f,6,e.commands[6].place*f.length,120); F.tick(e,f,0.1)
 F.place(f,6,1000,120); F.place(f,4,5000,150); F.place(f,5,3000,150)
 F.tick(e,f,5); assert(t.neutral and t.neutralMode=='sc' and t.safetyPhase=='out','incident cleared: the safety car stays out')
 F.tick(e,f,60); assert(t.neutral and t.safetyPhase=='in' and t.messageKind=='scIn','in this lap')
 f.cars[6].pit=true; F.tick(e,f,0.5)
 assert(not t.neutral and t.messageKind=='restart' and t.restart and not t.escalated,'green at the pit entry, no overtaking until the line')
 -- Voiture de sécurité immobilisée en piste : la neutralisation continue en FCY jusqu'au bout de sa durée minimale.
 e,f,t=scene(true); F.place(f,5,3000,0); F.tick(e,f,28)
 assert(t.safetyPhase=='place' and e.commands[6].place>=0)
 f.cars[6].pit=false; f.cars[6].inPitBox=false; F.place(f,6,e.commands[6].place*f.length,0); F.tick(e,f,C.K.scStuckTime+1)
 assert(t.neutral and t.neutralMode=='fcy' and t.safetyFailed,'safety car unavailable: FCY carries on')
 f.cars[6].pit=true; F.place(f,4,5000,150); F.place(f,5,3000,150); F.tick(e,f,5)
 assert(t.neutral and t.neutralMode=='fcy','FCY kept for its minimum time once the track is clear')
 F.tick(e,f,40); assert(not t.neutral,'then green')
 e,f,t=scene(false); F.place(f,5,3000,0); F.tick(e,f,17)
 assert(t.neutral and t.neutralMode=='vsc' and not t.escalated and t.safetyPhase=='parked','no escalation without the option')
 e,f,t=scene(true); F.tick(e,f,24)
 assert(t.neutral and t.neutralMode=='vsc','long recovery: not yet')
 F.tick(e,f,5); assert(t.neutralMode=='sc' and t.escalated,'long recovery: safety car')
 e,f,t=scene(true,'missing'); F.place(f,5,3000,0); F.tick(e,f,17)
 assert(t.neutral and t.neutralMode=='vsc' and t.safety==0,'no safety car on the grid: VSC kept')
 -- Beta 1.19 : règles de base (zone jaune locale seule) : la voiture de sécurité sort directement quand l'incident
 -- s'aggrave ; jamais hors course.
 e,f,t=scene(true,nil,'local'); assert(not t.neutral,'local yellow zone only: no neutralisation for one car')
 F.place(f,5,3000,0); F.tick(e,f,17)
 assert(t.neutral and t.neutralMode=='sc' and t.escalated and t.safetyPhase=='call','second car stopped: safety car straight from the local yellow')
 e,f,t=scene(true,'missing','local'); F.place(f,5,3000,0); F.tick(e,f,17)
 assert(not t.neutral and not t.escalated and t.safety==0,'local yellow without a safety car on the grid: stays local')
 local q,fq=F.scene('Q',6); q.profiles.Q.safetyCarEscalation=true; q.profiles.Q.redFlagEnabled=false; q.g.safetyCarModel='sc_car'; E.changed(q); fq.cars[6].id='sc_car'
 for i=2,5 do F.place(fq,i,(i-2)*400,150) end; F.place(fq,6,7000,0); fq.cars[6].pit=true; fq.cars[6].inPitBox=true; F.tick(q,fq,1)
 F.place(fq,4,5000,0); F.place(fq,5,3000,0); F.tick(q,fq,20); assert(not q.incidents.neutral,'never outside the race')
end
-- Interrupteurs de l'onglet Règles de course : Essais, Qualifications et Course ensemble ; nombre d'arrêts gardé ;
-- préréglage recommandé d'abord pour un profil jamais réglé ; chaque jeu de règles les règle.
tests.WEEKEND_SWITCHES=function()
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.validate(x,C.defaults(x)) end
 C.applyRules('F1',profiles)
 C.weekendSwitch(profiles,'mandatoryStops',false)
 for _,x in ipairs(C.ruleProfiles) do assert(profiles[x].mandatoryStops==0 and profiles[x].configured,x..': no mandatory stop') end
 assert(C.ruleCategory('C',profiles.C)==nil and profiles.J.mandatoryStops==0,'custom rules, track day untouched')
 C.weekendSwitch(profiles,'mandatoryStops',true); assert(profiles.C.mandatoryStops==1 and C.ruleCategory('C',profiles.C)=='F1','back to F1')
 -- Beta 1.51 : arrêt obligatoire oui ou non (un seul arrêt imposé) ; 2 ou 3 enregistrés deviennent 1.
 profiles.C.mandatoryStops=1; C.weekendSwitch(profiles,'mandatoryStops',true); assert(profiles.C.mandatoryStops==1 and profiles.P.mandatoryStops==1,'one stop kept')
 do local old=C.defaults('C'); old.mandatoryStops=3; local out,errors=C.validate('C',old); assert(out.mandatoryStops==1 and errors==0,'3 saved stops become 1, no error') end
 C.weekendSwitch(profiles,'safetyCarEscalation',false); for _,x in ipairs(C.ruleProfiles) do assert(profiles[x].safetyCarEscalation==false,x) end
 C.weekendSwitch(profiles,'safetyCarEscalation',true); assert(profiles.Q.safetyCarEscalation==true)
 local fresh={}; for _,x in ipairs(C.profiles) do fresh[x]=C.validate(x,C.defaults(x)) end
 C.weekendSwitch(fresh,'safetyCarEscalation',true)
 assert(fresh.C.configured and fresh.C.section_blue and fresh.C.safetyCarEscalation,'recommended preset applied first')
 local expected={base={0,true},F1={1,true},F1_2026={1,true},GT={1,true},Endurance={0,true}}
 for _,name in ipairs(C.ruleCategories) do
  local v=expected[name]; C.applyRules(name,profiles)
  for _,x in ipairs(C.ruleProfiles) do assert(profiles[x].mandatoryStops==v[1] and profiles[x].safetyCarEscalation==v[2],name..' '..x) end
 end
end
-- Révisions 10 et 11 (Beta 1.18 et 1.19) : voiture de sécurité activée en course pour les essais, qualifications et
-- course, quels que soient les jeux de règles (base comprise) ; anciennes révisions jugées sans la nouvelle clé, dans
-- l'ordre ; préréglages personnels des Beta 1.12 à 1.18 aussi ; Ferrari 458 Italia Stage 3 si aucun modèle n'était choisi.
tests.MIGRATION_SAFETY_CAR=function()
 local function weekend() local out={}; for _,x in ipairs(C.profiles) do out[x]=C.validate(x,C.defaults(x)) end; return out end
 local function stored(category,revision,change)
  local profiles=weekend(); C.applyRules(category,profiles)
  for _,x in ipairs(C.ruleProfiles) do profiles[x].safetyCarEscalation=false; if change then change(profiles[x]) end end
  C.migrate(C.validateGlobals({schemaVersion=3,dataRevision=revision or 10,presetsUsed=true}),profiles)
  return profiles
 end
 for _,category in ipairs(C.ruleCategories) do
  local profiles=stored(category)
  for _,x in ipairs(C.ruleProfiles) do assert(profiles[x].safetyCarEscalation and C.ruleCategory(x,profiles[x])==category,category..' '..x..': safety car on, rules recognised') end
  assert(not profiles.J.safetyCarEscalation and not profiles.H.safetyCarEscalation,'track day and hotlap untouched')
 end
 local custom=stored('F1',9,function(p) p.mandatoryStops=2 end)
 assert(custom.C.safetyCarEscalation and custom.C.mandatoryStops==2,'custom rules: safety car on, the rest kept')
 local gt=stored('GT',5,function(p) p.pitsClosed='pitFcy' end)
 assert(gt.C.pitsClosed=='open' and gt.C.safetyCarEscalation and C.ruleCategory('C',gt.C)=='GT','Beta 1.8 GT data migrated in order')
 local f1=stored('F1',6,function(p) p.pitFuel='refuel' end)
 assert(f1.C.pitFuel=='plan' and f1.C.safetyCarEscalation and C.ruleCategory('C',f1.C)=='F1','Beta 1.11 F1 data migrated in order')
 local Presets=require('src/presets')
 for _,revision in ipairs({8,9}) do
  local set=weekend(); C.applyRules('base',set); local p=set.C; p.safetyCarEscalation=false
  local store=Presets.layout(); store.name='Ancien'; store.profile='C'; store.revision=revision
  for k,v in pairs(p) do store['p_'..k]=v end
  local entry=Presets.decode(store)
  assert(entry.p.safetyCarEscalation and C.ruleCategory('C',entry.p)=='base' and Presets.encode(entry).revision==14,'revision '..revision..' custom preset updated')
 end
 -- Modèle par défaut : Ferrari 458 Italia Stage 3 du jeu de base ; un choix existant est gardé.
 assert(C.validateGlobals({}).safetyCarModel=='ferrari_458_s3','first install: Ferrari 458 Italia Stage 3')
 local g=C.validateGlobals({schemaVersion=3,dataRevision=10,presetsUsed=true,safetyCarModel=''}); C.migrate(g,weekend())
 assert(g.safetyCarModel=='ferrari_458_s3','no model chosen: default given at the update')
 g=C.validateGlobals({schemaVersion=3,dataRevision=10,presetsUsed=true,safetyCarModel='aston_vantage2018'}); C.migrate(g,weekend())
 assert(g.safetyCarModel=='aston_vantage2018','chosen model kept')
end
-- Beta 1.19 : réinitialisation de l'onglet Règles de course : jeu de règles exact, ou le plus proche d'un jeu retouché.
tests.RULES_CLOSEST=function()
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.validate(x,C.defaults(x)) end
 for _,name in ipairs(C.ruleCategories) do C.applyRules(name,profiles); assert(C.closestRuleCategory('C',profiles.C)==name,name) end
 C.applyRules('F1',profiles); profiles.C.pitWindowOpenPct=30; profiles.C.mandatoryStops=0
 assert(C.ruleCategory('C',profiles.C)==nil and C.closestRuleCategory('C',profiles.C)=='F1','retouched F1 is closest to F1')
 local skip={mandatoryStops=true,safetyCarEscalation=true}
 C.applyRules('base',profiles); profiles.C.mandatoryStops=1; profiles.C.safetyCarEscalation=true
 assert(C.ruleCategory('C',profiles.C,skip)=='base' and C.closestRuleCategory('C',profiles.C,skip)=='base','switches ignored')
 -- Égalité : le premier de la liste (F1 2025 avec l'Overtake Mode : aussi proche de F1 2025 que de F1 2026).
 C.applyRules('F1',profiles); profiles.C.overtakeMode=true; assert(C.closestRuleCategory('C',profiles.C)=='F1','tie: first in the list')
end
-- Beta 1.19 : modèle par défaut (Ferrari 458 Italia Stage 3) jamais choisi : porté par plusieurs voitures, ce sont des
-- concurrentes, aucune n'est garée (sauf celle à la livrée de voiture de sécurité) ; un modèle choisi, ou une seule
-- voiture de ce modèle, garde le comportement de la Beta 1.4.
tests.SAFETY_CAR_DEFAULT_MODEL=function()
 for _,profile in ipairs({'J','Q','C'}) do
  local e,f=F.scene(profile,12); E.select(e,profile); e.g.safetyCarModel='ferrari_458_s3'; e.g.safetyCarPicked=false; E.changed(e)
  for i=2,11 do f.cars[i].id='ferrari_458_s3' end
  F.tick(e,f,1)
  local parked=0; for i=1,f.count do if f.cars[i].safetyCar then parked=parked+1 end end
  assert(parked==0 and e.incidents.safety==0 and e.safetyOneMake,profile..': ten AI on the default model keep racing')
  f.cars[7].skinSafety=true; F.tick(e,f,1)
  parked=0; for i=1,f.count do if f.cars[i].safetyCar then parked=parked+1 end end
  assert(parked==1 and e.incidents.safety==7,profile..': only the safety car livery')
  f.cars[7].skinSafety=false; for i=2,11 do f.cars[i].id='model_'..i end; f.cars[12].id='ferrari_458_s3'; F.tick(e,f,1)
  assert(e.incidents.safety==12 and not e.safetyOneMake,profile..': one car of the default model is the safety car')
  f.cars[11].id='ferrari_458_s3'; e.g.safetyCarPicked=true; F.tick(e,f,1)
  assert(e.incidents.safety>0 and f.cars[11].safetyCar and f.cars[12].safetyCar and not e.safetyOneMake,profile..': chosen model: Beta 1.4 reserves')
 end
 -- Mise à jour : un modèle choisi avant la Beta 1.19 l'a été par le pilote ; un modèle vide reçoit le défaut, non choisi.
 local function weekend() local out={}; for _,x in ipairs(C.profiles) do out[x]=C.validate(x,C.defaults(x)) end; return out end
 local g=C.validateGlobals({schemaVersion=3,dataRevision=10,presetsUsed=true,safetyCarModel='aston_vantage2018'}); C.migrate(g,weekend())
 assert(g.safetyCarPicked and g.safetyCarModel=='aston_vantage2018','chosen before: picked')
 g=C.validateGlobals({schemaVersion=3,dataRevision=10,presetsUsed=true,safetyCarModel=''}); C.migrate(g,weekend())
 assert(not g.safetyCarPicked and g.safetyCarModel=='ferrari_458_s3','empty before: default, not picked')
 g=C.validateGlobals({}); C.migrate(g,weekend()); assert(not g.safetyCarPicked and g.safetyCarModel=='ferrari_458_s3','first install: default, not picked')
end
-- Beta 1.20 : réparations en course à chaque passage d'une IA endommagée à son emplacement, retenue le temps de la
-- réparation ; rien sans dégât notable, hors course, réparations coupées ou onglet Règles décoché. Endurance : carburant
-- libre, pneus et réparations à chaque arrêt, relais maximal, aucun arrêt imposé.
tests.PIT_REPAIR=function()
 local Pits=require('src/pits')
 local e,f=F.scene('C',4); local p=e.profiles.C
 assert(p.pitRepair and e.run.pitRepair,'on by default in the race')
 local a=f.cars[2]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0; a.damageBody=120; a.damageSuspension=0.3; a.engineLife=900
 local expected=math.min(C.K.repairMax,C.K.repairBase+120*C.K.repairBodyRate+0.3*C.K.repairSuspensionRate+0.1*C.K.repairEngineTime)
 F.tick(e,f,0.5)
 assert(e.commands[2].pitRepair and e.commands[2].pitHold and math.abs(e.pits.cars[2].repairTime-expected)<1e-6,'damaged car repaired and held ('..e.pits.cars[2].repairTime..')')
 F.tick(e,f,expected); assert(e.commands[2].pitRepair and not e.commands[2].pitHold,'released after the repair time')
 local b=f.cars[3]; b.pit=true; b.inPitBox=true; b.kmh=0; b.speed=0; F.tick(e,f,0.5)
 assert(not e.commands[3].pitRepair and not e.commands[3].pitHold,'no damage: no repair')
 local function revisit() a.inPitBox=false; F.tick(e,f,0.2); a.inPitBox=true; F.tick(e,f,0.5) end
 p.pitRepair=false; E.changed(e); revisit(); assert(not e.commands[2].pitRepair and not e.commands[2].pitHold,'repairs off')
 p.pitRepair=true; p.section_rules=false; E.changed(e); revisit(); assert(not e.commands[2].pitRepair,'rules tab unchecked: no repair')
 p.section_rules=true; E.changed(e); revisit(); assert(e.commands[2].pitRepair,'on again at the next visit')
 local q,fq=F.scene('Q',3); local c=fq.cars[2]; c.pit=true; c.inPitBox=true; c.kmh=0; c.speed=0; c.damageBody=200
 -- Beta 1.41 : hors course, réparée à son emplacement (dépannage de l'app ou arrêt natif), jamais retenue.
 F.tick(q,fq,0.5); assert(q.commands[2].pitRepair and not q.commands[2].pitHold,'outside the race: repaired, never held')
 q.profiles.Q.section_accidents=false; E.changed(q); F.tick(q,fq,0.5); assert(not q.commands[2].pitRepair,'accidents tab unchecked: no repair')
 -- Drapeau rouge : réparations seulement si les règles y permettent le travail (F1), comme les pneus.
 local red=Pits.new(); local cmds={}; for i=1,fq.count do cmds[i]={} end
 local run={}; for k,v in pairs(q.run) do run[k]=v end; run.pitRepair=true; run.redFlagWork=false
 Pits.update(red,fq,cmds,run,'C',100,1,nil,true,nil,false); assert(not cmds[2].pitRepair,'red flag without work: no repair')
 run.redFlagWork=true; red=Pits.new(); Pits.update(red,fq,cmds,run,'C',100,1,nil,true,nil,false); assert(cmds[2].pitRepair,'red flag with work allowed: repaired')
 assert(Pits.repairTime({damageBody=4,damageSuspension=0.01,engineLife=995})==0,'light damage: nothing to repair')
 assert(Pits.repairTime({damageBody=5000,damageSuspension=1,engineLife=0})==C.K.repairMax,'capped')
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.validate(x,C.defaults(x)) end
 C.applyRules('Endurance',profiles)
 for _,x in ipairs(C.ruleProfiles) do
  local r=profiles[x]
  assert(r.pitFuel=='refuel' and r.pitTyres and r.pitRepair and r.maxStintMin==50 and r.mandatoryStops==0 and C.ruleCategory(x,r)=='Endurance','Endurance '..x)
 end
end
-- Beta 1.20 : Endurance : réservoir plus petit que le relais : plein complet à l'arrêt de fin de relais, puis arrêt natif
-- de ravitaillement avant la fin du relais (ravitaillement libre au fil de la course).
tests.FUEL_SHORT_TANK=function()
 local Pits=require('src/pits')
 local e,f=F.scene('C',3); local p=e.run; local t=Pits.new()
 f.started=true; f.sessionLaps=60; f.timedRace=false; f.fuelRate=1; f.track='test'
 for i=1,3 do local a=f.cars[i]; a.fuel=8; a.maxFuel=30; a.fuelPerLap=2; a.lap=10; a.pit=false end
 p.pitFuel='refuel'; p.mandatoryStops=0; p.maxStintMin=50
 for i=1,3 do e.commands[i].rulePit=i==2 end
 t.cars[2].lapTime=100
 Pits.fuel(t,f,e.commands,p,'C',100,false)
 local reserve=2*C.K.fuelReserveLaps; local cmd=e.commands[2]
 assert(math.abs(cmd.fuelTarget-30)<1e-6 and cmd.fuelLaps==math.floor((30-reserve)/2) and cmd.fuelLaps<30,'tank smaller than the stint: full tank, native stop before the end of the stint')
end
-- Beta 1.20 : espacement élargi : des valeurs restées aux anciens défauts les suivent, des valeurs réglées restent ;
-- préréglages personnels de la Beta 1.19 aussi.
tests.TRAFFIC_MIGRATION=function()
 local function weekend() local out={}; for _,x in ipairs(C.profiles) do out[x]=C.validate(x,C.defaults(x)) end; return out end
 local function old(p) p.trafficGapSeconds=1.2; p.trafficVariation=35; p.trafficMaxReduction=10 end
 local profiles=weekend(); old(profiles.J)
 C.migrate(C.validateGlobals({schemaVersion=3,dataRevision=11,presetsUsed=true}),profiles)
 local j=profiles.J
 assert(j.trafficGapSeconds==2.5 and j.trafficVariation==45 and j.trafficMaxReduction==14,'old defaults follow')
 local custom=weekend(); old(custom.J); custom.J.trafficGapSeconds=1.8
 C.migrate(C.validateGlobals({schemaVersion=3,dataRevision=11,presetsUsed=true}),custom)
 assert(custom.J.trafficGapSeconds==1.8 and custom.J.trafficVariation==45 and custom.J.trafficMaxReduction==14,'tuned value kept, untouched ones follow')
 local same=weekend(); same.J.trafficGapSeconds=1.8
 C.migrate(C.validateGlobals({schemaVersion=3,dataRevision=12,presetsUsed=true}),same)
 assert(same.J.trafficGapSeconds==1.8,'current data untouched')
 local Presets=require('src/presets')
 local p=weekend().J; old(p)
 local store=Presets.layout(); store.name='Ancien'; store.profile='J'; store.revision=10
 for k,v in pairs(p) do store['p_'..k]=v end
 local entry=Presets.decode(store)
 assert(entry.p.trafficGapSeconds==2.5 and entry.p.trafficVariation==45 and Presets.encode(entry).revision==14,'Beta 1.19 custom preset updated')
end
-- Beta 1.21 : dans une file, pas de cession pour une voiture à peine plus rapide, ni à la pression, ni sur l'appel de
-- phares d'une IA : elle ne passerait pas et toute la file ralentirait (train de voitures identiques en journée circuit,
-- 29 octobre : 12 IA sur 19 en cession) ; piste libre devant, ou suiveur nettement plus rapide : cession.
tests.QUEUE_YIELD=function()
 local function run(ahead,sa,pressure)
  local e,f=F.scene('J',4); e.p.personalLineJitter=0; E.changed(e)
  F.rear(e,f,pressure and 8 or 20,sa)
  F.place(f,4,ahead+4.4,100)
  local yielded=false
  for _=1,(pressure and 8 or 5)*6 do F.tick(e,f,1/6); if F.yielding(e.states[2].state) then yielded=true end end
  return yielded
 end
 assert(not run(30,10),'30 m behind a car: no yield for a car 10 km/h faster')
 assert(run(500,10),'free road ahead: yields')
 assert(not run(30,0,true),'queue: no yield to pressure')
 assert(run(500,0,true),'free road: yields to pressure')
 assert(run(30,30),'much faster follower: yields even in a queue')
 local function flashed(ahead)
  local e,f=F.scene('J',4); local p=e.profiles.J
  p.aiFlashEnabled=true; p.pressureEnabled=false; p.multiClass=false; E.changed(e)
  F.place(f,2,0,100); F.place(f,3,29.4,100); F.place(f,4,29.4+ahead,100)
  local s=e.states[2]; for b=1,C.K.paceBins do s.pace[b]=50 end; s.paceCount=C.K.paceBins; s.paceMean=50
  local yielded=false
  for _=1,8*60 do F.tick(e,f,1/60); if F.yielding(e.states[3].state) then yielded=true end end
  return e.commands[2].flashEvent>0,yielded
 end
 local flash,yielded=flashed(30)
 assert(flash and not yielded,'AI flash in a queue: the car ahead does not yield')
 flash,yielded=flashed(500)
 assert(flash and yielded,'AI flash with free road ahead: yields')
end
-- Beta 1.22 : essais et qualifications, beaucoup de voitures (au moins spawnMinCars IA à leur emplacement) : sorties
-- des stands étalées par l'attente native, dans un ordre tiré au sort, au moins (1 - jitter) fois l'écart l'une de
-- l'autre ; attente annulée dès qu'une IA quitte son emplacement avant son tour ; une fois par session, de nouveau au
-- redémarrage ; ni en journée circuit, ni en course, ni avec peu de voitures, ni en cours de session, ni à 0.
tests.PIT_EXIT_SPREAD=function()
 local function boxed(profile,count,time,spread)
  local e,f=F.scene(profile,count or 12); E.select(e,profile)
  if spread then e.profiles[profile].pitExitSpread=spread end; E.changed(e)
  f.session=1; f.time=time or 5
  for i=2,f.count do local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0 end
  F.tick(e,f,0.1)
  return e,f
 end
 local e,f=boxed('Q')
 local x=e.traffic.exits; local spread=e.run.pitExitSpread; local delays={}
 assert(spread==10 and x.count==11,'qualifying: 10 s per AI by default, every AI in its box')
 assert(e.profiles.J.pitExitSpread==0 and e.profiles.C.pitExitSpread==0 and e.profiles.P.pitExitSpread==10,'practice and qualifying only')
 for i=2,12 do
  local d=x.releaseAt[i]-x.at; assert(d>=0 and d<11*spread,'delay '..i..': '..d); delays[#delays+1]=d
  local cmd=e.commands[i]
  if d>0.5 then assert(cmd.startDelay>0 and math.abs(cmd.startDelay-(x.releaseAt[i]-e.time))<0.05,'native wait until its turn: '..i) end
  assert(not cmd.scPark and not cmd.pitHold,'never parked nor braked: '..i)
 end
 table.sort(delays)
 for k=2,#delays do assert(delays[k]-delays[k-1]>=spread*(1-C.K.pitExitJitter)-1e-6,'staggered') end
 assert(delays[1]<spread and e.commands[1].startDelay<0,'first one soon, never the player')
 -- Sortie avant son tour (voiture déplacée) : attente annulée aussitôt, notée au journal.
 local late; for i=2,12 do if x.releaseAt[i]-x.at>3*spread then late=i end end
 assert(late,'a car released later')
 f.cars[late].inPitBox=false; F.tick(e,f,1/60)
 assert(e.commands[late].startDelay==0 and x.exited[late],'left early: wait cancelled')
 local logged=false
 for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('attente annulee',1,true) and r.index==late then logged=true end end
 assert(logged,'early exit logged')
 F.tick(e,f,0.1); assert(e.commands[late].startDelay<0,'cancelled once')
 local draws=x.draws; f.time=6; F.tick(e,f,1); assert(x.draws==draws,'once per session')
 F.tick(e,f,11*spread); for i=2,12 do assert(e.commands[i].startDelay<0,'everybody released: '..i) end
 f.time=1; F.tick(e,f,0.1); assert(x.draws==draws+1 and x.count==10,'restart: drawn again (10 AI still in their box)')
 local p=boxed('P'); assert(p.traffic.exits.count==11,'practice too')
 -- Beta 1.26 : journée circuit répartie sur tout le circuit par défaut (aucune attente) ; course : jamais (grille).
 local j=boxed('J',12,5,10); assert(j.traffic.exits.count==8 and j.traffic.exits.kept==3 and j.traffic.exits.mode=='track','track day: spread on track, a quarter kept in the pits')
 for i=2,12 do assert(j.commands[i].startDelay<0,'track day: nobody waits '..i) end
 for _,case in ipairs({{'C',12,5,10},{'Q',8},{'Q',12,200},{'Q',12,5,0}}) do
  local q,fq=boxed(case[1],case[2],case[3],case[4])
  assert(q.traffic.exits.count==0,case[1]..' '..tostring(case[2])..' '..tostring(case[3])..': no staggered exit')
  for i=2,fq.count do assert(q.commands[i].startDelay<0,case[1]..': nobody waits') end
 end
end
-- Beta 1.23 : sorties étalées plafonnées : toutes dehors en 3 min au plus (au plus le quart d'une session courte) ;
-- l'écart diminue avec beaucoup de voitures, jamais au-delà du réglage ni sous 2 s.
tests.PIT_EXIT_CAP=function()
 local function draw(count,left,spread)
  local e,f=F.scene('Q',count); E.select(e,'Q'); if spread then e.profiles.Q.pitExitSpread=spread end; E.changed(e)
  f.session=1; f.time=5; f.left=left
  for i=2,f.count do local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0 end
  F.tick(e,f,0.1)
  local x=e.traffic.exits; local last=0
  for i=2,f.count do last=math.max(last,x.releaseAt[i]-x.at) end
  return x,last
 end
 local x,last=draw(12,3600)
 assert(math.abs(x.gap-10)<1e-9 and last<11*10,'11 AI: the setting, 10 s')
 x,last=draw(48,3600)
 assert(x.count==47 and x.gap<10 and x.gap>=C.K.pitExitMinGap and last<=C.K.pitExitMaxTotal+1e-6,'47 AI: all out within 3 min ('..x.gap..', '..last..')')
 x,last=draw(48,400)
 assert(last<=400*C.K.pitExitSessionShare+1e-6 and x.gap>=C.K.pitExitMinGap,'short session: at most a quarter of it ('..last..')')
 x=draw(48,120); assert(math.abs(x.gap-C.K.pitExitMinGap)<1e-9,'never under 2 s')
 x=draw(48,0); assert(x.gap<10 and x.gap*(46+C.K.pitExitJitter)<=C.K.pitExitMaxTotal+1e-6,'unknown length: 3 min')
 x=draw(48,3600,1); assert(math.abs(x.gap-1)<1e-9,'never over the setting, even under 2 s')
end
-- Beta 1.24 : radar avant : contact imminent avec la voiture de devant (même file) : léger freinage dosé, monté
-- progressivement (jamais d'un coup), plafonné, relâché progressivement ; rien pour une voiture à côté, sans
-- rapprochement, de loin ni radar coupé ; anticipation par la prudence avant tout freinage.
tests.FRONT_RADAR=function()
 local function scene(gap,sa,lat,assist)
  local e,f=F.scene('C',3); e.startedAt=-100; e.g.useBrakeAssist=assist~=false; E.changed(e)
  F.place(f,2,0,100+sa); F.place(f,3,gap+4.4,100,lat or 0)
  e.states[2].nextPerception=0
  return e,f
 end
 local e,f=scene(6,30)
 local first=0; for _=1,30 do F.tick(e,f,1/60); first=e.commands[2].brake; if first>0 then break end end
 assert(first>0 and first<=C.K.radarApply/60+1e-9,'progressive: no stab of the brakes ('..first..')')
 F.tick(e,f,0.5)
 assert(e.commands[2].brake>first and e.commands[2].brake<=C.K.radarBrakeMax+1e-9,'light braking, capped ('..e.commands[2].brake..')')
 local logged=false
 for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('radar avant:',1,true) and r.index==2 then logged=true end end
 assert(logged,'radar logged')
 F.place(f,3,200,100); F.tick(e,f,1/60); assert(e.commands[2].brake>0,'released progressively, not at once')
 F.tick(e,f,1); assert(e.commands[2].brake==0,'released')
 for _,case in ipairs({{6,30,3},{6,0},{6,30,0,false},{60,30}}) do
  local q,fq=scene(case[1],case[2],case[3],case[4]); F.tick(q,fq,0.5)
  assert(q.commands[2].brake==0,'no radar brake: '..case[1]..' m, '..case[2]..' km/h, '..tostring(case[3])..', '..tostring(case[4]))
 end
 local function anticipation(assist) local w,fw=scene(20,40,0,assist); F.tick(w,fw,0.3); return w.commands[2].caution,w.commands[2].brake end
 local on,brake=anticipation(true); local off=anticipation(false)
 assert(on>off and brake==0,'anticipation: more caution before any braking ('..on..' vs '..off..')')
end
-- Beta 1.24 : voiture immobile cassée (suspension, moteur ou boîte hors d'usage) évacuée bien avant le délai d'une voiture
-- simplement arrêtée ; dégât léger : délai ordinaire.
tests.BROKEN_CAR_RECOVERED=function()
 local function when(field,value)
  local e,f=F.scene('J',3); F.place(f,3,5000,0); if field then f.cars[3][field]=value end
  for k=1,40 do F.tick(e,f,0.5); if e.commands[3].recover then return k*0.5,e.commands[3].recoverReason end end
  return math.huge,nil
 end
 local plain=when()
 assert(plain>=C.K.trackRecoverTime and plain<C.K.trackRecoverTime+6,'stopped on track: about 8 s ('..plain..')')
 for _,case in ipairs({{'damageSuspension',0.8},{'engineLife',0},{'damageGearbox',1}}) do
  local t,reason=when(case[1],case[2])
  assert(t<plain and t>=C.K.brokenRecoverTime and reason=='cassee',case[1]..': evacuated early ('..t..', '..tostring(reason)..')')
 end
 local light=when('damageSuspension',0.2); assert(light==plain,'light damage: not broken')
end
-- Beta 1.24 : voiture ramenée à son stand par l'app (dépannage) ou voiture de sécurité : aucun arrêt compté ; un vrai
-- arrêt l'est.
tests.TOWED_NOT_A_STOP=function()
 local Pits=require('src/pits')
 local e,f=F.scene('C',5); local run={}; for k,v in pairs(e.run) do run[k]=v end
 run.mandatoryStops=1; run.pitWindowOpenPct=25; run.pitWindowClosePct=75
 f.sessionLaps=10; f.leaderLaps=5; f.timedRace=false
 local t=Pits.new(); local cmds={}; for i=1,f.count do cmds[i]={} end
 local now=100
 local function step() now=now+0.5; Pits.update(t,f,cmds,run,'C',now,1,nil,false,nil,false) end
 step()
 local a=f.cars[2]; a.pit=true; a.inPitBox=true; a.teleport=true; step(); a.teleport=false; step()
 assert(t.cars[2].stops==0 and t.cars[2].windowStops==0,'towed to its stand: no stop counted')
 a.inPitBox=false; a.pit=false; for _=1,8 do step() end; a.pit=true; a.inPitBox=true; step()
 assert(t.cars[2].stops==1 and t.cars[2].windowStops==1,'a real stop counts')
 local sc=f.cars[3]; sc.safetyCar=true; sc.pit=true; sc.inPitBox=true; step()
 assert(t.cars[3].stops==0,'safety car: no stop counted')
 local red=f.cars[4]; red.pit=true; red.inPitBox=true; red.teleport=true; now=now+0.5; Pits.update(t,f,cmds,run,'C',now,1,nil,true,nil,false)
 assert(t.cars[4].stops==1,'red flag: every car returns to the pits, counted as before')
 -- Emplacement signalé une image après le dépannage : toujours pas un arrêt ; un vrai arrêt plus tard l'est.
 local late=f.cars[5]; cmds[5].recover=true; step(); cmds[5].recover=false; late.pit=true; late.inPitBox=true; step()
 assert(t.cars[5].stops==0,'box seen a frame after the tow: not a stop')
 late.inPitBox=false; late.pit=false; for _=1,8 do step() end; late.pit=true; late.inPitBox=true; step()
 assert(t.cars[5].stops==1,'a later real stop counts')
end
-- Beta 1.24 : gomme sèche tirée parmi la première de chaque nom court : les variantes d'adhérence d'un même mod
-- (grip F3, F2, F1) ne sont jamais tirées ; sans cette liste, toutes les gommes sèches.
tests.DRY_CHOICE_PRIMARY=function()
 local W=require('src/weather')
 local a={index=0,dryList={},dryPrimary={0,1,2,3}}
 for k=0,15 do a.dryList[#a.dryList+1]=k end
 for index=0,60 do a.index=index; local choice=W.dryChoice(a,12345); assert(choice>=0 and choice<=3,'first of each name only: '..choice) end
 a.dryPrimary={}; local high=false
 for index=0,200 do a.index=index; if W.dryChoice(a,7)>3 then high=true end end
 assert(high,'without the list: every dry compound')
end
-- Beta 1.24 : départ de course moins frileux (prudence ×1,3, agressivité ×0,8) et radar avant activé : des valeurs
-- restées aux anciens défauts suivent, des valeurs réglées restent ; préréglages personnels aussi.
tests.START_MIGRATION=function()
 local function weekend() local out={}; for _,x in ipairs(C.profiles) do out[x]=C.validate(x,C.defaults(x)) end; return out end
 local profiles=weekend(); profiles.C.startCautionMult=1.6; profiles.C.startAggrMult=0.6
 local g=C.validateGlobals({schemaVersion=3,dataRevision=12,presetsUsed=true,useBrakeAssist=false}); C.migrate(g,profiles)
 assert(math.abs(profiles.C.startCautionMult-1.3)<1e-9 and math.abs(profiles.C.startAggrMult-0.8)<1e-9,'old start defaults follow')
 assert(g.useBrakeAssist,'front radar switched on')
 local tuned=weekend(); tuned.C.startCautionMult=2; tuned.C.startAggrMult=0.6
 C.migrate(C.validateGlobals({schemaVersion=3,dataRevision=12,presetsUsed=true}),tuned)
 assert(tuned.C.startCautionMult==2 and math.abs(tuned.C.startAggrMult-0.8)<1e-9,'tuned value kept, untouched one follows')
 assert(C.validateGlobals({}).useBrakeAssist and C.defaults('C').startCautionMult==1.3,'first install: new defaults')
 local Presets=require('src/presets')
 local p=weekend().C; p.startCautionMult=1.6; p.startAggrMult=0.6
 local store=Presets.layout(); store.name='Ancien'; store.profile='C'; store.revision=11
 for k,v in pairs(p) do store['p_'..k]=v end
 store.g_useBrakeAssist=false
 local entry=Presets.decode(store)
 assert(math.abs(entry.p.startCautionMult-1.3)<1e-9 and entry.g.useBrakeAssist and Presets.encode(entry).revision==14,'Beta 1.23 custom preset updated')
end
-- Beta 1.24 : contacts entre voitures notés au journal (qui touche l'arrière de qui, ou sur le côté), une fois par paire
-- toutes les 10 s ; un mur n'en est pas un.
tests.CONTACT_LOG=function()
 local e,f=F.scene('J',3); F.place(f,2,0,100); F.place(f,3,6,90)
 local function count(text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end; return n end
 f.cars[2].collidedWith=3; F.tick(e,f,1/60)
 assert(count('contact: Driver_2 touche l arriere de Driver_3')==1,'rear contact logged')
 F.place(f,3,6,70); F.tick(e,f,2); assert(count('contact:')==1,'once per pair within 10 s, even with another speed')
 f.cars[2].collidedWith=0; F.tick(e,f,11); assert(count('contact:')==1,'a wall is not a car')
 F.place(f,3,0,100,2.5); f.cars[2].collidedWith=3; F.tick(e,f,1/60)
 assert(count('se touchent sur le cote')==1,'side contact logged')
 -- Carambolage : au plus 3 lignes par seconde entre IA ; le contact avec le joueur est toujours noté.
 local m,fm=F.scene('J',10)
 for k=2,10 do F.place(fm,k,k*100,100) end
 for k=3,9,2 do fm.cars[k].collidedWith=k+1 end
 fm.cars[10].collidedWith=1; F.place(fm,1,994,120)
 F.tick(m,fm,1/60)
 local lines,player=0,false
 for k=1,m.log.limit do local r=m.log[k]; if r and r.message and r.message:find('contact:',1,true) then lines=lines+1; if r.message:find('Driver_1',1,true) then player=true end end end
 assert(lines==4 and player,'pile-up: 3 AI lines and the player one ('..lines..')')
end
-- Beta 1.24 : drapeau bleu du joueur noté au journal : IA en retard d'un tour qui tarde à le laisser passer (avec la
-- raison), puis quand elle le laisse passer.
tests.BLUE_FLAG_LOG=function()
 local e,f=F.scene('C',3); e.startedAt=-100; F.rear(e,f,60,20,1); f.cars[1].lap=f.cars[2].lap+1; f.cars[2].yawRate=0.4
 local function found(text) for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then return true end end; return false end
 F.tick(e,f,4)
 assert(found('drapeau bleu: Driver_2 devant le joueur depuis') and found('(virage,'),'blue flag waiting, with the reason')
 f.cars[2].yawRate=0; F.tick(e,f,4)
 assert(found('drapeau bleu: Driver_2 laisse passer le joueur'),'blue flag yield logged')
 -- Sous drapeau jaune (voiture arrêtée plus loin) : céder est interdit, aucune ligne d'attente.
 local y,fy=F.scene('C',3); y.startedAt=-100; F.rear(y,fy,20,0,1); fy.cars[1].lap=fy.cars[2].lap+1; F.place(fy,3,200,0)
 F.tick(y,fy,6)
 local waiting=false
 for k=1,y.log.limit do local r=y.log[k]; if r and r.message and r.message:find('drapeau bleu: Driver_2 devant le joueur',1,true) then waiting=true end end
 assert(y.states[2].yellow and not waiting and not F.yielding(y.states[2].state),'under yellow: no yield, nothing logged')
end
-- Beta 1.24 : départ de course noté : maintien de ligne (IA mesurées, décalées) et pneus au départ.
tests.START_REPORT=function()
 local e,f=F.scene('C',4); e.profiles.C.startLaneHold=true; E.changed(e); f.started=false; F.tick(e,f,0.1); f.started=true; F.tick(e,f,0.1)
 local lane,tyres=false,false
 for k=1,e.log.limit do local r=e.log[k]; if r and r.message then
  if r.message:find('depart: maintien de ligne actif, 3 IA',1,true) then lane=true end
  if r.message:find('pneus au depart:',1,true) then tyres=true end
 end end
 assert(lane and tyres,'start report logged')
end
-- Beta 1.24 : retardataire qui retient le joueur : collé derrière à la même allure, le joueur qui lui prend un tour
-- obtient le drapeau bleu (avant, il fallait 3 km/h d'avance : une IA bloquant le joueur ne cédait jamais) ; loin
-- derrière à la même allure, rien ; même tour, rien.
tests.BLUE_FLAG_SAME_SPEED=function()
 local function yields(gap,lapped,profile)
  local e,f=F.scene(profile or 'C',3); e.startedAt=-100
  if profile then local q=e.profiles[profile]; q.yieldEnabled=false; q.pressureEnabled=false; q.flashMode='never'; E.changed(e) end
  F.rear(e,f,gap,0,1); if lapped then f.cars[1].lap=f.cars[2].lap+1 end
  for _=1,8 do F.tick(e,f,0.5); if F.yielding(e.states[2].state) then return true end end
  return false
 end
 assert(yields(20,true),'held up at the same speed: blue flag')
 assert(not yields(100,true),'far behind at the same speed: nothing yet')
 assert(not yields(20,false),'same lap: no blue flag')
 assert(not yields(20,true,'Q'),'qualifying: one more lap is only more time on track, no blue flag at the same speed')
end
-- Beta 1.24 : évacuation cohérente avec les règles de course. Seule en piste sous drapeau jaune local (aucune règle
-- n'en découle) : 8 s. Neutralisation choisie (VSC) : jamais avant l'incident majeur, la VSC est déclarée d'abord.
-- Plusieurs voitures en cause (drapeau rouge possible, essais) : arrêts échelonnés, drapeau rouge avant tout dépannage.
-- Retenue hors piste (voiture qui attend pour repartir) jamais coupée par le dépannage.
tests.RECOVERY_RESPECTS_RULES=function()
 local function first(e,f,i,limit) for k=1,limit*2 do F.tick(e,f,0.5); if e.commands[i].recover then return k*0.5 end end; return math.huge end
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='local'; E.changed(e)
 F.place(f,2,0,150); F.place(f,3,5000,0)
 local t=first(e,f,3,30)
 assert(t>=C.K.trackRecoverTime and t<C.K.trackRecoverTime+2 and not e.incidents.neutral,'alone under local yellow: quick ('..t..')')
 local e2,f2=F.scene('C',3); C.preset('Course','C',e2.profiles.C); e2.profiles.C.neutralization='vsc'; E.changed(e2)
 F.place(f2,2,0,150); F.place(f2,3,5000,0)
 local t2=first(e2,f2,3,40)
 assert(t2>=e2.run.majorIncidentTime+C.K.ruleDecision-0.5 and t2<math.huge and e2.incidents.neutral and e2.incidents.neutralMode=='vsc','VSC declared before the car is recovered ('..t2..')')
 local e3,f3=F.scene('P',5); E.changed(e3)
 -- Beta 1.47 : arrêts échelonnés au même endroit, en travers de la piste (piste bloquée).
 F.place(f3,2,600,0,-4); F.place(f3,3,400,150,0); F.place(f3,4,200,150,4); F.place(f3,5,4000,150)
 F.tick(e3,f3,3); F.place(f3,3,600,0,0); F.tick(e3,f3,3); F.place(f3,4,600,0,4)
 local recovered=false
 for _=1,40 do
  F.tick(e3,f3,0.5); if e3.incidents.red then break end
  for i=2,4 do if e3.commands[i].recover then recovered=true end end
 end
 assert(e3.profile=='P' and e3.incidents.red and not recovered,'staggered stops: red flag before any recovery')
 local e4,f4=F.scene('J',3); e4.profiles.J.incidentStopMin=30; e4.profiles.J.incidentStopMax=30; E.changed(e4)
 F.place(f4,2,0,150); F.place(f4,3,-60,150)
 F.tick(e4,f4,0.5); f4.cars[2].collided=true; f4.cars[2].offtrack=true; f4.cars[2].kmh=8; f4.cars[2].speed=8/3.6; F.tick(e4,f4,0.5)
 f4.cars[2].collided=false; f4.cars[2].kmh=0; f4.cars[2].speed=0
 local c=e4.incidents.cars[2]; assert(c.holding,'held off track')
 F.tick(e4,f4,34); assert(c.holding and not e4.commands[2].recover,'a car waiting to rejoin is not towed')
 F.tick(e4,f4,8); assert(not c.holding and e4.commands[2].recover,'towed once the wait is over')
end
-- Beta 1.25 : lancement du départ : collé derrière la voiture de devant en ligne droite, ni prudence de suivi ni
-- anticipation du radar ; freinage seulement à un contact vraiment imminent. Après le départ, comportement habituel.
tests.START_LAUNCH_FLAT_OUT=function()
 local function scene(launch,gap,sa)
  local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e)
  e.startedAt=launch and e.time or -100
  F.place(f,2,0,150+sa); F.place(f,3,gap+4.4,150)
  e.states[2].nextPerception=0
  F.tick(e,f,0.5)
  return e.commands[2].caution,e.commands[2].brake
 end
 local c0=scene(true,60,0)
 local c1,b1=scene(true,12,0)
 assert(math.abs(c1-c0)<1e-6 and b1==0,'launch: close behind at the same speed, no follow caution ('..c1..' vs '..c0..')')
 local c2=scene(false,12,0); local c3=scene(false,60,0)
 assert(c2>c3,'after the start: follow caution back ('..c2..' vs '..c3..')')
 local _,b4=scene(true,6,20)
 assert(b4==0,'launch: 1.1 s from the car ahead, no brake')
 -- Beta 1.50 : 0,54 s avec un couloir libre à côté : pied tenu ; contact vraiment imminent (moins de K.firstLapLastTTC s) :
 -- léger freinage, comme avant.
 local _,b5=scene(true,3,20)
 assert(b5==0,'launch: 0.54 s with a free lane: foot kept down')
 local _,b5b=scene(true,1.2,20)
 assert(b5b>0,'launch: contact really imminent, light brake')
 -- Approche rapide (+70 km/h, hors règle de la ligne droite) à 1 s : rien au lancement (contact à moins de 0,8 s seulement).
 local _,b7=scene(true,19.4,70)
 assert(b7==0,'launch: fast approach 1 s away, nothing yet')
 local _,b6=scene(false,6,20)
 assert(b6>0,'after the start: radar as usual')
end
-- Beta 1.25 : sens latéral perdu (0 / 0) sur une installation existante : convention d'AC rétablie (-1 / -1), signalée ;
-- jamais à la première installation ni sur un sens connu. Mesure interrompue : retentée après K.calibrationRetry s.
tests.SIGNS_RESTORED=function()
 local function weekend() local out={}; for _,x in ipairs(C.profiles) do out[x]=C.validate(x,C.defaults(x)) end; return out end
 local g=C.validateGlobals({schemaVersion=3,dataRevision=13,presetsUsed=true,offsetSign=0,sideSign=0})
 local _,_,restored=C.migrate(g,weekend())
 assert(restored and g.offsetSign==-1 and g.sideSign==-1,'lost signs restored')
 local known=C.validateGlobals({schemaVersion=3,dataRevision=13,presetsUsed=true,offsetSign=1,sideSign=1})
 local _,_,again=C.migrate(known,weekend()); assert(not again and known.offsetSign==1,'a known sign is never changed')
 local fresh=C.validateGlobals({}); local _,isFresh,firstRestored=C.migrate(fresh,weekend())
 assert(isFresh and not firstRestored and fresh.offsetSign==0,'first install: measured, never assumed')
 local Calibration=require('src/calibration')
 local cal=Calibration.new(); cal.attempted=true; cal.retryAt=100
 local f={online=false,replay=false,paused=false,count=0,cars={}}
 local caps={}
 local zero={offsetSign=0,sideSign=0}
 Calibration.step(cal,f,caps,zero,50); assert(cal.attempted,'waits before retrying')
 Calibration.step(cal,f,caps,zero,101); assert(not cal.attempted,'retried after the delay')
end
-- Beta 1.25 : passage de la ligne (tour sur le total, dernier tour, nouveau meilleur tour) et ligne de session de
-- l'overlay (position, tour, meilleur tour, carburant en tours, alerte sous deux tours).
tests.HUD_LAP_AND_SESSION_LINE=function()
 local H=require('src/hudinfo'); local L=require('src/lang')
 local e,f=F.scene('C',3); f.sessionLaps=8; f.timedRace=false
 local me=f.cars[1]; me.lap=2; me.position=3; me.bestLap=121.5; me.lastLap=122.1; me.fuel=20; me.fuelPerLap=2.5
 local H2=require('src/hudinfo'); local fresh=H2.new(); H2.update(fresh,f,e,e.time); assert(fresh.lapUntil==-math.huge,'no line crossing at the first reading')
 F.tick(e,f,C.K.hudLapTime+0.5)
 me.lap=3; me.lastLap=121.2; me.bestLap=121.2; F.tick(e,f,0.5)
 assert(e.hud.lapTitle==string.format(L.hudLapTitle,4,8) and e.hud.lapDetail==string.format(L.hudLapRecord,H.lapTime(121.2)),'line crossed: lap 4/8, new best lap ('..e.hud.lapDetail..')')
 assert(e.panel.kind=='lap' and e.panel.title==e.hud.lapTitle and e.panel.lapCode=='4','shown on the overlay')
 -- Beta 1.38 (maquette) : nouveau meilleur tour, consigne en violet.
 assert(e.hud.lapRecord==true and e.panel.lapRecord==true,'new best lap: purple instruction')
 me.lap=4; me.lastLap=122.4; F.tick(e,f,0.5)
 assert(e.hud.lapDetail==string.format(L.hudLapDetail,H.lapTime(122.4),H.lapTime(121.2)),'ordinary lap: last and best')
 assert(e.hud.lapRecord==false,'ordinary lap: not purple')
 F.tick(e,f,C.K.hudLapTime+0.5); assert(e.panel.kind~='lap','gone after a few seconds')
 local function value(label) for k=1,e.hud.stripCount do local it=e.hud.strip[k]; if it.label==label then return it.value,it.warn end end end
 assert(value(L.hudPosition)=='3/3' and value(L.hudLap)=='5/8' and value(L.hudBest)==H.lapTime(121.2),'position, lap and best lap')
 local fuel,warn=value(L.hudFuel); assert(fuel==(string.format(L.hudFuelLaps,8):gsub('%.',L.decimalMark)) and not warn,'fuel in laps')
 -- Beta 1.38 (maquette) : meilleur tour en violet dans la ligne de session, seul.
 local purple=0; for k=1,e.hud.stripCount do local it=e.hud.strip[k]; if it.best then purple=purple+1; assert(it.label==L.hudBest,'only the best lap is purple') end end
 assert(purple==1,'best lap purple')
 me.fuel=3; F.tick(e,f,0.5); fuel,warn=value(L.hudFuel); assert(warn,'fuel warning under two laps')
 assert(H.lapTime(61.25)==('1:01.250'):gsub('%.',L.decimalMark) and H.clock(3725)=='1:02:05' and H.clock(65)=='1:05','time formats')
end
-- Beta 1.25 : récapitulatif de course : place au départ (premier feu vert), dépassements en piste du joueur (voiture du
-- même tour, proche) ; jamais une voiture aux stands ni dépannée ; arrivée : félicitations, places gagnées, meilleur
-- tour comparé au plateau ; damier et titre « course terminée » sur l'overlay, récapitulatif au journal.
tests.RACE_RECAP=function()
 local L=require('src/lang'); local H=require('src/hudinfo')
 local e,f=F.scene('C',4); f.started=false
 F.place(f,1,0,150); F.place(f,2,20,140); F.place(f,3,2000,150); F.place(f,4,5000,150)
 local me=f.cars[1]; me.position=4
 F.tick(e,f,0.3); f.started=true; F.tick(e,f,0.3)
 assert(e.hud.started and e.hud.grid==4,'grid place at the first green')
 F.place(f,1,25,150); F.tick(e,f,0.3)
 assert(e.hud.passes==1 and e.hud.lost==0,'on-track pass counted')
 F.place(f,2,30,160); F.tick(e,f,0.3); assert(e.hud.lost==1,'overtaken counted')
 local c3=F.place(f,3,40,60); c3.pit=true; F.tick(e,f,0.3); F.place(f,1,45,150); F.tick(e,f,0.3); c3.pit=false
 assert(e.hud.passes==2,'car in the pit lane: never a pass ('..e.hud.passes..')')
 local c4=F.place(f,4,50,150); c4.teleport=true; F.tick(e,f,0.3); c4.teleport=false
 local passes=e.hud.passes
 F.place(f,4,40,150); F.tick(e,f,0.3); assert(e.hud.passes==passes,'teleported car: no pass')
 me.bestLap=120; f.cars[2].bestLap=119.5; me.position=1; me.lap=8; me.finished=true; F.tick(e,f,0.5)
 assert(e.hud.finished and e.hud.final==1 and e.hud.recap[1]==L.recapCheer.win,'winner congratulated')
 assert(e.hud.recap[2]==string.format(L.recapPlace,1,4,4,string.format(L.recapGained,3)),'places gained ('..e.hud.recap[2]..')')
 assert(e.hud.recap[3]==string.format(L.recapBest,H.lapTime(120),H.lapTime(119.5),'Driver_2'),'best lap against the field ('..e.hud.recap[3]..')')
 assert(e.hud.recap[4]==string.format(L.recapStats,passes,1,8),'overtakes and laps')
 assert(e.panel.kind=='checkered' and e.panel.finish and e.panel.title==L.flagTitles.finish and e.panel.short==L.recapCheer.win,'race over on the overlay')
 local logged=false
 for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('fin de course: '..L.recapCheer.win,1,true) then logged=true end end
 assert(logged,'recap written to the journal')
 local e2,f2=F.scene('C',3); f2.cars[1].position=5; F.tick(e2,f2,0.3); f2.cars[1].bestLap=100; f2.cars[2].bestLap=101; f2.cars[1].position=7; f2.cars[1].finished=true; F.tick(e2,f2,0.5)
 assert(e2.hud.recap[1]==L.recapCheer.top10 and e2.hud.recap[3]==string.format(L.recapFastest,H.lapTime(100)) and e2.hud.recap[2]:find(string.format(L.recapLost,2),1,true),'places lost, fastest lap of the race')
end
-- Beta 1.25 : sous la consigne, l'explication de ce qui se passe (double jaune, jaune) ; rien sans drapeau.
tests.FLAG_EXPLANATIONS=function()
 local L=require('src/lang')
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e)
 F.tick(e,f,0.5); assert(e.panel.kind=='none' and e.panel.explain=='','no flag, no explanation')
 F.place(f,1,-1000,100); F.place(f,2,-850,0); F.place(f,3,5000,100)
 for _=1,40 do F.tick(e,f,0.25); if e.panel.kind~='none' then break end end
 local kind=e.panel.kind
 local expected=kind=='yellow' and (e.panel.double and L.flagExplain.yellow2 or L.flagExplain.yellow) or L.flagExplain[kind]
 assert(expected and expected~='' and e.panel.explain==expected,'explanation of the flag shown ('..kind..')')
 assert(L.flagExplain.yellow2:find('arrêtée',1,true) or L.flagExplain.yellow2:find('stopped',1,true),'double yellow: a car stopped on the track')
 local H=require('src/hudinfo'); local h=H.new()
 assert(H.message(h,'ABS','3',nil,5,10) and not H.message(h,'ABS','2',nil,5,11) and h.msgText=='ABS · 2' and h.msgUntil==16,'AC message kept on the line, title logged once')
 assert(H.message(h,'Tour invalidé','',  'illegal',99,20) and h.msgIllegal and h.msgUntil==20+C.K.hudMessageMax,'warning flagged, bounded time')
end

-- Beta 1.26 : réglage d'AI flood de CSP édité comme du texte : section ajoutée si elle manque, clés remplacées sur place,
-- doublons retirés, autres lignes et fins de ligne intactes ; sauvegarde et retour au réglage d'origine (clé absente :
-- retirée) ; état lu chez l'utilisateur puis dans les défauts de CSP ; décision selon la répartition et le seuil.
tests.FLOOD_CONFIG_EDIT=function()
 local Flood=require('src/flood')
 local original='[WRONG_WAY]\r\nALLOW_IN_PRACTICE=0\r\n\r\n[AI_RACE_RETIREMENT]\r\nREJOIN=1\r\n'
 local off=Flood.edit(original,Flood.section,Flood.values(false,1))
 assert(off==original..'\r\n[AI_FLOOD]\r\nENABLED=0\r\n','section appended, CRLF kept: '..off)
 assert(Flood.state(off,nil)==false,'read back: off')
 local on=Flood.edit(off,Flood.section,Flood.values(true,2.5))
 assert(Flood.get(on,'AI_FLOOD','ENABLED')=='1' and Flood.get(on,'ai_flood','spawn_despawn')=='2500, 1000' and Flood.get(on,'AI_FLOOD','SPAWN_DISTANCE')=='1500, 750','range scaled from the CSP distances')
 assert(Flood.get(on,'AI_FLOOD','SPAWN_RANGE')=='500, 250' and Flood.get(on,'AI_FLOOD','SPAWN_MIN_DISTANCE_TO_PLAYER')=='1000, 500','every distance scaled')
 assert(on:find('ALLOW_IN_PRACTICE=0\r\n',1,true) and not on:find('[^\r]\n'),'other lines untouched, CRLF only')
 local custom='[AI_FLOOD]\nENABLED=1 ; comment\nPUSH_SPEED=80\nENABLED=1\n\n[OTHER]\nX=1\n'
 local edited=Flood.edit(custom,Flood.section,{ENABLED='0'})
 assert(edited=='[AI_FLOOD]\nENABLED=0\nPUSH_SPEED=80\n\n[OTHER]\nX=1\n','replaced in place, duplicate dropped: '..edited)
 local added=Flood.edit(custom,Flood.section,{SPAWN_RANGE='400, 200'})
 assert(added:find('PUSH_SPEED=80\nENABLED=1\nSPAWN_RANGE=400, 200\n\n[OTHER]',1,true),'missing key at the end of its section: '..added)
 local back=Flood.edit(on,Flood.section,Flood.restore(Flood.backup(original)))
 assert(not back:find('ENABLED',1,true) and not back:find('SPAWN',1,true) and back:find('REJOIN=1\r\n',1,true),'original setting back: absent keys removed')
 local saved=Flood.restore(Flood.backup(custom)); assert(saved.ENABLED=='1' and saved.SPAWN_RANGE==false,'present kept, absent removed')
 local defaults='[AI_FLOOD]\nENABLED=1\nMIN_TRACK_LENGTH=7000 ; m\n'
 local enabled,length=Flood.state('',defaults); assert(enabled==true and length==7000,'CSP defaults')
 assert(Flood.state('[AI_FLOOD]\nENABLED=0\n',defaults)==false and Flood.state(nil,nil)==true,'user setting first; enabled when unknown')
 assert(Flood.decide({spawnMode='track',spawnMinCars=10},10)=='off' and Flood.decide({spawnMode='pits',spawnMinCars=10},9)=='on' and Flood.decide({spawnMode='native',spawnMinCars=10},45)=='restore','decision')
end
-- Beta 1.40 : options de CSP de gui.ini tenues par l'app (module pur, port imité) : fichier réel du pilote rendu à
-- l'octet près, option déjà masquée jamais touchée, fichier absent recréé puis effacé, état gardé avant d'écrire,
-- écriture refusée : état rendu, valeur changée par le pilote laissée, plafond d'écritures, état appliqué figé
-- jusqu'à la relecture de CSP, déchargement avant relecture : options gardées, relance : rien de réécrit.
local function cspPort(files)
 local p={ready=true,files=files,mem=nil,reads=0,writes=0,applied={},guiFails=false,stateFails=false}
 p.read=function() p.reads=p.reads+1; local t=files.gui; if t==nil then return '',false end return t,true end
 p.write=function(text) if p.guiFails then return false end p.writes=p.writes+1; files.gui=text; return true end
 p.remove=function() p.writes=p.writes+1; files.gui=nil; return true end
 p.loadState=function() return files.state or '' end
 p.saveState=function(text) if p.stateFails then return false end if text=='' then files.state=nil else files.state=text end return true end
 p.loadSession=function() return p.mem end
 p.saveSession=function(text) p.mem=text end
 p.loaded=function(key) return p.applied[key] end
 return p
end
local BOTH={HIDE_SYSTEM_MESSAGES=true,HIDE_RACE_FLAGS=true}
tests.CSPGUI_DRIVER_FILE_RESTORED=function()
 local G=require('src/cspgui')
 local original='[NEW_UI]\r\nUI_SCALE=1.05\r\n\r\n[HIDE]\r\nHIDE_RACE_FLAGS=1\r\n'
 local files={gui=original}; local p=cspPort(files); p.applied.HIDE_RACE_FLAGS=true; p.applied.HIDE_SYSTEM_MESSAGES=false
 local c=G.new(); G.start(c,p); assert(G.view(c)=='idle')
 G.step(c,p,BOTH,0)
 assert(files.gui=='[NEW_UI]\r\nUI_SCALE=1.05\r\n\r\n[HIDE]\r\nHIDE_RACE_FLAGS=1\r\nHIDE_SYSTEM_MESSAGES=1\r\n','added in its section, CRLF kept: '..files.gui)
 assert(c.owned.HIDE_SYSTEM_MESSAGES==false and c.owned.HIDE_RACE_FLAGS==nil,'flags hidden by the driver: never held')
 local owned,orig,written=G.parse(files.state); assert(owned.HIDE_SYSTEM_MESSAGES==false and orig==original and written==files.gui,'state kept: original file and value')
 assert(G.frozen(c,'HIDE_SYSTEM_MESSAGES')==false and G.frozen(c,'HIDE_RACE_FLAGS')==true and G.view(c)=='waiting','applied by CSP: before the write')
 G.step(c,p,BOTH,1); assert(p.writes==1 and p.reads==1,'nothing re-read or re-written while the wish is unchanged')
 G.step(c,p,BOTH,20); assert(G.view(c)=='pending' and #c.events==2,'not reloaded by CSP: next launch, said once')
 G.step(c,p,BOTH,40); assert(#c.events==2)
 G.step(c,p,{},50)
 assert(files.gui==original and files.state==nil and p.writes==2,'original file back byte for byte, state cleared')
 assert(G.view(c)=='idle')
end
tests.CSPGUI_MISSING_FILE_AND_SECTION=function()
 local G=require('src/cspgui')
 local files={}; local p=cspPort(files)
 local c=G.new(); G.start(c,p); G.step(c,p,BOTH,0)
 assert(files.gui=='[HIDE]\nHIDE_SYSTEM_MESSAGES=1\nHIDE_RACE_FLAGS=1\n','file created: '..tostring(files.gui))
 assert(G.parse(files.state)~=nil and select(2,G.parse(files.state))==false,'original: absent')
 G.step(c,p,{HIDE_RACE_FLAGS=true},1)
 assert(files.gui=='[HIDE]\nHIDE_RACE_FLAGS=1\n' and c.owned.HIDE_SYSTEM_MESSAGES==nil and c.owned.HIDE_RACE_FLAGS==false,'one option given back: '..files.gui)
 G.step(c,p,{},2); assert(files.gui==nil and files.state==nil,'everything back: file absent again')
 -- Fichier changé entre-temps (Content Manager) : seules les options tenues reviennent.
 G.step(c,p,BOTH,3); files.gui=files.gui..'[OTHER]\nX=1\n'
 G.step(c,p,{},4); assert(files.gui=='[HIDE]\n[OTHER]\nX=1\n' and files.state==nil,'only the held keys removed: '..tostring(files.gui))
 -- Valeur changée par le pilote pendant que l'app la tenait : laissée telle quelle, plus tenue.
 files.gui='[HIDE]\nHIDE_SYSTEM_MESSAGES=0\n'; local d=G.new(); G.start(d,p); G.step(d,p,BOTH,0)
 assert(files.gui=='[HIDE]\nHIDE_SYSTEM_MESSAGES=1\nHIDE_RACE_FLAGS=1\n' and d.owned.HIDE_SYSTEM_MESSAGES=='0')
 files.gui='[HIDE]\nHIDE_SYSTEM_MESSAGES=1\nHIDE_RACE_FLAGS=0\n'
 G.step(d,p,{HIDE_SYSTEM_MESSAGES=true},1)
 assert(files.gui=='[HIDE]\nHIDE_SYSTEM_MESSAGES=1\nHIDE_RACE_FLAGS=0\n' and d.owned.HIDE_RACE_FLAGS==nil and d.owned.HIDE_SYSTEM_MESSAGES=='0','driver change left alone')
 local said=false; for _,ev in ipairs(d.events) do if ev[2]:find('modifie par vous',1,true) then said=true end end; assert(said,'logged')
end
tests.CSPGUI_CRASH_AND_FAILURES=function()
 local G=require('src/cspgui')
 -- Plantage après l'écriture : options reprises au lancement suivant, rendues si l'app est coupée.
 local files={gui='[HIDE]\nHIDE_RACE_FLAGS=0\n'}; local p=cspPort(files)
 local c=G.new(); G.start(c,p); G.step(c,p,BOTH,0)
 assert(files.gui=='[HIDE]\nHIDE_RACE_FLAGS=1\nHIDE_SYSTEM_MESSAGES=1\n')
 local q=cspPort(files); q.applied.HIDE_SYSTEM_MESSAGES=true; q.applied.HIDE_RACE_FLAGS=true
 local d=G.new(); G.start(d,q)
 assert(d.owned.HIDE_SYSTEM_MESSAGES==false and d.owned.HIDE_RACE_FLAGS=='0' and G.view(d)=='applied' and #d.events==1,'resumed from the state file')
 G.step(d,q,{},0); assert(files.gui=='[HIDE]\nHIDE_RACE_FLAGS=0\n' and files.state==nil and q.writes==1,'app off: original back')
 -- Fichier d'état non modifiable : gui.ini jamais écrit.
 local f2={gui=''}; local p2=cspPort(f2); p2.stateFails=true
 local e=G.new(); G.start(e,p2); G.step(e,p2,BOTH,0); assert(f2.gui=='' and p2.writes==0 and G.view(e)=='readonly','no state: no write')
 -- gui.ini non modifiable : état rendu tel qu'avant, plus aucune tentative.
 local f3={gui=''}; local p3=cspPort(f3); p3.guiFails=true
 local h=G.new(); G.start(h,p3); G.step(h,p3,BOTH,0)
 assert(f3.gui=='' and f3.state==nil and not next(h.owned) and G.view(h)=='readonly','state rolled back')
 G.step(h,p3,{},1); assert(p3.reads==1,'no more attempts')
 -- Fichier d'état illisible : rien n'est touché.
 local f4={gui='',state='v1\ngarbage\n'}; local p4=cspPort(f4); local k=G.new(); G.start(k,p4); G.step(k,p4,BOTH,0)
 assert(f4.gui=='' and p4.writes==0 and G.view(k)=='readonly','unreadable state: nothing written')
 assert(G.parse(G.serialize({HIDE_SYSTEM_MESSAGES='0 ',HIDE_RACE_FLAGS=false},'a\r\nb\n','c'))~=nil,'serialized state read back')
 local o,orig,w=G.parse(G.serialize({HIDE_SYSTEM_MESSAGES='0 '},'a\r\nb\n',false))
 assert(o.HIDE_SYSTEM_MESSAGES=='0 ' and orig=='a\r\nb\n' and w==false and G.serialize({},'x','y')=='','round trip')
 assert(G.parse(G.serialize({HIDE_SYSTEM_MESSAGES=false},'abc','d'):sub(1,-3))==nil,'truncated state refused')
end
tests.CSPGUI_SESSION_AND_RELEASE=function()
 local G=require('src/cspgui'); local K=require('src/config').K
 local files={}; local p=cspPort(files)
 local c=G.new(); G.start(c,p); G.step(c,p,BOTH,0)
 assert(G.frozen(c,'HIDE_RACE_FLAGS')==false,'written, not applied: AC flags still counted as shown')
 p.applied.HIDE_RACE_FLAGS=true; assert(G.frozen(c,'HIDE_RACE_FLAGS')==false,'the file is never taken for the applied value')
 -- Déchargement sans relecture de CSP : gardées (fichier d'état), relance dans la même partie : rien de réécrit.
 G.release(c,p,5); assert(files.gui:find('HIDE_SYSTEM_MESSAGES=1',1,true) and files.state~=nil and p.writes==1,'kept until the next launch')
 local d=G.new(); G.start(d,p); assert(G.frozen(d,'HIDE_RACE_FLAGS')==false,'same game: still frozen')
 G.step(d,p,BOTH,0); assert(p.writes==1,'relaunched: no write, no loop')
 -- Relecture par CSP : état appliqué relu ; déchargement : valeurs d'origine rendues, sauf relecture à l'instant.
 G.step(d,p,{},1); assert(files.gui==nil and p.writes==2)
 G.step(d,p,BOTH,2); assert(p.writes==3 and G.view(d)=='waiting')
 p.applied.HIDE_SYSTEM_MESSAGES=true; G.reloaded(d,p,3)
 assert(G.frozen(d,'HIDE_RACE_FLAGS')==nil and G.applied(d,'HIDE_SYSTEM_MESSAGES') and d.live and G.view(d)=='applied','reloaded by CSP')
 G.release(d,p,3+K.cspReloadRelease/2); assert(files.gui~=nil,'reload just before: CSP restarting the apps, kept')
 -- Beta 1.47 : déchargement après une relecture : laissées cochées aussi (fermeture du jeu : cases cochées dans Content
 -- Manager), valeurs d'origine gardées.
 G.release(d,p,3+K.cspReloadRelease); assert(files.gui~=nil and files.state~=nil and p.writes==3,'unloaded after a live reload: kept ticked')
 -- Retour arrière vers une version sans ces options : rendues même sans relecture de CSP.
 local r=G.new(); G.start(r,p); G.step(r,p,BOTH,10); assert(p.writes==3,'relaunched: nothing rewritten'); G.release(r,p,11); assert(files.gui~=nil,'not reloaded: kept')
 G.release(r,p,11,true); assert(files.gui==nil and files.state==nil,'rollback: restored anyway')
 -- Plafond d'écritures par partie (mémoire de la partie) : plus rien d'écrit, état affiché.
 local e=G.new(); G.start(e,p)
 for i=1,K.cspWritesMax do G.step(e,p,i%2==1 and BOTH or {},i) end
 assert(p.writes==K.cspWritesMax and G.view(e)=='capped','capped at '..K.cspWritesMax..' writes per game: '..p.writes..' '..G.view(e))
 -- Option déjà appliquée par CSP sans être dans gui.ini : jamais touchée.
 local f5={}; local p5=cspPort(f5); p5.applied.HIDE_RACE_FLAGS=true
 local h=G.new(); G.start(h,p5); G.step(h,p5,{HIDE_RACE_FLAGS=true},0); assert(f5.gui==nil and p5.writes==0,'applied by CSP: untouched')
 -- Option déjà cochée dans gui.ini, état appliqué inconnu : jamais tenue.
 local f6={gui='[HIDE]\nHIDE_RACE_FLAGS=1\n'}; local p6=cspPort(f6)
 local k=G.new(); G.start(k,p6); G.step(k,p6,BOTH,0)
 assert(f6.gui=='[HIDE]\nHIDE_RACE_FLAGS=1\nHIDE_SYSTEM_MESSAGES=1\n' and k.owned.HIDE_RACE_FLAGS==nil and k.owned.HIDE_SYSTEM_MESSAGES==false,'ticked in gui.ini: never held')
end
-- Beta 1.26 : journée circuit : AI flood coupé à partir du seuil, rétabli en dessous avec la portée choisie, réglage
-- d'origine rendu en mode natif ; une écriture par changement, annoncée ; jamais hors journée circuit ; écriture
-- impossible : plus aucune tentative, avertissement.
tests.FLOOD_MANAGED_TRACK_DAY=function()
 local Flood=require('src/flood')
 local function scene(profile)
  local e,f=F.scene(profile,12); E.select(e,profile); e.profiles[profile].section_traffic=true; E.changed(e)
  local written={}
  E.floodInit(e,'','[AI_FLOOD]\nENABLED=1\nMIN_TRACK_LENGTH=7000\n',true); e.floodWrite=function(text) written[#written+1]=text; return true end
  return e,f,written
 end
 local function found(e,text) for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then return true end end; return false end
 local e,f,written=scene('J')
 assert(e.flood.loaded==true and found(e,'AI flood de CSP au lancement: actif'),'state at launch logged')
 F.tick(e,f,0.1)
 assert(#written==1 and Flood.get(written[1],'AI_FLOOD','ENABLED')=='0' and e.g.floodBackup~='','11 AI: off, original saved')
 assert(found(e,'AI flood de CSP: desactive (11 IA, seuil 10') and e.hud.msgTitle==require('src/lang').floodTitle,'announced')
 F.tick(e,f,3); assert(#written==1,'written once')
 e.profiles.J.spawnMinCars=20; e.profiles.J.floodRangeKm=3; E.changed(e); F.tick(e,f,3)
 assert(#written==2 and Flood.get(written[2],'AI_FLOOD','ENABLED')=='1' and Flood.get(written[2],'AI_FLOOD','SPAWN_DESPAWN')=='3000, 1200','below the threshold: back on, 3 km')
 e.profiles.J.spawnMode='native'; E.changed(e); F.tick(e,f,3)
 assert(#written==3 and not written[3]:find('ENABLED',1,true) and not written[3]:find('SPAWN',1,true) and e.g.floodBackup=='','native: original setting restored')
 F.tick(e,f,3); assert(#written==3,'nothing more to restore')
 local q,fq,qw=scene('Q'); F.tick(q,fq,3); assert(#qw==0,'qualifying: never written')
 local w,fw=scene('J'); w.floodWrite=function() return false end; F.tick(w,fw,0.1)
 assert(not w.flood.writable and found(w,'ecriture du reglage impossible') and w.g.floodBackup=='','write failure: stopped, warned, nothing saved')
end
-- Beta 1.26 : journée circuit, IA à leur emplacement : posées sur tout le circuit à intervalles réguliers, à l'abri du
-- joueur, après K.spreadDelay s, plus rien une fois en piste ; AI flood actif pour la session sur un long circuit :
-- rien (CSP les place) ; circuit court : réparties ; sous le seuil : rien ; sorties étalées : écart selon la longueur.
tests.TRACK_DAY_SPREAD_ON_TRACK=function()
 local K=C.K
 local function found(e,text) for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then return true end end; return false end
 local function boxed(loaded,count,length,mode,keep,variation)
  local e,f=F.scene('J',count or 12); E.select(e,'J'); e.profiles.J.section_traffic=true; e.profiles.J.spawnPitPct=keep or 0; e.profiles.J.spawnGapVariation=variation or 0; if mode then e.profiles.J.spawnMode=mode end; E.changed(e)
  E.floodInit(e,'',loaded and '[AI_FLOOD]\nENABLED=1\n' or '[AI_FLOOD]\nENABLED=0\n',false)
  f.length=length or 25000; f.session=1; f.time=0.6
  for i=2,f.count do local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0 end
  F.tick(e,f,0.1)
  return e,f
 end
 local e,f=boxed(false)
 local x=e.traffic.exits
 assert(x.mode=='track' and x.count==11 and math.abs(x.gap-(25000-2*K.spreadPlayerGap)/11)<1e-6,'11 AI over the whole track ('..x.gap..')')
 assert(found(e,'11 IA sur tout le circuit'),'logged')
 for i=2,12 do assert(x.place[i]>=0 and e.commands[i].place<0 and e.commands[i].startDelay<0,'planned, not placed yet: '..i) end
 f.time=K.spreadDelay+0.5; F.tick(e,f,0.1)
 local rel={}
 for i=2,12 do local cmd=e.commands[i]; assert(cmd.place>=0 and cmd.placeFor~='','placed: '..i); rel[#rel+1]=(cmd.place-f.cars[1].spline)%1 end
 assert(e.commands[1].place<0,'never the player')
 table.sort(rel)
 assert(rel[1]*25000>=K.spreadPlayerGap and (1-rel[#rel])*25000>=K.spreadPlayerGap,'clear of the player')
 for k=2,#rel do assert(math.abs((rel[k]-rel[k-1])*25000-x.gap)<1e-3,'regular spacing') end
 -- Indicateurs de stands faux un instant (début de session) : jamais compté comme posée hors de sa place.
 for i=2,12 do f.cars[i].pit=false; f.cars[i].inPitBox=false end
 F.tick(e,f,0.1)
 for i=2,12 do assert(e.commands[i].place>=0,'not at its place yet: asked again '..i) end
 assert(x.placed==0,'nothing counted before arrival')
 for i=2,12 do local a=f.cars[i]; a.spline=e.commands[i].place; a.kmh=60; a.speed=60/3.6 end
 F.tick(e,f,0.1)
 for i=2,12 do assert(e.commands[i].place<0,'at its place: no more placement '..i) end
 -- Beta 1.28 : 3 s après, une IA restée au pas est nommée avec la raison.
 f.cars[5].kmh=5; f.cars[5].speed=5/3.6
 F.tick(e,f,K.spreadCheck+0.1)
 assert(found(e,f.cars[5].name..' ('..f.cars[5].id..') en difficulte apres le placement (lente'),'troubled AI named with its reason')
 assert(found(e,'10 IA roulent normalement, 1 en difficulte'),'trouble counted')
 f.cars[5].kmh=60; f.cars[5].speed=60/3.6
 assert(x.placed==11 and found(e,'11 IA posees en piste sur 11'),'report')
 -- IA partie d'elle-même, déjà lancée en piste avant d'être posée : laissée telle quelle ; fenêtre écoulée : abandon.
 local g,fg=boxed(false); fg.time=K.spreadDelay+0.5; F.tick(g,fg,0.1)
 fg.cars[2].pit=false; fg.cars[2].inPitBox=false; fg.cars[2].kmh=K.spreadMaxKmh+20; F.tick(g,fg,0.1)
 assert(g.commands[2].place<0 and g.commands[3].place>=0,'already launched by itself: left alone')
 fg.time=K.spreadWindow+1; F.tick(g,fg,0.1); assert(g.commands[3].place<0,'window over: given up')
 local q=boxed(true); assert(q.traffic.exits.count==0 and found(q,'AI flood de CSP actif pour cette session'),'AI flood running: placed by CSP')
 local s=boxed(true,12,5000); assert(s.traffic.exits.count==11 and s.traffic.exits.mode=='track','short track: no AI flood, spread')
 local u=boxed(false,10); assert(u.traffic.exits.count==0,'9 AI: under the threshold')
 local p=boxed(false,12,25000,'pits'); local px=p.traffic.exits
 assert(px.mode=='pits' and math.abs(px.gap-math.min(25000/11/K.trackDayExitSpeed,K.trackDayExitMaxTotal/(10+K.pitExitJitter)))<1e-6 and p.commands[2].place<0,'pit exits: gap from the track length ('..px.gap..')')
 local n=boxed(false,12,25000,'native'); assert(n.traffic.exits.count==0,'native: left to the game')
 -- Aucune IA chargée à la première image : préparée dès qu'elles le sont ; jamais avant K.spreadPlanDelay s.
 local w,fw=F.scene('J',12); E.select(w,'J'); w.profiles.J.section_traffic=true; w.profiles.J.spawnPitPct=0; E.changed(w)
 E.floodInit(w,'','[AI_FLOOD]\nENABLED=0\n',false); fw.length=25000; fw.session=1; fw.time=0
 for i=2,fw.count do local a=fw.cars[i]; a.valid=false; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0 end
 F.tick(w,fw,0.1); assert(w.traffic.exits.count==0 and not w.traffic.exits.planned,'no AI yet: waiting')
 for i=2,fw.count do fw.cars[i].valid=true end; F.tick(w,fw,0.1)
 assert(w.traffic.exits.count==0 and not w.traffic.exits.planned,'before '..K.spreadPlanDelay..' s: waiting')
 fw.time=K.spreadPlanDelay; F.tick(w,fw,0.1); assert(w.traffic.exits.count==11 and w.traffic.exits.mode=='track','AI loaded: spread')
 -- Part laissée aux stands (25 % par défaut) : 31 IA, 8 restent, 23 posées sur tout le circuit.
 assert(C.defaults('J').spawnPitPct==25,'25 % by default')
 local k,fk=boxed(false,32,25000,nil,25); local kx=k.traffic.exits
 assert(kx.count==23 and kx.kept==8 and math.abs(kx.gap-(25000-2*K.spreadPlayerGap)/23)<1e-6 and found(k,'8 laissees aux stands'),'31 AI: 8 kept in the pits')
 local planned=0; for i=2,32 do if kx.place[i]>=0 then planned=planned+1 end end; assert(planned==23,'23 placed')
 -- Écarts variés (100 % par défaut) : du presque collé à plusieurs fois l'écart moyen, jamais sous 15 m, jamais près
 -- du joueur ; circuit court : écart minimal tenu.
 assert(C.defaults('J').spawnGapVariation==100,'100 % by default')
 local function gaps(length,count)
  local v,fv=boxed(false,count,length,nil,0,100); local rel={}
  for i=2,count do local place=v.traffic.exits.place[i]; if place>=0 then rel[#rel+1]=(place-fv.cars[1].spline)%1 end end
  table.sort(rel); local out={}
  for k=2,#rel do out[#out+1]=(rel[k]-rel[k-1])*length end
  assert(rel[1]*length>=K.spreadPlayerGap-1e-6 and (1-rel[#rel])*length>=K.spreadPlayerGap-1e-6,'clear of the player')
  return out,v
 end
 local long,v=gaps(25000,46); local shortest,longest=math.huge,0
 for _,d in ipairs(long) do shortest=math.min(shortest,d); longest=math.max(longest,d) end
 assert(shortest>=K.spreadMinGap-1e-6 and longest>4*shortest and longest>1.5*v.traffic.exits.gap and shortest<0.5*v.traffic.exits.gap,'varied gaps ('..shortest..' to '..longest..')')
 assert(found(v,'m d ecart en moyenne (de '),'range logged')
 local short=gaps(2000,32); for _,d in ipairs(short) do assert(d>=K.spreadMinGap-1e-6,'never under 15 m: '..d) end
end
-- Beta 1.26 : IA nettement plus rapide en ligne droite que celle de devant : jamais retenue par l'espacement (elle la
-- rattrape et la dépasse) ; à allure voisine, retenue comme avant.
tests.TRAFFIC_FASTER_NOT_HELD=function()
 local Traffic=require('src/traffic'); local K=C.K
 local function limit(follower,leader)
  local e,f=F.scene('J',3); f.length=20000; e.p.section_traffic=true; e.p.trafficVariation=0
  for i=2,3 do local a=f.cars[i]; a.lx=0; a.lz=1; a.kmh=150; a.speed=150/3.6; a.corner=1 end
  f.cars[2].spline=0.1; f.cars[3].spline=0.1+40/20000
  e.states[2].trafficReference=follower; e.states[3].trafficReference=leader; e.states[2].trafficApplied=true; e.states[3].trafficApplied=true
  local random=require('src/util').unit(e.g.seed,f.cars[2].index,2)
  Traffic.update(Traffic.new(),f,e.states,e.p,e.g,'J',K.trafficCycle-random*K.trafficCycle)
  return e.states[2].trafficLimit
 end
 assert(limit(182,180)<K.unlimitedSpeed,'similar pace: held')
 assert(limit(200,180)==K.unlimitedSpeed,'clearly faster: free to catch up and pass')
 assert(limit(200,0)<K.unlimitedSpeed,'unknown leader reference: held as before')
end
-- Beta 1.26 : messages d'origine d'AC masqués par défaut, aussi sur une installation existante (révision 15) ; un choix
-- fait ensuite est gardé.
tests.MESSAGES_HIDDEN_BY_DEFAULT=function()
 assert(C.globalDefaults.overlayBlockMessages==true and C.dataRevision>=15)
 local g={}; for k,v in pairs(C.globalDefaults) do g[k]=v end
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.validate(x,C.defaults(x),{}) end
 g.dataRevision=14; g.presetsUsed=true; g.overlayBlockMessages=false; g.offsetSign=-1; g.sideSign=-1
 C.migrate(g,profiles); assert(g.overlayBlockMessages==true and g.dataRevision==C.dataRevision,'existing install: hidden')
 g.overlayBlockMessages=false; C.migrate(g,profiles); assert(g.overlayBlockMessages==false,'later choice kept')
end
-- Beta 1.26 : cible d'un dépassement perdue de vue un instant : manœuvre tenue K.targetLostGrace s, puis abandon.
tests.TARGET_LOST_GRACE=function()
 local e,f=F.scene('C',3); e.p.personalLineJitter=0
 F.place(f,2,0,100); F.place(f,3,15,100); F.tick(e,f,0.1)
 local s=e.states[2]; s.state='OVT_HOLD'; s.since=e.time; s.target=3; s.targetSide=1; s.passAlongside=false; s.restUntil=0; s.offset=0.4; s.filtered=0.4
 s.nextPerception=0
 f.cars[3].pit=true
 F.tick(e,f,C.K.targetLostGrace*0.5)
 assert(s.state=='OVT_HOLD','held through a short loss ('..s.state..', '..tostring(s.reason)..')')
 F.tick(e,f,C.K.targetLostGrace)
 assert(s.state~='OVT_HOLD' and s.state~='OVT_IN','given up after the grace ('..s.state..')')
end
-- Beta 1.27 : départ de course repris du profil personnalisé du pilote (attente 1 s, détente 25 s, sans maintien de
-- ligne) ; un profil Course resté aux anciens défauts les suit, des valeurs réglées restent telles quelles.
tests.START_DEFAULTS_127=function()
 local d=C.defaults('C'); assert(d.startDelay==2 and d.startRelax==25 and d.startLaneHold==false and d.startCautionMult==1.3 and d.startAggrMult==0.8,'race start defaults')
 local course=C.preset('Course','C',{}); assert(course.startDelay==2 and course.startRelax==25 and course.startLaneHold==false,'built-in Race preset')
 local g={}; for k,v in pairs(C.globalDefaults) do g[k]=v end
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.validate(x,C.defaults(x),{}) end
 g.dataRevision=15; g.presetsUsed=true; g.offsetSign=-1; g.sideSign=-1
 profiles.C.startDelay=12; profiles.C.startRelax=12; profiles.C.startLaneHold=true
 profiles.P.startDelay=12
 local upgraded=C.migrate(g,profiles)
 assert(profiles.C.startDelay==2 and profiles.C.startRelax==25 and profiles.C.startLaneHold==false,'old race defaults follow')
 assert(profiles.P.startDelay==12,'other profiles untouched')
 local listed=false; for _,u in ipairs(upgraded) do if u=='C:depart' then listed=true end end; assert(listed,'logged')
 local tuned={}; for k,v in pairs(C.globalDefaults) do tuned[k]=v end; tuned.dataRevision=15; tuned.presetsUsed=true; tuned.offsetSign=-1; tuned.sideSign=-1
 local mine={}; for _,x in ipairs(C.profiles) do mine[x]=C.validate(x,C.defaults(x),{}) end
 mine.C.startDelay=5; mine.C.startLaneHold=true; mine.C.startRelax=12
 C.migrate(tuned,mine)
 assert(mine.C.startDelay==5 and mine.C.startLaneHold==false and mine.C.startRelax==25,'each value follows on its own: a tuned delay stays')
 -- Beta 1.49 (révision 21) : 1 s (défaut de la 1.27 à la 1.48) devient 2 s ; une valeur réglée reste ; autres profils intacts.
 local g2={}; for k,v in pairs(C.globalDefaults) do g2[k]=v end; g2.dataRevision=20; g2.presetsUsed=true; g2.offsetSign=-1; g2.sideSign=-1
 local p2={}; for _,x in ipairs(C.profiles) do p2[x]=C.validate(x,C.defaults(x),{}) end
 p2.C.startDelay=1; p2.P.startDelay=1
 local up2=C.migrate(g2,p2)
 assert(p2.C.startDelay==2 and p2.P.startDelay==1,'1.49: race start wait 1 s -> 2 s, other profiles untouched')
 local seen=false; for _,u in ipairs(up2 or {}) do if u=='C:attente au depart 2 s' then seen=true end end; assert(seen,'1.49: logged')
 local g3={}; for k,v in pairs(C.globalDefaults) do g3[k]=v end; g3.dataRevision=20; g3.presetsUsed=true; g3.offsetSign=-1; g3.sideSign=-1
 local p3={}; for _,x in ipairs(C.profiles) do p3[x]=C.validate(x,C.defaults(x),{}) end
 p3.C.startDelay=3; C.migrate(g3,p3); assert(p3.C.startDelay==3,'1.49: a tuned wait stays')
end
-- Beta 1.28 : IA anormalement lente qui retient le trafic (diagnostic) : une ligne au journal après K.slowLogTime s
-- (modèle, vitesse, allure de sa classe, voitures derrière, état, limite de l'app, dégâts), une à la fin ; rien sans
-- voiture derrière, à un endroit dont l'allure n'est pas apprise, ni juste après un déplacement.
tests.SLOW_CAR_DIAGNOSTIC=function()
 local K=C.K
 local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end; return n end
 local function scene(follower,learned)
  local e,f=F.scene('J',6); E.select(e,'J'); e.profiles.J.section_traffic=true; E.changed(e)
  f.length=20000
  -- Beta 1.41 : rythme relatif habituel connu (allure de sa classe), la référence de l'IA elle-même.
  for i=2,6 do local s=e.states[i]; s.paceCount=K.paceBins; for b=1,K.paceBins do s.pace[b]=learned==false and 0 or 50 end; s.longRatio=1; s.longRatioTime=K.longRatioMin end
  F.place(f,1,-9000,0); F.place(f,2,0,100); F.place(f,3,follower and -30 or -3000,100)
  F.place(f,4,5000,180); F.place(f,5,9000,180); F.place(f,6,13000,180)
  F.tick(e,f,2)
  return e,f
 end
 local e,f=scene(true)
 F.tick(e,f,K.slowLogTime-3)
 assert(count(e,'IA anormalement lente: ')==0,'not before '..K.slowLogTime..' s')
 F.tick(e,f,4)
 local name=f.cars[2].name
 assert(count(e,'IA anormalement lente: '..name..' ('..f.cars[2].id..') a 100 km/h')==1,'slow car logged with its model and speed')
 assert(count(e,'allure de sa classe ici 180 km/h (habituelle de l IA 180 km/h), 1 voiture(s) derriere')==1,'class pace and queue logged')
 assert(count(e,'limite de vitesse app ')==1,'app speed limit reported')
 assert(f.cars[2].watchDamage==true,'damage watched while slow')
 F.tick(e,f,10); assert(count(e,'IA anormalement lente: '..name..' (')==1,'once per episode')
 F.place(f,2,0,180); F.tick(e,f,K.slowEnd+1)
 assert(count(e,'IA anormalement lente: '..name..' roule de nouveau normalement')==1 and not f.cars[2].watchDamage,'end of the episode logged')
 local e2,f2=scene(false); F.tick(e2,f2,K.slowLogTime+5); assert(count(e2,'IA anormalement lente')==0,'nobody held up: nothing')
 local e3,f3=scene(true,false); F.tick(e3,f3,K.slowLogTime+5); assert(count(e3,'IA anormalement lente')==0,'pace not learned here: nothing')
 local e4,f4=scene(true); f4.cars[2].teleport=true; F.tick(e4,f4,1/60); f4.cars[2].teleport=false
 F.tick(e4,f4,K.slowSettle+K.slowLogTime-3); assert(count(e4,'IA anormalement lente')==0,'just moved: settling time first')
 F.tick(e4,f4,5); assert(count(e4,'IA anormalement lente: ')==1,'then logged')
end
-- Beta 1.29 (demande du pilote) : collé derrière une IA à la même allure, l'appel du joueur est compris ; plus loin à la
-- même allure, non ; appelé de loin un peu lentement, compris dès que le joueur se rapproche (demande en cours) ; portée
-- de 200 m en journée circuit ; chaque appel et chaque cession sur appel du joueur au journal.
tests.FLASH_HELD_129=function()
 local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end; return n end
 local function scene(gap,sa)
  local e,f=F.scene('J'); e.p.flashObliviousPct=0; e.p.pressureEnabled=false; e.p.yieldBehindMargin=30; e.p.personalLineJitter=0
  F.rear(e,f,gap,sa,1); F.tick(e,f,0.2)
  return e,f
 end
 local function flash(e,f)
  e.flash.eventId=e.flash.eventId+1; e.flash.eventCount=2; F.tick(e,f,0.15)
  return Flash.dispatch(e.flash,f.cars,f.count,1,e.perception,e.states,e.p,e.g,e.profile,e.time)
 end
 local e,f=scene(40,0); assert(flash(e,f)==1 and e.flash.heard==1,'held up right behind: flash understood')
 F.tick(e,f,2); assert(F.yielding(e.states[2].state),'yields to a held-up player')
 assert(count(e,'cede sur appel de phares du joueur (')==1,'yield on the player flash logged')
 e,f=scene(100,0); flash(e,f); F.tick(e,f,3); assert(not F.yielding(e.states[2].state) and e.flash.heard==0,'same speed further back: not a request to pass')
 e,f=scene(30,-8); flash(e,f); F.tick(e,f,3); assert(not F.yielding(e.states[2].state),'dropping back: not held up')
 e,f=scene(100,2); flash(e,f); F.tick(e,f,1); assert(not F.yielding(e.states[2].state))
 F.rear(e,f,45,2,1); F.tick(e,f,2); assert(F.yielding(e.states[2].state),'request still alive: understood once the player is close')
 e,f=scene(180,40); assert(flash(e,f)==1 and e.flash.heard==1,'seen from 180 m on a track day'); F.tick(e,f,2); assert(F.yielding(e.states[2].state),'and accepted with a large advantage')
 e,f=scene(180,20); flash(e,f); assert(e.flash.heard==0,'180 m at +20 km/h: the AI would give up before the player arrives')
 -- Appel réel (feux de route appris) : une ligne au journal par appel.
 e,f=scene(40,0); e.g.flashField='highBeams'; e.p.section_flash=true
 local car=f.cars[1]
 for _,on in ipairs({true,false,true,false}) do car.highBeams=on; F.tick(e,f,0.2) end
 assert(count(e,'appel de phares du joueur: 1 IA visee(s) a moins de 200 m, la plus proche a 40 m (+0 km/h), vu par 1, compris par 1')==1,'player flash logged')
end
-- Beta 1.29 : portée des appels de phares 200 m (journée circuit, hotlap, essais, qualifications) et 150 m (course) ; une
-- portée restée à l'ancien défaut le suit, une portée réglée reste telle quelle.
tests.FLASH_RANGE_DEFAULTS_129=function()
 assert(C.defaults('J').flashRange==200 and C.defaults('P').flashRange==200 and C.defaults('Q').flashRange==200 and C.defaults('C').flashRange==150 and C.defaults('H').flashRange==200,'new defaults')
 local g={}; for k,v in pairs(C.globalDefaults) do g[k]=v end; g.dataRevision=16; g.presetsUsed=true; g.offsetSign=-1; g.sideSign=-1
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.validate(x,C.defaults(x),{}) end
 profiles.J.flashRange=120; profiles.P.flashRange=150; profiles.Q.flashRange=90; profiles.C.flashRange=100; profiles.H.flashRange=120
 profiles.J.flashCloseAdvantage=5; profiles.P.flashCloseAdvantage=4; profiles.Q.flashCloseAdvantage=10
 local upgraded=C.migrate(g,profiles)
 assert(profiles.J.flashRange==200 and profiles.P.flashRange==200 and profiles.C.flashRange==150 and profiles.H.flashRange==200,'old defaults follow')
 assert(profiles.Q.flashRange==90,'a tuned range stays')
 assert(profiles.J.flashCloseAdvantage==-5 and profiles.P.flashCloseAdvantage==-5 and profiles.Q.flashCloseAdvantage==10 and profiles.C.flashCloseAdvantage==6,'close-range advantage follows, a tuned one stays')
 local Pr=require('src/presets')
 local store=Pr.layout(); store.name='Ancien'; store.profile='J'; store.revision=12; store.p_flashRange=120; store.p_flashCloseAdvantage=5
 local entry=Pr.decode(store); assert(entry.p.flashRange==200 and entry.p.flashCloseAdvantage==-5,'custom preset at the old defaults follows')
 store.p_flashRange=90; entry=Pr.decode(store); assert(entry.p.flashRange==90,'tuned custom preset kept')
 assert(Pr.encode(entry).revision==14)
 local listed=false; for _,u in ipairs(upgraded) do if u=='J:phares' then listed=true end end; assert(listed,'logged')
end
-- Beta 1.29 (demande du pilote) : un préréglage règle tout son profil, règles de championnat comprises ; il ne garde que
-- les préférences du pilote et les motifs de classes. Ses règles valent pour tout le week-end (Essais, Qualifications,
-- Course), sans cocher l'onglet Règles ; jamais depuis la journée circuit ou le hotlap.
tests.PRESETS_COMPLETE_129=function()
 for key in pairs(C.presetKeptKeySet) do assert(not C.ruleKeySet[key],'no championship rule kept by a preset: '..key) end
 for _,key in ipairs(C.preferenceKeys) do assert(C.presetKeptKeySet[key],'driver preference kept: '..key) end
 assert(C.presetKeptKeySet.classPatterns and not C.presetKeptKeySet.mandatoryStops and not C.presetKeptKeySet.safetyCarEscalation)
 local profiles={}; for _,x in ipairs(C.profiles) do profiles[x]=C.validate(x,C.defaults(x),{}) end
 for _,x in ipairs({'P','Q','C'}) do C.preset(C.recommended[x],x,profiles[x]) end
 C.applyRules('F1',profiles); profiles.C.section_rules=false
 C.preset('Qualifications','Q',profiles.Q)
 assert(C.spreadRules('Q',profiles))
 for _,x in ipairs({'P','Q','C'}) do assert(C.ruleCategory(x,profiles[x])=='base' and profiles[x].mandatoryStops==0,'weekend rules follow the preset: '..x) end
 assert(profiles.C.section_rules==false,'race Rules tab left unticked')
 profiles.J.mandatoryStops=2; C.applyRules('GT',profiles)
 assert(C.spreadRules('J',profiles)==false and C.spreadRules('H',profiles)==false)
 for _,x in ipairs({'P','Q','C'}) do assert(C.ruleCategory(x,profiles[x])=='GT','weekend untouched by a track day preset: '..x) end
 local fresh={}; for _,x in ipairs(C.profiles) do fresh[x]=C.validate(x,C.defaults(x),{}) end
 C.preset('Course','C',fresh.C); fresh.C.mandatoryStops=1
 C.spreadRules('C',fresh)
 assert(not fresh.P.configured and fresh.P.mandatoryStops==1 and fresh.Q.mandatoryStops==1,'unconfigured profiles: weekend rules copied, left unconfigured')
 -- Préréglage intégré allumé après un clic seulement, profil par profil.
 local g={builtinMarks=''}; C.setMark(g,'J','Nordschleife'); C.setMark(g,'C','Endurance'); C.setMark(g,'P','Essais'); C.setMark(g,'P','')
 assert(g.builtinMarks=='J=Nordschleife,C=Endurance' and C.mark(g,'J')=='Nordschleife' and C.mark(g,'P')=='' and C.mark(g,'H')=='','marks per profile')
 local checked=C.validateGlobals({builtinMarks='J=Nordschleife'}); assert(checked.builtinMarks=='J=Nordschleife')
 checked=C.validateGlobals({builtinMarks='J=\n'}); assert(checked.builtinMarks=='','invalid marks dropped')
 local race=C.withRules('Endurance','C',C.preset('Endurance','C',{}))
 assert(C.ruleCategory('C',race)=='Endurance','endurance race preset carries the Endurance rules')
end
-- Beta 1.29 : appel de loin sans pouvoir rejoindre l'IA avant la fin de sa cession : refusé (elle s'écarterait pour
-- rien, abandonnerait puis ignorerait le joueur) ; renouvelé une fois assez près : compris, cession menée jusqu'à
-- l'arrivée du joueur, sans jamais l'ignorer.
tests.FLASH_CATCH_129=function()
 local K=C.K
 local e,f=F.scene('J'); e.p.flashObliviousPct=0; e.p.pressureEnabled=false; e.p.yieldBehindMargin=30; e.p.personalLineJitter=0
 F.rear(e,f,190,13,1); F.tick(e,f,0.2)
 local function flash() e.flash.eventId=e.flash.eventId+1; e.flash.eventCount=2; F.tick(e,f,0.15); return Flash.dispatch(e.flash,f.cars,f.count,1,e.perception,e.states,e.p,e.g,e.profile,e.time) end
 assert(flash()==1 and e.flash.heard==0,'190 m at +13 km/h: seen, not understood')
 local catch=13/3.6*(e.p.yieldMaxHold-K.flashCatchMargin)
 while e.states[2].playerGap>catch-5 do F.tick(e,f,0.5,true); assert(not F.yielding(e.states[2].state),'no early yield at '..math.floor(e.states[2].playerGap)..' m') end
 assert(flash()==1 and e.flash.heard==1,'close enough to catch it: understood')
 local yielded=false
 while e.states[2].playerGap>10 do
  F.tick(e,f,0.5,true); local s=e.states[2]
  yielded=yielded or F.yielding(s.state)
  assert(s.ignoreTarget~=1 or e.time>=s.ignoreUntil,'the AI never ignores the player')
  if yielded then assert(F.yielding(s.state),'yield held until the player arrives') end
 end
 assert(yielded,'yields to the renewed flash')
end
-- Beta 1.29 (séance d'essais du pilote) : hors course, pas de bagarre avec le joueur. Collé derrière l'IA, elle lâche de
-- l'agressivité (l'IA native ne lui ferme plus la porte) ; juste doublée par lui, elle ne cherche pas à le repasser
-- pendant K.courtesyTime s, sauf s'il ralentit nettement. En course, rien ne change.
tests.COURTESY_PRACTICE_129=function()
 local K=C.K
 local passStates={OVT_ARM=true,OVT_IN=true,OVT_HOLD=true,OVT_OUT=true}
 local function scene(profile)
  local e,f=F.scene(profile); e.p.personalLineJitter=0; e.p.flashObliviousPct=0; e.p.pressureEnabled=false
  F.place(f,2,0,100); F.place(f,1,-600,100); F.tick(e,f,3)
  return e,f
 end
 for _,profile in ipairs({'P','Q','J','C'}) do
  local e,f=scene(profile); local alone=e.commands[2].aggression
  F.place(f,1,-12,100); e.states[2].nextPerception=0; F.tick(e,f,3)
  local attacked=e.commands[2].aggression
  if profile=='C' then assert(math.abs(attacked-alone)<0.02,'race: aggression unchanged with the player behind')
  else assert(attacked<alone*0.6,profile..': aggression eased with the player right behind') end
 end
 -- Joueur qui double l'IA puis ralentit un peu devant elle : pas de riposte hors course pendant la courtoisie.
 local e,f=scene('P'); e.p.overtakeDetectAhead=60
 F.place(f,1,-12,100); e.states[2].nextPerception=0; F.tick(e,f,1)
 F.place(f,1,8,88); e.states[2].nextPerception=0; F.tick(e,f,0.2)
 assert(e.time-e.states[2].passedByPlayerAt<1,'pass by the player noted')
 for _=1,10 do F.tick(e,f,0.5); assert(not passStates[e.states[2].state],'no attack on the player who just passed it') end
 assert(e.commands[2].aggression<0.6*require('src/config').defaults('P').aggressionPct/100+0.05,'aggression eased right after the pass')
 -- Il ralentit nettement : la courtoisie ne retient plus l'IA.
 local e2,f2=scene('P'); e2.p.overtakeDetectAhead=60
 F.place(f2,1,-12,100); e2.states[2].nextPerception=0; F.tick(e2,f2,1)
 F.place(f2,1,8,60); e2.states[2].nextPerception=0; F.tick(e2,f2,0.2)
 local attacked=false; for _=1,10 do F.tick(e2,f2,0.5); attacked=attacked or passStates[e2.states[2].state] or false end
 assert(attacked,'a player who slows sharply can be passed')
end
-- Beta 1.29 (séance d'essais du pilote) : voiture bloquée dans un bac à sable, qui patine sur place (par moments au-dessus
-- du seuil d'arrêt) : dépannée à son stand après K.stuckRecoverTime s sans avancer ; une voiture qui repart doucement
-- hors piste ne l'est pas.
tests.STUCK_GRAVEL_129=function()
 local K=C.K
 local function scene()
  local e,f=F.scene('P',3); e.p.section_accidents=true; E.changed(e)
  F.place(f,2,1000,100); F.place(f,3,3000,100); F.place(f,1,-2000,100); F.tick(e,f,1,true)
  local a=f.cars[2]; a.offtrack=true; a.kmh=0; a.speed=0; F.tick(e,f,4)
  assert(e.incidents.cars[2].incident and not e.incidents.cars[2].onTrack,'off-track incident')
  return e,f,a
 end
 local e,f,a=scene()
 local t=0
 -- Déjà 4 s à l'arrêt : la dépanneuse vient au bout de K.stuckRecoverTime s sans avancer en tout.
 while t<K.stuckRecoverTime-4-2 do
  a.kmh=(math.floor(t*2)%2==0) and 8 or 0; a.speed=a.kmh/3.6; F.tick(e,f,0.5); t=t+0.5
  assert(not e.commands[2].recover,'not recovered before '..K.stuckRecoverTime..' s')
 end
 assert(e.incidents.cars[2].still<1,'never still for long: the old timer would wait forever')
 for _=1,10 do a.kmh=(a.kmh==0) and 8 or 0; a.speed=a.kmh/3.6; F.tick(e,f,0.5) end
 assert(e.commands[2].recover and e.commands[2].recoverReason=='bloquee','stuck in the gravel: recovered to its pit')
 -- Voiture qui repart doucement hors piste : elle avance, jamais dépannée.
 local e2,f2,b=scene()
 b.kmh=8; b.speed=8/3.6
 for _=1,80 do F.tick(e2,f2,0.5,true); assert(not e2.commands[2].recover,'a car driving out of the gravel is left alone') end
end
-- Beta 1.29 (bilan des journaux) : une cession tenue du même côté, dont la cible bornée par la largeur retombe à zéro à
-- chaque virage, ne compte aucun changement de direction ; un vrai zigzag (côté visé qui change) reste plafonné.
tests.DIRECTION_CLAMP_129=function()
 local K=C.K
 local e,f=F.scene('J'); e.g.offsetSign=-1; F.tick(e,f,0.5)
 local s,a,row=e.states[2],f.cars[2],e.perception.rows[2]
 s.state='YIELD_HOLD'; s.direction=-1; s.offset=-0.5; s.filtered=-0.5; s.velocity=0; s.driveUntil=0
 for j=1,K.directionLimit do s.directions[j]=-math.huge end
 local now=e.time
 for k=1,30 do
  local narrow=k%2==0
  a.leftWidth=narrow and 1.1 or 6; a.rightWidth=6
  now=now+2; D.lateral(s,-0.7,row,a,e.p,e.g,1/60,now)
  assert(not s.newDirectionLimit and now>=s.driveUntil,'same side held through the corners: no limit (step '..k..')')
 end
 assert(s.direction==-1,'still counted on the yielding side')
 -- Vrai zigzag : côté visé alterné, le plafond le retient.
 s.state='OVT_IN'; a.leftWidth=6; a.rightWidth=6; local limited=false
 for k=1,K.directionLimit+3 do now=now+e.p.lateralCooldown+0.5; D.lateral(s,k%2==0 and -0.7 or 0.7,row,a,e.p,e.g,1/60,now); limited=limited or s.newDirectionLimit end
 assert(limited,'a real zigzag is still capped')
end
-- Beta 1.29 (essais du pilote) : IA arrivée vite derrière le joueur qui s'écarte pour la laisser passer : le radar avant
-- freine un peu (le joueur déborde encore sur sa file), mais ce freinage n'empêche plus de déboîter ni de dépasser ; un
-- vrai freinage du pilote, lui, l'empêche toujours, et l'invitation non suivie est expliquée au journal.
tests.RADAR_BRAKE_PASS_129=function()
 local passStates={OVT_ARM=true,OVT_IN=true,OVT_HOLD=true,OVT_OUT=true}
 local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end; return n end
 local function run(nativeBrake,seconds)
  local e,f=F.scene('P',3); C.preset('Essais','P',e.profiles.P); E.changed(e); F.tick(e,f,1/60)
  e.p.personalLineJitter=0
  -- Le joueur s'écarte alors que l'IA, 18 km/h plus vite, n'est plus qu'à 5,6 m : le radar freine aussitôt.
  F.place(f,1,10,100,2.0); F.place(f,2,0,118); F.place(f,3,5000,100)
  e.states[2].nextPerception=0
  local passed=false
  for _=1,(seconds or 4)*60 do
   F.tick(e,f,1/60,true)
   -- En jeu, la pédale lue est le maximum du freinage natif et du freinage ajouté par l'app.
   local car=f.cars[2]; car.brake=math.max(nativeBrake or 0,e.commands[2].brake)
   -- La voiture ralentit quand elle freine (au plus jusqu'à l'allure du joueur).
   car.kmh=math.max(100,car.kmh-car.brake*40/60); car.speed=car.kmh/3.6
   passed=passed or passStates[e.states[2].state] or false
  end
  return passed,e
 end
 local passed,e=run(0)
 assert(e.states[2].radarBrake>0 or count(e,'radar avant: Driver_2')>0,'radar braking behind the player who moved aside')
 assert(passed,'radar braking alone does not stop the pass')
 local blocked,e2=run(0.6,12)
 assert(not blocked,'real braking: no change of line')
 assert(count(e2,'invitation du joueur non suivie: Driver_2 derriere a')==1 and count(e2,': freinage')==1,'refused invitation explained once')
end
-- Beta 1.31 (têtes-à-queue répétés aux mêmes freinages en descente) : en dépassement, la prudence est abaissée en ligne
-- droite ; dès que l'IA freine elle-même, ou en virage, prudence au moins à sa base, agressivité au plus à sa base.
tests.CAUTION_BRAKING_131=function()
 local function scene()
  local e,f=F.scene('P',3); e.p.personalLineJitter=0; e.p.flashObliviousPct=0
  F.place(f,2,0,150); F.place(f,3,60,140); F.place(f,1,-3000,100); F.tick(e,f,0.5)
  local s=e.states[2]
  s.state='OVT_IN'; s.target=3; s.targetSide=1; s.passAlongside=false; s.passStartAt=e.time; s.passMinGap=60
  F.tick(e,f,1)
  assert(s.state=='OVT_IN' and e.commands[2].caution<s.baseCaution*0.9 and e.commands[2].aggression>s.baseAggression*1.05,'straight: caution lowered and aggression raised to pass')
  return e,f,s
 end
 local e,f,s=scene()
 f.cars[2].brake=0.6; F.tick(e,f,0.5)
 assert(e.commands[2].caution>=s.baseCaution*0.97,'own braking: caution back to its base')
 assert(e.commands[2].aggression<=s.baseAggression*1.03,'own braking: aggression back to its base')
 local e2,f2,s2=scene()
 -- Virage serré (le facteur de ligne droite suit le lacet).
 f2.cars[2].yawRate=1; F.tick(e2,f2,0.5)
 assert(e2.commands[2].caution>=s2.baseCaution*0.97,'corner: caution back to its base')
end
-- Beta 1.31 (12 tentatives sur 14 abandonnées, la cible repartant plus vite) : un écart de vitesse passager n'engage plus
-- de dépassement ; un rapprochement soutenu, oui, une fois K.passCloseMin m gagnés. Chaque tentative et sa fin au journal.
tests.PASS_SUSTAINED_131=function()
 local K=C.K
 local passStates={OVT_ARM=true,OVT_IN=true,OVT_HOLD=true,OVT_OUT=true}
 local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end; return n end
 local function scene()
  local e,f=F.scene('P',3); e.p.personalLineJitter=0; e.p.flashObliviousPct=0; e.p.pressureEnabled=false; e.p.yieldEnabled=false
  F.place(f,1,-3000,100); F.place(f,3,30,100); F.place(f,2,0,116); e.states[2].nextPerception=0
  return e,f,e.states[2]
 end
 -- Avance passagère (0,5 s), puis la cible repart plus vite : aucune tentative.
 local e,f,s=scene()
 for _=1,30 do F.tick(e,f,1/60); assert(not passStates[s.state],'no attempt on a short burst of speed') end
 F.place(f,3,30,125); s.nextPerception=0
 for _=1,120 do F.tick(e,f,1/60); assert(not passStates[s.state],'target pulls away: still no attempt') end
 -- Avance soutenue : engagé une fois le terrain gagné, noté au journal.
 local e2,f2,s2=scene()
 local started
 for n=1,180 do F.tick(e2,f2,1/60); if not started and passStates[s2.state] then started=n/60 end end
 assert(started and started>=K.passCloseMin/(16/3.6)*0.9,'sustained closing: attempt once '..K.passCloseMin..' m are gained ('..tostring(started)..')')
 assert(count(e2,'depassement: Driver_2 -> Driver_3 (rapprochement, ')==1,'attempt logged with its trigger')
 -- La cible accélère : abandon, noté avec sa raison.
 F.place(f2,3,f2.cars[3].z,130); s2.nextPerception=0; F.tick(e2,f2,5)
 assert(count(e2,'depassement fini: Driver_2 -> Driver_3 : cible plus rapide apres')==1,'end of the attempt logged with its reason')
end
-- Beta 1.31 : vrais dépassements (deux voitures à moins de 20 m qui échangent leur place), dont ceux menés par une
-- manœuvre de l'app, et IA passées devant le joueur, comptés pour le résumé de la minute.
tests.REAL_PASS_131=function()
 -- Voiture 2 derrière la voiture devant (3, ou le joueur) à 15 m, puis devant elle à 10 m.
 local function pass(ahead,app)
  local e,f=F.scene('P',3); e.p.personalLineJitter=0; e.p.yieldEnabled=false
  local other=ahead==1 and 3 or 1
  F.place(f,other,-3000,100); F.place(f,ahead,15,100); F.place(f,2,0,100); e.states[2].nextPerception=0; F.tick(e,f,0.5)
  assert(e.states[2].frontWas==ahead,'car ahead noted')
  if app then e.states[2].lastPassTarget=ahead; e.states[2].lastPassAt=e.time end
  F.place(f,2,25,100); e.states[2].nextPerception=0; F.tick(e,f,0.5)
  return e.stats.realPass or 0,e.stats.realPassApp or 0,e.stats.passedPlayer or 0
 end
 local real,app,player=pass(3,false); assert(real==1 and app==0 and player==0,'native pass counted')
 real,app,player=pass(3,true); assert(real==1 and app==1,'pass led by an app manoeuvre counted apart')
 real,app,player=pass(1,false); assert(player==1 and real==0,'AI passing the player counted apart')
end
-- Beta 1.31 : tête-à-queue d'une IA : ce que l'app lui commandait juste avant, au journal.
tests.SPIN_CONTEXT_131=function()
 local e,f=F.scene('P',3)
 F.place(f,1,-3000,100); F.place(f,2,0,120); F.place(f,3,3000,100); F.tick(e,f,0.5)
 f.cars[2].slip=50; F.tick(e,f,1.5)
 local found=false
 for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('tete-a-queue, contexte: Driver_2 | etat ',1,true) and r.message:find('prudence ',1,true) then found=true end end
 assert(found,'spin context logged')
end
-- Beta 1.32 : panneaux lumineux du circuit. Configuration lue : une section active s'allume sur une condition lue sur
-- FLAG_TYPE (définie dans le fichier, un fichier inclus ou les conditions communes de CSP).
tests.LIGHTS_SCAN_132=function()
 local Lights=require('src/lights')
 local own='[CONDITION_...]\nNAME=RACING_FLAG\nINPUT=FLAG_TYPE\nLUT=(|1=0,1,0|2=1,1,0|)\n\n[MATERIAL_ADJUSTMENT_...]\nACTIVE = 1\nCONDITION = RACING_FLAG\n;INPUT=FLAG_TYPE\n'
 assert(Lights.equipped(Lights.scan(own)),'own condition and a lit section (Spa)')
 local shared='[CONDITION_85]\nNAME=RACING_FLAG\nINPUT=FLAG_TYPE\nLUT=flag_colors.lut\n'
 assert(not Lights.equipped(Lights.scan(shared)),'shared definition alone: nothing lit (Sepang, Monaco)')
 local out=Lights.scan(shared); Lights.scan('[MATERIAL_ADJUSTMENT_3]\nCONDITION = RACING_FLAG\n',out)
 assert(Lights.equipped(out),'shared definition, section of the track (Vallelunga)')
 assert(not Lights.equipped(Lights.scan('[CONDITION_1]\nNAME=X\n;INPUT=FLAG_TYPE\nINPUT=TIME\n[LIGHT_SERIES_0]\nCONDITION=X\n')),'commented input ignored')
 assert(not Lights.equipped(Lights.scan((own:gsub('ACTIVE = 1','ACTIVE = 0')))),'inactive section ignored')
 assert(not Lights.equipped(Lights.scan('[CONDITION_2]\nNAME=OTHER\nINPUT=FLAG_TYPE\n[LIGHT_SERIES_0]\nCONDITION=RACING_FLAG\n')),'another condition')
 assert(Lights.equipped(Lights.scan('[CONDITION_0]\r\nname = myflag\r\ninput = flag_type ; flags\r\n[MATERIAL_ADJUSTMENT_0]\r\ncondition = MYFLAG\r\n')),'case, CRLF and comments')
 local inc=Lights.scan('[INCLUDE]\nINCLUDE = common/conditions.ini, ext_config-flags.ini\n[INCLUDE: extra.ini]\n')
 assert(inc.includes[1]=='common/conditions.ini' and inc.includes[2]=='ext_config-flags.ini' and inc.includes[3]=='extra.ini','included files')
 assert(not Lights.equipped(Lights.scan(nil)) and not Lights.equipped(Lights.scan('')),'empty configuration')
end
-- Fichiers lus : configuration du circuit, sa variante, fichiers inclus voisins, configurations de CSP ; une fois par
-- circuit ; rien d'écrit.
tests.LIGHTS_TRACK_FILES_132=function()
 local host=require('tests/host').create(true); local a=A.new(); assert(A.access(a))
 local sep=string.char(92)
 local function path(...) return table.concat({...},sep) end
 host.files[path('cfgsys','tracks','common','conditions.ini')]='[CONDITION_85]\nNAME=RACING_FLAG\nINPUT=FLAG_TYPE\n'
 host.files[path('tracks','alpha','extension','ext_config.ini')]='[INCLUDE]\nINCLUDE = common/conditions.ini, ext_config-flags.ini\n'
 assert(A.trackLights(a,'alpha')==false and a.trackLightsFor=='alpha','shared conditions only: not equipped')
 host.files[path('tracks','alpha','extension','ext_config-flags.ini')]='[MATERIAL_ADJUSTMENT_0]\nACTIVE=1\nCONDITION=RACING_FLAG\n'
 assert(A.trackLights(a,'alpha')==false,'read once per track')
 a.trackLightsFor=nil; assert(A.trackLights(a,'alpha')==true and a.trackLightsSource:find('ext_config-flags.ini',1,true),'neighbour include lights the panels: '..a.trackLightsSource)
 -- Configuration de CSP (loaded) d'un circuit sans la sienne (Imola, Nordschleife).
 host.files[path('cfgsys','tracks','loaded','beta.ini')]='[CONDITION_1]\nNAME=MYRACING_FLAG\nINPUT=FLAG_TYPE\n[MATERIAL_ADJUSTMENT_14]\nCONDITION=MYRACING_FLAG\n'
 assert(A.trackLights(a,'beta')==true and a.trackLightsSource:find('beta.ini',1,true),'CSP configuration')
 -- Variante du circuit.
 host.trackLayout='gp'; host.files[path('tracks','gamma','gp','extension','ext_config.ini')]=host.files[path('cfgsys','tracks','loaded','beta.ini')]
 assert(A.trackLights(a,'gamma')==true,'layout configuration')
 host.trackLayout=nil
 -- Identifiant suspect : rien lu.
 assert(A.trackLights(a,'..'..sep..'x')==nil and A.trackLights(a,'')==nil,'odd track id: unknown')
 -- Lecture qui échoue : inconnu, jamais une erreur.
 local load=io.load; io.load=function() error('read') end
 assert(A.trackLights(a,'delta')==false,'unreadable files: nothing found'); io.load=load
end
-- Valeur des panneaux : rouge, jaune (zone, neutralisation), véhicule lent, piste glissante, bleu, vert, sinon rendu à AC ;
-- rouge seulement drapeaux d'AC masqués ; dernier tour et arrivée : drapeaux d'AC.
tests.LIGHTS_DECIDE_132=function()
 local Lights=require('src/lights'); local K=C.K
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e)
 local p=e.run; local l=Lights.new(); local now=100
 local t={red=false,neutral=false,neutralMode='sc',playerYellow=false,playerFlag=false,slipperyUntil=-math.huge,greenUntil=-math.huge}
 local function at(state) for k,v in pairs(state or {}) do t[k]=v end; local v,r=Lights.decide(l,t,f,p,'C',now); l.value=v; l.reason=r; return v,r end
 assert(at()==K.flagNone,'nothing to show: handed back to AC')
 assert(at({greenUntil=now+5})==K.flagStart,'green after an end')
 assert(at({slipperyUntil=now+5})==K.flagSlippery,'slippery above green')
 l.slowSlot=2; assert(at()==K.flagSlowVehicle,'slow vehicle above slippery')
 local v,r=at({playerYellow=true,neutral=true}); assert(v==K.flagCaution and r=='voiture de securite','safety car: yellow')
 v,r=at({neutral=false}); assert(v==K.flagCaution and r=='drapeau jaune','yellow zone')
 assert(at({red=true})==K.flagStop,'red above everything')
 assert(Lights.output(l,t,true)==K.flagStop,'red passed through: the applier reads the CSP setting when writing')
 t.playerFlag=false; assert(Lights.output(l,t,false,true)==K.flagNone,'option off: nothing'); t.playerFlag=true; assert(Lights.output(l,t,false,true)==K.flagCaution,'option off: HUD preference kept')
 at({red=false,playerYellow=false,slipperyUntil=-math.huge,greenUntil=-math.huge}); l.slowSlot=0
 f.sessionLaps=5; f.timedRace=false; f.cars[1].lap=4; l.slowSlot=2
 assert(at()==K.flagNone,'last lap of a lap race: AC white flag')
 f.cars[1].lap=4; assert(at({red=true})==K.flagStop,'red still shown on the last lap')
 f.cars[1].finished=true; assert(at()==K.flagNone,'finished: chequered flag of AC')
 f.cars[1].finished=false; f.sessionLaps=0; l.slowSlot=0; t.red=false
 local player=F.place(f,1,10000+500,100); player.lap=2; player.lapValid=true; player.spline=(player.z/f.length)%1
 local fast=F.place(f,2,10000+420,150); fast.lap=3; fast.lapValid=true; fast.spline=(fast.z/f.length)%1
 F.place(f,3,10000+4000,100)
 assert(at()==K.flagFasterCar,'blue flag on the panels')
 fast.lap=2; assert(at()==K.flagNone,'same lap: no blue')
end
-- Écritures : valeur changée aussitôt vers plus important, après une tenue vers moins important ou pour rendre ; sur le
-- jaune natif, seulement le jaune ou le rouge ; jamais sur un autre drapeau d'AC ; rendue à la restitution.
tests.LIGHTS_FLAG_WRITES_132=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C'); local a=A.new(); assert(A.access(a)); local K=C.K
 a.raceFlagsHidden=true; a.hiddenReadAt=math.huge
 f.flag=K.flagNone; A.flag(a,f,K.flagFasterCar,'drapeau bleu',10); assert(a.flagOverride and host.flag==K.flagFasterCar and a.flagValue==K.flagFasterCar,'blue taken')
 f.flag=K.flagFasterCar
 A.flag(a,f,K.flagCaution,'drapeau jaune',10.2); assert(host.flag==K.flagCaution,'more important: at once')
 A.flag(a,f,K.flagStart,'drapeau vert',10.5); assert(host.flag==K.flagCaution,'less important: not before the hold')
 A.flag(a,f,K.flagStart,'drapeau vert',10.2+K.lightsHold); assert(host.flag==K.flagStart,'after the hold')
 A.flag(a,f,K.flagNone,'',10.5+K.lightsHold); assert(a.flagOverride and host.flag==K.flagStart,'handing back waits for the hold too')
 A.flag(a,f,K.flagNone,'',10.2+2*K.lightsHold+0.01); assert(not a.flagOverride and host.flag==0 and a.flagValue==K.flagNone,'handed back to AC')
 f.flag=K.flagCaution; A.flag(a,f,K.flagFasterCar,'drapeau bleu',30); assert(not a.flagOverride,'never blue over the native yellow')
 A.flag(a,f,K.flagStop,'drapeau rouge',30); assert(a.flagOverride and host.flag==K.flagStop,'red over the native yellow')
 A.restore(a,f,false,31); assert(not a.flagOverride and host.flag==0 and a.flagValue==K.flagNone,'handed back on restore')
 for _,native in ipairs({K.flagFinished,K.flagOneLapLeft,K.flagFasterCar,K.flagStop,K.flagReturnToPits}) do
  f.flag=native; A.flag(a,f,K.flagCaution,'drapeau jaune',40); assert(not a.flagOverride,'never over the native flag '..native)
 end
 -- Beta 1.34 : le drapeau de départ d'AC, qu'AC tient longtemps, ne bloque plus les panneaux.
 f.flag=K.flagStart; A.flag(a,f,K.flagCaution,'drapeau jaune',50); assert(a.flagOverride and host.flag==K.flagCaution,'over the start flag AC holds')
 A.restore(a,f,false,51); assert(not a.flagOverride)
 -- Préférence d'origine (jaune du HUD, booléen) : aussitôt, sans tenue.
 f.flag=K.flagNone; A.flag(a,f,true); assert(host.flag==K.flagCaution); A.flag(a,f,false); assert(host.flag==0 and not a.flagOverride,'boolean preference unchanged')
end
-- Beta 1.34 : session Imola du pilote en 1.32 (circuit équipé, joueur sous jaune, aucune couleur écrite en 12 minutes,
-- rien au journal). Chaque refus est noté une fois par valeur et par cause ; chaque échec de capacité aussi.
-- Beta 1.34 : jeux de règles (F1 et F1 2026 en départ arrêté), fin du tour de relance (grille, ou vert avec la raison
-- au journal), dépassement à la ligne ou dès le vert (relance ordinaire derrière la voiture de sécurité comprise).
tests.RESTART_RULES_134=function()
 local profiles={P=C.defaults('P'),Q=C.defaults('Q'),C=C.defaults('C')}
 for name,want in pairs({base='rolling',F1='standing',F1_2026='standing',GT='rolling',Endurance='rolling'}) do
  C.applyRules(name,profiles); assert(profiles.C.redRestart==want and profiles.C.restartOvertake=='line' and profiles.P.redRestart==want,name)
 end
 local function logged(e,text) for n=0,e.log.count-1 do local row=e.log[(e.log.head-n-1)%e.log.limit+1]; if row.message:find(text,1,true) then return true end end return false end
 local function scIn(redRestart,ready,overtake,relaunch)
  local e,f=F.scene('C',5); e.profiles.C.neutralization='sc'; e.profiles.C.redRestart=redRestart; e.profiles.C.restartOvertake=overtake
  e.g.safetyCarModel='sc_car'; f.cars[5].id='sc_car'; E.changed(e)
  for i=1,4 do F.place(f,i,-60-i*30,80) end; F.place(f,5,-30,80)
  F.tick(e,f,0.5); e.gridCaps=ready
  local t=e.incidents; assert(t.safety==5)
  t.neutral=true; t.relaunch=relaunch; t.neutralMode='sc'; t.safetyPhase='in'; t.safetyLeft=true; t.safetySince=e.time; t.neutralSince=e.time; t.neutralUntil=e.time
  f.cars[5].pit=true; F.tick(e,f,0.1)
  return e,t
 end
 local e,t=scIn('standing',true,'line',true)
 assert(not t.neutral and t.standing=='grid' and e.grid.phase=='grid' and t.restart and t.greenUntil<e.time,'standing start: grid, no green, no overtaking until the line')
 assert(logged(e,'relance: depart arrete (SS)') and logged(e,'voiture de securite aux stands: formation de la grille'))
 e,t=scIn('standing',false,'line',true)
 assert(t.standing=='none' and t.greenUntil>e.time and t.restart and logged(e,'relance arretee indisponible (capacites): depart lance'),'missing capability: rolling start, reason logged')
 e,t=scIn('rolling',true,'line',true); assert(t.standing=='none' and t.greenUntil>e.time and t.restart,'rolling start: green, overtaking at the line')
 e,t=scIn('rolling',true,'scIn',true); assert(not t.restart and t.messageKind=='green' and logged(e,'depassement permis'),'overtaking at once with scIn')
 e,t=scIn('standing',true,'scIn',false); assert(t.standing=='none' and not t.restart,'ordinary Safety Car restart: scIn applies, never a standing start')
 e,t=scIn('standing',true,'line',false); assert(t.standing=='none' and t.restart,'ordinary Safety Car restart: line')
end
tests.GRID_SLOTS_134=function()
 local G=require('src/grid'); local U=require('src/util'); local K=C.K
 local slots,source=G.resolve(nil,10000,3)
 assert(source=='calculees' and #slots==3 and math.abs(U.spline(-slots[1].spline)*10000-K.gridFirst)<1e-6 and math.abs(U.spline(-slots[3].spline)*10000-(K.gridFirst+2*K.gridPitch))<1e-6)
 assert(slots[1].lateral==-K.gridColumn and slots[2].lateral==K.gridColumn and slots[3].lateral==-K.gridColumn,'alternating columns')
 local nodes={{spline=1-10/10000,lateral=-0.4},{spline=1-18/10000,lateral=0.4},{spline=1-26/10000,lateral=-0.4}}
 assert(select(2,G.resolve(nodes,10000,3))=='AC_START','track nodes used when consistent')
 assert(select(2,G.resolve(nodes,10000,4))=='calculees','too few nodes for the field: computed')
 local far={{spline=1-(K.gridNodeRange+200)/10000,lateral=0}}; assert(select(2,G.resolve(far,10000,1))=='calculees','node far from the line rejected')
 local disorder={{spline=1-26/10000,lateral=0},{spline=1-10/10000,lateral=0}}; assert(select(2,G.resolve(disorder,10000,2))=='calculees','nodes out of order rejected')
 local off={{spline=1-10/10000,lateral=1.4}}; assert(select(2,G.resolve(off,10000,1))=='calculees','node off the track rejected')
 local after={{spline=10/10000,lateral=0}}; assert(select(2,G.resolve(after,10000,1))=='calculees','node past the line rejected')
 assert(G.resolve(nil,0,3)==nil,'no track length: no grid')
end
-- Formation, retenue, feux, faux départ, extinction, sanction ; voitures arrêtées à leur place sans incident.
tests.GRID_STANDING_START_134=function()
 local K=C.K; local U=require('src/util'); local L=require('src/lang')
 local e,f=F.scene('C',5); C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart='standing'; E.changed(e); e.gridCaps=true
 local pos={[2]=1,[3]=2,[1]=3,[4]=4,[5]=5}
 local function slotZ(k) return -(K.gridFirst+(k-1)*K.gridPitch) end
 for i=1,5 do f.cars[i].position=pos[i]; F.place(f,i,slotZ(pos[i])-150,60) end
 F.tick(e,f,0.2)
 local t=e.incidents; local g=e.grid; t.standing='grid'; F.tick(e,f,0.1)
 assert(g.phase=='grid' and g.slotOf[2]==1 and g.slotOf[3]==2 and g.slotOf[1]==3 and g.slotOf[4]==4 and g.slotOf[5]==5,'slots in race order, player included')
 local cmd=e.commands[2]; local d=U.spline(g.slots[1].spline-f.cars[2].spline)*f.length
 local cap=U.clamp(math.sqrt(2*K.gridApproachDecel*(d-K.gridHoldDistance))*3.6,K.gridCrawlKmh,K.gridApproachKmh)
 assert(cmd.speedLimit<=cap+1e-6 and cmd.offset==-K.gridColumn and not cmd.stopHold,'approach: speed cap from the distance, column of the slot')
 -- Derniers mètres : freinage d'appoint, puis retenue à la place ; place dépassée : retenue sur place.
 F.place(f,2,slotZ(1)-10,40); F.tick(e,f,1/60)
 assert(e.commands[2].brake>0 and not e.commands[2].stopHold,'assist brake in the last metres')
 F.place(f,2,slotZ(1)-1,0); F.place(f,3,slotZ(2)+3,5); F.place(f,4,slotZ(4),0); F.place(f,5,slotZ(5)-1,1)
 F.tick(e,f,1/60)
 for i=2,5 do assert(g.held[i] and e.commands[i].stopHold,'held on its slot '..i) end
 assert(t.standing=='grid','waits for the player')
 F.tick(e,f,10)
 assert(t.activeCount==0 and not t.neutral and not t.red,'cars stopped on the grid are no incident')
 assert(e.panel.title==L.flagTitles.standing and e.panel.short:find('P3',1,true),'player told to reach P3')
 -- Joueur à sa place : feux, jaune sur les panneaux.
 F.place(f,1,slotZ(3),0); F.tick(e,f,0.5)
 assert(t.standing=='lights' and g.phase=='lights','lights once everyone is in place')
 F.tick(e,f,1.6); assert(t.gridLit>=2 and e.panel.kind=='lights' and e.panel.lit>=2,'lights coming on')
 assert(e.lights.value==K.flagCaution,'panels yellow during the lights')
 local delay=g.outAt-g.lightsAt
 assert(delay>=K.lightStep*(K.gridLights-1)+K.lightsOutMin-1e-6 and delay<=K.lightStep*(K.gridLights-1)+K.lightsOutMax+1e-6,'lights out after the fifth light and a random hold')
 -- Faux départ : le joueur avance de 2 m avant l'extinction.
 F.place(f,1,slotZ(3)+2,4); F.tick(e,f,1/60); assert(g.jump,'jump detected')
 F.place(f,1,slotZ(3)+2,0)
 -- Règle de la reprise posée comme par la relance (dépassement interdit jusqu'à la ligne) : levée à l'extinction.
 t.restart=true; t.restartSince=e.time; for i=1,5 do t.cars[i].restart=true; t.cars[i].restartLast=f.cars[i].spline end
 local count=e.penalties.count
 for _=1,400 do if t.standing=='go' then break end; F.tick(e,f,1/60) end
 assert(t.standing=='go' and t.greenUntil>e.time and not e.commands[2].stopHold,'lights out: holds released, green')
 assert(not t.restart and not t.cars[2].restart and not t.playerRestart,'standing start: overtaking allowed from the lights out')
 F.tick(e,f,0.3)
 assert(e.penalties.count==count and e.jumpDue,'jump start: not served on the grid')
 f.cars[1].lap=f.cars[1].lap+1; F.place(f,1,K.jumpServeDistance+20,120); F.tick(e,f,0.3)
 assert(e.penalties.count==count+1 and e.penalties.reason=='jump','jump start penalised like an infringement, past the line')
 F.tick(e,f,K.goShow+0.1); assert(t.standing=='none' and g.phase=='none','procedure over')
 assert(e.panel.kind=='jump' and e.panel.title==L.flagTitles.jump,'jump start shown after the go')
end
tests.GRID_TIMEOUT_ABORT_134=function()
 local K=C.K
 local function logged(e,text) for n=0,e.log.count-1 do local row=e.log[(e.log.head-n-1)%e.log.limit+1]; if row.message:find(text,1,true) then return true end end return false end
 local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); E.changed(e); e.gridCaps=true
 for i=1,4 do f.cars[i].position=i; F.place(f,i,-500-i*50,0) end
 F.tick(e,f,0.2); e.incidents.standing='grid'; F.tick(e,f,K.gridMax+1)
 assert(e.incidents.standing=='lights' and logged(e,'grille: delai maximal'),'lights after the maximum wait')
 for i=2,4 do assert(e.commands[i].stopHold,'held where they are') end
 -- Nouvel incident (tête-à-queue) pendant la formation : départ annulé.
 local e2,f2=F.scene('C',4); C.preset('Course','C',e2.profiles.C); E.changed(e2); e2.gridCaps=true
 for i=1,4 do f2.cars[i].position=i; F.place(f2,i,-300-i*50,60) end
 F.tick(e2,f2,0.2); e2.incidents.standing='grid'; F.tick(e2,f2,0.5)
 f2.cars[3].slip=C.K.slipDegrees+20; f2.cars[3].kmh=80; F.tick(e2,f2,C.K.spinTime+1)
 assert(e2.incidents.standing=='none' and e2.grid.phase=='none' and logged(e2,'depart arrete annule: nouvel incident'),'aborted on a new incident')
 assert(not e2.commands[2].stopHold,'holds released')
end
-- Panneau du joueur pendant le tour de relance : départ lancé (et la voiture de sécurité qui rentre), départ arrêté.
tests.RESTART_PANELS_134=function()
 local L=require('src/lang'); local Panel=require('src/panel')
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,0.2)
 local t=e.incidents; local p=e.run
 local function show(phase,ready) t.neutral=true; t.relaunch=true; t.neutralMode='sc'; t.safetyPhase=phase; t.gridReady=ready; e.panel.at=-math.huge; Panel.update(e.panel,t,f,p,'C',e.time) end
 p.redRestart='rolling'; p.restartOvertake='line'
 show('out',true); assert(e.panel.kind=='rolling' and e.panel.title==L.flagTitles.rolling and e.panel.short==L.flagShort.rolling,'rolling start announced')
 show('in',true); assert(e.panel.kind=='rolling' and e.panel.short==L.flagShort.rollingIn,'Safety Car in this lap')
 p.restartOvertake='scIn'; show('in',true); assert(e.panel.short==L.flagShort.rollingGreen,'overtaking at the green')
 p.restartOvertake='line'; p.redRestart='standing'; show('out',true)
 assert(e.panel.kind=='standing' and e.panel.title==L.flagTitles.standing and e.panel.short==L.flagShort.standingLap,'standing start announced')
 show('out',false); assert(e.panel.kind=='rolling','standing start unavailable: rolling announced')
 t.neutral=false; t.relaunch=false; t.standing='grid'; t.gridPit=false; t.gridSlot=4; t.gridGap=380; e.panel.at=-math.huge; Panel.update(e.panel,t,f,p,'C',e.time)
 assert(e.panel.short==string.format(L.flagShort.standing,4,380),'slot and distance shown')
 t.gridPit=true; e.panel.at=-math.huge; Panel.update(e.panel,t,f,p,'C',e.time); assert(e.panel.short==L.flagShort.standingPit,'start from the pit lane')
 t.standing='none'
end
-- Places de grille lues dans le modèle du circuit (nœuds AC_START), une fois par circuit ; arrêtées au premier nœud absent.
tests.GRID_NODES_134=function()
 local host=require('tests/host').create(true); local a=A.new()
 local reads=0
 ac.findNodes=function(name)
  local k=tonumber(name:match('AC_START_(%d+)')); reads=reads+1
  local exists=k and k<3
  return {size=function() return exists and 1 or 0 end,getWorldTransformationRaw=function() return {position={k=k}} end}
 end
 ac.worldCoordinateToTrack=function(p) return {x=p.k%2==0 and -0.4 or 0.4,y=0,z=0.999-p.k*0.0008} end
 local nodes=A.gridNodes(a,'test')
 assert(#nodes==3 and math.abs(nodes[1].spline-0.999)<1e-9 and nodes[1].lateral==-0.4 and nodes[2].lateral==0.4,'three nodes read')
 local before=reads; assert(A.gridNodes(a,'test')==nodes and reads==before,'read once per track')
 ac.findNodes=function() error('no scene') end
 assert(A.gridNodes(a,'other')==nil,'unreadable scene: no nodes')
 assert(host)
end
-- Extinction des feux : IA réveillées une fois (aux stands : départ immédiat), jamais le joueur.
-- Départ depuis la voie des stands : retenue à l'emplacement, puis là où elle rejoint la piste ; libérée aux feux éteints.
tests.GRID_PIT_STARTER_134=function()
 local K=C.K
 local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); E.changed(e); e.gridCaps=true
 for i=1,4 do f.cars[i].position=i; F.place(f,i,-200-i*40,60) end
 f.cars[3].pit=true; f.cars[3].inPitBox=true; f.cars[3].kmh=0
 F.tick(e,f,0.2); e.incidents.standing='grid'; F.tick(e,f,0.1)
 assert(e.grid.pit[3] and e.grid.slotOf[3]==0 and e.grid.slotOf[4]==3,'pit starter has no slot, the grid is closed up')
 assert(e.commands[3].pitHold,'held in its pit box')
 f.cars[3].pit=false; f.cars[3].inPitBox=false; F.place(f,3,300,60); F.tick(e,f,1/60)
 assert(e.commands[3].stopHold and e.commands[3].speedLimit<=K.gridCrawlKmh,'left the pit lane during the grid: held where it joins')
end
tests.GRID_WAKE_134=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C',3); local a=A.new(); assert(A.access(a))
 local cmd=e.commands[2]; cmd.gridWake=true
 A.apply(a,f,e.commands,e.g,10); assert((host.awakes[1] or 0)==1,'AI woken at lights out')
 cmd.gridWake=false; A.apply(a,f,e.commands,e.g,11); assert(host.awakes[1]==1,'one frame only')
 e.commands[1].gridWake=true; A.apply(a,f,e.commands,e.g,12); assert(host.awakes[0]==nil and a.caps.awake.failures==0,'never the player')
end
tests.LIGHTS_FLAG_DIAGNOSTICS_134=function()
 local host=require('tests/host').create(true); local _,f=F.scene('C'); local a=A.new(); assert(A.access(a)); local K=C.K
 a.raceFlagsHidden=true; a.hiddenReadAt=math.huge
 local logs={}; a.note=function(level,text) logs[#logs+1]=level..' '..text end
 local function count(text) local n=0; for _,l in ipairs(logs) do if l:find(text,1,true) then n=n+1 end end; return n end
 -- Drapeau de départ d'AC tenu pendant la course : le jaune est écrit et noté.
 f.flag=K.flagStart; A.flag(a,f,K.flagCaution,'drapeau jaune',10)
 assert(a.flagOverride and host.flag==K.flagCaution and count('panneaux lumineux du circuit: jaune (drapeau jaune)')==1,'written over the held start flag')
 A.restore(a,f,false,11); assert(not a.flagOverride); logs={}
 -- Drapeau natif à respecter (bleu d'AC) : refus noté une seule fois, avec sa cause ; écrit dès qu'il est levé.
 f.flag=K.flagFasterCar
 for t=20,22 do A.flag(a,f,K.flagCaution,'drapeau jaune',t) end
 assert(not a.flagOverride and count('panneaux lumineux du circuit: jaune voulu, non ecrit (drapeau natif 12)')==1,'native refusal logged once')
 A.flag(a,f,K.flagStop,'drapeau rouge',23); assert(count('rouge voulu, non ecrit (drapeau natif 12)')==1,'new value: logged again')
 f.flag=K.flagNone; A.flag(a,f,K.flagCaution,'drapeau jaune',24); assert(a.flagOverride and host.flag==K.flagCaution,'written once AC lifts it')
 A.restore(a,f,false,25); logs={}
 -- Capacité absente : cause notée (préférence du HUD comprise).
 a.caps.flag.available=false; a.caps.flag.reason='missing'
 A.flag(a,f,true); assert(not a.flagOverride and count('drapeau HUD du joueur: jaune voulu, non ecrit (capacite missing)')==1,'missing capability logged')
 A.flag(a,f,false); A.flag(a,f,true); assert(count('capacite missing')==2,'logged again after the flag ended')
 -- Écriture en échec : erreur de CSP gardée, notée par le drapeau puis par le bilan des capacités, coupure notée.
 a.caps.flag.available=true; a.caps.flag.reason='present'; logs={}
 physics.overrideRacingFlag=function() error('not allowed here') end
 A.flag(a,f,K.flagCaution,'drapeau jaune',30)
 assert(not a.flagOverride and a.caps.flag.failures==1 and a.caps.flag.error:find('not allowed here',1,true),'error text kept')
 assert(count('jaune voulu, non ecrit (echec:')==1,'failed write logged')
 A.reportCaps(a); A.reportCaps(a); assert(count('WARN capacite flag: echec (')==1,'capability failure logged once')
 for t=31,40 do A.flag(a,f,K.flagStop,'drapeau rouge',t) end
 assert(a.caps.flag.reason=='failures' and not a.caps.flag.available)
 A.reportCaps(a); A.reportCaps(a); assert(count('WARN capacite flag: coupee apres '..K.capabilityFailures..' echecs')==1,'disabled capability logged once')
 assert(count('rouge voulu, non ecrit (capacite failures)')==1,'then the cause becomes the disabled capability')
end
-- Drapeau imposé par l'app (panneaux lumineux) : jamais lu comme un drapeau d'AC (noir, départ, bleu, jaune) ; les
-- pénalités d'AC, propres à la voiture, restent lues.
tests.NATIVE_FLAG_OWNED_132=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e); local K=C.K
 f.flagOwned=true
 for _,v in ipairs({K.flagStop,K.flagStart,K.flagFasterCar,K.flagCaution,K.flagSlippery,K.flagSlowVehicle}) do
  f.flag=v; F.tick(e,f,0.5)
  local k=e.panel.kind; assert(k~='black' and k~='green' and k~='blue' and k~='yellow','own flag '..v..' read as native: '..k)
 end
 f.cars[1].penaltyType=K.penaltyBlackFlag; F.tick(e,f,0.5); assert(e.panel.kind=='black','AC penalty still read')
 f.cars[1].penaltyType=0; f.flagOwned=false; f.flag=K.flagStop; F.tick(e,f,0.5); assert(e.panel.kind=='black','AC black flag when it is not ours')
end
-- Véhicule lent devant le joueur (drapeau blanc) : quelques secondes sous la moitié de son allure (au pas sans allure
-- connue), dans la portée, dépassement permis ; ni derrière, ni aux stands, ni en incident (drapeau jaune).
tests.LIGHTS_SLOW_VEHICLE_132=function()
 local K=C.K; local L=require('src/lang')
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e)
 F.place(f,1,1000,150); F.place(f,2,1200,20); F.place(f,3,6000,150)
 F.tick(e,f,1,true); assert(e.panel.kind~='slow' and e.lights.slowSlot==0,'not before a few seconds')
 F.tick(e,f,K.slowVehicleTime,true)
 assert(e.lights.slowSlot==2 and e.panel.kind=='slow' and e.panel.title==L.flagTitles.slow and not e.panel.noPass,'slow vehicle ahead: white flag, overtaking allowed')
 assert(e.lights.value==K.flagSlowVehicle,'white on the panels')
 local found=false; for n=0,e.log.count-1 do local row=e.log[(e.log.head-n-1)%e.log.limit+1]; if row.message:find('vehicule lent devant le joueur',1,true) then found=true end end
 assert(found,'logged once')
 -- Dépassé : derrière le joueur, plus de drapeau.
 F.place(f,2,f.cars[1].z-50,20); F.tick(e,f,0.5); assert(e.lights.slowSlot==0 and e.panel.kind~='slow','behind the player: no flag')
 -- Aux stands : jamais.
 F.place(f,2,f.cars[1].z+150,20); f.cars[2].pit=true; F.tick(e,f,K.slowVehicleTime+0.5); assert(e.lights.slowSlot==0,'pit lane: no flag')
 f.cars[2].pit=false
 -- Allure apprise : sous la moitié, véhicule lent ; au-dessus, non.
 local e2,f2=F.scene('C',3); C.preset('Course','C',e2.profiles.C); E.changed(e2)
 -- Allure de la flotte (médiane des IA de la classe) : 200 km/h partout ; celle de la voiture lente, apprise, baisse.
 for i=2,3 do local s=e2.states[i]; s.paceCount=K.paceMinBins; for b=1,K.paceBins do s.pace[b]=200/3.6 end end
 F.place(f2,1,1000,150); F.place(f2,2,1200,120); F.place(f2,3,6000,150)
 F.tick(e2,f2,K.slowVehicleTime+0.5); assert(e2.lights.slowSlot==0,'above half its pace: not slow')
 F.place(f2,2,1200,80); F.tick(e2,f2,K.slowVehicleTime+0.5); assert(e2.lights.slowSlot==2,'below half its pace: slow vehicle')
 -- Arrêtée : incident, drapeau jaune (pas blanc).
 F.place(f2,2,1200,0); f2.cars[2].stopped=1; F.tick(e2,f2,4)
 assert(e2.incidents.cars[2].incident and e2.lights.slowSlot==0 and e2.lights.value==K.flagCaution,'stopped car: yellow, not white')
 -- Drapeaux jaunes de l'app coupés : rien.
 local e3,f3=F.scene('C',3); C.preset('Course','C',e3.profiles.C); e3.profiles.C.yellowEnabled=false; E.changed(e3)
 F.place(f3,1,1000,150); F.place(f3,2,1200,20); F.tick(e3,f3,K.slowVehicleTime+1); assert(e3.lights.slowSlot==0,'app flags off: no white flag')
end
-- Avertissement (drapeau noir et blanc) : place à rendre une fois le drapeau levé ; dernière infraction tolérée, différée
-- sous drapeau ; voiture endommagée (drapeau noir à disque orange) ; dépassement permis ; textes dans les deux langues.
tests.PANEL_WARNINGS_132=function()
 local Panel=require('src/panel'); local L=require('src/lang'); local en=require('src/lang_en'); local K=C.K
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e)
 local p=e.run; local panel=Panel.new(); local now=100; local l=require('src/lights').new()
 local t={red=false,neutral=false,neutralMode='fcy',safetyPhase='none',playerZone=false,playerDistance=0,greenUntil=-math.huge}
 local function at(state) for k,v in pairs(state or {}) do t[k]=v end; now=now+1; Panel.update(panel,t,f,p,'C',now,l); return panel.kind end
 panel.giveBackDue=true
 assert(at({playerZone=true,playerToZone=100,playerInside=false})=='yellow','the flag itself first')
 assert(at({playerZone=false})=='warning' and panel.title==L.flagTitles.warning and panel.raw==L.flagDetails.giveBack and not panel.noPass,'give the place back')
 panel.giveBackDue=false
 Panel.warn(panel); assert(at({playerZone=true})=='yellow','final warning deferred under a flag')
 assert(at({playerZone=false})=='warning' and panel.raw==L.flagDetails.warning,'final warning shown')
 assert(at()=='warning','for a few seconds')
 now=now+K.warningShow; assert(at()=='none','then cleared')
 l.meatballUntil=now+5; assert(at()=='meatball' and panel.title==L.flagTitles.meatball and not panel.noPass,'car damaged')
 l.slowSlot=2; l.slowGap=123; assert(at()=='slow' and panel.raw==string.format(L.flagDetails.slow,120),'slow vehicle above the damage notice')
 l.slowSlot=0; l.meatballUntil=-math.huge; assert(at()=='none')
 Panel.warn(panel); p.flagPanel=false; at(); p.flagPanel=true; assert(at()=='none','pending warning dropped with the panel off')
 for _,k in ipairs({'slow','warning','meatball'}) do assert(L.flagTitles[k] and en.flagTitles[k],k) end
 for _,k in ipairs({'slow','giveBack','warning','meatball'}) do assert(L.flagDetails[k] and en.flagDetails[k] and L.flagShort[k] and en.flagShort[k] and L.flagExplain[k] and en.flagExplain[k],k) end
end
-- Dégâts du joueur : lus une fois par seconde (à part de ceux des IA) ; annoncés à leur apparition ; jamais sans dégâts
-- mécaniques ; une réparation réarme l'annonce.
tests.PLAYER_DAMAGE_132=function()
 local host=require('tests/host').create(true); local K=C.K
 local Snapshot=require('src/snapshot'); local s=Snapshot.new()
 host.cars[0].damage={[0]=60,[1]=50,[2]=0,[3]=0,[4]=0}; host.cars[0].suspensionDamage={[0]=0.3,[1]=0,[2]=0,[3]=0}; host.cars[0].engineLifeLeft=900; host.cars[0].gearboxDamage=0
 Snapshot.read(s,1/60,10)
 assert(s.player==1 and s.playerDamageSlot==1 and s.playerBody==110 and math.abs(s.playerSuspension-0.3)<1e-9 and s.playerEngine==900,'player damage read')
 assert(s.cars[1].damageBody==0,'AI damage fields untouched for the player')
 assert(s.playerDamageAt==10+K.playerDamagePeriod,'next read in a second')
 host.cars[0].engineLifeLeft=500; Snapshot.read(s,1/60,10.5); assert(s.playerEngine==900,'not read again before a second')
 Snapshot.read(s,1/60,11.1); assert(s.playerEngine==500 and s.playerDamageAt==11.1+K.playerDamagePeriod,'read again after a second')
 local Lights=require('src/lights'); local l=Lights.new()
 local e,f=F.scene('C',3)
 f.playerDamageSlot=1; f.damageRate=1; f.playerSuspension=0.3; f.playerBody=0; f.playerEngine=1000; f.playerGearbox=0; f.playerBlown=false
 assert(Lights.update(l,e.incidents,f,e.run,'C',e.delta,e.states,false,20) and l.meatballUntil==20+K.meatballShow,'new damage announced')
 assert(not Lights.update(l,e.incidents,f,e.run,'C',e.delta,e.states,false,21),'announced once')
 f.playerEngine=500; assert(Lights.update(l,e.incidents,f,e.run,'C',e.delta,e.states,false,22),'another part damaged: announced again')
 f.playerSuspension=0; f.playerEngine=1000; Lights.update(l,e.incidents,f,e.run,'C',e.delta,e.states,false,23); assert(not l.damaged,'repaired')
 f.playerBlown=true; assert(Lights.update(l,e.incidents,f,e.run,'C',e.delta,e.states,false,24),'blown tyre')
 f.playerBlown=false; Lights.update(l,e.incidents,f,e.run,'C',e.delta,e.states,false,25)
 f.damageRate=0; f.playerSuspension=0.9; assert(not Lights.update(l,e.incidents,f,e.run,'C',e.delta,e.states,false,26),'damage disabled: never')
 f.damageRate=1; f.cars[1].pit=true; assert(not Lights.update(l,e.incidents,f,e.run,'C',e.delta,e.states,false,27),'pit lane: not announced')
end
-- Beta 1.32 : avertissement (drapeau noir et blanc) après la dernière infraction tolérée seulement ; levé à la
-- disqualification.
tests.PLAYER_FINAL_WARNING_132=function()
 local e,f=F.scene('C',3); e.profiles.C.penaltyDisqualify=2; e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
 F.place(f,3,6000,0); local z=0; local warned,early=false,false
 for _=1,60*90 do
  z=z+150/3.6/60; F.place(f,1,z,150); F.tick(e,f,1/60)
  local pending=e.panel.warnPending or e.panel.warnUntil>-math.huge
  if pending and e.penalties.count<2 then early=true end
  if pending and e.penalties.count==2 then warned=true end
 end
 assert(warned and not early,'final warning after the last tolerated infraction only')
 assert(e.penalties.disqualified and not e.panel.warnPending and e.panel.warnUntil==-math.huge,'dropped once disqualified')
end
-- Beta 1.33 : mise à jour depuis GitHub (logique pure, port réel sur une imitation de CSP).
for name,fn in pairs(require('tests/updates')) do assert(tests[name]==nil,'duplicate test '..name); tests[name]=fn end
-- Beta 1.35 engine fixes : relecture du moteur (départ arrêté, panneaux lumineux, diagnostics, performance).
local function engineLogged(e,text) for n=0,e.log.count-1 do local row=e.log[(e.log.head-n-1)%e.log.limit+1]; if row and row.message:find(text,1,true) then return true end end return false end
local function standingScene(n)
 local e,f=F.scene('C',n); C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart='standing'; E.changed(e); e.gridCaps=true
 for i=1,n do f.cars[i].position=i end
 return e,f
end
local function slotZ(k) return -(C.K.gridFirst+(k-1)*C.K.gridPitch) end
-- B1 : distance à la place mesurée vers l'avant ; seule une voiture juste au-delà de sa place y est retenue.
tests.GRID_FORWARD_DISTANCE_135=function()
 local K=C.K; local Grid=require('src/grid')
 local e,f=standingScene(4)
 F.place(f,1,slotZ(1)-300,0); F.place(f,2,2500,150); F.place(f,3,slotZ(3)+10,40); F.place(f,4,slotZ(4)-80,60)
 F.tick(e,f,0.2); e.incidents.standing='grid'; F.tick(e,f,1/60)
 local g=e.grid
 assert(g.phase=='grid','formation')
 assert(Grid.gap(g,f,2)>f.length*0.7 and not g.held[2] and not e.commands[2].stopHold and e.commands[2].speedLimit>K.gridCrawlKmh,'car a quarter lap past the line drives on to its slot')
 assert(g.held[3] and e.commands[3].stopHold and Grid.gap(g,f,3)<0,'just past its slot: held there')
 assert(not g.held[4] and math.abs(Grid.gap(g,f,4)-80)<1,'behind its slot: forward distance')
end
-- B1 : tour de relance sous VSC d'un départ arrêté, fini par le meneur près de la ligne, jamais au délai.
tests.RELAUNCH_LEADER_LAP_135=function()
 local K=C.K
 local e,f=standingScene(4); e.profiles.C.neutralization='vsc'; E.changed(e); F.tick(e,f,0.2)
 local t=e.incidents
 t.neutral=true; t.relaunch=true; t.neutralMode='vsc'; t.neutralSince=e.time; t.neutralUntil=e.time+1; t.relaunchSpanUntil=e.time; t.relaunchLeader=0; t.relaunchTravel=0; t.gridReady=true
 for i=1,4 do F.place(f,i,f.length-300-i*30,90) end
 F.tick(e,f,1/60); F.tick(e,f,1/60)
 assert(t.neutral and t.standing=='none','leader near the line right after the pits: a lap to go first')
 t.relaunchLeader=0; t.relaunchTravel=0
 for i=1,4 do F.place(f,i,1000-i*30,90) end
 F.tick(e,f,3)
 assert(t.neutral and t.relaunch and t.standing=='none','the timer alone no longer ends the relaunch lap')
 for z=2000,f.length-K.gridFormFrom-200,1500 do for i=1,4 do F.place(f,i,z-i*30,90) end; F.tick(e,f,1/60) end
 assert(t.neutral and t.standing=='none','still far from the line')
 for i=1,4 do F.place(f,i,f.length-K.gridFormFrom+100-i*30,90) end; F.tick(e,f,1/60)
 assert(not t.neutral and t.standing=='grid' and not t.ending,'formation once the leader completes its lap (no VSC ending)')
end
-- M1, M2 : faux départ armé seulement le joueur en place et à l'arrêt ; jamais au départ des stands ; vers l'avant.
tests.JUMP_ARMED_WHEN_PLACED_135=function()
 local K=C.K
 local e,f=standingScene(3); F.place(f,1,slotZ(1)-400,60); F.place(f,2,slotZ(2),0); F.place(f,3,slotZ(3),0)
 F.tick(e,f,0.2); e.incidents.standing='grid'; F.tick(e,f,K.gridMax+0.5)
 local g=e.grid
 assert(e.incidents.standing=='lights','lights on timeout')
 F.place(f,1,slotZ(1)-390,60); F.tick(e,f,1)
 assert(not g.jump and not g.refSet,'not in place: no reference, no jump')
 F.place(f,1,slotZ(1),0); F.tick(e,f,0.2); assert(g.refSet,'reference taken once in place and still')
 F.place(f,1,slotZ(1)-1.5,4); F.tick(e,f,1/60); assert(not g.jump,'rolling back is no jump')
 -- Départ des stands : jamais de faux départ, même en sortant pendant les feux.
 local e2,f2=standingScene(3); f2.cars[1].pit=true; F.place(f2,2,slotZ(1),0); F.place(f2,3,slotZ(2),0)
 F.tick(e2,f2,0.2); e2.incidents.standing='grid'; F.tick(e2,f2,0.5)
 assert(e2.incidents.standing=='lights' and e2.grid.pit[1],'pit starter: lights without waiting')
 f2.cars[1].pit=false; F.place(f2,1,-200,0); F.tick(e2,f2,0.2); F.place(f2,1,-195,10); F.tick(e2,f2,1/60)
 assert(not e2.grid.jump,'pit starter leaving during the lights: no jump')
 -- Pénalités du joueur coupées : ni sanction ni panneau.
 local e3,f3=standingScene(2); e3.profiles.C.playerPenalties=false; E.changed(e3); F.place(f3,1,slotZ(1),0); F.place(f3,2,slotZ(2),0)
 F.tick(e3,f3,0.2); e3.incidents.standing='grid'; F.tick(e3,f3,1.5); F.place(f3,1,slotZ(1)+3,10); F.tick(e3,f3,1/60)
 assert(e3.grid.jump,'jump seen')
 for _=1,600 do if e3.incidents.standing=='go' then break end; F.tick(e3,f3,1/60) end
 assert(e3.incidents.standing=='go' and not e3.jumpDue and e3.incidents.jumpUntil<e3.time and engineLogged(e3,'sans sanction'),'no penalty, no JUMP START panel')
end
-- M3, M6 : panneaux à la relance (vert, jamais véhicule lent) ; pénalité d'AC du joueur jamais couverte.
tests.LIGHTS_RESTART_AND_PENALTY_135=function()
 local K=C.K; local Lights=require('src/lights')
 local e,f=F.scene('C',3); F.place(f,1,-100,80); F.place(f,2,0,5); F.place(f,3,3000,100); F.tick(e,f,0.2)
 local l=e.lights; local t=e.incidents
 local function slowAt(now) for j=1,3 do l.slowFor[j]=K.slowVehicleTime+1 end; t.cars[2].moved=true; t.cars[2].incident=false; e.states[2].pitCautionUntil=0; l.at=-math.huge; l.last=now-0.25; Lights.update(l,t,f,e.run,'C',e.delta,e.states,false,now) end
 t.greenUntil=-math.huge; t.standing='none'; t.restart=false; t.neutral=false; t.red=false
 slowAt(e.time); assert(l.slowSlot==2,'slow vehicle seen outside the procedures')
 t.standing='go'; slowAt(e.time)
 assert(l.slowSlot==0 and l.slowFor[2]==0 and l.value==K.flagStart,'lights out: green, slow vehicle reset')
 t.standing='none'; t.restart=true; slowAt(e.time); assert(l.slowSlot==0,'restart: no slow vehicle')
 t.restart=false; t.greenUntil=e.time; slowAt(e.time+K.slowGrace*0.5); assert(l.slowSlot==0,'grace after the green')
 t.greenUntil=-math.huge; t.neutral=true; slowAt(e.time); assert(l.slowSlot==0,'neutralisation: no slow vehicle')
 t.neutral=false; t.playerYellow=true; l.playerPenalty=true
 assert(Lights.decide(l,t,f,e.run,'C',e.time)==K.flagNone,'AC penalty or disqualification: flag handed back')
 l.playerPenalty=false; assert(Lights.decide(l,t,f,e.run,'C',e.time)==K.flagCaution,'yellow again once lifted')
 -- Engine : pénalité d'AC lue sur la voiture du joueur.
 t.playerYellow=false; f.cars[1].penaltyType=3; F.tick(e,f,0.5); assert(e.lights.playerPenalty and e.lights.value==K.flagNone,'player penalty read by the engine')
end
-- M4 : protections de départ à l'extinction, colonne de la place reprise par le pilotage ; M5 : recomptage, stands.
tests.GRID_RELEASE_AND_RECOUNT_135=function()
 local K=C.K
 local e,f=standingScene(4); F.place(f,1,slotZ(1),0); F.place(f,2,slotZ(2),0); F.place(f,3,slotZ(3),0); F.place(f,4,-600,60)
 F.tick(e,f,0.2); e.incidents.standing='grid'; F.tick(e,f,0.3)
 assert(e.incidents.standing=='grid','waits for car 4')
 e.commands[4].rulePit=true; f.cars[4].pit=true; F.tick(e,f,0.3)
 assert(e.incidents.standing=='lights','car gone to the pits: no longer awaited')
 f.cars[4].pit=false; F.place(f,4,-600,60)
 local Pits=require('src/pits'); local pitsUpdate=Pits.update
 Pits.update=function(...) pitsUpdate(...); e.commands[3].rulePit=true end
 local okPits,errPits=pcall(F.tick,e,f,1/60); Pits.update=pitsUpdate; assert(okPits,errPits)
 assert(not e.commands[3].rulePit,'no pit request during the formation')
 local g=e.grid; local lat=g.slots[g.slotOf[2]].lateral
 for _=1,600 do if e.incidents.standing=='go' then break end; F.tick(e,f,1/60) end
 assert(e.incidents.standing=='go' and math.abs(e.launchAt-e.time)<=1/30,'launch time set at the lights out')
 local s=e.states[2]; local o=e.g.offsetSign<0 and -lat or lat
 assert(math.abs(s.filtered-o)<0.2,'steering state starts from the column of the slot')
 F.tick(e,f,0.1)
 assert(e.states[2].state=='IDLE','start delay of the race applied at the restart')
end
-- Mineurs : nœuds de grille jamais modifiés, places côte à côte, nœuds au-delà du nombre ignorés, raison notée.
tests.GRID_NODES_RESOLVE_135=function()
 local K=C.K; local Grid=require('src/grid')
 local L=10000
 local function node(before,lat) return {spline=((-before)/L)%1,lateral=lat} end
 local nodes={node(6,-0.4),node(6,0.4),node(14,-0.4),node(14,0.4),node(5000,0)}
 local out,source=Grid.resolve(nodes,L,4,{})
 assert(source=='AC_START' and out~=nodes and #out==4 and out[2].lateral==0.4,'side by side accepted, extra nodes ignored, copied')
 local copy,src2,why=Grid.resolve(nodes,L,5,out)
 assert(src2=='calculees' and why:find('noeud 5',1,true) and nodes[1].lateral==-0.4 and nodes[1].spline==((-6)/L)%1,'fallback never writes into the track nodes')
 assert(copy==out,'reuses the output table')
 local _,_,why2=Grid.resolve({node(6,0)},L,3,{}); assert(why2:find('1 noeuds pour 3',1,true),'reason when too few nodes')
end
-- Mineurs : place du joueur au mètre près, en place / dépassée ; sans place, départ des stands ; feux à l'heure.
tests.GRID_PLAYER_SLOT_TEXT_135=function()
 local K=C.K
 local e,f=standingScene(3); F.place(f,1,slotZ(1)-15.4,20); F.place(f,2,slotZ(2),0); F.place(f,3,-900,60)
 F.tick(e,f,0.2); e.incidents.standing='grid'; F.tick(e,f,1/60)
 local t=e.incidents
 assert(t.gridSlot==1 and t.gridGap==15 and not t.gridPlaced and not t.gridPassed,'metres below 20 m')
 F.place(f,1,slotZ(1)-120,20); F.tick(e,f,1/60); assert(t.gridGap==120,'rounded to 10 m beyond')
 F.place(f,1,slotZ(1),0); F.tick(e,f,1/60); assert(t.gridPlaced,'in position')
 F.place(f,1,slotZ(1)+12,0); F.tick(e,f,1/60); assert(t.gridPassed and not t.gridPlaced and t.gridGap==12,'slot passed, metres behind')
 -- Beta 1.36 : au-delà de K.gridOvershoot m, toujours « place dépassée » avec la distance en arrière, jamais presque un tour.
 F.place(f,1,slotZ(1)+60,0); F.tick(e,f,1/60); assert(t.gridPassed and t.gridGap==60,'60 m past the slot: passed, 60 m')
 F.place(f,1,slotZ(1)+K.gridPassedShow+200,80); F.tick(e,f,1/60); assert(not t.gridPassed and t.gridGap>f.length*0.5,'far past: slot ahead again (next lap)')
 F.place(f,1,slotZ(1)+12,0); F.tick(e,f,1/60)
 e.panel.at=-math.huge; require('src/panel').update(e.panel,t,f,e.run,'C',e.time,e.lights); assert(e.panel.slotPassed,'passed cue for the overlay')
 local e2,f2=standingScene(2); f2.cars[1].pit=true; F.place(f2,2,slotZ(1),0); F.tick(e2,f2,0.2); e2.incidents.standing='grid'; F.tick(e2,f2,1/60)
 f2.cars[1].pit=false; F.place(f2,1,-300,40); F.tick(e2,f2,1/60)
 assert(e2.incidents.gridPit,'player without a slot: pit-lane start, never P0')
end
-- Mineurs : pause sans rendu à AC, rouge relu au moment d'écrire, refus oublié à la session, restitution notée.
tests.FLAG_PAUSE_RED_SESSION_135=function()
 local K=C.K; local host=require('tests/host').create(true)
 local e,f=F.scene('C',3); F.tick(e,f,0.2)
 e.lights.value=K.flagCaution; f.paused=true; F.tick(e,f,0.2); assert(e.lights.value==K.flagCaution,'pause keeps the panel value')
 f.paused=false
 local a=A.new(); assert(A.access(a)); local logs={}; a.note=function(level,text) logs[#logs+1]=text end
 a.raceFlagsHidden=true; a.hiddenReadAt=-math.huge
 A.flag(a,f,K.flagStop,'drapeau rouge',10); assert(host.flag==K.flagCaution,'red only if AC flags are still hidden at write time')
 A.restore(a,f,false,11)
 local found=false; for _,t in ipairs(logs) do if t:find('rendus a AC (commandes rendues)',1,true) then found=true end end
 assert(found,'restore logged')
 f.flag=K.flagFasterCar; A.flag(a,f,K.flagCaution,'drapeau jaune',12); assert(a.flagBlocked,'refusal noted')
 A.nextSession(a,f); assert(a.flagBlocked==nil,'forgotten at the next session')
 -- Décalage du temps (24 h) : attentes de l'applicateur décalées aussi.
 local s=a.cars[2]; s.placeAt=100; s.launchAt=200; s.scKickAt=300; A.rebase(a,50)
 assert(s.placeAt==50 and s.launchAt==150 and s.scKickAt==250,'rebase covers placement and Safety Car timers')
end
-- Mineur : une ligne de véhicule lent au plus toutes les K.slowLogGap s quand le plus proche change.
tests.SLOW_LOG_RATE_135=function()
 local K=C.K; local e,f=F.scene('C',3); F.tick(e,f,0.2)
 local l=e.lights; local before=e.log.count
 l.slowSlot=2; l.slowKmh=20; l.slowGap=100; e.slowLogged=0; e.slowLoggedAt=nil
 local Lights=require('src/lights'); local update=Lights.update
 Lights.update=function() return false end
 F.tick(e,f,1/60); local n1=e.log.count
 l.slowSlot=3; F.tick(e,f,1/60); local n2=e.log.count
 Lights.update=update
 assert(n1==before+1 and n2==n1,'second slow car within the gap: not logged')
end
-- P1 : occupation latérale accélérée, mêmes résultats que le calcul complet.
tests.OCCUPANCY_EQUIVALENT_135=function()
 local P=require('src/perception'); local g=C.validateGlobals(C.globalDefaults); local K=C.K
 local function reference(cars,count,i,r)
  local a=cars[i]; r.left=false; r.right=false; local nearest2=math.huge
  for j=1,count do
   local b=cars[j]
   if i~=j and b.valid and not b.pit then
    local dx,dz=b.x-a.x,b.z-a.z
    local long=dx*a.lx+dz*a.lz; local lat=-dx*a.lz+dz*a.lx
    local closing=math.max(0,long>0 and a.speed-b.speed or b.speed-a.speed)
    local reach=(a.length+b.length)*0.5+g.occMargin+g.occSpeedGain*closing
    nearest2=math.min(nearest2,dx*dx+dz*dz)
    if math.abs(long)<=reach then
     if math.abs(lat)<g.occLatMin and math.abs(long)<=(a.length+b.length)*0.5+K.overlapMargin then r.left=true; r.right=true
     elseif lat>=g.occLatMin and lat<=g.occLatMax then r.left=true
     elseif lat<=-g.occLatMin and lat>=-g.occLatMax then r.right=true end
    end
   end
  end
  r.nearest=math.sqrt(nearest2)
 end
 local seed=12345; local function rnd() seed=(seed*1103515245+12345)%2147483648; return seed/2147483648 end
 for _=1,200 do
  local cars={}; local n=12
  for j=1,n do local h=rnd()*6.283; cars[j]={valid=rnd()>0.05,pit=rnd()<0.05,x=rnd()*40-20,z=rnd()*80-40,lx=math.sin(h),lz=math.cos(h),speed=rnd()*80,length=3.5+rnd()*2} end
  for i=1,n do
   local r1,r2={},{}; reference(cars,n,i,r1); P.occupancy(cars,n,i,g,r2)
   assert(r1.left==r2.left and r1.right==r2.right and math.abs(r1.nearest-r2.nearest)<1e-9,'same occupancy')
  end
 end
end
-- Beta 1.35 engine fixes : aucune sanction de dépassement pendant la formation de la grille (voitures qui rejoignent
-- leur place, parfois dans le désordre).
tests.AI_NO_SANCTION_DURING_FORMATION_135=function()
 local Pe=require('src/penalties')
 local e,f=F.scene('C',4); e.run.aiPenalties=true
 local st={}; for i=1,4 do st[i]={yellow=false} end
 local function step(t,za,zb,standing)
  F.place(f,2,za,100); F.place(f,3,zb,100); F.place(f,4,5000,100)
  e.incidents.cars[2].restart=true; e.incidents.cars[3].restart=true; e.incidents.standing=standing
  e.states[2].nextPerception=0; F.tick(e,f,1/60); e.incidents.standing=standing
  return Pe.ai(t,f,e.run,'C',e.incidents,st,e.perception.rows,e.time)
 end
 local t=Pe.new(); step(t,0,20,'grid'); assert(not step(t,30,20,'grid') and not t.ai.count[2],'formation: passing to reach the slot, no sanction')
 local t2=Pe.new(); step(t2,0,20,'none'); assert(step(t2,30,20,'none'),'restart regime outside the formation: sanctioned')
end
-- Beta 1.36 (3e relecture) : faux départ jamais sanctionné à l'arrêt sur la grille, même après un calage de 30 s.
tests.GRID_JUMP_STALL_136=function()
 local K=C.K
 local e,f=standingScene(3); F.place(f,1,slotZ(1),0); F.place(f,2,slotZ(2),0); F.place(f,3,slotZ(3),0); F.tick(e,f,0.2)
 local count=e.penalties.count
 e.jumpDue=true; e.jumpGoAt=e.time; e.jumpLap=f.cars[1].lap or 0
 F.tick(e,f,K.jumpServeMax+1)
 assert(e.jumpDue and e.penalties.count==count,'stalled on the grid: never served while stationary')
 F.place(f,1,slotZ(1)+8,20); F.tick(e,f,0.3)
 assert(not e.jumpDue and e.penalties.count==count+1 and e.penalties.reason=='jump','served once the player moves off')
end
-- Beta 1.36 : rouge et neutralisation avant la pénalité du joueur ; disqualification seule rend le drapeau à AC.
tests.LIGHTS_PRIORITY_136=function()
 local K=C.K; local Lights=require('src/lights')
 local e,f=F.scene('C',3); F.tick(e,f,0.2)
 local l=e.lights; local t=e.incidents
 t.red=false; t.neutral=true; t.neutralMode='sc'; t.playerYellow=true; l.playerPenalty=true; l.playerDisqualified=false
 local v,r=Lights.decide(l,t,f,e.run,'C',e.time); assert(v==K.flagCaution and r=='voiture de securite','safety car above the app penalty')
 t.neutral=false; assert(Lights.decide(l,t,f,e.run,'C',e.time)==K.flagNone,'local yellow: AC penalty kept')
 t.red=true; assert(Lights.decide(l,t,f,e.run,'C',e.time)==K.flagStop,'red above the app penalty')
 l.playerDisqualified=true; assert(Lights.decide(l,t,f,e.run,'C',e.time)==K.flagNone,'disqualified: AC black flag, even under red')
 t.red=false; t.playerYellow=false
 -- Engine : drapeau noir d'AC (4) = disqualification ; coupure des gaz (3) = pénalité seulement.
 f.cars[1].penaltyType=3; F.tick(e,f,0.3); assert(e.lights.playerPenalty and not e.lights.playerDisqualified,'slow-down penalty: not a disqualification')
 f.cars[1].penaltyType=K.penaltyBlackFlag; F.tick(e,f,0.3); assert(e.lights.playerDisqualified,'black flag: disqualified')
 f.cars[1].penaltyType=0; F.tick(e,f,0.3); assert(not e.lights.playerDisqualified and not e.lights.playerPenalty,'lifted')
end
-- Beta 1.36 : à l'extinction, colonne seulement pour les IA retenues près de leur place (jamais pour une voiture lâchée
-- par le délai maximal loin de sa place).
tests.GRID_RELEASE_COLUMN_136=function()
 local K=C.K
 local e,f=standingScene(4); F.place(f,1,slotZ(1),0); F.place(f,2,slotZ(2),0); F.place(f,3,slotZ(3),0); F.place(f,4,-900,60)
 F.tick(e,f,0.2); e.incidents.standing='grid'; F.tick(e,f,0.2)
 local g=e.grid; local k4=g.slotOf[4]; assert(k4 and k4>0,'car 4 has a slot')
 local lat=g.slots[k4].lateral; local o4=e.g.offsetSign<0 and -lat or lat
 local s4=e.states[4]
 g.since=e.time-K.gridMax-1
 for _=1,900 do if e.incidents.standing=='go' then break end; F.place(f,4,-900,60); s4.offset=0.123; s4.filtered=0.123; F.tick(e,f,1/60) end
 assert(e.incidents.standing=='go','lights out after the timeout')
 assert(math.abs(s4.filtered-0.123)<0.05 and math.abs(o4-0.123)>0.1,'far car: no lateral jump to its column')
end
-- Beta 1.37 : section Panneaux lumineux de chaque profil (défauts, couleurs, durées, tenue, migration, préréglages).
tests.LIGHTS_SECTION_137=function()
 local K=C.K; local Lights=require('src/lights'); local Panel=require('src/panel')
 for _,profile in ipairs(C.profiles) do
  local p=C.defaults(profile); assert(C.on(p,'lights') and p.lightsRed and p.lightsGreenTime==5 and p.lightsHold==1.5,'defaults: '..profile)
  local q=C.validate(profile,p); q.lightsYellow=false; q=C.validate(profile,q); assert(q.lightsYellow==true,'yellow always on')
  local old=C.defaults(profile); old.section_lights=nil; assert(C.on(C.validate(profile,old),'lights'),'older record: ticked')
 end
 for _,name in ipairs({'Nordschleife','Essais','Qualifications','Course','Endurance'}) do assert(C.on(C.preset(name,'C',{}),'lights'),name) end
 local only=C.defaults('J'); assert(not C.any(only) and not C.anySection(only),'panels alone never drive the AI')
 -- Révision 18 : option globale décochée (Beta 1.32 à 1.36) gardée, section décochée partout.
 local function stored(track)
  local g=C.validateGlobals(C.globalDefaults,{}); g.dataRevision=17; g.presetsUsed=true; g.trackLights=track
  local profiles={}; for _,profile in ipairs(C.profiles) do profiles[profile]=C.validate(profile,C.defaults(profile)); profiles[profile].configured=true end
  C.migrate(g,profiles); return g,profiles
 end
 local g,ps=stored(false); assert(g.dataRevision==C.dataRevision)
 for _,profile in ipairs(C.profiles) do assert(not C.on(ps[profile],'lights'),'global off kept: '..profile) end
 g,ps=stored(true); for _,profile in ipairs(C.profiles) do assert(C.on(ps[profile],'lights'),'global on: '..profile) end
 -- Couleurs.
 local e,f=F.scene('C',3); F.tick(e,f,0.2)
 local l=e.lights; local t=e.incidents; local p=e.run
 t.red=true; assert(Lights.decide(l,t,f,p,'C',e.time)==K.flagStop,'red by default')
 p.lightsRed=false; local v,r=Lights.decide(l,t,f,p,'C',e.time); assert(v==K.flagCaution and r=='drapeau rouge','red off: yellow instead')
 p.lightsRed=true; t.red=false
 l.slowSlot=2; assert(Lights.decide(l,t,f,p,'C',e.time)==K.flagSlowVehicle,'white')
 p.lightsWhite=false; assert(Lights.decide(l,t,f,p,'C',e.time)~=K.flagSlowVehicle,'white off'); p.lightsWhite=true; l.slowSlot=0
 t.slipperyUntil=e.time+10; assert(Lights.decide(l,t,f,p,'C',e.time)==K.flagSlippery,'orange')
 p.lightsOrange=false; assert(Lights.decide(l,t,f,p,'C',e.time)~=K.flagSlippery,'orange off'); p.lightsOrange=true; t.slipperyUntil=-math.huge
 local blue=Panel.blue; Panel.blue=function() return true end
 local okBlue,errBlue=pcall(function()
  assert(Lights.decide(l,t,f,p,'C',e.time)==K.flagFasterCar,'blue')
  p.lightsBlue=false; assert(Lights.decide(l,t,f,p,'C',e.time)~=K.flagFasterCar,'blue off'); p.lightsBlue=true
 end)
 Panel.blue=blue; assert(okBlue,errBlue)
 -- Vert : 5 s par défaut (durées de la 1.36), mis à l'échelle de la durée réglée ; 0 ou interrupteur coupé : aucun vert.
 local now=e.time; t.greenUntil=now+K.greenShow
 assert(Lights.decide(l,t,f,p,'C',now)==K.flagStart,'green')
 assert(Lights.decide(l,t,f,p,'C',now+4.9)==K.flagStart and Lights.decide(l,t,f,p,'C',now+5.1)==K.flagNone,'5 s by default, as in 1.36')
 p.lightsGreenTime=10; t.greenUntil=now+1+K.greenShow; Lights.decide(l,t,f,p,'C',now+1)
 assert(Lights.decide(l,t,f,p,'C',now+10.9)==K.flagStart and Lights.decide(l,t,f,p,'C',now+11.1)==K.flagNone,'10 s')
 t.greenUntil=now+20+K.greenZoneShow; Lights.decide(l,t,f,p,'C',now+20)
 assert(Lights.decide(l,t,f,p,'C',now+25.9)==K.flagStart and Lights.decide(l,t,f,p,'C',now+26.1)==K.flagNone,'zone end: three fifths of it')
 p.lightsGreenTime=0; t.greenUntil=now+40+K.greenShow; assert(Lights.decide(l,t,f,p,'C',now+40)==K.flagNone,'0: no green')
 p.lightsGreenTime=5; p.lightsGreen=false; t.greenUntil=now+50+K.greenShow; assert(Lights.decide(l,t,f,p,'C',now+50)==K.flagNone,'green off')
 t.standing='go'; assert(Lights.decide(l,t,f,p,'C',now+51)~=K.flagStart,'restart green off'); p.lightsGreen=true; t.standing='none'
 -- Tenue : vers moins important, après la durée réglée ; vers plus important, aussitôt ; sans réglage, K.lightsHold.
 require('tests/host').create(true); local a=A.new(); assert(A.access(a)); local h=f; h.flag=0
 A.flag(a,h,K.flagCaution,'drapeau jaune',100,4); assert(a.flagOverride and a.flagValue==K.flagCaution)
 A.flag(a,h,K.flagStart,'drapeau vert',102,4); assert(a.flagValue==K.flagCaution,'held 4 s, not 1.5')
 A.flag(a,h,K.flagStart,'drapeau vert',104.1,4); assert(a.flagValue==K.flagStart,'after 4 s')
 A.flag(a,h,K.flagCaution,'drapeau jaune',104.2,4); assert(a.flagValue==K.flagCaution,'more important: at once')
 A.flag(a,h,0,'',105,nil); assert(a.flagOverride,'default hold 1.5 s')
 A.flag(a,h,0,'',105.8,nil); assert(not a.flagOverride,'handed back after 1.5 s')
end
-- Beta 1.38 (maquette) : cinq feux allumés, consigne propre ; avant, consigne d'attente.
tests.PANEL_LIGHTS_ALL_138=function()
 local L=require('src/lang'); local Panel=require('src/panel')
 local e,f=F.scene('C',3)
 local t=e.incidents; t.standing='lights'; t.gridLit=3
 Panel.update(e.panel,t,f,e.run,'C',e.time+1)
 assert(e.panel.kind=='lights' and e.panel.short==L.flagShort.lights,'lights coming on: '..tostring(e.panel.kind)..' '..tostring(e.panel.short))
 t.gridLit=C.K.gridLights; Panel.update(e.panel,t,f,e.run,'C',e.time+2)
 assert(e.panel.kind=='lights' and e.panel.short==L.flagShort.lightsAll,'five lights: own instruction')
end
-- Beta 1.41 : trafic des IA (fichier à part).
for name,test in pairs(require('tests/ai141')) do assert(tests[name]==nil,name); tests[name]=test end
for name,test in pairs(require('tests/schema142')) do assert(tests[name]==nil,name); tests[name]=test end
for name,test in pairs(require('tests/aero142')) do assert(tests[name]==nil,name); tests[name]=test end
-- 1.42 STRATEGY : stratégie, tour de sortie, usure, pannes (fichier à part).
for name,test in pairs(require('tests/strategy142')) do assert(tests[name]==nil,name); tests[name]=test end
for name,test in pairs(require('tests/sanctions142')) do assert(tests[name]==nil,name); tests[name]=test end
-- Beta 1.42, fusion : défauts trouvés par la scène de course complète, et la scène elle-même.
for name,test in pairs(require('tests/merge142')) do assert(tests[name]==nil,name); tests[name]=test end
-- Beta 1.42, relecture adverse des sanctions des IA.
for name,test in pairs(require('tests/review142x')) do assert(tests[name]==nil,name); tests[name]=test end
for name,test in pairs(require('tests/fixsa142')) do assert(tests[name]==nil,name); tests[name]=test end -- FIXSA 1.42 (relecture STRATÉGIE et AERO)
for name,test in pairs(require('tests/postfix142')) do assert(tests[name]==nil,name); tests[name]=test end -- POSTFIX 1.42 (relecture des correctifs)
for name,test in pairs(require('tests/notices143')) do assert(tests[name]==nil,name); tests[name]=test end -- Beta 1.43 (annonces des sanctions des IA)
for name,test in pairs(require('tests/player144')) do assert(tests[name]==nil,name); tests[name]=test end -- Beta 1.44 (IA derrière le joueur qui ralentit)
for name,test in pairs(require('tests/fix147')) do assert(tests[name]==nil,name); tests[name]=test end -- Beta 1.47 (départs, défense, boucles, usure)
for name,test in pairs(require('tests/firstlap147')) do assert(tests[name]==nil,name); tests[name]=test end -- Beta 1.47 (premier tour attentif)
for name,test in pairs(require('tests/pits149')) do assert(tests[name]==nil,name); tests[name]=test end -- Beta 1.49 (arrêt F1 : composé, rappels, stratégie des stands)
for name,test in pairs(require('tests/start150')) do assert(tests[name]==nil,name); tests[name]=test end
for name,test in pairs(require('tests/quali151')) do assert(tests[name]==nil,name); tests[name]=test end -- Beta 1.51 (préréglage de la session, arrêt obligatoire, tours lancés) -- Beta 1.50 (départ en ligne droite, sortie de la voiture de sécurité, annonces)
-- Beta 1.50 : pose en piste de la voiture de sécurité (Beta 1.48) gardée en repli ; ces scènes l'exercent avec une voiture
-- de sécurité qui ne quitte jamais son emplacement, libérée dès la fin de l'appel, sans règle de vue du joueur (testées
-- dans tests/start150.lua).
local function placeFallback(fn)
 return function()
  local K=C.K; local keep={K.scLeaveMax,K.scExitLead,K.scHideAhead,K.scHideBehind}
  K.scLeaveMax=0; K.scExitLead=1e9; K.scHideAhead=0; K.scHideBehind=0
  local ok,err=pcall(fn)
  K.scLeaveMax,K.scExitLead,K.scHideAhead,K.scHideBehind=keep[1],keep[2],keep[3],keep[4]
  if not ok then error(err,0) end
 end
end
for _,name in ipairs({'SAFETY_CAR_CYCLE','SAFETY_CAR_STAYS_OUT','SAFETY_CAR_ESCALATION','SAFETY_CAR_PIT_EXIT','RED_FLAG_RELAUNCH_SC','SAFETY_CAR_STUCK','DRS_LATE_LOAD_AND_SC_QUEUE'}) do assert(tests[name],name); tests[name]=placeFallback(tests[name]) end
-- Beta 1.48 : reprendre sa place de l'ordre figé au drapeau rouge n'est pas un dépassement sous drapeau ; doubler une
-- voiture mieux classée l'est ; la voiture de sécurité jamais ; plus rien après la ligne.
tests.RED_FLAG_ORDER_EXEMPTION=function()
 local Incidents=require('src/incidents'); local Penalties=require('src/penalties')
 local function scene(playerRank)
  local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); E.changed(e)
  F.place(f,1,1000,150); F.place(f,2,1010,150); F.place(f,3,5000,150); F.place(f,4,7000,150)
  F.tick(e,f,0.5)
  local t=e.incidents
  t.redOrderN=3; t.redOrder={1,2,3}
  if playerRank==1 then t.redRank[1]=1; t.redRank[2]=2 else t.redRank[2]=1; t.redRank[1]=2 end
  t.redRank[3]=3
  t.restart=true; t.restartSince=e.time; for i=1,4 do t.cars[i].restart=true; t.cars[i].restartLast=f.cars[i].spline end
  F.tick(e,f,0.2); e.penalties.regimeAt=e.time-20
  return e,f,t
 end
 local e,f,t=scene(1)
 assert(Incidents.restoring(t,1,2) and not Incidents.restoring(t,2,1) and not Incidents.restoring(t,1,4) and not Incidents.restoring(t,4,1),'better-classed car only, never an unranked car (safety car)')
 assert(Penalties.mayPass(e.penalties,1,2,e.time,1)==false and Incidents.restoring(t,1,2),'driving: the director adds the exemption')
 F.place(f,1,1020,150); F.tick(e,f,0.3)
 assert(e.penalties.count==0,'player retakes its place: no penalty')
 local logged=false; for n=0,e.log.count-1 do local row=e.log[(e.log.head-n-1)%e.log.limit+1]; if row.message:find('reprend sa place sur Driver_2',1,true) then logged=true end end
 assert(logged,'logged')
 local e2,f2=scene(2)
 F.place(f2,1,1020,150); F.tick(e2,f2,0.3)
 assert(e2.penalties.count==1 and e2.penalties.reason=='pass','passing a better-classed car: penalty')
 -- Ligne franchie par tous : ordre levé, plus d'exemption.
 local e3,f3,t3=scene(1)
 for i=1,4 do F.place(f3,i,9900+i,150) end; F.tick(e3,f3,0.1)
 for i=1,4 do F.place(f3,i,10000+50+i,150) end; F.tick(e3,f3,0.3)
 assert(not t3.restart and t3.redOrderN==0 and not Incidents.restoring(t3,1,2),'after the line: no exemption')
end
-- Beta 1.48 : arrêts sous drapeau rouge : F1, changement de pneus compté même avant la fenêtre ; GT, ni pneus ni arrêt
-- compté, même arrivée à son emplacement après la reprise ; joueur (changement de composé obligatoire) : compté
-- seulement si le composé change.
tests.RED_FLAG_STOPS_148=function()
 local function red(category,after)
  local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); C.applyRules(category,e.profiles)
  if category=='GT' then e.profiles.C.pitWindowOpenPct=5 end
  E.changed(e)
  f.sessionLaps=10; f.leaderLaps=category=='GT' and 5 or 0
  local a=f.cars[2]; a.tyresKnown=true; a.compoundIndex=0; a.dryCompounds={[0]=true,[1]=true}
  F.tick(e,f,0.5); e.incidents.red=true; e.incidents.redSince=e.time; e.incidents.redMax=1e4
  a.pit=true; F.tick(e,f,0.5)
  if after then e.incidents.red=false end
  a.inPitBox=true; a.kmh=0; F.tick(e,f,0.5)
  return e
 end
 local f1=red('F1'); assert(f1.commands[2].pitCompound==1 and f1.pits.cars[2].windowStops==1,'F1: red-flag tyre change on lap 1 counts')
 local gt=red('GT',true); assert(gt.commands[2].pitCompound==-1 and gt.pits.cars[2].windowStops==0,'GT: in the pits under red, at its box after it: no tyres, not counted')
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); C.applyRules('F1',e.profiles); E.changed(e)
 f.sessionLaps=10; f.leaderLaps=5; local a=f.cars[1]; a.compoundIndex=0; F.tick(e,f,0.5)
 a.pit=true; a.inPitBox=true; a.kmh=0; F.tick(e,f,0.5); a.inPitBox=false; F.tick(e,f,0.5)
 assert(e.pits.cars[1].windowStops==0,'player, same compound: not counted')
 a.inPitBox=true; F.tick(e,f,0.5); a.compoundIndex=1; a.inPitBox=false; F.tick(e,f,0.5)
 assert(e.pits.cars[1].windowStops==1,'player, compound changed: counted')
end
-- Beta 1.48 : départ arrêté après un drapeau rouge : grille dans l'ordre figé au drapeau rouge, pas au classement d'AC.
tests.RED_FLAG_STANDING_ORDER_148=function()
 local Grid=require('src/grid')
 local e,f=F.scene('C',4)
 for i=1,4 do F.place(f,i,1000+i*100,100); f.cars[i].position=i end
 local t=e.incidents; t.redOrderN=4; t.redRank[1]=4; t.redRank[2]=3; t.redRank[3]=2; t.redRank[4]=1
 Grid.start(e.grid,t,f,e.time,e.log)
 assert(e.grid.order[1]==4 and e.grid.order[2]==3 and e.grid.order[4]==1,'grid in the frozen order')
 t.redOrderN=0; Grid.start(e.grid,t,f,e.time,e.log)
 assert(e.grid.order[1]==1 and e.grid.order[4]==4,'otherwise the AC classification')
end
-- Beta 1.48 (relecture) : nouveau drapeau rouge pendant la sortie des stands, puis levé (règles décochées) : aucune IA
-- retenue à son emplacement par la sortie précédente.
tests.RED_FLAG_CANCEL_GATES_148=function()
 local e,f=F.scene('C',7); C.preset('Course','C',e.profiles.C); E.changed(e)
 for i=5,7 do F.place(f,i,(i-1)*300,120) end
 F.tick(e,f,0.5); local t=e.incidents
 for i=2,4 do local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0 end
 t.releaseN=3; t.releaseList={2,3,4}; for i=2,4 do t.gate[i]=true; t.releaseAt[i]=e.time+100 end
 F.tick(e,f,0.1); assert(e.commands[3].pitHold,'held by the pit exit')
 F.block(f,{5,6,7},600)
 F.tick(e,f,C.K.redIncidentStill+3)
 assert(t.red,'new red flag')
 e.profiles.C.redFlagEnabled=false; E.changed(e); F.tick(e,f,0.5)
 assert(not t.red and t.redCancelled,'cancelled')
 for i=2,4 do assert(not t.gate[i] and not e.commands[i].pitHold,'no AI left held '..i) end
end
return tests
