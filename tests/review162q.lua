-- Affinage 1.62 (sessions d essai du 12 novembre) : dépassement franc en
-- courbe, joueur rangé sur le côté, cession au bord de Monaco, envol manqué au départ. Noms terminés par _162Q. Chargé
-- par tests/extended.lua. Chaque scène tourne avec le sens latéral du jeu (-1 / -1) et avec +1 / +1.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local D=require('src/director')
local P=require('src/perception')
local K=C.K
local tests={}
local function learned(e,i,kmh) local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=kmh/3.6 end; s.paceMean=kmh/3.6 end
local function scene(profile,count,sign)
 local e,f=F.scene(profile,count); e.g.offsetSign=sign; e.g.sideSign=sign
 e.profiles[profile].startDelay=0; e.profiles[profile].startRelax=0; e.profiles[profile].personalLineJitter=0; E.changed(e)
 for i=1,count do f.cars[i].sideDot=sign end
 return e,f
end

tests.K_162Q=function()
 assert(K.passFreeCornerCaution==1 and K.reachWideEdge==1.2 and K.anticBogGrace==1)
 assert(K.reachEdgeMargin==0.5,'frank-pass room margin unchanged')
end

-- Attaquant décalé de sa cible qui lui cède, en courbe sans freiner : prudence au plus K.passFreeCornerCaution (avant :
-- base du profil, 2,2 en essais et qualifications) ; au freinage, la base revient (règle de la Beta 1.31).
local function frankCurve(profile,sign,brake,third)
 local e,f=scene(profile,third and 4 or 3,sign)
 F.place(f,1,-5000,100); F.place(f,2,0,157,0); F.place(f,3,12.4,150,3.5*sign)
 if third then F.place(f,4,9.4,150,0) end
 F.tick(e,f,0.2)
 local s,o=e.states[2],e.states[3]
 for k=1,240 do
  o.state='YIELD_HOLD'; o.target=2; o.targetSide=1; o.followers[2]=true; o.yieldStart=e.time-1; o.holdUntil=e.time+60; o.yieldDetection=100; o.yieldMargin=5; o.offset=0.5; o.base=0
  if k<60 then s.state='OVT_IN'; s.target=3; s.targetSide=-1; s.passStartAt=s.passStartAt or e.time end
  learned(e,2,157); learned(e,3,150)
  F.place(f,2,0,157,0); F.place(f,3,12.4,150,3.5*sign); if third then F.place(f,4,9.4,150,0) end
  f.cars[2].yawRate=0.15; f.cars[3].yawRate=0.15; f.cars[2].brake=brake or 0; s.nextPerception=0
  F.tick(e,f,1/60)
 end
 return e,s
end
tests.PASS_FREE_CORNER_162Q=function()
 for _,sign in ipairs({-1,1}) do
  for _,profile in ipairs({'P','Q','J'}) do
   local e,s=frankCurve(profile,sign)
   assert(F.passing(s.state) and s.target==3,profile..' '..sign..': pass running '..s.state)
   assert(e.commands[2].caution<=K.passFreeCornerCaution+0.01,profile..' '..sign..': corner caution capped '..e.commands[2].caution)
   assert(s.baseCaution>K.passFreeCornerCaution+0.3,profile..': profile base above the cap (the case of the sessions)')
   -- Au freinage : jamais sous la base.
   local e2,s2=frankCurve(profile,sign,0.6)
   assert(e2.commands[2].caution>=s2.baseCaution-0.02,profile..' '..sign..': braking keeps the base '..e2.commands[2].caution)
  end
 end
end
-- Autre voiture proche devant dans sa file : jamais de plafond (la prudence de suivi reste).
tests.PASS_FREE_THIRD_IN_LANE_162Q=function()
 for _,sign in ipairs({-1,1}) do
  local row={count=0,neighbors={}}
  local s={state='OVT_IN',target=3}
  row.count=1; row.neighbors[1]={index=3,lat=3.5,long=12,gap=8}
  assert(D.passFreeTest(s,row,nil)==true,'target aside, nobody in the lane')
  assert(D.passFreeTest(s,row,{index=4,long=6,gap=2})==false,'another car close ahead in the lane')
  assert(D.passFreeTest(s,row,{index=3,long=12,gap=8,lat=3.5})==true,'front is the target itself')
  row.neighbors[1].lat=0.8*sign
  assert(D.passFreeTest(s,row,nil)==false,'target still on the line')
  s.state='OVT_ARM'; row.neighbors[1].lat=3.5*sign
  assert(D.passFreeTest(s,row,nil)==false,'not yet pulled out')
 end
end

