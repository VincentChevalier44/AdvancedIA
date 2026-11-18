-- Beta 2.0.4, retours des joueurs du 18 novembre (Overtake) et décisions du pilote (questionnaire du 18 novembre).
-- Chargé par tests/extended.lua.
--  G1 : voiture arrêtée hors piste « écartée » (zone jaune fermée) toujours dépannée comme bloquée (Lincoln Silva) ;
--  G2 : zone jaune locale : un dépassement laisse toujours le temps de rendre la place avant la pénalité ; sous
--       neutralisation, sanction immédiate comme avant (Racer63) ;
--  G3 : classe plus rapide collée derrière à la même allure : laissée passer ; carte des classes au journal
--       (iwouldsayhello).
local F=require('tests/fixture')
local C=require('src/config')
local K=C.K
local E=require('src/engine')
local tests={}
local function logged(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end

-- G1 : journaux du pilote (logs1112) : 128 voitures écartées, une seule dépannée ensuite par l'app.
tests.LOCK_DISMISSED_STILL_TOWED_204=function()
 assert(K.offClearTime<K.stuckRecoverTime,'scene: dismissal comes before the ordinary tow')
 local function run(profile,seconds,spin)
  local e,f=F.scene(profile,3); F.place(f,2,-4000,120)
  local car=F.place(f,3,1000,0,20); car.offtrack=true; car.wheelsOut=4; car.splineLat=20
  local t,recover,reason=0,false,nil
  while t<seconds do
   -- Bac à sable, une fois écartée : elle patine sur place (au-delà du seuil d'arrêt par moments), sans s'éloigner.
   if spin and t>K.offClearTime+1 then car.kmh=(t%1<0.5) and 12 or 0; car.speed=car.kmh/3.6 end
   F.tick(e,f,0.25); t=t+0.25
   if e.commands[3].recover then recover=true; reason=e.commands[3].recoverReason end
  end
  return e,recover,reason
 end
 local e,recover,reason=run('C',K.offClearTime+2)
 local c=e.incidents.cars[3]
 assert(c.dismissed and not c.incident and not recover,'dismissed after 15 s: yellow closed, not towed yet')
 e,recover,reason=run('C',K.stuckRecoverTime+3)
 assert(recover and reason=='bloquee','dismissed car still towed as stuck ('..tostring(recover)..', '..tostring(reason)..')')
 assert(e.states[3].retirePending==nil,'intact car towed: back to its pit box, repaired, not retired')
 e,recover,reason=run('P',K.stuckRecoverTime+3)
 assert(recover and reason=='bloquee','practice too')
 e,recover,reason=run('C',K.stuckRecoverTime+3,true)
 assert(recover,'dismissed, then wheel-spinning in the gravel without moving away: still towed')
end

-- G2 : rendre la place d'abord dans une zone jaune locale.
tests.LOCK_YELLOW_GIVE_BACK_FIRST_204=function()
 local Pe=require('src/penalties')
 local e,f=F.scene('C',3); local p=e.run
 local function zone(neutral) return {cars=e.incidents.cars,playerZone=not neutral,playerNoPass=not neutral,playerInside=not neutral,playerToZone=0,neutral=neutral,red=false,neutralMode=neutral and 'fcy' or '',safetyPhase='none',safety=0} end
 -- Régime en place depuis plus de K.passGiveBack s, puis dépassement d'une IA saine (pas en difficulté).
 local function pass(inc)
  local t=Pe.new(); local now=0
  F.place(f,1,0,100); F.place(f,3,10,100)
  while now<K.passGiveBack+5 do now=now+0.1; Pe.update(t,f,p,'C',inc,now,0.1) end
  F.place(f,1,20,100); now=now+0.1; Pe.update(t,f,p,'C',inc,now,0.1)
  return t,now
 end
 local t,now=pass(zone(false))
 assert(t.count==0 and t.giveBack==3 and t.waitNew==3 and t.waitLocal,'local zone: place to give back first, no penalty yet')
 local due=t.waiting[3]; assert(due and due-now>=K.giveBackMin-1e-6,'at least K.giveBackMin s to give it back')
 -- Place rendue dans le délai : rien.
 local t2,n2=pass(zone(false))
 F.place(f,3,30,100); n2=n2+0.1; Pe.update(t2,f,p,'C',zone(false),n2,0.1)
 for _=1,80 do n2=n2+0.1; Pe.update(t2,f,p,'C',zone(false),n2,0.1) end
 assert(t2.count==0,'place given back in time: no penalty')
 -- Place gardée : pénalité à l'échéance.
 F.place(f,1,20,100); F.place(f,3,10,100)
 while now<due+0.2 do now=now+0.1; Pe.update(t,f,p,'C',zone(false),now,0.1) end
 assert(t.count==1 and t.reason=='pass','place kept: penalty at the deadline')
 -- Neutralisation (FCY) : sanction immédiate, comme avant.
 local t3=pass(zone(true))
 assert(t3.count==1 and t3.reason=='pass','under FCY: immediate penalty as before')
end

-- G2 : ligne de journal, panneau pendant la zone, texte du jaune simple.
tests.LOCK_YELLOW_GIVE_BACK_SHOWN_204=function()
 local L=require('src/lang'); local LE=require('src/lang_en')
 assert(L.flagShort.zone1:find('dépassement interdit',1,true) and LE.flagShort.zone1:find('no overtaking',1,true),'single yellow says no overtaking')
 local Panel=require('src/panel')
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e)
 local panel=Panel.new()
 local t={red=false,neutral=false,neutralMode='fcy',safetyPhase='none',playerZone=true,playerInside=true,playerZoneDouble=false,playerToZone=0,playerDistance=0,greenUntil=-math.huge}
 panel.giveBackDue=true; Panel.update(panel,t,f,e.run,'C',100)
 assert(panel.kind=='warning' and panel.raw==L.flagDetails.giveBack,'place to give back shown inside the yellow zone ('..tostring(panel.kind)..')')
 panel.giveBackDue=false; Panel.update(panel,t,f,e.run,'C',101)
 assert(panel.kind=='zone1','nothing to give back: single yellow as before ('..tostring(panel.kind)..')')
 t.playerZone=false; t.playerInside=false; panel.giveBackDue=true; Panel.update(panel,t,f,e.run,'C',102)
 assert(panel.kind=='warning' and panel.raw==L.flagDetails.giveBack,'after the zone: as before')
 t.playerZone=true; t.playerInside=false; t.playerToZone=100; Panel.update(panel,t,f,e.run,'C',103)
 assert(panel.kind=='yellow','approaching the zone: the flag first, as before')
 local J=require('src/journal')
 local line='place a rendre: le joueur a double Driver_3 sous drapeau jaune (jaune simple), 5 s pour la rendre (180 km/h, elle 140 km/h)'
 assert(J.english(line)=='place to give back: the player passed Driver_3 under yellow (single yellow), 5 s to give it back (180 km/h, that car 140 km/h)',tostring(J.english(line)))
end

-- G2 : bout à bout dans le moteur : une ligne par dépassement à rendre.
tests.LOCK_YELLOW_GIVE_BACK_LOGGED_204=function()
 local e,f=F.scene('C',3)
 local Pe=require('src/penalties')
 local real=Pe.update
 local calls=0
 Pe.update=function(t,...) calls=calls+1; if calls==3 then t.waitNew=3; t.waitLocal=true; t.waiting[3]=e.time+5 end return real(t,...) end
 local ok,err=pcall(function() for _=1,6 do F.tick(e,f,1/60) end end)
 Pe.update=real
 assert(ok,tostring(err))
 assert(logged(e,'place a rendre: le joueur a double Driver_3')==1,'one line per pass ('..logged(e,'place a rendre')..')')
end

-- G3 : classe plus rapide collée derrière à la même allure.
tests.LOCK_CLASS_GLUED_YIELD_204=function()
 assert(K.classGlueGap==15)
 local function run(profile,gap,setup)
  local e,f=F.scene(profile,3); e.p.multiClass=true; e.p.section_endurance=true; e.p.flashMode='never'; e.p.blueFlagEnabled=false; e.p.lapseEnabled=false
  if setup then setup(e) end
  E.changed(e); F.tick(e,f,0.1)
  e.states[2].class=3; e.states[3].class=1; e.states[2].classified=true; e.states[3].classified=true; e.classes.nextAt=e.time+600
  local t=0
  while t<5 do F.place(f,1,-3000,100); F.place(f,2,0,100); F.place(f,3,-gap-4.4,100); e.states[2].nextPerception=0; F.tick(e,f,1/60); t=t+1/60 end
  return e
 end
 assert(F.yielding(run('C',8).states[2].state),'race: faster class glued behind at the same pace: let through')
 assert(F.yielding(run('Q',8).states[2].state),'qualifying too')
 assert(not F.yielding(run('C',30).states[2].state),'30 m behind at the same pace: not glued, line kept')
 local o=run('C',8,function(e) e.p.multiClass=false end)
 assert(not F.yielding(o.states[2].state),'multi-class off: nothing changes')
end

-- G3 : garde du tour lancé : une IA en tour lancé ne cède jamais à une voiture qui ne l'est pas ; les deux lancées : elle
-- cède.
tests.LOCK_CLASS_GLUED_PUSH_GUARD_204=function()
 local function run(fastPushing)
  local e,f=F.scene('Q',3); e.profiles.Q.qualiTraffic=true; e.p.multiClass=true; e.p.section_endurance=true; e.p.flashMode='never'; e.p.blueFlagEnabled=false; e.p.lapseEnabled=false
  E.changed(e); F.tick(e,f,1/60)
  e.states[2].class=3; e.states[3].class=1; e.states[2].classified=true; e.states[3].classified=true; e.classes.nextAt=e.time+600
  local t=0
  while t<5 do
   for _,i in ipairs({1,2,3}) do local c=e.quali.cars[i]; local push=i==2 or fastPushing; c.out=not push; c.cool=false end
   F.place(f,1,-3000,100); F.place(f,2,0,100); F.place(f,3,-8-4.4,100); e.states[2].nextPerception=0; F.tick(e,f,1/60); t=t+1/60
  end
  return e
 end
 local both=run(true)
 assert(both.quali.active and both.quali.push[2] and both.quali.push[3],'scene: both on a flying lap')
 assert(F.yielding(both.states[2].state),'both pushing: the slower class lets the glued faster class through ('..both.states[2].state..')')
 local guard=run(false)
 assert(guard.quali.push[2] and not guard.quali.push[3],'scene: only the slower car pushing')
 assert(not F.yielding(guard.states[2].state),'slower car on a flying lap: never yields to a car on its out-lap ('..guard.states[2].state..')')
end

-- G3 : carte des classes reconnues au journal, une ligne par changement.
tests.LOCK_CLASSES_LOGGED_204=function()
 local Classes=require('src/classes')
 local cars={{valid=true,name='A'},{valid=true,name='B'},{valid=true,name='C'}}
 local states={{classified=true,class=1,classMean=50},{classified=true,class=2,classMean=40,manualClass=true},{classified=false}}
 local sig,text=Classes.summary(cars,states,3)
 assert(sig=='1:1,2:2' and text=='1 = 1 voiture(s), la plus rapide A (180 km/h) ; 2 = 1 voiture(s), la plus rapide B (144 km/h), motif',tostring(text))
 assert(Classes.summary(cars,{{classified=false},{classified=false},{classified=false}},3)==nil,'nothing classified: no line')
 local J=require('src/journal')
 assert(J.english('classes reconnues: '..text)=='classes recognised: 1 = 1 car(s), fastest A (180 km/h) ; 2 = 1 car(s), fastest B (144 km/h), pattern',tostring(J.english('classes reconnues: '..text)))
 local e,f=F.scene('C',3); e.p.multiClass=true; e.p.section_endurance=true; E.changed(e)
 e.p.classPatterns='Car_2:1'; E.changed(e)
 F.tick(e,f,1)
 local n=logged(e,'classes reconnues:')
 F.tick(e,f,K.classPeriod*2+1)
 assert(logged(e,'classes reconnues:')==n,'same map: no new line ('..n..')')
end

-- G4 : grille du départ arrêté après le tour de formation (pilote, Monza, 18 novembre 09:45 : joueur dans la voie des
-- stands, les 9 IA placées derrière lui avancées d'une place, chacune dans l'autre colonne) ; décision du pilote du
-- 18 novembre : « cases vides partout ».
tests.LOCK_GRID_OWN_SLOT_204=function()
 local function scene(n)
  local e,f=F.scene('C',n); C.preset('Course','C',e.profiles.C); E.changed(e); e.gridCaps=true
  for i=1,n do f.cars[i].position=i end
  return e,f
 end
 local function slotZ(k) return -(K.gridFirst+(k-1)*K.gridPitch) end
 -- Joueur (voiture 1, parti 2e) dans la voie des stands à la fin du tour : sa place reste vide.
 local e,f=scene(5)
 for i=1,5 do F.place(f,i,slotZ(i)-200,60) end
 f.cars[1].position=2; f.cars[2].position=1
 F.tick(e,f,0.2)
 local t=e.incidents
 t.formationRank={2,1,3,4,5}; t.formationRankN=5; t.formationAt=e.time-30; t.formationNode={2,1,3,4,5}
 f.cars[1].pit=true
 t.standing='grid'; F.tick(e,f,0.1)
 local g=e.grid
 assert(g.pit[1] and g.slotOf[1]==0,'player in the pit lane: starts from the pits')
 assert(g.slotOf[2]==1 and g.slotOf[3]==3 and g.slotOf[4]==4 and g.slotOf[5]==5,'each AI keeps its own place, place 2 left empty ('..g.slotOf[3]..','..g.slotOf[4]..','..g.slotOf[5]..')')
 -- Colonne : la voiture partie 3e garde la colonne de la place 3 (jamais celle de la place 2).
 assert(g.slots[3] and g.slots[2] and g.slots[3].lateral~=g.slots[2].lateral,'scene: alternate columns')
 -- Sans rang de départ (pas de tour de formation) : places dans l'ordre, comme avant.
 local e2,f2=scene(4)
 for i=1,4 do F.place(f2,i,slotZ(i)-200,60) end
 F.tick(e2,f2,0.2); f2.cars[2].pit=true
 e2.incidents.standing='grid'; F.tick(e2,f2,0.1)
 local g2=e2.grid
 assert(g2.slotOf[1]==1 and g2.slotOf[3]==2 and g2.slotOf[4]==3,'no formation order: places in order as before')
 -- Rangs en double (lecture du classement fausse) : places dans l'ordre, jamais deux voitures sur une place.
 local G=require('src/grid')
 local gg={nodes=nil}
 assert(G.fixedSlots(gg,{1,2,3},3,{1,1,4},0)==nil and G.fixedSlots(gg,{1,2,3},3,{1,2.5,4},0)==nil,'duplicate or broken places: refused')
 assert(G.fixedSlots(gg,{1,2,3},3,nil,0)==nil,'no place read on the grid: places in order')
 assert(G.fixedSlots(gg,{1,2,3},3,{1,3,4},0)==4 and gg.fixed[1]==1 and gg.fixed[2]==3 and gg.fixed[3]==4,'gaps kept')
 assert(G.fixedSlots({nodes={1,2,3}},{1,2,3},3,{1,3,4},0)==nil,'not enough AC_START nodes for the empty places: places in order')
end

-- G5 : chemin de la grille et feux d'un départ arrêté : ni dépassement ni défense (pilote, Monza, 18 novembre 09:45 :
-- une IA arrêtée 2 m à côté de sa place, encore décalée par un dépassement commencé en rejoignant la grille).
tests.LOCK_GRID_NO_RACING_204=function()
 local function run(standing)
  local e,f=F.scene('C'); e.p.blueFlagEnabled=false; e.p.flashMode='never'; E.changed(e)
  F.tick(e,f,40)
  local passing=false
  for _=1,5*60 do
   if standing then e.incidents.standing=standing end
   F.front(e,f,25,40); F.tick(e,f,1/60)
   if F.passing(e.states[2].state) then passing=true end
  end
  return passing,e
 end
 assert(run(nil),'scene: the faster car attacks in the race')
 assert(not run('lights'),'start lights: no overtake')
 assert(not run('grid'),'on the way to the grid: no overtake')
