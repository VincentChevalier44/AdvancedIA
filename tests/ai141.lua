-- Beta 1.41 « trafic des IA » : situations relevées dans les journées circuit du 3 novembre (île de Man 60,6 km,
-- Nordschleife Touristenfahrten, 30 à 46 IA). Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local D=require('src/director')
local C=require('src/config')
local P=require('src/perception')
local A=require('src/applier')
local Merge=require('src/merge')
local K=C.K
local tests={}
local function logged(e,text) for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then return true end end return false end
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Allure apprise de chaque IA (m/s) à tous les endroits du circuit, rythme relatif habituel connu.
local function learned(e,f,first,last,speed,ratio)
 for i=first,last do
  local s=e.states[i]; s.paceCount=e.delta.bins
  for b=1,e.delta.bins do s.pace[b]=speed end
  s.longRatio=ratio or 1; s.longRatioTime=K.longRatioMin
 end
end
-- Allure apprise oubliée (inconnue ici).
local function forget(e,i) local s=e.states[i]; s.paceCount=0; for b=1,#s.pace do s.pace[b]=0 end; s.paceRatioCount=0 end
-- Île de Man : une IA endommagée à 30 km/h (allure de sa classe 200 km/h), une autre bloquée derrière elle à 28 km/h.
local function isleOfMan(obstacle)
 local e,f=F.scene('J',4); e.p.personalLineJitter=0; if obstacle==false then e.profiles.J.obstacleEnabled=false end; E.changed(e)
 f.length=60611; F.tick(e,f,1/60)
 learned(e,f,2,4,200/3.6)
 F.place(f,1,-20000,0); F.place(f,2,1000,30); F.place(f,3,1000-15-4.4,28); F.place(f,4,30000,200)
 return e,f
end

-- Tête d'une file lente : obstacle à contourner pour la voiture derrière (avant : trop rapide pour un obstacle, trop
-- lente pour un dépassement) ; jamais la voiture retenue derrière elle (pas de cascade).
tests.SLOW_LEAD_OBSTACLE_141=function()
 local e,f=isleOfMan()
 assert(e.delta.bins==1213,'50 m per pace bin on the Isle of Man: '..e.delta.bins)
 F.tick(e,f,2+K.slowObstacleTime)
 assert(e.states[2].abnormal,'slow lead car flagged')
 assert(not e.states[3].abnormal,'the car held behind it is not flagged')
 assert(e.states[3].state=='AVOID' and e.states[3].target==2,'obstacle for the car behind: '..e.states[3].state)
 -- Une voiture lente par nature (rythme relatif habituel bas) n'est jamais anormale.
 local e2,f2=isleOfMan(); learned(e2,f2,2,2,200/3.6,0.15)
 F.tick(e2,f2,2+K.slowObstacleTime+5)
 assert(not e2.states[2].abnormal and e2.states[3].state~='AVOID','slow by nature: never an obstacle')
 -- Limite de vitesse de l'app : jamais un obstacle.
 local e3,f3=isleOfMan(); F.tick(e3,f3,2)
 for _=1,(K.slowObstacleTime+2)*60 do e3.commands[2].speedLimit=30; F.tick(e3,f3,1/60) end
 assert(not e3.states[2].abnormal,'held by an app speed limit: not abnormal')
end
-- IA anormalement lente qui cède : aucun ralentissement de cession de plus (même cession, voiture lente par nature :
-- ralentie de yieldSlowdownPct).
tests.SLOW_NO_EXTRA_YIELD_SLOWDOWN_141=function()
 local function level(ratio)
  local e,f=isleOfMan(); learned(e,f,2,2,200/3.6,ratio); F.tick(e,f,2+K.slowObstacleTime)
  local s=e.states[2]
  for _=1,4*60 do
   s.state='YIELD_HOLD'; s.target=3; s.targetSide=1; s.followers[3]=true; s.yieldStart=e.time; s.holdUntil=e.time+60; s.yieldDetection=100; s.yieldMargin=5
   F.tick(e,f,1/60)
  end
  return e.commands[2].level,s.abnormal
 end
 local slow,flagged=level(1); local normal,other=level(0.15)
 assert(flagged and not other,'one abnormal, one slow by nature')
 assert(slow>=normal*1.03,'no extra yield slowdown for the abnormal car: '..slow..' vs '..normal)
end
-- Évitement coupé : dépassement engagé derrière elle sous K.speedMinPass (zone morte), sans rapprochement exigé.
tests.SLOW_LEAD_PASS_141=function()
 local e,f=isleOfMan(false)
 F.place(f,2,1000,28); F.place(f,3,1000-15-4.4,27)
 F.tick(e,f,2+K.slowObstacleTime)
 assert(e.states[2].abnormal,'flagged')
 local engaged=false
 for _=1,120 do F.tick(e,f,1/60); if F.passing(e.states[3].state) then engaged=true end end
 assert(engaged,'pass engaged at 27 km/h behind the slow car: '..e.states[3].state)
 assert(logged(e,'(cible lente, '),'trigger logged')
end
-- Endommagée et lente K.slowPitTime s : hors course ramenée à son stand, en course arrêt demandé ; hors course,
-- réparée à son emplacement.
tests.SLOW_DAMAGED_TO_PITS_141=function()
 local e,f=isleOfMan(); f.cars[2].damageSuspension=0.37; f.cars[2].damageBody=40
 F.tick(e,f,K.slowPitTime-1); assert(not e.commands[2].recover,'not before '..K.slowPitTime..' s')
 F.tick(e,f,2)
 assert(e.commands[2].recover and e.commands[2].recoverReason=='lente et endommagee','brought back to its pit')
 assert(count(e,'endommagee (suspension 0.37, carrosserie 40), ramenee a son stand')==1,'logged once')
 -- Sans dégâts notables : jamais.
 local e2,f2=isleOfMan(); f2.cars[2].damageSuspension=0.1; f2.cars[2].damageBody=100
 F.tick(e2,f2,2+K.slowPitTime+K.slowObstacleTime+1); assert(not e2.commands[2].recover,'no damage: stays out')
 -- Course : arrêt aux stands demandé.
 local r,fr=F.scene('C',4); r.p.personalLineJitter=0; E.changed(r); fr.length=60611; F.tick(r,fr,1/60)
 learned(r,fr,2,4,200/3.6)
 F.place(fr,1,-20000,0); F.place(fr,2,1000,30); F.place(fr,3,1000-15-4.4,28); F.place(fr,4,30000,200); fr.cars[2].damageSuspension=0.37
 F.tick(r,fr,2+K.slowPitTime+K.slowObstacleTime+1)
 assert(r.commands[2].rulePit and not r.commands[2].recover,'race: pit stop requested')
 assert(logged(r,'arret aux stands demande'),'logged')
 -- Hors course, à son emplacement avec des dégâts : réparée, jamais retenue.
 local a=f.cars[2]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0; a.damageBody=200
 F.tick(e,f,0.2); assert(e.commands[2].pitRepair and not e.commands[2].pitHold,'repaired at its pit')
