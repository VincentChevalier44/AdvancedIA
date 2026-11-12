-- Beta 1.60, tranche E : départ de la course (réglage raceStart : standing, formation, rolling ; src/formation.lua).
-- Noms terminés par _160E. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local L=require('src/lang')
local B=require('src/bridge')
local Formation=require('src/formation')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local LENGTH=1200
local function slotZ(k) return -(K.gridFirst+(k-1)*K.gridPitch) end
-- Grille : voiture 2 en pole, voiture 3 deuxième, joueur (voiture 1) troisième, les autres derrière.
local function place(i) return i==2 and 1 or i==3 and 2 or i==1 and 3 or i end
-- Course : grille arrêtée devant la ligne, puis feu vert d'AC (front montant de la session).
local function start(n,want,setup,length)
 -- Beta 1.62 : « Realistic race » active les départs réalistes ; ces tests gardent le tour de formation de la 1.60.
 local e,f=F.scene('C',n); C.preset('Course','C',e.profiles.C); e.profiles.C.raceStart=want; e.profiles.C.startRealism=false; f.length=length or LENGTH
 for i=1,n do f.cars[i].position=place(i); F.place(f,i,slotZ(place(i)),0) end
 if setup then setup(e,f) end
 E.changed(e); e.gridCaps=true; F.tick(e,f,1/60)
 f.started=false; F.tick(e,f,1/60)
 f.started=true; F.tick(e,f,1/60)
 return e,f
end
-- Peloton en file à 100 km/h jusqu'à ce que cond() soit vrai (au plus seconds s).
local function roll(e,f,seconds,cond)
 for i=1,f.count do local a=f.cars[i]; if not a.pit and not a.frozen then a.kmh=a.own or 100; a.speed=a.kmh/3.6 end end
 for _=1,math.floor(seconds*60) do
  if cond() then return true end
  for i=1,f.count do local a=f.cars[i]; if not a.frozen and not a.pit then a.z=a.z+a.speed/60; a.spline=(a.z/f.length)%1 end end
  F.tick(e,f,1/60)
 end
 return cond()
end
local function published(e,f)
 local out={cars={}}; for k=0,B.layout.maxCars-1 do out.cars[k]={} end
 B.publish(B.new('Beta 1.60'),out,e,f)
 return out
