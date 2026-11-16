-- Affinage 1.64 (lot q1 de la défense, fichier review164dc) : défense anticipée (couvrir l'intérieur avant le freinage, src/director.lua). Noms terminés par _164Q1
-- ou LOCK_. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local J=require('src/journal')
local Snapshot=require('src/snapshot')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Leader 2, suiveur 3 à gap m derrière (aligné à x m), +sa km/h ; carte des lignes droites : ahead m avant le freinage partout.
-- opts : brake (pédale du leader), lap3 (tour du suiveur), flw (premier tour), steps (images).
local function run(turn,gap,sa,x,ahead,opts)
 opts=opts or {}
 local e,f=F.scene('C',3); local p=e.profiles.C
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.defenseEnabled=true; p.startDelay=0; p.startRelax=0
 p.towBreakEnabled=false; p.slipstreamEnabled=false
 E.changed(e)
 local saved=Snapshot.turnAhead
 Snapshot.turnAhead=function() return turn end
 local s=e.states[2]; local states={}
 local ok,err=pcall(function()
  local z=3*f.length+1000
  F.place(f,1,z-5000,100); F.place(f,2,z,250); F.place(f,3,z-gap-4.4,250+sa,x)
  F.tick(e,f,1/60)
  local m=e.aero; assert(m and m.bins>0,'aero map')
  local run=math.floor(ahead*m.bins/f.length+0.5)
  for b=1,m.bins do m.seen[b]=K.towMapSeen; m.st[b]=1; m.run[b]=run end
  m.at=e.time
  for k=1,(opts.steps or 30) do
   F.place(f,1,z-5000,100); F.place(f,2,z,250); F.place(f,3,z-gap-4.4,250+sa,x)
   if opts.lap3 then f.cars[3].lap=opts.lap3 end
   if opts.brake then f.cars[2].brake=opts.brake end
   if opts.flw then s.flW=1 end
   e.states[3].state='DRIVE'; s.nextPerception=0; m.at=e.time
   F.tick(e,f,1/60)
   states[#states+1]=s.state..'/'..tostring(s.reason)..'/'..tostring(s.targetSide)
  end
 end)
 Snapshot.turnAhead=saved
 assert(ok,err)
 return s,e,states
end
local function covered(s) return s.state=='DEFEND' and s.reason=='cover' end
-- Aucune couverture à aucune image (une couverture lancée puis aussitôt finie compte aussi).
local function never(...)
 local s,e,st=run(...)
 for _,v in ipairs(st) do if v:find('^DEFEND/cover') then return false end end
 return not covered(s) and count(e,'defense anticipee:')==0 and (e.stats.defenceCover or 0)==0
end
tests.K_164DC=function()
 -- 2.0.2 f : fenêtre élargie (25 m, 1,6 m, dès 80 m) et tirage à 0,5 (aucune couverture en jeu avant).
 assert(K.coverEnabled==true and K.coverGap==25 and K.coverSaMin==0 and K.coverLatMax==1.6 and K.coverAheadMin==80 and K.coverAheadMax==600)
 assert(K.coverTimeMax==6 and K.coverChance==0.5 and K.coverAssert==0.3 and K.coverSeed==7 and K.coverLogGap==20)
end
-- LOCK : couverture de l'intérieur, dans les deux sens de virage, contre un suiveur aligné 15 m derrière ; aucune à
-- hauteur, au freinage, hors de la bande de distance, contre une voiture qui se dédouble, au premier tour, règle coupée ;
-- un seul mouvement (côté constant, une décision par tour).
tests.LOCK_DEFENSE_EARLY_COVER_164=function()
 local chance=K.coverChance; K.coverChance=1
 local ok,err=pcall(function()
  for _,turn in ipairs({1,-1}) do
   local s,e,st=run(turn,15,20,0,250)
   assert(covered(s),'turn '..turn..': cover expected, got '..table.concat(st,' '))
   -- Intérieur : côté du centre du virage, même correspondance que la défense ordinaire (attaquant à lat>0 : côté -1).
   assert(s.targetSide==(turn>0 and -1 or 1),'turn '..turn..': inside side '..tostring(s.targetSide))
   assert(count(e,'defense anticipee:')==1 and (e.stats.defenceCover or 0)==1,'one line, counted once')
   local sides={}; for _,v in ipairs(st) do if v:find('^DEFEND/cover') then sides[v]=true end end
   local n=0; for _ in pairs(sides) do n=n+1 end
   assert(n==1,'single move, constant side: '..table.concat(st,' '))
   -- Aligné à 1 m près (presque) : couverture aussi.
   assert(covered((run(turn,15,20,turn>0 and 0.8 or -0.8,250))),'nearly aligned: cover')
   -- Déjà décalé (2,5 m) : jamais la couverture anticipée.
   assert(never(turn,15,20,2.5,250),'attacker already aside: no early cover')
   -- À hauteur : jamais.
   assert(never(turn,-2,20,0,250),'alongside: no cover')
   -- Au freinage : jamais.
   assert(never(turn,15,20,0,250,{brake=0.6}),'braking: no cover')
   -- Hors de la bande : trop loin ou trop près du freinage.
   assert(never(turn,15,20,0,800),'800 m before braking: too early')
   -- Affinage 2.0.1 a (Monza S21-S23 : une seule défense anticipée par course) : 550 m avant le freinage, couverture.
   assert(covered((run(turn,15,20,0,550))),'550 m before braking: cover')
   assert(never(turn,15,20,0,60),'60 m before braking: too late')
   -- Suiveur trop loin, pas plus rapide.
   assert(never(turn,30,20,0,250),'30 m behind: no cover')
   -- Affinage 2.0.1 a : suiveur aligné à la même vitesse (AC garde sa distance, S23 : écart mini médian 9 m) : couverture ;
   -- suiveur qui recule (-5 km/h) : rien.
   assert(covered((run(turn,9,0,0,250))),'same speed in the tow: cover')
   assert(never(turn,15,-5,0,250),'dropping back: no cover')
   -- Voiture qui se dédouble : jamais.
   assert(never(turn,15,20,0,250,{lap3=5}),'lapping car: no cover')
   -- Premier tour : jamais.
   assert(never(turn,15,20,0,250,{flw=true}),'first lap: no cover')
  end
  -- Sens du virage inconnu : rien.
  assert(never(0,15,20,0,250),'unknown turn: no cover')
  -- Règle coupée.
  local saved=K.coverEnabled; K.coverEnabled=false
  local s=run(1,15,20,0,250); K.coverEnabled=saved
  assert(not covered(s),'switch off: no cover')
 end)
 K.coverChance=chance
 assert(ok,err)
 assert(J.english('defense anticipee: A couvre l interieur devant B (250 m avant le freinage)')=='early defence: A covers the inside ahead of B (250 m before braking)',J.english('defense anticipee: A couvre l interieur devant B (250 m avant le freinage)'))
end
return tests
