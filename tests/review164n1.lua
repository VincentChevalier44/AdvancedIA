-- Affinage 1.64 n1 (Monza S18, 14 novembre : duels côte à côte finis en tête-à-queue à l'entrée de la Variante Ascari,
-- 3978-4051 m, et de la première chicane, 948 m ; la voiture sans droit à l'espace gardait sa ligne à l'extérieur et
-- les deux trajectoires se croisaient). Au gros freinage (chicane, virage lent), la voiture sans droit cède aussi à
-- l'extérieur : lever de pied, prudence relevée, pas de nouvelle attaque pendant quelques secondes ; la voiture qui a
-- le droit tient son écart. En courbe rapide (freinage léger) : comme avant (verrou LOCK_DUEL_DIRECTOR_164).
local F=require('tests/fixture')
local E=require('src/engine')
local K=require('src/config').K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function logged(e,text) return count(e,text)>0 end

-- Même scène que review164a (voitures 2 et 3 côte à côte, 2 m d'écart latéral, voiture 3 « ahead » m devant), pédale de
-- frein réglable (S18 : freinage d'entrée de chicane, pédale proche de 1).
local function corner(sign,ahead,o)
 o=o or {}
 local e,f=F.scene(o.profile or 'C',4)
 e.g.offsetSign=sign; e.g.sideSign=sign; E.changed(e)
 for i=1,f.count do f.cars[i].sideDot=sign end
 F.place(f,1,-5000,100); f.started=true; F.tick(e,f,o.early and 0.5 or 30)
 for _,i in ipairs({2,3}) do local c=f.cars[i]; c.length=5; c.axleKnown=true; c.axleFront=1.6; c.axleRear=-2; c.mirror=0; c.geomRead=true end
 F.place(f,2,0,150,-2*sign); F.place(f,3,ahead,150,0); F.tick(e,f,0.3)
 local yaw=o.yaw or 0.3*sign
 local brake=o.brake or 0.95
 for k=1,(o.frames or 60) do
  F.place(f,2,0,150,-2*sign); F.place(f,3,ahead,150,0)
  f.cars[2].brake=brake; f.cars[3].brake=brake; f.cars[2].yawRate=yaw; f.cars[3].yawRate=yaw
  F.tick(e,f,1/60)
 end
 return e,f
end

tests.LOCK_DUEL_CONCEDE_164=function()
 assert(K.duelConcede==true and K.duelHeavyBrake>=0.7 and K.duelConcedeLift<K.cornerGiveLift and K.duelConcedeCaution>1 and K.duelConcedeHold>K.cornerGiveHold,'constants')
 for _,sign in ipairs({1,-1}) do
  -- Extérieure (lacet*sign>0), 2 m derrière, sans droit, au gros freinage : elle cède (« freinage »), lève franchement le
  -- pied, sa prudence monte, pas de nouvelle attaque avant K.duelConcedeHold s ; l'autre tient son écart.
  local e=corner(sign,2,{yaw=0.3*sign})
  local s2,s3=e.states[2],e.states[3]
  assert(s2.cornerGiveTo==3 and s2.cornerGiveMode=='chicane',sign..': outside without the right concedes at heavy braking')
  assert((s2.cornerLift or 1)<K.cornerGiveLift,sign..': concede: firmer lift than the plain corner give')
  assert(e.time<(s2.duelConcedeUntil or 0) and (s2.cornerGiveUntil or 0)>=e.time+K.duelConcedeHold-0.1,sign..': concede window and no new attack for duelConcedeHold s')
  assert(logged(e,'(freinage, sans droit a l espace)') and (e.stats.duelConcede or 0)>=1,sign..': journal line and counter')
  assert(s3.cornerGiveTo==0 and s3.duelKeepRoom~=nil,sign..': the car with the right keeps its room (never squeezes)')
  -- Même duel, freinage léger (courbe rapide) : comme avant, l'extérieure garde sa ligne sans lever le pied.
  local fast=corner(sign,2,{yaw=0.3*sign,brake=0.6})
  assert(fast.states[2].cornerGiveTo==0 and (fast.states[2].cornerLift or 1)>=1,sign..': light braking: outside keeps its line (unchanged)')
  -- Hors course (essais) : règle d'avant.
  local practice=corner(sign,2,{yaw=0.3*sign,profile='P'})
  assert(practice.states[2].cornerGiveMode~='chicane' and practice.time>=(practice.states[2].duelConcedeUntil or 0),sign..': outside a race: unchanged')
  -- Règle coupée : comme avant.
  local was=K.duelConcede; K.duelConcede=false
  local ok,err=pcall(function()
   local off=corner(sign,2,{yaw=0.3*sign})
   assert(off.states[2].cornerGiveTo==0,sign..': rule off: outside keeps its line')
  end)
  K.duelConcede=was; assert(ok,err)
 end
end

-- La voiture qui cède au gros freinage freine plus tôt : prudence commandée plus haute que la même scène règle coupée.
tests.DUEL_CONCEDE_CAUTION_164N1=function()
 local e=corner(1,2,{yaw=0.3,frames=90})
 local was=K.duelConcede; K.duelConcede=false
 local ok,res=pcall(function() return corner(1,2,{yaw=0.3,frames=90}) end)
 K.duelConcede=was; assert(ok,res)
 assert(e.commands[2].caution>res.commands[2].caution+0.05,'concede: caution raised')
end

tests.K_164N1=function()
 assert(K.duelHeavyBrake==0.8 and K.duelConcedeLift==0.6 and K.duelConcedeCaution==1.5 and K.duelConcedeTime==1.5 and K.duelConcedeHold==3,'constants')
end

return tests
