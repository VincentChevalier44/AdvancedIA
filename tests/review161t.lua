-- Beta 1.61 (affinage après les sessions du pilote du 11 novembre : Zandvoort et week-end à Spa). Chargé par
-- tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local D=require('src/director')
local C=require('src/config')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function scene(profile,n,set)
 local e,f=F.scene(profile,n or 3); local p=e.profiles[profile]
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false
 if set then set(p) end
 E.changed(e)
 return e,f
end

-- Essais à Spa : attaquant sans limite de l'app mais prudence 2 à 3,5, collé derrière une cible déjà écartée. Attaquant
-- en dépassement, cible décalée d'au moins K.passFreeLat m : pas de prudence de suivi envers elle (prudence plus basse
-- qu'avec la même cible dans sa trajectoire) ; signes du jeu (−1 / −1).
tests.PASS_FREE_NO_FOLLOW_CAUTION_161T=function()
 local function run(lat,guard)
  -- zone de freinage émulée à 150 % : elle ne doit pas viser une cible décalée non plus
  local e,f=scene('P',3,function(p) p.startDelay=0; p.startRelax=0; p.brakeZonePct=150 end)
  e.g.offsetSign=-1; e.g.sideSign=-1
  F.place(f,1,-5000,100)
  local sum,n=0,0
  for k=1,90 do
   F.place(f,2,0,120); F.place(f,3,10+4.4,100,lat)
   local s=e.states[2]; s.state='OVT_IN'; s.target=3; s.targetSide=lat>0 and 1 or -1; s.nextPerception=0
   if guard then s.pitGuardUntil=e.time+10 end
   F.tick(e,f,1/60)
   if k>60 then sum=sum+e.commands[2].caution; n=n+1 end
  end
  return sum/n,e
 end
 local inLane=run(0.3)
 local aside,e=run(K.passFreeLat+0.8)
 assert(aside<inLane-0.05,string.format('target aside: lower caution than in the lane (%.2f vs %.2f)',aside,inLane))
 assert(aside<=K.passFreeCaution+0.02,string.format('target aside: caution at most K.passFreeCaution (%.2f)',aside))
 assert((e.stats.passFree or 0)>0,'counter')
 -- Relecture 1.62 (S1) : le plafond ne défait pas les règles de sécurité (ici la garde de sortie des stands).
 local guarded=run(K.passFreeLat+0.8,true)
 assert(guarded>=aside*K.pitGuardCaution-0.05,string.format('safety multiplier kept on top of the cap (%.2f vs %.2f)',guarded,aside))
end

-- Courses de Zandvoort et de Spa : départ au freinage, perdu en sortie de virage. En course, l'attaquant en attente ne
-- déboîte que si la ligne droite qui reste laisse le temps d'arriver à hauteur, ou s'il est déjà dans l'aspiration.
tests.PULL_OUT_NEEDS_STRAIGHT_161T=function()
 local e,f=scene('C',3)
 local a=F.place(f,2,0,200)
 a.spline=0.5; a.length=4.4
 e.fl.points={0.5+150/f.length}; e.fl.count=1 -- point de freinage 150 m devant
 local far={gap=20,sa=10}
 assert(not D.pullOutTime(e,a,far,f),'20 m behind, +10 km/h, 150 m of straight: wait')
 e.fl.points={0.5+900/f.length}
 assert(D.pullOutTime(e,a,far,f),'900 m of straight: pull out')
 e.fl.points={0.5+150/f.length}
 assert(D.pullOutTime(e,a,{gap=K.pullOutCloseGap,sa=0},f),'already in the slipstream: pull out')
 e.fl.count=0; e.fl.points={}
 assert(D.pullOutTime(e,a,far,f),'no braking point known: as before')
end

-- Course, cible qui ressort plus vite d'un virage : en course, « cible plus rapide » ne se juge pas en virage (même
-- attente, même écart qui grandit, la tentative tient) ; en ligne droite, elle s'arrête comme avant.
tests.RACE_SLOW_TARGET_JUDGED_ON_STRAIGHT_161T=function()
 local function run(corner)
  local e,f=scene('C',3,function(p) p.startDelay=0; p.startRelax=0 end)
  F.place(f,1,-5000,100)
  local s=e.states[2]
  -- attaque lancée sur un vrai rapprochement
  local t=0
  while t<6 and not F.passing(s.state) do F.place(f,2,0,140); F.place(f,3,18+4.4,110); s.nextPerception=0; F.tick(e,f,1/60); t=t+1/60 end
  assert(F.passing(s.state),'attempt started')
  local aborted=false
  for k=1,60*(K.abortSlowTime+3) do
   local gap=12+k*0.05
   F.place(f,2,0,120); F.place(f,3,gap+4.4,150); local yaw=(1-corner)*e.profiles.C.cornerYawRef; f.cars[2].yawRate=yaw; f.cars[3].yawRate=yaw; s.nextPerception=0
   F.tick(e,f,1/60)
   if not F.passing(s.state) or s.state=='OVT_OUT' then aborted=true; break end
  end
  local why=''
  for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('depassement fini',1,true) then why=r.message end end
  return aborted,e,why..' state='..s.state
 end
 local abortedCorner,_,whyC=run(0.3)
 local abortedStraight=run(1)
 assert(not abortedCorner,'in a corner: no « cible plus rapide » '..whyC)
 assert(abortedStraight,'on a straight: the target pulling away still ends the attempt')
end

-- Spa, course : drapeaux bleus entre IA sur la grille, 13 s avant le départ. En course, aucun tour d'écart avant le
-- départ (comptes de tours de la séance d'avant) ; après le départ, le drapeau bleu revient.
tests.NO_AI_BLUE_FLAG_BEFORE_START_161T=function()
 local e,f=scene('C',3)
 F.place(f,1,-5000,100)
 F.place(f,2,0,100); F.place(f,3,-12-4.4,130)
 f.cars[3].lap=f.cars[2].lap+1
 f.started=false
 for _=1,60*(K.blueLogTime+1) do f.cars[3].lap=f.cars[2].lap+1; e.states[2].nextPerception=0; F.tick(e,f,1/60) end
 assert(count(e,'drapeau bleu IA:')==0 and not F.yielding(e.states[2].state),'no AI blue flag before the start')
 f.started=true
 for _=1,60*(K.blueLogTime+1) do F.place(f,2,0,100); F.place(f,3,-12-4.4,130); f.cars[3].lap=f.cars[2].lap+1; e.states[2].nextPerception=0; F.tick(e,f,1/60) end
 assert(count(e,'drapeau bleu IA:')>0 or F.yielding(e.states[2].state),'after the start: the AI blue flag is back')
end

return tests
