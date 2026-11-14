-- Affinage 1.63 w2 (Monza, F1, 22 IA, session 2 du pilote du 13 novembre, journal 2026-11-13_15_33_36_monza : 88 tentatives,
-- 2 réussies, 44 fins « cible plus rapide » à 4-7 m au plus près, 2 frondes seulement) : la fronde ne jouait qu'au-delà
-- de 6 m (déboîtement 0,6 s après l'arrêt du rapprochement, à plus de 1000 m du freinage) et, de 8 à 12 m, la règle
-- « ligne droite trop courte » et la fronde ne se recouvraient jamais (aucun déboîtement). Noms LOCK_*_163 (tests/LOCKS.md).
-- Chargé par tests/extended.lua. Scènes latérales avec -1 / -1 et +1 / +1.
local F=require('tests/fixture')
local E=require('src/engine')
local FL=require('src/firstlap')
local K=require('src/config').K
local tests={}

-- Course, ligne droite : attaquant (voiture 2) qui rattrape sa cible (voiture 3, 250 km/h) à 262 km/h depuis 40 m ;
-- rapprochement arrêté à stopAt m ; point de freinage 1900 m devant au début. Rend les transitions (état, écart,
-- distance au freinage).
local function chase(sign,stopAt,seconds,flW)
 local e,f=F.scene('C',3); e.g.offsetSign=sign; e.g.sideSign=sign
 local p=e.profiles.C; p.personalLineJitter=0; p.startDelay=0; p.startRelax=0; E.changed(e)
 for i=1,f.count do f.cars[i].sideDot=sign end
 F.place(f,1,-5000,100); f.started=true; F.tick(e,f,40)
 e.fl.count=1
 local s=e.states[2]; local z=0; local gap=40; local last=''; local out={}
 for k=1,60*seconds do
  local va=gap>stopAt+0.05 and 262 or 250; z=z+va/3.6/60; gap=gap-(va-250)/3.6/60
  F.place(f,2,z,va,0); F.place(f,3,z+gap+4.4,250,0)
  if k==1 then e.fl.points={(e.frame.cars[2].spline+1900/e.frame.length)%1} end
  if flW then s.flW=flW end
  s.nextPerception=0; F.tick(e,f,1/60)
  if s.state~=last then last=s.state; out[#out+1]={state=s.state,gap=gap,np=FL.nextPoint(e.fl,e.frame.cars[2],e.frame.length)} end
 end
 return out
end
local function first(out,state) for _,o in ipairs(out) do if o.state==state then return o end end end

-- Rapprochement arrêté à 5 m (cas de Monza) : il reste dans l'aspiration loin du freinage et déboîte à la fronde
-- (avant : à plus de 1000 m du freinage) ; à 9 m, il déboîte aussi (avant : jamais) ; premier tour : comme avant.
tests.LOCK_SHORT_SLING_163=function()
 for _,sign in ipairs({1,-1}) do
  for _,gap in ipairs({5,9}) do
   local out=chase(sign,gap,30)
   local pull=first(out,'OVT_IN')
   assert(pull,sign..', '..gap..' m: pulled out before the braking point')
   assert(pull.np<=500 and pull.np>=150,sign..', '..gap..' m: slingshot near the braking point ('..string.format('%.0f',pull.np)..' m)')
   assert(first(out,'OVT_HOLD'),sign..', '..gap..' m: position reached')
  end
  local early=first(chase(sign,5,30,1),'OVT_IN')
  assert(early and early.np>600,sign..': first lap: pull-out as before (far from braking)')
  -- Affinage 1.64 z1 : courbe rapide (corner sous K.passCornerC, règle du dernier moment hors jeu) : à 5 m dans le
  -- sillage, la fronde courte garde l'attaquant derrière loin du freinage (chemin réel en Curva Grande, Parabolica).
  local D=require('src/director')
  local e={profile='C',fl={points={0.5},count=1},time=0}
  local a={splineValid=true,spline=0.4,speed=69,length=4.4,corner=0.5}
  local st={seekFront=0,flW=0}
  local r
  for k=0,60 do e.time=k/60; r=D.seekLateTest(e,st,a,{index=3,gap=5,sa=0,lat=0.3*sign},{length=10000,player=1}) end
  assert(r==false,sign..': fast corner, 5 m in the wake, braking point 1000 m ahead: short sling keeps it behind')
 end
end

-- Côte à côte au freinage (chevauchement d'au moins 30 %) : jamais d'abandon « cible plus rapide » ; la priorité au
-- virage décide. Attaquant mené jusqu'à 2 m de chevauchement, puis cible qui accélère (256 km/h) pendant 2 s.
tests.LOCK_ALONGSIDE_BRAKING_163=function()
 for _,sign in ipairs({1,-1}) do
  local e,f=F.scene('C',3); e.g.offsetSign=sign; e.g.sideSign=sign
  local p=e.profiles.C; p.personalLineJitter=0; p.startDelay=0; p.startRelax=0; E.changed(e)
  for i=1,f.count do f.cars[i].sideDot=sign end
  F.place(f,1,-5000,100); f.started=true; F.tick(e,f,40)
  local s=e.states[2]; local z=0; local gap=30; local lat=0; local overlapped=false; local t0
  for k=1,60*25 do
   local vt=250
   if overlapped then vt=256 end
   local va=overlapped and 250 or (gap>-1.5 and 262 or 250)
   z=z+va/3.6/60; gap=gap-(va-vt)/3.6/60
   if s.state=='OVT_IN' or s.state=='OVT_HOLD' then lat=math.min(3.4,lat+3.4/60) end
   F.place(f,2,z,va,0); F.place(f,3,z+gap+4.4,vt,0)
   f.cars[2].lateral=(f.cars[2].lateral or 0)
   s.nextPerception=0; F.tick(e,f,1/60)
   if not overlapped and gap<=-1.5 and (s.state=='OVT_HOLD' or s.state=='OVT_IN') then overlapped=true; t0=k end
   if overlapped and gap<=-(4.4*0.3) then
    assert(s.state=='OVT_IN' or s.state=='OVT_HOLD' or s.state=='OVT_OUT' and s.lastReason~='abort_slow',sign..': overlapped: never cancelled as « target faster » ('..s.state..')')
   end
   if overlapped and k-t0>120 then break end
  end
  assert(overlapped,sign..': scene reached the overlap')
 end
end

-- Attaque au freinage (Monza, session 2 : 243 refus « virage ou freinage ») : course hors premier tour, attaquant à 8 m
-- derrière sa cible, même allure, les deux au freinage avant le braquage, côté libre : l'attaque s'engage (avant :
-- refus « virage ou freinage », rapprochement exigé de 5 km/h) et l'attaquant freine plus tard (prudence au plus
-- K.diveCautionRace). Premier tour : comme avant.
local function brakingScene(sign,flW)
 local e,f=F.scene('C',3); e.g.offsetSign=sign; e.g.sideSign=sign
 local p=e.profiles.C; p.personalLineJitter=0; p.startDelay=0; p.startRelax=0; E.changed(e)
 for i=1,f.count do f.cars[i].sideDot=sign end
 F.place(f,1,-5000,100); f.started=true; F.tick(e,f,40)
 local s=e.states[2]; local z=0; local engaged=false; local caution=math.huge
 for k=1,60*4 do
  local v=220-k*0.5
  z=z+v/3.6/60
  F.place(f,2,z,v,0); F.place(f,3,z+8+4.4,v,0)
  f.cars[2].brake=0.8; f.cars[3].brake=0.8
  if k==1 then e.fl.points={(e.frame.cars[2].spline+150/e.frame.length)%1}; e.fl.count=1 end
  if flW then s.flW=flW end
  s.nextPerception=0; F.tick(e,f,1/60)
  if s.state=='OVT_ARM' or s.state=='OVT_IN' or s.state=='OVT_HOLD' then engaged=true end
  if s.state=='OVT_IN' or s.state=='OVT_HOLD' then caution=math.min(caution,e.commands[2].caution or math.huge) end
 end
 return engaged,caution,s.baseCaution
end
tests.LOCK_BRAKING_DIVE_163=function()
 for _,sign in ipairs({1,-1}) do
  local engaged,caution,base=brakingScene(sign)
  assert(engaged,sign..': attack under braking engaged')
  assert(caution<base-1e-6 and caution>=base*K.diveCautionShare-1e-6,sign..': brakes a little later ('..caution..' / base '..base..')')
  assert(not brakingScene(sign,1),sign..': first lap: as before (no dive at equal speed)')
 end
end

-- Alignement dans l'aspiration (pilote : « toutes les IA se mettent dans l'aspiration de celle de devant ») : course hors
-- premier tour, suiveur à 30 m, même allure, cible décalée de 0,8 m, longue ligne droite : il se recale derrière elle
-- (avant : seulement au-delà de 1 m d'écart latéral).
tests.LOCK_WAKE_ALIGN_163=function()
 for _,sign in ipairs({1,-1}) do
  local e,f=F.scene('C',3); e.g.offsetSign=sign; e.g.sideSign=sign
  local p=e.profiles.C; p.personalLineJitter=0; p.startDelay=0; p.startRelax=0; E.changed(e)
  for i=1,f.count do f.cars[i].sideDot=sign end
  F.place(f,1,-5000,100); f.started=true; F.tick(e,f,40)
  local s=e.states[2]; local z=0; local aligned=false
  for k=1,60*4 do
   z=z+250/3.6/60
   F.place(f,2,z,250,0); F.place(f,3,z+30+4.4,250,0.8*sign)
   if k==1 then e.fl.points={(e.frame.cars[2].spline+2500/e.frame.length)%1}; e.fl.count=1 end
   s.nextPerception=0; F.tick(e,f,1/60)
   if (s.seekFront or 0)==3 then aligned=true; break end
  end
  assert(aligned,sign..': follower lines up in the wake of the car ahead')
 end
end

-- Cible appelée aux stands qui ralentit pour l'entrée pendant l'attaque (Monza, session 2 : « reussi » compté à 379 s,
-- la cible entrait aux stands à 379,8 s) : fin « cible aux stands », jamais une réussite.
tests.LOCK_TARGET_PIT_163=function()
 for _,sign in ipairs({1,-1}) do
  local engaged,_,_,e,s,f=nil
  local e2,f2=F.scene('C',3); e2.g.offsetSign=sign; e2.g.sideSign=sign
  local p=e2.profiles.C; p.personalLineJitter=0; p.startDelay=0; p.startRelax=0; E.changed(e2)
  for i=1,f2.count do f2.cars[i].sideDot=sign end
  F.place(f2,1,-5000,100); f2.started=true; F.tick(e2,f2,40)
  local st=e2.states[2]; local z=0; local gap=30; local inPass=false; local ended
  for k=1,60*20 do
   local vt=inPass and 200 or 250
   local va=gap>6 and 262 or 250; if inPass then va=250 end; z=z+va/3.6/60; gap=gap-(va-vt)/3.6/60
   F.place(f2,2,z,va,0); F.place(f2,3,z+gap+4.4,vt,0)
   if inPass then e2.commands[3].rulePit=true end
   st.nextPerception=0; F.tick(e2,f2,1/60)
   if inPass then e2.commands[3].rulePit=true end
   if not inPass and (st.state=='OVT_ARM' or st.state=='OVT_IN' or st.state=='OVT_HOLD') then inPass=true end
   if inPass and st.state=='OVT_OUT' then ended=true; break end
  end
  assert(inPass,sign..': attack started')
  assert(ended,sign..': attack ended when the target entered the pits')
  assert((e2.stats.clear or 0)==0 and (e2.stats.target_pit or 0)>=1,sign..': ended as « target in the pits », never a success')
 end
end

tests.K_163W2=function() assert(K.slingMinGap==K.wakePullGap and K.slingMinGap<K.wakeStallGapRace) end
return tests
