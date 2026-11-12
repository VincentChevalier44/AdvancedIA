-- Beta 1.62, fusion des deux parties des règles par session : inattentions loin d'un point de freinage et d'une voiture
-- nettement plus rapide derrière (décision 8 complétée), voiture lente hors course, côté de cession à une voiture
-- lancée (yieldSide), tour de refroidissement avant les stands en journée circuit. Noms terminés par _162C.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local J=require('src/journal')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function scene(profile,n,set)
 local e,f=F.scene(profile,n or 3); local p=e.profiles[profile]
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false
 if set then set(p) end
 -- Signes mesurés en jeu sur cette installation : -1 / -1.
 e.g.offsetSign=-1; e.g.sideSign=-1; for i=1,f.count do f.cars[i].sideDot=-1 end
 E.changed(e)
 return e,f
end

tests.K_162C=function()
 assert(K.lapseBrakeTime==3 and K.lapseRearTime==6 and K.lapseFastKmh==15)
end

-- Décision 8 : ligne droite, rien autour : une inattention commence ; point de freinage connu à 2 s : non ; voiture
-- nettement plus rapide à 3 s derrière : non ; voiture au même rythme derrière : oui.
tests.LAPSE_NOT_NEAR_BRAKE_NOR_FAST_BEHIND_162C=function()
 local function run(case)
  local e,f=scene('P',3,function(p) p.lapseEnabled=true end)
  F.place(f,1,-9000,100)
  if case=='fast' then F.rear(e,f,40,30) elseif case=='same' then F.rear(e,f,40,0) else F.place(f,2,0,150); F.place(f,3,3000,150) end
  F.tick(e,f,0.1)
  if case=='brake' then local a=f.cars[2]; e.fl.points[1]=(a.spline+a.speed*2/f.length)%1; e.fl.count=1 end
  local s=e.states[2]; s.lapseAt=e.time; s.lapseUntil=0
  F.tick(e,f,1/60)
  return s.lapseUntil>0
 end
 assert(run('free')==true,'straight, nothing around: a lapse starts')
 assert(run('brake')==false,'braking point 2 s ahead: no lapse')
 assert(run('fast')==false,'clearly faster car close behind: no lapse')
 assert(run('same')==true,'car behind at the same pace: a lapse may start')
end

-- Voiture anormalement lente hors course (essais, journée circuit « line ») : elle quitte la trajectoire pour la voiture
-- qui arrive (cession bleue, jamais « garder sa ligne »), une ligne au journal.
tests.SLOW_CAR_MOVES_ASIDE_OUTSIDE_RACE_162C=function()
 for _,profile in ipairs({'P','J'}) do
  local e,f=scene(profile,3,function(p) if profile=='J' then p.yieldSide='line' end end)
  F.place(f,1,-5000,100)
  local s=e.states[2]; local t=0; local seen=false
  while t<5 do
   F.rear(e,f,50,35); s.abnormalFor=K.slowObstacleTime+10
   F.tick(e,f,1/60); t=t+1/60
   if F.yielding(s.state) then seen=true; break end
  end
  assert(seen and s.yieldBlue==true and s.yieldLine~=true,profile..': slow car moves aside')
  assert(count(e,'IA lente: Driver_2 s ecarte pour Driver_3')==1,profile..': one line')
 end
end

-- Journée circuit : appelée aux stands (demande d'AC) : allure de refroidissement jusqu'à la voie des stands, une ligne ;
-- dans la voie : niveau rendu progressivement (au damier, l'app rend déjà les voitures à AC).
tests.TRACKDAY_COOL_BEFORE_PITS_162C=function()
 local e,f=scene('J',3,function(p) p.outLapEnabled=true end)
 F.tick(e,f,0.5)
 assert((e.commands[2].levelScale or 1)==1,'precondition: free running')
 f.cars[2].requestingPit=true
 F.tick(e,f,K.qualiCoolRamp+0.5)
 assert(math.abs(e.commands[2].levelScale-(1-K.qualiCoolLevel))<1e-6,'cool-down level before the pits: '..tostring(e.commands[2].levelScale))
 assert(count(e,'tour de refroidissement: Driver_2 avant les stands')==1,'one line')
 local en=J.english('tour de refroidissement: Driver_2 avant les stands (niveau -18 %)')
 assert(en=='cool-down pace before the pits: Driver_2 (level -18%)',en)
 assert((e.commands[3].levelScale or 1)==1,'other cars untouched')
 f.cars[2].requestingPit=false; f.cars[2].pit=true
 F.tick(e,f,K.qualiCoolRelease+0.2)
 f.cars[2].pit=false
 F.tick(e,f,1/60)
 local back=e.commands[2].levelScale or 1
 assert(back>1-K.qualiCoolLevel+1e-6,'level released after the call ends: '..tostring(back))
 -- Option coupée : rien.
 local e3,f3=scene('J',3,function(p) p.outLapEnabled=false end)
 f3.cars[2].requestingPit=true
 F.tick(e3,f3,K.qualiCoolRamp+0.5)
 assert((e3.commands[2].levelScale or 1)==1,'warm-up/cool-down switch off: nothing')
end

-- Cession à une voiture lancée : côté réglé (yieldSide), plus le côté du drapeau bleu ; « line » : elle garde sa ligne.
tests.FLYING_YIELD_SIDE_FROM_YIELDSIDE_162C=function()
 local function run(side,blueSide)
  local e,f=F.scene('Q',3); local p=e.profiles.Q
  p.qualiTraffic=true; p.yieldSide=side; p.blueFlagSide=blueSide; p.personalLineJitter=0; p.lapseEnabled=false
  e.g.offsetSign=-1; e.g.sideSign=-1; for i=1,f.count do f.cars[i].sideDot=-1 end
  E.changed(e); F.tick(e,f,1/60)
  local c3=e.quali.cars[3]; c3.out=false; c3.cool=false
  F.place(f,1,-5000,100)
  local s=e.states[2]
  for k=1,6*60 do
   local gap=5*200/3.6-k/60*(200-150)/3.6
   F.place(f,2,0,150); F.place(f,3,-gap-4.4,200); s.nextPerception=0
   F.tick(e,f,1/60)
   if F.yielding(s.state) then break end
  end
  return s
 end
 local s=run('left','right')
 assert(F.yielding(s.state) and s.yieldQuali,'yield to the flying car')
 -- Signe -1 : « gauche » (SDK -1) devient +1 dans le repère interne.
 assert(s.targetSide==1,'side from yieldSide (left), not from blueFlagSide: '..tostring(s.targetSide))
 local s2=run('line','right')
 assert(F.yielding(s2.state) and s2.yieldLine==true,'line: keeps its line for a flying car')
end
return tests
