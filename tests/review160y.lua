-- Beta 1.60, lot 5 (course du pilote du 11 novembre au Nürburgring, relecture du lot 3) : attente d'un dépassement en
-- course, attardée jamais « abandonnée », voiture lente qui ne défend pas et s'écarte, journal des drapeaux bleus entre
-- IA, voiture de sécurité (allure libre bornée, hystérésis, zone d'incident, regroupement, délai maximal, enveloppe du
-- rattrapage, place laissée), voiture en difficulté en tête de file seulement. Noms terminés par _160Y. Chargé par
-- tests/extended.lua. Valeurs des voitures : celles que le jeu fournit (position, vitesse, tour, voie des stands).
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local J=require('src/journal')
local Incidents=require('src/incidents')
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
-- Voiture de sécurité (voiture 5) posée en piste à 1200 m devant le meneur (voiture 2), comme tests/review160s.lua.
local function deployed(setup)
 local e,f=F.scene('C',5); C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; if setup then setup(e) end; E.changed(e)
 e.g.safetyCarModel='car_5'; F.place(f,5,0,0); f.cars[5].pit=true; f.cars[5].inPitBox=true
 f.cars[1].pit=true; f.cars[1].inPitBox=true
 F.place(f,2,1000,120); F.place(f,3,900,120); f.cars[2].position=1; f.cars[3].position=2
 F.place(f,4,6000,0)
 for _=1,900 do F.tick(e,f,0.1); if e.incidents.safetyPhase=='place' then break end end
 assert(e.incidents.neutral and e.incidents.safetyPhase=='place','safety car to be placed')
 F.place(f,4,6000,60); f.cars[4].pit=true
 F.place(f,5,1200,80); f.cars[5].pit=false; f.cars[5].inPitBox=false; F.tick(e,f,0.5)
 assert(e.incidents.safetyPhase=='out','on track')
 return e,f,e.incidents
end

tests.K_160Y=function()
 assert(K.passIgnoreMaxRace==180 and K.passIgnoreMaxRace<K.passIgnoreMax and K.scFreeGap<K.scLeadGap and K.scFreeMargin>0 and K.scBunchMax==180)
 assert(K.scGiveFloor>K.trafficMinSpeed and K.scGiveStuck<K.scPassedMax and K.troubleAheadGap==30 and K.planSpreadLaps==2)
 assert(K.scNominalKmh+K.scCatchUp-K.scFreeMargin>K.scLeadKmh,'free pace with unknown pace: above the slow pace, under the catch-up of the field')
end
-- Tentative en cours de l'IA 2 sur la voiture 3 qui s'échappe : « cible plus rapide ».
local function failed(profile,already,lapsAhead)
 local e,f=scene(profile,3,function(p) p.startDelay=0; p.startRelax=0 end); F.tick(e,f,0.2)
 F.place(f,1,-5000,100); F.place(f,2,0,100); F.place(f,3,12+4.4,108)
 if lapsAhead then f.cars[2].lap=f.cars[2].lap+lapsAhead end
 local s=e.states[2]
 s.state='OVT_IN'; s.reason='pass'; s.since=e.time; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=12; s.passGap0=12; s.passName='Cible'
 s.abortSlow=0; s.passStall=0; s.passAlongside=false; s.passProgRef=12; s.passProgTime=0; s.lastPassTarget=3; s.nextPerception=0
 s.passIgnore=3; s.passIgnoreCount=already; s.passIgnoreUntil=e.time+100
 local t=0
 while t<K.abortSlowTime+4 do F.place(f,3,12+4.4+t*8/3.6,108); s.nextPerception=0; F.tick(e,f,1/60); t=t+1/60; if s.reason=='abort_slow' then break end end
 assert(s.reason=='abort_slow','target faster: '..tostring(s.reason))
 return s,e
end
-- En course, jamais plus de K.passIgnoreMaxRace s d'attente ; hors course, la borne de la 1.54 (600 s).
tests.RACE_SUSPENSION_CAP_160Y=function()
 local s,e=failed('C',3)
 assert(s.passIgnoreCount==4 and math.abs(s.passIgnoreUntil-e.time-K.passIgnoreMaxRace)<1 and count(e,'plus de tentative pendant 180 s')==1,'race: third tier capped at 180 s ('..(s.passIgnoreUntil-e.time)..')')
 s,e=failed('P',3)
 assert(math.abs(s.passIgnoreUntil-e.time-K.passIgnoreMax)<1 and count(e,'plus de tentative pendant 600 s')==1,'outside the race: 600 s as before')
