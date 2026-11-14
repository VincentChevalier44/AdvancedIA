-- Beta 1.63 (course du pilote à Suzuka : 70 incidents au même virage, carnage sans drapeau rouge) : zone dangereuse
-- apprise en course (src/incidents.lua dangerCut, src/engine.lua dangerCap) et drapeau rouge sur carnage. Noms
-- terminés par _163Z. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local K=C.K
local E=require('src/engine')
local Incidents=require('src/incidents')
local DK=Incidents.DK
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end

tests.DANGER_K_163Z=function()
 assert(DK.dangerBefore==150 and DK.dangerPct[1]==0.04 and DK.dangerPct[2]==0.07 and DK.dangerRaise==2)
 assert(DK.carnageCars==5 and DK.carnageSpan==200 and DK.carnageWindow==60)
end

-- Trois incidents au même endroit : zone dangereuse (une ligne), plafond de DK.dangerBefore m avant à K.hotspotMeters m
-- après, jamais ailleurs ; relevée une fois après DK.dangerRaise nouveaux incidents ; incidents étalés : rien.
tests.DANGER_ZONE_163Z=function()
 local t=Incidents.new(); local lines={}; t.note=function(level,text) lines[#lines+1]=text end
 local L=10000; local spot=0.5
 for k=1,K.hotspotCount do Incidents.hotspotNote(t,spot+k*0.0005,L,100+k,k) end
 local at=spot+0.0005*K.hotspotCount -- endroit du point armé (dernier incident)
 local function cut(m) return Incidents.dangerCut(t,(at+m/L)%1,L,120,false) end
 assert(cut(0)==DK.dangerPct[1],'at the spot: first level')
 assert(cut(-(DK.dangerBefore-10))==DK.dangerPct[1],'just inside the approach')
 assert(cut(-(DK.dangerBefore+10))==0,'before the approach: no cap')
 assert(cut(K.hotspotMeters-10)==DK.dangerPct[1] and cut(K.hotspotMeters+10)==0,'after the spot: up to hotspotMeters')
 assert(cut(2000)==0,'elsewhere on the lap: no cap')
 local function lines_(text) local n=0; for _,l in ipairs(lines) do if l:find(text,1,true) then n=n+1 end end return n end
 assert(lines_('zone dangereuse: ')==1,'created: one line')
 for k=1,DK.dangerRaise do Incidents.hotspotNote(t,at,L,130+k,10+k) end
 assert(cut(0)==DK.dangerPct[2] and lines_('zone dangereuse relevee: ')==1,'raised once')
 for k=1,4 do Incidents.hotspotNote(t,at,L,140+k,20+k) end
 assert(cut(0)==DK.dangerPct[2] and lines_('zone dangereuse relevee: ')==1,'never beyond the last level, one line')
 assert(Incidents.dangerCut(t,at,L,140+K.hotspotForget+10,false)==0,'forgotten with the difficult spot')
 local spread=Incidents.new(); spread.note=function() end
 for k=1,K.hotspotCount do Incidents.hotspotNote(spread,0.1+0.2*k,L,100+k,k) end
 assert(spread.hotspotN==0 and Incidents.dangerCut(spread,0.3,L,110,false)==0,'incidents spread over the lap: no zone')
 assert(Incidents.dangerCut(spread,0.3,L,110,true)==DK.dangerPct[1],'zone kept by track (caution): first level')
end

-- Moteur réel : IA près du point plafonnée à (1 - 4 %) de son allure apprise ; IA loin : rien ; joueur jamais.
tests.DANGER_CAP_ENGINE_163Z=function()
 local e,f=F.scene('C',4)
 local function learned(i,kmh) local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=kmh/3.6 end; s.paceMean=kmh/3.6 end
 F.place(f,1,1000,150); F.place(f,2,1000,150); F.place(f,3,3000,150); F.place(f,4,5000,150)
 F.tick(e,f,1/60)
 local L=f.length; local spot=f.cars[2].spline+100/L
 local t=e.incidents
 for k=1,K.hotspotCount do Incidents.hotspotNote(t,spot,L,e.time,10+k) end
 assert(t.hotspotN==1,'difficult spot armed')
 for i=1,4 do learned(i,200) end
 F.tick(e,f,1/60)
 local cap=200*(1-DK.dangerPct[1])
 assert(e.commands[2].speedLimit<=cap+1e-6,'AI 100 m before the spot capped ('..e.commands[2].speedLimit..')')
 assert(e.commands[3].speedLimit>cap+1,'AI far from the spot: not capped ('..e.commands[3].speedLimit..')')
 e.commands[1].speedLimit=K.unlimitedSpeed; f.cars[1].z=f.cars[2].z; f.cars[1].spline=f.cars[2].spline
 E.dangerCapTest(e,1,e.states[1],e.time)
 assert(e.commands[1].speedLimit==K.unlimitedSpeed,'player never capped')
 e.run.section_accidents=false; e.commands[2].speedLimit=K.unlimitedSpeed
 E.dangerCapTest(e,2,e.states[2],e.time)
 assert(e.commands[2].speedLimit==K.unlimitedSpeed,'Accidents section off: no cap')
end

-- Drapeau rouge sur carnage : DK.carnageCars voitures en tête-à-queue dans DK.carnageSpan m en moins de
-- DK.carnageWindow s, piste encore passable : rouge, une ligne ; une de moins : non ; étalées sur le tour : non ;
-- joueur jamais compté. Premier tour de course compris.
tests.RED_FLAG_CARNAGE_163Z=function()
 -- Relecture 1.63 (S1) : voitures en tête-à-queue puis immobilisées (encore à terre au verdict) ; drive=true : elles
 -- repartent aussitôt (glissades sans suite) : jamais de carnage.
 local function run(n,gap,withPlayer,drive,stillFor)
  local e,f=F.scene('C',8); C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagHold=20; E.changed(e)
  for i=1,8 do F.place(f,i,(i-1)*400+200,120) end
  F.tick(e,f,0.5)
  local first=withPlayer and 1 or 2
  for k=0,n-1 do local i=first+k; F.place(f,i,2000+k*gap,20,(k%2==0) and -2 or 2); f.cars[i].slip=60 end
  F.tick(e,f,1.5)
  for k=0,n-1 do local i=first+k; F.place(f,i,2000+k*gap+(drive and 60 or 0),drive and 120 or 0,(k%2==0) and -2 or 2); f.cars[i].slip=drive and 0 or 60 end
  -- Correctif 1.63 : immobilisées DK.carnageStill s au moins (drapeau rouge plus strict) ; still : durée à l'arrêt.
  F.tick(e,f,stillFor or DK.carnageStill+1)
  return e
 end
 local e=run(DK.carnageCars,30)
 assert(e.incidents.red and count(e,'drapeau rouge: carnage, '..DK.carnageCars..' voitures accidentees')==1,'carnage: red flag, logged')
 e=run(DK.carnageCars-1,30)
 assert(not e.incidents.red,'one car fewer: no red flag')
 e=run(DK.carnageCars,600)
 assert(not e.incidents.red,'spread over the lap: no red flag')
 e=run(DK.carnageCars,30,true)
 assert(not e.incidents.red,'the player is never counted')
 e=run(DK.carnageCars,30,false,true)
 assert(not e.incidents.red,'spins that drive away: no red flag')
 e=run(DK.carnageCars,30,false,false,DK.carnageStill-3)
 assert(not e.incidents.red,'1.63: stopped for less than DK.carnageStill s: no red flag yet')
 -- Voitures arrêtées hors piste (sorties au même virage) : comptées ; intactes arrêtées en piste (file) : jamais.
 local function stopped(off)
  local e2,f=F.scene('C',8); C.preset('Course','C',e2.profiles.C); e2.profiles.C.redFlagHold=20; E.changed(e2)
  for i=1,8 do F.place(f,i,(i-1)*400+200,120) end
  F.tick(e2,f,0.5)
  for k=0,DK.carnageCars-1 do local i=2+k; F.place(f,i,2000+k*40,0,(k%2==0) and -9 or 9); f.cars[i].offtrack=off end
  F.tick(e2,f,math.max(K.obstacleTime,DK.carnageStill)+1) -- 1.63 : immobilisées DK.carnageStill s
  return e2
 end
 assert(stopped(true).incidents.red,'cars stopped off track at the same corner: red flag')
 assert(not stopped(false).incidents.red,'undamaged cars stopped on the track: not a carnage')
 assert(Incidents.carnageTest~=nil)
end

return tests
