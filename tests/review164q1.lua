-- Beta 1.64 q1 (Monza, F1, 22 IA, 13 novembre : retour à la référence propre S8 après S9 et S10, où rapprocher les
-- suiveurs au freinage avait multiplié les contacts ; journal 2026-11-13_19_26_03_monza : 93 tentatives, 1 réussie,
-- replay S8 : 100 s de côte à côte pour 8 dépassements en course) : la voiture chevauchée en ligne droite par un
-- attaquant engagé lève légèrement le pied, loin de tout freinage (src/director.lua, overlapYieldOf).
-- Noms LOCK_*_164 (tests/LOCKS.md). Chargé par tests/extended.lua. Scènes latérales avec -1 / -1 et +1 / +1.
local F=require('tests/fixture')
local E=require('src/engine')
local K=require('src/config').K
local tests={}

-- Course : cible (voiture 3) en ligne droite à v km/h ; attaquant (voiture 2) engagé sur elle (OVT_HOLD), à long m
-- (centre à centre, négatif : derrière) et lat m de côté. Rend le moteur, la plus petite limite d'accélérateur vue sur la
-- cible et le premier instant où elle a joué.
local function overlap(sign,o)
 local v=o.v or 300
 local e,f=F.scene('C',3); e.g.offsetSign=sign; e.g.sideSign=sign
 local p=e.profiles.C; p.personalLineJitter=0; p.startDelay=0; p.startRelax=0; E.changed(e)
 for i=1,f.count do f.cars[i].sideDot=sign end
 F.place(f,1,-5000,100); f.started=true; F.tick(e,f,40)
 local saved=K.overlapYieldEnabled; if o.off then K.overlapYieldEnabled=false end
 local s3=e.states[3]; local z=0; local minT,firstAt=1,nil
 for k=1,60*(o.seconds or 2) do
  local t=k/60
  z=z+v/3.6/60
  F.place(f,3,z,v,0); F.place(f,2,z+(o.long or -1.5),v,(o.lat or 2.8)*sign)
  if o.unknownNp then e.fl.points={}; e.fl.count=0
  else e.fl.count=1; e.fl.points={(e.frame.cars[3].spline+(o.np or 1500)/e.frame.length)%1} end
  if o.flW then s3.flW=o.flW end
  local s2=e.states[2]; s2.state=o.state or 'OVT_HOLD'; s2.target=3; s2.since=s2.since or 0
  s3.nextPerception=0; e.states[2].nextPerception=0; F.tick(e,f,1/60)
  local tl=e.commands[3].throttleLimit or 1
  if tl<minT then minT=tl end
  if tl<1 and not firstAt then firstAt=t end
 end
 K.overlapYieldEnabled=saved
 return e,minT,firstAt
end

-- Attaquant engagé à 1,5 m derrière le centre de la cible, 2,8 m de côté, à 300 km/h, freinage à 1500 m : la cible lève
-- légèrement le pied (accélérateur au plus 1-K.overlapYieldThrottle), compté et noté ; règle coupée, premier tour,
-- attaquant pas encore à hauteur (8 m derrière), pas de côté (0,5 m), point de freinage à moins de
-- K.overlapYieldBrakeLead s ou inconnu, attaquant qui n'est pas engagé : jamais.
tests.LOCK_OVERLAP_YIELD_164=function()
 for _,sign in ipairs({1,-1}) do
  local e,minT,at=overlap(sign,{})
  assert(at and minT<=1-K.overlapYieldThrottle+1e-6,sign..': overlapped on the straight: slight lift ('..string.format('%.2f',minT)..')')
  assert(minT>=1-K.overlapYieldThrottle-1e-6,sign..': only a slight lift')
  assert((e.stats.overlapYield or 0)>=1,sign..': counted')
  local logged=false
  for _,l in ipairs(e.log.lines or {}) do if tostring(l):find('chevauchement:',1,true) then logged=true end end
  local _,m0=overlap(sign,{off=true}); assert(m0>=1,sign..': rule off: never')
  local _,m1=overlap(sign,{flW=1}); assert(m1>=1,sign..': never on the first lap')
  local _,m2=overlap(sign,{long=-8}); assert(m2>=1,sign..': attacker not yet alongside: never')
  local _,m3=overlap(sign,{lat=0.5}); assert(m3>=1,sign..': not beside: never')
  local _,m4=overlap(sign,{np=120}); assert(m4>=1,sign..': braking point within the lead: never (corner duel decides)')
  local _,m5=overlap(sign,{unknownNp=true}); assert(m5>=1,sign..': unknown braking point: never')
  local _,m6=overlap(sign,{state='DRIVE'}); assert(m6>=1,sign..': attacker not engaged: never')
 end
end

-- Au plus K.overlapYieldMax s par épisode, puis K.overlapYieldHoldOff s sans.
tests.OVERLAP_YIELD_BOUNDED_164=function()
 for _,sign in ipairs({1,-1}) do
  local released=nil
  local e,f=nil,nil
  local _,minT=overlap(sign,{seconds=K.overlapYieldMax+1.5})
  assert(minT<1,sign..': lift seen')
  local e2=overlap(sign,{seconds=K.overlapYieldMax+1.5})
  assert(e2.commands[3].throttleLimit>=1,sign..': released after '..K.overlapYieldMax..' s')
 end
end

tests.K_164Q1=function()
 assert(K.overlapYieldEnabled==true and K.overlapYieldThrottle>0 and K.overlapYieldThrottle<=0.1 and K.overlapYieldBrakeLead>=2 and K.overlapYieldMax<=3 and K.overlapYieldShare<=0.5)
end

return tests