-- Joueur rangé de 3 m sur le côté réglé (« gauche »), nettement plus lent : l'IA prend le côté libéré, sans frein du
-- radar ; en course, plus d'attente du déboîtement (OVT_ARM) : déboîtement immédiat.
tests.PLAYER_ASIDE_FREED_SIDE_162Q=function()
 for _,sign in ipairs({-1,1}) do
  for _,profile in ipairs({'P','C'}) do
   local e,f=scene(profile,3,sign)
   F.place(f,3,-5000,100); F.place(f,2,0,160,0); F.place(f,1,30+4.4,100,3); e.states[2].nextPerception=0; F.tick(e,f,0.2)
   local nb=P.find(e.perception.rows[2],1)
   local freed=nb.lat>0 and 1 or -1
   local row=e.perception.rows[2]
   local side=D.passSideTest(e.profiles[profile],profile,e.states[2],nb,row,f.cars[1],e.g,f.cars[2])
   assert(side==freed,profile..' '..sign..': freed side before the set side ('..side..' / '..freed..')')
   -- Voiture à peine décalée : le côté réglé, comme avant.
   F.place(f,1,30+4.4,100,0.5); e.states[2].nextPerception=0; F.tick(e,f,0.2)
   nb=P.find(e.perception.rows[2],1)
   local set=D.passSideTest(e.profiles[profile],profile,e.states[2],nb,e.perception.rows[2],f.cars[1],e.g,f.cars[2])
   local fixed=e.g.offsetSign<0 and 1 or -1 -- « left » réglé
   assert(set==fixed,profile..' '..sign..': set side kept for a car on the line ('..set..')')
  end
 end
end
tests.RACE_ARM_OPENED_162Q=function()
 for _,sign in ipairs({-1,1}) do
  local e,f=scene('C',3,sign)
  local gap=40
  F.place(f,3,-5000,100); F.place(f,2,0,160,0); F.place(f,1,gap+4.4,100,3); F.tick(e,f,0.2)
  local s=e.states[2]; local armFor=0; local inSeen=false
  for _=1,120 do
   learned(e,2,160)
   F.place(f,2,0,160,0); F.place(f,1,gap+4.4,100,3); s.nextPerception=0
   F.tick(e,f,1/60); gap=gap-60/3.6/60
   if s.state=='OVT_ARM' then armFor=armFor+1/60 end
   if s.state=='OVT_IN' or s.state=='OVT_HOLD' then inSeen=true end
  end
  assert(inSeen,sign..': pulled out on the freed side ('..s.state..')')
  assert(armFor<=0.1,sign..': no wait in OVT_ARM behind a car already aside ('..armFor..' s)')
  assert((e.stats.armOpen or 0)>=1,'counted')
  -- Cible sur la trajectoire : l'attente d'avant (déboîtement au bon écart).
  local e2,f2=scene('C',3,sign)
  gap=40; F.place(f2,3,-5000,100); F.place(f2,2,0,160,0); F.place(f2,1,gap+4.4,100,0); F.tick(e2,f2,0.2)
  local s2=e2.states[2]; local arm2=false
  for _=1,30 do learned(e2,2,160); F.place(f2,2,0,160,0); F.place(f2,1,gap+4.4,100,0); s2.nextPerception=0; F.tick(e2,f2,1/60); gap=gap-60/3.6/60; if s2.state=='OVT_ARM' then arm2=true end end
  assert(arm2 and (e2.stats.armOpen or 0)==0,sign..': target on the line keeps the usual wait')
 end
end

-- Monaco : grand côté de 5,6 m : la carrosserie reste à K.reachWideEdge m du bord ; côté de 6,2 m ou plus : inchangé
-- (plafond de K.reachWideMeters m) ; petit côté : borne d'origine.
tests.YIELD_EDGE_MONACO_162Q=function()
 for _,sign in ipairs({-1,1}) do
  local s={state='YIELD_HOLD',zone={maxOffset=1}}
  local p={maxSideOffset=0.95}
  local g={offsetSign=sign}
  local a={splineValid=true,width=1.85,leftWidth=1.7,rightWidth=5.6,leftAhead=1.7,rightAhead=5.6,leftAhead2=1.7,rightAhead2=5.6}
  -- Désiré × offsetSign > 0 : droite (le grand côté).
  local bound=D.reachable(s,a,p,g,sign)
  local meters=math.abs(bound)*5.6
  assert(5.6-meters-a.width*0.5>=K.reachWideEdge-1e-6,sign..': body '..(5.6-meters-a.width*0.5)..' m from the edge')
  assert(meters>=3.4,'still a real yield: '..meters..' m')
  a.rightWidth=6.4; a.rightAhead=6.4; a.rightAhead2=6.4
  local wide=math.abs(D.reachable(s,a,p,g,sign))*6.4
  assert(math.abs(wide-K.reachWideMeters)<1e-6,'side of 6.4 m: '..K.reachWideMeters..' m as before: '..wide)
  -- Vers le petit côté : borne d'origine (petit côté moins une demi-voiture, rapportée au grand).
  local small=math.abs(D.reachable(s,a,p,g,-sign))
  assert(math.abs(small-(1.7-0.925)/6.4)<1e-6,'narrow side unchanged: '..small)
 end
