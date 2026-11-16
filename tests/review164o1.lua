-- Affinage 1.64 o1 (Monza, F1, 22 IA, session 19 du pilote du 14 novembre, journal 2026-11-14_10_33_19_monza) : Leclerc
-- ressort mieux de la chicane que Kaisanlahti (10 m derrière, +31 km/h à 460,5 s), attend dans l'aspiration (9 m) et le
-- radar le freine ; ses 5 tentatives finissent « sans rapprochement ». Demande du pilote : « s'il ressort mieux du virage,
-- il en profite pour doubler, il ne doit pas ralentir ». En course hors premier tour, dans les K.exitPassWindow s après un
-- virage, à K.exitPassGap m au plus d'une IA rattrapée d'au moins K.exitPassSa km/h : déboîtement aussitôt, du côté
-- opposé à la cible. Noms LOCK_*_164 (tests/LOCKS.md). Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local K=require('src/config').K
local tests={}

-- Attaquant 2 à gap m derrière la cible 3 (décalée de lat m), rattrapée de sa km/h ; virage pendant cornerTime s puis
-- ligne droite ; point de freinage connu à 2000 m.
local function scene(lat,gap,sa,cornerTime,target,brakeAt)
 local e,f=F.scene('C',4); local p=e.profiles.C
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.passAid=false; p.startDelay=0; p.startRelax=0
 E.changed(e); F.tick(e,f,0.2)
 target=target or 3
 F.place(f,1,-5000,100); F.place(f,4,5000,100)
 local s=e.states[2]
 s.state='OVT_ARM'; s.reason='pass'; s.since=e.time; s.target=target; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=gap; s.passName='Cible'
 s.abortSlow=0; s.passStall=0; s.passAlongside=false; s.passProgRef=gap; s.passProgTime=0; s.lastPassTarget=target; s.nextPerception=0
 local t=0; local pulled=false
 while t<cornerTime+1.0 do
  local yaw=t<cornerTime and 1.5 or 0
  f.cars[2].yawRate=yaw; f.cars[target].yawRate=yaw
  F.place(f,2,0,150+sa,0); F.place(f,target,gap+4.4,150,lat); s.nextPerception=0
  e.fl.points={(f.cars[2].spline+(brakeAt or 2000)/f.length)%1}; e.fl.count=1
  F.tick(e,f,1/60); t=t+1/60
  if s.state=='OVT_IN' then pulled=true; break end
 end
 return s,e,pulled
end
tests.LOCK_CORNER_EXIT_PASS_164=function()
 for _,lat in ipairs({1.0,-1.0}) do
  -- Session 19 : 10 m derrière, +31 km/h, juste après la chicane : déboîtement aussitôt, du côté opposé à la cible.
  local s,e,pulled=scene(lat,10,31,0.5)
  assert(pulled and (e.stats.exitPass or 0)>=1,lat..': pulls out at the corner exit ('..tostring(s.state)..')')
  -- Côté opposé à la cible, dans le repère de la perception (cible décalée de +lat : déboîtement vers -lat), les deux
  -- côtés étant libres dans la scène (verrou renforcé après la série longue : la mutation « côté de la cible » passait).
  assert(s.targetSide==(lat>0 and -1 or 1),lat..': side away from the target ('..tostring(s.targetSide)..')')
  local first=s.targetSide
  assert(e.time<(s.exitPassUntil or 0),lat..': exit-pass window open (no tow hold, radar guard only)')
  -- Côté opposé selon la cible : les deux décalages donnent deux côtés différents.
  local s2=select(1,scene(-lat,10,31,0.5)); assert(s2.targetSide==-first,lat..': side away from the target')
  -- Règle coupée : jamais par cette règle.
  K.exitPassEnabled=false; local _,e3=scene(lat,10,31,0.5); K.exitPassEnabled=true
  assert((e3.stats.exitPass or 0)==0,lat..': switch off')
  -- Pas de virage récent, rapprochement trop faible, trop loin : jamais par cette règle.
  local _,e4=scene(lat,10,31,0); assert((e4.stats.exitPass or 0)==0,lat..': no recent corner')
  local _,e5=scene(lat,10,5,0.5); assert((e5.stats.exitPass or 0)==0,lat..': too little closing')
  -- 2.0.2 (recalage des mutations) : près du freinage, la garde « pas en milieu de ligne droite » (towTooEarly) ne joue
  -- plus et ne cache plus le seuil de rapprochement : à +5 km/h, toujours jamais par cette règle.
  local _,e5b=scene(lat,10,5,0.5,nil,250); assert((e5b.stats.exitPass or 0)==0,lat..': too little closing, near the braking point')
  local _,e6=scene(lat,K.exitPassGap+8,31,0.5); assert((e6.stats.exitPass or 0)==0,lat..': too far')
 end
 -- Cible à peine décalée (0,4 m, les deux côtés libres) : le premier côté essayé est bien l'opposé de la cible (verrou
 -- renforcé après la série longue : plus décalée, le couloir du côté de la cible se ferme et cache l'erreur).
 for _,lat in ipairs({0.4,-0.4}) do
  local s,_,pulled=scene(lat,10,31,0.5)
  assert(pulled and s.targetSide==(lat>0 and -1 or 1),lat..': slight offset: side away from the target ('..tostring(s.targetSide)..')')
 end
