-- Beta 1.61 (tranche C, réglage classNuance, coupé par défaut). Décisions pures sur les retardataires et les classes :
-- quand un drapeau bleu commence (voiture vraiment sur le point d'arriver), où la cession attend (freinage proche),
-- ce qu'elle coûte, la trêve entre deux retardataires en lutte, le dédoublement, la classe lente qui tient sa ligne,
-- et le drapeau bleu du joueur en deux temps. Appelé par src/director.lua et src/panel.lua ; aucune fonction CSP,
-- aucune table ni chaîne par IA et par image (les tableaux sont créés une fois, le texte de la clé annexe au plus une
-- fois par seconde et seulement quand il change).
local C=require('src/config')
local U=require('src/util')
local P=require('src/perception')
local Classes=require('src/classes')
local FirstLap=require('src/firstlap')
local Zones=require('src/zones')
local K=C.K
local M={}
local max,min,abs,floor,huge=math.max,math.min,math.abs,math.floor,math.huge
local sideKey='AdvancedIA.traffic'
M.sideKey=sideKey
local function clear(t)
 for i=1,K.maxCars do t.with[i]=0; t.by[i]=0; t.untilAt[i]=-huge end
 t.restartAt=-huge; t.sideAt=-huge; t.sigN=-1; t.sigGap=-1; t.stage='none'; t.kind='none'; t.car=0; t.gapM=0; t.closing=0; t.count=0; t.logSig=0
end
function M.new()
 local t={session=-1,with={},by={},untilAt={},rel={index=0,long=0,lat=0,gap=0,sa=0,ttc=huge,same=false}}
 clear(t)
 return t
end
function M.reset(t) t.session=-1; clear(t) end -- (t,now)
function M.rebase(t,amount)
 for i=1,K.maxCars do t.untilAt[i]=t.untilAt[i]-amount end
 t.restartAt=t.restartAt-amount; t.sideAt=t.sideAt-amount
end
-- a) Voiture qui prend un tour sur le point d'arriver : déjà collée (K.blueCloseGap m), ou à K.blueCatchTime s au plus
-- au rythme du rapprochement. À 140 m et +5 km/h (100 s), plus de cession 30 s trop tôt.
function M.catch(gap,sa)
 if gap<=K.blueCloseGap then return true end
 return sa>0 and gap/(sa/3.6)<=K.blueCatchTime
end
-- b) Distance (m) au prochain point de freinage connu : zone « brake » du fichier du circuit (tranche A,
-- Zones.nextBrake : progression de 0 à 1, nil sans zone) ou point appris pendant la session (src/firstlap.lua).
function M.brakeNear(e,a,length)
 local best=FirstLap.nextPoint(e.fl,a,length)
 local at=a.splineValid and length>0 and Zones.nextBrake(e.zones,a.spline) or nil
 if at then local d=((at-a.spline)%1)*length; if d<best then best=d end end
 return best
end
-- Vrai à moins de seconds s du prochain point de freinage, à la vitesse de la voiture (plancher du premier tour).
function M.brakeSoon(e,a,length,seconds)
 local d=M.brakeNear(e,a,length)
 return d<=max(a.speed,K.firstLapSpeedMin)*seconds,d
end
-- c) Niveau rendu par la retardataire : de K.blueSlowdown (voiture retenue derrière, à vitesse égale) à K.blueSlowMin
-- (voiture bien plus rapide, K.blueFastSa km/h : elle ne donne que la trajectoire), linéaire entre les deux.
function M.slowdown(sa)
 return K.blueSlowMin+(K.blueSlowdown-K.blueSlowMin)*(1-U.clamp((sa or 0)/K.blueFastSa,0,1))
end
-- d) Trêve entre deux voitures du même tour rattrapées par la voiture k : ni l'une ni l'autre n'attaque l'autre
-- jusqu'à ce que k les ait passées toutes les deux, plus K.blueTruceAfter s ; bornée par hold s (réglage
-- yieldMaxHold) quoi qu'il arrive. Renvoie vrai quand la trêve commence (une ligne au journal).
function M.truce(t,i,j,k,now,hold)
 local fresh=not (t.with[i]==j and t.by[i]==k and now<t.untilAt[i])
 t.with[i]=j; t.by[i]=k; t.untilAt[i]=now+hold
 t.with[j]=i; t.by[j]=k; t.untilAt[j]=now+hold
 return fresh
end
function M.truced(t,i,j,now)
 return t.with[i]==j and now<t.untilAt[i] or t.with[j]==i and now<t.untilAt[j]
end
-- La voiture k a passé i : sa part de la trêve s'achève K.blueTruceAfter s plus tard (celle de l'autre voiture tient
-- jusqu'à son propre passage).
function M.passed(t,i,k,now)
 if t.by[i]==k and now<t.untilAt[i] then t.untilAt[i]=min(t.untilAt[i],now+K.blueTruceAfter) end
end
-- e) Voiture tout juste doublée par celle qui lui prend un tour : pas d'attaque en retour pendant K.relapHold s, sauf
-- nettement plus rapide (K.relapSa km/h).
function M.relapHeld(s,target,sa,now)
 return s.relapBy==target and now<(s.relapUntil or -huge) and sa<K.relapSa
end
-- f) Classe lente : la voiture rapide a déjà choisi son côté (décalée de K.classSideLat m) : la ligne est tenue.
function M.classHold(lat) return abs(lat)>=K.classSideLat end
-- Groupe de la classe rapide : la voisine r suit à K.classTrainTime s au plus une voiture déjà attendue (followers) ou
-- la voiture qui cède elle-même : elle passe avec le groupe.
function M.train(row,r,followers,frame)
 local other=frame.cars[r.index]; local span=K.classTrainTime*max(other.speed,1)
 if r.gap<=span then return true end
 for j=1,row.count do
  local n=row.neighbors[j]
  if n.index~=r.index and followers[n.index] and n.long<0 and r.gap>=n.gap and r.gap-n.gap<=span then return true end
 end
 return false
