-- 2.0.5 b (journal d'un joueur du 18 novembre, Beta 2.0.4 : « sens lateral: 1 / -1 » enregistré, les deux files du
-- départ rangées du mauvais côté, accrochages « sur le cote » à chacun des quatre départs ; décision du pilote du
-- 18 novembre : « corriger et réparer ») : sens latéral enregistré à l'envers réparé à la mise à jour, mesure contraire
-- à la convention d'AC retenue seulement après K.signConfirm mesures identiques de suite, déplacement minimal de
-- 0,5 m. Noms terminés par _205. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local Calibration=require('src/calibration')
local Caps=require('src/caps')
local J=require('src/journal')
local K=C.K
local tests={}
local function profiles() local out={}; for _,x in ipairs(C.profiles) do out[x]=C.validate(x,C.defaults(x)) end; return out end
-- Globales complètes (la mesure lit aussi les marges d'occupation), sens donné.
local function globals(offset,side,provisional)
 local g=C.validateGlobals({schemaVersion=3,dataRevision=24,presetsUsed=true,offsetSign=offset,sideSign=side}); g.signProvisional=provisional==true; return g
end

tests.K_205B=function()
 assert(K.signOffset==-1 and K.signSide==-1 and K.signConfirm==3 and K.calibrationMinMove==0.5 and C.dataRevision==24)
end

-- Installation existante dont le sens enregistré n'est pas la convention d'AC : remis à -1 / -1 provisoire à la mise à
-- jour, une seule fois, et dit au journal ; un sens conforme n'est pas touché.
tests.LOCK_SIGN_REPAIR_205=function()
 local g=C.validateGlobals({schemaVersion=3,dataRevision=23,presetsUsed=true,offsetSign=1,sideSign=-1})
 assert(g.offsetSign==1 and g.sideSign==-1 and g.dataRevision==23,'the player\'s stored sign')
 local _,fresh,restored,provisional,repaired=C.migrate(g,profiles())
 assert(repaired=='1 / -1','repaired, with what was stored: '..tostring(repaired))
 assert(g.offsetSign==-1 and g.sideSign==-1 and g.signProvisional==true and g.dataRevision==24,'back to -1 / -1, provisional (still measured)')
 assert(not fresh and not restored and not provisional,'neither a fresh install nor the old restore')
 local saved=C.validateGlobals(g); assert(saved.offsetSign==-1 and saved.sideSign==-1 and saved.signProvisional==true,'kept when saved')
 assert(C.migrate(g,profiles())==nil,'only once')
 for _,pair in ipairs({{1,1},{-1,1},{1,0},{0,1},{-1,0}}) do
  local w=C.validateGlobals({schemaVersion=3,dataRevision=23,presetsUsed=true,offsetSign=pair[1],sideSign=pair[2]})
  local _,_,_,_,r=C.migrate(w,profiles())
  assert(r==pair[1]..' / '..pair[2] and w.offsetSign==-1 and w.sideSign==-1 and w.signProvisional==true,'stored '..pair[1]..' / '..pair[2]..': repaired')
 end
 local ok=C.validateGlobals({schemaVersion=3,dataRevision=23,presetsUsed=true,offsetSign=-1,sideSign=-1})
 local _,_,_,_,none=C.migrate(ok,profiles())
 assert(none==nil and ok.offsetSign==-1 and ok.sideSign==-1 and ok.signProvisional==false,'the convention, already measured: untouched')
 -- Lignes du journal reconnues par la traduction.
 local text,rule=J.english('sens lateral repare: -1 / -1 (enregistre 1 / -1 ; convention d AC, la mesure le confirmera)',true)
 assert(rule and text:find('repaired',1,true),'repair line translated: '..tostring(text))
 text,rule=J.english('sens lateral: mesure contraire a la convention d AC (1 / -1), 1 sur 3, non retenue',true)
 assert(rule and text:find('not kept',1,true),'refused measurement line translated: '..tostring(text))
end

-- Une mesure : voiture 2 seule, repère 120 m devant ; elle se déplace de dx m (dx > 0 : sens +1), côté lu side.
local function measure(c,f,cap,g,t0,dx,side)
 F.place(f,1,-1000,100); F.place(f,2,0,100); F.place(f,3,120,100)
 for i=1,3 do f.cars[i].sideDot=side or -1 end
 Calibration.step(c,f,cap,g,t0); assert(c.index==2,'measurement started on the lone car (phase '..tostring(c.phase)..')')
 f.cars[2].x=dx
 Calibration.step(c,f,cap,g,t0+3.1)
 local refused,count=c.refused,c.refusedCount; c.refused=nil
 return refused,count
end
local function bench()
 local _,f=F.scene('J',3)
 local cap=Caps.new({present=function() return true end,write=function() return true end})
 return f,cap,Calibration.new()
end

-- Mesure contraire à la convention d'AC : refusée deux fois (sens gardé, toujours provisoire), retenue à la troisième
-- identique de suite ; une mesure conforme confirme aussitôt et remet le compte à zéro ; un déplacement de moins de
-- 0,5 m ne conclut rien ; sens encore inconnu : retenue aussitôt, comme avant.
tests.LOCK_SIGN_CONFIRM_205=function()
 local f,cap,c=bench(); local g=globals(-1,-1,true)
 local refused,count=measure(c,f,cap,g,0,0.6)
 assert(refused=='1 / -1' and count==1 and g.offsetSign==-1 and g.sideSign==-1 and g.signProvisional==true and c.phase=='inconclusive','first contrary measurement: not kept ('..tostring(refused)..', '..g.offsetSign..')')
 refused,count=measure(c,f,cap,g,70,0.6)
 assert(refused=='1 / -1' and count==2 and g.offsetSign==-1 and g.signProvisional==true,'second: still not kept')
 refused=measure(c,f,cap,g,140,0.6)
 assert(refused==nil and g.offsetSign==1 and g.sideSign==-1 and g.signProvisional==false and c.phase=='ready','third identical in a row: kept ('..g.offsetSign..' / '..g.sideSign..')')
 -- Sens contraire retenu : le compte repart de zéro (nouvelle mesure demandée depuis la convention : encore trois).
 assert((c.contra or 0)==0,'count reset once a direction is kept: '..tostring(c.contra))
 g.offsetSign=-1; g.sideSign=-1; g.signProvisional=true; c.attempted=false; c.phase='waiting'
 refused,count=measure(c,f,cap,g,300,0.6); assert(refused=='1 / -1' and count==1 and g.offsetSign==-1,'three again after a kept direction: '..tostring(count))
 -- Deux mesures contraires différentes ne s'additionnent pas.
 f,cap,c=bench(); g=globals(-1,-1,true)
 measure(c,f,cap,g,0,0.6); refused,count=measure(c,f,cap,g,70,0.6,1)
 assert(refused=='1 / 1' and count==1,'a different contrary measurement starts its own count: '..tostring(refused)..' '..tostring(count))
 refused,count=measure(c,f,cap,g,140,0.6,1); assert(count==2 and g.offsetSign==-1,'still not kept')
 -- Mesure conforme : confirmée aussitôt, compte remis à zéro (nouvelle mesure demandée ensuite : encore trois).
 f,cap,c=bench(); g=globals(-1,-1,true)
 measure(c,f,cap,g,0,0.6); refused=measure(c,f,cap,g,70,-0.6)
 assert(refused==nil and g.offsetSign==-1 and g.sideSign==-1 and g.signProvisional==false and c.confirmed==true,'the convention measured: confirmed at once')
 g.signProvisional=true; c.attempted=false; c.phase='waiting'
 measure(c,f,cap,g,200,0.6); refused,count=measure(c,f,cap,g,270,0.6)
 assert(count==2 and g.offsetSign==-1 and g.signProvisional==true,'count restarted after a matching measurement: '..tostring(count))
 -- Petit déplacement (écart naturel entre deux voitures) : rien de conclu.
 f,cap,c=bench(); g=globals(-1,-1,true)
 refused=measure(c,f,cap,g,0,0.3)
 assert(refused==nil and c.phase=='inconclusive' and (c.contra or 0)==0 and g.offsetSign==-1 and g.signProvisional==true,'0.3 m: inconclusive, not counted')
 -- Sens inconnu (0 / 0) : première mesure retenue.
 f,cap,c=bench(); g=globals(0,0,false)
 refused=measure(c,f,cap,g,0,0.6,1)
 assert(refused==nil and g.offsetSign==1 and g.sideSign==1 and c.phase=='ready','unknown sign: first measurement kept as before')
end
return tests
