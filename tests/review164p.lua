-- Pont v2 (AdvancedIA 1.64, 14 novembre) : demande de SuperHUD et de SpotterEnginer (N/b164/PONT_PENALITES.md) : raison
-- de la dernière sanction de chaque IA (lastReason, après retired) et règles de la session (trackWarnings, serveLaps, à la
-- fin des champs globaux). Noms LOCK_*_164 (tests/LOCKS.md). Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local B=require('src/bridge')
local Sanctions=require('src/sanctions')
local K=C.K
local tests={}
local function out(f,i,on) local a=f.cars[i]; a.wheelsOut=on and 4 or 0; a.offtrack=on end
local function speed(f,i,kmh) local a=f.cars[i]; a.kmh=kmh; a.speed=kmh/3.6 end
local function publish(e,f)
 local o={cars={}}; for k=0,B.layout.maxCars-1 do o.cars[k]={} end
 B.publish(B.new('test'),o,e,f); return o
end
tests.LOCK_BRIDGE_V2_FIELDS_164=function()
 local L=B.layout
 -- Format : ajouts à la fin seulement, types et codes figés (copiés au caractère près par les lecteurs).
 assert(L.version==2 and L.dataKey=='ACAdvancedIA.Bridge.Data.v2','bridge v2')
 local car=L.car
 assert(car[#car][1]=='lastReason' and car[#car][2]=='int' and car[#car-1][1]=='retired','lastReason right after retired, end of the car struct')
 local g=L.fields
 assert(g[#g-1][1]=='trackWarnings' and g[#g-1][2]=='int' and g[#g][1]=='serveLaps' and g[#g][2]=='int','session rules at the end of the globals')
 local want={'trackWarning','trackLimits','cut','blueFlags','contact','jumpStart','pitSpeed','pitExit','giveBack','flag','ignored','repeated','wrongWay'}
 for k,v in ipairs(want) do assert(L.reasons[k]==v,'reason code '..k) end
 assert(L.reasons[0]=='' and #L.reasons==13 and L.reasonOther==99,'codes 0, 1-13, 99')
 -- Course : trois avertissements de limites (jamais écrits), puis une pénalité de temps (code 2).
 local e,f=F.scene('C',4); F.tick(e,f,0.1); assert(e.profile=='C')
 assert(e.run.sanTrackWarnings==3 and e.run.sanServeLaps==3)
 local function off(i) out(f,i,true); F.tick(e,f,0.5); out(f,i,false); F.tick(e,f,K.sanStrikeGap) end
 for _=1,3 do off(2) end
 assert(e.sanctions.cars[2].strikes==3 and e.sanctions.cars[2].lastReason==0,'warnings: never written')
 local o=publish(e,f); assert(o.cars[1].lastReason==0,'published 0 after warnings only')
 off(2)
 assert(e.sanctions.cars[2].time==5 and e.sanctions.cars[2].lastReason==2,'time penalty: track limits (2)')
 -- Contresens : drapeau noir (13), la dernière raison remplace la précédente pour cette voiture seulement.
 local a=f.cars[3]; speed(f,3,40); a.lz=-1
 for _=1,math.floor(6*60+0.5) do a.z=a.z-a.speed/60; a.spline=(a.z/f.length)%1; F.tick(e,f,1/60) end
 assert(e.sanctions.cars[3].dq and e.sanctions.cars[3].lastReason==13,'black flag wrong way (13)')
 o=publish(e,f)
 assert(o.cars[1].lastReason==2 and o.cars[2].lastReason==13 and o.cars[0].lastReason==0 and o.cars[3].lastReason==0,'published per car')
 assert(o.trackWarnings==3 and o.serveLaps==3,'session rules published')
 -- Dépassement sous drapeau (10), raison inconnue (99), jamais le code 1.
 Sanctions.mark(e.sanctions,4,'flag'); assert(e.sanctions.cars[4].lastReason==10,'flag offence (10)')
 Sanctions.mark(e.sanctions,4,'something new'); assert(e.sanctions.cars[4].lastReason==99,'other (99)')
 Sanctions.mark(e.sanctions,4,'trackWarning'); assert(e.sanctions.cars[4].lastReason==99,'code 1 never written')
 -- Début de séance : remis à 0.
 Sanctions.reset(e.sanctions,e.time); assert(e.sanctions.cars[2].lastReason==0 and e.sanctions.cars[3].lastReason==0,'reset at session start')
 -- Règles de la session publiées telles qu'appliquées.
 e.profiles.C.sanTrackWarnings=1; e.profiles.C.sanServeLaps=2; E.changed(e); F.tick(e,f,0.1)
 o=publish(e,f); assert(o.trackWarnings==e.run.sanTrackWarnings and o.serveLaps==e.run.sanServeLaps and o.trackWarnings==1 and o.serveLaps==2,'rules follow the session')
end
return tests
