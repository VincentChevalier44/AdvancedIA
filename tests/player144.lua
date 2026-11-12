-- Beta 1.44 (essais du 4 novembre, Nordschleife, profil Essais) : le joueur ralentit et se range pour laisser passer
-- une IA, qui reste derrière lui. Reproduit par Engine.step : allure habituelle du joueur apprise (elle reste haute
-- quand il ralentit exprès), paire ignorée après un échec « cible plus rapide » sur le joueur, invitation refusée dans
-- une courbe douce, zone morte sous 30 km/h, courtoisie après un dépassement du joueur. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Merge=require('src/merge')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Allure apprise (m/s) partout pour les voitures first..last (joueur compris).
local function learned(e,first,last,speed)
 for i=first,last do local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=speed end end
end
-- Joueur (1) devant, à kmh, écarté de x m, rotation yaw ; IA (2) derrière à la même vitesse, gap m plus loin ;
-- voiture 3 loin devant. Allures habituelles : 200 km/h pour le joueur et pour l'IA.
local function scene(profile,kmh,x,gap,yaw,playerPace,aiPace)
 local e,f=F.scene(profile,3); e.p.personalLineJitter=0; F.tick(e,f,1/60)
 learned(e,2,2,(aiPace or 200)/3.6); learned(e,1,1,(playerPace or 200)/3.6)
 F.place(f,1,(gap or 20)+4.4,kmh,x or 0); F.place(f,2,0,kmh); F.place(f,3,5000,200)
 f.cars[1].yawRate=yaw or 0; f.cars[2].yawRate=yaw or 0
 local s=e.states[2]; s.nextPerception=0
 return e,f,s
end
-- Premier engagement d'un dépassement de l'IA (s) dans les seconds secondes, sinon nil.
local function engaged(e,f,s,seconds)
 for n=1,math.floor(seconds*60) do F.tick(e,f,1/60,true); if F.passing(s.state) then return n/60 end end
 return nil
end

-- Joueur au centre de la piste, 30 % sous son allure habituelle, IA calée derrière lui à sa vitesse : elle le double
-- (retenue), course comprise comme avant.
tests.PLAYER_SLOW_RETAIN_144=function()
 for _,profile in ipairs({'J','P','Q'}) do
  local e,f,s=scene(profile,140)
  local t=engaged(e,f,s,10)
  assert(t and t<=8,profile..': AI held behind the slow player passes ('..s.state..')')
 end
 local e,f,s=scene('C',140)
 assert(engaged(e,f,s,10),'race: retain pass on a clearly slow player, as before')
end

-- Joueur à son allure habituelle : rien ne change (pas de retenue forcée sur un joueur qui roule normalement).
tests.PLAYER_NORMAL_NO_FORCE_144=function()
 local e,f,s=scene('P',196)
 assert(not engaged(e,f,s,10),'player at his own pace: no forced pass')
end

-- Échec « cible plus rapide » sur le joueur (il est reparti) : jamais de paire ignorée contre lui ; quand il ralentit
-- de nouveau, la retenue reprend aussitôt.
tests.PLAYER_NEVER_IGNORED_144=function()
 local e,f,s=scene('P',140)
 assert(engaged(e,f,s,10),'first pass engaged')
 -- Le joueur repart nettement plus vite : abandon « cible plus rapide ».
 F.place(f,1,f.cars[2].z+12,200,0)
 for _=1,6*60 do F.tick(e,f,1/60,true); if s.state=='DRIVE' or s.state=='OVT_OUT' then break end end
 assert(s.passIgnore~=1,'never a pair ignore against the player')
 for _=1,4*60 do F.tick(e,f,1/60,true) end
 -- Il ralentit de nouveau, l'IA recalée derrière lui.
 F.place(f,1,f.cars[2].z+24.4,140,0); F.place(f,2,f.cars[2].z,140); s.nextPerception=0
 for _=1,2*60 do F.tick(e,f,1/60,true); if not F.passing(s.state) and s.state~='OVT_OUT' then break end end
 local t=engaged(e,f,s,10)
 assert(t,'retain pass again on the slowing player ('..s.state..')')
end

-- Joueur rangé de 3 m dans une courbe douce : invitation suivie hors course ; un écart que la courbure seule explique
-- n'en est pas une.
tests.PLAYER_INVITE_GENTLE_CURVE_144=function()
 for _,profile in ipairs({'J','P'}) do
  local e,f,s=scene(profile,140,3,20,0.06)
  local t=engaged(e,f,s,6)
  assert(t and t<3,profile..': invitation followed in a gentle curve ('..s.state..')')
 end
 -- Beta 1.62 : la journée circuit prend la règle de la course (dépasser en ligne droite) : géométrie hors course jugée en essais.
 local e,f,s=scene('P',100,2.5,20,0.1,100,100)
 assert(not engaged(e,f,s,6),'offset explained by the curvature: not an invitation')
 -- Courbe serrée (plus de K.inviteLatAccel m/s²) : pas d'invitation, raison au journal.
 -- Beta 1.62 : 0,18 rad/s à 100 km/h (5 m/s², au-dessus de K.inviteLatAccel) ; 0,3 rad/s (8 m/s²) est désormais un virage
 -- pour toutes les gardes (src/director.lua, M.cornerness).
 local e3,f3,s3=scene('P',100,6,20,0.18,100,100)
 assert(not engaged(e3,f3,s3,6) and count(e3,'invitation du joueur non suivie: Driver_2')==1 and count(e3,': virage')==1,'tight curve: no invitation, explained')
 -- Course : règle de la ligne droite inchangée.
 local e2,f2,s2=scene('C',140,3,20,0.06,140,140)
 assert(not engaged(e2,f2,s2,6),'race: invitation on straights only, unchanged')
