-- Beta 1.61, tranche C : retardataires et classes (noms terminés par _161C). Chargé par tests/extended.lua.
-- Réglage classNuance (coupé par défaut) : temps d'arrivée du drapeau bleu, cession jamais avant un freinage, niveau
-- rendu, trêve entre retardataires, dédoublement, classes, drapeau bleu du joueur en deux temps et clé annexe.
-- Valeurs des voitures : celles que le jeu fournit (position, vitesse, tour, lacet) ; sens latéral du jeu (-1 / -1)
-- et sens du banc (+1 / +1) pour les cas où le côté compte.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local J=require('src/journal')
local D=require('src/director')
local Nuance=require('src/nuance')
local Zones=require('src/zones')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function scene(profile,n,nuance,set,sign)
 local e,f=F.scene(profile,n or 3); local p=e.profiles[profile]
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.startDelay=0; p.startRelax=0; p.laneBiasEnabled=false
 p.classNuance=nuance==true
 if set then set(p) end
 if sign then e.g.offsetSign=sign; e.g.sideSign=sign end
 E.changed(e)
 F.place(f,1,-5000,100)
 return e,f
end
-- Voiture 3 derrière la voiture 2, à gap m et sa km/h de plus, avec laps tours d'avance, pendant seconds s.
local function lapping(e,f,gap,sa,laps,seconds,each)
 local t=0; local yielded=false
 while t<seconds do
  F.rear(e,f,gap,sa); if laps>0 then f.cars[3].lap=f.cars[2].lap+laps end
  if each then each() end
  F.tick(e,f,1/60); t=t+1/60
  if F.yielding(e.states[2].state) then yielded=true end
 end
 return yielded
end

tests.K_161C=function()
 assert(K.blueCatchTime==5 and K.blueBrakeTime==2 and K.blueZoneTime==4 and K.blueFastSa==20 and K.blueSlowMin==0.02 and K.nuanceBattleTime==1 and K.blueTruceAfter==2)
 assert(K.unlapMargin==1.3 and K.relapHold==10 and K.relapSa==8 and K.classSideLat==1.5 and K.classNoDiveTime==2 and K.classAmCorridor==1.2 and K.classTrainTime==2)
 assert(K.bluePlayerOrderTime==2 and K.blueStartGrace==30 and K.blueTrainRange==200 and K.trafficKeyBytes==160)
 assert(K.blueSlowMin<K.blueSlowdown and K.bluePlayerOrderTime<K.blueCatchTime,'ranges ordered')
 for _,profile in ipairs({'J','P','Q','C','H'}) do
  local ok,p=pcall(C.defaults,profile)
  if ok and p then assert(p.classNuance==false,profile..': off by default') end
 end
 assert(C.pendingKeys.classNuance==nil,'no longer pending')
end
-- a) Drapeau bleu : la distance seule ne suffit plus. 140 m et +5 km/h (100 s) : pas de cession ; réglage coupé : comme
-- avant ; voiture collée à 30 m, à la même vitesse : cession.
tests.BLUE_CATCH_TIME_161C=function()
 assert(Nuance.catch(140,5)==false and Nuance.catch(K.blueCloseGap,0)==true and Nuance.catch(60,45)==true and Nuance.catch(60,43)==false,'catch time')
 for _,sign in ipairs({1,-1}) do
  local e,f=scene('C',3,true,nil,sign)
  lapping(e,f,140,5,2,5)
  assert(not F.yielding(e.states[2].state) and e.states[2].state~='YIELD_OUT','far and slow-closing: no yield yet ('..e.states[2].state..')')
  local o,g=scene('C',3,false,nil,sign)
  lapping(o,g,140,5,2,5)
  assert(F.yielding(o.states[2].state),'switch off: as before, yields on distance ('..o.states[2].state..')')
  local c,h=scene('C',3,true,nil,sign)
  assert(lapping(c,h,30,0,2,5),'held right behind: yields ('..c.states[2].state..')')
  local q,k=scene('C',3,true,nil,sign)
  assert(lapping(q,k,60,45,2,5),'arriving within the catch time: yields ('..q.states[2].state..')')
 end
