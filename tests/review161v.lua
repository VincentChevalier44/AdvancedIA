-- Correctif 1.61 (Spa, 11 novembre : tour de formation puis départ arrêté ; grille calculée devant la vraie grille,
-- 20 IA ramenées aux stands par AC, feux sur une grille incomplète ; erreur de l'accueil) et comportement du tour de
-- formation (zigzag d'un bord à l'autre, freinages de chauffe, coup d'accélérateur avant la place). Chargé par
-- tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local D=require('src/director')
local Grid=require('src/grid')
local Antics=require('src/antics')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function standingScene(n)
 local e,f=F.scene('C',n); C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart='standing'; E.changed(e); e.gridCaps=true
 for i=1,n do f.cars[i].position=i end
 return e,f
end
local function slotZ(k) return -(K.gridFirst+(k-1)*K.gridPitch) end
-- Grille du circuit après la ligne (Spa) acceptée ; emplacement un peu hors de la trajectoire ramené ; raison précisée.
tests.GRID_NODES_AFTER_LINE_161V=function()
 local L=7000
 local function node(before,lat) return {spline=((-before)/L)%1,lateral=lat} end
 local after={node(-44,-0.4),node(-36,1.3),node(-28,-0.4),node(-20,0.4)}
 local out,source=Grid.resolve(after,L,4,{})
 assert(source=='AC_START' and #out==4,'grid after the line accepted (Spa)')
 assert(out[2].lateral==K.gridLatClamp and after[2].lateral==1.3,'lateral beyond the AI line clamped in the copy only')
 local _,src,why=Grid.resolve({node(-28,0),node(-20,1.8)},L,2,{})
 assert(src=='calculees' and why:find('noeud 2 incoherent : lateral 1.80',1,true),'too far out: refused with the reason')
 local _,_,why2=Grid.resolve({node(-(K.gridNodeAfter+100),0)},L,1,{})
 assert(why2:find('apres la ligne',1,true),'far after the line: reason')
 local _,_,why3=Grid.resolve({node(30,0),node(50,0),node(20,0)},L,3,{})
 assert(why3:find('noeud 3 incoherent : devant le precedent',1,true),'order: reason')
 assert(math.abs(Grid.before(((-12)/L)%1,L)-12)<1e-9 and math.abs(Grid.before((12/L)%1,L)+12)<1e-9,'signed distance before the line')
end
-- IA ramenée aux stands par AC pendant la grille : notée une fois, jamais comptée en place, partie de la voie des stands.
tests.GRID_LOST_CAR_NOT_COUNTED_161V=function()
 local e,f=standingScene(5)
 for i=1,5 do F.place(f,i,slotZ(i)-200,60) end
 F.tick(e,f,0.2)
 local t=e.incidents; local g=e.grid; t.standing='grid'; F.tick(e,f,0.1)
 assert(g.phase=='grid','grid forming')
 F.place(f,1,slotZ(1),0); F.place(f,2,slotZ(2),0); F.place(f,3,slotZ(3),0); F.place(f,4,slotZ(4),0)
 F.tick(e,f,1/60)
 assert(g.held[2] and g.held[3] and g.held[4] and g.heldAt[2] and g.firstHeldAt,'held, time noted')
 -- Joueur pas encore en place : les feux attendent (attente bornée non atteinte).
 F.place(f,1,slotZ(1)-100,30); F.tick(e,f,2)
 f.cars[5].pit=true; F.tick(e,f,1/60)
 assert(g.lost[5] and g.pit[5] and count(e,'ramenee aux stands par AC')==1,'teleported car noted once')
 F.tick(e,f,1/60); assert(count(e,'ramenee aux stands par AC')==1,'noted only once')
 -- Elle ressort de la voie des stands, loin de sa place : jamais attendue ni comptée sur la grille.
 f.cars[5].pit=false; F.place(f,5,slotZ(5)-700,40); F.tick(e,f,1/60)
 assert(t.standing=='grid','still waiting for the player')
 F.place(f,1,slotZ(1),0); F.tick(e,f,0.2)
 assert(t.standing=='lights','the remaining field is in place: lights')
 assert(e.commands[5].speedLimit<=K.gridCrawlKmh,'pit starter: crawls at the pit exit until the lights out')
 -- Une IA en place qui disparaît pendant les feux n'est pas comptée non plus.
 f.cars[3].pit=true; F.tick(e,f,1/60)
 assert(g.lost[3] and count(e,'a l arret depuis')==1,'teleport during the lights noted with the time stopped')
end
-- Attente bornée (relecture 1.62, S3) : jamais de feux sans le joueur en place (sauf le délai maximal) ; joueur en place :
-- K.gridWaitMax s après la dernière arrivée, sans attendre un retardataire, qui continue vers sa place pendant les feux.
tests.GRID_BOUNDED_WAIT_161V=function()
 local e,f=standingScene(4)
 F.place(f,1,slotZ(1)-400,60); F.place(f,2,slotZ(2)-300,60); F.place(f,3,slotZ(3)-300,60); F.place(f,4,slotZ(4)-900,60)
 F.tick(e,f,0.2)
 local t=e.incidents; local g=e.grid; t.standing='grid'; F.tick(e,f,0.1)
 F.place(f,2,slotZ(2),0); F.place(f,3,slotZ(3),0); F.tick(e,f,1/60)
 assert(g.held[2] and g.held[3] and not g.held[4] and t.standing=='grid','two held, one far behind')
 F.tick(e,f,K.gridWaitMax+2); assert(t.standing=='grid','player not in place: no lights')
 F.place(f,1,slotZ(1),0); F.tick(e,f,1/60)
 assert(t.standing=='lights' and count(e,'attente bornee')==1,'player in place, last arrival long ago: lights, one line')
 assert(not g.held[4] and not e.commands[4].stopHold and e.commands[4].speedLimit>K.gridCrawlKmh,'latecomer keeps driving to its slot during the lights')
 -- Joueur en place dès le début, une IA arrive tard : attente comptée depuis cette arrivée.
 local e2,f2=standingScene(4)
 F.place(f2,1,slotZ(1)-400,60); F.place(f2,2,slotZ(2)-300,60); F.place(f2,3,slotZ(3)-300,60); F.place(f2,4,slotZ(4)-900,60)
 F.tick(e2,f2,0.2)
 local t2=e2.incidents; t2.standing='grid'; F.tick(e2,f2,0.1)
 F.place(f2,1,slotZ(1),0); F.place(f2,2,slotZ(2),0); F.tick(e2,f2,1/60)
 F.tick(e2,f2,3); F.place(f2,3,slotZ(3),0); F.tick(e2,f2,1/60)
 F.tick(e2,f2,K.gridWaitMax-1); assert(t2.standing=='grid','measured from the last arrival: still waiting')
 F.tick(e2,f2,1.2); assert(t2.standing=='lights','lights after the bound from the last arrival')
end
-- Zigzag du tour de formation : borne propre, à K.formWeaveEdge m du bord, aussi aux points lus plus loin.
tests.FORMATION_WEAVE_BOUND_161V=function()
 local a={width=2,leftWidth=6,rightWidth=6,leftAhead=6,rightAhead=6,leftAhead2=6,rightAhead2=6,splineValid=true}
 local w=D.weaveBound(a,true)
 assert(math.abs(w-math.min(K.formWeaveMax,(6-1-K.formWeaveEdge)/6))<1e-9,'own room minus half a car and the margin')
 a.rightAhead2=3
 assert(math.abs(D.weaveBound(a,true)-(3-1-K.formWeaveEdge)/3)<1e-9 and math.abs(D.weaveBound(a,false)-w)<1e-9,'narrowing ahead on that side only')
 a.leftAhead=nil; assert(D.weaveBound(a,true)==nil,'unknown widths ahead: original bound')
 local s={state='DRIVE',zone={maxOffset=1},formWeave=true}
 local p={maxSideOffset=1}
 -- Trajectoire le long d'un bord (1,5 m à gauche, 10 m à droite) : vers le grand côté, le zigzag va bien plus loin.
 a.leftWidth=1.5; a.rightWidth=10; a.leftAhead=1.5; a.rightAhead=10; a.leftAhead2=1.5; a.rightAhead2=10
 local g={offsetSign=-1}
 local wide=D.reachable(s,a,p,g,-0.95)
 s.formWeave=nil
 local plain=D.reachable(s,a,p,g,-0.95)
 assert(math.abs(wide)>math.abs(plain)+0.5 and math.abs(wide)<=K.formWeaveMax+1e-9,'formation weave reaches further than free driving')
 s.formWeave=true; s.state='YIELD_IN'
 assert(math.abs(D.reachable(s,a,p,g,-0.95)-D.reachable({state='YIELD_IN',zone={maxOffset=1}},a,p,g,-0.95))<1e-9,'weave bound only in free driving')
end
-- Freinages de chauffe : seulement pendant le tour de formation, sans voiture proche derrière, brefs.
tests.FORMATION_WARM_BRAKE_161V=function()
 local t=Antics.new(); t.active=true
 local frame={count=1,length=7000,cars={{valid=true,control=true,player=false,pit=false,finished=false,safetyCar=false,splineValid=true,kmh=150,speed=150/3.6,yawRate=0,spline=0.5,brake=0}}}
 local row={count=0,back=0,front=0,neighbors={}}
 local e={incidents={formation=true,rollCall=false},runtimeG={seed=3},commands={{speedLimit=K.unlimitedSpeed}},perception={rows={row}},states={{zone={}}},grid={aiRelease={}}}
 Antics.launch(t,e,frame,0)
 local at=t.brakeAt[1]
 assert(at>=K.formBrakeEveryMin and at<=K.formBrakeEveryMax,'first warm-up brake scheduled')
 Antics.launch(t,e,frame,at)
 assert(t.brakeUntil[1]>at,'brake application started on a straight with nobody close')
 e.commands[1].speedLimit=K.unlimitedSpeed; Antics.launch(t,e,frame,at+0.1)
 assert(math.abs(e.commands[1].speedLimit-(150-K.formBrakeDrop))<1e-9,'speed limit dropped for the warm-up')
 e.commands[1].speedLimit=K.unlimitedSpeed; Antics.launch(t,e,frame,at+K.formBrakeTime+0.05)
 assert(e.commands[1].speedLimit==K.unlimitedSpeed,'short: released after the application')
 -- Voiture proche derrière : pas de freinage.
 local t2=Antics.new(); t2.active=true; row.count=1; row.back=1; row.neighbors[1]={index=1,long=-30,lat=0,gap=30}
 Antics.launch(t2,e,frame,0); Antics.launch(t2,e,frame,t2.brakeAt[1])
 assert(not (t2.brakeUntil[1]>t2.brakeAt[1]-K.formBrakeEveryMax-1),'no warm-up brake with a car close behind')
 -- Hors tour de formation : rien.
 local t3=Antics.new(); t3.active=true; e.incidents.formation=false; row.count=0; row.back=0
 Antics.launch(t3,e,frame,0); assert(t3.brakeAt[1]==0,'nothing outside the formation lap')
end
-- Coup d'accélérateur avant la place (départs réalistes) : une fois, borné par l'arrêt à la place.
tests.GRID_BURST_161V=function()
 local e,f=standingScene(3)
 for i=1,3 do F.place(f,i,slotZ(i)-300,60) end
 F.tick(e,f,0.2)
 local t=e.incidents; local g=e.grid; t.standing='grid'; F.tick(e,f,0.1)
 g.realism=true
 local d=60; F.place(f,2,slotZ(2)-d,40) -- car 2 : deuxième place
 local now=e.time
 -- Coup d'accélérateur exagéré le temps du test : la borne d'arrêt à la place s'applique.
 local kept=K.formBurstKmh; K.formBurstKmh=40; e.commands[2].speedLimit=K.unlimitedSpeed
 Grid.step(g,t,f,now,e.commands,e.g.offsetSign,1,e.log,e.states,nil)
 K.formBurstKmh=kept
 local base=math.sqrt(2*K.gridApproachDecel*(d-K.gridHoldDistance))*3.6
 local stop=math.sqrt(2*K.formBurstDecel*(d-K.gridHoldDistance))*3.6
 local lim=e.commands[2].speedLimit
 assert(g.burstDone[2] and lim>base and math.abs(lim-stop)<1e-6,'burst: cap raised, bounded by a stop at the slot')
 e.commands[2].speedLimit=K.unlimitedSpeed
 Grid.step(g,t,f,now+K.formBurstTime+0.1,e.commands,e.g.offsetSign,1,e.log,e.states,nil)
 assert(e.commands[2].speedLimit<=base+1e-6,'burst over: approach cap again, never twice')
 g.realism=false
end
-- Accueil : lien de l'avertissement des pénalités d'AC actives avec son libellé (erreur de l'interface du 11 novembre).
tests.WARN_LINK_ACPENALTIES_161V=function()
 for _,name in ipairs({'src/lang','src/lang_en'}) do
  local L=require(name); assert(type(L.warnLinks.acpenalties)=='string','link label '..name)
 end
 local W=require('src/widgets'); assert(W.upper(nil)=='','missing text drawn empty')
end
return tests
