-- Beta 1.60, tranche B : responsabilité des collisions (src/blame.lua, sanContact et sanPlayerContact) et contresens
-- jugé sur l'orientation de la voiture (src/incidents.lua, src/sanctions.lua). Noms terminés par _160B. Chargé par
-- tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Penalties=require('src/penalties')
local Sanctions=require('src/sanctions')
local Incidents=require('src/incidents')
local Journal=require('src/journal')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function logged(e,text) return count(e,text)>0 end
local function scene(profile,settings,cars)
 local e,f=F.scene(profile,cars or 4)
 for k,v in pairs(settings or {}) do e.profiles[profile][k]=v end
 E.changed(e); F.tick(e,f,0.1); assert(e.profile==profile)
 -- Voitures loin les unes des autres, historique des positions latérales rempli.
 for i=1,f.count do F.place(f,i,(i-2)*1000,100) end
 return e,f
end
local function settle(e,f) F.tick(e,f,K.blameOutcome+0.4) end
-- Contact signalé par CSP pendant une image (i touche j), puis verdict.
local function hit(e,f,i,j,after)
 f.cars[i].collidedWith=j; F.tick(e,f,1/60); f.cars[i].collidedWith=nil
 if after then after() end
 settle(e,f)
end
-- Choc par l'arrière en ligne droite : i derrière j, à kmhI et kmhJ.
local function rear(f,i,j,kmhI,kmhJ,z) F.place(f,i,z or 0,kmhI); F.place(f,j,(z or 0)+5,kmhJ) end
local ON={sanContact=true}

tests.BLAME_CONSTANTS_160B=function()
 assert(K.blameSample==0.25 and K.blameMinKmh==3 and K.blameStartGrace==20 and K.blameStartKmh==30 and K.blameChain==2 and K.blameRejoin==3)
 assert(K.blameCutTime==1 and K.blameMoveRatio==2 and K.blameOutcome==6 and K.blamePlaces==2 and K.blameWarnings==2 and K.blameOutTime==15)
 assert(K.blameMoveMin==1 and K.blamePairGap==3)
 for _,profile in ipairs({'P','Q','C'}) do local p=C.defaults(profile); assert(p.sanContact==false and p.sanPlayerContact==false,'off by default: '..profile) end
 assert(not C.pendingKeys.sanContact and not C.pendingKeys.sanPlayerContact,'slice B delivered: settings live')
