-- Beta 1.52 (décision du pilote) : mise à jour de SpotterEnginer signalée à l'accueil d'AdvancedIA, jamais installée par
-- lui ; contrat v1 publié par SpotterEnginer dans ac.store. Chargé par tests/extended.lua.
local A=require('src/applier')
local C=require('src/config')
local K=C.K
local tests={}
tests.COMPANION_UPDATE_PARSE_152=function()
 local u=A.parseCompanionUpdate('v=1;installed=1.1.0;latest=1.2.0;state=available')
 assert(u and u.state=='available' and u.installed=='1.1.0' and u.latest=='1.2.0' and u.needs==nil,'available')
 u=A.parseCompanionUpdate('v=1;installed=1.1.0;latest=1.3.0;state=incompatible;needs=Beta 1.53;extra=x')
 assert(u and u.state=='incompatible' and u.needs=='Beta 1.53','incompatible, unknown field ignored')
 u=A.parseCompanionUpdate('v=1;installed=1.1.0;state=incompatible;needs=?'); assert(u and u.needs=='?','needs unknown')
 assert(A.parseCompanionUpdate(nil)==nil and A.parseCompanionUpdate('')==nil,'absent')
 assert(A.parseCompanionUpdate('v=2;installed=1.1.0;state=available')==nil,'other contract version')
 assert(A.parseCompanionUpdate('v=1;installed=1.1.0;state=installing')==nil,'unknown state')
 assert(A.parseCompanionUpdate('v=1;state=available;latest=1.2.0')==nil,'installed version required')
 assert(A.parseCompanionUpdate('v=1;installed=1.1.0;state=available;'..string.rep('x',K.companionUpdateBytes))==nil,'too long')
 u=A.parseCompanionUpdate('v=1;installed=1.1.0;latest=<b>;state=available'); assert(u and u.latest==nil,'bad version dropped')
end
tests.COMPANION_WINDOW_OPEN_152=function()
 local saved=ac.accessAppWindow
 local shown=nil
 ac.accessAppWindow=function(name) if name=='IMGUI_LUA_SpotterEnginer_main' then return {setVisible=function(_,value) shown=value end} end return nil end
 local ok1=A.openCompanion('IMGUI_LUA_SpotterEnginer_main')
 local ok2=A.openCompanion('IMGUI_LUA_Other_main')
 ac.accessAppWindow=nil
 local ok3=A.openCompanion('IMGUI_LUA_SpotterEnginer_main')
 ac.accessAppWindow=saved
 assert(ok1==true and shown==true,'window shown')
 assert(ok2==false and ok3==false,'missing window or API: false, no error')
end
return tests
