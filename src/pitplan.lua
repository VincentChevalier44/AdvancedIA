-- Beta 1.49 : stratégie des stands du joueur (menu Quick Pitstop d'AC) en F1 : composé prévu relu au départ, quand le
-- préréglage ou sa valeur change (relu toutes les K.pitPlanPeriod s, jamais à chaque image) et à l'entrée de la voie
-- des stands ; avertissement si le composé prévu est celui déjà monté. Décisions pures : la lecture de CSP
-- (ac.getPitstopSpinners, sim.currentQuickPitPreset) est fournie par l'applicateur ; le préréglage du joueur n'est
-- jamais modifié. La correspondance valeur -> composé n'est retenue que si elle est sans ambiguïté :
--   valeurs max-min+1 = nombre de composés de la voiture : valeur-min = composé ;
--   un de plus : la plus petite valeur = « pas de changement », valeur-min-1 = composé (hypothèse dite au journal) ;
--   autrement : rien n'est affirmé, seulement le journal.
local K=require('src/config').K
local M={}
function M.new() return {checkAt=-math.huge,dumped=false,unreadable=false,lastPit=false,key='',state='',planned='',fitted='',value=0,noticeUntil=-math.huge,assumed=false} end
function M.reset(t)
 t.checkAt=-math.huge; t.dumped=false; t.unreadable=false; t.lastPit=false; t.key=''; t.state=''; t.planned=''; t.fitted=''; t.value=0
 t.noticeUntil=-math.huge; t.assumed=false; t.fixed=false
end
function M.rebase(t,amount)
 if t.checkAt>-math.huge then t.checkAt=t.checkAt-amount end
 if t.noticeUntil>-math.huge then t.noticeUntil=t.noticeUntil-amount end
end
local function count(a)
 local n=0
 for index=0,K.maxTyreCompounds-1 do if a.tyreNames and a.tyreNames[index] then n=n+1 else break end end
 return n
end
local function name(a,index) return index~=nil and a.tyreNames and a.tyreNames[index] or '?' end
local function list(v)
 if type(v)~='table' then return '' end
 local out={}
 for k=1,#v do out[#out+1]=tostring(v[k]) end
 return table.concat(out,'/')
end
-- Composé prévu par le préréglage : index, 'keep' (pas de changement) ou nil (correspondance ambiguë), et l'hypothèse.
function M.planned(spinner,compounds)
 local low,high,value=tonumber(spinner.min),tonumber(spinner.max),tonumber(spinner.value)
 if not low or not high or not value or compounds<=0 then return nil,'ambigue' end
 local range=high-low+1
 if range==compounds then return value-low,'directe' end
 if range==compounds+1 then
  if value==low then return 'keep','plus petite valeur = pas de changement' end
  return value-low-1,'plus petite valeur = pas de changement'
 end
 return nil,'ambigue'
end
-- due : arrêt obligatoire encore à faire (fenêtre à venir ou ouverte) ; f1 : changement de composé exigé ; read() :
-- liste des réglages de l'arrêt et préréglage, ou nil et la raison.
function M.update(t,frame,now,due,f1,started,read,note)
 local a=frame.player>0 and frame.cars[frame.player] or nil
 local active=due and f1 and started and a~=nil and a.valid and a.compoundIndex~=nil and a.tyresKnown
 if not active then t.state=''; t.lastPit=a~=nil and a.pit==true; return end
 local entering=a.pit==true and not t.lastPit
 t.lastPit=a.pit==true
 if now<t.checkAt and not entering then return end
 t.checkAt=now+K.pitPlanPeriod
 if t.unreadable then return end
 local spinners,preset=read()
 if type(spinners)~='table' then
  t.unreadable=true; t.state=''
  if note then note('INFO','strategie des stands illisible ('..tostring(preset or 'CSP sans getPitstopSpinners')..')',-1) end
  return
 end
 local compounds=count(a)
 local spinner=nil
 for k=1,#spinners do local s=spinners[k]; if type(s)=='table' and s.type=='compound' then spinner=s; break end end
 if not t.dumped then
  t.dumped=true
  if note then
   local parts={}
   for k=1,#spinners do
    local s=spinners[k]
    if type(s)=='table' then parts[#parts+1]=string.format('%s (%s) %s..%s valeur %s, prereglages %s',tostring(s.name),tostring(s.type),tostring(s.min),tostring(s.max),tostring(s.value),list(s.values)) end
   end
   local names={}
   for index=0,compounds-1 do names[#names+1]=index..' '..name(a,index) end
   note('INFO',string.format('strategie des stands (Quick Pitstop): prereglage %s, pneu monte %d %s, composes %s | %s',tostring((preset or 0)+1),a.compoundIndex,name(a,a.compoundIndex),table.concat(names,', '),#parts>0 and table.concat(parts,' | ') or 'aucun reglage'),-1)
  end
 end
 if not spinner then
  if t.state~='none' and note then note('INFO','strategie des stands: aucun reglage de compose dans le menu des stands',-1) end
  t.state='none'; return
 end
 local key=tostring(preset)..'|'..tostring(spinner.value)..'|'..a.compoundIndex
 if key==t.key then return end
 t.key=key; t.value=tonumber(spinner.value) or 0
 local plan,how=M.planned(spinner,compounds)
 local before=t.state
 t.fitted=name(a,a.compoundIndex)
 if plan==nil then
  t.state='unknown'; t.planned=''
  if note then note('INFO',string.format('strategie des stands: valeur %s (%s..%s) pour %d composes : correspondance ambigue, aucun avertissement',tostring(spinner.value),tostring(spinner.min),tostring(spinner.max),compounds),-1) end
  return
 end
 if not t.assumed and how~='directe' and note then t.assumed=true; note('INFO','strategie des stands: hypothese retenue : '..how,-1) end
 local same=plan=='keep' or plan==a.compoundIndex
 t.planned=plan=='keep' and t.fitted or name(a,plan)
 t.plannedIndex=plan=='keep' and a.compoundIndex or plan
 t.state=same and 'same' or 'ok'
 if note then note('INFO',string.format('strategie des stands: compose prevu %s (valeur %s, correspondance %s), monte %s%s',t.planned,tostring(spinner.value),how,t.fitted,same and ' : meme compose, avertissement' or ' : arret valable'),-1) end
 if same and before~='same' then t.noticeUntil=now+K.pitPlanNotice end
 -- Beta 1.50 : stratégie corrigée pendant la course (même composé, puis un autre) : avertissement levé, annoncé une fois.
 if before=='same' and t.state=='ok' then t.fixed=true; t.noticeUntil=-math.huge end
end
return M
