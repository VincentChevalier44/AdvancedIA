-- Beta 1.50 (Monza, 5 novembre, 11:23, 25 voitures) : au départ, une IA devant levait le pied en pleine ligne droite (le
-- joueur à fond derrière la percutait) ; la voiture de sécurité ne quittait jamais son emplacement (garée sans pilote) ;
-- annonces du pont pour SpotterEnginer ; corrections 1.49 (composés du joueur, rappel des stands verrouillé). Chargé par
-- tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local A=require('src/applier')
local FirstLap=require('src/firstlap')
local Penalties=require('src/penalties')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function careful(n) local e,f=F.scene('C',n); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,1/60); assert(FirstLap.arm(e,f,e.time,'relance')); return e,f end
-- Ligne droite du premier tour : voiture 2 à 150 km/h, voiture 3 devant (à kmhAhead), voiture 4 derrière (à kmhBehind).
local function straight(ahead,kmhAhead,behind,kmhBehind,narrow,pedal)
 local e,f=careful(4)
 F.place(f,1,-3000,100); F.place(f,2,0,150); F.place(f,3,ahead,kmhAhead); F.place(f,4,behind or -3500,kmhBehind or 100)
 if narrow then f.cars[2].leftWidth=2; f.cars[2].rightWidth=2 end
 -- Freinage pour un virage : point de freinage appris juste devant.
 if pedal then e.fl.points[1]=(40/f.length)%1; e.fl.count=1 end
 for i=2,4 do e.states[i].nextPerception=0 end
 for _=1,30 do if pedal then f.cars[2].brake=math.max(pedal,e.commands[2].brake or 0) end; F.tick(e,f,1/60) end
 return e.commands[2],e
end
tests.FIRST_LAP_STRAIGHT_150=function()
 -- Approche modérée (+50 km/h) à 1,1 s : pied tenu, compté ; pas de prudence d'écart en temps en ligne droite.
 local cmd,e=straight(20,100)
 assert(cmd.brake==0 and (cmd.throttleLimit or 1)>=1-1e-9 and (e.stats.flHold or 0)>=1,'1.1 s on a straight: foot kept down, counted')
 assert(math.abs((e.states[2].flFactor or 1)-1)<1e-6,'no time-gap caution on the straight')
 -- 0,55 s, couloir libre : pied tenu ; piste étroite : levée dosée.
 cmd=straight(12,100); assert(cmd.brake==0 and (cmd.throttleLimit or 1)>=1-1e-9,'free lane: foot kept down')
 -- Ni prudence de suivi, ni prudence du radar en ligne droite (aspiration à 12 m, même allure, 6 s) : même prudence que
 -- sans voiture devant.
 local function settled(ahead)
  local e3,f3=careful(4); F.place(f3,1,-3000,100); F.place(f3,4,-3500,100)
  for i=2,4 do e3.states[i].nextPerception=0 end
  for _=1,360 do F.place(f3,2,0,150); F.place(f3,3,ahead,150); F.tick(e3,f3,1/60) end
  return e3.commands[2].caution
 end
 local near,far=settled(12),settled(400); assert(math.abs(near-far)<1e-6,'no follow caution on the straight ('..near..' vs '..far..')')
 cmd=straight(12,100,nil,nil,true); assert(cmd.brake==0 and cmd.throttleLimit<1 and cmd.throttleLimit>K.radarStartLift,'no lane: graded lift')
 cmd=straight(15,100,nil,nil,true); assert(cmd.brake==0 and (cmd.throttleLimit or 1)>=1-1e-9,'no lane, 0.76 s: foot kept down (beyond K.radarStraightTTC s)')
 -- Voiture de derrière plus près de son contact que soi du sien (4 m à +50 km/h) : jamais de levée, jamais de frein.
 cmd,e=straight(12,100,-8.4,200,true); assert(cmd.brake==0 and (cmd.throttleLimit or 1)>=1-1e-9 and (e.stats.flPushed or 0)>=1,'pushed from behind: foot kept down')
 cmd=straight(8.6,100,-8.4,200,true); assert(cmd.brake==0,'pushed from behind, even a last resort brake is not applied')
 -- Dernier recours (0,3 s), personne de pressé derrière : freinage du radar comme avant.
 cmd=straight(8.6,100,nil,nil,true); assert(cmd.brake>K.radarStartBrakeMax,'last resort: radar brake')
 -- Vrai obstacle (approche de 130 km/h) : comportement d'avant (levée de pied du premier tour).
 cmd=straight(40,20,nil,nil,true); assert(cmd.throttleLimit and cmd.throttleLimit<=K.radarStartLift+1e-9,'real obstacle: previous behaviour')
 -- Pilote qui freine (pas une ligne droite) : frein léger comme avant.
 cmd=straight(12,100,nil,nil,true,0.6); assert(cmd.brake>0 and cmd.brake<=K.radarStartBrakeMax+1e-9,'braking: light brake as before')
 -- Point de freinage appris à moins de K.firstLapAnticipate s : plus une ligne droite (anticipation inchangée).
 local e2,f2=careful(4); F.place(f2,1,-3000,100); F.place(f2,2,0,150); F.place(f2,3,12,100); f2.cars[2].leftWidth=2; f2.cars[2].rightWidth=2
 e2.fl.points[1]=(40/f2.length)%1; e2.fl.count=1; for i=2,4 do e2.states[i].nextPerception=0 end
 for _=1,30 do F.tick(e2,f2,1/60) end
 -- Beta 1.59 : peloton (+50 km/h) : levée dosée selon le temps au contact (vrai obstacle : levée franche, plus haut).
 assert(e2.commands[2].throttleLimit and e2.commands[2].throttleLimit<1 and e2.commands[2].throttleLimit>=K.radarStartLift-1e-9,'before a learnt braking point: graded lift')
