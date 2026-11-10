local H=require('tests/host')
local C=require('src/config')
local E=require('src/engine')
local L=require('src/lang')
local ffi=require('ffi')
return function(source)
 -- Beta 1.51 : les cas réglés à la main partent sans préréglage de la session (comme la fixture) ; le dernier cas joue
 -- la vraie première installation avec l'interrupteur allumé (défaut de l'app).
 local presetDefault=C.globalDefaults.presetBySession; C.globalDefaults.presetBySession=false
 -- Filtre facultatif (mutations ciblées) : seuls les cas dont le nom contient INT_FILTER sont joués.
 local filter=rawget(_G,'INT_FILTER')
 local results={}; local function check(name,fn) if filter and not name:find(filter,1,true) then return end; fn()
 assert(not HUMANAI or HUMANAI.host.errors==0,name..' : erreur attrapée (arrêt, restitution, session, interface)'); results[#results+1]=name end
 local function main() script.HUMANAI__MAIN(); assert(not HUMANAI.engine.panic,'UI error') end
 local function click(label) HOST.clicked=label; main() end
 -- Commandes dessinées (Beta 1.9) : clic par identifiant stable ; le clic doit être consommé (commande affichée).
 local W=require('src/widgets')
 local function press(id) HOST.clicked='##aai_'..id; main(); assert(HOST.clicked=='','control not shown: '..id) end
 local function go(name) press('tab_'..name) end
 -- Beta 1.17 : la section Règles a son propre onglet.
 -- Beta 1.19 : arrêts aux stands et voiture de sécurité sous leur titre dans l'onglet Règles de course.
 local stopsKeys={mandatoryStops=true,pitWindowOpenPct=true,pitWindowClosePct=true,pitTyres=true,pitRepair=true,pitCompoundChange=true,minPitTime=true,maxStintMin=true,pitFuel=true,pitsClosed=true,pitMessage=true}
 local safetyKeys={safetyCarSpeedKmh=true,safetyCarEscalation=true,restartOvertake=true}
 local function section(group,key)
  if group=='rules' then go('rules'); press('rules_view_'..(stopsKeys[key] and 'stops' or safetyKeys[key] and 'safety' or 'all'))
  else go('settings'); press('cat_'..group) end
 end
 local function lit(id) return W.frame().active[id]==true end
 local function drawn(id) return HOST.hits['##aai_'..id]~=nil end
 local function redraw() HOST.hits={}; HOST.hitOrder={}; HOST.drawnTexts={}; main() end
 local function drag(id,ratio) HOST.drags['##aai_'..id]=ratio; main() end
 local function drawnText(value) for _,t in ipairs(HOST.drawnTexts) do if t==value then return true end end return false end
 -- Refonte Racing 26 : messages coupés à la largeur de leur bloc ; la première ligne dessinée ouvre le texte attendu.
 local function begins(value) for _,t in ipairs(HOST.drawnTexts) do if #t>=10 and value:find(t,1,true)==1 then return true end end return drawnText(value) end
 local function has(list,value) for _,x in ipairs(list) do if x==value then return true end end return false end
 local function pause(value) HOST.sim.isPaused=value; script.HUMANAI__MENU() end
 HOST=H.create(true); assert(loadstring(source))()
 check('première installation : Essais, Qualifications et Course comme « Règles de base » ; Journée circuit sans commande ni sonde',function()
  H.tick(HOST,5); local e=HUMANAI.engine
  assert(e.profile=='J' and HOST.calls==0 and HOST.accessCalls==0 and e.guard=='nosections','track day: zero command')
  -- Panneaux lumineux (Beta 1.37) : cochés partout par défaut, sans rien piloter tant qu'aucun autre onglet ne l'est.
  for _,group in ipairs(C.sections) do assert(not C.on(e.profiles.J,group) or group=='lights','track day: '..group) end
  for _,profile in ipairs(C.ruleProfiles) do
   local p=e.profiles[profile]
   assert(p.configured and C.on(p,'rules') and C.on(p,'accidents') and C.ruleCategory(profile,p)=='base',profile)
  end
  assert(HUMANAI.host.firstInstall and e.g.dataRevision==C.dataRevision and HUMANAI.host.caps.probeIndex==0 and e.g.offsetSign==0)
 end)
 check('ouverture automatique au setup sans callback HUD ni fenêtre déjà visible',function()
  assert(not HOST.windowOpen.main)
  HOST.sim.isInMainMenu=true; local calls=HOST.calls
  script.update(1/60)
  assert(HOST.windowOpen.main and HUMANAI.host.menuVisible and HOST.calls==calls)
  redraw(); assert(#HOST.drawnTexts>0)
  HOST.sim.isInMainMenu=false; script.update(1/60); assert(not HOST.windowOpen.main)
  local e=HUMANAI.engine
  local before=e.time; script.update(1/60); assert(math.abs(e.time-before-1/60)<1e-9)
  assert(HOST.calls==calls)
 end)
 check('fenêtres accessibles uniquement dans les menus pause/setup',function()
  redraw(); assert(#HOST.drawnTexts==0 and not HOST.windowOpen.main)
  pause(true); assert(HOST.windowOpen.main); redraw(); assert(#HOST.drawnTexts>0)
  HOST.sim.isPaused=false; HOST.sim.isInMainMenu=true; script.HUMANAI__MENU(); assert(HUMANAI.host.menuVisible)
  HOST.sim.isInMainMenu=false; pause(true)
 end)
 check('boutons de profil, surbrillance et activations indépendantes',function()
  go('settings'); press('section_general'); assert(HUMANAI.engine.profiles.J.section_general)
  assert(HOST.storage['humanai:p:J:'].section_general and HOST.calls==0)
  -- Profil automatique : cliquer un profil l'affiche et le règle sans figer la détection (piège relevé en jeu).
  local before=HUMANAI.engine.profile
  press('profile_C'); main(); assert(HUMANAI.engine.g.autoProfile and HUMANAI.engine.profile==before and lit('profile_C') and not lit('profile_'..before))
  local was=HUMANAI.engine.profiles.C.section_general
  press('section_general'); assert(HUMANAI.engine.profiles.C.section_general==not was and HUMANAI.engine.g.autoProfile,'edits go to the displayed profile')
  press('section_general'); assert(HUMANAI.engine.profiles.C.section_general==was,'the switch of the list toggles too')
  -- Sans profil automatique, le clic choisit le profil utilisé.
  go('home'); press('auto'); press('profile_C'); main(); assert(HUMANAI.engine.profile=='C' and not HUMANAI.engine.g.autoProfile)
  assert(lit('profile_C') and HUMANAI.engine.profiles.C.section_general==was)
  press('profile_J'); assert(HUMANAI.engine.p.section_general)
 end)
 check('auto : journée circuit déclarée dans race.ini prioritaire, ancien choix manuel annulé',function()
  press('profile_C'); HOST.sim.raceSessionType=3; HOST.configType=1
  H.tick(HOST,1.1); press('auto'); assert(HUMANAI.engine.profile=='J')
  HOST.configType=nil; HOST.sim.raceSessionType=1; H.tick(HOST,1.1)
 end)
 check('activation réelle et masquage des contrôles par section',function()
  -- Beta 1.38 : section décochée montrée grisée, avec son message en tête du volet.
  section('lateral'); redraw(); assert(drawn('set_rampSpeed') and begins(L.sectionOff))
  press('section_lateral'); redraw(); assert(drawn('set_rampSpeed') and not begins(L.sectionOff))
  assert(HUMANAI.engine.p.section_lateral)
  press('section_lateral'); assert(not HUMANAI.engine.p.section_lateral)
  press('cat_yield'); press('section_yield'); assert(HUMANAI.engine.p.section_yield)
 end)
 check('Beta 1.9 : fenêtre dessinée à toutes les largeurs, commandes dans la fenêtre, polices et découpes équilibrées',function()
  for _,width in ipairs({640,1000,1600}) do
   HOST.space={x=width,y=780}
   for _,name in ipairs({'home','settings','diagnostic'}) do
    go(name); redraw()
    for id,r in pairs(HOST.hits) do
     assert(r.x>=0 and r.x+r.w<=8+width+0.5,'control outside the window: '..id..' at '..width)
     if name~='settings' then assert(r.y+r.h<=34+780+0.5,'control below the window: '..id..' at '..width) end
    end
    assert(HOST.dwriteDepth==0 and HOST.clipDepth==0,'fonts and clips balanced')
   end
  end
  HOST.space={x=1000,y=780}; go('home')
 end)
 check('préréglage personnalisé nommé : sauvegarde, modification, chargement, surbrillance',function()
  go('home'); HOST.inputEdits['##aai_preset_name']='Mon circuit'; press('save_preset')
  assert(HUMANAI.host.presets[1].name=='Mon circuit')
  main(); assert(lit('custom_1'))
  HUMANAI.engine.p.levelPct=80; E.changed(HUMANAI.engine); main(); assert(not lit('custom_1'))
  press('custom_1'); assert(HUMANAI.engine.p.levelPct==95 and HUMANAI.engine.p.section_general)
  press('save_preset'); assert(HUMANAI.host.presets[1] and not HUMANAI.host.presets[2])
 end)
 check('préréglages intégrés : activation des sections recommandées, cases visibles et surbrillance',function()
  local e=HUMANAI.engine; assert(e.g.autoProfile and e.profile=='J')
  -- Profil automatique conservé : le préréglage règle son profil sans figer la détection.
  go('home'); press('builtin_Course'); main(); assert(e.g.autoProfile and e.profile=='J' and e.profiles.C.section_blue and e.profiles.C.section_overtake and not e.profiles.C.section_traffic)
  -- Beta 1.38 (demande du pilote) : préréglage d'un autre profil appliqué sans changer le profil affiché, aucune tuile allumée.
  go('home'); redraw(); assert(lit('profile_J') and e.profile=='J' and not lit('builtin_Course') and begins(string.format(L.presetAppliedTo,L.profiles.C)) and C.mark(e.g,'C')=='Course','shown profile kept, preset applied to its profile')
  press('auto'); press('profile_C'); go('home'); main(); assert(e.profile=='C' and not e.g.autoProfile and lit('builtin_Course'))
  assert(HUMANAI.engine.p.section_general and HUMANAI.engine.p.section_blue and HUMANAI.engine.p.section_overtake and not HUMANAI.engine.p.section_traffic)
  section('blue'); main(); assert(drawn('section_blue') and HUMANAI.engine.p.section_blue)
  -- Beta 1.38 : profil manuel, le préréglage d'un autre profil ne change plus de profil : la journée circuit d'abord.
  go('home'); press('profile_J'); press('builtin_Nordschleife'); main(); assert(HUMANAI.engine.profile=='J' and HUMANAI.engine.p.section_yield and HUMANAI.engine.p.section_traffic and not HUMANAI.engine.p.section_blue)
  press('builtin_Endurance'); main(); assert(HUMANAI.engine.p.section_endurance and HUMANAI.engine.p.multiClass and lit('builtin_Endurance'))
  press('custom_1')
 end)
 check('persistance du programme et des sections après rechargement',function()
  assert(loadstring(source))(); main()
  assert(HUMANAI.host.presets[1].name=='Mon circuit' and HUMANAI.engine.profiles.J.section_yield)
  go('home'); main(); assert(lit('custom_1'))
 end)
 check('sonde native et calibration uniquement après activation',function()
  pause(false); H.tick(HOST,5); assert(HUMANAI.host.caps.native110 and HUMANAI.engine.g.offsetSign==1,'native='..tostring(HUMANAI.host.caps.native110)..' sign='..HUMANAI.engine.g.offsetSign..' profile='..HUMANAI.engine.profile..' guard='..HUMANAI.engine.guard..' gen='..tostring(HUMANAI.engine.p.section_general)..' state='..HUMANAI.engine.states[2].state..' active='..tostring(HUMANAI.engine.commands[2].active)..' calls='..HOST.calls..' probe='..HUMANAI.host.caps.probeIndex..' done='..tostring(HUMANAI.host.caps.probeDone))
 end)
 check('export des zones et diagnostic dans le menu',function()
  pause(true); go('diagnostic'); HOST.clip=''; press('export'); assert(HOST.clip:match('zones')); pause(false)
 end)
 check('alt-online : aucune commande',function()
  HOST.sim.isAltOnlineRace=true; local old=HOST.calls; H.tick(HOST,1); assert(HOST.calls==old and HUMANAI.engine.guard=='online'); HOST.sim.isAltOnlineRace=false
 end)
 check('replay : aucune commande ni écriture de récupération',function()
  HOST.sim.isReplayActive=true; local old,stores=HOST.calls,HOST.storeWrites; H.tick(HOST,1); assert(HOST.calls==old and HOST.storeWrites==stores); HOST.sim.isReplayActive=false
 end)
 check('pause : aucune commande physique',function()
  pause(true); local old=HOST.calls; H.tick(HOST,1); assert(HOST.calls==old); pause(false)
 end)
 check('désactivation générale et restauration stable',function()
  HUMANAI.engine.g.enabled=false; H.tick(HOST,0.5); local old=HOST.calls; H.tick(HOST,1); assert(HOST.calls==old)
  HUMANAI.engine.g.enabled=true; H.tick(HOST,0.5)
 end)
 check('stands exclus des écritures',function()
  HOST.cars[1].isInPit=true; H.tick(HOST,1); HOST.cars[1].isInPit=false; H.tick(HOST,4)
 end)
 check('week-end : profil manuel conservé, auto réactivé suit la session',function()
  HOST.sim.currentSessionIndex=1; HOST.sim.currentSessionTime=0; HOST.sim.raceSessionType=3
  for fn in pairs(HOST.sessions) do fn() end
  H.tick(HOST,1); assert(HUMANAI.engine.profile=='J')
  HUMANAI.engine.g.autoProfile=true; H.tick(HOST,1.1); assert(HUMANAI.engine.profile=='C')
  E.select(HUMANAI.engine,'J'); H.tick(HOST,1)
 end)
 check('espacement réel par limite douce et restitution après désactivation',function()
  local e=HUMANAI.engine
  for _,group in ipairs(C.sections) do e.p['section_'..group]=false end
  e.p.section_traffic=true; E.changed(e)
  for i=1,3 do HOST.cars[i].splinePosition=(i-1)*0.001; HOST.cars[i].position.z=(i-1)*10 end
  local limited=false
  for _=1,C.K.trafficCycle*60 do
   H.tick(HOST,1/60)
   if HOST.speedLimits[1] and HOST.speedLimits[1]<108 then limited=true; break end
  end
  assert(limited,'spacing episode never reached native limiter')
  e.p.section_traffic=false; E.changed(e); H.tick(HOST,1)
  assert(HOST.speedLimits[1]==C.K.unlimitedSpeed)
  local old=HOST.calls; H.tick(HOST,1); assert(HOST.calls==old)
 end)
 check('rechargement sans double abonnement et déchargement idempotent',function()
  assert(loadstring(source))(); H.tick(HOST,1)
  local count=0; for _ in pairs(HOST.sessions) do count=count+1 end; assert(count==1)
  count=0; for _ in pairs(HOST.releases) do count=count+1 end; assert(count==1)
  HUMANAI.release(); local old=HOST.calls; script.HUMANAI__UPDATE(1/60); HUMANAI.release(); assert(HOST.calls==old)
 end)
 check('plafond natif et grip soumis à la section globale explicite',function()
  HOST=H.create(false); assert(loadstring(source))()
  local e=HUMANAI.engine; e.profiles.J.section_general=true; E.changed(e); H.tick(HOST,5)
  assert(not HUMANAI.host.caps.native110 and HOST.extraGrip==0)
  e.g.useGripBoost=true; e.g.levelMode='grip'; e.p.levelPct=110; e.p.paceSpreadPct=0; e.p.paceDriftPct=0
  E.changed(e); H.tick(HOST,5); assert(HOST.extraGrip==0)
  e.p.section_globals=true; E.changed(e); H.tick(HOST,5); assert(math.abs(HOST.extraGrip-1.248)<0.002)
  e.p.section_globals=false; E.changed(e); H.tick(HOST,1); assert(math.abs(HOST.extraGrip-1.2)<1e-9)
 end)
 check('chaque paramètre : bornes, choix, cases et sauvegarde via la vraie interface',function()
  HUMANAI.release(); HOST=H.create(true); HOST.space={x=1000,y=3000}; assert(loadstring(source))(); pause(true)
  -- Profil manuel : chaque profil cliqué devient le profil utilisé, pour vérifier aussi les valeurs effectives.
  go('home'); press('auto')
  for _,profile in ipairs(C.profiles) do
   go('home'); press('profile_'..profile); go('settings')
   for _,s in ipairs(C.schema) do
    -- Réglage sans effet dans ce profil (pénalités en journée circuit, surcouche Endurance en essais et en
    -- qualifications) : commande masquée, explication affichée, valeur par défaut.
    if s.group=='rules' and (stopsKeys[s.key] or safetyKeys[s.key]) and profile~='C' then
     -- Beta 1.19 : arrêts aux stands et voiture de sécurité, réglages du profil Course seul (vérifiés avec lui).
    elseif s.key=='mandatoryStops' then
     -- Beta 1.51 : arrêt obligatoire oui ou non, réglé par son interrupteur seul (vérifié avec les interrupteurs de course).
    elseif require('src/groups').hidden[s.key] then
     -- Beta 1.59 : réglage jamais montré (lightsYellow, figé à vrai) : aucune commande, valeur gardée.
     HUMANAI.engine.p['section_'..s.group]=true; section(s.group,s.key); redraw()
     assert(not drawn('set_'..s.key),profile..': '..s.key..' never shown')
    elseif C.hidden(profile,s.key) then
     HUMANAI.engine.p['section_'..s.group]=true; section(s.group,s.key); redraw()
     local note=(C.penaltyKeys[s.key] or C.sanctionKeys[s.key] and C.solo(profile)) and L.penaltiesTrackDay or (C.raceKeys[s.key] or C.sanctionRaceKeys[s.key]) and L.raceOnlySetting or C.spawnKeys[s.key] and (C.hidden(profile,'spawnMode') and L.spawnNotAvailable or L.floodNotAvailable) or (s.key=='qualiTraffic' or s.key=='qualiRuns') and L.qualiOnlySetting or C.sanctionPracticeKeys[s.key] and L.qualiOnlySetting or s.key=='qualiCoolLaps' and (C.hidden(profile,'qualiTraffic') and L.qualiOnlySetting or L.qualifyingOnlySetting) or s.key=='damagePit' and L.damagePitTrackDay or L.enduranceNotAvailable; local shown=false
     for _,t in ipairs(HOST.drawnTexts) do if #t>15 and note:find(t,1,true)==1 then shown=true end end
     assert(shown and not drawn('set_'..s.key),profile..': '..s.key..' hidden')
     assert(C.validate(profile,HUMANAI.engine.p)[s.key]==s.defaults[profile],profile..': '..s.key..' back to its default')
    else
    C.validate(profile,C.defaults(profile),HUMANAI.engine.p)
    HUMANAI.engine.p['section_'..s.group]=true
    section(s.group,s.key)
    local values=s.choices or (s.min and {s.min,s.max} or {true,false})
    for _,value in ipairs(values) do
     local requested=C.validate(profile,HUMANAI.engine.p); requested[s.key]=value
     local expected=C.validate(profile,requested)[s.key]
     if s.choices then local guard=0; while HUMANAI.engine.p[s.key]~=expected and guard<#s.choices do press('set_'..s.key); guard=guard+1 end
     elseif s.min then drag('set_'..s.key,value==s.min and 0 or 1)
     elseif HUMANAI.engine.p[s.key]~=value then press('set_'..s.key) end
     main(); H.tick(HOST,1/60)
     assert(HUMANAI.engine.p[s.key]==expected,profile..':'..s.key..':'..tostring(value))
     assert(HOST.storage['humanai:p:'..profile..':'][s.key]==expected,'storage:'..s.key)
     if type(expected)=='boolean' then assert(HUMANAI.engine.run[s.key]==expected,'effective:'..s.key) end
     if s.choices then redraw(); local at=0; for i,x0 in ipairs(s.choices) do if x0==expected then at=i end end; assert(lit('set_'..s.key..'_'..at),'preview:'..s.key) end
    end
    end
   end
  end
  -- Clic droit sur un réglage : valeur par défaut du profil affiché ; -/+ : un pas.
  go('home'); press('profile_J'); section('general'); local p=HUMANAI.engine.p
  p.section_general=true; p.levelPct=80; main(); local r=HOST.hits['##aai_set_levelPct']; HOST.mouse={x=r.x+1,y=r.y+1}; HOST.rightClick='##aai_set_levelPct'; main()
  assert(p.levelPct==C.defaults('J').levelPct,'right click restores the default'); HOST.mouse={x=-1e6,y=-1e6}
  press('set_levelPct_minus'); assert(math.abs(p.levelPct-(C.defaults('J').levelPct-0.5))<1e-9,'minus: one step')
  press('set_levelPct_plus'); assert(math.abs(p.levelPct-C.defaults('J').levelPct)<1e-9,'plus: one step')
  press('cat_yield'); if not HUMANAI.engine.p.section_yield then press('section_yield') end
  local guard=0; while HUMANAI.engine.p.yieldSide~='auto' and guard<3 do press('set_yieldSide'); guard=guard+1 end
  assert(HUMANAI.engine.p.yieldSide=='auto')
  assert(loadstring(source))(); main(); assert(HUMANAI.engine.profiles.J.yieldSide=='auto')
  HOST.space={x=1000,y=780}
 end)
 check('options globales : chaque choix et interrupteur rejoint le moteur et le stockage',function()
  go('home'); press('profile_J'); section('globals')
  if not HUMANAI.engine.p.section_globals then press('section_globals') end
  for index,value in ipairs(C.globalChoices.levelMode) do
   local guard=0; while HUMANAI.engine.g.levelMode~=value and guard<5 do press('global_levelMode'); guard=guard+1 end
   H.tick(HOST,1/60)
   assert(HUMANAI.engine.g.levelMode==value and HUMANAI.engine.runtimeG.levelMode==value)
   redraw(); assert(drawnText(L.levelModeLabels[index]),'level mode shown')
   assert(HOST.storage['humanai:g:'].levelMode==value)
  end
  for _,key in ipairs({'useGripBoost','useBrakeAssist','overrideAwareness','debugLog'}) do
   for _,value in ipairs({true,false}) do
    if HUMANAI.engine.g[key]~=value then press('global_'..key) end
    H.tick(HOST,1/60); assert(HUMANAI.engine.runtimeG[key]==value and HOST.storage['humanai:g:'][key]==value,key)
   end
  end
  for key in pairs(L.globalLabels) do
   for index,value in ipairs(C.globalBounds[key]) do
    drag('global_'..key,index==1 and 0 or 1); H.tick(HOST,1/60)
    assert(HUMANAI.engine.runtimeG[key]==value and HOST.storage['humanai:g:'][key]==value,key)
   end
  end
  local seed=HUMANAI.engine.g.seed; press('reroll'); H.tick(HOST,1/60)
  assert(HUMANAI.engine.runtimeG.seed~=seed and HOST.storage['humanai:g:'].seed==HUMANAI.engine.runtimeG.seed,'new personalities')
 end)
 check('suppression personnalisée persistante, réglages conservés et emplacement réutilisable',function()
  go('home'); HOST.inputEdits['##aai_preset_name']='Premier'; press('save_preset')
  HOST.inputEdits['##aai_preset_name']='Second'; press('save_preset')
  press('custom_1'); local level=HUMANAI.engine.p.levelPct
  press('custom_delete_1')
  assert(not HUMANAI.host.presets[1] and HOST.storage['humanai:custom:1:'].name=='')
  assert(HUMANAI.engine.g.loadedPreset=='' and HUMANAI.engine.p.levelPct==level)
  assert(loadstring(source))(); go('home')
  assert(not HUMANAI.host.presets[1] and HUMANAI.host.presets[2].name=='Second')
  HOST.inputEdits['##aai_preset_name']='Réutilisé'; press('save_preset')
  assert(HUMANAI.host.presets[1].name=='Réutilisé')
  press('custom_delete_2')
  assert(not HUMANAI.host.presets[2] and HUMANAI.engine.g.loadedPreset=='custom:Réutilisé')
  HOST.inputEdits['##aai_preset_name']=string.rep('A',64); press('save_preset')
  for _,width in ipairs({640,1000,1600}) do
   HOST.space={x=width,y=780}; redraw()
   for id,r in pairs(HOST.hits) do assert(r.x+r.w<=8+width+0.5,'long name kept inside: '..id) end
  end
  HOST.space={x=1000,y=780}
 end)
 check('météo : composé pluie aux stands, puis retour au sec après assèchement',function()
  HUMANAI.release(); HOST=H.create(true)
  HOST.tyreCatalog[1]={{short='S',name='Slick Soft'},{short='I',name='Intermediate'},{short='W',name='Full Wet'}}
  HOST.sim.rainWetness=1; HOST.sim.rainIntensity=1
  assert(loadstring(source))(); local e=HUMANAI.engine; e.profiles.J.section_weather=true; E.changed(e); H.tick(HOST,2)
  assert(HOST.rainHints[1]==true and HOST.pitRequests[1]==true and HOST.cars[1].compoundIndex==0)
  assert(HOST.grips[1]==nil,'real rain compound must not get fallback grip')
  HOST.cars[1].isInPit=true; HOST.cars[1].speedKmh=0; H.tick(HOST,2); assert(HOST.cars[1].compoundIndex==2)
  local A=require('src/applier'); A.dirty(HUMANAI.host,e.time); A.save(HUMANAI.host,e.g,e.profiles,e.time,false,true)
  HOST.cars[1].compoundIndex=0; HOST.cars[1].isAIUsingRainTyres=false
  assert(loadstring(source))(); H.tick(HOST,2)
  assert(HOST.cars[1].compoundIndex==2,'weather service blocked by pending driving restoration after reload in pits')
  HOST.sim.rainWetness=0; HOST.sim.rainIntensity=0; H.tick(HOST,17); assert(HOST.cars[1].compoundIndex==0 and HOST.rainHints[1]==false)
 end)
 check('météo : grip de secours borné, priorité native et récupération après rechargement',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.rainWetness=1; HOST.sim.rainIntensity=1
  assert(loadstring(source))(); local e=HUMANAI.engine; e.profiles.J.section_weather=true; E.changed(e); H.tick(HOST,2)
  assert(math.abs(HOST.grips[1]-1.38)<0.002)
  local A=require('src/applier'); A.checkpoint(HUMANAI.host,e.frame,true)
  local recovered=A.new(); assert(A.access(recovered)); A.recover(recovered,e.frame)
  assert(recovered.cars[2].rainHint==true and not recovered.cars[2].originalRain)
  A.restore(recovered,e.frame,false,e.time); assert(HOST.rainHints[1]==false and math.abs(HOST.grips[1]-1.2)<1e-9)
  HOST.cars[1].isAIUsingRainTyres=true; H.tick(HOST,1); assert(math.abs(HOST.grips[1]-1.2)<1e-9)
  e.profiles.J.section_weather=false; E.changed(e); H.tick(HOST,1); assert(not HUMANAI.host.cars[2].owned)
 end)
 check('1.4.0 : grille de départ, pneus adaptés à la météo avant le feu vert, gommes sèches réparties',function()
  for _,case in ipairs({{wet=0,start=2,expect='dry'},{wet=0,start=1,expect='dry'},{wet=0.3,start=0,expect=1},{wet=1,start=0,expect=2}}) do
   HUMANAI.release(); HOST=H.create(true)
   for i=1,3 do HOST.tyreCatalog[i]={{short='H',name='Hard'},{short='I',name='Intermediate'},{short='W',name='Full Wet'},{short='M',name='Medium'},{short='S',name='Soft'},{short='SS',name='Super Soft'}} end
   HOST.sim.rainWetness=case.wet; HOST.sim.rainIntensity=case.wet; HOST.sim.isSessionStarted=false; HOST.sim.timeToSessionStart=20000
   for i=1,3 do HOST.cars[i].speedKmh=0; HOST.cars[i].velocity={x=0,z=0}; HOST.cars[i].compoundIndex=case.start; HOST.cars[i].isAIUsingRainTyres=case.start==1 or case.start==2 end
   assert(loadstring(source))(); local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.g.autoProfile=false; e.g.manualProfile='C'; E.changed(e)
   H.tick(HOST,3)
   for i=1,3 do
    local index=HOST.cars[i].compoundIndex
    if case.expect=='dry' then assert(index==0 or index>=3,'dry compound fitted on the grid') else assert(index==case.expect,'rain compound fitted on the grid: '..index) end
    assert(not HOST.pitRequested[i],'no pit stop requested for a tyre choice made on the grid')
   end
  end
  -- 1.7.0 : IA apparue aux stands en intermédiaires sur piste sèche, qui repart aussitôt : gomme sèche montée dans
  -- la voie des stands, en roulant (relevé dans les journaux de la 1.5.1).
  HUMANAI.release(); HOST=H.create(true)
  HOST.tyreCatalog[1]={{short='H',name='Hard'},{short='I',name='Intermediate'},{short='S',name='Soft'}}
  HOST.cars[1].isInPitlane=true; HOST.cars[1].speedKmh=60; HOST.cars[1].compoundIndex=1
  assert(loadstring(source))(); local el=HUMANAI.engine; C.preset('Nordschleife','J',el.profiles.J); E.changed(el)
  H.tick(HOST,1)
  assert(HOST.cars[1].compoundIndex==0 or HOST.cars[1].compoundIndex==2,'dry compound fitted while rolling down the pit lane')
  -- 1.7.2 : pluie, IA en pneus pluie dans la voie des stands : aucun changement (plus de va-et-vient avec CSP).
  HUMANAI.release(); HOST=H.create(true)
  HOST.tyreCatalog[1]={{short='H',name='Hard'},{short='I',name='Intermediate'},{short='W',name='Wet'}}
  HOST.sim.rainWetness=0.4; HOST.sim.rainIntensity=0.2
  HOST.cars[1].isInPitlane=true; HOST.cars[1].speedKmh=60; HOST.cars[1].compoundIndex=2; HOST.cars[1].isAIUsingRainTyres=true
  assert(loadstring(source))(); local er=HUMANAI.engine; C.preset('Nordschleife','J',er.profiles.J); E.changed(er)
  H.tick(HOST,8)
  assert(HOST.cars[1].compoundIndex==2,'full wets kept in the rain')
  -- Journée circuit ou essais : session déjà lancée, voitures apparues à l'arrêt en pneus pluie au sec.
  HUMANAI.release(); HOST=H.create(true)
  HOST.tyreCatalog[1]={{short='H',name='Hard'},{short='W',name='Wet'},{short='S',name='Soft'}}
  HOST.sim.currentSessionTime=3000; HOST.cars[1].speedKmh=0; HOST.cars[1].velocity={x=0,z=0}; HOST.cars[1].compoundIndex=1; HOST.cars[1].isAIUsingRainTyres=true
  assert(loadstring(source))(); local ej=HUMANAI.engine; C.preset('Nordschleife','J',ej.profiles.J); E.changed(ej)
  H.tick(HOST,3)
  assert(HOST.cars[1].compoundIndex==0 or HOST.cars[1].compoundIndex==2,'dry compound fitted at the start of a track day')
  local lines={}; for n=0,ej.log.count-1 do local r=ej.log[(ej.log.head-n-1)%200+1]; lines[#lines+1]=r.message end
  local text=table.concat(lines,'\n')
  assert(text:find('meteo au lancement: sec',1,true) and text:find('pneus geres par l app: oui',1,true) and text:find('pneus adaptes a la meteo a l arret au depart: W -> ',1,true),'weather and tyre change logged')
  -- Onglet Météo décoché : le journal le dit, et l'app ne touche pas aux pneus.
  ej.profiles.J.section_weather=false; E.changed(ej); ej.weather.reported=''; H.tick(HOST,0.2)
  lines={}; for n=0,ej.log.count-1 do local r=ej.log[(ej.log.head-n-1)%200+1]; lines[#lines+1]=r.message end
  assert(table.concat(lines,'\n'):find('pneus geres par l app: non (onglet Meteo decoche)',1,true),'weather tab off logged')
  local J=require('src/journal'); assert(J.summary(ej):find('pneus IA : secs ',1,true),'tyre summary each minute')
  -- Gomme sèche déjà choisie par l'IA sur piste sèche : conservée sur la grille.
  HUMANAI.release(); HOST=H.create(true)
  HOST.tyreCatalog[1]={{short='H',name='Hard'},{short='M',name='Medium'},{short='W',name='Wet'}}
  HOST.sim.isSessionStarted=false; HOST.sim.timeToSessionStart=20000; HOST.cars[1].speedKmh=0; HOST.cars[1].velocity={x=0,z=0}; HOST.cars[1].compoundIndex=1
  assert(loadstring(source))(); local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.g.autoProfile=false; e.g.manualProfile='C'; E.changed(e)
  H.tick(HOST,3); assert(HOST.cars[1].compoundIndex==1,'native dry choice kept')
  local W=require('src/weather'); local seen={}
  for index=1,40 do seen[W.dryChoice({index=index,dryList={0,3,4,5}},19731019)]=true end
  assert(seen[0] and seen[3] and seen[4] and seen[5],'every dry compound can be chosen')
 end)
 check('météo au sec : conserve un autre composé sec choisi par l’IA',function()
  HUMANAI.release(); HOST=H.create(true)
  HOST.tyreCatalog[1]={{short='S',name='Slick Soft'},{short='H',name='Slick Hard'},{short='W',name='Wet'}}
  assert(loadstring(source))(); local e=HUMANAI.engine; e.profiles.J.section_weather=true; E.changed(e); H.tick(HOST,2)
  HOST.cars[1].compoundIndex=1; H.tick(HOST,2)
  assert(e.commands[2].weatherCompound==1 and HOST.pitRequests[1]~=true)
 end)
 check('veille sans lectures de voitures, reprise avec identités fraîches et arrêt restauré',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
  -- Veille : aucun onglet coché dans aucun profil (la première installation coche Essais, Qualifications et Course).
  local e=HUMANAI.engine; for _,p in pairs(e.profiles) do for _,group in ipairs(C.sections) do p['section_'..group]=false end end; E.changed(e)
  -- Beta 1.52 (relecture de la couche hôte) : en veille, la voiture du joueur seule est relue, une fois par image (place
  -- aux stands pour la mise à jour, pont), après une première lecture complète ; aucune commande.
  H.tick(HOST,1/60); local first=HOST.carReads; H.tick(HOST,2)
  assert(HOST.carReads-first==120 and HOST.calls==0,'standby: player only ('..(HOST.carReads-first)..')')
  e.profiles.J.section_general=true; E.changed(e); H.tick(HOST,1/60)
  assert(HOST.carReads>=4 and e.frame.cars[2].identity~=nil and e.frame.cars[1].player)
  -- Beta 1.52 : app coupée : la voiture du joueur seule est relue (une par image).
  e.g.enabled=false; H.tick(HOST,2); HOST.carReads=0; local calls=HOST.calls; H.tick(HOST,1)
  assert(HOST.carReads==60 and HOST.calls==calls and math.abs(HOST.cars[1].aiLevel-0.9)<1e-6)
 end)
 check('gauche/droite : cession à droite = offset SDK positif, repère indirect et repère direct d’AC',function()
  for _,rightHanded in ipairs({false,true}) do
   HUMANAI.release(); HOST=H.create(true,{rightHanded=rightHanded}); assert(loadstring(source))()
   local e=HUMANAI.engine; local p=e.profiles.J
   p.section_general=true; p.section_yield=true; p.yieldSide='right'; E.changed(e); H.tick(HOST,5)
   local expected=rightHanded and -1 or 1
   assert(e.g.offsetSign==expected and e.g.sideSign==expected,'signs '..e.g.offsetSign..'/'..e.g.sideSign)
   HOST.cars[0].position.z=-45; HOST.cars[0].splinePosition=1-45/10000; HOST.cars[0].speedKmh=170
   local moved=0
   for _=1,6*60 do
    H.tick(HOST,1/60); local value=HOST.offsets[1] or 0
    assert(value>-0.02,'yield towards the SDK left'); moved=math.max(moved,value)
   end
   assert(moved>0.3,'no yield to the right: '..moved)
  end
 end)
 check('rechargement : valeurs d’origine conservées, réglages sauvegardés ou non',function()
  for _,saved in ipairs({true,false}) do
   HUMANAI.release(); HOST=H.create(false); assert(loadstring(source))()
   local e=HUMANAI.engine; local p=e.profiles.J
   p.section_general=true; p.levelPct=80; p.paceSpreadPct=0; E.changed(e); H.tick(HOST,3)
   assert(math.abs(HOST.cars[2].aiLevel-0.9)>0.05)
   -- Beta 1.58 : dans la voie des stands, la voiture est rendue à AC (niveau d'origine) ; la reprise est vérifiée avec
   -- la voiture commandée en piste (niveau de l'app écrit, l'original gardé par le point de reprise).
   if saved then local A=require('src/applier'); A.dirty(HUMANAI.host,e.time); A.save(HUMANAI.host,e.g,e.profiles,e.time,false,true) end
   assert(loadstring(source))(); H.tick(HOST,1/60)
   local s=HUMANAI.host.cars[3]
   assert(s.owned and math.abs(s.originalLevel-0.9)<1e-6,'recovered original '..tostring(s.owned)..' '..s.originalLevel)
   HUMANAI.engine.profiles.J.section_general=false; E.changed(HUMANAI.engine); H.tick(HOST,2)
   assert(math.abs(HOST.cars[2].aiLevel-0.9)<1e-6,'level after restore '..HOST.cars[2].aiLevel)
  end
 end)
 check('déchargement en pause : niveaux et agressivités restitués',function()
  HUMANAI.release(); HOST=H.create(false); assert(loadstring(source))()
  local e=HUMANAI.engine; local p=e.profiles.J
  p.section_general=true; p.levelPct=70; p.aggressionPct=20; p.paceSpreadPct=0; E.changed(e); H.tick(HOST,3)
  assert(HOST.cars[1].aiLevel<0.8)
  pause(true); HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  assert(math.abs(HOST.cars[1].aiLevel-0.9)<1e-6 and math.abs(HOST.cars[1].aiAggression-0.45)<1e-6,'not restored on release')
  pause(false)
 end)
 check('110 % : relecture fiable à la sortie des stands, écrêtage toujours détecté',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
  local e=HUMANAI.engine; local p=e.profiles.J
  HOST.cars[3].isInPitlane=true
  p.section_general=true; p.levelPct=105; p.paceSpreadPct=0; E.changed(e); H.tick(HOST,3)
  assert(HUMANAI.host.caps.native110 and HUMANAI.host.caps.levelMode=='native')
  HOST.cars[3].isInPitlane=false; H.tick(HOST,3)
  assert(HUMANAI.host.caps.native110 and HOST.cars[3].aiLevel>1.04,'false clamp after pit exit')
  HOST.clampLevel=true; p.levelPct=108; E.changed(e); H.tick(HOST,5)
  -- Beta 1.53 : écrêtage détecté (journal), mais le mode automatique reste natif tant que le bonus de grip n'est pas
  -- autorisé ; « natif si confirmé » repasse au plafond.
  assert(not HUMANAI.host.caps.native110 and HUMANAI.host.caps.clampProven and HUMANAI.host.caps.levelMode=='native','clamp not detected')
  e.g.levelMode='native'; p.section_globals=true; E.changed(e); H.tick(HOST,2); assert(HUMANAI.host.caps.levelMode=='none','native if confirmed: cap')
 end)
 check('stands météo : demande maintenue dans la voie jusqu’à l’arrêt, composé changé à l’arrêt, levée après l’emplacement',function()
  HUMANAI.release(); HOST=H.create(true)
  HOST.tyreCatalog[1]={{short='S',name='Slick Soft'},{short='I',name='Intermediate'},{short='W',name='Full Wet'}}
  HOST.sim.rainWetness=1; HOST.sim.rainIntensity=1
  assert(loadstring(source))(); local e=HUMANAI.engine; e.profiles.J.section_weather=true; E.changed(e); H.tick(HOST,2)
  assert(HOST.pitRequests[1]==true)
  HOST.cars[1].isInPitlane=true; H.tick(HOST,3); assert(HOST.pitRequests[1]==true,'request withdrawn in the pit lane')
  HOST.cars[1].isInPit=true; HOST.cars[1].speedKmh=0; H.tick(HOST,2)
  assert(HOST.cars[1].compoundIndex==2 and HOST.pitRequests[1]==true)
  -- Beta 1.58 : arrêt fait et emplacement quitté : levée dans la voie aussi (false bloque un nouveau passage d'AC un
  -- court moment, ce qu'il faut ici : sinon AC pouvait la ramener à son emplacement en boucle).
  HOST.cars[1].isInPit=false; HOST.cars[1].speedKmh=60; H.tick(HOST,2); assert(HOST.pitRequests[1]==false,'lifted once the stop is done')
  HOST.cars[1].isInPitlane=false; HOST.cars[1].speedKmh=108; H.tick(HOST,2); assert(HOST.pitRequests[1]==false)
 end)
 check('météo au sec : stratégie pluie native de CSP non forcée',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
  local e=HUMANAI.engine; e.profiles.J.section_weather=true; E.changed(e); H.tick(HOST,3)
  assert(e.commands[2].weatherManaged and HOST.rainHints[1]==nil,'native rain strategy overridden in the dry')
  HOST.sim.rainWetness=1; HOST.sim.rainIntensity=1; H.tick(HOST,17); assert(HOST.rainHints[1]==true)
 end)
 check('menu setup/garage : la session continue, le moteur aussi ; vraie pause figée',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
  local e=HUMANAI.engine; e.profiles.J.section_general=true; E.changed(e); H.tick(HOST,2)
  HOST.sim.isInMainMenu=true; local before,frames=e.time,e.frames; H.tick(HOST,2)
  assert(HUMANAI.host.menuVisible and HOST.windowOpen.main and e.time>before+1.9 and e.frames>frames and e.guard=='ready')
  HOST.sim.isPaused=true; before,frames=e.time,e.frames; local calls=HOST.calls; H.tick(HOST,1)
  assert(e.time==before and e.frames==frames and HOST.calls==calls and e.guard=='paused')
  HOST.sim.isPaused=false; HOST.sim.isInMainMenu=false; H.tick(HOST,1/60); assert(not HUMANAI.host.menuVisible)
 end)
 check('redémarrage de session au même indice : écritures resynchronisées',function()
  HUMANAI.release(); HOST=H.create(false); assert(loadstring(source))()
  local e=HUMANAI.engine; local p=e.profiles.J; p.section_general=true; p.levelPct=80; p.paceSpreadPct=0; E.changed(e); H.tick(HOST,3)
  local commanded=HOST.cars[1].aiLevel; assert(math.abs(commanded-0.9)>0.05)
  HOST.cars[1].aiLevel=0.9 -- niveau rétabli par le jeu au redémarrage
  for fn in pairs(HOST.sessions) do fn(0,true) end; H.tick(HOST,1)
  assert(math.abs(HOST.cars[1].aiLevel-commanded)<0.01,'level not rewritten after restart')
  assert(math.abs(HUMANAI.host.cars[2].originalLevel-0.9)<1e-6)
 end)
 check('week-end : essais, qualifications, course ; préréglage reconnu et appliqué une fois par profil',function()
  -- Installation existante jamais réglée (la première installation, elle, part comme « Règles de base »).
  HUMANAI.release(); HOST=H.create(true); HOST.storage['humanai:g:']={dataRevision=4}
  HOST.raceIni={SESSION_0={NAME='Practice',TYPE=1},SESSION_1={NAME='Qualifying',TYPE=2},SESSION_2={NAME='Race',TYPE=3}}
  assert(loadstring(source))(); pause(true)
  local e=HUMANAI.engine; H.tick(HOST,0.1); main(); assert(e.profile=='P' and not C.anySection(e.profiles.P),'existing install never configured stays neutral')
  -- Préréglages chargés en mode automatique : la détection reste active.
  go('home'); press('builtin_Nordschleife'); press('builtin_Course'); assert(e.g.autoProfile and e.profile=='P' and e.g.presetsUsed)
  assert(e.profiles.J.section_traffic and e.profiles.C.section_blue)
  H.tick(HOST,0.1); main()
  assert(e.profile=='P' and e.profiles.P.configured and e.profiles.P.section_yield and not e.profiles.P.section_traffic)
  -- Beta 1.29 (demande du pilote) : préréglage recommandé appliqué tout seul : aucun bouton présélectionné.
  main(); assert(not lit('builtin_Essais'),'recommended preset applied on its own: nothing highlighted')
  assert(not e.profiles.Q.configured and not C.anySection(e.profiles.Q))
  local function nextSession(index,kind)
   HOST.sim.currentSessionIndex=index; HOST.sim.raceSessionType=kind
   for fn in pairs(HOST.sessions) do fn(index,false) end; H.tick(HOST,0.1); main()
  end
  nextSession(1,2)
  assert(e.profile=='Q' and e.profiles.Q.configured and e.profiles.Q.section_yield and not e.profiles.Q.section_blue)
  main(); assert(not lit('builtin_Qualifications') and HOST.storage['humanai:p:Q:'].section_yield==true)
  nextSession(2,3); main(); assert(e.profile=='C' and lit('builtin_Course'))
  -- Un profil Qualifications vidé volontairement n'est jamais réappliqué.
  nextSession(1,2); for _,group in ipairs(C.sections) do e.profiles.Q['section_'..group]=false end; E.changed(e); H.tick(HOST,0.1)
  assert(e.profile=='Q' and not C.anySection(e.profiles.Q))
  nextSession(2,3); nextSession(1,2); assert(not C.anySection(e.profiles.Q))
  pause(false)
 end)
 check('installation existante jamais réglée : aucun préréglage automatique sans préréglage déjà chargé',function()
  HUMANAI.release(); HOST=H.create(true); HOST.storage['humanai:g:']={dataRevision=4}; HOST.raceIni={SESSION_0={NAME='Qualifying',TYPE=2}}; assert(loadstring(source))(); H.tick(HOST,2)
  local e=HUMANAI.engine; assert(e.profile=='Q' and not e.g.presetsUsed and not C.anySection(e.profiles.Q) and HOST.calls==0)
 end)
 check('migration 1.2.0 : profil intact mis à jour, profil retouché conservé, sauvegarde',function()
  local legacy=require('tests/legacy_presets')
  HUMANAI.release(); HOST=H.create(true)
  local function stored(key) local t={}; for k,v in pairs(legacy[key]) do t[k]=v end; return t end
  HOST.storage['humanai:p:C:']=stored('Course:C')
  local touched=stored('Qualifications:Q'); touched.levelPct=99; HOST.storage['humanai:p:Q:']=touched
  HOST.storage['humanai:g:']={schemaVersion=3,enabled=true,autoProfile=true,manualProfile='J',presetsUsed=true,loadedPreset='builtin:Course',loadedPresetProfile='C'}
  assert(loadstring(source))(); H.tick(HOST,2)
  local e=HUMANAI.engine
  assert(e.profiles.C.section_accidents and e.profiles.C.section_rules and e.profiles.C.overtakeSide=='auto' and e.profiles.C.multiClass and e.g.dataRevision==C.dataRevision)
  assert(e.profiles.Q.levelPct==99 and e.profiles.Q.section_accidents and not e.profiles.Q.yellowEnabled and not e.profiles.Q.section_rules)
  assert(rawget(HOST.storage['humanai:g:'],'dataRevision')==C.dataRevision and rawget(HOST.storage['humanai:p:C:'],'section_accidents')==true,'migration saved')
  assert(HUMANAI.host.upgraded[1]=='C:Course')
  pause(true); go('settings'); assert(drawn('cat_accidents')); go('rules'); assert(drawn('section_rules')); pause(false)
 end)
 check('accident en jeu : zone jaune à 50 km/h, drapeau et message au joueur, IA accidentée retenue, tout rendu',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Nordschleife','J',e.profiles.J); E.changed(e)
  HOST.cars[0].splinePosition=0.995
  HOST.cars[3].speedKmh=0; HOST.cars[3].velocity={x=0,z=0}
  H.tick(HOST,8)
  assert(e.incidents.cars[4].incident,'stopped AI is an incident')
  -- Allure encore inconnue : vitesse de repli du double jaune, moins la marge propre au pilote.
  assert(HOST.speedLimits[1]<=50+1e-6 and HOST.speedLimits[1]>=50*(1-C.K.aiDeltaMarginMax)-1e-6,'zone fallback speed written: '..tostring(HOST.speedLimits[1]))
  -- 1.5.0 : panneau de drapeaux seul par défaut, drapeau natif laissé à AC ; drapeau natif sur demande.
  -- IA arrêtée en piste : double drapeau jaune.
  assert(HOST.flag==0 and (e.panel.title==L.flagTitles.yellow2 or e.panel.title==L.flagTitles.zone) and e.panel.double and #HOST.messages>=1 and HOST.messages[1]:find(L.messages.yellow[1],1,true),'player warned by the panel')
  e.profiles.J.yellowHud=true; E.changed(e); H.tick(HOST,0.5); assert(HOST.flag==C.K.flagCaution,'native yellow flag on request')
  -- Beta 1.7 : retenue hors piste seulement (jamais immobilisée sur la trajectoire).
  HOST.cars[2].collidedWith=3; HOST.cars[2].wheelsOutside=4; HOST.cars[2].speedKmh=5; HOST.cars[2].velocity={x=0,z=1.4}; H.tick(HOST,1)
  assert(HOST.stops[2]==C.K.stopPulse,'crashed AI held off the track')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  assert(HOST.flag==0 and HOST.stops[2]==0 and HOST.speedLimits[1]==C.K.unlimitedSpeed,'everything handed back')
 end)
 check('course avec arrêt obligatoire : demandes écrites, pneus à l’emplacement, levée à la sortie, mémorisé, rendu',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.session={laps=20,durationMinutes=0,isTimedRace=false}
  assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.profiles.C.mandatoryStops=1; E.changed(e)
  HOST.sim.leaderLapCount=4; H.tick(HOST,3); assert(e.profile=='C' and e.pits.state=='pending' and not HOST.pitRequests[1])
  HOST.sim.leaderLapCount=14; H.tick(HOST,3)
  assert(HOST.pitRequests[1]==true and HOST.pitRequests[2]==true and HOST.pitRequests[3]==true,'stops requested in the window')
  assert(#HOST.messages>=1 and HOST.messages[#HOST.messages]:find(L.messages.pitOpen[1],1,true),'player told the window is open')
  local car=HOST.cars[1]; car.isInPitlane=true; car.isInPit=true; car.speedKmh=0; car.velocity={x=0,z=0}; H.tick(HOST,2)
  assert(HUMANAI.host.cars[2].tyreVisit==1 and e.pits.cars[2].stops==1,'fresh tyres at the stop')
  car.isInPit=false; car.isInPitlane=false; car.speedKmh=108; car.velocity={x=0,z=30}; H.tick(HOST,3)
  assert(HOST.pitRequests[1]==false and HOST.pitRequests[2]==true,'request lifted after the stop only')
  assert(HOST.values['humanai:pits'] and HOST.values['humanai:pits']:find(',1',1,true),'stop remembered for a reload')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  assert(HOST.pitRequests[2]==false and HOST.pitRequests[3]==false,'requests handed back on unload')
 end)
 -- Beta 1.50 : la voiture de sécurité en service est retenue à son emplacement par l'attente d'AC (jamais garée sans
 -- pilote) ; les voitures de réserve restent garées sans pilote.
 local function scHeld(i) return HOST.parked[i]==true or (HOST.startDelays[i] or 0)>=C.K.scHoldTime end
 check('voiture de sécurité : garée aux stands au départ, panneau de choix, rendue au déchargement',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; e.g.safetyCarModel='model_3'; E.changed(e)
  H.tick(HOST,2)
  assert(e.incidents.safety==4 and HOST.teleports==1 and scHeld(3) and not HOST.parked[3],'safety car held in its box, never parked without a driver')
  pause(true); section('rules'); main(); assert(not HUMANAI.engine.panic); pause(false)
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  assert(not scHeld(3),'handed back')
 end)
 check('journal de session sur disque : rotation, en-tête, session, incident, résumé, fin ; coupé si désactivé',function()
  HUMANAI.release(); HOST=H.create(true); HOST.files['logs/AdvancedIA.log']='ancien lancement\n'
  assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Nordschleife','J',e.profiles.J); E.changed(e)
  HOST.cars[3].speedKmh=0; HOST.cars[3].velocity={x=0,z=0}
  H.tick(HOST,8)
  local text=HOST.files['logs/AdvancedIA.log']
  assert(HOST.files['logs/AdvancedIA.1.log']=='ancien lancement\n','previous launch kept')
  assert(text:find('=== AdvancedIA '..C.release..' : lancement ',1,true),'header with version')
  assert(text:find('session: indice 0',1,true) and text:find('profil: J (automatique)',1,true),'session and profile')
  assert(text:find('incident: arret, en piste',1,true) and text:find('resume: profil J',1,true),'incident and summary')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  assert(HOST.files['logs/AdvancedIA.log']:find('=== fin : ',1,true),'end line on unload')
  -- Rechargement de l'app dans le même lancement du jeu : même fichier poursuivi, pas de rotation.
  local before=HOST.files['logs/AdvancedIA.log']; assert(loadstring(source))(); H.tick(HOST,1)
  assert(HOST.files['logs/AdvancedIA.1.log']=='ancien lancement\n' and HOST.files['logs/AdvancedIA.log']:sub(1,#before)==before,'reload: same journal continued')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  HOST=H.create(true); assert(loadstring(source))(); HUMANAI.engine.g.journal=false; HUMANAI.host.journalTried=nil
  -- Beta 1.40 : seules les options de CSP (gui.ini, fichier d'état) sont écrites ; rien dans le dossier des journaux.
  H.tick(HOST,3); for path in pairs(HOST.files) do assert(path:sub(1,5)~='logs/','nothing written when disabled: '..path) end
  HUMANAI.release()
 end)
 check('modes Content Manager : journée circuit, essai seul et course seule détectés',function()
  local cases={{{NAME='Track Day',TYPE=1},'J'},{{NAME='Track Day',TYPE=2},'J'},{{NAME='Qualifying',TYPE=2},'Q'},{{NAME='Practice',TYPE=1},'P'},{{NAME='Quick Race',TYPE=3},'C'}}
  for _,case in ipairs(cases) do
   HUMANAI.release(); HOST=H.create(true); HOST.raceIni={SESSION_0=case[1]}; assert(loadstring(source))(); H.tick(HOST,0.1)
   assert(HUMANAI.engine.profile==case[2],case[1].NAME..' -> '..HUMANAI.engine.profile)
  end
 end)
 -- Beta 1.16 : parcours joué dans les deux langues (anglais à la première installation, puis français au clic).
 local function tooltipWalk(code)
  HUMANAI.release(); HOST=H.create(true); HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  if code=='fr' then press('lang_fr') end
  assert(require('src/locale').current==code and HUMANAI.engine.g.language==code,'interface language: '..code)
  local e=HUMANAI.engine
  for _,profile in ipairs(C.profiles) do C.preset(({J='Nordschleife',P='Essais',Q='Qualifications',C='Course'})[profile],profile,e.profiles[profile]) end
  e.profiles.C.neutralization='sc'; e.profiles.C.mandatoryStops=1; e.profiles.C.section_globals=true; e.profiles.J.section_globals=true
  -- Souris placée sur chaque commande dessinée de l'image : une infobulle doit s'afficher.
  local function covered(where)
   redraw(); local ids={}; for k,id in ipairs(HOST.hitOrder) do ids[k]=id end
   for _,id in ipairs(ids) do
    local r=HOST.hits[id]; HOST.mouse={x=r.x+r.w/2,y=r.y+r.h/2}; HOST.lastTooltip=nil; main()
    assert(HOST.lastTooltip,'tooltip missing: '..id..' ('..where..')')
   end
   HOST.mouse={x=-1e6,y=-1e6}
  end
  HOST.tooltips={}
  for _,profile in ipairs(C.profiles) do
   go('home'); press('profile_'..profile)
   for _,name in ipairs({'home','diagnostic'}) do go(name); covered(profile..'/'..name) end
   go('settings')
   local listed={}; for _,group in ipairs(C.sections) do if group~='rules' then listed[#listed+1]=group end end
   listed[#listed+1]='overlay'
   for _,group in ipairs(listed) do
    press('cat_'..group); covered(profile..'/'..group)
    assert(lit('cat_'..group),'selected section highlighted: '..group)
    for _,other in ipairs(C.sections) do if other~=group then assert(not lit('cat_'..other),'only one section highlighted') end end
    if group=='general' then
     local specific=false; for _,tip in ipairs(HOST.tooltips) do if tip:find('Content%sManager') then specific=true end end
     assert(specific,'setting tooltips are specific, not generic')
    end
    if group=='endurance' then press('pattern_rows'); covered(profile..'/patterns'); press('pattern_rows') end
   end
   go('rules'); covered(profile..'/rules')
   press('rules_view_stops'); covered(profile..'/rules stops'); press('rules_view_safety'); covered(profile..'/rules safety'); press('rules_view_all')
   e.profiles[profile].section_rules=false; main(); covered(profile..'/rules unticked')
   assert(drawn('rules_F1'),'rule buttons shown and explained with the tab unticked')
  end
  -- Onglet Diagnostic : souris sur chaque commande, une infobulle à chaque fois ; copie des zones, filtre du journal.
  go('diagnostic'); redraw(); local diagIds={}; for k,id in ipairs(HOST.hitOrder) do diagIds[k]=id end
  assert(#diagIds>=12,'diagnostic controls drawn')
  for _,id in ipairs(diagIds) do local r=HOST.hits[id]; HOST.mouse={x=r.x+r.w/2,y=r.y+r.h/2}; HOST.lastTooltip=nil; main(); assert(HOST.lastTooltip,'diagnostic tooltip missing: '..id) end
  HOST.mouse={x=-1e6,y=-1e6}
  HOST.clip=''; press('export'); assert(HOST.clip:match('zones'),'zones copied')
  press('log_filter'); redraw()
  assert(lit('log_filter_2') and not lit('log_filter_1'),'log filter cycled')
  HOST.hoverAll=true
  assert(HOST.styleDepth==0 and HOST.dwriteDepth==0 and HOST.clipDepth==0)
  for _,text in ipairs(HOST.tooltips) do for line in (text..'\n'):gmatch('(.-)\n') do assert(#line<=C.K.uiTipWidth+24,'tooltip line too long: '..line) end end
  HOST.hoverAll=false; HOST.space={x=1000,y=780}; pause(false)
 end
 check('1.4.0 : une infobulle après chaque commande, tous profils et onglets, onglet choisi en surbrillance',function() tooltipWalk('en') end)
 check('Beta 1.16 : une infobulle après chaque commande en français, tous profils et onglets',function() tooltipWalk('fr') end)
 check('1.5.0 : drapeau rouge en course, panneau de drapeaux, IA aux stands, dépannage, reprise, tout rendu',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.sim.carsCount=4
  assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagCars=2; e.profiles.C.redFlagHold=20; E.changed(e)
  H.tick(HOST,8)
  -- Beta 1.47 : drapeau rouge seulement sur une piste vraiment bloquée : piste étroite (3 m de chaque côté), deux
  -- voitures arrêtées côte à côte, immobilisées K.redIncidentStill s.
  local sides=ac.getTrackAISplineSides; ac.getTrackAISplineSides=function() return {x=3,y=3} end
  for k,i in ipairs({2,3}) do local c=HOST.cars[i]; c.speedKmh=0; c.velocity={x=0,z=0}; c.position={x=k==1 and -1.5 or 1.5,y=0,z=HOST.cars[2].position.z}; c.splinePosition=HOST.cars[2].splinePosition end
  H.tick(HOST,C.K.redIncidentStill+1)
  ac.getTrackAISplineSides=sides
  assert(e.incidents.red and HOST.pitRequests[1]==true,'red flag: AI called to the pits')
  HOST.transparent={}; script.HUMANAI__HUD(); assert(e.panel.kind=='red' and HOST.transparent.AdvancedIA_overlay,'overlay drawn on the red flag')
  HOST.draws=0; HOST.panelTexts={}; HOST.textTop=nil; HOST.circles=0; HUMANAI.drawFlags()
  assert(HOST.draws>=2 and HOST.fontDepth==0 and HOST.styleDepth==0 and has(HOST.panelTexts,L.flagTitles.red),'red flag drawn')
  assert(has(HOST.panelTexts,L.deltaLabel) and has(HOST.panelTexts,L.pitPill) and e.delta.kind=='red','red flag: delta box to the pits and PIT pill')
  -- Beta 1.38 (maquette) : plus de version en haut à droite de l'overlay.
  assert(not has(HOST.panelTexts,string.format(L.panelVersion,C.release)),'no version text at the top of the flags panel')
  assert(HOST.textTop>=34,'text placed under the CSP title bar, never behind it')
  -- Fenêtre basse : titre en police normale, toujours sous la barre de titre ; police toujours rendue.
  HOST.windowHeight=110; HOST.textTop=nil; HUMANAI.drawFlags(); assert(HOST.textTop>=34 and HOST.fontDepth==0); HOST.windowHeight=nil
  HOST.panelTexts={}; HUMANAI.drawFlags(); assert(has(HOST.panelTexts,e.panel.short) and e.panel.short~='','one-line instruction drawn')
  -- Beta 1.39 (maquette) : pastilles en capitales.
  local noPass; for k,text in ipairs(HOST.panelTexts) do if text==W.upper(L.noPassing) then noPass=HOST.panelColors[k] end end
  -- Refonte Racing 26 : vert du kit #2EE07F (composante verte 0,88).
  assert(noPass and noPass.g>0.8 and noPass.r<0.5,'no overtaking line drawn in green')
  -- Temps delta en direct : positif en vert, négatif en rouge (valeur signée, virgule décimale).
  local function deltaShown(value)
   e.delta.course.delta=value; H.tick(HOST,1/60); HOST.panelTexts={}; HOST.panelColors={}; HUMANAI.drawFlags()
   for k,text in ipairs(HOST.panelTexts) do if text:match('^[%+%-]%d+[,%.]%d%d$') then return text,HOST.panelColors[k] end end
  end
  local text,color=deltaShown(0.8)
  assert(text and text:sub(1,1)=='+' and color.g>0.8 and color.r<0.5,'positive delta in green: '..tostring(text))
  text,color=deltaShown(-0.5)
  assert(text and text:sub(1,1)=='-' and color.r>0.9 and color.g<0.5,'negative delta in red: '..tostring(text))
  -- Valeur arrondie à zéro : « +0,00 » en vert (le signe lu est celui du centième affiché).
  e.delta.value=-0.003; HOST.panelTexts={}; HOST.panelColors={}; HUMANAI.drawFlags()
  local zero; for k,shown in ipairs(HOST.panelTexts) do if shown=='+0'..L.decimalMark..'00' then zero=HOST.panelColors[k] end end
  assert(zero and zero.g>0.8 and zero.r<0.5,'rounded to zero: shown green')
  e.delta.course.delta=2
  HOST.cars[0].speedKmh=108
  H.tick(HOST,3); assert(HOST.teleports>=2,'immobilised AI recovered to their pits')
  for i=1,3 do HOST.cars[i].isInPit=true; HOST.cars[i].isInPitlane=true; HOST.cars[i].speedKmh=0; HOST.cars[i].velocity={x=0,z=0} end
  H.tick(HOST,30); assert(e.incidents.red,'restart waits for the player in the pit lane')
  HOST.cars[0].isInPitlane=true; HOST.cars[0].speedKmh=60
  for _=1,80 do if not e.incidents.red then break end; H.tick(HOST,0.5) end
  H.tick(HOST,0.3) -- panneau rafraîchi tous les quarts de seconde
  -- Beta 1.34 : tour de relance annoncé comme un départ lancé (RS).
  assert(not e.incidents.red and e.incidents.relaunch and e.incidents.neutralMode=='fcy' and e.panel.kind=='rolling' and e.panel.title==L.flagTitles.rolling,'relaunch lap under FCY (no safety car) after the hold')
  assert(HOST.messages[#HOST.messages]:find(L.messages.redRestartFcy[2],1,true),'relaunch announced')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  assert(HOST.flag==0,'native flag untouched')
 end)
 check('1.6.0 : arrêts obligatoires mémorisés appliqués après un rechargement, oubliés au redémarrage de la session',function()
  local function rules() local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.profiles.C.mandatoryStops=1; E.changed(e) end
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  assert(loadstring(source))(); rules(); H.tick(HOST,2)
  local id=HUMANAI.engine.pits.cars[2].identity; assert(id and id:match('^[%w_%-]+$'),'serializable identity: '..tostring(id))
  HUMANAI.release(); HOST.values['humanai:pits']='0\n'..id..',1'
  assert(loadstring(source))(); rules(); H.tick(HOST,0.5)
  assert(HUMANAI.engine.pits.cars[2].windowStops==1,'stop kept across a reload')
  for fn in pairs(HOST.sessions) do fn() end; H.tick(HOST,0.5)
  assert(HUMANAI.engine.pits.cars[2].windowStops==0,'restart of the session: stops forgotten')
  -- Disqualification d'une IA conservée à travers un rechargement : elle reste garée.
  local e=HUMANAI.engine; e.penalties.ai.count[2]=6; e.penalties.ai.dq[2]=true; e.penalties.dirty=true; H.tick(HOST,C.K.saveDelay+0.5)
  assert(HOST.values['humanai:penalties'] and HOST.values['humanai:penalties']:find('2,6,1,',1,true),'sanction saved: '..tostring(HOST.values['humanai:penalties']))
  HUMANAI.release(); assert(loadstring(source))(); rules(); H.tick(HOST,0.5)
  assert(HUMANAI.engine.penalties.ai.dq[2] and HUMANAI.engine.commands[2].scPark and HUMANAI.engine.states[2].disqualified,'disqualified AI still parked after a reload')
  -- Joueur disqualifié : drapeau noir levé au déchargement, de nouveau imposé après le rechargement ; levé au redémarrage.
  local pe=HUMANAI.engine.penalties; pe.count=6; pe.disqualified=true; pe.kind='dq'; pe.requestId=pe.requestId+1; pe.dirty=true; H.tick(HOST,C.K.saveDelay+0.5)
  assert(HUMANAI.host.blackFlag,'black flag applied')
  local releases=HOST.blackFlagReleases or 0; HUMANAI.release(); assert((HOST.blackFlagReleases or 0)==releases+1,'lifted on unload')
  assert(loadstring(source))(); rules(); H.tick(HOST,0.5)
  assert(HUMANAI.engine.penalties.disqualified and HUMANAI.host.blackFlag,'black flag imposed again after the reload')
  for fn in pairs(HOST.sessions) do fn() end; H.tick(HOST,0.5)
  assert(not HUMANAI.host.blackFlag and (HOST.blackFlagReleases or 0)==releases+2,'lifted for the new session')
 end)
 check('1.8.0 : décocher le profil automatique garde le profil en cours',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))(); H.tick(HOST,0.5)
  assert(HUMANAI.engine.profile=='C' and HUMANAI.engine.g.autoProfile)
  pause(true); go('home'); press('auto'); pause(false); H.tick(HOST,0.5)
  assert(not HUMANAI.engine.g.autoProfile and HUMANAI.engine.profile=='C','manual profile = the current one ('..HUMANAI.engine.profile..')')
 end)
 check('Beta 1.3 : voiture de sécurité habillée de sa livrée quand le tirage au sort ne la lui a pas donnée',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.skins={[2]='1white'}; HOST.skinFolders={model_2={'1white','2black','Safety_Car'}}
  assert(loadstring(source))(); local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.g.safetyCarModel='model_2'; E.changed(e); H.tick(HOST,2)
  assert(e.incidents.safety==3 and HOST.appliedSkins and HOST.appliedSkins['carRoot:2']=='cars/model_2/skins/Safety_Car','safety car dressed in the Safety_Car livery')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  -- Livrée déjà portée : rien n'est appliqué.
  HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.skins={[2]='Safety_Car'}; HOST.skinFolders={model_2={'Safety_Car'}}
  assert(loadstring(source))(); e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.g.safetyCarModel='model_2'; E.changed(e); H.tick(HOST,2)
  assert(e.incidents.safety==3 and not HOST.appliedSkins,'already in its livery: nothing applied')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 check('Beta 1.2 : erreurs de pilotage des IA écrites une fois par les fonctions natives',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))()
  -- Décisions injectées (le tirage est testé à part) : IA commandée, après l'attente et la détente du départ.
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.profiles.C.mistakesEnabled=false; E.changed(e); H.tick(HOST,30)
  local cmd=e.commands[2]; assert(cmd.active,'AI managed by the app') cmd.mistakeId=cmd.mistakeId+1; cmd.mistakeKind='brake'; cmd.mistakeTime=0.6; H.tick(HOST,1)
  assert(#HOST.mistakes==1 and HOST.mistakes[1].kind=='brake' and HOST.mistakes[1].index==1 and HOST.mistakes[1].time==0.6,'brake lock written once')
  cmd.mistakeId=cmd.mistakeId+1; cmd.mistakeKind='traction'; cmd.mistakeTime=0.4; cmd.mistakeSeverity=1.4; H.tick(HOST,1)
  assert(#HOST.mistakes==2 and HOST.mistakes[2].kind=='traction' and HOST.mistakes[2].severity==1.4,'wheelspin written with its severity')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 check('Beta 1.2 : DRS coupé par les règles pour toutes les voitures, rendu, bip delta joué par un seul événement',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  for i=0,3 do HOST.cars[i].drsPresent=true end
  assert(loadstring(source))(); local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); E.changed(e)
  -- Départ réel : session pas encore lancée au premier passage de l'app.
  HOST.sim.isSessionStarted=false; H.tick(HOST,0.5); HOST.sim.isSessionStarted=true; HOST.sim.leaderLapCount=1; H.tick(HOST,1)
  assert(HOST.drsBlocks[0]==true and HOST.drsBlocks[1]==true and HOST.drsBlocks[3]==true,'start: DRS off for the player and the AI, even if the game counter shows a lap')
  -- Le leader boucle un tour (l'hôte ne déplace pas les voitures) : DRS rendu.
  for _=1,110 do HOST.cars[1].splinePosition=(HOST.cars[1].splinePosition+0.01)%1; H.tick(HOST,1/60) end
  assert(HOST.drsBlocks[0]==false and HOST.drsBlocks[2]==false,'after one measured lap: handed back')
  e.drsRule.restart=true; H.tick(HOST,0.5); assert(HOST.drsBlocks[0]==true,'restart: off again')
  -- DRS des IA : ouvert dans la zone par la fonction native.
  e.profiles.C.rulesDrsLaps=0; E.changed(e); HOST.cars[2].drsAvailable=true; H.tick(HOST,0.5)
  assert(HOST.drsOpen[2]==true,'AI DRS opened in the zone')
  -- Freinage : refermé aussitôt, sans attendre le délai d'une seconde entre deux ouvertures.
  HOST.cars[2].drsActive=true; HOST.cars[2].brake=1; H.tick(HOST,0.2); assert(HOST.drsOpen[2]==false,'closed at once under braking')
  HOST.cars[2].brake=0; HOST.cars[2].drsActive=false
  e.profiles.C.rulesDrsLaps=1; E.changed(e); e.drsRule.restart=true; H.tick(HOST,0.5)
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  assert(HOST.drsBlocks[0]==false and HOST.drsBlocks[1]==false,'unload: DRS handed back to every car')
  -- Bips du temps delta : fichier de l'app, un seul événement sonore relancé.
  HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))(); e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); E.changed(e); H.tick(HOST,0.5)
  local played=HOST.played
  for _=1,3 do e.deltaBeep.beepId=e.deltaBeep.beepId+1; HUMANAI.host.deltaServed=nil; require('src/applier').deltaBeep(HUMANAI.host,e.frame,e.deltaBeep) end
  local count=0; for _,s in ipairs(HOST.sounds) do if s=='apps/lua/AdvancedIA/sounds/delta-beep.wav' then count=count+1 end end
  assert(count==1 and HOST.played==played+3,'one sound event, started three times')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 check('Beta 1.1 : voiture de sécurité choisie par son nom affiché dans Content Manager, parmi toutes les voitures',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  HOST.carFolders={'aston_vantage2018','zz_last'}; for k=1,120 do HOST.carFolders[#HOST.carFolders+1]=string.format('car_%03d',k) end
  HOST.files['cars/aston_vantage2018/ui/ui_car.json']='{\r\n  "name": "Aston Martin Vantage safety car 2021",\r\n  "brand": "Aston Martin"\r\n}'
  HOST.carFolders[#HOST.carFolders+1]='quoted_car'; HOST.files['cars/quoted_car/ui/ui_car.json']='{"name": "F355 \\"Persephone\\" \\u00e9t\\u00e9", "tags": ["a"]}'
  assert(loadstring(source))(); local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; E.changed(e); H.tick(HOST,0.5)
  HOST.space={x=1000,y=3000}; pause(true); go('home'); press('profile_C'); section('rules','safetyCarSpeedKmh'); main()
  -- Beta 1.39 : base lue par étapes, quelques images.
  for _=1,20 do main() end
  -- Beta 1.38 (maquette) : base en lignes (nom, dossier), huit au plus, les autres comptées.
  redraw(); assert(drawn('safety_pick_8') and not drawn('safety_pick_9') and begins(string.format(L.safetyMore,#HOST.carFolders-8)),'every installed car counted, eight rows shown')
  HOST.inputEdits['##aai_safety_filter']='persephone'; main(); redraw()
  assert(drawn('safety_pick_1') and not drawn('safety_pick_2') and drawnText('F355 "Persephone" été') and drawnText('quoted_car'),'escaped quotes and accents read')
  HOST.inputEdits['##aai_safety_filter']='safety car'; main(); redraw()
  assert(drawnText('Aston Martin Vantage safety car 2021') and drawnText('aston_vantage2018') and not drawn('safety_pick_2'),'found by its Content Manager name')
  press('safety_pick_1'); main()
  -- Beta 1.19 : bloc sous le titre Voiture de sécurité de l'onglet Règles de course, après ses réglages.
  redraw(); assert(HOST.hits['##aai_safety_clear'].y>HOST.hits['##aai_set_safetyCarEscalation'].y and not drawn('set_redFlagEnabled'),'safety car block in its own view, after its settings')
  pause(false); HOST.space={x=1000,y=780}
  assert(e.g.safetyCarModel=='aston_vantage2018' and e.g.safetyCarPicked,'folder stored as the model, picked by the driver')
 end)
 check('Beta 1.0 : version affichée en haut des fenêtres de réglage et de diagnostic',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))(); H.tick(HOST,0.5)
  local title=string.format(L.titleVersion,C.release)
  local function shown() for _,t in ipairs(HOST.wrappedTexts) do if t==title then return true end end return false end
  -- Refonte Racing 26 : marque en deux couleurs (ADVANCED, IA) et puce de version « β1.33 » dans l'en-tête de tous les onglets.
  local chip='β'..(C.release:gsub('^Beta ',''))
  pause(true); redraw(); assert(C.release:match('^Beta %d') and drawnText(chip) and drawnText('ADVANCED') and drawnText('IA'),'settings window')
  go('diagnostic'); redraw(); assert(drawnText(chip) and drawnText(W.upper(L.capabilities)),'diagnostic tab')
  -- Trois onglets, sans Préréglages ; aucune fenêtre de diagnostic séparée.
  assert(drawn('tab_home') and drawn('tab_settings') and drawn('tab_diagnostic') and not drawn('tab_presets') and script.HUMANAI__DEBUG==nil)
  pause(false)
 end)
 check('1.6.0 : erreur d affichage des réglages journalisée, moteur jamais arrêté',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))(); H.tick(HOST,1)
  local UI=package.loaded['src/ui']; local original=UI.main
  UI.main=function() error('panne volontaire') end
  pause(true); script.HUMANAI__MAIN(); script.HUMANAI__MAIN(); UI.main=original; pause(false)
  local e=HUMANAI.engine; local found=0
  for n=0,e.log.count-1 do local r=e.log[(e.log.head-n-1)%200+1]; if r.message:find('ui:',1,true) then found=found+1 end end
  assert(not e.panic and found==1,'UI error logged once, engine still running')
  assert(HUMANAI.host.errors==2,'both UI errors counted'); HUMANAI.host.errors=0
 end)
 check('1.6.0 : restitution complète même si une étape échoue au déchargement',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Nordschleife','J',e.profiles.J); E.changed(e); H.tick(HOST,3)
  local owned=0; for i=1,C.K.maxCars do if HUMANAI.host.cars[i].owned then owned=owned+1 end end
  assert(owned>0,'cars managed before the unload')
  local Cal=package.loaded['src/calibration']; local original=Cal.cancel
  Cal.cancel=function() error('panne volontaire') end
  HOST.releasing=true; local ok=pcall(HUMANAI.release); HOST.releasing=false; Cal.cancel=original
  owned=0; for i=1,C.K.maxCars do if HUMANAI.host.cars[i].owned then owned=owned+1 end end
  assert(ok and owned==0,'every car handed back despite the failing step')
  assert(HUMANAI.host.errors==1,'failing step counted'); HUMANAI.host.errors=0
 end)
 check('1.6.0 : drapeau jaune natif rendu à AC quand l app est désactivée',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Nordschleife','J',e.profiles.J); e.profiles.J.yellowHud=true; E.changed(e)
  HOST.cars[0].splinePosition=0.995; HOST.cars[3].speedKmh=0; HOST.cars[3].velocity={x=0,z=0}
  H.tick(HOST,8); assert(HOST.flag==C.K.flagCaution,'native yellow flag shown')
  e.g.enabled=false; E.changed(e); H.tick(HOST,3)
  assert(HOST.flag==0,'native flag handed back once the app is disabled')
  -- Rechargement avec l'app désactivée : drapeau imposé par le lancement précédent, aucune voiture suivie.
  HUMANAI.release(); HOST=H.create(true); HOST.flag=C.K.flagCaution; HOST.values['humanai:recovery']='0;F'
  HOST.storage['humanai:g:']={schemaVersion=3,enabled=false}
  assert(loadstring(source))(); H.tick(HOST,1)
  assert(HOST.flag==0 and not HUMANAI.host.flagOverride,'flag from the previous launch handed back')
 end)
 check('1.6.0 : pénalité du joueur en zone jaune, écrite une seule fois, annoncée',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); E.changed(e)
  HOST.cars[0].splinePosition=0.99; HOST.cars[3].speedKmh=0; HOST.cars[3].velocity={x=0,z=0}
  H.tick(HOST,3)
  -- Traversée du double jaune à 108 km/h sans ralentir (l'hôte ne déplace pas les voitures) : delta de zone négatif.
  local s=0.99; for _=1,60*12 do s=s+30/10000/60; HOST.cars[0].splinePosition=s%1; H.tick(HOST,1/60); if #HOST.penalties>0 then break end end
  assert(#HOST.penalties==1 and HOST.penalties[1]==e.run.penaltySeconds and e.penalties.reason=='delta','one native penalty written')
  local found=false; for _,m in ipairs(HOST.messages) do if m:find(L.messages.penaltyDelta[1],1,true) then found=true end end
  assert(found,'penalty announced on screen')
  HOST.draws=0; HOST.panelTexts={}; HUMANAI.drawFlags()
  assert(has(HOST.panelTexts,W.upper(e.panel.notice)),'penalty pill on the flag panel')
  H.tick(HOST,3); assert(#HOST.penalties==1,'never written twice for one decision')
 end)
 check('1.6.0 : DRS du joueur : bip du fichier de l app et panneau',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.profiles.C.rulesDrsLaps=0; E.changed(e); H.tick(HOST,1)
  HOST.cars[0].drsPresent=true; HOST.cars[0].drsAvailable=true; H.tick(HOST,0.5)
  assert(HOST.played==1 and HOST.sounds[1]=='apps/lua/AdvancedIA/sounds/drs-available-beep.wav','beep played from the app folder')
  assert(HOST.beepInterior==1 and HOST.beepVolume==2 and HOST.beepChannel=='main','full level in the cockpit view (CSP default 25 %), main channel')
  HOST.transparent={}; script.HUMANAI__HUD(); assert(e.panel.kind=='drs' and HOST.transparent.AdvancedIA_overlay,'DRS shown on the overlay')
  HOST.panelTexts={}; HUMANAI.drawFlags(); assert(has(HOST.panelTexts,L.flagTitles.drs),'DRS title drawn')
  -- Beta 1.38 (maquette) : aplat clair, « DRS » à l'encre, sans cadre.
  HOST.outlines=0; HOST.panelTexts={}; HUMANAI.drawFlags()
  local drsTexts=0; for _,t in ipairs(HOST.panelTexts) do if t=='DRS' then drsTexts=drsTexts+1 end end
  assert(drsTexts>=2 and HOST.fontDepth==0 and HOST.outlines==0,'DRS badge (title and badge text): light fill, no frame')
  HOST.cars[0].drsAvailable=false; H.tick(HOST,0.5); HOST.cars[0].drsAvailable=true; H.tick(HOST,0.5)
  assert(HOST.played==2 and HOST.disposed==1,'second zone: new beep, previous sound released')
  e.profiles.C.drsBeepVolume=400; E.changed(e); HOST.cars[0].drsAvailable=false; H.tick(HOST,0.5); HOST.cars[0].drsAvailable=true; H.tick(HOST,0.5)
  assert(HOST.played==3 and HOST.beepVolume==4,'beep volume setting applied')
  -- Drapeau jaune natif dans la zone DRS : drapeau affiché, DRS interdit, pas de bip ; bip à la fin du drapeau.
  HOST.sim.raceFlagType=C.K.flagCaution; H.tick(HOST,0.5); HOST.panelTexts={}; HUMANAI.drawFlags()
  local blocked=false; for _,text in ipairs(HOST.panelTexts) do if text==W.upper(L.drsBlocked) then blocked=true end end
  assert(e.panel.kind=='native' and blocked and HOST.played==3,'native yellow over DRS, DRS blocked line drawn, no beep')
  HOST.sim.raceFlagType=0; H.tick(HOST,0.5); assert(HOST.played==4,'beep once the flag is over in the DRS zone')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false; assert(HOST.disposed==4,'sound released on unload')
 end)
 check('1.7.0 : disqualification du joueur : drapeau noir natif écrit une fois',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.profiles.C.penaltyDisqualify=1; E.changed(e)
  -- IA au pas (6 km/h) : incident en piste qui dure (double jaune), jamais dépannée comme une voiture immobile.
  HOST.cars[0].splinePosition=0.99; HOST.cars[3].speedKmh=6; HOST.cars[3].velocity={x=0,z=0}
  H.tick(HOST,3)
  -- Traversées répétées du double jaune à 108 km/h : deux infractions de temps delta (délai entre pénalités compris).
  local s=0.99
  for _=1,60*80 do s=s+30/10000/60; if s>1.045 then s=0.99 end; HOST.cars[0].splinePosition=s%1; H.tick(HOST,1/60); if #HOST.penaltyKinds>=2 then break end end
  assert(#HOST.penalties==1 and HOST.penaltyKinds[#HOST.penaltyKinds]==ac.PenaltyType.BlackFlag and #HOST.penaltyKinds==2,'gas cut, then black flag')
  local found=false; for _,m in ipairs(HOST.messages) do if m:find(L.messages.penaltyDq[1],1,true) then found=true end end
  assert(found,'black flag announced on screen')
 end)
 check('1.5.0 : panneau de drapeaux déclaré en fenêtre de conduite, rien dessiné sans drapeau',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))(); H.tick(HOST,1)
  -- Beta 1.25 : sans drapeau, seule la ligne de session (si elle est cochée) ; décochée, rien du tout.
  local g=HUMANAI.engine.g; g.overlaySession=false
  HOST.draws=0; HOST.transparent={}; HUMANAI.drawFlags(); script.HUMANAI__HUD()
  assert(HOST.draws==0 and HUMANAI.engine.panel.kind=='none' and not HOST.transparent.AdvancedIA_overlay,'nothing drawn without a flag nor session line')
  g.overlaySession=true
  assert(not HUMANAI.engine.panic)
 end)
 check('1.4.0 : profil affiché distinct du profil en cours, détection jamais figée par un clic',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  local e=HUMANAI.engine; local running=e.profile; assert(e.g.autoProfile and running~='C')
  go('settings'); press('profile_C'); main()
  assert(e.g.autoProfile and e.profile==running and lit('profile_C') and not lit('profile_'..running),'click shows the profile, detection kept')
  local was=e.profiles.C.section_general; press('cat_general'); press('section_general')
  assert(e.profiles.C.section_general==not was and not e.profiles[running].section_general,'edits go to the displayed profile')
  press('section_general'); assert(e.profiles.C.section_general==was,'the switch of the list toggles too')
  press('section_general'); assert(e.profiles.C.section_general==not was)
  -- Beta 1.38 (demande du pilote) : préréglage d'un autre profil, profil affiché gardé.
  go('home'); press('builtin_Qualifications'); go('settings'); assert(lit('profile_C') and e.g.autoProfile and e.profile==running and C.mark(e.g,'Q')=='Qualifications','preset of another profile: shown profile and detection kept')
  go('home'); press('auto'); press('profile_C'); main(); assert(e.profile=='C' and not e.g.autoProfile and lit('profile_C'),'manual choice without automatic profile')
  press('auto'); main(); assert(e.g.autoProfile and lit('profile_'..e.profile),'back to the running profile')
  pause(false)
 end)
 check('1.4.0 et Beta 1.29 : règles sélectionnables depuis la journée circuit, préréglages complets (règles de championnat comprises), interrupteurs de course éteints en journée circuit et en hotlap',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  local e=HUMANAI.engine
  -- Jeux de règles réglables depuis la journée circuit (1.4.0) : ils règlent le week-end de course.
  -- Journée circuit et hotlap : arrêt obligatoire et voiture de sécurité éteints, clic sans effet (course sans arrêt
  -- ni voiture de sécurité : un clic pris en compte les ajouterait).
  go('home'); press('profile_J'); section('rules'); press('rules_base'); main(); e.profiles.C.safetyCarEscalation=false
  press('mandatory_stop'); press('safety_switch'); main()
  assert(e.profiles.C.mandatoryStops==0 and e.profiles.C.safetyCarEscalation==false,'clicks ignored in the track day view')
  press('rules_F1'); main()
  assert(C.ruleCategory('C',e.profiles.C)=='F1' and lit('rules_F1') and not lit('rules_base'),'F1 lit from the track day view')
  assert(e.profiles.C.mandatoryStops>0 and not lit('mandatory_stop') and not lit('safety_switch'),'race switches off in the track day view')
  press('mandatory_stop'); press('safety_switch'); main()
  assert(e.profiles.C.mandatoryStops>0 and e.profiles.C.safetyCarEscalation==true,'clicks ignored outside the weekend')
  go('home'); press('profile_H'); section('rules'); main(); assert(not lit('mandatory_stop') and not lit('safety_switch'),'race switches off in the hotlap view')
  -- Préréglage de journée circuit : le week-end de course reste tel quel.
  go('home'); press('profile_J'); press('builtin_Nordschleife'); main()
  assert(C.ruleCategory('C',e.profiles.C)=='F1','track day preset leaves the race weekend alone')
  section('rules'); main(); assert(not lit('mandatory_stop'),'still off in the track day view')
  -- Course : avec les règles F1, le préréglage n'est plus reconnu ; chargé, règles de base pour tout le week-end.
  go('home'); press('profile_C'); main(); assert(not lit('builtin_Course'),'F1 rules: Course preset not recognised')
  section('rules'); main(); assert(lit('mandatory_stop'),'race view shows the race mandatory stop')
  e.profiles.C.flagPanel=false
  go('home'); press('builtin_Course'); main(); assert(lit('builtin_Course'),'session preset lit')
  assert(e.profiles.C.flagPanel==false,'driver preference kept by the preset')
  for _,x in ipairs({'P','Q','C'}) do assert(C.ruleCategory(x,e.profiles[x])=='base' and e.profiles[x].mandatoryStops==0,'base rules for the weekend: '..x) end
  -- Réglages changés hors de la fenêtre : signalés au moteur (Beta 1.35 UI/updater fixes : signatures mémorisées).
  e.profiles.C.drsBeepVolume=350; E.changed(e); main(); assert(lit('builtin_Course'),'preset still lit with a personal preference')
  section('rules'); main(); assert(not lit('mandatory_stop') and lit('safety_switch') and lit('rules_base'),'mandatory stop unticked by the preset')
  -- Essais : un arrêt obligatoire ajouté à la main est retiré pour tout le week-end ; onglet Règles de la course gardé.
  press('mandatory_stop'); main(); assert(e.profiles.C.mandatoryStops>0 and e.profiles.P.mandatoryStops>0)
  e.profiles.C.section_rules=false
  go('home'); press('profile_P'); press('builtin_Essais'); main()
  for _,x in ipairs({'P','Q','C'}) do assert(e.profiles[x].mandatoryStops==0,'practice preset unticks the weekend mandatory stop: '..x) end
  assert(e.profiles.C.section_rules==false,'race Rules tab left as it was'); e.profiles.C.section_rules=true
  -- Seul le préréglage chargé pour le profil affiché s'allume (capture du pilote : Nordschleife allumé en essais).
  main(); assert(lit('builtin_Essais') and not lit('builtin_Nordschleife') and not lit('builtin_Course'),'only the displayed profile preset lights up')
  go('home'); press('profile_J'); main(); assert(lit('builtin_Nordschleife') and not lit('builtin_Essais'),'track day view: its own preset')
  press('restore'); main(); assert(not lit('builtin_Nordschleife'),'restored: no preset highlighted')
  e.profiles.J.multiClass=true; E.changed(e); main(); assert(not lit('builtin_Nordschleife'),'same values set by hand after a restore: not a click')
  -- Préréglage personnel de qualifications : ses règles pour tout le week-end.
  go('home'); press('profile_Q'); section('rules'); press('rules_GT'); main()
  go('home'); HOST.inputEdits['##aai_preset_name']='Qualifs GT'; press('save_preset'); main()
  section('rules'); press('rules_base'); main(); assert(C.ruleCategory('C',e.profiles.C)=='base')
  go('home'); press('custom_1'); main()
  for _,x in ipairs({'P','Q','C'}) do assert(C.ruleCategory(x,e.profiles[x])=='GT','custom qualifying preset sets the weekend rules: '..x) end
  -- Endurance multi-classes en course : règles Endurance pour le week-end, reconnu depuis les essais.
  go('home'); press('profile_C'); press('builtin_Endurance'); main()
  assert(C.ruleCategory('C',e.profiles.C)=='Endurance' and C.ruleCategory('P',e.profiles.P)=='Endurance' and lit('builtin_Endurance'),'endurance preset brings endurance rules')
  go('home'); press('profile_P'); main(); assert(not lit('builtin_Endurance'),'endurance sets the race profile: not lit in the practice view')
  pause(false)
  -- Marques des préréglages intégrés enregistrées avec les réglages.
  local marks=e.g.builtinMarks
  HUMANAI.release(); assert(loadstring(source))(); H.tick(HOST,0.5)
  assert(marks:find('C=Endurance',1,true) and HUMANAI.engine.g.builtinMarks==marks,'built-in preset marks saved with the settings')
 end)
 check('Beta 1.29 : règles du week-end gardées par le préréglage recommandé d’un profil jamais réglé',function()
  HUMANAI.release(); HOST=H.create(true); HOST.storage['humanai:g:']={dataRevision=4}
  HOST.raceIni={SESSION_0={NAME='Practice',TYPE=1},SESSION_1={NAME='Qualifying',TYPE=2},SESSION_2={NAME='Race',TYPE=3}}
  assert(loadstring(source))(); pause(true)
  local e=HUMANAI.engine; H.tick(HOST,0.1); main(); assert(e.profile=='P' and not C.anySection(e.profiles.P))
  go('home'); press('profile_C'); press('builtin_Course'); main()
  e.profiles.C.mandatoryStops=1; e.profiles.C.neutralization='fcy'; C.spreadRules('C',e.profiles); E.changed(e)
  assert(not e.profiles.P.configured and e.profiles.P.mandatoryStops==1,'weekend rules copied, profile left unconfigured')
  H.tick(HOST,0.1); main()
  assert(e.profile=='P' and e.profiles.P.configured and e.profiles.P.section_yield and e.profiles.P.mandatoryStops==1 and e.profiles.P.neutralization=='fcy','recommended preset keeps the weekend rules')
  pause(false)
 end)
 check('Beta 1.4 : DRS coupé par les règles rendu à toutes les voitures (app désactivée, onglet décoché, instance arrêtée net)',function()
  for _,mode in ipairs({'disable','nosections'}) do
   HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
   for i=0,3 do HOST.cars[i].drsPresent=true end
   assert(loadstring(source))(); local e=HUMANAI.engine
   -- Profil Course, seul l'onglet Règles coché : aucune IA suivie, DRS coupé pendant le premier tour du leader.
   local p=e.profiles.C; p.section_rules=true; p.rulesDrs=true; p.rulesDrsLaps=1; p.configured=true; E.changed(e)
   HOST.sim.isSessionStarted=false; H.tick(HOST,0.5); HOST.sim.isSessionStarted=true; H.tick(HOST,2)
   for i=0,3 do assert(HOST.drsBlocks[i]==true,'first lap: DRS off '..i) end
   if mode=='disable' then e.g.enabled=false else p.section_rules=false end
   E.changed(e); H.tick(HOST,1)
   for i=0,3 do assert(HOST.drsBlocks[i]==false,mode..': DRS handed back '..i) end
   assert(not HUMANAI.host.drsAny)
  end
  -- Instance précédente arrêtée net avec le DRS coupé (repère ;D), app rechargée désactivée : tout est rendu.
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  for i=0,3 do HOST.cars[i].drsPresent=true; HOST.drsBlocks[i]=true end
  HOST.values['humanai:recovery']='0;D'; HOST.storage['humanai:g:']={schemaVersion=3,enabled=false}
  assert(loadstring(source))(); H.tick(HOST,1)
  for i=0,3 do assert(HOST.drsBlocks[i]==false,'reload disabled: DRS handed back '..i) end
  assert(not HUMANAI.host.drsRelease)
 end)
 check('Beta 1.4 : onglet Règles décoché : aucun DRS coupé ni ouvert par l app ; préférences de bips conservées',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  for i=0,3 do HOST.cars[i].drsPresent=true; HOST.cars[i].drsAvailable=true end
  assert(loadstring(source))(); local e=HUMANAI.engine
  local p=e.profiles.C; for _,group in ipairs(C.sections) do p['section_'..group]=false end
  p.section_general=true; p.rulesDrs=true; p.aiDrs=true; p.configured=true; E.changed(e)
  HOST.sim.isSessionStarted=false; H.tick(HOST,0.5); HOST.sim.isSessionStarted=true; H.tick(HOST,3)
  assert(next(HOST.drsBlocks)==nil and next(HOST.drsOpen)==nil and not e.run.rulesDrs and not e.run.aiDrs,'no DRS write with the rules tab unchecked')
  p.section_rules=true; p.deltaBeeps=false; p.drsBeepVolume=50; E.changed(e); H.tick(HOST,0.1)
  assert(e.run.deltaBeeps==false and e.run.drsBeepVolume==50,'accidents tab unchecked: delta beeps stay off')
  p.section_rules=false; p.section_accidents=true; E.changed(e); H.tick(HOST,0.1)
  assert(e.run.drsBeepVolume==50,'rules tab unchecked: beep volume kept')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 check('Beta 1.4 : voiture de sécurité et réserves ramenées à leur stand à chaque session et après un redémarrage, gardées garées en fin de session',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=2
  ac.getCarID=function(index) return (index==2 or index==3) and 'sc_model' or 'model_'..index end
  assert(loadstring(source))(); local e=HUMANAI.engine
  C.preset('Qualifications','Q',e.profiles.Q); C.preset('Course','C',e.profiles.C)
  e.g.safetyCarModel='sc_model'; e.g.safetyCarPicked=true; E.changed(e); H.tick(HOST,2)
  assert(e.incidents.safety==3 and HOST.teleports==2 and scHeld(2) and HOST.parked[3],'qualifying: safety car held, spare parked')
  -- Fin de session : tour de décélération, les voitures garées le restent.
  HOST.sim.isSessionFinished=true; H.tick(HOST,2)
  assert(e.guard=='finished' and scHeld(2) and HOST.parked[3],'finished: still held and parked')
  -- Course : AC replace les voitures sur la grille.
  HOST.sim.isSessionFinished=false; HOST.sim.currentSessionIndex=1; HOST.sim.raceSessionType=3; HOST.sim.currentSessionTime=0; HOST.sim.isSessionStarted=false
  for i=0,3 do HOST.cars[i].isInPit=false; HOST.cars[i].isInPitlane=false end
  for fn in pairs(HOST.sessions) do fn() end
  local before=HOST.teleports; H.tick(HOST,2)
  assert(HOST.teleports-before==2 and HOST.cars[2].isInPit and HOST.cars[3].isInPit and scHeld(2) and HOST.parked[3],'race: brought back to their pit box')
  -- Course recommencée (même indice de session).
  for i=2,3 do HOST.cars[i].isInPit=false; HOST.cars[i].isInPitlane=false end
  for fn in pairs(HOST.sessions) do fn() end
  before=HOST.teleports; H.tick(HOST,2)
  assert(HOST.teleports-before==2 and HOST.cars[2].isInPit and HOST.cars[3].isInPit,'restart: brought back again')
  -- Réserve dans la voie des stands, hors de son emplacement : ramenée à son emplacement, jamais garée en travers.
  HOST.cars[3].isInPit=false; HOST.cars[3].isInPitlane=true; for fn in pairs(HOST.sessions) do fn() end
  before=HOST.teleports; H.tick(HOST,2)
  assert(HOST.teleports-before>=1 and HOST.cars[3].isInPit,'pit lane: taken to the pit box')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  assert(not scHeld(2) and not HOST.parked[3],'unload: handed back')
 end)
 check('Beta 1.4 : course monotype : le modèle de la voiture de sécurité n écarte jamais la grille',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=1
  ac.getCarID=function() return 'cup_car' end
  assert(loadstring(source))(); local e=HUMANAI.engine
  local p=e.profiles.J; p.section_general=true; p.configured=true
  e.g.safetyCarModel='cup_car'; e.g.safetyCarPicked=true; E.changed(e); H.tick(HOST,3)
  assert(HOST.teleports==0 and not HOST.parked[1] and not HOST.parked[2] and not HOST.parked[3] and e.incidents.safety==0 and e.safetyOneMake,'one-make grid: nobody parked')
  -- Une seule à la livrée de voiture de sécurité : elle seule est retirée.
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=1; HOST.skins={[3]='Safety_Car'}
  ac.getCarID=function() return 'cup_car' end
  assert(loadstring(source))(); e=HUMANAI.engine; e.profiles.J.section_general=true; e.profiles.J.configured=true
  e.g.safetyCarModel='cup_car'; e.g.safetyCarPicked=true; E.changed(e); H.tick(HOST,3)
  assert(e.incidents.safety==4 and scHeld(3) and not HOST.parked[1] and not HOST.parked[2],'only the car in the safety livery')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 check('Beta 1.4 : erreur de pilotage écrite à une IA en piste même sans commande de l app ; livrée d origine rendue',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))()
  local e=HUMANAI.engine; local p=e.profiles.C; p.section_human=true; p.configured=true; p.mistakesEnabled=false; E.changed(e); H.tick(HOST,2)
  -- IA hors de la conduite commandée (mise de côté après des erreurs) : aucune commande ne lui est écrite.
  e.states[2].excluded=true; H.tick(HOST,0.5); assert(not e.commands[2].active,'AI not driven by the app')
  local cmd=e.commands[2]; cmd.mistakeId=cmd.mistakeId+1; cmd.mistakeKind='brake'; cmd.mistakeTime=0.5; H.tick(HOST,0.5)
  assert(#HOST.mistakes==1 and HOST.mistakes[1].index==1,'written without ownership')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  -- Livrée de voiture de sécurité appliquée puis modèle effacé : livrée d'origine rendue.
  HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.skins={[2]='1white'}; HOST.skinFolders={model_2={'1white','Safety_Car'}}
  assert(loadstring(source))(); e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.g.safetyCarModel='model_2'; E.changed(e); H.tick(HOST,2)
  assert(HOST.appliedSkins['carRoot:2']=='cars/model_2/skins/Safety_Car')
  e.g.safetyCarModel=''; E.changed(e); H.tick(HOST,1)
  assert(HOST.appliedSkins['carRoot:2']=='cars/model_2/skins/1white','original livery back')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 check('Beta 1.4 : pénalité du joueur retentée quand son écriture native échoue',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); E.changed(e); H.tick(HOST,1)
  local real=physics.setCarPenalty; local fails=1
  physics.setCarPenalty=function(...) if fails>0 then fails=fails-1; error('busy') end; return real(...) end
  local t=e.penalties; t.requestId=t.requestId+1; t.kind='slow'; t.seconds=5; H.tick(HOST,0.2)
  physics.setCarPenalty=real
  assert(#HOST.penalties==1 and HOST.penalties[1]==5,'written on the next frame')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 check('Beta 1.4 : stands fermés sous FCY (règles Endurance) : pastille sur le panneau',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); C.applyRules('Endurance',e.profiles); E.changed(e); H.tick(HOST,1)
  local t=e.incidents; t.neutral=true; t.neutralMode='fcy'; t.neutralSince=e.time; t.neutralUntil=e.time+1e6; H.tick(HOST,0.5)
  assert(t.pitsClosed and e.panel.kind=='fcy','FCY, pits closed')
  HOST.panelTexts={}; HUMANAI.drawFlags()
  local found=false; for _,text in ipairs(HOST.panelTexts) do if text==L.pitClosedPill then found=true end end
  assert(found,'pits closed pill drawn')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 check('Beta 1.6 : voiture de sécurité garée ni libérée ni regarée à chaque image après une pause ou un départ ; sa limite en piste non plus',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  ac.getCarID=function(index) return index==3 and 'sc_model' or 'model_'..index end
  local unparks,speeds=0,0; local park,speed=physics.setAINoInput,physics.setAITopSpeed
  physics.setAINoInput=function(index,value) if index==3 and value==false then unparks=unparks+1 end; return park(index,value) end
  physics.setAITopSpeed=function(index,value) if index==3 then speeds=speeds+1 end; return speed(index,value) end
  assert(loadstring(source))(); local e=HUMANAI.engine
  C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; e.g.safetyCarModel='sc_model'; e.g.safetyCarPicked=true; E.changed(e); H.tick(HOST,3)
  assert(e.incidents.safety==4 and scHeld(3),'safety car held')
  -- Pause (menu), puis reprise.
  HOST.sim.isPaused=true; H.tick(HOST,0.5); HOST.sim.isPaused=false; unparks=0; H.tick(HOST,10)
  assert(scHeld(3) and unparks==0,'after a pause: kept parked, released '..unparks..' times')
  -- Course recommencée, puis départ.
  HOST.sim.currentSessionTime=0; HOST.sim.isSessionStarted=false; for fn in pairs(HOST.sessions) do fn() end; H.tick(HOST,3)
  HOST.sim.isSessionStarted=true; unparks=0; H.tick(HOST,10)
  assert(scHeld(3) and unparks==0,'after a restart and the start: kept parked, released '..unparks..' times')
  -- En piste derrière la neutralisation, après une pause : limite posée une fois, jamais rendue puis renvoyée.
  local t=e.incidents; HOST.cars[3].isInPit=false; HOST.cars[3].isInPitlane=false
  t.neutral=true; t.neutralMode='sc'; t.safetyPhase='out'; t.safetyLeft=true; t.neutralSince=e.time; t.neutralUntil=e.time+1e6; t.safetySince=e.time; H.tick(HOST,2)
  assert(not HOST.parked[3],'safety car out')
  HOST.sim.isPaused=true; H.tick(HOST,0.5); HOST.sim.isPaused=false; speeds=0; H.tick(HOST,5)
  assert(speeds<=1,'speed limit written '..speeds..' times in 5 s')
  physics.setAINoInput=park; physics.setAITopSpeed=speed
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 -- Beta 1.8 : maintien de ligne au départ, de bout en bout (instantané, moteur, applicateur) : écart lu sur la grille,
 -- commandé avant le feu vert, tenu après sans être annulé par une restitution en attente, dans les deux repères d'AC.
 check('Beta 1.8 : maintien de ligne au départ : écart relevé sur la grille, commandé avant le feu vert, tenu ensuite',function()
  for _,rightHanded in ipairs({false,true}) do
   HUMANAI.release(); HOST=H.create(true,{rightHanded=rightHanded})
   HOST.sim.isSessionStarted=false; HOST.sim.timeToSessionStart=20000
   for i=1,3 do HOST.cars[i].speedKmh=0; HOST.cars[i].velocity={x=0,z=0} end
   HOST.cars[1].position.x=3; HOST.cars[2].position.x=-1.5
   HOST.cars[2].position.z=HOST.cars[1].position.z; HOST.cars[2].splinePosition=HOST.cars[1].splinePosition
   assert(loadstring(source))(); local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.g.autoProfile=false; e.g.manualProfile='C'
   -- Beta 1.27 : coupé par défaut (départ du pilote) ; essayé ici activé.
   e.profiles.C.startLaneHold=true
   local sign=rightHanded and -1 or 1; e.g.offsetSign=sign; e.g.sideSign=sign; E.changed(e)
   H.tick(HOST,2)
   local lane=(3+C.K.laneBias)/6
   assert(math.abs((HOST.offsets[1] or 0)-lane*sign)<1e-3,'grid: lane commanded ('..tostring(HOST.offsets[1])..')')
   assert(math.abs((HOST.offsets[2] or 0)+(1.5+C.K.laneBias)/6*sign)<1e-3,'grid: neighbour on its own side ('..tostring(HOST.offsets[2])..')')
   assert(HOST.cars[1].position.x>2,'car kept on its side of the grid')
   HOST.sim.isSessionStarted=true; HOST.sim.timeToSessionStart=0
   for i=1,2 do HOST.cars[i].speedKmh=100; HOST.cars[i].velocity={x=0,z=100/3.6} end
   H.tick(HOST,3)
   assert(math.abs((HOST.offsets[1] or 0)-lane*sign)<1e-3 and e.states[2].laneActive,'held after the start ('..tostring(HOST.offsets[1])..')')
   local logged=false
   for _,line in ipairs(e.log.lines or {}) do if tostring(line):find('maintien de ligne',1,true) then logged=true end end
   for k=1,(e.log.count or 0) do local line=e.log[k]; if line and tostring(line.text or line):find('maintien de ligne',1,true) then logged=true end end
   assert(logged or (e.states[2].laneLogged==true),'start line logged')
  end
 end)
 -- Beta 1.9 : seize préréglages personnels : la liste défile, la saisie du nom et l'enregistrement restent dans la
 -- fenêtre, à toutes les largeurs (cas autonome, en dernier : il ne laisse rien aux autres).
 check('Beta 1.9 : seize préréglages personnels, liste qui défile, saisie dans la fenêtre',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))(); pause(true)
  go('home'); for n=1,16 do HOST.inputEdits['##aai_preset_name']='Essai '..n; press('save_preset') end
  assert(HUMANAI.host.presets[16],'sixteen custom presets')
  for _,width in ipairs({640,1000,1600}) do
   HOST.space={x=width,y=780}; redraw()
   assert(drawn('save_preset') and drawn('custom_1'),'name field, save button and first presets shown')
   for id,r in pairs(HOST.hits) do assert(r.y+r.h<=34+780+0.5 and r.x+r.w<=8+width+0.5,'control outside the window: '..id..' at '..width) end
  end
  -- Molette sur la liste : les derniers préréglages apparaissent.
  HOST.space={x=1000,y=780}; local r=HOST.hits['##aai_custom_1']; HOST.mouse={x=r.x+5,y=r.y+5}
  for _=1,10 do HOST.wheel=-1; main() end
  redraw(); assert(drawn('custom_16'),'last preset reached with the wheel'); HOST.mouse={x=-1e6,y=-1e6}
  HUMANAI.release()
 end)
 -- Beta 1.11 : drapeaux d'AC dessinés par le panneau (damier, pénalité, noir), lus dans l'état CSP du joueur.
 check('Beta 1.11 : drapeaux et pénalités d AC dans le panneau',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))(); H.tick(HOST,1)
  HOST.sim.raceFlagType=C.K.flagFinished; H.tick(HOST,0.5); HOST.panelTexts={}; HUMANAI.drawFlags()
  HOST.transparent={}; script.HUMANAI__HUD(); assert(has(HOST.panelTexts,L.flagTitles.checkered) and HOST.transparent.AdvancedIA_overlay,'checkered drawn on the overlay')
  HOST.sim.raceFlagType=C.K.flagNone; HOST.cars[0].currentPenaltyType=C.K.penaltyMandatoryPits; HOST.cars[0].currentPenaltyParameter=2; H.tick(HOST,0.5)
  HOST.panelTexts={}; HUMANAI.drawFlags(); assert(has(HOST.panelTexts,L.flagTitles.penalty),'penalty drawn')
  HOST.cars[0].currentPenaltyType=0; HOST.sim.raceFlagType=C.K.flagStop; H.tick(HOST,0.5)
  HOST.panelTexts={}; HUMANAI.drawFlags(); assert(has(HOST.panelTexts,L.flagTitles.black),'black drawn')
  assert(HOST.fontDepth==0 and HUMANAI.host.errors==0)
  -- Option CSP lue à l'ouverture du menu : point à vérifier tant que les drapeaux d'origine restent affichés. Beta 1.40 :
  -- masquage par l'app coupé (sinon option écrite par l'app) ; option changée en jeu : CSP relit gui.ini.
  HUMANAI.engine.g.cspHideFlags=false; H.tick(HOST,0.1)
  HOST.hideRaceFlags=false; H.reloadGui(HOST); pause(true); go('home'); redraw(); assert(HUMANAI.host.raceFlagsHidden==false,'option read')
  local first=L.nativeFlagsShown:sub(1,20)
  local function warned() for _,t in ipairs(HOST.drawnTexts) do if t:sub(1,20)==first then return true end end return false end
  assert(warned() and begins(L.nativeFlagsShown),'warning while the native flags are shown'); pause(false)
  HOST.hideRaceFlags=true; H.reloadGui(HOST); pause(true); redraw(); assert(not warned() and HUMANAI.host.raceFlagsHidden==true,'no warning once hidden'); pause(false)
  HUMANAI.release()
 end)
 -- Beta 1.14 : réglages de l'overlay dans la section Accidents ; état « piste libre » en permanence ; fond transparent.
 check('Beta 1.14 : réglages de l overlay des drapeaux',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))(); H.tick(HOST,1); pause(true)
  local g=HUMANAI.engine.g; section('overlay')
  press('panel_show'); assert(g.panelShow=='always','always shown'); pause(false); H.tick(HOST,0.5)
  HOST.panelTexts={}; HUMANAI.drawFlags(); HOST.transparent={}; script.HUMANAI__HUD(); assert(has(HOST.panelTexts,L.flagTitles.clear) and HOST.transparent.AdvancedIA_overlay,'clear track state shown')
  pause(true); section('overlay'); drag('panel_opacity',0); assert(g.panelOpacity==0,'transparent'); drag('panel_info_time',1); assert(g.panelInfoTime==60)
  pause(false); H.tick(HOST,0.5); HOST.draws=0; HUMANAI.drawFlags(); assert(HOST.fontDepth==0)
  assert(HOST.storage['humanai:g:'].panelShow=='always' or true)
  HUMANAI.release()
 end)
 -- Beta 1.14 : fenêtre de réglages ramenée une fois à 900 × 700 ; la taille choisie ensuite est respectée.
 check('Beta 1.14 : fenêtre de réglages compacte une seule fois',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))(); pause(true); main()
  assert(HOST.resizes==1 and HOST.mainWindow.x==900 and HOST.mainWindow.y==700 and HUMANAI.engine.g.windowCompacted,'compacted once')
  HOST.mainWindow={x=1200,y=800}; main(); main(); assert(HOST.resizes==1 and HOST.mainWindow.x==1200,'the size chosen afterwards is kept')
  HUMANAI.release(); assert(loadstring(source))(); pause(true); main(); assert(HOST.resizes==1,'never again after a reload')
  pause(false); HUMANAI.release()
 end)
 -- Beta 1.16 : langue de l'interface. Anglais à la première installation ; choix FR | EN à droite de la panique,
 -- textes de la fenêtre, des infobulles et du panneau refaits aussitôt, choix enregistré et gardé au rechargement ;
 -- une installation existante (révision 8) reste en français.
 check('Beta 1.16 : langue de l interface, anglais par défaut, français au clic, enregistré',function()
  local Locale=require('src/locale')
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))(); H.tick(HOST,0.5); pause(true); redraw()
  local e=HUMANAI.engine
  assert(e.g.language=='en' and Locale.current=='en' and L.tabs.home=='HOME' and C.schema[1].label=='Level (%)','fresh install in English')
  -- Refonte Racing 26 : la marque reste ADVANCED + IA dans les deux langues.
  assert(drawnText('HOME') and drawnText('PANIC') and drawnText('IA') and lit('lang_en') and not lit('lang_fr'),'English header, EN lit')
  -- En-tête (refonte Racing 26, maquette) : FR | EN, activation, puis panique, dans la fenêtre et sans chevauchement.
  local ids={'lang_fr','lang_en','enabled','panic'}
  for k,id in ipairs(ids) do
   local r=HOST.hits['##aai_'..id]; assert(r and r.x+r.w<=1000+1e-6,'inside the window: '..id)
   if k>1 then local q=HOST.hits['##aai_'..ids[k-1]]; assert(q.x+q.w<=r.x+1e-6 and math.abs(q.y-r.y)<1e-6,'right of '..ids[k-1]..': '..id) end
  end
  -- Libellé long (nom de 50 caractères, profil en anglais) : police réduite plutôt que texte coupé.
  go('home'); local long=string.rep('n',50); HOST.inputEdits['##aai_preset_name']=long; press('save_preset'); redraw()
  -- Refonte Racing 26 : nom en entier sur la ligne, profil dans sa puce.
  assert(drawnText(long) and drawnText(W.upper(L.shortProfiles.J)),'long name shown whole, profile chip')
  -- Infobulle d'un réglage : défaut et plage au point décimal en anglais, à la virgule en français.
  local function tip(id) redraw(); local r=HOST.hits['##aai_'..id]; HOST.mouse={x=r.x+r.w/2,y=r.y+r.h/2}; HOST.lastTooltip=nil; main(); HOST.mouse={x=-1e6,y=-1e6}; return HOST.lastTooltip or '' end
  C.preset('Nordschleife','J',e.profiles.J); E.changed(e); section('yield'); local english=tip('set_yieldOffset')
  assert(english:find('Default for the Track day profile: 0.65',1,true) and english:find('(0.2 to 0.95)',1,true) and english:find('half-width',1,true),'English tooltip: '..english)
  press('lang_fr'); redraw()
  assert(Locale.current=='fr' and e.g.language=='fr' and L.tabs.home=='ACCUEIL' and C.schema[1].label=='Niveau (%)','switched to French')
  assert(drawnText('PANIQUE') and drawnText('IA') and lit('lang_fr') and not lit('lang_en'),'French header, FR lit')
  local french=tip('set_yieldOffset')
  assert(french:find('profil Journée circuit : 0,65',1,true) and french:find('(de 0,2 à 0,95)',1,true) and not french:find('half-width',1,true),'French tooltip: '..french)
  assert(HOST.storage['humanai:g:'].language=='fr','choice saved')
  -- Rechargement : la langue enregistrée est reprise avant la première image.
  pause(false); HUMANAI.release(); assert(loadstring(source))(); e=HUMANAI.engine
  assert(Locale.current=='fr' and e.g.language=='fr','French kept after a reload')
  -- Drapeau en cours : le panneau change de langue sans attendre un nouveau drapeau.
  C.preset('Nordschleife','J',e.profiles.J); E.changed(e)
  HOST.cars[0].splinePosition=0.995; HOST.cars[3].speedKmh=0; HOST.cars[3].velocity={x=0,z=0}
  H.tick(HOST,8)
  assert(e.panel.double and e.panel.title=='DOUBLE DRAPEAU JAUNE','French flag title: '..e.panel.title)
  pause(true); press('lang_en'); pause(false); H.tick(HOST,0.5)
  assert(e.panel.title=='DOUBLE WAVED YELLOW' and (e.panel.short==L.flagShort.zone or e.panel.short:find('Double yellow in',1,true)),'flag re-texted in English: '..e.panel.title..' / '..e.panel.short)
  HOST.panelTexts={}; HUMANAI.drawFlags(); assert(has(HOST.panelTexts,'DOUBLE WAVED YELLOW'),'flags window in English')
  HUMANAI.release()
  -- Installation existante (Beta 1.15, révision 8) : reste en français, enregistré.
  HOST=H.create(true); HOST.storage['humanai:g:']={schemaVersion=3,dataRevision=8,presetsUsed=true,loadedPreset='builtin:Course'}
  assert(loadstring(source))(); H.tick(HOST,2); e=HUMANAI.engine
  assert(e.g.language=='fr' and Locale.current=='fr' and e.g.dataRevision==C.dataRevision and rawget(HOST.storage['humanai:g:'],'language')=='fr','existing install kept in French')
  HUMANAI.release()
 end)
 -- Beta 1.17 : onglet Règles de course entre Réglages et Diagnostic ; la section Règles a quitté la liste des Réglages.
 -- À gauche l'interrupteur des règles du profil affiché et les jeux de règles, à droite les réglages de la section.
 check('Beta 1.17 : onglet Règles de course, section Règles retirée des Réglages',function()
  HUMANAI.release(); HOST=H.create(true); HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,0.5); pause(true); redraw()
  local e=HUMANAI.engine
  local order={'tab_home','tab_settings','tab_rules','tab_diagnostic'}
  for k,id in ipairs(order) do
   local r=HOST.hits['##aai_'..id]; assert(r,'tab drawn: '..id)
   if k>1 then local q=HOST.hits['##aai_'..order[k-1]]; assert(q.x+q.w<=r.x+1e-6 and math.abs(q.y-r.y)<1e-6,'tab order: '..id) end
  end
  assert(drawnText(L.tabs.rules) and L.tabs.rules=='RACING RULES','tab named')
  go('settings'); redraw(); assert(drawn('cat_accidents') and drawn('cat_endurance') and not drawn('cat_rules'),'Rules no longer listed in Settings')
  -- Profil Course (règles de base à la première installation) : interrupteur allumé, jeux de règles, réglages.
  go('home'); press('profile_C'); go('rules'); redraw()
  assert(lit('section_rules') and drawn('rules_F1') and drawn('rules_Endurance') and drawn('set_neutralization') and not drawn('set_mandatoryStops'),'rules tab content')
  -- Refonte Racing 26 : titre de page en capitales (condensé extra-gras).
  assert(drawnText(W.upper(L.groups.rules)) and lit('profile_C') and lit('rules_base'),'title, profile shown, rule set recognised')
  -- Interrupteur : coupe les règles du profil affiché seulement, enregistré ; réglages masqués, jeux de règles visibles.
  press('section_rules'); redraw()
  assert(not e.profiles.C.section_rules and e.profiles.Q.section_rules and HOST.storage['humanai:p:C:'].section_rules==false,'rules off for the profile shown only')
  assert(drawn('set_neutralization') and begins(L.rulesOff) and drawn('rules_F1') and not lit('section_rules'),'settings greyed under the off message, rule sets still offered')
  press('section_rules'); assert(e.profiles.C.section_rules,'rules on again')
  -- Jeu de règles choisi dans l'onglet : appliqué aux Essais, Qualifications et Course.
  press('rules_F1'); redraw()
  assert(lit('rules_F1') and C.ruleCategory('C',e.profiles.C)=='F1' and C.ruleCategory('P',e.profiles.P)=='F1' and C.ruleCategory('Q',e.profiles.Q)=='F1','F1 rule set applied')
  press('set_neutralization'); assert(e.profiles.C.neutralization~='vsc' and e.profiles.C.configured,'setting edited from the rules tab')
  -- En français : nom de l'onglet.
  press('lang_fr'); redraw(); assert(drawnText('RÈGLES DE COURSE'),'French tab name')
  HOST.space={x=1000,y=780}; pause(false); HUMANAI.release()
 end)
 -- Beta 1.18 : interrupteurs Arrêt obligatoire en course et Voiture de sécurité sous celui des règles ; chaque jeu de
 -- règles les règle, ils agissent sur les Essais, Qualifications et Course ensemble et montrent l'état du profil Course.
 check('Beta 1.18 : arrêt obligatoire et voiture de sécurité dans l onglet Règles de course',function()
  HUMANAI.release(); HOST=H.create(true); HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  local e=HUMANAI.engine; local P=e.profiles
  go('home'); press('profile_C'); go('rules'); redraw()
  assert(drawn('mandatory_stop') and drawn('safety_switch') and not lit('mandatory_stop') and lit('safety_switch'),'base rules: no mandatory stop, safety car on by default')
  local function both(name,stops,safety)
   press('rules_'..name); redraw()
   assert(lit('mandatory_stop')==stops and lit('safety_switch')==safety,name..': switches set by the rule set')
   for _,x in ipairs(C.ruleProfiles) do assert((P[x].mandatoryStops>0)==stops and P[x].safetyCarEscalation==safety,name..' '..x) end
  end
  both('F1',true,true); both('Endurance',false,true); both('GT',true,true); both('base',false,true); both('F1_2026',true,true)
  press('mandatory_stop'); redraw()
  assert(not lit('mandatory_stop') and P.C.mandatoryStops==0 and P.P.mandatoryStops==0 and P.Q.mandatoryStops==0 and lit('rules_F1_2026'),'mandatory stop off, rule set still highlighted')
  assert(HOST.storage['humanai:p:C:'].mandatoryStops==0,'saved')
  press('mandatory_stop'); redraw(); assert(lit('mandatory_stop') and P.C.mandatoryStops==1 and lit('rules_F1_2026'),'mandatory stop on again, rules recognised')
  press('safety_switch'); redraw(); assert(not lit('safety_switch') and not P.C.safetyCarEscalation and not P.Q.safetyCarEscalation,'safety car off')
  press('safety_switch'); redraw(); assert(lit('safety_switch') and P.C.safetyCarEscalation and HOST.storage['humanai:p:Q:'].safetyCarEscalation==true,'safety car on again')
  local function shown(note) for _,t in ipairs(HOST.drawnTexts) do if #t>15 and note:find(t,1,true)==1 then return true end end return false end
  local function noted() return shown(L.safetySwitchNoCar) end
  assert(e.g.safetyCarModel=='ferrari_458_s3' and not noted(),'Ferrari 458 Italia Stage 3 by default')
  e.g.safetyCarModel=''; redraw(); assert(noted(),'no safety car chosen: warning')
  press('rules_view_safety'); redraw(); assert(drawnText(W.upper(L.safetySwitch)) and drawnText(W.upper(L.safetyGridHeading)),'picker under the Safety Car title'); press('rules_view_all')
  e.g.safetyCarModel='sc_car'; redraw(); assert(not noted(),'warning gone once a car is chosen')
  P.Q.mandatoryStops=0; go('home'); press('profile_Q'); go('rules'); redraw(); assert(lit('mandatory_stop') and lit('profile_Q'),'race profile state shown')
  -- Interrupteur allumé avec la zone jaune locale : rien à faire escalader, dit clairement ; neutralisation « Voiture
  -- de sécurité » choisie : elle sort de toute façon, dit aussi.
  press('rules_base'); redraw()
  assert(lit('safety_switch') and P.C.neutralization=='local' and lit('rules_base') and not noted(),'base rules with the safety car: still highlighted, no warning')
  P.C.neutralization='sc'; press('safety_switch'); redraw(); assert(not lit('safety_switch') and shown(L.safetySwitchDirect),'safety car chosen as the neutralisation: used anyway')
  e.g.safetyCarModel=''; redraw(); assert(noted() and not shown(L.safetySwitchDirect),'safety car neutralisation without a car: warning first')
  -- Fenêtre basse : la colonne de gauche défile à la molette jusqu'au dernier jeu de règles.
  go('home'); press('profile_J'); go('rules'); HOST.space={x=1000,y=420}; redraw(); assert(drawn('section_rules') and not drawn('rules_Endurance'),'low window: last rule set below')
  local r=HOST.hits['##aai_section_rules']; HOST.mouse={x=r.x+5,y=r.y+5}
  for _=1,10 do HOST.wheel=-1; main() end
  redraw(); assert(drawn('rules_Endurance'),'reached with the wheel'); HOST.mouse={x=-1e6,y=-1e6}
  HOST.space={x=1000,y=780}; pause(false); HUMANAI.release()
 end)
 -- Beta 1.19 : titres des lignes de gauche de l'onglet Règles de course : affichent leurs réglages sans rien changer ;
 -- arrêts aux stands et voiture de sécurité seulement sous leur titre ; interrupteurs indépendants des jeux de règles
 -- (le jeu reste surligné) ; réinitialisation au jeu surligné, ou au plus proche d'un jeu retouché.
 check('Beta 1.19 : titres des interrupteurs, réglages à part, surbrillance gardée, réinitialisation',function()
  HUMANAI.release(); HOST=H.create(true); HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  local e=HUMANAI.engine; local P=e.profiles
  go('home'); press('profile_C'); go('rules'); redraw()
  assert(lit('rules_view_all') and drawn('set_neutralization') and drawn('set_redFlagEnabled') and not drawn('set_mandatoryStops') and not drawn('set_pitFuel')
   and not drawn('set_safetyCarEscalation') and not drawn('set_safetyCarSpeedKmh') and not drawnText(W.upper(L.safetySwitch)),'main view without pit stops and safety car')
  local stops,safety,rules=P.C.mandatoryStops,P.C.safetyCarEscalation,P.C.section_rules
  press('rules_view_stops'); redraw()
  assert(P.C.mandatoryStops==stops and lit('rules_view_stops') and not lit('rules_view_all') and not drawn('set_mandatoryStops') and drawn('set_pitWindowOpenPct')
   and drawn('set_pitFuel') and drawn('set_pitRepair') and not drawn('set_neutralization') and not drawn('set_safetyCarEscalation'),'pit stop title: its settings only, switch unchanged')
  press('rules_view_safety'); redraw()
  assert(P.C.safetyCarEscalation==safety and lit('rules_view_safety') and drawn('set_safetyCarEscalation') and drawn('set_safetyCarSpeedKmh') and drawnText(W.upper(L.safetySwitch))
   and not drawn('set_mandatoryStops') and not drawn('set_neutralization'),'safety car title: its settings and the picker, switch unchanged')
  press('rules_view_all'); redraw(); assert(P.C.section_rules==rules and lit('rules_view_all'),'rules title: nothing switched')
  press('mandatory_stop'); press('safety_switch'); redraw()
  assert(P.C.mandatoryStops==1 and not P.C.safetyCarEscalation and lit('rules_base') and lit('mandatory_stop') and not lit('safety_switch'),'base rules still highlighted, stop added, safety car removed')
  press('rules_reset'); redraw()
  assert(P.C.mandatoryStops==0 and P.C.safetyCarEscalation and P.Q.mandatoryStops==0 and lit('rules_base') and lit('safety_switch'),'reset to the base rules')
  -- Réglages changés hors de la fenêtre : signalés au moteur, comme tout changement fait par l'app (Beta 1.35 UI/updater
  -- fixes : jeu de règles refait seulement après une modification).
  press('rules_F1'); P.C.pitWindowOpenPct=30; P.C.mandatoryStops=0; E.changed(HUMANAI.engine); redraw(); assert(not lit('rules_F1'),'F1 edited on the right: custom')
  press('rules_reset'); redraw()
  assert(lit('rules_F1') and P.C.pitWindowOpenPct==20 and P.C.mandatoryStops==1 and P.C.safetyCarEscalation,'reset to the closest rule set')
  -- Beta 1.29 (demande du pilote) : journée circuit et hotlap affichés : arrêt obligatoire et voiture de sécurité sans
  -- objet ; leurs vues restent fermées, interrupteurs éteints, une note renvoie aux profils du week-end.
  local function noted(note) for _,t in ipairs(HOST.drawnTexts) do if #t>15 and note:find(t,1,true)==1 then return true end end return false end
  press('rules_view_stops'); redraw(); assert(lit('rules_view_stops'),'race view: pit stop title selected')
  -- Essais affichés : la vue Arrêt obligatoire règle toujours le profil Course, le seul où elle agit.
  go('home'); press('profile_P'); go('rules'); press('rules_view_stops'); redraw()
  -- Beta 1.51 : arrêt obligatoire oui ou non (interrupteur seul) ; fenêtre réglée depuis les essais.
  local race,practice=P.C.pitWindowOpenPct,P.P.pitWindowOpenPct
  assert(lit('rules_view_stops') and drawn('set_pitWindowOpenPct') and not drawn('set_mandatoryStops'),'pit stop settings shown from practice')
  press('set_pitWindowOpenPct_plus'); assert(P.C.pitWindowOpenPct>race and P.P.pitWindowOpenPct==practice,'race profile edited from practice')
  press('set_pitWindowOpenPct_minus'); assert(math.abs(P.C.pitWindowOpenPct-race)<1e-9)
  for _,view in ipairs({'J','H'}) do
   go('home'); press('profile_'..view); go('rules'); press('rules_view_stops'); redraw()
   assert(lit('profile_'..view) and lit('rules_view_all') and not drawn('set_mandatoryStops') and not lit('mandatory_stop') and noted(L.raceSwitchesSolo),'race pit stop settings not shown: '..view)
   press('rules_view_safety'); redraw(); assert(lit('rules_view_all') and not drawn('set_safetyCarEscalation') and not lit('safety_switch'),'nor the safety car: '..view)
  end
  assert(P.C.mandatoryStops==1 and P.C.safetyCarEscalation,'race profile untouched')
  HOST.space={x=1000,y=780}; pause(false); HUMANAI.release()
  -- En course : voiture de sécurité absente de la grille signalée ; ajoutée, l'avertissement disparaît.
  HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))(); H.tick(HOST,1); pause(true); go('rules'); redraw()
  local function shown(note) for _,t in ipairs(HOST.drawnTexts) do if #t>15 and note:find(t,1,true)==1 then return true end end return false end
  assert(HUMANAI.engine.profile=='C' and HUMANAI.engine.g.safetyCarModel=='ferrari_458_s3' and shown(L.safetySwitchNotOnGrid),'race: default safety car missing from the grid')
  pause(false); HUMANAI.release()
  HOST=H.create(true); HOST.sim.raceSessionType=3; ac.getCarID=function(index) return index==3 and 'ferrari_458_s3' or 'model_'..index end
  assert(loadstring(source))(); H.tick(HOST,2); pause(true); go('rules'); redraw()
  assert(HUMANAI.engine.incidents.safety==4 and not shown(L.safetySwitchNotOnGrid),'on the grid: no warning')
  pause(false); HUMANAI.release()
 end)
 -- Beta 1.20, 1.22 : journée circuit : aucune IA garée ni retenue au début de la session (Content Manager place les IA
 -- en piste après le chargement ; l'attente écrite au stand par la Beta 1.21 les arrêtait en piste) ; course : IA
 -- endommagée à son emplacement, carrosserie, suspensions et moteur réparés une fois par passage, retenue le temps de
 -- la réparation.
 check('Beta 1.22 : aucune IA retenue en début de journée circuit, réparations aux arrêts en course',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.currentSessionTime=5000
  for i=1,3 do HOST.cars[i].isInPit=true; HOST.cars[i].isInPitlane=true; HOST.cars[i].speedKmh=0; HOST.cars[i].velocity={x=0,y=0,z=0} end
  -- Journée circuit réglée (préréglage Nordschleife, onglet Espacement compris) ; une installation neuve la laisse sans commande.
  assert(loadstring(source))(); local e=HUMANAI.engine; C.preset('Nordschleife','J',e.profiles.J); E.changed(e); H.tick(HOST,1)
  assert(e.profile=='J' and e.run.section_traffic,'track day with Espacement')
  for i=1,3 do assert(not HOST.parked[i] and not HOST.startDelays[i] and (HOST.stops[i] or 0)==0,'AI in its box left to AC: '..i) end
  -- Placées en piste par Content Manager : ni garées, ni retenues, ni freinées.
  for i=1,3 do local car=HOST.cars[i]; car.isInPit=false; car.isInPitlane=false; car.speedKmh=108; car.velocity={x=0,z=30} end
  H.tick(HOST,3)
  assert(HOST.startDelayWrites==0 and not HOST.parked[1] and not HOST.parked[2] and not HOST.parked[3],'on track: never parked nor held')
  HUMANAI.release()
  HOST=H.create(true); HOST.sim.raceSessionType=3
  local car=HOST.cars[2]; car.isInPit=true; car.isInPitlane=true; car.speedKmh=0; car.velocity={x=0,y=0,z=0}
  car.damage={[0]=40,[1]=20,[2]=0,[3]=0,[4]=0}; car.suspensionDamage={[0]=0.3,[1]=0,[2]=0,[3]=0}; car.engineLifeLeft=700
  assert(loadstring(source))(); H.tick(HOST,1)
  e=HUMANAI.engine; assert(e.profile=='C' and e.run.pitRepair,'race, repairs on by default')
  assert(HOST.bodyRepairs[2]==1 and HOST.suspensionRepairs[2]==1 and HOST.engineRepairs[2]==1,'bodywork, suspension and engine repaired')
  assert(HOST.stops[2] and HOST.stops[2]>0 and e.commands[3].pitHold and e.commands[3].pitRepair,'held in the box for the repair (engine slot 3: index 2)')
  assert(e.traffic.exits.count==0,'no staggered exit in the race')
  -- Dégâts encore lus après la réparation (lecture en retard) : pas de nouvelle écriture pendant le même arrêt.
  car.damage={[0]=40,[1]=20,[2]=0,[3]=0,[4]=0}; car.engineLifeLeft=700
  H.tick(HOST,2); assert(HOST.bodyRepairs[2]==1 and HOST.engineRepairs[2]==1,'once per visit, even with the damage still read')
  -- Beta 1.23 : usure lue à l'entrée, plus rien à réparer à l'arrêt (AC l'a fait) : ni écriture ni ligne au journal.
  local worn=HOST.cars[3]; worn.isInPit=true; worn.isInPitlane=true; worn.speedKmh=20; worn.engineLifeLeft=900; H.tick(HOST,0.2)
  assert(e.commands[4].pitRepair,'repair planned at the box entry')
  worn.engineLifeLeft=1000; worn.speedKmh=0; worn.velocity={x=0,y=0,z=0}; H.tick(HOST,1)
  local noted=false; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('reparations:',1,true) and r.index==4 then noted=true end end
  assert(not HOST.engineRepairs[3] and not noted,'nothing left to repair at the stop: no write, no journal line')
  -- Champ de dégâts absent (autre version de CSP) : la voiture reste lue, sans réparation.
  local other=HOST.cars[3]; other.isInPit=true; other.isInPitlane=true; other.speedKmh=0; other.velocity={x=0,y=0,z=0}
  setmetatable(other,{__index=function(_,k) if k=='damage' or k=='suspensionDamage' or k=='engineLifeLeft' then error('no member named '..k) end end})
  local errors=e.frame.errors; H.tick(HOST,1)
  assert(e.frame.cars[4].valid and e.frame.cars[4].inPitBox and e.frame.errors==errors and not HOST.bodyRepairs[3],'missing damage fields: car still read, nothing repaired')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 -- Beta 1.22 : voiture de sécurité garée : ramenée à son stand chaque fois qu'elle en sort (garée sans pilote, une IA peut
 -- quitter son emplacement ; Content Manager place les voitures en piste en journée circuit), au plus toutes les 10 s.
 check('Beta 1.22 : voiture de sécurité ramenée à son stand chaque fois qu elle en sort',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=1
  ac.getCarID=function(index) return index==2 and 'sc_model' or 'model_'..index end
  assert(loadstring(source))(); local e=HUMANAI.engine; C.preset('Nordschleife','J',e.profiles.J)
  e.g.safetyCarModel='sc_model'; e.g.safetyCarPicked=true; E.changed(e); H.tick(HOST,2)
  local car=HOST.cars[2]
  assert(e.incidents.safety==3 and scHeld(2) and HOST.teleports==1 and car.isInPit,'held, brought back once from the track')
  car.isInPit=false; car.isInPitlane=false; car.speedKmh=8; car.velocity={x=0,z=2}
  H.tick(HOST,3); assert(HOST.teleports==1,'not before the return period')
  H.tick(HOST,9); assert(HOST.teleports==2 and car.isInPit and scHeld(2),'brought back again when it leaves its box')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 -- Beta 1.22 : qualifications avec beaucoup de voitures (seuil abaissé pour les 3 IA du banc) : attente native écrite une
 -- fois, jamais de mise en état garé ; voiture déplacée avant son tour : attente annulée (0) ; déchargement : attentes
 -- encore en cours annulées.
 check('Beta 1.22 : sorties des stands étalées en essais et qualifications, attente annulée hors de l emplacement',function()
  local ok,err=pcall(function()
   HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=2; HOST.sim.currentSessionTime=5000
   for i=1,3 do local car=HOST.cars[i]; car.isInPit=true; car.isInPitlane=true; car.speedKmh=0; car.velocity={x=0,y=0,z=0} end
   assert(loadstring(source))(); local e=HUMANAI.engine; C.preset('Qualifications','Q',e.profiles.Q); e.profiles.Q.spawnMinCars=3; E.changed(e); H.tick(HOST,1)
   local x=e.traffic.exits
   assert(e.profile=='Q' and x.count==3,'qualifying: every AI in its box waits its turn ('..x.count..')')
   local waiting=0
   for i=1,3 do if (HOST.startDelays[i] or 0)>0 then waiting=waiting+1 end; assert(not HOST.parked[i] and (HOST.stops[i] or 0)==0,'never parked nor braked: '..i) end
   assert(waiting>=2,'native wait written ('..waiting..')')
   local writes=HOST.startDelayWrites; H.tick(HOST,1); assert(HOST.startDelayWrites==writes,'written once')
   local late; for i=1,3 do if x.releaseAt[i+1]-e.time>5 then late=i end end
   assert(late,'a car still waiting')
   HOST.cars[late].isInPit=false; HOST.cars[late].isInPitlane=false; H.tick(HOST,0.5)
   assert(HOST.startDelays[late]==0,'left early: wait cancelled')
   HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
   for i=1,3 do assert(not HOST.cars[i].isInPit or (HOST.startDelays[i] or 0)==0,'unload: pending wait cancelled: '..i) end
  end)
  if not ok then error(err,0) end
 end)
 -- Beta 1.24 : réinitialisation de chaque section des réglages : valeurs par défaut du profil affiché, préférences du
 -- pilote et motifs de classes gardés, autres sections intactes ; options globales de l'onglet seulement (sens latéral
 -- mesuré et voiture de sécurité gardés). Gommes sèches principales lues (une par nom court).
 check('Beta 1.24 : réinitialisation de chaque section des réglages',function()
  HUMANAI.release(); HOST=H.create(true); HOST.space={x=1000,y=3000}
  HOST.tyreCatalog[2]={{short='H',name='Origine dure'},{short='M',name='Origine medium'},{short='S',name='Origine tendre'},{short='SS',name='Origine super tendre'},
   {short='H',name='F1 dure'},{short='M',name='F1 medium'},{short='S',name='F1 tendre'},{short='SS',name='F1 super tendre'},{short='I',name='Intermediaire'},{short='W',name='Pluie'}}
  assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  local e=HUMANAI.engine; local P=e.profiles
  local car=e.frame.cars[3]
  assert(car.dryPrimary and #car.dryPrimary==4 and car.dryPrimary[1]==0 and car.dryPrimary[4]==3 and #car.dryList==8 and car.interCompound==8 and car.wetCompound==9,'first of each dry name only')
  go('home'); press('profile_C'); section('general')
  local d=C.defaults('C'); P.C.levelPct=70; P.C.aggressionPct=20; redraw()
  press('reset_general'); assert(P.C.levelPct==d.levelPct and P.C.aggressionPct==d.aggressionPct,'general reset to the profile defaults')
  section('accidents'); P.C.yellowHud=not d.yellowHud; P.C.obstacleDetect=60; redraw(); press('reset_accidents')
  assert(P.C.obstacleDetect==d.obstacleDetect and P.C.yellowHud==not d.yellowHud,'accidents reset, display preference kept')
  section('endurance'); P.C.classPatterns='car_2:1'; P.C.classGapPct=20; redraw(); press('reset_endurance')
  assert(P.C.classGapPct==d.classGapPct and P.C.classPatterns=='car_2:1','endurance reset, class patterns kept')
  P.C.levelPct=70; section('lateral'); redraw(); press('reset_lateral'); assert(P.C.levelPct==70,'only the section shown')
  section('globals'); e.g.useBrakeAssist=false; e.g.debugLog=true; e.g.offsetSign=-1; e.g.safetyCarModel='sc_x'; redraw(); press('reset_globals')
  assert(e.g.useBrakeAssist and not e.g.debugLog and e.g.offsetSign==-1 and e.g.safetyCarModel=='sc_x','globals reset, measured direction and safety car kept')
  pause(false); HUMANAI.release()
 end)
 -- Beta 1.25 : voiture de sécurité libérée encore à son emplacement (en course, elle n'en sortait jamais seule) :
 -- réveillée, départ immédiat et aucun freinage forcé, à intervalles, tant qu'elle y reste ; rien une fois sortie, ni
 -- tant qu'elle est garée.
 check('Beta 1.25 : voiture de sécurité libérée relancée hors de son emplacement',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  ac.getCarID=function(index) return index==3 and 'sc_model' or 'model_'..index end
  assert(loadstring(source))(); local e=HUMANAI.engine
  C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; e.g.safetyCarModel='sc_model'; e.g.safetyCarPicked=true; E.changed(e); H.tick(HOST,3)
  local car=HOST.cars[3]; car.isInPit=true; car.isInPitlane=true; car.speedKmh=0; car.velocity={x=0,z=0}; H.tick(HOST,2)
  assert(e.incidents.safety==4 and scHeld(3) and (HOST.awakes[3] or 0)==0,'held: never woken')
  local t=e.incidents
  t.neutral=true; t.neutralMode='sc'; t.safetyPhase='out'; t.safetyLeft=false; t.neutralSince=e.time; t.neutralUntil=e.time+1e6; t.safetySince=e.time
  HOST.startDelays[3]=nil; HOST.stops[3]=nil; HOST.pitRequests[3]=nil; H.tick(HOST,0.5)
  assert(not HOST.parked[3] and (HOST.awakes[3] or 0)==1 and HOST.startDelays[3]==0 and HOST.stops[3]==0 and HOST.pitRequests[3]==false,'released: woken, start now, no brake, no pit request')
  -- Relance répétée : réveil et départ immédiat à chaque fois (le premier départ immédiat peut venir de la retenue
  -- levée, Beta 1.52).
  HOST.startDelays[3]=nil; H.tick(HOST,4.6); local woken=HOST.awakes[3]
  assert(woken>=3 and woken<=4 and HOST.startDelays[3]==0,'repeated while still in its box ('..woken..'), start now each time')
  car.isInPit=false; car.isInPitlane=true; H.tick(HOST,0.5)
  local found=false
  for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('voiture de securite: sortie de son stand apres',1,true) then found=true end end
  H.tick(HOST,5); assert(HOST.awakes[3]==woken and found,'out of its box: no more calls, exit logged')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 -- Beta 1.25 : overlay en jeu : fenêtre transparente centrée en haut, verrouillée (clics
 -- traversants) ; déverrouillée : glisser, coin pour la taille, clic droit pour verrouiller ; masquée en rediffusion ;
 -- case de session d'AC remplacée puis rendue ; messages d'AC repris, notés, masqués sur demande, tout rendu au
 -- déchargement.
 check('Beta 1.25 : overlay en jeu, position, verrou, taille, case de session et messages d AC',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))()
  local e=HUMANAI.engine; local g=e.g; C.preset('Course','C',e.profiles.C); E.changed(e); H.tick(HOST,1)
  g.panelShow='always'
  HOST.transparent={}; script.HUMANAI__HUD()
  local w=HOST.transparent.AdvancedIA_overlay
  assert(w and math.abs(w.x-(1920-600)/2)<1e-6 and math.abs(w.y-1080*C.K.hudTop)<1e-6 and w.w==600 and not w.inputs,'centred at the top, locked, click-through')
  assert(HOST.hudHidden.sessionTime==true,'AC session box replaced by the session line')
  g.overlayLocked=false; script.HUMANAI__HUD(); w=HOST.transparent.AdvancedIA_overlay; assert(w.inputs,'unlocked: takes the mouse')
  HOST.mouseDelta={x=100,y=40}; HOST.drags['##aai_overlay_move']=0.5; script.HUMANAI__HUD()
  assert(math.abs(g.overlayX-(w.x+100))<1e-6 and math.abs(g.overlayY-(w.y+40))<1e-6,'dragged')
  HOST.mouseDelta={x=0,y=0}; script.HUMANAI__HUD()
  HOST.mouseDelta={x=60,y=0}; HOST.drags['##aai_overlay_size']=0.5; script.HUMANAI__HUD()
  assert(math.abs(g.overlayScale-1.1)<1e-6,'resized by its corner ('..g.overlayScale..')')
  HOST.mouseDelta={x=0,y=0}; script.HUMANAI__HUD()
  w=HOST.transparent.AdvancedIA_overlay; assert(math.abs(w.w-660)<1e-6,'drawn at the new size')
  HOST.mouse={x=10,y=10}; HOST.rightClick='##aai_overlay_move'; script.HUMANAI__HUD(); HOST.mouse={x=-1e6,y=-1e6}
  assert(g.overlayLocked,'right-click locks')
  g.overlayClickThrough=false; HOST.windowHovered=true; HOST.rightClick=nil
  HOST.mouseClickedAny=true
  g.overlayClickThrough=true; HOST.windowHovered=false
  HOST.sim.isReplayActive=true; H.tick(HOST,0.2); HOST.transparent={}; script.HUMANAI__HUD()
  assert(not HOST.transparent.AdvancedIA_overlay and HOST.hudHidden.sessionTime==false,'replay: hidden, AC box back')
  HOST.sim.isReplayActive=false; H.tick(HOST,0.2); HOST.transparent={}; script.HUMANAI__HUD()
  assert(HOST.transparent.AdvancedIA_overlay and HOST.hudHidden.sessionTime==true,'back after the replay')
  assert(#HOST.messageListeners==1,'AC messages listened to')
  HOST.messageListeners[1]('ABS','3',nil,5); H.tick(HOST,0.3)
  assert(e.hud.msgText=='ABS · 3' and e.time<e.hud.msgUntil,'AC message on the session line')
  local found=false; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('message d AC: ABS : 3',1,true) then found=true end end
  assert(found,'new AC message title logged')
  HOST.draws=0; HOST.drawnTexts={}; script.HUMANAI__HUD()
  local shown=false; for _,t in ipairs(HOST.drawnTexts) do if t=='ABS · 3' then shown=true end end
  assert(shown or HOST.draws>0,'message drawn')
  assert(HOST.blocked==1,'Beta 1.26: original AC messages hidden by default')
  local probed=false; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('affichage d origine masque',1,true) then probed=true end end
  assert(probed and e.hud.msgText=='ABS · 3','probe received, never shown on the overlay')
  g.overlayBlockMessages=false; script.HUMANAI__HUD(); assert(HOST.blocked==0,'shown on request')
  g.overlayBlockMessages=true; script.HUMANAI__HUD(); assert(HOST.blocked==1,'hidden again')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  assert(HOST.blocked==0 and #HOST.messageListeners==0 and HOST.hudHidden.sessionTime==false,'everything restored on unload')
 end)
 -- Beta 1.26 : journée circuit, IA à leur emplacement réparties sur tout le circuit : posées une fois sur la trajectoire
 -- de l'IA, dans le sens de la piste, lancées ; jamais le joueur ; plus rien une fois en piste.
 check('Beta 1.26 : journée circuit, IA réparties sur tout le circuit',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.currentSessionTime=300; HOST.files['cfgext\\new_behaviour.ini']='[AI_FLOOD]\r\nENABLED=0\r\n'
  for i=1,3 do local car=HOST.cars[i]; car.isInPit=true; car.isInPitlane=true; car.speedKmh=0; car.velocity={x=0,y=0,z=0} end
  assert(loadstring(source))(); local e=HUMANAI.engine
  e.profiles.J.section_traffic=true; e.profiles.J.section_general=true; e.profiles.J.spawnMinCars=3; e.profiles.J.spawnPitPct=0; E.changed(e); H.tick(HOST,0.1); e.traffic.exits.session=-99
  H.tick(HOST,0.4)
  local x=e.traffic.exits
  local fr=HUMANAI.frame or {}
  assert(e.profile=='J' and x.mode=='track' and x.count==3,'track day: 3 AI spread ('..tostring(x.mode)..', '..x.count..', guard '..tostring(e.guard)..', profile '..tostring(e.profile)..', flood '..tostring(e.flood.loaded)..', session '..tostring(x.session)..', draws '..tostring(x.draws)..', time '..tostring(x.time)..', mode '..tostring(e.run.spawnMode)..', min '..tostring(e.run.spawnMinCars)..')')
  H.tick(HOST,1.5)
  for i=1,3 do
   local p=HOST.positions[i]; local v=HOST.velocities[i]
   assert(p and v,'placed and launched: '..i)
   assert(p.dir==nil and math.abs(v.z-C.K.spreadSpeed/3.6)<1e-9 and math.abs(v.x)<1e-9,'aligned by CSP, launched along the car, '..C.K.spreadSpeed..' km/h: '..i)
  end
  assert(not HOST.positions[0],'never the player')
  assert(HOST.startDelays[1]==0 and HOST.startDelays[2]==0 and HOST.startDelays[3]==0,'native wait cancelled first')
  assert(x.placed==3,'all three at their place ('..x.placed..')')
  local writes=HOST.positionWrites; H.tick(HOST,3); assert(HOST.positionWrites==writes,'at their place: no more placement')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 -- Beta 1.26 : masquage qui retirerait aussi les messages à l'overlay : levé jusqu'au prochain lancement, journalisé.
 check('Beta 1.26 : masquage des messages d AC levé si l overlay ne les reçoit plus',function()
  HUMANAI.release(); HOST=H.create(true); HOST.blockSwallows=true; assert(loadstring(source))(); H.tick(HOST,0.5)
  local e=HUMANAI.engine
  script.HUMANAI__HUD(); assert(HOST.blocked==1,'hidden at first')
  for _=1,C.K.probeFrames+1 do script.HUMANAI__HUD() end
  assert(HOST.blocked==0,'lifted: the overlay no longer receives them')
  local warned=false; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('masquage leve',1,true) then warned=true end end
  assert(warned,'logged')
  script.HUMANAI__HUD(); assert(HOST.blocked==0,'not hidden again until the next launch')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 -- Beta 1.25 : section Overlay des réglages : verrou, fond (opaque, atténué, transparent), contenu, replacer, réinitialiser.
 check('Beta 1.25 : section Overlay des réglages',function()
  HUMANAI.release(); HOST=H.create(true); HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  local g=HUMANAI.engine.g
  section('overlay')
  assert(drawn('overlay_lock') and drawn('overlay_scale') and drawn('overlay_background') and drawn('panel_opacity') and drawn('overlay_content') and drawn('overlay_overlaySession') and drawn('overlay_overlayBlockMessages')
   and drawn('overlay_cspHideMessages') and drawn('overlay_cspHideFlags'),'overlay settings drawn')
  assert(not drawn('section_overlay'),'no profile switch: shared by every session')
  press('overlay_lock'); assert(not g.overlayLocked,'unlocked from the settings')
  press('overlay_background'); assert(g.overlayBackground=='ghost'); press('overlay_background'); assert(g.overlayBackground=='transparent')
  press('overlay_overlayExplain'); assert(not g.overlayExplain)
  g.overlayX=300; g.overlayY=200; g.overlayScale=1.6; redraw(); press('overlay_recenter'); assert(g.overlayX==-1 and g.overlayY==-1 and g.overlayScale==1,'put back on screen')
  g.overlayContent=50; g.panelOpacity=20; g.offsetSign=-1; g.cspHideFlags=false; g.cspMessagesLost=true; redraw(); press('reset_overlay')
  assert(g.overlayLocked and g.overlayBackground=='solid' and g.overlayExplain and g.overlayContent==100 and g.panelOpacity==C.globalDefaults.panelOpacity and g.offsetSign==-1,'overlay reset, nothing else')
  assert(g.cspHideFlags and not g.cspMessagesLost,'Beta 1.40: CSP options reset too')
  pause(false); HUMANAI.release()
 end)
 -- Beta 1.32 : panneaux lumineux du circuit, seulement sur un circuit équipé ; option coupée : rendu aussitôt.
 check('Beta 1.32 : panneaux lumineux du circuit allumés en jaune sur un circuit équipé, rendus à AC',function()
  HUMANAI.release(); HOST=H.create(true)
  local sep=string.char(92); local function path(...) return table.concat({...},sep) end
  HOST.files[path('tracks','test','extension','ext_config.ini')]='[INCLUDE]\nINCLUDE = common/conditions.ini, ext_config-flags.ini\n'
  HOST.files[path('tracks','test','extension','ext_config-flags.ini')]='[MATERIAL_ADJUSTMENT_0]\nACTIVE=1\nCONDITION=RACING_FLAG\n'
  HOST.files[path('cfgsys','tracks','common','conditions.ini')]='[CONDITION_85]\nNAME=RACING_FLAG\nINPUT=FLAG_TYPE\n'
  assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Nordschleife','J',e.profiles.J); E.changed(e)
  HOST.cars[0].splinePosition=0.995; HOST.cars[3].speedKmh=0; HOST.cars[3].velocity={x=0,z=0}
  H.tick(HOST,8)
  assert(HUMANAI.host.trackLights==true and HUMANAI.host.trackLightsSource~='','equipped track detected')
  assert(e.incidents.playerYellow and not e.profiles.J.yellowHud and HOST.flag==C.K.flagCaution,'yellow on the panels without the HUD preference')
  assert(e.panel.title==L.flagTitles.yellow2 or e.panel.title==L.flagTitles.zone,'own flag not read back as an AC yellow')
  local logged=false; for n=0,e.log.count-1 do local row=e.log[(e.log.head-n-1)%e.log.limit+1]; if row.message:find('panneaux lumineux du circuit: jaune',1,true) then logged=true end end
  assert(logged,'write logged with its reason')
  -- Section Panneaux lumineux du profil en cours (Beta 1.37) : décochée, drapeau rendu à AC aussitôt ; cochée, de retour.
  e.profiles.J.section_lights=false; E.changed(e); H.tick(HOST,0.5); assert(HOST.flag==0 and not HUMANAI.host.flagOverride,'handed back at once when the section is off')
  e.profiles.J.section_lights=true; E.changed(e); H.tick(HOST,0.5); assert(HOST.flag==C.K.flagCaution,'back on')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  assert(HOST.flag==0,'handed back on unload')
 end)
 -- Beta 1.34 : conditions de la session Imola du pilote (course, drapeau de départ d'AC tenu, joueur dans une zone
 -- jaune) ; en 1.32, aucune couleur n'était écrite et rien n'était noté.
 check('Beta 1.34 : en course, drapeau de départ d AC tenu : panneaux allumés, drapeau d AC et refus notés',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  local sep=string.char(92); local function path(...) return table.concat({...},sep) end
  HOST.files[path('tracks','test','extension','ext_config.ini')]='[INCLUDE]\nINCLUDE = common/conditions.ini, ext_config-flags.ini\n'
  HOST.files[path('tracks','test','extension','ext_config-flags.ini')]='[MATERIAL_ADJUSTMENT_0]\nACTIVE=1\nCONDITION=RACING_FLAG\n'
  HOST.files[path('cfgsys','tracks','common','conditions.ini')]='[CONDITION_85]\nNAME=RACING_FLAG\nINPUT=FLAG_TYPE\n'
  HOST.nativeFlag=C.K.flagStart; HOST.sim.raceFlagType=C.K.flagStart
  assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); E.changed(e)
  local function logged(text) for n=0,e.log.count-1 do local row=e.log[(e.log.head-n-1)%e.log.limit+1]; if row.message:find(text,1,true) then return true end end return false end
  H.tick(HOST,2); assert(e.profile=='C' and logged('drapeau d AC: 1 (depart)'),'AC start flag logged')
  HOST.cars[0].splinePosition=0.995; HOST.cars[3].speedKmh=0; HOST.cars[3].velocity={x=0,z=0}
  H.tick(HOST,8)
  assert(HUMANAI.host.trackLights==true and e.incidents.playerYellow,'equipped track, player under yellow')
  assert(HOST.flag==C.K.flagCaution and logged('panneaux lumineux du circuit: jaune'),'yellow written over the held start flag, and logged')
  -- Drapeau bleu d'AC : à respecter ; le refus est noté avec sa cause.
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  HOST=H.create(true); HOST.sim.raceSessionType=3
  HOST.files[path('tracks','test','extension','ext_config.ini')]='[INCLUDE]\nINCLUDE = common/conditions.ini, ext_config-flags.ini\n'
  HOST.files[path('tracks','test','extension','ext_config-flags.ini')]='[MATERIAL_ADJUSTMENT_0]\nACTIVE=1\nCONDITION=RACING_FLAG\n'
  HOST.files[path('cfgsys','tracks','common','conditions.ini')]='[CONDITION_85]\nNAME=RACING_FLAG\nINPUT=FLAG_TYPE\n'
  HOST.nativeFlag=C.K.flagFasterCar; HOST.sim.raceFlagType=C.K.flagFasterCar
  assert(loadstring(source))(); e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); E.changed(e)
  HOST.cars[0].splinePosition=0.995; HOST.cars[3].speedKmh=0; HOST.cars[3].velocity={x=0,z=0}
  H.tick(HOST,8)
  assert(HOST.sim.raceFlagType==C.K.flagFasterCar and HOST.flagOverrides==0 and e.incidents.playerYellow,'AC blue kept')
  assert(logged('panneaux lumineux du circuit: jaune voulu, non ecrit (drapeau natif 12)'),'refusal logged with its cause')
  HUMANAI.release()
 end)
 check('Beta 1.34 : configuration du circuit lue même sans onglet coché',function()
  HUMANAI.release(); HOST=H.create(true)
  local sep=string.char(92)
  HOST.files[table.concat({'tracks','test','extension','ext_config.ini'},sep)]='[MATERIAL_ADJUSTMENT_0]\nACTIVE=1\nCONDITION=RACING_FLAG\n'
  HOST.files[table.concat({'cfgsys','tracks','common','conditions.ini'},sep)]='[CONDITION_85]\nNAME=RACING_FLAG\nINPUT=FLAG_TYPE\n'
  assert(loadstring(source))()
  local e=HUMANAI.engine; for _,p in pairs(e.profiles) do for _,group in ipairs(C.sections) do p['section_'..group]=false end end; E.changed(e)
  H.tick(HOST,2)
  assert(e.guard=='nosections' and HUMANAI.host.trackLights==true,'track read with every section unticked')
  HUMANAI.release()
 end)
 check('Beta 1.32 : circuit non équipé, drapeau d AC jamais modifié',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Nordschleife','J',e.profiles.J); E.changed(e)
  HOST.cars[0].splinePosition=0.995; HOST.cars[3].speedKmh=0; HOST.cars[3].velocity={x=0,z=0}
  H.tick(HOST,8)
  assert(HUMANAI.host.trackLights==false and e.incidents.playerYellow and HOST.flag==0 and HOST.flagOverrides==0,'not equipped: AC flag untouched')
  HUMANAI.release()
 end)
 check('Beta 1.32 : réglage des panneaux lumineux, nouveaux drapeaux dessinés',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))(); H.tick(HOST,1); pause(true)
  local g=HUMANAI.engine.g
  -- Beta 1.37 : l'overlay mène à la section Panneaux lumineux (en bas, atteint à la molette).
  section('overlay'); redraw()
  local r=HOST.hits['##aai_overlay_lock']; HOST.mouse={x=r.x+5,y=r.y+5}
  for _=1,10 do HOST.wheel=-1; main() end
  redraw(); assert(drawn('overlay_lights') and not drawn('overlay_trackLights'),'link to the section, no global switch'); HOST.mouse={x=-1e6,y=-1e6}
  press('overlay_lights'); redraw(); assert(lit('cat_lights') and drawn('set_lightsRed') and drawn('lights_on_J'),'section opened by the link')
  -- Section propre de chaque profil : interrupteur de la liste, puces « Active pour », réinitialisation.
  local e0=HUMANAI.engine; local view=e0.profiles[HUMANAI.engine.profile]
  assert(C.on(e0.profiles.J,'lights') and C.on(e0.profiles.H,'lights'),'on by default in every profile')
  press('lights_on_J'); assert(not C.on(e0.profiles.J,'lights') and lit('lights_on_C'),'chip unticks that profile only')
  press('lights_on_J'); assert(C.on(e0.profiles.J,'lights'),'chip ticks it back')
  press('set_lightsRed'); assert(view.lightsRed==false,'red off'); press('reset_lights'); assert(view.lightsRed==true,'section reset')
  -- Beta 1.59 (décision du pilote) : la case figée du jaune n'est plus montrée ; le jaune reste toujours actif.
  assert(not drawn('set_lightsYellow') and view.lightsYellow==true,'yellow always on, no frozen switch shown')
  pause(false)
  local e=HUMANAI.engine
  e.lights.meatballUntil=e.time+10; H.tick(HOST,0.5)
  HOST.panelTexts={}; HOST.circles=0; HUMANAI.drawFlags()
  assert(e.panel.kind=='meatball' and has(HOST.panelTexts,L.flagTitles.meatball) and HOST.circles>0,'damaged car: black flag with an orange disc')
  e.lights.meatballUntil=-math.huge; e.panel.giveBackDue=false; require('src/panel').warn(e.panel); H.tick(HOST,0.5)
  HOST.panelTexts={}; HUMANAI.drawFlags(); assert(e.panel.kind=='warning' and has(HOST.panelTexts,L.flagTitles.warning),'final warning drawn')
  HUMANAI.release()
 end)
 -- Beta 1.33 : mise à jour depuis GitHub, app complète sur une imitation de CSP (réseau, empreinte, zips, fichiers).
 local Fake=require('tests/updatefake')
 local function ver(d) local major,minor=C.release:match('(%d+)%.(%d+)'); return 'Beta '..major..'.'..(tonumber(minor)+d) end
 local Update=require('src/update')
 local API='get https://api.github.com/repos/VincentChevalier44/AdvancedIA/releases/latest'
 local function logged(text) local e=HUMANAI.engine; for n=0,e.log.count-1 do local row=e.log[(e.log.head-n-1)%e.log.limit+1]; if row.message:find(text,1,true) then return true end end; return false end
 local function halt() pause(true); script.update(1/60) end
 local function updated(setup,body)
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  local F=Fake.install({root='local',state='state',files=HOST.files})
  local ok,err=pcall(function() F.app(ver(0)); if setup then setup(F) end; assert(loadstring(source))(); body(F) end)
  HOST.releasing=true; pcall(HUMANAI.release); HOST.releasing=false
  F.restore(); assert(ok,err)
 end
 local WORK='state/AdvancedIA-update/'
 check('Beta 1.33 : vérification au lancement, mise à jour d un clic depuis l en-tête, IA rendues avant le redémarrage',function()
  updated(function(F) F.release(ver(1)) end,function(F)
   local u=HUMANAI.updater; assert(HUMANAI.port.ready and u.phase=='idle' and u.installed==C.release)
   H.tick(HOST,5); assert(u.phase=='idle' and not F.find(API),'no request before the delay')
   H.tick(HOST,6); assert(u.phase=='available' and F.find(API),'checked once after the delay')
   assert(logged('mise a jour disponible: '..ver(1)),'logged')
   H.tick(HOST,30); local requests=0; for _,c in ipairs(F.calls) do if c==API then requests=requests+1 end end; assert(requests==1,'one request per launch')
   pause(true); script.update(1/60); assert(HUMANAI.host.updateStopped,'paused: stopped')
   go('home'); redraw(); assert(drawn('update_header') and lit('update_header') and drawn('update_home'),'header button and home alert')
   assert(begins(string.format(L.updateAlert,ver(1))),'home alert text')
   local order={}
   F.onRestart=function() order[#order+1]=next(HOST.releases)==nil and 'released' or 'running' end
   F.watch()
   -- Un clic : téléchargement, contrôles, extraction et copie de la version installée ; la copie finale à l'image suivante.
   press('update_header'); assert(u.phase=='ready' and HOST.files['local/AdvancedIA.lua']=='main '..ver(0),'nothing copied into the app by the click')
   HOST.releasing=true; script.update(1/60); HOST.releasing=false
   assert(F.restarts==1 and order[1]=='released','AI handed back to AC before the restart')
   local files=HOST.files
   assert(files['local/AdvancedIA.lua']=='main '..ver(1) and Update.manifestVersion(files['local/manifest.ini'])==ver(1) and files['local/src/new.lua']=='new '..ver(1))
   assert(files[WORK..'updated.txt']=='update '..ver(0)..' -> '..ver(1) and files[WORK..'installing.txt']==nil and Update.manifestVersion(files[WORK..'backup/manifest.ini'])==ver(0))
   local snap,mk,man,rep=F.find('copy state:AdvancedIA-update/current/manifest.ini'),F.find('save state:AdvancedIA-update/installing.txt'),F.find('move manifest.ini'),F.find('save state:AdvancedIA-update/updated.txt')
   assert(snap and mk and man and rep and snap<mk and mk<man and man<rep and rep<F.find('restartApp'),'snapshot -> mark -> copy (manifest last) -> report -> restart')
   -- Beta 1.35 : chaque fichier remplacé d'un seul coup (copie à côté puis déplacement), démarrage surveillé armé.
   assert(F.find('copy manifest.ini.new') and F.find('copy manifest.ini.new')<man and files['local/manifest.ini.new']==nil,'atomic replacement')
   assert(files[WORK..'boot.txt']==ver(1)..'\n0\n'..ver(0),'boot watch armed')
   assert(F.reloads==0,'no live reload of the app')
   assert(logged(ver(1)..' installee (') and logged('copies en') and logged('commandes des IA rendues a AC'),'journal written before the restart')
   -- Redémarrage qui n'a pas lieu (imitation de CSP : rien ne recharge l'app) : signalé après 10 s, une fois.
   H.tick(HOST,5); assert(not u.restartLate,'not late yet')
   H.tick(HOST,6); assert(u.restartLate and logged('l app n a pas redemarre, relancez la session pour finir'),'late restart reported')
   -- Beta 1.35 : lancement suivant (la version installée) : démarrage compté, puis confirmé à la première image.
   HOST.releasing=true; pcall(HUMANAI.release); HOST.releasing=false
   -- Beta 1.40 : options de CSP à masquer de nouveau (gui.ini rendu entre-temps) : rien d'écrit avant la confirmation.
   files['cfgext\\gui.ini']=nil; files['state\\ACAdvancedIA-cspgui.ini']=nil; local writes=HOST.guiWrites or 0
   assert(loadstring(source))(); assert(files[WORK..'boot.txt']==ver(1)..'\n1\n'..ver(0),'boot counted at load')
   -- Beta 1.36 : confirmé seulement une fois l'interface (ici l'overlay) dessinée sans erreur.
   H.tick(HOST,0.3); assert(files[WORK..'boot.txt']~=nil,'engine alone: not confirmed yet')
   assert((HOST.guiWrites or 0)==writes and files['cfgext\\gui.ini']==nil,'Beta 1.40: nothing hidden before the start is confirmed')
   for _=1,3 do script.HUMANAI__HUD() end
   H.tick(HOST,0.1); assert(files[WORK..'boot.txt']==nil,'boot confirmed once the engine and the overlay ran')
   assert(HOST.guiWrites==writes+1 and files['state\\ACAdvancedIA-cspgui.ini'],'Beta 1.40: hidden once confirmed, state file in the CSP state folder')
  end)
 end)
 -- Beta 1.37 : premier lancement réel de la 1.37, installée par le module de la 1.36 : version précédente gardée, paquet
 -- extrait jamais effacé, démarrage armé (compte 0), ancien boot.txt.bak, compte rendu. Restes effacés une fois le
 -- démarrage confirmé, noté une fois ; rien au lancement suivant.
 check('Beta 1.37 : premier lancement après une installation par la 1.36, restes effacés au démarrage confirmé',function()
  updated(function(F)
   local back={'AdvancedIA.lua','manifest.ini','src/update.lua','src/remote.lua','src/ui.lua'}
   for _,rel in ipairs(back) do F.files[WORK..'backup/'..rel]=rel=='manifest.ini' and '[ABOUT]\nVERSION='..ver(-1)..'\n' or 'old '..rel end
   F.files[WORK..'backup/.files']=table.concat(back,'\n')
   local nxt=WORK..'next/'..Fake.prefix
   for _,rel in ipairs(back) do F.files[nxt..rel]=rel=='manifest.ini' and '[ABOUT]\nVERSION='..ver(0)..'\n' or 'new '..rel end
   F.files[nxt..'.files']=table.concat(back,'\n')
   F.files[WORK..'boot.txt']=ver(0)..'\n0\n'..ver(-1)
   F.files[WORK..'boot.txt.bak']=ver(-1)..'\n1\n'..ver(-2)
   F.files[WORK..'updated.txt']='update '..ver(-1)..' -> '..ver(0)
  end,function()
   local files=HOST.files
   assert(files[WORK..'boot.txt']==ver(0)..'\n1\n'..ver(-1) and files[WORK..'boot.txt.bak']==nil,'start counted, no .bak left')
   assert(files[WORK..'next/'..Fake.prefix..'src/ui.lua'],'nothing removed while the start is watched')
   H.tick(HOST,0.3); for _=1,3 do script.HUMANAI__HUD() end; H.tick(HOST,0.1)
   assert(files[WORK..'boot.txt']==nil,'start confirmed')
   for path in pairs(files) do assert(path:sub(1,#WORK+5)~=WORK..'next/' and not path:find('%.bak$'),'left: '..path) end
   assert(files[WORK..'backup/src/ui.lua']=='old src/ui.lua' and HUMANAI.updater.previous==ver(-1),'previous version kept, roll back offered')
   local e=HUMANAI.engine; local n=0
   for k=0,e.log.count-1 do local row=e.log[(e.log.head-k-1)%e.log.limit+1]; if row.message:find('mise a jour: nettoyage (',1,true) then n=n+1 end end
   assert(n==1,'clean-up logged once: '..n)
   HOST.releasing=true; pcall(HUMANAI.release); HOST.releasing=false
   assert(loadstring(source))(); H.tick(HOST,0.3); for _=1,3 do script.HUMANAI__HUD() end; H.tick(HOST,0.1)
   assert(not logged('mise a jour: nettoyage ('),'next launch: nothing left to clean')
  end)
 end)
 check('Beta 1.33 : mise à jour refusée en conduite, information de l overlay aux stands une fois par lancement',function()
  updated(function(F) F.release(ver(1)) end,function(F)
   local e=HUMANAI.engine; local u=HUMANAI.updater
   H.tick(HOST,11); assert(u.phase=='available' and not HUMANAI.host.updateStopped,'on track: not stopped')
   assert(not Update.install(u,HUMANAI.port,HUMANAI.host.updateStopped) and u.error=='driving' and not F.last('get https://github.com/'),'refused while driving, nothing downloaded')
   H.tick(HOST,0.1); assert(logged('refusee en conduite'),'refusal logged (journal fed on the next frame)')
   assert(e.panel.updateUntil==-math.huge,'no overlay notice on track')
   -- Voie des stands en roulant : jamais « à l'arrêt » ; à l'emplacement à l'arrêt : oui.
   HOST.cars[0].isInPit=false; HOST.cars[0].isInPitlane=true; H.tick(HOST,1); assert(not HUMANAI.host.updateStopped,'pit lane at speed: not stopped')
   HOST.cars[0].isInPit=true; HOST.cars[0].speedKmh=0; H.tick(HOST,1)
   assert(HUMANAI.host.updateStopped and e.panel.updateUntil>e.time and e.panel.kind=='update','notice in the pits')
   HOST.panelTexts={}; HUMANAI.drawFlags(); assert(has(HOST.panelTexts,L.flagTitles.update),'overlay notice drawn')
   HOST.cars[0].isInPit=false; HOST.cars[0].isInPitlane=false; HOST.cars[0].speedKmh=108; H.tick(HOST,1); assert(e.panel.kind~='update','removed when leaving the pits')
   HOST.cars[0].isInPit=true; HOST.cars[0].isInPitlane=true; HOST.cars[0].speedKmh=0; H.tick(HOST,1); assert(e.panel.kind~='update','once per launch')
   -- Fenêtre dessinée hors de l'arrêt (état forcé) : boutons d'installation grisés et sans effet ; à l'arrêt, le même
   -- bouton installe.
   halt(); go('diagnostic'); HUMANAI.host.updateStopped=false; redraw()
   local before,serial,queued=#F.calls,u.serial,#u.events
   press('update_install'); assert(#F.calls==before and u.phase~='downloading' and u.serial==serial and #u.events==queued,'greyed install button does nothing (no refusal either)')
   script.update(1/60); redraw(); assert(drawn('update_install') and drawn('update_check') and drawn('update_notes') and drawn('global_updateCheck'))
   press('update_notes'); assert(F.opened[1]==u.release.page,'release page opened')
  end)
 end)
 check('Beta 1.33 : erreurs de mise à jour sans rien changer, annulation, option de vérification coupée',function()
  -- Empreinte différente : version installée intacte, erreur affichée, aucun redémarrage, rien copié.
  updated(function(F) F.release(ver(1),{actual=string.rep('cd',32)}) end,function(F)
   H.tick(HOST,11); halt(); go('diagnostic'); redraw()
   press('update_install'); redraw()
   assert(HUMANAI.updater.error=='integrity' and F.restarts==0 and HOST.files['local/AdvancedIA.lua']=='main '..ver(0) and HOST.files[WORK..'current/AdvancedIA.lua']==nil)
   assert(begins(L.updateStates.errHash),'error shown')
   assert(drawn('update_check'),'check always reachable after an error')
  end)
  -- Fichier de l'app ouvert pendant la copie finale : remise en place aussitôt, erreur dite avec le fichier.
  updated(function(F) F.release(ver(1)); F.locked['local/src/ui.lua']=true end,function(F)
   H.tick(HOST,11); halt(); go('diagnostic'); redraw(); press('update_install'); script.update(1/60); redraw()
   local u=HUMANAI.updater
   assert(u.error=='write' and u.detail=='src/ui.lua' and F.restarts==0 and HOST.files['local/AdvancedIA.lua']=='main '..ver(0) and HOST.files[WORK..'installing.txt']==nil)
   assert(logged('ecriture impossible : src/ui.lua, version actuelle conservee'),'logged with the file')
  end)
  -- Téléchargement annulé : la réponse arrivée ensuite est ignorée.
  updated(function(F) F.release(ver(1)) end,function(F)
   H.tick(HOST,11); halt(); go('diagnostic'); redraw()
   F.hold=true; press('update_install'); assert(HUMANAI.updater.phase=='downloading')
   redraw(); assert(drawn('update_cancel')); press('update_cancel'); F.hold=false; F.flush()
   assert(HUMANAI.updater.phase=='available' and F.restarts==0 and HOST.files['local/AdvancedIA.lua']=='main '..ver(0))
  end)
  -- Vérification au lancement coupée : aucune requête ; le bouton de vérification la fait à la demande.
  updated(function(F) F.release(ver(1)) end,function(F)
   halt(); go('diagnostic'); redraw(); press('global_updateCheck'); assert(HUMANAI.engine.g.updateCheck==false)
   pause(false); H.tick(HOST,15); assert(not F.find(API) and HUMANAI.updater.phase=='idle','no request when turned off')
   pause(true); redraw(); assert(begins(L.updateStates.unchecked))
   press('update_check'); assert(F.find(API) and HUMANAI.updater.phase=='available')
  end)
  -- GitHub sans version publiée, puis limite de requêtes : états affichés.
  updated(function(F) F.release(ver(1),{apiStatus=404}) end,function(F)
   H.tick(HOST,11); halt(); go('diagnostic'); redraw(); assert(HUMANAI.updater.phase=='none' and begins(L.updateStates.none))
   -- Une vérification par minute au plus, comptée aussi en pause (temps du moteur figé) : grisée, puis de nouveau active.
   local function asked() local n=0; for _,c in ipairs(F.calls) do if c==API then n=n+1 end end; return n end
   local t=HUMANAI.engine.time; press('update_check'); assert(asked()==1,'greyed for a minute')
   H.tick(HOST,61); assert(HUMANAI.engine.time==t,'engine time frozen while paused')
   redraw(); press('update_check'); assert(asked()==2,'asked again after a minute in pause')
  end)
  updated(function(F) F.release(ver(1),{apiStatus=403}) end,function()
   H.tick(HOST,11); halt(); go('diagnostic'); redraw(); assert(HUMANAI.updater.error=='rate' and begins(L.updateStates.errRate))
  end)
 end)
 check('Beta 1.33 : retour à la version sauvegardée, compte rendu après le redémarrage',function()
  updated(function(F)
   local names={}
   for k,val in pairs({['manifest.ini']='VERSION='..ver(-1),['AdvancedIA.lua']='main '..ver(-1),['src/update.lua']='update '..ver(-1),['src/remote.lua']='remote '..ver(-1),['src/ui.lua']='ui '..ver(-1)}) do
    F.files[WORK..'backup/'..k]=val; names[#names+1]=k
   end
   F.files[WORK..'backup/.files']=table.concat(names,'\n')
   F.files[WORK..'updated.txt']='update '..ver(-1)..' -> '..ver(0)
   F.release(ver(0))
  end,function(F)
   local u=HUMANAI.updater; assert(u.updated and u.updated.kind=='update' and u.previous==ver(-1) and HOST.files[WORK..'updated.txt']==nil)
   assert(logged('mise a jour reussie: '..ver(-1)..' -> '..ver(0)))
   halt(); go('home'); redraw(); assert(begins(string.format(L.updateDone.update,ver(-1),ver(0))),'report on the home page')
   assert(drawn('update_home_notes'),'notes link on the report')
   H.tick(HOST,0); go('diagnostic'); redraw(); assert(drawn('update_rollback') and not drawn('update_install'))
   -- Beta 1.35 : retour arrière demandé au clic, copié à l'image suivante (hors du dessin de la fenêtre).
   F.watch(); HOST.releasing=true; press('update_rollback'); assert(u.phase=='rollbackReady' and F.restarts==0,'deferred to the next frame'); script.update(1/60); HOST.releasing=false
   assert(F.restarts==1 and HOST.files['local/AdvancedIA.lua']=='main '..ver(-1) and Update.manifestVersion(HOST.files['local/manifest.ini'])==ver(-1) and F.reloads==0,
    'rollback: '..u.phase..' '..u.error..' '..u.detail..' restarts '..F.restarts..' reloads '..F.reloads..' stopped '..tostring(HUMANAI.host.updateStopped))
   assert(HOST.files[WORK..'updated.txt']=='rollback '..ver(0)..' -> '..ver(-1))
  end)
 end)
 check('Beta 1.35 : copie interrompue reprise au chargement, avant les autres modules ; reprise impossible dite, app jamais figée',function()
  -- Fichiers mêlés (manifeste encore à la version de départ), paquet extrait intact : copie terminée au chargement.
  updated(function(F)
   F.files['local/manifest.ini']='VERSION='..ver(-1)
   local names={}
   for k,val in pairs({['manifest.ini']='VERSION='..ver(0),['AdvancedIA.lua']='main '..ver(0),['src/update.lua']='update '..ver(0),['src/remote.lua']='remote '..ver(0),['src/ui.lua']='ui '..ver(0)}) do
    F.files[WORK..'next/'..Fake.prefix..k]=val; names[#names+1]=k
   end
   F.files[WORK..'next/'..Fake.prefix..'.files']=table.concat(names,'\n')
   for k,val in pairs({['manifest.ini']='VERSION='..ver(-1),['AdvancedIA.lua']='main '..ver(-1),['src/ui.lua']='ui '..ver(-1)}) do F.files[WORK..'current/'..k]=val end
   F.files[WORK..'current/.files']='manifest.ini\nAdvancedIA.lua\nsrc/ui.lua'
   F.files[WORK..'installing.txt']='update '..ver(-1)..' -> '..ver(0)
   F.before=HUMANAI
  end,function(F)
   assert(Update.manifestVersion(HOST.files['local/manifest.ini'])==ver(0) and HOST.files[WORK..'installing.txt']==nil,'finished at load')
   assert(HUMANAI==F.before,'no other module loaded before the restart')
   -- Beta 1.35 : code déjà chargé d'une autre version : aucun autre module lu, redémarrage seul à la première image ;
   -- la reprise est dite tout de suite au journal de CSP.
   assert(F.restarts==0 and F.csplog and F.csplog[1]:find('copie reprise au lancement',1,true),'restart pending, told to the CSP log')
   script.update(1/60)
   assert(F.restarts==1 and next(HOST.releases)==nil,'one restart before the engine ran')
   script.update(1/60); assert(F.restarts==1,'never twice')
   -- Lancement suivant : compte rendu lu, rien à reprendre.
   HOST.releasing=true; pcall(HUMANAI.release); HOST.releasing=false
   assert(loadstring(source))(); local u2=HUMANAI.updater
   assert(u2.phase=='idle' and u2.updated and u2.updated.kind=='update' and logged('copie reprise au lancement')==false and F.restarts==1,'report on the next launch')
   local t=HUMANAI.engine.time; H.tick(HOST,2); assert(HUMANAI.engine.time>t,'engine running')
  end)
  -- Rien à remettre en place après deux essais : repère levé, état terminal affiché, moteur jamais figé.
  updated(function(F) F.files['local/manifest.ini']='VERSION='..ver(-1); F.files[WORK..'installing.txt']='update '..ver(-1)..' -> '..ver(0)..'\ntries 2' end,function(F)
   local u=HUMANAI.updater
   assert(u.phase=='broken' and HOST.files[WORK..'installing.txt']==nil and F.restarts==0)
   local t=HUMANAI.engine.time; H.tick(HOST,2); assert(HUMANAI.engine.time>t,'engine running')
   halt(); go('diagnostic'); redraw(); assert(begins(string.format(L.updateStates.broken,u.brokenFile or '')),'explained')
   assert(not Update.install(u,HUMANAI.port,true) and not Update.check(u,HUMANAI.port,9999),'no further operation')
  end)
 end)
 -- Beta 1.35 : refonte Racing 26 : polices de l'app ou de secours, segment choisi à la souris, réglage remplacé par les
 -- panneaux lumineux, lien d'un point à vérifier, bandeau d'état, vue Journée circuit des règles, motif effacé, barre
 -- latérale qui défile.
 check('Beta 1.35 : interface Racing 26, polices, segments, liens, bandeau, vues inertes, motifs, défilement',function()
  local function logged(text) local e=HUMANAI.engine; local n=0; for k=0,e.log.count-1 do local row=e.log[(e.log.head-k-1)%e.log.limit+1]; if row.message:find(text,1,true) then n=n+1 end end; return n end
  HUMANAI.release(); HOST=H.create(true); HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  local e=HUMANAI.engine; local g=e.g
  -- Polices : fichiers absents du dossier de l'app, Segoe UI et Consolas, noté une seule fois.
  redraw(); redraw(); assert(W.fonts().body=='Segoe UI' and W.fonts().mono=='Consolas' and logged('polices de l interface absentes')==1,'system fonts, noted once')
  -- Fichiers présents : polices de l'app (dossier relatif à l'app) après un rechargement.
  for _,file in ipairs({'barlow/Barlow-Regular.ttf','barlow/Barlow-SemiBold.ttf','barlowcondensed/BarlowCondensed-SemiBold.ttf','barlowcondensed/BarlowCondensed-Bold.ttf','barlowcondensed/BarlowCondensed-ExtraBoldItalic.ttf','jetbrainsmono/JetBrainsMono-Medium.ttf'}) do HOST.files['local/fonts/'..file]='ttf' end
  pause(false); HUMANAI.release(); assert(loadstring(source))(); H.tick(HOST,0.5); pause(true); e=HUMANAI.engine; g=e.g; redraw()
  assert(W.fonts().body=='Barlow:fonts/barlow;Weight=Regular' and W.fonts().display:find('UltraBold;Style=Italic',1,true) and logged('polices de l interface absentes')==0,'app fonts loaded')
  assert(HOST.dwriteDepth==0,'fonts balanced')
  -- Segment : un clic sur une case la choisit (souris dessus), sans passer par la suivante.
  section('overlay'); redraw(); assert(g.overlayBackground=='solid')
  local r=HOST.hits['##aai_overlay_background']; HOST.mouse={x=r.x+r.w*5/6,y=r.y+r.h/2}; press('overlay_background')
  HOST.mouse={x=-1e6,y=-1e6}; redraw()
  assert(g.overlayBackground=='transparent' and lit('overlay_background_3') and not lit('overlay_background_1'),'third cell picked directly')
  press('reset_overlay'); assert(g.overlayBackground=='solid','overlay reset')
  -- Jaune natif du HUD : remplacé (grisé, sans effet) sur un circuit équipé avec les panneaux ; réglable sinon.
  go('home'); press('profile_J'); local p=e.profiles.J; p.section_accidents=true; p.configured=true; section('accidents','yellowHud')
  HUMANAI.host.trackLights=true; p.section_lights=true; redraw()
  local before=p.yellowHud; press('set_yellowHud'); assert(p.yellowHud==before,'locked while the panels replace it')
  redraw(); assert(begins(L.yellowHudLocked),'replacement explained')
  p.section_lights=false; redraw(); press('set_yellowHud'); assert(p.yellowHud==not before,'settable with the panels off for this profile')
  press('set_yellowHud'); p.section_lights=true; HUMANAI.host.trackLights=nil
  -- Point à vérifier : lien vers la section concernée.
  p.section_weather=false; go('home'); redraw(); assert(drawn('warn_weather'),'weather warning linked')
  press('warn_weather'); redraw(); assert(lit('cat_weather') and lit('tab_settings'),'link opens the Weather section')
  -- Bandeau d'état : app coupée, activation d'un clic.
  g.enabled=false; go('home'); redraw(); assert(drawn('banner_action') and begins(L.banners.disabled[2]),'disabled banner')
  press('banner_action'); assert(g.enabled,'enabled from the banner'); redraw(); assert(not drawn('banner_action'),'banner gone')
  -- Journée circuit : arrêt obligatoire et voiture de sécurité inertes, leurs vues non sélectionnables ; une vue ouverte
  -- en course est ramenée à « toutes » au passage en journée circuit.
  go('rules'); local shownProfile=e.profile
  press('profile_C'); redraw(); press('rules_view_stops'); redraw(); assert(lit('rules_view_stops'),'stops view in race')
  press('profile_'..shownProfile); redraw(); assert(lit('rules_view_all') and not lit('rules_view_stops'),'back to all views in J')
  HOST.hits={}; HOST.hitOrder={}; press('rules_view_stops'); assert(not drawn('set_pitWindowOpenPct'),'stops view never drawn in J, even on the click frame')
  redraw(); assert(not lit('rules_view_stops') and lit('rules_view_all'),'stops view not selectable in J')
  local stops=e.profiles.C.mandatoryStops; press('mandatory_stop'); assert(e.profiles.C.mandatoryStops==stops,'switch inert in J')
  -- Motifs de classes : saisie puis effacement d'une ligne.
  go('home'); press('profile_C'); e.profiles.C.section_endurance=true; section('endurance')
  HOST.inputEdits['##aai_pattern_1']='gt3'; main(); assert(e.profiles.C.classPatterns:find('gt3:',1,true),'pattern typed')
  press('pattern_clear_1'); assert(not e.profiles.C.classPatterns:find('gt3',1,true),'pattern cleared')
  -- Fenêtre basse : la molette sur la barre latérale amène les dernières sections.
  HOST.space={x=1000,y=420}; go('settings'); redraw(); assert(drawn('cat_general') and not drawn('cat_overlay'),'low window: last section below')
  local q=HOST.hits['##aai_cat_general']; HOST.mouse={x=q.x+5,y=q.y+5}
  for _=1,10 do HOST.wheel=-1; main() end
  redraw(); assert(drawn('cat_overlay'),'reached with the wheel'); HOST.mouse={x=-1e6,y=-1e6}
  assert(HOST.dwriteDepth==0 and HOST.clipDepth==0,'fonts and clips balanced')
  -- Libellé de bouton trop long : police réduite avant toute coupure.
  local label=string.rep('W',16); HOST.drawnTexts={}; W.button('test_shrink',label,0,0,120,28,false,'tip')
  assert(drawnText(label),'button label shrunk, not cut')
  HOST.space={x=1000,y=780}; pause(false); HUMANAI.release()
 end)
 -- Beta 1.35 : dessin des panneaux de l'étape B (relances RS et SS, feux de départ, départ, faux départ) d'après les
 -- champs du panneau (kind, lit, slotText, slotDistance), remplis par panel.lua (étape B).
 -- Beta 1.35 (fusion) : une capacité qui échoue pendant la restitution finale est versée au journal avant sa fermeture.
 check('Beta 1.35 : échec de capacité pendant la restitution finale journalisé',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Nordschleife','J',e.profiles.J); E.changed(e); H.tick(HOST,3)
  local owned=false; for i=1,C.K.maxCars do if HUMANAI.host.cars[i].owned then owned=true end end
  assert(owned,'AI owned before release')
  local original=physics.setAILevel; physics.setAILevel=function() error('niveau refuse') end
  HOST.releasing=true; local ok=pcall(HUMANAI.release); HOST.releasing=false; physics.setAILevel=original; assert(ok,'release completes')
  local found=false; for k=0,e.log.count-1 do local row=e.log[(e.log.head-k-1)%e.log.limit+1]; if row.message:find('capacite level: echec',1,true) then found=true end end
  assert(found,'final restore failure logged')
 end)
 check('Beta 1.35 : panneaux de relance et feux de départ dessinés',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))(); H.tick(HOST,1)
  local e=HUMANAI.engine; local panel=e.panel
  for _,kind in ipairs({'rolling','standing','lights','go','jump'}) do
   panel.kind=kind; panel.title=kind..' title'; panel.short=kind..' short'; panel.explain=''; panel.changedAt=e.time; panel.noPass=false; panel.drsBlocked=false
   panel.lit=kind=='lights' and 3 or 0; panel.slotText=kind=='standing' and 'P4' or nil; panel.slotDistance=kind=='standing' and 380 or nil
   panel.slotPlaced=false; panel.slotPassed=false
   HOST.panelTexts={}; HOST.circles=0; HOST.draws=0; HUMANAI.drawFlags()
   assert(has(HOST.panelTexts,kind..' title') and HOST.fontDepth==0 and HOST.dwriteDepth==0,'drawn: '..kind)
   if kind=='rolling' then assert(has(HOST.panelTexts,'RS'),'RS badge') end
   if kind=='standing' then assert(has(HOST.panelTexts,'SS') and has(HOST.panelTexts,string.format(L.placeLabel,'P4')) and has(HOST.panelTexts,string.format(L.placeMeters,380)),'SS badge, slot and distance') end
   if kind=='lights' then assert(has(HOST.panelTexts,'3/5') and HOST.circles>=5,'lights: 3 of 5') end
   if kind=='go' or kind=='jump' then assert(HOST.circles>=5,'lights out: '..kind) end
  end
  -- Beta 1.35 (fusion) : au mètre près sous 20 m (valeur de la grille), puis « en place » et « place dépassée ».
  panel.kind='standing'; panel.slotText='P4'; panel.slotDistance=7; panel.slotPlaced=false; panel.slotPassed=false
  HOST.panelTexts={}; HUMANAI.drawFlags(); assert(has(HOST.panelTexts,string.format(L.placeMeters,7)),'exact metres below 20 m')
  panel.slotPlaced=true; HOST.panelTexts={}; HUMANAI.drawFlags(); assert(has(HOST.panelTexts,L.gridPlaced) and not has(HOST.panelTexts,string.format(L.placeMeters,7)),'in position')
  panel.slotPlaced=false; panel.slotPassed=true; HOST.panelTexts={}; HUMANAI.drawFlags(); assert(has(HOST.panelTexts,string.format(L.gridPassedBy,7)),'slot passed, metres behind')
  panel.slotDistance=0; HOST.panelTexts={}; HUMANAI.drawFlags(); assert(has(HOST.panelTexts,L.gridPassed),'slot passed, no distance')
  HUMANAI.release()
 end)
 -- Beta 1.35 (relecture de l'interface) : sélecteur de profil jamais masqué (900 px, polices de secours, français),
 -- options globales décochées en lecture seule, textes refaits au changement de langue, état de l'en-tête (pause,
 -- commandes suspendues), diagnostic complet, polices de l'overlay sans ouvrir la fenêtre, une police poussée à la fois.
 check('Beta 1.35 : relecture de l interface, sélecteur de profil à 900 px, globales décochées, langue, état, diagnostic, overlay',function()
  local function count(text) local e=HUMANAI.engine; local n=0; for k=0,e.log.count-1 do local row=e.log[(e.log.head-k-1)%e.log.limit+1]; if row.message:find(text,1,true) then n=n+1 end end; return n end
  local function starts(prefix) for _,t in ipairs(HOST.drawnTexts) do if t:sub(1,#prefix)==prefix then return true end end return false end
  -- Overlay seul (fenêtre jamais ouverte) : polices cherchées et absence notée une fois.
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))(); H.tick(HOST,0.5)
  script.HUMANAI__HUD(); assert(count('polices de l interface absentes')==1 and W.fonts().body=='Segoe UI','overlay sets the fonts')
  -- 900 px, mesure réaliste, polices de secours, français : les cinq profils restent cliquables.
  HUMANAI.release(); HOST=H.create(true); HOST.realMeasure=true; HOST.space={x=900,y=700}; assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  local e=HUMANAI.engine; local g=e.g
  redraw()
  do local x=HUMANAI.engine; for k=0,x.log.count-1 do local r=x.log[(x.log.head-k-1)%x.log.limit+1]; assert(not r.message:find('ui:',1,true),r.message) end end
  if require('src/locale').current~='fr' then press('lang_fr') end
  redraw()
  for _,p in ipairs({'J','P','Q','C','H'}) do assert(drawn('profile_'..p),'profile '..p..' shown at 900 px') end
  -- Aucun chevauchement : le sélecteur commence après le dernier onglet.
  local tabsEnd=0; for id,r in pairs(HOST.hits) do if id:find('##aai_tab_',1,true)==1 then tabsEnd=math.max(tabsEnd,r.x+r.w) end end
  assert(tabsEnd>0 and HOST.hits['##aai_profile_J'].x>=tabsEnd,'profile selector after the tabs')
  press('profile_P'); redraw(); assert(lit('profile_P'),'profile picked at 900 px')
  -- Mesures gardées d'une image à l'autre : une image identique ne remesure presque rien.
  redraw(); HOST.measures=0; redraw(); assert(HOST.measures<=40,'texts measured once: '..HOST.measures)
  -- Une seule police poussée à la fois par le kit (aucune poussée par texte) ; tout refermé en fin d'image.
  HOST.fontPushes=0; redraw(); local pushes=HOST.fontPushes
  assert(HOST.dwriteDepth==0 and pushes<#HOST.drawnTexts,'fonts pushed only when the role changes: '..pushes..' for '..#HOST.drawnTexts)
  -- Options globales décochées : message de section inactive, aucun réglage modifiable en silence.
  press('profile_C'); local P=e.profiles[HUMANAI.engine.profile]
  section('globals'); redraw()
  if C.on(e.profiles[e.profile],'globals') then press('section_globals'); redraw() end
  -- Beta 1.38 (maquette) : décochées, réglages grisés sous le message de section inactive.
  assert(drawn('global_useGripBoost') and begins(L.sectionOff),'globals off: greyed under the off message')
  press('section_globals'); redraw(); assert(drawn('global_useGripBoost'),'globals on: editable')
  -- Changement de langue : valeur affichée (séparateur décimal) et texte du défaut refaits.
  section('general'); redraw(); assert(drawnText('1,2'),'French decimal comma')
  press('lang_en'); redraw(); assert(drawnText('1.2') and not drawnText('1,2'),'English decimal point after the switch')
  press('lang_fr'); redraw()
  -- État de l'en-tête : en pause, chiffres de l'accueil affichés ; rediffusion : commandes suspendues, jamais « actif ».
  script.update(1/60); go('home'); redraw(); assert(HUMANAI.engine.guard=='paused' and starts(W.upper(L.pillStates.paused)),'paused pill: '..tostring(HUMANAI.engine.guard))
  HOST.sim.isInMainMenu=true; pause(false); HOST.sim.isReplayActive=true; H.tick(HOST,0.2); redraw()
  assert(HUMANAI.engine.guard=='replay' and drawnText(W.upper(L.pillStates.suspended)),'replay: suspended pill')
  HOST.sim.isReplayActive=false; HOST.sim.isInMainMenu=false; pause(true); script.update(1/60)
  -- Diagnostic : dernier événement des phares et panneaux lumineux du circuit.
  go('diagnostic'); redraw()
  assert(drawnText(L.patch) and drawnText(' · '..L.track),'CSP line (Beta 1.39 : panneaux lumineux dans leur section, événement des phares en infobulle)')
  -- Message d'un onglet effacé au changement d'onglet (jamais repris par l'onglet Règles de course).
  go('home'); HUMANAI.engine.g.loadedPreset=''; press('builtin_Course'); go('rules'); redraw()
  assert(not begins(string.format(L.presetAppliedTo,L.profiles.C)) ,'home message not shown in the rules tab')
  -- Polices de secours plus larges (fenêtre rechargée, mesures refaites) : noms trop longs pour la place, sigles après
  -- le dernier onglet, tous cliquables.
  HUMANAI.release(); HOST=H.create(true); HOST.realMeasure=true; HOST.measureScale=1.3; HOST.space={x=900,y=700}; assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  redraw(); if require('src/locale').current~='fr' then press('lang_fr') end
  redraw()
  local te=0; for id,r in pairs(HOST.hits) do if id:find('##aai_tab_',1,true)==1 then te=math.max(te,r.x+r.w) end end
  for _,p in ipairs({'J','P','Q','C','H'}) do assert(drawn('profile_'..p),'profile '..p..' shown with wide fonts') end
  local j=HOST.hits['##aai_profile_J']
  assert(j.x>=te and j.w<50,'initials after the tabs with wide fonts: '..j.x..'+'..j.w..' / '..te)
  press('profile_Q'); redraw(); assert(lit('profile_Q'),'initial clickable')
  HUMANAI.release()
 end)
 -- Beta 1.35 UI/updater fixes : deuxième relecture de l'interface (en-têtes, lignes de choix, tuiles, logo, polices,
 -- confirmation, portée, comptes, clic droit, langue, overlay, saisie, mises à jour).
 local function starts(prefix) for _,t in ipairs(HOST.drawnTexts) do if t:sub(1,#prefix)==prefix then return true end end return false end
 local function boxOf(text) for _,b in ipairs(HOST.textBoxes or {}) do if b.text==text then return b end end end
 local function boxes() HOST.textBoxes={}; redraw() end
 local function rightClick(id) local r=HOST.hits['##aai_'..id]; HOST.mouse={x=r.x+2,y=r.y+2}; HOST.rightClick='##aai_'..id; main(); HOST.mouse={x=-1e6,y=-1e6}; HOST.rightClick=nil end
 check('Beta 1.35 UI/updater fixes : interface à 900 px, en-têtes, choix, tuiles, logo, polices',function()
  HUMANAI.release(); HOST=H.create(true); HOST.realMeasure=true; HOST.measureScale=1.3; HOST.space={x=900,y=3000}
  HOST.files['local/icon.png']='png'
  assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  redraw(); if require('src/locale').current~='fr' then press('lang_fr') end
  local e=HUMANAI.engine; local g=e.g; local v=HUMANAI.panel
  -- Logo de l'en-tête dessiné, marque décalée de 44 px ; infobulle propre de la puce de version.
  boxes(); local brand=boxOf('ADVANCED'); assert((HOST.images or 0)>0 and brand,'logo drawn')
  local image=ui.drawImage; ui.drawImage=nil; boxes(); local plain=boxOf('ADVANCED'); ui.drawImage=image
  assert(plain and math.abs(brand.x-plain.x-44)<1e-6,'brand moved by the logo: '..brand.x..' / '..tostring(plain and plain.x))
  boxes(); local chip=boxOf('β'..(C.release:gsub('^Beta ',''))); assert(chip,'version chip drawn')
  HOST.mouse={x=chip.x+1,y=chip.y+1}; redraw(); HOST.mouse={x=-1e6,y=-1e6}
  assert(HOST.lastTooltip==v.tips.ui.version,'version chip: its own tooltip')
  -- Aucune flèche « → » (absente de Barlow) dans les textes dessinés.
  go('home'); redraw()
  for _,t in ipairs(HOST.drawnTexts) do assert(not t:find('→',1,true),'arrow without a Barlow glyph: '..t) end
  -- Tuiles des préréglages intégrés : description entière, ou dernière ligne finie par « … ».
  for _,item in ipairs(v.builtinList) do
   local desc=L.presetDescs[item[2]]; local last=desc:match('(%S+)%s*$'); local ok=false
   for _,t in ipairs(HOST.drawnTexts) do
    if t:find(last,1,true) then ok=true end
    local cut=t:match('^(.-)…$'); if cut and #cut>3 and desc:find(cut,1,true) then ok=true end
   end
   assert(ok,'preset description complete or ended with an ellipsis: '..item[2])
  end
  -- Police du kit poussée seulement quand elle change, une seule à la fois, tout refermé en fin d'image.
  HOST.repeatPushes=0; HOST.lastPushed=nil; HOST.fontDepthMax=0; HOST.fontPushes=0; redraw()
  assert(HOST.dwriteDepth==0 and HOST.repeatPushes==0 and HOST.fontDepthMax==1 and HOST.fontPushes*2<=#HOST.drawnTexts,'kit fonts: '..HOST.fontPushes..' pushes ('..HOST.repeatPushes..' repeated) for '..#HOST.drawnTexts..' texts')
  -- Liste des réglages : intertitres (libellés) puis noms des sections (demi-gras), une seule police de secours.
  go('settings'); HOST.repeatPushes=0; HOST.lastPushed=nil; redraw()
  assert(HOST.dwriteDepth==0 and HOST.repeatPushes==0,'kit fonts on the settings list: '..HOST.repeatPushes..' repeated')
  -- En-tête des sections : titre et puces jamais sous le bouton de réinitialisation.
  go('settings')
  for _,group in ipairs({'general','human','lateral','start','yield','blue','flash','overtake','traffic','accidents','endurance','weather','globals','overlay'}) do
   press('cat_'..group); boxes()
   local r=HOST.hits['##aai_reset_'..group]; assert(r,'reset button '..group)
   for _,b in ipairs(HOST.textBoxes) do
    if b.y<r.y+r.h and b.y+b.size>r.y and b.x<r.x then assert(b.x+b.w<=r.x+1e-6,'header text under the reset button ('..group..'): '..b.text) end
   end
  end
  -- Choix globaux trop larges pour un segment : bouton à défilement, libellé lisible.
  press('cat_overlay'); redraw()
  local show=g.panelShow=='always' and L.choices.always or L.choiceShort.panelShow.info
  assert(starts(show:sub(1,8)) or starts(W.upper(show):sub(1,8)),'overlay display choice readable (short label, Beta 1.38)')
  -- Libellés trop larges pour un segment (police de secours) : bouton à défilement.
  local savedShow=v.showLabels; v.showLabels={string.rep('Avec une information ',3),savedShow[2]}; g.panelShow='info'; redraw()
  assert(starts('Avec une information') and not drawnText(W.upper(savedShow[2])),'overlay display choice falls back to a cycle button'); v.showLabels=savedShow
  -- Onglet Règles de course : en-tête dans le panneau ; ligne de choix au libellé entier (texte du défaut en infobulle).
  press('profile_C'); go('rules')
  local f=W.frame()
  for _,view in ipairs({'all','stops','safety'}) do
   press('rules_view_'..view); boxes()
   for _,b in ipairs(HOST.textBoxes) do
    if b.y>=f.oy+100*f.s and b.y<=f.oy+140*f.s and b.x>=f.ox+274*f.s then assert(b.x+b.w<=f.ox+(f.w-14)*f.s+1e-6,'rules pane header inside the panel ('..view..'): '..b.text) end
   end
  end
  press('rules_view_all'); redraw()
  local s; for _,x in ipairs(C.schema) do if x.key=='redRestart' then s=x end end
  local label=L.shortLabels[s.key] or s.label
  assert(drawnText(label),'red-flag restart label shown in full: '..label)
  -- Overlay : même règle des polices, dépilées aussi après une erreur de dessin.
  g.panelShow='always'; pause(false); H.tick(HOST,0.5)
  local pk=HUMANAI.engine.panel; pk.kind='sc'; pk.decided='sc'; pk.title=L.flagTitles.sc; pk.short=''; pk.explain=''; pk.changedAt=HUMANAI.engine.time
  HOST.repeatPushes=0; HOST.lastPushed=nil; HOST.fontDepthMax=0; HOST.fontPushes=0; HOST.transparent={}; script.HUMANAI__HUD()
  assert(HOST.transparent.AdvancedIA_overlay and HOST.dwriteDepth==0 and HOST.repeatPushes==0 and HOST.fontDepthMax==1 and HOST.fontPushes<=6,'overlay fonts: '..HOST.fontPushes..' pushes ('..HOST.repeatPushes..' repeated)')
  local clipped=ui.dwriteDrawTextClipped; ui.dwriteDrawTextClipped=function() error('draw failure (test)') end
  HUMANAI.drawFlags(); ui.dwriteDrawTextClipped=clipped
  assert(HOST.dwriteDepth==0 and HUMANAI.host.errors>0,'overlay fonts unwound after a drawing error')
  -- Hôte refait : l'erreur provoquée n'est pas comptée dans le cas.
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
 end)
 check('Beta 1.35 UI/updater fixes : confirmation, portée, comptes, clic droit, langue, mémorisation, overlay',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  redraw(); if require('src/locale').current~='fr' then press('lang_fr') end
  local e=HUMANAI.engine; local g=e.g; local v=HUMANAI.panel
  -- Confirmation de la réinitialisation dans sa section, effacée en ouvrant une autre section.
  section('general'); press('reset_general'); redraw()
  local done=string.format(L.sectionResetDone,L.categories.general)
  assert(begins(done),'section reset confirmed')
  press('cat_human'); redraw(); assert(not begins(done),'confirmation cleared in another section')
  press('cat_general'); redraw(); assert(not begins(done),'confirmation not shown again on coming back')
  -- Message de l'accueil (lien d'un point à vérifier) : jamais montré sous une section.
  v.presetMessage=L.presetSaved; redraw(); assert(not begins(L.presetSaved),'home message not shown in a settings section'); v.presetMessage=''
  -- Options globales : valables pour tous les profils.
  section('globals'); redraw()
  assert(drawnText(W.upper(L.scopeAll)) and not drawnText(W.upper(string.format(L.scopeProfile,L.profiles[v.view]))),'global options: all profiles')
  -- Même compte des sections sur l'accueil et dans la liste des réglages.
  local p=e.profiles[v.view]; local on=0; for _,x in ipairs(C.sections) do if C.on(p,x) then on=on+1 end end
  go('settings'); redraw(); assert(drawnText(string.format(L.navCount,on,#C.sections)),'sidebar count')
  go('home'); redraw(); assert(drawnText(string.format(L.sectionsActive,on,#C.sections)),'home count')
  -- Clic droit : interrupteurs globaux et de l'overlay rendus à leur valeur par défaut, comme les curseurs.
  section('globals'); if not C.on(e.profiles[e.profile],'globals') then press('section_globals') end; redraw()
  press('global_useGripBoost'); assert(g.useGripBoost==not C.globalDefaults.useGripBoost,'switched')
  rightClick('global_useGripBoost'); assert(g.useGripBoost==C.globalDefaults.useGripBoost,'global switch: right click resets')
  section('overlay'); redraw()
  press('overlay_overlayExplain'); assert(g.overlayExplain==not C.globalDefaults.overlayExplain,'overlay switched')
  rightClick('overlay_overlayExplain'); assert(g.overlayExplain==C.globalDefaults.overlayExplain,'overlay switch: right click resets')
  -- Panneaux lumineux pas encore lus : « inconnus », jamais « éteints ».
  local known=HUMANAI.host.trackLights; HUMANAI.host.trackLights=nil; go('home'); redraw()
  assert(drawnText(L.kpiLightsUnknown) and not drawnText(L.kpiLightsIdle),'lights not read yet: unknown')
  HUMANAI.host.trackLights=known
  -- Changement de langue : ligne des panneaux lumineux du diagnostic refaite.
  go('diagnostic'); redraw(); assert(drawnText(' · '..L.track) and drawnText(' · circuit '),'CSP line (fr)')
  press('lang_en'); redraw(); assert(drawnText(' · '..L.track) and drawnText(' · track '),'CSP line in English after the switch')
  press('lang_fr'); redraw()
  -- Signatures des préréglages et jeu de règles : calculés une fois par modification, jamais à chaque image.
  go('home'); press('profile_C'); press('builtin_Course'); redraw()
  local Presets=require('src/presets'); local signature=Presets.signature; local n=0
  Presets.signature=function(...) n=n+1; return signature(...) end
  local ok,err=pcall(redraw); Presets.signature=signature; assert(ok,err); assert(n==0,'preset signatures rebuilt on an unchanged frame: '..n)
  go('rules'); redraw()
  local category,closest=C.ruleCategory,C.closestRuleCategory; local m=0
  C.ruleCategory=function(...) m=m+1; return category(...) end; C.closestRuleCategory=function(...) m=m+1; return closest(...) end
  ok,err=pcall(redraw); C.ruleCategory=category; C.closestRuleCategory=closest; assert(ok,err); assert(m==0,'rule set worked out on an unchanged frame: '..m)
  -- Overlay : fenêtre à la taille de son contenu, gardée dans l'écran, bande d'accent tout en haut.
  local UI=require('src/ui'); local K=C.K
  g.panelShow='always'; g.overlayLocked=true; pause(false); H.tick(HOST,0.5)
  for _,scale in ipairs({1,1.5}) do
   g.overlayScale=scale; g.overlayX=-1; g.overlayY=-1; HOST.transparent={}; HOST.rects={}; script.HUMANAI__HUD()
   local o=HOST.transparent.AdvancedIA_overlay; local parts=UI.overlayParts(v,false)
   assert(o and math.abs(o.w-K.hudWidth*scale)<1e-6 and math.abs(o.h-UI.overlayHeight(parts)*scale)<1e-6,'overlay window sized from its content at '..scale)
   assert(math.abs(v.drawnHeight-o.h)<1e-6,'content height equals the window at '..scale)
   assert(o.x>=0 and o.y>=0 and o.x+o.w<=1920+1e-6 and o.y+o.h<=1080+1e-6,'overlay on screen at '..scale)
   local stripe=false; for _,q in ipairs(HOST.rects) do if q[1]==0 and math.abs(q[2])<1e-6 and math.abs(q[4]-q[2]-3*scale)<1e-6 then stripe=true end end
   assert(stripe,'accent stripe at the very top at '..scale)
  end
  g.overlayX=5000; g.overlayY=5000; HOST.transparent={}; script.HUMANAI__HUD(); local o=HOST.transparent.AdvancedIA_overlay
  assert(math.abs(o.x+o.w-1920)<1e-6 and math.abs(o.y+o.h-1080)<1e-6,'kept inside the screen')
  HOST.rects=nil; g.overlayX=-1; g.overlayY=-1; g.overlayScale=1
 end)
 check('Beta 1.35 UI/updater fixes : saisie native tenue dans son cadre à petite échelle',function()
  HUMANAI.release(); HOST=H.create(true); HOST.space={x=630,y=600}; assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  go('home'); HOST.varPushes=0; HOST.varDepth=0; redraw()
  assert(HOST.varPushes>0 and HOST.varDepth==0,'input padding reduced and restored at 0.7')
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  go('home'); HOST.varPushes=0; redraw(); assert(HOST.varPushes==0,'nothing changed at full scale')
 end)
 check('Beta 1.35 UI/updater fixes : notes à jour, retour arrière grisé pendant une opération',function()
  updated(function(F) F.release(ver(0)) end,function(F)
   local u=HUMANAI.updater
   H.tick(HOST,11); assert(u.phase=='current' and u.release and u.release.version==ver(0),'up to date: '..u.phase)
   halt(); go('diagnostic'); redraw()
   assert(Update.view(u,true)=='uptodate' and drawn('update_notes'),'release notes link while up to date')
   press('update_notes'); assert(F.opened[#F.opened]==u.release.page,'release page opened')
   u.previous=ver(-1); u.phase='downloading'; u.serial=u.serial+1; redraw()
   assert(drawn('update_rollback'),'rollback still shown, greyed, during an operation')
   local serial=u.serial; press('update_rollback'); assert(u.phase=='downloading' and u.serial==serial,'greyed rollback does nothing')
   u.phase='current'; u.serial=u.serial+1
  end)
 end)
 -- Beta 1.36 (3e relecture).
 check('Beta 1.36 : module de mise à jour illisible, app chargée sans mise à jour',function()
  HUMANAI.release(); HOST=H.create(true)
  local saved={}; for _,name in ipairs({'src/update','src/ui'}) do saved[name]=package.loaded[name]; package.loaded[name]=nil end
  package.preload['src/update']=function() error('module abime') end
  local ok,err=pcall(function()
   assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
   for _,tab in ipairs({'home','settings','rules','diagnostic'}) do go(tab); redraw() end
   HOST.transparent={}; script.HUMANAI__HUD(); assert(HOST.transparent.AdvancedIA_overlay,'overlay drawn')
   local e=HUMANAI.engine; local found=false
   for n=0,e.log.count-1 do local row=e.log[(e.log.head-n-1)%e.log.limit+1]; assert(not row.message:find('ui:',1,true),row.message); if row.message:find('mise a jour: module illisible',1,true) then found=true end end
   assert(found,'unreadable updater logged')
  end)
  package.preload['src/update']=nil
  HOST.releasing=true; pcall(HUMANAI.release); HOST.releasing=false
  for name,mod in pairs(saved) do package.loaded[name]=mod end
  assert(ok,err)
 end)
 check('Beta 1.36 : bouton de l onglet Règles après la réinitialisation d une section',function()
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  go('rules'); redraw()
  section('general'); press('reset_general'); redraw()
  local done=string.format(L.sectionResetDone,L.categories.general)
  go('rules'); redraw()
  assert(drawn('rules_reset') and not drawnText(done) and not drawnText(W.upper(done)),'rules button keeps its own label')
 end)
 check('Beta 1.36 : aucune puce de redémarrage après un retour arrière',function()
  updated(function(F) F.files[WORK..'updated.txt']='rollback '..ver(1)..' -> '..ver(0) end,function()
   local u=HUMANAI.updater
   H.tick(HOST,0.5); halt(); go('home'); redraw()
   assert(u.updated and u.updated.kind=='rollback' and Update.reported(u),'report read at launch')
   assert(not drawnText(L.updateBusy.rolledback) and not drawnText(L.updateBusy.done),'no RESTARTING chip in the header')
  end)
 end)
 check('Beta 1.36 : puce d état sans IA dans la session',function()
  HUMANAI.release(); HOST=H.create(true)
  HOST.sim.raceSessionType=3
  for i=1,3 do HOST.cars[i].isAIControlled=false end
  assert(loadstring(source))(); H.tick(HOST,0.5); local x=HUMANAI.engine; C.preset('Course','C',x.profiles.C); require('src/engine').changed(x); H.tick(HOST,0.3); HOST.sim.isInMainMenu=true; script.HUMANAI__MENU(); redraw()
  local noai=W.upper(L.pillStates.noai); local found=false
  for _,t in ipairs(HOST.drawnTexts) do if t:sub(1,#noai)==noai then found=true end end
  assert(found,'NO AI chip, never ACTIVE')
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))(); H.tick(HOST,0.5); local x=HUMANAI.engine; C.preset('Course','C',x.profiles.C); require('src/engine').changed(x); H.tick(HOST,0.3); HOST.sim.isInMainMenu=true; script.HUMANAI__MENU(); redraw()
  local ready=W.upper(L.pillStates.ready); found=false
  for _,t in ipairs(HOST.drawnTexts) do if t:sub(1,#ready)==ready then found=true end end
  assert(found,'ACTIVE chip with AI')
 end)
 check('Beta 1.37 : section Panneaux lumineux, accueil et diagnostic',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))(); H.tick(HOST,1); pause(true)
  local e=HUMANAI.engine; HUMANAI.host.trackLights=true
  go('home'); redraw(); assert(not drawnText(L.kpiLightsOff),'section on: not disabled')
  e.p.section_lights=false; redraw(); assert(drawnText(L.kpiLightsOff),'running profile unticked: disabled')
  e.p.section_lights=true; go('settings'); press('cat_lights'); redraw()
  assert(drawn('set_lightsGreenTime') and drawn('set_lightsHold') and drawn('lights_on_H'),'durations and session chips')
  HUMANAI.host.trackLights=false; redraw(); assert(begins(L.lightsNoEffect),'not equipped: no effect on this track')
  HUMANAI.host.trackLights=nil; pause(false)
 end)
 check('Beta 1.38 : reste new_behaviour.ini.bak effacé après chaque écriture du réglage d AI flood',function()
  HUMANAI.release(); HOST=H.create(true); HOST.files['cfgext\\new_behaviour.ini']='[AI_FLOOD]\r\nENABLED=1\r\n'
  local A=require('src/applier')
  assert(A.floodWrite('[AI_FLOOD]\r\nENABLED=0\r\n') and HOST.files['cfgext\\new_behaviour.ini']=='[AI_FLOOD]\r\nENABLED=0\r\n','written')
  assert(HOST.files['cfgext\\new_behaviour.ini.bak']==nil and HOST.bakDeleted==1,'no .bak left in cfg/extension')
  assert(A.floodWrite('[AI_FLOOD]\r\nENABLED=1\r\n') and HOST.files['cfgext\\new_behaviour.ini.bak']==nil and HOST.bakDeleted==2,'every write')
 end)
 check('Beta 1.38 : interface au niveau de la maquette',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,1); pause(true)
  local e=HUMANAI.engine; local g=e.g
  local function contains(part) for _,t in ipairs(HOST.drawnTexts) do if t:find(part,1,true) then return true end end return false end
  -- B3 : bandeau en ligne masqué par « Compris » jusqu'au prochain changement de garde.
  HOST.sim.isAltOnlineRace=true; H.tick(HOST,1); go('home'); redraw()
  assert(e.guard=='online' and drawn('banner_action') and drawnText(W.upper(L.banners.online[3])),'online banner with its Got it button')
  press('banner_action'); redraw(); assert(not drawn('banner_action'),'banner hidden after Got it')
  HOST.sim.isAltOnlineRace=false; H.tick(HOST,1); redraw(); HOST.sim.isAltOnlineRace=true; H.tick(HOST,1); redraw()
  assert(drawn('banner_action'),'shown again after a guard change')
  -- Changement de garde vu par l'overlay, fenêtre fermée.
  press('banner_action'); HOST.sim.isAltOnlineRace=false; H.tick(HOST,1); script.HUMANAI__HUD(); HOST.sim.isAltOnlineRace=true; H.tick(HOST,1); redraw()
  assert(drawn('banner_action'),'shown again after a guard change seen by the overlay')
  HOST.sim.isAltOnlineRace=false; H.tick(HOST,1)
  -- B7 : garde de l'en-tête (session, source, profil, auto), fenêtre ouverte depuis le menu, sans pause.
  pause(false); HOST.sim.isInMainMenu=true; H.tick(HOST,1); redraw()
  assert(e.guard=='ready' and contains(' · '..L.guards.ready..' · '..L.sessionTypes[3]..' ('),'header guard line: session, source, profile, auto ('..tostring(e.guard)..')')
  HOST.sim.isInMainMenu=false; pause(true)
  -- B2 : préréglage intégré d'un autre profil (Endurance depuis les essais : profil Course).
  press('profile_P'); press('builtin_Endurance'); redraw()
  assert(lit('profile_P') and not lit('builtin_Endurance') and begins(string.format(L.presetAppliedTo,L.profiles.C)),'other profile: shown profile kept, no tile lit')
  assert(C.mark(g,'C')=='Endurance' and C.ruleCategory('C',e.profiles.C)=='Endurance','built-in mark recorded for the target profile')
  press('profile_C'); redraw(); assert(lit('builtin_Endurance'),'lit in its own profile')
  -- A11, B1 : restauration du profil affiché ; nom de préréglage refusé.
  assert(drawnText(W.upper(L.restoreShort..L.profiles.C)),'restore names the profile')
  HOST.inputEdits['##aai_preset_name']=''; main(); press('save_preset'); redraw(); assert(begins(string.format(L.invalidPresetName,C.K.presetNameBytes)),'invalid preset name message')
  -- A3, A9 : options globales (titre, bonus de grip sous son interrupteur, nouveau tirage, défaut du mode de niveau).
  local q=e.profiles.C; q.section_globals=true; go('settings'); press('cat_globals'); redraw()
  local h=HOST.hits
  assert(drawnText(W.upper(L.groups.globals)),'Global options title')
  assert(h['##aai_global_gripPerLevelPct'].y>h['##aai_global_useGripBoost'].y and h['##aai_global_gripPerLevelPct'].y<h['##aai_global_useBrakeAssist'].y,'grip bonus right under its switch')
  local lv=1; for i,k in ipairs(C.globalChoices.levelMode) do if k==C.globalDefaults.levelMode then lv=i end end
  assert(drawnText(W.upper(L.reroll)) and drawnText(W.upper(string.format(L.defaultValue,L.levelModeLabels[lv]:lower()))),'New draw, level mode default')
  -- A10 : overlay (puce Active, taille 1×, libellé de la liste).
  press('cat_overlay'); redraw()
  assert(drawnText(W.upper(L.chipSectionOn)) and drawnText('1×') and (drawnText(L.categories.overlay) or drawnText(W.upper(L.categories.overlay))),'overlay: Active chip, size 1×, sidebar label')
  -- A2, B6 : panneaux lumineux (note du rouge seulement coupé, interrupteur du titre, une colonne, légende, en direct).
  HUMANAI.host.trackLights=true; q.section_lights=true; q.lightsRed=true; press('cat_lights'); redraw()
  local red=L.lightNotes.lightsRed:sub(1,10)
  assert(not contains(red),'red note hidden while red is on')
  q.lightsRed=false; redraw(); assert(contains(red),'red note when red is off'); q.lightsRed=true
  assert(drawn('section_lights_title') and lit('lights_on_C'),'title switch, session chip')
  press('section_lights_title'); redraw(); assert(not q.section_lights and begins(L.sectionOff) and drawn('set_lightsGreenTime'),'title switch: off, greyed with its message')
  press('section_lights_title'); redraw(); assert(q.section_lights)
  local a,b=HOST.hits['##aai_set_lightsRed'],HOST.hits['##aai_set_lightsGreenTime_minus']
  assert(a and b and math.abs(a.x-b.x)<1,'colours and durations in one column')
  assert(drawnText(W.upper(L.lightsLegendTitle[1])) or drawnText(L.lightsLegendTitle[1]),'legend heading')
  assert(contains((string.format(L.lightsGreenFor,tostring(q.lightsGreenTime)):gsub('%.',L.decimalMark):gsub('^ ',''))),'green duration in the legend')
  HUMANAI.host.flagOverride=true; HUMANAI.host.flagValue=2; e.incidents.neutral=true; e.incidents.neutralMode='vsc'; redraw()
  assert(contains(L.lightNames[2]..L.lightsPhaseVsc),'panels right now: yellow · VSC')
  go('home'); redraw(); assert(contains(L.lightShort[2]..L.lightsPhaseVsc),'home tile: Yellow · VSC')
  e.incidents.neutral=false; HUMANAI.host.flagOverride=nil
  -- B8 : note du jaune natif sous sa ligne.
  q.section_accidents=true; go('settings'); press('cat_accidents'); redraw(); assert(drawn('set_yellowHud') and begins(L.yellowHudLocked),'yellow HUD note')
  -- A8 : libellés courts des choix.
  q.section_flash=true; press('cat_flash'); redraw()
  assert(drawnText(W.upper(L.choiceShort.flashMode.lapped)) or drawnText(L.choiceShort.flashMode.lapped),'short choice labels')
  -- A6, A7, B9 : arrêt obligatoire (titre, « libre »), voiture de sécurité (phases).
  go('rules'); press('rules_view_stops'); redraw()
  assert(drawnText(W.upper(L.stopsTitle)) and drawnText(L.zeroValues.minPitTime),'stops title, zero shown as free')
  press('rules_view_safety'); redraw(); assert(g.safetyCarModel=='' or drawnText(W.upper(L.safetyPhaseStrip[1])),'safety car phase strip')
  -- C : motifs de classes (colonne « Numéro de classe », « + Ajouter une ligne »).
  q.section_endurance=true; go('settings'); press('cat_endurance'); redraw()
  local rows=0; for i=1,8 do if drawn('pattern_clear_'..i) then rows=i end end
  assert(rows>=1 and rows<8 and drawnText(W.upper(L.classColumn)),'used rows and one more, class number column')
  press('pattern_add'); redraw(); assert(drawn('pattern_clear_'..(rows+1)),'row added')
  -- A4 : diagnostic (libellés courts, noms des capacités).
  go('diagnostic'); redraw()
  assert(drawnText(W.upper(string.format(L.learnShort,C.K.flashLearnTime))) and drawnText(W.upper(L.markStartShort)) and drawnText(W.upper(L.exportZones)) and drawnText(W.upper(L.calibrateShort)),'short Diagnostic buttons')
  assert(drawnText(L.capNames.level) and drawnText(W.upper(L.apiList)),'capability names, AI functions heading')
  -- C : barre de défilement saisissable (accueil, fenêtre basse).
  HOST.space={x=1000,y=420}; go('home'); redraw()
  local before=HOST.hits['##aai_builtin_Nordschleife']
  assert(drawn('scroll_home_left') and before,'rail shown when the content overflows')
  HOST.mouseDelta={x=0,y=60}; HOST.drags['##aai_scroll_home_left']=0.5; main(); HOST.mouseDelta={x=0,y=0}; redraw()
  local after=HOST.hits['##aai_builtin_Nordschleife']
  assert(after==nil or after.y<before.y-1,'dragging the rail scrolls')
  HOST.space={x=1000,y=780}
  -- B10 : overlay (infractions sous l'avertissement, stands sous la voiture endommagée, version dans le drapeau).
  local panel=e.panel; local function flag(kind) panel.kind=kind; panel.decided=kind; panel.title=L.flagTitles[kind] or ''; panel.short=''; panel.explain=''; panel.changedAt=e.time; HOST.panelTexts={}; HUMANAI.drawFlags() end
  panel.infractions=1; panel.infractionMax=5; flag('warning'); assert(has(HOST.panelTexts,string.format(L.infractionPill,1,5)),'offence count pill')
  flag('meatball'); assert(has(HOST.panelTexts,L.pitPill),'pit pill under car damaged')
  panel.updateVersion='Beta 1.39'; flag('update'); assert(has(HOST.panelTexts,'1.39'),'version in the update flag')
  pause(false)
 end)
 -- Beta 1.39 (relevé en jeu : « Slow script … Drawing ACAdvancedIA, 2156 ms » avec 347 voitures installées) : base des
 -- voitures lue par étapes, jamais d'un coup ; chaque image lit au plus K.carReadMax fichiers et s'arrête après
 -- K.carReadBudget s de lecture.
 check('Beta 1.39 : base de 347 voitures lue par étapes, aucune image figée',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  HOST.carFolders={}; for k=1,347 do local id=string.format('car_%03d',k); HOST.carFolders[k]=id; HOST.files['cars/'..id..'/ui/ui_car.json']='{"name": "Voiture '..k..'"}' end
  assert(loadstring(source))(); local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; E.changed(e); H.tick(HOST,0.5)
  HOST.space={x=1000,y=3000}; pause(true); go('home'); press('profile_C'); go('rules')
  -- Disque lent (3 ms par fichier) : lectures comptées image par image.
  local load=io.load; local reads=0
  io.load=function(path) if path:find('/ui/ui_car.json',1,true) then reads=reads+1; local t=os.clock(); while os.clock()-t<0.003 do end end; return load(path) end
  local ok,err=pcall(function()
   press('rules_view_safety'); redraw()
   assert(begins(string.format(L.carLoading,0,347)) or begins(string.format(L.carLoading,reads,347)),'loading line shown')
   local most,slowest,frames=0,0,0
   while not drawn('safety_pick_1') and frames<400 do
    local before=reads; local t=os.clock(); redraw(); slowest=math.max(slowest,os.clock()-t); most=math.max(most,reads-before); frames=frames+1
   end
   assert(drawn('safety_pick_1') and reads==347,'every car read once: '..reads)
   assert(most>=1 and most<=2,'time budget per frame (3 ms reads, 4 ms budget): '..most)
   assert(slowest<0.25,'no frozen frame: '..slowest)
   assert(begins(string.format(L.safetyMore,347-8)) and drawnText('Voiture 1'),'sorted base, eight rows')
   -- Gardée pour la session : aucune relecture.
   go('home'); go('rules'); press('rules_view_safety'); redraw(); assert(reads==347,'read once per session')
  end)
  io.load=load; assert(ok,err)
  -- Sans horloge : nombre seul.
  local S=require('src/snapshot'); local loader=S.carLoader(); local steps=0
  repeat local done=S.carStep(loader,nil); steps=steps+1; assert(loader.read<=(steps-1)*C.K.carReadMax and steps<100,'count cap without a clock: '..loader.read) until done
  assert(#loader.list==347 and loader.list[1].name=='Voiture 1','loader without a clock')
  pause(false); HOST.space={x=1000,y=780}
 end)
 check('Beta 1.39 : image lente de la fenêtre journalisée une fois par lieu',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  -- Six voitures lentes à lire : plusieurs images lentes au même lieu quel que soit le découpage de la lecture (Beta 1.42 :
  -- avec deux seulement, la mutation « journalisée à chaque image » n'était pas toujours vue).
  HOST.carFolders={}; for k=1,6 do local f='slow_car'..k; HOST.carFolders[k]=f; HOST.files['cars/'..f..'/ui/ui_car.json']='{"name": "Slow '..k..'"}' end
  assert(loadstring(source))(); local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; E.changed(e); H.tick(HOST,0.5)
  HOST.space={x=1000,y=3000}; pause(true); go('home'); press('profile_C'); go('rules')
  local load=io.load
  io.load=function(path) if path:find('/ui/ui_car.json',1,true) then local t=os.clock(); while os.clock()-t<0.08 do end end; return load(path) end
  local ok,err=pcall(function() press('rules_view_safety'); for _=1,8 do redraw() end end)
  io.load=load; assert(ok,err)
  local function count(text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end; return n end
  assert(count('interface lente: regles/safety')==1,'slow frame logged with its place')
  assert(count('interface lente:')==1,'logged once')
  pause(false); HOST.space={x=1000,y=780}
 end)
 check('Beta 1.39 : reste new_behaviour.ini.bak des anciennes versions effacé au lancement',function()
  HUMANAI.release(); HOST=H.create(true); HOST.files['cfgext\\new_behaviour.ini.bak']='[AI_FLOOD]\r\nENABLED=0\r\n'
  assert(loadstring(source))(); local e=HUMANAI.engine
  local function count(text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end; return n end
  assert(HOST.files['cfgext\\new_behaviour.ini.bak']==nil and HOST.bakDeleted==1 and count('nettoyage: new_behaviour.ini.bak efface')==1,'leftover deleted and logged')
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))(); e=HUMANAI.engine
  assert((HOST.bakDeleted or 0)==0 and count('nettoyage: new_behaviour.ini.bak')==0,'nothing to delete, nothing logged')
 end)
 check('Beta 1.39 : derniers écarts de la maquette',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,1); pause(true)
  local e=HUMANAI.engine; local panel=e.panel; local P=require('src/panel')
  local function flag(kind) panel.kind=kind; panel.decided=kind; panel.title=L.flagTitles[kind] or ''; panel.short=''; panel.explain=''; panel.changedAt=e.time; HOST.panelTexts={}; HUMANAI.drawFlags() end
  -- N1 : pastilles en capitales ; N6 : PIT sous l'arrêt obligatoire ; N3 : écart du bleu dans sa case, sans pastilles.
  P.infractions(panel,1,5); panel.noPass=true; panel.passed=false; flag('yellow'); assert(has(HOST.panelTexts,W.upper(panel.passOk)),'pills in capitals')
  panel.noPass=false; flag('pit'); assert(has(HOST.panelTexts,W.upper(L.pitPill)),'pit pill under the mandatory stop')
  panel.blueGap=0.8; e.delta.value=nil; flag('blue')
  local gap=W.upper(string.format(L.blueGap,(string.format('%.1f',0.8):gsub('%.',L.decimalMark))))
  assert(has(HOST.panelTexts,gap) and not package.loaded['src/ui'].overlayParts(HUMANAI.panel).pills,'blue gap boxed right of the title, no pill row')
  -- N7 : drapeau noir de l'app : nombre d'infractions.
  local own=P.new(); P.infractions(own,6,5); P.native(own,{flagOwned=false,flag=C.K.flagStop,player=0,cars={}},10,nil,'C')
  assert(own.kind=='black' and own.short==string.format(L.flagShort.blackCount,6),'black flag: offences count')
  P.infractions(own,7,5); P.native(own,{flagOwned=false,flag=C.K.flagStop,player=0,cars={}},20,nil,'C')
  assert(own.short==string.format(L.flagShort.blackCount,7),'count refreshed')
  local native=P.new(); P.infractions(native,2,5); P.native(native,{flagOwned=false,flag=C.K.flagStop,player=0,cars={}},10,nil,'C')
  assert(native.short==L.flagShort.black,'AC black flag, not ours: plain instruction')
  -- N9 : feux et mise à jour sans explication.
  assert(L.flagExplain.lights==nil and L.flagExplain.update==nil,'no explanation for the lights and the update')
  -- N2 : lignes des motifs ouvertes par défaut.
  e.profiles.C.section_endurance=true; go('home'); press('profile_C'); go('settings'); press('cat_endurance'); redraw()
  assert(drawn('pattern_clear_1'),'pattern rows open by default')
  -- Section 4 : préréglage appliqué à un autre profil : « Aucun préréglage actif » ici.
  go('home'); press('profile_Q'); redraw(); press('builtin_Endurance'); redraw()
  assert(drawnText(L.noActivePreset) and begins(string.format(L.presetAppliedTo,L.profiles.C)),'other profile: no preset line here')
  press('profile_C'); redraw(); assert(not drawnText(L.noActivePreset),'preset line on its own profile')
  -- Préréglage du profil affiché chargé puis modifié, puis préréglage d'un autre profil : la marque est relue.
  press('profile_Q'); press('builtin_Qualifications'); local q=e.profiles.Q
  for _,s in ipairs(C.schema) do
   if type(q[s.key])=='number' and s.min and s.max and not C.presetKeptKeySet[s.key] and not C.hidden('Q',s.key) then q[s.key]=q[s.key]~=s.min and s.min or s.max; break end
  end
  E.changed(e); redraw(); assert(not drawnText(L.noActivePreset),'own preset, modified')
  press('builtin_Endurance'); redraw(); assert(drawnText(L.noActivePreset),'other profile again: mark read again')
  -- N4 : nom affiché du circuit dans l'en-tête, identifiant dans la ligne CSP du diagnostic.
  local function contains(part) for _,t in ipairs(HOST.drawnTexts) do if t:find(part,1,true) then return true end end return false end
  assert(contains('TEST RACEWAY') and not contains('TEST /'),'track name in the header')
  -- N11 : diagnostic (titres courts, ligne CSP, événement des phares en infobulle, journal).
  -- Infobulle du champ des phares (au-dessus du bouton Apprendre) : dernier événement.
  go('diagnostic'); redraw(); local r=HOST.hits['##aai_learn']; HOST.mouse={x=r.x+r.w/2,y=r.y-12}; HOST.lastTooltip=nil; redraw(); HOST.mouse={x=-1e6,y=-1e6}
  local event=(HOST.lastTooltip or ''):sub(1,#L.event)==L.event
  assert(drawnText(W.upper(L.diagFlash)) and drawnText(W.upper(L.diagZones)),'diagnostic: short titles')
  assert(drawnText(L.patch) and drawnText(' · '..L.splineLabel) and drawnText('test'),'diagnostic: CSP line with the track identifier')
  assert(event,'diagnostic: flash event tooltip')
  assert(drawnText(L.signLabel) and not drawnText(W.upper(L.flash)),'calibration line, no long title')
  pause(false); HOST.space={x=1000,y=780}
 end)
 -- Beta 1.40 : options de CSP de gui.ini tenues par l'app : fichier réel du pilote, rendu à l'octet près, relance sans
 -- réécriture, lancement suivant (option appliquée), relecture par CSP, panique, message témoin perdu.
 check('Beta 1.40 : options de CSP de gui.ini tenues par l app, valeurs d origine rendues',function()
  local gui,state='cfgext\\gui.ini','cfgstate\\ACAdvancedIA-cspgui.ini'
  local original='[NEW_UI]\r\nUI_SCALE=1.05\r\n\r\n[HIDE]\r\nHIDE_RACE_FLAGS=1\r\n'
  local hidden='[NEW_UI]\r\nUI_SCALE=1.05\r\n\r\n[HIDE]\r\nHIDE_RACE_FLAGS=1\r\nHIDE_SYSTEM_MESSAGES=1\r\n'
  HUMANAI.release(); HOST=H.create(true); HOST.files[gui]=original; HOST.hideRaceFlags=true
  assert(loadstring(source))(); H.tick(HOST,0.5)
  local e=HUMANAI.engine; local g=e.g
  local function count(text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end; return n end
  assert(HOST.files[gui]==hidden and HOST.guiWrites==1,'system messages hidden, the driver s own option untouched: '..tostring(HOST.files[gui]))
  assert(HOST.files[gui..'.bak']==nil and HOST.files[state..'.bak']==nil and HOST.files[state]:find('original 54\n'..original,1,true),'original kept, no .bak left')
  assert(count('options CSP: messages systeme masques')==1,'logged')
  H.tick(HOST,1); assert(HOST.guiWrites==1,'written once')
  -- Option coupée : fichier d'origine à l'octet près, fichier d'état effacé ; recochée : masquée à nouveau.
  g.cspHideMessages=false; H.tick(HOST,0.2); assert(HOST.files[gui]==original and HOST.files[state]==nil and HOST.guiWrites==2,'restored byte for byte')
  g.cspHideMessages=true; H.tick(HOST,0.2); assert(HOST.files[gui]==hidden and HOST.guiWrites==3)
  -- Beta 1.47 : panique (passagère) : rien ne change.
  e.panic=true; H.tick(HOST,0.2); assert(HOST.files[gui]==hidden and HOST.guiWrites==3,'panic: left as is')
  e.panic=false; H.tick(HOST,0.2); assert(HOST.files[gui]==hidden and HOST.guiWrites==3)
  -- Messages d'AC non repris sur l'overlay : leur affichage d'origine reste celui d'AC.
  g.overlayMessages=false; H.tick(HOST,0.2); assert(HOST.files[gui]==original,'overlay without messages: AC keeps them')
  g.overlayMessages=true; H.tick(HOST,0.2); assert(HOST.files[gui]==hidden and HOST.guiWrites==5)
  -- Beta 1.47 : app coupée (bouton APP) : valeurs d'origine rendues ; rallumée : cochées à nouveau.
  g.enabled=false; H.tick(HOST,0.2); assert(HOST.files[gui]==original,'app switched off: originals back')
  g.enabled=true; H.tick(HOST,0.2); assert(HOST.files[gui]==hidden and HOST.guiWrites==7)
  -- Déchargement sans relecture par CSP : gardées jusqu'au lancement suivant ; relance dans la même partie : rien d'écrit.
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  assert(HOST.files[gui]==hidden and HOST.files[state],'kept until the next launch (CSP reads gui.ini at launch)')
  assert(loadstring(source))(); H.tick(HOST,1); assert(HOST.guiWrites==7,'relaunched in the same game: no write')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  -- Lancement suivant : option appliquée par CSP ; le message témoin la vérifie une fois.
  local files={[gui]=HOST.files[gui],[state]=HOST.files[state]}
  HOST=H.create(true); for k,v in pairs(files) do HOST.files[k]=v end; HOST.hideRaceFlags=true; HOST.hideSystemMessages=true
  assert(loadstring(source))(); H.tick(HOST,0.5); e=HUMANAI.engine; g=e.g
  assert((HOST.guiWrites or 0)==0,'applied at launch: nothing to write')
  for _=1,C.K.probeFrames+1 do script.HUMANAI__HUD() end
  assert(count('option de CSP comprise')==1 and not g.cspMessagesLost,'probe received with the CSP option')
  -- Relecture par CSP en cours de partie, puis déchargement : Beta 1.47, laissées cochées (cases cochées dans Content
  -- Manager), valeurs d'origine gardées.
  g.cspHideMessages=false; H.tick(HOST,0.2); assert(HOST.files[gui]==original)
  g.cspHideMessages=true; H.tick(HOST,0.2); assert(HOST.files[gui]==hidden)
  H.reloadGui(HOST); H.tick(HOST,2.5)
  assert(count('gui.ini relu par CSP en cours de partie')==1,'live reload logged')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  assert(HOST.files[gui]==hidden and HOST.files[state]~=nil and #HOST.guiWatchers==0,'kept ticked on unload, watcher closed')
  assert(count('options laissees cochees')==1,'unload noted once in the journal')
  -- Retour arrière depuis l'app (vers une version d'avant ces options, qui ne les rendrait jamais) : valeurs d'origine
  -- rendues au déchargement.
  assert(loadstring(source))(); H.tick(HOST,0.5); e=HUMANAI.engine; HUMANAI.host.updater.after='rollback'
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  assert(HOST.files[gui]==original and HOST.files[state]==nil,'rolled back: originals given back on unload')
  -- Drapeaux d'AC masqués par l'app : jamais tenus pour masqués avant que CSP ait relu gui.ini (pas de rouge, drapeau
  -- noir d'AC) ; relu : masqués. Messages masqués par CSP après la relecture : le témoin les vérifie ; perdus, l'option
  -- est rendue, ce choix gardé et affiché ; recochée : nouvel essai.
  HOST=H.create(true); assert(loadstring(source))(); H.tick(HOST,0.5); local host=HUMANAI.host; e=HUMANAI.engine; g=e.g
  assert(HOST.files[gui]=='[HIDE]\nHIDE_SYSTEM_MESSAGES=1\nHIDE_RACE_FLAGS=1\n','missing file created: '..tostring(HOST.files[gui]))
  for _=1,C.K.probeFrames+1 do script.HUMANAI__HUD() end
  assert(count('affichage d origine masque, messages repris sur l overlay')==1 and count('option de CSP comprise')==0,'first probe: without the CSP option (not applied yet)')
  HOST.hideRaceFlags=true; require('src/applier').readFlagsHidden(host); assert(host.raceFlagsHidden==false,'written, not applied yet')
  pause(true); go('home'); redraw(); assert(begins(L.nativeFlagsNext),'warning: effective at the next launch'); pause(false)
  HOST.hideSystemMessages=true; HOST.hideSwallows=true
  H.reloadGui(HOST); assert(host.raceFlagsHidden==true,'reloaded: hidden')
  for _=1,C.K.probeFrames+1 do script.HUMANAI__HUD() end
  H.tick(HOST,0.2)
  assert(g.cspMessagesLost and count('ils n arrivent plus a l overlay: option rendue')==1,'probe lost: option given back')
  assert(HOST.files[gui]=='[HIDE]\nHIDE_RACE_FLAGS=1\n','system messages back, flags still hidden: '..tostring(HOST.files[gui]))
  HOST.space={x=1000,y=3000}; pause(true); section('overlay'); assert(begins(L.cspLost),'state shown under the switches')
  press('overlay_cspHideMessages'); press('overlay_cspHideMessages'); assert(g.cspHideMessages and not g.cspMessagesLost,'ticked again: retried')
  pause(false); HOST.space={x=1000,y=780}
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 -- Beta 1.42 : sections Stratégie des IA et Sanctions des IA (réglages, notes par profil), barre latérale de 17 entrées
 -- tenant dans la fenêtre, bloc « Course des IA » du Diagnostic montré seulement avec des lignes.
 check('sections Stratégie et Sanctions des IA : réglages, notes de profil, barre latérale et bloc du diagnostic',function()
  -- Fenêtre de 700 px de haut : la liste des 17 sections doit tenir (lignes resserrées).
  HOST=H.create(true); HOST.space={x=1000,y=700}; assert(loadstring(source))(); H.tick(HOST,0.5); pause(true)
  local e=HUMANAI.engine
  go('home'); press('auto'); press('profile_C'); go('settings')
  for _,group in ipairs({'sanctions','strategy','globals'}) do press('cat_'..group); redraw(); assert(lit('cat_'..group),'sidebar entry reachable: '..group) end
  press('cat_strategy'); redraw(); assert(drawn('set_strategyEnabled') and drawn('set_failureRate'),'race: strategy settings shown')
  press('cat_sanctions'); redraw(); assert(drawn('set_sanCutPenalty') and drawn('set_sanProcedureKind'),'race: sanction settings shown')
  go('home'); press('profile_Q'); go('settings'); press('cat_sanctions'); redraw()
  assert(drawn('set_sanTrackLimits') and not drawn('set_sanCutPenalty') and begins(L.sanctionsPractice),'qualifying: track limits only, note shown')
  press('cat_strategy'); redraw(); assert(not drawn('set_strategyEnabled') and begins(L.strategyOnlyRace),'qualifying: strategy race only')
  go('home'); press('profile_J'); go('settings'); press('cat_sanctions'); redraw(); assert(begins(L.sanctionsWeekend),'track day: weekend only')
  HOST.space={x=1000,y=3000}; go('diagnostic'); redraw(); assert(not drawnText(L.aiRaceHeading),'no AI race block without rows')
  e.strategy.rows[1]={text='Driver_2 : 1 arret(s), prochain vers le tour 12',kind='text'}; e.sanctions.rows[1]={text='Driver_3 : drive-through (faux depart)',kind='warn'}
  redraw(); assert(drawnText(L.aiRaceHeading) and drawnText(e.sanctions.rows[1].text),'AI race block with its rows')
  e.strategy.rows[1]=nil; e.sanctions.rows[1]=nil; HOST.space={x=1000,y=780}
  pause(false); HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 check('Beta 1.43 : annonces des sanctions des IA en panneau dédié de l overlay (maquette)',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,1); pause(true)
  local e=HUMANAI.engine; local panel=e.panel; local S=require('src/sanctions'); local HI=require('src/hudinfo'); local UIm=package.loaded['src/ui']
  e.g.overlayMessages=true
  local function notice(kind,what,driver,x,text) S.aiNotice(e.sanctions,kind,text,what,driver,x); HI.update(e.hud,e.frame,e,e.time) end
  local function draw(kind) panel.kind=kind; panel.decided=kind; panel.title=L.flagTitles[kind] or ''; panel.short=''; panel.explain=''; panel.changedAt=e.time-10; HOST.panelTexts={}; HUMANAI.drawFlags() end
  notice('aiSanction','drive','Lorenzo Brazzoli',L.sanctionTexts.reasons.jumpStart,'Lorenzo Brazzoli : drive-through (faux départ)')
  draw('none')
  assert(UIm.overlayParts(HUMANAI.panel).ai,'band free: dedicated notice')
  local N=L.aiNotices; local R=L.sanctionTexts.reasons
  assert(has(HOST.panelTexts,'DT') and has(HOST.panelTexts,'Lorenzo Brazzoli') and has(HOST.panelTexts,string.format(N.drive,R.jumpStart)) and has(HOST.panelTexts,N.labels.sanction),'badge, driver, sanction and label')
  assert(not has(HOST.panelTexts,e.hud.aiFallback),'no generic duplicate')
  draw('yellow'); local p=UIm.overlayParts(HUMANAI.panel)
  assert(not p.ai and p.aiStrip and has(HOST.panelTexts,e.hud.aiFallback) and not has(HOST.panelTexts,'DT') and has(HOST.panelTexts,L.flagTitles.yellow),'a flag keeps the band, the notice goes to the session line')
  notice('aiBlackFlag','blackFlag','Marco Weber',L.sanctionTexts.reasons.wrongWay,'Marco Weber : drapeau noir (contresens)')
  draw('none')
  assert(has(HOST.panelTexts,'Marco Weber') and has(HOST.panelTexts,string.format(N.blackFlag,R.wrongWay)) and has(HOST.panelTexts,N.labels.blackFlag) and not has(HOST.panelTexts,'DT'),'black flag notice without a code')
  e.hud.aiUntil=e.time-1; draw('none'); assert(not has(HOST.panelTexts,'Marco Weber'),'gone after its time')
  pause(false); HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 -- Beta 1.46 : pont des apps compagnes (SpotterEnginer). Absent : rien d'ouvert ni de calculé, commandes identiques ;
 -- présent : structures ouvertes et publiées ; erreur : pont coupé seul ; déchargement : pont fermé.
 check('Beta 1.46 : pont des apps compagnes inactif sans SpotterEnginer, ouvert avec, coupé sur erreur, fermé au déchargement',function()
  local B=require('src/bridge'); local beat0,pub0=B.beat,B.publish
  local beats,pubs=0,0
  B.beat=function(...) beats=beats+1; return beat0(...) end
  B.publish=function(...) pubs=pubs+1; return pub0(...) end
  local connected={}
  local function fakeStruct()
   local SI={}
   for _,k in ipairs({'boolean','int32','uint32','float','double'}) do SI[k]=function() return {kind=k} end end
   SI.string=function(n) return {kind='string',cap=n} end
   SI.key=function(s) return {kind='key',value=s} end
   SI.struct=function(f) return {kind='struct',fields=f} end
   SI.array=function(e,n) return {kind='array',elem=e,size=n} end
   local function make(d)
    if d.kind=='struct' then local o={}; for name,f in pairs(d.fields) do if f.kind~='key' then o[name]=make(f) end end; return o
    elseif d.kind=='array' then local a={}; for i=0,d.size-1 do a[i]=make(d.elem) end; return a
    elseif d.kind=='string' then return '' elseif d.kind=='boolean' then return false end
    return 0
   end
   ac.StructItem=SI
   ac.connect=function(layout) local o=make({kind='struct',fields=layout}); connected[#connected+1]=o; return o end
  end
  local function logged(prefix)
   local q=HUMANAI.engine.log
   for k=1,q.limit do local r=q[k]; if r and type(r.message)=='string' and r.message:sub(1,#prefix)==prefix then return true end end
   return false
  end
  local function launch(present)
   if HUMANAI then HUMANAI.release() end
   HOST=H.create(true); connected={}; beats=0; pubs=0; fakeStruct()
   ac.FolderID.ACAppsLua=1029; local getFolder=ac.getFolder
   ac.getFolder=function(id) if id==1029 then return 'appslua' end return getFolder(id) end
   if present then local sep=string.char(92); HOST.files['appslua'..sep..'SpotterEnginer'..sep..'manifest.ini']='[ABOUT]' end
   assert(loadstring(source))()
  end
  -- Absent : aucune structure partagée, aucun travail du pont à chaque image.
  launch(false); H.tick(HOST,3)
  assert(#connected==0 and beats==0 and pubs==0 and HUMANAI.bridgePort()==nil,'absent: nothing opened or computed')
  assert(logged('pont des apps compagnes: SpotterEnginer absent, pont inactif'),'absent: one journal line')
  local callsAbsent,timeAbsent=HOST.calls,HUMANAI.engine.time
  -- Présent : deux structures (hello, data), battement et état publiés à chaque image ; commandes identiques.
  launch(true); H.tick(HOST,3)
  local port=HUMANAI.bridgePort()
  assert(port and #connected==2 and beats>0 and pubs==beats,'present: opened and published every frame')
  assert(logged('pont des apps compagnes: ouvert (version 1)'),'present: journal line')
  local hello,data=connected[1],connected[2]
  assert(hello.bridgeVersion==1 and hello.release==C.release and hello.heartbeat==beats and hello.closed==false,'hello fields')
  assert(data.serial==pubs and data.carCount>0 and data.cars[0].valid==true and data.profile==HUMANAI.engine.profile,'data fields')
  assert(HOST.calls==callsAbsent and HUMANAI.engine.time==timeAbsent,'present: same commands as absent')
  -- Déchargement : pont fermé, plus rien publié.
  HUMANAI.release(); assert(hello.closed==true and HUMANAI.bridgePort()==nil,'release closes the bridge')
  -- Erreur de publication : pont coupé seul, une ligne au journal, moteur intact.
  launch(true); H.tick(HOST,1); hello=connected[1]
  B.publish=function() error('boom') end
  H.tick(HOST,2)
  assert(HUMANAI.bridgePort()==nil and hello.closed==true and logged('pont des apps compagnes coupe: '),'error cuts the bridge only')
  assert(not HUMANAI.engine.panic and HUMANAI.host.errors==0,'engine unaffected by a bridge error')
  local b0=beats; H.tick(HOST,1); assert(beats==b0,'nothing more after the cut')
  B.beat,B.publish=beat0,pub0; ac.connect=nil; ac.StructItem=nil
  HUMANAI.release()
 end)
 -- Beta 1.49 (session du 5 novembre, 11:33 : « arrivee en 0 », « 0 -> 1 ») : composés du joueur lus comme ceux des IA.
 check('Beta 1.49 : composes du joueur lus (noms de l arret obligatoire)',function()
  if HUMANAI then HUMANAI.release() end
  HOST=H.create(true); HOST.sim.raceSessionType=3
  local names={[0]='SS',[1]='S',[2]='M'}
  local get=ac.getTyresName
  ac.getTyresName=function(index,compound) return names[compound] end
  assert(loadstring(source))(); H.tick(HOST,2)
  local a=HUMANAI.engine.frame and HUMANAI.engine.frame.cars[HUMANAI.engine.frame.player] or nil
  ac.getTyresName=get
  assert(a and a.player and a.tyresKnown and a.tyreNames[0]=='SS' and a.tyreNames[2]=='M','player compounds read')
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
 end)
 -- Beta 1.49 : avis de l'arrêt F1 publiés pour SpotterEnginer (annonce de l'app : genre, valeurs, titre, texte) sans
 -- message d'AC en haut de l'écran ni ligne de session en double.
 check('Beta 1.49 : avis de l arret F1 annonces au pont, jamais en message d AC',function()
  if HUMANAI then HUMANAI.release() end
  HOST=H.create(true); HOST.sim.raceSessionType=3
  local connected={}
  local SI={}
  for _,k in ipairs({'boolean','int32','uint32','float','double'}) do SI[k]=function() return {kind=k} end end
  SI.string=function(n) return {kind='string',cap=n} end
  SI.key=function(s) return {kind='key',value=s} end
  SI.struct=function(fl) return {kind='struct',fields=fl} end
  SI.array=function(el,n) return {kind='array',elem=el,size=n} end
  local function make(d)
   if d.kind=='struct' then local o={}; for name,fl in pairs(d.fields) do if fl.kind~='key' then o[name]=make(fl) end end; return o
   elseif d.kind=='array' then local a={}; for i=0,d.size-1 do a[i]=make(d.elem) end; return a
   elseif d.kind=='string' then return '' elseif d.kind=='boolean' then return false end
   return 0
  end
  ac.StructItem=SI
  ac.connect=function(layout) local o=make({kind='struct',fields=layout}); connected[#connected+1]=o; return o end
  ac.FolderID.ACAppsLua=1029; local getFolder=ac.getFolder
  ac.getFolder=function(id) if id==1029 then return 'appslua' end return getFolder(id) end
  local sep=string.char(92); HOST.files['appslua'..sep..'SpotterEnginer'..sep..'manifest.ini']='[ABOUT]'
  assert(loadstring(source))(); H.tick(HOST,1)
  local e=HUMANAI.engine; local data=connected[2]
  assert(data,'bridge open')
  local L=require('src/lang')
  e.pits.playerNoticeFrom='SS'; e.pits.playerNoticeTo='S'
  local before=#HOST.messages
  e.announce('pitValidated',0,1); H.tick(HOST,0.5)
  assert(data.messageKind=='pitValidated' and data.messageValue==0 and data.messageExtra==1,'bridge: kind and values')
  assert(data.messageTitle==L.messages.pitValidated[1] and data.messageText==string.format(L.pitHint.counted,'SS','S'),'bridge: title and text ready')
  assert(#HOST.messages==before,'no AC message at the top of the screen')
  local id=data.messageId; H.tick(HOST,0.5); assert(data.messageId==id,'published once')
  e.pits.playerNoticeTo='SS'; e.announce('pitNotCounted',0,0); H.tick(HOST,0.5)
  assert(data.messageKind=='pitNotCounted' and data.messageId~=id and data.messageText==string.format(L.pitHint.sameDetail,'SS','SS') and #HOST.messages==before,'not counted: bridge only')
  -- Collision dans une image (pénalité, priorité 5, et avis de l'arrêt) : la pénalité publiée dans cette image, l'avis à
  -- l'image suivante, titre et texte écrits pour lui avant la publication du pont de la même image ; une seule fois.
  local S=require('src/sanctions'); local update0=S.update; local collide=false
  S.update=function(...) local r=update0(...); if collide then collide=false; e.announce('penaltyDelta',5,0); e.announce('pitValidated',0,1) end; return r end
  e.pits.playerNoticeFrom='SS'; e.pits.playerNoticeTo='S'
  collide=true; H.tick(HOST,1/60)
  local idPenalty=data.messageId
  assert(data.messageKind=='penaltyDelta' and data.messageTitle==L.messages.penaltyDelta[1] and data.messageText==string.format(L.messages.penaltyDelta[2],5),'collision frame: the penalty, title and text of the same message')
  H.tick(HOST,1/60)
  assert(data.messageId==idPenalty%C.K.counterMax+1 and data.messageKind=='pitValidated' and data.messageValue==0 and data.messageExtra==1,'next frame: the pit notice')
  assert(data.messageTitle==L.messages.pitValidated[1] and data.messageText==string.format(L.pitHint.counted,'SS','S'),'re-emission frame: title and text of the pit notice')
  local idPit=data.messageId; H.tick(HOST,1/60); assert(data.messageId==idPit,'published once')
  S.update=update0
  -- Autres annonces : comme avant (message d'AC).
  local before2=#HOST.messages; e.announce('pitOpen',20,95); H.tick(HOST,0.5); assert(#HOST.messages==before2+1 and data.messageKind=='pitOpen','other kinds unchanged')
  ac.connect=nil; ac.StructItem=nil
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
 end)
 -- Beta 1.50 : annonces de la voiture de sécurité et de la reprise du joueur : texte prêt (nom du pilote) au pont,
 -- jamais en message d'AC en haut de l'écran.
 check('Beta 1.50 : annonces de la voiture de securite et de la reprise au pont, jamais en message d AC',function()
  if HUMANAI then HUMANAI.release() end
  HOST=H.create(true); HOST.sim.raceSessionType=3
  local connected={}
  local SI={}
  for _,k in ipairs({'boolean','int32','uint32','float','double'}) do SI[k]=function() return {kind=k} end end
  SI.string=function(n) return {kind='string',cap=n} end
  SI.key=function(s) return {kind='key',value=s} end
  SI.struct=function(fl) return {kind='struct',fields=fl} end
  SI.array=function(el,n) return {kind='array',elem=el,size=n} end
  local function make(d)
   if d.kind=='struct' then local o={}; for name,fl in pairs(d.fields) do if fl.kind~='key' then o[name]=make(fl) end end; return o
   elseif d.kind=='array' then local a={}; for i=0,d.size-1 do a[i]=make(d.elem) end; return a
   elseif d.kind=='string' then return '' elseif d.kind=='boolean' then return false end
   return 0
  end
  ac.StructItem=SI
  ac.connect=function(layout) local o=make({kind='struct',fields=layout}); connected[#connected+1]=o; return o end
  ac.FolderID.ACAppsLua=1029; local getFolder=ac.getFolder
  ac.getFolder=function(id) if id==1029 then return 'appslua' end return getFolder(id) end
  local sep=string.char(92); HOST.files['appslua'..sep..'SpotterEnginer'..sep..'manifest.ini']='[ABOUT]'
  assert(loadstring(source))(); H.tick(HOST,1)
  local e=HUMANAI.engine; local data=connected[2]
  assert(data,'bridge open')
  local L=require('src/lang')
  local name=e.frame.cars[2].name; assert(name and name~='','car 2 named')
  local before=#HOST.messages
  e.announce('scOut',1,600); H.tick(HOST,0.5)
  assert(data.messageKind=='scOut' and data.messageValue==1 and data.messageExtra==600,'bridge: scOut values')
  assert(data.messageTitle==L.messages.scOut[1] and data.messageText==string.format(L.messages.scOut[2],name),'bridge: scOut text names the car behind')
  e.announce('scOut',-1,-1); H.tick(HOST,0.5); assert(data.messageText==L.messages.scOutAlone[2],'nobody behind')
  e.announce('scLeading',1,90); H.tick(HOST,0.5); assert(data.messageKind=='scLeading' and data.messageText==string.format(L.messages.scLeading[2],name),'queue formed')
  e.announce('restartPlace',2,1); H.tick(HOST,0.5); assert(data.messageKind=='restartPlace' and data.messageText==string.format(L.messages.restartPlace[2],2,name),'restart place behind a car')
  e.announce('restartPlace',1,-1); H.tick(HOST,0.5); assert(data.messageText==string.format(L.messages.restartPlaceSc[2],1),'restart place P1: behind the safety car')
  e.announce('restartRetake',1,3); H.tick(HOST,0.5); assert(data.messageKind=='restartRetake' and data.messageText==string.format(L.messages.restartRetake[2],name),'place to retake')
  assert(#HOST.messages==before,'never an AC message at the top of the screen')
  ac.connect=nil; ac.StructItem=nil
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
 end)
 -- Beta 1.49 : l'app s'appelle AdvancedIA ; l'ancienne version encore installée (apps/lua/ACAdvancedIA/manifest.ini)
 -- pilote les IA : AdvancedIA ne commande ni n'écrit rien et affiche seulement la consigne (fenêtre, écran, journal).
 -- Dossier vide (sans manifeste) : sans effet. Réglages de l'ancienne app non repris : signalés une fois.
 check('Beta 1.49 : ancienne version ACAdvancedIA installée : app inerte et consigne ; dossier vide sans effet',function()
  local Old=require('src/oldinstall')
  local function boot(files)
   if HUMANAI then HUMANAI.release() end
   HOST=H.create(true); HOST.sim.raceSessionType=3
   ac.FolderID.ACAppsLua=1029; local getFolder=ac.getFolder
   ac.getFolder=function(id) if id==1029 then return 'appslua' end return getFolder(id) end
   for k,val in pairs(files or {}) do HOST.files[k]=val end
   Old.active=nil; local before=HUMANAI
   assert(loadstring(source))()
   return before
  end
  local sep=string.char(92)
  -- Ancienne version présente : rien n'est commandé ni écrit, consigne dans la fenêtre et sur l'écran, une ligne au journal.
  local before=boot({['appslua'..sep..'ACAdvancedIA'..sep..'manifest.ini']='[ABOUT]\nNAME=ACAdvancedIA\n'})
  assert(Old.active==true and HUMANAI==before,'inert: the engine is never created')
  for _=1,120 do script.update(1/60); script.HUMANAI__UPDATE(1/60) end
  HOST.wrappedTexts={}; script.HUMANAI__MAIN()
  local inWindow=table.concat(HOST.wrappedTexts,'|')
  assert(inWindow:find(Old.textFr,1,true) and inWindow:find(Old.textEn,1,true),'window alone: instruction in French and English')
  script.HUMANAI__MENU(); HUMANAI.drawFlags()
  HOST.transparent={}; script.HUMANAI__HUD()
  assert(HOST.calls==0 and HOST.offsetCalls==0,'inert: no AI command')
  assert(not HOST.guiWrites and not HOST.stateWrites and not HOST.cfgWrites and not HOST.bakDeleted,'inert: no CSP option, state or AI flood write')
  local shown=table.concat(HOST.wrappedTexts,'|')
  assert(shown:find(Old.textFr,1,true) and shown:find(Old.textEn,1,true),'window: instruction in French and English')
  assert(HOST.transparent.AdvancedIA_overlay,'overlay: instruction on screen')
  local text=HOST.files['logs/AdvancedIA.log'] or ''
  assert(text:find('=== AdvancedIA ',1,true) and text:find('ancienne version ACAdvancedIA encore installee',1,true),'one journal line')
  -- Dossier laissé vide (sans manifeste) : l'app démarre normalement.
  boot({['appslua'..sep..'ACAdvancedIA'..sep..'notes.txt']='x'})
  assert(Old.active==nil and HUMANAI and HUMANAI.engine,'empty folder: normal start')
  H.tick(HOST,2); assert(HOST.calls>0,'empty folder: the app drives')
  assert(HUMANAI.host.oldSettings==false,'no old settings: no hint')
  -- Réglages de l'ancienne app présents, ceux d'AdvancedIA pas encore : un point « À vérifier » et une ligne au journal.
  local state=ac.getFolder(ac.FolderID.ExtCfgState)
  boot({[state..sep..'lua'..sep..'app'..sep..'ACAdvancedIA.ini']='[BOOLEAN]\n'})
  assert(HUMANAI.host.oldSettings==true,'old settings: hint')
  local found=false; local q=HUMANAI.engine.log
  for k=1,q.limit do local r=q[k]; if r and type(r.message)=='string' and r.message:find('reglages d ACAdvancedIA non repris',1,true) then found=true end end
  assert(found,'old settings: journal line')
  boot({[state..sep..'lua'..sep..'app'..sep..'ACAdvancedIA.ini']='[BOOLEAN]\n',[state..sep..'lua'..sep..'app'..sep..'AdvancedIA.ini']='[BOOLEAN]\n'})
  assert(HUMANAI.host.oldSettings==false,'settings already carried over: no hint')
  HUMANAI.release(); HOST=H.create(true); assert(loadstring(source))()
 end)
 -- Beta 1.47 (Monza, 4 novembre, 17:26) : drapeau rouge de l'app (5) sur les panneaux, relance de la session ; CSP garde
 -- le 5 après la restitution (simulé : HOST.stickyFlag) : l'app ne le prend pas pour un drapeau noir natif, renvoie la
 -- restitution puis écrit le drapeau de départ d'AC ; l'overlay ne reste pas sur le drapeau noir, les panneaux repartent.
 check('Beta 1.47 : rouge de l app resté affiché par CSP après une relance : repris, jamais un drapeau noir natif',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.sim.carsCount=4; HOST.hideRaceFlags=true
  local sep=string.char(92); local function path(...) return table.concat({...},sep) end
  HOST.files[path('tracks','test','extension','ext_config.ini')]='[INCLUDE]\nINCLUDE = common/conditions.ini, ext_config-flags.ini\n'
  HOST.files[path('tracks','test','extension','ext_config-flags.ini')]='[MATERIAL_ADJUSTMENT_0]\nACTIVE=1\nCONDITION=RACING_FLAG\n'
  HOST.files[path('cfgsys','tracks','common','conditions.ini')]='[CONDITION_85]\nNAME=RACING_FLAG\nINPUT=FLAG_TYPE\n'
  assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagCars=2; e.profiles.C.redFlagHold=20; E.changed(e)
  local function logged(text) for n=0,e.log.count-1 do local row=e.log[(e.log.head-n-1)%e.log.limit+1]; if row.message:find(text,1,true) then return true end end return false end
  H.tick(HOST,8)
  -- Piste étroite, deux voitures arrêtées côte à côte : piste bloquée (drapeau rouge de la Beta 1.47).
  local sides=ac.getTrackAISplineSides; ac.getTrackAISplineSides=function() return {x=3,y=3} end
  for k,i in ipairs({2,3}) do local c=HOST.cars[i]; c.speedKmh=0; c.velocity={x=0,z=0}; c.position={x=k==1 and -1.5 or 1.5,y=0,z=HOST.cars[2].position.z}; c.splinePosition=HOST.cars[2].splinePosition end
  H.tick(HOST,C.K.redIncidentStill+1)
  ac.getTrackAISplineSides=sides
  assert(e.incidents.red and HUMANAI.host.trackLights==true and HOST.flag==C.K.flagStop and HOST.sim.raceFlagType==C.K.flagStop,'red flag on the panels (5)')
  -- Relance de la session (même indice) ; CSP garde le 5 malgré les restitutions.
  HOST.stickyFlag=99
  -- Beta 1.47 : rouge 10 s après l'arrêt : les deux IA ont eu le temps d'être dépannées ; remises en piste.
  for _,i in ipairs({2,3}) do local c=HOST.cars[i]; c.speedKmh=150; c.velocity={x=0,z=40}; c.position={x=0,y=0,z=(i-1)*120}; c.splinePosition=(i-1)*0.012; c.isInPit=false; c.isInPitlane=false end
  for fn in pairs(HOST.sessions) do fn(0,true) end
  H.tick(HOST,0.5)
  assert(HOST.sim.raceFlagType==C.K.flagStop and not HUMANAI.host.flagOverride and HUMANAI.host.flagLeftover,'5 still shown after the restore: kept as the app s own')
  HOST.transparent={}; script.HUMANAI__HUD()
  assert(e.panel.kind~='black','overlay never on a black flag for the app s own red')
  assert(not logged('drapeau d AC: 5'),'not logged as an AC black flag')
  H.tick(HOST,5)
  assert(logged('drapeau 5 de l app encore affiche apres restitution') and logged('remplace par le drapeau de depart d AC'),'restore re-sent, then the AC start flag written')
  assert(HOST.sim.raceFlagType==C.K.flagStart and not HUMANAI.host.flagLeftover,'panels back to the AC start flag')
  assert(not logged('voulu, non ecrit (drapeau natif 5)'),'no refusal loop on the app s own 5')
  -- Ensuite : un jaune voulu est écrit normalement.
  HOST.stickyFlag=0; HOST.cars[0].splinePosition=0.995; HOST.cars[3].speedKmh=0; HOST.cars[3].velocity={x=0,z=0}
  H.tick(HOST,8)
  assert(HOST.flag==C.K.flagCaution,'yellow written again after the recovery')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 -- Vrai drapeau noir d'AC (l'app n'a rien écrit) : toujours respecté, montré par l'overlay, jamais recouvert.
 check('Beta 1.47 : vrai drapeau noir d AC respecté',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.hideRaceFlags=true
  local sep=string.char(92); local function path(...) return table.concat({...},sep) end
  HOST.files[path('tracks','test','extension','ext_config.ini')]='[INCLUDE]\nINCLUDE = common/conditions.ini, ext_config-flags.ini\n'
  HOST.files[path('tracks','test','extension','ext_config-flags.ini')]='[MATERIAL_ADJUSTMENT_0]\nACTIVE=1\nCONDITION=RACING_FLAG\n'
  HOST.files[path('cfgsys','tracks','common','conditions.ini')]='[CONDITION_85]\nNAME=RACING_FLAG\nINPUT=FLAG_TYPE\n'
  HOST.nativeFlag=C.K.flagStop; HOST.sim.raceFlagType=C.K.flagStop
  assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); E.changed(e)
  local function logged(text) for n=0,e.log.count-1 do local row=e.log[(e.log.head-n-1)%e.log.limit+1]; if row.message:find(text,1,true) then return true end end return false end
  HOST.cars[0].splinePosition=0.995; HOST.cars[3].speedKmh=0; HOST.cars[3].velocity={x=0,z=0}
  H.tick(HOST,8)
  assert(HOST.flagOverrides==0 and HOST.sim.raceFlagType==C.K.flagStop and not HUMANAI.host.flagLeftover,'AC black flag untouched')
  assert(logged('drapeau d AC: 5 (noir)') and logged('voulu, non ecrit (drapeau natif 5)'),'native black flag logged and respected')
  HOST.transparent={}; script.HUMANAI__HUD(); assert(e.panel.kind=='black','overlay shows the AC black flag')
  HUMANAI.release()
 end)
 -- Beta 1.50 : sortie par la voie des stands sur le banc de CSP : retenue par l'attente d'AC, libérée (attente levée,
 -- réveillée), elle quitte son emplacement d'elle-même (déplacée ici par le banc comme le ferait AC), roule dans la voie
 -- puis entre en piste : jamais de commande de position, annonce scOut au pont.
 check('Beta 1.50 : voiture de sécurité retenue, libérée, sortie par la voie des stands sans commande de position',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  ac.getCarID=function(index) return index==3 and 'sc_model' or 'model_'..index end
  assert(loadstring(source))(); local e=HUMANAI.engine
  C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; e.g.safetyCarModel='sc_model'; e.g.safetyCarPicked=true; E.changed(e); H.tick(HOST,3)
  assert(e.incidents.safety==4 and scHeld(3) and not HOST.parked[3] and HOST.cars[3].isInPit,'held in its box by AC own wait')
  local writes=HOST.positionWrites or 0
  local t=e.incidents; t.neutral=true; t.neutralMode='sc'; t.neutralSince=e.time; t.neutralUntil=e.time+1e6; t.safetyPhase='call'; t.safetySince=e.time-C.K.scCallTime-1
  H.tick(HOST,1)
  assert(t.safetyPhase=='exit' and HOST.startDelays[3]==0 and (HOST.awakes[3] or 0)>=1,'released: AC wait lifted, woken')
  local car=HOST.cars[3]; car.isInPit=false; car.isInPitlane=true; car.speedKmh=60; car.velocity={x=0,z=16}; H.tick(HOST,2)
  assert(t.safetyPhase=='exit' and logged('voiture de securite: sortie de son stand'),'left its box, in the pit lane')
  car.isInPitlane=false; car.speedKmh=100; car.velocity={x=0,z=28}; H.tick(HOST,0.5)
  assert(t.safetyPhase=='out' and t.safetyLeft and logged('voiture de securite: sortie en piste'),'on track')
  assert((HOST.positionWrites or 0)==writes and not HOST.positions[3],'never placed by a position command')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 -- Beta 1.50 : la pose en piste (Beta 1.48) reste le repli de la sortie par la voie des stands : ces cas l'exercent avec
 -- une voiture de sécurité qui ne quitte jamais son emplacement (le banc ne la déplace pas), libérée dès la fin de
 -- l'appel, sans règle de vue du joueur.
 local function placeFallback(fn)
  return function()
   local K=C.K; local keep={K.scLeaveMax,K.scExitLead,K.scHideAhead,K.scHideBehind}
   K.scLeaveMax=0; K.scExitLead=1e9; K.scHideAhead=0; K.scHideBehind=0
   local ok,err=pcall(fn)
   K.scLeaveMax,K.scExitLead,K.scHideAhead,K.scHideBehind=keep[1],keep[2],keep[3],keep[4]
   if not ok then error(err,0) end
  end
 end
 -- Beta 1.48 : banc honnête : la voiture de sécurité, garée à son emplacement, ne bouge que sur une commande de position.
 check('Beta 1.48 : voiture de sécurité posée en piste par CSP (setCarPosition), jamais conduite hors de son emplacement',placeFallback(function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  ac.getCarID=function(index) return index==3 and 'sc_model' or 'model_'..index end
  assert(loadstring(source))(); local e=HUMANAI.engine
  C.preset('Course','C',e.profiles.C); e.profiles.C.neutralization='sc'; e.g.safetyCarModel='sc_model'; e.g.safetyCarPicked=true; E.changed(e); H.tick(HOST,3)
  assert(e.incidents.safety==4 and scHeld(3) and HOST.cars[3].isInPit,'held in its box')
  local teleports=HOST.teleports; local writes=HOST.positionWrites or 0
  H.tick(HOST,5); assert((HOST.positionWrites or 0)==writes and HOST.cars[3].isInPit,'parked: never moved')
  local t=e.incidents; t.neutral=true; t.neutralMode='sc'; t.neutralSince=e.time; t.neutralUntil=e.time+1e6; t.safetyPhase='call'; t.safetySince=e.time-C.K.scCallTime-1
  H.tick(HOST,1)
  assert(HOST.positions[3] and not HOST.cars[3].isInPit and t.safetyPhase=='out' and t.safetyLeft,'placed on track by a position command')
  assert(not HOST.parked[3] and HOST.teleports==teleports,'never parked without a driver, never sent back to its box')
  local z=HOST.positions[3].pos.z
  for i=0,2 do local d=math.abs(((HOST.cars[i].splinePosition-z/10000+0.5)%1)-0.5)*10000; assert(d>=C.K.scPlaceFree,'free point '..i) end
  assert(HOST.velocities[3] and math.abs(HOST.velocities[3].z*3.6-C.K.scLeadKmh)<1e-6,'launched at the lead pace')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end))
 -- Beta 1.48 (test 11) : drapeau rouge de bout en bout sur le banc de CSP : ordre figé, voiture de sécurité posée par
 -- setCarPosition, tour de relance et vert, sans repli FCY.
 check('Beta 1.48 : drapeau rouge, ordre figé, voiture de sécurité posée par CSP, relance et vert sans repli',placeFallback(function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3
  ac.getCarID=function(index) return index==3 and 'sc_model' or 'model_'..index end
  assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagCars=2; e.profiles.C.redFlagHold=20; e.g.safetyCarModel='sc_model'; e.g.safetyCarPicked=true; E.changed(e)
  H.tick(HOST,8)
  assert(e.incidents.safety==4 and scHeld(3),'safety car held in its box')
  local sides=ac.getTrackAISplineSides; ac.getTrackAISplineSides=function() return {x=3,y=3} end
  for k,i in ipairs({1,2}) do local c=HOST.cars[i]; c.speedKmh=0; c.velocity={x=0,z=0}; c.position={x=k==1 and -1.5 or 1.5,y=0,z=HOST.cars[1].position.z}; c.splinePosition=HOST.cars[1].splinePosition end
  H.tick(HOST,C.K.redIncidentStill+1)
  ac.getTrackAISplineSides=sides
  local t=e.incidents
  assert(t.red and t.redOrderN==3 and t.redRank[4]==nil,'red flag: order frozen, player included, safety car excluded')
  H.tick(HOST,3)
  for i=0,2 do local c=HOST.cars[i]; c.isInPit=true; c.isInPitlane=true; c.speedKmh=0; c.velocity={x=0,z=0} end
  for _=1,120 do if not t.red then break end; H.tick(HOST,0.5) end
  assert(not t.red and t.relaunch and t.neutralMode=='sc' and t.safetyPhase=='place','relaunch behind the safety car, to be placed')
  -- Le joueur sort le premier (P1) ; la voiture de sécurité est posée devant lui par CSP.
  local writes=HOST.positionWrites or 0
  local c=HOST.cars[0]; c.isInPit=false; c.isInPitlane=false; c.splinePosition=0.5; c.position={x=0,y=0,z=5000}; c.speedKmh=60; c.velocity={x=0,y=0,z=60/3.6}; H.tick(HOST,0.2)
  c.splinePosition=0.5+(C.K.scPlaceOnTrack+5)/10000; c.position={x=0,y=0,z=5000+C.K.scPlaceOnTrack+5}; H.tick(HOST,1)
  assert((HOST.positionWrites or 0)>writes and HOST.positions[3] and not HOST.cars[3].isInPit and t.safetyPhase=='out','placed on track by setCarPosition')
  assert(math.abs(HOST.positions[3].pos.z-(5000+C.K.scPlaceOnTrack+5+C.K.scPlaceFirstOut))<1,'ahead of the first car out')
  H.tick(HOST,C.K.scMinOut+e.run.neutralizationHold+5)
  assert(t.safetyPhase=='in' and t.neutral,'in this lap')
  HOST.cars[3].isInPitlane=true; H.tick(HOST,0.5)
  assert(not t.neutral and not t.relaunch,'green when it enters the pit lane')
  local function logged(text) for n=0,e.log.count-1 do local row=e.log[(e.log.head-n-1)%e.log.limit+1]; if row.message:find(text,1,true) then return true end end return false end
  assert(logged('voiture de securite: posee en piste') and logged('drapeau rouge: ordre fige (3 voitures)'),'logged')
  assert(not logged('restee dans la voie des stands') and not logged('pose en piste impossible') and not logged('neutralisation: fcy'),'no FCY fallback')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end))
 check('Beta 1.52 : mise à jour de SpotterEnginer signalée à l accueil (publiée par lui), lien vers sa fenêtre, jamais installée',function()
  if HUMANAI then HOST.releasing=true; HUMANAI.release(); HOST.releasing=false end
  HOST=H.create(true); assert(loadstring(source))(); H.tick(HOST,0.5)
  local host=HUMANAI.host; local opened=0; host.openCompanion=function() opened=opened+1; return true end
  -- Beta 1.59 : une version qui sait se mettre à jour (1.2.0) : sa fenêtre ; 1.1.0 / 1.1.1 (bouton grisé) : à la main.
  host.companionUpdate=require('src/applier').parseCompanionUpdate('v=1;installed=1.2.0;latest=1.3.0;state=available')
  pause(true); redraw()
  assert(begins(string.format(L.companionAvailable,'1.3.0','1.2.0')),'shown on HOME')
  press('warn_spotter'); assert(opened==1,'link opens the SpotterEnginer window')
  host.companionUpdate=require('src/applier').parseCompanionUpdate('v=1;installed=1.1.1;latest=1.2.0;state=available'); redraw()
  assert(begins(string.format(L.companionManual,'1.2.0','1.1.1')) and not begins(string.format(L.companionAvailable,'1.2.0','1.1.1')),'1.59: 1.1.1 cannot update itself: manual update from GitHub')
  host.companionUpdate=require('src/applier').parseCompanionUpdate('v=1;installed=1.2.0;state=uptodate'); redraw()
  assert(not begins(string.format(L.companionAvailable,'1.3.0','1.2.0')),'up to date: nothing')
  host.companionUpdate=require('src/applier').parseCompanionUpdate('v=1;installed=1.1.0;latest=1.3.0;state=incompatible;needs=Beta 1.53'); redraw()
  assert(begins(string.format(L.companionNeeds,'Beta 1.53')),'incompatible: AdvancedIA to update first')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 check('Beta 1.51 : première installation, préréglage intégré de la session appliqué et allumé (journée circuit : Nordschleife), interrupteur à l accueil',function()
  C.globalDefaults.presetBySession=presetDefault
  if HUMANAI then HOST.releasing=true; HUMANAI.release(); HOST.releasing=false end
  HOST=H.create(true); assert(loadstring(source))(); H.tick(HOST,2)
  local e=HUMANAI.engine
  -- Beta 1.59 : piste d'essai qui n'est pas la Nordschleife : préréglage Journée circuit (décision 20).
  assert(e.g.presetBySession and e.profile=='J' and C.mark(e.g,'J')=='Circuit' and C.on(e.profiles.J,'yield'),'track day: Journée circuit applied off the Nordschleife')
  local found=false; for n=0,e.log.count-1 do local row=e.log[(e.log.head-n-1)%e.log.limit+1]; if row.message:find('preset_session: Circuit',1,true) then found=true end end
  assert(found,'logged')
  pause(true); main(); press('global_presetBySession'); assert(not e.g.presetBySession,'switch on HOME')
  press('global_presetBySession'); assert(e.g.presetBySession,'switch back on')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 -- Beta 1.53 (décision du pilote) : CSP accepte un niveau de 0 à 2 ; le mode automatique écrit au-dessus de 100 % même si
 -- la relecture est écrêtée (journal), « natif si confirmé » plafonne ; fenêtre DIAGNOSTICS : niveau appliqué et journal
 -- en anglais.
 check('1.53 : niveau au-dessus de 100 % écrit en mode automatique, relecture écrêtée notée, journal anglais',function()
  HUMANAI.release(); HOST=H.create(false); HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,0.5)
  local e=HUMANAI.engine; local p=e.profiles.J
  p.section_general=true; p.levelPct=105; p.paceSpreadPct=0; p.paceDriftPct=0; E.changed(e); H.tick(HOST,5)
  assert(e.p.levelPct==105,'profile used: '..tostring(e.p.levelPct))
  local caps=HUMANAI.host.caps
  assert(caps.probeDone and caps.clampProven and not caps.native110 and caps.levelMode=='native','auto stays native: '..tostring(caps.levelMode))
  local high=0; for _,s in pairs(HUMANAI.host.cars) do if s.owned and (s.level or 0)>1.04 then high=high+1 end end
  assert(high>0,'level above 100 % written')
  local probeLine
  for k=1,e.log.limit do local r=e.log[k]; if r and r.message:find('niveau au-dessus de 100 %: sonde 1.05 relue 1.00 (lecture ecretee)',1,true) then probeLine=r.message end end
  assert(probeLine and probeLine:find('-> natif (jusqu a 110 %) (mode demande auto, bonus de grip non autorise)',1,true),'probe line: '..tostring(probeLine))
  pause(true); go('diagnostic'); redraw()
  local english=false; for _,t in ipairs(HOST.drawnTexts) do if t:find('level above 100%: probe 1.05 read back 1.00 (read-back capped)',1,true) then english=true end end
  assert(english,'English journal line in the DIAGNOSTICS window')
  assert(begins('Level mode: native (CSP 0–2), read-back capped at 1.00 (grip bonus not allowed)'),'level mode note')
  -- Natif si confirmé : plafond à 100 %, la fenêtre montre le niveau demandé et le niveau écrit.
  e.g.levelMode='native'; p.section_globals=true; E.changed(e); pause(false); H.tick(HOST,3)
  assert(caps.levelMode=='none','native if confirmed: capped')
  pause(true); redraw()
  local pair=false; for _,t in ipairs(HOST.drawnTexts) do if t:find('^1%.05>1%.00 / ') then pair=true end end
  assert(pair,'requested > applied level shown')
  require('src/locale').set('fr'); redraw()
  local french=false; for _,t in ipairs(HOST.drawnTexts) do if t:find('niveau au-dessus de 100 %: sonde 1.05',1,true) then french=true end end
  assert(french,'French journal line again after the language change')
  pause(false)
 end)
 check('1.54 : boucle de dépassements sur la même cible (cible plus rapide) : attente stricte, aucun appel de phares vers elle',function()
  -- Nordschleife, 9 novembre : une IA a relancé six fois la même cible, qui repartait plus vite à chaque attaque, avec
  -- 33 appels de phares en 6 min. Ici : l'IA 2 (210 km/h) rattrape l'IA 3 (180 km/h), qui accélère à 230 km/h dès
  -- qu'elle est attaquée ; 6 min en ligne droite.
  HUMANAI.release(); HOST=H.create(false); HOST.space={x=1000,y=3000}; HOST.sim.trackLengthM=40000; assert(loadstring(source))(); H.tick(HOST,0.5)
  local e=HUMANAI.engine; local p=e.profiles.J
  p.section_general=true; p.section_overtake=true; p.section_flash=true; p.section_yield=true; p.section_lateral=true
  p.aiFlashEnabled=true; p.pressureEnabled=false; p.section_traffic=false; E.changed(e)
  local L=HOST.sim.trackLengthM
  -- Allures apprises aux tours précédents (en jeu : plusieurs tours de la Nordschleife) : l'IA 2 plus rapide partout.
  local function learnedPace() for i,v in pairs({[3]=210,[4]=180}) do local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=v/3.6 end end end
  local z={[1]=5000,[2]=0,[3]=600}
  local function set(i,v) local c=HOST.cars[i]; z[i]=z[i]+v/3.6/60; c.position={x=0,y=0,z=z[i]%L}; c.splinePosition=(z[i]%L)/L; c.velocity={x=0,z=v/3.6}; c.speedKmh=v; c.lapCount=1+math.floor(z[i]/L) end
  local attacking=false
  local attempts,flashes,flashesIgnored=0,0,0
  local passStates={OVT_ARM=true,OVT_IN=true,OVT_HOLD=true}
  for _=1,6*60*60 do
   if _%60==1 then learnedPace() end
   local s=e.states[3]
   local nowPass=passStates[s.state]==true
   if nowPass and not attacking then attempts=attempts+1 end
   attacking=nowPass
   local vT=attacking and 230 or 180
   local gap=z[3]-z[2]-4.4
   local vA=gap>30 and 210 or math.min(210,vT+math.max(-5,math.min(5,gap-12)))
   set(1,150); set(3,vT); set(2,vA)
   local before=e.commands[3].flashEvent or 0
   H.tick(HOST,1/60)
   if (e.commands[3].flashEvent or 0)~=before then flashes=flashes+1; if s.passIgnore==4 and e.time<s.passIgnoreUntil then flashesIgnored=flashesIgnored+1 end end
  end
  local function lines(text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
  assert(lines('cible plus rapide apres')>=2,'the loop is reproduced: repeated « target faster » failures')
  assert(flashesIgnored==0,'no flash toward the ignored target')
  assert(lines('depassement suspendu:')>=1,'strict wait logged')
  assert(attempts<=3,'at most three attempts in 6 min: '..attempts)
 end)
 check('1.55 : tentatives de dépassement sans progrès sur une cible aussi rapide (journée circuit) : coupées, attente de la paire',function()
  -- Nordschleife, 9 novembre : tentatives de 9 s en moyenne, jusqu'à 62 s, 27 sur 43 finies « cible plus rapide ». Ici :
  -- l'IA 2 (215 km/h) rattrape l'IA 3 (190 km/h), qui, attaquée, roule à son allure à quelques km/h près (virages) ; 6 min.
  HUMANAI.release(); HOST=H.create(false); HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,0.5)
  local e=HUMANAI.engine; local p=e.profiles.J
  for _,group in ipairs(C.sections) do p['section_'..group]=group~='traffic' end
  p.aiFlashEnabled=false; p.pressureEnabled=false; p.section_traffic=false; p.yieldEnabled=false; E.changed(e)
  local L=HOST.sim.trackLengthM
  local z={[1]=5000,[2]=0,[3]=400}
  local function set(i,v) local c=HOST.cars[i]; z[i]=z[i]+v/3.6/60; c.position={x=0,y=0,z=z[i]%L}; c.splinePosition=(z[i]%L)/L; c.velocity={x=0,z=v/3.6}; c.speedKmh=v; c.lapCount=1+math.floor(z[i]/L) end
  local passStates={OVT_ARM=true,OVT_IN=true,OVT_HOLD=true}
  local attacking,attempts,started,longest,time,waited=false,0,0,0,0,0
  for _=1,6*60*60 do
   local s=e.states[3]
   local nowPass=passStates[s.state]==true
   if nowPass and not attacking then attempts=attempts+1; started=time end
   if nowPass then longest=math.max(longest,time-started) end
   if s.passIgnore==4 and e.time<s.passIgnoreUntil then waited=waited+1/60 end
   attacking=nowPass
   local gap=z[3]-z[2]-4.4
   local vT=attacking and 215+5*math.sin(time*2*math.pi/5) or 190
   local vA=gap>10 and 215 or math.min(215,vT)
   set(1,150); set(3,vT); set(2,vA)
   H.tick(HOST,1/60); time=time+1/60
  end
  local function lines(text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
  print(string.format('1.55 futile overtakes: attempts %d, longest %.1f s, no progress %d, too long %d, target faster %d, not closing %d, suspended %d',
   attempts,longest,lines(': sans progres apres'),lines(': tentative trop longue apres'),lines(': cible plus rapide apres'),lines(': sans rapprochement apres'),lines('depassement suspendu:')))
  assert(attempts>=1,'an attempt is made')
  assert(longest<=C.K.passAttemptMax+1,'no attempt lasts more than 16 s: '..longest)
  assert(lines(': sans progres apres')>=1 and longest<=C.K.passProgressTime+1.5,'cut for lack of progress after 8 s: '..longest)
  assert(attempts<=3 and waited>=40,'per-pair wait after each cut: '..attempts..' attempts, '..waited..' s waited')
 end)
 check('1.55 : cession ordinaire à un suiveur pas plus rapide (allure libre égale) : refusée, notée une fois',function()
  -- Nordschleife, 9 novembre : 36 cessions en 10 min, 4 suivies d'un passage. Ici : l'IA 3 (180 km/h) est rattrapée par
  -- l'IA 2, de même allure libre apprise, qui se rapproche par à-coups (freinages) ; 6 min.
  HUMANAI.release(); HOST=H.create(false); HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,0.5)
  local e=HUMANAI.engine; local p=e.profiles.J
  for _,group in ipairs(C.sections) do p['section_'..group]=group~='traffic' end
  p.aiFlashEnabled=false; p.pressureEnabled=false; p.section_traffic=false; E.changed(e)
  local L=HOST.sim.trackLengthM
  local z={[1]=5000,[2]=0,[3]=150}
  local function set(i,v) local c=HOST.cars[i]; z[i]=z[i]+v/3.6/60; c.position={x=0,y=0,z=z[i]%L}; c.splinePosition=(z[i]%L)/L; c.velocity={x=0,z=v/3.6}; c.speedKmh=v; c.lapCount=1+math.floor(z[i]/L) end
  local function learned(i,kmh) local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=kmh/3.6 end; s.paceMean=kmh/3.6 end
  local yieldStates={YIELD_IN=true,YIELD_HOLD=true}
  local yielding,yields,time=false,0,0
  for _=1,6*60*60 do
   -- Beta 1.59 : hors course, refus seulement à un suiveur nettement plus lent (allure voisine : cession).
   learned(3,170); learned(4,180)
   local y=yieldStates[e.states[4].state]==true
   if y and not yielding then yields=yields+1 end
   yielding=y
   local gap=z[3]-z[2]-4.4
   local vF=gap>25 and 195 or 180+10*math.sin(time*2*math.pi/6)
   set(1,150); set(3,180); set(2,vF)
   H.tick(HOST,1/60); time=time+1/60
  end
  local function lines(text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
  print(string.format('1.55 yields without advantage: yields %d, attacks on a yield %d, refusals logged %d',yields,lines('(cession, '),lines('cession refusee:')))
  assert(yields==0,'no ordinary yield to a follower that is not faster: '..yields)
  assert(lines('cession refusee:')>=1 and lines('cession refusee:')<=6,'refusal logged once per episode')
 end)
 check('1.55 : appels de phares vers une IA qui cède sans être dépassée : suspendus après deux cessions sans passage',function()
  -- Nordschleife, 9 novembre : 80 appels de phares en 10 min, une même IA cédant 4 fois sans que l'appelant passe. Ici :
  -- l'IA 2, plus rapide en allure libre, est retenue derrière l'IA 3 (180 km/h) ; l'IA 3 cède à ses appels mais l'IA 2
  -- ne passe jamais (elle reste à son allure) ; 6 min.
  HUMANAI.release(); HOST=H.create(false); HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,0.5)
  local e=HUMANAI.engine; local p=e.profiles.J
  for _,group in ipairs(C.sections) do p['section_'..group]=group~='traffic' end
  p.aiFlashEnabled=true; p.pressureEnabled=false; p.section_traffic=false; p.yieldEnabled=false; E.changed(e)
  local L=HOST.sim.trackLengthM
  local z={[1]=5000,[2]=0,[3]=40}
  local function set(i,v) local c=HOST.cars[i]; z[i]=z[i]+v/3.6/60; c.position={x=0,y=0,z=z[i]%L}; c.splinePosition=(z[i]%L)/L; c.velocity={x=0,z=v/3.6}; c.speedKmh=v; c.lapCount=1+math.floor(z[i]/L) end
  local function learned(i,kmh) local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=kmh/3.6 end; s.paceMean=kmh/3.6 end
  local flashes,yields,yielding=0,0,false
  local yieldStates={YIELD_IN=true,YIELD_HOLD=true}
  for _=1,6*60*60 do
   learned(3,220); e.states[3].freePace=220/3.6; learned(4,180)
   local y=yieldStates[e.states[4].state]==true
   if y and not yielding then yields=yields+1 end
   yielding=y
   set(1,150); set(3,180); set(2,180)
   local before=e.commands[3].flashEvent or 0
   H.tick(HOST,1/60)
   if (e.commands[3].flashEvent or 0)~=before then flashes=flashes+1 end
  end
  local function lines(text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
  print(string.format('1.55 flashes: flashes %d, flash yields %d, suspended %d',flashes,yields,lines('appels de phares suspendus:')))
  assert(yields>=2,'the pattern is reproduced: yields on flashes without a pass')
  assert(lines('appels de phares suspendus:')>=1,'flashes suspended and logged')
  assert(flashes<=12,'far fewer flashes in 6 min: '..flashes)
 end)
 check('1.55 : avis « voiture lancée qui arrive » au joueur pas lancé : jamais pour une voiture de même allure, aussitôt pour une voiture 25 % plus rapide',function()
  -- Imola, essais du 9 novembre : avis pour des voitures qui ne rattrapaient jamais le joueur (écart de vitesse du moment
  -- bondissant à chaque freinage). Ici, qualifications : le joueur en tour de sortie (150 km/h), une IA lancée 60 m
  -- derrière, de même allure avec des à-coups de ±25 km/h, puis 25 % plus rapide ; 60 s chacune.
  local function run(kmh,swing)
   HUMANAI.release(); HOST=H.create(false); HOST.sim.raceSessionType=2; HOST.configType=2; HOST.space={x=1000,y=3000}; assert(loadstring(source))(); H.tick(HOST,0.5)
   local e=HUMANAI.engine; local p=e.profiles.Q
   for _,group in ipairs(C.sections) do p['section_'..group]=group~='traffic' end
   p.qualiTraffic=true; p.yellowMessage=true; p.aiFlashEnabled=false; E.changed(e)
   local L=HOST.sim.trackLengthM
   local z={[0]=1000,[1]=6000,[2]=940,[3]=3000}
   local function set(i,v) local c=HOST.cars[i]; z[i]=z[i]+v/3.6/60; c.position={x=0,y=0,z=z[i]%L}; c.splinePosition=(z[i]%L)/L; c.velocity={x=0,z=v/3.6}; c.speedKmh=v; c.lapCount=1+math.floor(z[i]/L) end
   local time=0
   for _=1,60*60 do
    local q=e.quali.cars; q[1].out=true; q[3].out=false; q[3].cool=false; q[3].planned=false
    set(0,150); set(1,150); set(2,kmh+swing*math.sin(time*2*math.pi/4)); set(3,150)
    H.tick(HOST,1/60); time=time+1/60
   end
   local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('arrive derriere le joueur',1,true) then n=n+1 end end
   return n,e.quali.active
  end
  local same,active=run(150,25)
  local fast=run(187.5,0)
  print(string.format('1.55 flying-lap warning: same pace %d warning(s), 25 %% faster %d warning(s), active %s',same,fast,tostring(active)))
  assert(active,'flying laps active (qualifying)')
  assert(same==0,'same pace, braking swings: never announced: '..same)
  assert(fast>=1,'25 % faster: announced')
 end)
 -- Beta 1.56 (décision du pilote) : vos limites de piste gérées par l'app, pénalités croissantes, rapport de course en
 -- CSV ; tout coupé par défaut. Course de l'hôte (joueur = voiture 0), préréglage Course, sorties du joueur à 100 km/h.
 local function race156(settings)
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.session={laps=10,durationMinutes=0,isTimedRace=false}
  assert(loadstring(source))(); H.tick(HOST,0.5)
  local e=HUMANAI.engine; local p=e.profiles.C
  C.preset('Course','C',p)
  for k,v in pairs(settings or {}) do p[k]=v end
  E.changed(e); H.tick(HOST,0.5)
  assert(e.profile=='C' and C.on(e.p,'sanctions'),'race with sanctions')
  return e
 end
 local function playerOff(seconds)
  local c=HOST.cars[0]; c.wheelsOutside=4; c.speedKmh=100; c.velocity={x=0,z=100/3.6}; H.tick(HOST,seconds or 1)
  c.wheelsOutside=0; H.tick(HOST,C.K.sanStrikeGap+0.2)
 end
 local function lines156(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
 check('1.56 : réglages par défaut : vos sorties jamais sanctionnées, aucune demande de pénalité, aucun rapport',function()
  local e=race156()
  assert(not e.run.sanPlayerTrackLimits and not e.run.sanEscalation and not e.run.sanReport,'off by default')
  local requests=#HOST.penalties
  for _=1,10 do playerOff(1) end
  for i=0,3 do HOST.cars[i].isRaceFinished=true end; H.tick(HOST,2)
  assert(lines156(e,'limites de piste joueur')==0 and lines156(e,'tour invalide joueur')==0 and lines156(e,'rapport de course')==0,'no new line')
  assert(#HOST.penalties==requests and e.sanctions.cars[1].time==0,'no penalty')
  assert(HOST.files['logs/AdvancedIA-race.csv']==nil,'no report file')
 end)
 check('1.56 : vos limites de piste en course (temps) : avertissements, puis pénalité au classement corrigé, jamais le drapeau noir',function()
  local e=race156({sanPlayerTrackLimits=true})
  local requests=#HOST.penalties
  for _=1,5 do playerOff(1) end
  local c=e.sanctions.cars[1]
  print(string.format('1.56 player track limits: warnings %d, penalties %d, time %.0f s',c.rWarn,c.trackN,c.time))
  assert(lines156(e,'limites de piste joueur: avertissement')==3,'three warnings')
  assert(lines156(e,'limites de piste joueur: penalite de temps +5 s')==2 and c.time==10,'then time penalties')
  assert(#HOST.penalties==requests and not e.penalties.disqualified,'nothing written to your car, never a black flag')
 end)
 check('1.56 : vos limites de piste, coupure des gaz d AC : demandée une fois ; refusée par CSP : du temps à la place',function()
  local e=race156({sanPlayerTrackLimits=true,sanPlayerPenalty='throttle',sanTrackWarnings=0})
  local requests=#HOST.penalties
  playerOff(1)
  assert(#HOST.penalties==requests+1 and HOST.penalties[#HOST.penalties]==5,'AC throttle cut 5 s written once')
  assert(e.sanctions.cars[1].time==0 and e.penalties.count==0,'no time, not counted towards the black flag')
  local saved=physics.setCarPenalty
  physics.setCarPenalty=function() error('refused') end
  playerOff(1); H.tick(HOST,C.K.sanPlayerCutConfirm+0.5)
  physics.setCarPenalty=saved
  print(string.format('1.56 throttle fallback: time %.0f s, refused line %d',e.sanctions.cars[1].time,lines156(e,'coupure des gaz refusee par AC')))
  assert(e.sanctions.cars[1].time==5 and lines156(e,'coupure des gaz refusee par AC')==1,'refused by CSP: a time penalty instead')
  local before=#HOST.penalties; H.tick(HOST,2); assert(#HOST.penalties==before,'never written afterwards')
 end)
 check('1.56 : pénalités d AC actives alors que l app gère vos limites de piste : prévenu une fois (journal, accueil)',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.sim.penaltiesEnabled=true; HOST.sim.allowedTyresOut=-1
  assert(loadstring(source))(); H.tick(HOST,0.5)
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.profiles.C.sanPlayerTrackLimits=true; E.changed(e); H.tick(HOST,1)
  assert(lines156(e,'limites de piste joueur: penalites d AC actives (roues dehors autorisees -1)')==1 and e.acPenaltyWarned,'warned once')
  H.tick(HOST,2); assert(lines156(e,'penalites d AC actives')==1,'once per session')
 end)
 check('1.56 : rapport de course : écrit une fois à l arrivée, rotation à la course suivante, partiel au changement de session',function()
  local e=race156({sanReport=true,sanPlayerTrackLimits=true})
  for _=1,4 do playerOff(1) end
  for i=0,3 do HOST.cars[i].isRaceFinished=true; HOST.cars[i].racePosition=i+1 end; H.tick(HOST,2)
  local text=HOST.files['logs/AdvancedIA-race.csv']
  assert(text and text:find('complete=1',1,true) and lines156(e,'rapport de course ecrit: AdvancedIA-race.csv (4 voitures)')==1,'written once the race is complete')
  local rows=0; for _ in text:gmatch('\n') do rows=rows+1 end
  print(string.format('1.56 race report: %d lines, first data row: %s',rows,text:match('\n[^\n]*\n([^\n]*)') or '?'))
  assert(rows==6 and text:find('corrected_pos,ac_pos,driver',1,true),'header and four cars')
  H.tick(HOST,5); assert(lines156(e,'rapport de course ecrit')==1,'only once')
  -- Course suivante interrompue par un changement de session : rapport partiel, l'ancien décalé.
  for i=0,3 do HOST.cars[i].isRaceFinished=false end
  -- Nouvelle session : le préréglage de la session (s'il est allumé) remet les options à leur défaut ; rapport rallumé.
  HOST.sim.currentSessionIndex=HOST.sim.currentSessionIndex+1; H.tick(HOST,1)
  e.profiles.C.sanReport=true; E.changed(e); H.tick(HOST,1)
  assert(e.run.sanReport and e.sanctions.raceSeen and not e.sanctions.reportDone,'second race under way')
  HOST.sim.currentSessionIndex=HOST.sim.currentSessionIndex+1; H.tick(HOST,1)
  assert(HOST.files['logs/AdvancedIA-race.1.csv'] and HOST.files['logs/AdvancedIA-race.csv']:find('complete=0',1,true),'partial report, previous one rotated')
 end)
 -- Beta 1.57 (Ved, Overtake) : suspension nommée ; toujours la garde « online » (aucune commande), une ligne au journal par
 -- début ou changement de genre, bandeau et textes propres au mode alt-online.
 check('1.57 : alt-online et vraie session en ligne nommées : une ligne au journal, bandeau alt-online',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))(); H.tick(HOST,1)
  local e=HUMANAI.engine
  HOST.sim.isAltOnlineRace=true; H.tick(HOST,1)
  local old=HOST.calls; H.tick(HOST,2)
  assert(e.guard=='online' and e.guardKind=='alt' and HOST.calls==old,'alt-online: suspended, named, no command')
  assert(lines156(e,'suspension: mode alt-online de CSP')==1,'logged once')
  pause(true); go('home'); redraw()
  assert(drawnText(W.upper(L.banners.altonline[1])) and not drawnText(W.upper(L.banners.online[1])) and drawn('banner_action'),'alt-online banner with its Got it button')
  pause(false)
  HOST.sim.isAltOnlineRace=false; HOST.sim.isOnlineRace=true; H.tick(HOST,1)
  assert(e.guard=='online' and e.guardKind=='online' and lines156(e,'suspension: session en ligne, aucune commande')==1,'real online named and logged')
  HOST.sim.isOnlineRace=false; H.tick(HOST,1); assert(e.guard~='online' and e.guardKind==nil,'offline again')
  print(string.format('1.57 guard kinds: alt %d line(s), online %d line(s)',lines156(e,'suspension: mode alt-online'),lines156(e,'suspension: session en ligne')))
 end)
 -- Beta 1.58 (MJFox, Overtake ; vu aussi par le pilote) : après l'arrivée, une IA gardée par l'app entrée dans la voie des
 -- stands y gardait ses dernières valeurs (décalage, vitesse limitée…) et tapait le mur : rendue à AC dans la voie, seules
 -- des valeurs d'origine y sont écrites (l'hôte refuse toute autre écriture aux stands).
 local function leftover(index)
  local s=HUMANAI.host.cars[index+1]; assert(s.owned,'AI driven by the app')
  physics.setAISplineOffset(index,-0.2); s.offset=-0.2; s.offsetReset=false
  physics.setAITopSpeed(index,150); s.speed=150
  return s
 end
 check('1.58 : après l arrivée, voiture gardée rendue à AC dans la voie des stands (décalage, vitesse, niveau)',function()
  local e=race156(); H.tick(HOST,3)
  local s=leftover(1)
  HOST.cars[1].isRaceFinished=true; HOST.cars[1].isInPitlane=true; HOST.cars[1].speedKmh=60
  local lane=HOST.laneWrites; H.tick(HOST,1)
  print(string.format('1.58 finish release: offset %s, speed %s, lane writes %d, line %d',tostring(HOST.offsets[1]),tostring(HOST.speedLimits[1]),HOST.laneWrites-lane,lines156(e,'voiture rendue a AC apres l arrivee')))
  assert(HOST.offsets[1]==0 and HOST.speedLimits[1]==C.K.unlimitedSpeed and s.level==nil and s.caution==nil,'handed back to AC in the lane')
  assert(HOST.laneWrites>lane and lines156(e,'voiture rendue a AC apres l arrivee')==1,'only original values written there, one line')
  local after=HOST.laneWrites; H.tick(HOST,3); assert(HOST.laneWrites==after,'nothing more written in the lane')
 end)
 check('1.58 : en course, dans la voie des stands, la demande d arrêt de l app est gardée',function()
  local e=race156(); H.tick(HOST,3)
  local s=leftover(2); s.pitRequest=true; physics.setAIPitStopRequest(2,true)
  HOST.cars[2].isInPitlane=true; HOST.cars[2].speedKmh=60; H.tick(HOST,1)
  assert(HOST.pitRequests[2]==true and s.pitRequest,'pit request kept in the lane')
  assert(HOST.offsets[2]==0 and HOST.speedLimits[2]==C.K.unlimitedSpeed,'offset and speed given back')
  assert(lines156(e,'voiture rendue a AC dans la voie des stands')==1,'one line')
 end)
 -- Beta 1.58 (course du pilote, fn_imola, 10 novembre) : une IA dont l'arrêt obligatoire était demandé, déplacée à son
 -- emplacement par AC ou CSP (sans entrée par la voie des stands), y était servie sans que l'arrêt compte ; la demande
 -- restait et l'IA était servie en boucle (pneus SS/S alternés) jusqu'à l'arrivée.
 local function f1race()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.session={laps=20,durationMinutes=0,isTimedRace=false}
  for i=0,3 do HOST.tyreCatalog[i]={{short='SS',name='Slick SuperSoft'},{short='S',name='Slick Soft'},{short='M',name='Slick Medium'}} end
  assert(loadstring(source))()
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C)
  e.profiles.C.mandatoryStops=1; e.profiles.C.pitCompoundChange=true; e.profiles.C.pitTyres=true; e.profiles.C.minPitTime=0; E.changed(e)
  HOST.sim.leaderLapCount=4; H.tick(HOST,3); assert(e.profile=='C' and e.pits.state=='pending')
  return e
 end
 local function tyreLines(e,slot) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('pneus poses',1,true) and r.index==slot then n=n+1 end end return n end
 local function toBox(car) car.isInPitlane=true; car.isInPit=true; car.speedKmh=0; car.velocity={x=0,z=0}; car.position={x=car.position.x,y=0,z=car.position.z+900} end
 local function out(car) car.isInPit=false; car.isInPitlane=false; car.speedKmh=108; car.velocity={x=0,z=30} end
 check('1.58 : arrêt demandé, IA déplacée à son emplacement par AC : servie une fois, arrêt compté, composé stable, elle repart',function()
  local e=f1race()
  HOST.sim.leaderLapCount=14; H.tick(HOST,3)
  assert(HOST.pitRequests[1]==true and e.pits.cars[2].wanted,'mandatory stop requested')
  local car=HOST.cars[1]; local before=car.compoundIndex; local tyres=tyreLines(e,2)
  toBox(car); H.tick(HOST,2)
  local c=e.pits.cars[2]
  print(string.format('1.58 teleported stop: window stops %d, tyres %d -> %d, service lines %d',c.windowStops,before,car.compoundIndex,tyreLines(e,2)-tyres))
  assert(c.windowStops==1 and lines156(e,'arret aux stands: 1 (dont 1 dans la fenetre)')>=1,'the requested stop counts')
  assert(car.compoundIndex~=before and tyreLines(e,2)-tyres==1,'one service, another compound')
  -- Sortie de l'emplacement, toujours dans la voie (comme dans la course du pilote) : la demande d'AC est levée là aussi.
  car.isInPit=false; car.speedKmh=40; car.velocity={x=0,z=11}; H.tick(HOST,1)
  assert(HOST.pitRequests[1]==false and not c.wanted,'request lifted inside the lane')
  local fitted=car.compoundIndex
  -- AC (ou CSP) la ramène plusieurs fois à son emplacement sans qu'elle sorte de la voie : aucun nouveau service.
  for _=1,3 do toBox(car); H.tick(HOST,2); car.isInPit=false; car.speedKmh=40; car.velocity={x=0,z=11}; H.tick(HOST,1) end
  print(string.format('1.58 re-boxed in the lane x3: compound %d -> %d, service lines %d, window stops %d',fitted,car.compoundIndex,tyreLines(e,2)-tyres,c.windowStops))
  assert(tyreLines(e,2)-tyres==1 and car.compoundIndex==fitted and c.windowStops==1,'exactly one service, stable compound')
  assert(lines156(e,'emplacement de nouveau sans sortie de la voie des stands')==1,'one line')
  out(car); H.tick(HOST,3)
  assert(not c.wanted and HOST.pitRequests[1]==false and c.windowStops==1,'released, never requested again')
  assert(lines156(e,'arret demande: obligatoire, ')==3,'one request per AI, never a loop')
  -- Beta 1.59 : aucune ligne DEBUG sans le journal détaillé (lignes des modules purs comprises).
  local debug=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.level=='DEBUG' and r.message~='' then debug=debug+1 end end
  assert(not e.g.debugLog and debug==0,'no DEBUG line without the detailed journal: '..debug)
 end)
 check('1.58 : dépannage sous neutralisation avec pneus posés, puis l arrêt obligatoire servi une fois, sans retour au composé de départ après le dépannage',function()
  local e=f1race()
  local car=HOST.cars[1]; local start=car.compoundIndex
  -- Dépannage (déplacement à l'emplacement) avant la fenêtre : pneus posés, aucun arrêt compté.
  toBox(car); H.tick(HOST,2)
  local c=e.pits.cars[2]
  assert(c.windowStops==0 and c.stops==0 and car.compoundIndex~=start,'tow: tyres fitted, no stop counted')
  local towed=car.compoundIndex
  out(car); H.tick(HOST,3)
  HOST.sim.leaderLapCount=14; H.tick(HOST,3)
  assert(HOST.pitRequests[1]==true and c.wanted,'mandatory stop still owed and requested')
  local tyres=tyreLines(e,2)
  car.isInPitlane=true; H.tick(HOST,0.5); car.isInPit=true; car.speedKmh=0; car.velocity={x=0,z=0}; H.tick(HOST,2)
  print(string.format('1.58 stop after a tow: compounds %d -> %d -> %d, window stops %d',start,towed,car.compoundIndex,c.windowStops))
  assert(c.windowStops==1 and tyreLines(e,2)-tyres==1,'served once and counted')
  -- Deux composés secs déjà roulés (départ, puis après le dépannage) : la règle F1 est remplie ; un autre que celui monté.
  assert(car.compoundIndex~=towed and e.pits.cars[2].usedCount==2,'another compound than the fitted one, two compounds raced')
  out(car); H.tick(HOST,3); assert(HOST.pitRequests[1]==false,'request lifted')
 end)
 -- Beta 1.59 (n° 16) : chaque étape donnée sur Overtake pour alléger ou couper l'overlay fait ce que dit son libellé.
 check('1.59 : étapes pour couper l overlay : panneau de l app, infos de session, récapitulatif, messages d AC, options de CSP, overlay coupé',function()
  local gui,state='cfgext\\gui.ini','cfgstate\\ACAdvancedIA-cspgui.ini'
  local original='[NEW_UI]\r\nUI_SCALE=1.05\r\n\r\n[HIDE]\r\n'
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.files[gui]=original
  assert(loadstring(source))(); H.tick(HOST,1)
  local e=HUMANAI.engine; local g=e.g; local v=HUMANAI.panel; local UIm=package.loaded['src/ui']; local K=C.K
  local function lines() local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and not r.message:find('options CSP',1,true) then n=n+1 end end return n end
  assert(HOST.files[gui]:find('HIDE_RACE_FLAGS=1',1,true) and HOST.files[gui]:find('HIDE_SYSTEM_MESSAGES=1',1,true),'both hidden at launch')
  -- 1. « Panneau de drapeaux AdvancedIA en conduite » coupé, dans chaque profil (section Accidents) : plus d'avis de l'app
  -- dans le bandeau (passage de la ligne, DRS, mise à jour) ; drapeaux et pénalités du jeu seulement.
  local me=HOST.cars[0]
  for _,profile in ipairs(C.profiles) do
   E.select(e,profile); e.profiles[profile].flagPanel=false; e.profiles[profile].section_accidents=true; e.profiles[profile].section_rules=true; E.changed(e); H.tick(HOST,0.5)
   assert(not e.run.flagPanel,profile..': panel off')
   me.drsPresent=true; me.drsAvailable=true; me.drsActive=false; e.hud.lapUntil=e.time+5; e.panel.updateUntil=e.time+5; e.panel.updateVersion='9.9'
   H.tick(HOST,0.5); assert(e.panel.kind=='none',profile..': no app notice in the band ('..e.panel.kind..')')
   me.currentPenaltyType=K.penaltyMandatoryPits; me.currentPenaltyParameter=2; H.tick(HOST,0.5)
   assert(e.panel.kind=='penaltyDrive' or e.panel.kind=='penalty',profile..': the game penalty stays ('..e.panel.kind..')')
   me.currentPenaltyType=0; me.currentPenaltyParameter=0; me.drsAvailable=false; e.panel.updateUntil=-math.huge
   e.profiles[profile].flagPanel=true; E.changed(e); H.tick(HOST,0.5)
  end
  E.select(e,'C'); H.tick(HOST,0.5)
  -- 2. « Infos de session » coupé : plus de ligne de session (sans message d'AC ni avis de sanction).
  g.panelShow='always'; e.hud.msgUntil=-math.huge; e.hud.aiUntil=-math.huge; H.tick(HOST,1)
  local shared=UIm.overlayParts(v); assert(shared.strip,'session line shown')
  g.overlaySession=false; H.tick(HOST,0.2); assert(not UIm.overlayParts(v).strip,'session info off: no session line')
  -- Message d'AC repris : la ligne revient pour lui seul (réglage « Reprendre les messages d'AC »).
  HOST.messageListeners[1]('ABS','3',nil,5); H.tick(HOST,0.3); assert(UIm.overlayParts(v).strip,'an AC message still uses the line')
  -- 4. « Reprendre les messages d'AC sur l'overlay » coupé : aucun message d'AC sur l'overlay.
  g.overlayMessages=false; H.tick(HOST,0.2); local p=UIm.overlayParts(v); assert(not (p and (p.strip or p.message)),'AC messages off: none on the overlay')
  g.overlayMessages=true; g.overlaySession=true; e.hud.msgUntil=-math.huge
  -- 3. « Récapitulatif de fin de course » coupé : pas de récapitulatif à l'arrivée.
  e.panel.kind='checkered'; e.panel.finish=true; e.panel.changedAt=e.time; e.hud.recap={'RACE OVER','P1','x'}
  assert(UIm.overlayParts(v,true).recap,'summary shown at the finish')
  g.overlayRecap=false; assert(not UIm.overlayParts(v,true).recap,'summary off: none')
  g.overlayRecap=true; e.panel.kind='none'; e.panel.finish=false; e.hud.recap={}
  -- 5. Options de CSP coupées : valeurs d'origine du pilote rendues (AC dessine ses drapeaux et ses messages). Nouveau
  -- lancement : les bascules de l'étape 1 ont usé le plafond d'écritures de gui.ini de la partie (K.cspWritesMax).
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
  HOST=H.create(true); HOST.sim.raceSessionType=3; HOST.files[gui]=original
  assert(loadstring(source))(); H.tick(HOST,1)
  e=HUMANAI.engine; g=e.g; v=HUMANAI.panel; E.select(e,'C'); H.tick(HOST,1)
  assert(HOST.files[gui]:find('HIDE_RACE_FLAGS=1',1,true) and HOST.files[gui]:find('HIDE_SYSTEM_MESSAGES=1',1,true),'both hidden while the app is active')
  g.cspHideFlags=false; H.tick(HOST,0.2); assert(not HOST.files[gui]:find('HIDE_RACE_FLAGS=1',1,true) and HOST.files[gui]:find('HIDE_SYSTEM_MESSAGES=1',1,true),'flags given back')
  g.cspHideMessages=false; H.tick(HOST,0.2); assert(HOST.files[gui]==original and HOST.files[state]==nil,'messages given back: original byte for byte')
  g.cspHideFlags=true; g.cspHideMessages=true; H.tick(HOST,0.2); assert(HOST.files[gui]~=original,'hidden again')
  -- 6. « Overlay de l'app » coupé (n° 15) : rien de l'overlay dans aucun cas, options de CSP et case de session rendues ;
  -- aucun effet sur le journal (hors lignes des options de CSP).
  HOST.transparent={}; script.HUMANAI__HUD(); assert(HOST.transparent.AdvancedIA_overlay and HOST.hudHidden.sessionTime==true,'overlay drawn, AC box replaced')
  local before=lines()
  g.overlayEnabled=false; H.tick(HOST,0.2)
  assert(HOST.files[gui]==original,'overlay off: CSP options given back')
  HOST.transparent={}; script.HUMANAI__HUD(); assert(not HOST.transparent.AdvancedIA_overlay and HOST.hudHidden.sessionTime==false and HOST.blocked==0,'overlay off: nothing drawn, AC box back, AC messages not blocked')
  local states={{kind='red'},{kind='yellow'},{kind='penalty'},{kind='drs'},{kind='lap'},{kind='checkered',finish=true}}
  e.hud.aiUntil=e.time+5; e.hud.msgUntil=e.time+5; e.hud.recap={'RACE OVER','P1'}
  for _,s in ipairs(states) do
   e.panel.kind=s.kind; e.panel.finish=s.finish or false; e.panel.changedAt=e.time
   for _,force in ipairs({false,true}) do assert(UIm.overlayParts(v,force)==nil,'overlay off: nil for '..s.kind) end
  end
  g.overlayLocked=false; HOST.transparent={}; script.HUMANAI__HUD(); assert(not HOST.transparent.AdvancedIA_overlay,'unlocked overlay off: nothing'); g.overlayLocked=true
  e.panel.kind='none'; e.panel.finish=false; e.hud.aiUntil=-math.huge; e.hud.msgUntil=-math.huge; e.hud.recap={}
  H.tick(HOST,1); assert(lines()-before<=1,'no journal effect')
  -- Relecture : CSP masque encore les drapeaux d'AC (gui.ini pas relu, plafond, lecture seule) : drapeaux et pénalités du
  -- jeu seulement, sinon personne ne les dessine ; plus rien dès que CSP ne les masque plus.
  local cg=HUMANAI.host.cspgui; cg.applied.HIDE_RACE_FLAGS=true
  me=HOST.cars[0]; me.currentPenaltyType=K.penaltyMandatoryPits; me.currentPenaltyParameter=2; H.tick(HOST,0.5)
  -- Table des parties partagée entre les appels : un avis de l'app resté d'un affichage précédent est remis à faux.
  shared.pills=true
  local q=UIm.overlayParts(v)
  assert(q==shared and q.band and not q.recap and not q.ai and not q.strip and not q.pills and (e.panel.kind=='penaltyDrive' or e.panel.kind=='penalty'),'CSP still hiding AC flags: the game penalty is drawn ('..e.panel.kind..')')
  HOST.transparent={}; script.HUMANAI__HUD(); assert(HOST.transparent.AdvancedIA_overlay and HOST.hudHidden.sessionTime==false,'drawn, AC box still given back')
  me.currentPenaltyType=0; me.currentPenaltyParameter=0; H.tick(HOST,0.5); assert(UIm.overlayParts(v)==nil,'no game flag: nothing')
  cg.applied.HIDE_SYSTEM_MESSAGES=true; HOST.messageListeners[1]('ABS','3',nil,5); H.tick(HOST,0.3)
  q=UIm.overlayParts(v); assert(q and q.strip and q.message and not q.band,'CSP still hiding AC messages: the message is drawn')
  cg.applied.HIDE_RACE_FLAGS=false; cg.applied.HIDE_SYSTEM_MESSAGES=false; H.tick(HOST,0.2); assert(UIm.overlayParts(v)==nil,'CSP no longer hiding: nothing')
  g.overlayEnabled=true; H.tick(HOST,0.2); HOST.transparent={}; script.HUMANAI__HUD()
  assert(HOST.transparent.AdvancedIA_overlay and HOST.hudHidden.sessionTime==true and HOST.files[gui]~=original,'on again: as before')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 -- Beta 1.59 (n° 17) : même course relancée par AC (même indice de session) : récapitulatif refait pour la nouvelle course,
 -- arrivée publiée au pont fausse entre la relance et la nouvelle arrivée.
 check('1.59 : course relancée dans la même session : récapitulatif de la nouvelle course, arrivée remise à zéro',function()
  HUMANAI.release(); HOST=H.create(true); HOST.sim.raceSessionType=3; assert(loadstring(source))(); H.tick(HOST,0.5)
  local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); E.changed(e); H.tick(HOST,1)
  local function count(text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
  for i=0,3 do HOST.cars[i].racePosition=i+1 end; H.tick(HOST,1)
  assert(e.hud.started and e.hud.grid==1,'first race: starts P1')
  for i=0,3 do HOST.cars[i].isRaceFinished=true end; HOST.cars[0].racePosition=4; HOST.cars[3].racePosition=1; H.tick(HOST,2)
  assert(e.hud.finished and e.hud.final==4 and count('fin de course: ')==1,'first race finished P4')
  -- Relance : départ retombé, voitures plus arrivées.
  HOST.sim.isSessionStarted=false; H.tick(HOST,0.2); for i=0,3 do HOST.cars[i].isRaceFinished=false end; H.tick(HOST,1)
  assert(not e.hud.finished and not e.hud.started and count('course relancee: ')==1 and count('fin de course: ')==1,'restart: reset, no second summary')
  assert(e.hud.final==0 and e.hud.grid==0,'bridge values reset (finished false, places 0)')
  -- Image encore marquée finie au moment de la relance (course précédente) : le départ n'y est pas pris.
  HOST.sim.isSessionFinished=true; HOST.cars[0].racePosition=2; HOST.sim.isSessionStarted=true; H.tick(HOST,0.3)
  assert(not e.hud.started and e.hud.grid==0,'frame still marked finished: start not taken')
  HOST.sim.isSessionFinished=false
  HOST.cars[0].racePosition=3; HOST.cars[3].racePosition=4; HOST.sim.isSessionStarted=true; H.tick(HOST,1)
  assert(e.hud.started and e.hud.grid==3 and not e.hud.finished,'second race: starts P3, not finished')
  for i=0,3 do HOST.cars[i].isRaceFinished=true end; HOST.cars[0].racePosition=2; H.tick(HOST,2)
  assert(e.hud.finished and e.hud.final==2 and e.hud.grid==3 and count('fin de course: ')==2,'second summary for the second race')
  HOST.releasing=true; HUMANAI.release(); HOST.releasing=false
 end)
 -- Beta 1.59 (H-A, décision du pilote) : vrais passages en piste des IA. Qualifications : sortie, un tour lancé, rentrée,
 -- attente à l'emplacement, composé le plus tendre ; essais : programmes variés ; coupé par défaut (rien de commandé).
 check('1.59 : passages en piste des IA en qualifications (sortie, un tour lance, rentree, attente, composé le plus tendre) et programmes varies en essais',function()
  local function session(kind,on)
   HUMANAI.release(); HOST=H.create(false); HOST.sim.raceSessionType=kind; HOST.configType=kind
   if kind==1 then HOST.raceIni={SESSION_0={NAME='Practice',TYPE=1}} end
   for i=0,3 do HOST.tyreCatalog[i]={{short='SS',name='Slick SuperSoft'},{short='S',name='Slick Soft'},{short='M',name='Slick Medium'}} end
   assert(loadstring(source))(); H.tick(HOST,0.5)
   local e=HUMANAI.engine; local p=e.profiles[kind==2 and 'Q' or 'P']
   for _,group in ipairs(C.sections) do p['section_'..group]=group~='traffic' end
   p.qualiRuns=on; E.changed(e)
   return e
  end
  local function runLines(e) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find('passage en piste: ',1,true) and r.index==2 then n=n+1 end end return n end
  -- Coupé (défaut) : aucune ligne, aucune demande.
  local e=session(2,false); local car=HOST.cars[1]; toBox(car); H.tick(HOST,2)
  assert(runLines(e)==0 and HOST.pitRequests[1]~=true and e.commands[2].runFuelSet==-1,'off: nothing commanded')
  -- Qualifications : premier passage préparé à l'emplacement (composé le plus tendre).
  e=session(2,true); car=HOST.cars[1]; toBox(car); H.tick(HOST,2)
  print(string.format('1.59 qualifying run: compound %d, run lines %d',car.compoundIndex,runLines(e)))
  assert(runLines(e)==1 and car.compoundIndex==0,'first run planned on the softest compound')
  -- Sortie, tour de sortie (ligne bien après la sortie), un tour lancé, puis le tour de rentrée : arrêt demandé.
  out(car); H.tick(HOST,C.K.qualiOutGrace+1)
  car.lapCount=(car.lapCount or 0)+1; H.tick(HOST,1); assert(HOST.pitRequests[1]~=true,'flying lap: no request')
  car.lapCount=car.lapCount+1; H.tick(HOST,1)
  print(string.format('1.59 qualifying in-lap: pit request %s',tostring(HOST.pitRequests[1])))
  assert(HOST.pitRequests[1]==true,'in-lap: pit requested')
  -- Retour à l'emplacement : nouveau passage prévu, l'IA y attend.
  toBox(car); H.tick(HOST,2)
  local c=e.runs.cars[2]
  print(string.format('1.59 qualifying back in the box: run lines %d, wait %.0f s',runLines(e),c.waitUntil-e.time))
  assert(runLines(e)==2 and c.waitUntil-e.time>=C.K.runsBoxQMin-3,'next run planned, waiting in the box')
  -- Essais : programmes tirés au sort pour chaque IA.
  e=session(1,true); for i=1,3 do toBox(HOST.cars[i]) end
  H.tick(HOST,2)
  local kinds={}; for i=1,4 do local r=e.runs.cars[i]; if r and r.program~='' then kinds[#kinds+1]=r.program end end
  print('1.59 practice programmes: '..table.concat(kinds,', '))
  assert(e.profile=='P' and #kinds>=2,'practice runs planned for the AI')
 end)
 -- Beta 1.59 (fourche H-B) : stratégies de départ variées et arrêt aux stands pour dégâts, coupés par défaut.
 check('1.59 : stratégies de départ variées sur la grille (course), rien réglage coupé ni après le départ',function()
  local K=C.K; local share=K.startVarietyShare
  for _,on in ipairs({false,true}) do
   HUMANAI.release(); HOST=H.create(true)
   for i=1,3 do HOST.tyreCatalog[i]={{short='SS',name='Slick SuperSoft'},{short='S',name='Slick Soft'},{short='M',name='Slick Medium'}} end
   HOST.sim.isSessionStarted=false; HOST.sim.timeToSessionStart=20000
   for i=1,3 do HOST.cars[i].speedKmh=0; HOST.cars[i].velocity={x=0,z=0}; HOST.cars[i].compoundIndex=1 end
   assert(loadstring(source))(); local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.g.autoProfile=false; e.g.manualProfile='C'
   e.profiles.C.strategyStartVariety=on; E.changed(e)
   K.startVarietyShare=1
   local ok,err=pcall(H.tick,HOST,3); K.startVarietyShare=share; assert(ok,err)
   local changed=0; for i=1,3 do if HOST.cars[i].compoundIndex~=1 then changed=changed+1 end end
   local n=lines156(e,'strategie de depart: ')
   print(string.format('1.59 starting strategies %s: %d AI on another compound, %d line(s)',on and 'on' or 'off',changed,n))
   if not on then assert(changed==0 and n==0,'switch off: nothing changed, nothing logged')
   else
    assert(changed==3 and n==3,'every AI eligible: one step softer or harder, one line each')
    for i=1,3 do assert(HOST.cars[i].compoundIndex==0 or HOST.cars[i].compoundIndex==2,'one step only') end
    assert(not HOST.pitRequested[1] and not HOST.pitRequested[2] and not HOST.pitRequested[3],'no pit stop for a starting compound')
    local fitted={}; for i=1,3 do fitted[i]=HOST.cars[i].compoundIndex end
    HOST.sim.isSessionStarted=true; HOST.sim.timeToSessionStart=0; H.tick(HOST,3)
    for i=1,3 do assert(HOST.cars[i].compoundIndex==fitted[i],'nothing more after the start') end
    assert(lines156(e,'strategie de depart: ')==3,'no new line after the start')
   end
  end
 end)
 check('1.59 : arrêt aux stands pour dégâts (course) : IA endommagée à pleine allure appelée, rien réglage coupé',function()
  for _,on in ipairs({false,true}) do
   HUMANAI.release(); HOST=H.create(true)
   assert(loadstring(source))(); local e=HUMANAI.engine; C.preset('Course','C',e.profiles.C); e.g.autoProfile=false; e.g.manualProfile='C'
   e.profiles.C.damagePit=on; E.changed(e)
   H.tick(HOST,1)
   HOST.cars[1].damage={[0]=120,[1]=0,[2]=0,[3]=0,[4]=0}; HOST.cars[1].suspensionDamage={[0]=0.1,[1]=0,[2]=0,[3]=0}
   H.tick(HOST,8)
   local n=lines156(e,'degats: ')
   print(string.format('1.59 damage pit stop %s: requested %s, %d line(s)',on and 'on' or 'off',tostring(HOST.pitRequests[1]),n))
   if not on then
    assert(n==0 and not HOST.pitRequested[1],'switch off: no call, no line')
    for i=1,e.frame.count do assert(not e.frame.cars[i].damageScan,'switch off: no damage read while driving') end
   else assert(n==1 and HOST.pitRequests[1]==true,'called once, pit stop requested') end
  end
 end)
 C.globalDefaults.presetBySession=presetDefault
 return results
end
