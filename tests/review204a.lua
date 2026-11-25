-- 2.0.4 (pilote, 16 novembre ; retours de joueurs : au départ, avec 60 IA, les voitures quittent leur file et plongent
-- vers la trajectoire, tête-à-queue et carambolages) : trois causes, trois verrous.
--  1. installation neuve : sens latéral 0 / 0, aucune file tenue : -1 / -1 provisoire (révision 23), mesure maintenue ;
--  2. départ arrêté : pédale encore enfoncée au feu vert prise pour le premier freinage, files rendues au bout de 1 s ;
--  3. départ lancé : files jamais relevées au drapeau vert de l'app, toutes rendues à la trajectoire d'un coup.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local E=require('src/engine')
local Calibration=require('src/calibration')
local K=C.K
local tests={}

local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function line(e,text) for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then return r.message end end return nil end
-- Grille en deux colonnes : places impaires (pole) sur la trajectoire, paires à side × 5,5 m ; rangées de 8 m.
local function grid(n,sign,before)
 local e,f=F.scene('C',n+1); C.preset('Course','C',e.profiles.C)
 if before then before(e,f) end
 E.changed(e); E.configure(e)
 if sign then e.g.offsetSign=sign; e.g.sideSign=sign end
 f.started=false
 F.place(f,1,-3000,0)
 for k=1,n do
  local i=k+1; local col=(k%2==1) and 0.1 or 5.5
  F.place(f,i,-(k-1)*8,0,col); f.cars[i].leftWidth=7.5; f.cars[i].rightWidth=7.5
 end
 F.tick(e,f,2)
 return e,f
end
local function held(e,n) local c=0; for k=1,n do local s=e.states[k+1]; if s.laneActive and s.lane~=0 then c=c+1 end end return c end
local function offsetCars(e,n) local c=0; for k=1,n do if (e.states[k+1].laneMeters or 0)~=0 then c=c+1 end end return c end
local function drive(e,f,n,secs,kmh,brake)
 for _=1,math.floor(secs*10+0.5) do
  for k=1,n do local i=k+1; local a=f.cars[i]; F.place(f,i,a.z+kmh/36,kmh,a.x); a.brake=brake or 0 end
  F.tick(e,f,0.1,true)
 end
end
-- Feu vert : pédale de frein d'AC encore enfoncée brakeFor s.
local function green(e,f,n,brakeFor)
 f.started=true
 for k=1,n do local i=k+1; F.place(f,i,f.cars[i].z,20,f.cars[i].x); f.cars[i].brake=brakeFor>0 and 1 or 0 end
 if brakeFor>0 then F.tick(e,f,brakeFor,true) end
 for k=1,n do f.cars[k+1].brake=0 end
 F.tick(e,f,1-brakeFor,true)
end

-- 1. Installation neuve : -1 / -1 provisoire, la mesure tourne quand même ; 60 IA tenues en deux files.
tests.LOCK_START_FRESH_SIGN_204=function()
 -- Globales d'une installation neuve passées par validateGlobals et la migration : sens provisoire.
 local g=C.validateGlobals(C.globalDefaults)
 assert(g.offsetSign==0 and g.sideSign==0 and g.signProvisional==false and g.dataRevision==0,'defaults: unknown sign')
 local profiles={J=C.defaults('J'),P=C.defaults('P'),Q=C.defaults('Q'),C=C.defaults('C'),H=C.defaults('H')}
 local _,fresh,restored,provisional=C.migrate(g,profiles)
 assert(fresh==true and restored==false and provisional==true,'fresh install: provisional, not restored')
 assert(g.offsetSign==-1 and g.sideSign==-1 and g.signProvisional==true and g.dataRevision==C.dataRevision,'fresh install: -1 / -1 provisional')
 local saved=C.validateGlobals(g); assert(saved.signProvisional==true and saved.offsetSign==-1,'kept when saved')
 -- Installation existante jamais mesurée (sens 0 / 0, révision 22) : même chose ; sens déjà mesuré : intact.
 local old=C.validateGlobals(C.globalDefaults); old.dataRevision=22; old.presetsUsed=true
 local _,_,_,p2=C.migrate(old,profiles); assert(p2==true and old.offsetSign==-1 and old.signProvisional==true,'existing unmeasured install')
 -- Réécrit le 18 novembre (décision du pilote, 2.0.5 b « corriger et réparer », journal d'un joueur au sens 1 / -1) :
 -- sens déjà mesuré conforme à la convention d'AC : intact ; sens enregistré contraire : réparé (avant : gardé tel
 -- quel ; LOCK_SIGN_REPAIR_205).
 local done=C.validateGlobals(C.globalDefaults); done.dataRevision=22; done.offsetSign=-1; done.sideSign=-1
 local _,_,_,p3,r3=C.migrate(done,profiles); assert(p3==false and r3==nil and done.offsetSign==-1 and not done.signProvisional,'measured sign kept')
 local wrong=C.validateGlobals(C.globalDefaults); wrong.dataRevision=22; wrong.offsetSign=1; wrong.sideSign=1
 local _,_,_,p4,r4=C.migrate(wrong,profiles); assert(p4==false and r4=='1 / 1' and wrong.offsetSign==-1 and wrong.signProvisional==true,'stored sign against the convention: repaired')
 -- La mesure tourne tant que le sens est provisoire, plus ensuite.
 local cal=Calibration.new(); local _,f0=F.scene('C',3)
 Calibration.step(cal,f0,{},{offsetSign=-1,sideSign=-1,signProvisional=true},10)
 assert(cal.phase~='ready','provisional: measurement still wanted')
 local cal2=Calibration.new(); Calibration.step(cal2,f0,{},{offsetSign=-1,sideSign=-1,signProvisional=false},10)
 assert(cal2.phase=='ready','measured: no measurement')
 -- Départ arrêté de 60 IA avec ce sens : les voitures décalées gardent leur file.
 local n=60
 local e,f=grid(n,nil,function(e2) e2.g.offsetSign=-1; e2.g.sideSign=-1; e2.g.signProvisional=true end)
 assert(e.g.offsetSign==-1,'scene uses the provisional sign')
 assert(offsetCars(e,n)>=25,'grid: offset cars latched '..offsetCars(e,n))
 green(e,f,n,0)
 drive(e,f,n,4,120)
 assert(held(e,n)>=25,'5 s after the green: files held '..held(e,n))
 local l=line(e,'depart: maintien de ligne')
 assert(l and l:find('signe -1',1,true),'start report with sign -1: '..tostring(l))
 -- Sens inconnu (comme avant la 2.0.4) : rien n'est tenu (le verrou échoue sans la révision 23).
 local e0,f1=grid(n,0)
 green(e0,f1,n,0); drive(e0,f1,n,4,120)
 assert(held(e0,n)==0,'unknown sign: nothing held (the old failure)')
