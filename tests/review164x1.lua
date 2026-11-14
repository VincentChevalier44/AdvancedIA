-- Affinage 1.64 x1 (Monza, F1, 22 IA, session 13 du pilote du 13 novembre, journal 2026-11-13_22_43_50_monza : 120 tentatives,
-- 0 réussie ; 75 fins « cible plus rapide », toutes encore alignées dans le sillage, à 4-12 m au plus près ; frondes à
-- 14-21 m, perdues ensuite). En course hors premier tour, l'attaquant qui attend dans l'aspiration d'une IA en ligne droite
-- (aligné, au plus K.wakeHoldGap m, point de freinage connu) garde son attaque ; pas de fronde au-delà de K.slingMaxGap m.
-- Noms LOCK_*_164 (tests/LOCKS.md). Chargé par tests/extended.lua.
local D=require('src/director')
local F=require('tests/fixture')
local E=require('src/engine')
local K=require('src/config').K
local tests={}

-- Scène : attaquant 2 aligné derrière la cible 3 (gap m, cible plus rapide de quelques km/h), point de freinage à 2000 m.
local function holdScene(lat,gap,targetKmh,known)
 local e,f=F.scene('C',4); local p=e.profiles.C
 p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.passAid=false; p.startDelay=0; p.startRelax=0
 E.changed(e); F.tick(e,f,0.2)
 F.place(f,1,-5000,100); F.place(f,4,5000,100); F.place(f,2,0,150,lat); F.place(f,3,gap+4.4,targetKmh,lat)
 if known~=false then e.fl.points={(f.cars[2].spline+2000/f.length)%1}; e.fl.count=1 else e.fl.points={}; e.fl.count=0 end
 local s=e.states[2]
 s.state='OVT_ARM'; s.reason='pass'; s.since=e.time; s.target=3; s.targetSide=1; s.passStartAt=e.time; s.passMinGap=gap; s.passName='Cible'
 s.abortSlow=0; s.passStall=0; s.passAlongside=false; s.passProgRef=gap; s.passProgTime=0; s.lastPassTarget=3; s.nextPerception=0
 return e,f,s
end
local function hold(lat,gap,targetKmh,seconds,known)
 local e,f,s=holdScene(lat,gap,targetKmh,known)
 local t=0
 while t<seconds do
  F.place(f,2,0,150,lat); F.place(f,3,gap+4.4,targetKmh,lat); s.nextPerception=0
  if known~=false then e.fl.points={(f.cars[2].spline+2000/f.length)%1}; e.fl.count=1 end
  F.tick(e,f,1/60); t=t+1/60
  if not F.passing(s.state) or s.state=='OVT_OUT' then return s,e,true end
 end
 return s,e,false
end
tests.LOCK_WAKE_HOLD_164=function()
 local savedTg=K.abortTgGrowRace; K.abortTgGrowRace=K.abortTgGrow
 local ok,err=pcall(function()
  for _,lat in ipairs({0.3,-0.3}) do
   -- Session 13 : 8 m derrière, cible 6 km/h plus rapide, alignés : l'attaque n'est plus coupée « cible plus rapide ».
   local s,_,ended=hold(lat,8,156,K.abortSlowTime+4)
   assert(not ended and s.state=='OVT_ARM',lat..': waits in the tow: '..tostring(s.state)..' '..tostring(s.reason))
   -- Règle coupée : comportement d'avant (fin « cible plus rapide »).
   K.wakeHoldEnabled=false; s,_,ended=hold(lat,8,156,K.abortSlowTime+4); K.wakeHoldEnabled=true
   assert(ended,lat..': switch off: the attempt ends as in 1.64 ('..tostring(s.reason)..')')
   -- Plus loin que K.wakeHoldGap m, ou point de freinage inconnu : règles d'avant.
   s,_,ended=hold(lat,K.wakeHoldGap+6,156,K.abortSlowTime+4); assert(ended,lat..': beyond the hold gap: ends ('..tostring(s.reason)..')')
   s,_,ended=hold(lat,8,156,K.abortSlowTime+4,false); assert(ended,lat..': unknown braking point: ends ('..tostring(s.reason)..')')
  end
 end)
 K.abortTgGrowRace=savedTg; K.wakeHoldEnabled=true
 assert(ok,err)
end
-- Règle de la fronde seule (seekLate), valeurs de la session 13 : fronde à 14,5-21,3 m perdue ; au-delà de K.slingMaxGap m,
-- l'attaquant reste dans l'aspiration ; à 10 m (verrou validé) la fronde vaut toujours.
local function run(o)
 local e={profile='C',fl={points={o.np and 0.4+o.np/10000 or nil},count=o.np and 1 or 0},time=0}
 local a={splineValid=true,spline=0.4,speed=69,length=5.3,corner=1}
 local s={seekFront=0,flW=0}
 local f={length=10000,player=1}
 local target={index=3,gap=o.gap,sa=0,lat=o.lat,long=o.gap+5}
 local r
 for k=0,60 do e.time=k/60; r=D.seekLateTest(e,s,a,target,f) end
 return r,s
end
tests.LOCK_SLING_MAX_GAP_164=function()
 for _,lat in ipairs({0.5,-0.5}) do
  for _,gap in ipairs({14.5,18.5,21.3}) do assert(run({gap=gap,lat=lat,np=150})==false,lat..', '..gap..' m: no sling from that far') end
  -- Décision du pilote 2026-11-14 : règle du dernier moment coupée en jeu ; la fronde bornée vaut sur le chemin de S12 ;
  -- la raison « sling » n'est notée que par la règle du dernier moment.
  local r,s=run({gap=10,lat=lat,np=300}); assert(r==true and (not K.lastPullEnabled or s.lastPullWhy=='sling'),lat..': 10 m: sling as before')
 end
end
-- Règle du dernier moment forcée (lot u1, coupée en jeu depuis le 14 novembre) : la borne de la fronde y vaut aussi.
tests.SLING_MAX_GAP_LASTPULL_164F1=function()
 local was=K.lastPullEnabled; K.lastPullEnabled=true
 local ok,err=pcall(tests.LOCK_SLING_MAX_GAP_164)
 K.lastPullEnabled=was; assert(ok,err)
end
-- Chemin de S12 forcé (règle du dernier moment coupée), depuis que le pilote l'a rallumée le 14 novembre (1 m avec
-- garde-fous) : la borne de la fronde y vaut toujours (série longue après installation).
tests.SLING_MAX_GAP_S12_164F1=function()
 local was=K.lastPullEnabled; K.lastPullEnabled=false
 local ok,err=pcall(tests.LOCK_SLING_MAX_GAP_164)
 K.lastPullEnabled=was; assert(ok,err)
end
tests.K_164X1=function()
 assert(K.wakeHoldEnabled==true and K.wakeHoldGap==20 and K.slingMaxGap==12 and K.slingMaxGap>=10 and K.wakeHoldLogPeriod>=10,'constants')
end
return tests