end

-- Joueur au pas (27 km/h, entre l'obstacle et la vitesse minimale de dépassement) : l'IA le double, hors course.
tests.PLAYER_CRAWL_144=function()
 for _,profile in ipairs({'J','P'}) do
  local e,f,s=scene(profile,27,0,8)
  local t=engaged(e,f,s,10)
  assert(t,profile..': AI passes the crawling player ('..s.state..')')
 end
end

-- Joueur qui vient de doubler l'IA puis ralentit nettement : la courtoisie (pas de riposte) ne la retient plus.
tests.PLAYER_PASSED_THEN_SLOWS_144=function()
 local e,f,s=scene('P',140)
 F.tick(e,f,1/60,true); s.passedByPlayerAt=e.time-3
 local t=engaged(e,f,s,10)
 assert(t,'slowing player who just passed: AI passes ('..s.state..')')
end

-- Joueur qui vient de doubler l'IA puis ralentit nettement (au moins K.courtesyPassSa km/h de moins qu'elle) alors que
-- l'allure de l'IA ici est inconnue (pas de « joueur lent » au sens de la Beta 1.44) : la règle de la Beta 1.29 la laisse
-- repasser, comme avant.
tests.PLAYER_PASSED_FAST_RETAKE_144=function()
 local passStates={OVT_ARM=true,OVT_IN=true,OVT_HOLD=true,OVT_OUT=true}
 local e,f=F.scene('P'); e.p.personalLineJitter=0; e.p.flashObliviousPct=0; e.p.pressureEnabled=false; e.p.overtakeDetectAhead=60
 F.place(f,2,0,100); F.place(f,1,-600,100); F.tick(e,f,3)
 local s=e.states[2]
 F.place(f,1,-12,100); s.nextPerception=0; F.tick(e,f,1)
 F.place(f,1,8,70); s.nextPerception=0; F.tick(e,f,0.2)
 s.paceCount=0; for b=1,#s.pace do s.pace[b]=0 end; s.paceRatioCount=0
 local attacked=false; for _=1,10 do F.tick(e,f,0.5); for b=1,#s.pace do s.pace[b]=0 end; s.paceRatioCount=0; attacked=attacked or passStates[s.state] or false end
 assert(attacked,'AI pace unknown, player 30 km/h slower right after passing: the AI may retake')
end

-- Véhicule lent devant le joueur : jamais une voiture à sa hauteur ou juste derrière lui (retenue par lui) ; une
-- voiture lente bien devant, toujours.
tests.SLOW_VEHICLE_NOT_ALONGSIDE_144=function()
 local e,f=F.scene('P',3); e.p.personalLineJitter=0; F.tick(e,f,1/60)
 learned(e,1,3,200/3.6)
 F.place(f,1,1000,60); F.place(f,2,999,60,3); F.place(f,3,6000,200)
 for _=1,8*60 do F.tick(e,f,1/60,true) end
 assert(e.lights.slowSlot~=2,'a car alongside the player, held by him, is not a slow vehicle ahead')
 assert(count(e,'vehicule lent devant le joueur: Driver_2')==0,'no slow-vehicle line for the car alongside')
 F.place(f,3,f.cars[1].z+150,60)
 for _=1,8*60 do F.tick(e,f,1/60,true) end
 assert(e.lights.slowSlot==3 and e.lights.slowGap>100,'a slow car well ahead is still flagged')
end

-- Jonction des stands : jamais d'attente sur une voiture qui vient de quitter la voie des stands devant l'IA (relevé du
-- 4 novembre : « attend … dans 0.0 s, 5 m avant elle », puis « repart apres 0.0 s ») ; une vraie arrivée, toujours.
tests.MERGE_EXITED_CAR_NOT_TRAFFIC_144=function()
 local e,f=F.scene('J',4); e.p.personalLineJitter=0; E.changed(e); f.length=10000
 F.place(f,1,8000,100); F.place(f,2,6000,100); F.place(f,4,9000,0); f.cars[4].pit=true; f.cars[4].inPitBox=true
 local a3=F.place(f,3,1900,60); a3.pit=true
 F.tick(e,f,6); F.place(f,3,2000,60); a3.pit=false; F.tick(e,f,1/60)
 assert(math.abs(e.merge.spline*f.length-2000)<1,'merge point learned')
 -- Voiture 2 dans la voie, sortie juste devant l'IA 4 qui la suit : pas une arrivée.
 local a4=f.cars[4]; a4.inPitBox=false; F.place(f,4,1960,50); F.place(f,2,1900,60); f.cars[2].pit=true; F.tick(e,f,0.2)
 F.place(f,2,2000,60); f.cars[2].pit=false; F.tick(e,f,1/60)
 assert(not e.commands[4].mergeHold,'the car that just left the pit lane is not arriving traffic')
 local exitAt=e.merge.cars[2].exitAt; E.rebase(e,1); assert(e.merge.cars[2].exitAt==exitAt-1,'exit time rebased')
 assert(count(e,'jonction des stands: Driver_4 attend Driver_2')==0,'no zero-length hold logged')
 -- Voiture en piste qui arrive : retenue, comme avant.
 F.place(f,1,1850,200); F.tick(e,f,1/60)
 assert(e.commands[4].mergeHold and count(e,'jonction des stands: Driver_4 attend Driver_1')==1,'real arrival: held and logged')
end

return tests