end

-- G6 : arrêtée avant sa place (plus de K.gridHoldDistance m) : tenue en place seulement après GK.shortStill s immobile
-- (pilote, Monza, 18 novembre 09:45 : une IA retenue 2,5 m avant sa place).
tests.LOCK_GRID_NO_EARLY_HOLD_204=function()
 local G=require('src/grid')
 assert(G.GK.shortStill==1.5)
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e); e.gridCaps=true
 for i=1,3 do f.cars[i].position=i end
 local function slotZ(k) return -(K.gridFirst+(k-1)*K.gridPitch) end
 for i=1,3 do F.place(f,i,slotZ(i)-200,60) end
 F.tick(e,f,0.2)
 local t=e.incidents; t.formationRank={1,2,3}; t.formationRankN=3; t.formationAt=e.time-30; t.formationNode={1,2,3}
 t.standing='grid'; F.tick(e,f,0.1)
 local g=e.grid
 -- Voiture 2 : 2,5 m avant sa place, sa vitesse un instant sous le seuil.
 F.place(f,2,slotZ(2)-2.5,1); F.tick(e,f,0.5)
 assert(not g.held[2],'below the still speed for a moment, 2.5 m short: not held yet')
 F.place(f,2,slotZ(2)-2,4); F.tick(e,f,0.5)
 assert(not g.held[2] and g.shortAt[2]==nil,'moving again: timer cleared')
 F.place(f,2,slotZ(2)-2,0); F.tick(e,f,G.GK.shortStill+0.3)
 assert(g.held[2],'really stopped 2 m short for '..G.GK.shortStill..' s: held')
 F.place(f,3,slotZ(3)-1,1); F.tick(e,f,0.1)
 assert(g.held[3],'within K.gridHoldDistance m: held at once as before')
