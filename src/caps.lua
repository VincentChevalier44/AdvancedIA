local K=require('src/config').K
local M={errorLength=160,names={'level','aggression','caution','offset','grip','brake','speed','rain','tyres','pit','stop','flag','flash','park','teleport','penalty','drs','drsActive','brakeMistake','tractionMistake','fuel','fuelSet','startDelay','awake','position','velocity','repairBody','repairSuspension','repairEngine','throttle','tyreKm'}}
function M.new(port)
 -- Beta 1.52 : failureCount, échecs de toutes les capacités depuis le lancement (journal des capacités, seulement après
 -- un nouvel échec).
 local c={port=port,native110=false,levelMode='none',probeIndex=0,probeID='',probeAt=0,probeOriginal=1,probeDone=false,failureCount=0}
 for _,name in ipairs(M.names) do local available=port.present(name); c[name]={available=available,failures=0,reason=available and 'present' or 'missing',error='',noted=false,notedOff=false} end
 return c
end
function M.call(c,name,index,value,extra,force)
 local cap=c[name]
 if not cap.available and not (force and cap.reason=='failures') then return false end
 local ok,err=c.port.write(name,index,value,extra)
 if ok then cap.failures=0; cap.reason='ready'; cap.available=true; return true end
 -- Beta 1.34 : erreur gardée (texte borné) pour le journal ; refus sans erreur (fonction absente, valeur refusée).
 cap.failures=cap.failures+1; cap.error=err~=nil and tostring(err):sub(1,M.errorLength) or 'refus'; c.failureCount=(c.failureCount or 0)%K.counterMax+1
 if cap.failures>=K.capabilityFailures then cap.available=false; cap.reason='failures' end
 return false
end
-- Restitution : tentée même après une série d'échecs ; une écriture réussie remet la capacité en service.
function M.restoreCall(c,name,index,value,extra) return M.call(c,name,index,value,extra,true) end
-- Sonde du niveau : voiture changée sous la sonde (sonde oubliée, à refaire) ; niveau d'origine remis (sonde finie).
local function probeSwapped(c,a) if a and a.valid and c.probeID~=(a.identity or a.id) then c.probeIndex=0; c.probeDone=false; return true end return false end
local function probeRestore(c,a) if M.restoreCall(c,'level',a.index,c.probeOriginal) then c.probeIndex=0; c.probeDone=true end end
-- Sonde interrompue (app désactivée, onglet Général décoché) : niveau d'origine rendu dès que la voiture le permet.
function M.cancelProbe(c,frame)
 if c.probeIndex==0 or frame.online or frame.replay or frame.paused then return end
 local a=frame.cars[c.probeIndex]
 if probeSwapped(c,a) then return end
 if a and a.valid and a.control and not a.player and not a.pit and not a.offtrack then probeRestore(c,a) end
end
function M.probe(c,frame,now,g)
 if frame.online or frame.replay or frame.paused then return end
 if c.probeIndex>0 then
  local a=frame.cars[c.probeIndex]
  if probeSwapped(c,a) then return end
  if not a or not a.valid or not a.control or a.pit or a.offtrack or frame.online or frame.replay then return end
  if now<c.probeAt then return end
  c.native110=a.aiLevel>=K.probeLevel-K.probeTolerance
  probeRestore(c,a)
 elseif not c.probeDone and c.level.available then
  for i=1,frame.count do
   local a=frame.cars[i]
   if a.valid and a.control and not a.pit and not a.offtrack and not a.finished and not a.calibrationBlocked then
    c.probeOriginal=a.aiLevel
    if M.call(c,'level',a.index,a.aiLevel) and M.call(c,'level',a.index,K.probeLevel) then c.probeIndex=i; c.probeID=a.identity or a.id; c.probeAt=now+K.probeDelay end
    break
   end
  end
 end
 M.mode(c,g)
end
function M.mode(c,g)
 local desired=g.levelMode
 c.levelMode=c.native110 and (desired=='auto' or desired=='native') and 'native' or ((desired=='auto' or desired=='grip') and g.useGripBoost and c.grip.available and 'grip' or 'none')
end
return M
