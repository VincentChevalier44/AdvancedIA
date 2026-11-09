local U=require('src/util')
local C=require('src/config')
local P=require('src/perception')
local Persona=require('src/persona')
local Classes=require('src/classes')
local Zones=require('src/zones')
local Incidents=require('src/incidents')
local Penalties=require('src/penalties')
local Flash=require('src/flash')
local Delta=require('src/delta')
local Strategy=require('src/strategy')
local FirstLap=require('src/firstlap')
local Quali=require('src/quali')
local K=C.K
local abs,min,max=math.abs,math.min,math.max
local M={}
local yieldStates={YIELD_IN=true,YIELD_HOLD=true,YIELD_OUT=true}
local passStates={OVT_ARM=true,OVT_IN=true,OVT_HOLD=true,OVT_OUT=true}
function M.newState()
 local s={state='IDLE',reason='init',since=0,target=0,targetSide=0,offset=0,velocity=0,filtered=0,base=0,
  persona={},zone={noYield=false,noOvertake=false,maxOffset=1},pace={},paceCount=0,paceMean=0,paceRatio=0,paceRatioCount=0,freePace=0,class=2,classified=false,classCandidate=0,classCycles=0,
  manualClass=false,stint=0,stintStart=0,pitBefore=false,pitExitUntil=0,pitCautionUntil=0,pitGuardUntil=0,
  confirm=0,confirmLost=0,pendingAt=0,pendingUntil=0,pendingTarget=0,pressure=0,pressureLost=0,pressureTarget=0,passConfirm=0,passCandidate=0,passLost=0,targetLost=0,
  holdUntil=0,postPass=false,yieldStart=0,linger=0,ignoreTarget=0,ignoreUntil=0,stuck=0,blocked=0,passBlocked=0,abortSlow=0,clear=0,restUntil=0,
  followers={},followerSlow={},multiLeader=false,yieldDetection=0,yieldMargin=0,blockedYield=0,obstacleSlow=0,obstacleIdentity='',newDirectionLimit=false,
  nextPerception=0,defendUntil=0,defendCooldown=0,defendAttacker=0,defendLap=-1,defendUsed=false,
  straight=0,calmUntil=0,speedBefore=0,speedWindow=0,speedWindowStart=0,lastContact=0,
  lapseAt=0,lapseUntil=0,lapseCount=0,brakeDemand=0,radarBrake=0,startCare=0,radarLogAt=-math.huge,blueWait=0,blueYieldLogged=false,blueWaitLogged=false,slipTime=0,errorCount=0,errorUntil=0,excluded=false,
  direction=0,lastDirectionAt=-math.huge,directions={},directionStates={},directionSides={},directionIntended={},limitState='',limitSide=0,directionCount=0,directionHead=0,driveUntil=0,returning=false,trafficLimit=K.unlimitedSpeed,trafficGap=math.huge,trafficTarget=0,
  playerGap=math.huge,playerSa=0,lappedByPlayer=false,bluePending=false,gap=math.huge,sa=0,ttc=math.huge,spinHold=false,trafficReference=0,trafficApplied=false,
  alongside=false,passAlongside=false,aborts=0,previousIdentity='',fatigue=1,yellow=false,aiFlashAt=-math.huge,overtakeArmed=false,overtakeSpline=-1,yieldClass=false,bop=0,
  hazardRel={index=0,long=0,lat=0,gap=0,sa=0,ttc=math.huge,same=false,alongside=false},
  scanRel={index=0,long=0,lat=0,gap=0,sa=0,ttc=math.huge,same=false,alongside=false},avoidClear=0,invited=0,avoidSide=0,passStall=0,holdStall=0,holdLong=math.huge,
  lane=0,laneActive=false,laneLatched=false,laneSeen=-math.huge,laneMeters=0,laneAt=0,laneLogged=false,passedByPlayerAt=-math.huge,playerBehind=false,inviteWait=0,inviteLogged=false,appBrake=0,baseCaution=1,baseAggression=0,maneuverAt=-math.huge,passStartAt=-math.huge,passMinGap=0,passName='',closeFront=0,closeMeters=0,lastPassTarget=0,lastPassAt=-math.huge,frontWas=0}
 for j=1,K.paceBins do s.pace[j]=0 end
 -- Beta 1.41 : IA anormalement lente (moteur), dépassements ignorés après un échec, cession perdue, vitesse de pointe
 -- réduite pour laisser passer.
 s.abnormal=false; s.abnormalFor=0; s.abnormalCalm=0; s.slowPitSent=false; s.longRatio=1; s.longRatioTime=0
 s.passIgnore=0; s.passIgnoreUntil=0; s.passIgnoreCount=0; s.followerStall={}; s.yieldPassed=false; s.yieldOrdinary=false; s.yieldStalled=false; s.yieldCap=nil; s.yieldCapNow=nil
 -- Relecture : suiveur que l'IA n'attend plus (cession perdue, échec « cible plus rapide ») ; jamais un drapeau bleu ni
 -- une classe. Demande d'arrêt d'une IA lente et endommagée (course).
 s.yieldIgnore=0; s.yieldIgnoreUntil=0; s.slowPitAsked=false; s.slowPitDone=false
 -- Beta 1.42 AERO : aspiration cassée (une manœuvre par ligne droite, attentes en secondes restantes : rien à recaler),
 -- air sale (0 à 1) et urgence des derniers tours (0 à 1).
 s.towing=false; s.towDone=false; s.towWait=0; s.towPair=0; s.towPairWait=0; s.dirty=0; s.dirtyBefore=false; s.dirtyLogWait=0; s.urgency=0
 for j=1,K.directionLimit do s.directions[j]=-math.huge; s.directionStates[j]=''; s.directionSides[j]=0 end
 for j=1,K.maxCars do s.followers[j]=false; s.followerSlow[j]=0; s.followerStall[j]=0 end
 return s
end
function M.reset(s,now,keepOffset,preserveErrors)
 s.state='IDLE'; s.reason='reset'; s.since=now; s.target=0; s.targetSide=0; s.confirm=0; s.confirmLost=0
 s.pendingAt=0; s.pendingUntil=0; s.pendingTarget=0; s.pressure=0; s.pressureLost=0; s.pressureTarget=0
 s.holdUntil=0; s.linger=0; s.stuck=0; s.blocked=0; s.passBlocked=0; s.invited=0; s.passStall=0; s.abortSlow=0; s.clear=0; s.passAlongside=false
 s.calmUntil=0; s.spinHold=false; s.postPass=false; s.alongside=false; s.velocity=0; s.filtered=keepOffset and s.offset or 0
 for j=1,K.maxCars do s.followers[j]=false; s.followerSlow[j]=0; s.followerStall[j]=0 end
 if not preserveErrors then s.errorUntil=0; s.excluded=false; s.errorCount=0 end
 s.direction=0; s.directionCount=0; s.directionHead=0; s.driveUntil=0; s.returning=keepOffset==true
 s.passConfirm=0; s.passCandidate=0; s.passLost=0; s.targetLost=0; s.holdStall=0; s.holdLong=math.huge
 s.lastDirectionAt=-math.huge; for j=1,K.directionLimit do s.directions[j]=-math.huge end
 s.defendUntil=0; s.defendCooldown=0; s.defendAttacker=0; s.defendLap=-1; s.defendUsed=false
 s.ignoreTarget=0; s.ignoreUntil=0; s.lapseUntil=0; s.bluePending=false; s.yieldBlue=false; s.yieldQuali=false; s.urgent=false
 s.passIgnore=0; s.passIgnoreUntil=0; s.passIgnoreCount=0; s.yieldPassed=false; s.yieldCap=nil; s.yieldCapNow=nil; s.yieldIgnore=0; s.yieldIgnoreUntil=0
 s.blockedYield=0; s.brakeDemand=0; s.radarBrake=0; s.speedWindowStart=now; s.speedWindow=0; s.cornerBefore=nil
 s.trafficReference=0; s.trafficApplied=false; s.yellow=false; s.overtakeArmed=false; s.overtakeSpline=-1; s.yieldClass=false
 if not keepOffset then s.offset=0 end
 s.lane=0; s.laneActive=false; s.laneLatched=false; s.laneMeters=0; s.laneLogged=false
 s.towing=false; s.towDone=false; s.dirty=0; s.dirtyBefore=false; s.urgency=0
end
function M.configure(s,g,profile,p,now)
 Persona.fill(s.persona,g.seed,s.slot or 0,profile,p,s.stint)
 s.lapseAt=now+s.persona.lapseInterval
end
-- Beta 1.41 : toutes les raisons d'une fin de tentative en clair (« guard » et « yield » restaient en anglais).
local passEnd={clear='reussi',chain='reussi, enchaine',abort_slow='cible plus rapide',abort_blocked='cote ferme',abort_stall='sans rapprochement',abort_follower='suiveur rapide',
 target_lost='cible perdue',abort_yellow='drapeau jaune',hold_limit='cote a cote sans progres',direction_limit='plafond anti-zigzag',
 guard='rendue a AC (stands, hors piste ou hors commande)',yield='cede a son suiveur',obstacle='evitement d un obstacle',contact='contact, reprise au calme',spun='tete-a-queue'}
local function transition(e,s,state,reason,now)
 if s.state==state then return end
 -- Beta 1.31 : fin d'une tentative de dépassement de l'app (sortie des états de passage), avec sa raison.
 if passStates[s.state] and s.state~='OVT_OUT' and not passStates[state] or state=='OVT_OUT' and passStates[s.state] and s.state~='OVT_OUT' then
  if U.finite(s.passStartAt) then
   local car=e.frame and e.frame.cars[s.slot]
   U.log(e.log,now,'INFO',string.format('depassement fini: %s -> %s : %s apres %.1f s (ecart mini %.0f m)',car and car.name or '?',s.passName,passEnd[reason] or reason,now-s.passStartAt,s.passMinGap),s.slot)
  end
  s.passStartAt=-math.huge
 end
 s.state=state; s.reason=reason; s.since=now
 local stats=e.stats; if stats then stats[reason]=(stats[reason] or 0)+1 end
 if e.runtimeG.debugLog then U.log(e.log,now,'DEBUG',state..':'..reason,s.slot) end
end
-- Classe plus rapide (numéro plus petit) : seulement entre deux voitures déjà classées.
local function faster(p,a,b) return p.multiClass and a.classified and b.classified and a.class<b.class end
local function sideFree(row,side) return side<0 and not row.left or side>0 and not row.right end
-- Endroit de l'allure apprise (plus fin sur les longs circuits, module delta).
local function paceBin(spline,bins) return Delta.bin(spline,bins) end
-- Allure libre apprise d'une voiture à l'endroit b (m/s) : la sienne, sinon celle de sa classe corrigée de son rythme
-- relatif (comme s.freePace) ; 0 inconnue. Jamais le maximum des deux (Delta.pace), qui rendrait deux voitures égales.
local function freeAt(e,s,b,p)
 local v=s.pace[b] or 0
 if v>0 then return v end
 local fleet=e.delta.fleet[p.multiClass and s.class or 1]
 if fleet and s.paceRatioCount>=K.paceRatioMin and (fleet[b] or 0)>0 then return fleet[b]*s.paceRatio end
 return 0
