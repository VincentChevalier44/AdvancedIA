-- Beta 1.59.1 (rapport de bedstyboi, essais libres à Donington, 11 novembre) : dégagement hors piste dans toutes les
-- sessions, voiture coincée en piste dépannée, voiture accidentée dépassable sous drapeau, pas de drapeau noir hors
-- course. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Penalties=require('src/penalties')
local K=C.K
local tests={}
local function logged(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end

-- Instantané : voiture lente ou arrêtée hors des stands, dans toutes les sessions : distance à la trajectoire et écart
-- latéral selon le sens de la piste (signé, indépendant du cap de la voiture) ; l'écart latéral du maintien de ligne
-- reste réservé au départ ; jamais pour une voiture qui roule ni aux stands.
tests.LINE_DISTANCE_READ_159N=function()
 assert(K.offLineKmh==25 and K.trackWedgedTime==45 and K.passAfterIncident==30 and K.lineAheadMeters==5)
 local host=require('tests/host').create(true)
 local Snapshot=require('src/snapshot'); local s=Snapshot.new()
 local car=host.cars[2]; car.wheelsOutside=4; car.speedKmh=0; car.velocity={x=0,z=0}; car.position.x=20
 Snapshot.read(s,1/60,10)
 local a=s.cars[3]
 assert(a.valid and a.offtrack and not s.laneWanted,'scene: parked off track, no start lane read')
 assert(a.lineDistValid and math.abs(a.lineDist-20)<0.5,'distance to the racing line read ('..tostring(a.lineDist)..')')
 assert(a.lineLatValid and math.abs(math.abs(a.lineLat)-20)<0.5,'lateral along the track direction read ('..tostring(a.lineLat)..')')
 assert(not a.splineLatValid,'start lateral reading untouched')
 assert(not s.cars[2].lineDistValid and not s.cars[2].lineLatValid,'car at pace: not read')
 -- En travers ou à contresens : même écart (le cap de la voiture ne compte pas) ; de l'autre côté : signe opposé.
 local before=a.lineLat
 car.look={x=1,z=0}; s.cars[3].lineX=nil; Snapshot.read(s,1/60,10.1); assert(math.abs(s.cars[3].lineLat-before)<1e-6,'car sideways: same lateral')
 car.look={x=0,z=-1}; s.cars[3].lineX=nil; Snapshot.read(s,1/60,10.2); assert(math.abs(s.cars[3].lineLat-before)<1e-6,'car facing backwards: same lateral')
 car.look={x=0,z=1}; car.position.x=-20; s.cars[3].lineX=nil; Snapshot.read(s,1/60,10.3); assert(math.abs(s.cars[3].lineLat+before)<1e-6,'other side: opposite sign')
 car.position.x=20
 car.speedKmh=60; Snapshot.read(s,1/60,10.4); assert(not s.cars[3].lineDistValid and not s.cars[3].lineLatValid,'off track but rolling: not read')
 car.speedKmh=0; car.wheelsOutside=0; Snapshot.read(s,1/60,10.5); assert(s.cars[3].lineDistValid and s.cars[3].lineLatValid,'stopped on the track: read (track blocked or not)')
 car.isInPitlane=true; Snapshot.read(s,1/60,10.6); assert(not s.cars[3].lineDistValid and not s.cars[3].lineLatValid,'pit lane: not read')
end
-- Drapeau rouge « piste vraiment bloquée » (Beta 1.47) hors du départ : l'écart du départ n'est pas lu (comme en jeu), la
-- décision suit l'écart selon le sens de la piste. Voitures en travers de toute la largeur : rouge ; les mêmes rangées du
-- même côté (passage libre) : pas de rouge ; aucune mesure : pas de rouge (comme avant, jamais plus fréquent à tort).
tests.RED_BLOCKED_ANY_SESSION_159N=function()
 local function run(place,measured)
  local e,f=F.scene('C',6); C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagHold=20; E.changed(e)
  for i=2,6 do F.place(f,i,(i-1)*300,120) end; F.place(f,1,-3000,100)
  F.tick(e,f,1/60); place(f); f.senseOff=true -- mesures fixées par le test (lecture manquée comprise)
  for i=1,6 do local a=f.cars[i]; a.splineLatValid=false; a.splineLat=0; a.lineLatValid=measured; a.lineLat=measured and a.x or 0 end
  F.tick(e,f,K.redIncidentStill+2); return e
 end
 local across=function(f) F.block(f,{3,4,5},600) end
 assert(run(across,true).incidents.red,'cars across the whole width, track-direction lateral: red flag')
 assert(not run(across,false).incidents.red,'no lateral reading at all: no red flag (as before)')
 local e=run(function(f) F.place(f,3,600,0,4.5); F.place(f,4,603,0,4.6); F.place(f,5,606,0,4.4) end,true)
 assert(not e.incidents.red and logged(e,'piste encore passable')==1,'three cars parked on the same side, the other side free: no red flag')
 -- Le signe du repère n'est pas connu : les mêmes voitures de l'autre côté, même décision.
 e=run(function(f) F.place(f,3,600,0,-4.5); F.place(f,4,603,0,-4.6); F.place(f,5,606,0,-4.4) end,true)
 assert(not e.incidents.red,'same on the other side')
end
-- Incidents : voiture arrêtée hors piste, loin de la trajectoire : dégagée après K.offClearTime s avec la seule distance
-- (essais : l'écart latéral n'est jamais lu) ; sans aucune mesure : gardée, comme avant.
tests.OFF_CLEAR_ANY_SESSION_159N=function()
 local function run(valid,dist)
  local e,f=F.scene('P',3); F.place(f,2,-4000,120); f.senseOff=true -- mesures fixées par le test
  local car=F.place(f,3,1000,0); car.offtrack=true; car.wheelsOut=2; car.splineLatValid=false; car.splineLat=0
  car.lineDistValid=valid; car.lineDist=dist
  F.tick(e,f,K.offClearTime+2)
  return e.incidents.cars[3],e
 end
 local c,e=run(true,20); assert(c.dismissed and not c.incident,'practice: cleared with the distance alone')
 assert(logged(e,'incident ecarte: arretee hors piste, loin de la trajectoire')==1,'logged once')
 c=run(true,5); assert(c.incident and not c.dismissed,'5 m from the line: kept')
 c=run(false,20); assert(c.incident and not c.dismissed,'no reading at all: kept (as before)')
end
-- Voiture en incident en piste qui remue sans avancer : jamais « arrêtée » K.trackRecoverTime s de suite ; dépannée après
-- K.trackWedgedTime s dans un rayon de K.stuckRadius m.
tests.WEDGED_ON_TRACK_159N=function()
 local e,f=F.scene('P',3); F.place(f,2,-4000,120); F.place(f,3,1000,0); F.tick(e,f,3)
 local c=e.incidents.cars[3]; assert(c.incident and c.onTrack,'scene: stopped on the track')
 local t=3; local at
 while t<K.trackWedgedTime+10 do
  F.place(f,3,1000+(t%2<1 and 0 or 1),t%2<1 and 15 or 3); F.tick(e,f,0.5); t=t+0.5
  assert(c.still<K.trackRecoverTime,'never still long enough for the ordinary recovery')
  if e.commands[3].recover and not at then at=t end
 end
 assert(c.incident,'still an incident (under the obstacle speed)')
 assert(at and at>=K.trackWedgedTime-1 and at<=K.trackWedgedTime+2,'recovered after K.trackWedgedTime s ('..tostring(at)..')')
 assert(e.commands[3].recoverReason=='bloquee','reason of the journal line')
end
-- Dépassement sous drapeau : voiture accidentée ou tout juste repartie dépassable K.passAfterIncident s.
tests.PASS_AFTER_INCIDENT_159N=function()
 local p=C.defaults('P'); local now=1000
 local b={valid=true,pit=false,offtrack=false,kmh=90}
 local function c(cleared,crash) return {incident=false,holding=false,clearedAt=now-cleared,lastCrash=now-crash} end
 assert(p.yellowHold<K.passAfterIncident and p.obstacleSpeedKmh<90)
 assert(Penalties.passable(b,c(20,math.huge),p,now),'incident ended 20 s ago: may be passed')
 assert(not Penalties.passable(b,c(K.passAfterIncident+1,math.huge),p,now),'ended long ago: an ordinary car')
 assert(Penalties.passable(b,c(math.huge,20),p,now),'crashed 20 s ago, no incident raised: may be passed')
 assert(not Penalties.passable(b,c(math.huge,K.passAfterIncident+1),p,now),'crashed long ago: an ordinary car')
 p.yellowHold=45; assert(Penalties.passable(b,c(40,math.huge),p,now),'a longer yellow hold still rules')
end
-- Infractions du joueur au-delà du nombre toléré : drapeau noir en course seulement ; en essais et en qualifications, la
-- coupure des gaz continue et l'avertissement « prochaine infraction » n'est pas donné.
tests.NO_BLACK_FLAG_OUTSIDE_RACE_159N=function()
 local function run(profile)
  local e,f=F.scene(profile,3); local p=e.profiles[profile]; p.playerPenalties=true; p.penaltyDisqualify=1; p.redFlagEnabled=false
  if profile=='C' then p.neutralization='local'; p.safetyCarEscalation=false end
  E.changed(e); F.place(f,2,-4000,120); F.place(f,3,5000,0); F.tick(e,f,3)
  assert(e.incidents.cars[3].incident,'scene: car stopped on the track')
  for _=1,4 do
   local z=4300
   while z<5300 do z=z+150/3.6/60; F.place(f,1,z,150); F.tick(e,f,1/60) end
   F.place(f,1,2000,150); F.tick(e,f,K.penaltyCooldown)
  end
  return e
 end
 local e=run('P'); local t=e.penalties
 assert(t.count>=3 and t.kind=='slow' and not t.disqualified,'practice: throttle cuts go on, no black flag ('..t.count..', '..tostring(t.kind)..')')
 assert(logged(e,'disqualification du joueur')==0 and logged(e,'avertissement du joueur')==0,'practice: no disqualification line, no last warning')
 e=run('Q'); assert(e.penalties.count>=3 and not e.penalties.disqualified,'qualifying: the same')
 e=run('C'); t=e.penalties
 assert(t.count==2 and t.kind=='dq' and t.disqualified,'race: black flag beyond the allowed number ('..t.count..')')
 assert(logged(e,'avertissement du joueur')==1,'race: last warning kept')
end
return tests
