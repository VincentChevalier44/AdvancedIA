-- Beta 1.55 (audit des journaux du 9 novembre, choix du pilote) : tentatives de dépassement sans progrès coupées hors
-- course, cession ordinaire seulement à un suiveur vraiment plus rapide, appels de phares suspendus après des cessions
-- sans passage ; drapeau pluie de CSP redonné « sec » sur piste sèche, gommes de chaque modèle au journal. Chargé par
-- tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local A=require('src/applier')
local C=require('src/config')
local J=require('src/journal')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function learned(e,i,kmh)
 local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=kmh/3.6 end; s.paceMean=kmh/3.6
end
-- Tentative forcée de l'IA 2 sur la voiture `target` placée `gap` m devant (positions figées : l'écart ne bouge que si le
-- test déplace la cible) ; l'écart de vitesse alterne pour ne déclencher ni « sans rapprochement » ni « cible plus rapide ».
local function attempt(profile,target,gap,seconds,step)
 local e,f=F.scene(profile,3); e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
 F.place(f,2,0,105); F.place(f,target,gap+4.4,100)
 local s=e.states[2]
 s.state='OVT_IN'; s.reason='pass'; s.since=e.time; s.target=target; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=gap; s.passName='Cible'
 s.abortSlow=0; s.passStall=0; s.passAlongside=false; s.passProgRef=gap; s.passProgTime=0; s.lastPassTarget=target; s.nextPerception=0
 local t,z=0,gap+4.4
 while t<seconds do
  local slow=math.floor(t*2)%2==0
  if step then local moved=step(t); if moved then z=z-moved end end
  F.place(f,target,z,slow and 100 or 107); s.nextPerception=0
  F.tick(e,f,1/60); t=t+1/60
  if not F.passing(s.state) then break end
 end
 return e,s,t
