-- Correctif 1.63 (Montréal, 12 novembre : tour de formation puis départ arrêté, toute la grille « ramenee aux stands par
-- AC (a l arret depuis 12 s) », le joueur seul sur la grille ; « file etiree (4074 m) » au feu vert ; sanctions, delta
-- et FCY pendant le tour de formation). Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Grid=require('src/grid')
local Formation=require('src/formation')
local Penalties=require('src/penalties')
local K=C.K
local GK=Grid.GK
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function standingScene(n)
 local e,f=F.scene('C',n); C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart='standing'; E.changed(e); e.gridCaps=true
 for i=1,n do f.cars[i].position=i end
 return e,f
end
local function slotZ(k) return -(K.gridFirst+(k-1)*K.gridPitch) end
local seq=K.lightStep*(K.gridLights-1)+K.lightsOutMin
-- Grille complète d'IA, joueur pas en place : feux au plus tard GK.stillMax - séquence - marge après la première IA
-- immobile, extinction au plus tard GK.stillMax s après elle (AC renvoie une IA immobile à son stand vers 12 s).
tests.GRID_NO_AI_STILL_TOO_LONG_163D=function()
 assert(GK.stillMax<=10 and GK.stillMax-seq-GK.lightsMargin>0,'still limit under AC 12 s')
 local e,f=standingScene(5)
 for i=1,5 do F.place(f,i,slotZ(i)-200,60) end
 F.tick(e,f,0.2)
 local t=e.incidents; local g=e.grid; t.standing='grid'; F.tick(e,f,0.1)
 assert(g.phase=='grid','grid forming')
 F.place(f,1,slotZ(1)-300,20)
 for i=2,5 do F.place(f,i,slotZ(i),0) end
 F.tick(e,f,1/60)
 local first=Grid.firstStill(g,f)
 assert(first and g.held[2] and g.held[5],'AI held, first still time known')
 local lit=nil
 for _=1,60*12 do F.tick(e,f,1/60); if t.standing=='lights' and not lit then lit=e.time end; if t.standing~='grid' and t.standing~='lights' then break end end
 assert(lit and lit-first<=GK.stillMax-seq-GK.lightsMargin+0.05,'lights without the player, before AC sends anyone back ('..tostring(lit and lit-first)..')')
 assert(g.outAt<=first+GK.stillMax+1e-6 or t.standing=='go' or t.standing=='none','lights out no later than the still limit')
 assert(e.time-first<=GK.stillMax+0.1,'released before the still limit ('..(e.time-first)..')')
 assert(count(e,'joueur pas en place')==1,'one line with the actual waits, player not in place')
end
-- IA arrivée près de sa place pendant qu'une autre est encore loin : elle approche au pas, sans s'arrêter.
tests.GRID_CREEP_WHILE_OTHERS_FAR_163D=function()
 local e,f=standingScene(4)
 for i=1,4 do F.place(f,i,slotZ(i)-200,60) end
 F.tick(e,f,0.2)
 local t=e.incidents; local g=e.grid; t.standing='grid'; F.tick(e,f,0.1)
 F.place(f,1,slotZ(1),0); F.place(f,2,slotZ(2)-15,10); F.place(f,3,slotZ(3)-15,10); F.place(f,4,slotZ(4)-600,60)
 F.tick(e,f,1/60)
 assert(g.creep,'another car still far from its slot')
 assert(not g.held[2] and not e.commands[2].stopHold and e.commands[2].speedLimit<=GK.creepKmh+1e-6,'creeps toward its slot')
 F.place(f,4,slotZ(4)-10,10); F.tick(e,f,1/60)
 assert(not g.creep,'field gathered: normal approach')
end
-- IA ramenée à son stand par AC : jamais comptée comme première IA immobile.
tests.GRID_LOST_CAR_NOT_FIRST_STILL_163D=function()
 local e,f=standingScene(4)
 for i=1,4 do F.place(f,i,slotZ(i)-200,60) end
 F.tick(e,f,0.2)
 local t=e.incidents; local g=e.grid; t.standing='grid'; F.tick(e,f,0.1)
 F.place(f,2,slotZ(2),0); F.tick(e,f,1/60)
 local at=Grid.firstStill(g,f)
 F.tick(e,f,2); F.place(f,3,slotZ(3),0); F.tick(e,f,1/60)
 f.cars[2].pit=true; F.tick(e,f,1/60)
 assert(g.lost[2] and Grid.firstStill(g,f)>at,'car sent to the pits no longer counts')
