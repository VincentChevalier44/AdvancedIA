-- Mise à jour depuis GitHub (Beta 1.33, renforcée en Beta 1.35) : logique pure avec un port imité (journal des appels),
-- puis le vrai port (src/remote.lua) sur une imitation de CSP à deux disques (tests/updatefake.lua).
local Up=require('src/update')
local Remote=require('src/remote')
local Fake=require('tests/updatefake')
local tests={}
local SHA=string.rep('ab',32)
-- Corps du paquet : exactement la taille annoncée par la version publiée.
local SIZE=1000000
local ZIPDATA=string.rep('z',SIZE)
local function release(over)
 local r={tag_name='v1.34',name='Beta 1.34',draft=false,prerelease=false,html_url='https://github.com/VincentChevalier44/AdvancedIA/releases/tag/v1.34',
  published_at='2026-11-05T10:00:00Z',body='## Beta 1.34\r\n\r\n- **Panneaux** lumineux\n- `DRS`\n',
  assets={{name='AdvancedIA-Beta-1.34.zip',size=SIZE,browser_download_url=Up.download..'v1.34/AdvancedIA-Beta-1.34.zip'},
   {name='AdvancedIA-Beta-1.34.sha256',size=100,browser_download_url=Up.download..'v1.34/AdvancedIA-Beta-1.34.sha256'}}}
 for k,v in pairs(over or {}) do r[k]=v end
 return r
