-- Banc des départs (Beta 1.47, test START_SCENES_147 et rapport de validation) : 24 IA (+ le joueur en fond de grille) sur quatre géométries de circuit et
-- quatre plateaux, premier tour complet, modèle simplifié de l'IA d'AC piloté par les commandes de l'app.
-- Modèle de l'IA d'AC (hypothèses, documentées dans le rapport) :
--  * profil de vitesse : vitesse maximale et vitesse de chaque virage (adhérence latérale mécanique + aérodynamique de la
--    catégorie, rayon du virage), freinage planifié à 85 % de la décélération maximale, plus tôt avec la prudence
--    (décélération planifiée divisée par 1 + 0,15 x (prudence - 1)) ; niveau de l'IA : vitesses de virage et freinage ;
--  * suivi : écart voulu 2 m + v x 0,10 s x prudence x (1,25 - 0,5 x agressivité), vitesse de la voiture de devant perçue
--    avec 0,25 s de retard, correction 1,5 /s ; freinage jusqu'à la décélération maximale ;
--  * dépassement par l'IA d'AC : retenue 1,5 s en ligne droite, file voisine libre : changement de file ; voiture
--    arrêtée devant : contournement si la file voisine est libre ;
--  * commandes de l'app : niveau, prudence, agressivité, frein (fraction de la décélération maximale), limite
--    d'accélérateur, limite de vitesse (zone jaune, file), décalage latéral.
-- Contacts : par paire, au début du contact (pare-chocs qui se touchent dans la même file) ; « dû à l'app » quand la
-- voiture touchée avait, dans la seconde précédente, un frein, un lever de pied ou une limite de vitesse de l'app.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local K=C.K
local abs,min,max,sqrt,floor=math.abs,math.min,math.max,math.sqrt,math.floor
-- Virages : {entrée (m après la ligne), longueur (m), vitesse d'une F1 (km/h)}.
local TRACKS={
 monza={length=5793,width=12,corners={{900,150,80},{1350,400,270},{2050,120,95},{2550,150,175},{2850,120,165},{3600,250,200},{4800,400,210}}},
 spa={length=7004,width=12,corners={{250,100,65},{750,300,290},{2050,200,130},{2700,120,110},{3600,300,230},{4300,150,160},{5600,300,300},{6650,150,90}}},
 short={length=4600,width=12,corners={{400,150,140},{620,100,120},{900,300,240},{1500,120,100},{2100,200,190},{2800,150,90},{3500,250,210},{4200,120,110}}},
 street={length=3500,width=9,corners={{300,60,85},{520,60,95},{800,60,75},{1250,80,110},{1600,60,70},{2100,90,130},{2600,60,90},{3100,60,80}}},
}
local CLASSES={
 f1={vmax=340,a0=12,decel=45,lat=20,aero=0.30,drag=0.0014},
 lmp2={vmax=320,a0=10,decel=32,lat=14,aero=0.20,drag=0.0012},
 gt3={vmax=275,a0=7.5,decel=22,lat=12,aero=0.08,drag=0.0007},
 gt4={vmax=250,a0=6,decel=17,lat=11,aero=0.04,drag=0.0006},
 road={vmax=195,a0=4.5,decel=10,lat=9,aero=0,drag=0.0004},
}
local SETS={
 f1={{24,'f1'}},gt3={{24,'gt3'}},road={{24,'road'}},
 mixed={{8,'lmp2'},{8,'gt3'},{8,'gt4'}},
}
local function frac(x) return x-floor(x) end
local function cornerSpeed(cl,R) local a,b=cl.aero,cl.lat; return min(cl.vmax/3.6*0.98,(a*R+sqrt((a*R)^2+4*R*b))/2) end
-- options : mode 'app' | 'off' ; pile=true : deux voitures en tête-à-queue arrêtées au premier virage ; seconds.
return function(trackName,setName,opts)
 opts=opts or {}
 local T=TRACKS[trackName]; local L=T.length
 local n=0; for _,g in ipairs(SETS[setName]) do n=n+g[1] end
 local app=opts.mode~='off'
 local e,f=F.scene('C',n+1); C.preset('Course','C',e.profiles.C); E.changed(e)
 if opts.tune then opts.tune(e) end
 f.length=L; f.started=false
 -- Virages : rayon d'après la vitesse d'une F1.
 local corners={}
 for k,c in ipairs(T.corners) do
  local v=c[3]/3.6; local R=v*v/(20+0.30*v)
  corners[k]={at=c[1],len=c[2],R=R,sign=k%2==0 and 1 or -1}
 end
 local cars={}
 local slot=0
 local order={}
 for _,g in ipairs(SETS[setName]) do for _=1,g[1] do slot=slot+1; order[slot]=g[2] end end
 -- Joueur en fond de grille (même modèle, jamais piloté par l'app).
 order[n+1]=order[n]
 local idx=0
 for k=2,n+1 do idx=idx+1; cars[k]={grid=idx} end
 cars[1]={grid=n+1}
 for k=1,n+1 do
  local c=cars[k]; local cl=CLASSES[order[c.grid]]
  local sd=(opts.seed or 0)*7.137
  c.cl=cl; c.cls=order[c.grid]; c.level=0.94+0.06*frac(math.sin(k*12.9898+sd)*43758.5453)
  -- Perturbations de l'IA d'AC : temps de réaction au départ, lancement plus ou moins bon, allure qui ondule en ligne
  -- droite, rapprochement de la trajectoire idéale (côté intérieur du virage suivant) au premier tour.
  c.react=0.15+0.45*frac(math.sin(k*78.233+sd)*43758.5453); c.launch=0.9+0.2*frac(math.sin(k*39.425+sd)*24634.6345); c.phase=k*1.7+sd
  c.vc={}; for j,cr in ipairs(corners) do c.vc[j]=cornerSpeed(cl,cr.R) end
  local z=-8-(c.grid-1)*8; local x=(c.grid%2==1) and -1.6 or 1.6
  F.place(f,k,z,0,x); local a=f.cars[k]
  a.id=c.cls..'_'..k; a.name=c.cls..k; a.lap=0; a.spline=(z/L)%1; a.width=1.85; a.length=4.6
  a.leftWidth=T.width/2; a.rightWidth=T.width/2; a.brake=0; a.gas=0; a.collided=false; a.collidedWith=-1
  c.z=z; c.x=x; c.lane=x; c.v=0; c.hist={}; c.hp=0; c.held=0; c.appUntil=-1; c.spun=false
  for h=1,15 do c.hist[h]=0 end
  e.states[k].nextPerception=0
 end
 f.cars[1].player=true; f.cars[1].control=false
 for k=2,n+1 do f.cars[k].player=false; f.cars[k].control=true end
 -- Grille : une seconde à l'arrêt, puis départ.
 for _=1,60 do F.tick(e,f,1/60) end
 f.started=true
 local dt=1/60; local t=0
 local R={radarStraight=0,radarBefore=0,liftStraight=0,liftBefore=0,maxBrakeStraight=0,contacts=0,contactsApp=0,contactsFirst=0,
  side=0,sideApp=0,avoid=0,avoidPack=0,avoidWave=0,yellowCars=0,yellowFar=0,yellowFarTime=0,deficit=0,deficitN=0,lap1Mean=0,lap1Last=0,
  defend=0,brakeOnsets=0,held=0,appSlow=0}
 local pair={}; local spair={}; local lastBrake,lastLift,lastAvoid,yellowSeen={}, {}, {}, {}
 local firstBrakeAt={}
 local spinAt=nil; local spinners={}
 local incidentZ=nil
 local lapDone={}; local lapSum,lapN=0,0
 local seconds=opts.seconds or 240
 -- Beta 1.60 (tranche E) : opts.laps tours (défaut 1) ; opts.formation : place de chaque voiture publiée (classement),
 -- joueur qui tient l'allure du tour de formation (il garde sa place, comme demandé à l'écran).
 local laps=opts.laps or 1
 local function profile(c,z,caution)
  local zz=z%L; local cl=c.cl
  local lvl=c.L or c.level
  local vmax=cl.vmax/3.6*(0.97+0.03*lvl)
  local b=0.85*cl.decel*(0.9+0.1*lvl)/(1+0.15*(caution-1))
  local v=vmax; local binding=false; local inCorner=false; local yaw=0
  for j,cr in ipairs(corners) do
   local vc=c.vc[j]*(0.88+0.12*lvl)
   local d=(cr.at-zz)%L
   if (zz-cr.at)%L<cr.len then inCorner=true; if vc<v then v=vc end; yaw=cr.sign*vc/cr.R
   elseif d<2500 then local lim=sqrt(vc*vc+2*b*d); if lim<v then v=lim; binding=true end end
  end
  return v,binding,inCorner,yaw
 end
 local function sameLane(a,b) return abs(a.x-b.x)<1.85 end
 -- Allure seule (sans trafic ni app) de chaque voiture sur son premier tour, au mètre : référence du déficit.
 for k=1,n+1 do
  local c=cars[k]; local z,v,tt=c.z,0,0; local solo={}; local z0=c.z
  while z<L do
   local vp=profile(c,z,1)
   local cl=c.cl
   if vp>v then v=min(vp,v+cl.a0*max(0.15,1-(v/(cl.vmax/3.6))^2)*dt) else v=max(vp,v-cl.decel*dt) end
   z=z+v*dt; tt=tt+dt; local m=floor(z-z0); if m>=0 then solo[m]=v end
  end
  c.solo=solo; c.z0=z0; c.soloLap=tt
 end
 while t<seconds do
  t=t+dt
  -- Ordre sur la piste (devant d'abord).
  local ord={}; for k=1,n+1 do ord[#ord+1]=k end
  table.sort(ord,function(p,q) return cars[p].z>cars[q].z end)
  local packV,packN=0,0
  local blockedNow={}
  for k=1,n+1 do if not cars[k].spun then packV=packV+cars[k].v; packN=packN+1 end end
  packV=packN>0 and packV/packN or 0
  -- Carambolage : quand la 5e voiture entre dans le premier virage, la 5e et la 6e partent en tête-à-queue.
  if opts.pile and not spinAt and cars[ord[5]].z>=corners[1].at+10 then
   -- L'une s'arrête dans sa file, l'autre glisse au bord de la piste ; reprise après 15 s (comme l'IA d'AC qui repart).
   spinAt=t; spinners[ord[5]]=true; spinners[ord[6]]=true; cars[ord[5]].spun=true; cars[ord[6]].spun=true; incidentZ=cars[ord[5]].z
   cars[ord[6]].edge=(cars[ord[6]].x>=0 and 1 or -1)*(T.width/2-1)
  end
  if spinAt and t-spinAt>=15 then
   for k in pairs(spinners) do if cars[k].spun then cars[k].spun=false; cars[k].lane=cars[k].x>0 and 1.6 or -1.6; cars[k].edge=nil end end
  end
  for p,k in ipairs(ord) do
   local c=cars[k]; local a=f.cars[k]; local cmd=e.commands[k]
   c.rank=p
   local active=app and k~=1 and cmd.active
   local caution=active and cmd.caution or 1
   local aggr=active and cmd.aggression or 0.8
   c.L=active and cmd.level or c.level
   local vp,binding,inCorner,yaw=profile(c,c.z,caution)
   if not binding and not inCorner then vp=vp*(1+0.012*math.sin(t*0.9+c.phase)) end
   if t<c.react then vp=0 end
   if opts.formation and k==1 and e.incidents.neutral then vp=min(vp,(e.incidents.formation and e.incidents.formationKmh or e.p.fcySpeedKmh)/3.6) end
   local vpOwn=vp
   -- Référence sans l'app : prudence 1, agressivité de l'IA d'AC, ni limite ni frein (attribution « prudence »).
   local vpBase=vp
   if active then vpBase=profile(c,c.z,1); if not binding and not inCorner then vpBase=vpBase*(1+0.012*math.sin(t*0.9+c.phase)) end; if t<c.react then vpBase=0 end end
   if active then
    local lim=min(cmd.speedLimit or K.unlimitedSpeed,cmd.yellowLimit or K.unlimitedSpeed,cmd.scSpeed or K.unlimitedSpeed)
    if lim<K.unlimitedSpeed then vp=min(vp,lim/3.6) end
   end
   -- Suivi (IA d'AC) : voiture devant dans la même file.
   local front,gap=nil,math.huge
   for q=p-1,1,-1 do local o=cars[ord[q]]; if sameLane(c,o) then front=ord[q]; gap=o.z-c.z-4.6; break end end
   local target=vp; local targetOwn=vpOwn; local targetBase=vpBase
   if front and gap<200 then
    local o=cars[front]; local seen=o.hist[(o.hp-14)%15+1] or o.v
    -- Vitesse sûre (Gipps) : arrêt possible derrière une voiture qui freinerait aussi fort que soi, après le temps de
    -- réaction, en gardant l'écart voulu.
    local h=0.10*caution*(1.25-0.5*aggr)
    local function safe(hh) local b=c.cl.decel*0.9; local room=gap-(2+c.v*hh); return -b*0.25+sqrt(max(0,(b*0.25)^2+seen*seen+2*b*room)) end
    local vf=safe(h)
    if vf<target then target=max(0,vf) end
    if vf<targetOwn then targetOwn=max(0,vf) end
    local vb=safe(0.10*(1.25-0.5*0.8))
    if vb<targetBase then targetBase=max(0,vb) end
    -- Contournement d'une voiture arrêtée, dépassement quand retenue en ligne droite (IA d'AC).
    local blocked=o.v<3 and gap<80 or vf<vp-2 and not binding and not inCorner
    if blocked then c.held=c.held+dt else c.held=0 end
    if (o.v<3 and gap<80) or c.held>1.5 then
     local other=c.lane>0 and -1.6 or 1.6; local free=true
     for q=1,n+1 do local w=cars[q]; if q~=k and abs(w.x-other)<1.85 and w.z>c.z-15 and w.z<c.z+25 then free=false; break end end
     if free then c.lane=other; c.held=0 end
    end
   end
   local cl=c.cl
   local acc
   if c.spun then
    acc=-min(c.v/dt,15); a.slip=c.v>1 and 90 or 0
   else
    a.slip=0
    -- Commande proportionnelle (gain 3 /s) : petit écart, petit freinage ; levée de pied : frein moteur et traînée.
    -- Frein de l'app : freinage au moins égal à sa part de la décélération maximale, jamais au-delà de celle-ci.
    local function accel(tg,thr,brake)
     local x
     if tg>c.v then
      x=min((tg-c.v)*3,cl.a0*max(0.15,1-(c.v/(cl.vmax/3.6))^2)*thr*(c.v<30 and c.launch or 1))
      if thr<1 then x=min(x,cl.a0*thr*max(0.15,1-(c.v/(cl.vmax/3.6))^2)-(1-thr)*(1+cl.drag*c.v*c.v)) end
     else x=-min((c.v-tg)*3,cl.decel); if c.v-tg>8 then x=-cl.decel end end
     if brake>0 then x=min(x,-brake*cl.decel) end
     return max(-cl.decel,x)
    end
    local thr=active and (cmd.throttleLimit or 1) or 1
    local brake=active and (cmd.brake or 0) or 0
    acc=accel(target,thr,brake)
    local accOwn=accel(targetOwn,1,0)
    local accBase=accel(targetBase,1,0)
    -- Ralentissement dû à l'app : décélération plus forte que celle que l'IA d'AC aurait choisie seule (commandes de
    -- frein, de levée de pied, de limite de vitesse ; ou prudence plus haute que celle d'origine).
    c.appNow=acc<accOwn-0.5; c.heldNow=targetOwn<vpOwn-2
    if acc<accOwn-0.5 then
     c.appUntil=t+1
     c.appWhy=brake>0 and acc<=-brake*cl.decel+0.01 and 'frein' or thr<1 and 'levee' or (cmd.yellowLimit or K.unlimitedSpeed)<c.v*3.6 and 'jaune' or 'vitesse'
    elseif active and acc<accBase-0.5 then c.appUntil=t+1; c.appWhy='prudence' end
   end
   c.v=max(0,c.v+acc*dt)
   -- Frein lu par l'app : pédale de l'IA (freinage voulu) ou frein imposé par l'app.
   a.brake=max(acc<-1 and min(1,-acc/cl.decel) or 0,active and (cmd.brake or 0) or 0)
   a.gas=acc>0 and 1 or 0
   a.yawRate=inCorner and yaw*(c.v/max(1,c.vc[1])) or 0
   if inCorner then a.yawRate=0; for j,cr in ipairs(corners) do if ((c.z%L)-cr.at)%L<cr.len then a.yawRate=cr.sign*c.v/cr.R end end end
   -- Rapprochement de la trajectoire idéale au premier tour (IA d'AC) : côté intérieur du virage suivant, si la file
   -- est libre de 6 m derrière à 10 m devant.
   if c.z>150 and c.z<L and not c.spun then
    local zz=c.z%L
    for _,cr in ipairs(corners) do
     local d=(cr.at-zz)%L
     if d<600 then
      local want=cr.sign*1.6
      if c.lane~=want then
       local free=true
       for q=1,n+1 do local w=cars[q]; if q~=k and abs(w.x-want)<1.85 and w.z>c.z-6 and w.z<c.z+10 then free=false; break end end
       if free then c.lane=want end
      end
      break
     end
    end
   end
   -- Latéral : file de l'IA d'AC, ou décalage de l'app (fraction de la demi-largeur).
   local xt=c.lane
   -- Décalage de l'app : ajouté à la file de l'IA d'AC (le décalage déplace la trajectoire suivie), dans la piste.
   if active and cmd.offset and cmd.offset~=0 then xt=max(-T.width/2+1,min(T.width/2-1,c.lane+cmd.offset*(T.width/2-1.2))) end
   if c.spun then xt=c.edge or c.x end
   local nx=c.x+max(-2*dt,min(2*dt,xt-c.x))
   if c.spun and c.edge then nx=c.x+max(-6*dt,min(6*dt,xt-c.x)) end
   if nx~=c.x then
    local hit=nil
    for q=1,n+1 do local w=cars[q]; if q~=k and abs(w.x-nx)<1.85 and abs(w.z-c.z)<4.6 and abs(w.x-c.x)>=1.85 then hit=q; break end end
    if hit then
     local key=min(k,hit)*100+max(k,hit); blockedNow[key]=true
     if not spair[key] then spair[key]=true; R.side=R.side+1; if active and cmd.offset and cmd.offset~=0 then R.sideApp=R.sideApp+1 end end
    else c.x=nx end
   end
   c.hp=c.hp%15+1; c.hist[c.hp]=c.v
   -- Mémoire des commandes de l'app (attribution des contacts).
   c.binding=binding; c.inCorner=inCorner; c.vp=vp
  end
  -- Intégration et contacts par l'arrière.
  for k=1,n+1 do local c=cars[k]; c.z=c.z+c.v*dt end
  table.sort(ord,function(p,q) return cars[p].z>cars[q].z end)
  for k=1,n+1 do f.cars[k].collided=false; f.cars[k].collidedWith=-1 end
  local touching={}
  for p,k in ipairs(ord) do
   local c=cars[k]
   for q=p-1,1,-1 do local o=cars[ord[q]]
    if sameLane(c,o) then
     local gap=o.z-c.z-4.6
     if gap<0 then
      local key=min(k,ord[q])*100+max(k,ord[q]); touching[key]=true
      if not pair[key] then
       pair[key]=true; R.contacts=R.contacts+1
       if o.appUntil>t then R.contactsApp=R.contactsApp+1; R.why=R.why or {}; R.why[o.appWhy]=(R.why[o.appWhy] or 0)+1 end
       local zz=c.z%L
       if c.z>=L*(laps-1) and c.z<L*laps and zz>=corners[1].at-400 and zz<=corners[1].at+corners[1].len then R.contactsFirst=R.contactsFirst+1 end
      end
      c.z=o.z-4.6; c.v=min(c.v,o.v)
      f.cars[k].collided=true; f.cars[k].collidedWith=ord[q]; f.cars[ord[q]].collided=true; f.cars[ord[q]].collidedWith=k
     end
     break
    end
   end
  end
  for key in pairs(pair) do if not touching[key] then pair[key]=nil end end
  for key in pairs(spair) do if not blockedNow[key] then spair[key]=nil end end
  for k=1,n+1 do
   local c=cars[k]; local a=f.cars[k]
   a.z=c.z; a.x=c.x; a.splineLat=c.x; a.spline=(c.z/L)%1; a.lap=max(0,floor(c.z/L)); a.speed=c.v; a.kmh=c.v*3.6
   if opts.formation then a.position=c.rank or c.grid end
   if c.z>=L*laps and not lapDone[k] then lapDone[k]=true; if k~=1 then lapSum=lapSum+t; lapN=lapN+1; R.lap1Last=max(R.lap1Last,t) end end
  end
  F.tick(e,f,dt)
  -- Mesures (premier tour de chaque IA).
  for k=2,n+1 do
   local c=cars[k]; local s=e.states[k]; local cmd=e.commands[k]
   if not lapDone[k] and not app and not c.spun and not c.binding and not c.inCorner and c.z>300 and c.solo[floor(c.z-c.z0)] then
    local vfree=c.solo[floor(c.z-c.z0)]
    R.deficit=R.deficit+max(0,vfree-c.v)/max(1,vfree); R.deficitN=R.deficitN+1
    if c.heldNow then R.held=R.held+1 end
   end
   if not lapDone[k] and app then
    local straight=not c.binding and not c.inCorner
    if c.binding and not firstBrakeAt[k] and c.z>0 then firstBrakeAt[k]=t end
    local br=(cmd.brake or 0)>0.001
    if br and not lastBrake[k] then
     R.brakeOnsets=R.brakeOnsets+1
     if straight then
      R.radarStraight=R.radarStraight+1
      -- Contact imminent (moins de 0,4 s, file de la voiture) : dernier recours.
      local best=math.huge
      for q=1,n+1 do local o=cars[q]; if q~=k and abs(o.x-c.x)<1.85 and o.z>c.z and c.v>o.v then best=min(best,(o.z-c.z-4.6)/(c.v-o.v)) end end
      if best<0.4 then R.radarLast=(R.radarLast or 0)+1 end
     end
     if not firstBrakeAt[k] then R.radarBefore=R.radarBefore+1 end
    end
    if br and straight then R.maxBrakeStraight=max(R.maxBrakeStraight,cmd.brake) end
    lastBrake[k]=br
    local lift=(cmd.throttleLimit or 1)<0.98
    if lift and not lastLift[k] then if straight then R.liftStraight=R.liftStraight+1 end; if not firstBrakeAt[k] then R.liftBefore=R.liftBefore+1 end end
    lastLift[k]=lift
    local av=s.state=='AVOID'
    if av and not lastAvoid[k] then
     R.avoid=R.avoid+1
     local tg=s.target and cars[s.target]
     if not tg or tg.v>0.3*packV then R.avoidPack=R.avoidPack+1 end
     -- Beta 1.50 : évitement d'une voiture qui roule au-dessus du seuil de la règle du premier tour (vitesse d'obstacle ou
     -- K.firstLapAvoidPct de l'allure de l'IA qui évite) : une vague de freinage, jamais une voiture vraiment lente.
     if not tg or tg.v*3.6>max(e.p.obstacleSpeedKmh,K.firstLapAvoidPct*c.v*3.6)+5 then R.avoidWave=R.avoidWave+1 end
    end
    lastAvoid[k]=av
    if s.state=='DEFEND' then R.defend=R.defend+1 end
    if spinAt and not c.spun and (cmd.yellowLimit or K.unlimitedSpeed)<c.v*3.6-5 and not yellowSeen[k] then
     yellowSeen[k]=true; R.yellowCars=R.yellowCars+1
     local d=(incidentZ or c.z)-c.z
     if d>R.yellowFar then R.yellowFar=d; R.yellowFarTime=d/max(1,c.v) end
    end
    -- Déficit d'allure en ligne droite (hors lancement) : vitesse sous la vitesse de profil sans suivi.
    if straight and c.z>300 and not c.spun and c.solo[floor(c.z-c.z0)] then
     local vfree=c.solo[floor(c.z-c.z0)]
     R.deficit=R.deficit+max(0,vfree-c.v)/max(1,vfree); R.deficitN=R.deficitN+1
     if c.heldNow then R.held=R.held+1 end
     if c.appNow then R.appSlow=R.appSlow+1 end
    end
   end
  end
  if lapN>=n then break end
 end
 R.held=R.deficitN>0 and R.held/R.deficitN*100 or 0; R.appSlow=R.deficitN>0 and R.appSlow/R.deficitN*100 or 0
 R.deficit=R.deficitN>0 and R.deficit/R.deficitN*100 or 0
 R.lap1Mean=lapN>0 and lapSum/lapN or 0; R.finished=lapN
 local so=0; for k=2,n+1 do so=so+cars[k].soloLap end; R.soloMean=so/n
 R.startRadar=e.startRadar or 0; R.startLift=e.startLift or 0
 R.log=e.log; R.engine=e
 return R
end
