-- Beta 1.47 : premier tour attentif (idée du pilote, départs de Monza à 24 IA du 4 novembre : bouchons, vagues de
-- freinage, chocs par l'arrière au premier freinage, évitements dans le peloton). Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local FirstLap=require('src/firstlap')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Course : grille puis départ (front montant de la session), le mode s'arme au départ.
local function race(n,setup)
 local e,f=F.scene('C',n); C.preset('Course','C',e.profiles.C)
 if setup then setup(e,f) end
 E.changed(e); F.tick(e,f,1/60)
 f.started=false; F.tick(e,f,1/60)
 f.started=true; F.tick(e,f,1/60)
 return e,f
end
-- Mode armé en pleine course (comme une relance), hors fenêtre de départ.
local function careful(n,plain)
 local e,f=F.scene('C',n); if not plain then C.preset('Course','C',e.profiles.C) end; E.changed(e); F.tick(e,f,1/60)
 assert(FirstLap.arm(e,f,e.time,'relance'))
 return e,f
end
tests.FIRST_LAP_ARMS_AND_ENDS_147=function()
 local e,f=race(5,function(e,f) F.place(f,1,-3000,0); for i=2,5 do F.place(f,i,-(i-2)*12,150) end end)
 assert(e.fl.on and e.fl.armed==4 and count(e,'premier tour: mode attentif pour 4 IA (depart)')==1,'armed at the start, logged once')
 for i=2,5 do assert(e.states[i].flOn and e.states[i].flW==1,'every AI on track') end
 assert(not e.states[1].flOn,'never the player')
 -- Passage de la ligne juste après le départ (grille devant la ligne) : ignoré.
 f.cars[2].lap=f.cars[2].lap+1; F.tick(e,f,1); assert(e.states[2].flOn,'crossing right after the start ignored')
 F.tick(e,f,K.firstLapLineGrace); assert(e.states[2].flOn and e.states[3].flOn,'pack still close: still careful')
 f.cars[2].lap=f.cars[2].lap+1; F.tick(e,f,1/60)
 assert(not e.states[2].flOn and e.states[2].flW>0 and e.states[2].flW<1,'ended at the line, released progressively')
 F.tick(e,f,K.firstLapRelease); assert(e.states[2].flW==0,'released after K.firstLapRelease s')
 -- Peloton étiré autour d'une IA : fini après K.firstLapSpreadTime s ; entrée aux stands : fini aussitôt.
 F.place(f,5,-2000,150); e.states[5].nextPerception=0; F.tick(e,f,K.firstLapSpreadTime+0.5)
 assert(not e.states[5].flOn,'spread: ended')
 f.cars[4].pit=true; f.cars[3].lap=f.cars[3].lap+1; F.tick(e,f,K.firstLapRelease+0.5)
 assert(not e.fl.on and count(e,'premier tour: fin du mode attentif')==1,'end logged once')
 assert(count(e,'ligne franchie 2, peloton etire 1, delai 0, stands 1')==1,'reasons counted')
 -- Jamais armé : app chargée en pleine course, réglage coupé, onglet Départ décoché, hors course.
 local m,fm=F.scene('C',3); C.preset('Course','C',m.profiles.C); E.changed(m); F.tick(m,fm,1)
 assert(not m.fl.on and count(m,'premier tour:')==0,'app loaded during the race: not armed')
 local o=race(3,function(e) e.profiles.C.firstLapCare=false end); assert(not o.fl.on,'setting off')
 local q=race(3,function(e) e.profiles.C.section_start=false end); assert(not q.fl.on,'start section off')
 local j,fj=F.scene('J',3); j.profiles.J.firstLapCare=true; E.changed(j); F.tick(j,fj,1/60); fj.started=false; F.tick(j,fj,1/60); fj.started=true; F.tick(j,fj,1/60)
 assert(not j.fl.on,'track day: never, even with the setting')
 j.incidents.restartSerial=(j.incidents.restartSerial or 0)+1; F.tick(j,fj,1/60); assert(not j.fl.on,'track day: no restart arming either')
 assert(C.defaults('C').firstLapCare==true and C.defaults('J').firstLapCare==false and C.defaults('Q').firstLapCare==false,'race default only')
end
-- Délai maximal : K.firstLapMax s, même dans un peloton serré (Nordschleife, île de Man).
tests.FIRST_LAP_TIME_CAP_147=function()
 local e,f=careful(3); F.place(f,1,-3000,0); F.place(f,2,0,150); F.place(f,3,20,150); e.states[2].nextPerception=0; e.states[3].nextPerception=0
 F.tick(e,f,K.firstLapMax-1); assert(e.states[2].flOn,'still careful before the cap')
 F.tick(e,f,1.5); assert(not e.states[2].flOn and e.fl.why.delai>=1,'ended at the cap')
end
-- Relance derrière la voiture de sécurité ou fin du tour de relance : le moteur arme le mode (compteur des incidents).
tests.FIRST_LAP_RESTART_147=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,1/60)
 assert(not e.fl.on)
 e.incidents.restartSerial=(e.incidents.restartSerial or 0)+1; F.tick(e,f,1/60)
 assert(e.fl.on and e.fl.kind=='relance' and count(e,'(relance)')==1,'armed at the restart')
