-- Affinage 2.0.1 e (week-end de Monza du pilote au volant, 2.0.0, journal 2026-11-14_18_54_45_monza ; essais t 0-3511 s,
-- qualifications 3511-4471 s ; analyse b201/e/ANALYSE.md) :
--  1. Delon, essais 1222 s : cession au pilote, limite remise à la sortie de la Roggia : 102 -> 84 km/h, le pilote à 11 m
--     qui réaccélère (101 km/h), contact à 13 km/h. Hors course, pendant K.slowLapExitTime s après un virage, suiveur à
--     moins de K.yieldExitGap m derrière : la limite ne descend jamais sous la vitesse du moment ; référence du suiveur
--     jamais prise en virage.
--  2. Mazur, essais 2739 s : tour de rentrée/refroidissement à 81 km/h au lieu de 148 à la sortie d'Ascari, le pilote à 8 m
--     à 125 km/h : baisse de niveau des tours pas lancés rendue en virage et à sa sortie quand une voiture rapide arrive.
--  3. Essais et qualifications : refus « virage ou freinage » dominants : voiture lancée qui rattrape une voiture pas
--     lancée : dépassement en sortie de virage (règle o1 de la course).
--  4. 358 cessions, 73 abouties, 140 « suiveur perdu » : cession ordinaire hors course seulement pour un suiveur qui arrive
--     (contact à K.yieldClosingTTC s au plus) ; suiveur qui ne se rapproche plus oublié, virages compris.
-- Noms LOCK_*_201 (tests/LOCKS.md). Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local Q=require('src/quali')
local K=require('src/config').K
local tests={}
local function withK(values,fn)
 local saved={}; for k,v in pairs(values) do saved[k]=K[k]; K[k]=v end
 local ok,err=pcall(fn)
 for k,v in pairs(saved) do K[k]=v end
 if not ok then error(err,0) end
end
local function learned(e,i,speed) local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=speed end; s.longRatio=1; s.longRatioTime=K.longRatioMin end

-- 1. Cession hors course (essais) : IA 2 à 102 km/h qui cède, suiveur 3 à 11 m derrière à 101 km/h, décalé de lat m ;
-- virage pendant 1 s puis ligne droite. Renvoie la plus basse marge (limite moins vitesse) pendant la sortie (1 à 3 s) et
-- 3,5 s après le virage.
local function yieldExit(lat,side)
 local e,f=F.scene('P',3); local p=e.profiles.P; p.personalLineJitter=0; p.pressureEnabled=false; E.changed(e)
 F.place(f,1,-5000,0); F.place(f,2,0,102); F.place(f,3,-11-4.4,101,lat)
 local s=e.states[2]
 local start=e.time
 local function hold()
  s.state='YIELD_HOLD'; s.target=3; s.targetSide=side; s.followers[3]=true; s.yieldStart=start; s.holdUntil=e.time+60; s.yieldDetection=100; s.yieldMargin=5
  e.states[3].restUntil=e.time+10
  learned(e,2,150/3.6)
 end
 local exitMin,laterMin=math.huge,math.huge
 for k=1,6*60 do
  local t=k/60
  f.cars[2].yawRate=t<1 and e.run.cornerYawRef*0.9 or 0
  F.place(f,2,0,102); F.place(f,3,-11-4.4,101,lat)
  hold(); F.tick(e,f,1/60)
  local margin=(e.commands[2].speedLimit or K.unlimitedSpeed)-f.cars[2].kmh
  if t>1.05 and t<3 then exitMin=math.min(exitMin,margin) end
  if t>4.5 then laterMin=math.min(laterMin,margin) end
 end
 return exitMin,laterMin
end
tests.LOCK_YIELD_CAP_NO_DECEL_201=function()
 for _,v in ipairs({{1.2,1},{-1.2,-1}}) do
  local exitMin,laterMin=yieldExit(v[1],v[2])
  assert(exitMin>=-1e-6,v[1]..': corner exit, follower at 11 m: never under its speed ('..exitMin..')')
  assert(laterMin<-1,v[1]..': later on the straight the yielding AI lifts again ('..laterMin..')')
  local old
  withK({yieldExitNoDecel=false},function() old=yieldExit(v[1],v[2]) end)
  assert(old<-1,v[1]..': 2.0.0 decelerated at the corner exit ('..old..')')
 end
end

