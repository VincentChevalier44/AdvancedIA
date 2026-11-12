-- Beta 1.59 (journées circuit du 10 novembre, décisions 19 et 20 du pilote) : le trafic s'écoule hors course (l'IA qui
-- cède lève vraiment le pied, le suiveur s'engage, refus de céder seulement à un suiveur nettement plus lent, voiture
-- lente au rythme inconnu jugée sur sa classe, radar avant qui ne freine plus pour une voiture qui se range) ; préréglage
-- intégré Journée circuit hors Nordschleife. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local J=require('src/journal')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function learned(e,i,kmh)
 local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=kmh/3.6 end; s.paceMean=kmh/3.6
end

-- Choix du préréglage de la journée circuit selon le circuit ; préréglage personnel et Endurance gardés.
tests.TRACKDAY_PRESET_CHOICE_159T=function()
 assert(K.nordschleifeMinLength==15000)
 assert(C.trackDayPreset('imola',4909)=='Circuit' and C.trackDayPreset('fn_imola',4869)=='Circuit','Imola: Journée circuit')
 assert(C.trackDayPreset('ks_nordschleife',20800)=='Nordschleife','ks_nordschleife: Nordschleife')
 assert(C.trackDayPreset('ks_nordschleife',25221)=='Nordschleife','Nordschleife endurance layout')
 assert(C.trackDayPreset('fn_nurburgring',25700)=='Nordschleife' and C.trackDayPreset('nuerburgring_combined',25000)=='Nordschleife','long Nurburgring: Nordschleife')
 assert(C.trackDayPreset('ks_nurburgring',5148)=='Circuit','GP circuit: Journée circuit')
 local g=C.validateGlobals(C.globalDefaults)
 assert(C.sessionPreset(g,'J','imola',4909)=='Circuit' and C.sessionPreset(g,'J','fn_nurburgring',25700)=='Nordschleife','no mark: by track')
 C.setMark(g,'J','Nordschleife'); assert(C.sessionPreset(g,'J','imola',4909)=='Circuit','Nordschleife mark, other track: Journée circuit')
 C.setMark(g,'J','Circuit'); assert(C.sessionPreset(g,'J','ks_nordschleife',20800)=='Nordschleife','Circuit mark, Nordschleife: Nordschleife')
 C.setMark(g,'J','Endurance'); assert(C.sessionPreset(g,'J','imola',4909)=='Endurance','Endurance kept')
 C.setMark(g,'J',C.personalMark); assert(C.sessionPreset(g,'J','imola',4909)==nil,'personal preset kept')
 assert(C.sessionPreset(g,'P','imola',4909)=='Essais','other profiles unchanged')
 -- Contenu : comme la Nordschleife, côtés libres, appels de phares plus rares.
 local n,c=C.preset('Nordschleife','J',{}),C.preset('Circuit','J',{})
 -- Beta 1.62 (décision 1 du pilote) : le plus lent garde sa ligne (yieldSide='line').
 assert(n.yieldSide=='right' and c.yieldSide=='line' and c.overtakeSide=='auto','free sides')
 assert(c.flashRange<n.flashRange and c.flashMinAdvantage>n.flashMinAdvantage,'fewer flashes')
 for _,group in ipairs(C.sections) do assert(n['section_'..group]==c['section_'..group],'same sections: '..group) end
 for key,value in pairs(n) do
  if key~='yieldSide' and key~='laneBiasEnabled' and key~='overtakeSide' and key~='flashRange' and key~='flashMinAdvantage' then assert(c[key]==value,'same value: '..key) end
 end
 assert(J.english('preset_session: Circuit (profil J)')=='preset_session: Track day (profile J)',J.english('preset_session: Circuit (profil J)'))
end

