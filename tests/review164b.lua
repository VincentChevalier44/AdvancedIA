-- Beta 1.64, lot 2 (référentiel des comportements pilotes, situation 01-16 ; décision du pilote du 13 novembre) : départ
-- avorté. Nouvel incident sur la grille ou aux feux d'une grille de l'app (fin du tour de formation, relance arrêtée
-- après un drapeau rouge) : tout le peloton refait un tour (tour de formation ou tour de relance), la voiture à l'origine
-- est retenue sur place jusqu'au passage du peloton puis part de l'arrière si elle a été doublée ; au-delà de
-- K.startAbortMax départs avortés, départ lancé. Noms LOCK_*_164 (tests/LOCKS.md) et START_ABORT_*_164. Chargé par
-- tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local U=require('src/util')
local L=require('src/lang')
local LE=require('src/lang_en')
local B=require('src/bridge')
local Grid=require('src/grid')
local Formation=require('src/formation')
local Incidents=require('src/incidents')
local Panel=require('src/panel')
local J=require('src/journal')
local JE=require('src/journal_en')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Circuit de 1200 m : le tour en plus dure moins que la fenêtre d'un choc (K.crashWindow s) : la fautive arrêtée à sa
-- nouvelle place n'est pas un nouvel incident (choc oublié à la nouvelle grille).
local LENGTH=1200
local function slotZ(k) return -(K.gridFirst+(k-1)*K.gridPitch) end
-- Grille : voiture 2 en pole, voiture 3 deuxième, joueur (voiture 1) troisième, les autres derrière.
local function place(i) return i==2 and 1 or i==3 and 2 or i==1 and 3 or i end
-- Journal agrandi : les scènes durent plusieurs tours (les lignes du départ restent comptables).
local function bigLog(e) e.log=U.newLog(4000,K.logRate,K.logDedup) end
-- Course : grille arrêtée devant la ligne, puis feu vert d'AC (front montant de la session) : tour de formation.
local function start(n,want,setup)
 local e,f=F.scene('C',n); bigLog(e); C.preset('Course','C',e.profiles.C); e.profiles.C.raceStart=want; e.profiles.C.startRealism=false; f.length=LENGTH
 for i=1,n do f.cars[i].position=place(i); F.place(f,i,slotZ(place(i)),0) end
 if setup then setup(e,f) end
 E.changed(e); e.gridCaps=true; F.tick(e,f,1/60)
 f.started=false; F.tick(e,f,1/60)
 f.started=true; F.tick(e,f,1/60)
 return e,f
end
-- Peloton en file à 100 km/h jusqu'à ce que cond() soit vrai (au plus seconds s) ; voitures gelées (frozen) immobiles.
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
 B.publish(B.new('Beta 1.64'),out,e,f)
 return out
end
-- Protection contre le renvoi d'AC (posée par l'applicateur en jeu) : choisie le temps d'un test, toujours rendue.
local function guarded(on,fn)
 local was=Grid.retireGuard; Grid.retireGuard=on
 local ok,err=pcall(fn); Grid.retireGuard=was
 if not ok then error(err,0) end
end
-- Grille appelée (fin du tour), voitures posées à leur place et à l'arrêt, jusqu'à l'allumage des feux.
local function toLights(e,f,seconds)
 local t=e.incidents
 assert(roll(e,f,seconds or 90,function() return t.standing=='grid' end),'grid called')
 for i=1,f.count do f.cars[i].frozen=false; local k=e.grid.slotOf[i]; if k>0 then F.place(f,i,slotZ(k),0) end end
 for _=1,240 do if t.standing=='lights' then break end; F.tick(e,f,0.5) end
 assert(t.standing=='lights','lights on, got '..tostring(t.standing))
end
-- Tête-à-queue sur place (recette de GRID_TIMEOUT_ABORT_134), images de 1/60 s jusqu'à l'annulation ; renvoie dans
-- l'image de l'abandon, voitures en cause à l'arrêt et gelées.
local function spin(e,f,list)
 local before=count(e,'depart arrete annule')
 for _,i in ipairs(list) do f.cars[i].slip=K.slipDegrees+20; f.cars[i].kmh=80 end
 F.tick(e,f,0.2)
 for _,i in ipairs(list) do f.cars[i].kmh=30 end
 for _=1,300 do if count(e,'depart arrete annule')>before then break end; F.tick(e,f,1/60) end
 assert(count(e,'depart arrete annule')==before+1,'start aborted once')
 for _,i in ipairs(list) do local a=f.cars[i]; a.slip=0; a.kmh=0; a.speed=0; a.frozen=true end
end
-- Voiture gelée relâchée : elle repart à l'allure du peloton.
local function free(f,i) local a=f.cars[i]; a.frozen=false; a.kmh=100; a.speed=100/3.6 end
-- Grille formée : voitures à leur place, à l'arrêt, images jusqu'à l'extinction des feux.
local function toGo(e,f)
 local t=e.incidents
 for i=1,f.count do f.cars[i].frozen=false; local k=e.grid.slotOf[i]; if k>0 then F.place(f,i,slotZ(k),0) end end
 for _=1,60*90 do if t.standing=='go' then break end; F.tick(e,f,1/60) end
 assert(t.standing=='go','lights out, got '..tostring(t.standing))
end