-- 2. Rythme des tours pas lancés : Mazur à la sortie d'Ascari (3960 m de 5755 m), 81 km/h ; voiture rapide (le pilote,
-- 125 km/h) 8 m derrière.
local function frame(aKmh,bKmh,gap,corner,push)
 local len=5755
 local a={valid=true,splineValid=true,pit=false,spline=3960/len,kmh=aKmh,speed=aKmh/3.6,corner=corner,control=true,player=false}
 local b={valid=true,splineValid=true,pit=false,spline=(3960-gap)/len,kmh=bKmh,speed=bKmh/3.6,corner=corner,control=false,player=true}
 return {count=2,length=len,cars={a,b}},{push={false,push or false},cars={{},{}}}
end
tests.LOCK_SLOW_LAP_CORNERS_201=function()
 local e={stats={}}
 local f,t=frame(81,125,8,0.3)
 local c=t.cars[1]
 assert(Q.fastBehind(t,f,f.cars[1],1),'fast car 8 m behind')
 local r=0; for k=1,60 do r=Q.relax(t,e,f,f.cars[1],c,1,k/60,1/60) end
 assert(r>=0.999,'corner with a fast car behind: level cut released ('..r..')')
 -- Ligne droite, plus de K.slowLapExitTime s après le virage : la baisse revient (rampe).
 f.cars[1].corner=1
 for k=1,6*60 do r=Q.relax(t,e,f,f.cars[1],c,1,1+k/60,1/60) end
 assert(r<=1e-6,'straight, long after the corner: reduced pace kept ('..r..')')
 -- Pas de voiture rapide derrière (85 km/h, 300 m) : rien n'est rendu.
 local f2,t2=frame(81,85,300,0.3); local c2=t2.cars[1]; local r2=0
 for k=1,60 do r2=Q.relax(t2,e,f2,f2.cars[1],c2,1,k/60,1/60) end
 assert(r2==0,'no fast car behind: nothing released')
 -- Voiture lancée derrière, même à vitesse voisine : rendu aussi.
 local f3,t3=frame(81,90,8,0.3,true); assert(Q.fastBehind(t3,f3,f3.cars[1],1),'flying-lap car behind')
 -- Réglage coupé (2.0.0) : rien n'est rendu.
 withK({slowLapRelax=false},function() local f4,t4=frame(81,125,8,0.3); local x=Q.relax(t4,e,f4,f4.cars[1],t4.cars[1],1,1,1/60); assert(x==0,'2.0.0: nothing released') end)
 -- En scène (qualifications) : refroidissement prévu de l'IA 2 ; voiture 3 à 8 m derrière, +44 km/h ; niveau commandé.
 local function coolScale(yaw)
  local es,fs=F.scene('Q',3); es.profiles.Q.qualiTraffic=true; es.profiles.Q.personalLineJitter=0; E.changed(es); F.tick(es,fs,0.2)
  local scale=1
  for _=1,90 do
   fs.cars[2].yawRate=yaw; F.place(fs,1,-5000,0); F.place(fs,2,0,81); F.place(fs,3,-8-4.4,125)
   local q=es.quali.cars[2]; q.seen=true; q.out=false; q.wasPit=false; q.cool=true; q.planned=true; q.coolLap=fs.cars[2].lap; q.coolAt=es.time-30
   F.tick(es,fs,1/60); scale=es.commands[2].levelScale or 1
  end
  return scale
 end
 local corner,straight=coolScale(1.5),coolScale(0)
 assert(corner>straight+0.1*K.qualiCoolLevel,'scene: cool-down level cut released in the corner ('..corner..' vs '..straight..')')
end

-- 3. Qualifications : attaquant lancé 2 à 10 m d'une voiture pas lancée 3 (refroidissement), +20 km/h, sortie de virage.
local function pqScene(lat)
 local e,f=F.scene('Q',4); local p=e.profiles.Q
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.passAid=false; p.qualiTraffic=true
 E.changed(e); F.tick(e,f,0.2)
 F.place(f,1,-5000,100); F.place(f,4,5000,100)
 local s=e.states[2]
 s.state='OVT_ARM'; s.reason='pass'; s.since=e.time; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=10; s.passName='Cible'
 s.abortSlow=0; s.passStall=0; s.passAlongside=false; s.passProgRef=10; s.passProgTime=0; s.lastPassTarget=3; s.nextPerception=0
 local t=0; local pulled=false; local pushOk=false
 while t<1.6 do
  local yaw=t<0.6 and 1.5 or 0
  f.cars[2].yawRate=yaw; f.cars[3].yawRate=yaw
  F.place(f,2,0,170,0); F.place(f,3,10+4.4,150,lat); s.nextPerception=0
  local q=e.quali.cars
  q[2].seen=true; q[2].out=false; q[2].cool=false; q[2].wasPit=false
  q[3].seen=true; q[3].out=false; q[3].cool=true; q[3].coolLap=f.cars[3].lap; q[3].wasPit=false
  e.fl.points={(f.cars[2].spline+2000/f.length)%1}; e.fl.count=1
  F.tick(e,f,1/60); t=t+1/60
  if e.quali.active and e.quali.push[2] and not e.quali.push[3] then pushOk=true end
  if s.state=='OVT_IN' then pulled=true; break end
 end
 return s,e,pulled,pushOk
