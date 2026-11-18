-- Relecture adversariale 2.0.4, tour 2, angle G (logique de course par scénarios). Noms LOCK_REVIEW204G_<n>.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local Engine=require('src/engine')
local tests={}

-- G1 : compteur de tours du meneur resté à 0 toute la course (cas d'un joueur, 2.0.3) : les tours restants (stratégie
-- des IA, derniers tours, pont) suivent le même repli que la fenêtre d'arrêt (tours des voitures), au lieu de rester
-- figés au total de la course.
tests.LOCK_REVIEW204G_1=function()
 local e,f=F.scene('C',3)
 f.sessionLaps=26; f.timedRace=false; f.leaderLaps=0; f.started=true
 for i=1,f.count do f.cars[i].lap=10 end
 Engine.raceInfo(e,f)
 assert(e.race.known and e.race.lapsLeft==16,'laps left from the cars ('..tostring(e.race.lapsLeft)..')')
 assert(e.race.leaderLaps==10,'leader laps kept with the race info')
 -- Compteur du jeu valable : il fait foi.
 f.leaderLaps=12; Engine.raceInfo(e,f)
 assert(e.race.lapsLeft==14,'game counter used when available')
 -- Hors course commencée : inconnu, rien de gardé.
 f.started=false; Engine.raceInfo(e,f)
 assert(not e.race.known and e.race.lapsLeft==-1 and e.race.leaderLaps==nil,'not racing: unknown')
end

return tests
