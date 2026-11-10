-- Beta 1.51 (demandes du pilote, 9 novembre) : préréglage intégré de la session détectée, arrêt obligatoire oui ou non,
-- tours lancés en essais et qualifications (une IA sortie des stands forçait devant le joueur en tour rapide). Chargé par
-- tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Presets=require('src/presets')
local Quali=require('src/quali')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Scène de qualifications, tours lancés actifs : voiture 1 (joueur) lancée, les autres en tour de sortie.
local function quali(n,on)
 local e,f=F.scene('Q',n); e.profiles.Q.qualiTraffic=on~=false; e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,1/60)
 local c=e.quali.cars[1]; c.out=false; c.cool=false; F.tick(e,f,1/60)
 return e,f
end
tests.QUALI_PUSH_STATES_151=function()
 local e,f=quali(3)
 assert(e.quali.active and e.quali.push[1] and not e.quali.push[2] and not e.quali.push[3],'player pushing, AI on their out-lap')
 -- Ligne passée plus de qualiOutGrace s après la sortie : tour lancé.
 local c=e.quali.cars[2]; c.exitAt=e.time-K.qualiOutGrace-1
 local a=f.cars[2]; a.lap=a.lap+1; F.tick(e,f,1/60); assert(e.quali.push[2],'line crossed: flying lap')
 -- Sortie des stands, ligne juste après (moins de qualiOutGrace s) : le tour de sortie continue un tour de plus.
 a.pit=true; F.tick(e,f,1/60); assert(not e.quali.push[2],'pit lane: not pushing')
 a.pit=false; F.tick(e,f,1/60); a.lap=a.lap+1; F.tick(e,f,1/60); assert(not e.quali.push[2] and c.out,'line right after the pit exit: still the out-lap')
 -- Pas en essais ni qualifications, ou réglage coupé : personne n'est lancé.
 local e2,f2=quali(3,false); assert(not e2.quali.active and not e2.quali.push[1],'setting off: inactive')
 local e3,f3=F.scene('C',3); e3.profiles.C.qualiTraffic=true; E.changed(e3); F.tick(e3,f3,1/60); assert(not e3.quali.active,'never in the race')
 assert(C.hidden('C','qualiTraffic') and C.hidden('J','qualiTraffic') and not C.hidden('Q','qualiTraffic') and not C.hidden('P','qualiTraffic'),'shown in P and Q only')
 assert(C.defaults('Q').qualiTraffic and C.defaults('P').qualiTraffic and not C.defaults('C').qualiTraffic and not C.defaults('J').qualiTraffic,'defaults')
 assert(C.preset('Qualifications','Q',{}).qualiTraffic and C.preset('Essais','P',{}).qualiTraffic,'presets keep it on')
 local yieldOff=C.defaults('Q'); yieldOff.section_yield=false; assert(not C.effective('Q',yieldOff).qualiTraffic,'yield tab off: off')
end
tests.QUALI_COOL_LAP_151=function()
 local e,f=quali(3)
 -- Allure de la flotte connue (200 km/h partout), joueur à 100 km/h : refroidissement au bout de qualiCoolTime s.
 local reference=Quali.reference
 Quali.reference=function() return 200/3.6 end
 local ok,err=pcall(function()
  F.tick(e,f,K.qualiCoolTime-0.5); assert(not e.quali.cars[1].cool,'not yet')
  F.tick(e,f,0.7)
  assert(e.quali.cars[1].cool and not e.quali.push[1],'clearly slower than the reference: cool-down lap')
  local a=F.place(f,1,f.cars[1].z,190); a.lap=a.lap+1; F.tick(e,f,1/60)
  assert(not e.quali.cars[1].cool and e.quali.push[1],'line crossed at speed: pushing again')
  -- Retenu derrière une voiture lente (20 m devant) pendant 6 s : reste lancé.
  F.place(f,1,f.cars[1].z,100); F.place(f,3,f.cars[1].z+25,100); for i=1,3 do e.states[i].nextPerception=0 end
  F.tick(e,f,6); assert(e.quali.push[1] and not e.quali.cars[1].cool,'held behind a slow car: still pushing')
 end)
 Quali.reference=reference
 assert(ok,err)
end
-- Voiture 2 en tour de sortie à 100 km/h, voiture 3 juste devant elle (35 m, piste pas libre), joueur lancé qui arrive à
-- 2 s (+15 km/h). En 1.50, aucune cession (voiture devant à moins de followRange, suiveur pas assez rapide).
local function priority(on)
 local e,f=quali(4,on)
 F.place(f,4,5000,100); F.place(f,3,40,100); F.place(f,2,0,100); F.place(f,1,-60,115)
 for i=1,4 do e.states[i].nextPerception=0 end
 local yielded=false
 for _=1,120 do F.tick(e,f,1/60); if F.yielding(e.states[2].state) then yielded=true; break end end
 return yielded,e
