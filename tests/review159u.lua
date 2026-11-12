-- Beta 1.59 (relecture indépendante de la tranche trafic) : garde-fous de l'exemption du radar, épisode de priorité au
-- virage, référence de la limite de cession. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function learned(e,i,kmh)
 local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=kmh/3.6 end; s.paceMean=kmh/3.6
end

-- Radar : l'exemption « voiture qui s'écarte » ne vaut qu'en ligne droite, pour une voiture qui ne tourne pas, hors
-- incident, avec une vraie vitesse latérale tenue (pas une image de bruit, pas une dérive lente).
tests.RADAR_OPENING_GUARDS_159U=function()
 assert(K.radarOpenRate==0.5 and K.radarLatTau==0.2 and K.radarOpenHold==0.15 and K.nordschleifeMinLength==15000)
 local function run(lateral,hook)
  local e,f=F.scene('J',2); local p=e.profiles.J; p.personalLineJitter=0; p.overtakeEnabled=false; E.changed(e); F.tick(e,f,0.2)
  local z2,z1=0,30; local most=0
  for k=1,150 do
   local t=k/60
   z2=z2+150/3.6/60; z1=z1+110/3.6/60
   F.place(f,2,z2,150); F.place(f,1,z1,110,lateral(t))
   if hook then hook(e,f) end
   F.tick(e,f,1/60); most=math.max(most,e.states[2].radarBrake or 0)
   if z1-z2<6 then break end
  end
  return most
 end
 local moving=function(t) return math.min(3.5,0.3+math.max(0,t-0.8)*4) end
 assert(run(moving)==0,'car really moving aside on a straight: no radar brake')
 assert(run(function(t) return 1.6+t*0.45 end)>0,'slow drift (0.45 m/s, under K.radarOpenRate): the radar brakes')
 local function brakedFrames(lateral) local n=0; run(lateral,function(e) if (e.states[2].radarBrake or 0)>0 then n=n+1 end end); return n end
 local steady=brakedFrames(function() return 0.3 end)
 local noisy=brakedFrames(function(t) return math.floor(t*60+0.5)%15==0 and 1.2 or 0.3 end)
 assert(steady>0 and noisy>=steady,'one frame of lateral noise: the radar does not let go ('..noisy..' of '..steady..')')
 assert(run(moving,function(e,f) f.cars[1].yawRate=0.25 end)>0,'car ahead turning (corner entry, spin): the radar brakes')
 assert(run(moving,function(e,f) f.cars[2].yawRate=e.run.cornerYawRef*0.8 end)>0,'follower in a corner: the radar brakes')
 assert(run(moving,function(e,f) e.incidents.cars[1].incident=true end)>0,'car ahead in an incident: the radar brakes')
end

-- Priorité au virage : le léger freinage d'AC en ligne droite n'ouvre pas d'épisode ; un épisode tient K.cornerPhaseGap s
-- sans virage et n'est compté et journalisé qu'une fois.
tests.CORNER_PHASE_159U=function()
 assert(K.cornerPhaseGap==0.5)
 local function scene(step)
  local e,f=F.scene('J',3); e.profiles.J.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
  F.place(f,1,-5000,0)
  for k=1,120 do
   F.place(f,2,1000-3,120,-1.25); F.place(f,3,1000,120,1.25)
   step(e,f,k)
   e.states[2].nextPerception=0; e.states[3].nextPerception=0
   F.tick(e,f,1/60)
  end
  return e
 end
 -- Ligne droite, freinage léger (sous K.passBrakeMax) côte à côte, nez derrière : aucune priorité en jeu.
 local e=scene(function(e,f) f.cars[2].brake=(K.ruleBrake+K.passBrakeMax)*0.5 end)
 assert((e.stats.cornerGive or 0)==0 and count(e,'priorite au virage')==0,'light gap braking on a straight: no corner priority')
 -- Virage, 0,25 s de ligne droite, virage : un seul épisode.
 e=scene(function(e,f,k) local yaw=(k<=40 or k>55) and e.run.cornerYawRef*0.8 or 0; for i=1,3 do f.cars[i].yawRate=yaw end end)
 assert((e.stats.cornerGive or 0)==1 and count(e,'priorite au virage: Driver_2 cede a Driver_3')==1,'one episode, one line: '..tostring(e.stats.cornerGive))
 -- Vrai freinage en ligne droite (au moins K.passBrakeMax) : épisode ouvert.
 e=scene(function(e,f) f.cars[2].brake=K.passBrakeMax+0.2 end)
 assert((e.stats.cornerGive or 0)==1,'real braking: the rule applies')
