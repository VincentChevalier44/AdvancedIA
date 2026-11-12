-- Beta 1.60 (tranche D, réglage strategySmart, course seulement, coupé par défaut) : temps perdu aux stands appris sur
-- les passages vus (joueur et arrêts d'AC compris), écarts en temps entre deux voitures, estimation de la sortie des
-- stands. Décisions pures, appelé par src/engine.lua après le pilotage ; aucune fonction de CSP. Tableaux créés une fois.
-- Le temps perdu : temps dans la voie moins le temps qu'il aurait fallu en piste pour la même portion du tour
-- (frac × temps au tour) ; sous neutralisation, la même formule avec le tour neutralisé donne la perte plus faible.
-- Les trois nombres (laneTime, frac, samples) forment un petit enregistrement par circuit (prêt pour la 1.61).
local U=require('src/util')
local K=require('src/config').K
local max,abs=math.max,math.abs
local M={}
local function car() return {lane=false,seen=false,at=0,spline=0,served=false,bad=false,timed=false} end
function M.new()
 local t={session=-1,cars={},laneTime=0,frac=0,samples=0,known=false,logged=-math.huge,neutralLap=0,text='',textAt=-math.huge,stamp=0,on=false}
 for i=1,K.maxCars do t.cars[i]=car() end
 return t
end
function M.reset(t)
 t.session=-1; t.laneTime=0; t.frac=0; t.samples=0; t.known=false; t.logged=-math.huge; t.neutralLap=0; t.text=''; t.textAt=-math.huge; t.stamp=0; t.on=false; t.body=nil
 for i=1,K.maxCars do local c=t.cars[i]; c.lane=false; c.seen=false; c.served=false; c.bad=false; c.timed=false end
end
function M.rebase(t,amount)
 if U.finite(t.textAt) then t.textAt=t.textAt-amount end
 for i=1,K.maxCars do local c=t.cars[i]; c.at=c.at-amount end
end
-- Temps perdu par un arrêt pour une voiture au temps au tour donné ; -1 tant qu'aucun passage n'a été appris.
function M.loss(t,lapTime)
 if not t.known or not lapTime or lapTime<=0 then return -1 end
 return max(0,t.laneTime-t.frac*lapTime)
end
-- Temps au tour appris d'une voiture (src/pits.lua), 0 inconnu.
local function lapTimeOf(e,i) local pc=e.pits.cars[i]; return pc and pc.lapTime or 0 end
M.lapTimeOf=lapTimeOf
-- Écart en temps de la voiture i à la voiture j : positif si j est devant. Différence d'avancement (tours et position
-- sur le tour) × temps au tour appris de la voiture de derrière ; nil si ce temps est inconnu.
function M.gap(e,frame,i,j)
 local a,b=frame.cars[i],frame.cars[j]
 if not a or not b then return nil end
 local d=(b.lap or 0)+(b.spline or 0)-(a.lap or 0)-(a.spline or 0)
 local lapTime=lapTimeOf(e,d>=0 and i or j)
 if lapTime<=0 then return nil end
 return d*lapTime
end
-- Trafic à la sortie des stands si la voiture i s'arrêtait maintenant : point de sortie virtuel = sa position moins
-- (perte / temps au tour) tours ; voiture plus lente (temps au tour moins bon de K.rejoinSlowPct) à moins de
-- K.rejoinAhead s devant ce point, ou file de K.rejoinTrain voitures dans K.rejoinTrainSpan s.
-- Rend traffic (booléen), l'indice de la voiture gênante (ou -1), son écart en secondes et l'écart de la première
-- voiture derrière ce point (math.huge si aucune) ; nil si rien n'est connu.
function M.rejoin(t,e,frame,i)
 local a=frame.cars[i]; local lapTime=lapTimeOf(e,i)
 local loss=M.loss(t,lapTime)
 if loss<0 or not a then return nil end
 local point=(a.spline or 0)-loss/lapTime
 local train,blocker,blockGap,behind=0,-1,math.huge,math.huge
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=i and b.valid and not b.pit and not b.finished and not b.safetyCar then
   local d=((b.spline or 0)-point)%1
   local gap=d*lapTime
   if gap<=K.rejoinTrainSpan then train=train+1 end
   local back=(1-d)*lapTime; if back<behind then behind=back end
   local other=lapTimeOf(e,j)
   if gap<=K.rejoinAhead and other>lapTime*(1+K.rejoinSlowPct) and gap<blockGap then blocker=j; blockGap=gap end
  end
 end
 if blocker>0 then return true,blocker,blockGap,behind end
 if train>=K.rejoinTrain then return true,-1,K.rejoinTrainSpan,behind end
 return false,-1,0,behind
end
-- Temps au tour de référence du plateau (le meilleur appris), pour la clé publiée et le journal ; 0 inconnu.
local function fieldLap(e,frame)
 local best=0
 for i=1,frame.count do local lt=lapTimeOf(e,i); if lt>0 and frame.cars[i].valid and (best==0 or lt<best) then best=lt end end
 return best
end
-- Tour neutralisé estimé pour une voiture au temps au tour donné : appris pendant une neutralisation (vitesse moyenne
-- des voitures en piste) ; avant cela, le temps de référence réglé (plus lent de fcyDeltaPct ou vscDeltaPct %) ; 0 inconnu.
function M.neutralLapTime(t,e,lapTime)
 if not lapTime or lapTime<=0 then return 0 end
 if t.neutralLap>lapTime then return t.neutralLap end
 local p=e.run; local pct=e.incidents.neutralMode=='vsc' and p.vscDeltaPct or p.fcyDeltaPct
 return lapTime*(1+(pct or 0)/100)