end
tests.QUALI_PRIORITY_YIELD_151=function()
 local yielded,e=priority(true)
 assert(yielded and e.states[2].yieldQuali and e.states[2].yieldBlue,'out-lap car yields to the flying car, even with a car ahead')
 assert((e.stats.qualiYield or 0)>=1 and count(e,'en tour lance')>=1,'counted and logged')
 local old=priority(false)
 assert(not old,'setting off (1.50 behaviour): no yield with a car ahead')
end
tests.QUALI_NO_ATTACK_151=function()
 -- IA 2 en tour de sortie, plus rapide (+40 km/h), derrière le joueur lancé : pas d'attaque.
 local e,f=quali(3)
 F.place(f,3,5000,100); F.place(f,1,40,100); F.place(f,2,0,140)
 for i=1,3 do e.states[i].nextPerception=0 end
 local passed=false
 for _=1,90 do F.place(f,1,40,100); F.place(f,2,0,140); F.tick(e,f,1/60); if F.passing(e.states[2].state) then passed=true end end
 assert(not passed and (e.stats.qualiNoPass or 0)>=1,'never attacks a flying car')
 -- Joueur pas lancé (tour de sortie) : dépassement permis.
 local e2,f2=quali(3); e2.quali.cars[1].out=true
 F.place(f2,3,5000,100); F.place(f2,1,40,100); F.place(f2,2,0,140)
 for i=1,3 do e2.states[i].nextPerception=0 end
 local passed2=false
 for _=1,90 do F.place(f2,1,40,100); F.place(f2,2,0,140); F.tick(e2,f2,1/60); if F.passing(e2.states[2].state) then passed2=true end end
 assert(passed2,'player not pushing: the AI may pass')
end
tests.QUALI_PLAYER_WARNING_151=function()
 -- Beta 1.55 : avis seulement sur un rapprochement confirmé (écart en temps au même point de la piste) : voitures en
 -- mouvement, l'IA lancée 30 % plus rapide que le joueur.
 local e,f=quali(3); e.quali.cars[1].out=true; e.quali.cars[2].out=false; e.quali.cars[2].exitAt=-math.huge
 F.place(f,3,5000,100); F.place(f,1,0,100); F.place(f,2,-60,130)
 for i=1,3 do e.states[i].nextPerception=0 end
 F.tick(e,f,0.2,true)
 assert(e.quali.push[2] and not e.quali.push[1],'AI pushing, player on the out-lap')
 for _=1,4*60 do F.tick(e,f,1/60,true); if e.incidents.messageKind=='fastCar' then break end end
 assert(e.incidents.messageKind=='fastCar' and e.incidents.messageText=='Driver_2' and e.incidents.messageValue<=3,'player warned: '..tostring(e.incidents.messageKind))
 local id=e.incidents.messageId
 F.tick(e,f,1,true); assert(e.incidents.messageId==id and (e.stats.qualiWarn or 0)==1,'once per car within qualiWarnRepeat s')
 assert(count(e,'arrive derriere le joueur')==1,'logged once')
end
tests.QUALI_PIT_EXIT_HOLD_151=function()
 local e,f=quali(4); f.length=10000
 F.place(f,1,8000,100); F.place(f,2,6000,100); F.place(f,4,9000,0); f.cars[4].pit=true; f.cars[4].inPitBox=true
 local a3=F.place(f,3,1900,60); a3.pit=true
 F.tick(e,f,6); F.place(f,3,2000,60); a3.pit=false; F.tick(e,f,1/60)
 assert(e.merge.spline>=0,'merge point learned')
 F.place(f,3,5000,100)
 local a4=f.cars[4]; a4.inPitBox=false; F.place(f,4,1960,50); F.tick(e,f,0.1)
 -- Voiture 2 en tour de sortie qui arrive : pas de retenue en qualifications.
 F.place(f,2,1850,200); F.tick(e,f,1/60)
 assert(not e.commands[4].mergeHold,'out-lap car arriving: not held')
 -- Voiture 2 lancée : retenue.
 e.quali.cars[2].out=false; e.quali.cars[2].cool=false
 F.place(f,4,1700,0); a4.inPitBox=true; F.tick(e,f,1/60); a4.inPitBox=false; F.place(f,4,1960,50); F.place(f,2,1850,200); F.tick(e,f,1/60)
 assert(e.quali.push[2] and e.commands[4].mergeHold and count(e,'en tour lance')>=1,'flying car arriving: held')
 F.place(f,2,2100,200); F.tick(e,f,1/60); assert(not e.commands[4].mergeHold,'released once past')
