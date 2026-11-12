local U=require('src/util')
local C=require('src/config')
local Director=require('src/director')
local Perception=require('src/perception')
local Flash=require('src/flash')
local Classes=require('src/classes')
local Traffic=require('src/traffic')
local Weather=require('src/weather')
local Incidents=require('src/incidents')
local Pits=require('src/pits')
local Pitplan=require('src/pitplan')
local Panel=require('src/panel')
local Penalties=require('src/penalties')
-- Beta 1.42 : stratégie et sanctions des IA (modules remplis par les fourches de comportement).
local Strategy=require('src/strategy')
local Sanctions=require('src/sanctions')
local Delta=require('src/delta')
local Mistakes=require('src/mistakes')
local HudInfo=require('src/hudinfo')
local Flood=require('src/flood')
local Lights=require('src/lights')
local Grid=require('src/grid')
local Merge=require('src/merge')
-- Beta 1.59 : stratégies de départ variées et arrêt aux stands pour dégâts (réglages coupés par défaut).
local StartVar=require('src/startvar')
local DamagePit=require('src/damagepit')
-- Beta 1.60 (étape de base) : modules des tranches A à E, vides tant que leur tranche n'est pas livrée.
local Priority=require('src/priority')
local Rear=require('src/rear')
local Blame=require('src/blame')
local Mood=require('src/mood')
local Wear=require('src/wear')
local Pitloss=require('src/pitloss')
local Formation=require('src/formation')
-- Beta 1.61 (étape de base) : modules des tranches A à E (vides tant que leur tranche manque).
local ZoneLearn=require('src/zonelearn')
local Pacemap=require('src/pacemap')
local Nuance=require('src/nuance')
local Antics=require('src/antics')
local Wx=require('src/wx')
-- Beta 1.47 : premier tour attentif (départ et relances, course).
local FirstLap=require('src/firstlap')
local Quali=require('src/quali')
-- Beta 1.59 : vrais passages en piste des IA (essais et qualifications), audit des entrées aux stands (course).
local Runs=require('src/runs')
-- Beta 1.56 : annonce des pénalités d'AC actives (vos limites de piste gérées par l'app).
local L=require('src/lang')
local K=C.K
local M={}
-- Beta 1.59 : plan d'arrêt du joueur publié par SpotterEnginer (contrat v1 convenu avec sa session :
-- « v=1;lap=N;compound=-;state=planned|boxnow|done|none;window=a-b;boxcalls=0|1;stamp=s »). Lecture seule, champs inconnus
-- ignorés ; nil si absent, trop long, d'une autre version ou illisible.
local sePlanStates={planned=true,boxnow=true,done=true,none=true}
function M.parsePitPlan(text)
 if type(text)~='string' or #text>K.sePlanBytes or text:sub(1,4)~='v=1;' then return nil end
 local fields={}
 for key,value in text:gmatch('(%w+)=([^;]*)') do fields[key]=value end
 local lap,stamp=tonumber(fields.lap),tonumber(fields.stamp)
 if not sePlanStates[fields.state] or not stamp or stamp~=stamp or stamp<0 then return nil end
 if fields.state~='none' and not (lap and lap==math.floor(lap) and lap>=1 and lap<=K.sePlanLapMax) then return nil end
 return {state=fields.state,lap=lap or 0,stamp=stamp}