end

-- G7 : place de chaque voiture lue sur la grille au feu vert du tour de formation (pilote, Monza, 18 novembre 10:34 : le
-- classement d'AC comptait une voiture de plus, toutes les IA une place derrière la leur, de biais).
tests.LOCK_GRID_NODE_READ_204=function()
 local G=require('src/grid')
 assert(G.GK.nodeRadius==3)
 local L=5000
 -- Six nœuds en quinconce, 8 m d'une place à l'autre, colonnes -0.5 / +0.5.
 local nodes={}
 for k=1,6 do nodes[k]={spline=((-(10+(k-1)*8))/L)%1,lateral=k%2==1 and -0.5 or 0.5} end
 local function car(k,dz) return {valid=true,splineValid=true,spline=(nodes[k].spline+(dz or 0)/L)%1,splineLat=0,leftWidth=5,rightWidth=5} end
 -- Voitures 1 à 5 posées sur les nœuds 2, 1, 3, 5, 4 ; classement d'AC décalé d'un cran (une voiture de plus devant).
 local frame={length=L,cars={car(2,0.4),car(1,-0.3),car(3),car(5,0.8),car(4)}}
 local rank={[1]=3,[2]=2,[3]=4,[4]=6,[5]=5}
 local node=G.nodeRanks(nodes,frame,rank,-1)
 assert(node and node[1]==2 and node[2]==1 and node[3]==3 and node[4]==5 and node[5]==4,'each car on the node it sits on, whatever the AC classification')
 -- Côte à côte (même abscisse) : le nœud du côté de la voiture.
 local pair={{spline=nodes[1].spline,lateral=-0.5},{spline=nodes[1].spline,lateral=0.5}}
 local right={valid=true,splineValid=true,spline=nodes[1].spline,splineLat=-3,leftWidth=5,rightWidth=5}
 local left={valid=true,splineValid=true,spline=nodes[1].spline,splineLat=3,leftWidth=5,rightWidth=5}
 local nb=G.nodeRanks(pair,{length=L,cars={right,left}},{[1]=1,[2]=2},-1)
 assert(nb and nb[1]==2 and nb[2]==1,'side by side: the node on the side of the car')
 -- Voiture sur aucun nœud, deux voitures sur le même nœud, pas de nœuds : rien (places dans l'ordre, comme avant).
 assert(G.nodeRanks(nodes,{length=L,cars={car(1,5)}},{[1]=1},-1)==nil,'5 m from any node: nothing')
 assert(G.nodeRanks(nodes,{length=L,cars={car(1),car(1,0.5)}},{[1]=1,[2]=2},-1)==nil,'two cars on one node: nothing')
 assert(G.nodeRanks(nil,frame,rank,-1)==nil,'no AC_START nodes: nothing')
 -- Bout à bout : grille avec ces places, le joueur (voiture 1, sur le nœud 2) aux stands : sa place reste vide.
 local e,f=F.scene('C',5); C.preset('Course','C',e.profiles.C); E.changed(e); e.gridCaps=true
 for i=1,5 do f.cars[i].position=rank[i] end
 e.grid.nodes=nodes; f.length=L
 for i=1,5 do F.place(f,i,-(10+(node[i]-1)*8)-200,60) end
 F.tick(e,f,0.2)
 local t=e.incidents; t.formationRank=rank; t.formationRankN=5; t.formationAt=e.time-30; t.formationNode={[1]=2,[2]=1,[3]=3,[4]=5,[5]=4}
 f.cars[1].pit=true
 t.standing='grid'; F.tick(e,f,0.1)
 local g=e.grid
 assert(g.source=='AC_START','scene: AC_START places')
 assert(g.slotOf[2]==1 and g.slotOf[3]==3 and g.slotOf[4]==5 and g.slotOf[5]==4 and g.slotOf[1]==0,'each AI on the place it started from, place 2 empty')
end

-- G7 bis : relevé fait par le tour de formation lui-même, au feu vert (classement d'AC décalé d'un cran).
tests.LOCK_GRID_NODE_READ_AT_GREEN_204=function()
 local L=5000
 local nodes={}
 for k=1,6 do nodes[k]={spline=((-(10+(k-1)*8))/L)%1,lateral=k%2==1 and -0.5 or 0.5} end
 local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); e.profiles.C.raceStart='formation'; e.profiles.C.startRealism=false; f.length=L
 local at={[1]=4,[2]=1,[3]=2,[4]=3}
 for i=1,4 do f.cars[i].position=at[i]+1; F.place(f,i,-(10+(at[i]-1)*8),0) end
 E.changed(e); e.gridCaps=true; e.grid.nodes=nodes; F.tick(e,f,1/60)
 f.started=false; F.tick(e,f,1/60)
 f.started=true; F.tick(e,f,1/60)
 local t=e.incidents
 assert(t.formation,'scene: formation lap armed')
 local n=t.formationNode
 assert(n and n[1]==4 and n[2]==1 and n[3]==2 and n[4]==3,'places read on the grid at the green flag')
end

-- G8 : colonne de la grille sans prolongement (pilote, Monza, 18 novembre 10:53 : la droite par deux places à 16 m,
-- prolongée à 350 m, transformait 0,03 d'écart des nœuds en 0,68 : tête-à-queue à 80 km/h) : la cible suit les places
-- réelles de la colonne et reste toujours entre elles, quels que soient le bruit des nœuds et la distance.
tests.LOCK_GRID_COLUMN_NO_EXTRAPOLATION_204=function()
 local G=require('src/grid')
 local L=5755
 local g={slots={}}
 -- 21 places en quinconce, bruit de quelques centièmes sur chaque nœud (comme Monza).
 local noise={0.03,-0.02,0.01,-0.03,0.02,0,-0.01,0.03,-0.02,0.01,0,0.02,-0.03,0.01,-0.01,0.02,0,-0.02,0.03,-0.01,0.01}
 for k=1,21 do g.slots[k]={spline=((-(220+(k-1)*8))/L)%1,lateral=(k%2==1 and -0.02 or 0.30)+noise[k]} end
 for k=1,21 do
  local lo,hi=math.huge,-math.huge
  for j=k,21,2 do lo=math.min(lo,g.slots[j].lateral); hi=math.max(hi,g.slots[j].lateral) end
  for d=0,400,5 do
   local v=G.columnLateral(g,k,d,L)
   assert(v>=lo-1e-9 and v<=hi+1e-9,string.format('place %d, %d m: %.3f outside its column [%.3f, %.3f]',k,d,v,lo,hi))
  end
  assert(math.abs(G.columnLateral(g,k,0,L)-g.slots[k].lateral)<1e-9,'at the place: its own lateral')
  if g.slots[k+2] then assert(math.abs(G.columnLateral(g,k,16,L)-g.slots[k+2].lateral)<1e-6,'16 m back: the next place of the column') end
 end
end

-- G9 : décalage de colonne mené progressivement (même session : un écart de plusieurs mètres demandé en une image à
-- 125 km/h) : sur le chemin de la grille, la commande ne change jamais de plus de GK.columnRate par seconde.
tests.LOCK_GRID_COLUMN_RAMP_204=function()
 local G=require('src/grid')
 assert(G.GK.columnRate==0.15)
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e); e.gridCaps=true
 for i=1,3 do f.cars[i].position=i end
 local function slotZ(k) return -(K.gridFirst+(k-1)*K.gridPitch) end
 F.place(f,1,slotZ(1)-900,0); F.place(f,3,slotZ(3)-900,0)
 local car=F.place(f,2,slotZ(2)-320,100,4) -- 320 m avant sa place, 4 m sur le côté
 F.tick(e,f,0.1)
 local t=e.incidents; t.formationRank={1,2,3}; t.formationRankN=3; t.formationAt=e.time-30; t.formationNode={1,2,3}
 t.standing='grid'; F.tick(e,f,1/60)
 local g=e.grid; local last=nil; local moved=0; local z=car.z
 for _=1,8*60 do
  z=z+100/3.6/60; F.place(f,2,z,100,car.x); F.tick(e,f,1/60)
  local o=e.commands[2].offset
  if last and not g.frozen[2] then
   assert(math.abs(o-last)<=G.GK.columnRate/60+1e-6,string.format('offset step %.4f in one frame',math.abs(o-last)))
   moved=moved+math.abs(o-last)
  end
  last=o
 end
 assert(moved>0.3,'the car does move towards its column ('..moved..')')
end

-- G10 : recalage exact sur la place : voir tests/review204h.lua (LOCK_GRID_SNAP_VERIFIED_204, LOCK_GRID_SNAP_GUARDS_204),
-- réécrit après l'essai du pilote de 11:47 (pose vérifiée sur la voiture après chaque écriture).

-- G11 : chemin de la grille : aucune place à rendre entre IA (même session : « place a rendre IA » juste avant le
-- tête-à-queue) ; lignes de journal de la grille traduites.
tests.LOCK_GRID_NO_AI_GIVEBACK_204=function()
 local Pe=require('src/penalties')
 local e,f=F.scene('C',3)
 local t=Pe.new(); local inc=e.incidents
 inc.standing='grid'; inc.red=false
 t.ai.giveBack[2]={[3]=e.time+10}
 local r=Pe.ai(t,f,e.run,'C',inc,e.states,e.perception.rows,e.time)
 assert(r==nil and next(t.ai.giveBack)==nil,'grid: nothing judged, places to give back cleared')
 local J=require('src/journal')
 assert(J.english('grille: places relevees sur la grille : 1:A, 2:B')=='grid: places read on the grid: 1:A, 2:B',tostring(J.english('grille: places relevees sur la grille : 1:A, 2:B')))
end

return tests
