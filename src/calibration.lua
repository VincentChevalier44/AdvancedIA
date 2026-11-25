local U=require('src/util')
local Caps=require('src/caps')
local Perception=require('src/perception')
local Config=require('src/config')
local K=Config.K
local M={}
function M.new() return {index=0,reference=0,indexID='',referenceID='',startAt=0,startLat=0,phase='waiting',attempted=false,canonical=0,safety={left=false,right=false,nearest=0}} end
local function resetSafe(self,frame,g,lateral)
 local a,b=frame.cars[self.index],frame.cars[self.reference]
 local moved=nil
 if self.startOwn~=nil then local own=lateral and lateral(a) or nil; if own then moved=own-self.startOwn end
 elseif b and b.valid and self.referenceID==(b.identity or b.id) then moved=-(b.x-a.x)*b.lz+(b.z-a.z)*b.lx-self.startLat end
 if moved and math.abs(moved)>=K.calibrationMinMove then self.canonical=U.sign(moved) end
 Perception.occupancy(frame.cars,frame.count,self.index,g or Config.globalDefaults,self.safety)
 if self.canonical==0 then return not self.safety.left and not self.safety.right end
 return self.canonical>0 and not self.safety.left or self.canonical<0 and not self.safety.right
end
local function safe(frame,i,active)
 local a=frame.cars[i]
 if not a or not a.valid or not a.control or a.player or a.pit or a.offtrack or a.calibrationBlocked or not a.splineValid or a.kmh<K.calibrationSpeed or (a.cornerYaw or a.corner)<(active and K.calibrationActiveCorner or K.calibrationCorner) then return false end
 if not a.sideDot or math.abs(a.sideDot)<K.sameDirection then return false end
 if a.leftWidth<K.calibrationMinWidth or a.rightWidth<K.calibrationMinWidth then return false end
 for j=1,frame.count do
  local b=frame.cars[j]
  if i~=j and b.valid then
   local dx,dz=b.x-a.x,b.z-a.z
   if dx*dx+dz*dz<K.calibrationRange^2 then return false end
  end
 end
 return true
