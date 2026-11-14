-- Beta 1.64, lot 4 (course sprint, décision du pilote du 13 novembre) : une course de K.sprintMaxKm km ou moins (tours ×
-- longueur ; course au temps : estimée au meilleur tour du plateau après K.sprintLapsSeen tours) n'a aucun arrêt
-- obligatoire ni changement de composé imposé, dit au départ (journal et message) ; décidée une fois, seulement avant
-- l'ouverture de la fenêtre ; au-delà, distance inconnue, fenêtre de CSP ou règles sans arrêt : rien ne change.
-- Chargé par tests/extended.lua (après tests/review164c).
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Pits=require('src/pits')
local K=C.K
local tests={}

-- Règles F1 (un arrêt, 20-95 %, deux composés secs), course aux tours sur un circuit de length m.
local function race(laps,length)
 local e,f=F.scene('C',3); local p=e.run
 p.mandatoryStops=1; p.pitWindowOpenPct=20; p.pitWindowClosePct=95; p.pitCompoundChange=true; p.redFlagWork=true; p.pitMessage=true; p.pitTyres=true
 f.sessionLaps=laps; f.leaderLaps=0; f.timedRace=false; f.sessionMinutes=0; f.pitWindowStart=0; f.pitWindowEnd=0; f.started=true
 f.length=length or 10000
 for i=1,f.count do f.cars[i].bestLap=0 end
 return e,f,p
end
-- Course au temps de minutes min sur un circuit de length m, au départ (aucun tour bouclé).
local function timed(minutes,length)
 local e,f,p=race(0,length); f.timedRace=true; f.sessionMinutes=minutes; f.left=minutes*60
 for i=1,f.count do f.cars[i].lap=0; f.cars[i].bestLap=0 end
 return e,f,p
