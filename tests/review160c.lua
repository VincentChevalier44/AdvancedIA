-- Beta 1.60, tranche C : tests de la tranche (noms terminés par _160C). Chargé par tests/extended.lua.
-- Réglages fineInputs (remise des gaz progressive, erreur à la limite) et dynamicPersona (humeur : stress, fatigue,
-- phase de la course), src/mood.lua, src/mistakes.lua, src/persona.lua ; sonde en lecture seule de ai.ini (applier).
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Mood=require('src/mood')
local Persona=require('src/persona')
local Applier=require('src/applier')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function scene(profile,key,on,cars)
 local e,f=F.scene(profile or 'C',cars or 3)
 if key then e.profiles[profile or 'C'][key]=on; E.changed(e) end
 for i=1,f.count do local a=f.cars[i]; a.gas=1; a.brake=0; a.position=i end
 F.tick(e,f,0.1)
 return e,f
end
-- Virage tenu (rotation forte) puis sortie pied au plancher ; renvoie le plafond à la première image de la sortie et
-- le nombre d'images avant le retour à 1.
local function exit(e,f,i)
 local a=f.cars[i]; a.gas=1; a.brake=0
 a.yawRate=1; F.tick(e,f,1); a.yawRate=0
 F.tick(e,f,1/60)
 local first=e.commands[i].throttleLimit; local frames=0; local last=first
 while e.commands[i].throttleLimit<1 and frames<600 do
  F.tick(e,f,1/60); frames=frames+1
  assert(e.commands[i].throttleLimit>=last-1e-9,'ceiling never goes down'); last=e.commands[i].throttleLimit
 end
 return first,frames
end
tests.PERSONA_STYLE_160C=function()
 local p=C.defaults('C'); for _,g in ipairs(C.sections) do p['section_'..g]=true end
 local seen={}
 for i=1,40 do
  local out=Persona.fill({},19731019,i,'C',p,0)
  assert(out.style>=0 and out.style<=1,'style in 0..1')
  local expected=K.styleGradeShare*(out.grade-1)/3+(1-K.styleGradeShare)*(1-out.assertiveness)
  assert(math.abs(out.style-expected)<1e-12,'style from grade and assertiveness'); seen[out.grade]=out.style
 end
 assert(seen[1] and seen[4] and seen[1]<seen[4],'a Platinum is more of a professional than a Bronze')
end
tests.EXIT_RAMP_STYLE_160C=function()
 -- fineInputs : professionnel, plafond plus haut et rendu plus vite que l'amateur ; jamais en baisse ; une sortie comptée.
 local e,f=scene('C','fineInputs',true)
 e.states[2].persona.style=0
 local proFrom,proFrames=exit(e,f,2)
 assert(math.abs(proFrom-K.exitFromPro)<K.exitStep+1e-9 and proFrom<1,'professional starts near exitFromPro: '..proFrom)
 assert(e.stats.exitRamp==1,'one exit counted: '..tostring(e.stats.exitRamp))
 e.states[2].persona.style=1
 local amFrom,amFrames=exit(e,f,2)
 assert(amFrom<proFrom and math.abs(amFrom-K.exitFromAm)<K.exitStep+1e-9,'amateur starts lower: '..amFrom)
 assert(amFrames>proFrames*2,'amateur ramp is longer: '..amFrames..' vs '..proFrames)
 assert(math.abs(proFrames/60-K.exitTimePro)<0.1 and math.abs(amFrames/60-K.exitTimeAm)<0.1,'durations follow the constants')
 -- Plafond : monotone, borné, 1 à la fin.
 local last=0
 for k=0,20 do local v=Mood.ceiling(0.7,1,k/20); assert(v>=last and v<=1 and v>=0.7-1e-9,'monotonic'); last=v end
 assert(Mood.ceiling(0.7,1,0.5)>0.8 and Mood.ceiling(0.7,1,0.5)<0.9,'half way up at half time')
 assert(Mood.ceiling(0.7,1,1)==1 and Mood.ceiling(0.7,0,0)==1 and Mood.ceiling(0.7,1,0.999)<1,'ends at exactly the ramp time')
