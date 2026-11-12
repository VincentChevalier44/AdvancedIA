-- Beta 1.59 (décision du pilote, réglage damagePit, section Accidents, coupé par défaut) : arrêt aux stands pour dégâts,
-- en course, essais et qualifications. Avant, une IA endommagée qui roulait encore près de son allure n'était jamais
-- appelée : ses dégâts n'étaient même pas lus au-dessus de 25 km/h (src/snapshot.lua). Réglage allumé, ils sont lus en
-- roulant, une IA par image (a.damageScan), au plus toutes les K.damagePitScanPeriod s par IA. Champs de CSP lus :
-- damage[] (carrosserie, km/h d'impact), suspensionDamage[] (0 à 1), gearboxDamage (0 à 1), engineLifeLeft (1000 neuf).
-- Appel quand un seuil est dépassé pendant K.damagePitConfirm s : jamais sous drapeau rouge ; jamais sous drapeau jaune,
-- neutralisation ou stands fermés, sauf voiture dangereuse (suspension) ; la boîte n'appelle pas, elle est
-- seulement écrite au journal (décision de la 1.59) ; en course, jamais dans les
-- K.damagePitMinLapsLeft derniers tours ; dans la limite d'appels partagée (compté comme cmd.slowCalled par
-- src/pits.lua et src/strategy.lua). Réparée à son emplacement : en course, même sans réparations réglementaires ;
-- hors course, par la réparation des IA endommagées à leur emplacement (src/engine.lua). Un appel par épisode ; après
-- un passage aux stands, appelée de nouveau seulement si les dégâts ont encore augmenté.
local C=require('src/config')
local K=C.K
local U=require('src/util')
local M={}
local function fresh(c,id)
 c.id=id; c.body=0; c.susp=0; c.gear=0; c.engine=K.engineLifeNew; c.scanAt=-math.huge; c.overSince=nil
 c.asked=false; c.visited=false; c.base=nil; c.waitLogged=false
end
function M.step(e,frame,now,red)
 local p=e.run
 local on=p.damagePit and p.section_accidents and not C.solo(e.profile) and frame.started==true
 local d=e.damagePit
 if not on then
  -- Réglage coupé : aucune lecture en roulant, aucun appel (rien n'est touché tant qu'il n'a jamais servi).
  if d and d.any then for i=1,frame.count do frame.cars[i].damageScan=false; e.commands[i].damageCalled=false end; d.any=false end
  return
 end
 -- Relecture 1.59 : remis à zéro aussi quand la même séance redémarre (e.raceGen, src/engine.lua).
 local gen=e.raceGen or 0
 if not d or d.session~=frame.session or d.gen~=gen then d={session=frame.session,gen=gen,cars={},next=1,any=false}; e.damagePit=d end
 d.any=true
 local race=e.profile=='C'
 -- Appels déjà en cours hors de la voie des stands (règles, stratégie, sanctions, IA lente) : limite partagée.
 local requested=0
 for i=1,frame.count do
  local a=frame.cars[i]; local cmd=e.commands[i]
  -- Relecture 1.59 : appels pour dégâts encore en cours comptés (leurs drapeaux viennent d'être remis à zéro).
  if not a.pit and (cmd.rulePit or cmd.stratCalled or cmd.sanCalled or cmd.slowCalled or (d.cars[i] and d.cars[i].asked)) then requested=requested+1 end
 end
 for i=1,frame.count do
  local a=frame.cars[i]; local cmd=e.commands[i]
  cmd.damageCalled=false
  local id=a.identity or a.id
  local c=d.cars[i]
  if not c then c={}; fresh(c,id); d.cars[i]=c elseif c.id~=id then fresh(c,id) end
  -- Dégâts lus à cette image (lecture en roulant demandée à l'image précédente, à l'emplacement, à basse vitesse).
  if a.damageScan or a.inPitBox or (a.kmh or 0)<K.damageReadSpeed or a.watchDamage then
   c.body=a.damageBody or 0; c.susp=a.damageSuspension or 0; c.gear=a.damageGearbox or 0; c.engine=a.engineLife or K.engineLifeNew
  end
  a.damageScan=false
  if a.valid and a.control and not a.player and not a.finished and not a.safetyCar then
   -- Relecture 1.59 : à l'emplacement pour une autre raison avec des dégâts au-delà d'un seuil : réparée aussi (sinon
   -- rappelée aussitôt). La boîte de vitesses n'a pas de réparation (journal seulement).
   local damaged=c.body>=K.damagePitBody or c.susp>=K.damagePitSuspension or c.engine<=K.damagePitEngine
   if a.inPitBox and (c.asked or damaged) then c.asked=false; c.visited=true; c.overSince=nil end
   -- Sortie de la voie après l'appel : dégâts relevés à l'emplacement (après réparation) gardés comme référence.
   if c.visited and not a.pit then c.visited=false; c.base={body=c.body,susp=c.susp,gear=c.gear,engine=c.engine} end
   if race and c.visited and a.inPitBox then cmd.pitRepair=true end
   if not a.pit then
    local over=damaged
    local b=c.base
    if over and b then
     over=c.body-b.body>=K.damagePitRegrowBody or c.susp-b.susp>=K.damagePitRegrowSuspension or b.engine-c.engine>=K.damagePitRegrowEngine
    end
    if over then c.overSince=c.overSince or now else c.overSince=nil; c.waitLogged=false end
    local unsafe=c.susp>=K.damagePitUnsafe
    local lapsOk=not race or (e.race.lapsLeft or -1)<0 or e.race.lapsLeft>=K.damagePitMinLapsLeft
    local held=c.overSince~=nil and now-c.overSince>=K.damagePitConfirm
    local busy=cmd.rulePit or cmd.stratCalled or cmd.sanCalled or cmd.slowCalled or cmd.recover or cmd.penaltyPass
    if held and lapsOk and not c.asked and not red and not busy then
     local flagged=e.incidents.neutral or e.incidents.pitsClosed or e.states[i].yellow
     if flagged and not unsafe then
      if not c.waitLogged then c.waitLogged=true; U.log(e.log,now,'INFO',string.format('degats: %s attend la fin du drapeau pour rentrer',a.name),i) end
     elseif requested<K.pitConcurrent then
      c.asked=true; requested=requested+1
      U.log(e.log,now,'INFO',string.format('degats: %s appelee aux stands (carrosserie %.0f km/h, suspension %.2f, boite %.2f, moteur %.0f)',a.name,c.body,c.susp,c.gear,c.engine),i)
     end
    end
    if c.asked and not red and not (e.incidents.pitsClosed and not unsafe) then cmd.rulePit=true; cmd.slowCalled=true; cmd.damageCalled=true end
   end
  end
 end
 -- Lecture en roulant : une IA par image, chacune au plus toutes les K.damagePitScanPeriod s.
 local n=frame.count
 for step=0,n-1 do
  local j=(d.next-1+step)%n+1
  local a=frame.cars[j]; local c=d.cars[j]
  if c and a.valid and a.control and not a.player and not a.finished and not a.safetyCar and not a.pit and now-c.scanAt>=K.damagePitScanPeriod then
   a.damageScan=true; c.scanAt=now; d.next=j%n+1; break
  end
 end
end
-- Relecture 1.59 : horloge du moteur recalée (src/engine.lua, M.rebase).
function M.rebase(d,amount)
 if not d then return end
 for _,c in pairs(d.cars) do
  if c.scanAt>-math.huge then c.scanAt=c.scanAt-amount end
  if c.overSince then c.overSince=c.overSince-amount end
 end
end
return M