end
-- Ligne 1 : frottement (moins de K.blameMinKmh km/h d'écart) sans suite : personne.
tests.BLAME_RUB_160B=function()
 local e,f=scene('C',ON); F.tick(e,f,1.5)
 rear(f,2,3,100,98); hit(e,f,2,3)
 assert(logged(e,'incident de course: contact Driver_2 / Driver_3 (contact leger)'),'rub: racing incident')
 assert(count(e,'responsabilite:')==0 and e.sanctions.cars[2].contacts==0 and e.sanctions.cars[2].contactWarn==0,'nobody at fault')
 -- Même écart, mais la voiture touchée sort de la piste : ce n'est plus un frottement.
 local e2,f2=scene('C',ON); F.tick(e2,f2,1.5)
 rear(f2,2,3,100,98); hit(e2,f2,2,3,function() f2.cars[3].offtrack=true; F.tick(e2,f2,1); f2.cars[3].offtrack=false end)
 assert(logged(e2,'Driver_2 en tort (grave)'),'small speed difference but the other car goes off: judged')
end
-- Ligne 2 : départ (K.blameStartGrace s) : personne, sauf un choc par l'arrière à plus de K.blameStartKmh km/h.
tests.BLAME_START_160B=function()
 local e,f=scene('C',ON); F.tick(e,f,1.5); e.startedAt=e.time
 rear(f,2,3,115,100); hit(e,f,2,3)
 assert(logged(e,'incident de course: contact Driver_2 / Driver_3 (depart)') and count(e,'responsabilite:')==0,'start: racing incident')
 local e2,f2=scene('C',ON); F.tick(e2,f2,1.5); e2.startedAt=e2.time
 rear(f2,2,3,135,100); hit(e2,f2,2,3)
 assert(logged(e2,'ligne droite choc par l arriere : Driver_2 en tort'),'start, rear hit over K.blameStartKmh: the car behind')
 local e3,f3=scene('C',ON); F.tick(e3,f3,1.5); e3.startedAt=e3.time-K.blameStartGrace-1
 rear(f3,2,3,115,100); hit(e3,f3,2,3)
 assert(logged(e3,'Driver_2 en tort'),'after the start window: judged')
end
-- Ligne 3 : voiture accidentée, arrêtée ou hors piste : personne.
tests.BLAME_INCIDENT_CAR_160B=function()
 local e,f=scene('C',ON); F.tick(e,f,1.5)
 rear(f,2,3,100,10); hit(e,f,2,3)
 assert(logged(e,'incident de course: contact Driver_2 / Driver_3 (voiture accidentee)') and count(e,'responsabilite:')==0,'stopped car: racing incident')
 local e2,f2=scene('C',ON); F.tick(e2,f2,1.5)
 rear(f2,2,3,120,100); f2.cars[3].offtrack=true; hit(e2,f2,2,3)
 assert(logged(e2,'(voiture accidentee)') and count(e2,'responsabilite:')==0,'car off the track: racing incident')
 local e3,f3=scene('C',ON); F.tick(e3,f3,1.5)
 rear(f3,2,3,120,100); f3.cars[3].lx=1; f3.cars[3].lz=0; hit(e3,f3,2,3)
 assert(count(e3,'responsabilite:')==0,'car sideways (spun): nobody')
 -- Voie des stands, voiture de sécurité, drapeau rouge ou neutralisation : jamais de verdict.
 local e4,f4=scene('C',ON); F.tick(e4,f4,1.5)
 rear(f4,2,3,120,100); f4.cars[3].pit=true; hit(e4,f4,2,3)
 assert(count(e4,'responsabilite:')==0 and count(e4,'incident de course:')==0 and e4.blame.open==0,'pit lane: no case at all')
end
-- Carambolage : seul le premier contact est jugé.
tests.BLAME_CHAIN_160B=function()
 local e,f=scene('C',ON,5); F.tick(e,f,1.5)
 F.place(f,2,0,120); F.place(f,3,5,100); F.place(f,4,10,85)
 f.cars[2].collidedWith=3; F.tick(e,f,1/60); f.cars[2].collidedWith=nil
 F.tick(e,f,0.5)
 f.cars[3].collidedWith=4; F.tick(e,f,1/60); f.cars[3].collidedWith=nil
 settle(e,f)
 assert(logged(e,'contact Driver_2 / Driver_3, ligne droite choc par l arriere : Driver_2 en tort'),'first contact judged')
 assert(logged(e,'incident de course: contact Driver_3 / Driver_4 (voiture accidentee)'),'second contact of the chain: racing incident')
 assert(e.sanctions.cars[3].contacts==0,'the pushed car is not blamed')
 -- Après K.blameChain s, un nouveau contact est jugé pour lui-même.
 local e2,f2=scene('C',ON,5); F.tick(e2,f2,1.5)
 F.place(f2,2,0,120); F.place(f2,3,5,100); F.place(f2,4,10,85)
 f2.cars[2].collidedWith=3; F.tick(e2,f2,1/60); f2.cars[2].collidedWith=nil
 F.tick(e2,f2,K.blameChain+0.5)
 f2.cars[3].collidedWith=4; F.tick(e2,f2,1/60); f2.cars[3].collidedWith=nil
 settle(e2,f2)
 assert(logged(e2,'contact Driver_3 / Driver_4, ligne droite choc par l arriere : Driver_3 en tort'),'later contact: judged')
end
-- Ligne 4 : retour en piste depuis moins de K.blameRejoin s : la voiture qui revient.
tests.BLAME_REJOIN_160B=function()
 local function run(wait)
  local e,f=scene('C',ON); F.tick(e,f,1.5)
  F.place(f,2,0,100,-1.2); F.place(f,3,1,90,1.2)
  f.cars[3].offtrack=true; F.tick(e,f,1); f.cars[3].offtrack=false; F.tick(e,f,wait)
  hit(e,f,2,3)
  return e
 end
 local e=run(0.5)
 assert(logged(e,'contact Driver_2 / Driver_3, retour en piste : Driver_3 en tort'),'the car that rejoined is at fault')
 local late=run(K.blameRejoin+0.6)
 assert(not logged(late,'retour en piste'),'after K.blameRejoin s: not a rejoin any more')
end
-- Ligne 5 : choc par l'arrière en ligne droite : la voiture de derrière.
tests.BLAME_REAR_STRAIGHT_160B=function()
 local e,f=scene('C',ON); F.tick(e,f,1.5)
 rear(f,2,3,115,100); hit(e,f,2,3)
 assert(logged(e,'responsabilite: contact Driver_2 / Driver_3, ligne droite choc par l arriere : Driver_2 en tort (leger)'),'car behind at fault')
 assert(e.sanctions.cars[2].contacts==1 and e.sanctions.cars[3].contacts==0,'only the car behind')
 -- Signalé par la voiture de devant : même verdict.
 local e2,f2=scene('C',ON); F.tick(e2,f2,1.5)
 rear(f2,2,3,115,100); hit(e2,f2,3,2)
 assert(logged(e2,'contact Driver_3 / Driver_2, ligne droite choc par l arriere : Driver_2 en tort (leger)'),'reported by the car ahead: still the car behind')
 -- Un seul dossier par paire tant que le contact dure.
 local e3,f3=scene('C',ON); F.tick(e3,f3,1.5)
 rear(f3,2,3,115,100); f3.cars[2].collidedWith=3; f3.cars[3].collidedWith=2; F.tick(e3,f3,4); f3.cars[2].collidedWith=nil; f3.cars[3].collidedWith=nil
 F.tick(e3,f3,K.blameOutcome+K.blamePairGap)
 assert(count(e3,'responsabilite:')==1 and e3.sanctions.cars[2].contacts==1,'one case for a lasting contact: '..count(e3,'responsabilite:'))
end
-- Ligne 5, exception : la voiture de devant vient de changer de ligne devant l'autre.
tests.BLAME_REAR_CUT_ACROSS_160B=function()
 local e,f=scene('C',ON); F.tick(e,f,1.5)
 F.place(f,2,0,115,0); F.place(f,3,5,100,3); F.tick(e,f,1.5)
 for k=1,48 do F.place(f,3,5,100,3-3*k/48); F.tick(e,f,1/60) end
 hit(e,f,2,3)
 assert(logged(e,'contact Driver_2 / Driver_3, ligne droite changement de ligne : Driver_3 en tort'),'the car that moved across is at fault')
 -- Déplacement trop petit (sous K.blameMoveMin) : la voiture de derrière.
 local e2,f2=scene('C',ON); F.tick(e2,f2,1.5)
 F.place(f2,2,0,115,0); F.place(f2,3,5,100,0.6); F.tick(e2,f2,1.5)
 for k=1,48 do F.place(f2,3,5,100,0.6-0.6*k/48); F.tick(e2,f2,1/60) end
 hit(e2,f2,2,3)
 assert(logged(e2,'choc par l arriere : Driver_2 en tort'),'small move: the car behind')
end
-- Ligne 6 : choc par l'arrière en virage ou au freinage : la voiture de derrière.
tests.BLAME_REAR_CORNER_160B=function()
 local e,f=scene('C',ON); F.tick(e,f,1.5)
 -- Relecture : freinage seul en ligne droite : pas un « virage » pour un choc par l'arrière (voiture de derrière en
 -- tort par la règle de la ligne droite, sauf changement de ligne de celle de devant).
 rear(f,2,3,115,100); f.cars[3].brake=K.passBrakeMax+0.2; hit(e,f,2,3)
 assert(logged(e,'contact Driver_2 / Driver_3, ligne droite choc par l arriere : Driver_2 en tort'),'braking on a straight: the car behind, straight-line rule')
 local e2,f2=scene('C',ON); F.tick(e2,f2,1.5)
 -- Virage : a.corner est recalculé à chaque image par le pilotage (vitesse de lacet).
 rear(f2,2,3,115,100); F.place(f2,3,5,100,3); F.tick(e2,f2,1.5)
 for k=1,48 do F.place(f2,3,5,100,3-3*k/48); f2.cars[2].yawRate=e2.run.cornerYawRef; f2.cars[3].yawRate=e2.run.cornerYawRef; F.tick(e2,f2,1/60) end
 hit(e2,f2,2,3)
 assert(logged(e2,'virage nez derriere : Driver_2 en tort'),'corner: the car behind, even when the car ahead moved')