end
-- Glissades en courbe (session 19 : suivis à niveau 1,04-1,06 et prudence 0,65-0,77 en courbe) : en virage, niveau au plus
-- K.cornerLevelMax (sauf base plus haute) et prudence au moins K.cornerCautionMin (au plus la base) ; en ligne droite, rien.
local function guard(yaw,lat)
 local e,f=F.scene('C',3); local p=e.profiles.C
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.startDelay=0; p.startRelax=0
 E.changed(e); F.tick(e,f,0.2)
 local cmd=e.commands[2]; local s=e.states[2]
 for _=1,90 do
  F.place(f,1,-3000,100); F.place(f,3,3000,100); local a=F.place(f,2,0,120,lat)
  a.yawRate=yaw; a.baseLevel=0.9
  F.tick(e,f,1/60)
 end
 return cmd,s
end
tests.LOCK_CORNER_GRIP_GUARD_164=function()
 local sl,sc,sm=K.cornerLevelMax,K.maxCaution,K.minCaution
 local ok,err=pcall(function()
  K.cornerLevelMax=0.9; K.maxCaution=0.6; K.minCaution=0.5
  for _,lat in ipairs({0.5,-0.5}) do
   local cmd,s=guard(1.5,lat)
   assert(cmd.level<=0.9+1e-6,lat..': level capped in a corner ('..cmd.level..')')
   assert(cmd.caution>=math.min(0.8,s.baseCaution or 0.8)-1e-6,lat..': caution floor in a corner ('..cmd.caution..')')
   cmd=guard(0,lat)
   assert(cmd.caution<0.8,lat..': no caution floor on a straight ('..cmd.caution..')')
  end
 end)
 K.cornerLevelMax,K.maxCaution,K.minCaution=sl,sc,sm
 assert(ok,err)