end
-- Radar : levée de pied d'abord ; frein léger à moins de K.firstLapBrakeTTC s au freinage du pilote, jamais en ligne
-- droite ni avec une voiture collée derrière ; plein freinage en dernier recours (moins de K.firstLapLastTTC s).
tests.FIRST_LAP_RADAR_LIFT_FIRST_147=function()
 local function run(mode,ahead,behind,pedal,narrow)
  local e,f
  if mode then e,f=careful(4) else e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,1/60) end
  F.place(f,1,-3000,100); F.place(f,2,0,150); F.place(f,3,ahead,100); F.place(f,4,behind or -3500,behind and 150 or 100)
  -- Beta 1.50 : piste étroite (pas de couloir libre à côté) : la levée de pied de la ligne droite reste possible.
  if narrow then f.cars[2].leftWidth=2; f.cars[2].rightWidth=2 end
  -- Beta 1.50 : freinage du pilote pour un virage : point de freinage appris juste devant (un freinage de suivi en ligne
  -- droite n'est plus une approche de virage, FIRST_LAP_STRAIGHT_150).
  if pedal and mode then e.fl.points[1]=(40/f.length)%1; e.fl.count=1 end
  for i=2,4 do e.states[i].nextPerception=0 end
  for _=1,30 do if pedal then f.cars[2].brake=math.max(pedal,e.commands[2].brake or 0) end; F.tick(e,f,1/60) end
  return e.commands[2],e.states[2],e
 end
 -- Contact à 1,1 s (15,6 m, +50 km/h).
 local cmd=run(false,20); assert(cmd.brake>0,'reference: the radar brakes')
 -- Beta 1.50 : en ligne droite, pied tenu au-delà de K.radarStraightTTC s (le peloton du départ ne freine plus pour rien).
 cmd=run(true,20); assert(cmd.brake==0 and (cmd.throttleLimit or 1)>=1-1e-9,'careful lap, straight, 1.1 s: foot kept down')
 -- Contact à 0,55 s : en ligne droite, pied tenu avec un couloir libre, levée dosée sans couloir ; au freinage du
 -- pilote, frein léger ; voiture collée derrière : levée de pied.
 cmd=run(true,12); assert(cmd.brake==0 and (cmd.throttleLimit or 1)>=1-1e-9,'straight, free lane alongside: foot kept down')
 cmd=run(true,12,nil,nil,true); assert(cmd.brake==0 and cmd.throttleLimit<1 and cmd.throttleLimit>K.radarStartLift,'straight, no lane: graded lift only')
 cmd=run(true,12,nil,0.6); assert(cmd.brake>0 and cmd.brake<=K.radarStartBrakeMax+1e-9,'braking: light brake under K.firstLapBrakeTTC')
 -- Beta 1.59 : peloton (+50 km/h) : levée dosée selon le temps au contact, jamais de frein.
 cmd=run(true,12,-8,0.6); assert(cmd.brake==0 and cmd.throttleLimit<1 and cmd.throttleLimit>=K.radarStartLift-1e-9,'car right behind: graded lift only')
 -- Suiveur à 15 m à 150 km/h (0,25 s) : collé en temps (K.radarStartFollowTime s), au-delà du plancher en mètres.
 cmd=run(true,12,-15,0.6); assert(cmd.brake==0,'close in time: lift only')
 -- Contact à 0,3 s : dernier recours, plein freinage du radar même suivi.
 local s,e
 cmd,s,e=run(true,8.6,-8); assert(cmd.brake>K.radarStartBrakeMax,'last resort: radar brake')
 assert((e.stats.flBrake or 0)>=1,'counted')
end
-- Évitement : jamais pour une voiture qui roule encore à l'allure du peloton (vague de freinage, tête-à-queue à haute
-- vitesse) ; une voiture arrêtée ou très lente l'est.
tests.FIRST_LAP_AVOID_SLOW_ONLY_147=function()
 local function run(mode,kmh)
  local e,f
  if mode then e,f=careful(3) else e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,1/60) end
  F.place(f,1,-3000,150); F.place(f,2,0,150); F.place(f,3,60,kmh); f.cars[3].slip=60; e.states[2].nextPerception=0
  -- Beta 1.59 : glissade tenue (K.spinTime s) pour une voiture en travers.
  F.tick(e,f,0.7)
  return e.states[2].state,e
 end
 assert(run(false,110)=='AVOID','reference: sideways car avoided')
 local state,e=run(true,110); assert(state~='AVOID' and (e.stats.flAvoid or 0)==1,'careful lap: not avoided at pack speed, refusal counted')
 assert(run(true,20)=='AVOID','careful lap: a very slow car is avoided')
