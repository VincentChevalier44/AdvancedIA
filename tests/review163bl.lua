-- Affinage 1.63 (course du pilote du 13 novembre, journal 2026-11-13_10_08_20) : drapeaux bleus et voitures lentes.
-- Consigne : « sous drapeau bleu, celui qui est concerné ralentit énormément et se met complètement hors trajectoire ;
-- le plus rapide passe à pleine vitesse » ; voitures endommagées « toujours sur le bas-côté, hors trajectoire ».
-- Noms LOCK_*_163 (tests/LOCKS.md). Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local K=C.K
local tests={}
local function logged(e,text) for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then return true end end return false end
local function learned(e,first,last,speed)
 for i=first,last do
  local s=e.states[i]; s.paceCount=e.delta.bins
  for b=1,e.delta.bins do s.pace[b]=speed end
  s.longRatio=1; s.longRatioTime=K.longRatioMin
 end
end
-- Retardataire (voiture 2, 180 km/h) et voiture qui lui prend un tour (voiture 3) gap m derrière, sa km/h plus vite ;
-- le joueur loin. Rendu : décalage atteint, niveau commandé, état.
local function blue(sign,gap,sa,frames)
 local e,f=F.scene('C',3); e.g.offsetSign=sign; e.g.sideSign=sign; e.startedAt=-100
 local s=e.states[2]
 for _=1,frames do
  F.place(f,1,-4000,100); F.place(f,2,5000,180); F.place(f,3,5000-gap,180+sa); f.cars[3].lap=f.cars[2].lap+1
  F.tick(e,f,1/60)
 end
 return math.abs(s.offset),e.commands[2].level,s.state,e
end
-- Sepang, 13 novembre : « décalage voulu 0.56, atteint 0.28 », le leader bloqué derrière : cession au décalage maximal
-- permis et levée de pied franche une fois écartée, des deux sens latéraux.
tests.LOCK_BLUE_FULL_SIDE_163=function()
 for _,sign in ipairs({1,-1}) do
  local _,free=blue(sign,3000,0,60)
  local off,level,state=blue(sign,30,40,240)
  assert(state=='YIELD_IN' or state=='YIELD_HOLD','blue flag: yields ('..sign..'): '..state)
  assert(off>=0.75,'completely off the line, edge of the track ('..sign..'): '..off)
  assert(level<=free*0.8,'slows down a lot once aside ('..sign..'): '..level..' vs '..free)
 end
end
-- Voiture anormalement lente (40 km/h, sa classe à 200) : tenue au bord, même sans personne derrière, des deux sens.
local function slow(sign,frames,body,susp,behind)
 local e,f=F.scene('C',4); e.g.offsetSign=sign; e.g.sideSign=sign; e.startedAt=-100; e.p.personalLineJitter=0; E.changed(e)
 f.length=60611; F.tick(e,f,1/60)
 learned(e,2,4,200/3.6)
 f.cars[2].damageBody=body or 0; f.cars[2].damageSuspension=susp or 0
 for _=1,frames do
  F.place(f,1,-20000,0); F.place(f,2,1000,40); F.place(f,4,30000,200)
  if behind then F.place(f,3,1000-behind-4.4,40) else F.place(f,3,-10000,200) end
  F.tick(e,f,1/60)
 end
 return e,f
end
tests.LOCK_SLOW_EDGE_163=function()
 for _,sign in ipairs({1,-1}) do
  local e=slow(sign,(K.slowObstacleTime+4)*60)
  local s=e.states[2]
  assert(s.abnormal,'abnormally slow ('..sign..')')
  assert(math.abs(s.offset)>=0.75,'pinned to the edge, off the racing line ('..sign..'): '..s.offset)
  assert(logged(e,'se range au bord'),'logged')
 end
 -- Allure retrouvée : plus tenue au bord.
 local e,f=slow(1,(K.slowObstacleTime+4)*60)
 for _=1,(K.slowEnd+2)*60 do F.place(f,2,1000,200); F.place(f,3,-10000,200); F.tick(e,f,1/60) end
 assert(not e.states[2].abnormal and e.states[2].edgeSide==0,'normal pace again: released')
end
-- Sepang : carrosserie 140, suspension 0.12, arrêt demandé au bout de 109 s seulement : dès K.slowPitTime2 s d'obstacle.
tests.LOCK_SLOW_PIT_CALL_163=function()
 local e=slow(1,(K.slowObstacleTime+K.slowPitTime2+1)*60,140,0.12)
 assert(e.commands[2].rulePit,'damaged slow car: pit stop requested at once')
 assert(logged(e,'arret aux stands demande'),'logged')
 -- Dégâts légers (en dessous des seuils abaissés) : pas d'arrêt demandé si tôt.
 local e2=slow(1,(K.slowObstacleTime+K.slowPitTime2+1)*60,100,0.1)
 assert(not e2.commands[2].rulePit,'light damage: no early pit call')
end
-- Sepang : suiveur collé à 4 m derrière une voiture lente, à la même allure (+1 km/h), jamais laissé passer : cession.
tests.LOCK_SLOW_GLUED_YIELD_163=function()
 local e=slow(1,(K.slowObstacleTime+3)*60,0,0,6)
 local st=e.states[2].state
 assert(st=='YIELD_IN' or st=='YIELD_HOLD','slow car yields to the car glued behind it: '..st)
end
return tests
