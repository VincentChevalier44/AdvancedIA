-- Beta 1.62, règles par session (partie R2, hors pilotage) : décisions 3, 4, 5 et 7 du pilote, priorité dans la voie
-- des stands, file du tour de formation, journée circuit (tour de chauffe, reprise après une sortie), préréglages.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Quali=require('src/quali')
local Formation=require('src/formation')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Qualifications : voiture 2 en tour lancé, une ligne avant son refroidissement prévu.
local function flying(e,f)
 local c=e.quali.cars[2]
 c.out=false; c.cool=false; c.planned=false; c.noDrop=true
 F.tick(e,f,1/60); assert(e.quali.push[2],'flying lap')
 c.pushLaps=Quali.target(e.runtimeG.seed,2)-1
 return c
end
local function cross(e,f,i) f.cars[i].lap=f.cars[i].lap+1; F.tick(e,f,1/60) end
-- Décision 3 : tour invalidé (limites de piste) ou passé sous drapeau jaune : refait, pas de refroidissement ; tour
-- propre ensuite : refroidissement prévu.
tests.QUALI_FAULTY_LAP_REDONE_162B=function()
 for _,cause in ipairs({'limits','yellow'}) do
  local e,f=F.scene('Q',3); e.profiles.Q.qualiTraffic=true; E.changed(e); F.tick(e,f,1/60)
  local c=flying(e,f)
  local lap=f.cars[2].lap
  if cause=='limits' then e.sanctions.cars[2].invalidLap=lap else e.states[2].yellow=true; F.tick(e,f,1/60); e.states[2].yellow=false end
  cross(e,f,2)
  assert(not c.cool and c.faultyLap==lap and count(e,'tour refait:')==1,cause..': faulty lap redone, no cool-down')
  assert(e.quali.push[2],cause..': still on a flying lap')
  assert(c.pushLaps==Quali.target(e.runtimeG.seed,2)-1,cause..': the faulty lap does not count')
  cross(e,f,2)
  assert(c.cool and c.planned,cause..': clean lap: planned cool-down')
 end
 -- Joueur : jamais.
 local e,f=F.scene('Q',3); e.profiles.Q.qualiTraffic=true; E.changed(e); F.tick(e,f,1/60)
 local c1=e.quali.cars[1]; c1.out=false; c1.cool=false; F.tick(e,f,1/60)
 e.sanctions.cars[1].invalidLap=f.cars[1].lap; cross(e,f,1)
 assert(count(e,'tour refait:')==0,'never the player')
end
-- Décision 4 : tour de sortie, voiture devant à moins de 2 s, début de tour : écart rouvert (baisse bornée) ; fin de
-- tour : rien.
tests.QUALI_EXIT_GAP_162B=function()
 local function scene(z)
  local e,f=F.scene('Q',3); e.profiles.Q.qualiTraffic=true; E.changed(e)
  F.place(f,1,z-3000,150); F.place(f,2,z,150); F.place(f,3,z+30,150)
  F.tick(e,f,1/60)
  for i=2,3 do local q=e.quali.cars[i]; q.noDrop=false; q.exitAt=e.time; q.out=true; q.outLap=f.cars[i].lap end
  return e,f
 end
 local e,f=scene(1000)
 F.tick(e,f,K.qualiOutRamp*1.5)
 local c=e.quali.cars[2]
 assert(c.gapDrop>0 and c.gapDrop<=K.qualiGapLevel+1e-9,'gap drop applied: '..tostring(c.gapDrop))
 assert(c.gapDrop+K.qualiOutLevel<=K.qualiOutMaxDrop+1e-9,'total out-lap drop bounded')
 assert(math.abs(e.commands[2].levelScale-(1-K.qualiOutLevel)*(1-c.gapDrop))<1e-6,'level lowered by both drops')
 assert(count(e,'laisse filer la voiture devant')==1,'one journal line')
 assert(e.quali.cars[3].gapDrop==0,'nobody ahead of car 3: no gap drop')
 -- Fin du tour de sortie (dernière partie) : jamais de ralenti pour se faire de la place.
 local e2,f2=scene(f.length*(K.qualiGapUntil+0.1))
 F.tick(e2,f2,K.qualiOutRamp*1.5)
 assert(e2.quali.cars[2].gapDrop==0,'last part of the lap: no gap drop')
