-- Sanctions sous drapeau : joueur (temps delta, dépassement, reprise hors des stands, arrêt manqué) et IA (dépassement),
-- avec escalade jusqu'à la disqualification. Décisions pures ; les écritures (pénalité native, retour au stand) restent dans applier.
local C=require('src/config')
local K=C.K
local P=require('src/perception')
local Delta=require('src/delta')
local Incidents=require('src/incidents')
local abs,max=math.abs,math.max
local M={}
function M.new()
 return {lastAt=-math.huge,requestId=0,seconds=0,reason='',count=0,ahead={},regime=false,passedUnder=false,passMade=false,
  redBefore=false,redPending=false,stopPending=false,jumpPending=false,waiting={},regimeAt=-math.huge,whole=false,wholeAt=-math.huge,giveBack=0,giveBackUntil=0,deltaKind='',deltaValue=0,passed=0,kind='slow',disqualified=false,
  ai={count={},slowUntil={},slowKmh={},slowFrom={},slowAt={},dq={},ahead={},regime={},passed={},lastAt={},waiting={},giveBack={},giveFrom={},giveAt={},owe={},oweUntil={},notes={}},
  retake={},rel={index=0,long=0,lat=0,gap=0,sa=0,ttc=math.huge,same=false,alongside=false}}
end
local function clear(map) for k in pairs(map) do map[k]=nil end end
-- Place prise illégalement : la voiture doublée peut la reprendre sans sanction tant qu'elle reste sous le régime du
-- drapeau ; le droit tombe dès la place reprise.
local function grant(t,victim,passer) local m=t.retake[victim]; if not m then m={}; t.retake[victim]=m end; m[passer]=true end
local function entitled(t,x,y) local m=t.retake[x]; return m~=nil and m[y]==true end
function M.reset(t)
 t.count=0; t.disqualified=false; t.kind='slow'
 for _,map in pairs(t.ai) do clear(map) end
 t.lastAt=-math.huge; t.regime=false; t.whole=false; t.passedUnder=false; t.passMade=false; clear(t.ahead); clear(t.waiting); t.giveBack=0; t.dirty=true
 t.redBefore=false; t.redPending=false; t.stopPending=false; t.jumpPending=false; clear(t.retake)
end
function M.rebase(t,amount)
 if t.lastAt>-math.huge then t.lastAt=t.lastAt-amount end
 if t.regimeAt>-math.huge then t.regimeAt=t.regimeAt-amount end; t.giveBackUntil=t.giveBackUntil-amount
 for j,v in pairs(t.waiting) do t.waiting[j]=v-amount end
 for _,pend in pairs(t.ai.waiting) do for j,v in pairs(pend) do pend[j]=v-amount end end
 if t.wholeAt>-math.huge then t.wholeAt=t.wholeAt-amount end
 for i,v in pairs(t.ai.giveAt) do t.ai.giveAt[i]=v-amount end
 for i,v in pairs(t.ai.slowUntil) do t.ai.slowUntil[i]=v-amount end
 for i,v in pairs(t.ai.lastAt) do t.ai.lastAt[i]=v-amount end
 for i,v in pairs(t.ai.slowAt) do t.ai.slowAt[i]=v-amount end
 for i,v in pairs(t.ai.oweUntil) do t.ai.oweUntil[i]=v-amount end
end
-- Voiture qu'il est permis de doubler sous drapeau jaune : accidentée (ou tout juste repartie, le temps du maintien
-- de la zone), arrêtée ou très lente, aux stands, hors piste.
local function passable(b,c,p,now) return not b.valid or b.pit or b.offtrack or c.incident or c.holding or now-c.clearedAt<p.yellowHold or b.kmh<p.obstacleSpeedKmh end
M.passable=passable
-- Voiture qui purge une sanction (IA au pied levé, joueur aux gaz coupés ou disqualifié) : elle peut être doublée.
local function serving(t,j,now,player)
 return now<(t.ai.slowUntil[j] or 0) or j==player and (t.disqualified or t.kind=='slow' and now<t.lastAt+t.seconds)