end
-- Ligne 7 : côte à côte en virage : le nez derrière de plus de K.cornerNoseMargin m est en tort.
tests.BLAME_SIDE_CORNER_NOSE_160B=function()
 assert(K.cornerNoseMargin==2.2)
 local function run(ahead)
  local e,f=scene('C',ON); F.tick(e,f,1.5)
  F.place(f,2,0,100,-1); F.place(f,3,ahead,92,1); f.cars[2].brake=0.5; f.cars[3].brake=0.5
  hit(e,f,2,3)
  return e
 end
 local level=run(2.1)
 assert(logged(level,'incident de course: contact Driver_2 / Driver_3 (nez a egalite)') and count(level,'responsabilite:')==0,'2.1 m: noses level, racing incident')
 local behind=run(2.3)
 assert(logged(behind,'contact Driver_2 / Driver_3, virage nez derriere : Driver_2 en tort'),'2.3 m behind: at fault')
 local other=run(-2.3)
 assert(logged(other,'virage nez derriere : Driver_3 en tort'),'the other way round')
end
-- Ligne 8 : côte à côte en ligne droite : la voiture qui s'est déplacée vers l'autre.
tests.BLAME_SIDE_STRAIGHT_MOVER_160B=function()
 local function run(from,to)
  local e,f=scene('C',ON); F.tick(e,f,1.5)
  F.place(f,2,0,100,from); F.place(f,3,1,92,1); F.tick(e,f,1.5)
  for k=1,48 do F.place(f,2,0,100,from+(to-from)*k/48); F.tick(e,f,1/60) end
  hit(e,f,2,3)
  return e
 end
 local e=run(-4,-1)
 assert(logged(e,'contact Driver_2 / Driver_3, ligne droite changement de ligne : Driver_2 en tort'),'the car that moved towards the other')
 -- Elle s'écartait de l'autre : jamais en tort.
 local away=run(-1,-4)
 assert(count(away,'Driver_2 en tort')==0,'moving away: not at fault')
