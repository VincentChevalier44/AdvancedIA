-- Affinage 1.63 (courses du pilote du 13 novembre, journaux 2026-11-13_14_10_15 Nürburgring 41 IA, 12_13_46 Nordschleife,
-- 10_08_20 Sepang, 11_54_00 Imola : 450 tentatives pour 23 réussies au Nürburgring ; 111 fins « cible plus rapide » et
-- 91 « sans rapprochement » à 9-12 m au plus près ; décalage atteint 0,44 sur 0,60 voulu) : attaquants qui déboîtent
-- dès que le rapprochement s'arrête, lentement, et perdent l'aspiration. Noms LOCK_*_163 (tests/LOCKS.md).
-- Chargé par tests/extended.lua. Scènes latérales avec -1 / -1 et +1 / +1.
local F=require('tests/fixture')
local E=require('src/engine')
local D=require('src/director')
local K=require('src/config').K
local tests={}

-- Course, ligne droite : attaquant (voiture 2) qui rattrape sa cible (voiture 3, 250 km/h) à 262 km/h depuis 40 m ;
-- rapprochement arrêté à stopAt m. points : points de freinage connus (FirstLap). each(e,s,t) à chaque image.
local function chase(sign,stopAt,seconds,points,each)
 local e,f=F.scene('C',3); e.g.offsetSign=sign; e.g.sideSign=sign
 local p=e.profiles.C; p.personalLineJitter=0; p.startDelay=0; p.startRelax=0; E.changed(e)
 for i=1,f.count do f.cars[i].sideDot=sign end
 F.place(f,1,-5000,100); f.started=true; F.tick(e,f,40)
 if points then e.fl.points=points; e.fl.count=#points end
 local s=e.states[2]; local z=0; local gap=40
 for k=1,60*seconds do
  local t=k/60; local va=gap>stopAt+0.05 and 262 or 250; z=z+va/3.6/60; gap=gap-(va-250)/3.6/60
  F.place(f,2,z,va,0); F.place(f,3,z+gap+4.4,250,0)
  s.nextPerception=0; F.tick(e,f,1/60)
  if each and each(e,s,t,gap) then break end
 end
 return e,s
end

-- Décalage atteint lentement (0,44 sur 0,60) : en course, hors premier tour, ligne droite et côté libre, l'attaquant
-- arrive en position bien plus vite (avant : 2,2 s entre le déboîtement et la position).
tests.LOCK_ATTACK_OFFSET_163=function()
 for _,sign in ipairs({1,-1}) do
  local inAt,holdAt
  chase(sign,9,12,nil,function(e,s,t) if s.state=='OVT_IN' and not inAt then inAt=t end; if s.state=='OVT_HOLD' and inAt and not holdAt then holdAt=t; return true end end)
  assert(inAt and holdAt,sign..': attack pulled out and reached its position')
  assert(holdAt-inAt<=1.9,sign..': wanted offset reached quickly ('..(holdAt-inAt)..' s)')
  -- Premier tour : rampe d'avant (le premier tour garde ses propres règles).
  local inAt1,holdAt1
  chase(sign,9,12,nil,function(e,s,t) s.flW=1; if s.state=='OVT_IN' and not inAt1 then inAt1=t end; if s.state=='OVT_HOLD' and inAt1 and not holdAt1 then holdAt1=t; return true end end)
  if inAt1 and holdAt1 then assert(holdAt1-inAt1>1.9,sign..': first lap: ramp unchanged ('..(holdAt1-inAt1)..' s)') end
 end
end

