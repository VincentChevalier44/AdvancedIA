-- Beta 1.53 : niveau au-dessus de 100 % (décision du pilote : CSP accepte 0 à 2, le mode automatique écrit en natif
-- sans attendre la relecture ; journal de la sonde et de l'écrêtage) et journal anglais de la fenêtre DIAGNOSTICS.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local Caps=require('src/caps')
local A=require('src/applier')
local J=require('src/journal')
local tests={}
local function port() return {present=function() return true end,write=function() return true end} end
-- Sonde finie : la voiture sondée relit `read`.
local function probed(read,g)
 local e,f=F.scene('J'); F.place(f,1,-1000,100); F.place(f,2,0,100); F.place(f,3,120,100)
 local cap=Caps.new(port()); g=g or {levelMode='auto',useGripBoost=false}
 Caps.probe(cap,f,0,g); assert(cap.probeIndex>0,'probe started')
 f.cars[cap.probeIndex].aiLevel=read; Caps.probe(cap,f,1,g); assert(cap.probeDone and cap.probeIndex==0,'probe done')
 return cap,g
end
tests.LEVEL_PROBE_LOG_ACCEPTED_153=function()
 local cap,g=probed(1.05)
 local text=Caps.report(cap,g)
 assert(text and text:find('niveau au-dessus de 100 %: sonde 1.05 relue 1.05 (niveau d origine',1,true),tostring(text))
 assert(text:find('-> natif (jusqu a 110 %) (mode demande auto, bonus de grip non autorise)',1,true),text)
 assert(cap.native110 and not cap.clampProven and cap.levelMode=='native')
 assert(Caps.report(cap,g)==nil,'logged once')
 -- Bonus de grip autorisé mais relecture à 1.05 : le niveau natif reste en service.
 local g2={levelMode='auto',useGripBoost=true}; Caps.mode(cap,g2); assert(cap.levelMode=='native','grip allowed, no cap proven: native')
 Caps.mode(cap,g)
 g.levelMode='none'; Caps.mode(cap,g); assert(Caps.report(cap,g)=='niveau au-dessus de 100 %: mode plafond 100 % (mode demande none, bonus de grip non autorise)')
 assert(Caps.report(cap,g)==nil,'mode change logged once')
end
tests.LEVEL_PROBE_LOG_CLAMPED_153=function()
 local cap,g=probed(1.0)
 local text=Caps.report(cap,g)
 assert(text and text:find('sonde 1.05 relue 1.00 (lecture ecretee)',1,true) and text:find('-> natif (jusqu a 110 %)',1,true),tostring(text))
 assert(cap.clampProven and not cap.native110 and cap.levelMode=='native','auto stays native with the grip bonus off')
 g.useGripBoost=true; Caps.mode(cap,g); assert(cap.levelMode=='grip','clamp proven and grip allowed: grip bonus')
 assert(Caps.report(cap,g)=='niveau au-dessus de 100 %: mode bonus de grip (mode demande auto, bonus de grip autorise)')
 g.levelMode='native'; Caps.mode(cap,g); assert(cap.levelMode=='none','native if confirmed: cap')
 g.levelMode='grip'; Caps.mode(cap,g); assert(cap.levelMode=='grip')
 g.useGripBoost=false; Caps.mode(cap,g); assert(cap.levelMode=='none')
end
tests.LEVEL_AUTO_BEFORE_READBACK_153=function()
 local cap=Caps.new(port())
 Caps.mode(cap,{levelMode='auto',useGripBoost=false}); assert(cap.levelMode=='native','auto: native at once')
 Caps.mode(cap,{levelMode='native',useGripBoost=false}); assert(cap.levelMode=='none','native if confirmed: waits for the read-back')
 cap.level.available=false; Caps.mode(cap,{levelMode='auto',useGripBoost=true}); assert(cap.levelMode=='grip','no level command: grip if allowed')
end
-- Couche hôte : 1.03 écrit en mode automatique même si la relecture est écrêtée ; écrêtage noté une fois ; « natif si
-- confirmé » repasse à 1.00.
tests.LEVEL_APPLIER_AUTO_CLAMPED_153=function()
 local host=require('tests/host').create(false); local e,f=F.scene('J')
 local a=A.new(); assert(A.access(a)); local notes={}; a.note=function(level,text,index) notes[#notes+1]=level..' '..text end
 for _,cmd in ipairs(e.commands) do cmd.active=false end
 local cmd=e.commands[2]; cmd.active=true; cmd.levelOwned=true; cmd.aggressionOwned=false; cmd.cautionOwned=false; cmd.level=1.03; cmd.offset=0
 local g=e.g; g.levelMode='auto'; g.useGripBoost=false; Caps.mode(a.caps,g)
 A.apply(a,f,e.commands,g,10); assert(math.abs(a.cars[2].level-1.03)<1e-9,'1.03 written: '..tostring(a.cars[2].level))
 f.cars[2].aiLevel=1.0
 A.apply(a,f,e.commands,g,20); A.apply(a,f,e.commands,g,30)
 local found=0; for _,n in ipairs(notes) do if n:find('WARN niveau au-dessus de 100 %: ',1,true) and n:find(' relu 1.00 apres 1.03 ecrit (lecture ecretee) -> natif',1,true) then found=found+1 end end
 assert(found==1,'clamp noted once: '..table.concat(notes,' | '))
 assert(a.caps.clampProven and a.caps.levelMode=='native' and math.abs(a.cars[2].level-1.03)<1e-9,'still native at 1.03')
 g.levelMode='native'; Caps.mode(a.caps,g); A.apply(a,f,e.commands,g,40)
 assert(a.caps.levelMode=='none' and math.abs(a.cars[2].level-1)<1e-9,'native if confirmed: capped at 1.00')
end
-- Journal anglais : modèles, noms recopiés, morceaux traduits, ligne inconnue gardée.
tests.JOURNAL_ENGLISH_153=function()
 assert(J.english('depassement fini: Jean de la Tour -> Le Pilote : cote ferme apres 7.4 s (ecart mini 4 m)')=='overtake ended: Jean de la Tour -> Le Pilote: side closed after 7.4 s (min gap 4 m)')
 assert(J.english('radar avant: Ana freine derriere Bob (8 m, 24 km/h plus vite), suiveur a 7 m')=='front radar: Ana brakes behind Bob (8 m, 24 km/h faster), follower at 7 m')
 assert(J.english('jonction des stands: A attend B en tour lance (a la jonction dans 1.4 s, 80 m avant elle)')=='pit-exit merge: A waits for B on a flying lap (at the merge in 1.4 s, 80 m before it)')
 assert(J.english('tete-a-queue, contexte: X | etat DRIVE depuis 1.0 s, derniere manoeuvre il y a 3.2 s, decalage +0.00, prudence 1.00 (base 1.00), agressivite 0.50 (base 0.50), niveau 0.95, aspiration non, frein app 0.00')
  =='spin, context: X | state DRIVE for 1.0 s, last manoeuvre 3.2 s ago, offset +0.00, caution 1.00 (base 1.00), aggression 0.50 (base 0.50), level 0.95, wheelspin no, app brake 0.00')
 -- Noms de Content Manager avec parenthèses (« Nom (100%, 100%) »).
 assert(J.english('depassement: A (100%, 100%) -> B (100%, 100%) (cession, 14 m, +5 km/h)')=='overtake: A (100%, 100%) -> B (100%, 100%) (yield, 14 m, +5 km/h)')
 local text,rule=J.english('ligne inconnue 12'); assert(text=='ligne inconnue 12' and rule==nil,'unknown line kept')
 local marked=J.english('appel de phares: Ana -> Bob',true); assert(marked=='headlight flash: <name> -> <name>')
 -- Aucun modèle masqué par un modèle placé avant lui : chaque modèle, rempli d'exemples, est reconnu par lui-même.
 local D=require('src/journal_en')
 for i,r in ipairs(D.rules) do
  local m=r[1]:gsub('{n}','Ana Bob (100%%, 100%%)'):gsub('{p}','zz'):gsub('{}','12')
  local _,rule=J.english(m); assert(rule and rule.en==r[2],'pattern '..i..' shadowed: '..m)
 end
end
return tests