end
-- g) Drapeau bleu du joueur, réglage en service. Renvoie l'écart en secondes (comme Panel.blue) ou nil, puis le
-- temps (1 annonce, 0 ordre) et le genre (2 classe, 0 tour). faster(p,a,b) : test de classe du directeur.
-- Jamais dans les K.blueStartGrace s après un départ ou une relance. La clé annexe est reconstruite au plus une fois
-- par seconde et écrite dans e.sideText seulement quand son contenu change.
local stages={[0]='none','advise','order'}
local kinds={[0]='none','lap','class'}
local function publish(t,e,now,kind,stage,car,gap,closing,count)
 -- Contrat SpotterEnginer (il attend 1,5 s) : un changement de genre, d'étape ou de voiture est publié tout de suite ;
 -- seuls l'écart, l'approche et le nombre restent limités à une fois par seconde.
 local id=kind*1000000+stage*100000+car
 if id==t.sideId and now<t.sideAt and now>=t.sideAt-1 then return end
 t.sideId=id; t.sideAt=now+1
 local sig=kind*1000000+stage*100000+car*1000+min(count,99)*10
 local coarse=floor(gap/5+0.5)*5
 -- Contrat SpotterEnginer (clé figée après 2,5 s sans changement) : drapeau bleu en cours, réécrite chaque seconde,
 -- stamp = seconde de simulation en cours ; sans drapeau bleu, seulement quand elle change (stamp = dernier changement).
 if kind==0 and sig==t.sigN and coarse==t.sigGap then return end
 t.sigN=sig; t.sigGap=coarse
 local text=string.format('v=1;blue=%s;stage=%s;car=%d;gap=%d;closing=%d;count=%d;stamp=%d',kinds[kind],stages[stage],car>0 and car-1 or -1,coarse,floor(closing+0.5),count,floor(now))
 if #text<=K.trafficKeyBytes then e.sideText[sideKey]=text end
end
function M.playerBlue(t,e,frame,p,profile,now,held,faster)
 local inc=e.incidents
 if inc and (inc.neutral or inc.red or inc.relaunch or inc.restart) then t.restartAt=now end
 if profile~='C' or not p.blueFlagEnabled or frame.player==0 or frame.length<=0 then return nil end
 local a=frame.cars[frame.player]
 if not a.valid or a.pit or not a.splineValid then publish(t,e,now,0,0,0,0,0,0); return nil end
 local since=now-max(e.startedAt or -huge,e.launchAt or -huge,t.restartAt)
 if since<K.blueStartGrace then publish(t,e,now,0,0,0,0,0,0); return nil end
 local rel=t.rel; local sa=e.states[frame.player]
 local best,bestGap,bestSa,bestCar,bestKind=nil,0,0,0,0
 local count=0
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=frame.player and b.valid and not b.pit and b.splineValid and not b.safetyCar then
   local r=P.relative(a,b,frame.length,rel)
   if r.same and r.long<0 and r.gap>=0 and r.gap<=p.blueFlagRange then
    local lap=Classes.laps(a,b,r,frame.length)>0
    local class=not lap and faster and faster(p,e.states[j],sa)
    if lap or class then
     local closing=r.sa>=K.lapSpeed or held and r.sa>-K.lapSpeed
     local near=M.catch(r.gap,r.sa) or held and r.sa>-K.lapSpeed
     if closing and near then
      count=count+1
      local gap=r.gap/max(1,b.speed)
      if not best or gap<best then best=gap; bestGap=r.gap; bestSa=r.sa; bestCar=j; bestKind=lap and 1 or 2 end
     end
    end
   end
  end
 end
 if not best then
  publish(t,e,now,0,0,0,0,0,0)
  t.stage='none'; t.kind='none'; t.car=0; t.count=0; t.logSig=0
  return nil
 end
 -- Voitures qui suivent la première (à K.blueTrainRange m au plus derrière elle) : nombre publié.
 local train=0
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=frame.player and b.valid and not b.pit and b.splineValid and not b.safetyCar then
   local r=P.relative(a,b,frame.length,rel)
   if r.same and r.long<0 and r.gap>=bestGap and r.gap<=bestGap+K.blueTrainRange and (Classes.laps(a,b,r,frame.length)>0 or faster and faster(p,e.states[j],sa)) then train=train+1 end
  end
 end
 count=max(count,train)
 local arrive=bestSa>0 and bestGap/(bestSa/3.6) or huge
 -- Ordre : la voiture est là (à K.bluePlayerOrderTime s, ou retenue juste derrière sans plus se rapprocher).
 local stage=(arrive<=K.bluePlayerOrderTime or bestGap<=K.blueCloseGap and bestSa<K.lapSpeed) and 2 or 1
 t.stage=stages[stage]; t.kind=kinds[bestKind]; t.car=bestCar; t.gapM=bestGap; t.closing=bestSa; t.count=count
 publish(t,e,now,bestKind,stage,bestCar,bestGap,bestSa,count)
 local sig=bestKind*10000+stage*1000+bestCar
 if sig~=t.logSig then
  t.logSig=sig; e.stats.bluePlayer=(e.stats.bluePlayer or 0)+1
  U.log(e.log,now,'INFO',string.format('drapeau bleu joueur: %s (%s a %.0f m, %.1f s, %d voiture(s))',bestKind==2 and 'classe' or stage==2 and 'ordre' or 'annonce',frame.cars[bestCar].name,bestGap,best,count),frame.player)
 end
 return best,stage==1 and 1 or 0,bestKind==2 and 2 or 0
end
return M
