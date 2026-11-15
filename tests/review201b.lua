-- Affinage 2.0.1 b (week-end de Monza du pilote, journal 2026-11-14_18_54_45_monza, course à t=4471 s ; replay
-- AC_141126-201445) : en tête, le pilote s'écarte (écart latéral de +2 à +8,5 m) et ralentit de 248 à 200 km/h puis à
-- moins de 70 km/h dans la ligne droite des stands ; en 2.0.0, en course, ni la voiture lente (raceSlow) ni le joueur
-- lent (playerSlow, invitation hors ligne droite) ne lançaient le dépassement du joueur : Mazur arrive à +12 km/h, le radar
-- le freine à 1 m derrière lui (« radar avant: Jakub Mazur freine derriere Chevalier.V (1 m, 13 km/h plus vite) »).
-- Course, premier tour compris (hors départ) : joueur nettement plus lent que l'allure libre de l'IA et écarté (ou plus
-- lent de K.raceSlowPlayerSa km/h) : doublé à la première occasion sûre, jamais au freinage. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local K=require('src/config').K
local tests={}

-- IA 2 en ligne droite à aiKmh km/h, freinée par AC à acBrake pour garder l'écart (replay : Mazur 12 m derrière, à la même
-- vitesse que le joueur, de 150 à 110 km/h, pendant 5 s) ; joueur (1) gap m devant, à kmh km/h, décalé de lat m ; point de
-- freinage appris pointM m devant l'IA.
local function scene(lat,gap,kmh,aiKmh,acBrake,pointM)
 local e,f=F.scene('C',3); e.startedAt=-100
 local p=e.profiles.C; p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.startDelay=0; p.startRelax=0
 E.changed(e)
 local s=e.states[2]
 -- Allure libre apprise de l'IA ici : 200 km/h (comme au banc de la 1.62 q).
 s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=200/3.6 end; s.paceMean=200/3.6
 local st={}
 for k=1,180 do
  F.place(f,1,2000+gap,kmh,lat); F.place(f,2,2000,aiKmh); F.place(f,3,-4000,100)
  -- Lacets du journal (4506,7 s) : IA 0,005 rad/s, joueur 0,097 rad/s (il s'écarte) : l'invitation exige les deux en ligne droite.
  f.cars[2].yawRate=0.005; f.cars[1].yawRate=0.097; f.cars[2].brake=acBrake
  e.fl.points={(f.cars[2].spline+pointM/f.length)%1}; e.fl.count=1
  s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=200/3.6 end; s.paceMean=200/3.6
  F.tick(e,f,1/60); st[s.state]=true
 end
 return s,e,st
end
local function passing(st) return st.OVT_OUT or st.OVT_IN or st.OVT_HOLD end
tests.LOCK_PASS_SLOW_PLAYER_201=function()
 for _,lat in ipairs({4.2,-4.2}) do
  -- Joueur 12 m devant, décalé de 4,2 m, à 130 km/h ; IA à sa vitesse (AC la freine à 0,4 pour garder l'écart) ;
  -- point de freinage à 400 m (la chicane).
  local s,e,st=scene(lat,12,130,131,0.4,400)
  assert((e.stats.slowPlayerPass or 0)>=1 and passing(st),lat..': passes the slow player ('..tostring(s.state)..')')
  K.raceSlowPlayer=false; local s2,e2,st2=scene(lat,12,130,131,0.4,400); K.raceSlowPlayer=true
  assert((e2.stats.slowPlayerPass or 0)==0 and not passing(st2),lat..': 2.0.0 stayed behind ('..tostring(s2.state)..')')
  -- Joueur à son allure (pas plus lent que l'allure libre) : la règle ne joue pas.
  local _,e3=scene(lat,12,198,199,0.4,400); assert((e3.stats.slowPlayerPass or 0)==0,lat..': player at pace: no rule')
  -- Point de freinage proche (40 m) : jamais de dépassement lancé au freinage.
  local _,e4,st4=scene(lat,12,130,131,0.4,40); assert(not passing(st4),lat..': no pass into the braking point')
 end
end
tests.K_201B=function() assert(K.raceSlowPlayer==true and K.raceSlowPlayerSa==20) end
return tests