end
local function laps(f,lap,best) for i=2,f.count do f.cars[i].lap=lap; f.cars[i].bestLap=best+(i-2)*10 end end
local function ai(f) local list={}; for i=1,f.count do local a=f.cars[i]; if a.valid and a.control and not a.player and not a.safetyCar then list[#list+1]=i end end; return list end
local function has(lines,text) local n=0; for _,l in ipairs(lines) do if l:find(text,1,true) then n=n+1 end end return n>0,n end
local function kinds(said,kind) local n=0; for _,s in ipairs(said) do if s[1]==kind then n=n+1 end end return n end
local function step(t,f,e,p,now,said) Pits.update(t,f,e.commands,p,'C',now,1,said and function(kind,a,b) said[#said+1]={kind,a,b} end or nil,false) end
local function journal(t) local lines={}; t.note=function(level,text) lines[#lines+1]=text end; return lines end

-- Seuil compris : 10 tours de 10 km (100 km) = sprint, décidé sur la grille, dit une fois au départ ; 11 tours (110 km)
-- comme avant ; 2 tours : seulement le sprint ; course déjà mouillée : seulement le sprint ; app rechargée en course.
tests.SPRINT_PATH_FORCED_164=function()
 local e,f,p=race(10); local t=Pits.new(); local lines=journal(t); local said={}
 f.started=false; step(t,f,e,p,100,said)
 assert(t.sprint==true and t.waived and t.state=='off','100 km on the grid: mandatory stop lifted ('..t.state..')')
 assert(#said==0 and not has(lines,'sprint'),'nothing said on the grid')
 f.started=true
 for lap=0,9 do f.leaderLaps=lap; step(t,f,e,p,101+lap,said)
  assert(t.state=='off' and t.total==0 and not t.opened,'lap '..lap..': still lifted, no window')
  for _,i in ipairs(ai(f)) do assert(not e.commands[i].rulePit,'AI '..i..' never called') end
 end
 assert(#said==1 and said[1][1]=='pitSprint' and said[1][2]==100 and said[1][3]==K.sprintMaxKm,'announced once at the start, with the distance')
 local _,n=has(lines,'arret obligatoire leve: course sprint de 100.0 km (10 tours, 100 km au plus)')
 assert(n==1,'journal line once')
 assert(not has(lines,'course trop courte') and not has(lines,'fenetre d arret'),'no short-race or window line')
 -- Arrêt d'une IA en sprint : jamais compté.
 f.leaderLaps=5; f.cars[2].pit=true; f.cars[2].inPitBox=true; step(t,f,e,p,120); f.cars[2].inPitBox=false; step(t,f,e,p,121); f.cars[2].pit=false; step(t,f,e,p,122)
 assert(t.cars[2].stops==1 and t.cars[2].windowStops==0,'stop in a sprint not counted')
 -- 110 km : comme avant (fenêtre ouverte, IA appelées), une ligne « maintenu ».
 local e2,f2,p2=race(11); local t2=Pits.new(); local lines2=journal(t2); local said2={}
 for lap=0,8 do f2.leaderLaps=lap; step(t2,f2,e2,p2,100+lap,said2) end
 assert(t2.sprint==false and not t2.waived and t2.state=='open','110 km: unchanged ('..t2.state..')')
 for _,i in ipairs(ai(f2)) do assert(e2.commands[i].rulePit,'110 km: AI '..i..' called') end
 assert(kinds(said2,'pitSprint')==0 and kinds(said2,'pitOpen')==1,'110 km: window announced, no sprint')
 local _,n2=has(lines2,'arret obligatoire maintenu: course de 110.0 km (plus de 100 km)'); assert(n2==1,'kept line once')
 -- Course très courte (2 tours, 20 km) : seulement le sprint, jamais « course trop courte » en plus.
 local e3,f3,p3=race(2); local t3=Pits.new(); local said3={}; local lines3=journal(t3)
 f3.leaderLaps=1; step(t3,f3,e3,p3,100,said3); step(t3,f3,e3,p3,101,said3)
 assert(#said3==1 and said3[1][1]=='pitSprint' and not has(lines3,'course trop courte') and not t3.shortWaived,'2 laps: sprint only')
 -- Course déjà mouillée à la première image (app rechargée en course) : seulement le sprint, jamais « course mouillée ».
 local e4,f4,p4=race(10); local t4=Pits.new(); t4.wetRace=true; local said4={}; local lines4=journal(t4)
 f4.leaderLaps=5; step(t4,f4,e4,p4,100,said4); step(t4,f4,e4,p4,101,said4)
 assert(#said4==1 and said4[1][1]=='pitSprint' and t4.waived and not has(lines4,'course mouillee'),'wet sprint: sprint only')
 -- Règles GT (42-58 %), 5 tours de 10 km : levé aussi.
 local e5,f5,p5=race(5); p5.pitWindowOpenPct=42; p5.pitWindowClosePct=58; p5.pitCompoundChange=false; local t5=Pits.new()
 f5.leaderLaps=3; step(t5,f5,e5,p5,100); assert(t5.sprint==true and t5.state=='off','GT rules: lifted too')
end

-- Limite exacte : 100,0 km sprint, 100,5 km non.
tests.SPRINT_BOUNDARY_164=function()
 local e,f,p=race(20,5000); local t=Pits.new(); step(t,f,e,p,100)
 assert(t.sprint==true and t.waived,'100.0 km: sprint')
 local e2,f2,p2=race(10,10050); local t2=Pits.new(); local said={}
 step(t2,f2,e2,p2,100,said); f2.leaderLaps=5; step(t2,f2,e2,p2,101,said)
 assert(t2.sprint==false and t2.state=='open' and kinds(said,'pitSprint')==0,'100.5 km: unchanged')
end

-- Distance inconnue (longueur 0), fenêtre de CSP, règles sans arrêt obligatoire : rien ne change.
tests.SPRINT_UNKNOWN_OR_CSP_164=function()
 local e,f,p=race(7,0); local t=Pits.new(); local said={}; local lines=journal(t)
 f.leaderLaps=3; step(t,f,e,p,100,said)
 assert(t.sprint==nil and t.state=='open' and t.opened,'length unknown: window opens as before ('..t.state..')')
 step(t,f,e,p,101,said)
 assert(t.sprint==false and t.sprintKm==-1 and t.state=='open','window opened first: stop kept')
 local _,n=has(lines,'arret obligatoire maintenu: distance inconnue avant l ouverture de la fenetre'); assert(n==1,'kept line once')
 f.length=10000; step(t,f,e,p,102,said)
 assert(t.sprint==false and t.state=='open' and kinds(said,'pitSprint')==0,'length known after the opening: never lifted')
 local e2,f2,p2=race(7); f2.pitWindowStart=100; f2.pitWindowEnd=900; f2.simTime=500; local t2=Pits.new(); local said2={}
 f2.leaderLaps=3; step(t2,f2,e2,p2,100,said2)
 assert(t2.csp and t2.sprint==nil and t2.state=='open' and #said2==1 and said2[1][1]=='pitOpenCsp','CSP window: unchanged')
 -- Sprint décidé (70 km), puis fenêtre déclarée par CSP : la fenêtre de CSP l'emporte.
 local e5,f5,p5=race(7); local t5=Pits.new(); f5.leaderLaps=3; step(t5,f5,e5,p5,100); assert(t5.sprint==true and t5.waived,'70 km: sprint')
 f5.pitWindowStart=100; f5.pitWindowEnd=900; f5.simTime=500; step(t5,f5,e5,p5,101)
 assert(t5.csp and not t5.waived and t5.state=='open','CSP window declared later: kept')
 local e3,f3,p3=race(5); p3.mandatoryStops=0; p3.maxStintMin=50; local t3=Pits.new(); local said3={}; local lines3=journal(t3)
 step(t3,f3,e3,p3,100,said3); step(t3,f3,e3,p3,101,said3)
 assert(#said3==0 and t3.sprint==nil and not t3.waived and not has(lines3,'arret obligatoire'),'no mandatory stop: nothing decided')
end

-- Course au temps : décidée au meilleur tour du plateau dès qu'une voiture a bouclé 2 tours, avant l'ouverture.
tests.SPRINT_TIMED_164=function()
 -- 30 min, 4,7 km, meilleur tour 90 s : 21 tours = 98,7 km : sprint.
 local e,f,p=timed(30,4700); local t=Pits.new(); local lines=journal(t); local said={}
 f.left=1750; step(t,f,e,p,100,said); assert(t.sprint==nil and t.state=='pending','no lap yet: undecided')
 laps(f,1,90); step(t,f,e,p,101,said); assert(t.sprint==nil and not t.waived,'one lap: undecided')
 laps(f,2,90); f.left=1600; step(t,f,e,p,102,said)
 assert(t.sprint==true and t.waived and t.state=='off' and math.abs(t.sprintKm-98.7)<1e-9 and t.sprintLap==90,'98.7 km: sprint ('..t.sprintKm..')')
 assert(kinds(said,'pitSprint')==1 and has(lines,'arret obligatoire leve: course sprint estimee a 98.7 km (30 min, meilleur tour 90.0 s, 100 km au plus)'),'said once with the estimate')
 -- Décision gardée : tour plus rapide ensuite, longueur perdue.
 laps(f,3,80); step(t,f,e,p,103,said); f.length=0; step(t,f,e,p,104,said)
 assert(t.sprint==true and t.state=='off' and kinds(said,'pitSprint')==1,'kept for the session')
 Pits.reset(t,200); assert(t.sprint==nil and t.sprintKm==-1 and not t.sprintSaid,'forgotten with the session')
 -- 4,9 km : 102,9 km : maintenu.
 local e2,f2,p2=timed(30,4900); local t2=Pits.new(); local lines2=journal(t2); local said2={}
 laps(f2,2,90); f2.left=1600; step(t2,f2,e2,p2,100,said2)
 assert(t2.sprint==false and not t2.waived and t2.state=='pending' and kinds(said2,'pitSprint')==0,'102.9 km: unchanged')
 assert(has(lines2,'arret obligatoire maintenu: course de 102.9 km (plus de 100 km)'),'kept line')
 -- Beta 1.64 (décision du pilote, constat 5) : fenêtre atteinte avant toute estimation : en attente (jamais ouverte)
 -- jusqu'à la décision, puis sprint (avant : ouverte, arrêt maintenu « distance inconnue », SPRINT_UNKNOWN_OR_CSP_164).
 local e3,f3,p3=timed(30,4700); local t3=Pits.new(); local lines3=journal(t3); local said3={}
 step(t3,f3,e3,p3,99,said3); f3.left=1800*0.7; step(t3,f3,e3,p3,100,said3); assert(not t3.opened and t3.sprint==nil and t3.state=='pending','window reached first: still pending')
 laps(f3,2,90); step(t3,f3,e3,p3,101,said3)
 assert(t3.sprint==true and t3.state=='off' and t3.waived and not t3.opened and kinds(said3,'pitSprint')==1 and kinds(said3,'pitOpen')==0,'decided before any opening: sprint')
 assert(not has(lines3,'arret obligatoire maintenu: distance inconnue avant l ouverture de la fenetre'),'never kept as unknown')
 -- Relecture 164d : app rechargée en pleine course au temps sans décision gardée (ancienne sauvegarde), fenêtre déjà
 -- atteinte : maintenu, jamais levé fenêtre ouverte.
 local e4,f4,p4=timed(30,4700); local t4=Pits.new(); laps(f4,8,90); f4.left=1800*0.6
 step(t4,f4,e4,p4,100); assert(t4.sprint==false and t4.state=='open' and not t4.waived,'reload without a kept decision: stop kept')
 -- Lignes du journal traduites (fenêtre DIAGNOSTICS).
 local Journal=require('src/journal')
 assert(Journal.english('arret obligatoire leve: course sprint estimee a 98.7 km (30 min, meilleur tour 90.0 s, 100 km au plus)')=='mandatory stop lifted: sprint race estimated at 98.7 km (30 min, best lap 90.0 s, 100 km at most)','translated (estimated)')
 assert(Journal.english('arret obligatoire leve: course sprint de 100.0 km (10 tours, 100 km au plus)')=='mandatory stop lifted: sprint race of 100.0 km (10 laps, 100 km at most)','translated (laps)')
 assert(Journal.english('arret obligatoire maintenu: course de 110.0 km (plus de 100 km)')=='mandatory stop kept: 110.0 km race (more than 100 km)','translated (kept)')
 assert(Journal.english('arret obligatoire maintenu: distance inconnue avant l ouverture de la fenetre')=='mandatory stop kept: distance unknown before the window opened','translated (unknown)')
end

-- Relecture 164d : décision gardée avec la session (rechargement de l'app) : relue, jamais reprise, ni redite.
tests.SPRINT_RELOAD_164=function()
 -- (a) F1, 15 min, tours de 100 s, 5 km : fenêtre ouverte (20 %) avant 2 tours bouclés : maintenu ; rechargée à 10 min
 -- (50 km estimés) : toujours maintenu, IA toujours appelées, aucune annonce.
 -- Beta 1.64 (décision du pilote, constat 5) : la fenêtre attend la décision quand l'estimation est possible ; ouverte
 -- d'abord ici parce que la longueur du circuit est encore inconnue à l'ouverture.
 local e,f,p=timed(15,5000); local t=Pits.new(); local said={}
 step(t,f,e,p,100,said); laps(f,1,100); f.left=700; f.length=0; step(t,f,e,p,101,said)
 assert(t.opened and t.sprint==nil,'(a) window opened before 2 laps')
 f.length=5000; laps(f,2,100); f.left=650; t.dirty=false; step(t,f,e,p,102,said)
 assert(t.sprint==false and t.dirty,'(a) kept, decision to be saved')
 local text=Pits.serialize(t,f.session)
 laps(f,6,100); f.left=300
 local t2=Pits.new(); local lines2=journal(t2); local said2={}; Pits.restore(t2,text,f.session); step(t2,f,e,p,200,said2)
 assert(t2.sprint==false and t2.state=='open' and not t2.waived,'(a) reload: decision read back, stop kept ('..t2.state..')')
 local called=0; for _,i in ipairs(ai(f)) do if e.commands[i].rulePit then called=called+1 end end
 assert(called>0,'(a) AI still called')
 assert(kinds(said2,'pitSprint')==0 and not has(lines2,'sprint') and not has(lines2,'arret obligatoire'),'(a) no sprint decision said again')
 -- Autre session (indice différent) : décision gardée ignorée.
 local t3=Pits.new(); Pits.restore(t3,text,f.session+1); assert(t3.restoredSprint==nil,'other session: ignored')
 -- Redémarrage de la session : oubliée.
 local t4=Pits.new(); Pits.restore(t4,text,f.session); Pits.forget(t4); assert(t4.restoredSprint==nil,'restart: forgotten')
 -- (b) 30 min, 4,7 km : sprint au tour 2 (meilleur tour 90 s, 98,7 km) ; rechargée au tour 8 (meilleur tour 85 s,
 -- 103,4 km) : toujours sprint, rien d'appelé, aucune annonce refaite.
 local eb,fb,pb=timed(30,4700); local tb=Pits.new(); local saidb={}
 step(tb,fb,eb,pb,100,saidb); laps(fb,2,90); fb.left=1600; tb.dirty=false; step(tb,fb,eb,pb,101,saidb)
 assert(tb.sprint==true and tb.sprintSaid and tb.dirty and kinds(saidb,'pitSprint')==1,'(b) sprint, said, to be saved')
 local textb=Pits.serialize(tb,fb.session)
 assert(textb:find('\n*sprint,1,98.700,90.000,1',1,true),'(b) saved line ('..textb..')')
 laps(fb,8,85); fb.left=1800-8*88
 local tc=Pits.new(); local linesc=journal(tc); local saidc={}; Pits.restore(tc,textb,fb.session); step(tc,fb,eb,pb,200,saidc)
 assert(tc.sprint==true and tc.waived and tc.state=='off' and math.abs(tc.sprintKm-98.7)<1e-9 and tc.sprintLap==90,'(b) reload: still a sprint ('..tc.state..')')
 for _,i in ipairs(ai(fb)) do assert(not eb.commands[i].rulePit,'(b) AI '..i..' never called') end
 assert(#saidc==0 and not has(linesc,'arret obligatoire'),'(b) nothing said again')
 -- Ligne gardée jamais prise pour une voiture.
 local td=Pits.new(); Pits.restore(td,textb,fb.session); assert(next(td.restored)==nil,'no car named sprint')
 -- Décision sur la grille, rechargée avant le départ : dite au départ.
 local eg,fg,pg=race(10); local tg=Pits.new(); fg.started=false; step(tg,fg,eg,pg,100)
 assert(tg.sprint==true and tg.dirty and not tg.sprintSaid,'decided on the grid: to be saved')
 local tg2=Pits.new(); local saidg={}; Pits.restore(tg2,Pits.serialize(tg,fg.session),fg.session)
 step(tg2,fg,eg,pg,101,saidg); fg.started=true; step(tg2,fg,eg,pg,102,saidg)
 assert(tg2.sprint==true and #saidg==1 and saidg[1][1]=='pitSprint','decided on the grid, reloaded: said at the start')
 -- Décision dite au départ : à sauvegarder aussi (jamais redite après un rechargement).
 tg.dirty=false; step(tg,fg,eg,pg,101); assert(tg.sprintSaid and tg.dirty,'said at the start: to be saved')
end

-- Relecture 164d : course au temps indécise : ni fenêtre ajustée ni course trop courte avant la décision ; jamais les deux
-- avis ; tour supplémentaire compté.
tests.SPRINT_TIMED_NOTICES_164=function()
 local function known(t,f,lap) for _,i in ipairs(ai(f)) do t.cars[i].lapTime=lap end end
 -- F1, 30 min, tour de référence 90 s connu au tour 1 (fermeture 92,5 %) : sprint : jamais « fenêtre ajustée ».
 local e,f,p=timed(30,4700); local t=Pits.new(); local lines=journal(t)
 step(t,f,e,p,100); laps(f,1,90); known(t,f,90); f.left=1710; step(t,f,e,p,101)
 assert(t.sprint==nil and not has(lines,'fenetre d arret ajustee'),'undecided: no adjusted-window line yet')
 laps(f,2,90); f.left=1620; step(t,f,e,p,102); step(t,f,e,p,103)
 assert(t.sprint==true and has(lines,'course sprint') and not has(lines,'fenetre d arret ajustee'),'sprint: never an adjusted-window line')
 -- 4,9 km (102,9 km) : maintenu, puis la fenêtre ajustée, dans cet ordre.
 local e2,f2,p2=timed(30,4900); local t2=Pits.new(); local lines2=journal(t2)
 step(t2,f2,e2,p2,100); laps(f2,1,90); known(t2,f2,90); f2.left=1710; step(t2,f2,e2,p2,101)
 assert(not has(lines2,'fenetre d arret ajustee'),'kept race: no adjusted-window line before the decision')
 laps(f2,2,90); f2.left=1620; step(t2,f2,e2,p2,102)
 assert(has(lines2,'arret obligatoire maintenu: course de 102.9 km') and has(lines2,'fenetre d arret ajustee'),'kept: adjusted window noted from the decision on')
 -- Course de 4 min (tours de 100 s, 5 km) : trop courte dès le tour 1, mais sprint au tour 2 : seulement le sprint.
 local e3,f3,p3=timed(4,5000); local t3=Pits.new(); local lines3=journal(t3); local said3={}
 step(t3,f3,e3,p3,100,said3); laps(f3,1,100); known(t3,f3,100); f3.left=140; step(t3,f3,e3,p3,101,said3)
 assert(t3.waived and kinds(said3,'pitShort')==0 and not has(lines3,'course trop courte'),'short but undecided: lifted, not said yet')
 laps(f3,2,100); f3.left=40; step(t3,f3,e3,p3,102,said3); step(t3,f3,e3,p3,103,said3)
 assert(t3.sprint==true and kinds(said3,'pitSprint')==1 and kinds(said3,'pitShort')==0 and not has(lines3,'course trop courte'),'sprint only, never both')
 -- Circuit de 50 km, 4 min (150 km) : trop courte, maintenue à la décision : la course trop courte dite alors, une fois.
 local e6,f6,p6=timed(4,50000); local t6=Pits.new(); local said6={}
 step(t6,f6,e6,p6,100,said6); laps(f6,1,100); known(t6,f6,100); f6.left=140; step(t6,f6,e6,p6,101,said6)
 assert(kinds(said6,'pitShort')==0,'150 km, undecided: not said yet')
 laps(f6,2,100); f6.left=40; step(t6,f6,e6,p6,102,said6); step(t6,f6,e6,p6,103,said6)
 assert(t6.sprint==false and t6.waived and kinds(said6,'pitShort')==1,'150 km kept: short race said once decided')
 -- Longueur inconnue (estimation impossible) : la course trop courte dite comme avant.
 local e4,f4,p4=timed(4,0); local t4=Pits.new(); local said4={}
 step(t4,f4,e4,p4,100,said4); laps(f4,1,100); known(t4,f4,100); f4.left=140; step(t4,f4,e4,p4,101,said4)
 assert(kinds(said4,'pitShort')==1,'length unknown: short race said as before')
 -- Tour supplémentaire (30 min, 4,7 km, 90 s) : 22 tours = 103,4 km : maintenu.
 local e5,f5,p5=timed(30,4700); f5.extraLap=true; local t5=Pits.new()
 step(t5,f5,e5,p5,100); laps(f5,2,90); f5.left=1600; step(t5,f5,e5,p5,101)
 assert(t5.sprint==false and math.abs(t5.sprintKm-103.4)<1e-9 and not t5.waived,'extra lap: 103.4 km, kept ('..t5.sprintKm..')')
 -- Lu dans la session d'AC (hasAdditionalLap).
 local host=require('tests/host').create(true)
 host.session={laps=0,durationMinutes=30,isTimedRace=true,hasAdditionalLap=true}
 local Snapshot=require('src/snapshot'); local s=Snapshot.new(); Snapshot.read(s,1/60,10)
 assert(s.timedRace and s.sessionMinutes==30 and s.extraLap==true,'extra lap read from the session')
 host.session={laps=0,durationMinutes=30,isTimedRace=true}; local s2=Snapshot.new(); Snapshot.read(s2,1/60,10)
 assert(s2.extraLap==false,'no extra lap')
end

-- Composé à l'arrêt : en sprint, un train neuf du même composé (la météo prime toujours) ; sinon, comme avant.
tests.SPRINT_COMPOUND_164=function()
 local a={tyresKnown=true,compoundIndex=0,dryCompounds={[0]=true,[1]=true,[2]=true}}
 local p={pitCompoundChange=true}
 assert(Pits.compound(a,{weatherManaged=false,weatherRain=false,weatherCompound=-1},p,{[0]=true},1)==1,'outside a sprint: another dry compound')
 assert(Pits.compound(a,{weatherManaged=false,weatherRain=false,weatherCompound=-1,sprintFree=true},p,{[0]=true},1)==0,'sprint: same compound')
 assert(Pits.compound(a,{weatherManaged=true,weatherRain=true,weatherCompound=4,sprintFree=true},p,{[0]=true},1)==4,'sprint: weather first')
 local e,f,pr=race(10); local t=Pits.new(); local b=f.cars[2]
 b.tyresKnown=true; b.compoundIndex=0; b.dryCompounds={[0]=true,[1]=true,[2]=true}
 f.leaderLaps=5; step(t,f,e,pr,100); b.pit=true; b.inPitBox=true; b.kmh=0; step(t,f,e,pr,101)
 assert(e.commands[2].sprintFree==true and e.commands[2].pitCompound==0,'sprint: AI at its box keeps its compound ('..e.commands[2].pitCompound..')')
 local e2,f2,p2=race(11); local t2=Pits.new(); local b2=f2.cars[2]
 b2.tyresKnown=true; b2.compoundIndex=0; b2.dryCompounds={[0]=true,[1]=true,[2]=true}
 f2.leaderLaps=5; step(t2,f2,e2,p2,100); b2.pit=true; b2.inPitBox=true; b2.kmh=0; step(t2,f2,e2,p2,101)
 assert(e2.commands[2].sprintFree==false and e2.commands[2].pitCompound==1,'110 km: another dry compound as before')
 -- Course mouillée (110 km) : composé imposé comme avant, pas de sprint.
 local e3,f3,p3=race(11); local t3=Pits.new(); t3.wetRace=true; local b3=f3.cars[2]
 b3.tyresKnown=true; b3.compoundIndex=0; b3.dryCompounds={[0]=true,[1]=true,[2]=true}
 f3.leaderLaps=5; step(t3,f3,e3,p3,100); b3.pit=true; b3.inPitBox=true; b3.kmh=0; step(t3,f3,e3,p3,101)
 assert(t3.waived and t3.sprint==false and e3.commands[2].pitCompound==1,'wet race over 100 km: unchanged')
end

-- Joueur, règles F1, moteur complet : en sprint, rien n'est dû (ni rappel, ni avis F1, ni compteur, ni pénalité) et le
-- message du sprint passe malgré une annonce plus importante de la même image ; 110 km : comme avant.
tests.SPRINT_PLAYER_164=function()
 local function scene(laps)
  local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); C.applyRules('F1',e.profiles)
  E.changed(e); f.sessionLaps=laps; f.leaderLaps=5
  local a=f.cars[1]; a.compoundIndex=0; a.tyresKnown=true
  a.tyreNames={[0]='SS',[1]='S',[2]='M'}; a.dryList={0,1,2}; a.dryCompounds={[0]=true,[1]=true,[2]=true}
  return e,f,a
 end
 local e,f=scene(10)
 local seen=false; local t=e.incidents
 for _=1,30 do F.tick(e,f,1/60); if t.messageKind=='pitSprint' then seen=true end end
 assert(seen and t.messageValue==100 and t.messageExtra==K.sprintMaxKm,'sprint announced to the player')
 F.tick(e,f,1)
 assert(e.pits.waived and e.pits.state=='off' and e.incidents.playerPitDue==0 and not e.incidents.playerPitCompound,'nothing due, no F1 reminder')
 f.leaderLaps=10; F.tick(e,f,1); assert(not e.penalties.stopPending,'no missed-stop penalty')
 local e2,f2=scene(11); F.tick(e2,f2,0.5)
 assert(not e2.pits.waived and e2.pits.state=='open' and e2.incidents.playerPitDue==1 and e2.incidents.playerPitCompound,'110 km: stop due as before')
 -- Relecture 164d : message du sprint écarté plus loin dans l'image (annonce plus importante) : redemandé, puis dit
 -- seulement une fois les annonces tues (busy) ; jamais gardé en attente par Incidents (affiché à l'écran).
 local Incidents=require('src/incidents'); local m=Incidents.new(); m.frameId=1; m.now=0
 local e3,f3,p3=race(10); local t3=Pits.new(); local said3=0
 local function emit(kind,a,b) said3=said3+1; Incidents.message(m,kind,a,b) end
 Pits.update(t3,f3,e3.commands,p3,'C',100,1,emit,false,nil,false,false)
 Incidents.message(m,'green'); Pits.confirmSprint(t3,m)
 assert(said3==1 and m.messageKind=='green' and t3.sprintShow,'covered by the green flag: asked again')
 m.frameId=2; m.now=0.02; Incidents.flushHeld(m,0.02)
 assert(m.messageKind=='green' and m.heldKind==nil,'never held by Incidents')
 Pits.update(t3,f3,e3.commands,p3,'C',100.02,1,emit,false,nil,false,true); Pits.confirmSprint(t3,m)
 assert(said3==1,'busy: waits')
 m.frameId=3; m.now=6
 Pits.update(t3,f3,e3.commands,p3,'C',106,1,emit,false,nil,false,false); Pits.confirmSprint(t3,m)
 assert(said3==2 and m.messageKind=='pitSprint' and m.messageValue==100 and not t3.sprintShow,'said once quiet')
 m.frameId=4; Pits.update(t3,f3,e3.commands,p3,'C',107,1,emit,false,nil,false,false); assert(said3==2,'said only once')
 -- Heure du dernier message décalée avec l'horloge.
 assert(m.messageAt==6,'time of the last message'); Incidents.rebase(m,5); assert(m.messageAt==1,'rebased')
end

-- Relecture 164d : course sprint avec tour de formation, moteur complet : l'annonce du tour de formation reste celle de
-- l'image du départ (écran et pont des apps compagnes) ; le sprint est dit ensuite, une fois, après la fin du tour.
tests.SPRINT_ANNOUNCE_FORCED_164=function()
 local LENGTH=1200
 local function slotZ(k) return -(K.gridFirst+(k-1)*K.gridPitch) end
 local function start(want)
  local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); C.applyRules('F1',e.profiles)
  e.profiles.C.raceStart=want; e.profiles.C.startRealism=false; e.profiles.C.pitMessage=true; f.length=LENGTH
  f.sessionLaps=10; f.leaderLaps=0
  for i=1,4 do f.cars[i].position=i; F.place(f,i,slotZ(i),0) end
  -- Sur la grille (course pas lancée), puis départ.
  f.started=false; E.changed(e); e.gridCaps=true; F.tick(e,f,1/60); F.tick(e,f,1/60)
  assert(not e.pits.sprintSaid and e.incidents.messageKind~='pitSprint','nothing said on the grid')
  f.started=true; F.tick(e,f,1/60)
  return e,f
 end
 local e,f=start('formation'); local t=e.incidents
 assert(e.pits.sprint==true and e.pits.sprintSaid,'12 km: sprint, decided and logged at the start')
 assert(t.messageKind=='formation' and t.messageExtra==0,'start frame: formation announcement kept ('..tostring(t.messageKind)..')')
 for _=1,120 do F.tick(e,f,1/60); assert(t.messageKind~='pitSprint','never during the formation lap') end
 -- Départ lancé : tour de formation, drapeau vert, puis le sprint, une seule fois.
 local r,fr=start('rolling'); local m=r.incidents
 assert(m.messageKind=='formation' and m.messageExtra==1,'rolling: formation announcement kept')
 local shown,id,afterGreen,lastAt,quiet=0,m.messageId,false,-math.huge,false
 for i=1,fr.count do local a=fr.cars[i]; a.kmh=100; a.speed=100/3.6 end
 for _=1,90*60 do
  for i=1,fr.count do local a=fr.cars[i]; if not a.pit then a.z=a.z+a.speed/60; a.spline=(a.z/fr.length)%1 end end
  F.tick(r,fr,1/60)
  if m.messageId~=id then id=m.messageId
   if m.messageKind=='pitSprint' then shown=shown+1; afterGreen=not m.formation and not m.neutral; quiet=r.time-lastAt>=K.sprintQuiet-1e-6 else lastAt=r.time end
  end
 end
 assert(shown==1 and afterGreen,'said once, after the formation lap ('..shown..')')
 assert(quiet,'never right after another message (K.sprintQuiet s)')
end

-- Décision du pilote 2026-11-14 (« jamais lever un arrêt configuré ») : la levée sprint est coupée en jeu
-- (K.sprintWaiver=false, tests/review164j1.lua : LOCK_SPRINT_164) ; ces tests gardent le chemin couvert en la forçant.
for name,fn in pairs(tests) do
 tests[name]=function()
  local old=K.sprintWaiver; K.sprintWaiver=true
  local ok,err=pcall(fn); K.sprintWaiver=old
  if not ok then error(err,0) end
 end
end
return tests