-- Départ avorté aux feux après le tour de formation : tout le peloton refait un tour de formation (même image), la
-- fautive retenue sur place, ordre du tour en plus = grille avortée ; ni course lancée ni premier tour attentif.
tests.LOCK_START_ABORT_EXTRA_LAP_164=function()
 guarded(true,function()
  local e,f=start(4,'formation')
  local t=e.incidents
  toLights(e,f)
  spin(e,f,{3})
  -- Image de l'abandon.
  assert(t.standing=='none','grid cancelled')
  assert(t.neutral and t.relaunch and t.formation and t.formationKind=='formation' and not t.formationAborted,'one more formation lap, same machinery')
  assert(e.formation.phase=='lap' and e.formation.report==true,'formation module back in its lap, start report still postponed')
  assert(t.startAborts==1 and t.startAbortPending==false,'attempt counted, armed in the same frame')
  local out=published(e,f); assert(out.standing=='form' and out.neutral==true,'bridge: form with neutral in the same frame, got '..tostring(out.standing))
  assert(t.messageKind=='startDelayed' and t.messageValue==1 and t.messageExtra==0,'announcement: start delayed, number 1, a standing start follows')
  assert(count(e,'depart retarde: depart avorte numero 1, un tour de formation de plus, puis depart arrete')==1,'logged')
  assert(t.cars[3].abortMark and t.cars[3].abortHold,'car 3 marked and held')
  assert(count(e,'depart retarde: Driver_3 retenue sur place jusqu au passage du peloton')==1,'hold logged')
  assert(t.formationRank[2]==1 and t.formationRank[3]==2 and t.formationRank[1]==3 and t.formationRank[4]==4 and t.formationRankN==4,'order of the aborted grid kept for the extra lap')
  assert(not t.restart,'no « until the line » rule during the extra lap')
  for i=1,4 do assert(not t.cars[i].restart,'no-overtaking flag cleared for car '..i) end
  -- Image suivante.
  F.tick(e,f,1/60)
  assert(t.relaunchLeader==2,'leader of the extra lap: the pole car, never the marked car ('..tostring(t.relaunchLeader)..')')
  assert(e.commands[3].stopHold and e.commands[3].noRetire,'car 3 held in place, protected from AC')
  assert(count(e,'grille annulee')==0,'the race is not launched')
  assert(not e.fl.on and e.launchAt==nil,'no careful first lap, no launch yet')
  -- Tout le tour en plus, jusqu'à la nouvelle grille.
  assert(roll(e,f,90,function() if not t.cars[3].abortHold and f.cars[3].frozen then free(f,3) end; return t.standing=='grid' end),'new grid after the extra lap')
  assert(count(e,'reprise: toutes les voitures ont franchi la ligne')==0,'no stray « restart » line')
  assert(count(e,'depart: depart arrete (SS) apres le tour de formation')==2,'second grid of the race start')
 end)
end
-- La fautive doublée pendant le tour en plus part de l'arrière de la nouvelle grille ; une fautive pas doublée (joueur
-- reparti aussitôt) garde sa place ; deux fautives dans la même image.
tests.LOCK_START_ABORT_BACK_OF_GRID_164=function()
 guarded(true,function()
  local e,f=start(4,'formation')
  local t=e.incidents
  toLights(e,f)
  spin(e,f,{3})
  for _=1,60 do
   F.tick(e,f,1/60)
   assert(e.commands[3].stopHold and e.commands[3].recover==false and t.cars[3].abortHold,'held while the field has not passed')
  end
  -- Le peloton est passé : 2, joueur, 4, puis la fautive.
  f.cars[2].position=1; f.cars[1].position=2; f.cars[4].position=3; f.cars[3].position=4
  F.tick(e,f,1/60)
  assert(count(e,'depart retarde: Driver_3 repart derriere le peloton apres')==1 and count(e,'(peloton passe)')==1,'released once the field has passed')
  assert(e.commands[3].gridWake and not t.cars[3].abortHold,'woken for one frame')
  F.tick(e,f,1/60); assert(not e.commands[3].gridWake,'one frame only')
  free(f,3)
  toLights(e,f)
  local g=e.grid
  assert(g.slotOf[2]==1 and g.slotOf[1]==2 and g.slotOf[4]==3 and g.slotOf[3]==4,'car 3 from the back of the grid ('..g.slotOf[2]..g.slotOf[1]..g.slotOf[4]..g.slotOf[3]..')')
  assert(count(e,'grille: Driver_3 part de l arriere de la grille (depart avorte)')==1 and count(e,'place perdue pendant le tour de formation')==0,'logged as an aborted start')
  assert(t.abortMarks==0 and not t.cars[3].abortMark,'marks used once')
  assert(count(e,'depart: depart arrete (SS) apres le tour de formation')==2,'second grid')
  toGo(e,f)
  assert(e.fl.kind=='depart arrete' and e.startSpeedLogged~=nil and e.formation.report==false,'race start reported once, at the real lights out')
  assert(t.startAborts==0,'counter cleared at lights out')
  -- (b) Joueur à l'origine, reparti aussitôt sans être doublé : marqué, jamais retenu, garde sa place.
  local p,fp=start(4,'formation')
  local tp=p.incidents
  toLights(p,fp)
  spin(p,fp,{1}); fp.cars[1].frozen=false
  assert(tp.cars[1].abortMark and not tp.cars[1].abortHold and count(p,'retenue sur place')==0,'player marked, never held')
  F.tick(p,fp,1/60); assert(not p.commands[1].stopHold,'no hold command for the player')
  toLights(p,fp)
  assert(p.grid.slotOf[1]==3,'not passed: keeps its place ('..p.grid.slotOf[1]..')')
  -- (c) Deux fautives dans la même image, toutes deux doublées.
  local q,fq=start(5,'formation')
  local tq=q.incidents
  toLights(q,fq)
  spin(q,fq,{3,4})
  assert(count(q,'depart arrete annule')==1 and tq.abortMarks==2 and tq.cars[3].abortMark and tq.cars[4].abortMark,'both marked, one abort')
  fq.cars[2].position=1; fq.cars[1].position=2; fq.cars[5].position=3; fq.cars[3].position=4; fq.cars[4].position=5
  F.tick(q,fq,1/60); free(fq,3); free(fq,4)
  toLights(q,fq)
  local gq=q.grid
  assert(gq.slotOf[2]==1 and gq.slotOf[1]==2 and gq.slotOf[5]==3 and gq.slotOf[3]==4 and gq.slotOf[4]==5,'car 3 then car 4 at the back')
  assert(count(q,'(depart avorte)')==2,'two lines')
 end)