end
-- b) Jamais de cession à K.blueBrakeTime s d'un point de freinage (appris, ou zone du circuit) : attente notée une fois.
tests.BLUE_NOT_INTO_BRAKING_161C=function()
 local e,f=scene('C',3,true)
 e.fl.count=1; e.fl.points[1]=40/f.length
 local yielded=lapping(e,f,30,10,2,3)
 local s=e.states[2]
 assert(not yielded,'braking point 40 m ahead: the yield waits ('..s.state..')')
 assert(s.bluePending==true and s.blueReason=='freinage proche','waiting level and reason: '..tostring(s.blueReason))
 assert(count(e,'drapeau bleu: Driver_2 attend la sortie pour Driver_3 (freinage proche, 40 m)')==1 and e.stats.blueBrakeWait==1,'one line, one count ('..count(e,'attend la sortie')..')')
 -- Plus de point devant : la cession part.
 e.fl.count=0
 lapping(e,f,30,10,2,3)
 assert(F.yielding(s.state),'no braking point: yields ('..s.state..')')
 -- Point loin (au-delà de K.blueBrakeTime s) : aucune attente.
 local far,g=scene('C',3,true)
 far.fl.count=1; far.fl.points[1]=200/g.length
 lapping(far,g,30,10,2,3)
 assert(F.yielding(far.states[2].state) and (far.stats.blueBrakeWait or 0)==0,'braking point 200 m ahead at 100 km/h: no wait')
 -- Zone « brake » du fichier du circuit (Zones.nextBrake, tranche A) : même attente.
 local saved=Zones.nextBrake
 Zones.nextBrake=function() return 40/10000 end
 local z,h=scene('C',3,true)
 lapping(z,h,30,10,2,3)
 Zones.nextBrake=saved
 assert(not F.yielding(z.states[2].state) and z.stats.blueBrakeWait==1,'brake zone of the track file: the yield waits')
 -- Réglage coupé : le point de freinage ne retient rien.
 local o,k=scene('C',3,false)
 o.fl.count=1; o.fl.points[1]=40/k.length
 lapping(o,k,30,10,2,3)
 assert(F.yielding(o.states[2].state) and (o.stats.blueBrakeWait or 0)==0,'switch off: yields as before')
 assert(J.english('drapeau bleu: A attend la sortie pour B (freinage proche, 40 m)')=='blue flag: A waits for the exit for B (braking zone ahead, 40 m)',J.english('drapeau bleu: A attend la sortie pour B (freinage proche, 40 m)'))
end
-- b) Zone d'attaque à moins de K.blueZoneTime s devant, voiture pas encore collée : la cession l'attend.
tests.BLUE_PREFERS_ATTACK_ZONE_161C=function()
 local saved=Zones.nextAttack
 Zones.nextAttack=function() return 80/10000 end
 local e,f=scene('C',3,true)
 lapping(e,f,60,45,2,3)
 local c,g=scene('C',3,true)
 lapping(c,g,30,5,2,3)
 Zones.nextAttack=saved
 assert(not F.yielding(e.states[2].state) and e.states[2].blueReason=='zone d attaque proche','attack zone 80 m ahead: the yield waits for it ('..e.states[2].state..')')
 assert(F.yielding(c.states[2].state),'lapping car already held behind: no wait for the zone')
 local n,h=scene('C',3,true)
 lapping(n,h,60,45,2,3)
 assert(F.yielding(n.states[2].state),'no attack zone known: yields')
