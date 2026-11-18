-- Beta 2.0.4, décisions du pilote du 17 novembre. Chargé par tests/extended.lua.
--  S1 : fenêtre d'arrêt fermée pendant que les stands sont fermés (neutralisation) : le joueur ne pouvait plus s'arrêter,
--       aucune pénalité (ligne au journal) ; stands ouverts : pénalité comme avant.
local F=require('tests/fixture')
local C=require('src/config')
local E=require('src/engine')
local tests={}

local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function race(closed)
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); C.applyRules('GT',e.profiles)
 local p=e.profiles.C; p.playerPenalties=true; p.pitsClosed='pitFcy'; p.mandatoryStops=1; p.pitWindowOpenPct=5; p.pitWindowClosePct=95; p.yellowEnabled=false
 E.changed(e); f.sessionLaps=100; f.leaderLaps=50
 F.tick(e,f,0.5)
 assert(e.pits.state=='open','window open')
 local t=e.incidents
 local function hold() if closed then t.neutral=true; t.neutralMode='fcy'; t.neutralSince=e.time; t.neutralUntil=e.time+1e4 end end
 hold(); F.tick(e,f,0.1)
 assert(t.pitsClosed==closed,'pits closed: '..tostring(t.pitsClosed))
 f.leaderLaps=96; hold(); F.tick(e,f,0.1)
 assert(e.pits.state=='closed','window closed')
 return e,f,t
end

tests.LOCK_PIT_CLOSED_NO_PENALTY_204=function()
 local e,f,t=race(true)
 assert(not e.penalties.stopPending,'pits closed at the window close: no penalty pending')
 assert(count(e,'stands fermes a la fermeture de la fenetre, pas de penalite')==1,'journal line written once')
 t.neutral=false; t.neutralMode=''; F.tick(e,f,2)
 assert(e.penalties.count==0 and count(e,'arret obligatoire non effectue dans la fenetre')==0,'never penalised afterwards')
 -- Stands ouverts à la fermeture de la fenêtre : pénalité comme avant.
 local e2,f2=race(false)
 F.tick(e2,f2,2)
 assert(count(e2,'arret obligatoire non effectue dans la fenetre')==1 and e2.penalties.count==1,'pits open: penalty kept')
 assert(count(e2,'pas de penalite')==0,'no excuse line when the pits were open')
end

-- S2 : demande d'arrêt tenue K.pitIgnoredLaps tours par une IA restée en piste (le jeu l'ignore) : une ligne, compteur de
-- l'accueil, demande abandonnée (plus de demande ni de place d'appel) ; une IA qui entre aux stands n'est jamais signalée.
tests.LOCK_PIT_REQUEST_IGNORED_204=function()
 local K=C.K
 local e,f=F.scene('C',6); C.preset('Course','C',e.profiles.C); C.applyRules('GT',e.profiles)
 local p=e.profiles.C; p.mandatoryStops=1; p.pitWindowOpenPct=5; p.pitWindowClosePct=95; p.yellowEnabled=false
 E.changed(e); f.sessionLaps=100; f.leaderLaps=60
 for i=2,6 do f.cars[i].lap=60 end
 F.tick(e,f,0.5)
 local called={}
 for i=2,6 do if e.commands[i].rulePit then called[#called+1]=i end end
 assert(#called>=2,'at least two AI called in: '..#called)
 local ignoredCar,goodCar=called[1],called[2]
 -- Les autres IA appelées entrent aux stands au tour suivant, la première reste en piste.
 for lap=1,K.pitIgnoredLaps do
  for i=2,6 do f.cars[i].lap=60+lap end
  if lap==1 then for k=2,#called do f.cars[called[k]].pit=true end end
  F.tick(e,f,0.5)
 end
 assert(e.pits.cars[ignoredCar].requestIgnored and e.pits.ignoredCount==1,'ignored once: '..tostring(e.pits.ignoredCount))
 assert(not e.pits.cars[goodCar].requestIgnored,'a car that entered the pits is never reported')
 assert(not e.commands[ignoredCar].rulePit,'request dropped')
 assert(count(e,'arret demande ignore par le jeu: ')==1,'one journal line')
 for i=2,6 do f.cars[i].lap=70 end; F.tick(e,f,0.5)
 assert(count(e,'arret demande ignore par le jeu: ')==1 and not e.commands[ignoredCar].rulePit,'never asked again, no repeated line')
 -- Session suivante : oublié.
 local Pits=require('src/pits'); Pits.reset(e.pits,e.time)
 assert(e.pits.ignoredCount==0 and not e.pits.cars[ignoredCar].requestIgnored,'reset with the session')
end

return tests
