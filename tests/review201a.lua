-- Affinage 2.0.1 a (Monza S21-S23, journaux 2026-11-14_13_23_58, 14_23_45, 16_18_47) : vrais dépassements en course 7, 1
-- et 5 (16 en S20) ; déboîtement au dernier moment 2 à 3 par course, jamais à 1 m (écart mini p10 = 4 m, médian 9 m) ;
-- défense anticipée 1 par course. Retour au déboîtement de S12 (choix du pilote du 14 novembre : « si la course est
-- moins bonne, on revient à 3 m ») et défense anticipée pour un suiveur aligné à la même vitesse. Chargé par
-- tests/extended.lua.
local D=require('src/director')
local K=require('src/config').K
local tests={}

-- Attaquant aligné à 4 m (écart mini p10 de S23), rapprochement arrêté (AC garde sa distance) : freinage loin, il reste
-- dans le sillage ; freinage proche, il déboîte à la fronde (en 2.0.0, à 3 m il attendait 1 m, jamais atteint : 0 « gap »).
tests.LOCK_PULLOUT_REACHABLE_201=function()
 assert(K.lastPullEnabled==false,'S12 pull-out in game')
 for _,lat in ipairs({0.3,-0.3}) do
  local function run(gap,sa,np)
   local e={profile='C',fl={points={0.4+np/10000},count=1},time=0}
   local a={splineValid=true,spline=0.4,speed=69,length=4.4}
   local s={seekFront=0,flW=0}
   local f={length=10000,player=1}
   local target={index=3,gap=gap,sa=sa,lat=lat}
   local r
   for k=0,60 do e.time=k/60; r=D.seekLateTest(e,s,a,target,f) end
   return r
  end
  assert(run(4,0,1000)==false,lat..': 4 m in the tow, braking far: stays (sling later)')
  assert(run(4,0,200)==true,lat..': 4 m in the tow, braking close: slingshot pull-out')
  assert(run(K.wakePullGap,0,1000)==true,lat..': 3 m in the tow, braking far: pulls out (2.0.0 waited for 1 m)')
  assert(run(9,0,1000)==false,lat..': 9 m, braking far: stays in the tow (sling later)')
  assert(run(9,0,200)==true,lat..': 9 m, braking close: slingshot pull-out')
 end
end

tests.K_201A=function()
 assert(K.lastPullEnabled==false and K.coverSaMin==0 and K.coverAheadMax==600 and K.coverAheadMin==80 and K.wakeStallGapRace==6) -- 2.0.2 f : bande dès 80 m (tests/review202f.lua)
end

return tests
