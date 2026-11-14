-- Beta 1.64, lot 1 (référentiel des comportements pilotes, situations 08-01 à 08-06 et 08-13 ; décisions du pilote du
-- 13 novembre : repères F1 pour toutes les catégories, fautes jugées sur le duel enregistré avant la corde) : duel au
-- virage partagé (src/priority.lua), sens du virage lu sur la piste (src/snapshot.lua), jugement des contacts
-- (src/blame.lua), géométrie des modèles au journal (src/engine.lua). Noms LOCK_*_164 (tests/LOCKS.md). Chargé par
-- tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local K=require('src/config').K
local Priority=require('src/priority')
local Snapshot=require('src/snapshot')
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function logged(e,text) return count(e,text)>0 end

-- Voiture de cap +z (repère des scènes : x latéral), essieu avant à front m, rétroviseur mirrorBack m derrière lui.
local function car(x,z,o)
 o=o or {}
 local front=o.front or 1.6
 return {x=x,z=z,lx=0,lz=1,length=o.length or 5,axleKnown=o.known~=false,axleFront=front,axleRear=front-3.6,mirror=front-(o.mirrorBack or 1.6),yawRate=o.yaw or 0,offtrack=o.off or false}
end
local function rel(a,b) local dx,dz=b.x-a.x,b.z-a.z; return dx*a.lx+dz*a.lz,dx*(-a.lz)+dz*a.lx end
local function duel(a,b,turn)
 local long,lat=rel(a,b); local out={}
 Priority.duel(a,b,long,lat,turn or 0,out)
 return out
end

-- Repères F1 (08-03, 08-05, 08-06) : intérieur au moins au niveau du rétroviseur adverse, extérieur devant l'essieu avant
-- adverse ; bande d'incertitude : les deux gardent leur ligne ; géométrie ou sens inconnus : règle du nez à l'identique.
tests.LOCK_DUEL_F1_164=function()
 local tol=K.duelTolerance
 assert(K.duelAxles==true and tol>0 and tol<0.5,'constants')
 -- b à x=-2 (lat +2 dans le repère de a) ; virage vers le côté lat positif (turn=1) : b à l'intérieur.
 -- Intérieur b, essieu avant 0,5 m devant le rétroviseur de a (b 1,1 m derrière a) : droit établi pour b ; a, devant,
 -- garde aussi le sien (extérieur devant) : personne ne cède.
 local o=duel(car(0,0),car(-2,-1.1),1)
 assert(o.mode=='axes' and o.inside==2 and o.b=='oui' and o.a=='oui' and not Priority.yields(o),'inside level with the mirror, outside ahead: both keep')
 -- Intérieur b 1,2 m derrière le rétroviseur de a (b 2,8 m derrière) : b n'a pas de droit, a l'a : b cède (vu de b).
 o=duel(car(-2,-2.8),car(0,0),1)
 assert(o.inside==1 and o.a=='non' and o.b=='oui' and Priority.yields(o),'inside behind the mirror: gives way ('..o.a..'/'..o.b..')')
 -- Extérieur a 0,5 m devant l'essieu avant de b (intérieur) : droit pour a ; b au rétroviseur de a ou devant : les deux.
 o=duel(car(0,0.5),car(-2,0),1)
 assert(o.inside==2 and o.a=='oui' and o.b=='oui','outside ahead of the front axle: right to room')
 -- Extérieur a 0,5 m derrière l'essieu avant de b (a 0,8 m derrière, essieu avant plus en avant de 0,3 m) : a n'a pas de droit et cède ; même si son nez est devant (voiture
 -- plus longue) : le nez ne décide plus (08-01).
 o=duel(car(0,-0.8,{length=5.6,front=1.9}),car(-2,0),1)
 assert(o.a=='non' and o.b=='oui' and Priority.yields(o),'outside behind the front axle: gives way')
 -- Bande d'incertitude : écart d'essieux sous la tolérance : incertain, personne ne cède (jamais une décision opposée
 -- d'une image à l'autre sur le bruit).
 for _,d in ipairs({-tol*0.9,0,tol*0.9}) do
  o=duel(car(0,d),car(-2,0),1)
  assert(o.a=='incertain' and not Priority.yields(o),'uncertainty band '..d)
 end
 -- Voiture hors piste : jamais de droit.
 o=duel(car(0,1,{off=true}),car(-2,0),1)
 assert(o.a=='non','off track: no right')
 -- Sens du virage inconnu (turn 0, lacet faible) : règle du nez ; lacet des deux voitures : sens connu (lacet positif :
 -- centre du virage côté lat négatif).
 o=duel(car(0,0,{yaw=0.01}),car(-2,-1.1,{yaw=0.01}),0)
 assert(o.mode=='nez','unknown turn: nose rule')
 o=duel(car(0,0,{yaw=-0.3}),car(-2,-1.1,{yaw=-0.3}),0)
 assert(o.mode=='axes' and o.inside==2,'turn from the yaw rate (negative yaw: centre on the positive lat side)')
 o=duel(car(0,0,{yaw=0.3}),car(-2,-1.1,{yaw=0.3}),0)
 assert(o.mode=='axes' and o.inside==1,'turn from the yaw rate (positive yaw: centre on the negative lat side)')
 -- Géométrie inconnue : exactement la règle du nez de la Beta 1.59 (K.cornerNoseMargin).
 for _,dz in ipairs({-3,-2.3,-2.1,0,2.1,2.3,3}) do
  local a,b=car(0,0,{known=false}),car(-2,dz,{known=false})
  o=duel(a,b,1)
  local long=rel(a,b)
  local old=long+(b.length-a.length)*0.5>K.cornerNoseMargin
  assert(o.mode=='nez' and Priority.yields(o)==old,'nose fallback identical at '..dz)
 end
 local saved=K.duelAxles; K.duelAxles=false
 o=duel(car(0,0),car(-2,-2.8),1); K.duelAxles=saved
 assert(o.mode=='nez','switch off: nose rule')
