-- Beta 1.64, lot 3 (référentiel des comportements pilotes, situations 03-10, 06-10 et 06-11 ; décisions du pilote du
-- 13 novembre) : drapeau rouge, piste dégagée au délai maximal. IA encore en incident en piste dépannées jusqu'à leur
-- stand, reprise dès la piste vide (au plus K.redClearWait s de plus) ; dépannage impossible ou sans effet : reprise
-- forcée notée au journal, tour de relance de durée normale, départ lancé si l'obstacle est encore en piste à la fin du
-- tour de relance (règles à départ arrêté). Noms LOCK_*_164 (tests/LOCKS.md). Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local U=require('src/util')
local A=require('src/applier')
local K=C.K
local tests={}
local openFile=io.open
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function logged(e,text) return count(e,text)>0 end
local function find(e,text) for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then return r.message end end return nil end
-- Journal agrandi : les scènes durent plus longtemps que les 200 lignes du journal de l'app.
local function bigLog(e) e.log=U.newLog(4000,K.logRate,K.logDedup) end
-- Voiture posée à son emplacement, à l'arrêt (aussi : dépannage simulé, comme le déplacement de CSP).
local function tow(f,i) local a=f.cars[i]; a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0 end
local function crawl(f,i,kmh) local a=f.cars[i]; a.kmh=kmh; a.speed=kmh/3.6 end
-- Scène de RED_FLAG_PROCEDURE : IA 3, 4 et 5 arrêtées en travers de la piste à 600 m ; drapeau rouge ; IA 2 et 6 et
-- joueur à leur emplacement ; délai maximal raccourci à 3 s de rouge (le délai tiré du tour est verrouillé par e4).
-- cap : e.teleportCap (nil : bancs du moteur seul ; true : déplacement de CSP en service).
local function redScene(profile,cap,setup)
 local e,f=F.scene(profile,6); bigLog(e)
 local p=e.profiles[profile]
 if profile=='C' then C.preset('Course','C',p) end
 p.redFlagHold=20
 if setup then setup(p,e) end
 E.changed(e); e.teleportCap=cap
 for i=2,6 do F.place(f,i,(i-1)*300,120) end
 F.block(f,{3,4,5},600)
 F.tick(e,f,K.redIncidentStill+1)
 local t=e.incidents
 assert(t.red and t.reds==1,'red flag')
 for _,i in ipairs({2,6,1}) do tow(f,i) end
 t.redMax=(e.time-t.redSince)+3
 return e,f,t
end
-- Images de 1/60 s jusqu'à « délai maximal + at » (ou la fin du rouge) ; kinematic : les voitures avancent.
local function upTo(e,f,t,at,kinematic) while t.red and e.time-t.redSince<t.redMax+at do F.tick(e,f,1/60,kinematic) end end
local function lifted(e,f,t,frames) for _=1,frames or 2 do if not t.red then return true end; F.tick(e,f,1/60) end return not t.red end
local WAIT1='drapeau rouge: delai maximal atteint, piste non degagee, 1 IA en piste depannees vers leur stand (attente au plus 15 s)'
local IMPOSSIBLE='drapeau rouge: piste non degagee au delai maximal, 3 IA en piste (Driver_3 a 600 m), depannage impossible, reprise forcee'

