-- Relecture adversariale 2.0.4, domaine B (direction de course). Noms LOCK_REVIEW204B_<n>. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local K=C.K
local Incidents=require('src/incidents')
local Sanctions=require('src/sanctions')
local Quali=require('src/quali')
local Pits=require('src/pits')
local tests={}

-- B1 : après K.timeWrap s de moteur (course de 24 h), les heures encore utilisées sont décalées comme les autres.
tests.LOCK_REVIEW204B_1=function()
 local now=K.timeWrap+10
 local t=Incidents.new()
 local c=t.cars[1]
 c.rejoinNext=now+2; c.rejoinSince=now-5; c.scPassedAt=now-1; c.zoneOpenAt=now-3
 t.scOutAt=now-4; t.exitLogAt=now+1
 Incidents.rebase(t,K.timeWrap)
 local n=now-K.timeWrap
 assert(c.rejoinNext==n+2,'rejoinNext shifted ('..tostring(c.rejoinNext)..')')
 assert(c.rejoinSince==n-5,'rejoinSince shifted')
 assert(c.scPassedAt==n-1 and c.zoneOpenAt==n-3,'safety car pass and yellow zone shifted')
 assert(t.scOutAt==n-4 and t.exitLogAt==n+1,'safety car exit shifted')
 -- Valeurs « jamais » laissées telles quelles.
 local t2=Incidents.new(); Incidents.rebase(t2,K.timeWrap)
 assert(t2.cars[1].rejoinNext==-math.huge and t2.cars[1].rejoinSince==nil,'unset values untouched')
 local s=Sanctions.new()
 local sc=s.cars[1]; sc.cutAt=now-1; sc.contactAt=now-2; s.playerDoneAt=now-3
 Sanctions.rebase(s,K.timeWrap)
 assert(sc.cutAt==n-1 and sc.contactAt==n-2 and s.playerDoneAt==n-3,'player cut, contact and finish shifted')
 local s2=Sanctions.new(); Sanctions.rebase(s2,K.timeWrap); assert(s2.playerDoneAt==nil,'no finish: untouched')
 local q=Quali.new(); q.cars[1].outFrom=now-6
 Quali.rebase(q,K.timeWrap)
 assert(q.cars[1].outFrom==n-6,'out-lap ramp start shifted')
end

-- B2 : compteur de tours du meneur lu à 0 toute la course (rapport d'un joueur, 2.0.3) : le drapeau blanc natif suit
-- le même repli que la fenêtre d'arrêt (tours des voitures).
tests.LOCK_REVIEW204B_2=function()
 local e,f=F.scene('C',3)
 f.sessionLaps=10; f.timedRace=false; f.leaderLaps=0; f.left=0
 -- Tours des IA seulement (un tour du joueur qui change affiche l'info de tour du panneau, prioritaire).
 for i=1,f.count do if not f.cars[i].player then f.cars[i].lap=9 end end
 f.flag=K.flagOneLapLeft; F.tick(e,f,0.5)
 assert(Pits.leaderLaps(f)==9,'fallback laps')
 assert(e.panel.kind=='white','leader lap count stuck at 0, cars on their last lap: white shown ('..tostring(e.panel.kind)..')')
 local e2,f2=F.scene('C',3)
 f2.sessionLaps=10; f2.timedRace=false; f2.leaderLaps=0; f2.left=0
 for i=1,f2.count do if not f2.cars[i].player then f2.cars[i].lap=3 end end
 f2.flag=K.flagOneLapLeft; F.tick(e2,f2,0.5)
 assert(e2.panel.kind~='white','cars on lap 4 of 10: still ignored')
end
-- B3 : mémoire du circuit abîmée (nombre de passages infini) : bornée à la reprise, la perte aux stands reste un nombre.
tests.LOCK_REVIEW204B_3=function()
 local Pitloss=require('src/pitloss')
 local t=Pitloss.new()
 assert(Pitloss.import(t,{laneTime=20,frac=0.05,samples=math.huge}),'record accepted')
 assert(t.samples==100000,'samples capped ('..tostring(t.samples)..')')
 local r=Pitloss.export(t)
 assert(r.samples==100000 and r.laneTime==20,'export unchanged')
end
-- B7 : temps au tour arrondi au millième avant la coupe en minutes (jamais « x:60.000 »).
tests.LOCK_REVIEW204B_4=function()
 local H=require('src/hudinfo')
 local t=H.lapTime(119.9996):gsub(',','.')
 assert(t=='2:00.000','rounded to the next minute ('..t..')')
 assert(H.lapTime(59.9996):gsub(',','.')=='1:00.000','under a minute too')
 assert(H.lapTime(83.4567):gsub(',','.')=='1:23.457','ordinary lap unchanged')
end
-- B8 (signalé par la session de SpotterEngineer) : clé AdvancedIA.tyres, rule=1 seulement en vraie course (contrat v1),
-- même avec le profil Course choisi à la main en essais ou en qualifications ; format inchangé.
tests.LOCK_REVIEW204B_5=function()
 local TK=require('src/tyreskey')
 local function body(kind)
  local e,f=F.scene('C',3)
  f.type=kind; f.configType=kind; f.configTrackDay=false
  local p=C.defaults('C'); p.mandatoryStops=1; p.pitCompoundChange=true
  e.profile='C'; e.run=p; e.pits=Pits.new()
  local slot=1; for i=1,f.count do if f.cars[i].player then slot=i end end
  f.player=slot; f.cars[slot].tyreNames={[0]='S',[1]='M'}; e.pits.cars[slot].usedDry={[0]=true}
  return TK.body(e,f)
 end
 local practice,quali,race=body(1),body(2),body(3)
 assert(practice=='v=1;rule=0;used=-','practice: rule 0, nothing used ('..practice..')')
 assert(quali=='v=1;rule=0;used=-','qualifying: rule 0 ('..quali..')')
 assert(race=='v=1;rule=1;used=S','race with the rule: rule 1 ('..race..')')
end
return tests
