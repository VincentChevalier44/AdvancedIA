-- 2.0.5 f (Beta 2.0.5, sens latéral seulement) : verrous de la mesure du sens latéral repris de la relecture
-- adversariale du 18 novembre (tests/review205c.lua, review205d.lua et review205e.lua de l'arbre de la relecture),
-- textes inchangés ; plus, ajouté sur décision du pilote, le verrou des passages remis à zéro à une session relancée
-- (LOCK_RUNS_RESET_RESTART_205) ; 2.0.5 g (relecture, tour 5) : côté du déboîtement en sortie de virage
-- (LOCK_CORNER_EXIT_PASS_SIDE_205), mesure lâchée hors piste (LOCK_SIGN_OFFTRACK_205), journal du lancement jamais
-- écrasé (LOCK_JOURNAL_LAUNCH_HELD_205) ; 2.0.5 h (relecture, tour 6, Q) : journal vidé comme avant sans io.move
-- (LOCK_JOURNAL_NO_MOVE_205 ; les deux verrous de « Relancer » du tour 6 sont des cas d'intégration). Noms terminés
-- par _205. Chargé par tests/extended.lua. Chaque verrou échoue sur la version d'avant (ou sur son mutant) et passe
-- après.
local F=require('tests/fixture')
local C=require('src/config')
local E=require('src/engine')
local K=C.K
local tests={}

-- Mesure du sens latéral (src/calibration.lua) : banc à trois voitures (1 = joueur loin derrière, 2 = voiture mesurée,
-- 3 = voiture repère 120 m devant), écart à la trajectoire lu par une fonction (ici x, la trajectoire = x).
do
 local Calibration=require('src/calibration')
 local Caps=require('src/caps')
 local function globals(offset,side,provisional)
  local g=C.validateGlobals({schemaVersion=3,dataRevision=24,presetsUsed=true,offsetSign=offset,sideSign=side}); g.signProvisional=provisional==true; return g
 end
 local function bench()
  local _,f=F.scene('J',3)
  local writes={}
  local cap=Caps.new({present=function() return true end,write=function(name,index,value) writes[#writes+1]=name..':'..index..':'..tostring(value); return true end})
  return f,cap,Calibration.new(),writes
 end
 local function own(a) return a.x end
 local function start(c,f,cap,g,t0)
  F.place(f,1,-1000,100); F.place(f,2,0,180); F.place(f,3,120,180)
  for i=1,3 do local a=f.cars[i]; a.sideDot=-1; a.lx=0; a.lz=1; a.cornerYaw=1; a.pit=false; a.offtrack=false end
  Calibration.step(c,f,cap,g,t0,own); assert(c.index==2,'measurement started ('..tostring(c.phase)..')')
 end
 -- Le sens est jugé sur le déplacement de la voiture mesurée elle-même (écart à la trajectoire), plus sur le cap de la
 -- voiture de référence (avant : une référence qui tournait de 1 degré inversait le sens mesuré).
 tests.LOCK_SIGN_OWN_MOVE_205=function()
  local f,cap,c=bench(); local g=globals(-1,-1,true)
  start(c,f,cap,g,0)
  local b=f.cars[3]; local th=math.rad(1)
  f.cars[2].x=-1.0; b.lx=math.sin(th); b.lz=math.cos(th); b.cornerYaw=0.988
  Calibration.step(c,f,cap,g,3.1,own)
  assert(c.refused==nil and g.offsetSign==-1 and g.sideSign==-1 and g.signProvisional==false and c.confirmed==true and c.phase=='ready',
   'a 1 m move to the left confirms -1 / -1 whatever the reference car does: refused='..tostring(c.refused)..' phase='..c.phase)
  -- Un vrai déplacement à droite reste une mesure contraire (trois de suite toujours exigées).
  f,cap,c=bench(); g=globals(-1,-1,true)
  start(c,f,cap,g,0); f.cars[2].x=0.8; Calibration.step(c,f,cap,g,3.1,own)
  assert(c.refused=='1 / -1' and c.refusedCount==1 and g.offsetSign==-1 and g.signProvisional==true,'real contrary move: counted, not kept')
  -- Sans la lecture (ancienne version de CSP) : voiture de référence, comme avant.
  f,cap,c=bench(); g=globals(0,0,false)
  F.place(f,1,-1000,100); F.place(f,2,0,180); F.place(f,3,120,180); for i=1,3 do f.cars[i].sideDot=-1 end
  Calibration.step(c,f,cap,g,0); f.cars[2].x=-0.8; Calibration.step(c,f,cap,g,3.1)
  assert(g.offsetSign==-1 and c.phase=='ready','fallback on the reference car')
 end
 -- Une mesure qui n'a pas pu être conclue à temps n'est jamais conclue plus tard (voiture sortie puis revenue ailleurs).
 tests.LOCK_SIGN_STALE_205=function()
  local f,cap,c=bench(); local g=globals(0,0,false)
  start(c,f,cap,g,0)
  f.cars[2].offtrack=true
  for t=1,20 do Calibration.step(c,f,cap,g,t,own) end
  f.cars[2].offtrack=false; f.cars[2].x=3
  local b=f.cars[3]; b.x=900; b.z=1500; b.lx=1; b.lz=0
  Calibration.step(c,f,cap,g,21,own)
  assert(g.offsetSign==0 and g.sideSign==0 and c.phase=='aborted' and c.index==0,'stale measurement dropped: '..g.offsetSign..' '..c.phase..' '..c.index)
 end
 -- La voiture mesurée entre dans la voie des stands : mesure abandonnée aussitôt (l'applicateur y rend le décalage).
 tests.LOCK_SIGN_PIT_205=function()
  local f,cap,c=bench(); local g=globals(-1,-1,true)
  start(c,f,cap,g,0)
  f.cars[2].pit=true
  Calibration.step(c,f,cap,g,1,own)
  assert(c.index==0 and c.phase=='aborted' and g.signProvisional==true,'dropped in the pit lane: '..c.index..' '..c.phase)
  start(c,f,cap,g,100); f.cars[2].pit=true
  assert(Calibration.cancel(c,f,cap,g,own)==true and c.index==0,'cancel does not wait for the pit stop to end')
 end
 -- 2.0.5 g (relecture, tour 5, N) : voiture mesurée sortie de la piste pendant la mesure (à 1 s, écart de 3 m à droite),
 -- revenue en piste 0,5 s plus tard encore à 0,8 m à droite : mesure jamais conclue, même quand la voiture revient
 -- avant la fin des trois secondes ; avant : conclue à 3 s avec l'écart de la sortie de piste (sens 1 / -1 retenu, ou
 -- compté comme mesure contraire quand -1 / -1 est provisoire).
 tests.LOCK_SIGN_OFFTRACK_205=function()
  local f,cap,c=bench(); local g=globals(0,0,false)
  start(c,f,cap,g,0)
  for t=0.1,0.9,0.1 do Calibration.step(c,f,cap,g,t,own) end
  f.cars[2].offtrack=true; f.cars[2].x=3
  Calibration.step(c,f,cap,g,1.0,own); Calibration.step(c,f,cap,g,1.2,own)
  assert(c.index==2,'scene: measurement still running while off the track')
  f.cars[2].offtrack=false; f.cars[2].x=0.8
  for t=1.5,2.9,0.1 do Calibration.step(c,f,cap,g,t,own) end
  Calibration.step(c,f,cap,g,3.05,own)
  assert(g.offsetSign==0 and g.sideSign==0 and c.phase~='ready','measurement with a trip off the track concluded: '..g.offsetSign..' / '..g.sideSign..' phase '..c.phase)
  -- -1 / -1 provisoire : la sortie de piste n'est pas comptée comme une mesure contraire.
  f,cap,c=bench(); g=globals(-1,-1,true)
  start(c,f,cap,g,0)
  f.cars[2].offtrack=true; f.cars[2].x=3; Calibration.step(c,f,cap,g,1.0,own)
  f.cars[2].offtrack=false; f.cars[2].x=0.8; Calibration.step(c,f,cap,g,1.5,own)
  Calibration.step(c,f,cap,g,3.05,own)
  assert(c.refused==nil and (c.contra or 0)==0,'trip off the track counted as a contrary measurement: '..tostring(c.refused)..' '..tostring(c.contra))
 end
end

-- Mesure du sens latéral (src/calibration.lua) : quand la mesure rend elle-même son décalage (fin de la mesure en
-- piste, annulation en piste), elle note la voiture (restoredIndex) : le fichier d'entrée remet à zéro le suivi de
-- l'applicateur (cas d'intégration LOCK_SIGN_MEASURE_RECORD_205). Dans la voie des stands rien n'est noté : le décalage
-- y est rendu par l'applicateur (laneRelease), qui a besoin de son suivi.
tests.LOCK_SIGN_MEASURE_RESTORED_205=function()
 local Calibration=require('src/calibration'); local Caps=require('src/caps')
 local function bench()
  local _,f=F.scene('J',3); local writes={}
  local cap=Caps.new({present=function() return true end,write=function(name,index,value) writes[#writes+1]=name..':'..index..':'..tostring(value); return true end})
  local g=C.validateGlobals({schemaVersion=3,dataRevision=24,presetsUsed=true,offsetSign=0,sideSign=0}); g.signProvisional=false
  local c=Calibration.new()
  F.place(f,1,-1000,100); F.place(f,2,0,180); F.place(f,3,120,180)
  for i=1,3 do local a=f.cars[i]; a.sideDot=-1; a.lx=0; a.lz=1; a.cornerYaw=1; a.pit=false; a.offtrack=false end
  Calibration.step(c,f,cap,g,0); assert(c.index==2 and c.restoredIndex==nil,'scene: measurement started ('..tostring(c.phase)..')')
  return f,cap,c,g,writes
 end
 -- Fin de la mesure en piste, sans conclusion (la voiture n'a pas bougé) : décalage rendu par la mesure, voiture notée.
 local f,cap,c,g,writes=bench()
 Calibration.step(c,f,cap,g,K.calibrationTime+0.1)
 assert(c.index==0 and c.phase=='inconclusive' and g.offsetSign==0,'scene: measurement ended without a conclusion ('..tostring(c.phase)..')')
 assert(writes[#writes]=='offset:1:0','scene: offset given back by the measurement ('..tostring(writes[#writes])..')')
 assert(c.restoredIndex==2,'measured car noted when the measurement gives its offset back: '..tostring(c.restoredIndex))
 -- Annulation en piste : de même.
 f,cap,c,g,writes=bench()
 assert(Calibration.cancel(c,f,cap,g)==true and c.index==0 and writes[#writes]=='offset:1:0','scene: cancelled on the track, offset given back')
 assert(c.restoredIndex==2,'measured car noted at a cancel on the track: '..tostring(c.restoredIndex))
 -- Voie des stands : mesure abandonnée, rien de rendu par la mesure, rien de noté.
 f,cap,c,g,writes=bench(); local n=#writes
 f.cars[2].pit=true; Calibration.step(c,f,cap,g,1)
 assert(c.index==0 and #writes==n and c.restoredIndex==nil,'pit lane: offset left to the applier, nothing noted')
 f,cap,c,g,writes=bench(); n=#writes
 f.cars[2].pit=true
 assert(Calibration.cancel(c,f,cap,g)==true and #writes==n and c.restoredIndex==nil,'cancel in the pit lane: nothing noted')
end

-- Journal : ligne du sens provisoire sans la raison « installation neuve » (elle est écrite aussi après une réparation
-- ou une nouvelle mesure demandée) ; traduction sans mot français.
tests.LOCK_SIGN_PROVISIONAL_LINE_205=function()
 local J=require('src/journal')
 local e,f=F.scene('Q',3)
 e.g.offsetSign=-1; e.g.sideSign=-1; e.g.signProvisional=true; E.changed(e)
 f.type=3; f.session=1; F.tick(e,f,0.1) -- nouvelle session, nouveau profil : la ligne du sens latéral est réécrite
 local found
 for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('sens lateral: -1 / -1',1,true) then found=r.message end end
 assert(found=='sens lateral: -1 / -1 provisoire (convention d AC, pas encore confirme par la mesure)','line written while the direction is provisional: '..tostring(found))
 local _,rule=J.english(found,true); local text=J.english(found)
 assert(rule~=nil and text=='lateral direction: -1 / -1 provisional (AC convention, not yet confirmed by the measurement)','English rule: '..tostring(text))
 assert(not text:find('new installation',1,true) and not text:find('never measured',1,true),'no wrong reason')
end

-- Essais et qualifications (src/runs.lua) : session relancée par le joueur (même indice ; l'hôte remet engine.session à
-- -1, AdvancedIA.lua session()). Une IA arrivée à son stand en fin de session sans assez de temps pour un passage y est
-- gardée (stay) ; avant : cet état survivait à la relance et l'IA restait à son stand toute la nouvelle session (relecture
-- du 18 novembre, deuxième tour, relecteur H).
do
 local function tyres(a)
  a.id='lotus_exos'; a.tyresKnown=true; a.compoundIndex=1
  a.tyreNames={[0]='H',[1]='M',[2]='S',[3]='SS'}; a.tyreLongNames={[0]='Slick Hard',[1]='Slick Medium',[2]='Slick Soft',[3]='Slick SuperSoft'}
  a.dryCompounds={[0]=true,[1]=true,[2]=true,[3]=true}
  a.fuel=40; a.maxFuel=60; a.fuelPerLap=2.5; a.lastLap=90; a.bestLap=88
 end
 tests.LOCK_RUNS_RESET_RESTART_205=function()
  local e,f=F.scene('Q',3)
  e.profiles.Q.qualiRuns=true; E.changed(e)
  local a=f.cars[2]; tyres(a)
  F.tick(e,f,0.2)
  f.left=60 -- une minute avant le drapeau : aucun passage ne tient (tour de 90 s)
  a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0
  F.tick(e,f,0.5)
  assert(e.runs.cars[2].stay==true,'scene: stay expected at the end of the session')
  assert(e.commands[2].pitHold==true,'scene: held in its box at the end of the session')
  -- Session relancée par le joueur (même indice) : comme AdvancedIA.lua session().
  E.reset(e,e.time,true); e.session=-1
  f.left=1000; f.time=0; a.lap=0; a.lastLap=0; a.bestLap=0
  F.tick(e,f,5)
  local c=e.runs.cars[2]
  assert(c.stay~=true and e.commands[2].pitHold~=true,'stay kept across the restart: stay='..tostring(c.stay)..' lanePlanned='..tostring(c.lanePlanned)..' phase='..tostring(c.phase)..' pitHold='..tostring(e.commands[2].pitHold))
  F.tick(e,f,200)
  assert(e.runs.cars[2].stay~=true,'AI held in its box for the whole new session')
 end
end

-- Relecture du 18 novembre, tour 2 (constat I1) : une voiture rendue au jeu (niveau et agressivité d'origine écrits)
-- puis reprise dans la même image (mesure du sens latéral, sonde du niveau) garde ses vraies valeurs d'origine ;
-- avant : l'image du moment portait encore les valeurs de l'app, prises pour celles d'origine.
tests.LOCK_RESTORE_FRAME_ORIGINALS_205=function()
 local A=require('src/applier')
 local host=require('tests/host').create(true); local e,f=F.scene('J'); local a=A.new(); assert(A.access(a))
 local car=f.cars[2]; local s=a.cars[2]
 s.owned=true; s.id=car.identity or car.id; s.originalLevel=0.964; s.originalAggression=0.38; s.level=1.0074; s.aggression=0.7643
 car.aiLevel=1.0074; car.aiAggression=0.7643
 A.restore(a,f,false,1)
 assert(not s.owned,'car given back')
 assert(math.abs(car.aiLevel-0.964)<1e-9 and math.abs(car.aiAggression-0.38)<1e-9,string.format('frame keeps the app values after the restore: level %.4f, aggression %.4f',car.aiLevel,car.aiAggression))
 -- Reprise dans la même image, comme la mesure du sens latéral (AdvancedIA.lua) : les valeurs d'origine sont les vraies.
 if not s.owned then s.owned=true; s.originalLevel=car.aiLevel; s.originalAggression=car.aiAggression end
 assert(math.abs(s.originalLevel-0.964)<1e-9 and math.abs(s.originalAggression-0.38)<1e-9,'claimed again in the same frame: true originals kept')
 -- Voiture rendue dans la voie des stands (laneRelease, restitution des seules voitures en attente) : même règle.
 local e2,f2=F.scene('J'); local b=A.new(); assert(A.access(b)); local c2=f2.cars[2]; local s2=b.cars[2]
 s2.owned=true; s2.id=c2.identity or c2.id; s2.originalLevel=0.9; s2.originalAggression=0.4; s2.level=1.0; s2.aggression=0.8; s2.offset=0; s2.offsetReset=true
 c2.aiLevel=1.0; c2.aiAggression=0.8; c2.pit=true
 A.restore(b,f2,true,5)
 assert(math.abs(c2.aiLevel-0.9)<1e-9 and math.abs(c2.aiAggression-0.4)<1e-9,string.format('pit lane: frame keeps the app values: level %.4f, aggression %.4f',c2.aiLevel,c2.aiAggression))
end

-- 2.0.5 g (relecture, tour 5, O) : déboîtement en sortie de virage (K.exitPassEnabled) et sur une erreur devant : côté
-- opposé à la cible, aussi quand la cible n'est décalée que de 0,3 à 1 m et qu'elle n'occupe pas encore ce côté (hors de
-- portée de l'occupation) ; repère de la perception : cible à lat<0 (côté interne +1) -> déboîtement vers -1. Avant : le
-- côté de la cible (LOCK_CORNER_EXIT_PASS_164 ne passait que par les replis pullOutTargetLat et occupation).
do
 local function scene(x,gap,sa,sign)
  local e,f=F.scene('C',4); local p=e.profiles.C
  if sign then e.g.offsetSign=sign; if e.runtimeG then e.runtimeG.offsetSign=sign end end
  p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.passAid=false; p.startDelay=0; p.startRelax=0
  E.changed(e); if sign then e.g.offsetSign=sign; if e.runtimeG then e.runtimeG.offsetSign=sign end end
  F.tick(e,f,0.2)
  F.place(f,1,-5000,100); F.place(f,4,5000,100)
  local s=e.states[2]
  s.state='OVT_ARM'; s.reason='pass'; s.since=e.time; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=gap; s.passName='Cible'
  s.abortSlow=0; s.passStall=0; s.passAlongside=false; s.passProgRef=gap; s.passProgTime=0; s.lastPassTarget=3; s.nextPerception=0
  local t=0; local pulled=false
  while t<1.5 do
   local yaw=t<0.5 and 1.5 or 0
   f.cars[2].yawRate=yaw; f.cars[3].yawRate=yaw
   F.place(f,2,0,150+sa,0); F.place(f,3,gap+4.4,150,x); s.nextPerception=0
   e.fl.points={(f.cars[2].spline+2000/f.length)%1}; e.fl.count=1
   F.tick(e,f,1/60); t=t+1/60
   if s.state=='OVT_IN' then pulled=true; break end
  end
  return s,e,pulled
 end
 tests.LOCK_CORNER_EXIT_PASS_SIDE_205=function()
  local bad={}
  for _,sign in ipairs({1,-1}) do
   for _,c in ipairs({{0.6,14,16},{-0.6,14,16},{0.8,14,16},{-0.8,14,16},{0.6,10,31},{-0.6,10,31}}) do
    local x,gap,sa=c[1],c[2],c[3]
    local s,e,pulled=scene(x,gap,sa,sign)
    local want=x>0 and -1 or 1 -- x>0 : cible du côté perception lat<0 (interne +1) ; opposé : -1
    if not (pulled and (e.stats.exitPass or 0)>=1 and s.targetSide==want) then
     bad[#bad+1]=string.format('sign %+d, target x=%+.1f m, gap %d m, +%d km/h: pulled=%s side=%d (want %d)',sign,x,gap,sa,tostring(pulled),s.targetSide,want)
    end
   end
  end
  assert(#bad==0,'exit pass towards the target: '..table.concat(bad,' | '))
 end
end

-- 2.0.5 g (relecture, tour 5, N) : journal du lancement (src/applier.lua journalOpen) quand un ancien journal est tenu
-- ouvert par un autre programme (Windows : ni renommé ni remplacé ; io.move de CSP rend alors faux). Aucun journal
-- précédent n'est perdu : une place restée prise n'est jamais écrasée et le journal resté en place est poursuivi
-- (jamais vidé). Avant : .1 tenu ouvert -> journal précédent vidé ; .2 ou .3 tenu ouvert -> un journal écrasé.
do
 local A=require('src/applier')
 local function run(locked)
  local host=require('tests/host').create(true)
  local base=ac.getFolder(ac.FolderID.Logs)..'/AdvancedIA'
  local function list() local t={}; for path,v in pairs(host.files) do if path:sub(1,#base)==base and path:match('%.log$') then t[#t+1]=path:sub(#base+1)..'='..tostring(v):sub(1,8) end end; table.sort(t); return table.concat(t,' ') end
  host.files[base..'.log']='L0'; host.files[base..'.1.log']='L1'; host.files[base..'.2.log']='L2'; host.files[base..'.3.log']='L3'
  local move=io.move; local held=base..'.'..locked..'.log'
  io.move=function(from,to,overwrite) if from==held or to==held then return false end return move(from,to,overwrite) end
  local d=A.new(); d.note=function() end
  local ok,err=pcall(function() assert(A.journalOpen(d)); assert(A.journalWrite(d,'now\n')) end)
  io.move=move; assert(ok,err)
  local contents={}; local written=false
  for path,v in pairs(host.files) do if path:sub(1,#base)==base then contents[v:sub(1,2)]=true; written=written or v:find('now',1,true)~=nil end end
  local wanted=locked==3 and {'L0','L1','L2','L3'} or {'L0','L1','L2'}
  for _,want in ipairs(wanted) do assert(contents[want],'previous log '..want..' lost at launch (held open: .'..locked..'.log): '..list()) end
  assert(written,'new launch written: '..list())
 end
 tests.LOCK_JOURNAL_LAUNCH_HELD_205=function() run(1); run(2); run(3) end
end

-- 2.0.5 h (relecture, tour 6, Q) : journal du lancement sur un CSP sans io.move (aucun décalage possible) : le journal
-- précédent est vidé comme avant, jamais poursuivi (poursuivi, il atteindrait pour de bon la limite de 4 Mo et
-- couperait le journal de tous les lancements suivants).
tests.LOCK_JOURNAL_NO_MOVE_205=function()
 local A=require('src/applier')
 local host=require('tests/host').create(true)
 local base=ac.getFolder(ac.FolderID.Logs)..'/AdvancedIA'
 host.files[base..'.log']='OLD'
 local move=io.move; io.move=nil
 local d=A.new(); d.note=function() end
 local ok,err=pcall(function() assert(A.journalOpen(d)); assert(A.journalWrite(d,'now\n')) end)
 io.move=move; assert(ok,err)
 assert(host.files[base..'.log']=='now\n' and d.journalBytes==4,'without io.move the previous log is continued: '..tostring(host.files[base..'.log'])..' bytes '..tostring(d.journalBytes))
end

return tests