end
-- Reprise du départ réel (Borja Carrera, 232,4 s) : départ lancé, IA à 10 m derrière une voiture plus lente de 41 km/h,
-- joueur à fond à 6 m derrière elle : l'IA ne lève jamais le pied (le choc passait à l'arrière).
tests.START_REPLAY_PUSHED_150=function()
 local e,f=careful(4)
 F.place(f,3,10+4.4,120); F.place(f,2,0,161); F.place(f,1,-(6+4.4),190); F.place(f,4,-3000,100)
 f.cars[2].leftWidth=2; f.cars[2].rightWidth=2
 for i=2,4 do e.states[i].nextPerception=0 end
 for _=1,20 do F.tick(e,f,1/60) end
 local cmd=e.commands[2]
 assert(cmd.brake==0 and (cmd.throttleLimit or 1)>=1-1e-9,'pushed by the player at full throttle: no lift, no brake')
 assert((e.startHold or 0)>=1 and count(e,'radar avant: ')==0,'held and not logged as a radar event')
 -- Sous K.radarStraightTTC s sans couloir (5 m à +41 km/h), joueur à 3 m à +71 km/h : ni levée ni frein.
 local e3,f3=careful(4)
 F.place(f3,3,5+4.4,120); F.place(f3,2,0,161); F.place(f3,1,-(3+4.4),232); F.place(f3,4,-3000,100)
 f3.cars[2].leftWidth=2; f3.cars[2].rightWidth=2
 for i=2,4 do e3.states[i].nextPerception=0 end
 for _=1,6 do F.tick(e3,f3,1/60) end
 assert(e3.commands[2].brake==0 and (e3.commands[2].throttleLimit or 1)>=1-1e-9,'pushed under 0.6 s, no lane: foot kept down')
 -- L'IA d'AC freine elle-même pour suivre : toujours ni levée ni frein de l'app.
 local e2,f2=careful(4)
 F.place(f2,3,10+4.4,120); F.place(f2,2,0,161); F.place(f2,1,-(6+4.4),190); F.place(f2,4,-3000,100)
 f2.cars[2].leftWidth=2; f2.cars[2].rightWidth=2
 for i=2,4 do e2.states[i].nextPerception=0 end
 -- Voisines perçues d'abord (sans elles, le freinage de la voiture 2 serait appris comme un point de freinage libre).
 for _=1,2 do F.tick(e2,f2,1/60) end
 assert(e2.fl.count==0,'no braking point yet')
 for _=1,20 do f2.cars[2].brake=math.max(0.4,e2.commands[2].brake or 0); F.tick(e2,f2,1/60) end
 assert(e2.fl.count==0,'a follow brake is never a braking point')
 assert(e2.commands[2].brake==0 and (e2.commands[2].throttleLimit or 1)>=1-1e-9,'AC AI braking to follow, pushed by the player: no app lift or brake')
end
-- Départ réel du 5 novembre, 13:09 (interim 2 en jeu, 25 voitures, F1) : IA qui freine elle-même pour suivre, suiveur
-- à 4 m à la même allure ; levées de pied à 8 m / +25 km/h (180,3 s), à 6 m / +18 km/h 3 s après le départ (166,9 s),
-- derrière le joueur à 3 m / +13 km/h (182,5 s). Jamais de levée de pied ; la raison d'une levée est dite au journal.
local function real(ahead,sa,behind,since,playerAhead,narrow)
 local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,1/60)
 e.startedAt=e.time-since; assert(FirstLap.arm(e,f,e.time,'depart'))
 local front=playerAhead and 1 or 3
 F.place(f,front,ahead+4.4,180-sa); F.place(f,2,0,180); F.place(f,4,-(behind+4.4),180)
 if not playerAhead then F.place(f,1,-3000,100) else F.place(f,3,-3000,100) end
 if narrow then f.cars[2].leftWidth=2; f.cars[2].rightWidth=2 end
 for i=2,4 do e.states[i].nextPerception=0 end
 for _=1,2 do F.tick(e,f,1/60) end
 for _=1,20 do f.cars[2].brake=math.max(0.3,e.commands[2].brake or 0); F.tick(e,f,1/60) end
 return e.commands[2],e