-- Course, déplacement de CSP en service : une IA au pas en piste (aucune règle actuelle ne la dépanne) retient la reprise
-- au délai maximal ; dépannée (raison dédiée), la reprise suit aussitôt ; attente notée une fois par drapeau rouge.
tests.LOCK_RED_CLEAR_TRACK_164=function()
 local e,f,t=redScene('C',true)
 tow(f,4); tow(f,5); crawl(f,3,6)
 F.tick(e,f,1,true)
 assert(t.red and t.onTrack==1 and t.cars[3].incident,'crawling AI still in an incident on the track')
 assert(not e.commands[3].recover and t.redClear~=true,'before the maximum delay: a crawling AI is recovered by no rule')
 upTo(e,f,t,0.5,true)
 local cmd=e.commands[3]
 assert(t.red and t.redClear==true,'held at the maximum delay while an AI is still on the track')
 assert(cmd.recover and cmd.recoverReason=='delai maximal' and (cmd.recoverStill or 0)>0,'crawling AI recovered at the maximum delay: '..tostring(cmd.recoverReason))
 assert(count(e,WAIT1)==1,'wait logged')
 F.tick(e,f,7,true)
 assert(t.red and count(e,WAIT1)==1,'wait logged once, not every frame')
 tow(f,3)
 assert(lifted(e,f,t),'restart as soon as the track is clear')
 assert(t.relaunch and t.neutral and t.neutralMode=='fcy','restart lap under FCY (no Safety Car)')
 assert(count(e,'reprise apres drapeau rouge (delai maximal): tour de relance sous fcy')==1 and count(e,'reprise forcee')==0,'normal restart, no forced restart line')
 assert(not (t.neutralEnd>=t.redEnd) and t.redObstacle~=true,'clear track: restart lap and standing restart unchanged')
 -- Second drapeau rouge dans la même scène : l'attente est notée de nouveau.
 for _,i in ipairs({3,4,5}) do local a=f.cars[i]; a.pit=false; a.inPitBox=false; F.place(f,i,600,120) end
 F.tick(e,f,1/60)
 F.block(f,{3,4,5},600)
 F.tick(e,f,K.redIncidentStill+1)
 assert(t.red and t.reds==2,'second red flag')
 tow(f,4); tow(f,5); crawl(f,3,6)
 t.redMax=(e.time-t.redSince)+3
 upTo(e,f,t,0.5,true)
 assert(t.red and t.redClear==true and count(e,WAIT1)==2,'wait logged again at the next red flag')
end

-- Dépannage impossible (capacité absente ou coupée) ou sans effet : reprise forcée notée, bornée à K.redClearWait s ;
-- jamais de second rouge sur les mêmes voitures ; zone jaune à l'obstacle seulement drapeaux jaunes cochés.
tests.LOCK_RED_CLEAR_FALLBACK_164=function()
 local function settle(e,f,t,label)
  F.tick(e,f,30); assert(not t.red and t.reds==1,label..': no second red flag on the same cars')
 end
 -- (a) capacité absente (bancs du moteur seul, CSP sans déplacement) : reprise au délai maximal, sans attente.
 local e,f,t=redScene('C',nil)
 upTo(e,f,t,-0.5); assert(t.red,'(a) still red before the maximum delay')
 upTo(e,f,t,0.1)
 assert(not t.red and t.redEnd-t.redSince<t.redMax+0.05,'(a) restart at the maximum delay, no wait')
 assert(t.relaunch and t.neutralMode=='fcy','(a) restart lap under FCY')
 assert(count(e,IMPOSSIBLE)==1 and count(e,'delai maximal atteint')==0,'(a) forced restart logged: '..tostring(find(e,'piste non degagee')))
 settle(e,f,t,'(a)')
 -- (b) capacité en service, déplacement sans effet (voitures restées en place) : attente bornée.
 e,f,t=redScene('C',true)
 upTo(e,f,t,0.5)
 assert(t.red and t.redClear==true and count(e,'drapeau rouge: delai maximal atteint, piste non degagee, 3 IA en piste')==1,'(b) wait logged')
 upTo(e,f,t,K.redClearWait-0.5); assert(t.red,'(b) still waiting just before the bound')
 upTo(e,f,t,K.redClearWait+0.1)
 assert(not t.red and t.redEnd-t.redSince<t.redMax+K.redClearWait+0.05,'(b) forced restart at the bound')
 local line=find(e,'drapeau rouge: piste non degagee 15 s apres le delai maximal')
 assert(line and line:find('3 IA en piste (Driver_3 a 600 m), depannage sans effet, reprise forcee',1,true) and count(e,'depannage impossible')==0,'(b) ineffective recovery logged: '..tostring(line))
 settle(e,f,t,'(b)')
 -- (c) capacité coupée pendant l'attente (échecs) : reprise forcée aussitôt.
 e,f,t=redScene('C',true)
 upTo(e,f,t,2); assert(t.red and t.redClear==true,'(c) waiting')
 e.teleportCap=false
 assert(lifted(e,f,t),'(c) capability cut: forced restart at once')
 assert(count(e,IMPOSSIBLE)==1,'(c) logged as unavailable')
 settle(e,f,t,'(c)')
 -- (d) règles avec VSC : tour de relance sous VSC.
 e,f,t=redScene('C',nil,function(p) p.neutralization='vsc' end)
 upTo(e,f,t,0.1)
 assert(not t.red and t.relaunch and t.neutralMode=='vsc' and count(e,IMPOSSIBLE)==1,'(d) restart lap under VSC')
 settle(e,f,t,'(d)')
 -- (e) drapeaux jaunes cochés : zone jaune à l'obstacle.
 e,f,t=redScene('C',nil,function(p) p.yellowEnabled=true end)
 upTo(e,f,t,0.1)
 assert(not t.red and t.neutral,'(e) forced restart')
 local zone=false
 for k=1,t.zoneCount do local z=t.zones[k]; if (z.slot==3 or z.slot==4 or z.slot==5) and z.onTrack then zone=true end end
 assert(zone and (logged(e,'zone jaune ouverte: Driver_3') or logged(e,'zone jaune ouverte: Driver_4') or logged(e,'zone jaune ouverte: Driver_5')),'(e) yellow zone at the obstacle')
 settle(e,f,t,'(e)')
 -- (f) décision du pilote : drapeaux jaunes décochés, réglage respecté : aucune zone jaune forcée.
 e,f,t=redScene('C',nil,function(p) p.yellowEnabled=false end)
 upTo(e,f,t,0.1)
 assert(not t.red and t.neutral and t.relaunch and count(e,IMPOSSIBLE)==1,'(f) forced restart')
 assert(count(e,'zone jaune ouverte')==0,'(f) yellow flags unticked: no yellow zone forced')
 settle(e,f,t,'(f)')
 assert(count(e,'zone jaune ouverte')==0,'(f) still none later')