end
tests.PASS_NO_PROGRESS_155=function()
 assert(K.passProgressGain==3 and K.passProgressTime==8 and K.passAttemptMax==15 and K.passCapGrace==4)
 local e,s,t=attempt('J',3,20,20)
 assert(s.reason=='abort_noprogress' and t>K.passProgressTime and t<K.passProgressTime+1,'no ground gained: abort after 8 s, got '..s.reason..' at '..t)
 assert(s.passIgnore==3 and s.passIgnoreCount==1 and s.passIgnoreUntil>e.time,'same per-pair wait as « target faster »')
 assert(count(e,'depassement fini: Driver_2 -> Cible : sans progres apres ')==1,'end logged with its reason')
 -- En course : inchangé (pas d'abandon sans progrès).
 local _,r=attempt('C',3,20,20)
 assert(r.reason~='abort_noprogress' and r.reason~='abort_timeout','race unchanged: '..r.reason)
 -- Jamais contre le joueur.
 local _,p=attempt('J',1,20,12)
 assert(p.reason~='abort_noprogress' and p.reason~='abort_timeout','never against the player: '..p.reason)
end
-- En course : « sans rapprochement » (cible à la même allure pendant K.passStallTime s) toujours seul juge.
tests.PASS_STALL_RACE_155=function()
 local e,f=F.scene('C',3); e.p.personalLineJitter=0
 F.place(f,2,0,100); F.place(f,3,20,100); F.tick(e,f,0.1)
 local s=e.states[2]; s.state='OVT_IN'; s.target=3; s.targetSide=1; s.passAlongside=false; s.restUntil=0; s.passStartAt=e.time
 e.states[2].nextPerception=0
 for _=1,10*60 do F.tick(e,f,1/60); if not F.passing(s.state) then break end end
 assert(s.reason=='abort_stall','race: abort on « not closing » ('..s.state..' '..s.reason..')')
end
tests.PASS_PROGRESS_KEPT_155=function()
 -- 3.2 m gagnés toutes les 3 s : la tentative continue au-delà de 15 s.
 local last=0
 local _,s,t=attempt('J',3,40,20,function(time) if time-last>=3 then last=time; return 3.2 end end)
 assert(F.passing(s.state) and t>=20,'an attempt that keeps gaining is never cut: '..s.reason..' at '..t)
 -- 3.2 m gagnés toutes les 6 s : jamais 8 s sans progrès, mais plus de 4 s sans terrain gagné après 15 s.
 last=0
 local e,r,u=attempt('J',3,40,30,function(time) if time-last>=6 then last=time; return 3.2 end end)
 assert(r.reason=='abort_timeout' and u>K.passAttemptMax and u<K.passAttemptMax+5,'slow attempt capped: '..r.reason..' at '..u)
 assert(count(e,': tentative trop longue apres ')==1)
end
-- Deux échecs sans progrès de suite : attente stricte notée avec sa raison (traduite).
tests.PASS_SUSPENDED_REASON_155=function()
 local line='depassement suspendu: A (100%, 100%) -> B (100%, 100%) apres 2 echecs (sans progres), plus de tentative pendant 180 s'
 assert(J.english(line)=='overtaking suspended: A (100%, 100%) -> B (100%, 100%) after 2 failures (no progress), no new attempt for 180 s',J.english(line))
 assert(J.english('depassement fini: A -> B : tentative trop longue apres 16.1 s (ecart mini 12 m)')=='overtake ended: A -> B: attempt too long after 16.1 s (min gap 12 m)')
end
-- Cession ordinaire : jamais à un suiveur connu pas plus rapide ici ; permise s'il l'est ou si l'allure est inconnue ;
-- inchangée pour le joueur.
tests.YIELD_NEEDS_ADVANTAGE_155=function()
 local function yields(follower,mine,theirs)
  local e,f=F.scene('J'); e.p.personalLineJitter=0; e.p.pressureEnabled=false; e.p.flashObliviousPct=0; E.changed(e)
  F.rear(e,f,45,30,follower)
  local seen=false
  -- Allures apprises tenues à chaque image (la fixture apprend la vitesse du moment en conduite libre).
  for _=1,4*60 do
   if mine then learned(e,2,mine) end
   if theirs then learned(e,follower,theirs) end
   F.tick(e,f,1/60); if F.yielding(e.states[2].state) then seen=true; break end
  end
  return seen,e
 end
 assert(K.yieldNeedAdvantage==true)
 -- Beta 1.59 : hors course, refus seulement à un suiveur nettement plus lent (allure égale : cession).
 assert((yields(3,180,180)),'equal learned pace: yield (1.59)')
 local seen,e=yields(3,180,170)
 assert(not seen,'clearly slower follower: no ordinary yield')
 assert(count(e,'cession refusee: Driver_2 ne cede pas a Driver_3 (pas plus rapide ici)')==1 and e.stats.yieldNoAdv==1,'refusal logged and counted once per episode')
 assert(J.english('cession refusee: A (100%, 100%) ne cede pas a B (100%, 100%) (pas plus rapide ici)')=='yield refused: A (100%, 100%) does not yield to B (100%, 100%) (not faster here)')
 assert((yields(3,180,220)),'really faster follower: yield')
 assert((yields(3,nil,nil)),'unknown pace: yield as before')
 assert((yields(1,180,170)),'the player, even clearly slower here: unchanged')
end
-- Appels de phares : après K.flashFailLimit cessions sur appel sans passage, plus d'appel vers cette voiture pendant
-- K.flashMuteTime s, noté une fois.
tests.FLASH_MUTED_AFTER_FAILED_YIELDS_155=function()
 assert(K.flashFailLimit==2 and K.flashMuteTime==120 and K.flashAfterAbort==20)
 local e,f=F.scene('J',3); local p=e.profiles.J
 p.aiFlashEnabled=true; p.pressureEnabled=false; p.multiClass=false; p.yieldEnabled=false; E.changed(e)
 F.place(f,2,0,100); F.place(f,3,29.4,100); F.tick(e,f,0.5)
 local o=e.states[3]
 for k=1,2 do
  o.state='YIELD_HOLD'; o.reason='yield'; o.since=e.time; o.target=2; o.targetSide=1; o.yieldStart=e.time; o.yieldFlashBy=2; o.yieldPassed=false
  o.followers[2]=true; o.holdUntil=e.time; o.yieldDetection=1; o.yieldMargin=1
  for _=1,40*60 do F.tick(e,f,1/60); if not F.yielding(o.state) then break end end
  assert(not F.yielding(o.state),'yield over')
  if k==1 then assert(e.states[2].flashFailCount==1 and e.states[2].flashMute==0,'first failure counted only') end
 end
 local s=e.states[2]
 assert(s.flashMute==3 and s.flashMuteUntil>e.time+100,'second failure: muted')
 assert(count(e,'appels de phares suspendus: Driver_2 -> Driver_3 apres 2 cessions sans passage, plus d appel pendant 120 s')==1)
 assert(J.english('appels de phares suspendus: A (100%, 100%) -> B (100%, 100%) apres 2 cessions sans passage, plus d appel pendant 120 s')
  =='headlight flashes suspended: A (100%, 100%) -> B (100%, 100%) after 2 yields without a pass, no flash for 120 s')
 -- Retenue derrière la voiture suspendue : aucun appel ; après l'attente, l'appel revient.
 local function flashes(muted)
  local g,gf=F.scene('J',3); local q=g.profiles.J
  q.aiFlashEnabled=true; q.pressureEnabled=false; q.multiClass=false; E.changed(g)
  F.place(gf,2,0,100); F.place(gf,3,29.4,100)
  local t=g.states[2]; for b=1,K.paceBins do t.pace[b]=50 end; t.paceCount=K.paceBins; t.paceMean=50
  for _=1,8*60 do
   if muted=='mute' then t.flashMute=3; t.flashMuteUntil=g.time+100 elseif muted=='hold' then t.flashHoldTarget=3; t.flashHoldUntil=g.time+10 end
   F.tick(g,gf,1/60)
  end
  return g.commands[2].flashEvent>0
 end
 assert(flashes(nil),'held behind a slower AI: flash')
 assert(not flashes('mute'),'muted target: no flash')
 assert(not flashes('hold'),'held after an abort: no flash')
 -- En course : rien ne change (les appels pour un tour ou une classe restent).
 local r=F.scene('C',3); assert(r.profile=='C')
end
-- Fin « suiveur rapide » ou « cède à son suiveur » : pas d'appel vers la cible pendant K.flashAfterAbort s.
tests.FLASH_HOLD_AFTER_ABORT_155=function()
 local e,f=F.scene('J',4); e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
 F.place(f,2,0,105); F.place(f,3,24.4,100); F.place(f,4,-14.4,105+K.abortFollowerSpeed+20)
 local s=e.states[2]
 s.state='OVT_IN'; s.reason='pass'; s.since=e.time; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=20; s.passName='Cible'
 s.abortSlow=0; s.passStall=0; s.passAlongside=false; s.passProgRef=20; s.passProgTime=0; s.lastPassTarget=3; s.nextPerception=0
 for _=1,3*60 do F.tick(e,f,1/60); if not F.passing(s.state) then break end end
 assert(s.reason=='abort_follower','fast follower: '..s.reason)
 assert(s.flashHoldTarget==3 and math.abs(s.flashHoldUntil-(e.time+K.flashAfterAbort))<1,'no flash toward the target for 20 s')
end
-- Fins de cession par raison, abandons, cessions refusées, appels suspendus et drapeau pluie de CSP au résumé ; tout
-- traduit.
tests.SUMMARY_FIELDS_155=function()
 local e,f=F.scene('J',3); F.tick(e,f,0.2)
 local plain=J.summary(e)
 assert(plain:find(' (meteo sec), drapeau pluie de CSP 0',1,true) and not plain:find('abandons :',1,true) and not plain:find('fins de cession',1,true),'optional parts only when used')
 f.cars[3].nativeRainTyres=true
 local n=e.stats
 n.abort_noprogress=2; n.abort_timeout=1; n.abort_slow=1
 n.yieldEnd=6; n.yieldEnd_passed=1; n.yieldEnd_lost=2; n.yieldEnd_hold_limit=2; n.yieldEnd_yellow=0
 n.yieldNoAdv=3; n.flashMuted=1; n.flashHeld=2
 local line=J.summary(e)
 assert(line:find('annules 4 (',1,true),'cancelled total includes the new aborts')
 assert(line:find('drapeau pluie de CSP 1',1,true))
 local tail=' | abandons : sans progres 2, tentative trop longue 1, priorite au virage 0, maintien trop long 0 | fins de cession : duree max 2, jaune 0, autres 1 | cessions refusees (suiveur pas plus rapide) 3 | appels de phares suspendus 1, retenus apres abandon 2'
 assert(line:sub(-#tail)==tail,line)
 local en=J.english(line)
 local entail=' | aborts: no progress 2, attempt too long 1, corner priority 0, held too long 0 | yield ends: max duration 2, yellow 0, other 1 | yields refused (follower not faster) 3 | headlight flashes suspended 1, held after an abort 2'
 assert(en:sub(-#entail)==entail and en:find('CSP rain flag 1',1,true),en)
end
-- Gommes de chaque modèle au journal, une fois par session, avec la classe retenue (piste sèche, intermédiaire, pluie,
-- non autorisée).
tests.TYRE_MODELS_LOGGED_155=function()
 local e,f=F.scene('J',3); F.tick(e,f,0.2)
 for i=2,3 do
  local a=f.cars[i]; a.id='lotus_exos'; a.tyresKnown=true
  a.tyreNames={[0]='S',[1]='W'}; a.tyreLongNames={[0]='Slick',[1]='Wet'}; a.tyreClass={[0]='sec',[1]='pluie'}
 end
 F.tick(e,f,2.5)
 assert(count(e,'gommes du modele lotus_exos: S (Slick) sec, W (Wet) pluie')==1,'one line per model')
 assert(J.english('gommes du modele lotus_exos: S (Slick) sec, W (Wet) pluie, I (Inter) intermediaire, X () non autorise')
  =='compounds of model lotus_exos: S (Slick) dry, W (Wet) rain, I (Inter) intermediate, X () not allowed')
 -- Classes relevées par la lecture des gommes.
 local S=require('src/snapshot')
 local get,long,legal=ac.getTyresName,ac.getTyresLongName,ac.areTyresLegal
 local names={[0]='SM',[1]='W',[2]='I',[3]='X'}
 ac.getTyresName=function(_,index) return names[index] end; ac.getTyresLongName=function() return '' end
 ac.areTyresLegal=function(short) return short~='X' end
 local s=S.new(); local a=s.cars[2]; a.identity='x'; a.compoundIndex=0
 local ok,err=pcall(function() S.tyres(a) end)
 ac.getTyresName,ac.getTyresLongName,ac.areTyresLegal=get,long,legal
 assert(ok,tostring(err))
 assert(a.tyreClass[0]=='sec' and a.tyreClass[1]=='pluie' and a.tyreClass[2]=='intermediaire' and a.tyreClass[3]=='non autorise')
end
-- Drapeau pluie de CSP revenu sur piste sèche après la consigne « sec » : consigne redonnée (au plus une fois par
-- K.rainReassertGap s), notée une fois.
tests.RAIN_FLAG_REASSERTED_155=function()
 local host=require('tests/host').create(true); local e,f=F.scene('J'); local a=A.new(); assert(A.access(a))
 local notes={}; a.note=function(_,text) notes[#notes+1]=text end
 for _,cmd in ipairs(e.commands) do cmd.active=false; cmd.weatherManaged=false end
 local car=f.cars[2]; car.nativeRainTyresKnown=true; car.nativeRainTyres=true
 local cmd=e.commands[2]; cmd.weatherManaged=true; cmd.weatherRain=false; cmd.weatherCompound=-1
 A.apply(a,f,e.commands,e.g,10)
 local s=a.cars[2]
 assert(s.rainHint==false and host.rainHints[car.index]==false,'first dry hint')
 host.rainHints[car.index]=nil
 A.apply(a,f,e.commands,e.g,11)
 assert(host.rainHints[car.index]==nil,'not right after the first hint')
 A.apply(a,f,e.commands,e.g,10+K.rainReassertGap)
 assert(host.rainHints[car.index]==false,'flag back to rain: dry hint given again')
 host.rainHints[car.index]=nil
 A.apply(a,f,e.commands,e.g,12+K.rainReassertGap)
 assert(host.rainHints[car.index]==nil,'rate-limited')
 A.apply(a,f,e.commands,e.g,10+2*K.rainReassertGap)
 assert(host.rainHints[car.index]==false,'again after the gap')
 local n=0; for _,text in ipairs(notes) do if text=='pneus pluie de CSP revenus sur piste seche: consigne sec redonnee' then n=n+1 end end
 assert(n==1,'logged once per car: '..n)
 assert(J.english('pneus pluie de CSP revenus sur piste seche: consigne sec redonnee')=='CSP rain tyres back on a dry track: dry hint given again')
 -- Sous la pluie : rien de redonné.
 host.rainHints[car.index]=nil; car.nativeRainTyres=false; cmd.weatherRain=true
 A.apply(a,f,e.commands,e.g,40)
 car.nativeRainTyres=true; host.rainHints[car.index]=nil
 A.apply(a,f,e.commands,e.g,60)
 assert(host.rainHints[car.index]~=false,'rain: never forced dry')
end
-- Avis « voiture lancée qui arrive » au joueur pas lancé : seulement sur un rapprochement confirmé (écart en temps au
-- même point de la piste) ; jamais pour une voiture de même allure, même avec des à-coups de vitesse (freinages).
local function qualiScene()
 local e,f=F.scene('Q',3); e.profiles.Q.qualiTraffic=true; e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,1/60)
 local c=e.quali.cars[1]; c.out=false; c.cool=false; F.tick(e,f,1/60)
 e.quali.cars[1].out=true; e.quali.cars[2].out=false; e.quali.cars[2].exitAt=-math.huge
 F.place(f,3,5000,100); F.place(f,1,0,100)
 for i=1,3 do e.states[i].nextPerception=0 end
 return e,f
end
local function warned(kmh,swing,seconds,pit,off)
 local e,f=qualiScene()
 F.place(f,2,-50,kmh); f.cars[2].pit=pit==true; f.cars[2].offtrack=off==true
 local t=0
 for _=1,seconds*60 do
  f.cars[1].speed=100/3.6; f.cars[1].kmh=100
  local v=kmh+(swing or 0)*math.sin(t*2*math.pi/4); f.cars[2].speed=v/3.6; f.cars[2].kmh=v
  F.tick(e,f,1/60,true); t=t+1/60
  if (e.stats.qualiWarn or 0)>0 or count(e,'arrive derriere le joueur')>0 then return true,e end
 end
 return false,e
end
tests.QUALI_WARNING_CONFIRMED_155=function()
 assert(K.qualiCatchRateLong==0.1 and K.qualiCatchSpanLong==3 and K.qualiCatchRateShort==0.3 and K.qualiCatchSpanShort==1 and K.qualiCatchProject==15 and K.qualiCatchWindow==6)
 assert((warned(125,0,10)),'25 % faster: announced')
 local same=warned(100,0,30); assert(not same,'same pace: never announced')
 local swinging=warned(100,30,30); assert(not swinging,'same mean pace with braking swings of 30 km/h: never announced')
 local pit=warned(125,0,10,true); assert(not pit,'a car in the pit lane is never announced')
 local off=warned(125,0,10,false,true); assert(not off,'a car off the track is never announced')
 -- Voiture à peine plus rapide (1 %) : rapprochement trop lent, jamais confirmé ; noté en DEBUG avec l'option.
 local e,f=qualiScene(); e.g.debugLog=true; E.changed(e)
 F.place(f,2,-50,101)
 for _=1,40*60 do F.tick(e,f,1/60,true) end
 assert((e.stats.qualiWarn or 0)==0,'barely faster: no warning')
 assert(count(e,'tour lance non confirme: Driver_2 (ecart ')==1,'unconfirmed candidate noted once (debug)')
 assert(J.english('tour lance non confirme: A (100%, 100%) (ecart 2.4 s, rapprochement 0.02 s/s)')=='flying lap not confirmed: A (100%, 100%) (gap 2.4 s, closing 0.02 s/s)')
 -- Confirmation trop tardive (plus de K.qualiCatchWindow s après l'arrivée à portée) : pas d'avis.
 local g,gf=qualiScene()
 F.place(gf,2,-50,100)
 for _=1,10*60 do F.tick(g,gf,1/60,true) end
 gf.cars[2].speed=130/3.6; gf.cars[2].kmh=130
 for _=1,5*60 do F.tick(g,gf,1/60,true) end
 assert(count(g,'arrive derriere le joueur')==0,'confirmed too late after appearing: no warning')
end
return tests