end

-- Sens du virage sur la piste (src/snapshot.lua, M.turnAhead) : même convention que le repère latéral de la perception
-- (côté du centre du virage), dans les deux sens ; ligne droite : inconnu.
tests.LOCK_DUEL_TURN_SIGN_164=function()
 local savedVec,savedTo=rawget(_G,'vec3'),ac.trackProgressToWorldCoordinateTo
 local L,R=5000,150
 local function circle(side) -- centre du virage à x = side*R ; départ à l'origine, cap +z
  return function(p,r) local s=p*L; local th=s/R; r.x=side*(R-R*math.cos(th)); r.y=0; r.z=R*math.sin(th) end
 end
 local ok,err=pcall(function()
  rawset(_G,'vec3',function() return {x=0,y=0,z=0} end)
  for _,side in ipairs({1,-1}) do
   ac.trackProgressToWorldCoordinateTo=circle(side)
   local turn=Snapshot.turnAhead(0,L)
   -- Centre (side*R, 0) vu d'une voiture à l'origine de cap +z (repère de src/perception.lua).
   local _,centreLat=rel(car(0,0),{x=side*R,z=0})
   assert(turn~=0 and (turn>0)==(centreLat>0),'side '..side..': turn '..turn..', centre lat '..centreLat)
  end
  ac.trackProgressToWorldCoordinateTo=function(p,r) r.x=0; r.y=0; r.z=p*L end
  assert(Snapshot.turnAhead(0,L)==0,'straight: unknown')
  ac.trackProgressToWorldCoordinateTo=function() error('missing') end
  assert(Snapshot.turnAhead(0,L)==0,'no track data: unknown')
 end)
 rawset(_G,'vec3',savedVec); ac.trackProgressToWorldCoordinateTo=savedTo
 assert(ok,err)
end