end
tests.START_REAL_1309_150=function()
 for _,case in ipairs({{8,25,4,16},{6,18,4,3},{9,26,4,17},{6,22,5,18}}) do
  local cmd,e=real(case[1],case[2],case[3],case[4])
  assert(cmd.brake==0 and (cmd.throttleLimit or 1)>=1-1e-9,string.format('AI braking to follow, %d m +%d km/h, follower %d m, %d s after the start: foot kept down',case[1],case[2],case[3],case[4]))
  assert(count(e,'radar avant: ')==0,'not a radar event')
 end
 local cmd=real(3,13,4,18,true); assert(cmd.brake==0 and (cmd.throttleLimit or 1)>=1-1e-9,'behind the player, 3 m +13 km/h: foot kept down')
 cmd=real(10,41,4,30,false,true); assert(cmd.brake==0 and (cmd.throttleLimit or 1)>=1-1e-9,'after the launch, first lap, braking to follow, 0.88 s, no lane: foot kept down')
 -- Levée dosée (piste étroite, 0,5 s) : raison au journal.
 local _,e=real(7,50,30,18,false,true)
 assert(count(e,'(contact 0.5 s, aucun couloir libre)')==1,'lift reason logged')
 -- Approche d'un point de freinage appris : anticipation comme avant, raison au journal.
 local e2,f2=F.scene('C',4); C.preset('Course','C',e2.profiles.C); E.changed(e2); F.tick(e2,f2,1/60)
 e2.startedAt=e2.time-30; assert(FirstLap.arm(e2,f2,e2.time,'depart'))
 F.place(f2,3,12,130); F.place(f2,2,0,180); F.place(f2,1,-3000,100); F.place(f2,4,-3000,100)
 e2.fl.points[1]=(60/f2.length)%1; e2.fl.count=1; for i=2,4 do e2.states[i].nextPerception=0 end
 for _=1,30 do F.tick(e2,f2,1/60) end
 assert(count(e2,'(anticipation du freinage)')==1,'anticipation reason logged')
end
-- Stratégie corrigée pendant la course : avertissement levé, annonce « pitPlanOk » une fois.
tests.PIT_PLAN_OK_150=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); C.applyRules('F1',e.profiles); E.changed(e)
 f.sessionLaps=10; f.leaderLaps=3
 local a=f.cars[1]; a.compoundIndex=0; a.tyresKnown=true; a.tyreNames={[0]='SS',[1]='S',[2]='M'}; a.dryList={0,1,2}; a.dryCompounds={[0]=true,[1]=true,[2]=true}
 local spinner={name='TYRES',type='compound',min=0,max=2,value=0,values={0,0,0}}
 e.pitSpinners=function() return {spinner},0 end
 F.tick(e,f,K.pitPlanPeriod+0.5)
 assert(e.pitplan.state=='same' and e.incidents.playerPlanNotice and e.incidents.messageKind=='pitPlanSame','same compound: warned')
 spinner.value=1; F.tick(e,f,K.pitPlanPeriod+0.1)
 local t=e.incidents
 assert(e.pitplan.state=='ok' and t.messageKind=='pitPlanOk' and t.messageValue==0 and t.messageExtra==1,'fixed: announced (fitted SS 0, planned S 1)')
 assert(not t.playerPlanNotice,'warning cleared')
 local Panel=require('src/panel'); local L=require('src/lang')
 assert(Panel.pitAnnounce(t,'pitPlanOk')==string.format(L.pitHint.planFixed,'S'),'announcement text')
 local id=t.messageId; F.tick(e,f,K.pitPlanPeriod*2); assert(t.messageId==id,'announced once')
 assert(L.messages.pitPlanOk and require('src/lang_en').messages.pitPlanOk and require('src/lang_en').pitHint.planFixed,'texts')
end
-- Composés du joueur lus comme ceux des IA (journal, overlay, stratégie des stands).
tests.PLAYER_TYRES_150=function()
 local host=require('tests/host').create(true)
 local Snapshot=require('src/snapshot'); local s=Snapshot.new()
 host.tyreCatalog[0]={{short='SS',name='Slick SuperSoft'},{short='S',name='Slick Soft'},{short='M',name='Slick Medium'}}
 Snapshot.read(s,1/60,10)
 local a=s.cars[1]
 assert(a.player and a.tyresKnown and a.tyreNames[0]=='SS' and a.tyreNames[1]=='S' and a.tyreNames[2]=='M','player compounds read: '..tostring(a.tyreNames[0]))
 assert(a.dryCompounds[0] and a.dryCompounds[2] and #a.dryList==3,'player dry compounds listed')
end
-- Stratégie des stands lue après des redémarrages de session avant le vrai départ (journal du 5 novembre, 11:23).
tests.PIT_PLAN_RESTARTS_150=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); C.applyRules('F1',e.profiles); E.changed(e)
 f.sessionLaps=10; f.leaderLaps=3
 local a=f.cars[1]; a.compoundIndex=0; a.tyresKnown=true; a.tyreNames={[0]='SS',[1]='S',[2]='M'}; a.dryList={0,1,2}; a.dryCompounds={[0]=true,[1]=true,[2]=true}
 local reads=0
 e.pitSpinners=function() reads=reads+1; return {{name='TYRES',type='compound',min=0,max=2,value=0,values={0,0,0}}},0 end
 for k=1,3 do f.session=k; f.started=false; F.tick(e,f,1); f.started=true; F.tick(e,f,1) end
 F.tick(e,f,K.pitPlanPeriod+0.5)
 assert(reads>=1 and count(e,'strategie des stands (Quick Pitstop): prereglage 1, pneu monte 0 SS')>=1,'menu dumped after the restarts: '..reads)
 assert(e.pitplan.state=='same','same compound planned: warned')
