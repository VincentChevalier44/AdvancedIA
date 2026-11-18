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
local abs=math.abs
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
-- Beta 1.64, lot 1 (référentiel des comportements pilotes, 08-01 à 08-06 et 08-13 ; décision du pilote du 13 novembre :
-- repères F1 pour toutes les catégories) : résultat de duel partagé par la priorité au virage (src/director.lua) et la
-- responsabilité des contacts (src/blame.lua). Droit à l'espace de chaque voiture : 'oui', 'non' ou 'incertain'.
--   Intérieur : essieu avant au moins au niveau du rétroviseur de la voiture extérieure ;
--   extérieur : essieu avant devant celui de la voiture intérieure.
-- Repère commun : axe moyen des deux caps ; essieux et rétroviseurs (a.axleFront, a.mirror, m le long du cap depuis la
-- position de la voiture, src/snapshot.lua) ; le rétroviseur est une estimation déclarée. Dans la bande K.duelTolerance :
-- 'incertain' (les deux gardent leur ligne). Voiture hors piste : 'non'. Sens du virage (turn : côté du centre du virage
-- dans le repère latéral de a, 1 ou -1 ; 0 inconnu) : donné par la piste devant, sinon par le lacet des deux voitures.
-- Géométrie ou sens inconnus : règle du nez de la Beta 1.59 (out.mode='nez'), à l'identique.
local function grade(v) if v>=K.duelTolerance then return 'oui' elseif v<=-K.duelTolerance then return 'non' end return 'incertain' end
function M.duel(a,b,long,lat,turn,out)
 local nose=M.nose(a,b,long)
 out.mode='nez'; out.inside=0
 if nose>K.cornerNoseMargin then out.a='non'; out.b='oui' elseif nose<-K.cornerNoseMargin then out.a='oui'; out.b='non' else out.a='incertain'; out.b='incertain' end
 if not K.duelAxles or not a.axleKnown or not b.axleKnown then return out end
 if turn==0 then
  local ys=(a.yawRate or 0)+(b.yawRate or 0)
  if abs(ys)<K.duelYawMin then return out end
  turn=ys>0 and -1 or 1
 end
 local tx,tz=a.lx+b.lx,a.lz+b.lz; local n=math.sqrt(tx*tx+tz*tz)
 if n<1 then return out end
 local d=((b.x-a.x)*tx+(b.z-a.z)*tz)/n
 local aF,bF=a.axleFront,d+b.axleFront
 if lat*turn>0 then out.inside=2; out.b=grade(bF-(a.mirror)); out.a=grade(aF-bF)
 else out.inside=1; out.a=grade(aF-(d+b.mirror)); out.b=grade(bF-aF) end
 if a.offtrack then out.a='non' end
 if b.offtrack then out.b='non' end
 out.mode='axes'
 return out
end
-- Vrai quand a doit laisser le virage à b d'après le duel.
function M.yields(out) return out.a=='non' and out.b=='oui' end
-- Affinage 1.64 (Monza, session 7 du 13 novembre : 16 cessions « sans droit a l espace », dépassements en course 9 -> 2,
-- côte à côte 102 s -> 55 s ; des paires se cédaient l'une à l'autre d'un virage à l'autre) : le droit à l'espace (jugement
-- des contacts) n'est pas le geste de pilotage. Lever le pied et quitter l'attaque : règle du nez de la Beta 1.59 (nez
-- derrière de plus de K.cornerNoseMargin m), ou voiture INTÉRIEURE sans droit face à une voiture qui l'a (elle ne force
-- pas le virage). Voiture extérieure sans droit : garde sa ligne sans lever le pied (écart figé, jamais vers l'autre),
-- comme en 1.63. Renvoie vrai et la raison ('nez' ou 'interieur').
function M.gives(out,a,b,long)
 if M.nose(a,b,long)>K.cornerNoseMargin then return true,'nez' end
 if out.mode=='axes' and out.inside==1 and M.yields(out) then return true,'interieur' end
 return false,nil
end
-- Duel enregistré par l'IA i avec la voiture j à l'entrée du virage (avant la corde) : deux emplacements par voiture,
-- alloués une fois (trois de front), repérés par l'indice et l'identité de l'autre voiture.
local function slot(s,j,id)
 local r1,r2=s.duelRec1,s.duelRec2
 if not r1 then r1={other=0,id='',at=-math.huge,mine='',theirs='',mode=''}; r2={other=0,id='',at=-math.huge,mine='',theirs='',mode=''}; s.duelRec1=r1; s.duelRec2=r2 end
 if r1.other==j and r1.id==id then return r1 end
 if r2.other==j and r2.id==id then return r2 end
 return r1.at<=r2.at and r1 or r2
end
function M.record(s,j,id,out,now)
 local r=slot(s,j,id or '')
 r.other=j; r.id=id or ''; r.at=now; r.mine=out.a; r.theirs=out.b; r.mode=out.mode
end
-- Duel enregistré entre i et j depuis au plus K.duelRecordKeep s : droit de i, droit de j, mode ; nil sans duel.
local function find(s,j,id,now)
 if not s then return nil end
 for k=1,2 do
  local r=k==1 and s.duelRec1 or s.duelRec2
  if r and r.other==j and r.id==id and now-r.at<=K.duelRecordKeep and now>=r.at then return r end
 end
 return nil
end
function M.recorded(e,frame,i,j,now)
 local idI,idJ=frame.cars[i].identity or frame.cars[i].id or '',frame.cars[j].identity or frame.cars[j].id or ''
 local ri,rj=find(e.states[i],j,idJ,now),find(e.states[j],i,idI,now)
 -- Le plus récent des deux points de vue.
 if ri and (not rj or ri.at>=rj.at) then return ri.mine,ri.theirs,ri.mode end
 if rj then return rj.theirs,rj.mine,rj.mode end
 return nil
end
-- Recalage de l'horloge (src/engine.lua, M.rebase) : heures des champs partagés.
function M.rebase(s,amount)
 if s.commitAt then s.commitAt=s.commitAt-amount end
 -- Relecture 2.0.4 (E1) : dernière vue de l'engagement du joueur (src/director.lua, ps.commitSeen) décalée aussi.
 if s.commitSeen then s.commitSeen=s.commitSeen-amount end
 if s.heldUntil and s.heldUntil>0 then s.heldUntil=s.heldUntil-amount end
 if s.duelRec1 then s.duelRec1.at=s.duelRec1.at-amount; s.duelRec2.at=s.duelRec2.at-amount end
end
return M
