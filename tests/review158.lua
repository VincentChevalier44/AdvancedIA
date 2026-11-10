-- Beta 1.58 (MJFox, Overtake ; vu aussi par le pilote) : après l'arrivée, des IA rentrant aux stands tapaient le mur et se
-- percutaient : une voiture gardée par l'app n'est plus commandée dans la voie des stands, et ses dernières valeurs y
-- restaient (décalage, vitesse limitée, prudence…). Elle y est maintenant rendue à AC. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local A=require('src/applier')
local C=require('src/config')
local K=C.K
local E=require('src/engine')
local tests={}
-- Voiture 2 de la scène commandée (décalage, vitesse limitée, niveau, prudence), puis état choisi par setup.
local function driven(profile)
 local host=require('tests/host').create(true); local e,f=F.scene(profile or 'C'); local a=A.new(); assert(A.access(a))
 local lines={}; a.note=function(level,text) lines[#lines+1]=level..' '..text end
 for _,cmd in ipairs(e.commands) do cmd.active=false; cmd.weatherManaged=false end
 local cmd=e.commands[2]; cmd.active=true; cmd.offset=0.2; cmd.speedLimit=150; cmd.level=1.05; cmd.levelOwned=true; cmd.caution=2; cmd.cautionOwned=true
 e.g.offsetSign=-1; a.offsetSign=-1; a.g=e.g
 A.apply(a,f,e.commands,e.g,1)
 local s=a.cars[2]; assert(s.owned and host.offsets[1]==-0.2 and host.speedLimits[1]==150 and s.caution~=nil,'car driven')
 return host,e,f,a,s,cmd,lines
end
local function frames(a,f,e,from,to,step) local t=from; while t<=to+1e-9 do A.restore(a,f,true,t); A.apply(a,f,e.commands,e.g,t); t=t+step end end
tests.LANE_RELEASE_AFTER_FINISH_158=function()
 local host,e,f,a,s,cmd,lines=driven()
 cmd.active=false; f.cars[2].finished=true; f.cars[2].pit=true
 local seen={}
 local t=1; while t<=1.5 do A.restore(a,f,true,t); A.apply(a,f,e.commands,e.g,t); seen[#seen+1]=host.offsets[1]; t=t+1/60 end
 local ramp=false; for _,v in ipairs(seen) do if v<0 and v>-0.2 then ramp=true end end
 assert(ramp,'offset ramped back, not jumped')
 assert(host.offsets[1]==0 and s.offset==0 and s.offsetReset,'offset given back to 0 within the ramp')
 assert(host.speedLimits[1]==K.unlimitedSpeed and s.speed==nil,'speed cap lifted')
 assert(s.level==nil and s.caution==nil and math.abs(host.cars[1].aiLevel-s.originalLevel)<1e-9,'native level and caution given back')
 assert(s.owned,'ownership kept (handled again if it leaves the lane)')
 local n=0; for _,l in ipairs(lines) do if l:find('voiture rendue a AC apres l arrivee',1,true) then n=n+1 end end
 assert(n==1,'one line')
 local calls=host.calls; frames(a,f,e,1.6,3,1/60); assert(host.calls==calls,'nothing more written once released')
end
tests.LANE_RELEASE_MID_RACE_158=function()
 -- Arrêt en course, pneus gérés par l'app (commande toujours voulue : jamais marquée à rendre) : rendue dans la voie,
 -- reprise normalement à la sortie.
 local host,e,f,a,s,cmd,lines=driven()
 cmd.active=false; cmd.weatherManaged=true; f.cars[2].pit=true
 frames(a,f,e,1,1.5,1/60)
 assert(host.offsets[1]==0 and host.speedLimits[1]==K.unlimitedSpeed and s.level==nil,'released in the lane')
 local n=0; for _,l in ipairs(lines) do if l:find('voiture rendue a AC dans la voie des stands',1,true) then n=n+1 end end
 assert(n==1,'one line')
 f.cars[2].pit=false; cmd.active=true; cmd.weatherManaged=false; A.restore(a,f,true,2); A.apply(a,f,e.commands,e.g,2)
 assert(host.offsets[1]==-0.2 and host.speedLimits[1]==150,'driven again after the lane')
 -- Deuxième passage de la même session : pas de deuxième ligne.
 cmd.active=false; f.cars[2].pit=true; frames(a,f,e,2.1,2.6,1/60)
 n=0; for _,l in ipairs(lines) do if l:find('voiture rendue a AC',1,true) then n=n+1 end end
 assert(n==1 and host.offsets[1]==0,'released again, logged once per session')
end
tests.LANE_RELEASE_KEEPS_PIT_REQUEST_158=function()
 local host,e,f,a,s,cmd=driven()
 s.pitRequest=true; host.pitRequests[1]=true
 cmd.active=false; f.cars[2].pit=true; frames(a,f,e,1,1.5,1/60)
 assert(s.pitRequest and host.pitRequests[1]==true,'the app pit request is kept in the lane')
 assert(host.offsets[1]==0,'but the offset is given back')
end
tests.LANE_RELEASE_HELD_CARS_158=function()
 -- Tenue exprès (garée : voiture de réserve, disqualifiée ; retenue à son box) : jamais rendue dans la voie.
 for _,held in ipairs({{'scPark','parked','spare'},{'pitHold','stop'}}) do
  local host,e,f,a,s,cmd=driven()
  s[held[2]]=true; cmd.active=false; cmd[held[1]]=true; cmd.parkReason=held[3] or 'sc'; f.cars[2].pit=true; f.cars[2].inPitBox=true; f.cars[2].kmh=0
  local level=host.cars[1].aiLevel; frames(a,f,e,1,1.5,1/60)
  assert(s[held[2]],held[1]..': held')
  assert(host.offsets[1]==-0.2 and host.speedLimits[1]==150 and host.cars[1].aiLevel==level and s.laneAt==nil,held[1]..': held on purpose, untouched')
 end
end
tests.LANE_RELEASE_ONLY_IN_LANE_158=function()
 -- Sur la piste, rien ne change : le chemin de restitution d'avant (voisin libre) reste le seul.
 local host,e,f,a,s,cmd=driven()
 cmd.active=false; cmd.weatherManaged=true
 frames(a,f,e,1,1.5,1/60)
 assert(host.offsets[1]==-0.2 and s.laneAt==nil,'on track: no lane release')
 assert(K.laneReleaseRate>0 and K.laneReleaseStep>0)
end
-- Beta 1.58 (course du pilote, fn_imola) : composé de l'arrêt jamais déjà roulé quand il en reste ; borne des passages
-- servis pendant une même demande.
local Pits=require('src/pits')
tests.PIT_COMPOUND_STABLE_158=function()
 local a={tyresKnown=true,compoundIndex=1,dryCompounds={[0]=true,[1]=true,[2]=true}}
 local cmd={weatherManaged=false,weatherRain=false,weatherCompound=-1}; local p={pitCompoundChange=true}
 assert(Pits.compound(a,cmd,p)==0,'old rule kept without the used list')
 assert(Pits.compound(a,cmd,p,{[0]=true,[1]=true})==2,'a dry compound not yet used in the race first')
 assert(Pits.compound(a,cmd,p,{[0]=true,[1]=true,[2]=true})==0,'all used: another one than the fitted compound')
 -- SS, puis S (dépannage), puis l'arrêt : M ; plus jamais de retour à SS tant qu'un composé reste à rouler.
 a.compoundIndex=2; assert(Pits.compound(a,cmd,p,{[0]=true,[1]=true,[2]=true})==0,'everything used: like before')
 a.compoundIndex=1; assert(Pits.compound(a,cmd,{pitCompoundChange=false},{[0]=true})==1,'no compound rule: same compound, fresh set')
 cmd.weatherManaged=true; cmd.weatherRain=true; cmd.weatherCompound=3; assert(Pits.compound(a,cmd,p,{})==3,'weather first')
end
tests.PIT_REQUEST_SERVICE_CAP_158=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); local p=e.profiles.C; p.mandatoryStops=1; p.maxStintMin=0; p.minPitTime=0; p.pitWindowOpenPct=10; p.pitWindowClosePct=90
 E.changed(e); f.sessionLaps=10; f.leaderLaps=9
 local lines={}; local t=Pits.new(); t.note=function(level,text) lines[#lines+1]=level..' '..text end
 Pits.update(t,f,e.commands,p,'C',100,1,nil,false)
 local c=t.cars[2]; assert(c.wanted,'stop requested in the window')
 -- Servie deux fois pendant la même demande sans arrêt compté (règles fermées à l'arrivée) : la demande est abandonnée.
 c.requestServices=K.pitRequestServiceMax
 Pits.update(t,f,e.commands,p,'C',101,1,nil,false)
 local warn=0; for _,l in ipairs(lines) do if l:find('WARN arret demande abandonne',1,true) then warn=warn+1 end end
 assert(not c.wanted and not e.commands[2].rulePit and c.requestAbandoned and warn==1,'abandoned once, with a warning')
 assert(not c.deferred,'an abandoned request holds no call slot')
 Pits.update(t,f,e.commands,p,'C',102,1,nil,false); Pits.update(t,f,e.commands,p,'C',103,1,nil,false)
 warn=0; for _,l in ipairs(lines) do if l:find('arret demande abandonne',1,true) then warn=warn+1 end end
 assert(not c.wanted and warn==1,'never requested again, one line')
 Pits.reset(t,104); assert(not t.cars[2].requestAbandoned and t.cars[2].requestServices==0,'forgotten with the session')
end
tests.PIT_COMPOUND_TWO_USED_158=function()
 -- Deux composés secs déjà roulés : la règle d'avant (un autre que celui monté), plus de descente SS -> S -> M -> H.
 local a={tyresKnown=true,compoundIndex=1,dryCompounds={[0]=true,[1]=true,[2]=true,[3]=true}}
 local cmd={weatherManaged=false,weatherRain=false,weatherCompound=-1}; local p={pitCompoundChange=true}
 assert(Pits.compound(a,cmd,p,{[0]=true},1)==2,'one compound used: an unused one')
 assert(Pits.compound(a,cmd,p,{[0]=true,[1]=true},2)==0,'two used: another than the fitted one, as before')
end
tests.PIT_APP_TOW_NOT_THE_STOP_158=function()
 -- Dépannage par l'app d'une IA dont l'arrêt obligatoire est demandé : jamais compté ; plus demandé dans la voie après le
 -- service (AC ne la ramène pas à son emplacement), redemandé en piste, puis compté au vrai arrêt.
 local e,f=F.scene('C',3); local run={}; for k,v in pairs(e.run) do run[k]=v end
 run.mandatoryStops=1; run.pitWindowOpenPct=10; run.pitWindowClosePct=95; run.pitTyres=true; run.maxStintMin=0; run.minPitTime=0
 f.sessionLaps=10; f.leaderLaps=9; f.timedRace=false
 local t=Pits.new(); local cmds={}; for i=1,f.count do cmds[i]={} end
 local now=100
 local function step(red) now=now+0.5; Pits.update(t,f,cmds,run,'C',now,1,nil,red or false,nil,false) end
 step(); local c=t.cars[2]; local a=f.cars[2]; assert(c.wanted,'requested')
 cmds[2].recover=true; step(); cmds[2].recover=false
 -- Beta 1.59 : à l'arrêt à son emplacement (passage servi seulement une fois vraiment arrêtée).
 a.pit=true; a.inPitBox=true; a.kmh=0; a.teleport=true; step(); a.teleport=false
 assert(c.windowStops==0 and c.requestServices==1,'app tow: not the requested stop')
 a.inPitBox=false; step()
 assert(cmds[2].laneServed and not cmds[2].rulePit and not c.wanted,'served in this lane pass: no request before the lane exit')
 a.pit=false; step(); assert(c.wanted and cmds[2].rulePit and not cmds[2].laneServed,'requested again on track')
 assert(c.requestServices==1,'kept for the safety net')
 now=now+K.towWindow+1
 a.pit=true; step(); a.inPitBox=true; step()
 assert(c.windowStops==1,'the real stop counts')
 a.inPitBox=false; step(); assert(not c.wanted,'done')
end
tests.PIT_ONE_SERVICE_PER_LANE_158=function()
 -- Ramenée à son emplacement sans être sortie de la voie : ni arrêt compté, ni nouveau service, une ligne.
 local e,f=F.scene('C',3); local run={}; for k,v in pairs(e.run) do run[k]=v end
 run.mandatoryStops=1; run.pitWindowOpenPct=10; run.pitWindowClosePct=95; run.pitTyres=true; run.pitRepair=true; run.pitCompoundChange=true; run.maxStintMin=0; run.minPitTime=0
 f.sessionLaps=10; f.leaderLaps=9; f.timedRace=false
 local a=f.cars[2]; a.tyresKnown=true; a.compoundIndex=0; a.dryCompounds={[0]=true,[1]=true,[2]=true}
 local lines={}; local t=Pits.new(); t.note=function(level,text) lines[#lines+1]=level..' '..text end
 local cmds={}; for i=1,f.count do cmds[i]={} end
 local now=100
 local function step() now=now+0.5; Pits.update(t,f,cmds,run,'C',now,1,nil,false,nil,false) end
 step(); local c=t.cars[2]
 a.pit=true; step(); a.inPitBox=true; a.kmh=0; a.damageBody=50; step()
 assert(c.windowStops==1 and cmds[2].pitCompound==1 and cmds[2].pitRepair,'first arrival: counted, tyres and repairs')
 a.compoundIndex=1
 for _=1,3 do a.inPitBox=false; step(); assert(cmds[2].laneServed,'out of the box, still in the lane'); a.inPitBox=true; step()
  assert(cmds[2].pitCompound==-1 and not cmds[2].pitRepair and c.windowStops==1 and c.stops==1,'back in its box in the same lane pass: nothing more') end
 local n=0; for _,l in ipairs(lines) do if l:find('INFO emplacement de nouveau sans sortie de la voie des stands',1,true) then n=n+1 end end
 assert(n==1,'one line')
 a.inPitBox=false; a.pit=false; step(); assert(c.laneVisit==nil and not cmds[2].laneServed,'lane pass over')
end
tests.PIT_USED_PASSED_158=function()
 -- Roulée en SS, arrivée à l'emplacement déjà en S (changé par AC) : M, jamais un retour au SS de départ.
 local e,f=F.scene('C',3); local run={}; for k,v in pairs(e.run) do run[k]=v end
 run.mandatoryStops=1; run.pitWindowOpenPct=10; run.pitWindowClosePct=95; run.pitTyres=true; run.pitCompoundChange=true; run.maxStintMin=0; run.minPitTime=0
 f.sessionLaps=10; f.leaderLaps=9; f.timedRace=false
 local a=f.cars[2]; a.tyresKnown=true; a.compoundIndex=0; a.dryCompounds={[0]=true,[1]=true,[2]=true}
 local t=Pits.new(); local cmds={}; for i=1,f.count do cmds[i]={} end
 Pits.update(t,f,cmds,run,'C',100,1,nil,false,nil,false)
 a.pit=true; a.inPitBox=true; a.compoundIndex=1; Pits.update(t,f,cmds,run,'C',100.5,1,nil,false,nil,false)
 assert(cmds[2].pitCompound==2,'not back to the starting compound: '..tostring(cmds[2].pitCompound))
end
return tests