end
-- Le tour de formation commence au feu vert d'AC : neutralisation propre, premier tour et journal du départ reportés.
tests.FORMATION_BEGINS_160E=function()
 local e,f=start(4,'formation')
 local t=e.incidents
 assert(t.neutral and t.relaunch and t.formation and t.formationKind=='formation' and t.neutralMode=='fcy' and not t.formationAborted,'formation lap: own neutralisation')
 assert(e.formation.phase=='lap' and e.formation.report==true,'module in its lap phase, start report postponed')
 assert(not e.fl.on and count(e,'premier tour: mode attentif')==0,'careful first lap not armed yet')
 assert(e.startSpeedLogged==nil,'start report postponed to the real start')
 assert(count(e,'depart: tour de formation (3 voitures, 100 km/h en tete), puis depart arrete')==1,'logged once (AI only)')
 assert(t.messageKind=='formation' and t.messageValue==3 and t.messageExtra==0,'announcement: formation, number of AI, 0 = a standing start follows')
 assert(t.formationKmh==math.max(e.run.fcySpeedKmh,K.formationMinKmh)*K.formationSpeedMult and Formation.pace(e.run)==t.formationKmh,'pace of the leader')
 F.tick(e,f,0.2)
 assert(e.panel.kind=='standing' and e.panel.short==string.format(L.flagShort.formationLap,100),'panel: formation lap, then a standing start')
 assert(e.delta.kind=='' and not e.delta.course.on,'no delta time for the player during the formation lap')
 local out=published(e,f)
 assert(out.standing=='form' and out.neutral==true and out.relaunch==true and out.neutralMode=='fcy','bridge: standing=form, neutralisation published as it is')
 -- Allure : personne au-delà de l'allure de formation ; file : la deuxième voiture ne dépasse pas la pole.
 roll(e,f,3,function() return false end)
 assert(e.commands[2].yellowLimit>e.run.fcySpeedKmh+5,'pole car at the formation pace, above the FCY fallback speed ('..tostring(e.commands[2].yellowLimit)..')')
 for i=2,4 do assert(e.commands[i].yellowLimit<=t.formationKmh+1e-6,'AI capped at the formation pace '..i..' '..tostring(e.commands[i].yellowLimit)..' '..tostring(e.commands[i].active)) end
 assert(t.formation and e.incidents.activeCount==0,'still in formation, no incident from the grid')
 -- Sans messages de drapeaux : le tour a lieu et il est annoncé quand même (relecture : jamais de règle « pas de
 -- dépassement » sans rien à l'écran).
 local q=start(4,'rolling',function(e2) e2.profiles.C.yellowMessage=false end)
 assert(q.incidents.formation and q.incidents.messageKind=='formation' and q.incidents.messageExtra==1,'flag messages off: the formation lap is still announced (1 = a rolling start follows)')
end
-- Fin du tour : grille, feux, extinction ; le départ de la course est noté là, premier tour attentif « depart arrete ».
tests.FORMATION_STANDING_160E=function()
 local e,f=start(4,'formation',function(e2) e2.profiles.C.redRestart='rolling' end)
 local t=e.incidents
 assert(roll(e,f,60,function() return t.standing=='grid' end),'grid called at the end of the lap')
 assert(not t.neutral and not t.relaunch and not t.formation and t.restart,'formation over, no overtaking until the lights')
 assert(count(e,'depart: depart arrete (SS) apres le tour de formation')==1 and count(e,'fin du tour de formation: formation de la grille')==1,'logged as the race start (redRestart=rolling ignored here)')
 assert(count(e,'relance: depart arrete (SS)')==0 and count(e,'fin du tour de relance')==0,'not logged as a restart')
 assert(t.relaunchTravel>=K.relaunchTravel and t.relaunchToLine<=K.gridFormFrom,'leader has done its lap, grid called K.gridFormFrom m before the line')
 F.tick(e,f,1/60); assert(e.formation.phase=='grid' and published(e,f).standing=='grid','bridge: grid, as after a red flag')
 for i=1,4 do F.place(f,i,slotZ(place(i)),0) end
 for _=1,1200 do if t.standing=='go' then break end; F.tick(e,f,1/60) end
 assert(t.standing=='go','lights out')
 assert(e.fl.on and e.fl.kind=='depart arrete' and not e.fl.forced,'careful first lap armed as a standing start')
 assert(e.startSpeedLogged~=nil and e.formation.report==false and e.launchAt~=nil,'start reported at the lights out, start protections replayed')
 assert(not t.restart,'overtaking allowed from the lights out')
 F.tick(e,f,0.1); assert(e.formation.phase=='none' and count(e,'grille annulee')==0,'module done')
 assert(count(e,'premier tour: mode attentif')==1,'armed once')
end
-- Départ lancé : appel, drapeau vert près de la ligne, dépassement interdit jusqu'à la ligne même avec « dès le vert ».
tests.FORMATION_ROLLING_160E=function()
 local e,f=start(4,'rolling',function(e2) e2.profiles.C.restartOvertake='scIn' end)
 local t=e.incidents
 assert(t.formationKind=='rolling' and count(e,'puis depart lance')==1,'rolling start chosen')
 F.tick(e,f,0.2); assert(e.panel.kind=='rolling' and e.panel.short==string.format(L.flagShort.formationRoll,100),'panel: formation lap, then a rolling start')
 assert(roll(e,f,60,function() return t.rollCall end),'roll call when the leader nears the line')
 assert(t.formation and t.neutral and t.relaunchToLine<=K.rollCallDistance and t.relaunchToLine>K.rollGreenBefore,'called K.rollCallDistance m before the line, no green yet')
 F.tick(e,f,1/60)
 assert(t.messageKind=='rollStart' and t.messageValue==3 and t.messageExtra==2,'announcement: P3, behind the car in P2 (AC index 2)')
 assert(published(e,f).standing=='roll','bridge: standing=roll, got '..tostring(published(e,f).standing))
 roll(e,f,1,function() return false end)
 assert(e.panel.short==L.flagShort.formationCall,'panel: rolling start, got '..tostring(e.panel.short)..' '..tostring(e.panel.decided))
 local serial=t.restartSerial or 0
 assert(roll(e,f,30,function() return not t.neutral end),'green flag')
 assert(t.relaunchToLine<=K.rollGreenBefore,'green given K.rollGreenBefore m before the line')
 assert(not t.formation and not t.relaunch and not t.rollCall and not t.rollGo,'formation over')
 assert(t.restart and t.cars[2].restart and t.cars[1].restart,'no overtaking until the line, even with restartOvertake=scIn')
 assert(t.messageKind=='rollGreen','announcement: rollGreen')
 assert(count(e,'depart lance: drapeau vert a la ligne, depassement interdit jusqu a la ligne, premier virage attentif')==1,'logged')
 assert(e.fl.on and e.fl.kind=='depart lance' and not e.fl.forced and e.launchAt==e.time,'careful first lap armed (setting on), start protections replayed')
 assert((t.restartSerial or 0)==serial and count(e,'(relance)')==0,'not armed a second time as a restart')
 assert(e.startSpeedLogged~=nil and e.formation.phase=='none' and published(e,f).standing=='none','start reported, bridge back to none')
 -- Chaque voiture retrouve le droit de dépasser à la ligne.
 assert(roll(e,f,30,function() return not t.restart end) and count(e,'reprise: toutes les voitures ont franchi la ligne')==1,'rule lifted at the line')
end
-- Garde-fou du premier virage : mode attentif imposé même réglage coupé, jusqu'au premier freinage terminé ou 25 s.
tests.ROLLING_T1_FORCED_160E=function()
 local e,f=start(4,'rolling',function(e2) e2.profiles.C.firstLapCare=false end)
 local t=e.incidents
 assert(roll(e,f,90,function() return not t.neutral end),'green flag')
 assert(e.fl.on and e.fl.forced and e.fl.kind=='depart lance' and e.states[2].flOn and e.states[2].flW==1,'forced with the setting off')
 -- Freinage avant K.rollT1Min s : ne compte pas.
 f.cars[2].brake=0.8; F.tick(e,f,0.5); f.cars[2].brake=0; F.tick(e,f,0.2)
 assert(e.states[2].flOn,'a braking right at the green does not end it')
 F.tick(e,f,K.rollT1Min)
 f.cars[2].brake=0.8; F.tick(e,f,0.5); assert(e.states[2].flOn,'still careful while braking')
 f.cars[2].brake=0; F.tick(e,f,0.1)
 assert(not e.states[2].flOn and e.fl.why.virage==1 and e.states[3].flOn,'ended after its first braking zone; the others go on')
 F.tick(e,f,K.rollT1Max+K.firstLapRelease+1)
 assert(not e.fl.on and not e.fl.forced and count(e,'depart lance: fin du premier virage attentif')==1,'ended for all at K.rollT1Max s, logged once')
 assert(count(e,'premier freinage fait 1, delai 2')==1,'reasons counted')
 -- Réglage coupé, départ arrêté d'AC : jamais imposé.
 local o=start(4,'standing',function(e2) e2.profiles.C.firstLapCare=false end); assert(not o.fl.on,'standing start: never forced')
end
-- Départ lancé : aucun vert avec un incident juste après la ligne ; un tour de plus, une seule fois.
tests.ROLLING_EXTRA_LAP_160E=function()
 local e,f=start(5,'rolling',function(e2,f2)
  e2.profiles.C.neutralization='local'
  f2.cars[5].position=5; F.place(f2,5,200,0,5.5); f2.cars[5].offtrack=true; f2.cars[5].frozen=true
 end)
 local t=e.incidents
 assert(roll(e,f,90,function() return t.formationExtra>=1 end),'one more lap')
 assert(t.formation and t.neutral and t.relaunchTravel<K.relaunchTravel and not t.rollCall and count(e,'depart lance: un tour de plus (incident a 200 m apres la ligne)')==1,'lap counted again, logged')
 assert(roll(e,f,90,function() return not t.neutral end),'green at the end of the extra lap, incident or not')
 assert(t.formationExtra==K.formationExtraLaps and count(e,'depart lance: un tour de plus')==1 and e.fl.kind=='depart lance','no second extra lap')
 -- Incident loin de la ligne : aucun tour de plus.
 local e2,f2=start(5,'rolling',function(e3,f3) e3.profiles.C.neutralization='local'; f3.cars[5].position=5; F.place(f3,5,700,0,5.5); f3.cars[5].offtrack=true; f3.cars[5].frozen=true end)
 assert(roll(e2,f2,90,function() return not e2.incidents.neutral end) and count(e2,'un tour de plus')==0,'incident beyond K.rollClearAhead: green')
end
-- Incident majeur pendant le tour : formation abandonnée, FCY ordinaire (delta jugé), puis départ lancé sans grille.
tests.FORMATION_INCIDENT_160E=function()
 local e,f=start(5,'formation',function(e2,f2)
  e2.profiles.C.neutralization='fcy'; e2.profiles.C.redRestart='standing'; e2.profiles.C.safetyCarEscalation=false
  f2.cars[5].position=5; F.place(f2,5,600,0); f2.cars[5].frozen=true
 end)
 local t=e.incidents
 assert(roll(e,f,60,function() return t.formationAborted end),'formation abandoned on a major incident')
 assert(not t.formation and t.neutral and t.relaunch and t.neutralMode=='fcy','ordinary FCY takes over')
 assert(count(e,'depart: tour de formation abandonne (incident), neutralisation fcy')==1 and t.messageKind=='fcy','logged, FCY announced')
 F.tick(e,f,0.2)
 assert(e.panel.short==L.flagShort.formationOff,'panel: '..tostring(e.panel.short))
 assert(e.delta.course.on and e.delta.course.kind=='fcy','delta judged again: '..tostring(e.delta.course.kind))
 assert(published(e,f).standing=='form' and published(e,f).neutral==true,'bridge: an aborted formation lap stays « form » while its neutralisation lasts')
 -- Incident dégagé : drapeau vert au délai, départ lancé (jamais la grille, même avec redRestart=standing).
 f.cars[5].pit=true
 assert(roll(e,f,120,function() return not t.neutral end),'green flag')
 assert(t.standing=='none' and t.restart and not t.formationAborted and not t.relaunch,'rolling start, no grid')
 assert(e.fl.on and e.fl.kind=='depart lance' and t.messageKind=='rollGreen' and e.formation.phase=='none','race started at the green')
 assert(count(e,'formation de la grille')==0,'no grid')
end
-- Refus : circuit trop long, en ligne ; grille indisponible : départ lancé ; course relancée par AC ; drapeau rouge.
tests.FORMATION_REFUSED_160E=function()
 local e=start(4,'formation',nil,K.formationMaxLength+100)
 assert(not e.incidents.neutral and not e.incidents.formation and e.formation.phase=='none','long track: AC standing start')
 assert(count(e,'depart: tour de formation impossible (circuit trop long) : depart arrete d AC')==1 and e.fl.on and e.fl.kind=='depart' and e.startSpeedLogged~=nil,'logged; start as in 1.59')
 local o,fo=start(4,'standing'); fo.online=true
 o.run.raceStart='rolling'; assert(Formation.begin(o.formation,o,fo,o.time)==false and not o.incidents.neutral and count(o,'impossible (en ligne)')==1,'online: refused')
 fo.online=false; fo.length=0; assert(Formation.begin(o.formation,o,fo,o.time)==false and count(o,'impossible (circuit inconnu)')==1,'unknown track: refused')
 fo.length=LENGTH; o.incidents.red=true; assert(Formation.begin(o.formation,o,fo,o.time)==false and count(o,'impossible (drapeau rouge)')==1,'red flag: refused')
 -- Grille indisponible : le tour a lieu, départ lancé.
 local g,fg=start(4,'standing'); g.gridCaps=false; g.run.raceStart='formation'
 assert(Formation.begin(g.formation,g,fg,g.time)==true and g.incidents.formationKind=='rolling' and count(g,'depart: grille indisponible (capacites) : depart lance apres le tour de formation')==1,'grid unavailable: rolling start')
 -- Course relancée par AC pendant le tour : plus rien de la formation ; le feu vert suivant en commence une autre.
 local r,fr=start(4,'rolling'); roll(r,fr,3,function() return false end)
 fr.started=false; F.tick(r,fr,1/60)
 assert(not r.incidents.neutral and not r.incidents.formation and not r.incidents.relaunch and r.formation.phase=='none' and count(r,'depart: tour de formation interrompu (course relancee)')==1,'race restarted by AC: cleared')
 fr.started=true; F.tick(r,fr,1/60); assert(r.incidents.formation and r.formation.begun==2,'next green: a new formation lap')
 -- Drapeau rouge pendant le tour : sa procédure prend la suite.
 r.incidents.red=true; Formation.step(r.formation,r,fr,r.time)
 assert(not r.incidents.formation and r.formation.phase=='none' and count(r,'depart: tour de formation interrompu (drapeau rouge)')==1,'red flag: formation dropped')
end
-- La relance d'un drapeau rouge ne change pas : règles de relance respectées, journal identique.
tests.FORMATION_RED_FLAG_UNCHANGED_160E=function()
 local function relaunch(rule,want)
  local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart=rule; e.profiles.C.raceStart=want; f.length=LENGTH
  for i=1,4 do f.cars[i].position=place(i); F.place(f,i,slotZ(place(i)),0) end
  E.changed(e); e.gridCaps=true; F.tick(e,f,1/60)
  local t=e.incidents
  t.neutral=true; t.relaunch=true; t.neutralMode='fcy'; t.neutralSince=e.time; t.neutralUntil=e.time+(rule=='standing' and 1e6 or 5); t.relaunchSpanUntil=e.time; t.relaunchLeader=0; t.relaunchTravel=0
  assert(roll(e,f,60,function() return not t.neutral end),'restart lap ends')
  return e,t
 end
 for _,want in ipairs({'standing','rolling','formation'}) do
  local e,t=relaunch('standing',want)
  assert(t.standing=='grid' and count(e,'relance: depart arrete (SS)')==1 and count(e,'fin du tour de relance: formation de la grille')==1,'red-flag restart, standing rule: grid ('..want..')')
  assert(count(e,'tour de formation')==0 and not t.rollGo and t.relaunchToLine<=K.gridFormFrom and t.relaunchToLine>K.rollGreenBefore,'grid called K.gridFormFrom m before the line')
  local e2,t2=relaunch('rolling',want)
  assert(t2.standing=='none' and t2.restart and t2.messageKind=='restart' and (t2.restartSerial or 0)==1 and e2.fl.kind=='relance' and not t2.rollGo,'red-flag restart, rolling rule ('..want..')')
 end
end
-- Défaut : départ arrêté partout ; aucun préréglage ni jeu de règles ne choisit autre chose ; rien ne bouge alors.
tests.RACESTART_DEFAULT_160E=function()
 for _,profile in ipairs(C.profiles) do assert(C.defaults(profile).raceStart=='standing','default '..profile) end
 for _,name in ipairs({'Nordschleife','Circuit','Essais','Qualifications','Course','Endurance'}) do
  for _,profile in ipairs(C.profiles) do assert(C.preset(name,profile,{}).raceStart=='standing','built-in preset '..name..' '..profile) end
 end
 for name,preset in pairs(C.rulePresets or {}) do if type(preset)=='table' then assert(preset.raceStart==nil,'rule set '..tostring(name)) end end
 assert(C.pendingKeys.raceStart==nil,'setting live')
 local e=start(4,'standing')
 assert(not e.incidents.neutral and not e.incidents.formation and e.formation.phase=='none' and e.formation.begun==0 and e.formation.refused==0,'standing: nothing happens')
 assert(e.fl.on and e.fl.kind=='depart' and e.startSpeedLogged~=nil and count(e,'depart: tour de formation')==0,'start as in 1.59')
 -- Onglet Départ décoché : départ arrêté d'AC ; hors course : jamais.
 local o=start(4,'rolling',function(e2) e2.profiles.C.section_start=false end)
 assert(o.run.raceStart=='standing' and not o.incidents.formation,'start section off: AC standing start')
 local j,fj=F.scene('J',3); j.profiles.J.raceStart='rolling'; E.changed(j); F.tick(j,fj,1/60); fj.started=false; F.tick(j,fj,1/60); fj.started=true; F.tick(j,fj,1/60)
 assert(not j.incidents.formation and not j.incidents.neutral,'track day: never')
 j.run.raceStart='rolling'; fj.length=LENGTH; assert(Formation.begin(j.formation,j,fj,j.time)==false and not j.incidents.neutral,'outside a race: refused by the module itself')
 assert(K.formationMaxLength*3.6/(K.formationMinKmh*0.75)<K.neutralMax,'the longest formation lap ends before the neutralisation time cap')
end
-- Joueur en pole qui s'échappe : ni l'appel ni le drapeau vert ne viennent avec lui ; ils viennent avec le peloton.
tests.FORMATION_PLAYER_AHEAD_160E=function()
 local e,f=start(4,'rolling',function(_,f2) f2.cars[1].position=1; f2.cars[2].position=2; f2.cars[3].position=3; F.place(f2,1,slotZ(1),0); F.place(f2,2,slotZ(2),0); F.place(f2,3,slotZ(3),0); f2.cars[1].own=250 end)
 local t=e.incidents
 -- Le joueur boucle son tour en 17 s ; la meilleure IA en met 43.
 roll(e,f,20,function() return false end)
 assert(t.formation and t.neutral and not t.rollCall and t.relaunchLeader==2,'player gone ahead: no call, no green; the best AI is the reference')
 assert(roll(e,f,40,function() return not t.neutral end) and t.relaunchLeader==2,'green when the pack reaches the line')
 local to=((-f.cars[2].spline)%1)*f.length; assert(to<=K.rollGreenBefore+1,'given for the leading AI ('..to..' m before the line)')
end
-- Banc des départs (modèle simplifié de l'IA d'AC, 24 IA et le joueur) : tour de formation puis départ lancé, et le
-- premier tour de course : tout le monde boucle ses deux tours, aucun contact au premier virage, aucun abandon.
tests.START_BENCH_ROLLING_160E=function()
 local run=require('tests/startbench147')
 for _,sc in ipairs({{'short','gt3'},{'monza','f1'}}) do
  local r=run(sc[1],sc[2],{mode='app',seed=1,laps=2,formation=true,seconds=900,tune=function(e) e.profiles.C.raceStart='rolling'; E.changed(e) end})
  local scene=sc[1]..'/'..sc[2]
  local function n(text) local c=0; for k=1,r.log.limit do local row=r.log[k]; if row and row.message and row.message:find(text,1,true) then c=c+1 end end return c end
  assert(n('depart: tour de formation (')==1 and n('depart lance: drapeau vert')==1 and n('abandonne')==0 and n('un tour de plus')==0,scene..': one formation lap, one green')
  assert(r.finished==24,scene..': formation lap and first racing lap completed by every AI ('..r.finished..')')
  assert(r.contactsFirst==0 and r.contacts<=2,scene..': no contact into the first corner ('..r.contactsFirst..', '..r.contacts..' in all)')
  assert(r.radarStraight-(r.radarLast or 0)<=5,scene..': no braking wave on the straights ('..r.radarStraight..')')
  assert(n('premier tour: mode attentif pour 24 IA (depart lance)')==1,scene..': careful first lap armed at the green')
 end
end

-- Contrat du pont avec SpotterEnginer (il juge sur les fronts), image par image : « form » puis « roll » ne sont publiés
-- qu'avec neutral et relaunch vrais, dès la première image de la neutralisation ; à la fin, standing ne quitte « form »
-- ou « roll » que dans l'image où neutral et relaunch retombent (ou après), jamais avant. Tour abandonné sur incident :
-- « form » tenu tant que sa neutralisation dure.
tests.FORMATION_BRIDGE_EDGES_160M2=function()
 local function watch(e,f,seconds,stop)
  local seen={form=0,roll=0}; local wasNeutral,wasStanding=false,'none'; local rose,fell=false,false
  for _=1,math.floor(seconds*60) do
   for i=1,f.count do local a=f.cars[i]; if not a.frozen and not a.pit then a.z=a.z+a.speed/60; a.spline=(a.z/f.length)%1 end end
   F.tick(e,f,1/60)
   local out=published(e,f); local st=out.standing
   if st=='form' or st=='roll' then
    seen[st]=seen[st]+1
    assert(out.neutral==true and out.relaunch==true,'« '..st..' » published without neutral and relaunch')
   end
   if out.neutral and not wasNeutral then rose=true; assert(st=='form','neutral rises with standing=form in the same frame, got '..tostring(st)) end
   if wasNeutral and not out.neutral then fell=true; assert(wasStanding=='form' or wasStanding=='roll','standing left form/roll before neutral fell: '..tostring(wasStanding)) end
   if out.neutral then assert(st=='form' or st=='roll','standing back to « '..tostring(st)..' » while the neutralisation of the start lasts') end
   wasNeutral=out.neutral==true; wasStanding=st
   if stop and stop(out) then break end
  end
  return seen,rose,fell
 end
 -- Départ lancé complet.
 local function begin(n,want,setup)
  local e,f=F.scene('C',n); C.preset('Course','C',e.profiles.C); e.profiles.C.raceStart=want; f.length=LENGTH
  for i=1,n do f.cars[i].position=place(i); F.place(f,i,slotZ(place(i)),0) end
  if setup then setup(e,f) end
  E.changed(e); e.gridCaps=true; F.tick(e,f,1/60)
  f.started=false; F.tick(e,f,1/60); f.started=true
  for i=1,f.count do local a=f.cars[i]; if not a.pit and not a.frozen then a.kmh=100; a.speed=100/3.6 end end
  return e,f
 end
 local e,f=begin(4,'rolling')
 assert(published(e,f).standing=='none' and not published(e,f).neutral,'before AC’s green: nothing')
 local seen,rose,fell=watch(e,f,120,function(out) return not out.neutral and out.standing=='none' and e.incidents.rollGo==false and e.formation.phase=='none' end)
 assert(rose and fell and seen.form>0 and seen.roll>0,'rolling start: form, then roll, then none ('..seen.form..', '..seen.roll..')')
 assert(published(e,f).standing=='none' and not published(e,f).relaunch,'after the green: none, no relaunch')
 -- Tour de formation puis grille : form -> grid dans l'image où neutral retombe.
 local g,fg=begin(4,'formation')
 local gridAt=false
 seen,rose,fell=watch(g,fg,120,function(out) if out.standing=='grid' then gridAt=true end; return gridAt end)
 assert(rose and seen.form>0 and seen.roll==0 and gridAt,'formation then the grid')
 -- Incident majeur pendant le tour : « form » tenu jusqu'au drapeau vert.
 local a,fa=begin(5,'rolling',function(e2,f2)
  e2.profiles.C.neutralization='fcy'; e2.profiles.C.safetyCarEscalation=false
  f2.cars[5].position=5; F.place(f2,5,600,0); f2.cars[5].frozen=true
 end)
 local aborted=false
 seen,rose,fell=watch(a,fa,60,function() if a.incidents.formationAborted then aborted=true end; return aborted end)
 assert(aborted and published(a,fa).standing=='form' and published(a,fa).neutral==true,'aborted formation lap: still « form » under its FCY')
end
-- Annonce « formation » : extra 0 quand un départ arrêté suit le tour, 1 quand un départ lancé suit.
tests.FORMATION_ANNOUNCE_EXTRA_160M2=function()
 local e=start(4,'formation'); assert(e.incidents.messageKind=='formation' and e.incidents.messageExtra==0,'standing start follows: 0')
 local r=start(4,'rolling'); assert(r.incidents.messageKind=='formation' and r.incidents.messageExtra==1,'rolling start follows: 1')
 -- Grille indisponible : le tour finit par un départ lancé, l'annonce le dit.
 local q,fq=F.scene('C',4); C.preset('Course','C',q.profiles.C); q.profiles.C.raceStart='formation'; fq.length=LENGTH
 for i=1,4 do fq.cars[i].position=place(i); F.place(fq,i,slotZ(place(i)),0) end
 E.changed(q); q.gridCaps=false; F.tick(q,fq,1/60); fq.started=false; F.tick(q,fq,1/60); fq.started=true; F.tick(q,fq,1/60)
 assert(q.incidents.formation and q.incidents.formationKind~='formation' and q.incidents.messageExtra==1,'grid unavailable: rolling start announced')
end
return tests