end
-- Ligne 9 : rien de clair : incident de course.
tests.BLAME_UNCLEAR_160B=function()
 local e,f=scene('C',ON); F.tick(e,f,1.5)
 F.place(f,2,0,100,-1); F.place(f,3,1,92,1); hit(e,f,2,3)
 assert(logged(e,'incident de course: contact Driver_2 / Driver_3 (indetermine)') and count(e,'responsabilite:')==0,'nobody moved: racing incident')
 -- Les deux se rapprochent autant l'une que l'autre.
 local e2,f2=scene('C',ON); F.tick(e2,f2,1.5)
 F.place(f2,2,0,100,-3); F.place(f2,3,1,92,3); F.tick(e2,f2,1.5)
 for k=1,48 do F.place(f2,2,0,100,-3+2*k/48); F.place(f2,3,1,92,3-2*k/48); F.tick(e2,f2,1/60) end
 hit(e2,f2,2,3)
 assert(logged(e2,'(indetermine)') and count(e2,'responsabilite:')==0,'both moved: racing incident')
 -- Neutralisation : jamais de verdict.
 local e3,f3=scene('C',ON); F.tick(e3,f3,1.5)
 rear(f3,2,3,115,100); e3.incidents.neutral=true
 f3.cars[2].collidedWith=3; F.tick(e3,f3,1/60); f3.cars[2].collidedWith=nil
 assert(e3.blame.open==1 and e3.blame.cases[1].fault==0 and e3.blame.cases[1].situation=='indetermine','neutralised: nobody at fault')
end
-- Gravité : l'autre voiture sort, part en incident ou perd K.blamePlaces places dans les K.blameOutcome s.
tests.BLAME_GRADE_160B=function()
 local e,f=scene('C',ON); F.tick(e,f,1.5)
 rear(f,2,3,115,100); f.cars[2].position=4; f.cars[3].position=3
 hit(e,f,2,3,function() f.cars[3].position=3+K.blamePlaces end)
 assert(logged(e,'Driver_2 en tort (grave)'),'places lost: serious')
 local e2,f2=scene('C',ON); F.tick(e2,f2,1.5)
 rear(f2,2,3,115,100); f2.cars[2].position=4; f2.cars[3].position=3
 hit(e2,f2,2,3,function() f2.cars[3].position=3+K.blamePlaces-1 end)
 assert(logged(e2,'Driver_2 en tort (leger)'),'one place lost: light')
 local e3,f3=scene('C',ON); F.tick(e3,f3,1.5)
 rear(f3,2,3,115,100)
 hit(e3,f3,2,3,function() f3.cars[2].offtrack=true; F.tick(e3,f3,1); f3.cars[2].offtrack=false end)
 assert(logged(e3,'Driver_2 en tort (leger)'),'only the car at fault went off: light')
