-- Beta 1.42 AERO : aspiration cassée en ligne droite, air sale derrière une voiture, urgence des derniers tours.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local D=require('src/director')
local C=require('src/config')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Constantes changées le temps d'un test (tirage au sort rendu certain), toujours rendues.
local function with(values,fn)
 local saved={}; for k,v in pairs(values) do saved[k]=K[k]; K[k]=v end
 local ok,err=pcall(fn)
 for k,v in pairs(saved) do K[k]=v end
 if not ok then error(err,0) end
end
-- Carte des lignes droites apprise : tout le tour en ligne droite sauf les endroits de from à to (fractions du tour).
local function straightMap(e,f,from,to)
 F.tick(e,f,1/60)
 local m=e.aero; assert(m and m.bins==e.delta.bins,'straight map created')
 for b=1,m.bins do
  local x=(b-0.5)/m.bins; local corner=x>=from and x<to
  m.st[b]=corner and 0 or 1; m.seen[b]=K.towMapSeen
 end
 m.at=-math.huge
 return m
end
-- Course : meneur (voiture 2) à 200 km/h sur la ligne droite, suiveur (voiture 3) dans son sillage ; joueur loin.
local function towScene(profile,gap,setup,count)
 local e,f=F.scene(profile or 'C',count or 3); e.p.personalLineJitter=0
 if setup then setup(e,f) end
 E.changed(e)
 F.place(f,1,-4000,100); F.place(f,2,1000,200); F.place(f,3,1000-(gap or 15)-4.4,200)
 -- Relecture 1.42 : jamais au premier tour de la course ; la paire est dans son troisième tour.
 for k=1,f.count do f.cars[k].lap=2 end
 straightMap(e,f,0.5,0.55)
 return e,f
end

tests.TOW_BREAK_142=function()
 with({towChance=1},function()
  local e,f=towScene()
  local s=e.states[2]
  F.tick(e,f,1,true)
  assert(s.state=='DEFEND' and s.reason=='tow' and s.towing,'tow broken on the straight: '..s.state..' '..s.reason)
  assert(count(e,'aspiration: Driver_2 casse l aspiration de Driver_3')==1,'logged once')
  F.tick(e,f,2,true)
  assert(math.abs(s.offset)>0.1,'one move to the side: '..s.offset)
  local moved=s.directionCount
  F.tick(e,f,K.towHoldMax,true)
  assert(s.state~='DEFEND' and not s.towing and (e.stats.tow_end or 0)==1,'back to the line: '..s.state)
  assert(s.directionCount<=moved,'the return is not counted as a change of side')
  F.tick(e,f,K.towCooldown+K.towPairCooldown,true)
  assert(count(e,'aspiration:')==1,'one evaluation per straight')
  -- Tirage perdu : pas de nouvel essai sur la même ligne droite.
  local e2,f2
  with({towChance=0},function() e2,f2=towScene(); F.tick(e2,f2,0.5,true) end)
  F.tick(e2,f2,1,true)
  assert(count(e2,'aspiration:')==0,'draw lost: no second try on the same straight')
  assert(count(e,'plafond anti-zigzag')==0,'no direction_limit')
 end)
end
-- Retour à la ligne avant la fin de la ligne droite (freinage) : K.towReturnTime s avant le virage.
tests.TOW_RETURNS_BEFORE_CORNER_142=function()
 with({towChance=1,towHoldMax=200},function()
  -- Dépassements coupés : seul le meneur manœuvre, le suiveur reste dans son sillage.
  local e,f=towScene('C',15,function(e) e.profiles.C.overtakeEnabled=false end)
  local s=e.states[2]
  F.tick(e,f,1,true)
  assert(s.towing,'towing')
  -- Virage à 5000 m : le meneur y arrive en (5000-1000-55)/55,6 s environ ; retour au plus tard K.towReturnTime s avant.
  local endAt
  for _=1,80*60 do F.tick(e,f,1/60,true); if not s.towing then endAt=f.cars[2].z; break end end
  assert(endAt and endAt<5000-(K.towReturnTime-0.5)*200/3.6 and endAt>5000-(K.towReturnTime+1.5)*200/3.6,'tow ended just before the corner: '..tostring(endAt))
  assert(s.reason=='tow_end','ended by the straight end')
 end)
