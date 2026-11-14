-- Affinage 1.63 (dépassements entre IA, courses F1 du 12 novembre) : attaque poussée en course (src/director.lua).
-- Noms terminés par _163U. Chargé par tests/extended.lua. Chaque scène tourne avec le sens latéral du jeu (-1 / -1) et +1 / +1.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local K=C.K
local tests={}

local function scene(profile,sign,tune)
 local e,f=F.scene(profile,3); e.g.offsetSign=sign; e.g.sideSign=sign
 local p=e.profiles[profile]; p.startDelay=0; p.startRelax=0; p.personalLineJitter=0
 if tune then tune(p) end
 E.changed(e)
 for i=1,3 do f.cars[i].sideDot=sign end
 return e,f
end

-- Voiture 2 rattrape la voiture 3 (IA) en ligne droite : tentative, puis niveau poussé et prudence bornée.
local function attack(profile,sign,o)
 o=o or {}
 local e,f=scene(profile,sign,o.tune)
 F.place(f,1,-5000,100)
 local gap=o.gap or 20
 F.place(f,2,0,o.kmh or 220,0); F.place(f,3,gap+4.4,180,0)
 if o.player3 then f.player=3 end
 local s=e.states[2]
 local pushed,base=false,nil
 for n=1,o.frames or 240 do
  F.place(f,2,0,o.kmh or 220,0); F.place(f,3,gap+4.4,180,0); s.nextPerception=0
  if o.each then o.each(e,f) end
  F.tick(e,f,1/60)
  if s.pushFor~=nil and s.pushFor==s.passStartAt and e.time-s.pushAt<=K.pushMax then pushed=true end
 end
 return e,s,pushed
end

tests.K_163U=function()
 assert(K.pushLevel==0.03 and K.pushCaution==1.0 and K.pushTime==1.0 and K.pushGapMin==25 and K.pushMax==10 and K.pushPairCooldown==20)
end

tests.ATTACK_PUSH_RACE_163U=function()
 for _,sign in ipairs({-1,1}) do
  local e,s,pushed=attack('C',sign)
  assert((e.stats.attackPush or 0)>=1,sign..': push counted ('..tostring(e.stats.attackPush)..', '..s.state..')')
  assert(pushed,sign..': push active during the attempt')
  local cmd=e.commands[2]
  assert(cmd.caution==nil or cmd.caution<=math.max(K.pushCaution,s.baseCaution)+1e-6 or s.state=='DRIVE','caution bounded')
 end
end

tests.ATTACK_PUSH_GUARDS_163U=function()
 for _,sign in ipairs({-1,1}) do
  local e=attack('J',sign); assert((e.stats.attackPush or 0)==0,sign..': never outside the race')
  e=attack('C',sign,{each=function(en) en.states[2].flW=1 end}); assert((e.stats.attackPush or 0)==0,sign..': never on the careful first lap')
  e=attack('C',sign,{gap=60}); assert((e.stats.attackPush or 0)==0 or e.states[2].state~='DRIVE',sign..': far target, no push before the attempt')
 end
end

-- Le niveau commandé est plus haut avec le coup de pouce qu'avec K.pushLevel à 0 (même scène), puis revient au bout
-- de K.pushMax s.
tests.ATTACK_PUSH_LEVEL_163U=function()
 for _,sign in ipairs({-1,1}) do
  local old=K.pushLevel
  K.pushLevel=0; local e0=attack('C',sign,{frames=90}); local l0=e0.commands[2].level
  K.pushLevel=old; local e1,s1=attack('C',sign,{frames=90}); local l1=e1.commands[2].level
  assert(l0 and l1 and l1>l0+1e-4,sign..': pushed level higher ('..tostring(l0)..' / '..tostring(l1)..', '..s1.state..')')
  s1.pushAt=e1.time-K.pushMax-1
  assert(not (e1.time-s1.pushAt<=K.pushMax),sign..': expired after K.pushMax s')
 end
end

return tests