end
-- Gain d'un arrêt sous neutralisation par rapport à un arrêt sous drapeau vert, en secondes ; -1 inconnu.
function M.neutralSaving(t,e,lapTime)
 local green=M.loss(t,lapTime); local slow=M.neutralLapTime(t,e,lapTime)
 if green<0 or slow<=lapTime then return -1 end
 return green-M.loss(t,slow)
end
local function sample(t,lane,frac)
 if lane<K.pitLossMin or lane>K.pitLossMax or frac<=0 or frac>=1 then return end
 if t.samples==0 then t.laneTime=lane; t.frac=frac
 else t.laneTime=t.laneTime+(lane-t.laneTime)*K.pitLossAlpha; t.frac=t.frac+(frac-t.frac)*K.pitLossAlpha end
 t.samples=t.samples+1; t.known=true
end
M.sample=sample
-- Beta 1.61 (tranche B, mémoire du circuit) : les trois nombres appris, pour le fichier du circuit (nil : rien d'appris),
-- et leur reprise à la session suivante (jamais par-dessus ce que la session a déjà appris ; bornes de la 1.60).
function M.export(t)
 if not t.known or t.samples<1 then return nil end
 return {laneTime=t.laneTime,frac=t.frac,samples=math.min(t.samples,100000)}
end
function M.import(t,record)
 if t.known or type(record)~='table' then return false end
 local lane,frac,samples=record.laneTime,record.frac,record.samples
 if type(lane)~='number' or type(frac)~='number' or type(samples)~='number' then return false end
 if not (lane>=K.pitLossMin and lane<=K.pitLossMax and frac>0 and frac<1 and samples>=1) then return false end
 t.laneTime=lane; t.frac=frac; t.samples=math.floor(samples); t.known=true
 return true
end
-- Texte de la clé publiée pour SpotterEnginer (AdvancedIA.strategy, contrat v1) : refait au plus une fois par
-- K.strategyPubPeriod s, horodaté seulement quand les nombres changent (l'hôte n'écrit que si le texte change).
local function publish(t,e,frame,now)
 if now-t.textAt<K.strategyPubPeriod then return end
 t.textAt=now
 local lap=fieldLap(e,frame)
 local loss=M.loss(t,lap)
 local slow=M.neutralLapTime(t,e,lap)
 local neutral=loss>=0 and slow>lap and M.loss(t,slow) or -1
 local body=string.format('v=1;pitLoss=%.1f;pitLossNeutral=%.1f;laneTime=%.1f;samples=%d',loss,neutral,t.known and t.laneTime or -1,t.samples)
 if body~=t.body then t.body=body; t.stamp=now; t.text=string.format('%s;stamp=%.1f',body,now) end
end
function M.update(t,e,frame,now)
 local p=e.run
 local on=p.strategySmart==true and p.strategyEnabled==true and e.profile=='C' and frame.started==true and not frame.online and not frame.replay
 if not on then
  if t.on then t.on=false; t.text=''; t.body=nil; for i=1,K.maxCars do local c=t.cars[i]; c.lane=false; c.seen=false; c.timed=false end end
  return
 end
 t.on=true
 local inc=e.incidents
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]
  if not a.valid or a.safetyCar then c.lane=false; c.seen=false; c.timed=false
  else
   local lane=a.pit==true
   local pc=e.pits.cars[i]
   local towed=pc and pc.towedAt~=nil and now>=pc.towedAt and now-pc.towedAt<=K.towWindow
   if lane and not c.lane and c.seen and not frame.finished then
    -- Entrée dans la voie (jamais une voiture déjà dans la voie à la première image).
    c.at=now; c.spline=a.spline or 0; c.served=false; c.bad=false; c.timed=true
   end
   if lane and c.timed then
    if a.teleport or towed or inc.red or e.commands[i].recover then c.bad=true end
    if a.inPitBox and (a.kmh or 0)<=K.tyreStopSpeed and not e.commands[i].noOutLap and not e.commands[i].penaltyPass then c.served=true end
   end
   if not lane and c.lane and c.timed then
    c.timed=false
    -- Sortie : dépannage, drapeau rouge, pénalité sans service (aucun arrêt à l'emplacement) : pas un échantillon.
    if c.served and not c.bad and not a.teleport and not towed then
     local before=M.loss(t,fieldLap(e,frame))
     sample(t,now-c.at,((a.spline or 0)-c.spline)%1)
     local after=M.loss(t,fieldLap(e,frame))
     if t.known and after>=0 and (before<0 or abs(after-t.logged)>K.pitLossLogStep) then
      t.logged=after
      U.log(e.log,now,'INFO',string.format('stands: temps perdu appris %.1f s (voie %.1f s, %d passage(s))',after,t.laneTime,t.samples),-1)
     end
    end
   end
   c.lane=lane; c.seen=true
  end
 end
 -- Tour neutralisé : vitesse moyenne des voitures en piste pendant la neutralisation (une fois par période publiée).
 if inc.neutral and not inc.red and (frame.length or 0)>0 and now-t.textAt>=K.strategyPubPeriod then
  local sum,n=0,0
  for i=1,frame.count do local a=frame.cars[i]; if a.valid and not a.pit and not a.safetyCar and (a.speed or 0)>K.pitLossMinSpeed then sum=sum+a.speed; n=n+1 end end
  if n>0 then local lap=frame.length/(sum/n); t.neutralLap=t.neutralLap>0 and t.neutralLap+(lap-t.neutralLap)*K.pitLossAlpha or lap end
 end
 publish(t,e,frame,now)
end
return M