end
-- Rappel « changez de composé » verrouillé : un freinage dans la fenêtre ne l'éteint pas, une seule annonce ; point passé
-- sans entrer : fini pour ce tour ; tour suivant : de nouveau, une fois.
tests.PIT_HINT_LATCH_150=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); C.applyRules('F1',e.profiles); E.changed(e)
 f.sessionLaps=10; f.leaderLaps=5
 local a=f.cars[1]; a.compoundIndex=0; a.tyresKnown=true; a.tyreNames={[0]='SS',[1]='S',[2]='M'}; a.dryList={0,1,2}; a.dryCompounds={[0]=true,[1]=true,[2]=true}
 F.tick(e,f,0.5)
 local b=f.cars[2]; F.place(f,2,3000,150); F.tick(e,f,0.2); b.pit=true; F.tick(e,f,0.2); b.pit=false; F.place(f,2,6000,150)
 assert(math.abs(e.pits.entrySpline-0.3)<0.01,'pit entry learnt')
 F.place(f,1,2100,180); F.tick(e,f,0.5); assert(e.incidents.playerPitHint,'18 s from the entry at 180 km/h: hint')
 local id=e.incidents.messageId; local kinds=0
 -- Freinage fort : 60 km/h à 400 m de l'entrée (24 s) : reste montré, aucune nouvelle annonce.
 for z=2150,2600,50 do F.place(f,1,z,60); F.tick(e,f,0.2); assert(e.incidents.playerPitHint,'latched while braking at '..z); if e.incidents.messageKind=='pitCompound' and e.incidents.messageId~=id then kinds=kinds+1 end end
 assert(kinds==0 and e.incidents.messageId==id,'announced once per approach')
 F.place(f,1,3050,200); F.tick(e,f,0.2); assert(not e.incidents.playerPitHint,'entry passed without pitting: over for this lap')
 F.place(f,1,4000,200); F.tick(e,f,0.5); assert(not e.incidents.playerPitHint,'after the entry: never again this lap')
end
-- Voiture de sécurité : libérée à son emplacement, sortie par la voie des stands, en piste devant la première voiture,
-- file formée ; annonces du pont.
local function scScene()
 local e,f=F.scene('C',5); e.profiles.C.neutralization='sc'; e.g.safetyCarModel='sc_car'; E.changed(e)
 f.cars[5].id='sc_car'
 for i=2,4 do F.place(f,i,(i-2)*400,150) end
 F.place(f,1,-2000,150)
 F.place(f,5,7000,0); f.cars[5].pit=true; f.cars[5].inPitBox=true
 F.tick(e,f,1)
 F.place(f,4,5000,0); F.tick(e,f,18)
 assert(e.incidents.safetyPhase=='call','called on the major incident')
 return e,f
end
tests.SC_EXIT_150=function()
 local e,f=scScene(); local t=e.incidents
 F.tick(e,f,K.scCallTime)
 assert(t.safetyPhase=='exit' and not e.commands[5].scPark and e.commands[5].scRelease and count(e,'liberee, sort par la voie des stands')==1,'released in its box, leaves by the pit lane')
 assert(e.commands[5].place==nil or e.commands[5].place<0,'never placed')
 F.tick(e,f,2); assert(e.states[2].yellow,'field under the FCY delta while it is in the pit lane')
 f.cars[5].inPitBox=false; F.tick(e,f,0.5); assert(count(e,'voiture de securite: sortie de son stand')==1,'left its box')
 F.tick(e,f,K.scLeaveMax); assert(t.safetyPhase=='exit','driving down the pit lane: no fallback before K.scLaneMax s')
 f.cars[5].pit=false; F.place(f,5,1000,120); F.tick(e,f,0.1)
 assert(t.safetyPhase=='out' and t.safetyLeft and count(e,'voiture de securite: sortie en piste devant')==1,'on track ahead of the first car')
 assert(t.messageKind=='scOut' and t.messageValue==2 and math.abs(t.messageExtra-600)<1,'bridge: scOut, car right behind (0-based index 2), gap')
 -- File formée : première voiture à moins de K.scLeadGap m, une seule annonce.
 F.place(f,5,1000,120); F.place(f,3,1000-K.scLeadGap+20,120); F.tick(e,f,0.1)
 assert(t.messageKind=='scLeading' and t.messageValue==2 and count(e,'en tete de la file')==1,'queue formed: announced')
 local id=t.messageId; F.tick(e,f,1); assert(t.messageId==id or t.messageKind~='scLeading','announced once')