end
-- En course, un échec contre une voiture à qui l'on prend un tour n'est jamais compté (ni attente, ni ligne).
tests.LAPPED_TARGET_NEVER_SUSPENDED_160Y=function()
 local s,e=failed('C',1,2)
 assert(s.passIgnoreCount==1 and count(e,'depassement suspendu:')==0,'lapped target: failure not counted ('..s.passIgnoreCount..')')
 -- Finition 1.61 (relecture) : courte attente fixe, jamais plus longue au fil des échecs.
 assert(s.lappedHold==3 and math.abs(s.lappedHoldUntil-(e.time+K.passLappedHold))<1 and K.passLappedHold==10,'lapped target: short fixed hold')
 s,e=failed('C',1)
 assert(s.passIgnoreCount==2 and count(e,'depassement suspendu:')==1,'same lap: counted as before')
 s,e=failed('P',1,2)
 assert(s.passIgnoreCount==2,'outside the race the lap gap only tells the time on track: counted')
end
-- Journal des drapeaux bleus entre IA (course) : cession notée une fois, compteur ; retard noté avec la raison.
tests.BLUE_FLAG_AI_JOURNAL_160Y=function()
 local e,f=scene('C',3,function(p) p.startDelay=0; p.startRelax=0; p.laneBiasEnabled=false end)
 F.place(f,1,-5000,100)
 local t=0
 while t<5 do F.rear(e,f,50,35); f.cars[3].lap=3; F.tick(e,f,1/60); t=t+1/60 end
 assert(F.yielding(e.states[2].state),'lapped car yields ('..e.states[2].state..')')
 assert(count(e,'drapeau bleu IA: Driver_2 laisse passer Driver_3 (3 tour(s) d avance) apres ')==1 and e.stats.blueAiYield==1,'one line, one count')
 assert(count(e,'sans la laisser passer')==0 and (e.stats.blueAiLate or 0)==0,'no late line when it yields in time')
 assert(J.english('drapeau bleu IA: A laisse passer B (2 tour(s) d avance) apres 1.2 s')=='blue flag between AI: A lets B through (2 lap(s) ahead) after 1.2 s',J.english('drapeau bleu IA: A laisse passer B (2 tour(s) d avance) apres 1.2 s'))
 -- Drapeaux bleus coupés : la voiture ne cède pas pour le tour d'écart, rien n'est noté (le journal suit le réglage).
 local n,g=scene('C',3,function(p) p.startDelay=0; p.startRelax=0; p.blueFlagEnabled=false end)
 F.place(g,1,-5000,100); t=0
 while t<5 do F.rear(n,g,50,35); g.cars[3].lap=3; F.tick(n,g,1/60); t=t+1/60 end
 assert(count(n,'drapeau bleu IA')==0,'setting off: nothing logged')
 -- Même tour : pas un drapeau bleu.
 local m,h=scene('C',3,function(p) p.startDelay=0; p.startRelax=0 end)
 F.place(h,1,-5000,100); t=0
 while t<5 do F.rear(m,h,50,35); F.tick(m,h,1/60); t=t+1/60 end
 assert(count(m,'drapeau bleu IA')==0,'same lap: nothing logged')
 -- Cession impossible (attardée en plein virage) : retard noté une fois après K.blueLogTime s, avec la raison.
 local l,k=scene('C',3,function(p) p.startDelay=0; p.startRelax=0 end)
 F.place(k,1,-5000,100); t=0
 while t<K.blueLogTime+2 do F.rear(l,k,30,2); k.cars[3].lap=3; k.cars[2].yawRate=l.run.cornerYawRef; F.tick(l,k,1/60); t=t+1/60 end
 assert(not F.yielding(l.states[2].state),'in a corner: no yield')
 assert(count(l,'drapeau bleu IA: Driver_2 devant Driver_3 depuis ')==1 and count(l,'sans la laisser passer (virage, ')==1 and l.stats.blueAiLate==1,'late: one line, one count ('..count(l,'drapeau bleu IA')..')')
