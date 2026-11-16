-- Affinage 2.0.2 h (le pilote, 16 novembre : « en course, les IA freinent et ne me doublent pas si je suis plus lent ;
-- même dans le bas-côté, quand je reviens sur la piste, l'IA reste derrière, freine et ne me double pas ») : sous un
-- jaune de zone seule, la voiture en cause (accidentée, hors piste, tout juste repartie : src/penalties.lua, passable)
-- se double (K.yellowPassIncident) ; une voiture repartie, qui roule sans glisser, n'est plus un obstacle contourné au
-- ralenti (K.avoidRejoinEnds). Journal de Barcelone du 15 novembre, 3513,5 s : « incident: tete-a-queue, hors piste,
-- 3761 m, 105 km/h, Chevalier.V » puis « zone jaune ouverte: Chevalier.V a 3761 m (simple) » : la zone vient du joueur
-- lui-même. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local K=require('src/config').K
local tests={}
local function passing(st) return st.OVT_OUT or st.OVT_IN or st.OVT_HOLD end
-- Joueur (1) en tête-à-queue hors piste à lat*2,5 m, puis repartant à rejoinKmh km/h, écarté de lat m, gap m devant
-- l'IA 2 (allure libre apprise 200 km/h, à aiKmh km/h). other : voiture 3 (incident ailleurs, ou loin).
local function scene(lat,gap,rejoinKmh,aiKmh,spin,slide)
 local e,f=F.scene('C',3); e.startedAt=-100
 local p=e.profiles.C; p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.startDelay=0; p.startRelax=0
 E.changed(e)
 local s=e.states[2]
 local function pace() s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=200/3.6 end; s.paceMean=200/3.6 end
 pace()
 local st={}; local minOff,maxOff=0,0
 local pl=f.cars[1]
 -- Tête-à-queue hors piste (1,5 s).
 for _=1,90 do
  F.place(f,1,2000+gap,spin and 20 or rejoinKmh,spin and lat*2.5 or lat); F.place(f,2,2000,aiKmh); F.place(f,3,-4000,100)
  pl.slip=spin and 90 or 0; pl.offtrack=spin==true; pl.lx=spin and 1 or 0; pl.lz=spin and 0 or 1
  pace(); F.tick(e,f,1/60)
 end
 local opened=e.incidents.cars[1].incident==true and s.yellow==true
 -- Retour en piste : roule droit, sans glisser.
 for _=1,300 do
  F.place(f,1,2000+gap,rejoinKmh,lat); F.place(f,2,2000,aiKmh); F.place(f,3,-4000,100)
  pl.slip=slide and 90 or 0; pl.offtrack=false; pl.lx=0; pl.lz=1; f.cars[2].yawRate=0.005; pl.yawRate=0.005
  pace(); F.tick(e,f,1/60); st[s.state]=true; if not st.first and (s.state=='OVT_OUT' or s.state=='OVT_IN' or s.state=='OVT_HOLD') then st.first=_ end
  if not st.avoidEnd and st.AVOID and s.state~='AVOID' then st.avoidEnd=_ end
  minOff=math.min(minOff,s.offset); maxOff=math.max(maxOff,s.offset)
 end
 return s,e,st,opened,minOff,maxOff
end
local function sanctioned(e)
 for _,l in ipairs(e.log.lines or {}) do if tostring(l):find('sanction IA',1,true) or tostring(l):find('IA disqualifiee',1,true) then return true end end
 return false
end
tests.LOCK_PASS_PLAYER_OFFTRACK_202=function()
 for _,lat in ipairs({3,-3}) do
  local s,e,st,opened,lo,hi=scene(lat,18,70,75,true)
  assert(opened,lat..': the spin opens the player incident and the yellow zone')
  assert(passing(st) and (e.stats.yellowPassIncident or 0)>=1,lat..': passes the rejoining player under his own yellow ('..tostring(s.state)..')')
  -- Jamais vers le côté d'où il revient.
  if lat>0 then assert(hi<=1e-6 and lo<-0.05,lat..': away from the player ('..lo..', '..hi..')')
  else assert(lo>=-1e-6 and hi>0.05,lat..': away from the player ('..lo..', '..hi..')') end
  assert(not sanctioned(e),lat..': no AI sanction for passing the car involved')
  assert((st.OVT_IN or st.OVT_HOLD) and (e.stats.abort_yellow or 0)==0,lat..': the pass goes on, never cut by the yellow ('..tostring(e.stats.abort_yellow)..')')
  -- 2.0.2 g : l'IA restait derrière (drapeau jaune).
  K.yellowPassIncident=false; local s2,e2,st2=scene(lat,18,70,75,true); K.yellowPassIncident=true
  assert(not passing(st2),lat..': 2.0.2 g stayed behind ('..tostring(s2.state)..')')
 end
end
-- Voiture repartie en piste près de la trajectoire (2,4 m, dans la file de l'IA) : en 2.0.2 g, obstacle contourné au
-- ralenti (niveau réduit) tant que son incident durait (3 s après la reprise) ; désormais fini dès qu'elle roule sans
-- glisser (K.avoidRejoinEnds), dépassement plus tôt.
tests.LOCK_REJOIN_NO_AVOID_202=function()
 for _,lat in ipairs({2.4,-2.4}) do
  local s,e,st=scene(lat,18,70,75,true)
  assert(st.AVOID and st.avoidEnd and st.avoidEnd<=120 and st.first and st.first<=150,lat..': avoidance ends and the pass starts soon ('..tostring(st.avoidEnd)..', '..tostring(st.first)..')')
  K.avoidRejoinEnds=false; local _,_,st2=scene(lat,18,70,75,true); K.avoidRejoinEnds=true
  assert(st2.avoidEnd and st2.avoidEnd>=160 and st2.first and st2.first>=190,lat..': 2.0.2 g avoided behind him longer ('..tostring(st2.avoidEnd)..', '..tostring(st2.first)..')')
  -- Toujours en travers (glisse encore) : l'évitement continue.
  local s3,_,st3=scene(lat,18,70,75,true,true)
  assert(st3.AVOID and not st3.avoidEnd and s3.state=='AVOID',lat..': a sliding car is still avoided ('..tostring(s3.state)..')')
 end
end
-- Sous jaune d'une autre voiture, jamais de dépassement d'une voiture qui roule (le joueur lent n'est pas en cause).
tests.LOCK_YELLOW_OTHER_CAR_HELD_202=function()
 for _,lat in ipairs({3,-3}) do
  local e,f=F.scene('C',3); e.startedAt=-100
  local p=e.profiles.C; p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.startDelay=0; p.startRelax=0
  E.changed(e)
  local s=e.states[2]; local st={}
  local lim=e.commands[2]
  -- Zone ouverte d'abord (voiture 3 arrêtée hors piste depuis 3 s), puis l'IA arrive derrière le joueur.
  for _=1,180 do local w=F.place(f,3,2250,0,8); w.offtrack=true; w.slip=0; F.place(f,1,1500,100); F.place(f,2,1000,100); F.tick(e,f,1/60) end
  for _=1,360 do
   -- Joueur à l'allure permise sous le jaune (jamais « en difficulté »), IA juste derrière à la même allure.
   local v=lim.yellowLimit<K.unlimitedSpeed and lim.yellowLimit or 150
   F.place(f,1,2018,v,lat); F.place(f,2,2000,v+3); local w=F.place(f,3,2250,0,8); w.offtrack=true; w.slip=90; w.lx=1; w.lz=0
   s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=200/3.6 end; s.paceMean=200/3.6
   F.tick(e,f,1/60); st[s.state]=true
  end
  assert(e.incidents.cars[3].incident and s.yellow,lat..': yellow from car 3')
  assert(not passing(st) and (e.stats.yellowPassIncident or 0)==0,lat..': the running player is not passed under yellow ('..tostring(s.state)..')')
 end
end
-- Jaune de zone seulement : neutralisation, drapeau rouge ou tour de relance de la voiture : rien ne change.
tests.LOCK_YELLOW_ZONE_ONLY_202=function()
 local D=require('src/director')
 local cars={{restart=false},{restart=true}}
 assert(D.yellowZoneTest({cars=cars},1,true)==true and D.yellowZoneTest({cars=cars},1,false)==false,'local zone')
 assert(D.yellowZoneTest({cars=cars,neutral=true},1,true)==false,'neutralisation')
 assert(D.yellowZoneTest({cars=cars,red=true},1,true)==false,'red flag')
 assert(D.yellowZoneTest({cars=cars,restart=true},2,true)==false and D.yellowZoneTest({cars=cars,restart=true},1,true)==true,'restart lap')
end
tests.K_202H=function() assert(K.yellowPassIncident==true and K.avoidRejoinEnds==true and K.playerSlowFleet==nil) end
return tests
