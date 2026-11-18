-- Relecture adversariale de la 2.0.4, tour 2, angle E (cycle de vie des états, cohérence entre modules). Chargé par
-- tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local E=require('src/engine')
local Pits=require('src/pits')
local Priority=require('src/priority')
local K=C.K
local tests={}

-- E1 à E3 : heures oubliées au retour de l'horloge du moteur (K.timeWrap, 24 h) : dernière vue de l'engagement du
-- joueur (src/director.lua, ps.commitSeen), début du drapeau vert affiché (panel.startSeen), dépannage par l'app
-- (src/pits.lua, appTowAt) et classement du tour de formation (incidents, formationAt).
tests.LOCK_REVIEW204E_1=function()
 local s={commitAt=100,commitSeen=100}
 Priority.rebase(s,K.timeWrap)
 assert(s.commitSeen==100-K.timeWrap,'player commitment seen time shifted')
 local s2={}; Priority.rebase(s2,K.timeWrap); assert(s2.commitSeen==nil,'absent: untouched')
 local e,f=F.scene('C',3)
 F.tick(e,f,0.5)
 local now=e.time
 e.panel.startSeen=now-1; e.pits.cars[2].appTowAt=now-2; e.incidents.formationAt=now-3
 E.rebase(e,K.timeWrap)
 local t=e.time
 assert(math.abs((t-e.panel.startSeen)-1)<1e-6,'green flag start shifted')
 assert(math.abs((t-e.pits.cars[2].appTowAt)-2)<1e-6,'app tow time shifted')
 assert(math.abs((t-e.incidents.formationAt)-3)<1e-6,'formation ranking time shifted')
 e.panel.startSeen=nil; e.pits.cars[2].appTowAt=nil; e.incidents.formationAt=nil
 E.rebase(e,10)
 assert(e.panel.startSeen==nil and e.pits.cars[2].appTowAt==nil and e.incidents.formationAt==nil,'nil untouched')
end

-- E4 : compteur de tours du leader resté à 0 (rapport d'un joueur, 2.0.3) : les tours restants de la course (pont,
-- raceLapsLeft ; derniers tours du directeur) suivent le même repli que la fenêtre d'arrêt (tours des voitures).
tests.LOCK_REVIEW204E_2=function()
 local e,f=F.scene('C',3)
 f.sessionLaps=10; f.timedRace=false; f.leaderLaps=0
 for i=1,f.count do f.cars[i].lap=6 end
 F.tick(e,f,0.5)
 assert(Pits.leaderLaps(f)==6,'fallback laps')
 assert(e.race.known and e.race.lapsLeft==4,'laps left from the cars (got '..tostring(e.race.lapsLeft)..')')
 -- Compteur du jeu valide : lui seul compte.
 f.leaderLaps=7; F.tick(e,f,0.5)
 assert(e.race.lapsLeft==3,'game counter used when available')
end

-- E5 : plus de voitures que l'app n'en suit (K.maxCars) : dit une fois au journal (les autres sont ignorées).
tests.LOCK_REVIEW204E_3=function()
 local e,f=F.scene('C',3)
 f.countAll=K.maxCars+9
 e.session=-2; e.loggedSession=-2
 F.tick(e,f,0.2)
 local seen=0
 for i=1,K.logLines do local l=e.log[i]; if l and type(l.message)=='string' and l.message:find('voitures au-dela de '..K.maxCars..' ignorees par l app: 9 sur '..(K.maxCars+9),1,true) then seen=seen+1 end end
 assert(seen==1,'warning written once ('..seen..')')
 local e2,f2=F.scene('C',3); f2.countAll=K.maxCars; e2.session=-2; e2.loggedSession=-2; F.tick(e2,f2,0.2)
 for i=1,K.logLines do local l=e2.log[i]; assert(not (l and type(l.message)=='string' and l.message:find('ignorees par l app',1,true)),'no warning at the limit') end
end

return tests