end
tests.EXIT_RAMP_PASSING_160C=function()
 -- En dépassement (OVT_IN, OVT_HOLD) : rampe raccourcie de K.exitPassFactor.
 for _,state in ipairs({'DRIVE','OVT_IN','OVT_HOLD'}) do
  local e,f=scene('C','fineInputs',true)
  local s=e.states[2]; s.persona.style=1
  local a=f.cars[2]; local c=e.mood.cars[2]
  c.low=K.exitMinCorner; c.wasLow=true; a.corner=1; a.gas=1; s.state=state
  Mood.exit(e.mood,e,f,e.time,1/60)
  local expected=K.exitTimeAm*(state=='DRIVE' and 1 or K.exitPassFactor)
  assert(c.rampAt==e.time and math.abs(c.rampTime-expected)<1e-9,state..': ramp time '..tostring(c.rampTime))
 end
 -- Piste mouillée et pneus arrière usés (s.wearExit, tranche D) : rampe allongée.
 local e,f=scene('C','fineInputs',true)
 local s=e.states[2]; s.persona.style=1; s.wearExit=1.5; f.wet=1
 local c=e.mood.cars[2]; c.low=K.exitMinCorner; c.wasLow=true; f.cars[2].corner=1
 Mood.exit(e.mood,e,f,e.time,1/60)
 assert(math.abs(c.rampTime-K.exitTimeAm*(1+K.exitWetGain)*1.5)<1e-9,'longer in the wet and on worn tyres')
end
tests.EXIT_RAMP_OFF_160C=function()
 local e,f=scene('C')
 local first=exit(e,f,2)
 assert(first==1 and e.stats.exitRamp==nil,'fineInputs off: no ceiling, nothing counted')
 -- Section Facteur humain décochée : coupé aussi.
 e,f=scene('C','fineInputs',true); e.profiles.C.section_human=false; E.changed(e)
 first=exit(e,f,2)
 assert(first==1 and e.stats.exitRamp==nil,'section off: no ceiling')
end
tests.EXIT_RAMP_SKIPPED_160C=function()
 -- Départ, neutralisation, évitement : pas de rampe.
 local e,f=scene('C','fineInputs',true)
 e.startedAt=e.time
 local first=exit(e,f,2)
 assert(first==1,'no ramp in the start phase: '..first)
 for _,case in ipairs({'start','neutral','red','avoid','calm','yellow','firstlap','sanction'}) do
  e,f=scene('C','fineInputs',true)
  local c=e.mood.cars[2]; local s=e.states[2]
  c.low=K.exitMinCorner; c.wasLow=true; f.cars[2].corner=1
  if case=='start' then e.startedAt=e.time elseif case=='neutral' then e.incidents.neutral=true elseif case=='red' then e.incidents.red=true
  elseif case=='avoid' then s.state='AVOID' elseif case=='calm' then s.state='CALM' elseif case=='yellow' then s.yellow=true
  elseif case=='firstlap' then e.fl.on=true else e.penalties.ai.slowUntil[2]=e.time+5 end
  Mood.exit(e.mood,e,f,e.time,1/60)
  assert(c.rampAt==nil and not c.wasLow and e.stats.exitRamp==nil,'no ramp: '..case)
  e.incidents.neutral=false; e.incidents.red=false
 end
 -- Pied levé à la sortie : pas de rampe.
 e,f=scene('C','fineInputs',true)
 local a=f.cars[2]; a.yawRate=1; a.gas=0.2; F.tick(e,f,1); a.yawRate=0
 F.tick(e,f,1/60)
 assert(e.commands[2].throttleLimit==1 and e.stats.exitRamp==nil,'only a car on the throttle is ramped')
 -- Virage trop court : pas de rampe.
 e,f=scene('C','fineInputs',true)
 a=f.cars[2]; a.yawRate=1; F.tick(e,f,K.exitMinCorner-0.2); a.yawRate=0; F.tick(e,f,1/60)
 assert(e.commands[2].throttleLimit==1 and e.stats.exitRamp==nil,'corner too short')
