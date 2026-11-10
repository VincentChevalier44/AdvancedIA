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
  -- Beta 1.53 : valeur relue gardée pour le journal ; une relecture sous 1 (+ tolérance) prouve l'écrêtage de la
  -- lecture (clampProven), seule raison pour laquelle le mode automatique passe au bonus de grip (s'il est autorisé).
  c.probeRead=a.aiLevel
  c.native110=a.aiLevel>=K.probeLevel-K.probeTolerance
  c.clampProven=a.aiLevel<1+K.probeTolerance
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
-- Beta 1.53 (décision du pilote) : physics.setAILevel accepte 0 à 2 (SDK CSP) ; seule la lecture aiLevel est
-- documentée de 0 à 1. Mode automatique : niveau natif jusqu'à K.nativeLevelMax dès que la commande existe, sans
-- attendre la relecture ; bonus de grip seulement si la relecture prouve l'écrêtage et que le bonus est autorisé.
-- « Natif si confirmé » garde son sens (relecture à 1.05 nécessaire) ; « bonus de grip » et « plafond » inchangés.
function M.mode(c,g)
 local desired=g.levelMode
 local grip=g.useGripBoost and c.grip.available
 if desired=='auto' then c.levelMode=c.level.available and not (c.clampProven and grip) and 'native' or grip and 'grip' or 'none'
 elseif desired=='native' then c.levelMode=c.native110 and 'native' or 'none'
 elseif desired=='grip' then c.levelMode=grip and 'grip' or 'none'
 else c.levelMode='none' end
end
-- Beta 1.53 (le pilote ne voyait aucune IA au-dessus de 100 % sans savoir pourquoi) : lignes du journal sur le niveau
-- au-dessus de 100 %, construites seulement au moment de les écrire (fin de sonde, changement de mode, déclassement).
local modeJournal={native='natif (jusqu a %.0f %%)',grip='bonus de grip',none='plafond 100 %%'}
local function modeText(c,g)
 return string.format(modeJournal[c.levelMode] or modeJournal.none,K.nativeLevelMax*100)..string.format(' (mode demande %s, bonus de grip %s)',tostring(g.levelMode),g.useGripBoost and 'autorise' or 'non autorise')
end
function M.probeText(c,g)
 return string.format('niveau au-dessus de 100 %%: sonde %.2f relue %.2f%s (niveau d origine %.2f) -> ',K.probeLevel,c.probeRead or -1,c.clampProven and ' (lecture ecretee)' or '',c.probeOriginal or -1)..modeText(c,g)
end
function M.modeText(c,g) return 'niveau au-dessus de 100 %: mode '..modeText(c,g) end
function M.demotionText(c,g,name,written,read)
 return string.format('niveau au-dessus de 100 %%: %s relu %.2f apres %.2f ecrit (lecture ecretee) -> ',tostring(name),read,written)..modeText(c,g)
end
-- Journal du mode : la fin de sonde (une fois) puis chaque changement de mode (réglages, déclassement déjà noté).
function M.report(c,g)
 if not c.probeDone or c.probeRead==nil then return nil end
 if not c.probeReported then c.probeReported=true; c.reportedMode=c.levelMode; return M.probeText(c,g) end
 if c.reportedMode~=c.levelMode then c.reportedMode=c.levelMode; return M.modeText(c,g) end
 return nil
end
return M