end
-- Mode du rappel d'arrêt du joueur d'après ce plan : nil (rappels de l'app), 'quiet' (le plan est suivi : rien avant son
-- tour) ou 'box' (son tour : rappel autorisé). Nos règles restent la référence : plan absent, figé, sans plan, arrêt
-- donné pour fait alors qu'il est encore dû, tour hors de notre fenêtre ou « rentrez » fenêtre fermée : nil.
function M.pitPlanMode(e,frame,player,due,now)
 local s=e.sePlan
 if not due or e.profile~='C' or not s then return nil end
 if s.raw~=s.parsedFor then s.parsedFor=s.raw; s.plan=M.parsePitPlan(s.raw) end
 local plan=s.plan
 if not plan then return nil end
 -- Horodatage figé (plus de K.sePlanStale s du temps du moteur, qui ne passe pas en pause) : plan oublié ; horodatage qui
 -- recule (nouvelle session, rechargement) : repris de zéro.
 if plan.stamp~=s.stamp then s.stamp=plan.stamp; s.stampAt=now end
 if not s.stampAt or now-s.stampAt>K.sePlanStale then return nil end
 if plan.state=='none' or plan.state=='done' then return nil end
 if plan.state=='boxnow' then
  if e.pits.state~='open' then return nil end
  -- Stands fermés par nos règles : jamais « rentrez » (l'overlay montre déjà STANDS FERMÉS).
  return e.incidents.pitsClosed and 'quiet' or 'box'
 end
 local current=(player and player.lap or 0)+1
 if plan.lap<current then return nil end
 -- Beta 1.59 (relecture) : fin de fenêtre proche (course chronométrée, fenêtre de CSP comprises) : nos rappels.
 local w=e.pits
 if w.close>w.open and w.position>=w.close-(w.close-w.open)*K.pitRemindLate then return nil end
 if not e.pits.csp and frame.sessionLaps>0 and not frame.timedRace and e.pits.close>0 and (plan.lap-1)/frame.sessionLaps>e.pits.close then return nil end
 return 'quiet'
end
-- Beta 1.60 : conseil d'undercut ou d'overcut du joueur publié par SpotterEnginer, contrat v1 convenu avec sa session :
-- « v=1;mode=undercut|overcut|cover|none;rival=<indice AC|-1>;gain=<s, une décimale|-1.0>;lap=<tour d'arrêt|0>;
-- stamp=<s entières du simulateur> », K.seStrategyBytes octets au plus, écrit au changement, périmé après
-- K.seStrategyStale s sans que stamp avance (même règle que le plan d'arrêt). Lecture seule ; champs inconnus ignorés,
-- autre version ignorée. AFFICHAGE ET JOURNAL SEULEMENT : jamais lu par les IA, nos règles restent la référence. Rend
-- le conseil, ou nil et la cause du refus.
local seStratModes={none=true,undercut=true,overcut=true,cover=true}
function M.parseStrategy(text)
 if type(text)~='string' then return nil,'illisible' end
 if #text>K.seStrategyBytes then return nil,'trop longue' end
 if text:sub(1,4)~='v=1;' then return nil,'version' end
 local fields={}
 for key,value in text:gmatch('(%w+)=([^;]*)') do fields[key]=value end
 local stamp=tonumber(fields.stamp)
 if not seStratModes[fields.mode] or not stamp or stamp~=stamp or stamp<0 or stamp==math.huge then return nil,'illisible' end
 local rival,lap,gain=tonumber(fields.rival) or -1,tonumber(fields.lap) or 0,tonumber(fields.gain) or -1
 if rival~=rival or lap~=lap or gain~=gain then return nil,'illisible' end
 return {mode=fields.mode,rival=math.floor(U.clamp(rival,-1,K.maxCars)),lap=math.floor(U.clamp(lap,0,K.sePlanLapMax)),
  gain=U.clamp(gain,-K.seStrategyMax,K.seStrategyMax),stamp=math.floor(stamp)}
end
local function seStrategyIgnored(e,s,why,now)
 s.ignored=s.ignored or {}
 if s.ignored[why] then return end
 s.ignored[why]=true
 U.log(e.log,now,'INFO','SpotterEnginer strategie: ignoree ('..why..')',-1)
end
-- À chaque image (course) : conseil valable montré sur le rappel d'arrêt du joueur (e.incidents.seStrategyMode et
-- seStrategyTarget, src/panel.lua) et journalisé à chaque changement, avec notre propre temps perdu appris à côté du
-- sien. Figé plus de K.seStrategyStale s du temps du moteur : oublié ; horodatage qui recule : repris de zéro.
function M.seStrategy(e,frame,player,now)
 local s=e.seStrategy; local inc=e.incidents
 inc.seStrategyMode=''; inc.seStrategyTarget=''
 if not s or e.profile~='C' or type(s.raw)~='string' or s.raw=='' then return end
 if s.raw~=s.parsedFor then
  local why
  s.parsedFor=s.raw; s.plan,why=M.parseStrategy(s.raw)
  if not s.plan then seStrategyIgnored(e,s,why,now) end
 end
 local plan=s.plan
 if not plan then return end
 if plan.stamp~=s.stamp then s.stamp=plan.stamp; s.stampAt=now end
 if not s.stampAt or now-s.stampAt>K.seStrategyStale then seStrategyIgnored(e,s,'figee',now); return end
 local target=''
 local b=plan.rival>=0 and frame.cars[plan.rival+1]
 if b and b.valid and b.index==plan.rival and not b.player then target=b.name or '' end
 if plan.mode~=s.logMode or plan.rival~=s.logTarget or plan.lap~=s.logLap then
  s.logMode=plan.mode; s.logTarget=plan.rival; s.logLap=plan.lap
  local pc=player and e.pits.cars[frame.player]
  U.log(e.log,now,'INFO',string.format('SpotterEnginer strategie: %s (rival %s, tour %d, gain %.1f s ; notre temps perdu aux stands %.1f s)',plan.mode,target~='' and target or '-',plan.lap,plan.gain,
   Pitloss.loss(e.pitloss,pc and pc.lapTime or 0)),-1)
 end
 if plan.mode~='none' then inc.seStrategyMode=plan.mode; inc.seStrategyTarget=target end
end
-- Journal du départ (Beta 1.24) : maintien de ligne (IA mesurées, décalées de la trajectoire) et pneus de chaque IA,
-- pour vérifier en jeu le premier virage et les gommes montées.
local function startReport(e,frame,now)
 local n,measured,offset,held,sides=0,0,0,0,0; local tyres,order={},{}
 e.startRadar=0; e.startLift=0; e.startHold=0; e.startSpeedLogged=false
 for i=1,frame.count do
  local a=frame.cars[i]
  if a.valid and a.control and not a.player and not a.safetyCar then
   n=n+1
   if a.splineLatValid then measured=measured+1 end
   if (e.states[i].laneMeters or 0)~=0 then offset=offset+1 end
   if (e.states[i].lane or 0)~=0 then held=held+1 end
   if (a.leftWidth or 0)>0 and (a.rightWidth or 0)>0 then sides=sides+1 end
   local index=a.compoundIndex or -1
   local key=index..' '..((a.tyreNames and a.tyreNames[index] or '?')..' '..(a.tyreLongNames and a.tyreLongNames[index] or ''))
   if not tyres[key] then tyres[key]=0; order[#order+1]=key end
   tyres[key]=tyres[key]+1
  end
 end
 U.log(e.log,now,'INFO',string.format('depart: maintien de ligne %s, %d IA, trajectoire mesuree %d, decalees %d, maintenues %d, largeur connue %d, signe %d ; prudence x%.2f, agressivite x%.2f ; drapeaux bleus %s (%.0f m) ; radar avant %s',
  e.run.startLaneHold and 'actif' or 'coupe',n,measured,offset,held,sides,e.runtimeG.offsetSign or 0,e.run.startCautionMult,e.run.startAggrMult,e.run.blueFlagEnabled and 'actifs' or 'coupes',e.run.blueFlagRange,e.runtimeG.useBrakeAssist and 'actif' or 'coupe'),-1)
 local parts={}; for _,key in ipairs(order) do parts[#parts+1]=tyres[key]..' x '..key end
 U.log(e.log,now,'INFO','pneus au depart: '..(#parts>0 and table.concat(parts,', ') or 'inconnus'),-1)
end
-- Beta 1.55 (essais du 9 novembre à Imola : IA vues en pneus pluie, toutes comptées en gommes sèches) : gommes de chaque
-- modèle de voiture des IA (noms courts et longs, classe retenue par l'app), une fois par session.
local function tyreModels(e,frame,now)
 if now<e.tyreModelsAt then return end
 e.tyreModelsAt=now+K.tyreModelsPeriod
 for i=1,frame.count do
  local a=frame.cars[i]
  if a.valid and a.tyresKnown and not a.player and a.id and a.tyreClass and not e.tyreModels[a.id] then
   e.tyreModels[a.id]=true
   local parts={}
   for index=0,K.maxTyreCompounds-1 do
    local short=a.tyreNames[index]; if not short then break end
    parts[#parts+1]=string.format('%s (%s) %s',short,a.tyreLongNames[index] or '',a.tyreClass[index] or '?')
   end
   U.log(e.log,now,'INFO',string.format('gommes du modele %s: %s',a.id,table.concat(parts,', ')),i)
  end
 end
end
-- Délai laissé à la direction de course avant l'évacuation d'une IA immobile en pleine piste (Beta 1.24), pour ne
-- jamais court-circuiter les règles : incident majeur puis neutralisation choisie (VSC, FCY, voiture de sécurité),
-- escalade en voiture de sécurité ou drapeau rouge (plusieurs voitures en cause en piste), neutralisation en cours.
-- 0 : aucune règle ne peut découler de cette voiture (seule en piste sous drapeau jaune local), évacuation rapide.
local function decisionTime(e,neutral)
 local p,t=e.run,e.incidents
 local race=e.profile=='C'
 local escalation=race and p.safetyCarEscalation and t.safety>0 and not t.safetyFailed
 local red=(race or e.profile=='P' or e.profile=='Q') and p.redFlagEnabled
 local several=t.onTrack>=2
 local delay=0
 -- Délais de la Beta 1.23 : fenêtre du drapeau rouge (5 s d'arrêt simultané) et de l'escalade.
 if neutral or several and (red or escalation) then delay=K.neutralRecoverTime end
 -- Incident majeur déclaré à majorIncidentTime s : la neutralisation (ou l'escalade) a le temps d'être décidée.
 if race and p.neutralization~='local' or (neutral or several) and escalation then delay=math.max(delay,p.majorIncidentTime+K.ruleDecision) end
 return delay
end
-- Journal des contacts entre voitures (Beta 1.24) : qui touche qui et comment, une fois par paire toutes les
-- K.contactLogPeriod s, pour régler le radar sur des faits. Au plus K.contactLogBudget lignes par seconde entre IA
-- (un carambolage ne noie pas les lignes d'incident) ; un contact avec le joueur est toujours noté.
local function contacts(e,frame,now)
 local second=math.floor(now)
 if e.contactSecond~=second then e.contactSecond=second; e.contactCount=0 end
 for i=1,frame.count do
  local a=frame.cars[i]; local j=a.collidedWith or -1
  if a.valid and j>=1 and j<=frame.count and j~=i and frame.cars[j].valid then
   local key=i<j and i*K.maxCars+j or j*K.maxCars+i
   local next=e.contacts[key]
   local b=frame.cars[j]
   -- Beta 1.60 : responsabilité des collisions (src/blame.lua), à chaque image où CSP signale le contact.
   Blame.contact(e.blame,e,frame,i,j,now)
   -- Beta 1.47 : dernier contact de chaque voiture (limites de piste : pas d'avertissement pour une voiture poussée).
   if e.lastContactAt then e.lastContactAt[i]=now; e.lastContactAt[j]=now end
   -- Beta 1.41 : chaque contact compté sur la minute (une fois par paire et par K.contactLogPeriod s), même au-delà du
   -- budget de lignes du journal ; avant, le résumé comptait les reprises au calme, pas les contacts.
   local seen=e.contactSeen[key]
   if not seen or now>=seen or seen-now>K.contactLogPeriod then e.contactSeen[key]=now+K.contactLogPeriod; e.stats.contactEvent=(e.stats.contactEvent or 0)+1 end
   if (not next or now>=next or next-now>K.contactLogPeriod) and (a.player or b.player or e.contactCount<K.contactLogBudget) then
    e.contacts[key]=now+K.contactLogPeriod
    if not a.player and not b.player then e.contactCount=e.contactCount+1 end
    local rel=Perception.relative(a,b,frame.length,e.contactRel)
    local text
    if math.abs(rel.lat)>=(a.width+b.width)*0.5 then text=string.format('contact: %s et %s se touchent sur le cote',a.name,b.name)
    elseif rel.long>0 then text=string.format('contact: %s touche l arriere de %s',a.name,b.name)
    else text=string.format('contact: %s touche l arriere de %s',b.name,a.name) end
    U.log(e.log,now,'INFO',string.format('%s (%.0f km/h d ecart)',text,math.abs(a.kmh-b.kmh)),i)
   end
  end
 end
end
-- Message à l'écran de chaque pénalité du joueur.
local penaltyMessages={delta='penaltyDelta',pass='penaltyPass',red='penaltyRed',stop='penaltyStop',jump='penaltyJump'}
function M.new(g,profiles)
 local initial=g.autoProfile and 'J' or g.manualProfile
 local e={g=g,profiles=profiles,profile=initial,p=profiles[initial],states={},commands={},perception=Perception.new(),
  flash=Flash.new(),classes=Classes.new(),traffic=Traffic.new(),weather=Weather.new(),incidents=Incidents.new(),pits=Pits.new(),pitplan=Pitplan.new(),panel=Panel.new(),penalties=Penalties.new(),delta=Delta.new(),mistakes=Mistakes.new(),deltaBeep={beepId=0,volume=1,nextAt=0},drsRule={restart=false,started=false,seen=false,travel={},last={},leader=0,reason=''},drs={was=false,beepId=0,volume=1},run={},runtimeG={},zones={},frame=nil,time=0,startedAt=0,session=-1,sessionType=-1,
  configured='',seed=-1,revision=0,configuredRevision=-1,eventSalt=0,wasStarted=false,
  log=U.newLog(K.logLines,K.logRate,K.logDedup),errors=0,frames=0,activeCount=0,maxFrame=0,meanFrame=0,
  guard='init',guardKind=nil,onlineLogKind=nil,onlineLogAt=-math.huge,onlineWas=false,panic=false,returning=false,pitSpline=-1,zoneStart=-1,
  flood={user='',system=nil,writable=false,loaded=false,minLength=K.floodMinLength,at=0},probeSeen=false}
 e.announce=function(kind,value,extra,text) Incidents.message(e.incidents,kind,value,extra,text) end
 -- Événements des modules purs vers le journal circulaire (et le journal de session sur disque).
 -- Beta 1.59 (relecture) : lignes DEBUG seulement avec le journal détaillé (règle des autres lignes DEBUG).
 e.note=function(level,message,index) if level=='DEBUG' and not (e.runtimeG and e.runtimeG.debugLog) then return end U.log(e.log,e.time,level,message,index) end
 -- Compteurs d'événements de la minute écoulée, relevés et remis à zéro par le résumé du journal.
 e.stats={}
 -- Informations de l'overlay (Beta 1.25), lues par le panneau.
 e.hud=HudInfo.new(); e.panel.info=e.hud
 -- Panneaux lumineux du circuit et signaux FIA du joueur (Beta 1.32) ; dernier véhicule lent annoncé au journal.
 e.lights=Lights.new(); e.slowLogged=0; e.tyreModels={}; e.tyreModelsAt=0
 -- Départ arrêté après un drapeau rouge (Beta 1.34) : places de grille, formation, feux ; capacités vues par le
 -- script principal (retenue, allure, décalage).
 e.grid=Grid.new(); e.gridCaps=false
 -- Contacts déjà notés (Beta 1.24) : prochaine ligne permise par paire de voitures.
 e.contacts={}; e.contactRel={}; e.contactSecond=-1; e.contactCount=0
 e.contactSeen={}; e.lastContactAt={}
 e.incidents.note=e.note; e.pits.note=e.note
 -- Beta 1.41 : sortie des stands (jonction, retenue au bout de la voie).
 e.merge=Merge.new()
 e.fl=FirstLap.new()
 -- Beta 1.51 : session (circuit#indice) dont le préréglage intégré est appliqué ; tampon des réglages gardés.
 e.presetSession=''; e.presetSessionDirty=false; e.presetKept={}
 -- Beta 1.51 : tours lancés en essais et qualifications.
 e.quali=Quali.new()
 -- Beta 1.42 : stratégie et sanctions des IA ; avancement de la course (tours restants, -1 inconnu).
 e.strategy=Strategy.new(); e.sanctions=Sanctions.new(); e.race={progress=-1,lapsLeft=-1,known=false}
 -- Beta 1.60 : états des modules des tranches A à E.
 e.rear=Rear.new(); e.blame=Blame.new(); e.mood=Mood.new(); e.wear=Wear.new(); e.pitloss=Pitloss.new(); e.formation=Formation.new()
 -- Beta 1.61 : états des modules des tranches A à E ; textes des clés annexes publiées pour SpotterEnginer (clé → texte,
 -- écrits par l'hôte quand ils changent).
 e.zonelearn=ZoneLearn.new(); e.pacemap=Pacemap.new(); e.nuance=Nuance.new(); e.antics=Antics.new(); e.wx=Wx.new(); e.sideText={}
 for i=1,K.maxCars do
  local s=Director.newState(); s.slot=i; e.states[i]=s
  -- Relecture 1.52 : dernier saut de position (IA anormalement lente), décalé par M.rebase (C.optionalTimerFields).
  s.slowTeleportAt=-math.huge
  e.commands[i]={active=false,offset=0,level=1,aggression=0.5,caution=1,brake=0,speedLimit=K.unlimitedSpeed,yellowLimit=K.unlimitedSpeed,stopHold=false,recover=false,penaltyPass=false,flashEvent=0,rulePit=false,pitHold=false,pitCompound=-1,pitVisit=0,scPark=false,scSpeed=K.unlimitedSpeed,mistakeId=0,mistakeKind='',mistakeCause='',mistakeTime=0,mistakeSeverity=1,fuelTarget=-1,fuelLaps=0,fuelSet=-1,pitRepair=false,startDelay=-1,startDelayFor='',levelScale=1,throttleLimit=1,wearId=0,wearWheel=0,wearKm=0}
 end
 return e
end
function M.changed(e) e.revision=(e.revision+1)%K.counterMax end
function M.select(e,profile)
 if e.profiles[profile] then e.profile=profile; e.p=e.profiles[profile]; e.g.manualProfile=profile; e.g.autoProfile=false; M.changed(e) end
end
function M.reset(e,now,keepOffset)
 for i=1,K.maxCars do Director.reset(e.states[i],now,keepOffset,true); e.commands[i].active=false end
 e.pitSpline=-1; e.eventSalt=(e.eventSalt+1)%K.counterMax; e.returning=keepOffset
end
function M.rebase(e,amount)
 e.time=e.time-amount; e.startedAt=e.startedAt-amount; if e.launchAt then e.launchAt=e.launchAt-amount end; if e.jumpGoAt then e.jumpGoAt=e.jumpGoAt-amount end; if e.jumpJudgeAt then e.jumpJudgeAt=e.jumpJudgeAt-amount end; e.panel.at=e.panel.at-amount; Penalties.rebase(e.penalties,amount); Delta.rebase(e.delta,amount); Mistakes.rebase(e.mistakes,amount); e.deltaBeep.nextAt=e.deltaBeep.nextAt-amount
 if e.panel.noticeUntil>-math.huge then e.panel.noticeUntil=e.panel.noticeUntil-amount end
 if e.panel.warnUntil>-math.huge then e.panel.warnUntil=e.panel.warnUntil-amount end
 Lights.rebase(e.lights,amount); Grid.rebase(e.grid,amount); Merge.rebase(e.merge,amount)
 if e.slowLoggedAt then e.slowLoggedAt=e.slowLoggedAt-amount end
 if e.tyreModelsAt>0 then e.tyreModelsAt=e.tyreModelsAt-amount end
 if e.panel.changedAt>-math.huge then e.panel.changedAt=e.panel.changedAt-amount end
 e.classes.nextAt=e.classes.nextAt-amount; e.classes.bopAt=e.classes.bopAt-amount
 e.traffic.nextAt=e.traffic.nextAt-amount
 e.weather.pendingAt=e.weather.pendingAt-amount
 Incidents.rebase(e.incidents,amount); Pits.rebase(e.pits,amount); Pitplan.rebase(e.pitplan,amount); Strategy.rebase(e.strategy,amount); Sanctions.rebase(e.sanctions,amount); Quali.rebase(e.quali,amount)
 -- Relecture 1.52 : informations de l'overlay, premier tour attentif, prochaine décision de l'AI flood et sorties
 -- étalées des stands (sinon IA retenue près de 24 h si le décalage tombe pendant les sorties) décalées aussi.
 HudInfo.rebase(e.hud,amount)
 -- Relecture 1.59 : passages en piste et arrêts pour dégâts recalés aussi.
 Runs.rebase(e.runs,amount); DamagePit.rebase(e.damagePit,amount)
 -- Beta 1.60 : modules des tranches A à E et champs de priorité partagés (src/priority.lua).
 Rear.rebase(e.rear,amount); Blame.rebase(e.blame,amount); Mood.rebase(e.mood,amount); Wear.rebase(e.wear,amount); Pitloss.rebase(e.pitloss,amount); Formation.rebase(e.formation,amount)
 ZoneLearn.rebase(e.zonelearn,amount); Pacemap.rebase(e.pacemap,amount); Nuance.rebase(e.nuance,amount); Antics.rebase(e.antics,amount); Wx.rebase(e.wx,amount)
 for i=1,K.maxCars do Priority.rebase(e.states[i],amount) end
 if e.sePlan and e.sePlan.stampAt then e.sePlan.stampAt=e.sePlan.stampAt-amount end
 if e.seStrategy and e.seStrategy.stampAt then e.seStrategy.stampAt=e.seStrategy.stampAt-amount end
 if FirstLap.rebase then FirstLap.rebase(e.fl,amount) end
 e.flood.at=e.flood.at-amount
 local x=e.traffic.exits
 if x then
  x.at=x.at-amount
  for i=1,K.maxCars do
   if U.finite(x.releaseAt[i]) then x.releaseAt[i]=x.releaseAt[i]-amount end
   if U.finite(x.checkAt[i]) then x.checkAt[i]=x.checkAt[i]-amount end
  end
 end
 for i=1,K.maxCars do
  local s=e.states[i]
  for _,key in ipairs(C.timerFields) do if U.finite(s[key]) then s[key]=s[key]-amount end end
  -- Relecture 1.52 : champ facultatif absent (nil) : rien à décaler.
  for _,key in ipairs(C.optionalTimerFields) do local v=s[key]; if v and v>0 then s[key]=v-amount end end
  for j=1,K.directionLimit do if U.finite(s.directions[j]) then s.directions[j]=s.directions[j]-amount end end
  local r=e.flash.requests[i]; r.untilTime=r.untilTime-amount; r.readyAt=r.readyAt-amount; r.cornerUntil=r.cornerUntil-amount
  local q=e.flash.ai[i]; q.untilTime=q.untilTime-amount; q.readyAt=q.readyAt-amount
  if U.finite(r.lastSeen) then r.lastSeen=r.lastSeen-amount end
 end
 local f=e.flash
 f.onAt=f.onAt-amount
 if f.learnUntil>0 then f.learnUntil=f.learnUntil-amount end
 if U.finite(f.lastEdge) then f.lastEdge=f.lastEdge-amount end
 if U.finite(f.lastPulse) then f.lastPulse=f.lastPulse-amount end
 if U.finite(f.lastEvent) then f.lastEvent=f.lastEvent-amount end
 if U.finite(f.eventTime) then f.eventTime=f.eventTime-amount end
 for i=1,K.logLines do if U.finite(e.log[i].time) then e.log[i].time=e.log[i].time-amount end end
 e.log.second=-1; e.rebaseDelta=amount
end
function M.configure(e)
 e.p=e.profiles[e.profile]
 C.effective(e.profile,e.p,e.run); C.effectiveGlobals(e.g,e.p,e.runtimeG)
 for i=1,K.maxCars do
  Director.configure(e.states[i],e.runtimeG,e.profile,e.run,e.time); e.states[i].nextPerception=e.time+(i%10)*K.perceptionPeriod/10
  local car=e.frame and e.frame.cars[i]
  if car and not e.p.section_general then e.commands[i].level=car.baseLevel or car.aiLevel; e.commands[i].aggression=car.baseAggression or car.aiAggression; e.commands[i].caution=K.defaultCaution end
 end
 local previous=e.flash; e.flash=Flash.new()
 -- Un apprentissage des phares en cours survit à un changement de réglage.
 if previous.learnUntil>0 then e.flash.learnUntil=previous.learnUntil; e.flash.scores=previous.scores; e.flash.last=previous.last end
 Classes.configure(e.classes,e.run); e.classes.nextAt=0; e.traffic.nextAt=0
 e.configured=e.profile; e.seed=e.g.seed; e.configuredRevision=e.revision
end
-- Pilotage des voitures first à last, chacune protégée par l'appel de l'appelant : carAt désigne la voiture fautive.
local carAt=0
-- DRS du joueur : bip au moment où il devient disponible (écriture sonore par l'applicateur) ; jamais sous drapeau.
local function drsBeep(e,frame,flagged,assist,volume)
 local driver=frame.player>0 and frame.cars[frame.player] or nil
 local available=assist and driver and driver.valid and driver.drsPresent and driver.drsAvailable and not flagged or false
 if available and not e.drs.was then e.drs.beepId=e.drs.beepId%K.counterMax+1; e.drs.volume=volume/100 end
 e.drs.was=available
end
-- Beta 1.60 (lot 3) : nom affiché des pilotes dont le nom porte le suffixe de Content Manager : niveau et agressivité
-- que l'app applique (colonnes NIV. et AGR. du tableau des IA), refaits au plus toutes les K.nameRefresh s et seulement
-- quand les valeurs arrondies changent ; joueur et voiture que l'app ne pilote pas : nom seul.
local function names(e,frame,now)
 if now<(e.namesAt or -math.huge) and e.namesAt-now<=K.nameRefresh then return end
 e.namesAt=now+K.nameRefresh
 for i=1,frame.count do
  local a=frame.cars[i]
  if a.cmSuffix then
   local cmd=e.commands[i]
   if a.valid and a.control and not a.player and cmd.active then
    -- Relecture (N3) : niveau réellement écrit (facteur des modules compris : un tour de chauffe montre son niveau).
    local lv,ag=math.floor(cmd.level*math.max(K.levelScaleMin,cmd.levelScale or 1)*100+0.5),math.floor(cmd.aggression*100+0.5)
    if lv~=a.nameLv or ag~=a.nameAg then a.nameLv=lv; a.nameAg=ag; a.name=string.format('%s (%d%%, %d%%)',a.baseName,lv,ag) end
   elseif a.nameLv~=nil then a.nameLv=nil; a.nameAg=nil; a.name=a.baseName end
  end
 end
end
M.names=names
local function drive(e,first,last,dt,now)
 for i=first,last do
  carAt=i
  local s=e.states[i]
  if s.excluded or now<s.errorUntil then e.commands[i].active=false
  else
   Director.step(e,i,dt,now)
   s.errorCount=0
   if e.commands[i].active then e.activeCount=e.activeCount+1 end
  end
 end
end
-- Beta 1.41 : bandeau qu'AC dessine lui-même (coupe, pénalité : CSP ne permet pas de le masquer).
function M.drawnByAC(title,description)
 for _,text in ipairs({type(title)=='string' and title:upper() or '',type(description)=='string' and description:upper() or ''}) do
  for _,pattern in ipairs(C.acDrawnMessages) do if text:find(pattern) then return true end end
 end
 return false
end
-- Message d'AC (ac.onMessage, Beta 1.25) : repris sur la ligne de session de l'overlay ; chaque titre noté une fois par
-- session au journal (pour savoir lesquels masquer ensuite).
function M.message(e,title,description,kind,time)
 -- Message témoin du masquage (Beta 1.26) : seulement noté, jamais affiché.
 if title==K.messageProbe then e.probeSeen=true; return end
 if not e.g.overlayMessages then return end
 -- Beta 1.41 (sessions de la Beta 1.40 : CUT DETECTED et PENALTY, SLOW DOWN… vus deux fois, par AC et par l'overlay) :
 -- bandeaux de coupe et de pénalité qu'AC dessine lui-même, notés au journal comme les autres, jamais repris.
 -- Annonce de l'app elle-même (ac.setMessage, « Penalty » en anglais) : reprise comme avant.
 local own=title==e.ownTitle and description==e.ownText
 -- Beta 1.43 : annonce de sanction d'une IA (panneau dédié, src/hudinfo) : notée au journal comme avant, jamais reprise
 -- en double sur la ligne de session.
 if own and e.ownAi then
  local seen=e.hud.seen
  local key=type(title)=='string' and title~='' and title or tostring(description or '')
  if not seen[key] then
   seen[key]=true
   U.log(e.log,e.time or 0,'INFO',string.format('message d AC: %s%s%s',tostring(title or ''),(description or '')~='' and ' : ' or '',tostring(description or '')),-1)
  end
  return
 end
 if not own and M.drawnByAC(title,description) then
  local h=e.hud
  if e.acDrawnSession~=e.session then e.acDrawnSession=e.session; U.log(e.log,e.time or 0,'INFO','messages d AC: penalites et coupes laissees a l affichage d AC (CSP ne permet pas de les masquer)',-1) end
  -- Beta 1.56 : AC sanctionne encore vos coupes alors que l'app gère vos limites de piste : noté une fois par session.
  if not e.acCutSeen and e.run and e.run.sanPlayerTrackLimits and (e.profile=='P' or e.profile=='Q' or e.profile=='C') then
   e.acCutSeen=true; e.acPenaltyWarned=true
   U.log(e.log,e.time or 0,'WARN',string.format('limites de piste joueur: AC sanctionne encore les coupes (%s)',tostring(title or description or '')),-1)
  end
  local key=type(title)=='string' and title~='' and title or tostring(description or '')
  if not h.seen[key] then
   h.seen[key]=true
   U.log(e.log,e.time or 0,'INFO',string.format('message d AC: %s%s%s',tostring(title or ''),(description or '')~='' and ' : ' or '',tostring(description or '')),-1)
  end
  return
 end
 if HudInfo.message(e.hud,title,description,kind,time,e.time or 0) then
  U.log(e.log,e.time or 0,'INFO',string.format('message d AC: %s%s%s',tostring(title or ''),(description or '')~='' and ' : ' or '',tostring(description or '')),-1)
 end
end
-- AI flood de CSP (Beta 1.26) : état lu au lancement (CSP le charge alors), puis réglage géré en journée circuit.
function M.floodInit(e,user,system,writable)
 local f=e.flood
 f.user=type(user)=='string' and user or ''; f.system=system; f.writable=writable==true; f.at=0
 f.loaded,f.minLength=Flood.state(f.user,system)
 U.log(e.log,0,'INFO',string.format('AI flood de CSP au lancement: %s (circuits d au moins %.1f km)%s',f.loaded and 'actif' or 'inactif',f.minLength/1000,f.writable and '' or ', reglage non modifiable par l app'),-1)
end
-- Journée circuit : réglage écrit selon la répartition choisie et le nombre d'IA (Flood.decide). CSP le lit au
-- lancement : la session en cours garde l'état chargé (e.flood.loaded) ; chaque écriture est annoncée sur l'overlay
-- et au journal. Réglage d'origine sauvegardé avant la première écriture (g.floodBackup), rendu en mode natif.
local function flood(e,frame,now)
 local f=e.flood
 if e.profile~='J' or not f.writable or frame.online or now<f.at then return end
 f.at=now+K.floodPeriod
 local count=0
 for i=1,frame.count do local a=frame.cars[i]; if a.valid and a.control and not a.player and not a.safetyCar then count=count+1 end end
 if count==0 then return end
 local decision=Flood.decide(e.run,count)
 if decision=='restore' and e.g.floodBackup=='' then return end
 local values=decision=='restore' and Flood.restore(e.g.floodBackup) or Flood.values(decision=='on',e.run.floodRangeKm)
 local text=Flood.edit(f.user,Flood.section,values)
 if text==f.user then
  if decision=='restore' then e.g.floodBackup=''; e.settingsChanged=true end
  return
 end
 local backup=e.g.floodBackup=='' and decision~='restore' and Flood.backup(f.user) or nil
 if not (e.floodWrite and e.floodWrite(text)) then
  f.writable=false
  U.log(e.log,now,'WARN','AI flood de CSP: ecriture du reglage impossible (cfg/extension/new_behaviour.ini)',-1)
  return
 end
 f.user=text
 if backup then e.g.floodBackup=backup elseif decision=='restore' then e.g.floodBackup='' end
 e.settingsChanged=true
 U.log(e.log,now,'INFO',string.format('AI flood de CSP: %s (%d IA, seuil %d, portee %.1f km), effet au prochain lancement',decision=='off' and 'desactive' or decision=='on' and 'active' or 'reglage d origine rendu',count,e.run.spawnMinCars or 0,e.run.floodRangeKm or 1),-1)
 HudInfo.flood(e.hud,decision,count,e.run.floodRangeKm or 1,now)
end
-- IA anormalement lente (Beta 1.28, diagnostic) : en piste, hors stands et zone jaune, en conduite, en cession ou en
-- dépassement (jamais en évitement ni au calme après un incident), plus lente que K.slowRatio fois l'allure de sa
-- classe à cet endroit (allure apprise), avec une voiture derrière à moins de K.slowFollowGap m, pendant K.slowLogTime
-- s : une ligne au journal, puis une à la fin de l'épisode, avec sa raison.
-- Beta 1.41 (journée circuit du 3 novembre, île de Man : deux IA endommagées à 30 km/h pendant plus de quatre minutes,
-- une file derrière elles) : seule la tête de la file compte (une voiture à peine plus rapide juste devant : même
-- file, jamais une cascade d'obstacles), et l'état sert au pilotage : au bout de K.slowObstacleTime s, obstacle à
-- contourner pour les voitures derrière (s.abnormal), sans ralentissement de cession de plus ; endommagée et lente
-- K.slowPitTime s, rentrée aux stands (voir plus bas).
local slowStates={DRIVE=true,YIELD_IN=true,YIELD_HOLD=true,YIELD_OUT=true,OVT_ARM=true,OVT_IN=true,OVT_HOLD=true,OVT_OUT=true,DEFEND=true}
local function slowReset(s) s.abnormalFor=0; s.abnormalCalm=0; s.abnormal=false; s.slowPitSent=false end
-- Raisons de fin d'épisode : textes construits une fois (jamais une chaîne par image).
local stateWhy=setmetatable({},{__index=function(t,k) local v='etat '..tostring(k); t[k]=v; return v end})
local crawlWhy='roule au pas (moins de '..K.slowMinKmh..' km/h)'
local function slowCars(e,frame,now,dt)
 local multi=e.run.multiClass==true
 for i=1,frame.count do
  local a=frame.cars[i]; local s=e.states[i]; local cmd=e.commands[i]
  if a.teleport then s.slowTeleportAt=now end
  local behind,expected,lead=0,0,false
  -- Raison de la fin d'un épisode (journal) : la première cause relevée quand la voiture ne retient plus le trafic.
  local why
  local eligible=a.valid and a.control and not a.player and not a.safetyCar and not a.pit and not a.inPitBox and now-(s.slowTeleportAt or -math.huge)>=K.slowSettle
  if not eligible then
   why=(a.pit or a.inPitBox) and 'rentree aux stands' or not a.valid and 'absente' or not a.control and 'hors commande' or 'deplacee (depannage)'
   slowReset(s)
  elseif a.offtrack or not a.splineValid or s.yellow or not slowStates[s.state] then
   why=a.offtrack and 'hors piste' or s.yellow and 'drapeau jaune' or stateWhy[s.state]
  else
   local fleet=e.delta.fleet[multi and s.class or 1]
   expected=fleet and fleet[Delta.bin(a.spline,e.delta.bins)] or 0
   -- Beta 1.41 : allure de la classe ici corrigée du rythme relatif habituel de l'IA (une voiture de route parmi des GT
   -- roule à son allure, pas « anormalement lente »). Relecture : rythme encore inconnu, diagnostic de la Beta 1.39 sur
   -- l'allure de la classe (journal seulement : ni obstacle ni stands).
   local own=(s.longRatioTime or 0)>=K.longRatioMin and expected*s.longRatio or 0
   if expected*3.6<K.slowMinPaceKmh then why='allure de reference inconnue ici'
   elseif a.kmh<K.slowMinKmh then why=crawlWhy
   elseif a.speed<(own>0 and own or expected)*K.slowRatio then
    local row=e.perception.rows[i]
    local ahead=row.front>0 and row.neighbors[row.front]
    lead=not (ahead and ahead.gap<K.slowFollowGap and frame.cars[ahead.index].kmh<=a.kmh+K.slowLeadMargin)
    if lead then
     for j=1,row.count do local r=row.neighbors[j]; if r.long<0 and r.gap<K.slowFollowGap then behind=behind+1 end end
     -- Beta 1.59 (journées circuit du 10 novembre : 80 km/h là où sa classe roule à 165, quatre voitures derrière, rien
     -- de fait) : hors course, rythme habituel encore inconnu (dans le trafic, jamais K.longRatioMin s de conduite
     -- libre) : obstacle quand même sous K.slowUnknownRatio fois l'allure de sa classe ici (plus strict que slowRatio).
     local judged=own>0 or e.profile~='C' and a.speed<expected*K.slowUnknownRatio
     if not judged or cmd.speedLimit<K.unlimitedSpeed then slowReset(s) else s.abnormalFor=(s.abnormalFor or 0)+dt; s.abnormalCalm=0 end
     if behind==0 then why='plus aucune voiture derriere' end
    else
     why='derriere une voiture lente'
     slowReset(s)
    end
   else
    why='allure retrouvee'
    -- Relecture : lenteur passagère, jamais cumulée avant l'état anormal (seul un épisode continu compte).
    if not s.abnormal then s.abnormalFor=0 end
    s.abnormalCalm=(s.abnormalCalm or 0)+dt
    if s.abnormalCalm>=K.slowEnd then slowReset(s) end
   end
  end
  local was=s.abnormal
  s.abnormal=(s.abnormalFor or 0)>=K.slowObstacleTime
  if s.abnormal and not was then
   U.log(e.log,now,'INFO',string.format('IA lente a contourner: %s, obstacle pour les voitures derriere (%.0f km/h, habituelle de l IA %.0f km/h, %d voiture(s) derriere)',
    a.name,a.kmh,expected*s.longRatio*3.6,behind),i)
  end
  if behind>0 then
   s.slowFor=(s.slowFor or 0)+dt; s.slowCalm=0; s.slowWhy=nil
   if not s.slowLogged and s.slowFor>=K.slowLogTime then
    s.slowLogged=true
    local cap=math.min(cmd.speedLimit or K.unlimitedSpeed,cmd.yellowLimit or K.unlimitedSpeed,cmd.scSpeed or K.unlimitedSpeed)
    local capText=cap<K.unlimitedSpeed and string.format('%.0f km/h',cap) or 'aucune'
    local usual=(s.longRatioTime or 0)>=K.longRatioMin and string.format('%.0f km/h',expected*s.longRatio*3.6) or e.profile~='C' and 'inconnue, allure de la classe' or 'inconnue, diagnostic seulement'
    U.log(e.log,now,'WARN',string.format('IA anormalement lente: %s (%s) a %.0f km/h depuis %.0f s, allure de sa classe ici %.0f km/h (habituelle de l IA %s), %d voiture(s) derriere a moins de %.0f m | etat %s, commande app %s, limite de vitesse app %s, niveau %.2f, degats carrosserie %.0f, suspension %.2f, moteur %.0f, boite %.2f | a %.0f m, pedales gaz %.2f frein %.2f, frein app %.2f, demande de stands app %s',
     a.name,a.id,a.kmh,s.slowFor,expected*3.6,usual,behind,K.slowFollowGap,s.state,cmd.active and 'oui' or 'non',capText,cmd.level or 0,a.damageBody or 0,a.damageSuspension or 0,a.engineLife or 0,a.damageGearbox or 0,
     a.spline*frame.length,a.gas or 0,a.brake or 0,cmd.brake or 0,cmd.rulePit and 'oui' or 'non'),i)
   end
  elseif (s.slowFor or 0)>0 then
   if not s.slowWhy then s.slowWhy=why=='allure retrouvee' and string.format('allure retrouvee, %.0f km/h',a.kmh) or why or 'aucune voiture derriere' end
   s.slowCalm=(s.slowCalm or 0)+dt
   if s.slowCalm>=K.slowEnd then
    if s.slowLogged then
     local text=s.slowWhy:find('^allure retrouvee') and string.format('IA anormalement lente: %s roule de nouveau normalement apres %.0f s (%s)',a.name,s.slowFor,s.slowWhy)
      or string.format('IA anormalement lente: %s ne retient plus le trafic apres %.0f s (%s)',a.name,s.slowFor,s.slowWhy)
     U.log(e.log,now,'INFO',text,i)
    end
    s.slowFor=0; s.slowCalm=0; s.slowLogged=false; s.slowWhy=nil
   end
  end
  -- Dégâts lus à chaque image pendant l'épisode (sinon seulement à basse vitesse).
  a.watchDamage=(s.abnormalFor or 0)>0 or (s.slowFor or 0)>=K.slowLogTime*0.5
 end
end
-- Beta 1.42 : avancement de la course (0 à 1) et tours restants du leader, en course commencée ; -1 inconnu.
local function raceInfo(e,frame)
 local r=e.race; local racing=e.profile=='C' and frame.started==true
 r.progress=racing and Pits.progress(frame) or -1
 local left=-1
 if racing then
  if frame.sessionLaps>0 and not frame.timedRace then left=math.max(0,frame.sessionLaps-frame.leaderLaps)
  elseif r.progress>0 and frame.leaderLaps>0 then left=math.max(0,math.ceil(frame.leaderLaps*(1-r.progress)/r.progress)) end
 end
 r.lapsLeft=left; r.known=left>=0
end
function M.step(e,frame,dt)
 e.frame=frame
 e.rebaseDelta=0
 if not U.finite(dt) or dt<=0 or dt>K.dtMax then
  e.guard='dt'; for i=1,K.maxCars do local s=e.states[i]; s.velocity=0; s.filtered=s.offset; e.commands[i].active=false end
  return false
 end
 if not frame.paused and not frame.replay then e.time=e.time+dt end
 if e.time>K.timeWrap then M.rebase(e,K.timeWrap) end
 local now=e.time
 -- DRS du joueur : disponibilité décidée par AC (zones et points de détection), notée à chaque changement.
 local me=frame.player>0 and frame.cars[frame.player] or nil
 local drsNow=me and me.valid and me.drsPresent and (me.drsAvailable and 1 or 0) or -1
 if drsNow~=e.playerDrs then
  if drsNow>=0 then U.log(e.log,now,'INFO',drsNow==1 and 'DRS joueur: disponible (AC)' or 'DRS joueur: indisponible (AC)',frame.player) end
  e.playerDrs=drsNow
 end
 if e.session~=frame.session or e.sessionType~=frame.type then
  -- Beta 1.61 (tranche B) : mémoire du circuit fusionnée avant l'oubli de l'allure apprise (réglage trackMemory).
  Pacemap.sessionEnd(e.pacemap,e,now)
  e.session=frame.session; e.sessionType=frame.type
  M.reset(e,now,true); e.wasStarted=frame.started; e.startedAt=frame.started and now-frame.time or now; e.launchAt=nil; e.jumpDue=false; e.jumpJudgeAt=nil; e.jumpGrade=nil
  e.classes.nextAt=0; e.flash=Flash.new(); e.tyreModels={}; e.tyreModelsAt=0
  -- Beta 1.60 : nouvelle session, modules des tranches A à E remis à zéro.
  Rear.reset(e.rear,now); Blame.reset(e.blame,now); Mood.reset(e.mood,now); Wear.reset(e.wear,now); Pitloss.reset(e.pitloss,now); Formation.reset(e.formation,now)
  ZoneLearn.reset(e.zonelearn,now); Pacemap.reset(e.pacemap,now); Nuance.reset(e.nuance,now); Antics.reset(e.antics,now); Wx.reset(e.wx,now)
  e.weather=Weather.new(); Incidents.reset(e.incidents); Pits.reset(e.pits,now); Pitplan.reset(e.pitplan); Penalties.reset(e.penalties); Delta.reset(e.delta); Mistakes.reset(e.mistakes); Lights.reset(e.lights); Grid.reset(e.grid); e.slowLogged=0; e.panel.warnPending=false; e.panel.warnUntil=-math.huge; e.drsRule={restart=false,started=false,seen=false,travel={},last={},leader=0,reason=''}
  -- Beta 1.56 : course commencée sans rapport (option) : rapport partiel avant l'oubli des sanctions ; pénalités d'AC
  -- relues pour la nouvelle session.
  e.reportLines=Sanctions.flushReport(e.sanctions,e,frame) or e.reportLines; e.acPenaltyWarned=false; e.acCutSeen=false; e.acPenaltyChecked=false
  e.configuredRevision=-1; Merge.reset(e.merge); Strategy.reset(e.strategy,now); Sanctions.reset(e.sanctions,now); Quali.reset(e.quali)
  FirstLap.reset(e.fl); e.fl.restartSerial=e.incidents.restartSerial or 0
  for i=1,K.maxCars do local s=e.states[i]; s.flOn=false; s.flW=0; s.flCare=0; s.flApproach=false end
  for i=1,K.maxCars do
   local s=e.states[i]; s.topKmh=0; s.stint=0; s.stintStart=now; s.class=2; s.classified=false; s.classCandidate=0; s.classCycles=0
   s.paceCount=0; s.paceMean=0; s.paceRatio=0; s.paceRatioCount=0; s.freePace=0; s.longRatio=1; s.longRatioTime=0; s.lastContact=now
   s.excluded=false; s.disqualified=false; s.errorUntil=0; s.errorCount=0; s.pitBefore=false; s.pitExitUntil=0; s.pitCautionUntil=0; s.pitGuardUntil=0; s.obstacleSlow=0
   -- Relecture de la Beta 1.41 : état « anormalement lente » et demande d'arrêt oubliés avec la session.
   slowReset(s); s.slowPitAsked=false; s.slowPitDone=false
   -- Relecture 1.52 : épisode « anormalement lente » du journal oublié aussi (sinon sa fin notée dans la session suivante).
   s.slowFor=0; s.slowLogged=false; s.slowCalm=0; s.slowWhy=nil
   for j=1,#s.pace do s.pace[j]=0 end
   -- Beta 1.61 (tranche B) : a priori de la mémoire du circuit reposé par src/pacemap.lua dans la nouvelle session.
   s.prior=nil; s.priorMap=nil; s.priorMean=nil; s.priorRatio=nil; s.priorN=0
  end
 end
 if e.g.autoProfile then e.profile=C.autoProfile(frame)
 else e.profile=e.g.manualProfile end
 local newProfile=e.loggedSession~=e.session or e.loggedProfile~=e.profile
 if newProfile then
  if e.loggedSession~=e.session then
   U.log(e.log,now,'INFO',string.format('session: indice %d, type CSP %d, type race.ini %d%s, circuit %s, voitures %d, longueur %.0f m',
    frame.session,frame.type,frame.configType,frame.configTrackDay and ' (Track Day)' or '',frame.track,frame.count,frame.length),-1)
  end
  U.log(e.log,now,'INFO','profil: '..e.profile..(e.g.autoProfile and ' (automatique)' or ' (manuel)'),-1)
  e.loggedSession=e.session; e.loggedProfile=e.profile
 end
 tyreModels(e,frame,now)
 local selected=e.profiles[e.profile]
 -- Beta 1.51 (demande du pilote) : profil automatique, préréglage intégré de la session appliqué et allumé dès qu'une
 -- nouvelle session est détectée (circuit et indice de session), une seule fois par session : un rechargement de l'app
 -- dans le même lancement (repère e.presetSession, gardé par ac.store) ne refait rien, les retouches du pilote restent.
 -- Règles de championnat du profil gardées. Hotlap et préréglage personnel : rien (C.sessionPreset).
 -- Profils déjà servis compris dans la clé : une détection qui arrive après la première image (journée circuit d'abord,
 -- puis qualifications) donne encore son préréglage au bon profil.
 -- Relecture 1.52 : clé « circuit#indice#profils servis » (ancienne clé circuit#indice#profil lue de même) : une bascule
 -- A -> B -> A dans la même session ne réapplique rien (retouches gardées) ; bornée à K.presetSessionKeyMax octets (nom du
 -- circuit tronqué) ; base refaite seulement quand le circuit ou l'indice change, jamais une chaîne par image. App
 -- coupée : rien (appliqué à son retour).
 if e.presetTrack~=frame.track or e.presetIndex~=frame.session then
  e.presetTrack=frame.track; e.presetIndex=frame.session
  local index='#'..tostring(frame.session)
  e.presetBase=tostring(frame.track):sub(1,K.presetSessionKeyMax-#index-K.presetSessionProfilesMax-1)..index
 end
 -- Profils servis relus seulement quand la clé ou la base change (clé rechargée par AdvancedIA.lua comprise).
 if e.presetParsed~=e.presetSession or e.presetParsedBase~=e.presetBase then
  local base,text=e.presetBase,e.presetSession
  e.presetParsed=text; e.presetParsedBase=base
  local served=#text>#base and text:sub(1,#base+1)==base..'#' and text:sub(#base+2) or ''
  e.presetServed=served:find('#',1,true) and '' or served
 end
 local bySession=e.g.autoProfile and e.g.presetBySession
 if bySession and e.g.enabled and selected and not frame.replay and not frame.online then
  local served=e.presetServed or ''
  if not served:find(e.profile,1,true) and #served<K.presetSessionProfilesMax then
   e.presetSession=e.presetBase..'#'..served..e.profile; e.presetSessionDirty=true
   local name=C.sessionPreset(e.g,e.profile,frame.track,frame.length)
   if name then
    C.applyBuiltin(e.g,e.profiles,name,e.profile,true,e.presetKept,frame.track,frame.length)
    e.settingsChanged=true; M.changed(e)
    U.log(e.log,now,'INFO',string.format('preset_session: %s (profil %s%s)',name,e.profile,C.isNordschleife(frame.track,frame.length) and ', circuit Nordschleife' or ''),-1)
   else U.log(e.log,now,'INFO','preset_session: aucun (profil '..e.profile..(C.mark(e.g,e.profile)==C.personalMark and ', preset personnel garde)' or ')'),-1) end
  end
 -- Profil Hotlap : aucun préréglage recommandé (sessions sans IA), il reste neutre. Relecture 1.52 : jamais avec le
 -- préréglage par session coché (relecture, en ligne, app coupée compris), ni en relecture ou en ligne.
 elseif not bySession and not frame.replay and not frame.online and e.g.presetsUsed and selected and not selected.configured and not C.anySection(selected) and C.recommended[e.profile] then
  -- Profil jamais réglé : son préréglage intégré recommandé, une seule fois. Un profil déjà réglé n'est jamais modifié.
  local name=e.profile=='J' and C.trackDayPreset(frame.track,frame.length) or C.recommended[e.profile]
  -- Beta 1.29 : règles de championnat du week-end gardées (copiées par le préréglage d'une autre session).
  local rules=e.keptWeekendRules or {}; e.keptWeekendRules=rules
  local weekend=not C.solo(e.profile)
  if weekend then for _,s in ipairs(C.ruleSchema) do rules[s.key]=selected[s.key] end end
  -- Beta 1.29 (demande du pilote) : appliqué tout seul, il n'est pas noté comme chargé par le pilote.
  C.preset(name,e.profile,selected)
  if weekend then for _,s in ipairs(C.ruleSchema) do selected[s.key]=rules[s.key] end; C.validate(e.profile,selected,selected) end
  e.settingsChanged=true; M.changed(e); U.log(e.log,now,'INFO','preset_auto:'..name,-1)
 end
 -- Réglages réels de la session dans le journal : onglets cochés du profil et jeu de règles.
 if newProfile and selected then
  local tabs={}; for _,group in ipairs(C.sections) do if C.on(selected,group) then tabs[#tabs+1]=group end end
  -- Beta 1.59 : jeu de règles mémorisé, pour noter ensuite chacun de ses changements (onglet Règles ou accueil).
  e.rulesLogged=C.on(selected,'rules') and (C.ruleCategory(e.profile,selected,C.switchKeys) or 'personnalisees') or 'decochees'
  U.log(e.log,now,'INFO','onglets: '..(#tabs>0 and table.concat(tabs,',') or 'aucun')..' ; regles: '..e.rulesLogged,-1)
  -- Sens latéral (Beta 1.25) : sans lui, aucun déplacement latéral n'est écrit (cession, dépassement, évitement).
  U.log(e.log,now,'INFO',string.format('sens lateral: %d / %d%s',e.g.offsetSign,e.g.sideSign,e.g.offsetSign==0 and ' (en attente de mesure, aucun deplacement lateral)' or ''),-1)
 end
 if e.configured~=e.profile or e.seed~=e.g.seed or e.configuredRevision~=e.revision then
  M.reset(e,now,true); M.configure(e)
  -- Beta 1.59 : changement du jeu de règles en cours de session (onglet Règles de course ou accueil) noté une fois ;
  -- calculé seulement quand les réglages changent, jamais à chaque image.
  if selected and e.rulesLogged then
   local rules=C.on(selected,'rules') and (C.ruleCategory(e.profile,selected,C.switchKeys) or 'personnalisees') or 'decochees'
   if rules~=e.rulesLogged then e.rulesLogged=rules; U.log(e.log,now,'INFO','regles de course: '..rules..' (changement)',-1) end
  end
 end
 C.effective(e.profile,e.p,e.run); C.effectiveGlobals(e.g,e.p,e.runtimeG)
 if e.returning then
  local settled=true
  for i=1,frame.count do if math.abs(e.states[i].offset-e.states[i].base)>K.offsetEpsilon then settled=false; break end end
  e.returning=not settled
 end
 if frame.started and not e.wasStarted then
  e.startedAt=now; e.launchAt=nil
  -- Beta 1.47 (banc des départs) : l'arrêt sur la grille ne compte pas comme un arrêt en piste : sans cela, une voiture
  -- encore lente une seconde après le feu vert était un obstacle à contourner (évitements dans le peloton au départ).
  -- Beta 1.60 (tranche E) : tour de formation (réglage raceStart) : le journal du départ et le premier tour attentif
  -- attendent le vrai départ (extinction des feux de la grille, ou drapeau vert du départ lancé).
  if Formation.begin(e.formation,e,frame,now) then for i=1,frame.count do e.states[i].obstacleSlow=0; frame.cars[i].stopped=0 end else
  for i=1,frame.count do e.states[i].obstacleSlow=0; frame.cars[i].stopped=0 end
  if e.profile=='C' then startReport(e,frame,now); FirstLap.arm(e,frame,now,'depart') end
  end
 end
 -- Mesure du départ (Beta 1.25) : vitesse moyenne du peloton à la fin de l'attente de départ et freinages du radar
 -- pendant le lancement, pour comparer les départs d'une version à l'autre.
 if e.startSpeedLogged==false and frame.started and now-e.startedAt>=e.run.startDelay then
  e.startSpeedLogged=true
  local sum,n=0,0
  for i=1,frame.count do local a=frame.cars[i]; if a.valid and a.control and not a.player and not a.safetyCar and not a.pit then sum=sum+a.kmh; n=n+1 end end
  -- Relecture 1.52 : pieds tenus en ligne droite (director.lua, e.startHold) notés aussi.
  U.log(e.log,now,'INFO',string.format('depart: peloton a %.0f km/h en moyenne apres %.0f s, %d freinage(s) du radar au lancement, %d lever(s) de pied, %d pied(s) tenu(s) en ligne droite',n>0 and sum/n or 0,e.run.startDelay,e.startRadar or 0,e.startLift or 0,e.startHold or 0),-1)
 end
 -- Beta 1.59 : même session relancée par AC (départ retombé, même indice) : récapitulatif et place de départ de
 -- l'overlay (et du pont) remis à zéro ; le reste du moteur est remis à zéro au changement de session, comme avant.
 if e.wasStarted and not frame.started and not frame.replay then e.raceGen=(e.raceGen or 0)+1; HudInfo.restart(e.hud); U.log(e.log,now,'INFO','course relancee: recapitulatif et place de depart remis a zero',-1) end
 e.wasStarted=frame.started
 -- Maintien de ligne au départ : écart à la trajectoire lu dans l'instantané suivant, pendant le départ seulement.
 frame.laneWanted=e.profile=='C' and e.run.startLaneHold==true and (not frame.started or now-math.max(e.startedAt,e.launchAt or -math.huge)<e.run.startDelay+e.run.startRelax)
 -- Beta 1.60 : jugement des collisions en service : écart latéral à la piste lu pour toutes les voitures (src/snapshot.lua).
 frame.blameWanted=Blame.active(e)
 -- Informations de l'overlay (Beta 1.25) : à chaque image, même app à l'arrêt ou session finie ; récapitulatif de
 -- course noté une fois au journal.
 HudInfo.update(e.hud,frame,e,now)
 if e.hud.recapNew then
  e.hud.recapNew=false
  U.log(e.log,now,'INFO','fin de course: '..table.concat(e.hud.recap,' | '),frame.player)
 end
 local reason=not e.g.enabled and 'disabled' or frame.online and 'online' or frame.replay and 'replay' or frame.paused and 'paused'
  or frame.finished and 'finished' or frame.length<=0 and 'spline' or e.panic and 'panic' or not C.any(e.p) and 'nosections' or 'ready'
 e.guard=reason
 -- Beta 1.57 (CSP 0.3.0-preview212 chez un joueur) : champs de CSP absents de cette version, lus comme absents (valeurs
 -- neutres) ; une ligne à chaque nouvelle liste.
 if frame.fieldsSerial and frame.fieldsSerial~=e.fieldsLogged then
  e.fieldsLogged=frame.fieldsSerial
  if (frame.missingSim or '')~='' or (frame.missingCar or '')~='' then
   U.log(e.log,now,'INFO','champs de CSP absents (version plus ancienne, lus comme absents): session '..(frame.missingSim~='' and frame.missingSim or '-')..' | voitures '..(frame.missingCar~='' and frame.missingCar or '-'),-1)
  end
 end
 -- Beta 1.57 (Ved, Overtake : « en ligne » hors connexion) : genre d'une garde « online » (vraie session en ligne, mode
 -- alt-online d'un script New Modes de CSP, lecture impossible), pour la fenêtre et le journal ; la garde elle-même (et le
 -- pont) ne change pas. Une ligne au début de la suspension ou à un changement de genre ; une suspension du même genre
 -- qui revient, au plus toutes les K.onlineLogGap s.
 if reason=='online' then
  local kind=frame.onlineKind=='alt' and 'alt' or frame.onlineKind=='read' and 'read' or 'online'
  e.guardKind=kind
  if kind~=e.onlineLogKind or not e.onlineWas and now-e.onlineLogAt>=K.onlineLogGap then
   e.onlineLogKind=kind; e.onlineLogAt=now
   U.log(e.log,now,'INFO',kind=='alt' and 'suspension: mode alt-online de CSP (script New Modes, annonce meme hors connexion), aucune commande ; lancer une session hors ligne depuis Content Manager'
    or kind=='read' and 'suspension: lecture de l etat du jeu impossible ('..(frame.readError~='' and frame.readError or 'erreur inconnue')..'), aucune commande'
    or 'suspension: session en ligne, aucune commande',-1)
  end
  e.onlineWas=true
 else e.guardKind=nil; e.onlineWas=false end
 if reason~='ready' then
  Merge.idle(e.merge,e.commands)
  for i=1,K.maxCars do local cmd=e.commands[i]; cmd.active=false; cmd.stopHold=false; cmd.rulePit=false; cmd.pitHold=false; cmd.penaltyPass=false; cmd.pitCompound=-1; cmd.fuelTarget=-1; cmd.fuelSet=-1; cmd.scPark=false; cmd.scSpeed=K.unlimitedSpeed; cmd.recover=false; cmd.drsBlock=false; cmd.startDelay=-1; cmd.slowCalled=false end
  -- App à l'arrêt : le panneau reprend encore les drapeaux d'AC (leur affichage d'origine est masqué dans CSP).
  e.incidents.playerFlag=false; e.incidents.playerYellow=false
  -- Pause : valeur des panneaux gardée (l'applicateur n'écrit rien en pause) ; sinon rendue à AC et recalculée dès la
  -- reprise (jamais un quart de seconde rendu à AC à chaque sortie de pause, Beta 1.35).
  if reason~='paused' then e.lights.value=K.flagNone; e.lights.reason=''; e.lights.at=-math.huge end; Panel.native(e.panel,frame,now,e.p,e.profile)
  -- Relecture 1.52 : rappels et avis des stands du joueur vidés (lus par le pont), sauf en pause (aucune annonce
  -- refaite à chaque reprise).
  if reason~='paused' then Incidents.clearPlayerPit(e.incidents) end
  -- Aucun onglet coché (hotlap, journée circuit sans commande) : le bip du DRS du joueur reste actif ; app coupée,
  -- panique, pause : aucun bip.
  if reason=='nosections' then drsBeep(e,frame,frame.flag==K.flagCaution and not frame.flagOwned,e.p.drsAssist~=false,e.p.drsBeepVolume or 100) else e.drs.was=false end
  return false
 end
 e.frames=(e.frames+1)%K.counterMax; e.activeCount=0
 -- Beta 1.41 (journée circuit du 3 novembre : voiture de sécurité posée en piste puis renvoyée aux stands) : identifiée
 -- avant la répartition des IA, qui l'écarte dès la première image.
 -- Voiture de sécurité : modèle choisi, présent sur la grille et piloté par l'IA ; garée aux stands dans toutes les
 -- sessions, déployée seulement en course quand les règles la prévoient.
 local model=e.g.safetyCarModel; local safety,matches,preferred,ais=0,0,0,0
 -- Toutes les IA de ce modèle sont mises de côté (grille « Manuel » de Content Manager : adversaires tirés au sort
 -- parmi les candidats) : celle à la livrée de voiture de sécurité (sinon la première, habillée de cette livrée) sert
 -- de voiture de sécurité, les autres restent garées aux stands dans toutes les sessions et ne courent jamais.
 for i=1,frame.count do
  local a=frame.cars[i]
  if a.valid and a.control and not a.player then ais=ais+1 end
  local reserved=model~='' and a.valid and a.control and not a.player and a.id==model
  if reserved then matches=matches+1; if safety==0 then safety=i end; if preferred==0 and a.skinSafety then preferred=i end end
  a.safetyCar=reserved
 end
 if preferred>0 then safety=preferred end
 -- Course monotype (le joueur roule ce modèle, ou toutes les IA) : aucune concurrente retirée ; seule une voiture à la
 -- livrée de voiture de sécurité le devient, sinon aucune (repli FCY).
 local player=frame.player>0 and frame.cars[frame.player] or nil
 -- Modèle par défaut jamais choisi par le pilote (Ferrari 458 Italia Stage 3, Beta 1.19), courant comme IA : porté par
 -- plusieurs voitures, ce sont des concurrentes ; seule une voiture à la livrée de voiture de sécurité le devient.
 local shared=model~='' and matches>=2 and not e.g.safetyCarPicked
 local oneMake=model~='' and (player~=nil and player.id==model or matches>=2 and matches>=ais or shared)
 if oneMake then
  safety=preferred
  for i=1,frame.count do frame.cars[i].safetyCar=i==safety end
 end
 -- Relecture 1.52 : état comparé champ par champ (jamais une chaîne par image).
 if matches~=e.safetyMatches or oneMake~=e.safetyOneMake or safety~=e.safetySlot then
  e.safetyMatches=matches; e.safetySlot=safety; e.safetyAmbiguous=matches>1 and not oneMake; e.safetyOneMake=oneMake
  if oneMake then U.log(e.log,now,'WARN',string.format('voiture de securite: modele %s = modele de la grille (%s), %s',model,shared and string.format('modele par defaut porte par %d voitures',matches) or 'monotype',safety>0 and 'seule la voiture a livree de securite est retiree' or 'aucune voiture retiree (repli FCY)'),-1)
  elseif matches>1 then U.log(e.log,now,'WARN',string.format('voiture de securite: modele %s porte par %d voitures, %s deployee, %d garees',model,matches,preferred>0 and 'celle a livree de securite' or 'la premiere',matches-1),-1) end
 end
 e.incidents.safety=safety
 flood(e,frame,now)
 Traffic.update(e.traffic,frame,e.states,e.run,e.runtimeG,e.profile,now,e.log)
 Traffic.exits(e.traffic,frame,e.run,e.runtimeG,e.profile,now,e.commands,e.log,e.flood.loaded and frame.length>=e.flood.minLength)
 contacts(e,frame,now)
 for i=1,frame.count do
  local a=frame.cars[i]; local state=e.states[i]
  if state.obstacleIdentity~=(a.identity or a.id) then state.obstacleSlow=0; a.stopped=0; state.obstacleIdentity=a.identity or a.id; state.topKmh=0 end
  -- Beta 1.47 : vitesse maximale vue de chaque voiture (repli relatif du double jaune quand l'allure est inconnue).
  if a.valid and not a.pit and a.kmh<K.topKmhMax and a.kmh>(state.topKmh or 0) then state.topKmh=a.kmh end
  if a.valid and not a.pit and a.kmh<e.run.obstacleSpeedKmh then state.obstacleSlow=math.min(K.stoppedTime+K.dtMax,math.max(state.obstacleSlow,a.stopped)+dt)
  else state.obstacleSlow=0 end
  a.stopped=state.obstacleSlow
  if a.pit and a.splineValid then e.pitSpline=a.spline end
  a.pitDistance=e.pitSpline>=0 and math.abs(U.spline(a.spline-e.pitSpline))*frame.length or math.huge
 end
 -- Incidents dès l'envol du départ : une grille arrêtée n'est pas une zone jaune, un accrochage au premier virage oui.
 local ready=frame.started and not (e.profile=='C' and now-e.startedAt<K.gridGrace)
 e.incidents.playerExcluded=e.penalties.disqualified
 -- Départ arrêté (Beta 1.34) : retenue, plafond d'allure et décalage disponibles, sens latéral mesuré, longueur de piste
 -- connue ; sinon la relance reste un départ lancé (raison au journal).
 e.incidents.gridReady=e.gridCaps==true and e.g.offsetSign~=0 and frame.length>0
 e.incidents.gridWhy=e.gridCaps~=true and 'capacites' or e.g.offsetSign==0 and 'sens lateral non mesure' or frame.length<=0 and 'circuit' or ''
 -- Beta 1.48 : IA disqualifiées (exclues de l'ordre figé au drapeau rouge), jonction des stands (pose de la voiture de
 -- sécurité en piste).
 e.incidents.dq=e.penalties.ai.dq; e.incidents.junction=e.merge.spline
 -- Beta 1.59 (relecture) : aucun point difficile armé au départ, à une relance ou pendant le premier tour attentif.
 e.incidents.hotspotPause=not frame.started or e.fl.on==true or e.incidents.restart==true or e.incidents.relaunch==true or e.profile=='C' and now-e.startedAt<K.hotspotStartGrace
 Incidents.update(e.incidents,frame,e.run,e.profile,now,dt,ready,e.runtimeG.seed)
 -- Beta 1.47 : relance lancée (drapeau vert derrière la voiture de sécurité, fin du tour de relance) : premier tour
 -- attentif de nouveau.
 if (e.incidents.restartSerial or 0)~=e.fl.restartSerial then e.fl.restartSerial=e.incidents.restartSerial or 0; FirstLap.arm(e,frame,now,'relance') end
 -- Allure de référence de la flotte (temps delta), quelques endroits par image ; Beta 1.41 : nombre d'endroits selon la
 -- longueur de la piste (changé : allure apprise de chaque voiture oubliée, ses rythmes relatifs gardés).
 if Delta.size(e.delta,frame.length) then
  local n=e.delta.bins
  for i=1,K.maxCars do
   local s=e.states[i]
   for j=#s.pace,n+1,-1 do s.pace[j]=nil end
   for j=1,n do s.pace[j]=0 end
   s.paceCount=0; s.paceMean=0; s.freePace=0
   -- Beta 1.61 (tranche B) : l'a priori gardé avait l'ancien nombre d'endroits (relu par src/pacemap.lua).
   s.prior=nil; s.priorMap=nil; s.priorMean=nil; s.priorRatio=nil; s.priorN=0
  end
 end
 Delta.refresh(e.delta,frame,e.states,e.run.multiClass==true)
 slowCars(e,frame,now,dt)
 -- Beta 1.31 : contexte d'un tête-à-queue d'IA (ce que l'app lui commandait juste avant) et vrais dépassements (deux
 -- voitures à moins de K.realPassGap m qui échangent leur place), avec ou sans manœuvre de l'app, et IA passées devant
 -- le joueur : ce que l'app change se mesure en jeu.
 local stats=e.stats
 for i=1,frame.count do
  local a=frame.cars[i]; local s=e.states[i]; local c=e.incidents.cars[i]
  if c.incident and c.since==now and not a.player and c.spun then
   local cmd=e.commands[i]
   U.log(e.log,now,'INFO',string.format('tete-a-queue, contexte: %s | etat %s depuis %.1f s, derniere manoeuvre %s, decalage %+.2f, prudence %.2f (base %.2f), agressivite %.2f (base %.2f), niveau %.2f, aspiration %s, frein app %.2f, limite %s, inattention %s, etat precedent %s (%s)',
    a.name,s.state,now-s.since,U.finite(s.maneuverAt) and string.format('il y a %.1f s',now-s.maneuverAt) or 'aucune',cmd.offset or 0,cmd.caution or 0,s.baseCaution or 0,cmd.aggression or 0,s.baseAggression or 0,cmd.level or 0,
    (s.slipTime or 0)>K.slipTime and 'oui' or 'non',s.appBrake or 0,
    -- Beta 1.54 : limite de vitesse de l'app (espacement, drapeau jaune), perte de concentration et état quitté juste avant.
    math.min(cmd.speedLimit or K.unlimitedSpeed,cmd.yellowLimit or K.unlimitedSpeed)<K.unlimitedSpeed and string.format('%.0f km/h',math.min(cmd.speedLimit or K.unlimitedSpeed,cmd.yellowLimit or K.unlimitedSpeed)) or 'aucune',
    (s.lapseUntil or 0)>now and 'oui' or 'non',s.prevState or 'aucun',s.prevReason or 'aucune'),i)
   -- Beta 1.60 : humeur de l'IA au moment du tête-à-queue (src/mood.lua), seulement avec les personnalités dynamiques.
   local mood=e.run and e.run.dynamicPersona and e.mood and e.mood.cars and e.mood.cars[i]
   if mood then U.log(e.log,now,'INFO',string.format('tete-a-queue, humeur: %s | stress %.0f %%, fatigue %.0f %%',a.name,(mood.stress or 0)*100,(mood.fatigue or 0)*100),i) end
  end
  if a.valid and not a.player and not a.pit then
   local row=e.perception.rows[i]
   if s.frontWas>0 then
    -- Position relative directe (abscisse sur la piste), sans parcourir les voisins à chaque image.
    local other=frame.cars[s.frontWas]
    local ahead=other and other.valid and other.splineValid and a.splineValid and U.spline(other.spline-a.spline)*frame.length or nil
    if ahead and ahead<0 and -ahead<=K.realPassGap and not other.pit then
     if other.player then stats.passedPlayer=(stats.passedPlayer or 0)+1
     else
      stats.realPass=(stats.realPass or 0)+1
      if s.lastPassTarget==s.frontWas and now-s.lastPassAt<K.realPassWindow then stats.realPassApp=(stats.realPassApp or 0)+1 end
     end
     s.frontWas=0
    elseif not ahead or math.abs(ahead)>K.realPassGap*2 then s.frontWas=0 end
   end
   local front=row.front>0 and row.neighbors[row.front] or nil
   if front and front.gap<=K.realPassGap then
    -- Voisins relevés par intermittence : la voiture n'est retenue que si elle est encore devant (position directe).
    local o=frame.cars[front.index]
    if o and o.splineValid and a.splineValid and U.spline(o.spline-a.spline)*frame.length>0 then s.frontWas=front.index end
   end
  else s.frontWas=0 end
 end
 local player=frame.player>0 and frame.cars[frame.player] or nil
 if player then
  local learned=Flash.sampleLearn(e.flash,player,now)
  if learned~=nil then e.g.flashField=learned; e.settingsChanged=true end
  local state=e.states[frame.player]
  if now>=state.nextPerception then Perception.refresh(e.perception,frame.cars,frame.count,frame.player,frame.length,e.frames); state.nextPerception=now+K.perceptionPeriod end
  local row=e.perception.rows[frame.player]
  state.state='DRIVE'
  if not (e.incidents.neutral or e.incidents.red or e.incidents.playerZone) then Director.pace(state,player,row,dt,e.run,nil,e.delta.bins) end
 end
 -- Une voiture par appel protégé, ou toutes en un seul (cache JIT agrandi : le compilateur trace alors Director.step) ;
 -- une erreur isole la voiture fautive et le pilotage reprend à la suivante, dans le même ordre.
 -- Beta 1.42 : facteurs des modules (niveau, accélérateur) remis au neutre avant le pilotage ; avancement de la course.
 for i=1,frame.count do local cmd=e.commands[i]; cmd.levelScale=1; cmd.throttleLimit=1 end
 raceInfo(e,frame)
 FirstLap.update(e,frame,now,dt)
 names(e,frame,now)
 Quali.update(e.quali,e,frame,now,dt)
 -- Beta 1.60 : avant le pilotage. Départ de la course (tour de formation, départ lancé), humeur des IA, conscience de
 -- l'arrière : champs par voiture lus par src/director.lua (champ absent : neutre).
 -- Tranche E : 'roll' au drapeau vert du départ lancé (ou grille annulée) : protections du départ rejouées, journal
 -- du départ, premier virage attentif imposé.
 if Formation.step(e.formation,e,frame,now,dt)=='roll' then e.launchAt=now; startReport(e,frame,now); FirstLap.arm(e,frame,now,'depart lance',true) end
 Mood.update(e.mood,e,frame,now,dt)
 Rear.update(e.rear,e,frame,now,dt)
 -- Beta 1.61 : avant le pilotage. Météo en direct (s.wxWet), tirages du départ et file du tour de formation
 -- (s.formOffset) : champs par voiture lus par src/director.lua (champ absent : neutre). e.passDone : voiture qui
 -- vient de réussir un dépassement dans cette image (posé par le directeur, lu par ZoneLearn.step).
 e.passDone=nil
 Wx.update(e.wx,e,frame,now,dt)
 Antics.draw(e.antics,e,frame,now)
 Antics.weave(e.antics,e,frame,now,dt)
 local first=1
 while first<=frame.count do
  local last=e.batchCars and frame.count or first
  local ok,err=pcall(drive,e,first,last,dt,now)
  if ok then first=last+1
  else
   local i=carAt; first=i+1
   local s=e.states[i]
   e.errors=math.min(K.counterMax,e.errors+1); s.errorCount=math.min(K.carErrorMax,s.errorCount+1); s.errorUntil=now+K.carErrorTime; s.excluded=s.errorCount>=K.carErrorMax
   s.state='IDLE'; s.velocity=0; s.filtered=s.offset
   local row=e.perception.rows[i]; pcall(Perception.occupancy,frame.cars,frame.count,i,e.runtimeG,row)
   local reset=(s.offset>0 and not row.left) or (s.offset<0 and not row.right) or s.offset==0
   if reset then s.offset=0; s.filtered=0 end
   local cmd=e.commands[i]; local car=frame.cars[i]
   cmd.active=true; cmd.offset=s.offset; cmd.level=car.baseLevel or car.aiLevel; cmd.aggression=car.baseAggression or car.aiAggression; cmd.caution=K.defaultCaution; cmd.brake=0; cmd.speedLimit=K.unlimitedSpeed; cmd.yellowLimit=K.unlimitedSpeed
   U.log(e.log,now,'ERROR',tostring(err):sub(1,256),i)
  end
 end
 for i=frame.count+1,K.maxCars do e.commands[i].active=false; e.states[i].state='IDLE' end
 for i=1,K.maxCars do e.commands[i].stopHold=i<=frame.count and e.incidents.cars[i].holding end
 -- Erreurs de pilotage des IA (blocage des roues, patinage) : décision, journal ; écriture par l'applicateur.
 local slips=Mistakes.update(e.mistakes,e,frame,e.run,e.profile,now)
 if slips then
  for _,i in ipairs(slips) do
   local cmd=e.commands[i]
   U.log(e.log,now,'INFO',string.format('erreur de pilotage: %s (%.1f s, %s), %s',cmd.mistakeKind=='brake' and 'blocage des roues au freinage' or 'patinage en sortie de virage',cmd.mistakeTime,cmd.mistakeCause,frame.cars[i].name),i)
  end
 end
 Incidents.player(e.incidents,frame,e.run,now)
 -- Temps delta du joueur (neutralisation, drapeau rouge, double drapeau jaune) ; file derrière la voiture de sécurité.
 local queued=false
 if player then local row=e.perception.rows[frame.player]; queued=row.front>0 and row.neighbors[row.front].gap<K.scQueueGap end
 Delta.update(e.delta,frame,e.run,e.incidents,e.states,now,dt,queued)
 -- Bips du temps delta : de plus en plus rapprochés près de zéro, très rapides en négatif.
 local dv=e.delta.value; local beep=e.deltaBeep; local interval=nil
 if dv and e.run.deltaBeeps then
  interval=dv<0 and K.deltaBeepNegative or dv<K.deltaBeepNear and K.deltaBeepFast or dv<K.deltaBeepMid and K.deltaBeepMedium or dv<K.deltaBeepFar and K.deltaBeepSlow or nil
 end
 if not interval then beep.nextAt=now
 elseif now>=beep.nextAt then beep.beepId=beep.beepId%K.counterMax+1; beep.volume=e.run.drsBeepVolume/100; beep.nextAt=now+interval
 elseif beep.nextAt>now+interval then beep.nextAt=now+interval end
 -- DRS (règles de course, comme la direction de course en F1) : coupé pour toutes les voitures sous la pluie, sous
 -- drapeau (neutralisation, drapeau rouge, zone jaune de la voiture) et, en course, pendant les premiers tours du leader
 -- après le départ, une voiture de sécurité ou un drapeau rouge (jamais après une VSC ou une FCY). Jamais en journée
 -- circuit.
 local dr=e.drsRule
 local rules=e.run.rulesDrs and not C.solo(e.profile)
 -- Tours mesurés par l'app (déplacement réel sur la piste, sauts écartés) depuis le départ et depuis chaque reprise :
 -- le compteur de tours du jeu n'est pas utilisé (grille avant la ligne de départ). App chargée en pleine course déjà
 -- lancée : pas d'attente.
 local restart=false
 local inc=e.incidents
 if inc.red or inc.neutral and (inc.neutralMode=='sc' or inc.relaunch) then dr.restart=true
 elseif dr.restart and not inc.neutral then dr.restart=false; restart=true end
 if frame.started and not dr.started or restart then
  local late=not restart and not dr.seen and frame.time>=K.drsLateLoad
  for i=1,K.maxCars do dr.travel[i]=late and K.drsLapsMax or 0; dr.last[i]=-1 end
 end
 dr.started=frame.started; dr.seen=true
 local leader=0
 for i=1,frame.count do
  local a=frame.cars[i]
  if frame.started and a.valid and a.splineValid and not a.pit then
   local last=dr.last[i] or -1
   if last>=0 then local ds=U.spline(a.spline-last); if ds>=0 and ds*frame.length<=K.deltaJump then dr.travel[i]=(dr.travel[i] or 0)+ds end end
   dr.last[i]=a.spline
   if (dr.travel[i] or 0)>leader then leader=dr.travel[i] end
  else dr.last[i]=-1 end
 end
 dr.leader=leader
 local laps=e.profile=='C' and math.max(0,math.ceil(e.run.rulesDrsLaps-leader-1e-9)) or 0
 local drsReason=not rules and '' or e.weather.wet and 'wet' or (e.incidents.neutral or e.incidents.red) and 'flag' or laps>0 and 'laps' or ''
 for i=1,frame.count do
  local a=frame.cars[i]
  -- Drapeau jaune de la voiture : zone de l'app, ou drapeau jaune natif d'AC montré au joueur.
  local own=rules and (a.player and (e.incidents.playerZone or frame.flag==K.flagCaution and not frame.flagOwned) or not a.player and e.states[i].yellow)
  local cmd=e.commands[i]
  cmd.drsBlock=rules and a.valid and a.drsPresent and (drsReason~='' or own) or false
  -- DRS des IA : ouvert quand il est disponible (coupé par les règles, il ne l'est jamais), en ligne droite et hors
  -- freinage ; refermé au freinage. Ouvertures comptées (toutes, et celles demandées par l'app).
  local s=e.states[i]; local want=nil
  if not a.player and a.valid and a.control and a.drsPresent then
   if a.drsActive and not s.drsWas then e.stats.drsOpen=(e.stats.drsOpen or 0)+1 end
   s.drsWas=a.drsActive
   if e.run.aiDrs and not cmd.drsBlock then
    if a.drsActive then if a.brake>=K.drsAiBrake then want=false end
    elseif a.drsAvailable and a.brake<K.drsAiBrake and (a.cornerYaw or a.corner or 1)>=K.drsAiCorner and a.kmh>=K.drsAiKmh then want=true end
   end
   if want and not s.drsAsked then s.drsAsked=true; e.stats.drsAsk=(e.stats.drsAsk or 0)+1 end
   if not a.drsAvailable then s.drsAsked=false end
  end
  cmd.drsWant=want
 end
 e.incidents.drsReason=drsReason=='' and rules and player and e.incidents.playerZone and 'flag' or drsReason
 e.incidents.drsLapsLeft=laps
 if dr.reason=='laps' and drsReason=='' then
  U.log(e.log,now,'INFO',string.format('DRS autorise: %.2f tour(s) mesure(s) du leader (compteur du jeu : %d)',leader,frame.leaderLaps),-1)
 end
 dr.reason=drsReason
 if player and player.drsPresent and e.run.drsAssist and rules and e.profile=='C' and drsReason~=dr.announced then
  local kind=drsReason=='laps' and 'drsLaps' or drsReason=='wet' and 'drsWet' or drsReason=='' and dr.announced~=nil and 'drsOn' or nil
  if kind then Incidents.message(e.incidents,kind,laps) end
  -- Annonce retenue seulement si le message a été affiché (un drapeau vert de la même image l'emporte) ; sinon retentée.
  local t=e.incidents
  if not kind or t.messageKind==kind and t.messageFrame==t.frameId then dr.announced=drsReason end
 end
 -- Beta 1.32 : véhicule lent devant le joueur (drapeau blanc), dégâts du joueur (drapeau noir à disque orange), valeur
 -- des panneaux lumineux du circuit ; place à rendre (avertissement).
 local l=e.lights
 local penaltyType=frame.player>0 and (frame.cars[frame.player].penaltyType or 0) or 0
 l.playerDisqualified=e.penalties.disqualified==true or penaltyType==K.penaltyBlackFlag
 l.playerPenalty=penaltyType>0
 if Lights.update(l,e.incidents,frame,e.run,e.profile,e.delta,e.states,e.run.multiClass==true,now) then
  U.log(e.log,now,'INFO',string.format('voiture du joueur endommagee: suspension %.2f, moteur %.0f, boite %.2f, carrosserie %.0f km/h, pneu eclate %s',
   frame.playerSuspension,frame.playerEngine,frame.playerGearbox,frame.playerBody,frame.playerBlown and 'oui' or 'non'),frame.player)
 end
 -- Une ligne par véhicule lent, pas plus d'une toutes les K.slowLogGap s (journée circuit chargée).
 if l.slowSlot>0 and l.slowSlot~=e.slowLogged and (e.slowLogged==0 or now-(e.slowLoggedAt or -math.huge)>=K.slowLogGap) then
  e.slowLoggedAt=now
  U.log(e.log,now,'INFO',string.format('vehicule lent devant le joueur: %s a %.0f km/h, %.0f m devant',frame.cars[l.slowSlot].name,l.slowKmh,l.slowGap),l.slowSlot)
 end
 e.slowLogged=l.slowSlot
 -- Pénalités du joueur sous drapeau jaune : journal, message à l'écran et ligne du panneau ; écriture par l'applicateur.
 Penalties.resume(e.penalties,frame)
 local penalty=Penalties.update(e.penalties,frame,e.run,e.profile,e.incidents,now,dt,e.delta)
 e.panel.passed=e.penalties.passedUnder
 Panel.infractions(e.panel,e.penalties.count,e.run.penaltyDisqualify)
 if penalty then
  local seconds=e.penalties.seconds
  local t=e.penalties; local detail
  if penalty=='delta' then detail=string.format('delta negatif (%s, %.2f s au mini-secteur)',t.deltaKind,t.deltaValue)
  elseif penalty=='pass' then detail=string.format('depassement sous drapeau jaune (%s)',t.passed>0 and frame.cars[t.passed].name or '?')
  elseif penalty=='red' then detail='pas dans la voie des stands a la reprise apres drapeau rouge'
  elseif penalty=='jump' then detail='faux depart (depart arrete)'
  else detail='arret obligatoire non effectue dans la fenetre' end
  if t.kind=='dq' then
   U.log(e.log,now,'WARN',string.format('disqualification du joueur: drapeau noir apres %d infractions, derniere : %s',t.count,detail),frame.player)
   if e.run.yellowMessage then Incidents.message(e.incidents,'penaltyDq',t.count) end; Panel.notice(e.panel,'dq',t.count,now)
   -- Beta 1.32 : disqualifié, l'avertissement n'a plus lieu d'être.
   e.panel.warnPending=false; e.panel.warnUntil=-math.huge
  else
   U.log(e.log,now,'WARN',string.format('penalite du joueur: %s, coupure des gaz %.0f s (infraction %d / %d)',detail,seconds,t.count,e.run.penaltyDisqualify),frame.player)
   if e.run.yellowMessage then Incidents.message(e.incidents,penaltyMessages[penalty],seconds) end
   Panel.notice(e.panel,penalty,seconds,now)
   -- Beta 1.32 : dernière infraction tolérée, la suivante disqualifie : avertissement (drapeau noir et blanc).
   -- Beta 1.59.1 : en course seulement (pas de drapeau noir en essais ni en qualifications).
   if e.profile=='C' then
   if t.count>=e.run.penaltyDisqualify then Panel.warn(e.panel); U.log(e.log,now,'INFO','avertissement du joueur: prochaine infraction, disqualification',frame.player) end
   end
  end
 end
 -- Sanctions des IA sous drapeau jaune : journal, message à l'écran pour une disqualification.
 local sanctioned=Penalties.ai(e.penalties,frame,e.run,e.profile,e.incidents,e.states,e.perception.rows,now)
 if sanctioned then
  local ai=e.penalties.ai
  for _,i in ipairs(sanctioned) do
   local other=frame.cars[ai.passed[i]]
   if ai.dq[i] then
    e.states[i].disqualified=true
    U.log(e.log,now,'WARN',string.format('IA disqualifiee: %s, %d depassements sous drapeau jaune (dernier : %s)',frame.cars[i].name,ai.count[i],other.name),i)
    if e.run.yellowMessage then Incidents.message(e.incidents,'aiDq',0,0,frame.cars[i].name) end
   else
    U.log(e.log,now,'WARN',string.format('sanction IA: %s a double %s sous drapeau jaune (infraction %d / %d), pied leve %.0f s',frame.cars[i].name,other.name,ai.count[i],e.run.penaltyDisqualify,e.run.penaltySeconds),i)
   end
  end
 end
 -- Beta 1.60 : voiture de sécurité doublée par une IA (src/incidents.lua) : même sanction, même ligne de journal.
 local passes=e.incidents.scPasses
 if passes and #passes>0 then
  for k=1,#passes do
   local i=passes[k]; local a=frame.cars[i]; local sc=frame.cars[e.incidents.safety]
   if sc and a.valid and a.control and not a.player and Penalties.scPassed(e.penalties,i,e.incidents.safety,a,e.run,e.profile,now) then
    local ai=e.penalties.ai
    if ai.dq[i] then
     e.states[i].disqualified=true
     U.log(e.log,now,'WARN',string.format('IA disqualifiee: %s, %d depassements sous drapeau jaune (dernier : %s)',a.name,ai.count[i],sc.name),i)
     if e.run.yellowMessage then Incidents.message(e.incidents,'aiDq',0,0,a.name) end
    else
     U.log(e.log,now,'WARN',string.format('sanction IA: %s a double %s sous drapeau jaune (infraction %d / %d), pied leve %.0f s',a.name,sc.name,ai.count[i],e.run.penaltyDisqualify,e.run.penaltySeconds),i)
    end
   end
  end
  for k=#passes,1,-1 do passes[k]=nil end
 end
 -- Beta 1.50 : place rendue après un dépassement interdit sous neutralisation ou au tour de relance.
 local notes=e.penalties.ai.notes
 if notes and #notes>0 then
  for k=1,#notes do
   local n=notes[k]; local a,b=frame.cars[n.i],frame.cars[n.j]
   if n.kind=='owe' then U.log(e.log,now,'WARN',string.format('sanction IA: %s rend la place a %s (au plus %.0f s)',a.name,b.name,K.aiGiveBackMax),n.i)
   elseif n.kind=='given' then U.log(e.log,now,'INFO',string.format('place rendue IA: %s a %s (neutralisation)',a.name,b.name),n.i)
   else U.log(e.log,now,'INFO',string.format('place a rendre IA: %s a %s, abandonnee (%s)',a.name,b.name,n.why or ''),n.i) end
  end
  for k=#notes,1,-1 do notes[k]=nil end
 end
 -- Bip du DRS : jamais sous drapeau (le DRS y est interdit) ; il retentit à la fin du drapeau si la zone est encore active.
 local flagged=e.incidents.red or e.incidents.neutral or e.incidents.playerZone or frame.flag==K.flagCaution and not frame.flagOwned
 drsBeep(e,frame,flagged or (e.incidents.drsReason or '')~='',e.run.drsAssist,e.run.drsBeepVolume)
 if player and e.p.section_flash and (e.g.flashField~='' or e.run.hornEnabled) then
  local signal=player[e.g.flashField]==true or e.run.hornEnabled and player.hornActive
  if Flash.step(e.flash,signal,now) then
   local reacted=Flash.dispatch(e.flash,frame.cars,frame.count,frame.player,e.perception,e.states,e.run,e.runtimeG,e.profile,now)
   -- Beta 1.29 : chaque appel du joueur au journal (IA visées, la plus proche, appel vu et compris).
   local f=e.flash
   U.log(e.log,now,'INFO',f.ranked>0 and string.format('appel de phares du joueur: %d IA visee(s) a moins de %.0f m, la plus proche a %.0f m (%+.0f km/h), vu par %d, compris par %d',f.ranked,e.run.flashRange,f.nearestGap,f.nearestSa,reacted,f.heard)
    or string.format('appel de phares du joueur: aucune IA visee devant a moins de %.0f m',e.run.flashRange),frame.player)
  end
 end
 if e.run.multiClass then Classes.update(e.classes,frame.cars,e.states,frame.count,e.run,now) end
 Classes.balance(e.classes,frame.cars,e.states,frame.count,e.run,now)
 Weather.step(e.weather,frame,e.commands,e.run,now,e.states,e.runtimeG.seed)
 -- Beta 1.59 : gomme de départ variée (course, avant le départ, réglage strategyStartVariety).
 StartVar.step(e.weather,frame,e.commands,e.run,e.runtimeG.seed,e.profile=='C',e.log,now)
 -- Journal : météo lue au lancement de chaque session et à chaque changement de profil, avec la gestion des pneus
 -- du profil en cours (diagnostic des pneus pluie au sec).
 -- Relecture 1.52 : clé refaite seulement quand la session ou le profil change (jamais une chaîne par image).
 if e.reportSession~=frame.session or e.reportProfile~=e.profile then e.reportSession=frame.session; e.reportProfile=e.profile; e.reportKey=frame.session..e.profile end
 local reported=e.reportKey
 if e.weather.reported~=reported then
  e.weather.reported=reported
  local managed=e.run.weatherTyresEnabled and 'oui' or not C.on(e.p,'weather') and 'non (onglet Meteo decoche)' or 'non (option pneus decochee)'
  U.log(e.log,now,'INFO',string.format('meteo au lancement: %s (humidite %.2f, pluie %.2f, eau %.2f), profil %s, pneus geres par l app: %s',
   e.weather.wet and 'pluie' or 'sec',frame.wet or 0,frame.rain or 0,frame.water or 0,e.profile,managed),-1)
 end
 if e.weather.changedAt==now then
  U.log(e.log,now,'INFO',e.weather.wet and 'meteo: piste humide' or 'meteo: piste seche',-1)
  if e.run.weatherMessage then Incidents.message(e.incidents,e.weather.wet and 'wet' or 'dry') end
  -- Piste glissante (drapeau à bandes jaunes et rouges) au passage du sec à la pluie, jamais au lancement (ni dans les
  -- premières secondes de la session, le temps que la météo lue se stabilise).
  if e.weather.wet and frame.time>=K.slipperyGrace then e.incidents.slipperyUntil=now+K.slipperyShow end
 end
 local red=e.incidents.red
 -- Course devenue mouillée : la règle des deux composés secs (F1) ne s'applique plus.
 if e.weather.wet and e.profile=='C' and frame.started then e.pits.wetRace=true end
 Pits.update(e.pits,frame,e.commands,e.run,e.profile,now,e.runtimeG.seed,e.announce,red,e.penalties.ai.dq,e.incidents.pitsClosed)
 -- Beta 1.41 : sortie des stands, IA retenue au bout de la voie tant qu'une voiture en piste arrive à la jonction.
 Merge.update(e.merge,frame,e.commands,now,dt,e.log,red,e.profile,e.stopCap~=false,e.quali.active and e.quali.push or nil)
 -- Beta 1.42 : stratégie individuelle des IA (arrêts, carburant, pneus, pannes, tour de sortie).
 Strategy.update(e.strategy,e,frame,now,dt)
 -- Beta 1.60 : après le pilotage. Remise des gaz en sortie de virage, usure et carburant sur le rythme, temps perdu
 -- aux stands (cmd.levelScale par produit, cmd.throttleLimit par minimum, comme la stratégie).
 Mood.exit(e.mood,e,frame,now,dt)
 Wear.update(e.wear,e,frame,now,dt)
 Pitloss.update(e.pitloss,e,frame,now,dt)
 -- Beta 1.61 : après le pilotage. Envol et faux départs, zones apprises, allure gardée par circuit.
 Antics.launch(e.antics,e,frame,now,dt)
 ZoneLearn.step(e.zonelearn,e,frame,now,dt)
 Pacemap.observe(e.pacemap,e,frame,now,dt)
 -- Beta 1.59 : passages en piste (après les arrêts des règles et de la stratégie, qui remettent les demandes à zéro).
 Runs.update(e,frame,now)
 -- Arrêts obligatoires du joueur : rappel sur le panneau à l'ouverture et vers la fin de la fenêtre ; arrêt manqué
 -- à la fermeture : pénalité, dès que possible (une fenêtre qui se ferme à 100 % de la course ne se ferme jamais).
 -- Relecture 1.52 : un seul arrêt obligatoire (0 ou 1 depuis la 1.51) : dû ou non ; l'entier 0/1 reste publié au pont.
 local pc=player and e.pits.cars[frame.player] or nil
 local due=pc~=nil and e.pits.state=='open' and pc.windowStops<e.run.mandatoryStops
 e.incidents.playerPitDue=due and 1 or 0
 e.incidents.playerPitRemind=due and (now-e.pits.openedAt<K.pitRemindTime or e.pits.position>=e.pits.close-(e.pits.close-e.pits.open)*K.pitRemindLate)
 -- Beta 1.59 (demande du pilote : « Arrêt obligatoire » répété sans cesse) : l'overlay ne montre plus le rappel en
 -- continu vers la fin de la fenêtre ; il le montre à l'ouverture, puis au plus une fois par tour (dernier tiers du
 -- tour, K.pitHintShow s ; en F1, le rappel d'avant l'entrée des stands le remplace). L'état publié au pont
 -- (playerPitRemind) ne change pas. Plan de SpotterEnginer valable : rien avant son tour.
 local sePlanMode=M.pitPlanMode(e,frame,player,due,now)
 local p0=e.pits
 local lap=player and player.lap or 0
 local f1Remind=e.profile=='C' and e.run.pitCompoundChange==true and not e.pits.waived and e.run.mandatoryStops>0
 -- Beta 1.59 (relecture) : entrée des stands connue : juste avant elle (K.pitHintTime + K.pitHintShow s) ; sinon dernier tiers.
 local entryD=p0.entrySpline>=0 and frame.length>0 and player.splineValid and U.spline(p0.entrySpline-player.spline)*frame.length or -1
 local remindHere=entryD>=0 and entryD/math.max(player.speed or 0,K.pitHintMinSpeed)<=K.pitHintTime+K.pitHintShow or entryD<0 and player.splineValid and player.spline>=K.pitHintSector
 if due and sePlanMode~='quiet' and not f1Remind and remindHere and p0.remindLap~=lap then p0.remindLap=lap; p0.remindAt=now end
 if not due then p0.remindLap=nil end
 e.incidents.playerPitShowRemind=due and (now-e.pits.openedAt<K.pitRemindTime or p0.remindLap==lap and now-(p0.remindAt or -math.huge)<K.pitHintShow)
 e.incidents.sePlanMode=sePlanMode
 -- Beta 1.60 (tranche D) : conseil de stratégie de SpotterEnginer (affichage et journal seulement).
 M.seStrategy(e,frame,player,now)
 -- Relecture 1.52 : fenêtre fermée pendant que le composé du joueur est attendu (F1, arrivé dans la fenêtre) : pénalité
 -- différée jusqu'à la décision (src/pits.lua), seulement si l'arrêt n'est finalement pas compté (même composé à la fin
 -- du délai) ; oubliée si la voiture du joueur change ou si l'arrêt obligatoire est levé (course mouillée).
 if e.pits.justClosed and pc and pc.windowStops<e.run.mandatoryStops then
  if pc.pendingCompound~=nil then e.pits.stopAwait=pc.identity else e.penalties.stopPending=true end
 end
 if e.pits.stopAwait then
  if not pc or pc.identity~=e.pits.stopAwait or e.pits.waived then e.pits.stopAwait=false
  elseif pc.pendingCompound==nil then
   e.pits.stopAwait=false
   if pc.windowStops<e.run.mandatoryStops then e.penalties.stopPending=true end
  end
 end
 -- Beta 1.49 : F1 (changement de composé exigé), arrêt obligatoire encore dû : stratégie des stands du joueur relue
 -- (src/pitplan.lua, lecture fournie par l'hôte) ; rappel « changez de composé » avant l'entrée des stands (environ
 -- K.pitHintTime s, entrée relevée sur les autres voitures, sinon dernier tiers du tour), dans la voie et à
 -- l'emplacement ; avis du joueur après l'arrêt (src/pits.lua). Rien ne change pour les IA.
 local f1=e.profile=='C' and e.run.pitCompoundChange==true and not e.pits.waived and e.run.mandatoryStops>0
 local owed=f1 and pc~=nil and pc.windowStops<e.run.mandatoryStops and (e.pits.state=='pending' or e.pits.state=='open')
 e.incidents.playerPitCompound=f1
 if e.pitSpinners then Pitplan.update(e.pitplan,frame,now,owed,f1,frame.started and e.incidents.standing~='grid' and e.incidents.standing~='lights',e.pitSpinners,e.note) end
 local hint=false
 -- Beta 1.50 (course du 5 novembre, 11:22 : « pitCompound » annoncé deux fois à 10 s d'écart) : rappel verrouillé dès
 -- qu'il apparaît, jusqu'au point d'entrée des stands (un freinage dans la fenêtre faisait baisser le temps restant
 -- sous le seuil, puis remonter) ; jamais après le point (distance négative) ; point passé sans entrer : fini pour ce
 -- tour ; dans la voie des stands, il continue ; à la sortie, levé.
 -- Beta 1.59 : au plus une fois par tour (p0.hintLap), jamais avant le tour du plan de SpotterEnginer ; dans la voie et
 -- à l'emplacement, toujours (consigne du composé). Sans entrée connue : K.pitHintShow s dans le dernier tiers du tour.
 local allowHint=sePlanMode~='quiet'
 if owed and e.pits.state=='open' and player.valid then
  if player.pit or player.inPitBox then hint=true; p0.hintLatch=true
  elseif player.splineValid then
   local entry=e.pits.entrySpline
   if entry>=0 and frame.length>0 then
    local d=U.spline(entry-player.spline)*frame.length
    -- Verrou levé aussi si la voiture s'éloigne de l'entrée de plus de K.pitHintLatchSlack m (déplacée, demi-tour).
    if p0.hintLatch and (d<0 or d>(p0.hintLatchD or d)+K.pitHintLatchSlack) then p0.hintLatch=false end
    if not p0.hintLatch and allowHint and p0.hintLap~=lap and d>=0 and d/math.max(player.speed or 0,K.pitHintMinSpeed)<=K.pitHintTime then p0.hintLatch=true; p0.hintLatchD=d; p0.hintLap=lap end
    if p0.hintLatch then p0.hintLatchD=math.min(p0.hintLatchD or d,d) end
    hint=p0.hintLatch==true
   else
    p0.hintLatch=false
    if allowHint and p0.hintLap~=lap and player.spline>=K.pitHintSector then p0.hintLap=lap; p0.hintAt=now end
    hint=p0.hintLap==lap and now-(p0.hintAt or -math.huge)<K.pitHintShow
   end
  end
 else p0.hintLatch=false end
 if owed and player.compoundIndex~=e.pits.hintFor then
  p0.hintFor=player.compoundIndex; p0.hintTyre=player.compoundIndex~=nil and player.tyreNames and player.tyreNames[player.compoundIndex] or ''
  local others={}
  for _,index in ipairs(player.dryList or {}) do if index~=player.compoundIndex and player.tyreNames and player.tyreNames[index] then others[#others+1]=player.tyreNames[index] end end
  p0.hintOthers=others
 end
 -- Annonces du pont (SpotterEnginer) : au début du rappel d'avant l'entrée (une fois par approche) et de l'avis de
 -- stratégie au départ ; stratégie au même composé : celle-ci à la place du rappel.
 local planNotice=owed and e.pitplan.state=='same' and now<e.pitplan.noticeUntil
 local fitted=player and player.compoundIndex or -1
 -- Beta 1.50 : stratégie corrigée (même composé, puis un autre) : annoncée une fois au pont (SpotterEnginer).
 if e.pitplan.fixed then e.pitplan.fixed=false; if owed then e.announce('pitPlanOk',fitted,e.pitplan.plannedIndex or -1) end end
 if hint and not e.incidents.playerPitHint then
  if owed and e.pitplan.state=='same' then e.announce('pitPlanSame',fitted,e.pitplan.plannedIndex or fitted) else e.announce('pitCompound',fitted,-1) end
 elseif planNotice and not e.incidents.playerPlanNotice then e.announce('pitPlanSame',fitted,e.pitplan.plannedIndex or fitted) end
 e.incidents.playerPitHint=hint
 e.incidents.playerTyre=e.pits.hintTyre; e.incidents.playerTyreOthers=e.pits.hintOthers
 e.incidents.playerPlan=owed and e.pitplan.state or ''; e.incidents.playerPlanned=e.pitplan.planned
 e.incidents.playerPlanNotice=planNotice
 e.incidents.playerPitNotice=now<e.pits.playerNoticeUntil and e.pits.playerNotice or ''
 e.incidents.playerPitFrom=e.pits.playerNoticeFrom; e.incidents.playerPitTo=e.pits.playerNoticeTo
 -- Relecture 1.52 : panneau du joueur décidé après ses pénalités et ses rappels des stands de cette image (avant, ceux de
 -- l'image précédente).
 e.panel.giveBackDue=e.penalties.giveBack>0 and not e.penalties.disqualified
 -- Beta 1.59 : panneau de l'app coupé par le pilote lui-même (pas seulement par des onglets décochés).
 -- Overlay coupé alors que CSP masque encore les drapeaux d'AC : le bandeau les reprend seuls (src/ui.lua).
 e.panel.ownOnly=e.p.flagPanel==false or e.g.overlayEnabled==false and e.cspHidingFlags==true
 Panel.update(e.panel,e.incidents,frame,e.run,e.profile,now,l,e)
 -- Drapeau rouge : toutes les IA rentrent aux stands et y restent. Dépannage d'une IA immobile en piste jusqu'à son
 -- stand : sous drapeau rouge, sous neutralisation, ou bloquée longtemps (commissaires), jamais le joueur.
 local neutral=e.incidents.neutral
 local decide=decisionTime(e,neutral)
 for i=1,frame.count do
  local a=frame.cars[i]; local cmd=e.commands[i]
  cmd.recover=false; cmd.slowCalled=false
  if a.valid and a.control and not a.player and not a.finished and not a.safetyCar then
   if red then cmd.rulePit=not a.inPitBox; cmd.pitHold=a.inPitBox==true
   -- Reprise : chaque IA attend son tour pour quitter son emplacement (ordre du classement).
   -- Sortie des stands échelonnée après un drapeau rouge (relance de course, reprise d'essais ou de qualifications).
   -- Beta 1.48 : sortie conditionnée par la voiture précédente dans l'ordre figé (Incidents.gates).
   elseif e.incidents.gate[i] then cmd.pitHold=a.inPitBox==true end
   local c=e.incidents.cars[i]; local still=c.still
   -- Beta 1.29 : incident hors piste, temps passé sans avancer (une voiture qui patine dans un bac à sable n'est jamais
   -- à l'arrêt assez longtemps) ; drapeau rouge, neutralisation et pleine piste gardent l'immobilisation.
   local stalled=c.incident and not c.onTrack and math.max(still,c.stuckFor or 0) or still
   -- Beta 1.24 : en pleine piste, jamais avant la décision de la direction de course (decisionTime) ; sinon après
   -- K.trackRecoverTime s (20 avant). Hors piste (aucune règle n'en découle) après K.stuckRecoverTime s (90 avant),
   -- jamais pendant sa retenue. Cassée (suspension, moteur ou boîte hors d'usage) : dès K.brokenRecoverTime s, en
   -- piste au plus tôt à la décision de la direction de course.
   local wait=c.onTrack and decide or 0
   local neutralStuck=c.incident and neutral and still>=math.max(K.neutralRecoverTime,wait)
   local trackStuck=c.incident and c.onTrack and not c.holding and e.run.section_accidents and still>=math.max(K.trackRecoverTime,wait)
   local stuck=c.incident and not c.holding and e.run.section_accidents and stalled>=math.max(K.stuckRecoverTime,wait)
   -- Beta 1.59.1 : en piste, voiture en incident qui remue sans avancer (contre un mur, derrière un rail : jamais à
   -- l'arrêt assez longtemps) : dépannée après K.trackWedgedTime s sans s'éloigner de K.stuckRadius m.
   local wedged=c.incident and c.onTrack and not c.holding and e.run.section_accidents and (c.stuckFor or 0)>=math.max(K.trackWedgedTime,wait)
   local broken=c.incident and e.run.section_accidents and stalled>=math.max(K.brokenRecoverTime,wait) and ((a.damageSuspension or 0)>=K.brokenSuspension or (a.engineLife or K.engineLifeNew)<=K.brokenEngine or (a.damageGearbox or 0)>=K.brokenGearbox)
   cmd.recover=not a.pit and (red and still>=K.redRecoverTime or neutralStuck or trackStuck or broken or stuck)
   if wedged and not a.pit then cmd.recover=true end
   cmd.recoverReason=red and 'drapeau rouge' or neutralStuck and 'neutralisation' or broken and 'cassee' or trackStuck and 'en piste' or 'bloquee'
   cmd.recoverStill=(red or neutralStuck or trackStuck) and still or wedged and not stuck and not broken and c.stuckFor or stalled
   -- Beta 1.41 : IA anormalement lente en tête de file depuis K.slowPitTime s et endommagée (suspension, carrosserie) :
   -- hors course, dépannée à son stand (puis réparée, plus bas) ; en course, arrêt demandé (réparée selon les règles),
   -- jamais stands fermés ni sous drapeau rouge.
   local s=e.states[i]
   local damaged=(a.damageSuspension or 0)>=K.slowPitSuspension or (a.damageBody or 0)>=K.slowPitBody
   -- Relecture : en course sans l'onglet Règles (aucune réparation réglementaire), un seul appel par session ; passée
   -- aux stands après l'appel, elle n'est plus appelée.
   if a.pit and s.slowPitAsked then s.slowPitAsked=false; s.slowPitDone=not e.run.section_rules end
   if damaged and (s.abnormalFor or 0)>=K.slowPitTime and not a.pit and e.run.section_accidents then
    local call=false
    if e.profile=='C' then
     -- Relecture 1.52 : appel marqué (cmd.slowCalled), compté par pits.lua et strategy.lua dans la limite d'appels.
     if not red and not e.incidents.pitsClosed and not s.slowPitDone then cmd.rulePit=true; cmd.slowCalled=not a.pit; s.slowPitAsked=true; call=true end
    elseif not cmd.recover then cmd.recover=true; cmd.recoverReason='lente et endommagee'; cmd.recoverStill=s.abnormalFor end
    if not s.slowPitSent then
     s.slowPitSent=true
     U.log(e.log,now,'INFO',string.format('IA anormalement lente: %s endommagee (suspension %.2f, carrosserie %.0f), %s apres %.0f s',a.name,a.damageSuspension or 0,a.damageBody or 0,
      e.profile~='C' and 'ramenee a son stand (le deplacement la repare)' or call and 'arret aux stands demande' or s.slowPitDone and 'deja appelee aux stands cette session, plus de demande' or 'arret aux stands impossible pour l instant',s.abnormalFor),i)
    end
   end
  end
 end
 -- Beta 1.59 : arrêt aux stands pour dégâts (course, essais, qualifications ; réglage damagePit).
 DamagePit.step(e,frame,now,red)
 -- Beta 1.41 : hors course, une IA endommagée à son emplacement (dépannage de l'app ou arrêt natif) est réparée une
 -- fois par passage : elle ne repart plus avec ses dégâts, lente, en tête d'une nouvelle file.
 if e.profile~='C' and e.run.section_accidents then
  for i=1,frame.count do
   local a=frame.cars[i]
   if a.inPitBox and a.valid and a.control and not a.player and not a.safetyCar and Pits.repairTime(a)>0 then e.commands[i].pitRepair=true end
  end
 end
 -- Départ arrêté (Beta 1.34) : formation, feux, départ, après les commandes des stands (retenues à l'emplacement
 -- gardées) ; un faux départ du joueur est une infraction comme une autre (sanction à l'image suivante).
 local launched=Grid.step(e.grid,e.incidents,frame,now,e.commands,e.g.offsetSign,e.runtimeG.seed,e.log,e.states,e.penalties.ai.dq)
 if launched then
  -- Beta 1.35 : protections et prudence de départ de la course aussi à l'extinction d'un départ arrêté.
  e.launchAt=now
  for i=1,frame.count do e.states[i].obstacleSlow=0; frame.cars[i].stopped=0 end
  FirstLap.arm(e,frame,now,'depart arrete')
  -- Beta 1.60 (tranche E) : départ arrêté après le tour de formation : c'est le départ de la course (journal du départ).
  if e.formation.report then e.formation.report=false; startReport(e,frame,now) end
  -- Beta 1.36 : départ arrêté, dépassement permis dès l'extinction (la règle « jusqu'à la ligne » reste aux départs lancés).
  Incidents.lightsOut(e.incidents)
  if launched=='jump' then
   local a=frame.player>0 and frame.cars[frame.player] or nil
   if e.run.playerPenalties and not C.solo(e.profile) and a then e.incidents.jumpUntil=now+K.jumpShow; e.jumpDue=true; e.jumpGoAt=now; e.jumpLap=a.lap or 0
   else U.log(e.log,now,'INFO','faux depart du joueur: sans sanction (penalites du joueur desactivees)',frame.player) end
  end
  -- Beta 1.61 (tranche D, réglage startRealism) : faux départs gradués. Mouvement sur la grille : averti, sans
  -- pénalité ; faux départ : la pénalité d'avant ; flagrant : pénalité x K.jumpFlagrantMult. Jugé un cran plus bas
  -- K.jumpJudgeTime s après l'extinction si le joueur n'est pas devant la place d'où il est parti.
  e.jumpGrade=nil; e.jumpJudgeAt=nil; e.penalties.jumpMult=nil
  if e.run.startRealism and e.grid.jumpGrade then
   local g=e.grid; local grade=g.jumpGrade; local a=frame.player>0 and frame.cars[frame.player] or nil
   if a then
    U.log(e.log,now,'WARN',string.format('faux depart du joueur: %s (%.1f m, %.0f km/h, %.1f s avant l extinction)',grade=='creep' and 'mouvement sur la grille, averti' or grade=='flagrant' and 'faux depart flagrant' or 'faux depart',g.jumpMoved,g.jumpKmh,g.jumpLead),frame.player)
    if e.run.playerPenalties and not C.solo(e.profile) then
     if grade=='creep' then Incidents.message(e.incidents,'jumpWarn',g.jumpMoved,-1)
     else
      e.jumpGrade=grade; e.jumpJudgeAt=now+K.jumpJudgeTime; e.jumpPlace=g.jumpSlot or 0
      if grade=='flagrant' then e.penalties.jumpMult=K.jumpFlagrantMult; Incidents.message(e.incidents,'jumpFlagrant',e.run.penaltySeconds*K.jumpFlagrantMult,-1) end
     end
    end
   end
  end
 end
 -- Faux départ : sanction servie une fois le joueur passé la ligne et à K.jumpServeDistance m (jamais à l'arrêt sur la
 -- grille au milieu des voitures qui partent) ; au plus tard K.jumpServeMax s après l'extinction, mais seulement en roulant
-- ou la ligne passée (Beta 1.36 : jamais à l'arrêt sur la grille, même après un calage).
 if e.jumpDue then
  local a=frame.player>0 and frame.cars[frame.player] or nil
  -- Beta 1.61 (tranche D) : avantage rendu : un cran plus bas, une fois. Finition (relecture) : au moins une place
  -- derrière celle du départ (la pole qui reste en tête n'a rien rendu).
  if e.jumpJudgeAt and a and a.valid and now>=e.jumpJudgeAt then
   e.jumpJudgeAt=nil
   local pos=a.position or 0
   if (e.jumpPlace or 0)>0 and pos>e.jumpPlace then
    e.jumpGrade=Antics.lower(e.jumpGrade)
    U.log(e.log,now,'INFO',string.format('faux depart: %s juge un cran plus bas (avantage rendu, place %d pour %d)',a.name,pos,e.jumpPlace),frame.player)
    if e.jumpGrade=='jump' then e.penalties.jumpMult=nil
    else e.jumpDue=false; e.penalties.jumpMult=nil; e.incidents.jumpUntil=now; Incidents.message(e.incidents,'jumpWarn',e.grid.jumpMoved,-1) end
   end
  end
  if not e.jumpDue then e.jumpJudgeAt=nil
  elseif not a or not a.valid then e.jumpDue=false
  elseif e.jumpJudgeAt then -- Beta 1.61 : servie seulement une fois rejugée (K.jumpJudgeTime s après l'extinction)
  elseif (a.lap or 0)>e.jumpLap and a.spline*frame.length>=K.jumpServeDistance or now-e.jumpGoAt>=K.jumpServeMax and ((a.lap or 0)>e.jumpLap or a.kmh>K.gridStillKmh) then e.jumpDue=false; e.penalties.jumpPending=true end
 end
 -- Formation de la grille et feux : aucun arrêt aux stands demandé (la voie des stands longe la grille).
 if e.incidents.standing=='grid' or e.incidents.standing=='lights' then
  for i=1,frame.count do local cmd=e.commands[i]; if not frame.cars[i].pit then cmd.rulePit=false; cmd.weatherPit=false; cmd.slowCalled=false end end
 end
 -- Carburant des arrêts forcés, une fois toutes les demandes d'arrêt connues (règles, météo, drapeau rouge).
 Pits.fuel(e.pits,frame,e.commands,e.run,e.profile,now,red)
 for i=1,K.maxCars do local cmd=e.commands[i]; cmd.scPark=false; cmd.scSpeed=K.unlimitedSpeed; cmd.parkReason='sc'; cmd.scRelease=false end
 Incidents.safety(e.incidents,e.commands,e.run,frame,e.delta,e.states)
 -- Voitures de réserve du modèle de la voiture de sécurité : garées aux stands dans toutes les sessions.
 for i=1,frame.count do if frame.cars[i].safetyCar and i~=e.incidents.safety then local cmd=e.commands[i]; cmd.scPark=true; cmd.parkReason='spare' end end
 for i=1,K.maxCars do e.commands[i].scSkin=false end
 local sc=e.incidents.safety>0 and frame.cars[e.incidents.safety]
 if sc and sc.skinKnown and not sc.skinSafety then e.commands[e.incidents.safety].scSkin=true end
 -- IA sanctionnées : pied levé quelques secondes ; disqualifiée, ramenée à son stand et garée jusqu'à la fin.
 local ai=e.penalties.ai
 for i=1,frame.count do
  local cmd=e.commands[i]
  if ai.dq[i] then cmd.scPark=true; cmd.parkReason='dq'; e.states[i].disqualified=true
  -- Pied levé progressif : jamais de freinage brusque devant la voiture tout juste doublée.
  elseif now<(ai.slowUntil[i] or 0) then cmd.yellowLimit=math.min(cmd.yellowLimit,math.max(ai.slowKmh[i],ai.slowFrom[i]-K.aiPenaltyDecel*3.6*(now-ai.slowAt[i]))) end
  -- Place à rendre (dépassement pendant la transition) : levée de pied franche (décélération d'approche) sous l'allure
  -- de la voiture doublée, pour la laisser repasser avant l'échéance.
  local back=ai.giveBack[i] or 0
  if back>0 and not ai.dq[i] then
   if not ai.giveFrom[i] then ai.giveFrom[i]=frame.cars[i].kmh; ai.giveAt[i]=now end
   local target=math.max(K.trafficMinSpeed,frame.cars[back].kmh-K.giveBackDrop)
   cmd.yellowLimit=math.min(cmd.yellowLimit,math.max(target,ai.giveFrom[i]-e.run.yellowDecel*3.6*(now-ai.giveAt[i])))
  else ai.giveFrom[i]=nil; ai.giveAt[i]=nil end
 end
 -- Beta 1.42 : sanctions des IA (limites de piste, virage coupé, procédure, contresens, purge, place à rendre).
 Sanctions.update(e.sanctions,e,frame,now,dt)
 -- Beta 1.62 : priorité dans la voie des stands (dernier à écrire cmd.pitHold).
 if not e.incidents.red then Pits.releaseGuard(e.pits,frame,e.commands,now,e.log) end
 -- Beta 1.56 : vos limites de piste gérées par l'app alors que les pénalités d'AC sont actives (lues une fois par
 -- session) : prévenu une fois (journal, accueil, overlay), la règle de l'app continue (décision du pilote).
 if not e.acPenaltyChecked and e.run.sanPlayerTrackLimits and C.on(e.p,'sanctions') and (e.profile=='P' or e.profile=='Q' or e.profile=='C') then
  e.acPenaltyChecked=true
  if frame.penaltiesEnabled==true then
   e.acPenaltyWarned=true
   U.log(e.log,now,'WARN',string.format('limites de piste joueur: penalites d AC actives (roues dehors autorisees %s), coupez-les dans Content Manager pour eviter une double sanction',
    frame.allowedTyresOut~=nil and tostring(frame.allowedTyresOut) or '?'),-1)
   Incidents.message(e.incidents,'playerSanction',0,0,L.acPenaltiesOnShort)
  end
 end
 -- Beta 1.49 : annonce de l'arrêt F1 écartée dans une image déjà prise : publiée ici, à l'image suivante libre.
 Incidents.flushHeld(e.incidents,now)
 -- Beta 1.60 : fin de l'image. Positions et verdicts des collisions, puis régulateur sans coup de frein, en dernier :
 -- il borne les ralentissements que l'app vient d'écrire devant une voiture collée.
 Blame.sample(e.blame,e,frame,now,dt)
 Blame.settle(e.blame,e,frame,now)
 Rear.govern(e.rear,e,frame,now,dt)
 return true
end
return M
