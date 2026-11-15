-- Affinage 1.64 u1 (Monza, F1, 22 IA, session 12 du pilote du 13 novembre, journal 2026-11-13_21_44_20_monza : « une
-- voiture derrière une autre se décale trop tôt pour doubler, elle devrait se décaler au dernier moment, à 30 cm de la
-- voiture qui la précède » ; 117 déboîtements, 97 jamais plus près que 4 m, 69 à 7 m ou plus). En course, hors premier
-- tour, derrière une IA, point de freinage connu, en ligne droite : l'attaquant encore à moins de K.lastPullLat m de côté
-- reste dans le sillage ; déboîtement seulement à K.lastPullGap m (1 m, décision du pilote), au point de fronde, ou à moins de
-- K.lastPullTTC s du contact. Noms LOCK_*_164 (tests/LOCKS.md). Chargé par tests/extended.lua.
local D=require('src/director')
local F=require('tests/fixture')
local E=require('src/engine')
local FL=require('src/firstlap')
local K=require('src/config').K
local abs=math.abs
local tests={}

-- Règle seule (seekLate) : attaquant à 250 km/h (69 m/s), cible à gap m, sa km/h de rapprochement, lat m de côté, point
-- de freinage np m devant (nil : inconnu).
local function run(o)
 local e={profile=o.profile or 'C',fl={points={o.np and 0.4+o.np/10000 or nil},count=o.np and 1 or 0},time=0}
 local a={splineValid=true,spline=0.4,speed=69,length=5.3,corner=o.corner or 1}
 local s={seekFront=o.seek or 0,flW=o.flW or 0}
 local f={length=10000,player=o.player or 1}
 local target={index=3,gap=o.gap,sa=o.sa or 0,lat=o.lat,long=o.gap+5}
 local r
 for k=0,60 do e.time=k/60; r=D.seekLateTest(e,s,a,target,f) end
 return r,s
end

-- Voiture de devant à 250 km/h puis qui perd 5 m/s² (levée de pied), attaquant à 2 m.
local function liftRun(sign,lat)
 local e={profile='C',fl={points={0.4+0.1},count=1},time=0}
 local a={splineValid=true,spline=0.4,speed=69,length=5.3,corner=1}
 local s={seekFront=0,flW=0}
 local fc={speed=69.4,brake=0}
 local f={length=10000,player=1,cars={[3]=fc}}
 local target={index=3,gap=2,sa=0,lat=lat,long=7}
 local r
 for k=0,30 do e.time=k/60; if k>15 then fc.speed=fc.speed-5/60 end; r=D.seekLateTest(e,s,a,target,f); if r then return r,s end end
 return r,s