end
-- c) Niveau rendu : K.blueSlowMin quand la voiture arrive K.blueFastSa km/h plus vite, K.blueSlowdown retenue derrière.
tests.BLUE_SLOWDOWN_RANGE_161C=function()
 assert(math.abs(Nuance.slowdown(20)-0.02)<1e-12 and math.abs(Nuance.slowdown(45)-0.02)<1e-12,'much faster: 2 %')
 assert(math.abs(Nuance.slowdown(0)-0.08)<1e-12 and math.abs(Nuance.slowdown(-5)-0.08)<1e-12,'held: 8 %')
 assert(math.abs(Nuance.slowdown(10)-0.05)<1e-12,'linear in between')
 local function level(nuance,sa)
  local e,f=scene('C',3,nuance)
  lapping(e,f,30,sa,2,4)
  assert(F.yielding(e.states[2].state),'yielding')
  return e.commands[2].level
 end
 local fastOn,fastOff=level(true,25),level(false,25)
 assert(fastOn>fastOff*1.03,'lapping car much faster: the backmarker keeps more of its level ('..fastOn..' against '..fastOff..')')
 local heldOn,heldOff=level(true,0),level(false,0)
 assert(math.abs(heldOn-heldOff)<1e-3 and fastOn>heldOn*1.03,'held behind: the full slowdown, as before ('..heldOn..' against '..heldOff..')')
end
-- d) Deux retardataires en lutte rattrapées : trêve jusqu'au passage des deux, plus K.blueTruceAfter s.
tests.BLUE_TRUCE_161C=function()
 local e,f=scene('C',4,true)
 local function each() F.place(f,4,20+4.4,100) end
 lapping(e,f,30,10,2,4,each)
 local s=e.states[2]
 assert(F.yielding(s.state),'rear backmarker yields first ('..s.state..')')
 assert(count(e,'drapeau bleu: treve Driver_2 / Driver_4, Driver_3 passe d abord')==1 and e.stats.blueTruce==1,'one truce line ('..count(e,'treve')..')')
 local t=e.nuance; local now=e.time
 assert(Nuance.truced(t,2,4,now) and Nuance.truced(t,4,2,now) and not Nuance.truced(t,2,3,now),'truce between the pair only')
 local front=e.perception.rows[4].neighbors[1]
 local row2=e.perception.rows[2]; local n=row2.front>0 and row2.neighbors[row2.front]
 assert(n and n.index==4 and D.nuanceGate(e,s,f.cars[2],n,e.run,'C',f,now,2)=='treve','no attack on the other backmarker during the truce')
 assert(front~=nil)
 -- La voiture qui prend un tour a passé la 2 : sa part finit K.blueTruceAfter s plus tard ; la trêve tient pour la 4.
 Nuance.passed(t,2,3,now)
 assert(math.abs(t.untilAt[2]-(now+K.blueTruceAfter))<1e-9 and Nuance.truced(t,2,4,now+K.blueTruceAfter+1),'held until the front one is passed too')
 Nuance.passed(t,4,3,now+5)
 assert(Nuance.truced(t,2,4,now+5+K.blueTruceAfter-0.1) and not Nuance.truced(t,2,4,now+5+K.blueTruceAfter+0.1),'released K.blueTruceAfter s after both are passed')
 -- Bornée par la durée maximale de cession quoi qu'il arrive.
 local u=Nuance.new(); assert(Nuance.truce(u,2,4,3,100,25)==true and Nuance.truce(u,2,4,3,101,25)==false,'new truce told once')
 assert(Nuance.truced(u,2,4,125.9) and not Nuance.truced(u,2,4,126.1),'ends on the timer')
 Nuance.passed(u,2,9,101); assert(Nuance.truced(u,2,4,120),'another car passing does not end it')
 -- Voiture de devant loin (plus de K.nuanceBattleTime s) : pas de trêve. Réglage coupé : rien.
 local far,g=scene('C',4,true)
 lapping(far,g,30,10,2,4,function() F.place(g,4,60+4.4,100) end)
 assert((far.stats.blueTruce or 0)==0,'no battle: no truce')
 local o,h=scene('C',4,false)
 lapping(o,h,30,10,2,4,function() F.place(h,4,20+4.4,100) end)
 assert((o.stats.blueTruce or 0)==0 and count(o,'treve')==0,'switch off: no truce')
 assert(J.english('drapeau bleu: treve A / B, C passe d abord')=='blue flag: truce A / B, C goes first',J.english('drapeau bleu: treve A / B, C passe d abord'))