end
-- Journée circuit : tour de chauffe progressif après une vraie sortie des stands (outLapEnabled), jamais sans.
tests.TRACKDAY_WARMUP_LAP_162B=function()
 for _,on in ipairs({true,false}) do
  local e,f=F.scene('J',3); e.profiles.J.outLapEnabled=on; E.changed(e)
  f.cars[2].pit=true; F.tick(e,f,1/60)
  f.cars[2].pit=false; F.tick(e,f,K.qualiOutRamp*0.5)
  local half=e.commands[2].levelScale or 1
  if on then
   assert(half<1 and half>1-K.qualiOutLevel+1e-6,'ramp: '..tostring(half))
   F.tick(e,f,K.qualiOutRamp)
   assert(math.abs(e.commands[2].levelScale-(1-K.qualiOutLevel))<1e-6,'warm-up level')
   assert(count(e,'tour de chauffe:')==1,'one line')
   e.quali.cars[2].jExitAt=e.time-K.qualiOutGrace-1; f.cars[2].lap=f.cars[2].lap+1; F.tick(e,f,K.qualiCoolRelease+0.1)
   assert((e.commands[2].levelScale or 1)==1,'level back after the line')
  else
   assert(half==1 and count(e,'tour de chauffe:')==0,'switch off: nothing')
  end
 end
