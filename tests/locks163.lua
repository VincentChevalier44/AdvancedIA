-- Verrous de non-régression 1.63 (règle du pilote, 13 novembre : un problème corrigé ne doit jamais revenir). Chaque
-- test rebâtit la situation du journal du pilote (temps et valeurs repris autant que le banc le permet) et échoue sur
-- l'ancien comportement. Liste et sources : tests/LOCKS.md. Noms LOCK_<sujet>_163. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local A=require('src/applier')
local Incidents=require('src/incidents')
local Dangerfile=require('src/dangerfile')
local K=C.K
local DK=Incidents.DK
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Drapeau rouge en course, voiture 6 = voiture de sécurité, joueur (1) et IA (2 à 5) rentrés à leur emplacement ;
-- junction : jonction des stands connue (m) ou nil.
local function redRelaunch(junction,playerLast)
 local e,f=F.scene('C',6); C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagHold=20; e.g.safetyCarModel='car_6'; E.changed(e)
 F.place(f,6,0,0); f.cars[6].pit=true; f.cars[6].inPitBox=true
 F.block(f,{3,4,5},600); F.place(f,2,3000,120)
 for i=1,5 do f.cars[i].position=i end
 if playerLast then f.cars[1].position=5; for i=2,5 do f.cars[i].position=i-1 end end
 F.tick(e,f,K.redIncidentStill+1); local t=e.incidents; assert(t.red and t.safety==6,'red flag')
 for i=2,5 do local a=f.cars[i]; F.place(f,i,100+i*20,0); a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0 end
 F.place(f,1,100,0); f.cars[1].pit=true; f.cars[1].inPitBox=true
 if junction then e.merge.spline=junction/f.length end
 for _=1,200 do if not t.red then break end; F.tick(e,f,0.5) end
 assert(not t.red and t.relaunch,'relaunch')
 return e,f,t
end
-- Suzuka (2026-11-13_06_55_49_rt_suzuka.log) : voiture de sécurité libérée à 226,3 s, sortie de son stand 1,1 s
-- après, encore 14 s dans la voie des stands, en piste à 240,1 s avec deux IA déjà devant elle (92 m et 15 m).
-- Aucune IA ne quitte son emplacement avant qu'elle soit en piste et à 150 m de son entrée en piste.
tests.LOCK_AI_BEFORE_SC_163=function()
 local e,f,t=redRelaunch(380,true)
 assert(t.safetyPhase=='exit','it leaves first')
 F.tick(e,f,1.1); f.cars[6].inPitBox=false; F.place(f,6,40,80)
 for k=1,14 do F.tick(e,f,1); for i=2,5 do assert(e.commands[i].pitHold,'AI '..i..' held while the Safety Car is in the pit lane ('..k..' s)') end end
 f.cars[6].pit=false; F.place(f,6,380,80); F.tick(e,f,0.2)
 assert(t.safetyPhase=='out','on track at 380 m')
 F.place(f,6,480,80); F.tick(e,f,3)
 for i=2,5 do assert(e.commands[i].pitHold,'100 m on track: still held '..i) end
 F.place(f,6,560,80); F.tick(e,f,0.5)
 assert(not e.commands[2].pitHold and e.commands[3].pitHold,'then released one by one, in order (P1 first)')
