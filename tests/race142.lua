-- Beta 1.42 : course complète de bout en bout (scène déterministe) qui fait jouer ensemble toutes les nouveautés :
-- stratégie individuelle (carburant, usure, arrêts), tour de sortie, blocages et usure, panne progressive, faux départ
-- servi et faux départ ignoré (drapeau noir après les tours permis), excès de vitesse dans les stands, virage coupé
-- avec gain (avertissements, pénalité de temps, coupure des gaz), contresens (drapeau noir, IA garée à son stand),
-- aspiration cassée et air sale, derniers tours, arrivée, classement corrigé, commandes rendues.
-- Le faux départ est injecté dans grid.lua (e.grid.aiJump) : sa détection pendant les feux de l'app a ses propres tests.
-- Chaque image vérifie : aucune erreur du moteur, commandes bornées, jamais de coupure des gaz en virage ni avec une
-- voiture juste derrière, aucune IA arrêtée en piste, jamais une demande d'arrêt pour le joueur.
-- Renvoie le texte du récapitulatif (empreintes, compteurs du journal) ; chargé par tests/golden142.py et par le test
-- RACE_SCENE_142 de tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local K=require('src/config').K
local L=4000
local LAPS=12
local CORNERS={{0.18,0.24},{0.42,0.47},{0.68,0.76}}
local ENTRY,BOX,EXIT=0.93,0.985,0.03
local function corner(spline) for _,c in ipairs(CORNERS) do if spline>=c[1] and spline<=c[2] then return true end end return false end
local function clamp(v,a,b) return v<a and a or v>b and b or v end
return function(laps,hook)
 laps=laps or LAPS
 local count=13
 local e,f=F.scene('C',count)
 local rp=e.profiles.C
 rp.failuresEnabled=true; rp.failureRate=1.0; rp.finalLapsEnabled=true; rp.finalLaps=3; rp.towBreakEnabled=true; rp.dirtyAirEnabled=true
 rp.strategyEnabled=true; rp.strategyUndercut=true; rp.outLapEnabled=true; rp.lockWearEnabled=true; rp.mistakesEnabled=true; rp.mistakeRate=6
 rp.sanTrackLimits=true; rp.sanCutPenalty=true; rp.sanJumpStart=true; rp.sanPitSpeed=true; rp.sanPitExit=true; rp.sanWrongWay=true
 rp.sanUnservedTime=true; rp.sanGiveBack=true; rp.sanMessages=true; rp.sanProcedureKind='drive'
 -- Beta 1.47 : scène de la 1.42 gardée telle quelle (seuil d'usure de 75 % ; nouveau défaut 30 %).
 rp.strategyTyreWearPct=75
 -- Affinage 1.62 : scène de la 1.42 gardée telle quelle, sans recherche de l'aspiration (src/director.lua, slipSeek ;
 -- tests/review162s.lua) : le virage coupé avec gain et sa pénalité de temps en dépendent. Rendue à la fin.
 local seekKeep=K.seekLat; K.seekLat=math.huge
 E.changed(e)
 f.length=L; f.sessionLaps=laps; f.timedRace=false; f.sessionMinutes=0; f.leaderLaps=0; f.sectorCount=3; f.pitsSpeedLimit=80
 f.started=true; f.finished=false; f.time=0
 local R=L/(2*math.pi)
 local car={}
 for i=1,count do
  local a=f.cars[i]
  local c={dist=-(i-1)*8,v=0,pace=49+(math.floor(i/2)%3)*0.8,phase='track',boxFor=0,parked=false,stopFor=0,wrongUntil=-1,ignore=i==8,
   speeder=i==9,sped=false,cutLap=-1,lastWear=a.wearId or 0}
  if i==6 then c.pace=53 end
  car[i]=c
  a.wearKnown=true; a.tyreWear={0,0,0,0}; a.tyreKm={0,0,0,0}; a.tyreTemp={88,88,88,88}; a.tyreOptimum={90,90,90,90}
  a.maxFuel=110; a.fuel=i%2==0 and 70 or 45; a.fuelPerLap=4.2; a.kers=-1
  a.tyresKnown=true; a.dryCompound=0; a.interCompound=-1; a.wetCompound=-1; a.compoundIndex=0; a.nativeRainTyresKnown=true; a.nativeRainTyres=false
  a.inPitBox=false; a.pit=false; a.finished=false; a.wheelsOut=0; a.offtrack=false; a.teleport=false; a.lap=0; a.sector=0; a.position=i
 end
 local dt=1/60
 local lines={}; local lastSerial=e.log.serial
 local function collect()
  local q=e.log; local n=q.serial-lastSerial; lastSerial=q.serial
  if n>q.limit then n=q.limit end
  for k=n-1,0,-1 do local r=q[(q.head-k-1)%q.limit+1]; lines[#lines+1]=r.message end
 end
 local ffi=require('ffi'); local bit=require('bit')
 local u=ffi.new('union { double d; uint32_t w[2]; }'); local h=0x12345678
 local function mix(x) h=bit.tobit(bit.bxor(bit.rol(h,5),x)*0x01000193) end
 local function num(v)
  local t=type(v)
  if t=='number' then u.d=v; mix(u.w[0]); mix(u.w[1]) elseif t=='boolean' then mix(v and 1 or 2) elseif v==nil then mix(3) else mix(4) end
 end
 local prints={}; local frame=0; local finishedAt=nil; local order=0
 local maxThrottleCut,cutFrames,levelScaled=1,0,0
 local function fail(msg) error(string.format('race142 t=%.1f s: %s',e.time,msg),0) end
 while true do
  frame=frame+1
  local t=frame*dt; f.time=t; f.simTime=t
  -- Faux départs injectés au départ (voiture 5 purge son drive-through, voiture 8 l'ignore).
  if frame==30 then e.grid.aiJump[5]=true; e.grid.aiJump[8]=true end
  local leader=0
  for i=1,count do
   local a=f.cars[i]; local c=car[i]; local cmd=e.commands[i]
   a.teleport=false
   if cmd.scPark and not c.parked then
    -- IA garée (disqualification) : ramenée à son stand par l'applicateur, immobile jusqu'à la fin.
    c.parked=true; c.phase='box'; c.v=0; c.dist=math.floor(c.dist/L)*L+BOX*L; a.teleport=true
   end
   if not a.finished and not c.parked then
    local spline=(c.dist/L)%1
    -- Voie des stands : entrée sur demande d'arrêt (jamais pour la voiture 8, qui ignore sa pénalité).
    if c.phase=='track' and cmd.rulePit and not c.ignore and spline>=ENTRY and spline<ENTRY+0.01 and i~=1 then c.phase='lane'; c.boxFor=0 end
    local target
    if c.phase=='lane' then
     target=(c.speeder and not c.sped) and 30 or 21
     if spline>=BOX and spline<BOX+0.004 then c.phase='box'; c.boxFor=0; c.v=0 end
    elseif c.phase=='box' then
     target=0; c.boxFor=c.boxFor+dt
     if c.boxFor>=2.5 and not cmd.pitHold then
      -- Service : pneus si un composé est demandé, carburant à la cible (sinon assez pour finir), rien pour un passage
      -- de pénalité.
      if not cmd.penaltyPass then
       for w=1,4 do a.tyreWear[w]=0; a.tyreKm[w]=0; a.tyreTemp[w]=45 end
       local left=math.max(0,laps-a.lap)
       if (cmd.fuelTarget or -1)>0 then a.fuel=math.max(a.fuel,math.min(a.maxFuel,cmd.fuelTarget)) else a.fuel=math.min(a.maxFuel,math.max(a.fuel,left*4.2+3)) end
      end
      c.phase='exit'; c.sped=c.sped or c.speeder
     end
    elseif c.phase=='exit' then
     target=21
     if spline>=EXIT and spline<0.5 then c.phase='track' end
    else
     target=c.pace*(corner(spline) and 0.55 or 1)
     if cmd.active then target=target*clamp((cmd.level or 1)*(cmd.levelScale or 1),0.7,1.1) end
     local th=cmd.throttleLimit or 1
     if th<1 then target=target*(0.6+0.4*th) end
     target=math.min(target,(cmd.speedLimit or K.unlimitedSpeed)/3.6,(cmd.yellowLimit or K.unlimitedSpeed)/3.6,(cmd.scSpeed or K.unlimitedSpeed)/3.6)
     if cmd.stopHold then target=0 end
     if a.fuel<=0 then target=0 end
    end
    -- Contresens de la voiture 7 au 4e tour (8 s à 40 km/h).
    local dir=1
    if i==7 and c.wrongUntil<0 and a.lap==3 and spline>0.5 then c.wrongUntil=t+8 end
    if t<c.wrongUntil then dir=-1; target=11 end
    local accel=target>c.v and 6 or 12
    c.v=c.v+clamp(target-c.v,-accel*dt,accel*dt)
    local before=c.dist
    c.dist=c.dist+dir*c.v*dt
    -- Virage coupé de la voiture 6 (la plus rapide, tours 2 à 7, deuxième virage) : 4 roues dehors, 60 m gagnés.
    local s2=(c.dist/L)%1
    if i==6 and c.phase=='track' and a.lap>=2 and a.lap<=7 and c.cutLap~=a.lap and s2>=0.44 and s2<0.445 then c.cutLap=a.lap; c.cutUntil=t+0.6 end
    -- Pendant la coupe, la position sur la ligne avance plus vite (raccourci) : 60 m gagnés en 0,6 s.
    if c.cutUntil and t<c.cutUntil then c.dist=c.dist+100*dt end
    -- Voiture 10 : sorties des limites sans gain (tours 3 à 6, ligne droite à 30 %) : avertissements puis pénalité de temps.
    if i==10 and c.phase=='track' and a.lap>=3 and a.lap<=6 and c.cutLap~=a.lap and s2>=0.30 and s2<0.305 then c.cutLap=a.lap; c.outUntil=t+0.8 end
    a.wheelsOut=((c.cutUntil and t<c.cutUntil) or (c.outUntil and t<c.outUntil)) and 4 or 0; a.offtrack=a.wheelsOut>=4
    -- Carburant et usure au mètre (avant gauche plus usé : asymétrie de fin de relais).
    local d=math.abs(c.dist-before)
    a.fuel=math.max(0,a.fuel-4.2*d/L)
    local wr=0.055*d/L
    a.tyreWear[1]=math.min(1,a.tyreWear[1]+wr*1.15); a.tyreWear[2]=math.min(1,a.tyreWear[2]+wr); a.tyreWear[3]=math.min(1,a.tyreWear[3]+wr*0.8); a.tyreWear[4]=math.min(1,a.tyreWear[4]+wr*0.75)
    for w=1,4 do a.tyreKm[w]=a.tyreKm[w]+d/1000; a.tyreTemp[w]=math.min(88,a.tyreTemp[w]+0.6*dt) end
    -- Méplat demandé par mistakes.lua (setTyresVirtualKM côté applicateur).
    if (cmd.wearId or 0)~=c.lastWear then c.lastWear=cmd.wearId or 0; local w=(cmd.wearWheel or 0)+1; a.tyreKm[w]=a.tyreKm[w]+(cmd.wearKm or 0); a.tyreWear[w]=math.min(1,a.tyreWear[w]+(cmd.wearKm or 0)*0.01375) end
   elseif c.parked then c.v=0 end
   -- Instantané de la voiture.
   local spline=(c.dist/L)%1
   a.pit=c.phase~='track'; a.inPitBox=c.phase=='box'
   a.kmh=c.v*3.6; a.speed=c.v; a.spline=spline; a.lap=math.max(0,math.floor(c.dist/L)); a.sector=math.floor(spline*3)
   local wrong=t<c.wrongUntil
   local angle=spline*math.pi*2
   a.x=R*math.sin(angle); a.z=R*math.cos(angle); a.lx=(wrong and -1 or 1)*math.cos(angle); a.lz=(wrong and 1 or -1)*math.sin(angle)
   a.yawRate=corner(spline) and c.v/90 or 0
   a.brake=(c.phase=='track' and corner((c.dist/L+0.01)%1) and not corner(spline)) and 0.8 or 0; a.gas=1-a.brake
   if a.lap>leader then leader=a.lap end
  end
  f.leaderLaps=leader
  -- Positions (distance parcourue) et arrivée : une fois le leader arrivé, chaque voiture à la ligne suivante.
  local ranks={}; for i=1,count do ranks[i]=i end
  table.sort(ranks,function(x,y) return car[x].dist>car[y].dist end)
  for p,i in ipairs(ranks) do f.cars[i].position=p end
  for i=1,count do
   local a=f.cars[i]
   if not a.finished and not car[i].parked and (a.lap>=laps or finishedAt and car[i].dist>=(math.floor(car[i].dist/L))*L and a.lap>=laps-1 and t-finishedAt>140) then
    a.finished=true; order=order+1; finishedAt=finishedAt or t
   end
  end
  if finishedAt and t-finishedAt>150 then f.finished=true end
  local ok=E.step(e,f,dt)
  collect()
  if hook then hook(e,f,t,car) end
  if e.errors~=0 then fail('erreur du moteur') end
  -- Vérifications de sécurité à chaque image.
  for i=2,count do
   local a=f.cars[i]; local c=car[i]; local cmd=e.commands[i]
   local th=cmd.throttleLimit or 1; local ls=cmd.levelScale or 1
   if th<K.throttleMin-1e-9 or th>1 then fail('accelerateur hors bornes '..i) end
   if ls<K.levelScaleMin-1e-9 or ls>1 then fail('niveau hors bornes '..i) end
   if ls<1 then levelScaled=levelScaled+1 end
   if th<0.75 and not a.pit and not a.finished and cmd.active then
    cutFrames=cutFrames+1; if th<maxThrottleCut then maxThrottleCut=th end
    if corner(a.spline) then fail('coupure des gaz en virage, voiture '..i) end
    for j=1,count do
     if j~=i then local gap=c.dist-car[j].dist; if gap>0 and gap<20 and not f.cars[j].pit then fail(string.format('coupure des gaz avec la voiture %d a %.0f m derriere la %d',j,gap,i)) end end
    end
   end
   if not a.pit and not a.finished and not c.parked and t>20 and c.v<1 and t>=c.wrongUntil then
    c.stopFor=c.stopFor+dt; if c.stopFor>5 then fail('IA arretee en piste '..i) end
   else c.stopFor=0 end
  end
  if e.commands[1].rulePit then fail('arret demande pour le joueur') end
  if frame%600==0 then
   for i=1,count do local cmd=e.commands[i]; num(cmd.active); num(cmd.level); num(cmd.levelScale); num(cmd.throttleLimit); num(cmd.rulePit); num(cmd.pitHold); num(cmd.penaltyPass); num(cmd.offset); num(car[i].dist) end
   if frame%6000==0 then prints[#prints+1]=string.format('%d:%08x',frame,bit.band(h,0xffffffff)) end
  end
  if f.finished and e.guard=='finished' then break end
  if frame>60*60*40 then fail('course jamais finie') end
 end
 -- Arrivée : commandes rendues (l'applicateur rend l'accélérateur et le niveau des voitures non commandées).
 F.tick(e,f,1)
 collect()
 for i=1,count do local cmd=e.commands[i]; if cmd.active or cmd.rulePit or cmd.pitHold or cmd.scPark or cmd.stopHold or cmd.penaltyPass then fail('commande gardee a l arrivee '..i) end end
 local function countOf(text) local n=0; for _,m in ipairs(lines) do if m:find(text,1,true) then n=n+1 end end return n end
 local keys={'strategie: ','plan ','arret demande','tour de sortie: ','usure: ','panne: ','reparee aux stands','sanction IA: ','faux depart','drive-through (',
  'sanction IA purgee','stands IA: ','limites de piste IA: ','penalite de temps','coupure des gaz','drapeau noir (contresens)','drapeau noir (penalite',
  'passage de penalite a l emplacement','aspiration: ','fin de course: ','classement corrige','arret aux stands: ','non purge a l arrivee'}
 local counts={}
 for _,k in ipairs(keys) do counts[#counts+1]=string.format('%s=%d',k:gsub('[: %(]+$',''):gsub(' ','_'),countOf(k)) end
 local st={}; for k,v in pairs(e.stats) do st[#st+1]=k..'='..v end; table.sort(st)
 local summary=string.format('race142 %d IA %d tours %d images, erreurs %d, coupure mini %.2f (%d images), niveau reduit %d images\n  journal %s\n  stats %s\n  empreintes %s',
  count-1,laps,frame,e.errors,maxThrottleCut,cutFrames,levelScaled,table.concat(counts,','),table.concat(st,','),table.concat(prints,' '))
 K.seekLat=seekKeep
 return summary,lines,countOf
end