end
tests.TOW_SAFETY_142=function()
 with({towChance=1},function()
  local function towed(e,f,seconds) F.tick(e,f,seconds or 1.5,true); return count(e,'aspiration:')>0 or e.states[2].towing end
  -- Hors course : jamais.
  local e,f=towScene('P'); assert(not towed(e,f),'never in practice')
  -- Réglage coupé.
  e,f=towScene('C',15,function(e) e.profiles.C.towBreakEnabled=false end); assert(not towed(e,f),'switched off')
  -- Suiveur trop loin.
  e,f=towScene('C',45); assert(not towed(e,f),'follower out of range')
  -- Suiveur qui prend un tour (drapeau bleu) : jamais.
  e,f=towScene(); f.cars[3].lap=f.cars[2].lap+1; assert(not towed(e,f),'never against a lapping car')
  -- Suiveur attardé (un tour de retard) : jamais.
  e,f=towScene(); f.cars[3].lap=f.cars[2].lap-1; assert(not towed(e,f),'never against a lapped car')
  -- Voiture à côté du meneur : jamais.
  -- (Relecture 1.42 : voiture à côté du côté opposé à la cassure, pour que seul le garde « à côté » la refuse.)
  e,f=towScene('C',15,nil,4); F.place(f,4,1000,200,-3.5); assert(not towed(e,f),'never with a car alongside')
  -- Au freinage : jamais.
  e,f=towScene(); f.cars[2].brake=1; assert(not towed(e,f),'never under braking')
  -- Ligne droite trop courte (300 m) : jamais.
  e,f=towScene(); local m=straightMap(e,f,0.13,0.07); for b=1,m.bins do local x=(b-0.5)/m.bins; m.st[b]=(x>=0.1 and x<0.138) and 1 or 0 end; m.at=-math.huge
  F.place(f,2,1010,160); F.place(f,3,1010-19.4,160); assert(not towed(e,f,0.5),'never on a short straight (380 m)')
  -- Plafond anti-zigzag presque atteint : jamais (deux changements de côté encore permis exigés).
  e,f=towScene(); local s=e.states[2]
  for j=1,K.directionLimit-1 do s.directions[j]=e.time-1 end; s.lastDirectionAt=e.time-5
  assert(not towed(e,f,0.5),'never without room in the anti-zigzag budget')
 end)
end
-- Remise à zéro : aspiration cassée oubliée (changement de session, déplacement).
tests.TOW_RESET_142=function()
 local s=D.newState(); s.towing=true; s.towDone=true; s.dirty=1; s.urgency=1
 D.reset(s,0)
 assert(not s.towing and not s.towDone and s.dirty==0 and s.urgency==0,'reset')
end

-- Air sale : derrière une voiture en virage, gaz légèrement relâchés et micro-corrections ; jamais en ligne droite, ni
-- loin derrière, ni là où le réglage est coupé (journée circuit).
local function dirtyScene(profile,gap,yaw,setup)
 local e,f=F.scene(profile or 'C',3); e.p.personalLineJitter=0
 if setup then setup(e,f) end
 E.changed(e)
 F.place(f,1,-4000,100); F.place(f,2,1000,150); F.place(f,3,1000-(gap or 8)-4.4,150)
 f.cars[3].yawRate=yaw or 0.4
 return e,f
end
tests.DIRTY_AIR_142=function()
 local e,f=dirtyScene()
 local s=e.states[3]; local low,maxBase=1,0
 for _=1,4*60 do F.tick(e,f,1/60); low=math.min(low,e.commands[3].throttleLimit); maxBase=math.max(maxBase,math.abs(s.base)) end
 assert(s.dirty>0,'in dirty air')
 assert(low<1 and low>=1-e.p.dirtyAirLiftPct/100-1e-9,'slight throttle lift: '..low)
 assert(maxBase>0.005,'micro-corrections: '..maxBase)
 assert(s.directionCount==0,'never counted as a change of side')
 assert((e.stats.dirtyAir or 0)>=1,'episode counted')
 local function lift(...) local e2,f2=dirtyScene(...); F.tick(e2,f2,1); return e2.commands[3].throttleLimit,e2.states[3] end
 assert(lift('C',8,0)==1,'never on a straight')
 assert(lift('C',30)==1,'never beyond the dirty air distance')
 assert(lift('J')==1,'off in track day by default')
 assert(lift('P')<1,'on in practice')
 local limit,st=lift('C',8,0.4,function(e) e.profiles.C.dirtyAirEnabled=false end)
 assert(limit==1 and st.dirty==0,'switched off')
 -- Sans air sale, la ligne ne varie pas (variation coupée, voiture proche).
 local e3,f3=dirtyScene('C',8,0.4,function(e) e.profiles.C.dirtyAirEnabled=false end)
 local quiet=0; for _=1,4*60 do F.tick(e3,f3,1/60); quiet=math.max(quiet,math.abs(e3.states[3].base)) end
 assert(quiet==0,'no line variation without dirty air: '..quiet)
end

-- Urgence des derniers tours : agressivité et défense renforcées contre un adversaire direct, jamais contre une
-- attardée, ni avant les derniers tours ; une ligne au journal par session.
local function finalScene(lapsLeft,setup,gap,kmh3)
 local e,f=F.scene('C',3); e.p.personalLineJitter=0
 e.profiles.C.towBreakEnabled=false
 if setup then setup(e,f) end
 E.changed(e)
 -- Beta 1.59 : 20 tours (au plus 20 % de la course : les 3 derniers tours restent concernés).
 f.sessionLaps=20; f.leaderLaps=20-lapsLeft; f.timedRace=false
 -- Beta 1.47 : suiveur nettement d'un côté (condition de la défense).
 F.place(f,1,-4000,100); F.place(f,2,1000,200); F.place(f,3,1000-(gap or 25)-4.4,kmh3 or 200,0.8)
 -- Relecture 1.42 : tours restants de chaque voiture (même tour que le leader ici).
 for k=1,f.count do f.cars[k].lap=f.leaderLaps end
 return e,f
