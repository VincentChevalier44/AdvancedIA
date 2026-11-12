-- Beta 1.60 (tranche C, réglages dynamicPersona et fineInputs, section Facteur humain). Décisions pures, aucune
-- fonction de CSP : tout passe par les leviers existants (agressivité, prudence, niveau, plafond d'accélérateur).
-- M.update (avant le pilotage, humeur recalculée toutes les K.moodPeriod s) : stress et fatigue par IA, agressivité selon
-- la phase de la course ; écrit s.moodAggr, s.moodCaution, s.moodFatigue, s.moodRisk dans e.states[i] (champ absent :
-- neutre, lus par src/director.lua et src/mistakes.lua) et multiplie cmd.levelScale à chaque image.
-- M.exit (après le pilotage) : remise des gaz progressive en sortie de virage et courte roue libre après un gros
-- freinage, par le minimum de cmd.throttleLimit (remis au neutre à chaque image par src/engine.lua).
-- Réglage coupé (ou section décochée : C.effective le coupe) : rien n'est lu ni écrit (les champs posés sont retirés une fois). Tableaux créés une fois par voiture ;
-- une ligne de journal seulement à un changement d'état, au plus une par IA toutes les K.moodLogGap s.
local C=require('src/config')
local K=C.K
local U=require('src/util')
local min,max,floor,exp=math.min,math.max,math.floor,math.exp
local M={}
local function fresh(c)
 c.id=nil; c.stress=0; c.fatigue=0; c.press=0; c.contactAt=nil; c.mistakeId=nil; c.position=0; c.stint=nil; c.carry=0; c.progressAt=0
 c.level=1; c.stressed=false; c.tired=false; c.stressLogAt=-math.huge; c.tiredLogAt=-math.huge
 c.low=0; c.wasLow=false; c.rampAt=nil; c.rampFrom=1; c.rampTime=0; c.braked=false; c.coastUntil=-math.huge
end
function M.new()
 local t={session=-1,gen=-1,cars={},nextAt=0,lastAt=nil,moodOn=false}
 for i=1,K.maxCars do t.cars[i]={}; fresh(t.cars[i]) end
 return t
end
function M.reset(t)
 t.session=-1; t.gen=-1; t.nextAt=0; t.lastAt=nil
 for i=1,K.maxCars do fresh(t.cars[i]) end
end
function M.rebase(t,amount)
 t.nextAt=t.nextAt-amount; if t.lastAt then t.lastAt=t.lastAt-amount end
 for i=1,K.maxCars do
  local c=t.cars[i]
  if U.finite(c.stressLogAt) then c.stressLogAt=c.stressLogAt-amount end
  if U.finite(c.tiredLogAt) then c.tiredLogAt=c.tiredLogAt-amount end
  if c.rampAt then c.rampAt=c.rampAt-amount end
  if U.finite(c.coastUntil) then c.coastUntil=c.coastUntil-amount end
  if c.contactAt then c.contactAt=c.contactAt-amount end
 end
end
local function clear(s) s.moodAggr=nil; s.moodCaution=nil; s.moodFatigue=nil; s.moodRisk=nil end
-- Agressivité selon l'avancement de la course (0 à 1) : un peu plus bas au début, plus haut à la fin (sauf quand
-- l'urgence des derniers tours s'en charge déjà).
function M.phase(progress,finalLaps)
 if not progress or progress<0 then return 1 end
 if progress<K.phaseEarlyEnd then return K.phaseEarly end
 local from=1-K.phaseLateShare
 if progress>from and not finalLaps then return U.lerp(1,K.phaseLate,U.clamp((progress-from)/K.phaseLateShare,0,1)) end
 return 1
end
-- Effets de l'humeur (bornés) : agressivité, prudence, niveau, risque d'erreur, fréquence des pertes de concentration.
function M.outputs(stress,fatigue,assertiveness,phase)
 local aggr=U.clamp(phase*(1+K.moodAggrGain*stress*(2*assertiveness-1)),K.moodAggrMin,K.moodAggrMax)
 local caution=1+K.moodCautionStress*stress*max(0,1-2*assertiveness)+K.moodCautionFatigue*fatigue
 return aggr,caution,1-K.moodLevelFatigue*fatigue,1+K.moodRiskStress*stress,1+K.moodLapseFatigue*fatigue