-- Pilotage (08-01, 08-03) : une IA intérieure dont l'essieu avant n'atteint pas le rétroviseur de l'autre lui laisse le
-- virage même nez à moins de K.cornerNoseMargin m (règle du nez : elle gardait sa ligne) ; au niveau du rétroviseur, elle
-- garde sa ligne ; journal « sans droit a l espace ».
local function corner(sign,behind,o)
 o=o or {}
 local e,f=F.scene('C',4)
 e.g.offsetSign=sign; e.g.sideSign=sign; if o.san then e.profiles.C.sanContact=true end; E.changed(e)
 for i=1,f.count do f.cars[i].sideDot=sign end
 F.place(f,1,-5000,100); f.started=true; F.tick(e,f,30)
 for _,i in ipairs({2,3}) do local c=f.cars[i]; c.length=5; c.axleKnown=o.known~=false; c.axleFront=1.6; c.axleRear=-2; c.mirror=0; c.geomRead=true end
 -- Voitures côte à côte (2 m d'écart latéral), voiture 3 behind m devant ; sens du virage donné par le lacet.
 local v3=o.kmh3 or 150
 F.place(f,2,0,150,-2*sign); F.place(f,3,behind,v3,0); F.tick(e,f,0.3)
 local yaw=o.yaw or 0.3*sign
 for k=1,30 do
  F.place(f,2,0,150,-2*sign); F.place(f,3,behind,v3,0)
  f.cars[2].brake=0.6; f.cars[3].brake=0.6; f.cars[2].yawRate=yaw; f.cars[3].yawRate=yaw
  F.tick(e,f,1/60)
 end
 return e,f
end
tests.LOCK_DUEL_DIRECTOR_164=function()
 for _,sign in ipairs({1,-1}) do
   -- Lacet positif : centre du virage du côté latéral négatif (src/priority.lua) ; voiture 3 à x=0, voiture 2 à x=-2*sign :
  -- la voiture 2 est à l'extérieur quand yaw*sign>0, à l'intérieur sinon.
  -- Affinage 1.64 (Monza S7) : voiture 3 2 m devant (nez à moins de 2,2 m : la règle du nez ne fait céder personne).
  -- Intérieure, l'essieu avant de la voiture 2 est 0,4 m derrière le rétroviseur de l'autre : elle cède (ne force pas le
  -- virage). Extérieure sans droit : garde sa ligne sans lever le pied (comme la Beta 1.63).
  for _,y in ipairs({0.3,-0.3}) do
   local e=corner(sign,2,{yaw=y})
   local outside=y*sign>0
   assert((e.states[2].cornerGiveTo==3)==(not outside),sign..' / '..y..': inside without the right gives way, outside keeps its line (2 m behind)')
   if outside then assert((e.states[2].cornerLift or 1)>=1,sign..': outside without the right never lifts') end
  end
  -- Extérieure 1,5 m derrière l'essieu avant : sans droit, mais garde sa ligne (avant l'affinage : elle cédait).
  for _,y in ipairs({0.3,-0.3}) do
   local e=corner(sign,1.5,{yaw=y})
   assert(e.states[2].cornerGiveTo==0,sign..' / '..y..': 1.5 m: nobody gives')
  end
  -- Géométrie inconnue : règle du nez (1,5 m < 2,2 m) : personne ne cède, comme la Beta 1.63.
  local e=corner(sign,1.5,{known=false})
  assert(e.states[2].cornerGiveTo==0 and e.states[3].cornerGiveTo==0,sign..': unknown geometry: nose rule, nobody gives')
  -- Côte à côte, essieux au même niveau : bande d'incertitude, personne ne cède.
  e=corner(sign,0)
  assert(e.states[2].cornerGiveTo==0 and e.states[3].cornerGiveTo==0,sign..': level: nobody gives')
 end
 local any=corner(1,2,{yaw=-0.3})
 assert(any.states[2].cornerGiveTo==3 and logged(any,'(interieur sans droit a l espace)') and (any.stats.duelAxes or 0)>=1,'journal line and counter')
end

