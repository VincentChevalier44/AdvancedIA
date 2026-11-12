-- Beta 1.51 (demande du pilote, qualifications) : essais et qualifications, tours lancés. Une IA sortie des stands
-- forçait le passage devant le joueur en plein tour rapide. Comme en F1 : tour de sortie (pneus à chauffer), tours
-- lancés, tour de refroidissement ; une voiture qui n'est pas lancée se pousse devant une voiture lancée qui arrive,
-- ne l'attaque jamais, et ne sort pas des stands juste devant elle ; le joueur pas lancé est prévenu qu'une IA lancée
-- arrive. Décisions pures : le directeur (cession, dépassement), la sortie des stands (src/merge.lua) et le moteur
-- (avis au joueur) lisent t.push.
--   t.active  : profil Essais ou Qualifications, réglage qualiTraffic, ni drapeau rouge ni neutralisation ;
--   t.push[i] : voiture i en tour lancé (faux hors de t.active).
local U=require('src/util')
local K=require('src/config').K
local Delta=require('src/delta')
-- Beta 1.52 : avis au joueur (message de l'overlay), résolu une fois (aucune dépendance circulaire).
local Incidents=require('src/incidents')
local max,min=math.max,math.min
local M={}
-- Beta 1.51 : planned (refroidissement prévu d'une IA, niveau abaissé), pushLaps (tours lancés de suite), lapSeen (tour
-- vu à l'image d'avant), wasPush, coolAt et coolEnd (début du refroidissement prévu, fin et retour du niveau).
-- Beta 1.52 : why, raison d'une voiture pas lancée pour le journal ('' si lancée).
-- Beta 1.55 : catchT et catchG (relevés de l'écart en temps au joueur, au même point de la piste), catchN, catchBin (case
-- du dernier relevé), candAt (arrivée
-- à qualiWarnTime s au plus), candOut (hors de portée depuis), candLogged (refus noté).
local function car() return {seen=false,wasPit=false,out=false,outLap=-1,exitAt=-math.huge,cool=false,coolLap=-1,slow=0,warnAt=-math.huge,
 planned=false,pushLaps=0,lapSeen=-1,wasPush=false,coolAt=-math.huge,coolEnd=-math.huge,why='',outEnd=-math.huge,outLogged=false,outPit=false,
 catchT={},catchG={},catchN=0,catchBin=0,candAt=-math.huge,candOut=0,candLogged=false,
 -- Beta 1.62 (règles des qualifications) : yellowLap (tour lancé passé sous drapeau jaune), faultyLap (dernier tour
 -- lancé fautif, refait), gapDrop (baisse pour rouvrir l'écart en tour de sortie), jOut (tour de chauffe en journée
 -- circuit), jExitAt, jEnd.
 yellowLap=-1,faultyLap=-1,gapDrop=0,gapLogged=false,jOut=false,jExitAt=-math.huge,jEnd=-math.huge,jLap=-1,jWasPit=false,jCool=false,jCoolAt=-math.huge,jCoolEnd=-math.huge} end
function M.new()
 local t={active=false,push={},cars={},logAt=-math.huge,playerAt={},playerBin=0}
 for i=1,K.maxCars do t.cars[i]=car(); t.push[i]=false end
 return t
end
function M.reset(t)
 t.active=false; t.logAt=-math.huge; t.playerAt={}; t.playerBin=0
 for i=1,K.maxCars do t.cars[i]=car(); t.push[i]=false end
end
function M.rebase(t,amount)
 if U.finite(t.logAt) then t.logAt=t.logAt-amount end
 for b,v in pairs(t.playerAt) do t.playerAt[b]=v-amount end
 for i=1,K.maxCars do
  local c=t.cars[i]
  if U.finite(c.exitAt) then c.exitAt=c.exitAt-amount end
  if U.finite(c.warnAt) then c.warnAt=c.warnAt-amount end
  if U.finite(c.coolAt) then c.coolAt=c.coolAt-amount end
  if U.finite(c.coolEnd) then c.coolEnd=c.coolEnd-amount end
  if U.finite(c.outEnd) then c.outEnd=c.outEnd-amount end
  if U.finite(c.candAt) then c.candAt=c.candAt-amount end
  if U.finite(c.jExitAt) then c.jExitAt=c.jExitAt-amount end
  if U.finite(c.jEnd) then c.jEnd=c.jEnd-amount end
  if U.finite(c.jCoolAt) then c.jCoolAt=c.jCoolAt-amount end
  if U.finite(c.jCoolEnd) then c.jCoolEnd=c.jCoolEnd-amount end
  for k=1,c.catchN do c.catchT[k]=c.catchT[k]-amount end
 end
end
local function name(a) return a and a.name or '?' end
-- Allure de la flotte (classe de la voiture) à l'endroit de a, corrigée de son rythme de longue durée (borné) : la
-- référence du tour de refroidissement ; 0 inconnue. Jamais l'allure apprise de la voiture elle-même (elle suit sa
-- vitesse du moment quand elle ralentit).
function M.reference(e,s,a,multi)
 local f=e.delta.fleet[multi and s.class or 1]
 if not f or not a.splineValid then return 0 end
 local v=f[Delta.bin(a.spline,e.delta.bins)] or 0
 return v*U.clamp(s.longRatio or 1,K.qualiCoolPaceMin,1)
