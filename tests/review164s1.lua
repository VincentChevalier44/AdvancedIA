-- Affinage 1.64 s1 (Monza S21, 14 novembre). Chargé par tests/extended.lua. Registre : tests/LOCKS.md.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Dangerfile=require('src/dangerfile')
local Delta=require('src/delta')
local K=C.K
local tests={}
-- Fichier gardé de Monza (Documents\Assetto Corsa\AdvancedIA\danger\monza__monza_f1_2026.ini) : zone à 0,163856 du
-- tour (943 m sur 5755 m), niveau 1, vitesse de la flotte 72,9 km/h. Replay S21 : chaque voiture tenue 2 à 3 s à
-- 75-76 km/h après le point le plus lent (~949 m), jusqu'à ~1040 m, puis réaccélération (ex. 76 -> 114 -> 142 km/h).
local function scene(paceKnown)
 local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,0.2)
 f.length=5755
 Dangerfile.loaded(e.danger,{{spline=0.163856,level=1,count=1,sessions=2,quiet=2,kmh=72.9,date='2026-11-14'}},'monza')
 local s=e.states[2]
 if paceKnown then
  for b=1,#s.pace do s.pace[b]=150/3.6 end
  s.paceCount=math.max(K.paceMinBins,#s.pace)
 else
  for b=1,#s.pace do s.pace[b]=0 end
  s.paceCount=0
 end
 return e,f,s
end
local function capAt(meters,kmh,paceKnown)
 local e,f,s=scene(paceKnown)
 local zone=0.163856*5755
 F.place(f,2,zone+meters,kmh); F.tick(e,f,1/60)
 if paceKnown then local b=Delta.bin(f.cars[2].spline,e.delta.bins); s.pace[b]=150/3.6; s.paceCount=math.max(K.paceMinBins,s.paceCount) end
 local cmd=e.commands[2]; cmd.speedLimit=K.unlimitedSpeed; s.dangerCapped=false
 E.dangerCapTest(e,2,s,e.time)
 return s.dangerCapped,cmd.speedLimit
end
tests.LOCK_DANGER_KEPT_EXIT_164=function()
 assert(K.dangerKeptAfter==30,'constant')
 -- Sortie de la chicane, 57 m après la zone (~1000 m), 76 km/h, allure jamais apprise : plus aucun plafond.
 local capped,limit=capAt(57,76,false)
 assert(not capped and limit>=K.unlimitedSpeed,'exit, 57 m past the zone: free to accelerate ('..tostring(limit)..')')
 -- 6 m après la zone (point le plus lent ~949 m), allure inconnue : la vitesse de repli (72,9 km/h) ne s'applique plus.
 capped,limit=capAt(6,60,false)
 assert(not capped,'just past the zone, pace unknown: no fallback cap ('..tostring(limit)..')')
 -- Avant la zone (approche, 100 m avant) : plafond gardé (LOCK_DANGER_KEPT_163), repli 72,9 km/h x 0,96.
 capped,limit=capAt(-100,140,false)
 assert(capped and math.abs(limit-72.9*(1-0.04))<0.5,'approach: capped at the fallback ('..tostring(limit)..')')
 -- Allure connue : plafonnée jusqu'à 30 m après la zone, libre au-delà.
 capped,limit=capAt(20,100,true)
 assert(capped and math.abs(limit-150*0.96)<0.5,'20 m past, pace known: capped at pace -4 % ('..tostring(limit)..')')
 capped,limit=capAt(57,100,true)
 assert(not capped,'57 m past, pace known: free')
end
-- Monza S21 : joueur (Chevalier.V) resté aux stands toute la course (107 m parcourus dans le replay), caméra sur les IA ;
-- tête-à-queue à 2895 m (88,5 s), 5190 m (124 s), 2941 m (180 s)… : zones jaunes ouvertes, aucun panneau allumé (le
-- seul drapeau des panneaux est celui du joueur). Les panneaux suivent la voiture suivie par la caméra.
local Incidents=require('src/incidents')
local Lights=require('src/lights')
tests.LOCK_FOCUS_PANELS_164=function()
 local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,0.5)
 local p=e.run; local t=e.incidents
 f.length=5755
 F.place(f,1,100,0); f.cars[1].pit=true
 -- Zone jaune de l'IA 2 en tête-à-queue à 2895 m ; IA 3 à 200 m avant, à 250 km/h ; IA 4 loin.
 F.place(f,2,2895,0); F.place(f,3,2695,250); F.place(f,4,4500,250)
 t.zoneCount=1; t.zones[1]={slot=2,spline=2895/5755,onTrack=true,at=e.time}
 local function decide(focus)
  f.focus=focus; Incidents.player(t,f,p,e.time)
  local v,r=Lights.decide(e.lights,t,f,p,'C',e.time)
  return t.focusYellow,v,r
 end
 local y,v,r=decide(3)
 assert(y and v==K.flagCaution and r=='drapeau jaune, voiture suivie','followed car approaching the spin: yellow panels ('..tostring(r)..')')
 y,v=decide(4); assert(not y and v~=K.flagCaution,'followed car far from the zone: no yellow')
 y=decide(0); assert(not y,'no focused car: nothing')
 y=decide(2); assert(not y,'the car in the incident itself: nothing')
 -- Joueur en piste : son propre drapeau seulement (jamais celui de la voiture suivie).
 f.cars[1].pit=false; F.place(f,1,100,200)
 y,v=decide(3); assert(not y and not t.playerYellow and v~=K.flagCaution,'player racing: only his own flag')
end
return tests