-- Session : journée circuit à Imola → Journée circuit ; à fn_nurburgring (25,7 km) → Nordschleife, noté au journal.
tests.TRACKDAY_PRESET_SESSION_159T=function()
 local function run(track,length)
  local e,f=F.scene('J',3); e.g.presetBySession=true; e.g.autoProfile=true; f.track=track; f.length=length; f.configTrackDay=true; f.session=5
  E.step(e,f,1/60)
  return e
 end
 local e=run('fn_imola',4869)
 assert(e.profile=='J' and C.mark(e.g,'J')=='Circuit' and count(e,'preset_session: Circuit (profil J)')==1,'Imola: Journée circuit')
 e=run('fn_nurburgring',25700)
 assert(C.mark(e.g,'J')=='Nordschleife' and count(e,'preset_session: Nordschleife (profil J, circuit Nordschleife)')==1,'fn_nurburgring: Nordschleife')
end

-- Cession ordinaire hors course : refus seulement à un suiveur plus lent de K.yieldRefuseKmh km/h ; en course, règle 1.55.
tests.YIELD_REFUSAL_MARGIN_159T=function()
 assert(K.yieldRefuseKmh==3)
 local function yields(profile,mine,theirs)
  local e,f=F.scene(profile); local p=e.profiles[profile]; p.personalLineJitter=0; p.pressureEnabled=false; p.flashObliviousPct=0; E.changed(e)
  F.rear(e,f,45,30,3)
  for _=1,4*60 do learned(e,2,mine); learned(e,3,theirs); F.tick(e,f,1/60); if F.yielding(e.states[2].state) then return true,e end end
  return false,e
 end
 assert((yields('J',180,180)),'same pace: yield')
 assert((yields('J',180,178)),'within the margin: yield')
 local seen,e=yields('J',180,170)
 assert(not seen and count(e,'cession refusee:')==1,'clearly slower: refused, logged once')
end

-- Attaque sur une IA qui cède à l'attaquant : plus d'abandon « cible plus rapide », « sans progrès » ni « trop longue »
-- hors course ; sans cession : abandon comme avant.
tests.ATTACK_COMMITS_ON_YIELD_159T=function()
 -- Même scène que la tentative forcée de la 1.55 (écart figé, vitesse alternée) : sans cession, « sans progrès » à 8 s.
 local function run(yielding)
  local e,f=F.scene('J',3); e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
  F.place(f,2,0,105); F.place(f,3,24.4,100)
  local s,o=e.states[2],e.states[3]
  s.state='OVT_IN'; s.reason='pass'; s.since=e.time; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=20; s.passName='Cible'
  s.abortSlow=0; s.passStall=0; s.passAlongside=false; s.passProgRef=20; s.passProgTime=0; s.lastPassTarget=3; s.nextPerception=0
  local t=0
  while t<20 do
   if yielding then o.state='YIELD_HOLD'; o.target=2; o.followers[2]=true; o.yieldStart=e.time; o.holdUntil=e.time+60; o.yieldDetection=100; o.yieldMargin=5 end
   local slow=math.floor(t*2)%2==0
   F.place(f,3,24.4,slow and 100 or 107); s.nextPerception=0
   F.tick(e,f,1/60); t=t+1/60
   if not F.passing(s.state) then break end
  end
  return s,t
 end
 local s,t=run(false)
 assert(s.reason=='abort_noprogress' and t<K.passProgressTime+1,'no yield: abort as before ('..tostring(s.reason)..' at '..t..')')
 s,t=run(true)
 assert(F.passing(s.state) or (s.reason~='abort_noprogress' and s.reason~='abort_timeout' and s.reason~='abort_slow' and s.reason~='abort_stall'),'target yielding to it: committed, got '..tostring(s.reason)..' at '..t)
end

-- Voiture lente au rythme habituel inconnu : obstacle hors course sous K.slowUnknownRatio fois l'allure de sa classe ;
-- en course, diagnostic seulement (inchangé).
tests.SLOW_UNKNOWN_CLASS_159T=function()
 assert(K.slowUnknownRatio==0.5)
 local function run(profile,kmh)
  local e,f=F.scene(profile,4); e.profiles[profile].personalLineJitter=0; E.changed(e)
  f.length=60611; F.tick(e,f,1/60)
  for i=2,4 do learned(e,i,165); e.states[i].longRatio=1; e.states[i].longRatioTime=0 end
  F.place(f,1,-20000,0); F.place(f,2,1000,kmh); F.place(f,3,1000-15-4.4,kmh); F.place(f,4,30000,165)
  for _=1,12*60 do for i=2,4 do learned(e,i,165); e.states[i].longRatioTime=0 end; F.tick(e,f,1/60) end
  return e
 end
 assert(run('J',60).states[2].abnormal,'track day: 60 km/h where the class runs 165, usual pace unknown: obstacle')
 assert(not run('J',100).states[2].abnormal,'track day: 100 km/h (61 % of the class pace): not abnormal')
 assert(not run('C',60).states[2].abnormal,'race: unknown usual pace stays diagnostic only')