end
-- Voiture j qu'il est permis de doubler pour la voiture i sous drapeau : elle doit lui rendre la place, purge une
-- sanction, ou i reprend la place qu'elle lui a prise (file d'attente du pilotage sous drapeau). Beta 1.50 : sous
-- neutralisation (neutral), une voiture qui purge une sanction reste dans la file : jamais doublée.
function M.mayPass(t,i,j,now,player,neutral)
 return (t.ai.waiting[j] and t.ai.waiting[j][i] or 0)>now or j==player and (t.waiting[i] or 0)>now or not neutral and serving(t,j,now,player) or entitled(t,i,j)
end
-- Escalade : coupure des gaz jusqu'au nombre d'infractions toléré, puis disqualification (drapeau noir).
local function decide(t,reason,seconds,now,p)
 t.requestId=t.requestId%K.counterMax+1; t.reason=reason; t.count=t.count+1; t.lastAt=now; t.dirty=true
 if t.count>p.penaltyDisqualify then t.kind='dq'; t.disqualified=true; t.seconds=0 else t.kind='slow'; t.seconds=seconds end
 return reason
end
-- Dépassement pendant la transition (freinage au déclenchement d'un drapeau) : en attente jusqu'à l'échéance, annulé
-- si la place est rendue.
local function deadline(regimeAt,now) return max(regimeAt+K.passGiveBack,now+K.giveBackMin) end
-- Retourne 'delta', 'pass', 'red' ou 'stop' quand une pénalité vient d'être décidée, sinon nil. Le dépassement sous
-- drapeau est suivi même sans pénalité (journée circuit, option décochée) : le panneau le signale en rouge.
-- d : temps delta du joueur (infraction au passage d'un mini-secteur ou à la sortie d'un double drapeau jaune).
function M.update(t,frame,p,profile,inc,now,_,d)
 local i=frame.player
 -- Dépassement interdit à 150 m d'une zone jaune et dedans (comme pour les IA), sous neutralisation et au rouge, et
 -- jusqu'à la ligne après une reprise derrière la voiture de sécurité. Un dépassement en attente survit à la fin du
 -- régime : il est pardonné si la place est rendue, sanctionné à l'échéance sinon.
 local regime=inc.playerNoPass or inc.neutral or inc.red or inc.playerRestart==true
 if not regime then t.passMade=false; if t.retake[i] then clear(t.retake[i]) end end
 -- Fin d'un drapeau rouge : le joueur devait attendre la reprise dans la voie des stands (pas s'il a été annulé).
 local redEnded=t.redBefore and not inc.red and not inc.redCancelled; t.redBefore=inc.red
 t.giveBack=0; t.giveBackUntil=0
 if i==0 or frame.length<=0 then clear(t.waiting); t.passedUnder=false; return nil end
 local a=frame.cars[i]
 if redEnded and a.valid and not a.pit and not a.finished and profile=='C' then t.redPending=true end
 -- Voie des stands : rien n'est jugé ; des places gagnées par un arrêt ne sont pas des dépassements.
 if not a.valid or a.pit or not a.splineValid then clear(t.ahead); clear(t.waiting); t.passedUnder=t.passMade; return nil end
 if not p.playerPenalties or C.solo(profile) then t.redPending=false; t.stopPending=false; t.jumpPending=false end
 local ready=p.playerPenalties and not C.solo(profile) and not t.disqualified and now-t.lastAt>=K.penaltyCooldown
 -- Infractions en attente (reprise hors des stands, arrêt obligatoire manqué) : appliquées dès que possible.
 if ready and t.redPending then t.redPending=false; return decide(t,'red',p.penaltySeconds,now,p) end
 if ready and t.stopPending then t.stopPending=false; return decide(t,'stop',p.penaltySeconds,now,p) end
 -- Faux départ d'un départ arrêté (Beta 1.34).
 if ready and t.jumpPending then t.jumpPending=false; return decide(t,'jump',p.penaltySeconds,now,p) end
 -- Delta négatif au passage d'un mini-secteur ou à la sortie d'un double drapeau jaune : nouveau départ du delta.
 if ready and d and d.infraction then
  t.deltaKind=d.infractionKind; t.deltaValue=d.infractionValue; Delta.penalized(d)
  return decide(t,'delta',p.penaltySeconds,now,p)
 end
 -- Dépassement : une voiture devant passe entièrement derrière le joueur pendant le régime de drapeau jaune.
 -- Dépassement déjà engagé (côte à côte) quand le drapeau s'impose : il peut s'achever.
 local starting=regime and not t.regime; t.regime=regime
 if starting then t.regimeAt=now end
 local result=nil
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=i then
   -- Une IA qui purge une sanction (pied levé) peut être doublée, comme une voiture lente ; une IA qui doit rendre la
   -- place au joueur aussi (il la reprend), comme celle qui la lui a prise sous drapeau.
   local retake=entitled(t,i,j)
   -- Beta 1.48 : le joueur reprend sa place de l'ordre figé au drapeau rouge (reprise) : dépassement permis.
   local restore=Incidents.restoring(inc,i,j)
   if restore then local r=P.relative(a,b,frame.length,t.rel); if r.same and r.long<-(a.length+b.length)*0.5 then Incidents.restored(inc,frame,i,j) end end
   local owed=(t.ai.waiting[j] and t.ai.waiting[j][i] or 0)>now or retake or restore
   if retake then local r=P.relative(a,b,frame.length,t.rel); if r.same and r.long<-(a.length+b.length)*0.5 then t.retake[i][j]=nil end end
   if passable(b,inc.cars[j],p,now) or serving(t,j,now,i) or owed then t.ahead[j]=nil; t.waiting[j]=nil
   else
    local r=P.relative(a,b,frame.length,t.rel)
    if not r.same or abs(r.long)>K.passWatch then t.ahead[j]=nil
    else
     local half=(a.length+b.length)*0.5
     if starting and abs(r.long)<=half then t.ahead[j]=nil
     -- Devant (de nouveau) : place rendue, le dépassement en attente est oublié. Une voiture qui passe devant le joueur
     -- sous drapeau (hors du délai de transition, sans droit de reprise ni place rendue, joueur sans sanction en cours)
     -- lui laisse le droit de reprendre sa place, que les sanctions des IA soient actives ou non.
     elseif r.long>half then
      if t.ahead[j]==false and regime and not t.waiting[j] and now-t.regimeAt>=K.passGiveBack and not entitled(t,j,i) and not Incidents.restoring(inc,j,i) and not serving(t,i,now,i) and not passable(a,inc.cars[i],p,now) then grant(t,i,j) end
      t.ahead[j]=true; t.waiting[j]=nil
     elseif r.long<-half then
      if t.ahead[j] and regime then
       if now-t.regimeAt<K.passGiveBack then t.waiting[j]=deadline(t.regimeAt,now)
       else t.passMade=true; grant(t,j,i); if ready and not result then t.passed=j; result=decide(t,'pass',p.penaltySeconds,now,p) end end
      end
      t.ahead[j]=false
     end
    end
   end
   local due=t.waiting[j]
   if due then
    if now>=due then
     t.waiting[j]=nil; t.passMade=true; grant(t,j,i)
     if ready and not result then t.passed=j; result=decide(t,'pass',p.penaltySeconds,now,p) end
    elseif t.giveBack==0 or due<t.giveBackUntil then t.giveBack=j; t.giveBackUntil=due end
   end
  end
 end
 -- Panneau : dépassement fait (ou en attente) ; une place rendue efface la pastille rouge.
 t.passedUnder=t.passMade or next(t.waiting)~=nil
 return result
