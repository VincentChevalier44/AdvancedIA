-- Beta 1.64 (décision du pilote du 14 novembre) : clignotants des IA par la voiture cible (src/signals.lua). Noms
-- LOCK_*_164 (tests/LOCKS.md) et *_164G1. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local A=require('src/applier')
local S=require('src/signals')
local C=require('src/config')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end

tests.K_164G1=function()
 assert(K.signalMinOffset==0.15)
 assert(S.NONE==0 and S.LEFT==1 and S.RIGHT==2 and S.HAZARDS==3)
 assert(S.NONE==(ac.TurningLights and ac.TurningLights.None or 0))
 for _,profile in ipairs({'J','P','Q','C','H'}) do assert(C.defaults(profile).aiTurnSignals==true,profile) end
end
-- Règle pure, dans les deux sens latéraux.
tests.SIGNAL_MODE_164G1=function()
 for _,sign in ipairs({1,-1}) do
  local y={state='YIELD_IN'}
  assert(S.mode(y,0.6*sign,sign,'J',false)==S.RIGHT,'track day: yields to the right ('..sign..')')
  assert(S.mode(y,-0.6*sign,sign,'J',false)==S.LEFT,'track day: yields to the left ('..sign..')')
  assert(S.mode({state='YIELD_HOLD'},0.6*sign,sign,'Q',false)==S.RIGHT,'qualifying: held aside')
  assert(S.mode({state='YIELD_OUT'},0.6*sign,sign,'J',false)==S.NONE,'back to the line: no signal')
  assert(S.mode(y,0.05*sign,sign,'J',false)==S.NONE,'tiny offset: no signal')
  assert(S.mode(y,0.6*sign,sign,'C',false)==S.NONE,'race without a blue flag: no signal')
  assert(S.mode({state='YIELD_IN',yieldBlue=true},0.6*sign,sign,'C',false)==S.RIGHT,'race: blue flag side')
  assert(S.mode({state='YIELD_IN',yieldClass=true},-0.6*sign,sign,'C',false)==S.LEFT,'race: faster class side')
  for _,st in ipairs({'OVT_ARM','OVT_PULL','OVT_HOLD','DEFEND','DRIVE','IDLE','CALM','AVOID'}) do
   assert(S.mode({state=st},0.8*sign,sign,'C',false)==S.NONE,'never while '..st)
  end
  assert(S.mode({state='DRIVE',edgePin=true},0,sign,'C',false)==S.HAZARDS,'slow car at the edge: hazards')
  assert(S.mode(y,0.6*sign,sign,'J',true)==S.NONE,'never the player')
 end
 assert(S.mode({state='YIELD_IN'},0.6,0,'J',false)==S.NONE,'lateral sign unknown: no signal')