end

-- 2. Départ arrêté : pédale de frein encore enfoncée au feu vert, files tenues ; un vrai freinage les rend.
tests.LOCK_START_FILES_GRID_BRAKE_204=function()
 for _,sign in ipairs({-1,1}) do
  local n=24
  local e,f=grid(n,sign)
  local latched=offsetCars(e,n); assert(latched>=10,'grid latched '..latched)
  green(e,f,n,0.2)
  drive(e,f,n,4,120)
  assert(held(e,n)>=10,'sign '..sign..': grid brake at the green, files still held at 5 s: '..held(e,n))
  local done=0; for k=1,n do if e.states[k+1].filesDone then done=done+1 end end
  assert(done==0,'sign '..sign..': no first braking counted yet ('..done..')')
  -- Vrai premier freinage, à 120 km/h : files rendues (phase des deux files terminée).
  drive(e,f,n,0.5,120,1)
  done=0; for k=1,n do if (e.states[k+1].laneMeters or 0)~=0 and e.states[k+1].filesDone then done=done+1 end end
  assert(done>=10,'sign '..sign..': real braking ends the files ('..done..')')
 end
end

-- 3. Départ lancé : à l'appel, voitures physiquement en deux files ; au drapeau vert de l'app, files relevées et tenues.
local LENGTH=5000
local function slotZ(k) return -(K.gridFirst+(k-1)*K.gridPitch) end
tests.LOCK_START_ROLLING_FILES_204=function()
 local n=61
 local e,f=F.scene('C',n); C.preset('Course','C',e.profiles.C); e.profiles.C.raceStart='rolling'; e.profiles.C.startRealism=false; f.length=LENGTH
 e.g.offsetSign=-1; e.g.sideSign=-1
 local function place(i) return i==2 and 1 or i==3 and 2 or i==1 and 3 or i end
 for i=1,n do f.cars[i].position=place(i); F.place(f,i,slotZ(place(i)),0); f.cars[i].leftWidth=7.5; f.cars[i].rightWidth=7.5 end
 E.changed(e); e.gridCaps=true; F.tick(e,f,1/60)
 f.started=false; F.tick(e,f,1/60)
 f.started=true; F.tick(e,f,1/60)
 local t=e.incidents
 assert(t.formationKind=='rolling','rolling start chosen')
 local function roll(seconds,cond,files)
  for _=1,math.floor(seconds*60) do
   if cond() then return true end
   for i=1,f.count do
    local a=f.cars[i]
    if not a.pit then
     a.kmh=100; a.speed=100/3.6; a.z=a.z+a.speed/60; a.spline=(a.z/f.length)%1
     -- Appel du départ lancé : deux files (places impaires sur la trajectoire, paires à 5,5 m), comme src/antics.lua.
     if files and t.rollCall and i~=1 then a.x=place(i)%2==1 and 0.1 or 5.5 end
    end
   end
   F.tick(e,f,1/60)
  end
  return cond()
 end
 assert(roll(400,function() return t.rollCall end),'roll call')
 assert(roll(60,function() return not t.neutral end,true),'green flag')
 assert(e.launchAt==e.time,'green given by the app')
 local l=line(e,'depart: maintien de ligne')
 local kept=l and tonumber(l:match('maintenues (%d+)'))
 assert(kept and kept>0,'start report: files held at the green ('..tostring(l)..')')
 roll(1,function() return false end)
 local c=0; for i=2,n do local s=e.states[i]; if s.laneActive and s.lane~=0 then c=c+1 end end
 assert(c>0,'1 s after the green: files still held ('..c..')')
end
return tests
