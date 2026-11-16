-- 2.0.3 k (accord avec SpotterEngineer, décision du pilote du 16 novembre) : clé annexe « AdvancedIA.tyres »
-- (src/tyreskey.lua) : règle F1 des deux composés secs pour le joueur et composés secs qu'il a roulés. Chargé par
-- tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local Pits=require('src/pits')
local TK=require('src/tyreskey')
local K=C.K
local tests={}
local function field(text,name) return (';'..text):match(';'..name..'=([^;]*)') end

-- Course aux tours (comme tests/review203a.lua), règle F1 réglée, arrêt laissé au défaut de la distance.
local function race(laps,length,compoundRule)
 local e,f=F.scene('C',3)
 local p=C.defaults('C'); p.section_rules=true; p.mandatoryStops=1; p.pitWindowOpenPct=20; p.pitWindowClosePct=80
 p.pitCompoundChange=compoundRule
 local run=C.distanceDefault('C',p,{mandatoryManual=false},C.effective('C',p,{}))
 run.pitCompoundChange=compoundRule
 f.sessionLaps=laps; f.leaderLaps=0; f.timedRace=false; f.sessionMinutes=0; f.pitWindowStart=0; f.pitWindowEnd=0; f.started=false
 f.length=length
 for i=1,f.count do f.cars[i].bestLap=0; f.cars[i].lap=0 end
 local t=Pits.new()
 local function step(now) Pits.update(t,f,e.commands,run,'C',now,1,function() end,false) end
 step(100); f.started=true; f.leaderLaps=1; for i=1,f.count do f.cars[i].lap=1 end; step(101)
 e.profile='C'; e.run=run; e.pits=t
 return e,f,t
end
local function playerSlot(f) for i=1,f.count do if f.cars[i].player then return i end end return 1 end

tests.LOCK_TYRES_KEY_203=function()
 -- Règle : course de 120 km, règle F1 réglée : 1 ; course de 37 km (arrêt levé par la distance) : 0 ; sans règle F1 : 0.
 local e,f,t=race(26,4615,true)
 f.player=playerSlot(f)
 assert(not t.waived,'120 km: not waived')
 local body=TK.body(e,f)
 assert(body:sub(1,4)=='v=1;' and field(body,'rule')=='1','120 km with the F1 rule: rule=1 ('..body..')')
 local e2,f2,t2=race(8,4591,true); f2.player=playerSlot(f2)
 assert(t2.waived,'37 km: waived by the distance default')
 assert(field(TK.body(e2,f2),'rule')=='0','short race: rule=0')
 local e3,f3=race(26,4615,false); f3.player=playerSlot(f3)
 assert(field(TK.body(e3,f3),'rule')=='0','no F1 rule: rule=0')
 -- Levée (course mouillée, pitWaived) : 0 ; hors course : 0 et liste vide.
 t.waived=true; assert(field(TK.body(e,f),'rule')=='0','waived: rule=0'); t.waived=false
 e.profile='P'; assert(TK.body(e,f)=='v=1;rule=0;used=-','outside a race: rule=0, nothing used'); e.profile='C'
 -- Composés roulés (usedDry du joueur, src/pits.lua), dans l'ordre des indices, noms nettoyés et coupés à 8 caractères.
 local slot=f.player; local a=f.cars[slot]
 a.tyreNames={[0]='S',[1]='M;=,x',[2]='SUPERSOFTX'}
 t.cars[slot].usedDry={}
 assert(field(TK.body(e,f),'used')=='-','none used: -')
 t.cars[slot].usedDry={[2]=true,[0]=true,[1]=true}
 assert(field(TK.body(e,f),'used')=='S,M___x,SUPERSOF','used list ('..TK.body(e,f)..')')
 assert(TK.clean('AB;C=D,E')=='AB_C_D_E' and TK.clean('123456789')=='12345678','sanitising')
 -- Borne de 160 octets : liste coupée sur des noms entiers, horodatage compris.
 local many={}; local used={}
 for i=0,K.maxTyreCompounds-1 do many[i]='ABCDEFGH'; used[i]=true end
 a.tyreNames=many; t.cars[slot].usedDry=used
 local text=TK.text(TK.body(e,f),99999.9)
 assert(#text<=TK.K.bytes,'at most 160 bytes ('..#text..')')
 assert(field(text,'used'):match('^ABCDEFGH[,ABCDEFGH]*$') and field(text,'stamp')=='99999.9','whole names, stamp last')
 a.tyreNames={[0]='S',[1]='M'}; t.cars[slot].usedDry={[0]=true}
 -- Rythme : au plus toutes les 0,5 s, seulement au changement, et au moins toutes les 5 s (horodatage vivant).
 local s=TK.new()
 local w1=TK.step(s,e,f,10)
 assert(w1=='v=1;rule=1;used=S;stamp=10.0','first write ('..tostring(w1)..')')
 t.cars[slot].usedDry={[0]=true,[1]=true}
 assert(TK.step(s,e,f,10.2)==nil,'not before 0.5 s, even after a change')
 assert(TK.step(s,e,f,10.6)=='v=1;rule=1;used=S,M;stamp=10.6','rewritten on change')
 assert(TK.step(s,e,f,11.2)==nil,'unchanged: not rewritten')
 assert(TK.step(s,e,f,15)==nil,'unchanged within 5 s')
 assert(TK.step(s,e,f,15.7)=='v=1;rule=1;used=S,M;stamp=15.7','refreshed after 5 s')
 assert(TK.closedText(20)=='v=1;rule=0;used=-;stamp=20.0','closing text')
 assert(TK.key=='AdvancedIA.tyres')
end

return tests