end
tests.EXIT_RAMP_REAR_160C=function()
 local e,f=scene('C','fineInputs',true)
 -- Voiture réellement collée derrière (4 m, même vitesse) : s.rearClose vient de la perception (src/rear.lua).
 e.states[2].persona.style=1; F.place(f,3,f.cars[2].z-4.4-4,f.cars[2].kmh); e.states[2].nextPerception=0
 -- Le régulateur sans coup de frein (src/rear.lua, pour tous) étale en plus la baisse du plafond : il descend en
 -- douceur, jamais sous K.exitFromRear, puis revient à 1.
 local a=f.cars[2]; a.gas=1; a.brake=0; a.yawRate=1; F.tick(e,f,1); a.yawRate=0
 assert(e.states[2].rearClose==true,'car close behind seen by the perception')
 local low,frames=1,0
 repeat F.tick(e,f,1/60); frames=frames+1; low=math.min(low,e.commands[2].throttleLimit) until frames>=60 and e.commands[2].throttleLimit>=1 or frames>900
 assert(low>=K.exitFromRear-1e-9 and low<1 and frames<900,'never below exitFromRear with a car close behind: '..low..' after '..frames)
end
tests.COAST_AFTER_BRAKING_160C=function()
 local e,f=scene('C','fineInputs',true)
 local a=f.cars[2]
 for _,style in ipairs({1,0}) do
  e.states[2].persona.style=style
  a.brake=1; a.gas=0; F.tick(e,f,0.2); a.brake=0; a.gas=1; F.tick(e,f,1/60)
  if style==1 then
   assert(e.commands[2].throttleLimit==K.coastThrottle,'amateur coasts after a heavy braking: '..e.commands[2].throttleLimit)
   F.tick(e,f,K.coastTimeAm+0.05); assert(e.commands[2].throttleLimit==1,'coast over')
  else assert(e.commands[2].throttleLimit==1,'a professional does not coast') end
 end
end
local function slide(e,f,i,seconds)
 local a=f.cars[i]; a.gas=1; a.brake=0; a.yawRate=1; a.kmh=80; a.speed=80/3.6; a.slip=K.limitSlipDeg+2
 F.tick(e,f,seconds)
end
local function grip(e,f,i) local a=f.cars[i]; a.slip=0; a.yawRate=0; F.tick(e,f,0.1) end
tests.LIMIT_MISTAKE_160C=function()
 local chance=K.limitChance; K.limitChance=100
 local ok,err=pcall(function()
  local e,f=scene('C','fineInputs',true)
  e.profiles.C.mistakesEnabled=true; E.changed(e)
  local cmd=e.commands[2]; local before=cmd.mistakeId
  slide(e,f,2,K.limitSlipTime-0.1); assert(cmd.mistakeId==before,'slip not held long enough')
  slide(e,f,2,0.3)
  assert(cmd.mistakeId==before+1 and cmd.mistakeKind=='traction' and cmd.mistakeCause=='a la limite','traction mistake at the limit')
  assert(cmd.mistakeSeverity==K.limitSeverity and cmd.mistakeTime>=K.limitTimeMin and cmd.mistakeTime<=K.limitTimeMax,'low severity, short time')
  assert(e.stats.limitMistake==1 and count(e,'a la limite')==1,'counted and logged once')
  slide(e,f,2,2); assert(cmd.mistakeId==before+1,'one draw per episode')
  -- Délai par IA.
  grip(e,f,2); e.mistakes.lastAt=-math.huge; slide(e,f,2,1); assert(cmd.mistakeId==before+1,'per-car cooldown')
  grip(e,f,2); e.mistakes.lastAt=-math.huge; e.mistakes.cars[2].limitAt=e.time-K.limitCooldown-1; slide(e,f,2,1)
  assert(cmd.mistakeId==before+2,'again after the cooldown')
  -- Écart dans le peloton : une autre IA juste après, rien.
  local other=e.commands[3].mistakeId
  slide(e,f,3,1); assert(e.commands[3].mistakeId==other,'field gap K.mistakeGap respected')
  -- Dérive sous le seuil : rien.
  grip(e,f,3); e.mistakes.lastAt=-math.huge
  local a=f.cars[3]; a.gas=1; a.yawRate=1; a.kmh=80; a.speed=80/3.6; a.slip=K.limitSlipDeg-1; F.tick(e,f,1)
  assert(e.commands[3].mistakeId==other,'below the slip threshold: nothing')
 end)
 K.limitChance=chance; assert(ok,err)
