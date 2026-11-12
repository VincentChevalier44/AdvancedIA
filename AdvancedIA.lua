-- Reprise d'une mise à jour interrompue (Beta 1.35), avant tout autre module : une copie arrêtée au milieu (plantage,
-- coupure) aurait pu laisser des modules de deux versions ; elle est terminée ou défaite ici, de façon synchrone, avant
-- que les autres modules soient chargés. Seuls les deux modules de la mise à jour sont lus d'abord, chacun protégé.
-- Contrat figé (lu par toutes les versions à venir, voir src/update.lua) : Update.recover(port), Remote.new(onRelease),
-- port.ready, port.work, port.restart, port.log, port.bootOk, Update.recoverText.
local okUpdate,Update=pcall(require,'src/update')
local okRemote,Remote=pcall(require,'src/remote')
local onRelease
local port
-- Beta 1.52 : erreur de Remote.new gardée pour le journal (avant : seulement « port »).
local portError
if okUpdate and okRemote and type(Update)=='table' and type(Remote)=='table' then
 local ok,made=pcall(Remote.new,function() if onRelease then onRelease() end end)
 if ok and type(made)=='table' then port=made elseif not ok then portError=made end
end
if not port then
 -- Modules de la mise à jour illisibles : l'app se charge sans mise à jour (port inerte, état affiché « non vérifié »).
 local function none() end
 local unread=(okUpdate and okRemote and (portError~=nil and 'port: '..tostring(portError) or 'port') or tostring(not okUpdate and Update or Remote)):sub(1,160)
 port={ready=false,work='',restart=none,log=none,bootOk=none,unreadable=unread}
 if not okUpdate or type(Update)~='table' then
  -- Beta 1.52 : sans checkGap (copie de celui de src/update.lua) : l'interface ne le lit que port prêt, jamais ici.
  Update=setmetatable({new=function(version) return {phase='idle',installed=version,events={},serial=0,askedAt=0} end,
   view=function() return 'unchecked' end,take=function(_,out) return out end,page=''},{__index=function() return none end})
  -- Beta 1.36 : le remplaçant est aussi celui que rend require('src/update') (interface) ; un second require d'un module
  -- en échec lèverait « loop or previous error loading module » et arrêterait le chargement de l'app.
  local loaded=_G.package and _G.package.loaded
  if loaded then loaded['src/update']=Update end
 end
end
local recovered
do
 local ok,result=pcall(function() return port.ready and Update.recover(port) or nil end)
 -- Sans reprise, result vaut nil : jamais « ok and result or … », qui prendrait alors l'échec.
 if ok then recovered=result else recovered={outcome='failed',failed=tostring(result):sub(1,120),file=port.work} end
end
-- Reprise dite tout de suite au journal de CSP : elle reste lisible même si un module ne se charge pas ensuite.
if recovered and port.ready then
 local okText,level,text=pcall(Update.recoverText,recovered)
 if okText and text then pcall(port.log,level..' '..text) end
end
-- Fichiers de l'app copiés à l'instant par la reprise : le code déjà chargé est celui d'une autre version. Aucun autre
-- module n'est lu ; l'app redémarre à la première image (compte rendu lu au lancement suivant).
if recovered and recovered.restart then
 local asked=false
 local function restartOnly() if not asked then asked=true; pcall(port.restart) end end
 function script.update() restartOnly() end
 function script.HUMANAI__UPDATE() restartOnly() end
 function script.HUMANAI__MAIN() end
 function script.HUMANAI__MENU() end
 function script.HUMANAI__HUD() end
 return
end
-- Beta 1.49 : ancienne version ACAdvancedIA encore installée (son manifeste) : elle pilote les IA ; cette app reste
-- inerte et affiche seulement la consigne (src/oldinstall.lua), avant toute lecture ou écriture (AI flood, journal).
local oldTidied=false
do
 local okOld,Old=pcall(require,'src/oldinstall')
 local okApplier,Applier0=pcall(require,'src/applier')
 local okConfig,Config0=pcall(require,'src/config')
 if okOld and okApplier and Applier0.companionInstalled(Old.folder) then
  Old.run(script,Applier0,okConfig and Config0.release or '')
  return
 end
 -- Beta 1.52 : ancienne version désinstallée : copie laissée par sa mise à jour (cfg/extension/state/ACAdvancedIA-update)
 -- effacée, une fois ; ligne au journal de session plus bas.
 if okOld and okApplier and type(Applier0.oldWorkLeftover)=='function' then local okTidy,done=pcall(Applier0.oldWorkLeftover,Old.folder,Old.oldWork); oldTidied=okTidy and done==true end
end
local Snapshot=require('src/snapshot')
local Applier=require('src/applier')
local Engine=require('src/engine')
local Pacemap=require('src/pacemap')
local Panel=require('src/panel')
local Director=require('src/director')
local Caps=require('src/caps')
local Calibration=require('src/calibration')
local Zones=require('src/zones')
local UI=require('src/ui')
local U=require('src/util')
local Config=require('src/config')
local Lang=require('src/lang')
local Pits=require('src/pits')
local Penalties=require('src/penalties')
local Strategy=require('src/strategy')
local Sanctions=require('src/sanctions')
local Journal=require('src/journal')
local Locale=require('src/locale')
local Lights=require('src/lights')
local Cspgui=require('src/cspgui')
local Bridge=require('src/bridge')
local K=Config.K
-- Cache des traces du compilateur JIT agrandi (machine virtuelle de l'app) : avec les 1 000 traces et 512 Ko de code
-- machine par défaut, le moteur vide et recompile tout son code toutes les une à deux minutes (pics d'image). Sans
-- effet sur les décisions ; ignoré si la bibliothèque jit n'est pas exposée.
local jitlib=rawget(_G,'jit')
local jitTuned=type(jitlib)=='table' and type(jitlib.opt)=='table' and type(jitlib.opt.start)=='function' and pcall(jitlib.opt.start,'maxtrace=8000','maxmcode=16384')==true
-- Beta 1.60 (lot 5, coût par image) : le pas du directeur est une très longue fonction ; avec les limites par défaut
-- (100 traces latérales par trace, 15 déroulages de boucle, 4 000 instructions enregistrées), le compilateur abandonne
-- la plupart de ses traces et met en liste noire jusqu'aux petites fonctions utilitaires (U.clamp : 1 163 abandons sur
-- 2 500 images au banc), le code restant interprété. Limites relevées, dans un appel à part : s'il échoue, le cache
-- agrandi ci-dessus reste acquis. Sans effet sur les décisions (journaux de référence identiques).
local jitWide=jitTuned and pcall(jitlib.opt.start,'maxside=400','loopunroll=30','maxrecord=20000','maxirconst=2000','maxsnap=2000')==true
local previous=rawget(_G,'HUMANAI')
if previous and type(previous.release)=='function' then pcall(previous.release) end
local host=Applier.new()
local globals,profiles=Applier.openStore(host)
-- Langue de l'interface choisie avant de préparer les textes de la fenêtre de réglages.
Locale.set(globals.language)
local engine=Engine.new(globals,profiles)
-- Voitures pilotées en un seul appel protégé seulement avec le cache agrandi (avec le cache par défaut, le code compilé
-- plus volumineux le saturerait plus vite).
engine.batchCars=jitTuned
local frame=Snapshot.new()
local calibration=Calibration.new()
local initialized=false
local released=false
local loadedTrack=''
-- Finition 1.61 (relecture) : fichier par circuit refusé à la lecture : mis de côté (jamais écrasé), une ligne.
local function refusedAside(folder,key,what)
 local name=Applier.trackFileSetAside(folder,key)
 U.log(engine.log,engine.time,'WARN',name and string.format('%s: fichier refuse mis de cote (%s)',what,name) or string.format('%s: fichier refuse non deplace',what),-1)
end
-- Drapeau natif d'AC vu en dernier (Beta 1.34) : chaque changement est noté au journal (panneaux lumineux en jeu).
local nativeFlag=nil
local nativeFlagNames={[0]='aucun',[1]='depart',[2]='jaune',[3]='glissant',[5]='noir',[8]='penalite',[12]='bleu',[13]='damier',[14]='dernier tour'}
local lastCheckpoint=0
local shownMessage=0
-- Messages à l'écran : drapeaux, neutralisations, météo ; un seul affichage par événement.
-- Beta 1.50 : annonces de la voiture de sécurité (en piste, file formée) et de la reprise du joueur (place, place à
-- reprendre) : seulement pour le pont des apps compagnes (texte prêt, nom du pilote), jamais en message en haut de
-- l'écran : l'overlay les montre déjà.
local silentKinds={scOut=true,scLeading=true,restartPlace=true,restartRetake=true,rollStart=true}
local function carName(value)
 local k=math.floor(tonumber(value) or -1)+1
 return frame and k>=1 and k<=frame.count and frame.cars[k].name or ''
end
local function announce()
 local t=engine.incidents
 if t.messageId==shownMessage then return end
 shownMessage=t.messageId
 local m=Lang.messages[t.messageKind]
 if m and silentKinds[t.messageKind] then
  local kind=t.messageKind; local text
  if kind=='scOut' then local who=carName(t.messageValue); text=who~='' and string.format(m[2],who) or Lang.messages.scOutAlone[2]
  elseif kind=='scLeading' or kind=='restartRetake' then text=string.format(m[2],carName(t.messageValue))
  elseif kind=='rollStart' then local who=carName(t.messageExtra); text=who~='' and string.format(m[2],t.messageValue,who) or string.format(Lang.messages.rollStartLead[2],t.messageValue)
  else local who=carName(t.messageExtra); text=who~='' and string.format(m[2],t.messageValue,who) or string.format(Lang.messages.restartPlaceSc[2],t.messageValue) end
  engine.ownTitle=m[1]; engine.ownText=text; engine.ownAi=false; return
 end
 -- Beta 1.49 : avis de l'arrêt F1 (rappel, stratégie, arrêt validé ou non compté) : seulement pour le pont des apps
 -- compagnes (texte du panneau), jamais en message en haut de l'écran ni en double sur l'overlay.
 local quiet=m and Panel.pitAnnounce(t,t.messageKind)
 if quiet then engine.ownTitle=m[1]; engine.ownText=quiet; engine.ownAi=false; return end
 if m then
  local text=t.messageText~='' and string.format(m[2],t.messageText) or string.format(m[2],t.messageValue,t.messageExtra)
  -- Beta 1.41 : annonce de l'app, revenue par ac.onMessage : jamais prise pour un bandeau de pénalité d'AC.
  engine.ownTitle=m[1]; engine.ownText=text
  -- Beta 1.43 : annonce de sanction d'une IA (panneau dédié de l'overlay, jamais reprise en double).
  engine.ownAi=t.messageKind=='aiSanction' or t.messageKind=='aiBlackFlag'
  Applier.message(m[1],text)
 end
