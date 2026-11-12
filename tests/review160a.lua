-- Beta 1.60, tranche A : conscience de l'arrière (réglage rearAwareness), régulateur sans coup de frein (pour tous),
-- aide au dépassement (réglage passAid). Noms terminés par _160A. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local D=require('src/director')
local Rear=require('src/rear')
local Priority=require('src/priority')
local J=require('src/journal')
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
-- Scène du régulateur : IA 2, suiveur 3 collé à gap m ; voiture 1 (joueur) loin.
local function governed(gap,sa)
 local e,f=scene('P',3)
 F.place(f,1,-5000,100); F.rear(e,f,gap or 5,sa or 0,3); F.tick(e,f,0.3)
 return e,f,e.states[2],e.commands[2]
end
local function govern(e,f,dt) Rear.govern(e.rear,e,f,e.time,dt or 1/60) end

tests.K_BLOCK_160A=function()
 assert(K.rearMinSa==5 and K.rearHorizonMin==1 and K.rearHorizonMax==2 and K.rearHold==0.5 and K.rearFastSa==25 and K.rearYieldTtc==6 and K.rearFastRange==250 and K.rearFastConfirm==0.5)
 assert(K.defensePulledLat==2.2 and K.intentCaution==1.1 and K.rearCloseMin==8 and K.rearCloseTime==0.7 and K.rearCloseSa==10)
 assert(K.rearThrottleRate==0.6 and K.rearThrottleFloor==0.7 and K.rearCapDecel==6 and K.rearLevelRate==0.03 and K.rearBrakeMax==0.12 and K.rearLastTtc==0.8 and K.rearCautionRate==0.5)
 assert(K.commitLat==1.5 and K.commitGap==8 and K.holdLineTime==1.5 and K.passAidLevel==0.015 and K.passAidMax==6 and K.passAidPairCooldown==30 and K.passAidSaMax==5 and K.passAidHold==4)
 assert(not C.pendingKeys.rearAwareness and not C.pendingKeys.passAid,'slice A settings are live')
 for _,profile in ipairs({'J','P','Q','C'}) do local d=C.defaults(profile); assert(d.rearAwareness==false and d.passAid==false,'off by default '..profile) end
end

-- Voiture collée derrière : distance en temps, plancher, suiveur qui s'éloigne ; le joueur compte.
tests.REAR_CLOSE_160A=function()
 local e,_,s=governed(5,0)
 assert(s.rearClose==true and s.rearCloseBy==3,'5 m behind at the same speed: close')
 e,_,s=governed(30,0); assert(s.rearClose==false,'30 m at 100 km/h (0.7 s = 19 m): not close')
 e,_,s=governed(15,0); assert(s.rearClose==true,'15 m at 100 km/h: close in time')
 e,_,s=governed(5,-20); assert(s.rearClose==false,'falling away at 20 km/h: not close')
 local f; e,f=scene('P',3); F.place(f,3,-5000,100); F.place(f,2,0,100); F.place(f,1,-9.4,100); e.states[2].nextPerception=0; F.tick(e,f,0.3)
 assert(e.states[2].rearClose==true and e.states[2].rearCloseBy==1,'the player counts as a follower')
end

tests.GOVERN_THROTTLE_160A=function()
 local e,f,s,cmd=governed(5,0)
 assert(s.govThrottle==1,'reference before any slowing')
 cmd.throttleLimit=0.3; govern(e,f)
 assert(math.abs(cmd.throttleLimit-(1-K.rearThrottleRate/60))<1e-9,'ramped: '..cmd.throttleLimit)
 for _=1,120 do cmd.throttleLimit=0.3; govern(e,f) end
 assert(math.abs(cmd.throttleLimit-K.rearThrottleFloor)<1e-9,'never below the floor: '..cmd.throttleLimit)
 assert((e.stats.rearGoverned or 0)==1,'one episode counted')
 cmd.throttleLimit=0.9; govern(e,f); assert(cmd.throttleLimit==0.9,'a lift above the bound is untouched')
end

tests.GOVERN_CAP_160A=function()
 local e,f,s,cmd=governed(5,0)
 cmd.speedLimit=60; govern(e,f)
 assert(math.abs(cmd.speedLimit-(100-K.rearCapDecel/60))<1e-9,'starts from the car speed: '..cmd.speedLimit)
 cmd.speedLimit=60; govern(e,f)
 assert(math.abs(cmd.speedLimit-(100-2*K.rearCapDecel/60))<1e-9,'then from the governed value')
 cmd.speedLimit=K.unlimitedSpeed; govern(e,f); assert(cmd.speedLimit==K.unlimitedSpeed and s.govCap==K.unlimitedSpeed,'release untouched')
end