end
local function entries() local t={}; for _,f in ipairs(Up.required) do t[#t+1]=Up.prefix..f end; t[#t+1]=Up.prefix..'src/'; return t end
-- Port imité : o.* règle les réponses et les versions des sources (next, current, backup), calls garde l'ordre.
local function port(o)
 o=o or {}
 local p={calls={},marked=o.marked,reported=o.report,boots=o.boot,note=o.failed}
 local versions={next=o.next==nil and 'Beta 1.34' or o.next or nil,current=o.current,backup=o.backup}
 local function log(x) p.calls[#p.calls+1]=x end
 function p.get(url,_,cb)
  log('get '..url)
  local function answer()
   if url==Up.api then cb(o.apiErr,o.apiStatus or 200,'api')
   elseif url:find('%.sha256$') then cb(o.shaErr,o.shaStatus or 200,o.shaText or (SHA..'  AdvancedIA-Beta-1.34.zip\n'))
   else cb(o.zipErr,o.zipStatus or 200,o.zipData or ZIPDATA) end
  end
  if p.hold then p.pending=p.pending or {}; p.pending[#p.pending+1]=answer else answer() end
 end
 function p.flush() while p.pending and #p.pending>0 do local list=p.pending; p.pending={}; for _,fn in ipairs(list) do fn() end end end
 function p.json() if o.json==nil then return release() end; return o.json or nil end
 function p.sha256() return o.hash or SHA end
 function p.entries() return o.entries or entries() end
 function p.entry(_,name) if name:sub(-4)=='.lua' and o.lua then return o.lua end; return o.manifest or '[ABOUT]\nVERSION=Beta 1.34\n' end
 function p.installedVersion() return o.installed end
 function p.sourceVersion(name) return versions[name] end
 function p.sourceComplete(name) return versions[name]~=nil and not (o.incomplete or {})[name] end
 function p.sourceHas() return o.missing==nil end
 function p.markerFile() return 'state/installing.txt' end
 function p.marker() return p.marked end
 function p.mark(t) log('mark '..t:match('^[^\n]*')); if o.markFails then return false end; p.marked=t; return true end
 function p.clearMarker() log('clear'); if o.clearFails then return false end; p.marked=nil; return true end
 function p.report(t) log('report '..t); p.reported=t; return true end
 function p.takeReport() local t=p.reported; p.reported=nil; return Up.parseReport(t) end
 function p.boot() local b=p.boots; if not b then return nil end; return b[1],b[2],b[3] end
 function p.bootSet(version,from,count) log('boot '..version..' '..(count or 0)); p.boots={version,count or 0,from}; return true end
 function p.bootClear() log('boot clear'); p.boots=nil; return true end
 function p.failedNote(t) log('failed note'); p.note=t; return true end
 function p.failed() return p.note end
 function p.clearFailed() p.note=nil; return true end
 function p.stage(_,names,cb)
  log('stage'); p.names=names
  local function done() cb(o.stageErr) end
  if p.holdStage then p.staged=done else done() end
 end
 function p.snapshot(source) log('snapshot'); p.snapSource=source; if o.snapshotFails then return false,'src/ui.lua' end; versions.current=o.installed or 'Beta 1.33'; return true,nil,{saved=2,ms=1} end
 function p.place(name)
  log('place '..name)
  if (o.placeFails or {})[name] then return false,o.placeFails[name] end
  o.installed=versions[name]; return true,nil,{compared=5,copied=3,ms=2}
 end
 function p.promote(kind) log('promote '..kind); if o.promoteFails then return false,'renommage' end; if kind=='update' then versions.backup=versions.current end; return true end
 function p.restart() log('restart') end
 return p
end
local function find(calls,x) for i,c in ipairs(calls) do if c==x then return i end end end
local function count(calls,x) local n=0; for _,c in ipairs(calls) do if c==x then n=n+1 end end; return n end
local function ready(o) local u=Up.new('Beta 1.33'); local p=port(o); Up.start(u,p); Up.check(u,p,100); return u,p end
local function events(u) local out=Up.take(u,{}); local text={}; for i,e in ipairs(out) do text[i]=e[1]..' '..e[2] end; return table.concat(text,'\n') end
local function ordered(calls,list) local last=0; for _,x in ipairs(list) do local i=find(calls,x); if not i or i<last then return false,x end; last=i end; return true end

tests.UPDATE_VERSIONS=function()
 assert(table.concat(Up.version('Beta 1.33'),'.')=='1.33' and table.concat(Up.version('v1.33.2'),'.')=='1.33.2')
 assert(table.concat(Up.version('AdvancedIA-Beta-1.34.zip'),'.')=='1.34' and Up.version('Beta')==nil and Up.version(nil)==nil)
 assert(Up.newer('Beta 1.34','Beta 1.33') and Up.newer('v1.33.1','Beta 1.33') and Up.newer('Beta 1.40','Beta 1.39'))
 assert(not Up.newer('Beta 1.33','Beta 1.33') and not Up.newer('Beta 1.32','Beta 1.33') and not Up.newer('Beta 1.33','Beta 1.33.0'))
 assert(Up.newer('Beta 2.0','Beta 1.99') and not Up.newer('x','Beta 1.0') and not Up.newer('Beta 1.0','x'))
 assert(Up.label('v1.34')=='Beta 1.34' and Up.label('')==nil)
end
tests.UPDATE_RELEASE_PARSE=function()
 local r=Up.release(release())
 assert(r and r.version=='Beta 1.34' and r.zip.size==SIZE and r.published=='2026-11-05' and r.page:find('/tag/v1.34',1,true))
 assert(r.notes[1]=='Beta 1.34' and r.notes[2]=='' and r.notes[3]=='- Panneaux lumineux' and r.notes[4]=='- DRS' and #r.notes==4)
 -- Brouillon, préversion, sans paquet ou sans empreinte, autre nom, autre adresse, taille aberrante : refusés.
 assert(not Up.release(release({draft=true})) and not Up.release(release({prerelease=true})) and not Up.release(release({tag_name='latest'})))
 local a=release(); table.remove(a.assets,2); assert(not Up.release(a))
 a=release(); table.remove(a.assets,1); assert(not Up.release(a))
 a=release(); a.assets[1].name='AdvancedIA-Beta-1.35.zip'; assert(not Up.release(a))
 -- Beta 1.49 : les noms d'avant le changement de nom (ACAdvancedIA-Beta-…) ne sont jamais retenus, ni l'ancien dépôt.
 a=release(); a.assets[1].name='ACAdvancedIA-Beta-1.34.zip'; assert(not Up.release(a))
 a=release(); a.assets[2].name='ACAdvancedIA-Beta-1.34.sha256'; assert(not Up.release(a))
 a=release(); a.assets[2].name='ACAdvancedIA-Beta-1.34.zip.sha256'; assert(not Up.release(a))
 a=release(); a.assets[1].browser_download_url='https://github.com/VincentChevalier44/ACAdvancedIA/releases/download/v1.34/AdvancedIA-Beta-1.34.zip'; assert(not Up.release(a))
 assert(Up.prefix=='apps/lua/AdvancedIA/' and Up.required[2]=='AdvancedIA.lua' and Up.repo=='VincentChevalier44/AdvancedIA')
 a=release(); a.assets[1].browser_download_url='https://example.com/AdvancedIA-Beta-1.34.zip'; assert(not Up.release(a))
 a=release(); a.assets[2].browser_download_url='https://example.com/AdvancedIA-Beta-1.34.sha256'; assert(not Up.release(a))
 a=release(); a.assets[1].size=0; assert(not Up.release(a))
 a=release(); a.assets[1].size=Up.sizeMax+1; assert(not Up.release(a))
 a=release(); a.html_url='https://evil.example/'; assert(Up.release(a).page==Up.page)
 assert(not Up.release(nil) and not Up.release('x'))
 local long=string.rep('x',500); local n=Up.notes(long..'\n'..string.rep('l\n',100))
 assert(#n[1]==Up.lineMax and #n==Up.notesMax)
 -- Coupure UTF-8 : jamais au milieu d'un caractère (« → » sur trois octets).
 local arrows=Up.notes(string.rep('→',100))[1]
 assert(arrows:sub(-3)=='...' and #arrows<=Up.lineMax and arrows:sub(1,-4)==string.rep('→',math.floor((Up.lineMax-3)/3)))
 assert(Up.cut('aé',2)=='a' and Up.cut('aé',3)=='aé' and Up.cut('abc',5)=='abc')
end
tests.UPDATE_DIGEST_AND_CONTENT=function()
 assert(Up.digest(SHA..'  AdvancedIA-Beta-1.34.zip','AdvancedIA-Beta-1.34.zip')==SHA)
 assert(Up.digest(SHA:upper()..' *AdvancedIA-Beta-1.34.zip\r\n','AdvancedIA-Beta-1.34.zip')==SHA)
 assert(not Up.digest(SHA..'  autre.zip','AdvancedIA-Beta-1.34.zip') and not Up.digest('abc  AdvancedIA-Beta-1.34.zip','AdvancedIA-Beta-1.34.zip'))
 assert(not Up.digest(nil,'x'))
 assert(Up.content(entries()))
 local function with(x) local t=entries(); t[#t+1]=x; return t end
 assert(not Up.content(with('apps/lua/Autre/x.lua')) and not Up.content(with(Up.prefix..'../../evil.lua')) and not Up.content(with(Up.prefix..'src/../../x')))
 assert(not Up.content(with(Up.prefix..'src\\a.lua')) and not Up.content(with('C:/evil')) and not Up.content(with('/apps/lua/AdvancedIA/x')))
 assert(not Up.content(with(Up.prefix..'src//a.lua')) and not Up.content(with(Up.prefix..'./a.lua')))
 -- Entrées de dossier et noms qui contiennent seulement des points : acceptés.
 assert(Up.content(with(Up.prefix..'fonts/')) and Up.content(with(Up.prefix..'docs/notes..md')))
 -- Chaque fichier indispensable, dont le module de mise à jour lui-même.
 for i=1,#Up.required do local t=entries(); table.remove(t,i); assert(not Up.content(t),'required '..i) end
 assert(not Up.content({}) and not Up.content(nil))
 -- Fichiers du paquet : sans les entrées de dossier, chemins relatifs à l'app.
 local files=Up.files(entries()); assert(#files==#Up.required and files[1]=='manifest.ini')
 -- Modules requis par le code du paquet : tous présents.
 local list=entries(); list[#list+1]=Up.prefix..'src/ui.lua'
 assert(Up.requires(list,function() return "local W=require('src/update')\nlocal R=require(\"src/remote\")" end))
 local okReq,missing=Up.requires(list,function(name) return name:find('ui.lua',1,true) and "local G=require('src/groups')" or '' end)
 assert(not okReq and missing=='src/groups')
 assert(Up.requires(list,function() return "local bit=require('bit')" end),'library modules ignored')
 assert(Up.manifestVersion('[ABOUT]\r\nVERSION=Beta 1.34\r\n')=='Beta 1.34' and Up.manifestVersion('NAME=x')==nil and Up.manifestVersion(nil)==nil)
 assert(Up.manifestVersion('REQUIRED_VERSION=0.2.3\nVERSION=Beta 1.34')=='Beta 1.34' and Up.manifestVersion('REQUIRED_VERSION=0.2.3')==nil)
 -- À l'arrêt : pause, menu, ou emplacement des stands à l'arrêt ; jamais la voie des stands en roulant.
 assert(Up.stopped({paused=true}) and Up.stopped({menu=true}) and Up.stopped({},{inPitBox=true,kmh=0}))
 assert(not Up.stopped({},{inPitBox=true,kmh=40}) and not Up.stopped({},{pit=true,inPitBox=false,kmh=0}) and not Up.stopped({}) and not Up.stopped(nil,{inPitBox=true,kmh=0}))
 assert(Up.parseReport('recovered Beta 1.33 -> Beta 1.34')=='recovered' and Up.parseReport('n importe quoi')==nil)
 local kind,from,to,auto=Up.parseReport('rollback Beta 1.35 -> Beta 1.34 auto'); assert(kind=='rollback' and from=='Beta 1.35' and to=='Beta 1.34' and auto)
 local kind2,from2,to2,tries=Up.parse('update Beta 1.33 -> Beta 1.34\ntries 1'); assert(kind2=='update' and from2=='Beta 1.33' and to2=='Beta 1.34' and tries==1)
end
tests.UPDATE_CHECK_STATES=function()
 local u=ready(); assert(u.phase=='available' and u.release.version=='Beta 1.34' and Up.offered(u))
 assert(events(u):find('INFO mise a jour disponible: Beta 1.34 (publiee le 2026-11-05, 1000000 octets)',1,true))
 u=Up.new('Beta 1.34'); Up.check(u,port(),100); assert(u.phase=='current' and not Up.offered(u))
 u=Up.new('Beta 1.35'); Up.check(u,port(),100); assert(u.phase=='current')
 u=Up.new('Beta 1.33'); Up.check(u,port({apiStatus=404}),100); assert(u.phase=='none' and events(u):find('aucune version publiee',1,true))
 -- Limite de requêtes de GitHub : dite comme telle, la version n'est plus proposée.
 u=Up.new('Beta 1.33'); Up.check(u,port({apiStatus=403}),100); assert(u.phase=='failed' and u.error=='rate' and u.status==403 and events(u):find('limite de requetes) (statut 403)',1,true))
 u=Up.new('Beta 1.33'); Up.check(u,port({apiStatus=500}),100); assert(u.error=='network' and u.status==500)
 u=Up.new('Beta 1.33'); Up.check(u,port({apiErr='timeout'}),100); assert(u.phase=='failed' and u.error=='network' and events(u):find('echec reseau : timeout',1,true))
 u=Up.new('Beta 1.33'); Up.check(u,port({json=false}),100); assert(u.phase=='failed' and u.error=='format' and not Up.offered(u))
 -- Une vérification ou une installation en cours n'est jamais doublée ; au bouton, une vérification par minute au plus.
 u=Up.new('Beta 1.33'); u.phase='downloading'; assert(not Up.check(u,port(),100) and u.phase=='downloading')
 u=Up.new('Beta 1.33'); local p=port(); assert(Up.check(u,p,100) and not Up.check(u,p,100+Up.checkGap-1) and Up.check(u,p,100+Up.checkGap))
end
-- Beta 1.35 : vérification et téléchargement bornés dans le temps (réponse qui n'arrive jamais).
tests.UPDATE_TIMEOUTS=function()
 local u=Up.new('Beta 1.33'); local p=port(); p.hold=true
 Up.check(u,p,100); Up.tick(u,p,true,100+Up.checkTimeout-1); assert(u.phase=='checking')
 Up.tick(u,p,true,100+Up.checkTimeout+1); assert(u.phase=='failed' and u.error=='network' and not Up.busy(u))
 p.flush(); assert(u.phase=='failed','late answer ignored')
 u=Up.new('Beta 1.33'); p=port(); Up.check(u,p,0); p.hold=true; Up.tick(u,p,true,10)
 assert(Up.install(u,p,true) and u.phase=='downloading')
 Up.tick(u,p,true,10+Up.downloadTimeout+1); assert(u.phase=='failed' and u.error=='network' and events(u):find('telechargement non termine',1,true))
 p.flush(); assert(u.phase=='failed','late download ignored')
end
tests.UPDATE_INSTALL_ORDER=function()
 local u,p=ready({installed='Beta 1.33'})
 assert(Up.install(u,p,true) and u.phase=='ready')
 assert(not find(p.calls,'snapshot') and not find(p.calls,'mark update Beta 1.33 -> Beta 1.34'),'nothing copied before the next stopped frame')
 Up.tick(u,p,true,200)
 local ok,missing=ordered(p.calls,{'get '..u.release.sha.url,'get '..u.release.zip.url,'stage','snapshot','mark update Beta 1.33 -> Beta 1.34','place next','promote update','clear','report update Beta 1.33 -> Beta 1.34','boot Beta 1.34 0','restart'})
 assert(ok,missing)
 assert(p.snapSource=='next' and p.names and #p.names==#Up.required,'snapshot of the files the copy replaces')
 assert(u.phase=='restarting' and u.after=='update' and p.marked==nil and Up.view(u,true)=='done')
 local log=events(u)
 for _,line in ipairs({'telechargement de la Beta 1.34','Beta 1.34 prete, empreinte et contenu verifies','Beta 1.34 installee (5 fichiers compares, 3 copies en 2 ms ; 2 fichiers gardes en 1 ms), commandes des IA rendues a AC'}) do assert(log:find(line,1,true),line) end
 -- Version de départ lue dans le manifeste installé (pas seulement celle du module).
 u,p=ready({installed='Beta 1.33.1'}); Up.install(u,p,true); Up.tick(u,p,true,1); assert(find(p.calls,'mark update Beta 1.33.1 -> Beta 1.34'))
end
tests.UPDATE_READY_EXPIRES=function()
 -- Paquet prêt quand le pilote est reparti : copie reportée (jamais en roulant), paquet gardé, nouveau clic à l'arrêt.
 local u,p=ready({installed='Beta 1.33'})
 p.holdStage=true; Up.install(u,p,true); assert(u.phase=='staging')
 p.staged(); assert(u.phase=='ready' and Up.busy(u) and Up.view(u,false)=='ready')
 Up.tick(u,p,false,201); assert(u.phase=='available' and u.release.staged and not find(p.calls,'place next'))
 assert(events(u):find('copie reportee (pilote reparti)',1,true))
 -- Nouveau clic à l'arrêt : rien n'est retéléchargé ; copie à l'image suivante.
 local downloads=count(p.calls,'get '..u.release.zip.url)
 assert(Up.install(u,p,true) and u.phase=='ready' and count(p.calls,'get '..u.release.zip.url)==downloads)
 Up.tick(u,p,true,300); assert(u.phase=='restarting' and find(p.calls,'place next'))
 -- Paquet extrait abîmé entre-temps : téléchargé à nouveau.
 u,p=ready({installed='Beta 1.33',incomplete={next=true}}); Up.install(u,p,true); assert(u.phase=='failed' and u.error=='content')
 -- Annulée pendant l'attente : rien n'est copié.
 u,p=ready({installed='Beta 1.33'}); Up.install(u,p,true); assert(Up.cancel(u) and u.phase=='available')
 Up.tick(u,p,true,400); assert(not find(p.calls,'place next') and not find(p.calls,'mark update Beta 1.33 -> Beta 1.34'))
 assert(Up.cancelable.ready and Up.cancelable.downloading and not Up.cancelable.placing)
end
tests.UPDATE_INSTALL_GUARDS=function()
 -- En conduite : rien n'est téléchargé ; le refus est journalisé.
 local u,p=ready(); assert(not Up.install(u,p,false) and u.phase=='failed' and u.error=='driving' and not find(p.calls,'get '..u.release.zip.url))
 assert(events(u):find('INFO mise a jour: refusee en conduite',1,true) and Up.offered(u))
 -- Déjà à jour, ou aucune version connue : bouton sans effet.
 u=Up.new('Beta 1.34'); p=port(); Up.check(u,p,100); assert(not Up.install(u,p,true) and #p.calls==1)
 u=Up.new('Beta 1.33'); assert(not Up.install(u,port(),true))
 -- Chaque échec avant la copie finale laisse la version installée intacte (ni repère, ni copie dans l'app).
 local cases={{shaStatus=404,code='network'},{shaErr='timeout',code='network'},{shaText='bad',code='format',detail='empreinte'},{zipStatus=500,code='network'},
  {zipErr='reset',code='network'},{zipData='court',code='integrity',detail='taille 5 octets'},{hash=string.rep('cd',32),code='integrity',detail='SHA-256'},
  {entries={'apps/lua/Autre/x'},code='content'},{lua="require('src/absent')",code='content',detail='module absent : src/absent'},
  {manifest='VERSION=Beta 1.33',code='content'},{stageErr='disk',code='write'},{next=false,code='content'},{missing=true,code='content'},
  {incomplete={next=true},code='content'},{snapshotFails=true,code='write'}}
 for i,o in ipairs(cases) do
  u,p=ready(o); Up.take(u,{}); Up.install(u,p,true); Up.tick(u,p,true,500)
  assert(u.phase=='failed' and u.error==o.code,'case '..i..' '..tostring(u.error))
  if o.detail then assert(u.detail:find(o.detail,1,true),'case '..i..' detail '..u.detail) end
  assert(not find(p.calls,'place next') and not find(p.calls,'restart') and p.marked==nil,'case '..i)
  assert(events(u):find('version actuelle conservee',1,true),'case '..i)
 end
 -- Repère impossible à écrire (ou à relire) : rien n'est copié.
 u,p=ready({markFails=true}); Up.install(u,p,true); Up.tick(u,p,true,500); assert(u.error=='write' and not find(p.calls,'place next'))
end
tests.UPDATE_PLACE_FAILURE_RESTORES=function()
 -- Copie en échec : la version de départ (current) est remise en place aussitôt, repère levé, version conservée.
 local u,p=ready({installed='Beta 1.33',placeFails={next='src/ui.lua'}}); Up.install(u,p,true); Up.tick(u,p,true,500)
 assert(u.phase=='failed' and u.error=='write' and u.detail=='src/ui.lua' and p.marked==nil and not find(p.calls,'restart'))
 assert(ordered(p.calls,{'mark update Beta 1.33 -> Beta 1.34','place next','place current','clear'}))
 assert(not find(p.calls,'promote update') and not find(p.calls,'boot Beta 1.34 0'),'backup kept and no boot watch when the install failed')
 -- Remise en place impossible aussi : état terminal (plus aucune opération), repère gardé pour la reprise au lancement.
 u,p=ready({installed='Beta 1.33',placeFails={next='src/ui.lua',current='src/engine.lua'}}); Up.take(u,{}); Up.install(u,p,true); Up.tick(u,p,true,500)
 assert(u.phase=='broken' and u.brokenFile=='state/installing.txt' and p.marked~=nil and Up.view(u,true)=='broken' and Up.busy(u))
 assert(events(u):find('ERROR mise a jour: copie de src/ui.lua impossible, puis remise en place impossible (src/engine.lua)',1,true))
 assert(not Up.check(u,p,9999) and not Up.install(u,p,true) and not Up.rollback(u,p,true))
 -- Copie réussie mais sauvegarde non promue, repère non effacé : dit au journal, redémarrage quand même (reprise au
 -- lancement suivant : manifeste déjà à la version visée).
 u,p=ready({installed='Beta 1.33',promoteFails=true,clearFails=true}); Up.take(u,{}); Up.install(u,p,true); Up.tick(u,p,true,500)
 local log=events(u)
 assert(u.phase=='restarting' and log:find('retour arriere indisponible',1,true) and log:find('repere non efface',1,true))
end
tests.UPDATE_CANCEL=function()
 -- Annulation pendant le téléchargement : la réponse arrivée ensuite est ignorée, même après un nouveau clic.
 local u=Up.new('Beta 1.33'); local p=port(); Up.check(u,p,100)
 p.hold=true; Up.install(u,p,true); assert(u.phase=='downloading')
 assert(Up.cancel(u) and u.phase=='available')
 Up.install(u,p,true); assert(u.phase=='downloading')
 p.flush()
 -- Une seule chaîne a continué (le premier téléchargement est ignoré) : un seul « stage ».
 assert(count(p.calls,'stage')==1 and u.phase=='ready','one pipeline: '..count(p.calls,'stage'))
 assert(not Up.cancel(Up.new('x')))
end
tests.UPDATE_RECOVER=function()
 assert(Up.recover(port())==nil)
 -- Repère illisible : levé, rien copié.
 local p=port({marked='???'}); local r=Up.recover(p); assert(r.outcome=='cleared' and p.marked==nil and not find(p.calls,'place next'))
 -- Manifeste à la version visée : copie allée au bout ; sauvegarde promue, compte rendu.
 p=port({marked='update Beta 1.33 -> Beta 1.34',installed='Beta 1.34',current='Beta 1.33'})
 r=Up.recover(p); assert(r.outcome=='finished' and not r.restart and p.marked==nil and p.reported=='update Beta 1.33 -> Beta 1.34' and find(p.calls,'promote update') and not find(p.calls,'place next'))
 -- Manifeste encore à la version de départ, paquet extrait intact : la copie est refaite vers la version visée.
 p=port({marked='update Beta 1.33 -> Beta 1.34',installed='Beta 1.33',current='Beta 1.33'})
 r=Up.recover(p); assert(r.outcome=='completed' and r.restart and p.marked==nil and find(p.calls,'place next') and p.reported=='update Beta 1.33 -> Beta 1.34')
 -- Paquet absent ou incomplet : version de départ remise en place ; compte rendu « recovered ».
 for _,o in ipairs({{next=false},{incomplete={next=true}}}) do
  o.marked='update Beta 1.33 -> Beta 1.34'; o.installed='Beta 1.33'; o.current='Beta 1.33'
  p=port(o); r=Up.recover(p); assert(r.outcome=='restored' and r.restart and find(p.calls,'place current') and not find(p.calls,'place next') and p.reported=='recovered Beta 1.33 -> Beta 1.34')
 end
 -- Rien n'est possible : essai compté dans le repère, puis abandon au deuxième essai (jamais en boucle), noté.
 p=port({marked='update Beta 1.33 -> Beta 1.34',installed='Beta 1.33',next=false,current=false})
 r=Up.recover(p); assert(r.outcome=='failed' and p.marked:find('tries 1',1,true))
 r=Up.recover(p); assert(r.outcome=='failed' and p.marked:find('tries 2',1,true))
 r=Up.recover(p); assert(r.outcome=='gaveup' and not r.restart and p.marked==nil and p.note:find('installed Beta 1.33',1,true))
 -- Autre version installée (réinstallée à la main) : repère levé sans rien copier.
 p=port({marked='update Beta 1.33 -> Beta 1.34',installed='Beta 1.40'})
 r=Up.recover(p); assert(r.outcome=='cleared' and r.installed=='Beta 1.40' and p.marked==nil and not find(p.calls,'place current'))
 -- Retour arrière interrompu : refait vers la version précédente (backup).
 p=port({marked='rollback Beta 1.34 -> Beta 1.33',installed='Beta 1.34',backup='Beta 1.33',current='Beta 1.34'})
 r=Up.recover(p); assert(r.outcome=='completed' and find(p.calls,'place backup') and p.reported=='rollback Beta 1.34 -> Beta 1.33')
 -- Repère qui ne se réécrit pas (lecture seule) : rien n'est copié, aucun redémarrage (jamais en boucle).
 p=port({marked='update Beta 1.33 -> Beta 1.34',installed='Beta 1.33',current='Beta 1.33',markFails=true})
 r=Up.recover(p); assert(r.outcome=='failed' and not r.restart and not find(p.calls,'place next') and not find(p.calls,'place current'))
 -- Copie refaite mais repère impossible à effacer : aucun redémarrage (le lancement suivant trouve la version visée).
 p=port({marked='update Beta 1.33 -> Beta 1.34',installed='Beta 1.33',current='Beta 1.33',clearFails=true})
 r=Up.recover(p); assert(r.outcome=='failed' and not r.restart and r.failed=='repere')
 for _,o in ipairs({'cleared','finished','completed','restored','autorollback','bootfailed','gaveup','failed'}) do
  local level,text=Up.recoverText({outcome=o,kind='update',from='Beta 1.33',to='Beta 1.34',file='x'}); assert(level and text,o)
 end
 assert(Up.recoverText(nil)==nil and Up.recoverText({outcome='?'})==nil)
end
-- Beta 1.35 : démarrage surveillé : une version installée qui ne démarre pas deux fois de suite est défaite.
tests.UPDATE_BOOT_WATCH=function()
 -- Démarrage réussi : la surveillance s'arrête (bootOk côté port, voir le test du vrai port).
 local p=port({installed='Beta 1.34',backup='Beta 1.33',boot={'Beta 1.34',0,'Beta 1.33'}})
 assert(Up.recover(p)==nil and p.boots[2]==1)
 assert(Up.recover(p)==nil and p.boots[2]==2)
 local r=Up.recover(p)
 assert(r.outcome=='autorollback' and r.restart and r.auto and find(p.calls,'place backup') and p.marked==nil and p.boots==nil)
 assert(p.reported=='rollback Beta 1.34 -> Beta 1.33 auto')
 -- Compte rendu au lancement suivant : retour arrière automatique dit.
 local u=Up.new('Beta 1.33'); Up.start(u,p); assert(u.updated.kind=='rollback' and u.updated.auto and events(u):find('retour arriere termine (automatique)',1,true))
 -- Version précédente incomplète : rien n'est copié, l'app le dit.
 p=port({installed='Beta 1.34',backup='Beta 1.33',incomplete={backup=true},boot={'Beta 1.34',2,'Beta 1.33'}})
 r=Up.recover(p); assert(r.outcome=='bootfailed' and not r.restart and not find(p.calls,'place backup'))
 u=Up.new('Beta 1.34'); Up.start(u,p,r); assert(u.phase=='broken')
 -- Surveillance d'une autre version (réinstallée à la main) : oubliée.
 p=port({installed='Beta 1.40',boot={'Beta 1.34',1,'Beta 1.33'}}); assert(Up.recover(p)==nil and p.boots==nil)
end
tests.UPDATE_START_REPORTS=function()
 local u=Up.new('Beta 1.34'); local p=port({report='update Beta 1.33 -> Beta 1.34',backup='Beta 1.33'})
 Up.start(u,p); assert(u.updated.kind=='update' and u.updated.from=='Beta 1.33' and u.previous=='Beta 1.33' and Up.view(u,true)=='success')
 assert(events(u):find('mise a jour reussie: Beta 1.33 -> Beta 1.34',1,true))
 -- Compte rendu lu une seule fois.
 local again=Up.new('Beta 1.34'); Up.start(again,p); assert(again.updated==nil)
 -- Sauvegarde de la version installée elle-même, ou incomplète : rien à proposer.
 u=Up.new('Beta 1.33'); Up.start(u,port({backup='Beta 1.33'})); assert(u.previous==nil)
 u=Up.new('Beta 1.34'); Up.start(u,port({backup='Beta 1.33',incomplete={backup=true}})); assert(u.previous==nil)
 -- Reprise faite au chargement : dite au journal ; impossible : état terminal.
 u=Up.new('Beta 1.34'); Up.start(u,port(),{outcome='completed',kind='update',from='Beta 1.33',to='Beta 1.34'}); assert(events(u):find('copie reprise au lancement, installation termine',1,true))
 -- Fichiers copiés au chargement : un redémarrage, à la première image ; compte rendu laissé au lancement suivant.
 local rp=port({report='update Beta 1.33 -> Beta 1.34'})
 u=Up.new('Beta 1.34'); Up.start(u,rp,{outcome='completed',kind='update',from='Beta 1.33',to='Beta 1.34',restart=true})
 assert(u.phase=='restarting' and u.restartPending and u.updated==nil and rp.reported=='update Beta 1.33 -> Beta 1.34' and Up.busy(u))
 Up.tick(u,rp,false,1); Up.tick(u,rp,false,2)
 assert(count(rp.calls,'restart')==1 and not u.restartPending,'one restart')
 -- Reprise sans copie (terminée, repère levé, abandon) : jamais de redémarrage.
 for _,o in ipairs({'finished','cleared','gaveup'}) do local q=port(); local w=Up.new('Beta 1.34'); Up.start(w,q,{outcome=o,kind='update',from='Beta 1.33',to='Beta 1.34',file='x'}); Up.tick(w,q,true,1); assert(not find(q.calls,'restart'),o) end
 u=Up.new('Beta 1.33'); Up.start(u,port(),{outcome='restored',kind='update',from='Beta 1.33',to='Beta 1.34'}); assert(events(u):find('Beta 1.33 remise en place au lancement',1,true))
 u=Up.new('Beta 1.33'); Up.start(u,port(),{outcome='gaveup',kind='update',from='Beta 1.33',to='Beta 1.34',file='state/installing.txt'})
 assert(u.phase=='broken' and u.brokenFile=='state/installing.txt' and events(u):find('ERROR mise a jour: reprise abandonnee',1,true))
 -- Abandon d'une reprise rappelé tant que la même version reste installée ; oublié après une réinstallation.
 local fp=port({failed='update Beta 1.33 -> Beta 1.34\ninstalled Beta 1.33'})
 u=Up.new('Beta 1.33'); Up.start(u,fp); assert(u.warning and events(u):find('une reprise a echoue',1,true) and fp.note~=nil)
 u=Up.new('Beta 1.35'); Up.start(u,fp); assert(u.warning==nil and fp.note==nil)
end
tests.UPDATE_ROLLBACK=function()
 local u=Up.new('Beta 1.34'); local p=port({backup='Beta 1.33',installed='Beta 1.34'}); Up.start(u,p)
 assert(not Up.rollback(u,p,false) and u.error=='driving' and not find(p.calls,'place backup'))
 u=Up.new('Beta 1.34'); p=port({backup='Beta 1.33',installed='Beta 1.34'}); Up.start(u,p)
 -- Demandé au clic, copié à l'image suivante, toujours à l'arrêt (hors du dessin de la fenêtre).
 assert(Up.rollback(u,p,true) and u.phase=='rollbackReady' and Up.busy(u) and not find(p.calls,'place backup'))
 Up.tick(u,p,true,50)
 assert(u.phase=='restarting' and u.after=='rollback' and Up.view(u,true)=='rolledback')
 assert(ordered(p.calls,{'snapshot','mark rollback Beta 1.34 -> Beta 1.33','place backup','promote rollback','clear','report rollback Beta 1.34 -> Beta 1.33','boot clear','restart'}))
 assert(p.snapSource=='backup')
 -- Pilote reparti avant l'image suivante : retour arrière annulé.
 u=Up.new('Beta 1.34'); p=port({backup='Beta 1.33',installed='Beta 1.34'}); Up.start(u,p); Up.rollback(u,p,true); Up.tick(u,p,false,50)
 assert(u.phase=='idle' and not find(p.calls,'place backup'))
 -- Retour en échec : version installée remise en place aussitôt.
 u=Up.new('Beta 1.34'); p=port({backup='Beta 1.33',installed='Beta 1.34',placeFails={backup='src/ui.lua'}}); Up.start(u,p)
 Up.rollback(u,p,true); Up.tick(u,p,true,50); assert(u.phase=='failed' and u.error=='write' and find(p.calls,'place current') and p.marked==nil and not find(p.calls,'restart'))
 -- Version précédente devenue incomplète : refusé sans rien copier.
 u=Up.new('Beta 1.34'); local o={backup='Beta 1.33',installed='Beta 1.34'}; p=port(o); Up.start(u,p); o.incomplete={backup=true}
 assert(not Up.rollback(u,p,true) and u.error=='write' and not find(p.calls,'snapshot'))
 -- Sans version précédente : bouton sans effet.
 u=Up.new('Beta 1.34'); p=port(); Up.start(u,p); assert(not Up.rollback(u,p,true) and #p.calls==0)
end
tests.UPDATE_VIEW_STATES=function()
 local V=Up.view
 local u=Up.new('Beta 1.33'); assert(V(u,true)=='unchecked')
 local p=port(); Up.check(u,p,100); assert(V(u,true)=='available' and V(u,false)=='driving')
 u=Up.new('Beta 1.33'); p=port(); Up.check(u,p,100); Up.install(u,p,false); assert(V(u,false)=='driving' and V(u,true)=='available')
 -- Retour arrière refusé en conduite sans version publiée connue : jamais « un clic installe la mise à jour ».
 u=Up.new('Beta 1.34'); p=port({backup='Beta 1.33'}); Up.start(u,p); Up.rollback(u,p,false); assert(V(u,true)=='driving')
 u=Up.new('Beta 1.34'); Up.check(u,port(),100); assert(V(u,true)=='uptodate')
 u=Up.new('Beta 1.33'); Up.check(u,port({apiStatus=404}),100); assert(V(u,true)=='none')
 for err,view in pairs({network='errNet',rate='errRate',format='errFormat',integrity='errHash',content='errHash',write='errWrite'}) do
  u=Up.new('Beta 1.33'); u.phase='failed'; u.error=err; assert(V(u,true)==view,err)
 end
 for phase,view in pairs({checking='checking',downloading='downloading',verifying='verifying',staging='installing',saving='installing',placing='installing',ready='ready',rollbackReady='installing',broken='broken'}) do
  u=Up.new('Beta 1.33'); u.phase=phase; assert(V(u,true)==view,phase)
 end
 -- Après le redémarrage : compte rendu affiché même si la vérification du lancement a déjà répondu.
 for report,view in pairs({['update Beta 1.33 -> Beta 1.34']='success',['rollback Beta 1.34 -> Beta 1.33']='rolledback',['recovered Beta 1.33 -> Beta 1.34']='interrupted'}) do
  u=Up.new('Beta 1.34'); p=port({report=report}); Up.start(u,p); assert(V(u,true)==view,report)
  Up.check(u,p,100); assert(V(u,true)==view,report)
 end
 u=Up.new('Beta 1.34'); Up.start(u,port({report='n importe quoi'})); assert(u.updated==nil and V(u,true)=='unchecked')
end
tests.UPDATE_RESTART_LATE=function()
 local u,p=ready({installed='Beta 1.33'}); Up.install(u,p,true); Up.tick(u,p,true,1000); Up.take(u,{})
 assert(u.phase=='restarting' and not u.restartLate)
 Up.tick(u,p,true,1000+Up.restartWait-1); assert(not u.restartLate)
 Up.tick(u,p,true,1000+Up.restartWait+1); assert(u.restartLate and events(u):find("l app n a pas redemarre",1,true))
end
tests.UPDATE_EVENTS_BOUNDED=function()
 local u=Up.new('Beta 1.33')
 for _=1,Up.eventsMax+10 do u.phase='downloading'; Up.cancel(u) end
 local out=Up.take(u,{}); assert(#out==Up.eventsMax and #u.events==0 and out[1][2]=='mise a jour: annulee avant toute copie')
end
-- Vrai port sans CSP (bancs de mesure, tests sans imitation) : inerte, rien n'est demandé, lu ni écrit.
tests.UPDATE_REMOTE_INERT=function()
 assert(rawget(_G,'web')==nil)
 local released=0; local p=Remote.new(function() released=released+1 end)
 assert(p.ready==false and p.marker()==nil and p.sourceVersion('backup')==nil and p.installedVersion()==nil and p.takeReport()==nil and p.mark('x')==false)
 assert(p.sourceComplete('backup')==false and p.boot()==nil and p.failed()==nil)
 local err; p.get('https://x',nil,function(e) err=e end); assert(err=='unavailable')
 local e2; p.stage('data',{},function(e) e2=e end); assert(e2=='unavailable')
 assert(p.snapshot('next')==false and p.place('next')==false)
 p.restart(); assert(released==1)
 p.log('x'); p.bootOk()
 local u=Up.new('Beta 1.33'); assert(Up.recover(p)==nil); Up.start(u,p,nil); assert(u.phase=='idle' and #u.events==0)
 -- Toutes les fonctions de CSP sauf web et JSON (ancien CSP) : inerte aussi, sans erreur.
 local f=Fake.install({})
 local ok,msg=pcall(function()
  rawset(_G,'web',nil); rawset(_G,'JSON',nil)
  local q=Remote.new(function() end); assert(q.app==f.root and q.ready==false and q.marker()==nil and q.sourceVersion('backup')==nil)
 end)
 f.restore(); assert(ok,msg)
end
-- Lance une installation complète sur l'imitation de CSP ; setup(f) avant, body(f,p,u) après.
local function onFake(options,setup,body)
 local f=Fake.install({})
 local ok,err=pcall(function()
  f.app('Beta 1.33',{['tracks/spa.lua']='zones',['backup/old.txt']='old'}); f.release('Beta 1.34',options)
  if setup then setup(f) end
  local order={}; f.order=order
  f.onRestart=function() order[#order+1]='restartApp' end
  local p=Remote.new(function() order[#order+1]='release' end)
  local u=Up.new('Beta 1.33'); Up.start(u,p,Up.recover(p))
  body(f,p,u)
 end)
 f.restore(); assert(ok,err)
end
-- Installation de bout en bout (rappels asynchrones différés, téléchargement redirigé, corps binaire) : dossier de
-- travail hors de l'app, copie des fichiers remplacés, copie finale fichier par fichier d'un seul coup (manifeste en
-- dernier), aucun rechargement en direct ; puis démarrage surveillé et retour arrière.
tests.UPDATE_REMOTE_END_TO_END=function()
 onFake(nil,function(f)
  f.async=true
  -- Version précédente plus ancienne déjà gardée : remplacée d'un bloc, rien n'en reste.
  f.files[f.work..'/backup/AdvancedIA.lua']='main Beta 1.32'; f.files[f.work..'/backup/manifest.ini']='VERSION=Beta 1.32'
  f.files[f.work..'/backup/.files']='AdvancedIA.lua\nmanifest.ini'
 end,function(f,p,u)
  assert(p.ready and p.app==f.root and p.installedVersion()=='Beta 1.33' and p.work==f.work and u.previous=='Beta 1.32')
  Up.check(u,p,0); f.flush(); assert(u.phase=='available' and u.release.notes[3]=='- Nouveau point')
  f.watch(); assert(Up.install(u,p,true)); f.flush()
  assert(u.phase=='ready','install: '..tostring(u.phase)..' '..tostring(u.error)..' '..tostring(u.detail))
  assert(f.find('redirect https://release-assets.githubusercontent.com/AdvancedIA-Beta-1.34.zip'),'download redirected')
  local files=f.files
  -- Rien n'a encore changé dans le dossier de l'app ; paquet extrait, comparé et listé dans le travail.
  assert(files[f.root..'/AdvancedIA.lua']=='main Beta 1.33' and f.reloads==0)
  assert(files[f.work..'/next/'..Fake.prefix..'AdvancedIA.lua']=='main Beta 1.34' and files[f.work..'/next/'..Fake.prefix..'.files']:find('src/new.lua',1,true))
  assert(files[f.work..'/current/AdvancedIA.lua']==nil,'nothing saved before the final copy')
  Up.tick(u,p,true,10)
  assert(u.phase=='restarting','tick: '..tostring(u.phase)..' '..tostring(u.detail))
  -- Sauvegarde : seulement les fichiers que la copie remplace (jamais le reste du dossier de l'app).
  assert(files[f.work..'/backup/AdvancedIA.lua']=='main Beta 1.33' and files[f.work..'/backup/tracks/spa.lua']==nil and files[f.work..'/backup/backup/old.txt']==nil)
  -- Copie finale : fichiers changés, nouveau fichier, identiques jamais réécrits, manifeste en dernier, aucun rechargement,
  -- chaque fichier copié à côté puis mis en place, surveillance rétablie à la fin.
  assert(files[f.root..'/AdvancedIA.lua']=='main Beta 1.34' and files[f.root..'/src/ui.lua']=='ui Beta 1.34' and files[f.root..'/src/new.lua']=='new Beta 1.34')
  assert(files[f.root..'/sounds/beep.wav']=='wav' and not f.find('copy sounds/beep.wav.new') and files[f.root..'/tracks/spa.lua']=='zones')
  assert(f.last('move ')==f.find('move manifest.ini') and f.find('move src/ui.lua')<f.find('move AdvancedIA.lua') and Up.manifestVersion(files[f.root..'/manifest.ini'])=='Beta 1.34')
  assert(files[f.root..'/src/ui.lua.new']==nil and files[f.root..'/manifest.ini.new']==nil,'no temporary file left')
  assert(f.reloads==0,'live reloads: '..f.reloads)
  assert(f.last('pause ')==f.last('pause false') and f.last('pause false')>f.find('move manifest.ini'),'file watching resumed after the copy')
  -- Version précédente promue d'un bloc, repère levé, compte rendu écrit, démarrage surveillé ; IA rendues puis redémarrage.
  assert(f.find('movedir state:AdvancedIA-update/backup'),'promoted by renaming the folder')
  for path in pairs(files) do assert(not path:find('/backup.old/',1,true),'older backup cleared: '..path) end
  assert(files[f.work..'/installing.txt']==nil and files[f.work..'/updated.txt']=='update Beta 1.33 -> Beta 1.34' and files[f.work..'/boot.txt']=='Beta 1.34\n0\nBeta 1.33')
  assert(f.order[1]=='release' and f.order[2]=='restartApp' and #f.order==2 and f.restarts==1)
  -- Lancement suivant : compte rendu, version précédente proposée, première image : surveillance levée ; retour arrière.
  local p2=Remote.new(function() end)
  local u2=Up.new('Beta 1.34'); Up.start(u2,p2,Up.recover(p2)); assert(u2.updated.kind=='update' and u2.previous=='Beta 1.33' and files[f.work..'/updated.txt']==nil)
  assert(files[f.work..'/boot.txt']=='Beta 1.34\n1\nBeta 1.33','boot counted'); p2.bootOk(); assert(files[f.work..'/boot.txt']==nil,'boot confirmed')
  f.watch(); assert(Up.rollback(u2,p2,true) and u2.phase=='rollbackReady'); Up.tick(u2,p2,true,0); assert(u2.phase=='restarting')
  assert(files[f.root..'/AdvancedIA.lua']=='main Beta 1.33' and Up.manifestVersion(files[f.root..'/manifest.ini'])=='Beta 1.33' and f.reloads==0)
  assert(files[f.work..'/updated.txt']=='rollback Beta 1.34 -> Beta 1.33' and files[f.work..'/installing.txt']==nil and f.restarts==2)
  -- Page de la version : seulement une adresse https.
  p.open(u.release.page); p.open('file:///c:/x'); assert(#f.opened==1 and f.opened[1]==u.release.page)
 end)
end
-- Démarrage surveillé par le vrai port : deux lancements sans première image, puis retour automatique à la version
-- précédente au troisième, avant tout autre module.
tests.UPDATE_REMOTE_BOOT_WATCH=function()
 onFake(nil,nil,function(f,p,u)
  Up.check(u,p,0); Up.install(u,p,true); Up.tick(u,p,true,1); assert(u.phase=='restarting')
  local files=f.files
  for launch=1,2 do local q=Remote.new(function() end); assert(Up.recover(q)==nil,'launch '..launch) end
  assert(files[f.work..'/boot.txt']=='Beta 1.34\n2\nBeta 1.33')
  local q=Remote.new(function() end); local r=Up.recover(q)
  assert(r and r.outcome=='autorollback' and r.restart and Up.manifestVersion(files[f.root..'/manifest.ini'])=='Beta 1.33' and files[f.root..'/AdvancedIA.lua']=='main Beta 1.33')
  assert(files[f.work..'/boot.txt']==nil and files[f.work..'/installing.txt']==nil and files[f.work..'/updated.txt']=='rollback Beta 1.34 -> Beta 1.33 auto')
 end)
end
-- Échecs du vrai port : la version installée reste intacte (ou remise en place aussitôt), sans repère qui traîne.
tests.UPDATE_REMOTE_FAILURES=function()
 local function intact(f) local files=f.files; return files[f.root..'/AdvancedIA.lua']=='main Beta 1.33' and files[f.root..'/src/ui.lua']=='ui Beta 1.33' and Up.manifestVersion(files[f.root..'/manifest.ini'])=='Beta 1.33' and files[f.work..'/installing.txt']==nil end
 local function run(options,setup,check)
  onFake(options,setup,function(f,p,u) Up.check(u,p,0); f.flush(); Up.install(u,p,true); f.flush(); Up.tick(u,p,true,10); check(f,u) end)
 end
 run({actual=string.rep('cd',32)},nil,function(f,u) assert(u.error=='integrity' and intact(f) and f.files[f.work..'/current/AdvancedIA.lua']==nil) end)
 run({size=999},nil,function(f,u) assert(u.error=='integrity' and u.detail:find('taille',1,true) and intact(f)) end)
 run({entries={['apps/lua/AdvancedIA/../../evil.lua']='x'}},nil,function(f,u) assert(u.error=='content' and intact(f)) end)
 run({entries={[Fake.prefix..'src/remote.lua']=false}},nil,function(f,u) assert(u.error=='content' and intact(f)) end)
 run({entries={[Fake.prefix..'src/ui.lua']="local G=require('src/groups')"}},nil,function(f,u) assert(u.error=='content' and u.detail=='module absent : src/groups' and intact(f)) end)
 run(nil,function(f) f.corruptExtract=Fake.prefix..'src/ui.lua' end,function(f,u) assert(u.error=='write' and u.detail:find('different du paquet : src/ui.lua',1,true) and intact(f)) end)
 run(nil,function(f) f.failExtract=true end,function(f,u) assert(u.error=='write' and u.detail:find('extraction',1,true) and intact(f) and f.restarts==0) end)
 run(nil,function(f) f.failCopy=f.work..'/current/src/ui.lua' end,function(f,u) assert(u.error=='write' and u.detail=='sauvegarde : src/ui.lua' and intact(f)) end)
 -- Fichier de l'app ouvert (verrouillé) pendant la copie finale : remise en place aussitôt, version conservée, aucun
 -- fichier temporaire laissé.
 run(nil,function(f) f.locked[f.root..'/src/ui.lua']=true end,function(f,u)
  assert(u.error=='write' and u.detail=='src/ui.lua' and f.files[f.root..'/AdvancedIA.lua']=='main Beta 1.33' and Up.manifestVersion(f.files[f.root..'/manifest.ini'])=='Beta 1.33',
   'locked: '..u.phase..' '..u.error..' '..u.detail..' '..tostring(f.files[f.root..'/AdvancedIA.lua']))
  assert(f.files[f.work..'/installing.txt']==nil,'marker'); assert(f.restarts==0,'restarts')
  assert(f.files[f.work..'/backup/AdvancedIA.lua']==nil,'backup'); assert(f.files[f.root..'/src/ui.lua.new']==nil,'tmp')
 end)
 -- Fichier de l'app illisible (copie de sauvegarde refusée) : rien n'est copié dans l'app.
 run(nil,function(f) f.unreadable[f.root..'/src/ui.lua']=true end,function(f,u) assert(u.error=='write' and u.detail=='sauvegarde : src/ui.lua' and intact(f)) end)
 -- Fichier en lecture seule dans l'app : refusé de même.
 run(nil,function(f) f.readonly[f.root..'/src/remote.lua']=true end,function(f,u) assert(u.error=='write' and u.detail=='src/remote.lua' and intact(f)) end)
 -- Repère en lecture seule (ni réécrit ni effacé) : rien n'est copié dans l'app.
 run(nil,function(f) f.readonly[f.work..'/installing.txt']=true end,function(f,u) assert(u.error=='write' and u.detail=='repere' and intact(f)) end)
 -- Surveillance de CSP qui reprend seule pendant une longue copie : réaffirmée, aucun rechargement.
 run(nil,function(f) f.watch(); f.autoResume=6 end,function(f,u) assert(u.phase=='restarting' and f.reloads==0,'reloads '..f.reloads..' '..tostring(u.detail)) end)
 -- Renommage de dossier refusé : version précédente gardée par copie vérifiée.
 run(nil,function(f) f.failDirMove=true end,function(f,u) assert(u.phase=='restarting' and f.files[f.work..'/backup/AdvancedIA.lua']=='main Beta 1.33' and f.files[f.work..'/current/AdvancedIA.lua']==nil) end)
end
-- Reprise au chargement par le vrai port : copie interrompue (fichiers mêlés, manifeste encore ancien) terminée depuis
-- le paquet extrait ; sans lui, version de départ remise en place ; rien à reprendre ensuite. Promotion rejouée sans
-- dégât. Restes de la Beta 1.33/1.34.
tests.UPDATE_REMOTE_RECOVERY=function()
 local function source(f,root,map) local names={}; for k,val in pairs(map) do f.files[root..'/'..k]=val; names[#names+1]=k end; f.files[root..'/.files']=table.concat(names,'\n') end
 onFake(nil,nil,function(f,p)
  local files=f.files
  source(f,f.work..'/next/'..Fake.prefix:gsub('/$',''),{['manifest.ini']='VERSION=Beta 1.34',['AdvancedIA.lua']='main Beta 1.34',['src/update.lua']='update Beta 1.34',['src/remote.lua']='remote Beta 1.34',['src/ui.lua']='ui Beta 1.34'})
  source(f,f.work..'/current',{['manifest.ini']='VERSION=Beta 1.33',['AdvancedIA.lua']='main Beta 1.33',['src/ui.lua']='ui Beta 1.33'})
  files[f.root..'/src/ui.lua']='ui Beta 1.34'; files[f.work..'/installing.txt']='update Beta 1.33 -> Beta 1.34'
  -- Coupure au milieu d'un remplacement : fichier temporaire à moitié écrit, jamais pris pour le vrai.
  files[f.root..'/src/remote.lua.new']='remo'
  local r=Up.recover(p)
  assert(r.outcome=='completed' and files[f.root..'/AdvancedIA.lua']=='main Beta 1.34' and Up.manifestVersion(files[f.root..'/manifest.ini'])=='Beta 1.34')
  assert(files[f.root..'/src/remote.lua']=='remote Beta 1.34' and files[f.root..'/src/remote.lua.new']==nil)
  assert(files[f.work..'/installing.txt']==nil and files[f.work..'/updated.txt']=='update Beta 1.33 -> Beta 1.34' and files[f.work..'/backup/AdvancedIA.lua']=='main Beta 1.33')
  assert(Up.recover(p)==nil,'nothing left to recover')
  -- Promotion rejouée (plantage juste après elle) : version précédente intacte.
  assert(p.promote('update') and files[f.work..'/backup/AdvancedIA.lua']=='main Beta 1.33' and p.sourceComplete('backup'))
 end)
 onFake(nil,nil,function(f,p)
  local files=f.files
  source(f,f.work..'/current',{['manifest.ini']='VERSION=Beta 1.33',['AdvancedIA.lua']='main Beta 1.33',['src/ui.lua']='ui Beta 1.33'})
  files[f.root..'/src/ui.lua']='ui Beta 1.34'; files[f.work..'/installing.txt']='update Beta 1.33 -> Beta 1.34'
  local r=Up.recover(p)
  assert(r.outcome=='restored' and files[f.root..'/src/ui.lua']=='ui Beta 1.33' and files[f.work..'/updated.txt']=='recovered Beta 1.33 -> Beta 1.34')
 end)
 -- Version précédente incomplète (un fichier manquant) : jamais proposée ni utilisée.
 onFake(nil,function(f)
  local names={}; for k,val in pairs({['manifest.ini']='VERSION=Beta 1.32',['AdvancedIA.lua']='main Beta 1.32'}) do f.files[f.work..'/backup/'..k]=val; names[#names+1]=k end
  names[#names+1]='src/ui.lua'; f.files[f.work..'/backup/.files']=table.concat(names,'\n')
 end,function(_,p,u) assert(u.previous==nil and not p.sourceComplete('backup') and not Up.rollback(u,p,true)) end)
 -- Beta 1.52 : restes de l'ancien module (Beta 1.33/1.34, dossier backup/ de l'app) plus lus : ces versions
 -- s'appelaient ACAdvancedIA (apps/lua/ACAdvancedIA), le dossier de l'app AdvancedIA ne les a jamais contenus (code
 -- mort retiré, relecture 1.52) ; un fichier de ce nom n'est ni pris pour un compte rendu ni effacé.
 onFake(nil,function(f)
  f.files[f.root..'/backup/updated.txt']='update Beta 1.32 -> Beta 1.33'; f.files[f.root..'/backup/installing.txt']='update Beta 1.32 -> Beta 1.33'
 end,function(f,_,u)
  assert(u.updated==nil and f.files[f.root..'/backup/updated.txt']~=nil and f.files[f.root..'/backup/installing.txt']~=nil)
 end)
end
-- Beta 1.36 (3e relecture) : dossiers vides effacés avec leurs fichiers ; trois mises à jour de suite, la version
-- précédente est chaque fois renommée d'un bloc (jamais la copie de repli).
tests.UPDATE_REMOTE_REPEATED_136=function()
 local f=Fake.install({})
 local ok,err=pcall(function()
  f.app('Beta 1.33')
  for round,v in ipairs({'Beta 1.34','Beta 1.35','Beta 1.36'}) do
   f.release(v)
   local installed=Up.manifestVersion(f.files[f.root..'/manifest.ini'])
   local p=Remote.new(function() end)
   local u=Up.new(installed); Up.start(u,p,Up.recover(p)); p.bootOk()
   Up.check(u,p,0); f.flush(); assert(u.phase=='available','round '..round..': '..tostring(u.phase))
   f.watch(); assert(Up.install(u,p,true)); f.flush(); assert(u.phase=='ready','round '..round..' install: '..tostring(u.phase)..' '..tostring(u.detail))
   local before=#f.calls
   Up.tick(u,p,true,10); assert(u.phase=='restarting','round '..round..' tick: '..tostring(u.phase)..' '..tostring(u.detail))
   local renamed,copied=false,false
   for k=before+1,#f.calls do
    local c=f.calls[k]
    if c=='movedir state:AdvancedIA-update/backup' then renamed=true end
    if c:find('^copy state:AdvancedIA%-update/backup/') then copied=true end
   end
   assert(renamed and not copied,'round '..round..': previous version renamed in one go, never copied')
   assert(Up.manifestVersion(f.files[f.root..'/manifest.ini'])==v,'round '..round..': installed '..v)
   for path in pairs(f.dirs) do assert(not path:find('/backup.old',1,true),'round '..round..': backup.old left: '..path) end
  end
 end)
 f.restore(); assert(ok,err)
end
-- Beta 1.36 : copie finie (ou refaite) par la reprise du lancement : version installée surveillée à son démarrage.
tests.UPDATE_RECOVER_BOOT_136=function()
 local p=port({marked='update Beta 1.33 -> Beta 1.34',installed='Beta 1.34'})
 local r=Up.recover(p); assert(r.outcome=='finished' and p.boots and p.boots[1]=='Beta 1.34' and p.boots[2]==1 and p.boots[3]=='Beta 1.33','finished: watched, this launch counted')
 p=port({marked='update Beta 1.33 -> Beta 1.34',installed='Beta 1.33'})
 r=Up.recover(p); assert(r.outcome=='completed' and r.restart and p.boots and p.boots[1]=='Beta 1.34' and p.boots[2]==0,'completed: watched from its first start')
 p=port({marked='rollback Beta 1.34 -> Beta 1.33',installed='Beta 1.33',boot={'Beta 1.34',1,'Beta 1.33'}})
 r=Up.recover(p); assert(r.outcome=='finished' and p.boots==nil,'rollback finished: watch cleared')
end
-- Beta 1.37 : état réel du disque du pilote après la mise à jour 1.35 -> 1.36 (version précédente gardée, paquet extrait
-- jamais effacé, boot.txt.bak) : nettoyé au lancement suivant ; la version précédente reste entière.
tests.UPDATE_TIDY_USER_STATE_137=function()
 local f=Fake.install({})
 local ok,err=pcall(function()
  f.app('Beta 1.36')
  local W=f.work
  local back={'AdvancedIA.lua','manifest.ini','src/update.lua'}
  for _,rel in ipairs(back) do f.files[W..'/backup/'..rel]=rel=='manifest.ini' and 'VERSION=Beta 1.35' or 'old '..rel end
  f.files[W..'/backup/.files']=table.concat(back,'\n')
  local nxt=W..'/next/'..Fake.prefix
  for _,rel in ipairs({'AdvancedIA.lua','manifest.ini','src/update.lua','src/remote.lua','src/ui.lua'}) do f.files[nxt..rel]='new '..rel end
  f.files[nxt..'.files']='AdvancedIA.lua\nmanifest.ini\nsrc/update.lua\nsrc/remote.lua\nsrc/ui.lua'
  f.files[W..'/boot.txt.bak']='Beta 1.36\n0\nBeta 1.35'
  local p=Remote.new(function() end)
  local u=Up.new('Beta 1.36'); Up.start(u,p,Up.recover(p))
  for path in pairs(f.files) do assert(not path:find(W..'/next',1,true) and path~=W..'/boot.txt.bak','left: '..path) end
  for path in pairs(f.dirs) do assert(not path:find(W..'/next',1,true),'folder left: '..path) end
  for _,rel in ipairs(back) do assert(f.files[W..'/backup/'..rel],'previous version kept: '..rel) end
  assert(u.previous=='Beta 1.35','rollback still offered')
  assert(events(u):find('mise a jour: nettoyage (7 fichiers)',1,true),events(u))
  local u2=Up.new('Beta 1.36'); Up.start(u2,p,Up.recover(p)); assert(not events(u2):find('nettoyage',1,true),'nothing left to clean')
  -- Démarrage surveillé ou repère en cours : rien n'est effacé.
  f.files[W..'/next/x']='x'; f.files[W..'/boot.txt']='Beta 1.36\n1\nBeta 1.35'
  assert(Up.tidy(Up.new('Beta 1.36'),p)==0 and f.files[W..'/next/x'],'boot watched: nothing removed')
  f.files[W..'/boot.txt']=nil; f.files[W..'/installing.txt']='update Beta 1.35 -> Beta 1.36'
  assert(Up.tidy(Up.new('Beta 1.36'),p)==0 and f.files[W..'/next/x'],'marker pending: nothing removed')
  -- Version précédente incomplète : la copie current/ peut en être la seule trace, gardée ; complète : effacée.
  f.files[W..'/installing.txt']=nil; f.files[W..'/current/a.lua']='a'; f.files[W..'/current/.files']='a.lua'
  local kept=f.files[W..'/backup/src/update.lua']; f.files[W..'/backup/src/update.lua']=nil
  Up.tidy(Up.new('Beta 1.36'),p); assert(f.files[W..'/current/a.lua'] and not f.files[W..'/next/x'],'backup incomplete: current kept, next removed')
  f.files[W..'/backup/src/update.lua']=kept
  Up.tidy(Up.new('Beta 1.36'),p); assert(not f.files[W..'/current/a.lua'] and f.files[W..'/backup/src/update.lua'],'backup complete: current removed')
 end)
 f.restore(); assert(ok,err)
end
-- Beta 1.37 : mises à jour successives par le vrai port : rien d'autre que la version précédente ne reste ; aucun .bak,
-- même juste après le lancement qui compte le démarrage (boot.txt réécrit).
tests.UPDATE_NO_LEFTOVERS_137=function()
 local f=Fake.install({})
 local ok,err=pcall(function()
  f.app('Beta 1.34')
  for round,v in ipairs({'Beta 1.35','Beta 1.36','Beta 1.37'}) do
   f.release(v)
   local installed=Up.manifestVersion(f.files[f.root..'/manifest.ini'])
   local p=Remote.new(function() end)
   local u=Up.new(installed); Up.start(u,p,Up.recover(p)); p.bootOk(); Up.tidy(u,p)
   Up.check(u,p,0); f.flush(); f.watch(); assert(Up.install(u,p,true)); f.flush(); Up.tick(u,p,true,10)
   assert(u.phase=='restarting','round '..round..': '..tostring(u.phase)..' '..tostring(u.detail))
   local p2=Remote.new(function() end); local u2=Up.new(v); Up.start(u2,p2,Up.recover(p2))
   assert(f.files[f.work..'/boot.txt'] and not f.files[f.work..'/boot.txt.bak'],'round '..round..': boot counted, no .bak')
   p2.bootOk(); Up.tidy(u2,p2)
   for path in pairs(f.files) do
    if path:sub(1,#f.work)==f.work then
     local rest=path:sub(#f.work+2)
     assert(rest:sub(1,7)=='backup/' and not rest:find('%.bak$') and not rest:find('%.new$'),'round '..round..' left: '..rest)
    end
   end
   for path in pairs(f.dirs) do assert(not path:find('/next',1,true) and not path:find('/current',1,true) and not path:find('backup.old',1,true),'round '..round..' folder left: '..path) end
  end
 end)
 f.restore(); assert(ok,err)
end
-- Beta 1.37 : la copie de la version installée ne garde que les fichiers que la mise à jour remplace (le manifeste
-- toujours) ; les fichiers identiques ne sont ni copiés ni gardés.
tests.UPDATE_SNAPSHOT_CHANGED_137=function()
 local f=Fake.install({})
 local ok,err=pcall(function()
  f.app('Beta 1.36'); f.release('Beta 1.37')
  local p=Remote.new(function() end); local u=Up.new('Beta 1.36'); Up.start(u,p,Up.recover(p))
  Up.check(u,p,0); f.flush(); f.watch(); assert(Up.install(u,p,true)); f.flush()
  local before=#f.calls; Up.tick(u,p,true,10); assert(u.phase=='restarting',tostring(u.phase))
  local saved={}
  for k=before+1,#f.calls do local rel=f.calls[k]:match('^copy state:AdvancedIA%-update/current/(.*)$'); if rel then saved[#saved+1]=rel end end
  table.sort(saved)
  assert(table.concat(saved,',')=='AdvancedIA.lua,manifest.ini,src/remote.lua,src/ui.lua,src/update.lua',table.concat(saved,','))
  assert(f.files[f.work..'/backup/sounds/beep.wav']==nil and f.files[f.work..'/backup/AdvancedIA.lua']=='main Beta 1.36','unchanged file not kept')
  assert(events(u):find('5 fichiers gardes',1,true),events(u))
 end)
 f.restore(); assert(ok,err)
end
-- Beta 1.47 : CSP a fait tourner l'ancien code (1.44) alors que le disque portait la 1.45 ; la mise à jour a écrit
-- « 1.45 -> 1.45 ». Le compte rendu porte la version qui tournait ; le repère garde celle du disque (reprise).
tests.UPDATE_REPORT_RUNNING_147=function()
 local u,p=ready({installed='Beta 1.34'})
 assert(u.installed=='Beta 1.33' and Up.install(u,p,true)); Up.tick(u,p,true,200)
 assert(find(p.calls,'mark update Beta 1.34 -> Beta 1.34'),'marker: version on disk (recovery)')
 assert(find(p.calls,'report update Beta 1.33 -> Beta 1.34'),'report: version that was running')
 u,p=ready({installed='Beta 1.33'}); Up.install(u,p,true); Up.tick(u,p,true,200)
 assert(find(p.calls,'report update Beta 1.33 -> Beta 1.34') and find(p.calls,'mark update Beta 1.33 -> Beta 1.34'),'same versions: unchanged')
end
return tests