end

-- Radar avant : le joueur se range (s'écarte latéralement) devant une IA plus rapide : pas de freinage hors course ;
-- joueur sur la trajectoire : freinage comme avant.
tests.RADAR_CLEARING_CAR_159T=function()
 local function run(profile,lateral)
  local e,f=F.scene(profile,2); local p=e.profiles[profile]; p.personalLineJitter=0; p.overtakeEnabled=false; E.changed(e); F.tick(e,f,0.2)
  local z2,z1=0,30; local most=0
  for k=1,150 do
   local t=k/60
   z2=z2+150/3.6/60; z1=z1+110/3.6/60
   F.place(f,2,z2,150); F.place(f,1,z1,110,lateral(t))
   F.tick(e,f,1/60); most=math.max(most,e.states[2].radarBrake or 0)
   if z1-z2<6 then break end
  end
  return most
 end
 local moving=function(t) return math.min(3.5,0.3+math.max(0,t-0.8)*4) end
 assert(run('J',function() return 0 end)>0,'player on the line: the radar brakes')
 assert(run('J',moving)==0,'player moving aside: no radar brake')
 assert(run('C',moving)>0,'race: unchanged')
end

-- Cession à un suiveur plus rapide sur une journée circuit : l'IA qui cède lève vraiment le pied (vitesse de pointe sous
-- celle du suiveur) et le suiveur passe en quelques secondes.
local function trackdayYield()
 local e,f=F.scene('J',3); local p=e.p; p.personalLineJitter=0; p.aiFlashEnabled=false; E.changed(e); F.tick(e,f,0.2)
 local z={[2]=200,[3]=150}; local v={[2]=170,[3]=176}
 local yieldAt,passAt,minCap=nil,nil,math.huge
 for k=1,60*60 do
  learned(e,2,170); learned(e,3,176)
  for i=2,3 do
   local cap=e.commands[i].speedLimit or K.unlimitedSpeed
   local speed=math.min(v[i],cap)
   z[i]=z[i]+speed/3.6/60; F.place(f,i,z[i],speed,f.cars[i].x)
   f.cars[i].x=(e.states[i].offset or 0)*6; f.cars[i].splineLat=f.cars[i].x
  end
  F.place(f,1,-5000,0)
  F.tick(e,f,1/60)
  local t=k/60
  if not yieldAt and F.yielding(e.states[2].state) then yieldAt=t end
  if yieldAt and not passAt and z[3]>z[2]+6 then passAt=t end
  if F.yielding(e.states[2].state) then minCap=math.min(minCap,e.commands[2].speedLimit or K.unlimitedSpeed) end
  if passAt then break end
 end
 print(string.format('1.59t track-day yield: yield at %s s, pass at %s s, lowest cap %.0f km/h',tostring(yieldAt),tostring(passAt),minCap))
 assert(yieldAt,'slower AI yields')
 assert(minCap<=176-K.yieldPassDeltaKmh+0.5,'the yielding AI really lifts: top speed under the follower ('..minCap..')')
 assert(passAt and passAt-yieldAt<15,'pass completes within 15 s of the yield')