end
tests.LIMIT_MISTAKE_CHANCE_160C=function()
 -- Tirage : chance K.limitChance × risque ; à chance nulle, jamais.
 local chance=K.limitChance; K.limitChance=0
 local ok,err=pcall(function()
  local e,f=scene('C','fineInputs',true); e.profiles.C.mistakesEnabled=true; E.changed(e)
  local before=e.commands[2].mistakeId
  slide(e,f,2,2); assert(e.commands[2].mistakeId==before and e.stats.limitMistake==nil,'no chance: nothing')
  -- Tirage perdu : pas d'autre tirage tant que la même dérive dure.
  K.limitChance=100; slide(e,f,2,2); assert(e.commands[2].mistakeId==before,'one draw per episode, won or lost')
  grip(e,f,2); slide(e,f,2,1); assert(e.commands[2].mistakeId==before+1,'a new slide draws again')
 end)
 K.limitChance=chance; assert(ok,err)
end
tests.LIMIT_MISTAKE_OFF_160C=function()
 local chance=K.limitChance; K.limitChance=100
 local ok,err=pcall(function()
  local e,f=scene('C'); e.profiles.C.mistakesEnabled=true; e.profiles.C.mistakeRate=0.01; E.changed(e)
  local before=e.commands[2].mistakeId
  slide(e,f,2,2); assert(e.commands[2].mistakeId==before and e.stats.limitMistake==nil,'fineInputs off: nothing')
  e,f=scene('C','fineInputs',true); e.profiles.C.mistakesEnabled=false; E.changed(e)
  before=e.commands[2].mistakeId
  slide(e,f,2,2); assert(e.commands[2].mistakeId==before,'mistakes off: nothing')
 end)
 K.limitChance=chance; assert(ok,err)
end
tests.NO_BRAKE_MISTAKE_REAR_160C=function()
 -- Erreur armée, gros freinage : blocage des roues, sauf avec une voiture collée derrière (s.rearClose).
 for _,close in ipairs({false,true}) do
  local e,f=scene('C'); e.profiles.C.mistakesEnabled=true; E.changed(e)
  local a=f.cars[2]; a.kmh=200; a.speed=200/3.6; a.brake=1; a.gas=0
  -- Voiture réellement collée derrière (4 m, même vitesse), vue par la perception avant que l'erreur ne soit armée.
  if close then F.place(f,3,a.z-4.4-4,200); f.cars[3].gas=1; f.cars[3].brake=0 end; e.states[2].nextPerception=0
  a.brake=0; a.gas=1; F.tick(e,f,0.2); a.brake=1; a.gas=0
  assert(e.states[2].rearClose==close,'rearClose from the perception')
  e.mistakes.cars[2].armedUntil=e.time+60; e.mistakes.cars[2].nextCheck=e.time+60
  local before=e.commands[2].mistakeId
  F.tick(e,f,0.1)
  if close then assert(e.commands[2].mistakeId==before,'no lock-up with a car close behind')
  else assert(e.commands[2].mistakeId==before+1 and e.commands[2].mistakeKind=='brake','lock-up without a follower') end
 end
