-- Beta 1.61, tranche E : météo en direct (noms terminés par _161E). Chargé par tests/extended.lua.
-- Réglage weatherLive (src/wx.lua, src/weather.lua) : tendance et prévision, humidité effective par voiture selon ses
-- pneus, seuil sec/pluie propre au pilote, arrêt anticipé, averse courte, pneu pluie sur l'eau projetée, arrêts étalés.
local F=require('tests/fixture')
local C=require('src/config')
local Wx=require('src/wx')
local W=require('src/weather')
local K=C.K
local tests={}
local KEY='AdvancedIA.weather'
local function logged(e,text)
 local n=0
 for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end
 return n
end
local function near(a,b,eps) return math.abs(a-b)<=(eps or 1e-9) end
-- Course, IA en pneus secs (composé 0), intermédiaires 1, pluie 2 ; audace de 0,5 pour tous ; tous au début du tour.
local function scene(count,live)
 local e,f=F.scene('C',count or 4)
 for i=2,f.count do
  local a=f.cars[i]
  a.tyresKnown=true; a.dryCompound=0; a.interCompound=1; a.wetCompound=2; a.compoundIndex=0; a.currentTyreIsDry=true
  a.nativeRainTyresKnown=true; a.nativeRainTyres=false; a.index=i-1; a.spline=0.1; a.kmh=150
  e.states[i].persona.strategyRisk=0.5
 end
 e.run.section_weather=true; e.run.weatherAdaptation=true; e.run.weatherTyresEnabled=true; e.run.weatherLive=live~=false
 f.wet=0; f.rain=0; f.water=0; f.time=1000
 return e,f
end
-- Une seconde de simulation par pas : src/wx.lua puis src/weather.lua, comme dans le moteur. change(t) règle la scène.
local function run(e,f,from,to,change)
 for t=from,to do
  if change then change(t) end
  Wx.update(e.wx,e,f,t)
  W.step(e.weather,f,e.commands,e.run,t,e.states,0)
 end
end
local function rain(a,index) a.compoundIndex=index; a.currentTyreIsDry=index==0 end
tests.WX_TREND_161E=function()
 local e,f=scene()
 run(e,f,0,5)
 assert(e.wx.trend=='steady' and e.wx.eta==-1,'steady in the dry')
 run(e,f,6,66,function(t) f.rain=(t-5)*0.001 end)
 assert(e.wx.trend=='wetting','rain rising: wetting, got '..e.wx.trend)
 assert(logged(e,'meteo: tendance humide')==1,'one trend line')
 run(e,f,67,400)
 assert(e.wx.trend=='steady','constant rain: steady again')
 run(e,f,401,470,function(t) f.rain=math.max(0,0.061-(t-400)*0.001) end)
 assert(e.wx.trend=='drying','rain falling: drying')
 assert(logged(e,'meteo: tendance sechante')==1,'drying logged once')
end
tests.WX_ETA_161E=function()
 local w=Wx.new()
 w.trend='wetting'; w.pw=0.06; w.sw=0.001; w.pr=0; w.sr=0; w.pa=0; w.sa=0
 assert(near(Wx.eta(w,false),60,1e-6),'time to the wet threshold at the present slope')
 w.pr=0.08; w.sr=0.002
 assert(near(Wx.eta(w,false),10,1e-6),'the first threshold crossed counts')
 assert(Wx.eta(w,true)==-1,'already wet: no crossover while wetting')
 w.sw=0.00001; w.sr=0; w.pr=0
 assert(Wx.eta(w,false)==K.wxEtaMax,'capped')
 w.trend='drying'; w.pw=0.25; w.sw=-0.002; w.pr=0; w.sr=0
 assert(near(Wx.eta(w,true),100,1e-6),'time for the wetness to fall under the dry threshold')
 w.pr=0.1; w.sr=0
 assert(Wx.eta(w,true)==-1,'rain still above its threshold and not falling: unknown')
 w.trend='steady'
 assert(Wx.eta(w,true)==-1 and Wx.eta(w,false)==-1,'steady: unknown')