tests.GOVERN_LEVEL_160A=function()
 local e,f,s,cmd=governed(5,0)
 assert(s.govScale==1)
 cmd.levelScale=0.8; govern(e,f)
 assert(math.abs(cmd.levelScale-(1-K.rearLevelRate/60))<1e-9,'module level factor ramped: '..cmd.levelScale)
 -- Le niveau du directeur n'est jamais relevé (bornes de l'IA) ; le facteur ne dépasse jamais 1.
 local level=cmd.level; cmd.level=level*0.5; cmd.levelScale=1; govern(e,f); assert(cmd.level==level*0.5 and cmd.levelScale==1,'director level untouched, factor never above 1')
 cmd.level=level
 local caution=s.govCaution
 cmd.caution=caution+2; govern(e,f)
 assert(math.abs(cmd.caution-(caution+K.rearCautionRate/60))<1e-9,'caution rise bounded: '..cmd.caution)
 -- Au freinage ou en virage : la prudence remonte librement (protection de la Beta 1.31).
 f.cars[2].brake=0.5; cmd.caution=s.govCaution+2; local asked=cmd.caution; govern(e,f); assert(cmd.caution==asked,'braking: caution untouched')
 f.cars[2].brake=0; f.cars[2].corner=0; cmd.caution=s.govCaution+2; asked=cmd.caution; govern(e,f); assert(cmd.caution==asked,'corner: caution untouched')
end

tests.GOVERN_RADAR_160A=function()
 local e,f,s,cmd=governed(5,0)
 cmd.brake=0.5; s.radarBrake=0.5; s.appBrake=0.5; govern(e,f)
 assert(cmd.brake==K.rearBrakeMax and s.radarBrake==K.rearBrakeMax and s.appBrake==K.rearBrakeMax,'radar brake capped at '..K.rearBrakeMax)
 assert(cmd.throttleLimit<1 and cmd.throttleLimit>=K.rearThrottleFloor,'the lift comes first')
 -- En virage : frein plafonné, jamais de coupure des gaz ajoutée.
 do local e2,f2,s2,c2=governed(5,0); f2.cars[2].corner=0; c2.brake=0.5; s2.radarBrake=0.5; govern(e2,f2); assert(c2.brake==K.rearBrakeMax and c2.throttleLimit==1,'corner: brake capped, no throttle cut') end
 -- Dernier recours : contact devant à moins de K.rearLastTtc s : plein frein du radar.
 local row=e.perception.rows[2]; local n=row.neighbors[row.count+1]
 n.index=1; n.long=6; n.lat=0; n.gap=1.6; n.sa=60; n.ttc=0.1; n.same=true; row.count=row.count+1; row.front=row.count
 cmd.brake=0.5; cmd.throttleLimit=0.3; govern(e,f)
 assert(cmd.brake==0.5 and cmd.throttleLimit==0.3,'obstacle under the last-resort time: full brake')
end

tests.GOVERN_EXEMPT_160A=function()
 local function untouched(set,why)
  local e,f,s,cmd=governed(5,0); set(e,f,s,cmd)
  cmd.throttleLimit=0.3; cmd.brake=0.5; cmd.speedLimit=40; govern(e,f)
  assert(cmd.throttleLimit==0.3 and cmd.brake==0.5 and cmd.speedLimit==40,why)
 end
 untouched(function(_,_,s) s.yellow=true end,'yellow flag')
 untouched(function(e) e.incidents.neutral=true end,'neutralisation')
 untouched(function(e) e.incidents.red=true end,'red flag')
 untouched(function(_,_,s) s.state='AVOID' end,'avoidance')
 untouched(function(_,_,s) s.state='CALM' end,'calm recovery')
 untouched(function(_,f) f.cars[2].pit=true end,'pit lane')
 untouched(function(_,_,_,cmd) cmd.stopHold=true end,'grid hold')
 untouched(function(_,_,_,cmd) cmd.rulePit=true end,'pit call')
 untouched(function(_,_,_,cmd) cmd.scSpeed=80 end,'Safety Car speed')
 untouched(function(e) e.incidents.cars[2].incident=true end,'car in an incident')
 untouched(function(_,_,s) s.flW=1 end,'careful first lap has its own rules')
 untouched(function(_,_,s) s.disqualified=true end,'disqualified')
 untouched(function(e) e.sanctions.cars[2].cutLimit=0.5 end,'AI penalty being served (throttle cut)')
end

-- Sans voiture collée : commandes laissées telles quelles (références suivies seulement).
tests.GOVERN_NO_FOLLOWER_160A=function()
 local e,f,s,cmd=governed(60,0)
 assert(s.rearClose==false)
 cmd.throttleLimit=0.3; cmd.brake=0.5; cmd.speedLimit=40; cmd.levelScale=0.7; cmd.caution=5; govern(e,f)
 assert(cmd.throttleLimit==0.3 and cmd.brake==0.5 and cmd.speedLimit==40 and cmd.levelScale==0.7 and cmd.caution==5,'identical to 1.59')
 assert(s.govThrottle==0.3 and s.govCap==40 and (e.stats.rearGoverned or 0)==0,'references follow, nothing counted')
end

