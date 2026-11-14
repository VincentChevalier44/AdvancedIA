-- Affinage 1.63 (course courte, demande du pilote du 13 novembre : dans une course de 7 tours, une IA pouvait s'arrêter
-- au 7e tour et franchir l'arrivée dans la voie des stands) : fenêtre des règles fermée avant le dernier tour, au moins un
-- tour ouvert, IA appelées au plus tard un tour avant la fermeture, arrêt levé si la course est trop courte ; fenêtre de
-- CSP et longues courses inchangées. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local Pits=require('src/pits')
local K=require('src/config').K
local tests={}

local function race(laps,open,close)
 local e,f=F.scene('C',3); local p=e.run
 p.mandatoryStops=1; p.pitWindowOpenPct=open or 20; p.pitWindowClosePct=close or 95; p.pitCompoundChange=false; p.redFlagWork=false; p.pitMessage=true
 f.sessionLaps=laps; f.leaderLaps=0; f.timedRace=false; f.sessionMinutes=0; f.pitWindowStart=0; f.pitWindowEnd=0; f.started=true
 -- Beta 1.64, lot 4 (accord du pilote) : circuit de 60 km, toutes ces courses au-dessus de K.sprintMaxKm (100 km ou moins :
 -- course sprint, LOCK_SPRINT_164).
 f.length=60000
 return e,f,p
end
local function stop(t,f,cmds,p,now,i)
 i=i or 2
 Pits.update(t,f,cmds,p,'C',now,1,nil,false)
 f.cars[i].pit=true; f.cars[i].inPitBox=true; Pits.update(t,f,cmds,p,'C',now+1,1,nil,false)
 f.cars[i].inPitBox=false; Pits.update(t,f,cmds,p,'C',now+2,1,nil,false)
 f.cars[i].pit=false; Pits.update(t,f,cmds,p,'C',now+3,1,nil,false)
end
local function ai(f) local list={}; for i=1,f.count do local a=f.cars[i]; if a.valid and a.control and not a.player and not a.safetyCar then list[#list+1]=i end end; return list end

-- Course de 7 tours à 20-95 % (préréglage F1) : leader dans le dernier tour (6 tours faits) : fenêtre fermée, un arrêt n'y
-- compte plus ; dans l'avant-dernier tour, compté ; toutes les IA appelées dès le 5e tour.
tests.LOCK_SHORT_RACE_WINDOW_163=function()
 local e,f,p=race(7); local t=Pits.new(); local lines={}; t.note=function(level,text) lines[#lines+1]=text end
 f.leaderLaps=6; stop(t,f,e.commands,p,100)
 assert(t.state=='closed','leader on the last lap: window closed ('..t.state..')')
 assert(t.cars[2].windowStops==0,'stop entered on the last lap not counted')
 assert(t.close<6/7,'effective closing before the last lap')
 local found=false; for _,l in ipairs(lines) do if l:find('fenetre d arret ajustee a la longueur de la course',1,true) then found=true end end
 assert(found,'journal line for the adjusted window')
 local e2,f2,p2=race(7); local t2=Pits.new()
 f2.leaderLaps=5; stop(t2,f2,e2.commands,p2,100)
 assert(t2.cars[2].windowStops==1,'stop in the second-to-last lap counted')
 local e3,f3,p3=race(7); local t3=Pits.new(); local said={}
 for laps=0,4 do f3.leaderLaps=laps; Pits.update(t3,f3,e3.commands,p3,'C',100+laps,1,function(kind,a,b) said[#said+1]={kind,a,b} end,false) end
 for _,i in ipairs(ai(f3)) do assert(e3.commands[i].rulePit,'AI '..i..' called by lap 5') end
 local open=nil; for _,s in ipairs(said) do if s[1]=='pitOpen' then open=s end end
 assert(open and open[3]<6/7*100 and math.abs(open[3]-t3.close*100)<1e-9,'player notice shows the effective closing')
end

-- Fenêtre d'ouverture trop tardive (GT 42-58 % en 5 tours) : au moins un tour ouvert.
tests.SHORT_RACE_KEEPS_ONE_OPEN_LAP_163S2=function()
 local e,f,p=race(5,42,58); local t=Pits.new()
 local opened=0
 for laps=0,4 do f.leaderLaps=laps; Pits.update(t,f,e.commands,p,'C',100+laps,1,nil,false); if t.state=='open' then opened=opened+1 end end
 assert(opened>=1,'at least one open lap')
 assert(t.state=='closed','closed on the last lap')
end

-- Course de 2 tours : aucun tour ouvert hors du premier et du dernier : arrêt levé, annoncé, rien demandé.
tests.SHORT_RACE_WAIVED_163S2=function()
 local e,f,p=race(2); local t=Pits.new(); local said={}; local lines={}; t.note=function(level,text) lines[#lines+1]=text end
 f.leaderLaps=1; Pits.update(t,f,e.commands,p,'C',100,1,function(kind) said[#said+1]=kind end,false)
 assert(t.waived and t.state=='off','mandatory stop lifted ('..t.state..')')
 for _,i in ipairs(ai(f)) do assert(not e.commands[i].rulePit,'no AI called') end
 assert(said[1]=='pitShort','announced once')
 Pits.update(t,f,e.commands,p,'C',101,1,function(kind) said[#said+1]=kind end,false)
 assert(#said==1,'announced only once')
 local found=false; for _,l in ipairs(lines) do if l:find('course trop courte',1,true) then found=true end end
 assert(found,'journal line')
 -- 3 tours : un tour ouvert (le 2e), pas levé.
 local e3,f3,p3=race(3); local t3=Pits.new(); f3.leaderLaps=1; Pits.update(t3,f3,e3.commands,p3,'C',100,1,nil,false)
 assert(not t3.waived and t3.state=='open','3 laps: lap 2 open')
end

-- Course chronométrée de 10 min, tour de référence 90 s : fermée 1,5 tour avant la fin du temps ; inconnu : inchangé.
tests.TIMED_RACE_WINDOW_163S2=function()
 local e,f,p=race(0); f.sessionLaps=0; f.timedRace=true; f.sessionMinutes=10; f.left=600
 local t=Pits.new()
 Pits.update(t,f,e.commands,p,'C',100,1,nil,false)
 assert(t.close==0.95,'lap time unknown: closing unchanged')
 for _,i in ipairs(ai(f)) do t.cars[i].lapTime=90 end
 f.left=60; Pits.update(t,f,e.commands,p,'C',101,1,nil,false)
 assert(math.abs(t.close-(1-1.5*90/600))<1e-9,'closing 1.5 reference laps before the end')
 assert(t.state=='closed','last 60 s: closed')
 -- Beta 1.64 (décision du pilote, constat 5) : fenêtre en attente jusqu'à la décision du sprint (2 tours bouclés) ; ici
 -- 7 tours de 60 km : arrêt maintenu.
 for _,i in ipairs(ai(f)) do f.cars[i].lap=5; f.cars[i].bestLap=90 end
 f.left=600-0.70*600; Pits.update(t,f,e.commands,p,'C',102,1,nil,false)
 assert(t.state=='open','70 %: open')
 for _,i in ipairs(ai(f)) do assert(e.commands[i].rulePit,'AI '..i..' called one reference lap before the closing') end
end

-- Longue course (50 tours, 20-95 %) : pourcentages gardés tels quels, rien d'ajusté.
tests.LONG_RACE_WINDOW_UNCHANGED_163S2=function()
 local e,f,p=race(50); local t=Pits.new(); local lines={}; t.note=function(level,text) lines[#lines+1]=text end
 f.leaderLaps=30; Pits.update(t,f,e.commands,p,'C',100,1,nil,false)
 assert(t.open==0.2 and t.close==0.95,'long race: window unchanged')
 for _,l in ipairs(lines) do assert(not l:find('ajustee',1,true),'no adjusted window line') end
 -- 20 tours, 20-80 % : marge déjà là, inchangée.
 local e2,f2,p2=race(20,20,80); local t2=Pits.new(); f2.leaderLaps=10; Pits.update(t2,f2,e2.commands,p2,'C',100,1,nil,false)
 assert(t2.close==0.8,'20 laps at 80 %: unchanged')
end

-- Fenêtre déclarée par CSP : jamais touchée.
tests.CSP_WINDOW_UNTOUCHED_163S2=function()
 local e,f,p=race(7); f.pitWindowStart=100; f.pitWindowEnd=900; f.simTime=500
 local t=Pits.new(); f.leaderLaps=6; Pits.update(t,f,e.commands,p,'C',100,1,nil,false)
 assert(t.csp and t.open==100 and t.close==900 and t.state=='open','CSP window kept')
end

return tests