end
tests.LOCK_PQ_EXIT_PASS_201=function()
 for _,lat in ipairs({0.8,-0.8}) do
  local s,e,pulled,pushOk=pqScene(lat)
  assert(pushOk,lat..': flying-lap car behind a car that is not pushing')
  assert(pulled and (e.stats.exitPass or 0)>=1,lat..': corner exit: pulls out at once ('..tostring(s.state)..')')
  assert(s.targetSide==(lat>0 and -1 or 1),lat..': side away from the target')
  local e2
  withK({pqExitPass=false},function() local _; _,e2=pqScene(lat) end)
  assert((e2.stats.exitPass or 0)==0,lat..': 2.0.0: no corner-exit pass in qualifying')
 end
end

-- 4. Cession ordinaire hors course (journée circuit) : suiveur 15 m derrière, décalé de lat m, +2,5 km/h (contact à 22 s,
-- cession « proche » de la 2.0.0 sans vrai rapprochement) : plus de cession ; +20 km/h (contact à 2,7 s) : cession.
local function rearYield(lat,sa)
 local e,f=F.scene('J',3); local p=e.profiles.J; p.personalLineJitter=0; p.pressureEnabled=false; p.aiFlashEnabled=false; E.changed(e)
 local yielded=false
 for _=1,4*60 do
  F.place(f,1,-5000,0); F.place(f,2,0,100); F.place(f,3,-15-4.4,100+sa,lat); e.states[2].nextPerception=0
  F.tick(e,f,1/60)
  if F.yielding(e.states[2].state) then yielded=true end
 end
 return yielded,e
end
local function stall(flag)
 local e,f=F.scene('J',3); E.changed(e)
 local s=e.states[2]
 local start=e.time
 local n=0
 withK({yieldStallCorners=flag},function()
  for _=1,2*60 do
   s.state='YIELD_HOLD'; s.target=3; s.targetSide=1; s.followers[3]=true; s.yieldStart=start; s.holdUntil=e.time+60; s.yieldDetection=100; s.yieldOrdinary=true
   f.cars[2].yawRate=e.run.cornerYawRef*0.9
   F.place(f,1,-5000,0); F.place(f,2,0,100); F.place(f,3,-10-4.4,100); s.nextPerception=0
   F.tick(e,f,1/60)
  end
  n=s.followerStall and s.followerStall[3] or 0
 end)
 return n
end
tests.LOCK_YIELD_CLOSING_201=function()
 for _,lat in ipairs({0.8,-0.8}) do
  assert(not rearYield(lat,2.5),lat..': follower not really closing (contact in 22 s): no yield')
  local y0; withK({yieldClosingTTC=false},function() y0=rearYield(lat,2.5) end)
  assert(y0,lat..': 2.0.0 yielded to it')
  assert(rearYield(lat,20),lat..': follower closing (contact in 2.7 s): yield')
 end
 -- Suiveur qui ne se rapproche plus, en virage : compté comme arrêté (oublié), comme en ligne droite.
 assert(stall(true)>0.5,'corner: a follower that no longer closes is counted as stalled')
 assert(stall(false)==0,'2.0.0: never counted in a corner')
end
tests.K_201E=function()
 assert(K.yieldExitNoDecel==true and K.yieldExitGap==40 and K.slowLapRelax==true and K.slowLapBehind==5 and K.slowLapFastKmh==20 and K.slowLapExitTime==2.5)
 assert(K.slowLapRelaxIn==0.5 and K.slowLapRelaxOut==2 and K.pqExitPass==true and K.yieldClosingTTC==4 and K.yieldStallCorners==true)
end
return tests