end
-- Erreur devant (demande du pilote : « petite erreur, sortie large : celle de derrière ralentit aussi au lieu d'en profiter ») :
-- cible en sortie large (2 roues dehors), rattrapée de 10 km/h, en ligne droite, sans virage récent : déboîtement aussitôt du côté opposé.
local function mistake(lat,sa,off,firstLap)
 local e,f=F.scene('C',4); local p=e.profiles.C
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.passAid=false; p.startDelay=0; p.startRelax=0
 E.changed(e); F.tick(e,f,0.2)
 F.place(f,1,-5000,100); F.place(f,4,5000,100)
 local s=e.states[2]
 s.state='OVT_ARM'; s.reason='pass'; s.since=e.time; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=10; s.passName='Cible'
 s.abortSlow=0; s.passStall=0; s.passAlongside=false; s.passProgRef=10; s.passProgTime=0; s.lastPassTarget=3; s.nextPerception=0
 for _=1,60 do
  f.cars[2].yawRate=0; f.cars[3].yawRate=0
  F.place(f,2,0,150+sa,0); F.place(f,3,14.4,150,lat); f.cars[3].wheelsOut=off and 2 or 0; s.nextPerception=0
  e.fl.points={(f.cars[2].spline+2000/f.length)%1}; e.fl.count=1
  F.tick(e,f,1/60)
  if s.state=='OVT_IN' then break end
 end
 return s,e
end
tests.LOCK_MISTAKE_PASS_164=function()
 for _,lat in ipairs({1.2,-1.2}) do
  local s,e=mistake(lat,10,true)
  assert((e.stats.mistakePass or 0)>=1 and s.state=='OVT_IN',lat..': passes the car that ran wide ('..tostring(s.state)..')')
  assert(s.targetSide==(lat>0 and -1 or 1),lat..': side away from where it ran wide ('..tostring(s.targetSide)..')')
  local _,e2=mistake(lat,10,false); assert((e2.stats.mistakePass or 0)==0,lat..': no mistake, no rule')
  K.mistakePassEnabled=false; local _,e3=mistake(lat,10,true); K.mistakePassEnabled=true
  assert((e3.stats.mistakePass or 0)==0,lat..': switch off')
 end
end
-- Drapeau bleu au virage (demande du pilote : « au braquage, le retardataire réaccélère alors que la voiture rapide est encore
-- à sa hauteur ») : cession tenue, levée de pied et prudence relevée tant qu'elle est à sa hauteur ou à moins de
-- K.blueCornerClear m devant, en virage ; ensuite la trêve : pas d'attaque sur elle pendant K.blueNoAttack s.
local function blueCorner(sign,lead,yaw)
 local e,f=F.scene('C',3); e.g.offsetSign=sign; e.g.sideSign=sign; e.startedAt=-100
 local s=e.states[2]
 local x=-30
 for k=1,600 do
  -- Cession engagée (voiture rapide 30 m derrière), puis elle remonte par l'autre côté jusqu'à lead m devant.
  if k>240 then x=math.min(lead,x+12/60) end
  local turning=k>240 and x>=-6
  f.cars[2].yawRate=turning and yaw or 0; f.cars[3].yawRate=turning and yaw or 0
  F.place(f,1,-4000,100); F.place(f,2,5000,170); F.place(f,3,5000+x,k>240 and 213 or 220,-sign*3.5); f.cars[3].lap=f.cars[2].lap+1
  F.tick(e,f,1/60)
  if k==240 then s.yieldingAt=s.state end
  if x>=lead and k>300 and turning then break end
 end
 return s,e,s.yieldingAt
end
tests.LOCK_BLUE_CORNER_HOLD_164=function()
 for _,sign in ipairs({1,-1}) do
  local s,e,yielding=blueCorner(sign,2,1.5)
  assert(yielding=='YIELD_IN' or yielding=='YIELD_HOLD','yields first ('..sign..'): '..yielding)
  assert(s.blueCornerHold==true and (e.stats.blueCornerHold or 0)>0,'holds the yield in the corner, lapper alongside ('..sign..')')
  assert(s.state~='YIELD_OUT' and s.state~='DRIVE','no early return to its pace ('..sign..'): '..s.state)
  -- Voiture rapide juste passée (10 m devant), encore dans le virage : cession tenue, pas de retour à l'allure.
  local s3,e3=blueCorner(sign,10,1.5)
  assert(s3.blueCornerHold==true and s3.state~='YIELD_OUT' and s3.state~='DRIVE','still held just after the pass ('..sign..'): '..s3.state)
  assert(s3.passIgnore==3 and e3.time<s3.passIgnoreUntil,'no attack on the car that just passed ('..sign..')')
  -- Voiture rapide bien devant (au-delà de K.blueCornerClear), même en virage : la tenue finit.
  local s2=blueCorner(sign,K.blueCornerClear+15,1.5); assert(not s2.blueCornerHold,'released once clearly ahead ('..sign..')')
 end
end
-- Décision du pilote 2026-11-14 (vidéos : suiveurs décalés de 1 à 1,5 m dans l'aspiration) : recalage dès K.wakeAlignLat m
-- (0,3 m, avant 0,7 m) en ligne droite ; en courbe, rien ne change (le recalage n'y joue pas).
local function align(sign,lat,yaw)
 local e,f=F.scene('C',3); e.g.offsetSign=sign; e.g.sideSign=sign
 local p=e.profiles.C; p.personalLineJitter=0; p.startDelay=0; p.startRelax=0; E.changed(e)
 for i=1,f.count do f.cars[i].sideDot=sign end
 F.place(f,1,-5000,100); f.started=true; F.tick(e,f,40)
 local s=e.states[2]; local z=0
 for k=1,60*4 do
  z=z+250/3.6/60
  f.cars[2].yawRate=yaw; f.cars[3].yawRate=yaw
  F.place(f,2,z,250,0); F.place(f,3,z+30+4.4,250,lat*sign)
  if k==1 then e.fl.points={(e.frame.cars[2].spline+2500/e.frame.length)%1}; e.fl.count=1 end
  s.nextPerception=0; F.tick(e,f,1/60)
  if (s.seekFront or 0)==3 then return true end
 end
 return false
end
tests.LOCK_WAKE_ALIGN_TIGHT_164=function()
 for _,sign in ipairs({1,-1}) do
  assert(align(sign,0.45,0),sign..': 0.45 m off the wake on a straight: lines up')
  assert(not align(sign,0.15,0),sign..': already in the wake (0.15 m): no move')
  assert(not align(sign,0.45,1.5),sign..': in a corner: unchanged, no move')
 end
end
tests.K_164O1=function()
 assert(K.exitPassEnabled==true and K.exitPassGap==15 and K.exitPassSa==12 and K.exitPassWindow>0 and K.exitPassRadarTTC<=0.6 and K.exitPassHold>0 and K.cornerGuardEnabled==true and K.cornerLevelMax<=1.03 and K.cornerCautionMin>=0.8 and K.mistakePassEnabled==true and K.blueCornerClear>=15 and K.blueNoAttack>=5,'constants')
end
return tests
