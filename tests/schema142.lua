-- Beta 1.42, étape de schéma : stratégie et sanctions des IA, aspiration, air sale, fin de course, pneus. Réglages,
-- sections, préréglages, migration, textes et interfaces neutres (aucun effet tant que les modules sont vides).
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local A=require('src/applier')
local Groups=require('src/groups')
local Pr=require('src/presets')
local Strategy=require('src/strategy')
local Sanctions=require('src/sanctions')
local K=C.K
local tests={}
local newKeys={
 overtake={'towBreakEnabled','towBreakRange','towBreakStraight','dirtyAirEnabled','dirtyAirGap','dirtyAirLiftPct','finalLapsEnabled','finalLaps','finalAggressionPct','finalDefensePct'},
 weather={'outLapEnabled','outLapLevelPct','lockWearEnabled','lockWearGain','lockFlatSpotKm'},
 strategy={'strategyEnabled','strategyTyreWearPct','strategyFuelMarginLaps','strategyUndercut','strategyRiskPct','strategySpreadPct','failuresEnabled','failureRate','failureLossPct'},
 sanctions={'sanTrackLimits','sanTrackWarnings','sanCutPenalty','sanCutSeconds','sanJumpStart','sanPitSpeed','sanPitExit','sanProcedureKind','sanWrongWay','sanWrongWaySeconds',
  'sanServeLaps','sanStopGoSeconds','sanTimeSeconds','sanUnservedTime','sanGiveBack','sanGiveBackSeconds','sanMessages'}}
