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
function M.new()
 return {phase='none',slots={},slotOf={},held={},pit={},order={},source='',since=0,lightsAt=0,outAt=0,goUntil=-math.huge,
  ref=0,refSet=false,jump=false,count=0,heldCount=0,nodes=nil,timedOut=false,woke=false,aiRef={},aiJump={},aiJumpAt={},
  -- Beta 1.61 (tranche D, réglage startRealism : g.realism posé par src/antics.lua) : grade du faux départ du joueur
  -- (g.jumpGrade : creep, jump, flagrant), avance, vitesse et avance en temps relevées, place sur la grille ; IA qui
  -- vole le départ (g.aiRelease[i] : retenue levée tant de secondes avant l'extinction) et grade des IA.
  aiRelease={},aiReleased={},aiJumpGrade={},realism=false,jumpMoved=0,jumpKmh=0,jumpLead=0,jumpSlot=0,
  -- Correctif 1.61 (Spa, 11 novembre) : heure de retenue de chaque IA, IA ramenée aux stands par AC pendant la grille,
  -- première retenue (attente bornée avant les feux).
  heldAt={},lost={},firstHeldAt=nil,burstDone={},burstUntil={}}
end
local function clearCars(g) for i=1,K.maxCars do g.slotOf[i]=0; g.held[i]=false; g.pit[i]=false; g.aiRef[i]=nil; g.aiJumpAt[i]=nil; g.aiRelease[i]=nil; g.aiReleased[i]=nil; g.heldAt[i]=nil; g.lost[i]=nil; g.burstDone[i]=nil; g.burstUntil[i]=nil end; g.firstHeldAt=nil; g.lastHeldAt=nil; g.aiReadyAt=nil end
local function clearPlayer(t) t.gridPlaced=false; t.gridPassed=false end
function M.reset(g)
 g.phase='none'; g.source=''; g.since=0; g.lightsAt=0; g.outAt=0; g.goUntil=-math.huge; g.ref=0; g.refSet=false; g.jump=false
 g.count=0; g.heldCount=0; g.timedOut=false; clearCars(g)
 for i=1,K.maxCars do g.aiJump[i]=nil; g.aiJumpAt[i]=nil end
 for i=1,K.maxCars do g.aiJumpGrade[i]=nil end
 g.jumpGrade=nil; g.jumpMoved=0; g.jumpKmh=0; g.jumpLead=0; g.jumpSlot=0; g.jumpLaunchAt=nil
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
-- Formation : places attribuées dans l'ordre du classement aux voitures en piste (voiture de sécurité et voitures
-- arrivées exclues) ; les voitures aux stands partent de la voie des stands.
function M.start(g,t,frame,now,log)
 clearCars(g); clearPlayer(t)
 local order=g.order; local n=0
 for i=1,frame.count do
  local a=frame.cars[i]
  if a.valid and not a.finished and not a.safetyCar and (a.control or a.player) then
   if a.pit then g.pit[i]=true elseif a.splineValid then n=n+1; order[n]=i end
  end
 end
 -- Beta 1.48 : ordre figé au drapeau rouge (t.redRank) ; voitures absentes de l'ordre ensuite, au classement.
 if (t.redOrderN or 0)>0 then M.sortByRank(order,n,frame.cars,t.redRank) else M.sortByPosition(order,n,frame.cars) end
 local slots,source,why=M.resolve(g.nodes,frame.length,n,g.slots)
 if not slots then return false end
 g.slots=slots; g.source=source
 for k=1,n do g.slotOf[order[k]]=k end
 g.phase='grid'; g.since=now; g.count=n; g.heldCount=0; g.jump=false; g.refSet=false; g.timedOut=false
 g.jumpGrade=nil; g.jumpMoved=0; g.jumpKmh=0; g.jumpLead=0; g.jumpSlot=0; g.jumpLaunchAt=nil
 t.standing='grid'
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
local function approach(g,frame,i,cmd,offsetSign,still,now)
 local a=frame.cars[i]; local d=gap(g,frame,i)
 if not g.held[i] and (still or d<=K.gridHoldDistance or a.kmh<K.gridStillKmh and d<=K.gridSlotRadius) then
  g.held[i]=true; g.heldCount=g.heldCount+1; g.heldAt[i]=now; if now and not g.firstHeldAt then g.firstHeldAt=now end; if now then g.lastHeldAt=now end
 end
 local cap=U.clamp(math.sqrt(2*K.gridApproachDecel*math.max(0,d-K.gridHoldDistance))*3.6,K.gridCrawlKmh,K.gridApproachKmh)
 -- Correctif 1.61 (départs réalistes, demande du pilote) : coup d'accélérateur juste avant la place (« burnout »), une
 -- fois par départ, entre K.formBurstFrom et K.formBurstTo m de la place : plafond relevé de K.formBurstKmh km/h pendant
 -- K.formBurstTime s, jamais au-dessus de l'allure qui s'arrête encore à la place en K.formBurstDecel m/s².
 if g.realism and now and not g.held[i] and not g.burstDone[i] and d<=K.formBurstFrom and d>=K.formBurstTo then g.burstDone[i]=true; g.burstUntil[i]=now+K.formBurstTime end
 if g.realism and now and now<(g.burstUntil[i] or -math.huge) and not g.held[i] then cap=math.min(cap+K.formBurstKmh,math.sqrt(2*K.formBurstDecel*math.max(0,d-K.gridHoldDistance))*3.6) end
 cmd.speedLimit=math.min(cmd.speedLimit or K.unlimitedSpeed,g.held[i] and K.gridCrawlKmh or cap)
 if g.held[i] then cmd.stopHold=true
 elseif d<K.gridBrakeFrom and a.kmh>cmd.speedLimit+K.gridBrakeMargin then cmd.brake=math.max(cmd.brake or 0,U.clamp((a.kmh-cmd.speedLimit)/K.gridBrakeScale,K.gridBrakeMin,K.brakeMax)) end
 -- Colonne de la place (repère du SDK, +1 à droite) dans le repère latéral interne calibré.
 if d<K.gridColumnFrom then local lat=g.slots[g.slotOf[i]].lateral; cmd.offset=offsetSign<0 and -lat or lat end