end
-- e) Dédoublement : pas d'attaque en retour juste après avoir été doublée, dédoublement en ligne droite seulement.
tests.RELAP_HOLD_161C=function()
 local e,f=scene('C',3,true)
 F.front(e,f,10,5); F.tick(e,f,0.2)
 local s=e.states[2]; local row=e.perception.rows[2]; local n=row.neighbors[row.front]
 assert(n and n.index==3,'car 3 ahead')
 local now=e.time
 assert(D.nuanceGate(e,s,f.cars[2],n,e.run,'C',f,now,2)==nil,'nothing holds an ordinary pass')
 s.relapBy=3; s.relapUntil=now+K.relapHold
 assert(D.nuanceGate(e,s,f.cars[2],n,e.run,'C',f,now,2)=='tour tout juste pris','just lapped by it: no attack back')
 local sa=n.sa; n.sa=K.relapSa
 assert(D.nuanceGate(e,s,f.cars[2],n,e.run,'C',f,now,2)==nil,'unless clearly faster')
 n.sa=sa
 assert(D.nuanceGate(e,s,f.cars[2],n,e.run,'C',f,now+K.relapHold+0.1,2)==nil,'over after K.relapHold s')
 assert(D.nuanceGate(e,s,f.cars[2],n,e.run,'P',f,now,2)==nil,'outside the race the lap gap means nothing')
end
tests.UNLAP_WIDE_MARGIN_161C=function()
 local e,f=scene('C',3,true)
 F.front(e,f,10,5); f.cars[3].lap=f.cars[2].lap+1; F.tick(e,f,0.2)
 F.front(e,f,10,5); f.cars[3].lap=f.cars[2].lap+1
 local s=e.states[2]; local row=e.perception.rows[2]; local n=row.neighbors[row.front]
 local a=f.cars[2]
 a.corner=1
 assert(D.nuanceGate(e,s,a,n,e.run,'C',f,e.time,2)==nil,'un-lapping on a straight: allowed')
 a.corner=K.lapCorner-0.01
 assert(D.nuanceGate(e,s,a,n,e.run,'C',f,e.time,2)=='dedoublement hors ligne droite','un-lapping in a corner: waits')
 f.cars[3].lap=f.cars[2].lap
 assert(D.nuanceGate(e,s,a,n,e.run,'C',f,e.time,2)==nil,'same lap: the ordinary corner rule')
end
-- e) Pas de défense contre une voiture à un tour qui se dédouble : une ligne, jamais l'état DEFEND.
tests.UNLAP_NO_DEFENCE_161C=function()
 local function run(nuance)
  local e,f=scene('C',3,nuance,function(p) p.defenseEnabled=true; p.noMoveBraking=false end)
  local s=e.states[2]; s.persona.assertiveness=1
  local t=0; local defended=false
  while t<2 do
   F.place(f,2,0,150); F.place(f,3,-15,160,0.8); f.cars[2].lap=f.cars[2].lap+2; s.nextPerception=0
   F.tick(e,f,1/60); t=t+1/60
   if s.state=='DEFEND' or s.defendAttacker==3 then defended=true end
  end
  return e,defended
 end
 local e,defended=run(true)
 assert(not defended,'no defence against a lapped car un-lapping itself')
 assert(count(e,'retardataire: Driver_3 se dedouble de Driver_2 (+10 km/h), sans defense')==1 and e.stats.unlap==1,'one line ('..count(e,'se dedouble')..')')
 local o,considered=run(false)
 assert(considered and count(o,'se dedouble')==0 and (o.stats.unlap or 0)==0,'switch off: defence considered as before, nothing logged')
 assert(J.english('retardataire: A se dedouble de B (+6 km/h), sans defense')=='backmarker: A unlaps itself from B (+6 km/h), no defence',J.english('retardataire: A se dedouble de B (+6 km/h), sans defense'))
