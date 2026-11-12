-- Beta 1.62, relecture d'ensemble (audit AUDIT_ENSEMBLE.md) : résumé de la minute (compteurs masqués ou absents),
-- côté de dépassement « opposé » avec une cession automatique, réglages sans effet masqués, préréglage Circuit.
-- Noms terminés par _162H. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local D=require('src/director')
local J=require('src/journal')
local L=require('src/lang')
local LE=require('src/lang_en')
local tests={}

local function find(text,pattern) return text:find(pattern,1,true)~=nil end

-- Résumé : le compteur « côté occupé » des départs refusés ne masque plus celui de la conscience de l'arrière ; les fins
-- de dépassement par priorité au virage ou maintien trop long entrent dans « annulés » (tentés = réussis + annulés).
tests.SUMMARY_COUNTERS_162H=function()
 local e=F.scene('C',4)
 e.stats.pass=4; e.stats.clear=1; e.stats.abort_slow=1; e.stats.pass_corner_priority=1; e.stats.pass_hold_limit=1
 e.stats.rearSide=3; e.stats.refSide=7; e.stats.refRoom=1
 e.stats.passAwaySide=2; e.stats.passSideRoom=5; e.stats.nuanceHold=6; e.stats.bluePlayer=8
 e.stats.rearGoverned=1; e.stats.rearGovBrake=1
 local s=J.summary(e)
 assert(find(s,'depassements tentes 4, reussis 1, annules 3'),'tried = succeeded + cancelled: '..s)
 assert(find(s,'priorite au virage 1, maintien trop long 1'),'corner priority and hold limit published')
 assert(find(s,'lignes gardees 3,'),'rear awareness shows rearSide, not refSide')
 assert(find(s,'cote occupe 7,'),'refused starts keep refSide')
 assert(find(s,'a l oppose de la cession 2, vers la place 5'),'side changes published')
 assert(find(s,'attaques retenues par la nuance 6') and find(s,'drapeaux bleus au joueur 8'),'nuance counters published')
 assert(find(s,'frein radar 1,'),'governor detail published')
 local en=J.english(s)
 assert(not en:find('cote occupe',1,true) and en:find('corner priority 1',1,true),'English summary translated: '..en)
end
-- Une cession ou une défense finie par « hold_limit » ou « corner_priority » n'est pas un dépassement annulé.
tests.YIELD_HOLD_NOT_A_PASS_ABORT_162H=function()
 local e,f=F.scene('P',3); F.tick(e,f,1/60)
 local s=e.states[2]; e.stats.pass_hold_limit=nil; e.stats.pass_corner_priority=nil
 s.state='YIELD_HOLD'; D.transitionTest(e,s,'YIELD_OUT','hold_limit',e.time)
 s.state='DEFEND'; D.transitionTest(e,s,'DRIVE','corner_priority',e.time)
 assert(not e.stats.pass_hold_limit and not e.stats.pass_corner_priority,'not counted as pass aborts')
 s.state='OVT_HOLD'; D.transitionTest(e,s,'OVT_OUT','hold_limit',e.time)
 s.state='OVT_IN'; D.transitionTest(e,s,'OVT_OUT','corner_priority',e.time)
 assert(e.stats.pass_hold_limit==1 and e.stats.pass_corner_priority==1,'pass aborts counted')
end
-- Côté de dépassement « opposé » avec une cession automatique ou « garder sa ligne » : règle automatique (plus de
-- dépassement toujours à gauche) ; avec un côté de cession fixe, toujours l'opposé.
tests.OPPOSITE_WITH_AUTO_YIELD_162H=function()
 local e,f=F.scene('P',3); F.tick(e,f,1/60)
 local p=e.run; local s=e.states[2]; local g={offsetSign=-1,sideSign=-1}
 local row={front=0,back=0,neighbors={},left=false,right=false}
 p.overtakeSide='opposite'
 p.yieldSide='right'; local fixed=D.passSideTest(p,'P',s,{lat=1,index=3,gap=12,sa=10},row,f.cars[3],g,f.cars[2])
 p.yieldSide='left'; local fixedL=D.passSideTest(p,'P',s,{lat=1,index=3,gap=12,sa=10},row,f.cars[3],g,f.cars[2])
 assert(fixed==-fixedL,'fixed yield side: always the opposite')
 p.yieldSide='auto'
 local a1=D.passSideTest(p,'P',s,{lat=1,index=3,gap=12,sa=10},row,f.cars[3],g,f.cars[2])
 local a2=D.passSideTest(p,'P',s,{lat=-1,index=3,gap=12,sa=10},row,f.cars[3],g,f.cars[2])
 assert(a1==1 and a2==-1,'auto yield: side follows the target, not always left ('..a1..', '..a2..')')
end
-- Réglages affichés sans effet : départ et premier tour hors course, espacement hors journée circuit, cession ordinaire
-- et pression en course. Masqués dans l'interface seulement : la valeur enregistrée n'est jamais remise à son défaut.
tests.HIDDEN_WITHOUT_EFFECT_162H=function()
 for _,key in ipairs({'startDelay','startCautionMult','startAggrMult','startRelax','startLaneHold','firstLapCare'}) do
  assert(C.uiHidden('P',key) and C.uiHidden('J',key) and not C.uiHidden('C',key) and not C.hidden('P',key),key)
 end
 for _,key in ipairs({'trafficGapSeconds','trafficDensityGain','trafficVariation','trafficMaxReduction'}) do
  assert(C.uiHidden('C',key) and C.uiHidden('P',key) and not C.uiHidden('J',key) and not C.hidden('C',key),key)
 end
 for _,key in ipairs({'yieldEnabled','pressureEnabled','pressureGap','pressureTime'}) do
  assert(C.uiHidden('C',key) and not C.uiHidden('P',key) and not C.uiHidden('J',key) and not C.hidden('C',key),key)
 end
end
-- Préréglage Circuit : le plus lent garde sa ligne, donc pas de biais de ligne ; textes au singulier.
tests.CIRCUIT_NO_LANE_BIAS_AND_SINGULAR_162H=function()
 local p=C.preset('Circuit','J')
 assert(p.yieldSide=='line' and p.laneBiasEnabled==false,'Circuit: keep line, no lane bias')
 assert(L.headerCarsOne and LE.headerCarsOne and L.warningsCountOne and LE.safetyMoreOne,'singular variants')
 assert(string.format(L.headerCarsOne,1)=='1 IA pilotée' and string.format(LE.warningsCountOne,1)=='1 item','singular texts')
 assert(L.reasons.corner_priority and LE.reasons.held_line and LE.reasons.abort_timeout,'reason labels')
end
return tests
