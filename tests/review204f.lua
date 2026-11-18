-- Beta 2.0.4, décisions du pilote du 17 novembre (essais du tour de formation, journaux 2026-11-17_13_13_54 et
-- 2026-11-17_13_20_42). Chargé par tests/extended.lua.
--  F1 : départ maintenu quand l'incident n'est pas sur la grille (entrée des stands à 540 m de la ligne, voiture partie
--       dans la voie des stands) ;
--  F2 : zigzag du tour de formation sur 90 % de la largeur, centré sur le milieu de la piste, jamais figé par le lacet
--       qu'il produit, rentré dans les virages et à l'entrée des stands ;
--  F3 : départ lancé en paires côte à côte, en quinconce légère ;
--  F4 : entrée des stands lue dans pit_lane.ai.
local F=require('tests/fixture')
local C=require('src/config')
local K=C.K
local E=require('src/engine')
local U=require('src/util')
local Antics=require('src/antics')
local AK=Antics.AK
local Snapshot=require('src/snapshot')
local tests={}

local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end

-- F1 (2026-11-17_13_13_54 : « depart arrete annule: nouvel incident » deux fois, pour une IA arrêtée à 4682 m derrière
-- une IA partie dans la voie des stands, puis pour une IA ramenée aux stands et en tête-à-queue à 4686 m ; circuit de
-- 5236 m, entrée des stands vers 4650 m) : la grille continue, une ligne « depart maintenu » par incident.
tests.LOCK_GRID_KEPT_OFF_GRID_204=function()
 local function scene()
  local e,f=F.scene('C',12); f.length=5236; C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart='standing'; E.changed(e); e.gridCaps=true
  e.pitEntry=(-560/5236)%1
  for i=1,12 do f.cars[i].position=i; F.place(f,i,-(K.gridFirst+(i-1)*K.gridPitch)-300-(i-1)*20,60) end
  F.tick(e,f,0.2); e.incidents.standing='grid'; F.tick(e,f,0.5)
  return e,f
 end
 local function spin(e,f,i,z) F.place(f,i,z,80); f.cars[i].slip=K.slipDegrees+20; F.tick(e,f,0.2); f.cars[i].kmh=30; F.tick(e,f,K.spinTime+1) end
 -- Tête-à-queue à l'entrée des stands (540 m avant la ligne) : départ maintenu.
 local e,f=scene()
 assert(e.grid.phase=='grid','grid forming')
 spin(e,f,9,-540)
 assert(e.incidents.cars[9].incident,'the spin is an incident')
 assert(e.grid.phase=='grid' and e.incidents.standing=='grid','start kept: the grid goes on')
 assert(count(e,'depart arrete annule: nouvel incident')==0,'never cancelled for an incident at the pit entry')
 assert(count(e,'depart maintenu: incident de ')==1,'noted once')
 -- Voiture dans la voie des stands : départ maintenu.
 local e2,f2=scene(); f2.cars[10].pit=true; F.tick(e2,f2,0.2)
 spin(e2,f2,10,-400)
 assert(e2.grid.phase=='grid' and count(e2,'depart arrete annule: nouvel incident')==0,'never cancelled for a car in the pit lane')
 -- Ailleurs (300 m avant la ligne) : annulé comme avant.
 local e3,f3=scene()
 spin(e3,f3,8,-300)
 assert(e3.incidents.standing=='none' and count(e3,'depart arrete annule: nouvel incident')==1,'cancelled elsewhere, as before')
end

-- F2 : une IA seule, piste de 12 m dont la trajectoire passe à 3 m du bord gauche (lw=3, rw=9), sens calibré -1.
local function lone(opts)
 opts=opts or {}
 local t=Antics.new(); t.active=true
 local a={valid=true,control=true,player=false,pit=false,finished=false,safetyCar=false,splineValid=true,kmh=120,speed=120/3.6,
  yawRate=opts.yaw or 0,spline=0.5,brake=0,name='A',leftWidth=3,rightWidth=9,width=1.85,x=0,z=3500}
 local frame={count=1,length=7000,cars={a},player=0}
 local e={incidents={formation=true,rollCall=false},runtimeG={seed=5},commands={{speedLimit=K.unlimitedSpeed}},perception={rows={{count=0,back=0,front=0,neighbors={}}}},
  states={{zone={}}},grid={aiRelease={}},stats={},log=U.newLog(200,1000,0),g={offsetSign=-1},pitEntry=opts.pitEntry or -1}
 return t,e,frame