end
-- Cession : jamais de dépassement d'une IA qui cède en s'éloignant ; sur vraie avance, aussitôt.
tests.CESSION_GATE_141=function()
 local function run(sa,mine)
  local e,f=F.scene('J',3); e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
  F.front(e,f,15,sa); F.tick(e,f,1/60)
  -- L'IA qui cède, en tête, apprend son allure du moment (100 km/h) : celle de la suiveuse est comparée à elle.
  if mine then learned(e,f,2,2,mine); learned(e,f,3,3,100/3.6) else forget(e,2) end
  local o=e.states[3]
  local engaged=false
  for _=1,150 do
   o.state='YIELD_HOLD'; o.target=2; o.targetSide=1; o.followers[2]=true; o.yieldStart=e.time; o.holdUntil=e.time+30
   F.tick(e,f,1/60); if F.passing(e.states[2].state) then engaged=true end
  end
  return engaged,e
 end
 assert(not run(-13),'yielding car pulling away at 13 km/h: no pass (loop of the logs)')
 assert(not run(-13,60),'even when faster in free pace: no pass on a yielding car pulling away')
 -- Beta 1.59 : hors course, la cession accordée à un suiveur d'allure voisine ou inconnue est attaquée ; nettement plus
 -- lent ici : toujours pas.
 assert(run(5,100/3.6),'same free pace here, track day: the yield is used')
 assert(not run(5,20),'clearly slower here: no pass')
 local ok,e=run(5,60); assert(ok and logged(e,'(cession, '),'really faster here: pass on the yield')
 assert(run(2),'unknown pace, track day: the yield is used')
 assert(run(5),'unknown pace, closing: pass')
end
-- Échec « cible plus rapide » : paire ignorée 45 s, puis 180 s ; l'IA qui cédait ne l'attend plus ; la retenue ne
-- relance rien pendant ce temps.
tests.PASS_IGNORE_141=function()
 local e,f=F.scene('J',3); e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
 local s=e.states[2]
 local function attempt()
  F.front(e,f,20,-10)
  s.state='OVT_IN'; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=20; s.passName='x'; s.abortSlow=0; s.passAlongside=false
  for _=1,5*60 do F.tick(e,f,1/60); if s.state~='OVT_IN' and s.state~='OVT_HOLD' then break end end
 end
 attempt()
 assert(s.state=='OVT_OUT' and s.reason=='abort_slow','aborted: target faster')
 assert(s.passIgnore==3 and s.passIgnoreUntil-e.time>K.passIgnore-1 and s.passIgnoreUntil-e.time<=K.passIgnore,'pair ignored '..K.passIgnore..' s')
 assert(e.states[3].yieldIgnore==2 and e.states[3].yieldIgnoreUntil>=s.passIgnoreUntil-1e-9,'the target no longer yields to it')
 F.tick(e,f,3); attempt()
 assert(s.passIgnoreCount==2 and s.passIgnoreUntil-e.time>K.passIgnore*K.passIgnoreGrowth-1,'second failure: longer')
 -- Retenue pendant l'attente : aucun dépassement de cette cible.
 F.tick(e,f,5); F.front(e,f,10,0); F.tick(e,f,1/60); learned(e,f,2,2,60); learned(e,f,3,3,100/3.6)
 -- Terrain perdu pendant l'échec oublié : seule l'attente retient.
 local engaged=false
 for _=1,120 do s.stuck=100; s.closeMeters=0; F.tick(e,f,1/60); if F.passing(s.state) then engaged=true end end
 assert(not engaged,'held behind an ignored target: no retenue pass')
 s.passIgnoreUntil=e.time; for _=1,120 do s.stuck=100; s.closeMeters=0; F.tick(e,f,1/60); if F.passing(s.state) then engaged=true end end
 assert(engaged,'once the wait is over: retenue pass')
 -- Course : la cible n'ignore jamais son suiveur (drapeaux bleus, classes).
 local r,fr=F.scene('C',3); r.p.personalLineJitter=0; E.changed(r); F.tick(r,fr,0.2)
 local rs=r.states[2]; F.front(r,fr,20,-10)
 rs.state='OVT_IN'; rs.target=3; rs.targetSide=1; rs.passStartAt=r.time; rs.passMinGap=20; rs.passName='x'; rs.abortSlow=0; rs.passAlongside=false
 for _=1,5*60 do F.tick(r,fr,1/60); if rs.state~='OVT_IN' and rs.state~='OVT_HOLD' then break end end
 assert(rs.reason=='abort_slow' and rs.passIgnore==3 and r.states[3].yieldIgnore~=2,'race: the target keeps yielding when asked')
end
-- Retenue seulement derrière une cible qui ne s'éloigne pas.
tests.RETENUE_GATE_141=function()
 local function run(sa)
  local e,f=F.scene('J',3); e.p.personalLineJitter=0; e.p.pressureEnabled=false; E.changed(e); F.tick(e,f,0.2)
  F.front(e,f,10,sa); F.tick(e,f,1/60); learned(e,f,2,2,60); learned(e,f,3,3,100/3.6); local s=e.states[2]
  local engaged=false
  for _=1,150 do s.stuck=100; F.tick(e,f,1/60); if F.passing(s.state) then engaged=true end end
  return engaged
 end
 assert(not run(-6),'target pulling away: no retenue pass')
 assert(run(0),'held at the same speed: retenue pass')
end
-- Cession à une IA aussi rapide (pression) : perdue au bout de K.followerStallTime s en ligne droite (« lost », pas
-- « abouties »), puis plus de cession à ce suiveur pendant K.passIgnore s.
tests.YIELD_LOST_141=function()
 local e,f=F.scene('J',3); e.p.personalLineJitter=0; E.changed(e)
 F.rear(e,f,8,0); F.tick(e,f,7)
 assert(F.yielding(e.states[2].state),'pressure yield (PDR T05)')
 F.tick(e,f,K.followerStallTime+8)
 assert((e.stats.lost or 0)==1 and (e.stats.passed or 0)==0,'yield lost, not completed')
 assert(e.states[2].yieldIgnore==3 and e.states[2].yieldIgnoreUntil>e.time,'follower no longer waited for')
 F.tick(e,f,10); assert(not F.yielding(e.states[2].state),'no new yield to the same follower')
 -- Suiveur plus rapide connu, mais allure libre ici pas meilleure : pas de cession à la pression.
 local e2,f2=F.scene('J',3); e2.p.personalLineJitter=0; E.changed(e2); F.tick(e2,f2,0.2)
 -- Beta 1.59 : hors course, refus seulement à un suiveur nettement plus lent ici (allure voisine : cession).
 F.rear(e2,f2,8,0); F.tick(e2,f2,1/60); learned(e2,f2,2,2,100/3.6); learned(e2,f2,3,3,90/3.6); F.tick(e2,f2,8); assert(not F.yielding(e2.states[2].state),'clearly slower free pace: no pressure yield')
