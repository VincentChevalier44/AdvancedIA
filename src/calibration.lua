local U=require('src/util')
local Caps=require('src/caps')
local Perception=require('src/perception')
local Config=require('src/config')
local K=Config.K
local M={}
function M.new() return {index=0,reference=0,indexID='',referenceID='',startAt=0,startLat=0,phase='waiting',attempted=false,canonical=0,safety={left=false,right=false,nearest=0}} end
local function resetSafe(self,frame,g)
 local a,b=frame.cars[self.index],frame.cars[self.reference]
 if b and b.valid and self.referenceID==(b.identity or b.id) then
  local lat=-(b.x-a.x)*b.lz+(b.z-a.z)*b.lx
  if math.abs(lat-self.startLat)>=K.calibrationMinMove then self.canonical=U.sign(lat-self.startLat) end
 end
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
function M.step(self,frame,caps,g,now)
 if frame.online or frame.replay or frame.paused then return false end
 if self.index==0 and g.offsetSign~=0 and g.sideSign~=0 then self.phase='ready'; return false end
 if self.index>0 then
  local a,b=frame.cars[self.index],frame.cars[self.reference]
  if a and a.valid and self.indexID~=(a.identity or a.id) then self.index=0; self.phase='aborted'; self.retryAt=now+K.calibrationRetry; return false end
  local valid=safe(frame,self.index,true) and b and b.valid and self.referenceID==(b.identity or b.id) and not b.pit and not b.offtrack and (b.cornerYaw or b.corner)>=K.calibrationCorner
  if not valid or now-self.startAt>=K.calibrationTime then
   if a and a.valid and a.control and not a.pit and not a.offtrack then
    if valid then
     local lat=-(b.x-a.x)*b.lz+(b.z-a.z)*b.lx; local delta=lat-self.startLat
     if math.abs(delta)>=K.calibrationMinMove then
      g.offsetSign=U.sign(delta); g.sideSign=a.sideDot and U.sign(a.sideDot) or 1; self.phase='ready'
     else self.phase='inconclusive' end
    else self.phase='aborted' end
    if self.phase~='ready' then self.retryAt=now+K.calibrationRetry end
    if resetSafe(self,frame,g) then
     if Caps.restoreCall(caps,'offset',a.index,0,false) then self.index=0 end
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
      self.startAt=now; self.startLat=-dx*b.lz+dz*b.lx; self.canonical=0; self.phase='running'; self.attempted=true
      return true
     end
    end
   end
  end
 end
 return false
end
function M.cancel(self,frame,caps,g)
 if self.index==0 then return true end
 local a=frame.cars[self.index]
 if a and a.valid and self.indexID~=(a.identity or a.id) then self.index=0; self.phase='aborted'; self.retryAt=-math.huge; return true end
 if a and a.valid and a.control and not a.pit and not a.offtrack and not frame.replay and not frame.online and not frame.paused and resetSafe(self,frame,g) then
  if Caps.restoreCall(caps,'offset',a.index,0,false) then self.index=0; self.phase='aborted'; self.retryAt=-math.huge; return true end
 end
 return false
end
return M