end
tests.WX_FORECAST_ABSENT_161E=function()
 local e,f=scene()
 f.wxKnown=nil; f.wxUpcoming=nil; f.wxTransition=nil
 run(e,f,0,90,function(t) f.rain=t*0.001 end)
 assert(e.wx.forecast=='unknown' and e.wx.forecastIn==-1,'older CSP: forecast unknown')
 assert(logged(e,'meteo: prevision indisponible')==1,'said once')
 assert(e.wx.trend=='wetting','the trend alone still works')
 f.wxKnown=false; f.wxUpcoming=-1; f.wxTransition=-1
 run(e,f,91,100)
 assert(e.wx.forecast=='unknown' and logged(e,'meteo: prevision indisponible')==1,'fields remembered absent')
end
tests.WX_FORECAST_161E=function()
 local e,f=scene()
 f.wxKnown=true; f.wxCurrent=15; f.wxUpcoming=7; f.wxTransition=0
 run(e,f,0,60,function(t) f.wxTransition=t*0.005 end)
 assert(e.wx.forecast=='rain','upcoming type Rain: class rain, got '..e.wx.forecast)
 assert(e.wx.forecastIn>100 and e.wx.forecastIn<200,'time left from the rate of the transition: '..e.wx.forecastIn)
 assert(logged(e,'meteo: prevision pluie dans')==1,'forecast logged once')
 assert(logged(e,'meteo: prevision indisponible')==0)
 -- Champs constants : prévision inconnue.
 local e2,f2=scene()
 f2.wxKnown=true; f2.wxCurrent=15; f2.wxUpcoming=15; f2.wxTransition=0
 run(e2,f2,0,60)
 assert(e2.wx.forecast=='unknown','same type, no transition: unknown')
end
tests.WX_RAIN_CLASS_161E=function()
 local seen={}
 for kind=0,32 do local c=Wx.rainClass(kind); assert(c=='none' or c=='light' or c=='rain' or c=='heavy','type '..kind..' mapped'); seen[c]=true end
 assert(seen.none and seen.light and seen.rain and seen.heavy)
 assert(Wx.rainClass(15)=='none' and Wx.rainClass(6)=='light' and Wx.rainClass(7)=='rain' and Wx.rainClass(8)=='heavy' and Wx.rainClass(3)=='light')
 assert(Wx.rainClass(33)=='unknown' and Wx.rainClass(-1)=='unknown' and Wx.rainClass(nil)=='unknown' and Wx.rainClass('x')=='unknown')
end
tests.WX_PACE_PROGRESSIVE_161E=function()
 local e,f=scene()
 run(e,f,0,3)
 assert(e.states[2].wxWet==0,'dry: zero')
 f.wet=0.5
 run(e,f,4,4)
 local first=e.states[2].wxWet
 -- Piste devenue mouillée d'un coup : première pluie en pneus secs (K.wxOnsetCaution) pendant K.wxOnsetTime s.
 local target=Wx.carWet(0.5,false,true,false,false,Wx.skill(e.runtimeG.seed,f.cars[2].index),true)
 assert(first>0 and first<target*0.3,'no step when the track turns wet: '..first)
 run(e,f,5,80)
 assert(near(e.states[2].wxWet,target,0.01),'reaches the tyre-dependent value: '..e.states[2].wxWet..' / '..target)
 assert(target>0.5*K.wxSkillMin and e.states[2].wxWet>0.5,'dry tyres on a wet track: more than the raw wetness')
