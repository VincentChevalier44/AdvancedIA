-- Premier tour 1.63 (Spa du 13 novembre, « prudents mais très rapides, aucun ralentissement ; s'il y a de la place, ils se
-- doublent ») : verrous LOCK_*_163 qui reconstruisent les situations des journaux de Spa, Imola et Suzuka et échouent
-- avec l'ancien comportement (tests/LOCKS.md). Chargé par tests/extended.lua. Scènes latérales avec -1 / -1 et +1 / +1.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local K=C.K
local tests={}

local function scene(sign,count,tune)
 local e,f=F.scene('C',count or 3); e.g.offsetSign=sign; e.g.sideSign=sign
 local p=e.profiles.C; p.personalLineJitter=0
 if tune then tune(p) end
 E.changed(e)
 for i=1,f.count do f.cars[i].sideDot=sign end
 return e,f,p
end
local function firstLap(e,s,f,i) s.flW=1; s.flOn=true; s.flAge=0; s.flLap=f.cars[i].lap or 0; s.flSpread=0; e.fl.on=true end

tests.K_163H4=function()
 assert(K.startWindowMax==10 and K.flGuardTTC==0.8 and K.diveGap==12 and K.diveCorner==0.85 and K.diveSa==5)
 assert(K.raceSlowGap==40 and K.raceSlowSa==12)
 assert(K.firstLapAggr==1 and K.firstLapPassMargin==1 and K.firstLapCorridor==1)
end

-- Spa (2026-11-13 07:34, « phase de depart » 31 refus) : départ de course réglé comme le profil Course (attente 2 s,
-- détente 25 s) ; au plus 14 s après les feux, ligne droite, voiture devant plus lente de 30 km/h, côté libre : l'attaque
-- s'arme (avant : dépassements interdits jusqu'à 27 s).
tests.LOCK_START_PASS_BAN_163=function()
 for _,sign in ipairs({-1,1}) do
  local e,f=scene(sign,3,function(p) p.startDelay=2; p.startRelax=25 end)
  F.place(f,1,-5000,100)
  local function put(dz) F.place(f,2,dz,200,0); F.place(f,3,dz+20,170,0) end
  put(0); f.started=true; F.tick(e,f,0.1); e.launchAt=e.time -- feux éteints maintenant
  local s=e.states[2]; local armed=false; local z=0
  for n=1,60*16 do z=z+200/3.6/60; put(z); s.nextPerception=0; F.tick(e,f,1/60); if F.passing(s.state) then armed=e.time-e.launchAt; break end end
  assert(armed and armed<=14,sign..': attack armed on the straight soon after the launch ('..s.state..', '..tostring(armed)..' s)')
 end
end

-- Spa, La Source (19–26 s : « radar avant: X leve le pied derriere Y (11 m, 33 km/h plus vite) (courbe) » pour presque
-- tout le peloton) : premier tour, en courbe, voiture devant à 12 m, 40 km/h de rapprochement (contact à 1,1 s) : ni
-- levée de pied ni frein du radar, ni prudence ajoutée (avant : levée de pied et prudence d'avertissement).
tests.LOCK_FIRST_CORNER_CONCERTINA_163=function()
 for _,sign in ipairs({-1,1}) do
  local e,f=scene(sign,3)
  F.place(f,1,-5000,100)
  local function put() F.place(f,2,0,160,0); F.place(f,3,12+4.4,120,0); f.cars[2].yawRate=0.2; f.cars[3].yawRate=0.2 end
  local s=e.states[2]
  put(); f.started=true; firstLap(e,s,f,2); F.tick(e,f,0.1)
  local lifted,braked=false,false
  for n=1,40 do put(); firstLap(e,s,f,2); s.nextPerception=0; F.tick(e,f,1/60)
   local c=e.commands[2]; if n>10 then if (c.throttleLimit or 1)<1 then lifted=true end; if (c.brake or 0)>0 then braked=true end end end
  assert(not lifted and not braked,sign..': no app lift or brake in the first corner pack (TTC 1.1 s)')
  assert((s.radarTTC or 99)>K.flGuardTTC,sign..': scene: contact beyond the guard')
 end
end

-- Spa / Imola (« une IA ralentit, celle de derrière ralentit aussi au lieu de déboîter ») : course, ligne droite, voiture
-- devant à 25 m qui ralentit (30 km/h de rapprochement), l'IA d'AC freine pour la suivre, côté libre : l'attaque s'arme
-- (avant : le freinage de suivi refusait tout dépassement).
tests.LOCK_SLOWING_CAR_PASS_163=function()
 for _,sign in ipairs({-1,1}) do
  local e,f=scene(sign,3,function(p) p.startDelay=0; p.startRelax=0 end)
  F.place(f,1,-5000,100)
  f.started=true; F.tick(e,f,40)
  local function put() F.place(f,2,0,190,0); F.place(f,3,25+4.4,160,0); f.cars[2].brake=0.4 end
  local s=e.states[2]; local armed=false
  for _=1,120 do put(); s.nextPerception=0; F.tick(e,f,1/60); if F.passing(s.state) then armed=true; break end end
  assert(armed,sign..': attack armed behind a slowing car while AC brakes to follow ('..s.state..')')
  assert((e.stats.slowOpen or 0)>=1,sign..': counted for the minute summary')
 end
end

-- Suzuka / Spa (aucune attaque au premier virage) : premier tour, freinage avant le braquage, cible à 8 m plus lente de
-- 8 km/h (sous le seuil de la voiture qui ralentit), côté libre : attaque au freinage armée (avant : retenue du premier tour et refus « freinage »).
tests.LOCK_CORNER_DIVE_163=function()
 -- Affinage 1.64 z1 (repris de la 1.63 w2, perdu à une fusion) : attaque au freinage de course (K.diveGapRace) coupée
 -- le temps du test, pour que seule la règle du premier tour (K.diveGap) puisse armer l'attaque.
 local saved=K.diveGapRace; K.diveGapRace=nil
 local ok,err=pcall(function()
 for _,sign in ipairs({-1,1}) do
  local e,f=scene(sign,3)
  F.place(f,1,-5000,100)
  local function put() F.place(f,2,0,170,0); F.place(f,3,8+4.4,162,0); f.cars[2].yawRate=0; f.cars[3].yawRate=0; f.cars[2].brake=0.6; f.cars[3].brake=0.6 end
  put(); f.started=true; F.tick(e,f,40)
  local s=e.states[2]; local armed=false
  for _=1,120 do put(); firstLap(e,s,f,2); s.nextPerception=0; F.tick(e,f,1/60); if s.passGo or s.state=='OVT_IN' then armed=true; break end end
  assert(armed,sign..': late-braking attack launched into the corner on lap 1 ('..s.state..')')
  assert((e.stats.diveOpen or 0)>=1,sign..': counted for the minute summary')
 end
 end)
 K.diveGapRace=saved
 if not ok then error(err,0) end
end
return tests
