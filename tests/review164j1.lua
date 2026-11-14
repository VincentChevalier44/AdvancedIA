-- Beta 1.64, décision du pilote du 14 novembre 2026 (« jamais lever un arrêt configuré ») : un arrêt obligatoire réglé
-- (préréglage de règles ou à la main) n'est jamais levé ni annoncé « course sprint », quelle que soit la distance ; la
-- fenêtre ajustée à la course courte (1.63) s'applique ; seule la course trop courte (aucun tour ouvert possible) le lève.
-- Chargé par tests/extended.lua (après tests/review164d).
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Pits=require('src/pits')
local K=C.K
local tests={}

local function race(laps,length)
 local e,f=F.scene('C',3); local p=e.run
 p.mandatoryStops=1; p.pitWindowOpenPct=20; p.pitWindowClosePct=95; p.pitCompoundChange=true; p.redFlagWork=true; p.pitMessage=true; p.pitTyres=true
 f.sessionLaps=laps; f.leaderLaps=0; f.timedRace=false; f.sessionMinutes=0; f.pitWindowStart=0; f.pitWindowEnd=0; f.started=true
 f.length=length or 10000
 for i=1,f.count do f.cars[i].bestLap=0 end
 return e,f,p
end
local function ai(f) local list={}; for i=1,f.count do local a=f.cars[i]; if a.valid and a.control and not a.player and not a.safetyCar then list[#list+1]=i end end; return list end
local function kinds(said,kind) local n=0; for _,s in ipairs(said) do if s[1]==kind then n=n+1 end end return n end
local function step(t,f,e,p,now,said) Pits.update(t,f,e.commands,p,'C',now,1,said and function(kind,a,b) said[#said+1]={kind,a,b} end or nil,false) end
local function journal(t) local lines={}; t.note=function(level,text) lines[#lines+1]=text end; return lines end
local function has(lines,text) for _,l in ipairs(lines) do if l:find(text,1,true) then return true end end return false end

-- 10 tours de 10 km (100 km) avec un arrêt réglé : jamais levé, jamais « sprint » ; la fenêtre s'ouvre, les IA sont
-- appelées ; 2 tours : la course trop courte lève encore l'arrêt (impossible).
tests.LOCK_SPRINT_164=function()
 assert(K.sprintWaiver==false,'sprint waiver off (driver decision 2026-11-14)')
 local e,f,p=race(10); local t=Pits.new(); local lines=journal(t); local said={}
 f.started=false; step(t,f,e,p,100,said)
 assert(t.sprint==nil and not t.waived,'100 km on the grid: configured stop kept')
 f.started=true
 for lap=0,8 do f.leaderLaps=lap; step(t,f,e,p,101+lap,said) end
 assert(t.state=='open' or t.state=='closed','window used ('..t.state..')')
 assert(t.opened,'window opened')
 local called=false
 for _,i in ipairs(ai(f)) do if e.commands[i].rulePit then called=true end end
 assert(called or t.state=='closed','AI called in the window')
 assert(kinds(said,'pitSprint')==0 and not has(lines,'course sprint'),'never announced as a sprint')
 -- Course trop courte : 2 tours, aucun tour ouvert possible : levée gardée.
 local e2,f2,p2=race(2); local t2=Pits.new(); local said2={}
 f2.leaderLaps=0; step(t2,f2,e2,p2,100,said2); step(t2,f2,e2,p2,101,said2)
 assert(t2.waived,'2 laps: impossible stop lifted')
 assert(kinds(said2,'pitSprint')==0,'2 laps: never « sprint »')
end

-- Départ avec tour de formation, 10 tours courts : jamais de message « course sprint ».
tests.LOCK_SPRINT_START_ANNOUNCE_164=function()
 local LENGTH=1200
 local function slotZ(k) return -(K.gridFirst+(k-1)*K.gridPitch) end
 local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); C.applyRules('F1',e.profiles)
 e.profiles.C.raceStart='formation'; e.profiles.C.startRealism=false; e.profiles.C.pitMessage=true; f.length=LENGTH
 f.sessionLaps=10; f.leaderLaps=0
 for i=1,4 do f.cars[i].position=i; F.place(f,i,slotZ(i),0) end
 f.started=false; E.changed(e); e.gridCaps=true; F.tick(e,f,1/60); F.tick(e,f,1/60)
 f.started=true
 for _=1,600 do F.tick(e,f,1/60); assert(e.incidents.messageKind~='pitSprint','never « course sprint »') end
 assert(e.pits.sprint==nil and not e.pits.waived,'configured stop kept')
end

return tests
