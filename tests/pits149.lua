-- Beta 1.49 (Monza, 5 novembre, 09:55, règles F1) : arrêt obligatoire du joueur refusé (même composé remonté) sans
-- explication. Composé suivi jusqu'à la sortie de la voie des stands plus K.pitCompoundGrace s, composés nommés au
-- journal, avis de l'overlay (validé, même composé), rappel avant l'entrée des stands, stratégie des stands (menu
-- Quick Pitstop, src/pitplan.lua). Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Pitplan=require('src/pitplan')
local L=require('src/lang')
local LE=require('src/lang_en')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Course F1 (fenêtre ouverte, tour 5 / 10), joueur (1) en SS avec S et M disponibles, à l'arrêt dans la voie des stands.
local function race(f1)
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); C.applyRules('F1',e.profiles)
 if f1==false then e.profiles.C.pitCompoundChange=false end
 E.changed(e); f.sessionLaps=10; f.leaderLaps=5
 local a=f.cars[1]; a.compoundIndex=0; a.tyresKnown=true
 a.tyreNames={[0]='SS',[1]='S',[2]='M'}; a.dryList={0,1,2}; a.dryCompounds={[0]=true,[1]=true,[2]=true}
 F.tick(e,f,0.5)
 return e,f,a
end
local function arrive(e,f,a) a.pit=true; a.inPitBox=true; a.kmh=0; F.tick(e,f,0.5) end
tests.PIT_COMPOUND_149=function()
 -- Composé changé une seconde après la sortie de l'emplacement, encore dans la voie : compté, composés nommés, avis.
 local e,f,a=race()
 arrive(e,f,a); assert(e.pits.cars[1].windowStops==0,'not counted at the box arrival (F1)')
 assert(count(e,'compte au changement de compose (arrivee en SS)')==1,'arrival line names the compound')
 a.inPitBox=false; F.tick(e,f,1); assert(e.pits.cars[1].windowStops==0,'not yet')
 a.compoundIndex=1; F.tick(e,f,0.5)
 assert(e.pits.cars[1].windowStops==1 and count(e,'compte: compose change (SS -> S, 1 dans la fenetre)')==1,'counted when AC updates the compound late')
 assert(e.incidents.playerPitNotice=='counted' and e.incidents.playerPitDue==0,'notice: validated; nothing due any more')
 local m=e.incidents
 assert(m.messageKind=='pitValidated' and m.messageValue==0 and m.messageExtra==1,'bridge announcement: validated SS (0) -> S (1)')
 local id=m.messageId; F.tick(e,f,1); assert(m.messageId==id,'announced once')
 F.tick(e,f,0.5); assert(e.panel.kind=='pit' and e.panel.short==string.format(L.pitHint.counted,'SS','S'),'overlay: mandatory stop validated (SS → S)')
 F.tick(e,f,K.pitNoticeCounted+1); assert(e.incidents.playerPitNotice=='' and not e.incidents.playerPitRemind and e.panel.kind~='pit','no reminder after a counted stop')
 -- Longtemps dans la voie après l'emplacement (plus que la marge), puis changé : compté.
 e,f,a=race(); arrive(e,f,a); a.inPitBox=false; F.tick(e,f,K.pitCompoundGrace+2)
 assert(count(e,'non compte')==0,'no decision while still in the pit lane')
 a.compoundIndex=1; F.tick(e,f,0.5); assert(e.pits.cars[1].windowStops==1,'counted after a long pit-lane exit')
 -- Changé hors de la voie des stands, dans la marge : compté.
 e,f,a=race(); arrive(e,f,a); a.inPitBox=false; F.tick(e,f,0.5); a.pit=false; F.tick(e,f,1)
 a.compoundIndex=2; F.tick(e,f,0.5); assert(e.pits.cars[1].windowStops==1,'counted within the grace after the pit lane')
 -- Même composé : refusé à la fin de la marge seulement, nommé au journal, avis de 8 s puis le rappel F1.
 e,f,a=race(); arrive(e,f,a); a.inPitBox=false; F.tick(e,f,0.5); a.pit=false
 F.tick(e,f,K.pitCompoundGrace-1); assert(count(e,'non compte')==0,'no decision before the grace ends')
 F.tick(e,f,2); assert(e.pits.cars[1].windowStops==0 and count(e,'non compte: compose inchange (SS -> SS)')==1,'not counted, compounds named')
 assert(e.incidents.playerPitNotice=='same','notice: same compound')
 assert(e.incidents.messageKind=='pitNotCounted' and e.incidents.messageValue==0 and e.incidents.messageExtra==0,'bridge announcement: not counted SS -> SS')
 local idSame=e.incidents.messageId; F.tick(e,f,1); assert(e.incidents.messageId==idSame,'announced once')
 F.tick(e,f,0.5); assert(e.panel.kind=='pit' and e.panel.short==string.format(L.pitHint.same,'SS','SS') and e.panel.raw==string.format(L.pitHint.sameDetail,'SS','SS'),'overlay: stop not counted, same compound')
 a.compoundIndex=1; F.tick(e,f,1); assert(e.pits.cars[1].windowStops==0,'a later change without a stop does not count')
 F.tick(e,f,K.pitNoticeSame); assert(e.incidents.playerPitNotice=='','notice over')
 -- Hors F1 : compté à l'arrivée, comme avant.
 e,f,a=race(false); arrive(e,f,a); assert(e.pits.cars[1].windowStops==1 and e.incidents.playerPitNotice=='','other rules: counted at the box')