end
tests.SESSION_PRESET_151=function()
 local function scene(kind,track)
  local e,f=F.scene('J'); e.g.presetBySession=true; e.g.autoProfile=true; f.configType=kind; f.track=track or 'test'
  return e,f
 end
 -- Qualifications : préréglage appliqué et allumé, règles du week-end gardées.
 local e,f=scene(2)
 C.applyRules('F1',e.profiles); local stops,sc=e.profiles.Q.mandatoryStops,e.profiles.Q.neutralization
 e.profiles.Q.levelPct=60
 E.step(e,f,1/60)
 local q=e.profiles.Q
 assert(e.profile=='Q' and C.mark(e.g,'Q')=='Qualifications' and e.g.loadedPreset=='builtin:Qualifications' and q.levelPct~=60,'qualifying preset applied and lit')
 assert(q.mandatoryStops==stops and q.neutralization==sc and C.ruleCategory('Q',q,C.switchKeys)=='F1','weekend rules kept')
 assert(e.presetSession=='test#0#Q' and e.presetSessionDirty and count(e,'preset_session: Qualifications')==1,'session key, logged')
 local candidate=C.preset('Qualifications','Q',{})
 assert(Presets.signature('Q',q,{},nil,C.presetMatchSkip)==Presets.signature('Q',candidate,{},nil,C.presetMatchSkip),'tile lit despite F1 rules')
 -- Retouche du pilote pendant la session : gardée (une fois par session) ; rechargement de l'app : rien.
 q.levelPct=61; E.changed(e); E.step(e,f,1/60); assert(q.levelPct==61,'once per session')
 local e2,f2=scene(2); e2.presetSession='test#0#Q'; e2.profiles.Q.levelPct=62; E.step(e2,f2,1/60); assert(e2.profiles.Q.levelPct==62,'app reloaded in the same launch: nothing')
 -- Nouvelle session (course) : préréglage de la course ; Endurance choisi pour la course : gardé.
 f.session=1; f.configType=3; f.type=3; E.step(e,f,1/60); assert(e.profile=='C' and C.mark(e.g,'C')=='Course','race preset')
 C.setMark(e.g,'C','Endurance'); f.session=2; E.step(e,f,1/60); assert(C.mark(e.g,'C')=='Endurance' and e.profiles.C.enduranceOverlay,'Endurance kept for the race')
 -- Préréglage personnel chargé : jamais remplacé.
 C.setMark(e.g,'C',C.personalMark); e.profiles.C.levelPct=70; f.session=3; E.step(e,f,1/60); assert(e.profiles.C.levelPct==70 and count(e,'preset personnel garde')==1,'personal preset kept')
 -- Journée circuit sur la Nordschleife : Nordschleife Touristenfahrten, noté au journal.
 local e3,f3=scene(1,'ks_nordschleife'); f3.configTrackDay=true; E.step(e3,f3,1/60)
 assert(e3.profile=='J' and C.mark(e3.g,'J')=='Nordschleife' and count(e3,'circuit Nordschleife')==1,'Nordschleife track day')
 -- Détection en retard : journée circuit à la première image, qualifications à la suivante : Qualifications pour Q.
 local e7,f7=scene(nil); f7.configType=-1; f7.type=1; E.step(e7,f7,1/60); assert(e7.profile=='J' and C.mark(e7.g,'J')=='Circuit','first frame: track day (1.59: Journée circuit off the Nordschleife)')
 f7.configType=2; f7.type=2; E.step(e7,f7,1/60); assert(e7.profile=='Q' and C.mark(e7.g,'Q')=='Qualifications','late detection: qualifying preset')
 -- Hotlap : aucun ; réglage coupé : ancienne règle (profil jamais réglé seulement, aucune tuile).
 local e4,f4=scene(4); e4.profiles.H=C.defaults('H'); E.step(e4,f4,1/60); assert(e4.profile=='H' and C.mark(e4.g,'H')=='','hotlap: none')
 local e5,f5=scene(2); e5.g.presetBySession=false; e5.profiles.Q.levelPct=60; E.step(e5,f5,1/60); assert(e5.profiles.Q.levelPct==60 and C.mark(e5.g,'Q')=='','off: nothing')
 -- Profil manuel : rien.
 local e6,f6=scene(2); e6.g.autoProfile=false; e6.g.manualProfile='Q'; e6.profiles.Q.levelPct=60; E.step(e6,f6,1/60); assert(e6.profiles.Q.levelPct==60,'manual profile: nothing')
