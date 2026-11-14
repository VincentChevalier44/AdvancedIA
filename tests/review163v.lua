-- Affinage 1.63, lot 3 (course du Red Bull Ring du 12 novembre au soir) : premier virage (radar au contact, frein dosé
-- en zone de freinage), IA accidentée qui repart sous neutralisation, dépassements sans hésitation en course.
-- Noms terminés par _163V. Chargé par tests/extended.lua. Les scènes latérales tournent avec -1 / -1 et +1 / +1.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local D=require('src/director')
local K=C.K
local tests={}

local function logged(e,text) local n=0; for k=1,e.log.limit do local row=e.log[k]; if row and row.message and row.message:find(text,1,true) then n=n+1 end end return n end

local function scene(profile,sign,count)
 local e,f=F.scene(profile,count or 3); e.g.offsetSign=sign; e.g.sideSign=sign
 local p=e.profiles[profile]; p.startDelay=0; p.startRelax=0; p.personalLineJitter=0
 E.changed(e)
 for i=1,f.count do f.cars[i].sideDot=sign end
 return e,f
end

tests.K_163V=function()
 assert(K.flTouchGap==2.5 and K.flTouchClosing==0.4 and K.flZoneBrakeMax==0.3 and K.flZoneGap==6)
 assert(K.raceConfirmTime==0.2 and K.raceCloseShare==0.5 and K.raceStallGrow==3 and K.raceAttemptMax==30)
 assert(K.passCornerExitC==0.45 and K.passExitGas==0.8 and K.rejoinLastWait==6)
end

-- Premier tour attentif, zone de freinage (virage), pilote qui freine déjà, voiture devant à 4 m qui se rapproche de
-- 15 km/h : frein dosé du radar (au plus K.flZoneBrakeMax), même avec une voiture collée derrière.
tests.FIRSTLAP_ZONE_BRAKE_163V=function()
 for _,sign in ipairs({-1,1}) do
  local e,f=scene('C',sign,4)
  F.place(f,1,-5000,100)
  local function put()
   F.place(f,4,-6,120,0); F.place(f,2,0,120,0); F.place(f,3,4+4.4,105,0)
   for i=2,4 do f.cars[i].yawRate=0.25; f.cars[i].brake=0.6 end
  end
  put(); f.started=true; F.tick(e,f,0.1)
  local s=e.states[2]
  local braked,top=false,0
  for _=1,30 do put(); s.flW=1; s.flOn=true; s.flAge=0; s.flLap=f.cars[2].lap or 0; s.flSpread=0; e.fl.on=true; s.nextPerception=0; F.tick(e,f,1/60); local b=e.commands[2].brake or 0; if b>0 then braked=true end; if b>top then top=b end end
  assert(braked,sign..': radar brakes in the braking zone ('..tostring(s.radarTTC)..')')
  assert((e.commands[2].brake or 0)<=K.flZoneBrakeMax+1e-9,sign..': dosed brake')
  assert(top>K.radarStartBrakeMax+1e-6,sign..': beyond the old first-lap cap (lift only with a car behind) ('..top..')')
 end
end

-- Virage, voiture collée devant (1,5 m) à 1,5 km/h de rapprochement : vue par le radar au premier tour ; hors premier tour,
-- sous K.brakeClosing, comme avant (pas vue).
tests.FIRSTLAP_TOUCH_SEEN_163V=function()
 for _,sign in ipairs({-1,1}) do
  for _,fl in ipairs({true,false}) do
   local e,f=scene('C',sign,3)
   F.place(f,1,-5000,100)
   local function put() F.place(f,2,0,100,0); F.place(f,3,1.5+4.4,98.5,0); f.cars[2].yawRate=0.25; f.cars[3].yawRate=0.25 end
   put(); f.started=true; F.tick(e,f,0.1)
   local s=e.states[2]
   for _=1,20 do put(); if fl then s.flW=1; s.flOn=true; s.flAge=0; s.flLap=f.cars[2].lap or 0; s.flSpread=0; e.fl.on=true else s.flW=0; s.flOn=false end; s.nextPerception=0; F.tick(e,f,1/60) end
   if fl then assert(s.radarIndex==3,sign..': touching car seen on the careful first lap')
   else assert(s.radarIndex~=3,sign..': unchanged outside the first lap') end
  end
 end
end

-- IA accidentée intacte, arrêtée en piste sous VSC : redémarrage demandé (avant : dépannée après 20 s) ; sous
-- drapeau rouge : jamais.
tests.REJOIN_UNDER_NEUTRAL_163V=function()
 for _,mode in ipairs({'neutral','red'}) do
  local e,f=F.scene('C',3); F.place(f,2,-4000,120); F.place(f,3,1000,0); F.tick(e,f,3)
  local t=e.incidents; local c=t.cars[3]
  assert(c.incident,'scene: stopped')
  local seen=false
  for _=1,60 do
   if mode=='neutral' then t.neutral=true else t.red=true; t.redSince=t.redSince or e.time; t.redMax=1e4 end
   F.tick(e,f,1/60)
   if c.rejoining then seen=true end
  end
  if mode=='neutral' then assert(seen,'restart requested under a neutralisation')
  else assert(not seen and logged(e,'redemarrage demande')==0,'never under a red flag (stopped, intact, red held every frame)') end
 end