end
-- Voiture lente à contourner (s.abnormal, posé par le moteur) en course : elle ne défend jamais.
tests.SLOW_CAR_NEVER_DEFENDS_160Y=function()
 local function run(slow)
  local e,f=scene('C',3,function(p) p.rearAwareness=false; p.defenseEnabled=true; p.defenseTriggerGap=40; p.startDelay=0; p.startRelax=0 end)
  K.defenseChance=1
  F.place(f,1,-5000,100); F.place(f,2,0,100); F.place(f,3,-25-4.4,110,-1.2)
  local s=e.states[2]; s.nextPerception=0
  local t=0
  while t<0.8 do
   F.place(f,3,-25-4.4,110,-1.2); s.nextPerception=0; s.persona.awareness=e.run.awMin
   if slow then s.abnormalFor=K.slowObstacleTime+10 end
   F.tick(e,f,1/60); t=t+1/60
   if s.state=='DEFEND' then break end
  end
  return s.state=='DEFEND',s
 end
 local chance=K.defenseChance
 local ok,err=pcall(function()
  assert((run(false)),'ordinary car: defends')
  local seen,s=run(true)
  assert(s.abnormal==true,'precondition: flagged slow by the engine')
  assert(not seen,'slow car: never defends')
 end)
 K.defenseChance=chance
 assert(ok,err)
end
-- Voiture lente à contourner en course : elle s'écarte pour la voiture qui arrive (comme sous drapeau bleu), une ligne.
tests.SLOW_CAR_MOVES_ASIDE_160Y=function()
 local function run(slow)
  local e,f=scene('C',3,function(p) p.startDelay=0; p.startRelax=0; p.defenseEnabled=false end)
  F.place(f,1,-5000,100)
  local s=e.states[2]; local t=0
  while t<5 do
   F.rear(e,f,50,35); if slow then s.abnormalFor=K.slowObstacleTime+10 end
   F.tick(e,f,1/60); t=t+1/60
   if F.yielding(s.state) then break end
  end
  return F.yielding(s.state),e,s
 end
 local seen,e,s=run(true)
 assert(s.abnormal==true,'precondition: flagged slow by the engine')
 assert(seen and s.yieldBlue==true and count(e,'IA lente: Driver_2 s ecarte pour Driver_3')==1 and e.stats.slowYield==1,'slow car in a race: moves aside, one line')
 assert(not run(false),'ordinary car in a race, same lap: no yield')
 assert(J.english('IA lente: A s ecarte pour B (50 m, +35 km/h)')=='slow AI: A moves aside for B (50 m, +35 km/h)',J.english('IA lente: A s ecarte pour B (50 m, +35 km/h)'))
end
-- Voiture en difficulté : seulement la tête d'un train lent, jamais la voiture retenue par celle de devant.
tests.TROUBLE_HEAD_ONLY_160Y=function()
 local function run(gapAhead)
  local e,f=F.scene('C',4); e.profiles.C.neutralization='fcy'; E.changed(e); F.tick(e,f,0.1)
  for i=1,4 do F.place(f,i,(i-2)*300,100) end
  e.incidents.neutral=true; e.incidents.neutralMode='fcy'; e.incidents.neutralSince=e.time; e.incidents.neutralUntil=e.time+600
  local s=e.states[3]
  for _=1,60*5 do
   F.place(f,3,300,30); F.place(f,2,0,70); F.place(f,4,300+4.4+gapAhead,30)
   for b=1,#s.pace do s.pace[b]=200/3.6 end; s.paceCount=#s.pace
   -- La voiture de devant est elle-même en difficulté (aucune file derrière elle) : la limite de 3 reste celle du drapeau.
   e.incidents.cars[4].trouble=true
   e.incidents.neutral=true; s.nextPerception=0
   F.tick(e,f,1/60)
  end
  return e.incidents.cars[3].trouble==true
 end
 assert(run(200),'nobody close ahead: in trouble as before')
 assert(not run(K.troubleAheadGap-10),'held up by the car ahead: not in trouble')
end
-- Allure libre de la voiture de sécurité : nombre fini quand l'allure du peloton est inconnue ; hystérésis sur l'écart.
tests.SC_FREE_PACE_BOUNDED_160Y=function()
 local e,f,t=deployed()
 local free=K.scNominalKmh+K.scCatchUp-K.scFreeMargin
 assert(e.commands[5].scSpeed==K.scLeadKmh and t.safetySlow,'slow while the field is far behind')
 F.place(f,2,1200-100,120); F.place(f,3,1000,120); F.tick(e,f,0.2)
 assert(t.safetySlow and e.commands[5].scSpeed==K.scLeadKmh,'100 m behind after being slow: still slow (hysteresis)')
 F.place(f,2,1200-K.scFreeGap+10,120); F.tick(e,f,0.2)
 assert(not t.safetySlow and e.commands[5].scSpeed==free,'under K.scFreeGap: free, a finite pace while the pace of the field is unknown: '..tostring(e.commands[5].scSpeed))
 F.place(f,2,1200-100,120); F.tick(e,f,0.2)
 assert(not t.safetySlow and e.commands[5].scSpeed==free,'back to 100 m: still free (hysteresis)')
 F.place(f,2,1200-K.scLeadGap-10,120); F.tick(e,f,0.2)
 assert(t.safetySlow and e.commands[5].scSpeed==K.scLeadKmh,'beyond K.scLeadGap: slow again')