end
local function run(t,e,frame,from,seconds)
 local lo,hi=0,0
 for k=1,math.floor(seconds*60) do Antics.weave(t,e,frame,from+k/60,1/60); lo=math.min(lo,t.form[1]); hi=math.max(hi,t.form[1]) end
 return lo,hi
end
tests.LOCK_FORMATION_WEAVE_WIDE_204=function()
 local bend=Snapshot.bendLat; local value=0
 Snapshot.bendLat=function() return value,0 end
 local ok,err=pcall(function()
  -- Lacet fort (celui que le zigzag produit) : plus jamais figé.
  local t,e,frame=lone({yaw=0.5})
  local lo,hi=run(t,e,frame,0,12)
  -- Milieu de la piste à +3 m de la trajectoire ; 90 % de la largeur, voiture comprise : 4,475 m de part et d'autre.
  local right,left=(3+0.9*6-0.925)/9,(0.9*6-0.925-3)/3
  assert(lo<=-(right-0.03) and hi>=left-0.03,string.format('wide weave centred on the track middle (%.2f to %.2f, wanted %.2f to %.2f)',lo,hi,-right,left))
  assert(lo>=-right-1e-6 and hi<=left+1e-6,'never beyond 90 % of the width')
  -- Virage (courbure au-delà de K.formWeaveBend) : retour vers la trajectoire.
  value=K.formWeaveBend*2; run(t,e,frame,12,3)
  assert(math.abs(t.form[1])<1e-6,'back to the line in a corner ('..t.form[1]..')')
  -- Entrée des stands : jamais de zigzag.
  value=0; local t2,e2,f2=lone({pitEntry=0.5}); local lo2,hi2=run(t2,e2,f2,0,6)
  assert(lo2==0 and hi2==0,'no weave at the pit entry')
 end)
 Snapshot.bendLat=bend; assert(ok,err)
end

