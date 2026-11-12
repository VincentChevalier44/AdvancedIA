-- Beta 1.61, tranche A : zones (noms terminés par _161A). Chargé par tests/extended.lua.
-- Modèle unique de zone par circuit (src/zones.lua), fichier lu sans être cru, apprentissage avec « Mémoire des
-- circuits » (src/zonelearn.lua), champs par voiture lus par le directeur (s.zone).
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Z=require('src/zones')
local ZL=require('src/zonelearn')
local T=require('src/trackfile')
local FL=require('src/firstlap')
local K=C.K
local tests={}
local function user(kind,from,to,extra)
 local z={kind=kind,source='user',from=from,to=to or from,noYield=false,noOvertake=false,maxOffset=1,note=''}
 for key,value in pairs(extra or {}) do z[key]=value end
 return z
end
local function list(...) local zones={}; for _,z in ipairs({...}) do zones[#zones+1]=z end; zones.learnt={}; zones.serial=0; return Z.index(zones) end
local function file(sections,head)
 local h={kind='zones',track='test',layout='',length=10000,serial=5}
 for key,value in pairs(head or {}) do h[key]=value end
 return T.build('t',h,sections)
end
-- Mémoire des circuits en service dans une scène (réglage global livré par cette tranche).
local function memory(e,f,on)
 e.g.trackMemory=on; E.changed(e); f.trackKey='test'; f.layout=''; F.tick(e,f,0.05)
 assert(e.runtimeG.trackMemory==on,'track memory switch reaches the engine')
end
tests.ZONE_LEGACY_IDENTICAL_161A=function()
 local text='return { zones = { { from=0.10, to=0.20, noYield=true, noOvertake=false, maxOffset=0.4, note="a" }, { from=0.95, to=0.05, noYield=false, noOvertake=true, maxOffset=0.7 } } }'
 local legacy=assert(Z.parse(text))
 local merged=Z.merge(assert(Z.parse(text)),nil)
 assert(#merged==2 and not merged.extra and #merged.brakes==0 and merged[1].source=='file' and merged[1].kind=='nomove','file zones: no manoeuvre, source file')
 for _,progress in ipairs({0.0,0.03,0.07,0.1,0.15,0.2,0.21,0.5,0.96}) do
  local a=Z.at(legacy,progress,{}); local b=Z.at(merged,progress,{})
  assert(a.noYield==b.noYield and a.noOvertake==b.noOvertake and a.maxOffset==b.maxOffset,'same bound at '..progress)
  for key in pairs(b) do assert(key=='noYield' or key=='noOvertake' or key=='maxOffset','no new field with a legacy list: '..key) end
 end
 local out=Z.at(legacy,0.15,{}); assert(out.noYield and not out.noOvertake and out.maxOffset==0.4)
 out=Z.at(legacy,0.99,{}); assert(out.noOvertake and out.maxOffset==0.7,'range across the line')
 assert(Z.nextBrake(legacy,0.5)==nil and Z.brakeAhead(legacy,0.5)==nil and Z.attackAhead(legacy,0.5)==nil,'nothing known')
 -- COPY : le texte d'origine ne porte que les zones « sans manœuvre ».
 local mixed=list(user('nomove',0.1,0.2,{noYield=true}),user('attack',0.3,0.4),user('brake',0.5))
 local copy=Z.export(mixed); local back=assert(Z.parse(copy)); assert(#back==1 and back[1].from==0.1,'legacy text: no-manoeuvre zones only')
end
tests.ZONE_DECODE_VALID_161A=function()
 local text=file({
  {name='zone.1',kind='nomove',from=0.123,to=0.131,noYield=true,noOvertake=true,maxOffset=0.4,source='user',note='Narrow section'},
  {name='zone.2',kind='brake',from=0.0451,source='learnt',hits=14,sessions=3,last=5},
  {name='zone.3',kind='attack',from=0.3,to=0.34,source='user'},
  {name='zone.4',kind='line',from=0.5,to=0.55,source='user',side=-0.5,share=0.25,wet=true},
  {name='zone.5',kind='caution',from=0.7,to=0.72,source='learnt',hits=2,sessions=1,last=4,off=true},
 })
 local d=assert(Z.decode(text,'test','',10000))
 assert(#d.user==3 and #d.learnt==2 and d.serial==5 and d.ignored==0 and d.lengthOK==true,'counts')
 assert(d.user[1].noYield and d.user[1].maxOffset==0.4 and d.user[1].note=='Narrow section','no-manoeuvre fields')
 assert(d.user[3].side==-0.5 and d.user[3].share==0.25 and d.user[3].wet==true,'line fields')
 assert(d.learnt[1].kind=='brake' and d.learnt[1].to==d.learnt[1].from and d.learnt[1].hits==14 and d.learnt[1].sessions==3,'learnt counts')
 assert(d.learnt[2].off==true,'refused zone kept')
 local zones=Z.merge(nil,d)
 assert(zones.extra and zones.attackN==1 and zones.lineN==1 and zones.cautionN==0,'kinds counted, refused caution not applied')
 assert(#zones.brakes==1 and zones.brakes[1]==0.0451 and Z.nextBrake(zones,0.9)==0.0451,'confirmed braking point known')
 assert(math.abs(Z.brakeAhead(zones,0.9)-0.1451)<1e-9 and math.abs(Z.attackAhead(zones,0.25)-0.05)<1e-9,'distances ahead')
end
tests.ZONE_DECODE_REJECT_161A=function()
 local good={name='zone.1',kind='attack',from=0.3,to=0.34,source='user'}
 local d,why=Z.decode(string.rep('x',K.maxZoneBytes+1),'test','',10000); assert(not d and why=='taille','size')
 d,why=Z.decode(file({good},{kind='pace'}),'test','',10000); assert(not d and why=='format','another kind of file')
 d,why=Z.decode(file({good}):gsub('format=1','format=2'),'test','',10000); assert(not d and why=='format','format number')
 d,why=Z.decode(file({good}),'imola','',10000); assert(not d and why=='circuit','file of another track')
 d,why=Z.decode(file({good}),'test','gp',10000); assert(not d and why=='circuit','file of another layout')
 d,why=Z.decode('not a file','test','',10000); assert(not d and why=='syntaxe','syntax')
 d,why=Z.decode(nil,'test','',10000); assert(not d and why=='taille','no text')
 -- Zone fausse : écartée et comptée, le reste gardé.
 local bad={
  {name='zone.1',kind='attack',from=0.3,to=0.34,source='user',speed=12},     -- clé inconnue
  {name='zone.2',kind='attack',from=1.3,to=0.34,source='user'},              -- hors plage
  {name='zone.3',kind='attack',from=0.3,source='user'},                      -- fin manquante
  {name='zone.4',kind='warp',from=0.3,to=0.34,source='user'},                -- genre inconnu
  {name='zone.5',kind='attack',from=0.3,to=0.34,source='file'},              -- source refusée
  {name='zone.6',kind='line',from=0.3,to=0.34,source='learnt',side=0.5,hits=1,sessions=1,last=1}, -- jamais apprise
  {name='zone.7',kind='brake',from=0.3,source='learnt',hits=1,sessions=1,last=9},  -- datée après le fichier
  {name='zone.8',kind='brake',from=0.3,source='learnt',hits=1.5,sessions=1,last=1}, -- compte non entier
  {name='zone.9',kind='nomove',from=0.3,to=0.34,source='user',noYield='yes'}, -- booléen faux
  {name='zone.10',kind='line',from=0.3,to=0.34,source='user',side=2},         -- côté hors plage
  {name='zone.11',kind='line',from=0.3,to=0.34,source='user'},                -- côté manquant
  {name='zone.12',kind='attack',from=0.3,to=0.34,source='user',hits=3},       -- compte sur une zone du pilote
  {name='other.1',kind='attack',from=0.3,to=0.34,source='user'},             -- section inconnue
  good,
 }
 good.name='zone.14'
 d=assert(Z.decode(file(bad),'test','',10000))
 assert(#d.user==1 and #d.learnt==0 and d.ignored==13,'bad zones dropped and counted: '..#d.user..' '..d.ignored)
 -- Plafonds : zones du pilote, points de freinage, zones d'attaque, zones apprises.
 local many={}
 for k=1,K.maxZones+1 do many[#many+1]={name='zone.'..k,kind='nomove',from=0.1,to=0.2,source='user'} end
 d=assert(Z.decode(file(many),'test','',10000)); assert(#d.user==K.maxZones and d.ignored==1,'user zone cap')
 many={}
 for k=1,K.zoneBrakeMax+2 do many[#many+1]={name='zone.'..k,kind='brake',from=k/100,source='learnt',hits=1,sessions=2,last=1} end
 d=assert(Z.decode(file(many),'test','',10000)); assert(#d.learnt==K.zoneBrakeMax and d.ignored==2,'braking point cap')
 many={}
 for k=1,K.attackMax+1 do many[#many+1]={name='zone.'..k,kind='attack',from=k/100,to=k/100+0.005,source='user'} end
 d=assert(Z.decode(file(many),'test','',10000)); assert(#d.user==K.attackMax and d.ignored==1,'attack zone cap')
 many={}
 for k=1,K.zoneLearntMax+3 do many[#many+1]={name='zone.'..k,kind='caution',from=k/200,to=k/200+0.001,source='learnt',hits=1,sessions=2,last=1} end
 d=assert(Z.decode(file(many),'test','',10000)); assert(#d.learnt==K.zoneLearntMax and d.ignored==3,'learnt zone cap')
 -- Note : coupée, sans caractère de contrôle.
 d=assert(Z.decode(file({{name='zone.1',kind='attack',from=0.3,to=0.34,source='user',note=string.rep('n',K.zoneNote+20)..'\n'}}),'test','',10000))
 assert(#d.user[1].note==K.zoneNote,'note cut')
end
tests.ZONE_LENGTH_CHANGED_161A=function()
 local text=file({{name='zone.1',kind='attack',from=0.3,to=0.34,source='user'},{name='zone.2',kind='brake',from=0.5,source='learnt',hits=9,sessions=3,last=2}})
 local d=assert(Z.decode(text,'test','',10000*(1+K.trackLengthTol*0.9))); assert(d.lengthOK and #d.learnt==1,'within the tolerance')
 d=assert(Z.decode(text,'test','',10000*(1+K.trackLengthTol*1.5))); assert(d.lengthOK==false and #d.learnt==0 and #d.user==1 and d.ignored==1,'length changed: learnt dropped, user kept')
 d=assert(Z.decode(text,'test','',0)); assert(d.lengthOK==false and #d.learnt==0,'length unknown: learnt dropped')
end
tests.ZONE_ENCODE_ROUNDTRIP_161A=function()
 local zones=list(user('nomove',0.1,0.2,{noYield=true,noOvertake=true,maxOffset=0.4,note='pit wall'}),user('attack',0.3,0.34),user('line',0.5,0.55,{side=0.75,share=0.3,wet=true}),user('caution',0.6,0.62,{off=true}),user('brake',0.8))
 zones.learnt[1]={kind='brake',source='learnt',from=0.045,to=0.045,hits=14,sessions=3,last=4}
 zones.learnt[2]={kind='attack',source='learnt',from=0.9,to=0.95,hits=2,sessions=0,last=0} -- pas encore comptée : pas écrite
 zones.learnt[3]={kind='caution',source='learnt',from=0.7,to=0.72,hits=1,sessions=0,last=0,off=true} -- refusée : gardée
 Z.index(zones)
 local text,count=Z.encode(zones,{track='test',layout='gp',length=4909,serial=6})
 assert(count==7 and #text<K.maxZoneBytes,'user zones, counted learnt zones and refused ones: '..count)
 local d=assert(Z.decode(text,'test','gp',4909)); assert(d.serial==6 and #d.user==5 and #d.learnt==2 and d.ignored==0,'read back')
 local back=Z.merge(nil,d)
 for _,progress in ipairs({0.05,0.15,0.32,0.52,0.61,0.8,0.97}) do
  local a=Z.at(zones,progress,{}); local b=Z.at(back,progress,{})
  assert(a.noYield==b.noYield and a.noOvertake==b.noOvertake and a.maxOffset==b.maxOffset and a.caution==b.caution and a.passMargin==b.passMargin and (a.line and a.line.side)==(b.line and b.line.side),'same zones at '..progress)
 end
 assert(#back.brakes==2 and back.brakes[1]==0.045 and back.brakes[2]==0.8,'braking points back, sorted')
 assert(Z.encode(back,{track='test',layout='gp',length=4909,serial=6})==text,'stable text')
end
tests.ZONE_FILE_SOURCE_NEVER_WRITTEN_161A=function()
 local legacy=assert(Z.parse('return { { from=0.10, to=0.20, noYield=true } }'))
 local zones=Z.merge(legacy,{user={user('attack',0.3,0.34)},learnt={},serial=1})
 local text,count=Z.encode(zones,{track='test',layout='',length=10000,serial=1})
 assert(count==1 and not text:find('nomove',1,true) and text:find('kind=attack',1,true),'the legacy file zones are never written')
 -- Liste d'origine seule (aucun fichier nouveau) : rien à écrire.
 local _,none=Z.encode(legacy,{track='test',layout='',length=10000,serial=0}); assert(none==0)
end
-- Contrat lu par la tranche C (src/nuance.lua, src/director.lua) : Zones.nextBrake(zones,progress) et
-- Zones.nextAttack(zones,progress) rendent la progression (0 à 1) du prochain point de freinage et du début de la
-- prochaine zone d'attaque devant progress ; nil quand rien n'est connu (liste d'origine, liste vide, nil).
tests.ZONE_NEXT_BRAKE_161A=function()
 for _,zones in ipairs({{},assert(Z.parse('return { { from=0.10, to=0.20, noYield=true } }')),list()}) do assert(Z.nextBrake(zones,0.5)==nil,'no braking point known') end
 assert(Z.nextBrake(nil,0.5)==nil,'no list')
 local zones=list(user('brake',0.30),user('brake',0.80),user('brake',0.55,nil,{off=true}))
 zones.learnt[1]={kind='brake',source='learnt',from=0.10,to=0.10,hits=9,sessions=K.zoneConfirmSessions,last=0}
 zones.learnt[2]={kind='brake',source='learnt',from=0.60,to=0.60,hits=9,sessions=K.zoneConfirmSessions-1,last=0}
 Z.index(zones)
 assert(Z.nextBrake(zones,0.05)==0.10 and Z.nextBrake(zones,0.10)==0.30 and Z.nextBrake(zones,0.29)==0.30,'next point ahead, strictly after the car')
 assert(Z.nextBrake(zones,0.31)==0.80,'a point switched off and a learnt point not yet confirmed are not known')
 assert(Z.nextBrake(zones,0.85)==0.10,'across the line')
 local at=Z.nextBrake(zones,0.95); assert(math.abs(((at-0.95)%1)*5000-750)<1e-6,'distance as slice C computes it')
end
tests.ZONE_NEXT_ATTACK_161A=function()
 for _,zones in ipairs({{},assert(Z.parse('return { { from=0.10, to=0.20, noYield=true } }')),list(user('brake',0.3),user('caution',0.4,0.5))}) do assert(Z.nextAttack(zones,0.5)==nil,'no attack zone known') end
 assert(Z.nextAttack(nil,0.5)==nil,'no list')
 local zones=list(user('attack',0.30,0.36),user('attack',0.70,0.75),user('attack',0.50,0.55,{off=true}))
 zones.learnt[1]={kind='attack',source='learnt',from=0.90,to=0.95,hits=9,sessions=K.zoneConfirmSessions,last=0}
 zones.learnt[2]={kind='attack',source='learnt',from=0.10,to=0.15,hits=9,sessions=K.zoneConfirmSessions-1,last=0}
 Z.index(zones)
 assert(Z.nextAttack(zones,0.2)==0.30 and Z.nextAttack(zones,0.32)==0.70,'start of the next zone ahead; inside a zone: the one after')
 assert(Z.nextAttack(zones,0.45)==0.70,'zone switched off: not known')
 assert(Z.nextAttack(zones,0.8)==0.90 and Z.nextAttack(zones,0.96)==0.30,'confirmed learnt zone known, unconfirmed one not; across the line')
 local at=Z.nextAttack(zones,0.98); assert(math.abs(((at-0.98)%1)*10000-3200)<1e-6,'distance as slice C computes it')
end
tests.ZONE_KINDS_AT_161A=function()
 local zones=list(user('attack',0.30,0.40),user('nomove',0.35,0.37,{noOvertake=true}),user('caution',0.38,0.39),user('attack',0.60,0.70,{off=true}))
 local out={}
 Z.at(zones,0.32,out); assert(out.passMargin==K.attackMargin and K.attackMargin<1 and out.attack and not out.caution,'attack zone: margin')
 Z.at(zones,0.36,out); assert(out.passMargin==nil and out.noOvertake,'no manoeuvre wins over attack')
 Z.at(zones,0.385,out); assert(out.passMargin==nil and out.caution==true,'caution wins over attack')
 Z.at(zones,0.65,out); assert(out.passMargin==nil and not out.attack,'zone switched off: not applied')
 Z.at(zones,0.5,out); assert(out.passMargin==nil and out.caution==nil and out.line==nil and out.maxOffset==1,'outside')
 -- Pause du départ : points difficiles suspendus, comme les points appris en direct.
 zones.cautionPause=true; Z.at(zones,0.385,out); assert(out.caution==nil and out.passMargin==K.attackMargin,'caution paused at the start')
 zones.cautionPause=false
 -- Voiture de devant déjà attaquée par une autre : pas de marge.
 out.noBoost=true; Z.at(zones,0.32,out); assert(out.passMargin==nil,'target already under attack: no margin'); out.noBoost=nil
 -- Champs décidés après le pilotage (image d'avant), recopiés ; effacés quand la liste redevient d'origine.
 out.waitNext=true; out.lineNext=0.1; Z.at(zones,0.5,out); assert(out.passWait==true and out.lineOffset==0.1)
 Z.at({},0.5,out); assert(out.passWait==nil and out.lineOffset==nil and out.waitNext==nil and out.lineNext==nil and out.caution==nil and out.zoned==nil,'new fields cleared with a plain list')
end
tests.ZONE_CAUTION_SAME_AS_HOTSPOT_161A=function()
 local e,f=F.scene('P',3)
 F.tick(e,f,0.3); assert(e.states[2].hotspot==false,'no spot')
 e.zones=list(user('caution',0.99,0.01))
 F.tick(e,f,0.3); assert(e.states[2].hotspot==true and e.states[2].zone.caution==true,'caution zone: same state as a difficult spot')
 assert(e.states[3].hotspot==false,'car outside the zone')
 e.zones[1].off=true; Z.index(e.zones)
 F.tick(e,f,0.3); assert(e.states[2].hotspot==false,'zone switched off')
 -- Pause du départ et des relances, comme les points difficiles appris en direct.
 e.zones[1].off=nil; Z.index(e.zones); f.started=false
 F.tick(e,f,0.3); assert(e.zones.cautionPause==true and e.states[2].hotspot==false,'paused before the start')
end
tests.ZONE_ATTACK_WAIT_161A=function()
 local function scene(sa,zoneFrom)
  local e,f=F.scene('C',3)
  e.zones=list(user('attack',zoneFrom or 0.015,0.06))
  F.front(e,f,20,sa)
  return e,f
 end
 -- Zone d'attaque à 150 m, voiture à 115 km/h : moins de K.attackWaitTime s : le dépassement attend.
 local e,f=scene(15); F.tick(e,f,0.5)
 assert(e.states[2].zone.passWait==true and e.zonelearn.held==1,'pass held for the attack zone just ahead')
 assert(not F.passing(e.states[2].state),'no pass started while waiting')
 -- Zone trop loin : pas d'attente.
 e,f=scene(15,0.05); F.tick(e,f,0.5); assert(e.states[2].zone.passWait==nil,'zone further than the wait time')
 -- Dans la zone : pas d'attente, marge réduite.
 e,f=scene(15); F.place(f,2,200,115); F.place(f,3,224.4,100); e.states[2].nextPerception=0; F.tick(e,f,0.5)
 assert(e.states[2].zone.passWait==nil and e.states[2].zone.passMargin==K.attackMargin,'inside the zone')
 -- Dans une zone d'attaque, avec une autre zone toute proche devant : on attaque ici, on n'attend pas la suivante.
 e,f=scene(15); e.zones=list(user('attack',0.015,0.03),user('attack',0.035,0.06))
 F.place(f,2,200,115); F.place(f,3,224.4,100); e.states[2].nextPerception=0; F.tick(e,f,0.5)
 assert(e.states[2].zone.attack==true and e.states[2].zone.passWait==nil,'inside a zone: no wait for the next one')
 -- Jamais d'attente : rapprochement franc.
 e,f=scene(K.attackNoWaitSa+10); F.tick(e,f,0.5); assert(e.states[2].zone.passWait==nil,'fast closing: no wait')
 -- Jamais d'attente : voiture à un tour devant.
 e,f=scene(15); f.cars[2].lap=f.cars[3].lap+1; F.tick(e,f,0.5); assert(e.states[2].zone.passWait==nil,'lapping: no wait')
 -- Jamais d'attente : retenue depuis K.attackStuckTime s.
 e,f=scene(0); F.tick(e,f,0.5); assert(e.states[2].zone.passWait==true)
 F.tick(e,f,K.attackStuckTime); assert(e.states[2].zone.passWait==nil and e.states[2].zlStuck>=K.attackStuckTime,'held up for long: no wait')
 -- Voiture de devant tenue par une autre attaquante engagée : pas de marge pour une troisième.
 e,f=scene(15); F.place(f,2,200,115); F.place(f,3,224.4,100); e.states[2].nextPerception=0
 e.states[3].heldBy=1; e.states[3].heldUntil=1e9
 F.tick(e,f,0.5); assert(e.states[2].zone.noBoost==true and e.states[2].zone.passMargin==nil,'target already held by another attacker')
end
tests.ZONE_LINE_SHARE_WET_161A=function()
 local function scene(extra)
  local e,f=F.scene('P',3)
  local z={side=1,share=1}; for key,value in pairs(extra or {}) do z[key]=value end
  e.zones=list(user('line',0.99,0.02,z))
  return e,f
 end
 local e,f=scene()
 F.tick(e,f,0.2); local early=e.states[2].zone.lineOffset
 assert(early and early>0 and early<K.baseMax,'line ramped in, not stepped')
 F.tick(e,f,K.lineRamp+0.5)
 assert(math.abs(e.states[2].zone.lineOffset-K.baseMax)<1e-9 and e.zonelearn.lines==1,'line reached, bounded by the base line limit')
 assert(e.states[3].zone.lineOffset==nil,'car outside the zone')
 -- Sortie de la zone : rendue progressivement.
 F.place(f,2,3000,100); F.tick(e,f,0.2)
 local leaving=e.states[2].zone.lineOffset; assert(leaving and leaving<K.baseMax and leaving>0,'ramped out')
 F.tick(e,f,K.lineRamp+0.5); assert(e.states[2].zone.lineOffset==nil,'back on the line')
 -- Part des IA : aucune avec 0.
 e,f=scene({share=0}); F.tick(e,f,1); assert(e.states[2].zone.lineOffset==nil,'share 0: nobody')
 -- Ligne du mouillé : seulement piste mouillée.
 e,f=scene({wet=true}); F.tick(e,f,1); assert(e.states[2].zone.lineOffset==nil,'wet line on a dry track: no')
 f.wet=0.6; F.tick(e,f,1); assert((e.states[2].zone.lineOffset or 0)>0,'wet line on a wet track')
 -- Côté gauche, et borne d'une zone sans manœuvre au même endroit.
 e,f=scene({side=-1}); e.zones[#e.zones+1]=user('nomove',0.99,0.02,{maxOffset=0.1}); Z.index(e.zones)
 F.tick(e,f,K.lineRamp+0.5); assert(math.abs(e.states[2].zone.lineOffset+0.1)<1e-9,'left side, clamped by the no-manoeuvre bound')
 -- Voiture à côté : jamais.
 e,f=scene(); F.place(f,3,0,100,3); e.states[2].nextPerception=0; F.tick(e,f,1)
 assert(e.states[2].zone.lineOffset==nil,'never with a car alongside')
end
tests.BRAKE_LEARN_HITS_161A=function()
 local e,f=F.scene('P',4); memory(e,f,true)
 F.tick(e,f,0.2)
 local zones=e.zones; local t=e.zonelearn
 assert(zones.learnt and #zones.learnt==0 and #zones.brakes==0,'list prepared, nothing learnt')
 -- Une seule voiture : jamais assez ; deux voitures et K.brakeLearnHits freinages : comptée une session.
 for _=1,K.brakeLearnHits+2 do ZL.brake(t,zones,0.5,f.length,2,e,e.time) end
 assert(#zones.learnt==1 and zones.learnt[1].sessions==0 and not zones.dirty,'one car is not enough')
 ZL.brake(t,zones,0.5+K.firstLapPointMerge*0.5/f.length,f.length,3,e,e.time)
 local z=zones.learnt[1]
 assert(#zones.learnt==1 and z.sessions==1 and z.counted and zones.dirty,'merged with the neighbour point, counted once')
 assert(#zones.brakes==0 and FL.nextPoint(e.fl,f.cars[2],f.length)==math.huge,'one session: not applied yet')
 ZL.brake(t,zones,0.5,f.length,4,e,e.time); assert(z.sessions==1,'counted once per session')
 -- Point éloigné : un autre point.
 ZL.brake(t,zones,0.7,f.length,2,e,e.time); assert(#zones.learnt==2,'another place')
 -- Nouvelle session : soldée et enregistrement demandé ; deuxième session confirmée : point connu dès le premier tour.
 ZL.reset(t,e.time); F.tick(e,f,0.1)
 assert(e.zoneSaveAsk=='learn' and zones.serial==1 and z.last==1 and not z.counted,'session settled, save asked')
 e.zoneSaveAsk=nil
 for k=1,K.brakeLearnHits do ZL.brake(t,zones,0.5,f.length,2+k%2,e,e.time) end
 assert(z.sessions==2 and #zones.brakes==1,'second session: confirmed and applied')
 F.tick(e,f,0.1)
 local d=FL.nextPoint(e.fl,f.cars[2],f.length)
 assert(math.abs(d-5000)<1,'known to the careful first lap: '..d)
 assert(Z.nextBrake(zones,0.2)==0.5,'known to the other modules')
end
tests.BRAKE_LEARNT_IN_SCENE_161A=function()
 -- Freinage d'une IA libre depuis une ligne droite : appris toute la session, seulement avec la mémoire.
 for _,on in ipairs({false,true}) do
  local e,f=F.scene('P',3); memory(e,f,on)
  F.tick(e,f,0.2)
  for k=1,3 do
   f.cars[2].brake=0; f.cars[3].brake=0; F.tick(e,f,0.1)
   f.cars[2].brake=0.8; f.cars[3].brake=0.8; F.tick(e,f,0.1)
   if k==1 then f.cars[3].spline=f.cars[2].spline end
  end
  local n=e.zones.learnt and #e.zones.learnt or 0
  if on then assert(n>=1 and e.zones.learnt[1].kind=='brake' and e.zones.learnt[1].hits>=3,'braking points learnt with track memory: '..n)
  else assert(n==0 and e.zoneSaveAsk==nil and e.zones.learnt==nil,'track memory off: nothing learnt, nothing prepared') end
 end
end
tests.ATTACK_LEARN_CLUSTER_161A=function()
 local e,f=F.scene('C',3); memory(e,f,true)
 F.tick(e,f,0.2)
 local zones=e.zones; local t=e.zonelearn
 zones.learnt[1]={kind='brake',source='learnt',from=0.53,to=0.53,hits=9,sessions=2,last=0}; Z.index(zones)
 for k=1,K.attackLearnPasses-1 do ZL.pass(t,zones,0.5+k*20/f.length,f.length,e,e.time) end
 local z=zones.learnt[2]
 assert(#zones.learnt==2 and z.kind=='attack' and z.sessions==0,'cluster of passes, not enough yet')
 ZL.pass(t,zones,0.5,f.length,e,e.time)
 assert(z.sessions==1 and z.counted,'enough passes: counted')
 local span=((z.to-z.from)%1)*f.length
 assert(span>=K.attackMinMeters-1e-6 and span<=K.attackMaxMeters+1e-6,'bounded length: '..span)
 assert(math.abs(z.to-0.53)<1e-9,'ends at the next known braking point')
 -- Dépassement loin de là : une autre zone ; plafond du nombre de zones d'attaque.
 for k=1,K.attackMax+3 do ZL.pass(t,zones,(0.6+k*0.04)%1,f.length,e,e.time) end
 local attacks=0; for _,q in ipairs(zones.learnt) do if q.kind=='attack' then attacks=attacks+1 end end
 assert(attacks==K.attackMax,'attack zone cap: '..attacks)
 -- Dans la scène : le dépassement réussi signalé par le directeur (e.passDone) est lu en course seulement.
 local before=z.hits
 f.cars[2].spline=0.5; e.passDone=2; ZL.step(t,e,f,e.time,1/60); assert(z.hits==before+1,'pass flag read in the race')
 e.profile='P'; e.passDone=2; ZL.step(t,e,f,e.time,1/60); assert(z.hits==before+1,'not outside the race')
end
tests.CAUTION_CONFIRM_TWO_SESSIONS_161A=function()
 local e,f=F.scene('P',3); memory(e,f,true)
 F.tick(e,f,0.2)
 local zones=e.zones; local t=e.zonelearn; local inc=e.incidents
 -- Point difficile armé en direct : gardé (une session).
 inc.hotspotArmedN=(inc.hotspotArmedN or 0)+1; inc.hotspotArmedAt=0.4
 F.tick(e,f,0.1)
 local z=zones.learnt[1]
 assert(z and z.kind=='caution' and z.sessions==1 and not zones.extra,'armed spot kept, not applied after one session')
 inc.hotspotArmedN=inc.hotspotArmedN+1; inc.hotspotArmedAt=0.4+K.hotspotMeters*0.5/f.length
 F.tick(e,f,0.1); assert(#zones.learnt==1 and z.sessions==1 and z.hits==2,'same spot, same session: one session')
 ZL.reset(t,e.time); F.tick(e,f,0.1); e.zoneSaveAsk=nil
 inc.hotspotArmedN=inc.hotspotArmedN+1; inc.hotspotArmedAt=0.4
 F.tick(e,f,0.1)
 assert(z.sessions==K.zoneConfirmSessions and zones.extra and zones.cautionN==1,'second session: confirmed, applied')
 local out={}; Z.at(zones,0.4,out); assert(out.caution==true,'applied at the spot')
 Z.at(zones,0.4+3*K.hotspotMeters/f.length,out); assert(out.caution==nil,'not further away')
end
tests.ZONE_FORGET_161A=function()
 local e,f=F.scene('P',3); memory(e,f,true)
 F.tick(e,f,0.2)
 local zones=e.zones; local t=e.zonelearn
 zones.serial=20
 zones.learnt[1]={kind='brake',source='learnt',from=0.2,to=0.2,hits=30,sessions=4,last=21-K.zoneForgetSessions}     -- oubliée
 zones.learnt[2]={kind='brake',source='learnt',from=0.4,to=0.4,hits=30,sessions=4,last=22-K.zoneForgetSessions}     -- encore gardée
 zones.learnt[3]={kind='caution',source='learnt',from=0.6,to=0.62,hits=3,sessions=4,last=0,off=true}               -- refusée : gardée
 zones.learnt[4]={kind='attack',source='learnt',from=0.7,to=0.75,hits=1,sessions=0,last=0}                         -- pas encore comptée
 Z.index(zones); assert(#zones.brakes==2)
 ZL.settle(t,zones,f.length,e,e.time)
 assert(zones.serial==21 and #zones.learnt==3 and zones.learnt[1].from==0.4 and #zones.brakes==1 and t.forgotten==1,'not confirmed for too long: forgotten')
 ZL.settle(t,zones,f.length,e,e.time); assert(zones.serial==21,'serial advances once per session')
 -- Zone confirmée dans la session : datée, donc gardée.
 zones.learnt[1].counted=true; zones.bumped=nil; ZL.settle(t,zones,f.length,e,e.time)
 assert(zones.serial==22 and zones.learnt[1].last==22 and #zones.learnt==3,'confirmed zone dated')
 -- Une session avec la mémoire compte pour l'oubli même sans rien apprendre : enregistrement demandé.
 local e2,f2=F.scene('P',3); memory(e2,f2,true)
 e2.zones=Z.merge(nil,{user={},learnt={{kind='brake',source='learnt',from=0.2,to=0.2,hits=30,sessions=4,last=3}},serial=3})
 ZL.reset(e2.zonelearn,e2.time); F.tick(e2,f2,0.1); assert(e2.zones.dirty==true and e2.zoneSaveAsk==nil,'a session with track memory counts')
 ZL.reset(e2.zonelearn,e2.time); F.tick(e2,f2,0.1); assert(e2.zoneSaveAsk=='learn' and e2.zones.serial==4,'saved at the session change')
end
tests.ZONE_OFF_NOT_RELEARNT_161A=function()
 local e,f=F.scene('C',3); memory(e,f,true)
 F.tick(e,f,0.2)
 local zones=e.zones; local t=e.zonelearn
 zones.learnt[1]={kind='brake',source='learnt',from=0.5,to=0.5,hits=10,sessions=3,last=0,off=true}
 zones.learnt[2]={kind='attack',source='learnt',from=0.2,to=0.25,hits=10,sessions=3,last=0,off=true}
 zones.learnt[3]={kind='caution',source='learnt',from=0.79,to=0.81,hits=10,sessions=3,last=0,off=true}
 Z.index(zones); assert(#zones.brakes==0 and not zones.extra,'refused zones are not applied')
 for k=1,K.brakeLearnHits+2 do ZL.brake(t,zones,0.5,f.length,2+k%2,e,e.time) end
 for _=1,K.attackLearnPasses+2 do ZL.pass(t,zones,0.22,f.length,e,e.time) end
 ZL.caution(t,zones,0.8,f.length,e,e.time)
 assert(#zones.learnt==3 and zones.learnt[1].hits==10 and zones.learnt[2].hits==10 and zones.learnt[3].hits==10 and not zones.dirty,'a refused zone is not learnt again')
 assert(#zones.brakes==0 and not zones.extra)
end
tests.ZONE_NO_WRITE_MEMORY_OFF_161A=function()
 -- Mémoire coupée (défaut) : rien n'est appris, aucun enregistrement demandé, même avec un fichier de zones.
 local e,f=F.scene('C',3); f.trackKey='test'; f.layout=''
 assert(e.runtimeG.trackMemory==false,'off by default')
 e.zones=Z.merge(nil,{user={user('attack',0.3,0.34)},learnt={{kind='brake',source='learnt',from=0.5,to=0.5,hits=10,sessions=3,last=1}},serial=1})
 local inc=e.incidents
 for _=1,4 do
  f.cars[2].brake=0; F.tick(e,f,0.1); f.cars[2].brake=0.8; F.tick(e,f,0.1)
  inc.hotspotArmedN=(inc.hotspotArmedN or 0)+1; inc.hotspotArmedAt=0.4; e.passDone=2
  ZL.step(e.zonelearn,e,f,e.time,1/60)
 end
 ZL.reset(e.zonelearn,e.time); F.tick(e,f,0.2)
 assert(#e.zones.learnt==1 and e.zones.learnt[1].hits==10 and e.zoneSaveAsk==nil and not e.zones.dirty and e.zones.serial==1,'memory off: nothing learnt, nothing saved')
 assert(#e.zones.brakes==1 and e.zones.attackN==1,'the zones of the file still act')
 -- Hors ligne seulement, jamais en rediffusion, jamais sans clé de circuit.
 for _,case in ipairs({'online','replay','key'}) do
  local e2,f2=F.scene('P',3); memory(e2,f2,true)
  F.tick(e2,f2,0.2)
  if case=='key' then f2.trackKey='' else f2[case]=true end
  e2.incidents.hotspotArmedN=(e2.incidents.hotspotArmedN or 0)+1; e2.incidents.hotspotArmedAt=0.4
  ZL.step(e2.zonelearn,e2,f2,e2.time,1/60)
  assert(#e2.zones.learnt==0 and e2.zoneSaveAsk==nil,'nothing learnt: '..case)
 end
end
return tests
