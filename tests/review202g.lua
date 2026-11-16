-- Affinage 2.0.2 g (course du 15 novembre, 15 h 17) : défense anticipée jugée sur le point de freinage appris (la carte des
-- lignes droites, morcelée, ne la mettait jamais « dans la bande ») ; IA accidentée retenue tant qu'une voiture en course
-- toute proche est là, même arrêtée dans une file sous double jaune. Noms terminés par _202 ou LOCK_. Chargé par
-- tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Snapshot=require('src/snapshot')
local I=require('src/incidents')
local K=C.K
local tests={}
-- Leader 2 à 250 km/h, suiveur 3 à gap m derrière, même vitesse, aligné ; carte des lignes droites morcelée (run 0
-- partout, comme en file) ; point de freinage appris ahead m devant le leader ; turn : sens du virage suivant.
local function run(turn,gap,ahead)
 local e,f=F.scene('C',3); local p=e.profiles.C
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.defenseEnabled=true; p.startDelay=0; p.startRelax=0
 p.towBreakEnabled=false; p.slipstreamEnabled=false
 E.changed(e)
 local saved=Snapshot.turnAhead
 Snapshot.turnAhead=function() return turn end
 local s=e.states[2]
 local ok,err=pcall(function()
  local z=3*f.length+1000
  F.place(f,1,z-5000,100); F.place(f,2,z,250); F.place(f,3,z-gap-4.4,250,0)
  F.tick(e,f,1/60)
  local m=e.aero; assert(m and m.bins>0,'aero map')
  for b=1,m.bins do m.seen[b]=K.towMapSeen; m.st[b]=0; m.run[b]=0 end
  for k=1,30 do
   F.place(f,1,z-5000,100); F.place(f,2,z,250); F.place(f,3,z-gap-4.4,250,0)
   e.fl.points[1]=((f.cars[2].z+ahead)/f.length)%1; e.fl.count=1
   e.states[3].state='DRIVE'; s.nextPerception=0; m.at=e.time
   F.tick(e,f,1/60)
  end
 end)
 Snapshot.turnAhead=saved
 assert(ok,err)
 return s,e
end
local function covered(s) return s.state=='DEFEND' and s.reason=='cover' end
tests.K_202G=function() assert(K.rejoinNear==true and K.rejoinNearBehind==40 and K.raceSlowNoUnlap==true) end
-- LOCK : la défense anticipée se règle sur le point de freinage appris quand la carte des lignes droites ne dit rien
-- (course de 15 h 17 : « candidats 39, dans la bande 0 »), dans les deux sens de virage ; jamais à 60 m du freinage.
tests.LOCK_COVER_BRAKE_POINT_202=function()
 local chance=K.coverChance; K.coverChance=1
 local ok,err=pcall(function()
  for _,turn in ipairs({1,-1}) do
   local s,e=run(turn,15,300)
   assert(covered(s),'turn '..turn..': cover 300 m before the learned braking point')
   assert(s.targetSide==(turn>0 and -1 or 1),'inside side')
   assert(e.coverDiag and e.coverDiag.band>0,'counted in the band')
   assert(not covered((run(turn,15,60))),'60 m before braking: no cover')
  end
 end)
 K.coverChance=chance
 assert(ok,err)