end
tests.WX_TYRE_MISMATCH_161E=function()
 assert(near(Wx.carWet(0.4,false,true,false,false,1,false),0.4*(1+K.wxSlickPenalty)),'dry tyres on a wet track')
 assert(near(Wx.carWet(0.8,true,false,true,true,1,false),0.8*(1+K.wxInterHeavy)),'intermediates in heavy rain')
 assert(near(Wx.carWet(0.8,false,false,true,true,1,false),0.8),'intermediates in ordinary rain: the track')
 assert(near(Wx.carWet(0.8,true,false,false,true,1,false),0.8),'rain tyres in heavy rain: the track')
 assert(near(Wx.carWet(0.05,false,false,false,true,1,false),K.wxWetOnDry),'rain tyres on a drying track')
 assert(near(Wx.carWet(0.4,false,true,false,false,1,true),0.4*(1+K.wxSlickPenalty)*K.wxOnsetCaution),'first rain on dry tyres')
 assert(near(Wx.carWet(0.4,false,false,false,false,1,true),0.4),'tyres unknown: the track')
 assert(Wx.carWet(0,false,true,false,false,1,true)==0,'dry track on dry tyres: zero')
end
tests.WX_SKILL_RANGE_161E=function()
 local low,high=math.huge,-math.huge
 for index=0,60 do
  local s=Wx.skill(7,index)
  assert(s>=K.wxSkillMin and s<=K.wxSkillMax,'in range')
  low=math.min(low,s); high=math.max(high,s)
 end
 assert(high-low>0.2,'drivers differ')
 assert(Wx.skill(7,3)==Wx.skill(7,3),'stable')
 assert(near(Wx.carWet(0.4,false,false,true,true,1.2,false),0.48),'the skill scales the loss')
end
tests.WX_CLAMP_161E=function()
 assert(Wx.carWet(1,true,true,false,false,K.wxSkillMax,true)==K.wxWetMax,'clamped to the maximum')
 assert(Wx.carWet(0,false,false,false,false,1,false)==0)
 assert(K.wxWetMax>1 and K.wxWetMax<=2)
end
tests.WX_OWN_CROSSOVER_161E=function()
 local e,f=scene(4)
 e.states[2].persona.strategyRisk=0.9; e.states[3].persona.strategyRisk=0.1
 run(e,f,0,5)
 f.wet=0.14
 run(e,f,6,6+K.weatherConfirm+2)
 assert(e.weather.wet,'everyone s threshold crossed')
 assert(e.wx.carWet[3]==true and e.wx.carWet[4]==true,'cautious and average drivers: wet')
 assert(e.wx.carWet[2]==false,'bold driver stays on dry tyres longer when it gets wet')
 assert(e.commands[2].weatherCompound==0 and not e.commands[2].weatherPit and e.commands[2].weatherRain==false,'no stop for the bold one')
 assert(e.commands[3].weatherCompound==1 and e.commands[3].weatherPit,'the cautious one stops for intermediates')
 f.wet=0.2
 run(e,f,30,30+K.weatherConfirm+2)
 assert(e.wx.carWet[2]==true,'bold driver wet at its own threshold')
 for i=2,4 do rain(f.cars[i],1); e.wx.cls[i]=false end
 f.wet=0.10
 run(e,f,60,60+K.weatherConfirm+2)
 assert(e.wx.carWet[2]==false,'bold driver fits dry tyres earlier when it dries')
 assert(e.wx.carWet[3]==true and e.wx.carWet[4]==true,'the others wait')
 f.wet=0.04
 run(e,f,90,90+K.weatherConfirm+2)
 assert(e.wx.carWet[4]==false and e.wx.carWet[3]==true,'average driver dry at the usual threshold, the cautious one later')
end
-- Pluie qui monte de 0,001 par seconde : bascule de tous attendue sous K.wxAnticipate s.
local function rising(e,f,to,from)
 if not from then run(e,f,0,3) end
 run(e,f,from or 4,to,function(t) f.rain=(t-3)*0.001 end)