end
-- Beta 1.42 : vitesse maximale d'une IA qui rend une place (sous l'allure de la voiture à laisser repasser, levée de
-- pied progressive depuis sa vitesse au début) : place à rendre sous drapeau (moteur) et après un dépassement hors piste
-- (sanctions des IA).
function M.giveBackLimit(fromKmh,at,now,otherKmh,decel) return max(max(K.trafficMinSpeed,otherKmh-K.giveBackDrop),fromKmh-decel*3.6*(now-at)) end
-- Sanction d'une IA : pied levé quelques secondes ; au-delà du nombre toléré, disqualification.
-- Beta 1.50 (neutralisation du 5 novembre 14:57 : IA passées devant le joueur en tête) : sous neutralisation ou au tour de
-- relance (owe), la place est aussi RENDUE : levée de pied sous l'allure de la voiture doublée jusqu'à ce qu'elle repasse,
-- au plus K.aiGiveBackMax s.
-- Place due (une à la fois : la première voiture doublée).
local function owe(s,i,j,now)
 if s.owe[i] or s.dq[i] then return end
 s.owe[i]=j; s.oweUntil[i]=now+K.aiGiveBackMax; s.notes[#s.notes+1]={kind='owe',i=i,j=j}
end
local function sanction(t,s,i,j,a,p,now,events,neutral)
 s.lastAt[i]=now; s.count[i]=(s.count[i] or 0)+1; s.passed[i]=j
 if s.count[i]>p.penaltyDisqualify then s.dq[i]=true
 else s.slowUntil[i]=now+p.penaltySeconds; s.slowKmh[i]=math.max(K.trafficMinSpeed,a.kmh*K.aiPenaltyFactor); s.slowFrom[i]=a.kmh; s.slowAt[i]=now
  if neutral then owe(s,i,j,now) end
 end
 events=events or {}; events[#events+1]=i; t.dirty=true
 return events
end
-- Sanctions des IA : un dépassement sous drapeau jaune (zone jaune, neutralisation, drapeau rouge : son propre régime)
-- la fait lever le pied quelques secondes ; au-delà du nombre toléré, disqualification. Au déclenchement d'une
-- neutralisation ou d'un drapeau rouge (tout le peloton freine en même temps), un dépassement fait pendant la
-- transition attend : oublié si la place est rendue (giveBack : voiture à laisser repasser), sanctionné à l'échéance
-- sinon. Une zone jaune s'annonce, elle : dépassement sanctionné aussitôt. Renvoie les IA sanctionnées.
function M.ai(t,frame,p,profile,inc,states,rows,now)
 if not p.aiPenalties or C.solo(profile) then clear(t.ai.giveBack); return nil end
 local s=t.ai; local events=nil
 local whole=inc.neutral or inc.red
 if whole and not t.whole then t.wholeAt=now end
 t.whole=whole
 local transition=whole and now-t.wholeAt<K.passGiveBack
 for i=1,frame.count do
  local a=frame.cars[i]
  local ahead=s.ahead[i]; if not ahead then ahead={}; s.ahead[i]=ahead end
  local waiting=s.waiting[i]; if not waiting then waiting={}; s.waiting[i]=waiting end
  s.giveBack[i]=0
  if a.valid and a.control and not a.player and not a.pit and not a.safetyCar and not s.dq[i] then
   -- Régime de la voiture (zone jaune, reprise jusqu'à la ligne) ou de tout le peloton (neutralisation, drapeau rouge),
   -- même hors piste. Un dépassement en attente survit à la fin du régime (place rendue ou sanction à l'échéance).
   -- Hors piste, le drapeau jaune de l'IA est suspendu par le pilotage : le régime est gardé (couper la piste pour
   -- doubler reste un dépassement sous drapeau).
   local relaunch=inc.cars[i].restart==true and inc.standing~='grid' and inc.standing~='lights'
   local regime=states[i].yellow or whole or relaunch or a.offtrack and s.regime[i]==true
   -- Beta 1.50 : neutralisation (VSC, FCY, voiture de sécurité) ou tour de relance : la place prise est à rendre.
   local neutral=inc.neutral and not inc.red or relaunch
   -- Place due après un dépassement interdit sous neutralisation : rendue dès que la voiture doublée est de nouveau
   -- devant ; abandonnée si elle sort de la course, rentre aux stands, est accidentée ou disqualifiée, ou au bout du délai
   -- (suivie même après la fin de la neutralisation).
   local owed=s.owe[i]
   if owed then
    local b=frame.cars[owed]
    local why=(not b.valid or b.finished) and 'hors course' or b.pit and 'aux stands' or (inc.cars[owed] and inc.cars[owed].incident) and 'accidentee'
     or s.dq[owed] and 'disqualifiee' or now>=(s.oweUntil[i] or 0) and 'delai depasse'
    local back=P.relative(a,b,frame.length,t.rel)
    if not why and back.same and back.long>(a.length+b.length)*0.5 then
     s.notes[#s.notes+1]={kind='given',i=i,j=owed}; s.owe[i]=nil; s.oweUntil[i]=nil
    elseif why then
     s.notes[#s.notes+1]={kind='dropped',i=i,j=owed,why=why}; s.owe[i]=nil; s.oweUntil[i]=nil
    else s.giveBack[i]=owed end
   end
   local was=s.regime[i]; s.regime[i]=regime
   if not regime and t.retake[i] then clear(t.retake[i]) end
   -- Hors régime, déjà sortie du précédent et sans dépassement en attente : rien à suivre (la liste « devant » est
   -- vidée au prochain régime).
   if regime or was or next(waiting)~=nil then
    -- Début du régime : on repart des voitures devant ; un dépassement déjà côte à côte peut s'achever.
    if regime and not was then clear(ahead) end
    -- Voitures suivies devenues dépassables (hors piste, aux stands, accidentées, sanctionnées) : oubliées, même hors
    -- de la perception (une voiture hors piste n'y figure pas) ; doublées pendant ce temps, ce n'est pas une infraction.
    -- Beta 1.50 : sous neutralisation, une voiture qui purge une sanction n'est pas dépassable (file).
    local spare=not (whole and not inc.red)
    for j in pairs(ahead) do if passable(frame.cars[j],inc.cars[j],p,now) or spare and serving(t,j,now,frame.player) then ahead[j]=nil end end
    for j in pairs(waiting) do if passable(frame.cars[j],inc.cars[j],p,now) or spare and serving(t,j,now,frame.player) then waiting[j]=nil end end
    local row=rows[i]
    for k=1,row.count do
     local r=row.neighbors[k]; local j=r.index; local b=frame.cars[j]
     -- Voiture qui doit rendre la place à celle-ci (IA ou joueur) : la reprendre n'est pas un dépassement.
     local retake=entitled(t,i,j)
     -- Beta 1.48 : reprise de sa place de l'ordre figé au drapeau rouge : dépassement permis.
     local restore=Incidents.restoring(inc,i,j)
     if restore and r.same and r.long<-(a.length+b.length)*0.5 then Incidents.restored(inc,frame,i,j) end
     local owed=(s.waiting[j] and s.waiting[j][i] or 0)>now or j==frame.player and (t.waiting[i] or 0)>now or retake or restore
     if retake then local fresh=P.relative(a,b,frame.length,t.rel); if fresh.same and fresh.long<-(a.length+b.length)*0.5 then t.retake[i][j]=nil end end
     if passable(b,inc.cars[j],p,now) or owed or not r.same or abs(r.long)>K.passWatch then ahead[j]=nil
     else
      local half=(a.length+b.length)*0.5
      -- Devant (de nouveau) : place rendue.
      if r.long>half then ahead[j]=true; waiting[j]=nil
      elseif r.long<-half then
       if ahead[j] and regime then
        if transition then waiting[j]=deadline(t.wholeAt,now)
        -- Une infraction au plus par délai, comme pour le joueur : plusieurs voitures doublées d'un coup, une sanction ;
        -- la voiture doublée peut reprendre sa place dans tous les cas.
        else grant(t,j,i); if now-(s.lastAt[i] or -math.huge)>=K.penaltyCooldown then events=sanction(t,s,i,j,a,p,now,events,neutral) elseif neutral then owe(s,i,j,now) end end
       end
       ahead[j]=false
      end
     end
    end
    local earliest=math.huge
    for j,due in pairs(waiting) do
     if now>=due then
      waiting[j]=nil; grant(t,j,i)
      if now-(s.lastAt[i] or -math.huge)>=K.penaltyCooldown then events=sanction(t,s,i,j,a,p,now,events,neutral) elseif neutral then owe(s,i,j,now) end
     elseif due<earliest then earliest=due; s.giveBack[i]=j end
    end
   end
  -- Voie des stands : rien n'est suivi (places gagnées par un arrêt).
  elseif a.pit then clear(ahead); clear(waiting)
   if s.owe[i] then s.notes[#s.notes+1]={kind='dropped',i=i,j=s.owe[i],why='aux stands'}; s.owe[i]=nil; s.oweUntil[i]=nil end
  end
 end
 return events
end
-- Infractions et disqualifications conservées à travers un rechargement de l'app au cours de la même session : joueur,
-- puis IA par index et identité.
function M.serialize(t,frame,session)
 local rows={tostring(session),string.format('P,%d,%d',t.count,t.disqualified and 1 or 0)}
 for i=1,frame.count do
  local n=t.ai.count[i]; local a=frame.cars[i]; local identity=a.identity or a.id
  if n and n>0 and type(identity)=='string' and identity:match('^[%w_%-]+$') then rows[#rows+1]=string.format('%d,%d,%d,%s',i,n,t.ai.dq[i] and 1 or 0,identity) end
 end
 return table.concat(rows,'\n')
end
-- Données mises en attente : rendues après la remise à zéro du premier pas du moteur (nouvelle session vue par l'app
-- rechargée).
function M.restore(t,text,session)
 t.pending=nil
 if type(text)~='string' or #text>K.maxZoneBytes then return end
 local pending={session=session,rows={}}; local first=true
 for line in text:gmatch('[^\n]+') do
  if first then first=false; if line~=tostring(session) then return end
  else
   local count,dq=line:match('^P,(%d+),([01])$')
   if count then pending.count=math.min(tonumber(count),K.counterMax); pending.dq=dq=='1'
   else
    local index,n,d,identity=line:match('^(%d+),(%d+),([01]),([%w_%-]+)$')
    if index and tonumber(index)>=1 and tonumber(index)<=K.maxCars then
     pending.rows[#pending.rows+1]={index=tonumber(index),count=math.min(tonumber(n),K.counterMax),dq=d=='1',identity=identity}
    end
   end
  end
 end
 if not first then t.pending=pending end
end
-- Rendues dans la même session seulement ; sanctions des IA à la voiture de même identité au même index.
function M.resume(t,frame)
 local pending=t.pending
 if not pending or frame.count==0 then return end
 t.pending=nil
 if frame.session~=pending.session then return end
 -- Joueur disqualifié : drapeau noir de nouveau imposé (l'instance précédente l'a levé en se déchargeant).
 if pending.count then t.count=pending.count; t.disqualified=pending.dq; if pending.dq then t.kind='dq'; t.requestId=t.requestId%K.counterMax+1 end end
 for _,row in ipairs(pending.rows) do
  local a=frame.cars[row.index]
  if a and a.valid and (a.identity or a.id)==row.identity then t.ai.count[row.index]=row.count; if row.dq then t.ai.dq[row.index]=true end end
 end
end
return M
