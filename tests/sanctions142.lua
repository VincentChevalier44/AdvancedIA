-- Beta 1.42, fourche SANCTIONS : sanctions des IA, mêmes règles que pour le joueur (limites de piste, virage coupé,
-- procédure, contresens, purge aux stands, place à rendre, classement corrigé). Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Grid=require('src/grid')
local Sanctions=require('src/sanctions')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function logged(e,text) return count(e,text)>0 end
local function out(f,i,on) local a=f.cars[i]; a.wheelsOut=on and 4 or 0; a.offtrack=on end
local function speed(f,i,kmh) local a=f.cars[i]; a.kmh=kmh; a.speed=kmh/3.6 end
-- Allure apprise de la voiture i (m/s) à tous les endroits.
local function learn(e,i,v) local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=v end end
local function race(count,settings)
 local e,f=F.scene('C',count or 4)
 if settings then for k,v in pairs(settings) do e.profiles.C[k]=v end; E.changed(e) end
 F.tick(e,f,0.1); assert(e.profile=='C')
 return e,f
end
-- Essais : tour invalidé aussitôt (une fois par tour) ; dernier secteur : tour suivant aussi ; ni une sortie au pas
-- (tête-à-queue), ni le joueur.
tests.SAN_TRACK_LIMITS_PRACTICE_142=function()
 local e,f=F.scene('P',6); F.tick(e,f,0.1)
 assert(e.profile=='P' and e.run.sanTrackLimits and not e.run.sanCutPenalty and not e.run.sanJumpStart,'practice: track limits, no race sanction')
 f.sectorCount=3; f.cars[2].sector=0
 out(f,2,true); F.tick(e,f,0.2); assert(not logged(e,'tour invalide IA'),'dwell')
 F.tick(e,f,0.3); assert(count(e,'tour invalide IA: Driver_2 (secteur 1)')==1,'lap invalidated')
 out(f,2,false); F.tick(e,f,1); out(f,2,true); F.tick(e,f,1); out(f,2,false); F.tick(e,f,0.1)
 assert(count(e,'tour invalide IA: Driver_2')==1,'once per lap')
 f.cars[3].sector=2; out(f,3,true); F.tick(e,f,0.5); out(f,3,false); F.tick(e,f,0.1)
 assert(logged(e,'tour invalide IA: Driver_3 (secteur 3, dernier secteur : tour suivant aussi)'),'last sector')
 local c=e.sanctions.cars[3]; assert(c.invalidNext==f.cars[3].lap+1 and c.invalid==2)
 f.cars[3].lap=f.cars[3].lap+1; F.tick(e,f,0.1); assert(c.invalidLap==f.cars[3].lap and c.invalidNext==-1,'next lap invalid from the start')
 assert(#e.sanctions.rows>=2 and e.sanctions.rows[1].text:find('Driver_3',1,true),'Diagnostic rows, newest first')
 speed(f,5,20); out(f,5,true); F.tick(e,f,1); out(f,5,false); F.tick(e,f,0.1)
 assert(not logged(e,'tour invalide IA: Driver_5'),'a crawl off the track is not track limits')
 -- Beta 1.56 : ni sur le chemin des IA, ni sur celui de vos limites de piste (option coupée par défaut).
 out(f,1,true); F.tick(e,f,1); out(f,1,false); F.tick(e,f,0.1); assert(not logged(e,'IA: Driver_1') and not logged(e,'joueur (app)'),'never the player')
 e.g.safetyCarModel='sc_car'; f.cars[6].id='sc_car'; E.changed(e); F.tick(e,f,0.1); assert(f.cars[6].safetyCar,'safety car identified'); out(f,6,true); F.tick(e,f,1); out(f,6,false); F.tick(e,f,0.1); assert(not logged(e,'tour invalide IA: Driver_6'),'never the safety car')
end
-- Endroit où plusieurs IA sortent (la trajectoire elle-même) : ignoré dès la troisième, noté une fois.
tests.SAN_LINE_IGNORED_142=function()
 local e,f=F.scene('P',6); F.tick(e,f,0.1)
 for k,i in ipairs({2,3,4,5}) do F.place(f,i,5000+(k-1)*5,100) end
 F.tick(e,f,0.5)
 for _,i in ipairs({2,3,4,5}) do out(f,i,true); F.tick(e,f,0.5); out(f,i,false); F.tick(e,f,0.2) end
 assert(count(e,'tour invalide IA')==2,'two laps invalidated before the place is known: '..count(e,'tour invalide IA'))
 assert(count(e,'limites de piste IA: zone ignoree a 50')==1,'place ignored once')
end
-- Course : avertissements puis pénalité de temps ; une sortie comptée par délai ; rien au départ.
tests.SAN_TRACK_LIMITS_RACE_142=function()
 local e,f=race()
 assert(e.run.sanTrackLimits and e.run.sanTrackWarnings==3 and e.run.sanTimeSeconds==5)
 local function off(i) out(f,i,true); F.tick(e,f,0.5); out(f,i,false); F.tick(e,f,K.sanStrikeGap) end
 for _=1,3 do off(2) end
 assert(count(e,'limites de piste IA: Driver_2 avertissement')==3 and logged(e,'avertissement 3 / 3'),'three warnings')
 assert(e.sanctions.cars[2].time==0 and not logged(e,'tour invalide IA'),'no penalty yet, no lap invalidation in the race')
 off(2)
 assert(logged(e,'sanction IA: Driver_2 penalite de temps +5 s (limites de piste), total +5 s') and e.sanctions.cars[2].time==5,'then a time penalty')
 out(f,2,true); F.tick(e,f,0.5); out(f,2,false); F.tick(e,f,0.5); out(f,2,true); F.tick(e,f,0.5); out(f,2,false); F.tick(e,f,0.1)
 assert(e.sanctions.cars[2].strikes==5,'one strike per gap')
 e.startedAt=e.time-5; out(f,3,true); F.tick(e,f,0.5); out(f,3,false); F.tick(e,f,0.1)
 assert(e.sanctions.cars[3].strikes==0,'nothing judged at the start')
end
-- Virage coupé avec gain : coupure des gaz progressive (jamais sous K.sanCutThrottle, jamais à zéro), servie en
-- ligne droite puis rendue.
tests.SAN_CUT_THROTTLE_142=function()
 local e,f=race(); learn(e,2,30)
 local z=f.cars[2].z
 out(f,2,true); F.tick(e,f,1); F.place(f,2,z+100,100); out(f,2,false); F.tick(e,f,1/60)
 assert(logged(e,'sanction IA: Driver_2 coupure des gaz 5 s (virage coupe, gain'),'cut with a time gain')
 local c=e.sanctions.cars[2]; assert(c.strikes==0 and c.cutLeft>0,'a cut, not a track-limits strike')
 local low=1
 for _=1,math.floor(K.sanCutAfterRejoin*60) do F.tick(e,f,1/60); low=math.min(low,e.commands[2].throttleLimit) end
 assert(low==1,'never right after the rejoin')
 for _=1,60 do F.tick(e,f,1/60); low=math.min(low,e.commands[2].throttleLimit) end
 assert(low>=K.sanCutThrottle-1e-9 and low<0.5,'gradual, never a hard cut: '..low)
 F.tick(e,f,5); assert(c.cutLeft==0 and logged(e,'sanction IA purgee: Driver_2 coupure des gaz'),'served')
 F.tick(e,f,1); assert(e.commands[2].throttleLimit==1,'given back')
 -- Sortie sans gain (allure inconnue, voiture lente) : une sortie des limites, pas une coupure.
 local e2,f2=race(); out(f2,3,true); F.tick(e2,f2,1); out(f2,3,false); F.tick(e2,f2,0.1)
 assert(e2.sanctions.cars[3].strikes==1 and e2.sanctions.cars[3].cutLeft==0)
end
-- Jamais avec une voiture proche derrière, en virage, au freinage, à basse vitesse ; sans occasion sûre, pénalité de
-- temps à la place.
tests.SAN_CUT_SAFETY_142=function()
 local e,f=race()
 local c=e.sanctions.cars[2]; c.cutLeft=5; c.cutSeconds=5
 F.place(f,3,-20-4.4,100); F.tick(e,f,1)
 assert(e.commands[2].throttleLimit==1 and c.cutLeft==5 and c.cutWait>0.9,'car close behind')
 F.place(f,3,1000,100); f.cars[2].yawRate=0.5; F.tick(e,f,1); assert(e.commands[2].throttleLimit==1,'corner')
 f.cars[2].yawRate=0; f.cars[2].brake=0.5; F.tick(e,f,0.5); assert(e.commands[2].throttleLimit==1,'braking')
 f.cars[2].brake=0; speed(f,2,60); F.tick(e,f,0.5); assert(e.commands[2].throttleLimit==1,'too slow')
 speed(f,2,100); f.cars[2].yawRate=0.5
 F.tick(e,f,K.sanCutDeferMax)
 assert(c.cutLeft==0 and c.time==e.run.sanTimeSeconds and logged(e,'coupure des gaz impossible en securite'),'converted to a time penalty')
end
-- Drive-through (faux départ) : appel aux stands, passage sans service ni attente, pas un arrêt obligatoire, purgé à
-- la sortie de la voie.
tests.SAN_DRIVE_THROUGH_142=function()
 local e,f=race()
 assert(e.run.sanJumpStart and e.run.sanProcedureKind=='drive')
 e.grid.aiJump[2]=true; F.tick(e,f,0.1)
 local c=e.sanctions.cars[2]
 assert(c.pending=='drive' and logged(e,'sanction IA: Driver_2 drive-through (faux depart), a purger en 3 tours'),'drive-through')
 assert(e.grid.aiJump[2]=='taken','jump consumed once')
 assert(e.commands[2].rulePit and not e.commands[3].rulePit,'called to the pits')
 local a=f.cars[2]
 a.pit=true; F.tick(e,f,1); assert(c.entry,'penalty visit')
 local pc=e.pits.cars[2]; local before=pc.windowStops; local visitBefore=pc.visit; local stopsBefore=pc.stops
 a.damageBody=80; a.inPitBox=true; speed(f,2,0); F.tick(e,f,1/60)
 assert(pc.windowStops==before and pc.stops==stopsBefore and pc.visit==visitBefore and logged(e,'passage de penalite a l emplacement'),'not a mandatory stop, not a visit')
 assert(e.commands[2].noOutLap,'no out-lap after a penalty visit')
 assert(e.run.pitRepair and not e.commands[2].pitHold and e.commands[2].pitCompound==-1 and not e.commands[2].pitRepair,'no wait, no service (no repair although damaged)')
 a.damageBody=0; F.tick(e,f,2); a.inPitBox=false; speed(f,2,60); F.tick(e,f,1); a.pit=false; speed(f,2,100); F.tick(e,f,K.sanLaneDebounce+0.1)
 assert(c.pending=='' and logged(e,'sanction IA purgee: Driver_2 drive-through'),'served')
 assert(not e.commands[2].rulePit,'no more pit call')
 assert(e.commands[2].noOutLap,'still no out-lap just after the exit'); F.tick(e,f,K.sanNoOutLap+0.1); assert(e.commands[2].noOutLap==false,'flag given back')
 -- Autre arrêt voulu (règles, stratégie) : la pénalité attend, ce passage ne la purge pas.
 e.grid.aiJump[3]=true; F.tick(e,f,0.1); local d=e.sanctions.cars[3]
 assert(d.pending=='drive')
 e.profiles.C.maxStintMin=1; E.changed(e); e.pits.cars[3].lastStop=e.time-120; F.tick(e,f,0.5)
 assert(e.commands[3].rulePit and not d.asked,'another stop wanted: the penalty waits')
 f.cars[3].pit=true; F.tick(e,f,1/60); assert(not d.entry,'a service stop is not a penalty visit')
 f.cars[3].pit=false; F.tick(e,f,0.1); assert(d.pending=='drive','still due')
end
tests.SAN_STOP_GO_142=function()
 local e,f=race(4,{sanProcedureKind='stopgo'})
 e.grid.aiJump[2]=true; F.tick(e,f,0.1)
 local c=e.sanctions.cars[2]; assert(c.pending=='stopgo' and logged(e,'stop-and-go 10 s (faux depart)'))
 local a=f.cars[2]; a.pit=true; F.tick(e,f,1); a.inPitBox=true; speed(f,2,0); F.tick(e,f,5)
 assert(e.commands[2].pitHold and e.commands[2].pitCompound==-1,'held at the box, no service')
 F.tick(e,f,5.1); assert(not e.commands[2].pitHold and c.held,'released after the stop')
 a.inPitBox=false; speed(f,2,60); F.tick(e,f,1); a.pit=false; F.tick(e,f,K.sanLaneDebounce+0.1)
 assert(c.pending=='' and logged(e,'sanction IA purgee: Driver_2 stop-and-go'),'served')
 -- Sortie de l'emplacement avant la fin de l'arrêt : pas purgée.
 e.grid.aiJump[3]=true; F.tick(e,f,0.1); local d=e.sanctions.cars[3]; local b=f.cars[3]
 b.pit=true; F.tick(e,f,1); b.inPitBox=true; speed(f,3,0); F.tick(e,f,2); b.inPitBox=false; b.pit=false; speed(f,3,100); F.tick(e,f,K.sanLaneDebounce+0.1)
 assert(d.pending=='stopgo','not served without the full stop')
end
-- Pénalité non purgée en sanServeLaps tours (un tour sans aucun moment où elle était possible ne compte pas) :
-- drapeau noir, IA garée à son stand.
tests.SAN_IGNORED_BLACK_FLAG_142=function()
 local e,f=race()
 e.startedAt=e.time-10; e.grid.aiJump[2]=true; F.tick(e,f,0.1)
 local c=e.sanctions.cars[2]; local a=f.cars[2]
 assert(c.pending=='drive' and not e.commands[2].rulePit,'no pit call in the first seconds of the race')
 a.lap=a.lap+1; F.tick(e,f,0.1); a.lap=a.lap+1; F.tick(e,f,0.1)
 assert(c.pendingLaps==0,'a lap without any chance to serve does not count')
 e.startedAt=-100; e.sanctions.pitSeen=true
 for _=1,2 do F.tick(e,f,0.1); a.lap=a.lap+1; F.tick(e,f,0.1) end
 assert(c.pendingLaps==2 and not c.dq)
 F.tick(e,f,0.1); a.lap=a.lap+1; F.tick(e,f,0.1)
 assert(c.dq and e.penalties.ai.dq[2] and e.states[2].disqualified and logged(e,'sanction IA: Driver_2 drapeau noir (penalite non purgee)'),'black flag')
 F.tick(e,f,0.1); assert(e.commands[2].scPark and e.commands[2].parkReason=='dq','parked at its box')
end
-- Contresens : drapeau noir après sanWrongWaySeconds s au-dessus de K.sanWrongWayKmh km/h (course et essais).
tests.SAN_WRONG_WAY_142=function()
 local function back(e,f,i,kmh,seconds)
  local a=f.cars[i]; speed(f,i,kmh); a.lz=-1 -- Beta 1.60 : contresens = nez en premier contre le sens de la piste (voiture retournée)
  for _=1,math.floor(seconds*60+0.5) do a.z=a.z-a.speed/60; a.spline=(a.z/f.length)%1; F.tick(e,f,1/60) end
 end
 local e,f=race()
 back(e,f,3,15,6); assert(not e.sanctions.cars[3].dq,'too slow: not driving the wrong way')
 back(e,f,3,40,3); assert(not e.sanctions.cars[3].dq,'tolerated')
 back(e,f,3,40,2.5); assert(e.sanctions.cars[3].dq and logged(e,'sanction IA: Driver_3 drapeau noir (contresens)'),'black flag')
 assert(logged(e,'Driver_3') and e.incidents.messageKind=='aiBlackFlag','on-screen black flag')
 local p,fp=F.scene('P',3); F.tick(p,fp,0.1)
 back(p,fp,2,40,6); assert(p.sanctions.cars[2].dq,'practice too')
end
-- Excès de vitesse dans la voie des stands : drive-through, une fois par passage, jamais dans la marge ni au début.
tests.SAN_PIT_SPEED_142=function()
 local e,f=race()
 local a=f.cars[2]; a.pit=true; speed(f,2,84); F.tick(e,f,8); assert(not logged(e,'stands IA'),'within the margin')
 a.pit=false; F.tick(e,f,K.sanLaneDebounce+0.5); a.pit=true; speed(f,2,120)
 F.tick(e,f,K.sanPitSpeedGrace+K.sanPitSpeedDwell-0.3); assert(not logged(e,'stands IA'),'grace and dwell')
 F.tick(e,f,0.6)
 assert(logged(e,'stands IA: Driver_2 a 120 km/h dans la voie (limite 80 km/h)') and e.sanctions.cars[2].pending=='drive','drive-through')
 F.tick(e,f,5); assert(count(e,'stands IA: Driver_2')==1,'once per visit')
end
-- Ligne de sortie : sortie de la voie bien avant la jonction apprise (jamais à la jonction).
tests.SAN_PIT_EXIT_142=function()
 local e,f=race()
 e.merge.spline=0.5; e.merge.samples=3
 local a=F.place(f,2,5000-60,100); a.pit=true; F.tick(e,f,6); a.pit=false; F.tick(e,f,K.sanLaneDebounce+0.1)
 assert(logged(e,'stands IA: Driver_2 sortie de la voie 60 m avant la jonction') and e.sanctions.cars[2].pending=='drive','pit-exit line')
 local b=F.place(f,3,5000+2,100); b.pit=true; F.tick(e,f,6); b.pit=false; F.tick(e,f,K.sanLaneDebounce+0.1)
 assert(not logged(e,'Driver_3 sortie'),'at the junction: nothing')
 e.merge.samples=1; local d=F.place(f,4,5000-60,100); d.pit=true; F.tick(e,f,6); d.pit=false; F.tick(e,f,K.sanLaneDebounce+0.1)
 assert(not logged(e,'Driver_4 sortie'),'junction not learnt well enough')
end
-- Place à rendre après un dépassement hors piste : levée de pied, place rendue ; sinon pénalité de temps.
tests.SAN_GIVE_BACK_142=function()
 local e,f=race()
 F.place(f,2,0,100); F.place(f,3,14.4,100); F.tick(e,f,0.5)
 out(f,2,true); F.tick(e,f,0.5); F.place(f,2,30,110); F.tick(e,f,0.1)
 local c=e.sanctions.cars[2]
 assert(c.owedTo==3 and logged(e,'place a rendre IA: Driver_2 doit rendre la place a Driver_3 (15 s)'),'place owed')
 out(f,2,false); F.tick(e,f,2); assert(e.commands[2].yellowLimit<108,'lifts off: '..e.commands[2].yellowLimit)
 F.place(f,3,50,100); F.tick(e,f,0.1)
 assert(c.owedTo==0 and logged(e,'place rendue IA: Driver_2 a Driver_3') and c.time==0,'place given back')
 F.place(f,2,0,100); F.place(f,3,14.4,100); F.tick(e,f,1)
 out(f,2,true); F.tick(e,f,0.5); F.place(f,2,30,110); F.tick(e,f,0.1); out(f,2,false)
 assert(c.owedTo==3)
 F.tick(e,f,e.run.sanGiveBackSeconds+0.5)
 assert(c.owedTo==0 and c.time==5 and logged(e,'penalite de temps +5 s (place non rendue)'),'time penalty at the deadline')
 -- Voiture doublée qui rentre aux stands : plus rien à rendre.
 F.place(f,2,0,100); F.place(f,3,14.4,100); F.tick(e,f,1)
 out(f,2,true); F.tick(e,f,0.5); F.place(f,2,30,110); F.tick(e,f,0.1); out(f,2,false)
 f.cars[3].pit=true; F.tick(e,f,0.1); assert(c.owedTo==0 and logged(e,'annulee (Driver_3 hors course ou aux stands)'))
end
-- Classement corrigé : temps ajouté à l'arrivée, pénalité aux stands encore due ajoutée au résultat, place corrigée du
-- joueur dans le récapitulatif (le classement d'AC est inchangé).
tests.SAN_CLASSIFICATION_142=function()
 local e,f=race()
 f.cars[2].position=1; f.cars[1].position=2; f.cars[3].position=3; f.cars[4].position=4
 F.tick(e,f,0.5)
 e.sanctions.cars[2].time=5; e.sanctions.cars[3].pending='drive'
 f.time=1000; f.cars[2].finished=true; f.cars[2].lap=10; F.tick(e,f,0.1)
 f.time=1003; f.cars[1].finished=true; f.cars[1].lap=10; F.tick(e,f,0.1)
 assert(Sanctions.position(e.sanctions,1)==1 and Sanctions.position(e.sanctions,2)==2,'time penalty moves the winner behind')
 assert(e.hud.recap[5]=='Classement corrigé : P1','recap line: '..tostring(e.hud.recap[5]))
 f.time=1004; f.cars[3].finished=true; f.cars[3].lap=10; F.tick(e,f,0.1)
 assert(e.sanctions.cars[3].time==K.sanDriveTime and logged(e,'drive-through non purge a l arrivee, +20 s au resultat'),'unserved drive-through added')
 assert(logged(e,'classement corrige (le classement d AC reste inchange): P1 Driver_1 (AC P2), P2 Driver_2 (+5 s, AC P1)'),'journal')
 assert(#e.sanctions.classRows>=1 and e.sanctions.classRows[1].text=='P1 : Driver_1 (+0 s, P2 chez AC)','Diagnostic row: '..e.sanctions.classRows[1].text)
 -- Sans le réglage : la pénalité due n'est pas ajoutée.
 local g,fg=race(4,{sanUnservedTime=false}); g.sanctions.cars[2].pending='drive'; fg.cars[2].finished=true; fg.cars[2].position=1; F.tick(g,fg,0.1)
 assert(g.sanctions.cars[2].time==0)
end
-- Pénalités répétées : au-delà du nombre toléré (partagé avec les dépassements sous drapeau), drapeau noir.
tests.SAN_ESCALATION_142=function()
 local e,f=race(4,{penaltyDisqualify=2,sanProcedureKind='time'})
 for _=1,3 do e.grid.aiJump[2]=true; F.tick(e,f,0.1) end
 assert(e.sanctions.cars[2].dq and logged(e,'sanction IA: Driver_2 drapeau noir (trop d infractions)'),'black flag')
 e.penalties.ai.count[3]=2; e.grid.aiJump[3]=true; F.tick(e,f,0.1)
 assert(e.sanctions.cars[3].dq,'shared with the flag offences')
end
-- Trop tard pour purger (moins de tours restants que le délai) : ajoutée au résultat.
tests.SAN_LATE_142=function()
 local e,f=F.scene('C',4); f.sessionLaps=10; f.leaderLaps=9; f.timedRace=false; F.tick(e,f,0.1)
 assert(e.race.known and e.race.lapsLeft==1)
 e.grid.aiJump[2]=true; F.tick(e,f,0.1)
 local c=e.sanctions.cars[2]
 assert(c.pending=='' and c.time==K.sanDriveTime and logged(e,'trop tard pour la purger'),'converted')
 local g,fg=F.scene('C',4); fg.sessionLaps=10; fg.leaderLaps=9; fg.timedRace=false; g.profiles.C.sanUnservedTime=false; E.changed(g); F.tick(g,fg,0.1)
 g.grid.aiJump[2]=true; F.tick(g,fg,0.1); assert(g.sanctions.cars[2].pending=='drive','kept when unserved penalties are not added')
end
-- Faux départ d'une IA pendant les feux d'un départ arrêté de l'app : relevé une fois, oublié avec la grille.
tests.SAN_GRID_JUMP_142=function()
 local e,f=race(3)
 local g=Grid.new(); Grid.reset(g)
 local t={standing='lights',cars={},gridLit=0}
 for i=1,K.maxCars do t.cars[i]={incident=false,since=0} end
 local now=e.time
 g.phase='lights'; g.since=now-10; g.lightsAt=now; g.outAt=now+10; g.slots={{spline=f.cars[2].spline,lateral=0}}; g.slotOf[2]=1; g.held[2]=true
 speed(f,2,0)
 Grid.step(g,t,f,now,e.commands,1,0,e.log,e.states,nil)
 assert(g.aiRef[2]==f.cars[2].spline and not g.aiJump[2],'reference at its place')
 Grid.step(g,t,f,now+0.1,e.commands,1,0,e.log,e.states,nil); assert(not g.aiJump[2],'still')
 F.place(f,2,f.cars[2].z+2,5)
 Grid.step(g,t,f,now+0.2,e.commands,1,0,e.log,e.states,nil)
 assert(not g.aiJump[2],'not yet: a sustained movement is needed')
 Grid.step(g,t,f,now+0.2+K.aiJumpDwell,e.commands,1,0,e.log,e.states,nil)
 assert(g.aiJump[2]==true and logged(e,'faux depart IA: Driver_2, 2.0 m'),'jump start')
 Grid.reset(g); assert(g.aiJump[2]==nil and g.aiRef[2]==nil,'forgotten with the grid')
end
-- Jamais en journée circuit, section décochée : rien ; app arrêtée un moment : états passagers oubliés ; changement de
-- session : tout oublié.
tests.SAN_SAFETY_142=function()
 local j,fj=F.scene('J',3); F.tick(j,fj,0.1)
 assert(not j.run.sanTrackLimits and not j.run.sanWrongWay and not j.run.sanMessages,'track day: hidden, off')
 out(fj,2,true); F.tick(j,fj,1); out(fj,2,false); F.tick(j,fj,0.1)
 assert(#j.sanctions.rows==0 and not logged(j,'IA: Driver_2'),'nothing in a track day')
 local e,f=race(4,{section_sanctions=false})
 assert(not e.run.sanTrackLimits and not e.run.sanCutPenalty and not e.run.sanPitSpeed and not e.run.sanWrongWay and not e.run.sanGiveBack,'section unticked')
 learn(e,2,30); local z=f.cars[2].z
 out(f,2,true); F.tick(e,f,1); F.place(f,2,z+100,100); out(f,2,false); F.tick(e,f,1)
 f.cars[3].pit=true; speed(f,3,150); F.tick(e,f,8); f.cars[3].pit=false; speed(f,3,100)
 e.grid.aiJump[4]=true; F.tick(e,f,0.1)
 assert(#e.sanctions.rows==0 and not logged(e,'sanction IA') and not logged(e,'limites de piste IA') and e.sanctions.cars[4].pending=='','nothing with the section unticked')
 for i=1,f.count do assert(e.commands[i].throttleLimit==1) end
 local r=race(); local c=r.sanctions.cars[2]; F.place(r.frame,3,-30,100); F.tick(r,r.frame,0.2)
 c.cutLimit=0.5; c.owedTo=3; c.owedUntil=0; r.sanctions.lastAt=r.time-5; F.tick(r,r.frame,1/60)
 assert(c.cutLimit==1 and c.owedTo==0 and c.time==0,'transient state dropped after a pause of the app')
 c.time=5; c.pending='drive'; Sanctions.reset(r.sanctions,r.time); assert(c.time==0 and c.pending=='' and #r.sanctions.rows==0,'session change')
end
-- Rechargement de l'app : pénalités, temps et drapeau noir rendus à la même voiture, même session seulement.
tests.SAN_SERIALIZE_142=function()
 local e,f=race()
 local c=e.sanctions.cars[2]; c.time=10; c.count=2; c.pending='drive'; c.pendingLaps=1; c.strikes=3
 local text=Sanctions.serialize(e.sanctions,f.session); assert(text:find('2,car_2,10.0,2,drive,1,3,0',1,true),text)
 local g,fg=race(); Sanctions.restore(g.sanctions,text,fg.session); F.tick(g,fg,0.1)
 local d=g.sanctions.cars[2]; assert(d.time==10 and d.pending=='drive' and d.pendingLaps==1 and d.strikes==3 and d.count==2,'restored')
 local h,fh=race(); Sanctions.restore(h.sanctions,text,fh.session+1); F.tick(h,fh,0.1); assert(h.sanctions.cars[2].time==0,'text of another session ignored')
 Sanctions.restore(h.sanctions,text,fh.session); fh.session=fh.session+1; F.tick(h,fh,0.1); assert(h.sanctions.cars[2].time==0,'reloaded in another session: ignored')
 assert(Sanctions.serialize(h.sanctions,fh.session)=='','nothing to keep')
end
-- Charge de course (30 IA) avec des sorties des limites, des passages rapides dans la voie des stands et un contresens
-- injectés : aucune erreur, accélérateur jamais sous K.sanCutThrottle, jamais le joueur, aucune chaîne par image.
tests.SAN_WORKLOAD_142=function()
 local W=require('tests/workload')
 local e,f=W.prepare(30); e.g.autoProfile=false; E.select(e,'C'); E.changed(e)
 local dt=1/60; local low=1
 for frame=1,3600 do
  local t=e.time; W.animate(f,t,dt)
  for i=2,f.count do local a=f.cars[i]; local off=(frame+i*37)%900<40; a.wheelsOut=off and 4 or 0; a.offtrack=off end
  local w=f.cars[7]; if frame>1800 and frame<2400 then w.distance=w.distance-2*w.speed*dt; w.spline=(w.distance/f.length)%1; w.lx=-w.lx; w.lz=-w.lz end
  E.step(e,f,dt)
  assert(e.errors==0,'no car error')
  for i=1,f.count do low=math.min(low,e.commands[i].throttleLimit) end
 end
 assert(low>=K.sanCutThrottle-1e-9,'throttle never below the cut floor: '..low)
 assert(e.sanctions.cars[1].strikes==0 and e.sanctions.cars[1].time==0 and not e.sanctions.cars[1].dq,'never the player')
 assert(e.sanctions.cars[7].dq,'wrong way: black flag')
 assert(#e.sanctions.rows<=K.sanRowsMax+K.sanClassRows,'bounded rows')
end
return tests