end
-- Vitesse de pointe réduite de K.yieldTopCut km/h pour l'IA qui cède, suiveur proche, en ligne droite.
tests.YIELD_TOP_SPEED_141=function()
 local e,f=F.scene('J',3); E.changed(e)
 F.place(f,2,0,150); F.place(f,3,-14.4,150); learned(e,f,2,2,150/3.6)
 local s=e.states[2]
 local function hold()
  s.state='YIELD_HOLD'; s.target=3; s.targetSide=1; s.followers[3]=true; s.yieldStart=e.time; s.holdUntil=e.time+60; s.yieldDetection=100; s.yieldMargin=5
 -- Beta 1.60 (lot 3) : suiveur tenu hors dépassement (sinon passage franc et lever de pied franc : tests/review160w.lua)
  e.states[3].restUntil=e.time+10
 end
 for _=1,3*60 do hold(); F.tick(e,f,1/60) end
 -- Beta 1.59 : hors course, aussi sous la vitesse du suiveur (150 km/h ici) de K.yieldPassDeltaKmh km/h.
 local cut=math.min(150-K.yieldTopCut,150-K.yieldPassDeltaKmh)
 assert(math.abs(e.commands[2].speedLimit-cut)<0.01,'top speed cut: '..e.commands[2].speedLimit)
 -- Allure libre ici plus haute : la limite monte avec elle, toujours sous celle du suiveur.
 learned(e,f,2,2,170/3.6); for _=1,2 do hold(); F.tick(e,f,1/60) end
 assert(math.abs(e.commands[2].speedLimit-math.min(170-K.yieldTopCut,150-K.yieldPassDeltaKmh))<0.01,'follows the usual top speed, under the follower: '..e.commands[2].speedLimit)
 learned(e,f,2,2,150/3.6)
 -- Beta 1.59 : hors course, levée progressive (jamais sous la vitesse du moment, remontée de K.yieldCapReleaseKmh km/h/s).
 local released=function() for _=1,math.ceil(K.yieldCapReleaseMargin/K.yieldCapReleaseKmh*60)+2 do hold(); F.tick(e,f,1/60); assert(e.commands[2].speedLimit>=f.cars[2].kmh-1e-6,'never under its speed while released: '..e.commands[2].speedLimit..' vs '..f.cars[2].kmh..' state '..e.states[2].state) end return e.commands[2].speedLimit>=K.unlimitedSpeed end
 f.cars[2].yawRate=e.run.cornerYawRef*0.9; assert(released(),'corner: released')
 f.cars[2].yawRate=0
 for _=1,3*60 do hold(); F.tick(e,f,1/60) end
 assert(e.commands[2].speedLimit<K.unlimitedSpeed,'capped again on the straight')
 F.place(f,3,-300,150); for _=1,6 do hold(); F.tick(e,f,1/60) end; assert(released(),'no close follower: released')
end
-- Plafond anti-zigzag : le retour sur la ligne personnelle est la ligne ; côté du dépassement dès l'image de la décision.
tests.DIRECTION_LINE_141=function()
 local e,f=F.scene('J',3); local s=e.states[2]; local a=f.cars[2]; local row=e.perception.rows[2]
 row.left=false; row.right=false
 s.state='OVT_OUT'; s.base=-0.08; s.direction=1; s.offset=0.5; s.filtered=0.5; s.lastDirectionAt=-math.huge
 D.lateral(s,s.base,row,a,e.run,e.runtimeG,1/60,100)
 assert(s.direction==0 and s.directionSides[s.directionHead]==0,'back to its own line: the line, not the opposite side')
 -- Conduite libre (maintien de ligne au départ, retour) : jamais compté, même d'un côté à l'autre.
 s.state='DRIVE'; s.direction=0; local head=s.directionHead
 for n=1,8 do for _=1,30 do D.lateral(s,(n%2==0 and 1 or -1)*0.6,row,a,e.run,e.runtimeG,1/60,100+n) end end
 assert(s.directionHead==head and not s.newDirectionLimit,'free driving never counted')
 -- Ligne personnelle d'un côté, dépassement de l'autre : un seul changement noté.
 local e2,f2=F.scene('J',3); e2.p.personalLineJitter=0; E.changed(e2)
 local s2=e2.states[2]; s2.persona.laneBias=0.1
 F.front(e2,f2,35,30); F.tick(e2,f2,1)
 assert(F.passing(s2.state) and s2.targetSide==-1,'pass engaged on the left')
 local n=0; for j=1,K.directionLimit do if s2.directionStates[j]:sub(1,3)=='OVT' then n=n+1; assert(s2.directionSides[j]==-1,'noted on its side') end end
 assert(n==1,'one change of side for one pull-out: '..n)
end
-- Sortie des stands : jonction apprise, voiture de la voie vue près d'elle, IA retenue tant qu'une voiture arrive.
tests.PIT_EXIT_MERGE_141=function()
 local e,f=F.scene('J',4); e.p.personalLineJitter=0; E.changed(e); f.length=10000
 F.place(f,1,8000,100); F.place(f,2,6000,100); F.place(f,4,9000,0); f.cars[4].pit=true; f.cars[4].inPitBox=true
 local a3=F.place(f,3,1900,60); a3.pit=true
 F.tick(e,f,6); F.place(f,3,2000,60); a3.pit=false; F.tick(e,f,1/60)
 assert(math.abs(e.merge.spline*f.length-2000)<1 and logged(e,'jonction des stands: relevee a 2000 m'),'merge point learned')
 -- Un déplacement n'apprend rien.
 F.place(f,3,5000,100)
 local a4=f.cars[4]; a4.inPitBox=false; F.place(f,4,1960,50); F.tick(e,f,0.1)
 -- IA de la voie à 40 m de la jonction, voiture en piste à 150 m d'elle à 200 km/h : retenue.
 F.place(f,2,1850,200); F.place(f,3,5000,100); F.tick(e,f,1/60)
 assert(e.commands[4].mergeHold and not a4.merging,'held while a car arrives, not in the way of its radar')
 assert(logged(e,'jonction des stands: Driver_4 attend Driver_2'),'logged')
 F.refresh(e,f,2); assert(not P.find(e.perception.rows[2],4),'a held car is not seen by the track car')
 F.place(f,2,2100,200); F.tick(e,f,1/60)
 assert(not e.commands[4].mergeHold and logged(e,'repart apres') and logged(e,'piste libre'),'released once the car is past')
 F.refresh(e,f,2); assert(a4.merging and P.find(e.perception.rows[2],4),'released near the merge: seen by the track car')
 F.place(f,2,1850,200); F.tick(e,f,1/60); assert(not e.commands[4].mergeHold,'once per exit')
 -- Nouvelle sortie, circulation sans fin : K.mergeHoldMax s au plus.
 F.place(f,4,1700,0); a4.inPitBox=true; F.tick(e,f,1/60); a4.inPitBox=false; F.place(f,4,1960,50)
 local held=0
 for _=1,(K.mergeHoldMax+2)*60 do F.place(f,2,1850,200); F.tick(e,f,1/60); if e.commands[4].mergeHold then held=held+1 end end
 assert(held>=K.mergeHoldMax*60-2 and held<=K.mergeHoldMax*60+2 and logged(e,'attente maximale'),'held '..K.mergeHoldMax..' s at most: '..held)
 -- Loin de la jonction : ni vue ni retenue.
 a4.inPitBox=true; F.tick(e,f,1/60); a4.inPitBox=false; F.place(f,4,1500,50); F.place(f,2,1300,200); F.tick(e,f,1/60)
 F.refresh(e,f,2); assert(not e.commands[4].mergeHold and not a4.merging and not P.find(e.perception.rows[2],4),'far from the merge: not seen, not held')
 -- Joueur et drapeau rouge : jamais retenus.
 F.place(f,4,1960,50); F.place(f,2,1850,200)
 F.place(f,4,1700,0); a4.inPitBox=true; F.tick(e,f,1/60); a4.inPitBox=false; F.place(f,4,1960,50)
 Merge.update(e.merge,f,e.commands,e.time,1/60,e.log,true,'J',true); assert(not e.commands[4].mergeHold,'red flag: never held')
 Merge.update(e.merge,f,e.commands,e.time,1/60,e.log,false,'J',true); assert(e.commands[4].mergeHold,'same exit without the red flag: held')
 local p1=f.cars[1]; p1.pit=true; F.place(f,1,1960,50); F.place(f,4,9000,0); a4.inPitBox=true
 F.tick(e,f,1/60); assert(not e.commands[1].mergeHold,'player never held')
