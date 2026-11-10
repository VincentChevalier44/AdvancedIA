-- Beta 1.54 (journée circuit du 9 novembre à la Nordschleife : une IA a relancé six fois la même cible, chaque échec
-- « cible plus rapide », avec 33 appels de phares en 6 min) : attente stricte de la paire après K.passIgnoreStrict échecs,
-- aucun appel de phares vers une cible ignorée hors course, contexte d'un tête-à-queue enrichi. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local J=require('src/journal')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function learned(e,first,last,speed)
 for i=first,last do local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=speed end end
end
-- Paire ignorée avec une avance d'allure apprise : permis au premier échec (Beta 1.47), plus à partir du deuxième.
tests.PASS_IGNORE_STRICT_154=function()
 local function engaged(failures)
  local e,f=F.scene('J',3); e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
  learned(e,2,2,260/3.6); learned(e,3,3,200/3.6)
  local s=e.states[2]; s.passIgnore=3; s.passIgnoreUntil=e.time+100; s.passIgnoreCount=failures
  F.front(e,f,25,20)
  for _=1,4*60 do F.tick(e,f,1/60); if F.passing(s.state) then return true end end
  return false
 end
 assert(K.passIgnoreStrict==2,'strict wait from the second failure')
 assert(engaged(1),'first failure: a real advantage still allows a pass (Beta 1.47)')
 assert(not engaged(K.passIgnoreStrict),'repeated failures: no pass on closing, even with a learned advantage')
 -- Attente terminée : la paire est de nouveau permise.
 local e,f=F.scene('J',3); e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
 learned(e,2,2,260/3.6); learned(e,3,3,200/3.6)
 local s=e.states[2]; s.passIgnore=3; s.passIgnoreUntil=e.time; s.passIgnoreCount=3
 F.front(e,f,25,20)
 local ok=false; for _=1,4*60 do F.tick(e,f,1/60); if F.passing(s.state) then ok=true; break end end
 assert(ok,'wait over: pass allowed again')
end
-- Deux échecs « cible plus rapide » de suite : la deuxième attente est notée une fois au journal, pas la première.
tests.PASS_SUSPENDED_LOG_154=function()
 local e,f=F.scene('J',3); e.p.personalLineJitter=0; E.changed(e); F.tick(e,f,0.2)
 local s=e.states[2]
 local function attempt()
  F.front(e,f,20,-10)
  s.state='OVT_IN'; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=20; s.passName='Cible'; s.abortSlow=0; s.passAlongside=false
  for _=1,5*60 do F.tick(e,f,1/60); if s.state~='OVT_IN' and s.state~='OVT_HOLD' then break end end
 end
 attempt(); assert(s.reason=='abort_slow' and s.passIgnoreCount==1)
 assert(count(e,'depassement suspendu:')==0,'first failure: no suspension line')
 F.tick(e,f,3); attempt(); assert(s.reason=='abort_slow' and s.passIgnoreCount==2)
 assert(count(e,'depassement suspendu:')==1 and count(e,'-> Cible apres 2 echecs (cible plus rapide), plus de tentative pendant 180 s')==1,'second failure: one line, with the wait')
end
-- Appel de phares vers une IA retenue : jamais vers une cible ignorée hors course ; permis à nouveau après l'attente.
tests.FLASH_IGNORED_TARGET_154=function()
 local function flashed(ignored)
  local e,f=F.scene('J',3); local p=e.profiles.J
  p.aiFlashEnabled=true; p.pressureEnabled=false; p.multiClass=false; E.changed(e)
  F.place(f,2,0,100); F.place(f,3,29.4,100)
  local s=e.states[2]; for b=1,K.paceBins do s.pace[b]=50 end; s.paceCount=K.paceBins; s.paceMean=50
  for _=1,8*60 do
   if ignored then s.passIgnore=3; s.passIgnoreUntil=e.time+100; s.passIgnoreCount=1 end
   F.tick(e,f,1/60)
  end
  return e.commands[2].flashEvent>0,count(e,'appel de phares:')
 end
 local yes=flashed(false); assert(yes,'held behind a slower AI: flash')
 local no,n=flashed(true); assert(not no and n==0,'ignored target: no flash')
end
-- Contexte d'un tête-à-queue : limite de vitesse, perte de concentration et état quitté juste avant (traduits).
tests.SPIN_CONTEXT_154=function()
 local line='tete-a-queue, contexte: X | etat DRIVE depuis 0.4 s, derniere manoeuvre aucune, decalage +0.00, prudence 1.55 (base 1.55), agressivite 0.52 (base 0.52), niveau 0.95, aspiration non, frein app 0.00, limite 104 km/h, inattention non, etat precedent IDLE (guard)'
 assert(J.english(line)=='spin, context: X | state DRIVE for 0.4 s, last manoeuvre none, offset +0.00, caution 1.55 (base 1.55), aggression 0.52 (base 0.52), level 0.95, wheelspin no, app brake 0.00, speed limit 104 km/h, lapse no, previous state IDLE (guard)',J.english(line))
 assert(J.english('depassement suspendu: A (100%, 100%) -> B (100%, 100%) apres 3 echecs (cible plus rapide), plus de tentative pendant 600 s')
  =='overtaking suspended: A (100%, 100%) -> B (100%, 100%) after 3 failures (target faster), no new attempt for 600 s')
 -- Ligne écrite par le moteur : limite, inattention et état quitté, traduite en entier.
 local g,gf=F.scene('P',3)
 F.place(gf,1,-3000,100); F.place(gf,2,0,120); F.place(gf,3,3000,100); F.tick(g,gf,0.5)
 gf.cars[2].slip=50; F.tick(g,gf,1.5)
 local found
 for k=1,g.log.limit do local r=g.log[k]; if r and r.message and r.message:find('tete-a-queue, contexte: Driver_2 | ',1,true) then found=r.message end end
 assert(found and found:find(', frein app [%d.]+, limite [^,]+, inattention [a-z]+, etat precedent [A-Z_]+ %([%w_ ]+%)$'),tostring(found))
 assert(J.english(found):find('previous state',1,true),'whole line translated: '..J.english(found))
 -- État quitté gardé à chaque changement d'état.
 local e,f=F.scene('J',3); E.changed(e); F.tick(e,f,0.5)
 local s=e.states[2]; assert(s.state=='DRIVE' and s.prevState=='IDLE','previous state kept: '..tostring(s.prevState))
end
return tests
