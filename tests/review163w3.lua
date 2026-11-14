-- Affinage 1.63 w3 (Monza, F1, 22 IA, session 3 du pilote du 13 novembre, journal 2026-11-13_16_35_16_monza : 140
-- tentatives, 1 réussie ; 56 fins « sans rapprochement » (écart mini moyen 11,6 m) et 65 « cible plus rapide » (9,9 m) ;
-- 2 frondes seulement, aucune attaque au freinage) : la prudence de suivi (×1,3 à 10 m), l'avertissement du radar
-- (2,5 s) et son frein (1,2 s) tenaient le suiveur à une dizaine de mètres. Rapprochement dans le sillage en ligne droite.
-- Noms LOCK_*_163 (tests/LOCKS.md). Chargé par tests/extended.lua. Scènes latérales avec -1 / -1 et +1 / +1.
local F=require('tests/fixture')
local E=require('src/engine')
local K=require('src/config').K
local tests={}

-- Course, ligne droite : suiveur (voiture 2) à gap m derrière sa cible (voiture 3), même allure (250 km/h), décalage
-- latéral lat m ; point de freinage à np m devant. Rend l'état, la commande et le moteur après seconds s.
local function follow(sign,o)
 o.v=o.v or 250
 local e,f=F.scene('C',3); e.g.offsetSign=sign; e.g.sideSign=sign
 local p=e.profiles.C; p.personalLineJitter=0; p.startDelay=0; p.startRelax=0; E.changed(e)
 for i=1,f.count do f.cars[i].sideDot=sign end
 F.place(f,1,-5000,100); f.started=true; F.tick(e,f,40)
 e.fl.count=1
 local s=e.states[2]; local z=0; local seen=false
 for k=1,60*(o.seconds or 3) do
  local t=k/60
  local vt=o.v
  if o.decelAt and t>=o.decelAt and (not o.decelFor or t<o.decelAt+o.decelFor) then vt=math.max(80,o.v-(t-o.decelAt)*o.decel*3.6) end
  if o.decelFor and o.decelAt and t>=o.decelAt+o.decelFor then vt=o.v end
  o.gap=(o.gap or 12)-(o.v-vt)/3.6/60
  z=z+o.v/3.6/60
  F.place(f,2,z,o.v,0); F.place(f,3,z+o.gap+4.4,vt,o.lat or 0)
  if o.frontBrake or o.brakeWith and o.decelAt and t>=o.decelAt then f.cars[3].brake=0.8 end
  if o.unknownNp then e.fl.points={}; e.fl.count=0 end
  if k==1 or o.keepNp then e.fl.points={(e.frame.cars[2].spline+(o.np or 1900)/e.frame.length)%1} end
  if o.flW then s.flW=o.flW end
  s.nextPerception=0; F.tick(e,f,1/60)
  if s.closeIn then seen=true end
  if o.onTick then o.onTick(e,s,t) end
 end
 return e,s,seen
end

-- Monza S3 : aligné à 12 m, même allure, loin du freinage : il se rapproche (prudence au plus K.closeInCaution, sous la
-- prudence native) ; premier tour, voiture de devant qui freine, décalé de 2 m ou à 0,3 s du freinage : comme avant.
tests.LOCK_CLOSE_IN_TOW_163=function()
 for _,sign in ipairs({1,-1}) do
  local e,s,seen=follow(sign,{gap=12})
  assert(seen and s.closeIn,sign..': aligned in the tow at 12 m: closes in')
  assert(e.commands[2].caution<=K.closeInCaution+0.05,sign..': caution lowered ('..string.format('%.2f',e.commands[2].caution)..')')
  assert((e.stats.closeIn or 0)>=1,sign..': counted')
  local _,s1=follow(sign,{gap=12,flW=1}); assert(not s1.closeIn,sign..': never on the first lap')
  local _,s2=follow(sign,{gap=12,frontBrake=true}); assert(not s2.closeIn,sign..': target braking: released')
  local _,s3=follow(sign,{gap=12,lat=2*sign}); assert(not s3.closeIn,sign..': not aligned: unchanged')
  local _,s4=follow(sign,{gap=12,np=20,keepNp=true}); assert(not s4.closeIn,sign..': braking point within the lead: released')
  local _,s5=follow(sign,{gap=2.5}); assert(not s5.closeIn,sign..': closer than the minimum: unchanged')
  local e6,s6=follow(sign,{gap=12,seconds=1}); assert(s6.closeIn,sign..': short scene')
 end
end

-- Monza, session 4 (journal 2026-11-13_17_16_25_monza : 33 contacts, « touche l arriere de » à 16-40 km/h au freinage de
-- la Prima Variante (687 m) et de la Parabolica (5142-5160 m), suiveur à 3-6 m) : fin du rapprochement dès que la voiture
-- de devant lève le pied ou freine, à moins de K.closeInBrakeLead s d'un point de freinage, point inconnu, ou
-- rapprochement de plus de K.closeInNearSa km/h à moins de K.closeInNearGap m ; prudence rendue d'un coup, radar entier,
-- pas de reprise avant K.closeInHoldOff s.
tests.LOCK_CLOSE_IN_BRAKE_RELEASE_163=function()
 for _,sign in ipairs({1,-1}) do
  -- Cible à 300 km/h qui freine (30 m/s²) au bout de 2 s, suiveur à 5 m : relâché dans l'image, prudence rendue.
  local released,cautionAt,was=nil,nil,false
  follow(sign,{v=300,gap=5,np=1900,decelAt=2,decel=30,brakeWith=true,seconds=2.2,onTick=function(e,s,t)
   if t<1.99 and s.closeIn then was=true end
   if t>=2 and not released and not s.closeIn then released=t; cautionAt=e.commands[2].caution end
  end})
  assert(was,sign..': closed in before the braking')
  assert(released and released<=2+2/60,sign..': released at once when the target brakes ('..tostring(released)..')')
  assert(cautionAt>=K.defaultCaution,sign..': caution given back at once ('..string.format('%.2f',cautionAt)..')')
  -- Levée de pied sans frein (5 m/s²) : relâché aussi ; puis pas de reprise avant K.closeInHoldOff s.
  local rel2,again=nil,nil
  follow(sign,{v=300,gap=6,np=1900,decelAt=2,decel=5,decelFor=0.5,seconds=4,onTick=function(e,s,t)
   if t>=2 and not rel2 and not s.closeIn then rel2=t end
   if rel2 and s.closeIn and not again then again=t end
  end})
  assert(rel2 and rel2<=2.2,sign..': released when the target lifts')
  assert(not again or again-rel2>=K.closeInHoldOff-0.05,sign..': no resume before the hold-off')
  -- Point de freinage à 80 m (moins de K.closeInBrakeLead s à 300 km/h ; 1,2 s depuis la session 6 de Monza, décision du pilote) ou inconnu : jamais.
  local _,s3=follow(sign,{v=300,gap=6,np=80,keepNp=true}); assert(not s3.closeIn,sign..': braking point too near')
  local _,s4,seen4=follow(sign,{v=300,gap=6,unknownNp=true}); assert(not seen4,sign..': unknown braking point: never')
 end
end

-- Constantes du lot.
tests.K_163W3=function()
 assert(K.closeInBrakeLead>=1.2 and K.closeInFrontDecel<=3 and K.closeInHoldOff>=2 and K.closeInEnabled==true and K.closeInMin==3 and K.closeInGap==30 and K.closeInCaution<K.defaultCaution and K.closeInTTC>0 and K.closeInRadarTTC<K.radarTTC)
end

return tests