end
-- Applicateur : retenue au bout de la voie des stands (exception à la règle D12), rendue aussitôt.
tests.PIT_EXIT_HOLD_WRITES_141=function()
 local host=require('tests/host').create(true); local e,f=F.scene('J'); local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false; cmd.stopHold=false; cmd.mergeHold=false end
 local car=f.cars[2]; car.pit=true; car.inPitBox=false; e.commands[2].mergeHold=true
 A.apply(a,f,e.commands,e.g,10); assert(a.cars[2].stop and host.stops[1]==K.stopPulse,'held at the end of the pit lane')
 e.commands[2].mergeHold=false; A.apply(a,f,e.commands,e.g,11); assert(not a.cars[2].stop and host.stops[1]==0,'released')
 car.pit=false; e.commands[2].mergeHold=true; A.apply(a,f,e.commands,e.g,12); assert(not a.cars[2].stop,'on track: never by the pit-exit hold')
end
-- Journée circuit : voiture de sécurité identifiée avant la répartition, jamais posée en piste.
tests.SAFETY_CAR_NOT_SPREAD_141=function()
 local e,f=F.scene('J',12); E.select(e,'J'); e.profiles.J.section_traffic=true; e.profiles.J.spawnPitPct=0; E.changed(e)
 E.floodInit(e,'','[AI_FLOOD]\nENABLED=0\n',false)
 e.g.safetyCarModel='sc_test'; e.g.safetyCarPicked=true; f.cars[7].id='sc_test'
 f.length=25000; f.session=1; f.time=0.6
 for i=2,f.count do local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0 end
 F.tick(e,f,0.1)
 local x=e.traffic.exits
 assert(x.mode=='track' and x.count==10 and x.place[7]<0,'safety car kept in its pit ('..x.count..' placed)')
