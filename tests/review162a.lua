-- Beta 1.62, règles par session, partie pilotage (src/director.lua) : ligne droite jugée aussi sur l'accélération
-- latérale ; journée circuit « line » (la voiture lente garde sa ligne), dépassements en ligne droite, pas de suivi
-- collé ; essais (relais long) ; qualifications (fin de tour, virage sacrifié) ; inattentions. Noms terminés par _162A.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local D=require('src/director')
local K=C.K
local tests={}
local function scene(profile,n,set)
 local e,f=F.scene(profile,n or 3); local p=e.profiles[profile]
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false
 if set then set(p) end
 -- Signes mesurés en jeu sur cette installation : -1 / -1.
 e.g.offsetSign=-1; e.g.sideSign=-1; for i=1,f.count do f.cars[i].sideDot=-1 end
 E.changed(e)
 return e,f
end

tests.K_162A=function()
 assert(K.cornerLatRef==10 and K.jFollowTime==1 and K.jFollowCaution==1.4 and K.jPassMargin==0.5)
 assert(K.qualiSacrificeTime==2 and K.lapEndMeters==600 and K.practiceLapMargin==0.015)
end

-- Courbe rapide : 0,1 rad/s à 250 km/h (environ 0,7 g) n'est plus une ligne droite ; la même rotation lente reste
-- jugée sur la rotation seule.
tests.CORNERNESS_LATERAL_162A=function()
 assert(D.cornerness(0,250/3.6,0.5)==1,'straight')
 local fast=D.cornerness(0.1,250/3.6,0.5)
 assert(fast<0.35,'fast sweeper at 250 km/h is a corner: '..fast)
 local slow=D.cornerness(0.1,10,0.5)
 assert(math.abs(slow-0.8)<1e-9,'slow: rotation only: '..slow)
 assert(D.cornerness(-0.1,250/3.6,0.5)==fast,'sign ignored')
end

-- Journée circuit, décision 1 : « line » : la voiture lente cède en gardant sa ligne ; côté réglé : elle se décale.
tests.LINE_YIELD_KEEPS_LINE_162A=function()
 local function run(side)
  local e,f=scene('J',3,function(p) p.yieldSide=side end)
  local held,maxOff=false,0
  for _=1,8*60 do
   F.rear(e,f,30,40); F.tick(e,f,1/60)
   local s=e.states[2]
   if F.yielding(s.state) then held=true; maxOff=math.max(maxOff,math.abs(s.offset-(s.base or 0))) end
  end
  return held,maxOff,e
 end
 local held,off,e=run('line')
 assert(held,'track day: the slower car yields')
 assert(e.states[2].yieldLine==true,'line yield flagged')
 assert(off<0.02,'it keeps its line: '..off)
 local held2,off2=run('right')
 assert(held2 and off2>0.1,'control: with a fixed side it moves aside: '..off2)
end

-- « line » : le passage franc ne demande pas de décalage à la cible ; il demande la place à côté d'elle.
tests.LINE_FRANK_NEEDS_ROOM_162A=function()
 local e,f=scene('J',3,function(p) p.yieldSide='line' end)
 F.tick(e,f,0.2)
 local ts=e.states[3]
 ts.state='YIELD_HOLD'; ts.followers[2]=true; ts.yieldLine=true; ts.offset=0; ts.base=0
 F.place(f,3,20,100); F.place(f,2,8,110)
 local frank=D.frankYieldTest(e,f,2,3,'J',e.g,nil)
 assert(frank==true,'room on both sides of the target: frank')
 -- Relecture M2 : place jugée au-delà de la cible (ses largeurs), pas celles de l'attaquant.
 f.cars[3].leftWidth=2.4; f.cars[3].rightWidth=2.4; f.cars[2].leftWidth=8; f.cars[2].rightWidth=8
 assert(D.frankYieldTest(e,f,2,3,'J',e.g,nil)==false,'2.4 m each side of the target: no room to pass beside it')
 -- Cible près d'un bord (signes -1/-1 du jeu) : franc, et le côté choisi est le large.
 f.cars[3].leftWidth=1.5; f.cars[3].rightWidth=9
 assert(D.frankYieldTest(e,f,2,3,'J',e.g,nil)==true,'target near the left edge: room on the right')
 local p=e.run; local s=e.states[2]; local g={offsetSign=-1,sideSign=-1}
 p.overtakeSide='auto' -- préréglage « Journée circuit »
 local row={front=0,back=0,neighbors={},left=false,right=false}
 local front={lat=1,index=3,gap=12,sa=10}
 local side=D.passSideTest(p,'J',s,front,row,f.cars[3],g,f.cars[2])
 assert(side*g.offsetSign>0,'side with room (right) chosen, not the side of the target offset noise: '..side)
 f.cars[3].leftWidth=9; f.cars[3].rightWidth=1.5
 side=D.passSideTest(p,'J',s,front,row,f.cars[3],g,f.cars[2])
 assert(side*g.offsetSign<0,'mirror: left chosen: '..side)
 ts.yieldLine=false
 f.cars[3].leftWidth=6; f.cars[3].rightWidth=6
 assert(D.frankYieldTest(e,f,2,3,'J',e.g,nil)==false,'ordinary yield still needs the target to have moved')
