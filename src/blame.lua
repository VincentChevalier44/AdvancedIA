-- Beta 1.60 (tranche B, réglages sanContact et sanPlayerContact, coupés par défaut) : responsabilité des collisions.
-- Décisions pures : aucune fonction de CSP, aucune commande écrite ; les sanctions passent par src/sanctions.lua.
-- M.contact : appelé par src/engine.lua pour chaque voiture i dont CSP signale un contact avec j à cette image (pour i
-- et pour j quand les deux le signalent) ; ouvre un dossier par paire. M.sample : fin de l'image, positions latérales
-- récentes, retours en piste, suites du contact. M.settle : verdict K.blameOutcome s après le contact.
-- Règle du pilote : dans un virage, la voiture dont le nez est derrière est en tort ; en ligne droite, celle qui percute
-- par l'arrière, ou celle qui change de ligne ; quand ce n'est pas clair, c'est un incident de course. Un faux verdict
-- est pire qu'aucun verdict : départ, voiture accidentée, arrêtée, hors piste ou en travers, carambolage, frottement
-- sans suite, nez à égalité, neutralisation : personne n'est en tort.
-- Aucune table ni chaîne créée par image : dossiers et historiques alloués une fois.
local U=require('src/util')
local C=require('src/config')
local Perception=require('src/perception')
local Priority=require('src/priority')
local Sanctions=require('src/sanctions')
local K=C.K
local abs,max,huge=math.abs,math.max,math.huge
local M={}
-- Historique des positions latérales : K.blameCutTime s au pas de K.blameSample s, plus un échantillon.
local SAMPLES=8
local CASES=24
local function case() return {open=false,i=0,j=0,key=0,at=0,dueAt=0,fault=0,situation='',diff=0,lostI=false,lostJ=false,placeI=0,placeJ=0,waiting=false,outAll=true,idI='',idJ=''} end
function M.new()
 local t={session=-1,raceGen=nil,sampleAt=-huge,head=0,filled=0,lat={},mid={},off={},rejoinAt={},hitAt={},hitBy={},cases={},open=0,pairUntil={},
  rel={index=0,long=0,lat=0,gap=0,sa=0,ttc=huge,same=false,alongside=false}}
 for i=1,K.maxCars do
  t.off[i]=false; t.rejoinAt[i]=-huge; t.hitAt[i]=-huge; t.hitBy[i]=0
  for k=1,SAMPLES do t.lat[(i-1)*SAMPLES+k]=huge; t.mid[(i-1)*SAMPLES+k]=huge end
 end
 for k=1,CASES do t.cases[k]=case() end
 return t
end
local function clear(t)
 for i=1,K.maxCars do
  t.off[i]=false; t.rejoinAt[i]=-huge; t.hitAt[i]=-huge; t.hitBy[i]=0
  for k=1,SAMPLES do t.lat[(i-1)*SAMPLES+k]=huge; t.mid[(i-1)*SAMPLES+k]=huge end
 end
 for k=1,CASES do t.cases[k].open=false end
 for key in pairs(t.pairUntil) do t.pairUntil[key]=nil end
 t.open=0; t.head=0; t.filled=0; t.sampleAt=-huge
end
function M.reset(t) t.session=-1; t.raceGen=nil; clear(t) end -- (t,now)
function M.rebase(t,amount)
 t.sampleAt=t.sampleAt-amount
 for i=1,K.maxCars do t.rejoinAt[i]=t.rejoinAt[i]-amount; t.hitAt[i]=t.hitAt[i]-amount end
 for key,v in pairs(t.pairUntil) do t.pairUntil[key]=v-amount end
 for k=1,CASES do local c=t.cases[k]; c.at=c.at-amount; c.dueAt=c.dueAt-amount end
end
-- Jugement en service : un des deux réglages, en essais, qualifications ou course (jamais en journée circuit ni en
-- hotlap : la section des sanctions y est masquée).
function M.active(e)
 local p=e.run; local profile=e.profile
 return p~=nil and (p.sanContact==true or p.sanPlayerContact==true and profile=='C') and (profile=='C' or profile=='P' or profile=='Q')
end
local active=M.active
-- Déplacement latéral signé de la voiture i sur les K.blameCutTime dernières secondes (m, repère de la piste) ; nil
-- quand l'historique est trop court ou qu'une position manque (jamais de verdict sur une donnée inconnue).
local function moved(t,i)
 local back=math.ceil(K.blameCutTime/K.blameSample)
 if t.filled<=back or back>=SAMPLES then return nil end
 local base=(i-1)*SAMPLES
 local newest=t.lat[base+t.head]; local oldest=t.lat[base+(t.head-back-1)%SAMPLES+1]
 if newest==huge or oldest==huge then return nil end
 -- Relecture : l'écart est mesuré par rapport à la trajectoire ; quand la trajectoire elle-même traverse la piste
 -- (milieu de piste déplacé de plus de K.blameMoveMin/2 m sur la fenêtre), une voiture qui roule droit semble
 -- changer de ligne : déplacement inconnu, jamais un verdict.
 local midNew=t.mid[base+t.head]; local midOld=t.mid[base+(t.head-back-1)%SAMPLES+1]
 if midNew==huge or midOld==huge or abs(midNew-midOld)>K.blameMoveMin*0.5 then return nil end
 return newest-oldest