end
tests.PIT_HINT_149=function()
 -- Rappel avant l'entrée des stands (entrée inconnue : dernier tiers du tour), dans la voie, à l'emplacement.
 local e,f,a=race()
 -- (passage de la ligne affiché d'abord quelques secondes : priorité au-dessus du rappel)
 F.place(f,1,2000,180); F.tick(e,f,8)
 assert(e.pits.entrySpline<0 and not e.incidents.playerPitHint,'mid-lap: no hint')
 F.place(f,1,8000,180); F.tick(e,f,0.5)
 assert(e.incidents.playerPitHint and e.panel.kind=='pit' and e.panel.short==string.format(L.pitHint.change,'SS','S ou M'),'last third: change compound, other compounds listed')
 assert(e.incidents.messageKind=='pitCompound' and e.incidents.messageValue==0 and e.incidents.messageExtra==-1,'bridge announcement: pre-entry reminder')
 local Panel=require('src/panel'); local Locale=require('src/locale')
 assert(Panel.pitAnnounce(e.incidents,'pitCompound')==string.format(L.pitHint.change,'SS','S ou M'),'announcement text (French)')
 assert(Locale.set('en')); local english=Panel.pitAnnounce(e.incidents,'pitCompound'); Locale.set('fr')
 assert(english==string.format(LE.pitHint.change,'SS','S or M'),'announcement text (English): '..tostring(english))
 assert(Panel.pitAnnounce(e.incidents,'pitOpen')==nil,'other kinds untouched')
 local idHint=e.incidents.messageId; F.tick(e,f,1); assert(e.incidents.messageId==idHint,'once per approach')
 -- Entrée relevée sur une IA venue de la piste : rappel à environ K.pitHintTime s de l'entrée.
 local b=f.cars[2]; F.place(f,2,3000,150); F.tick(e,f,0.2); b.pit=true; F.tick(e,f,0.2)
 assert(math.abs(e.pits.entrySpline-0.3)<0.01,'pit entry learnt from an AI')
 -- Beta 1.59 : au plus une fois par tour : déjà montré ce tour-ci (dernier tiers), rien de plus avant le tour suivant.
 F.place(f,1,2500,180); F.tick(e,f,0.5); assert(not e.incidents.playerPitHint,'1.59: already shown this lap: no second hint')
 F.place(f,1,2500+f.length,180); F.tick(e,f,8); assert(e.incidents.playerPitHint,'next lap (line crossing shown first), 500 m before the entry at 50 m/s: hint')
 F.place(f,1,100,180); F.tick(e,f,0.5); assert(not e.incidents.playerPitHint,'far from the entry: no hint')
 a.pit=true; F.tick(e,f,0.5); assert(e.incidents.playerPitHint,'in the pit lane: hint')
 a.inPitBox=true; a.kmh=0; F.tick(e,f,0.5); assert(e.incidents.playerPitHint and e.panel.kind=='pit','in the box (pit menu): hint')
 -- Priorité : un drapeau rouge passe avant.
 e.incidents.red=true; e.incidents.redSince=e.time; e.incidents.redMax=1e4; F.tick(e,f,0.5)
 assert(e.panel.kind=='red','the red flag stays above the reminder: '..tostring(e.panel.kind))
 -- Hors F1 : rappel habituel seulement.
 e,f,a=race(false); F.place(f,1,8000,180); F.tick(e,f,0.5)
 assert(not e.incidents.playerPitHint and not e.incidents.playerPitCompound,'other rules: no compound hint')
 -- Rappel F1 habituel : « Arrêt obligatoire · changez de composé ».
 e,f,a=race(); F.place(f,1,2000,180); F.tick(e,f,8); e.pits.openedAt=e.time; F.tick(e,f,0.5)
 assert(e.incidents.playerPitRemind and e.panel.short==L.flagShort.pitCompound,'F1 reminder: change compound')
 -- Longueurs : chaque consigne tient dans le bandeau (64 caractères au plus, noms de composés de 3 lettres).
 local function chars(s) local n=0; for _ in s:gmatch('[^\128-\191]') do n=n+1 end return n end
 for _,T in ipairs({L,LE}) do
  local H=T.pitHint
  for _,s in ipairs({string.format(H.change,'SSS','SSS, SSS'..H.orWord..'SSS'),H.generic,string.format(H.same,'SSS','SSS'),string.format(H.counted,'SSS','SSS'),string.format(H.planSame,'SSS'),string.format(H.planOk,'SSS'),T.flagShort.pitCompound}) do
   assert(chars(s)<=64,'too long: '..s)
  end
 end
end
tests.PIT_PLAN_149=function()
 local frame={player=1,cars={{valid=true,compoundIndex=0,tyresKnown=true,pit=false,tyreNames={[0]='SS',[1]='S',[2]='M'}}}}
 local notes={}
 local function note(_,text) notes[#notes+1]=text end
 local function has(text) for _,n in ipairs(notes) do if n:find(text,1,true) then return true end end return false end
 local reads=0
 local spinner={name='TYRES',type='compound',min=0,max=2,value=0,values={0,1,2}}
 local function read() reads=reads+1; return {{name='FUEL',type='fuel',min=0,max=100,value=40,values={40,60,80}},spinner},1 end
 local t=Pitplan.new()
 -- Même composé prévu : avertissement, menu entier au journal une fois.
 Pitplan.update(t,frame,10,true,true,true,read,note)
 assert(t.state=='same' and t.noticeUntil>10 and has('strategie des stands (Quick Pitstop): prereglage 2, pneu monte 0 SS, composes 0 SS, 1 S, 2 M | FUEL (fuel) 0..100 valeur 40, prereglages 40/60/80 | TYRES (compound) 0..2 valeur 0'),'same compound: warning and dump')
 -- Relu toutes les K.pitPlanPeriod s seulement, et à l'entrée de la voie des stands.
 Pitplan.update(t,frame,10.5,true,true,true,read,note); assert(reads==1,'not read every frame')
 frame.cars[1].pit=true; Pitplan.update(t,frame,10.6,true,true,true,read,note); assert(reads==2,'read on entering the pit lane')
 frame.cars[1].pit=false
 -- Autre composé prévu : arrêt valable.
 spinner.value=2; Pitplan.update(t,frame,13,true,true,true,read,note)
 assert(t.state=='ok' and t.planned=='M' and has('compose prevu M (valeur 2, correspondance directe), monte SS : arret valable'),'other compound: valid')
 -- Une valeur de plus : la plus petite vaut « pas de changement » (hypothèse dite une fois).
 spinner.max=3; spinner.value=0; Pitplan.update(t,frame,16,true,true,true,read,note)
 assert(t.state=='same' and has('hypothese retenue : plus petite valeur = pas de changement'),'no change = same compound')
 spinner.value=2; Pitplan.update(t,frame,19,true,true,true,read,note); assert(t.state=='ok' and t.planned=='S','value 2 = compound 1')
 -- Correspondance ambiguë : journal seulement.
 spinner.max=9; spinner.value=5; Pitplan.update(t,frame,22,true,true,true,read,note)
 assert(t.state=='unknown' and has('correspondance ambigue, aucun avertissement'),'ambiguous: log only')
 -- CSP sans l'API : une ligne, plus aucune lecture.
 local u=Pitplan.new(); notes={}; local tries=0
 local function none() tries=tries+1; return nil,'CSP sans getPitstopSpinners' end
 Pitplan.update(u,frame,10,true,true,true,none,note); Pitplan.update(u,frame,20,true,true,true,none,note)
 assert(tries==1 and #notes==1 and has('strategie des stands illisible (CSP sans getPitstopSpinners)') and u.state=='','API absent: one line')
 -- Hors F1, arrêt fait ou course pas lancée : rien n'est lu.
 local v=Pitplan.new(); reads=0
 Pitplan.update(v,frame,10,true,false,true,read,note); Pitplan.update(v,frame,10,false,true,true,read,note); Pitplan.update(v,frame,10,true,true,false,read,note)
 assert(reads==0 and v.state=='','nothing read outside F1 with the stop due after the start')
 -- Moteur : stratégie au même composé au départ : avis de l'overlay (8 s), puis dans le rappel d'avant l'entrée.
 local e,f,a=race(); e.pitSpinners=function() return {{name='TYRES',type='compound',min=0,max=2,value=0,values={0}}},0 end
 f.started=true; F.tick(e,f,K.pitPlanPeriod+0.5)
 assert(e.incidents.playerPlan=='same' and e.incidents.playerPlanNotice and e.panel.kind=='pit' and e.panel.short==string.format(L.pitHint.planSame,'SS'),'start: same compound planned')
 assert(e.panel.raw==string.format(L.pitHint.planSameDetail,'SS','S ou M'),'detail lists the other compounds')
 assert(e.incidents.messageKind=='pitPlanSame' and e.incidents.messageValue==0 and e.incidents.messageExtra==0,'bridge announcement: same compound planned at the start')
 F.tick(e,f,K.pitPlanNotice+1); assert(not e.incidents.playerPlanNotice,'notice over')
 -- (passage de la ligne affiché d'abord quelques secondes : priorité au-dessus du rappel)
 F.place(f,1,2000,180); F.tick(e,f,8); assert(not e.incidents.playerPitHint,'mid-lap: no reminder')
 local idPlan=e.incidents.messageId
 F.place(f,1,7000,180); F.tick(e,f,0.5); assert(e.incidents.playerPitHint and e.panel.kind=='pit' and e.panel.short==string.format(L.pitHint.planSame,'SS'),'again before the pit entry')
 assert(e.incidents.messageKind=='pitPlanSame' and e.incidents.messageId~=idPlan,'bridge announcement: again with the pre-entry reminder, instead of pitCompound')
 e.pitSpinners=function() return {{name='TYRES',type='compound',min=0,max=2,value=1,values={1}}},0 end
 F.tick(e,f,K.pitPlanPeriod+0.5); assert(e.incidents.playerPlan=='ok' and e.panel.short==string.format(L.pitHint.planOk,'S'),'fixed: S planned, stop valid')
end
-- Beta 1.49 : une seule annonce par image ; celle de l'arrêt F1, écartée par une plus importante, attend l'image
-- suivante (une fois, au plus K.heldMessageMax s) ; les autres annonces ne changent pas.
tests.PIT_HELD_149=function()
 local Incidents=require('src/incidents')
 local e,f=race(); local t=e.incidents
 local function frame() F.tick(e,f,1/60) end
 frame()
 -- Pénalité puis avis de l'arrêt dans la même image : la pénalité d'abord, l'avis à l'image suivante.
 e.announce('penaltyDelta',5,0); e.announce('pitValidated',0,1)
 assert(t.messageKind=='penaltyDelta' and t.heldKind=='pitValidated','penalty first, pit notice held')
 local id=t.messageId; frame()
 assert(t.messageKind=='pitValidated' and t.messageValue==0 and t.messageExtra==1 and t.messageId~=id and t.heldKind==nil,'pit notice published the next frame')
 id=t.messageId; frame(); assert(t.messageId==id,'no duplicate')
 -- Avis d'abord, remplacé par une pénalité de la même image : gardé lui aussi (la dernière attente l'emporte).
 e.announce('pitNotCounted',0,0); e.announce('pitCompound',0,-1); e.announce('penaltyPass',5,0)
 assert(t.messageKind=='penaltyPass' and t.heldKind=='pitCompound' and t.heldExtra==-1,'overwritten pit notice held, latest wins')
 frame(); assert(t.messageKind=='pitCompound' and t.messageExtra==-1,'then published')
 -- Avis seul, remplacé par une pénalité de la même image : gardé, publié ensuite.
 e.announce('pitValidated',0,1); e.announce('penaltyPass',5,0)
 assert(t.messageKind=='penaltyPass' and t.heldKind=='pitValidated','overwritten pit notice held')
 frame(); assert(t.messageKind=='pitValidated' and t.messageExtra==1,'then published')
 -- Image suivante déjà prise par une autre annonce : l'avis attend encore une image.
 local S=require('src/sanctions'); local update0=S.update; local busy=true
 S.update=function(...) local r=update0(...); if busy then busy=false; e.announce('pitOpen',20,95) end; return r end
 e.announce('penaltyDelta',5,0); e.announce('pitNotCounted',0,0)
 frame(); S.update=update0
 assert(t.messageKind=='pitOpen' and t.heldKind=='pitNotCounted','busy frame: the other announcement kept, the pit notice still waiting')
 frame(); assert(t.messageKind=='pitNotCounted' and t.heldKind==nil,'published on the next free frame')
 -- Trop ancien : oublié.
 e.announce('red',0,0); e.announce('pitPlanSame',0,1); t.heldAt=t.heldAt-C.K.heldMessageMax-1
 id=t.messageId; frame(); assert(t.messageId==id and t.heldKind==nil,'expired: dropped')
 -- Autres annonces : inchangées (une moins importante est perdue comme avant).
 e.announce('penaltyDelta',5,0); e.announce('pitOpen',20,95); assert(t.heldKind==nil,'other kinds are never held')
 -- Changement de session : oublié.
 e.announce('red',0,0); e.announce('pitValidated',0,1); Incidents.reset(t); assert(t.heldKind==nil,'session change: dropped')
end
return tests
