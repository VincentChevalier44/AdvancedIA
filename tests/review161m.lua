-- Beta 1.61 (fusion des tranches) : tests des raccords faits à la fusion. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local A=require('src/applier')
local J=require('src/journal')
local tests={}
-- Zandvoort, 11 novembre : « pneus adaptes a la meteo aux stands » écrit cinq fois en 25 s pour la même voiture, tant
-- que la gomme montée n'avait pas changé. La consigne reste redonnée, la ligne n'est écrite qu'une fois par passage
-- aux stands et par gomme demandée ; un nouveau passage, ou une autre gomme, redonne une ligne.
tests.WEATHER_LANE_LINE_ONCE_161M=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C'); local a=A.new(); assert(A.access(a))
 host.tyreCatalog[2]={{short='M',name='Medium'},{short='W',name='Wet'},{short='H',name='Hard'}}
 local lines=0; a.note=function(_,text) if text:find('pneus adaptes a la meteo',1,true) then lines=lines+1 end end
 for _,cmd in ipairs(e.commands) do cmd.active=false; cmd.weatherManaged=false end
 local cmd=e.commands[3]; cmd.weatherManaged=true; cmd.weatherRain=true; cmd.weatherCompound=1; cmd.weatherGrid=false
 local car=f.cars[3]; car.pit=true; car.inPitBox=true; car.kmh=0; car.tyresKnown=true; car.compoundIndex=0
 host.cars[2].isInPit=true; host.cars[2].isInPitlane=true; host.cars[2].speedKmh=0; host.cars[2].compoundIndex=0
 -- La gomme lue par l'app ne change pas pendant l'arrêt (AC ne la monte qu'au départ de l'emplacement).
 for step=0,4 do A.apply(a,f,e.commands,e.g,1+step*6); car.compoundIndex=0 end
 assert(lines==1,'one line for the whole pit-lane pass, got '..lines)
 assert(a.cars[3].tyreAt>1+4*6,'the tyre order is still given again while the fitted compound has not changed')
 -- Autre gomme demandée pendant le même passage : une ligne de plus.
 cmd.weatherCompound=2; A.apply(a,f,e.commands,e.g,40); car.compoundIndex=0
 assert(lines==2,'a new target compound is noted, got '..lines)
 -- Sortie des stands puis nouveau passage : une ligne de nouveau.
 car.pit=false; car.inPitBox=false; car.kmh=120; cmd.weatherCompound=-1; A.apply(a,f,e.commands,e.g,50)
 car.pit=true; car.inPitBox=true; car.kmh=0; cmd.weatherCompound=2; A.apply(a,f,e.commands,e.g,60)
 assert(lines==3,'a new pit-lane pass is noted again, got '..lines)
end
-- Résumé de la minute : zones, mémoire du circuit et météo en direct écrits seulement s'il y a lieu ; les compteurs de
-- la minute (attaques attendues, lignes alternatives, anticipations, paris) repartent de zéro.
tests.MINUTE_SUMMARY_SLICES_161M=function()
 local e=F.scene('C',4)
 -- Compteurs de la météo déjà remplis mais réglage coupé : rien d'écrit.
 e.wx.stats.count=4; e.wx.stats.grip=3
 local text=J.summary(e)
 assert(not text:find('zones :',1,true) and not text:find('memoire :',1,true) and not text:find('meteo en direct',1,true),'nothing with the switches off')
 e.zonelearn.held=2; e.zonelearn.lines=1; e.zonelearn.learntCount=3
 e.pacemap.used=5
 e.run.weatherLive=true; e.wx.live=true; local n=e.wx.stats; n.count=4; n.grip=3; n.early=2; n.gamble=1; n.wrong=1
 text=J.summary(e)
 assert(text:find('zones : attaques attendues 2, lignes alternatives 1, zones apprises 3, oubliees 0',1,true),text)
 assert(text:find('memoire : allure d avant utilisee par 5 voiture(s)',1,true),text)
 assert(text:find('meteo en direct : adherence moyenne 75 %, arrets anticipes 2, paris 1, en mauvais pneus 1',1,true),text)
 assert(e.zonelearn.held==0 and e.zonelearn.lines==0 and n.early==0 and n.gamble==0,'minute counters set back to zero')
 text=J.summary(e)
 assert(not text:find('zones :',1,true),'zones part not repeated with nothing new')
 assert(text:find('arrets anticipes 0, paris 0',1,true),'live weather part keeps the state, counters at zero')
end
return tests
