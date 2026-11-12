-- Affinage 1.61 (coût en jeu, Spa 40 IA) : métadonnées des voitures relues par tranches. Chargé par tests/extended.lua.
local K=require('src/config').K
local H=require('tests/host')
local tests={}
-- Hôte de test agrandi à n voitures (copies de la voiture 1), toutes à leur place sur la piste.
local function grow(host,n)
 for i=4,n-1 do
  local c={}; for k,v in pairs(host.cars[1]) do c[k]=v end
  c.index=i; c.position={x=0,y=0,z=(i-1)*120}; c.splinePosition=(i-1)*0.012; c.aabbSize={x=1.85,z=4.4}
  host.cars[i]=c
 end
 host.sim.carsCount=n
end
-- Première lecture : toutes les voitures d'un coup ; relecture périodique : K.metaCarsPerFrame voitures par image,
-- dans l'ordre, la passe finie en quelques images ; une voiture au-delà de la tranche n'est relue qu'à son tour.
tests.META_SLICED_161U=function()
 local host=H.create(true); local Snapshot=require('src/snapshot'); local f=Snapshot.new()
 local n=20; grow(host,n)
 Snapshot.read(f,1/60,0)
 for i=2,n do assert(math.abs(f.cars[i].length-4.4)<1e-6,'first read complete '..i) end
 assert(f.metaNext==n+1,'first pass done in one frame')
 for i=1,n-1 do host.cars[i].aabbSize={x=1.9,z=5} end
 local t=K.metaPeriod+0.2
 Snapshot.read(f,1/60,t)
 local per=K.metaCarsPerFrame
 assert(per<n-1,'slice smaller than the field')
 for i=2,per do assert(math.abs(f.cars[i].length-5)<1e-6,'first slice read '..i) end
 assert(math.abs(f.cars[per+1].length-4.4)<1e-6,'car beyond the slice not read yet')
 assert(f.metaNext==per+1,'cursor after the first slice')
 local frames=1
 while f.metaNext<=n do t=t+1/60; Snapshot.read(f,1/60,t); frames=frames+1; assert(frames<=math.ceil(n/per),'pass ends') end
 for i=2,n do assert(math.abs(f.cars[i].length-5)<1e-6,'every car read again '..i) end
 assert(frames==math.ceil(n/per),'frames for the pass')
end
-- Changement de session : passe complète dans la même image (identités connues avant toute décision).
tests.META_FULL_ON_SESSION_161U=function()
 local host=H.create(true); local Snapshot=require('src/snapshot'); local f=Snapshot.new()
 local n=20; grow(host,n)
 Snapshot.read(f,1/60,0)
 for i=1,n-1 do host.cars[i].aabbSize={x=1.9,z=5} end
 host.sim.currentSessionIndex=1
 Snapshot.read(f,1/60,0.1)
 for i=2,n do assert(math.abs(f.cars[i].length-5)<1e-6,'full pass at a session change '..i) end
 assert(f.metaNext==n+1)
end
return tests