end
-- LOCK : reprise d'une IA accidentée (course de 15 h 17, 90-125 s : Alias repart « piste libre » dans une file arrêtée et
-- touche Jæger puis Vilenius à 0-2 km/h) : une voiture en course à 20 m derrière, ou à hauteur, même à l'arrêt, retient ;
-- une autre voiture accidentée, ou une voiture à 60 m arrêtée, ne retient pas ; réglage coupé : comme la 2.0.2.
tests.LOCK_REJOIN_NEAR_QUEUE_202=function()
 local L=5000
 local function frame(d,kmh)
  local a={valid=true,splineValid=true,spline=0.5,kmh=0,pit=false}
  local b={valid=true,splineValid=true,spline=0.5-d/L,kmh=kmh,pit=false}
  return {length=L,count=2,cars={a,b}}
 end
 local p={rejoinGap=120}
 local t={cars={{incident=true},{incident=false}}}
 for _,wide in ipairs({false,true}) do
  assert(I.trafficTest(frame(20,0),1,p,wide,t),'stopped car 20 m behind holds')
  assert(I.trafficTest(frame(-8,0),1,p,wide,t),'stopped car alongside/ahead 8 m holds')
  assert(not I.trafficTest(frame(60,0),1,p,wide,t),'stopped car 60 m behind: free')
  local t2={cars={{incident=true},{incident=true}}}
  assert(not I.trafficTest(frame(20,0),1,p,wide,t2),'another crashed car does not hold')
 end
 K.rejoinNear=false
 local ok=not I.trafficTest(frame(20,0),1,p,false,t)
 K.rejoinNear=true
 assert(ok,'rule off: 2.0.2 behaviour')
end
-- LOCK : la règle « voiture lente devant » (2.0.2) ne joue jamais contre une IA qui a un tour d'avance (course de 15 h 17 :
-- Vilenius, un tour de retard, redouble Koch puis lui cède sous drapeau bleu, six fois de suite) ; même scène sans tour
-- d'avance : elle joue toujours ; réglage coupé : comme avant.
local function slowScene(lat,lapAhead)
 local e,f=F.scene('C',3); e.startedAt=-100
 local p=e.profiles.C; p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.startDelay=0; p.startRelax=0
 E.changed(e)
 local s=e.states[2]
 for k=1,180 do
  F.place(f,3,2012,130,lat); F.place(f,2,2000,131); F.place(f,1,-4000,100)
  f.cars[2].yawRate=0.005; f.cars[3].yawRate=0.05; f.cars[2].brake=0.4
  f.cars[2].lap=3; f.cars[3].lap=3+lapAhead; f.cars[2].lapValid=true; f.cars[3].lapValid=true
  e.fl.points={(f.cars[2].spline+400/f.length)%1}; e.fl.count=1
  s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=200/3.6 end; s.paceMean=200/3.6
  F.tick(e,f,1/60)
 end
 return e
end
tests.LOCK_SLOW_CAR_NO_UNLAP_202=function()
 for _,lat in ipairs({3.0,-3.0}) do
  assert((slowScene(lat,0).stats.slowCarPass or 0)>=1,lat..': same lap: rule plays')
  assert((slowScene(lat,1).stats.slowCarPass or 0)==0,lat..': car a lap ahead: never')
  K.raceSlowNoUnlap=false; local n=(slowScene(lat,1).stats.slowCarPass or 0); K.raceSlowNoUnlap=true
  assert(n>=1,lat..': guard off: 2.0.2 behaviour')
 end
end
-- Règle 1.64 t1 (à hauteur au premier tour) toujours là sous la nouvelle règle : coupée, une voiture lancée 8 m devant retient
-- encore au premier tour ; hors premier tour, elle ne retient pas (la mutation « 164t1 hauteur ignoree » la vise).
tests.LAP1_ALONGSIDE_NEAR_OFF_202=function()
 local L=5000
 local a={valid=true,splineValid=true,spline=0.5,kmh=0,pit=false}
 local b={valid=true,splineValid=true,spline=0.5+8/L,kmh=40,pit=false}
 local frame={length=L,count=2,cars={a,b}}
 K.rejoinNear=false
 local lap1=I.trafficTest(frame,1,{rejoinGap=120},true,{cars={{incident=true},{incident=false}}})
 local race=I.trafficTest(frame,1,{rejoinGap=120},false,{cars={{incident=true},{incident=false}}})
 K.rejoinNear=true
 assert(lap1==true,'first lap: a car alongside holds')
 assert(race==false,'outside the first lap: not traffic')
end
return tests