end
-- Voiture qui ne peut pas être jugée ni servir de repère : accidentée (incident de l'app), arrêtée ou au pas, hors piste.
local function wrecked(e,frame,i)
 local a=frame.cars[i]; local ic=e.incidents.cars[i]
 return ic~=nil and ic.incident==true or a.offtrack==true or a.kmh<(e.run.obstacleSpeedKmh or 25)
end
local function lost(e,frame,i)
 local a=frame.cars[i]; local ic=e.incidents.cars[i]
 return ic~=nil and ic.incident==true or a.offtrack==true
end
local function name(a) return a.name~='' and a.name or a.id or '?' end
-- Verdict à l'instant du contact (table du schéma, première ligne qui s'applique) : indice de la voiture en tort (0 :
-- personne) et situation (texte du journal).
local function judge(t,e,frame,i,j,now)
 local a,b=frame.cars[i],frame.cars[j]; local p=e.run; local inc=e.incidents
 local rel=Perception.relative(a,b,frame.length,t.rel)
 local side=abs(rel.lat)>=(a.width+b.width)*0.5
 -- Voiture de derrière (rear) et de devant (front) : b est devant a quand rel.long est positif.
 local rear,front=i,j
 if rel.long<0 then rear,front=j,i end
 local diff=abs(a.kmh-b.kmh)
 if inc.red or inc.neutral then return 0,'indetermine' end
 -- Départ : K.blameStartGrace s après les feux (ou départ arrêté de l'app en cours), sauf un choc par l'arrière à plus
 -- de K.blameStartKmh km/h d'écart, jugé comme en course.
 -- Relecture : départ lancé après un tour de formation ou une relance (e.launchAt), comme src/engine.lua.
 local starting=e.profile=='C' and (not frame.started or now-max(e.startedAt,e.launchAt or -huge)<K.blameStartGrace or inc.standing~=nil and inc.standing~='none' and inc.standing~='go')
 if starting and (side or diff<=K.blameStartKmh) then return 0,'depart' end
 -- Voiture accidentée, arrêtée, hors piste ou en travers, ou déjà touchée par une troisième voiture (carambolage : seul
 -- le premier contact est jugé).
 local chainI=now-t.hitAt[i]<=K.blameChain and t.hitBy[i]~=j and t.hitBy[i]~=0
 local chainJ=now-t.hitAt[j]<=K.blameChain and t.hitBy[j]~=i and t.hitBy[j]~=0
 if wrecked(e,frame,i) or wrecked(e,frame,j) or not rel.same or chainI or chainJ then return 0,'voiture accidentee' end
 -- Retour en piste depuis moins de K.blameRejoin s : la voiture qui revient (les deux : indéterminé).
 local backI,backJ=now-t.rejoinAt[i]<=K.blameRejoin,now-t.rejoinAt[j]<=K.blameRejoin
 if backI and backJ then return 0,'indetermine' end
 if backI then return i,'retour en piste' end
 if backJ then return j,'retour en piste' end
 -- Virage jugé sur la piste (relecture) : rotation de la voiture (formule de a.corner, src/director.lua, recalculée ici
 -- pour le joueur aussi) ou accélération latérale d'au moins K.blameCornerG m/s². Le freinage seul ne fait un « virage »
 -- que côte à côte (entrée de virage, règle de la priorité), et jamais dans une zone de drapeau jaune local : une
 -- voiture qui freine en ligne droite pour un jaune n'est pas dans un virage.
 local yawA,yawB=abs(a.yawRate or 0),abs(b.yawRate or 0)
 local curve=1-yawA/p.cornerYawRef<p.cornerMin or yawA*a.speed>=K.blameCornerG or 1-yawB/p.cornerYawRef<p.cornerMin or yawB*b.speed>=K.blameCornerG
 local si,sj=e.states[i],e.states[j]
 local yellowZone=si~=nil and si.yellow==true or sj~=nil and sj.yellow==true
 local corner=curve or not yellowZone and ((a.brake or 0)>=K.passBrakeMax or (b.brake or 0)>=K.passBrakeMax)
 local movedI,movedJ=moved(t,i),moved(t,j)
 if not side then
  -- Voiture de devant anormalement lente (endommagée, au ralenti) : comme une voiture accidentée, personne en tort.
  local sf=e.states[front]
  if sf~=nil and sf.abnormal==true then return 0,'voiture accidentee' end
  if curve then return rear,'virage nez derriere' end
  -- Ligne droite, choc par l'arrière : la voiture de derrière, sauf si celle de devant vient de changer de ligne. Tant
  -- que le déplacement latéral des deux voitures n'est pas connu (historique trop court, lecture manquée) : indéterminé,
  -- jamais un verdict (relecture : sans cette donnée, la voiture de derrière était toujours en tort, vous compris).
  local mf=front==i and movedI or movedJ; local mr=rear==i and movedI or movedJ
  if not (mf and mr) then return 0,'indetermine' end
  if abs(mf)>=K.blameMoveMin and abs(mf)>=K.blameMoveRatio*abs(mr) then return front,'ligne droite changement de ligne' end
  return rear,'ligne droite choc par l arriere'
 end
 if corner then
  -- Côte à côte en virage : le nez derrière de plus de K.cornerNoseMargin m cède (formule de la priorité au virage).
  local nose=Priority.nose(a,b,rel.long)
  if nose>K.cornerNoseMargin then return i,'virage nez derriere' end
  if nose<-K.cornerNoseMargin then return j,'virage nez derriere' end
  return 0,'nez a egalite'
 end
 -- Côte à côte en ligne droite : la voiture qui s'est déplacée vers l'autre (au moins K.blameMoveMin m, et
 -- K.blameMoveRatio fois plus que l'autre) ; une voiture tenue sur sa ligne pour un attaquant engagé et qui a bougé
 -- vers lui est en tort sans la comparaison.
 if not (a.trackLatValid and b.trackLatValid and movedI and movedJ) then return 0,'indetermine' end
 local towards=b.trackLat>=a.trackLat and 1 or -1
 local mi,mj=movedI*towards,-movedJ*towards
 local heldI,heldJ=Priority.held(e.states[i],now)==j,Priority.held(e.states[j],now)==i
 local faultI=mi>=K.blameMoveMin and (heldI or mi>=K.blameMoveRatio*max(0,mj))
 local faultJ=mj>=K.blameMoveMin and (heldJ or mj>=K.blameMoveRatio*max(0,mi))
 if faultI and not faultJ then return i,'ligne droite changement de ligne' end
 if faultJ and not faultI then return j,'ligne droite changement de ligne' end
 return 0,'indetermine'
end
function M.contact(t,e,frame,i,j,now)
 if not active(e) then return end
 local a,b=frame.cars[i],frame.cars[j]
 -- Jamais dans la voie des stands, ni avec la voiture de sécurité ou une voiture arrivée.
 if a.pit or b.pit or a.safetyCar or b.safetyCar or a.finished or b.finished then return end
 -- Sans le jugement des IA : seulement les contacts où vous êtes en cause.
 if not e.run.sanContact and not (a.player or b.player) then return end
 local key=i<j and i*K.maxCars+j or j*K.maxCars+i
 local busy=t.pairUntil[key]
 if busy and now<busy and busy-now<=K.blameOutcome+K.blamePairGap then
  -- Contact qui dure : un seul dossier par paire, rouvert K.blamePairGap s après la dernière image de contact.
  t.pairUntil[key]=max(busy,now+K.blamePairGap); t.hitAt[i]=now; t.hitAt[j]=now
  return
 end
 local slot=nil
 for k=1,CASES do if not t.cases[k].open then slot=t.cases[k]; break end end
 local fault,situation=judge(t,e,frame,i,j,now)
 t.hitAt[i]=now; t.hitBy[i]=j; t.hitAt[j]=now; t.hitBy[j]=i
 t.pairUntil[key]=now+K.blameOutcome
 if not slot then return end
 slot.open=true; slot.i=i; slot.j=j; slot.key=key; slot.at=now; slot.dueAt=now+K.blameOutcome; slot.fault=fault; slot.situation=situation
 slot.diff=abs(a.kmh-b.kmh); slot.lostI=false; slot.lostJ=false; slot.placeI=a.position or 0; slot.placeJ=b.position or 0; slot.waiting=false; slot.outAll=true
 slot.idI=a.identity or a.id or ''; slot.idJ=b.identity or b.id or ''
 t.open=t.open+1
end
function M.sample(t,e,frame,now)
 if not active(e) then
  if t.open>0 or t.filled>0 then clear(t) end
  return
 end
 -- Nouvelle session ou course relancée dans la même session : dossiers et historiques oubliés.
 if t.session~=frame.session or t.raceGen~=e.raceGen then clear(t); t.session=frame.session; t.raceGen=e.raceGen end
 if now-t.sampleAt<K.blameSample and now>=t.sampleAt then return end
 t.sampleAt=now
 t.head=t.head%SAMPLES+1; if t.filled<SAMPLES then t.filled=t.filled+1 end
 for i=1,math.min(frame.count,K.maxCars) do
  local a=frame.cars[i]
  local known=a.valid and a.trackLatValid==true and not a.teleport
  t.lat[(i-1)*SAMPLES+t.head]=known and a.trackLat or huge
  -- Milieu de la piste par rapport à la trajectoire (m) ; largeurs inconnues : inconnu.
  t.mid[(i-1)*SAMPLES+t.head]=known and (a.leftWidth or 0)>0 and (a.rightWidth or 0)>0 and (a.rightWidth-a.leftWidth)*0.5 or huge
  if a.teleport or not a.valid then t.off[i]=false; t.rejoinAt[i]=-huge; for k=1,SAMPLES do t.lat[(i-1)*SAMPLES+k]=huge; t.mid[(i-1)*SAMPLES+k]=huge end
  else
   local off=a.offtrack==true and not a.pit
   if t.off[i] and not off and not a.pit then t.rejoinAt[i]=now end
   t.off[i]=off
  end
 end
 -- Suites du contact pour les dossiers ouverts : perte de contrôle, sortie de piste (les places sont lues au verdict).
 if t.open>0 then
  for k=1,CASES do
   local c=t.cases[k]
   if c.open then
    if lost(e,frame,c.i) then c.lostI=true end
    if lost(e,frame,c.j) then c.lostJ=true end
    if c.waiting then
     local victim=c.fault==c.i and c.j or c.i
     if not wrecked(e,frame,victim) then c.outAll=false end
    end
   end
  end
 end
end
local function close(t,c) c.open=false; c.waiting=false; t.open=max(0,t.open-1) end
local function incident(t,e,frame,c,situation,now)
 e.stats.blameJudged=(e.stats.blameJudged or 0)+1; e.stats.blameIncident=(e.stats.blameIncident or 0)+1
 U.log(e.log,now,'INFO',string.format('incident de course: contact %s / %s (%s)',name(frame.cars[c.i]),name(frame.cars[c.j]),situation),c.i)
 close(t,c)
end
function M.settle(t,e,frame,now)
 if t.open==0 then return end
 if not active(e) then return end
 for k=1,CASES do
  local c=t.cases[k]
  if c.open and (now>=c.dueAt or c.dueAt-now>K.blameOutcome+K.blameOutTime) then
   local a,b=frame.cars[c.i],frame.cars[c.j]
   -- Voiture remplacée, téléportée aux stands ou disparue depuis le contact : dossier abandonné sans verdict.
   if c.i>frame.count or c.j>frame.count or not a.valid or not b.valid or (a.identity or a.id or '')~=c.idI or (b.identity or b.id or '')~=c.idJ then close(t,c)
   elseif c.diff<K.blameMinKmh and not c.lostI and not c.lostJ then incident(t,e,frame,c,'contact leger',now)
   elseif c.fault==0 then incident(t,e,frame,c,c.situation,now)
   else
    local fault=c.fault; local victim=fault==c.i and c.j or c.i
    local fa=frame.cars[fault]; local va=frame.cars[victim]
    -- Le fautif n'est pas jugé : vous sans votre réglage (ou hors course), une IA sans le sien.
    local judged
    if fa.player then judged=e.run.sanPlayerContact==true and e.profile=='C' else judged=e.run.sanContact==true and fa.control==true end
    if not judged then incident(t,e,frame,c,'non juge',now)
    else
     local before=victim==c.i and c.placeI or c.placeJ; local after=va.position or 0
     local victimLost=victim==c.i and c.lostI or victim==c.j and c.lostJ
     local serious=victimLost or before>0 and after>0 and after-before>=K.blamePlaces
     if serious and not c.waiting and wrecked(e,frame,victim) and now-c.at<K.blameOutTime then
      -- Contact grave et victime encore arrêtée : verdict attendu jusqu'à K.blameOutTime s (drive-through si elle ne
      -- repart pas).
      c.waiting=true; c.outAll=true; c.dueAt=c.at+K.blameOutTime
     else
      local out=serious and c.waiting and c.outAll and wrecked(e,frame,victim)
      e.stats.blameJudged=(e.stats.blameJudged or 0)+1; e.stats.blameFault=(e.stats.blameFault or 0)+1
      U.log(e.log,now,'INFO',string.format('responsabilite: contact %s / %s, %s : %s en tort (%s)',name(a),name(b),c.situation,name(fa),serious and 'grave' or 'leger'),fault)
      close(t,c)
      Sanctions.contact(e.sanctions,e,frame,fault,serious,out,now)
     end
    end
   end
  end
 end
end
return M