end
-- Imola (2026-11-13_07_39_46_fn_imola.log) : libérée à 228,5 s pendant qu'une IA arrivait encore à son stand, 10 s à
-- 0 km/h à son emplacement, posée à 446 m 22 s plus tard, IA sorties avant elle (jonction inconnue).
tests.LOCK_SC_STUCK_163=function()
 -- Reprise différée tant qu'une IA roule encore dans la voie des stands.
 local e,f=F.scene('C',6); C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagHold=20; e.g.safetyCarModel='car_6'; E.changed(e)
 F.place(f,6,0,0); f.cars[6].pit=true; f.cars[6].inPitBox=true
 F.block(f,{3,4,5},600); F.place(f,2,3000,120)
 for i=1,5 do f.cars[i].position=i end
 F.tick(e,f,K.redIncidentStill+1); local t=e.incidents; assert(t.red,'red flag')
 for i=2,5 do local a=f.cars[i]; F.place(f,i,100+i*20,0); a.pit=true; a.inPitBox=true end
 F.place(f,1,100,0); f.cars[1].pit=true; f.cars[1].inPitBox=true
 F.place(f,5,200,30); f.cars[5].inPitBox=true
 F.tick(e,f,e.profiles.C.redFlagHold+5); assert(t.red,'an AI still rolling to its box: no restart yet')
 F.place(f,5,200,0); F.tick(e,f,4); assert(not t.red and t.relaunch,'pit lane calm: restart')
 -- Immobile à son emplacement : posée après 4 s (avant : 10 s), à la hauteur de son stand plus la jonction, IA retenues.
 assert(t.safetyPhase=='exit' or t.safetyPhase=='place','released')
 F.tick(e,f,4.5)
 assert(t.safetyPhase=='place' and e.commands[6].place and e.commands[6].place>=0,'still in its box after 4 s: placed')
 for i=2,5 do assert(e.commands[i].pitHold,'AI held until it is placed '..i) end
 -- Applicateur : retenue restée posée (garée sans pilote, freinage forcé) levée à la libération, réveil, ligne.
 local host=require('tests/host').create(true); local e2,f2=F.scene('C'); local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e2.commands) do cmd.active=false end
 local cmd=e2.commands[3]; f2.cars[3].safetyCar=true; f2.cars[3].pit=true; f2.cars[3].inPitBox=true
 a.cars[3]=a.cars[3] or {}; local s=a.cars[3]
 cmd.scPark=false; cmd.scRelease=true; cmd.scSpeed=K.unlimitedSpeed
 s.stop=true; host.stops[2]=K.scHoldStop; host.startDelays[2]=K.scHoldTime
 A.apply(a,f2,e2.commands,e2.g,10)
 assert(host.startDelays[2]==0 and host.stops[2]==0 and (host.awakes[2] or 0)>=1 and not s.stop,'every hold cleared, woken up')
 assert(#(a.log or {})>=0)
end
-- Plafond de la voiture de sécurité en ligne droite (le pilote : 160–180 km/h) : allure du suiveur inconnue (premiers
-- tours, drapeau rouge du premier tour) : aucune limite ; file loin : plus d'allure lente fixe.
tests.LOCK_SC_SPEED_163=function()
 local e,f,t=redRelaunch(380)
 f.cars[6].inPitBox=false; f.cars[6].pit=false; F.place(f,6,380,80); F.tick(e,f,0.2)
 F.place(f,6,2500,250); F.tick(e,f,0.2)
 assert(t.safetyPhase=='out' and e.commands[6].scSpeed>=K.unlimitedSpeed,'field far behind: never slowed: '..tostring(e.commands[6].scSpeed))
 local b=f.cars[2]; b.pit=false; b.inPitBox=false; F.place(f,2,2450,240); F.tick(e,f,0.2)
 assert(e.commands[6].scSpeed>=K.unlimitedSpeed,'queue head close, its pace unknown: never capped at 160: '..tostring(e.commands[6].scSpeed))
 -- La file la rattrape : rattrapage relatif à elle, jamais 160 km/h fixes.
 for _,fl in pairs(e.delta.fleet) do for k in pairs(fl) do fl[k]=0 end end
 local c=f.cars[3]; c.pit=false; c.inPitBox=false; F.place(f,3,1400,200); e.states[3].paceCount=0; e.states[3].priorMap=nil
 local cap=Incidents.cap(t,f,3,e.run,e.delta,e.states,0)
 assert(cap>250,'1 km behind a Safety Car at 250 km/h: catches up: '..cap)
end
-- Suzuka : voitures devant la voiture de sécurité sans l'avoir doublée (sorties avant elle) et des dizaines de lignes
-- « reprend sa place » pour des voitures déjà dans l'ordre. Une voiture devant elle lève le pied jusqu'à être repassée ;
-- la reprise de place n'est notée que pour un vrai dépassement.
tests.LOCK_QUEUE_ORDER_163=function()
 local e,f,t=redRelaunch(380)
 f.cars[6].inPitBox=false; f.cars[6].pit=false; F.place(f,6,400,100); F.tick(e,f,0.2)
 local a=f.cars[3]; a.pit=false; a.inPitBox=false; F.place(f,3,415,150); F.tick(e,f,0.2)
 F.place(f,3,492,150); F.tick(e,f,0.2)
 assert(t.cars[3].scLift,'ahead of it without passing: lifts')
 local cap=Incidents.cap(t,f,3,e.run,e.delta,e.states,0)
 assert(cap<=math.max(K.scGiveFloor,100-K.giveBackDrop)+1e-6,'never escapes ahead of the Safety Car: '..cap)
 t.redOrder={1,2,3,4,5}; t.redRank={[1]=1,[2]=2,[3]=3,[4]=4,[5]=5}; t.redOrderN=5
 for _=1,20 do Incidents.restored(t,f,2,4,-30,4.4) end
 assert(count(e,'reprise: Driver_2 reprend sa place sur Driver_4')==0,'already ahead in the order: no line')
end
-- Suzuka : « peloton non regroupe (15 / 22) » : la voiture de sécurité rentrait après un tour. Elle attend jusqu'à
-- K.scBunchLaps tours (3) que la file soit formée.
tests.LOCK_QUEUE_BUNCH_163=function()
 assert(K.scBunchLaps>=3 and K.scBunchMax>=420,'regroup wait: 3 laps, 420 s at most')
 local e,f=F.scene('C',5); C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; E.changed(e)
 e.g.safetyCarModel='car_5'; F.place(f,5,0,0); f.cars[5].pit=true; f.cars[5].inPitBox=true
 f.cars[1].pit=true; f.cars[1].inPitBox=true
 F.place(f,2,1000,120); F.place(f,3,900,120); f.cars[2].position=1; f.cars[3].position=2
 F.place(f,4,6000,0)
 for _=1,900 do F.tick(e,f,0.1); if e.incidents.safetyPhase=='place' then break end end
 F.place(f,4,6000,60); f.cars[4].pit=true
 F.place(f,5,1200,80); f.cars[5].pit=false; f.cars[5].inPitBox=false; F.tick(e,f,0.5)
 local t=e.incidents; assert(t.safetyPhase=='out','on track')
 F.place(f,5,1200,100); F.place(f,2,1150,100); F.place(f,3,6000,100)
 F.tick(e,f,K.scMinOut+180+10)
 assert(t.safetyPhase=='out' and count(e,'peloton non regroupe')==0,'old bound (1 lap, 180 s) passed: still waiting for the queue')
end
-- Imola (2026-11-13_07_39_46_fn_imola.log, premier tour, ~750 m) : drapeau rouge sur cinq tête-à-queue qui
-- repartaient. Rouge seulement si cinq voitures restent immobilisées 10 s dans les mêmes 200 m.
tests.LOCK_RED_CARNAGE_163=function()
 local function run(n,stillFor)
  local e,f=F.scene('C',8); C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagHold=20; E.changed(e)
  for i=1,8 do F.place(f,i,(i-1)*400+200,120) end
  F.tick(e,f,0.5)
  for k=0,n-1 do local i=2+k; F.place(f,i,750+k*30,20,(k%2==0) and -2 or 2); f.cars[i].slip=60 end
  F.tick(e,f,1.5)
  for k=0,n-1 do local i=2+k; F.place(f,i,750+k*30,0,(k%2==0) and -2 or 2); f.cars[i].slip=60 end
  F.tick(e,f,stillFor)
  return e,f
 end
 local e,f=run(5,6)
 assert(not e.incidents.red,'5 spins, stopped 6 s: no red flag yet')
 for k=0,4 do local i=2+k; F.place(f,i,750+k*30+40,120) end; F.tick(e,f,6)
 assert(not e.incidents.red,'they rejoin: never a red flag')
 e=run(5,DK.carnageStill+1); assert(e.incidents.red,'5 cars still stopped 10 s: red flag')
 e=run(4,DK.carnageStill+5); assert(not e.incidents.red,'4 cars: no red flag')
 assert(DK.carnageCars==5 and DK.carnageSpan==200 and DK.carnageStill==10)
end
-- Suzuka (Degner, ~2357–2383 m) : carnage du premier tour, aucune zone dangereuse (départ et premier tour exclus),
-- carnage de nouveau au même virage la course suivante. Zone gardée par circuit, mémoire des circuits coupée, appliquée
-- dès le premier tour du lancement suivant.
tests.LOCK_DANGER_KEPT_163=function()
 local e,f=F.scene('C',6); C.preset('Course','C',e.profiles.C); E.changed(e)
 for i=1,6 do F.place(f,i,(i-1)*300+200,150) end
 F.tick(e,f,0.5)
 assert(e.runtimeG.trackMemory~=true,'track memory off')
 local L=f.length; local t=e.incidents
 -- Premier tour (grâce du départ) : trois IA en tête-à-queue à 2357–2383 m à 145–159 km/h, puis arrêtées.
 local at={2383,2368,2357}
 for k=1,3 do local i=k+1; F.place(f,i,at[k],150,(k%2==0) and -2 or 2); f.cars[i].slip=60 end
 F.tick(e,f,1.5)
 for k=1,3 do local i=k+1; F.place(f,i,at[k],0,(k%2==0) and -2 or 2) end
 F.tick(e,f,K.obstacleTime+1)
 assert(t.hotspotPause and t.hotspotN==0,'first lap: no ordinary difficult spot')
 assert(e.danger.n==1,'lap-1 carnage: zone kept for the track ('..e.danger.n..')')
 e.danger.zones[1].kmh=150
 local list=Dangerfile.decode(Dangerfile.encode(e.danger,{track=f.track,layout='',length=L}),f.track,'',L)
 local e2,f2=F.scene('C',4); C.preset('Course','C',e2.profiles.C); E.changed(e2); F.tick(e2,f2,0.2)
 Dangerfile.loaded(e2.danger,list,'k')
 F.place(f2,2,2300,159); F.tick(e2,f2,1/60)
 local s=e2.states[2]; s.dangerCapped=false; E.dangerCapTest(e2,2,s,e2.time)
 assert(s.dangerCapped and e2.commands[2].speedLimit<150,'next launch, lap 1: capped before the corner')
end
return tests
