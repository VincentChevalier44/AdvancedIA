-- Beta 1.60, lot 4 (séances du pilote du 11 novembre) : « cible plus rapide » jugé sur l'écart en temps ; réouverture
-- d'une attente en course ; tests manquants des relectures. Noms terminés par _160X. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function scene(profile,n,set)
 local e,f=F.scene(profile,n or 3); local p=e.profiles[profile]
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false
 if set then set(p) end
 E.changed(e)
 return e,f
end
-- Tentative en cours de l'IA 2 sur la voiture 3, à gap m (le banc ne déplace pas les voitures : elles sont replacées).
local function attempt(profile,gap)
 local e,f=scene(profile,4,function(p) p.startDelay=0; p.startRelax=0 end)
 F.tick(e,f,0.2)
 F.place(f,1,-5000,100); F.place(f,4,5000,100); F.place(f,2,0,100,2); F.place(f,3,gap+4.4,100)
 local s=e.states[2]
 s.state='OVT_IN'; s.reason='pass'; s.since=e.time; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=gap; s.passGap0=gap; s.passName='Cible'
 s.abortSlow=0; s.passStall=0; s.passAlongside=false; s.passProgRef=gap; s.passProgTime=0; s.lastPassTarget=3; s.nextPerception=0
 s.offset=0.4; s.filtered=0.4; s.passMinTg=nil; s.passTg=0; s.passPrevV=nil
 return e,f,s
end

tests.K_160X=function()
 assert(K.abortTgGrow==0.1 and K.abortTgSpeed==10 and K.passReopenWaitRace==20 and K.abortSlowTime==3 and K.abortGap==5)
 assert(K.passReopenWaitRace>K.passReopenWait,'race: a longer wait than outside the race')
end

-- Sortie de virage : les deux voitures accélèrent ensemble, la cible (devant, donc plus vite à chaque instant) garde le
-- même écart en temps : les mètres grandissent, la vitesse relative est négative, mais elle ne s'échappe pas.
tests.ABORT_SLOW_CORNER_EXIT_160X=function()
 for _,profile in ipairs({'C','P'}) do
  local e,f,s=attempt(profile,12)
  local tg=12/(80/3.6); local t=0
  while t<K.abortSlowTime+3 do
   local v=80+12*t                      -- km/h : 12 km/h de plus par seconde
   local gap=tg*v/3.6                   -- écart en temps constant
   F.place(f,2,0,v,2); F.place(f,3,gap+4.4,v+12*tg); s.nextPerception=0
   s.passProgRef=gap; s.passProgTime=0  -- le jugement « sans progrès » (hors course) n'est pas l'objet
   F.tick(e,f,1/60); t=t+1/60
   assert(s.reason~='abort_slow',profile..': same time gap out of the corner: not « target faster » (at '..t..' s, gap '..gap..' m)')
  end
  assert(s.passTg-s.passMinTg<K.abortTgGrow,'time-gap drift stays under the threshold: '..(s.passTg-s.passMinTg))
 end
end
-- Vitesses stables, cible plus rapide : l'écart en temps grandit, l'abandon vient comme avant.
tests.ABORT_SLOW_REAL_ESCAPE_160X=function()
 for _,profile in ipairs({'C','P'}) do
  local e,f,s=attempt(profile,12)
  local t,gap=0,12
  while t<K.abortSlowTime+4 do
   gap=gap+10/3.6/60
   F.place(f,2,0,150,2); F.place(f,3,gap+4.4,160); s.nextPerception=0; s.passProgRef=gap; s.passProgTime=0
   F.tick(e,f,1/60); t=t+1/60
   if s.reason=='abort_slow' then break end
  end
  assert(s.reason=='abort_slow',profile..': target 10 km/h faster at a steady speed: ends « target faster » ('..tostring(s.reason)..')')
  assert(t>K.abortSlowTime-0.1 and t<K.abortSlowTime+2,'after about K.abortSlowTime s, got '..t)
 end
