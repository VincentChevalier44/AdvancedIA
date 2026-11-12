-- Décisions pures ; les écritures restent dans applier, la lecture dans snapshot.
local K=require('src/config').K
local U=require('src/util')
local M={}
function M.new() return {wet=false,initialized=false,pending=false,pendingAt=0,changedAt=-math.huge} end
-- Composé sec propre à chaque IA parmi les gommes sèches autorisées (dur, medium, tendre, super tendre...), stable
-- d'une session à l'autre : choisi quand l'IA doit quitter un pneu pluie ou un pneu inadapté. Beta 1.24 : une gomme par
-- nom court (la première) ; les variantes d'adhérence d'un même mod (grip F3, F2, F1...) ne sont jamais tirées.
function M.dryChoice(a,seed)
 local list=a.dryPrimary and #a.dryPrimary>0 and a.dryPrimary or a.dryList
 if list and #list>0 then return list[math.min(#list,math.floor(U.unit(seed or 0,a.index or 0,K.tyreSalt)*#list)+1)] end
 return a.dryCompound or -1
end
-- Beta 1.61 (tranche E, réglage weatherLive) : arrêts météo étalés. Au plus K.wxPitWave IA appelées à la fois hors de
-- la voie des stands ; les plus mal chaussées d'abord (live.urgency), jamais retenue en pneus secs sous forte pluie
-- (live.critical) ; une IA appelée garde sa place jusqu'à la voie des stands, K.wxCallMax s au plus (relecture : une IA
-- qui ne rentre pas libère sa place et repasse derrière les autres pendant le même temps).
local function stagger(live,frame,commands,now)
 local busy=0
 for i=1,frame.count do
  if not commands[i].weatherPit then live.called[i]=false; live.calledAt[i]=nil
  elseif live.critical[i] then live.called[i]=true
  elseif live.called[i] and not frame.cars[i].pit then
   if now-(live.calledAt[i] or now)>=K.wxCallMax then live.called[i]=false; live.calledAt[i]=nil; live.skipUntil[i]=now+K.wxCallMax
   else busy=busy+1 end
  end
 end
 while busy<K.wxPitWave do
  local best,chosen=0,0
  for i=1,frame.count do
   if commands[i].weatherPit and not live.called[i] and not frame.cars[i].pit and now>=(live.skipUntil[i] or -math.huge) and (live.urgency[i] or 0)>best then best=live.urgency[i]; chosen=i end
  end
  if chosen==0 then break end
  live.called[chosen]=true; live.calledAt[chosen]=now; busy=busy+1
 end
 for i=1,frame.count do
  local cmd=commands[i]
  if cmd.weatherPit and not live.called[i] and not frame.cars[i].pit then cmd.weatherPit=false end
 end
end
M.stagger=stagger
function M.step(w,frame,commands,p,now,states,seed)
 local rain,water=frame.rain or 0,frame.water or 0
 local desired=w.wet
 if frame.wet>=K.weatherWetOn or rain>=K.weatherRainOn or water>=K.weatherWaterOn then desired=true
 elseif frame.wet<=K.weatherWetOff and rain<=K.weatherRainOff and water<=K.weatherWaterOff then desired=false end
 if not w.initialized then w.wet=desired; w.pending=desired; w.initialized=true end
 if desired~=w.pending then w.pending=desired; w.pendingAt=now end
 if desired~=w.wet and now-w.pendingAt>=K.weatherConfirm then w.wet=desired; w.changedAt=now end
 -- Beta 1.61 (tranche E) : données de src/wx.lua (réglage weatherLive ; nil : rien ne change).
 local live=w.live
 for i=1,frame.count do
  local a,cmd=frame.cars[i],commands[i]
  local healthy=not states or not states[i].excluded and now>=states[i].errorUntil
  cmd.weatherManaged=p.section_weather and p.weatherTyresEnabled and healthy and a.valid and a.control and not a.player and not a.offtrack and not a.finished and not a.safetyCar
  cmd.weatherRain=w.wet; cmd.weatherCompound=-1; cmd.weatherPit=false; cmd.weatherGrip=1; cmd.weatherGrid=false
  if cmd.weatherManaged and a.tyresKnown then
   local target=a.currentTyreIsDry and a.compoundIndex or M.dryChoice(a,seed)
   -- Sur la grille ou à l'apparition : conditions présentes pour tous. En piste, avec la météo en direct : état propre au
   -- pilote (seuil selon son audace, arrêt anticipé, averse courte) et eau projetée pour le choix du pneu pluie.
   local grid=(not frame.started or frame.startIn>0 or frame.time<K.spawnWindow) and not a.pit and a.kmh<=K.tyreStopSpeed
   local wet,heavy=w.wet,math.max(frame.wet,rain,water)>=K.weatherHeavy
   if live and not grid and live.carWet[i]~=nil then wet=live.carWet[i]; heavy=live.heavy==true or live.critical[i]==true; cmd.weatherRain=wet end
   if wet then
    -- Sous la pluie, intermédiaires et pneus pluie conviennent tous deux : une IA déjà équipée de l'un ou de l'autre
    -- les garde (la logique pluie de CSP choisit souvent les pneus pluie ; les changer relançait un va-et-vient aux stands).
    local current=a.compoundIndex
    local onRain=current~=nil and current>=0 and (current==a.wetCompound or current==a.interCompound)
    if onRain then target=current
    else target=(heavy and a.wetCompound or a.interCompound) or -1 end
    if target<0 then target=a.wetCompound or -1 end
    if target<0 then target=a.interCompound or -1 end
    if target<0 and a.nativeRainTyresKnown and not a.nativeRainTyres then cmd.weatherGrip=1+p.rainGripBoostPct/100*math.max(frame.wet,rain,water) end
   end
   cmd.weatherCompound=target
   -- Avant le départ (grille) ou dans les premières secondes d'une session (voitures apparues à l'arrêt, journée circuit,
   -- essais) : la gomme adaptée est montée sur place au lieu d'un arrêt au premier passage.
   cmd.weatherGrid=grid
   cmd.weatherPit=target>=0 and a.compoundIndex~=nil and a.compoundIndex~=target and not cmd.weatherGrid
  end
 end
 if live then stagger(live,frame,commands,now) end
end
return M