end
-- Départ depuis la voie des stands : aucune commande aux stands ; sortie de la voie des stands pendant la formation (ou
-- les feux), retenue là où elle rejoint la piste, au pas, jusqu'à l'extinction (jamais lancée sur la grille arrêtée).
local function pitStarter(a,cmd)
 if a.player or not a.valid then return end
 if a.pit then cmd.pitHold=true else cmd.stopHold=true; cmd.speedLimit=math.min(cmd.speedLimit or K.unlimitedSpeed,K.gridCrawlKmh) end
end
-- Levée de toutes les retenues : réveil des IA (impulsion d'une image), plus aucune commande de grille. Beta 1.35 :
-- l'état latéral du pilotage (states) part de la colonne de la place, sans saut de trajectoire à l'extinction.
local function release(g,frame,commands,offsetSign,states)
 for i=1,frame.count do
  if g.slotOf[i]>0 or g.pit[i] then commands[i].gridWake=true; g.woke=true end
  local k=g.slotOf[i]; local s=states and states[i]
  -- Beta 1.36 : seulement une IA retenue près de sa place (jamais une voiture lâchée par le délai loin de sa place, ni
  -- une voiture aux stands) : aucun saut latéral au départ ni à la sortie des stands.
  if k>0 and s and not frame.cars[i].player and g.slots[k] and g.held[i] and not frame.cars[i].pit and gap(g,frame,i)<K.gridColumnFrom then
   local lat=g.slots[k].lateral; local o=offsetSign<0 and -lat or lat
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
   if not a.player and a.valid and not a.pit and not g.lost[i] and not (dq and dq[i]) then n=n+1; if g.held[i] then held=held+1 end end
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
local function placedPlayer(g,frame,player)
 local a=frame.cars[player]
 return math.abs(gap(g,frame,player))<=K.gridSlotRadius and a.kmh<K.gridStillKmh
end
-- À chaque image tant qu'un départ arrêté est en cours. Renvoie 'go' à l'extinction des feux ('jump' s'il y a eu faux
-- départ du joueur : à sanctionner par le moteur, une fois le joueur passé la ligne).
function M.step(g,t,frame,now,commands,offsetSign,seed,log,states,dq)
 -- Réveil d'une seule image : effacé à l'image suivante (aucune boucle tant qu'il n'y en a pas eu).
 if g.woke then for i=1,K.maxCars do commands[i].gridWake=false end; g.woke=false end
 if t.standing=='none' then if g.phase~='none' then M.reset(g); clearPlayer(t) end; return nil end
 if t.standing=='grid' and g.phase=='none' and not M.start(g,t,frame,now,log) then
  t.standing='none'; t.greenUntil=now+K.greenShow; U.log(log,now,'INFO','relance arretee indisponible (grille): depart lance',-1); return nil
 end
 local player=frame.player
 -- Nouvel incident pendant la formation ou les feux : départ annulé.
 if g.phase=='grid' or g.phase=='lights' then
  for i=1,frame.count do
   local c=t.cars[i]
   if c.incident and c.since>=g.since then
    U.log(log,now,'INFO','depart arrete annule: nouvel incident',i)
    release(g,frame,commands,offsetSign,states); M.reset(g); t.standing='none'; t.gridLit=0; clearPlayer(t); return nil
   end
  end
 end
 local slotted=player>0 and g.slotOf[player]>0 and not g.pit[player]
 if g.phase=='grid' then
  local timeout=now-g.since>=K.gridMax
  lostCars(g,frame,now,log)
  for i=1,frame.count do
   local a=frame.cars[i]
   if g.slotOf[i]>0 and not a.player and a.valid and not a.pit and not g.lost[i] then approach(g,frame,i,commands[i],offsetSign,timeout,now)
   elseif g.pit[i] then pitStarter(a,commands[i]) end
  end
  local n,held=expected(g,frame,dq)
  if timeout and not g.timedOut then g.timedOut=true; U.log(log,now,'INFO',string.format('grille: delai maximal, %d IA retenues sur place',n-held),-1) end
  local placed=not slotted or frame.cars[player].pit or placedPlayer(g,frame,player)
  -- Correctif 1.61 : attente bornée à K.gridWaitMax s après la première IA retenue (une IA tenue à l'arrêt trop longtemps
  -- est ramenée à son stand par AC) ; les retardataires continuent vers leur place pendant les feux.
  -- Relecture 1.62 (S3) : attente mesurée depuis la dernière arrivée (K.gridWaitMax s), au plus K.gridWaitFirstMax s
  -- depuis la première (avant qu'AC ne ramène une IA immobile à son stand) ; jamais sans le joueur en place, sauf le
  -- délai maximal (K.gridMax s).
  local waited=g.lastHeldAt~=nil and now-g.lastHeldAt>=K.gridWaitMax or g.firstHeldAt~=nil and now-g.firstHeldAt>=K.gridWaitFirstMax
  -- Beta 1.62 (relecture 162v, point 1) : IA prêtes (toutes en place, ou attente bornée écoulée) ; le joueur pas encore en
  -- place a sa propre attente bornée, K.gridPlayerWait s après ce moment, puis les feux partent (il est jugé comme
  -- d'habitude par les règles du faux départ). Avant, les IA restaient immobiles jusqu'au délai maximal (120 s).
  local aiReady=held>=n or waited
  if aiReady and not g.aiReadyAt then g.aiReadyAt=now end
  local playerLate=aiReady and not placed and g.aiReadyAt~=nil and now-g.aiReadyAt>=K.gridPlayerWait
  if aiReady and (placed or playerLate) or timeout then
   if not timeout and not (placed and held>=n) then
    local since=g.lastHeldAt or g.firstHeldAt or now
    U.log(log,now,'INFO',string.format('grille: attente bornee (%.0f s), feux sans attendre les retardataires (%d / %d IA en place%s)',now-since,held,n,placed and '' or ', joueur pas en place'),-1)
   end
   g.phase='lights'; g.lightsAt=now; t.standing='lights'
   -- Cinquième feu après (K.gridLights-1) pas, extinction entre K.lightsOutMin et K.lightsOutMax s plus tard.
   g.outAt=now+K.lightStep*(K.gridLights-1)+K.lightsOutMin+U.unit(seed or 0,t.reds or 0,K.lightsOutSalt)*(K.lightsOutMax-K.lightsOutMin)
   U.log(log,now,'INFO',string.format('feux: allumage (%d / %d IA en place)',held,n),-1)
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
    if placedPlayer(g,frame,player) then g.ref=a.spline; g.refSet=true end
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