end
tests.WX_ANTICIPATE_BOLD_ONLY_161E=function()
 local e,f=scene(5)
 e.states[2].persona.strategyRisk=0.9; e.states[3].persona.strategyRisk=0.9
 f.cars[2].spline=0.8; f.cars[4].spline=0.8
 rising(e,f,47)
 assert(e.wx.trend=='wetting' and e.wx.eta>K.wxAnticipate,'crossover still far: '..e.wx.eta)
 assert(e.wx.carWet[2]==false and logged(e,'anticipe les pneus')==0,'too early: nobody stops')
 rising(e,f,63,48)
 assert(not e.weather.wet and e.wx.trend=='wetting' and e.wx.eta>=0 and e.wx.eta<=K.wxAnticipate,'crossover expected soon: '..e.wx.eta)
 assert(e.wx.carWet[2]==true and e.wx.early[2]==true,'bold driver near the pit entry stops early')
 assert(e.commands[2].weatherPit and e.commands[2].weatherCompound==1,'with the coming compound')
 assert(e.wx.carWet[3]==false,'bold driver far from the pit entry waits')
 assert(e.wx.carWet[4]==false and not e.commands[4].weatherPit,'average driver waits for its own crossover')
 assert(logged(e,'anticipe les pneus pluie')==1,'logged once')
 assert(e.wx.stats.early==1)
end
tests.WX_COMBO_STOP_161E=function()
 local e,f=scene(4)
 f.cars[2].spline=0.8; f.cars[3].spline=0.8
 local c=e.strategy.cars[2]; c.planned=true; c.nextLap=f.cars[2].lap+K.wxComboLaps
 local d=e.strategy.cars[3]; d.planned=true; d.nextLap=f.cars[3].lap+K.wxComboLaps+2
 rising(e,f,63)
 assert(e.wx.carWet[2]==true and e.wx.early[2]==true,'a stop due within a few laps is taken now with the coming tyres')
 assert(e.wx.carWet[3]==false,'a later stop is not')
end
tests.WX_SHORT_SHOWER_161E=function()
 local e,f=scene(4)
 e.states[2].persona.strategyRisk=0.9
 run(e,f,0,3)
 -- Averse qui faiblit : la pluie baisse de 0,002 par seconde, piste à 0,3.
 e.wx.pr=0.202; e.wx.sr=-0.002; e.wx.pw=0.3; e.wx.sw=0; f.wet=0.3
 run(e,f,4,4+K.weatherConfirm+10,function(t) f.rain=math.max(0,0.2-(t-4)*0.002) end)
 assert(e.weather.wet and e.wx.carWet[3]==true,'average driver goes to rain tyres')
 assert(e.wx.carWet[2]==false and e.wx.hold[2]==true,'bold driver on dry tyres stays out in a short shower')
 assert(not e.commands[2].weatherPit and e.commands[2].weatherCompound==0)
 assert(logged(e,'reste en pneus secs (averse courte')==1 and e.wx.stats.gamble==1,'logged and counted once')
 -- Forte pluie : plus de pari.
 f.wet=0.7
 run(e,f,40,42)
 assert(e.wx.carWet[2]==true and e.wx.hold[2]==false,'heavy rain: the gamble ends')
end
tests.WX_PROJECTED_COMPOUND_161E=function()
 local e,f=scene(3)
 run(e,f,0,3)
 e.wx.pw=0.399; e.wx.sw=0.001; f.wet=0.4
 run(e,f,4,4+K.weatherConfirm+3,function(t) f.wet=0.4+(t-4)*0.001 end)
 assert(e.weather.wet and e.wx.carWet[2]==true)
 assert(f.wet<K.weatherHeavy and e.wx.heavy==true,'water projected above the heavy threshold')
 assert(e.commands[2].weatherCompound==2,'rain tyres chosen on the projected water')
 -- Sans la météo en direct : intermédiaires sur la valeur présente.
 local e2,f2=scene(3,false)
 f2.wet=0.4
 run(e2,f2,0,K.weatherConfirm+3)
 assert(e2.weather.wet and e2.commands[2].weatherCompound==1,'present value without weatherLive')