-- Aucune inattention ne commence avec une voiture collée derrière ; elle commence dès qu'elle est partie.
tests.LAPSE_NOT_STARTED_REAR_160A=function()
 local function run(gap)
  local e,f=scene('P',3,function(p) p.lapseEnabled=true end)
  F.place(f,1,-5000,100); F.rear(e,f,gap,0,3); F.tick(e,f,0.3)
  local s=e.states[2]; s.lapseAt=e.time; s.lapseUntil=0
  F.tick(e,f,0.2)
  return s.lapseUntil>e.time
 end
 assert(not run(5),'close follower: no lapse starts')
 assert(run(80),'nobody behind: the lapse starts')
end

-- Côté prévu : voiture 22 m derrière, +60 km/h (1,3 s), 3 m à gauche : au-delà de l'occupation ordinaire (6 m + 0,8 s),
-- dans l'horizon du pilote le plus attentif : côté gauche fermé ; droite libre.
local function sideScene(on,gap,sa,x)
 local e,f=scene('P',3,function(p) p.rearAwareness=on end)
 F.place(f,1,-5000,100); F.place(f,2,0,100); F.place(f,3,-5000+50,100)
 F.tick(e,f,0.2)
 e.states[2].persona.awareness=e.run.awMin
 F.place(f,3,-(gap or 22)-4.4,100+(sa or 60),x or -3); F.tick(e,f,0.1)
 F.place(f,3,-(gap or 22)-4.4,100+(sa or 60),x or -3); e.states[2].nextPerception=0; F.tick(e,f,1/60)
 return e,f