end
-- Sanctions des IA : avertissement, avertissement, temps ; grave : temps ; grave et l'autre arrêtée : drive-through.
tests.SAN_CONTACT_GRADED_160B=function()
 local e,f=scene('C',ON); F.tick(e,f,1.5)
 local c=e.sanctions.cars[2]
 rear(f,2,3,115,100); hit(e,f,2,3)
 assert(logged(e,'sanction IA: Driver_2 avertissement contact 1 / 2') and c.contactWarn==1 and c.time==0,'first light contact: warning')
 F.tick(e,f,K.blamePairGap); hit(e,f,2,3)
 assert(logged(e,'sanction IA: Driver_2 avertissement contact 2 / 2') and c.time==0 and c.count==0,'second: warning')
 F.tick(e,f,K.blamePairGap); hit(e,f,2,3)
 assert(logged(e,'sanction IA: Driver_2 penalite de temps +5 s (contact), total +5 s') and c.time==5 and c.count==1,'third: time penalty, counted')
 assert(c.contacts==3 and c.pending=='','no pit penalty for light contacts')
 -- Grave dès le premier : pénalité de temps, sans avertissement.
 local e2,f2=scene('C',ON); F.tick(e2,f2,1.5)
 rear(f2,2,3,115,100); hit(e2,f2,2,3,function() f2.cars[3].offtrack=true; F.tick(e2,f2,1); f2.cars[3].offtrack=false end)
 assert(logged(e2,'sanction IA: Driver_2 penalite de temps +5 s (contact)') and e2.sanctions.cars[2].contactWarn==0,'serious: time at once')
 -- Grave et la voiture touchée reste arrêtée K.blameOutTime s : drive-through.
 local e3,f3=scene('C',ON); F.tick(e3,f3,1.5)
 rear(f3,2,3,115,100)
 f3.cars[2].collidedWith=3; F.tick(e3,f3,1/60); f3.cars[2].collidedWith=nil
 f3.cars[3].offtrack=true; f3.cars[3].kmh=0; f3.cars[3].speed=0
 F.tick(e3,f3,K.blameOutcome+0.4)
 assert(count(e3,'responsabilite:')==0,'verdict waits while the other car is still stopped')
 F.tick(e3,f3,K.blameOutTime-K.blameOutcome+0.4)
 assert(logged(e3,'Driver_2 en tort (grave)') and logged(e3,'sanction IA: Driver_2 drive-through (contact)') and e3.sanctions.cars[2].pending=='drive','other car out: drive-through')
 -- Repartie avant K.blameOutTime s : pénalité de temps.
 local e4,f4=scene('C',ON); F.tick(e4,f4,1.5)
 rear(f4,2,3,115,100)
 f4.cars[2].collidedWith=3; F.tick(e4,f4,1/60); f4.cars[2].collidedWith=nil
 f4.cars[3].offtrack=true; f4.cars[3].kmh=0; f4.cars[3].speed=0
 F.tick(e4,f4,K.blameOutcome+2); f4.cars[3].offtrack=false; f4.cars[3].kmh=100; f4.cars[3].speed=100/3.6
 F.tick(e4,f4,K.blameOutTime-K.blameOutcome)
 assert(logged(e4,'sanction IA: Driver_2 penalite de temps +5 s (contact)') and e4.sanctions.cars[2].pending=='','other car back: time, no drive-through')
 -- Repartie puis de nouveau arrêtée à l'échéance : pas restée hors course tout le temps, pénalité de temps.
 local e5,f5=scene('C',ON); F.tick(e5,f5,1.5)
 rear(f5,2,3,115,100)
 f5.cars[2].collidedWith=3; F.tick(e5,f5,1/60); f5.cars[2].collidedWith=nil
 f5.cars[3].offtrack=true; f5.cars[3].kmh=0; f5.cars[3].speed=0
 F.tick(e5,f5,K.blameOutcome+2); f5.cars[3].offtrack=false; f5.cars[3].kmh=100; f5.cars[3].speed=100/3.6
 -- (l'incident de l'app met quelques secondes à se lever après le redémarrage)
 F.tick(e5,f5,5.5); f5.cars[3].offtrack=true; f5.cars[3].kmh=0; f5.cars[3].speed=0
 assert(e5.blame.open==1 and e5.blame.cases[1].waiting and not e5.blame.cases[1].outAll,'seen moving again while the verdict waits')
 F.tick(e5,f5,K.blameOutTime-K.blameOutcome)
 assert(logged(e5,'sanction IA: Driver_2 penalite de temps +5 s (contact)') and e5.sanctions.cars[2].pending=='','other car moved again in between: time, no drive-through')
 -- Réglage coupé avec un drive-through en attente : annulé (comme les autres sources).
 e3.profiles.C.sanContact=false; E.changed(e3); F.tick(e3,f3,0.2)
 assert(e3.sanctions.cars[2].pending=='' and logged(e3,'sanction IA: Driver_2 drive-through annule (reglage coupe)'),'switch off: pending pit penalty cancelled')
end
-- Essais et qualifications : journal et avertissements seulement, même pour un contact grave.
tests.SAN_CONTACT_PRACTICE_160B=function()
 for _,profile in ipairs({'P','Q'}) do
  local e,f=scene(profile,ON); F.tick(e,f,1.5)
  local c=e.sanctions.cars[2]
  for n=1,3 do
   rear(f,2,3,115,100); hit(e,f,2,3,function() f.cars[3].offtrack=true; F.tick(e,f,1); f.cars[3].offtrack=false end); F.tick(e,f,K.blamePairGap)
   assert(c.contactWarn==n and c.time==0 and c.pending=='' and c.count==0,profile..': warnings only')
  end
  assert(logged(e,'sanction IA: Driver_2 avertissement contact 3 / 3') and count(e,'penalite de temps')==0,profile..': never a penalty')
 end
