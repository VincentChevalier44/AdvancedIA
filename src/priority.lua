-- Beta 1.60 (étape de base) : état de priorité partagé par la priorité au virage (src/director.lua, Beta 1.59), l'aide
-- au dépassement (tranche A) et la responsabilité des collisions (tranche B). Tests purs, sans fonction de CSP, sans
-- table ni chaîne créée par appel. Champs par voiture (e.states[i]) :
--   s.cornerGiveTo  indice de la voiture à qui l'IA laisse le virage (0 : personne), écrit par src/director.lua (1.59) ;
--   s.committed     indice de la voiture que l'attaquant est engagé à dépasser (0 : aucune), s.commitSide (-1 gauche,
--                   1 droite, 0 inconnu), s.commitAt (heure de l'engagement) : écrits par M.commit, effacés par M.release ;
--   s.heldBy        indice de l'attaquant engagé pour qui le défenseur garde sa ligne (0 : aucun), s.heldUntil (heure de
--                   fin) : écrits par M.hold, lus par M.held.
-- Seule la tranche A écrit ces champs (src/director.lua) ; src/blame.lua et les zones d'attaque de la 1.61 les lisent.
local C=require('src/config')
local K=C.K
local M={}
-- Avance du nez de b sur celui de a (m, positive : nez de b devant). long : avance du centre de b sur le centre de a
-- (ligne de perception de a, r.long). Même formule que la priorité au virage de la 1.59.
function M.nose(a,b,long) return long+(b.length-a.length)*0.5 end
-- Vrai quand le nez de a est derrière celui de b de plus de K.cornerNoseMargin m : a n'a pas la priorité au virage.
function M.behind(a,b,long) return M.nose(a,b,long)>K.cornerNoseMargin end
-- Vrai en virage ou en vrai freinage (K.passBrakeMax), faux en ligne droite. ownBrake : pédale de frein de la voiture
-- (0 à 1) ; p : réglages effectifs (p.cornerMin).
function M.cornerContext(a,p,ownBrake) return a.corner<p.cornerMin or (ownBrake or 0)>=K.passBrakeMax end
-- Engagement de l'attaquant i sur la voiture j, du côté side : gardé pour la tentative (l'heure du premier engagement
-- sur la même voiture n'est pas réécrite).
function M.commit(e,i,j,side,now)
 local s=e.states[i]
 if s.committed~=j then s.committed=j; s.commitAt=now end
 s.commitSide=side or 0
end
-- Fin de la tentative de i ; le défenseur qui gardait sa ligne pour lui est libéré aussi.
function M.release(e,i)
 local s=e.states[i]; local j=s.committed or 0
 if j>0 then local t=e.states[j]; if t and t.heldBy==i then t.heldBy=0; t.heldUntil=0 end end
 s.committed=0; s.commitSide=0
end
function M.committed(s,j) return (s.committed or 0)>0 and (j==nil or s.committed==j) end
-- Le défenseur j garde sa ligne pour l'attaquant i jusqu'à untilTime (rafraîchi tant que i reste engagé).
function M.hold(e,j,i,untilTime) local t=e.states[j]; t.heldBy=i; t.heldUntil=untilTime end
-- Indice de l'attaquant pour qui la voiture garde sa ligne à cette heure, 0 sinon.
function M.held(s,now) return (s.heldBy or 0)>0 and now<(s.heldUntil or 0) and s.heldBy or 0 end
-- Recalage de l'horloge (src/engine.lua, M.rebase) : heures des champs partagés.
function M.rebase(s,amount)
 if s.commitAt then s.commitAt=s.commitAt-amount end
 if s.heldUntil and s.heldUntil>0 then s.heldUntil=s.heldUntil-amount end
end
return M
