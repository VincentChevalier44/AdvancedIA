-- Beta 1.60, fusion de la tranche A, borne de décalage par côté et corrections de la relecture indépendante de la
-- fusion B-E. Noms terminés par _160M2. Chargé par tests/extended.lua.
-- Les mesures latérales viennent de F.sense (tests/fixture.lua), qui ne donne que ce que src/snapshot.lua donne en jeu.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local D=require('src/director')
local J=require('src/journal')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function logged(e,text) return count(e,text)>0 end
local function widths(a,l,r,l1,r1,l2,r2)
 a.leftWidth=l; a.rightWidth=r; a.leftAhead=l1 or l; a.rightAhead=r1 or r; a.leftAhead2=l2 or l1 or l; a.rightAhead2=r2 or r1 or r
end

-- Borne de décalage : vers le grand côté, la place réelle de ce côté ; vers le petit côté, la borne d'origine ; les
-- deux signes mesurés du décalage (offsetSign) et les deux côtés.
tests.REACH_PER_SIDE_160M2=function()
 assert(K.reachWideShare==0.8 and K.reachWideMeters==4 and K.reachEdgeMargin==0.5 and K.reachLook1==1 and K.reachLook2==2 and K.reachLookMin==15)
 local e,f=F.scene('P',3); local s,a,p=e.states[2],f.cars[2],e.run
 s.state='YIELD_IN' -- manœuvre : la place du grand côté ne sert pas à la conduite libre
 local half=a.width*0.5
 local old=(1.5-half)/10.5
 for _,sign in ipairs({1,-1}) do
  local g={offsetSign=sign}
  -- Trajectoire au bord gauche : 1,5 m à gauche, 10,5 m à droite. Décalage écrit = décalage × signe ; positif : droite.
  widths(a,1.5,10.5)
  local right,left=D.reachable(s,a,p,g,0.8*sign),D.reachable(s,a,p,g,-0.8*sign)
  assert(math.abs(math.abs(right)-K.reachWideMeters/10.5)<1e-9 and right*sign>0,'wide side (right): 4 m off the line: '..right)
  assert(math.abs(math.abs(left)-old)<1e-9 and left*sign<0,'narrow side (left): the original bound: '..left)
  assert(math.abs(D.room(s,a,p,true)-K.reachWideMeters)<1e-9 and math.abs(D.room(s,a,p,false)-old*1.5)<1e-9,'room per side in metres')
  -- Trajectoire au bord droit : miroir.
  widths(a,10.5,1.5)
  right,left=D.reachable(s,a,p,g,0.8*sign),D.reachable(s,a,p,g,-0.8*sign)
  assert(math.abs(math.abs(left)-K.reachWideMeters/10.5)<1e-9 and left*sign<0,'wide side (left): '..left)
  assert(math.abs(math.abs(right)-old)<1e-9,'narrow side (right): '..right)
 end
 local g={offsetSign=1}
 -- Côté presque aussi large que l'autre mais étroit : jamais à moins d'une demi-voiture plus la marge du bord.
 for w=2,12,0.5 do
  widths(a,1,w)
  local o=D.reachable(s,a,p,g,1)
  if o>(1-half)/w+1e-9 then assert(w*(1-o)>=half+K.reachEdgeMargin-1e-9,'edge margin kept at '..w..' m: '..o) end
  assert(o<=math.min(p.maxSideOffset,K.reachWideShare)+1e-9 and o*w<=math.max(K.reachWideMeters,1-half)+1e-9,'share and metres caps at '..w)
 end
 -- Piste symétrique : rien ne change (borne d'origine).
 widths(a,6,6); assert(math.abs(D.reachable(s,a,p,g,1)-math.min(p.maxSideOffset,(6-half)/6))<1e-9,'symmetric track: unchanged')
 -- Largeurs lues plus loin absentes (lecture manquée) : borne d'origine.
 widths(a,1.5,10.5); a.leftAhead2=0
 assert(math.abs(D.reachable(s,a,p,g,0.8)-old)<1e-9,'no look-ahead: the original bound')
 -- Plus loin, ce côté devient le petit côté (la trajectoire traverse la piste) : la borne se referme déjà.
 widths(a,1.5,10.5,1.5,10.5,10.5,1.5)
 assert(math.abs(D.reachable(s,a,p,g,0.8)-old)<1e-9,'side narrow 2 s ahead: the original bound now')
 widths(a,1.5,10.5,10.5,1.5,1.5,10.5)
 assert(math.abs(D.reachable(s,a,p,g,0.8)-old)<1e-9,'side narrow 1 s ahead: the original bound now')
 -- Toujours le grand côté plus loin, même plus étroit : la borne en mètres tient (4 m hors de la trajectoire).
 widths(a,1.5,10.5,3,9,5.9,6.1)
 assert(math.abs(D.reachable(s,a,p,g,0.8)-K.reachWideMeters/10.5)<1e-9,'still the wide side ahead: kept')
 -- Zone du circuit et décalage maximal du profil : toujours respectés.
 widths(a,1.5,10.5); s.zone.maxOffset=0.2
 assert(math.abs(D.reachable(s,a,p,g,0.8)-0.2)<1e-9,'track zone cap kept'); s.zone.maxOffset=1
 -- Sens latéral non mesuré : aucun décalage.
 assert(D.reachable(s,a,p,{offsetSign=0},0.8)==0)
end

-- Trajectoire qui traverse la piste (10,5 m → 1,5 m du côté où la voiture s'est écartée) : avec les largeurs lues 1 et
-- 2 s plus loin, la rampe latérale ramène la voiture à temps ; aucune roue hors de la piste (échelle par côté de CSP).
tests.REACH_EDGE_SWEEP_160M2=function()
 for _,profile in ipairs({'J','P','C'}) do
  for _,kmh in ipairs({80,160,280}) do
   for _,sweep in ipairs({1,2,4}) do
    local e,f=F.scene(profile,3); local s,a,p,g=e.states[2],f.cars[2],e.run,e.runtimeG
    local row={left=false,right=false}
    a.kmh=kmh; a.speed=kmh/3.6
    local half=a.width*0.5
    -- Largeur à droite à l'instant t : 10,5 m, puis rampe vers 1,5 m en « sweep » s à partir de t=3 s ; total 12 m.
    local function right(t) return t<=3 and 10.5 or t>=3+sweep and 1.5 or 10.5-9*(t-3)/sweep end
    s.state='YIELD_HOLD'; s.direction=1; s.offset=0; s.filtered=0; s.velocity=0
    local worst=math.huge; local now=e.time; local peak=0
    for frame=1,60*(8+sweep) do
     local t=frame/60; now=now+1/60
     local r=right(t); local r1=right(t+K.reachLook1); local r2=right(t+K.reachLook2)
     widths(a,12-r,r,12-r1,r1,12-r2,r2)
     local o=D.lateral(s,0.8,row,a,p,g,1/60,now)
     peak=math.max(peak,o)
     -- Position dans l'échelle du côté : o × largeur du côté visé ; marge entre la roue et le bord.
     if o>0 then worst=math.min(worst,r*(1-o)-half) end
    end
    assert(peak*10.5>2.5,'the car really moved aside on the wide side: '..peak*10.5)
    assert(worst>=0,string.format('wheel off the track: %.2f m (profile %s, %d km/h, sweep %d s)',worst,profile,kmh,sweep))
   end
  end
 end
end

-- Lignes du journal : décalage voulu, atteint et permis à la fin d'un dépassement ; côté visé à la fin d'une cession.
tests.PASS_END_OFFSETS_160M2=function()
 local line='depassement fini: A -> B : sans progres apres 16.1 s (ecart mini 4 m ; decalage voulu 0.65, atteint 0.38 soit 4.0 m vers la droite, borne la plus basse 0.05)'
 assert(J.english(line)=='overtake ended: A -> B: no progress after 16.1 s (min gap 4 m; offset wanted 0.65, reached 0.38, i.e. 4.0 m to the right, lowest bound 0.05)',J.english(line))
 local y='cession finie: A -> B : suiveur passe apres 6.2 s (decalage voulu 0.80, atteint 0.38 soit 4.0 m vers la gauche, piste alors 10.5 m a gauche, 1.5 m a droite ; borne la plus basse 0.05)'
 assert(J.english(y):find('reached 0.38, i.e. 4.0 m to the left, track then 10.5 m on the left, 1.5 m on the right; lowest bound 0.05)',1,true),J.english(y))
 -- Tentative réelle : la ligne porte les trois valeurs.
 local e,f=F.scene('P',3); e.profiles.P.startDelay=0; e.profiles.P.startRelax=0; e.profiles.P.yieldEnabled=false; E.changed(e)
 F.place(f,1,-5000,100); F.front(e,f,20,30); F.tick(e,f,0.2)
 local s=e.states[2]; local seen=false
 for _=1,6*60 do F.front(e,f,20,30); F.tick(e,f,1/60); if s.state=='OVT_IN' or s.state=='OVT_HOLD' then seen=true end; if seen and s.pPeak and s.pPeak>0.1 then break end end
 assert(seen and s.pWant and s.pWant>0.3 and s.pBound and s.pBound>0,'offsets recorded during the attempt')
 F.place(f,3,-300,100); s.nextPerception=0; F.tick(e,f,6)
 local found
 for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('depassement fini:',1,true) then found=r.message end end
 assert(found and found:find(' ; decalage voulu %d%.%d%d, atteint %d%.%d%d soit %d+%.%d m vers la %a+, borne la plus basse %d%.%d%d%)$'),'pass end line carries the offsets: '..tostring(found))
 assert(s.pWant==nil and s.pPeak==nil and s.pBound==nil and s.pPeakM==nil,'record cleared at the end')
end

-- Instantané : largeurs lues 1 et 2 s plus loin pour les IA pilotées (jamais pour le joueur) ; écart latéral selon la
-- piste de toutes les voitures hors des stands, joueur compris, seulement quand le jugement des collisions le demande.
tests.SNAPSHOT_AHEAD_AND_TRACK_LAT_160M2=function()
 assert(K.blameLatPeriod==0.1 and K.blameCornerG==3)
 local host=require('tests/host').create(true)
 local Snapshot=require('src/snapshot'); local s=Snapshot.new()
 local asked={}; local sides=ac.getTrackAISplineSides
 ac.getTrackAISplineSides=function(v) asked[#asked+1]=v; return {x=3,y=9} end
 local ok,err=pcall(function()
  -- Lectures décalées d'une voiture à l'autre (une image par indice) : quelques images suffisent.
  for k=0,7 do Snapshot.read(s,1/60,10+k/600) end
  local ai,player=s.cars[3],s.cars[1]
  assert(ai.control and ai.leftWidth==3 and ai.rightWidth==9 and ai.leftAhead==3 and ai.rightAhead==9 and ai.leftAhead2==3 and ai.rightAhead2==9,'AI: widths here and at the two points ahead')
  assert(player.player and player.leftAhead==0 and player.rightAhead2==0,'player: no look-ahead read')
  -- Points demandés : K.reachLook1 et K.reachLook2 s plus loin (K.reachLookMin m au moins par pas).
  local d1=math.max(ai.speed*K.reachLook1,K.reachLookMin)/s.length; local d2=math.max(ai.speed*K.reachLook2,K.reachLookMin*2)/s.length
  local seen1,seen2=false,false
  for _,v in ipairs(asked) do if math.abs(v-(ai.spline+d1)%1)<1e-9 then seen1=true end; if math.abs(v-(ai.spline+d2)%1)<1e-9 then seen2=true end end
  assert(seen1 and seen2,'look-ahead distances follow the speed')
  -- Lecture manquée plus loin : 0 (la borne reste celle d'avant).
  local here=ai.spline
  ac.getTrackAISplineSides=function(v) if math.abs(v-here)<1e-9 then return {x=3,y=9} end error('no data') end
  for k=0,7 do Snapshot.read(s,1/60,10.1+k/600) end; assert(s.cars[3].leftWidth==3 and s.cars[3].leftAhead==0 and s.cars[3].rightAhead2==0,'failed read ahead: zero')
  -- Jugement coupé : aucun écart lu. En service : toutes les voitures hors des stands, joueur compris.
  assert(not s.cars[1].trackLatValid and not s.cars[3].trackLatValid,'blame off: no track lateral')
  host.cars[0].position.x=2.5; host.cars[2].position.x=-1.5
  s.blameWanted=true; for k=0,7 do Snapshot.read(s,1/60,10.2+k/600) end
  assert(s.cars[1].trackLatValid and math.abs(math.abs(s.cars[1].trackLat)-2.5)<0.05,'player read: '..tostring(s.cars[1].trackLat))
  assert(s.cars[3].trackLatValid and math.abs(math.abs(s.cars[3].trackLat)-1.5)<0.05 and s.cars[3].trackLat*s.cars[1].trackLat<0,'AI read, opposite side: '..tostring(s.cars[3].trackLat))
  assert(not s.cars[3].lineLatValid and not s.cars[3].splineLatValid,'the other lateral readings keep their own conditions')
  -- Entre deux lectures (K.blameLatPeriod s) la valeur reste valable ; relue ensuite.
  host.cars[2].position.x=-3; Snapshot.read(s,1/60,10.22)
  assert(s.cars[3].trackLatValid and math.abs(math.abs(s.cars[3].trackLat)-1.5)<0.05,'kept between two reads')
  for k=1,8 do Snapshot.read(s,1/60,10.22+k/60) end
  assert(math.abs(math.abs(s.cars[3].trackLat)-3)<0.05,'read again after the period')
  host.cars[2].isInPitlane=true; Snapshot.read(s,1/60,10.5); assert(not s.cars[3].trackLatValid,'pit lane: not read')
  host.cars[2].isInPitlane=false; s.blameWanted=false; Snapshot.read(s,1/60,10.6); assert(not s.cars[1].trackLatValid,'blame off again: invalid')
 end)
 ac.getTrackAISplineSides=sides; assert(ok,err)
end
-- Moteur : le jugement en service demande l'écart latéral ; coupé (défaut) : rien n'est demandé.
tests.BLAME_WANTS_LATERAL_160M2=function()
 local e,f=F.scene('C',3); F.tick(e,f,0.1); assert(f.blameWanted==false,'defaults: no lateral read asked')
 e.profiles.C.sanPlayerContact=true; E.changed(e); F.tick(e,f,0.1); assert(f.blameWanted==true,'player contacts judged: asked')
 local q,fq=F.scene('Q',3); q.profiles.Q.sanContact=true; E.changed(q); F.tick(q,fq,0.1); assert(fq.blameWanted==true,'AI contacts judged in qualifying: asked')
 local j,fj=F.scene('J',3); j.profiles.J.sanContact=true; E.changed(j); F.tick(j,fj,0.1); assert(fj.blameWanted==false,'track day: never')
end
local function blameScene(settings)
 local e,f=F.scene('C',4)
 for k,v in pairs(settings) do e.profiles.C[k]=v end
 E.changed(e); F.tick(e,f,0.1)
 for i=1,f.count do F.place(f,i,(i-2)*1000,100) end
 F.tick(e,f,1.5)
 return e,f
end
local function hit(e,f,i,j,before)
 if before then before() end
 f.cars[i].collidedWith=j; F.tick(e,f,1/60); f.cars[i].collidedWith=nil
 F.tick(e,f,K.blameOutcome+0.4)
end
-- Relecture : vous percutez une IA par l'arrière en ligne droite. Écart latéral connu : règle de la ligne droite. Écart
-- inconnu (lecture manquée) : indéterminé, jamais un verdict contre vous.
tests.BLAME_PLAYER_NEEDS_LATERAL_160M2=function()
 local both={sanContact=true,sanPlayerContact=true}
 local e,f=blameScene(both)
 F.place(f,1,0,115); F.place(f,2,5,100); F.tick(e,f,1.5)
 assert(f.cars[1].trackLatValid and f.cars[2].trackLatValid and not f.cars[1].splineLatValid,'lateral of the player known through trackLat only')
 hit(e,f,1,2)
 assert(logged(e,'ligne droite choc par l arriere : Driver_1 en tort'),'known lateral: the car behind (you) is at fault')
 local u,fu=blameScene(both)
 F.place(fu,1,0,115); F.place(fu,2,5,100); F.tick(u,fu,1.5)
 fu.senseOff=true; for i=1,fu.count do fu.cars[i].trackLatValid=false; fu.cars[i].trackLat=0 end
 F.tick(u,fu,K.blameCutTime+2*K.blameSample)
 hit(u,fu,1,2)
 assert(count(u,'responsabilite:')==0 and logged(u,'incident de course: contact Driver_1 / Driver_2 (indetermine)'),'unknown lateral: undetermined, nobody at fault')
 assert(u.sanctions.cars[1].contactWarn==0 and u.sanctions.cars[1].contacts==0,'nothing held against you')
 -- La voiture de devant vient de changer de ligne devant vous : c'est elle (la règle marche enfin pour le joueur).
 local c,fc=blameScene(both)
 F.place(fc,1,0,115,0); F.place(fc,2,5,100,3); F.tick(c,fc,1.5)
 for k=1,48 do F.place(fc,2,5,100,3-3*k/48); F.tick(c,fc,1/60) end
 hit(c,fc,1,2)
 assert(logged(c,'ligne droite changement de ligne : Driver_2 en tort') and count(c,'Driver_1 en tort')==0,'the AI that cut across you is at fault')
end
-- Relecture : virage jugé sur la piste. Freinage en ligne droite dans une zone de drapeau jaune, côte à côte : pas un
-- virage (personne n'a bougé : indéterminé) ; hors zone : entrée de virage, le nez derrière cède. Voiture de devant
-- anormalement lente percutée : personne en tort. Forte accélération latérale à faible rotation : virage.
tests.BLAME_CORNER_FROM_TRACK_160M2=function()
 local on={sanContact=true}
 local function side(yellow)
  local e,f=blameScene(on)
  F.place(f,2,0,100,-1); F.place(f,3,2.3,92,1); F.tick(e,f,1.5); f.cars[2].brake=0.5; f.cars[3].brake=0.5
  hit(e,f,2,3,function() e.states[2].yellow=yellow; e.states[3].yellow=yellow end)
  return e
 end
 assert(logged(side(false),'virage nez derriere : Driver_2 en tort'),'braking side by side outside a yellow zone: corner entry')
 local y=side(true)
 assert(count(y,'responsabilite:')==0 and logged(y,'(indetermine)'),'braking side by side for a local yellow: not a corner')
 local e,f=blameScene(on)
 F.place(f,2,0,115); F.place(f,3,5,100); F.tick(e,f,1.5)
 hit(e,f,2,3,function() e.states[3].abnormal=true end)
 assert(count(e,'responsabilite:')==0 and logged(e,'(voiture accidentee)'),'abnormally slow car hit from behind: nobody at fault')
 -- 250 km/h, rotation faible (sous le seuil de a.corner) mais 3 m/s² d'accélération latérale et plus : virage.
 -- Finition 1.61 : l'accélération latérale d'une seule des deux voitures suffit (chacune à son tour).
 for _,only in ipairs({0,2,3}) do
  local g,fg=blameScene(on)
  F.place(fg,2,0,250); F.place(fg,3,5,235,3); F.tick(g,fg,1.5)
  local yaw=(K.blameCornerG+0.5)/(250/3.6); assert(1-yaw/g.run.cornerYawRef>=g.run.cornerMin,'scene: below the rotation threshold')
  for k=1,48 do F.place(fg,3,5,235,3-3*k/48); fg.cars[2].yawRate=(only~=3) and yaw or 0; fg.cars[3].yawRate=(only~=2) and yaw or 0; F.tick(g,fg,1/60) end
  hit(g,fg,2,3)
  assert(logged(g,'virage nez derriere : Driver_2 en tort'),'fast corner by lateral acceleration ('..only..'): the car behind, even when the car ahead moved')
 end
end
-- Relecture : protection du départ comptée depuis le départ lancé (e.launchAt), pas seulement depuis les feux d'AC.
tests.BLAME_START_AFTER_ROLLING_160M2=function()
 local e,f=blameScene({sanContact=true})
 e.startedAt=e.time-300; e.launchAt=e.time
 F.place(f,2,0,115); F.place(f,3,5,100); F.tick(e,f,1.5)
 hit(e,f,2,3)
 assert(count(e,'responsabilite:')==0 and logged(e,'(depart)'),'just after a rolling start: start protection')
 local o,fo=blameScene({sanContact=true})
 o.startedAt=o.time-300; o.launchAt=o.time-K.blameStartGrace-5
 F.place(fo,2,0,115); F.place(fo,3,5,100); F.tick(o,fo,1.5)
 hit(o,fo,2,3)
 assert(logged(o,'choc par l arriere : Driver_2 en tort'),'after the protection: judged')
end
-- Relecture : sans aucune IA en piste, pas de tour de formation (départ d'AC, une ligne au journal).
tests.FORMATION_NEEDS_AI_160M2=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); e.profiles.C.raceStart='rolling'; f.length=5000
 for i=1,3 do F.place(f,i,(i-2)*10,0) end
 for i=2,3 do f.cars[i].pit=true end
 E.changed(e); e.gridCaps=true; F.tick(e,f,1/60)
 f.started=false; F.tick(e,f,1/60); f.started=true; F.tick(e,f,1/60)
 assert(not e.incidents.formation and not e.incidents.neutral,'no formation lap without an AI on the track')
 assert(logged(e,'depart: tour de formation impossible (aucune IA) : depart arrete d AC'),'refusal logged')
 assert(J.english('depart: tour de formation impossible (aucune IA) : depart arrete d AC')=='start: formation lap not possible (no AI car): AC standing start',J.english('depart: tour de formation impossible (aucune IA) : depart arrete d AC'))
end

-- Relecture (coût) : voiture arrêtée qui ne bouge pas : distance à la trajectoire lue une fois, gardée ensuite sans
-- nouvelle lecture ; relue dès qu'elle bouge de plus de K.lineStill m ; jamais gardée après une lecture manquée.
tests.LINE_READ_CACHED_WHEN_STILL_160M2=function()
 assert(K.lineStill==0.05)
 local host=require('tests/host').create(true)
 local Snapshot=require('src/snapshot'); local s=Snapshot.new()
 local car=host.cars[2]; car.wheelsOutside=4; car.speedKmh=0; car.velocity={x=0,z=0}; car.position.x=20
 local calls=0; local read=ac.trackProgressToWorldCoordinateTo
 ac.trackProgressToWorldCoordinateTo=function(v,r) calls=calls+1; return read(v,r) end
 local ok,err=pcall(function()
  Snapshot.read(s,1/60,10); local a=s.cars[3]
  assert(a.lineDistValid and a.lineLatValid and math.abs(a.lineDist-20)<0.5,'first read')
  local first,lat=a.lineDist,a.lineLat; local after=calls
  for k=1,30 do Snapshot.read(s,1/60,10+k/60) end
  -- Les autres voitures roulent : aucune lecture pour elles non plus ; la voiture arrêtée garde ses valeurs.
  assert(calls==after,'no new read while the car stays still: '..(calls-after))
  assert(s.cars[3].lineDistValid and s.cars[3].lineLatValid and s.cars[3].lineDist==first and s.cars[3].lineLat==lat,'values kept')
  car.position.x=20.02; Snapshot.read(s,1/60,11); assert(calls==after,'2 cm: still')
  car.position.x=23; Snapshot.read(s,1/60,11.1)
  assert(calls>after and math.abs(s.cars[3].lineDist-23)<0.5,'moved: read again ('..tostring(s.cars[3].lineDist)..')')
  -- Lecture manquée : rien de gardé, relue à l'image suivante.
  after=calls; ac.trackProgressToWorldCoordinateTo=function() calls=calls+1; error('no data') end
  car.position.x=26; Snapshot.read(s,1/60,11.2); assert(not s.cars[3].lineDistValid,'failed read: invalid')
  ac.trackProgressToWorldCoordinateTo=function(v,r) calls=calls+1; return read(v,r) end
  Snapshot.read(s,1/60,11.3); assert(s.cars[3].lineDistValid and math.abs(s.cars[3].lineDist-26)<0.5,'read again after a failure')
 end)
 ac.trackProgressToWorldCoordinateTo=read; assert(ok,err)
end

-- SpotterEnginer : version lue dans son manifest.ini ([ABOUT], VERSION=X.Y.Z), comparée nombre par nombre ; illisible :
-- nil (aucun avertissement).
tests.COMPANION_VERSION_160M2=function()
 local A=require('src/applier')
 assert(K.seStartMinMajor==1 and K.seStartMinMinor==3 and K.seStartMinPatch==4)
 local v=A.manifestVersion('[ABOUT]\r\nNAME=SpotterEnginer\r\nVERSION=1.3.4\r\n[WINDOW_...]\r\nVERSION=9.9.9\r\n')
 assert(v and v[1]==1 and v[2]==3 and v[3]==4,'three numbers from [ABOUT]')
 v=A.manifestVersion('[about]\n VERSION = 1.3.10 \n'); assert(v and v[3]==10,'spaces and case')
 assert(A.manifestVersion('[OTHER]\nVERSION=1.3.4\n')==nil,'only in [ABOUT]')
 assert(A.manifestVersion('[ABOUT]\nVERSION=Beta 1.59\n')==nil and A.manifestVersion('[ABOUT]\nVERSION=1.3\n')==nil,'not three plain numbers: unreadable')
 assert(A.manifestVersion(nil)==nil and A.manifestVersion('')==nil)
 local min={1,3,4}
 assert(A.versionBelow({1,3,3},min) and A.versionBelow({1,2,9},min) and A.versionBelow({0,9,9},min),'older')
 assert(not A.versionBelow({1,3,4},min) and not A.versionBelow({1,3,10},min) and not A.versionBelow({1,4,0},min) and not A.versionBelow({2,0,0},min),'1.3.10 is above 1.3.4')
 -- Lecture du fichier (hôte de test) : dossier des apps Lua, une lecture.
 local host=require('tests/host').create(true)
 local folder,id=ac.getFolder,ac.FolderID.ACAppsLua
 local ok,err=pcall(function()
  ac.FolderID.ACAppsLua=99; ac.getFolder=function(k) if k==99 then return 'apps' end return folder(k) end
  assert(A.companionVersion('SpotterEnginer')==nil,'not installed: nil')
  host.files['apps\\SpotterEnginer\\manifest.ini']='[ABOUT]\nNAME=SpotterEnginer\nVERSION=1.3.3\n'
  local got=A.companionVersion('SpotterEnginer'); assert(got and got[1]==1 and got[2]==3 and got[3]==3,'read from the manifest')
  assert(A.versionBelow(got,min),'1.3.3 does not know the formation lap')
  host.files['apps\\SpotterEnginer\\manifest.ini']='garbage'
  assert(A.companionVersion('SpotterEnginer')==nil,'unreadable: nil, no warning')
  assert(A.companionVersion('../x')==nil,'unsafe name refused')
 end)
 ac.getFolder=folder; ac.FolderID.ACAppsLua=id; assert(ok,err)
 local J2=require('src/journal')
 assert(J2.english('pont des apps compagnes: version de SpotterEnginer illisible')=='companion app bridge: version of SpotterEnginer unreadable',J2.english('pont des apps compagnes: version de SpotterEnginer illisible'))
 assert(J2.english('pont des apps compagnes: SpotterEnginer version 1.3.3 (tour de formation et depart lance inconnus avant la 1.3.4)')=='companion app bridge: SpotterEnginer version 1.3.3 (formation lap and rolling start unknown before 1.3.4)',J2.english('pont des apps compagnes: SpotterEnginer version 1.3.3 (tour de formation et depart lance inconnus avant la 1.3.4)'))
 assert(J2.english('pont des apps compagnes: SpotterEnginer version 1.3.4')=='companion app bridge: SpotterEnginer version 1.3.4')
 -- Textes de l'avertissement dans les deux langues.
 local fr,en=require('src/lang'),require('src/lang_en')
 assert(type(fr.companionRaceStart)=='string' and type(en.companionRaceStart)=='string' and string.format(en.companionRaceStart,'1.3.3',1,3,4):find('1.3.4 or later',1,true),'warning texts')
end
-- Plan sans arrêt : dit en clair au journal et à l'écran, jamais « tour -1 ».
tests.PLAN_WITHOUT_STOP_160M2=function()
 local J2=require('src/journal')
 assert(J2.english('strategie: Driver_2 plan 0 arret(s), aucun arret prevu, risque 50 %')=='strategy: Driver_2 plans 0 stop(s), no stop planned, risk 50%',J2.english('strategie: Driver_2 plan 0 arret(s), aucun arret prevu, risque 50 %'))
 -- Plan à 0 arrêt en course : carburant pour finir, pneus qui tiennent.
 local e,f=F.scene('C',3); e.profiles.C.strategyEnabled=true; e.profiles.C.section_strategy=true; E.changed(e)
 f.sessionLaps=10; f.timedRace=false; f.sessionMinutes=0; f.leaderLaps=2
 for i=1,3 do local a=f.cars[i]; a.lap=2; a.fuel=100; a.maxFuel=120; a.fuelPerLap=2; a.wearKnown=true; a.tyreWear={0.01,0.01,0.01,0.01} end
 e.strategy.wearTrust='trusted'
 for lap=2,4 do for i=1,3 do f.cars[i].lap=lap end; F.tick(e,f,1) end
 assert(count(e,'tour -1')==0,'never a negative lap in the journal')
 if count(e,'strategie: Driver_2 plan ')>0 then assert(logged(e,'strategie: Driver_2 plan 0 arret(s), aucun arret prevu, risque '),'plan without a stop said in words') end
 for k=1,#e.strategy.rows do local r=e.strategy.rows[k]; if r and r.text then assert(not r.text:find('-1',1,true),'overlay row: '..r.text) end end
end
-- Contrat figé de SpotterEnginer 1.3.4 (exemples réels de sa session) : lus tels quels ; la clé change chaque seconde
-- (stamp) : une ligne de journal seulement quand le mode, le rival ou le tour changent.
tests.SE_STRATEGY_REAL_EXAMPLES_160M2=function()
 local p=E.parseStrategy('v=1;mode=undercut;rival=4;gain=1.3;lap=12;stamp=123')
 assert(p and p.mode=='undercut' and p.rival==4 and math.abs(p.gain-1.3)<1e-9 and p.lap==12 and p.stamp==123)
 p=E.parseStrategy('v=1;mode=cover;rival=7;gain=-1.0;lap=12;stamp=123'); assert(p and p.mode=='cover' and p.rival==7 and p.gain==-1 and p.lap==12)
 p=E.parseStrategy('v=1;mode=none;rival=-1;gain=-1.0;lap=0;stamp=123'); assert(p and p.mode=='none' and p.rival==-1 and p.lap==0)
 local e,f=F.scene('C',6); F.tick(e,f,0.1)
 for i=1,6 do f.cars[i].index=i-1 end
 local player=f.cars[1]
 for k=0,20 do
  e.seStrategy=e.seStrategy or {}; e.seStrategy.raw=string.format('v=1;mode=undercut;rival=4;gain=1.3;lap=12;stamp=%d',123+k)
  E.seStrategy(e,f,player,100+k)
  assert(e.incidents.seStrategyMode=='undercut' and e.incidents.seStrategyTarget=='Driver_5','shown every second while the stamp advances')
 end
 assert(count(e,'SpotterEnginer strategie: undercut')==1,'one journal line for 21 stamps: '..count(e,'SpotterEnginer strategie: undercut'))
 e.seStrategy.raw='v=1;mode=cover;rival=3;gain=-1.0;lap=12;stamp=144'; E.seStrategy(e,f,player,121)
 assert(count(e,'SpotterEnginer strategie: cover (rival Driver_4, tour 12, gain -1.0 s')==1,'new line when the mode and the rival change')
 -- Stamp figé : oublié après K.seStrategyStale s.
 E.seStrategy(e,f,player,121+K.seStrategyStale+0.5); assert(e.incidents.seStrategyMode=='','stale after 6 s without a new stamp')
 e.seStrategy.raw='v=1;mode=none;rival=-1;gain=-1.0;lap=0;stamp=160'; E.seStrategy(e,f,player,140); assert(e.incidents.seStrategyMode=='','mode none: nothing shown')
end

-- Voiture nettement en difficulté sous neutralisation : signalée (une ligne), dépassable sans sanction, et la file ne
-- se forme pas derrière elle ; une voiture à l'allure de la file, dans un virage lent ou d'allure inconnue : jamais.
tests.TROUBLE_CAR_PASSABLE_160M2=function()
 assert(K.troubleRatio==0.5 and K.troubleTime==3)
 local Penalties=require('src/penalties')
 local function scene(kmh,own,setup)
  local e,f=F.scene('C',4); e.profiles.C.neutralization='fcy'; E.changed(e); F.tick(e,f,0.1)
  for i=1,4 do F.place(f,i,(i-2)*300,100) end
  e.incidents.neutral=true; e.incidents.neutralMode='fcy'; e.incidents.neutralSince=e.time; e.incidents.neutralUntil=e.time+600
  local s=e.states[3]
  for k=1,60*5 do
   F.place(f,3,300,kmh); F.place(f,2,0,math.min(100,kmh+40))
   for b=1,#s.pace do s.pace[b]=own/3.6 end; s.paceCount=#s.pace
   if setup then setup(e,f) end
   e.incidents.neutral=true
   F.tick(e,f,1/60)
  end
  return e,f
 end
 -- Voiture 3 à 30 km/h là où elle roule d'habitude à 200 et où le drapeau en permet davantage : en difficulté.
 local e,f=scene(30,200)
 local limit=e.commands[3].yellowLimit
 assert(e.incidents.cars[3].trouble==true,'car far below the allowed pace for 3 s: in trouble (limit '..tostring(limit)..')')
 assert(count(e,'voiture en difficulte: Driver_3 (30 km/h, ')==1,'logged once')
 assert(Penalties.passable(f.cars[3],e.incidents.cars[3],e.run,e.time),'may be passed without sanction')
 assert(e.states[2].neutralQueue~=3,'the queue does not form behind it')
 -- Relecture finale 1.61 : voiture 2 juste derrière (dans K.scQueueGap) : toujours pas de file derrière elle.
 for _=1,30 do F.place(f,3,300,30); F.place(f,2,300-(f.cars[3].length or K.length)-20,70); e.incidents.neutral=true; F.tick(e,f,1/60) end
 assert(e.incidents.cars[3].trouble==true and e.states[2].neutralQueue~=3,'close behind a car in trouble: no queue ('..tostring(e.states[2].neutralQueue)..')')
 local J2=require('src/journal'); local line
 for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('voiture en difficulte:',1,true) then line=r.message end end
 assert(J2.english(line):find('car in trouble: Driver_3 (30 km/h, ',1,true)==1 and J2.english(line):find('may be passed under the flag',1,true),J2.english(line))
 -- À l'allure permise : jamais.
 local n=scene(85,200); assert(not n.incidents.cars[3].trouble and count(n,'voiture en difficulte')==0,'car at the pace of the flag: not in trouble')
 -- Virage lent (allure habituelle 50 km/h ici) : rouler à 30 n'est pas une difficulté.
 local c=scene(30,50); assert(not c.incidents.cars[3].trouble,'slow corner: not in trouble')
 -- Allure habituelle inconnue : jamais jugée.
 local u=scene(30,0); assert(not u.incidents.cars[3].trouble,'unknown pace: never judged')
 -- Tour de relance ou de formation (peloton qui s'élance) : jamais.
 local r=scene(30,200,function(e2) e2.incidents.relaunch=true end); assert(not r.incidents.cars[3].trouble,'relaunch lap: never')
 -- Fin du drapeau : plus en difficulté pour cette règle.
 e.incidents.neutral=false; F.place(f,3,300,30); F.tick(e,f,0.5)
 assert(not e.incidents.cars[3].trouble,'flag over: cleared')
end
-- Priorité au virage : jamais sous drapeau ou neutralisation ; jamais envers une voiture qui cède déjà à celle-ci.
tests.CORNER_PRIORITY_NO_FLIP_160M2=function()
 local function pair(setup)
  local e,f=F.scene('C',3); e.profiles.C.startDelay=0; e.profiles.C.startRelax=0; e.profiles.C.neutralization='fcy'; E.changed(e); F.tick(e,f,0.1)
  F.place(f,1,-5000,100)
  -- Voiture 2 à gauche, voiture 3 à droite, 3 m devant (nez de la 2 derrière de plus de K.cornerNoseMargin m), en virage.
  for k=1,90 do
   F.place(f,2,0,100,-1.2); F.place(f,3,3,100,1.2)
   f.cars[2].yawRate=e.run.cornerYawRef; f.cars[3].yawRate=e.run.cornerYawRef
   e.states[2].nextPerception=0; e.states[3].nextPerception=0
   if setup then setup(e,f) end
   F.tick(e,f,1/60)
  end
  return e
 end
 local e=pair()
 assert(e.states[2].cornerGiveTo==3 and count(e,'priorite au virage: Driver_2 cede a Driver_3')==1,'scene: the nose behind gives way')
 -- La voiture 3 cède déjà à la 2 (ordre inversé un instant plus tôt) : la 2 ne cède pas à son tour.
 local g=pair(function(e2) e2.states[3].cornerGiveTo=2 end)
 assert(g.states[2].cornerGiveTo~=3 and count(g,'priorite au virage: Driver_2 cede a Driver_3')==0,'no flip-flop: the other car is already giving way')
 -- Neutralisation : la règle ne tourne pas.
 local n=pair(function(e2) e2.incidents.neutral=true; e2.incidents.neutralMode='fcy'; e2.incidents.neutralSince=e2.time; e2.incidents.neutralUntil=e2.time+600 end)
 assert(n.incidents.neutral and n.states[2].cornerGiveTo==0 and count(n,'priorite au virage')==0,'never under a neutralisation')
end
-- File sous neutralisation : la voiture de devant reste la cible tant que celle-ci n'est pas entièrement passée ; à sa
-- hauteur, limite K.scOverlapDrop km/h sous sa vitesse.
tests.NEUTRAL_QUEUE_OVERLAP_160M2=function()
 local function at(z)
  local e,f=F.scene('C',3); e.profiles.C.neutralization='fcy'; E.changed(e); F.tick(e,f,0.1)
  F.place(f,1,-5000,100)
  for k=1,120 do
   F.place(f,3,0,80,2.5); F.place(f,2,z,80,-1)
   e.incidents.neutral=true; e.incidents.neutralMode='fcy'; e.incidents.neutralSince=e.time-5; e.incidents.neutralUntil=e.time+600
   e.states[2].nextPerception=0
   F.tick(e,f,1/60)
  end
  return e
 end
 local behind=at(-10); assert(behind.states[2].neutralQueue==3,'scene: queued behind the car ahead')
 local over=at(-2)
 assert(over.states[2].neutralQueue==3,'overlapping by more than 1 m: still its queue target')
 assert(over.commands[2].yellowLimit<=80-K.scOverlapDrop+1e-6,'alongside: limited below its speed ('..tostring(over.commands[2].yellowLimit)..')')
 local past=at(6); assert(past.states[2].neutralQueue~=3,'entirely past: no longer the target')
end

-- Seconde relecture, S5, et installation réelle du jeu (sens latéral -1 / -1) : la place se lit du côté réellement
-- visé. Décalage écrit = décalage interne × offsetSign ; positif : droite (largeur de droite).
tests.SIDE_ROOM_BOTH_SIGNS_160M2=function()
 assert(K.sideMinRoom==1 and K.reachSideMax==6)
 local e,f=F.scene('P',3); local s,a,p=e.states[2],f.cars[2],e.run
 s.state='YIELD_IN'
 for _,sign in ipairs({1,-1}) do
  local g={offsetSign=sign}
  -- Trajectoire au bord droit : 10,5 m à gauche, 1,5 m à droite.
  widths(a,10.5,1.5)
  local toRight,toLeft=sign,-sign -- côté interne qui écrit un décalage positif (droite), négatif (gauche)
  assert(D.sideRoom(s,a,p,g,toRight)<0.2,'right side: no room (sign '..sign..')')
  assert(math.abs(D.sideRoom(s,a,p,g,toLeft)-K.reachWideMeters)<1e-9,'left side: 4 m (sign '..sign..')')
  local left=D.reachable(s,a,p,g,0.8*toLeft)
  assert(math.abs(math.abs(left)-K.reachWideMeters/10.5)<1e-9 and left*toLeft>0,'move to the left bounded by the left side (sign '..sign..'): '..left)
  assert(math.abs(D.reachable(s,a,p,g,0.8*toRight))<0.06,'move to the right bounded by the right side (sign '..sign..')')
 end
 assert(D.sideRoom(s,a,p,{offsetSign=0},1)==nil,'sign unknown: no judgement')
 widths(a,0,0); assert(D.sideRoom(s,a,p,{offsetSign=-1},1)==nil,'widths unknown: no judgement')
 -- Conduite libre (DRIVE, IDLE) : borne d'origine des deux côtés (S4) ; manœuvre : place du grand côté.
 widths(a,10.5,1.5); local g={offsetSign=-1}
 s.state='DRIVE'; assert(math.abs(D.reachable(s,a,p,g,0.8))<0.06 and math.abs(D.reachable(s,a,p,g,-0.8))<0.06,'free driving: original bound on both sides')
 s.state='IDLE'; assert(math.abs(D.reachable(s,a,p,g,0.8))<0.06,'idle: original bound')
 s.state='OVT_IN'; assert(math.abs(D.reachable(s,a,p,g,0.8))>0.3,'manoeuvre: real room of the wide side')
 -- N6 : côté annoncé très large (dégagement compté) : compté pour K.reachSideMax m, 4 m hors trajectoire au plus.
 widths(a,1.5,40); s.state='YIELD_IN'
 local far=D.reachable(s,a,p,{offsetSign=1},0.8)
 assert(far*40<=K.reachWideMeters+1e-9 and far*40<=K.reachSideMax-a.width*0.5-K.reachEdgeMargin+1e-9,'huge reported side: counted for 6 m at most ('..far*40 ..' m)')
 -- Finition 1.61 : voiture large (3,6 m) : la limite des 6 m du côté passe sous les 4 m hors trajectoire.
 local w0=a.width; a.width=3.6
 local wide=D.reachable(s,a,p,{offsetSign=1},0.8)*40
 a.width=w0
 assert(math.abs(wide-(K.reachSideMax-1.8-K.reachEdgeMargin))<1e-6,'wide car: 6 m of side minus half the car and the margin ('..wide..' m)')
end
-- Cession et dépassement en scène complète, avec le sens latéral du jeu (-1 / -1) puis +1 / +1 : la voiture va du côté
-- qui a de la place, et la ligne du journal nomme le bon côté de la piste.
tests.YIELD_GOES_TO_THE_ROOM_160M2=function()
 local function last(e) local line; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('cession finie:',1,true) then line=r.message end end return line end
 local function run(sign,left,right,side)
  local e,f=F.scene('J',3); e.g.offsetSign=sign; e.g.sideSign=sign; e.profiles.J.flashObliviousPct=0; e.profiles.J.yieldSide=side or 'right'; E.changed(e)
  for i=1,3 do f.cars[i].leftWidth=left; f.cars[i].rightWidth=right; f.cars[i].sideDot=sign end
  F.place(f,1,-5000,100); F.rear(e,f,45,30,3)
  local s=e.states[2]; local seen=false
  for _=1,6*60 do F.tick(e,f,1/60); if F.yielding(s.state) then seen=true; break end end
  assert(seen,'the yield starts (sign '..sign..', '..left..' / '..right..')')
  F.tick(e,f,2.5)
  local written=s.offset*sign -- décalage écrit à CSP : positif = droite
  F.place(f,3,40,130); s.nextPerception=0; F.tick(e,f,3)
  return written,last(e),e
 end
 for _,sign in ipairs({-1,1}) do
  -- Trajectoire au bord droit, côté de cession réglé à droite : pas de place à droite, 4 m à gauche : cession à gauche.
  local written,line=run(sign,10.5,1.5,'right')
  assert(written<-0.25,'sign '..sign..': written offset negative (left), about 4 m: '..written)
  assert(line:find('m vers la gauche, piste alors 10.5 m a gauche, 1.5 m a droite',1,true) and line:find('autre cote pris',1,true),'sign '..sign..': '..tostring(line))
  -- Trajectoire au bord gauche, côté réglé à droite : place à droite, cession à droite, côté réglé gardé.
  written,line=run(sign,1.5,10.5,'right')
  assert(written>0.25,'sign '..sign..': written offset positive (right): '..written)
  assert(line:find('m vers la droite, piste alors 1.5 m a gauche, 10.5 m a droite',1,true) and not line:find('autre cote pris',1,true),'sign '..sign..': '..tostring(line))
  -- Côté réglé à gauche, trajectoire au bord gauche : cession à droite.
  written,line=run(sign,1.5,10.5,'left')
  assert(written>0.25 and line:find('autre cote pris',1,true),'sign '..sign..', set side left without room: right taken: '..written)
  -- Piste symétrique : côté réglé, comme avant.
  written,line=run(sign,6,6,'right')
  assert(written>0.25 and not line:find('autre cote pris',1,true),'sign '..sign..', symmetric track: set side kept')
 end
end
-- Dépassement : côté pris selon la place (hors course, le côté est l'opposé du côté de cession réglé : gauche).
tests.PASS_GOES_TO_THE_ROOM_160M2=function()
 local function run(sign,left,right)
  local e,f=F.scene('P',3); e.g.offsetSign=sign; e.g.sideSign=sign
  e.profiles.P.startDelay=0; e.profiles.P.startRelax=0; e.profiles.P.yieldEnabled=false; E.changed(e)
  for i=1,3 do f.cars[i].leftWidth=left; f.cars[i].rightWidth=right; f.cars[i].sideDot=sign end
  F.place(f,1,-5000,100); F.front(e,f,20,30); F.tick(e,f,0.2)
  local s=e.states[2]; local t=0
  while t<5 do F.front(e,f,20,30); F.tick(e,f,1/60); t=t+1/60; if F.passing(s.state) then return s.targetSide*sign,e end end
  return 0,e
 end
 for _,sign in ipairs({-1,1}) do
  local side=run(sign,10.5,1.5); assert(side<0,'sign '..sign..': line on the right edge: pass on the left (the set side): '..side)
  local e
  side,e=run(sign,1.5,10.5); assert(side>0 and (e.stats.passSideRoom or 0)>=1,'sign '..sign..': line on the left edge: pass on the right, where the room is: '..side)
  side,e=run(sign,1.9,1.9); assert(side==0 and (e.stats.passNoRoom or 0)==1,'sign '..sign..': no room on either side: no attempt')
  side=run(sign,6,6); assert(side<0,'sign '..sign..': symmetric track: the set side')
 end
end
-- Seconde relecture, S2 et S1/S3 : le régulateur juge sur la cible du radar ; jamais adouci pour un vrai obstacle.
tests.GOVERN_RADAR_TARGET_160M2=function()
 local Rear=require('src/rear')
 assert(K.rearLastTtc==0.8)
 local function scene(set)
  local e,f=F.scene('P',4); e.profiles.P.startDelay=0; e.profiles.P.startRelax=0; E.changed(e)
  F.place(f,1,-5000,100); F.place(f,2,0,150); F.place(f,3,-4.4-5,150); F.place(f,4,60,140)
  for i=2,4 do f.cars[i].gas=1; f.cars[i].brake=0 end
  e.states[2].nextPerception=0; F.tick(e,f,0.2)
  local s,cmd=e.states[2],e.commands[2]
  assert(s.rearClose==true,'scene: car close behind')
  s.radarIndex=4; s.radarTTC=2; s.radarSa=20
  if set then set(e,f,s,cmd) end
  cmd.brake=0.5; s.radarBrake=0.5; s.appBrake=0.5
  Rear.govern(e.rear,e,f,e.time,1/60)
  return cmd.brake,e
 end
 assert(scene()==K.rearBrakeMax,'ordinary closing on the radar target: brake capped')
 assert(scene(function(_,_,s) s.radarSa=K.radarStraightObstacleKmh end)==0.5,'closing at 60 km/h or more: a real obstacle, full radar brake')
 assert(scene(function(_,_,s) s.radarTTC=K.rearLastTtc-0.1 end)==0.5,'contact with the radar target under the last-resort time: full brake')
 assert(scene(function(e) e.incidents.cars[4].incident=true end)==0.5,'radar target in an incident: full brake')
 assert(scene(function(e) e.states[4].abnormal=true end)==0.5,'radar target abnormally slow: full brake')
 assert(scene(function(e) e.incidents.standing='grid' end)==0.5,'standing grid forming: exempt (S1)')
 assert(scene(function(e,_,s) s.pitGuardUntil=e.time+5 end)==0.5,'pit-exit guard: exempt (S3)')
 assert(scene(function(_,_,s) s.radarIndex=0 end)==K.rearBrakeMax,'no radar target: capped as before')
end
return tests