end
-- Applicateur par le faux hôte : voiture cible choisie, clignotant commandé, cible rendue au joueur à chaque appel ;
-- renvoi à chaque image tant qu'elle clignote, une seule extinction, jamais le joueur ; restitution.
local function signalHost()
 local host=require('tests/host').create(true)
 local rec={calls={},target=0}
 ac.setTargetCar=function(index) rec.target=index; return index~=nil end
 ac.setTurningLights=function(mode) rec.calls[#rec.calls+1]={index=rec.target,mode=mode} end
 return host,rec
end
tests.LOCK_AI_TURN_SIGNALS_164=function()
 local host,rec=signalHost()
 local e,f=F.scene('J',3); local a=A.new(); assert(A.access(a))
 assert(a.caps.turnSignals.available,'capability present')
 for i=1,3 do e.commands[i].signal=0 end
 e.commands[2].signal=S.RIGHT; e.commands[1].signal=S.LEFT
 A.apply(a,f,e.commands,e.g,10)
 assert(#rec.calls==1 and rec.calls[1].index==1 and rec.calls[1].mode==S.RIGHT,'AI 1 signals right, the player never')
 assert(rec.target==0,'target given back to the player')
 A.apply(a,f,e.commands,e.g,10.02)
 assert(#rec.calls==2 and rec.calls[2].mode==S.RIGHT and rec.target==0,'re-sent every frame while signalling')
 e.commands[2].signal=S.NONE
 A.apply(a,f,e.commands,e.g,10.04)
 assert(#rec.calls==3 and rec.calls[3].index==1 and rec.calls[3].mode==S.NONE and rec.target==0,'switched off once')
 A.apply(a,f,e.commands,e.g,10.06)
 assert(#rec.calls==3,'nothing sent while off')
 e.commands[3].signal=S.HAZARDS; A.apply(a,f,e.commands,e.g,10.08)
 assert(rec.calls[4].index==2 and rec.calls[4].mode==S.HAZARDS and rec.target==0,'hazards')
 A.restore(a,f,false,10.1,true)
 assert(rec.calls[#rec.calls].index==2 and rec.calls[#rec.calls].mode==S.NONE and rec.target==0,'switched off at restore')
 ac.setTargetCar=nil; ac.setTurningLights=nil
end
-- Sans les fonctions de CSP : capacité absente, rien d'envoyé, une ligne au journal.
tests.SIGNAL_UNAVAILABLE_164G1=function()
 require('tests/host').create(true); ac.setTargetCar=nil; ac.setTurningLights=nil
 local e,f=F.scene('J',3); local a=A.new(); assert(A.access(a))
 local lines={}; a.note=function(level,text) lines[#lines+1]=text end
 assert(not a.caps.turnSignals.available,'capability missing')
 for i=1,3 do e.commands[i].signal=0 end
 e.commands[2].signal=S.LEFT; A.apply(a,f,e.commands,e.g,10); A.apply(a,f,e.commands,e.g,10.02)
 local n=0; for _,l in ipairs(lines) do if l:find('clignotants des IA: indisponibles',1,true) then n=n+1 end end
 assert(n==1,'one journal line ('..n..')')
end
-- Moteur : réglage, sens latéral et état du directeur ; réglage coupé : rien.
tests.SIGNAL_DECIDE_164G1=function()
 for _,sign in ipairs({1,-1}) do
  local e,f=F.scene('J',3); F.tick(e,f,0.5)
  e.g.offsetSign=sign; e.states[2].state='YIELD_IN'; e.commands[2].offset=0.6*sign
  S.decide(e,f)
  assert(e.commands[2].signal==S.RIGHT,'decided right ('..sign..')')
  assert(e.commands[1].signal==S.NONE,'never the player')
  e.p.aiTurnSignals=false; S.decide(e,f)
  assert(e.commands[2].signal==S.NONE,'setting off: no signal')
 end
end
-- Règle du pilote (14 novembre) : chaque préréglage intégré met explicitement l'option, même si le réglage enregistré
-- était coupé (pas seulement par défaut).
tests.PRESETS_AI_TURN_SIGNALS_164G1=function()
 -- Défaut du schéma coupé le temps du test : seul un préréglage qui met l'option lui-même la garde.
 local entry; for _,s in ipairs(C.schema) do if s.key=='aiTurnSignals' then entry=s end end
 assert(entry,'schema entry')
 local saved={}; for k,v in pairs(entry.defaults) do saved[k]=v; entry.defaults[k]=false end
 local ok,err=pcall(function()
  for _,row in ipairs({{'Nordschleife','J'},{'Circuit','J'},{'Essais','P'},{'Qualifications','Q'},{'Course','C'},{'Endurance','C'},{'Endurance','J'}}) do
   local p=C.preset(row[1],row[2],{aiTurnSignals=false})
   assert(p.aiTurnSignals==true,row[1]..' '..row[2]..' switches AI turn signals on explicitly')
   assert(p.section_lateral==true,row[1]..' '..row[2]..' lateral tab ticked')
  end
 end)
 for k,v in pairs(saved) do entry.defaults[k]=v end
 assert(ok,err)
end
return tests