end
-- Le compte attend l'écart en temps, il ne repart pas de zéro : dès que l'écart a grandi, l'abandon est immédiat.
tests.ABORT_SLOW_WAITS_160X=function()
 local e,f,s=attempt('C',12)
 for _=1,60 do F.place(f,2,0,150,2); F.place(f,3,12+4.4,151); s.nextPerception=0; F.tick(e,f,1/60) end
 assert(s.reason~='abort_slow' and s.abortSlow>0 and s.abortSlow<=K.abortSlowTime,'1 km/h faster for 1 s: counted, held at the threshold at most')
 s.passTg=s.passMinTg+K.abortTgGrowRace-1e-6; s.abortSlow=K.abortSlowTime -- affinage 1.61 : seuil de la course
 F.place(f,2,0,150,2); F.place(f,3,12+4.4,160); s.nextPerception=0; F.tick(e,f,1/60); F.tick(e,f,1/60)
 assert(s.reason=='abort_slow','time gap grown past K.abortTgGrowRace with the count full: ends at once ('..tostring(s.reason)..')')
end
-- Relecture du lot 3 (M1) : deux voitures côte à côte sous neutralisation : seule celle dont le centre est derrière
-- prend l'autre pour cible de la file (avant : les deux, et elles se ralentissaient l'une l'autre jusqu'à 30 km/h).
tests.NEUTRAL_QUEUE_SIDE_BY_SIDE_160X=function()
 local function at(z)
  local e,f=F.scene('C',3); e.profiles.C.neutralization='fcy'; E.changed(e); F.tick(e,f,0.1)
  F.place(f,1,-5000,100)
  for _=1,120 do
   F.place(f,3,0,80,2.5); F.place(f,2,z,80,-1)
   e.incidents.neutral=true; e.incidents.neutralMode='fcy'; e.incidents.neutralSince=e.time-5; e.incidents.neutralUntil=e.time+600
   e.states[2].nextPerception=0; e.states[3].nextPerception=0
   F.tick(e,f,1/60)
  end
  return e
 end
 local e=at(-1)
 assert(e.states[2].neutralQueue==3 and e.states[3].neutralQueue~=2,'centre 1 m behind: car 2 queues on car 3, not the reverse')
 e=at(1)
 assert(e.states[3].neutralQueue==2 and e.states[2].neutralQueue~=3,'centre 1 m ahead: car 3 queues on car 2, not the reverse')
end
-- Relecture du lot 3 (S9) : passage franc seulement s'il existe un passage : cible décalée de 1,8 m, attaquant sans
-- place de l'autre côté (1,2 m de piste) : pas de départ immédiat, les règles ordinaires.
tests.FRANK_NEEDS_CLEARANCE_160X=function()
 local function run(sign,width)
  local e,f=F.scene('P',3); e.g.offsetSign=sign; e.g.sideSign=sign
  e.profiles.P.startDelay=0; e.profiles.P.startRelax=0; e.profiles.P.personalLineJitter=0; E.changed(e)
  for i=1,3 do f.cars[i].sideDot=sign end
  F.place(f,1,-5000,100); F.place(f,2,0,150); F.place(f,3,10+4.4,150); F.tick(e,f,0.2)
  local s,o=e.states[2],e.states[3]; local t=0
  while t<0.5 do
   o.state='YIELD_HOLD'; o.target=2; o.targetSide=1; o.followers[2]=true; o.yieldStart=e.time; o.holdUntil=e.time+60; o.yieldDetection=100; o.yieldMargin=5; o.offset=0.3; o.base=0
   for i=2,3 do local st=e.states[i]; st.paceCount=e.delta.bins; for b=1,e.delta.bins do st.pace[b]=150/3.6 end; st.paceMean=150/3.6 end
   F.place(f,2,0,150); F.place(f,3,10+4.4,150); s.nextPerception=0
   if width then f.cars[2].leftWidth=width; f.cars[2].rightWidth=width end
   F.tick(e,f,1/60); t=t+1/60
   if F.passing(s.state) then return t end
  end
  return math.huge
 end
 for _,sign in ipairs({-1,1}) do
  assert(run(sign,nil)<=0.2,'sign '..sign..': room on the other side: frank pass at once')
  assert(run(sign,1.2)>0.2,'sign '..sign..': no room for the attacker beside the yielding car: not a frank pass')
 end