end
tests.MOOD_PHASE_CURVE_160C=function()
 assert(Mood.phase(-1,false)==1 and Mood.phase(nil,false)==1,'unknown progress: neutral')
 assert(Mood.phase(0.05,false)==K.phaseEarly and Mood.phase(K.phaseEarlyEnd,false)==1 and Mood.phase(0.5,false)==1,'early, then middle')
 local half=Mood.phase(1-K.phaseLateShare/2,false)
 assert(half>1 and half<K.phaseLate and math.abs(Mood.phase(1,false)-K.phaseLate)<1e-12,'late rise')
 assert(Mood.phase(1,true)==1 and Mood.phase(0.95,true)==1,'no double with the last-laps urgency')
 assert(Mood.phase(0.05,true)==K.phaseEarly,'early phase kept with the urgency on')
end
tests.MOOD_ASSERTIVE_VS_TIMID_160C=function()
 local aggrA,cautA,_,riskA=Mood.outputs(1,0,1,1)
 local aggrT,cautT,_,riskT=Mood.outputs(1,0,0,1)
 assert(math.abs(aggrA-(1+K.moodAggrGain))<1e-12 and math.abs(aggrT-(1-K.moodAggrGain))<1e-12,'assertive attacks more, timid less')
 assert(cautA==1 and math.abs(cautT-(1+K.moodCautionStress))<1e-12,'only the timid driver gets more careful')
 assert(riskA==1+K.moodRiskStress and riskT==riskA,'stress raises the mistake risk')
 local aggr,caut,level,risk,lapse=Mood.outputs(0,0,0.5,1)
 assert(aggr==1 and caut==1 and level==1 and risk==1 and lapse==1,'calm and fresh: neutral')
 aggr,caut,level,risk,lapse=Mood.outputs(0,1,0.5,1)
 assert(aggr==1 and math.abs(caut-(1+K.moodCautionFatigue))<1e-12 and math.abs(level-(1-K.moodLevelFatigue))<1e-12 and lapse==1+K.moodLapseFatigue and risk==1,'fatigue: slower, more careful, less focused')
 assert((Mood.outputs(1,0,1,2))==K.moodAggrMax and (Mood.outputs(1,0,0,0.1))==K.moodAggrMin,'aggression clamped')
end
tests.MOOD_STRESS_RISE_DECAY_160C=function()
 local e,f=scene('C','dynamicPersona',true)
 local c=e.mood.cars[2]
 assert(c.stress==0,'calm')
 F.rear(e,f,5,0); F.tick(e,f,K.moodPressHold-0.5)
 assert(c.stress==0,'follower not there long enough')
 F.tick(e,f,8)
 local pressed=c.stress
 assert(pressed>0.1 and pressed<=1,'stress rises with a car close behind: '..pressed)
 assert(e.mood.cars[3].stress==0,'the follower itself is not under pressure')
 -- Suiveur parti : retombée.
 F.place(f,3,-2000,100); e.states[2].nextPerception=0; F.tick(e,f,30)
 assert(c.stress<pressed*0.7 and c.stress>0,'decay: '..c.stress)
 -- Contact, erreur, place perdue.
 local before=c.stress; e.lastContactAt[2]=e.time; F.tick(e,f,1.1)
 assert(c.stress>before+K.moodStressContact*K.moodGainPro*0.9,'contact')
 before=c.stress; e.commands[2].mistakeId=e.commands[2].mistakeId+1; F.tick(e,f,1.1)
 assert(c.stress>before+K.moodStressMistake*K.moodGainPro*0.9,'own mistake')
 before=c.stress; f.cars[2].position=3; F.tick(e,f,1.1)
 assert(c.stress>before+K.moodStressPlace*K.moodGainPro*0.9,'place lost')
 before=c.stress; f.cars[2].position=2; F.tick(e,f,1.1)
 assert(c.stress<before,'a place gained does not add stress')
 -- Professionnel plus calme que l'amateur.
 local function after(style)
  local e2,f2=scene('C','dynamicPersona',true); e2.states[2].persona.style=style
  F.rear(e2,f2,5,0); F.tick(e2,f2,12); return e2.mood.cars[2].stress
 end
 assert(after(0)<after(1),'a professional keeps calmer than an amateur')
 -- Le style règle le gain : même contact, stress plus fort pour l'amateur.
 local function bump(style)
  local e2,f2=scene('C','dynamicPersona',true); e2.states[2].persona.style=style
  F.tick(e2,f2,1.1); e2.lastContactAt[2]=e2.time; F.tick(e2,f2,1.1); return e2.mood.cars[2].stress
 end
 local pro,am=bump(0),bump(1)
 assert(math.abs(pro-K.moodStressContact*K.moodGainPro)<0.02 and math.abs(am-K.moodStressContact*K.moodGainAm)<0.02,'gain from the style: '..pro..' '..am)
