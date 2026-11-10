-- Beta 1.59 : relecture de la 1.58 (points A à G, 13, 15 à 17). Les nouveautés du groupe H ont leurs propres fichiers.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local K=C.K
local E=require('src/engine')
local Pits=require('src/pits')
local Incidents=require('src/incidents')
local A=require('src/applier')
local tests={}
local function logged(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- D : plan d'arrêt de SpotterEnginer (contrat v1), lecture et mode.
tests.SE_PITPLAN_PARSE_159=function()
 local p=E.parsePitPlan('v=1;lap=12;compound=-;state=planned;window=10-20;boxcalls=0;stamp=33.5')
 assert(p and p.state=='planned' and p.lap==12 and p.stamp==33.5,'valid plan read')
 assert(E.parsePitPlan('v=1;state=none;stamp=1').state=='none','none without a lap')
 assert(E.parsePitPlan('v=2;lap=12;state=planned;stamp=1')==nil,'other version ignored')
 assert(E.parsePitPlan('v=1;lap=0;state=planned;stamp=1')==nil and E.parsePitPlan('v=1;lap=1.5;state=boxnow;stamp=1')==nil,'bad lap')
 assert(E.parsePitPlan('v=1;lap=3;state=later;stamp=1')==nil and E.parsePitPlan('v=1;lap=3;state=planned')==nil,'bad state, no stamp')
 assert(E.parsePitPlan('v=1;lap=3;state=planned;stamp=1;x='..string.rep('a',K.sePlanBytes))==nil,'too long')
 assert(E.parsePitPlan(nil)==nil and E.parsePitPlan(12)==nil,'not a string')
end
tests.SE_PITPLAN_MODE_159=function()
 local e,f=F.scene('C',3)
 local player=f.cars[1]; player.lap=5
 e.pits.state='open'; e.pits.close=0.9; e.pits.csp=false; f.sessionLaps=20; f.timedRace=false
 e.sePlan={raw='v=1;lap=8;compound=-;state=planned;window=1-20;boxcalls=0;stamp=10'}
 assert(E.pitPlanMode(e,f,player,true,100)=='quiet','planned later: quiet')
 assert(E.pitPlanMode(e,f,player,false,101)==nil,'not due: our rules')
 assert(E.pitPlanMode(e,f,player,true,100+K.sePlanStale+1)==nil,'stale stamp: our rules')
 e.sePlan.raw='v=1;lap=8;state=planned;stamp=11'; assert(E.pitPlanMode(e,f,player,true,200)=='quiet','new stamp: fresh again')
 e.sePlan.raw='v=1;lap=20;state=planned;stamp=12'; assert(E.pitPlanMode(e,f,player,true,201)==nil,'plan lap after our window: our rules')
 e.sePlan.raw='v=1;lap=3;state=planned;stamp=13'; assert(E.pitPlanMode(e,f,player,true,202)==nil,'plan lap already passed: our rules')
 e.sePlan.raw='v=1;lap=6;state=boxnow;stamp=14'; assert(E.pitPlanMode(e,f,player,true,203)=='box','box now, window open')
 e.incidents.pitsClosed=true; assert(E.pitPlanMode(e,f,player,true,203.5)=='quiet','pits closed: never box now'); e.incidents.pitsClosed=false
 e.pits.state='pending'; assert(E.pitPlanMode(e,f,player,true,204)==nil,'box now outside the window: our rules'); e.pits.state='open'
 e.sePlan.raw='v=1;lap=6;state=done;stamp=15'; assert(E.pitPlanMode(e,f,player,true,205)==nil,'done while still due: our rules')
 -- Relecture : fin de fenêtre proche (toute fenêtre, chronométrée ou de CSP) : nos rappels reprennent.
 e.sePlan.raw='v=1;lap=8;state=planned;stamp=17'; e.pits.open=0.2; e.pits.close=0.9; e.pits.position=0.8
 assert(E.pitPlanMode(e,f,player,true,205.5)==nil,'late in the window: our rules'); e.pits.position=0.3
 assert(E.pitPlanMode(e,f,player,true,205.6)=='quiet','early in the window: the plan is followed')
 e.profile='Q'; e.sePlan.raw='v=1;lap=8;state=planned;stamp=16'; assert(E.pitPlanMode(e,f,player,true,206)==nil,'race only')
end
-- C : sélecteur des règles de course à l'accueil, verrouillé en course commencée.
tests.RULES_LOCKED_159=function()
 assert(C.rulesLocked('C',{started=true,finished=false}),'race running: locked')
 assert(not C.rulesLocked('C',{started=false,finished=false}) and not C.rulesLocked('C',{started=true,finished=true}),'before / after the race: free')
 assert(not C.rulesLocked('Q',{started=true,finished=false}),'qualifying: free')
end
-- B : SpotterEnginer 1.1.0 et 1.1.1 ne savent pas se mettre à jour seules.
tests.COMPANION_MANUAL_159=function()
 assert(A.parseCompanionUpdate('v=1;installed=1.1.1;latest=1.2.0;state=available').manual==true,'1.1.1: manual')
 assert(A.parseCompanionUpdate('v=1;installed=1.1.0;latest=1.2.0;state=available').manual==true,'1.1.0: manual')
 assert(not A.parseCompanionUpdate('v=1;installed=1.2.0;latest=1.3.0;state=available').manual,'1.2.0: its own window')
 assert(not A.parseCompanionUpdate('v=1;installed=1.1.1;state=uptodate').manual,'up to date: nothing')
end
-- A : case figée du jaune jamais montrée, toujours active.
tests.LIGHTS_YELLOW_HIDDEN_159=function()
 local G=require('src/groups')
 assert(G.hidden.lightsYellow,'hidden')
 for _,list in pairs(G) do if type(list)=='table' then for _,sub in ipairs(list) do if type(sub)=='table' and type(sub[2])=='table' then for _,k in ipairs(sub[2]) do assert(k~='lightsYellow','not in a subgroup') end end end end end
 local q=C.validate('C',C.defaults('C')); q.lightsYellow=false; q=C.validate('C',q); assert(q.lightsYellow==true,'always on')
end
-- E : Général coupé : ni répartition des IA ni sorties des stands étalées par l'app.
tests.GENERAL_GATES_SPAWN_159=function()
 local p=C.defaults('J'); p.section_general=true; p.spawnMode='track'; p.pitExitSpread=50
 local on=C.effective('J',p); assert(on.spawnMode=='track' and on.pitExitSpread==50,'general on: spawn kept ('..tostring(on.spawnMode)..')')
 p.section_general=false; local off=C.effective('J',p)
 assert(off.spawnMode=='native' and off.pitExitSpread==0,'general off: native spawn, no staggered exits')
end
-- E : derniers tours, au plus 20 % de la course, au moins un.
tests.FINAL_LAPS_SHARE_159=function()
 local D=require('src/director')
 assert(D.finalLapsFor({finalLaps=3},{sessionLaps=10,timedRace=false})==2,'10 laps: 2')
 assert(D.finalLapsFor({finalLaps=3},{sessionLaps=3,timedRace=false})==1,'3 laps: 1')
 assert(D.finalLapsFor({finalLaps=3},{sessionLaps=30,timedRace=false})==3,'30 laps: setting')
 assert(D.finalLapsFor({finalLaps=3},{sessionLaps=0,timedRace=true})==3,'timed race: setting')
 assert(D.finalLapsFor({finalLaps=3},{sessionLaps=0,timedRace=true,leaderLaps=5},{known=true,lapsLeft=5})==2,'timed race, laps left known (10 laps in all): 2')
end
-- E : point difficile après K.hotspotCount incidents à moins de K.hotspotMeters m, oublié après K.hotspotForget s.
tests.HOTSPOT_159=function()
 local t=Incidents.new(); local lines={}; t.note=function(level,text) lines[#lines+1]=text end
 local L=10000
 for k=1,K.hotspotCount-1 do Incidents.hotspotNote(t,0.5+k*0.001,L,100+k) end
 assert(not Incidents.nearHotspot(t,0.5,L,110),'two incidents: not yet')
 Incidents.hotspotNote(t,0.503,L,120)
 assert(Incidents.nearHotspot(t,0.5,L,121) and not Incidents.nearHotspot(t,0.6,L,121),'third: difficult spot, local')
 local n=0; for _,l in ipairs(lines) do if l:find('point difficile: ',1,true) then n=n+1 end end; assert(n==1,'logged once')
 Incidents.hotspotNote(t,0.502,L,130); n=0; for _,l in ipairs(lines) do if l:find('point difficile: ',1,true) then n=n+1 end end; assert(n==1,'same spot: no new line')
 assert(not Incidents.nearHotspot(t,0.5,L,130+K.hotspotForget+1),'forgotten after a calm period')
 local far=Incidents.new(); far.note=function() end
 for k=1,K.hotspotCount do Incidents.hotspotNote(far,0.5,L,k*(K.hotspotWindow+1)) end
 assert(not Incidents.nearHotspot(far,0.5,L,K.hotspotCount*(K.hotspotWindow+1)+1),'spread over time: no hotspot')
end
-- E : groupe d'incidents (deux voitures arrêtées à 50 m l'une de l'autre) : une seule annonce au joueur.
tests.YELLOW_CLUSTER_ONE_NOTICE_159=function()
 local function run(gap)
  local e,f=F.scene('J',3); F.place(f,1,-5000,150); F.place(f,2,900,0); F.place(f,3,900+gap,0)
  F.tick(e,f,10); assert(e.incidents.zoneCount>=2,'two zones')
  F.place(f,1,900-300,150); F.tick(e,f,1); F.place(f,1,900+gap-300,150); F.tick(e,f,1)
  return logged(e,'drapeau jaune au joueur: incident a ')
 end
 assert(run(50)==1,'cluster: one notice ('..run(50)..')')
 assert(run(3000)>=2,'far apart: two notices')
end
-- Relecture : double jaune pour une voiture lente en piste (jamais sous K.doubleFloorKmh km/h) ou à contresens ; jaune
-- simple pour une voiture qui roule encore à bonne allure.
tests.DOUBLE_YELLOW_FLOOR_159=function()
 local function zoneOf(kmh,setup)
  local e,f=F.scene('J',3); F.place(f,2,-4000,120); F.place(f,3,1000,0); F.tick(e,f,4)
  if setup then setup(e,f) end
  f.cars[3].kmh=kmh; f.cars[3].speed=kmh/3.6; F.tick(e,f,0.5)
  return e.incidents.cars[3]
 end
 assert(zoneOf(30).double,'30 km/h on track: double (floor)')
 assert(zoneOf(30,function(e) e.profiles.J.obstacleSpeedKmh=5; E.changed(e) end).double,'obstacle speed set low: the floor still holds')
 local c=zoneOf(0); assert(c.double,'stopped: double')
end
-- Relecture : dégagement hors piste tenu (pas d'incident neuf quand la lecture hors piste sautille), point difficile nourri
-- une fois par voiture et par arrêt.
tests.OFF_CLEAR_HELD_159=function()
 local e,f=F.scene('J',3); F.place(f,2,-4000,120)
 local car=F.place(f,3,1000,0,20); car.offtrack=true; car.wheelsOut=4; car.splineLat=20
 F.tick(e,f,C.K.offClearTime+2)
 local c=e.incidents.cars[3]; assert(c.dismissed and not c.incident,'cleared after 15 s')
 local n=logged(e,'incident: arret')
 for _=1,5 do car.offtrack=false; F.tick(e,f,0.2); car.offtrack=true; F.tick(e,f,0.3) end
 assert(logged(e,'incident: arret')==n and c.dismissed,'flicker: no new incident while still stopped')
end
-- Lignes nouvelles du journal traduites en anglais.
tests.JOURNAL_EN_159=function()
 local J=require('src/journal')
 for _,line in ipairs({'point difficile: 1200 m (3 incidents en 300 s au plus), prudence accrue pour les IA, aucun depassement commence',
  'incident ecarte: arretee hors piste, loin de la trajectoire depuis 15 s','regles de course: F1 (changement)',
  'course relancee: recapitulatif et place de depart remis a zero'}) do
  local en=J.english(line); assert(en and en~=line,'translated: '..line)
 end
end
-- F : passage de la voie servi seulement une fois arrêtée à l'emplacement (un effleurement de l'emplacement ne compte pas).
tests.PIT_LANE_FLICKER_159=function()
 local e,f=F.scene('C',3); local run={}; for k,v in pairs(e.run) do run[k]=v end
 run.mandatoryStops=1; run.pitWindowOpenPct=10; run.pitWindowClosePct=95; run.pitTyres=true; run.maxStintMin=0; run.minPitTime=0
 f.sessionLaps=10; f.leaderLaps=9; f.timedRace=false
 local t=Pits.new(); local cmds={}; for i=1,f.count do cmds[i]={} end
 local now=100
 local function step() now=now+0.5; Pits.update(t,f,cmds,run,'C',now,1,nil,false,nil,false) end
 step(); local a=f.cars[2]
 a.pit=true; a.kmh=60; step(); a.inPitBox=true; step(); a.inPitBox=false; step()
 assert(not cmds[2].laneServed,'box touched at speed: not served, the request stays')
 a.inPitBox=true; a.kmh=0; step(); a.inPitBox=false; a.kmh=40; step()
 assert(cmds[2].laneServed,'stopped in the box: served')
end
-- G : réglages sans effet dans la scène générique de tests/effectiveness.py : chacun change ce qu'il règle.
tests.SETTINGS_TARGETED_159=function()
 -- Fin de zone après l'incident (yellowAfter) : IA 30 m après une voiture arrêtée en piste.
 local function after(m)
  local e,f=F.scene('J',3); e.profiles.J.yellowAfter=m; E.changed(e)
  F.place(f,2,-4000,120); F.place(f,3,1000,0); F.tick(e,f,10)
  F.place(f,2,1030,60); e.states[2].nextPerception=0; F.tick(e,f,0.5)
  return e.states[2].yellow
 end
 assert(after(50) and not after(0),'yellowAfter: zone after the incident')
 -- VSC : temps de référence plus lent de vscDeltaPct.
 local function vsc(pct)
  local e,f=F.scene('C',3); e.profiles.C.neutralization='vsc'; e.profiles.C.vscDeltaPct=pct; E.changed(e)
  local s=e.states[2]; for b=1,#s.pace do s.pace[b]=150/3.6 end; s.paceCount=400; s.paceMean=150/3.6
  F.place(f,2,0,150); F.place(f,3,6000,0); F.tick(e,f,25)
  assert(e.incidents.neutral,'vsc on'); return e.commands[2].yellowLimit
 end
 assert(vsc(10)>vsc(80)*1.3,'vscDeltaPct: slower reference')
 -- Drapeau rouge : référence du delta du joueur (redDeltaPct).
 local Delta=require('src/delta')
 local function red(pct)
  local e,f=F.scene('C',3); e.profiles.C.redDeltaPct=pct; E.changed(e); F.tick(e,f,1/60)
  local s=e.states[1]; for b=1,#s.pace do s.pace[b]=150/3.6 end; s.paceCount=400; s.paceMean=150/3.6
  local inc={red=true,neutral=false,playerZone=false,playerInside=false}
  -- Allure du joueur connue (150 km/h) : la référence du drapeau rouge en dépend seule.
  local d=Delta.new(); local a=f.cars[1]; a.kmh=100; a.speed=100/3.6
  local pace=Delta.pace; Delta.pace=function() return 150/3.6 end
  local ok,err=pcall(function()
   local t=100
   for _=1,1200 do t=t+1/60; a.z=a.z+a.speed/60; a.spline=(a.z/f.length)%1; Delta.update(d,f,e.run,inc,e.states,t,1/60,false) end
  end)
  Delta.pace=pace; assert(ok,err)
  return d.value
 end
 local r1,r2=red(10),red(200); assert(r1~=nil and r1~=r2,'redDeltaPct: red flag reference '..tostring(r1)..' / '..tostring(r2))
 -- Overtake Mode : écart de détection et gain de niveau.
 local function lap(gapSetting,boost)
  local e,f=F.scene('C',3); e.profiles.C.overtakeMode=true; e.profiles.C.overtakeEnabled=false; e.profiles.C.overtakeModeGap=gapSetting; e.profiles.C.overtakeModeBoostPct=boost; E.changed(e)
  F.place(f,2,9450,100); F.place(f,3,9450+40,100); F.place(f,1,2000,100)
  F.tick(e,f,3,true)
  return e
 end
 assert(lap(2,2).states[2].overtakeArmed and not lap(0.3,2).states[2].overtakeArmed,'overtakeModeGap: detection gap')
 local b0,b5=lap(2,0).commands[2].level,lap(2,5).commands[2].level
 assert(b5>b0*1.03,'overtakeModeBoostPct: level gain')
 -- Message à l'écran au changement de météo (weatherMessage).
 local function weather(on)
  local e,f=F.scene('C',3); e.profiles.C.weatherMessage=on; E.changed(e); F.tick(e,f,0.5)
  f.wet=1; f.rain=0.5; local seen=false
  for _=1,math.floor((C.K.weatherConfirm+1)*60) do F.tick(e,f,1/60); if e.incidents.messageKind=='wet' then seen=true end end
  return seen
 end
 assert(weather(true) and not weather(false),'weatherMessage: on-screen message')
end
return tests