end
-- Nombre de tours lancés de suite avant le refroidissement d'une IA (tiré une fois par IA et par graine).
function M.target(seed,i) return K.qualiPushMin+math.floor(U.unit(seed,i,K.qualiCoolSalt)*(K.qualiPushMax-K.qualiPushMin+1)) end
-- Assez de temps pour un refroidissement puis un tour lancé (temps restant inconnu : oui).
local function timeForCool(frame,a)
 if not (frame.left and frame.left>0) then return true end
 local lap=max(K.qualiCoolLapMin,a.lastLap or 0,a.bestLap or 0)
 return frame.left>K.qualiCoolLate*lap
end
-- Une fois par image, avant le pilotage.
function M.update(t,e,frame,now,dt)
 local p=e.run; local profile=e.profile; local inc=e.incidents
 t.active=(profile=='P' or profile=='Q') and p.qualiTraffic==true and not inc.red and not inc.neutral and not frame.replay and not frame.online
 -- Beta 1.52 : hors essais et qualifications (journée circuit, course, hotlap), rien à suivre : personne n'est lancé,
 -- seuls le passage aux stands et le tour vu sont tenus à jour ; état oublié (revu à la première vue au retour).
 if profile~='P' and profile~='Q' then
  for i=1,frame.count do
   local a=frame.cars[i]; local c=t.cars[i]
   -- Beta 1.62 (règles de la journée circuit) : tour de chauffe progressif après une vraie sortie des stands.
   if profile=='J' then M.trackDayOut(c,e,a,i,p,now) else c.jOut=false end
   c.wasPit=a.pit==true; c.lapSeen=a.lap or 0; c.seen=false; c.cool=false; c.planned=false; c.slow=0; c.pushLaps=0; c.wasPush=false; c.why=''
   t.push[i]=false; e.states[i].qualiNoLearn=false
  end
  for i=frame.count+1,K.maxCars do t.push[i]=false end
  return
 end
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]; local s=e.states[i]
  local lap=a.lap or 0
  if not c.seen then
   -- Première vue : voie des stands (tour de sortie à la sortie) ou déjà en piste (posée par l'app, rechargement) :
   -- tour de sortie jusqu'à la ligne.
   -- Relecture (S10) : déjà en piste à la première vue (rechargement de l'app) : classée sans la baisse de niveau
   -- du tour de chauffe (c.exitAt ancien : la rampe et le rendu de K.qualiOutLevel sont déjà passés).
   c.seen=true; c.wasPit=a.pit==true; c.out=true; c.outLap=a.pit and -1 or lap; c.exitAt=now; c.noDrop=not a.pit
  end
  if a.pit then
   c.out=true; c.outLap=-1; c.cool=false; c.slow=0; c.planned=false; c.pushLaps=0
  elseif c.wasPit or a.teleport then
   c.out=true; c.outLap=lap; c.exitAt=now; c.cool=false; c.slow=0; c.outPit=c.wasPit==true; c.noDrop=false
  end
  c.wasPit=a.pit==true
  if c.out and not a.pit and c.outLap>=0 and lap>c.outLap then
   -- Ligne passée juste après la sortie (ligne placée après la sortie des stands) : le tour de sortie continue.
   if now-c.exitAt<K.qualiOutGrace then c.outLap=lap else c.out=false; c.outEnd=now; c.outLogged=false; c.outPit=false end
  end
  -- Beta 1.62 (décision 3 du pilote) : tour lancé passé sous drapeau jaune (relevé pour le tour en cours).
  if c.wasPush and not a.player and s.yellow then c.yellowLap=lap end
  -- Tour de refroidissement (ou tour abandonné) : nettement plus lente que sa référence ici, jusqu'à la ligne.
  local prevLap=c.lapSeen
  local crossed=c.lapSeen>=0 and lap>c.lapSeen
  c.lapSeen=lap
  if not c.out and not a.pit then
   if c.cool and lap>c.coolLap then
    if c.planned then c.coolEnd=now end
    c.cool=false; c.slow=0; c.planned=false
   end
   -- Beta 1.51 : qualifications, IA pilotée : après sa série de tours lancés, un tour de refroidissement prévu.
   -- Beta 1.52 : série remise à zéro par un tour qui n'était pas lancé (tours lancés de suite seulement) ; refroidissement
   -- prévu seulement avec l'onglet Général (sans lui, le niveau n'est pas commandé : la voiture roulerait un tour entier
   -- à pleine vitesse sans être lancée).
   if crossed and not c.wasPush then c.pushLaps=0 end
   -- Beta 1.62 (décision 3 du pilote) : qualifications, IA pilotée : tour lancé fautif (tour invalidé par les limites de
   -- piste, src/sanctions.lua, ou passé sous drapeau jaune) : il ne compte pas dans la série, la voiture refait un tour
   -- lancé au lieu de son refroidissement ; son temps reste au classement d'AC (l'app ne peut pas l'effacer).
   local why=crossed and c.wasPush and profile=='Q' and t.active and a.control and not a.player and M.faulty(c,e,i,prevLap) or nil
   if why then
    c.faultyLap=prevLap; e.stats.qualiRedo=(e.stats.qualiRedo or 0)+1
    U.log(e.log,now,'INFO',string.format('tour refait: %s (%s), un autre tour lance',name(a),why),i)
   elseif crossed and c.wasPush then
    c.pushLaps=c.pushLaps+1
    if t.active and profile=='Q' and p.qualiCoolLaps and not p.qualiRuns and p.section_general and a.control and not a.player and c.pushLaps>=M.target(e.runtimeG.seed,i) and timeForCool(frame,a) then
     c.cool=true; c.planned=true; c.coolLap=lap; c.coolAt=now; c.pushLaps=0
     e.stats.qualiCool=(e.stats.qualiCool or 0)+1
     if now>=t.logAt then t.logAt=now+K.qualiLogGap; U.log(e.log,now,'INFO',string.format('tour de refroidissement: %s (niveau -%.0f %%)',name(a),K.qualiCoolLevel*100),i) end
    end
   end
   local ref=M.reference(e,s,a,p.multiClass)
   -- Retenue derrière une voiture (à moins de K.followRange m) : jamais un refroidissement (elle perdrait sa priorité au
   -- moment où elle en a besoin).
   local row=e.perception.rows[i]
   local held=row and row.front>0 and row.neighbors[row.front].gap<=K.followRange
   -- Beta 1.52 : drapeau jaune du joueur lu dans src/incidents.lua (s.yellow n'est tenu que pour les IA).
   local yellow=a.player and (inc.playerYellow or inc.playerZone) or not a.player and s.yellow
   if not c.cool and ref>0 and a.speed<ref*K.qualiCoolRatio and not held and not yellow and not (s.state=='YIELD_IN' or s.state=='YIELD_HOLD') then
    c.slow=c.slow+dt
    if c.slow>=K.qualiCoolTime then c.cool=true; c.coolLap=lap end
   elseif not c.cool then c.slow=0 end
  end
  local cmd=e.commands[i]
  -- Pas lancée : tour de sortie, refroidissement, voie des stands, appelée aux stands (tour de rentrée), anormalement
  -- lente (dégâts), arrivée, ou à l'arrêt.
  local inLap=not a.player and (cmd.rulePit or cmd.sanCalled or cmd.stratCalled)
  -- Niveau abaissé pendant le refroidissement prévu (montée en qualiCoolRamp s), rendu en qualiCoolRelease s après la ligne.
  -- Beta 1.52 : tours lancés coupés (drapeau rouge) pendant un refroidissement prévu : il s'achève, le niveau revient
  -- par la même rampe (jamais d'un coup) et aucun ancien début n'est repris au retour.
  if not t.active and c.planned and c.cool then c.coolEnd=now; c.cool=false; c.planned=false; c.slow=0 end
  local drop=0
  if t.active and c.planned and c.cool then drop=K.qualiCoolLevel*min(1,(now-c.coolAt)/K.qualiCoolRamp)
  elseif now-c.coolEnd<K.qualiCoolRelease then drop=K.qualiCoolLevel*(1-(now-c.coolEnd)/K.qualiCoolRelease) end
  if drop>0 and a.control and not a.player then cmd.levelScale=(cmd.levelScale or 1)*(1-drop) end
  -- Beta 1.60 (lot 3, demande du pilote : tours de chauffe impossibles à distinguer des tours lancés) : tour de sortie
  -- des essais et qualifications (de la sortie des stands à la ligne), IA pilotée, onglet Général : niveau abaissé de
  -- K.qualiOutLevel (montée en K.qualiOutRamp s, rendu en K.qualiCoolRelease s après la ligne) ; s'ajoute à la chauffe
  -- des pneus (réglage outLapLevelPct). Jamais dans la voie des stands ; tours lancés coupés : rendu par la même rampe.
  local outNow=t.active and c.out and c.outLap>=0 and not a.pit
  if not outNow and c.outLogged then c.outEnd=now; c.outLogged=false end
  -- Relecture du lot 3 (N8) : tours lancés rétablis après une coupure (drapeau rouge) : la baisse reprend du niveau
  -- où le rendu en était (avant : d'un coup, la rampe était mesurée depuis l'ancienne sortie des stands).
  if outNow and not c.outOn and c.outEnd and c.outEnd>c.exitAt then
   local f=now-c.outEnd<K.qualiCoolRelease and 1-(now-c.outEnd)/K.qualiCoolRelease or 0
   c.outFrom=now-f*K.qualiOutRamp
  end
  c.outOn=outNow
  local outDrop=0
  if outNow and c.noDrop then outDrop=0
  elseif outNow then outDrop=K.qualiOutLevel*min(1,(now-max(c.exitAt,c.outFrom or -math.huge))/K.qualiOutRamp)
  elseif now-c.outEnd<K.qualiCoolRelease then outDrop=K.qualiOutLevel*(1-(now-c.outEnd)/K.qualiCoolRelease) end
  if outDrop>0 and a.control and not a.player and p.section_general then
   cmd.levelScale=(cmd.levelScale or 1)*(1-outDrop)
   if outNow and not c.outLogged then
    c.outLogged=true; e.stats.qualiOut=(e.stats.qualiOut or 0)+1
    -- Une ligne par vraie sortie des stands (voitures vues en piste au début de la séance ou au rechargement : aucune
    -- ligne, vingt lignes dans la même seconde videraient le quota du journal).
    if c.outPit then U.log(e.log,now,'INFO',string.format('tour de chauffe: %s (niveau -%.0f %%)',name(a),K.qualiOutLevel*100),i) end
   end
  end
  -- Beta 1.62 (décision 4 du pilote) : tour de sortie, voiture devant à moins de K.qualiExitGap s : baisse de niveau
  -- bornée pour rouvrir l'écart avant le tour lancé, seulement dans la première partie du tour (avant K.qualiGapUntil
  -- du tour) et jamais avec une voiture lancée qui arrive derrière (jamais de ralenti dans le dernier secteur). Baisse
  -- totale du tour de sortie au plus K.qualiOutMaxDrop (pas de ralenti inutile).
  M.exitGap(t,e,a,c,i,cmd,outNow and not c.noDrop and p.section_general,outDrop,now,dt)
  t.push[i]=t.active and a.valid and not a.pit and not a.finished and not a.safetyCar and not c.out and not c.cool and not inLap
   and not s.abnormal and a.kmh>=K.qualiCoolMinKmh or false
  c.wasPush=t.push[i]
  -- Beta 1.52 : raison d'une voiture pas lancée (journal des cessions et de l'avis au joueur).
  c.why=t.push[i] and '' or a.pit and 'stands' or c.out and 'tour de sortie' or c.cool and 'refroidissement' or inLap and 'tour de rentree'
   or s.abnormal and 'endommagee' or a.kmh<K.qualiCoolMinKmh and 'trop lente' or ''
  -- Beta 1.52 : IA pas lancée pendant les tours lancés : allure habituelle pas apprise (src/director.lua).
  s.qualiNoLearn=t.active and not t.push[i] and not a.player
 end
 for i=frame.count+1,K.maxCars do t.push[i]=false end
 if not t.active then return end
 -- Avis au joueur pas lancé : IA lancée qui arrive derrière lui (à qualiWarnTime s au plus, qui se rapproche).
 -- Beta 1.55 (essais du 9 novembre à Imola : avis pour des voitures qui ne rattrapaient jamais le joueur, l'écart de
 -- vitesse du moment bondissant à chaque freinage) : écart en temps au même point de la piste (instant où le joueur
 -- y est passé), rapprochement confirmé sur la durée (voir le bloc k155 de config.lua) ; ni voiture aux stands ni hors
 -- piste. Mètres et km/h ne servent plus qu'au journal.
 local pl=frame.player
 local me=pl>0 and frame.cars[pl] or nil
 if not (me and me.valid and me.splineValid and not t.push[pl] and not me.pit) then t.playerBin=0; return end
 local bins=e.delta.bins
 local here=Delta.bin(me.spline,bins)
 if here~=t.playerBin then
  -- Cases sautées (image lente) : même instant pour les quelques cases franchies d'un coup.
  local from=t.playerBin
  local step=from>0 and (here-from)%bins or 0
  -- Première case (entrée pas vue) et saut trop grand : rien de relevé.
  if from>0 and step>0 and step<=K.qualiCatchFill then for k=1,step do t.playerAt[(from+k-1)%bins+1]=now end end
  t.playerBin=here
 end
 local best,gapTime=nil,math.huge
 for j=1,frame.count do
  local b=frame.cars[j]; local c=t.cars[j]
  -- Écart relevé à l'entrée de la voiture dans chaque case, comparé à l'instant d'entrée du joueur dans la même case
  -- (deux entrées : aucune dent de scie due à la taille des cases).
  -- Voie des stands déjà exclue par t.push ; hors piste exclue ici.
  if j~=pl and t.push[j] and b.valid and b.splineValid and not b.player and not b.offtrack then
   local here=Delta.bin(b.spline,bins)
   if here~=c.catchBin then
    local fresh=c.catchBin>0
    c.catchBin=here
    local at=t.playerAt[here]
    local g=fresh and at and now-at
    if g and g>=0 and g<=K.qualiCatchWatch then
     if c.catchN>=K.qualiCatchSamples then for k=1,c.catchN-1 do c.catchT[k]=c.catchT[k+1]; c.catchG[k]=c.catchG[k+1] end; c.catchN=c.catchN-1 end
     c.catchN=c.catchN+1; c.catchT[c.catchN]=now; c.catchG[c.catchN]=g
    elseif fresh then c.catchN=0 end
   end
  else c.catchBin=0; c.catchN=0 end
  local seen=c.catchN>0 and now-c.catchT[c.catchN]<=K.qualiCatchForget and c.catchG[c.catchN] or nil
  if not seen then
   if c.catchN>0 or U.finite(c.candAt) then
    c.candOut=c.candOut+dt
    if c.candOut>=K.qualiCatchForget then c.catchN=0; c.candAt=-math.huge; c.candLogged=false end
   end
  else
   c.candOut=0
   -- Rapprochement (s par seconde) depuis le relevé le plus récent qui couvre chaque durée.
   local last=c.catchT[c.catchN]
   local rateLong,rateShort=nil,nil
   for k=c.catchN-1,1,-1 do
    local span=last-c.catchT[k]
    if not rateShort and span>=K.qualiCatchSpanShort then rateShort=(c.catchG[k]-seen)/span end
    if not rateLong and span>=K.qualiCatchSpanLong then rateLong=(c.catchG[k]-seen)/span end
   end
   local rate=max(rateLong and rateLong>=K.qualiCatchRateLong and rateLong or 0,rateShort and rateShort>=K.qualiCatchRateShort and rateShort or 0)
   local confirmed=rate>0 and seen/rate<=K.qualiCatchProject
   if seen<=K.qualiWarnTime then
    if not U.finite(c.candAt) then c.candAt=now end
    if confirmed and now-c.candAt<=K.qualiCatchWindow then
     if seen<gapTime then best,gapTime=j,seen end
    elseif now-c.candAt>K.qualiCatchWindow and not c.candLogged then
     c.candLogged=true
     if e.runtimeG.debugLog then U.log(e.log,now,'DEBUG',string.format('tour lance non confirme: %s (ecart %.1f s, rapprochement %.2f s/s)',name(b),seen,max(rateLong or 0,rateShort or 0)),j) end
    end
   end
  end
 end
 if best then
  local c=t.cars[best]
  if now-c.warnAt>=K.qualiWarnRepeat then
   c.warnAt=now; e.stats.qualiWarn=(e.stats.qualiWarn or 0)+1
   local b=frame.cars[best]
   local meters=((me.spline-b.spline)%1)*frame.length
   if p.yellowMessage then Incidents.message(inc,'fastCar',best-1,math.floor(gapTime*10+0.5)/10,name(b)) end
   U.log(e.log,now,'INFO',string.format('tour lance: %s arrive derriere le joueur (%s) a %.1f s (%.0f m, %+.0f km/h)',name(b),t.cars[pl].why~='' and t.cars[pl].why or 'pas lance',gapTime,meters,(b.speed-me.speed)*3.6),best)
  end
 end
end
-- Beta 1.62 (décision 3) : cause d'un tour lancé fautif (nil sinon) : tour invalidé par les limites de piste
-- (src/sanctions.lua, même numéro de tour) ou passé sous drapeau jaune.
function M.faulty(c,e,i,lap)
 local sc=e.sanctions and e.sanctions.cars and e.sanctions.cars[i]
 if sc and sc.invalidLap==lap and lap>=0 then return 'tour invalide, limites de piste' end
 if c.yellowLap==lap and lap>=0 then return 'drapeau jaune' end
 return nil
end
-- Beta 1.62 (décision 4) : écart en temps (s) à la voiture devant (perception), ou nil.
local function aheadTime(e,i,a)
 local row=e.perception.rows[i]
 if not row or row.front<=0 then return nil end
 local r=row.neighbors[row.front]
 local b=e.frame.cars[r.index]
 if not b or b.pit or not b.valid or r.gap<0 then return nil end
 return r.gap/max(a.speed,K.qualiGapMinSpeed)
end
function M.exitGap(t,e,a,c,i,cmd,eligible,outDrop,now,dt)
 local want=0
 if eligible and t.active and a.control and not a.player and a.splineValid and (a.spline%1)<K.qualiGapUntil then
  local gap=aheadTime(e,i,a)
  local row=e.perception.rows[i]
  local flying=M.follower(t,e,i,row)
  if gap and gap<K.qualiExitGap and not flying then want=max(0,min(K.qualiGapLevel,K.qualiOutMaxDrop-(outDrop or 0))) end
 end
 local rate=K.qualiGapLevel/K.qualiOutRamp*dt
 if want>c.gapDrop then c.gapDrop=min(want,c.gapDrop+rate) else c.gapDrop=max(want,c.gapDrop-rate) end
 if c.gapDrop>0 then
  cmd.levelScale=(cmd.levelScale or 1)*(1-c.gapDrop)
  if want>0 and not c.gapLogged then
   c.gapLogged=true; e.stats.qualiGap=(e.stats.qualiGap or 0)+1
   U.log(e.log,now,'INFO',string.format('tour de sortie: %s laisse filer la voiture devant (ecart vise %.0f s)',name(a),K.qualiExitGap),i)
  end
 elseif want==0 then c.gapLogged=false end
end
-- Beta 1.62 (règles de la journée circuit) : tour de chauffe progressif après une vraie sortie des stands (réglage
-- outLapEnabled, onglet Général) : niveau abaissé de K.qualiOutLevel (montée K.qualiOutRamp s) jusqu'à la ligne, rendu
-- en K.qualiCoolRelease s. Voitures posées en piste au début de la séance : aucune baisse.
function M.trackDayOut(c,e,a,i,p,now)
 local cmd=e.commands[i]
 if not (p.outLapEnabled and p.section_general and a.control and not a.player) then c.jOut=false; c.jWasPit=a.pit==true; return end
 if a.pit then c.jOut=false
 elseif c.jWasPit then c.jOut=true; c.jExitAt=now; c.jLap=a.lap or 0
  e.stats.trackDayOut=(e.stats.trackDayOut or 0)+1
  U.log(e.log,now,'INFO',string.format('tour de chauffe: %s (niveau -%.0f %%)',name(a),K.qualiOutLevel*100),i)
 elseif c.jOut and (a.lap or 0)>c.jLap then
  if now-c.jExitAt<K.qualiOutGrace then c.jLap=a.lap or 0 else c.jOut=false; c.jEnd=now end
 end
 c.jWasPit=a.pit==true
 local drop=0
 if c.jOut then drop=K.qualiOutLevel*min(1,(now-c.jExitAt)/K.qualiOutRamp)
 elseif now-c.jEnd<K.qualiCoolRelease then drop=K.qualiOutLevel*(1-(now-c.jEnd)/K.qualiCoolRelease) end
 -- Beta 1.62 (journée circuit : « tour de refroidissement avant de rentrer ») : appelée aux stands (règles, sanction,
 -- stratégie, demande d'AC) : allure de refroidissement jusqu'à la voie des stands ; au damier l'app rend déjà les
 -- voitures à AC (session finie) (même niveau et mêmes rampes que le refroidissement des qualifications) ; une ligne par voiture.
 local cooling=not a.pit and not a.finished and (cmd.rulePit or cmd.sanCalled or cmd.stratCalled or a.requestingPit==true)
 if cooling then
  if not c.jCool then
   c.jCool=true; c.jCoolAt=now; e.stats.trackDayCool=(e.stats.trackDayCool or 0)+1
   U.log(e.log,now,'INFO',string.format('tour de refroidissement: %s avant les stands (niveau -%.0f %%)',name(a),K.qualiCoolLevel*100),i)
  end
  drop=max(drop,K.qualiCoolLevel*min(1,(now-c.jCoolAt)/K.qualiCoolRamp))
 elseif c.jCool then c.jCool=false; c.jCoolEnd=now
 end
 if not c.jCool and now-c.jCoolEnd<K.qualiCoolRelease then drop=max(drop,K.qualiCoolLevel*(1-(now-c.jCoolEnd)/K.qualiCoolRelease)) end
 if drop>0 then cmd.levelScale=(cmd.levelScale or 1)*(1-drop) end
end
-- Voiture lancée la plus proche derrière la voiture i pas lancée (à qualiYieldTime s au plus, qui se rapproche) : la
-- voisine (perception), ou nil. Une voiture lente plus proche ne la masque pas.
function M.follower(t,e,i,row)
 if not t.active or t.push[i] or not row then return nil end
 local best,gapTime=nil,math.huge
 for j=1,row.count do
  local r=row.neighbors[j]
  if r.long<0 and r.gap>=0 and t.push[r.index] and math.abs(r.lat)<=K.latYield and (r.sa>=K.qualiYieldSa or r.gap<=K.qualiYieldNear and r.sa>=-K.blueSlack) then
   local b=e.frame.cars[r.index]
   local time=r.gap/max(b.speed,1)
   -- Beta 1.60 (lot 3) : voiture lancée vue plus tôt (K.qualiYieldLead s) : la voiture qui chauffe ses pneus quitte la
   -- trajectoire avant son arrivée.
   if time<=math.max(K.qualiYieldTime,K.qualiYieldLead) and time<gapTime then best,gapTime=r,time end
  end
 end
 return best,gapTime
end
return M