end

-- Essais et qualifications : même règle, session relancée (sans tour de relance), sortie échelonnée.
tests.LOCK_RED_CLEAR_QUALI_164=function()
 for _,profile in ipairs({'Q','P'}) do
  local e,f,t=redScene(profile,true)
  tow(f,4); tow(f,5); crawl(f,3,6)
  upTo(e,f,t,0.5,true)
  assert(t.red and e.commands[3].recover and e.commands[3].recoverReason=='delai maximal' and count(e,WAIT1)==1,profile..' (a): held, crawling AI recovered')
  tow(f,3)
  assert(lifted(e,f,t),profile..' (a): restart once the track is clear')
  assert(count(e,'reprise apres drapeau rouge (delai maximal): session relancee')==1 and not t.neutral and not t.relaunch and count(e,'reprise forcee')==0,profile..' (a): session resumed')
  F.tick(e,f,0.3); assert(t.messageKind=='sessionResume',profile..' (a): resume message')
  e,f,t=redScene(profile,nil)
  upTo(e,f,t,0.1)
  assert(not t.red and t.redEnd-t.redSince<t.redMax+0.05 and count(e,'depannage impossible, reprise forcee')==1,profile..' (b): forced restart at the maximum delay')
  assert(not t.neutral and not t.relaunch,profile..' (b): no restart lap outside the race')
  assert(e.commands[2].pitHold or e.commands[6].pitHold,profile..' (b): staggered pit exit')
 end
end

