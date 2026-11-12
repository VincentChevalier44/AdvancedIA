-- Beta 1.61 (tranche B, réglage global trackMemory, coupé par défaut) : mémoire du circuit. L'allure libre apprise
-- par les IA (une vitesse par endroit du tour) est gardée par circuit, tracé et modèle de voiture, avec le temps perdu
-- aux stands de la 1.60, et relue à la session suivante.
-- Un a priori, jamais un remplacement : la session apprend de zéro comme avant ; l'allure gardée n'est consultée que
-- là où rien n'est encore connu (src/director.lua : s.prior × s.priorRatio en dernier repli ; src/delta.lua :
-- s.priorMap ; src/classes.lua : s.priorMean). Ce que la session apprend gagne toujours.
-- Jamais gardé ni utilisé : piste mouillée, en ligne, rediffusion, circuit sans clé de fichier, nombre d'endroits ou
-- longueur différents de ceux du fichier.
-- Décisions pures, aucun accès aux fichiers ici : le module demande (t.ioRead, t.ioWrite) et l'hôte (AdvancedIA.lua)
-- lit et écrit par Applier.trackFileRead / trackFileWrite, puis rend la main par M.loaded / M.written.
-- Rien de ce qui est lu n'est cru : chaque contrôle écarte le fichier entier ou le modèle fautif ; moyennes et
-- comptes recalculés, jamais lus. Vieillissement par le numéro de série du fichier, jamais par l'horloge.
-- Coupé : aucune lecture, aucune écriture, aucun champ posé, aucune allocation par image.
local U=require('src/util')
local C=require('src/config')
local TrackFile=require('src/trackfile')
local Delta=require('src/delta')
local Pitloss=require('src/pitloss')
local K=C.K
local floor,min,max,abs=math.floor,math.min,math.max,math.abs
local M={}
local KIND='pace'
function M.new()
 return {session=-1,on=false,key='',track='',layout='',length=0,bins=0,loaded=false,asked=false,models={},order={},serial=0,pit=nil,
  wet=0,total=0,tick=0,counted=false,slot={},lastSave=0,learnt=0,savedLearnt=-1,slow=false,saving=nil,ioRead=nil,ioWrite=nil,ioKey=nil,
  used=0,known=0,unknown=0,startLogged=false,place='',forgetWanted=false,status='',scratch={},values={}}
end
-- Nouvelle session : ce qui est gardé du circuit reste (même fichier) ; les compteurs de la session repartent.
function M.reset(t)
 t.session=-1; t.wet=0; t.total=0; t.tick=0; t.counted=false; t.learnt=0; t.savedLearnt=-1; t.saving=nil; t.used=0; t.startLogged=false
 for i=#t.slot,1,-1 do t.slot[i]=nil end
end
function M.rebase(t,amount) if U.finite(t.lastSave) then t.lastSave=t.lastSave-amount end; if U.finite(t.tick) then t.tick=t.tick-amount end end
local function log(e,now,level,text) U.log(e.log,now,level,text,-1) end
local function detach(e)
 for i=1,K.maxCars do local s=e.states[i]; if s.priorMap~=nil or s.prior~=nil then s.prior=nil; s.priorMap=nil; s.priorMean=nil; s.priorRatio=nil; s.priorN=0 end end
end
local function forgetAll(t)
 t.models={}; for i=#t.order,1,-1 do t.order[i]=nil end
 t.pit=nil; t.serial=0; t.loaded=false; t.asked=false; t.saving=nil; t.counted=false
 for i=#t.slot,1,-1 do t.slot[i]=nil end
end
local function modelName(name)
 if type(name)~='string' then return false end
 local plain=name:match('^player:(.+)$') or name
 return #plain>=1 and #plain<=K.paceMapNameMax and plain:match('^[%w_%-%.]+$')~=nil
end
M.modelName=modelName
-- Moyenne et nombre d'endroits connus d'une carte : toujours recalculés.
local function measure(data,bins)
 local sum,n=0,0
 for b=1,bins do local v=data[b]; if v>0 then sum=sum+v; n=n+1 end end
 return n>0 and sum/n or 0,n
end
-- Une carte : bins × 3 chiffres hexadécimaux, la vitesse en 0,1 m/s (000 : inconnue).
function M.encode(data,bins)
 local parts={}
 local cap=K.paceMapMaxSpeed
 for b=1,bins do
  local v=data[b] or 0
  if not (v>0) then v=0 end
  parts[b]=string.format('%03X',min(cap,floor(v*10+0.5)))
 end
 return table.concat(parts)
