-- Beta 1.60 (tranche A). Conscience de l'arrière et régulateur « sans coup de frein ».
--   M.scan (appelé par src/director.lua à chaque perception, 10 Hz) : s.rearClose (voiture collée derrière, calculé
--     pour tous : le régulateur n'a pas de réglage), s.rearCloseBy, s.rearCloseGap ; avec le réglage rearAwareness :
--     côtés où une voiture plus rapide sera à hauteur dans l'horizon (s.rearLeftUntil, s.rearRightUntil, s.rearSideBy).
--   M.govern (dernier appel de l'image, src/engine.lua) : avec une voiture collée derrière, chaque ralentissement
--     ajouté par l'app est borné et étalé par rapport à la valeur laissée passer à l'image précédente (s.gov*).
--     Jamais sous drapeau, neutralisation, voie des stands, évitement, incident, ni devant un obstacle imminent.
-- Aucune fonction de CSP, aucune table ni chaîne créée par image.
local C=require('src/config')
local U=require('src/util')
local K=C.K
local abs,min,max=math.abs,math.min,math.max
local M={}
function M.new() return {session=-1} end
function M.reset(t) t.session=-1 end -- (t,now)
function M.rebase() end -- (t,amount) : les heures tenues par voiture (côtés, journal) se bornent seules (voir M.side).
function M.update() end -- (t,e,frame,now,dt) : rien avant le pilotage, la perception de l'image est lue par M.scan.
-- Voiture collée derrière : la plus proche derrière dans la même file (row.back : |lat| <= K.latYield), à moins de
-- max(K.rearCloseMin, vitesse du suiveur x K.rearCloseTime) m, qui ne s'éloigne pas de plus de K.rearCloseSa km/h. Le
-- joueur compte.
function M.close(row,cars)
 local back=row.back>0 and row.neighbors[row.back] or nil
 if back and back.long<0 and back.gap<max(K.rearCloseMin,cars[back.index].speed*K.rearCloseTime) and back.sa>=-K.rearCloseSa then return back end
 return nil
end
-- Horizon de la conscience de l'arrière (s) : K.rearHorizonMax pour le pilote le plus attentif (temps de perception
-- le plus court du profil), K.rearHorizonMin pour le moins attentif.
function M.horizon(s,p)
 local span=(p.awMax or 0)-(p.awMin or 0)
 local slow=span>0 and U.clamp(((s.persona.awareness or 0)-p.awMin)/span,0,1) or 0.5
 return U.lerp(K.rearHorizonMax,K.rearHorizonMin,slow)
end
-- Côté (-1 gauche, 1 droite) où une voiture plus rapide arrive (tenu K.rearHold s ; borné : un recalage de l'horloge
-- ne le prolonge pas).
function M.side(s,side,now)
 local untilTime=side<0 and s.rearLeftUntil or side>0 and s.rearRightUntil or nil
 return untilTime~=nil and now<untilTime and untilTime-now<=K.rearHold
end
function M.scan(e,i,row,p,g,now)
 local s=e.states[i]; local cars=e.frame.cars
 local back=M.close(row,cars)
 s.rearClose=back~=nil; s.rearCloseBy=back and back.index or 0; s.rearCloseGap=back and back.gap or 0
 if not p.rearAwareness then return end
 local horizon=M.horizon(s,p)
 for j=1,row.count do
  local r=row.neighbors[j]
  -- Voiture derrière, pas encore à hauteur, qui se rapproche et sera à hauteur dans l'horizon, nettement d'un côté.
  if r.long<0 and r.gap>=0 and r.sa>=K.rearMinSa and r.gap/(r.sa/3.6)<=horizon then
   local lat=abs(r.lat)
   if lat>=g.occLatMin and lat<=g.occLatMax then
    if r.lat>0 then s.rearLeftUntil=now+K.rearHold else s.rearRightUntil=now+K.rearHold end
    s.rearSideBy=r.index; s.rearSideIn=r.gap/(r.sa/3.6); s.rearSideSa=r.sa
   end
  end
 end
end
-- Vrai quand le régulateur ne doit rien toucher : règles et sécurité d'abord.
local function exempt(e,a,s,cmd,now)
 -- Départ et premier tour attentif : leurs propres règles pour une voiture collée derrière (Beta 1.47 à 1.59).
 if (s.flW or 0)>0 then return true end
 if e.profile=='C' and now-max(e.startedAt or -math.huge,e.launchAt or -math.huge)<e.run.startDelay+e.run.startRelax then return true end
 if not cmd.active or a.player or not a.valid or a.pit or a.finished or s.disqualified or s.excluded then return true end
 if s.yellow or e.incidents.neutral or e.incidents.red then return true end
 if s.state=='AVOID' or s.state=='CALM' or s.state=='IDLE' then return true end
 if cmd.stopHold or cmd.pitHold or cmd.rulePit or cmd.scPark or cmd.recover or (cmd.scSpeed or K.unlimitedSpeed)<K.unlimitedSpeed then return true end
 local ic=e.incidents.cars[a.slot]
 if ic and ic.incident then return true end
 -- Sanction en cours (coupure des gaz d'une IA, src/sanctions.lua) : une pénalité se purge telle quelle.
 local sc=e.sanctions and e.sanctions.cars[a.slot]
 if sc and sc.cutLimit<1 then return true end
 if e.profile=='C' and not e.frame.started then return true end
 -- Relecture : grille d'un départ arrêté de l'app qui se forme (voitures freinées vers leur place), protection de la
 -- sortie des stands (limite derrière une voiture en piste).
 local standing=e.incidents.standing
 if standing~=nil and standing~='none' then return true end
 if now<(s.pitGuardUntil or 0) then return true end
 return false
end
-- Compteurs par épisode : total (résumé de la minute) et par commande adoucie (audit des journaux).
local govKeys={['frein radar']='rearGovBrake',['lever de pied']='rearGovThrottle',['limite de vitesse']='rearGovCap',niveau='rearGovLevel',prudence='rearGovCaution'}
local function note(e,s,a,what,now)
 if not s.govActive then
  s.govActive=true; e.stats.rearGoverned=(e.stats.rearGoverned or 0)+1
  local key=govKeys[what]; e.stats[key]=(e.stats[key] or 0)+1
 end
 if e.runtimeG.debugLog and (now>=(s.govLogAt or -math.huge) or s.govLogAt-now>K.radarLogPeriod) then
  s.govLogAt=now+K.radarLogPeriod
  local f=e.frame.cars[s.rearCloseBy]
  U.log(e.log,now,'DEBUG',string.format('adouci: %s %s devant %s (%.0f m)',a.name,what,f and f.name or '?',s.rearCloseGap or 0),a.slot)
 end
end
function M.govern(_,e,frame,now,dt)
 if not e or not frame then return end
 for i=1,frame.count do
  local a=frame.cars[i]; local s=e.states[i]; local cmd=e.commands[i]
  if not a.player then
   local free=not s.rearClose or exempt(e,a,s,cmd,now)
   -- Obstacle imminent devant (contact à moins de K.rearLastTtc s) : dernier recours, rien n'est adouci.
   -- Relecture (le frein était plafonné pour presque toute une file) : jugé sur la cible du radar elle-même
   -- (s.radarTTC, s.radarSa, s.radarIndex, src/director.lua) : jamais adouci pour un vrai obstacle (approche d'au moins
   -- K.radarStraightObstacleKmh km/h, voiture en incident ou anormalement lente) ni à moins de K.rearLastTtc s du contact.
   if not free then
    local row=e.perception.rows[i]; local front=row.front>0 and row.neighbors[row.front] or nil
    if front and front.long>0 and front.ttc<K.rearLastTtc then free=true end
    local j=s.radarIndex or 0
    if j>0 then
     local ic=e.incidents.cars[j]; local js=e.states[j]
     if (s.radarTTC or math.huge)<K.rearLastTtc or (s.radarSa or 0)>=K.radarStraightObstacleKmh or ic and ic.incident or js and js.abnormal==true then free=true end
    end
   end
   if free or s.govThrottle==nil then
    s.govActive=false
   else
    local touched=nil
    -- Frein ajouté par le radar : au plus K.rearBrakeMax, et le lever de pied d'abord (en ligne droite seulement :
    -- jamais de coupure des gaz en virage).
    if (cmd.brake or 0)>K.rearBrakeMax then
     cmd.brake=K.rearBrakeMax; s.appBrake=min(s.appBrake or 0,K.rearBrakeMax); s.radarBrake=min(s.radarBrake or 0,K.rearBrakeMax)
     if (a.corner or 1)>=e.run.cornerMin then cmd.throttleLimit=min(cmd.throttleLimit or 1,K.rearThrottleFloor) end
     touched='frein radar'
    end
    -- Plafond d'accélérateur : descente d'au plus K.rearThrottleRate par seconde, jamais sous K.rearThrottleFloor.
    local throttle=cmd.throttleLimit or 1
    local floor=max(K.rearThrottleFloor,s.govThrottle-K.rearThrottleRate*dt)
    -- Relecture : plafond voulu d'une panne (src/strategy.lua) : jamais relevé au-dessus de lui.
    local sc=e.strategy and e.strategy.cars and e.strategy.cars[i]
    if sc and sc.failCeilAt==now and sc.failCeil<floor then floor=sc.failCeil end
    if throttle<floor then cmd.throttleLimit=floor; touched=touched or 'lever de pied' end
    -- Limite de vitesse de l'app : part de la vitesse de la voiture, descend d'au plus K.rearCapDecel km/h par seconde.
    local cap=cmd.speedLimit or K.unlimitedSpeed
    if cap<K.unlimitedSpeed then
     local from=min(s.govCap,a.kmh)
     local allowed=from-K.rearCapDecel*dt
     if cap<allowed then cmd.speedLimit=allowed; touched=touched or 'limite de vitesse' end
    end
    -- Facteur de niveau des modules (tour de sortie, panne, stratégie, usure, humeur : cmd.levelScale) : descente d'au
    -- plus K.rearLevelRate par seconde, jamais au-dessus de 1. Le niveau du directeur (cmd.level), déjà lissé, n'est
    -- pas touché : le relever sortirait l'IA de ses bornes (départ d'une session, changement de niveau de base).
    local lowest=min(1,s.govScale-K.rearLevelRate*dt)
    if (cmd.levelScale or 1)<lowest then cmd.levelScale=lowest; touched=touched or 'niveau' end
    -- Prudence (elle fait freiner AC pour l'écart) : montée d'au plus K.rearCautionRate par seconde, en ligne droite et
    -- hors freinage seulement (au freinage et en virage, la prudence remonte vite exprès : Beta 1.31, têtes-à-queue).
    local highest=s.govCaution+K.rearCautionRate*dt
    if (cmd.caution or 1)>highest and (a.corner or 1)>=e.run.cornerMin and (a.brake or 0)<=K.ruleBrake then cmd.caution=highest; touched=touched or 'prudence' end
    if touched then note(e,s,a,touched,now) else s.govActive=false end
   end
   s.govThrottle=cmd.throttleLimit or 1; s.govCap=cmd.speedLimit or K.unlimitedSpeed
   s.govScale=cmd.levelScale or 1; s.govCaution=cmd.caution or 1
  end
 end
end
return M
