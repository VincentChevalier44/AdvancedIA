-- Beta 1.60, lot 3 (essais du pilote du 11 novembre) : passage franc sur une cession accordée ; tours de chauffe et de
-- refroidissement nettement plus lents en essais et qualifications, voiture lancée vue plus tôt. Noms terminés par
-- _160W. Chargé par tests/extended.lua. Les scènes tournent avec le sens latéral du jeu (-1 / -1) et avec +1 / +1.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Q=require('src/quali')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function learned(e,i,kmh)
 local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=kmh/3.6 end; s.paceMean=kmh/3.6
end
-- Voiture o qui cède à la voiture to, tenue dans cet état (le banc ne déplace pas les voitures).
local function yields(e,o,to,offset,side)
 o.state='YIELD_HOLD'; o.target=to; o.targetSide=side or 1; o.followers[to]=true; o.yieldStart=e.time; o.holdUntil=e.time+60; o.yieldDetection=100; o.yieldMargin=5
 if offset then o.offset=offset*(side or 1); o.base=0 end
end

-- Constantes du lot.
tests.K_160W=function()
 assert(K.frankOffM==1 and K.frankClear==0.4 and K.frankLevel==0.02 and K.frankMax==8 and K.frankDeltaKmh==30 and K.frankLiftGap==20
  and K.frankThirdGap==25 and K.frankYieldLevel==0.06 and K.frankYieldExtra==15)
 assert(K.qualiOutLevel==0.12 and K.qualiOutRamp==3 and K.qualiYieldLead==6 and K.qualiCoolLevel==0.18)
 assert(K.frankDeltaKmh>K.yieldPassDeltaKmh,'frank lift deeper than the ordinary one')
end

-- Passage franc : cible qui cède à cette IA et sortie de la trajectoire d'au moins K.frankOffM m : la tentative part sans
-- délai de confirmation, du côté opposé à la cession ; cible encore sur la trajectoire : délais d'avant.
tests.FRANK_START_160W=function()
 local function run(sign,offset)
  local e,f=F.scene('P',3); e.g.offsetSign=sign; e.g.sideSign=sign
  e.profiles.P.startDelay=0; e.profiles.P.startRelax=0; e.profiles.P.personalLineJitter=0; E.changed(e)
  for i=1,3 do f.cars[i].sideDot=sign end
  F.place(f,1,-5000,100); F.place(f,2,0,150); F.place(f,3,10+4.4,150); F.tick(e,f,0.2)
  local s,o=e.states[2],e.states[3]; local t=0
  while t<3 do
   yields(e,o,2,offset,1); learned(e,2,150); learned(e,3,150)
   F.place(f,2,0,150); F.place(f,3,10+4.4,150); s.nextPerception=0
   F.tick(e,f,1/60); t=t+1/60
   if F.passing(s.state) then return t,s,e end
  end
  return math.huge,s,e
 end
 for _,sign in ipairs({-1,1}) do
  -- 0,3 de 6 m : 1,8 m hors trajectoire.
  local t,s,e=run(sign,0.3)
  assert(t<=0.2,'sign '..sign..': frank pass starts at once ('..t..' s)')
  assert(s.state=='OVT_IN' and s.target==3 and s.targetSide==-1,'sign '..sign..': straight into the pass, on the side opposite to the yield: '..tostring(s.state)..' '..tostring(s.targetSide))
  -- 0,1 de 6 m : 0,6 m, encore sur la trajectoire : confirmation d'avant (invitation K.inviteTime puis confirmTime).
  local late=run(sign,0.1)
  assert(late>=K.inviteTime and late<math.huge,'sign '..sign..': target still on the line: the usual delays ('..late..' s)')
 end
end