-- Rapprochement arrêté à 9 m dans le sillage (AC garde sa distance) : en course, il reste dans le sillage et déboîte
-- à la fronde avant le point de freinage (avant : déboîtement 0,6 s après l'arrêt du rapprochement, aspiration perdue).
tests.LOCK_TOW_SLING_163=function()
 for _,lat in ipairs({0.3,-0.3}) do
  local function run(profile,flW,np,gap)
   local e={profile=profile,fl={points={0.4+np/10000},count=1},time=0}
   local a={splineValid=true,spline=0.4,speed=69,length=4.4}
   local s={seekFront=0,flW=flW}
   local f={length=10000,player=1}
   local target={index=3,gap=gap or 9,sa=0,lat=lat}
   local r
   for k=0,60 do e.time=k/60; r=D.seekLateTest(e,s,a,target,f) end
   return r
  end
  assert(run('C',0,1000)==false,lat..': race, braking point 1000 m ahead: stays in the wake')
  assert(run('C',0,200)==true,lat..': race, braking point close: slingshot pull-out')
  assert(run('C',1,1000)==true,lat..': first lap: as before')
  assert(run('J',0,1500)==true,lat..': not a race: as before (pull-out once closing stops)')
  -- Affinage 1.63 w2 (Monza, session 2) : à 5 m aussi, la fronde attend ; déboîtement immédiat seulement à K.wakePullGap m ou moins.
  assert(run('C',0,1000,5)==false,lat..': 5 m in the wake, braking point 1000 m ahead: stays (sling)')
  -- Décision du pilote 2026-11-14 : 1 m avec garde-fous (K.lastPullEnabled) : à K.wakePullGap m, freinage loin, il reste
  -- dans le sillage ; à K.lastPullGap m il déboîte (fronde et contact proche jouent toujours avant).
  if K.lastPullEnabled then
   assert(run('C',0,1000,K.wakePullGap)==false,lat..': 3 m in the wake, braking far: stays until 1 m')
   assert(run('C',0,1000,K.lastPullGap)==true,lat..': 1 m in the wake: pulls out')
   assert(run('C',0,200,K.wakePullGap)==true,lat..': 3 m, braking point close: slingshot pull-out first')
  else
   assert(run('C',0,1000,K.wakePullGap)==true,lat..': already very close in the wake: pulls out')
  end
  -- Affinage 1.64 z1 : dans une courbe rapide (corner sous K.passCornerC : Curva Grande, Parabolica), la règle du dernier
  -- moment (lot u1) ne joue pas et ce chemin de la fronde reste celui du jeu : il doit garder l'attaquant dans le sillage
  -- loin du freinage (sans attendre l'arrêt du rapprochement) et compter le gain d'aspiration.
  local function runC(np,gap)
   local e={profile='C',fl={points={0.4+np/10000},count=1},time=0}
   local a={splineValid=true,spline=0.4,speed=69,length=4.4,corner=0.5}
   local s={seekFront=0,flW=0}
   local f={length=10000,player=1}
   local target={index=3,gap=gap or 9,sa=0,lat=lat}
   local r
   for k=0,60 do e.time=k/60; r=D.seekLateTest(e,s,a,target,f) end
   return r
  end
  assert(runC(1000)==false,lat..': fast corner, braking point 1000 m ahead: stays in the wake (sling path)')
  assert(runC(1000,5)==false,lat..': fast corner, 5 m in the wake: stays (short sling)')
  assert(runC(200)==true,lat..': fast corner, braking point close: slingshot pull-out')
 end
end

-- Dans le sillage à 9 m : attaque poussée gardée au-delà de K.pushMax s (jusqu'à K.pushMaxRace s), toujours sans
-- déboîter loin du point de freinage (avant : déboîtement à 9 m et attaque poussée finie après 10 s).
tests.LOCK_ATTACK_PUSH_TOW_163=function()
 for _,sign in ipairs({1,-1}) do
  local seen=false
  chase(sign,9,30,{0.999},function(e,s,t)
   if s.pushAt and e.time-s.pushAt>=K.pushMax+4 then
    assert(s.state=='OVT_ARM',sign..': still in the wake ('..s.state..')')
    assert((e.commands[2].level or 0)>=1.02,sign..': attack push kept ('..tostring(e.commands[2].level)..')')
    seen=true; return true
   end
  end)
  assert(seen,sign..': scene reached the long push')
 end
end

tests.K_163W1=function()
 assert(K.attackRampMult>1 and K.slingGainKmh>0 and K.wakeStallGapRace>K.wakePullGap and K.pushMaxRace>K.pushMax and K.pushTowGap<=K.seekRange)
end
return tests