end
-- Zone d'incident en piste ou son approche : allure nominale au plus.
tests.SC_ZONE_NOMINAL_160Y=function()
 local e,f,t=deployed()
 F.place(f,2,1200-50,120); F.tick(e,f,0.2)
 assert(e.commands[5].scSpeed>K.scNominalKmh,'precondition: free above the nominal pace')
 local zone=t.zones[1] or {}; t.zones[1]=zone
 local count0=t.zoneCount
 zone.slot=4; zone.spline=(1200+300)/f.length; zone.onTrack=true; t.zoneCount=1
 Incidents.safety(t,e.commands,e.run,f,e.delta,e.states)
 assert(e.commands[5].scSpeed==K.scNominalKmh,'approaching a zone with a car on track: nominal pace ('..tostring(e.commands[5].scSpeed)..')')
 zone.onTrack=false; Incidents.safety(t,e.commands,e.run,f,e.delta,e.states)
 assert(e.commands[5].scSpeed>K.scNominalKmh,'incident off the track: free')
 zone.onTrack=true; zone.spline=(1200+K.yellowApproach+e.run.yellowBefore+200)/f.length; Incidents.safety(t,e.commands,e.run,f,e.delta,e.states)
 assert(e.commands[5].scSpeed>K.scNominalKmh,'zone beyond the approach: free')
 t.zoneCount=count0
end
-- Regroupement : une voiture hors piste ou presque arrêtée ne retient pas la voiture de sécurité ; attente bornée.
tests.SC_BUNCH_COUNT_160Y=function()
 local function run(setup)
  local e,f,t=deployed()
  F.place(f,5,1200,100); F.place(f,2,1150,100); F.place(f,3,6000,100); setup(f.cars[3],t.cars[3])
  F.tick(e,f,K.scMinOut+e.run.neutralizationHold+5)
  return t.safetyPhase,e
 end
 assert(run(function() end)=='out','car far away at speed: it waits')
 local phase,e=run(function(a) a.offtrack=true end)
 assert(phase=='in' and count(e,'peloton non regroupe')==0,'car off the track: not counted, in this lap')
 assert(run(function(a) a.kmh=12; a.speed=12/3.6 end)=='in','car crawling under the obstacle speed: not counted')
 assert(K.scMinOut+K.scBunchMax<K.neutralMax,'bounded wait under the limit of any neutralisation')
end
-- Délai maximal de la neutralisation, voiture de sécurité en piste : elle rentre d'abord, le vert vient à son entrée
-- dans la voie des stands.
tests.SC_NEUTRAL_MAX_160Y=function()
 local e,f,t=deployed()
 F.place(f,5,1200,100); F.place(f,2,1150,100); F.place(f,3,6000,100); F.tick(e,f,0.2)
 t.neutralSince=e.time-K.neutralMax-1; F.tick(e,f,0.2)
 assert(t.neutral and t.safetyPhase=='in' and count(e,'voiture de securite: rentre ce tour')==1,'limit reached with the Safety Car on track: in this lap, still neutralised ('..t.safetyPhase..')')
 assert(count(e,'neutralisation levee: delai maximal')==0,'no green with the Safety Car on track')
 f.cars[5].pit=true; F.tick(e,f,0.2)
 assert(not t.neutral and count(e,'drapeau vert: voiture de securite aux stands')==1 and math.abs(t.neutralEnd-e.time)<1,'green once it is in the pit lane')
end
-- Appelée puis neutralisation levée avant sa sortie : dit au journal.
tests.SC_RECALLED_160Y=function()
 local e,f=F.scene('C',5); C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; E.changed(e)
 e.g.safetyCarModel='car_5'; F.place(f,5,0,0); f.cars[5].pit=true; f.cars[5].inPitBox=true
 f.cars[1].pit=true; f.cars[1].inPitBox=true
 F.place(f,2,1000,120); F.place(f,3,900,120); F.place(f,4,6000,0)
 local t=e.incidents
 for _=1,900 do F.tick(e,f,0.1); if t.safetyPhase=='call' then break end end
 assert(t.neutral and t.safetyPhase=='call','called')
 t.neutralSince=e.time-K.neutralMax-1; F.tick(e,f,0.2)
 assert(not t.neutral and count(e,'voiture de securite: rappelee avant sa sortie (neutralisation levee)')==1,'recalled: one line')
 assert(J.english('voiture de securite: rappelee avant sa sortie (neutralisation levee)')=='Safety Car: recalled before going out (neutralisation lifted)')