end
-- f) Classe lente : voiture rapide déjà décalée, la ligne est tenue ; droit derrière, elle s'écarte comme avant.
local function classes(e) e.states[2].class=3; e.states[3].class=1; e.states[2].classified=true; e.states[3].classified=true; e.classes.nextAt=e.time+600 end
tests.CLASS_HOLD_SIDE_CHOSEN_161C=function()
 for _,sign in ipairs({1,-1}) do
  local function run(nuance,x)
   local e,f=scene('C',3,nuance,function(p) p.multiClass=true end,sign)
   classes(e)
   local t=0
   while t<4 do F.place(f,2,0,100); F.place(f,3,-30-4.4,120,x); e.states[2].nextPerception=0; F.tick(e,f,1/60); t=t+1/60 end
   return e
  end
  local e=run(true,2)
  assert(not F.yielding(e.states[2].state),'faster class already 2 m to one side: the slower car holds its line ('..e.states[2].state..')')
  assert(count(e,'classe: Driver_2 tient sa ligne, Driver_3 deja decale')==1 and e.stats.classHold>=1,'one line per K.nuanceLogGap s ('..count(e,'tient sa ligne')..')')
  local b=run(true,0)
  assert(F.yielding(b.states[2].state),'faster class straight behind: moves aside ('..b.states[2].state..')')
  local o=run(false,2)
  assert((o.stats.classHold or 0)==0 and count(o,'tient sa ligne')==0,'switch off: no hold')
 end
 assert(Nuance.classHold(1.5) and Nuance.classHold(-1.6) and not Nuance.classHold(1.4))
end
-- f) Classe rapide : pas de plongeon à K.classNoDiveTime s d'un point de freinage derrière une classe lente.
tests.CLASS_NO_DIVE_161C=function()
 local e,f=scene('C',3,true,function(p) p.multiClass=true end)
 e.states[2].class=1; e.states[3].class=3; e.states[2].classified=true; e.states[3].classified=true; e.classes.nextAt=e.time+600
 F.front(e,f,10,10); F.tick(e,f,0.2); F.front(e,f,10,10)
 local s=e.states[2]; local row=e.perception.rows[2]; local n=row.neighbors[row.front]
 local a=f.cars[2]; a.corner=1
 assert(D.nuanceGate(e,s,a,n,e.run,'C',f,e.time,2)==nil,'no braking point: the faster class may pass')
 e.fl.count=1; e.fl.points[1]=((a.z+40)/f.length)%1
 assert(D.nuanceGate(e,s,a,n,e.run,'C',f,e.time,2)=='classe lente au freinage','braking point 40 m ahead: waits for the exit')
 assert(D.nuanceGate(e,s,a,n,e.run,'P',f,e.time+1,2)=='classe lente au freinage','in every session')
 assert(count(e,'classe: Driver_2 attend la sortie pour passer Driver_3 (classe lente au freinage)')==1 and e.stats.classWait==1,'one line per target')
 e.fl.points[1]=((a.z+200)/f.length)%1
 assert(D.nuanceGate(e,s,a,n,e.run,'C',f,e.time,2)==nil,'braking point far ahead: free')
 e.fl.points[1]=((a.z+40)/f.length)%1; e.states[2].class=3
 assert(D.nuanceGate(e,s,a,n,e.run,'C',f,e.time,2)==nil,'same class: the ordinary rules')
 assert(J.english('classe: A attend la sortie pour passer B (classe lente au freinage)')=='class: A waits for the exit to pass B (slower class braking)')
end
-- f) Groupe de la classe rapide : la voiture qui suit à K.classTrainTime s au plus passe avec le groupe.
tests.CLASS_TRAIN_161C=function()
 local frame={cars={{speed=40},{speed=40},{speed=40}}}
 local row={count=2,neighbors={{index=2,gap=30,long=-30},{index=3,gap=100,long=-100}}}
 local followers={false,true,false}
 assert(Nuance.train(row,row.neighbors[2],followers,frame)==true,'70 m behind a car already waited for, at 40 m/s: within 2 s')
 row.neighbors[2].gap=30+81
 assert(Nuance.train(row,row.neighbors[2],followers,frame)==false,'more than K.classTrainTime s behind the group')
 followers[2]=false; row.neighbors[2].gap=79
 assert(Nuance.train(row,row.neighbors[2],followers,frame)==true,'within 2 s of the yielding car itself')