end
-- Neutralisation (journal du 5 novembre, 14:57) : joueur en tête, plus lent que le delta des IA, dans une autre file
-- que l'IA qui arrive : l'IA se cale derrière lui, jamais à côté ni devant ; de même derrière la voiture de sécurité.
tests.NEUTRAL_QUEUE_150=function()
 local e,f=F.scene('C',3); e.profiles.C.neutralization='fcy'; E.changed(e)
 local t=e.incidents; t.neutral=true; t.neutralMode='fcy'; t.neutralSince=e.time; t.neutralUntil=e.time+1e6
 F.place(f,1,1030,70,3); F.place(f,2,1000,120,-1); F.place(f,3,6000,120)
 e.states[2].nextPerception=0
 for _=1,30 do F.tick(e,f,1/60) end
 local cap=70+(30-4.4-K.queueKeep)*K.queueClose
 assert(e.commands[2].yellowLimit<=cap+1e-6 and e.states[2].neutralQueue==1,'queued behind the player in another lane: '..e.commands[2].yellowLimit)
 -- Joueur à 20 m : limite posée aussitôt (pas de descente progressive).
 F.place(f,1,1020,70,3); F.place(f,2,1000,120,-1); F.tick(e,f,1/60)
 assert(e.commands[2].yellowLimit<=70+K.queueClose*(20-4.4-K.queueKeep)+1e-6,'hard queue: capped at once')
 -- Voiture accidentée : se double.
 t.cars[1].incident=true; F.tick(e,f,1/60); assert(e.states[2].neutralQueue~=1,'a crashed car can be passed')
end
tests.SC_EXIT_FALLBACK_150=function()
 -- Jamais sortie de son emplacement en K.scLeaveMax s : posée en piste, jamais en vue du joueur.
 local e,f=scScene(); local t=e.incidents
 F.place(f,1,2000,150); F.place(f,2,2500,150); f.cars[2].position=1; f.cars[1].position=2; f.cars[3].position=3
 F.tick(e,f,K.scCallTime+0.1); assert(t.safetyPhase=='exit')
 F.tick(e,f,K.scLeaveMax+0.1)
 assert(t.safetyPhase=='place' and count(e,'ne quitte pas son emplacement, posee en piste hors de la vue du joueur')==1,'fallback: placed on track')
 F.tick(e,f,0.1)
 local at=e.commands[5].place
 local pl=f.cars[1]
 assert(at and at>=0,'position command')
 local d=((at-pl.spline)%1)*f.length
 assert(d>=K.scHideAhead-1,'never in sight of the player: '..d)
 -- Pied tenu dans la voie des stands : rien ne bouge avant K.scLaneMax s.
 local e2,f2=scScene(); local t2=e2.incidents
 F.tick(e2,f2,K.scCallTime+0.1); f2.cars[5].inPitBox=false; F.tick(e2,f2,K.scLaneMax+0.5)
 assert(t2.safetyPhase=='place' and count(e2,'restee dans la voie des stands, posee en piste hors de la vue du joueur')==1,'stuck in the pit lane: fallback')
end
tests.SC_EXIT_TIMING_150=function()
 -- Jonction connue : libérée quand le meneur est à moins de K.scExitLead s de la sortie des stands.
 local e,f=scScene(); local t=e.incidents
 e.merge.spline=6000/f.length; f.cars[2].position=1
 F.place(f,2,200,150); F.tick(e,f,K.scCallTime+0.5)
 assert(t.safetyPhase=='call','leader far from the pit exit: kept in its box')
 F.place(f,2,6000-150/3.6*(K.scExitLead-2),150); F.tick(e,f,0.2)
 assert(t.safetyPhase=='exit','leader close to the pit exit: released')
 -- Au plus K.scCallMaxWait s d'appel.
 local e2,f2=scScene(); local t2=e2.incidents
 e2.merge.spline=6000/f2.length; f2.cars[2].position=1; F.place(f2,2,200,0)
 F.tick(e2,f2,K.scCallMaxWait+0.5); assert(t2.safetyPhase=='exit','released after the longest wait')
end
tests.SC_RETURN_HIDDEN_150=function()
 -- Ligne franchie sans rentrer : ramenée à son stand seulement hors de la vue du joueur.
 local e,f=scScene(); local t=e.incidents
 F.tick(e,f,K.scCallTime+0.1); f.cars[5].inPitBox=false; f.cars[5].pit=false; F.place(f,5,1000,120); F.tick(e,f,0.1)
 assert(t.safetyPhase=='out')
 t.safetyPhase='parked'; t.safetyReturnAt=e.time; F.place(f,1,900,150); F.place(f,5,1100,120); F.tick(e,f,0.1)
 assert(t.safetyHide and e.commands[5].scHideWait and e.commands[5].rulePit and e.commands[5].scSpeed<K.unlimitedSpeed,'in sight: drives to the pit entry, not teleported')
 F.place(f,1,-3000,150); F.tick(e,f,0.1)
 assert(not t.safetyHide and not e.commands[5].scHideWait,'out of sight: sent back')