end
-- Défense : jamais pendant le premier tour (même scène que NO_DEFENSE_UNDER_BRAKING).
tests.FIRST_LAP_NO_DEFENCE_147=function()
 for _,mode in ipairs({false,true}) do
  local e,f
  if mode then e,f=careful(3,true) else e,f=F.scene('C',3) end
  e.profiles.C.noMoveBraking=false; E.changed(e); F.tick(e,f,1/60); e.p.personalLineJitter=0
  local s=e.states[2]; s.persona.assertiveness=1
  F.place(f,1,-3000,100); F.place(f,2,0,150); F.place(f,3,-15,160,0.8); s.nextPerception=0; F.tick(e,f,1)
  if mode then assert(s.defendAttacker~=3 and s.state~='DEFEND','careful lap: no defence') else assert(s.defendAttacker==3,'reference: defence considered') end
 end
end
-- Écart en temps : même facteur de prudence à 100 et à 300 km/h pour le même écart en secondes ; anticipation d'un point
-- de freinage appris à moins de K.firstLapAnticipate s, pas au-delà.
tests.FIRST_LAP_TIME_GAP_147=function()
 local function factor(kmh,headway,point,frontBrake)
  local e,f=careful(3); local v=kmh/3.6
  F.place(f,1,-3000,kmh); F.place(f,2,0,kmh); F.place(f,3,headway*v+4.4,kmh); e.states[2].nextPerception=0
  -- Beta 1.50 : en courbe (l'écart en temps ne joue plus en ligne droite, voir FIRST_LAP_STRAIGHT_150).
  f.cars[2].yawRate=e.p.cornerYawRef*0.5
  if point then e.fl.points[1]=(point/f.length)%1; e.fl.count=1 end
  if frontBrake then f.cars[3].brake=frontBrake end
  F.tick(e,f,4)
  return e.states[2].flFactor,e.states[2].flApproach
 end
 local slow,fast=factor(100,0.4),factor(300,0.4)
 assert(slow>1.05 and math.abs(slow-fast)<1e-6,'same factor in seconds: '..slow..' / '..fast)
 assert(math.abs(factor(300,1.0)-1)<1e-6,'beyond K.firstLapGapTime s: nothing')
 local _,near=factor(150,0.5,60); local _,far=factor(150,0.5,200)
 assert(near and not far,'braking point within K.firstLapAnticipate s anticipated, not beyond')
 -- Sous K.firstLapPointKmh km/h (aucun point appris) : seul le freinage de la voiture de devant fait anticiper.
 local _,braking=factor(50,0.5,nil,0.6); assert(braking,'car ahead braking: anticipated')
 local _,coasting=factor(50,0.5); assert(not coasting,'car ahead not braking: nothing')
end
-- Dépassement : en vraie ligne droite avec une vraie avance ; jamais à l'approche d'un point de freinage du tour.
tests.FIRST_LAP_PASS_STRAIGHT_ONLY_147=function()
 local function run(point)
  local e,f=careful(3); e.p.overtakeSide='left'; e.p.personalLineJitter=0; e.p.laneBiasEnabled=false; E.changed(e)
  F.place(f,1,-3000,100); F.front(e,f,15,35)
  if point then e.fl.points[1]=((f.cars[2].z+60)/f.length)%1; e.fl.count=1 end
  F.tick(e,f,2)
  return F.passing(e.states[2].state),e
 end
 assert(run(false),'straight, real advantage: pass')
 local passing,e=run(true); assert(not passing and (e.stats.flPass or 0)>=1,'braking point ahead: held, counted')
end
-- Tour suivant inchangé : une fois le mode fini et rendu, mêmes commandes qu'une course sans le mode.
tests.FIRST_LAP_LAP2_UNCHANGED_147=function()
 local function place(e,f) F.place(f,1,-3000,0); for i=2,5 do F.place(f,i,-(i-2)*30,150) end end
 local on,fon=race(5,place)
 local off,foff=race(5,function(e,f) e.profiles.C.firstLapCare=false; place(e,f) end)
 assert(on.fl.on and not off.fl.on)
 F.tick(on,fon,K.firstLapLineGrace+1); F.tick(off,foff,K.firstLapLineGrace+1)
 for i=2,5 do assert(on.commands[i].aggression<=on.states[i].baseAggression*K.firstLapAggr+1e-3 and off.commands[i].aggression>on.commands[i].aggression,'careful lap: aggression capped below the base') end
 for i=2,5 do fon.cars[i].lap=fon.cars[i].lap+1; foff.cars[i].lap=foff.cars[i].lap+1 end
 F.tick(on,fon,K.firstLapRelease+0.5); F.tick(off,foff,K.firstLapRelease+0.5)
 assert(not on.fl.on,'mode over')
 -- Commandes lissées (approche exponentielle) : quelques secondes pour rejoindre la même valeur, à 1e-5 près.
 F.tick(on,fon,4); F.tick(off,foff,4)
 for _=1,120 do
  F.tick(on,fon,1/60); F.tick(off,foff,1/60)
  for i=2,5 do
   local a,b=on.commands[i],off.commands[i]
   for _,key in ipairs({'level','caution','aggression','brake','throttleLimit','offset','yellowLimit','speedLimit'}) do
    assert(a[key]==b[key] or math.abs(a[key]-b[key])<=1e-5,'lap 2 unchanged: '..key..' car '..i..' '..tostring(a[key])..' / '..tostring(b[key]))
   end
  end
 end
end
-- Départ : l'arrêt sur la grille (feux) ne fait pas d'une voiture encore lente au lancement un obstacle à contourner.
tests.START_LAUNCH_NO_AVOID_147=function()
 for _,care in ipairs({true,false}) do
  -- Beta 1.49 : attente au départ de 1 s (défaut de la 1.47, celui de cette scène) ; 2 s couvriraient toute la scène.
  local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); e.profiles.C.firstLapCare=care; e.profiles.C.startDelay=1; E.changed(e)
  F.place(f,1,-3000,0); F.place(f,2,0,0); F.place(f,3,20,0)
  F.tick(e,f,1/60); f.started=false; F.tick(e,f,12)
  f.started=true; F.tick(e,f,1/60)
  F.place(f,2,0,40); F.place(f,3,20,15); for i=2,3 do e.states[i].nextPerception=0 end
  F.tick(e,f,1.5)
  assert(e.states[2].state~='AVOID','launching car ahead is not an obstacle (careful lap '..tostring(care)..')')
 end
