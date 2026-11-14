-- Beta 1.63 (règle réelle de la F1, demande du pilote) : arrêt sous neutralisation (VSC, FCY, voiture de sécurité) compté
-- comme arrêt obligatoire même avant l'ouverture de la fenêtre, avec le changement de composé obligatoire (F1) ; sous
-- drapeau rouge, comme avant ; ailleurs la fenêtre ne change pas. Noms terminés par _163R. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local Pits=require('src/pits')
local tests={}
-- Lecture du vrai fichier : io.open capturé au chargement, avant que le banc ne le remplace.
local openFile=io.open

-- Course de 20 tours, meneur au tour 2 (10 %), fenêtre 20 à 95 % ; règles F1 (composé à changer) ou non.
local function race(f1)
 local e,f=F.scene('C',3); local p=e.run
 p.mandatoryStops=1; p.pitWindowOpenPct=20; p.pitWindowClosePct=95; p.pitCompoundChange=f1; p.redFlagWork=f1
 f.sessionLaps=20; f.leaderLaps=2; f.timedRace=false; f.sessionMinutes=0; f.pitWindowStart=0; f.pitWindowEnd=0; f.started=true
 return e,f,p
end
local function stop(t,f,cmds,p,now,red,neutral,i)
 i=i or 2
 t.neutralCount=neutral
 Pits.update(t,f,cmds,p,'C',now,1,nil,false)
 f.cars[i].pit=true; f.cars[i].inPitBox=true; Pits.update(t,f,cmds,p,'C',now+1,1,nil,red)
 f.cars[i].inPitBox=false; Pits.update(t,f,cmds,p,'C',now+2,1,nil,red)
 f.cars[i].pit=false; Pits.update(t,f,cmds,p,'C',now+3,1,nil,false)
end

tests.F1_STOP_UNDER_NEUTRALISATION_COUNTS_163R=function()
 local e,f,p=race(true); local t=Pits.new()
 stop(t,f,e.commands,p,100,false,true)
 assert(t.state=='pending','window not open yet ('..t.state..')')
 assert(t.cars[2].windowStops==1,'F1: stop under VSC/SC before the window counts')
 -- Arrêt fait : plus aucun arrêt obligatoire demandé à l'ouverture de la fenêtre.
 f.leaderLaps=18; t.neutralCount=false; Pits.update(t,f,e.commands,p,'C',200,1,nil,false)
 assert(t.state=='open' and e.commands[3].rulePit and not e.commands[2].rulePit,'no second mandatory stop asked (a car that owes it is called)')
end

tests.F1_STOP_UNDER_GREEN_BEFORE_WINDOW_NOT_COUNTED_163R=function()
 local e,f,p=race(true); local t=Pits.new()
 stop(t,f,e.commands,p,100,false,false)
 assert(t.cars[2].windowStops==0,'F1: green-flag stop before the window still not counted (window kept)')
end

tests.NO_COMPOUND_RULE_UNDER_NEUTRALISATION_NOT_COUNTED_163R=function()
 local e,f,p=race(false); local t=Pits.new()
 stop(t,f,e.commands,p,100,false,true)
 assert(t.cars[2].windowStops==0,'other rule sets: window unchanged under neutralisation')
end

tests.F1_RED_FLAG_COMPOUND_CHANGE_COUNTS_ONCE_163R=function()
 local e,f,p=race(true); local t=Pits.new()
 stop(t,f,e.commands,p,100,true,false)
 assert(t.cars[2].windowStops==1,'F1: red-flag stop counts')
 -- Obligation remplie : aucun arrêt obligatoire demandé ensuite, fenêtre ouverte.
 f.leaderLaps=18; t.neutralCount=false; Pits.update(t,f,e.commands,p,'C',200,1,nil,false)
 assert(t.state=='open' and e.commands[3].rulePit and not e.commands[2].rulePit,'no second mandatory stop asked after the red-flag change')
end

tests.F1_WET_WAIVER_UNCHANGED_163R=function()
 local e,f,p=race(true); local t=Pits.new(); t.wetRace=true
 stop(t,f,e.commands,p,100,false,true)
 assert(t.state=='off' and t.cars[2].windowStops==0,'wet race: obligation lifted, nothing counted')
end

-- Joueur : compté sous neutralisation avant la fenêtre seulement si le composé change (comme dans la fenêtre).
tests.F1_PLAYER_STOP_UNDER_NEUTRALISATION_163R=function()
 local e,f,p=race(true); local t=Pits.new()
 local pl=f.cars[1]; pl.player=true; f.player=1; pl.compoundIndex=0
 local cmds=e.commands
 t.neutralCount=true; Pits.update(t,f,cmds,p,'C',100,1,nil,false)
 pl.pit=true; pl.inPitBox=true; Pits.update(t,f,cmds,p,'C',101,1,nil,false)
 assert(t.cars[1].pendingCompound==0,'waits for the compound change')
 pl.compoundIndex=1; pl.inPitBox=false; Pits.update(t,f,cmds,p,'C',102,1,nil,false)
 assert(t.cars[1].windowStops==1,'player: compound changed under neutralisation, counted')
end

-- Moteur : neutralisation comptée en course seulement, jamais au tour de formation ni sous drapeau rouge (lu dans
-- src/engine.lua, garde contre une modification silencieuse).
tests.NEUTRAL_COUNT_NOT_IN_FORMATION_163R=function()
 local root=package.path:match('^([^;]+)/%?%.lua'); local f=assert(openFile(root..'/src/engine.lua','rb')); local src=f:read('*a'); f:close()
 local line=src:match('e%.pits%.neutralCount=([^\r\n]*)')
 assert(line,'neutralCount set in engine.lua')
 assert(line:find('not e.incidents.formation ',1,true) and line:find('not e.incidents.formationAborted',1,true),'formation lap excluded')
 assert(line:find('not e.incidents.red',1,true) and line:find('frame.started==true',1,true),'red flag and grid excluded')
end

return tests