end

-- Limite de cession : la référence du suiveur tient pendant toute la cession, virages compris (la limite y est levée) :
-- à la sortie d'un virage, suiveur collé à la même vitesse, la limite ne tombe pas sous la référence moins
-- K.yieldPassDeltaKmh ; remise à zéro à la cession suivante.
tests.YIELD_CAP_REFERENCE_159U=function()
 local e,f=F.scene('J',3); E.changed(e)
 F.place(f,1,-5000,0); F.place(f,2,0,170); F.place(f,3,-14.4,170); learned(e,2,170)
 local s=e.states[2]; local start=e.time-1; local lowest=math.huge
 for k=1,9*60 do
  s.state='YIELD_HOLD'; s.target=3; s.targetSide=1; s.followers[3]=true; s.yieldStart=start; s.holdUntil=e.time+60; s.yieldDetection=100; s.yieldMargin=5
 -- Beta 1.60 (lot 3) : suiveur tenu hors dépassement (sinon passage franc et lever de pied franc : tests/review160w.lua)
  e.states[3].restUntil=e.time+10
  local bend=(k%180)>120
  local cap=e.commands[2].speedLimit or K.unlimitedSpeed
  local v=bend and 120 or math.min(170,cap)
  if not bend and k>180 and (k%180)<=2 then v=120 end
  F.place(f,2,0,v); F.place(f,3,-14.4,v)
  f.cars[2].yawRate=bend and e.run.cornerYawRef*0.8 or 0
  F.tick(e,f,1/60)
  if not bend then lowest=math.min(lowest,e.commands[2].speedLimit or K.unlimitedSpeed) end
 end
 assert(lowest>=170-K.yieldPassDeltaKmh-0.5,'reference kept through the corners: '..lowest)
 assert(s.yieldFollowRef>=170,'reference of the episode: '..tostring(s.yieldFollowRef))
 -- Nouvelle cession : référence repartie de zéro.
 s.yieldStart=e.time; F.place(f,2,0,100); F.place(f,3,-14.4,100); f.cars[2].yawRate=0
 s.state='YIELD_HOLD'; s.followers[3]=true; F.tick(e,f,1/60)
 assert(s.yieldFollowRef<=101,'new yield: reference reset ('..tostring(s.yieldFollowRef)..')')
end

-- Tête-à-queue : horloges de la priorité au virage décalées avec l'horloge du moteur et remises à zéro.
tests.CORNER_TIMERS_159U=function()
 local seen={}
 for _,key in ipairs(C.optionalTimerFields) do seen[key]=true end
 assert(seen.cornerGiveUntil and seen.cornerEntryAt,'corner timers rebased')
 local e,f=F.scene('J',2); F.tick(e,f,0.1)
 local s=e.states[2]; s.cornerGiveUntil=99; s.cornerLift=0.8; s.cornerGiveTo=1; s.passBrakeFree=true; s.yieldQueueFor=2
 require('src/director').reset(s,e.time)
 assert(s.cornerGiveUntil==0 and s.cornerLift==1 and s.cornerGiveTo==0 and s.passBrakeFree==false and s.yieldQueueFor==0,'reset')