end
-- g) Drapeau bleu du joueur : annonce puis ordre ; plus tard pour une voiture qui remonte lentement ; clé annexe.
local function player(nuance,gap,sa,set,laps)
 local e,f=F.scene('C',3); local p=e.profiles.C
 p.classNuance=nuance; if set then set(p,e) end
 E.changed(e)
 local t=0
 while t<2.5 do
  F.place(f,1,0,100); F.place(f,2,5000,100); F.place(f,3,-gap-4.4,100+sa)
  if (laps or 2)>0 then f.cars[3].lap=f.cars[1].lap+(laps or 2) end
  F.tick(e,f,1/60); t=t+1/60
 end
 return e,f
end
tests.PLAYER_BLUE_STAGES_161C=function()
 local e=player(true,100,30)
 assert(e.panel.kind~='blue','100 m and +30 km/h (12 s): not yet ('..e.panel.kind..')')
 assert(e.sideText[Nuance.sideKey]~=nil and e.sideText[Nuance.sideKey]:find('^v=1;blue=none;stage=none;car=%-1;gap=0;closing=0;count=0;stamp=%d+$'),'side key says none: '..tostring(e.sideText[Nuance.sideKey]))
 local o=player(false,100,30)
 assert(o.panel.kind=='blue' and o.sideText[Nuance.sideKey]==nil,'switch off: blue on distance as before, no side key')
 local a=player(true,40,30)
 assert(a.panel.kind=='blue' and a.nuance.stage=='advise' and a.nuance.kind=='lap','40 m and +30 km/h (4.8 s): advise ('..a.panel.kind..', '..a.nuance.stage..')')
 assert(a.sideText[Nuance.sideKey]:find('^v=1;blue=lap;stage=advise;car=2;gap=40;closing=30;count=1;stamp=%d+$'),a.sideText[Nuance.sideKey])
 assert(count(a,'drapeau bleu joueur: annonce (Driver_3 a 40 m, ')==1,'one line on the stage')
 local r=player(true,15,30)
 assert(r.panel.kind=='blue' and r.nuance.stage=='order','15 m and +30 km/h (1.8 s): order ('..r.nuance.stage..')')
 assert(r.sideText[Nuance.sideKey]:find('blue=lap;stage=order;car=2;gap=15;') and #r.sideText[Nuance.sideKey]<=K.trafficKeyBytes,r.sideText[Nuance.sideKey])
 local h=player(true,30,0)
 assert(h.panel.kind~='blue','at equal speed behind: not closing, no flag (as before)')
 assert(J.english('drapeau bleu joueur: annonce (A a 40 m, 1.2 s, 2 voiture(s))')=='player blue flag: advise (A at 40 m, 1.2 s, 2 car(s))',J.english('drapeau bleu joueur: annonce (A a 40 m, 1.2 s, 2 voiture(s))'))
end
tests.PLAYER_BLUE_CLASS_161C=function()
 local function class(p,e) p.multiClass=true; e.states[1].class=3; e.states[3].class=1; e.states[1].classified=true; e.states[3].classified=true; e.classes.nextAt=1e9 end
 local e=player(true,15,30,class,0)
 assert(e.panel.kind=='blue' and e.nuance.kind=='class','faster class on the same lap: blue flag ('..e.panel.kind..', '..e.nuance.kind..')')
 assert(e.sideText[Nuance.sideKey]:find('^v=1;blue=class;stage=order;car=2;'),e.sideText[Nuance.sideKey])
 assert(count(e,'drapeau bleu joueur: classe (Driver_3 a 15 m, ')==1)
 local o=player(false,15,30,class,0)
 assert(o.panel.kind~='blue','switch off: no blue flag for a faster class on the same lap')
 local s=player(true,15,30,nil,0)
 assert(s.panel.kind~='blue','single class, same lap: none')
end
tests.PLAYER_BLUE_START_GRACE_161C=function()
 local e=player(true,15,30,function(_,e) e.startedAt=e.time-10 end)
 assert(e.panel.kind~='blue' and e.sideText[Nuance.sideKey]:find('blue=none'),'10 s after the start: not raised')
 local l=player(true,15,30,function(_,e) e.startedAt=e.time-K.blueStartGrace-1 end)
 assert(l.panel.kind=='blue','after K.blueStartGrace s: raised')
 local r=player(true,15,30,function(_,e) e.startedAt=-1000; e.launchAt=e.time-5 end)
 assert(r.panel.kind~='blue','after a standing start following a formation lap: grace from the real start')
end
-- Clé annexe : seulement quand son contenu change, au plus une fois par seconde, 160 caractères au plus.
tests.TRAFFIC_KEY_161C=function()
 local t=Nuance.new(); local e={sideText={},stats={},log={limit=0},incidents={},states={},startedAt=-1000}
 local frame={player=0,length=5000,count=0,cars={}}
 assert(Nuance.playerBlue(t,e,frame,{blueFlagEnabled=true},'C',100,false)==nil and e.sideText[Nuance.sideKey]==nil,'no player: nothing written')
 local e2,f2=player(true,40,30)
 local first=e2.sideText[Nuance.sideKey]
 for _=1,90 do F.place(f2,1,0,100); F.place(f2,3,-40-4.4,130); f2.cars[3].lap=f2.cars[1].lap+2; F.tick(e2,f2,1/60) end
 assert(e2.sideText[Nuance.sideKey]~=first and e2.sideText[Nuance.sideKey]:find('stage=advise;car=2;gap=40;',1,true),'blue active, same content: rewritten every second with the stamp advancing (contrat SpotterEnginer, finition 1.61): '..e2.sideText[Nuance.sideKey])
 for _=1,90 do F.place(f2,1,0,100); F.place(f2,3,-15-4.4,130); f2.cars[3].lap=f2.cars[1].lap+2; F.tick(e2,f2,1/60) end
 assert(e2.sideText[Nuance.sideKey]~=first and e2.sideText[Nuance.sideKey]:find('stage=order'),'content changed: rewritten')
 -- Finition 1.61 : plus de drapeau bleu : une réécriture « none », puis plus rien tant que rien ne change.
 for _=1,120 do F.place(f2,1,0,100); F.place(f2,3,-900,100); f2.cars[3].lap=f2.cars[1].lap; F.tick(e2,f2,1/60) end
 local none=e2.sideText[Nuance.sideKey]
 assert(none and none:find('blue=none',1,true),'no blue flag: none record: '..tostring(none))
 for _=1,180 do F.place(f2,1,0,100); F.place(f2,3,-900,100); f2.cars[3].lap=f2.cars[1].lap; F.tick(e2,f2,1/60) end
 assert(e2.sideText[Nuance.sideKey]==none,'no blue flag and nothing new: not rewritten (stamp of the last change): '..tostring(e2.sideText[Nuance.sideKey]))
end
-- Réglage coupé : rien de la tranche ; essais : le réglage ne change rien (les tours d'écart n'y disent rien).
tests.NUANCE_OFF_IDENTICAL_161C=function()
 local e,f=scene('C',4,false)
 e.fl.count=1; e.fl.points[1]=40/f.length
 lapping(e,f,30,10,2,5,function() F.place(f,4,20+4.4,100) end)
 for _,key in ipairs({'blueBrakeWait','blueTruce','unlap','classWait','classHold','nuanceHold','bluePlayer'}) do assert(e.stats[key]==nil,key..' counted with the switch off') end
 assert(e.sideText[Nuance.sideKey]==nil and e.states[2].relapBy==nil,'no side key, no state')
end
tests.NUANCE_PRACTICE_UNCHANGED_161C=function()
 local function run(nuance)
  local e,f=scene('P',3,nuance)
  e.fl.count=1; e.fl.points[1]=40/f.length
  lapping(e,f,30,10,2,5)
  return e
 end
 local on,off=run(true),run(false)
 assert(on.states[2].state==off.states[2].state and on.states[2].offset==off.states[2].offset and on.commands[2].level==off.commands[2].level,'practice: identical with the switch on')
 assert((on.stats.blueBrakeWait or 0)==0,'no lap rule outside the race')
end
return tests
