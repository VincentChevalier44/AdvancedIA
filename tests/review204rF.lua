-- Relecture adversariale 2.0.4, tour 2, angle F (sécurité, fichiers, coût) : verrous LOCK_REVIEW204F_<n>. Chargé par
-- tests/extended.lua.
local A=require('src/applier')
local U=require('src/update')
local tests={}

-- F1 : chemins du paquet de mise à jour : noms réservés de Windows et point ou espace final refusés ; noms ordinaires
-- (y compris ceux qui commencent comme un nom réservé) acceptés.
tests.LOCK_REVIEW204F_1=function()
 local p=U.prefix
 local base={p,p..'manifest.ini',p..'AdvancedIA.lua',p..'src/',p..'src/update.lua',p..'src/remote.lua'}
 local function with(extra) local list={} for _,v in ipairs(base) do list[#list+1]=v end list[#list+1]=extra; return list end
 assert(U.content(base),'ordinary package accepted')
 for _,good in ipairs({'src/config.lua','src/console.lua','sounds/auxiliary.wav','fonts2/nullable.ttf','src/com10.lua','docs/LPT.md'}) do
  assert(U.content(with(p..good)),'ordinary name refused: '..good)
 end
 for _,bad in ipairs({'CON','con.lua','src/nul','src/NUL.txt','sounds/aux.wav','prn','src/com1.lua','LPT9.ini','src/Com3',
  'src/name.','src/name ','src/dir./x.lua','src/../x.lua','src/./x.lua','src//x.lua','src\\x.lua','src/x.lua:stream'}) do
  assert(not U.content(with(p..bad)),'unsafe name accepted: '..bad)
 end
end

-- F2 : écriture du journal ou du rapport CSV qui échoue (disque plein) : le fichier ouvert est refermé.
tests.LOCK_REVIEW204F_2=function()
 local savedOpen=io.open
 local opened,closed=0,0
 io.open=function()
  opened=opened+1
  return {write=function() error('disk full',0) end,close=function() closed=closed+1; return true end,seek=function() return 0 end}
 end
 local ok,err=pcall(function()
  local a=A.new(); a.journalPath='logs/test.log'; a.journalBytes=0
  assert(A.journalWrite(a,'line\n')==false,'write failure reported')
  assert(opened==1 and closed==1,'journal handle closed after a failed write ('..opened..' opened, '..closed..' closed)')
  assert(a.journalBytes==0 and (a.journalFailures or 0)==1,'failure counted, size untouched')
 end)
 io.open=savedOpen
 assert(ok,err)
end

return tests