end
-- Prudence d'ensemble plafonnée (K.firstLapCautionMax fois la base) pendant le premier tour ; sans le mode, non.
tests.FIRST_LAP_CAUTION_CAP_147=function()
 local saved=K.firstLapCautionMax; K.firstLapCautionMax=1.2
 local ok,err=pcall(function()
  local function run(mode)
   local e,f
   if mode then e,f=careful(3) else e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,1/60) end
   F.place(f,1,-3000,100); F.place(f,2,0,150); F.place(f,3,14,100); for i=2,3 do e.states[i].nextPerception=0 end
   -- Beta 1.50 : en courbe (en ligne droite, plus de prudence de suivi à plafonner).
   f.cars[2].yawRate=e.p.cornerYawRef*0.5
   F.tick(e,f,3)
   return e.commands[2].caution,e.states[2].baseCaution
  end
  local ref,base=run(false); local capped,base2=run(true)
  assert(ref>base*1.2+0.05,'reference above the cap: '..ref..' / '..base)
  assert(capped<=base2*1.2+0.02,'careful lap: capped ('..capped..' / '..base2..')')
 end)
 K.firstLapCautionMax=saved
 assert(ok,err)
end
-- Double jaune, allure inconnue : repli relatif à la voiture (K.yellowUnknownPct de sa vitesse maximale vue), au moins
-- yellowSpeedKmh : le même ralentissement pour une F1 ou une voiture de route.
tests.YELLOW_UNKNOWN_RELATIVE_147=function()
 local function limit(kmh)
  local e,f=F.scene('J',4); F.place(f,4,600,0); F.place(f,2,350,kmh); F.place(f,3,-2000,100)
  F.tick(e,f,2.5); assert(e.incidents.cars[4].incident and e.states[2].yellow,'zone ahead')
  F.tick(e,f,15)
  return e.commands[2].yellowLimit,e.run.yellowSpeedKmh
 end
 local fast,floor=limit(300)
 assert(fast<=K.yellowUnknownPct*300+1e-6 and fast>=K.yellowUnknownPct*300*(1-K.aiDeltaMarginMax)-1e-6,'fast car: relative fallback ('..fast..')')
 local slow=limit(100)
 assert(slow<=floor+1e-6 and slow>=floor*(1-K.aiDeltaMarginMax)-1e-6,'slow car: never under yellowSpeedKmh ('..slow..')')