end

-- Journée circuit : dépassement seulement en ligne droite (seuil de la course) ; en essais, comme avant.
tests.TRACKDAY_PASS_STRAIGHT_ONLY_162A=function()
 local function run(profile)
  local e,f=scene(profile,3)
  local yaw=nil
  for _=1,4*60 do
   F.front(e,f,25,30)
   -- a.corner = 0,5 : entre p.cornerMin (0,35) et K.passCornerC (0,6), rotation lente (accélération latérale faible).
   yaw=e.profiles[profile].cornerYawRef*0.5; f.cars[2].yawRate=yaw; f.cars[2].kmh=40; f.cars[2].speed=40/3.6; f.cars[3].kmh=20; f.cars[3].speed=20/3.6
   F.tick(e,f,1/60)
  end
  return e
 end
 local e=run('J')
 assert((e.stats.refCorner or 0)>=1,'track day: refused in a gentle corner')
 local p=run('P')
 assert((p.stats.refCorner or 0)==0,'practice: gentle corner still allowed')
end

-- Journée circuit : collé à moins de K.jFollowTime s sans doubler : prudence relevée ; plus loin : non.
tests.TRACKDAY_NO_TAILGATE_162A=function()
 local function caution(profile,gap)
  local e,f=scene(profile,3,function(p) p.overtakeEnabled=false end)
  for _=1,30 do F.front(e,f,gap,0); F.tick(e,f,1/60) end
  return e.commands[2].caution
 end
 local close,far=caution('J',10),caution('J',60)
 assert(close>=far*K.jFollowCaution*0.99,'track day: caution raised when tailgating: '..close..' vs '..far)
 local pc,pf=caution('P',10),caution('P',60)
 assert(math.abs(pc-pf)<1e-6 or pc<pf*K.jFollowCaution*0.99,'practice: no track-day tailgating rule')
end

-- Essais, décision 2 : relais long : suiveur à peine plus rapide au tour : pas de cession ; nettement plus rapide : oui.
tests.PRACTICE_LONG_RUN_MARGIN_162A=function()
 local function run(ratio)
  local e,f=scene('P',3)
  local s,fs=e.states[2],e.states[3]
  local yielded=false
  for _=1,6*60 do
   s.paceRatio=1; s.paceRatioCount=K.paceRatioMin; fs.paceRatio=ratio; fs.paceRatioCount=K.paceRatioMin
   F.rear(e,f,25,15); F.tick(e,f,1/60)
   if F.yielding(s.state) then yielded=true end
  end
  return yielded
 end
 assert(run(1.005)==false,'follower 0.5 % faster per lap: no yield')
 assert(run(1.03)==true,'follower 3 % faster per lap: yield')
end