end
-- Beta 1.41 (journées circuit du 3 novembre : 72 à 100 % des dépassements finis sur « cible plus rapide », la même paire
-- jusqu'à 16 fois de suite) : vraie avance de la voiture s sur la voiture o à l'endroit de a, allure libre plus rapide
-- d'au moins K.passFreeMargin ; nil si l'une des deux allures y est inconnue.
local function realAdvantage(e,s,o,a,p)
 local b=paceBin(a.spline,e.delta.bins)
 local mine,theirs=freeAt(e,s,b,p),freeAt(e,o,b,p)
 if mine<=0 or theirs<=0 then return nil end
 return mine>=theirs*(1+K.passFreeMargin)
end
-- Beta 1.44 : joueur nettement plus lent que l'allure libre de l'IA s ici (moins de K.playerSlowRatio fois elle ;
-- inconnue : seulement sous K.speedMinPass*K.playerCrawlRatio km/h, au pas). Jamais son allure apprise à lui : apprise à
-- chaque image en conduite libre, elle suit sa vitesse du moment quand il ralentit.
local function playerSlow(e,s,b,a,p)
 local mine=freeAt(e,s,paceBin(a.spline,e.delta.bins),p)
 if mine>0 then return b.speed<mine*K.playerSlowRatio end
 return b.kmh<K.speedMinPass*K.playerCrawlRatio
end
-- Invitation : en course, les deux voitures en ligne droite (rayon K.inviteCurve), comme avant ; hors course
-- (Beta 1.44), courbe douce permise (au plus K.inviteLatAccel m/s² de part et d'autre), l'écart latéral moins celui que
-- la courbure seule donne à cette distance (k·d²/2) devant valoir K.inviteLat.
local function inviteGeometry(profile,a,b,rel)
 if profile=='C' then return abs(a.yawRate)<=K.inviteCurve*a.speed and abs(b.yawRate)<=K.inviteCurve*b.speed end
 if abs(a.yawRate)*a.speed>K.inviteLatAccel or abs(b.yawRate)*b.speed>K.inviteLatAccel then return false end
 local k=abs(a.yawRate)/max(a.speed,1)
 return abs(rel.lat)-k*rel.long*rel.long*0.5>=K.inviteLat
end
-- Côté de l'interface, convention SDK (+1 = droite), converti dans le repère latéral interne calibré.
local function userSide(side,g) return g.offsetSign<0 and -side or side end
local function fixedSide(value,fallback,g) return userSide(value=='left' and -1 or value=='right' and 1 or fallback,g) end
local function yieldSide(p,rel,ordinary,row,g)
 local value=ordinary and p.yieldSide or p.blueFlagSide
 if value~='auto' then return fixedSide(value,1,g) end
 local preferred=rel and rel.lat<0 and -1 or 1
 if sideFree(row,preferred) then return preferred end
 return -preferred
end
local function passSide(p,profile,s,front,row,other,g)
 if p.overtakeSide=='opposite' then return -fixedSide(p.yieldSide,1,g) end
 if p.overtakeSide=='left' or p.overtakeSide=='right' then return fixedSide(p.overtakeSide,1,g) end
 local preferred=front.lat>0 and 1 or front.lat<0 and -1 or (other.yawRate~=0 and U.sign(other.yawRate) or s.persona.personalSide)
 if profile~='C' then preferred=-fixedSide(p.yieldSide,1,g) end
 if sideFree(row,preferred) then return preferred end
 if sideFree(row,-preferred) then return -preferred end
 return s.persona.assertiveness>0.5 and 1 or -1
end
local function baseModifiers(s,p,now,a)
 local persona=s.persona
 local drift=p.paceDriftPct/100*(math.sin(now/persona.period*math.pi*2+persona.phase)+math.sin(now/persona.period2*math.pi*2-persona.phase))*0.5
 local level=(p.section_general and p.levelPct/100 or a.baseLevel or a.aiLevel)*(1+persona.levelSpread+drift)
 local aggression=(p.section_general and p.aggressionPct/100*K.maxAggression or a.baseAggression or a.aiAggression)*(1+persona.aggrSpread)
 local caution=(p.section_general and p.caution or K.defaultCaution)*(1+persona.cautSpread)
 -- Grades Pro-Am et BoP émulée : multiplicateurs neutres lorsque les règles correspondantes sont inactives.
 level=level*(persona.gradeLevel or 1)*(1+(p.bopEnabled and s.bop or 0)); caution=caution*(persona.gradeCaution or 1)
 if p.enduranceOverlay then
  level=level*(1+persona.stintSwing)*(1-p.stintDegradationPct/100*U.clamp((now-s.stintStart)/K.stintDuration,0,1))
  if now<s.pitCautionUntil then caution=caution*K.stintExitCaution end
 end
 if p.weatherAdaptation then level=level*(1-K.wetLevel*a.wet); caution=caution*(1+K.wetCaution*a.wet); aggression=aggression*(1-K.wetAggression*a.wet) end
 return level,aggression,caution
end
-- Changement de direction (PDR §7.5) = changement du côté visé : gauche, ligne, droite. Suivre un but qui varie du
-- même côté (écart réduit en virage, demande urgente) n'en est pas un : ni compté, ni retenu par le délai.
local function directionAllowed(s,desired,now,p,emergency,intended,frozen)
 -- Beta 1.41 (journées circuit du 3 novembre : 16 cibles figées sur 156 changements notés, 41 retours à la ligne notés
 -- du côté opposé) : une cible figée sur le décalage du moment (freinage, voiture à côté) n'est ni un changement ni un
 -- côté visé, le côté gardé reste celui de la dernière vraie manœuvre ; la ligne est la ligne personnelle de l'IA (sa
 -- variation va jusqu'à K.baseMax d'un côté, et le retour vise exactement s.base), pas seulement le centre.
 if frozen and not emergency then return true end
 local line=desired==s.base or abs(desired)<=K.sideDeadband
 local direction=line and 0 or desired>0 and 1 or -1
 if direction==s.direction then return true end
 -- Évitement, récupération et relâchement d'urgence : jamais retenus ni comptés par le plafond (PDR §7.5).
 if emergency then s.direction=direction; s.lastDirectionAt=now; return true end
 if now-s.lastDirectionAt<p.lateralCooldown then return false end
 local active=0
 for j=1,K.directionLimit do if now-s.directions[j]<K.directionWindow then active=active+1 end end
 -- Avertissement une fois par déclenchement, pas à chaque refus pendant le repos.
 if active>=K.directionLimit then if now>=s.driveUntil then s.newDirectionLimit=true; s.limitState=s.state; s.limitSide=direction end; s.limitIntended=intended or desired; s.driveUntil=now+K.directionRest; return false end
 s.directionHead=s.directionHead%K.directionLimit+1; s.directions[s.directionHead]=now; s.directionStates[s.directionHead]=s.state; s.directionSides[s.directionHead]=direction; s.directionCount=active+1
 s.directionIntended[s.directionHead]=intended or desired
 s.direction=direction; s.lastDirectionAt=now
 return true
end
-- Changement de côté encore permis par le plafond (repos et délai écoulés, moins de six dans la minute) : une cession ou
-- un dépassement ne commence pas s'il serait aussitôt refusé.
local function directionBudget(s,now,p)
 if now<s.driveUntil or now-s.lastDirectionAt<p.lateralCooldown then return false end
 local active=0
 for j=1,K.directionLimit do if now-s.directions[j]<K.directionWindow then active=active+1 end end
 return active<K.directionLimit
end
-- Avertissement du plafond : changements de côté retenus dans la fenêtre (état, côté visé, âge), du plus ancien au plus
-- récent, puis le changement refusé ; la cause d'un déclenchement se lit dans le journal.
-- Cible voulue avant la borne de largeur, et cible figée sur le décalage du moment (freinage, voiture à côté) : un vrai
-- changement de côté se distingue d'une borne qui s'effondre dans un virage (diagnostic).
local function wanted(value) return value and string.format(' (voulu %+.2f)',value) or '' end
local function limitText(s,now)
 local parts={}
 for k=1,K.directionLimit do
  local j=(s.directionHead+k-1)%K.directionLimit+1
  if now-s.directions[j]<K.directionWindow then parts[#parts+1]=string.format('%s>%+d -%.0fs',s.directionStates[j],s.directionSides[j],now-s.directions[j])..wanted(s.directionIntended[j]) end
 end
 return string.format('direction_limit: %s ; refuse %s>%+d',table.concat(parts,', '),s.limitState,s.limitSide)..wanted(s.limitIntended)
end
M.limitText=limitText
function M.reachable(s,a,p,g,desired)
 if g.offsetSign==0 or not a.splineValid or not (a.leftWidth>0 and a.rightWidth>0) then return 0 end
 local usable=max(0,min(a.leftWidth,a.rightWidth)-a.width*0.5)
 local bound=min(p.maxSideOffset,s.zone.maxOffset,usable/max(a.leftWidth,a.rightWidth))
 return U.clamp(desired,-bound,bound)
end
-- Maintien de ligne au départ (course) : sur la grille, l'écart à la trajectoire est relevé une fois (première mesure
-- valide) et commandé tel quel, la voiture étant arrêtée, décalé de 0,3 m à l'opposé d'un voisin (jamais vers lui) ;
-- après le feu vert, il est tenu tant qu'une voiture roule à côté et pendant un freinage, puis rendu à la trajectoire
-- par la rampe ordinaire, qui ne va jamais vers un côté occupé (D14). Une voiture proche de la trajectoire ou sans
-- mesure ne retient rien.
local function laneTarget(s,a,row,g)
 local meters=s.laneMeters+(row.right and not row.left and -K.laneBias or row.left and not row.right and K.laneBias or 0)
 local width=meters*g.offsetSign>0 and a.rightWidth or a.leftWidth
 if width<=0 then return 0 end
 -- Borne du côté de la voiture : elle y est déjà ; la borne symétrique la ramènerait vers la trajectoire.
 -- Beta 1.25 : au plus K.laneMaxOffset du demi-côté (échelle mètres-décalage encore jamais vérifiée en jeu).
 local bound=min(s.zone.maxOffset,K.laneMaxOffset,max(0,width-a.width*0.5)/width)
 return U.clamp(meters/width,-bound,bound)
end
local function laneHold(e,s,a,row,g,frame,now,i)
 if not frame.started then
  if not s.laneLatched and a.splineLatValid then
   s.laneLatched=true; s.laneLogged=false
   s.laneMeters=g.offsetSign~=0 and abs(a.splineLat)>=K.laneMin and a.splineLat or 0
  end
  s.lane=s.laneMeters~=0 and laneTarget(s,a,row,g) or 0; s.laneSeen=now; s.laneActive=s.lane~=0
  if s.laneActive then s.offset=s.lane; s.filtered=s.lane; s.velocity=0 end
  return s.lane
 end
 if s.lane==0 then return 0 end
 s.laneActive=true
 if not s.laneLogged then
  s.laneLogged=true; s.laneAt=now
  U.log(e.log,now,'INFO',string.format('maintien de ligne: %s a %+.1f m de la trajectoire (decalage %+.2f)',a.name,s.laneMeters,s.lane),i)
 end
 if s.alongside then s.laneSeen=now end
 if now-s.laneSeen<K.laneRelease or a.brake>K.ruleBrake then
  local target=laneTarget(s,a,row,g); if target~=0 then s.lane=target end
  return s.lane
 end
 s.laneActive=false
 U.log(e.log,now,'INFO',string.format('maintien de ligne: %s rendu apres %.1f s, ecart mesure %+.1f m',a.name,now-s.laneAt,(a.splineLat or 0)-s.laneMeters),i)
 s.lane=0
 return 0
end
function M.lateral(s,desired,row,a,p,g,dt,now)
 local intended,frozen=desired,desired==s.offset
 if not s.laneActive then desired=M.reachable(s,a,p,g,desired) end
 local delta=desired-s.offset
 local blocked=delta<0 and row.left or delta>0 and row.right
 local factor=1; local emergency=false
 if blocked then
  s.blocked=s.blocked+dt; s.velocity=0; s.filtered=s.offset
  if s.blocked<K.blockedRelease then return s.offset end
  -- Recule seulement dans le côté libre, sans traverser la ligne centrale.
  local retreat=s.offset<0 and not row.right or s.offset>0 and not row.left
  if not retreat then return s.offset end
  desired=0; delta=desired-s.offset; factor=p.emergencyReleaseFactor; emergency=true
 else s.blocked=0 end
 if delta==0 then s.velocity=0; return s.offset end
 -- Plafond anti-zigzag (PDR §7.5) : seules les manœuvres comptent. La variation lente de la ligne en conduite libre
 -- et le retour à la ligne pendant le repos imposé ne sont pas des changements de direction.
 local maneuver=s.state~='DRIVE' and s.state~='IDLE'
 -- Beta 1.29 (bilan des journaux du 2 novembre : 1225 des 3780 changements notés, 38 %, venaient de la borne) : le côté
 -- compté est celui que vise la manœuvre, pas la cible bornée par la largeur ; dans un virage, la borne retombe presque
 -- à zéro et passait pour un retour à la ligne, puis un nouveau départ du même côté. Le repos de 20 s qui suivait
 -- coupait cessions et dépassements.
 -- Beta 1.47 : cession au drapeau bleu ni retenue ni comptée (céder au plus rapide passe avant le plafond).
 if maneuver and not directionAllowed(s,emergency and desired or intended,now,p,emergency or s.state=='CALM' or s.state=='AVOID' or s.yieldBlue and yieldStates[s.state],intended,frozen) then s.velocity=0; s.filtered=s.offset; return s.offset end
 local rate=p.rampSpeed*U.clamp(K.lateralSpeedBase/max(a.kmh,K.lateralSpeedFloor),K.lateralRateMin,K.lateralRateMax)*factor
 local velocity=U.sign(delta)*rate
 s.velocity=U.approach(s.velocity,velocity,p.rampAccel*dt)
 s.filtered=U.ema(s.filtered,desired,dt,p.lowPassTau)
 local candidate=U.approach(s.offset,s.filtered,abs(s.velocity)*dt)
 local nextOffset=U.clamp(candidate,min(s.offset,desired),max(s.offset,desired))
 -- Dernière barrière, valable aussi pour les retours au centre et les dépassements annulés.
 if (nextOffset<s.offset and row.left) or (nextOffset>s.offset and row.right) then return s.offset end
 s.offset=nextOffset
 return s.offset
end
-- Joueur à la hauteur d'une autre voiture, ou qui en rattrape une dans sa file : son écart n'invite pas à passer
-- (une IA déjà passée qui s'éloigne ou roule à son allure n'empêche pas l'invitation de la suivante).
local busyRel={}
local function busy(frame,player,i)
 local a=frame.cars[player]
 for j=1,frame.count do
  local b=frame.cars[j]
  if j~=player and j~=i and b.valid and not b.pit then
   local r=P.relative(a,b,frame.length,busyRel)
   if r.same and (abs(r.long)<=(a.length+b.length)*0.5 or r.long>0 and r.gap<K.inviteClear and abs(r.lat)<=K.latPass and r.sa>=K.inviteSa) then return true end
  end
 end
 return false
end
-- fleet : allure médiane de la classe à chaque endroit (module delta), pour estimer l'allure libre là où l'IA n'a jamais
-- roulé seule (rythme relatif appris ailleurs, au moins K.paceRatioMin endroits).
local function pace(s,a,row,dt,p,fleet,bins)
 local bin=paceBin(a.spline,bins)
 -- Allure habituelle apprise seulement en conduite libre : jamais sous drapeau jaune, neutralisation ou espacement.
 if s.state=='DRIVE' and row.free and s.lapseUntil<=0 and a.splineValid and not a.pit and not a.offtrack and not s.yellow and not s.trafficApplied then
  local old=s.pace[bin]
  if old==0 then s.paceCount=s.paceCount+1; s.paceMean=(s.paceMean*(s.paceCount-1)+a.speed)/s.paceCount; s.pace[bin]=a.speed
  else local v=old+(a.speed-old)*K.paceAlpha; s.pace[bin]=v; s.paceMean=s.paceMean+(v-old)/max(1,s.paceCount) end
  local median=fleet and fleet[bin] or 0
  if median>0 then
   local ratio=a.speed/median
   s.paceRatio=s.paceRatioCount>0 and s.paceRatio+(ratio-s.paceRatio)*K.paceRatioAlpha or ratio; s.paceRatioCount=s.paceRatioCount+1
   -- Fusion 1.42 : rythme de longue durée (IA anormalement lente) borné, une flotte encore apprise au départ arrêté
   -- (voitures à l'accélération) ne gonfle plus l'allure habituelle d'une IA.
   ratio=U.clamp(ratio,K.paceRatioLow,K.paceRatioHigh)
   -- Beta 1.41 : rythme relatif de longue durée, figé dès que l'IA roule anormalement lente (moteur) : la référence d'une
   -- IA endommagée reste son allure d'avant les dégâts.
   if s.abnormalFor==0 then s.longRatio=s.longRatioTime>0 and U.ema(s.longRatio,ratio,dt,K.longRatioTau) or ratio; s.longRatioTime=s.longRatioTime+dt end
  end
 end
 local free=s.pace[bin]
 if free==0 and fleet and s.paceRatioCount>=K.paceRatioMin and (fleet[bin] or 0)>0 then free=fleet[bin]*s.paceRatio end
 s.freePace=free
 if free>0 and a.speed<free*p.stuckPaceRatio then s.stuck=s.stuck+dt else s.stuck=0 end
end
local function lapOrClass(e,s,a,other,rel,p,profile)
 local laps=not C.solo(profile) and p.blueFlagEnabled and Classes.laps(a,other,rel,e.frame.length) or 0
 local upper=faster(p,e.states[other.slot],s)
 return laps,upper
end
local function yieldTrigger(e,s,a,row,p,profile,now,dt)
 local back=row.back>0 and row.neighbors[row.back] or nil
 -- Le voisin lent le plus proche ne doit pas masquer un leader ou un joueur rapide.
 local approaching
 for j=1,row.count do
  local r=row.neighbors[j]
  if r.long<0 and r.gap>=0 and abs(r.lat)<=K.latYield and not yieldStates[e.states[r.index].state] and r.sa>=p.yieldBehindMargin*K.nearYieldMargin
   and (not approaching or r.gap<approaching.gap) then approaching=r end
 end
 if approaching then back=approaching end
 -- Beta 1.51 (qualifications) : IA pas lancée (tour de sortie, refroidissement) : la voiture lancée la plus proche
 -- derrière (à quelques secondes) passe avant tout le reste ; une voiture lente plus proche ne la masque pas.
 local qualiCar=e.quali and Quali.follower(e.quali,e,a.slot,row) or nil
 if qualiCar then back=qualiCar end
 local flash=e.flash.requests[a.slot]
 local activeFlash=flash.untilTime>now and now>=flash.readyAt
 if activeFlash and a.corner<p.cornerMin and not flash.extended then flash.untilTime=flash.cornerUntil; flash.extended=true end
 if activeFlash then
  local player=P.find(row,e.frame.player)
  if player and player.long<0 and player.gap<=p.flashRange then back=player end
 end
 local ai=e.flash.ai[a.slot]
 local aiFlash=not activeFlash and ai.untilTime>now and now>=ai.readyAt
 if aiFlash then
  local source=P.find(row,ai.source)
  if source and source.long<0 and source.gap>=0 and source.gap<=p.flashRange then back=source else aiFlash=false end
 end
 if not back or back.gap<0 then s.confirm=0; s.pendingAt=0; s.pendingTarget=0; s.bluePending=false; return nil end
 local other=e.frame.cars[back.index]
 local laps,upper=lapOrClass(e,s,a,other,back,p,profile)
 local quali=qualiCar~=nil and back.index==qualiCar.index
 if yieldStates[e.states[other.slot].state] then s.pendingAt=0; return nil end
 if faster(p,s,e.states[other.slot]) and laps==0 and not quali then s.pendingAt=0; return nil end
 local blueRange=p.blueFlagRange*((laps>=2 or upper) and K.lapRangeMult or 1)
 -- Beta 1.24 : en course, voiture qui prend un tour collée derrière, à la même allure (retenue) : drapeau bleu aussi.
 -- En essais et qualifications, l'écart de tours ne dit que le temps passé en piste : il faut s'approcher.
 local blue=laps>0 and back.gap<=blueRange and (back.sa>=K.lapSpeed or profile=='C' and back.gap<=K.blueCloseGap and back.sa>=-K.blueSlack)
 local classYield=upper and back.sa>=p.classYieldMargin and (back.sa>=K.classFightSpeed or row.front==0 or row.neighbors[row.front].gap>K.followRange)
 -- Beta 1.29 : appel du joueur jugé tant que la demande vit (plus rapide, ou retenu juste derrière) : appelé de loin un
 -- peu trop lentement, il est compris dès que le joueur se rapproche.
 local currentAdvantage=Flash.advantage(p,back.gap,back.sa)
 local acceptedFlash=activeFlash and back.index==e.frame.player and currentAdvantage
 local permittedFlash=acceptedFlash and (profile~='C' or p.flashMode=='always' or blue or classYield)
 -- Appel d'une IA : en course, admis pour un tour ou une classe supérieure, même à vitesse égale (voiture bloquée).
 -- Dans une file (Beta 1.21) : collée à une voiture, une IA qui s'écarte et ralentit pour une voiture à peine plus rapide
 -- ne laisse passer personne et ralentit toute la file (train de voitures identiques en journée circuit). Cession
 -- ordinaire et appel de phares d'une IA comme la cession entre classes : piste libre devant, ou suiveur nettement plus
 -- rapide. L'appel de phares du joueur reste honoré.
 local clear=row.front==0 or row.neighbors[row.front].gap>K.followRange or back.sa>=K.classFightSpeed
 local aiAccepted=aiFlash and back.index==ai.source and (profile~='C' and clear or laps>0 or upper)
 if profile=='C' and not blue and not classYield and not permittedFlash and not aiAccepted then s.confirm=0; s.pendingAt=0; s.pendingTarget=0; s.bluePending=false; return nil end
 -- Beta 1.51 : IA en tour lancé : pas de cession ordinaire à une voiture qui ne l'est pas (appel de phares compris à part).
 local ordinary=p.yieldEnabled and profile~='C' and clear and not (e.quali and e.quali.active and e.quali.push[a.slot] and not e.quali.push[back.index])
 if not ordinary and not blue and not classYield and not permittedFlash and not aiAccepted and not quali then return nil end
 if s.ignoreTarget==back.index and now<s.ignoreUntil then return nil end
 if s.yieldIgnore==back.index and now<s.yieldIgnoreUntil and not blue and not classYield and not quali then return nil end
 local margin=p.yieldBehindMargin*U.lerp(K.courtesyMin,K.courtesyMax,s.persona.courtesy)*U.lerp(K.gapMarginMin,1,back.gap/K.yieldMarginRange)
 local horizon=p.yieldHorizon
 if acceptedFlash then margin=margin*K.flashMargin; horizon=horizon*K.flashHorizon end
 local detection=max(p.yieldDetectBehind,min(K.detectMax,max(0,back.sa/3.6)*horizon))*(1+(p.weatherAdaptation and K.wetDetect*e.frame.wet or 0))
 if acceptedFlash then detection=max(detection,p.flashRange) end
 local c1=ordinary and back.gap<=detection and back.sa>=margin and back.ttc<=horizon
 local c2=ordinary and back.gap<=K.nearYield and back.sa>=K.nearYieldMargin*margin
 if p.pressureEnabled and back.gap<=p.pressureGap and abs(back.sa)<=K.pressureSa then
  if s.pressureTarget~=back.index then s.pressure=0; s.pressureTarget=back.index end
  s.pressure=s.pressure+dt; s.pressureLost=0
 elseif back.gap>p.pressureGap*K.pressureResetRange then
  s.pressureLost=s.pressureLost+dt; if s.pressureLost>K.pressureResetTime then s.pressure=0 end
 end
 -- Beta 1.41 : pression (suiveur collé à la même allure) refusée à une IA dont l'allure libre ici n'est pas plus rapide
 -- (connue) : avant, l'IA cédait à une IA aussi rapide qu'elle, qui ne passait jamais, puis recommençait. Allure inconnue
 -- et joueur : cession comme avant (PDR T05).
 local c3=ordinary and p.pressureEnabled and s.pressure>=p.pressureTime and (back.index==e.frame.player or realAdvantage(e,e.states[back.index],s,a,p)~=false)
 local c4=permittedFlash
 local c5=aiAccepted
 local trigger=c1 or c2 or c3 or c4 or c5 or blue or classYield or quali
 local needed=(blue or quali) and K.lapConfirm or classYield and p.confirmTime*K.classConfirm or (c4 or c5) and K.flashConfirm or p.confirmTime
 if activeFlash and not c4 then needed=needed*K.flashMargin end
 if trigger then
  s.confirmLost=0
  if s.pendingTarget~=back.index then s.confirm=0; s.pendingAt=0; s.pendingTarget=back.index end
  s.confirm=s.confirm+dt
  if s.confirm>=needed and s.pendingAt==0 then
   local reaction=s.persona.reaction+s.persona.awareness*U.unit(e.runtimeG.seed,a.slot,other.index+e.eventSalt)
   if c4 or c5 then reaction=U.clamp(s.persona.reaction*K.flashReact,K.flashReactionMin,K.flashReactionMax) elseif blue or quali then reaction=reaction*K.lapReaction elseif classYield then reaction=reaction*K.classReaction end
   s.pendingAt=now+reaction; s.pendingUntil=now+K.pendingTTL
  end
 else
  s.confirmLost=s.confirmLost+dt
  if s.confirmLost>K.confirmReset then s.confirm=0; s.pendingAt=0; s.pendingTarget=0; s.bluePending=false end
 end
 if now>s.pendingUntil and s.pendingAt>0 then s.pendingAt=0; s.confirm=0 end
 if not trigger or s.pendingAt==0 or now<s.pendingAt then return nil end
 local corner=(blue or quali) and K.lapCorner or classYield and K.classCorner or p.cornerMin
 if a.corner<corner then s.bluePending=blue; if blue then s.blueReason='virage' end; return nil end
 local side=yieldSide(p,back,profile~='C' and not blue and not quali,row,e.runtimeG)
 if not sideFree(row,side) then s.blockedYield=s.blockedYield+dt else s.blockedYield=0 end
 local blocked=s.zone.noYield and 'zone sans cession' or a.kmh<K.speedMinYield and 'trop lent' or not sideFree(row,side) and 'cote occupe' or not blue and not quali and not directionBudget(s,now,p) and 'trop de changements de trajectoire' or nil
 if blocked then if blue then s.blueReason=blocked end; return nil end
 s.target=back.index; s.targetSide=side; s.gap=back.gap; s.sa=back.sa; s.ttc=back.ttc
 s.yieldDetection=max(detection,blue and blueRange or 0,quali and other.speed*K.qualiYieldTime*K.qualiYieldRange or 0); s.yieldMargin=margin
 for j=1,K.maxCars do s.followers[j]=false; s.followerSlow[j]=0; s.followerStall[j]=0 end
 s.followers[back.index]=true; s.multiLeader=false; s.yieldPassed=false
 s.confirm=0; s.pendingAt=0; s.pendingTarget=0; s.bluePending=false; s.holdUntil=now+p.yieldHoldMin
 s.linger=0; s.postPass=false; s.yieldStart=now; s.yieldBlue=blue or classYield or quali; s.urgent=c4 and flash.urgent
 s.yieldOrdinary=not (blue or classYield or c4 or c5 or quali); s.yieldStalled=false
 -- Beta 1.51 : cession à une voiture lancée (journal et compteurs à part, comme un drapeau bleu pour le reste).
 s.yieldQuali=quali and not blue and not classYield and not c4 and not c5
 if s.yieldQuali then
  e.stats.qualiYield=(e.stats.qualiYield or 0)+1
  if now>=(s.qualiLogAt or -math.huge) then s.qualiLogAt=now+K.qualiLogGap; U.log(e.log,now,'INFO',string.format('cede a %s en tour lance (%s, %.0f m, %+.0f km/h)',other.name,e.quali.cars[a.slot].out and 'tour de sortie' or 'refroidissement',back.gap,back.sa),a.slot) end
 end
 s.yieldClass=(classYield or c5 and upper) and not blue
 if c5 then U.log(e.log,now,'INFO','cede sur appel de phares de '..other.name,a.slot) end
 if c4 then U.log(e.log,now,'INFO',string.format('cede sur appel de phares du joueur (%.0f m, %+.0f km/h)',back.gap,back.sa),a.slot) end
 return back
end
-- Réduction progressive depuis la vitesse actuelle, jamais sous la limite cible : après un freinage ou un virage,
-- l'IA réaccélère librement jusqu'à cette limite au lieu d'être retenue à sa vitesse du moment.
function M.trafficCap(cmd,s,a,p,profile,dt)
 local applied=profile=='J' and p.section_traffic and s.state=='DRIVE'
 local limit=applied and not s.alongside and a.corner>=p.cornerMin and s.trafficLimit or K.unlimitedSpeed
 if limit<K.unlimitedSpeed then
  local start=cmd.speedLimit<K.unlimitedSpeed and cmd.speedLimit or a.kmh
  cmd.speedLimit=U.approach(max(start,limit),limit,K.trafficDecelKmh*dt)
 elseif applied and cmd.speedLimit<a.kmh then cmd.speedLimit=U.approach(cmd.speedLimit,a.kmh,K.trafficAccelKmh*dt)
 else cmd.speedLimit=K.unlimitedSpeed end
 s.trafficApplied=cmd.speedLimit<K.unlimitedSpeed
end
-- Beta 1.42 AERO : carte des lignes droites du circuit, apprise des IA pilotées (part de passages en ligne droite par
-- endroit de l'allure apprise), et longueur des lignes droites recalculée toutes les K.towMapPeriod s : longueur de la
-- ligne droite de chaque endroit et longueur restante devant. Oubliée au changement de circuit ou de découpage.
local function aeroMap(e,frame)
 local m=e.aero; local bins=e.delta.bins
 if not m or m.bins~=bins or m.length~=frame.length then
  m={bins=bins,length=frame.length,st={},seen={},run={},len={},at=-math.huge,session=m and m.session,finalLogged=m and m.finalLogged or false}
  for b=1,bins do m.st[b]=0; m.seen[b]=0; m.run[b]=0; m.len[b]=0 end
  e.aero=m
 end
 if m.session~=frame.session then
  m.session=frame.session; m.finalLogged=false
  -- Relecture 1.42 : carte réapprise à chaque session (celle des essais ne vaut pas pour le premier tour de la course).
  for b=1,m.bins do m.st[b]=0; m.seen[b]=0; m.run[b]=0; m.len[b]=0 end
  m.at=-math.huge
 end
 return m
end
local function straightBin(m,b) return m.seen[b]>=K.towMapSeen and m.st[b]>=K.towStraightShare end
local function aeroRuns(m,now)
 if now<m.at and now>=m.at-K.towMapPeriod then return end
 m.at=now+K.towMapPeriod
 local bins=m.bins; local run,len=m.run,m.len
 local z=0
 for b=1,bins do if not straightBin(m,b) then z=b; break end end
 if z==0 then for b=1,bins do run[b]=bins; len[b]=bins end; return end
 run[z]=0
 for k=1,bins-1 do local b=(z-1-k)%bins+1; run[b]=straightBin(m,b) and run[b%bins+1]+1 or 0 end
 local current,previous=0,false
 for k=1,bins do
  local b=(z-1+k)%bins+1; local straight=run[b]>0
  if straight and not previous then current=run[b] end
  len[b]=straight and current or 0; previous=straight
 end
end
-- Tours d'avance de a sur b (symétrique de Classes.laps).
local function lapsAhead(a,b,rel,length)
 if length<=0 or not a.lapValid or not b.lapValid or not a.splineValid or not b.splineValid or a.lap<1 then return 0 end
 return max(0,math.floor((a.lap+a.spline)-(b.lap+b.spline)+rel.long/length+K.lapTolerance))
end
-- Adversaire direct : même tour (ni attardée, ni voiture qui prend un tour), même classe, ni voiture de sécurité ni
-- voiture aux stands.
local function rival(e,s,a,n,p,frame)
 local other=frame.cars[n.index]; local os=e.states[n.index]
 if other.safetyCar or other.pit then return false end
 if Classes.laps(a,other,n,frame.length)>0 or lapsAhead(a,other,n,frame.length)>0 then return false end
 return not faster(p,s,os) and not faster(p,os,s)
end
-- Plafond anti-zigzag : au moins n changements de côté encore permis dans la minute.
local function directionRoom(s,now,p,n)
 if now<s.driveUntil or now-s.lastDirectionAt<p.lateralCooldown then return false end
 local active=0
 for j=1,K.directionLimit do if now-s.directions[j]<K.directionWindow then active=active+1 end end
 return active<=K.directionLimit-n
end
-- Air sale (0 à 1) : dans le sillage d'une voiture à moins de dirtyAirGap m, en virage, à vive allure ; jamais sous
-- drapeau, au départ, à côté d'une voiture, ni en évitement, reprise au calme ou attente.
local function dirtyAir(e,s,a,front,p,startPhase)
 if not p.dirtyAirEnabled or startPhase or s.yellow or e.incidents.neutral or e.incidents.red or s.alongside or not front or front.long<=0 or front.gap<0
  or front.gap>p.dirtyAirGap or abs(front.lat)>K.dirtyAirLat or a.kmh<K.dirtyAirSpeed or a.corner>=p.cornerMin
  or s.state=='AVOID' or s.state=='CALM' or s.state=='IDLE' then return 0 end
 return U.clamp(1-(front.gap-K.dirtyAirFull)/max(1,p.dirtyAirGap-K.dirtyAirFull),0,1)
end
-- Urgence des derniers tours (0 à 1) : course commencée, finalLaps derniers tours du leader, drapeau vert, un adversaire
-- direct à moins de K.finalRange m devant ou derrière ; montée d'un cran par tour jusqu'au dernier.
local function urgency(e,s,a,row,p,profile,frame,startPhase)
 if profile~='C' or not p.finalLapsEnabled or not frame.started or a.finished or startPhase or s.yellow
  or e.incidents.neutral or e.incidents.red or s.bluePending or s.yieldBlue then return 0 end
 -- Relecture 1.42 : tours restants de la voiture elle-même (le leader arrivé, les autres finissent leur dernier tour ;
 -- course chronométrée : tour qui suit la fin du temps compris), jamais face au joueur.
 local left=Strategy.lapsLeft(e,frame,a)
 if left<1 or left>p.finalLaps then return 0 end
 for j=1,row.count do
  local n=row.neighbors[j]
  if n.gap>=0 and n.gap<=K.finalRange and n.index~=frame.player and rival(e,s,a,n,p,frame) then return (p.finalLaps-left+1)/p.finalLaps end
 end
 return 0
end
-- Aspiration cassée : en tête d'une paire en ligne droite (longue d'au moins towBreakStraight m, au moins
-- K.towMinAheadTime s encore devant), suivie dans son sillage à moins de towBreakRange m par un adversaire direct :
-- une seule manœuvre, du côté opposé à la file du suiveur, tenue jusqu'à K.towReturnTime s de la fin de la ligne
-- droite. Jamais sous drapeau, au freinage, à côté d'une voiture, devant une voiture qui prend un tour (drapeau bleu)
-- ou d'une autre classe, ni sans deux changements de côté encore permis par le plafond anti-zigzag ; une évaluation par
-- ligne droite, attente par voiture et par paire.
local function towStart(e,s,a,back,row,p,profile,frame,now,startPhase,braking,m,i,g)
 if profile~='C' or not p.towBreakEnabled or s.towDone or s.towWait>0 or not back or m.bins<=0 or s.returning or startPhase or s.yellow or e.incidents.neutral
  or e.incidents.red or braking or a.brake>K.ruleBrake or s.alongside or s.bluePending or s.yieldBlue or s.lapseUntil>now or a.corner<K.towCorner
  or a.kmh<K.towSpeed or back.long>=0 or back.gap>p.towBreakRange or abs(back.lat)>K.towLat or back.sa<K.towSaMin
  or e.flash.requests[i].untilTime>now or not directionRoom(s,now,p,2) then return false end
 -- Relecture 1.42 : jamais après une défense sur cette ligne droite (un seul mouvement), au premier tour, face au joueur,
 -- à un suiveur qui arrive vite (plus de K.towSaMax km/h) ou déjà en dépassement, ni près de la sortie des stands (zone
 -- des stands, ou K.towMergeBefore m avant à K.towMergeAfter m après la jonction apprise).
 if s.defendUsed or (a.lap or 0)<1 or back.index==frame.player or back.sa>K.towSaMax or passStates[e.states[back.index].state] then return false end
 if a.pitDistance and a.pitDistance<K.pitZone then return false end
 local junction=e.merge and e.merge.spline or -1
 if junction>=0 and frame.length>0 then
  local after=U.spline(a.spline-junction)*frame.length
  if after>=-K.towMergeBefore and after<=K.towMergeAfter then return false end
 end
 if s.towPair==back.index and s.towPairWait>0 then return false end
 if not rival(e,s,a,back,p,frame) then return false end
 local b=paceBin(a.spline,m.bins); local binLength=frame.length/m.bins
 local straight=m.len[b]*binLength
 if straight<p.towBreakStraight or m.run[b]*binLength<K.towMinAheadTime*a.speed then return false end
 s.towDone=true
 if U.unit(g.seed,i,(a.lap+back.index)*3+K.towSalt)>=K.towChance+K.towAssert*s.persona.assertiveness then return false end
 -- Relecture 1.42 : jamais vers le côté de dépassement imposé par le réglage (le suiveur y déboîte) ; sinon s'éloigner du
 -- suiveur (lat>0 : suiveur du côté gauche, repère interne où -1 est la gauche). Suiveur déjà nettement du côté visé, ou
 -- côté occupé : pas de manœuvre (jamais vers le suiveur).
 local away=back.lat>0 and 1 or -1
 local forced=(p.overtakeSide=='left' or p.overtakeSide=='right') and fixedSide(p.overtakeSide,1,g) or p.overtakeSide=='opposite' and -fixedSide(p.yieldSide,1,g) or 0
 local side=forced~=0 and -forced or away
 if side~=away and abs(back.lat)>K.towLatSide or not sideFree(row,side) then return false end
 s.targetSide=side; s.towing=true; s.defendUntil=now+K.towHoldMax; s.towPair=back.index; s.towPairWait=K.towPairCooldown; s.towWait=K.towCooldown
 -- Un seul mouvement par ligne droite : la défense ne suit pas la cassure (même attaquant, même tour).
 s.defendUsed=true; s.defendAttacker=back.index; s.defendLap=a.lap
 transition(e,s,'DEFEND','tow',now)
 U.log(e.log,now,'INFO',string.format('aspiration: %s casse l aspiration de %s (%.0f m, ligne droite %.0f m)',a.name,frame.cars[back.index].name,back.gap,straight),i)
 return true
end
function M.step(e,i,dt,now)
 local frame=e.frame; local a=frame.cars[i]; local s=e.states[i]; local cmd=e.commands[i]
 local p,g,profile=e.run,e.runtimeG,e.profile; local row=e.perception.rows[i]
 cmd.active=false; a.wet=frame.wet
 if a.player then return end -- État du joueur tenu par le moteur pour sa carte d'allure.
 if not a.valid or not a.control or a.pit or a.offtrack or a.finished or a.safetyCar or s.excluded or s.disqualified or now<s.errorUntil then
  if a.pit then s.pitBefore=true end
  cmd.yellowLimit=K.unlimitedSpeed; s.yellow=false
  transition(e,s,'IDLE','guard',now); return
 end
 local identity=a.identity or a.id
 if a.teleport or s.previousIdentity~=identity then
  -- Beta 1.41 : le rythme relatif de longue durée ne dépend pas de l'endroit : gardé après un déplacement (dépannage,
  -- placement), oublié au changement de voiture.
  if s.previousIdentity~=identity then s.longRatio=1; s.longRatioTime=0 end
  M.reset(s,now,false); s.previousIdentity=identity; s.bop=0
  for j=1,#s.pace do s.pace[j]=0 end
  s.paceCount=0; s.paceMean=0; s.paceRatio=0; s.paceRatioCount=0; s.freePace=0
 end
 if s.pitBefore then
  s.pitBefore=false; s.stint=s.stint+1; s.stintStart=now
  Persona.fill(s.persona,g.seed,i,profile,p,s.stint)
  s.pitExitUntil=now+(p.enduranceOverlay and K.stintExitDelay or K.pitExitDelay)
  -- Beta 1.47 : décalage remis à zéro (rendu à AC dans la voie des stands) ; aucun retour depuis une valeur périmée.
  s.pitCautionUntil=now+K.stintExitCautionTime; s.pitGuardUntil=now+K.pitGuardTime; M.reset(s,now,false)
 end
 a.corner=U.clamp(1-abs(a.yawRate or 0)/p.cornerYawRef,0,1)
 -- Beta 1.42 AERO : attentes de l'aspiration cassée, carte des lignes droites (seulement quand elle sert).
 s.towWait=max(0,s.towWait-dt); s.towPairWait=max(0,s.towPairWait-dt); s.dirtyLogWait=max(0,s.dirtyLogWait-dt)
 local m=aeroMap(e,frame)
 if p.towBreakEnabled and m.bins>0 then
  if a.splineValid and a.kmh>=K.towMapSpeed then
   -- Relecture 1.42 : une zone de freinage n'est pas de la ligne droite (retour à la ligne avant le point de freinage).
   local b=paceBin(a.spline,m.bins); m.st[b]=m.st[b]+((a.corner>=K.towCorner and a.brake<=K.ruleBrake and 1 or 0)-m.st[b])*K.towMapAlpha
   if m.seen[b]<K.towMapSeen then m.seen[b]=m.seen[b]+1 end
  end
  aeroRuns(m,now)
 end
 if s.returning and abs(s.offset-M.reachable(s,a,p,g,s.base))<K.centerEpsilon then s.returning=false end
 Zones.at(e.zones,a.spline,s.zone)
 if a.pitDistance and a.pitDistance<K.pitZone then s.zone.maxOffset=min(s.zone.maxOffset,K.pitOffsetMax) end
 if now>=s.nextPerception then P.refresh(e.perception,frame.cars,frame.count,i,frame.length,e.frames); s.nextPerception=now+K.perceptionPeriod end
 P.occupancy(frame.cars,frame.count,i,g,row)
 -- Drapeau jaune ou neutralisation : limite propre, composée avec l'espacement par l'applicateur, descente bornée.
 local cap,yellow=Incidents.cap(e.incidents,frame,i,p,e.delta,e.states,s.persona.deltaMargin)
 s.yellow=yellow
 -- Sous drapeau (zone jaune et son approche, neutralisation, drapeau rouge) : en file derrière la voiture de devant,
 -- sans la rattraper au-delà d'un léger rapprochement ; jamais derrière une voiture accidentée, arrêtée ou très lente,
 -- qu'il est permis de doubler. Évite qu'une IA rattrape et double celle qui freine la première pour la zone.
 if (yellow or e.incidents.neutral or e.incidents.red) and row.front>0 and row.neighbors[row.front].gap<K.scQueueGap then
  local front=row.neighbors[row.front]; local j=front.index
  -- Voiture qui doit rendre la place à celle-ci (IA ou joueur), qui purge une sanction, ou dont celle-ci reprend la
  -- place : jamais de file derrière elle.
  local owes=Penalties.mayPass(e.penalties,i,j,now,frame.player,e.incidents.neutral and not e.incidents.red)
  if not owes and not Penalties.passable(frame.cars[j],e.incidents.cars[j],p,now) then
   cap=min(cap,max(K.trafficMinSpeed,frame.cars[j].kmh+max(0,front.gap-K.queueKeep)*K.queueClose))
  end
 end
 -- Beta 1.50 (première voiture de sécurité réelle, 5 novembre 14:57 : les IA ont doublé le joueur en tête, puis la
 -- voiture de sécurité) : sous neutralisation (VSC, FCY, voiture de sécurité, tour de relance), file derrière la voiture
 -- la plus proche devant sur la piste, QUELLE QUE SOIT SA FILE (une IA qui se décalait n'avait plus de voiture « devant »)
 -- : joueur, IA ou voiture de sécurité ; seule une voiture accidentée (incident) se double, jamais une voiture qui roule
 -- à l'allure de la neutralisation (le joueur lent ou la voiture de sécurité passaient pour « lents »). Limite posée
 -- aussitôt à moins de 2 x K.queueKeep m.
 local hardQueue=false
 if e.incidents.neutral and not e.incidents.red and a.splineValid and frame.length>0 and not a.pit then
  local best,bj=K.scQueueGap,0
  for j=1,frame.count do
   local b=frame.cars[j]
   if j~=i and b.valid and not b.pit and b.splineValid and not (e.incidents.cars[j] and e.incidents.cars[j].incident) then
    local d=U.spline(b.spline-a.spline)*frame.length-((a.length or K.length)+(b.length or K.length))*0.5
    if d>-1 and d<best and not Penalties.mayPass(e.penalties,i,j,now,frame.player,true) then best=d; bj=j end
   end
  end
  if bj>0 then
   cap=min(cap,max(K.trafficMinSpeed,frame.cars[bj].kmh+max(0,best-K.queueKeep)*K.queueClose))
   hardQueue=best<2*K.queueKeep; s.neutralQueue=bj
  else s.neutralQueue=0 end
 else s.neutralQueue=0 end
 if cap<K.unlimitedSpeed then
  local start=cmd.yellowLimit<K.unlimitedSpeed and cmd.yellowLimit or a.kmh
  cmd.yellowLimit=U.approach(max(start,cap),cap,p.yellowDecel*3.6*dt)
  if hardQueue then cmd.yellowLimit=min(cmd.yellowLimit,cap) end
 else cmd.yellowLimit=K.unlimitedSpeed end
 local front=row.front>0 and row.neighbors[row.front] or nil
 local back=row.back>0 and row.neighbors[row.back] or nil
 local target=P.find(row,s.target)
 -- Voiture accidentée hors du voisinage de même sens (tête-à-queue, contresens) : position relative directe.
 if not target and s.state=='AVOID' and s.target>0 and s.target<=frame.count and e.incidents.cars[s.target].incident then
  target=P.relative(a,frame.cars[s.target],frame.length,s.hazardRel)
 end
 local player=P.find(row,frame.player)
 local request=e.flash.requests[i]
 if request.untilTime>now and (not player or player.long>(a.length+frame.cars[frame.player].length)*0.5+K.passBuffer or player.gap>p.flashRange*K.lostRange) then request.untilTime=0 end
 local ai=e.flash.ai[i]
 if ai.untilTime>now then
  local source=P.find(row,ai.source)
  if not source or source.long>(a.length+frame.cars[ai.source].length)*0.5+K.passBuffer or source.gap>p.flashRange*K.lostRange then ai.untilTime=0 end
 end
 s.playerGap=player and player.gap or math.huge; s.playerSa=player and player.sa or 0
 -- Beta 1.29 (demande du pilote) : hors course, pas de bagarre avec le joueur. Juste doublée par lui (il passe de
 -- derrière à devant, tout près), l'IA ne cherche pas à le repasser pendant K.courtesyTime s ; tant qu'il est collé
 -- derrière, à côté, ou juste devant après l'avoir doublée, elle lâche de l'agressivité : l'IA native ne force plus.
 if player and player.long>0 and s.playerBehind and player.gap<=K.courtesyRange then s.passedByPlayerAt=now end
 s.playerBehind=player~=nil and player.long<=0
 local passedByPlayer=profile~='C' and player~=nil and player.long>0 and now-s.passedByPlayerAt<K.courtesyTime
 local courtesy=profile~='C' and player~=nil and player.gap<=K.courtesyRange and (player.long<=0 or passedByPlayer)
 s.lappedByPlayer=player and Classes.laps(a,frame.cars[frame.player],player,frame.length)>0 or false
 s.alongside=false
 for j=1,row.count do local r=row.neighbors[j]; if r.alongside and abs(r.lat)>=K.nearLine and abs(r.lat)<=g.occLatMax then s.alongside=true; break end end
 local level,aggression,caution=baseModifiers(s,p,now,a)
 s.baseCaution=caution; s.baseAggression=aggression
 if courtesy then aggression=aggression*K.courtesyAggression end
 local desired=0; local elapsed=now-math.max(e.startedAt,e.launchAt or -math.huge)
 cmd.active=true; cmd.brake=0
 local startPhase=profile=='C' and elapsed<p.startDelay+p.startRelax
 -- Beta 1.42 AERO : air sale (sillage en virage) et urgence des derniers tours (agressivité, défense).
 -- Beta 1.47 : premier tour attentif (src/firstlap.lua, poids s.flW) : ni air sale, ni urgence, ni aspiration cassée,
 -- ni défense ; dépassement en vraie ligne droite seulement, évitement d'une voiture arrêtée ou très lente seulement.
 local firstLap=(s.flW or 0)>0
 s.dirty=dirtyAir(e,s,a,front,p,startPhase or firstLap)
 s.urgency=urgency(e,s,a,row,p,profile,frame,startPhase or firstLap)
 if s.urgency>0 then
  -- Relecture 1.42 : jamais d'agressivité en plus avec une attardée, une autre classe ou le joueur juste devant.
  local blocked=front and front.long>0 and front.gap<=K.finalRange and (front.index==frame.player or not rival(e,s,a,front,p,frame))
  if not blocked then aggression=aggression*(1+p.finalAggressionPct/100*s.urgency) end
  if not m.finalLogged then
   m.finalLogged=true
   U.log(e.log,now,'INFO',string.format('fin de course: %d derniers tours, agressivite +%.0f %%, defense +%.0f %%',p.finalLaps,p.finalAggressionPct,p.finalDefensePct),-1)
  end
 end
 -- Règle sportive : aucun changement de trajectoire ne commence au freinage.
 -- Beta 1.30 (essais du pilote : une IA arrivée vite derrière lui, qu'il laissait passer en s'écartant, a ralenti
 -- jusqu'à l'arrêt) : le léger freinage ajouté par l'app (radar avant) n'est pas un freinage du pilote. Compté comme tel,
 -- il interdisait de déboîter (règle du freinage) et de dépasser : l'IA restait derrière, freinée, jusqu'à son allure.
 -- La pédale lue est le maximum du freinage natif et du freinage imposé (API CSP) : au-dessus de celui-ci seulement,
 -- c'est le pilote qui freine.
 local ownBrake=a.brake>s.appBrake+K.brakeEcho and a.brake or 0
 local braking=p.noMoveBraking and ownBrake>K.ruleBrake
 if s.spinHold and a.kmh>=K.calmExitSpeed then s.spinHold=false end
 if profile=='C' and (not frame.started or elapsed<p.startDelay) or now<s.pitExitUntil or s.spinHold then
  transition(e,s,'IDLE','start',now); s.confirm=0; s.pendingAt=0
 else
  if s.state=='IDLE' then transition(e,s,'DRIVE','ready',now) end
  if now-s.speedWindowStart>=K.contactWindow then
   local drop=s.speedWindow-a.kmh
   if p.contactRecovery and drop>=K.contactDrop and row.nearest<K.contactRange then
    s.calmUntil=now+K.calmTime; s.lastContact=now; transition(e,s,'CALM','contact',now)
   end
   s.speedWindow=a.kmh; s.speedWindowStart=now
  end
  if s.state=='CALM' then
   if now>=s.calmUntil then
    if a.kmh>=K.calmExitSpeed then transition(e,s,'DRIVE','calm_end',now) else transition(e,s,'IDLE','spun',now); s.spinHold=true end
   end
   level=level*K.calmLevel; aggression=aggression*K.calmAggression; caution=caution*K.calmCaution
  else
   local obstacle
   if p.obstacleEnabled and (profile~='C' or elapsed>=p.startDelay) then
    local jam=false
    -- Beta 1.47 : premier tour attentif : seule une voiture arrêtée ou très lente (sous K.firstLapAvoidPct de l'allure de
    -- l'IA, ou sous la vitesse d'obstacle) est contournée : une vague de freinage ou une épingle n'est jamais un
    -- obstacle ; refus comptés pour le résumé.
    local slowRef=firstLap and max(p.obstacleSpeedKmh,K.firstLapAvoidPct*a.kmh) or math.huge
    local refused=false
    for j=1,row.count do
     local r=row.neighbors[j]; local other=frame.cars[r.index]
     if firstLap and other.kmh>=slowRef and r.long>0 and r.gap<p.obstacleDetect and abs(r.lat)<=K.latPass then refused=refused or other.slip>K.slipDegrees or e.incidents.cars[r.index].incident==true
     elseif r.long>0 and r.gap<p.obstacleDetect and abs(r.lat)<=K.latPass and (not other.player or other.kmh<=p.obstacleSpeedKmh) then
      -- Beta 1.41 : une IA anormalement lente en tête de file (dégâts : 30 km/h là où sa classe roule à 200) est un
      -- obstacle, même suivie à sa vitesse ; avant, elle était trop rapide pour un obstacle et trop lente pour un
      -- dépassement (zone morte).
      local abnormal=e.states[r.index].abnormal==true
      local slow=other.kmh<p.obstacleSpeedKmh and other.stopped>=K.obstacleTime or other.stopped>=K.stoppedTime or abnormal
      -- Bouchon : une voiture lente que l'on suit déjà au pas n'est pas un obstacle à contourner, sauf incident ;
      -- une voiture en travers l'est toujours.
      local approach=r.sa>=K.obstacleClosing or e.incidents.cars[r.index].incident or abnormal
      if slow and not approach and other.slip<=K.slipDegrees then jam=true end
      if (other.slip>K.slipDegrees or slow and approach) and (not obstacle or r.gap<obstacle.gap) then obstacle=r end
     end
    end
    -- Journal : bouchon suivi sans évitement, compté une fois par épisode.
    if jam and not obstacle and not s.jamNoted then s.jamNoted=true; e.stats.jam=(e.stats.jam or 0)+1 elseif not jam then s.jamNoted=false end
    if not obstacle then
     local nearest,distance=0,math.huge
     for j=1,frame.count do
      local c=e.incidents.cars[j]
      if j~=i and c.incident and c.onTrack then
       local r=P.relative(a,frame.cars[j],frame.length,s.scanRel)
       if r.coherent and r.long>0 and r.gap<p.obstacleDetect and abs(r.lat)<=K.latPass and r.gap<distance then
        if frame.cars[j].kmh>=slowRef then refused=true else nearest=j; distance=r.gap end
       end
      end
     end
     if nearest>0 then obstacle=P.relative(a,frame.cars[nearest],frame.length,s.hazardRel) end
    end
    if refused and not obstacle then
     if not s.flAvoidNoted then s.flAvoidNoted=true; e.stats.flAvoid=(e.stats.flAvoid or 0)+1 end
    else s.flAvoidNoted=false
    end
   end
   if obstacle then
    if s.state~='AVOID' or s.target~=obstacle.index then s.avoidClear=0; s.avoidSide=0 end
    s.target=obstacle.index; target=obstacle; transition(e,s,'AVOID','obstacle',now)
   end
   if s.state=='AVOID' then
    level=level*(1-p.obstacleLevelDrop/100); aggression=aggression*K.avoidAggression; caution=caution*p.obstacleCautionMult
    if target then
     local side=s.avoidSide~=0 and s.avoidSide or target.lat>0 and 1 or target.lat<0 and -1 or (a.leftWidth>a.rightWidth and userSide(-1,g) or a.rightWidth>a.leftWidth and userSide(1,g) or fixedSide(p.yieldSide,1,g))
     -- Obstacle qui glisse vers le côté retenu (tête-à-queue qui traverse la piste) : côté réévalué, jamais vers lui.
     if s.avoidSide~=0 and target.lat*side<-K.nearLine then side=-side; s.avoidSide=0 end
     -- Obstacle au milieu : l'un ou l'autre côté ; décalé : jamais vers lui.
     if s.avoidSide==0 and not sideFree(row,side) and abs(target.lat)<K.nearLine then side=-side end
     if sideFree(row,side) then s.avoidSide=side end
     if sideFree(row,side) and not s.zone.noOvertake and P.corridor(frame.cars,frame.count,i,side,target.gap,target.index,g.occLatMax) then desired=side*min(p.avoidOffset,p.maxSideOffset)
     else level=level*K.obstacleBlockedLevel; desired=s.offset end
     -- Cible repartie à vive allure, sans glisser ni être un incident, pendant une seconde : l'évitement s'achève.
     local other=frame.cars[target.index]
     local moving=not e.incidents.cars[target.index].incident and not e.states[target.index].abnormal and other.kmh>=p.obstacleSpeedKmh+K.avoidClearMargin and other.slip<=K.slipDegrees and other.stopped<K.obstacleTime
     s.avoidClear=moving and s.avoidClear+dt or 0
     if target.long<-K.obstacleClear or s.avoidClear>=K.avoidRecheck then transition(e,s,'DRIVE','obstacle_clear',now) end
    else transition(e,s,'DRIVE','obstacle_lost',now) end
   else
    if now<s.driveUntil then transition(e,s,'DRIVE','direction_limit',now)
    elseif not s.returning and not startPhase and not s.yellow and not braking and s.lapseUntil<=now and not s.alongside and (not yieldStates[s.state] or s.state=='YIELD_OUT') and yieldTrigger(e,s,a,row,p,profile,now,dt) then
     transition(e,s,'YIELD_IN','yield',now)
    -- Retour après dépassement : jamais de nouveau maintien (PDR §10.2.4) ; l'occupation retient le rabattement.
    -- En attente derrière la cible (OVT_ARM), une voiture à côté retient le déboîtement mais ne le saute pas.
    elseif s.alongside and passStates[s.state] and s.state~='OVT_OUT' and s.state~='OVT_ARM' then transition(e,s,'OVT_HOLD','alongside',now) end
    if yieldStates[s.state] then
     -- Sous drapeau jaune, laisser passer revient à se faire dépasser : la cession s'achève.
     if s.yellow and s.state~='YIELD_OUT' then transition(e,s,'YIELD_OUT','yellow',now) end
     local amp=K.cornerAmpMin+(1-K.cornerAmpMin)*a.corner
     desired=s.targetSide*min(p.maxSideOffset,p.yieldOffset*amp*(s.urgent and K.urgentAmp or 1))
     if p.predictableSlowClass and s.yieldClass then desired=s.base end
     if s.state=='YIELD_IN' and abs(s.offset-M.reachable(s,a,p,g,desired))<K.yieldReachedEpsilon then transition(e,s,'YIELD_HOLD','yield_position',now) end
     if s.state~='YIELD_OUT' then
      -- Beta 1.41 : IA déjà anormalement lente (dégâts) : pas de ralentissement de plus pour céder.
      if not s.abnormal then level=level*(1-(s.yieldBlue and K.blueSlowdown or p.yieldSlowdownPct/100)) end; aggression=aggression*K.yieldAggression
      if s.state=='YIELD_HOLD' then caution=caution*K.yieldHoldCaution end
     end
     if target and target.long<0 and target.gap<K.invitationGap then
      s.linger=s.linger+dt
      if (s.linger>K.invitationTime or s.urgent) and not s.abnormal then level=level*(1-p.inviteSlowdownPct/100*U.clamp((s.linger-K.invitationTime)/K.invitationRamp+(s.urgent and 1 or 0),0,1)) end
     end
     local remaining=0
     for j=1,row.count do
      local r=row.neighbors[j]; local other=frame.cars[r.index]
      if r.long<0 and r.gap>=0 and r.gap<=s.yieldDetection and abs(r.lat)<=K.latYield and not yieldStates[e.states[r.index].state] then
       local laps,upper=lapOrClass(e,s,a,other,r,p,profile)
       local qualifies=profile~='C' and p.yieldEnabled and r.sa>=p.yieldBehindMargin or laps>0 and r.sa>=K.lapSpeed or upper and r.sa>=p.classYieldMargin
        or s.yieldQuali and e.quali.push[r.index] and r.sa>=-K.blueSlack
       if qualifies and not s.followers[r.index] then s.followers[r.index]=true; s.holdUntil=max(s.holdUntil,now+p.yieldHoldMin); s.postPass=false end
      end
     end
     for j=1,frame.count do
      if s.followers[j] then
       local r=P.find(row,j)
       if r and r.long<0 and r.sa<K.lostSaRatio*s.yieldMargin and r.gap>K.slowLostGap then s.followerSlow[j]=s.followerSlow[j]+dt else s.followerSlow[j]=0 end
       -- Beta 1.41 : cession ordinaire (ni drapeau bleu, ni classe, ni appel de phares), suiveur qui ne se rapproche plus en
       -- ligne droite, même collé (à moins de K.slowLostGap m) : perdu au bout de K.followerStallTime s (avant, l'IA restait
       -- écartée et ralentie jusqu'à la durée maximale de cession) ; en virage, le compte attend la ligne droite.
       -- Relecture : jamais le joueur (une cession à son appel ou à sa pression n'est jamais perdue ainsi).
       if j==frame.player or not (r and r.long<0 and r.sa<K.followerStallSa and r.gap>K.followerStallGap) or not s.yieldOrdinary then s.followerStall[j]=0
       elseif a.corner>=p.cornerMin then s.followerStall[j]=s.followerStall[j]+dt end
       local passed=r and r.long>(a.length+frame.cars[j].length)*0.5+K.passBuffer
       -- Beta 1.47 (essais du 4 novembre : 69 à 79 % des cessions sans passage) : hors course, oubliée plus tôt.
       local stalled=s.followerStall[j]>(profile=='C' and K.followerStallTime or K.followerStallTimeOff)
       local lost=not r or r.gap>s.yieldDetection*K.lostRange or s.followerSlow[j]>K.slowLostTime or stalled
       if passed then s.yieldPassed=true elseif stalled and j==s.target then s.yieldStalled=true end
       if passed or lost then s.followers[j]=false else remaining=remaining+1 end
      end
     end
     if remaining>=2 and s.yieldBlue then s.multiLeader=true end
     if remaining==0 and s.state~='YIELD_OUT' then
      if not s.postPass then s.holdUntil=max(s.holdUntil,now+s.persona.holdAfter+(s.multiLeader and K.blueTrainHold or 0)); s.postPass=true end
      if now-s.yieldStart>=max(K.holdFloor,p.yieldHoldMin) and now>=s.holdUntil then
       -- Beta 1.41 : « passed » (abouties) seulement si un suiveur est vraiment passé ; suiveurs perdus : « lost » ; perdu
       -- faute de se rapprocher (cession ordinaire), le suiveur principal n'est plus attendu pendant K.passIgnore s.
       if s.yieldQuali then local key=s.yieldPassed and 'qualiPassed' or 'qualiLost'; e.stats[key]=(e.stats[key] or 0)+1 end
       if s.yieldPassed then transition(e,s,'YIELD_OUT','passed',now)
       else
        if s.yieldStalled then s.yieldIgnore=s.target; s.yieldIgnoreUntil=max(s.yieldIgnoreUntil,now+K.passIgnore) end
        transition(e,s,'YIELD_OUT','lost',now)
       end
      end
     end
     if now-s.yieldStart>p.yieldMaxHold and s.yieldQuali and s.state~='YIELD_OUT' then e.stats.qualiLost=(e.stats.qualiLost or 0)+1 end
     if now-s.yieldStart>p.yieldMaxHold then s.ignoreTarget=s.target; s.ignoreUntil=now+K.ignoreFollower; transition(e,s,'YIELD_OUT','hold_limit',now) end
     if s.state=='YIELD_OUT' then desired=s.base; if abs(s.offset-M.reachable(s,a,p,g,s.base))<K.centerEpsilon then transition(e,s,'DRIVE','yield_end',now); s.target=0 end end
    elseif passStates[s.state] then
     if s.yellow and not s.alongside and s.state~='OVT_OUT' then transition(e,s,'OVT_OUT','abort_yellow',now) end
     desired=s.targetSide*p.overtakeOffset*(K.cornerAmpMin+(1-K.cornerAmpMin)*a.corner)
     if not target then
      -- Beta 1.26 : cible perdue de vue un instant (roues hors piste, choix des voisins) : manœuvre tenue sur son
      -- décalage K.targetLostGrace s avant l'abandon ; en préparation, retour à la ligne pendant K.abortSlowTime s.
      s.targetLost=s.targetLost+dt
      local arm=s.state=='OVT_ARM'
      local grace=arm and K.abortSlowTime or s.state~='OVT_OUT' and K.targetLostGrace or 0
      if s.targetLost>=grace then transition(e,s,'OVT_OUT','target_lost',now) else desired=arm and s.base or s.offset end
     else
      s.targetLost=0; s.passMinGap=min(s.passMinGap,target.gap)
      local alongside=target.alongside and s.state~='OVT_ARM'
      if alongside then s.passAlongside=true; s.holdStall=0; s.holdLong=math.huge; if s.state~='OVT_OUT' then transition(e,s,'OVT_HOLD','alongside',now) end; desired=s.offset end
      if s.state=='OVT_IN' and abs(s.offset-M.reachable(s,a,p,g,desired))<K.yieldReachedEpsilon then transition(e,s,'OVT_HOLD','pass_position',now) end
      if not alongside and s.state~='OVT_OUT' then
       local clear=P.corridor(frame.cars,frame.count,i,s.targetSide,K.corridorMin,s.target,g.occLatMax)
       -- Abandon avant le côte à côte seulement (PDR §10.2.4) : ensuite l'IA termine, sauf si la cible repasse devant
       -- et s'éloigne. « La cible s'échappe » ne vaut que pour une cible encore devant.
       s.abortSlow=target.long>0 and target.sa<0 and target.gap>K.abortGap and s.abortSlow+dt or 0
       s.passStall=s.state~='OVT_ARM' and target.long>0 and not s.passAlongside and target.sa<K.passStallSa and s.passStall+dt or 0
       if s.state=='OVT_ARM' and now-s.since>K.passArmMax then s.passStall=K.passStallTime+dt end
       s.passBlocked=not clear and not s.passAlongside and s.passBlocked+dt or 0
       -- Côte à côte achevé sans marge atteinte (cible repassée devant, ou juste derrière à la même allure) : retour au
       -- bout de quelques secondes sans progrès vers la marge ; un dépassement lent qui progresse n'est jamais coupé.
       if s.passAlongside then
        if target.long<s.holdLong-K.holdProgress then s.holdLong=target.long; s.holdStall=0 else s.holdStall=s.holdStall+dt end
       else s.holdStall=0; s.holdLong=math.huge end
       -- Suiveur beaucoup plus rapide : en course, seulement s'il prend un tour ou vient d'une classe plus rapide (on ne
       -- renonce pas à une attaque pour une voiture du même tour qui freine plus tard).
       local fastBack=not s.passAlongside and back and back.sa>=K.abortFollowerSpeed and back.gap<K.abortFollowerGap
        and (profile~='C' or Classes.laps(a,frame.cars[back.index],back,frame.length)>0 or faster(p,e.states[back.index],s))
       if s.passBlocked>K.abortBlocked or s.abortSlow>K.abortSlowTime or s.passStall>K.passStallTime or fastBack or s.holdStall>K.passHoldMax then
        s.aborts=s.aborts+1
        local why=s.passBlocked>K.abortBlocked and 'abort_blocked' or s.abortSlow>K.abortSlowTime and 'abort_slow' or s.passStall>K.passStallTime and 'abort_stall' or fastBack and 'abort_follower' or 'hold_limit'
        transition(e,s,'OVT_OUT',why,now)
        -- Beta 1.41 : cible repartie plus vite : plus de dépassement sur cession ni sur retenue de cette cible pendant
        -- K.passIgnore s, multiplié par K.passIgnoreGrowth à chaque nouvel échec sur elle (au plus K.passIgnoreMax s,
        -- compte oublié K.passIgnoreForget s après la fin de la dernière attente) ; hors course, elle ne lui cède plus
        -- pendant ce temps (jamais un drapeau bleu ni une classe : en course, rien n'est ignoré par elle).
        -- Beta 1.44 : jamais contre le joueur hors course (il ralentit et repart à sa guise pour se faire doubler).
        if why=='abort_slow' and (profile=='C' or s.target~=frame.player) then
         if s.passIgnore~=s.target or now>s.passIgnoreUntil+K.passIgnoreForget then s.passIgnore=s.target; s.passIgnoreCount=0 end
         s.passIgnoreCount=s.passIgnoreCount+1
         local hold=min(K.passIgnoreMax,K.passIgnore*K.passIgnoreGrowth^(s.passIgnoreCount-1))
         s.passIgnoreUntil=now+hold
         local o=e.states[s.target]
         if profile~='C' and not o.yieldBlue then o.yieldIgnore=i; o.yieldIgnoreUntil=max(o.yieldIgnoreUntil,now+hold) end
        end
       end
      end
      if s.state=='OVT_ARM' then
       desired=s.base
       -- Déboîtement en ligne droite seulement (PDR §10.2.4).
       if target.gap<=U.clamp(p.pullOutGapBase+p.pullOutGapPerMps*a.speed,p.pullOutGapBase,K.pullOutMax) and a.corner>=K.passCornerC and not s.alongside and ownBrake<K.passBrakeMax and not braking
        and -target.lat*s.targetSide<K.pullOutTargetLat then transition(e,s,'OVT_IN','pull_out',now) end
      end
      if target.long<-(a.length+frame.cars[target.index].length)*0.5-p.overtakeClearMargin then s.clear=s.clear+dt else s.clear=0 end
      if s.clear>=K.clearConfirm and s.state~='OVT_OUT' then
       if p.overtakeChain and front and front.index~=s.target and front.gap<p.overtakeDetectAhead and P.corridor(frame.cars,frame.count,i,s.targetSide,K.corridorMin,front.index,g.occLatMax) then s.target=front.index; s.clear=0; s.passStall=0; s.passAlongside=false; transition(e,s,'OVT_IN','chain',now)
       else transition(e,s,'OVT_OUT','clear',now) end
      end
     end
     if s.state=='OVT_OUT' then desired=s.base; if abs(s.offset-M.reachable(s,a,p,g,s.base))<K.centerEpsilon then s.restUntil=now+p.overtakeRestTime; s.target=0; transition(e,s,'DRIVE','pass_end',now) end end
     if s.state=='OVT_IN' or s.state=='OVT_HOLD' then aggression=aggression*K.passAggression; caution=min(caution,max(K.slipCautionMin,caution*K.passCaution)) end
    elseif s.state=='DEFEND' and s.towing then
     -- Beta 1.42 AERO : aspiration cassée, côté tenu jusqu'à la fin de la ligne droite ; retour à la ligne (conduite libre,
     -- jamais compté par le plafond) avant le freinage.
     desired=s.targetSide*min(K.towOffset,p.maxSideOffset)
     local ahead=m.bins>0 and m.run[paceBin(a.spline,m.bins)]*frame.length/m.bins or 0
     local req=e.flash.requests[i]
     if now>=s.defendUntil or s.alongside or s.yellow or e.incidents.neutral or e.incidents.red or a.brake>K.ruleBrake or req.untilTime>now or not back
      or not sideFree(row,s.targetSide) or a.corner<p.cornerMin or ahead<K.towReturnTime*a.speed
      or s.towPair>0 and (e.states[s.towPair].state=='OVT_IN' or e.states[s.towPair].state=='OVT_HOLD') then s.towing=false; transition(e,s,'DRIVE','tow_end',now) end
    elseif s.state=='DEFEND' then
     desired=s.targetSide*min(p.defenseMaxOffset,p.maxSideOffset); aggression=aggression*K.defenseAggression; caution=caution*K.defenseCaution
     local req=e.flash.requests[i]
     if now>=s.defendUntil or s.alongside or s.yellow or a.brake>K.ruleBrake or req.untilTime>now or not back or not sideFree(row,s.targetSide) then transition(e,s,'DRIVE','defense_end',now) end
    else
     s.base=userSide(s.persona.laneBias,g)
     if row.nearest>K.jitterRange then s.base=s.base+(math.sin(now/s.persona.jitterPeriod*math.pi*2+s.persona.phase)+0.5*math.sin(now/s.persona.jitterPeriod2*math.pi*2-s.persona.phase))/1.5*p.personalLineJitter end
     -- Beta 1.42 AERO : dans l'air sale, la variation de ligne de l'IA (mêmes ondes, plus rapides) devient des
     -- micro-corrections ; jamais vers un côté occupé, bornée comme la ligne, jamais comptée comme changement de côté.
     if s.dirty>0 and not row.left and not row.right then
      local t=now*K.dirtyJitterRate
      s.base=s.base+(math.sin(t/s.persona.jitterPeriod*math.pi*2+s.persona.phase)+0.5*math.sin(t/s.persona.jitterPeriod2*math.pi*2-s.persona.phase))/1.5*s.dirty*max(K.dirtyJitterAmp,p.personalLineJitter*K.dirtyJitterGain)
     end
     s.base=U.clamp(s.base,-K.baseMax,K.baseMax); desired=s.base
     local defend=false
     -- Défense : jamais au freinage, quel que soit l'onglet Règles.
     local boost=s.urgency>0 and back and back.index~=frame.player and rival(e,s,a,back,p,frame) and 1+p.finalDefensePct/100*s.urgency or 1
     -- Beta 1.47 (Monza, 4 novembre : déport vers le joueur arrivé à gauche, +51 km/h, dans un virage à droite, sur un tour
     -- de sortie) : défense seulement contre un suiveur nettement d'un côté (au moins K.defenseLatMin m), pas beaucoup plus
     -- rapide (au plus K.defenseSaMax km/h, ou contact à K.defenseTTCMin s au moins), en vraie ligne droite avec de la
     -- ligne droite devant (carte des lignes droites, si apprise), jamais à hauteur, sur un tour de sortie, pendant la garde
     -- après les stands ni près de la jonction des stands.
     local defendOk=not firstLap and back~=nil and abs(back.lat)>=K.defenseLatMin and (back.sa<=K.defenseSaMax or back.ttc>=K.defenseTTCMin) and a.corner>=K.defenseCorner
      and not back.alongside and now>=(s.pitGuardUntil or 0) and not (e.strategy and e.strategy.cars[i] and e.strategy.cars[i].outLap)
      and not (a.pitDistance and a.pitDistance<K.pitZone)
     if defendOk and m.bins>0 and a.splineValid and frame.length>0 then
      -- Carte apprise devant (endroit suivant vu, carte calculée) : sinon, rien à juger.
      local b=paceBin(a.spline,m.bins); local nb=b%m.bins+1
      if m.at>-math.huge and m.seen[nb]>=K.towMapSeen and m.run[b]*frame.length/m.bins<K.defenseRunTime*a.speed then defendOk=false end
     end
     local junction=e.merge and e.merge.spline or -1
     if defendOk and junction>=0 and frame.length>0 then local after=U.spline(a.spline-junction)*frame.length; if after>=-K.towMergeBefore and after<=K.towMergeAfter then defendOk=false end end
     if defendOk and not s.returning and not startPhase and not s.yellow and a.brake<=K.ruleBrake and s.lapseUntil<=now and profile=='C' and p.defenseEnabled and back and back.gap<p.defenseTriggerGap*boost and back.sa>0 and a.corner>=K.passCornerC and not s.alongside and now>=s.defendCooldown and directionBudget(s,now,p) and not s.defendUsed and e.flash.requests[i].untilTime<=now then
      local laps,upper=lapOrClass(e,s,a,frame.cars[back.index],back,p,profile)
      if laps==0 and not upper and (s.defendAttacker~=back.index or s.defendLap~=a.lap) then
       s.defendAttacker=back.index; s.defendLap=a.lap
       local probability=min(1,(K.defenseChance+K.defenseAssert*s.persona.assertiveness)*boost)
       local side=back.lat>0 and -1 or 1
       if U.unit(g.seed,i,a.lap+back.index)<probability and sideFree(row,side) then
        s.targetSide=side; s.defendUntil=now+K.defenseTime; s.defendCooldown=now+p.defenseCooldown/boost; s.defendUsed=true; s.towing=false
        transition(e,s,'DEFEND','attacker',now); defend=true
        if now>=(s.defendLogAt or -math.huge) or (s.defendLogAt or 0)-now>K.defenseLogGap then
         s.defendLogAt=now+K.defenseLogGap
         U.log(e.log,now,'INFO',string.format('defense: %s couvre %s cote %s (%.0f m, ecart lateral %.1f m, %+.0f km/h, lacet %.3f rad/s)',a.name,frame.cars[back.index].name,side<0 and 'gauche' or 'droit',back.gap,abs(back.lat),back.sa,abs(a.yawRate or 0)),i)
        end
       end
      end
     end
     if not defend and towStart(e,s,a,back,row,p,profile,frame,now,startPhase or firstLap,braking,m,i,g) then defend=true end
     -- Joueur écarté au-delà de la file de l'IA (il n'est alors pas « la voiture devant ») : cible de l'invitation.
     local front=front
     if frame.player>0 and (not front or front.index~=frame.player) then
      local invitee=P.find(row,frame.player)
      if invitee and invitee.long>0 and invitee.gap<=K.inviteGap and abs(invitee.lat)>=K.inviteLat and abs(invitee.lat)<=K.inviteLatMax
       and (not front or invitee.gap<front.gap) then front=invitee end
     end
     -- Beta 1.31 : terrain gagné sur la voiture de devant (mètres, mémoire de K.closeMemory s), suivi à chaque image,
     -- virages compris : une suite de virages ne le remet pas à zéro.
     if front and front.index==s.closeFront then s.closeMeters=s.closeMeters+(front.sa/3.6-s.closeMeters/K.closeMemory)*dt
     else s.closeFront=front and front.index or 0; s.closeMeters=0 end
     -- Beta 1.41 : derrière une IA anormalement lente, dépassement permis dès K.slowPassRatio fois sa vitesse (à 30 km/h
     -- derrière elle, K.speedMinPass n'était jamais atteinte).
     -- Beta 1.44 (essais du 4 novembre, Nordschleife) : hors course, joueur nettement plus lent que l'IA ici (il ralentit
     -- pour se faire doubler) : dépassement permis au pas (zone morte sous K.speedMinPass) et courtoisie levée.
     local slowPlayer=front~=nil and profile~='C' and front.index==frame.player and playerSlow(e,s,frame.cars[front.index],a,p)
     local slowAhead=front and (e.states[front.index].abnormal==true or slowPlayer)
     local minPass=slowAhead and min(K.speedMinPass,K.slowPassRatio*frame.cars[front.index].kmh) or K.speedMinPass
     local canPass=not s.returning and not startPhase and not s.yellow and not braking and s.lapseUntil<=now and p.overtakeEnabled and front and front.gap>=0 and now>=s.restUntil and directionBudget(s,now,p) and not s.zone.noOvertake and not s.alongside
      and a.kmh>=minPass and a.corner>=(profile=='C' and K.passCornerC or p.cornerMin) and ownBrake<K.passBrakeMax
     -- Beta 1.30 : joueur écarté juste devant (invitation) sans dépassement engagé au bout de K.inviteReport s : la raison
     -- au journal, une fois par épisode.
     local inviting=front and front.index==frame.player and front.long>0 and front.gap<=K.inviteGap and abs(front.lat)>=K.inviteLat and abs(front.lat)<=K.inviteLatMax
     if inviting and not passStates[s.state] and not defend then
      s.inviteWait=s.inviteWait+dt
      if s.inviteWait>=K.inviteReport and not s.inviteLogged then
       s.inviteLogged=true
       local why=s.yellow and 'drapeau jaune' or startPhase and 'depart' or s.returning and 'retour a la ligne' or (braking or ownBrake>=K.passBrakeMax) and 'freinage'
        or a.corner<(profile=='C' and K.passCornerC or p.cornerMin) and 'virage' or now<s.restUntil and 'repos apres manoeuvre' or not directionBudget(s,now,p) and 'plafond anti-zigzag'
        or s.alongside and 'voiture a cote' or a.kmh<minPass and 'trop lent' or not p.overtakeEnabled and 'depassements coupes' or s.zone.noOvertake and 'zone sans depassement'
        or s.lapseUntil>now and 'inattention' or front.sa<=-K.inviteSa and 'joueur plus rapide'
        or profile~='C' and abs(a.yawRate)*a.speed>K.inviteLatAccel and 'virage' or 'conditions de passage'
       U.log(e.log,now,'INFO',string.format('invitation du joueur non suivie: %s derriere a %.0f m (ecart lateral %.1f m, %+.0f km/h, lacet IA %.3f, joueur %.3f rad/s) : %s',
        a.name,front.gap,abs(front.lat),front.sa,abs(a.yawRate),abs(frame.cars[front.index].yawRate),why),i)
      end
     else s.inviteWait=0; s.inviteLogged=false end
     if canPass and not defend then
      local other=frame.cars[front.index]; local margin=p.overtakeAheadMargin*U.lerp(K.assertMin,K.assertMax,s.persona.assertiveness)*U.lerp(K.gapMarginMin,1,front.gap/K.passMarginRange)
      if faster(p,s,e.states[front.index]) then margin=margin*K.classMargin end
      local slowClass=faster(p,e.states[front.index],s)
      local lapped=not C.solo(profile) and Classes.laps(a,other,front,frame.length)>0
      local leaderRow=e.perception.rows[front.index]; local ahead=leaderRow and leaderRow.front>0 and leaderRow.neighbors[leaderRow.front]
      local fight=lapped and ahead and other.speed>0 and ahead.gap/other.speed<K.fightTime and abs(ahead.sa)<K.fightSpeed or false
      local advantage=profile=='C' and K.passAdvantageC or K.passAdvantageJ
      local closing=front.gap<=p.overtakeDetectAhead and front.sa>=margin and front.ttc<=p.overtakeHorizon
      local trigger=closing
      local stuck=s.stuck>=p.stuckTime*s.persona.patience
      local otherState=e.states[front.index]
      -- Beta 1.41 : cible anormalement lente (dégâts) : dépassement sans rapprochement exigé (suivie à sa vitesse, l'IA
      -- ne gagnait jamais de terrain), avance et couloir jugés sur l'allure libre ; jamais ignorée.
      local slowTarget=otherState.abnormal==true and front.gap<=p.overtakeDetectAhead
      -- Beta 1.41 : paire ignorée après un échec « cible plus rapide » ; vraie avance ici (allure libre).
      local ignored=front.index==s.passIgnore and now<s.passIgnoreUntil and not slowTarget
      local adv=realAdvantage(e,s,otherState,a,p)
      -- Beta 1.41 : retenue seulement derrière une cible qui ne s'éloigne pas (au plus K.cessionSaMin km/h, K.retainLossMax m
      -- perdus) et pas plus rapide ici en allure libre (inconnue : permise).
      local stuckTrigger=front.gap<=max(K.stuckGapMin,K.stuckGapTime*a.speed) and stuck and not ignored and front.sa>=-K.cessionSaMin
       and s.closeMeters>-K.retainLossMax and adv~=false
      trigger=trigger or stuckTrigger
      local free=s.freePace
      trigger=trigger or slowTarget
      local potential=max(front.sa,(stuck or slowTarget) and (free-a.speed)*3.6 or 0)
      -- Invitation à passer, course comprise : le joueur juste devant, les deux voitures en ligne droite, s'écarte nettement
      -- de la trajectoire de l'IA qui le suit sans doubler lui-même, ou l'IA de devant lui cède la place. Aucune avance de
      -- vitesse exigée (l'IA native se cale sur la voiture de devant), dépassement direct du côté libéré.
      -- Beta 1.41 : une cession lance le dépassement si l'IA qui cède ne s'éloigne pas (au plus K.cessionSaMin km/h) et, cession
      -- ordinaire, si l'IA est vraiment plus rapide ici (allure libre ; inconnue : avance du moment) ; drapeau bleu et
      -- classe : l'écart de vitesse seul. L'invitation du joueur reste sans condition de vitesse.
      local yieldingToMe=(otherState.state=='YIELD_IN' or otherState.state=='YIELD_HOLD') and otherState.target==i and (not ignored or otherState.yieldBlue) and front.sa>=-K.cessionSaMin
       and (otherState.yieldBlue or adv==true or adv==nil and front.sa>=advantage)
      local invited=yieldingToMe or front.index==frame.player and abs(front.lat)>=K.inviteLat and front.gap<=K.inviteGap and front.sa>-K.inviteSa
       and inviteGeometry(profile,a,other,front) and not busy(frame,front.index,i)
      s.invited=invited and s.invited+dt or 0
      invited=s.invited>=K.inviteTime
      trigger=trigger or invited
      -- Beta 1.47 (boucles : jusqu'à 13 tentatives par paire en 10 min) : paire ignorée après un échec « cible plus rapide »,
      -- plus de dépassement sur simple rapprochement sans vraie avance ici (la retenue et la cession l'étaient déjà).
      if ignored and adv~=true and not (stuckTrigger or slowTarget or invited) then trigger=false end
      -- Beta 1.51 (qualifications) : IA pas lancée (tour de sortie, refroidissement) : jamais à l'attaque d'une voiture
      -- lancée devant elle, sauf invitation ou voiture anormalement lente.
      if trigger and e.quali and e.quali.active and not e.quali.push[i] and e.quali.push[front.index] and not slowTarget and not invited then
       trigger=false
       if s.qualiHeldFor~=front.index then s.qualiHeldFor=front.index; e.stats.qualiNoPass=(e.stats.qualiNoPass or 0)+1 end
      end
      -- Beta 1.29 : hors course, pas de riposte sur le joueur qui vient de la doubler, sauf s'il ralentit nettement.
      if passedByPlayer and front.index==frame.player and not invited and front.sa<K.courtesyPassSa and not slowPlayer then trigger=false end
      if trigger and (potential>=advantage or invited) and not slowClass and not fight then
       if s.passCandidate~=front.index then s.passCandidate=front.index; s.passConfirm=0 end
       -- Beta 1.31 (journaux du 2 novembre : 12 tentatives sur 14 abandonnées, la cible repartant plus vite) : engagé sur
       -- un seul rapprochement, le dépassement attend que l'IA ait vraiment gagné K.passCloseMin m sur la cible (terrain
       -- gagné suivi en continu) ; un écart de vitesse passager (sortie de virage, freinage plus tôt) ne suffit plus.
       local closingOnly=closing and not stuckTrigger and not invited and not slowTarget
       s.passConfirm=s.passConfirm+dt; s.passLost=0
       local side=invited and (front.lat>0 and 1 or -1) or passSide(p,profile,s,front,row,other,g)
       -- Beta 1.41 : cible anormalement lente (zone morte) : écart de vitesse du dépassement = allure libre moins la
       -- vitesse de la cible (suivie à sa vitesse, l'écart du moment, nul, exigeait le couloir le plus long) ; ailleurs,
       -- l'écart du moment, comme avant (relecture).
       local closingSpeed=max(a.speed-other.speed,slowTarget and free-other.speed or 0,K.corridorSpeedMin)
       local req=U.clamp((front.gap+a.length+other.length+2*p.overtakeClearMargin)*a.speed/closingSpeed,K.corridorMin,K.corridorMax)
       if p.overtakeSide=='auto' and yieldStates[otherState.state] and sideFree(row,-otherState.targetSide) then side=-otherState.targetSide end
       local yieldingSame=yieldStates[otherState.state] and otherState.targetSide==side
       -- Beta 1.47 : premier tour attentif : dépassement seulement en vraie ligne droite, hors freinage (le sien, celui de
       -- la cible, ou un point de freinage proche), avec une vraie avance et un couloir plus long ; invitation permise.
       local flHeld=firstLap and not invited and (a.corner<K.firstLapPassCorner or ownBrake>K.ruleBrake or other.brake>(otherState.appBrake or 0)+K.brakeEcho and other.brake>K.ruleBrake
        or s.flApproach or potential<advantage*K.firstLapPassMargin)
       if firstLap then req=req*K.firstLapCorridor end
       if flHeld and s.passConfirm>=p.confirmTime and s.flPassHeldFor~=front.index then s.flPassHeldFor=front.index; e.stats.flPass=(e.stats.flPass or 0)+1 end
       if not flHeld and s.passConfirm>=p.confirmTime and (not closingOnly or s.closeMeters>=(ignored and K.passCloseMin*K.passIgnoreCloseMult or K.passCloseMin)) and sideFree(row,side) and not yieldingSame and P.corridor(frame.cars,frame.count,i,side,req,front.index,g.occLatMax) then
        s.target=front.index; s.targetSide=side; s.clear=0; s.abortSlow=0; s.passBlocked=0; s.passStall=0; s.passAlongside=false
        s.passConfirm=0; s.passCandidate=0
        if invited then s.ignoreTarget=front.index; s.ignoreUntil=now+K.inviteRespite end
        -- Beta 1.31 : chaque tentative au journal (déclencheur, écart, avance), et sa fin à la sortie des états de passage.
        U.log(e.log,now,'INFO',string.format('depassement: %s -> %s (%s, %.0f m, %+.0f km/h)',a.name,other.name,yieldingToMe and 'cession' or invited and 'invitation' or slowTarget and 'cible lente' or closingOnly and 'rapprochement' or 'retenue',front.gap,front.sa),i)
        s.passStartAt=now; s.passMinGap=front.gap; s.passName=other.name; s.lastPassTarget=front.index; s.lastPassAt=now
        transition(e,s,profile=='C' and not invited and 'OVT_ARM' or 'OVT_IN',yieldingToMe and 'yielded' or invited and 'invited' or 'pass',now)
       end
      else
       s.passLost=s.passLost+dt; if s.passLost>K.confirmReset then s.passConfirm=0; s.passCandidate=0 end
      end
     elseif not canPass then s.invited=0; s.passLost=s.passLost+dt; if s.passLost>K.confirmReset then s.passConfirm=0; s.passCandidate=0 end
     end
    end
   end
  end
 end
 if a.corner<K.passCornerC then s.defendUsed=false end
 if a.corner<p.cornerMin then s.towDone=false end
 -- Départ de course (Beta 1.25) : à fond en ligne droite derrière la voiture de devant ; la prudence de départ ne vient
 -- qu'au freinage et en virage (premier virage), vite, et repart lentement (sortie du virage). Lancement : ligne droite
 -- pendant le départ, sans prudence de suivi ; seul un contact vraiment imminent fait freiner le radar.
 local starting=profile=='C' and frame.started and elapsed<p.startDelay+p.startRelax
 if starting then
  -- Beta 1.47 (départs du 4 novembre, Monza et Spa : vagues de freinages radar puis chaînes de chocs par l'arrière au
  -- premier freinage) : le lancement ne tombe plus sur un écart de rotation passager en ligne droite (rotation tenue
  -- K.startYawHold s au-dessus de K.startYaw rad/s), ni sur le frein que l'app impose elle-même (freinage du pilote
  -- seulement) ; il s'arrête K.startAnticipate s avant le premier point de freinage du peloton (le premier qui freine
  -- vraiment), et ne revient plus ensuite (premier freinage, le sien ou celui du peloton juste devant).
  if abs(a.yawRate or 0)>K.startYaw then s.startYawTime=(s.startYawTime or 0)+dt else s.startYawTime=0 end
  local key=e.startedAt+(e.launchAt or 0)
  -- Beta 1.50 (départ réel du 5 novembre, 13:09) : seul un freinage libre (aucune voiture devant à moins de
  -- K.firstLapPointFree s) est le premier freinage du peloton ; un freinage de suivi dans le peloton, dès le lancement,
  -- n'en est pas un (il plaçait le « premier freinage » en pleine ligne droite : anticipation pour tout le peloton,
  -- fin du lancement, frein du départ non plafonné).
  local freeAhead=not front or front.long<=0 or FirstLap.headway(front.gap,a.speed)>=K.firstLapPointFree
  local freeBrake=ownBrake>K.ruleBrake and freeAhead
  if freeBrake and a.kmh>=K.startBrakeKmh then
   s.startBraked=true
   if e.startPackKey~=key and a.splineValid then e.startPackKey=key; e.startPackSpline=a.spline end
  end
  local ahead=e.startPackKey==key and e.startPackSpline~=nil and a.splineValid and frame.length>0
   and ((e.startPackSpline-a.spline)%1)*frame.length<=a.speed*K.startAnticipate
  if ahead then s.startBraked=true end
  s.startAhead=ahead
  local wanted=(s.startBraked or freeBrake or s.startYawTime>=K.startYawHold) and 1 or 0
  s.startCare=U.approach(s.startCare,wanted,(wanted>s.startCare and K.startCareRise or K.startCareFall)*dt)
 else s.startCare=0; s.startYawTime=0; s.startBraked=false; s.startAhead=false end
 local launch=starting and s.startCare<0.5
 -- Beta 1.50 (course du 5 novembre, Monza, 25 voitures : « il y en a toujours un devant qui freine, on ne sait pas
 -- pourquoi ») : ligne droite du départ et du premier tour : pilote qui ne freine pas, voiture droite, hors de
 -- l'anticipation d'un freinage (premier freinage du peloton au départ, point de freinage appris au premier tour).
 -- Pied tenu en aspiration : ni écart en temps, ni prudence du radar ; levée de pied seulement au contact imminent.
 -- Course du 5 novembre, 13:09 (interim 2 en jeu) : l'IA d'AC freine elle-même pour suivre dans le peloton ; ce
 -- freinage de suivi n'est pas une approche de virage : la ligne droite se juge sur la géométrie seule (voiture droite,
 -- hors anticipation du premier freinage du peloton ou d'un point de freinage appris), jamais sur la pédale (sinon la
 -- règle ne s'appliquait presque jamais et la prudence ajoutée faisait freiner davantage).
 local npNear=firstLap and FirstLap.nextPoint(e.fl,a,frame.length)<=max(a.speed,K.firstLapSpeedMin)*K.firstLapAnticipate
 local straightGeom=(starting or firstLap) and a.corner>=K.slipCorner and not (starting and s.startAhead) and not npNear
 local straightRun=straightGeom
 local following=front and front.gap<K.followRange and not s.alongside and (p.section_general or p.section_overtake or s.state~='DRIVE')
 if not following or not p.slipstreamEnabled or a.corner<K.slipCorner or a.kmh<=K.slipSpeed then s.slipTime=0 end
 if following then
  -- Beta 1.50 : en ligne droite du départ et du premier tour, ni prudence de suivi (aspiration, voiture collée).
  if not launch and not straightRun then
   caution=caution*U.lerp(K.followCaution,1,(front.gap-K.followMinGap)/K.followGapRange)*s.persona.brakeMargin
   if front.ttc<K.followTTC then caution=caution*K.followTTCMult end
  end
  if p.slipstreamEnabled and a.corner>=K.slipCorner and a.kmh>K.slipSpeed then s.slipTime=s.slipTime+dt; if s.slipTime>K.slipTime then caution=min(caution,max(K.slipCautionMin,caution*K.slipCaution)) end else s.slipTime=0 end
  if profile=='C' and front.index==frame.player and front.gap<K.playerFollowGap then caution=caution*K.playerCaution end
 end
 -- Beta 1.47 : premier tour attentif : écart en temps (même effet en F1, en GT ou en voiture de route) hors lancement,
 -- et anticipation de chaque freinage du tour (points appris en direct, freinage de la voiture de devant) avec une
 -- voiture à moins de K.firstLapGapTime s devant ; prudence seulement, jamais de frein ni de limite de vitesse.
 if firstLap then
  local close=front~=nil and front.long>0 and front.gap>=0 and FirstLap.headway(front.gap,a.speed)<K.firstLapGapTime
  local approach=false
  if close then
   local fb=frame.cars[front.index].brake; local fs=e.states[front.index]
   approach=FirstLap.nextPoint(e.fl,a,frame.length)<=max(a.speed,K.firstLapSpeedMin)*K.firstLapAnticipate or fb>(fs.appBrake or 0)+K.brakeEcho and fb>K.ruleBrake
  end
  if approach and not s.flApproach then e.stats.flCare=(e.stats.flCare or 0)+1 end
  s.flApproach=approach
  s.flCare=U.approach(s.flCare or 0,approach and 1 or 0,(approach and K.firstLapCareRise or K.firstLapCareFall)*dt)
  -- Montée douce (K.firstLapCareRise par seconde) : jamais un saut de prudence qui ferait freiner tout le peloton.
  local timeFactor=1
  if close and not launch and not straightRun then timeFactor=U.lerp(K.firstLapFollowCaution,1,U.clamp((FirstLap.headway(front.gap,a.speed)-K.firstLapGapMin)/(K.firstLapGapTime-K.firstLapGapMin),0,1)) end
  local wantedFactor=max(timeFactor,U.lerp(1,K.firstLapBrakeCaution,s.flCare))
  s.flFactor=U.approach(s.flFactor or 1,wantedFactor,(wantedFactor>(s.flFactor or 1) and K.firstLapCareRise or K.firstLapCareFall)*dt)
  caution=caution*U.lerp(1,s.flFactor,s.flW)
 end
 -- Radar avant (Beta 1.24) : dès la grille et en toute session, une IA qui va heurter une voiture devant elle dans sa
 -- file (joueur ou IA, la plus proche du contact) lève d'abord le pied (prudence accrue à moins de K.radarWarnTTC s du
 -- contact), puis, contact imminent (moins de K.radarTTC s), ajoute un léger freinage dosé, monté et relâché
 -- progressivement, comme un pilote : jamais de coup de frein, jamais d'écart latéral ; le frein ne fait que s'ajouter.
 -- Une aspiration ou une approche lente n'est pas un contact imminent : rien n'y change.
 local radarTarget=0
 if g.useBrakeAssist then
  local close,closeTTC=nil,math.huge
  for j=1,row.count do
   local r=row.neighbors[j]; local other=frame.cars[r.index]
   if r.long>0 and r.sa/3.6>K.brakeClosing and abs(r.lat)<=(a.width+other.width)*0.5+K.radarLatMargin then
    local ttc=max(0,r.gap)/(r.sa/3.6)
    if ttc<closeTTC then close=r; closeTTC=ttc end
   end
  end
  if close then
   if closeTTC<K.radarWarnTTC and not launch and not straightRun then caution=caution*U.lerp(K.radarCaution,1,closeTTC/K.radarWarnTTC) end
   if closeTTC<(launch and K.radarLaunchTTC or K.radarTTC) then
    radarTarget=U.clamp(close.sa/3.6/K.brakeGain,K.radarMinBrake,K.radarBrakeMax)
    -- Beta 1.47 : départ, avant le premier freinage : freinage plafonné à K.radarStartBrakeMax ; voiture collée derrière
    -- (moins de K.radarStartFollowGap m) : lever de pied seulement, sans frein (un coup de frein en pleine ligne droite
    -- lançait la chaîne de chocs par l'arrière : 51 freinages radar dans les 10 premières secondes à Monza).
    local lift=false
    -- Beta 1.47 : voiture collée derrière en temps (K.radarStartFollowTime s, au moins K.radarStartFollowMin m).
    local followed=back~=nil and back.long<0 and back.gap<max(K.radarStartFollowMin,frame.cars[back.index].speed*K.radarStartFollowTime)
    -- Beta 1.50 : ligne droite du départ et du premier tour, approche modérée (moins de K.radarStraightObstacleKmh km/h :
    -- jamais une voiture arrêtée). Voiture de derrière plus près de son contact que soi du sien : ni levée ni frein, même
    -- quand l'IA d'AC freine elle-même pour suivre (le choc passait à l'arrière : joueur à fond à 6 m derrière une IA qui
    -- levait le pied). Sinon, sans freinage du pilote : pied tenu ; levée dosée seulement à moins de K.radarStraightTTC s
    -- du contact et sans couloir libre à côté ; à moins de K.firstLapLastTTC s : dernier recours, comme avant.
    local straightHold=false
    local pushed=back~=nil and back.long<0 and back.ttc<closeTTC
    -- Raison d'une levée de pied ou d'un frein du départ et du premier tour, dite au journal (audit des départs réels).
    local why150=not (starting or firstLap) and '' or not straightGeom and ((starting and s.startAhead or npNear) and 'anticipation du freinage' or 'courbe')
     or close.sa>=K.radarStraightObstacleKmh and 'approche rapide' or closeTTC<K.firstLapLastTTC and string.format('contact %.1f s, dernier recours',closeTTC)
     or string.format('contact %.1f s, aucun couloir libre',closeTTC)
    local count=function(push)
     if now>=(s.straightHoldAt or -math.huge) or s.straightHoldAt-now>1 then
      s.straightHoldAt=now+1; e.startHold=(e.startHold or 0)+1; e.stats.flHold=(e.stats.flHold or 0)+1
      if push then e.stats.flPushed=(e.stats.flPushed or 0)+1 end
     end
    end
    if straightGeom and pushed and close.sa<K.radarStraightObstacleKmh then straightHold=true; radarTarget=0; count(true)
    elseif straightRun and close.sa<K.radarStraightObstacleKmh and closeTTC>=K.firstLapLastTTC then
     local lane=(not row.left or not row.right) and (a.leftWidth or 0)+(a.rightWidth or 0)>=K.radarLaneWidth
     if closeTTC>=K.radarStraightTTC or lane then straightHold=true; radarTarget=0; count(false)
     else
      radarTarget=0; lift=true; cmd.throttleLimit=min(cmd.throttleLimit or 1,U.lerp(K.radarStartLift,1,closeTTC/K.radarStraightTTC))
     end
    end
    if not straightHold and not lift and starting and not s.startBraked then
     radarTarget=min(radarTarget,K.radarStartBrakeMax)
     if followed then radarTarget=0; lift=true; cmd.throttleLimit=min(cmd.throttleLimit or 1,K.radarStartLift) end
    end
    -- Beta 1.47 : premier tour attentif : levée de pied d'abord ; frein seulement à moins de K.firstLapBrakeTTC s du
    -- contact, au freinage du pilote, léger (K.radarStartBrakeMax) et jamais avec une voiture collée derrière ; en ligne
    -- droite (pilote qui ne freine pas), levée de pied seule ; plein freinage du radar en dernier recours seulement
    -- (contact à moins de K.firstLapLastTTC s : vrai obstacle).
    if firstLap and not lift and not straightHold then
     if closeTTC>=K.firstLapBrakeTTC or (followed or ownBrake<=K.ruleBrake) and closeTTC>=K.firstLapLastTTC then radarTarget=0; lift=true; cmd.throttleLimit=min(cmd.throttleLimit or 1,K.radarStartLift)
     elseif closeTTC>=K.firstLapLastTTC then radarTarget=min(radarTarget,K.radarStartBrakeMax) end
     if not lift and s.radarBrake==0 then e.stats.flBrake=(e.stats.flBrake or 0)+1 end
    end
    if launch and s.radarBrake==0 and not lift and not straightHold then e.startRadar=(e.startRadar or 0)+1 end
    -- Levers de pied du départ comptés (au plus un par voiture et par seconde) pour le bilan du journal.
    if lift and (now>=(s.startLiftAt or -math.huge) or s.startLiftAt-now>1) then s.startLiftAt=now+1; e.startLift=(e.startLift or 0)+1; if firstLap then e.stats.flLift=(e.stats.flLift or 0)+1 end end
    if not straightHold and s.radarBrake==0 and (now>=s.radarLogAt or s.radarLogAt-now>K.radarLogPeriod) then
     s.radarLogAt=now+K.radarLogPeriod
     U.log(e.log,now,'INFO',string.format('radar avant: %s %s derriere %s (%.0f m, %.0f km/h plus vite)%s',a.name,lift and 'leve le pied' or 'freine',frame.cars[close.index].name,close.gap,close.sa,
      (back and back.long<0 and string.format(', suiveur a %.0f m',back.gap) or '')..(why150~='' and ' ('..why150..')' or '')),i)
    end
   end
  end
 end
 s.radarBrake=U.approach(s.radarBrake,radarTarget,(radarTarget>s.radarBrake and K.radarApply or K.radarRelease)*dt)
 if s.radarBrake>0 then cmd.brake=max(cmd.brake,s.radarBrake) end
 -- Freinage imposé par l'app à cette image : relu dans la pédale à l'image suivante.
 s.appBrake=cmd.brake
 -- Départ (course) : prudence et agressivité de départ dès la grille, pleines jusqu'à la fin de l'attente (premier virage
 -- compris), puis ramenées à la normale pendant la détente ; aucun déplacement commandé d'ici là.
 if profile=='C' and (not frame.started or elapsed<p.startDelay+p.startRelax) then
  local relax=frame.started and (elapsed-p.startDelay)/p.startRelax or 0
  local care=frame.started and s.startCare or 1
  caution=caution*U.lerp(U.lerp(1,p.startCautionMult,care),1,relax); aggression=aggression*U.lerp(U.lerp(1,p.startAggrMult,care),1,relax)
  s.laneActive=false
  if s.state~='AVOID' then desired=p.startLaneHold and laneHold(e,s,a,row,g,frame,now,i) or 0 end
 elseif s.lane~=0 or s.laneActive then s.lane=0; s.laneActive=false
 end
 -- Beta 1.47 : premier tour attentif : agressivité au plus K.firstLapAggr de la base.
 if firstLap then aggression=min(aggression,U.lerp(aggression,s.baseAggression*K.firstLapAggr,s.flW)) end
 local allowLapse=p.lapseEnabled and not s.alongside and s.state~='DEFEND' and s.state~='YIELD_IN' and s.state~='IDLE' and s.state~='CALM'
 s.fatigue=p.enduranceOverlay and now-s.lastContact>K.fatigueTime and K.fatigueGain or 1
 if now>=s.lapseAt and allowLapse then
  s.lapseCount=(s.lapseCount+1)%K.counterMax; Persona.nextLapse(s.persona,g.seed,i,s.lapseCount,p)
  s.lapseUntil=now+s.persona.lapseDuration; s.lapseAt=now+s.persona.lapseInterval/min(K.fatigueMax,s.fatigue)
 end
 if s.lapseUntil>now and allowLapse then
  local ramp=min((s.persona.lapseDuration-(s.lapseUntil-now))/K.lapseRamp,(s.lapseUntil-now)/K.lapseRamp,1)
  level=level*(1-s.persona.lapseDrop*max(0,ramp))
 elseif s.lapseUntil<=now then s.lapseUntil=0 end
 if s.bluePending then level=level*K.lapCornerLevel end
 if s.alongside and s.state~='AVOID' then aggression=p.section_general and p.aggressionPct/100*K.maxAggression or a.baseAggression or a.aiAggression; desired=s.offset; if passStates[s.state] then caution=caution*K.alongsideCaution end end
 -- Sortie des stands : prudence accrue derrière une voiture proche (joueur compris).
 local pitGuard=now<s.pitGuardUntil and front and front.gap<K.pitGuardGap
 if pitGuard then caution=caution*K.pitGuardCaution end
 if a.brake>K.brakeEmulationPedal or front and front.gap<K.brakeEmulationRange and front.sa/3.6>K.brakeEmulationClosing then
  caution=caution*(1+K.brakeEmulationGain*(p.brakeZonePct-100)/100)*s.persona.brakeMargin
 end
 if s.state~='DRIVE' then s.blockedYield=0 end
 if s.blockedYield>K.blockedYieldTime and back and back.gap<K.blockedYieldGap and not s.abnormal then level=level*(1-p.yieldSlowdownPct/100) end
 -- Appel de phares d'une IA réellement retenue sous son allure derrière la voiture de devant (en course : tour ou
 -- classe). Une classe rapide qui s'approche sans être gênée n'appelle pas : la lutte de la classe lente continue.
 if p.aiFlashEnabled and front and front.gap>=0 and not s.yellow and not startPhase and now-s.aiFlashAt>=K.aiFlashCooldown
  and a.kmh>K.flashSpeed and a.corner>=p.cornerMin and s.state~='IDLE' and s.state~='CALM' and s.state~='AVOID' then
  local other=frame.cars[front.index]; local otherState=e.states[front.index]
  local free=s.freePace
  local held=front.gap<K.aiFlashGap and s.stuck>=p.stuckTime and (free-other.speed)*3.6>=p.flashMinAdvantage
  local allowed=held and profile~='C'
  if held and profile=='C' then
   allowed=faster(p,s,otherState) or Classes.laps(other,a,P.relative(other,a,frame.length,s.scanRel),frame.length)>0
  end
  if allowed and other.control and not other.player and not yieldStates[otherState.state] then
   local request=e.flash.ai[front.index]
   s.aiFlashAt=now; cmd.flashEvent=(cmd.flashEvent%K.counterMax)+1; e.stats.flash=(e.stats.flash or 0)+1
   U.log(e.log,now,'INFO',string.format('appel de phares: %s -> %s',a.name,other.name),i)
   request.source=i; request.untilTime=now+p.flashRequestTTL
   request.readyAt=now+U.clamp(otherState.persona.reaction or K.neutralReaction,K.flashReactionMin,K.flashReactionMax)
  end
 end
 -- Overtake Mode (F1 2026) : à moins de l'écart choisi derrière la voiture de devant au point de détection (fin du
 -- tour), gain de niveau dans les lignes droites du tour suivant. Coupé sous drapeau, sous la pluie, et après le départ
 -- ou une reprise tant que le leader n'a pas atteint le point de détection.
 if profile=='C' and p.overtakeMode and not s.yellow and not startPhase and not e.weather.wet and e.drsRule.leader>=K.overtakeDetect then
  if s.overtakeSpline>=0 and s.overtakeSpline<K.overtakeDetect and a.spline>=K.overtakeDetect and a.spline-s.overtakeSpline<0.5 then
   s.overtakeArmed=front~=nil and a.speed>0 and front.gap/a.speed<=p.overtakeModeGap
  end
  if s.overtakeArmed and a.corner>=p.cornerMin then level=level*(1+p.overtakeModeBoostPct/100) end
 else s.overtakeArmed=false end
 s.overtakeSpline=a.splineValid and a.spline or -1
 if braking and s.state~='AVOID' and s.state~='CALM' then desired=s.offset end
 if s.zone.noYield and yieldStates[s.state] or s.zone.noOvertake and passStates[s.state] then desired=s.base end
 if a.corner<K.returnCornerMin and (s.state=='YIELD_OUT' or s.state=='OVT_OUT' or s.state=='DRIVE') then desired=s.offset end
 if s.state=='IDLE' then desired=s.laneActive and s.lane or 0; s.confirm=0; s.pendingAt=0 end
 if frame.length<=0 or not a.splineValid then desired=0 end
 -- Repos anti-zigzag : jamais au détriment d'un évitement ou d'une récupération en cours.
 -- Beta 1.47 : jamais au détriment d'un drapeau bleu (céder au plus rapide passe avant le plafond).
 if now<s.driveUntil and s.state~='AVOID' and s.state~='CALM' and not (s.yieldBlue and yieldStates[s.state]) then desired=0; if s.state~='IDLE' then transition(e,s,'DRIVE','direction_limit',now) end end
 cmd.offset=M.lateral(s,desired,row,a,p,g,dt,now)
 if s.newDirectionLimit then s.newDirectionLimit=false; e.stats.limit=(e.stats.limit or 0)+1; U.log(e.log,now,'WARN',limitText(s,now),i) end
 -- Beta 1.31 (têtes-à-queue répétés aux mêmes freinages en descente, Acque Minerali et Rivazza) : en freinage ou en
 -- virage, jamais moins prudente ni plus agressive que sa base. L'aspiration, le dépassement et la poursuite
 -- abaissaient la prudence, lissée sur 0,4 s, jusque dans le freinage. Remontée rapide de la prudence.
 local protect=ownBrake>K.ruleBrake or a.corner<p.cornerMin
 if protect then caution=max(caution,s.baseCaution); aggression=min(aggression,s.baseAggression) end
 if passStates[s.state] or yieldStates[s.state] or s.state=='DEFEND' then s.maneuverAt=now end
 -- Beta 1.42 AERO : air sale, accélérateur limité (au plus dirtyAirLiftPct % de moins) ; épisodes comptés.
 if s.dirty>0 then
  cmd.throttleLimit=min(cmd.throttleLimit or 1,1-p.dirtyAirLiftPct/100*s.dirty)
  if not s.dirtyBefore then e.stats.dirtyAir=(e.stats.dirtyAir or 0)+1 end
  if e.runtimeG.debugLog and s.dirtyLogWait<=0 and front then
   s.dirtyLogWait=K.dirtyLogPeriod
   U.log(e.log,now,'DEBUG',string.format('air sale: %s derriere %s (%.0f m)',a.name,frame.cars[front.index].name,front.gap),i)
  end
 end
 s.dirtyBefore=s.dirty>0
 -- Beta 1.47 : premier tour attentif : prudence d'ensemble plafonnée à K.firstLapCautionMax fois la prudence de base
 -- (départ, suivi, radar et freinage cumulés montaient à 3 ou 4 : peloton au pas à l'entrée du premier virage), hors
 -- drapeau jaune, neutralisation et drapeau rouge.
 if firstLap and not s.yellow and not e.incidents.neutral and not e.incidents.red then caution=min(caution,U.lerp(caution,s.baseCaution*K.firstLapCautionMax,s.flW)) end
 local tau=s.state=='CALM' or s.state=='AVOID'
 tau=tau and K.fastModulatorTau or s.state=='YIELD_OUT' and K.yieldRecoveryTau or s.yieldBlue and yieldStates[s.state] and K.blueRecoveryTau or K.modulatorTau
 cmd.level=U.ema(cmd.level,U.clamp(level,K.minNativeLevel,1.1),dt,tau)
 cmd.aggression=U.ema(cmd.aggression,U.clamp(aggression,0,K.maxAggression),dt,aggression<cmd.aggression and protect and K.fastModulatorTau or tau)
 cmd.caution=U.ema(cmd.caution,U.clamp(caution,0.5,K.maxCaution),dt,caution>cmd.caution and protect and K.fastModulatorTau or tau)
 cmd.levelOwned=p.section_general or abs(cmd.level-(a.baseLevel or a.aiLevel))>=K.levelEpsilon
 cmd.aggressionOwned=p.section_general or abs(cmd.aggression-(a.baseAggression or a.aiAggression))>=K.aggrEpsilon
 cmd.cautionOwned=p.section_general or abs(cmd.caution-K.defaultCaution)>=K.cautionEpsilon
 M.trafficCap(cmd,s,a,p,profile,dt)
 -- Beta 1.41 (journées circuit du 3 novembre : cessions sans fin en ligne droite, le niveau ne change pas la vitesse de
 -- pointe) : en cession (pas en sortie), un suiveur à moins de K.yieldCapGap m derrière ou à sa hauteur, en ligne droite
 -- au-delà de K.yieldCapMinKmh km/h : vitesse de pointe réduite de K.yieldTopCut km/h sous l'allure libre apprise à
 -- chaque endroit (inconnue : sous la vitesse du début de la réduction), atteinte en douceur, montant librement avec
 -- elle, rendue dès que la cession s'achève, au virage ou sans suiveur proche.
 local close=false
 if s.state=='YIELD_IN' or s.state=='YIELD_HOLD' then
  for j=1,row.count do local r=row.neighbors[j]; if s.followers[r.index] and (r.alongside or r.long<0 and r.gap<K.yieldCapGap) then close=true; break end end
 end
 if close and a.corner>=p.cornerMin and a.kmh>=K.yieldCapMinKmh then
  if not s.yieldCap then s.yieldCap=a.kmh-K.yieldTopCut; s.yieldCapNow=a.kmh end
  local target=max(K.trafficMinSpeed,s.freePace>0 and s.freePace*3.6-K.yieldTopCut or s.yieldCap)
  s.yieldCapNow=target>=s.yieldCapNow and target or U.approach(s.yieldCapNow,target,K.trafficDecelKmh*dt)
  cmd.speedLimit=min(cmd.speedLimit,s.yieldCapNow)
 else s.yieldCap=nil; s.yieldCapNow=nil end
 -- Sortie des stands : une fois le limiteur levé, jamais de rattrapage brutal de la voiture de devant. Écart de
 -- vitesse permis de 7,5 à 15 km/h selon l'assurance, réduit avec la distance, négatif si elle est trop près.
 if pitGuard then
  local ahead=frame.cars[front.index].kmh
  local margin=K.pitGuardAllowance*U.lerp(0.5,1,s.persona.assertiveness)*U.clamp((front.gap-K.pitGuardMin)/(K.pitGuardGap-K.pitGuardMin),0,1)
  local cap=front.gap<K.pitGuardMin and ahead-K.pitGuardBack or ahead+margin
  cmd.speedLimit=math.min(cmd.speedLimit,math.max(math.min(K.trafficMinSpeed,ahead),cap))
 end
 s.brakeDemand=cmd.brake; s.cornerBefore=a.corner
 -- Journal des drapeaux bleus (Beta 1.24) : IA en retard d'un tour ou plus devant le joueur, à portée : une ligne quand
 -- elle le laisse passer, une autre si elle tarde (plus de K.blueLogTime s), avec la raison. Sous drapeau jaune,
 -- neutralisation ou drapeau rouge, céder est interdit : l'attente est suspendue, rien n'est noté.
 local flagged=s.yellow or e.incidents.neutral or e.incidents.red
 if flagged then
 elseif profile=='C' and p.blueFlagEnabled and s.lappedByPlayer and s.playerGap<=p.blueFlagRange and (s.playerSa>0 or s.playerGap<=K.blueCloseGap) then
  s.blueWait=s.blueWait+dt
  s.blueClear=0
  if yieldStates[s.state] and s.target==frame.player then
   if not s.blueYieldLogged then s.blueYieldLogged=true; U.log(e.log,now,'INFO',string.format('drapeau bleu: %s laisse passer le joueur apres %.1f s',a.name,s.blueWait),i) end
  elseif s.blueWait>=K.blueLogTime and not s.blueWaitLogged then
   s.blueWaitLogged=true
   U.log(e.log,now,'INFO',string.format('drapeau bleu: %s devant le joueur depuis %.0f s sans le laisser passer (%s, %.0f m, %+.0f km/h)',a.name,s.blueWait,s.blueReason or 'en attente',s.playerGap,s.playerSa),i)
  end
 elseif s.playerGap>p.blueFlagRange*2 or not s.lappedByPlayer then
  -- Beta 1.47 : oubli après K.blueClearTime s seulement (« laisse passer » écrit deux fois en 6 s quand le tour d'écart
  -- vacillait au passage de la ligne).
  s.blueClear=(s.blueClear or 0)+dt
  if s.blueClear>=K.blueClearTime then s.blueWait=0; s.blueYieldLogged=false; s.blueWaitLogged=false; s.blueReason=nil end
 end
 pace(s,a,row,dt,p,e.delta.fleet[p.multiClass and s.class or 1],e.delta.bins)
 if front then s.gap=front.gap; s.sa=front.sa; s.ttc=front.ttc end
end
M.pace=pace
return M