end
-- Allure apprise : 50 m par endroit au plus sur un long circuit, 400 endroits sur un circuit ordinaire.
tests.PACE_BINS_141=function()
 local e,f=F.scene('J',3); f.length=60611; F.tick(e,f,1/60)
 assert(e.delta.bins==1213 and #e.states[2].pace==1213,'Isle of Man: 1213 bins')
 learned(e,f,2,3,50); F.tick(e,f,2)
 assert((e.delta.fleet[1][1213] or 0)>0 and (e.delta.fleet[1][1] or 0)>0,'whole fleet table refreshed in 2 s')
 local e2,f2=F.scene('J',3); f2.length=4000; F.tick(e2,f2,1/60)
 assert(e2.delta.bins==C.K.paceBins and #e2.states[2].pace==C.K.paceBins,'ordinary track: unchanged')
end
-- Journal : vrais contacts (une fois par paire et par période), cessions sans passage, fins de dépassement en clair.
tests.JOURNAL_141=function()
 local e,f=F.scene('J',3); E.changed(e)
 f.cars[2].collidedWith=3; F.tick(e,f,1/60); f.cars[2].collidedWith=nil
 assert(e.stats.contactEvent==1,'contact counted')
 f.cars[2].collidedWith=3; F.tick(e,f,1); f.cars[2].collidedWith=nil
 assert(e.stats.contactEvent==1,'once per pair and per '..K.contactLogPeriod..' s')
 local text=require('src/journal').summary(e)
 assert(text:find(', contacts 1, reprises au calme 0,',1,true) and text:find(', cessions sans passage 0,',1,true),'minute summary')
 local s=e.states[2]; s.state='OVT_IN'; s.target=3; s.passStartAt=e.time; s.passName='Driver_3'; s.passMinGap=10
 f.cars[2].pit=true; F.tick(e,f,1/60)
 assert(logged(e,'Driver_3 : rendue a AC (stands, hors piste ou hors commande)'),'guard in plain words')
end
-- Fin d'un épisode de lenteur : la vraie raison (rentrée aux stands), plus « roule de nouveau normalement ».
tests.SLOW_END_REASON_141=function()
 local e,f=isleOfMan(); F.tick(e,f,2+K.slowLogTime+1)
 assert(count(e,'IA anormalement lente: Driver_2 (car_2) a 30 km/h')==1,'episode logged')
 f.cars[2].pit=true; F.tick(e,f,K.slowEnd+1)
 assert(logged(e,'IA anormalement lente: Driver_2 ne retient plus le trafic apres') and logged(e,'(rentree aux stands)'),'real reason logged')
end
-- Chronomètre du coût : compteur Windows, sinon os.preciseClock s'il avance pendant l'image, sinon os.clock ; source
-- notée une fois.
tests.FRAME_CLOCK_141=function()
 local saved=os.preciseClock
 os.preciseClock=nil; local t=A.osClock(); assert(t and t.source=='os.clock (1 ms)' and type(t.read())=='number','os.clock')
 local n=0; os.preciseClock=function() n=n+1; return n*1e-6 end
 t=A.osClock(); assert(t.source=='os.preciseClock','os.preciseClock when it moves')
 os.preciseClock=function() return 5 end
 t=A.osClock(); assert(t.source=='os.clock (1 ms)','frozen within a frame: os.clock')
 os.preciseClock=saved
 local a=A.new(); local notes={}; a.note=function(_,text) notes[#notes+1]=text end
 if a.timer then A.clock(a); A.clock(a); assert(#notes==1 and notes[1]:find('cout par image mesure par: ',1,true),'source noted once') end
end
-- ---------------------------------------------------------------------------------------------------------------
-- Relecture adversariale de la Beta 1.41 (scénarios de scratchpad/adv141 repris).
-- Lecture des vrais fichiers : io.open capturé au chargement, avant que le banc ne le remplace.
local openFile=io.open
-- Voie des stands de 10 km : jonction apprise à 2000 m, IA 4 dans la voie, voiture 2 en piste qui arrive.
local function mergeScene(profile)
 local e,f=F.scene(profile or 'J',4); e.p.personalLineJitter=0; E.changed(e); f.length=10000
 F.place(f,1,8000,100); F.place(f,2,6000,100); F.place(f,4,9000,0); f.cars[4].pit=true; f.cars[4].inPitBox=true
 local a3=F.place(f,3,1900,60); a3.pit=true
 F.tick(e,f,6); F.place(f,3,2000,60); a3.pit=false; F.tick(e,f,1/60)
 F.place(f,3,5000,100)
 assert(e.merge.spline>=0,'merge point learned')
 local a4=f.cars[4]
 local function leave(box,at,kmh) F.place(f,4,box,0); a4.inPitBox=true; F.tick(e,f,1/60); a4.inPitBox=false; F.place(f,4,at,kmh) end
 return e,f,a4,leave
end
-- B1 : retenue en journée circuit seulement (course : la circulation sans fin la retenait 20 s à chaque sortie).
tests.REVIEW_MERGE_PROFILE_141=function()
 for _,profile in ipairs({'C','P','Q'}) do
  local e,f,_,leave=mergeScene(profile); leave(1700,1960,50)
  local held=0
  for k=1,25*60 do F.place(f,2,2000-150-((k*69/60)%450),250); F.tick(e,f,1/60); if e.commands[4].mergeHold then held=held+1 end end
  assert(held==0 and not logged(e,'attend'),profile..': never held at the pit exit ('..held..' frames)')
 end
 -- Arrêt natif indisponible : ni retenue ni « attend » au journal.
 local e,f,_,leave=mergeScene('J'); leave(1700,1960,50); e.stopCap=false
 F.place(f,2,1850,200); F.tick(e,f,1/60)
 assert(not e.commands[4].mergeHold and not logged(e,'attend'),'stop capability unavailable: no hold, nothing logged')
 e.stopCap=true; F.tick(e,f,1/60); assert(e.commands[4].mergeHold and logged(e,'Driver_4 attend Driver_2'),'stop capability back: held')
end
-- B1 : jamais une voiture qui roule vers son emplacement ni une voiture arrêtée à côté du sien en fin de voie ; seulement
-- une IA qui roule après avoir dépassé son emplacement ; fenêtre d'arrivée de K.mergeWindowMax s au plus.
tests.REVIEW_MERGE_BOX_141=function()
 local e,f,a4,leave=mergeScene('J')
 -- Arrivée dans la voie (jamais encore à son emplacement pendant ce passage), son emplacement en fin de voie.
 a4.inPitBox=false; F.place(f,4,1500,0); F.tick(e,f,1/60); a4.pit=false; F.tick(e,f,1/60); a4.pit=true
 F.place(f,4,1960,40); F.place(f,2,1850,200); F.tick(e,f,1/60)
 assert(not e.commands[4].mergeHold,'driving to its own pit box: never held')
 -- Emplacement à 40 m de la jonction : à sa hauteur ou à peine plus loin, jamais retenue.
 leave(1960,1960,20); F.place(f,2,1850,200); F.tick(e,f,1/60)
 assert(not e.commands[4].mergeHold,'at its own pit box: never held')
 F.place(f,4,1970,20); F.tick(e,f,1/60); assert(not e.commands[4].mergeHold,'10 m past its box: not yet')
 F.place(f,4,1980,20); F.tick(e,f,1/60); assert(e.commands[4].mergeHold,'15 m past its box, moving: held')
 -- Arrêtée après son emplacement sans retenue en cours : jamais retenue (elle ne roule pas vers la sortie).
 local e2,f2,_,leave2=mergeScene('J'); leave2(1700,1960,0); F.place(f2,2,1850,200); F.tick(e2,f2,1/60)
 assert(not e2.commands[4].mergeHold,'stopped: no new hold')
 -- Fenêtre : à l'arrêt, une voiture à 6 s de la jonction ne retient plus (9 s avant la relecture), à 4 s oui.
 local e3,f3,_,leave3=mergeScene('J'); leave3(1700,1960,20)
 F.place(f3,2,2000-6*55,198); F.tick(e3,f3,1/60); assert(not e3.commands[4].mergeHold,'car 6 s away: free')
 F.place(f3,2,2000-4*55,198); F.tick(e3,f3,1/60); assert(e3.commands[4].mergeHold,'car 4 s away: held')
 assert(K.mergeHoldMax==10 and K.mergeWindowMax<=5,'10 s wait at most, 5 s arrival window')
end
-- M4 : voiture de la voie vue en piste seulement en roulant, ou au pas tout près de la jonction ; file arrêtée,
-- joueur qui attend et IA arrêtée : invisibles.
tests.REVIEW_MERGE_SEEN_141=function()
 local e,f,a4,leave=mergeScene('J'); leave(1700,1950,0)
 local function seen(at,kmh) F.place(f,4,at,kmh); F.place(f,2,1700,200); F.tick(e,f,1/60); F.refresh(e,f,2); return a4.merging and P.find(e.perception.rows[2],4)~=nil end
 assert(not seen(1950,0),'stopped 50 m before the merge: invisible')
 assert(not seen(1985,0),'stopped 15 m before the merge: invisible')
 assert(not seen(1950,10),'crawling 50 m before the merge: invisible')
 assert(seen(1985,10),'crawling 15 m before the merge: seen')
 assert(seen(1950,40),'moving 50 m before the merge: seen')
 -- Joueur à l'arrêt au bout de la voie : invisible pour les IA en piste.
 local p1=f.cars[1]; p1.pit=true; F.place(f,1,1990,0); F.place(f,4,9000,0); a4.inPitBox=true; F.place(f,2,1700,200); F.tick(e,f,1/60); F.refresh(e,f,2)
 assert(not p1.merging and not P.find(e.perception.rows[2],1),'waiting player: invisible')
end
-- m7 : app à l'arrêt, passage dans la voie oublié : une sortie pendant l'arrêt n'apprend rien.
tests.REVIEW_MERGE_IDLE_141=function()
 local e,f=F.scene('J',3); E.changed(e); f.length=10000
 local a=F.place(f,3,1900,60); a.pit=true; F.tick(e,f,6)
 Merge.idle(e.merge,e.commands)
 assert(not e.merge.cars[3].wasPit and e.merge.cars[3].pitFor==0,'lane visit forgotten')
 F.place(f,3,2000,60); a.pit=false; Merge.update(e.merge,f,e.commands,e.time,1/60,e.log,false,'J',true)
 assert(e.merge.spline<0,'nothing learned from a lane exit seen across a stop of the app')
end
-- M1 : allure du joueur apprise sur les mêmes endroits que celle de la flotte (60 km : 1213 endroits).
tests.REVIEW_PLAYER_PACE_BINS_141=function()
 local e,f=F.scene('J',3); f.length=60611; F.tick(e,f,1/60)
 F.place(f,1,30000,150); F.place(f,2,50000,100); F.place(f,3,10000,100)
 F.tick(e,f,3,true)
 local s=e.states[1]; local b=require('src/delta').bin(f.cars[1].spline,e.delta.bins)
 assert(e.delta.bins==1213 and (s.pace[b] or 0)>0,'player pace learned at its place among 1213 bins')
 for j=e.delta.bins+1,#s.pace do assert(s.pace[j]==nil,'no stale bin') end
end
-- M2 : le joueur collé derrière une IA qui lui cède n'est jamais « perdu » ni ignoré.
tests.REVIEW_PLAYER_NOT_STALLED_141=function()
 local e,f=F.scene('J',3); e.p.personalLineJitter=0; E.changed(e)
 F.place(f,3,30000,100)
 F.rear(e,f,8,0,1); F.tick(e,f,7)
 local s=e.states[2]
 assert(F.yielding(s.state),'yields to the player (pressure)')
 F.tick(e,f,K.followerStallTime+8)
 assert((e.stats.lost or 0)==0 and s.yieldIgnore~=1 and (s.ignoreTarget~=1 or e.time>=s.ignoreUntil),'player never lost nor ignored')
 assert(s.followerStall[1]==0,'player never counted as a stalled follower')
end
-- m2 : état anormal oublié au changement de session.
tests.REVIEW_SLOW_SESSION_RESET_141=function()
 local e,f=isleOfMan(); F.tick(e,f,2+K.slowObstacleTime)
 assert(e.states[2].abnormal,'abnormal')
 e.states[2].slowPitAsked=true; e.states[2].slowPitDone=true
 f.session=1; f.type=3; F.tick(e,f,1/60)
 local s=e.states[2]
 assert(not s.abnormal and s.abnormalFor==0 and s.abnormalCalm==0 and not s.slowPitSent and not s.slowPitAsked and not s.slowPitDone,'forgotten at the session change')
end
-- M3 : rythme habituel encore inconnu : ligne de diagnostic de la 1.39 (allure de la classe). Beta 1.59 (journées circuit
-- du 10 novembre) : hors course, obstacle quand même sous K.slowUnknownRatio fois l'allure de sa classe ; état anormal :
-- une ligne à son entrée.
tests.REVIEW_SLOW_UNKNOWN_RATIO_141=function()
 local e,f=isleOfMan(); for i=2,4 do e.states[i].longRatioTime=0 end
 f.cars[2].damageSuspension=0.4
 F.tick(e,f,30)
 assert(count(e,'IA anormalement lente: Driver_2 (car_2) a 30 km/h')==1 and logged(e,'(habituelle de l IA inconnue, allure de la classe)'),'1.39 diagnostic line, 1.59 class pace')
 assert(e.states[2].abnormal,'1.59: track day, unknown usual pace, 30 km/h where its class runs 200: obstacle all the same')
 local e2,f2=isleOfMan(); F.tick(e2,f2,2+K.slowObstacleTime+3)
 assert(count(e2,'IA lente a contourner: Driver_2, obstacle pour les voitures derriere (30 km/h, habituelle de l IA 200 km/h, 1 voiture(s) derriere)')==1,'entry in the abnormal state logged once')
end
-- m1 : lenteur passagère, jamais cumulée avant l'état anormal.
tests.REVIEW_SLOW_INTERMITTENT_141=function()
 local e,f=F.scene('J',3); e.p.personalLineJitter=0; E.changed(e); f.length=60611; F.tick(e,f,1/60)
 learned(e,f,2,3,200/3.6)
 F.place(f,1,-20000,0); F.place(f,3,40000,200)
 local seen=false
 for _=1,4 do
  for _=1,90 do F.place(f,2,1000,100); F.tick(e,f,1/60) end
  for _=1,360 do F.place(f,2,1000,190); F.tick(e,f,1/60); seen=seen or e.states[2].abnormal end
  seen=seen or e.states[2].abnormal
 end
 assert(not seen and e.states[2].abnormalFor==0,'four 1.5 s slow spots: never abnormal')
 -- Au pas : la raison de fin dit « au pas », pas « allure de référence inconnue ».
 local e2,f2=isleOfMan(); F.tick(e2,f2,2+K.slowLogTime+1); F.place(f2,2,1000,8); F.place(f2,3,1000-15-4.4,7); F.tick(e2,f2,K.slowEnd+1)
 assert(logged(e2,'(roule au pas (moins de '..K.slowMinKmh..' km/h))') and not logged(e2,'allure de reference inconnue'),'crawl reason in plain words')
end
-- m4 et m5 : l'attente d'une paire ignorée ne bloque jamais un drapeau bleu (ni pour l'IA qui cède, ni pour la suiveuse).
tests.REVIEW_BLUE_NOT_IGNORED_141=function()
 -- IA qui cède (essais) : suiveuse qui lui prend un tour, ignorée après un échec.
 local function yields(lapped)
  local e,f=F.scene('P',3); e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
  local a2=F.place(f,2,5000,100); local a3=F.place(f,3,5000-40,140)
  a2.lap=3; a3.lap=lapped and 4 or 3; a2.lapValid=true; a3.lapValid=true
  e.states[2].nextPerception=0
  local s=e.states[2]; local yielded=false
  for _=1,4*60 do s.yieldIgnore=3; s.yieldIgnoreUntil=e.time+300; F.tick(e,f,1/60,true); yielded=yielded or F.yielding(s.state) end
  return yielded,s
 end
 local blue,s=yields(true); assert(blue and s.yieldBlue,'blue flag honoured despite the pair wait')
 assert(not yields(false),'ordinary yield: the pair wait still applies')
 -- Suiveuse : dépassement sur une cession au drapeau bleu malgré l'attente de la paire.
 local function pass(blueYield)
  local e,f=F.scene('J',3); e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
  F.front(e,f,15,0); F.tick(e,f,1/60); learned(e,f,2,3,100/3.6)
  local s,o=e.states[2],e.states[3]; local engaged=false
  for _=1,150 do
   s.passIgnore=3; s.passIgnoreUntil=e.time+300
   o.state='YIELD_HOLD'; o.target=2; o.targetSide=1; o.followers[2]=true; o.yieldStart=e.time; o.holdUntil=e.time+30; o.yieldBlue=blueYield
   F.tick(e,f,1/60); if F.passing(s.state) then engaged=true end
  end
  return engaged
 end
 assert(pass(true),'blue-flag yield: passes despite the pair wait')
 assert(not pass(false),'ordinary yield: the pair wait still applies')
end
-- m8 : couloir jugé sur l'allure libre seulement derrière une IA anormalement lente ; ailleurs, écart du moment.
tests.REVIEW_CORRIDOR_141=function()
 local saved=P.corridor; local asked,gap,v,vo; local attacker=2
 P.corridor=function(cars,count,i,side,req,front,...)
  -- Premier couloir demandé : celui du déclenchement (ceux du dépassement en cours suivent).
  if i==attacker and not asked then asked=req; gap=cars[front].z-cars[i].z-(cars[i].length+cars[front].length)*0.5; v=cars[i].speed; vo=cars[front].speed end
  return saved(cars,count,i,side,req,front,...)
 end
 local ok,err=pcall(function()
  local e,f=F.scene('J',3); e.p.personalLineJitter=0; e.p.pressureEnabled=false; E.changed(e); F.tick(e,f,0.2)
  F.front(e,f,10,0); F.tick(e,f,1/60); learned(e,f,2,2,60); learned(e,f,3,3,100/3.6); local s=e.states[2]
  asked=nil; for _=1,150 do s.stuck=100; F.tick(e,f,1/60); if asked then break end end
  local a,o=f.cars[2],f.cars[3]
  local base=(10+a.length+o.length+2*e.run.overtakeClearMargin)*a.speed
  assert(asked and math.abs(asked-require('src/util').clamp(base/K.corridorSpeedMin,K.corridorMin,K.corridorMax))<0.5,'held behind an ordinary car: corridor from the speed of the moment ('..tostring(asked)..')')
  -- Cible anormalement lente : écart de vitesse de l'allure libre.
  local e2,f2=isleOfMan(false); F.place(f2,2,1000,28); F.place(f2,3,1000-15-4.4,27); attacker=3
  asked=nil; F.tick(e2,f2,2+K.slowObstacleTime); for _=1,120 do if asked then break end; F.tick(e2,f2,1/60) end
  local U=require('src/util'); local free=e2.states[3].freePace
  assert(asked,'pass corridor asked behind the abnormal car')
  local span=(gap+8.8+2*e2.run.overtakeClearMargin)*v
  local expected=U.clamp(span/math.max(v-vo,free-vo,K.corridorSpeedMin),K.corridorMin,K.corridorMax)
  local moment=U.clamp(span/math.max(v-vo,K.corridorSpeedMin),K.corridorMin,K.corridorMax)
  assert(math.abs(asked-expected)<0.5 and moment-expected>1,'abnormal car ahead: free-pace corridor ('..asked..' m, '..expected..' m expected, '..moment..' m from the speed of the moment)')
 end)
 P.corridor=saved
 assert(ok,err)
end
-- m6 : course sans l'onglet Règles : une IA lente et endommagée appelée aux stands une fois par session.
tests.REVIEW_SLOW_PIT_ONCE_141=function()
 local function race(rules)
  local r,fr=F.scene('C',4); r.p.personalLineJitter=0; r.profiles.C.section_rules=rules; E.changed(r); fr.length=60611; F.tick(r,fr,1/60)
  learned(r,fr,2,4,200/3.6)
  F.place(fr,1,-20000,0); F.place(fr,2,1000,30); F.place(fr,3,1000-15-4.4,28); F.place(fr,4,30000,200); fr.cars[2].damageSuspension=0.37
  F.tick(r,fr,2+K.slowPitTime+K.slowObstacleTime+1)
  assert(r.commands[2].rulePit,'first call')
  -- Passage aux stands sans réparation, puis de nouveau lente derrière la file.
  local a=fr.cars[2]; a.pit=true; F.tick(r,fr,1); a.pit=false
  for i=2,4 do r.states[i].longRatio=1; r.states[i].longRatioTime=K.longRatioMin end
  F.place(fr,2,1000,30); F.place(fr,3,1000-15-4.4,28); F.tick(r,fr,2+K.slowPitTime+K.slowObstacleTime+1)
  return r.commands[2].rulePit,r
 end
 local again,r=race(false); assert(not again and logged(r,'deja appelee aux stands cette session, plus de demande'),'rules unticked: one call per session')
 assert(race(true),'rules ticked: called again')
end
-- m10 : dépannage d'une IA lente et endommagée : jamais « immobile » ; le déplacement la répare.
tests.REVIEW_RECOVER_TEXT_141=function()
 local host=require('tests/host').create(true); local e,f=F.scene('J'); local a=A.new(); assert(A.access(a))
 local notes={}; a.note=function(_,text) notes[#notes+1]=text end
 for _,cmd in ipairs(e.commands) do cmd.active=false; cmd.stopHold=false; cmd.mergeHold=false end
 local cmd=e.commands[2]; cmd.recover=true; cmd.recoverReason='lente et endommagee'; cmd.recoverStill=31
 A.apply(a,f,e.commands,e.g,10)
 local text=table.concat(notes,'\n')
 assert(host and text:find('IA lente et endommagee depannee a son stand, reparee par le deplacement (lente depuis 31 s)',1,true) and not text:find('immobile',1,true),'plain text: '..text)
end
-- m12 : une constante de la Beta 1.41 qui en écraserait une autre arrête le chargement.
tests.REVIEW_K_COLLISION_141=function()
 local root=package.path:match('^([^;]+)/%?%.lua'); local file=assert(openFile(root..'/src/config.lua','rb')); local text=file:read('*a'); file:close()
 local marker='clockProbeLoops=20000,'
 assert(text:find(marker,1,true),'marker found')
 local injected=text:gsub(marker:gsub('%p','%%%0'),marker..'paceBins=400,',1)
 local chunk=assert(loadstring(injected,'=config'))
 local ok,err=pcall(chunk)
 assert(not ok and tostring(err):find('paceBins',1,true),'duplicate key refused: '..tostring(err))
 assert(pcall(assert(loadstring(text,'=config'))),'real file loads')
end
-- Panneaux lumineux (Melbourne, layout_f1_2026, journée circuit du 3 novembre : « non detectes ») : inclusions en
-- en-tête avec « ../../ », « extension/... » depuis le dossier d'AC ; sorties du dossier du circuit refusées ; limite.
tests.LIGHTS_INCLUDES_141=function()
 local host=require('tests/host').create(true); local a=A.new(); assert(A.access(a))
 local sep=string.char(92)
 local function path(...) return table.concat({...},sep) end
 local flags='[INCLUDE]\nINCLUDE = common/conditions.ini\n[CONDITION_1]\nNAME=MYRACING_FLAG\nINPUT=FLAG_TYPE\n[MATERIAL_ADJUSTMENT_0]\nACTIVE=1\nCONDITION=MYRACING_FLAG\n'
 host.files[path('cfgsys','tracks','common','conditions.ini')]='[CONDITION_85]\nNAME=RACING_FLAG\nINPUT=FLAG_TYPE\n'
 local lines={'[INCLUDE: ../../extension/ext_config.ini]','[INCLUDE: mel22.ini]','[INCLUDE: extension/config/tracks/loaded/mel22.ini]'}
 for n=1,10 do lines[#lines+1]='[INCLUDE: ../../common/part'..n..'.ini]'; host.files[path('tracks','mel','common','part'..n..'.ini')]='[INCLUDE]\nINCLUDE = common/conditions.ini\n[DEFAULTS]\n' end
 lines[#lines+1]='[INCLUDE: ../../common/digitalflags.ini]'
 host.files[path('tracks','mel','lay','extension','ext_config.ini')]=table.concat(lines,'\n')..'\n'
 host.files[path('tracks','mel','extension','ext_config.ini')]='[INCLUDE: ../common/missing.ini]\n'
 host.files[path('tracks','mel','common','digitalflags.ini')]=flags
 host.trackLayout='lay'
 assert(A.trackLights(a,'mel')==true and a.trackLightsSource==path('common','digitalflags.ini'),'parent-relative include detected: '..tostring(a.trackLightsSource))
 -- Avant la Beta 1.41 : toute inclusion avec « .. » ignorée, non détecté (la variante seule ne s'allume sur rien).
 host.files[path('tracks','mel','common','digitalflags.ini')]='[DEFAULTS]\n'
 a.trackLightsFor=nil; assert(A.trackLights(a,'mel')==false,'nothing lit: not equipped')
 assert(a.trackLightsDetail:find('(14 fichier(s) lu(s), inclusions non lues : 3 introuvable(s), 0 hors du circuit et de CSP, 0 au-dela de la limite)',1,true),'what was read: '..a.trackLightsDetail)
 -- Sorties du dossier du circuit, chemins absolus : jamais lus (même si le fichier existe).
 for _,f in ipairs({path('tracks','x.ini'),path('tracks','other','common','f.ini'),'C:'..sep..'f.ini',path('cfgsys','..','f.ini')}) do host.files[f]=flags end
 host.files[path('tracks','esc','extension','ext_config.ini')]='[INCLUDE: ../../x.ini]\n[INCLUDE: ../../other/common/f.ini]\n[INCLUDE: C:/f.ini]\n[INCLUDE: /f.ini]\n[INCLUDE: ../../../../../../f.ini]\n[INCLUDE]\nINCLUDE = common/../../../f.ini\n'
 host.trackLayout=nil; a.trackLightsFor=nil
 assert(A.trackLights(a,'esc')==false,'escapes refused')
 assert(a.trackLightsDetail:find('0 introuvable(s), 6 hors du circuit et de CSP',1,true),'escapes counted: '..a.trackLightsDetail)
 -- Même fichier sous deux casses : lu une fois.
 host.files[path('tracks','dup','extension','ext_config.ini')]='[INCLUDE: ../Common/A.ini]\n[INCLUDE: ../common/a.ini]\n'
 host.files[path('tracks','dup','Common','A.ini')]='[DEFAULTS]\n'; host.files[path('tracks','dup','common','a.ini')]='[DEFAULTS]\n'
 a.trackLightsFor=nil; assert(A.trackLights(a,'dup')==false and a.trackLightsDetail:find('(2 fichier(s) lu(s)',1,true),'read once whatever the case: '..a.trackLightsDetail)
 -- Limite de fichiers lus : le reste compté, jamais une erreur.
 local many={}
 for n=1,K.lightsFiles+6 do many[#many+1]='[INCLUDE: f'..n..'.ini]'; host.files[path('tracks','big','extension','f'..n..'.ini')]='[DEFAULTS]\n' end
 host.files[path('tracks','big','extension','ext_config.ini')]=table.concat(many,'\n')
 a.trackLightsFor=nil; assert(A.trackLights(a,'big')==false and a.trackLightsDetail:find('('..K.lightsFiles..' fichier(s) lu(s)',1,true) and a.trackLightsDetail:find('7 au-dela de la limite',1,true),'limit: '..a.trackLightsDetail)
 -- « extension/... » depuis le dossier d'AC (configuration de CSP).
 local get=ac.getFolder
 ac.getFolder=function(id) if id==ac.FolderID.ContentTracks then return path('ac','content','tracks') elseif id==ac.FolderID.ExtCfgSys then return path('ac','extension','config') end return get(id) end
 host.files[path('ac','content','tracks','root','extension','ext_config.ini')]='[INCLUDE: extension/config/tracks/loaded/root2.ini]\n'
 host.files[path('ac','extension','config','tracks','loaded','root2.ini')]=flags
 a.trackLightsFor=nil; local ok=A.trackLights(a,'root'); ac.getFolder=get
 assert(ok==true and a.trackLightsSource==path('loaded','root2.ini'),'AC-root relative include: '..tostring(a.trackLightsSource))
end
-- Bandeaux de coupe et de pénalité qu'AC dessine lui-même (sessions de la Beta 1.40) : notés, jamais repris sur
-- l'overlay ; les autres messages (autres apps, votes, aides) repris comme avant.
tests.AC_DRAWN_MESSAGES_141=function()
 local e,f=F.scene('J',3); e.g.overlayMessages=true; F.tick(e,f,0.1)
 local h=e.hud
 local function shown(title,text,kind) h.msgUntil=-math.huge; E.message(e,title,text,kind,3); return h.msgUntil>e.time end
 assert(not shown('CUT DETECTED','LAP WILL NOT COUNT','illegal'),'cut banner not duplicated')
 assert(not shown('PENALTY, SLOW DOWN FOR 9 SECONDS OR SLOW DOWN TO 35 KMH','BEFORE THE END OF CURRENT LAP','illegal'),'penalty banner not duplicated')
 assert(not shown('PENALTY','',nil),'bare penalty title')
 assert(not shown('DRIVE THROUGH PENALTY','',nil) and not shown('','You have been disqualified for not clearing the Track Cut penalty',nil),'drive-through, disqualification')
 assert(not shown('Jump-start: Drive-through','',nil) and not shown('Cut detected','',nil),'case and variants')
 assert(logged(e,'message d AC: CUT DETECTED : LAP WILL NOT COUNT') and logged(e,'message d AC: PENALTY, SLOW DOWN FOR 9 SECONDS'),'still logged')
 assert(count(e,'messages d AC: penalites et coupes laissees a l affichage d AC (CSP ne permet pas de les masquer)')==1,'explained once per session')
 assert(shown('SetupLab','setup tour rapide v1 prêt',nil) and h.msgText:find('SetupLab',1,true),'other apps: shown')
 assert(shown('Restart session voting ended.','Not passed',nil),'votes: shown')
 assert(shown('ABS','3','illegal'),'illegal kind without a penalty text: shown')
 assert(shown('Brake Bias','68.0 %',nil),'aids shown')
 -- Nouvelle session : explication de nouveau.
 -- (même ligne dans les K.logDedup s : regroupée par le journal)
 f.session=1; F.tick(e,f,0.1); F.tick(e,f,e.log.dedup+1); shown('CUT DETECTED','LAP WILL NOT COUNT','illegal')
 assert(count(e,'messages d AC: penalites et coupes laissees')==2,'once per session')
end
-- Annonces de l'app (en anglais « Penalty », « Disqualified… ») revenues par ac.onMessage : reprises, jamais prises
-- pour un bandeau d'AC.
tests.OWN_MESSAGES_NOT_DROPPED_141=function()
 local e,f=F.scene('J',3); e.g.overlayMessages=true; F.tick(e,f,0.1)
 local h=e.hud; local en=require('src/lang_en').messages
 local function shown(title,text) h.msgUntil=-math.huge; E.message(e,title,text,nil,3); return h.msgUntil>e.time end
 for _,key in ipairs({'penaltyPass','penaltyJump','penaltyDq'}) do
  local m=en[key]; local text=m[2]:gsub('%%%.0f','3'):gsub('%%d','3')
  assert(E.drawnByAC(m[1],text),key..': looks like an AC banner')
  e.ownTitle=m[1]; e.ownText=text
  assert(shown(m[1],text),key..': the app’s own announcement is shown')
 end
 e.ownTitle='Penalty'; e.ownText='other'
 assert(not shown('Penalty','an AC text'),'same title, other text: AC banner, not shown')
end
return tests