end
function M.step(self,frame,caps,g,now,lateral)
 if frame.online or frame.replay or frame.paused then return false end
 -- 2.0.4 : sens -1 / -1 provisoire (installation neuve, révision 23) : la mesure tourne quand même, pour le confirmer.
 if self.index==0 and g.offsetSign~=0 and g.sideSign~=0 and not g.signProvisional then self.phase='ready'; return false end
 if self.index>0 then
  local a,b=frame.cars[self.index],frame.cars[self.reference]
  if a and a.valid and self.indexID~=(a.identity or a.id) then self.index=0; self.phase='aborted'; self.retryAt=now+K.calibrationRetry; return false end
  local valid=safe(frame,self.index,true) and b and b.valid and self.referenceID==(b.identity or b.id) and not b.pit and not b.offtrack and (b.cornerYaw or b.corner)>=K.calibrationCorner
  -- 2.0.5 g (relecture, tour 5, N) : voiture mesurée sortie de la piste : mesure périmée aussitôt (jamais conclue, même
  -- revenue avant la fin des trois secondes) ; décalage rendu dès son retour en piste, côté libre.
  if a and a.valid and a.offtrack then self.startAt=-math.huge end
  if not valid or now-self.startAt>=K.calibrationTime then
   -- 2.0.5 c (relecture) : voiture mesurée entrée dans la voie des stands : mesure abandonnée aussitôt, le décalage est
   -- rendu par l'applicateur comme pour toute voiture gardée dans la voie (laneRelease) ; avant : décalage tenu pendant
   -- tout l'arrêt et mesure figée.
   if a and a.valid and a.control and a.pit then self.index=0; self.phase='aborted'; self.retryAt=now+K.calibrationRetry; return true end
   if a and a.valid and a.control and not a.pit and not a.offtrack then
    -- 2.0.5 c : mesure périmée (voiture sortie de la piste puis revenue, attente d'une remise à zéro) : jamais conclue.
    if valid and now-self.startAt<=K.calibrationTime+K.calibrationLate then
     -- 2.0.5 c : déplacement de la voiture elle-même par rapport à la trajectoire (lateral, lu au début et à la fin) ;
     -- le cap de la voiture repère, 100 à 150 m devant, pèse jusqu'à 9 m sur l'ancienne mesure. Sans cette lecture
     -- (ancien CSP) : mesure par la voiture repère, comme avant.
     local delta
     if self.startOwn~=nil then local own=lateral and lateral(a) or nil; delta=own and own-self.startOwn or 0
     else delta=-(b.x-a.x)*b.lz+(b.z-a.z)*b.lx-self.startLat end
     if math.abs(delta)>=K.calibrationMinMove then
      local so,ss=U.sign(delta),a.sideDot and U.sign(a.sideDot) or 1
      -- 2.0.5 b (journal d'un joueur : sens 1 / -1 enregistré, files du départ rangées du mauvais côté) : mesure
      -- contraire à la convention d'AC en usage (K.signOffset / K.signSide) : retenue seulement après K.signConfirm
      -- mesures identiques de suite (self.refused : sens refusé et rang, pour le journal) ; une mesure conforme remet
      -- le compte à zéro et confirme aussitôt. Sens encore inconnu (0 / 0) : retenue aussitôt, comme avant.
      local contrary=g.offsetSign==K.signOffset and g.sideSign==K.signSide and (so~=K.signOffset or ss~=K.signSide)
      if contrary and self.contraOffset==so and self.contraSide==ss then self.contra=(self.contra or 0)+1
      elseif contrary then self.contraOffset=so; self.contraSide=ss; self.contra=1
      end
      if contrary and self.contra<K.signConfirm then self.phase='inconclusive'; self.refused=so..' / '..ss; self.refusedCount=self.contra
      else
       if g.signProvisional then g.signProvisional=false; self.confirmed=true end
       g.offsetSign=so; g.sideSign=ss; self.phase='ready'
       self.contra=0; self.contraOffset=nil; self.contraSide=nil -- sens retenu : le compte repart de zéro
      end
     else self.phase='inconclusive' end
    else self.phase='aborted' end
    if self.phase~='ready' then self.retryAt=now+K.calibrationRetry end
    if resetSafe(self,frame,g,lateral) then
     -- 2.0.5 e (relecture) : décalage rendu par la mesure elle-même : voiture notée (self.restoredIndex) pour que le
     -- fichier d'entrée remette à zéro le suivi de l'applicateur (AdvancedIA.lua).
     if Caps.restoreCall(caps,'offset',a.index,0,false) then self.restoredIndex=self.index; self.index=0 end
    else self.phase='waiting_reset' end
   end
  end
  return true
 end
 -- Beta 1.25 : une mesure interrompue ou sans conclusion est retentée toutes les K.calibrationRetry s (une seule
 -- tentative par lancement laissait les signes inconnus, sans aucun déplacement latéral, toute la session).
 if self.attempted then
  if not self.retryAt or now<self.retryAt then return false end
  self.attempted=false
 end
 for i=1,frame.count do
  local a=frame.cars[i]
  if safe(frame,i) then
   for j=1,frame.count do
    local b=frame.cars[j]
    local dx,dz=b.x-a.x,b.z-a.z; local long=dx*a.lx+dz*a.lz; local lat=-dx*a.lz+dz*a.lx
    if i~=j and b.valid and b.control and not b.player and not b.pit and not b.offtrack and (b.cornerYaw or b.corner)>=K.calibrationCorner and a.lx*b.lx+a.lz*b.lz>K.calibrationAlignment
     and long>=K.calibrationPairGap and long<=K.calibrationPairMax and math.abs(lat)<K.latYield then
     if Caps.call(caps,'offset',a.index,K.calibrationOffset,false) then
      self.index=i; self.reference=j; self.indexID=a.identity or a.id; self.referenceID=b.identity or b.id
      self.startAt=now; self.startLat=-dx*b.lz+dz*b.lx; self.startOwn=lateral and lateral(a) or nil; self.canonical=0; self.phase='running'; self.attempted=true
      return true
     end
    end
   end
  end
 end
 return false
end
function M.cancel(self,frame,caps,g,lateral)
 if self.index==0 then return true end
 local a=frame.cars[self.index]
 if a and a.valid and self.indexID~=(a.identity or a.id) then self.index=0; self.phase='aborted'; self.retryAt=-math.huge; return true end
 -- 2.0.5 c : dans la voie des stands, le décalage est rendu par l'applicateur (laneRelease).
 if a and a.valid and a.control and a.pit then self.index=0; self.phase='aborted'; self.retryAt=-math.huge; return true end
 if a and a.valid and a.control and not a.pit and not a.offtrack and not frame.replay and not frame.online and not frame.paused and resetSafe(self,frame,g,lateral) then
  if Caps.restoreCall(caps,'offset',a.index,0,false) then self.restoredIndex=self.index; self.index=0; self.phase='aborted'; self.retryAt=-math.huge; return true end
 end
 return false
end
return M
