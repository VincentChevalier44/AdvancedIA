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
function M.new() return {session=-1,phase='none',kind='',called=false,report=false,begun=0,refused=0,prog={},strungFor=0,strungLogged=false} end
function M.reset(f) f.session=-1; f.phase='none'; f.kind=''; f.called=false; f.report=false; f.strungFor=0; f.strungLogged=false end -- (f,now)
function M.rebase() end -- (f,amount) : aucune date gardée
-- Fin de tout état de formation dans les incidents (neutral : la neutralisation de la formation est levée aussi).
local function clear(t,neutral)
 if neutral and (t.formation or t.formationAborted) then t.neutral=false; t.relaunch=false; t.ending=false end
 t.formation=false; t.formationAborted=false; t.rollCall=false; t.rollGo=false; t.formationExtra=0; t.rollGreenAt=nil; t.formationSlowFrom=nil
end
function M.pace(p) return max(p.fcySpeedKmh or 0,K.formationMinKmh)*K.formationSpeedMult end
-- Beta 1.61 (tranche D, réglage startRealism) : allure de la tête selon l'endroit du tour : lente à la sortie de la
-- grille (K.formOutDistance m), vive au milieu, lente sur les K.formBunchDistance derniers mètres (le peloton se
-- regroupe). travel : mètres parcourus par la tête ; toLine : distance de la tête à la ligne.
function M.profile(p,travel,toLine,length)
 local base=M.pace(p)
 if travel<K.formOutDistance then return base*K.formSlowMult end
 if travel>=length*K.relaunchTravel and toLine<=K.formBunchDistance then return base*K.formSlowMult end
 return base*K.formBriskMult
end
-- Feu vert d'AC. Vrai : le tour de formation commence (le moteur reporte le journal du départ et le premier tour).
function M.begin(f,e,frame,now)
 local t=e.incidents; local p=e.run
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
  U.log(e.log,now,'INFO',string.format('depart: grille indisponible (%s) : depart lance apres le tour de formation',e.gridCaps~=true and 'capacites' or 'sens lateral non mesure'),-1)
  kind='rolling'
 end
 -- Relecture : IA seulement (le meneur du tour est une IA) ; sans aucune IA en piste, pas de tour de formation.
 local n=0
 for i=1,frame.count do local a=frame.cars[i]; if a.valid and not a.pit and not a.finished and not a.safetyCar and a.control then n=n+1 end end
 if n==0 then
  f.refused=f.refused+1
  U.log(e.log,now,'INFO',string.format('depart: tour de formation impossible (%s) : depart arrete d AC','aucune IA'),-1)
  return false
 end
 local kmh=M.pace(p)
 t.neutral=true; t.relaunch=true; t.ending=false; t.escalated=false; t.neutralMode='fcy'; t.neutralSince=now; t.neutralUntil=now
 t.relaunchSpanUntil=now; t.relaunchLeader=0; t.relaunchTravel=0; t.relaunchToLine=math.huge
 t.formation=true; t.formationKind=kind; t.formationAborted=false; t.formationExtra=0; t.formationKmh=kmh; t.rollGo=false; t.rollCall=false
 f.phase='lap'; f.kind=kind; f.called=false; f.report=true; f.begun=f.begun+1
 -- Beta 1.61 (tranche D) : la voiture de tête choisit son moment : drapeau vert du départ lancé entre
 -- K.rollZoneFrom m et K.rollGreenBefore m de la ligne (jamais plus tard qu'en 1.60), tiré de la graine.
 t.rollGreenAt=nil
 if p.startRealism then
  if kind=='rolling' then t.rollGreenAt=U.lerp(K.rollGreenBefore,max(K.rollGreenBefore,K.rollZoneFrom),U.unit(e.runtimeG.seed or 0,f.begun,K.anticSalt+7)) end
  t.formationKmh=M.profile(p,0,frame.length,frame.length)
  U.log(e.log,now,'INFO',string.format('tour de formation: depart par rangees, zigzags %s, deux files a %.0f m de la ligne','oui',kind=='rolling' and K.rollCallDistance or 0),-1)
 end
 U.log(e.log,now,'INFO',string.format('depart: tour de formation (%d voitures, %.0f km/h en tete), puis depart %s',n,kmh,kind=='formation' and 'arrete' or 'lance'),-1)
 -- Relecture : toujours annoncé, même messages de drapeau coupés (règle « pas de dépassement » jamais sans message).
 -- Valeur : nombre d'IA ; extra : 0 départ arrêté après le tour, 1 départ lancé (contrat avec SpotterEnginer).
 Incidents.message(t,'formation',n,kind=='formation' and 0 or 1)
 return true
end
-- Beta 1.62 : plus grand écart (m) entre deux voitures qui se suivent dans la file (IA en piste, ordre de course) ; renvoie
-- aussi l'avancement (tours) de la dernière voiture devant cet écart. Relecture 1.62 (S2) : le joueur ne compte pas (il
-- ne déclenche rien), aucune fonction créée à chaque image.
local function desc(x,y) return x>y end
function M.worstGap(f,frame)
 local prog=f.prog; local n=0
 for i=1,frame.count do
  local a=frame.cars[i]
  if a.valid and not a.player and i~=frame.player and not a.pit and not a.finished and not a.safetyCar and a.splineValid then n=n+1; prog[n]=(a.lap or 0)+(a.spline or 0) end
 end
 for k=n+1,#prog do prog[k]=nil end
 if n<2 then return 0,nil end
 table.sort(prog,desc)
 local worst,ahead=0,nil
 for k=1,n-1 do local d=(prog[k]-prog[k+1])*frame.length; if d>worst then worst=d; ahead=prog[k] end end
 return worst,ahead
end
function M.bunch(f,e,frame,now,dt)
 local t=e.incidents
 local gap,ahead=M.worstGap(f,frame)
 if gap>K.formationMaxGap then f.strungFor=f.strungFor+(dt or 0) else f.strungFor=0; f.strungLogged=false end
 -- Base de l'image : profil d'allure (startRealism, recalculé à chaque image) ou allure fixe du tour ; jamais composé.
 local base=e.run.startRealism and t.formationKmh or M.pace(e.run)
 t.formationKmh=base; t.formationSlowFrom=nil
 if f.strungFor>=K.formationGapTime and ahead then
  -- Relecture 1.62 (S2) : seules les voitures devant le plus grand écart ralentissent (Incidents.cap) ; celles de
  -- derrière gardent l'allure du tour et recollent.
  t.formationSlowFrom=ahead; t.formationSlowKmh=base*K.formationWaitMult
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
  if t.formation and e.run.startRealism then t.formationKmh=M.profile(e.run,(t.relaunchTravel or 0)*frame.length,t.relaunchToLine or frame.length,frame.length) end
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