end
tests.SC_RELAUNCH_EXIT_150=function()
 -- Tour de relance : IA retenues jusqu'à K.scExitGap s après la sortie de la voiture de sécurité de son emplacement.
 local e,f=F.scene('C',6); C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagHold=20; e.g.safetyCarModel='car_6'; E.changed(e)
 F.place(f,6,0,0); f.cars[6].pit=true; f.cars[6].inPitBox=true
 F.block(f,{3,4,5},600); F.place(f,2,3000,120)
 for i=1,5 do f.cars[i].position=i end
 F.tick(e,f,K.redIncidentStill+1); local t=e.incidents; assert(t.red and t.safety==6)
 for i=2,5 do local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0; F.place(f,i,100+i*20,0); a.pit=true; a.inPitBox=true end
 f.cars[1].pit=true; F.place(f,1,100,0); f.cars[1].pit=true; f.cars[1].inPitBox=true
 for _=1,200 do if not t.red then break end; F.tick(e,f,0.5) end
 assert(t.relaunch and t.safetyPhase=='exit' and e.commands[6].scRelease,'relaunch: it leaves first')
 F.tick(e,f,K.scLeaveMax-2); assert(e.commands[2].pitHold and t.restartState=='wait','field and player wait while it is still in its box')
 f.cars[6].inPitBox=false; F.tick(e,f,K.scExitGap-1); assert(e.commands[2].pitHold and t.restartState=='wait','just left: still held')
 F.tick(e,f,1.5); assert(t.safetyPhase=='exit' and t.restartState=='go','then the player (P1) goes')
 f.cars[1].inPitBox=false; F.place(f,1,300,60); f.cars[1].pit=true
 for _=1,40 do F.tick(e,f,0.25); if not e.commands[2].pitHold then break end end
 assert(not e.commands[2].pitHold,'released behind them, in the frozen order')
end
tests.SC_HOLD_150=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C'); local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false end
 local cmd=e.commands[3]; cmd.scPark=true; cmd.scSpeed=K.unlimitedSpeed; cmd.parkReason='sc'
 A.apply(a,f,e.commands,e.g,1); assert(host.teleports==1,'brought back to its pit')
 f.cars[3].pit=true; f.cars[3].inPitBox=true; A.apply(a,f,e.commands,e.g,1.2)
 assert(host.parked[2]==nil and host.startDelays[2]==K.scHoldTime and host.stops[2]==K.scHoldStop,'held by AC own wait, never parked without a driver')
 host.stops[2]=nil; A.apply(a,f,e.commands,e.g,1.5); assert(host.stops[2]==nil,'pulses spaced')
 A.apply(a,f,e.commands,e.g,2.3); assert(host.stops[2]==K.scHoldStop,'hold renewed')
 -- Libérée : attente levée, réveillée, aucune mise sans pilote à lever.
 cmd.scPark=false; cmd.scRelease=true; A.apply(a,f,e.commands,e.g,3)
 assert(host.startDelays[2]==0 and host.stops[2]==0 and (host.awakes[2] or 0)>=1 and host.parked[2]==nil,'released: leaves by itself')
 -- Sorties malgré l'attente : garée sans pilote après K.scEscapeMax.
 cmd.scRelease=false; cmd.scPark=true
 for k=1,C.K.scEscapeMax do
  f.cars[3].pit=true; f.cars[3].inPitBox=true; A.apply(a,f,e.commands,e.g,4+k*10)
  f.cars[3].inPitBox=false; f.cars[3].pit=false; host.cars[2].isInPit=false; A.apply(a,f,e.commands,e.g,4.5+k*10)
 end
 f.cars[3].pit=true; f.cars[3].inPitBox=true; A.apply(a,f,e.commands,e.g,40)
 assert(host.parked[2]==true,'fallback after repeated escapes: parked without a driver')
 -- Restitution : attente levée.
 local host2=require('tests/host').create(true); local e2,f2=F.scene('C'); local b=A.new(); assert(A.access(b))
 for _,c in ipairs(e2.commands) do c.active=false end
 local c3=e2.commands[3]; c3.scPark=true; c3.scSpeed=K.unlimitedSpeed; c3.parkReason='sc'; f2.cars[3].pit=true; f2.cars[3].inPitBox=true
 A.apply(b,f2,e2.commands,e2.g,1); assert(b.cars[3].scHeld,'held')
 host2.releasing=true; A.restore(b,f2,false,2,true); host2.releasing=false
 assert(host2.startDelays[2]==0 and host2.stops[2]==0 and not b.cars[3].scHeld,'handed back on unload')
