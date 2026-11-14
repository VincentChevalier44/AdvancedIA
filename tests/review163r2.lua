-- Relecture 1.63 (N/b163/RELECTURE_163.md) : M1 zone dangereuse sans apprentissage, M2 évitement figé, M3/S8 priorité
-- au virage et attardée, S3 attaque poussée hors pluie, S5 sillage tardif jamais derrière le joueur, S6 zone dangereuse
-- hors tour lancé de qualifications et hotlap, S2 essais de redémarrage par incident.
-- Noms terminés par _163R2. Chargé par tests/extended.lua. Les scènes latérales tournent avec -1 et +1.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local D=require('src/director')
local P=require('src/perception')
local Incidents=require('src/incidents')
local K=C.K
local DK=Incidents.DK or {dangerPct={0.04,0.07}}
local tests={}

local function signed(e,f,sign) e.g.offsetSign=sign; e.g.sideSign=sign; for i=1,f.count do f.cars[i].sideDot=sign end; E.changed(e) end
local function learned(e,i,kmh) local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=kmh/3.6 end; s.paceMean=kmh/3.6 end
local function logged(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end

-- M1 : sous le plafond de la zone dangereuse, l'allure apprise ne baisse pas (avant : elle rejoignait la vitesse
-- plafonnée à chaque passage).
tests.DANGER_NO_PACE_LEARNING_163R2=function()
 local e,f=F.scene('C',3)
 F.place(f,1,-5000,100); F.place(f,2,0,150); F.place(f,3,5000,150)
 F.tick(e,f,1/60)
 learned(e,2,200)
 local s=e.states[2]
 local bin=1; for b=1,e.delta.bins do if s.pace[b]>0 then bin=b; break end end
 for _=1,120 do s.dangerCapped=true; F.place(f,2,0,150); F.tick(e,f,1/60); s.dangerCapped=true end
 local lowest=math.huge; for b=1,e.delta.bins do if s.pace[b]>0 and s.pace[b]<lowest then lowest=s.pace[b] end end
 assert(math.abs(lowest-200/3.6)<1e-6,'capped: pace not learnt ('..(lowest*3.6)..' km/h)')
 s.dangerCapped=false
 for _=1,120 do F.place(f,2,0,150); F.tick(e,f,1/60); s.dangerCapped=false end
 lowest=math.huge; for b=1,e.delta.bins do if s.pace[b]>0 and s.pace[b]<lowest then lowest=s.pace[b] end end
 assert(lowest<200/3.6-1,'not capped: learning as before')
end

-- S6 : jamais en hotlap ni sur un tour lancé de qualifications.
tests.DANGER_SESSIONS_163R2=function()
 for _,profile in ipairs({'H','Q'}) do
  local e,f=F.scene(profile,4)
  F.place(f,1,1000,150); F.place(f,2,1000,150); F.place(f,3,3000,150); F.place(f,4,5000,150)
  F.tick(e,f,1/60)
  local L=f.length; local t=e.incidents
  for k=1,K.hotspotCount do Incidents.hotspotNote(t,f.cars[2].spline+100/L,L,e.time,10+k) end
  for i=1,4 do learned(e,i,200) end
  e.run.section_accidents=true
  if profile=='Q' then e.quali.active=true; e.quali.push[2]=true else e.profile='H' end
  e.commands[2].speedLimit=K.unlimitedSpeed
  E.dangerCapTest(e,2,e.states[2],e.time)
  assert(e.commands[2].speedLimit==K.unlimitedSpeed and not e.states[2].dangerCapped,profile..': no danger cap')
 end
end

-- M2 : part de l'évitement figée au début de l'épisode ; l'IA qui s'écarte ne revient pas vers l'obstacle.
tests.AVOID_SHARE_FROZEN_163R2=function()
 for _,sign in ipairs({-1,1}) do
  local e,f=F.scene('J',3); e.p.personalLineJitter=0; signed(e,f,sign)
  F.place(f,1,-5000,100); F.place(f,2,0,100); F.place(f,3,60,0,0.8*sign)
  local s=e.states[2]; local first,low=nil,math.huge
  -- L'obstacle s'éloigne latéralement (comme si l'IA s'était déjà écartée) : le chevauchement mesuré baisse.
  local lat,steps=0.8,0
  for _=1,60 do
   if s.state=='AVOID' and steps<20 then steps=steps+1; lat=0.8+steps*0.06 end
   F.place(f,3,60,0,lat*sign); F.tick(e,f,0.1)
   if s.state=='AVOID' and s.avoidShare then first=first or s.avoidShare; low=math.min(low,s.avoidShare) end
  end
  assert(first and first>0.5,sign..': scene: avoidance with a real overlap ('..tostring(first)..')')
  assert(first and low>=first-1e-9,sign..': share never decreases ('..tostring(first)..' / '..tostring(low)..')')
 end