end
-- Vous n'êtes jamais jugé sans votre réglage ; rien du tout quand les deux réglages sont coupés.
tests.PLAYER_CONTACT_OFF_160B=function()
 local e,f=scene('C',ON); F.tick(e,f,1.5)
 rear(f,1,2,115,100,-3000)
 for _=1,4 do hit(e,f,1,2); F.tick(e,f,K.blamePairGap) end
 local c=e.sanctions.cars[1]
 assert(count(e,'incident de course: contact Driver_1 / Driver_2 (non juge)')==4,'player at fault, switch off: not judged')
 assert(count(e,'contact joueur')==0 and count(e,'Driver_1 en tort')==0 and c.contacts==0 and c.contactWarn==0 and c.time==0,'nothing for the player')
 assert(e.penalties.requestId==0 and not e.penalties.disqualified,'no native penalty')
 -- Appel direct de la sanction, réglage coupé : rien non plus.
 Sanctions.contact(e.sanctions,e,f,1,true,false,e.time)
 assert(c.contacts==0 and c.contactWarn==0 and c.time==0 and count(e,'contact joueur')==0,'sanction path closed too')
 -- Une IA qui vous percute est jugée comme pour une autre IA.
 rear(f,3,1,115,100,-5000); hit(e,f,3,1)
 assert(logged(e,'contact Driver_3 / Driver_1, ligne droite choc par l arriere : Driver_3 en tort') and e.sanctions.cars[3].contactWarn==1,'AI hitting the player: judged')
 -- Votre réglage seul, en essais : rien (course seulement).
 local p,fp=scene('P',{sanPlayerContact=true}); F.tick(p,fp,1.5)
 rear(fp,1,2,115,100,-3000); hit(p,fp,1,2)
 assert(count(p,'contact joueur')==0 and count(p,'incident de course')==0 and p.blame.open==0 and p.blame.filled==0,'practice: the player switch does nothing')
end
-- Les deux réglages coupés (défaut) : aucun dossier, aucune ligne, aucun historique tenu.
tests.SAN_CONTACT_OFF_IDENTICAL_160B=function()
 local e,f=scene('C'); F.tick(e,f,1.5)
 assert(not e.run.sanContact and not e.run.sanPlayerContact)
 rear(f,2,3,125,100); hit(e,f,2,3,function() f.cars[3].offtrack=true; F.tick(e,f,1); f.cars[3].offtrack=false end)
 rear(f,1,4,125,100,-3000); hit(e,f,1,4)
 assert(count(e,'responsabilite:')==0 and count(e,'incident de course:')==0 and count(e,'avertissement contact')==0 and count(e,'contact joueur')==0,'no line')
 assert(e.blame.open==0 and e.blame.filled==0 and e.blame.head==0 and next(e.blame.pairUntil)==nil,'no state kept')
 assert((e.stats.blameJudged or 0)==0 and e.sanctions.cars[2].time==0 and e.sanctions.cars[2].contacts==0,'no counter, no sanction')
 assert(count(e,'contact: Driver_2 touche l arriere de Driver_3')==1,'the 1.24 contact line is unchanged')
 -- Section des sanctions décochée : les réglages ne valent plus rien.
 local e2,f2=scene('C',ON); e2.profiles.C.section_sanctions=false; E.changed(e2); F.tick(e2,f2,1.5)
 rear(f2,2,3,125,100); hit(e2,f2,2,3)
 assert(count(e2,'responsabilite:')==0 and e2.blame.open==0,'sanctions section off: nothing')
 -- Journée circuit : rien.
 local j,fj=F.scene('J',4); j.profiles.J.sanContact=true; E.changed(j); F.tick(j,fj,1.5)
 rear(fj,2,3,125,100); hit(j,fj,2,3)
 assert(count(j,'responsabilite:')==0 and j.blame.open==0,'track day: nothing')
