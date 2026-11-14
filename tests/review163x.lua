-- Beta 1.63 (rapport public : drapeau blanc « dernier tour » dès l'extinction des feux, jamais effacé) : blanc natif
-- retenu seulement s'il est cohérent, durée d'affichage bornée (src/panel.lua). Noms terminés par _163X.
local F=require('tests/fixture')
local C=require('src/config')
local Panel=require('src/panel')
local K=C.K
local tests={}
local function logged(e,word)
 local q=e.log; local n=0
 for k=0,q.count-1 do local row=q[(q.head-k-1)%q.limit+1]; if row and tostring(row.message):find(word,1,true) then n=n+1 end end
 return n
end
local function race(laps,timed,leader,left)
 local e,f=F.scene('C',3)
 f.sessionLaps=laps; f.timedRace=timed; f.leaderLaps=leader; f.left=left
 f.flag=K.flagOneLapLeft; F.tick(e,f,0.5)
 return e,f
end
tests.WHITE_TIMED_START_IGNORED_163X=function()
 local e=race(0,true,0,1500)
 assert(e.panel.kind~='white','timed race, white at the start: ignored ('..e.panel.kind..')')
 assert(logged(e,'drapeau natif dernier tour: ignore')==1,'one journal line')
 local e2=race(0,true,6,120)
 assert(e2.panel.kind=='white','timed race, two minutes left: shown')
end
tests.WHITE_LAPS_RACE_163X=function()
 local e=race(10,false,3,0)
 assert(e.panel.kind~='white','10-lap race, leader on lap 4: ignored')
 local e2,f2=race(10,false,9,0)
 assert(e2.panel.kind=='white','leader on its last lap: shown')
 assert(logged(e2,'drapeau natif dernier tour: retenu')==1,'one journal line')
 e2.g.panelInfoTime=0
 assert(Panel.visible(e2.panel,e2.g,e2.panel.changedAt+Panel.WK.whiteShow-0.5),'visible within the cap')
 assert(not Panel.visible(e2.panel,e2.g,e2.panel.changedAt+Panel.WK.whiteShow+0.5),'hidden after the cap even with 0 = while it lasts')
 e2.g.panelInfoTime=3
 assert(not Panel.visible(e2.panel,e2.g,e2.panel.changedAt+3.5),'a shorter setting still applies')
 F.tick(e2,f2,0.5); assert(logged(e2,'drapeau natif dernier tour')==1,'no repeated line in the same session')
end
tests.WHITE_ONE_LAP_RACE_163X=function()
 local e=race(1,false,0,0)
 assert(e.panel.kind=='white','1-lap race: shown')
 e.g.panelInfoTime=0
 assert(not Panel.visible(e.panel,e.g,e.panel.changedAt+Panel.WK.whiteShow+0.5),'hidden after 8 s')
end
tests.WHITE_NOT_STARTED_163X=function()
 local e,f=F.scene('C',3); f.started=false; f.sessionLaps=10; f.leaderLaps=9
 f.flag=K.flagOneLapLeft; F.tick(e,f,0.5)
 assert(e.panel.kind~='white','never before the start')
end
return tests
