-- Correctif 1.63 (Suzuka du 13 novembre, deux drapeaux rouges) : relance après drapeau rouge (voiture de sécurité
-- d'abord, IA libérées dans l'ordre une fois qu'elle est en piste, personne devant elle ne s'échappe), allure de la
-- voiture de sécurité sans plafond fixe, reprise de place notée seulement pour un vrai dépassement, zones dangereuses
-- gardées par circuit (src/dangerfile.lua). Noms terminés par _163H. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Incidents=require('src/incidents')
local Dangerfile=require('src/dangerfile')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Drapeau rouge (course, voiture 6 = voiture de sécurité), toutes les voitures rentrées : reprise sous voiture de
-- sécurité, elle quitte son emplacement d'abord.
local function relaunch()
 local e,f=F.scene('C',6); C.preset('Course','C',e.profiles.C); e.profiles.C.redFlagHold=20; e.g.safetyCarModel='car_6'; E.changed(e)
 F.place(f,6,0,0); f.cars[6].pit=true; f.cars[6].inPitBox=true
 F.block(f,{3,4,5},600); F.place(f,2,3000,120)
 for i=1,5 do f.cars[i].position=i end
 F.tick(e,f,K.redIncidentStill+1); local t=e.incidents; assert(t.red and t.safety==6,'red flag')
 for i=2,5 do local a=f.cars[i]; F.place(f,i,100+i*20,0); a.pit=true; a.inPitBox=true; a.kmh=0; a.speed=0 end
 F.place(f,1,100,0); f.cars[1].pit=true; f.cars[1].inPitBox=true
 for _=1,200 do if not t.red then break end; F.tick(e,f,0.5) end
 assert(t.relaunch and t.safetyPhase=='exit','relaunch: it leaves first')
 return e,f,t
end
-- IA retenues tant que la voiture de sécurité est dans la voie des stands, puis tant qu'elle n'a pas roulé
-- releaseDist m en piste ; ensuite libérées dans l'ordre figé (le joueur P1 d'abord, puis l'IA P2).
tests.RELAUNCH_SC_FIRST_163H=function()
 local e,f,t=relaunch()
 f.cars[6].inPitBox=false; F.tick(e,f,K.scExitGap+2)
 assert(t.safetyPhase=='exit' and e.commands[2].pitHold and t.restartState=='wait','still in the pit lane: everyone waits ('..tostring(t.restartState)..')')
 f.cars[6].pit=false; F.place(f,6,400,80); F.tick(e,f,0.2)
 assert(t.safetyPhase=='out','on track')
 F.place(f,6,450,80); F.tick(e,f,0.2)
 assert(e.commands[2].pitHold and t.restartState=='wait','only 50 m on track: still waiting')
 F.place(f,6,600,80); F.tick(e,f,0.2)
 assert(count(e,'reprise: voiture de securite en piste a')==1,'release logged once')
 assert(t.restartState=='go','then the player (P1) goes first')
 f.cars[1].inPitBox=false; F.place(f,1,300,60); f.cars[1].pit=true
 for _=1,40 do F.tick(e,f,0.25); if not e.commands[2].pitHold then break end end
 assert(not e.commands[2].pitHold,'P2 released behind P1, in the frozen order')
 assert(e.commands[3].pitHold,'P3 still waits for P2')
end
-- Allure de la voiture de sécurité : allure du suiveur inconnue : aucune limite (plus 140–160 km/h fixes) ; connue :
-- elle plus lente de 12 % (au-dessus du rattrapage de la file) ; jamais d'allure lente fixe quand la file est loin.
tests.SC_FULL_PACE_163H=function()
 local e,f,t=relaunch()
 f.cars[6].inPitBox=false; f.cars[6].pit=false; F.place(f,6,400,150); F.tick(e,f,0.2)
 assert(t.safetyPhase=='out','on track')
 F.place(f,2,6000,0); F.place(f,3,6000,0); F.place(f,4,6000,0); F.place(f,5,6000,0); F.place(f,1,6000,0)
 F.tick(e,f,0.2)
 assert(e.commands[6].scSpeed>=K.unlimitedSpeed,'field far behind: no fixed slow pace: '..tostring(e.commands[6].scSpeed))
 F.place(f,2,350,150); f.cars[2].pit=false; f.cars[2].inPitBox=false; F.tick(e,f,0.2)
 assert(t.scHead==2 and e.commands[6].scSpeed>=K.unlimitedSpeed,'follower pace unknown: unlimited: '..tostring(e.commands[6].scSpeed))
 local s=e.states[2]; for b=1,#s.pace do s.pace[b]=300/3.6 end; s.paceCount=400
 F.tick(e,f,0.2)
 local v=e.commands[6].scSpeed
 assert(v>200 and v<300 and math.abs(v-300/(1+K.scPacePct/100))<1e-6,'known pace: the follower K.scPacePct % slower: '..v)
