-- Affinage 1.62 (demande de la communauté, décision du pilote du 12 novembre) : recherche de l'aspiration en ligne droite
-- (src/director.lua, slipSeek). Noms terminés par _162S. Chargé par tests/extended.lua. Chaque scène tourne avec le sens
-- latéral du jeu (-1 / -1) et avec +1 / +1.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local D=require('src/director')
local P=require('src/perception')
local K=C.K
local tests={}
local function learned(e,i,kmh) local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=kmh/3.6 end; s.paceMean=kmh/3.6 end
local function scene(profile,count,sign,tune)
 local e,f=F.scene(profile,count); e.g.offsetSign=sign; e.g.sideSign=sign
 local p=e.profiles[profile]; p.startDelay=0; p.startRelax=0; p.personalLineJitter=0; p.slipstreamEnabled=true; p.overtakeEnabled=false
 if tune then tune(p) end
 E.changed(e)
 for i=1,count do f.cars[i].sideDot=sign end
 return e,f
end
-- Voiture 2 à 200 km/h, voiture 3 devant à gap m, écartée de lat m, à kmh3 km/h ; point de freinage à point m devant.
local function run(profile,sign,o)
 o=o or {}
 local e,f=scene(profile,3,sign,o.tune)
 F.place(f,1,-5000,100)
 local gap,lat,v3=o.gap or 30,o.lat or 2.5,o.kmh3 or 198
 F.place(f,2,0,200,0); F.place(f,3,gap+4.4,v3,lat*sign)
 F.tick(e,f,0.1)
 local a=f.cars[2]
 if o.point~=false then e.fl.points[1]=(a.spline+(o.point or 800)/f.length)%1; e.fl.count=1 end
 if o.setup then o.setup(e,f) end
 local s=e.states[2]
 for _=1,o.frames or 30 do
  learned(e,2,200); learned(e,3,v3)
  F.place(f,2,0,200,0); F.place(f,3,gap+4.4,v3,lat*sign); s.nextPerception=0
  if o.each then o.each(e,f) end
  F.tick(e,f,1/60)
 end
 return e,s,f
end

tests.K_162S=function()
 assert(K.seekLat==1 and K.seekLatMax==5 and K.seekTime==2 and K.seekRange==90 and K.seekSaMax==25 and K.seekTTC==3)
 assert(K.seekAheadTime==5 and K.seekReturnTime==3 and K.seekSettleLat==0.4 and K.seekSettle==1.5 and K.seekPullMargin==1.5)
end

-- Course, essais : voiture de devant écartée de 2,5 m sur une longue ligne droite : l'IA se recale derrière elle (vers
-- son côté), une ligne au journal, un épisode compté.
tests.SLIPSTREAM_SEEK_BEHIND_OFFLINE_CAR_162S=function()
 for _,profile in ipairs({'C','P'}) do
  for _,sign in ipairs({-1,1}) do
   local e,s=run(profile,sign)
   local r=P.find(e.perception.rows[2],3)
   assert(s.seekFront==3,profile..' '..sign..': episode started ('..tostring(s.seekFront)..', '..s.state..')')
   assert(s.seekAt and s.seekAt*(-r.lat)>0,profile..' '..sign..': target towards the car ahead')
   assert(s.offset*(-r.lat)>0,profile..' '..sign..': moving towards the car ahead ('..s.offset..')')
   assert((e.stats.slipSeek or 0)==1,'one episode counted')
   local n=0; for _,m in ipairs(e.log.entries or {}) do if tostring(m.text or m):find('aspiration recherchee: Driver_2 derriere Driver_3',1,true) then n=n+1 end end
   assert(n<=1,'one journal line per episode')
  end
 end
end

-- Épisode coupé une image puis repris (même paire) : pas de nouvelle ligne ni de nouveau compte avant K.seekLogGap s ;
-- après, oui. La conduite, elle, reprend aussitôt (seekFront reposé).
tests.SLIPSTREAM_SEEK_JOURNAL_PER_PAIR_162S=function()
 assert(K.seekLogGap==20)
 for _,sign in ipairs({-1,1}) do
  local e,s,f=run('C',sign)
  assert(s.seekFront==3 and (e.stats.slipSeek or 0)==1,sign..': episode started')
  local row=e.perception.rows[2]
  local function again(t)
   s.seekFront=0; s.seekAt=nil
   return D.slipSeekTest(e,s,f.cars[2],row,e.run,'C',f,t,P.find(row,3),false,0,false,2,e.runtimeG,e.aero)
  end
  assert(again(e.time+1)~=nil and s.seekFront==3,sign..': seeking resumes at once')
  assert(e.stats.slipSeek==1,sign..': no new count within the gap ('..e.stats.slipSeek..')')
  assert(again(e.time+K.seekLogGap+2)~=nil and e.stats.slipSeek==2,sign..': counted again after the gap')
 end