-- Toute autre attente au délai maximal finit exactement à ce délai, comme avant ; règles décochées : annulation aussitôt.
tests.LOCK_RED_CLEAR_SCOPE_164=function()
 local function exact(e,f,t,label)
  upTo(e,f,t,-0.5); assert(t.red,label..': still red before the maximum delay')
  upTo(e,f,t,0.1)
  assert(not t.red and t.redEnd-t.redSince<t.redMax+0.05,label..': restart exactly at the maximum delay')
  assert(count(e,'piste non degagee')==0 and count(e,'delai maximal atteint')==0,label..': no clear-track line')
 end
 local function penalised(e,f,label) F.tick(e,f,1); assert(e.penalties.redPending or e.penalties.reason=='red',label..': player out of the pits penalised') end
 local function playerOut(f) local a=f.cars[1]; a.pit=false; a.inPitBox=false; F.place(f,1,5000,100) end
 -- (1) IA qui roule encore dans la voie des stands.
 local e,f,t=redScene('C',true)
 tow(f,3); tow(f,5)
 local a4=f.cars[4]; a4.pit=true; a4.inPitBox=false; a4.kmh=30; a4.speed=30/3.6
 F.tick(e,f,1/60); assert(t.onTrack==0,'(1) track clear')
 exact(e,f,t,'(1) AI rolling in the pit lane')
 -- (2) toutes les IA à leur emplacement, joueur resté en piste.
 e,f,t=redScene('C',true)
 for _,i in ipairs({3,4,5}) do tow(f,i) end
 playerOut(f)
 exact(e,f,t,'(2) player out')
 assert(t.redPlayerIn==false,'(2) player still out at the restart')
 penalised(e,f,'(2)')
 -- (3) IA arrêtée hors piste, loin de la trajectoire.
 e,f,t=redScene('C',true)
 tow(f,4); tow(f,5)
 local a3=F.place(f,3,600,0,20); a3.offtrack=true; a3.wheelsOut=4
 F.tick(e,f,1/60); assert(t.onTrack==0,'(3) car off the track not counted')
 exact(e,f,t,'(3) AI stopped off the track')
 -- (4) joueur dehors et IA au pas en piste : retenue pour l'IA seulement, levée dès son dépannage.
 e,f,t=redScene('C',true)
 tow(f,4); tow(f,5); crawl(f,3,6); playerOut(f)
 upTo(e,f,t,0.5,true)
 assert(t.red and t.redClear==true,'(4) held for the AI on the track')
 tow(f,3)
 assert(lifted(e,f,t),'(4) restart without waiting for the player')
 assert(count(e,'reprise forcee')==0,'(4) normal restart')
 penalised(e,f,'(4)')
 -- (5) règles décochées pendant l'attente : annulation, personne n'est pénalisé.
 e,f,t=redScene('C',true)
 tow(f,4); tow(f,5); crawl(f,3,6); playerOut(f)
 upTo(e,f,t,1,true)
 assert(t.red and t.redClear==true,'(5) waiting')
 e.profiles.C.redFlagEnabled=false; E.changed(e); F.tick(e,f,1/60)
 assert(not t.red and t.redCancelled and count(e,'drapeau rouge leve: regles inactives')==1 and count(e,'reprise forcee')==0,'(5) cancelled at once')
 F.tick(e,f,1); assert(e.penalties.count==0 and not e.penalties.redPending,'(5) cancelled red: no penalty')
end