end
-- Allure propre inconnue, loin derrière une voiture de sécurité à 250 km/h : rattrapage au-dessus de son allure.
tests.SC_CATCH_RELATIVE_163H=function()
 local e,f,t=relaunch()
 f.cars[6].inPitBox=false; f.cars[6].pit=false; F.place(f,6,2000,250); F.tick(e,f,0.2)
 assert(t.safetyPhase=='out','on track')
 local a=f.cars[2]; a.pit=false; a.inPitBox=false; F.place(f,2,1000,200); F.tick(e,f,0.1)
 for _,fl in pairs(e.delta.fleet) do for k in pairs(fl) do fl[k]=0 end end
 local s=e.states[2]; s.paceCount=0; s.priorMap=nil
 local cap=Incidents.cap(t,f,2,e.run,e.delta,e.states,0)
 assert(cap>250 and math.abs(cap-(250+K.scCatchUp))<1e-6,'1 km behind, pace unknown: catches up: '..cap)
end
-- Voiture devant la voiture de sécurité sans l'avoir doublée : elle lève le pied jusqu'à être repassée ; une fois
-- derrière elle, plus de limite propre.
tests.SC_AHEAD_LIFTS_163H=function()
 local e,f,t=relaunch()
 f.cars[6].inPitBox=false; f.cars[6].pit=false; F.place(f,6,400,100); F.tick(e,f,0.2)
 local a=f.cars[3]; a.pit=false; a.inPitBox=false; F.place(f,3,480,150); F.tick(e,f,0.2)
 assert(t.cars[3].scAhead and count(e,'voiture de securite: Driver_3 roule devant elle')==1,'noted ahead')
 local cap=Incidents.cap(t,f,3,e.run,e.delta,e.states,0)
 assert(math.abs(cap-math.max(K.scGiveFloor,100-K.giveBackDrop))<1e-6,'lifts to let it by: '..cap)
 F.place(f,3,300,90); F.tick(e,f,0.2)
 assert(not t.cars[3].scAhead,'behind it again: forgotten')
end
-- « reprend sa place » noté seulement quand la voiture était vraiment derrière puis passe devant.
tests.RESTORE_LOG_REAL_PASS_163H=function()
 local e,f=F.scene('C',4); E.changed(e)
 local t=e.incidents
 t.redOrder={1,2,3,4}; t.redRank={[1]=1,[2]=2,[3]=3,[4]=4}; t.redOrderN=4; t.relaunch=true
 Incidents.restored(t,f,2,3,-20,4.4)
 assert(count(e,'reprise: Driver_2 reprend sa place sur Driver_3')==0,'already ahead, never behind: nothing')
 Incidents.restored(t,f,2,4,15,4.4); Incidents.restored(t,f,2,4,0,4.4)
 assert(count(e,'reprise: Driver_2 reprend sa place sur Driver_4')==0,'alongside: not yet')
 Incidents.restored(t,f,2,4,-15,4.4)
 assert(count(e,'reprise: Driver_2 reprend sa place sur Driver_4')==1,'behind then ahead: one line')
 Incidents.restored(t,f,2,4,-30,4.4); assert(count(e,'reprise: Driver_2 reprend sa place sur Driver_4')==1,'once per pair')