-- F3 (2026-11-17_13_20_42 : départ lancé, voitures en file indienne) : à l'appel des files (K.rollPairFrom m), deux
-- files de part et d'autre du milieu de la piste ; une place paire se cale à côté de sa voisine de rangée, une demi-longueur
-- derrière ; sans files écartées, file d'avant.
tests.LOCK_ROLLING_PAIRS_204=function()
 local bend=Snapshot.bendLat
 Snapshot.bendLat=function(a) return 0,a.x end
 local ok,err=pcall(function()
  local function scene(lat2)
   local e,f=F.scene('C',5); f.length=5236; C.preset('Course','C',e.profiles.C); E.changed(e)
   for i=1,5 do local a=f.cars[i]; a.position=i; a.leftWidth=6; a.rightWidth=6; a.width=1.85; a.length=5 end
   -- Joueur en tête (file de gauche), place 2 une demi-longueur derrière lui (file de droite si écartée), puis la
   -- rangée suivante ; 120 km/h, à 1500 m de la ligne.
   local z={-1500,-1503,-1512,-1514.5,-1524}
   for i=1,5 do F.place(f,i,z[i],80,i%2==1 and -2 or (i==2 and lat2 or 2)) end
   F.tick(e,f,0.2)
   local t=e.incidents; t.neutral=true; t.relaunch=true; t.formation=true; t.formationKind='rolling'; t.rollCall=true; t.relaunchTravel=0.8; t.formationKmh=200
   for _=1,30 do F.tick(e,f,1/60); F.place(f,1,z[1],80,-2); F.place(f,2,z[2],80,lat2) end
   return e,f,t
  end
  local e,f,t=scene(2)
  assert(t.rollCall and e.states[2].rollPaired and e.states[3].rollPaired,'pairs formed once the files are apart')
  -- Côte à côte, une demi-longueur derrière la voisine : jamais renvoyée derrière elle (comparée plus bas à la file
  -- d'avant, qui la fait reculer).
  -- Files pas encore écartées (0,5 m) : file d'avant, la place 2 qui chevauche la voiture de devant recule.
  local e2=scene(-1.5)
  assert(not e2.states[2].rollPaired,'files not apart yet: single file as before')
  assert(e2.commands[2].yellowLimit<e.commands[2].yellowLimit-3,'and it drops back behind ('..e2.commands[2].yellowLimit..' / paired '..e.commands[2].yellowLimit..')')
 end)
 Snapshot.bendLat=bend; assert(ok,err)
end

-- F4 : entrée des stands, premier point de pit_lane.ai (x, y, z en flottants de 32 bits après l'en-tête).
tests.PIT_ENTRY_READ_204=function()
 local A=require('src/applier')
 assert(A.float32('\0\0\192\63',1)==1.5 and A.float32('\0\0\16\192',1)==-2.25 and A.float32('\0\0\0\0',1)==0,'float32')
 local saved={ac=rawget(_G,'ac'),io=rawget(_G,'io'),vec3=rawget(_G,'vec3')}
 local data=string.rep('\0',16)..'\0\0\192\63'..'\0\0\0\0'..'\0\0\16\192'..string.rep('\0',8)
 local asked=nil
 local ok,err=pcall(function()
  rawset(_G,'ac',{FolderID={ContentTracks=1},getFolder=function() return 'C:\\AC\\content\\tracks' end,getTrackLayout=function() return 'gp' end,
   worldCoordinateToTrackProgress=function(v) asked=v; return 0.9 end})
  rawset(_G,'io',{load=function(path) if path=='C:\\AC\\content\\tracks\\mel\\gp\\ai\\pit_lane.ai' then return data end return nil end})
  rawset(_G,'vec3',function(x,y,z) return {x=x,y=y,z=z} end)
  local host={}
  assert(A.pitEntry(host,'mel')==0.9,'entry read')
  assert(asked and asked.x==1.5 and asked.y==0 and asked.z==-2.25,'first point of the pit lane')
  host.pitEntryFor=nil; rawget(_G,'io').load=function() return nil end
  assert(A.pitEntry(host,'mel')==-1,'unreadable: unknown')
  assert(A.pitEntry(host,'..')==-1,'never outside the tracks folder')
 end)
 rawset(_G,'ac',saved.ac); rawset(_G,'io',saved.io); rawset(_G,'vec3',saved.vec3); assert(ok,err)
end

-- F5 (Monza, 17 novembre, replay : une quinzaine de petits coups de volant par IA ; pilote : « un droite franc, un
-- gauche franc ») : vague en trapèze, chaque côté tenu puis traversé d'un coup ; deux changements de sens par période.
tests.LOCK_FORMATION_WEAVE_FRANK_204=function()
 local bend=Snapshot.bendLat
 Snapshot.bendLat=function() return 0,0 end
 local ok,err=pcall(function()
  local t,e,frame=lone({})
  run(t,e,frame,0,2)
  local prev,dir,turns,held,n=t.form[1],0,0,0,0
  local lo,hi=0,0
  for k=1,12*60 do
   Antics.weave(t,e,frame,2+k/60,1/60); local v=t.form[1]
   local d=v>prev+1e-9 and 1 or v<prev-1e-9 and -1 or 0
   if d~=0 and dir~=0 and d~=dir then turns=turns+1 end
   if d~=0 then dir=d end
   prev=v; lo=math.min(lo,v); hi=math.max(hi,v); n=n+1
  end
  local period=t.period[1]
  assert(turns<=math.ceil(2*12/period)+1,'no small steering corrections ('..turns..' turns for a '..period..' s period)')
  -- Part du temps à plus de 90 % de l'ampleur d'un côté : tenue (un sinus : 28 %).
  local t2,e2,f2=lone({}); run(t2,e2,f2,0,2)
  for k=1,12*60 do Antics.weave(t2,e2,f2,2+k/60,1/60); local v=t2.form[1]; if v>=0.9*hi or v<=0.9*lo then held=held+1 end end
  assert(held/(12*60)>=0.45,'each side held ('..held/(12*60)..')')
 end)
 Snapshot.bendLat=bend; assert(ok,err)
end

-- F6 (capture de la grille de Monza, 17 novembre : voitures de travers ; replay : écart d'un mètre corrigé au pas dans les
-- 4 derniers mètres, 11 à 15 degrés).
-- Réécrit le 18 novembre (décision du pilote, essai de 13:33 ; replay : le décalage « tenu à l'écart réel » dans les 10
-- derniers mètres donnait lui-même un coup de volant de 10 à 17 degrés, l'écart mesuré et la consigne ne coïncidant pas) :
-- la consigne de colonne est suivie jusqu'à la place, jamais remplacée par l'écart mesuré, et gardée une fois la voiture
-- tenue (LOCK_GRID_DRIVE_TO_POSE_204).
tests.LOCK_GRID_ALIGNED_204=function()
 local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); E.changed(e); e.gridCaps=true
 for i=1,4 do f.cars[i].position=i; F.place(f,i,-(K.gridFirst+(i-1)*K.gridPitch)-300,60) end
 F.tick(e,f,0.2); e.incidents.standing='grid'; F.tick(e,f,0.5)
 local g=e.grid; local k=g.slotOf[3]; assert(k>0,'slot given')
 local slotZ=-(K.gridFirst+(k-1)*K.gridPitch)
 -- À 6 m de sa place, au pas, à 0,2 m de sa colonne : décalage tenu à son écart réel.
 local a3=f.cars[3]; local sign=e.g.offsetSign
 local lat0=g.slots[k].lateral; local want=sign<0 and -lat0 or lat0
 local ww=want*sign>0 and a3.rightWidth or a3.leftWidth
 local m=want*ww+0.2
 F.place(f,3,slotZ-6,10,m); a3.splineLat=m; a3.splineLatValid=true; f.laneWanted=true
 F.tick(e,f,1/60)
 local w=m*sign>0 and a3.rightWidth or a3.leftWidth
 assert(w>0 and not g.frozen[3],'last metres at a crawl: nothing swapped for the measured lateral')
 for _=1,3*60 do F.place(f,3,slotZ-6,10,m); a3.splineLat=m; a3.splineLatValid=true; F.tick(e,f,1/60) end
 assert(math.abs(e.commands[3].offset-want)<1e-6,'the column command is followed to the place ('..e.commands[3].offset..' / '..want..')')
 -- Encore à 2 m de sa colonne (arrivée de l'autre colonne) : jamais figée, elle finit de s'y ranger.
 local k2=g.slotOf[2]; local lat2=g.slots[k2].lateral; local want2=sign<0 and -lat2 or lat2
 local a2=f.cars[2]; local w2=want2*sign>0 and a2.rightWidth or a2.leftWidth
 local m2=want2*w2+2
 F.place(f,2,-(K.gridFirst+(k2-1)*K.gridPitch)-6,10,m2); a2.splineLat=m2; a2.splineLatValid=true
 -- 2.0.4 (LOCK_GRID_COLUMN_RAMP_204) : elle rejoint sa colonne progressivement, jamais figée en chemin.
 for _=1,5*60 do F.place(f,2,-(K.gridFirst+(k2-1)*K.gridPitch)-6,10,m2); a2.splineLat=m2; a2.splineLatValid=true; F.tick(e,f,1/60); assert(not g.frozen[2],'far from its column: never frozen') end
 assert(math.abs(e.commands[2].offset-want2)<1e-6,'far from its column: ends in its column ('..e.commands[2].offset..' / '..want2..')')
 -- Plus loin : colonne de la place, dès K.gridColumnEarly m.
 F.place(f,4,-(K.gridFirst+3*K.gridPitch)-(K.gridColumnEarly-20),60); F.tick(e,f,1/60)
 local lat=g.slots[g.slotOf[4]].lateral
 assert(math.abs(e.commands[4].offset-(e.g.offsetSign<0 and -lat or lat))<1e-6,'column taken early')
end

-- F7 (Monza, 17 novembre, départ lancé : 50 à 60 m entre les premières voitures, files de 15 à 30 m) : regroupement de
-- fin de tour, une voiture derrière la tête peut rouler K.formCatchPct % plus vite ; une place impaire vise K.rollRowGap
-- m derrière la voiture de sa file (jamais K.queueKeep de plus).
tests.LOCK_ROLLING_TIGHT_204=function()
 local Incidents=require('src/incidents')
 local e,f=F.scene('C',4); f.length=5236; E.changed(e)
 for i=1,4 do f.cars[i].position=i; F.place(f,i,-1200-(i-1)*30,100,0) end
 F.tick(e,f,0.2)
 local t=e.incidents; t.neutral=true; t.relaunch=true; t.formation=true; t.formationKind='rolling'; t.relaunchTravel=0.8; t.relaunchToLine=1200; t.formationKmh=100; t.relaunchLeader=1; t.neutralMode='fcy'
 local p=e.profiles.C
 local lead=Incidents.cap(t,f,1,p,e.delta,e.states,0)
 local back=Incidents.cap(t,f,3,p,e.delta,e.states,0)
 assert(back>=lead*1.25,'cars behind may close up ('..back..' vs '..lead..')')
 -- Tête ralentie (file étirée) : les autres rattrapent sur l'allure du tour (Monza, 17 h 06 : toutes tenues à 78 km/h).
 t.formationSlowFrom=f.cars[3].spline; t.formationSlowSpan=0.5; t.formationSlowKmh=60
 assert(Incidents.cap(t,f,3,p,e.delta,e.states,0)>=lead*1.25,'catch up on the lap pace, never on the slowed head')
 t.formationSlowFrom=nil
 -- Plus tôt dans le tour : allure de la tête pour tous.
 t.relaunchToLine=3000
 assert(Incidents.cap(t,f,3,p,e.delta,e.states,0)<=lead+1e-6,'only at the end of the lap')
end

-- F8 (décision du pilote, 17 novembre : burnouts et gros freinages avant la grille) : ralentit, repart à fond, freine
-- fort ; jamais avec une voiture collée derrière.
tests.LOCK_FORMATION_BURNOUT_204=function()
 local function scene(backGap)
  local t,e,frame=lone({})
  frame.cars[1].spline=1-1000/7000; frame.cars[1].kmh=100
  e.incidents.formationKind='formation'; e.incidents.relaunchTravel=0.8; e.incidents.relaunchLeader=0
  e.perception.rows[1]={count=backGap and 2 or 1,front=1,back=backGap and 2 or 0,neighbors={{index=2,long=12,lat=0,gap=12},backGap and {index=3,long=-backGap,lat=0,gap=backGap} or nil}}
  for i=2,3 do frame.cars[i]={valid=true,control=true,player=false,pit=false,finished=false,safetyCar=false,splineValid=true,kmh=100,speed=100/3.6,spline=0.85,name='B'..i}; e.commands[i]={speedLimit=K.unlimitedSpeed}; e.states[i]={zone={}} end
  frame.count=3
  return t,e,frame
 end
 local t,e,frame=scene(nil)
 local slow,brake=false,false
 for k=1,60*10 do
  e.commands[1].speedLimit=K.unlimitedSpeed; e.commands[1].brake=0
  if k==60*3 then e.perception.rows[1].neighbors[1].gap=K.burnGap+5 end
  if k==60*5 then e.perception.rows[1].neighbors[1].gap=K.burnGoGap-2 end
  Antics.burn(t,e,frame,k/60)
  if e.commands[1].speedLimit<=K.burnSlowKmh then slow=true end
  if (e.commands[1].brake or 0)>=K.burnBrake then brake=true end
 end
 assert(slow and brake,'slows down, launches, then brakes hard')
 -- Une ligne par voiture (ici les trois voitures sont dans la zone).
 assert(count(e,'burnout et gros freinage avant la grille')==3 and t.burnLogged[1],'one journal line per car')
 -- Voiture collée derrière : jamais.
 local t2,e2,f2=scene(3); local any=false
 for k=1,60*10 do e2.commands[1].speedLimit=K.unlimitedSpeed; Antics.burn(t2,e2,f2,k/60); if e2.commands[1].speedLimit<=K.burnSlowKmh then any=true end end
 assert(not any,'never with a car right behind')
end

-- F9 (Monza, 16 h 29 : rangées de tête jamais formées, voiture de sécurité et joueur aux stands comptés dans le
-- classement) : places des deux files comptées parmi les voitures en piste.
tests.LOCK_ROLLING_PLACES_ON_TRACK_204=function()
 local e,f=F.scene('C',5); e.profiles.C.startRealism=true; E.changed(e); F.tick(e,f,0.2)
 for i=1,5 do f.cars[i].position=i end
 f.cars[2].pit=true -- deuxième au classement, aux stands
 local t=e.antics; local inc=e.incidents
 inc.formation=true; inc.rollCall=true
 Antics.weave(t,e,f,e.time+1/60,1/60)
 assert(e.states[1].rollPlace==1 and e.states[3].rollPlace==2 and e.states[4].rollPlace==3 and e.states[5].rollPlace==4,'places among the cars on track')
 assert(e.states[2].rollPlace==nil,'never a car in the pits')
 inc.rollCall=false; Antics.weave(t,e,f,e.time+2/60,1/60)
 assert(e.states[3].rollPlace==nil,'cleared after the call')
end

-- F10 (Monza, 16 h 59 : voitures tournées vers la droite sur la grille ; la trajectoire traverse la ligne droite en biais) :
-- la colonne suit la ligne des places de la même colonne.
tests.LOCK_GRID_COLUMN_LINE_204=function()
 local Grid=require('src/grid')
 local L=5000
 local g={slots={{spline=(-10/L)%1,lateral=0.10},{spline=(-18/L)%1,lateral=0.60},{spline=(-26/L)%1,lateral=0.14},{spline=(-34/L)%1,lateral=0.64}}}
 -- Place 1 (colonne de gauche) : 0,10 sur la place, 0,14 à 16 m derrière (place 3), 0,12 à mi-chemin.
 assert(math.abs(Grid.columnLateral(g,1,0,L)-0.10)<1e-9,'on the slot')
 assert(math.abs(Grid.columnLateral(g,1,16,L)-0.14)<1e-9,'through the slot behind')
 assert(math.abs(Grid.columnLateral(g,1,8,L)-0.12)<1e-9,'column line, parallel to the slots')
 -- 2.0.4 (pilote, Monza, 18 novembre 10:53, LOCK_GRID_COLUMN_NO_EXTRAPOLATION_204) : au-delà des places de la colonne,
 -- jamais de droite prolongée (0,30 à 80 m avant) : la dernière place de la colonne ; la dernière place, sa latérale.
 assert(math.abs(Grid.columnLateral(g,1,80,L)-0.14)<1e-9,'beyond the column: its last place, never extended')
 assert(math.abs(Grid.columnLateral(g,4,16,L)-0.64)<1e-9,'last slot: its own lateral')
 assert(Grid.columnLateral(g,1,1e5,L)<=K.gridLatClamp,'bounded')
end

-- F11 (pilote, 17 h 40 : « le premier beaucoup trop loin devant », retardataires pas recollés au vert) : appel des files,
-- peloton pas groupé : la tête attend (meneur du tour et première place des files), jamais de rattrapage pour elles ; les
-- autres rattrapent.
tests.LOCK_ROLLING_LEADER_WAITS_204=function()
 local Incidents=require('src/incidents')
 local e,f=F.scene('C',4); f.length=5236; E.changed(e)
 for i=1,4 do f.cars[i].position=i; F.place(f,i,-1200-(i-1)*30,100,0) end
 F.tick(e,f,0.2)
 local t=e.incidents; t.neutral=true; t.relaunch=true; t.formation=true; t.formationKind='rolling'; t.relaunchTravel=0.8; t.relaunchToLine=1200; t.formationKmh=100; t.neutralMode='fcy'
 t.relaunchLeader=1; t.rollCall=true; t.rollFirst=2; t.rollCompact=false
 local p=e.profiles.C
 local function cap(i) return (Incidents.cap(t,f,i,p,e.delta,e.states,0)) end
 assert(cap(1)<=math.max(K.rollWaitMinKmh,100*K.rollWaitPct/100)+1e-6,'the leader waits ('..cap(1)..')')
 assert(cap(2)<=math.max(K.rollWaitMinKmh,100*K.rollWaitPct/100)+1e-6,'the first place of the files never runs away ('..cap(2)..')')
 assert(cap(3)>=125,'the others catch up ('..cap(3)..')')
 t.rollCompact=true
 assert(cap(1)>=99 and cap(2)<=101,'grouped: lap pace for the head, no catch-up for the first place')
end

-- F12 (relecture 2.0.4, banc du départ lancé, modèle simplifié de l'IA d'AC, 24 IA et le joueur en fond de grille) : au
-- drapeau vert, les IA devant le joueur sont groupées (au plus K.rollCompactMax m entre deux places), jamais d'échange de
-- place ni de file pendant l'appel, la première place reste devant. Départ arrêté avec burnouts : aucune IA renvoyée à
-- l'arrière de la grille.
tests.LOCK_ROLLING_BENCH_GROUPED_204=function()
 local run=require('tests/startbench147')
 local bend=Snapshot.bendLat; Snapshot.bendLat=function(a) return -1,a.x end
 local ok,err=pcall(function()
  local M={swaps=0,last={},spread=nil,front=nil}
  local r=run('monza','f1',{mode='app',seed=1,laps=2,formation=true,seconds=600,tune=function(e) local L=e.log; e.log=U.newLog(4000,L.rate,L.dedup); e.profiles.C.startRealism=true; e.profiles.C.raceStart='rolling'; E.changed(e) end,
   each=function(e,f,t,cars)
    if not e.incidents.rollCall then return end
    local byPlace={}
    for i=1,f.count do local p=e.states[i].rollPlace; if p then byPlace[p]=i; if M.last[i] and M.last[i]~=p then M.swaps=M.swaps+1 end; M.last[i]=p end end
    local spread=0; local k=2
    while byPlace[k] and not f.cars[byPlace[k]].player do local d=cars[byPlace[k-1]].z-cars[byPlace[k]].z; if d>spread then spread=d end; k=k+1 end
    M.spread=spread
    local best,bi=-math.huge,0; for i=1,f.count do if e.states[i].rollPlace and cars[i].z>best then best=cars[i].z; bi=i end end
    M.front=bi==byPlace[1]
   end})
  -- Assoupli le 18 novembre (décision du pilote, file stricte de la 2.0.4) : groupées selon la borne que l'app emploie
  -- elle-même pour « encore groupé » (K.rollCompactOff, 14 m ; K.rollCompactMax, 10 m, avant) : le peloton du banc, groupé
  -- dès 630 m de la ligne, roule à 71 km/h au drapeau vert (53 avant), rangées à 10,1 m (8,6 avant).
  assert(M.spread and M.spread<=K.rollCompactOff,'AI ahead of the player grouped at the green ('..tostring(M.spread)..' m)')
  assert(M.swaps==0 and M.front,'no place swap during the call, the first place stays in front ('..M.swaps..')')
  assert(r.finished==24,'every AI completes its laps')
  local r2=run('monza','f1',{mode='app',seed=1,laps=2,formation=true,seconds=600,tune=function(e) local L=e.log; e.log=U.newLog(4000,L.rate,L.dedup); e.profiles.C.startRealism=true; e.profiles.C.raceStart='formation'; E.changed(e) end})
  local n=0; for k=1,r2.log.limit do local row=r2.log[k]; if row and row.message and row.message:find('part de l arriere',1,true) then n=n+1 end end
  assert(n==0,'standing start with burnouts: no AI sent to the back of the grid ('..n..')')
 end)
 Snapshot.bendLat=bend; assert(ok,err)
end
return tests