end
-- Résumé de la minute : segment du premier tour écrit seulement s'il a agi, puis remis à zéro.
tests.FIRST_LAP_SUMMARY_147=function()
 local J=require('src/journal')
 local e,f=careful(3); F.tick(e,f,1/60)
 e.stats.flCare=2; e.stats.flLift=3; e.stats.flBrake=1; e.stats.flAvoid=4; e.stats.flPass=5
 assert(J.summary(e):find('premier tour attentif : anticipations 2, levers de pied du radar 3, freinages du radar 1, evitements refuses (voiture pas assez lente) 4, depassements retenus 5',1,true),'segment written')
 assert(not J.summary(e):find('premier tour attentif',1,true),'reset after the summary')
end
-- Points de freinage du tour : appris sur une IA libre devant (personne à moins de K.firstLapPointFree s) qui freine
-- depuis K.firstLapPointKmh km/h, jamais sur une IA qui freine derrière une autre ; points voisins fusionnés.
tests.FIRST_LAP_POINTS_LEARNT_147=function()
 local e,f=careful(3)
 F.place(f,1,-3000,100); F.place(f,2,500,150); F.place(f,3,480,150); for i=2,3 do e.states[i].nextPerception=0 end
 F.tick(e,f,0.2); assert(e.fl.count==0)
 f.cars[3].brake=0.7; F.tick(e,f,0.2); assert(e.fl.count==0,'braking behind another car: not a braking point')
 f.cars[2].brake=0.7; F.tick(e,f,0.2); assert(e.fl.count==1,'free car braking: braking point learnt')
 f.cars[2].brake=0; F.tick(e,f,0.2); F.place(f,2,520,150); f.cars[2].brake=0.7; F.tick(e,f,0.2); assert(e.fl.count==1,'nearby point merged')
end
-- Air sale : jamais pendant le premier tour (même scène que DIRTY_AIR_142).
tests.FIRST_LAP_NO_DIRTY_AIR_147=function()
 for _,mode in ipairs({false,true}) do
  local e,f=F.scene('C',3); e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,1/60)
  if mode then assert(FirstLap.arm(e,f,e.time,'relance')) end
  F.place(f,1,-4000,100); F.place(f,2,1000,150); F.place(f,3,1000-8-4.4,150); f.cars[3].yawRate=0.4
  for i=2,3 do e.states[i].nextPerception=0 end
  F.tick(e,f,2)
  if mode then assert(e.states[3].dirty==0,'careful lap: no dirty air') else assert(e.states[3].dirty>0,'reference: dirty air') end
 end