end
-- Retenue bornée : jamais au-delà de K.startBackHold s (K.startBackHoldBare sans protection), jamais dépannée ni
-- redémarrée par l'app pendant la retenue ; une épave n'est pas retenue.
tests.LOCK_START_ABORT_HOLD_164=function()
 assert(K.startBackHold+K.obstacleTime+3<=K.neutralRecoverTime,'released before the neutralisation recovery can take it')
 local function scene(guard,setup)
  local e,f=start(4,'formation',function(e2) e2.profiles.C.section_accidents=true end)
  toLights(e,f)
  if setup then setup(e,f) end
  spin(e,f,{3})
  return e,f,e.incidents
 end
 local function holdFor(e,f,t,seconds,each)
  while e.time-t.cars[3].abortHoldAt<seconds-1e-6 and t.cars[3].abortHold do F.tick(e,f,1/60); if each then each() end end
 end
 local function released(e,f,t,limit)
  for _=1,math.floor(limit*60) do
   F.tick(e,f,1/60)
   if not t.cars[3].abortHold then
    assert(e.commands[3].gridWake and not e.commands[3].stopHold,'woken, hold lifted')
    F.tick(e,f,1/60); assert(not e.commands[3].gridWake,'one frame only')
    return true
   end
  end
  return false
 end
 -- (a) Avec la protection.
 guarded(true,function()
  local e,f,t=scene(true)
  assert(t.cars[3].abortHold,'held')
  holdFor(e,f,t,K.startBackHold-0.5)
  assert(t.cars[3].abortHold and e.commands[3].stopHold,'still held half a second before the limit')
  assert(t.cars[3].incident,'still an incident')
  assert(count(e,'IA accidentee: redemarrage demande')==0 and not t.cars[3].rejoining,'no restart request during the hold')
  assert(released(e,f,t,1),'released at the limit')
  assert(count(e,'(attente maximale)')==1,'maximum wait logged')
 end)
 -- (b) Sans la protection : K.startBackHoldBare s.
 guarded(false,function()
  local e,f,t=scene(false)
  holdFor(e,f,t,K.startBackHoldBare-0.5)
  assert(t.cars[3].abortHold,'held without the protection')
  assert(released(e,f,t,1) and math.abs(e.time-t.cars[3].abortHoldAt-K.startBackHoldBare)<0.1,'released at K.startBackHoldBare s')
 end)
 -- (c) Retenue allongée le temps du test : aucun dépannage ni redémarrage même au-delà du délai de dépannage.
 local kept=K.startBackHold
 local ok,err=pcall(guarded,true,function()
  K.startBackHold=30
  local e,f,t=scene(true)
  holdFor(e,f,t,21,function()
   assert(e.commands[3].recover==false and not t.cars[3].rejoining,'never recovered nor restarted while held')
  end)
  assert(t.cars[3].abortHold and t.cars[3].still>=K.neutralRecoverTime and e.commands[3].recover==false,'held past the recovery delay ('..t.cars[3].still..')')
  for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.index==3 then assert(not r.message:find('redemarrage demande',1,true) and not r.message:find('ne peut plus rouler',1,true),'no rejoin line for car 3: '..r.message) end end
 end)
 K.startBackHold=kept; assert(ok,err)
 -- (d) Épave (suspension cassée) : marquée, jamais retenue (dépannée comme avant).
 guarded(true,function()
  local e,f,t=scene(true,function(_,f2) f2.cars[3].damageSuspension=K.brokenSuspension end)
  assert(t.cars[3].abortMark and not t.cars[3].abortHold and count(e,'retenue sur place')==0,'broken car marked, not held')
 end)
end
-- Au-delà de K.startAbortMax départs avortés : départ lancé à la fin du tour ; compteur remis à zéro au drapeau vert et
-- au feu vert d'AC.
tests.LOCK_START_ABORT_MAX_164=function()
 guarded(true,function()
  local e,f=start(4,'formation')
  local t=e.incidents
  toLights(e,f)
  local first=e.grid.outAt-e.grid.lightsAt
  spin(e,f,{3}); F.tick(e,f,1/60); free(f,3)
  toLights(e,f)
  local second=e.grid.outAt-e.grid.lightsAt
  assert(math.abs(first-second)>1e-6,'lights-out delay drawn again for the new attempt')
  spin(e,f,{4})
  assert(t.messageKind=='startDelayed' and t.messageValue==2 and t.messageExtra==0,'second abort announced')
  assert(count(e,'depart avorte numero 2, un tour de formation de plus, puis depart arrete')==1,'second abort logged')
  F.tick(e,f,1/60); free(f,4)
  toLights(e,f)
  spin(e,f,{2})
  assert(t.formationKind=='rolling' and t.messageValue==3 and t.messageExtra==1,'third abort: rolling start announced')
  assert(count(e,'depart avorte numero 3, un tour de formation de plus, puis depart lance')==1,'third abort logged')
  assert(t.formationRankN==0,'no grid order to keep')
  F.tick(e,f,1/60); free(f,2)
  e.startRadar=99
  local grid=false
  assert(roll(e,f,90,function() if t.standing=='grid' then grid=true end; return not t.neutral end),'green flag')
  assert(not grid,'no fourth grid')
  F.tick(e,f,1/60)
  assert(count(e,'depart lance: drapeau vert a la ligne')==1 and e.fl.kind=='depart lance' and e.startRadar~=99,'rolling start, start reported')
  assert(t.startAborts==0 and t.abortMarks==0,'cleared at the green')
  assert(count(e,'depart: depart arrete (SS) apres le tour de formation')==3,'three grids')
  -- Course relancée par AC : le feu vert suivant repart de zéro.
  local r,fr=start(4,'formation')
  r.incidents.startAborts=2
  fr.started=false; F.tick(r,fr,1/60); fr.started=true; F.tick(r,fr,1/60)
  assert(r.incidents.startAborts==0 and r.incidents.formation,'cleared at AC’s green')
 end)
