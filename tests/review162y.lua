-- Beta 1.62, dernier lot : marge des limites de LuaJIT, drapeaux bleus (journal et vetos), attente du joueur sur la
-- grille, priorité dans la voie des stands, compteurs par épisode, fins de dépassement « autre ».
-- Noms terminés par _162Y. Chargé par tests/extended.lua.
local tests={}

local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local J=require('src/journal')
local K=C.K
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end

-- Drapeaux bleus (relecture 162v, point 2) : une inattention imposée par l'app (comme le freinage, une voiture à côté, un
-- retour ou le départ) empêche la cession : aucun temps « sans excuse » compté, donc aucun drapeau ignoré.
tests.BLUE_VETO_LAPSE_162Y=function()
 local e,f=F.scene('C',3); local p=e.profiles.C
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.startDelay=0; p.startRelax=0; p.sanContact=true
 E.changed(e); F.place(f,1,-5000,100)
 local t=0
 while t<40 do F.rear(e,f,30,2); f.cars[3].lap=3; e.states[2].lapseUntil=e.time+1; F.tick(e,f,1/60); t=t+1/60 end
 local s=e.states[2]; local c=e.sanctions.cars[2]
 assert(s.blueAiLate and (s.blueAiFree or 0)==0,'lapse imposed by the app: no unexcused time ('..tostring(s.blueAiFree)..')')
 assert(c.blueN==0 and c.time==0,'no flag counted')
 -- Sans inattention, la même scène cède (le veto venait bien de l'inattention).
 local e2,f2=F.scene('C',3); local p2=e2.profiles.C
 p2.personalLineJitter=0; p2.lapseEnabled=false; p2.pressureEnabled=false; p2.startDelay=0; p2.startRelax=0; p2.sanContact=true
 E.changed(e2); F.place(f2,1,-5000,100)
 local yielded=false
 for _=1,600 do F.rear(e2,f2,30,2); f2.cars[3].lap=3; F.tick(e2,f2,1/60); if F.yielding(e2.states[2].state) then yielded=true; break end end
 assert(yielded,'without the lapse the lapped car yields')
end

-- Grille (relecture 162v, point 1) : IA prêtes, joueur pas en place : attente propre au joueur (K.gridPlayerWait s), puis
-- les feux ; avant, les IA restaient immobiles jusqu'au délai maximal (K.gridMax s).
tests.GRID_PLAYER_WAIT_162Y=function()
 local function slotZ(k) return -(K.gridFirst+(k-1)*K.gridPitch) end
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart='standing'; E.changed(e); e.gridCaps=true
 for i=1,3 do f.cars[i].position=i end
 F.place(f,1,slotZ(1)-900,0); F.place(f,2,slotZ(2)-300,60); F.place(f,3,slotZ(3)-300,60)
 F.tick(e,f,0.2)
 local t=e.incidents; t.standing='grid'; F.tick(e,f,0.1)
 F.place(f,2,slotZ(2),0); F.place(f,3,slotZ(3),0); F.tick(e,f,1/60)
 assert(e.grid.held[2] and e.grid.held[3] and t.standing=='grid','AI in place, player far away')
 F.tick(e,f,K.gridPlayerWait-1); assert(t.standing=='grid','player still has time')
 F.tick(e,f,1.5)
 assert(t.standing=='lights','lights after the player wait, long before the hard timeout')
 assert(count(e,'joueur pas en place')==1,'journal says the player was not in place')
 assert(K.gridPlayerWait<K.gridMax,'player wait shorter than the hard timeout')
end

-- Résumé (relecture 162v, point 5) : une tentative finie autrement (cession, obstacle, contact…) compte dans « autres » :
-- tentés = réussis + annulés sur la minute.
tests.PASS_OTHER_ENDING_162Y=function()
 local e=F.scene('C',4)
 e.stats.pass=3; e.stats.clear=1; e.stats.abort_slow=1; e.stats.pass_other=1
 local sum=J.summary(e)
 assert(sum:find('depassements tentes 3, reussis 1, annules 2',1,true),'tried = succeeded + cancelled with « other » endings: '..sum)
 assert(sum:find('jaune 0, autres 1)',1,true),'other endings published')
 local D=require('src/director')
 local s=e.states[2]; s.state='OVT_HOLD'; s.passStartAt=0; s.passName='x'; s.passMinGap=5; s.slot=2
 e.stats.pass_other=0
 D.transitionTest(e,s,'YIELD_IN','yield',1)
 assert(e.stats.pass_other==1,'an attempt ended by a yield counts as other')
 s.state='OVT_HOLD'; s.passStartAt=0
 D.transitionTest(e,s,'DRIVE','abort_slow',2)
 assert(e.stats.pass_other==1,'a listed abort is not counted twice')
end

-- Compteurs de la nuance des classes et du changement de côté (relecture 162v, point 4) : une fois par voiture et cible.
tests.ONCE_PER_TARGET_COUNTERS_162Y=function()
 local D=require('src/director')
 local e=F.scene('C',4); local s=e.states[2]
 for _=1,60 do D.refused(e,s,3,'nuanceHold'); D.refused(e,s,3,'sideRoom') end
 assert(e.stats.nuanceHold==1 and e.stats.passSideRoom==1,'counted once per target, not per frame')
 D.refused(e,s,4,'nuanceHold'); assert(e.stats.nuanceHold==2,'new target: counted again')
end

-- Limites de LuaJIT : 60 upvalues par fonction, 200 locales actives par fonction (le bloc principal d'un module compte).
-- director.M.step était à 60 upvalues et ui.lua à 199 locales de module : un ajout empêchait le chargement de l'app.
-- Ce test prévient le prochain lot avant la limite (55 upvalues, 185 locales).
local function protoOf(path,want)
 local ju=require('jit.util')
 local chunk=assert(loadfile(path))
 local found
 local function walk(fn)
  local i=ju.funcinfo(fn)
  if want and i.linedefined==want then found=fn end
  for k=-1,-(i.gcconsts or 0),-1 do local c=ju.funck(fn,k); if type(c)=='proto' then walk(c) end end
 end
 walk(chunk)
 return chunk,found,ju
end
local function moduleLocals(path)
 local n=0
 for line in io.lines(path) do
  if line:sub(1,15)=='local function ' then n=n+1
  elseif line:sub(1,6)=='local ' then
   local head=line:sub(7):match('^([^=]*)') or ''
   for name in head:gmatch('[%w_]+') do n=n+1 end
  end
 end
 return n
end
tests.LUAJIT_LIMITS_MARGIN_162Y=function()
 local dir=assert(package.searchpath('src/director',package.path))
 local ui=assert(package.searchpath('src/ui',package.path))
 local stepLine
 local k=0
 for line in io.lines(dir) do k=k+1; if line:sub(1,16)=='function M.step(' then stepLine=k; break end end
 assert(stepLine,'director M.step found')
 local _,step,ju=protoOf(dir,stepLine)
 assert(step,'M.step prototype found')
 local upv=ju.funcinfo(step).upvalues
 assert(upv<=55,'director.M.step captures '..upv..' upvalues (LuaJIT limit 60, keep <= 55)')
 local locals=moduleLocals(ui)
 assert(locals<=185,'ui.lua has '..locals..' module locals (LuaJIT limit 200, keep <= 185)')
 local dl=moduleLocals(dir)
 assert(dl<=185,'director.lua has '..dl..' module locals (keep <= 185)')
end

return tests