end
tests.LOCK_LAST_MOMENT_PULLOUT_164=function()
 for _,sign in ipairs({1,-1}) do
  local lat=1.5*sign
  -- Cas de la session 12 : 7-14 m derrière, 1,5 m de côté (hors du sillage strict de 1,2 m), freinage à 1000 m : avant,
  -- déboîtement immédiat ; maintenant il reste derrière.
  for _,gap in ipairs({7,10,14}) do
   assert(run({gap=gap,lat=lat,np=1000})==false,sign..', '..gap..' m: stays in the wake far from braking')
  end
  -- Dernier moment (décision du pilote 2026-11-13 : 1 m) : à 3 m et 2 m il reste derrière, à 1 m il déboîte.
  assert(run({gap=3,lat=lat,np=1000})==false and run({gap=2,lat=lat,np=1000})==false,sign..': 3 m and 2 m: still in the wake')
  local r,s=run({gap=1,lat=lat,np=1000}); assert(r==true and s.lastPullWhy=='gap',sign..': pulls out at 1 m')
  r,s=run({gap=0.6,lat=lat,np=1000}); assert(r==true,sign..': 0.6 m: pulls out')
  -- Sécurité : à 2 m, la voiture de devant lève le pied (5 m/s²) : déboîtement aussitôt.
  r,s=liftRun(sign,lat); assert(r==true and s.lastPullWhy=='lift',sign..': car ahead lifts within 3 m: pulls out now')
  -- Fonce sur sa cible (10 m, +50 km/h : contact dans 0,72 s) : déboîtement aussitôt (jamais d'accrochage arrière).
  r,s=run({gap=10,sa=50,lat=lat,np=1000}); assert(r==true and s.lastPullWhy=='ttc',sign..': closing fast: pulls out now')
  -- Point de fronde : 10 m, freinage à 300 m (4,3 s à 250 km/h ; il faut 5,5 s, plus K.seekPullMargin) : déboîtement ;
  -- à 600 m (8,7 s) : encore derrière.
  r,s=run({gap=10,lat=lat,np=300}); assert(r==true and s.lastPullWhy=='sling',sign..': sling point: pulls out')
  assert(run({gap=10,lat=lat,np=600})==false,sign..': before the sling point: still in the wake')
  -- Comme avant : premier tour, hors course, derrière le joueur, point de freinage inconnu, en virage, bien décalé.
  assert(run({gap=10,lat=lat,np=1000,flW=1})==true,sign..': first lap: as before')
  assert(run({gap=10,lat=lat,np=1000,profile='J'})==true,sign..': not a race: as before')
  assert(run({gap=10,lat=lat,np=1000,player=3})==true,sign..': behind the player: as before')
  assert(run({gap=10,lat=lat})==true,sign..': braking point unknown: as before')
  assert(run({gap=10,lat=lat,np=1000,corner=0.3})==true,sign..': in a corner: as before')
  assert(run({gap=10,lat=2.5*sign,np=1000})==true,sign..': already well aside: as before')
 end
end

-- Scène : attaquant décalé de 1,5 m qui rattrape sa cible (250 km/h) à 262 km/h depuis 40 m, rapprochement arrêté à
-- 9 m, freinage 1900 m devant : il reste derrière loin du freinage et déboîte près du point de freinage.
local function chase(sign)
 local e,f=F.scene('C',3); e.g.offsetSign=sign; e.g.sideSign=sign
 local p=e.profiles.C; p.personalLineJitter=0; p.startDelay=0; p.startRelax=0; E.changed(e)
 for i=1,f.count do f.cars[i].sideDot=sign end
 F.place(f,1,-5000,100); f.started=true; F.tick(e,f,40)
 e.fl.count=1
 local s=e.states[2]; local z=0; local gap=40; local pull
 for k=1,60*30 do
  local va=gap>9.05 and 262 or 250; z=z+va/3.6/60; gap=gap-(va-250)/3.6/60
  F.place(f,2,z,va,1.5*sign); F.place(f,3,z+gap+4.4,250,0)
  if k==1 then e.fl.points={(e.frame.cars[2].spline+1900/e.frame.length)%1} end
  s.nextPerception=0; F.tick(e,f,1/60)
  if s.state=='OVT_IN' and not pull then pull={gap=gap,np=FL.nextPoint(e.fl,e.frame.cars[2],e.frame.length)} end
 end
 return pull
end
tests.LAST_MOMENT_SCENE_164U1=function()
 for _,sign in ipairs({1,-1}) do
  local pull=chase(sign)
  if pull then assert(pull.np<=600,sign..': pull-out near the braking point ('..string.format('%.0f',pull.np)..' m)') end
 end
end

-- Abandon d'attaque (Monza S12, 676 s : Grøndal abandonne « côté fermé », revient vers la ligne, Greensmith collé derrière
-- en diagonale le percute à 28 km/h) : décalage tenu tant qu'une voiture est à moins de K.exitRearGap m derrière en
-- diagonale, au plus K.exitHoldMax s ; sinon retour à la ligne comme avant ; hors course : comme avant.
tests.LOCK_ATTACK_EXIT_FOLLOWER_164=function()
 for _,sign in ipairs({1,-1}) do
  local function hold(lat,gap,long,t,profile)
   local e={stats={}}; local s={since=0}
   local row={count=1,neighbors={{long=long or -1,gap=gap,lat=lat*sign}}}
   return D.exitHoldTest(e,s,row,t or 1,profile or 'C')
  end
  assert(hold(3,6)==true,sign..': car 6 m behind, 3 m aside: offset held')
  assert(hold(1.5,10)==true,sign..': car 10 m behind, 1.5 m aside: offset held')
  assert(hold(3,20)==false,sign..': car 20 m behind: back to the line')
  assert(hold(0.2,6)==false,sign..': car straight behind: back to the line')
  assert(hold(6,6)==false,sign..': car far aside: back to the line')
  assert(hold(3,6,1)==false,sign..': car ahead: not a follower')
  assert(hold(3,6,-1,5)==false,sign..': held at most K.exitHoldMax s')
  assert(hold(3,6,-1,1,'J')==false,sign..': not a race: as before')
 end
end

tests.K_164U1=function()
 -- Affinage 2.0.1 a (choix du pilote du 14 novembre, « si la course est moins bonne, on revient à 3 m ») : coupée.
 assert(K.lastPullEnabled==false and K.lastPullLat==2.0 and K.lastPullTTC==0.8 and K.lastPullLogPeriod==15 and K.lastPullGap==1.0 and K.exitRearGap==12 and K.exitHoldMax==4,'constants')
 assert(K.wakePullGap==3 and K.wakeAlignLat==0.3,'lift guard at 3 m, tow alignment 0.3 m (driver decision 2026-11-14)')
end

-- Décision du pilote 2026-11-14 (retour au déboîtement de S12) : la règle du dernier moment est coupée en jeu
-- (K.lastPullEnabled=false) ; ses tests la forcent le temps du test pour que le code reste couvert.
for _,name in ipairs({'LOCK_LAST_MOMENT_PULLOUT_164','LAST_MOMENT_SCENE_164U1'}) do
 local f=tests[name]
 tests[name]=function() local was=K.lastPullEnabled; K.lastPullEnabled=true; local ok,err=pcall(f); K.lastPullEnabled=was; if not ok then error(err,0) end end
end
return tests
