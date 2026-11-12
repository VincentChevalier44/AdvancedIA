-- Temps delta sous neutralisation, drapeau rouge et double drapeau jaune, comme sur le volant d'une F1 : temps écoulé
-- moins le temps de référence sur la distance parcourue ; positif = assez lent. Référence : allure libre apprise à
-- chaque endroit, plus lente du pourcentage du régime, jamais sous un plancher de freinage depuis la vitesse au
-- déclenchement. Infraction au passage d'un mini-secteur (ou à la sortie d'une zone) en négatif au-delà de la
-- tolérance. Décisions pures : le moteur lit, les pénalités jugent, l'interface affiche.
local U=require('src/util')
local K=require('src/config').K
local max,min,floor=math.max,math.min,math.floor
local M={}
local function accumulator() return {on=false,kind='',delta=0,last=-1,sector=-1,pit=false} end
function M.new()
 local lists={}; for class=1,K.classMax do lists[class]={} end
 return {course=accumulator(),zone=accumulator(),fleet={},fleetNext=1,bins=K.paceBins,lists=lists,counts={},value=nil,kind='',infraction=false,
  infractionKind='',infractionValue=0,onsetAt=-math.huge,onsetKmh=0,signalAt=-math.huge,signalKmh=0,zoneSlot=0,
  inside=false,wasZone=false}
end
function M.reset(d)
 d.course=accumulator(); d.zone=accumulator(); d.value=nil; d.kind=''; d.infraction=false; d.inside=false; d.wasZone=false
 for _,f in pairs(d.fleet) do for b=1,#f do f[b]=0 end end
end
function M.rebase(d,amount)
 if U.finite(d.onsetAt) then d.onsetAt=d.onsetAt-amount end
 if U.finite(d.signalAt) then d.signalAt=d.signalAt-amount end
