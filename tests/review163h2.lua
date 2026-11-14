-- Affinage 1.63 (13 novembre, demandes du pilote) : tour de formation vivant (allure de la tête variable, décrochages
-- pour ouvrir un écart, freinages et zigzags avec des gardes de file), départs arrêté et lancé ; grille protégée du
-- renvoi aux stands d'AC (cmd.noRetire), file regroupée serrée sur la fin du tour. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Grid=require('src/grid')
local Formation=require('src/formation')
local Antics=require('src/antics')
local K=C.K
local U=require('src/util')
local AK=Antics.AK
local FK=Formation.FK
local GK=Grid.GK
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Une IA (indice 1) en ligne droite à 120 km/h, voisins donnés (gap, long).
local function lone(neighbors,front,back,opts)
 opts=opts or {}
 local t=Antics.new(); t.active=true
 local cars={{valid=true,control=true,player=false,pit=false,finished=false,safetyCar=false,splineValid=true,kmh=120,speed=120/3.6,yawRate=0,spline=opts.spline or 0.5,brake=0,name='A'}}
 for k,n in ipairs(neighbors) do cars[n.index]=cars[n.index] or {valid=true,control=true,player=n.index==opts.player,pit=false,finished=false,safetyCar=false,splineValid=true,kmh=n.kmh or 120,speed=(n.kmh or 120)/3.6,yawRate=0,spline=0.5,brake=0,name='B'..k} end
 local frame={count=#cars,length=7000,cars=cars,player=opts.player or 0}
 local row={count=#neighbors,back=back or 0,front=front or 0,neighbors=neighbors}
 local cmds,states,rows={}, {}, {row}
 for i=1,#cars do cmds[i]={speedLimit=K.unlimitedSpeed}; states[i]={zone={}} end
 local e={incidents={formation=true,rollCall=opts.rollCall or false},runtimeG={seed=5},commands=cmds,perception={rows=rows},states=states,grid={aiRelease={}},stats={},log=U.newLog(200,1000,0)}
 return t,e,frame
end
local function logged(e,text) local n=0; for k=1,200 do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Allure de la tête : variable au milieu du tour (bande de la graine, jamais un saut), lente en sortie et à la fin.
tests.FORMATION_PACE_BAND_163H2=function()
 local p={fcySpeedKmh=80}; local base=Formation.pace(p); local L=6000
 local lo,hi,last=math.huge,0,nil
 for x=K.formOutDistance,L*0.5,10 do
  local v=Formation.profile(p,x,L-x,L,7)
  -- Affinage 1.63 (pilote : « ils ont le droit de monter à 300 km/h ») : de la chauffe au plafond libre.
  assert(v>=base*FK.warmMult-1e-9 and v<=FK.freeKmh+1e-9,'between the warm-up pace and no limit')
  if last then assert(math.abs(v-last)<=(FK.freeKmh-base*FK.warmMult)*10/FK.bandSeg+1e-9,'no jump') end
  last=v; lo=math.min(lo,v); hi=math.max(hi,v)
 end
 assert(hi>=FK.freeKmh-1e-9 and lo<=base*FK.briskMult+1e-9,'free stretches and warm-up stretches ('..lo..' to '..hi..')')
 assert(Formation.profile(p,L-1000,1000,L,7)==base,'regrouped at the lap pace before the grid')
 assert(Formation.profile(p,100,L-100,L,7)==base*K.formSlowMult and Formation.profile(p,L-200,200,L,7)==base*K.formSlowMult,'slow out of the grid and before it')
 assert(Formation.profile(p,2000,L-2000,L)==base*K.formBriskMult,'no seed: the 1.61 pace')
end
-- Décrochage : une IA collée à celle de devant lève le pied (progressivement, jamais sous le plancher) jusqu'à l'écart
-- voulu ; une ligne au journal ; jamais avec une voiture collée derrière, jamais devant le joueur, jamais en fin de tour
-- ni pendant l'appel du départ lancé.
tests.FORMATION_DROP_BACK_163H2=function()
 local t,e,frame=lone({{index=2,long=12,lat=0,gap=8}},1,0)
 Antics.launch(t,e,frame,0,1/60)
 local at=t.dropAt[1]; assert(at>=AK.cycleMin and at<=AK.cycleMax,'first drop scheduled')
 Antics.launch(t,e,frame,at,1/60)
 assert(t.drop[1]>at and t.dropGap[1]>=AK.gapMin and t.dropGap[1]<=AK.gapMax,'drop started, gap of 3 to 6 car lengths')
 assert(logged(e,'tour de formation: A laisse un ecart pour chauffer')==1 and e.stats.formationDrop==1,'one journal line')
 local prev=e.commands[1].speedLimit
 for k=1,120 do e.commands[1].speedLimit=K.unlimitedSpeed; Antics.launch(t,e,frame,at+k/60,1/60); local v=e.commands[1].speedLimit
  assert(v>=K.formBrakeFloor and v>=120-AK.dropKmh-1e-9,'bounded lift'); if k==1 then assert(v>=120-AK.dropRate/60-1e-9,'gradual from the current speed ('..v..')') end; if prev<K.unlimitedSpeed then assert(prev-v<=AK.dropRate/60+1e-9,'progressive') end; prev=v end
 assert(prev<120-AK.dropRate*1.5,'really lifting ('..prev..')')
 frame.cars[2].kmh=120; e.perception.rows[1].neighbors[1].gap=t.dropGap[1]+1
 e.commands[1].speedLimit=K.unlimitedSpeed; Antics.launch(t,e,frame,at+2.1,1/60)
 assert(t.drop[1]==0 and e.commands[1].speedLimit==K.unlimitedSpeed,'gap opened: back to the queue at full throttle')
 assert(logged(e,'laisse un ecart')==1,'still one line per car and per formation lap')
 -- Second décrochage du même tour : compté, jamais une deuxième ligne.
 e.perception.rows[1].neighbors[1].gap=8; Antics.launch(t,e,frame,t.dropAt[1],1/60)
 assert(t.drop[1]>0 and e.stats.formationDrop==2 and logged(e,'laisse un ecart')==1,'second drop: counted, not logged again')
 -- Voiture collée derrière, joueur derrière, fin du tour, appel du départ lancé : jamais.
local function never(s,why) local t2,e2,f2=s[1],s[2],s[3]; Antics.launch(t2,e2,f2,0,1/60); Antics.launch(t2,e2,f2,t2.dropAt[1],1/60); assert(t2.drop[1]==0,why) end
 never({lone({{index=2,long=12,lat=0,gap=8},{index=3,long=-8,lat=0,gap=AK.dropBehind-2}},1,2)},'car close behind')
 never({lone({{index=2,long=12,lat=0,gap=8},{index=3,long=-40,lat=0,gap=AK.playerClear-10}},1,2,{player=3})},'player behind')
 never({lone({{index=2,long=12,lat=0,gap=8}},1,0,{spline=1-(AK.dropStopBefore-100)/7000})},'end of the lap')
 never({lone({{index=2,long=12,lat=0,gap=8}},1,0,{rollCall=true})},'roll call: orderly two files')
end
-- Gardes du tour de formation : zigzag permis avec 3 à 4 longueurs devant (avant : 25 m), jamais avec quelqu'un à côté ;
-- derrière la voiture de sécurité, l'ancienne garde (K.weaveClear) ; freinage de chauffe : AK.brakeAhead, AK.brakeBehind,
-- K.formBrakeClear avec le joueur derrière.
tests.FORMATION_GUARDS_163H2=function()
 local frame0={count=0}
 local _,e,frame=lone({{index=2,long=AK.weaveAhead+2,lat=0,gap=AK.weaveAhead-2}},1,0)
 frame.length=7000
 assert(Antics.mayWeave(e,frame,1,true),'formation lap: weave with a few lengths ahead')
 assert(not Antics.mayWeave(e,frame,1,false),'behind the safety car: the old clearance')
 e.perception.rows[1].neighbors[1].long=AK.alongside-1; assert(not Antics.mayWeave(e,frame,1,true),'never with a car alongside')
 e.perception.rows[1].neighbors[1].long=0; assert(not Antics.mayWeave(e,frame,1,true),'never with a car exactly alongside')
 e.perception.rows[1].neighbors[1].long=-(AK.weaveBehind-1); assert(not Antics.mayWeave(e,frame,1,true),'never with a car right behind')
 e.perception.rows[1].neighbors[1].long=-(AK.weaveBehind+1); assert(Antics.mayWeave(e,frame,1,true),'clear behind')
 local function brakes(neighbors,front,back,opts)
  local t2,e2,f2=lone(neighbors,front,back,opts); Antics.launch(t2,e2,f2,0,1/60); local at=t2.brakeAt[1]; Antics.launch(t2,e2,f2,at,1/60); return t2.brakeUntil[1]>at
 end
 assert(brakes({{index=2,long=-(AK.brakeBehind+8),lat=0,gap=AK.brakeBehind+4}},0,1),'warm-up brake with a gap behind it')
 assert(not brakes({{index=2,long=-(AK.brakeBehind+2),lat=0,gap=AK.brakeBehind-2}},0,1),'never with a car close behind')
 assert(not brakes({{index=2,long=-(AK.brakeBehind+8),lat=0,gap=AK.brakeBehind+4}},0,1,{player=2}),'the player behind: the 1.61 distance')
 assert(not brakes({{index=2,long=AK.brakeAhead+2,lat=0,gap=AK.brakeAhead-2}},1,0),'never close to the car ahead')
 assert(frame0.count==0)
end
-- Fin du tour : file regroupée plus serrée (FK.compactGap) ; avant, seulement au-delà de K.formationMaxGap.
tests.FORMATION_COMPACT_END_163H2=function()
 local function strung(toLine)
  local e,f=F.scene('C',4); f.length=6000; E.changed(e)
  for i=2,4 do F.place(f,i,3000-(i-2)*(FK.compactGap+10),100) end
  F.tick(e,f,0.1)
  local t=e.incidents; t.formation=true; t.relaunchTravel=0.8; t.relaunchToLine=toLine; t.formationKmh=100
  local fm=e.formation or Formation.new()
  for _=1,math.ceil(FK.compactTime*60)+2 do Formation.bunch(fm,e,f,e.time,1/60) end
  return t.formationSlowFrom~=nil
 end
 assert(strung(FK.compactFrom-100),'end of the lap: gathered tighter')
 assert(not strung(FK.compactFrom+500),'middle of the lap: the 1.62 limit')
end
-- Grille : toute IA de la grille porte la protection contre le renvoi aux stands (les deux sens latéraux), effacée
-- après l'extinction ; sans protection disponible : borne de la 1.63 ; avec : attente plus longue permise ; une ligne.
tests.GRID_NO_RETIRE_163H2=function()
 for _,sign in ipairs({-1,1}) do
  local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart='standing'; E.changed(e); e.gridCaps=true
  e.g.offsetSign=sign
  for i=1,4 do f.cars[i].position=i; F.place(f,i,-(K.gridFirst+(i-1)*K.gridPitch)-200,60) end
  F.tick(e,f,0.2)
  local t=e.incidents; t.standing='grid'; F.tick(e,f,0.1)
  assert(e.grid.phase=='grid','grid forming '..sign)
  for i=2,4 do assert(e.commands[i].noRetire==true,'AI on its way protected '..i..' '..sign) end
  assert(not e.commands[1].noRetire,'never the player')
  -- Drapeau laissé d'une image précédente : effacé à chaque image (jamais une protection qui traîne).
  e.commands[1].noRetire=true; F.tick(e,f,1/60); assert(not e.commands[1].noRetire,'stale flag cleared every frame '..sign)
  assert(count(e,'grille: 3 IA sans protection du renvoi aux stands, attente bornee')==1,'one line '..sign)
  for i=1,4 do F.place(f,i,-(K.gridFirst+(i-1)*K.gridPitch),0) end
  local went=false
  for _=1,60*40 do F.tick(e,f,1/60); if t.standing~='grid' and t.standing~='lights' then went=true; break end end
  assert(went,'lights out '..sign)
  for i=1,4 do assert(not e.commands[i].noRetire,'cleared after the start '..i) end
 end
 assert(GK.stillMaxGuarded>GK.stillMax and GK.waitFirstGuarded>K.gridWaitFirstMax,'longer waits only with the protection')
 Grid.retireGuard=true
 local ok,err=pcall(function()
  local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart='standing'; E.changed(e); e.gridCaps=true
  for i=1,3 do f.cars[i].position=i; F.place(f,i,-(K.gridFirst+(i-1)*K.gridPitch)-200,60) end
  F.tick(e,f,0.2); local t=e.incidents; t.standing='grid'; F.tick(e,f,0.1)
  F.place(f,1,-(K.gridFirst)-400,20); F.place(f,2,-(K.gridFirst+K.gridPitch),0); F.place(f,3,-(K.gridFirst+2*K.gridPitch)-300,20)
  local first=nil
  for _=1,60*12 do F.tick(e,f,1/60); first=first or Grid.firstStill(e.grid,f) end
  assert(first and t.standing=='grid','protected: the grid still waits for the late car after 12 s')
  assert(count(e,'protegees du renvoi aux stands, tenue sans limite de temps')==1,'protection noted')
 end)
 Grid.retireGuard=false; assert(ok,err)
end
-- Affinage 1.63 (13 novembre, zigzags d'environ 80 % de la largeur) : zigzag ample et lent ; voiture devant dans la
-- garde : retour vers la file AK.returnMult fois plus vite (jamais à côté d'elle au freinage du virage).
tests.FORMATION_BIG_WEAVE_163K=function()
 local t,e,frame=lone({}); e.g={offsetSign=-1}
 Antics.weave(t,e,frame,0,1/60)
 assert(t.period[1]>=AK.weavePeriodMin and t.period[1]<=AK.weavePeriodMax,'slow formation weave ('..t.period[1]..' s)')
 t.form[1]=0; t.period[1]=AK.weavePeriodMin
 for k=1,math.floor(AK.weavePeriodMin*60) do Antics.weave(t,e,frame,k/60,1/60) end
 local peak=0; for k=1,math.floor(AK.weavePeriodMin*60) do Antics.weave(t,e,frame,AK.weavePeriodMin+k/60,1/60); peak=math.max(peak,math.abs(t.form[1])) end
 assert(peak>=0.8*K.formWeaveAmp,'full weave at 120 km/h ('..peak..')')
 local t2,e2,f2=lone({{index=2,long=10,lat=0,gap=10}},1,0); e2.g={offsetSign=-1}
 t2.form[1]=0.8; Antics.weave(t2,e2,f2,1,0.1)
 assert(math.abs(t2.form[1]-(0.8-AK.weaveRate*AK.returnMult*0.1))<1e-9,'quick return to the queue ('..t2.form[1]..')')
end
-- Verrous (règle du pilote, 13 novembre : un problème corrigé ne revient jamais). Banc : tour de formation complet par
-- le vrai moteur (circuit urbain, 24 voitures de route, graine 1).
local function bench(kind,watch)
 local run=require('tests/startbench147')
 local M={drops=0,brakes=0,weaves=0,lead=0,rollMoves=0,rollFrames=0,amp=0,wide=0}; local wasD,wasB={},{}
 local r=run('street','road',{mode='app',seed=1,laps=2,formation=true,seconds=200,tune=function(e) e.profiles.C.startRealism=true; e.profiles.C.raceStart=kind; E.changed(e) end,
  each=function(e,_,_,cars)
   local inc=e.incidents
   if not inc.formation then return end
   local an=e.antics; local top=0
   for k=2,#cars do
    local d=(an.drop and an.drop[k] or 0)>0; if d and not wasD[k] then M.drops=M.drops+1 end; wasD[k]=d
    local b=an.brakeUntil[k]>e.time; if b and not wasB[k] then M.brakes=M.brakes+1 end; wasB[k]=b
    local o=math.abs(e.states[k].formOffset or 0)
    if o>0.3 and not inc.rollCall then M.weaves=M.weaves+1 end
    if not inc.rollCall then M.amp=math.max(M.amp,o); if o>0.6 then M.wide=M.wide+1 end end
    if cars[k].v*3.6>top then top=cars[k].v*3.6 end
    if inc.rollCall then M.rollFrames=M.rollFrames+1; if d or b or e.states[k].formWeave then M.rollMoves=M.rollMoves+1 end end
   end
   if top>M.lead then M.lead=top end
  end})
 M.contacts=r.contacts
 return M
end
-- Tour de formation avant un départ arrêté (journaux du 13 novembre : « depart: tour de formation (22 voitures, 100 km/h
-- en tete) », aucun freinage de chauffe, allure plate) : décrochages, freinages, zigzags, allure au-delà de 115 km/h.
tests.LOCK_FORMATION_ANTICS_163=function()
 local M=bench('formation')
 assert(M.drops>=5 and M.brakes>=10 and M.weaves>1000,'lively formation lap ('..M.drops..' drops, '..M.brakes..' brakes, '..M.weaves..' weave frames)')
 -- Affinage 1.63 (pilote, 13 novembre : plafonnés, zigzags trop petits) : sans limite de vitesse (au banc urbain :
 -- 154 km/h, 132 avant), zigzags jusqu'à environ 80 % de la largeur permise.
 assert(M.lead>145,'never capped: fastest car '..M.lead..' km/h (1.63 h2: 132)')
 assert(M.amp>=0.8 and M.wide>500,'big weaves ('..M.amp..', '..M.wide..' wide frames)')
 assert(M.contacts==0,'no contact ('..M.contacts..')')
end
-- Tour de formation avant un départ lancé (essai du pilote du 13 novembre) : le même tour vivant, puis à l'appel (deux
-- files) plus aucun décrochage, freinage ni zigzag.
tests.LOCK_ROLLING_FORMATION_163=function()
 local M=bench('rolling')
 assert(M.drops>=5 and M.brakes>=10 and M.weaves>1000,'lively rolling formation lap ('..M.drops..' drops, '..M.brakes..' brakes, '..M.weaves..' weave frames)')
 assert(M.lead>145,'never capped: '..M.lead..' km/h')
 assert(M.amp>=0.8 and M.wide>500,'big weaves ('..M.amp..', '..M.wide..' wide frames)')
 assert(M.rollFrames>0 and M.rollMoves==0,'roll call: orderly two files ('..M.rollMoves..' / '..M.rollFrames..')')
 assert(M.contacts==0,'no contact ('..M.contacts..')')
end
-- File étirée jusqu'à la grille (2026-11-13_07_18_43, circuit long de 6 km : « file etiree (46 a 53 m) », 35 s de
-- grille) : sur la fin du tour, un écart de 30 m (sous l'ancienne limite de 44 m) fait déjà ralentir la tête.
tests.LOCK_STRUNG_GRID_163=function()
 local e,f=F.scene('C',23); f.length=6003; E.changed(e)
 for i=2,23 do F.place(f,i,4800-(i-2)*12-(i==12 and 18 or 0),100) end
 F.tick(e,f,0.1)
 local t=e.incidents; t.formation=true; t.relaunchTravel=0.8; t.relaunchToLine=1200; t.formationKmh=100
 local fm=Formation.new()
 for _=1,120 do Formation.bunch(fm,e,f,e.time,1/60) end
 assert(t.formationSlowFrom~=nil and (t.formationSlowKmh or 100)<100,'end of the lap: the head waits for a 30 m gap')
 assert(count(e,'tour de formation: file etiree (')==1,'noted once')
end
-- Grille (2026-11-13_07_18_43 : cinq IA « ramenee aux stands par AC (a l arret depuis 5 a 7 s) » au feu, 9 / 22 en
-- place ; Montréal du 12 novembre : 12 s) : dès la première image de la grille, chaque IA (en approche au pas comprise)
-- porte la protection contre le renvoi d'AC ; sans protection, les feux restent dans la borne de 10 s.
tests.LOCK_GRID_RETIRE_163=function()
 local e,f=F.scene('C',23); C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart='standing'; E.changed(e); e.gridCaps=true
 for i=1,23 do f.cars[i].position=i; F.place(f,i,-(K.gridFirst+(i-1)*K.gridPitch)-300-(i-1)*15,60) end
 F.tick(e,f,0.2)
 local t=e.incidents; t.standing='grid'; F.tick(e,f,0.1)
 for i=2,6 do F.place(f,i,-(K.gridFirst+(i-1)*K.gridPitch)-10,5) end
 F.tick(e,f,1/60)
 for i=2,23 do assert(e.commands[i].noRetire==true,'protected from the first grid frame '..i) end
 assert(count(e,'grille: 22 IA sans protection du renvoi aux stands')==1,'one line for the grid')
 assert(not Grid.retireGuard and GK.stillMax<=10,'without the protection: the 10 s bound stays')
end
-- Grille après le tour de formation (2026-11-13_11_54_00, 22 IA, protection active : « grille: feux apres 61 s de
-- grille, premiere IA immobile depuis 30.0 s (8 / 22 IA en place) ») : la file arrive derrière la tête (écarts de 24 m,
-- un trou de 129 m) ; avec la protection, plus d'approche au pas : la grille se remplit en moins de GK.fillTarget s après
-- la première IA en place, et les feux attendent toutes les IA. Mouvement simple : chaque IA suit son plafond (4 m/s2
-- en accélération, 6 en freinage) sans s'approcher à moins de 7 m de la voiture devant elle.
local function fill(guard,stuck,slow)
 Grid.retireGuard=guard
 local e,f=F.scene('C',23); C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart='standing'; E.changed(e); e.gridCaps=true
 f.length=4900; f.cars[1].pit=true
 local z=-(K.gridFirst)-(K.gridFormFrom-K.gridFirst)
 for i=2,23 do f.cars[i].position=i-1; if i==13 then z=z-129 elseif i>2 then z=z-24 end; F.place(f,i,z,80) end
 f.cars[1].position=23
 F.tick(e,f,0.1)
 local t=e.incidents; t.standing='grid'
 local M={start=nil,lightsHeld=nil,n=nil,first=nil,full=nil}
 for step=1,60*130 do
  for i=2,23 do
   local a=f.cars[i]; local cmd=e.commands[i]; local v=a.speed
   local want=(cmd.stopHold and 0) or math.min(cmd.speedLimit or 1e9,300)/3.6
   if stuck and i==23 then want=0 end
   if slow and i==23 then want=math.min(want,slow/3.6) end
   for j=2,23 do local b=f.cars[j]; if j~=i and b.z>a.z and b.z-a.z<7+v*0.6 then want=math.min(want,math.max(0,b.speed-(7-(b.z-a.z))*0.5)) end end
   if v<want then v=math.min(want,v+4/60) else v=math.max(want,v-6/60) end
   a.speed=v; a.kmh=v*3.6; a.z=a.z+v/60; a.spline=(a.z/f.length)%1
  end
  F.tick(e,f,1/60)
  local g=e.grid
  if g.phase~='none' and not M.start then M.start=e.time end
  if g.firstHeldAt and not M.first then M.first=g.firstHeldAt end
  if (g.phase=='grid' or g.phase=='lights') and g.heldCount>=22 and not M.full then M.full=e.time end
  if t.standing=='lights' and not M.lightsHeld then M.lightsHeld=g.heldCount; M.lightsAt=e.time end
  if t.standing=='go' or t.standing=='none' and M.start then break end
 end
 Grid.retireGuard=false
 local s=''
 for k=1,e.log.limit do local r=e.log[k]; if r and r.message and (r.message:find('grille',1,true) or r.message:find('feux',1,true)) then s=s..string.format('%.1f %s | ',r.time or 0,r.message) end end
 for i=2,23 do local a=f.cars[i]; if not e.grid.held[i] then s=s..string.format('%d z=%.0f v=%.0f lim=%s; ',i,a.z,a.kmh,tostring(e.commands[i].speedLimit)) end end
 M.why=s
 return M,e
end
tests.LOCK_GRID_FILL_163=function()
 local M,e=fill(true)
 assert(M.first and M.first-M.start<=25,'leader in its slot without crawling ('..tostring(M.first)..' s, Imola: 31 s)')
 assert(M.first and M.full,'every AI reaches its slot ('..tostring(M.first)..', '..tostring(M.full)..') '..M.why)
 assert(M.full-M.first<=GK.fillTarget,'grid filled '..string.format('%.1f',M.full-M.first)..' s after the first AI in place (Imola: 8 / 22 after 30 s) '..M.why)
 assert(M.lightsHeld==22,'lights only with all 22 AI in place ('..tostring(M.lightsHeld)..')')
 assert(count(e,'IA pas en place aux feux')==0,'nobody missing at the lights')
 -- Une IA immobilisée loin de sa place : feux GK.stallGuarded s après la dernière arrivée, elle est nommée aux feux.
 -- Une IA lente mais qui roule : attendue (progression), feux avec les 22 IA.
 local M3=fill(true,false,50)
 assert(M3.lightsHeld==22 and M3.full and M3.full-M3.first>GK.stallGuarded,'slow AI still rolling: waited for ('..tostring(M3.lightsHeld)..') '..M3.why)
 local M2,e2=fill(true,true)
 assert(M2.lightsHeld==21 and count(e2,'grille: 1 IA pas en place aux feux : Driver_23 (place 22')==1,'stuck AI: bounded wait, named at the lights ('..tostring(M2.lightsHeld)..') '..M2.why)
end
return tests
