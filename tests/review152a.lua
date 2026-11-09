-- Beta 1.52 (relecture du pilotage des IA) : un test par défaut majeur corrigé, chacun en échec sur la Beta 1.51, et
-- quelques défauts mineurs. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Scène de qualifications, tours lancés actifs (joueur loin derrière, en tour de sortie).
local function quali(n)
 local e,f=F.scene('Q',n); e.profiles.Q.qualiTraffic=true; e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,1/60)
 return e,f
end
-- 1. Cession prioritaire achevée : drapeau bleu, classe et tour lancé oubliés à la sortie des états de cession (restés
-- vrais, ils coupaient l'urgence, l'aspiration cassée, la place à rendre et l'attente réciproque).
tests.REVIEW_YIELD_FLAGS_CLEARED_152=function()
 local e,f=F.scene('C',3); e.p.personalLineJitter=0
 F.place(f,1,-3000,100); F.place(f,2,0,100); F.place(f,3,3000,100)
 local s=e.states[2]
 s.state='YIELD_OUT'; s.yieldBlue=true; s.yieldQuali=true; s.yieldClass=true; s.target=3; s.offset=0; s.filtered=0; s.base=0
 F.tick(e,f,0.2)
 assert(s.state=='DRIVE','yield over: '..s.state)
 assert(not s.yieldBlue and not s.yieldQuali and not s.yieldClass,'priority flags cleared on leaving the yield states')
 -- Course : une vraie cession au drapeau bleu, puis la voiture qui prend le tour s'éloigne : drapeaux oubliés.
 local e2,f2=F.scene('C',3); e2.p.personalLineJitter=0
 F.rear(e2,f2,100,20); f2.cars[3].lap=2; F.tick(e2,f2,3)
 local s2=e2.states[2]
 assert(F.yielding(s2.state) and s2.yieldBlue,'blue flag yield')
 F.place(f2,3,1500,130); f2.cars[3].lap=3; e2.states[2].nextPerception=0
 local back=false
 for _=1,40*60 do F.tick(e2,f2,1/60); if s2.state=='DRIVE' then back=true; break end end
 assert(back and not s2.yieldBlue,'back to driving, blue flag forgotten ('..s2.state..')')
end
-- 2. Drapeau bleu en attente (virage) oublié quand la cession n'est pas jugée (reprise au calme, évitement, voiture à
-- côté...) : avant, le niveau restait abaissé et l'urgence coupée jusqu'à la cession suivante.
tests.REVIEW_BLUE_PENDING_CLEARED_152=function()
 local e,f=F.scene('C',3); e.p.personalLineJitter=0
 F.rear(e,f,60,20); f.cars[3].lap=2; f.cars[2].yawRate=0.4; F.tick(e,f,3)
 local s=e.states[2]
 assert(s.bluePending,'blue flag pending in the corner')
 s.state='CALM'; s.calmUntil=e.time+10
 F.tick(e,f,0.1)
 assert(s.state=='CALM' and not s.bluePending,'yield not judged (calm recovery): no pending blue flag')
end
-- 3. Repos anti-zigzag : une cession prioritaire (drapeau bleu) commence quand même ; une cession ordinaire attend.
tests.REVIEW_PRIORITY_YIELD_DURING_REST_152=function()
 local e,f=F.scene('C',3); e.p.personalLineJitter=0
 F.rear(e,f,100,20); f.cars[3].lap=2
 local s=e.states[2]; s.driveUntil=e.time+30
 local yielded=false
 for _=1,4*60 do F.tick(e,f,1/60); if F.yielding(s.state) then yielded=true; break end end
 assert(yielded and s.yieldBlue,'blue flag yield started during the rest ('..s.state..')')
 F.tick(e,f,0.5); assert((F.yielding(s.state) or s.state=='YIELD_OUT'),'not cut short by the rest ('..s.state..')')
 -- Journée circuit, cession ordinaire : attend la fin du repos.
 local e2,f2=F.scene('J',3); e2.p.personalLineJitter=0
 F.rear(e2,f2,45,30)
 local s2=e2.states[2]; s2.driveUntil=e2.time+30
 F.tick(e2,f2,3)
 assert(not F.yielding(s2.state),'ordinary yield waits for the end of the rest')