end

-- Jamais : journée circuit ; option coupée ; voiture de devant sur la trajectoire ; ligne droite trop courte (point de
-- freinage à 200 m) ou inconnue ; drapeau jaune ; voiture rattrapée trop vite ; côté occupé.
tests.SLIPSTREAM_SEEK_GUARDS_162S=function()
 for _,sign in ipairs({-1,1}) do
  local function none(label,e,s) assert((s.seekFront or 0)==0 and (e.stats.slipSeek or 0)==0,sign..': '..label) end
  none('track day',run('J',sign))
  none('option off',run('C',sign,{tune=function(p) p.slipstreamEnabled=false end}))
  none('car ahead on the line',run('C',sign,{lat=0.5}))
  none('short straight',run('C',sign,{point=200}))
  none('straight unknown',run('C',sign,{point=false}))
  none('careful first lap',run('C',sign,{each=function(e) e.states[2].flW=1 end}))
  none('closing too fast',run('C',sign,{kmh3=160}))
  none('in a corner',run('C',sign,{each=function(e,f) f.cars[2].yawRate=0.2 end}))
 end
end

-- Qualifications : seulement en tour lancé, jamais avec une voiture lancée juste derrière.
tests.SLIPSTREAM_SEEK_QUALI_162S=function()
 for _,sign in ipairs({-1,1}) do
  local e,s,f=run('Q',sign,{frames=1})
  local function try(push2,pushBack,cool)
   local q=e.quali; q.active=true; q.push[2]=push2; q.push[1]=pushBack; q.cars[2].cool=cool or false
   if pushBack then F.place(f,1,-30,200,0) else F.place(f,1,-5000,100) end
   F.refresh(e,f,2); s.seekFront=0; s.seekAt=nil
   local row=e.perception.rows[2]
   return D.slipSeekTest(e,s,f.cars[2],row,e.run,'Q',f,e.time,P.find(row,3),false,0,false,2,e.runtimeG,e.aero)~=nil
  end
  assert(try(true,false),sign..': flying lap seeks the tow')
  assert(not try(false,false),sign..': out lap does not')
  assert(not try(true,false,true),sign..': cool-down lap does not')
  assert(not try(true,true),sign..': never with a car on a flying lap just behind')
 end
end

-- Retour à la ligne : l'épisode finit quand il reste moins de K.seekReturnTime s de ligne droite.
tests.SLIPSTREAM_SEEK_RETURNS_BEFORE_BRAKING_162S=function()
 for _,sign in ipairs({-1,1}) do
  local e,s,f=run('C',sign)
  assert(s.seekFront==3)
  local a=f.cars[2]; e.fl.points[1]=(a.spline+a.speed*(K.seekReturnTime-0.5)/f.length)%1
  learned(e,2,200); F.place(f,2,0,200,0); F.place(f,3,34.4,198,2.5*sign); s.nextPerception=0; F.tick(e,f,1/60)
  assert((s.seekFront or 0)==0 and s.seekAt==nil,sign..': back to the line before the braking point')
 end
end

-- Déboîtement retenu dans l'aspiration de la cible tant que la ligne droite laisse plus que le temps juste nécessaire.
tests.SLIPSTREAM_SEEK_LATE_PULL_OUT_162S=function()
 local e={fl={points={0.5},count=1}}
 local a={splineValid=true,spline=0.4,speed=60,length=4.4}
 local target={index=3,gap=30,sa=20}
 local s={seekFront=3}
 -- 1000 m devant, il faut (30+4,4)/(20/3,6) = 6,2 s : 16,7 s devant, retenu.
 assert(D.seekLateTest(e,s,a,target,{length=10000})==false,'long straight: still in the tow')
 e.fl.points[1]=0.4+400/10000 -- 6,7 s devant : dans la marge
 assert(D.seekLateTest(e,s,a,target,{length=10000})==true,'just enough left: pull out')
 s.seekFront=0; e.fl.points[1]=0.5
 assert(D.seekLateTest(e,s,a,target,{length=10000})==true,'no tow sought: as before')
 s.seekFront=3; target.gap=6
 assert(D.seekLateTest(e,s,a,target,{length=10000})==true,'already close in the tow: as before')
end

return tests