end
-- Tours de refroidissement des IA (qualifications) : après sa série de tours lancés, l'IA fait un tour au niveau abaissé,
-- n'est plus lancée (elle cède aux voitures lancées), puis repart ; jamais en essais, jamais pour le joueur, jamais en fin
-- de séance.
tests.QUALI_AI_COOL_LAPS_151=function()
 local Q=require('src/quali')
 local function run(profile,left)
  local e,f=F.scene(profile,3); e.profiles[profile].qualiTraffic=true; e.profiles[profile].qualiCoolLaps=true; E.changed(e)
  f.left=left or 0; F.tick(e,f,1/60)
  local c=e.quali.cars[2]; c.out=false; c.cool=false; F.tick(e,f,1/60)
  assert(e.quali.push[2],'AI 2 pushing')
  local n=Q.target(e.runtimeG.seed,2); assert(n>=K.qualiPushMin and n<=K.qualiPushMax,'target drawn in range')
  local a=f.cars[2]
  for _=1,n do a.lap=a.lap+1; F.tick(e,f,1/60) end
  return e,f,c,a
 end
 local e,f,c,a=run('Q')
 assert(c.cool and c.planned and not e.quali.push[2] and (e.stats.qualiCool or 0)==1,'cool-down lap after the flying laps')
 F.tick(e,f,K.qualiCoolRamp+0.1)
 assert(math.abs(e.commands[2].levelScale-(1-K.qualiCoolLevel))<1e-6,'level lowered: '..e.commands[2].levelScale)
 a.lap=a.lap+1; F.tick(e,f,1/60)
 assert(not c.cool and e.quali.push[2] and e.commands[2].levelScale<1,'line: pushing again, level coming back')
 F.tick(e,f,K.qualiCoolRelease+0.1); assert(e.commands[2].levelScale==1,'level back')
 -- Joueur : jamais de refroidissement prévu.
 local pc=e.quali.cars[1]; assert(not pc.planned,'never for the player')
 -- Essais : jamais ; fin de séance (moins de qualiCoolLate tours) : jamais.
 local e2,f2,c2=run('P'); assert(not c2.planned and e2.quali.push[2],'never in practice')
 local e3,f3,c3=run('Q',100); assert(not c3.planned and e3.quali.push[2],'not at the end of the session')
 assert(C.hidden('P','qualiCoolLaps') and not C.hidden('Q','qualiCoolLaps') and C.defaults('Q').qualiCoolLaps,'qualifying only, on by default')
end
-- Scène animée de qualifications (20 min, 20 IA, rythmes variés, passages aux stands, joueur qui ralentit un tour sur
-- trois) avec le préréglage de la session et les tours lancés actifs : le nouveau code tourne vraiment (sans erreur),
-- cessions prioritaires et refroidissements observés.
tests.QUALI_SOAK_151=function()
 local W=require('tests/workload')
 local e,f=F.scene('Q',21); e.g.presetBySession=true; e.profiles.Q.qualiTraffic=true
 f.length=math.pi*2000; f.commands=e.commands
 for i=1,f.count do local a=f.cars[i]; a.distance=(i-1)*f.length/f.count; a.pace=90+(i%5)*20; a.lap=0 end
 E.step(e,f,1/30)
 local dt=1/30; local yields,cools,pushes,planned=0,0,0,0
 for n=1,20*60*30 do
  local t=n*dt
  W.animate(f,t,dt)
  local pl=f.cars[1]; pl.pit=false; if pl.lap%3==2 then pl.kmh=40; pl.speed=40/3.6 end
  E.step(e,f,dt)
  assert(e.errors==0,'no car error')
  for i=2,f.count do if e.states[i].yieldQuali and F.yielding(e.states[i].state) then yields=yields+1 end end
  if e.quali.cars[1].cool then cools=cools+1 end
  if e.quali.push[2] then pushes=pushes+1 end
  for i=2,f.count do if e.quali.cars[i].planned then planned=planned+1 end end
 end
 assert(e.profile=='Q' and C.mark(e.g,'Q')=='Qualifications','session preset applied')
 assert(e.quali.active and pushes>0 and yields>0 and cools>0 and planned>0,'flying laps, cool-down laps (player, AI) and priority yields happen: '..pushes..' / '..cools..' / '..planned..' / '..yields)
end
return tests