end
-- 4. Enchaînement de dépassement : soumis aux gardes du déclenchement (ici, tours lancés) et noté au journal comme une
-- nouvelle tentative (fin de la précédente, nouvelle cible, instant du début).
local function chainScene(profile)
 local e,f
 if profile=='Q' then e,f=quali(4) else e,f=F.scene(profile,4); e.p.personalLineJitter=0 end
 e.p.overtakeChain=true; E.changed(e); F.tick(e,f,1/60)
 F.place(f,1,-3000,100); F.place(f,2,0,100); F.place(f,3,-35,100); F.place(f,4,40,100)
 local s=e.states[2]
 s.state='OVT_HOLD'; s.target=3; s.targetSide=1; s.direction=1; s.offset=0.4; s.filtered=0.4
 s.passStartAt=e.time; s.passName='Driver_3'; s.passMinGap=10; s.passAlongside=false; s.lastPassTarget=3; s.lastPassAt=e.time
 for i=1,4 do e.states[i].nextPerception=0 end
 return e,f,s
end
tests.REVIEW_CHAIN_GUARDS_152=function()
 local e,f,s=chainScene('J')
 local start=e.time
 F.tick(e,f,K.clearConfirm+0.2)
 assert(s.target==4 and F.passing(s.state),'chained onto the next car ('..s.state..', '..s.target..')')
 assert(s.passName=='Driver_4' and s.lastPassTarget==4 and s.passStartAt>start and s.passMinGap<=40,'attempt fields updated')
 assert(count(e,'reussi, enchaine')==1 and count(e,'Driver_4 (enchainement')==1,'previous attempt closed, new one logged')
 -- Qualifications : IA pas lancée, voiture lancée devant : pas d'enchaînement (garde de la 1.51).
 local e2,f2,s2=chainScene('Q')
 e2.quali.cars[4].out=false; e2.quali.cars[4].cool=false; F.tick(e2,f2,1/60)
 assert(e2.quali.push[4] and not e2.quali.push[2],'car 4 pushing, car 2 not')
 F.tick(e2,f2,K.clearConfirm+0.2)
 assert(s2.target~=4 and count(e2,'Driver_4 (enchainement')==0,'no chain onto a flying car ('..s2.state..', '..s2.target..')')
end
-- 5. Appel de phares entre IA : une IA lancée ne cède pas à l'appel d'une voiture pas lancée ; l'appel d'une IA ne
-- remplace pas la voiture lancée prioritaire.
tests.REVIEW_AI_FLASH_QUALI_152=function()
 local e,f=quali(4)
 F.place(f,1,-3000,100); F.place(f,4,4000,100); F.place(f,2,0,100); F.place(f,3,-30,100)
 e.quali.cars[2].out=false; e.quali.cars[2].cool=false
 for i=1,4 do e.states[i].nextPerception=0 end
 F.tick(e,f,1/60)
 assert(e.quali.push[2] and not e.quali.push[3],'car 2 pushing, car 3 on its out-lap')
 local yielded=false
 for _=1,3*60 do
  local q=e.flash.ai[2]; q.source=3; q.untilTime=e.time+5; q.readyAt=e.time
  F.place(f,2,0,100); F.place(f,3,-30,100); F.tick(e,f,1/60)
  if F.yielding(e.states[2].state) then yielded=true; break end
 end
 assert(not yielded,'a flying car never yields to the flash of a car that is not')