end
-- Endroit de l'allure apprise : count endroits sur le tour (d.bins ; K.paceBins sans précision).
local function bin(spline,count) count=count or K.paceBins; return min(count,floor((spline%1)*count)+1) end
M.bin=bin
-- Beta 1.41 (île de Man, 60,6 km : 152 m par endroit avec 400 endroits ; Nordschleife, 52 à 64 m) : au plus
-- K.paceBinMeters m par endroit, K.paceBins endroits au moins (circuits ordinaires inchangés), K.paceBinsMax au plus.
-- Nombre changé (autre longueur de piste) : allure de la flotte oubliée ; renvoie true (le moteur oublie aussi
-- l'allure apprise de chaque voiture).
function M.size(d,length)
 local bins=length>0 and U.clamp(math.ceil(length/K.paceBinMeters),K.paceBins,K.paceBinsMax) or K.paceBins
 if bins==d.bins then return false end
 d.bins=bins; d.fleetNext=1; d.fleet={}
 return true
end
-- Allure de la flotte : médiane, à chaque endroit, des IA de la même classe (toutes hors multi-classes) qui l'ont
-- apprise ; quelques indices par image, toute la piste en moins de deux secondes.
function M.refresh(d,frame,states,multi)
 local classes=multi and K.classMax or 1
 local lists,counts=d.lists,d.counts
 -- Beta 1.41 : autant de tours de flotte par seconde quel que soit le nombre d'endroits.
 for _=1,math.ceil(K.fleetBinsPerFrame*d.bins/K.paceBins) do
  local b=d.fleetNext; d.fleetNext=b%d.bins+1
  for class=1,classes do counts[class]=0 end
  -- Un seul passage sur les voitures, réparties par classe (toutes dans la classe 1 hors multi-classes).
  for i=1,frame.count do
   local a=frame.cars[i]; local s=states[i]
   local class=multi and s.class or 1
   if a.valid and not a.player and not a.safetyCar and s.paceCount>=K.paceMinBins then
    local v=s.pace[b]
    if v>0 then
     -- Insertion triée : la médiane se lit directement.
     local list=lists[class]; local count=counts[class]
     local at=count; while at>=1 and list[at]>v do list[at+1]=list[at]; at=at-1 end
     list[at+1]=v; counts[class]=count+1
    end
   end
  end
  for class=1,classes do
   local f=d.fleet[class]
   if not f then f={}; for j=1,d.bins do f[j]=0 end; d.fleet[class]=f end
   local count=counts[class]
   f[b]=count>0 and lists[class][floor(count/2)+1] or 0
  end
 end
end
-- Allure libre de référence (m/s) de la voiture i à l'indice b : la plus élevée de son allure apprise et de celle de
-- sa classe (un mauvais passage isolé ne crée pas d'endroit trop sévère) ; 0 si aucune n'est connue.
function M.pace(d,states,i,b,multi)
 local s=states[i]
 local own=s.paceCount>=K.paceMinBins and s.pace[b] or 0
 local f=d.fleet[multi and s.class or 1]
 -- Beta 1.61 (tranche B) : allure gardée du circuit (src/pacemap.lua) en dernier repli, avant la vitesse fixe.
 if s.priorMap then local v=max(own,f and f[b] or 0); if v==0 then v=s.priorMap[b] or 0 end return v end
 return max(own,f and f[b] or 0)
end
-- Vitesse de référence (m/s) d'un régime : allure plus lente du pourcentage ; allure inconnue : vitesse de repli
-- (0 : aucune). Jamais sous le minimum (épingles).
function M.reference(d,states,i,b,multi,pct,fallbackKmh)
 local pace=M.pace(d,states,i,b,multi)
 local v=pace>0 and pace/(1+pct/100) or (fallbackKmh or 0)/3.6
 if v<=0 then return 0 end
 return max(K.deltaMinKmh/3.6,v)
end
-- Double drapeau jaune : Slow Zone à vitesse fixe (endurance) si elle est réglée, sinon allure plus lente du
-- pourcentage de zone.
-- fallbackKmh (Beta 1.47, IA) : vitesse de repli de l'allure inconnue (défaut : yellowSpeedKmh).
function M.zoneReference(d,states,i,b,multi,p,fallbackKmh)
 if p.slowZoneKmh>0 then return max(K.deltaMinKmh,p.slowZoneKmh)/3.6 end
 return M.reference(d,states,i,b,multi,p.zoneDeltaPct,fallbackKmh or p.yellowSpeedKmh)
end
-- Régime de delta du joueur hors zone : genre, pourcentage et vitesse de repli. Voiture de sécurité appelée ou encore
-- dans la voie des stands : delta FCY. Drapeau rouge : jusqu'à la voie des stands.
local function regime(inc,frame,p,a)
 if inc.red then if a.pit then return '' end; return 'red',p.redDeltaPct,p.redFlagSpeedKmh end
 if not inc.neutral then return '' end
 -- Beta 1.60 (tranche E) : tour de formation du départ : aucun temps delta (tenir sa place suffit).
 if inc.formation then return '' end
 local mode=inc.neutralMode
 if mode=='vsc' then return 'vsc',p.vscDeltaPct,p.fcySpeedKmh end
 if mode=='sc' then
  local merging=inc.safetyPhase=='call' or inc.safety>0 and frame.cars[inc.safety].pit
  if merging then return 'scCall',p.fcyDeltaPct,p.fcySpeedKmh end
  -- Relecture du lot 3 (S5) : voiture de sécurité en piste à son allure libre : la référence du joueur est celle du
  -- rattrapage des IA (K.scCatchPct), sinon il ne pouvait pas rejoindre la file sans infraction.
  return 'sc',K.scCatchPct,K.scNominalKmh+K.scCatchUp
 end
 return 'fcy',p.fcyDeltaPct,p.fcySpeedKmh
end
-- Phases successives d'une même neutralisation par voiture de sécurité : le delta continue.
local chained={scCall=true,sc=true,fcy=true}
local function sectors(length) return U.clamp(floor(length/K.miniSectorLength+0.5),K.miniSectorsMin,K.miniSectorsMax) end
-- Avance l'accumulateur de la distance parcourue depuis l'image précédente ; vrai au passage d'un mini-secteur. Saut
-- (téléportation, retour) : simple recalage. Recul ou arrêt : le temps passe sans avancer, le delta grandit.
local function advance(acc,a,length,dt,vref,count)
 local crossed=false
 if acc.last>=0 and vref>0 then
  local ds=U.spline(a.spline-acc.last)*length
  if ds>=0 and ds<=K.deltaJump then acc.delta=min(K.deltaCap,acc.delta+dt-ds/vref)
  elseif ds<0 and ds>-K.deltaJump then acc.delta=min(K.deltaCap,acc.delta+dt) end
 end
 acc.last=a.spline
 local s=floor((a.spline%1)*count)
 if acc.sector>=0 and s~=acc.sector then crossed=true end
 acc.sector=s
 return crossed
end
-- Plancher de freinage : depuis la vitesse au signal, réduite à la décélération d'approche après le temps de réaction.
local function brakeFloor(kmh,since,decel) return kmh/3.6-decel*max(0,since-K.penaltyBrakeMargin) end
local function zoneExists(inc,slot)
 for z=1,inc.zoneCount do if inc.zones[z].slot==slot then return true end end
 return false
end
-- queued : le joueur a rejoint la file derrière la voiture de sécurité (delta figé, jamais jugé).
function M.update(d,frame,p,inc,states,now,dt,queued)
 d.infraction=false; d.value=nil; d.kind=''
 local i=frame.player
 if i==0 or frame.length<=0 then d.course.on=false; d.zone.on=false; d.inside=false; d.wasZone=false; return end
 local a=frame.cars[i]
 local multi=p.multiClass==true
 local count=sectors(frame.length)
 local b=bin(a.spline,d.bins)
 local tolerance=p.deltaTolerance
 -- Neutralisation ou drapeau rouge.
 local c=d.course
 local kind,pct,fallback=regime(inc,frame,p,a)
 if kind~=c.kind then
  if kind=='' then c.on=false
  elseif not (c.on and chained[c.kind] and chained[kind]) then
   c.on=true; c.delta=K.deltaStart; c.last=-1; c.sector=-1; c.pit=false; d.onsetAt=now; d.onsetKmh=a.kmh
  end
  c.kind=kind
 end
 if c.on then
  if a.pit or not a.valid or not a.splineValid then c.pit=true; c.last=-1; c.sector=-1
  else
   -- Sortie des stands : nouveau départ, plancher depuis la vitesse de sortie.
   if c.pit then c.pit=false; c.delta=K.deltaStart; d.onsetAt=now; d.onsetKmh=a.kmh end
   if kind=='sc' and queued then
    c.delta=max(c.delta,K.deltaStart); c.last=a.spline; c.sector=floor((a.spline%1)*count)
   else
    local vref=M.reference(d,states,i,b,multi,pct,fallback)
    if kind=='scCall' then vref=min(vref,(K.scNominalKmh-K.scMergeMargin)/3.6) end
    vref=max(vref,brakeFloor(d.onsetKmh,now-d.onsetAt,p.yellowDecel))
    if advance(c,a,frame.length,dt,vref,count) and c.delta<-tolerance then
     d.infraction=true; d.infractionKind=kind; d.infractionValue=c.delta
    end
   end
  end
 end
 -- Double drapeau jaune : delta propre à la zone, remis à zéro à l'entrée (depuis l'extérieur de toute zone), plancher
 -- de freinage depuis le panneau d'approche. Simple jaune (incident hors piste) : pas de delta.
 local z=d.zone
 if inc.playerZone and not d.wasZone then d.signalAt=now; d.signalKmh=a.kmh end
 d.wasZone=inc.playerZone
 local inside=inc.playerInside and not a.pit and a.valid and a.splineValid
 if inside and not d.inside then
  d.zoneSlot=inc.playerZoneSlot
  if inc.playerZoneDouble then z.on=true; z.kind='zone'; z.delta=0; z.last=-1; z.sector=-1 end
 elseif inside and not z.on and inc.playerZoneDouble then
  -- Zone devenue double pendant la traversée (zone simple qui chevauche une double, incident revenu en piste) :
  -- delta de zone à zéro, plancher de freinage depuis la vitesse de cet instant.
  d.signalAt=now; d.signalKmh=a.kmh; z.on=true; z.kind='zone'; z.delta=0; z.last=-1; z.sector=-1
 elseif not inside and d.inside then
  -- Sortie jugée seulement si la zone existe encore : incident dégagé pendant la traversée, rien n'est jugé.
  if z.on and zoneExists(inc,d.zoneSlot) and z.delta<-tolerance and not d.infraction then
   d.infraction=true; d.infractionKind='zone'; d.infractionValue=z.delta
  end
  z.on=false
 end
 d.inside=inside
 -- Sortie jugée sur la zone où se trouve le joueur à cet instant.
 if inside and inc.playerZoneSlot>0 then d.zoneSlot=inc.playerZoneSlot end
 if z.on then
  local vref=M.zoneReference(d,states,i,b,multi,p)
  vref=max(vref,brakeFloor(d.signalKmh,now-d.signalAt,p.yellowDecel))
  if advance(z,a,frame.length,dt,vref,count) and z.delta<-tolerance and not d.infraction then
   d.infraction=true; d.infractionKind='zone'; d.infractionValue=z.delta
  end
  d.value=z.delta; d.kind='zone'
 elseif c.on and not c.pit then d.value=c.delta; d.kind=c.kind end
end
-- Pénalité décidée : nouveau départ, avec la marge de réaction.
function M.penalized(d)
 d.course.delta=max(d.course.delta,K.deltaStart); d.zone.delta=max(d.zone.delta,K.deltaStart)
end
return M