end
-- Écart de la file mesuré sur le cercle du tour : voitures de part et d'autre de la ligne, aucun faux écart d'un tour.
tests.FORMATION_GAP_ACROSS_LINE_163D=function()
 local L=4287
 local frame={count=4,player=0,length=L,cars={}}
 local sp={0.995,0.985,0.002,0.009}
 for i=1,4 do frame.cars[i]={valid=true,splineValid=true,spline=sp[i],lap=sp[i]<0.5 and 1 or 0} end
 local gap,ahead,span=Formation.worstGap(Formation.new(),frame)
 assert(gap<0.02*L and gap>0,'no lap-sized gap ('..gap..')')
 -- Vrai trou derrière les deux premières : voitures de devant repérées sur le cercle.
 sp={0.02,0.01,0.95,0.94}; for i=1,4 do frame.cars[i].spline=sp[i] end
 gap,ahead,span=Formation.worstGap(Formation.new(),frame)
 assert(math.abs(gap-0.06*L)<1 and math.abs(ahead-0.01)<1e-9 and math.abs(span-0.01)<1e-9,'front group found across the line')
end
-- Pendant le tour de formation : aucune sanction d'IA, aucune pénalité du joueur (dépassement, delta).
tests.FORMATION_NO_PENALTIES_163D=function()
 local e,f=standingScene(3)
 local t=e.incidents
 t.neutral=true; t.relaunch=true; t.formation=true; t.neutralMode='fcy'; t.neutralSince=e.time-30
 local pt=e.penalties; pt.ai.giveBack[2]=3
 local p=e.run; p.aiPenalties=true
 assert(Penalties.ai(pt,f,p,'C',t,e.states,e.perception.rows,e.time)==nil and next(pt.ai.giveBack)==nil,'no AI sanction')
 local d={infraction=true,infractionKind='zone',infractionValue=-1}
 p.playerPenalties=true
 assert(Penalties.update(pt,f,p,'C',t,e.time,0,d)==nil,'no player delta penalty')
end
-- Grille après le tour de formation : une voiture RETARDÉE (incident pendant le tour) doublée par des voitures parties
-- derrière elle part de l'arrière ; relecture 1.63 (N2) : une voiture simplement doublée garde sa place, celle qui l'a
-- doublée reprend la sienne (ordre du départ).
tests.FORMATION_LOST_PLACE_BACK_OF_GRID_163D=function()
 local function run(delayed)
  local e,f=standingScene(5)
  for i=1,5 do F.place(f,i,slotZ(i)-200,60) end
  F.tick(e,f,0.2)
  local t=e.incidents
  t.formationRank={1,2,3,4,5}; t.formationRankN=5; t.formationAt=e.time-30; t.formationNode={1,2,3,4,5} -- 2.0.4 : places lues sur la grille
  if delayed then t.cars[2].since=e.time-10 end
  f.cars[2].position=4; f.cars[3].position=2; f.cars[4].position=3
  t.standing='grid'; F.tick(e,f,0.1)
  return e,e.grid,t
 end
 local e,g,t=run(true)
 -- 2.0.4 (décision du pilote du 18 novembre, « cases vides partout ») : chacune garde sa place du départ, la place de la
 -- voiture renvoyée reste vide, elle se place derrière la dernière place (LOCK_GRID_OWN_SLOT_204).
 assert(g.slotOf[2]==6 and g.slotOf[1]==1 and g.slotOf[3]==3 and g.slotOf[4]==4 and g.slotOf[5]==5,'delayed car 2 behind the last place, the others keep their own place')
 assert(count(e,'part de l arriere de la grille')==1 and t.formationRankN==0,'one line, rank used once')
 local e2,g2=run(false)
 assert(g2.slotOf[1]==1 and g2.slotOf[2]==2 and g2.slotOf[3]==3 and g2.slotOf[4]==4 and g2.slotOf[5]==5,'passed without incident: starting order restored')
 assert(count(e2,'part de l arriere de la grille')==0,'nobody sent to the back')
end
return tests