end
tests.FINAL_LAPS_142=function()
 local function aggression(...) local e,f=finalScene(...); F.tick(e,f,3); return e.commands[2].aggression,e end
 local base=aggression(2,function(e) e.profiles.C.finalLapsEnabled=false end)
 local boosted,e=aggression(2)
 assert(e.states[2].urgency>0.6 and e.states[2].urgency<0.7,'two laps left of three: '..e.states[2].urgency)
 assert(boosted>base*1.05,'more aggression in the last laps: '..boosted..' vs '..base)
 assert(count(e,'fin de course: 3 derniers tours')==1,'logged once per session')
 assert(e.race.known and e.race.lapsLeft==2,'laps left known')
 local early=aggression(5); assert(math.abs(early-base)<1e-9,'not before the last laps')
 local e2,f2=finalScene(2); f2.cars[3].lap=f2.cars[2].lap-1; F.tick(e2,f2,3)
 assert(e2.states[2].urgency==0 and math.abs(e2.commands[2].aggression-base)<1e-9,'never against a lapped car')
 local e3,f3=finalScene(2); f3.cars[3].lap=f3.cars[2].lap+1; F.tick(e3,f3,3)
 assert(e3.states[2].urgency==0,'never against a lapping car (blue flag)')
 -- Une ligne par session, même longtemps après (au-delà du filtre des doublons du journal) ; la session suivante en
 -- note une nouvelle.
 local e4,f4=finalScene(2); F.tick(e4,f4,K.logDedup+2)
 assert(count(e4,'fin de course:')==1,'once per session, not every frame')
 f4.session=f4.session+1; F.tick(e4,f4,1)
 assert(count(e4,'fin de course:')==2,'logged again in the new session')
end
-- Défense : déclenchée plus loin dans les derniers tours (adversaire direct qui se rapproche).
tests.FINAL_DEFENSE_142=function()
 with({defenseChance=1},function()
  local function defended(...)
   local e,f=finalScene(...)
   -- Positions tenues : l'écart reste celui du test, seule la vitesse de rapprochement compte.
   for _=1,60 do F.tick(e,f,1/60); if e.states[2].state=='DEFEND' then return true end end
   return false
  end
  local trigger=C.defaults('C').defenseTriggerGap
  assert(not defended(2,function(e) e.profiles.C.finalLapsEnabled=false end,trigger+2,215),'no defence beyond the trigger gap')
  assert(defended(2,nil,trigger+2,215),'defence from further away in the last laps')
  assert(not defended(6,nil,trigger+2,215),'not before the last laps')
 end)
end
-- Course chargée (30 IA par paires, lignes droites et virages, trois derniers tours) : aspiration cassée, air sale et
-- urgence s'y produisent, sans erreur ni déclenchement de plus du plafond anti-zigzag que réglages coupés.
tests.AERO_RACE_WORKLOAD_142=function()
 local W=require('tests/workload')
 local function run(on)
  local e,f=W.prepare(30)
  e.g.autoProfile=false; E.select(e,'C')
  local rp=e.profiles.C; rp.towBreakEnabled=on; rp.dirtyAirEnabled=on; rp.finalLapsEnabled=on; E.changed(e)
  -- Relecture 1.42 : urgence calculée sur les tours de chaque voiture : course de 3 tours (les voitures en font un).
  f.sessionLaps=3; f.timedRace=false
  for i=1,f.count do local a=f.cars[i]; a.distance=math.floor((i-1)/2)*800+(i%2)*22; a.pace=172+(i%2)*4 end
  local dt=1/60
  for _=1,9000 do
   W.animate(f,e.time,dt)
   for i=1,f.count do local a=f.cars[i]; a.yawRate=(a.spline%0.5)<0.125 and 0.4 or 0; a.pit=false end
   local leader=0; for i=1,f.count do leader=math.max(leader,f.cars[i].lap) end; f.leaderLaps=leader
   E.step(e,f,dt)
   assert(e.errors==0,'no car error')
  end
  return e
 end
 local on,off=run(true),run(false)
 assert((on.stats.tow or 0)>=1,'tow broken in a race')
 assert((on.stats.dirtyAir or 0)>=1,'dirty air in a race')
 assert(count(on,'fin de course:')==1 and count(off,'fin de course:')==0,'last-laps urgency logged once')
 assert((on.stats.limit or 0)<=(off.stats.limit or 0)+1,'no more anti-zigzag triggers: '..(on.stats.limit or 0)..' vs '..(off.stats.limit or 0))
 assert((off.stats.tow or 0)==0 and (off.stats.dirtyAir or 0)==0,'nothing when switched off')
end
return tests