end
tests.WX_STAGGERED_161E=function()
 local e,f=scene(9)
 f.wet=0.3
 run(e,f,0,K.weatherConfirm+5)
 local called=0
 for i=2,9 do assert(e.wx.carWet[i]==true); if e.commands[i].weatherPit then called=called+1 end end
 assert(called==K.wxPitWave,'limited number of weather calls at a time: '..called)
 local first=0
 for i=2,9 do if e.commands[i].weatherPit then first=i; break end end
 f.cars[first].pit=true
 run(e,f,30,31)
 called=0
 for i=2,9 do if e.commands[i].weatherPit and not f.cars[i].pit then called=called+1 end end
 assert(called==K.wxPitWave,'a car in the pit lane frees its place')
 -- Pneus secs sous forte pluie : jamais retenue.
 f.wet=0.7
 run(e,f,32,34)
 for i=2,9 do assert(e.commands[i].weatherPit,'critical: everyone called '..i) end
 -- Sans la météo en direct : tous appelés au même instant, comme avant.
 local e2,f2=scene(9,false)
 f2.wet=0.3
 run(e2,f2,0,K.weatherConfirm+5)
 for i=2,9 do assert(e2.commands[i].weatherPit,'without weatherLive: all at once') end
end
tests.WX_MIN_STINT_161E=function()
 local e,f=scene(3)
 f.wet=0.3
 run(e,f,0,K.weatherConfirm+3)
 assert(e.wx.carWet[2]==true)
 rain(f.cars[2],1)
 run(e,f,20,21)
 assert(e.wx.stopAt[2]==20,'weather stop seen')
 f.wet=0
 run(e,f,22,20+K.wxMinStint-2)
 assert(not e.weather.wet and e.wx.carWet[2]==true and e.commands[2].weatherCompound==1,'no reversal right after a weather stop')
 run(e,f,20+K.wxMinStint,20+K.wxMinStint+2)
 assert(e.wx.carWet[2]==false and e.commands[2].weatherCompound==0,'allowed after the minimum stint')
 -- Exception : pneus secs sous forte pluie.
 rain(f.cars[2],0)
 run(e,f,300,301)
 local at=e.wx.stopAt[2]
 assert(at==300)
 f.wet=0.7
 run(e,f,302,302+K.weatherConfirm+2)
 assert(e.wx.carWet[2]==true,'dry tyres in heavy rain: reversal allowed')
end
-- Sur la grille avant le départ : conditions présentes pour tous, quel que soit le seuil du pilote.
tests.WX_GRID_PRESENT_161E=function()
 local e,f=scene(3)
 e.states[2].persona.strategyRisk=0.9
 run(e,f,0,3)
 f.wet=0.14
 run(e,f,4,4+K.weatherConfirm+2)
 assert(e.weather.wet and e.wx.carWet[2]==false and e.commands[2].weatherCompound==0,'on track: the bold driver has its own threshold')
 f.started=false; f.cars[2].kmh=0
 run(e,f,30,31)
 assert(e.commands[2].weatherGrid and e.commands[2].weatherCompound==1 and e.commands[2].weatherRain==true,'on the grid: present conditions')