-- Passage franc en cours : une ligne et un compte par tentative ; gain de niveau borné dans le temps.
tests.FRANK_BONUS_160W=function()
 local function run(offset,seconds)
  local e,f=F.scene('P',3); e.g.offsetSign=-1; e.g.sideSign=-1
  e.profiles.P.startDelay=0; e.profiles.P.startRelax=0; e.profiles.P.personalLineJitter=0; E.changed(e)
  for i=1,3 do f.cars[i].sideDot=-1 end
  F.place(f,1,-5000,100); F.place(f,2,0,150); F.place(f,3,10+4.4,150); F.tick(e,f,0.2)
  local s,o=e.states[2],e.states[3]; local t=0
  while t<seconds do
   yields(e,o,2,offset,1); learned(e,2,150); learned(e,3,150)
   F.place(f,2,0,150); F.place(f,3,10+4.4,150); s.nextPerception=0
   F.tick(e,f,1/60); t=t+1/60
  end
  return e,s
 end
 local e,s=run(0.3,2)
 assert(F.passing(s.state) and s.frankFor==3,'frank pass running: '..tostring(s.state))
 assert(count(e,'passage franc: Driver_2 -> Driver_3')==1 and (e.stats.frankPass or 0)==1,'one line, one count per attempt: '..count(e,'passage franc:'))
 -- Ligne de suivi : toutes les K.frankTracePeriod s, jamais à chaque image.
 local traces=count(e,'suivi du depassement: Driver_2 -> Driver_3 | ecart 10 m')
 assert(traces>=1 and traces<=2,'tracking line every '..K.frankTracePeriod..' s: '..traces)
 local with=e.commands[2].level
 local e0,s0=run(0.1,2)
 assert(count(e0,'passage franc:')==0 and (e0.stats.frankPass or 0)==0 and s0.frankFor==nil,'target on the line: no frank pass')
 local without=e0.commands[2].level
 assert(with>without*(1+K.frankLevel*0.5),'bounded level gain while it lasts: '..with..' / '..without)
 -- Après K.frankMax s : gain rendu (niveau lissé revenu à celui d'une tentative ordinaire).
 local e2,s2=run(0.3,K.frankMax+4)
 if F.passing(s2.state) then assert(e2.commands[2].level<without*(1+K.frankLevel*0.5),'gain given back after '..K.frankMax..' s: '..e2.commands[2].level) end
 assert((e2.stats.frankPass or 0)<=2,'never one count per frame')
end

-- Voiture qui cède, sortie de la trajectoire, attaquant engagé à moins de K.frankLiftGap m : lever de pied franc
-- (K.frankDeltaKmh sous lui) ; attaquant pas engagé, ou autre voiture collée dans sa file : lever de pied d'avant.
tests.FRANK_LIFT_160W=function()
 local function run(profile,committed,third,blue)
  local e,f=F.scene(profile,4); e.g.offsetSign=-1; e.g.sideSign=-1; E.changed(e)
  for i=1,4 do f.cars[i].sideDot=-1 end
  local s,fs=e.states[2],e.states[3]; local start=e.time-1; local lowest=math.huge
  -- Allure propre de la voiture qui cède : 200 km/h ; attaquant à 170 : la borne « sous l'attaquant » est la plus basse.
  learned(e,2,200)
  for _=1,6*60 do
   s.state='YIELD_HOLD'; s.target=3; s.targetSide=1; s.followers[3]=true; s.yieldStart=start; s.holdUntil=e.time+60; s.yieldDetection=100; s.yieldMargin=5
   s.yieldBlue=blue==true; s.offset=0.3; s.base=0
   if not committed then fs.state='DRIVE'; fs.target=0; fs.restUntil=e.time+10 end
   if committed then
    fs.state='OVT_IN'; fs.target=2; fs.targetSide=-1; fs.passStartAt=e.time; fs.passMinGap=10; fs.passName='x'; fs.passProgRef=10; fs.passProgTime=0; fs.abortSlow=0; fs.passStall=0; fs.lastPassTarget=2
   end
   local cap=e.commands[2].speedLimit or K.unlimitedSpeed
   local v=math.min(170,cap)
   F.place(f,1,-5000,0); F.place(f,2,0,v); F.place(f,3,-14.4,170,-2.5)
   if third then F.place(f,4,-19.4,v) else F.place(f,4,3000,100) end
   s.nextPerception=0
   F.tick(e,f,1/60)
   lowest=math.min(lowest,e.commands[2].speedLimit or K.unlimitedSpeed)
  end
  return lowest,e,s
 end
 local lowest,e,s=run('P',true,false)
 assert(lowest<=170-K.frankDeltaKmh+0.5 and lowest>=170-K.frankDeltaKmh-0.5,'frank lift: '..K.frankDeltaKmh..' km/h under the passer: '..lowest)
 assert((e.stats.frankLift or 0)==1 and s.frankLift==true,'counted once per episode: '..tostring(e.stats.frankLift))
 lowest,e,s=run('P',false,false)
 assert(lowest>=170-K.yieldPassDeltaKmh-0.5 and not s.frankLift and (e.stats.frankLift or 0)==0,'follower not committed: the ordinary lift: '..lowest)
 lowest,e,s=run('P',true,true)
 assert(lowest>=170-K.yieldPassDeltaKmh-0.5 and not s.frankLift,'another car close behind in its lane: never the frank lift: '..lowest)
 -- Course : jamais pour une cession ordinaire ; cession prioritaire (drapeau bleu) : oui.
 lowest,e,s=run('C',true,false,false)
 assert(not s.frankLift and (e.stats.frankLift or 0)==0,'race, ordinary yield: no frank lift')
 lowest,e,s=run('C',true,false,true)
 -- Rampe de la course (K.trafficDecelKmh km/h par seconde) : la limite descend sous celle d'une cession ordinaire.
 assert(s.frankLift==true and lowest<170-K.yieldTopCut-5,'race, blue-flag yield: frank lift, deeper than the ordinary cap: '..lowest)
end

-- Tour de chauffe : essais et qualifications, tour de sortie d'une IA pilotée, niveau abaissé de K.qualiOutLevel
-- (rampe), rendu après la ligne ; jamais le joueur, jamais sans l'onglet Général, jamais hors tours lancés.
tests.QUALI_OUT_LAP_LEVEL_160W=function()
 local function scene(profile,general,traffic)
  local e,f=F.scene(profile,3); e.profiles[profile].qualiTraffic=traffic~=false; e.profiles[profile].section_general=general~=false; E.changed(e)
  F.tick(e,f,1/60)
  return e,f
 end
 for _,profile in ipairs({'Q','P'}) do
  local e,f=scene(profile)
  local c=e.quali.cars[2]
  assert(c.out and not e.quali.push[2],profile..': first seen on the track: out-lap')
  -- Relecture du lot 3 (S10) : déjà en piste à la première vue (rechargement de l'app) : pas de baisse de niveau.
  assert(c.noDrop==true,'first seen on the track: classified without the level drop')
  F.tick(e,f,K.qualiOutRamp); assert(e.commands[2].levelScale>1-1e-6,profile..': no drop for a car first seen on the track: '..tostring(e.commands[2].levelScale))
  -- Vraie sortie des stands (ici posée à la main) : la baisse et sa rampe.
  for i=1,3 do local q=e.quali.cars[i]; if q then q.noDrop=false; q.exitAt=e.time end end
  F.tick(e,f,K.qualiOutRamp*0.5)
  local half=e.commands[2].levelScale
  assert(half<1 and half>1-K.qualiOutLevel+1e-6,profile..': ramp, not a step: '..tostring(half))
  F.tick(e,f,K.qualiOutRamp)
  assert(math.abs(e.commands[2].levelScale-(1-K.qualiOutLevel))<1e-6,profile..': out-lap level lowered: '..e.commands[2].levelScale)
  assert(count(e,'tour de chauffe:')==0 and (e.stats.qualiOut or 0)==2,profile..': counted once per car (two AI); no line for a car first seen on the track: '..tostring(e.stats.qualiOut))
  assert((e.commands[1].levelScale or 1)==1,profile..': never the player')
  -- Ligne franchie (après le délai de la ligne placée juste après la sortie) : tour lancé, niveau rendu en douceur.
  c.exitAt=e.time-K.qualiOutGrace-1
  f.cars[2].lap=f.cars[2].lap+1; F.tick(e,f,1/60)
  assert(not c.out and e.quali.push[2],profile..': flying lap after the line')
  local back=e.commands[2].levelScale
  assert(back<1 and back>1-K.qualiOutLevel-1e-6,profile..': level coming back, not at once: '..back)
  F.tick(e,f,K.qualiCoolRelease+0.1)
  assert((e.commands[2].levelScale or 1)==1,profile..': level back')
  -- Vraie sortie des stands : une ligne, une seule.
  f.cars[2].pit=true; F.tick(e,f,0.2); f.cars[2].pit=false; F.tick(e,f,K.qualiOutRamp+0.5)
  assert(count(e,'tour de chauffe: Driver_2 (niveau -12 %)')==1,profile..': one line per real pit exit: '..count(e,'tour de chauffe:'))
  assert(math.abs(e.commands[2].levelScale-(1-K.qualiOutLevel))<1e-6,profile..': lowered again on the new out-lap')
 end
 -- Finition 1.61 : vraie sortie des stands posée à la main, sinon la voiture vue en piste au départ n'a pas de baisse.
 local function exit(e) for i=1,3 do local q=e.quali.cars[i]; if q then q.noDrop=false; q.exitAt=e.time; q.out=true; q.outLap=0 end end end
 local e,f=scene('Q',false); exit(e); F.tick(e,f,K.qualiOutRamp+0.5)
 assert((e.commands[2].levelScale or 1)==1 and count(e,'tour de chauffe:')==0,'General tab off: the level is not commanded')
 e,f=scene('Q',true,false); exit(e); F.tick(e,f,K.qualiOutRamp+0.5)
 assert((e.commands[2].levelScale or 1)==1,'flying-lap priority off: nothing')
 e,f=scene('J'); F.tick(e,f,K.qualiOutRamp+0.5)
 assert((e.commands[2].levelScale or 1)==1,'track day: nothing')
 -- Voie des stands : jamais.
 e,f=scene('Q'); f.cars[2].pit=true; F.tick(e,f,K.qualiOutRamp+0.5)
 assert((e.commands[2].levelScale or 1)==1,'pit lane: nothing')
end

-- Voiture lancée vue K.qualiYieldLead s derrière une voiture qui ne l'est pas (avant : K.qualiYieldTime s) : la cession
-- commence avant son arrivée ; jamais l'inverse.
tests.QUALI_EARLY_YIELD_160W=function()
 local function scene(seconds)
  local e,f=F.scene('Q',3); e.profiles.Q.qualiTraffic=true; E.changed(e)
  F.tick(e,f,1/60)
  local c2,c3=e.quali.cars[2],e.quali.cars[3]
  c3.out=false; c3.cool=false
  local gap=seconds*200/3.6
  F.place(f,1,-5000,100); F.place(f,2,0,150); F.place(f,3,-gap-4.4,200)
  e.states[2].nextPerception=0; e.states[3].nextPerception=0
  F.tick(e,f,1/60)
  return e,f,c2,c3
 end
 local e,f=scene(5)
 assert(e.quali.push[3] and not e.quali.push[2],'car 3 on a flying lap, car 2 on its out-lap')
 local row=e.perception.rows[2]
 local seen=Q.follower(e.quali,e,2,row)
 assert(seen and seen.index==3,'flying car seen 5 s behind')
 assert(Q.follower(e.quali,e,3,e.perception.rows[3])==nil,'a flying car never looks for one')
 -- La cession commence (confirmation et réaction du pilote), du temps avant l'arrivée.
 local s=e.states[2]; local started
 for k=1,3*60 do
  local gap=5*200/3.6-k/60*(200-150)/3.6
  F.place(f,2,0,150); F.place(f,3,-gap-4.4,200); s.nextPerception=0
  F.tick(e,f,1/60)
  if F.yielding(s.state) then started=gap; break end
 end
 assert(started and s.yieldQuali and started>K.qualiYieldTime*200/3.6,'yield started before the old 3 s range: '..tostring(started)..' m')
 assert(s.yieldDetection>=200/3.6*K.qualiYieldLead*K.qualiYieldRange-1,'follower kept in sight over the whole approach: '..s.yieldDetection)
 local e2=scene(7)
 assert(Q.follower(e2.quali,e2,2,e2.perception.rows[2])==nil,'7 s behind: not yet')
end

-- Journal : tours des deux voitures à la fin d'une cession pendant les tours lancés ; rien hors essais et qualifications.
tests.YIELD_LAP_TAGS_160W=function()
 local e,f=F.scene('Q',3); e.profiles.Q.qualiTraffic=true; E.changed(e)
 F.tick(e,f,1/60)
 e.quali.cars[3].out=false
 F.place(f,1,-5000,100); F.place(f,2,0,150); F.place(f,3,-60,190)
 local s=e.states[2]
 for _=1,4*60 do F.place(f,2,0,150); F.place(f,3,-60,190); s.nextPerception=0; F.tick(e,f,1/60); if F.yielding(s.state) then break end end
 assert(F.yielding(s.state),'yield to the flying car')
 F.tick(e,f,1.5)
 F.place(f,3,60,190); s.nextPerception=0; F.tick(e,f,4)
 assert(count(e,'tours de la cession: Driver_2 (tour de sortie), suiveur Driver_3 (tour lance)')==1,'lap of both cars at the end of the yield')
end

-- Nom des pilotes : suffixe « (N%, N%) » de Content Manager (complet ou coupé) retiré, remplacé par le niveau et
-- l'agressivité que l'app applique ; nom sans suffixe laissé tel quel ; joueur et voiture non pilotée : nom seul.
tests.DRIVER_NAME_SUFFIX_160W=function()
 local S=require('src/snapshot')
 assert(S.stripName('G. Tsaknis (100%, 100%)')=='G. Tsaknis' and S.stripName('G. Tsaknis (95%,40%)')=='G. Tsaknis','complete suffix')
 assert(S.stripName('P. Müller (100%')=='P. Müller' and S.stripName('P. Müller (100%, 10')=='P. Müller' and S.stripName('P. Müller (1')=='P. Müller' and S.stripName('P. Müller (100%,')=='P. Müller','cut suffix')
 assert(S.stripName('Driver_2')==nil and S.stripName('Kimi (Iceman)')==nil and S.stripName('Team (7)')==nil and S.stripName('(100%, 100%)')==nil and S.stripName('A (B')==nil,'no suffix: the name is left alone')
 assert(K.nameRefresh==1)
 local e,f=F.scene('P',4)
 local function named(a,raw) a.rawName=raw; a.baseName=S.stripName(raw) or raw; a.cmSuffix=S.stripName(raw)~=nil; a.name=a.baseName end
 named(f.cars[1],'Me (100%, 100%)'); named(f.cars[2],'G. Tsaknis (100%, 100%)'); named(f.cars[3],'P. Müller (100%')
 F.tick(e,f,1/60)
 local function label(i,base) local cmd=e.commands[i]; return string.format('%s (%d%%, %d%%)',base,math.floor(cmd.level*100+0.5),math.floor(cmd.aggression*100+0.5)) end
 e.namesAt=-math.huge; E.names(e,f,e.time)
 assert(f.cars[2].name==label(2,'G. Tsaknis') and f.cars[3].name==label(3,'P. Müller'),'applied level and aggression: '..f.cars[2].name..' / '..f.cars[3].name)
 assert(f.cars[1].name=='Me','player: the name alone')
 assert(f.cars[4].name=='Driver_4' and f.cars[4].cmSuffix==nil,'name without the suffix: untouched')
 -- Valeurs qui changent : au plus une mise à jour par K.nameRefresh s.
 e.commands[2].level=0.84; e.commands[2].aggression=0.39
 E.names(e,f,e.time+K.nameRefresh*0.5)
 assert(f.cars[2].name~='G. Tsaknis (84%, 39%)','not refreshed before '..K.nameRefresh..' s')
 E.names(e,f,e.time+K.nameRefresh+0.01)
 assert(f.cars[2].name=='G. Tsaknis (84%, 39%)','refreshed: '..f.cars[2].name)
 -- Voiture que l'app ne pilote plus : nom seul.
 f.cars[2].control=false; e.namesAt=-math.huge; E.names(e,f,e.time+5)
 assert(f.cars[2].name=='G. Tsaknis','not driven by the app: the name alone')
 -- Journal : le nom affiché est celui des lignes.
 f.cars[2].control=true; e.namesAt=-math.huge; E.names(e,f,e.time+7)
 assert(f.cars[2].name=='G. Tsaknis (84%, 39%)')
end

-- Lever de pied franc sans spirale : attaquant qui suit la vitesse de la voiture qui cède (l'IA d'AC garde son écart) :
-- la limite reste à K.frankDeltaKmh km/h sous l'allure libre de la voiture qui cède, jamais plus bas ; côtés opposés.
tests.FRANK_LIFT_NO_SPIRAL_160W=function()
 local e,f=F.scene('P',3); e.g.offsetSign=-1; e.g.sideSign=-1; E.changed(e)
 for i=1,3 do f.cars[i].sideDot=-1 end
 local s,fs=e.states[2],e.states[3]; local start=e.time-1; local lowest=math.huge
 -- Allure propre 150 km/h ; attaquant vu à 190 km/h au début, puis à la vitesse de la voiture qui cède.
 learned(e,2,150)
 for k=1,10*60 do
  s.state='YIELD_HOLD'; s.target=3; s.targetSide=1; s.followers[3]=true; s.yieldStart=start; s.holdUntil=e.time+60; s.yieldDetection=100; s.yieldMargin=5; s.offset=0.3; s.base=0
  fs.state='OVT_IN'; fs.target=2; fs.targetSide=-1; fs.passStartAt=e.time; fs.passMinGap=10; fs.passName='x'; fs.passProgRef=10; fs.passProgTime=0; fs.abortSlow=0; fs.passStall=0; fs.lastPassTarget=2
  local cap=e.commands[2].speedLimit or K.unlimitedSpeed
  local v=math.min(150,cap)
  F.place(f,1,-5000,0); F.place(f,2,0,v); F.place(f,3,-14.4,k<=30 and 190 or v,-2.5); s.nextPerception=0
  F.tick(e,f,1/60)
  lowest=math.min(lowest,e.commands[2].speedLimit or K.unlimitedSpeed)
 end
 assert(lowest<=150-K.frankDeltaKmh+0.5,'frank lift under its own usual pace even when the passer matches its speed: '..lowest)
 assert(lowest>=150-K.frankDeltaKmh-0.5,'never a spiral down: '..lowest)
end

-- Côtés : la cible s'écarte du côté que l'attaquant avait pris : l'attaquant change de côté ; côtés déjà opposés : rien.
tests.PASS_AWAY_FROM_YIELD_160W=function()
 for _,sign in ipairs({-1,1}) do
  for _,yieldTo in ipairs({1,-1}) do
   local e,f=F.scene('J',3); e.g.offsetSign=sign; e.g.sideSign=sign; e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
   for i=1,3 do f.cars[i].sideDot=sign end
   F.place(f,1,-5000,100); F.place(f,2,0,105); F.place(f,3,24.4,100)
   local s,o=e.states[2],e.states[3]
   s.state='OVT_IN'; s.reason='pass'; s.since=e.time; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=20; s.passName='Cible'
   s.abortSlow=0; s.passStall=0; s.passAlongside=false; s.passProgRef=20; s.passProgTime=0; s.lastPassTarget=3; s.nextPerception=0
   for _=1,30 do
    yields(e,o,2,0.3,yieldTo); F.place(f,2,0,105); F.place(f,3,24.4,100); s.nextPerception=0
    F.tick(e,f,1/60)
   end
   assert(F.passing(s.state),'still passing')
   assert(s.targetSide==-yieldTo,'sign '..sign..', yield to '..yieldTo..': the attacker takes the other side: '..s.targetSide)
   assert((e.stats.passAwaySide or 0)==(yieldTo==1 and 1 or 0),'counted once, only when it changed side: '..tostring(e.stats.passAwaySide))
   -- Relecture du lot 3 (S8) : cible qui cède sans avoir encore bougé : le côté pris est gardé.
   if yieldTo==1 then
    local e2,f2=F.scene('J',3); e2.g.offsetSign=sign; e2.g.sideSign=sign; e2.p.personalLineJitter=0; E.changed(e2); F.tick(e2,f2,0.2)
    for i=1,3 do f2.cars[i].sideDot=sign end
    F.place(f2,1,-5000,100); F.place(f2,2,0,105); F.place(f2,3,24.4,100)
    local s2,o2=e2.states[2],e2.states[3]
    s2.state='OVT_IN'; s2.reason='pass'; s2.since=e2.time; s2.target=3; s2.targetSide=1; s2.passStartAt=e2.time; s2.passMinGap=20; s2.passName='Cible'
    s2.abortSlow=0; s2.passStall=0; s2.passAlongside=false; s2.passProgRef=20; s2.passProgTime=0; s2.lastPassTarget=3; s2.nextPerception=0
    for _=1,30 do yields(e2,o2,2,nil,1); o2.offset=0; o2.base=0; F.place(f2,2,0,105); F.place(f2,3,24.4,100); s2.nextPerception=0; F.tick(e2,f2,1/60) end
    assert(s2.targetSide==1 and (e2.stats.passAwaySide or 0)==0,'sign '..sign..': the yielding car has not moved yet: side kept')
   end
  end
 end
end

return tests