end
local function dirty()
 Applier.dirty(host,engine.time)
 if host.menuVisible then Applier.save(host,globals,profiles,engine.time,frame.replay,true) end
end
-- Messages d'AC (Beta 1.25) : écoute et masquage optionnel, annulés au déchargement.
local messageListener,messageBlock=nil,nil
local messages
local panel=UI.new(engine,host,calibration,dirty)
messageListener=Applier.listenMessages(function(title,description,kind,time) if not released then pcall(Engine.message,engine,title,description,kind,time) end end)
host.note=engine.note
-- Options de CSP tenues par l'app (Beta 1.40, src/cspgui.lua) : messages système et drapeaux d'origine d'AC masqués
-- tant que l'app est active (Beta 1.47 : laissées cochées à la fermeture, voir Cspgui.want). Fichiers lus et écrits dans update()
-- seulement (jamais pendant le dessin), au premier passage et à chaque changement de ce qui est voulu.
local cspPort=Applier.cspPort()
local csp=Cspgui.new()
Cspgui.start(csp,cspPort)
host.cspgui=csp; host.cspFrozen=function(key) return Cspgui.frozen(csp,key) end
local cspClock=0
local cspWant,cspEvents={},{}
local function cspLog()
 Cspgui.take(csp,cspEvents)
 for i=1,#cspEvents do local ev=cspEvents[i]; U.log(engine.log,engine.time or 0,ev[1],ev[2],-1); cspEvents[i]=nil end
