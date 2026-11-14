-- Beta 1.63 (coût par image, suite de AUDIT_FPS) : pilotage étalé des IA loin de toutes les autres sur les grandes
-- grilles (src/engine.lua, STAGGER), table des largeurs de la piste (src/snapshot.lua, WIDTHS), champs lents des IA
-- relus à 10 Hz (src/snapshot.lua, SLOW). Noms terminés par _163B. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local D=require('src/director')
local S=require('src/snapshot')
local tests={}

tests.STAGGER_CONSTANTS_163B=function()
 local st=E.STAGGER
 assert(st.enabled==false,'off by default: behaviour unchanged')
 assert(st.min2==25 and st.min3==45 and st.stride2==2 and st.stride3==3 and st.gapTime==3 and st.gapMin==60 and st.startGuard==30)
 assert(S.SLOW.period==0.1 and S.SLOW.groups==6 and S.WIDTHS.maxBins==30000)
end

-- Compte les pas du directeur par voiture pendant n images.
local function counted(e,f,n)
 local calls={}; local step=D.step
 D.step=function(e2,i,dt,now) calls[i]=(calls[i] or 0)+1; return step(e2,i,dt,now) end
 local ok,err=pcall(F.tick,e,f,n/60)
 D.step=step; assert(ok,err)
 return calls
end
-- Grille de count voitures : la 2 seule loin devant, les autres en paquet loin derrière, en file serrée.
local function grid(count)
 local e,f=F.scene('C',count)
 F.place(f,1,-9000,100)
 F.place(f,2,4000,200,0)
 for i=3,count do F.place(f,i,(i-3)*12,200,(i%2==0) and 2 or -2) end
 F.tick(e,f,0.5)
 for i=1,count do e.states[i].nextPerception=0 end
 F.tick(e,f,0.2)
 return e,f
end

-- Petite grille : tout le monde piloté à chaque image.
tests.STAGGER_SMALL_GRID_EVERY_FRAME_163B=function() E.STAGGER.enabled=true; local ok,err=pcall(function()
 local e,f=grid(20)
 local calls=counted(e,f,12)
 for i=2,20 do assert((calls[i] or 0)==12,'car '..i..' stepped every frame ('..tostring(calls[i])..')') end
 assert((e.stats.stagger or 0)==0)
 end)
 E.STAGGER.enabled=false; assert(ok,err)
end

-- Grande grille : la voiture isolée en conduite simple n'est pilotée qu'une image sur deux (trois à 45 voitures) ;
-- celles du paquet (voisin à moins de 2 s) à chaque image ; le temps sauté est rendu au pas suivant.
tests.STAGGER_FAR_CAR_ONLY_163B=function() E.STAGGER.enabled=true; local ok,err=pcall(function()
 for _,case in ipairs({{30,2},{48,3}}) do
  local count,stride=case[1],case[2]
  local e,f=grid(count)
  local s=e.states[2]
  assert(s.state=='DRIVE','isolated car in plain driving ('..s.state..')')
  assert(E.farFromAllTest(e,2,s,e.time),'isolated car far from all')
  assert(not E.farFromAllTest(e,5,e.states[5],e.time),'car in the pack is not')
  local calls=counted(e,f,12)
  assert(calls[2]==12/stride,count..' cars: isolated car stepped one frame in '..stride..' ('..tostring(calls[2])..')')
  for i=3,count do assert(calls[i]==12,count..' cars: car '..i..' in the pack stepped every frame ('..tostring(calls[i])..')') end
  assert(s.lagDt<=(stride-1)/60+1e-9,'skipped time carried to the next step')
 end
 end)
 E.STAGGER.enabled=false; assert(ok,err)
end

-- Jamais étalé : neutralisation, premier tour attentif, départ récent, voiture qui sort des stands.
tests.STAGGER_GUARDS_163B=function() E.STAGGER.enabled=true; local ok,err=pcall(function()
 local function stepsOf2(prep)
  local e,f=grid(30); prep(e,f); return counted(e,f,6)[2] or 0
 end
 local e,f=grid(30)
 assert(E.staggerStrideTest(e,f,e.time)==2,'30 cars: one frame in two')
 e.incidents.neutral=true; assert(E.staggerStrideTest(e,f,e.time)==1,'neutralisation'); e.incidents.neutral=false
 e.incidents.red=true; assert(E.staggerStrideTest(e,f,e.time)==1,'red flag'); e.incidents.red=false
 e.incidents.zoneCount=1; assert(E.staggerStrideTest(e,f,e.time)==1,'incident zone'); e.incidents.zoneCount=0
 e.fl.on=true; assert(E.staggerStrideTest(e,f,e.time)==1,'careful first lap'); e.fl.on=false
 e.formation.phase='form'; assert(E.staggerStrideTest(e,f,e.time)==1,'formation lap'); e.formation.phase='none'
 e.launchAt=e.time-5; assert(E.staggerStrideTest(e,f,e.time)==1,'recent start')
 e.launchAt=e.time-40; assert(E.staggerStrideTest(e,f,e.time)==2,'start long ago')
 assert(stepsOf2(function(e) e.states[2].pitExitUntil=e.time+10 end)==6,'pit exit')
 assert(stepsOf2(function(e) e.states[2].lapseUntil=e.time+10 end)==6,'lapse')
 end)
 E.STAGGER.enabled=false; assert(ok,err)