end
-- Relance arrêtée après un drapeau rouge : départ avorté : un tour de relance de plus ; la fautive part de l'arrière de
-- l'ordre du drapeau rouge si elle est doublée ; au 3e, départ lancé.
local function redScene(n,setup)
 local e,f=F.scene('C',n or 4); bigLog(e); C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart='standing'; e.profiles.C.raceStart='standing'; f.length=LENGTH
 for i=1,f.count do f.cars[i].position=place(i); F.place(f,i,slotZ(place(i)),0) end
 if setup then setup(e,f) end
 E.changed(e); e.gridCaps=true; F.tick(e,f,1/60)
 local t=e.incidents
 t.redOrder={}; for i=1,f.count do t.redOrder[place(i)]=i; t.redRank[i]=place(i) end; t.redOrderN=f.count
 t.neutral=true; t.relaunch=true; t.neutralMode='fcy'; t.neutralSince=e.time; t.neutralUntil=e.time+1e6; t.relaunchSpanUntil=e.time; t.relaunchLeader=0; t.relaunchTravel=0
 toLights(e,f)
 e.startRadar=99
 return e,f,t
end
local function panelShort(e,f)
 e.panel.at=-math.huge; Panel.update(e.panel,e.incidents,f,e.run,'C',e.time,nil,e)
 return e.panel.short
end
tests.LOCK_START_ABORT_RED_164=function()
 guarded(true,function()
  local e,f,t=redScene()
  assert(count(e,'relance: depart arrete (SS)')==1,'red-flag restart grid')
  spin(e,f,{2})
  assert(t.neutral and t.relaunch and not t.formation,'one more restart lap')
  assert(e.formation.phase=='none' and e.formation.report==false,'not a race start')
  assert(t.startAbortRoll==false and t.redOrderN==4 and t.redRank[2]==1,'red-flag order kept')
  assert(t.messageKind=='startDelayed','announced')
  assert(count(e,'depart avorte numero 1, un tour de relance de plus, puis depart arrete')==1,'logged')
  F.tick(e,f,1/60)
  assert(t.relaunchLeader==3,'leader: the next car, never the marked one ('..tostring(t.relaunchLeader)..')')
  assert(Incidents.restoring(t,2,3)==false,'the marked car does not « take back its place »')
  assert(panelShort(e,f)==L.flagShort.standingLap,'panel: restart lap, then a standing start')
  f.cars[3].position=1; f.cars[1].position=2; f.cars[4].position=3; f.cars[2].position=4
  F.tick(e,f,1/60); assert(not t.cars[2].abortHold,'released'); free(f,2)
  toLights(e,f)
  assert(count(e,'relance: depart arrete (SS)')==2,'second restart grid')
  assert(e.grid.slotOf[3]==1 and e.grid.slotOf[2]==4,'car 2 from the back of the red-flag order')
  assert(count(e,'(depart avorte)')==1,'logged')
  toGo(e,f)
  assert(e.startRadar==99,'no race start report at a restart')
  assert(e.fl.kind=='depart arrete' and t.redOrderN==0 and t.startAborts==0,'lights out: order and counter cleared')
  -- 2e scène : troisième départ avorté de suite : départ lancé à la fin du tour de relance.
  local r,fr,tr=redScene()
  tr.startAborts=2
  spin(r,fr,{2})
  assert(tr.startAbortRoll==true and tr.messageValue==3 and tr.messageExtra==1,'third: rolling start announced')
  F.tick(r,fr,1/60)
  assert(panelShort(r,fr)==L.flagShort.rolling,'panel: restart lap, then a rolling start')
  fr.cars[3].position=1; fr.cars[1].position=2; fr.cars[4].position=3; fr.cars[2].position=4
  F.tick(r,fr,1/60); free(fr,2)
  assert(roll(r,fr,90,function() return not tr.neutral end),'end of the restart lap')
  assert(count(r,'relance: depart lance apres 3 departs avortes')==1,'logged')
  assert(tr.standing=='none' and tr.restart,'rolling restart, no overtaking until the line')
  F.tick(r,fr,1/60)
  assert(r.fl.kind=='relance' and r.startRadar==99,'armed as a restart')
  assert(tr.startAborts==0 and tr.startAbortRoll==false,'cleared at the green')
 end)