end
-- CSP relit gui.ini (option changée en jeu, ou écrite par l'app) : état appliqué et drapeaux d'AC masqués relus.
local cspWatch=Applier.watchGui(function()
 if released then return end
 pcall(Cspgui.reloaded,csp,cspPort,cspClock); Applier.readFlagsHidden(host); cspLog()
end)
cspLog()
-- Démarrage surveillé d'une version tout juste installée (boot.txt, src/update.lua) : rien n'est écrit avant sa
-- confirmation (une relance de l'app par CSP à la relecture de gui.ini compterait comme un démarrage manqué).
local bootWatched=false
if port.ready and type(port.boot)=='function' then local okBoot,version=pcall(port.boot); bootWatched=okBoot and version~=nil end
local function cspStep(dt)
 if U.finite(dt) and dt>0 then cspClock=cspClock+math.min(dt,1) end
 -- Beta 1.47 : décision dans src/cspgui.lua (Cspgui.want) ; nil pendant la panique : rien ne change.
 Cspgui.step(csp,cspPort,Cspgui.want(globals,engine.p,engine.panic,cspWant),cspClock)
 -- Beta 1.59 (relecture) : drapeaux d'AC encore masqués par CSP (gui.ini pas relu, plafond, lecture seule).
 engine.cspHidingFlags=Cspgui.applied(csp,'HIDE_RACE_FLAGS')
 cspLog()
end
-- AI flood de CSP (Beta 1.26) : état chargé par CSP au lancement ; le moteur écrit ensuite le réglage voulu.
do local user,system,writable=Applier.floodRead(); Engine.floodInit(engine,user,system,writable); engine.floodWrite=Applier.floodWrite end
-- Beta 1.49 : stratégie des stands du joueur (menu Quick Pitstop), lecture seule (src/pitplan.lua).
engine.pitSpinners=Applier.pitSpinners
if Applier.floodLeftover() then U.log(engine.log,0,'INFO','nettoyage: new_behaviour.ini.bak efface (reste d une version d avant la Beta 1.38)',-1) end
if oldTidied then U.log(engine.log,0,'INFO','nettoyage: cfg/extension/state/ACAdvancedIA-update efface (copie laissee par la mise a jour de l ancienne version ACAdvancedIA, desinstallee)',-1) end
host.oldSettings=Applier.oldSettings()
if host.oldSettings then U.log(engine.log,0,'WARN','reglages d ACAdvancedIA non repris (state/lua/app/ACAdvancedIA.ini present, AdvancedIA.ini absent) : voir A verifier',-1) end
if host.storageErrors>0 then U.log(engine.log,0,'WARN','invalid_storage:'..host.storageErrors,-1) end
U.log(engine.log,0,'INFO',jitTuned and 'compilateur JIT: cache agrandi (8000 traces, 16 Mo), voitures pilotees en un seul appel protege' or 'compilateur JIT: options indisponibles, voitures pilotees une par une',-1)
if jitTuned then U.log(engine.log,0,'INFO',jitWide and 'compilateur JIT: limites de trace relevees' or 'compilateur JIT: limites de trace par defaut (options refusees)',-1) end
if host.upgraded and #host.upgraded>0 then U.log(engine.log,0,'INFO','profils mis a jour vers les prereglages '..Config.release..': '..table.concat(host.upgraded,', '),-1) end
if host.signsRestored then U.log(engine.log,0,'INFO','sens lateral retabli: -1 / -1 (convention AC, mesure sur cette installation jusqu a la Beta 1.8 ; la mesure le confirmera)',-1) end
if host.firstInstall then U.log(engine.log,0,'INFO','premiere installation: prereglages recommandes et regles de base (essais, qualifications, course)',-1) end
local journal=Journal.new()
-- Journal de session sur disque : lignes nouvelles toutes les deux secondes, résumé chaque minute. Les capacités de CSP
-- perdues sont dites par l'applicateur (Applier.reportCaps), une seule fois.
-- Affinage 1.61 (coût en jeu, Spa 40 IA : 2,5 à 3 ms en moyenne, pointe de 202 ms) : coût de chaque poste de l'image
-- (secondes), cumulé sur la minute du résumé, et celui de l'image en cours (ligne « image lente »). Postes : 1 lecture
-- (Snapshot.read), 2 moteur (Engine.step), 3 fichiers (mémoire, rapport, journal), 4 commandes (le reste de update),
-- 5 mise à jour, 6 options CSP, 7 pont, 8 interface (fenêtres, hors du coût par image). Aucune table créée par image.
local prof={sum={0,0,0,0,0,0,0,0,0},cur={0,0,0,0,0,0,0,0},frames=0,at=nil,slowLogs=0,slowAt=-math.huge}
-- Affinage 1.62 (mesure fine) : sous-postes de la lecture mesurés par Snapshot avec la même horloge ; interface séparée
-- en fenêtre (8) et overlay (9).
Snapshot.clock=function() return Applier.clock(host) end
local function mark(i)
 local at=prof.at; if not at then return end
 local now=Applier.clock(host); if not now then prof.at=nil; return end
 prof.cur[i]=prof.cur[i]+(now-at); prof.at=now
end
local function profLine()
 local s,n=prof.sum,math.max(1,prof.frames)
 local line=string.format('cout par poste (moyenne ms par image): lecture %.3f, moteur %.3f, fichiers %.3f, commandes %.3f, mise a jour %.3f, options CSP %.3f, pont %.3f, interface %.3f',
  s[1]*1000/n,s[2]*1000/n,s[3]*1000/n,s[4]*1000/n,s[5]*1000/n,s[6]*1000/n,s[7]*1000/n,(s[8]+s[9])*1000/n)
 local r=Snapshot.cost
 local detail=string.format('cout detaille (moyenne ms par image): lecture session %.3f, voitures %.3f, metadonnees %.3f, gommes %.3f, interface fenetre %.3f, overlay %.3f',
  r[1]*1000/n,r[2]*1000/n,r[3]*1000/n,r[4]*1000/n,s[8]*1000/n,s[9]*1000/n)
 for i=1,9 do s[i]=0 end; for i=1,4 do r[i]=0 end; prof.frames=0
 return line,detail
end
local function writeJournal(force)
 if not globals.journal then return end
 if not host.journalTried then
  host.journalTried=true
  if Applier.journalOpen(host) then Applier.journalWrite(host,'=== AdvancedIA '..Config.release..' : lancement '..Applier.clockText()..' ===\n') end
 end
 if not host.journalPath or not force and engine.time<journal.flushAt then return end
 journal.flushAt=engine.time+K.journalPeriod
 -- Beta 1.47 : à la fermeture, résumé de la minute entamée (avant : perdu, le dernier contact d'une session n'y était pas).
 if engine.time>=journal.summaryAt or force and released and engine.time>journal.summaryAt-K.journalSummary+1 then journal.summaryAt=engine.time+K.journalSummary; U.log(engine.log,engine.time,'INFO',Journal.summary(engine),-1); if prof.frames>0 then local line,detail=profLine(); U.log(engine.log,engine.time,'INFO',line,-1); U.log(engine.log,engine.time,'INFO',detail,-1) end end
 Journal.collect(journal,engine.log,Applier.clockText())
 Applier.journalWrite(host,Journal.take(journal))
end
-- Beta 1.56 : rapport de course (option) : lignes préparées par les sanctions, écrites par l'applicateur.
local function writeReport(lines)
 if not lines then return end
 local ok,info=Applier.reportWrite(host,lines)
 if ok then U.log(engine.log,engine.time,'INFO',string.format('rapport de course ecrit: %s (%d voitures)',info,math.max(0,#lines-2)),-1)
 else U.log(engine.log,engine.time,'WARN',string.format('rapport de course: ecriture impossible (%s)',info),-1) end
end
local function cancelProbe() if host.allowed then Caps.cancelProbe(host.caps,frame) end end
local function syncRestored()
 for i=1,frame.count do
  local state=host.cars[i]
  if state.justRestored then
   Director.reset(engine.states[i],engine.time,false,true); engine.commands[i].active=false; engine.commands[i].offset=0
   state.justRestored=false
  end
 end
end
-- Une voiture au moins garde une commande de l'app à rendre.
local function anyOwned()
 for i=1,frame.count do if host.cars[i].owned then return true end end
 return false
end
-- Chaque étape de la restitution est protégée : une erreur dans l'une n'empêche jamais les suivantes.
local function step(fn,...)
 local ok,err=pcall(fn,...)
 if not ok then host.errors=host.errors+1; U.log(engine.log,engine.time,'ERROR','stop:'..tostring(err):sub(1,200),-1) end
end
-- keepParked : fin de session, voitures garées (voiture de sécurité, réserves, IA disqualifiées) laissées à leur stand
-- jusqu'à la session suivante ; jamais au déchargement.
local function stop(final,keepParked)
 if host.allowed then step(cancelProbe); step(Calibration.cancel,calibration,frame,host.caps,globals) end
 step(Applier.restore,host,frame,false,engine.time,final,keepParked); step(syncRestored); step(Applier.checkpoint,host,frame)
end
-- Arrêts et sanctions de la course : sauvegardés une seconde au plus après un changement, et au déchargement.
local lastRaceSave=0
local function saveRace(force)
 if not force and engine.time-lastRaceSave<K.saveDelay then return end
 lastRaceSave=engine.time
 if engine.pits.dirty then engine.pits.dirty=false; Applier.storeText('humanai:pits',Pits.serialize(engine.pits,frame.session)) end
 if engine.penalties.dirty then engine.penalties.dirty=false; Applier.storeText('humanai:penalties',Penalties.serialize(engine.penalties,frame,frame.session)) end
 -- Beta 1.42 : stratégie et sanctions des IA, gardées pour un rechargement de l'app en pleine course.
 if engine.strategy.dirty then engine.strategy.dirty=false; Applier.storeText('humanai:strategy',Strategy.serialize(engine.strategy,frame.session)) end
 if engine.sanctions.dirty then engine.sanctions.dirty=false; Applier.storeText('humanai:sanctions',Sanctions.serialize(engine.sanctions,frame.session)) end
end
-- Pont vers les apps compagnes (Beta 1.46, src/bridge.lua) : ouvert plus bas seulement si l'app lectrice est installée ;
-- fermé au déchargement (les lecteurs passent à « absent » aussitôt).
local bridge,bridgePort=nil,nil
local companion='SpotterEnginer'
-- Beta 1.52 : sa mise à jour, signalée à l'accueil (clé publiée par lui, fenêtre de réglages ID=main de son manifeste).
local companionKey,companionWindow=companion..'.update','IMGUI_LUA_'..companion..'_main'
local companionPresent,companionAt=false,-math.huge
-- Beta 1.59 : plan d'arrêt du joueur publié par SpotterEnginer (lecture seule), relu toutes les K.sePlanPeriod s.
local sePlanAt=-math.huge
local strategyPublished=''
local sidePublished={} -- Beta 1.61 : dernier texte écrit de chaque clé annexe (engine.sideText)
host.openCompanion=function() return Applier.openCompanion(companionWindow) end
local function release()
 if released then return end
 if bridgePort then pcall(Bridge.close,bridge,bridgePort.hello); bridgePort=nil end
 -- Aucune image ne suivra : restitution complète, y compris en pause ou en replay.
 -- Beta 1.52 : instantané protégé (released est déjà posé : une erreur ici empêchait toute la restitution).
 released=true; pcall(Snapshot.read,frame,K.dtMax,engine.time); pcall(saveRace,true); Applier.access(host); stop(true); Applier.unregister(host)
 pcall(Applier.reportCaps,host)
 -- Overlay en jeu (Beta 1.25) : case de session d'AC et messages d'origine rendus, écoute des messages close.
 pcall(UI.restoreNative,panel); pcall(messages,false); Applier.dispose(messageListener); messageListener=nil
 -- Options de CSP (Beta 1.47) : laissées cochées, valeurs d'origine gardées (src/cspgui.lua).
 -- Retour arrière depuis l'app vers une version qui ne connaît pas ces options (Beta 1.52 : d'avant la Beta 1.40, ou
 -- version illisible ; avant : à chaque retour arrière) : rendues.
 local up=host.updater; local back=up~=nil and up.after=='rollback'
 local force=back and (not Update.version(up.afterVersion) or Update.newer('Beta 1.40',up.afterVersion))
 pcall(Cspgui.release,csp,cspPort,cspClock,force); Applier.dispose(cspWatch); cspWatch=nil; cspLog()
 -- Beta 1.56 : course commencée sans rapport (option) : rapport partiel avant la fin du journal.
 pcall(function() writeReport(engine.reportLines or Sanctions.flushReport(engine.sanctions,engine,frame)); engine.reportLines=nil end)
 pcall(writeJournal,true); Applier.journalWrite(host,'=== fin : '..Applier.clockText()..' ===\n')
end
-- Mise à jour depuis GitHub (Beta 1.33) : vérification une fois par lancement, installation d'un clic à l'arrêt. Avant
-- le redémarrage de l'app : événements versés au journal, puis restitution complète (commandes des IA rendues à AC).
-- Sans les fonctions de CSP (bancs de mesure, tests), le port est inerte et rien ne change.
local updater=Update.new(Config.release)
local updateEvents={}
local function updateLog()
 Update.take(updater,updateEvents)
 for i=1,#updateEvents do local ev=updateEvents[i]; U.log(engine.log,engine.time,ev[1],ev[2],-1); updateEvents[i]=nil end
end
onRelease=function() updateLog(); release() end
host.updater=updater; host.updatePort=port; host.updateStopped=false; host.updateNow=0
local updateClock,updateAsked,updateNoticed=0,false,false
-- Horloge de la mise à jour : temps réel (le temps du moteur est figé en pause et dans les menus, là où la fenêtre sert).
local updateNow,updateCounter=0,nil
-- Compte rendu de la reprise faite au chargement et de la dernière opération ; version précédente proposée.
if port.ready then Update.start(updater,port,recovered) end
updateLog()
-- Messages d'AC (Beta 1.25) : repris sur l'overlay ; leur affichage d'origine est masqué (Beta 1.26 : par défaut). Un
-- message témoin, envoyé dès le premier masquage, doit encore arriver à l'écoute : sinon (masquage qui couperait
-- aussi l'overlay), le masquage est levé jusqu'au prochain lancement et le journal le dit. Beta 1.40 : le témoin
-- vérifie aussi, une fois, les messages masqués par l'option de CSP (hide : option appliquée par CSP) ; s'ils
-- n'arrivent plus, l'option est rendue et ce choix gardé (cspMessagesLost, levé en recochant l'interrupteur).
local probe,unblockable=nil,false
local probeHide,hideProbed=false,false
local function startProbe(hide) engine.probeSeen=false; probe=Config.K.probeFrames; probeHide=hide; Applier.probeMessage(Config.K.messageProbe) end
messages=function(block,hide)
 if unblockable then block=false end
 if block and not messageBlock then
  messageBlock=Applier.blockMessages() or false
  if messageBlock and probe==nil then startProbe(hide==true) end
 elseif not block and messageBlock~=nil then Applier.dispose(messageBlock); messageBlock=nil end
 if hide and not hideProbed and type(probe)~='number' then startProbe(true) end
 if probe then
  if engine.probeSeen then
   probe=false; if probeHide then hideProbed=true end
   U.log(engine.log,engine.time or 0,'INFO','messages d AC: affichage d origine masque, messages repris sur l overlay'..(probeHide and ' (option de CSP comprise)' or ''),-1)
  else
   probe=probe-1
   if probe<=0 then
    probe=false
    if messageBlock then
     unblockable=true; Applier.dispose(messageBlock); messageBlock=nil
     U.log(engine.log,engine.time or 0,'WARN','messages d AC: les messages masques n arrivent plus a l overlay, masquage leve jusqu au prochain lancement',-1)
    end
    if probeHide then
     hideProbed=true; globals.cspMessagesLost=true; dirty()
     U.log(engine.log,engine.time or 0,'WARN',csp.owned.HIDE_SYSTEM_MESSAGES~=nil and 'messages d AC: masques par l option de CSP, ils n arrivent plus a l overlay: option rendue'
      or 'messages d AC: masques par l option de CSP, ils n arrivent plus a l overlay: decochez Hide system messages (CSP)',-1)
    end
   end
  end
 end
end
local raceKeys={'humanai:pits','humanai:penalties','humanai:strategy','humanai:sanctions'}
local function session()
 if released then return end
 Engine.reset(engine,engine.time,true); engine.session=-1; calibration.attempted=false; Pits.forget(engine.pits); Strategy.forget(engine.strategy); engine.penalties.pending=nil
 -- Beta 1.42 : point de reprise des sanctions oublié aussi (redémarrage au même indice) ; celui de la stratégie l'est par Strategy.forget.
 if engine.sanctions then engine.sanctions.pending=nil end
 -- Beta 1.52 : points de reprise gardés dans ac.store vidés aussi (même indice de session : un rechargement de l'app
 -- dans la session recommencée reprenait sinon les arrêts, pénalités, stratégie et sanctions d'avant) ; rien de la
 -- session d'avant n'est écrit ensuite (changements en attente oubliés). Vider plutôt que réécrire : un texte vide est
 -- refusé par chaque relecture, sans dépendre de l'état du moteur avant sa remise à zéro.
 engine.pits.dirty=false; engine.penalties.dirty=false; engine.strategy.dirty=false; if engine.sanctions then engine.sanctions.dirty=false end
 for _,key in ipairs(raceKeys) do Applier.storeText(key,'') end
 host.session=nil -- Un redémarrage garde le même indice : les écritures suivies sont resynchronisées.
end
-- Beta 1.32 : panneaux lumineux du circuit cherchés dans sa configuration (et drapeaux d'AC masqués relus), une fois
-- par circuit.
local function lightsCheck()
 if host.trackLightsFor==frame.track then return end
 local lights=Applier.trackLights(host,frame.track)
 -- Beta 1.34 : places de grille du circuit (départ arrêté), lues en même temps.
 engine.grid.nodes=Applier.gridNodes(host,frame.track)
 U.log(engine.log,engine.time,'INFO',lights==true and 'panneaux lumineux du circuit: detectes ('..host.trackLightsSource..')' or lights==false and 'panneaux lumineux du circuit: non detectes'..(host.trackLightsDetail or '') or 'panneaux lumineux du circuit: configuration illisible',-1)
end
local capsReported,menuClock=0,0
local function update(dt)
 if released then return end
 local valid=U.finite(dt) and dt>0 and dt<=K.dtMax
 -- Lecture légère (rien à piloter ni à rendre). Les cinq profils restent testés : un profil coché autre que celui en
 -- cours garde les voitures lues pour l'interface (nombre d'IA, gommes du profil affiché). Beta 1.52 : voitures de la
 -- session seulement, et aussi DRS coupé, drapeau noir du joueur ou drapeau de l'app resté affiché : à rendre, lecture
 -- complète.
 local quiet=not globals.enabled
 if not quiet then
  quiet=true; for _,p in pairs(profiles) do if Config.any(p) then quiet=false; break end end
 end
 if quiet then
  if calibration.index>0 or host.caps.probeIndex>0 or host.flagOverride or host.drsAny or host.drsRelease or host.blackFlag or host.flagLeftover then quiet=false end
  if quiet and anyOwned() then quiet=false end
 end
 -- Affinage 1.62 (coût) : sens latéral des voitures lu seulement pendant sa recherche ou sa mesure (src/calibration.lua).
 Snapshot.sideWanted=(globals.offsetSign or 0)==0 or (globals.sideSign or 0)==0 or calibration.index>0
 local read=Snapshot.read(frame,valid and dt or K.dtMax,engine.time,quiet)
 mark(1)
 -- Drapeau du joueur imposé par l'app elle-même : le panneau ne le prend pas pour un drapeau natif.
 -- Beta 1.47 : aussi sa dernière valeur restée affichée après une restitution (Applier.flagMine).
 frame.flagOwned=Applier.flagMine(host,frame)
 if read and not frame.flagOwned and frame.flag~=nativeFlag then
  if nativeFlag~=nil or frame.flag~=K.flagNone then U.log(engine.log,engine.time,'INFO',string.format('drapeau d AC: %d (%s)',frame.flag,nativeFlagNames[frame.flag] or 'autre'),-1) end
  nativeFlag=frame.flag
 end
 -- Beta 1.52 : horloge des images pour la fenêtre ouverte hors des menus (le temps du moteur est figé en replay).
 if U.finite(dt) and dt>0 then menuClock=menuClock+math.min(dt,1) end
 if read then Applier.menu(host,frame.menu,menuClock) else Applier.menu(host,Snapshot.menu(),menuClock) end
 -- Beta 1.52 : état de la mise à jour de SpotterEnginer (publié par lui), relu toutes les K.companionUpdatePeriod s.
 if companionPresent and menuClock>=companionAt then companionAt=menuClock+K.companionUpdatePeriod; host.companionUpdate=Applier.companionUpdate(companionKey) end
 if companionPresent and menuClock>=sePlanAt then
  sePlanAt=menuClock+K.sePlanPeriod
  local plan=engine.sePlan; if not plan then plan={}; engine.sePlan=plan end
  plan.raw=Applier.loadText(K.sePlanKey)
  -- Beta 1.60 (tranche D) : conseil de stratégie de SpotterEnginer (lecture seule, affichage et journal) ; temps perdu
  -- aux stands appris publié pour lui (réglage strategySmart ; écrit seulement quand le texte change).
  local advice=engine.seStrategy; if not advice then advice={}; engine.seStrategy=advice end
  advice.raw=Applier.loadText(K.seStrategyKey)
  local text=engine.pitloss.text
  if text~='' and text~=strategyPublished then strategyPublished=text; Applier.storeText(K.strategyPubKey,text) end
  -- Beta 1.61 : autres clés annexes pour SpotterEnginer (trafic, météo), mêmes règles : écrites quand le texte change.
  -- Finition 1.61 (relecture, contrat SpotterEnginer) : réglage coupé (ou plus de texte) après une publication : un
  -- dernier enregistrement « rien » est écrit une fois, horodaté, au lieu de laisser la dernière valeur figée.
  if not (engine.run and engine.run.classNuance) then engine.sideText['AdvancedIA.traffic']=nil end
  for key,side in pairs(engine.sideText) do if side~='' and side~=sidePublished[key] then sidePublished[key]=side; Applier.storeText(key,side) end end
  for key,was in pairs(sidePublished) do
   if was and (engine.sideText[key]==nil or engine.sideText[key]=='') then
    local stamp=math.floor(math.max(0,engine.time))
    local final=key=='AdvancedIA.traffic' and 'v=1;blue=none;stage=none;car=-1;gap=0;closing=0;count=0;stamp='..stamp
     or 'v=1;wet=0.00;rain=0.00;water=0.00;trend=off;eta=-1;next=none;forecast=unknown;forecastIn=-1;aiDry=0;aiRain=0;stamp='..stamp
    sidePublished[key]=false; Applier.storeText(key,final)
   end
  end
 end
 if not initialized then
  -- Session courante connue avant la récupération : un rechargement n'est pas un changement de session.
  initialized=true; host.session=frame.session; Applier.recover(host,frame)
  Pits.restore(engine.pits,Applier.loadText('humanai:pits'),frame.session)
  Penalties.restore(engine.penalties,Applier.loadText('humanai:penalties'),frame.session)
  Strategy.restore(engine.strategy,Applier.loadText('humanai:strategy'),frame.session)
  Sanctions.restore(engine.sanctions,Applier.loadText('humanai:sanctions'),frame.session)
  -- Beta 1.51 : session dont le préréglage intégré est déjà appliqué (rechargement de l'app dans le même lancement).
  do local key=Applier.loadText('humanai:presetsession'); if type(key)=='string' and #key<=256 and not key:find('%c') then engine.presetSession=key end end
  Applier.register(host,function() local ok=pcall(release); if not ok then host.errors=host.errors+1 end end,
   function() local ok=pcall(session); if not ok then host.errors=host.errors+1 end end)
 end
 Applier.baselines(host,frame)
 -- Départ arrêté (Beta 1.34) : retenue, plafond d'allure et décalage disponibles.
 engine.gridCaps=host.caps.stop.available and host.caps.speed.available and host.caps.offset.available
 -- Beta 1.41 : retenue à la sortie des stands seulement si l'arrêt natif répond.
 engine.stopCap=host.caps.stop.available==true
 engine.pitCap=host.caps.pit.available==true
 -- Beta 1.56 : pénalité native du joueur écrite (limites de piste, option coupure des gaz), capacité disponible.
 engine.penaltyWritten=host.penaltyWritten or 0; engine.penaltyCap=host.caps.penalty.available==true
 local ready=Engine.step(engine,frame,dt)
 mark(2)
 -- Beta 1.61 : la prévision météo de CSP n'est lue que météo en direct en service (relecture).
 Snapshot.wxWanted=engine.run~=nil and engine.run.weatherLive==true
 -- Beta 1.61 (tranche B, réglage trackMemory) : fichier d'allure du circuit lu et écrit ici pour src/pacemap.lua (le
 -- moteur ne touche à aucun fichier) ; rien n'est demandé tant que le réglage est coupé. Durée de l'écriture notée.
 local memory=engine.pacemap
 -- Fusion 1.61 : le bouton « Oublier ce circuit » (zones, tranche A) oublie aussi l'allure gardée (tranche B).
 if engine.trackForgetAsk then engine.trackForgetAsk=nil; memory.forgetWanted=engine.runtimeG.trackMemory==true end
 if memory.ioRead then
  local key=memory.ioRead; memory.ioRead=nil; local text,place=Applier.trackFileRead(K.paceFolder,key,K.paceMapMaxBytes)
  -- Finition 1.61 (relecture) : fichier présent mais refusé : mis de côté avant toute écriture.
  if Pacemap.loaded(memory,engine,text,place)==false and (text~=nil or place=='big') then refusedAside(K.paceFolder,key,'memoire du circuit') end
 end
 if memory.ioWrite then
  local text,key=memory.ioWrite,memory.ioKey; memory.ioWrite=nil; memory.ioKey=nil
  local place,ms=Applier.trackFileWrite(K.paceFolder,key,text)
  Pacemap.written(memory,engine,place,ms,#text)
 end
 if engine.reportLines then local lines=engine.reportLines; engine.reportLines=nil; writeReport(lines) end
 if engine.presetSessionDirty then engine.presetSessionDirty=false; Applier.storeText('humanai:presetsession',engine.presetSession) end
 -- Beta 1.52 : seulement après un nouvel échec d'une capacité (compteur de Caps.call) ; avant : à chaque image.
 if host.caps.failureCount~=capsReported then capsReported=host.caps.failureCount; Applier.reportCaps(host) end
 if engine.settingsChanged then engine.settingsChanged=false; dirty() end
 writeJournal(false)
 mark(3)
 if engine.rebaseDelta>0 then
  Applier.rebase(host,engine.rebaseDelta); calibration.startAt=calibration.startAt-engine.rebaseDelta
  -- Beta 1.52 : nouvel essai de la mesure du sens latéral et information de mise à jour de l'overlay recalés aussi.
  if U.finite(calibration.retryAt) then calibration.retryAt=calibration.retryAt-engine.rebaseDelta end
  if U.finite(engine.panel.updateUntil) then engine.panel.updateUntil=engine.panel.updateUntil-engine.rebaseDelta end
  frame.metaAt=frame.metaAt-engine.rebaseDelta; frame.playerDamageAt=frame.playerDamageAt-engine.rebaseDelta
  if frame.conflictAt then frame.conflictAt=frame.conflictAt-engine.rebaseDelta end
  lastCheckpoint=lastCheckpoint-engine.rebaseDelta; lastRaceSave=lastRaceSave-engine.rebaseDelta
  journal.flushAt=journal.flushAt-engine.rebaseDelta; journal.summaryAt=journal.summaryAt-engine.rebaseDelta
 end
 if host.session~=frame.session then Applier.nextSession(host,frame) end
 if not valid or frame.online or frame.replay or frame.paused then return end
 -- Beta 1.34 : configuration du circuit lue aussi quand le moteur ne tourne pas (aucun onglet coché, app coupée).
 if not ready then lightsCheck() end
 if not ready and not engine.recalibrateRequested and calibration.index==0 and host.caps.probeIndex==0 then
  -- Drapeau natif imposé rendu à AC même sans voiture suivie (app désactivée, onglets décochés, rechargement).
  if not anyOwned() then
   if (host.flagOverride or host.flagLeftover) and Applier.access(host) then Applier.flag(host,frame,false,nil,nil,nil,engine.time) end
   -- DRS coupé par les règles (aucune voiture suivie pour autant) : rendu à toutes les voitures, joueur compris.
   if (host.drsAny or host.drsRelease) and Applier.access(host) then Applier.drs(host,frame,nil,engine.time); Applier.checkpoint(host,frame) end
   -- App désactivée : drapeau noir levé, la disqualification du joueur avec.
   if not globals.enabled and host.blackFlag and Applier.access(host) then
    Applier.releaseBlackFlag(host); if not host.blackFlag then engine.penalties.disqualified=false; engine.penalties.kind='slow' end
   end
   Applier.save(host,globals,profiles,engine.time,frame.replay); return
  end
 end
 local access=Applier.access(host)
 if not access then engine.guard='access'; return end
 if engine.recalibrateRequested then
  stop()
  if calibration.index>0 or anyOwned() then calibration.phase='waiting_reset'; return end
  globals.offsetSign=0; globals.sideSign=0; calibration.attempted=false; calibration.phase='waiting'
  engine.recalibrateRequested=false; Engine.reset(engine,engine.time,false); dirty()
 end
 if not ready then stop(false,engine.guard=='finished'); Applier.save(host,globals,profiles,engine.time,frame.replay); return end
 if loadedTrack~=frame.track then
  loadedTrack=frame.track; engine.zones={}; engine.zoneStart=-1; local data=Snapshot.zones(frame.track)
  lightsCheck()
  if data then
   local zones,err=Zones.parse(data)
   if zones then engine.zones=zones; U.log(engine.log,engine.time,'INFO','zones_loaded',-1)
   else U.log(engine.log,engine.time,'WARN','zones_rejected:'..err,-1) end
  end
  -- Beta 1.61 (tranche A) : fichier des zones du circuit et de son tracé (Documents\Assetto Corsa\AdvancedIA\tracks),
  -- lu après le fichier d'origine ; jamais cru (src/zones.lua, M.decode). Aucun fichier : rien ne change.
  local key=frame.trackKey or ''
  if key~='' then
   local text,why=Applier.trackFileRead(K.zoneFolder,key,K.maxZoneBytes)
   if text then
    local decoded,reason=Zones.decode(text,frame.track,frame.layout,frame.length)
    if decoded then
     local fromFile=#engine.zones
     engine.zones=Zones.merge(engine.zones,decoded)
     U.log(engine.log,engine.time,'INFO',string.format('zones: %d du fichier, %d du pilote, %d apprises (%s)',fromFile,#decoded.user,#decoded.learnt,key),-1)
     if decoded.ignored>0 then U.log(engine.log,engine.time,'WARN',string.format('zones: %d zone(s) ignoree(s) (%s)',decoded.ignored,key),-1) end
     if not decoded.lengthOK then U.log(engine.log,engine.time,'WARN',string.format('zones: longueur du circuit changee, zones apprises ecartees (%s)',key),-1) end
    else U.log(engine.log,engine.time,'WARN',string.format('zones: fichier refuse (%s)',reason),-1); refusedAside(K.zoneFolder,key,'zones') end
   elseif why=='big' then U.log(engine.log,engine.time,'WARN','zones: fichier refuse (taille)',-1); refusedAside(K.zoneFolder,key,'zones') end
  end
 end
 -- Beta 1.61 (tranche A) : enregistrement des zones demandé par le pilote (SAVE, « Forget this track ») ou par
 -- l'apprentissage (seulement avec « Mémoire des circuits »). Jamais à chaque image : sur demande.
 if engine.zoneSaveAsk then
  local ask=engine.zoneSaveAsk; engine.zoneSaveAsk=nil
  local key=frame.trackKey or ''
  -- Finition 1.61 (relecture) : rien n'est écrit sans rien à écrire (SAVE sans zone du pilote, mémoire coupée ; oubli
  -- sans zone apprise).
  local zones=engine.zones
  local userCount=0; for _,z in ipairs(zones) do if z.source=='user' then userCount=userCount+1 end end
  local nothing=ask=='forget' and #(zones.learnt or {})==0 or ask=='user' and userCount==0 and not engine.runtimeG.trackMemory
  if nothing then U.log(engine.log,engine.time,'INFO','zones: rien a enregistrer',-1) end
  if not nothing and key~='' and frame.length>0 and (ask~='learn' or engine.runtimeG.trackMemory) then
   if ask=='forget' then
    local n=#(zones.learnt or {})
    zones.learnt={}; Zones.index(zones)
    U.log(engine.log,engine.time,'INFO',string.format('zones: %d zone(s) apprise(s) oubliee(s) a la demande (%s)',n,key),-1)
   end
   local text,count=Zones.encode(zones,{track=frame.track,layout=frame.layout,length=frame.length,serial=zones.serial or 0})
   if #text<=K.maxZoneBytes and Applier.trackFileWrite(K.zoneFolder,key,text) then
    zones.dirty=nil
    U.log(engine.log,engine.time,'INFO',string.format('zones: fichier enregistre (%d zones, %s)',count,key),-1)
   else U.log(engine.log,engine.time,'WARN','zones: enregistrement impossible',-1) end
  end
 end
 Applier.restore(host,frame,true,engine.time)
 syncRestored()
 local probeBefore=host.caps.probeIndex
 if Config.on(engine.p,'general') then Caps.probe(host.caps,frame,engine.time,engine.runtimeG)
 else cancelProbe(); Caps.mode(host.caps,engine.runtimeG) end
 local levelReport=Caps.report(host.caps,engine.runtimeG)
 if levelReport then U.log(engine.log,engine.time,'INFO',levelReport,-1) end
 if probeBefore==0 and host.caps.probeIndex>0 then
  local index=host.caps.probeIndex; local s=host.cars[index]; local car=frame.cars[index]
  if not s.owned then s.owned=true; s.id=car.identity or car.id; s.originalLevel=host.caps.probeOriginal; s.originalAggression=car.aiAggression end
  s.level=K.probeLevel; host.recoveryDirty=true; Applier.checkpoint(host,frame)
 elseif probeBefore>0 and host.caps.probeIndex==0 then
  -- Fin de sonde : le niveau d'origine vient d'être réécrit ; le suivi d'écriture le reflète.
  local s=host.cars[probeBefore]
  if s.owned and s.level~=nil then s.level=host.caps.probeOriginal; s.levelAt=engine.time end
 end
 local signBefore=globals.offsetSign
 if Config.needsOffset(engine.run,engine.profile) then -- Beta 1.62 : la défense ne compte qu'en course
  -- Beta 1.52 : voitures exclues de la mesure calculées seulement quand elle cherche ou mesure (avant : à chaque image).
  if calibration.index>0 or globals.offsetSign==0 or globals.sideSign==0 then
   for i=1,frame.count do
    local state=engine.states[i]
    frame.cars[i].calibrationBlocked=state.state~='DRIVE' or state.excluded or engine.commands[i].active~=true
   end
  end
  Calibration.step(calibration,frame,host.caps,globals,engine.time)
 -- Beta 1.52 : mesure en cours devenue inutile : seule la mesure est annulée (décalage rendu dès que c'est sûr) ; avant,
 -- stop() refaisait la restitution complète (drapeaux, DRS, attentes des stands, toutes les voitures) à chaque image
 -- tant que l'annulation attendait.
 elseif calibration.index>0 then step(Calibration.cancel,calibration,frame,host.caps,globals) end
 if signBefore~=globals.offsetSign and globals.offsetSign~=0 then U.log(engine.log,engine.time,'INFO',string.format('sens lateral mesure: %d / %d',globals.offsetSign,globals.sideSign),-1) end
 if signBefore~=globals.offsetSign or engine.settingsChanged then engine.settingsChanged=false; dirty() end
 if calibration.index>0 then
  local index=calibration.index; engine.commands[index].active=false
  local s=host.cars[index]; local car=frame.cars[index]
  if not s.owned then s.owned=true; s.id=car.identity or car.id; s.originalLevel=car.aiLevel; s.originalAggression=car.aiAggression end
  s.offset=K.calibrationOffset
  s.offsetReset=false
  if engine.time==calibration.startAt then host.recoveryDirty=true; Applier.checkpoint(host,frame) end
 end
 -- Beta 1.52 : recopiés seulement quand le sens latéral a changé depuis Engine.step (mesure, recalibration) ; le moteur
 -- les recopie déjà à chaque image.
 local rg=engine.runtimeG
 if rg.offsetSign~=globals.offsetSign or rg.sideSign~=globals.sideSign then Config.effectiveGlobals(globals,engine.p,rg) end
 host.calibrationIndex=calibration.index
 Applier.apply(host,frame,engine.commands,engine.runtimeG,engine.time)
 -- Drapeau du joueur : panneaux lumineux du circuit (section du profil en cours, circuit équipé) ; sinon jaune natif du
 -- HUD sur demande.
 local lightsOn=Config.on(engine.run,'lights') and host.trackLights==true
 local flagValue,flagReason=Lights.output(engine.lights,engine.incidents,lightsOn)
 Applier.flag(host,frame,flagValue,flagReason,lightsOn and engine.time or nil,engine.run.lightsHold,engine.time)
 Applier.penalty(host,frame,engine.penalties)
 Applier.beep(host,frame,engine.drs)
 Applier.deltaBeep(host,frame,engine.deltaBeep)
 Applier.drs(host,frame,engine.commands,engine.time)
 announce()
 local periodic=engine.time-lastCheckpoint>=K.saveDelay
 if host.recoveryDirty or periodic then lastCheckpoint=engine.time; Applier.checkpoint(host,frame,periodic) end
 saveRace(false)
 Applier.save(host,globals,profiles,engine.time,frame.replay)
end
-- Mise à jour : vérification au lancement (après K.updateDelay s), état « à l'arrêt » pour l'installation (pause, menu
-- ou stands) ; information de l'overlay une fois par lancement, aux stands seulement, retirée dès la sortie.
local function updateTick(dt)
 if not port.ready then return end
 local step=U.finite(dt) and dt>0 and dt<=K.dtMax and dt or 0
 if U.finite(dt) and dt>0 and dt<=K.dtMax then updateClock=updateClock+dt end
 local counter=Applier.clock(host)
 if counter and updateCounter and counter>updateCounter then step=math.max(step,counter-updateCounter) end
 updateCounter=counter; updateNow=updateNow+math.min(step,1); host.updateNow=updateNow
 -- Après la restitution (redémarrage demandé) : seule l'alerte de redémarrage en retard reste suivie.
 if released then if updater.phase=='restarting' then Update.tick(updater,port,false,updateNow); updateLog() end; return end
 -- Beta 1.52 : en lecture légère, voiture du joueur relue à part (frame.lightPlayer).
 local slot=frame.player>0 and frame.player or frame.lightPlayer or 0
 local player=slot>0 and frame.cars[slot] or nil
 host.updateStopped=Update.stopped(frame,player)
 Update.tick(updater,port,host.updateStopped,updateNow)
 if not updateAsked and globals.updateCheck and updateClock>=K.updateDelay and updater.phase=='idle' then updateAsked=true; Update.check(updater,port,updateNow) end
 local pit=player~=nil and player.pit==true and not frame.paused
 local panelState=engine.panel
 if pit and not updateNoticed and Update.offered(updater) then
  updateNoticed=true; panelState.updateUntil=engine.time+K.updateNotice; panelState.updateVersion=updater.release.version
 elseif not pit then panelState.updateUntil=-math.huge end
 updateLog()
end
local function protect(fn,arg)
 local ok,err=pcall(fn,arg)
 if not ok then
  engine.errors=engine.errors+1; engine.panic=true
  U.log(engine.log,engine.time,'ERROR',tostring(err):sub(1,256),-1)
  pcall(stop)
 end
 return ok
end
-- Démarrage surveillé (mise à jour) : la version installée est confirmée après K.bootFrames images où le moteur a tourné
-- sans erreur et K.bootUIFrames dessins sans erreur protégée de la fenêtre ou de l'overlay (Beta 1.36 : une interface en
-- échec à chaque image n'est jamais confirmée ; la version est défaite au lancement suivant).
local booted=false
local bootEngine,bootUI=0,0
if port.unreadable then U.log(engine.log,0,'ERROR','mise a jour: module illisible, app chargee sans mise a jour ('..port.unreadable..')',-1) end
HUMANAI={engine=engine,host=host,release=release,updater=updater,port=port,panel=panel}
-- Pont vers les apps compagnes (Beta 1.46) : seulement si SpotterEnginer est installé (dossier apps/lua/SpotterEnginer et
-- son manifest.ini, lus une fois au lancement), l'état du moteur est recopié à chaque image dans une structure partagée
-- (ac.connect), après update(), même moteur arrêté (pause, replay, en ligne, app coupée : la raison est publiée). Sans
-- lui : rien n'est ouvert ni calculé, une ligne au journal. Lecture seule du moteur ; une erreur coupe le pont seul (une
-- ligne au journal), jamais le moteur ni l'interface.
companionPresent=Applier.companionInstalled(companion)
if companionPresent then
 local why
 -- Beta 1.60 : version de SpotterEnginer lue une fois (son manifest.ini) : plus ancienne que K.seStartMin*, le tour de
 -- formation et le départ lancé lui sont inconnus (avertissement à l'accueil quand « Départ de la course » n'est pas
 -- le départ arrêté). Illisible : aucun avertissement, une ligne au journal.
 local version=Applier.companionVersion(companion)
 if version then
  host.companionVersionText=string.format('%d.%d.%d',version[1],version[2],version[3])
  host.companionOldStart=Applier.versionBelow(version,{K.seStartMinMajor,K.seStartMinMinor,K.seStartMinPatch})
  U.log(engine.log,0,'INFO',string.format('pont des apps compagnes: %s version %s%s',companion,host.companionVersionText,host.companionOldStart and ' (tour de formation et depart lance inconnus avant la '..string.format('%d.%d.%d',K.seStartMinMajor,K.seStartMinMinor,K.seStartMinPatch)..')' or ''),-1)
 else U.log(engine.log,0,'INFO','pont des apps compagnes: version de '..companion..' illisible',-1) end
 bridge=Bridge.new(Config.release)
 bridgePort,why=Applier.bridgeOpen(Bridge.layout)
 U.log(engine.log,0,'INFO',bridgePort and string.format('pont des apps compagnes: ouvert (version %d)',Bridge.layout.version) or 'pont des apps compagnes: indisponible ('..tostring(why)..')',-1)
else
 U.log(engine.log,0,'INFO','pont des apps compagnes: '..companion..' absent, pont inactif',-1)
end
-- Une seule fonction pour l'appel protégé : rien n'est créé à chaque image.
local function bridgeWork() Bridge.beat(bridge,bridgePort.hello); Bridge.publish(bridge,bridgePort.data,engine,frame) end
local function bridgeStep()
 if released or not bridgePort then return end
 local ok,err=pcall(bridgeWork)
 if not ok then
  pcall(Bridge.close,bridge,bridgePort.hello); bridgePort=nil
  U.log(engine.log,engine.time or 0,'ERROR','pont des apps compagnes coupe: '..tostring(err):sub(1,200),-1)
 end
end
-- Tests : port du pont (nil sans app lectrice, ou après une erreur ou le déchargement).
HUMANAI.bridgePort=function() return bridgePort end
local costFrames=0
function script.HUMANAI__UPDATE(dt)
 local before=Applier.clock(host)
 prof.at=before; local cur=prof.cur; for i=1,7 do cur[i]=0 end
 local ran=protect(update,dt)
 mark(4)
 if ran and not booted then
  bootEngine=bootEngine+1
  -- Démarrage confirmé : surveillance levée, puis restes de la mise à jour effacés (Beta 1.37).
  if bootEngine>=K.bootFrames and bootUI>=K.bootUIFrames then booted=true; bootWatched=false; pcall(port.bootOk); if port.ready then pcall(Update.tidy,updater,port); updateLog() end end
 end
 local ok,err=pcall(updateTick,dt)
 if not ok then host.errors=host.errors+1; U.log(engine.log,engine.time,'ERROR','mise a jour: '..tostring(err):sub(1,200),-1) end
 mark(5)
 -- Options de CSP (Beta 1.40) : une erreur les fige jusqu'au prochain lancement (jamais une erreur à chaque image).
 if not released and csp.writable and not bootWatched then
  local okCsp,errCsp=pcall(cspStep,dt)
  if not okCsp then csp.writable=false; host.errors=host.errors+1; U.log(engine.log,engine.time,'ERROR','options CSP: '..tostring(errCsp):sub(1,200),-1) end
 end
 mark(6)
 bridgeStep()
 mark(7)
 local after=before and Applier.clock(host)
 prof.at=nil
 if after then
  local cost=math.max(0,after-before)*1000
  for i=1,7 do prof.sum[i]=prof.sum[i]+cur[i] end; prof.frames=prof.frames+1
  -- Affinage 1.61 : image plus lente que K.slowFrameMs : coût de chaque poste (pointe de 202 ms à Spa, jamais située).
  if cost>K.slowFrameMs and prof.slowLogs<K.slowFrameLogs and menuClock-prof.slowAt>=K.slowFrameGap then
   prof.slowLogs=prof.slowLogs+1; prof.slowAt=menuClock
   U.log(engine.log,engine.time,'WARN',string.format('image lente: %.0f ms (lecture %.1f, moteur %.1f, fichiers %.1f, commandes %.1f, mise a jour %.1f, options CSP %.1f, pont %.1f)',
    cost,cur[1]*1000,cur[2]*1000,cur[3]*1000,cur[4]*1000,cur[5]*1000,cur[6]*1000,cur[7]*1000),-1)
  end
  -- Affinage 1.62 (AUDIT_FPS cause 9) : première image mesurée (chargement des places de grille, des panneaux, des
  -- zones) hors du maximum : avant, le « max » de chaque résumé restait cette saccade de chargement.
  if costFrames>0 then engine.maxFrame=math.max(engine.maxFrame,cost) end
  -- Beta 1.52 : compteur d'images mesurées propre (engine.frames n'avance que moteur en marche : la moyenne valait
  -- alors le coût de la dernière image).
  costFrames=math.min(costFrames+1,K.performanceWindow)
  engine.meanFrame=engine.meanFrame+(cost-engine.meanFrame)/costFrames
 end
end
-- Un seul point d'entrée par image, actif aussi lorsque le setup est ouvert.
function script.update(dt) script.HUMANAI__UPDATE(dt) end
function script.HUMANAI__MENU() if not released then Applier.menu(host,Snapshot.menu()) end end
-- Fenêtres de réglage : une erreur d'affichage est journalisée (une fois par message) sans arrêter le moteur.
local lastUIError=''
local function protectUI(fn,arg)
 local ok,err=pcall(fn,arg)
 if ok then
  if not booted then bootUI=bootUI+1 end
 else
  host.errors=host.errors+1
  local text=tostring(err):sub(1,200)
  if text~=lastUIError then lastUIError=text; U.log(engine.log,engine.time,'ERROR','ui:'..text,-1) end
 end
end
-- Image lente d'une fenêtre (Beta 1.39) : au-delà de K.uiSlowFrame s, un WARN par lieu (onglet, section ; overlay), au
-- plus K.uiSlowLogs, pour situer un gel dans le journal de la séance suivante. Première image de chaque fenêtre (polices
-- chargées) : seuil K.uiSlowFirst.
local slowSeen,slowCount,slowWarm={},0,{}
local Widgets=require('src/widgets'); local missingNoted=false
local function timedUI(fn,place)
 local started=Applier.clock(host)
 protectUI(fn,panel)
 local ended=started and Applier.clock(host)
 local spent=ended and ended-started or 0
 local slot=place=='overlay' and 9 or 8
 prof.sum[slot]=prof.sum[slot]+spent
 local window=place or 'main'
 local limit=slowWarm[window] and K.uiSlowFrame or K.uiSlowFirst; slowWarm[window]=true
 if spent>limit and slowCount<K.uiSlowLogs then
  local where=place or UI.where(panel)
  if not slowSeen[where] then
   slowSeen[where]=true; slowCount=slowCount+1
   U.log(engine.log,engine.time,'WARN',string.format('interface lente: %s, %.0f ms',where,spent*1000),-1)
  end
 end
 -- Correctif 1.61 : texte absent dessiné vide (src/widgets.lua), appelant noté une fois.
 if Widgets.missing and not missingNoted then missingNoted=true; U.log(engine.log,engine.time,'WARN','interface: texte absent ('..Widgets.missing..')',-1) end
end
function script.HUMANAI__MAIN()
 script.HUMANAI__MENU()
 if host.menuVisible then
  -- Une seule fois : fenêtre ramenée à la taille compacte (Beta 1.14), puis la taille du pilote est respectée.
  if not globals.windowCompacted and Applier.compactWindow(host,UI.compactSize()) then globals.windowCompacted=true; dirty() end
  timedUI(UI.main)
 end
end
-- Panneau de drapeaux : protégé comme les autres fenêtres ; une erreur d'affichage est journalisée une fois et
-- n'arrête jamais le moteur.
-- Tests : panneau de drapeaux seul (le même contenu que dans l'overlay), hors de tout point d'entrée de CSP (Beta 1.52 :
-- l'ancien rappel de fenêtre HUMANAI__FLAGS, absent du manifeste depuis la Beta 1.25, est retiré).
HUMANAI.drawFlags=function() if not released then protectUI(UI.flags,panel) end end
-- Overlay en jeu (Beta 1.25, rappel IN_GAME) : fenêtre transparente dessinée par l'app.
function script.HUMANAI__HUD()
 if released then return end
 timedUI(UI.hud,'overlay')
 -- Beta 1.59 (relecture) : overlay coupé : messages d'AC jamais bloqués par l'app (AC les dessine lui-même).
 local shown=globals.overlayEnabled~=false
 pcall(messages,globals.overlayMessages and globals.overlayBlockMessages and globals.enabled and shown,globals.overlayMessages and globals.enabled and shown and Cspgui.applied(csp,'HIDE_SYSTEM_MESSAGES'))
end
