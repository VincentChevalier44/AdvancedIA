-- Beta 1.61 (finition) : tests restés à écrire après les relectures des lots de la 1.60. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Rear=require('src/rear')
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

-- Relecture S6 : une seule réouverture par attente. Une paire déjà rejugée pendant cette attente ne l'est plus, même
-- de nouveau rattrapée à +30 km/h ; pendant les K.passReopenHold s qui suivent la réouverture, la tentative reste
-- permise (le temps de l'engager).
tests.PASS_SUSPENSION_SINGLE_REOPEN_161F=function()
 local function run(reopenedAgo)
  local e,f=scene('P',3,function(p) p.startDelay=0; p.startRelax=0 end)
  F.place(f,1,-5000,100); F.front(e,f,20,30); F.tick(e,f,0.2)
  local s=e.states[2]; s.passIgnore=3; s.passIgnoreUntil=e.time+180; s.passIgnoreCount=K.passIgnoreStrict; s.passIgnoreAt=e.time-20
  s.passReopened=reopenedAgo and e.time-reopenedAgo or nil
  local before=e.stats.passReopen or 0
  local t=0
  while t<3 do F.front(e,f,20,30); F.tick(e,f,1/60); t=t+1/60; if F.passing(s.state) then return true,e,(e.stats.passReopen or 0)-before end end
  return false,e,(e.stats.passReopen or 0)-before
 end
 local seen,e,n=run(nil)
 assert(seen and n==1 and count(e,'depassement rejuge:')==1,'first reopening: judged again, one line')
 seen,e,n=run(K.passReopenHold+5)
 assert(not seen and n==0 and count(e,'depassement rejuge:')==0,'already reopened during this suspension: held until it ends')
 seen,e,n=run(1)
 assert(seen and n==0,'within K.passReopenHold s of the reopening: the attempt may still start, no second line')
end

-- Relecture N8 : le régulateur (pas de coup de frein, voiture collée derrière) ne relève jamais le plafond
-- d'accélérateur voulu par une panne (src/strategy.lua, c.failCeil) ; un plafond d'une autre source est relevé.
tests.GOVERN_FAILURE_CEILING_161F=function()
 local e,f=scene('P',3)
 F.place(f,1,-5000,100); F.rear(e,f,5,0,3); F.tick(e,f,0.3)
 local s,cmd=e.states[2],e.commands[2]
 assert(s.rearClose,'a car close behind')
 e.strategy=e.strategy or {}; e.strategy.cars=e.strategy.cars or {}
 local saved=e.strategy.cars[2]
 cmd.throttleLimit=0.4; e.strategy.cars[2]={failCeil=0.4,failCeilAt=e.time}
 Rear.govern(e.rear,e,f,e.time,1/60)
 assert(cmd.throttleLimit==0.4,'failure ceiling kept: '..tostring(cmd.throttleLimit))
 cmd.throttleLimit=0.4; e.strategy.cars[2]={failCeil=0.4,failCeilAt=e.time-1}
 Rear.govern(e.rear,e,f,e.time,1/60)
 assert(cmd.throttleLimit>=K.rearThrottleFloor,'an older or other ceiling is raised to the governor floor: '..tostring(cmd.throttleLimit))
 e.strategy.cars[2]=saved
end

-- Lot 3 : nom lu à travers ac.getDriverName (suffixe de Content Manager retiré, nom brut gardé pour l'identité), et
-- relecture N3 : le niveau affiché est le niveau réellement écrit (facteur des modules compris).
tests.DRIVER_NAME_READ_AND_LEVEL_161F=function()
 local host=require('tests/host').create(true)
 local Snapshot=require('src/snapshot'); local saved=ac.getDriverName
 ac.getDriverName=function(index) if index==1 then return 'G. Tsaknis (100%, 100%)' elseif index==2 then return 'P. Müller (100%' end return 'Driver '..index end
 local ok,err=pcall(function()
  local s=Snapshot.new(); Snapshot.read(s,1/60,0)
  local a,b,c=s.cars[2],s.cars[3],s.cars[1]
  assert(a.rawName=='G. Tsaknis (100%, 100%)' and a.baseName=='G. Tsaknis' and a.cmSuffix==true and a.name=='G. Tsaknis','suffix stripped: '..tostring(a.name))
  assert(b.baseName=='P. Müller' and b.cmSuffix==true,'cut suffix stripped: '..tostring(b.name))
  assert(c.name=='Driver 0' and not c.cmSuffix,'name without the suffix kept')
  local identity=a.identity
  Snapshot.read(s,1/60,5); assert(a.identity==identity,'identity follows the raw name, stable')
  assert(host~=nil)
 end)
 ac.getDriverName=saved
 assert(ok,err)
 -- N3 : un tour de chauffe (facteur des modules 0.8) se voit dans le nom.
 local e,f=F.scene('P',3)
 local S=require('src/snapshot')
 local a=f.cars[2]; a.rawName='G. Tsaknis (100%, 100%)'; a.baseName='G. Tsaknis'; a.cmSuffix=true; a.name='G. Tsaknis'
 F.tick(e,f,1/60)
 local cmd=e.commands[2]; cmd.level=1; cmd.aggression=0.5; cmd.levelScale=0.8
 e.namesAt=-math.huge; E.names(e,f,e.time)
 assert(a.name=='G. Tsaknis (80%, 50%)','level times the module factor: '..a.name)
 assert(S~=nil)
end

-- Relecture S10 : un à-coup d'image (capture, Alt-Tab) ne fait pas croire à une téléportation : le saut est jugé
-- contre le chemin parcouru (K.teleportPath fois la vitesse fois l'intervalle), K.teleport m au moins.
tests.TELEPORT_THRESHOLD_SCALED_161F=function()
 local host=require('tests/host').create(true)
 local Snapshot=require('src/snapshot'); local s=Snapshot.new()
 local car=host.cars[1]
 local function at(z,kmh) car.position={x=0,y=0,z=z}; car.speedKmh=kmh; car.velocity={x=0,y=0,z=kmh/3.6} end
 at(1000,300); Snapshot.read(s,1/60,0); Snapshot.read(s,1/60,1/60)
 at(1000+70,300); Snapshot.read(s,1,1)
 assert(s.cars[2].teleport==false,'70 m in a 1 s stall at 300 km/h: driven, not teleported')
 at(1000+70+70,300); Snapshot.read(s,1/60,1+1/60)
 assert(s.cars[2].teleport==true,'70 m in one normal frame: teleported')
 at(2000,0); Snapshot.read(s,1/60,2); at(2000+K.teleport+1,0); Snapshot.read(s,1/60,2+1/60)
 assert(s.cars[2].teleport==true,'stopped car moved more than K.teleport m: teleported')
 assert(K.teleport==40 and K.teleportPath==1.5)
end

-- Relecture S1 (lot 3) : voiture de sécurité en tête-à-queue, arrêtée ou hors piste : la contourner n'est ni noté
-- « doublée » ni sanctionné ; la surveillance reprend quand elle roule de nouveau.
tests.SC_STOPPED_NOT_PASSED_161F=function()
 local Incidents=require('src/incidents')
 local e,f=F.scene('C',5); C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; E.changed(e)
 e.g.safetyCarModel='car_5'; F.place(f,5,0,0); f.cars[5].pit=true; f.cars[5].inPitBox=true
 f.cars[1].pit=true; f.cars[1].inPitBox=true
 F.place(f,2,1000,120); F.place(f,3,900,120); f.cars[2].position=1; f.cars[3].position=2
 F.place(f,4,6000,0)
 for _=1,900 do F.tick(e,f,0.1); if e.incidents.safetyPhase=='place' then break end end
 F.place(f,4,6000,60); f.cars[4].pit=true
 F.place(f,5,1200,80); f.cars[5].pit=false; f.cars[5].inPitBox=false; F.tick(e,f,0.5)
 local t=e.incidents; assert(t.safetyPhase=='out','on track')
 F.place(f,2,1150,100); F.tick(e,f,0.3); assert(t.cars[2].scBehind,'behind it')
 -- Tête-à-queue : elle s'arrête presque ; la voiture 2 la contourne.
 F.place(f,5,1200,5); F.tick(e,f,0.1); F.place(f,2,1215,60); F.tick(e,f,0.1)
 assert(not t.cars[2].scPassed and count(e,'voiture de securite: doublee')==0 and count(e,'sanction IA: Driver_2')==0,'going round a stopped safety car: no pass, no sanction')
 assert(not t.cars[2].scBehind,'watch cleared while it is stopped')
 assert(Incidents.cap~=nil)
end

-- Relecture S7 (lot 3) : la cession « vers le côté qui a la place » ne change jamais de côté vers un suiveur déjà
-- décalé de ce côté-là. Trajectoire au bord droit (1,5 m), côté réglé à droite : échange vers la gauche, sauf si le
-- suiveur arrive déjà décalé à gauche. Signes du jeu (-1 / -1).
tests.YIELD_NO_SWAP_TOWARDS_FOLLOWER_161F=function()
 local function run(x)
  local e,f=F.scene('J',3); e.g.offsetSign=-1; e.g.sideSign=-1; e.profiles.J.flashObliviousPct=0; e.profiles.J.yieldSide='right'; E.changed(e)
  for i=1,3 do f.cars[i].leftWidth=10.5; f.cars[i].rightWidth=1.5; f.cars[i].sideDot=-1 end
  F.place(f,1,-5000,100); F.rear(e,f,45,30,3); if x then F.place(f,3,-45-4.4,130,x) end
  local s=e.states[2]
  for _=1,6*60 do F.tick(e,f,1/60); if F.yielding(s.state) then break end end
  assert(F.yielding(s.state),'the yield starts')
  F.tick(e,f,1.5)
  return s.offset*e.g.offsetSign
 end
 assert(run(nil)<-0.25,'follower on the line: swapped to the side with room (left)')
 local a,b=run(2.5),run(-2.5)
 assert((a<-0.25)~=(b<-0.25),'follower offset to one side: the swap towards it is refused, the other kept ('..a..' / '..b..')')
 assert(K.sideFollowerLat==1)
end

-- Relecture S7 (1.60, jugement des contacts) : l'écart latéral est mesuré par rapport à la trajectoire ; quand la
-- trajectoire elle-même traverse la piste pendant la fenêtre (milieu de piste déplacé de plus de K.blameMoveMin/2 m),
-- une voiture qui roule droit semble changer de ligne : jamais un verdict « changement de ligne » sur cette mesure.
tests.BLAME_LINE_CROSSING_UNKNOWN_161F=function()
 local function run(cross)
  local e,f=F.scene('C',4); e.profiles.C.sanContact=true; E.changed(e); F.tick(e,f,0.1)
  for i=1,f.count do F.place(f,i,(i-2)*1000,100); f.cars[i].leftWidth=6; f.cars[i].rightWidth=6 end
  F.tick(e,f,1.5)
  F.place(f,2,0,115,0); F.place(f,3,5,100,3); F.tick(e,f,1.5)
  for k=1,48 do
   F.place(f,3,5,100,3-3*k/48)
   if cross then for i=2,3 do f.cars[i].leftWidth=6+3*k/48; f.cars[i].rightWidth=6-3*k/48 end end
   F.tick(e,f,1/60)
  end
  f.cars[2].collidedWith=3; F.tick(e,f,1/60); f.cars[2].collidedWith=nil; F.tick(e,f,K.blameOutcome+0.4)
  return count(e,'ligne droite changement de ligne : Driver_3 en tort'),count(e,'responsabilite: contact Driver_2 / Driver_3'),count(e,'incident de course: contact Driver_2 / Driver_3 (indetermine)')
 end
 local cut,cases=run(false); assert(cut==1 and cases==1,'track middle steady: the car that moved across is at fault')
 local unknown; cut,cases,unknown=run(true); assert(cut==0 and cases==0 and unknown==1,'the racing line crosses the track during the window: no verdict on that measure (race incident, undetermined)')
end

-- Contrat SpotterEnginer (1,5 s d'attente chez lui) : la clé du trafic est publiée tout de suite quand le genre,
-- l'étape ou la voiture change ; seuls l'écart, l'approche et le nombre restent limités à une fois par seconde.
tests.TRAFFIC_KEY_IMMEDIATE_ON_STAGE_161F=function()
 local Nuance=require('src/nuance')
 local e,f=F.scene('C',3); e.profiles.C.classNuance=true; E.changed(e)
 local function at(gap) F.place(f,1,0,100); F.place(f,2,5000,100); F.place(f,3,-gap-4.4,130); f.cars[3].lap=f.cars[1].lap+2 end
 local t=0; while t<2.5 do at(100); F.tick(e,f,1/60); t=t+1/60 end
 local key=e.sideText[Nuance.sideKey]; assert(key and key:find('stage=none',1,true),'none first: '..tostring(key))
 -- Publication toute fraîche : l'ancienne limite aurait retenu le changement jusqu'à une seconde.
 e.nuance.sideAt=e.time+1
 local waited=0
 repeat at(40); F.tick(e,f,1/60); waited=waited+1/60; key=e.sideText[Nuance.sideKey] until key:find('stage=advise',1,true) or waited>2
 assert(key:find('stage=advise;car=2;',1,true) and waited<=0.3,'stage change published at once ('..waited..' s): '..tostring(key))
 -- Même étape, autre écart : limité à une fois par seconde.
 local before=key; at(35); F.tick(e,f,1/60)
 assert(e.sideText[Nuance.sideKey]==before,'gap only: held by the 1 s throttle')
 -- Drapeau bleu en cours, écart stable : réécrite chaque seconde, stamp qui avance (sinon SpotterEnginer la croit figée).
 local seen,last=0,e.sideText[Nuance.sideKey]
 for _=1,4*60 do at(40); F.tick(e,f,1/60); local k=e.sideText[Nuance.sideKey]; if k~=last then seen=seen+1; last=k end end
 assert(seen>=3 and last:find('stage=advise',1,true),'steady gap during a blue: text changes every second ('..seen..' changes in 4 s)')
 -- Plus de drapeau bleu : publiée une fois, puis inchangée.
 for _=1,60 do at(400); F.tick(e,f,1/60) end
 local none=e.sideText[Nuance.sideKey]; assert(none:find('blue=none',1,true),none)
 for _=1,3*60 do at(400); F.tick(e,f,1/60) end
 assert(e.sideText[Nuance.sideKey]==none,'no blue: rewritten only on change')
end

-- Relecture S8 (aide au dépassement, réglage passAid) : joueur engagé sur deux IA à la fois (derrière l'une, à la
-- hauteur de l'autre) : chacune tient sa ligne avec une ligne de journal et un compte à elle, jamais une ligne et un
-- compte à chaque image (l'engagement du joueur n'est pas repris d'une IA à l'autre).
tests.PASS_AID_PLAYER_TWO_AI_161F=function()
 local Priority=require('src/priority')
 local e,f=scene('C',4,function(p) p.passAid=true; p.startDelay=0; p.startRelax=0 end)
 local function put() F.place(f,2,0,100); F.place(f,1,-4-4.4,110,-2); F.place(f,4,-4-4.4+1,105,-5); F.place(f,3,5000,100) end
 put(); F.tick(e,f,0.2)
 local flips,last=0,nil
 for _=1,120 do put(); e.states[2].nextPerception=0; e.states[4].nextPerception=0; F.tick(e,f,1/60); local c=e.states[1].committed or 0; if c~=0 and last and c~=last then flips=flips+1 end; if c~=0 then last=c end end
 assert(flips==0 and e.states[1].committed==2,'the player commitment stays with the first AI, never taken over by the other: '..flips..' flips, '..tostring(e.states[1].committed))
 local a,b=count(e,'aide au depassement: Driver_1 engage sur Driver_2'),count(e,'aide au depassement: Driver_1 engage sur Driver_4')
 assert(a==1 and b==1,'one line per AI, not one per frame: '..a..' / '..b)
 assert((e.stats.passCommit or 0)==2,'one count per AI: '..tostring(e.stats.passCommit))
 assert(Priority.held(e.states[2],e.time)==1 and Priority.held(e.states[4],e.time)==1,'both hold their line')
end

-- Course au Red Bull Ring (lot 5) : un plan qui passe à 0 arrêt (carburant suffisant après un ravitaillement) est dit
-- en clair, jamais « prochain vers le tour -1 » ; la scène écrit vraiment la ligne.
tests.PLAN_WITHOUT_STOP_WRITTEN_161F=function()
 local e,f=F.scene('C',3); e.profiles.C.strategyEnabled=true; e.profiles.C.section_strategy=true; E.changed(e)
 f.sessionLaps=10; f.timedRace=false; f.sessionMinutes=0; f.leaderLaps=2
 for i=1,3 do local a=f.cars[i]; a.lap=2; a.fuel=8; a.maxFuel=120; a.fuelPerLap=2; a.wearKnown=true; a.tyreWear={0.01,0.01,0.01,0.01} end
 e.strategy.wearTrust='trusted'
 for lap=2,3 do for i=1,3 do f.cars[i].lap=lap end; F.tick(e,f,1) end
 assert(count(e,'strategie: Driver_2 plan 1 arret(s), prochain vers le tour')>=1,'short of fuel: one stop planned')
 F.tick(e,f,K.strategyPlanLogGap+1)
 -- Arrêt aux stands : ravitaillée, la voiture repart avec de quoi finir.
 for i=1,3 do local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0 end; F.tick(e,f,5)
 for i=1,3 do local a=f.cars[i]; a.fuel=100; a.pit=false; a.inPitBox=false; a.kmh=100 end; F.tick(e,f,1)
 for lap=4,6 do for i=1,3 do f.cars[i].lap=lap end; F.tick(e,f,K.strategyPlanLogGap+1) end
 assert(count(e,'strategie: Driver_2 plan 0 arret(s), aucun arret prevu, risque ')==1,'plan without a stop said in words')
 assert(count(e,'tour -1')==0,'never a negative lap')
end

return tests