end
-- Première journée circuit en 1.59 (10 novembre) : joueur rangé en ligne droite, trois IA en file derrière lui, chacune
-- rattrapée par la suivante : aucune ne renonce (« suiveur rapide »), aucune n'est freinée par le radar, les trois
-- s'engagent ; une voiture de la file déjà passée devant dans le couloir ne le ferme pas.
tests.PLAYER_ASIDE_QUEUE_159U=function()
 local e,f=F.scene('J',4); local p=e.profiles.J; p.personalLineJitter=0; p.aiFlashEnabled=false; E.changed(e); F.tick(e,f,0.2)
 local z={60,35,15,-5}; local v={110,130,160,190}; local engaged={}; local brake=0
 for k=1,11*60 do
  for i=1,4 do z[i]=z[i]+v[i]/3.6/60 end
  -- File gardée : une IA ne traverse pas celle de devant (elle se cale à 12 m, comme l'IA native).
  for i=3,4 do if z[i-1]-z[i]<12 then z[i]=z[i-1]-12 end end
  F.place(f,1,z[1],110,-3.5)
  for i=2,4 do F.place(f,i,z[i],v[i],(e.states[i].offset or 0)*6) end
  F.tick(e,f,1/60)
  for i=2,4 do
   if F.passing(e.states[i].state) and e.states[i].target==1 then engaged[i]=true end
   if i==2 and z[1]-z[i]>4 then brake=math.max(brake,e.states[i].radarBrake or 0) end
  end
 end
 assert(count(e,'suiveur rapide')==0,'no pass given up for the car behind ('..count(e,'suiveur rapide')..')')
 assert(count(e,'cible plus rapide')==0,'no pass given up as target faster')
 assert(brake==0,'no radar braking behind the player aside ('..brake..')')
 for i=2,4 do assert(z[i]>z[1],'car '..i..' is past the player') end
 assert(engaged[2] or engaged[3] or engaged[4] or count(e,'-> Driver_1')==0,'passes on the player engage')
end
-- Deuxième journée circuit en 1.59 : une IA en plein dépassement ne commence pas de cession ordinaire à son suiveur
-- (hors course) ; priorité au virage seulement entre voitures vraiment côte à côte (décalées), jamais pour la voiture
-- juste devant ; le dépassement n'est quitté que pour sa cible.
tests.NO_YIELD_MID_PASS_159U=function()
 local function run(profile,passing)
  local e,f=F.scene(profile,3); local p=e.profiles[profile]; p.personalLineJitter=0; p.aiFlashEnabled=false; E.changed(e); F.tick(e,f,0.2)
  local s=e.states[2]; local yielded=false
  local z1,z2,z3=60,30,10
  for k=1,4*60 do
   z1=z1+120/3.6/60; z2=z2+125/3.6/60; z3=z3+150/3.6/60; if z2-z3<8 then z3=z2-8 end
   F.place(f,1,passing and z1 or z1+3000,120,-3); F.place(f,2,z2,125,0); F.place(f,3,z3,150,0)
   if passing then s.state='OVT_IN'; s.reason='pass'; s.target=1; s.targetSide=1; s.passStartAt=s.passStartAt or e.time; s.passMinGap=10; s.passName='Cible'; s.lastPassTarget=1 end
   s.nextPerception=0
   F.tick(e,f,1/60)
   if s.state=='YIELD_IN' or s.state=='YIELD_HOLD' then yielded=true; break end
  end
  return yielded,e
 end
 local yielded,e=run('J',true)
 assert(not yielded and count(e,'cede a son suiveur')==0,'track day: no ordinary yield in the middle of a pass')
 assert(run('J',false),'track day, not passing: the yield still starts')
end
tests.CORNER_PAIR_REAL_159U=function()
 local function scene(lat2,lat3,ahead,late)
  local e,f=F.scene('J',3); e.profiles.J.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
  F.place(f,1,-5000,0)
  for k=1,(late and 180 or 90) do
   F.place(f,2,1000,120,lat2); F.place(f,3,1000+((late and k<=90) and 30 or ahead),120,lat3)
   for i=1,3 do f.cars[i].yawRate=e.run.cornerYawRef*0.8 end
   e.states[2].nextPerception=0; e.states[3].nextPerception=0
   F.tick(e,f,1/60)
  end
  return e
 end
 local e=scene(0,0,4.6)
 assert((e.stats.cornerGive or 0)==0 and count(e,'priorite au virage')==0,'car just ahead in line, bumper to bumper: not a corner-priority case')
 e=scene(-1.25,1.25,3)
 assert((e.stats.cornerGive or 0)==1,'really side by side, nose behind: gives way')
 e=scene(-1.25,1.25,3,true)
 assert((e.stats.cornerGive or 0)==0,'side by side only in the middle of the corner: no priority (pair not there at the entry)')
end
return tests
