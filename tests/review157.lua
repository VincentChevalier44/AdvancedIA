-- Beta 1.57 (Ved, Overtake : « l'app dit que je suis en ligne alors que je suis hors connexion ») : la suspension
-- « en ligne » est nommée (vraie session en ligne, mode alt-online de CSP, lecture impossible) pour la fenêtre et le
-- journal ; elle suspend toujours de la même façon. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Snapshot=require('src/snapshot')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
-- Lecture de CSP : genre de la suspension ; s.online reste le seul drapeau qui suspend.
tests.SNAPSHOT_ONLINE_KIND_157=function()
 local host=require('tests/host').create(true)
 local s=Snapshot.new()
 Snapshot.read(s,1/60,1); assert(s.online==false and s.onlineKind=='','offline')
 host.sim.isOnlineRace=true; Snapshot.read(s,1/60,2); assert(s.online==true and s.onlineKind=='online','real online')
 host.sim.isOnlineRace=false; host.sim.isAltOnlineRace=true; Snapshot.read(s,1/60,3); assert(s.online==true and s.onlineKind=='alt','alt-online')
 host.sim.isOnlineRace=true; Snapshot.read(s,1/60,4); assert(s.online==true and s.onlineKind=='online','both flags: real online first')
 host.sim.isOnlineRace=false; host.sim.isAltOnlineRace=false
 local saved=ac.getSim
 ac.getSim=function() error('C:\\Games\\Assetto Corsa\\extension\\internal\\lib.lua:12: sim unavailable',0) end
 local ok,read=pcall(Snapshot.read,s,1/60,5)
 ac.getSim=saved
 assert(ok and read==false,'read failure handled, nothing thrown')
 assert(s.online==true and s.onlineKind=='read' and s.count==0,'read failure still suspends, named')
 assert(s.readError=='lib.lua:12: sim unavailable','error text without its folders: '..tostring(s.readError))
 Snapshot.read(s,1/60,6); assert(s.online==false and s.onlineKind=='','offline again')
end
-- Texte d'erreur pour le journal : une ligne, sans dossier, raccourci.
tests.CLEAN_ERROR_157=function()
 assert(Snapshot.cleanError(nil)=='' and Snapshot.cleanError('plain')=='plain','empty and plain')
 assert(Snapshot.cleanError('D:/a/b/c.lua:3: bad\nnext line')=='c.lua:3: bad next line','folders and line break removed')
 assert(Snapshot.cleanError('see C:\\x\\y.txt and /tmp/z.log')=='see y.txt and z.log','every folder removed')
 assert(Snapshot.cleanError('D:\\Steam Library\\Assetto Corsa\\apps\\lua\\AdvancedIA\\src\\snapshot.lua:140: attempt to index nil')=='snapshot.lua:140: attempt to index nil','folders with spaces removed')
 local long=Snapshot.cleanError(string.rep('x',K.readErrorChars+40))
 assert(#long==K.readErrorChars,'shortened to K.readErrorChars')
end
-- Moteur : garde « online » inchangée (et le pont), genre pour la fenêtre ; une ligne au début de la suspension ou à
-- un changement de genre, une suspension du même genre qui revient au plus toutes les K.onlineLogGap s.
tests.ENGINE_GUARD_KIND_157=function()
 local e,f=F.scene('C',3)
 F.tick(e,f,0.5); assert(e.guard=='ready' and e.guardKind==nil,'ready offline')
 f.online=true; f.onlineKind='alt'; F.tick(e,f,1)
 assert(e.guard=='online' and e.guardKind=='alt','alt-online: online guard, alt kind')
 assert(count(e,'suspension: mode alt-online de CSP')==1,'logged when it starts')
 -- Une seule écriture (le journal circulaire fusionne aussi les doublons : l'heure de la ligne le prouve).
 local at=e.onlineLogAt
 F.tick(e,f,2); assert(count(e,'suspension: mode alt-online de CSP')==1 and e.onlineLogAt==at,'logged once')
 f.onlineKind='read'; f.readError='lib.lua:12: sim unavailable'; F.tick(e,f,0.5)
 assert(e.guardKind=='read' and count(e,'suspension: lecture de l etat du jeu impossible (lib.lua:12: sim unavailable), aucune commande')==1,'kind change logged')
 f.online=false; f.onlineKind=''; F.tick(e,f,0.5); assert(e.guard=='ready' and e.guardKind==nil,'offline again')
 f.online=true; f.onlineKind='read'; F.tick(e,f,0.5)
 assert(count(e,'suspension: lecture de l etat du jeu impossible')==1,'same kind back within the gap: not logged again')
 f.online=false; f.onlineKind=''; F.tick(e,f,K.onlineLogGap)
 f.online=true; f.onlineKind='read'; F.tick(e,f,0.5)
 assert(count(e,'suspension: lecture de l etat du jeu impossible')==2,'same kind back after the gap: logged again')
 -- Genre absent (cadre ancien) ou vrai en ligne : « online ».
 f.onlineKind=nil; F.tick(e,f,0.5)
 assert(e.guardKind=='online' and count(e,'suspension: session en ligne, aucune commande')==1,'real online named and logged')
 f.online=false; F.tick(e,f,0.5)
end
-- Textes FR et EN : garde, puce et bandeau distincts pour chaque genre ; bandeau avec son bouton « Compris ».
tests.GUARD_TEXTS_157=function()
 local fr=require('src/lang'); local en=require('src/lang_en')
 for _,L in ipairs({fr,en}) do
  for _,k in ipairs({'altonline','readerror'}) do
   assert(type(L.guards[k])=='string' and L.guards[k]~=L.guards.online,k..' guard text')
   assert(type(L.pillStates[k])=='string' and L.pillStates[k]~=L.pillStates.online,k..' pill')
   local b=L.banners[k]; assert(b and b[1]~=L.banners.online[1] and b[2]~=L.banners.online[2] and b[3]==L.banners.online[3],k..' banner')
  end
  assert(L.banners.altonline[2]:find('Content Manager',1,true),'alt-online banner says what to do')
 end
end
-- Version de CSP plus ancienne (Ved : CSP 0.3.0-preview212) : un champ absent d'une structure FFI lève une erreur à la
-- lecture. Structure factice qui lève sur les champs choisis et compte leurs lectures.
local function struct(source,absent,hits)
 return setmetatable({},{__index=function(_,k)
  if absent[k] then hits.n=hits.n+1; error("'struct simState' has no member named '"..k.."'",0) end
  return source[k]
 end})
end
tests.OLD_CSP_SIM_FIELDS_157=function()
 local host=require('tests/host').create(true)
 local savedSim,savedCar=ac.getSim,ac.getCar
 local ok,err=pcall(function()
  Snapshot.resetFields()
  local hits={n=0}
  local sim=struct(host.sim,{isAltOnlineRace=true,isReplayOnlyMode=true,isInMainMenu=true},hits)
  ac.getSim=function() return sim end
  local s=Snapshot.new()
  assert(Snapshot.read(s,1/60,1)==true,'session read despite the missing fields')
  assert(s.online==false and s.onlineKind=='' and s.replay==false and s.count==host.sim.carsCount,'optional fields missing: not online, cars counted')
  assert(s.missingSim=='isAltOnlineRace, isReplayOnlyMode, isInMainMenu' and s.missingCar=='','missing fields listed: '..s.missingSim)
  -- Ensuite : plus aucune lecture d'un champ absent (aucune erreur, aucune protection à chaque image).
  hits.n=0; for n=2,20 do Snapshot.read(s,1/60,n/60) end
  assert(hits.n==0 and s.online==false,'cached: missing fields never read again')
  assert(Snapshot.menu()==false,'menu read through the same view')
  -- Champ essentiel absent : vraie erreur de lecture, nommée.
  Snapshot.resetFields()
  local sim2=struct(host.sim,{carsCount=true},hits); ac.getSim=function() return sim2 end
  local s2=Snapshot.new()
  assert(Snapshot.read(s2,1/60,1)==false,'essential field missing: read fails')
  assert(s2.online==true and s2.onlineKind=='read' and s2.readError=='champ de CSP essentiel absent: carsCount' and s2.count==0,'named read error: '..tostring(s2.readError))
  -- Champ absent de la seule lecture de course (drapeau, fenêtre d'arrêt) : réessayée par la vue, sans erreur comptée.
  Snapshot.resetFields()
  local sim4=struct(host.sim,{raceFlagType=true},hits); ac.getSim=function() return sim4 end
  local s4=Snapshot.new()
  assert(Snapshot.read(s4,1/60,1)==true and s4.flag==0 and s4.errors==0,'race fields degrade field by field')
  Snapshot.read(s4,1/60,2); assert(s4.missingSim=='raceFlagType' and s4.errors==0,'race field listed, no error')
  -- Champ absent des voitures : voitures lues quand même, valeur neutre.
  Snapshot.resetFields(); ac.getSim=savedSim
  local carHits={n=0}; local views={}
  ac.getCar=function(index) local raw=host.cars[index]; if not raw then return nil end; views[index]=views[index] or struct(raw,{isAIUsingRainTyres=true,drsPresent=true},carHits); return views[index] end
  local s3=Snapshot.new()
  assert(Snapshot.read(s3,1/60,1)==true,'cars read despite the missing fields')
  local valid=0; for i=1,s3.count do if s3.cars[i].valid then valid=valid+1 end end
  assert(valid==s3.count and s3.count>0,'every car valid')
  assert(s3.cars[2].nativeRainTyresKnown==false and s3.cars[2].drsPresent==false,'neutral values')
  Snapshot.read(s3,1/60,2)
  assert(s3.missingCar=='isAIUsingRainTyres, drsPresent' and s3.missingSim=='','car fields listed: '..s3.missingCar)
  carHits.n=0; Snapshot.read(s3,1/60,3); assert(carHits.n==0,'cached for the cars too')
 end)
 ac.getSim,ac.getCar=savedSim,savedCar; Snapshot.resetFields()
 assert(ok,err)
end
-- Moteur : une ligne par nouvelle liste de champs absents ; aucune ligne sans champ absent.
tests.OLD_CSP_FIELDS_LOG_157=function()
 local e,f=F.scene('C',3)
 f.fieldsSerial=1; f.missingSim=''; f.missingCar=''; F.tick(e,f,0.5)
 assert(count(e,'champs de CSP absents')==0,'nothing missing: no line')
 f.fieldsSerial=2; f.missingSim='isAltOnlineRace, isInMainMenu'; F.tick(e,f,1)
 assert(count(e,'champs de CSP absents (version plus ancienne, lus comme absents): session isAltOnlineRace, isInMainMenu | voitures -')==1,'listed once')
 -- Le journal circulaire fusionne les doublons : la liste notée le prouve.
 F.tick(e,f,1); assert(count(e,'champs de CSP absents')==1 and e.fieldsLogged==2,'not repeated')
 f.fieldsSerial=3; f.missingCar='drsPresent'; F.tick(e,f,0.5)
 assert(count(e,'session isAltOnlineRace, isInMainMenu | voitures drsPresent')==1,'new list logged')
end
-- Résumé du journal : lectures de l'état du jeu en échec (depuis le lancement), seulement s'il y en a eu.
tests.READ_ERRORS_SUMMARY_157=function()
 local Journal=require('src/journal')
 local e,f=F.scene('C',3)
 F.tick(e,f,0.5)
 f.errors=0; assert(not Journal.summary(e):find('lectures de l etat du jeu en echec',1,true),'none: not written')
 f.errors=7; assert(Journal.summary(e):find(' | lectures de l etat du jeu en echec 7',1,true),'counted at the end of the summary')
 f.errors=0
end
return tests
