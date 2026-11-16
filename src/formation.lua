-- Beta 1.60 (tranche E, réglage raceStart : standing, formation, rolling ; idée d'Artood2s). Départ de la course :
-- « standing » = départ arrêté d'AC, rien ne change ; « formation » = tour de formation puis départ arrêté sur la
-- grille ; « rolling » = tour de formation puis départ lancé. Jamais choisi par défaut, jamais par un préréglage.
-- Le tour de formation réutilise la machinerie du tour de relance d'un drapeau rouge (src/incidents.lua) : au feu vert
-- d'AC, neutralisation propre (t.neutral, t.relaunch, FCY, t.formation) : file dans l'ordre de la grille, personne ne
-- double, tête plafonnée à t.formationKmh, aucun temps delta pour le joueur ; fin quand la tête a bouclé son tour
-- (leaderLap). Puis :
--  - formation : standing() forcé, grille, feux, extinction (src/grid.lua, inchangé), faux départs jugés comme à une
--    relance ;
--  - rolling : drapeau vert à K.rollGreenBefore m de la ligne, dépassement interdit jusqu'à la ligne (règle imposée),
--    premier virage attentif imposé (src/firstlap.lua, force) ; aucun vert avec un incident juste après la ligne.
-- Incident majeur pendant le tour : formation abandonnée, FCY ordinaire, puis départ lancé. Drapeau rouge : sa propre
-- procédure. Le journal du départ et le premier tour attentif attendent le vrai départ (moteur).
-- M.begin : au feu vert d'AC (moteur) ; M.step : avant le pilotage, renvoie 'roll' quand la course est lancée sans
-- grille (drapeau vert du départ lancé, grille annulée) ; M.pace : allure de la tête du tour de formation.
local U=require('src/util')
local K=require('src/config').K
local Incidents=require('src/incidents')
local max=math.max
local M={}
-- Correctif 1.63 (Montréal, 12 novembre : « file etiree (4074 m entre deux voitures) » dès le feu vert, des voitures
-- d'un côté de la ligne et de l'autre) : écarts mesurés sur le cercle du tour (le plus grand écart est la partie vide du
-- tour, jamais un écart de la file) ; ralentissement de la tête progressif (FK.slowRate km/h par seconde au plus).
local FK={slowRate=4,
 -- Affinage 1.63 (demande du pilote, 13 novembre : « ils ont l'air de limiter leur vitesse ») : au milieu du tour, l'allure
 -- de la tête varie d'un tronçon de bandSeg m à l'autre entre bandLo et bandHi fois l'allure du tour (100 km/h par
 -- défaut : de 90 à 140 km/h), d'après la graine ; plus jamais une limite plate tout le tour.
 bandSeg=400,bandLo=0.9,bandHi=1.4,bandSalt=911,
 -- Affinage 1.63 (Bakou, 13 novembre : file étirée à 46-53 m jusqu'au bout, 35 s pour remplir la grille) : sur les
 -- compactFrom derniers mètres de la tête, la file est regroupée plus serrée (compactGap m, compactTime s).
 compactFrom=1600,compactGap=24,compactTime=1.5,
 -- Affinage 1.63 (pilote, 13 novembre : « ils ne doivent pas être limités, ils peuvent monter à 300 km/h ; la tête
 -- accélère à fond en ligne droite, ralentit, fait de grands zigzags, réaccélère, refreine ») : au milieu du tour, chaque
 -- tronçon de bandSeg m est tiré (graine) : « libre » (part freeShare : aucun plafond, freeKmh), « chauffe » (part
 -- warmShare : warmMult fois l'allure du tour, grands zigzags) ou « vif » (briskMult) ; passage interpolé d'un tronçon à
 -- l'autre (accélération franche, puis freinage franc vers la chauffe). Fin du tour (compactFrom m) : allure du tour.
 freeShare=0.55,warmShare=0.25,freeKmh=400,warmMult=0.85,briskMult=1.5}
M.FK=FK
function M.new() return {session=-1,phase='none',kind='',called=false,report=false,begun=0,refused=0,prog={},strungFor=0,strungLogged=false} end
function M.reset(f) f.session=-1; f.phase='none'; f.kind=''; f.called=false; f.report=false; f.strungFor=0; f.strungLogged=false; f.slowKmh=nil end -- (f,now)
function M.rebase() end -- (f,amount) : aucune date gardée
-- Fin de tout état de formation dans les incidents (neutral : la neutralisation de la formation est levée aussi).
local function clear(t,neutral)
 if neutral and (t.formation or t.formationAborted) then t.neutral=false; t.relaunch=false; t.ending=false end
 t.formation=false; t.formationAborted=false; t.rollCall=false; t.rollGo=false; t.formationExtra=0; t.rollGreenAt=nil; t.formationSlowFrom=nil
 t.formationRankN=0
end
function M.pace(p) return max(p.fcySpeedKmh or 0,K.formationMinKmh)*K.formationSpeedMult end
-- Beta 1.61 (tranche D, réglage startRealism) : allure de la tête selon l'endroit du tour : lente à la sortie de la
-- grille (K.formOutDistance m), vive au milieu, lente sur les K.formBunchDistance derniers mètres (le peloton se
-- regroupe). travel : mètres parcourus par la tête ; toLine : distance de la tête à la ligne.
function M.profile(p,travel,toLine,length,seed)
 local base=M.pace(p)
 if travel<K.formOutDistance then return base*K.formSlowMult end
 if travel>=length*K.relaunchTravel and toLine<=K.formBunchDistance then return base*K.formSlowMult end
 if seed==nil then return base*K.formBriskMult end
 -- Affinage 1.63 : fin du tour (regroupement avant la grille ou l'appel) : allure du tour.
 if travel>=length*K.relaunchTravel and toLine<=FK.compactFrom then return base end
 -- Affinage 1.63 : tronçons tirés (libre, chauffe, vif), interpolés (jamais un saut) ; graine du départ.
 local x=math.max(0,travel-K.formOutDistance)/FK.bandSeg; local k=math.floor(x); local w=x-k
 local function seg(j)
  local u=U.unit(seed,j,FK.bandSalt)
  if u<FK.freeShare then return FK.freeKmh end
  if u<FK.freeShare+FK.warmShare then return base*FK.warmMult end
  return base*FK.briskMult
 end
 return seg(k)*(1-w)+seg(k+1)*w
end
-- Beta 1.64 (lot 2) : mise en place du tour de formation (extraite de M.begin, mêmes effets dans le même ordre) : au feu
-- vert d'AC, et pour le tour en plus d'un départ avorté (M.rearm). Renvoie l'allure du tour.
local function arm(f,e,frame,now,kind)
 local t=e.incidents; local p=e.run
 local kmh=M.pace(p)
 t.neutral=true; t.relaunch=true; t.ending=false; t.escalated=false; t.neutralMode='fcy'; t.neutralSince=now; t.neutralUntil=now
 t.relaunchSpanUntil=now; t.relaunchLeader=0; t.relaunchTravel=0; t.relaunchToLine=math.huge
 t.formation=true; t.formationKind=kind; t.formationAborted=false; t.formationExtra=0; t.formationKmh=kmh; t.rollGo=false; t.rollCall=false
 f.phase='lap'; f.kind=kind; f.called=false; f.begun=f.begun+1
 -- Beta 1.61 (tranche D) : la voiture de tête choisit son moment : drapeau vert du départ lancé entre
 -- K.rollZoneFrom m et K.rollGreenBefore m de la ligne (jamais plus tard qu'en 1.60), tiré de la graine.
 t.rollGreenAt=nil
 if p.startRealism then
  if kind=='rolling' then t.rollGreenAt=U.lerp(K.rollGreenBefore,max(K.rollGreenBefore,K.rollZoneFrom),U.unit(e.runtimeG.seed or 0,f.begun,K.anticSalt+7)) end
  t.formationKmh=M.profile(p,0,frame.length,frame.length)
 end
 return kmh
end
-- Feu vert d'AC. Vrai : le tour de formation commence (le moteur reporte le journal du départ et le premier tour).
function M.begin(f,e,frame,now)
 local t=e.incidents; local p=e.run
 Incidents.clearStartAbort(t)
 if f.phase~='none' then clear(t,true); f.phase='none'; f.report=false end
 local want=p.raceStart
 if e.profile~='C' or want==nil or want=='standing' then return false end
 local why=frame.online and 'en ligne' or frame.replay and 'rediffusion' or frame.length<=0 and 'circuit inconnu' or frame.length>K.formationMaxLength and 'circuit trop long'
  or t.red and 'drapeau rouge' or t.neutral and 'neutralisation' or nil
 if why then
  f.refused=f.refused+1
  U.log(e.log,now,'INFO',string.format('depart: tour de formation impossible (%s) : depart arrete d AC',why),-1)
  return false
 end
 local kind=want=='formation' and 'formation' or 'rolling'
 -- Grille indisponible (capacités, sens latéral non mesuré) : départ lancé, comme le repli d'une relance arrêtée.
 if kind=='formation' and not (e.gridCaps==true and e.g.offsetSign~=0) then
  -- 2.0.2 i (retour d'un joueur : « tour de formation arrêté » toujours suivi d'un départ lancé) : sens latéral pas
  -- encore mesuré au feu vert (première séance, course seule) : le tour de formation reste « arrêté » ; la mesure peut
  -- se faire pendant le tour, et la fin du tour (Incidents standing, t.gridReady relu à chaque image) choisit la grille
  -- ou, toujours inconnu, le départ lancé (une ligne au journal). Capacités absentes (CSP) : départ lancé dès le feu vert.
  if e.gridCaps~=true or not K.formationWaitSign then
   U.log(e.log,now,'INFO',string.format('depart: grille indisponible (%s) : depart lance apres le tour de formation',e.gridCaps~=true and 'capacites' or 'sens lateral non mesure'),-1)
   kind='rolling'
  else
   U.log(e.log,now,'INFO','depart: sens lateral pas encore mesure : mesure pendant le tour de formation, sinon depart lance',-1)
  end
 end
 -- Relecture : IA seulement (le meneur du tour est une IA) ; sans aucune IA en piste, pas de tour de formation.
 local n=0
 for i=1,frame.count do local a=frame.cars[i]; if a.valid and not a.pit and not a.finished and not a.safetyCar and a.control then n=n+1 end end
 if n==0 then
  f.refused=f.refused+1
  U.log(e.log,now,'INFO',string.format('depart: tour de formation impossible (%s) : depart arrete d AC','aucune IA'),-1)
  return false
 end
 -- Correctif 1.63 (règlement du tour de formation) : ordre de la grille au feu vert, relevé pour la grille d'arrivée du
 -- tour (src/grid.lua : une voiture qui a perdu sa place part de l'arrière de la grille).
 local rank=t.formationRank or {}; t.formationRank=rank; for k in pairs(rank) do rank[k]=nil end
 local ranked=0
 for i=1,frame.count do local a=frame.cars[i]; if a.valid and not a.pit and not a.finished and not a.safetyCar and (a.control or a.player) and (a.position or 0)>=1 then rank[i]=a.position; ranked=ranked+1 end end
 t.formationRankN=ranked; t.formationAt=now
 local kmh=arm(f,e,frame,now,kind); f.report=true
 if p.startRealism then
  U.log(e.log,now,'INFO',string.format('tour de formation: depart par rangees, zigzags %s, deux files a %.0f m de la ligne','oui',kind=='rolling' and K.rollCallDistance or 0),-1)
  U.log(e.log,now,'INFO',string.format('tour de formation: tete sans limite de vitesse sur %d %% du tour, chauffe a %.0f km/h sur %d %%, regroupee sur les %.0f derniers m',math.floor(FK.freeShare*100+0.5),kmh*FK.warmMult,math.floor(FK.warmShare*100+0.5),FK.compactFrom),-1)
 end
 U.log(e.log,now,'INFO',string.format('depart: tour de formation (%d voitures, %.0f km/h en tete), puis depart %s',n,kmh,kind=='formation' and 'arrete' or 'lance'),-1)
 -- Relecture : toujours annoncé, même messages de drapeau coupés (règle « pas de dépassement » jamais sans message).
 -- Valeur : nombre d'IA ; extra : 0 départ arrêté après le tour, 1 départ lancé (contrat avec SpotterEnginer).
 Incidents.message(t,'formation',n,kind=='formation' and 0 or 1)
 return true
end
-- Beta 1.64 (lot 2, décision du pilote du 13 novembre) : départ avorté (nouvel incident sur la grille ou aux feux d'une
-- grille de l'app) : tout le peloton refait un tour (même machinerie : tour de formation, ou tour de relance après un
-- drapeau rouge), puis nouvelle grille et nouveaux feux ; au-delà de K.startAbortMax départs avortés, départ lancé à la fin
-- du tour. Refusé (comportement d'avant, une ligne) : drapeau rouge, neutralisation déjà déclarée, course relancée.
function M.rearm(f,e,frame,now)
 local t=e.incidents; local p=e.run; local from=t.startAbortPending; t.startAbortPending=false
 local n=t.startAborts or 0
 local why=t.red and 'drapeau rouge' or t.neutral and 'neutralisation' or (e.profile~='C' or not frame.started) and 'course relancee'
  or from=='start' and f.phase~='grid' and 'formation inactive' or frame.length<=0 and 'circuit inconnu'
  -- Relecture 1.64 : au moins un vrai tour de course après le tour en plus et le nouveau départ (course aux tours).
  or (frame.sessionLaps or 0)>0 and not frame.timedRace and (frame.leaderLaps or 0)+2>=frame.sessionLaps and 'course trop courte' or nil
 if why then
  Incidents.clearStartAbort(t)
  U.log(e.log,now,'INFO',string.format('depart retarde impossible (%s): grille annulee',why),-1)
  return false
 end
 local roll=n>K.startAbortMax
 -- Envol comme au feu vert d'AC (moteur) : aucune voiture de la grille prise pour un arrêt (gridStop tombe hors grille) ;
 -- personne ne double jusqu'à la nouvelle grille par la neutralisation seule (comme au tour de formation).
 for i=1,frame.count do
  local c=t.cars[i]; e.states[i].obstacleSlow=0; frame.cars[i].stopped=0; c.restart=false
  if not c.abortMark then c.moved=false; c.halt=0 end
 end
 t.playerRestart=false; t.restart=false
 if from=='start' then
  clear(t,false)
  local rank=t.formationRank or {}; t.formationRank=rank; for k in pairs(rank) do rank[k]=nil end
  local ranked=0
  if not roll then for i=1,frame.count do local k=t.cars[i].abortSlot or 0; if k>0 then rank[i]=k; ranked=ranked+1 end end end
  t.formationRankN=ranked; t.formationAt=now
  arm(f,e,frame,now,roll and 'rolling' or 'formation')
  f.strungFor=0; f.strungLogged=false; f.slowKmh=nil
 else
  t.neutral=true; t.relaunch=true; t.ending=false; t.escalated=false; t.neutralMode=p.neutralization=='vsc' and 'vsc' or 'fcy'; t.neutralSince=now
  t.neutralUntil=now+frame.length/(max(p.fcySpeedKmh or 0,1)/3.6); t.relaunchSpanUntil=now; t.relaunchLeader=0; t.relaunchTravel=0; t.relaunchToLine=math.huge
  t.startAbortRoll=roll
 end
 U.log(e.log,now,'INFO',string.format('depart retarde: depart avorte numero %d, un tour de %s de plus, puis depart %s',n,from=='start' and 'formation' or 'relance',roll and 'lance' or 'arrete'),-1)
 local held=0
 for i=1,frame.count do
  local c=t.cars[i]; local a=frame.cars[i]
  if c.abortMark and (c.abortSlot or 0)>0 and not a.player and a.valid and a.control and not a.pit and not a.finished and not Incidents.brokenReason(a) then
   local behind=false
   for j=1,frame.count do local cj=t.cars[j]; local b=frame.cars[j]; if j~=i and not cj.abortMark and (cj.abortSlot or 0)>c.abortSlot and b.valid and not b.pit and not b.finished then behind=true; break end end
   if behind then c.abortHold=true; c.abortHoldAt=now; held=held+1; U.log(e.log,now,'INFO',string.format('depart retarde: %s retenue sur place jusqu au passage du peloton',a.name),i) end
  end
 end
 t.abortHolds=held
 -- Toujours annoncé (règle « pas de dépassement » jamais sans message). Valeur : numéro du départ avorté ; extra : 0 départ
 -- arrêté après le tour, 1 départ lancé (contrat avec SpotterEnginer).
 Incidents.message(t,'startDelayed',n,roll and 1 or 0)
 return from
end
-- Beta 1.62 : plus grand écart (m) entre deux voitures qui se suivent dans la file (IA en piste, ordre de course) ; renvoie
-- aussi l'avancement (tours) de la dernière voiture devant cet écart. Relecture 1.62 (S2) : le joueur ne compte pas (il
-- ne déclenche rien), aucune fonction créée à chaque image.
local function desc(x,y) return x>y end
-- Correctif 1.63 : abscisses seules (0 à 1), triées ; écarts sur le cercle ; le plus grand est la partie vide du tour
-- (devant la tête, derrière la dernière). Renvoie le plus grand des autres écarts (m), l'abscisse de la voiture juste
-- devant lui et la part de tour de cette voiture jusqu'à la tête (voitures de devant : de l'une à l'autre).
function M.worstGap(f,frame)
 local prog=f.prog; local n=0
 for i=1,frame.count do
  local a=frame.cars[i]
  if a.valid and not a.player and i~=frame.player and not a.pit and not a.finished and not a.safetyCar and a.splineValid then n=n+1; prog[n]=(a.spline or 0)%1 end
 end
 for k=n+1,#prog do prog[k]=nil end
 if n<2 then return 0,nil,0 end
 table.sort(prog,desc)
 -- Écart k : entre prog[k+1] (derrière) et prog[k] (devant) ; écart n : de prog[1] à prog[n] en passant la ligne.
 local empty,emptyK=-1,0
 for k=1,n do local d=k<n and prog[k]-prog[k+1] or prog[n]+1-prog[1]; if d>empty then empty=d; emptyK=k end end
 local lead=emptyK<n and prog[emptyK+1] or prog[1]
 local worst,ahead=0,nil
 for k=1,n do
  if k~=emptyK then
   local d=k<n and prog[k]-prog[k+1] or prog[n]+1-prog[1]
   if d*frame.length>worst then worst=d*frame.length; ahead=prog[k] end
  end
 end
 return worst,ahead,ahead and (lead-ahead)%1 or 0
end
function M.bunch(f,e,frame,now,dt)
 local t=e.incidents
 local gap,ahead,span=M.worstGap(f,frame)
 local late=(t.relaunchTravel or 0)>=K.relaunchTravel and (t.relaunchToLine or math.huge)<=FK.compactFrom
 local limit=late and FK.compactGap or K.formationMaxGap
 if gap>limit then f.strungFor=f.strungFor+(dt or 0) else f.strungFor=0; f.strungLogged=false; f.slowKmh=nil end
 -- Base de l'image : profil d'allure (startRealism, recalculé à chaque image) ou allure fixe du tour ; jamais composé.
 local base=e.run.startRealism and t.formationKmh or M.pace(e.run)
 t.formationKmh=base; t.formationSlowFrom=nil
 -- Affinage 1.63 : panneau et journal : allure du tour (jamais le plafond libre d'un tronçon) ; regroupement à partir
 -- d'une allure réelle (au plus briskMult fois l'allure du tour), jamais du plafond libre.
 t.formationShowKmh=M.pace(e.run); local ref=math.min(base,M.pace(e.run)*FK.briskMult)
 if f.strungFor>=(late and FK.compactTime or K.formationGapTime) and ahead then
  -- Relecture 1.62 (S2) : seules les voitures devant le plus grand écart ralentissent (Incidents.cap) ; celles de
  -- derrière gardent l'allure du tour et recollent.
  -- Correctif 1.63 : abscisse et part de tour des voitures de devant (cercle du tour) ; allure abaissée progressivement.
  t.formationSlowFrom=ahead; t.formationSlowSpan=span
  f.slowKmh=max(ref*K.formationWaitMult,(f.slowKmh or ref)-FK.slowRate*(dt or 0))
  t.formationSlowKmh=f.slowKmh
  if not f.strungLogged then f.strungLogged=true; e.stats.formationStrung=(e.stats.formationStrung or 0)+1; U.log(e.log,now,'INFO',string.format('tour de formation: file etiree (%.0f m entre deux voitures), la tete ralentit',gap),-1) end
 end
end
-- Avant le pilotage de chaque image. Renvoie 'roll' quand la course est lancée sans passer par les feux de la grille.
function M.step(f,e,frame,now,dt)
 if f.phase=='none' then return nil end
 local t=e.incidents
 -- Course relancée par AC, profil changé : plus rien de la formation (le prochain feu vert en commencera une autre).
 if e.profile~='C' or not frame.started then
  if f.phase=='grid' and t.standing~='none' then t.standing='none'; t.gridLit=0 end
  clear(t,true); f.phase='none'; f.report=false
  U.log(e.log,now,'INFO','depart: tour de formation interrompu (course relancee)',-1)
  return nil
 end
 -- Drapeau rouge : sa procédure prend la suite (stands, tour de relance, départ selon les règles).
 if t.red then
  clear(t,false); f.phase='none'; f.report=false
  U.log(e.log,now,'INFO','depart: tour de formation interrompu (drapeau rouge)',-1)
  return nil
 end
 if f.phase=='lap' then
  if t.rollGo then
   t.rollGo=false; f.phase='none'; f.report=false
   if t.rollGreenAt then
    local lead=frame.cars[t.relaunchLeader or 0]
    U.log(e.log,now,'INFO',string.format('depart lance: %s lance le depart a %.0f m de la ligne',lead and lead.name or '?',t.relaunchToLine or 0),-1)
    t.rollGreenAt=nil
   end
   return 'roll'
  end
  -- Beta 1.61 (tranche D) : allure de la tête selon l'endroit du tour (réglage startRealism).
  if t.formation and e.run.startRealism then t.formationKmh=M.profile(e.run,(t.relaunchTravel or 0)*frame.length,t.relaunchToLine or frame.length,frame.length,(e.runtimeG.seed or 0)+f.begun) end
  -- Beta 1.62 (règles de la course) : jamais plus de dix longueurs de voiture entre deux voitures de la file : file
  -- étirée depuis K.formationGapTime s, la tête ralentit (K.formationWaitMult) jusqu'au regroupement.
  if t.formation then M.bunch(f,e,frame,now,dt) else f.strungFor=0; f.strungLogged=false end
  if not t.formation and not t.formationAborted then
   -- Fin du tour : grille en formation (src/grid.lua), sinon état inattendu : la course est lancée.
   if t.standing~='none' then f.phase='grid' else f.phase='none'; f.report=false; return 'roll' end
  elseif t.formation and t.rollCall and not f.called then
   -- Appel du départ lancé : place du joueur et voiture à suivre (pont : valeur = place, extra = indice AC, -1 en tête).
   f.called=true
   local pl=frame.player; local a=pl>0 and frame.cars[pl] or nil
   if a and a.valid and not a.pit then
    local place=(a.position or 0)>=1 and a.position or 0; local ahead=-1
    if place>1 then for j=1,frame.count do local b=frame.cars[j]; if j~=pl and b.valid and not b.pit and not b.safetyCar and b.position==place-1 then ahead=j-1; break end end end
    if place>=1 then Incidents.message(t,'rollStart',place,ahead) end
   end
  end
 elseif f.phase=='grid' then
  -- Grille annulée avant les feux (nouvel incident, grille indisponible) : la course est lancée telle quelle. Feux
  -- éteints : le moteur a noté le départ (f.report remis à faux).
  if t.standing=='none' or t.standing=='go' then
   f.phase='none'
   if f.report then f.report=false; U.log(e.log,now,'INFO','depart: grille annulee apres le tour de formation, la course est lancee',-1); return 'roll' end
  end
 end
 return nil
end
return M