end
-- Beta 1.61 (mutations masquées depuis le lever de pied franc du lot 3) : la même cession, passage franc neutralisé
-- (décalage exigé hors d'atteinte) : la limite de la 1.59 (15 km/h sous le suiveur) suffit seule à lever le pied.
local function withK(values,fn)
 local saved={}; for k,v in pairs(values) do saved[k]=K[k]; K[k]=v end
 local ok,err=pcall(fn)
 for k,v in pairs(saved) do K[k]=v end
 if not ok then error(err,0) end
end
tests.TRACKDAY_YIELD_PASS_159T=function()
 trackdayYield()
 withK({frankOffM=1e9},trackdayYield)
end
-- Cession avec deux suiveurs en file derrière (pas à sa hauteur) : limite de vitesse levée au bout de K.yieldQueueTime s
-- (une voiture tenue sous sa vitesse ferait un bouchon), comptée une fois ; un seul suiveur : limite tenue.
tests.YIELD_CAP_QUEUE_RELEASE_159T=function()
 assert(K.yieldQueueTime==3)
 local function run(followers)
  local e,f=F.scene('J',4); E.changed(e)
  F.place(f,1,-5000,0); F.place(f,2,0,150); F.place(f,3,-14.4,160); F.place(f,4,followers==2 and -34.4 or -3000,160); learned(e,2,150)
  local s=e.states[2]; local capped=false; local start=e.time-1
  for _=1,6*60 do
   s.state='YIELD_HOLD'; s.target=3; s.targetSide=1; s.followers[3]=true; s.followers[4]=followers==2; s.yieldStart=start; s.holdUntil=e.time+60; s.yieldDetection=100; s.yieldMargin=5
   F.tick(e,f,1/60); if e.commands[2].speedLimit<K.unlimitedSpeed then capped=true end
  end
  return e,capped
 end
 local e1,c1=run(1)
 assert(c1 and e1.commands[2].speedLimit<K.unlimitedSpeed,'one follower: the yielding AI keeps its lift')
 local e2,c2=run(2)
 assert(e2.commands[2].speedLimit>=K.unlimitedSpeed and (e2.stats.yieldCapQueue or 0)==1,'two queued followers: lift released, counted once ('..tostring(e2.commands[2].speedLimit)..', '..tostring(e2.stats.yieldCapQueue)..', queue '..tostring(e2.states[2].yieldQueueFor)..')')
end
-- Joueur rangé à 3 m à gauche en ligne droite, IA derrière sur la trajectoire à +40 km/h, freinage d'AC pour garder
-- l'écart : hors course, ni frein du radar ni dépassement retenu (invitation ou rapprochement en quelques secondes) ;
-- joueur sur la trajectoire : le radar protège toujours.
tests.PLAYER_ASIDE_PASS_159T=function()
 -- lateral(t) : position latérale du joueur ; acBrake : l'IA native freine pour garder l'écart (vitesse calée sur 112).
 local function run(profile,lateral,acBrake)
  local e,f=F.scene(profile,2); local p=e.profiles[profile]; p.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
  local z2,z1=0,35; local passAt,most,moved=nil,0,0
  for k=1,6*60 do
   local t=k/60
   local held=acBrake and z1-z2<30
   f.cars[2].brake=held and 0.25 or 0
   local v2=held and 112 or 150
   z2=z2+v2/3.6/60; z1=z1+110/3.6/60
   F.place(f,2,z2,v2,(e.states[2].offset or 0)*6); F.place(f,1,z1,110,lateral(t))
   F.tick(e,f,1/60); most=math.max(most,e.states[2].radarBrake or 0)
   if not passAt and F.passing(e.states[2].state) then passAt=t end
   if passAt then moved=math.max(moved,e.states[2].offset or 0) end
   if z1-z2<5 then break end
  end
  return passAt,most,moved
 end
 local aside=function(t) return -math.min(3,math.max(0,t-0.3)*4) end
 local passAt,_,moved=run('J',aside,true)
 assert(moved>0.2,'the pass moves to the free side despite AC braking ('..moved..')')
 assert(passAt and passAt<4,'player moving 3 m aside, AC braking for the gap: the AI passes within a few seconds ('..tostring(passAt)..')')
 local _,most=run('J',aside,false)
 assert(most==0,'player moving aside: no radar brake ('..most..')')
 local _,onLine=run('J',function() return 0 end,false)
 assert(onLine>0,'player on the line: the radar still brakes')
end

-- Le cas du coordinateur : IA à 80 km/h où sa classe roule à 165, rythme habituel inconnu, 4 IA plus rapides en file
-- derrière : obstacle, et chacune des 4 (la 4e comprise) lance un dépassement en quelques secondes.
tests.SLOW_QUEUE_FOUR_159T=function()
 local e,f=F.scene('J',6); e.p.personalLineJitter=0; E.changed(e)
 f.length=60611; F.tick(e,f,1/60)
 F.place(f,1,-20000,0); F.place(f,2,1000,80)
 for i=3,6 do F.place(f,i,1000-(i-2)*15,80) end
 local started={}; local seen
 for k=1,15*60 do
  for i=2,6 do learned(e,i,165); e.states[i].longRatio=1; e.states[i].longRatioTime=0 end
  F.tick(e,f,1/60)
  for i=3,6 do if not started[i] and (F.passing(e.states[i].state) or e.states[i].state=='AVOID') then started[i]=k/60 end end
  seen=seen or {}; for i=3,6 do seen[i]=(seen[i] or '')..(seen[i] and seen[i]:sub(-#e.states[i].state)==e.states[i].state and '' or ' '..e.states[i].state) end
 end
 local fl=e.delta.fleet[1]; local b=require('src/delta').bin(f.cars[2].spline,e.delta.bins)
 assert(e.states[2].abnormal,'80 km/h where the class runs 165, usual pace unknown: obstacle (fleet '..tostring(fl and fl[b] and fl[b]*3.6)..', state '..e.states[2].state..', for '..tostring(e.states[2].abnormalFor)..')')
 for i=3,6 do assert(started[i],'follower '..(i-2)..' starts a pass (obstacle or overtake):'..seen[i]) end
 assert((e.stats.obstacle or 0)>=4,'the four followers go round it (obstacle path): '..tostring(e.stats.obstacle)..' ;'..seen[3]..' |'..seen[6])
 -- Évitement d'obstacle coupé : la file passe par le dépassement, les voitures 3 et 4 de la file comprises.
 e,f=F.scene('J',6); e.p.personalLineJitter=0; e.profiles.J.obstacleEnabled=false; E.changed(e)
 f.length=60611; F.tick(e,f,1/60)
 F.place(f,1,-20000,0); F.place(f,2,1000,80)
 for i=3,6 do F.place(f,i,1000-(i-2)*15,80) end
 local passed={}
 for _=1,15*60 do
  for i=2,6 do learned(e,i,165); e.states[i].longRatio=1; e.states[i].longRatioTime=0 end
  F.tick(e,f,1/60)
  for i=3,6 do if F.passing(e.states[i].state) then passed[i]=true end end
 end
 for i=3,6 do assert(passed[i],'obstacle off: follower '..(i-2)..' starts a pass') end
 assert((e.stats.queuePass or 0)>=3,'queue passes counted: '..tostring(e.stats.queuePass))
end

-- Limite de cession : le suiveur qui freine pour garder son écart (vitesse calée sur celle de l'IA qui cède) ne la fait
-- pas descendre en spirale jusqu'à K.trafficMinSpeed.
tests.YIELD_CAP_NO_SPIRAL_159T=function()
 local e,f=F.scene('J',3); E.changed(e)
 F.place(f,1,-5000,0); F.place(f,2,0,170); F.place(f,3,-14.4,170); learned(e,2,170)
 local s=e.states[2]; local start=e.time-1; local lowest=math.huge
 for _=1,8*60 do
  s.state='YIELD_HOLD'; s.target=3; s.targetSide=1; s.followers[3]=true; s.yieldStart=start; s.holdUntil=e.time+60; s.yieldDetection=100; s.yieldMargin=5
  local cap=e.commands[2].speedLimit or K.unlimitedSpeed
  local v2=math.min(170,cap); F.place(f,2,0,v2); F.place(f,3,-14.4,v2)
  -- Beta 1.60 (lot 3) : suiveur tenu hors dépassement (sinon lever de pied franc : tests/review160w.lua)
  e.states[3].restUntil=e.time+10
  F.tick(e,f,1/60); lowest=math.min(lowest,e.commands[2].speedLimit or K.unlimitedSpeed)
 end
 assert(lowest>=170-K.yieldPassDeltaKmh-0.5,'cap held from the follower speed first seen, no spiral: '..lowest)
end

-- Priorité à l'entrée du virage (19i, tous profils) : côte à côte en virage, le nez derrière de plus de K.cornerNoseMargin m
-- cède (lève le pied, quitte son attaque ou sa défense, une ligne au journal) ; nez devant : garde sa ligne ; nez à
-- égalité : aucun des deux ne cède. Jamais de mouvement vers une voiture à côté (vérifié à chaque image par le fixture).
local function corner(profile,ahead,attacker,behind)
 local first
 local e,f=F.scene(profile,3); e.profiles[profile].personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
 local yaw=e.run.cornerYawRef*0.8
 F.place(f,1,-5000,0)
 local s=e.states[2]
 for k=1,90 do
  -- Voiture 2 à droite, l'autre (attacker : la 3 ou le joueur) à gauche, 2,5 m d'écart ; la 2 a ahead m d'avance au nez.
  F.place(f,2,1000+ahead,120,-1.25); F.place(f,attacker,1000,120,1.25)
  if behind then F.place(f,1,1000+ahead-12,120,-1.25) end
  for i=1,3 do f.cars[i].yawRate=yaw end
  if k==1 then s.state='OVT_HOLD'; s.reason='pass'; s.since=e.time; s.target=attacker; s.targetSide=-1; s.passStartAt=e.time; s.passMinGap=0; s.passName='Cible'; s.passAlongside=true; s.lastPassTarget=attacker end
  s.nextPerception=0; e.states[3].nextPerception=0
  F.tick(e,f,1/60)
  if k==1 then first=e.commands[2].throttleLimit end
 end
 return e,s,first
end
tests.CORNER_PRIORITY_159T=function()
 assert(K.cornerNoseMargin==2.2)
 for _,profile in ipairs({'J','C'}) do
  -- IA 2 en attaque, nez 3 m derrière l'IA 3 au virage : elle cède.
  local e,s,first=corner(profile,-3,3)
  assert(first>1-2*K.cornerLiftRate/60,profile..': gentle lift, never a step ('..first..')')
  assert(not (s.state=='OVT_IN' or s.state=='OVT_HOLD'),profile..': nose behind: the attacker leaves its pass ('..s.state..')')
  assert(e.commands[2].throttleLimit<=K.cornerGiveLift+1e-9,profile..': nose behind: it lifts')
  assert(count(e,'priorite au virage: Driver_2 cede a Driver_3 (nez derriere)')==1 and (e.stats.cornerGive or 0)==1,profile..': one line per episode')
  assert(count(e,'depassement fini: Driver_2 -> Cible : priorite au virage (nez derriere)')==1,profile..': pass end with its reason')
  -- Nez devant : l'attaquante garde sa ligne ; l'IA 3 à côté (nez derrière) lève le pied.
  e,s=corner(profile,3,3)
  assert(s.state=='OVT_HOLD' and e.commands[2].throttleLimit==1,profile..': nose ahead: keeps its line ('..s.state..')')
  assert(e.commands[3].throttleLimit<=K.cornerGiveLift+1e-9 and count(e,'priorite au virage: Driver_3 cede a Driver_2')==1,profile..': the defender AI leaves room')
  -- Nez à égalité : personne ne cède.
  e,s=corner(profile,1,3)
  assert((e.stats.cornerGive or 0)==0,profile..': level noses: nobody gives way')
  -- Voiture à 12 m derrière : elle cède sans lever le pied (jamais de coupure devant une voiture).
  e,s=corner(profile,-3,3,true)
  assert(e.commands[2].throttleLimit==1 and (e.stats.cornerGive or 0)==1,profile..': a car close behind: gives way without lifting')
  -- Joueur devant au virage : l'IA cède.
  e,s=corner(profile,-3,1)
  assert(e.commands[2].throttleLimit<=K.cornerGiveLift+1e-9 and count(e,'priorite au virage: Driver_2 cede a Driver_1 (nez derriere)')==1,profile..': the player ahead: the AI gives way')
 end
 assert(J.english('priorite au virage: A (100%, 100%) cede a B (nez derriere)')=='corner priority: A (100%, 100%) gives way to B (nose behind)',J.english('priorite au virage: A (100%, 100%) cede a B (nez derriere)'))
 -- Ligne droite, sans freinage : aucune priorité en jeu.
 local e=F.scene('J',3); assert((e.stats.cornerGive or 0)==0)
end

-- Règle du pilote : jamais de coup de frein devant une voiture collée. Suiveur à 5 m, 10 km/h plus vite : la limite de
-- cession part de la vitesse du moment et descend d'au plus K.yieldCapDecelOff km/h par seconde ; le radar du suiveur
-- n'a pas à freiner fort ; levée progressive ensuite (jamais sous la vitesse du moment).
local function yieldCapGentle()
 assert(K.yieldCapDecelOff==6 and K.yieldCapReleaseKmh==8)
 -- Suiveur 5 m derrière (pare-chocs), 10 km/h plus vite, qui se cale en douceur (15 km/h/s) comme l'IA d'AC.
 local function run(yield)
  local e,f=F.scene('J',3); E.changed(e); F.tick(e,f,0.2)
  F.place(f,1,-5000,0); learned(e,2,160); learned(e,3,170)
  local z2,z3,v2,v3=0,-9.4,160,170
  local s=e.states[2]; local start=e.time; local last,worst,followBrake=nil,0,0
  for _=1,6*60 do
   if yield then s.state='YIELD_HOLD'; s.target=3; s.targetSide=1; s.followers[3]=true; s.yieldStart=start; s.holdUntil=e.time+60; s.yieldDetection=100; s.yieldMargin=5 end
   local cap=e.commands[2].speedLimit or K.unlimitedSpeed
   if cap<K.unlimitedSpeed then
    if last then worst=math.max(worst,(last-cap)*60) end
    last=cap
   end
   v2=math.min(160,cap)
   if z2-z3<4.4+15 then v3=v3+math.max(-15/60,math.min(15/60,v2-v3)) end
   z2=z2+v2/3.6/60; z3=math.min(z3+v3/3.6/60,z2-4.9)
   F.place(f,2,z2,v2); F.place(f,3,z3,v3)
   F.tick(e,f,1/60); followBrake=math.max(followBrake,e.states[3].radarBrake or 0)
  end
  return e,f,s,last,worst,followBrake,z2
 end
 local _,_,_,_,_,alone=run(false)
 local e,f,s,last,worst,followBrake,z2=run(true)
 assert(last and last<160,'the yielding AI lifts')
 assert(worst<=K.yieldCapDecelOff+1e-6,'cap lowered at most at the K rate: '..worst..' km/h/s')
 assert(followBrake<=alone+0.05,'the lift adds no hard brake for the follower: '..followBrake..' (without the yield '..alone..')')
 -- Levée : suiveur parti, jamais sous la vitesse du moment, remontée bornée.
 local prev=e.commands[2].speedLimit; F.place(f,3,z2-400,170); local steps=0
 for _=1,4*60 do
  s.followers[3]=false; s.state='DRIVE'; F.tick(e,f,1/60)
  local cap=e.commands[2].speedLimit
  if cap<K.unlimitedSpeed then assert(cap>=f.cars[2].kmh-1e-6 and cap-math.max(prev,f.cars[2].kmh)<=K.yieldCapReleaseKmh/60+1e-6,'ramped release'); steps=steps+1 end
  prev=cap<K.unlimitedSpeed and cap or prev
 end
 assert(e.commands[2].speedLimit>=K.unlimitedSpeed and steps>0,'released in the end, not at once')
end
-- Beta 1.61 : suiveur collé = régulateur arrière de la 1.60, qui étale lui aussi chaque limite ; la descente douce
-- propre à la cession est vérifiée seule, suiveur hors de la portée du régulateur.
tests.YIELD_CAP_GENTLE_159T=function()
 yieldCapGentle()
 withK({rearCloseMin=0,rearCloseTime=0},yieldCapGentle)
end

return tests
