-- 2.0.3 a (pilote, 16 novembre : « moins de 100 km arrêt au stand désactivé par défaut, plus de 100 km on active l'arrêt
-- au stand par défaut ») : arrêt obligatoire réglé par la distance tant que le pilote ne règle pas lui-même l'interrupteur
-- (C.globalDefaults.mandatoryManual) ; son choix est gardé quelle que soit la distance (décision du 14 novembre). Et
-- (rapport d'un joueur : fenêtre « en attente » toute la course, 0 IA en règle) : tours du leader lus à 0 alors que les
-- voitures bouclent des tours : avancement d'après les voitures. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local Pits=require('src/pits')
local K=C.K
local tests={}

local function ai(f) local list={}; for i=1,f.count do local a=f.cars[i]; if a.valid and a.control and not a.player and not a.safetyCar then list[#list+1]=i end end; return list end
local function has(lines,text) local n=0; for _,l in ipairs(lines) do if l:find(text,1,true) then n=n+1 end end return n end
-- Course aux tours de laps tours sur un circuit de length m (37 km : 8 tours de 4,6 km ; 120 km : 26 tours), réglages
-- du profil Course passés par C.effective et C.distanceDefault comme en jeu ; manual : choix du pilote (nil : défaut).
local function race(laps,length,manual,stops)
 local e,f=F.scene('C',3)
 local p=C.defaults('C'); p.section_rules=true; p.mandatoryStops=stops or 0; p.pitWindowOpenPct=20; p.pitWindowClosePct=80
 local g={mandatoryManual=manual==true}
 local run=C.distanceDefault('C',p,g,C.effective('C',p,{}))
 run.pitMessage=true; run.pitTyres=true
 f.sessionLaps=laps; f.leaderLaps=0; f.timedRace=false; f.sessionMinutes=0; f.pitWindowStart=0; f.pitWindowEnd=0; f.started=false
 f.length=length
 for i=1,f.count do f.cars[i].bestLap=0; f.cars[i].lap=0 end
 return e,f,run
end
local function drive(e,f,p,t,laps,leader)
 local said={}
 local function step(now) Pits.update(t,f,e.commands,p,'C',now,1,function(kind) said[#said+1]=kind end,false) end
 step(100); f.started=true
 local called=false
 for lap=0,laps-1 do
  if leader then f.leaderLaps=lap else f.leaderLaps=0 end
  for i=1,f.count do f.cars[i].lap=lap end
  step(101+lap)
  for _,i in ipairs(ai(f)) do if e.commands[i].rulePit then called=true end end
 end
 return called,said
end

tests.LOCK_MANDATORY_DEFAULT_BY_DISTANCE_203=function()
 assert(C.globalDefaults.mandatoryManual==false,'default: not set by the player')
 -- 37 km (8 tours de 4,6 km), défaut : pas d'arrêt obligatoire, dit au journal ; même avec l'interrupteur resté allumé.
 for _,stops in ipairs({0,1}) do
  local e,f,p=race(8,4591,nil,stops); local t=Pits.new(); local lines={}; t.note=function(_,text) lines[#lines+1]=text end
  assert(p.mandatoryByDistance==true and p.mandatoryStops==1,'default: distance decides')
  local called=drive(e,f,p,t,8,true)
  assert(t.sprint==true and t.waived and t.state=='off' and not called,'37 km by default: no mandatory stop ('..t.state..')')
  assert(has(lines,'arret obligatoire par defaut selon la distance: desactive (100 km au plus sans arret)')==1,'journal says off by default')
 end
 -- 120 km (26 tours de 4,6 km), défaut, interrupteur jamais allumé : un arrêt, IA appelées.
 local e,f,p=race(26,4615,nil,0); local t=Pits.new(); local lines={}; t.note=function(_,text) lines[#lines+1]=text end
 local called=drive(e,f,p,t,26,true)
 assert(t.sprint==false and not t.waived and t.opened and called,'120 km by default: mandatory stop on, AI called')
 assert(has(lines,'arret obligatoire par defaut selon la distance: active (100 km au plus sans arret)')==1,'journal says on by default')
 -- Choix du pilote : arrêt allumé dans une course de 37 km gardé ; éteint dans une course de 120 km gardé.
 local e2,f2,p2=race(8,4591,true,1); local t2=Pits.new()
 assert(p2.mandatoryByDistance==false and p2.mandatoryStops==1)
 local called2=drive(e2,f2,p2,t2,8,true)
 assert(t2.sprint==nil and not t2.waived and t2.opened and called2,'explicit on in a short race: kept')
 local e3,f3,p3=race(26,4615,true,0); local t3=Pits.new()
 assert(p3.mandatoryByDistance==false and p3.mandatoryStops==0)
 local called3=drive(e3,f3,p3,t3,26,true)
 assert(t3.state=='off' and not t3.opened and not called3,'explicit off in a long race: kept')
 -- Onglet Règles décoché : jamais d'arrêt, quelle que soit la distance ; hors course : rien.
 local p4=C.defaults('C'); p4.section_rules=false
 local r4=C.distanceDefault('C',p4,{mandatoryManual=false},C.effective('C',p4,{}))
 assert(r4.mandatoryByDistance==false and r4.mandatoryStops==0,'rules off: no stop')
 local p5=C.defaults('P'); p5.section_rules=true
 assert(C.distanceDefault('P',p5,{mandatoryManual=false},C.effective('P',p5,{})).mandatoryByDistance==false,'practice untouched')
 -- Interrupteur réglé par le pilote : marqué ; jeu de règles de championnat : retour au défaut.
 local profiles={}; for _,pr in ipairs(C.profiles) do profiles[pr]=C.defaults(pr) end
 local g={mandatoryManual=true}
 assert(C.applyRules('F1',profiles,g) and g.mandatoryManual==false,'rule set: back to the default')
 local vg=C.validateGlobals({mandatoryManual=true}); assert(vg.mandatoryManual==true,'kept when saved')
end

tests.LOCK_PROGRESS_LEADER_FALLBACK_203=function()
 -- Tours du leader lus à 0 toute la course (rapport du joueur) : avancement d'après les voitures, fenêtre ouverte, IA appelées.
 local e,f,p=race(26,10000,true,1); local t=Pits.new(); local lines={}; t.note=function(level,text) lines[#lines+1]=level..' '..text end
 local called=drive(e,f,p,t,20,false)
 assert(t.opened and called and t.progress>0.5,'window opened from the cars laps ('..t.state..', '..tostring(t.progress)..')')
 assert(has(lines,'WARN tours du leader indisponibles, avancement d apres les voitures')==1,'said once')
 -- Tours du leader disponibles : jamais remplacés ; avant le départ : 0.
 f.leaderLaps=3; for i=1,f.count do f.cars[i].lap=9 end
 assert(Pits.leaderLaps(f)==3,'leader laps used when available')
 f.leaderLaps=0; f.started=false; assert(Pits.leaderLaps(f)==0,'not before the start')
 f.started=true; f.cars[2].valid=false; f.cars[3].valid=false; f.cars[1].valid=false; assert(Pits.leaderLaps(f)==0,'only valid cars')
end

return tests