end
-- Relecture (N4) : suffixe de Content Manager seulement après une espace.
tests.NAME_SUFFIX_AFTER_SPACE_160X=function()
 local S=require('src/snapshot')
 assert(S.stripName('G. Tsaknis (100%, 100%)')=='G. Tsaknis' and S.stripName('P. Müller (100%')=='P. Müller' and S.stripName('A B (100%, 10')=='A B')
 assert(S.stripName('Team(2')==nil and S.stripName('Team(95%, 100%)')==nil and S.stripName('Driver 7')==nil,'no space before the bracket: a name, not a suffix')
end
-- Relecture (N6) : marque d'ordre des octets en tête du manifeste de SpotterEnginer.
tests.MANIFEST_BOM_160X=function()
 local A=require('src/applier')
 local v=A.manifestVersion('\239\187\191[ABOUT]\r\nNAME=SpotterEnginer\r\nVERSION=1.3.4\r\n')
 assert(v and v[1]==1 and v[2]==3 and v[3]==4,'BOM before [ABOUT]: version still read')
 v=A.manifestVersion('[ABOUT]\nVERSION=1.3.10\n'); assert(v and v[3]==10 and A.versionBelow(v,{1,3,4})==false and A.versionBelow({1,3,3},{1,3,4})==true)
end
-- Lot 4 (journal du lot 3) : lever de pied franc dès K.frankCapMinKmh km/h. Beta 1.62 (règles par session : « jamais
-- ralentir sur la ligne en virage rapide ») : en ligne droite seulement, partout ; en virage la limite ne joue pas.
tests.FRANK_LIFT_CORNER_160X=function()
 assert(K.frankCapMinKmh==50)
 local function run(profile,blue,kmh,seconds,corner)
  local e,f=F.scene(profile,4); e.g.offsetSign=-1; e.g.sideSign=-1; E.changed(e)
  for i=1,4 do f.cars[i].sideDot=-1 end
  local s,fs=e.states[2],e.states[3]; local start=e.time-1; local lowest=math.huge
  s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=(kmh+30)/3.6 end; s.paceMean=(kmh+30)/3.6
  for _=1,seconds*60 do
   s.state='YIELD_HOLD'; s.target=3; s.targetSide=1; s.followers[3]=true; s.yieldStart=start; s.holdUntil=e.time+60; s.yieldDetection=100; s.yieldMargin=5
   s.yieldBlue=blue==true; s.offset=0.3; s.base=0
   fs.state='OVT_IN'; fs.target=2; fs.targetSide=-1; fs.passStartAt=e.time; fs.passMinGap=10; fs.passName='x'; fs.passProgRef=10; fs.passProgTime=0; fs.abortSlow=0; fs.passStall=0; fs.lastPassTarget=2
   local cap=e.commands[2].speedLimit or K.unlimitedSpeed
   local v=math.min(kmh,cap)
   F.place(f,1,-5000,0); F.place(f,2,0,v); F.place(f,3,-14.4,kmh,-2.5); F.place(f,4,3000,100)
   f.cars[2].yawRate=corner and e.profiles[profile].cornerYawRef*0.9 or 0   -- en virage : a.corner = 0,1 (src/director.lua)
   s.nextPerception=0
   F.tick(e,f,1/60)
   lowest=math.min(lowest,e.commands[2].speedLimit or K.unlimitedSpeed)
  end
  return lowest,e
 end
 local lowest=run('P',false,120,8,false)
 assert(lowest<=120-K.frankDeltaKmh+0.5,'practice, on a straight at 120 km/h: the yielding car lifts for the passer: '..lowest)
 assert(run('P',false,120,8,true)>=K.unlimitedSpeed,'practice, in a corner: it holds its speed (no cap)')
 assert(run('P',false,40,4,false)>=K.unlimitedSpeed,'below K.frankCapMinKmh: no cap')
 assert(run('C',true,120,4,true)>=K.unlimitedSpeed,'race, blue flag: never in a corner')
end
return tests