end
-- Banc des départs (tests/startbench147.lua, modèle simplifié de l'IA d'AC) : Monza, Spa, premier virage proche, circuit
-- urbain étroit ; F1 et voitures de route ; 24 IA et le joueur. Premier tour : jamais de vague de freinage en ligne
-- droite (seuls les contacts imminents, moins de K.firstLapLastTTC s, freinent), pas d'évitement dans le peloton, pas de
-- bouchon (tour 1 au plus 12 % au-dessus du même tour roulé seul), tout le monde boucle son tour.
tests.START_SCENES_147=function()
 local run=require('tests/startbench147')
 for _,tr in ipairs({'monza','spa','short','street'}) do
  for _,st in ipairs({'f1','road'}) do
   local r=run(tr,st,{mode='app',seed=1}); local scene=tr..'/'..st
   assert(r.finished==24,scene..': lap 1 completed by every AI ('..r.finished..')')
   assert(r.radarStraight-(r.radarLast or 0)<=5,scene..': no braking wave on the straights ('..r.radarStraight..', last resort '..(r.radarLast or 0)..')')
   -- Beta 1.50 : la règle du premier tour (évitement d'une voiture vraiment lente seulement) jugée sur l'IA qui évite ;
   -- les évitements d'une voiture à 18-24 km/h par des IA à 36-106 km/h (urbain, voitures de route) sont permis.
   assert(r.avoidWave==0 and r.avoidPack<=4,scene..': no avoidance of a car at pack speed ('..r.avoidWave..', pack '..r.avoidPack..')')
   assert(r.lap1Mean<=r.soloMean*1.12,scene..': no jam ('..r.lap1Mean..' s, alone '..r.soloMean..' s)')
  end
 end
end
-- Drapeau rouge (décision du pilote : « rouge si la piste est vraiment bloquée ») : au moins redFlagCars voitures
-- immobilisées K.redIncidentStill s à cause d'un incident, et aucun passage sur la largeur de la piste. Les voitures
-- intactes qui attendent dans la file derrière l'accident ne comptent pas ; une voiture de la file endommagée, oui.
tests.RED_FLAG_BLOCKED_ONLY_147=function()
 local function scene(place)
  local e,f=F.scene('C',6); C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagHold=20; E.changed(e)
  for i=2,6 do F.place(f,i,(i-1)*300,120) end; F.place(f,1,-3000,100)
  F.tick(e,f,1/60); place(e,f); return e,f
 end
 -- File derrière une voiture arrêtée sur la trajectoire : pas de rouge, refus noté.
 local e,f=scene(function(e,f) F.place(f,3,600,0); F.place(f,4,590,0); F.place(f,5,580,0) end)
 F.tick(e,f,K.redIncidentStill+2)
 assert(not e.incidents.red and count(e,'pas de drapeau rouge: 3 voitures arretees dont 2 dans la file')==1,'queue behind the accident: no red flag, refusal logged once')
 -- Trois voitures arrêtées loin l'une de l'autre, chacune contournable : pas de rouge.
 e,f=scene(function(e,f) F.place(f,3,600,0); F.place(f,4,900,0); F.place(f,5,1200,0) end)
 F.tick(e,f,K.redIncidentStill+2)
 assert(not e.incidents.red and count(e,'dont 0 dans la file, piste encore passable')==1,'track still passable: no red flag')
 -- Trois voitures accidentées en travers de la piste : rouge, jamais avant K.redIncidentStill s.
 e,f=scene(function(e,f) F.block(f,{3,4,5},600) end)
 F.tick(e,f,K.redIncidentStill-1); assert(not e.incidents.red,'not before K.redIncidentStill s')
 F.tick(e,f,2)
 assert(e.incidents.red and count(e,'drapeau rouge: 3 voitures accidentees immobilisees 10 s, piste bloquee')==1,'blocked track: red flag, logged')
 -- Voiture de la file endommagée : elle compte (deux en travers devant, une endommagée juste derrière).
 e,f=scene(function(e,f) F.block(f,{3,4},600); F.place(f,5,590,0,0); f.cars[5].damageBody=K.slowPitBody+1 end)
 F.tick(e,f,K.redIncidentStill+2)
 assert(e.incidents.red,'damaged car in the queue counted, track blocked')
end
-- Carambolage au premier virage sur le banc des départs : les voitures de la file s'arrêtent un moment, aucun drapeau
-- rouge (jaunes seulement), tout le monde boucle son tour.
tests.PILEUP_NO_RED_147=function()
 local run=require('tests/startbench147')
 for _,st in ipairs({'road','gt3'}) do
  local r=run('monza',st,{mode='app',pile=true,seed=1})
  local reds=0; for k=0,r.log.count-1 do local row=r.log[(r.log.head-k-1)%r.log.limit+1]; if row.message:find('drapeau rouge:',1,true) and not row.message:find('pas de drapeau rouge',1,true) then reds=reds+1 end end
  assert(reds==0 and r.finished==24,'monza/'..st..' pile-up: no red flag ('..reds..'), lap completed by all ('..r.finished..')')
 end
end
return tests
