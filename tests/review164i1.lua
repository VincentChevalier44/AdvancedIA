-- Affinage 1.64 i1 (décision du pilote du 14 novembre) : fenêtre d'AdvancedIA ouvrable en jeu depuis la barre des apps
-- d'AC. Fermée par défaut hors des menus, jamais refermée par l'app en jeu ; ouverte seule dans les menus pause/setup et
-- refermée à leur sortie sauf si le joueur l'avait ouverte en jeu. Noms LOCK_*_164 (tests/LOCKS.md). Chargé par
-- tests/extended.lua.
local A=require('src/applier')
local H=require('tests/host')
local C=require('src/config')
local tests={}

tests.LOCK_INGAME_WINDOW_164=function()
 local host=H.create(true); local a=A.new()
 host.windowOpen.main=true
 A.menu(a,false,0); assert(not host.windowOpen.main,'closed by default outside the menus (restored open by CSP)')
 host.windowOpen.main=true
 for k=1,600 do A.menu(a,false,k/60) end
 assert(host.windowOpen.main and A.windowOpenInGame()==true,'opened by the player in game: never closed by the app')
 A.menu(a,true,11); assert(host.windowOpen.main,'still open in the menu')
 A.menu(a,false,12); assert(host.windowOpen.main,'opened in game before the menu: kept open at menu exit')
 host.windowOpen.main=false; A.menu(a,false,13); assert(A.windowOpenInGame()==false,'closed by the player: nothing drawn')
 A.menu(a,true,14); assert(host.windowOpen.main,'auto-open in the menus')
 A.menu(a,false,15); assert(not host.windowOpen.main,'auto-opened: closed at menu exit')
 local isOpen=ac.isWindowOpen; ac.isWindowOpen=nil
 assert(A.windowOpenInGame()==false,'no CSP function: never drawn in game'); ac.isWindowOpen=isOpen
end
-- Réglages lus au lancement de la séance : grisés dans la fenêtre ouverte en jeu.
tests.INGAME_NEXT_SESSION_KEYS_164I1=function()
 for _,key in ipairs({'raceStart','startRealism','strategyStartVariety','spawnMode'}) do assert(C.nextSessionKeys[key],key) end
 local known={}; for _,s in ipairs(C.schema) do known[s.key]=true end
 for key in pairs(C.nextSessionKeys) do assert(known[key],'unknown key '..key) end
 assert(not C.nextSessionKeys.levelPct,'live settings stay live')
end
return tests
