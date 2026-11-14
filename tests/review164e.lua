-- Beta 1.64, lot 5 (procédures de la voiture de sécurité, décisions du pilote du 13 novembre, questionnaire) :
-- dédoublement comme en F1 (attardées de la file autorisées une par une, rentrée à la fin du tour suivant), arrivée
-- neutralisée (dernier tour sous voiture de sécurité : elle rentre sans relance, file jusqu'au damier), zigzags derrière
-- elle seulement pneus froids. Lot 4 (course sprint) : fenêtre en attente jusqu'à la décision d'une course au temps,
-- marge de 3 % sur le tour de référence de l'estimation. Chargé par tests/extended.lua (après tests/review164d).
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Incidents=require('src/incidents')
local Delta=require('src/delta')
local Pits=require('src/pits')
local Antics=require('src/antics')
local U=require('src/util')
local K=C.K
local SK=Incidents.SK
local openFile=io.open
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local SC=8
local SCLAP=10000/(K.scNominalKmh/3.6)
-- Course (préréglage Course), voiture de sécurité car_8, voiture 7 arrêtée en piste à 6000 m (neutralisation SC), puis
-- rentrée aux stands ; voiture de sécurité posée en piste à 2000 m, file derrière elle (o.z : {voiture=z}, joueur 1
-- seulement s'il y figure, sinon aux stands ; o.lapped : voitures au tour 10, les autres au tour 11). o.call : retour dès
-- la neutralisation (voiture de sécurité appelée). Rend e, f, t et L (tour de chaque voiture, rendu après F.place).
local function scene(o)
 o=o or {}
 local e,f=F.scene('C',8); C.preset('Course','C',e.profiles.C); local p=e.profiles.C; p.neutralization='sc'
 if o.setup then o.setup(p) end
 E.changed(e); e.g.safetyCarModel='car_8'
 f.sessionLaps=o.sessionLaps or 30; f.leaderLaps=o.leaderLaps or 10; f.timedRace=o.timed==true; f.left=o.left or 1000
 local z=o.z or {[2]=1950,[3]=1930,[4]=1910,[5]=1890,[6]=1870}
 local lapped=o.lapped or {[4]=true}
 F.place(f,SC,0,0); f.cars[SC].pit=true; f.cars[SC].inPitBox=true
 local order={}; local L={[SC]=11}
 for i=1,6 do
  if z[i] then F.place(f,i,z[i],100); f.cars[i].lap=lapped[i] and 10 or 11; L[i]=f.cars[i].lap; order[#order+1]=i
  else f.cars[i].pit=true; f.cars[i].inPitBox=true end
 end
 table.sort(order,function(x,y) if (lapped[x] and 1 or 0)~=(lapped[y] and 1 or 0) then return not lapped[x] end return z[x]>z[y] end)
 for k,i in ipairs(order) do f.cars[i].position=k end
 local n=#order; for i=1,7 do if not z[i] then n=n+1; f.cars[i].position=n end end
 F.place(f,7,6000,0); f.cars[7].lap=11; L[7]=11
 local t=e.incidents
 for _=1,900 do F.tick(e,f,0.1); if o.call and t.neutral or t.safetyPhase=='exit' then break end end
 if o.call then assert(t.neutral,'neutralised'); return e,f,t,L end
 assert(t.safetyPhase=='exit','Safety Car released')
 f.cars[7].pit=true; f.cars[7].inPitBox=true
 F.place(f,SC,2000,100); f.cars[SC].pit=false; f.cars[SC].inPitBox=false; f.cars[SC].lap=11
 F.tick(e,f,0.1); assert(t.safetyPhase=='out','Safety Car on track')
 return e,f,t,L
end
local function put(f,L,i,z,kmh) F.place(f,i,z,kmh or f.cars[i].kmh); f.cars[i].lap=L[i] or f.cars[i].lap end
-- Toute la piste décalée de dz m (voitures en piste de L, tours gardés).
local function shift(f,L,dz) for i,_ in pairs(L) do local a=f.cars[i]; if not a.pit then put(f,L,i,a.z+dz,a.kmh) end end end
-- Images jusqu'à la décision de rentrée (dédoublement lancé ou voiture de sécurité qui rentre).
local function decide(e,f,t)
 for _=1,80*60 do F.tick(e,f,1/60); if t.unlapState~='none' or t.safetyPhase~='out' then return end end
 error('no decision')
end
local function frames(e,f,n) for _=1,n do F.tick(e,f,1/60) end end
-- Voiture i menée jusqu'à z par pas de 0,5 m par image (le passage devant la voiture de sécurité, vu par la perception
-- comme en jeu, jamais d'un saut).
local function glide(e,f,L,i,z,kmh) local a=f.cars[i]; while math.abs(z-a.z)>0.5 do put(f,L,i,a.z+(z>a.z and 0.5 or -0.5),kmh); F.tick(e,f,1/60) end; put(f,L,i,z,kmh); F.tick(e,f,1/60) end
-- File formée et première attardée autorisée.
local function running(o)
 local e,f,t,L=scene(o); decide(e,f,t); assert(t.unlapState=='run','unlapping started')
 F.tick(e,f,SK.settle+0.1); assert(t.unlapCar>0,'first car allowed')
 return e,f,t,L
end
local function scFreeCount(e,f) local n=0; for j=1,f.count do if e.incidents.cars[j].scFree then n=n+1 end end return n end

-- Dédoublement : file formée, une attardée (Driver_4) autorisée après SK.settle s, exemptée (aucun jaune, son allure de
-- rattrapage, ni « doublée par » ni sanction), puis la voiture de sécurité rentre à son passage de la ligne suivant.
tests.LOCK_SC_UNLAP_164=function()
 local e,f,t,L=scene()
 assert(e.run.multiClass==true,'multi-class setting on (Course preset): a single-class field still unlaps')
 decide(e,f,t)
 assert(count(e,'voiture de securite: file formee, 1 attardee(s) autorisee(s) a se dedoubler une par une')==1 and t.unlapState=='run' and t.safetyPhase=='out' and t.unlapCar==0,'queue formed: unlapping starts, Safety Car stays out')
 local at=e.time
 while e.time-at<SK.settle-0.05 do F.tick(e,f,1/60); assert(t.unlapCar==0 and count(e,'autorisee a se dedoubler (')==0,'nothing during the settle time') end
 F.tick(e,f,0.2)
 assert(t.unlapCar==4 and count(e,'voiture de securite: Driver_4 autorisee a se dedoubler (1 / 1)')==1,'Driver_4 allowed')
 assert(t.messageKind=='scUnlap' and t.messageValue==3 and t.messageText=='Driver_4','message to the overlay and the bridge ('..tostring(t.messageKind)..')')
 assert(Incidents.unlapping(t,4) and t.cars[4].scFree and scFreeCount(e,f)==1,'only Driver_4 exempted')
 put(f,L,4,1980,100)
 local cap,yellow=Incidents.cap(t,f,4,e.run,e.delta,e.states,0)
 -- Sans garde de la voiture de sécurité : son allure de rattrapage (inconnue : K.scNominalKmh+K.scCatchUp), jamais la file
 -- 20 m derrière elle (à peine plus que la voiture de sécurité).
 assert(not yellow and math.abs(cap-(math.max(K.scNominalKmh,f.cars[SC].kmh)+K.scCatchUp))<1e-6,'Driver_4 may pass, no Safety Car guard: '..cap)
 local _,y5=Incidents.cap(t,f,5,e.run,e.delta,e.states,0); assert(y5,'Driver_5 still under the Safety Car')
 for _,z in ipairs({1940,1960,1995}) do put(f,L,4,z,140); F.tick(e,f,0.2) end
 assert(t.unlapCar==4,'still unlapping alongside the Safety Car')
 glide(e,f,L,4,2010,140); F.tick(e,f,0.2)
 assert(count(e,'doublee par')==0 and #t.scPasses==0 and e.penalties.ai.owe[4]==nil and e.penalties.ai.count[4]==nil and count(e,'sanction IA')==0,'no pass of the Safety Car, no sanction')
 assert(count(e,'voiture de securite: Driver_4 s est dedoublee (1 / 1)')==1 and t.unlapState=='done' and not t.cars[4].scLift and t.safetyPhase=='out','unlapped, the Safety Car waits for its line')
 F.tick(e,f,1); assert(t.safetyPhase=='out','still out mid-lap')
 shift(f,L,7990); frames(e,f,1); assert(t.safetyPhase=='out','before the line')
 shift(f,L,20); frames(e,f,2)
 assert(t.safetyPhase=='in' and count(e,'voiture de securite: rentre ce tour')==1 and t.unlapState=='none' and not t.cars[4].unlapOut,'in at its line crossing')
 assert(count(e,'dedoublement interrompu')==0 and count(e,'peloton non regroupe')==0,'released cleanly')
end

-- Ordre : liste figée au moment de la file formée, de l'avant vers l'arrière ; une seule autorisée à la fois ; la
-- suivante seulement quand la précédente est entièrement devant la voiture de sécurité.
tests.LOCK_SC_UNLAP_ORDER_164=function()
 local e,f,t,L=scene({z={[2]=1975,[6]=1940,[5]=1910,[4]=1880,[3]=1860},lapped={[4]=true,[6]=true}})
 decide(e,f,t)
 assert(t.unlapN==2 and t.unlapList[1]==6 and t.unlapList[2]==4,'frozen list, front to back')
 f.cars[5].lap=10; L[5]=10
 F.tick(e,f,SK.settle+0.1)
 assert(t.unlapCar==6 and not Incidents.unlapping(t,4),'Driver_6 first, alone')
 F.tick(e,f,0.5)
 local _,y4=Incidents.cap(t,f,4,e.run,e.delta,e.states,0)
 assert(y4 and e.states[4].neutralQueue~=0,'Driver_4 waits in the queue')
 for _=1,30 do F.tick(e,f,1/60); assert(scFreeCount(e,f)==1,'one exempted car at a time') end
 put(f,L,6,1995,140); F.tick(e,f,0.3); assert(t.unlapCar==6,'alongside the Safety Car: not yet')
 local seen,extra,id=0,nil,t.messageId
 glide(e,f,L,6,2010,140)
 for _=1,30 do F.tick(e,f,1/60); if t.messageId~=id then id=t.messageId; if t.messageKind=='scUnlap' then seen=seen+1; extra=t.messageExtra end end end
 assert(t.unlapCar==4 and seen==1 and extra==0,'then Driver_4, second message with none left')
 assert(count(e,'Driver_5 autorisee')==0,'a car lapped after the freeze is never added')
end

-- Tours de retard : écart des tours moins l'écart physique.
tests.LOCK_SC_UNLAP_LAPS_164=function()
 local len=1200
 local function car(lap,spline,valid) return {lap=lap,spline=spline,lapValid=valid~=false,splineValid=true} end
 local L=car(11,0.30)
 assert(Incidents.lapsDown(L,car(10,0.30+300/len))==1,'(a) lapped, 300 m ahead of the leader')
 assert(Incidents.lapsDown(L,car(10,0.30-300/len))==1,'(b) lapped, 300 m behind')
 assert(Incidents.lapsDown(L,car(11,0.30-300/len))==0,'(c) same lap, behind')
 assert(Incidents.lapsDown(L,car(10,0.30))==1,'(d) lapped, level')
 assert(Incidents.lapsDown(L,car(9,0.30))==2,'(e) two laps down')
 assert(Incidents.lapsDown(L,car(10,0.30,false))==0,'(f) lap unknown')
 local b=car(10,0.30+300/len)
 assert(math.floor((L.lap+L.spline)-(b.lap+b.spline)+K.lapTolerance)==0,'the plain lap difference misses (a)')
end

-- Rien sans attardée, sans format de course connu, en course multi-classe, en fin de course ou après un regroupement tardif.
tests.LOCK_SC_UNLAP_NONE_164=function()
 local function inAt(o) local e,f,t=scene(o); decide(e,f,t); return e,t,e.time end
 local e1,t1,at1=inAt({lapped={}})
 local _,_,at0=inAt({lapped={},sessionLaps=0})
 assert(t1.safetyPhase=='in' and math.abs(at1-at0)<1e-9 and count(e1,'dedoublement')==0,'(a) no lapped car: in at the same frame')
 local e2,t2=inAt({sessionLaps=0})
 assert(t2.safetyPhase=='in' and t2.unlapState=='none' and count(e2,'dedoublement')==0,'(b) unknown format: never')
 local e3,f3,t3=scene(); e3.states[3].class=2; e3.states[3].classified=true; decide(e3,f3,t3)
 assert(t3.safetyPhase=='in' and count(e3,'voiture de securite: dedoublement non lance (course multi-classe, 1 attardee(s))')==1,'(c) multi-class race: not started')
 local e4,t4=inAt({leaderLaps=28})
 assert(t4.safetyPhase=='in' and count(e4,'dedoublement non lance (fin de course proche')==1,'(d) 2 laps to go: not started')
 local e5,f5,t5=scene({z={[2]=1950,[3]=1930,[4]=1910,[5]=1890,[6]=1500}})
 F.tick(e5,f5,K.scMinOut+2); assert(t5.safetyPhase=='out' and t5.unlapState=='none','not regrouped: waits')
 t5.safetySince=e5.time-(K.scMinOut+K.scBunchMax)-1; frames(e5,f5,2)
 assert(t5.safetyPhase=='in' and count(e5,'peloton non regroupe')==1 and count(e5,'dedoublement')==0,'(e) late regroup: in as in 1.63')
end

-- Joueur attardé : autorisé, panneau propre, ni delta ni pénalité ; sans progrès, son tour passe ; doublé par une
-- autorisée : aucune place à reprendre.
tests.LOCK_SC_UNLAP_PLAYER_164=function()
 local z={[2]=1960,[3]=1940,[1]=1920,[5]=1900,[6]=1880,[4]=1860}
 local e,f,t,L=running({z=z,lapped={[1]=true}})
 assert(t.unlapCar==1 and t.messageKind=='scUnlap' and t.messageText=='Driver_1','player allowed by name')
 F.tick(e,f,0.5)
 assert(e.panel.decided=='scUnlap' and e.panel.kind=='sc' and not e.panel.noPass,'panel: unlap, no « no overtaking » line')
 assert(e.delta.course.kind=='' and not e.delta.infraction,'no delta while unlapping')
 local n0=e.penalties.count
 for _,zz in ipairs({1945,1965,1995}) do put(f,L,1,zz,140); F.tick(e,f,0.2) end
 glide(e,f,L,1,2010,140)
 assert(e.penalties.count==n0 and count(e,'doublee par')==0,'no pass penalty')
 assert(count(e,'voiture de securite: Driver_1 s est dedoublee (1 / 1)')==1,'unlapped')
 F.tick(e,f,0.5)
 assert(e.panel.decided~='scUnlap' and e.panel.kind=='sc' and not t.cars[1].scFree and e.delta.course.kind=='sc','back to the Safety Car rules')
 local e2,f2,t2=running({z=z,lapped={[1]=true}})
 t2.unlapAt=e2.time-U.clamp(SCLAP,SK.passMin,SK.passMax)-0.1; frames(e2,f2,2)
 assert(count(e2,'voiture de securite: Driver_1 ne se dedouble pas (delai depasse), reste dans la file')==1 and count(e2,'dedoublement termine (0 / 1)')==1,'no progress in one Safety Car lap: turn lost')
 local e3,f3,t3,L3=running({z={[2]=1960,[1]=1940,[4]=1920,[3]=1900,[5]=1880,[6]=1860},lapped={[4]=true}})
 assert(t3.unlapCar==4,'AI allowed')
 local n3=e3.penalties.count
 for _,zz in ipairs({1945,1965,1995}) do put(f3,L3,4,zz,140); F.tick(e3,f3,0.2) end
 glide(e3,f3,L3,4,2010,140)
 assert((e3.penalties.retake[1]==nil or e3.penalties.retake[1][4]==nil) and e3.penalties.count==n3,'passed by the allowed AI: nothing to retake')
end

-- IA autorisée : ni « doublée par », ni place à rendre, ni sanction ; témoin : la même manœuvre par une IA non autorisée.
tests.LOCK_SC_UNLAP_FREE_164=function()
 local e,f,t,L=running()
 assert(t.unlapCar==4 and e.run.aiPenalties,'Driver_4 allowed, AI sanctions on')
 for _,z in ipairs({1940,1960,1995}) do put(f,L,4,z,140); F.tick(e,f,0.2) end
 glide(e,f,L,4,2010,140)
 assert(#t.scPasses==0 and count(e,'doublee par')==0 and not t.cars[4].scPassed and not t.cars[4].scLift,'Safety Car passed freely')
 assert(e.penalties.ai.owe[4]==nil and count(e,'sanction IA')==0,'no place to give back, no sanction')
 for _,z in ipairs({1935,1960,1995,2020}) do put(f,L,5,z,140); F.tick(e,f,0.2) end
 assert(count(e,'voiture de securite: doublee par Driver_5')==1 and (e.penalties.ai.owe[5]~=nil or count(e,'sanction IA')>0),'witness: Driver_5 must give the places back')
end

-- Directeur : l'autorisée hors de la file (au plus +SK.rel km/h sur la voiture devant) ; la file derrière elle ; rabattue
-- devant, elle redevient la cible ; à hauteur, jamais.
tests.LOCK_SC_UNLAP_CAP_164=function()
 local e,f,t,L=running({z={[2]=1975,[3]=1950,[4]=1935,[5]=1900,[6]=1875}})
 assert(t.unlapCar==4,'Driver_4 allowed')
 put(f,L,3,1950,120); put(f,L,4,1920,170); put(f,L,5,1900,120)
 F.tick(e,f,1)
 local vt=(120+SK.rel)/3.6; local best=30-4.4
 local env=math.sqrt(vt*vt+2*e.run.yellowDecel*math.max(0,best-K.queueKeep))*3.6
 local lim=e.commands[4].yellowLimit
 assert(e.states[4].neutralQueue==0 and lim<=env+0.5 and lim>120+(best-K.queueKeep)*K.queueClose+5,'(a) out of the queue, +'..SK.rel..' km/h at most: '..lim..' / '..env)
 assert(e.states[5].neutralQueue==4,'(b) the car behind still queues')
 put(f,L,4,1960,100); put(f,L,3,1950,130); F.tick(e,f,0.5)
 assert(e.states[3].neutralQueue==4 and e.commands[3].yellowLimit<=100+1e-6,'(c) tucked in ahead: target again ('..e.commands[3].yellowLimit..')')
 put(f,L,4,1951,130); put(f,L,3,1950,130); F.tick(e,f,0.3)
 assert(e.states[3].neutralQueue~=4,'(d) alongside: never a target')
end

-- Fin du dédoublement : drapeau rouge, voiture de sécurité indisponible, incident en piste, délai maximal, aux stands,
-- sans progrès.
tests.LOCK_SC_UNLAP_ABORT_164=function()
 local o={z={[2]=1975,[4]=1950,[3]=1925,[6]=1900,[5]=1875},lapped={[4]=true,[6]=true}}
 local function clean(e,f,t) for j=1,f.count do assert(not t.cars[j].unlapOut and not t.cars[j].scFree and not Incidents.unlapping(t,j),'cleared '..j) end; assert(t.unlapCar==0) end
 local e,f,t=running(o)
 t.red=true; t.redSince=e.time; t.redMax=1e6; frames(e,f,1)
 assert(count(e,'voiture de securite: dedoublement interrompu (drapeau rouge)')==1,'(a) red flag'); clean(e,f,t)
 e,f,t=running(o)
 -- Neutralisation encore due (sinon la FCY de repli est levée dans la même image : « fin de neutralisation »).
 t.neutralUntil=e.time+100; f.cars[SC].kmh=0; f.cars[SC].speed=0; F.tick(e,f,K.scStuckTime+0.5)
 assert(count(e,'voiture de securite: dedoublement interrompu (voiture de securite indisponible)')==1,'(b) Safety Car unavailable'); clean(e,f,t)
 local L
 e,f,t,L=running(o)
 f.cars[7].pit=false; f.cars[7].inPitBox=false; put(f,L,7,6000,100); F.tick(e,f,0.2); put(f,L,7,6000,0); F.tick(e,f,K.obstacleTime+1)
 assert(t.unlapCar==4,'(c) the allowed car finishes')
 glide(e,f,L,4,2010,140); F.tick(e,f,0.2)
 assert(count(e,'Driver_4 s est dedoublee (1 / 2)')==1 and count(e,'voiture de securite: dedoublement arrete (incident en piste), 1 attardee(s) restent dans la file')==1 and t.unlapState=='done','(c) incident on track: stopped')
 e,f,t,L=running(o)
 t.unlapUntil=e.time; glide(e,f,L,4,2010,140); F.tick(e,f,0.2)
 assert(count(e,'dedoublement arrete (delai maximal), 1 attardee(s)')==1,'(d) time limit')
 e,f,t=running(o)
 f.cars[4].pit=true; frames(e,f,2)
 assert(count(e,'voiture de securite: Driver_4 ne se dedouble pas (aux stands), reste dans la file')==1,'(e) in the pits')
 e,f,t=running(o)
 t.unlapAt=e.time-SK.passMax-0.1; frames(e,f,2)
 assert(count(e,'Driver_4 ne se dedouble pas (delai depasse)')==1 and t.unlapCar==6,'(f) no progress: next one')
end

-- Rentrée à la fin du tour suivant : au-delà du délai maximal de la neutralisation, jamais pendant le dédoublement ; au
-- plus SK.doneLaps tours ; liste toute écartée : rentre ce tour ; un seul dédoublement par sortie ; libération gardée.
tests.LOCK_SC_UNLAP_NEXT_LAP_164=function()
 local e,f,t,L=running()
 t.neutralSince=e.time-K.neutralMax-1
 for _=1,60 do F.tick(e,f,1/60); assert(t.safetyPhase=='out','never in while unlapping') end
 glide(e,f,L,4,2010,140); F.tick(e,f,0.2); assert(t.unlapState=='done','done')
 F.tick(e,f,2); assert(t.safetyPhase=='out','beyond the neutralisation limit: still waits for its line')
 shift(f,L,7990); frames(e,f,1); shift(f,L,20); frames(e,f,2)
 assert(t.safetyPhase=='in','in at the line')
 -- (d) Nouvel incident après la rentrée (« reste en piste »), puis dégagé : aucun second dédoublement.
 e,f,t,L=running(); glide(e,f,L,4,2010,140); F.tick(e,f,0.2)
 shift(f,L,7990); frames(e,f,1); shift(f,L,20); frames(e,f,2); assert(t.safetyPhase=='in','(d) in')
 put(f,L,4,f.cars[SC].z-150,100)
 f.cars[7].pit=false; f.cars[7].inPitBox=false; put(f,L,7,6000,100); F.tick(e,f,0.2); put(f,L,7,6000,0); F.tick(e,f,16)
 assert(count(e,'voiture de securite: reste en piste')==1 and t.safetyPhase=='out','(d) stays out')
 f.cars[7].pit=true; f.cars[7].inPitBox=true
 for _=1,90 do F.tick(e,f,1); if t.safetyPhase~='out' then break end end
 assert(t.safetyPhase=='in' and count(e,'file formee')==1,'(d) one unlapping per deployment')
 -- (b) Ligne jamais franchie : SK.doneLaps tours au plus.
 local e2,f2,t2,L2=running()
 glide(e2,f2,L2,4,2010,140); F.tick(e2,f2,0.2); assert(t2.unlapState=='done')
 t2.unlapDoneAt=e2.time-SK.doneLaps*SCLAP-0.1; frames(e2,f2,3)
 assert(t2.safetyPhase=='in','(b) in after '..SK.doneLaps..' Safety Car laps')
 -- (c) Toutes écartées : rentre ce tour (une image après la ligne du journal).
 local e3,f3,t3=scene(); decide(e3,f3,t3); f3.cars[4].pit=true
 local found=false
 for _=1,(SK.settle+1)*60 do F.tick(e3,f3,1/60); if count(e3,'dedoublement termine (0 / 1), rentre ce tour')==1 then found=true; break end end
 assert(found and count(e3,'Driver_4 ne se dedouble pas (aux stands)')==1,'(c) nobody to unlap')
 frames(e3,f3,1); assert(t3.safetyPhase=='in','(c) in at the next frame')
 -- (e) Nouvel incident majeur pendant l'attente de la ligne : libération gardée, rentrée au premier moment permis ; au
 -- vert, les dédoublées encore loin libérées par la règle existante.
 local e4,f4,t4,L4=running()
 glide(e4,f4,L4,4,2010,140); F.tick(e4,f4,0.2)
 f4.cars[7].pit=false; f4.cars[7].inPitBox=false; put(f4,L4,7,6000,100); F.tick(e4,f4,0.2); put(f4,L4,7,6000,0); F.tick(e4,f4,16)
 assert(e4.time<t4.neutralUntil,'neutralisation extended')
 shift(f4,L4,7990); frames(e4,f4,1); shift(f4,L4,20); frames(e4,f4,1)
 assert(t4.unlapRelease and t4.safetyPhase=='out','(e) release kept while the incident holds it')
 f4.cars[7].pit=true; f4.cars[7].inPitBox=true
 for _=1,60*60 do F.tick(e4,f4,1/60); if t4.safetyPhase~='out' then break end end
 assert(t4.safetyPhase=='in' and e4.time>=t4.neutralUntil and e4.time-t4.neutralUntil<=3/60,'(e) in at the first allowed frame')
 put(f4,L4,4,f4.cars[SC].z+400,140); f4.cars[SC].pit=true; frames(e4,f4,2)
 assert(count(e4,'drapeau vert: voiture de securite aux stands')==1 and count(e4,'reprise: 1 voiture(s) hors de la file')==1,'(e) green: the unlapped car races at once')
end

-- Arrivée neutralisée : dernier tour sous voiture de sécurité.
tests.LOCK_SC_FINISH_164=function()
 local e,f,t,L=scene({sessionLaps=10,leaderLaps=8,lapped={}})
 f.leaderLaps=9; frames(e,f,1)
 assert(t.scFinal and t.safetyPhase=='in' and t.messageKind=='scFinish' and count(e,'voiture de securite: dernier tour, rentre sans relance (arrivee neutralisee)')==1,'last lap: in without a restart')
 local serial,green=t.restartSerial or 0,t.greenUntil
 f.cars[SC].pit=true; F.tick(e,f,0.5)
 assert(t.safetyPhase=='parking' and t.neutral and (t.restartSerial or 0)==serial and t.greenUntil==green and not t.restart and count(e,'drapeau vert')==0 and t.messageKind~='green','Safety Car in the pits: no green flag')
 t.neutralSince=e.time-K.neutralMax-1; F.tick(e,f,1); assert(t.neutral,'beyond the neutralisation limit: held')
 f.cars[7].pit=false; f.cars[7].inPitBox=false; put(f,L,7,6000,100); F.tick(e,f,0.2); put(f,L,7,6000,0); F.tick(e,f,16)
 assert(count(e,'reste en piste')==0 and t.safetyPhase~='out' and t.safetyPhase~='in' and t.neutral,'new incident: the Safety Car stays in')
 F.tick(e,f,0.5)
 assert(e.panel.decided=='scFinish' and e.panel.kind=='sc','panel')
 local a=f.cars[2]
 local want=math.max(K.trafficMinSpeed,Delta.reference(e.delta,e.states,2,Delta.bin(a.spline,e.delta.bins),e.run.multiClass==true,K.scPacePct,K.scNominalKmh)*3.6)
 local cap,yellow=Incidents.cap(t,f,2,e.run,e.delta,e.states,0)
 assert(yellow and math.abs(cap-want)<1e-6 and cap>K.scNominalKmh-K.scMergeMargin,'queue at the Safety Car pace, never 90 km/h: '..cap)
 assert(e.delta.course.kind=='sc','player delta as behind the Safety Car')
end

-- Damier : la tenue continue, voitures arrivées exemptées, jamais de drapeau rouge ; levée sans vert quand toutes
-- sont passées, puis le moteur s'arrête.
tests.LOCK_SC_FINISH_FLAG_164=function()
 local o={sessionLaps=10,leaderLaps=8,lapped={},z={[2]=1950,[3]=1930,[4]=1910,[5]=1890,[1]=1870}}
 local function flagged(oo)
  local e,f,t,L=scene(oo or o)
  f.leaderLaps=9; frames(e,f,1); f.cars[SC].pit=true; f.cars[SC].inPitBox=true; F.tick(e,f,0.5)
  f.finished=true; f.cars[2].finished=true; f.cars[1].finished=true; F.tick(e,f,0.2)
  return e,f,t,L
 end
 local e,f,t,L=flagged()
 local n0=e.penalties.count; local serial=t.restartSerial or 0
 assert(e.guard=='ready' and t.neutral and t.scFinal and count(e,'arrivee neutralisee: drapeau a damier, 3 voiture(s) encore en piste')==1,'held after the leader flag')
 assert(e.states[3].neutralQueue==2,'Driver_2 (finished) still a queue target')
 put(f,L,3,1970,120); put(f,L,2,1950,60); F.tick(e,f,0.5)
 assert(e.penalties.ai.owe[3]==nil and count(e,'sanction IA')==0,'passing a finished car: no sanction')
 put(f,L,5,1890,60); put(f,L,1,1900,120); F.tick(e,f,0.2); put(f,L,1,1915,120); F.tick(e,f,0.3)
 assert(e.penalties.count==n0 and not e.penalties.stopPending,'finished player: no penalty')
 -- Une voiture encore en piste hors incident (Driver_6) : la tenue dure pendant que trois autres bloquent la piste.
 local e2,f2,t2=flagged({sessionLaps=10,leaderLaps=8,lapped={},z={[2]=1950,[3]=1930,[4]=1910,[5]=1890,[6]=1880,[1]=1870}})
 F.block(f2,{3,4,5},3000); F.tick(e2,f2,K.redIncidentStill+1)
 assert(t2.scFinal and t2.redCount>=e2.run.redFlagCars and not t2.red,'never a red flag after the chequered flag')
 for i=3,5 do f.cars[i].finished=true end; frames(e,f,1)
 assert(not t.neutral and not t.scFinal and count(e,'arrivee neutralisee: toutes les voitures ont franchi la ligne')==1 and t.messageKind~='green' and (t.restartSerial or 0)==serial,'lifted without a green flag')
 frames(e,f,1); assert(e.guard=='finished' and t.safetyPhase=='parked','then the app stops as before')
end

-- Tenue après le damier : au plus SK.holdLaps tour à K.scNominalKmh.
tests.LOCK_SC_FINISH_HOLD_164=function()
 local e,f,t=scene({sessionLaps=10,leaderLaps=8,lapped={}})
 f.leaderLaps=9; frames(e,f,1); f.cars[SC].pit=true; F.tick(e,f,0.5)
 f.finished=true; for i=2,6 do f.cars[i].finished=i~=3 end; F.tick(e,f,0.2)
 assert(t.neutral,'held')
 t.scFlagAt=e.time-SK.holdLaps*SCLAP-0.1; frames(e,f,1)
 assert(not t.neutral and count(e,'arrivee neutralisee: levee apres')==1 and count(e,'(1 voiture(s) encore en piste)')==1,'lifted after one Safety Car lap')
 frames(e,f,1); assert(e.guard=='finished','app stops')
end

-- Course au temps : accrochée au temps écoulé, tour de plus d'AC une fois ; format inconnu : jamais.
tests.LOCK_SC_FINISH_TIMED_164=function()
 local e,f,t=scene({timed=true,sessionLaps=0,left=30,lapped={}})
 frames(e,f,2); assert(not t.scFinal,'30 s left: not yet')
 f.left=0; frames(e,f,1); assert(t.scFinal,'time over: neutralised finish')
 f.leaderLaps=f.leaderLaps+1; F.tick(e,f,SK.finalCross+0.2)
 assert(count(e,'arrivee neutralisee: tour de plus apres la fin du temps, neutralisation tenue')==1 and t.neutral and t.scFinal and count(e,'drapeau vert')==0,'extra lap held')
 f.leaderLaps=f.leaderLaps+1; F.tick(e,f,SK.finalCross+0.2)
 assert(count(e,'arrivee neutralisee annulee (pas de drapeau a damier au passage du meneur), relance normale')==1 and not t.scFinal,'second crossing without a flag: cancelled')
 local e2,f2,t2=scene({sessionLaps=0,leaderLaps=29,lapped={}})
 for _=1,10 do frames(e2,f2,6); assert(not t2.scFinal,'unknown format: never') end
end

-- Annulation sur preuve : pas de damier au passage du meneur, ou borne lointaine ; relance normale par les stands.
tests.LOCK_SC_FINISH_GIVEUP_164=function()
 local function latched()
  local e,f,t=scene({sessionLaps=10,leaderLaps=8,lapped={}})
  f.leaderLaps=9; frames(e,f,1); f.cars[SC].pit=true; F.tick(e,f,0.5); assert(t.safetyPhase=='parking')
  return e,f,t
 end
 local e,f,t=latched(); local serial=t.restartSerial or 0
 f.leaderLaps=10; F.tick(e,f,SK.finalCross+0.2)
 assert(count(e,'arrivee neutralisee annulee (pas de drapeau a damier au passage du meneur), relance normale')==1 and not t.scFinal,'(a) no flag at the line: cancelled')
 frames(e,f,2)
 assert((t.restartSerial or 0)==serial+1 and count(e,'drapeau vert: voiture de securite aux stands')==1 and t.restart,'(a) green through the Safety Car path, no overtaking to the line')
 local e2,f2,t2=latched()
 t2.scFinalAt=e2.time-SK.finalMax*math.max(SCLAP,t2.leadLapDur)-0.1; frames(e2,f2,1)
 assert(count(e2,'arrivee neutralisee annulee (delai depasse), relance normale')==1 and not t2.scFinal,'(b) far bound')
end

-- Voiture de sécurité appelée pendant le dernier tour : elle ne sort pas, file jusqu'au damier, levée sans vert.
tests.LOCK_SC_FINISH_CALL_164=function()
 local e,f,t=scene({sessionLaps=10,leaderLaps=9,lapped={},call=true})
 for _=1,60 do F.tick(e,f,0.5); assert(t.safetyPhase~='exit' and t.safetyPhase~='out' and t.safetyPhase~='place','never deployed') end
 assert(t.safetyPhase=='parked' and t.scFinal and count(e,'voiture de securite: dernier tour, reste aux stands (arrivee neutralisee)')==1,'stays in the pits')
 local a=f.cars[2]
 local want=math.max(K.trafficMinSpeed,Delta.reference(e.delta,e.states,2,Delta.bin(a.spline,e.delta.bins),e.run.multiClass==true,K.scPacePct,K.scNominalKmh)*3.6)
 local cap=Incidents.cap(t,f,2,e.run,e.delta,e.states,0)
 assert(math.abs(cap-want)<1e-6 and cap>K.scNominalKmh-K.scMergeMargin,'Safety Car pace, no 90 km/h cap: '..cap)
 f.finished=true; for i=2,6 do f.cars[i].finished=true end; frames(e,f,2)
 assert(not t.neutral and count(e,'toutes les voitures ont franchi la ligne')==1 and count(e,'drapeau vert')==0,'lifted at the flag, no green')
end

-- Zigzags derrière la voiture de sécurité : seulement pneus froids (plus de K.outLapTempMargin °C sous l'idéale) ;
-- donnée inconnue : comme avant ; tour de formation inchangé ; jamais pendant un dédoublement.
tests.LOCK_SC_WEAVE_TYRES_164=function()
 assert(SK.settle>=K.weaveAmp/K.formOffsetRate,'weaving fades out before the first unlap')
 local e,f=F.scene('C',5); e.profiles.C.startRealism=true; E.changed(e); F.tick(e,f,0.2)
 local t=e.antics; local inc=e.incidents; local now=e.time
 local function tyres(temp,opt,known) for i=2,5 do local a=f.cars[i]; a.wearKnown=known~=false; a.tyreTemp={temp,temp,temp,temp}; a.tyreOptimum={opt,opt,opt,opt} end end
 local function sc(phase,relaunch) inc.neutral=true; inc.neutralMode='sc'; inc.safetyPhase=phase or 'out'; inc.relaunch=relaunch==true; inc.formation=false; inc.unlapState='none' end
 local function run(n) local peak,jump=0,0; for _=1,n do now=now+1/60; local before=e.states[3].formOffset or 0; Antics.weave(t,e,f,now,1/60); local v=e.states[3].formOffset or 0; peak=math.max(peak,math.abs(v)); jump=math.max(jump,math.abs(v-before)) end; return peak,jump end
 sc('out'); tyres(60,90); assert(run(240)>0,'(a) cold tyres: weave')
 tyres(90,90); local _,jump=run(240)
 assert(e.states[3].formOffset==nil and jump<=K.formOffsetRate/60+1e-9,'(b) warm: back to the line smoothly')
 tyres(87,90); assert(run(240)==0,'(c) 3 °C under: no weave')
 tyres(90,90,false); assert(run(240)>0,'(d) unknown: as before'); tyres(90,0); run(10); assert(run(240)>0,'(d) no optimum: as before')
 tyres(90,90); run(400)
 inc.neutral=false; inc.formation=true; local peak=run(240); assert(peak>0.4,'(e) formation lap unchanged: '..peak)
 inc.formation=false
 for _,ph in ipairs({'in','call'}) do sc(ph); tyres(60,90); run(60); assert(e.states[3].formOffset==nil,'(f) '..ph) end
 sc('out',true); run(60); assert(e.states[3].formOffset==nil,'(f) relaunch')
 sc('out'); inc.unlapState='run'; tyres(60,90); assert(run(240)==0,'(g) never while unlapping')
 inc.unlapState='none'
end

-- Textes : langues, journal traduit, README.
tests.SC_PROCEDURES_TEXTS_164=function()
 local Lf,Le=require('src/lang'),require('src/lang_en')
 for _,L in ipairs({Lf,Le}) do
  for _,k in ipairs({'scUnlap','scFinish'}) do
   assert(L.messages[k] and L.flagShort[k] and L.flagDetails[k] and L.flagExplain[k],'texts '..k)
   assert(string.format(L.flagShort[k],0,0) and string.format(L.flagDetails[k],0,0),'panel formats '..k)
  end
  assert(string.format(L.messages.scUnlap[2],'Driver_4'):find('Driver_4',1,true) and string.format(L.messages.scFinish[2],0,0),'message formats')
 end
 local J=require('src/journal')
 local lines={
  {string.format('voiture de securite: file formee, %d attardee(s) autorisee(s) a se dedoubler une par une',2),'Safety Car: queue formed, 2 lapped car(s) allowed to unlap one at a time'},
  {string.format('voiture de securite: dedoublement non lance (%s, %d attardee(s))','course multi-classe',1),'Safety Car: unlapping not started (multi-class race, 1 lapped car(s))'},
  {'voiture de securite: dedoublement non lance (fin de course proche, 1 attardee(s))','Safety Car: unlapping not started (race end close, 1 lapped car(s))'},
  {'voiture de securite: dedoublement non lance (incident en piste, 1 attardee(s))','Safety Car: unlapping not started (incident on track, 1 lapped car(s))'},
  {'voiture de securite: Driver_4 autorisee a se dedoubler (1 / 2)','Safety Car: Driver_4 allowed to unlap (1 / 2)'},
  {'voiture de securite: Driver_4 s est dedoublee (1 / 2)','Safety Car: Driver_4 has unlapped (1 / 2)'},
  {'voiture de securite: Driver_4 ne se dedouble pas (hors course), reste dans la file','Safety Car: Driver_4 does not unlap (out of the race), stays in the queue'},
  {'voiture de securite: Driver_4 ne se dedouble pas (aux stands), reste dans la file','Safety Car: Driver_4 does not unlap (in the pits), stays in the queue'},
  {'voiture de securite: Driver_4 ne se dedouble pas (accidentee), reste dans la file','Safety Car: Driver_4 does not unlap (crashed), stays in the queue'},
  {'voiture de securite: Driver_4 ne se dedouble pas (delai depasse), reste dans la file','Safety Car: Driver_4 does not unlap (delay exceeded), stays in the queue'},
  {'voiture de securite: dedoublement arrete (incident en piste), 1 attardee(s) restent dans la file','Safety Car: unlapping stopped (incident on track), 1 lapped car(s) stay in the queue'},
  {'voiture de securite: dedoublement arrete (delai maximal), 1 attardee(s) restent dans la file','Safety Car: unlapping stopped (time limit), 1 lapped car(s) stay in the queue'},
  {'voiture de securite: dedoublement termine (1 / 1), rentre au prochain passage de la ligne','Safety Car: unlapping over (1 / 1), in after its next line crossing'},
  {'voiture de securite: dedoublement termine (0 / 1), rentre ce tour','Safety Car: unlapping over (0 / 1), in this lap'},
  {'voiture de securite: dedoublement interrompu (drapeau rouge)','Safety Car: unlapping interrupted (red flag)'},
  {'voiture de securite: dedoublement interrompu (fin de neutralisation)','Safety Car: unlapping interrupted (end of the neutralisation)'},
  {'voiture de securite: dedoublement interrompu (voiture de securite indisponible)','Safety Car: unlapping interrupted (Safety Car unavailable)'},
  {'voiture de securite: dedoublement interrompu (dernier tour)','Safety Car: unlapping interrupted (last lap)'},
  {'voiture de securite: dedoublement interrompu (voiture de securite plus en piste)','Safety Car: unlapping interrupted (Safety Car no longer on track)'},
  {'voiture de securite: dernier tour, rentre sans relance (arrivee neutralisee)','Safety Car: last lap, in without a restart (neutralised finish)'},
  {'voiture de securite: dernier tour, reste aux stands (arrivee neutralisee)','Safety Car: last lap, stays in the pits (neutralised finish)'},
  {'arrivee neutralisee: voiture de securite aux stands, file jusqu au damier','neutralised finish: Safety Car in the pits, single file to the flag'},
  {'arrivee neutralisee: voiture de securite rappelee a son stand, file jusqu au damier','neutralised finish: Safety Car recalled to its pit box, single file to the flag'},
  {'arrivee neutralisee: tour de plus apres la fin du temps, neutralisation tenue','neutralised finish: extra lap after the time ran out, neutralisation held'},
  {'arrivee neutralisee annulee (pas de drapeau a damier au passage du meneur), relance normale','neutralised finish cancelled (no chequered flag when the leader crossed the line), normal restart'},
  {'arrivee neutralisee annulee (delai depasse), relance normale','neutralised finish cancelled (delay exceeded), normal restart'},
  {string.format('arrivee neutralisee: drapeau a damier, %d voiture(s) encore en piste',3),'neutralised finish: chequered flag, 3 car(s) still on track'},
  {'arrivee neutralisee: toutes les voitures ont franchi la ligne','neutralised finish: every car has crossed the line'},
  {string.format('arrivee neutralisee: levee apres %.0f s (%d voiture(s) encore en piste)',300.4,1),'neutralised finish: lifted after 300 s (1 car(s) still on track)'},
 }
 for _,pair in ipairs(lines) do local got=J.english(pair[1]); assert(got==pair[2],'translated: '..pair[1]..' -> '..tostring(got)) end
 local root=package.path:match('^([^;]+)/%?%.lua'); local file=assert(openFile(root..'/README.md','rb')); local text=file:read('*a'); file:close()
 assert(text:find('never leads the field through the pit lane',1,true) and text:find('weave only while their tyres are below working temperature',1,true),'README: new texts')
 assert(not text:find('They also weave behind the Safety Car.',1,true),'README: old sentence gone')
end

-- Lot 4 (course sprint), décisions restantes du pilote du 13 novembre.
local function race(laps,length)
 local e,f=F.scene('C',3); local p=e.run
 p.mandatoryStops=1; p.pitWindowOpenPct=20; p.pitWindowClosePct=95; p.pitCompoundChange=true; p.redFlagWork=true; p.pitMessage=true; p.pitTyres=true
 f.sessionLaps=laps; f.leaderLaps=0; f.timedRace=false; f.sessionMinutes=0; f.pitWindowStart=0; f.pitWindowEnd=0; f.started=true
 f.length=length or 10000
 for i=1,f.count do f.cars[i].bestLap=0 end
 return e,f,p
end
local function timed(minutes,length)
 local e,f,p=race(0,length); f.timedRace=true; f.sessionMinutes=minutes; f.left=minutes*60
 for i=1,f.count do f.cars[i].lap=0; f.cars[i].bestLap=0 end
 return e,f,p
end
local function laps(f,lap,best) for i=2,f.count do f.cars[i].lap=lap; f.cars[i].bestLap=best+(i-2)*10 end end
local function kinds(said,kind) local n=0; for _,s in ipairs(said) do if s[1]==kind then n=n+1 end end return n end
local function step(t,f,e,p,now,said) Pits.update(t,f,e.commands,p,'C',now,1,said and function(kind,a,b) said[#said+1]={kind,a,b} end or nil,false) end
local function journal(t) local lines={}; t.note=function(_,text) lines[#lines+1]=text end; return lines end
local function has(lines,text) for _,l in ipairs(lines) do if l:find(text,1,true) then return true end end return false end

-- (a) Course au temps encore indécise : fenêtre « en attente » (jamais ouverte, aucun appel) jusqu'à la décision (une
-- voiture à 2 tours), au plus jusqu'à sa fermeture : la décision se prend avant l'ouverture.
tests.LOCK_SPRINT_TIMED_WAIT_164=function()
 -- 15 min, 5 km, tours de 110 s : fenêtre atteinte (33 %) au 1er tour, sprint au 2e (45 km).
 local e,f,p=timed(15,5000); local t=Pits.new(); local said={}
 step(t,f,e,p,100,said); laps(f,1,110); f.left=600; step(t,f,e,p,101,said)
 assert(t.sprint==nil and t.state=='pending' and not t.opened and kinds(said,'pitOpen')==0,'undecided: window held pending ('..t.state..')')
 for _,i in ipairs({2,3}) do assert(not e.commands[i].rulePit,'no AI called while undecided') end
 laps(f,2,110); f.left=500; step(t,f,e,p,102,said)
 assert(t.sprint==true and t.state=='off' and not t.opened and kinds(said,'pitOpen')==0 and kinds(said,'pitSprint')==1,'decided before any opening: sprint')
 -- 50 km : plus de 100 km : fenêtre ouverte à l'image de la décision.
 local e2,f2,p2=timed(15,50000); local t2=Pits.new(); local said2={}; local lines2=journal(t2)
 step(t2,f2,e2,p2,100,said2); laps(f2,1,110); f2.left=600; step(t2,f2,e2,p2,101,said2)
 assert(t2.state=='pending' and not t2.opened,'long race, undecided: pending')
 laps(f2,2,110); f2.left=500; step(t2,f2,e2,p2,102,said2)
 assert(t2.sprint==false and t2.state=='open' and kinds(said2,'pitOpen')==1 and has(lines2,'arret obligatoire maintenu: course de 450.0 km'),'more than 100 km: opens at the decision')
 -- Jamais estimable (aucune voiture à 2 tours) : en attente au plus jusqu'à la fermeture, jamais une fenêtre fermée sans
 -- avoir été ouverte prise pour un arrêt manqué.
 local e3,f3,p3=timed(15,5000); local t3=Pits.new()
 step(t3,f3,e3,p3,100); laps(f3,1,110); f3.left=600; step(t3,f3,e3,p3,101); assert(t3.state=='pending')
 f3.left=10; step(t3,f3,e3,p3,102)
 assert(t3.sprint==nil and t3.state=='closed' and not t3.opened and not t3.justClosed,'never estimable: closed, never opened')
end

-- (b) Estimation au tour de référence × K.sprintLapShare (0,97) : un rythme qui s'améliore après le 2e tour ne fait pas
-- passer une course de plus de 100 km pour un sprint ; le tour retenu reste le meilleur tour brut.
tests.LOCK_SPRINT_LAP_MARGIN_164=function()
 assert(K.sprintLapShare==0.97,'3 % margin')
 local e,f,p=timed(30,4900); local t=Pits.new(); local lines=journal(t)
 laps(f,2,92); f.left=1600; step(t,f,e,p,100)
 assert(t.sprint==false and math.abs(t.sprintKm-102.9)<1e-9 and t.sprintLap==92 and has(lines,'arret obligatoire maintenu: course de 102.9 km (plus de 100 km)'),'92 s on 4.9 km: 21 laps, 102.9 km, stop kept ('..t.sprintKm..')')
 local e2,f2,p2=timed(30,4700); local t2=Pits.new()
 laps(f2,2,90); f2.left=1600; step(t2,f2,e2,p2,100)
 assert(t2.sprint==true and math.abs(t2.sprintKm-98.7)<1e-9 and t2.sprintLap==90,'90 s on 4.7 km: still 98.7 km, sprint')
end

-- Relecture 164e (trois relecteurs indépendants, constats A1 à A11).
local Penalties=require('src/penalties')
local Lf,Le=require('src/lang'),require('src/lang_en')
-- Variante de scene : n voitures (joueur 1, voiture arrêtée n-1, voiture de sécurité n), longueur de piste, tour
-- supplémentaire, rappel à chaque image de l'attente (o.each). Rend e, f, t, L, sc, inc.
local function sceneX(o)
 local n=o.count or 8; local sc=n; local inc=n-1
 local e,f=F.scene('C',n); C.preset('Course','C',e.profiles.C); local p=e.profiles.C; p.neutralization='sc'
 E.changed(e); e.g.safetyCarModel='car_'..sc
 f.length=o.length or 10000
 f.sessionLaps=o.sessionLaps or 30; f.leaderLaps=o.leaderLaps or 10; f.timedRace=o.timed==true; f.left=o.left or 1000; f.extraLap=o.extraLap
 F.place(f,sc,0,0); f.cars[sc].pit=true; f.cars[sc].inPitBox=true
 local z=o.z or {[2]=1950,[3]=1930,[4]=1910,[5]=1890,[6]=1870}; local lapped=o.lapped or {}
 local order={}; local L={[sc]=11}
 for i=1,inc-1 do
  if z[i] then F.place(f,i,z[i],100); f.cars[i].lap=lapped[i] and 10 or 11; L[i]=f.cars[i].lap; order[#order+1]=i
  else f.cars[i].pit=true; f.cars[i].inPitBox=true end
 end
 table.sort(order,function(x,y) if (lapped[x] and 1 or 0)~=(lapped[y] and 1 or 0) then return not lapped[x] end return z[x]>z[y] end)
 for k,i in ipairs(order) do f.cars[i].position=k end
 local m=#order; for i=1,inc do if not z[i] then m=m+1; f.cars[i].position=m end end
 F.place(f,inc,o.incZ or 6000,0); f.cars[inc].lap=11; L[inc]=11
 local t=e.incidents
 for _=1,900 do F.tick(e,f,0.1); if o.each then o.each(e,f,t) end; if o.call and t.neutral or not o.call and t.safetyPhase=='exit' then break end end
 if o.call then assert(t.neutral,'neutralised'); return e,f,t,L,sc,inc end
 assert(t.safetyPhase=='exit','Safety Car released')
 f.cars[inc].pit=true; f.cars[inc].inPitBox=true
 F.place(f,sc,o.scZ or 2000,100); f.cars[sc].pit=false; f.cars[sc].inPitBox=false; f.cars[sc].lap=11
 F.tick(e,f,0.1); assert(t.safetyPhase=='out','Safety Car on track')
 return e,f,t,L,sc,inc
end

-- A1 : course au temps avec un tour supplémentaire : le dernier tour est celui qui suit le passage du meneur au temps
-- écoulé (jamais celui où le temps s'écoule) ; tour supplémentaire déjà compté à l'accrochage ; compté aussi dans les
-- tours restants du dédoublement ; temps écoulé sous drapeau vert, voiture de sécurité appelée pendant le tour en plus.
tests.LOCK_SC_FINISH_EXTRA_LAP_164=function()
 local e,f,t=scene({timed=true,sessionLaps=0,left=30,lapped={}})
 f.extraLap=true; frames(e,f,2); assert(not t.scFinal,'30 s left')
 f.left=0; frames(e,f,2)
 assert(not t.scFinal and t.safetyPhase=='out' and t.zeroLaps==f.leaderLaps,'time over with an extra lap: not the last lap yet')
 f.leaderLaps=f.leaderLaps+1; frames(e,f,1)
 assert(t.scFinal and t.safetyPhase=='in' and t.scExtra and count(e,'voiture de securite: dernier tour, rentre sans relance (arrivee neutralisee)')==1,'extra lap: the last lap')
 f.leaderLaps=f.leaderLaps+1; F.tick(e,f,SK.finalCross+0.2)
 assert(count(e,'tour de plus apres la fin du temps')==0 and count(e,'arrivee neutralisee annulee (pas de drapeau a damier au passage du meneur), relance normale')==1,'the extra lap is never counted twice')
 -- Tours restants du dédoublement : 3 tours de voiture de sécurité de temps, plus le tour supplémentaire.
 local e2,f2,t2=scene({timed=true,sessionLaps=0,left=3*SCLAP})
 f2.extraLap=true; decide(e2,f2,t2)
 assert(t2.unlapState=='run' and count(e2,'file formee, 1 attardee(s)')==1,'extra lap counted in the laps left')
 local e3,f3,t3=scene({timed=true,sessionLaps=0,left=3*SCLAP}); decide(e3,f3,t3)
 assert(t3.unlapState=='none' and count(e3,'dedoublement non lance (fin de course proche, 1 attardee(s))')==1,'witness without the extra lap')
 -- Temps écoulé sous drapeau vert, meneur dans le tour supplémentaire, puis voiture de sécurité appelée : dernier tour.
 local changed=false
 local e4,f4,t4=sceneX({timed=true,sessionLaps=0,left=0,extraLap=true,lapped={},call=true,each=function(_,ff,tt) if not changed and not tt.neutral and tt.zeroLaps==10 then ff.leaderLaps=11; changed=true end end})
 assert(changed,'time over noted under green, then the extra lap')
 frames(e4,f4,2)
 assert(t4.scFinal and t4.safetyPhase=='parked' and count(e4,'voiture de securite: dernier tour, reste aux stands (arrivee neutralisee)')==1,'called during the extra lap: stays in the pits')
end

-- A2 : rechargement de l'app pendant la fenêtre « en attente » d'une course au temps indécise : jamais « maintenu »
-- d'office (la règle de l'ancienne sauvegarde) ; décidée ensuite comme sans rechargement.
tests.LOCK_SPRINT_RELOAD_UNDECIDED_164=function()
 local e,f,p=timed(15,5000); local t=Pits.new()
 step(t,f,e,p,100); laps(f,1,110); f.left=600; step(t,f,e,p,101)
 assert(t.sprint==nil and t.state=='pending' and t.position>=t.open,'undecided, beyond the opening')
 local text=Pits.serialize(t,f.session)
 assert(text:find('\n*sprint,u',1,true),'undecided race saved ('..text..')')
 local t2=Pits.new(); local said={}; local lines=journal(t2); Pits.restore(t2,text,f.session)
 assert(t2.restoredSprint==nil and next(t2.restored)==nil and t2.restoredUndecided,'read as undecided, never as a decision or a car')
 step(t2,f,e,p,200,said)
 assert(t2.sprint==nil and t2.state=='pending' and not t2.opened,'reload: still undecided ('..tostring(t2.sprint)..')')
 laps(f,2,110); f.left=500; step(t2,f,e,p,201,said)
 assert(t2.sprint==true and t2.state=='off' and kinds(said,'pitSprint')==1 and kinds(said,'pitOpen')==0,'then a sprint after 2 laps')
 assert(not has(lines,'distance inconnue'),'never kept as unknown')
 -- Autre session ou redémarrage : règle de l'ancienne sauvegarde, comme avant.
 local e3,f3,p3=timed(15,5000); local t3=Pits.new(); Pits.restore(t3,text,f3.session); Pits.forget(t3)
 assert(not t3.restoredUndecided,'restart: forgotten')
 laps(f3,1,110); f3.left=600; step(t3,f3,e3,p3,100)
 assert(t3.sprint==false and t3.state=='open','restart: old rule, stop kept')
end

-- A3 : course au temps sans meilleur tour exploitable (ancien CSP, tour de moins de 20 s) : arrêt maintenu, distance
-- inconnue, dès que le meneur a bouclé K.sprintLapsSeen+1 tours (avant : fenêtre « en attente » jusqu'à sa fermeture,
-- aucun appel, aucun message, aucune pénalité).
tests.LOCK_SPRINT_TIMED_NO_BEST_164=function()
 for _,best in ipairs({0,5}) do
  local e,f,p=timed(15,5000); local t=Pits.new(); local lines=journal(t); local said={}
  step(t,f,e,p,100,said); laps(f,1,best); f.leaderLaps=1; f.left=600; step(t,f,e,p,101,said)
  assert(t.sprint==nil and t.state=='pending','one lap: undecided')
  laps(f,2,best); f.leaderLaps=2; f.left=500; step(t,f,e,p,102,said)
  assert(t.sprint==nil and t.state=='pending','two laps: still waiting for a lap time')
  laps(f,3,best); f.leaderLaps=3; f.left=400; step(t,f,e,p,103,said); step(t,f,e,p,104,said); step(t,f,e,p,105,said)
  assert(t.sprint==false and t.state=='open' and t.opened and kinds(said,'pitOpen')==1,'best '..best..' s: window opened')
  local n=0; for _,l in ipairs(lines) do if l:find('arret obligatoire maintenu: distance inconnue avant l ouverture de la fenetre',1,true) then n=n+1 end end
  assert(n==1,'unknown distance said once ('..n..')')
 end
end

-- A4 : ouverture retardée par la décision (course au temps de plus de 100 km) : appels étalés depuis l'ouverture réelle ;
-- annonce sans objet si l'arrêt obligatoire du joueur est déjà fait ; arrêts de stratégie non retenus tant que la
-- fenêtre attend au-delà de son ouverture.
tests.LOCK_SPRINT_DELAYED_OPEN_164=function()
 local e,f,p=timed(15,50000); local t=Pits.new(); local said={}
 step(t,f,e,p,100,said); laps(f,1,110); f.left=600; step(t,f,e,p,101,said); assert(t.state=='pending')
 laps(f,2,110); f.left=500; step(t,f,e,p,102,said)
 assert(t.sprint==false and t.state=='open' and math.abs(t.openedPos-t.position)<1e-9,'opened late, at the decision')
 local old=0
 for _,i in ipairs({2,3}) do
  local u=U.unit(1,i,K.pitSalt)
  local atNew=t.position+(t.close-t.position)*K.pitSpread*u
  local atOld=t.open+(t.close-t.open)*K.pitSpread*u
  if t.position>=atOld then old=old+1 end
  assert(e.commands[i].rulePit==(t.position>=atNew),'AI '..i..' called from the real opening')
 end
 assert(old>0,'witness: called at once from the set opening')
 -- Arrêt du joueur compté pendant l'attente : aucune annonce « fenêtre ouverte » (journal gardé).
 local e2,f2,p2=timed(15,50000); local t2=Pits.new(); local said2={}; local lines2=journal(t2)
 step(t2,f2,e2,p2,100,said2); laps(f2,1,110); f2.left=600; step(t2,f2,e2,p2,101,said2)
 t2.cars[1].windowStops=1
 laps(f2,2,110); f2.left=500; step(t2,f2,e2,p2,102,said2)
 assert(t2.opened and kinds(said2,'pitOpen')==0 and has(lines2,'fenetre d arret ouverte'),'player stop already made: no window message')
end
local function worn(a,w) a.wearKnown=true; a.tyreWear={w,w,w,w}; a.tyreKm={10,10,10,10}; a.tyreTemp={90,90,90,90}; a.tyreOptimum={90,90,90,90} end
tests.LOCK_SPRINT_DELAYED_HOLD_164=function()
 local function strat(share)
  local e,f=F.scene('C',4)
  f.sessionLaps=0; f.leaderLaps=2; f.timedRace=true; f.sessionMinutes=30; f.left=1800*share; f.started=true; f.fuelRate=1
  for i=1,f.count do f.cars[i].lap=2; f.cars[i].bestLap=0 end
  e.strategy.wearTrust='trusted'
  e.p.mandatoryStops=1; e.p.pitWindowOpenPct=20; e.p.pitWindowClosePct=95; E.changed(e)
  F.tick(e,f,1/60)
  worn(f.cars[2],0.5)
  local c=e.strategy.cars[2]; c.lap=2; c.lapWear=0.5; c.wearRate=0.05; c.wearLaps=3; c.planned=true; c.stops=1; c.nextLap=2; c.limit='tyres'
  F.tick(e,f,0.2)
  return e,f
 end
 local e=strat(0.6)
 assert(e.pits.state=='pending' and e.pits.sprint==nil and e.pits.position>=e.pits.open,'undecided, beyond the opening')
 assert(e.strategy.cars[2].wanted and count(e,'arret retenu jusqu a l ouverture de la fenetre obligatoire')==0,'the stop would count: never held')
 local e2=strat(0.9)
 assert(e2.pits.state=='pending' and e2.pits.position<e2.pits.open and not e2.strategy.cars[2].wanted and count(e2,'arret retenu jusqu a l ouverture de la fenetre obligatoire')==1,'witness: held before the opening')
end

-- A5 : multi-classe : classes de toutes les voitures classées, joueur compris, voiture de sécurité exclue.
tests.LOCK_SC_UNLAP_CLASSES_164=function()
 local function classes(patterns,set)
  local e,f=F.scene('C',8); C.preset('Course','C',e.profiles.C); e.profiles.C.classPatterns=patterns or ''; E.changed(e)
  F.tick(e,f,0.1); assert(e.run.multiClass==true,'multi-class setting on')
  if set then set(e) end
  e.classes.nextAt=0; F.tick(e,f,0.1)
  if set then set(e) end
  F.tick(e,f,0.1)
  return e.incidents.classes
 end
 assert(classes('car_:2')==1,'every car in class 2 (pattern): one class')
 assert(classes('car_1:2,car_:1')==2,'the player alone in his class: two classes')
 assert(classes(nil,function(e) for i=1,8 do e.states[i].class=1; e.states[i].classified=true end; e.states[1].class=2 end)==2,'player alone, recognised from the pace: two classes')
 assert(classes(nil,function(e) for i=1,8 do e.states[i].class=1; e.states[i].classified=true end end)==1,'one class')
 assert(classes(nil,function(e) e.states[3].class=2; e.states[3].classified=true end)==2,'a second class recognised from the pace: a faster one exists')
end

-- A6 : arrivée neutralisée annulée, voiture de sécurité déjà rappelée en piste : drapeau vert aussitôt, avec la règle de
-- reprise (avant : vert sans règle « jusqu'à la ligne », plus tard, sans voiture de sécurité devant la file).
tests.LOCK_SC_FINISH_RECALLED_GREEN_164=function()
 local e,f,t,L=scene({sessionLaps=10,leaderLaps=8,lapped={}})
 f.leaderLaps=9; frames(e,f,1); assert(t.scFinal and t.safetyPhase=='in')
 shift(f,L,7990); frames(e,f,1); shift(f,L,20); frames(e,f,1)
 assert(t.safetyPhase=='parked' and not f.cars[SC].pit and count(e,'arrivee neutralisee: voiture de securite rappelee a son stand, file jusqu au damier')==1,'line crossed: recalled on track')
 local serial=t.restartSerial or 0
 f.leaderLaps=10; F.tick(e,f,SK.finalCross+0.2)
 assert(count(e,'arrivee neutralisee annulee (pas de drapeau a damier au passage du meneur), relance normale')==1 and not t.scFinal,'cancelled')
 assert(not t.neutral and (t.restartSerial or 0)==serial+1 and count(e,'drapeau vert: arrivee neutralisee annulee, voiture de securite rappelee a son stand')==1,'green at once')
 assert(count(e,'drapeau vert: fin de neutralisation')==0,'never the plain end of neutralisation')
 if e.run.restartOvertake=='scIn' then assert(t.messageKind=='green','green message') else assert(t.restart,'no overtaking until the line') end
end

-- A7 : texte de l'arrivée neutralisée neutre (voiture de sécurité appelée au dernier tour : elle n'est jamais sortie).
tests.LOCK_SC_FINISH_TEXT_164=function()
 assert(Lf.messages.scFinish[2]=='Dernier tour sous voiture de sécurité : arrivée en file, sans dépassement.','fr message')
 assert(Le.messages.scFinish[2]=='Last lap under the Safety Car: finish in single file, no overtaking.','en message')
 for _,s in ipairs({Lf.messages.scFinish[2],Lf.flagDetails.scFinish}) do assert(not s:find('rentre',1,true),'fr: '..s) end
 for _,s in ipairs({Le.messages.scFinish[2],Le.flagDetails.scFinish}) do assert(not s:find('comes in',1,true),'en: '..s) end
end

-- A8 : file plus longue qu'un demi-tour (circuit court) : une voiture du même tour loin derrière le meneur n'est jamais
-- prise pour une attardée (écart pris le long de la file).
tests.LOCK_SC_UNLAP_QUEUE_GAP_164=function()
 local z={}; for i=2,10 do z[i]=1420-(i-2)*140 end
 local e,f,t=sceneX({count=12,length=1600,z=z,incZ=100,scZ=1440})
 decide(e,f,t)
 assert(t.safetyPhase=='in' and t.unlapState=='none' and count(e,'dedoublement')==0,'same lap, far behind in the queue: never lapped')
 local L={lap=11,spline=0.9,lapValid=true,splineValid=true}
 local function car(lap,spline) return {lap=lap,spline=spline,lapValid=true,splineValid=true} end
 assert(Incidents.lapsDown(L,car(11,0.3),0.6)==0 and Incidents.lapsDown(L,car(11,0.3))==1,'same lap 0.6 lap behind: 0 along the queue (1 on the lap circle)')
 assert(Incidents.lapsDown(L,car(10,0.3),0.6)==1 and Incidents.lapsDown(car(11,0.30),car(10,0.35),-0.05)==1,'lapped behind or ahead in the queue: 1')
end

-- A9 : arrivée neutralisée déclenchée pendant la sortie de la voiture de sécurité : ramenée à son stand ; ni en tête de la
-- file ni en train de rentrer, elle n'est jamais une cible de la file et la doubler n'est pas une faute.
tests.LOCK_SC_FINISH_DURING_EXIT_164=function()
 local e,f,t,L=scene({sessionLaps=10,leaderLaps=8,lapped={},call=true})
 for _=1,600 do F.tick(e,f,0.1); if t.safetyPhase=='exit' then break end end
 assert(t.safetyPhase=='exit','released')
 f.cars[SC].inPitBox=false; f.leaderLaps=9; frames(e,f,1)
 assert(t.scFinal and t.safetyPhase=='parked' and e.commands[SC].scPark and count(e,'voiture de securite: dernier tour, reste aux stands (arrivee neutralisee)')==1,'brought back to its pit box')
 -- Sortie quand même en piste (déplacement impossible) devant Driver_2.
 F.place(f,SC,1990,120); f.cars[SC].pit=false; f.cars[SC].lap=11; put(f,L,2,1960,120); F.tick(e,f,0.5)
 assert(t.safetyPhase~='out' and t.safetyPhase~='in' and t.cars[SC].scFree,'never deployed, exempted')
 assert(e.states[2].neutralQueue~=SC,'never a queue target')
 assert(Penalties.passable(f.cars[SC],t.cars[SC],e.run,e.time),'passing it is no offence')
 -- Témoin : voiture de sécurité ordinaire en tête de la file : toujours une cible, jamais dépassable.
 local e2,f2,t2=scene()
 F.tick(e2,f2,0.5)
 assert(not t2.cars[SC].scFree and not Penalties.passable(f2.cars[SC],t2.cars[SC],e2.run,e2.time) and e2.states[2].neutralQueue==SC,'ordinary Safety Car unchanged')
end

-- A10 : jamais une course finie sous voiture de sécurité à cause du dédoublement : tours restants vérifiés au lancement et
-- avant chaque autorisation (attardées restantes × délai par voiture + 2 tours de voiture de sécurité).
tests.LOCK_SC_UNLAP_RACE_END_164=function()
 local o={lapped={[4]=true,[6]=true}}
 o.leaderLaps=26
 local e,f,t=scene(o); decide(e,f,t)
 assert(t.safetyPhase=='in' and count(e,'voiture de securite: dedoublement non lance (fin de course proche, 2 attardee(s))')==1,'4 laps for 2 lapped cars: not started')
 o.leaderLaps=25
 local e2,f2,t2,L2=running(o)
 assert(t2.unlapCar==4 and t2.unlapN==2,'5 laps: started')
 f2.leaderLaps=27
 glide(e2,f2,L2,4,2010,140); F.tick(e2,f2,0.2)
 assert(count(e2,'Driver_4 s est dedoublee (1 / 2)')==1 and count(e2,'voiture de securite: dedoublement arrete (fin de course proche), 1 attardee(s) restent dans la file')==1,'3 laps left: stopped')
 assert(t2.unlapState=='done' and count(e2,'Driver_6 autorisee')==0,'no further car allowed')
 local J=require('src/journal')
 assert(J.english('voiture de securite: dedoublement arrete (fin de course proche), 1 attardee(s) restent dans la file')=='Safety Car: unlapping stopped (race end close), 1 lapped car(s) stay in the queue','translated')
end

-- A11 : voiture dédoublée encore loin de la dernière voiture de la file : allure proche de la course (K.unlapRacePct %)
-- jusqu'à K.unlapTailGap m d'elle, puis le rattrapage de la file.
tests.LOCK_SC_UNLAP_REJOIN_164=function()
 local e,f,t,L=running()
 e.states[4].priorMap=setmetatable({},{__index=function() return 70 end})
 glide(e,f,L,4,2010,140); F.tick(e,f,0.2)
 assert(t.unlapState=='done' and t.unlapTail==6,'unlapped, Driver_6 last in the queue')
 assert(K.unlapRacePct==3 and K.unlapTailGap==200,'race pace minus 3 %, until 200 m from the queue')
 local race=70/1.03*3.6; local catch=70/(1+K.scCatchPct/100)*3.6
 local cap=Incidents.cap(t,f,4,e.run,e.delta,e.states,0)
 assert(math.abs(cap-race)<1e-6,'far from the queue: close to race pace ('..cap..')')
 put(f,L,4,1700,140); F.tick(e,f,0.1)
 cap=Incidents.cap(t,f,4,e.run,e.delta,e.states,0)
 assert(math.abs(cap-catch)<1e-6,'170 m from the last car: the queue pace ('..cap..')')
 local _,_,t3=scene(); assert(t3.unlapTail==0,'nothing without unlapping')
end

-- Décision du pilote 2026-11-14 (« jamais lever un arrêt configuré ») : la levée sprint est coupée en jeu
-- (K.sprintWaiver=false) ; les tests du chemin sprint le gardent couvert en la forçant.
for name,fn in pairs(tests) do
 if name:find('SPRINT',1,true) then
  tests[name]=function()
   local old=K.sprintWaiver; K.sprintWaiver=true
   local ok,err=pcall(fn); K.sprintWaiver=old
   if not ok then error(err,0) end
  end
 end
end
return tests
