local W=require('tests/workload')
-- Même cache du compilateur JIT que l'app en jeu (fichier d'entrée) ; voitures pilotées comme en jeu.
local jitTuned=pcall(require('jit').opt.start,'maxtrace=8000','maxmcode=16384')
-- Beta 1.60 (lot 5) : mêmes limites de trace que l'app (AdvancedIA.lua).
if jitTuned then pcall(require('jit').opt.start,'maxside=400','loopunroll=30','maxrecord=20000','maxirconst=2000','maxsnap=2000') end
local E=require('src/engine')
return function(clock,count,frames,profiling)
 local e,f=W.prepare(count); local dt=1/60; e.batchCars=jitTuned
 for _=1,2000 do W.animate(f,e.time,dt); E.step(e,f,dt) end
 local profile=require('jit.profile'); local stacks,states={},{}
 if profiling then profile.start('fi2',function(thread,samples,state)
  local key=profile.dumpstack(thread,'l',1); stacks[key]=(stacks[key] or 0)+samples; states[state]=(states[state] or 0)+samples
 end) end
 local times={}; local sum,maximum=0,0
 for i=1,frames do
  W.animate(f,e.time,dt); local before=clock(); E.step(e,f,dt); local cost=(clock()-before)*1000
  times[i]=cost; sum=sum+cost; maximum=math.max(maximum,cost); assert(e.errors==0)
 end
 if profiling then profile.stop() end
 table.sort(times)
 return {ai=count,frames=frames,meanMs=sum/frames,p99Ms=times[math.ceil(frames*0.99)],peakMs=maximum,stacks=stacks,vmstates=states,errors=e.errors}
end