end
tests.MOOD_JOURNAL_160C=function()
 local e,f=scene('C','dynamicPersona',true)
 e.states[2].persona.style=1
 F.rear(e,f,5,0); F.tick(e,f,3); e.mood.cars[2].stress=K.moodLogStress-0.02; F.tick(e,f,3)
 assert(count(e,'humeur: Driver_2 sous pression (stress ')==1 and e.stats.moodStress==1,'one line when the threshold is crossed')
 e.mood.cars[2].stress=0; F.tick(e,f,1.1); e.mood.cars[2].stress=0.9; F.tick(e,f,1.1)
 assert(count(e,'sous pression')==1,'at most one line per car per K.moodLogGap')
 e.states[2].stintStart=e.time-K.moodFatigueStint*K.moodLogFatigue-10; F.tick(e,f,1.1)
 assert(count(e,'humeur: Driver_2 fatigue (relais ')==1 and e.stats.moodTired==1,'tired line')
end
tests.MOOD_FATIGUE_RESET_PIT_160C=function()
 for _,endurance in ipairs({false,true}) do
  local e,f=scene('C','dynamicPersona',true)
  e.profiles.C.enduranceOverlay=endurance; E.changed(e); F.tick(e,f,0.1)
  local s=e.states[2]; local c=e.mood.cars[2]
  s.stintStart=e.time-K.moodFatigueStint/2; F.tick(e,f,1.1)
  assert(math.abs(c.fatigue-0.5)<0.01,'half a stint: '..c.fatigue)
  assert(math.abs(e.commands[2].levelScale-(1-K.moodLevelFatigue*c.fatigue))<1e-9,'level follows fatigue every frame')
  assert(s.moodFatigue and math.abs(s.moodFatigue-(1+K.moodLapseFatigue*c.fatigue))<1e-9 and s.fatigue>=s.moodFatigue,'lapses follow fatigue (director read)')
  s.stint=s.stint+1; s.stintStart=e.time; F.tick(e,f,1.1)
  if endurance then assert(c.fatigue<0.01,'driver change: fully rested: '..c.fatigue)
  else assert(math.abs(c.fatigue-0.5*(1-K.moodFatigueRest))<0.01,'pit stop: partly rested: '..c.fatigue) end
 end