end
-- Rattrapage : enveloppe de freinage de K.scQueueGap à K.scWatch m derrière la voiture de sécurité.
tests.SC_CATCH_ENVELOPE_160Y=function()
 local e,f,t=deployed()
 F.place(f,5,1200,80); F.place(f,2,1200-150,160); F.place(f,3,900,120); F.tick(e,f,0.2)
 local half=(f.cars[2].length+f.cars[5].length)*0.5
 local gap=150-half
 local v=80/3.6
 local expected=math.sqrt(v*v+2*e.run.yellowDecel*(gap-K.queueKeep))*3.6
 local cap=Incidents.cap(t,f,2,e.run,e.delta,e.states,0)
 assert(math.abs(cap-expected)<0.5 and cap<K.scNominalKmh+K.scCatchUp,'150 m behind a Safety Car at 80 km/h: braking envelope ('..cap..' for '..expected..')')
 F.place(f,2,1200-(K.scWatch+half+20),160); F.tick(e,f,0.1)
 assert(math.abs(Incidents.cap(t,f,2,e.run,e.delta,e.states,0)-(K.scNominalKmh+K.scCatchUp))<1e-6,'beyond K.scWatch: the catch-up pace')
 F.place(f,2,1200-(half+30),100); F.tick(e,f,0.1)
 assert(math.abs(Incidents.cap(t,f,2,e.run,e.delta,e.states,0)-(80+(30-K.queueKeep)*K.queueClose))<1e-6,'inside K.scQueueGap: the queue rule as before')
end
-- Place à rendre : jamais sous K.scGiveFloor km/h ; voiture de sécurité retenue juste derrière : place laissée.
tests.SC_GIVE_BACK_BOUNDED_160Y=function()
 local e,f,t=deployed()
 F.place(f,5,1200,100); F.place(f,2,1150,100); F.tick(e,f,0.3)
 f.cars[2].lx=1; f.cars[2].lz=0; F.place(f,2,1210,130); F.tick(e,f,0.1)
 assert(t.cars[2].scPassed,'precondition: the Safety Car was passed')
 F.place(f,5,1200,50); F.tick(e,f,0.1)
 assert(Incidents.cap(t,f,2,e.run,e.delta,e.states,0)==K.scGiveFloor,'place to give back: never under K.scGiveFloor ('..Incidents.cap(t,f,2,e.run,e.delta,e.states,0)..')')
 F.tick(e,f,K.scGiveStuck-1); assert(t.cars[2].scPassed,'held up for less than K.scGiveStuck s: still to give back')
 F.tick(e,f,1.5)
 assert(not t.cars[2].scPassed and count(e,'voiture de securite: retenue derriere Driver_2 qui l a doublee, place laissee')==1,'Safety Car held up right behind it: place left, one line')
 assert(Incidents.cap(t,f,2,e.run,e.delta,e.states,0)>K.scGiveFloor,'no give-back limit any more')
 -- Voiture de sécurité à son allure derrière elle : la place reste à rendre.
 local e2,f2,t2=deployed()
 F.place(f2,5,1200,100); F.place(f2,2,1150,100); F.tick(e2,f2,0.3)
 f2.cars[2].lx=1; f2.cars[2].lz=0; F.place(f2,2,1210,130); F.tick(e2,f2,K.scGiveStuck+2)
 assert(t2.cars[2].scPassed,'Safety Car at its pace: the place is still to give back')
end
-- Joueur sous voiture de sécurité en piste : régime « sc » ; voiture appelée : « scCall » (référence FCY).
tests.SC_PLAYER_DELTA_KIND_160Y=function()
 local e,f,t=deployed()
 f.cars[1].pit=false; f.cars[1].inPitBox=false; F.place(f,1,300,100); F.tick(e,f,0.5)
 assert(e.delta.course.kind=='sc','Safety Car on track: regime sc ('..tostring(e.delta.course.kind)..')')
