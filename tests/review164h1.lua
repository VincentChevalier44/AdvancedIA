-- Beta 1.64 (demande du pilote du 14 novembre) : overlay réglable par bureau d'applications d'AC (src/desktops.lua).
local C=require('src/config')
local Desk=require('src/desktops')
local tests={}
-- Bureau lu (0 à 3 dans AC) : 1 à 4 ; absent, illisible ou hors plage : inconnu (overlay affiché partout, comme avant).
tests.LOCK_OVERLAY_DESKTOPS_164=function()
 assert(Desk.current(0)==1 and Desk.current(3)==4 and Desk.current(2.0)==3,'desktops 0..3 -> 1..4')
 assert(Desk.current(nil)==nil and Desk.current(4)==nil and Desk.current(-1)==nil and Desk.current(1.5)==nil and Desk.current('x')==nil and Desk.current({})==nil,'unknown desktop')
 local g={}; for k,v in pairs(C.globalDefaults) do g[k]=v end
 for n=1,4 do assert(C.globalDefaults[Desk.keys[n]]==true and Desk.visible(g,n),'shown on every desktop by default') end
 g.overlayDesk2=false
 assert(Desk.visible(g,1) and not Desk.visible(g,2) and Desk.visible(g,3) and Desk.visible(g,4),'desktop 2 only hidden')
 assert(Desk.visible(g,nil),'unknown desktop: shown')
 -- Réglage global gardé et validé (une valeur d'un autre type revient au défaut).
 local saved={}; for k,v in pairs(g) do saved[k]=v end
 local back=C.validateGlobals(saved); assert(back.overlayDesk2==false and back.overlayDesk1==true,'saved and restored')
 saved.overlayDesk3='no'; back=C.validateGlobals(saved); assert(back.overlayDesk3==true,'bad value: default')
 assert(Desk.text({language='fr'},'label')=='Bureau %d' and Desk.text({language='en'},'label')=='Desktop %d','texts FR/EN')
end
return tests
