-- Départ arrêté après un drapeau rouge (Beta 1.34) : décisions pures, aucune écriture (commandes lues par l'applicateur).
-- Après le tour de relance derrière la voiture de sécurité (ou sous VSC/FCY, fini quand le meneur boucle son tour),
-- chaque voiture en piste rejoint sa place de grille en roulant, dans l'ordre du classement, places resserrées ;
-- jamais de déplacement forcé (tours exacts).
-- - formation (« grid ») : allure plafonnée selon la distance à la place (mesurée vers l'avant, Beta 1.35 : une voiture
--   loin de sa place la rejoint en roulant, jamais arrêtée en pleine piste), freinage d'appoint sur les derniers mètres,
--   colonne de la place, puis retenue par impulsions du compteur d'arrêt natif ; une IA juste au-delà de sa place (moins
--   de K.gridOvershoot m) est retenue là où elle est (jamais de marche arrière) ; une IA aux stands n'y reçoit aucune
--   commande (aucune écriture aux stands) : elle attend à son emplacement ou, sortie pendant la formation, est retenue au
--   pas là où elle rejoint la piste (départ depuis la voie des stands) ;
-- - feux (« lights ») : grille complète (IA en place, recomptées à chaque image ; joueur à sa place ou aux stands) ou
--   délai maximal écoulé ; un feu par K.lightStep s, puis extinction après un délai tiré de la graine (reproductible) ;
--   faux départ du joueur surveillé seulement une fois en place et à l'arrêt (vers l'avant), jamais au départ des stands ;
-- - départ (« go ») : toutes les retenues levées ensemble, IA réveillées dans la colonne de leur place, drapeau vert ;
--   dépassement permis aussitôt la ligne franchie (elle est juste devant la grille).
-- Nouvel incident pendant la formation ou les feux : départ annulé, retenues levées, les drapeaux jaunes habituels
-- prennent le relais (dépassement toujours interdit jusqu'à la ligne).
local U=require('src/util')
local K=require('src/config').K
local Antics=require('src/antics')
local max=math.max
local M={}
-- Correctif 1.63 (Montréal, 12 novembre : toute la grille « ramenee aux stands par AC (a l arret depuis 12 s) », le
-- joueur seul sur la grille) : AC renvoie à son stand une IA immobile depuis environ 12 s. Aucune IA ne reste donc
-- immobile plus de GK.stillMax s avant l'extinction : les feux s'allument au plus tard GK.stillMax - (séquence des
-- feux) - GK.lightsMargin s après la première IA immobilisée (joueur en place ou non : il est jugé comme d'habitude), et
-- l'extinction ne dépasse jamais GK.stillMax s après elle. Tant que des voitures sont encore loin de leur place (plus de
-- GK.creepSpread m), une IA qui arrive près de la sienne (GK.creepZone m) s'en approche au pas (GK.creepKmh km/h) au lieu
-- de s'y arrêter tôt.
local GK={stillMax=10,lightsMargin=0.5,creepZone=25,creepKmh=5,creepSpread=25,stillMaxGuarded=40,waitFirstGuarded=30,
 -- Affinage 1.63 (Imola, 13 novembre : « feux apres 61 s de grille, premiere IA immobile depuis 30.0 s (8 / 22 IA en
 -- place) » : avec la protection, la première IA n'était retenue qu'après 31 s, toute la file avançant au pas derrière
 -- les IA déjà près de leur place) : protection active (M.retireGuard), plus d'approche au pas ni de feux à la limite
 -- d'immobilité ; les feux attendent toutes les IA, au plus stallGuarded s sans nouvelle arrivée ou fillGuarded s
 -- après la première en place (le délai maximal K.gridMax reste). Aux feux, IA pas en place : une ligne (missMax noms).
 stallGuarded=20,fillGuarded=60,missMax=6,fillTarget=20,
 -- Avec la protection : approche plus vive (approachKmh au plus, freinage prévu à approachDecel m/s²) : la file, encore
 -- à 500 m de la ligne quand la grille commence (K.gridFormFrom), rejoint ses places sans traîner.
 approachKmh=120,approachDecel=2.5,
 -- Arrêt de la progression : aucune arrivée ET aucune IA attendue au-dessus de movingKmh depuis stallGuarded s.
 movingKmh=3,
 -- 2.0.4 : arrêt avant la place (plus de K.gridHoldDistance m) tenu en place après shortStill s immobile seulement.
 shortStill=1.5,
 -- 2.0.4 : vitesse au plus du décalage de colonne (fraction de la demi-largeur par seconde, environ 1 m/s).
 columnRate=0.15,
 -- 2.0.4 (décision du pilote du 18 novembre : « recaler ») : IA arrêtée à sa place depuis snapStill s (moins de snapKmh
 -- km/h), à moins de snapMax m et snapAngle degrés de la pose relevée au feu vert, aucune autre voiture à moins de
 -- snapClear m de cette pose : reposée exactement sur sa place (une fois par grille, avant les feux).
 -- Essai du pilote du 18 novembre à 13:05 : 20 IA reposées à 2 cm près ; la dernière, arrêtée à 3,3 m de sa place (un
 -- écart sur le côté dans les derniers mètres), n'était pas reposée (snapMax valait 2,5 m) : snapMax porté à 4 m.
 snapStill=0.5,snapKmh=0.5,snapMax=4,snapAngle=25,snapClear=3.5,
 -- 2.0.4 (pilote, Monza, 18 novembre 11:47 : 17 IA reposées à l'envers, 0,46 m devant leur place : la fonction de CSP
 -- attend la direction opposée au cap lu, et pose un point de la voiture 0,465 m devant la position lue) : pose vérifiée
 -- snapCheck s après chaque écriture (cap et position relus sur la voiture) ; à l'envers, ou à plus de snapTol m : sens
 -- et décalage corrigés d'après l'écart mesuré, nouvelle écriture (snapTries au plus par voiture). Les feux attendent la
 -- fin des vérifications, snapWait s au plus. snapDir et snapFwd : convention de départ ; décalage appris en jeu le
 -- 18 novembre à 13:05 (-0,49 m après une correction sur la première voiture, écart restant 0,02 m au plus).
 snapCheck=0.4,snapTol=0.05,snapTries=3,snapWait=4,snapDir=-1,snapFwd=-0.49,
 -- 2.0.4 (décision du pilote du 18 novembre) : voiture à plus de lateGap m du peloton quand la grille se forme : elle
 -- perd sa place (arrière de la grille) et n'est pas attendue.
 lateGap=500,
 -- 2.0.4 (pilote, Monza, 18 novembre 13:33 : « elles arrivent mal positionnées et on les repositionne après, ça ne
 -- fait pas réel » ; replay : toutes arrêtées 1 à 1,5 m avant leur place, six tournées de 10 à 17 degrés dans les 10
 -- derniers mètres) : avec la pose relevée au feu vert, l'IA roule jusqu'à sa pose : distance mesurée le long du cap de
 -- la pose (si elle s'accorde à poseTrust m près avec celle de la piste), tenue en place à poseStop m (la distance
 -- qu'elle parcourt encore en s'arrêtant du pas).
 poseStop=0.3,poseTrust=5,
 -- 2.0.4 : distance (m, le long de la piste) au nœud AC_START au-delà de laquelle une voiture n'est sur aucune place.
 nodeRadius=3}
M.GK=GK
-- Affinage 1.63 (Bakou, 13 novembre : les cinq premières IA « ramenee aux stands par AC (a l arret depuis 5 a 7 s) »,
-- feux allumés avec 9 / 22 IA en place) : le compteur d'AC part dès l'approche au pas, bien avant l'arrêt. Toute IA de la
-- grille (en approche, en place, ou partant des stands) porte cmd.noRetire pendant la grille et les feux : l'applicateur
-- appelle alors à chaque image physics.preventAIFromRetiring (CSP : « If not moving, they will still retire some time
-- after this function is called, unless you'll keep calling it »), la protection prévue par CSP contre ce renvoi.
-- Quand l'applicateur la sait disponible (M.retireGuard, posé par lui), la grille attend toutes les IA (au plus
-- GK.waitFirstGuarded s après la première en place, extinction au plus GK.stillMaxGuarded s après elle) ; sinon, la
-- borne de temps de la 1.63 (GK.stillMax) reste la seule défense.
M.retireGuard=false
local function stillMax() return M.retireGuard and GK.stillMaxGuarded or GK.stillMax end
function M.new()
 return {phase='none',slots={},slotOf={},held={},pit={},order={},source='',since=0,lightsAt=0,outAt=0,goUntil=-math.huge,
  ref=0,refSet=false,jump=false,count=0,heldCount=0,nodes=nil,timedOut=false,woke=false,aiRef={},aiJump={},aiJumpAt={},
  -- Beta 1.61 (tranche D, réglage startRealism : g.realism posé par src/antics.lua) : grade du faux départ du joueur
  -- (g.jumpGrade : creep, jump, flagrant), avance, vitesse et avance en temps relevées, place sur la grille ; IA qui
  -- vole le départ (g.aiRelease[i] : retenue levée tant de secondes avant l'extinction) et grade des IA.
  aiRelease={},aiReleased={},aiJumpGrade={},realism=false,jumpMoved=0,jumpKmh=0,jumpLead=0,jumpSlot=0,
  -- Correctif 1.61 (Spa, 11 novembre) : heure de retenue de chaque IA, IA ramenée aux stands par AC pendant la grille,
  -- première retenue (attente bornée avant les feux).
  heldAt={},lost={},firstHeldAt=nil,burstDone={},burstUntil={},
  -- Beta 1.64 (lot 2) : origine d'une grille de l'app ('start' : fin du tour de formation, 'red' : relance) ; '' : posée
  -- à la main (départ avorté traité comme avant).
  from='',
  -- Relecture 1.64 (lot 2) : IA tenue à sa place et heurtée pendant la grille ou les feux (victime, jamais marquée).
  hit={},
  -- Beta 2.0.4 : incident hors de la grille déjà noté (heure de l'incident), départ maintenu ; décalage tenu à l'arrivée
  -- sur la place (écart réel, la voiture ne braque plus).
  kept={},frozen={},shortAt={}}
end
local function clearCars(g) g.frozen=g.frozen or {}; g.shortAt=g.shortAt or {}; g.ramp=g.ramp or {}; g.snapped=g.snapped or {}; g.stillAt=g.stillAt or {}; g.snapAt=g.snapAt or {}; g.snapTry=g.snapTry or {}; g.snapOff=g.snapOff or {}; g.late=g.late or {}; for i=1,K.maxCars do g.ramp[i]=nil; g.snapped[i]=nil; g.stillAt[i]=nil; g.snapAt[i]=nil; g.snapTry[i]=nil; g.late[i]=nil end; g.snapN=0; g.snapSum=0; g.snapMoves=0; g.snapMaxD=0; g.snapMaxA=0; g.snapFixes=0; g.snapLeft=0; g.snapBusy=false; for i=1,K.maxCars do g.frozen[i]=nil; g.shortAt[i]=nil; g.slotOf[i]=0; g.held[i]=false; g.pit[i]=false; g.aiRef[i]=nil; g.aiJumpAt[i]=nil; g.aiRelease[i]=nil; g.aiReleased[i]=nil; g.heldAt[i]=nil; g.lost[i]=nil; g.burstDone[i]=nil; g.burstUntil[i]=nil end; g.firstHeldAt=nil; g.lastHeldAt=nil; g.aiReadyAt=nil end
local function clearPlayer(t) t.gridPlaced=false; t.gridPassed=false end
function M.reset(g)
 g.guardLogged=false; g.phase='none'; g.source=''; g.since=0; g.lightsAt=0; g.outAt=0; g.goUntil=-math.huge; g.ref=0; g.refSet=false; g.jump=false
 g.count=0; g.heldCount=0; g.timedOut=false; g.movingAt=nil; clearCars(g)
 for i=1,K.maxCars do g.aiJump[i]=nil; g.aiJumpAt[i]=nil end
 for i=1,K.maxCars do g.aiJumpGrade[i]=nil end
 g.jumpGrade=nil; g.jumpMoved=0; g.jumpKmh=0; g.jumpLead=0; g.jumpSlot=0; g.jumpLaunchAt=nil
 g.from=''
end
function M.rebase(g,amount)
 g.since=g.since-amount; g.lightsAt=g.lightsAt-amount; g.outAt=g.outAt-amount
 if U.finite(g.goUntil) then g.goUntil=g.goUntil-amount end
 -- Relecture 1.52 : début du mouvement d'une IA avant l'extinction (faux départ) décalé aussi.
 for i=1,K.maxCars do if g.aiJumpAt[i] then g.aiJumpAt[i]=g.aiJumpAt[i]-amount end end
 -- Correctif 1.61 : heures de retenue et de coup d'accélérateur décalées aussi.
 if g.firstHeldAt then g.firstHeldAt=g.firstHeldAt-amount end
 if g.lastHeldAt then g.lastHeldAt=g.lastHeldAt-amount end
 if g.aiReadyAt then g.aiReadyAt=g.aiReadyAt-amount end
 if g.movingAt then g.movingAt=g.movingAt-amount end
 for i=1,K.maxCars do if g.heldAt[i] then g.heldAt[i]=g.heldAt[i]-amount end; if g.burstUntil[i] then g.burstUntil[i]=g.burstUntil[i]-amount end end
end
-- Ordre du classement de la course (positions inconnues à la fin, départage par indice) : un seul comparateur, sans
-- fermeture créée à chaque tri (aussi pour la sortie des stands après un drapeau rouge).
local sortCars
local function byPosition(x,y)
 local px,py=sortCars[x].position or 0,sortCars[y].position or 0
 if px<1 then px=math.huge end; if py<1 then py=math.huge end
 if px~=py then return px<py end
 return x<y
end
local sortRank
local function byRank(x,y)
 local rx,ry=sortRank[x],sortRank[y]
 if rx and ry then return rx<ry end
 if rx or ry then return rx~=nil end
 return byPosition(x,y)
end
function M.sortByRank(list,n,cars,rank)
 for k=#list,n+1,-1 do list[k]=nil end
 sortCars=cars; sortRank=rank; table.sort(list,byRank); sortCars=nil; sortRank=nil
end
function M.sortByPosition(list,n,cars)
 for k=#list,n+1,-1 do list[k]=nil end
 sortCars=cars; table.sort(list,byPosition); sortCars=nil
end
-- Places de la grille : nœuds AC_START du circuit (lus par l'applicateur : abscisse sur la piste et position latérale
-- normalisée, +1 à droite) s'ils sont cohérents pour les voitures à placer (à moins de K.gridNodeRange m avant la ligne
-- ou de K.gridNodeAfter m après elle, chacun derrière le précédent ou à sa hauteur, latéral connu) ; sinon calculées :
-- première place à K.gridFirst m de la ligne, K.gridPitch m entre deux places, colonnes alternées. Les places sont copiées
-- (les nœuds du circuit, gardés pour les relances suivantes, ne sont jamais modifiés). Renvoie la liste, sa source et,
-- places calculées, la raison ; nil sans longueur de piste.
-- Correctif 1.61 (Spa, 11 novembre : « noeud 1 incoherent », grille calculée devant la vraie grille) : une grille après
-- la ligne (Spa) est acceptée, et un emplacement un peu au-delà de la largeur de la trajectoire de l'IA (ligne des
-- stands plus large) est ramené à K.gridLatClamp au lieu de rejeter toute la grille ; la raison du refus est précisée.
-- Distance signée d'une abscisse avant la ligne (m) : positive avant la ligne, négative après.
function M.before(spline,length)
 local d=((-spline)%1)*length
 if d>length*0.5 then d=d-length end
 return d
end
local function refused(k,before,lat,last)
 if not before then return string.format('noeud %d incoherent : abscisse inconnue',k) end
 if before>K.gridNodeRange then return string.format('noeud %d incoherent : %.0f m avant la ligne',k,before) end
 if before<-K.gridNodeAfter then return string.format('noeud %d incoherent : %.0f m apres la ligne',k,-before) end
 if before<last-K.gridSideBySide then return string.format('noeud %d incoherent : devant le precedent',k) end
 return string.format('noeud %d incoherent : lateral %s',k,U.finite(lat) and string.format('%.2f',lat) or 'inconnu')
end
function M.resolve(nodes,length,count,out)
 if not U.finite(length) or length<=0 or count<1 then return nil,'','' end
 out=out or {}
 local why='aucun noeud'
 if type(nodes)=='table' and #nodes>=count then
  local good=true; local last=-math.huge
  for k=1,count do
   local n=nodes[k]; local before=U.finite(n.spline) and M.before(n.spline,length) or nil
   if not (before and before<=K.gridNodeRange and before>=-K.gridNodeAfter and before>=last-K.gridSideBySide and U.finite(n.lateral) and math.abs(n.lateral)<=K.gridNodeLatMax) then
    good=false; why=refused(k,before,n.lateral,last); break
   end
   last=math.max(last,before)
  end
  if good then
   for k=1,count do local s=out[k] or {}; out[k]=s; s.spline=nodes[k].spline; s.lateral=U.clamp(nodes[k].lateral,-K.gridLatClamp,K.gridLatClamp) end
   for k=#out,count+1,-1 do out[k]=nil end
   return out,'AC_START',''
  end
 elseif type(nodes)=='table' then why=string.format('%d noeuds pour %d voitures',#nodes,count) end
 for k=1,count do
  local s=out[k] or {}; out[k]=s
  s.spline=((-(K.gridFirst+(k-1)*K.gridPitch))/length)%1; s.lateral=k%2==1 and -K.gridColumn or K.gridColumn
 end
 for k=#out,count+1,-1 do out[k]=nil end
 return out,'calculees',why
end
-- Correctif 1.63 (règlement) puis Beta 1.64 (lot 2) : voiture retardée (incident pendant le tour de formation, bySince ;
-- ou voiture à l'origine d'un départ avorté, toujours) doublée par une voiture partie derrière elle : arrière de la grille.
local function toBack(g,t,frame,order,n,rank,bySince,now,log)
 local back=g.back or {}; g.back=back; local nb=0; local keep=0
 for k=1,n do
  local i=order[k]; local ri=rank[i]; local pi=frame.cars[i].position or 0; local lost=false
  local ci=t.cars and t.cars[i]; local delayed=ci~=nil and (ci.abortMark or bySince and (ci.since or 0)~=0 and (ci.since or 0)>=(t.formationAt or math.huge))
  if ri and pi>=1 and delayed then
   for m=1,n do local j=order[m]; local rj=rank[j]; local pj=frame.cars[j].position or 0; if rj and rj>ri and pj>=1 and pj<pi and (ci.abortMark or not frame.cars[j].player) then lost=true; break end end
  end
  if lost then nb=nb+1; back[nb]=i else keep=keep+1; order[keep]=i end
 end
 for m=1,nb do local i=back[m]; order[keep+m]=i; U.log(log,now,'INFO',string.format('grille: %s part de l arriere de la grille (%s)',frame.cars[i].name,t.cars[i].abortMark and 'depart avorte' or 'place perdue pendant le tour de formation'),i) end
 g.backN=nb
end
-- Relecture 1.64 (lot 2) : relance après un drapeau rouge : voitures renvoyées à l'arrière de la grille aussi à la fin de
-- l'ordre figé (rangs renumérotés, mêmes voitures, voitures aux stands comprises) : ni « reprend sa place » ni place du
-- joueur fausses jusqu'à l'extinction.
local function redBack(t,back,nb)
 local N=t.redOrderN or 0; local k=0
 for r=1,N do
  local i=t.redOrder[r]; local out=false
  for m=1,nb do if back[m]==i then out=true; break end end
  if i and not out then k=k+1; t.redOrder[k]=i end
 end
 for m=1,nb do local i=back[m]; if t.redRank[i] then k=k+1; t.redOrder[k]=i end end
 for r=1,k do t.redRank[t.redOrder[r]]=r end
end
-- 2.0.4 (pilote, Monza, 18 novembre 09:45 : joueur dans la voie des stands à la fin du tour de formation, les 9 IA
-- placées derrière lui avancées d'une place, chacune dans l'autre colonne, certaines pas arrivées aux feux) ; décision du
-- pilote du 18 novembre (« cases vides partout ») : après un tour de formation, chaque voiture reprend SA place (node[i] :
-- nœud AC_START relevé au feu vert du tour, M.nodeRanks) ; la place d'une voiture partie dans la voie des stands reste
-- vide ; une voiture qui a perdu sa place (toBack) se place derrière la dernière place occupée au départ. Renvoie le
-- nombre de places à préparer, ou nil (place absente ou en double, pas assez de nœuds AC_START) : places dans l'ordre,
-- comme avant.
function M.fixedSlots(g,order,n,node,back)
 if type(node)~='table' then return nil end
 local keep=n-(back or 0); local top=0; local used=g.used or {}; g.used=used
 for k in pairs(used) do used[k]=nil end
 for _,r in pairs(node) do if type(r)=='number' and r>top then top=r end end
 for k=1,keep do
  local r=node[order[k]]
  if type(r)~='number' or r<1 or r~=math.floor(r) or used[r] then return nil end
  used[r]=true
 end
 local total=top+(back or 0)
 if total<n or type(g.nodes)=='table' and #g.nodes<total and #g.nodes>=n then return nil end
 local slotOf=g.fixed or {}; g.fixed=slotOf
 for k=1,keep do slotOf[k]=node[order[k]] end
 for m=1,(back or 0) do slotOf[keep+m]=top+m end
 for k=#slotOf,n+1,-1 do slotOf[k]=nil end
 return total
end
-- 2.0.4 (pilote, Monza, 18 novembre 10:34 : le classement d'AC au feu vert du tour de formation compte une voiture de plus
-- que la grille : toutes les IA une place derrière la leur) : place de chaque voiture classée (rank) lue sur la grille :
-- nœud AC_START le plus proche le long de la piste (à moins de GK.nodeRadius m), entre deux nœuds côte à côte (moins de
-- K.gridSideBySide m d'écart) celui du côté de la voiture. Renvoie node (rempli) ou nil : nœuds absents, voiture sur
-- aucun nœud, deux voitures sur le même nœud.
function M.nodeRanks(nodes,frame,rank,offsetSign,out)
 if type(nodes)~='table' or #nodes==0 or not frame or not U.finite(frame.length) or frame.length<=0 or type(rank)~='table' then return nil end
 out=out or {}; for k in pairs(out) do out[k]=nil end
 local taken={}; local any=false
 for i in pairs(rank) do
  local a=frame.cars[i]
  if not a or not a.splineValid then return nil end
  local best,bestD=nil,math.huge
  for k=1,#nodes do
   local d=math.abs(U.spline(a.spline-nodes[k].spline))*frame.length
   if d<bestD-K.gridSideBySide then best=k; bestD=d
   elseif d<bestD+K.gridSideBySide and best then
    -- Côte à côte : le nœud du côté de la voiture (repère du SDK, +1 à droite).
    local w=(a.splineLat or 0)*(offsetSign or 0)>0 and (a.rightWidth or 0) or (a.leftWidth or 0)
    local lat=w>0 and (a.splineLat or 0)/w or 0; if (offsetSign or 0)<0 then lat=-lat end
    if math.abs(nodes[k].lateral-lat)<math.abs(nodes[best].lateral-lat) then best=k; bestD=math.min(bestD,d) end
   end
  end
  if not best or bestD>GK.nodeRadius or taken[best] then return nil end
  taken[best]=true; out[i]=best; any=true
 end
 return any and out or nil
end
-- 2.0.4 (pilote, Monza, 18 novembre 11:47 : une IA sortie de piste, dépannée et repartie des stands roulait seule à
-- 125 km/h pendant que la grille se formait ; la grille l'attendait, sa place au milieu des voitures arrêtées) ; décision
-- du pilote du 18 novembre : voiture à plus de GK.lateGap m du peloton quand la grille se forme : arrière de la grille
-- (derrière la dernière place, dans l'ordre), jamais attendue (g.late). Le peloton : la voiture qui a le plus de
-- voitures à moins de GK.lateGap m d'elle. Après toBack : order = gardées, puis renvoyées (g.backN).
function M.lateCars(g,frame,order,n,now,log)
 local L=frame.length or 0
 if n<3 or L<=0 then return 0 end
 local best,bestCount=nil,-1
 for k=1,n do
  local a=frame.cars[order[k]]; local count=0
  for m=1,n do local b=frame.cars[order[m]]; if math.abs(U.spline(b.spline-a.spline))*L<=GK.lateGap then count=count+1 end end
  if count>bestCount then best=a; bestCount=count end
 end
 local keep=n-(g.backN or 0); local late=g.lateBuf or {}; g.lateBuf=late; local nl=0; local at=0
 for k=1,keep do
  local i=order[k]; local a=frame.cars[i]
  if not a.player and math.abs(U.spline(a.spline-best.spline))*L>GK.lateGap then nl=nl+1; late[nl]=i else at=at+1; order[at]=i end
 end
 if nl==0 then return 0 end
 -- Renvoyées (toBack) décalées vers l'avant de la liste, retardataires tout au bout.
 for m=1,(g.backN or 0) do order[at+m]=order[keep+m] end
 for m=1,nl do
  local i=late[m]; order[at+(g.backN or 0)+m]=i; g.late[i]=true
  U.log(log,now,'INFO',string.format('grille: %s part de l arriere de la grille (plus avec le peloton a la fin du tour de formation), sans etre attendue',frame.cars[i].name),i)
 end
 for k=#late,nl+1,-1 do late[k]=nil end
 g.backN=(g.backN or 0)+nl
 return nl
end
-- 2.0.4 (audit du 18 novembre : sur le chemin de la grille, une voiture dont la place est plus loin, arrivée derrière une
-- voiture de SA COLONNE déjà arrêtée, ne peut la rejoindre sans la doubler ; deux voitures de colonnes différentes ne se
-- gênent pas) : dans chaque colonne (places impaires, places paires), les voitures gardées doivent arriver dans l'ordre
-- de leurs places. Ordre réel sur la piste (de la tête à la queue du peloton) comparé à l'ordre des places : la plus
-- longue suite de voitures déjà dans l'ordre garde ses places ; les autres (jamais le joueur) partent de l'arrière de la
-- grille, dans l'ordre où elles roulent. order = gardées, renvoyées (toBack), retardataires (nl dernières) ; node : place
-- de chaque voiture (M.nodeRanks), sinon son rang.
function M.orderCars(g,frame,order,n,nl,now,log,node)
 local L=frame.length or 0
 local back=(g.backN or 0)-(nl or 0); local keep=n-(g.backN or 0)
 if keep<3 or L<4*GK.lateGap then return 0 end
 local list=g.seqBuf or {}; g.seqBuf=list; local m=0
 local ref=frame.cars[order[1]].spline
 for k=1,keep do
  local i=order[k]
  if not frame.cars[i].player then m=m+1; list[m]={i=i,slot=type(node)=='table' and type(node[i])=='number' and node[i] or k,at=U.spline(frame.cars[i].spline-ref)} end
 end
 for k=#list,m+1,-1 do list[k]=nil end
 table.sort(list,function(x,y) if x.at~=y.at then return x.at>y.at end return x.slot<y.slot end)
 -- Par colonne : plus longue suite croissante des places.
 local inSeq={}; local kept=0
 for parity=0,1 do
  local col={}; for a=1,m do if list[a].slot%2==parity then col[#col+1]=list[a] end end
  local len,prev={},{}; local bestEnd,bestLen=0,0
  for a=1,#col do
   len[a]=1; prev[a]=0
   for b=1,a-1 do if col[b].slot<col[a].slot and len[b]+1>len[a] then len[a]=len[b]+1; prev[a]=b end end
   if len[a]>bestLen then bestLen=len[a]; bestEnd=a end
  end
  local a=bestEnd
  while a>0 do inSeq[col[a].i]=true; kept=kept+1; a=prev[a] end
 end
 if kept==m then return 0 end
 -- Reconstruction : gardées (ordre des places), renvoyées d'avant, déplacées (ordre de la piste), retardataires.
 local out=g.outBuf or {}; g.outBuf=out; local at=0
 for k=1,keep do local i=order[k]; if frame.cars[i].player or inSeq[i] then at=at+1; out[at]=i end end
 for k=1,back do at=at+1; out[at]=order[keep+k] end
 local moved=0
 for x=1,m do local i=list[x].i; if not inSeq[i] then
  at=at+1; out[at]=i; moved=moved+1
  U.log(log,now,'INFO',string.format('grille: %s part de l arriere de la grille (plus a sa place dans la file a la fin du tour de formation)',frame.cars[i].name),i)
 end end
 for k=1,(nl or 0) do at=at+1; out[at]=order[keep+back+k] end
 for k=1,n do order[k]=out[k] end
 g.backN=(g.backN or 0)+moved
 return moved
end
-- Formation : places attribuées dans l'ordre du classement aux voitures en piste (voiture de sécurité et voitures
-- arrivées exclues) ; les voitures aux stands partent de la voie des stands.
function M.start(g,t,frame,now,log)
 clearCars(g); clearPlayer(t)
 local from=t.startAbortFrom; t.startAbortFrom=nil
 if g.hit then for i=1,K.maxCars do g.hit[i]=nil end end
 local order=g.order; local n=0; local fixed=nil
 for i=1,frame.count do
  local a=frame.cars[i]
  if a.valid and not a.finished and not a.safetyCar and (a.control or a.player) then
   if a.pit then g.pit[i]=true elseif a.splineValid then n=n+1; order[n]=i end
  end
 end
 -- Beta 1.48 : ordre figé au drapeau rouge (t.redRank) ; voitures absentes de l'ordre ensuite, au classement.
 if (t.redOrderN or 0)>0 then M.sortByRank(order,n,frame.cars,t.redRank)
  -- Beta 1.64 (lot 2) : relance après un départ avorté : la voiture à l'origine, doublée, part de l'arrière.
  if (t.abortMarks or 0)>0 then toBack(g,t,frame,order,n,t.redRank,false,now,log) end
  if (t.abortMarks or 0)>0 and (g.backN or 0)>0 then redBack(t,g.back,g.backN) end
 elseif (t.formationRankN or 0)>0 and t.formationRank then
  -- Correctif 1.63 (règlement du tour de formation) : grille dans l'ordre du départ ; une voiture doublée par une
  -- voiture partie derrière elle (place perdue et pas reprise) part de l'arrière de la grille, dans l'ordre du départ.
  -- Relecture 1.63 (N2) : seulement une voiture retardée (incident pendant le tour : tête-à-queue, arrêt) ; une voiture
  -- simplement doublée reprend sa place d'origine, celle qui l'a doublée aussi (ordre du départ rétabli).
  M.sortByRank(order,n,frame.cars,t.formationRank)
  g.backN=0
  toBack(g,t,frame,order,n,t.formationRank,true,now,log)
  local nl=M.lateCars(g,frame,order,n,now,log)
  M.orderCars(g,frame,order,n,nl,now,log,t.formationNode)
  t.formationRankN=0
  fixed=M.fixedSlots(g,order,n,t.formationNode,g.backN); t.formationNode=nil
 else M.sortByPosition(order,n,frame.cars) end
 -- Beta 1.64 (lot 2) : marques d'un départ avorté : servent une seule fois (cette grille). Le choc qui a fait avorter le
 -- départ est oublié (fenêtre K.crashWindow) : la fautive arrêtée à sa nouvelle place n'est pas un nouvel incident.
 if (t.abortMarks or 0)>0 and t.cars then for i=1,#t.cars do local c=t.cars[i]; if c.abortMark then c.lastCrash=-math.huge end; c.abortMark=false; c.abortHold=false end; t.abortMarks=0; t.abortHolds=0 end
 local slots,source,why=M.resolve(g.nodes,frame.length,fixed or n,g.slots)
 if not slots then return false end
 g.slots=slots; g.source=source
 for k=1,n do g.slotOf[order[k]]=fixed and g.fixed[k] or k end
 g.phase='grid'; g.since=now; g.count=n; g.heldCount=0; g.jump=false; g.refSet=false; g.timedOut=false; g.gridId=(g.gridId or 0)+1
 -- 2.0.4 : une ligne : place de chaque voiture et d'où elle vient (relevée sur la grille au feu vert, ou dans l'ordre).
 if log then
  local parts={}
  for k=1,n do local i=order[k]; parts[k]=string.format('%d:%s',g.slotOf[i],frame.cars[i].name or '?') end
  U.log(log,now,'INFO',string.format('grille: places %s : %s',fixed and 'relevees sur la grille' or 'dans l ordre',table.concat(parts,', ')),-1)
 end
 g.jumpGrade=nil; g.jumpMoved=0; g.jumpKmh=0; g.jumpLead=0; g.jumpSlot=0; g.jumpLaunchAt=nil
 t.standing='grid'
 g.from=from or ''
 U.log(log,now,'INFO',string.format('grille: formation, %d voitures, %s',n,source=='AC_START' and string.format('%d places (AC_START)',#g.nodes) or 'places calculees ('..why..')'),-1)
 return true
end
-- Distance de la voiture à sa place, mesurée vers l'avant (positive : place devant elle, jusqu'à presque un tour) ;
-- négative seulement juste au-delà de la place (moins de K.gridOvershoot m), en mètres.
local function gap(g,frame,i)
 local s=g.slots[g.slotOf[i]]
 if not s then return 0 end
 local ahead=((s.spline-frame.cars[i].spline)%1)*frame.length
 local past=frame.length-ahead
 if ahead>0 and past<=K.gridOvershoot then return -past end
 return ahead
end
M.gap=gap
-- Commandes d'une IA pendant la formation et les feux : plafond d'allure (racine de 2·décélération·distance),
-- freinage d'appoint sur les derniers mètres, colonne de sa place à l'approche, retenue une fois en place (ou juste
-- au-delà de sa place : jamais de marche arrière).
-- Beta 2.0.4 : écart latéral (repère des places) de la colonne de la place k, d m avant elle : droite passant par la place k
-- et la place de la même colonne la plus proche (k+2 derrière, sinon k-2 devant) ; bornée comme les places.
function M.columnLateral(g,k,d,length)
 local s=g.slots[k]; if not s then return 0 end
 if not length or length<=0 or not U.finite(d) or d<=0 then return s.lateral end
 -- 2.0.4 (pilote, Monza, 18 novembre 10:53 : tête-à-queue à 80 km/h, 230 m avant la grille, décalage +0.61 pour une
 -- place sur la trajectoire) : la droite par la place k et la place k+2 (16 m) prolongée jusqu'à 350 m multipliait par
 -- 20 le moindre écart des nœuds. Désormais la colonne suit les places réelles de la même colonne derrière la place k
 -- (k+2, k+4…), par segments, sans jamais aller au-delà de la dernière : la cible reste toujours entre les places.
 local j=k; local prev=0; local lat=s.lateral
 while true do
  local o=g.slots[j+2]
  if not o then return lat end
  local dist=U.spline(s.spline-o.spline)*length -- positif : la place j+2 est derrière la place k
  if dist<=prev+0.5 then return lat end
  if d<=dist then return U.clamp(lat+(o.lateral-lat)*((d-prev)/(dist-prev)),-K.gridLatClamp,K.gridLatClamp) end
  j=j+2; prev=dist; lat=o.lateral
 end
end
local function approach(g,frame,i,cmd,offsetSign,still,now)
 local a=frame.cars[i]; local d=gap(g,frame,i)
 local hold=K.gridHoldDistance
 local pose=g.pose and g.source=='AC_START' and g.pose[g.slotOf[i]] or nil
 if pose and U.finite(a.x) and U.finite(a.z) then
  local dp=(pose.x-a.x)*pose.lx+(pose.z-a.z)*pose.lz
  if math.abs(dp-d)<=GK.poseTrust then d=dp; hold=GK.poseStop end
 end
 -- 2.0.4 (pilote, Monza, 18 novembre 09:45 : une IA retenue 2,5 m avant sa place, sa vitesse passée sous le seuil un
 -- instant pendant qu'elle avançait au pas) : arrêtée plus loin que K.gridHoldDistance m de sa place, elle n'est tenue
 -- en place qu'après GK.shortStill s immobile (sinon elle continue d'avancer jusqu'à sa place).
 local short=a.kmh<K.gridStillKmh and d<=K.gridSlotRadius
 if short then g.shortAt[i]=g.shortAt[i] or now or 0 else g.shortAt[i]=nil end
 if not g.held[i] and (still or d<=hold or short and (now==nil or now-g.shortAt[i]>=GK.shortStill)) then
  g.held[i]=true; g.heldCount=g.heldCount+1; g.heldAt[i]=now; if now and not g.firstHeldAt then g.firstHeldAt=now end; if now then g.lastHeldAt=now end
 end
 cmd.noRetire=true
 local cap=M.retireGuard and U.clamp(math.sqrt(2*GK.approachDecel*math.max(0,d-hold))*3.6,K.gridCrawlKmh,GK.approachKmh)
  or U.clamp(math.sqrt(2*K.gridApproachDecel*math.max(0,d-hold))*3.6,K.gridCrawlKmh,K.gridApproachKmh)
 -- Correctif 1.61 (départs réalistes, demande du pilote) : coup d'accélérateur juste avant la place (« burnout »), une
 -- fois par départ, entre K.formBurstFrom et K.formBurstTo m de la place : plafond relevé de K.formBurstKmh km/h pendant
 -- K.formBurstTime s, jamais au-dessus de l'allure qui s'arrête encore à la place en K.formBurstDecel m/s².
 if g.realism and now and not g.held[i] and not g.burstDone[i] and d<=K.formBurstFrom and d>=K.formBurstTo then g.burstDone[i]=true; g.burstUntil[i]=now+K.formBurstTime end
 if g.realism and now and now<(g.burstUntil[i] or -math.huge) and not g.held[i] then cap=math.min(cap+K.formBurstKmh,math.sqrt(2*K.formBurstDecel*math.max(0,d-hold))*3.6) end
 -- Correctif 1.63 : approche au pas tant que d'autres voitures sont encore loin de leur place (jamais immobile trop tôt).
 if g.creep and not g.held[i] and d<=GK.creepZone and d>hold then cap=math.min(cap,GK.creepKmh) end
 cmd.speedLimit=math.min(cmd.speedLimit or K.unlimitedSpeed,g.held[i] and K.gridCrawlKmh or cap)
 -- 2.0.4 (pilote, Monza, 18 novembre 13:05 : « les roues avant ne sont pas droites, le volant est tourné ») : IA tenue à
 -- sa place : volant droit imposé (src/applier.lua, commande du frein avec la direction à zéro) jusqu'à l'extinction.
 -- 2.0.4 (même essai : une IA partie d'elle-même de l'autre côté de la piste en rattrapant la file, « agressivité
 -- 109 % ») : sur le chemin de sa place et à sa place, la consigne latérale est suivie strictement (évitement natif de
 -- l'IA ignoré : la file stricte tient les distances) et son agressivité native est nulle (src/applier.lua).
 cmd.gridStrict=true; cmd.gridCalm=true
 if g.held[i] then cmd.stopHold=true; cmd.gridStraight=true
 elseif d<K.gridBrakeFrom and a.kmh>cmd.speedLimit+K.gridBrakeMargin then cmd.brake=math.max(cmd.brake or 0,U.clamp((a.kmh-cmd.speedLimit)/K.gridBrakeScale,K.gridBrakeMin,K.brakeMax)) end
 -- Colonne de la place (repère du SDK, +1 à droite) dans le repère latéral interne calibré.
 -- Affinage 2.0.4 (pilote, 17 novembre, capture de la grille de Monza : voitures de travers sur leur place ; replay :
 -- l'écart restant, corrigé au pas dans les derniers mètres, tournait la voiture de 11 à 15 degrés) : colonne prise dès
 -- K.gridColumnEarly m (hors de la zone de l'entrée des stands), et dans les K.gridSteerFreeze derniers mètres, au pas,
 -- décalage tenu à l'écart réel de la voiture (elle s'aligne, ne braque plus) ; le même écart est gardé à l'extinction.
 local entry=g.pitEntry or -1
 local de=entry>=0 and a.splineValid and frame.length>0 and U.spline(a.spline-entry)*frame.length or nil
 local atEntry=de~=nil and de>=-K.pitEntryBefore and de<=K.pitEntryAfter
 local from=K.gridColumnEarly and math.max(K.gridColumnFrom,K.gridColumnEarly) or K.gridColumnFrom
 g.frozen=g.frozen or {}
 -- Affinage 2.0.4 (Monza, 16 h 24 : une IA arrivée de l'autre colonne, figée à mi-chemin, 2 m à côté de sa place et de
 -- travers) : figée seulement déjà dans sa colonne (à moins de K.gridFreezeTol m de la place) ; sinon elle finit de s'y
 -- ranger.
 -- Affinage 2.0.4 (Monza, 16 h 59 : voitures arrêtées droites par rapport à la trajectoire, mais la trajectoire traverse
 -- la ligne droite de la grille en biais : toutes tournées vers la droite) : la colonne suit la ligne des places de la même
 -- colonne (place k et la place k+2, ou k-2 pour la dernière), jamais un écart fixe à la trajectoire : la voiture arrive
 -- parallèle aux places.
 local k=g.slotOf[i]; local lat=M.columnLateral(g,k,d,frame.length); local want=offsetSign<0 and -lat or lat
 -- 2.0.4 (pilote, Monza, 18 novembre 10:53) : la commande de colonne remplaçait d'un coup le décalage progressif du
 -- pilotage (à 125 km/h, un écart de plusieurs mètres demandé en une image : l'IA d'AC donne un grand coup de volant,
 -- dépasse sa cible et part en tête-à-queue) : décalage mené de l'écart réel de la voiture vers sa colonne à
 -- GK.columnRate par seconde au plus (M.columnRamp).
 -- 2.0.4 (pilote, Monza, 18 novembre 13:33 ; replay : six IA bien alignées à 8 m de leur place tournées de 10 à 17
 -- degrés dans les derniers mètres) : la consigne de colonne n'est plus jamais remplacée par l'écart mesuré de la voiture
 -- (les deux ne coïncident pas : un coup de volant à chaque fois) : elle est suivie jusqu'à la place et encore une fois la
 -- voiture tenue (une voiture posée d'emblée sur sa place finit de la rejoindre : à l'extinction, le pilotage repart de
 -- la colonne de la place).
 if g.frozen[i] then cmd.offset=g.frozen[i]
 elseif d<from and not atEntry then
  cmd.offset=M.columnRamp(g,i,a,want)
 else g.ramp[i]=nil end
end
-- Décalage de colonne mené progressivement (2.0.4) : départ de l'écart réel de la voiture (repère interne, comme la
-- retenue des derniers mètres), puis au plus GK.columnRate par seconde (g.dt, durée de l'image de la grille).
function M.columnRamp(g,i,a,want)
 g.ramp=g.ramp or {}
 local cur=g.ramp[i]
 if cur==nil then
  -- Repère interne : écart / largeur du côté (le signe du repère est porté par la commande, comme pour la retenue).
  if a.splineLatValid and (a.leftWidth or 0)>0 and (a.rightWidth or 0)>0 then
   local w=(a.splineLat*(g.offsetSign or 0)>0) and a.rightWidth or a.leftWidth
   cur=U.clamp(a.splineLat/w,-K.gridLatClamp,K.gridLatClamp)
  else
   -- Écart réel pas lu : départ du dernier décalage du pilotage (commande continue, jamais de saut).
   local st=g.states and g.states[i]
   cur=st and U.finite(st.offset) and st.offset or want
  end
 end
 cur=U.approach(cur,want,GK.columnRate*(g.dt or 0))
 g.ramp[i]=cur
 return cur
end
-- Départ depuis la voie des stands : aucune commande aux stands ; sortie de la voie des stands pendant la formation (ou
-- les feux), retenue là où elle rejoint la piste, au pas, jusqu'à l'extinction (jamais lancée sur la grille arrêtée).
local function pitStarter(a,cmd)
 if a.player or not a.valid then return end
 cmd.noRetire=true
 if a.pit then cmd.pitHold=true else cmd.stopHold=true; cmd.speedLimit=math.min(cmd.speedLimit or K.unlimitedSpeed,K.gridCrawlKmh) end
end
-- Levée de toutes les retenues : réveil des IA (impulsion d'une image), plus aucune commande de grille. Beta 1.35 :
-- l'état latéral du pilotage (states) part de la colonne de la place, sans saut de trajectoire à l'extinction.
local function release(g,frame,commands,offsetSign,states)
 for i=1,frame.count do
  if g.slotOf[i]>0 or g.pit[i] then commands[i].gridWake=true; g.woke=true end
  commands[i].noRetire=false -- Affinage 1.63 : protection levée à l'extinction (ou à l'annulation)
  local k=g.slotOf[i]; local s=states and states[i]
  -- Beta 1.36 : seulement une IA retenue près de sa place (jamais une voiture lâchée par le délai loin de sa place, ni
  -- une voiture aux stands) : aucun saut latéral au départ ni à la sortie des stands.
  if k>0 and s and not frame.cars[i].player and g.slots[k] and g.held[i] and not frame.cars[i].pit and gap(g,frame,i)<K.gridColumnFrom then
   local lat=g.slots[k].lateral; local o=g.frozen and g.frozen[i] or (offsetSign<0 and -lat or lat)
   s.offset=o; s.filtered=o; s.velocity=0; commands[i].offset=o
  end
 end
 clearCars(g)
end
-- IA attendues à leur place : celles qui ont une place, en piste, ni invalides ni disqualifiées (recomptées à chaque
-- image : une IA rentrée aux stands ou garée pendant la formation ne retient plus les feux), et combien y sont.
local function expected(g,frame,dq)
 local n,held=0,0
 for i=1,frame.count do
  if g.slotOf[i]>0 then
   local a=frame.cars[i]
   if not a.player and a.valid and not a.pit and not g.lost[i] and not g.late[i] and not (dq and dq[i]) then n=n+1; if g.held[i] then held=held+1 end end
  end
 end
 return n,held
end
-- Correctif 1.61 (Spa, 11 novembre : 20 IA « rendues a AC dans la voie des stands » pendant la grille, pneus changés à
-- la même seconde : ramenées à leur stand par AC, sans rouler) : une IA de la grille qui apparaît aux stands est notée
-- une fois, avec le temps passé à l'arrêt, puis traitée comme partant de la voie des stands (jamais comptée en place).
local function lostCars(g,frame,now,log)
 for i=1,frame.count do
  if g.slotOf[i]>0 and not g.pit[i] and not g.lost[i] then
   local a=frame.cars[i]
   if not a.player and a.valid and a.pit then
    g.lost[i]=true; g.pit[i]=true
    U.log(log,now,'WARN',string.format('grille: %s ramenee aux stands par AC (%s), part de la voie des stands',a.name,g.heldAt[i] and string.format('a l arret depuis %.0f s',now-g.heldAt[i]) or 'pas encore en place'),i)
   end
  end
 end
end
-- Beta 1.61 (tranche D) : IA qui vole le départ (tirée par src/antics.lua, seulement avec la sanction du faux départ) :
-- sa retenue est levée g.aiRelease[i] s avant l'extinction, et le faux départ est relevé aussitôt (toujours sanctionné).
local function early(g,frame,i,commands,now,log)
 local lead=g.aiRelease[i]
 if not lead or now<g.outAt-lead then return false end
 if not g.aiReleased[i] then
  g.aiReleased[i]=true; commands[i].gridWake=true; g.woke=true
  if not g.aiJump[i] then
   g.aiJump[i]=true; g.aiJumpGrade[i]=Antics.grade(0,0,g.outAt-now,false,true)
   U.log(log,now,'WARN',string.format('faux depart IA: %s, %s (%.1f m, %.1f s avant l extinction)',frame.cars[i].name,g.aiJumpGrade[i]=='flagrant' and 'faux depart flagrant' or 'faux depart',0,g.outAt-now),i)
  end
 end
 return true
end
-- Correctif 1.63 : heure de la première IA immobilisée encore sur la grille (ni ramenée aux stands, ni aux stands).
local function firstStill(g,frame)
 local first=nil
 for i=1,frame.count do
  local at=g.heldAt[i]
  if at and g.held[i] and g.slotOf[i]>0 and not g.lost[i] and not frame.cars[i].pit and not frame.cars[i].player and (not first or at<first) then first=at end
 end
 return first
end
M.firstStill=firstStill
-- Plus grande distance à sa place d'une IA attendue pas encore retenue (approche au pas des autres, GK.creepSpread).
local function farthest(g,frame,dq)
 local far=0
 for i=1,frame.count do
  local a=frame.cars[i]
  if g.slotOf[i]>0 and not g.held[i] and not a.player and a.valid and not a.pit and not g.lost[i] and not g.late[i] and not (dq and dq[i]) then local d=gap(g,frame,i); if d>far then far=d end end
 end
 return far
end
-- Affinage 1.63 : une IA attendue pas encore en place roule-t-elle encore (au-dessus de GK.movingKmh) ?
function M.rolling(g,frame,dq)
 for i=1,frame.count do
  local a=frame.cars[i]
  if g.slotOf[i]>0 and not g.held[i] and not a.player and a.valid and not a.pit and not g.lost[i] and not g.late[i] and not (dq and dq[i]) and (a.kmh or 0)>GK.movingKmh then return true end
 end
 return false
end
-- Affinage 1.63 (Imola, 13 novembre) : aux feux, IA attendues pas encore en place : nom, place, distance, vitesse.
local missBuf={}
function M.missing(g,frame,now,log,dq)
 local m=0; local total=0
 for i=1,frame.count do
  local a=frame.cars[i]
  if g.slotOf[i]>0 and not g.held[i] and not a.player and a.valid and not a.pit and not g.lost[i] and not g.late[i] and not (dq and dq[i]) then
   total=total+1
   if m<GK.missMax then m=m+1; missBuf[m]=string.format('%s (place %d, %.0f m, %.0f km/h)',a.name,g.slotOf[i],gap(g,frame,i),a.kmh or 0) end
  end
 end
 for k=#missBuf,m+1,-1 do missBuf[k]=nil end
 if total>0 then U.log(log,now,'INFO',string.format('grille: %d IA pas en place aux feux : %s%s',total,table.concat(missBuf,', '),total>m and ', ...' or ''),-1) end
end
local function placedPlayer(g,frame,player)
 local a=frame.cars[player]
 return math.abs(gap(g,frame,player))<=K.gridSlotRadius and a.kmh<K.gridStillKmh
end
-- Beta 1.64 (lot 2) : départ avorté d'une grille gérée par l'app : tentative comptée, voitures en cause marquées (toutes
-- celles de cette image), places de la grille avortée relevées (ordre du tour en plus), tour en plus demandé au moteur.
function M.abortMarks(g,t,frame)
 t.startAborts=(t.startAborts or 0)+1; t.startAbortPending=g.from; t.abortMarks=0
 for i=1,frame.count do
  local c=t.cars[i]; c.abortSlot=g.slotOf[i] or 0
  if c.since>=g.since and c.incident then c.abortMark=true; t.abortMarks=t.abortMarks+1 end
  -- Relecture 1.64 : IA tenue à sa place et heurtée : victime, jamais à l'origine (le départ reste avorté).
  if c.abortMark and g.hit and g.hit[i] then c.abortMark=false; t.abortMarks=t.abortMarks-1 end
  -- Relecture 1.64 : choc pendant la grille avortée oublié (une victime arrêtée à sa nouvelle place, circuit court, n'est
  -- pas un nouvel incident) ; celui de la voiture marquée l'est à la nouvelle grille (M.start).
  if not c.abortMark and (c.lastCrash or -math.huge)>=g.since then c.lastCrash=-math.huge end
 end
end
-- Beta 1.64 (lot 2) : toutes les voitures parties derrière la fautive (place de la grille avortée) et encore en course
-- sont devant elle au classement d'AC (même mesure que la règle 163D) ; place inconnue : jamais (attente maximale).
local function passed(t,frame,i)
 local pi=frame.cars[i].position or 0; local si=t.cars[i].abortSlot or 0
 if pi<1 or si<=0 then return false end
 for j=1,frame.count do
  local b=frame.cars[j]; local cj=t.cars[j]
  if j~=i and not cj.abortMark and (cj.abortSlot or 0)>si and b.valid and not b.pit and not b.finished and (b.position or 0)>pi then return false end
 end
 return true
end
-- Beta 1.64 (lot 2) : fautive retenue sur place (arrêt tenu, protection contre le renvoi, aucun dépannage) pendant le tour
-- en plus jusqu'au passage du peloton, au plus K.startBackHold s (K.startBackHoldBare sans protection) ; puis réveillée
-- une image : elle part derrière le peloton, jamais téléportée.
function M.holdBack(g,t,frame,commands,now,log)
 local n=0; local live=t.neutral and t.relaunch and not t.red
 for i=1,frame.count do
  local c=t.cars[i]
  if c.abortHold then
   local a=frame.cars[i]; local why=nil
   if not live or not a.valid or a.pit or a.finished then why='retenue annulee'
   elseif passed(t,frame,i) then why='peloton passe'
   elseif not c.incident then why='incident termine'
   elseif now-c.abortHoldAt>=(M.retireGuard and K.startBackHold or K.startBackHoldBare) then why='attente maximale' end
   -- Relecture 1.64 : attente maximale seulement piste libre derrière (même règle que la reprise d'une IA accidentée,
   -- c.abortTraffic posé par src/incidents.lua) ; sinon tenue au plus K.gridMax s (protection) ou K.startBackHoldBareMax s
   -- (sans : avant le renvoi d'AC).
   if why=='attente maximale' and c.abortTraffic and now-c.abortHoldAt<(M.retireGuard and K.gridMax or K.startBackHoldBareMax) then why=nil end
   if why then
    c.abortHold=false
    if a.valid and not a.pit then commands[i].gridWake=true; g.woke=true end
    -- Relecture 1.64 : dépannage reparti de zéro (temps d'arrêt imposé par l'app jamais compté), dès cette image.
    if a.valid and not a.pit then commands[i].recover=false; c.still=0; c.stuckFor=0; c.anchorX=a.x; c.anchorZ=a.z end
    U.log(log,now,'INFO',string.format('depart retarde: %s repart derriere le peloton apres %.0f s (%s)',a.name,now-c.abortHoldAt,why),i)
   else
    local cmd=commands[i]; n=n+1
    cmd.noRetire=true; cmd.stopHold=true; cmd.recover=false; cmd.speedLimit=math.min(cmd.speedLimit or K.unlimitedSpeed,K.gridCrawlKmh)
   end
  end
 end
 t.abortHolds=n
end
-- À chaque image tant qu'un départ arrêté est en cours. Renvoie 'go' à l'extinction des feux ('jump' s'il y a eu faux
-- départ du joueur : à sanctionner par le moteur, une fois le joueur passé la ligne).
-- 2.0.4 (décision du pilote du 18 novembre : « recaler ») : pose exacte de chaque place, relevée au feu vert du tour
-- de formation sur la voiture qui s'y trouve (immobile seulement) : position et cap où AC l'a posée pour un départ
-- arrêté. node : place de chaque voiture (M.nodeRanks) ; sans place relevée, aucune pose.
function M.recordPoses(g,frame,node)
 local pose=g.pose or {}; g.pose=pose
 for k in pairs(pose) do pose[k]=nil end
 if type(node)~='table' then return 0 end
 local n=0
 for i,k in pairs(node) do
  local a=frame.cars[i]
  if a and a.valid and (a.kmh or 99)<1 and U.finite(a.x) and U.finite(a.z) and U.finite(a.lx) and U.finite(a.lz) then
   pose[k]={x=a.x,y=a.y or 0,z=a.z,lx=a.lx,ly=a.ly or 0,lz=a.lz}; n=n+1
  end
 end
 return n
end
-- Recalage (avant les feux) : IA tenue à sa place, immobile depuis GK.snapStill s, près de la pose relevée (GK.snapMax m,
-- GK.snapAngle degrés), personne à moins de GK.snapClear m de cette pose : commande gridSnap (écrite par l'applicateur).
-- Vérifié GK.snapCheck s plus tard sur la voiture elle-même (M.snapVerify) : la convention de CSP (g.conv : sens de la
-- direction, décalage du point posé) est apprise de l'écart mesuré et gardée pour les voitures suivantes ; la référence du
-- faux départ est reprise après chaque écriture, le décalage retenu devient celui de la place.
local function conv(g)
 local c=g.conv
 if not c then c={dir=GK.snapDir,fwd=GK.snapFwd,lat=0}; g.conv=c end
 return c
end
local function snapClear(frame,i,pose)
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=i and b.valid and not b.pit and U.finite(b.x) and (b.x-pose.x)^2+(b.z-pose.z)^2<GK.snapClear^2 then return false end
 end
 return true
end
local function snapWrite(g,commands,i,pose,now,offsetSign)
 local c=conv(g)
 g.snapSeq=(g.snapSeq or 0)+1
 -- Repère de la pose : avant (lx, lz), droite (-lz, lx).
 commands[i].gridSnap={id=g.snapSeq,x=pose.x+c.fwd*pose.lx-c.lat*pose.lz,y=pose.y,z=pose.z+c.fwd*pose.lz+c.lat*pose.lx,
  lx=c.dir*pose.lx,ly=c.dir*pose.ly,lz=c.dir*pose.lz}
 local o=g.snapOff[i] or {}; g.snapOff[i]=o; o.fwd=c.fwd; o.lat=c.lat
 g.snapAt[i]=now; g.snapTry[i]=(g.snapTry[i] or 0)+1; g.aiRef[i]=nil
 local k=g.slotOf[i]; local s=g.slots[k]; if s then g.frozen[i]=offsetSign<0 and -s.lateral or s.lateral end
end
-- Écart mesuré après une écriture : (avant, droite) dans le repère de la pose, et cap inversé ou non.
function M.snapResidual(a,pose)
 local dx,dz=a.x-pose.x,a.z-pose.z
 return dx*pose.lx+dz*pose.lz,dx*(-pose.lz)+dz*pose.lx,a.lx*pose.lx+a.lz*pose.lz<0
end
-- Vérification d'une écriture : à l'envers, le sens est inversé et le décalage vaut l'écart moins le décalage écrit ; à
-- l'endroit, le décalage écrit moins l'écart. Renvoie vrai si la pose est bonne (rien à réécrire).
function M.snapVerify(g,i,a,pose)
 local c=conv(g); local o=g.snapOff[i] or {fwd=0,lat=0}
 local rf,rl,flipped=M.snapResidual(a,pose)
 if flipped then c.dir=-c.dir; c.fwd=rf-o.fwd; c.lat=rl-o.lat; return false,rf,rl,true end
 if math.sqrt(rf*rf+rl*rl)<=GK.snapTol then return true,rf,rl,false end
 c.fwd=o.fwd-rf; c.lat=o.lat-rl
 return false,rf,rl,false
end
function M.snap(g,frame,commands,now,offsetSign)
 g.snapBusy=false
 if (g.phase~='grid' and g.phase~='lights') or g.source~='AC_START' or not g.pose then return end
 for i=1,frame.count do
  local a=frame.cars[i]; local k=g.slotOf[i]; local pose=k>0 and g.pose[k] or nil
  if pose and g.held[i] and not a.player and a.valid and not a.pit and not g.lost[i] then
   if g.snapAt[i] then
    -- Écriture en attente de vérification (pendant les feux aussi).
    if now-g.snapAt[i]>=GK.snapCheck then
     local ok,rf,rl,flipped=M.snapVerify(g,i,a,pose)
     if ok or g.snapTry[i]>=GK.snapTries or not snapClear(frame,i,pose) then
      g.snapAt[i]=nil; g.snapped[i]=true
      local d=math.sqrt(rf*rf+rl*rl)
      if ok then g.snapN=(g.snapN or 0)+1 else g.snapLeft=(g.snapLeft or 0)+1 end
      g.snapMaxD=math.max(g.snapMaxD or 0,d); if flipped then g.snapMaxA=180 end
     else
      g.snapFixes=(g.snapFixes or 0)+1
      snapWrite(g,commands,i,pose,now,offsetSign); g.snapBusy=true
     end
    else g.snapBusy=true end
   elseif not g.snapped[i] and g.phase=='grid' then
    if (a.kmh or 99)<GK.snapKmh then g.stillAt[i]=g.stillAt[i] or now else g.stillAt[i]=nil end
    local dx,dz=a.x-pose.x,a.z-pose.z; local dist=math.sqrt(dx*dx+dz*dz)
    local ang=math.deg(math.acos(U.clamp(a.lx*pose.lx+a.lz*pose.lz,-1,1)))
    if dist<=GK.snapMax and ang<=GK.snapAngle and snapClear(frame,i,pose) then
     if g.stillAt[i] and now-g.stillAt[i]>=GK.snapStill then
      g.snapSum=(g.snapSum or 0)+dist; g.snapMoves=(g.snapMoves or 0)+1
      snapWrite(g,commands,i,pose,now,offsetSign)
     end
     g.snapBusy=true
    end
   end
  end
 end
end
-- Aux feux (2.0.4) : une ligne : recalages faits, puis écart de chaque IA à sa place (long / latéral, m), pour vérifier
-- la grille dans le journal.
function M.lightsReport(g,frame,now,log,offsetSign)
 if not log then return end
 local parts={}
 for i=1,frame.count do
  local a=frame.cars[i]; local k=g.slotOf[i]
  if k>0 and not a.player and a.valid and not a.pit then
   local lat=0; local s=g.slots[k]
   if s and a.splineLatValid and (a.leftWidth or 0)>0 and (a.rightWidth or 0)>0 then
    local want=offsetSign<0 and -s.lateral or s.lateral
    local w=want*offsetSign>0 and a.rightWidth or a.leftWidth
    lat=(a.splineLat or 0)-want*w
   end
   parts[#parts+1]=string.format('%d:%+.1f/%+.1f',k,gap(g,frame,i),lat)
  end
 end
 local c=g.conv or {dir=0,fwd=0,lat=0}
 U.log(log,now,'INFO',string.format('grille aux feux: %d IA reposees exactement (deplacees de %.2f m en moyenne, ecart restant au plus %.2f m, %d correction(s), %d pas a leur pose ; sens %+d, decalage %+.2f m) ; ecarts long/lat (m) %s',
  g.snapN or 0,(g.snapMoves or 0)>0 and (g.snapSum or 0)/g.snapMoves or 0,g.snapMaxD or 0,g.snapFixes or 0,g.snapLeft or 0,c.dir,c.fwd,table.concat(parts,' ')),-1)
end
function M.step(g,t,frame,now,commands,offsetSign,seed,log,states,dq)
 -- 2.0.4 : durée de l'image (décalage de colonne progressif) et repère latéral.
 g.dt=g.lastNow and math.max(0,math.min(0.1,now-g.lastNow)) or 0; g.lastNow=now; g.offsetSign=offsetSign; g.states=states
 for i=1,K.maxCars do local c=commands[i]; c.gridSnap=nil; c.gridStraight=nil; c.gridStrict=nil; c.gridCalm=nil end
 -- Réveil d'une seule image : effacé à l'image suivante (aucune boucle tant qu'il n'y en a pas eu).
 if g.woke then for i=1,K.maxCars do commands[i].gridWake=false end; g.woke=false end
 -- Affinage 1.63 : protection contre le renvoi d'AC reposée à chaque image par la grille (approach, pitStarter).
 for i=1,K.maxCars do commands[i].noRetire=false end
 -- Beta 1.64 (lot 2) : fautive d'un départ avorté retenue sur place pendant le tour en plus.
 if (t.abortHolds or 0)>0 then M.holdBack(g,t,frame,commands,now,log) end
 if t.standing=='none' then if g.phase~='none' then M.reset(g); clearPlayer(t) end; return nil end
 if t.standing=='grid' and g.phase=='none' and not M.start(g,t,frame,now,log) then
  t.standing='none'; t.greenUntil=now+K.greenShow; U.log(log,now,'INFO','relance arretee indisponible (grille): depart lance',-1); return nil
 end
 local player=frame.player
 -- Nouvel incident pendant la formation ou les feux : départ annulé.
 if g.phase=='grid' or g.phase=='lights' then
  -- Relecture 1.64 (lot 2) : IA tenue à sa place et heurtée par une autre voiture (victime d'un choc sur la grille).
  local hit=g.hit; if hit then for i=1,frame.count do if g.held[i] and (frame.cars[i].collidedWith or -1)>=1 then hit[i]=true end end end
  -- Beta 2.0.4 (pilote, 17 novembre : deux départs avortés de suite, IA entrées dans la voie des stands puis arrêt ou
  -- tête-à-queue à l'entrée des stands, 540 m avant la ligne) : jamais annulé pour une voiture dans la voie des stands ou
  -- partie de là (g.pit, g.lost), ni pour un incident dans la zone de l'entrée des stands (g.pitEntry, posé par le
  -- moteur : de K.pitEntryBefore m avant à K.pitEntryAfter m après) ; une ligne par incident, la voiture repart et la
  -- grille l'attend comme les autres. Ailleurs : annulé comme avant.
  g.kept=g.kept or {}
  for i=1,frame.count do
   local c=t.cars[i]
   local a=frame.cars[i]
   local away=a.pit or g.pit[i] or g.lost[i]
   local entry=g.pitEntry or -1
   local d=entry>=0 and a.splineValid and frame.length>0 and U.spline(a.spline-entry)*frame.length or nil
   local atEntry=d~=nil and d>=-K.pitEntryBefore and d<=K.pitEntryAfter
   local onGrid=not away and not atEntry
   if c.incident and c.since>=g.since and not onGrid and g.kept[i]~=c.since then
    g.kept[i]=c.since
    U.log(log,now,'INFO',away and string.format('depart maintenu: incident de %s dans la voie des stands',a.name or '') or string.format('depart maintenu: incident de %s a l entree des stands (%.0f m avant la ligne)',a.name or '',((-a.spline)%1)*frame.length),i)
   end
   if c.incident and c.since>=g.since and onGrid then
    U.log(log,now,'INFO','depart arrete annule: nouvel incident',i)
    if g.from~='' and not t.red then M.abortMarks(g,t,frame) end
    release(g,frame,commands,offsetSign,states); M.reset(g); t.standing='none'; t.gridLit=0; clearPlayer(t); return nil
   end
  end
 end
 local slotted=player>0 and g.slotOf[player]>0 and not g.pit[player]
 M.snap(g,frame,commands,now,offsetSign)
 if g.phase=='grid' then
  local timeout=now-g.since>=K.gridMax
  lostCars(g,frame,now,log)
  g.creep=not M.retireGuard and farthest(g,frame,dq)>GK.creepSpread
  for i=1,frame.count do
   local a=frame.cars[i]
   if g.slotOf[i]>0 and not a.player and a.valid and not a.pit and not g.lost[i] then approach(g,frame,i,commands[i],offsetSign,timeout,now)
   elseif g.pit[i] then pitStarter(a,commands[i]) end
  end
  local n,held=expected(g,frame,dq)
  -- Affinage 1.63 : une ligne par grille sur la protection contre le renvoi d'AC (vérification en jeu).
  if not g.guardLogged then g.guardLogged=true; U.log(log,now,'INFO',string.format(M.retireGuard and 'grille: %d IA protegees du renvoi aux stands, tenue sans limite de temps' or 'grille: %d IA sans protection du renvoi aux stands, attente bornee',n),-1) end
  if timeout and not g.timedOut then g.timedOut=true; U.log(log,now,'INFO',string.format('grille: delai maximal, %d IA retenues sur place',n-held),-1) end
  local placed=not slotted or frame.cars[player].pit or placedPlayer(g,frame,player)
  -- Correctif 1.61 : attente bornée à K.gridWaitMax s après la première IA retenue (une IA tenue à l'arrêt trop longtemps
  -- est ramenée à son stand par AC) ; les retardataires continuent vers leur place pendant les feux.
  -- Relecture 1.62 (S3) : attente mesurée depuis la dernière arrivée (K.gridWaitMax s), au plus K.gridWaitFirstMax s
  -- depuis la première (avant qu'AC ne ramène une IA immobile à son stand) ; jamais sans le joueur en place, sauf le
  -- délai maximal (K.gridMax s).
  -- Affinage 1.63 : avec la protection, une IA qui roule encore vers sa place compte comme une progression.
  if M.retireGuard and M.rolling(g,frame,dq) then g.movingAt=now end
  local stallFrom=M.retireGuard and g.lastHeldAt~=nil and max(g.lastHeldAt,g.movingAt or g.lastHeldAt) or g.lastHeldAt
  local waited=stallFrom~=nil and now-stallFrom>=(M.retireGuard and GK.stallGuarded or K.gridWaitMax) or g.firstHeldAt~=nil and now-g.firstHeldAt>=(M.retireGuard and GK.fillGuarded or K.gridWaitFirstMax)
  -- Beta 1.62 (relecture 162v, point 1) : IA prêtes (toutes en place, ou attente bornée écoulée) ; le joueur pas encore en
  -- place a sa propre attente bornée, K.gridPlayerWait s après ce moment, puis les feux partent (il est jugé comme
  -- d'habitude par les règles du faux départ). Avant, les IA restaient immobiles jusqu'au délai maximal (120 s).
  local aiReady=held>=n or waited
  if aiReady and not g.aiReadyAt then g.aiReadyAt=now end
  local playerLate=aiReady and not placed and g.aiReadyAt~=nil and now-g.aiReadyAt>=K.gridPlayerWait
  -- Correctif 1.63 : feux au plus tard quand la première IA immobile atteint GK.stillMax moins la séquence des feux.
  local seq=K.lightStep*(K.gridLights-1)+K.lightsOutMin
  local first=firstStill(g,frame)
  -- Affinage 1.63 : protection active : jamais de feux à la limite d'immobilité (l'IA retenue n'est plus renvoyée).
  local due=not M.retireGuard and first~=nil and now-first>=stillMax()-seq-GK.lightsMargin
  -- 2.0.4 : recalages en cours (pose à vérifier) : les feux attendent, GK.snapWait s au plus après les IA prêtes.
  local snapHold=g.snapBusy==true and g.aiReadyAt~=nil and now-g.aiReadyAt<GK.snapWait and not timeout and not due
  if (aiReady and (placed or playerLate) or due or timeout) and not snapHold then
   if not timeout and not (placed and held>=n) then
    U.log(log,now,'INFO',string.format('grille: feux apres %.0f s de grille, premiere IA immobile depuis %.1f s (%d / %d IA en place%s)',now-g.since,first and now-first or 0,held,n,placed and '' or ', joueur pas en place'),-1)
   end
   g.phase='lights'; g.lightsAt=now; t.standing='lights'; g.creep=false
   -- Cinquième feu après (K.gridLights-1) pas, extinction entre K.lightsOutMin et K.lightsOutMax s plus tard.
   g.outAt=now+K.lightStep*(K.gridLights-1)+K.lightsOutMin+U.unit(seed or 0,(t.reds or 0)+(t.startAborts or 0)*K.startAbortSalt,K.lightsOutSalt)*(K.lightsOutMax-K.lightsOutMin)
   -- Correctif 1.63 : extinction au plus tard GK.stillMax s après la première IA immobile (jamais avant la séquence).
   if first and not M.retireGuard then g.outAt=max(now+seq,math.min(g.outAt,first+stillMax())) end
   if held<n then M.missing(g,frame,now,log,dq) end
   U.log(log,now,'INFO',string.format('feux: allumage (%d / %d IA en place)',held,n),-1)
   M.lightsReport(g,frame,now,log,offsetSign)
  end
 end
 if g.phase=='lights' then
  lostCars(g,frame,now,log)
  -- Extinction : avant toute retenue de cette image (elles ne sont plus reposées).
  if now>=g.outAt then
   U.log(log,now,'INFO',string.format('feux eteints apres %.1f s: depart',now-g.lightsAt),-1)
   -- Beta 1.61 (tranche D) : grade du faux départ du joueur, jugé à l'extinction (réglage coupé : comme avant).
   if g.realism then
    local pa=player>0 and frame.cars[player] or nil
    -- Finition 1.61 (relecture) : avance mesurée depuis le vrai départ (au-dessus de K.jumpSpeed km/h), jamais depuis la
    -- détection : une voiture qui glisse lentement 2 s avant l'extinction n'est pas un faux départ flagrant.
    local lead=g.jump and g.jumpLaunchAt and g.outAt-g.jumpLaunchAt or 0
    local grade=Antics.grade(g.jumpMoved,g.jumpKmh,lead,pa~=nil and pa.kmh<K.gridStillKmh,g.jump)
    g.jumpGrade=grade~='none' and grade or nil
   else g.jumpGrade=g.jump and 'jump' or nil end
   g.jumpSlot=player>0 and g.slotOf[player] or 0
   local jumped=g.jump
   release(g,frame,commands,offsetSign,states); g.phase='go'; g.goUntil=now+K.goShow; t.standing='go'; t.gridLit=0; t.greenUntil=now+K.greenShow
   clearPlayer(t)
   return jumped and 'jump' or 'go'
  end
  for i=1,frame.count do
   local a=frame.cars[i]
   if g.slotOf[i]>0 and not a.player and a.valid and not a.pit and not g.lost[i] then
    -- Correctif 1.61 : retardataire encore loin de sa place (attente bornée) : il continue d'y aller, jamais arrêté en
    -- pleine piste.
    if not early(g,frame,i,commands,now,log) then approach(g,frame,i,commands[i],offsetSign,gap(g,frame,i)<=K.gridLateRoll,now) end
    -- Beta 1.42 : faux départ d'une IA (retenue à sa place, puis avancée de plus de K.jumpDistance m ou roulant au-dessus
    -- de K.jumpSpeed km/h avant l'extinction) : relevé pour les sanctions des IA, une fois par départ.
    if g.held[i] and a.splineValid and not g.aiJump[i] then
     local ref=g.aiRef[i]
     if not ref then if a.kmh<K.gridStillKmh then g.aiRef[i]=a.spline end
     else
      local moved=U.spline(a.spline-ref)*frame.length
      -- Relecture : mouvement tenu K.aiJumpDwell s (plus de K.aiJumpMinMove m) ; relevé une fois par départ (true, puis
      -- 'taken' une fois pris par les sanctions : jamais réarmé).
      local moving=moved>math.max(K.jumpDistance,K.aiJumpMinMove) or a.kmh>K.jumpSpeed and moved>K.aiJumpMinMove
      if not moving then g.aiJumpAt[i]=nil elseif not g.aiJumpAt[i] then g.aiJumpAt[i]=now end
      if moving and now-g.aiJumpAt[i]>=K.aiJumpDwell then g.aiJump[i]=true; U.log(log,now,'WARN',string.format('faux depart IA: %s, %.1f m, %.0f km/h, %.1f s avant l extinction',a.name,moved,a.kmh,g.outAt-now),i) end
      -- Beta 1.61 (tranche D) : grade du faux départ relevé (réglage startRealism) ; avance comptée seulement pour un vrai
      -- départ (au-dessus de K.jumpSpeed km/h), finition 1.61.
      if g.realism and g.aiJump[i]==true and not g.aiJumpGrade[i] then g.aiJumpGrade[i]=Antics.grade(moved,a.kmh,a.kmh>K.jumpSpeed and g.outAt-now or 0,false,true) end
     end
    end
   elseif g.pit[i] then pitStarter(a,commands[i]) end
  end
  t.gridLit=math.min(K.gridLights,1+math.floor((now-g.lightsAt)/K.lightStep))
  -- Faux départ : surveillé une fois le joueur à sa place et à l'arrêt (référence), jamais au départ des stands ; il
  -- avance de plus de K.jumpDistance m, ou roule vers l'avant au-dessus de K.jumpSpeed km/h.
  local a=slotted and frame.cars[player] or nil
  if a and a.valid and not a.pit and a.splineValid and (not g.jump or g.realism) then
   if not g.refSet then
    if placedPlayer(g,frame,player) then g.ref=a.spline; g.refSet=true
    -- Relecture 1.63 (N1) : joueur pas encore en place quand les feux s'allument (feux tenus sous la limite d'AC) : s'il
    -- atteint sa place en roulant (au-dessus de K.jumpSpeed km/h) avant l'extinction, faux départ comme à l'arrêt (aucun
    -- avantage à partir lancé).
    elseif g.phase=='lights' and now<g.outAt and gap(g,frame,player)<=0 and a.kmh>K.jumpSpeed then
     g.ref=a.spline; g.refSet=true; g.jump=true; g.jumpLead=g.outAt-now
     if g.realism then g.jumpMoved=max(g.jumpMoved,K.jumpDistance+1); g.jumpKmh=max(g.jumpKmh,a.kmh); g.jumpLaunchAt=g.jumpLaunchAt or now end
     U.log(log,now,'WARN',string.format('faux depart du joueur: %.1f m, %.0f km/h, %.1f s avant l extinction',-gap(g,frame,player),a.kmh,g.outAt-now),player)
    end
   else
    local moved=U.spline(a.spline-g.ref)*frame.length
    if g.realism then g.jumpMoved=max(g.jumpMoved,moved); g.jumpKmh=max(g.jumpKmh,a.kmh); if a.kmh>K.jumpSpeed and not g.jumpLaunchAt and now<g.outAt then g.jumpLaunchAt=now end end
    if g.jump then -- déjà relevé : seule l'avance est encore suivie (grade jugé à l'extinction)
    elseif moved>K.jumpDistance or a.kmh>K.jumpSpeed and moved>0 then g.jump=true; g.jumpLead=g.outAt-now; U.log(log,now,'WARN',string.format('faux depart du joueur: %.1f m, %.0f km/h, %.1f s avant l extinction',moved,a.kmh,g.outAt-now),player) end
   end
  end
 end
 if g.phase=='go' and now>=g.goUntil then g.phase='none'; t.standing='none' end
 -- Joueur : place et distance pour le panneau (au mètre sous 20 m, arrondie à 10 m au-delà), en place, place dépassée.
 if (g.phase=='grid' or g.phase=='lights') and player>0 then
  local k=g.slotOf[player]
  t.gridSlot=k; t.gridPit=k==0 or g.pit[player] or frame.cars[player].pit==true
  local d=k>0 and gap(g,frame,player) or 0
  -- Beta 1.36 : au-delà de sa place, distance en arrière (jusqu'à K.gridPassedShow m), jamais « presque un tour ».
  local back=d<0 and -d or 0
  if k>0 and d>0 and frame.length-d<=K.gridPassedShow then back=frame.length-d end
  t.gridPlaced=k>0 and not t.gridPit and placedPlayer(g,frame,player)
  t.gridPassed=k>0 and not t.gridPit and back>K.gridSlotRadius
  local shown=t.gridPassed and back or math.max(0,d)
  t.gridGap=shown<K.gridGapFine and math.floor(shown) or math.floor(shown/K.gridGapStep+0.5)*K.gridGapStep
 end
 return nil
end
return M