end
-- Décision 5 : drapeaux bleus ignorés de suite (sous l'option sanContact) : pénalité au troisième ; elle cède : compte
-- remis à zéro.
tests.BLUE_FLAGS_IGNORED_PENALTY_162B=function()
 -- Relecture M1 : par le directeur. Attardée en plein virage (veto « virage ») pendant 60 s : jamais de drapeau compté,
 -- jamais de pénalité ; le retard est noté une fois.
 local e,f=F.scene('C',3); local p=e.profiles.C
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.startDelay=0; p.startRelax=0; p.sanContact=true
 E.changed(e); F.place(f,1,-5000,100)
 local t=0
 while t<60 do F.rear(e,f,30,2); f.cars[3].lap=3; f.cars[2].yawRate=e.run.cornerYawRef; F.tick(e,f,1/60); t=t+1/60 end
 local c=e.sanctions.cars[2]
 assert(not F.yielding(e.states[2].state) and e.states[2].blueAiLate,'vetoed: late, no yield')
 assert(c.blueN==0 and c.time==0 and count(e,'drapeau bleu IA ignore:')==0,'veto (corner): never counted ('..c.blueN..', '..c.time..')')
 -- Sans veto (temps libre) : drapeaux 1, 2, 3, une seule pénalité par épisode, hors du compte du drapeau noir ; même
 -- voiture qui reste derrière : plus rien ; nouvelle voiture : nouvel épisode.
 local s=e.states[2]; e.log.dedup=0
 local function free(w) s.blueAiBy=3; s.blueAiLate=true; s.blueAiYield=false; s.blueAiFree=w; F.rear(e,f,30,2); f.cars[3].lap=3; F.tick(e,f,1/60) end
 free(K.blueLogTime); assert(c.blueN==1,'first flag')
 local lines=count(e,'drapeau bleu IA ignore:')
 free(K.blueLogTime+0.5); assert(c.blueN==1 and count(e,'drapeau bleu IA ignore:')==lines,'same flag neither counted nor logged twice')
 free(K.blueLogTime+K.blueIgnoreStep); free(K.blueLogTime+2*K.blueIgnoreStep)
 assert(c.time==e.run.sanTimeSeconds and c.count==0,'third flag: one time penalty, not counted towards the black flag')
 for k=3,12 do free(K.blueLogTime+k*K.blueIgnoreStep) end
 assert(c.time==e.run.sanTimeSeconds and count(e,'drapeaux bleus ignores')==1,'more than 3 flags in the same episode: no second penalty')
 -- Beta 1.62 (dernier lot) : une seule ligne par épisode, au troisième drapeau (celui de la pénalité).
 assert(count(e,'drapeau bleu IA ignore:')==1,'journal: one line per episode, at the third flag ('..count(e,'drapeau bleu IA ignore:')..')')
 c.blueBy=1; free(K.blueLogTime); assert(c.blueN==1 and not c.blueDone and c.blueBy==3,'another lapper: new episode')
 s.blueAiYield=true; F.tick(e,f,1/60); assert(c.blueN==0,'yields: count reset')
 -- Option coupée : rien.
 local e2,f2=F.scene('C',3); e2.profiles.C.sanContact=false; E.changed(e2); F.tick(e2,f2,1/60)
 local s2=e2.states[2]; s2.blueAiBy=3; s2.blueAiLate=true; s2.blueAiFree=K.blueLogTime+3*K.blueIgnoreStep; F.tick(e2,f2,1/60)
 assert(e2.sanctions.cars[2].blueN==0 and e2.sanctions.cars[2].time==0,'option off: nothing')
end
-- Priorité dans la voie des stands : IA à son emplacement retenue tant qu'une voiture lancée dans la voie arrive
-- derrière, au plus K.boxReleaseMax s.
tests.PIT_RELEASE_PRIORITY_162B=function()
 local e,f=F.scene('C',3); F.tick(e,f,1/60)
 local a=F.place(f,2,2000,0); a.pit=true; a.inPitBox=true
 local b=F.place(f,3,2000-30,60); b.pit=true; b.inPitBox=false
 -- Beta 1.62 (relecture 162v, point 3) : immobile à son emplacement (service d'AC) : ni retenue ni temps compté ; dès
 -- qu'elle part (fin du service), retenue au plus K.boxReleaseMax s.
 F.tick(e,f,K.boxReleaseMax+2)
 assert(not e.commands[2].pitHold and e.pits.release[2].since<0,'service: no hold, no time spent')
 F.place(f,2,2000,5); F.tick(e,f,1/60)
 assert(e.commands[2].pitHold==true and count(e,'attend que')==1,'held while a car comes down the lane')
 F.tick(e,f,K.boxReleaseMax+0.5)
 assert(not e.commands[2].pitHold,'bounded wait')
 -- Voiture déjà passée : aucune retenue.
 local e2,f2=F.scene('C',3); F.tick(e2,f2,1/60)
 local a2=F.place(f2,2,2000,5); a2.pit=true; a2.inPitBox=true
 local b2=F.place(f2,3,2000+30,60); b2.pit=true; b2.inPitBox=false
 F.tick(e2,f2,1/60)
 assert(not e2.commands[2].pitHold,'car already past: no hold')
 -- Relecture 1.62 (S4) : service d'AC (voie vide plus longtemps que K.boxReleaseMax) puis une voiture arrive : retenue
 -- entière, l'attente repart de zéro ; décalage de l'horloge : retenue décalée aussi.
 local e3,f3=F.scene('C',3); F.tick(e3,f3,1/60)
 local a3=F.place(f3,2,2000,5); a3.pit=true; a3.inPitBox=true
 local b3=F.place(f3,3,2000-30,60); b3.pit=true; b3.inPitBox=false
 F.tick(e3,f3,1/60); assert(e3.commands[2].pitHold,'first car: held')
 F.place(f3,3,2000+30,60); F.tick(e3,f3,K.boxReleaseMax+2); assert(not e3.commands[2].pitHold,'lane empty')
 F.place(f3,3,2000-30,60); F.tick(e3,f3,1/60); assert(e3.commands[2].pitHold,'next car: held again, fresh wait')
 local r=e3.pits.release[2]; local before=r.since
 require('src/pits').rebase(e3.pits,100); assert(math.abs(r.since-(before-100))<1e-9,'rebased')
end
-- Tour de formation : file étirée (plus de dix longueurs) : la tête ralentit, sans effet composé.
tests.FORMATION_STRUNG_QUEUE_162B=function()
 -- Relecture 1.62 (S2) : seules les voitures devant le plus grand écart ralentissent ; celles de derrière recollent
 -- (Incidents.cap par voiture, puis avancement simulé à l'allure plafonnée : la file se regroupe, sans téléportation).
 local Incidents=require('src/incidents')
 local e,f=F.scene('C',4); F.tick(e,f,1/60)
 local fo=Formation.new(); local t=e.incidents
 e.run.startRealism=false; t.formation=true; t.neutral=true
 local base=Formation.pace(e.run); t.formationKmh=base
 local pos={[1]=0,[2]=1100,[3]=1080,[4]=980}
 local function place() for i=1,4 do F.place(f,i,pos[i],base/3.6) end end
 place()
 local gap=Formation.worstGap(fo,f)
 assert(math.abs(gap-100)<1e-6,'worst gap among AI only (the player far behind is ignored): '..gap)
 for _=1,10 do Formation.bunch(fo,e,f,e.time,1) end
 assert(t.formationKmh==base and t.formationSlowFrom,'base pace kept, cars ahead of the gap flagged')
 assert(math.abs(t.formationSlowKmh-base*K.formationWaitMult)<1e-9,'slowed pace not compounded: '..tostring(t.formationSlowKmh))
 assert(count(e,'file etiree')==1,'one line')
 local function cap(i) return (Incidents.cap(t,f,i,e.run,e.delta,e.states,0)) end
 assert(cap(2)<cap(4)-1,'car ahead of the gap slowed, car behind it not: '..cap(2)..' / '..cap(4))
 local start=pos[3]-pos[4]
 for _=1,60 do
  for i=2,4 do pos[i]=pos[i]+cap(i)/3.6 end
  place(); Formation.bunch(fo,e,f,e.time,1)
 end
 assert(pos[3]-pos[4]<start-30,'the queue regroups: '..(pos[3]-pos[4])..' m (was '..start..')')
 -- Le joueur, seul loin derrière : rien.
 local e2,f2=F.scene('C',3); F.tick(e2,f2,1/60)
 F.place(f2,1,0,30); F.place(f2,2,2000,30); F.place(f2,3,1990,30)
 local g2=Formation.worstGap(Formation.new(),f2)
 assert(g2<20,'player lagging: no strung queue ('..g2..')')
end
-- Journée circuit : reprise après une sortie, attente de la piste libre au plus K.rejoinWaitMaxJ s.
tests.TRACKDAY_REJOIN_WAIT_162B=function()
 for _,profile in ipairs({'J','C'}) do
  local e,f=F.scene(profile,3); F.tick(e,f,1/60)
  local a=f.cars[2]; a.offtrack=true; F.place(f,2,2000,0); a.offtrack=true
  local c=e.incidents.cars[2]; c.crashAt=e.time
  F.tick(e,f,1/60)
  assert(c.holding,profile..': held')
  local want=profile=='J' and K.rejoinWaitMaxJ or K.rejoinWaitMax
  assert(math.abs(c.holdMax-c.holdUntil-want)<1e-6,profile..': wait bound '..tostring(c.holdMax-c.holdUntil))
 end
end
-- Décision 3 avec les vrais passages (qualiRuns) : tour lancé fautif toujours refait (au plus K.runsRedoMax fois).
tests.RUNS_FAULTY_LAP_REDONE_162B=function()
 local e,f=F.scene('Q',3)
 e.profiles.Q.qualiRuns=true; E.changed(e); f.left=1000
 local a=f.cars[2]
 a.id='lotus_exos'; a.tyresKnown=true; a.compoundIndex=1
 a.tyreNames={[0]='H',[1]='M',[2]='S',[3]='SS'}; a.tyreLongNames={[0]='Slick Hard',[1]='Slick Medium',[2]='Slick Soft',[3]='Slick SuperSoft'}
 a.dryCompounds={[0]=true,[1]=true,[2]=true,[3]=true}
 a.fuel=40; a.maxFuel=60; a.fuelPerLap=2.5; a.lastLap=90; a.bestLap=88
 a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0
 F.tick(e,f,0.2)
 local cmd=e.commands[2]
 a.pit=false; a.inPitBox=false; a.kmh=150; a.speed=150/3.6; a.lap=5
 F.tick(e,f,K.qualiOutGrace+1); assert(not cmd.rulePit,'out-lap')
 a.lap=6; F.tick(e,f,0.2); assert(not cmd.rulePit,'flying lap')
 -- Tour lancé 6 fautif : refait.
 e.quali.cars[2].faultyLap=6
 a.lap=7; F.tick(e,f,0.2)
 assert(not cmd.rulePit and count(e,'tour rapide refait (tour fautif)')==1,'faulty lap redone')
 a.lap=8; F.tick(e,f,0.2); assert(cmd.rulePit,'clean lap: in-lap')
end
-- Décision 7 et audit : préréglages et masquage.
tests.PRESETS_RULES_162B=function()
 local course=C.preset('Course','C',{})
 for _,k in ipairs({'passAid','rearAwareness','sanContact','startRealism','dynamicPersona','fineInputs','wearPace','strategySmart'}) do assert(course[k]==true,'Realistic race: '..k) end
 assert(course.raceStart=='standing' and course.sanPlayerContact==false,'standing start and player contacts never imposed')
 local endu=C.preset('Endurance','C',{})
 assert(endu.classNuance==true and endu.passAid==true,'Multi-class endurance: lapped cars and classes nuanced')
 assert(C.preset('Course','C',{}).classNuance==false,'Realistic race: classNuance left to the player')
 local enduJ=C.preset('Endurance','J',{})
 assert(enduJ.yieldSide~='right' and enduJ.overtakeSide~='left','Multi-class endurance on a track day: no Nordschleife base everywhere')
 assert(C.preset('Circuit','J',{}).outLapEnabled and C.preset('Nordschleife','J',{}).outLapEnabled,'track-day warm-up lap')
 -- Décision 1 (pour R1) : choix « garder sa ligne », libellé propre (la valeur line a un autre sens ailleurs).
 local L=require('src/lang'); local LE=require('src/lang_en')
 assert(L.choiceLong.yieldSide.line~=L.choices.line and LE.choiceLong.yieldSide.line~=LE.choices.line and L.choiceShort.yieldSide.line,'own label for keep line')
 assert(C.preset('Circuit','J',{}).yieldSide=='line' and C.preset('Nordschleife','J',{}).yieldSide=='right','Journée circuit: keep line; Touristenfahrten: keep right')
 assert(C.hidden('P','defenseEnabled') and C.hidden('Q','defenseEnabled') and C.hidden('J','defenseEnabled') and not C.hidden('C','defenseEnabled'),'defence shown in the race only')
end
return tests
