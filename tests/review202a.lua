-- Affinage 2.0.2 a (décisions du pilote du 15 novembre, « les deux » : vrais écarts de rythme en course et attaque plus
-- décidée ; puis : déboîtement à la fronde et pas en milieu de ligne droite ; aspiration d'AC à x1 trop faible ; doubler
-- toute voiture nettement plus lente devant). Replays de Monza (S21-S25) : 1 à 7 vrais dépassements par course après le
-- premier tour ; 4 à 12 déboîtements dans le sillage par course, 20 à 38 % à plus de 6 s du freinage, aucun côte à côte
-- atteint ; vitesse maxi avant le freinage dans le sillage (5-30 m) : médiane de -1 à +10 km/h par rapport à seule.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local D=require('src/director')
local Wear=require('src/wear')
local K=require('src/config').K
local tests={}

-- Rythme d'une voiture selon l'usure (w), le carburant (fuel/max) et le profil, par src/wear.lua.
local function paceOf(profile,w,fuel)
 local t=Wear.new()
 local cmd={levelScale=1}
 local e={profile=profile,run={wearPace=true,strategyTyreWearPct=60},strategy={wearTrust='trusted'},states={{}},penalties={ai={dq={}}},commands={cmd},log=require('src/util').newLog(50,100,0)}
 local a={valid=true,control=true,player=false,finished=false,safetyCar=false,wearKnown=true,tyreWear={w,w,w,w},fuel=fuel,maxFuel=100,id='x',name='x',index=1}
 local frame={count=1,cars={a},online=false,replay=false}
 Wear.update(t,e,frame,0,0)
 return t.target[1]