end
-- Course à Zandvoort sur le lot 4 (18 tentatives en 17 minutes, 45 départs « sans place ») : trajectoire au bord de la
-- piste qui la traverse dans les 2 s : aucun côté n'a la place maintenant, la tentative part du côté qui s'ouvre ;
-- aucun côté ne s'ouvre : pas de tentative, raison comptée une fois ; ligne droite trop courte : pas de tentative.
tests.PASS_SIDE_THAT_OPENS_160Y=function()
 local function run(l1,r1,l2,r2,point)
  local e,f=scene('C',3,function(p) p.startDelay=0; p.startRelax=0; p.laneBiasEnabled=false end)
  F.place(f,1,-5000,100)
  local a=f.cars[2]; a.leftWidth=1.5; a.rightWidth=8.5; a.aheadFixed=true; a.leftAhead=l1; a.rightAhead=r1; a.leftAhead2=l2; a.rightAhead2=r2
  if point then e.fl.count=1; e.fl.points[1]=point/f.length end
  local s=e.states[2]; local t=0
  while t<4 do F.front(e,f,15,35); F.tick(e,f,1/60); t=t+1/60; if F.passing(s.state) then break end end
  return F.passing(s.state),e,s
 end
 local seen,e,s=run(5,5,8.5,1.5,600)
 assert(seen and s.targetSide==-1 and e.stats.passSoonRoom==1,'the left side opens within 2 s, braking point far: attempt on the left ('..tostring(s.targetSide)..')')
 assert((e.stats.refRoom or 0)==0,'nothing refused')
 -- Finition 1.61 (relecture) : aucun point de freinage connu : la garde ne peut pas juger, règle d'avant (pas de départ).
 seen,e=run(5,5,8.5,1.5)
 assert(not seen and (e.stats.passSoonRoom or 0)==0 and e.stats.refRoom==1,'no braking point known: no start on the side that opens')
 -- Braking point known and far (as after a first lap): only the « closes again in between » rule refuses.
 seen,e=run(8.5,1.5,1.5,8.5,600)
 assert(not seen and e.stats.refRoom==1 and (e.stats.passSoonRoom or 0)==0,'the wide side closes within 1 s and the other is closed again at 2 s (esses): no attempt, counted once ('..tostring(e.stats.refRoom)..')')
 seen,e=run(5,5,8.5,1.5,10)
 assert(not seen and e.stats.refShort==1,'braking point 10 m ahead: straight too short, counted once')
 -- Trajectoire au milieu : la règle d'avant, aucun départ « du côté qui s'ouvre ».
 local n,g=scene('C',3,function(p) p.startDelay=0; p.startRelax=0; p.laneBiasEnabled=false end)
 F.place(g,1,-5000,100); local t=0
 while t<4 do F.front(n,g,15,35); F.tick(n,g,1/60); t=t+1/60; if F.passing(n.states[2].state) then break end end
 assert(F.passing(n.states[2].state) and (n.stats.passSoonRoom or 0)==0,'line in the middle of the track: as before')
end
-- Départs refusés : une fois par raison et par cible ; remis à zéro quand une tentative part.
tests.PASS_REFUSALS_COUNTED_160Y=function()
 local D=require('src/director')
 local e=scene('C',3)
 local s=e.states[2]
 D.refused(e,s,3,'room'); D.refused(e,s,3,'room'); D.refused(e,s,3,'suspended'); D.refused(e,s,1,'room')
 assert(e.stats.refRoom==2 and e.stats.refSusp==1,'once per reason and target')
 local Journal=require('src/journal')
 assert(Journal.english('departs de depassement refuses : pas de place 2, ligne droite trop courte 0, paire suspendue 1'):find('pass starts refused: no room 2, straight too short 0, pair suspended 1',1,true),Journal.english('departs de depassement refuses : pas de place 2, ligne droite trop courte 0, paire suspendue 1'))
 -- Paire suspendue : comptée.
 local n,g=scene('C',3,function(p) p.startDelay=0; p.startRelax=0 end)
 F.place(g,1,-5000,100)
 local z=n.states[2]; local t=0
 while t<2 do F.front(n,g,15,35); z.passIgnore=3; z.passIgnoreUntil=n.time+100; z.passIgnoreCount=K.passIgnoreStrict; z.passIgnoreAt=n.time; F.tick(n,g,1/60); t=t+1/60 end
 assert(not F.passing(z.state) and n.stats.refSusp==1,'suspended pair: no attempt, counted once ('..tostring(n.stats.refSusp)..')')
end
return tests
