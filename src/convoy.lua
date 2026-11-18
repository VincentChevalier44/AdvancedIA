-- Beta 2.0.4 (pilote, Monza, 18 novembre 11:47 ; décisions du pilote du 18 novembre : « file stricte », pour les deux
-- départs). Tour de formation en file stricte.
--
-- Ce que montre le replay : les IA rattrapent la file à plus de 200 km/h (la tête à 120) ; la file du pilotage et le
-- radar avant ne voient que la voiture devant DANS LEUR COULOIR : pendant le zigzag, la voiture de devant est sur le côté,
-- la suivante arrive à sa hauteur (P3 à 4 m derrière P2, P6 à côté de P4), puis les zigzags se croisent : accrochage,
-- tête-à-queue. Sur le chemin de la grille, le peloton arrivait en désordre et côte à côte à 125 km/h : colonnes qui se
-- croisent, voiture arrêtée à sa place devant une voiture dont la place est plus loin (« touche l'arrière »).
--
-- Règle (une seule, quelle que soit la position latérale) : pendant le tour de formation, une IA ne s'approche jamais à
-- moins de CK.gap m (pare-chocs) de la voiture qui la précède SUR LA PISTE. Plafond d'allure : celle de la voiture de
-- devant, plus ce qui se freine encore à CK.decel m/s² sur la distance libre (temps de réaction CK.react s compris) :
-- l'IA suit ce plafond comme toute limite d'allure (aucune vague de freinages commandés dans la file). Freinage commandé
-- seulement en dernier recours : au-dessus du plafond ET à moins de CK.panic s de la distance de garde à la vitesse de
-- rapprochement du moment ; ou plafond presque nul (voiture de devant arrêtée tout près). L'ordre de la grille est donc gardé pendant tout le tour, personne n'est
-- jamais à côté d'une autre voiture (zigzags, freinages de chauffe et burnouts restent permis derrière).
--
-- Jamais pendant l'appel des deux files du départ lancé (paires côte à côte voulues : src/director.lua, inchangé). Sur
-- la grille : une voiture déjà tenue à sa place ne compte que si elle est dans le couloir de l'IA (les deux colonnes se
-- longent) ; à moins de CK.gridFree m de sa propre place, toutes les voitures sont jugées ainsi. Dans ces deux cas la
-- garde tombe à CK.gridGap m : les places d'une même colonne peuvent être plus proches que CK.gap m (grille en une seule
-- file), l'IA doit pouvoir rejoindre la sienne ; l'approche de sa place la freine déjà (src/grid.lua).
-- Jamais comptées devant : voiture en incident, retenue, garée hors piste, hors piste, aux stands.
local U=require('src/util')
local K=require('src/config').K
local Grid=require('src/grid')
local M={}
-- 2.0.4 (pilote, Monza, 18 novembre 13:33 : à la première chicane la file s'est tassée jusqu'à l'arrêt, quatre voitures à
-- 0 km/h pendant 2 s, une touchette à 12 km/h d'écart) : en deçà de la garde, l'IA ne roule que CK.closeRate m/s par mètre
-- manquant moins vite que la voiture de devant (0,25 ; 1 avant : dans une file qui se resserre au freinage, chaque voiture
-- roulait 4 m/s moins vite que la précédente, la cinquième était à l'arrêt). Essayé puis retiré le même jour : anticiper
-- le freinage de la voiture de devant (au banc : vagues de freinages commandés et contacts en plus).
local CK={gap=6,gridGap=1.5,decel=4,react=0.25,range=300,closeRate=0.25,brakeMargin=3,brakeScale=20,brakeMin=0.15,sideLat=0.8,gridFree=60,panic=1,gapMin=2,gapTime=0.5,
 stopKmh=3,nearGap=2,auditKmh=30}
M.CK=CK
function M.new() return {active=false,lap=false,near=0,nearOn={},closest=math.huge} end
-- Garde (m) à la vitesse v (m/s) : CK.gap en roulant, réduite à basse vitesse (CK.gapMin m à l'arrêt, plus CK.gapTime s
-- de la vitesse) : au départ de la grille, les voitures sont à moins de CK.gap m les unes des autres et doivent pouvoir
-- s'élancer derrière celle de devant sans être retenues au frein.
function M.guard(v,gap)
 gap=gap or CK.gap
 return math.min(gap,CK.gapMin+(v or 0)*CK.gapTime)
end
-- Plafond d'allure (m/s) derrière une voiture à vp m/s, bumper m devant (pare-chocs), à v m/s ; garde gap m (CK.gap).
function M.cap(vp,bumper,v,gap)
 gap=M.guard(v,gap)
 local room=bumper-gap-v*CK.react
 if room>0 then return math.sqrt(vp*vp+2*CK.decel*room) end
 return math.max(0,vp-CK.closeRate*math.max(0,gap-bumper))
end
local function counted(inc,b,j)
 if not (b.valid and not b.pit and b.splineValid and not b.offtrack) then return false end
 local c=inc.cars and inc.cars[j]
 return not (c and (c.incident or c.holding or c.parked or c.abortHold))
end
-- Voiture qui précède l'IA i sur la piste (la plus proche devant, à CK.range m au plus) et distance centre à centre.
function M.ahead(e,frame,i,grid)
 local a=frame.cars[i]; local inc=e.incidents; local g=e.grid
 local own=grid and g and (g.slotOf[i] or 0)>0 and Grid.gap(g,frame,i) or math.huge
 local best,bestLong,tight=nil,CK.range,false
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=i and counted(inc,b,j) then
   local long=U.spline(b.spline-a.spline)*frame.length
   if long>0 and long<bestLong then
    local ok=true; local corridor=grid and (own<=CK.gridFree or g and g.held[j]) or false
    -- Grille : voiture tenue à sa place, ou IA près de sa propre place : seulement dans le couloir de l'IA.
    if corridor then
     local dx,dz=b.x-a.x,b.z-a.z
     ok=math.abs(dx*(-a.lz)+dz*a.lx)<((a.width or K.width)+(b.width or K.width))*0.5+CK.sideLat
    end
    if ok then best=j; bestLong=long; tight=corridor end
   end
  end
 end
 return best,bestLong,tight
end
local function report(t,e,now)
 if not t.lap then return end
 t.lap=false
 U.log(e.log,now,'INFO',string.format('tour de formation: file stricte, %d rapprochement(s) a moins de %d m de la voiture de devant, plus petit ecart %.1f m',t.near,CK.nearGap,t.closest<math.huge and t.closest or 0),-1)
end
function M.step(e,frame,now)
 local t=e.convoy; if not t then t=M.new(); e.convoy=t end
 local inc=e.incidents; local g=e.grid
 local grid=inc.standing=='grid' or inc.standing=='lights'
 local lap=inc.formation==true and not (inc.rollCall==true and K.rollPairs)
 local on=e.profile=='C' and not frame.online and not frame.replay and (lap or grid) and (frame.length or 0)>0
 if lap and not t.lap then t.lap=true; t.near=0; t.closest=math.huge; for i=1,K.maxCars do t.nearOn[i]=false end
 elseif not lap and t.lap then report(t,e,now) end
 t.active=on
 if not on then return end
 for i=1,frame.count do
  local a=frame.cars[i]; local c=inc.cars and inc.cars[i]
  if a.valid and a.control and not a.player and not a.pit and not a.finished and not a.safetyCar and a.splineValid and not a.offtrack
   and not (grid and g and g.held[i]) and not (c and (c.incident or c.holding)) then
   local j,long,tight=M.ahead(e,frame,i,grid)
   if j then
    local b=frame.cars[j]
    local bumper=long-((a.length or K.length)+(b.length or K.length))*0.5
    local vp=b.speed or 0
    local kmh=M.cap(vp,bumper,a.speed or 0,tight and CK.gridGap or CK.gap)*3.6
    local cmd=e.commands[i]
    cmd.speedLimit=math.min(cmd.speedLimit or K.unlimitedSpeed,math.max(kmh,K.gridCrawlKmh))
    local closing=(a.speed or 0)-vp
    if kmh<CK.stopKmh then cmd.brake=math.max(cmd.brake or 0,K.brakeMax)
    elseif a.kmh>kmh+CK.brakeMargin and closing>0 and bumper-M.guard(a.speed or 0,tight and CK.gridGap or CK.gap)<closing*CK.panic then
     cmd.brake=math.max(cmd.brake or 0,U.clamp((a.kmh-kmh)/CK.brakeScale,CK.brakeMin,K.brakeMax))
    end
    -- Audit (tour de formation seulement) : passages à moins de CK.nearGap m, plus petit écart.
    if lap and not grid and a.kmh>CK.auditKmh and not b.player then
     if bumper<t.closest then t.closest=bumper end
     if bumper<CK.nearGap then if not t.nearOn[i] then t.nearOn[i]=true; t.near=t.near+1 end else t.nearOn[i]=false end
    end
   end
  end
 end
end
return M
