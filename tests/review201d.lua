-- Affinage 2.0.1 d (décision du pilote : jaune progressif ; course de Monza du 14 novembre, journal
-- 2026-11-14_18_54_45_monza, t=4600 s : double jaune dans la zone de freinage de la première chicane, voitures proches
-- ralenties aussitôt, suivantes de 92 à 192 km/h plus vite à 29-64 m, « Yazeed Al-Rajhi touche l arriere de Sari Vatanen
-- (32 km/h d ecart) ») : sous jaune, la voiture qui a une voiture plus rapide juste derrière ralentit en douceur
-- (K.yellowRearDecel), et la voiture qui suit freine tôt derrière la plus lente (enveloppe à K.yellowFollowDecel), sans
-- attendre la descente bornée de sa limite. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local K=require('src/config').K
local tests={}

-- Voiture 4 arrêtée en piste à 2000 m (double jaune) ; voiture 2 à frontM m à frontKmh km/h ; voiture 3 gap m derrière elle
-- à backKmh km/h ; décalage latéral lat (les deux signes). Rend les limites jaunes des voitures 2 et 3, image par image.
local function scene(lat,frontM,frontKmh,gap,backKmh,frames)
 local e,f=F.scene('C',4); e.startedAt=-100
 local p=e.profiles.C; p.lapseEnabled=false; p.pressureEnabled=false; p.personalLineJitter=0
 F.place(f,1,-6000,150); F.place(f,2,-4000,150); F.place(f,3,-4100,150); F.place(f,4,2000,0)
 F.tick(e,f,10)
 assert(e.incidents.zoneCount>=1,'zone opened')
 local l2,l3={},{}
 for k=1,frames do
  F.place(f,1,-6000,150); F.place(f,4,2000,0)
  F.place(f,2,frontM,frontKmh,lat); F.place(f,3,frontM-gap,backKmh,lat)
  F.tick(e,f,1/30)
  l2[k]=e.commands[2].yellowLimit; l3[k]=e.commands[3].yellowLimit
 end
 return e,l2,l3
end
local function lines(e,pat) local n=0; for _,l in ipairs(e.log and e.log.lines or {}) do if tostring(l):find(pat,1,true) then n=n+1 end end; return n end

tests.LOCK_YELLOW_RAMP_201=function()
 for _,lat in ipairs({0.6,-0.6}) do
  -- Valeurs du journal : voiture de devant à 200 km/h dans l'approche de la zone, suivante 92 km/h plus vite à 29 m.
  local e,l2,l3=scene(lat,1500,200,29,292,30)
  -- (1) Voiture de devant : descente de sa limite au plus K.yellowRearDecel m/s² (1 s = 30 images).
  local drop=l2[1]-l2[30]
  assert(drop<=K.yellowRearDecel*3.6*(29/30)+1,lat..': front eases gently ('..string.format('%.1f',drop)..' km/h in 1 s)')
  -- (2) Suivante : enveloppe de freinage derrière la plus lente, aussitôt (jamais retardée par la descente bornée).
  local vf=200/3.6; local env=math.sqrt(vf*vf+2*K.yellowFollowDecel*math.max(0,29-K.queueKeep))*3.6
  assert(l3[5]<=env+1,lat..': follower brakes early behind the slower car within 0.15 s ('..string.format('%.0f',l3[5])..' > '..string.format('%.0f',env)..')')
  assert((e.stats.yellowFollow or 0)>=1,lat..': early-yellow counted')
  -- Règle coupée (2.0.0) : la suivante gardait une limite bien plus haute (descente bornée depuis 292 km/h).
  K.yellowRamp=false; local _,m2,m3=scene(lat,1500,200,29,292,30); K.yellowRamp=true
  assert(m3[5]>env+20,lat..': 2.0.0 follower limit stayed high ('..string.format('%.0f',m3[5])..')')
  assert(m2[1]-m2[30]>drop+3,lat..': 2.0.0 front dropped faster ('..string.format('%.1f',m2[1]-m2[30])..')')
  -- Sans voiture plus rapide derrière (même vitesse) : descente d'approche ordinaire, aucune enveloppe de suivi.
  local e3,n2,n3=scene(lat,1500,200,29,200,30)
  assert((e3.stats.yellowFollow or 0)==0,lat..': same speed, no early braking')
 end
end
tests.K_201D=function() assert(K.yellowRamp==true and K.yellowRearWatch==80 and K.yellowRearSa==15 and K.yellowRearDecel==2.5 and K.yellowFollowWatch==250 and K.yellowFollowSa==15 and K.yellowFollowDecel==6 and K.yellowRampLogPeriod==10) end
return tests