end

-- Course, attaque à moins d'une seconde : confirmation courte (même scène, K.raceConfirmTime grand = avant).
local function firstAttack(confirm,sign)
 local old=K.raceConfirmTime; K.raceConfirmTime=confirm
 local e,f=scene('C',sign,3)
 F.place(f,1,-5000,100)
 local s=e.states[2]; local at=nil
 for n=1,180 do
  F.place(f,2,0,220,0); F.place(f,3,30+4.4,190,0); s.nextPerception=0
  F.tick(e,f,1/60)
  if not at and s.passStartAt and s.passStartAt>0 and s.state~='DRIVE' then at=n end
 end
 K.raceConfirmTime=old
 return at
end
tests.RACE_EAGER_CONFIRM_163V=function()
 for _,sign in ipairs({-1,1}) do
  local slow=firstAttack(10,sign); local quick=firstAttack(K.raceConfirmTime,sign)
  assert(quick,sign..': attack armed')
  assert(not slow or quick<slow,sign..': armed sooner ('..tostring(quick)..' / '..tostring(slow)..')')
 end
end

-- Course, tentative engagée, cible à la même vitesse, écart constant : plus d'abandon « sans rapprochement » au bout de
-- K.passStallTime s (l'écart n'a pas grandi) ; écart qui grandit de K.raceStallGrow m : abandon comme avant.
tests.RACE_STALL_ONLY_WHEN_GAP_GROWS_163V=function()
 for _,grow in ipairs({false,true}) do
  local e,f=scene('C',-1,3)
  F.place(f,1,-5000,100)
  local s=e.states[2]
  local gap=12
  local function put(g) F.place(f,2,0,200,0); F.place(f,3,g+4.4,200,0) end
  put(gap); F.tick(e,f,0.1)
  s.state='OVT_IN'; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=gap; s.passGap0=gap; s.since=e.time
  local over=false
  for n=1,60*10 do
   local g=grow and gap+math.min(6,n/60) or gap
   put(g); s.nextPerception=0
   if s.state=='OVT_IN' or s.state=='OVT_HOLD' then s.passMinGap=math.min(s.passMinGap or g,gap) end
   F.tick(e,f,1/60)
   if s.passStall>K.passStallTime then over=true end
   -- Mise en position (OVT_HOLD) au bout de 2 s environ : la tentative continue ; on suit au-delà de K.passStallTime.
   if s.state~='OVT_IN' and s.state~='OVT_HOLD' then break end
  end
  if grow then assert(over or (s.state~='OVT_IN' and s.state~='OVT_HOLD'),'gap growing: stall can still end the attempt')
  else
   assert(not over,'equal speed, constant gap: no « sans rapprochement » (passStall '..tostring(s.passStall)..')')
   -- L'abandon « sans rapprochement » remet passStall à zéro dans la même image : le compteur seul ne le voit pas.
   assert(logged(e,'sans rapprochement apres')==0,'equal speed, constant gap: attempt not ended « sans rapprochement »')
  end
 end
end

-- Hungaroring : « ne peut plus rouler » puis « repart » 1 s plus tard. Verdict après le dernier essai plus
-- K.rejoinLastWait s ; une voiture jugée incapable n'est plus dite repartie.
tests.REJOIN_VERDICT_ORDER_163V=function()
 local e,f=F.scene('P',3); F.place(f,2,-4000,120); F.place(f,3,1000,0); F.tick(e,f,3)
 local c=e.incidents.cars[3]; assert(c.incident,'scene: stopped')
 local tries3=nil; local t=0
 while t<K.rejoinMaxTime+5 and not c.cannot do F.tick(e,f,0.5); t=t+0.5; if c.rejoinTries==K.rejoinTries and not tries3 then tries3=e.time end end
 assert(c.cannot and tries3,'verdict reached')
 assert(e.time-tries3>=K.rejoinGap+K.rejoinLastWait-0.6 or e.time-(c.rejoinSince or 0)>=K.rejoinMaxTime-0.6,'last attempt given K.rejoinLastWait s more ('..(e.time-tries3)..')')
 F.place(f,3,1030,40); F.tick(e,f,0.5)
 assert(logged(e,'IA accidentee repart (redemarree')==0,'never « repart » after « ne peut plus rouler »')
end

-- Attaque poussée : une ligne au journal par tentative.
tests.ATTACK_PUSH_LOGGED_163V=function()
 for _,sign in ipairs({-1,1}) do
  local e,f=scene('C',sign,3)
  F.place(f,1,-5000,100)
  local s=e.states[2]
  for _=1,240 do F.place(f,2,0,220,0); F.place(f,3,20+4.4,180,0); s.nextPerception=0; F.tick(e,f,1/60) end
  local n=logged(e,'attaque poussee: ')
  assert(n>=1 and n==(e.stats.attackPush or 0),sign..': one line per push ('..n..' / '..tostring(e.stats.attackPush)..')')
 end
end

return tests
