-- Relecture 1.52, domaine B (moteur et règles de course) : arrêt obligatoire du joueur (stratégie des stands relue,
-- pénalité différée jusqu'au composé), fenêtre fermée, préréglage de la session (relecture, app coupée, bascule de
-- profil), ligne de session d'une course devenue mouillée. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local L=require('src/lang')
local Pitplan=require('src/pitplan')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Course F1 (fenêtre de 20 à 95 %, tour 50 / 100), joueur (1) en SS avec S et M disponibles, pénalités du joueur actives.
local function race(rules)
 local e,f=F.scene('C',3); C.preset('Course','C',e.profiles.C); C.applyRules(rules or 'F1',e.profiles)
 e.profiles.C.playerPenalties=true
 E.changed(e); f.sessionLaps=100; f.leaderLaps=50
 local a=f.cars[1]; a.compoundIndex=0; a.tyresKnown=true
 a.tyreNames={[0]='SS',[1]='S',[2]='M'}; a.dryList={0,1,2}; a.dryCompounds={[0]=true,[1]=true,[2]=true}
 F.tick(e,f,0.5)
 return e,f,a
end
-- Majeur 1 : après une image inactive (relance arrêtée, course pas encore lancée), la stratégie au même composé est de
-- nouveau signalée : la clé n'empêche plus la relecture.
tests.PITPLAN_INACTIVE_RESET_152B=function()
 local frame={player=1,cars={{valid=true,compoundIndex=0,tyresKnown=true,pit=false,tyreNames={[0]='SS',[1]='S',[2]='M'}}}}
 local spinner={name='TYRES',type='compound',min=0,max=2,value=0,values={0,1,2}}
 local function read() return {spinner},0 end
 local t=Pitplan.new()
 Pitplan.update(t,frame,10,true,true,true,read,nil); assert(t.state=='same','same compound planned')
 -- Relance arrêtée : image inactive.
 Pitplan.update(t,frame,11,true,true,false,read,nil); assert(t.state=='','inactive: no state')
 -- Course relancée, même stratégie : de nouveau l'avertissement.
 Pitplan.update(t,frame,11.1,true,true,true,read,nil)
 assert(t.state=='same' and t.noticeUntil>11.1,'active again: same compound warned again ('..tostring(t.state)..')')
end
-- Majeur 2 : fenêtre fermée pendant que le composé du joueur est attendu : pénalité seulement si le composé reste le même.
tests.STOP_PENDING_COMPOUND_152B=function()
 for _,same in ipairs({false,true}) do
  local e,f,a=race()
  a.pit=true; a.inPitBox=true; a.kmh=0; F.tick(e,f,0.5)
  assert(e.pits.cars[1].pendingCompound==0,'arrival in the window: compound awaited')
  -- Fenêtre fermée (96 %) pendant l'arrêt.
  f.leaderLaps=96; F.tick(e,f,0.5)
  assert(e.pits.state=='closed' and not e.penalties.stopPending,'window closed while the compound is awaited: no penalty yet')
  a.inPitBox=false; F.tick(e,f,0.5)
  if not same then a.compoundIndex=1 end
  F.tick(e,f,0.5); a.pit=false; a.kmh=100; F.tick(e,f,K.pitCompoundGrace+2)
  if same then
   assert(e.pits.cars[1].windowStops==0 and count(e,'arret obligatoire non effectue dans la fenetre')==1,'same compound: penalty')
  else
   assert(e.pits.cars[1].windowStops==1,'compound changed: stop counted')
   assert(not e.penalties.stopPending and count(e,'arret obligatoire non effectue')==0 and e.penalties.count==0,'compound changed: no penalty')
  end
 end
end
-- Mineur 3 : fenêtre fermée : aucune IA appelée pour l'arrêt obligatoire, un arrêt n'y compte pas.
tests.PIT_WINDOW_CLOSED_152B=function()
 local e,f=race('GT')
 f.leaderLaps=70; F.tick(e,f,0.5)
 assert(e.pits.state=='closed','GT window (42 to 58 %) closed at 70 %')
 assert(not e.pits.cars[2].wanted and not e.pits.cars[3].wanted,'no AI called once the window has closed')
 local b=f.cars[2]; b.pit=true; b.inPitBox=true; b.kmh=0; F.tick(e,f,0.5)
 assert(e.pits.cars[2].stops==1 and e.pits.cars[2].windowStops==0,'a stop after the window does not count')
 -- Fenêtre ouverte : compté comme avant.
 local e2,f2=race('GT'); f2.leaderLaps=45; F.tick(e2,f2,0.5)
 local c=f2.cars[2]; c.pit=true; c.inPitBox=true; c.kmh=0; F.tick(e2,f2,0.5)
 assert(e2.pits.state=='open' and e2.pits.cars[2].windowStops==1,'a stop in the open window counts')