end
local function frozen(e,frame,s,p,now,i)
 local inc=e.incidents
 local q=e.quali
 -- Beta 1.62 (préréglages hors course) : humeur figée pendant un tour lancé de qualifications.
 return s.yellow or inc.neutral or inc.red or not frame.started or e.fl.on or e.profile=='Q' and q and q.active and q.push[i]==true
  or e.profile=='C' and now-math.max(e.startedAt,e.launchAt or -math.huge)<p.startDelay+p.startRelax
end
function M.update(t,e,frame,now)
 local p=e.run
 if not p.dynamicPersona then
  if t.moodOn then t.moodOn=false; for i=1,K.maxCars do clear(e.states[i]); t.cars[i].level=1 end end
  return
 end
 t.moodOn=true
 local gen=e.raceGen or 0
 if t.session~=frame.session or t.gen~=gen then
  t.session=frame.session; t.gen=gen; t.nextAt=now; t.lastAt=nil
  for i=1,K.maxCars do fresh(t.cars[i]); clear(e.states[i]) end
 end
 if now>=t.nextAt then
  local step=min(K.moodStepMax,t.lastAt and now-t.lastAt or K.moodPeriod)
  t.lastAt=now; t.nextAt=now+K.moodPeriod
  local race=e.profile=='C'
  local progress=race and frame.started and e.race.progress>=0 and min(1,e.race.progress) or -1
  local phase=M.phase(progress,p.finalLapsEnabled)
  for i=1,frame.count do
   local a=frame.cars[i]; local s=e.states[i]; local c=t.cars[i]; local cmd=e.commands[i]
   local id=a.identity or a.id
   if not (a.valid and a.control and not a.player and not a.safetyCar and not a.finished) then clear(s); c.level=1; c.press=0
   else
    if c.id~=id then fresh(c); c.id=id end
    local style=s.persona.style or 0.5
    local gain=U.lerp(K.moodGainPro,K.moodGainAm,style)
    -- Stress : retombée, puis suiveur collé, contact, erreur, place perdue.
    c.stress=c.stress*exp(-step/(K.moodStressDecay*U.lerp(K.moodDecayPro,K.moodDecayAm,style)))
    local row=e.perception.rows[i]
    local back=row and row.back>0 and row.neighbors[row.back] or nil
    if back and not a.pit and back.gap>=0 and back.gap<=K.moodPressTime*max(a.speed or 0,1) then c.press=c.press+step else c.press=0 end
    if c.press>K.moodPressHold then c.stress=c.stress+K.moodStressRise*step*gain end
    local contact=e.lastContactAt and e.lastContactAt[i] or nil
    if contact and c.contactAt~=contact then if c.contactAt or now-contact<=step then c.stress=c.stress+K.moodStressContact*gain end; c.contactAt=contact end
    if c.mistakeId and cmd.mistakeId~=c.mistakeId then c.stress=c.stress+K.moodStressMistake*gain end
    c.mistakeId=cmd.mistakeId
    local position=race and frame.started and not a.pit and a.position or 0
    if position>0 and c.position>0 and position>c.position then c.stress=c.stress+K.moodStressPlace*gain end
    c.position=position
    c.stress=U.clamp(c.stress,0,1)
    -- Fatigue : relais en cours, plus la course ; un arrêt la rend (en entier avec un changement de pilote).
    local raceShare=progress>=0 and progress or 0
    if c.stint==nil then c.stint=s.stint; c.progressAt=0
    elseif c.stint~=s.stint then
     c.stint=s.stint; c.carry=p.enduranceOverlay and 0 or c.fatigue*(1-K.moodFatigueRest); c.progressAt=raceShare
    end
    c.fatigue=U.clamp(c.carry+max(0,now-s.stintStart)/K.moodFatigueStint+K.moodFatigueRace*max(0,raceShare-c.progressAt),0,1)
    if frozen(e,frame,s,p,now,i) then clear(s); c.level=1
    else
     local aggr,caution,level,risk,lapse=M.outputs(c.stress,c.fatigue,s.persona.assertiveness or 0.5,phase)
     s.moodAggr=aggr; s.moodCaution=caution; s.moodRisk=risk; s.moodFatigue=lapse; c.level=level
     -- Journal : seuil franchi, au plus une ligne par IA toutes les K.moodLogGap s.
     local stressed=c.stress>=K.moodLogStress
     if stressed and not c.stressed and now-c.stressLogAt>=K.moodLogGap then
      c.stressLogAt=now; e.stats.moodStress=(e.stats.moodStress or 0)+1
      U.log(e.log,now,'INFO',string.format('humeur: %s sous pression (stress %d %%), agressivite %d %%',a.name or '',floor(c.stress*100+0.5),floor(aggr*100+0.5)),i)
     end
     c.stressed=stressed
     local tired=c.fatigue>=K.moodLogFatigue
     if tired and not c.tired and now-c.tiredLogAt>=K.moodLogGap then
      c.tiredLogAt=now; e.stats.moodTired=(e.stats.moodTired or 0)+1
      U.log(e.log,now,'INFO',string.format('humeur: %s fatigue (relais %d min), niveau %.1f %%',a.name or '',floor(max(0,now-s.stintStart)/60+0.5),level*100),i)
     end
     c.tired=tired
    end
   end
  end
 end
 -- Niveau : facteur de fatigue appliqué à chaque image (cmd.levelScale vient d'être remis à 1).
 for i=1,frame.count do
  local level=t.cars[i].level
  if level<1 then local cmd=e.commands[i]; cmd.levelScale=cmd.levelScale*level end
 end
end
-- Plafond d'accélérateur de la remise des gaz, de from à 1 en time s, par pas de K.exitStep (peu d'écritures).
function M.ceiling(from,time,elapsed)
 if time<=0 or elapsed>=time then return 1 end
 local value=from+(1-from)*max(0,elapsed)/time
 return min(1,floor(value/K.exitStep+1e-6)*K.exitStep)