end
tests.LOCK_PACE_DELTA_202=function()
 -- Mi-relais : pneus à 50 % (seuil de la stratégie 60 %), demi-réservoir : course -1,8 %, essais -1,0 %.
 local race,prac=paceOf('C',0.5,50),paceOf('P',0.5,50)
 assert(math.abs((1-race)-0.018)<1e-6 and math.abs((1-prac)-0.010)<1e-6,('mid-stint: race %.4f practice %.4f'):format(race,prac))
 -- Voisins : pneus neufs et 10 % de carburant contre pneus à 50 % et demi-réservoir : écart de 0,5 à 1,5 % visé, ici 2,7 %
 -- en fin de relais seulement (borné).
 local fresh=paceOf('C',0.1,10); local old=paceOf('C',0.5,50)
 assert(fresh-old>=0.005 and fresh-old<=0.03,('neighbour delta %.4f'):format(fresh-old))
 -- Bornes : jamais plus de K.wearRaceMaxLoss en course, ni plus de K.wearRaceMaxGain.
 assert(paceOf('C',1.0,100)>=1-K.wearRaceMaxLoss-1e-9 and paceOf('C',0.0,0)<=1+K.wearRaceMaxGain+1e-9,'bounded')
 -- Qualifications inchangées (même calcul qu'en 2.0.1).
 assert(math.abs(paceOf('Q',0.5,50)-prac)<1e-12,'qualifying unchanged')
 -- Préréglage « Course réaliste » : dispersion du niveau gardée à 2 % (3 % : un évitement de plus au premier tour au banc).
 local C=require('src/config'); local out=C.preset('Course','C',C.defaults('C')); assert(out.paceSpreadPct==2,'race preset spread kept at 2 %')
end

-- Déboîtement trop tôt (milieu de ligne droite) : refusé en course derrière une IA alignée tant qu'il reste plus de
-- K.pullOutSlackMax s de ligne droite au-delà du temps d'arriver à hauteur ; à la fronde, permis.
tests.LOCK_ATTACK_SUSTAIN_202=function()
 assert(K.abortSlowTimeRace>K.abortSlowTime,'race: target must escape longer before the abort')
 for _,sign in ipairs({-1,1}) do
  local e={fl={points={0.5},count=1},profile='C',time=0}
  local a={splineValid=true,spline=0.4,speed=80,length=4.5}
  local frame={length=10000,player=0}
  local target={index=3,gap=8,sa=5,lat=0.5*sign,long=8}
  -- 1000 m de ligne droite (12,5 s) ; arriver à hauteur : (8+4,5)/(10/3,6) = 4,5 s : trop tôt.
  assert(D.towTooEarlyTest(e,{},a,target,frame,'C')==true,sign..': mid-straight pull-out held')
  e.fl.points[1]=0.4+500/10000 -- 6,25 s : dans la fenêtre (4,5 + 3 s)
  assert(D.towTooEarlyTest(e,{},a,target,frame,'C')==false,sign..': at the sling point: allowed')
  e.fl.points[1]=0.5
  assert(D.towTooEarlyTest(e,{},a,target,frame,'P')==false,sign..': practice: unchanged')
  assert(D.towTooEarlyTest(e,{flW=1},a,target,frame,'C')==false,sign..': lap 1: unchanged')
  assert(D.towTooEarlyTest(e,{slowPlayerFor=3},a,target,frame,'C')==false,sign..': slow car ahead: pass at once')
  -- Pas tout à fait aligné (1,8 m) : retenu aussi (il se recale) ; écarté (3 m) : inchangé.
  target.lat=1.8*sign; assert(D.towTooEarlyTest(e,{},a,target,frame,'C')==true,sign..': loosely aligned: held too')
  target.lat=3.0*sign; assert(D.towTooEarlyTest(e,{},a,target,frame,'C')==false,sign..': not in the tow: unchanged')
  -- Vrai avantage de vitesse (+20 km/h, au moins K.towTooEarlySa) : déboîtement libre (sortie de virage de la 1.64 o1).
  target.lat=0.5*sign; target.sa=20; assert(D.towTooEarlyTest(e,{},a,target,frame,'C')==false,sign..': real speed advantage: free')
 end
end

-- IA nettement plus lente devant (comme le joueur lent de la 2.0.1) : doublée à la première occasion sûre.
local function scene(lat,gap,kmh,aiKmh,acBrake,pointM)
 local e,f=F.scene('C',3); e.startedAt=-100
 local p=e.profiles.C; p.personalLineJitter=0; p.lapseEnabled=false; p.pressureEnabled=false; p.startDelay=0; p.startRelax=0
 E.changed(e)
 local s=e.states[2]
 local st={}
 for k=1,180 do
  F.place(f,3,2000+gap,kmh,lat); F.place(f,2,2000,aiKmh); F.place(f,1,-4000,100)
  f.cars[2].yawRate=0.005; f.cars[3].yawRate=0.05; f.cars[2].brake=acBrake
  e.fl.points={(f.cars[2].spline+pointM/f.length)%1}; e.fl.count=1
  s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=200/3.6 end; s.paceMean=200/3.6
  F.tick(e,f,1/60); st[s.state]=true
 end
 return s,e,st
end
local function passing(st) return st.OVT_OUT or st.OVT_IN or st.OVT_HOLD end
tests.LOCK_PASS_SLOW_CAR_202=function()
 for _,lat in ipairs({3.0,-3.0}) do
  -- IA 12 m devant, écartée de 3 m, à 130 km/h (allure libre 200) ; suiveuse à sa vitesse, freinée par AC à 0,4.
  local s,e,st=scene(lat,12,130,131,0.4,400)
  assert((e.stats.slowCarPass or 0)>=1 and passing(st),lat..': passes the slow car ('..tostring(s.state)..')')
  K.raceSlowAny=false; local s2,e2,st2=scene(lat,12,130,131,0.4,400); K.raceSlowAny=true
  assert((e2.stats.slowCarPass or 0)==0,lat..': rule off: no slow-car pass')
  local _,e3=scene(lat,12,198,199,0.4,400); assert((e3.stats.slowCarPass or 0)==0,lat..': car at pace: no rule')
  -- Point de freinage proche (40 m) : la nouvelle règle ne lance rien (le dépassement entre IA au freinage reste celui de la
  -- 1.63, attaque au freinage « dive », inchangé : même issue règle coupée).
  local _,_,st4=scene(lat,12,130,131,0.4,40)
  K.raceSlowAny=false; local _,_,st5=scene(lat,12,130,131,0.4,40); K.raceSlowAny=true
  assert((passing(st4) and true or false)==(passing(st5) and true or false),lat..': braking zone: same as 2.0.1')
 end
end

tests.K_202A=function()
 assert(K.wearRaceMult==1.8 and K.wearRaceMaxLoss==0.03 and K.wearRaceMaxGain==0.015 and K.abortSlowTimeRace==4.5)
 assert(K.towBoost==0.02 and K.towBoostMin==3 and K.towBoostRange==30 and K.towBoostSpeed==200 and K.pullOutSlackMax==3 and K.raceSlowAny==true and K.towTooEarlyLat==2.5 and K.towTooEarlySa==15)
end
return tests
