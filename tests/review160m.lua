-- Beta 1.60, fusion des tranches B, C, D, E et du correctif 1.59.1 : points d'intégration. Noms terminés par _160M.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local Pe=require('src/penalties')
local J=require('src/journal')
local K=C.K
local tests={}
-- Tour de formation : pas de « rendez la place » pour un meilleur envol dans les K.formationGrace premières secondes.
tests.FORMATION_LAUNCH_GRACE_160M=function()
 local function scene(since,formation)
  local e,f=F.scene('C',3); local p=e.run
  local inc={cars=e.incidents.cars,playerZone=false,playerNoPass=false,playerInside=false,neutral=true,red=false,neutralMode='fcy',safetyPhase='none',safety=0,formation=formation,neutralSince=since}
  local t=Pe.new()
  F.place(f,1,0,60); F.place(f,3,10,60); Pe.update(t,f,p,'C',inc,0,1/60)
  F.place(f,1,20,60); Pe.update(t,f,p,'C',inc,1/60,1/60)
  return t,f,p,inc
 end
 local t=scene(0,true)
 assert(not t.passedUnder and t.giveBack==0 and t.count==0,'launch at AC s green light: no place to give back')
 local late=scene(-K.formationGrace-1,true)
 assert(late.passedUnder and late.giveBack==3,'after the grace: the formation lap forbids overtaking')
 local fcy=scene(0,false)
 assert(fcy.passedUnder and fcy.giveBack==3,'ordinary neutralisation: no grace')
 -- La grâce finie, la place déjà prise n'est pas réclamée ; un nouveau dépassement l'est.
 local t2,f,p,inc=scene(0,true)
 local now=1/60; while now<K.formationGrace+1 do now=now+0.1; Pe.update(t2,f,p,'C',inc,now,0.1) end
 assert(t2.count==0 and not t2.passedUnder,'place taken at the launch never claimed later')
end
-- Tour de formation : usure par tour non apprise sur ce tour (champ inc.formation de la tranche E, lu par la tranche D).
tests.FORMATION_WEAR_RATE_160M=function()
 local function worn(a,w) a.wearKnown=true; a.tyreWear={w,w,w,w}; a.tyreKm={10,10,10,10}; a.tyreTemp={90,90,90,90}; a.tyreOptimum={90,90,90,90} end
 local function run(formation)
  local e,f=F.scene('C',4)
  e.profiles.C.strategyTyreWearPct=75; e.run.strategyTyreWearPct=75
  f.sessionLaps=20; f.leaderLaps=2; f.timedRace=false; f.sessionMinutes=0; f.started=true
  for i=1,f.count do f.cars[i].lap=2 end
  e.strategy.wearTrust='trusted'
  local a=f.cars[2]; local c=e.strategy.cars[2]
  a.lap=2; worn(a,0.10); F.tick(e,f,0.2)
  a.lap=3; worn(a,0.20); F.tick(e,f,0.2)
  assert(c.wearLaps==1,'first lap learnt')
  e.incidents.formation=formation; F.tick(e,f,0.2); e.incidents.formation=false
  a.lap=4; worn(a,0.22); F.tick(e,f,0.2)
  return c
 end
 local c=run(true)
 assert(c.wearLaps==1 and math.abs(c.wearRate-0.1)<1e-9 and not c.lapForm,'lap with a formation phase: rate not learnt, flag cleared')
 assert(run(false).wearLaps==2,'ordinary lap: learnt')
 assert(require('src/incidents').new().formation==false,'field exists at creation')
end
-- Résumé de la minute : parties 1.60 absentes sans compteur, présentes avec, et traduites.
tests.SUMMARY_PARTS_160M=function()
 local e,f=F.scene('C',3)
 e.wear.count=5; e.wear.avg=0.99; e.wear.worst=0.96
 local plain=J.summary(e,f)
 assert(not plain:find('contacts juges',1,true) and not plain:find('pilotage fin',1,true) and not plain:find('humeur',1,true) and not plain:find('rythme pneus',1,true),'defaults: line unchanged')
 e.stats.blameJudged=3; e.stats.blameFault=1; e.stats.blameIncident=2; e.stats.exitRamp=4; e.stats.limitMistake=1; e.stats.moodStress=2; e.stats.moodTired=1
 e.run.wearPace=true
 local s=J.summary(e,f)
 assert(s:find(' | contacts juges 3 (en tort 1, incidents de course 2)',1,true),s)
 assert(s:find(' | pilotage fin : sorties progressives 4, erreurs a la limite 1',1,true),s)
 assert(s:find(' | humeur : sous pression 2, fatiguees 1',1,true),s)
 assert(s:find(' | rythme pneus et carburant : moyenne -1.0 %, plus forte baisse -4.0 %',1,true),s)
 assert(e.stats.blameJudged==0,'counters reset')
 local en=J.english(s)
 assert(en:find('contacts judged 3 (at fault 1, racing incidents 2)',1,true) and en:find('fine driving: progressive exits 4, mistakes at the limit 1',1,true) and en:find('mood: under pressure 2, tired 1',1,true) and en:find('tyre and fuel pace: average',1,true) and en:find('largest loss',1,true),en)
 assert(J.english('tete-a-queue, humeur: Jean Dupont | stress 40 %, fatigue 10 %')=='spin, mood: Jean Dupont | stress 40%, fatigue 10%')
end
return tests
