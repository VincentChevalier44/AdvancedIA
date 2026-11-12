-- Beta 1.62 (choix du pilote, 12 novembre) : options pertinentes dans chaque préréglage intégré, onglet coché.
-- Noms terminés par _162P. Chargé par tests/extended.lua.
local C=require('src/config')
local tests={}

local all={'fineInputs','dynamicPersona','wearPace','rearAwareness','weatherLive'}
local matrix={
 {'Nordschleife','J',{},{'damagePit','qualiRuns','classNuance','passAid','strategyStartVariety'}},
 {'Circuit','J',{},{'damagePit','qualiRuns','classNuance','passAid','strategyStartVariety'}},
 {'Essais','P',{'damagePit','qualiRuns'},{'passAid','strategyStartVariety','classNuance'}},
 {'Qualifications','Q',{'damagePit','qualiRuns'},{'passAid','strategyStartVariety','classNuance'}},
 {'Course','C',{'damagePit','strategyStartVariety','passAid','strategySmart','startRealism','sanContact'},{'qualiRuns','classNuance'}},
 {'Endurance','C',{'damagePit','strategyStartVariety','passAid','strategySmart','classNuance'},{'qualiRuns'}},
}
tests.PRESETS_RELEVANT_OPTIONS_162P=function()
 for _,row in ipairs(matrix) do
  local name,profile,on,off=row[1],row[2],row[3],row[4]
  local p=C.preset(name,profile,{})
  for _,key in ipairs(all) do assert(p[key]==true,name..' '..key) end
  for _,key in ipairs(on) do assert(p[key]==true,name..' '..key) end
  for _,key in ipairs(off) do assert(p[key]~=true,name..' must not enable '..key) end
  -- jamais imposés
  assert(p.trackMemory~=true and p.sanPlayerContact~=true,name..' player choices')
  assert(p.raceStart==nil or p.raceStart=='standing',name..' raceStart')
 end
end
-- Chaque option active a son onglet coché, sinon elle serait coupée sans le dire.
tests.PRESET_OPTIONS_SECTIONS_TICKED_162P=function()
 local section={fineInputs='human',dynamicPersona='human',rearAwareness='lateral',wearPace='weather',weatherLive='weather',
  damagePit='accidents',qualiRuns='yield',strategyStartVariety='strategy',strategySmart='strategy',passAid='overtake',classNuance='blue'}
 for _,row in ipairs(matrix) do
  local p=C.preset(row[1],row[2],{})
  for key,group in pairs(section) do
   if p[key]==true then assert(p['section_'..group]==true,row[1]..' '..key..' needs section '..group) end
  end
 end
end
return tests
