-- Beta 1.61 (tranche E, réglage weatherLive, coupé par défaut). Météo en direct : tendance et prévision, humidité
-- effective par voiture selon ses pneus (s.wxWet dans e.states[i], lu par src/director.lua et src/mistakes.lua ; champ
-- absent : neutre, l'humidité de la piste sert comme avant), et données du choix des pneus préparées pour
-- src/weather.lua, qui reste le seul endroit où une gomme est choisie (w.live : état par voiture, arrêt anticipé,
-- averse courte, eau projetée, urgence de l'arrêt). Décisions pures, une fois par K.wxPeriod s ; tableaux créés une fois,
-- journal sur transition seulement. Réglage coupé : rien n'est écrit, rien n'est lu.
local K=require('src/config').K
local U=require('src/util')
local Pitloss=require('src/pitloss')
local Strategy=require('src/strategy')
local max,min,floor=math.max,math.min,math.floor
local M={}
local SIDE_KEY='AdvancedIA.weather'
-- Classe de pluie d'un type de météo de CSP (ac.WeatherType, 0 à 32) : none, light, rain, heavy ; type inconnu : unknown.
local CLASS={[0]='rain','heavy','heavy','light','light','rain','light','rain','heavy','light','rain','heavy','light','rain','heavy',
 'none','none','none','none','none','none','none','none','none','none','none','rain','heavy','heavy','none','none','none','rain'}
local LABEL={none='sec',light='pluie fine',rain='pluie',heavy='forte pluie'}
local TREND={wetting='humide',steady='stable',drying='sechante'}
function M.rainClass(kind)
 if type(kind)~='number' or kind~=kind then return 'unknown' end
 return CLASS[floor(kind)] or 'unknown'
end
local function clear(list) for k in pairs(list) do list[k]=nil end end
local function blank(t)
 t.at=-math.huge; t.live=false; t.pw=-1; t.pr=-1; t.pa=-1; t.sw=0; t.sr=0; t.sa=0; t.trend='steady'; t.eta=-1
 t.forecast='unknown'; t.forecastIn=-1; t.pt=-1; t.st=0; t.fcur=-2; t.fup=-2; t.fq=-2; t.noForecast=false; t.forecastLogged=''
 t.onsetAt=-math.huge; t.trendAt=-math.huge; t.heavy=false; t.proj=0; t.aiDry=0; t.aiRain=0; t.body=''; t.key=''
 clear(t.carWet); clear(t.pend); clear(t.pendAt); clear(t.stopAt); clear(t.cls); clear(t.early); clear(t.hold); clear(t.called); clear(t.calledAt); clear(t.skipUntil)
 clear(t.urgency); clear(t.critical); clear(t.waitLogged)
 local n=t.stats; n.count=0; n.grip=0; n.early=0; n.gamble=0; n.wrong=0
end
function M.new()
 local t={session=-1,carWet={},pend={},pendAt={},stopAt={},cls={},early={},hold={},called={},calledAt={},skipUntil={},urgency={},critical={},waitLogged={},stats={}}
 blank(t)
 return t
end
function M.reset(t) t.session=-1; blank(t) end -- (t,now)
function M.rebase(t,amount)
 t.at=t.at-amount; t.onsetAt=t.onsetAt-amount; t.trendAt=t.trendAt-amount
 for i,v in pairs(t.pendAt) do t.pendAt[i]=v-amount end
 for i,v in pairs(t.stopAt) do t.stopAt[i]=v-amount end
 for i,v in pairs(t.calledAt) do t.calledAt[i]=v-amount end
 for i,v in pairs(t.skipUntil) do t.skipUntil[i]=v-amount end
end
-- Temps (s) avant la bascule de l'état sec/pluie d'aujourd'hui à la pente présente, au plus K.wxEtaMax ; -1 inconnu.
function M.eta(w,wetNow)
 if w.trend=='wetting' and not wetNow then
  local best=-1
  if w.sw>0 and w.pw<K.weatherWetOn then best=(K.weatherWetOn-w.pw)/w.sw end
  if w.sr>0 and w.pr<K.weatherRainOn then local t=(K.weatherRainOn-w.pr)/w.sr; if best<0 or t<best then best=t end end
  if w.sa>0 and w.pa<K.weatherWaterOn then local t=(K.weatherWaterOn-w.pa)/w.sa; if best<0 or t<best then best=t end end
  return best>=0 and min(best,K.wxEtaMax) or -1
 elseif w.trend=='drying' and wetNow then
  local worst=0
  if w.pw>K.weatherWetOff then if w.sw>=0 then return -1 end; worst=max(worst,(w.pw-K.weatherWetOff)/-w.sw) end
  if w.pr>K.weatherRainOff then if w.sr>=0 then return -1 end; worst=max(worst,(w.pr-K.weatherRainOff)/-w.sr) end
  if w.pa>K.weatherWaterOff then if w.sa>=0 then return -1 end; worst=max(worst,(w.pa-K.weatherWaterOff)/-w.sa) end
  return min(worst,K.wxEtaMax)
 end
 return -1
end
-- Fin attendue de l'averse (s) : prévision sèche de CSP, ou pluie qui baisse à la pente présente ; -1 inconnue.
local function showerEnd(w)
 local best=-1
 if w.forecast=='none' and w.forecastIn>=0 then best=w.forecastIn end
 if w.sr<=-K.wxSlopeMin and w.pr>0 then local t=w.pr/-w.sr; if best<0 or t<best then best=t end end
 return best
end
-- Seuil d'un pilote : celui de tous décalé par son audace, tenu au-dessus d'une fraction du seuil de base.
local function threshold(base,shift) return max(base*0.3,base+shift) end
-- Humidité visée d'une voiture selon ses pneus (avant le suivi progressif) : pneus secs sur le mouillé, intermédiaires
-- sous forte pluie, pneus pluie sur piste qui sèche, talent du pilote sous la pluie, première pluie.
function M.carWet(wet,heavy,onDry,onInter,onRain,skill,onset)
 local target=wet
 if onDry then
  target=target*(1+K.wxSlickPenalty)
  if onset then target=target*K.wxOnsetCaution end
 elseif onRain then
  if onInter and heavy then target=target*(1+K.wxInterHeavy) end
  if wet<K.wxDryLine then target=max(target,K.wxWetOnDry) end
 end
 return U.clamp(target*skill,0,K.wxWetMax)
end
function M.skill(seed,index) return U.lerp(K.wxSkillMin,K.wxSkillMax,U.unit(seed or 0,index or 0,K.wxSkillSalt)) end
-- Texte de la clé annexe pour SpotterEnginer (au plus K.weatherKeyBytes octets) ; l'horodatage est celui du dernier
-- changement des autres champs.
function M.side(w,wet,rain,water,now)
 local nextTyre=w.trend=='wetting' and not w.wetNow and (w.heavy and 'wet' or 'inter') or w.trend=='drying' and w.wetNow and 'dry' or 'none'
 local body=string.format('v=1;wet=%.2f;rain=%.2f;water=%.2f;trend=%s;eta=%d;next=%s;forecast=%s;forecastIn=%d;aiDry=%d;aiRain=%d',
  wet,rain,water,w.trend,w.eta>=0 and floor(w.eta) or -1,nextTyre,w.forecast,w.forecastIn>=0 and floor(w.forecastIn) or -1,w.aiDry,w.aiRain)
 if body~=w.body then
  w.body=body
  local text=body..';stamp='..floor(max(0,now))
  if #text<=K.weatherKeyBytes then w.key=text end
 end
 return w.key
end
local function off(w,e,frame)
 for i=1,frame.count do local s=e.states[i]; if s then s.wxWet=nil end end
 if e.weather then e.weather.live=nil end
 if e.sideText then e.sideText[SIDE_KEY]=nil end
 blank(w)
end
function M.update(w,e,frame,now)
 local p=e.run
 if not (p and p.weatherLive==true) then
  if w.live then off(w,e,frame) end
  return
 end
 if e.weather then e.weather.live=p.weatherTyresEnabled and w or nil end
 if now-w.at<K.wxPeriod then return end
 local step=w.live and min(now-w.at,K.wxPeriod*5) or 0
 w.at=now; w.live=true
 local wet,rain,water=frame.wet or 0,frame.rain or 0,frame.water or 0
 local wetNow=e.weather~=nil and e.weather.wet==true
 w.wetNow=wetNow
 -- Tendance : pentes lissées des trois mesures.
 if w.pw>=0 and step>0 then
  w.sw=U.ema(w.sw,(wet-w.pw)/step,step,K.wxTrendTau); w.sr=U.ema(w.sr,(rain-w.pr)/step,step,K.wxTrendTau); w.sa=U.ema(w.sa,(water-w.pa)/step,step,K.wxTrendTau)
 end
 local was=w.pw
 w.pw=wet; w.pr=rain; w.pa=water
 local up,down=max(w.sw,w.sr,w.sa),min(w.sw,w.sr,w.sa)
 local trend=up>=K.wxSlopeMin and up>=-down and 'wetting' or down<=-K.wxSlopeMin and 'drying' or 'steady'
 local before=w.trend
 w.trend=trend
 w.eta=M.eta(w,wetNow)
 -- Première pluie : la piste était encore sèche quand la tendance a tourné à l'humide.
 if trend=='wetting' and before~='wetting' and was<K.wxDryLine then w.onsetAt=now end
 -- Eau projetée : choix entre intermédiaires et pneus pluie.
 local most=max(wet,rain,water)
 w.proj=U.clamp(most+U.clamp((trend=='wetting' and up or trend=='drying' and down or 0)*K.wxProjectTime,-K.wxProjectMax,K.wxProjectMax),0,1)
 w.heavy=w.proj>=K.weatherHeavy
 -- Prévision de CSP, si le contrôleur météo la renseigne ; sinon la tendance seule.
 local forecast,forecastIn='unknown',-1
 local cur,upc,tr=frame.wxCurrent,frame.wxUpcoming,frame.wxTransition
 if frame.wxKnown~=true or type(upc)~='number' or type(tr)~='number' or tr<0 then
  -- Beta 1.62 (préréglages) : ligne reportée après le lancement, pour ne pas prendre la place des lignes du lancement.
  if not w.noForecast and now>=K.wxPeriod*10 then w.noForecast=true; U.log(e.log,now,'INFO','meteo: prevision indisponible (CSP ou controleur meteo)',-1) end
 else
  if w.pt>=0 and step>0 then w.st=U.ema(w.st,(tr-w.pt)/step,step,K.wxPeriod*10) end
  w.pt=tr
  local q=floor(tr*4)
  if cur~=w.fcur or upc~=w.fup or q~=w.fq then
   w.fcur=cur; w.fup=upc; w.fq=q
   U.log(e.log,now,'DEBUG',string.format('meteo: champs de prevision de CSP: type %d, a venir %d, transition %.2f',cur or -1,upc,tr),-1)
  end
  if upc~=cur and w.st>0.00001 and tr<1 then forecast=M.rainClass(upc); forecastIn=min((1-tr)/w.st,K.wxEtaMax) end
 end
 w.forecast=forecast; w.forecastIn=forecastIn
 if forecast~='unknown' and forecast~=w.forecastLogged then
  w.forecastLogged=forecast
  U.log(e.log,now,'INFO',string.format('meteo: prevision %s dans %.0f s',LABEL[forecast] or forecast,forecastIn),-1)
 elseif forecast=='unknown' then w.forecastLogged='' end
 if trend~=before and now-w.trendAt>=K.wxLogGap then
  w.trendAt=now
  U.log(e.log,now,'INFO',string.format('meteo: tendance %s (pluie %.0f %%, piste %.0f %%, eau %.0f %%), bascule estimee dans %.0f s',TREND[trend],rain*100,wet*100,water*100,w.eta),-1)
 end
 local shower=showerEnd(w)
 local onset=now-w.onsetAt<K.wxOnsetTime
 local coming=nil
 if trend=='wetting' then coming=true elseif trend=='drying' then coming=false end
 local seed=e.runtimeG and e.runtimeG.seed or 0
 local n=w.stats
 n.count=0; n.grip=0; n.wrong=0
 local aiDry,aiRain=0,0
 for i=1,frame.count do
  local a,s=frame.cars[i],e.states[i]
  if not (s and a.valid and a.control and not a.player and not a.safetyCar and not a.finished) then
   if s then s.wxWet=nil end
   w.carWet[i]=nil; w.cls[i]=nil; w.urgency[i]=0; w.critical[i]=false
  else
   local known=a.tyresKnown and a.compoundIndex~=nil
   local onDry=known and a.currentTyreIsDry==true
   local onRain=known and not onDry
   local onInter=onRain and a.compoundIndex==a.interCompound
   if onDry then aiDry=aiDry+1 elseif onRain then aiRain=aiRain+1 end
   -- Rythme : humidité effective suivie progressivement.
   local value=wet
   if p.weatherAdaptation then
    local target=M.carWet(wet,most>=K.weatherHeavy,onDry,onInter,onRain,M.skill(seed,a.index),onset)
    local prev=s.wxWet or wet
    value=step>0 and U.ema(prev,target,step,K.wxPaceTau) or prev
    if target==0 and value<0.001 then value=0 end
    s.wxWet=value
   else s.wxWet=nil end
   n.count=n.count+1; n.grip=n.grip+(1-min(1,value))
   -- Pneus : état sec/pluie propre au pilote.
   if p.weatherTyresEnabled then
    local risk=s.persona and s.persona.strategyRisk or 0.5
    local shift=(risk-0.5)*2*K.wxRiskSpan
    local cw=w.carWet[i]
    if cw==nil then cw=wetNow; w.pend[i]=cw; w.pendAt[i]=now; w.early[i]=false; w.hold[i]=false end
    if w.cls[i]~=nil and known and w.cls[i]~=onDry then w.stopAt[i]=now; w.early[i]=false; w.hold[i]=false end
    if known then w.cls[i]=onDry end
    local wetOn,rainOn,waterOn=threshold(K.weatherWetOn,shift),threshold(K.weatherRainOn,shift),threshold(K.weatherWaterOn,shift)
    local desired=cw
    if wet>=wetOn or rain>=rainOn or water>=waterOn then desired=true
    elseif wet<=min(threshold(K.weatherWetOff,shift),wetOn*0.8) and rain<=min(threshold(K.weatherRainOff,shift),rainOn*0.8)
     and water<=min(threshold(K.weatherWaterOff,shift),waterOn*0.8) then desired=false end
    if desired~=w.pend[i] then w.pend[i]=desired; w.pendAt[i]=now end
    local critical=onDry and most>=K.weatherHeavy
    local locked=now-(w.stopAt[i] or -math.huge)<K.wxMinStint and not critical
    if not locked then
     -- Averse courte : un audacieux en pneus secs reste en piste.
     local short=shower>=0 and shower<=K.wxShowerTime and most<K.weatherHeavy
     local holding=not cw and onDry and short and risk>=K.wxGambleRisk and (desired or w.hold[i])
     if holding then
      if not w.hold[i] then
       w.hold[i]=true; n.gamble=n.gamble+1
       U.log(e.log,now,'INFO',string.format('meteo: %s reste en pneus secs (averse courte, %.0f s)',a.name or '',shower),i)
      end
     else
      w.hold[i]=false
      -- Un arrêt anticipé tient tant que la tendance l'annonce encore.
      if desired~=cw and now-(w.pendAt[i] or now)>=K.weatherConfirm and not (w.early[i] and coming==cw) then cw=desired; w.early[i]=false
      elseif coming~=nil and coming~=cw and not w.early[i] and not short and not a.pit and (a.spline or 0)>=K.wxPitEntryFrom then
       -- Arrêt anticipé : bascule attendue (tendance) ou annoncée (prévision, un tour et le temps perdu aux stands).
       local lapTime=Pitloss.lapTimeOf(e,i)
       local horizon=lapTime>0 and lapTime+max(0,Pitloss.loss(e.pitloss,lapTime)) or K.wxAnticipate
       local expected=w.eta>=0 and w.eta<=K.wxAnticipate
        or forecastIn>=0 and forecastIn<=horizon and (coming and forecast~='none' or not coming and forecast=='none')
       if expected and (risk>=K.wxGambleRisk or Strategy.dueWithin(e.strategy,i,a.lap,K.wxComboLaps)) then
        cw=coming; w.early[i]=true; n.early=n.early+1
        U.log(e.log,now,'INFO',string.format('meteo: %s anticipe les pneus %s (bascule dans %.0f s, audace %.0f %%)',a.name or '',coming and 'pluie' or 'secs',
         w.eta>=0 and w.eta or forecastIn,risk*100),i)
       end
      end
     end
    end
    if cw~=wetNow and not w.early[i] and not w.hold[i] then
     if not w.waitLogged[i] then
      w.waitLogged[i]=true
      U.log(e.log,now,'DEBUG',string.format('meteo: %s attend sa bascule (seuil %.0f %%)',a.name or '',wetOn*100),i)
     end
    else w.waitLogged[i]=false end
    w.carWet[i]=cw
    w.critical[i]=critical
    w.urgency[i]=cw and (onDry and 1+most or 0) or (onRain and (onInter and 0.5 or 0.8) or 0)
    if cw and onDry or not cw and onRain and wet<K.wxDryLine then n.wrong=n.wrong+1 end
   else
    w.carWet[i]=nil; w.urgency[i]=0; w.critical[i]=false
   end
  end
 end
 w.aiDry=aiDry; w.aiRain=aiRain
 if e.sideText then e.sideText[SIDE_KEY]=M.side(w,wet,rain,water,now) end
end
return M
