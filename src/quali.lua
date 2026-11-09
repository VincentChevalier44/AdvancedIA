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
local max=math.max
local M={}
local function car() return {seen=false,wasPit=false,out=false,outLap=-1,exitAt=-math.huge,cool=false,coolLap=-1,slow=0,warnAt=-math.huge} end
function M.new()
 local t={active=false,push={},cars={},logAt=-math.huge}
 for i=1,K.maxCars do t.cars[i]=car(); t.push[i]=false end
 return t
end
function M.reset(t)
 t.active=false; t.logAt=-math.huge
 for i=1,K.maxCars do t.cars[i]=car(); t.push[i]=false end
end
function M.rebase(t,amount)
 if U.finite(t.logAt) then t.logAt=t.logAt-amount end
 for i=1,K.maxCars do
  local c=t.cars[i]
  if U.finite(c.exitAt) then c.exitAt=c.exitAt-amount end
  if U.finite(c.warnAt) then c.warnAt=c.warnAt-amount end
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
-- Une fois par image, avant le pilotage.
function M.update(t,e,frame,now,dt)
 local p=e.run; local profile=e.profile; local inc=e.incidents
 t.active=(profile=='P' or profile=='Q') and p.qualiTraffic==true and not inc.red and not inc.neutral and not frame.replay and not frame.online
 for i=1,frame.count do
  local a=frame.cars[i]; local c=t.cars[i]; local s=e.states[i]
  local lap=a.lap or 0
  if not c.seen then
   -- Première vue : voie des stands (tour de sortie à la sortie) ou déjà en piste (posée par l'app, rechargement) :
   -- tour de sortie jusqu'à la ligne.
   c.seen=true; c.wasPit=a.pit==true; c.out=true; c.outLap=a.pit and -1 or lap; c.exitAt=now
  end
  if a.pit then
   c.out=true; c.outLap=-1; c.cool=false; c.slow=0
  elseif c.wasPit or a.teleport then
   c.out=true; c.outLap=lap; c.exitAt=now; c.cool=false; c.slow=0
  end
  c.wasPit=a.pit==true
  if c.out and not a.pit and c.outLap>=0 and lap>c.outLap then
   -- Ligne passée juste après la sortie (ligne placée après la sortie des stands) : le tour de sortie continue.
   if now-c.exitAt<K.qualiOutGrace then c.outLap=lap else c.out=false end
  end
  -- Tour de refroidissement (ou tour abandonné) : nettement plus lente que sa référence ici, jusqu'à la ligne.
  if not c.out and not a.pit then
   if c.cool and lap>c.coolLap then c.cool=false; c.slow=0 end
   local ref=M.reference(e,s,a,p.multiClass)
   -- Retenue derrière une voiture (à moins de K.followRange m) : jamais un refroidissement (elle perdrait sa priorité au
   -- moment où elle en a besoin).
   local row=e.perception.rows[i]
   local held=row and row.front>0 and row.neighbors[row.front].gap<=K.followRange
   if not c.cool and ref>0 and a.speed<ref*K.qualiCoolRatio and not held and not s.yellow and not (s.state=='YIELD_IN' or s.state=='YIELD_HOLD') then
    c.slow=c.slow+dt
    if c.slow>=K.qualiCoolTime then c.cool=true; c.coolLap=lap end
   elseif not c.cool then c.slow=0 end
  end
  local cmd=e.commands[i]
  -- Pas lancée : tour de sortie, refroidissement, voie des stands, appelée aux stands (tour de rentrée), anormalement
  -- lente (dégâts), arrivée, ou à l'arrêt.
  local inLap=not a.player and (cmd.rulePit or cmd.sanCalled or cmd.stratCalled)
  t.push[i]=t.active and a.valid and not a.pit and not a.finished and not a.safetyCar and not c.out and not c.cool and not inLap
   and not s.abnormal and a.kmh>=K.qualiCoolMinKmh or false
 end
 for i=frame.count+1,K.maxCars do t.push[i]=false end
 if not t.active then return end
 -- Avis au joueur pas lancé : IA lancée qui arrive derrière lui (à qualiWarnTime s au plus, qui se rapproche).
 local pl=frame.player
 local row=pl>0 and e.perception.rows[pl]
 if pl>0 and not t.push[pl] and row and not frame.cars[pl].pit then
  local best,gapTime=nil,math.huge
  for j=1,row.count do
   local r=row.neighbors[j]; local b=frame.cars[r.index]
   if r.long<0 and r.gap>=0 and t.push[r.index] and not b.player and r.sa>=K.qualiWarnSa then
    local time=r.gap/max(b.speed,1)
    if time<=K.qualiWarnTime and time<gapTime then best,gapTime=r,time end
   end
  end
  if best then
   local c=t.cars[best.index]
   if now-c.warnAt>=K.qualiWarnRepeat then
    c.warnAt=now; e.stats.qualiWarn=(e.stats.qualiWarn or 0)+1
    local b=frame.cars[best.index]
    if p.yellowMessage then require('src/incidents').message(inc,'fastCar',best.index-1,math.floor(gapTime*10+0.5)/10,name(b)) end
    U.log(e.log,now,'INFO',string.format('tour lance: %s arrive derriere le joueur (%s) a %.1f s (%.0f m, %+.0f km/h)',name(b),t.cars[pl].out and 'tour de sortie' or 'refroidissement',gapTime,best.gap,best.sa),best.index)
   end
  end
 end
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
   if time<=K.qualiYieldTime and time<gapTime then best,gapTime=r,time end
  end
 end
 return best,gapTime
end
return M