end
-- Abandon causé par la dernière voiture : les autres, arrêtées à leur place, ne deviennent jamais des incidents.
tests.START_ABORT_NO_FALSE_INCIDENT_164=function()
 guarded(true,function()
  local e,f=start(4,'formation')
  local t=e.incidents
  toLights(e,f)
  spin(e,f,{4})
  assert(t.cars[2].moved==false and e.states[2].obstacleSlow==0,'grid cars start the extra lap as from AC’s green')
  assert(t.cars[4].abortMark and not t.cars[4].abortHold,'last car marked, nobody behind it: not held')
  F.tick(e,f,3)
  assert(count(e,'incident:')==1,'only the car at fault')
  assert(count(e,'zone jaune ouverte: Driver_2')==0 and count(e,'zone jaune ouverte: Driver_3')==0,'no yellow for cars waiting on the grid')
 end)
end
-- Refus (comportement d'avant, une ligne) : neutralisation déjà déclarée, course relancée.
tests.START_ABORT_REFUSED_164=function()
 guarded(true,function()
  local e,f=start(4,'formation',function(e2) e2.profiles.C.neutralization='fcy' end)
  local t=e.incidents
  toLights(e,f)
  assert(e.formation.phase=='grid','formation module waiting for the grid')
  t.neutral=true; t.relaunch=false; t.neutralMode='fcy'; t.neutralSince=e.time; t.neutralUntil=e.time+1e6
  spin(e,f,{3})
  assert(count(e,'depart retarde impossible (neutralisation): grille annulee')==1,'refused, logged')
  assert(t.startAborts==0 and t.abortMarks==0 and not t.cars[3].abortHold and not t.cars[3].abortMark,'nothing kept')
  F.tick(e,f,1/60)
  assert(count(e,'depart: grille annulee apres le tour de formation, la course est lancee')==1 and e.launchAt~=nil,'race launched as before')
  -- Appel direct hors course.
  local r,fr=start(4,'standing')
  r.incidents.startAbortPending='start'; r.incidents.startAborts=1
  r.profile='P'
  local res=Formation.rearm(r.formation,r,fr,r.time)
  r.profile='C'
  assert(res==false and count(r,'depart retarde impossible (course relancee): grille annulee')==1 and r.incidents.startAborts==0,'outside a race: refused')
 end)
end
-- Grille posée à la main (pas de l'app) : abandon exactement comme avant ; t minimal accepté.
tests.START_ABORT_MANUAL_GRID_UNCHANGED_164=function()
 local e2,f2=F.scene('C',4); C.preset('Course','C',e2.profiles.C); E.changed(e2); e2.gridCaps=true
 for i=1,4 do f2.cars[i].position=i; F.place(f2,i,-300-i*50,60) end
 F.tick(e2,f2,0.2); e2.incidents.standing='grid'; F.tick(e2,f2,0.5)
 f2.cars[3].slip=K.slipDegrees+20; f2.cars[3].kmh=80; F.tick(e2,f2,0.2); f2.cars[3].kmh=30; F.tick(e2,f2,K.spinTime+1)
 local t=e2.incidents
 assert(t.standing=='none' and e2.grid.phase=='none' and count(e2,'depart arrete annule: nouvel incident')==1,'aborted on a new incident')
 assert(not t.neutral and not t.formation and t.startAborts==0 and t.messageKind~='startDelayed' and count(e2,'depart retarde')==0,'nothing more')
 assert(not t.cars[3].abortMark and not e2.commands[3].stopHold and e2.grid.from=='','no mark, no hold')
 -- t minimal (bancs unitaires) : aucune erreur.
 for _,from in ipairs({'','start'}) do
  local g=Grid.new(); Grid.reset(g)
  local tm={standing='lights',cars={},gridLit=0}; for i=1,K.maxCars do tm.cars[i]={incident=false,since=0} end
  local now=e2.time
  g.phase='lights'; g.since=now-10; g.lightsAt=now; g.outAt=now+10; g.slots={{spline=f2.cars[2].spline,lateral=0}}; g.slotOf[2]=1; g.held[2]=true; g.from=from
  tm.cars[2].incident=true; tm.cars[2].since=now
  assert(Grid.step(g,tm,f2,now,e2.commands,1,0,e2.log,e2.states,nil)==nil and tm.standing=='none','minimal state accepted ('..from..')')
  assert(Grid.step(g,tm,f2,now+0.1,e2.commands,1,0,e2.log,e2.states,nil)==nil,'next frame too')
 end
end
-- Délai d'extinction : tirage d'avant sans départ avorté ; tiré de nouveau à chaque tentative.
tests.START_ABORT_LIGHTS_VARY_164=function()
 guarded(true,function()
  local function scene(aborts)
   local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C); e.profiles.C.redRestart='standing'; E.changed(e); e.gridCaps=true
   for i=1,4 do f.cars[i].position=i; F.place(f,i,slotZ(i),0) end
   F.tick(e,f,0.2)
   local t=e.incidents; t.startAborts=aborts; t.standing='grid'
   for _=1,600 do if t.standing=='lights' then break end; F.tick(e,f,1/60) end
   assert(t.standing=='lights','lights')
   return e.grid.outAt-e.grid.lightsAt,e.runtimeG.seed or 0,t.reds or 0
  end
  local base=K.lightStep*(K.gridLights-1)+K.lightsOutMin
  local d1,s1,r1=scene(0)
  assert(math.abs(d1-(base+U.unit(s1,r1,K.lightsOutSalt)*(K.lightsOutMax-K.lightsOutMin)))<1e-9,'same draw as before')
  local d2,s2,r2=scene(1)
  assert(math.abs(d2-(base+U.unit(s2,r2+K.startAbortSalt,K.lightsOutSalt)*(K.lightsOutMax-K.lightsOutMin)))<1e-9,'drawn with the attempt')
  assert(math.abs(d2-(base+U.unit(s2,r2,K.lightsOutSalt)*(K.lightsOutMax-K.lightsOutMin)))>1e-6,'different delay for the new attempt')
 end)
end
-- Drapeau rouge pendant le tour de relance en plus : tout le départ avorté est oublié, la retenue tombe.
tests.START_ABORT_RED_DURING_LAP_164=function()
 local kept=K.startBackHold
 local ok,err=pcall(guarded,true,function()
  K.startBackHold=30
  local e,f,t=redScene(5,function(e2) e2.profiles.C.redFlagEnabled=true; e2.profiles.C.redFlagCars=3 end)
  spin(e,f,{2})
  assert(t.cars[2].abortHold and t.startAborts==1,'held')
  roll(e,f,1,function() return false end)
  F.block(f,{3,4,5},600); for _,i in ipairs({3,4,5}) do f.cars[i].frozen=true end
  local was=false
  for _=1,60*20 do if t.red then break end; was=t.cars[2].abortHold; F.tick(e,f,1/60) end
  assert(t.red and was,'red flag while car 2 is still held')
  assert(t.startAborts==0 and t.abortMarks==0 and t.abortHolds==0 and not t.cars[2].abortMark,'start abort forgotten')
  F.tick(e,f,1/60)
  assert(not e.commands[2].stopHold,'hold dropped')
 end)
 K.startBackHold=kept; assert(ok,err)
end
-- Textes : messages des deux langues, priorité de l'annonce, journal traduit sans mot français.
tests.START_ABORT_TEXTS_164=function()
 for _,lang in ipairs({L,LE}) do
  local m=lang.messages.startDelayed
  assert(m and m[1]~='' and select(2,m[2]:gsub('%%d',''))==1 and select(2,m[2]:gsub('%%',''))==1,'one %d in the start-delayed message')
 end
 local t={frameId=1,messageFrame=-1,messagePriority=0,messageId=0}
 Incidents.message(t,'yellow',1); Incidents.message(t,'startDelayed',1,0); Incidents.message(t,'green')
 assert(t.messageKind=='startDelayed','above yellow and green')
 Incidents.message(t,'formation',3,0); assert(t.messageKind=='formation','same priority as formation (later one wins)')
 t.frameId=2; Incidents.message(t,'startDelayed',1,0); Incidents.message(t,'sc'); assert(t.messageKind=='sc','not above the Safety Car')
 local lines={
  'depart retarde: depart avorte numero 1, un tour de formation de plus, puis depart arrete',
  'depart retarde: depart avorte numero 3, un tour de formation de plus, puis depart lance',
  'depart retarde: depart avorte numero 2, un tour de relance de plus, puis depart arrete',
  'depart retarde: Driver_3 retenue sur place jusqu au passage du peloton',
  'depart retarde: Driver_3 repart derriere le peloton apres 4 s (peloton passe)',
  'depart retarde: Driver_3 repart derriere le peloton apres 15 s (attente maximale)',
  'depart retarde: Driver_3 repart derriere le peloton apres 2 s (incident termine)',
  'depart retarde: Driver_3 repart derriere le peloton apres 0 s (retenue annulee)',
  'depart retarde impossible (neutralisation): grille annulee',
  'depart retarde impossible (drapeau rouge): grille annulee',
  'depart retarde impossible (course relancee): grille annulee',
  'depart retarde impossible (formation inactive): grille annulee',
  'depart retarde impossible (circuit inconnu): grille annulee',
  'grille: Driver_3 part de l arriere de la grille (depart avorte)',
  'relance: depart lance apres 3 departs avortes',
 }
 local french={'depart','retarde','avorte','tour','plus','peloton','retenue','derriere','grille','annulee','arrete','lance','relance','passe','termine','attente','drapeau','rouge','course','circuit','inconnu','arriere','apres','sur','jusqu','au','de','la','numero'}
 for _,line in ipairs(lines) do
  local text,rule=J.english(line,true)
  assert(rule~=nil,'no rule for: '..line)
  assert(not text:find('[\192-\255]'),'accent in: '..text)
  for word in text:gmatch('[%a]+') do for _,w in ipairs(french) do assert(word~=w,'French word « '..w..' » in: '..text) end end
 end
 assert(JE.exact['peloton passe'] and JE.exact['incident termine'] and JE.exact['formation inactive'],'reasons translated')
end
-- Relecture 1.64 (lot 2) : fautive doublée seulement par le joueur (dernier sur la grille) : arrière de la grille aussi.
tests.LOCK_START_ABORT_PLAYER_PASSES_164=function()
 guarded(true,function()
  -- Grille : voitures 2, 3, 4 (IA), joueur (voiture 1) dernier.
  local pos={[2]=1,[3]=2,[4]=3,[1]=4}
  local e,f=start(4,'formation',function(_,f2) for i=1,4 do f2.cars[i].position=pos[i]; F.place(f2,i,slotZ(pos[i]),0) end end)
  local t=e.incidents
  toLights(e,f)
  assert(e.grid.slotOf[4]==3 and e.grid.slotOf[1]==4,'player last on the grid')
  spin(e,f,{4})
  assert(t.cars[4].abortMark and t.cars[4].abortHold,'car 4 held: the player started behind it')
  f.cars[1].position=3; f.cars[4].position=4
  F.tick(e,f,1/60)
  assert(not t.cars[4].abortHold and count(e,'(peloton passe)')==1,'released once the player has passed')
  free(f,4)
  toLights(e,f)
  assert(e.grid.slotOf[2]==1 and e.grid.slotOf[3]==2 and e.grid.slotOf[1]==3 and e.grid.slotOf[4]==4,'car 4 from the back ('..e.grid.slotOf[1]..e.grid.slotOf[4]..')')
  assert(count(e,'grille: Driver_4 part de l arriere de la grille (depart avorte)')==1,'logged')
 end)
end
-- Relecture 1.64 : relance après un drapeau rouge, joueur à l'origine du départ avorté : jamais « place à reprendre »
-- pendant le tour en plus ; renvoyé à l'arrière, ordre figé renuméroté (place et voiture à suivre justes jusqu'à
-- l'extinction).
tests.LOCK_START_ABORT_RED_PLAYER_MARKED_164=function()
 guarded(true,function()
  local e,f,t=redScene()
  spin(e,f,{1})
  assert(t.cars[1].abortMark and not t.cars[1].abortHold,'player marked, never held')
  local retake=0
  local function watch() if t.restartState=='retake' or t.messageKind=='restartRetake' then retake=retake+1 end end
  -- La voiture 4, partie derrière le joueur, le double pendant qu'il est arrêté.
  roll(e,f,8,function() watch(); return false end)
  assert(retake==0,'no « retake » for the player at fault during the extra lap ('..retake..')')
  assert(t.restartRank==3 and t.restartState=='ok','player shown in its place, nothing to take back')
  f.cars[2].position=1; f.cars[3].position=2; f.cars[4].position=3; f.cars[1].position=4
  free(f,1)
  assert(roll(e,f,90,function() watch(); return t.standing=='grid' end),'new restart grid')
  toLights(e,f)
  for _=1,30 do F.tick(e,f,1/60); watch() end
  assert(e.grid.slotOf[4]==3 and e.grid.slotOf[1]==4,'player from the back')
  assert(t.redRank[2]==1 and t.redRank[3]==2 and t.redRank[4]==3 and t.redRank[1]==4 and t.redOrder[4]==1 and t.redOrder[3]==4 and t.redOrderN==4,'red-flag order renumbered')
  assert(t.restartRank==4 and t.restartAhead==4,'player P4 behind car 4')
  assert(retake==0 and t.restartState~='retake','never told to take a place back ('..retake..')')
  assert(Incidents.restoring(t,1,4)==false and Incidents.restoring(t,4,1)==true,'car 4 keeps its place over the player')
 end)
end
-- Relecture 1.64 : victime d'un choc sur la grille (non marquée), circuit court : à la nouvelle grille, son arrêt à sa
-- place n'est pas un nouvel incident (choc de la grille avortée oublié).
tests.START_ABORT_GRID_CRASH_FORGOTTEN_164=function()
 guarded(true,function()
  local e,f=start(4,'formation',function(_,f2) f2.length=500; for i=1,4 do F.place(f2,i,slotZ(place(i)),0) end end)
  local t=e.incidents
  toLights(e,f)
  -- Voiture 4 heurtée à sa place : perte de plus de K.contactDrop km/h avec contact, pas encore un incident.
  local a=f.cars[4]; a.kmh=60; a.speed=60/3.6; F.tick(e,f,K.contactWindow+0.05)
  a.collided=true; a.kmh=0; a.speed=0; F.tick(e,f,K.contactWindow+0.05); a.collided=false
  local crashAt=t.cars[4].lastCrash
  assert(e.time-crashAt<1 and not t.cars[4].incident,'crash recorded, not an incident')
  spin(e,f,{3})
  assert(not t.cars[4].abortMark,'car 4 not at fault')
  f.cars[2].position=1; f.cars[1].position=2; f.cars[4].position=3; f.cars[3].position=4
  F.tick(e,f,1/60); free(f,3)
  toLights(e,f)
  assert(e.time-crashAt<K.crashWindow-3,'new grid within the crash window ('..(e.time-crashAt)..' s)')
  F.tick(e,f,3)
  assert(count(e,'depart arrete annule')==1 and t.startAborts==1 and t.standing=='lights','one aborted start only')
 end)
end
-- Relecture 1.64 : fautive retenue : attente maximale seulement piste libre derrière (jamais réveillée dans le peloton
-- qui la double) ; sans la protection, au plus K.startBackHoldBareMax s ; avec, jusqu'au passage du peloton.
tests.LOCK_START_ABORT_HOLD_TRAFFIC_164=function()
 assert(K.startBackHoldBareMax>K.startBackHoldBare and K.startBackHoldBareMax<Grid.GK.stillMax,'bare hold under the grid still limit')
 for _,guard in ipairs({false,true}) do
  guarded(guard,function()
   local e,f=start(22,'formation')
   local t=e.incidents
   toLights(e,f)
   spin(e,f,{3})
   assert(t.cars[3].abortHold,'car 3 (second on the grid) held')
   -- Le peloton part lentement (31 km/h) : les dernières voitures sont encore derrière la voiture 3 après l'attente.
   for i=1,f.count do if i~=3 then f.cars[i].own=31 end end
   local limit=guard and K.startBackHold or K.startBackHoldBare
   -- Image suivante : réveil de la grille annulée (une image) effacé.
   F.tick(e,f,1/60); assert(not e.commands[3].gridWake,'grid wake cleared')
   local woke=false
   roll(e,f,limit+1,function() if e.commands[3].gridWake then woke=true end; return false end)
   assert(t.cars[3].abortHold and not woke and t.cars[3].abortTraffic,'not woken into the traffic after the maximum wait')
   if not guard then
    assert(roll(e,f,K.startBackHoldBareMax-limit,function() return not t.cars[3].abortHold end),'released at the bare maximum')
    assert(math.abs(e.time-t.cars[3].abortHoldAt-K.startBackHoldBareMax)<0.1 and count(e,'(attente maximale)')==1,'at K.startBackHoldBareMax s')
   else
    local n=1; f.cars[2].position=1
    for i=1,f.count do if i~=2 and i~=3 then n=n+1; f.cars[i].position=n end end
    f.cars[3].position=f.count
    F.tick(e,f,1/60)
    assert(not t.cars[3].abortHold and count(e,'(peloton passe)')==1 and e.commands[3].gridWake,'released once the field has passed')
   end
  end)
 end
end
-- Relecture 1.64 : victime immobile 35 s à sa place puis tête-à-queue sur place : retenue, puis jamais dépannée à la
-- sortie de sa retenue (temps d'arrêt imposé par l'app non compté).
tests.LOCK_START_ABORT_RELEASE_NO_RECOVER_164=function()
 guarded(true,function()
  local e,f=start(4,'formation',function(e2) e2.profiles.C.section_accidents=true end)
  local t=e.incidents
  toLights(e,f)
  t.cars[3].stuckFor=35
  spin(e,f,{3})
  assert(t.cars[3].abortHold,'held')
  local guard=0
  while t.cars[3].abortHold do F.tick(e,f,1/60); guard=guard+1; assert(guard<60*20,'released') end
  assert(count(e,'(attente maximale)')==1,'released at the maximum wait')
  assert(e.commands[3].gridWake and e.commands[3].recover~=true,'not recovered in the release frame')
  for _=1,180 do F.tick(e,f,1/60); assert(e.commands[3].recover~=true,'not recovered after the release') end
 end)
end
-- Relecture 1.64 : course aux tours trop courte pour un tour en plus et un nouveau départ : refusé (comportement d'avant).
tests.START_ABORT_SHORT_RACE_164=function()
 guarded(true,function()
  local e,f=start(4,'formation')
  local t=e.incidents
  f.sessionLaps=3; f.leaderLaps=1; f.timedRace=false
  toLights(e,f)
  spin(e,f,{3})
  assert(count(e,'depart retarde impossible (course trop courte): grille annulee')==1,'refused, logged')
  assert(t.startAborts==0 and not t.cars[3].abortHold and not t.formation,'nothing kept')
  F.tick(e,f,1/60)
  assert(count(e,'depart: grille annulee apres le tour de formation, la course est lancee')==1 and e.launchAt~=nil,'race launched as before')
  local text=J.english('depart retarde impossible (course trop courte): grille annulee',true)
  assert(text:find('race too short',1,true),'translated: '..text)
  -- Encore un tour de course après le tour en plus et le nouveau départ : accepté.
  local r,fr=start(4,'formation')
  fr.sessionLaps=4; fr.leaderLaps=1; fr.timedRace=false
  toLights(r,fr); spin(r,fr,{3})
  assert(r.incidents.startAborts==1 and r.incidents.formation,'accepted')
  -- Course au temps : jamais refusé pour les tours.
  local q,fq=start(4,'formation')
  fq.sessionLaps=3; fq.leaderLaps=1; fq.timedRace=true
  toLights(q,fq); spin(q,fq,{3})
  assert(q.incidents.startAborts==1,'timed race: accepted')
 end)
end
-- Relecture 1.64 : IA tenue à sa place et heurtée (victime) : départ avorté quand même, mais ni marquée ni retenue.
tests.START_ABORT_GRID_VICTIM_164=function()
 guarded(true,function()
  local e,f=start(4,'formation')
  local t=e.incidents
  toLights(e,f)
  -- Voiture 3 heurtée par la voiture 4 (contact signalé par CSP), puis tête-à-queue.
  f.cars[3].collided=true; f.cars[3].collidedWith=4; F.tick(e,f,1/60); f.cars[3].collided=false; f.cars[3].collidedWith=-1
  spin(e,f,{3})
  assert(t.startAborts==1 and t.formation and t.messageKind=='startDelayed','start still aborted, one more lap')
  assert(not t.cars[3].abortMark and not t.cars[3].abortHold and t.abortMarks==0,'victim hit in its place: neither marked nor held')
  F.tick(e,f,1/60); assert(not e.commands[3].stopHold,'no hold')
 end)
end
-- Relecture 1.64 : faux départ d'une IA aux feux d'une grille de l'app : pris à l'extinction seulement ; un départ avorté
-- l'efface (comme celui du joueur).
tests.START_ABORT_AI_JUMP_FORGOTTEN_164=function()
 guarded(true,function()
  local function setup(e2) e2.profiles.C.sanJumpStart=true; e2.profiles.C.section_sanctions=true end
  local e,f=start(4,'formation',setup)
  toLights(e,f)
  e.grid.aiJump[2]=true; F.tick(e,f,1/60)
  assert(e.grid.aiJump[2]==true and e.sanctions.cars[2].count==0,'not taken during the lights of an app grid')
  spin(e,f,{3})
  F.tick(e,f,1/60)
  assert(not e.grid.aiJump[2] and e.sanctions.cars[2].count==0,'aborted start: jump forgotten, no penalty')
  local q,fq=start(4,'formation',setup)
  toLights(q,fq); q.grid.aiJump[2]=true
  toGo(q,fq); F.tick(q,fq,1/60)
  assert(q.grid.aiJump[2]=='taken' and q.sanctions.cars[2].count==1,'taken once the lights are out ('..q.sanctions.cars[2].count..')')
 end)
end
return tests