end
tests.RESTART_ANNOUNCE_150=function()
 local Incidents=require('src/incidents')
 local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); E.changed(e)
 local t=e.incidents
 t.redOrder={3,1,2,4}; t.redRank={[3]=1,[1]=2,[2]=3,[4]=4}; t.redOrderN=4
 t.red=true; t.redSince=e.time; t.redMax=1e4
 F.tick(e,f,0.5)
 assert(t.restartState=='pit' and t.messageKind=='restartPlace' and t.messageValue==2 and t.messageExtra==2,'red flag: P2 behind car 3 (0-based 2)')
 local L=require('src/lang')
 assert(L.messages.restartPlace and L.messages.restartRetake and L.messages.scOut and L.messages.scLeading and L.messages.scOutAlone and L.messages.restartPlaceSc,'texts')
 local LE=require('src/lang_en')
 for _,k in ipairs({'restartPlace','restartRetake','scOut','scLeading','scOutAlone','restartPlaceSc'}) do assert(LE.messages[k],k) end
 assert(Incidents.reset~=nil)
end
-- Beta 1.50 : IA qui double sous neutralisation (journal du 5 novembre, 14:57) : en plus du pied levé et de
-- l'infraction, elle rend la place (sous l'allure de la voiture doublée, jusqu'à ce qu'elle repasse ; au plus
-- K.aiGiveBackMax s). Zone jaune locale : pas de place due.
local function neutralScene()
 local e,f=F.scene('C',3); e.profiles.C.neutralization='fcy'; e.profiles.C.aiPenalties=true; E.changed(e)
 local t=e.incidents; t.neutral=true; t.neutralMode='fcy'; t.neutralSince=e.time; t.neutralUntil=e.time+1e6
 F.place(f,1,1000,70); F.place(f,2,960,70); F.place(f,3,6000,70)
 -- Au-delà de la transition (K.passGiveBack s) : dépassement sanctionné aussitôt.
 for _=1,math.floor((K.passGiveBack+1)*60) do F.place(f,1,1000,70); F.place(f,2,960,70); e.states[2].nextPerception=0; F.tick(e,f,1/60) end
 return e,f
end
tests.NEUTRAL_GIVEBACK_150=function()
 local e,f=neutralScene(); local ai=e.penalties.ai
 -- IA passée devant le joueur sous neutralisation : sanction ET place à rendre.
 F.place(f,1,1000,70); F.place(f,2,1030,120); e.states[2].nextPerception=0; F.tick(e,f,1/60)
 assert((ai.count[2] or 0)==1 and ai.owe[2]==1 and count(e,'rend la place a Driver_1')==1,'illegal pass under FCY: place to give back')
 for _=1,30 do F.place(f,1,1000,70); F.place(f,2,1030,ai.giveFrom[2] and e.commands[2].yellowLimit or 120); F.tick(e,f,1/60) end
 assert(ai.giveBack[2]==1 and e.commands[2].yellowLimit<120-1,'slowing down to let the player through: '..e.commands[2].yellowLimit)
 assert(Penalties.mayPass(e.penalties,1,2,e.time,f.player),'the player may retake the place')
 -- Joueur de nouveau devant : place rendue, plus de limite propre.
 F.place(f,1,1060,70); F.place(f,2,1030,70); e.states[2].nextPerception=0; F.tick(e,f,1/60)
 assert(ai.owe[2]==nil and count(e,'place rendue IA: Driver_2 a Driver_1')==1,'place given back')
 F.tick(e,f,1/60); assert((ai.giveBack[2] or 0)==0,'no more give-back limit')
 -- Jamais rendue : abandonnée au bout de K.aiGiveBackMax s, la sanction reste.
 local e2,f2=neutralScene(); local ai2=e2.penalties.ai
 F.place(f2,1,1000,70); F.place(f2,2,1030,120); e2.states[2].nextPerception=0; F.tick(e2,f2,1/60)
 assert(ai2.owe[2]==1)
 for _=1,math.floor((K.aiGiveBackMax+1)*60) do F.place(f2,1,1000,70); F.place(f2,2,1030,70); F.tick(e2,f2,1/60) end
 assert(ai2.owe[2]==nil and count(e2,'abandonnee (delai depasse)')==1 and (ai2.count[2] or 0)==1,'given up after the longest wait')
 -- Voiture doublée aux stands : abandonnée aussitôt.
 local e3,f3=neutralScene(); local ai3=e3.penalties.ai
 F.place(f3,1,1000,70); F.place(f3,2,1030,120); e3.states[2].nextPerception=0; F.tick(e3,f3,1/60)
 f3.cars[1].pit=true; F.tick(e3,f3,1/60)
 assert(ai3.owe[2]==nil and count(e3,'abandonnee (aux stands)')==1,'passed car in the pits: dropped')