-- Qualifications : deux voitures en tour de sortie, dernier tronçon avant la ligne : pas de dépassement (compté une
-- fois) ; au milieu du tour : rien.
tests.QUALI_LAP_END_AGREEMENT_162A=function()
 local function run(z,cool)
  local e,f=scene('Q',3,function(p) p.qualiTraffic=true end)
  for _=1,3*60 do
   e.quali.cars[2].out=true; e.quali.cars[3].out=true; e.quali.cars[3].cool=cool==true
   F.place(f,2,z,130); F.place(f,3,z+25+4.4,100); e.states[2].nextPerception=0
   F.tick(e,f,1/60)
  end
  return e
 end
 local near=run(10000*2-400-25)
 assert(near.quali.push[2]==false and near.quali.push[3]==false,'both on an out-lap')
 assert((near.stats.lapEndHold or 0)==1,'no pass in the last metres: one episode: '..tostring(near.stats.lapEndHold))
 local mid=run(10000+3000)
 assert((mid.stats.lapEndHold or 0)==0,'mid-lap: no hold')
 -- Relecture 1.62 (S7) : voiture devant en tour de refroidissement : jamais de retenue.
 local cool=run(10000*2-400-25,true)
 assert((cool.stats.lapEndHold or 0)==0,'car ahead cooling down: no hold')
end

-- Décision 8 : aucune inattention ne commence en virage ; en ligne droite, oui.
tests.LAPSE_STRAIGHT_ONLY_162A=function()
 local function run(yaw)
  local e,f=scene('P',3,function(p) p.lapseEnabled=true end)
  F.place(f,2,0,150); F.place(f,3,3000,150)
  F.tick(e,f,0.1)
  local s=e.states[2]; s.lapseAt=e.time; s.lapseUntil=0
  f.cars[2].yawRate=yaw
  F.tick(e,f,1/60)
  return s.lapseUntil>0
 end
 assert(run(0)==true,'straight: a lapse starts')
 assert(run(0.3)==false,'fast corner: no lapse')
end
-- Essais : la voiture qui cède ne lève le pied qu'en ligne droite ; en virage, niveau tenu (décalage seulement).
tests.YIELD_LIFT_STRAIGHT_ONLY_162A=function()
 local function level(profile,yaw)
  local e,f=scene(profile,3)
  local s=e.states[2]; local lv
  for _=1,40 do
   s.state='YIELD_HOLD'; s.target=3; s.targetSide=1; s.followers[3]=true; s.yieldStart=e.time-1; s.holdUntil=e.time+60; s.yieldDetection=100; s.yieldMargin=5; s.yieldBlue=false
   F.place(f,2,0,100); F.place(f,3,-40,110); f.cars[2].yawRate=yaw; s.nextPerception=0
   F.tick(e,f,1/60); lv=e.commands[2].level
  end
  return lv
 end
 local straight,corner=level('P',0),level('P',0.3)
 assert(corner>straight*1.02,'practice: no lift in a corner: '..corner..' vs '..straight)
end

-- Qualifications : voiture lancée à moins de K.qualiSacrificeTime s : la cession commence dans une courbe (seuil
-- ordinaire) et le décalage est tenu dans le virage ; en essais, la cession à une voiture lancée attend K.lapCorner.
tests.QUALI_SACRIFICE_CORNER_162A=function()
 local function run(profile)
  local e,f=scene(profile,3,function(p) p.qualiTraffic=true end)
  local s=e.states[2]; local first,off=nil,0
  for n=1,4*60 do
   e.quali.cars[2].out=true; e.quali.cars[3].out=false; e.quali.cars[3].cool=false
   F.place(f,2,0,100); F.place(f,3,-40,200); f.cars[2].yawRate=0.18; s.nextPerception=0
   F.tick(e,f,1/60)
   if F.yielding(s.state) then first=first or n; off=math.max(off,math.abs(s.offset)) end
  end
  return first,off,e
 end
 local first,off,e=run('Q')
 assert(e.quali.push[3]==true and e.quali.push[2]==false,'flying car behind an out-lap car')
 assert(first,'qualifying: the yield starts in the curve')
 assert(off>0.7*e.profiles.Q.yieldOffset,'offset held through the corner: '..off)
 assert(run('P')==nil,'practice: waits for K.lapCorner')
end
return tests
