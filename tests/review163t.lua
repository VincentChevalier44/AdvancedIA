-- Affinage 1.63 (sessions F1 du 12 novembre) : sillage, dépassements, premier tour, arrêts pour dégâts.
-- Noms terminés par _163T. Chargé par tests/extended.lua.
local C=require('src/config')
local D=require('src/director')
local K=C.K
local tests={}

-- Attaquant dans le sillage direct de sa cible (sans recherche d'aspiration) : déboîtement au dernier moment
-- (K.wakePullGap m), rapprochement arrêté K.wakeStallTime s, ou ligne droite juste suffisante. Les deux côtés.
tests.WAKE_LATE_PULL_OUT_163T=function()
 assert(K.wakePullGap==3 and K.wakeStallSa==2 and K.wakeStallTime==0.6 and K.wakeStallGap==12)
 for _,lat in ipairs({-0.4,0.4}) do
  local e={fl={points={0.5},count=1},time=0}
  local a={splineValid=true,spline=0.4,speed=60,length=4.4}
  local s={seekFront=0}
  local target={index=3,gap=30,sa=20,lat=lat}
  local f={length=10000}
  assert(D.seekLateTest(e,s,a,target,f)==false,lat..': long straight, in the wake: stays behind')
  target.gap=10; e.time=0.1
  assert(D.seekLateTest(e,s,a,target,f)==false,lat..': 10 m, still closing: stays')
  target.gap=2.5; e.time=0.2
  assert(D.seekLateTest(e,s,a,target,f)==true,lat..': nose at the gearbox: pulls out')
  -- Rapprochement arrêté à 8 m (AC garde sa distance) : déboîtement après K.wakeStallTime s.
  target.gap=8; target.sa=1
  local t=1; e.time=t
  assert(D.seekLateTest(e,s,a,target,f)==false,lat..': stall just started')
  for _=1,5 do t=t+0.1; e.time=t; D.seekLateTest(e,s,a,target,f) end
  e.time=t+0.15
  assert(D.seekLateTest(e,s,a,target,f)==true,lat..': no more closing: pulls out')
  -- Compte repris après une image non jugée : pas de déboîtement d'un coup.
  target.sa=1; e.time=t+5
  assert(D.seekLateTest(e,s,a,target,f)==false,lat..': stall count restarted after a gap')
  -- Hors du sillage (cible écartée) : règle d'avant.
  target.gap=30; target.sa=20; target.lat=lat*6
  assert(D.seekLateTest(e,s,a,target,f)==true,lat..': target aside: as before')
  -- Ligne droite juste suffisante : déboîtement.
  target.lat=lat; e.fl.points[1]=0.4+400/10000
  assert(D.seekLateTest(e,s,a,target,f)==true,lat..': just enough straight left: pulls out')
 end
end

-- Arrêt pour dégâts : une touchette (carrosserie 83–111 relevée à Monaco) n'appelle plus ; premier tour : prudence
-- plafonnée plus bas et plancher relevé.
tests.TUNING_CONSTANTS_163T=function()
 assert(K.damagePitBody==150,'body threshold')
 assert(K.firstLapCautionMax==1.6 and K.firstLapFloorPct==0.7,'first lap caution cap and floor')
end

local F=require('tests/fixture')
local E=require('src/engine')
local P=require('src/perception')
local function signed(e,f,sign) e.g.offsetSign=sign; e.g.sideSign=sign; for i=1,f.count do f.cars[i].sideDot=sign end; E.changed(e) end

-- Évitement à la mesure du chevauchement : voiture arrêtée au bord (aucun chevauchement) : trajectoire tenue ; voiture
-- qui déborde sur la trajectoire : écart vers le côté opposé. Les deux sens latéraux.
tests.AVOID_OVERLAP_163T=function()
 for _,sign in ipairs({-1,1}) do
  local function run(lat)
   local e,f=F.scene('J',3); e.p.personalLineJitter=0; signed(e,f,sign)
   F.place(f,1,-5000,100); F.place(f,2,0,100); F.place(f,3,60,0,lat*sign)
   F.tick(e,f,4)
   return e,e.states[2],P.find(e.perception.rows[2],3)
  end
  local _,s=run(3)
  assert(s.state=='AVOID' and math.abs(s.offset-s.base)<0.05,sign..': stopped car beside the line: line kept ('..s.state..', '..s.offset..')')
  local _,s2,r=run(0.8)
  assert(s2.state=='AVOID' and math.abs(s2.offset-s2.base)>0.05,sign..': car over the line: moves aside ('..s2.offset..')')
  assert(r==nil or s2.offset*(-r.lat)<0,sign..': never towards it')
 end
end

-- Drapeau bleu tenu par l'écart en temps : voiture qui prend un tour à 60 m (1,1 s à 200 km/h), 8 km/h plus lente à
-- cet instant (freinage) : la cession commence (avant : « en attente » sans raison).
tests.BLUE_HELD_BY_TIME_163T=function()
 assert(K.blueHoldTime==1.5 and K.blueHoldSlack==30 and K.blueYieldDeltaKmh==15)
 for _,sign in ipairs({-1,1}) do
  local e,f=F.scene('C',3); e.startedAt=-100; signed(e,f,sign)
  F.place(f,2,0,200); F.place(f,3,5000,200); F.place(f,1,-64.4,192); f.cars[1].lap=f.cars[2].lap+1
  e.states[2].nextPerception=0
  local ok=false
  for _=1,10 do F.tick(e,f,0.5); F.place(f,2,0,200); F.place(f,1,-64.4,192); f.cars[1].lap=f.cars[2].lap+1; if e.states[2].state=='YIELD_IN' or e.states[2].state=='YIELD_HOLD' then ok=true; break end end
  assert(ok,sign..': lapping car 1.1 s behind: blue flag yield ('..e.states[2].state..')')
 end
end

-- Priorité au virage : en course, la voiture qui prend un tour ne cède jamais le virage à l'attardée (c'est elle qui
-- cède) ; entre voitures du même tour, la règle d'avant. Les deux sens latéraux.
tests.CORNER_PRIORITY_LAPPED_163T=function()
 for _,sign in ipairs({-1,1}) do
  local function give(lapped)
   -- Côté de la voisine changé (gauche puis droite) ; repère latéral de la scène gardé (E.changed relance la scène).
   local e,f=F.scene('C',3); e.startedAt=-100; e.p.personalLineJitter=0
   local function put()
    F.place(f,1,-5000,100); F.place(f,2,0,120,0); F.place(f,3,3,120,2.5*sign)
    if lapped then f.cars[2].lap=f.cars[3].lap+1 end
    f.cars[2].yawRate=0.4; f.cars[3].yawRate=0.4; f.cars[2].brake=0.5
   end
   put(); e.states[2].nextPerception=0
   local seen=0
   for _=1,12 do F.tick(e,f,0.1); put(); if e.states[2].cornerGiveTo==3 then seen=seen+1 end end
   return seen>0
  end
  assert(give(false),sign..': same lap, nose behind: gives the corner')
  assert(not give(true),sign..': lapping the other car: keeps its line')
 end
end

return tests
