-- Beta 1.60, voiture de sécurité (course de Bakou du 11 novembre) : allure libre, jamais doublée, file regroupée avant
-- sa rentrée, relance pour la file seulement, pose en piste sans attendre quand elle reste immobile à son emplacement.
-- Noms terminés par _160S. Chargé par tests/extended.lua. Valeurs des voitures : celles que le jeu fournit (position
-- le long de la piste, vitesse, voie des stands) ; aucun écart latéral forcé.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local A=require('src/applier')
local Incidents=require('src/incidents')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Course, voiture 5 = voiture de sécurité, voiture 4 arrêtée en piste (incident majeur) : voiture de sécurité appelée,
-- posée en piste à 1200 m devant le meneur (voiture 2), joueur (voiture 1) dans la voie des stands.
local function deployed(setup)
 local e,f=F.scene('C',5); C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; if setup then setup(e) end; E.changed(e)
 e.g.safetyCarModel='car_5'; F.place(f,5,0,0); f.cars[5].pit=true; f.cars[5].inPitBox=true
 f.cars[1].pit=true; f.cars[1].inPitBox=true
 F.place(f,2,1000,120); F.place(f,3,900,120); f.cars[2].position=1; f.cars[3].position=2
 F.place(f,4,6000,0)
 for _=1,900 do F.tick(e,f,0.1); if e.incidents.safetyPhase=='place' then break end end
 assert(e.incidents.neutral and e.incidents.safetyPhase=='place','safety car to be placed')
 -- Incident dégagé : la voiture 4 rentre aux stands (hors de la file).
 F.place(f,4,6000,60); f.cars[4].pit=true
 F.place(f,5,1200,80); f.cars[5].pit=false; f.cars[5].inPitBox=false; F.tick(e,f,0.5)
 assert(e.incidents.safetyPhase=='out','on track')
 return e,f,e.incidents
end
-- Allure libre : 80 km/h tant que le peloton est loin, puis plus aucune limite ; allure du peloton connue : jamais plus
-- vite que la voiture juste derrière elle, plus lente de K.scPacePct %.
tests.SC_FREE_PACE_160S=function()
 local e,f,t=deployed()
 assert(e.run.safetyCarSpeedKmh==nil,'the speed setting is gone')
 assert(e.commands[5].scSpeed==K.scLeadKmh,'slow while the field is far behind')
 F.place(f,2,1150,120); F.place(f,3,1100,120); F.tick(e,f,0.5)
 assert(t.scHead==2 and e.commands[5].scSpeed==K.scNominalKmh+K.scCatchUp-K.scFreeMargin,'free pace once the queue head is close (lot 5: finite while the pace of the field is unknown): '..tostring(e.commands[5].scSpeed))
 local s=e.states[2]; for b=1,#s.pace do s.pace[b]=250/3.6 end; s.paceCount=400
 F.tick(e,f,0.2)
 assert(math.abs(e.commands[5].scSpeed-250/(1+K.scPacePct/100))<1e-6,'never faster than the field can follow: '..e.commands[5].scSpeed)
 for b=1,#s.pace do s.pace[b]=60/3.6 end; F.tick(e,f,0.2)
 assert(e.commands[5].scSpeed==K.scLeadKmh,'never below its catch-up pace')
end
-- Limite rendue à AC quand elle roule à son allure libre (elle restait posée à 80 km/h) ; jamais pour une autre voiture.
tests.SC_FREE_RELEASE_160S=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C'); local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false end
 local cmd=e.commands[3]; f.cars[3].safetyCar=true
 cmd.scPark=false; cmd.scSpeed=K.scLeadKmh; A.apply(a,f,e.commands,e.g,1); assert(host.speedLimits[2]==K.scLeadKmh,'catch-up pace written')
 cmd.scSpeed=K.unlimitedSpeed; A.apply(a,f,e.commands,e.g,1.2); assert(host.speedLimits[2]==nil or host.speedLimits[2]>=K.unlimitedSpeed,'limit given back: '..tostring(host.speedLimits[2]))
 assert(a.cars[3].speed==nil,'no limit kept')
