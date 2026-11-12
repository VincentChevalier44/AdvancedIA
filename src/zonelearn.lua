-- Beta 1.61 (tranche A). Appelé par src/engine.lua après le pilotage, à chaque image ; ne fait rien tant que la liste
-- des zones du circuit (e.zones, src/zones.lua) ne porte aucune zone d'un genre nouveau et que le réglage global
-- « Mémoire des circuits » (trackMemory) est coupé.
--  1. Pour la liste : pause du départ des points difficiles, points de freinage connus donnés au premier tour attentif
--     (e.fl.known), et par voiture, pour l'image suivante (champs de s.zone lus par Zones.at) : attente d'une zone
--     d'attaque toute proche (waitNext), voiture de devant déjà attaquée par une autre (noBoost), ligne de la zone
--     (lineNext, installée en K.lineRamp s).
--  2. Avec trackMemory : apprentissage des points de freinage (toute la session), des zones d'attaque (dépassements
--     réussis en course, e.passDone) et des points difficiles armés (e.incidents.hotspotArmedN). Une zone apprise
--     compte une session quand elle est confirmée dans la session ; elle est appliquée après K.zoneConfirmSessions
--     sessions et oubliée après K.zoneForgetSessions sessions sans confirmation (numéro de série du fichier, jamais
--     l'horloge). Aucun fichier n'est écrit ici : le module demande l'enregistrement (e.zoneSaveAsk='learn'), l'hôte
--     écrit (AdvancedIA.lua), au changement de session, à l'arrivée et au plus toutes les K.zoneSavePeriod s.
local U=require('src/util')
local K=require('src/config').K
local Zones=require('src/zones')
local FirstLap=require('src/firstlap')
local Priority=require('src/priority')
local min,max,abs=math.min,math.max,math.abs
local M={}
function M.new() return {session=-1,flush=false,held=0,lines=0,learntCount=0,forgotten=0} end
-- Nouvelle session : les marques de la session sont soldées au prochain pas (qui a le moteur sous la main).
function M.reset(t) t.session=-1; t.flush=true end -- (t,now)
function M.rebase(t,amount) if t.savedAt then t.savedAt=t.savedAt-amount end end
local kindText={brake='freinage',attack='attaque',caution='point difficile'}
local function meters(z,length)
 if z.kind=='caution' then return ((z.from+((z.to-z.from)%1)*0.5)%1)*length end
 return z.from*length
end
-- Zone confirmée dans cette session : une session de plus, notée ; appliquée dès qu'elle est confirmée.
local function count(t,zones,z,length,e,now)
 z.counted=true; z.sessions=min(100000,(z.sessions or 0)+1); zones.dirty=true; t.learntCount=t.learntCount+1
 U.log(e.log,now,'INFO',string.format('zone apprise: %s a %.0f m (%d passages, %d sessions)',kindText[z.kind],meters(z,length),z.hits or 0,z.sessions),-1)
 if Zones.confirmed(z) then Zones.index(zones) end
end
local function record(zones,kind,from,to)
 local learnt=zones.learnt
 if #learnt>=K.zoneLearntMax then return nil end
 local z={kind=kind,source='learnt',from=from,to=to,hits=0,sessions=0,last=0,now=0,noYield=false,noOvertake=false,maxOffset=1,note=''}
 learnt[#learnt+1]=z
 return z
end
local function hit(z) z.hits=min(100000,(z.hits or 0)+1); z.now=(z.now or 0)+1 end
-- Début de freinage d'une IA libre, depuis une ligne droite : point de freinage (fusionné à K.firstLapPointMerge m).
function M.brake(t,zones,spline,length,index,e,now)
 local learnt=zones.learnt; local merge=K.firstLapPointMerge/length; local z=nil; local n=0
 for k=1,#learnt do local q=learnt[k]; if q.kind=='brake' then n=n+1; if not z and abs(U.spline(q.from-spline))<=merge then z=q end end end
 if not z then
  if n>=K.zoneBrakeMax then return end
  z=record(zones,'brake',spline,spline); if not z then return end
 end
 if z.off then return end
 hit(z)
 local cars=z.cars; if not cars then cars={}; z.cars=cars; z.carN=0 end
 if not cars[index] then cars[index]=true; z.carN=z.carN+1 end
 if not z.counted and z.now>=K.brakeLearnHits and z.carN>=K.brakeLearnCars then count(t,zones,z,length,e,now) end
 if z.counted then zones.dirty=true end
end
-- Dépassement réussi : zone d'attaque autour des dépassements voisins, finie au prochain point de freinage connu.
function M.pass(t,zones,spline,length,e,now)
 local learnt=zones.learnt; local merge=K.attackMergeMeters/length; local z=nil; local n=0
 for k=1,#learnt do
  local q=learnt[k]
  if q.kind=='attack' then
   n=n+1
   if not z and (abs(U.spline((q.anchor or q.to)-spline))<=merge or (q.from<=q.to and spline>=q.from and spline<=q.to) or (q.from>q.to and (spline>=q.from or spline<=q.to))) then z=q end
  end
 end
 if not z then
  if n>=K.attackMax then return end
  z=record(zones,'attack',spline,spline); if not z then return end
  z.anchor=spline
 end
 if z.off then return end
 hit(z)
 if z.anchor then
  local d=Zones.brakeAhead(zones,z.anchor)
  local after=d and d*length<=K.attackMaxMeters and d*length or K.attackMinMeters*0.5
  local span=U.clamp(after+K.attackMergeMeters,K.attackMinMeters,K.attackMaxMeters)
  z.to=(z.anchor+after/length)%1; z.from=(z.to-span/length)%1
 end
 if not z.counted and z.now>=K.attackLearnPasses then count(t,zones,z,length,e,now) end
 if z.counted then zones.dirty=true end
end
-- Point difficile armé par src/incidents.lua : gardé pour les sessions suivantes.
function M.caution(t,zones,spline,length,e,now)
 local learnt=zones.learnt; local half=K.hotspotMeters/length; local z=nil
 for k=1,#learnt do
  local q=learnt[k]
  if q.kind=='caution' and abs(U.spline((q.from+((q.to-q.from)%1)*0.5)-spline))<=half then z=q; break end
 end
 if not z then z=record(zones,'caution',(spline-half)%1,(spline+half)%1); if not z then return end end
 if z.off then return end
 hit(z)
 if not z.counted then count(t,zones,z,length,e,now) end
 zones.dirty=true
end
-- Avant un enregistrement : numéro de série avancé une fois par session, zones confirmées datées, zones qui ne sont
-- plus confirmées depuis K.zoneForgetSessions sessions oubliées (jamais une zone refusée par le pilote : elle reste,
-- pour ne pas être apprise de nouveau).
function M.settle(t,zones,length,e,now)
 if not zones.bumped then zones.bumped=true; zones.serial=min(1e9,(zones.serial or 0)+1) end
 local serial=zones.serial; local learnt=zones.learnt; local w=0; local dropped=false
 for k=1,#learnt do
  local z=learnt[k]
  if z.counted then z.last=serial end
  if (z.sessions or 0)>0 and not z.off and serial-(z.last or 0)>=K.zoneForgetSessions then
   dropped=true; t.forgotten=t.forgotten+1
   U.log(e.log,now,'INFO',string.format('zone oubliee: %s a %.0f m (plus confirmee depuis %d sessions)',kindText[z.kind],meters(z,length),serial-(z.last or 0)),-1)
  else w=w+1; learnt[w]=z end
 end
 for k=#learnt,w+1,-1 do learnt[k]=nil end
 if dropped then Zones.index(zones) end
end
-- Marques de la session effacées (nouvelle session).
local function fresh(zones)
 zones.bumped=nil
 local learnt=zones.learnt
 for k=1,#learnt do local z=learnt[k]; z.counted=nil; z.now=0; z.cars=nil; z.carN=nil end
end
-- Par voiture, pour l'image suivante : attente d'une zone d'attaque, voiture de devant déjà attaquée, ligne de la zone.
local function cars(t,e,frame,now,dt,zones)
 local rows=e.perception.rows; local length=frame.length
 for i=1,frame.count do
  local a=frame.cars[i]; local s=e.states[i]; local z=s.zone
  if z then
   local wait,held,line=nil,nil,0
   if a.valid and a.control and not a.pit and a.splineValid and length>0 then
    local row=rows[i]; local fr=row.front>0 and row.neighbors[row.front] or nil
    if zones.attackN>0 and fr then
     s.zlStuck=fr.gap<K.followRange and (s.zlStuck or 0)+dt or 0
     local os=e.states[fr.index]
     local holder=os and Priority.held(os,now) or 0
     if holder>0 and holder~=i then held=true end
     if not z.attack then
      local d=Zones.attackAhead(zones,a.spline)
      if d and d*length<=max(a.speed,K.firstLapSpeedMin)*K.attackWaitTime then
       local o=frame.cars[fr.index]
       local lapping=a.lapValid and o.lapValid and (a.lap or 0)>(o.lap or 0)
       local class=e.run.multiClass and a.classified and o.classified and a.class<o.class
       -- Jamais d'attente : rapprochement franc, voiture retenue depuis longtemps, voiture à un tour, classe plus lente.
       if not (fr.sa>K.attackNoWaitSa or s.zlStuck>=K.attackStuckTime or lapping or class) then wait=true end
      end
     end
    else s.zlStuck=0 end
    local lz=z.line
    if lz and s.state=='DRIVE' and not row.left and not row.right and (not lz.wet or frame.wet>=K.lineWet)
     and U.unit(e.g.seed,i,K.lineSalt)<(lz.share or K.lineShareDefault) then
     line=(lz.side or 0)*min(K.baseMax,z.maxOffset or 1)
    end
   end
   if wait and not z.waitNext then t.held=t.held+1 end
   z.waitNext=wait; z.noBoost=held
   local cur=s.zlLine or 0
   if cur~=line then
    local step=K.baseMax*dt/K.lineRamp
    if cur<line then cur=min(line,cur+step) else cur=max(line,cur-step) end
    s.zlLine=cur
   end
   if cur~=0 and not s.zlLineOn then s.zlLineOn=true; t.lines=t.lines+1 elseif cur==0 and s.zlLineOn then s.zlLineOn=nil end
   z.lineNext=cur~=0 and cur or nil
  end
 end
end
local function learn(t,e,frame,now,zones)
 local length=frame.length
 if (frame.trackKey or '')=='' or frame.online or frame.replay or length<=0 or not zones.learnt then return end
 if t.flush then
  -- Session d'avant soldée et enregistrée ; une session avec la mémoire en service compte pour l'oubli.
  t.flush=false
  if zones.dirty then M.settle(t,zones,length,e,now); e.zoneSaveAsk='learn' end
  fresh(zones); t.started=nil; t.finishSaved=nil
 end
 if not t.started then
  t.started=true; t.savedAt=now; t.armedSeen=e.incidents.hotspotArmedN or 0
  for k=1,#zones.learnt do if (zones.learnt[k].sessions or 0)>0 then zones.dirty=true; break end end
 end
 -- Points de freinage : toute la session, sur le sec, hors drapeau.
 if frame.started and not frame.finished and frame.wet<K.lineWet then
  local rows=e.perception.rows
  for i=1,frame.count do
   local a=frame.cars[i]; local s=e.states[i]
   if a.valid and a.control and not a.player and not a.safetyCar and not a.pit and not a.finished and not s.yellow then
    local braking=FirstLap.braking(a,s)
    if braking and not s.zlBrakeWas and FirstLap.freePoint(a,rows[i]) then M.brake(t,zones,a.spline,length,i,e,now) end
    s.zlBrakeWas=braking
   else s.zlBrakeWas=false end
  end
 end
 -- Zones d'attaque : dépassements réussis en course.
 if e.passDone and e.profile=='C' then
  local a=frame.cars[e.passDone]
  if a and a.valid and a.splineValid then M.pass(t,zones,a.spline,length,e,now) end
 end
 -- Points difficiles armés depuis le dernier pas.
 local armed=e.incidents.hotspotArmedN or 0
 if armed~=t.armedSeen then t.armedSeen=armed; M.caution(t,zones,e.incidents.hotspotArmedAt or 0,length,e,now) end
 -- Enregistrement demandé à l'hôte : périodique, et une fois à l'arrivée.
 if zones.dirty and not e.zoneSaveAsk and (now-(t.savedAt or now)>=K.zoneSavePeriod or frame.finished and not t.finishSaved) then
  t.savedAt=now; t.finishSaved=frame.finished or nil
  M.settle(t,zones,length,e,now); e.zoneSaveAsk='learn'
 end
end
function M.step(t,e,frame,now,dt)
 local zones=e.zones
 if not zones then return end
 if e.fl.known~=zones.brakes then e.fl.known=zones.brakes end
 if zones.extra then
  zones.cautionPause=e.incidents.hotspotPause==true
  cars(t,e,frame,now,dt,zones)
 end
 if not e.runtimeG.trackMemory then return end
 if not zones.learnt then Zones.index(zones) end
 learn(t,e,frame,now,zones)
end
return M