end
function M.exit(t,e,frame,now,dt)
 local p=e.run
 if not p.fineInputs then return end
 local inc=e.incidents
 local flag=inc.neutral or inc.red
 local start=not frame.started or e.fl.on or e.profile=='C' and now-math.max(e.startedAt,e.launchAt or -math.huge)<p.startDelay+p.startRelax
 local wet=U.clamp(max(frame.wet or 0,frame.rain or 0),0,1)
 for i=1,frame.count do
  local a=frame.cars[i]; local s=e.states[i]; local c=t.cars[i]; local cmd=e.commands[i]
  local ok=a.valid and a.control and not a.player and not a.safetyCar and not a.finished and not a.pit and not a.offtrack and cmd.active
   and not flag and not start and not s.yellow and s.state~='AVOID' and s.state~='CALM' and s.state~='IDLE'
   and now>=(e.penalties.ai.slowUntil[i] or 0)
  if not ok then c.low=0; c.wasLow=false; c.rampAt=nil; c.braked=false; c.coastUntil=-math.huge
  else
   local style=s.persona.style or 0.5
   local corner=a.corner or 1
   -- Roue libre après un gros freinage (amateur seulement : durée nulle pour un professionnel).
   if a.brake>=K.mistakeBrakePedal then c.braked=true
   elseif c.braked and a.brake<K.coastBrake then
    c.braked=false
    local time=U.lerp(0,K.coastTimeAm,style)
    if time>0 then c.coastUntil=now+time end
   end
   -- Sortie de virage : la rectitude repasse K.exitCornerFrom après assez de temps en virage, pied sur l'accélérateur.
   if corner<p.cornerMin then c.low=c.low+dt; if c.low>=K.exitMinCorner then c.wasLow=true end
   elseif corner>=K.exitCornerFrom then
    if c.wasLow and a.gas>=K.exitGas then
     local from=U.lerp(K.exitFromPro,K.exitFromAm,style)
     local time=U.lerp(K.exitTimePro,K.exitTimeAm,style)*(1+K.exitWetGain*wet)*(s.wearExit or 1)
     if s.state=='OVT_IN' or s.state=='OVT_HOLD' then time=time*K.exitPassFactor end
     c.rampAt=now; c.rampFrom=from; c.rampTime=time
     e.stats.exitRamp=(e.stats.exitRamp or 0)+1
    end
    c.low=0; c.wasLow=false
   end
   local limit=1
   if now<c.coastUntil then limit=K.coastThrottle end
   if c.rampAt then
    local value=M.ceiling(c.rampFrom,c.rampTime,now-c.rampAt)
    if value>=1 then c.rampAt=nil else limit=min(limit,value) end
   end
   if limit<1 then
    if s.rearClose and limit<K.exitFromRear then limit=K.exitFromRear end
    cmd.throttleLimit=min(cmd.throttleLimit or 1,limit)
   end
  end
 end
end
return M