end
-- Rattrapage : allure propre plus lente de K.scCatchPct % (inconnue : l'ancienne limite fixe), loin de la voiture de
-- sécurité ; juste derrière elle : son allure (rattrapage borné) ; à sa hauteur : moins vite qu'elle.
tests.SC_FIELD_CAP_160S=function()
 local e,f,t=deployed()
 F.place(f,5,1200,100); F.place(f,2,5000,150); F.tick(e,f,0.2)
 local cap=Incidents.cap(t,f,2,e.run,e.delta,e.states,0)
 assert(math.abs(cap-(K.scNominalKmh+K.scCatchUp))<1e-6,'pace unknown: the former fixed limit: '..cap)
 local s=e.states[2]; for b=1,#s.pace do s.pace[b]=300/3.6 end; s.paceCount=400
 cap=Incidents.cap(t,f,2,e.run,e.delta,e.states,0)
 assert(math.abs(cap-300/(1+K.scCatchPct/100))<1e-6,'own pace, a little slower: '..cap)
 -- 40 m derrière elle (pare-chocs) : son allure plus un rattrapage borné.
 F.place(f,2,1200-40-4.4,150); cap=Incidents.cap(t,f,2,e.run,e.delta,e.states,0)
 assert(math.abs(cap-(100+(40-K.queueKeep)*K.queueClose))<1e-6,'behind it: bounded closing: '..cap)
 F.place(f,2,1200-5-4.4,150); cap=Incidents.cap(t,f,2,e.run,e.delta,e.states,0)
 assert(math.abs(cap-100)<1e-6,'in its wheel tracks: its pace: '..cap)
 -- À sa hauteur (2 m de recouvrement), quelle que soit sa file : jamais lâchée, un peu moins vite qu'elle.
 F.place(f,2,1200-2.4,150,3); cap=Incidents.cap(t,f,2,e.run,e.delta,e.states,0)
 assert(math.abs(cap-(100-K.scOverlapDrop))<1e-6,'alongside: slower than it: '..cap)
 -- Entièrement devant, sans l'avoir doublée (pas de place à rendre) : rattrapage ordinaire.
 F.place(f,2,1300,150); cap=Incidents.cap(t,f,2,e.run,e.delta,e.states,0)
 assert(math.abs(cap-300/(1+K.scCatchPct/100))<1e-6,'ahead, never behind it before: ordinary catch-up: '..cap)
end
-- Voiture de sécurité doublée : journal, sanction de l'IA, place à rendre (limite sous son allure), puis place rendue.
-- Dans un virage (caps différents : la perception oublie la voiture de devant), le dépassement est vu quand même.
tests.SC_PASSED_160S=function()
 local e,f,t=deployed()
 F.place(f,5,1200,100); F.place(f,2,1150,100); F.place(f,3,1100,100); F.tick(e,f,0.3)
 assert(t.cars[2].scBehind and t.cars[3].scBehind and count(e,'voiture de securite: doublee')==0,'both behind it')
 -- Virage serré : la voiture 2 tourne (cap à 90 degrés), puis se retrouve entièrement devant.
 f.cars[2].lx=1; f.cars[2].lz=0; F.place(f,2,1210,130); F.tick(e,f,0.1)
 assert(t.cars[2].scPassed and count(e,'voiture de securite: doublee par Driver_2 a 1200 m, place a rendre')==1,'pass seen on the track position')
 assert(count(e,'sanction IA: Driver_2 a double Driver_5 sous drapeau jaune (infraction 1 / ')==1,'AI sanctioned, same line as any pass under neutralisation')
 local cap=Incidents.cap(t,f,2,e.run,e.delta,e.states,0)
 assert(math.abs(cap-(100-K.giveBackDrop))<1e-6,'gives the place back: below its pace: '..cap)
 F.tick(e,f,1); assert(count(e,'voiture de securite: doublee')==1 and count(e,'sanction IA: Driver_2')==1,'noted and sanctioned once')
 -- La voiture de sécurité repasse devant : place rendue, plus de limite propre.
 f.cars[2].lx=0; f.cars[2].lz=1; F.place(f,2,1150,70); F.tick(e,f,0.1)
 assert(not t.cars[2].scPassed and count(e,'voiture de securite: place rendue par Driver_2')==1,'place given back')
 -- Voiture vue devant elle sans l'avoir doublée (pose en piste derrière elle) : notée une fois, jamais sanctionnée.
 F.place(f,3,5000,100); F.tick(e,f,0.1); F.place(f,3,1300,100); F.tick(e,f,0.5)
 assert(t.cars[3].scAhead,'noted once: remembered')
 assert(not t.cars[3].scPassed and count(e,'voiture de securite: Driver_3 roule devant elle')==1 and count(e,'sanction IA: Driver_3')==0,'ahead without passing: noted only')
 -- Place jamais rendue : abandonnée après K.scPassedMax s.
 F.place(f,2,1210,100); F.tick(e,f,0.1); assert(t.cars[2].scPassed,'passed again')
 F.tick(e,f,K.scPassedMax+0.5); assert(not t.cars[2].scPassed and count(e,'place non rendue par Driver_2')==1,'dropped after the time limit')
 -- Sanctions des IA coupées : dépassement noté, place à rendre, aucune infraction.
 local e2,f2,t2=deployed(function(x) x.profiles.C.aiPenalties=false end)
 F.place(f2,5,1200,100); F.place(f2,2,1150,100); F.tick(e2,f2,0.3)
 f2.cars[2].lx=1; f2.cars[2].lz=0; F.place(f2,2,1210,130); F.tick(e2,f2,0.1)
 assert(t2.cars[2].scPassed and count(e2,'voiture de securite: doublee par Driver_2')==1 and count(e2,'sanction IA')==0,'AI sanctions off: noted, place to give back, no strike')
end
-- Elle ne rentre qu'une fois le peloton regroupé derrière elle ; attente bornée (voiture qui se traîne).
tests.SC_BUNCH_160S=function()
 local e,f,t=deployed()
 F.place(f,5,1200,100); F.place(f,2,1150,100); F.place(f,3,6000,100)
 F.tick(e,f,K.scMinOut+e.run.neutralizationHold+5)
 assert(t.safetyPhase=='out' and count(e,'voiture de securite: rentre ce tour')==0,'field split in two: it stays out')
 F.place(f,3,1150-K.scBunchGap+10,100); F.tick(e,f,0.2)
 assert(t.safetyPhase=='in' and count(e,'voiture de securite: rentre ce tour')==1 and count(e,'peloton non regroupe')==0,'bunched up: in this lap')
 -- Peloton jamais regroupé : elle rentre après K.scBunchLaps tour(s) à l'allure nominale, raison au journal.
 local e2,f2,t2=deployed()
 F.place(f2,5,1200,100); F.place(f2,2,1150,100); F.place(f2,3,6000,100)
 local wait=K.scMinOut+math.min(K.scBunchMax,K.scBunchLaps*f2.length/(K.scNominalKmh/3.6))
 F.tick(e2,f2,wait-5); assert(t2.safetyPhase=='out','still waiting')
 F.tick(e2,f2,10)
 assert(t2.safetyPhase=='in' and count(e2,'voiture de securite: peloton non regroupe (1 / 2 dans la file)')==1,'bounded wait, logged')
end
-- Vert : « dépassement interdit jusqu'à la ligne » pour la file derrière elle seulement.
tests.SC_GREEN_TRAIN_160S=function()
 local e,f,t=deployed()
 F.place(f,5,1200,100); F.place(f,2,1150,100); F.place(f,3,1100,100); F.place(f,4,6000,100); f.cars[4].pit=false
 F.tick(e,f,K.scMinOut+K.scBunchLaps*f.length/(K.scNominalKmh/3.6)+e.run.neutralizationHold+5)
 assert(t.safetyPhase=='in','in this lap')
 -- Elle entre dans la voie des stands, la tête de la file déjà un peu devant elle.
 F.place(f,5,9000,60); F.place(f,2,9020,100); F.place(f,3,8950,100); F.tick(e,f,0.1)
 f.cars[5].pit=true; F.tick(e,f,0.1)
 assert(not t.neutral and t.restart,'green, restart rule')
 assert(t.cars[2].restart and t.cars[3].restart,'the queue: no overtaking until the line')
 assert(not t.cars[4].restart and count(e,'reprise: 1 voiture(s) hors de la file, depassement permis aussitot')==1,'a car elsewhere on the track races at once')
end
-- Libérée mais immobile à son emplacement : posée en piste après K.scLeaveStill s, sans attendre K.scLeaveMax s.
tests.SC_LEAVE_STILL_160S=function()
 local e,f=F.scene('C',5); C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; E.changed(e)
 e.g.safetyCarModel='car_5'; F.place(f,5,0,0); f.cars[5].pit=true; f.cars[5].inPitBox=true
 F.place(f,2,1000,120); f.cars[2].position=1; F.place(f,1,2000,120); F.place(f,4,6000,0)
 local t=e.incidents
 for _=1,900 do F.tick(e,f,0.1); if t.safetyPhase=='exit' or t.safetyPhase=='place' then break end end
 assert(t.safetyPhase=='exit','released in its box')
 local since=e.time
 for _=1,600 do F.tick(e,f,0.1); if t.safetyPhase~='exit' then break end end
 assert(t.safetyPhase=='place' and e.time-since<K.scLeaveStill+1 and K.scLeaveStill<K.scLeaveMax,'placed after '..(e.time-since)..' s')
 assert(count(e,'ne quitte pas son emplacement')==1,'reason logged')
 -- Elle roule dans son emplacement (elle sort) : jamais posée avant K.scLeaveMax s.
 local e2,f2=F.scene('C',5); C.preset('Course','C',e2.profiles.C); e2.profiles.C.neutralization='sc'; E.changed(e2)
 e2.g.safetyCarModel='car_5'; F.place(f2,5,0,20); f2.cars[5].pit=true; f2.cars[5].inPitBox=true
 F.place(f2,2,1000,120); f2.cars[2].position=1; F.place(f2,1,2000,120); F.place(f2,4,6000,0)
 local t2=e2.incidents
 for _=1,900 do F.tick(e2,f2,0.1); if t2.safetyPhase=='exit' or t2.safetyPhase=='place' then break end end
 assert(t2.safetyPhase=='exit','released in its box')
 F.tick(e2,f2,K.scLeaveStill+5); assert(t2.safetyPhase=='exit','moving in its box: not placed yet')
end
return tests