end
-- Journal du 5 novembre, 14:57 (Monza) : joueur en tête, plus lent que l'allure des IA, voiture de sécurité appelée sur
-- deux voitures arrêtées, jamais sortie de son emplacement, posée 800 m devant le joueur ; les IA arrivent derrière lui.
-- Sur toute la séquence : aucune IA ne double le joueur ni la voiture de sécurité, la file se forme derrière le joueur,
-- vert à l'entrée de la voiture de sécurité dans la voie des stands.
tests.REPLAY_1457_150=function()
 local n=8; local e,f=F.scene('C',n); e.profiles.C.neutralization='sc'; e.profiles.C.aiPenalties=true; e.g.safetyCarModel='sc_car'; E.changed(e)
 local sc=n; f.cars[sc].id='sc_car'
 local z,kmh,want={},{},{}
 z[1]=1500; kmh[1]=150
 for i=2,5 do z[i]=1500-(i-1)*60; want[i]=150 end
 z[6]=5000; z[7]=5005
 for i=1,7 do F.place(f,i,z[i],(i==6 or i==7) and 0 or 150,(i%2==0) and 3 or 0); f.cars[i].position=i end
 F.place(f,sc,7000,0); f.cars[sc].pit=true; f.cars[sc].inPitBox=true
 local t=e.incidents
 local placed,green,headOk=false,false,false
 local slowPlayer=90
 local function onTrack(i) return z[i] end
 local scZ=nil
 for frame=1,60*400 do
  -- Joueur : 150 km/h avant la neutralisation, puis plus lent que l'allure des IA.
  if t.neutral then kmh[1]=slowPlayer end
  for i=2,5 do
   local lim=e.commands[i].yellowLimit or K.unlimitedSpeed
   kmh[i]=math.min(want[i],lim<K.unlimitedSpeed and lim or want[i])
  end
  for i=1,5 do z[i]=z[i]+kmh[i]/3.6/60; F.place(f,i,z[i],kmh[i],(i%2==0) and 3 or 0) end
  -- Voitures arrêtées dépannées par l'app (ramenées à leur stand) : retirées de la piste.
  for i=6,7 do if e.commands[i].recover or (e.time-100>60 and t.neutral) then f.cars[i].pit=true end end
  -- Pose de la voiture de sécurité (repli) : commande de position suivie, puis 80 km/h ou son allure.
  local at=e.commands[sc].place
  if not placed and at and at>=0 and t.safetyPhase=='place' then
   scZ=math.floor(z[1]/f.length)*f.length+at*f.length; if scZ<z[1] then scZ=scZ+f.length end
   f.cars[sc].pit=false; f.cars[sc].inPitBox=false; F.place(f,sc,scZ,80); placed=true
  elseif placed and scZ then
   -- Allure réduite tant que la file n'est pas formée (accélère la scène), puis son allure.
   local v=t.safetySlow and 30 or 100
   if t.safetyPhase=='in' and e.time-t.safetySince>5 then f.cars[sc].pit=true end
   if not f.cars[sc].pit then scZ=scZ+v/3.6/60; F.place(f,sc,scZ,v) end
  end
  F.tick(e,f,1/60)
  if t.neutral and placed then
   for i=2,5 do
    if not (z[i]<z[1]-1) then
     local lines={}
     for k=1,e.log.limit do local r=e.log[k]; if r and r.message and (r.message:find('Driver_2',1,true) or r.message:find('joueur',1,true) or r.message:find('neutralisation',1,true)) then lines[#lines+1]=string.format('%.1f %s',r.time or -1,r.message) end end
     error(string.format('AI %d passed the player under the SC (frame %d, %.0f vs %.0f) lim %.1f queue %s mayPass %s phase %s giveBack %s waiting %s retake %s kind %s last %.1f sec %.1f'..string.char(10)..'%s',i,frame,z[i],z[1],e.commands[i].yellowLimit,tostring(e.states[i].neutralQueue),tostring(Penalties.mayPass(e.penalties,i,1,e.time,f.player)),t.safetyPhase,tostring(e.penalties.ai.giveBack[i]),tostring(e.penalties.waiting[i]),tostring(e.penalties.retake[i] and e.penalties.retake[i][1]),tostring(e.penalties.kind),e.penalties.lastAt,e.penalties.seconds,table.concat(lines,string.char(10))))
    end
    if scZ and not f.cars[sc].pit then assert(z[i]<scZ,'AI passed the Safety Car') end
   end
  end
  if count(e,'en tete de la file (Driver_1')==1 then headOk=true end
  if placed and not t.neutral and count(e,'drapeau vert: voiture de securite aux stands')>=1 then green=true; break end
 end
 assert(count(e,'ne quitte pas son emplacement, posee en piste hors de la vue du joueur')==1,'fallback used as in the journal')
 assert(placed,'placed on track')
 assert(headOk,'queue head = the player')
 assert(green,'green flag at the Safety Car pit-in')
 for i=2,5 do assert(z[i]<z[1],'still behind the player at the green flag') end
 assert(count(e,'a double Driver_1')==0,'no illegal pass of the player at all')
end
return tests
