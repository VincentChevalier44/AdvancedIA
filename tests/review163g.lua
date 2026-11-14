-- Série complète 1.63 : mutations restées non détectées après les changements de comportement de la 1.63 (grille bornée
-- par la première IA immobile, places à rendre d'abord, drapeau bleu tenu au temps). Ces tests visent les chemins de code
-- encore atteignables. Noms terminés par _163G. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Pe=require('src/penalties')
local K=C.K
local tests={}
local function standingScene(n)
 local e,f=F.scene('C',n); C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart='standing'; E.changed(e); e.gridCaps=true
 for i=1,n do f.cars[i].position=i end
 return e,f
end
local function slotZ(k) return -(K.gridFirst+(k-1)*K.gridPitch) end

-- Grille : les IA retenues sont ramenées à leur stand par AC (perdues), la dernière n'arrive jamais. Plus aucune IA
-- immobile ne compte pour la limite de la 1.63 : l'attente bornée de la 1.61 / 1.62 reprend la main, mesurée depuis la
-- dernière arrivée (K.gridWaitMax) et au plus K.gridWaitFirstMax depuis la première.
tests.GRID_WAIT_AFTER_LOST_163G=function()
 local e,f=standingScene(4)
 F.place(f,1,slotZ(1)-300,60); F.place(f,2,slotZ(2)-300,60); F.place(f,3,slotZ(3)-300,60); F.place(f,4,slotZ(4)-900,60)
 F.tick(e,f,0.2)
 local t=e.incidents; local g=e.grid; t.standing='grid'; F.tick(e,f,0.1)
 F.place(f,1,slotZ(1),0); F.place(f,2,slotZ(2),0); F.tick(e,f,1/60)
 assert(g.held[2] and not g.held[3] and t.standing=='grid','first AI held')
 local t0=g.firstHeldAt
 F.tick(e,f,1); f.cars[2].pit=true; F.tick(e,f,1/60); assert(g.lost[2],'first AI sent to its box by AC')
 F.tick(e,f,t0+10-e.time)
 F.place(f,3,slotZ(3),0); F.tick(e,f,1/60); assert(g.held[3] and g.lastHeldAt>=t0+9.9,'second AI held later')
 F.tick(e,f,1); f.cars[3].pit=true; F.tick(e,f,1/60); assert(g.lost[3],'second AI sent to its box too')
 F.tick(e,f,t0+15-e.time)
 assert(t.standing=='grid','15 s after the first arrival, 5 s after the last: still waiting (not 12 s from the first)')
 F.tick(e,f,t0+K.gridWaitFirstMax+0.6-e.time)
 assert(t.standing=='lights','bounded wait from the first arrival: lights without the latecomer')
end

-- Joueur seul attendu : toutes les IA ramenées à leur stand, le joueur pas encore en place. Ses K.gridPlayerWait s
-- d'attente, puis les feux, et les cinq feux s'allument avant l'extinction.
tests.GRID_PLAYER_ALONE_163G=function()
 local e,f=standingScene(3)
 F.place(f,1,slotZ(1)-300,30); F.place(f,2,slotZ(2)-300,60); F.place(f,3,slotZ(3)-300,60)
 F.tick(e,f,0.2)
 local t=e.incidents; local g=e.grid; t.standing='grid'; F.tick(e,f,0.1)
 F.place(f,2,slotZ(2),0); F.place(f,3,slotZ(3),0); F.tick(e,f,1/60)
 assert(g.held[2] and g.held[3] and g.aiReadyAt,'every AI held: ready, the player still driving to the grid')
 local ready=g.aiReadyAt
 F.tick(e,f,0.5); f.cars[2].pit=true; f.cars[3].pit=true; F.tick(e,f,1/60)
 assert(g.lost[2] and g.lost[3],'both AI sent to their boxes')
 F.tick(e,f,ready+K.gridPlayerWait-1-e.time); assert(t.standing=='grid','player wait not over')
 F.tick(e,f,ready+K.gridPlayerWait+0.5-e.time); assert(t.standing=='lights','player wait over: lights')
 local lit=g.lightsAt
 F.tick(e,f,lit+K.lightStep*(K.gridLights-1)-0.05-e.time)
 assert(t.standing=='lights','five lights before the lights out')
end

-- Drapeau bleu à la même allure, voiture qui prend un tour collée derrière, à basse vitesse : au-delà de la tenue au
-- temps de la 1.63 (1,5 s), la règle de la 1.24 (K.blueCloseGap m) lève encore le drapeau en course.
tests.BLUE_SAME_SPEED_SLOW_163G=function()
 local e,f=F.scene('C',3); e.startedAt=-100
 F.place(f,3,5000,60)
 local yielded=false
 for _=1,8 do
  F.place(f,2,0,60); F.place(f,1,-33-4.4,60); f.cars[1].lap=f.cars[2].lap+1; e.states[2].nextPerception=0
  F.tick(e,f,0.5); if F.yielding(e.states[2].state) then yielded=true; break end
 end
 assert(yielded,'lapped car, same slow pace, 33 m behind (2 s): blue flag, yields')
end

-- Sanctions des IA dans une zone jaune (pas une neutralisation) : la voiture doublée reçoit le droit de reprendre sa
-- place ; la reprendre n'est pas sanctionné.
tests.AI_RETAKE_YELLOW_163G=function()
 local e,f=F.scene('C',4); e.run.aiPenalties=true
 local st={}; for i=1,4 do st[i]={yellow=true} end
 local function step(t,z2,z3)
  F.place(f,1,-5000,100); F.place(f,2,z2,100); F.place(f,3,z3,100); F.place(f,4,5000,100)
  e.states[2].nextPerception=0; e.states[3].nextPerception=0; F.tick(e,f,1/60)
  e.incidents.neutral=false; e.incidents.red=false; for i=1,4 do e.incidents.cars[i].restart=false end
  return Pe.ai(t,f,e.run,'C',e.incidents,st,e.perception.rows,e.time)
 end
 local t=Pe.new()
 step(t,20,0); step(t,20,30)
 assert((t.ai.count[3] or 0)==1,'AI 3 passed AI 2 under yellow at the same speed: sanctioned')
 -- Après son pied levé (une voiture qui purge une sanction se double librement), toujours sous jaune.
 for _=1,math.ceil((e.run.penaltySeconds+1)*60) do step(t,20,30) end
 step(t,40,30)
 assert((t.ai.count[2] or 0)==0,'AI 2 retakes its place: no sanction')
end

-- Neutralisation, dépassement pendant la transition (le peloton freine) jamais rendu : sanction à l'échéance, et la
-- place reste à rendre (owe).
tests.AI_GIVEBACK_TRANSITION_163G=function()
 local e,f=F.scene('C',4); e.run.aiPenalties=true
 local st={}; for i=1,4 do st[i]={yellow=false} end
 local function step(t,z2,z3)
  F.place(f,1,-5000,100); F.place(f,2,z2,100); F.place(f,3,z3,100); F.place(f,4,5000,100)
  e.states[2].nextPerception=0; e.states[3].nextPerception=0; F.tick(e,f,1/60)
  e.incidents.neutral=true; e.incidents.red=false; for i=1,4 do e.incidents.cars[i].restart=false end
  return Pe.ai(t,f,e.run,'C',e.incidents,st,e.perception.rows,e.time)
 end
 local t=Pe.new()
 step(t,0,20); step(t,30,20)
 assert(t.ai.waiting[2] and t.ai.waiting[2][3],'pass during the transition: waits for the place to be given back')
 local due=t.ai.waiting[2][3]
 for _=1,math.ceil((due-e.time)*60)+30 do step(t,30,20); if (t.ai.count[2] or 0)>0 then break end end
 assert((t.ai.count[2] or 0)==1 and t.ai.owe[2]==3,'not given back in time: sanctioned and the place is still owed')
end

return tests