end
-- Lecture d'une carte : le tableau, ou nil et la raison ('longueur', 'chiffres', 'vitesse', 'endroits').
function M.decode(text,bins)
 if type(text)~='string' or #text~=bins*3 then return nil,'longueur' end
 if text:find('%X') then return nil,'chiffres' end
 local data={}
 for b=1,bins do
  local v=tonumber(text:sub(b*3-2,b*3),16)
  if v>K.paceMapMaxSpeed then return nil,'vitesse' end
  data[b]=v/10
 end
 -- Valeur isolée (écart de plus de K.paceMapSpike à la médiane de ses quatre voisins connus) : inconnue.
 local out={}
 for b=1,bins do
  local v=data[b]; out[b]=v
  if v>0 then
   local n=0; local w={}
   for d=-2,2 do if d~=0 then local x=data[(b-1+d)%bins+1]; if x>0 then n=n+1; w[n]=x end end end
   if n==4 then
    table.sort(w); local median=(w[2]+w[3])/2
    if abs(v-median)>K.paceMapSpike*median then out[b]=0 end
   end
  end
 end
 local mean,count=measure(out,bins)
 if count<K.paceMapMinShare*bins then return nil,'endroits' end
 return out,nil,mean,count
end
local function addModel(t,name,model)
 if not t.models[name] then t.order[#t.order+1]=name end
 t.models[name]=model
end
-- Fichier lu par l'hôte (text nil : aucun fichier). Rend true si quelque chose est connu.
function M.loaded(t,e,text,place)
 local now=e.time
 t.loaded=true; t.place=place or ''
 t.models={}; for i=#t.order,1,-1 do t.order[i]=nil end
 t.pit=nil; t.serial=0
 if place=='big' then log(e,now,'WARN','memoire du circuit: fichier ignore (taille)'); return false end
 if type(text)~='string' then log(e,now,'INFO','memoire du circuit: rien de connu pour '..t.key); return false end
 local doc,why=TrackFile.parse(text,K.paceMapMaxBytes)
 if not doc then log(e,now,'WARN','memoire du circuit: fichier ignore ('..(why=='big' and 'taille' or why=='format' and 'format' or 'syntaxe')..')'); return false end
 local ok,lengthOK=TrackFile.check(doc,KIND,t.track,t.layout,t.length)
 if not ok then log(e,now,'WARN','memoire du circuit: fichier ignore ('..(lengthOK=='kind' and 'format' or 'circuit')..')'); return false end
 if not lengthOK then log(e,now,'WARN','memoire du circuit: fichier ignore (longueur)'); return false end
 if TrackFile.integer(doc.head.bins,1,K.paceBinsMax)~=t.bins then log(e,now,'WARN','memoire du circuit: fichier ignore (endroits)'); return false end
 local serial=TrackFile.serial(doc)
 if serial>K.paceMapSerialMax then log(e,now,'WARN','memoire du circuit: fichier ignore (format)'); return false end
 t.serial=serial
 local sessions=0
 for _,section in ipairs(doc.sections) do
  local v=section.values
  if section.name=='pit' then
   local lane=TrackFile.number(v.laneTime,K.pitLossMin,K.pitLossMax); local frac=TrackFile.number(v.frac,0,1); local samples=TrackFile.integer(v.samples,1,K.paceMapSerialMax)
   if lane and frac and frac>0 and frac<1 and samples then t.pit={laneTime=lane,frac=frac,samples=samples} end
  else
   local name=section.name:match('^model%.(.+)$')
   if name then
    local why2
    if not modelName(name) then why2='nom'
    elseif #t.order>=K.paceMapModels then why2='trop de modeles'
    else
     local count=TrackFile.integer(v.sessions,0,K.paceMapSerialMax); local last=TrackFile.integer(v.last,0,K.paceMapSerialMax)
     if not count or not last or last>serial then why2='compteurs'
     else
      local data,bad,mean,n=M.decode(v.data,t.bins)
      if not data then why2=bad
      else addModel(t,name,{base=data,data=data,mean=mean,count=n,sessions=count,last=last,text=nil}); sessions=max(sessions,count) end
     end
    end
    if why2 then log(e,now,'WARN',string.format('memoire du circuit: modele %s ignore (%s)',modelName(name) and name or '?',why2)) end
   end
  end
 end
 if #t.order==0 and not t.pit then log(e,now,'INFO','memoire du circuit: rien de connu pour '..t.key); return false end
 log(e,now,'INFO',string.format('memoire du circuit: %s, allure de %d modele(s) (%d session(s)), temps aux stands %.1f s',t.key,#t.order,sessions,t.pit and t.pit.laneTime or -1))
 return true
end
local function slotName(a) return (a.player and 'player:' or '')..tostring(a.id or '') end
-- Allure gardée posée sur chaque voiture selon son modèle (une fois par seconde) ; rythme de la voiture contre cette
-- allure appris là où elle a déjà roulé seule (s.priorRatio), l'a priori n'étant donné au directeur qu'ensuite.
local function attach(t,e,frame)
 local dry=(frame.wet or 0)<=K.priorWetMax
 local used,known,unknown=0,0,0
 for i=1,frame.count do
  local a=frame.cars[i]; local s=e.states[i]
  if a.valid and not a.safetyCar then
   local name=slotName(a)
   if t.slot[i]~=name then t.slot[i]=name; s.prior=nil; s.priorMap=nil; s.priorMean=nil; s.priorRatio=nil; s.priorN=0 end
   -- Modèle créé dans cette session (pas de carte lue) : ce n'est pas un a priori, c'est la session elle-même.
   local model=dry and t.models[name] or nil
   if model and model.base then
    known=known+1
    s.priorMap=model.base; s.priorMean=model.mean
    local b=Delta.bin(a.spline or 0,t.bins)
    local own=s.pace[b] or 0; local kept=model.base[b] or 0
    if own>0 and kept>0 and a.splineValid then
     local ratio=U.clamp(own/kept,K.priorRatioLow,K.priorRatioHigh)
     s.priorRatio=(s.priorN or 0)>0 and s.priorRatio+(ratio-s.priorRatio)*K.priorRatioAlpha or ratio
     s.priorN=(s.priorN or 0)+1
    end
    if s.paceCount>=K.priorRatioMin and (s.priorN or 0)>0 then s.prior=model.base; used=used+1 else s.prior=nil end
   else
    if not a.player then unknown=unknown+1 end
    if s.priorMap~=nil or s.prior~=nil then s.prior=nil; s.priorMap=nil; s.priorMean=nil; s.priorRatio=nil; s.priorN=0 end
   end
  end
 end
 t.used=used; t.known=known; t.unknown=unknown
end
-- Valeur de la session pour un modèle : médiane, à chaque endroit, des voitures du modèle qui l'ont apprise (voiture
-- anormalement lente écartée). Rend la part du tour apprise.
local function sessionMap(t,e,name,out)
 local cars=t.scratch; local n=0
 for i=1,K.maxCars do
  if t.slot[i]==name then local s=e.states[i]; if s.paceCount>=K.paceMinBins and (s.abnormalFor or 0)<=0 then n=n+1; cars[n]=s end end
 end
 local w=t.values; local seen=0
 for b=1,t.bins do
  local k=0
  for j=1,n do local v=cars[j].pace[b] or 0; if v>0 then k=k+1; local at=k-1; while at>=1 and w[at]>v do w[at+1]=w[at]; at=at-1 end; w[at+1]=v end end
  if k>0 then out[b]=w[floor(k/2)+1]; seen=seen+1 else out[b]=0 end
 end
 for j=1,n do cars[j]=nil end
 return seen/max(1,t.bins)
end
-- Fusion légère d'un modèle : gardé + (session − gardé) × K.paceMapAlpha, toujours depuis la carte lue au chargement
-- (une sauvegarde répétée dans la même session ne cumule pas) ; valeur trop basse ignorée, trop haute bornée.
function M.mergeModel(t,e,name)
 local session={}
 local share=sessionMap(t,e,name,session)
 if share<K.paceMapMinShare then return false end
 local model=t.models[name]
 local serial=t.serial+1
 if not model then
  local mean,count=measure(session,t.bins)
  addModel(t,name,{base=nil,data=session,mean=mean,count=count,sessions=1,last=serial,fresh=true,merged=true,text=nil})
  return true
 end
 local base=model.base or model.data
 local data=(model.data~=base and model.data) or {}
 for b=1,t.bins do
  local kept=base[b] or 0; local v=session[b]
  if model.fresh then data[b]=v
  elseif kept<=0 then data[b]=v
  elseif v<=0 or v<K.paceMapLow*kept then data[b]=kept
  else data[b]=kept+(min(v,K.paceMapHigh*kept)-kept)*K.paceMapAlpha end
 end
 model.data=data; model.mean,model.count=measure(data,t.bins); model.text=nil
 if not model.merged then model.merged=true; model.sessions=min(K.paceMapSerialMax,model.sessions+1) end
 model.last=serial
 return true
end
-- Texte du fichier : au plus K.paceMapModels modèles, les moins récemment confirmés écartés d'abord.
function M.text(t)
 local names={}
 for _,name in ipairs(t.order) do if t.models[name] then names[#names+1]=name end end
 table.sort(names,function(x,y) local a,b=t.models[x],t.models[y]; if a.last~=b.last then return a.last>b.last end return x<y end)
 local sections={}
 if t.pit then sections[1]={name='pit',laneTime=t.pit.laneTime,frac=t.pit.frac,samples=t.pit.samples} end
 local kept=0
 for _,name in ipairs(names) do
  if kept<K.paceMapModels then
   local model=t.models[name]
   if not model.text then model.text=M.encode(model.data,t.bins) end
   kept=kept+1
   sections[#sections+1]={name='model.'..name,sessions=model.sessions,last=model.last,data=model.text}
  else t.models[name]=nil end
 end
 if kept<#names then for i=#t.order,1,-1 do if not t.models[t.order[i]] then table.remove(t.order,i) end end end
 return TrackFile.build('AdvancedIA track memory ('..C.release..'). Written by the app; do not edit.',
  {kind=KIND,track=t.track,layout=t.layout,length=t.length,serial=min(K.paceMapSerialMax,t.serial+(t.counted and 1 or 0)),bins=t.bins},sections),kept
end
-- Raison pour laquelle la session ne compte pas, ou nil.
local function refusal(t,frame)
 if frame and frame.online then return 'en ligne' end
 if t.total>0 and t.wet>K.paceMapWetShare*t.total then return 'piste mouillee' end
 return nil
end
-- Sauvegarde étalée : un modèle fusionné par appel, puis le texte ; rend le texte quand il est prêt.
function M.saveStep(t,e)
 local job=t.saving
 if not job then return nil end
 if job.at<=#job.names then
  local name=job.names[job.at]; job.at=job.at+1
  if M.mergeModel(t,e,name) then job.kept=job.kept+1 end
  return nil
 end
 t.saving=nil
 if e.pitloss then local rec=Pitloss.export(e.pitloss); if rec then t.pit=rec end end
 if job.kept==0 and not t.pit then
  if not job.quiet then log(e,e.time,'INFO','memoire du circuit: session non retenue (trop peu de tours)') end
  return nil
 end
 if job.kept>0 then t.counted=true end
 local text=M.text(t)
 return text
end
local function startSave(t,quiet)
 local names={}; local seen={}
 for i=1,K.maxCars do local name=t.slot[i]; if name and name~='' and not seen[name] and modelName(name) then seen[name]=true; names[#names+1]=name end end
 table.sort(names)
 t.saving={names=names,at=1,kept=0,quiet=quiet}
end
-- Fin de session (avant l'oubli de l'allure apprise) : fusion et texte en une fois, écriture demandée à l'hôte.
function M.sessionEnd(t,e,now)
 if not t.on or not t.loaded or t.total<=0 then return end
 local why=refusal(t,nil)
 if why then log(e,now,'INFO','memoire du circuit: session non retenue ('..why..')')
 else
  startSave(t,false)
  local text
  for _=1,K.maxCars+2 do text=M.saveStep(t,e); if text or not t.saving then break end end
  if text then t.ioWrite=text; t.ioKey=t.key end
 end
 t.saving=nil
 -- La session suivante part de ce qui vient d'être gardé.
 for _,name in ipairs(t.order) do local model=t.models[name]; if model then model.base=model.data; model.merged=nil; model.fresh=nil end end
 if t.counted then t.serial=min(K.paceMapSerialMax,t.serial+1); t.counted=false end
end
-- Écriture faite par l'hôte : durée notée ; une écriture lente garde la seule sauvegarde de fin de session.
function M.written(t,e,place,ms,bytes,models)
 local now=e.time
 if not place then log(e,now,'WARN','memoire du circuit: enregistrement impossible'); return end
 t.place=place
 log(e,now,'INFO',string.format('memoire du circuit: enregistree (%d modele(s), %d octets, %d ms)',models or #t.order,bytes or 0,floor((ms or 0)+0.5)))
 if (ms or 0)>K.paceMapSlowMs and not t.slow then t.slow=true; log(e,now,'INFO','memoire du circuit: ecriture lente, enregistrement en fin de session seulement') end
end
-- Oubli demandé (bouton de la fenêtre) : fichier vide et valide, rien n'est effacé du disque.
function M.forget(t,e,now)
 if not t.on or t.key=='' then return false end
 local key=t.key
 t.models={}; for i=#t.order,1,-1 do t.order[i]=nil end
 t.pit=nil; t.saving=nil; t.counted=false; t.loaded=true
 detach(e)
 for i=#t.slot,1,-1 do t.slot[i]=nil end
 -- La session en cours ne réécrit pas ce qui vient d'être oublié avant d'avoir appris de nouveau.
 t.total=0; t.wet=0
 t.ioWrite=M.text(t); t.ioKey=key
 log(e,now,'INFO','memoire du circuit: oubliee pour '..key)
 return true
end
-- Appelé après le pilotage, à chaque image ; travail une fois par seconde.
function M.observe(t,e,frame,now)
 local on=e.runtimeG.trackMemory==true and not frame.online and not frame.replay and (frame.trackKey or '')~='' and (frame.length or 0)>0 and (e.delta.bins or 0)>0
 if not on then
  if t.on then t.on=false; t.ioRead=nil; t.saving=nil; detach(e); forgetAll(t); t.status='' end
  return
 end
 if not t.on then t.on=true; t.lastSave=now; t.tick=now end
 local bins=e.delta.bins
 if t.key~=frame.trackKey or t.bins~=bins or abs(t.length-frame.length)>K.trackLengthTol*frame.length then
  detach(e); forgetAll(t)
  t.key=frame.trackKey; t.track=frame.track or ''; t.layout=frame.layout or ''; t.length=frame.length; t.bins=bins
  t.total=0; t.wet=0; t.lastSave=now
 end
 if not t.loaded then
  if not t.asked then t.asked=true; t.ioRead=t.key end
  return
 end
 if t.forgetWanted then t.forgetWanted=false; M.forget(t,e,now) end
 -- Sauvegarde étalée en cours : un modèle par image, écriture demandée quand le texte est prêt.
 if t.saving then
  local text=M.saveStep(t,e)
  if text then t.ioWrite=text; t.ioKey=t.key end
 end
 if now-t.tick<1 then return end
 t.tick=now
 if frame.paused then return end
 t.total=t.total+1
 if (frame.wet or 0)>K.priorWetMax then t.wet=t.wet+1 end
 attach(t,e,frame)
 if t.pit and e.pitloss and not e.pitloss.known then Pitloss.import(e.pitloss,t.pit) end
 if not t.startLogged and frame.started and t.total>=K.paceMapStartNote then
  t.startLogged=true
  if #t.order>0 then log(e,now,'INFO',string.format('memoire du circuit: %d voiture(s) avec une allure connue au depart, %d sans',t.known,t.unknown)) end
 end
 -- Sauvegarde périodique : seulement si quelque chose de nouveau a été appris ; de préférence joueur aux stands, forcée
 -- après deux périodes ; jamais après une écriture lente.
 if not t.slow and not t.saving and not t.ioWrite then
  local learnt=0
  for i=1,frame.count do if t.slot[i] then learnt=learnt+e.states[i].paceCount end end
  t.learnt=learnt
  local since=now-t.lastSave
  local me=frame.player>0 and frame.cars[frame.player] or nil
  local calm=me==nil or me.pit==true
  if learnt~=t.savedLearnt and (since>=K.paceMapSavePeriod*2 or (calm and since>=K.paceMapSavePeriod)) then
   t.lastSave=now; t.savedLearnt=learnt
   if not refusal(t,frame) then startSave(t,true) end
  end
 end
 t.status=string.format('%s: %d / %d',t.key,#t.order,t.used)
end
-- Texte d'état pour la fenêtre (tranche A) : nil s'il n'y a rien à montrer.
function M.status(t) if not t.on or t.key=='' then return nil end return t.status end
return M