end

-- Départ : voiture devant encore dans son envol manqué : jamais de « pied tenu » derrière elle, même poussée par la
-- voiture de derrière ; levée de pied dosée ; envol fini depuis plus de K.anticBogGrace s : règle d'avant.
local function bogStart(sign,poor,late)
 local e,f=scene('C',4,sign)
 e.profiles.C.startDelay=8; e.profiles.C.startRelax=4; E.changed(e)
 F.place(f,1,-5000,0); F.place(f,3,10.4,40,0); F.place(f,2,0,62,0); F.place(f,4,-5.4,66,0)
 F.tick(e,f,1/60)
 e.startedAt=e.time-1.2
 local t=e.antics
 t.kind='grid'; t.at=e.time-(late and 5 or 1.2); t.poor[3]=poor; t.react[3]=0.2; t.bog[3]=1.2
 local lifted,held=false,false
 for _=1,40 do
  F.place(f,3,10.4,40,0); F.place(f,2,0,62,0); F.place(f,4,-5.4,66,0)
  for i=2,4 do f.cars[i].yawRate=0 end
  e.states[2].nextPerception=0
  F.tick(e,f,1/60)
  if (e.commands[2].throttleLimit or 1)<1 or (e.commands[2].brake or 0)>0 then lifted=true end
 end
 held=(e.startHold or 0)>0
 return lifted,held,e
end
tests.START_BOG_NO_HOLD_162Q=function()
 for _,sign in ipairs({-1,1}) do
  local lifted,_,e=bogStart(sign,true,false)
  assert(lifted,sign..': lifts behind a missed start ('..tostring(e.commands[2].throttleLimit)..')')
  local lifted2,held2=bogStart(sign,false,false)
  assert(not lifted2 or held2~=nil,'reference scene runs')
  local lifted3=bogStart(sign,true,true)
  assert(lifted3==lifted2,sign..': missed start over for more than '..K.anticBogGrace..' s: the rule of before')
 end
 -- Fonction seule : fenêtre réaction + envol + grâce.
 local e={antics={kind='grid',at=10,poor={[3]=true},react={[3]=0.2},bog={[3]=1.2}}}
 assert(D.boggingTest(e,3,11)==true and D.boggingTest(e,3,12.3)==true and D.boggingTest(e,3,12.5)==false and D.boggingTest(e,4,11)==false)
 e.antics.kind='form'; assert(D.boggingTest(e,3,11)==false,'formation start: no missed start')
end

-- Voiture qui cède (essais), attaquant à sa hauteur et décalé d'elle : la limite du passage franc suit la vitesse du
-- moment de l'attaquant (K.frankDeltaKmh sous elle), plus seulement sa vitesse la plus haute de l'épisode.
tests.FRANK_LIFT_CURRENT_SPEED_162Q=function()
 for _,sign in ipairs({-1,1}) do
  local e,f=scene('P',3,sign)
  local s,fs=e.states[2],e.states[3]; local start=e.time-1
  learned(e,2,160)
  local lowest,seen=math.huge,math.huge
  for k=1,8*60 do
   s.state='YIELD_HOLD'; s.target=3; s.targetSide=1; s.followers[3]=true; s.yieldStart=start; s.holdUntil=e.time+60; s.yieldDetection=100; s.yieldMargin=5
   s.offset=0.3; s.base=0
   fs.state='OVT_HOLD'; fs.target=2; fs.targetSide=-1; fs.passStartAt=start; fs.passMinGap=0; fs.passName='x'; fs.passProgRef=0; fs.passProgTime=0; fs.abortSlow=0; fs.passStall=0; fs.lastPassTarget=2
   -- L'attaquant passe de 170 à 130 km/h (partie plus lente), toujours 3 m à côté.
   local v=k<2*60 and 170 or 130
   local cap=e.commands[2].speedLimit or K.unlimitedSpeed
   F.place(f,1,-5000,0); F.place(f,2,0,math.min(v,cap)); F.place(f,3,-2,v,-3)
   s.nextPerception=0
   F.tick(e,f,1/60)
   if k>2*60 and s.frankNowKmh then seen=math.min(seen,s.frankNowKmh) end
   if k>6*60 then lowest=math.min(lowest,e.commands[2].speedLimit or K.unlimitedSpeed) end
  end
  assert(seen<=131,sign..': current passer speed seen '..seen)
  assert(lowest<=130-K.frankDeltaKmh+1,sign..': lift under the current passer speed: '..lowest)
 end
end
return tests