end
-- 6. Refroidissement prévu seulement avec l'onglet Général : sans lui, le niveau n'est pas commandé et la voiture
-- roulait un tour entier à pleine vitesse sans être lancée.
tests.REVIEW_COOL_NEEDS_GENERAL_152=function()
 local e,f=F.scene('Q',3); e.profiles.Q.qualiTraffic=true; e.profiles.Q.qualiCoolLaps=true; e.profiles.Q.section_general=false; E.changed(e)
 f.left=0; F.tick(e,f,1/60)
 assert(not e.run.section_general and e.run.qualiTraffic and e.run.qualiCoolLaps,'general tab off, flying laps on')
 local c=e.quali.cars[2]; c.out=false; c.cool=false; F.tick(e,f,1/60)
 assert(e.quali.push[2],'AI 2 pushing')
 local a=f.cars[2]
 for _=1,K.qualiPushMax+1 do a.lap=a.lap+1; F.tick(e,f,1/60) end
 assert(not c.planned and e.quali.push[2] and (e.stats.qualiCool or 0)==0,'no planned cool-down lap without the general tab')
end
-- 11. Cessions en tour lancé : passées et perdues font le total, quelle que soit la fin (ici, drapeau jaune).
tests.REVIEW_QUALI_YIELD_COUNTS_152=function()
 local e,f=quali(3)
 local s=e.states[2]
 s.state='YIELD_HOLD'; s.target=3; s.targetSide=1; s.yieldQuali=true; s.yieldBlue=true; s.yieldStart=e.time; s.holdUntil=e.time+30; s.followers[3]=true
 e.stats.qualiYield=1
 s.yellow=true
 local Incidents=require('src/incidents'); local cap=Incidents.cap
 Incidents.cap=function() return K.unlimitedSpeed,true end
 local ok,err=pcall(function() F.tick(e,f,1/60) end)
 Incidents.cap=cap
 assert(ok,err)
 assert(s.state=='YIELD_OUT' or s.state=='DRIVE','yield ended by the yellow flag ('..s.state..')')
 assert((e.stats.qualiPassed or 0)+(e.stats.qualiLost or 0)==e.stats.qualiYield,'passed + lost = yields')
end
-- 12. Durée maximale de cession : suiveur ignoré une fois (l'oubli n'est plus repoussé à chaque image de la sortie).
tests.REVIEW_HOLD_LIMIT_ONCE_152=function()
 local e,f=F.scene('J',3); e.p.personalLineJitter=0
 F.rear(e,f,45,30); F.tick(e,f,4)
 local s=e.states[2]
 assert(F.yielding(s.state),'yielding')
 s.yieldStart=e.time-e.p.yieldMaxHold-1
 F.tick(e,f,1/60)
 assert(s.state=='YIELD_OUT' and s.reason=='hold_limit','hold limit reached')
 local until0=s.ignoreUntil
 F.tick(e,f,0.2)
 assert(s.state~='YIELD_OUT' or s.ignoreUntil==until0,'ignore window set once')
end
-- 8. Recalage du temps : instants des états des IA décalés.
tests.REVIEW_REBASE_FIELDS_152=function()
 local e,f=F.scene('J',3)
 local s=e.states[2]
 local fields={'passedByPlayerAt','qualiLogAt','lastPassAt','passStartAt','maneuverAt','laneSeen','laneAt','straightHoldAt','defendLogAt'}
 for _,key in ipairs(fields) do s[key]=e.time-1 end
 E.rebase(e,1000)
 for _,key in ipairs(fields) do assert(math.abs(s[key]-(e.time-1))<1e-6,key..' rebased') end
end
-- 14. Série de tours lancés : remise à zéro par un tour qui n'était pas lancé.
tests.REVIEW_PUSH_SERIES_RESET_152=function()
 local e,f=quali(3)
 local c=e.quali.cars[2]; c.out=false; c.cool=false; F.tick(e,f,1/60)
 assert(e.quali.push[2],'pushing')
 c.pushLaps=1
 -- Tour de sortie (après un passage aux stands) achevé à la ligne : la série repart de zéro.
 c.out=true; c.outLap=f.cars[2].lap; c.exitAt=e.time-K.qualiOutGrace-1; F.tick(e,f,1/60)
 local a=f.cars[2]; a.lap=a.lap+1; F.tick(e,f,1/60)
 assert(c.pushLaps==0,'series reset by a lap that was not a flying lap: '..c.pushLaps)
end
return tests
