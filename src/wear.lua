-- Beta 1.60 (tranche D, réglage wearPace, tous les profils, coupé par défaut ; idée d'Artood2s) : l'usure des pneus, la
-- gomme et la charge de carburant agissent sur le rythme des IA. Appelé par src/engine.lua après le pilotage, à côté de
-- la stratégie : cmd.levelScale par produit (une part volontairement petite : la physique d'AC ralentit déjà une voiture
-- usée ou lourde) ; s.wearBrake dans e.states[i], lu par src/director.lua dans les zones de freinage, et s.wearExit pour
-- la remise des gaz (src/mood.lua) ; champ absent : neutre. Décisions pures, cibles revues une fois par seconde,
-- variation du niveau étalée (K.wearScaleRate par seconde). Tableaux créés une fois, aucune chaîne par image.
--  - usure (échelle vérifiée en jeu seulement, comme la stratégie) : rien sous K.wearPaceStart (ou la moitié du seuil), puis jusqu'à
--    K.wearPaceAtThreshold au seuil d'usure de la stratégie, puis la falaise jusqu'à K.wearPaceCliff à 100 % ;
--  - gomme (gommes sèches du modèle classées) : K.compoundPaceStep par cran plus tendre que la gomme du milieu ;
--  - carburant : K.fuelPace × (0,5 - carburant / réservoir) ;
--  - pneus en surchauffe (K.wearHotDelta °C au-dessus de l'optimum pendant K.wearHotTime s) : -K.wearHotPct.
local U=require('src/util')
local K=require('src/config').K
local StartVar=require('src/startvar')
local max,min,abs=math.max,math.min,math.abs
local M={}
function M.new()
 local t={session=-1,on=false,nextAt=-math.huge,ranks={},scale={},target={},loss={},hot={},logAt={},logScale={},cliff={},avg=1,worst=1,count=0}
 for i=1,K.maxCars do t.scale[i]=1; t.target[i]=1; t.loss[i]=0; t.hot[i]=-1; t.logAt[i]=-math.huge; t.logScale[i]=1; t.cliff[i]=false end
 return t
end
function M.reset(t)
 t.session=-1; t.nextAt=-math.huge; t.avg=1; t.worst=1; t.count=0
 for i=1,K.maxCars do t.scale[i]=1; t.target[i]=1; t.loss[i]=0; t.hot[i]=-1; t.logAt[i]=-math.huge; t.logScale[i]=1; t.cliff[i]=false end
end
function M.rebase(t,amount)
 if U.finite(t.nextAt) then t.nextAt=t.nextAt-amount end
 for i=1,K.maxCars do
  if t.hot[i]>=0 then t.hot[i]=t.hot[i]-amount end
  if U.finite(t.logAt[i]) then t.logAt[i]=t.logAt[i]-amount end
 end
end
-- Perte de rythme due à l'usure (part du niveau, 0 à K.wearPaceCliff) : trois segments.
function M.curve(w,threshold)
 threshold=U.clamp(threshold,0.02,0.99)
 -- Seuil de la stratégie sous K.wearPaceStart (défaut : 30 %) : départ à la moitié du seuil, jamais une marche.
 local start=min(K.wearPaceStart,threshold*0.5)
 if w<=start then return 0 end
 if w<=threshold then return K.wearPaceAtThreshold*(w-start)/(threshold-start) end
 return K.wearPaceAtThreshold+(K.wearPaceCliff-K.wearPaceAtThreshold)*(min(1,w)-threshold)/(1-threshold)
end
-- Gain de rythme de la gomme montée : crans plus tendres (positif) ou plus durs (négatif) que la gomme du milieu des
-- gommes sèches du modèle ; 0 si les gommes ne sont pas classées ou si la gomme montée n'en fait pas partie (pluie).
function M.compound(a,ranks)
 if not ranks then return 0 end
 local current=a.compoundIndex and ranks[a.compoundIndex]
 if not current then return 0 end
 local softer,harder=0,0
 for _,r in pairs(ranks) do if r<current then softer=softer+1 elseif r>current then harder=harder+1 end end
 -- Place parmi les gommes classées : autant de gommes plus dures que de plus tendres = gomme du milieu.
 return U.clamp((harder-softer)/2*K.compoundPaceStep,-K.compoundPaceMax,K.compoundPaceMax)
end
-- Gain de rythme de la charge de carburant : réservoir à moitié = neutre, plus léger = plus vite.
function M.fuel(a)
 if (a.fuel or -1)<0 or (a.maxFuel or 0)<=0 then return 0 end
 return K.fuelPace*(0.5-U.clamp(a.fuel/a.maxFuel,0,1))
end
local function wearOf(a)
 if not a.wearKnown or not a.tyreWear then return -1,-1 end
 local w=a.tyreWear
 return max(w[1] or 0,w[2] or 0,w[3] or 0,w[4] or 0),max(w[3] or 0,w[4] or 0)
end
local function name(a) return a.name or ('#'..tostring(a.index or '?')) end
local function eligible(a,s,e,i)
 return a.valid and a.control and not a.player and not a.finished and not a.safetyCar and not s.disqualified and not (e.penalties.ai.dq and e.penalties.ai.dq[i])
end
local function clearCar(t,s,i) t.scale[i]=1; t.target[i]=1; t.loss[i]=0; t.hot[i]=-1; t.cliff[i]=false; t.logScale[i]=1; if s then s.wearBrake=nil; s.wearExit=nil end end
-- Perte de rythme due à l'usure appliquée en ce moment à la voiture i (0 si le réglage est coupé ou l'usure non fiable) :
-- lue par la stratégie pour estimer le gain d'un undercut.
function M.lossOf(t,i) return t.on and t.loss[i] or 0 end
function M.update(t,e,frame,now,dt)
 local p=e.run
 if not p.wearPace or frame.online or frame.replay then
  if t.on then t.on=false; for i=1,K.maxCars do clearCar(t,e.states[i],i) end end
  return
 end
 t.on=true
 local review=now>=t.nextAt
 if review then t.nextAt=now+K.wearPeriod end
 local trusted=e.strategy.wearTrust=='trusted'
 local threshold=U.clamp((p.strategyTyreWearPct or 0)/100,K.strategyWearMin,K.strategyWearMax)
 local sum,n,worst=0,0,1
 for i=1,frame.count do
  local a=frame.cars[i]; local s=e.states[i]
  if not eligible(a,s,e,i) then clearCar(t,s,i)
  else
   if review then
    local w,rear=-1,-1
    if trusted then w,rear=wearOf(a) end
    local loss=w>=0 and M.curve(w,threshold) or 0
    t.loss[i]=loss
    local model=a.id or ''
    local ranks=t.ranks[model]
    if ranks==nil and a.tyresKnown then ranks=StartVar.ranks(a) or false; t.ranks[model]=ranks end
    local compound=M.compound(a,ranks)
    local fuel=M.fuel(a)
    -- Surchauffe : moyenne des quatre pneus au-dessus de l'optimum, tenue K.wearHotTime s.
    local hot=0
    if a.wearKnown and a.tyreTemp and a.tyreOptimum and (a.tyreOptimum[1] or 0)>0 and not a.pit then
     local over=((a.tyreTemp[1] or 0)+(a.tyreTemp[2] or 0)+(a.tyreTemp[3] or 0)+(a.tyreTemp[4] or 0)-(a.tyreOptimum[1] or 0)-(a.tyreOptimum[2] or 0)-(a.tyreOptimum[3] or 0)-(a.tyreOptimum[4] or 0))/4
     if over>=K.wearHotDelta then
      if t.hot[i]<0 then t.hot[i]=now end
      if now-t.hot[i]>=K.wearHotTime then hot=K.wearHotPct end
     else t.hot[i]=-1 end
    else t.hot[i]=-1 end
    t.target[i]=U.clamp(1-loss+compound+fuel-hot,1-K.wearScaleMaxLoss,1+K.wearScaleMaxGain)
    if w>=0 then
     s.wearBrake=1+K.wearBrakeCaution*U.clamp((w-K.wearPaceStart)/(1-K.wearPaceStart),0,1)
     s.wearExit=1+K.wearExitGain*max(0,rear)
    else s.wearBrake=nil; s.wearExit=nil end
    -- Journal : pneus au bout (une fois par relais), puis une ligne par variation de K.wearLogStep, espacée de K.wearLogGap s.
    if w>=0 and w>threshold and not t.cliff[i] then
     t.cliff[i]=true
     U.log(e.log,now,'INFO',string.format('rythme: %s pneus au bout (%.0f %%), rythme %.1f %%',name(a),w*100,(t.target[i]-1)*100),i)
    elseif w>=0 and w<threshold-K.lockWearReset then t.cliff[i]=false end
    if abs(t.target[i]-t.logScale[i])>=K.wearLogStep and now-t.logAt[i]>=K.wearLogGap then
     t.logScale[i]=t.target[i]; t.logAt[i]=now
     local index=a.compoundIndex
     U.log(e.log,now,'INFO',string.format('rythme: %s %+.1f %% (pneus %.0f %%, gomme %s, carburant %.0f %%)',name(a),(t.target[i]-1)*100,max(0,w)*100,index~=nil and a.tyreNames and a.tyreNames[index] or '?',(a.maxFuel or 0)>0 and (a.fuel or 0)/a.maxFuel*100 or 0),i)
    end
   end
   -- Variation étalée du niveau, puis produit (comme la stratégie).
   local step=K.wearScaleRate*(dt or 0)
   local scale=t.scale[i]; local target=t.target[i]
   if scale<target then scale=min(target,scale+step) elseif scale>target then scale=max(target,scale-step) end
   t.scale[i]=scale
   if scale~=1 then local cmd=e.commands[i]; cmd.levelScale=cmd.levelScale*scale end
   sum=sum+scale; n=n+1; if scale<worst then worst=scale end
  end
 end
 -- Pour le résumé de la minute (texte ajouté par le coordinateur) : moyenne et plus forte baisse du plateau.
 t.count=n; t.avg=n>0 and sum/n or 1; t.worst=worst
end
return M
