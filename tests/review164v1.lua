-- Affinage 1.64 (Monza S12, 13 novembre) : IA accidentée relancée devant une voiture lancée hors des 120 m regardés
-- (Aasen relancé à 551,9 s à Ascari, percuté par Lopez arrivé 141 km/h plus vite) ; journal des drapeaux bleus entre IA
-- qui disait « sans la laisser passer » pendant l'approche (13 à 92 m). Noms LOCK_*_164 (tests/LOCKS.md) et *_164V1.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end

tests.K_164V1=function()
 assert(K.rejoinRaceTime==4 and K.rejoinRaceReachMax==450 and K.rejoinRaceWait==15)
end
-- S12 : Aasen arrêté en piste à 3999 m (hors premier tour) ; Lopez lancé à 300 km/h 200 m derrière : pas de relance.
local function stopped(behindAt,kmh)
 local e,f=F.scene('P',3); F.place(f,1,-4000,120); F.place(f,2,behindAt,kmh); F.place(f,3,3999,0); F.tick(e,f,3)
 return e,f,e.incidents.cars[3]
end
tests.LOCK_RACE_REJOIN_TIME_164=function()
 local e,f,c=stopped(3799,300)
 assert(e.incidents.hotspotPause~=true,'scene: not the first lap')
 assert(c.incident,'scene: stopped')
 F.place(f,2,3799,300); F.tick(e,f,1)
 assert(c.rejoinTries==0,'no restart with a car at 300 km/h 200 m behind (reaches it in 2.4 s)')
 -- 300 km/h à 380 m (4,6 s) : relance.
 F.place(f,2,3619,300); F.tick(e,f,1)
 assert(c.rejoinTries==1,'restart when the car is more than 4 s away ('..tostring(c.rejoinTries)..')')
 -- Portée bornée : 400 km/h à 460 m (plus de K.rejoinRaceReachMax m) : ne bloque pas.
 local g,h,d=stopped(3539,400); h.cars[2].kmh=400; F.tick(g,h,1)
 assert(d.rejoinTries==1,'reach bounded at K.rejoinRaceReachMax m')
 -- Affinage 1.64 z1 : la borne n'agit qu'au-delà de K.rejoinRaceReachMax/K.rejoinRaceTime m/s (405 km/h) ; vitesse lue
 -- aberrante (500 km/h, téléportation) à 460 m : sans borne elle bloquerait (556 m de portée), la borne la laisse partir.
 local g2,h2,d2=stopped(3539,500); h2.cars[2].kmh=500; F.tick(g2,h2,1)
 assert(d2.rejoinTries==1,'reach bounded at K.rejoinRaceReachMax m even for an aberrant speed')
 -- Voiture lente (60 km/h, 300 m) : règle d'avant (relance), comme REJOIN_NORMAL_UNCHANGED_164T1.
 local m,n,q=stopped(3699,60); F.tick(m,n,1)
 assert(q.rejoinTries==1,'slow car 300 m behind: restart as before')
end
tests.REJOIN_RACE_WAIT_164V1=function()
 -- Trafic continu (300 km/h, 200 m) : attente, « piste jamais libre » seulement après K.rejoinRaceWait s.
 local e,f,c=stopped(3799,300)
 local t=0
 while t<K.trackRecoverTime+2 do F.place(f,2,3799,300); F.tick(e,f,0.5); t=t+0.5 end
 assert(not c.cannot,'still waiting after K.trackRecoverTime s ('..tostring(c.cannot)..')')
 while t<K.rejoinRaceWait+4 do F.place(f,2,3799,300); F.tick(e,f,0.5); t=t+0.5 end
 assert(c.cannot=='piste jamais libre','recovered after K.rejoinRaceWait s ('..tostring(c.cannot)..')')
end
-- S12 : « sans la laisser passer » pendant l'approche (92 m, +23 km/h) : plus de ligne tant que la voiture est loin.
tests.LOCK_BLUE_LATE_CLOSE_ONLY_164=function()
 local e,f=F.scene('C',3,function(p) p.startDelay=0; p.startRelax=0; p.classNuance=false end)
 F.place(f,1,-5000,100)
 local t=0
 while t<K.blueLogTime+2 do F.rear(e,f,92,23); f.cars[3].lap=3; f.cars[2].yawRate=e.run.cornerYawRef; F.tick(e,f,1/60); t=t+1/60 end
 assert(count(e,'sans la laisser passer')==0 and (e.stats.blueAiLate or 0)==0,'far approach: no late line')
 -- Proche (30 m) et bloquée en virage : ligne après K.blueLogTime s, comme avant.
 t=0
 while t<K.blueLogTime+2 do F.rear(e,f,30,2); f.cars[3].lap=3; f.cars[2].yawRate=e.run.cornerYawRef; F.tick(e,f,1/60); t=t+1/60 end
 assert(count(e,'sans la laisser passer')==1,'close and blocked: one late line ('..count(e,'sans la laisser passer')..')')
end
return tests