end

-- Plafond d'accélérateur posé par le directeur (remis à 1 à chaque image) gardé les images sautées.
tests.STAGGER_KEEPS_DIRECTOR_THROTTLE_163B=function() E.STAGGER.enabled=true; local ok,err=pcall(function()
 local e,f=grid(30)
 local s=e.states[2]; s.dirThrottle=0.7
 -- Image où la voiture 2 n'est pas pilotée : plafond repris.
 local step=D.step; local stepped=false
 D.step=function(e2,i,dt,now) if i==2 then stepped=true end; return step(e2,i,dt,now) end
 local ok,err=pcall(function()
  for _=1,2 do stepped=false; s.dirThrottle=0.7; F.tick(e,f,1/60); if not stepped then assert(e.commands[2].throttleLimit<=0.7+1e-9,'director throttle kept') return end end
  error('car 2 never skipped')
 end)
 D.step=step; assert(ok,err)
 end)
 E.STAGGER.enabled=false; assert(ok,err)
end

-- Table des largeurs : valeurs interpolées entre deux mètres, écart négligeable avec une lecture directe ; point
-- illisible : lecture directe.
tests.TRACK_WIDTH_TABLE_163B=function()
 local sides=ac.getTrackAISplineSides
 local length=5123.4
 local function truth(v) return 4+2*math.sin(v*2*math.pi*7),5+1.5*math.cos(v*2*math.pi*3) end
 ac.getTrackAISplineSides=function(v) local l,r=truth(v); return {x=l,y=r} end
 S.WIDTHS.reads=0
 local ok,err=pcall(function()
  local worst=0
  for k=0,997 do
   local v=(k*0.001003+0.00037)%1
   local l,r=S.sidesAtTest(v,length); local tl,tr=truth(v)
   worst=math.max(worst,math.abs(l-tl),math.abs(r-tr))
  end
  assert(worst<0.002,'interpolation error '..worst..' m')
  assert(S.WIDTHS.bins==5123 and S.WIDTHS.reads<=2*998,'one read per metre point at most')
  local before=S.WIDTHS.reads; S.sidesAtTest(0.5,length); S.sidesAtTest(0.5,length)
  assert(S.WIDTHS.reads-before<=2,'points kept')
  -- Fonction remplacée : table refaite ; point illisible : rien (la lecture directe prend le relais).
  ac.getTrackAISplineSides=function() error('no data') end
  local l=S.sidesAtTest(0.25,length); assert(l==nil,'unreadable point: no table value')
 end)
 ac.getTrackAISplineSides=sides; assert(ok,err)
end

-- Champs lents : carburant relu au plus tard après SLOW.period s, aussitôt au changement de tour ; position, vitesse
-- et tour lus à chaque image.
tests.SLOW_FIELDS_163B=function()
 local host=require('tests/host').create(true)
 local s=S.new()
 for k=0,12 do S.read(s,1/60,20+k/60) end
 local raw=host.cars[2]; local a=s.cars[3]
 assert(a.control,'AI car')
 raw.fuel=33; S.read(s,1/60,20.3)
 local seen=a.fuel==33
 local reads=1
 while not seen and reads<12 do S.read(s,1/60,20.3+reads/60); reads=reads+1; seen=a.fuel==33 end
 assert(seen and reads<=7,'fuel read again within the period ('..reads..' frames)')
 -- Changement de tour : relu aussitôt.
 for k=1,3 do S.read(s,1/60,21+k/60) end
 raw.fuel=21; raw.lapCount=(raw.lapCount or 0)+1; S.read(s,1/60,21.1)
 assert(a.fuel==21,'lap change: slow fields read at once')
 -- Le joueur : chaque image.
 local p=s.cars[1]; host.cars[0].bestLapTimeMs=88000; S.read(s,1/60,21.2); assert(p.bestLap==88,'player read every frame')
end

return tests
