-- Correctif 1.63 (grilles de 60, rapport public : trop de sanctions de contact et de limites de piste, bouchons).
-- Noms terminés par _163S. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function out(f,i,on) local a=f.cars[i]; a.wheelsOut=on and 4 or 0; a.offtrack=on end
tests.K_163S=function() assert(K.passLenientRatio==0.7 and K.blameNudgeKmh==8 and K.sanCrowdGap==8 and K.sanCrowdLat==3.5) end
-- Sous neutralisation (après la transition) : une IA qui double rend d'abord la place ; rendue, rien ; gardée,
-- sanction au bout de K.aiGiveBackMax s (avant : sanction aussitôt, place à rendre en plus).
tests.AI_GIVE_BACK_UNDER_NEUTRAL_163S=function()
 local function run(giveBack)
  local e,f=F.scene('C',4); e.profiles.C.neutralization='fcy'; e.profiles.C.yellowEnabled=false; E.changed(e)
  F.place(f,4,6000,0); F.place(f,2,1000,150); F.place(f,3,1010,150)
  local s=e.states[2]; for b=1,#s.pace do s.pace[b]=400/3.6 end; s.paceCount=400
  for _=1,40*10 do F.tick(e,f,0.1); if e.incidents.neutral then break end end
  assert(e.incidents.neutral,'neutralised')
  F.tick(e,f,K.passGiveBack+1)
  F.place(f,2,1000,120); F.place(f,3,1010,120); e.states[2].nextPerception=0; F.tick(e,f,0.5)
  F.place(f,2,1020,120); F.place(f,3,1000,120); e.states[2].nextPerception=0; F.tick(e,f,0.5)
  assert(e.penalties.ai.giveBack[2]==3 and (e.penalties.ai.count[2] or 0)==0,'pass under the neutralisation: place to give back first')
  if giveBack then F.place(f,3,1040,120); e.states[2].nextPerception=0; F.tick(e,f,0.5); assert(e.penalties.ai.giveBack[2]==0,'given back') end
  F.tick(e,f,K.aiGiveBackMax+1)
  return e
 end
 assert((run(true).penalties.ai.count[2] or 0)==0,'place given back: no sanction')
 assert(run(false).penalties.ai.count[2]==1,'place kept: sanction at the deadline')
end
-- Limites de piste : sortie avec une voiture tout près (poussée dehors) excusée ; seule, avertissement.
tests.TRACK_LIMITS_CROWD_163S=function()
 for _,lat in ipairs({-2,2}) do
  local e,f=F.scene('C',4); F.tick(e,f,0.1)
  for i=1,4 do e.states[i].flW=0 end
  F.place(f,1,-3000,100); F.place(f,4,8000,100)
  F.place(f,2,2000,120,0); F.place(f,3,2003,120,lat); e.states[2].nextPerception=0; F.tick(e,f,0.2)
  out(f,2,true); F.tick(e,f,0.5); out(f,2,false); F.tick(e,f,K.sanStrikeGap)
  assert(e.sanctions.cars[2].strikes==0 and (e.stats.tlCrowd or 0)>=1,lat..': car alongside: excused')
  F.place(f,3,4000,120,0); F.place(f,2,2000,120,0); e.states[2].nextPerception=0; F.tick(e,f,0.2)
  out(f,2,true); F.tick(e,f,0.5); out(f,2,false); F.tick(e,f,K.sanStrikeGap)
  assert(e.sanctions.cars[2].strikes==1,lat..': alone: a warning ('..e.sanctions.cars[2].strikes..')')
 end
end
-- Contacts : touchette sans perte de contrôle, personne en tort ; choc franc par l'arrière, jugé comme avant.
tests.CONTACT_NUDGE_163S=function()
 local function hit(diff)
  local e,f=F.scene('C',4); e.profiles.C.sanContact=true; E.changed(e); F.tick(e,f,0.1)
  e.startedAt=e.time-120; for i=1,4 do e.states[i].flW=0 end
  for _=1,8 do F.place(f,2,3000,100,0); F.place(f,3,3005,100,0); F.tick(e,f,0.25) end
  F.place(f,2,3000,100+diff,0); F.place(f,3,3004.6,100,0); f.cars[2].collidedWith=3; F.tick(e,f,1/60); f.cars[2].collidedWith=-1
  F.place(f,2,3000,100,0); F.place(f,3,3010,100,0); F.tick(e,f,K.blameOutcome+0.5)
  return e
 end
 local e=hit(5)
 assert(e.sanctions.cars[2].contacts==0 and (e.stats.blameLenient or 0)==1,'5 km/h nudge: nobody at fault')
 local e2=hit(20)
 assert(e2.sanctions.cars[2].contacts==1 and (e2.stats.blameLenient or 0)==0,'20 km/h hit from behind: judged as before')
end
-- Train d'attardées (rapport public, grilles de 60) : la voiture juste derrière cède déjà au meneur ; celle de devant
-- (même tour qu'elle) laisse aussi passer le meneur, sans attendre qu'il soit collé derrière elle.
tests.BLUE_TRAIN_OPENS_163S=function()
 local function run(train)
  local e,f=F.scene('C',4); e.startedAt=-100
  local function put()
   F.place(f,1,-5000,100); F.place(f,4,0,150); F.place(f,3,-12,150); F.place(f,2,-40,150)
   f.cars[2].lap=f.cars[4].lap+1; f.cars[3].lap=f.cars[4].lap
  end
  put(); e.states[4].nextPerception=0
  for _=1,12 do
   if train then local s3=e.states[3]; s3.state='YIELD_HOLD'; s3.target=2 end
   F.tick(e,f,0.25); put()
   local s4=e.states[4]
   if (s4.state=='YIELD_IN' or s4.state=='YIELD_HOLD') and s4.target==2 then return true end
  end
  return false
 end
 assert(run(true),'car behind already yielding to the leader: the car ahead yields to the leader too')
end
return tests