end
tests.REAR_SIDE_PREDICTED_160A=function()
 local e,f=sideScene(true); local s=e.states[2]
 -- Fixture : x négatif = lat positif = gauche (perception : lat=-dx*lz+dz*lx).
 local row=e.perception.rows[2]
 assert(Rear.side(s,-1,e.time) and not Rear.side(s,1,e.time),'left predicted, right free')
 assert(row.left and not row.right,'ORed into the occupancy')
 -- Retour à la ligne vers la gauche retenu ; mouvement vers la droite permis.
 s.offset=0.3; s.filtered=0.3; local held=D.lateral(s,0,row,f.cars[2],e.run,e.runtimeG,1/60,e.time)
 assert(held==0.3,'move towards the predicted side held: '..held)
 s.offset=-0.3; s.filtered=-0.3; s.blocked=0; local moved=D.lateral(s,0,row,f.cars[2],e.run,e.runtimeG,1/60,e.time)
 assert(moved>-0.3,'move away allowed: '..moved)
 -- Pilote le moins attentif : horizon de 1 s, voiture à 1,3 s : rien.
 e=sideScene(true); assert(Rear.horizon(e.states[2],e.run)==K.rearHorizonMax)
 -- Trop loin dans le temps : rien.
 e=sideScene(true,60,40); assert(not Rear.side(e.states[2],-1,e.time),'5 s away: not predicted')
 -- Droit derrière : rien (la cession s'en occupe).
 e=sideScene(true,22,60,0); assert(not Rear.side(e.states[2],-1,e.time) and not Rear.side(e.states[2],1,e.time),'straight behind: no side')
 -- Voiture qui ne se rapproche pas assez : rien.
 e=sideScene(true,0.5,3); assert(not Rear.side(e.states[2],-1,e.time),'closing under K.rearMinSa (0.6 s away): not predicted')
end
tests.REAR_SIDE_OFF_160A=function()
 local e=sideScene(false)
 local row=e.perception.rows[2]
 assert(not row.left and not row.right and e.states[2].rearLeftUntil==nil,'switch off: plain occupancy')
end
tests.REAR_SIDE_HOLD_BOUNDED_160A=function()
 local s={rearLeftUntil=10.4}
 assert(Rear.side(s,-1,10) and not Rear.side(s,-1,10.5) and not Rear.side(s,1,10),'held K.rearHold s')
 s.rearLeftUntil=5000; assert(not Rear.side(s,-1,10),'a clock rebase cannot extend the hold')
 local p={awMin=0.2,awMax=0.6}
 assert(Rear.horizon({persona={awareness=0.2}},p)==K.rearHorizonMax and Rear.horizon({persona={awareness=0.6}},p)==K.rearHorizonMin,'horizon from awareness')
end

-- Cession anticipée (hors course) : voiture beaucoup plus rapide vue au-delà de la détection ordinaire.
local function yieldScene(profile,on,gap,sa)
 local e,f=scene(profile,3,function(p) p.rearAwareness=on; p.flashObliviousPct=0 end)
 F.place(f,1,-5000,100); F.rear(e,f,gap,sa,3)
 return e,f
end
tests.REAR_YIELD_EARLY_160A=function()
 local function run(on)
  local e,f=yieldScene('J',on,120,90); F.tick(e,f,0.1)
  for i=2,3 do e.states[i].persona.reaction=0.2; e.states[i].persona.awareness=0 end
  local t=0
  while t<6 do F.place(f,3,-120-4.4,190); e.states[2].nextPerception=0; F.tick(e,f,1/60); t=t+1/60; if F.yielding(e.states[2].state) then return t,e end end
  return math.huge,e
 end
 local on,e=run(true)
 assert(on<6 and count(e,'cession anticipee:')==1 and (e.stats.rearYield or 0)==1,'early yield, logged once')
 assert(J.english('cession anticipee: A -> B (120 m, +90 km/h)')=='early yield: A -> B (120 m, +90 km/h)',J.english('cession anticipee: A -> B (120 m, +90 km/h)'))
 local off,o=run(false)
 assert(count(o,'cession anticipee:')==0,'switch off: no early yield line')
 -- Confirmation réduite (K.rearFastConfirm) : la cession commence plus tôt qu'en 1.59.
 assert(on<off-(1-K.rearFastConfirm)*e.run.confirmTime+0.05,'confirmed faster: '..on..' s against '..off..' s')
 -- En course : jamais.
 local r,f=yieldScene('C',true,120,90); F.tick(r,f,1)
 assert(not F.yielding(r.states[2].state) and count(r,'cession anticipee:')==0,'race: unchanged')
end
tests.REAR_YIELD_TOO_LATE_160A=function()
 local function run(on)
  local e,f=yieldScene('J',on,12,60)
  local t=0
  while t<3 do F.place(f,3,-12-4.4,160); e.states[2].nextPerception=0; F.tick(e,f,1/60); t=t+1/60; if F.yielding(e.states[2].state) then return true end end
  return false
 end
 assert(run(false),'1.59: yields to the car 12 m behind at +60 km/h')
 assert(not run(true),'rear awareness: alongside within the horizon, no yield starts')
end

-- Défense en un seul mouvement, tôt : jamais contre un attaquant déjà décalé, trop près ou en dépassement.
tests.DEFENCE_EARLY_ONLY_160A=function()
 local function run(on,gap,sa,x,attacking)
  local e,f=scene('C',3,function(p) p.rearAwareness=on; p.defenseEnabled=true; p.defenseTriggerGap=40; p.startDelay=0; p.startRelax=0 end)
  K.defenseChance=1
  F.place(f,1,-5000,100); F.place(f,2,0,100); F.place(f,3,-gap-4.4,100+sa,x)
  local s=e.states[2]; s.nextPerception=0; f.cars[2].lap=3; f.cars[3].lap=3; s.persona.awareness=e.run.awMin
  local t=0
  while t<0.5 do
   if attacking then e.states[3].state='OVT_IN'; e.states[3].target=2; e.states[3].targetSide=-1 end
   F.place(f,3,-gap-4.4,100+sa,x); s.nextPerception=0; s.persona.awareness=e.run.awMin; F.tick(e,f,1/60); t=t+1/60
   if s.state=='DEFEND' then break end
  end
  return s.state=='DEFEND',e
 end
 local chance=K.defenseChance
 local ok,err=pcall(function()
  assert((run(false,25,10,-1.2)),'1.59: defence against a follower 1.2 m aside')
  assert((run(true,25,10,-1.2)),'early attacker (9 s to alongside, 1.2 m aside): one defence')
  local seen,e=run(true,25,10,-2.5)
  assert(not seen and count(e,'defense non lancee:')==1,'attacker already 2.5 m aside: no defence, one line')
  assert(J.english('defense non lancee: A, B deja decale ou trop pres')=='defence not started: A, B already pulled out or too close')
  assert((run(false,10.6,19.5,-1.2)),'1.59: defence against a follower 1.96 s from alongside')
  local near,ne=run(true,10.6,19.5,-1.2)
  assert(not near and count(ne,'defense non lancee:')==1,'alongside within the horizon (1.96 s, horizon 2 s): no defence, one line')
  assert(not run(true,25,10,-1.2,true),'AI attacker already pulling out: no defence')
  assert((run(false,25,10,-2.5)),'switch off: 1.59 behaviour')
 end)
 K.defenseChance=chance
 assert(ok,err)
end

-- Aide au dépassement : scène de l'attaquant 2 décalé à droite de la cible 3, en ligne droite.
local function passScene(profile,on,gap,x,targetKmh)
 local e,f=scene(profile,4,function(p) p.passAid=on; p.startDelay=0; p.startRelax=0 end)
 F.tick(e,f,0.2)
 F.place(f,1,-5000,100); F.place(f,4,5000,100); F.place(f,2,0,105,x or 2); F.place(f,3,gap+4.4,targetKmh or 100)
 local s=e.states[2]
 s.state='OVT_IN'; s.reason='pass'; s.since=e.time; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=gap; s.passName='Cible'
 s.abortSlow=0; s.passStall=0; s.passAlongside=false; s.passProgRef=gap; s.passProgTime=0; s.lastPassTarget=3; s.nextPerception=0
 s.offset=0.4; s.filtered=0.4
 return e,f,s,e.states[3]
end
tests.COMMIT_GEOMETRY_160A=function()
 local e,f,s,o=passScene('C',true,5,2); F.tick(e,f,1/60)
 assert(s.committed==3 and s.commitSide==1 and Priority.held(o,e.time)==2,'2 m aside, 5 m behind: committed, target holds')
 assert(count(e,'aide au depassement: Driver_2 engage sur Driver_3 (cote droit, 5 m), Driver_3 tient sa ligne')==1,'one line')
 assert(J.english('aide au depassement: A engage sur B (cote droit, 5 m), B tient sa ligne')=='passing aid: A committed on B (right side, 5 m), B holds its line',J.english('aide au depassement: A engage sur B (cote droit, 5 m), B tient sa ligne'))
 F.tick(e,f,0.2); assert(count(e,'aide au depassement:')==1 and (e.stats.passCommit or 0)==1,'once per attempt')
 e,f,s=passScene('C',true,5,1); F.tick(e,f,1/60); assert((s.committed or 0)==0,'1 m aside: not committed')
 e,f,s=passScene('C',true,20,2); F.tick(e,f,1/60); assert((s.committed or 0)==0,'20 m behind: not committed')
 e,f,s=passScene('C',true,5,2); f.cars[2].yawRate=1; F.tick(e,f,1/60); assert((s.committed or 0)==0,'in a corner: not committed')
 e,f,s=passScene('C',true,5,2); F.place(f,4,12,100,4); F.tick(e,f,1/60); assert((s.committed or 0)==0,'corridor closed by a third car: not committed')
end
tests.PASS_AID_OFF_IDENTICAL_160A=function()
 local e,f,s,o=passScene('C',false,5,2); F.tick(e,f,0.5)
 assert((s.committed or 0)==0 and (o.heldBy or 0)==0 and count(e,'aide au depassement')==0 and (e.stats.passCommit or 0)==0,'switch off: nothing')
end
tests.DEFENDER_HOLDS_LINE_160A=function()
 -- Attaquant à 7,9 m du pare-chocs, +5 km/h : hors de l'occupation ordinaire (6 m + 0,8 s), dans l'engagement (8 m).
 local e,f,s,o=passScene('C',true,7.9,2)
 do local plain={left=false,right=false}; require('src/perception').occupancy(f.cars,f.count,3,e.runtimeG,plain); assert(not plain.right,'plain occupancy leaves the side open') end
 o.state='DEFEND'; o.reason='attacker'; o.targetSide=1; o.defendUntil=e.time+10; o.towing=false
 F.tick(e,f,1/60); F.tick(e,f,1/60)
 assert(o.state=='DRIVE' and o.reason=='held_line','a running defence ends: '..o.state..' '..tostring(o.reason))
 local row=e.perception.rows[3]
 assert(row.right,'the attacker side (right of the target) is closed')
 local cmd=e.commands[3]
 assert(cmd.brake==0 and cmd.throttleLimit==1 and cmd.speedLimit==K.unlimitedSpeed,'never a lift, never a brake')
 assert((e.stats.lineHeld or 0)==1,'counted once')
 -- Mouvement vers l'attaquant retenu, s'écarter permis.
 o.offset=0; o.filtered=0; assert(D.lateral(o,0.5,row,f.cars[3],e.run,e.runtimeG,1/60,e.time)==0,'no move towards the attacker')
 o.blocked=0; o.state='YIELD_IN'; o.yieldBlue=true; assert(D.lateral(o,-0.5,row,f.cars[3],e.run,e.runtimeG,1/60,e.time)<0,'moving away allowed')
 o.state='DRIVE'; o.yieldBlue=false
 -- Fin de la tentative : ligne libérée.
 s.state='DRIVE'; s.target=0; F.tick(e,f,1/60)
 assert((s.committed or 0)==0 and Priority.held(o,e.time)==0,'released with the attempt')
end
tests.ATTACKER_BONUS_BOUNDED_160A=function()
 local function level(on,target,seconds)
  local e,f,s=passScene('C',on,5,2)
  if target==1 then F.place(f,1,5+4.4,100); F.place(f,3,5000,100); s.target=1 end
  local t=0
  while t<seconds do F.place(f,2,0,105,2); s.nextPerception=0; if s.state~='OVT_IN' and s.state~='OVT_HOLD' then break end; F.tick(e,f,1/60); t=t+1/60 end
  return e.commands[2].level,s,e
 end
 local off=level(false,3,1.5); local on,s=level(true,3,1.5)
 assert(s.aidBonus==true and on>off and on<=off*(1+K.passAidLevel)+1e-9,'bonus of at most 1.5 %: '..on..' vs '..off)
 local player=level(true,1,1.5); local playerOff=level(false,1,1.5)
 assert(math.abs(player-playerOff)<1e-12,'never against the player')
 -- Durée bornée puis attente par paire.
 local _,s2=level(true,3,0.1)
 assert(s2.aidPair==3 and s2.aidPairUntil>0,'pair cooldown armed')
 local e,f,s3=passScene('C',true,5,2); s3.aidPair=3; s3.aidPairUntil=e.time+20; F.tick(e,f,1/60)
 assert(s3.committed==3 and s3.aidBonus==false,'same pair within the cooldown: committed, no bonus')
 e,f,s3=passScene('C',true,5,2); F.tick(e,f,1/60); s3.commitAt=e.time-K.passAidMax-1
 local before=e.commands[2].level; s3.aidPairUntil=0; F.tick(e,f,1/60)
 assert(s3.aidPairUntil==0 and e.commands[2].level<=before+1e-12,'after K.passAidMax s: no more bonus')
end
tests.PASS_AID_NO_ABORT_SLOW_160A=function()
 local function run(on)
  local e,f,s=passScene('C',on,12,2,107)
  local t=0
  while t<K.abortSlowTime+6 do
   F.place(f,2,0,105,2); F.place(f,3,12+4.4,107); s.nextPerception=0
   if on and (s.committed or 0)==0 then Priority.commit(e,2,3,1,e.time) end
   F.tick(e,f,1/60); t=t+1/60
   if not F.passing(s.state) or s.state=='OVT_OUT' then break end
  end
  return s.reason,t
 end
 -- Affinage 1.61 : la course demande un écart en temps plus grand (K.abortTgGrowRace) ; ce test garde l'objet du lot 1.60a
 -- (la minuterie attend tant que l'aide tient), avec l'ancien seuil.
 local savedTg=K.abortTgGrowRace; K.abortTgGrowRace=K.abortTgGrow
 local why,tOff=run(false); assert(why=='abort_slow','1.59: target faster ends the attempt ('..tostring(why)..')')
 local reason,t=run(true)
 print(string.format('1.60a pass aid: abort_slow at %.2f s without the aid, %s at %.2f s with it',tOff,tostring(reason),t))
 K.abortTgGrowRace=savedTg
 assert(reason~='abort_slow' or t>K.passAidHold,'committed: the target-faster timer waits (at most K.passAidHold s), got '..tostring(reason)..' at '..t)
 -- Relecture finale 1.61 : le délai gagné est réel (le minuteur ne compte pas pendant l'engagement).
 assert(reason~='abort_slow' or t>=tOff+1.5,'committed: the attempt lasts clearly longer than without the aid ('..tOff..' -> '..t..')')
end
tests.PASS_AID_CORNER_PRIORITY_WINS_160A=function()
 local e,f,s,o=passScene('C',true,5,2); F.tick(e,f,1/60)
 assert(s.committed==3)
 -- Au virage : plus de ligne tenue rafraîchie ni de gain ; la priorité au virage de la 1.59 décide.
 f.cars[2].yawRate=1; f.cars[3].yawRate=1
 local level=e.commands[2].level
 F.tick(e,f,K.holdLineTime+0.2)
 assert(Priority.held(o,e.time)==0,'hold not refreshed in the corner')
 assert(e.commands[2].level<=level+1e-9,'no bonus in the corner')
end
tests.PLAYER_ATTACKER_HELD_LINE_160A=function()
 local function run(on)
  local e,f=scene('C',3,function(p) p.passAid=on; p.startDelay=0; p.startRelax=0 end)
  F.place(f,3,5000,100); F.place(f,2,0,100); F.place(f,1,-4-4.4,110,-2)
  F.tick(e,f,0.2); F.place(f,1,-4-4.4,110,-2); e.states[2].nextPerception=0; F.tick(e,f,1/60); F.tick(e,f,1/60)
  return e,f
 end
 local e,f=run(true); local s=e.states[2]; local row=e.perception.rows[2]
 assert(Priority.held(s,e.time)==1 and e.states[1].commitSide==-1,'player 2 m to the left, 4 m behind, closing: the AI holds its line')
 assert(row.left,'no move towards the player')
 assert(count(e,'aide au depassement: Driver_1 engage sur Driver_2 (cote gauche, 4 m), Driver_2 tient sa ligne')==1,'one line')
 assert(e.commands[1].active==false,'nothing written to the player car')
 -- Joueur reparti : libéré.
 F.place(f,1,-200,100,-2); F.tick(e,f,K.holdLineTime+0.3)
 assert((e.states[1].committed or 0)==0 and Priority.held(s,e.time)==0,'released')
 e=run(false); assert(Priority.held(e.states[2],e.time)==0 and count(e,'aide au depassement')==0,'switch off: nothing')
end

-- Essais à Monza du 11 novembre (correctifs pour tous). Attente après deux échecs levée, hors course, quand la cible est
-- de nouveau nettement rattrapée ; jamais avant K.passReopenWait s (K.passReopenWaitRace s en course), jamais sur un faible rapprochement.
tests.PASS_SUSPENSION_REOPEN_160A=function()
 assert(K.passReopenSa==25 and K.passReopenWait==10 and K.yieldOverallMargin==0.01 and K.yieldRefuseOverallKmh==8)
 local function run(profile,sa,since)
  local e,f=scene(profile,3,function(p) p.startDelay=0; p.startRelax=0 end)
  F.place(f,1,-5000,100); F.front(e,f,20,sa); F.tick(e,f,0.2)
  local s=e.states[2]; s.passIgnore=3; s.passIgnoreUntil=e.time+180; s.passIgnoreCount=K.passIgnoreStrict; s.passIgnoreAt=e.time-since
  local t=0
  while t<3 do F.front(e,f,20,sa); F.tick(e,f,1/60); t=t+1/60; if F.passing(s.state) then return true,e end end
  return false,e
 end
 local seen,e=run('P',30,20)
 assert(seen and count(e,'depassement rejuge: Driver_2 -> Driver_3')==1 and (e.stats.passReopen or 0)==1,'closing at +30 km/h, 20 s after the failure: judged again, one line')
 assert(J.english('depassement rejuge: A -> B (cible de nouveau rattrapee, 20 m, +25 km/h)')=='pass judged again: A -> B (target caught again, 20 m, +25 km/h)',J.english('depassement rejuge: A -> B (cible de nouveau rattrapee, 20 m, +25 km/h)'))
 assert(not run('P',30,2),'2 s after the failure: still suspended')
 assert(not run('P',20,20),'closing at +20 km/h (the loops of Beta 1.47): still suspended')
 assert(K.passReopenWaitRace==20 and not run('C',30,12),'race: still suspended 12 s after the failure')
 assert(run('C',30,21),'race (lot 4): judged again K.passReopenWaitRace s after the failure')
 assert(not run('C',20,21),'race: closing at +20 km/h: still suspended')
end
-- « Cible plus rapide » après un vrai rapprochement : pas compté vers l'attente stricte (hors course).
tests.PASS_FAILURE_AFTER_GAIN_160A=function()
 local function run(profile,gap0)
  local e,f=scene(profile,3,function(p) p.startDelay=0; p.startRelax=0 end); F.tick(e,f,0.2)
  F.place(f,1,-5000,100); F.place(f,2,0,100); F.place(f,3,12+4.4,108)
  local s=e.states[2]
  s.state='OVT_IN'; s.reason='pass'; s.since=e.time; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=12; s.passGap0=gap0; s.passName='Cible'
  s.abortSlow=0; s.passStall=0; s.passAlongside=false; s.passProgRef=12; s.passProgTime=0; s.lastPassTarget=3; s.nextPerception=0
  s.passIgnore=3; s.passIgnoreCount=1; s.passIgnoreUntil=e.time+100
  local t=0
  while t<K.abortSlowTime+1 do F.place(f,3,12+4.4,108); s.nextPerception=0; F.tick(e,f,1/60); t=t+1/60; if s.reason=='abort_slow' then break end end
  assert(s.reason=='abort_slow','target faster: '..tostring(s.reason))
  return s.passIgnoreCount,e
 end
 local n,e=run('P',20)
 assert(n==K.passIgnoreStrict-1 and count(e,'depassement suspendu:')==0,'8 m gained before the target left: not counted towards the suspension')
 n,e=run('P',12); assert(n==K.passIgnoreStrict and count(e,'depassement suspendu:')==1,'nothing gained: counted as in 1.59')
 n=run('C',20); assert(n==K.passIgnoreStrict-1,'race (lot 4): a failure after a real gain is not counted either')
 n=run('C',12); assert(n==K.passIgnoreStrict,'race: nothing gained: counted')
end
-- Refus de céder : jamais à un suiveur au rythme d'ensemble meilleur que le sien, même plus lent à cet endroit.
tests.YIELD_REFUSAL_OVERALL_PACE_160A=function()
 local function learned(e,i,kmh) local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=kmh/3.6 end; s.paceMean=kmh/3.6 end
 local function yields(mineRatio,theirRatio,theirs)
  local e,f=scene('J',3,function(p) p.flashObliviousPct=0 end)
  F.rear(e,f,45,30,3)
  for _=1,4*60 do
   learned(e,2,180); learned(e,3,theirs or 175)
   if mineRatio then e.states[2].paceRatio=mineRatio; e.states[2].paceRatioCount=K.paceRatioMin; e.states[3].paceRatio=theirRatio; e.states[3].paceRatioCount=K.paceRatioMin end
   F.tick(e,f,1/60); if F.yielding(e.states[2].state) then return true,e end
  end
  return false,e
 end
 assert(not yields(),'follower 5 km/h slower here, overall pace unknown: refused as in 1.59')
 assert(not yields(1.01,0.99),'slower here and slower overall: refused')
 assert(not yields(1,1.005),'overall pace within the margin: refused')
 assert((yields(0.99,1.01)),'5 km/h slower here but clearly faster overall: not refused')
 assert(not yields(0.99,1.01,170),'10 km/h slower here: refused even when faster overall')
end
-- Aide au dépassement : attaquant engagé, « sans progrès » et « trop longue » attendent K.passAidMax s.
tests.PASS_AID_NO_PROGRESS_HOLD_160A=function()
 local function run(on)
  local e,f,s=passScene('P',on,5,2)
  s.passProgTime=K.passProgressTime+1; s.passProgRef=5
  F.place(f,2,0,100,2); s.nextPerception=0; F.tick(e,f,1/60); F.tick(e,f,1/60)
  return s
 end
 local s=run(false); assert(s.reason=='abort_noprogress','1.59: no progress ends the attempt ('..tostring(s.reason)..')')
 s=run(true); assert(s.committed==3 and F.passing(s.state) and s.state~='OVT_OUT','committed: the attempt goes on ('..tostring(s.reason)..')')
end

-- Fin de chaque cession au journal, avec le décalage voulu, atteint et permis par la largeur de piste.
tests.YIELD_END_LINE_160A=function()
 local function run(width)
  local e,f=scene('J',3,function(p) p.flashObliviousPct=0 end)
  for i=1,3 do f.cars[i].leftWidth=width; f.cars[i].rightWidth=12-width end
  F.place(f,1,-5000,100); F.rear(e,f,45,30,3)
  local s=e.states[2]; local seen=false
  for _=1,6*60 do F.tick(e,f,1/60); if F.yielding(s.state) then seen=true; break end end
  assert(seen,'the yield starts')
  F.tick(e,f,2)
  F.place(f,3,40,130); s.nextPerception=0; F.tick(e,f,3)
  return e,s
 end
 local e=run(6)
 assert(count(e,'cession finie: Driver_2 -> Driver_3 : ')==1,'one line per yield')
 local function last(e2) local line; for k=1,e2.log.limit do local r=e2.log[k]; if r and r.message and r.message:find('cession finie:',1,true) then line=r.message end end return line end
 local pattern='decalage voulu ([%d.]+), atteint ([%d.]+) soit ([%d.]+) m vers la (%a+), piste alors ([%d.]+) m a gauche, ([%d.]+) m a droite ; borne la plus basse ([%d.]+)'
 local line=last(e)
 local wanted,reached,metres,side,left,right,lowest=line:match(pattern)
 assert(tonumber(wanted)>=0.5 and tonumber(reached)>0.2 and side=='droite' and tonumber(left)==6 and tonumber(right)==6 and tonumber(lowest)>=tonumber(reached)-0.01,line)
 assert(math.abs(tonumber(metres)-tonumber(reached)*6)<0.06,'metres in the scale of the side: '..line)
 assert(J.english(line):find('yield ended: Driver_2 -> Driver_3: ',1,true)==1 and J.english(line):find(' m to the right, track then 6.0 m on the left',1,true),J.english(line))
 -- Trajectoire au bord gauche de la piste (1,5 m à gauche, 10,5 m à droite), cession à droite (défaut) : vers le grand
 -- côté, la borne par côté laisse K.reachWideMeters m ; la voiture quitte vraiment la trajectoire.
 line=last(run(1.5)); wanted,reached,metres,side,left,right,lowest=line:match(pattern)
 assert(side=='droite' and tonumber(left)==1.5 and tonumber(right)==10.5 and tonumber(metres)>3 and tonumber(metres)<=K.reachWideMeters+0.06,'line along the left edge, yield to the right: real room: '..line)
 assert(not line:find('autre cote pris',1,true),'set side kept: '..line)
 -- Trajectoire au bord droit (10,5 m à gauche, 1,5 m à droite), cession réglée à droite : ce côté n'a pas de place,
 -- l'autre en a : cession à gauche (relecture), dite au journal.
 line=last(run(10.5)); wanted,reached,metres,side,left,right,lowest=line:match(pattern)
 assert(side=='gauche' and tonumber(left)==10.5 and tonumber(right)==1.5 and tonumber(metres)>3,'line along the right edge: the yield goes to the side that has room: '..line)
 assert(line:find(' ; cote regle sans place, autre cote pris)',1,true) and J.english(line):find('other side taken)',1,true),'swap said in the line: '..line)
end
-- Tentative de dépassement : il faut de la place (K.passMinRoom m de décalage permis) ; voiture lente : toujours.
tests.PASS_NEEDS_ROOM_160A=function()
 assert(K.passMinRoom==1.2)
 local function run(width,slow)
  local e,f=scene('P',3,function(p) p.startDelay=0; p.startRelax=0; p.yieldEnabled=false end)
  for i=1,3 do f.cars[i].leftWidth=width; f.cars[i].rightWidth=width end
  F.place(f,1,-5000,100); F.front(e,f,20,30); F.tick(e,f,0.2)
  local s=e.states[2]
  local t=0
  while t<4 do F.front(e,f,20,30); if slow then e.states[3].abnormal=true end; F.tick(e,f,1/60); t=t+1/60; if F.passing(s.state) then return true,e end end
  return false,e
 end
 assert((run(6)),'12 m of track: the attempt starts')
 local seen,e=run(1.9)
 assert(not seen and (e.stats.passNoRoom or 0)==1,'3.8 m of track (0.97 m of offset): no attempt, counted once: '..tostring(seen)..' '..tostring(e.stats.passNoRoom)..' '..e.states[2].state)
 assert((run(2.3)),'4.6 m of track (1.37 m of offset): the attempt starts')
end
return tests