local function schemaOf(key) for _,s in ipairs(C.schema) do if s.key==key then return s end end end
tests.SCHEMA_142_KEYS=function()
 local fr,en=require('src/lang'),require('src/lang_en'); local tfr,ten=require('src/tips'),require('src/tips_en')
 local total=0
 for group,keys in pairs(newKeys) do
  local placed={}
  for _,entry in ipairs(Groups.sections[group]) do for _,k in ipairs(entry[2]) do placed[k]=(placed[k] or 0)+1 end end
  for _,key in ipairs(keys) do
   total=total+1
   local s=assert(schemaOf(key),'schema: '..key)
   assert(s.group==group,key..': group')
   assert(placed[key]==1,key..': exactly one subgroup')
   assert(type(en.labels[key])=='string' and en.labels[key]~='','EN label: '..key)
   assert(type(tfr.settings[key])=='string' and type(ten.settings[key])=='string','tips: '..key)
   for _,profile in ipairs(C.profiles) do
    local d=s.defaults[profile]
    if s.min then assert(type(d)=='number' and d>=s.min and d<=s.max,key..': default in range ('..profile..')')
    elseif s.choices then local ok=false; for _,c in ipairs(s.choices) do ok=ok or c==d end; assert(ok,key..': choice default')
    else assert(type(d)=='boolean',key..': boolean default') end
   end
  end
 end
 assert(total==41,'41 new settings')
 for _,group in ipairs({'strategy','sanctions'}) do
  assert(C.on(C.preset('Course','C',{}),group),'Course preset: '..group)
  for _,L in ipairs({fr,en}) do assert(L.groups[group] and L.categories[group] and L.sectionDescs[group],'section texts: '..group) end
  assert(tfr.tabs[group] and ten.tabs[group] and tfr.sections[group] and ten.sections[group],'section tips: '..group)
 end
 for _,id in ipairs({'overtakeAero','overtakeFinal','weatherOutLap','weatherWear','strategyPlan','strategyCharacter','strategyFailures','sanctionsTrack','sanctionsProcedure','sanctionsFlags','sanctionsServe','sanctionsDisplay'}) do
  assert(#fr.subgroups[id]==2 and #en.subgroups[id]==2,'subgroup texts: '..id)
 end
 for _,c in ipairs({'drive','stopgo','time'}) do assert(fr.choices[c] and en.choices[c],'choice: '..c) end
 for _,key in ipairs({'sanTrackWarnings','sanServeLaps','finalLaps'}) do assert(C.integerKeys[key],'integer: '..key) end
 assert(C.on(C.preset('Essais','P',{}),'sanctions') and C.on(C.preset('Qualifications','Q',{}),'sanctions'),'practice and qualifying presets: sanctions')
 assert(not C.on(C.preset('Essais','P',{}),'strategy') and not C.on(C.preset('Nordschleife','J',{}),'sanctions') and not C.on(C.preset('Nordschleife','J',{}),'strategy'),'no strategy outside the race, nothing in track day')
 -- Ni Hotlap ni défaut : sections décochées au départ (les préréglages les cochent).
 for _,profile in ipairs(C.profiles) do local d=C.defaults(profile); assert(not d.section_strategy and not d.section_sanctions,profile..': unticked by default') end
end
tests.SCHEMA_142_HIDDEN=function()
 for key in pairs(C.raceKeys) do
  assert(not C.hidden('C',key),key..': shown in the race')
  for _,profile in ipairs({'J','P','Q','H'}) do assert(C.hidden(profile,key),key..': hidden in '..profile) end
 end
 for key in pairs(C.sanctionKeys) do
  assert(C.hidden('J',key) and C.hidden('H',key) and not C.hidden('C',key),key..': weekend only')
  assert(C.hidden('P',key)==(C.sanctionRaceKeys[key]==true),key..': practice')
 end
 for _,key in ipairs({'sanTrackLimits','sanWrongWay','sanWrongWaySeconds','sanMessages'}) do assert(not C.hidden('Q',key),key..': shown in qualifying') end
 -- Air sale, tour de sortie, usure : tous les profils.
 for _,key in ipairs({'dirtyAirEnabled','outLapEnabled','lockWearEnabled'}) do assert(not C.hidden('J',key) and not C.hidden('Q',key),key) end
end
tests.SCHEMA_142_GATING=function()
 for _,profile in ipairs({'P','Q','C'}) do
  local p=C.preset(profile=='C' and 'Course' or profile=='P' and 'Essais' or 'Qualifications',profile,{})
  local run=C.effective(profile,p)
  if profile=='C' then assert(run.strategyEnabled and run.failuresEnabled and run.towBreakEnabled and run.finalLapsEnabled and run.sanCutPenalty and run.sanGiveBack,'race preset on') end
  assert(run.sanTrackLimits and run.sanWrongWay and run.dirtyAirEnabled and run.outLapEnabled and run.lockWearEnabled,profile..': on')
  p.section_overtake=false; p.section_weather=false; p.section_strategy=false; p.section_sanctions=false
  run=C.effective(profile,p)
  assert(not (run.towBreakEnabled or run.dirtyAirEnabled or run.finalLapsEnabled or run.outLapEnabled or run.lockWearEnabled or run.strategyEnabled or run.failuresEnabled),profile..': off')
  for _,key in ipairs(C.sanctionSwitches) do assert(run[key]==false,profile..': '..key) end
 end
 local j=C.effective('J',C.preset('Nordschleife','J',{}))
 assert(not (j.towBreakEnabled or j.dirtyAirEnabled or j.finalLapsEnabled or j.outLapEnabled or j.lockWearEnabled or j.strategyEnabled or j.sanTrackLimits),'track day: nothing new')
end
tests.SCHEMA_142_MIGRATION=function()
 local function profiles() local t={}; for _,profile in ipairs(C.profiles) do t[profile]=C.defaults(profile); t[profile].configured=true end; return t end
 local set=profiles(); for _,profile in ipairs({'P','Q','C'}) do set[profile].section_rules=true end
 set.J.section_rules=true
 local g=C.validateGlobals(C.globalDefaults); g.dataRevision=18; g.presetsUsed=true
 local upgraded=C.migrate(g,set)
 assert(set.C.section_strategy and set.C.section_sanctions and set.P.section_sanctions and set.Q.section_sanctions,'weekend profiles with racing rules get the new sections')
 assert(not set.P.section_strategy and not set.Q.section_strategy and not set.J.section_sanctions and not set.J.section_strategy,'no strategy in practice, nothing in track day')
 local listed={}; for _,u in ipairs(upgraded) do listed[u]=true end
 assert(listed['C:strategie et sanctions'] and listed['P:sanctions'] and listed['Q:sanctions'],'logged')
 assert(g.dataRevision==C.dataRevision)
 -- Règles décochées : rien n'est coché.
 local off=profiles(); g.dataRevision=18; C.migrate(g,off); assert(not off.C.section_strategy and not off.C.section_sanctions,'racing rules off: untouched')
 -- Préréglage personnel de la révision 13 (Beta 1.29 à 1.41) : même migration ; enregistré en révision 14.
 local store=Pr.layout(); store.name='Course 1.41'; store.profile='C'; store.revision=13
 for k,v in pairs(C.defaults('C')) do store['p_'..k]=v end
 store.p_section_rules=true; store.p_section_strategy=nil; store.p_section_sanctions=nil
 local entry=assert(Pr.decode(store)); assert(entry.p.section_strategy and entry.p.section_sanctions,'custom preset migrated')
 assert(Pr.encode(entry).revision==15)
end
tests.SCHEMA_142_NEUTRAL_HOOKS=function()
 local e,f=F.scene('C',4); e.commands[2].levelScale=0.5; e.commands[3].throttleLimit=0.2; F.tick(e,f,2)
 for i=1,f.count do local cmd=e.commands[i]; assert(cmd.levelScale==1 and cmd.throttleLimit==1 and cmd.wearId==0,'neutral command '..i) end
 assert(#e.strategy.rows==0 and #e.sanctions.rows==0,'no rows yet')
 assert(Strategy.serialize(e.strategy,f.session)=='' and Sanctions.serialize(e.sanctions,f.session)=='')
 f.sessionLaps=0; f.sessionMinutes=0; f.timedRace=false; F.tick(e,f,0.1)
 assert(e.race.progress==-1 and e.race.lapsLeft==-1 and not e.race.known,'unknown race length')
 f.sessionLaps=10; f.leaderLaps=7; F.tick(e,f,0.1)
 assert(e.race.lapsLeft==3 and e.race.known,'laps left from the session')
 f.sessionLaps=0; f.timedRace=true; f.sessionMinutes=60; f.left=1800; f.leaderLaps=10; F.tick(e,f,0.1)
 assert(math.abs(e.race.progress-0.5)<0.01 and e.race.lapsLeft==10,'timed race: laps left from the progress')
 local j,fj=F.scene('J',3); F.tick(j,fj,1); assert(j.race.progress==-1 and not j.race.known,'track day: no race progress')
end
tests.SCHEMA_142_APPLIER_INTERFACE=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C')
 local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false end
 local cmd=e.commands[2]; cmd.active=true; cmd.offset=0; cmd.levelOwned=true; cmd.aggressionOwned=false; cmd.cautionOwned=false; cmd.level=0.9; cmd.speedLimit=K.unlimitedSpeed
 -- Neutre : rien d'écrit pour l'accélérateur ; niveau du directeur tel quel.
 A.apply(a,f,e.commands,e.g,1); assert(host.throttleWrites==0 and math.abs(host.cars[1].aiLevel-0.9)<1e-9,'neutral')
 cmd.levelScale=0.9; A.apply(a,f,e.commands,e.g,2); assert(math.abs(host.cars[1].aiLevel-0.81)<1e-9,'level scaled')
 cmd.levelScale=0.2; A.apply(a,f,e.commands,e.g,3); assert(math.abs(host.cars[1].aiLevel-0.9*K.levelScaleMin)<1e-9,'scale bounded')
 cmd.levelScale=1; cmd.throttleLimit=0.5; A.apply(a,f,e.commands,e.g,4); assert(host.throttleLimits[1]==0.5 and host.throttleWrites==1,'throttle limited')
 A.apply(a,f,e.commands,e.g,5); assert(host.throttleWrites==1,'written once')
 cmd.throttleLimit=1; A.apply(a,f,e.commands,e.g,6); assert(host.throttleLimits[1]==1 and host.throttleWrites==2 and a.cars[2].throttle==nil,'given back once, forgotten')
 A.apply(a,f,e.commands,e.g,7); assert(host.throttleWrites==2,'nothing more')
 -- Rendu aussi aux stands et à la restitution.
 cmd.throttleLimit=0.4; A.apply(a,f,e.commands,e.g,8); f.cars[2].pit=true; A.apply(a,f,e.commands,e.g,9); assert(host.throttleLimits[1]==1,'pit lane: given back')
 f.cars[2].pit=false; A.apply(a,f,e.commands,e.g,10); assert(host.throttleLimits[1]==0.4)
 A.restore(a,f,false,11,true); assert(host.throttleLimits[1]==1 and a.cars[2].throttle==nil,'release: given back')
 -- Usure ajoutée à un pneu : une seule fois par événement.
 f.cars[2].tyreKm={10,20,30,40}; cmd.wearId=1; cmd.wearWheel=1; cmd.wearKm=1.5
 A.apply(a,f,e.commands,e.g,12); A.apply(a,f,e.commands,e.g,13)
 assert(#host.tyreKmWrites==1 and host.tyreKmWrites[1].wheel==1 and math.abs(host.tyreKmWrites[1].km-21.5)<1e-9,'one wear event')
end
tests.SCHEMA_142_SIDEBAR_FITS=function()
 -- 17 sections : la liste tient dans la fenêtre de 700 px (lignes resserrées), tous les onglets visibles.
 local sections=0; for _,group in ipairs(C.sections) do if group~='rules' then sections=sections+1 end end
 assert(sections==16 and #C.sections==17,'16 sidebar sections plus racing rules')
end
return tests
