-- Beta 1.63 (contrat avec SpotterEnginer 1.3.9) : pitDue publié pendant la fenêtre « pending » (src/bridge.lua).
-- Noms terminés par _163P. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local B=require('src/bridge')
local tests={}
local function due(e,f)
 local out={cars={}}; for k=0,B.layout.maxCars-1 do out.cars[k]={} end
 B.publish(B.new('test'),out,e,f); return out.pitDue
end
tests.PIT_DUE_PENDING_163P=function()
 local e,f=F.scene('C',3); F.tick(e,f,0.5)
 local slot=f.player; assert(slot and slot>0,'player slot')
 e.run.mandatoryStops=1; e.pits.cars[slot]=e.pits.cars[slot] or {}; local own=e.pits.cars[slot]
 e.pits.state='pending'; e.pits.waived=false; own.windowStops=0
 assert(due(e,f)==1,'pending, stop still owed: 1')
 own.windowStops=1
 assert(due(e,f)==0,'pending, stop already counted (under a neutralisation): 0')
 own.windowStops=0; e.pits.waived=true
 assert(due(e,f)==0,'pending, obligation waived by rain: 0')
 e.pits.waived=false; e.run.mandatoryStops=0
 assert(due(e,f)==0,'pending, no mandatory stop: 0')
 -- Fenêtre ouverte : valeur d'avant (playerPitDue de l'hôte), inchangée.
 e.run.mandatoryStops=1; e.pits.state='open'; e.incidents.playerPitDue=1
 assert(due(e,f)==1,'open: unchanged source')
 e.incidents.playerPitDue=0
 assert(due(e,f)==0,'open: unchanged source (0)')
end
return tests