end
tests.MOOD_FROZEN_FLAG_START_160C=function()
 local e,f=scene('C','dynamicPersona',true)
 local s=e.states[2]; local c=e.mood.cars[2]
 s.persona.assertiveness=1; c.stress=1; F.tick(e,f,1.1)
 assert(s.moodAggr and s.moodAggr>1,'active in the race')
 e.startedAt=e.time; c.stress=1; F.tick(e,f,1.1)
 assert(s.moodAggr==nil and s.moodCaution==nil and s.moodRisk==nil and s.moodFatigue==nil and e.commands[2].levelScale==1,'frozen in the start phase')
 assert(c.stress<1 and c.stress>0.9,'stress still decays')
 e.startedAt=-100; F.tick(e,f,1.1); assert(s.moodAggr~=nil,'back after the start')
 e.fl.on=true; e.mood.nextAt=e.time
 Mood.update(e.mood,e,f,e.time); assert(s.moodAggr==nil,'frozen in the careful first lap'); e.fl.on=false
 e.mood.nextAt=e.time; Mood.update(e.mood,e,f,e.time); assert(s.moodAggr~=nil,'back')
 e.incidents.neutral=true; e.mood.nextAt=e.time
 Mood.update(e.mood,e,f,e.time); assert(s.moodAggr==nil,'frozen under neutralisation'); e.incidents.neutral=false
 e.mood.nextAt=e.time; Mood.update(e.mood,e,f,e.time); assert(s.moodAggr~=nil,'back')
 e.incidents.red=true; e.mood.nextAt=e.time
 Mood.update(e.mood,e,f,e.time); assert(s.moodAggr==nil,'frozen under a red flag'); e.incidents.red=false
 e.mood.nextAt=e.time; Mood.update(e.mood,e,f,e.time); assert(s.moodAggr~=nil,'back')
 s.yellow=true; e.mood.nextAt=e.time
 Mood.update(e.mood,e,f,e.time); assert(s.moodAggr==nil,'frozen under a yellow flag')
end
tests.MOOD_PROTECT_160C=function()
 -- Au freinage ou en virage : jamais plus agressive ni moins prudente que sans l'humeur ; en ligne droite, l'humeur agit.
 local function run(on,brake,yaw)
  local e,f=scene('C','dynamicPersona',on)
  local s=e.states[2]; s.persona.assertiveness=1; s.persona.style=1
  local a=f.cars[2]; a.brake=brake; a.gas=brake>0 and 0 or 1; a.yawRate=yaw
  if on then e.mood.cars[2].stress=1 end
  F.tick(e,f,1.1)
  if on then assert(s.moodAggr and s.moodAggr>1.05,'mood asks for more aggression') end
  return e.commands[2].aggression,e.commands[2].caution
 end
 local aOn,cOn=run(true,1,0); local aOff,cOff=run(false,1,0)
 assert(aOn<=aOff+1e-9 and cOn>=cOff-1e-9,'braking: never above the base ('..aOn..' vs '..aOff..')')
 aOn,cOn=run(true,0,1); aOff,cOff=run(false,0,1)
 assert(aOn<=aOff+1e-9 and cOn>=cOff-1e-9,'corner: never above the base')
 aOn=run(true,0,0); aOff=run(false,0,0)
 assert(aOn>aOff+1e-6,'straight: the mood changes the aggression command ('..aOn..' vs '..aOff..')')