end
-- Fichier des zones dangereuses : aller-retour, fichier refusé, vieillissement d'un lancement à l'autre.
tests.DANGER_FILE_163H=function()
 local d=Dangerfile.new()
 Dangerfile.armed(d,0.40,5000,1,210,'2026-11-13')
 local text=Dangerfile.encode(d,{track='trk',layout='',length=5000})
 local list=Dangerfile.decode(text,'trk','',5000)
 assert(list and #list==1 and math.abs(list[1].spline-0.40)<1e-6 and list[1].level==1 and math.abs(list[1].kmh-210)<1e-6,'round trip')
 assert(Dangerfile.decode(text,'other','',5000)==nil,'another track: refused')
 assert(Dangerfile.decode('garbage','trk','',5000)==nil,'bad file: refused')
 local l2=Dangerfile.decode(text,'trk','',6000); assert(l2 and #l2==0,'track length changed: zones dropped')
 -- Jonction des stands gardée aussi (pose de la voiture de sécurité à la sortie des stands au lancement suivant).
 local dj=Dangerfile.new(); assert(Dangerfile.junctionSeen(dj,246/5000,5000) and not Dangerfile.junctionSeen(dj,250/5000,5000),'junction kept once')
 local _,j=Dangerfile.decode(Dangerfile.encode(dj,{track='trk',layout='',length=5000}),'trk','',5000)
 assert(math.abs(j*5000-246)<1e-3,'junction round trip: '..tostring(j))
 local _,j0=Dangerfile.decode(text,'trk','',5000); assert(j0==-1,'no junction: unknown')
 -- Lancement suivant : chargée (un lancement de plus), de nouveau armée au même endroit : niveau 2.
 local d2=Dangerfile.new(); assert(Dangerfile.loaded(d2,list,'trk')==1)
 Dangerfile.armed(d2,0.401,5000,1,nil,''); assert(d2.zones[1].level==2 and d2.zones[1].quiet==0,'keeps producing incidents: second level')
 -- Lancements calmes : niveau 2 ramené à 1, puis zone oubliée.
 local z=d2.zones[1]; local cur={z}
 for _=1,Dangerfile.DF.lower do local dd=Dangerfile.new(); Dangerfile.loaded(dd,cur,'trk'); cur=dd.zones end
 assert(cur[1] and cur[1].level==1,'calm sessions: back to the first level')
 for _=1,Dangerfile.DF.drop do local dd=Dangerfile.new(); Dangerfile.loaded(dd,cur,'trk'); cur=dd.zones end
 assert(#cur==0,'never again: forgotten')
 -- Part retirée : dans la zone, rien ailleurs.
 local d3=Dangerfile.new(); Dangerfile.armed(d3,0.5,5000,2,200,'')
 local cut,kmh=Dangerfile.cut(d3,0.5-100/5000,5000,150,100,{0.04,0.07}); assert(cut==0.07 and kmh==200,'before it: cut')
 assert(Dangerfile.cut(d3,0.2,5000,150,100,{0.04,0.07})==0,'elsewhere: nothing')
end
-- Zone gardée appliquée dès le premier tour (allure inconnue : repli de la zone), jamais au joueur ; incidents du
-- départ gardés pour le circuit sans armer de point difficile.
tests.DANGER_KEPT_LAP1_163H=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,0.2)
 local L=f.length
 Dangerfile.armed(e.danger,1000/L,L,1,200,'')
 F.place(f,2,950,180); F.place(f,1,950,180); F.tick(e,f,0.1)
 local s=e.states[2]; s.dangerCapped=false
 E.dangerCapTest(e,2,s,e.time)
 assert(s.dangerCapped and math.abs(e.commands[2].speedLimit-200*(1-0.04))<1e-6,'lap 1, pace unknown: kept zone fallback: '..tostring(e.commands[2].speedLimit))
 local p=e.states[1]; p.dangerCapped=false; E.dangerCapTest(e,1,p,e.time); assert(not p.dangerCapped,'never the player')
 -- Départ / premier tour : trois voitures au même endroit : zone gardée, aucun point difficile.
 local t=e.incidents; local before=t.hotspotN
 for i=1,3 do Incidents.hotspotNote(t,3000/L,L,e.time,i,true) end
 assert(t.hotspotN==before and t.dangerEvents and #t.dangerEvents==1 and count(e,'zone dangereuse gardee: 3000 m')==1,'start: kept for the track only')
 F.tick(e,f,0.1); assert(e.dangerSaveAsk==true and e.danger.n==2,'engine: merged and save asked')
 -- Jonction gardée : utilisée tant qu'elle n'est pas relevée dans ce lancement.
 e.merge.spline=-1; e.danger.junction=0.3; F.tick(e,f,1/60); assert(e.incidents.junction==0.3,'kept junction used')
end
-- De bout en bout, mémoire des circuits coupée : zone née au premier tour (allure inconnue), allure de la flotte relevée
-- ensuite, fichier écrit puis relu au lancement suivant : plafond appliqué dès le premier tour.
tests.DANGER_END_TO_END_163H=function()
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); E.changed(e); F.tick(e,f,0.2)
 assert(e.runtimeG.trackMemory~=true,'track memory off')
 local L=f.length; local t=e.incidents
 for i=1,3 do Incidents.hotspotNote(t,4000/L,L,e.time,i,true) end
 F.tick(e,f,0.05)
 assert(e.danger.n==1 and (e.danger.zones[1].kmh or 0)==0,'born on lap 1: no fleet pace yet')
 local fleet=e.delta.fleet[1]; for b=1,e.delta.bins do fleet[b]=220/3.6 end
 e.dangerSaveAsk=nil; F.tick(e,f,1/60)
 local kmh=e.danger.zones[1].kmh
 assert(kmh>0 and e.dangerSaveAsk==true,'fleet pace filled in once known: '..tostring(kmh))
 local text=Dangerfile.encode(e.danger,{track=f.track,layout='',length=L})
 local list=assert(Dangerfile.decode(text,f.track,'',L),'decoded')
 local e2,f2=F.scene('C',3); C.preset('Course','C',e2.profiles.C); E.changed(e2); F.tick(e2,f2,0.2)
 assert(Dangerfile.loaded(e2.danger,list,'k')==1,'next launch: loaded')
 F.place(f2,2,3950,200); F.tick(e2,f2,1/60)
 local s=e2.states[2]; s.dangerCapped=false; E.dangerCapTest(e2,2,s,e2.time)
 assert(s.dangerCapped and math.abs(e2.commands[2].speedLimit-kmh*(1-Incidents.DK.dangerPct[1]))<1e-3,'lap 1 of the next launch: capped: '..tostring(e2.commands[2].speedLimit))
end
return tests
