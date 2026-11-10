-- Journal de session : lignes nouvelles du journal circulaire, horodatées ; l'écriture sur disque est faite par applier.
local M={}
function M.new() return {serial=0,lines={},count=0,flushAt=0,summaryAt=0} end
-- Lignes ajoutées depuis le dernier prélèvement, de la plus ancienne à la plus récente.
function M.collect(j,log,stamp)
 for n=log.count-1,0,-1 do
  local r=log[(log.head-n-1)%log.limit+1]
  if r.serial>j.serial then
   j.serial=r.serial; j.count=j.count+1
   j.lines[j.count]=string.format('%s %9.1f %-5s %3d %s',stamp,r.time,r.level,r.index,r.message)
  end
 end
end
function M.take(j)
 if j.count==0 then return nil end
 local text=table.concat(j.lines,'\n',1,j.count)..'\n'
 for i=1,j.count do j.lines[i]=nil end
 j.count=0
 return text
end
-- Résumé périodique : IA gérées par état, incidents et neutralisation, coût mesuré.
function M.summary(e)
 local frame=e.frame; local ai,managed,drive,yield,pass,avoid,calm,yellow=0,0,0,0,0,0,0,0
 local unmanaged={}
 if frame then
  for i=1,frame.count do
   local a=frame.cars[i]
   if a.valid and a.control and not a.player then
    ai=ai+1
    local s=e.states[i]; local state=s.state
    if e.commands[i].active then managed=managed+1
    -- IA non gérée et sa raison (voiture de sécurité exclue).
    elseif not a.safetyCar then
     unmanaged[#unmanaged+1]=i..' '..(a.pit and 'stands' or a.offtrack and 'hors piste' or a.finished and 'arrivee' or s.disqualified and 'disqualifiee' or s.excluded and 'ecartee' or e.time<s.errorUntil and 'erreur' or 'attente')
    end
    if state=='DRIVE' then drive=drive+1 elseif state:sub(1,5)=='YIELD' then yield=yield+1
    elseif state:sub(1,3)=='OVT' then pass=pass+1 elseif state=='AVOID' then avoid=avoid+1 elseif state=='CALM' then calm=calm+1 end
    if s.yellow then yellow=yellow+1 end
   end
  end
 end
 local t=e.incidents
 -- Événements de la minute écoulée : transitions des IA (par raison), appels, blocages, incidents ; puis remise à zéro.
 local n=e.stats or {}
 local function c(key) return n[key] or 0 end
 local minute=string.format(' | sur la minute : depassements tentes %d, reussis %d, annules %d (cote ferme %d, cible plus rapide %d, sans rapprochement %d, suiveur rapide %d, cible perdue %d, jaune %d), invitations du joueur %d, passages sur cession %d, cessions %d, abouties %d, cessions sans passage %d, defenses %d, evitements %d, contacts %d, reprises au calme %d, appels de phares %d, blocages %d, manoeuvres interrompues par blocage %d, incidents %d, IA arretees %d',
  c('pass')+c('chain')+c('invited')+c('yielded'),c('clear')+c('chain'),c('abort_blocked')+c('abort_slow')+c('abort_stall')+c('abort_follower')+c('target_lost')+c('abort_yellow')+c('abort_noprogress')+c('abort_timeout'),c('abort_blocked'),c('abort_slow'),c('abort_stall'),c('abort_follower'),c('target_lost'),c('abort_yellow'),c('invited'),c('yielded'),c('yield'),c('passed'),c('lost'),c('attacker'),c('obstacle'),c('contactEvent'),c('contact'),c('flash'),c('limit'),c('direction_limit'),t.started,t.held)
 -- Règles d'arrêt de la 1.6.0 : voitures lentes écartées des incidents et bouchons suivis sans évitement.
 minute=minute..string.format(' | arrets ecartes : file %d, depart ou stands %d, au pas %d | bouchons suivis sans evitement %d',
  t.suppressed.queue,t.suppressed.spawn,t.suppressed.crawl,c('jam'))
 -- Beta 1.31 : vrais dépassements entre IA (échange de places à moins de 20 m), dont ceux menés par une manœuvre de
 -- l'app, et IA passées devant le joueur.
 minute=minute..string.format(' | depassements reels %d (manoeuvre de l app %d), IA passees devant le joueur %d',c('realPass'),c('realPassApp'),c('passedPlayer'))
 t.suppressed.queue=0; t.suppressed.spawn=0; t.suppressed.crawl=0
 local drsOpen,drsAsk=c('drsOpen'),c('drsAsk')
 -- Beta 1.42 (relecture) : aspiration cassée et air sale de la minute, écrits seulement s'il y en a eu.
 local tows,towEnds,dirtyAirs=c('tow'),c('tow_end'),c('dirtyAir')
 -- Beta 1.47 : premier tour attentif (src/firstlap.lua), écrit seulement s'il a agi.
 local flCare,flLift,flBrake,flAvoid,flPass=c('flCare'),c('flLift'),c('flBrake'),c('flAvoid'),c('flPass')
 -- Beta 1.50 : pied tenu en ligne droite (dont voiture de derrière plus près de son contact).
 local flHold,flPushed=c('flHold'),c('flPushed')
 -- Beta 1.51 : essais et qualifications, tours lancés (src/quali.lua), écrits seulement s'il y en a eu.
 local qY,qP,qL,qN,qW,qC=c('qualiYield'),c('qualiPassed'),c('qualiLost'),c('qualiNoPass'),c('qualiWarn'),c('qualiCool')
 local qH=e.merge and e.merge.qualiHolds or 0; if e.merge then e.merge.qualiHolds=0 end
 -- Beta 1.55 : abandons sans progrès et trop longs (hors course), fins de cession par raison, cessions refusées et
 -- appels de phares suspendus, écrits seulement s'il y en a eu (ajoutés en fin de ligne).
 local noProg,tooLong=c('abort_noprogress'),c('abort_timeout')
 local yEnd,yHold,yYellow=c('yieldEnd'),c('yieldEnd_hold_limit'),c('yieldEnd_yellow')
 local yOther=yEnd-c('yieldEnd_passed')-c('yieldEnd_lost')-yHold-yYellow
 local yNoAdv,fMuted,fHeld=c('yieldNoAdv'),c('flashMuted'),c('flashHeld')
 for key in pairs(n) do n[key]=0 end
 t.started=0; t.held=0
 -- Pneus des IA à l'instant du résumé, et météo retenue par l'app.
 local dry,inter,wet,unknown,rainFlag=0,0,0,0,0
 if frame then
  for i=1,frame.count do
   local a=frame.cars[i]
   if a.valid and a.control and not a.player then
    if not a.tyresKnown or a.compoundIndex==nil then unknown=unknown+1
    elseif a.currentTyreIsDry then dry=dry+1
    elseif a.compoundIndex==a.interCompound then inter=inter+1
    elseif a.compoundIndex==a.wetCompound then wet=wet+1
    else unknown=unknown+1 end
    -- Beta 1.55 : drapeau pluie de CSP (pneus pluie de l'IA), indépendant de la gomme montée.
    if a.nativeRainTyres then rainFlag=rainFlag+1 end
   end
  end
 end
 minute=minute..string.format(' | pneus IA : secs %d, intermediaires %d, pluie %d, inconnus %d (meteo %s), drapeau pluie de CSP %d',dry,inter,wet,unknown,e.weather and e.weather.wet and 'pluie' or 'sec',rainFlag)
  ..string.format(' | DRS des IA : ouvertures %d, dont demandees par l app %d',drsOpen,drsAsk)
  ..(tows+towEnds+dirtyAirs>0 and string.format(' | aspiration cassee %d (finies %d), air sale %d',tows,towEnds,dirtyAirs) or '')
  ..(flCare+flLift+flBrake+flAvoid+flPass>0 and string.format(' | premier tour attentif : anticipations %d, levers de pied du radar %d, freinages du radar %d, evitements refuses (voiture pas assez lente) %d, depassements retenus %d',flCare,flLift,flBrake,flAvoid,flPass) or '')
  ..(flHold>0 and string.format(' | ligne droite : pied tenu %d fois (dont voiture de derriere plus pres %d)',flHold,flPushed) or '')
  ..(qY+qP+qL+qN+qW+qH+qC>0 and string.format(' | tours lances : cessions %d (abouties %d, perdues %d), attaques retenues %d, retenues a la jonction %d, avis au joueur %d, refroidissements des IA %d',qY,qP,qL,qN,qH,qW,qC) or '')
  ..(noProg+tooLong>0 and string.format(' | abandons : sans progres %d, tentative trop longue %d',noProg,tooLong) or '')
  ..(yEnd>0 and string.format(' | fins de cession : duree max %d, jaune %d, autres %d',yHold,yYellow,yOther) or '')
  ..(yNoAdv>0 and string.format(' | cessions refusees (suiveur pas plus rapide) %d',yNoAdv) or '')
  ..(fMuted+fHeld>0 and string.format(' | appels de phares suspendus %d, retenus apres abandon %d',fMuted,fHeld) or '')
 return string.format('resume: profil %s, garde %s, IA %d, gerees %d | conduite %d, cession %d, depassement %d, evitement %d, recuperation %d | sous jaune %d, incidents %d, zones %d, IA arretees %d, neutralisation %s | cout moyen %.3f ms, max %.3f ms, erreurs %d',
  e.profile,e.guard,ai,managed,drive,yield,pass,avoid,calm,yellow,t.activeCount,t.zoneCount,t.holdCount,t.neutral and t.neutralMode or 'aucune',e.meanFrame,e.maxFrame,e.errors)
  ..(e.maxFrame==0 and ' (cout non mesure : aucun chronometre disponible)' or '')..(#unmanaged>0 and ' | hors gestion : '..table.concat(unmanaged,', ') or '')..minute
  -- Beta 1.57 (CSP 0.3.0-preview212 chez un joueur : lecture refusée à chaque image, sans trace au journal) : lectures de
  -- l'état du jeu en échec depuis le lancement, écrites seulement s'il y en a eu (ajoutées en fin de ligne).
  ..((e.frame and e.frame.errors or 0)>0 and string.format(' | lectures de l etat du jeu en echec %d',e.frame.errors) or '')
end
-- Beta 1.53 : ligne du journal en anglais pour la fenêtre (le fichier reste en français). Table src/journal_en.lua
-- compilée au premier appel ; appelée une fois par ligne et par langue (texte gardé par la fenêtre), jamais par image.
local compiled=nil
local function escape(s) return (s:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]','%%%0')) end
local function compile()
 local data=require('src/journal_en')
 compiled={rules={},generic={},exact=data.exact}
 for _,r in ipairs(data.rules) do
  local kinds={}
  -- Noms ({n}) pris au plus long : un nom de pilote peut contenir des parenthèses (« Nom (100%, 100%) » de Content
  -- Manager), la suite du modèle fixe la coupure.
  local pattern=escape(r[1]):gsub('{(%a?)}',function(k) kinds[#kinds+1]=k; return k=='n' and '(.*)' or '(.-)' end)
  compiled.rules[#compiled.rules+1]={pattern='^'..pattern..'$',prefix=r[1]:match('^(.-){') or r[1],kinds=kinds,en=r[2]}
 end
 local plain={}
 local k=1; local list=data.generic
 while k<=#list do
  local item=list[k]
  if type(item)=='table' then compiled.generic[#compiled.generic+1]={item[1],item[2]}; k=k+1
  else plain[#plain+1]={item,list[k+1]}; k=k+2 end
 end
 table.sort(plain,function(x,y) return #x[1]>#y[1] or #x[1]==#y[1] and x[1]<y[1] end)
 for _,p in ipairs(plain) do
  local fr=p[1]
  local pattern=(fr:find('^%w') and '%f[%w]' or '')..escape(fr)..(fr:find('%w$') and '%f[%W]' or '')
  compiled.generic[#compiled.generic+1]={pattern,(p[2]:gsub('%%','%%%%'))}
 end
end
local function generic(text)
 for _,g in ipairs(compiled.generic) do text=text:gsub(g[1],g[2]) end
 return text
end
local function phrase(text) return compiled.exact[text] or generic(text) end
-- mark : noms remplacés par <name> et valeurs recopiées par <v> (contrôle des tests : aucun mot français hors des
-- données recopiées).
function M.english(message,mark)
 if not compiled then compile() end
 message=tostring(message or '')
 for _,r in ipairs(compiled.rules) do
  if r.prefix=='' or message:find(r.prefix,1,true)==1 then
   local parts={message:match(r.pattern)}
   if parts[1]~=nil then
    return (r.en:gsub('{(%d+)}',function(n)
     local i=tonumber(n); local v=parts[i] or ''
     if r.kinds[i]=='p' then return phrase(v) end
     if mark then return r.kinds[i]=='n' and '<name>' or '<v>' end
     return v
    end)),r
   end
  end
 end
 return generic(message),nil
end
return M