-- Jugement des contacts (08-13) : le duel enregistré à l'entrée décide (même verdict que la priorité au virage) ;
-- contact côte à côte en virage sans duel enregistré : incident de course, jamais une faute.
tests.LOCK_DUEL_BLAME_RECORD_164=function()
 local function judged(yaw,prior,ahead)
  -- 15 km/h d'écart : ni touchette ni contact léger (jugé).
  local e,f=corner(1,ahead or 1.5,{yaw=yaw,san=true,kmh3=135})
  if not prior then for _,i in ipairs({2,3}) do local s=e.states[i]; if s.duelRec1 then s.duelRec1.at=-math.huge; s.duelRec2.at=-math.huge end end end
  f.cars[2].collidedWith=3; F.tick(e,f,1/60); f.cars[2].collidedWith=nil
  F.tick(e,f,K.blameOutcome+0.4)
  return e
 end
 -- Voiture 2 extérieure 1,5 m derrière l'essieu avant (sans droit, garde sa ligne) : en tort au contact ; intérieure au même
 -- endroit (essieu au niveau du rétroviseur : incertain) : incident de course.
 local gave,kept=judged(0.3,true),judged(-0.3,true)
 assert(logged(gave,'virage sans droit a l espace : Driver_2 en tort'),'the car without the right to room is at fault')
 assert(count(kept,'responsabilite:')==0,'uncertain right: not at fault')
 local none=judged(0.3,false)
 assert(logged(none,'(virage sans duel enregistre)') and count(none,'responsabilite:')==0,'no recorded duel: racing incident')
 -- Même avec le nez 3 m devant (la photo du choc aurait donné une faute) : sans duel enregistré, incident de course.
 local far=judged(0.3,false,3)
 assert(logged(far,'(virage sans duel enregistre)') and count(far,'responsabilite:')==0,'no recorded duel, nose 3 m ahead: still a racing incident')
 -- Duel enregistré il y a plus de K.duelRecordKeep s : oublié.
 local s=gave.states[2]; local id=gave.frame.cars[3].identity or gave.frame.cars[3].id
 Priority.record(s,3,id,{a='non',b='oui',mode='axes'},100)
 assert(Priority.recorded(gave,gave.frame,2,3,100+K.duelRecordKeep-0.1)=='non','kept while fresh')
 assert(Priority.recorded(gave,gave.frame,2,3,100+K.duelRecordKeep+0.1)==nil,'forgotten after duelRecordKeep')
 -- Vu de l'autre voiture : droits inversés ; autre identité : aucun duel.
 local mine,theirs=Priority.recorded(gave,gave.frame,3,2,100+1)
 assert(mine=='oui' and theirs=='non','seen from the other car')
 Priority.record(s,3,'autre',{a='non',b='oui',mode='axes'},200)
 assert(Priority.recorded(gave,gave.frame,2,3,200.5)==nil,'identity checked')
end

-- Géométrie au journal (src/engine.lua) : une ligne par modèle, mesures ou repli.
tests.DUEL_GEOMETRY_LOG_164=function()
 local e,f=F.scene('C',4)
 F.place(f,1,-5000,100); f.started=true
 for i=2,4 do local c=f.cars[i]; c.id=i==4 and 'modele_b' or 'modele_a'; c.geomRead=true end
 local c=f.cars[2]; c.axleKnown=true; c.axleFront=1.62; c.axleRear=-1.98; c.mirror=0.1; c.mirrorEstimated=false; c.length=5.4
 f.cars[3].axleKnown=true; f.cars[3].axleFront=1.62; f.cars[3].axleRear=-1.98; f.cars[3].mirror=0.1; f.cars[3].length=5.4
 f.cars[4].axleKnown=false; f.cars[4].lengthKnown=false
 F.tick(e,f,1)
 assert(count(e,'geometrie: modele_a, longueur 5.40 m, essieu avant +1.62 m, empattement 3.60 m, retroviseur +0.10 m (devant les yeux du pilote)')==1,'measured model, once')
 assert(count(e,'geometrie: modele_b, longueur inconnue')==1,'length fallback logged')
end

tests.K_164A=function()
 assert(K.duelRecordKeep>K.cornerEntryWindow and K.duelTurnAhead>K.duelTurnStep and K.duelBaseMin<K.duelBaseMax and K.duelGeomWait>0)
end

return tests
