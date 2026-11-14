-- Beta 1.63 (accord avec SetupLab) : clé annexe « AdvancedIA.session » (src/sessionkey.lua). Noms terminés par _163K.
-- Chargé par tests/extended.lua. Le moteur tourne sur la scène de test ; la clé est construite à partir de son état.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local SK=require('src/sessionkey')
local K=C.K
local tests={}
local function field(text,name) return (';'..text):match(';'..name..'=([^;]*)') end
local function cross(e,f,s,lap)
 f.cars[1].lap=lap; F.tick(e,f,0.1); SK.player(s,e,f)
end

-- Tour sali par une VSC : playerLapClean faux pendant le tour, puis lastLapClean faux après la ligne avec le bon numéro ;
-- tour suivant propre : lastLapClean vrai après la ligne suivante.
tests.SESSION_KEY_LAP_DIRTY_THEN_CLEAN_163K=function()
 local e,f=F.scene('C',3)
 local s=SK.new()
 F.tick(e,f,0.1); SK.player(s,e,f)
 local lap0=f.cars[1].lap
 assert(s.lapId==lap0 and s.clean==true,'lap in progress starts clean')
 e.incidents.neutral=true; e.incidents.neutralMode='vsc'
 SK.player(s,e,f)
 assert(s.clean==false and s.reason=='vsc','VSC dirties the lap in progress')
 e.incidents.neutral=false; e.incidents.neutralMode=''
 cross(e,f,s,lap0+1)
 assert(s.lastId==lap0 and s.lastClean==false and s.lapId==lap0+1 and s.clean==true,'completed lap kept dirty, new lap clean')
 local text=SK.text(s,e,f)
 assert(text:sub(1,4)=='v=1;','version first')
 assert(field(text,'lastLapId')==tostring(lap0) and field(text,'lastLapClean')=='0' and field(text,'playerLapClean')=='1' and field(text,'reason')=='vsc',text)
 cross(e,f,s,lap0+2)
 assert(s.lastId==lap0+1 and s.lastClean==true,'clean lap reported clean')
 assert(field(SK.text(s,e,f),'session')=='C','race profile letter')
end

-- Chaque cause : rouge, voiture de sécurité, delta, pénalité native en cours, drapeau noir, zone jaune du joueur.
tests.SESSION_KEY_REASONS_163K=function()
 local e,f=F.scene('C',3)
 local t=e.incidents
 local function r() return SK.dirt(e,f) end
 assert(r()==nil,'nothing on a clean track')
 t.red=true; assert(r()=='red'); t.red=false
 t.neutral=true; t.neutralMode='sc'; assert(r()=='sc'); t.neutralMode='fcy'; assert(r()=='fcy'); t.neutralMode='local'; assert(r()=='yellow'); t.neutral=false
 e.delta.value=1.5; assert(r()=='delta'); e.delta.value=nil
 f.cars[1].penaltyType=2; assert(r()=='slowdown'); f.cars[1].penaltyType=K.penaltyBlackFlag; assert(r()=='blackflag'); f.cars[1].penaltyType=0
 t.playerYellow=true; assert(r()=='yellow'); t.playerYellow=false
 t.formation=true; assert(r()=='formation'); t.formation=false
end

-- DRS coupé par les règles : drsAllowed=0 ; changement de gomme obligatoire en course seulement, plus dû une fois fait.
tests.SESSION_KEY_DRS_AND_COMPOUND_163K=function()
 local e,f=F.scene('C',3)
 local s=SK.new()
 F.tick(e,f,0.1)
 e.commands[1].drsBlock=true
 assert(field(SK.text(s,e,f),'drsAllowed')=='0','DRS cut by the rules')
 e.commands[1].drsBlock=false
 assert(field(SK.text(s,e,f),'drsAllowed')=='1')
 e.run.pitCompoundChange=true; e.run.mandatoryStops=1; e.pits.state='open'; e.pits.waived=false
 e.pits.cars[1].windowStops=0
 assert(field(SK.text(s,e,f),'compoundChange')=='1','owed in the race')
 e.pits.cars[1].windowStops=1
 assert(field(SK.text(s,e,f),'compoundChange')=='0','done')
 e.pits.cars[1].windowStops=0; e.pits.waived=true
 local text=SK.text(s,e,f)
 assert(field(text,'compoundChange')=='0' and field(text,'wetWaived')=='1','waived by rain')
 local eq,fq=F.scene('Q',3)
 eq.run.pitCompoundChange=true; eq.run.mandatoryStops=1; eq.pits.state='open'
 assert(field(SK.text(SK.new(),eq,fq),'compoundChange')=='0' and field(SK.text(SK.new(),eq,fq),'session')=='Q','never outside the race')
end

-- Allure moyenne des IA : tours propres comptés ; tour avec passage aux stands, premier tour de course et tour sous
-- neutralisation exclus.
tests.SESSION_KEY_AI_LAP_MEAN_163K=function()
 local e,f=F.scene('C',3)
 local s=SK.new()
 local a2,a3=f.cars[2],f.cars[3]
 a2.lap=0; a3.lap=0
 SK.ai(s,e,f)
 -- Premier tour d'une course : exclu.
 a2.lap=1; a2.lastLap=95; a3.lap=1; a3.lastLap=96; SK.ai(s,e,f)
 assert(s.count==0,'first race lap excluded')
 -- Tour propre de la voiture 2 ; tour de la voiture 3 avec passage dans la voie des stands.
 a3.pit=true; SK.ai(s,e,f); a3.pit=false
 a2.lap=2; a2.lastLap=90; a3.lap=2; a3.lastLap=120; SK.ai(s,e,f)
 assert(s.count==1 and math.abs(s.sum-90)<1e-9,'pit lap excluded, clean lap counted')
 -- Tour sous neutralisation : exclu.
 e.incidents.neutral=true; e.incidents.neutralMode='vsc'; SK.ai(s,e,f); e.incidents.neutral=false
 a2.lap=3; a2.lastLap=110; SK.ai(s,e,f)
 assert(s.count==1,'neutralised lap excluded')
 a2.lap=4; a2.lastLap=92; SK.ai(s,e,f)
 local text=SK.text(s,e,f)
 assert(field(text,'aiLapCount')=='2' and field(text,'aiLapMean')=='91.000',text)
end

-- Écriture : au plus toutes les K.period s, seulement quand le texte change ; nouvelle session : tout repart de zéro.
tests.SESSION_KEY_RATE_AND_RESET_163K=function()
 local e,f=F.scene('C',3)
 local s=SK.new()
 F.tick(e,f,0.1)
 assert(SK.step(s,e,f,10)~=nil,'first write')
 assert(SK.step(s,e,f,10.2)==nil,'not before the period')
 assert(SK.step(s,e,f,10.6)==nil,'unchanged text not rewritten')
 e.commands[1].drsBlock=true
 assert(SK.step(s,e,f,11.2)~=nil,'changed text written after the period')
 s.count=3; s.sum=300; s.lastId=5
 f.session=1; SK.player(s,e,f)
 assert(s.count==0 and s.lastId==-1,'new session resets')
 assert(SK.closedText=='v=1;closed=1')
end
return tests
