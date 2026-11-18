-- Relecture adversariale de la 2.0.4, domaine A (conduite des IA). Chargé par tests/extended.lua.
-- A1 : horloges du directeur absentes des listes recalées (C.timerFields, C.optionalTimerFields) : au retour de
-- l'horloge du moteur (K.timeWrap, 24 h de temps du moteur, course de 24 heures), une fenêtre « jusqu'à » restait
-- ouverte 24 h et une sortie de virage restait « récente » (exitCornerAt).
local F=require('tests/fixture')
local C=require('src/config')
local E=require('src/engine')
local D=require('src/director')
local K=C.K
local tests={}
local openFile=io.open

tests.LOCK_REVIEW204A_1=function()
 local e,f=F.scene('C',3)
 F.tick(e,f,1)
 local now=e.time
 local s=e.states[2]
 s.exitCornerAt=now-1; s.exitPassUntil=now+3; s.lappedHoldUntil=now+5; s.rearLeftUntil=now+2; s.seekLatch=now-0.5
 e.coverDiag={cand=1,band=0,turn0=0,roll=0,side=0,done=0,at=now+60}
 E.rebase(e,1000)
 local t=e.time
 assert(math.abs(t-(now-1000))<1e-9,'engine time rebased')
 assert(math.abs((t-s.exitCornerAt)-1)<1e-9,'corner exit still 1 s ago, not 1001 s in the future')
 assert(math.abs((s.exitPassUntil-t)-3)<1e-9 and math.abs((s.lappedHoldUntil-t)-5)<1e-9 and math.abs((s.rearLeftUntil-t)-2)<1e-9,'windows keep their length')
 assert(math.abs((t-s.seekLatch)-0.5)<1e-9,'seek latch rebased')
 assert(math.abs((e.coverDiag.at-t)-60)<1e-9,'cover summary rebased')
 -- Valeurs absentes ou infinies : intactes.
 s.exitCornerAt=nil; s.exitPassUntil=-math.huge; E.rebase(e,10)
 assert(s.exitCornerAt==nil and s.exitPassUntil==-math.huge,'nil and -inf untouched')
 -- Garde pour la suite : tout champ d'état posé à partir de « now » dans les modules de conduite est recalé (liste du
 -- moteur, champs facultatifs, src/priority.lua ou la liste du directeur).
 local root=package.path:match('^([^;]+)/%?%.lua')
 local known={commitAt=true,heldUntil=true,diveNow=true}
 for _,k in ipairs(C.timerFields) do known[k]=true end
 for _,k in ipairs(C.optionalTimerFields) do known[k]=true end
 for _,k in ipairs(D.extraTimers) do known[k]=true end
 local missing={}
 for _,name in ipairs({'director','rear','nuance','mistakes','priority','antics','cooldown','mood','flash','signals','perception','traffic','persona','firstlap','formation','grid','wear','classes'}) do
  local file=assert(openFile(root..'/src/'..name..'.lua','rb')); local text=file:read('*a'); file:close()
  for key in text:gmatch('[^%w_]s%.([%w_]+)=now[^%w_]') do if not known[key] then missing[#missing+1]=name..':'..key end end
  for key in text:gmatch('[^%w_]s%.([%w_]+)=max%(s%.[%w_]+,now') do if not known[key] then missing[#missing+1]=name..':'..key end end
 end
 assert(#missing==0,'state timers not rebased: '..table.concat(missing,', '))
end

return tests
