-- Beta 1.60 (étape de base) : les neuf réglages (déclarés, coupés, masqués tant que leur tranche manque), l'état de
-- priorité partagé (src/priority.lua), les modules vides et leurs appels, le bus des modificateurs du directeur.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local P=require('src/priority')
local G=require('src/groups')
local K=C.K
local tests={}
local keys={'fineInputs','dynamicPersona','rearAwareness','passAid','wearPace','strategySmart','raceStart','sanContact','sanPlayerContact'}
tests.SETTINGS_DECLARED_OFF_160=function()
 local byKey={}; for _,s in ipairs(C.schema) do byKey[s.key]=s end
 for _,key in ipairs(keys) do
  local s=assert(byKey[key],key); assert(C.isNewKey(key),key..': new key')
  for _,profile in ipairs(C.profiles) do
   local d=s.defaults[profile]
   if key=='raceStart' then assert(d=='standing',key..' '..profile) else assert(d==false,key..' '..profile) end
  end
 end
 assert(#byKey.raceStart.choices==3 and byKey.raceStart.choices[2]=='formation' and byKey.raceStart.choices[3]=='rolling','choices')
 -- Aucun jeu de règles ne les règle.
 for _,key in ipairs(keys) do
  for name,preset in pairs(C.rulePresets or {}) do if type(preset)=='table' then assert(preset[key]==nil,key..' in rule set '..tostring(name)) end end
 end
end
tests.SETTINGS_VISIBILITY_160=function()
 -- Visibilité prévue de chaque réglage (C.hidden), que sa tranche soit livrée ou non.
 local saved={}; for key in pairs(C.pendingKeys) do saved[key]=true end
 for key in pairs(saved) do C.pendingKeys[key]=nil end
 local ok,err=pcall(function()
  for _,key in ipairs({'fineInputs','dynamicPersona','rearAwareness','passAid','wearPace'}) do
   for _,profile in ipairs(C.profiles) do assert(not C.hidden(profile,key),key..' shown in '..profile) end
  end
  for _,key in ipairs({'strategySmart','raceStart','sanPlayerContact'}) do
   assert(not C.hidden('C',key),key..' shown in the race')
   for _,profile in ipairs({'J','P','Q','H'}) do assert(C.hidden(profile,key),key..' hidden in '..profile) end
  end
  assert(not C.hidden('P','sanContact') and not C.hidden('Q','sanContact') and not C.hidden('C','sanContact'),'AI blame: weekend')
  assert(C.hidden('J','sanContact') and C.hidden('H','sanContact'),'AI blame: hidden on a track day and in hotlap')
  -- Section décochée : réglage coupé ; section cochée : valeur du pilote.
  local p=C.defaults('C')
  for _,g in ipairs(C.sections) do p['section_'..g]=true end
  for _,key in ipairs(keys) do p[key]=key=='raceStart' and 'rolling' or true end
  local out=C.effective('C',p)
  for _,key in ipairs(keys) do assert(out[key]==p[key],key..' kept') end
  local pairsOff={{'human','fineInputs'},{'human','dynamicPersona'},{'lateral','rearAwareness'},{'overtake','passAid'},{'weather','wearPace'},{'strategy','strategySmart'},{'sanctions','sanContact'},{'sanctions','sanPlayerContact'}}
  for _,pair in ipairs(pairsOff) do
   p['section_'..pair[1]]=false; out=C.effective('C',p); assert(out[pair[2]]==false,pair[2]..' off with its section'); p['section_'..pair[1]]=true
  end
  p.section_start=false; out=C.effective('C',p); assert(out.raceStart=='standing','standing start with the Start section off')
 end)
 for key in pairs(saved) do C.pendingKeys[key]=true end
 assert(ok,err)
end
tests.SETTINGS_PENDING_HIDDEN_160=function()
 -- Tranche non livrée : réglage masqué partout et tenu à sa valeur par défaut, même allumé dans un fichier de réglages.
 local p=C.defaults('C')
 for _,g in ipairs(C.sections) do p['section_'..g]=true end
 for _,key in ipairs(keys) do p[key]=key=='raceStart' and 'rolling' or true end
 local out=C.effective('C',p)
 for _,key in ipairs(keys) do
  if C.pendingKeys[key] then
   assert(G.hidden[key],key..' never shown')
   assert(out[key]==(key=='raceStart' and 'standing' or false),key..' held at its default')
  else assert(not G.hidden[key] and out[key]==p[key],key..' live') end
 end
end
tests.PRIORITY_NOSE_160=function()
 local a,b={length=4.6},{length=5.0}
 assert(math.abs(P.nose(a,b,1.0)-1.2)<1e-9 and math.abs(P.nose(b,a,-1.0)+1.2)<1e-9,'nose advance, antisymmetric')
 assert(P.behind(a,b,K.cornerNoseMargin) and not P.behind(a,b,K.cornerNoseMargin-0.2-1e-6),'margin, longer car ahead')
 assert(not P.behind(b,a,K.cornerNoseMargin+0.1) and P.behind(b,a,K.cornerNoseMargin+0.3),'margin, shorter car ahead')
end
tests.PRIORITY_CORNER_CONTEXT_160=function()
 local p={cornerMin=0.5}
 assert(P.cornerContext({corner=0.4},p,0) and not P.cornerContext({corner=0.5},p,0),'corner')
 assert(P.cornerContext({corner=1},p,K.passBrakeMax) and not P.cornerContext({corner=1},p,K.passBrakeMax-0.01) and not P.cornerContext({corner=1},p,nil),'real braking only')
end
tests.PRIORITY_COMMIT_160=function()
 local e={states={{},{},{}}}
 assert(not P.committed(e.states[1]) and P.held(e.states[2],0)==0,'neutral without fields')
 P.commit(e,1,2,-1,10); P.commit(e,1,2,-1,12)
 assert(P.committed(e.states[1]) and P.committed(e.states[1],2) and not P.committed(e.states[1],3),'committed to car 2')
 assert(e.states[1].commitAt==10 and e.states[1].commitSide==-1,'sticky for the attempt')
 P.hold(e,2,1,15)
 assert(P.held(e.states[2],14)==1 and P.held(e.states[2],15)==0,'held until the time')
 P.rebase(e.states[1],4); P.rebase(e.states[2],4)
 assert(e.states[1].commitAt==6 and P.held(e.states[2],10.5)==1 and P.held(e.states[2],11)==0,'clock rebase')
 P.commit(e,1,3,1,20); assert(e.states[1].committed==3 and e.states[1].commitAt==20,'new target, new time')
 P.commit(e,1,2,1,21); P.release(e,1)
 assert(not P.committed(e.states[1]) and P.held(e.states[2],9)==0,'release frees the defender')
 P.rebase(e.states[3],1)
end
tests.MODULE_HOOKS_160=function()
 -- Chaque module est créé, appelé à chaque image dans l'ordre prévu, recalé et remis à zéro avec la session.
 local names={rear={'update','govern'},blame={'sample','settle'},mood={'update','exit'},wear={'update'},pitloss={'update'},formation={'step'}}
 local e,f=F.scene('C',4)
 local order,saved={},{}
 for name,entries in pairs(names) do
  assert(type(e[name])=='table',name..': state created')
  local module=require('src/'..name)
  for _,entry in ipairs(entries) do
   local key=name..'.'..entry; saved[key]=module[entry]
   module[entry]=function(t,...) assert(t==e[name],key..': its state'); order[#order+1]=key; return saved[key](t,...) end
  end
 end
 local ok,err=pcall(function()
  F.tick(e,f,1/30,true)
  local at={}; for k,key in ipairs(order) do at[key]=at[key] or k end
  for key in pairs(saved) do assert(at[key],key..': called') end
  local sequence={'formation.step','mood.update','rear.update','mood.exit','wear.update','pitloss.update','blame.sample','blame.settle','rear.govern'}
  for k=2,#sequence do assert(at[sequence[k-1]] < at[sequence[k]],sequence[k-1]..' before '..sequence[k]) end
  assert(order[#order]=='rear.govern','governor last')
 end)
 for name,entries in pairs(names) do local module=require('src/'..name); for _,entry in ipairs(entries) do module[entry]=saved[name..'.'..entry] end end
 assert(ok,err)
 E.rebase(e,5)
end
tests.MODIFIER_BUS_NEUTRAL_160=function()
 -- Champs du bus absents ou à 1 : mêmes commandes, au bit près ; champs actifs : agressivité et prudence suivent.
 local function run(set)
  local e,f=F.scene('J',4); F.place(f,2,0,150); F.place(f,3,400,150); F.place(f,4,800,150)
  for _=1,60 do
   if set then for i=2,4 do set(e.states[i]) end end
   F.tick(e,f,1/30,true)
  end
  return e.commands[2].aggression,e.commands[2].caution,e.commands[2].level
 end
 local a0,c0,l0=run(nil)
 local a1,c1,l1=run(function(s) s.moodAggr=1; s.moodCaution=1; s.moodFatigue=1; s.wearBrake=1 end)
 assert(a0==a1 and c0==c1 and l0==l1,'neutral values change nothing')
 local a2,c2=run(function(s) s.moodAggr=0.5; s.moodCaution=1.5 end)
 assert(a2 < a0 and c2 > c0,'mood reaches the commands: '..a0..' '..a2..' '..c0..' '..c2)
end
return tests
