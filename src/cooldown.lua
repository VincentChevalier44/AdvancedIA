-- Beta 1.63 (demande du pilote, 12 novembre au soir) : tour de décélération après le drapeau à damier, en course.
-- Une IA qui a passé la ligne d'arrivée (a.finished) ne refait plus son tour de rentrée à fond : plafond d'allure à
-- K.coolPace de son allure apprise à cet endroit (repli : de sa vitesse au moment où elle a fini), qui baisse d'au plus
-- K.coolDecel m/s² (jamais de freinage brusque), jamais sous K.coolMinKmh km/h. Une voiture encore en course à moins de
-- K.coolRoomRange m derrière : décalage K.coolOffset vers le côté libre (jamais vers une voiture à côté), rendu ensuite.
-- Le moteur ne pilote plus une voiture arrivée (ni toute la grille une fois la session finie) : ce module ne donne que
-- ces deux consignes (src/applier.lua, M.cooldown) ; voie des stands et fin de session : tout est rendu à AC.
-- Le joueur n'est jamais touché.
local K=require('src/config').K
local U=require('src/util')
local Delta=require('src/delta')
local Perception=require('src/perception')
local M={}
function M.new()
 local t={cars={},count=0}
 for i=1,K.maxCars do t.cars[i]={on=false,cap=0,ref=0,offset=0,noted=false,identity=''} end
 return t
end
local function clear(c) c.on=false; c.cap=0; c.ref=0; c.offset=0 end
-- Voiture encore en course derrière, à moins de K.coolRoomRange m : côté libre vers lequel se décaler (-1 gauche,
-- +1 droite, 0 : rien à faire). Le côté est celui de la piste le plus large (bords connus), jamais celui d'une voiture
-- déjà à côté (Perception.occupancy).
local occ={left=false,right=false}
local function room(frame,i,g)
 local a=frame.cars[i]; local length=frame.length
 if length<=0 or not a.splineValid then return 0 end
 local behind=false
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=i and b.valid and not b.pit and b.splineValid and not b.finished then
   local d=U.spline(a.spline-b.spline)*length
   if d>0 and d<K.coolRoomRange then behind=true; break end
  end
 end
 if not behind then return 0 end
 Perception.occupancy(frame.cars,frame.count,i,g,occ)
 local side=(a.rightWidth or 0)>(a.leftWidth or 0) and 1 or -1
 if side<0 and occ.left or side>0 and occ.right then side=-side end
 if side<0 and occ.left or side>0 and occ.right then return 0 end
 return side
end
-- states : états du moteur (allure apprise, m/s par case) ; bins : cases d'allure du circuit ; race : course en cours ou
-- finie ; dt : pas de l'image ; g : réglages globaux (sens latéral). Rend t (t.cars[i].on, .cap en km/h, .offset de
-- -1 à 1, sens canonique).
function M.step(t,frame,states,bins,race,dt,note,g)
 t.count=0
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]
  local identity=a.identity or a.id or ''
  if c.identity~=identity then clear(c); c.noted=false; c.identity=identity end
  local eligible=race and a.valid and a.control and not a.player and not a.safetyCar and a.finished and not a.pit and not a.offtrack and a.splineValid
  if not eligible then
   if not a.finished then c.noted=false end
   clear(c)
  else
   local s=states and states[i]
   local own=0
   if s and bins and bins>0 and s.paceCount and s.paceCount>=K.paceMinBins then own=(s.pace[Delta.bin(a.spline,bins)] or 0)*3.6 end
   if not c.on then
    c.on=true; c.cap=math.max(a.kmh,K.coolMinKmh); c.ref=a.kmh; c.offset=0
    if not c.noted then c.noted=true; if note then note('INFO',string.format('tour de deceleration: %s',a.name~='' and a.name or a.id),i) end end
   end
   local ref=own>0 and own or c.ref
   local target=math.max(K.coolMinKmh,K.coolPace*ref)
   local step=K.coolDecel*3.6*(dt or 0)
   if target<c.cap then c.cap=math.max(target,c.cap-step) else c.cap=target end
   local side=g and g.offsetSign~=0 and room(frame,i,g) or 0
   local goal=side*K.coolOffset
   local move=K.coolOffsetRate*(dt or 0)
   if math.abs(goal-c.offset)<=move then c.offset=goal else c.offset=c.offset+U.sign(goal-c.offset)*move end
   t.count=t.count+1
  end
 end
 return t
end
return M