-- Applicateur : ligne dédiée (jamais « immobile depuis »), un seul déplacement par série.
tests.LOCK_RED_CLEAR_TOW_LINE_164=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C'); local a=A.new(); assert(A.access(a))
 local notes={}; a.note=function(_,text) notes[#notes+1]=text end
 for _,cmd in ipairs(e.commands) do cmd.active=false; cmd.stopHold=false; cmd.mergeHold=false end
 local cmd=e.commands[3]; cmd.recover=true; cmd.recoverReason='delai maximal'; cmd.recoverStill=42
 A.apply(a,f,e.commands,e.g,10)
 local text=table.concat(notes,'\n')
 assert(host.teleports==1,'recovered to its pit box')
 assert(text:find('IA encore en piste au delai maximal du drapeau rouge depannee a son stand (en incident depuis 42 s)',1,true) and not text:find('IA immobile depannee',1,true),'dedicated line: '..text)
 A.apply(a,f,e.commands,e.g,10.1); assert(host.teleports==1,'one move per series')
 cmd.recover=false; A.apply(a,f,e.commands,e.g,10.2)
 cmd.recover=true; A.apply(a,f,e.commands,e.g,10.3); assert(host.teleports==2,'new series: moved again')
end

-- Constantes et textes (README, infobulles FR et EN) : même attente.
tests.K_RED_CLEAR_164=function()
 assert(K.redClearWait>K.redRecoverTime and K.redClearWait<K.redFlagMax,'constants')
 local s=string.format('%.0f s',K.redClearWait)
 assert(require('src/tips').settings.redFlagHold:find('au plus '..s..' de plus',1,true),'FR tooltip')
 assert(require('src/tips_en').settings.redFlagHold:find('at most '..s..' more',1,true),'EN tooltip')
 local root=package.path:match('^([^;]+)/%?%.lua'); local file=assert(openFile(root..'/README.md','rb')); local text=file:read('*a'); file:close()
 assert(text:find('(at most '..s..' later)',1,true) and text:find('after those '..s..',',1,true),'README')
end

-- Décision du pilote (13 novembre) : reprise forcée avec un obstacle encore en piste : tour de relance de durée normale,
-- l'obstacle (sous jaune) ne prolonge plus la neutralisation ; jamais de nouvelle neutralisation pour lui.
tests.LOCK_RED_FALLBACK_RELAUNCH_164=function()
 local e,f,t=redScene('C',nil,function(p) p.neutralization='vsc'; p.yellowEnabled=true end)
 upTo(e,f,t,0.1)
 assert(not t.red and t.relaunch and t.neutralMode=='vsc' and t.neutralEnd==t.redEnd,'forced restart: the obstacle is no longer a major incident')
 F.tick(e,f,5)
 assert(t.neutral and t.onTrack==3 and t.cars[3].still>=e.run.majorIncidentTime,'obstacle stopped on the track for longer than a major incident')
 local zone=false; for k=1,t.zoneCount do if t.zones[k].slot==3 then zone=true end end
 assert(zone,'obstacle under yellow')
 -- Fin du tour de relance (durée injectée : la piste du banc fait 10 km).
 t.neutralUntil=e.time+1
 for _=1,60*(3+K.vscEnding) do if not t.neutral then break end; F.tick(e,f,1/60) end
 assert(not t.neutral and count(e,'drapeau vert: fin de neutralisation')==1,'restart lap ends on time')
 F.tick(e,f,10)
 assert(not t.neutral and count(e,'neutralisation: vsc')==0,'no new neutralisation for the same obstacle')
end

-- Décision du pilote (13 novembre) : règles à départ arrêté, reprise forcée, obstacle encore en piste à la fin du tour de
-- relance : départ lancé à la place (ligne, panneau) ; parti entre-temps : départ arrêté normal.
tests.LOCK_RED_FALLBACK_STANDING_164=function()
 local function scene()
  local e,f,t=redScene('C',nil,function(p) p.neutralization='vsc'; p.redRestart='standing' end)
  e.gridCaps=true
  upTo(e,f,t,0.1)
  assert(not t.red and t.relaunch and t.neutralMode=='vsc' and t.redObstacle==true,'forced restart, obstacle left on the track')
  return e,f,t
 end
 -- Tour de relance du meneur (recette de RELAUNCH_LEADER_LAP_135) : IA 2, 6 et joueur sortis des stands.
 local function lap(e,f,t)
  for _,i in ipairs({1,2,6}) do local a=f.cars[i]; a.pit=false; a.inPitBox=false end
  f.cars[2].position=1; f.cars[6].position=2; f.cars[1].position=3; for i=3,5 do f.cars[i].position=i+1 end
  t.relaunchSpanUntil=e.time; t.relaunchLeader=0; t.relaunchTravel=0
  local function at(z) for k,i in ipairs({2,6,1}) do F.place(f,i,z-k*30,90) end; F.tick(e,f,1/60) end
  at(1000); at(1000)
  for z=2000,f.length-K.gridFormFrom-200,1500 do at(z) end
  assert(t.neutral and t.standing=='none','restart lap still running')
  at(f.length-K.gridFormFrom+100)
 end
 local e,f,t=scene()
 F.tick(e,f,0.3); assert(e.panel.decided=='rolling','panel: rolling start announced while the obstacle is on the track: '..tostring(e.panel.decided))
 lap(e,f,t)
 assert(not t.neutral and t.standing=='none' and count(e,'relance arretee indisponible (piste non degagee): depart lance')==1,'obstacle still there: rolling start instead')
 assert(count(e,'drapeau vert: fin de neutralisation')==1 and count(e,'relance: depart arrete (SS)')==0,'green flag, no grid')
 -- Obstacle dépanné pendant le tour de relance : départ arrêté normal.
 e,f,t=scene()
 for i=3,5 do tow(f,i) end
 F.tick(e,f,0.3); assert(e.panel.decided=='standingLap','panel: standing start announced once the track is clear: '..tostring(e.panel.decided))
 lap(e,f,t)
 assert(t.standing=='grid' and count(e,'relance: depart arrete (SS)')==1 and count(e,'piste non degagee): depart lance')==0,'obstacle gone: standing start')
end

return tests