end
tests.WX_KEY_161E=function()
 local e,f=scene(4)
 run(e,f,0,5)
 local text=e.sideText[KEY]
 assert(type(text)=='string' and #text<=K.weatherKeyBytes,'key text bounded')
 assert(text:match('^v=1;wet=%d%.%d%d;rain=%d%.%d%d;water=%d%.%d%d;trend=%a+;eta=%-?%d+;next=%a+;forecast=%a+;forecastIn=%-?%d+;aiDry=%d+;aiRain=%d+;stamp=%d+$'),text)
 assert(text:find('trend=steady;eta=-1;next=none;forecast=unknown;forecastIn=-1;aiDry=3;aiRain=0',1,true),text)
 run(e,f,6,20)
 assert(e.sideText[KEY]==text,'unchanged values: same text, same stamp')
 f.rain=0.05
 run(e,f,21,21)
 assert(e.sideText[KEY]~=text and e.sideText[KEY]:find('rain=0.05',1,true) and e.sideText[KEY]:find('stamp=21',1,true),'new text and stamp on change')
 e.run.weatherLive=false
 run(e,f,22,22)
 assert(e.sideText[KEY]==nil,'key no longer published with the switch off')
end
tests.WX_OFF_IDENTICAL_161E=function()
 -- Réglage weatherLive coupé : aucun champ écrit, mêmes gommes au même instant qu'avant.
 local e,f=scene(5,false)
 local e2,f2=scene(5,false)
 for t=0,60 do
  local wet=t>=10 and 0.3 or 0
  f.wet=wet; f2.wet=wet
  Wx.update(e.wx,e,f,t)
  W.step(e.weather,f,e.commands,e.run,t,e.states,0)
  W.step(e2.weather,f2,e2.commands,e2.run,t,e2.states,0)
  assert(e.weather.live==nil and e.sideText[KEY]==nil)
  for i=2,5 do
   assert(e.states[i].wxWet==nil,'no per-car wetness')
   local a,b=e.commands[i],e2.commands[i]
   assert(a.weatherCompound==b.weatherCompound and a.weatherPit==b.weatherPit and a.weatherRain==b.weatherRain and a.weatherGrid==b.weatherGrid,'same commands at '..t)
  end
 end
 assert(e.weather.wet and e.commands[2].weatherPit)
 -- Allumé puis coupé : tout est rendu.
 e.run.weatherLive=true
 run(e,f,61,65)
 assert(e.states[2].wxWet~=nil and e.weather.live==e.wx)
 e.run.weatherLive=false
 run(e,f,66,66)
 assert(e.states[2].wxWet==nil and e.weather.live==nil and e.wx.live==false,'weatherLive off: fields cleared')
end
tests.WX_NEEDS_PARENT_SWITCHES_161E=function()
 local e,f=scene(4)
 e.run.weatherAdaptation=false
 f.wet=0.3
 run(e,f,0,K.weatherConfirm+3)
 assert(e.states[2].wxWet==nil,'pace effects need « Adapt pace to the weather »')
 assert(e.wx.carWet[2]==true and e.weather.live==e.wx,'tyre effects still on')
 local e2,f2=scene(4)
 e2.run.weatherTyresEnabled=false
 f2.wet=0.3
 run(e2,f2,0,K.weatherConfirm+3)
 assert(e2.states[2].wxWet~=nil and e2.states[2].wxWet>0.3,'pace effects on')
 assert(e2.weather.live==nil and e2.wx.carWet[2]==nil,'tyre effects need « Manage dry and wet tyres »')
 assert(not e2.commands[2].weatherManaged)
end
-- Lecture par le directeur et les erreurs de pilotage : une IA en pneus secs sur piste mouillée perd plus de niveau
-- que la même en pneus pluie (réglage weatherLive), et autant qu'avant réglage coupé.
tests.WX_DIRECTOR_READS_161E=function()
 local function level(live,index)
  local e,f=F.scene('C',3)
  for i=2,3 do
   local a=f.cars[i]
   a.tyresKnown=true; a.dryCompound=0; a.interCompound=1; a.wetCompound=2; rain(a,index); a.nativeRainTyresKnown=true; a.nativeRainTyres=index~=0; a.index=i-1
  end
  e.profiles.C.weatherAdaptation=true; e.profiles.C.weatherTyresEnabled=false; e.profiles.C.weatherLive=live
  require('src/engine').changed(e)
  f.wet=0.5; f.rain=0.3
  F.tick(e,f,40)
  return e.commands[2].level,e.states[2].wxWet
 end
 local slickOn,wetOn=level(true,0)
 local rainOn=level(true,2)
 local slickOff,wetOff=level(false,0)
 local rainOff=level(false,2)
 assert(wetOff==nil and near(slickOff,rainOff,1e-9),'weatherLive off: same loss whatever the tyres')
 assert(wetOn~=nil and wetOn>0.5,'effective wetness above the track s on dry tyres')
 assert(slickOn<slickOff-0.005,'dry tyres on a wet track: slower with weatherLive')
 assert(slickOn<rainOn-0.005,'and slower than on rain tyres')
end
return tests