end
-- Vous en tort (sanPlayerContact, course) : avertissements à l'écran, puis du temps ; jamais de drapeau noir.
tests.PLAYER_CONTACT_TIME_160B=function()
 local e,f=scene('C',{sanPlayerContact=true}); F.tick(e,f,1.5)
 local c=e.sanctions.cars[1]
 rear(f,1,2,115,100,-3000)
 hit(e,f,1,2)
 assert(logged(e,'responsabilite: contact Driver_1 / Driver_2, ligne droite choc par l arriere : Driver_1 en tort (leger)'),'player judged')
 assert(logged(e,'contact joueur: avertissement 1 / 2') and c.contactWarn==1 and c.time==0,'first warning')
 assert(e.incidents.messageKind=='playerContact' and e.incidents.messageText:find('Driver_1',1,true),'on-screen warning under its own title')
 F.tick(e,f,K.blamePairGap); hit(e,f,1,2)
 assert(logged(e,'contact joueur: avertissement 2 / 2') and c.time==0,'second warning')
 for n=1,8 do
  F.tick(e,f,K.blamePairGap); hit(e,f,1,2)
  assert(c.time==5*n and logged(e,string.format('contact joueur: penalite de temps +5 s, total +%d s',5*n)),'time penalty '..n)
 end
 assert(not c.dq and not e.penalties.disqualified and e.penalties.requestId==0 and e.penalties.count==0 and not e.penalties.ai.dq[1],'never a black flag, nothing written to the car')
 assert(count(e,'drapeau noir')==0 and count(e,'limites de piste joueur')==0,'no black flag line, not mixed with track limits')
 -- Une IA en tort contre vous, sans le réglage des IA : pas jugée.
 rear(f,3,1,115,100,-6000); hit(e,f,3,1)
 assert(logged(e,'incident de course: contact Driver_3 / Driver_1 (non juge)') and e.sanctions.cars[3].contacts==0,'AI not judged without sanContact')
 -- Contacts entre IA : aucun dossier sans sanContact.
 rear(f,3,4,115,100,2000); hit(e,f,3,4)
 assert(count(e,'Driver_3 / Driver_4')==0 and logged(e,'contact: Driver_3 touche l arriere de Driver_4'),'AI pair: only the 1.24 contact line')
 -- Rapport de course : colonne « contacts » à la fin.
 local lines=Sanctions.report(e.sanctions,e,f,false)
 assert(lines[2]:find(',black_flag,contacts$') and #lines>=3,'report header')
 local found=false
 for k=3,#lines do if lines[k]:find(',Driver_1,',1,true) then found=lines[k]:find(',10$')~=nil end end
 assert(found,'ten contacts at fault in the report')
end
-- Coupure des gaz native d'AC : raison « contact » sur le pont ; refusée : du temps à la place.
tests.PLAYER_CONTACT_THROTTLE_160B=function()
 local t=Penalties.new(); t.lastAt=10
 assert(Penalties.requestContact(t,5,10.5)==nil,'never over a decision not yet written')
 local id=Penalties.requestContact(t,5,12)
 assert(id==1 and t.kind=='slow' and t.seconds==5 and t.reason=='contact' and t.count==0 and #t.reason<=8,'throttle cut, reason contact, not counted')
 t.disqualified=true; assert(Penalties.requestContact(t,5,20)==nil,'never after a black flag')
 local saved=K.blameWarnings; K.blameWarnings=0
 local ok,err=pcall(function()
  local e,f=scene('C',{sanPlayerContact=true,sanPlayerPenalty='throttle'}); F.tick(e,f,1.5)
  e.penaltyCap=true
  local c=e.sanctions.cars[1]
  rear(f,1,2,115,100,-3000)
  f.cars[1].collidedWith=2; F.tick(e,f,1/60); f.cars[1].collidedWith=nil; F.tick(e,f,K.blameOutcome+0.05)
  assert(logged(e,'contact joueur: coupure des gaz 5 s demandee a AC') and c.contactRequest==e.penalties.requestId and e.penalties.reason=='contact' and c.time==0,'requested')
  local B=require('src/bridge'); local out={cars={}}; for k=0,B.layout.maxCars-1 do out.cars[k]={} end
  B.publish(B.new('test'),out,e,f); assert(out.penaltyReason=='contact','bridge: penaltyReason contact')
  e.penaltyWritten=c.contactRequest; F.tick(e,f,0.1); assert(c.contactRequest==0 and c.time==0,'written by AC: nothing more')
  F.tick(e,f,K.blamePairGap+0.5)
  f.cars[1].collidedWith=2; F.tick(e,f,1/60); f.cars[1].collidedWith=nil; F.tick(e,f,K.blameOutcome+0.05)
  local asked=c.contactRequest; assert(asked>0,'second request')
  F.tick(e,f,K.sanPlayerCutConfirm+0.1)
  assert(c.contactRequest==0 and e.penalties.cancelled==asked and c.time==5 and logged(e,'contact joueur: penalite de temps +5 s, coupure des gaz refusee par AC, total +5 s'),'not written: time instead')
  -- Capacité absente : du temps tout de suite.
  local e2,f2=scene('C',{sanPlayerContact=true,sanPlayerPenalty='throttle'}); F.tick(e2,f2,1.5)
  e2.penaltyCap=false; rear(f2,1,2,115,100,-3000); hit(e2,f2,1,2)
  assert(e2.sanctions.cars[1].time==5 and e2.penalties.reason~='contact' and e2.penalties.requestId==0,'no native penalty: time')
 end)
 K.blameWarnings=saved
 assert(ok,err)
end
-- Journal en anglais : chaque ligne nouvelle a son modèle.
tests.BLAME_JOURNAL_EN_160B=function()
 local function en(text) return (Journal.english(text)) end
 assert(en('responsabilite: contact Driver_2 / Driver_3, virage nez derriere : Driver_2 en tort (grave)')=='blame: contact Driver_2 / Driver_3, corner, nose behind: Driver_2 at fault (serious)')
 assert(en('responsabilite: contact A / B, ligne droite choc par l arriere : A en tort (leger)')=='blame: contact A / B, straight, hit from behind: A at fault (light)')
 assert(en('responsabilite: contact A / B, ligne droite changement de ligne : B en tort (leger)')=='blame: contact A / B, straight, change of line: B at fault (light)')
 assert(en('responsabilite: contact A / B, retour en piste : B en tort (leger)')=='blame: contact A / B, rejoining the track: B at fault (light)')
 for fr,english in pairs({['nez a egalite']='noses level',depart='start',['voiture accidentee']='car in an incident',['contact leger']='light contact',indetermine='unclear',['non juge']='not judged'}) do
  assert(en('incident de course: contact A / B ('..fr..')')=='racing incident: contact A / B ('..english..')',fr)
 end
 assert(en('sanction IA: A avertissement contact 1 / 2')=='AI sanction: A contact warning 1 / 2')
 assert(en('sanction IA: A penalite de temps +5 s (contact), total +5 s')=='AI sanction: A time penalty +5 s (contact), total +5 s')
 assert(en('sanction IA: A drive-through (contact), a purger en 3 tours')=='AI sanction: A drive-through (contact), to serve within 3 laps')
 assert(en('contact joueur: avertissement 1 / 2')=='player contact: warning 1 / 2')
 assert(en('contact joueur: penalite de temps +5 s, total +10 s')=='player contact: time penalty +5 s, total +10 s')
 assert(en('contact joueur: penalite de temps +5 s, coupure des gaz refusee par AC, total +5 s')=='player contact: time penalty +5 s, throttle cut refused by AC, total +5 s')
 assert(en('contact joueur: coupure des gaz 5 s demandee a AC')=='player contact: 5 s throttle cut requested from AC')
end
-- Contresens : nez en premier contre le sens de la piste.
local function drive(e,f,i,kmh,seconds,heading)
 local a=f.cars[i]; a.kmh=kmh; a.speed=kmh/3.6; a.lz=heading
 for _=1,math.floor(seconds*60+0.5) do a.z=a.z-a.speed/60; a.spline=(a.z/f.length)%1; F.tick(e,f,1/60) end
end
local function bridgeWrong(e,f,slot)
 local B=require('src/bridge'); local out={cars={}}; for k=0,B.layout.maxCars-1 do out.cars[k]={} end
 B.publish(B.new('test'),out,e,f)
 return out.cars[slot-1].wrong
end
tests.WRONG_NOSE_FIRST_160B=function()
 local e,f=scene('C')
 drive(e,f,3,40,K.wrongWayTime+0.3,-1)
 assert(e.incidents.cars[3].wrong>=K.wrongWayTime and bridgeWrong(e,f,3)==true,'turned round and driving back: wrong way')
 assert(Incidents.noseFirst({x=0,z=-1,lx=0,lz=-1},0,0)==true and Incidents.noseFirst({x=0,z=-1,lx=0,lz=1},0,0)==false and Incidents.noseFirst({x=0,z=0,lx=0,lz=1},0,0)==false,'helper: displacement along the heading')
end
tests.WRONG_REVERSING_160B=function()
 local e,f=scene('C')
 local most=0
 local a=f.cars[3]; a.kmh=40; a.speed=40/3.6; a.lz=1
 for _=1,math.floor((K.wrongWayTime*3)*60) do a.z=a.z-a.speed/60; a.spline=(a.z/f.length)%1; F.tick(e,f,1/60); most=math.max(most,e.incidents.cars[3].wrong) end
 assert(most==0 and bridgeWrong(e,f,3)==false,'reversing, nose forward: never wrong way (bridge wrong=false)')
 assert(count(e,'contresens')==0,'no wrong-way line')
end
tests.WRONG_SANCTION_REVERSING_160B=function()
 local e,f=scene('C')
 drive(e,f,3,40,e.run.sanWrongWaySeconds+2,1)
 assert(not e.sanctions.cars[3].dq and e.sanctions.cars[3].wrongFor==0 and count(e,'drapeau noir')==0,'AI reversing: no black flag')
 local e2,f2=scene('C')
 drive(e2,f2,3,40,e2.run.sanWrongWaySeconds+0.5,-1)
 assert(e2.sanctions.cars[3].dq and logged(e2,'sanction IA: Driver_3 drapeau noir (contresens)'),'AI driving back nose first: black flag as before')
end
tests.WRONG_TELEPORT_160B=function()
 local e,f=scene('C')
 drive(e,f,3,40,K.wrongWayTime*0.6,-1)
 assert(e.incidents.cars[3].wrong>0,'counting')
 f.cars[3].teleport=true; F.tick(e,f,1/60); f.cars[3].teleport=false
 assert(e.incidents.cars[3].wrong==0 and e.sanctions.cars[3].wrongFor==0,'teleport: reset')
 -- Première image après la remise à zéro : aucun déplacement connu, rien de compté.
 F.tick(e,f,1/60); assert(e.incidents.cars[3].wrong==0,'no displacement known: nothing counted')
end
return tests
