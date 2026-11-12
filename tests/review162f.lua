-- Beta 1.62, relecture indépendante (S5, S6, S9, S11) : mesure par rotation gardée pour l'étalonnage et l'aspiration,
-- zigzag du tour de formation selon la vitesse, défense hors course, compteurs des règles par session dans le résumé.
-- Noms terminés par _162F. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local D=require('src/director')
local J=require('src/journal')
local Antics=require('src/antics')
local K=C.K
local tests={}

-- S5 : courbe rapide (rotation faible, accélération latérale forte) : a.corner bas (règles de ligne droite) mais la
-- mesure d'avant (a.cornerYaw) reste haute : étalonnage, apprentissage des points, aspiration et DRS inchangés.
tests.CORNER_YAW_KEPT_162F=function()
 local e,f=F.scene('P',3); F.tick(e,f,1/60)
 local a=f.cars[2]; local ref=e.run.cornerYawRef
 F.place(f,2,2000,250); a.yawRate=ref*0.1; F.tick(e,f,1/60)
 assert(a.corner<K.calibrationCorner,'fast curve: not a straight for the passing rules ('..a.corner..')')
 assert(math.abs(a.cornerYaw-0.9)<1e-6 and a.corner<a.cornerYaw-0.03,'yaw-only measure kept: '..tostring(a.cornerYaw)..' / '..a.corner)
 assert(math.abs(D.cornerness(ref*0.1,0,ref)-0.9)<1e-9,'at rest both measures agree')
end
-- S6 : amplitude du zigzag de formation réduite avec la vitesse ; arrêt causé par sa propre accélération latérale :
-- cible tenue, pas de retour brusque à zéro.
tests.FORMATION_WEAVE_SPEED_162F=function()
 local lo=K.formWeaveAmp*1
 local hi=K.formWeaveAmp*K.formWeaveFastShare
 assert(K.formWeaveFullKmh<K.formWeaveFastKmh and hi<lo,'amplitude shrinks with speed')
 local e,f=F.scene('C',3); F.tick(e,f,1/60)
 local s=e.states[2]
 local t={active=true,weaving=true,form={},period={}}
 for i=1,K.maxCars do t.form[i]=0; t.period[i]=0 end
 e.incidents.formation=true; e.incidents.rollCall=false
 F.place(f,1,0,30); F.place(f,2,3000,150); F.place(f,3,6000,30)
 t.form[2]=0.3; f.cars[2].yawRate=(K.weaveLatAccel+1)/(150/3.6)
 local mayWeave=Antics.mayWeave
 Antics.mayWeave=function(ee,ff,i,lap,skip) return skip==true end
 Antics.weave(t,e,f,e.time,1/60)
 Antics.mayWeave=mayWeave
 assert(math.abs(t.form[2]-0.3)<1e-9,'own lateral acceleration: target held, no snap back ('..t.form[2]..')')
end
-- S9 : défense et ses réglages masqués hors course ; un « non » du joueur gardé en course ; hors course, coupée (ne
-- compte pas pour needsOffset).
tests.DEFENSE_RACE_ONLY_162F=function()
 for _,key in ipairs({'defenseEnabled','defenseMaxOffset','defenseCooldown','defenseTriggerGap'}) do
  assert(C.hidden('P',key) and C.hidden('J',key) and not C.hidden('C',key),key)
 end
 local d=C.defaults('C'); d.defenseEnabled=false
 local race=C.validate('C',d,{})
 assert(race.defenseEnabled==false,'race: the player\'s « off » is kept')
 local q={yieldEnabled=false,blueFlagEnabled=false,flashMode='never',overtakeEnabled=false,defenseEnabled=true,obstacleEnabled=false,laneBiasEnabled=false,personalLineJitter=0,multiClass=false}
 assert(not C.needsOffset(q,'P') and C.needsOffset(q,'C'),'outside the race, defence alone needs no offset')
end
-- S11 : compteurs des règles par session dans le résumé de la minute (s'il y en a eu), traduits.
tests.MINUTE_SUMMARY_RULES_162F=function()
 local e=F.scene('C',4)
 local text=J.summary(e)
 assert(not text:find('regles des sessions',1,true),'nothing when all are zero')
 e.stats.lapEndHold=1; e.stats.qualiRedo=2; e.stats.blueIgnored=1; e.stats.passFree=3.5
 text=J.summary(e)
 local at=text:find('regles des sessions',1,true)
 assert(at,'present')
 assert(text:find('regles des sessions : attaquant libre 3.5 s, fin de tour gardee 1, tours refaits 2,',1,true),text:sub(at,at+300))
 assert(text:find('regles des sessions : attaquant libre 3.5 s, fin de tour gardee 1, tours refaits 2, ecart de sortie 0, chauffes en journee circuit 0, refroidissements en journee circuit 0, file de formation etiree 0, penalites drapeaux bleus 1',1,true),text)
 local en=J.english(' | regles des sessions : attaquant libre 3.5 s, fin de tour gardee 1, tours refaits 2')
 assert(en:find('session rules: attacker free 3.5 s, lap-end hold 1, laps redone 2',1,true),en)
end
return tests
