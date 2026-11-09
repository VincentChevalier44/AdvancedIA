-- Sortie des stands (Beta 1.41) : décisions pures, écrites par l'applicateur. Journées circuit du 3 novembre : à l'île
-- de Man, une IA qui sortait des stands heurtée deux fois à la jonction, à 141 puis 131 km/h d'écart (invisible pour les
-- IA en piste tant qu'elle était dans la voie) ; sur la Nordschleife (Touristenfahrten), onze arrêts au même endroit,
-- à la jonction.
-- Jonction apprise à chaque sortie de la voie des stands en roulant (au moins K.mergeLearnPit s dans la voie, à moins de
-- K.mergeLearnKmh km/h, jamais un déplacement) ; voitures de la voie près de la jonction vues par les IA en piste (radar
-- avant, obstacle, dépassement : a.merging) ; IA retenue au bout de la voie (règle D12 : seule commande dans la voie des
-- stands avec la retenue à l'emplacement) tant qu'une voiture en piste arrive à la jonction, K.mergeHoldMax s au plus.
local U=require('src/util')
local K=require('src/config').K
local abs,max,min=math.abs,math.max,math.min
local M={}
-- boxSeen, boxSpline : emplacement de la voiture pendant ce passage dans la voie des stands.
local function car() return {wasPit=false,pitFor=0,holding=false,released=false,holdFor=0,boxSeen=false,boxSpline=0,exitAt=-math.huge} end
function M.new()
 local t={spline=-1,samples=0,outliers=0,holds=0,cars={}}
 for i=1,K.maxCars do t.cars[i]=car() end
 return t
end
-- Recalage du temps (Beta 1.44 : instant de sortie des stands).
function M.rebase(t,amount) for i=1,K.maxCars do local c=t.cars[i]; if c.exitAt>-math.huge then c.exitAt=c.exitAt-amount end end end
function M.reset(t)
 t.spline=-1; t.samples=0; t.outliers=0; t.holds=0
 for i=1,K.maxCars do t.cars[i]=car() end
end
-- Distance (m) le long de la piste jusqu'à la jonction : positive avant elle, négative après.
function M.before(t,spline,length) return U.spline(t.spline-spline)*length end
-- Sortie relevée à spline : moyenne glissante ; trois sorties de suite à plus de K.mergeOutlier m : autre jonction.
local function learn(t,spline,length,log,now)
 if t.spline<0 then t.spline=spline; t.samples=1; t.outliers=0
 else
  local offset=U.spline(spline-t.spline)
  if abs(offset)*length>K.mergeOutlier then
   t.outliers=t.outliers+1
   if t.outliers<3 then return end
   t.spline=spline; t.samples=1; t.outliers=0
  else t.spline=(t.spline+offset*K.mergeAlpha)%1; t.samples=t.samples+1; t.outliers=0 end
 end
 if t.samples==1 then U.log(log,now,'INFO',string.format('jonction des stands: relevee a %.0f m',t.spline*length),-1) end
end
-- Voiture en piste (joueur compris) qui arrive à la jonction dans les window s, ou la passe à moins de K.mergeClear m :
-- la plus proche (indice, secondes). Beta 1.44 : jamais une voiture sortie des stands depuis moins de K.mergeExitGrace s
-- (elle vient de la voie, devant l'IA qui attend : relevé du 4 novembre, attente de 0,0 s sur la voiture qui sortait).
-- Beta 1.51 : push (essais et qualifications) : seulement une voiture en tour lancé.
local function arriving(t,frame,i,window,now,push)
 local length=frame.length; local best,soonest=0,math.huge
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=i and b.valid and not b.pit and b.splineValid and b.kmh>=K.mergeTrafficKmh and now-t.cars[j].exitAt>=K.mergeExitGrace and (not push or push[j]) then
   local d=M.before(t,b.spline,length)
   local time=d>0 and d/max(b.speed,1) or 0
   if d>=-K.mergeClear and time<=window and time<soonest then best=j; soonest=time end
  end
 end
 return best,soonest
end
-- Une fois par image : jonction, voitures de la voie près d'elle (a.merging), retenue (cmd.mergeHold). red : drapeau
-- rouge (toutes rentrent et restent aux stands : aucune retenue). Relecture de la Beta 1.41 : retenue en journée
-- circuit seulement (profile 'J' ; en course, essais et qualifications, la sortie des stands reste celle d'AC) et
-- seulement si l'arrêt natif répond (canStop) ; commencée seulement pour une IA qui roule vers la sortie après avoir
-- dépassé son emplacement (jamais une voiture qui roule vers le sien, au bout de la voie).
-- Beta 1.51 (qualifications : une IA sortie des stands juste devant le joueur en tour rapide) : push (essais et
-- qualifications, tours lancés actifs) : retenue aussi, seulement pour une voiture en tour lancé qui arrive.
function M.update(t,frame,commands,now,dt,log,red,profile,canStop,push)
 local length=frame.length
 local holds=(profile=='J' or push~=nil and (profile=='P' or profile=='Q')) and canStop==true
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]; local cmd=commands[i]
  if c.wasPit and not a.pit and a.valid and a.splineValid and not a.teleport and c.pitFor>=K.mergeLearnPit and a.kmh<=K.mergeLearnKmh and length>0 then
   learn(t,a.spline,length,log,now)
  end
  if a.pit and not a.inPitBox then c.pitFor=c.pitFor+dt else c.pitFor=0 end
  if c.wasPit and not a.pit and not a.teleport then c.exitAt=now end
  c.wasPit=a.pit==true
  if a.inPitBox and a.splineValid then c.boxSeen=true; c.boxSpline=a.spline elseif not a.pit then c.boxSeen=false end
  local d=t.spline>=0 and length>0 and a.valid and a.pit and not a.inPitBox and a.splineValid and M.before(t,a.spline,length) or nil
  -- IA pilotée seulement (jamais le joueur ni la voiture de sécurité), une fois par sortie.
  local zone=d~=nil and holds and a.control and not a.player and not a.safetyCar and not red and not c.released and d>=K.mergeHoldMin and d<=K.mergeHoldZone
   and (c.holding or c.boxSeen and d<=M.before(t,c.boxSpline,length)-K.mergeBoxClear and a.kmh>=K.mergeHoldStartKmh)
  if zone then
   local window=min(K.mergeWindowMax,K.mergeWindow+d/max(a.speed,K.mergeCrawl))
   local j,time=arriving(t,frame,i,window,now,profile~='J' and push or nil)
   if j>0 and c.holdFor<K.mergeHoldMax then
    if not c.holding then
     c.holding=true; t.holds=t.holds+1; if profile~='J' then t.qualiHolds=(t.qualiHolds or 0)+1 end
     U.log(log,now,'INFO',string.format('jonction des stands: %s attend %s%s (a la jonction dans %.1f s, %.0f m avant elle)',a.name,frame.cars[j].name,profile~='J' and ' en tour lance' or '',time,d),i)
    end
    c.holdFor=c.holdFor+dt
   elseif c.holding then
    c.holding=false; c.released=true
    U.log(log,now,'INFO',string.format('jonction des stands: %s repart apres %.1f s (%s)',a.name,c.holdFor,j>0 and 'attente maximale' or 'piste libre'),i)
   end
  elseif c.holding then
   c.holding=false; c.released=true
   U.log(log,now,'INFO',string.format('jonction des stands: %s repart apres %.1f s (%s)',a.name,c.holdFor,red and 'drapeau rouge' or not holds and 'retenue coupee' or 'hors de la zone d attente'),i)
  end
  -- Nouvelle sortie : hors de la voie des stands ou à l'emplacement.
  if not a.pit or a.inPitBox then c.released=false; c.holding=false; c.holdFor=0 end
  cmd.mergeHold=c.holding
  -- Vue des IA en piste près de la jonction, sauf retenue : elle attend (à l'arrêt, une voie qui longe la trajectoire
  -- ferait freiner le radar de chaque voiture qui passe). Relecture : seulement en roulant, ou au pas tout près de la
  -- jonction ; une file arrêtée dans la voie, le joueur qui attend et une IA arrêtée restent invisibles.
  a.merging=d~=nil and d<=K.mergeBefore and d>=-K.mergeAfter and not c.holding
   and (a.kmh>=K.mergeSeenKmh or abs(d)<=K.mergeSeenNear and a.kmh>=K.mergeSeenCrawl)
 end
end
-- App à l'arrêt (pause, panique, aucun onglet) : aucune retenue ; passage dans la voie oublié (une sortie pendant
-- l'arrêt n'apprend rien à la reprise).
function M.idle(t,commands)
 for i=1,K.maxCars do commands[i].mergeHold=false; local c=t.cars[i]; c.wasPit=false; c.pitFor=0 end
end
return M
