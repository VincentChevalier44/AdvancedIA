-- 2.0.2 i (retours des joueurs sur Overtake, 15-16 novembre) : (1) arrêts sans accident et voitures jamais revenues
-- (course WEC du pilote, 2026-11-15_19_47_04 : 10 IA « abandonnees » après un tête-à-queue ou un arrêt sous FCY, toutes
-- intactes : « ne repart pas apres 3 essai(s) », « piste jamais libre ») ; (2) tour de formation « arrêté » suivi d'un
-- départ lancé quand le sens latéral n'est pas encore mesuré. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local K=C.K
local tests={}

tests.K_202I=function()
 assert(K.retireBrokenOnly==true and K.formationWaitSign==true and K.failureMinLaps==2)
end

local function recoverScene(profile,brokenEngine)
 local e,f=F.scene(profile,3); F.place(f,1,-4000,120); F.place(f,2,-3000,200); F.place(f,3,5166,0)
 local recovered=false
 for _=1,60 do
  F.place(f,3,5166,0); if brokenEngine then f.cars[3].engineLife=0 end
  local c=e.incidents.cars[3]; if c.incident then c.cannot=c.cannot or 'ne repart pas apres 3 essai(s)' end
  F.tick(e,f,0.25); if e.commands[3].recover then recovered=true; break end
 end
 return e,f,recovered
end

-- Course : une IA intacte dépannée (jamais repartie) rentre et repart ; seule une IA cassée abandonne.
tests.LOCK_RETIRE_BROKEN_ONLY_202=function()
 local e,f,rec=recoverScene('C',false)
 assert(rec,'scene: intact car recovered ('..tostring(e.commands[3].recoverReason)..')')
 assert(e.states[3].retirePending==nil,'intact car: no retirement pending ('..tostring(e.states[3].retirePending)..')')
 f.cars[3].pit=true; f.cars[3].inPitBox=true; F.tick(e,f,1/60); F.tick(e,f,1/60)
 assert(not e.states[3].retired and e.commands[3].parkReason~='retired','intact car: back in the race after repair')
 local g,h,rec2=recoverScene('C',true)
 assert(rec2 and g.states[3].retirePending~=nil,'broken car: retirement pending')
 h.cars[3].pit=true; h.cars[3].inPitBox=true; F.tick(g,h,1/60)
 assert(g.states[3].retired,'broken car: retires (driver decision 2026-11-14 kept)')
 -- Règle coupée : comportement de la 2.0.0 (toute IA dépannée abandonne).
 local old=K.retireBrokenOnly; K.retireBrokenOnly=false
 local ok,err=pcall(function() local m,n,r=recoverScene('C',false); assert(r and m.states[3].retirePending~=nil,'rule off: 2.0.0 behaviour') end)
 K.retireBrokenOnly=old; assert(ok,err)
end

-- Tour de formation « arrêté » au feu vert sans sens latéral mesuré : gardé (décision à la fin du tour), journal.
tests.LOCK_FORMATION_STANDING_KEPT_202=function()
 local E=require('src/engine')
 local function run(sign,wait)
  local old=K.formationWaitSign; K.formationWaitSign=wait
  local ok,e=pcall(function()
   local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); e.profiles.C.raceStart='formation'; e.profiles.C.startRealism=false; f.length=4000
   for i=1,4 do f.cars[i].position=i; F.place(f,i,-(i*12),0) end
   E.changed(e); e.gridCaps=true; F.tick(e,f,1/60); e.g.offsetSign=sign
   f.started=false; F.tick(e,f,1/60); e.g.offsetSign=sign
   f.started=true; F.tick(e,f,1/60)
   return e
  end)
  K.formationWaitSign=old; assert(ok,e); return e
 end
 local function has(e,text) for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then return true end end return false end
 local e=run(0,true)
 assert(e.incidents.formationKind=='formation','unmeasured sign: standing formation kept ('..tostring(e.incidents.formationKind)..')')
 assert(has(e,'sens lateral pas encore mesure'),'journal line')
 local g=run(0,false); assert(g.incidents.formationKind~='formation' and has(g,'grille indisponible'),'rule off: rolling as before')
 local h=run(-1,true); assert(h.incidents.formationKind=='formation' and not has(h,'sens lateral pas encore mesure'),'measured sign: standing formation')
end
return tests
