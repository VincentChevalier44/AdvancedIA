-- Affinage 2.0.2 f (courses du 15 novembre) : défense anticipée enfin possible, bilan au journal, coup de pouce de
-- l'aspiration fini avant le freinage, version « Beta x.y.z » d'une app compagne lue, réglage d'aspiration d'AC lu aussi
-- dans assists.ini. Noms terminés par _202 ou LOCK_. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local J=require('src/journal')
local Snapshot=require('src/snapshot')
local A=require('src/applier')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Leader 2 à 250 km/h, suiveur 3 à gap m derrière (x m de côté), +sa km/h ; carte des lignes droites : ahead m avant le
-- freinage partout ; turn : sens du virage suivant (sonde remplacée).
local function run(turn,gap,sa,x,ahead,opts)
 opts=opts or {}
 local e,f=F.scene('C',3); local p=e.profiles.C
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.defenseEnabled=true; p.startDelay=0; p.startRelax=0
 p.towBreakEnabled=false; p.slipstreamEnabled=false
 E.changed(e)
 local saved=Snapshot.turnAhead
 Snapshot.turnAhead=function() return turn end
 local s=e.states[2]
 local ok,err=pcall(function()
  local z=3*f.length+1000
  F.place(f,1,z-5000,100); F.place(f,2,z,250); F.place(f,3,z-gap-4.4,250+sa,x)
  F.tick(e,f,1/60)
  local m=e.aero; assert(m and m.bins>0,'aero map')
  local r=math.floor(ahead*m.bins/f.length+0.5)
  for b=1,m.bins do m.seen[b]=K.towMapSeen; m.st[b]=1; m.run[b]=r end
  m.at=e.time
  for k=1,(opts.steps or 30) do
   F.place(f,1,z-5000,100); F.place(f,2,z,250); F.place(f,3,z-gap-4.4,250+sa,x)
   if opts.brake3 then f.cars[3].brake=opts.brake3 end
   e.states[3].state='DRIVE'; s.nextPerception=0; m.at=e.time
   F.tick(e,f,1/60)
  end
 end)
 Snapshot.turnAhead=saved
 assert(ok,err)
 return s,e
end
local function covered(s) return s.state=='DEFEND' and s.reason=='cover' end
tests.K_202F=function()
 assert(K.coverGap==25 and K.coverLatMax==1.6 and K.coverAheadMin==80 and K.coverAheadMax==600 and K.coverChance==0.5)
 assert(K.coverDiagPeriod==120 and K.towBoostEndAhead==150)
end
-- LOCK : couverture dans la fenêtre élargie (courses du 15 novembre : suiveurs dans l'aspiration à 20-25 m, 1,2 à 1,6 m de
-- côté, à la même vitesse) ; compteurs du bilan tenus ; ligne de bilan traduite.
tests.LOCK_COVER_FIRES_202=function()
 local chance=K.coverChance; K.coverChance=1
 local ok,err=pcall(function()
  for _,turn in ipairs({1,-1}) do
   local s,e=run(turn,22,0,turn>0 and 1.4 or -1.4,100)
   assert(covered(s),'turn '..turn..': cover at 22 m, 1.4 m aside, 100 m before braking')
   assert(s.targetSide==(turn>0 and -1 or 1),'inside side')
   local cd=e.coverDiag; assert(cd and cd.cand>0 and cd.band>0 and cd.done==1,'diagnostic counters')
   -- Toujours rien à 30 m, ni déjà décalé (2,5 m), ni à 60 m du freinage.
   assert(not covered((run(turn,30,0,0,250))),'30 m: no cover')
   assert(not covered((run(turn,15,0,2.5,250))),'2.5 m aside: no cover')
   assert(not covered((run(turn,15,0,0,60))),'60 m before braking: no cover')
  end
  -- Sens du virage inconnu : compté, jamais couvert.
  local s,e=run(0,15,0,0,250)
  assert(not covered(s) and e.coverDiag.turn0>0,'unknown turn counted')
 end)
 K.coverChance=chance
 assert(ok,err)
 assert(J.english('defense anticipee, bilan: candidats 12, dans la bande 5, sens du virage inconnu 1, tirage refuse 2, cote occupe 0, couvertures 2')
  =='anticipated defence, summary: candidates 12, in the band 5, corner direction unknown 1, roll refused 2, side taken 0, covers 2')
end
-- LOCK : le coup de pouce de l'aspiration (+2 % de niveau) s'arrête K.towBoostEndAhead m avant le bout de la ligne droite
-- et au freinage (S28 : tête-à-queue à l'entrée de la première chicane).
tests.LOCK_TOWBOOST_ENDS_202=function()
 local function boosted(ahead,brake)
  local _,e=run(0,10,0,0,ahead,{brake3=brake,steps=40})
  return (e.stats.towBoost or 0)>0
 end
 assert(boosted(400),'400 m of straight left: boost')
 assert(not boosted(100),'100 m before braking: no boost')
 assert(not boosted(400,0.6),'braking: no boost')
end
-- Version d'une app compagne : « VERSION=Beta 2.1.0 » lue (SpotterEngineer, 15 novembre), deux nombres toujours refusés.
tests.COMPANION_VERSION_PREFIX_202=function()
 local v=A.manifestVersion('[ABOUT]\nNAME=SpotterEngineer\nVERSION=Beta 2.1.0\nREQUIRES_ADVANCEDIA=Beta 2.0.2\n')
 assert(v and v[1]==2 and v[2]==1 and v[3]==0,'Beta 2.1.0')
 assert(A.manifestVersion('[ABOUT]\nVERSION=1.3.8\n')[3]==8,'plain still read')
 assert(A.manifestVersion('[ABOUT]\nVERSION=Beta 1.59\n')==nil,'two numbers refused')
end
-- Réglage d'aspiration de Content Manager (assists.ini) lu une fois ; écrit au journal quand il diffère de ac.getAssists.
tests.ASSISTS_FILE_202=function()
 assert(J.english('aspiration d AC: x3.0 dans assists.ini (aide de la voiture du joueur, pas des IA)')=='AC slipstream: x3.0 in assists.ini (player car assist, not the AI)')
 assert(J.english('aspiration d AC: x1.0')=='AC slipstream: x1.0')
end
return tests
