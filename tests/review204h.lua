-- Beta 2.0.4, essai du pilote à Monza le 18 novembre à 11:47 (journal 2026-11-18_11_43_34_monza, replay
-- AC_181126-114728) et ses décisions du même jour (questionnaire). Chargé par tests/extended.lua.
--  H1 : recalage sur la grille vérifié sur la voiture après chaque écriture (17 IA reposées à l'envers, 0,46 m devant
--       leur place : la fonction de CSP attend la direction opposée au cap lu et pose un point 0,465 m devant la position
--       lue) ;
--  H2 : voiture qui n'est plus avec le peloton quand la grille se forme : arrière de la grille, jamais attendue ;
--  H3 : tour de formation en file stricte (accrochage de deux IA à la même hauteur pendant le zigzag ; peloton en
--       désordre et côte à côte sur le chemin de la grille) ;
--  H4 : zigzag : écart latéral tenu avec une voiture à sa hauteur ;
--  H5 : pas de priorité au virage pendant la formation de la grille.
local F=require('tests/fixture')
local C=require('src/config')
local K=C.K
local E=require('src/engine')
local G=require('src/grid')
local tests={}
local function logged(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end

local L=5000
local nodes={}
for k=1,6 do nodes[k]={spline=((-(10+(k-1)*8))/L)%1,lateral=k%2==1 and -0.3 or 0.3} end
local function slotZ(k) return -(10+(k-1)*8) end
local function slotX(k) return (k%2==1 and -1 or 1)*1.5 end
-- Grille de n voitures arrivées du tour de formation ; poses relevées sur les places (cap +z).
local function scene(n)
 local e,f=F.scene('C',n); C.preset('Course','C',e.profiles.C); E.changed(e); e.gridCaps=true; f.length=L
 for i=1,n do f.cars[i].position=i end
 e.grid.nodes=nodes; e.grid.conv=nil
 for i=1,n do local a=F.place(f,i,slotZ(i),0,slotX(i)); a.lx=0; a.lz=1; a.ly=0; a.y=0.3 end
 local node={}; for i=1,n do node[i]=i end
 assert(G.recordPoses(e.grid,f,node)==n,'poses recorded for the cars standing on their places')
 for i=1,n do F.place(f,i,slotZ(i)-300,60) end
 F.tick(e,f,0.2)
 local t=e.incidents; t.formationRank={}; for i=1,n do t.formationRank[i]=i end
 t.formationRankN=n; t.formationAt=e.time-30; t.formationNode=node
 t.standing='grid'; F.tick(e,f,0.1)
 return e,f
end
local function park(f,i,dz,dx,ang)
 local a=F.place(f,i,slotZ(i)+dz,0,slotX(i)+dx)
 a.lx=math.sin(math.rad(ang)); a.lz=math.cos(math.rad(ang)); a.ly=0
 return a
end
-- Modèle de la fonction de CSP : la voiture regarde sign fois la direction donnée ; le point posé est à of m devant et
-- ol m à droite de la position lue.
local function csp(f,i,cmd,sign,of,ol)
 local a=f.cars[i]
 local fx,fz=sign*cmd.lx,sign*cmd.lz; local n=math.sqrt(fx*fx+fz*fz); fx,fz=fx/n,fz/n
 a.lx=fx; a.lz=fz
 a.x=cmd.x-of*fx-ol*(-fz); a.z=cmd.z-of*fz-ol*fx
 a.spline=(a.z/f.length)%1; a.splineLat=a.x; a.kmh=0; a.speed=0
end
-- Laisse tourner la grille seconds s en appliquant le modèle à chaque commande ; renvoie le nombre d'écritures par voiture.
local function run(e,f,seconds,sign,of,ol,frozen)
 local writes={}
 for _=1,math.floor(seconds*60) do
  -- La voiture reste où le modèle l'a posée (le banc ne la remet pas sur la trajectoire).
  for i=2,f.count do local a=f.cars[i]; if frozen and frozen[i] then local p=frozen[i]; a.x=p.x; a.z=p.z; a.lx=p.lx; a.lz=p.lz; a.spline=(a.z/f.length)%1; a.splineLat=a.x; a.kmh=0; a.speed=0 end end
  f.senseOff=true
  E.step(e,f,1/60)
  for i=2,f.count do
   local cmd=e.commands[i].gridSnap
   if cmd then
    writes[i]=(writes[i] or 0)+1
    csp(f,i,cmd,sign,of,ol)
    frozen=frozen or {}; local a=f.cars[i]; frozen[i]={x=a.x,z=a.z,lx=a.lx,lz=a.lz}
   end
  end
 end
 return writes,frozen
end
local function hold(f,i,dz,dx,ang,frozen)
 local a=park(f,i,dz,dx,ang); frozen[i]={x=a.x,z=a.z,lx=a.lx,lz=a.lz}
end
local function residual(e,f,i)
 local a=f.cars[i]; local p=e.grid.pose[i]
 return math.sqrt((a.x-p.x)^2+(a.z-p.z)^2),a.lx*p.lx+a.lz*p.lz
end

tests.LOCK_GRID_SNAP_VERIFIED_204=function()
 assert(G.GK.snapDir==-1 and G.GK.snapFwd==-0.49 and G.GK.snapTol==0.05 and G.GK.snapTries==3)
 -- (a) Convention apprise en jeu à Monza le 18 novembre à 13:05 (direction opposée au cap, décalage -0,49 m) : juste à
 -- la première écriture.
 local e,f=scene(4); local g=e.grid; local fr={}
 assert(g.source=='AC_START' and g.slotOf[2]==2,'scene: AC_START places')
 hold(f,2,-1.2,0.4,6,fr); hold(f,3,-1.0,-0.3,-4,fr)
 local w=run(e,f,3,-1,-0.49,0,fr)
 local d2,c2=residual(e,f,2); local d3,c3=residual(e,f,3)
 assert(w[2]==1 and w[3]==1,'one write per car ('..tostring(w[2])..', '..tostring(w[3])..')')
 assert(d2<0.01 and c2>0.999 and d3<0.01 and c3>0.999,string.format('exactly on the pose, same heading (%.3f m, %.3f m)',d2,d3))
 assert(g.snapN==2 and g.snapFixes==0 and g.snapLeft==0 and g.snapped[2] and g.snapped[3],'verified, no correction needed')
 assert(g.aiRef[2]==nil or math.abs(g.aiRef[2]-f.cars[2].spline)<1e-9,'false-start reference taken again after the write')
 -- (b) Convention inverse (direction = cap, point posé = position lue) : première écriture à l'envers, corrigée seule.
 local e2,f2=scene(4); local g2=e2.grid; local fr2={}
 hold(f2,2,-1.2,0.4,6,fr2)
 local w2=run(e2,f2,3,1,0,0,fr2)
 local dd,cc=residual(e2,f2,2)
 assert(w2[2]==2,'backwards after the first write: one correction ('..tostring(w2[2])..')')
 assert(dd<0.01 and cc>0.999,string.format('corrected: on the pose, right way round (%.3f m, cos %.3f)',dd,cc))
 assert(g2.conv.dir==1 and math.abs(g2.conv.fwd)<1e-6 and g2.snapFixes==1 and g2.snapN==1,'convention learnt from the car itself')
 -- La voiture suivante profite de la convention apprise : une seule écriture.
 hold(f2,3,-1.0,-0.3,-4,fr2)
 local w3=run(e2,f2,3,1,0,0,fr2)
 local d5,c5=residual(e2,f2,3)
 assert(w3[3]==1 and d5<0.01 and c5>0.999,'next car right at the first write')
 -- (c) Point posé ailleurs (0,2 m devant, 0,1 m à droite) : corrigé en une écriture de plus.
 local e3,f3=scene(4); local fr3={}
 hold(f3,2,-0.8,0.2,0,fr3)
 local w4=run(e3,f3,3,-1,0.2,0.1,fr3)
 local d6,c6=residual(e3,f3,2)
 assert(w4[2]==2 and d6<0.01 and c6>0.999,string.format('offset learnt (%d writes, %.3f m)',w4[2] or 0,d6))
 -- (d) Écriture perdue (la voiture ne bouge pas) : réessayée, jamais plus de GK.snapTries écritures, comptée « pas à sa pose ».
 local e4,f4=scene(4); local fr4={}
 hold(f4,2,-1.2,0.4,6,fr4)
 local lost=0
 for _=1,5*60 do
  local p=fr4[2]; local a=f4.cars[2]; a.x=p.x; a.z=p.z; a.lx=p.lx; a.lz=p.lz; a.spline=(a.z/L)%1; a.kmh=0; a.speed=0; f4.senseOff=true
  E.step(e4,f4,1/60); if e4.commands[2].gridSnap then lost=lost+1 end
 end
 assert(lost==G.GK.snapTries and e4.grid.snapLeft==1 and e4.grid.snapN==0,'lost writes: '..lost..' tries, reported as not on its pose')
end

tests.LOCK_GRID_SNAP_GUARDS_204=function()
 local function never(setup,why)
  local e,f=scene(4); local fr={}
  setup(e,f,fr)
  local w=run(e,f,4,-1,-0.49,0,fr)
  assert(not w[2],why)
  return e
 end
 assert(G.GK.snapMax==4)
 local e=never(function(_,f,fr) hold(f,2,-3.9,2.5,0,fr) end,'4.6 m away: no snap')
 assert(e.grid.held[2],'scene: held short of its place after the wait')
 -- Essai du pilote de 13:05 : dernière IA arrêtée à 3,3 m de sa place (1,5 m avant, 3 m sur le côté) : reposée.
 local e8,f8=scene(4); local fr8={}
 hold(f8,2,-1.5,2.9,3,fr8)
 local w8=run(e8,f8,4,-1,-0.49,0,fr8)
 local d8=residual(e8,f8,2)
 assert(w8[2]==1 and d8<0.01,'3.3 m from its place: set on it ('..tostring(w8[2])..')')
 never(function(_,f,fr) hold(f,2,-1,0,30,fr) end,'30 degrees: no snap')
 never(function(_,f,fr) hold(f,2,-1,0,0,fr); hold(f,3,8-2,3,0,fr) end,'another car 2 m from the pose: no snap')
 -- Aux feux : aucun premier recalage ; une vérification en cours continue.
 local e5,f5=scene(4); local fr5={}
 hold(f5,2,-1,0,0,fr5); e5.grid.phase='lights'; e5.incidents.standing='lights'; e5.grid.lightsAt=e5.time; e5.grid.outAt=e5.time+60
 local w5=run(e5,f5,2,-1,-0.49,0,fr5)
 assert(not w5[2],'lights: no first snap')
 -- Recalage en attente de vérification : les feux attendent (g.snapBusy), GK.snapWait s au plus.
 local e6,f6=scene(4); local fr6={}
 hold(f6,2,-1.2,0.4,6,fr6)
 local busy,waited=true,0
 for _=1,4*60 do
  local p=fr6[2]; local a=f6.cars[2]; a.x=p.x; a.z=p.z; a.lx=p.lx; a.lz=p.lz; a.spline=(a.z/L)%1; a.kmh=0; a.speed=0; f6.senseOff=true
  E.step(e6,f6,1/60)
  local cmd=e6.commands[2].gridSnap
  if cmd then csp(f6,2,cmd,-1,-0.49,0); fr6[2]={x=f6.cars[2].x,z=f6.cars[2].z,lx=f6.cars[2].lx,lz=f6.cars[2].lz} end
  if e6.grid.snapAt[2] then waited=waited+1; busy=busy and e6.grid.snapBusy==true end
 end
 assert(waited>=10 and busy,'between the write and its check: the lights wait ('..waited..' frames)')
 -- Applicateur : une écriture par commande, avec la position et la direction données ; jamais le joueur.
 local host=require('tests/host').create(true)
 local A=require('src/applier'); local a=A.new(); assert(A.access(a))
 local e7,f7=F.scene('C',4)
 for _,cmd in ipairs(e7.commands) do cmd.active=false; cmd.gridSnap=nil end
 e7.commands[2].gridSnap={id=7,x=1,y=0.3,z=-18,lx=0,ly=0,lz=-1}
 local writes=host.positionWrites or 0
 A.apply(a,f7,e7.commands,e7.g,e7.time); A.apply(a,f7,e7.commands,e7.g,e7.time+0.1)
 assert((host.positionWrites or 0)==writes+1 and host.positions[1] and host.positions[1].pos.z==-18 and host.positions[1].dir.z==-1,'one position write with the pose and the direction given')
 e7.commands[2].gridSnap={id=8,x=1,y=0.3,z=-18,lx=0,ly=0,lz=-1}; A.apply(a,f7,e7.commands,e7.g,e7.time+0.2)
 assert((host.positionWrites or 0)==writes+2,'a new command is written again')
 e7.commands[1].gridSnap={id=9,x=0,y=0,z=0,lx=0,ly=0,lz=1}; A.apply(a,f7,e7.commands,e7.g,e7.time+0.3)
 assert(not host.positions[0],'never the player')
end

-- H2 : voiture seule loin du peloton quand la grille se forme.
tests.LOCK_GRID_LATE_CAR_204=function()
 assert(G.GK.lateGap==500)
 local e,f=F.scene('C',6); C.preset('Course','C',e.profiles.C); E.changed(e); e.gridCaps=true; f.length=L
 for i=1,6 do f.cars[i].position=i end
 e.grid.nodes=nil
 local function sz(k) return -(K.gridFirst+(k-1)*K.gridPitch) end
 for i=1,6 do F.place(f,i,sz(i)-200,60) end
 F.place(f,3,2000,125) -- la voiture 3 roule seule, 2 km plus loin sur le tour
 F.tick(e,f,0.2)
 local t=e.incidents; t.formationRank={1,2,3,4,5,6}; t.formationRankN=6; t.formationAt=e.time-30; t.formationNode={1,2,3,4,5,6}
 t.standing='grid'; F.tick(e,f,0.1)
 local g=e.grid
 assert(g.late[3] and g.slotOf[3]==7,'late car behind the last place ('..tostring(g.slotOf[3])..')')
 assert(g.slotOf[1]==1 and g.slotOf[2]==2 and g.slotOf[4]==4 and g.slotOf[5]==5 and g.slotOf[6]==6,'the others keep their own place, place 3 left empty')
 assert(logged(e,'grille: Driver_3 part de l arriere de la grille (plus avec le peloton a la fin du tour de formation), sans etre attendue')==1,'one line')
 -- Jamais attendue : toutes les autres en place, les feux s'allument alors qu'elle roule encore (protection du renvoi
 -- aux stands active, comme en jeu : sans cette règle les feux attendraient toutes les IA).
 local guard=G.retireGuard; G.retireGuard=true
 local ok,err=pcall(function()
  for _=1,8*60 do
   for i=2,6 do if i~=3 then F.place(f,i,sz(i),0) end end
   F.place(f,1,sz(1),0); F.place(f,3,2000,125)
   F.tick(e,f,1/60); G.retireGuard=true
   if g.phase~='grid' then break end
  end
 end)
 G.retireGuard=guard; assert(ok,err)
 assert(g.phase=='lights' or g.phase=='go','lights without waiting for the late car ('..tostring(g.phase)..')')
 assert(logged(e,'IA pas en place aux feux')==0,'not reported as missing either')
 -- Peloton entier (aucune voiture à plus de GK.lateGap m) : personne n'est retardataire ; le joueur ne l'est jamais.
 local g2={backN=0,late={}}; local fr={length=L,cars={}}; local order={}
 for i=1,5 do fr.cars[i]={spline=((-300-i*15)/L)%1,name='C'..i,player=i==1}; order[i]=i end
 assert(G.lateCars(g2,fr,order,5,0,e.log)==0 and next(g2.late)==nil,'whole pack together: nobody late')
 fr.cars[1].spline=0.4
 assert(G.lateCars(g2,fr,order,5,0,e.log)==0,'the player is never sent to the back by this rule')
 -- Avec une voiture déjà renvoyée (toBack) : gardées, renvoyées, puis retardataires.
 local g3={backN=1,late={}}; local fr3={length=L,cars={}}; local o3={1,2,4,5,3}
 for i=1,5 do fr3.cars[i]={spline=((-300-i*15)/L)%1,name='C'..i} end
 fr3.cars[2].spline=0.5
 assert(G.lateCars(g3,fr3,o3,5,0,e.log)==1 and o3[1]==1 and o3[2]==4 and o3[3]==5 and o3[4]==3 and o3[5]==2 and g3.backN==2,'kept, sent back, then late ('..table.concat(o3,',')..')')
end

-- H3 : file stricte du tour de formation.
local Convoy=require('src/convoy')
local function cars(e,f,list)
 -- list : {z, kmh, x} par voiture (1 = joueur, loin derrière si absent).
 for i=1,f.count do
  local c=list[i] or {-3000-i*50,0,0}
  local a=F.place(f,i,c[1],c[2],c[3] or 0); a.lx=0; a.lz=1; a.offtrack=false; a.pit=false
 end
 for i=1,f.count do local cmd=e.commands[i]; cmd.speedLimit=K.unlimitedSpeed; cmd.brake=0 end
end
tests.LOCK_FORMATION_CONVOY_204=function()
 local CK=Convoy.CK
 assert(CK.gap==6 and CK.decel==4 and CK.react==0.25 and CK.gapMin==2 and CK.gapTime==0.5 and CK.panic==1 and CK.closeRate==0.25)
 -- Plafond : l'allure de la voiture de devant à la distance de garde, ce qui se freine encore au-delà, moins vite en deçà.
 assert(math.abs(Convoy.cap(30,6,30)-30)<1e-9,'at the guard distance: the pace of the car ahead')
 assert(math.abs(Convoy.cap(30,6+0.25*40+50,40)-math.sqrt(900+2*4*50))<1e-9,'beyond: what can still be braked (reaction time included)')
 -- Garde réduite à basse vitesse (départ de la grille : voitures à 2,7 m, à l'arrêt) : elles peuvent s'élancer.
 assert(Convoy.guard(0)==2 and Convoy.guard(4)==4 and Convoy.guard(20)==6,'guard: 2 m at a standstill, 6 m from 8 m/s')
 assert(Convoy.cap(0,2.7,0)>0,'grid launch: free to move off behind the car ahead')
 -- En deçà de la garde : à peine moins vite que la voiture de devant (0,25 m/s par mètre manquant : jamais d'arrêt en
 -- chaîne dans une file qui se resserre).
 assert(math.abs(Convoy.cap(30,3,30)-29.25)<1e-9 and Convoy.cap(0,1,5)==0,'closer than the guard: slightly slower than the car ahead')
 local e,f=F.scene('C',4); F.tick(e,f,0.1)
 local inc=e.incidents
 local function step(formation,rollCall,standing)
  inc.formation=formation; inc.rollCall=rollCall; inc.standing=standing or 'none'
  Convoy.step(e,f,e.time)
  return e.commands[2].speedLimit,e.commands[2].brake
 end
 -- Voiture 3 devant à 100 km/h, 5 m sur le côté (hors du couloir) ; voiture 2 à 40 m derrière, 80 km/h plus vite.
 local function setup() cars(e,f,{nil,{0,180,0},{40+4.4,100,5},{-2000,100,0}}) end
 setup(); local limit,brake=step(true,false)
 local cap=Convoy.cap(100/3.6,40+4.4-f.cars[2].length*0.5-f.cars[3].length*0.5,180/3.6)*3.6
 assert(math.abs(limit-cap)<1e-6 and cap<180,string.format('car ahead off to the side: capped behind it all the same (%.0f km/h)',limit))
 assert(brake==0,'40 m away: the speed limit alone, no brake command')
 -- Dernier recours : 12 m derrière, 80 km/h plus vite (moins d'une seconde de la garde) : freinage commandé.
 cars(e,f,{nil,{0,180,0},{12+4.4,100,5},{-2000,100,0}}); limit,brake=step(true,false)
 assert(brake>0,'under one second from the guard distance: brake command')
 setup(); limit,brake=step(false,false)
 assert(limit==K.unlimitedSpeed and brake==0,'outside the formation lap: nothing')
 setup(); limit=step(true,true)
 assert(limit==K.unlimitedSpeed,'two-file call of the rolling start: nothing (pairs side by side)')
 -- Jamais comptées devant : en incident, hors piste, aux stands.
 setup(); inc.cars[3].incident=true; limit=step(true,false); inc.cars[3].incident=false
 assert(limit==K.unlimitedSpeed,'car in an incident ahead: not followed')
 setup(); f.cars[3].offtrack=true; limit=step(true,false); assert(limit==K.unlimitedSpeed,'off track: not followed')
 setup(); f.cars[3].pit=true; limit=step(true,false); assert(limit==K.unlimitedSpeed,'in the pits: not followed')
 -- Le joueur devant compte comme une autre voiture.
 cars(e,f,{{40+4.4,100,5},{0,180,0},{-2000,100,0},{-2100,100,0}}); limit=step(true,false)
 assert(limit<180,'the player ahead is followed too')
 -- Collée (2 m de pare-chocs), voiture de devant arrêtée : freinage complet.
 cars(e,f,{nil,{0,2,0},{2+4.4,0,4},{-2000,0,0}}); limit,brake=step(true,false)
 assert(brake==K.brakeMax and limit==K.gridCrawlKmh,'creeping 2 m behind a stopped car: full brake')
 -- Grille : voiture tenue à sa place dans l'autre colonne : pas comptée ; dans son couloir : comptée.
 local g=e.grid
 cars(e,f,{nil,{0,40,0},{30,0,5},{-2000,0,0}}); g.held[3]=true; g.slotOf[2]=0
 limit=step(false,false,'grid'); assert(limit==K.unlimitedSpeed,'held car in the other column: free to drive past')
 cars(e,f,{nil,{0,40,0},{30,0,1},{-2000,0,0}}); limit=step(false,false,'grid')
 assert(limit<K.unlimitedSpeed,'held car in its own corridor: followed')
 cars(e,f,{nil,{0,40,0},{3+4.4,0,1},{-2000,0,0}}); limit,brake=step(false,false,'grid')
 assert(limit<40 and brake>0,'3 m behind a held car in its own corridor: slows down behind it')
 -- Grille en une seule file (places à 8 m) : la garde réduite laisse rejoindre sa place derrière une voiture tenue.
 assert(Convoy.CK.gridGap==1.5)
 cars(e,f,{nil,{0,10,0},{8,0,0},{-2000,0,0}}); limit=step(false,false,'grid')
 assert(limit>=10,'single-file grid: free to reach its own place 8 m behind a held car ('..limit..')')
 g.held[3]=false
 -- Branché dans le moteur (après la grille) : actif pendant le tour de formation.
 cars(e,f,{nil,{0,180,0},{40+4.4,100,5},{-2000,100,0}})
 e.convoy=nil; inc.standing='lights'; F.tick(e,f,1/60)
 assert(e.convoy and e.convoy.active==true,'run by the engine (grid and lights of a standing start)')
end

-- Banc : file de 8 IA qui rattrapent à 230 km/h une tête à 110, écarts latéraux alternés (zigzag) : jamais à moins de
-- 2 m de la voiture de devant, ordre gardé. Sans la règle : dépassements (le banc le montre).
tests.LOCK_FORMATION_CONVOY_BENCH_204=function()
 local function bench(rule)
  local e,f=F.scene('C',9); F.tick(e,f,0.1)
  local inc=e.incidents; inc.formation=true; inc.rollCall=false; inc.standing='none'
  local z,v={},{}
  for i=2,9 do z[i]=-(i-2)*90; v[i]=(i==2) and 110/3.6 or 230/3.6 end
  local closest=math.huge; local swaps=0
  for step=1,60*60 do
   for i=1,9 do
    local a=f.cars[i]
    if i==1 then F.place(f,1,-5000,0)
    else F.place(f,i,z[i],v[i]*3.6,(i%2==0 and -1 or 1)*4*math.sin(step/60*2)); end
    a.lx=0; a.lz=1; a.offtrack=false
    e.commands[i].speedLimit=K.unlimitedSpeed; e.commands[i].brake=0
   end
   if rule then Convoy.step(e,f,step/60) end
   for i=3,9 do
    local cmd=e.commands[i]; local limit=cmd.speedLimit/3.6
    -- IA simple : accélère à 6 m/s² jusqu'à 230 km/h ou sa limite ; au-dessus de la limite : 4 m/s², 12 m/s² pleins freins.
    if v[i]>limit then v[i]=math.max(limit,v[i]-(4+8*cmd.brake)/60) else v[i]=math.min(math.min(limit,230/3.6),v[i]+6/60) end
    if cmd.brake>=K.brakeMax then v[i]=math.max(0,v[i]-12/60) end
   end
   for i=2,9 do z[i]=z[i]+v[i]/60 end
   for i=3,9 do
    local bumper=z[i-1]-z[i]-f.cars[i].length
    if bumper<closest then closest=bumper end
    if z[i]>z[i-1] then swaps=swaps+1 end
   end
  end
  return closest,swaps,z
 end
 local closest,swaps=bench(true)
 assert(swaps==0,'grid order kept all along')
 assert(closest>=2,string.format('never closer than 2 m to the car ahead (%.1f m)',closest))
 local without,passes=bench(false)
 assert(passes>0 and without<0,'scene: without the rule the cars drive through each other')
end

-- H4 : zigzag : une voiture à sa hauteur, quel que soit l'écart latéral : écart tenu.
tests.LOCK_FORMATION_WEAVE_BESIDE_204=function()
 local Antics=require('src/antics')
 assert(Antics.AK.sideClear==3)
 local function frame(long,lat,pit)
  return {count=2,cars={{valid=true,x=0,z=0,lx=0,lz=1,length=5.3},{valid=true,pit=pit,x=lat,z=long,lx=0,lz=1,length=5.3}}}
 end
 assert(Antics.beside(frame(4.4,6),1),'4.4 m behind its nose, 6 m to the side: beside')
 assert(Antics.beside(frame(-8,-7),1),'overlap within 3 m: beside')
 assert(not Antics.beside(frame(9,3),1),'9 m ahead: not beside')
 assert(not Antics.beside(frame(4.4,6,true),1),'in the pits: ignored')
 -- Dans le zigzag : écart latéral tenu tant que la voiture est à sa hauteur, repris ensuite.
 local Snapshot=require('src/snapshot'); local U=require('src/util')
 local bend=Snapshot.bendLat; Snapshot.bendLat=function() return 0,0 end
 local ok,err=pcall(function()
  local t=Antics.new(); t.active=true
  local function car(x,z) return {valid=true,control=true,player=false,pit=false,finished=false,safetyCar=false,splineValid=true,kmh=120,speed=120/3.6,yawRate=0,spline=0.5,brake=0,name='A',leftWidth=6,rightWidth=6,width=1.85,length=5.3,x=x,z=z,lx=0,lz=1} end
  local fr={count=2,length=7000,cars={car(0,3500),car(6,3600)},player=0}
  local row=function() return {count=0,back=0,front=0,neighbors={}} end
  local e={incidents={formation=true,rollCall=false},runtimeG={seed=5},commands={{speedLimit=K.unlimitedSpeed},{speedLimit=K.unlimitedSpeed}},perception={rows={row(),row()}},
   states={{zone={}},{zone={}}},grid={aiRelease={}},stats={},log=U.newLog(200,1000,0),g={offsetSign=-1},pitEntry=-1}
  local now=0
  local function span(seconds) local lo,hi=math.huge,-math.huge; for _=1,math.floor(seconds*60) do now=now+1/60; Antics.weave(t,e,fr,now,1/60); lo=math.min(lo,t.form[1]); hi=math.max(hi,t.form[1]) end return lo,hi end
  local lo,hi=span(6); assert(hi-lo>0.5,'scene: alone, it weaves ('..(hi-lo)..')')
  fr.cars[2].z=3504 -- voiture 2 à sa hauteur, 6 m sur le côté
  span(0.1); lo,hi=span(6)
  assert(hi-lo<1e-9,'a car beside it: lateral held ('..(hi-lo)..')')
  fr.cars[2].z=3600; lo,hi=span(6); assert(hi-lo>0.5,'clear again: weaving again')
 end)
 Snapshot.bendLat=bend; assert(ok,err)
end

-- H5 : pas de priorité au virage pendant la formation de la grille ni les feux (scène de LOCK_DUEL_DIRECTOR_164 : IA
-- intérieure sans droit à l'espace, qui cède en course).
tests.LOCK_GRID_NO_CORNER_PRIORITY_204=function()
 local function corner(standing)
  local e,f=F.scene('C',4)
  e.g.offsetSign=1; e.g.sideSign=1; E.changed(e)
  for i=1,f.count do f.cars[i].sideDot=1 end
  F.place(f,1,-5000,100); f.started=true; F.tick(e,f,30)
  for _,i in ipairs({2,3}) do local c=f.cars[i]; c.length=5; c.axleKnown=true; c.axleFront=1.6; c.axleRear=-2; c.mirror=0; c.geomRead=true end
  F.place(f,2,0,150,-2); F.place(f,3,2,150,0); F.tick(e,f,0.3)
  for _=1,30 do
   if standing then e.incidents.standing=standing end
   F.place(f,2,0,150,-2); F.place(f,3,2,150,0)
   f.cars[2].brake=0.6; f.cars[3].brake=0.6; f.cars[2].yawRate=-0.3; f.cars[3].yawRate=-0.3
   F.tick(e,f,1/60)
  end
  return e
 end
 assert(corner(nil).states[2].cornerGiveTo==3,'scene: in the race the inside car without the right gives way')
 assert(corner('grid').states[2].cornerGiveTo==0,'on the way to the grid: no corner priority')
 assert(corner('lights').states[2].cornerGiveTo==0,'at the lights: no corner priority')
 local J=require('src/journal')
 local line='tour de formation: file stricte, 0 rapprochement(s) a moins de 2 m de la voiture de devant, plus petit ecart 6.4 m'
 assert(J.english(line)=='formation lap: strict single file, 0 time(s) closer than 2 m to the car ahead, smallest gap 6.4 m',tostring(J.english(line)))
 line='grille aux feux: 20 IA reposees exactement (deplacees de 1.20 m en moyenne, ecart restant au plus 0.01 m, 0 correction(s), 0 pas a leur pose ; sens -1, decalage +0.47 m) ; ecarts long/lat (m) 1:+0.0/+0.0'
 assert(J.english(line)=='grid at the lights: 20 AI set exactly on their place (moved by 1.20 m on average, remaining gap at most 0.01 m, 0 correction(s), 0 not on their pose; direction -1, offset +0.47 m) ; long/lat gaps (m) 1:+0.0/+0.0',tostring(J.english(line)))
 line='grille: Driver_3 part de l arriere de la grille (plus avec le peloton a la fin du tour de formation), sans etre attendue'
 assert(J.english(line)=='grid: Driver_3 starts from the back of the grid (no longer with the pack at the end of the formation lap), not waited for',tostring(J.english(line)))
end

-- H2 bis : ordre réel des voitures à la formation de la grille : dans chaque colonne, une voiture arrivée derrière une
-- voiture dont la place est derrière la sienne part de l'arrière (elle ne pourrait rejoindre sa place sans la doubler).
tests.LOCK_GRID_ORDER_BY_COLUMN_204=function()
 local log=require('src/util').newLog(200,1000,0)
 -- Ordre sur la piste (tête d'abord), par place : 1,2,4,6,7,5,8,9 : la 5 est derrière la 7 (même colonne).
 local function run(phys,player)
  local fr={length=L,cars={}}; local order={}
  for k,slot in ipairs(phys) do fr.cars[slot]={spline=((-300-k*15)/L)%1,name='C'..slot,player=slot==player} end
  local n=#phys; for k=1,n do order[k]=phys[k] end; table.sort(order)
  local g={backN=0}
  local moved=G.orderCars(g,fr,order,n,0,0,log,nil)
  return moved,order,g
 end
 local moved,order,g=run({1,2,4,6,7,5,8,9,3})
 -- Colonne impaire sur la piste : 1,7,5,9,3 : la plus longue suite dans l'ordre garde 3 voitures ; 2 partent de l'arrière.
 assert(moved==2 and g.backN==2,'two cars of the odd column out of order ('..moved..')')
 local at={}; for k,i in ipairs(order) do at[i]=k end
 assert(at[2]<at[4] and at[4]<at[6] and at[6]<at[8] and at[8]<=7,'even column untouched')
 assert(at[3]==9 or at[3]==8,'car 3 (last on the track, place 3) to the back')
 -- Voitures de colonnes différentes côte à côte ou inversées (2 devant 1, 6 devant 5) : personne ne bouge.
 moved=run({2,1,4,3,6,5,8,7})
 assert(moved==0,'neighbours of different columns swapped: nobody moved ('..moved..')')
 moved=run({1,2,3,4,5,6,7,8}); assert(moved==0,'in order: nobody moved')
 -- Le joueur n'est jamais déplacé par cette règle.
 local m2,o2=run({1,2,4,6,7,5,8,9},5)
 assert(m2==0 and o2[4]==5,'the player keeps his place whatever his position on the track ('..table.concat(o2,',')..')')
 -- Avec des renvoyées et des retardataires déjà en fin de liste : gardées, renvoyées, déplacées, retardataires.
 local fr={length=L,cars={}}; local phys={1,2,3,6,4,8,5,7}
 for k,slot in ipairs(phys) do fr.cars[slot]={spline=((-300-k*15)/L)%1,name='C'..slot} end
 fr.cars[9]={spline=0.5,name='C9'}; fr.cars[10]={spline=((-600)/L)%1,name='C10'}
 local order={1,2,3,4,5,6,7,8,10,9}; local g3={backN=2}
 local m3=G.orderCars(g3,fr,order,10,1,0,log,nil)
 assert(m3==1 and g3.backN==3 and order[8]==10 and (order[9]==4 or order[9]==6) and order[10]==9,'kept, sent back (10), moved, late (9) : '..table.concat(order,','))
 local J=require('src/journal')
 local line='grille: Driver_3 part de l arriere de la grille (plus a sa place dans la file a la fin du tour de formation)'
 assert(J.english(line)=='grid: Driver_3 starts from the back of the grid (no longer in its place in the queue at the end of the formation lap)',tostring(J.english(line)))
end

-- H6 : IA tenue à sa place de la grille : volant droit (pilote, Monza, 18 novembre 13:05 : « les roues avant ne sont pas
-- droites, le volant est tourné »), rendu à l'extinction.
tests.LOCK_GRID_WHEELS_STRAIGHT_204=function()
 local e,f=scene(4); local fr={}
 hold(f,2,-1.2,0.4,6,fr)
 run(e,f,3,-1,-0.49,0,fr)
 assert(e.grid.held[2] and e.commands[2].gridStraight==true and e.commands[2].stopHold,'held at its place: wheels straight asked')
 assert(not e.commands[3].gridStraight,'still on its way: nothing')
 -- Extinction : plus de volant imposé.
 e.incidents.standing='none'; E.step(e,f,1/60)
 assert(not e.commands[2].gridStraight,'after the grid: released')
 -- Applicateur : frein tenu et direction à zéro tant que demandé ; frein 0 et direction d'origine ensuite ; jamais aux stands.
 local host=require('tests/host').create(true)
 local A=require('src/applier'); local a=A.new(); assert(A.access(a))
 local e2,f2=F.scene('C',4)
 for _,cmd in ipairs(e2.commands) do cmd.active=false; cmd.gridStraight=nil; cmd.brake=0 end
 for _,k in ipairs({2,3}) do local cmd=e2.commands[k]; cmd.active=true; cmd.levelOwned=false; cmd.aggressionOwned=false; cmd.cautionOwned=false; cmd.offset=0 end
 e2.commands[2].gridStraight=true
 A.apply(a,f2,e2.commands,e2.g,e2.time)
 assert(host.controls[1].steer==0 and host.controls[1].brake==K.brakeMax,'steering forced to zero, brake held ('..tostring(host.controls[1].steer)..', '..tostring(host.controls[1].brake)..')')
 e2.commands[2].gridStraight=nil
 A.apply(a,f2,e2.commands,e2.g,e2.time+0.1)
 assert(host.controls[1].steer==math.huge and host.controls[1].brake==0,'released: original steering, no brake')
 e2.commands[3].gridStraight=true; f2.cars[3].pit=true
 local before=host.controls[2].steer
 A.apply(a,f2,e2.commands,e2.g,e2.time+0.2)
 assert(host.controls[2].steer==before,'in the pits: never')
 e2.g.useBrakeAssist=false; e2.commands[2].gridStraight=true
 A.apply(a,f2,e2.commands,e2.g,e2.time+0.3)
 assert(host.controls[1].steer==math.huge,'brake assist switched off by the user: no control override')
end

-- H7 : file stricte qui se resserre au freinage (pilote, Monza, 18 novembre 13:33 : file tassée jusqu'à l'arrêt à la
-- première chicane, quatre voitures à 0 km/h, touchette à 12 km/h d'écart) : six voitures à 2 m les unes des autres
-- derrière une tête à 60 km/h : aucune ne s'arrête, la file se rouvre d'elle-même.
tests.LOCK_FORMATION_CONVOY_NO_CASCADE_204=function()
 local function chain(rate)
  local keep=Convoy.CK.closeRate; Convoy.CK.closeRate=rate
  local z,v={},{}
  for k=1,6 do z[k]=-(k-1)*(4.4+2); v[k]=60/3.6 end
  local slowest=math.huge; local closest=math.huge
  for _=1,20*60 do
   for k=2,6 do
    local bumper=z[k-1]-z[k]-4.4
    local cap=Convoy.cap(v[k-1],bumper,v[k])
    -- IA simple : suit son plafond (6 m/s² au freinage, 4 à l'accélération), jamais plus de 60 km/h.
    local want=math.min(cap,60/3.6)
    if v[k]>want then v[k]=math.max(want,v[k]-6/60) else v[k]=math.min(want,v[k]+4/60) end
    if v[k]<slowest then slowest=v[k] end
    if bumper<closest then closest=bumper end
   end
   for k=1,6 do z[k]=z[k]+v[k]/60 end
  end
  Convoy.CK.closeRate=keep
  return slowest*3.6,closest,z[5]-z[6]-4.4
 end
 local slowest,closest,last=chain(Convoy.CK.closeRate)
 assert(slowest>=40,string.format('nobody slows below 40 km/h behind a head at 60 (%.0f km/h)',slowest))
 assert(closest>=1.5 and last>=5.5,string.format('no contact, the queue opens up again (%.1f m, then %.1f m)',closest,last))
 local before=chain(1)
 assert(before<=25 and slowest-before>=15,string.format('scene: with the old rate the tail drops to walking pace (%.0f km/h, %.0f now)',before,slowest))
end

-- H8 : arrivée sur la place en roulant (pilote, Monza, 18 novembre 13:33 : « elles arrivent mal positionnées et on les
-- repositionne après » ; replay : arrêt 1 à 1,5 m trop court, coup de volant dans les 10 derniers mètres).
tests.LOCK_GRID_DRIVE_TO_POSE_204=function()
 assert(G.GK.poseStop==0.3)
 local e,f=scene(4); local g=e.grid
 -- 1,2 m avant sa pose, au pas : pas encore tenue (avant : tenue dès 1,5 m), plafond au pas.
 local a=park(f,2,-1.2,0,0); a.kmh=8; a.speed=8/3.6; f.senseOff=true
 E.step(e,f,1/60)
 assert(not g.held[2] and e.commands[2].speedLimit<=K.gridCrawlKmh+1e-6 and not e.commands[2].stopHold,'1.2 m short of its pose: still driving to it')
 -- À 0,25 m : tenue.
 a=park(f,2,-0.25,0,0); a.kmh=6; a.speed=6/3.6; E.step(e,f,1/60)
 assert(g.held[2] and e.commands[2].stopHold,'0.25 m from its pose: held')
 -- Sans pose relevée (grille sans tour de formation) : comme avant, tenue à K.gridHoldDistance m.
 local e2,f2=scene(4); e2.grid.pose=nil
 local b=park(f2,2,-1.2,0,0); b.kmh=8; b.speed=8/3.6; f2.senseOff=true; E.step(e2,f2,1/60)
 assert(e2.grid.held[2],'no recorded pose: held within K.gridHoldDistance m as before')
 -- Consigne de colonne : jamais remplacée par l'écart mesuré dans les derniers mètres (0,3 m d'écart mesuré, au pas).
 local e3,f3=scene(4); local g3=e3.grid
 local k=g3.slotOf[3]; local sign=e3.g.offsetSign; local want=sign<0 and -g3.slots[k].lateral or g3.slots[k].lateral
 local c=park(f3,3,-300,0,0); c.kmh=60; c.speed=60/3.6; f3.senseOff=true
 for _=1,10*60 do E.step(e3,f3,1/60) end
 assert(math.abs(e3.commands[3].offset-want)<1e-6,'scene: column reached')
 c=park(f3,3,-6,0.3,0); c.kmh=10; c.speed=10/3.6; c.splineLat=c.x; c.splineLatValid=true
 for _=1,30 do E.step(e3,f3,1/60); assert(math.abs(e3.commands[3].offset-want)<1e-6 and not g3.frozen[3],'last metres at a crawl: the column command, never the measured lateral') end
 c=park(f3,3,-0.2,0.3,0); c.kmh=5; c.speed=5/3.6; E.step(e3,f3,1/60)
 assert(g3.held[3] and math.abs(e3.commands[3].offset-want)<1e-6 and not g3.frozen[3],'held: still the column command')
 -- Consigne suivie strictement et agressivité native nulle sur le chemin de la grille ; rendu après.
 assert(e3.commands[3].gridStrict==true and e3.commands[3].gridCalm==true and e3.commands[2].gridStrict==true,'grid cars: strict lateral command, calm')
 e3.incidents.standing='none'; E.step(e3,f3,1/60)
 assert(not e3.commands[3].gridStrict and not e3.commands[3].gridCalm,'after the grid: released')
 local host=require('tests/host').create(true)
 local A=require('src/applier'); local ap=A.new(); assert(A.access(ap))
 local e4,f4=F.scene('C',4)
 for _,cmd in ipairs(e4.commands) do cmd.active=false end
 local cmd=e4.commands[2]; cmd.active=true; cmd.levelOwned=false; cmd.aggressionOwned=false; cmd.cautionOwned=false; cmd.offset=0; cmd.gridStrict=true; cmd.gridCalm=true
 A.apply(ap,f4,e4.commands,e4.g,e4.time)
 assert(host.offsetOverrides and host.offsetOverrides[1]==true,'offset written with the native avoidance overridden, even at zero')
 assert(host.cars[1].aiAggression==0,'native aggression set to zero ('..tostring(host.cars[1].aiAggression)..')')
 cmd.gridStrict=nil; cmd.gridCalm=nil
 A.apply(ap,f4,e4.commands,e4.g,e4.time+1)
 assert(host.offsetOverrides[1]==false and host.cars[1].aiAggression==f4.cars[2].aiAggression and f4.cars[2].aiAggression>0,'given back after the grid ('..tostring(host.offsetOverrides[1])..', '..tostring(host.cars[1].aiAggression)..')')
end

return tests