end

-- M3 et S8 : priorité au virage avec une voiture attardée. Les deux sens latéraux.
tests.CORNER_PRIORITY_REVIEW_163R2=function()
 for _,sign in ipairs({-1,1}) do
  -- other : voiture voisine (3 IA, ou 1 le joueur) ; nose : la voisine a le nez devant (sinon derrière) ;
  -- laps : +1 l'IA 2 prend un tour à la voisine, -1 la voisine prend un tour à l'IA 2.
  local function give(other,nose,laps)
   local e,f=F.scene('C',3); e.startedAt=-100; e.p.personalLineJitter=0
   local far=other==3 and 1 or 3
   local function put()
    F.place(f,far,-5000,100); F.place(f,2,0,120,0); F.place(f,other,nose and 3 or -3,120,2.5*sign)
    if laps>0 then f.cars[2].lap=f.cars[other].lap+1 elseif laps<0 then f.cars[other].lap=f.cars[2].lap+1 end
    f.cars[2].yawRate=0.4; f.cars[other].yawRate=0.4; f.cars[2].brake=0.5
   end
   put(); e.states[2].nextPerception=0
   local seen=false
   for _=1,12 do F.tick(e,f,0.1); put(); if e.states[2].cornerGiveTo==other then seen=true end end
   return seen,e
  end
  assert(give(1,true,1),sign..': lapping the player who has his nose ahead: still gives him the corner (M3)')
  assert(not give(3,true,1),sign..': lapping an AI: keeps its line (1.63)')
  local seen,e=give(3,false,-1)
  assert(seen and logged(e,'(drapeau bleu)')>=1,sign..': being lapped, nose ahead: gives the corner to the lapping car (S8)')
  assert(not give(3,false,0),sign..': same lap, nose ahead: keeps the corner (as before)')
 end
end

-- S5 : sillage tardif jamais derrière le joueur.
tests.WAKE_NOT_BEHIND_PLAYER_163R2=function()
 local e={fl={points={0.5},count=1},time=0}
 local a={splineValid=true,spline=0.4,speed=60,length=4.4}
 local s={seekFront=0}
 local f={length=10000,player=3}
 local target={index=3,gap=10,sa=20,lat=0.4}
 assert(D.seekLateTest(e,s,a,target,f)==true,'behind the player: no late pull-out hold')
 f.player=1
 assert(D.seekLateTest(e,s,a,target,f)==false,'behind an AI: stays in the wake as before')
end

-- S3 : attaque poussée jamais sur piste mouillée.
tests.ATTACK_PUSH_DRY_ONLY_163R2=function()
 local function pushes(wet)
  local e,f=F.scene('C',3); e.g.offsetSign=-1; e.g.sideSign=-1
  local p=e.profiles.C; p.startDelay=0; p.startRelax=0; p.personalLineJitter=0; E.changed(e)
  for i=1,f.count do f.cars[i].sideDot=-1 end
  F.place(f,1,-5000,100)
  local s=e.states[2]
  for _=1,240 do F.place(f,2,0,220,0); F.place(f,3,24.4,180,0); f.wet=wet; s.nextPerception=0; F.tick(e,f,1/60) end
  return e.stats.attackPush or 0
 end
 assert(pushes(0)>=1,'dry: attack push as before')
 assert(pushes(0.6)==0,'wet track: no attack push')
end

-- S2 : une voiture repartie qui s'arrête de nouveau dans le même incident ne repart pas à zéro.
tests.REJOIN_TRIES_PER_INCIDENT_163R2=function()
 local e,f=F.scene('P',3); F.place(f,2,-4000,120); F.place(f,3,1000,0); F.tick(e,f,3)
 local c=e.incidents.cars[3]
 assert(c.incident,'scene: stopped')
 F.tick(e,f,1); assert(c.rejoinTries==1,'first attempt')
 F.place(f,3,1030,0); F.tick(e,f,0.5)
 assert(logged(e,'IA accidentee repart (redemarree, 1 essai(s))')==1,'moved off once')
 F.tick(e,f,K.rejoinStill+K.rejoinGap+1)
 assert(c.rejoinTries==2,'stopped again in the same incident: the count goes on ('..tostring(c.rejoinTries)..')')
end

return tests