end
-- Mineur 14 : course devenue mouillée (F1) : la ligne de session n'affiche plus « Arrêt 0/1 ».
tests.HUD_STOP_WAIVED_152B=function()
 local function stops(e) for k=1,e.hud.stripCount do if e.hud.strip[k].label==L.hudStops then return true end end return false end
 local e,f=race()
 F.tick(e,f,0.5); assert(stops(e),'dry F1 race: mandatory stop shown')
 e.pits.wetRace=true; F.tick(e,f,0.5)
 assert(e.pits.waived and not stops(e),'wet race: mandatory stop no longer shown')
end
-- Préréglage de la session : scène en profil automatique, réglage par session coché.
local function session(kind,track)
 local e,f=F.scene('J'); e.g.presetBySession=true; e.g.autoProfile=true; f.configType=kind; f.track=track or 'test'
 return e,f
end
-- Mineur 10 : réglage par session coché, relecture : l'ancienne règle preset_auto ne s'applique pas.
tests.PRESET_AUTO_REPLAY_152B=function()
 local e,f=session(2); e.g.presetsUsed=true; e.profiles.Q=C.defaults('Q'); f.replay=true
 E.step(e,f,1/60)
 assert(count(e,'preset_auto')==0 and count(e,'preset_session')==0,'replay with presetBySession: no preset at all')
 -- Contrôle : réglage par session décoché, hors relecture : ancienne règle, comme avant.
 local e2,f2=session(2); e2.g.presetBySession=false; e2.g.presetsUsed=true; e2.profiles.Q=C.defaults('Q')
 E.step(e2,f2,1/60); assert(count(e2,'preset_auto')==1,'presetBySession off: recommended preset as before')
end
-- Mineur 16 : bascule J -> Q -> J dans la même session : le préréglage de J n'est pas réappliqué (appels comptés : le
-- journal fusionne les lignes identiques rapprochées).
local function counted(fn)
 local calls=0; local original=C.applyBuiltin
 C.applyBuiltin=function(...) calls=calls+1; return original(...) end
 local ok,err=pcall(fn,function() return calls end)
 C.applyBuiltin=original
 if not ok then error(err,0) end
end
tests.SESSION_PRESET_TOGGLE_152B=function()
 counted(function(calls)
  local e,f=session(nil); f.configType=-1; f.type=1
  E.step(e,f,1/60); assert(e.profile=='J' and calls()==1,'track day first')
  f.configType=2; f.type=2; E.step(e,f,1/60); assert(e.profile=='Q' and calls()==2,'then qualifying')
  f.configType=-1; f.type=1; E.step(e,f,1/60)
  assert(e.profile=='J' and calls()==2,'back to the track day: nothing applied again ('..calls()..')')
  assert(e.presetSession=='test#0#JQ' and e.presetSessionDirty,'session key with the profiles served: '..e.presetSession)
  -- Ancienne clé (circuit#indice#profil) : Q déjà servi, J encore à servir.
  local e2,f2=session(2); e2.presetSession='test#0#Q'; e2.profiles.Q.levelPct=62; E.step(e2,f2,1/60)
  assert(e2.profiles.Q.levelPct==62 and calls()==2,'old key: Q already served')
  f2.configType=-1; f2.type=1; E.step(e2,f2,1/60); assert(calls()==3 and e2.presetSession=='test#0#QJ','old key: J served next')
  -- Nouvelle session : tout est de nouveau servi.
  f2.session=1; E.step(e2,f2,1/60); assert(calls()==4 and e2.presetSession=='test#1#J','new session')
  -- Clé bornée à 256 octets (nom de circuit très long).
  local e3,f3=session(2,string.rep('x',400)); E.step(e3,f3,1/60); assert(#e3.presetSession<=256 and calls()==5,'key bounded')
  f3.configType=-1; f3.type=1; E.step(e3,f3,1/60); assert(#e3.presetSession<=256 and calls()==6,'bounded key still parsed')
  f3.configType=2; f3.type=2; E.step(e3,f3,1/60); assert(calls()==6,'bounded key: once per profile')
 end)
end
-- Mineur 17 : app coupée : aucun préréglage de la session ; appliqué une fois l'app rallumée.
tests.SESSION_PRESET_DISABLED_152B=function()
 counted(function(calls)
  local e,f=session(2); e.g.enabled=false
  E.step(e,f,1/60); assert(calls()==0 and e.presetSession=='','app off: nothing')
  e.g.enabled=true; E.step(e,f,1/60); assert(calls()==1 and count(e,'preset_session: Qualifications')==1,'app on: applied')
 end)
end
return tests
