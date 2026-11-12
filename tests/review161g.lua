-- Beta 1.61 (finition, seconde relecture) : lecture de la prévision météo et places des arrêts météo. Chargé par
-- tests/extended.lua.
local K=require('src/config').K
local Snap=require('src/snapshot')
local W=require('src/weather')
local tests={}
-- Prévision de CSP lue seulement météo en direct en service ; lecture ratée : nouvel essai K.wxRetry s plus tard.
tests.WX_READ_GATED_AND_RETRY_161G=function()
 local saved=ac.getSim
 local sim={}
 ac.getSim=function() return sim end
 local ok,err=pcall(function()
  local s={time=5000}
  Snap.wxWanted=false; Snap.wxRead(s)
  assert(s.wxKnown==nil,'switch off: nothing read')
  Snap.wxWanted=true; Snap.wxRead(s)
  assert(s.wxKnown==false and s.wxUpcoming==-1,'fields absent: unknown')
  sim.weatherConditions={currentType=15,upcomingType=7,transition=0.25}
  s.time=5010; Snap.wxRead(s)
  assert(s.wxKnown==false,'no new try before K.wxRetry s')
  s.time=5000+K.wxRetry+1; Snap.wxRead(s)
  assert(s.wxKnown==true and s.wxUpcoming==7 and s.wxCurrent==15 and s.wxTransition==0.25,'tried again later: read')
  sim.weatherConditions.transition=0.5
  s.time=s.time+0.5; Snap.wxRead(s)
  assert(s.wxTransition==0.25,'at most once per K.wxPeriod')
  s.time=s.time+K.wxPeriod; Snap.wxRead(s)
  assert(s.wxTransition==0.5,'read again after the period')
 end)
 ac.getSim=saved; Snap.wxWanted=false
 assert(ok,err)
end
-- IA appelée pour un arrêt météo qui ne rentre pas : place libérée après K.wxCallMax s, les suivantes appelées.
tests.WX_CALLED_CAR_RELEASED_161G=function()
 local n=5
 local live={called={},calledAt={},skipUntil={},critical={},urgency={}}
 local frame={count=n,cars={}}; local cmds={}
 for i=1,n do frame.cars[i]={pit=false}; live.urgency[i]=10-i end
 local function ask() for i=1,n do cmds[i]={weatherPit=true} end end
 ask(); W.stagger(live,frame,cmds,0)
 local called=0; for i=1,n do if cmds[i].weatherPit then called=called+1 end end
 assert(called==K.wxPitWave and cmds[1].weatherPit and not cmds[n].weatherPit,'wave of K.wxPitWave, most urgent first')
 ask(); W.stagger(live,frame,cmds,K.wxCallMax*0.5)
 assert(cmds[1].weatherPit and not cmds[n].weatherPit,'kept while waiting for the lane')
 ask(); W.stagger(live,frame,cmds,K.wxCallMax+1)
 assert(not cmds[1].weatherPit and cmds[n].weatherPit and cmds[n-1].weatherPit,'never entered: place freed, the next cars called')
 frame.cars[n].pit=true; ask(); W.stagger(live,frame,cmds,K.wxCallMax+2)
 assert(cmds[n].weatherPit,'a car in the lane keeps its call')
end
return tests