end
tests.MOOD_OFF_NEUTRAL_160C=function()
 local e,f=scene('C')
 F.rear(e,f,5,0); e.lastContactAt[2]=e.time; F.tick(e,f,8)
 local s=e.states[2]
 assert(s.moodAggr==nil and s.moodCaution==nil and s.moodRisk==nil and s.moodFatigue==nil,'dynamicPersona off: no field')
 assert(e.mood.cars[2].stress==0 and e.commands[2].levelScale==1 and e.stats.moodStress==nil,'nothing computed')
 -- Allumé puis coupé : champs retirés.
 e.profiles.C.dynamicPersona=true; E.changed(e); F.tick(e,f,1.1)
 s.stintStart=e.time-K.moodFatigueStint; F.tick(e,f,1.1)
 assert(s.moodCaution~=nil and e.commands[2].levelScale<1,'on')
 e.profiles.C.dynamicPersona=false; E.changed(e); F.tick(e,f,0.1)
 assert(s.moodAggr==nil and s.moodCaution==nil and s.moodRisk==nil and s.moodFatigue==nil and e.commands[2].levelScale==1,'switched off: fields removed')
 -- Section Facteur humain décochée : coupé aussi.
 e,f=scene('C','dynamicPersona',true); e.profiles.C.section_human=false; E.changed(e)
 e.states[2].stintStart=e.time-K.moodFatigueStint; F.tick(e,f,1.1)
 assert(e.states[2].moodCaution==nil and e.commands[2].levelScale==1,'section off: nothing')
 -- Hors course : pas de courbe de phase, pas de place perdue.
 e,f=scene('P','dynamicPersona',true)
 f.cars[2].position=3; F.tick(e,f,1.1); f.cars[2].position=5; F.tick(e,f,1.1)
 assert(e.mood.cars[2].stress==0 and (e.states[2].moodAggr or 1)==1,'practice: no place lost, no race phase')
 -- Le joueur n'a jamais d'humeur.
 assert(e.states[1].moodAggr==nil and e.mood.cars[1].stress==0,'never the player')
end
tests.MOOD_RISK_IN_MISTAKES_160C=function()
 -- Le stress multiplie le risque d'erreur : avec un risque énorme, l'erreur est armée à la première vérification.
 local function armed(risk)
  local e,f=scene('C'); e.profiles.C.mistakesEnabled=true; E.changed(e)
  e.states[2].moodRisk=risk; e.mistakes.cars[2].nextCheck=0
  F.tick(e,f,0.1)
  return e.mistakes.cars[2].armedUntil>e.time
 end
 assert(not armed(nil) and not armed(1),'ordinary risk: not armed at once')
 assert(armed(1e9),'s.moodRisk multiplies the risk')
end
tests.AI_INI_PROBE_160C=function()
 local _,f=scene('C')
 local lines={}
 local a={note=function(_,text) lines[#lines+1]=text end}
 local saved=rawget(ac,'INIConfig')
 local reads=0
 ac.INIConfig={carData=function(index,file)
  assert(file=='ai.ini'); reads=reads+1
  if index==f.cars[3].index then error('unreadable') end
  return {get=function(_,section,key,fallback) if section=='LOOKAHEAD' and key=='BASE' then return 12.5 end return fallback end}
 end}
 local ok,err=pcall(function()
  f.cars[2].id='model_a'; f.cars[2].index=1; f.cars[3].id='model_b'; f.cars[3].index=2
  for _=1,6 do if not a.aiIniDone then Applier.aiIniProbe(a,f) end end
  assert(a.aiIniDone and reads==2,'each AI model read once, the player never: '..reads)
  assert(#lines==2 and lines[1]=='sonde ai.ini: model_a LOOKAHEAD BASE 12.5 GAS_BRAKE absent ; PEDALS BRAKE_HINT absent ; TYRES HINT absent','values or absent: '..tostring(lines[1]))
  assert(lines[2]=='sonde ai.ini: model_b illisible','a failed read is reported, never raised')
  -- Même modèle deux fois : une seule lecture.
  f.cars[3].id='model_a'; a={note=a.note}; lines={}; reads=0
  for _=1,6 do if not a.aiIniDone then Applier.aiIniProbe(a,f) end end
  assert(reads==1 and #lines==1,'one line per car model')
  -- CSP sans la lecture : une ligne, puis plus rien.
  ac.INIConfig={}; a={note=a.note}; lines={}
  for _=1,6 do if not a.aiIniDone then Applier.aiIniProbe(a,f) end end
  assert(#lines==1 and lines[1]=='sonde ai.ini: lecture indisponible (CSP)','unavailable: one line')
 end)
 ac.INIConfig=saved; assert(ok,err)
end
return tests
