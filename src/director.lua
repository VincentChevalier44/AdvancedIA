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
local Rear=require('src/rear')
local Priority=require('src/priority')
local Nuance=require('src/nuance')
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
  calmUntil=0,speedWindow=0,speedWindowStart=0,lastContact=0,
  lapseAt=0,lapseUntil=0,lapseCount=0,radarBrake=0,startCare=0,radarLogAt=-math.huge,blueWait=0,blueYieldLogged=false,blueWaitLogged=false,slipTime=0,errorCount=0,errorUntil=0,excluded=false,
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
 s.passIgnore=0; s.passIgnoreUntil=0; s.passIgnoreCount=0; s.passReopened=nil; s.followerStall={}; s.yieldPassed=false; s.yieldOrdinary=false; s.yieldStalled=false; s.yieldCap=nil; s.yieldCapNow=nil
 -- Relecture : suiveur que l'IA n'attend plus (cession perdue, échec « cible plus rapide ») ; jamais un drapeau bleu ni
 -- une classe. Demande d'arrêt d'une IA lente et endommagée (course).
 s.yieldIgnore=0; s.yieldIgnoreUntil=0; s.slowPitAsked=false; s.slowPitDone=false
 -- Beta 1.55 : progrès d'une tentative, cession refusée, appels de phares suspendus (voir le bloc k155 de config.lua).
 s.passProgRef=0; s.passProgTime=0; s.noAdvFor=0; s.noAdvAt=0; s.yieldFlashBy=0
 s.flashFailTarget=0; s.flashFailCount=0; s.flashFailAt=0; s.flashMute=0; s.flashMuteUntil=0; s.flashHoldTarget=0; s.flashHoldUntil=0
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
 s.cornerGiveUntil=0; s.cornerEntryAt=0; s.cornerLift=1; s.cornerGiveTo=0; s.cornerPhase=false; s.cornerOut=0; s.passBrakeFree=false; s.yieldQueueFor=0
 s.holdUntil=0; s.linger=0; s.stuck=0; s.blocked=0; s.passBlocked=0; s.invited=0; s.passStall=0; s.abortSlow=0; s.clear=0; s.passAlongside=false
 s.calmUntil=0; s.spinHold=false; s.postPass=false; s.alongside=false; s.velocity=0; s.filtered=keepOffset and s.offset or 0
 for j=1,K.maxCars do s.followers[j]=false; s.followerSlow[j]=0; s.followerStall[j]=0 end
 if not preserveErrors then s.errorUntil=0; s.excluded=false; s.errorCount=0 end
 s.direction=0; s.directionCount=0; s.directionHead=0; s.driveUntil=0; s.returning=keepOffset==true
 s.passConfirm=0; s.passCandidate=0; s.passLost=0; s.targetLost=0; s.holdStall=0; s.holdLong=math.huge
 s.lastDirectionAt=-math.huge; for j=1,K.directionLimit do s.directions[j]=-math.huge end
 s.defendUntil=0; s.defendCooldown=0; s.defendAttacker=0; s.defendLap=-1; s.defendUsed=false
 -- Beta 1.60 : engagement de l'aide au dépassement et conscience de l'arrière oubliés avec la manœuvre.
 s.committed=0; s.commitSide=0; s.aidLogged=0; s.rearLeftUntil=nil; s.rearRightUntil=nil; s.defendLate=false
 s.ignoreTarget=0; s.ignoreUntil=0; s.lapseUntil=0; s.bluePending=false; s.yieldBlue=false; s.yieldQuali=false; s.yieldLine=false; s.urgent=false
 s.passIgnore=0; s.passIgnoreUntil=0; s.passIgnoreCount=0; s.passReopened=nil; s.yieldPassed=false; s.yieldCap=nil; s.yieldCapNow=nil; s.yieldIgnore=0; s.yieldIgnoreUntil=0
 s.passProgRef=0; s.passProgTime=0; s.noAdvFor=0; s.noAdvAt=0; s.yieldFlashBy=0
 s.flashFailTarget=0; s.flashFailCount=0; s.flashFailAt=0; s.flashMute=0; s.flashMuteUntil=0; s.flashHoldTarget=0; s.flashHoldUntil=0
 s.blockedYield=0; s.radarBrake=0; s.speedWindowStart=now; s.speedWindow=0
 s.trafficReference=0; s.trafficApplied=false; s.yellow=false; s.overtakeArmed=false; s.overtakeSpline=-1; s.yieldClass=false
 if not keepOffset then s.offset=0 end
 s.lane=0; s.laneActive=false; s.laneLatched=false; s.laneMeters=0; s.laneLogged=false
 -- Beta 1.52 : refus comptés (tours lancés, premier tour attentif) oubliés.
 s.qualiHeldFor=nil; s.flPassHeldFor=nil
 s.towing=false; s.towDone=false; s.dirty=0; s.dirtyBefore=false; s.urgency=0
end
function M.configure(s,g,profile,p,now)
 Persona.fill(s.persona,g.seed,s.slot or 0,profile,p,s.stint)
 s.lapseAt=now+s.persona.lapseInterval
end
-- Beta 1.41 : toutes les raisons d'une fin de tentative en clair (« guard » et « yield » restaient en anglais).
local passEnd={clear='reussi',chain='reussi, enchaine',abort_slow='cible plus rapide',abort_blocked='cote ferme',abort_stall='sans rapprochement',abort_follower='suiveur rapide',
 target_lost='cible perdue',abort_yellow='drapeau jaune',hold_limit='cote a cote sans progres',direction_limit='plafond anti-zigzag',
 guard='rendue a AC (stands, hors piste ou hors commande)',yield='cede a son suiveur',obstacle='evitement d un obstacle',contact='contact, reprise au calme',spun='tete-a-queue',
 abort_noprogress='sans progres',abort_timeout='tentative trop longue',corner_priority='priorite au virage (nez derriere)'}
-- Beta 1.60 : raisons de fin d'une cession dites au journal (ligne « cession finie »).
local yieldEnd={passed='suiveur passe',lost='suiveur perdu',hold_limit='duree maximale',yellow='drapeau jaune',guard='rendue a AC (stands, hors piste ou hors commande)',
 obstacle='evitement d un obstacle',contact='contact, reprise au calme',spun='tete-a-queue',direction_limit='plafond anti-zigzag'}
-- Beta 1.55 : cession sur l'appel de phares de l'IA f finie sans passage : comptée pour f ; à K.flashFailLimit (compte
-- oublié après K.flashFailForget s), plus d'appel de f vers cette voiture pendant K.flashMuteTime s, noté une fois.
-- Beta 1.60 (lot 3) : tour de la voiture i pendant les tours lancés (journal des cessions) ; '' hors essais et
-- qualifications.
local function lapTag(e,i)
 local q=e.quali
 if not (q and q.active and i and i>0) then return '' end
 if q.push[i] then return 'tour lance' end
 local why=q.cars[i].why
 return why~='' and why or 'pas lance'
end
local function flashFailed(e,s,now)
 local f=e.states[s.yieldFlashBy]
 if not f then return end
 if f.flashFailTarget~=s.slot or now>f.flashFailAt+K.flashFailForget then f.flashFailTarget=s.slot; f.flashFailCount=0 end
 f.flashFailCount=f.flashFailCount+1; f.flashFailAt=now
 if f.flashFailCount>=K.flashFailLimit then
  local count=f.flashFailCount
  f.flashMute=s.slot; f.flashMuteUntil=now+K.flashMuteTime; f.flashFailCount=0
  if e.stats then e.stats.flashMuted=(e.stats.flashMuted or 0)+1 end
  local cars=e.frame and e.frame.cars
  U.log(e.log,now,'INFO',string.format('appels de phares suspendus: %s -> %s apres %d cessions sans passage, plus d appel pendant %.0f s',
   cars and cars[f.slot] and cars[f.slot].name or '?',cars and cars[s.slot] and cars[s.slot].name or '?',count,K.flashMuteTime),f.slot)
 end
end
-- Fin d'une tentative de dépassement au journal, avec sa raison (Beta 1.52 : aussi à l'enchaînement sur la voiture
-- suivante, qui ne quitte pas les états de passage).
-- Beta 1.62 (relecture 162v, point 5) : raisons de fin de tentative déjà comptées dans le résumé (réussies ou annulées) ;
-- toute autre fin (cession, obstacle, contact, garde, plafond anti-zigzag, départ, remise à zéro) va dans pass_other,
-- pour que tentés = réussis + annulés sur la minute (hors tentatives à cheval sur deux minutes).
local passCounted={clear=true,chain=true,abort_blocked=true,abort_slow=true,abort_stall=true,abort_follower=true,target_lost=true,abort_yellow=true,abort_noprogress=true,abort_timeout=true,corner_priority=true,hold_limit=true}
local function passFinished(e,s,reason,now)
 if U.finite(s.passStartAt) then
  if not passCounted[reason] and e.stats then e.stats.pass_other=(e.stats.pass_other or 0)+1 end
  if reason=='clear' or reason=='chain' then e.passDone=s.slot end -- Beta 1.61 : lu puis effacé par le moteur (src/zonelearn.lua)
  local car=e.frame and e.frame.cars[s.slot]
  -- Beta 1.60 : décalage voulu, atteint et permis par la largeur de piste pendant la tentative (preuve en jeu de la
  -- borne par côté de M.reachable), quand la tentative a demandé un décalage.
  -- Journal du Hungaroring (11 novembre) : « permis » était la plus petite borne de toute la tentative, relevée à un
  -- autre instant que « atteint », avec les largeurs de cet instant-là : illisible. La ligne dit maintenant le plus
  -- grand décalage atteint, en mètres, son côté, et à part la borne la plus basse rencontrée.
  local detail=s.pWant and string.format(' ; decalage voulu %.2f, atteint %.2f soit %.1f m vers la %s, borne la plus basse %.2f',s.pWant,s.pPeak or 0,s.pPeakM or 0,s.pPeakRight and 'droite' or 'gauche',s.pBound or 0) or ''
  U.log(e.log,now,'INFO',string.format('depassement fini: %s -> %s : %s apres %.1f s (ecart mini %.0f m%s)',car and car.name or '?',s.passName,passEnd[reason] or reason,now-s.passStartAt,s.passMinGap,detail),s.slot)
 end
 s.pWant=nil; s.pPeak=nil; s.pBound=nil; s.pPeakM=nil
 s.frankFor=nil; s.frankAt=nil
 s.passStartAt=-math.huge
end
local function transition(e,s,state,reason,now)
 if s.state==state then return end
 -- Affinage 1.62 : recherche de l'aspiration seulement en conduite libre et en attente de déboîtement.
 if state~='DRIVE' and state~='OVT_ARM' then s.seekFront=0; s.seekAt=nil end
 -- Beta 1.31 : fin d'une tentative de dépassement de l'app (sortie des états de passage), avec sa raison.
 if passStates[s.state] and s.state~='OVT_OUT' and not passStates[state] or state=='OVT_OUT' and passStates[s.state] and s.state~='OVT_OUT' then
  passFinished(e,s,reason,now)
 end
 -- Beta 1.52 : fin d'une cession à une voiture lancée (sortie de YIELD_IN ou YIELD_HOLD, quelle qu'en soit la raison :
 -- passage, suiveur perdu, durée maximale, drapeau jaune, évitement, reprise au calme, garde) comptée une fois : passées
 -- et perdues font le total des cessions en tour lancé.
 if (s.state=='YIELD_IN' or s.state=='YIELD_HOLD') and state~='YIELD_IN' and state~='YIELD_HOLD' and s.yieldQuali and e.stats then
  local key=s.yieldPassed and 'qualiPassed' or 'qualiLost'; e.stats[key]=(e.stats[key] or 0)+1
 end
 -- Beta 1.52 : cession prioritaire (drapeau bleu, classe, tour lancé) oubliée à la sortie des états de cession : restée
 -- vraie, elle coupait l'urgence des derniers tours et l'aspiration cassée, annulait une place à rendre et bloquait
 -- l'attente réciproque jusqu'à la remise à zéro suivante.
 if yieldStates[s.state] and not yieldStates[state] then s.yieldBlue=false; s.yieldQuali=false; s.yieldClass=false end
 -- Beta 1.55 : fin d'une cession comptée par raison (résumé de la minute) ; cession sur l'appel de phares d'une IA finie
 -- sans passage : comptée pour elle (hors course).
 if (s.state=='YIELD_IN' or s.state=='YIELD_HOLD') and state~='YIELD_IN' and state~='YIELD_HOLD' then
  if e.stats then local key='yieldEnd_'..reason; e.stats.yieldEnd=(e.stats.yieldEnd or 0)+1; e.stats[key]=(e.stats[key] or 0)+1 end
  -- Beta 1.60 (qualifications à Silverstone du 11 novembre : le pilote voit les IA lever le pied sans quitter la
  -- trajectoire) : fin de chaque cession au journal, avec le décalage voulu, le plus grand décalage atteint, la plus
  -- petite borne permise par la largeur de piste pendant la cession et les largeurs à cet instant (preuve en jeu).
  if s.yWant then
   local cars=e.frame and e.frame.cars; local car=cars and cars[s.slot]; local other=cars and cars[s.target]
   -- Largeurs et côté relevés à l'instant du plus grand décalage atteint ; borne la plus basse de la cession à part.
   U.log(e.log,now,'INFO',string.format('cession finie: %s -> %s : %s apres %.1f s (decalage voulu %.2f, atteint %.2f soit %.1f m vers la %s, piste alors %.1f m a gauche, %.1f m a droite ; borne la plus basse %.2f%s)',
    car and car.name or '?',other and other.name or '?',yieldEnd[reason] or reason,now-(s.yieldStart or now),s.yWant,s.yPeak or 0,s.yPeakM or 0,s.yRightSide and 'droite' or 'gauche',s.yLeft or 0,s.yRight or 0,s.yBound or 0,
    s.yieldSwapped and ' ; cote regle sans place, autre cote pris' or ''),s.slot)
   s.yWant=nil; s.yPeak=nil; s.yBound=nil; s.yPeakM=nil
   -- Beta 1.60 (lot 3) : essais et qualifications, tours des deux voitures (qui était lancée, qui chauffait ses pneus).
   local tag=lapTag(e,s.slot)
   if tag~='' then U.log(e.log,now,'INFO',string.format('tours de la cession: %s (%s), suiveur %s (%s)',car and car.name or '?',tag,other and other.name or '?',lapTag(e,s.target)),s.slot) end
  end
  if s.yieldFlashBy>0 and not s.yieldPassed and e.profile~='C' then flashFailed(e,s,now) end
  s.yieldFlashBy=0
 end
 -- Beta 1.55 : hors course, tentative finie « suiveur rapide » ou « cède à son suiveur » : pas d'appel de phares vers
 -- sa cible pendant K.flashAfterAbort s (avant : l'IA, toujours retenue, rappelait au bout de 8 s).
 if passStates[s.state] and s.state~='OVT_OUT' and (reason=='abort_follower' or reason=='yield') and e.profile~='C' and s.lastPassTarget>0 then
  s.flashHoldTarget=s.lastPassTarget; s.flashHoldUntil=max(s.flashHoldUntil,now+K.flashAfterAbort)
  if e.stats then e.stats.flashHeld=(e.stats.flashHeld or 0)+1 end
 end
 -- Beta 1.54 : état quitté gardé pour le contexte d'un tête-à-queue (ce que faisait l'IA juste avant).
 s.prevState=s.state; s.prevReason=s.reason
 s.state=state; s.reason=reason; s.since=now
 local stats=e.stats; if stats then stats[reason]=(stats[reason] or 0)+1
  -- Relecture d'ensemble 1.62 : fins de dépassement par priorité au virage ou maintien trop long, comptées à part (les
  -- mêmes raisons servent aussi aux cessions et à la défense) pour que tentés = réussis + annulés dans le résumé.
  if state=='OVT_OUT' and passStates[s.prevState] and (reason=='hold_limit' or reason=='corner_priority') then stats['pass_'..reason]=(stats['pass_'..reason] or 0)+1 end
 end
 if e.runtimeG.debugLog then U.log(e.log,now,'DEBUG',state..':'..reason,s.slot) end
end
-- Classe plus rapide (numéro plus petit) : seulement entre deux voitures déjà classées.
M.transitionTest=transition -- relecture d'ensemble 1.62 : tests du décompte des fins de dépassement
local function faster(p,a,b) return p.multiClass and a.classified and b.classified and a.class<b.class end
local function sideFree(row,side) return side<0 and not row.left or side>0 and not row.right end
-- Allure libre apprise d'une voiture à l'endroit b (m/s) : la sienne, sinon celle de sa classe corrigée de son rythme
-- relatif (comme s.freePace) ; 0 inconnue. Jamais le maximum des deux (Delta.pace), qui rendrait deux voitures égales.
local function freeAt(e,s,b,p)
 local v=s.pace[b] or 0
 if v>0 then return v end
 local fleet=e.delta.fleet[p.multiClass and s.class or 1]
 if fleet and s.paceRatioCount>=K.paceRatioMin and (fleet[b] or 0)>0 then return fleet[b]*s.paceRatio end
 -- Beta 1.61 (bus des modificateurs, src/pacemap.lua) : allure gardée des sessions précédentes, dernier repli ; champ absent : neutre.
 if s.prior and (s.prior[b] or 0)>0 then return s.prior[b]*(s.priorRatio or 1) end
 return 0
end
M.freeAt=freeAt -- Beta 1.61 : allure libre connue à une place (tests, src/pacemap.lua)
-- Beta 1.41 (journées circuit du 3 novembre : 72 à 100 % des dépassements finis sur « cible plus rapide », la même paire
-- jusqu'à 16 fois de suite) : vraie avance de la voiture s sur la voiture o à l'endroit de a, allure libre plus rapide
-- d'au moins K.passFreeMargin ; nil si l'une des deux allures y est inconnue.
local function realAdvantage(e,s,o,a,p)
 local b=Delta.bin(a.spline,e.delta.bins)
 local mine,theirs=freeAt(e,s,b,p),freeAt(e,o,b,p)
 if mine<=0 or theirs<=0 then return nil end
 return mine>=theirs*(1+K.passFreeMargin)
end
-- Beta 1.59 (journées circuit du 10 novembre : 393 et 685 cessions refusées, des files derrière des voitures au même
-- rythme) : hors course, refus de céder seulement à un suiveur f nettement plus lent ici que la voiture s (allure libre
-- de plus de K.yieldRefuseKmh km/h sous la sienne) ; inconnue ou voisine : cession. En course, règle de la Beta 1.55.
local function yieldRefused(e,f,s,a,p,profile)
 if profile=='C' then return realAdvantage(e,f,s,a,p)==false end
 local b=Delta.bin(a.spline,e.delta.bins)
 local mine,theirs=freeAt(e,f,b,p),freeAt(e,s,b,p)
 if mine<=0 or theirs<=0 then return false end
 -- Beta 1.60 (même séance : 32 refus en 9 minutes entre voitures identiques, dont la plus rapide de la séance refusée
 -- par une voiture 1,5 s plus lente au tour) : l'allure apprise à un endroit est bruitée (trafic, trajectoire) ; un
 -- suiveur au rythme d'ensemble meilleur que le sien de K.yieldOverallMargin (rythme relatif à la classe, connu des deux) n'est
 -- jamais refusé tant qu'il n'est pas plus lent ici de plus de K.yieldRefuseOverallKmh km/h.
 if f.paceRatioCount>=K.paceRatioMin and s.paceRatioCount>=K.paceRatioMin and f.paceRatio>s.paceRatio*(1+K.yieldOverallMargin) and (theirs-mine)*3.6<=K.yieldRefuseOverallKmh then return false end
 return (theirs-mine)*3.6>K.yieldRefuseKmh
end
-- Beta 1.59 (journées circuit du 10 novembre : files derrière une voiture lente, les voitures 2 à n jamais en
-- dépassement) : voiture devant elle-même anormalement lente, ou dans la file d'une tête anormalement lente : chaîne
-- remontée sur au plus K.slowQueueLinks voitures, chacune à moins de K.slowFollowGap m de la suivante et pas plus lente
-- qu'elle de plus de K.slowLeadMargin km/h (file serrée qui roule à l'allure de sa tête).
local function queueSlow(e,frame,front)
 if not front then return false end
 local index=front.index
 for _=1,K.slowQueueLinks do
  if e.states[index].abnormal==true then return true end
  local r=e.perception.rows[index]; local ahead=r and r.front>0 and r.neighbors[r.front]
  if not ahead or ahead.long<=0 or ahead.gap>=K.slowFollowGap or frame.cars[ahead.index].kmh>frame.cars[index].kmh+K.slowLeadMargin then return false end
  index=ahead.index
 end
 return e.states[index].abnormal==true
end
-- Beta 1.44 : joueur nettement plus lent que l'allure libre de l'IA s ici (moins de K.playerSlowRatio fois elle ;
-- inconnue : seulement sous K.speedMinPass*K.playerCrawlRatio km/h, au pas). Jamais son allure apprise à lui : apprise à
-- chaque image en conduite libre, elle suit sa vitesse du moment quand il ralentit.
local function playerSlow(e,s,b,a,p)
 local mine=freeAt(e,s,Delta.bin(a.spline,e.delta.bins),p)
 if mine>0 then return b.speed<mine*K.playerSlowRatio end
 return b.kmh<K.speedMinPass*K.playerCrawlRatio
end
-- Beta 1.51 (qualifications) : IA i pas lancée (tour de sortie, refroidissement) derrière la voiture j lancée.
-- Beta 1.52 : garde commune au déclenchement du dépassement, à son enchaînement et à l'appel de phares.
local function qualiGuard(e,i,j) return e.quali and e.quali.active and not e.quali.push[i] and e.quali.push[j] end
-- Beta 1.60 (lot 3, passage franc) : la voiture j cède à la voiture i (hors course, ou drapeau bleu, classe, tour lancé)
-- et a vraiment quitté la trajectoire : décalage d'au moins K.frankOffM m (dans l'échelle du côté pris), ou, largeurs
-- inconnues, K.frankClear m de jeu latéral entre les deux voitures (rel : voisin j vu de i).
local function frankYield(e,frame,i,j,profile,g,rel)
 local ts=e.states[j]
 if not ts or not (ts.state=='YIELD_IN' or ts.state=='YIELD_HOLD') or not (ts.followers and ts.followers[i]) then return false end
 if profile=='C' and not ts.yieldBlue then return false end
 local a,b=frame.cars[i],frame.cars[j]
 if ts.yieldLine then
  -- Beta 1.62 (journée circuit, décision 1) : la cible garde sa ligne et lève le pied : franc dès qu'elle cède, si
  -- l'attaquant a la place de passer à côté d'elle (bord à K.reachEdgeMargin m), marge K.jPassMargin m en plus en
  -- journée circuit ; largeurs inconnues : franc.
  -- Relecture 1.62 (M2) : la place se juge au-delà de la cible (elle garde sa ligne : ses largeurs de part et d'autre),
  -- sur le côté qu'elle laisse le plus large, celui que passSide choisit.
  local room=max(b.leftWidth or 0,b.rightWidth or 0)
  if room<=0 then return true end
  return room-b.width*0.5-K.reachEdgeMargin>=a.width+K.frankClear+(profile=='J' and K.jPassMargin or 0)
 end
 local w=ts.offset*g.offsetSign>0 and (b.rightWidth or 0) or (b.leftWidth or 0)
 if w>0 then
  -- Relecture du lot 3 (S9) : franc seulement si le passage existe : décalage de la cible (m) plus la place de
  -- l'attaquant de l'autre côté (bord à K.reachEdgeMargin m) au moins égaux aux deux demi-largeurs plus K.frankClear m ;
  -- sinon les règles ordinaires (abandons permis). Largeurs de l'attaquant inconnues : comme avant.
  local off=abs(ts.offset-(ts.base or 0))*w
  if off<K.frankOffM then return false end
  local mine=ts.offset*g.offsetSign>0 and (a.leftWidth or 0) or (a.rightWidth or 0)
  if mine>0 and off+max(0,mine-a.width*0.5-K.reachEdgeMargin)<(a.width+b.width)*0.5+K.frankClear then return false end
  return true
 end
 return rel~=nil and abs(rel.lat)>=(a.width+b.width)*0.5+K.frankClear
end
-- Beta 1.62 (règles par session, audit du 11 novembre) : « ligne droite » jugée sur la rotation ET sur l'accélération
-- latérale |lacet|·v (K.cornerLatRef m/s² pour 1) : une courbe rapide (0,7 g à 250 km/h) n'est plus une ligne droite.
-- Toutes les gardes « en ligne droite / pas en virage » lisent a.corner, calculé ici une fois par image.
function M.cornerness(yaw,speed,ref)
 local y=abs(yaw or 0)
 return U.clamp(min(1-y/ref,1-y*max(speed or 0,0)/K.cornerLatRef),0,1)
end
-- Beta 1.62 : journée circuit (décision 1 du pilote) : avec yieldSide « line », la voiture qui cède garde sa ligne et
-- lève le pied ; c'est le plus rapide qui se décale. Gardes de dépassement de la course en journée circuit aussi
-- (dépasser seulement en ligne droite).
local function straightRules(profile) return profile=='C' or profile=='J' end
M.frankYieldTest=function(e,frame,i,j,profile,g,rel) return frankYield(e,frame,i,j,profile,g,rel) end -- Beta 1.62 : tests
-- Beta 1.47 : premier tour attentif : dépassement retenu hors vraie ligne droite, au freinage (le sien, celui de la
-- cible, ou un point de freinage proche) ou sans vraie avance. Beta 1.52 : commun au déclenchement et à l'enchaînement.
local function firstLapHeld(s,a,other,otherState,ownBrake,potential,advantage)
 return a.corner<K.firstLapPassCorner or ownBrake>K.ruleBrake or other.brake>(otherState.appBrake or 0)+K.brakeEcho and other.brake>K.ruleBrake
  or s.flApproach or potential<advantage*K.firstLapPassMargin
end
-- Invitation : en course, les deux voitures en ligne droite (rayon K.inviteCurve), comme avant ; hors course
-- (Beta 1.44), courbe douce permise (au plus K.inviteLatAccel m/s² de part et d'autre), l'écart latéral moins celui que
-- la courbure seule donne à cette distance (k·d²/2) devant valoir K.inviteLat.
local function inviteGeometry(profile,a,b,rel)
 if straightRules(profile) then return abs(a.yawRate)<=K.inviteCurve*a.speed and abs(b.yawRate)<=K.inviteCurve*b.speed end
 if abs(a.yawRate)*a.speed>K.inviteLatAccel or abs(b.yawRate)*b.speed>K.inviteLatAccel then return false end
 local k=abs(a.yawRate)/max(a.speed,1)
 return abs(rel.lat)-k*rel.long*rel.long*0.5>=K.inviteLat
end
-- Côté de l'interface, convention SDK (+1 = droite), converti dans le repère latéral interne calibré.
local function userSide(side,g) return g.offsetSign<0 and -side or side end
local function fixedSide(value,fallback,g) return userSide(value=='left' and -1 or value=='right' and 1 or fallback,g) end
-- Beta 1.60 (relecture de la borne par côté) : le côté réglé est une préférence. Place (m) vers le côté interne
-- side : gauche ou droite réelles selon le signe écrit (side × offsetSign), src M.room plus bas ; largeurs inconnues :
-- nil (rien ne change). Cession : côté réglé sans K.sideMinRoom m de décalage permis alors que l'autre en a et est
-- libre : l'autre côté (une cession qui ne peut pas bouger est pire) ; « auto » : côté qui a de la place d'abord.
local sideRoom
-- Relecture du lot 3 (S7) : jamais d'échange de côté vers un suiveur déjà décalé de ce côté-là (au moins
-- K.sideFollowerLat m ; « auto » s'écarte du suiveur : côté -1 pour un suiveur à lat<0).
local function towards(rel,side) return rel~=nil and abs(rel.lat)>=K.sideFollowerLat and side==(rel.lat<0 and 1 or -1) end
local function yieldSide(p,rel,ordinary,row,g,s,a)
 local value=ordinary and p.yieldSide or p.blueFlagSide
 local room=s and a and sideRoom(s,a,p,g,1)~=nil
 if value~='auto' then
  local side=fixedSide(value,1,g)
  if room and sideRoom(s,a,p,g,side)<K.sideMinRoom and sideRoom(s,a,p,g,-side)>=K.sideMinRoom and sideFree(row,-side) and not towards(rel,-side) then return -side,true end
  return side
 end
 local preferred=rel and rel.lat<0 and -1 or 1
 if room and sideFree(row,preferred) and sideFree(row,-preferred) and sideRoom(s,a,p,g,preferred)<K.sideMinRoom and sideRoom(s,a,p,g,-preferred)>=K.sideMinRoom and not towards(rel,-preferred) then return -preferred,true end
 if sideFree(row,preferred) then return preferred end
 return -preferred
end
local function passSide(p,profile,s,front,row,other,g,a)
 -- Relecture d'ensemble 1.62 : « opposé » n'a de sens qu'avec un côté de cession fixe ; avec « auto » ou « line » (le
 -- côté de cession n'est pas connu d'avance), le dépassement suit la règle automatique au lieu de toujours passer à gauche.
 -- Affinage 1.62 (12 novembre : « si le joueur ralentit beaucoup sur le côté, l'IA reste derrière ») : voiture devant
 -- déjà écartée de la trajectoire d'au moins K.inviteLat m : le côté qu'elle a libéré, s'il est libre, avant le côté
 -- réglé (le côté réglé est alors pris par elle : règle de sécurité de la décision 6 du pilote) ; au banc, l'IA visait
 -- la gauche réglée où le joueur s'était rangé et le radar la freinait derrière lui.
 if abs(front.lat)>=K.inviteLat then local freed=front.lat>0 and 1 or -1; if sideFree(row,freed) then return freed end end
 if p.overtakeSide=='opposite' and (p.yieldSide=='left' or p.yieldSide=='right') then return -fixedSide(p.yieldSide,1,g) end
 if p.overtakeSide=='left' or p.overtakeSide=='right' then return fixedSide(p.overtakeSide,1,g) end
 local preferred=front.lat>0 and 1 or front.lat<0 and -1 or (other.yawRate~=0 and U.sign(other.yawRate) or s.persona.personalSide)
 if profile~='C' and p.yieldSide=='line' then
  -- Beta 1.62 (journée circuit, décision 1) : « line » : la voiture lente garde sa ligne ; le plus rapide passe du côté
  -- qui a le plus de place (largeurs inconnues : comme en course).
  -- Relecture 1.62 (M2) : côté jugé au-delà de la cible (ses largeurs : elle garde sa ligne) ; inconnues : celles de
  -- l'attaquant.
  local w1=other and (1*g.offsetSign>0 and other.rightWidth or other.leftWidth) or 0
  local w2=other and (-1*g.offsetSign>0 and other.rightWidth or other.leftWidth) or 0
  if g.offsetSign~=0 and (w1 or 0)>0 and (w2 or 0)>0 then preferred=w1>=w2 and 1 or -1
  else
   local rl,rr=a and sideRoom(s,a,p,g,-1),a and sideRoom(s,a,p,g,1)
   if rl and rr then preferred=rr>=rl and 1 or -1 end
  end
 elseif profile~='C' and (p.yieldSide=='left' or p.yieldSide=='right') then preferred=-fixedSide(p.yieldSide,1,g) end
 if sideFree(row,preferred) then return preferred end
 if sideFree(row,-preferred) then return -preferred end
 return s.persona.assertiveness>K.passSideAssert and 1 or -1
end
M.passSideTest=passSide -- relecture 1.62 (M2) : tests
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
-- Changements de côté retenus dans la fenêtre du plafond (K.directionWindow s).
local function activeDirections(s,now)
 local active=0
 for j=1,K.directionLimit do if now-s.directions[j]<K.directionWindow then active=active+1 end end
 return active
end
local function directionAllowed(s,desired,now,p,emergency,intended,frozen)
 -- Beta 1.41 (journées circuit du 3 novembre : 16 cibles figées sur 156 changements notés, 41 retours à la ligne notés
 -- du côté opposé) : une cible figée sur le décalage du moment (freinage, voiture à côté) n'est ni un changement ni un
 -- côté visé, le côté gardé reste celui de la dernière vraie manœuvre ; la ligne est la ligne personnelle de l'IA (sa
 -- variation va jusqu'à K.baseMax d'un côté, et le retour vise exactement s.base), pas seulement le centre.
 if frozen and not emergency then return true end
 -- Affinage 1.62 : position de recherche de l'aspiration (s.seekAt) tenue comme la ligne personnelle.
 local line=desired==s.base or s.seekAt~=nil and (intended or desired)==s.seekAt or abs(desired)<=K.sideDeadband
 local direction=line and 0 or desired>0 and 1 or -1
 if direction==s.direction then return true end
 -- Évitement, récupération et relâchement d'urgence : jamais retenus ni comptés par le plafond (PDR §7.5).
 if emergency then s.direction=direction; s.lastDirectionAt=now; return true end
 if now-s.lastDirectionAt<p.lateralCooldown then return false end
 local active=activeDirections(s,now)
 -- Avertissement une fois par déclenchement, pas à chaque refus pendant le repos.
 if active>=K.directionLimit then if now>=s.driveUntil then s.newDirectionLimit=true; s.limitState=s.state; s.limitSide=direction end; s.limitIntended=intended or desired; s.driveUntil=now+K.directionRest; return false end
 s.directionHead=s.directionHead%K.directionLimit+1; s.directions[s.directionHead]=now; s.directionStates[s.directionHead]=s.state; s.directionSides[s.directionHead]=direction; s.directionCount=active+1
 s.directionIntended[s.directionHead]=intended or desired
 s.direction=direction; s.lastDirectionAt=now
 return true
end
-- Changement de côté encore permis par le plafond (repos et délai écoulés, moins de six dans la minute) : une cession ou
-- un dépassement ne commence pas s'il serait aussitôt refusé.
-- Plafond anti-zigzag : au moins n changements de côté encore permis dans la minute.
local function directionRoom(s,now,p,n)
 if now<s.driveUntil or now-s.lastDirectionAt<p.lateralCooldown then return false end
 return activeDirections(s,now)<=K.directionLimit-n
end
local function directionBudget(s,now,p) return directionRoom(s,now,p,1) end
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
-- Borne de décalage par la largeur de piste. Le décalage de CSP va de -1 (bord gauche) à +1 (bord droit) : sa valeur en
-- mètres dépend du côté visé. Borne d'origine, des deux côtés : (petit côté - demi-voiture) / grand côté, sûre quelle
-- que soit l'échelle, mais presque nulle quand la trajectoire longe un bord (1,5 m d'un côté, 10,5 m de l'autre :
-- 0,05, soit un demi-mètre vers le grand côté).
-- Beta 1.60 (qualifications à Silverstone du 11 novembre : les IA lèvent le pied sans quitter la trajectoire) : vers le
-- GRAND côté seulement, la borne est la place réelle de ce côté : au plus K.reachWideMeters m hors de la trajectoire,
-- K.reachWideShare du côté, et jamais à moins d'une demi-voiture plus K.reachEdgeMargin m du bord ; elle doit tenir
-- ici ET aux deux points lus plus loin (a.leftAhead…, src/snapshot.lua), où ce côté doit encore être le grand côté
-- (sinon la borne d'origine de ce point s'applique : la voiture revient avant que la trajectoire ne traverse la piste).
-- Vers le petit côté : borne d'origine, inchangée. Côté visé : droite quand le décalage écrit (desired × offsetSign,
-- src/applier.lua) est positif, comme pour le maintien de ligne. Largeurs lues plus loin absentes : borne d'origine.
local function sideBound(left,right,half,toRight)
 local narrow,wide=min(left,right),max(left,right)
 local bound=max(0,narrow-half)/wide
 local width=toRight and right or left
 -- Affinage 1.62 (Monaco, 12 novembre : cession à 3,6 m d'un côté de 5,6 m, montée sur le vibreur puis le mur) : bord
 -- réel gardé à K.reachWideEdge m de la carrosserie ; côté annoncé plus large que K.reachSideMax m : compté comme avant
 -- (K.reachEdgeMargin, plafond de K.reachWideMeters m : grands côtés inchangés).
 if width>=wide and wide>narrow then bound=max(bound,min(K.reachWideShare,K.reachWideMeters/width,max(0,min(width-half-K.reachWideEdge,K.reachSideMax-half-K.reachEdgeMargin))/width)) end
 return bound
end
local function widthBound(s,a,p,toRight,free)
 local half=a.width*0.5
 local usable=max(0,min(a.leftWidth,a.rightWidth)-half)
 local bound=usable/max(a.leftWidth,a.rightWidth)
 -- Relecture : conduite libre (DRIVE, IDLE : variation de ligne, biais de journée circuit) : borne d'origine ; la place
 -- du grand côté ne sert qu'aux manœuvres (cession, dépassement, défense, évitement). N6 : côté annoncé plus large
 -- que K.reachSideMax m (dégagement compté dans la largeur de certains circuits) : compté pour K.reachSideMax m.
 if not free and a.leftWidth~=a.rightWidth and K.reachWideShare>0 and (a.leftAhead or 0)>0 and (a.rightAhead or 0)>0 and (a.leftAhead2 or 0)>0 and (a.rightAhead2 or 0)>0 then
  local wide=min(sideBound(a.leftWidth,a.rightWidth,half,toRight),sideBound(a.leftAhead,a.rightAhead,half,toRight),sideBound(a.leftAhead2,a.rightAhead2,half,toRight))
  if wide>bound then bound=wide end
 end
 return min(p.maxSideOffset,s.zone.maxOffset,bound)
end
-- Correctif 1.61 (tour de formation, décision du pilote du 11 novembre : zigzag d'un bord à l'autre) : borne du zigzag,
-- vers chaque côté sa place réelle moins une demi-voiture et K.formWeaveEdge m, ici et aux deux points lus plus loin
-- (jamais une roue dehors là où la piste se resserre), au plus K.formWeaveMax ; largeurs lues plus loin absentes :
-- borne d'origine.
local function weaveBound(a,toRight)
 local half=a.width*0.5
 local function side(l,r) local w=toRight and r or l; return w>0 and max(0,w-half-K.formWeaveEdge)/w or 0 end
 if not ((a.leftAhead or 0)>0 and (a.rightAhead or 0)>0 and (a.leftAhead2 or 0)>0 and (a.rightAhead2 or 0)>0) then return nil end
 return min(K.formWeaveMax,side(a.leftWidth,a.rightWidth),side(a.leftAhead,a.rightAhead),side(a.leftAhead2,a.rightAhead2))
end
M.weaveBound=weaveBound
function M.reachable(s,a,p,g,desired)
 if g.offsetSign==0 or not a.splineValid or not (a.leftWidth>0 and a.rightWidth>0) then return 0 end
 local toRight=desired*g.offsetSign>0
 local bound=widthBound(s,a,p,toRight,s.state=='DRIVE' or s.state=='IDLE')
 if s.formWeave and (s.state=='DRIVE' or s.state=='IDLE') then local w=weaveBound(a,toRight); if w and w>bound then bound=min(w,p.maxSideOffset,s.zone.maxOffset) end end
 return U.clamp(desired,-bound,bound)
end
-- Place (m) que la borne laisse vers un côté de la piste (gauche ou droite réelles), dans l'échelle de ce côté ; ne
-- dépend pas du sens latéral mesuré (comme la règle de place d'avant).
function M.room(s,a,p,toRight)
 if not (a.leftWidth>0 and a.rightWidth>0) then return 0 end
 return widthBound(s,a,p,toRight)*(toRight and a.rightWidth or a.leftWidth)
end
-- Beta 1.60 (lot 5, course à Zandvoort du 11 novembre sur le lot 4 : 18 tentatives en 17 minutes, 45 départs refusés
-- « sans place ») : place (m) qu'un côté aura 2 s plus loin, là où la trajectoire traverse la piste. Sur un circuit
-- étroit et sinueux, le côté large se referme dans les 2 s (la borne du décalage le prévoit : M.reachable) pendant que
-- l'autre s'ouvre : aucun côté n'avait K.passMinRoom m et aucune tentative ne partait. Le côté qui s'ouvre accueille
-- la tentative : le décalage, fraction de la largeur du côté, grandit avec elle (la borne reste celle de M.reachable à
-- chaque image : roues en piste comme avant). Largeurs lues plus loin inconnues : 0 (rien ne change).
function M.roomSoon(s,a,p,toRight)
 if not ((a.leftAhead or 0)>0 and (a.rightAhead or 0)>0 and (a.leftAhead2 or 0)>0 and (a.rightAhead2 or 0)>0) then return 0 end
 -- Jamais un côté qui se referme entre-temps (enchaînement de virages) : la plus petite borne à 1 s et à 2 s.
 local half=a.width*0.5
 local near=sideBound(a.leftAhead,a.rightAhead,half,toRight); local far=sideBound(a.leftAhead2,a.rightAhead2,half,toRight)
 return min(p.maxSideOffset,s.zone.maxOffset,near,far)*(toRight and a.rightAhead2 or a.leftAhead2)
end
-- Départ de dépassement refusé : compté une fois par raison, par cible et par épisode (jusqu'à la prochaine tentative
-- ou une autre cible) ; résumé de la minute (src/journal.lua). Aucune chaîne construite par image.
local refuseStat={room='refRoom',short='refShort',suspended='refSusp',firstlap='refFirst',zone='refZone',flag='refFlag',start='refStart',corner='refCorner',
 budget='refBudget',side='refSide',corridor='refCorridor',closing='refClosing',advantage='refAdv',other='refOther'}
-- Beta 1.62 (relecture 162v, point 4) : retenue par la nuance des classes et changement de côté vers la place comptés
-- une fois par voiture et par cible, comme les départs refusés (ils l'étaient à chaque image).
refuseStat.nuanceHold='nuanceHold'; refuseStat.sideRoom='passSideRoom'
local function refused(e,s,index,key)
 local seen=s.refSeen; if not seen then seen={}; s.refSeen=seen end
 if seen[key]==index then return end
 seen[key]=index
 local stat=refuseStat[key]; e.stats[stat]=(e.stats[stat] or 0)+1
end
M.refused=refused
-- Affinage 1.61 (courses de Zandvoort et de Spa du 11 novembre : départs en fin de ligne droite, au freinage, perdus à
-- la sortie du virage) : en course, l'attaquant en attente derrière sa cible ne déboîte que si la ligne droite qui
-- reste (prochain point de freinage appris) laisse le temps d'arriver à hauteur au rapprochement du moment, ou s'il est
-- déjà dans son aspiration (K.pullOutCloseGap m). Aucun point connu : comme avant.
function M.pullOutTime(e,a,target,frame)
 if target.gap<=K.pullOutCloseGap then return true end
 local np=FirstLap.nextPoint(e.fl,a,frame.length)
 if not (np<math.huge) then return true end
 local need=(target.gap+a.length)/max(target.sa/3.6,K.pullOutClosingMin)
 return np/max(a.speed,1)>=need*K.passSoonShare
end
-- Place vers le côté interne side (-1 ou 1 : celui des cibles de décalage) ; largeurs ou sens inconnus : nil.
sideRoom=function(s,a,p,g,side)
 if g.offsetSign==0 or not (a.leftWidth>0 and a.rightWidth>0) then return nil end
 return M.room(s,a,p,side*g.offsetSign>0)
end
M.sideRoom=sideRoom
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
 -- Correctif 1.61 : zigzag du tour de formation, rampe plus vive (K.formWeaveRampMult).
 if s.formWeave and not s.laneActive then factor=K.formWeaveRampMult end
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
 local bin=Delta.bin(a.spline,bins)
 -- Allure habituelle apprise seulement en conduite libre : jamais sous drapeau jaune, neutralisation ou espacement.
 -- Beta 1.52 : ni hors d'un tour lancé en essais et qualifications (tour de sortie, refroidissement, tour de rentrée :
 -- s.qualiNoLearn, posé par src/quali.lua pour les IA seulement) ; l'allure dérivait vers le bas.
 if s.state=='DRIVE' and row.free and s.lapseUntil<=0 and a.splineValid and not a.pit and not a.offtrack and not s.qualiNoLearn and not s.yellow and not s.trafficApplied then
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
 if free==0 and s.prior and (s.prior[bin] or 0)>0 then free=s.prior[bin]*(s.priorRatio or 1) end -- Beta 1.61 : src/pacemap.lua
 s.freePace=free
 if free>0 and a.speed<free*p.stuckPaceRatio then s.stuck=s.stuck+dt else s.stuck=0 end
end
local function lapOrClass(e,s,a,other,rel,p,profile)
 local laps=not C.solo(profile) and p.blueFlagEnabled and Classes.laps(a,other,rel,e.frame.length) or 0
 local upper=faster(p,e.states[other.slot],s)
 return laps,upper
end
-- rest (Beta 1.52) : repos anti-zigzag en cours : seules les cessions prioritaires (drapeau bleu, classe, tour lancé)
-- sont jugées.
local function yieldTrigger(e,s,a,row,p,profile,now,dt,rest)
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
 -- Beta 1.52 : sauf l'appel de phares du joueur (le joueur est servi) ; l'appel d'une autre IA ne la remplace jamais.
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
  if source and source.long<0 and source.gap>=0 and source.gap<=p.flashRange and (not qualiCar or source.index==qualiCar.index) then back=source else aiFlash=false end
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
 -- Beta 1.60 (lot 5) : en course, une voiture lente à contourner s'écarte pour celle qui arrive comme sous drapeau bleu
 -- (côté, tenue de la cession, passage franc du suiveur) ; son niveau n'est pas abaissé davantage (plus bas).
 -- Beta 1.61 (réglage classNuance, course) : la distance seule ne lève plus le drapeau bleu : la voiture qui prend un
 -- tour doit être sur le point d'arriver (K.blueCatchTime s au rythme du rapprochement) ou déjà collée.
 if p.classNuance and blue and profile=='C' and not Nuance.catch(back.gap,back.sa) then blue=false; s.blueVetoAt=now end
 -- Beta 1.62 (fusion, règles par session) : hors course aussi (essais, qualifications, journée circuit) : une voiture
 -- anormalement lente (dégâts) quitte la trajectoire ; en journée circuit « line » ne s'applique pas à elle (cession bleue).
 local slowSelf=not blue and s.abnormal==true and back.gap<=p.blueFlagRange and back.sa>=K.lapSpeed
 if slowSelf then blue=true end
 local classYield=upper and back.sa>=p.classYieldMargin and (back.sa>=K.classFightSpeed or row.front==0 or row.neighbors[row.front].gap>K.followRange)
 -- Beta 1.61 (classNuance) : classe lente : la voiture rapide est déjà décalée (K.classSideLat m), elle a choisi son
 -- côté : la ligne est tenue. Une ligne au plus toutes les K.nuanceLogGap s.
 if p.classNuance and classYield and not blue and Nuance.classHold(back.lat) then
  classYield=false
  if now>=(s.classHoldLogAt or -math.huge) or (s.classHoldLogAt or 0)-now>K.nuanceLogGap then
   s.classHoldLogAt=now+K.nuanceLogGap; e.stats.classHold=(e.stats.classHold or 0)+1
   U.log(e.log,now,'INFO',string.format('classe: %s tient sa ligne, %s deja decale',a.name,other.name),a.slot)
  end
 end
 -- Beta 1.52 : pendant le repos anti-zigzag, rien d'autre n'est jugé (attentes de la cession ordinaire gelées, comme
 -- avant).
 if rest and not blue and not classYield and not quali then s.bluePending=false; return nil end
 -- Beta 1.29 : appel du joueur jugé tant que la demande vit (plus rapide, ou retenu juste derrière) : appelé de loin un
 -- peu trop lentement, il est compris dès que le joueur se rapproche.
 local currentAdvantage=Flash.advantage(p,back.gap,back.sa)
 local acceptedFlash=activeFlash and back.index==e.frame.player and currentAdvantage
 local permittedFlash=acceptedFlash and not rest and (profile~='C' or p.flashMode=='always' or blue or classYield)
 -- Appel d'une IA : en course, admis pour un tour ou une classe supérieure, même à vitesse égale (voiture bloquée).
 -- Dans une file (Beta 1.21) : collée à une voiture, une IA qui s'écarte et ralentit pour une voiture à peine plus rapide
 -- ne laisse passer personne et ralentit toute la file (train de voitures identiques en journée circuit). Cession
 -- ordinaire et appel de phares d'une IA comme la cession entre classes : piste libre devant, ou suiveur nettement plus
 -- rapide. L'appel de phares du joueur reste honoré.
 local clear=row.front==0 or row.neighbors[row.front].gap>K.followRange or back.sa>=K.classFightSpeed
 -- Beta 1.52 : IA en tour lancé : jamais de cession sur l'appel d'une voiture qui ne l'est pas (garde de la 1.51 que
 -- l'appel de phares contournait : la cession invitait la voiture pas lancée à l'attaquer).
 local aiAccepted=aiFlash and not rest and back.index==ai.source and (profile~='C' and clear or laps>0 or upper)
  and not qualiGuard(e,back.index,a.slot)
 if profile=='C' and not blue and not classYield and not permittedFlash and not aiAccepted then s.confirm=0; s.pendingAt=0; s.pendingTarget=0; s.bluePending=false; return nil end
 -- Beta 1.51 : IA en tour lancé : pas de cession ordinaire à une voiture qui ne l'est pas (appel de phares compris à part).
 local ordinary=p.yieldEnabled and profile~='C' and clear and not (e.quali and e.quali.active and e.quali.push[a.slot] and not e.quali.push[back.index]) and not rest
 if not ordinary and not blue and not classYield and not permittedFlash and not aiAccepted and not quali then return nil end
 if s.ignoreTarget==back.index and now<s.ignoreUntil then return nil end
 if s.yieldIgnore==back.index and now<s.yieldIgnoreUntil and not blue and not classYield and not quali then return nil end
 local margin=p.yieldBehindMargin*U.lerp(K.courtesyMin,K.courtesyMax,s.persona.courtesy)*U.lerp(K.gapMarginMin,1,back.gap/K.yieldMarginRange)
 local horizon=p.yieldHorizon
 if acceptedFlash then margin=margin*K.flashMargin; horizon=horizon*K.flashHorizon end
 local detection=max(p.yieldDetectBehind,min(K.detectMax,max(0,back.sa/3.6)*horizon))*(1+(p.weatherAdaptation and K.wetDetect*(s.wxWet or e.frame.wet) or 0))
 if acceptedFlash then detection=max(detection,p.flashRange) end
 local c1=ordinary and back.gap<=detection and back.sa>=margin and back.ttc<=horizon
 local c2=ordinary and back.gap<=K.nearYield and back.sa>=K.nearYieldMargin*margin
 -- Beta 1.60 (réglage rearAwareness, hors course) : voiture beaucoup plus rapide qui arrive (K.rearFastSa km/h, contact à
 -- K.rearYieldTtc s) : cession ordinaire dès K.rearFastRange m, confirmée plus vite ; trop tard (à hauteur dans
 -- l'horizon sans cession commencée) : aucune cession, l'IA garde sa ligne et la voiture rapide la contourne.
 local early=false
 if p.rearAwareness and profile~='C' and ordinary and back.sa>=K.rearFastSa then
  if back.gap/(back.sa/3.6)<=Rear.horizon(s,p) then
   if not (blue or classYield or quali or permittedFlash or aiAccepted) then s.confirm=0; s.pendingAt=0; s.pendingTarget=0; return nil end
  elseif back.ttc<=K.rearYieldTtc and back.gap<=K.rearFastRange then early=true; c1=true end
 end
 if p.pressureEnabled and back.gap<=p.pressureGap and abs(back.sa)<=K.pressureSa then
  if s.pressureTarget~=back.index then s.pressure=0; s.pressureTarget=back.index end
  s.pressure=s.pressure+dt; s.pressureLost=0
 elseif back.gap>p.pressureGap*K.pressureResetRange then
  s.pressureLost=s.pressureLost+dt; if s.pressureLost>K.pressureResetTime then s.pressure=0 end
 end
 -- Beta 1.41 : pression (suiveur collé à la même allure) refusée à une IA dont l'allure libre ici n'est pas plus rapide
 -- (connue) : avant, l'IA cédait à une IA aussi rapide qu'elle, qui ne passait jamais, puis recommençait. Allure inconnue
 -- et joueur : cession comme avant (PDR T05).
 local c3=ordinary and p.pressureEnabled and s.pressure>=p.pressureTime and (back.index==e.frame.player or not yieldRefused(e,e.states[back.index],s,a,p,profile))
 local c4=permittedFlash
 local c5=aiAccepted
 -- Beta 1.55 (Nordschleife, 9 novembre : 36 cessions en 10 min, 4 suivies d'un passage) : cession ordinaire sur simple
 -- rapprochement seulement à un suiveur vraiment plus rapide ici (allure libre apprise ; inconnue : permise), comme la
 -- pression ; jamais le joueur, jamais un drapeau bleu, une classe, un tour lancé ni un appel de phares. Refus noté une
 -- fois par suiveur et par épisode.
 if (c1 or c2) and K.yieldNeedAdvantage and not (c4 or c5 or blue or classYield or quali) and back.index~=e.frame.player
  and yieldRefused(e,e.states[back.index],s,a,p,profile) then
  c1=false; c2=false
  if s.noAdvFor~=back.index or now>s.noAdvAt+K.yieldNoAdvForget then
   s.noAdvFor=back.index; e.stats.yieldNoAdv=(e.stats.yieldNoAdv or 0)+1
   U.log(e.log,now,'INFO',string.format('cession refusee: %s ne cede pas a %s (pas plus rapide ici)',a.name,other.name),a.slot)
   local tag=lapTag(e,a.slot)
   if tag~='' then U.log(e.log,now,'INFO',string.format('tours de la cession: %s (%s), suiveur %s (%s)',a.name,tag,other.name,lapTag(e,back.index)),a.slot) end
  end
  s.noAdvAt=now
 end
 -- Beta 1.59 (deuxième journée circuit en 1.59 : 19 dépassements quittés « cede a son suiveur », dont sur une cible qui
 -- lui cédait) : hors course, une IA en plein dépassement ne commence pas de cession ordinaire (rapprochement, pression,
 -- appel de phares d'une IA) : elle finit son dépassement, le suiveur passe derrière elle ; appel de phares du joueur
 -- (PDR F09), drapeau bleu, classe et tour lancé gardent leurs règles.
 if profile~='C' and passStates[s.state] and s.state~='OVT_OUT' then c1=false; c2=false; c3=false; c5=false end
 -- Beta 1.62 (essais, relais long, décision 2 du pilote) : aucune des deux voitures lancée : cession ordinaire seulement
 -- à un suiveur nettement plus rapide au tour (rythme relatif à la classe meilleur de K.practiceLapMargin, connu des
 -- deux) ; rythmes inconnus : règles d'avant. Joueur, appels de phares, drapeau bleu et classe inchangés.
 if profile=='P' and (c1 or c2 or c3) and not (c4 or c5 or blue or classYield or quali) and back.index~=e.frame.player
  and not (e.quali and e.quali.active and (e.quali.push[back.index] or e.quali.push[a.slot])) then
  local fs=e.states[back.index]
  if fs.paceRatioCount>=K.paceRatioMin and s.paceRatioCount>=K.paceRatioMin and fs.paceRatio<s.paceRatio*(1+K.practiceLapMargin) then c1=false; c2=false; c3=false end
 end
 local trigger=c1 or c2 or c3 or c4 or c5 or blue or classYield or quali
 local needed=(blue or quali) and K.lapConfirm or classYield and p.confirmTime*K.classConfirm or (c4 or c5) and K.flashConfirm or p.confirmTime
 if activeFlash and not c4 then needed=needed*K.flashMargin end
 if early and c1 and not (blue or quali or classYield or c4 or c5) then needed=needed*K.rearFastConfirm end
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
 -- Beta 1.62 (qualifications : « sacrifier son virage ») : voiture lancée à moins de K.qualiSacrificeTime s derrière :
 -- la cession commence dès le seuil ordinaire (la règle du freinage reste : aucune cession au freinage).
 if quali and profile=='Q' and back.gap<=max(other.speed,1)*K.qualiSacrificeTime then corner=min(corner,p.cornerMin) end
 if a.corner<corner then s.bluePending=blue; if blue then s.blueReason='virage'; s.blueVetoAt=now end; return nil end
 -- Beta 1.61 (classNuance) : jamais de cession à K.blueBrakeTime s d'un point de freinage connu (zone du circuit ou
 -- point appris) : elle attend la sortie, au niveau d'attente du virage ; une ligne par épisode. Zone d'attaque à
 -- moins de K.blueZoneTime s devant, voiture pas encore collée : la cession l'attend (Zones.nextAttack, tranche A).
 if p.classNuance and not quali and (blue and not slowSelf and profile=='C' or classYield) then
  local soon,d=Nuance.brakeSoon(e,a,e.frame.length,K.blueBrakeTime)
  if soon then
   s.bluePending=blue; if blue then s.blueReason='freinage proche'; s.blueVetoAt=now end
   if s.brakeWaitFor~=back.index or now>(s.brakeWaitAt or -math.huge)+K.nuanceLogGap then
    s.brakeWaitFor=back.index; s.brakeWaitAt=now; e.stats.blueBrakeWait=(e.stats.blueBrakeWait or 0)+1
    U.log(e.log,now,'INFO',string.format('drapeau bleu: %s attend la sortie pour %s (freinage proche, %.0f m)',a.name,other.name,d),a.slot)
   end
   return nil
  end
  local zone=blue and back.gap>K.blueCloseGap and not s.zone.passMargin and Zones.nextAttack and a.splineValid and Zones.nextAttack(e.zones,a.spline) or nil
  if zone and ((zone-a.spline)%1)*e.frame.length<=max(a.speed,K.firstLapSpeedMin)*K.blueZoneTime then s.bluePending=true; s.blueReason='zone d attaque proche'; s.blueVetoAt=now; return nil end
 end
 local side,swapped=yieldSide(p,back,profile~='C' and not blue,row,e.runtimeG,s,a) -- Beta 1.62 : voiture lancée : côté réglé (yieldSide)
 s.yieldSwapped=swapped==true
 local line=p.yieldSide=='line' and not (blue or classYield)
 if not sideFree(row,side) and not line then s.blockedYield=s.blockedYield+dt else s.blockedYield=0 end
 -- Beta 1.52 : cession à une classe plus rapide comme le drapeau bleu et le tour lancé : jamais refusée par le plafond
 -- (s.yieldBlue la couvre, le plafond ne la retient ni ne la compte).
 local blocked=s.zone.noYield and 'zone sans cession' or a.kmh<K.speedMinYield and 'trop lent' or not line and not sideFree(row,side) and 'cote occupe' or not blue and not classYield and not quali and not directionBudget(s,now,p) and 'trop de changements de trajectoire' or nil
 if blocked then if blue then s.blueReason=blocked; s.blueVetoAt=now end; return nil end
 s.target=back.index; s.targetSide=side; s.gap=back.gap; s.sa=back.sa; s.ttc=back.ttc
 s.yieldDetection=max(detection,blue and blueRange or 0,quali and other.speed*max(K.qualiYieldTime,K.qualiYieldLead)*K.qualiYieldRange or 0); s.yieldMargin=margin
 for j=1,K.maxCars do s.followers[j]=false; s.followerSlow[j]=0; s.followerStall[j]=0 end
 s.followers[back.index]=true; s.multiLeader=false; s.yieldPassed=false
 s.confirm=0; s.pendingAt=0; s.pendingTarget=0; s.bluePending=false; s.holdUntil=now+p.yieldHoldMin; s.brakeWaitFor=0
 s.linger=0; s.postPass=false; s.yieldStart=now; s.yieldBlue=blue or classYield or quali; s.urgent=c4 and flash.urgent
 s.yieldOrdinary=not (blue or classYield or c4 or c5 or quali); s.yieldStalled=false
 -- Beta 1.62 (journée circuit, décision 1) : « line » : la voiture qui cède garde sa ligne et lève le pied (cession
 -- ordinaire, appels de phares et, depuis la 1.62, tour lancé ; drapeau bleu et classe gardent leur côté).
 s.yieldLine=line
 -- Beta 1.55 : cession sur l'appel de phares d'une IA : son auteur, pour compter les cessions sans passage.
 s.yieldFlashBy=c5 and back.index or 0
 -- Beta 1.51 : cession à une voiture lancée (journal et compteurs à part, comme un drapeau bleu pour le reste).
 s.yieldQuali=quali and not blue and not classYield and not c4 and not c5
 if s.yieldQuali then
  e.stats.qualiYield=(e.stats.qualiYield or 0)+1
  -- Beta 1.52 : raison relevée par src/quali.lua (sortie, refroidissement, rentrée, endommagée, trop lente).
  if now>=(s.qualiLogAt or -math.huge) then s.qualiLogAt=now+K.qualiLogGap; U.log(e.log,now,'INFO',string.format('cede a %s en tour lance (%s, %.0f m, %+.0f km/h)',other.name,e.quali.cars[a.slot].why~='' and e.quali.cars[a.slot].why or 'pas lance',back.gap,back.sa),a.slot) end
 end
 s.yieldClass=(classYield or c5 and upper) and not blue
 if slowSelf then
  e.stats.slowYield=(e.stats.slowYield or 0)+1
  U.log(e.log,now,'INFO',string.format('IA lente: %s s ecarte pour %s (%.0f m, %+.0f km/h)',a.name,other.name,back.gap,back.sa),a.slot)
 end
 if early and s.yieldOrdinary then
  e.stats.rearYield=(e.stats.rearYield or 0)+1
  U.log(e.log,now,'INFO',string.format('cession anticipee: %s -> %s (%.0f m, %+.0f km/h)',a.name,other.name,back.gap,back.sa),a.slot)
 end
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
-- Beta 1.60 (lot 5) : tours d'avance de a sur b sans voisin de perception (cible d'un dépassement en cours).
local function leadLaps(a,b)
 if not a or not b or not a.lapValid or not b.lapValid or not a.splineValid or not b.splineValid or a.lap<1 then return 0 end
 return max(0,math.floor((a.lap+a.spline)-(b.lap+b.spline)+K.lapTolerance))
end
-- Adversaire direct : même tour (ni attardée, ni voiture qui prend un tour), même classe, ni voiture de sécurité ni
-- voiture aux stands.
local function rival(e,s,a,n,p,frame)
 local other=frame.cars[n.index]; local os=e.states[n.index]
 if other.safetyCar or other.pit then return false end
 if Classes.laps(a,other,n,frame.length)>0 or lapsAhead(a,other,n,frame.length)>0 then return false end
 return not faster(p,s,os) and not faster(p,os,s)
end
-- Beta 1.61 (classNuance) : trêve entre deux voitures du même tour rattrapées par la voiture à qui i cède : la voiture
-- juste devant (à K.nuanceBattleTime s au plus, adversaire direct) et i ne s'attaquent plus tant que la voiture qui
-- arrive ne les a pas passées toutes les deux (src/nuance.lua) ; bornée par la durée maximale de cession.
function M.nuanceTruce(e,s,a,row,p,frame,now,i)
 local n=row.front>0 and row.neighbors[row.front] or nil
 if not n or n.gap<0 or n.index==frame.player or n.gap>K.nuanceBattleTime*max(a.speed,1) or not rival(e,s,a,n,p,frame) then return end
 if Nuance.truce(e.nuance,i,n.index,s.target,now,p.yieldMaxHold) then
  e.stats.blueTruce=(e.stats.blueTruce or 0)+1
  U.log(e.log,now,'INFO',string.format('drapeau bleu: treve %s / %s, %s passe d abord',a.name,frame.cars[n.index].name,frame.cars[s.target].name),i)
 end
end
-- Beta 1.61 (classNuance) : dépassement retenu par les règles des retardataires et des classes. Renvoie la raison :
-- trêve en cours avec la cible ; voiture qui vient de prendre un tour à l'IA (K.relapHold s, sauf K.relapSa km/h de
-- plus) ; dédoublement hors ligne droite ; classe rapide à K.classNoDiveTime s d'un point de freinage derrière une
-- classe lente, sans recouvrement (elle attend la sortie, une ligne par cible toutes les K.nuanceLogGap s).
function M.nuanceGate(e,s,a,front,p,profile,frame,now,i)
 if Nuance.truced(e.nuance,i,front.index,now) then return 'treve' end
 local other=frame.cars[front.index]
 if profile=='C' and not C.solo(profile) then
  if Nuance.relapHeld(s,front.index,front.sa,now) then return 'tour tout juste pris' end
  if a.corner<K.lapCorner and Classes.laps(a,other,front,frame.length)>0 then return 'dedoublement hors ligne droite' end
 end
 if faster(p,s,e.states[front.index]) and front.gap>0 and Nuance.brakeSoon(e,a,frame.length,K.classNoDiveTime) then
  if s.classWaitFor~=front.index or now>(s.classWaitAt or -math.huge)+K.nuanceLogGap then
   s.classWaitFor=front.index; s.classWaitAt=now; e.stats.classWait=(e.stats.classWait or 0)+1
   U.log(e.log,now,'INFO',string.format('classe: %s attend la sortie pour passer %s (classe lente au freinage)',a.name,other.name),i)
  end
  return 'classe lente au freinage'
 end
 return nil
end
-- Air sale (0 à 1) : dans le sillage d'une voiture à moins de dirtyAirGap m, en virage, à vive allure ; jamais sous
-- drapeau, au départ, à côté d'une voiture, ni en évitement, reprise au calme ou attente.
local function dirtyAir(e,s,a,front,p,startPhase)
 if not p.dirtyAirEnabled or startPhase or s.yellow or e.incidents.neutral or e.incidents.red or s.alongside or not front or front.long<=0 or front.gap<0
  or front.gap>p.dirtyAirGap or abs(front.lat)>K.dirtyAirLat or a.kmh<K.dirtyAirSpeed or a.corner>=p.cornerMin
  or s.state=='AVOID' or s.state=='CALM' or s.state=='IDLE' then return 0 end
 return U.clamp(1-(front.gap-K.dirtyAirFull)/max(1,p.dirtyAirGap-K.dirtyAirFull),0,1)
end
-- Beta 1.59 (course de 10 tours du 10 novembre) : derniers tours concernés au plus K.finalLapsShare de la course
-- (au moins 1) quand le nombre de tours est connu ; course chronométrée : finalLaps tel quel.
local function finalLapsFor(p,frame,race)
 local total=frame.sessionLaps>0 and not frame.timedRace and frame.sessionLaps or race and race.known and (frame.leaderLaps or 0)+race.lapsLeft or 0
 if total>0 then return min(p.finalLaps,max(1,math.floor(K.finalLapsShare*total+0.5))) end
 return p.finalLaps
end
M.finalLapsFor=finalLapsFor
-- Urgence des derniers tours (0 à 1) : course commencée, finalLaps derniers tours du leader, drapeau vert, un adversaire
-- direct à moins de K.finalRange m devant ou derrière ; montée d'un cran par tour jusqu'au dernier.
local function urgency(e,s,a,row,p,profile,frame,startPhase)
 if profile~='C' or not p.finalLapsEnabled or not frame.started or a.finished or startPhase or s.yellow
  or e.incidents.neutral or e.incidents.red or s.bluePending or s.yieldBlue then return 0 end
 -- Relecture 1.42 : tours restants de la voiture elle-même (le leader arrivé, les autres finissent leur dernier tour ;
 -- course chronométrée : tour qui suit la fin du temps compris), jamais face au joueur.
 local left=Strategy.lapsLeft(e,frame,a)
 local laps=finalLapsFor(p,frame,e.race)
 if left<1 or left>laps then return 0 end
 for j=1,row.count do
  local n=row.neighbors[j]
  if n.gap>=0 and n.gap<=K.finalRange and n.index~=frame.player and rival(e,s,a,n,p,frame) then return (laps-left+1)/laps end
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
 local b=Delta.bin(a.spline,m.bins); local binLength=frame.length/m.bins
 local straight=m.len[b]*binLength
 if straight<p.towBreakStraight or m.run[b]*binLength<K.towMinAheadTime*a.speed then return false end
 s.towDone=true
 if U.unit(g.seed,i,(a.lap+back.index)*3+K.towSalt)>=K.towChance+K.towAssert*s.persona.assertiveness then return false end
 -- Relecture 1.42 : jamais vers le côté de dépassement imposé par le réglage (le suiveur y déboîte) ; sinon s'éloigner du
 -- suiveur (lat>0 : suiveur du côté gauche, repère interne où -1 est la gauche). Suiveur déjà nettement du côté visé, ou
 -- côté occupé : pas de manœuvre (jamais vers le suiveur).
 local away=back.lat>0 and 1 or -1
 local forced=(p.overtakeSide=='left' or p.overtakeSide=='right') and fixedSide(p.overtakeSide,1,g) or p.overtakeSide=='opposite' and (p.yieldSide=='left' or p.yieldSide=='right') and -fixedSide(p.yieldSide,1,g) or 0 -- Beta 1.62 (relecture 162v, point 6) : même garde que passSide
 local side=forced~=0 and -forced or away
 if side~=away and abs(back.lat)>K.towLatSide or not sideFree(row,side) then return false end
 s.targetSide=side; s.towing=true; s.defendUntil=now+K.towHoldMax; s.towPair=back.index; s.towPairWait=K.towPairCooldown; s.towWait=K.towCooldown
 -- Un seul mouvement par ligne droite : la défense ne suit pas la cassure (même attaquant, même tour).
 s.defendUsed=true; s.defendAttacker=back.index; s.defendLap=a.lap
 transition(e,s,'DEFEND','tow',now)
 U.log(e.log,now,'INFO',string.format('aspiration: %s casse l aspiration de %s (%.0f m, ligne droite %.0f m)',a.name,frame.cars[back.index].name,back.gap,straight),i)
 return true
end
-- Beta 1.60 (lot 4, coût par image) : ces deux fonctions étaient créées dans M.step à chaque passage. Une fonction
-- imbriquée qui capture des variables de M.step oblige le compilateur JIT à abandonner au retour de M.step (opération
-- UCLO non compilée) : la boucle des voitures restait interprétée. Mêmes calculs, variables passées en paramètres.
local function straightHoldCount(e,s,now,push)
 if now>=(s.straightHoldAt or -math.huge) or s.straightHoldAt-now>1 then
  s.straightHoldAt=now+1; e.startHold=(e.startHold or 0)+1; e.stats.flHold=(e.stats.flHold or 0)+1
  if push then e.stats.flPushed=(e.stats.flPushed or 0)+1 end
 end
end
local function capText(v) return v and v<K.unlimitedSpeed and string.format('%.0f',v) or 'aucune' end
-- Affinage 1.62 (sessions du 12 novembre : prudence de l'attaquant médiane 1,64 sur 2 741 lignes de suivi, cible
-- écartée de 3 à 5 m) : attaquant décalé de sa cible, cherchée parmi tous les voisins (à sa hauteur, elle n'est plus
-- « devant » dans la perception) ; jamais avec une autre voiture proche devant lui dans sa file.
local function passFreeOf(s,row,front)
 if s.state~='OVT_IN' and s.state~='OVT_HOLD' then return false end
 local r=P.find(row,s.target)
 if not r or abs(r.lat)<K.passFreeLat then return false end
 return not (front and front.index~=s.target and front.long>0 and front.gap<K.followRange)
end
-- Affinage 1.62 (départ de Zandvoort du 12 novembre : 20 contacts en 30 s, les deux premiers chocs par l'arrière sur
-- deux envols manqués, aucun lever de pied derrière eux) : voiture j encore dans son envol manqué (src/antics.lua), ou
-- depuis moins de K.anticBogGrace s.
local function bogging(e,j,now)
 local t=e.antics
 if not t or not t.poor or not t.poor[j] or (t.kind~='ac' and t.kind~='grid') then return false end
 local since=now-t.at
 return since>=0 and since<(t.react[j] or 0)+(t.bog[j] or 0)+K.anticBogGrace
end
M.passFreeTest=passFreeOf; M.boggingTest=bogging -- affinage 1.62 : tests
-- Affinage 1.62 (demande de la communauté, décision du pilote du 12 novembre) : recherche de l'aspiration en ligne droite.
-- Derrière une voiture (IA ou joueur) écartée d'au moins K.seekLat m de sa file, à moins de K.seekTime s (au plus
-- K.seekRange m), en vraie ligne droite (K.slipCorner, plus de K.slipSpeed km/h) avec encore K.seekAheadTime s de ligne
-- droite devant (point de freinage appris ou carte des lignes droites ; rien de connu : aucune recherche), l'IA se recale
-- derrière elle (rampe ordinaire, bornes de largeur, Monaco compris). Jamais vers un côté occupé ou un couloir pris, sous
-- drapeau, en neutralisation, au départ ou au premier tour attentif, pendant une cession ou une inattention, au freinage,
-- à côté d'une voiture, en zone interdite ou difficile, derrière une voiture qui cède, en difficulté ou qu'on rattrape
-- trop vite (plus de K.seekSaMax km/h, contact à moins de K.seekTTC s). Course, essais et qualifications (ni journée
-- circuit, ni hotlap) ; en qualifications, seulement en tour lancé et jamais avec une voiture lancée juste derrière.
-- Retour à la ligne quand il reste moins de K.seekReturnTime s de ligne droite. Un épisode par voiture de devant (journal
-- une fois, compteur de la minute). Renvoie le décalage voulu (repère de desired), ou nil.
local function slipSeek(e,s,a,row,p,profile,frame,now,rel,braking,ownBrake,early,i,g,m)
 local ok=rel~=nil and p.slipstreamEnabled and (profile=='C' or profile=='P' or profile=='Q') and g.offsetSign~=0 and frame.length>0 and a.splineValid
  and a.leftWidth>0 and a.rightWidth>0 and not early and not braking and ownBrake<K.passBrakeMax and a.brake<=K.ruleBrake
  and (a.cornerYaw or a.corner)>=K.slipCorner and a.corner>=K.slipCorner and a.kmh>K.slipSpeed
  and not s.yellow and not e.incidents.neutral and not e.incidents.red and not s.alongside and not s.bluePending and not s.yieldBlue
  and s.lapseUntil<=now and not s.returning and not s.zone.noOvertake and not s.hotspot
  and rel.long>0 and not rel.alongside and rel.gap<=min(K.seekRange,a.speed*K.seekTime) and abs(rel.lat)<=K.seekLatMax
  and rel.sa<=K.seekSaMax and rel.ttc>=K.seekTTC
 local seeking=(s.seekFront or 0)~=0
 if ok and seeking and s.seekFront~=rel.index then ok=false end
 if ok and not seeking and abs(rel.lat)<K.seekLat then ok=false end
 if ok then
  local o=e.states[rel.index]; local ic=e.incidents.cars[rel.index]
  if yieldStates[o.state] or o.abnormal==true or ic and (ic.incident or ic.trouble) then ok=false end
 end
 if ok and profile=='Q' then
  local q=e.quali
  ok=q~=nil and q.active and q.push[i] and not (q.cars[i] and q.cars[i].cool)
  if ok then for j=1,row.count do local r=row.neighbors[j]; if r.long<0 and r.gap<=a.speed*K.seekTime and q.push[r.index] then ok=false; break end end end
 end
 if ok then
  local ahead=FirstLap.nextPoint(e.fl,a,frame.length)
  -- Aucun point de freinage connu : carte des lignes droites, là où elle est apprise (endroit vu assez souvent).
  if not (ahead<math.huge) and m.bins>0 and m.at>-math.huge then local b=Delta.bin(a.spline,m.bins); if m.seen[b]>=K.towMapSeen then ahead=m.run[b]*frame.length/m.bins end end
  if not (ahead<math.huge) or ahead<a.speed*(seeking and K.seekReturnTime or K.seekAheadTime) then ok=false end
 end
 if ok and abs(rel.lat)>=K.seekSettleLat then
  local side=rel.lat>0 and -1 or 1
  if not sideFree(row,side) or not P.corridor(frame.cars,frame.count,i,side,K.corridorMin,rel.index,g.occLatMax) then ok=false end
 end
 if not ok then s.seekFront=0; s.seekAt=nil; return nil end
 if not seeking then
  local cur=s.offset
  s.seekFront=rel.index; s.seekM=cur*(cur*g.offsetSign>0 and a.rightWidth or a.leftWidth)-rel.lat; s.seekLatch=now
  -- Une ligne et un compte par paire au plus toutes les K.seekLogGap s : un épisode coupé une image (courbe, frein) puis
  -- repris n'est pas un nouvel épisode pour le journal (course du 12 novembre : 479 lignes en 6 tours).
  if not (s.seekLogFront==rel.index and s.seekLogAt and now>=s.seekLogAt and now-s.seekLogAt<K.seekLogGap) then
   s.seekLogFront=rel.index; s.seekLogAt=now
   e.stats.slipSeek=(e.stats.slipSeek or 0)+1
   U.log(e.log,now,'INFO',string.format('aspiration recherchee: %s derriere %s (%.0f m, ecart lateral %.1f m)',a.name,frame.cars[rel.index].name,rel.gap,abs(rel.lat)),i)
  end
 elseif abs(rel.lat)>=K.seekSettleLat and now-s.seekLatch>=K.seekSettle then
  s.seekM=s.seekM-rel.lat; s.seekLatch=now
 end
 local d=U.clamp(s.seekM/(s.seekM*g.offsetSign>0 and a.rightWidth or a.leftWidth),-p.maxSideOffset,p.maxSideOffset)
 s.seekAt=d
 return d
end
-- Attaquant en attente qui a cherché l'aspiration de sa cible : déboîtement retenu tant que la ligne droite laisse plus
-- de K.seekPullMargin s au-delà du temps qu'il faut pour arriver à hauteur (M.pullOutTime), sauf déjà dans le sillage.
local function seekLate(e,s,a,target,frame)
 if (s.seekFront or 0)~=target.index or target.gap<=K.pullOutCloseGap then return true end
 local np=FirstLap.nextPoint(e.fl,a,frame.length)
 if not (np<math.huge) then return true end
 local need=(target.gap+a.length)/max(target.sa/3.6,K.pullOutClosingMin)
 return np/max(a.speed,1)<=need*K.passSoonShare+K.seekPullMargin
end
M.slipSeekTest=slipSeek; M.seekLateTest=seekLate
-- Beta 1.62 : fonctions rarement appelées par M.step, regroupées pour rester loin de la limite de 60 upvalues de LuaJIT.
local H={capText=capText,limitText=limitText,aeroMap=aeroMap,aeroRuns=aeroRuns,finalLapsFor=finalLapsFor,urgency=urgency,towStart=towStart,playerSlow=playerSlow,straightHoldCount=straightHoldCount,laneHold=laneHold,passFinished=passFinished,passEnd=passEnd,lapsAhead=lapsAhead,yieldRefused=yieldRefused,firstLapHeld=firstLapHeld,inviteGeometry=inviteGeometry,passFreeOf=passFreeOf,bogging=bogging,slipSeek=slipSeek,seekLate=seekLate}
function M.step(e,i,dt,now)
 local frame=e.frame; local a=frame.cars[i]; local s=e.states[i]; local cmd=e.commands[i]
 local p,g,profile=e.run,e.runtimeG,e.profile; local row=e.perception.rows[i]
 cmd.active=false; a.wet=s.wxWet or frame.wet -- Beta 1.61 : s.wxWet (src/wx.lua), champ absent : humidité de la piste
 if a.player then return end -- État du joueur tenu par le moteur pour sa carte d'allure.
 if not a.valid or not a.control or a.pit or a.offtrack or a.finished or a.safetyCar or s.excluded or s.disqualified or now<s.errorUntil then
  if a.pit then s.pitBefore=true end
  cmd.yellowLimit=K.unlimitedSpeed; s.yellow=false; s.bluePending=false
  local gone=e.incidents.cars[i]; if gone then gone.trouble=false end; s.troubleFor=0
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
 a.corner=M.cornerness(a.yawRate,a.speed,p.cornerYawRef)
 -- Relecture 1.62 (S5) : mesure d'avant (rotation seule) gardée pour l'étalonnage, l'apprentissage des points de
 -- freinage, l'aspiration et le DRS ; a.corner (avec l'accélération latérale) pour les règles de ligne droite.
 a.cornerYaw=U.clamp(1-abs(a.yawRate or 0)/p.cornerYawRef,0,1)
 -- Beta 1.42 AERO : attentes de l'aspiration cassée, carte des lignes droites (seulement quand elle sert).
 s.towWait=max(0,s.towWait-dt); s.towPairWait=max(0,s.towPairWait-dt); s.dirtyLogWait=max(0,s.dirtyLogWait-dt)
 local m=H.aeroMap(e,frame)
 -- Affinage 1.62 : carte apprise aussi pour la recherche de l'aspiration (course, essais, qualifications).
 if (p.towBreakEnabled or p.slipstreamEnabled and (profile=='C' or profile=='P' or profile=='Q')) and m.bins>0 then
  if a.splineValid and a.kmh>=K.towMapSpeed then
   -- Relecture 1.42 : une zone de freinage n'est pas de la ligne droite (retour à la ligne avant le point de freinage).
   local b=Delta.bin(a.spline,m.bins); m.st[b]=m.st[b]+((a.corner>=K.towCorner and a.brake<=K.ruleBrake and 1 or 0)-m.st[b])*K.towMapAlpha
   if m.seen[b]<K.towMapSeen then m.seen[b]=m.seen[b]+1 end
  end
  H.aeroRuns(m,now)
 end
 if s.returning and abs(s.offset-M.reachable(s,a,p,g,s.base))<K.centerEpsilon then s.returning=false end
 Zones.at(e.zones,a.spline,s.zone)
 -- Beta 1.59 : point difficile appris (src/incidents.lua) : prudence accrue, aucun dépassement commencé.
 s.hotspot=Incidents.nearHotspot(e.incidents,a.spline,frame.length,now)
 if s.zone.caution then s.hotspot=true end -- Beta 1.61 : point difficile gardé par circuit (src/zones.lua), champ absent : neutre
 if a.pitDistance and a.pitDistance<K.pitZone then s.zone.maxOffset=min(s.zone.maxOffset,K.pitOffsetMax) end
 if now>=s.nextPerception then P.refresh(e.perception,frame.cars,frame.count,i,frame.length,e.frames); s.nextPerception=now+K.perceptionPeriod; Rear.scan(e,i,row,p,g,now) end
 P.occupancy(frame.cars,frame.count,i,g,row)
 -- Beta 1.60 (réglage rearAwareness) : côté où une voiture plus rapide sera à hauteur dans l'horizon (src/rear.lua) :
 -- compté comme occupé, donc aucun mouvement vers lui (cession, retour à la ligne, défense, dernière barrière).
 local rearLeft,rearRight=false,false
 if p.rearAwareness then
  rearLeft=not row.left and Rear.side(s,-1,now); rearRight=not row.right and Rear.side(s,1,now)
  if rearLeft then row.left=true end
  if rearRight then row.right=true end
 end
 -- Beta 1.60 (réglage passAid) : attaquant engagé à sa hauteur ou presque : l'IA tient sa ligne, aucun mouvement vers
 -- le côté de l'attaquant (s'écarter reste permis) ; joueur attaquant engagé : même règle (jugée ici, l'app n'écrit
 -- rien sur sa voiture).
 local heldBy=0
 if p.passAid then
  local pr=P.find(row,frame.player); local ps=e.states[frame.player]
  if ps then
   local pc=frame.cars[frame.player]
   local engaged=pr~=nil and a.corner>=K.passCornerC and pr.same and abs(pr.lat)>=K.commitLat and abs(pr.lat)<=g.occLatMax and (pr.alongside and pr.long<=0 or pr.long<0 and pr.gap<=K.commitGap and pr.sa>0)
   -- Relecture : joueur engagé sur deux IA à la fois : chaque IA tient sa ligne, avec sa propre ligne de journal et
   -- son propre compte (s.aidPlayer) ; l'engagement du joueur (une seule cible) n'est pas repris à une autre IA
   -- encore engagée (vue à cette image ou à la précédente : ps.commitSeen), sinon les deux se le reprenaient à
   -- chaque image, avec une ligne et un compte à chaque fois.
   if engaged then
    local other=ps.committed or 0
    if other==i or other==0 or now-(ps.commitSeen or -math.huge)>K.perceptionPeriod*2 then
     Priority.commit(e,frame.player,i,pr.lat>0 and -1 or 1,now); ps.commitSeen=now
    end
    Priority.hold(e,i,frame.player,now+K.holdLineTime)
    if not s.aidPlayer then
     s.aidPlayer=true; e.stats.passCommit=(e.stats.passCommit or 0)+1
     U.log(e.log,now,'INFO',string.format('aide au depassement: %s engage sur %s (cote %s, %.0f m), %s tient sa ligne',pc.name,a.name,pr.lat*g.offsetSign>0 and 'gauche' or 'droit',max(0,pr.gap),a.name),i)
    end
   else
    if s.aidPlayer and not (pr and pr.alongside) then s.aidPlayer=false end
    if ps.committed==i and not (pr and pr.alongside) then Priority.release(e,frame.player); ps.aidLogged=0 end
   end
  end
  heldBy=Priority.held(s,now)
  if heldBy>0 then
   local side=e.states[heldBy].commitSide or 0
   if side<0 then row.left=true elseif side>0 then row.right=true end
   if s.heldCounted~=heldBy then s.heldCounted=heldBy; e.stats.lineHeld=(e.stats.lineHeld or 0)+1 end
  else s.heldCounted=0 end
 end
 -- Drapeau jaune ou neutralisation : limite propre, composée avec l'espacement par l'applicateur, descente bornée.
 local cap,yellow=Incidents.cap(e.incidents,frame,i,p,e.delta,e.states,s.persona.deltaMargin)
 s.yellow=yellow
 local regimeCap=cap
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
  local best,bj=K.scWatch,0
  for j=1,frame.count do
   local b=frame.cars[j]
   if j~=i and b.valid and not b.pit and b.splineValid and not (e.incidents.cars[j] and e.incidents.cars[j].incident) then
    local d=U.spline(b.spline-a.spline)*frame.length-((a.length or K.length)+(b.length or K.length))*0.5
    -- Beta 1.60 (course à Bakou du 11 novembre : le leader a doublé la voiture de sécurité) : la voiture de devant
    -- reste la cible de la file tant que celle-ci n'est pas entièrement passée (avant : dès 1 m de recouvrement, plus
    -- de cible, et la limite repartait à l'allure de rattrapage). Jamais derrière une voiture en difficulté (plus bas).
    local jc=e.incidents.cars[j]
    -- Relecture du lot 3 (M1) : seule la voiture dont le centre est derrière est limitée (borne d'une demi-longueur
    -- cumulée : avec une longueur entière, deux voitures côte à côte se limitaient l'une l'autre jusqu'à 30 km/h).
    if d>-((a.length or K.length)+(b.length or K.length))*0.5 and d<best and not (jc and jc.trouble) and not Penalties.mayPass(e.penalties,i,j,now,frame.player,true) then best=d; bj=j end
   end
  end
  -- Relecture du lot 3 (S6) : voiture de devant entre K.scQueueGap et K.scWatch m : enveloppe de freinage (vitesse d'où
  -- la descente à p.yellowDecel ramène à son allure à K.queueKeep m d'elle) ; avant, la limite ne commençait qu'à
  -- K.scQueueGap m et une voiture arrivant 100 km/h plus vite finissait à sa hauteur.
  if bj>0 and best>=K.scQueueGap then
   local vt=frame.cars[bj].kmh/3.6
   cap=min(cap,max(K.trafficMinSpeed,math.sqrt(vt*vt+2*p.yellowDecel*max(0,best-K.queueKeep))*3.6))
   bj=0
  end
  if bj>0 then
   cap=min(cap,max(K.trafficMinSpeed,frame.cars[bj].kmh+max(0,best-K.queueKeep)*K.queueClose))
   -- À sa hauteur (recouvrement) : K.scOverlapDrop km/h de moins qu'elle, pour revenir derrière.
   if best<0 then cap=min(cap,max(K.trafficMinSpeed,frame.cars[bj].kmh-K.scOverlapDrop)) end
   hardQueue=best<2*K.queueKeep; s.neutralQueue=bj
  else s.neutralQueue=0 end
 else s.neutralQueue=0 end
 if cap<K.unlimitedSpeed then
  local start=cmd.yellowLimit<K.unlimitedSpeed and cmd.yellowLimit or a.kmh
  cmd.yellowLimit=U.approach(max(start,cap),cap,p.yellowDecel*3.6*dt)
  if hardQueue then cmd.yellowLimit=min(cmd.yellowLimit,cap) end
 else cmd.yellowLimit=K.unlimitedSpeed end
 -- Beta 1.60 (décision du pilote d'après la course à Bakou : cinq IA sanctionnées pour avoir doublé une voiture
 -- endommagée qui roulait à plus de 25 km/h ; pratique de la FIA) : sous drapeau jaune ou neutralisation, une voiture
 -- nettement en difficulté peut être doublée sans sanction, par les IA et par le joueur (src/penalties.lua, passable) et
 -- la file ne se forme pas derrière elle. En difficulté : déjà « lente à contourner » avant le drapeau (s.abnormal), ou
 -- depuis K.troubleTime s sous K.troubleRatio fois l'allure qu'elle pourrait tenir (la limite du drapeau, bornée par son
 -- allure habituelle ici : un virage lent n'est pas une difficulté ; allure inconnue : jamais jugée), sans voiture
 -- devant qui la retienne (limite de la file). Jamais sous drapeau rouge ni pendant un tour de relance ou de formation
 -- (peloton qui s'élance). Une ligne au journal par épisode.
 local ic=e.incidents.cars[i]
 if ic then
  local trouble=false
  if (yellow or e.incidents.neutral) and not e.incidents.red and not e.incidents.relaunch and a.splineValid then
   local own=(s.freePace or 0)*3.6
   local ref=own>0 and regimeCap<K.unlimitedSpeed and min(regimeCap,own) or 0
   -- Relecture du lot 3 (N2) : jamais une voiture retenue par celle de devant (à moins de K.troubleAheadGap m) : seule
   -- la tête d'un train lent est en difficulté, pas chaque voiture du bouchon tour à tour.
   if ref>0 and cap>=regimeCap and a.kmh<ref*K.troubleRatio and not (row.front>0 and row.neighbors[row.front].gap<K.troubleAheadGap) then s.troubleFor=(s.troubleFor or 0)+dt else s.troubleFor=0 end
   trouble=s.troubleFor>=K.troubleTime or s.abnormal==true
   if trouble and not ic.trouble then
    e.stats.troubleCar=(e.stats.troubleCar or 0)+1
    U.log(e.log,now,'INFO',string.format('voiture en difficulte: %s (%.0f km/h, %.0f km/h permis), depassement permis sous drapeau',a.name,a.kmh,ref>0 and ref or regimeCap),i)
   end
  else s.troubleFor=0 end
  ic.trouble=trouble
 end
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
 -- Beta 1.60 (bus des modificateurs) : humeur de l'IA (src/mood.lua), après la base : les protections existantes la
 -- bornent toujours. Champ absent : neutre (x*1 est exact).
 aggression=aggression*(s.moodAggr or 1); caution=caution*(s.moodCaution or 1)
 if courtesy then aggression=aggression*K.courtesyAggression end
 local desired=0; local elapsed=now-math.max(e.startedAt,e.launchAt or -math.huge)
 -- Beta 1.52 : cession jugée à cette image (yieldTrigger appelé) ; sinon, plus de drapeau bleu en attente.
 local yieldEvaluated=false
 cmd.active=true; cmd.brake=0
 local startPhase=profile=='C' and elapsed<p.startDelay+p.startRelax
 -- Beta 1.42 AERO : air sale (sillage en virage) et urgence des derniers tours (agressivité, défense).
 -- Beta 1.47 : premier tour attentif (src/firstlap.lua, poids s.flW) : ni air sale, ni urgence, ni aspiration cassée,
 -- ni défense ; dépassement en vraie ligne droite seulement, évitement d'une voiture arrêtée ou très lente seulement.
 local firstLap=(s.flW or 0)>0
 -- Beta 1.52 : refus du premier tour attentif oublié hors du mode (une relance recompte).
 if not firstLap then s.flPassHeldFor=nil end
 s.dirty=dirtyAir(e,s,a,front,p,startPhase or firstLap)
 s.urgency=H.urgency(e,s,a,row,p,profile,frame,startPhase or firstLap)
 if s.urgency>0 then
  -- Relecture 1.42 : jamais d'agressivité en plus avec une attardée, une autre classe ou le joueur juste devant.
  local blocked=front and front.long>0 and front.gap<=K.finalRange and (front.index==frame.player or not rival(e,s,a,front,p,frame))
  if not blocked then aggression=aggression*(1+p.finalAggressionPct/100*s.urgency) end
  if not m.finalLogged then
   m.finalLogged=true
   U.log(e.log,now,'INFO',string.format('fin de course: %d derniers tours, agressivite +%.0f %%, defense +%.0f %%',H.finalLapsFor(p,frame,e.race),p.finalAggressionPct,p.finalDefensePct),-1)
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
      -- Beta 1.59 (MJFox) : voiture en travers = glissade tenue (K.spinTime s), plus une seule image de glissade (une
      -- voiture à peine dans l'herbe faisait éviter et ralentir celles de derrière).
      local sliding=e.incidents.cars[r.index].spin>=K.spinTime
      if slow and not approach and not sliding then jam=true end
      if (sliding or slow and approach) and (not obstacle or r.gap<obstacle.gap) then obstacle=r end
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
    s.blueVetoAt=now -- Beta 1.62 : évitement d un obstacle, excuse pour un drapeau bleu
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
    -- Beta 1.52 : pendant le repos anti-zigzag, une cession prioritaire (drapeau bleu, classe, tour lancé) peut encore
    -- commencer et n'est pas interrompue (céder au plus rapide passe avant le plafond, comme plus bas) ; seules les
    -- cessions ordinaires et les appels de phares attendent la fin du repos.
    local rest=now<s.driveUntil
    if rest and not (s.yieldBlue and yieldStates[s.state]) then transition(e,s,'DRIVE','direction_limit',now) end
    local canYield=not s.returning and not startPhase and not s.yellow and not braking and s.lapseUntil<=now and not s.alongside and (not yieldStates[s.state] or s.state=='YIELD_OUT')
    if canYield then yieldEvaluated=true
    -- Beta 1.62 (relecture 162v, point 2) : retour, départ, jaune, freinage, inattention imposée, voiture à côté ou cession
    -- déjà en cours : la cession est impossible, donc pas de temps compté pour un drapeau bleu ignoré.
    else s.blueVetoAt=now end
    if canYield and yieldTrigger(e,s,a,row,p,profile,now,dt,rest) then
     transition(e,s,'YIELD_IN','yield',now)
     if p.classNuance and s.yieldBlue and not s.yieldQuali and not s.abnormal then M.nuanceTruce(e,s,a,row,p,frame,now,i) end
    -- Retour après dépassement : jamais de nouveau maintien (PDR §10.2.4) ; l'occupation retient le rabattement.
    -- En attente derrière la cible (OVT_ARM), une voiture à côté retient le déboîtement mais ne le saute pas.
    elseif s.alongside and passStates[s.state] and s.state~='OVT_OUT' and s.state~='OVT_ARM' then transition(e,s,'OVT_HOLD','alongside',now) end
    if yieldStates[s.state] then
     -- Sous drapeau jaune, laisser passer revient à se faire dépasser : la cession s'achève.
     if s.yellow and s.state~='YIELD_OUT' then transition(e,s,'YIELD_OUT','yellow',now) end
     -- Beta 1.62 (qualifications : « sacrifier son virage ») : cession à une voiture lancée en qualifications : décalage
     -- tenu dans le virage (bornes par côté inchangées) au lieu de revenir vers la corde.
     local amp=(s.yieldQuali and profile=='Q') and 1 or K.cornerAmpMin+(1-K.cornerAmpMin)*a.corner
     desired=s.targetSide*min(p.maxSideOffset,p.yieldOffset*amp*(s.urgent and K.urgentAmp or 1))
     if p.predictableSlowClass and s.yieldClass or s.yieldLine then desired=s.base end
     -- Beta 1.62 (essais, qualifications, journée circuit : « jamais ralentir sur la ligne en virage rapide ni au
     -- freinage ») : hors course, la voiture qui cède ne lève le pied qu'en ligne droite hors freinage ; en virage elle
     -- tient son allure et se décale seulement.
     local liftOk=profile=='C' or a.corner>=p.cornerMin and ownBrake<=K.ruleBrake
     if s.state=='YIELD_IN' and abs(s.offset-M.reachable(s,a,p,g,desired))<K.yieldReachedEpsilon then transition(e,s,'YIELD_HOLD','yield_position',now) end
     if s.state~='YIELD_OUT' then
      -- Beta 1.41 : IA déjà anormalement lente (dégâts) : pas de ralentissement de plus pour céder.
      -- Beta 1.61 (classNuance, drapeau bleu en course) : de K.blueSlowdown (voiture retenue) à K.blueSlowMin (voiture
      -- bien plus rapide : seule la trajectoire est donnée), selon la vitesse de rapprochement du moment.
      if not s.abnormal and liftOk then level=level*(1-(s.yieldBlue and K.blueSlowdown or p.yieldSlowdownPct/100)) end; aggression=aggression*K.yieldAggression
      if p.classNuance and profile=='C' and s.yieldBlue and not s.abnormal and not s.yieldQuali and not s.yieldClass then level=level*(1-Nuance.slowdown(target and target.long<0 and target.sa or K.blueFastSa))/(1-K.blueSlowdown) end
      -- Beta 1.60 (lot 3, passage franc) : attaquant engagé à sa hauteur ou juste derrière (s.frankLift, image d'avant) :
      -- K.frankYieldLevel de niveau en moins, virages compris (la limite de vitesse ne joue qu'en ligne droite).
      if s.frankLift and not s.abnormal and liftOk then level=level*(1-K.frankYieldLevel) end
      if s.state=='YIELD_HOLD' then caution=caution*K.yieldHoldCaution end
     end
     if target and target.long<0 and target.gap<K.invitationGap then
      s.linger=s.linger+dt
      if (s.linger>K.invitationTime or s.urgent) and not s.abnormal and liftOk then level=level*(1-p.inviteSlowdownPct/100*U.clamp((s.linger-K.invitationTime)/K.invitationRamp+(s.urgent and 1 or 0),0,1)) end
     end
     local remaining=0
     for j=1,row.count do
      local r=row.neighbors[j]; local other=frame.cars[r.index]
      if r.long<0 and r.gap>=0 and r.gap<=s.yieldDetection and abs(r.lat)<=K.latYield and not yieldStates[e.states[r.index].state] then
       local laps,upper=lapOrClass(e,s,a,other,r,p,profile)
       local qualifies=profile~='C' and p.yieldEnabled and r.sa>=p.yieldBehindMargin or laps>0 and r.sa>=K.lapSpeed or upper and r.sa>=p.classYieldMargin
        or s.yieldQuali and e.quali.push[r.index] and r.sa>=-K.blueSlack
        or p.classNuance and upper and r.sa>=-K.blueSlack and Nuance.train(row,r,s.followers,frame) -- Beta 1.61 : groupe de la classe rapide
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
       -- Beta 1.61 (classNuance) : la voiture est passée : sa part de la trêve finit ; en course, celle qui vient de
       -- prendre un tour à l'IA n'est pas attaquée en retour pendant K.relapHold s.
       if passed and p.classNuance and s.yieldBlue and not s.yieldQuali then
        Nuance.passed(e.nuance,i,j,now)
        if profile=='C' and leadLaps(frame.cars[j],a)>0 then s.relapBy=j; s.relapUntil=now+K.relapHold end
       end
       if passed or lost then s.followers[j]=false else remaining=remaining+1 end
      end
     end
     if remaining>=2 and s.yieldBlue then s.multiLeader=true end
     if remaining==0 and s.state~='YIELD_OUT' then
      if not s.postPass then s.holdUntil=max(s.holdUntil,now+s.persona.holdAfter+(s.multiLeader and K.blueTrainHold or 0)); s.postPass=true end
      if now-s.yieldStart>=max(K.holdFloor,p.yieldHoldMin) and now>=s.holdUntil then
       -- Beta 1.41 : « passed » (abouties) seulement si un suiveur est vraiment passé ; suiveurs perdus : « lost » ; perdu
       -- faute de se rapprocher (cession ordinaire), le suiveur principal n'est plus attendu pendant K.passIgnore s.
       -- Beta 1.52 : cessions en tour lancé comptées par transition() (toutes les sorties).
       if s.yieldPassed then transition(e,s,'YIELD_OUT','passed',now)
       else
        if s.yieldStalled then s.yieldIgnore=s.target; s.yieldIgnoreUntil=max(s.yieldIgnoreUntil,now+K.passIgnore) end
        transition(e,s,'YIELD_OUT','lost',now)
       end
      end
     end
     -- Beta 1.52 : durée maximale atteinte : suiveur ignoré une fois, à l'entrée en YIELD_OUT (réécrit à chaque image de
     -- la sortie, l'oubli était sans cesse repoussé).
     if now-s.yieldStart>p.yieldMaxHold+(s.frankLift and K.frankYieldExtra or 0) and s.state~='YIELD_OUT' then s.ignoreTarget=s.target; s.ignoreUntil=now+K.ignoreFollower; transition(e,s,'YIELD_OUT','hold_limit',now) end
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
      -- Beta 1.60 (réglage passAid) : engagement de l'attaquant (en ligne droite, décalé d'au moins K.commitLat m de la
      -- cible, à K.commitGap m de son pare-chocs ou à sa hauteur, couloir libre) : gardé pour la tentative. Tant qu'il
      -- dure hors virage, la cible tient sa ligne (src/priority.lua) ; entre deux IA, léger gain de niveau borné
      -- (K.passAidLevel pendant K.passAidMax s, puis K.passAidPairCooldown s sans gain sur la même paire), sans la
      -- levée de l'air sale. Au virage, la priorité au virage décide (plus de ligne tenue ni de gain).
      if p.passAid and (s.state=='OVT_IN' or s.state=='OVT_HOLD') then
       if s.committed~=s.target and a.corner>=K.passCornerC and target.lat*s.targetSide>=K.commitLat and target.long>-(a.length+frame.cars[s.target].length)*0.5
        and (target.alongside or target.gap<=K.commitGap) and P.corridor(frame.cars,frame.count,i,s.targetSide,K.corridorMin,s.target,g.occLatMax) then
        Priority.commit(e,i,s.target,s.targetSide,now); e.stats.passCommit=(e.stats.passCommit or 0)+1
        s.aidBonus=s.target~=frame.player and not (s.aidPair==s.target and now<(s.aidPairUntil or 0) and s.aidPairUntil-now<=K.passAidPairCooldown)
        if s.aidLogged~=s.target then
         s.aidLogged=s.target
         U.log(e.log,now,'INFO',string.format('aide au depassement: %s engage sur %s (cote %s, %.0f m), %s tient sa ligne',a.name,frame.cars[s.target].name,s.targetSide*g.offsetSign<0 and 'gauche' or 'droit',max(0,target.gap),frame.cars[s.target].name),i)
        end
       end
       if s.committed==s.target and not Priority.cornerContext(a,p,ownBrake) then
        Priority.hold(e,s.target,i,now+K.holdLineTime)
        if s.aidBonus and now-s.commitAt<=K.passAidMax then
         level=level*(1+K.passAidLevel); s.dirty=0
         s.aidPair=s.target; s.aidPairUntil=now+K.passAidPairCooldown
        end
       end
      end
      -- Beta 1.60 (lot 3, demande du pilote : dès que la voiture de devant commence à se décaler, celle de derrière
      -- accélère et dépasse rapidement) : cible qui lui cède et vraiment sortie de la trajectoire : passage franc.
      -- Léger gain de niveau borné (K.frankLevel pendant K.frankMax s, sans le réglage passAid : une cession accordée
      -- est le cas le plus sûr), prudence et agressivité au moins à leur base ; les prudences de sécurité (radar,
      -- premier tour, drapeaux, freinage et virage) s'appliquent toujours ensuite.
      if (s.state=='OVT_IN' or s.state=='OVT_HOLD') and frankYield(e,frame,i,s.target,profile,g,target) then
       if s.frankFor~=s.target then
        s.frankFor=s.target; s.frankAt=now; e.stats.frankPass=(e.stats.frankPass or 0)+1
        U.log(e.log,now,'INFO',string.format('passage franc: %s -> %s (%.0f m, cible ecartee)',a.name,frame.cars[s.target].name,max(0,target.gap)),i)
       end
       if now-s.frankAt<=K.frankMax then level=level*(1+K.frankLevel); s.dirty=0 end
       caution=min(caution,s.baseCaution); aggression=max(aggression,s.baseAggression)
      end
      -- Beta 1.60 (lot 3) : suivi d'un dépassement sur une cession accordée (preuve en jeu de ce qui retient
      -- l'attaquant) : toutes les K.frankTracePeriod s, cible à moins de K.frankTraceGap m : vitesses, niveau, prudence,
      -- limites de vitesse et d'accélérateur et frein de l'app des deux voitures (commandes de l'image d'avant).
      local yts=e.states[s.target]
      if s.state~='OVT_OUT' and yts and yts.followers and yts.followers[i] and (yts.state=='YIELD_IN' or yts.state=='YIELD_HOLD') and target.gap<K.frankTraceGap
       and (now>=(s.frankTraceAt or -math.huge) or s.frankTraceAt-now>K.frankTracePeriod) then
       s.frankTraceAt=now+K.frankTracePeriod
       local tc=e.commands[s.target]; local b=frame.cars[s.target]
       U.log(e.log,now,'INFO',string.format('suivi du depassement: %s -> %s | ecart %.0f m, lateral %.1f m, %s | lui %.0f km/h, niveau %.2f, prudence %.2f, limite %s, gaz %.2f, frein %.2f | cible %.0f km/h, niveau %.2f, limite %s, gaz %.2f',
        a.name,b.name,target.gap,abs(target.lat),s.state=='OVT_HOLD' and 'cote a cote ou en position' or 'en deboitement',a.kmh,cmd.level or 0,cmd.caution or 0,H.capText(cmd.speedLimit),cmd.throttleLimit or 1,s.appBrake or 0,
        b.kmh,tc.level or 0,H.capText(tc.speedLimit),tc.throttleLimit or 1),i)
      end
      if alongside then s.passAlongside=true; s.holdStall=0; s.holdLong=math.huge; if s.state~='OVT_OUT' then transition(e,s,'OVT_HOLD','alongside',now) end; desired=s.offset end
      if s.state=='OVT_IN' and abs(s.offset-M.reachable(s,a,p,g,desired))<K.yieldReachedEpsilon then transition(e,s,'OVT_HOLD','pass_position',now) end
      if not alongside and s.state~='OVT_OUT' then
       -- Affinage 1.61 (courses de Zandvoort et de Spa du 11 novembre : 78 et 7 fins « cote ferme », attaquant encore
       -- derrière sa cible, en virage ou dans la file de 40 voitures) : une voiture plus loin devant qui roule
       -- au moins aussi vite ne ferme pas le couloir (elle s'éloigne, comme au départ de la tentative) ; en course,
       -- l'attaquant pas encore déboîté (OVT_ARM) ne juge le couloir qu'en ligne droite hors freinage (en virage, les voitures
       -- devant paraissent sur le côté).
       local race=profile=='C'
       local straight=a.corner>=K.passCornerC and ownBrake<K.passBrakeMax and not braking
       local clear=P.corridor(frame.cars,frame.count,i,s.targetSide,K.corridorMin,s.target,g.occLatMax,a.speed-K.corridorLeadMargin)
       if race and s.state=='OVT_ARM' and not straight then clear=true end
       -- Abandon avant le côte à côte seulement (PDR §10.2.4) : ensuite l'IA termine, sauf si la cible repasse devant
       -- et s'éloigne. « La cible s'échappe » ne vaut que pour une cible encore devant.
       -- Beta 1.60 (lot 4, Nürburgring GP et Red Bull Ring du 11 novembre : 22 et 27 fins « cible plus rapide » après
       -- 5 s environ, à 9–21 m, cible qui réaccélère en sortie de virage) : « elle s'échappe » se juge sur l'écart en
       -- temps, pas sur la vitesse seule : il doit avoir grandi de K.abortTgGrow s depuis le plus petit de la tentative
       -- (deux voitures qui accélèrent ensemble gardent le même écart en temps alors que les mètres grandissent).
       -- L'écart en temps est suivi par sa dérive (vitesse relative mesurée, moins l'effet de l'accélération propre),
       -- sans dépendre de la position : le compte des K.abortSlowTime s reste celui d'avant, il attend seulement.
       local v=max(a.kmh/3.6,K.abortTgSpeed)
       local dv=s.passPrevV and v-s.passPrevV or 0; s.passPrevV=v
       s.passTg=(s.passTg or 0)-dt*target.sa/3.6/v-target.gap*dv/(v*v)
       if s.passMinTg==nil or s.passTg<s.passMinTg then s.passMinTg=s.passTg end
       s.abortSlow=target.long>0 and target.sa<0 and target.gap>K.abortGap and s.abortSlow+dt or 0
       -- Affinage 1.61 (mêmes courses : 79 et 31 fins « cible plus rapide » 6 à 8 s après un départ en fin de ligne
       -- droite, à 7–12 m au plus près ; la cible ressortait du virage plus vite) : en course, l'écart ne se juge qu'en
       -- ligne droite hors freinage, et il doit avoir grandi de K.abortTgGrowRace s (au lieu de K.abortTgGrow).
       if race and not straight then s.abortSlow=min(s.abortSlow,K.abortSlowTime) end
       if s.passTg-s.passMinTg<(race and K.abortTgGrowRace or K.abortTgGrow) then s.abortSlow=min(s.abortSlow,K.abortSlowTime) end
       s.passStall=s.state~='OVT_ARM' and target.long>0 and not s.passAlongside and target.sa<K.passStallSa and s.passStall+dt or 0
       if s.state=='OVT_ARM' and now-s.since>K.passArmMax then s.passStall=K.passStallTime+dt end
       s.passBlocked=not clear and not s.passAlongside and s.passBlocked+dt or 0
       -- Beta 1.60 (réglage passAid) : attaquant engagé, cible qui ne s'éloigne pas de plus de K.passAidSaMax km/h :
       -- « cible plus rapide » et « sans rapprochement » ne comptent pas, au plus K.passAidHold s après l'engagement.
       if p.passAid and s.committed==s.target and target.sa>=-K.passAidSaMax and now-s.commitAt<=K.passAidHold then s.abortSlow=0; s.passStall=0 end
       -- Beta 1.55 (Nordschleife, 9 novembre : tentatives de 9 s en moyenne, jusqu'à 62 s, 27 sur 43 finies « cible plus
       -- rapide ») : hors course, pas encore côte à côte, cible devant (jamais le joueur) : abandon sans K.passProgressGain m
       -- gagnés en K.passProgressTime s, et au bout de K.passAttemptMax s sauf terrain gagné dans les K.passCapGrace
       -- dernières secondes (un dépassement lent qui progresse n'est jamais coupé).
       local judged=profile~='C' and s.target~=frame.player and target.long>0 and not s.passAlongside
       if judged and target.gap<=s.passProgRef-K.passProgressGain then s.passProgRef=target.gap; s.passProgTime=0
       elseif judged then s.passProgTime=s.passProgTime+dt else s.passProgRef=target.gap; s.passProgTime=0 end
       local noProgress=judged and s.passProgTime>K.passProgressTime
       local tooLong=judged and U.finite(s.passStartAt) and now-s.passStartAt>K.passAttemptMax and s.passProgTime>K.passCapGrace
       -- Côte à côte achevé sans marge atteinte (cible repassée devant, ou juste derrière à la même allure) : retour au
       -- bout de quelques secondes sans progrès vers la marge ; un dépassement lent qui progresse n'est jamais coupé.
       if s.passAlongside then
        if target.long<s.holdLong-K.holdProgress then s.holdLong=target.long; s.holdStall=0 else s.holdStall=s.holdStall+dt end
       else s.holdStall=0; s.holdLong=math.huge end
       -- Suiveur beaucoup plus rapide : en course, seulement s'il prend un tour ou vient d'une classe plus rapide (on ne
       -- renonce pas à une attaque pour une voiture du même tour qui freine plus tard).
       local fastBack=not s.passAlongside and back and back.sa>=K.abortFollowerSpeed and back.gap<K.abortFollowerGap
        and (profile~='C' or Classes.laps(a,frame.cars[back.index],back,frame.length)>0 or faster(p,e.states[back.index],s))
       -- Beta 1.59 (journées circuit du 10 novembre : 47 abandons « cible plus rapide », 32 « sans progrès » sur 159
       -- tentatives) : hors course, cible qui cède à cette IA : l'attaque s'engage, plus d'abandon « cible plus rapide »,
       -- « sans rapprochement », « sans progrès » ni « trop longue » tant que la cession dure (elle a sa propre durée
       -- maximale) ; côté fermé, suiveur rapide et côte à côte sans progrès restent.
       local ts=e.states[s.target]
       -- Beta 1.60 (lot 3) : en course aussi pour une cession prioritaire (drapeau bleu, classe). Le compte « sans
       -- progrès » court toujours pendant la cession (essayé : le remettre à zéro relançait la boucle de dépassements
       -- de la 1.54, 14 tentatives en 6 min sur une cible qui repart plus vite).
       local yielded=ts and ts.followers and ts.followers[i] and (ts.state=='YIELD_IN' or ts.state=='YIELD_HOLD') and (profile~='C' or ts.yieldBlue==true) or false
       if yielded then
        s.abortSlow=0; s.passStall=0; noProgress=false; tooLong=false
        -- Beta 1.60 (lot 3, Nürburgring GP du 11 novembre : cession et dépassement tous deux « vers la droite », 25 s
        -- l'un derrière l'autre) : la cible s'écarte du côté que l'attaquant avait pris : il change de côté (la voiture
        -- qui cède va où elle a la place ; la trajectoire qu'elle libère est à lui), l'autre côté libre.
        -- Relecture (S8) : seulement si la cible a vraiment bougé (passage franc) et si le plafond anti-zigzag le permet.
        if not ts.yieldLine and ts.targetSide==s.targetSide and target.long>0 and sideFree(row,-ts.targetSide) and frankYield(e,frame,i,s.target,profile,g,target)
         and directionAllowed(s,-ts.targetSide*0.5,now,p,false,-ts.targetSide*0.5) then
         s.targetSide=-ts.targetSide; e.stats.passAwaySide=(e.stats.passAwaySide or 0)+1
        end
        if profile=='C' then fastBack=false end
       end
       -- Beta 1.60 (réglage passAid) : attaquant engagé : « sans progrès » et « trop longue » attendent aussi, le temps
       -- du gain de niveau (K.passAidMax s après l'engagement).
       if p.passAid and s.committed==s.target and now-s.commitAt<=K.passAidMax then noProgress=false; tooLong=false end
       -- Beta 1.59 (première journée circuit en 1.59, 10 novembre : 42 abandons « suiveur rapide » sur 113 tentatives, la
       -- file derrière le joueur rangé renonçait voiture après voiture) : hors course, dans les trois cas où l'attaque
       -- s'engage (cible qui lui cède, joueur rangé, voiture lente ou file derrière elle), la voiture qui arrive derrière
       -- passe par le même couloir : plus d'abandon « suiveur rapide ». Joueur rangé et plus lent que l'allure libre de
       -- l'IA ici : plus d'abandon « cible plus rapide » ni « sans rapprochement » non plus. Sécurité inchangée.
       if profile~='C' then
        local aside=s.target==frame.player and abs(target.lat)>=K.inviteLat
        local slow=ts and ts.abnormal==true or queueSlow(e,frame,target)
        if yielded or aside or slow then fastBack=false end
        if aside and s.freePace>0 and frame.cars[s.target].speed<s.freePace then s.abortSlow=0; s.passStall=0 end
       end
       if s.passBlocked>K.abortBlocked or s.abortSlow>K.abortSlowTime or s.passStall>K.passStallTime or fastBack or s.holdStall>K.passHoldMax or noProgress or tooLong then
        s.aborts=s.aborts+1
        local why=s.passBlocked>K.abortBlocked and 'abort_blocked' or s.abortSlow>K.abortSlowTime and 'abort_slow' or s.passStall>K.passStallTime and 'abort_stall' or fastBack and 'abort_follower'
         or s.holdStall>K.passHoldMax and 'hold_limit' or noProgress and 'abort_noprogress' or tooLong and 'abort_timeout' or 'hold_limit'
        transition(e,s,'OVT_OUT',why,now)
        -- Beta 1.41 : cible repartie plus vite : plus de dépassement sur cession ni sur retenue de cette cible pendant
        -- K.passIgnore s, multiplié par K.passIgnoreGrowth à chaque nouvel échec sur elle (au plus K.passIgnoreMax s,
        -- compte oublié K.passIgnoreForget s après la fin de la dernière attente) ; hors course, elle ne lui cède plus
        -- pendant ce temps (jamais un drapeau bleu ni une classe : en course, rien n'est ignoré par elle).
        -- Beta 1.44 : jamais contre le joueur hors course (il ralentit et repart à sa guise pour se faire doubler).
        -- Beta 1.55 : abandons « sans progrès » et « tentative trop longue » (hors course) dans la même attente.
        -- Beta 1.60 (lot 5, course du 11 novembre : attardées « attaquées puis abandonnées ») : en course, aucun échec
        -- compté contre une voiture à qui l'on prend un tour (jamais d'attente : elle doit s'écarter au drapeau bleu).
        -- Finition 1.61 (relecture) : contre une attardée en course, pas d'attente qui grandit, mais une courte attente
        -- fixe (K.passLappedHold s) : sans elle, rien ne bornait les reprises (boucles des 1.47 et 1.54).
        if (why=='abort_slow' or why=='abort_noprogress' or why=='abort_timeout') and profile=='C' and leadLaps(a,frame.cars[s.target])>0 then
         s.lappedHold=s.target; s.lappedHoldUntil=now+K.passLappedHold
        end
        if (why=='abort_slow' or why=='abort_noprogress' or why=='abort_timeout') and (profile=='C' or s.target~=frame.player) and not (profile=='C' and leadLaps(a,frame.cars[s.target])>0) then
         if s.passIgnore~=s.target or now>s.passIgnoreUntil+K.passIgnoreForget then s.passIgnore=s.target; s.passIgnoreCount=0; s.passReopened=nil end
         s.passIgnoreCount=s.passIgnoreCount+1
         -- Beta 1.60 (essais à Monza du 11 novembre : la voiture la plus rapide écartée 180 s d'une voiture qu'elle
         -- rattrapait à +31 km/h six secondes plus tard) : hors course, « cible plus rapide » après un vrai rapprochement
         -- (K.passProgressGain m gagnés pendant la tentative : la cible est repartie, aspiration perdue en déboîtant ou
         -- sortie de virage) : l'échec ne compte pas vers l'attente stricte.
         if why=='abort_slow' and (s.passGap0 or 0)-s.passMinGap>=K.passProgressGain then s.passIgnoreCount=min(s.passIgnoreCount,K.passIgnoreStrict-1) end
         s.passIgnoreAt=now
         -- Lot 5 : en course, jamais plus de K.passIgnoreMaxRace s (deux paires écartées 600 s le 11 novembre).
         local hold=min(profile=='C' and K.passIgnoreMaxRace or K.passIgnoreMax,K.passIgnore*K.passIgnoreGrowth^(s.passIgnoreCount-1))
         s.passIgnoreUntil=now+hold
         -- Beta 1.54 : attente stricte (plus de rapprochement accepté, plus d'appel de phares hors course) notée au journal.
         if s.passIgnoreCount>=K.passIgnoreStrict then
          U.log(e.log,now,'INFO',string.format('depassement suspendu: %s -> %s apres %d echecs (%s), plus de tentative pendant %.0f s',a.name,s.passName,s.passIgnoreCount,H.passEnd[why],hold),i)
         end
         local o=e.states[s.target]
         if profile~='C' and not o.yieldBlue then o.yieldIgnore=i; o.yieldIgnoreUntil=max(o.yieldIgnoreUntil,now+hold) end
        end
       end
      end
      if s.state=='OVT_ARM' then
       desired=s.base
       -- Affinage 1.62 (12 novembre : « si le joueur ralentit beaucoup sur le côté, l'IA reste derrière » ; au banc, attente
       -- du déboîtement de 38 m à −7 m sans bouger) : cible déjà écartée de la trajectoire d'au moins K.inviteLat m, plus
       -- lente, ligne droite hors freinage : côté qu'elle a libéré pris aussitôt (comme une invitation), couloir libre.
       if abs(target.lat)>=K.inviteLat and target.long>0 and target.sa>=0 and a.corner>=K.passCornerC and not s.alongside and ownBrake<K.passBrakeMax and not braking then
        local side=target.lat>0 and 1 or -1
        if sideFree(row,side) and P.corridor(frame.cars,frame.count,i,side,K.corridorMin,s.target,g.occLatMax) then
         s.targetSide=side; e.stats.armOpen=(e.stats.armOpen or 0)+1; transition(e,s,'OVT_IN','opened',now)
        end
       end
       -- Déboîtement en ligne droite seulement (PDR §10.2.4).
       if s.state=='OVT_ARM' and target.gap<=U.clamp(p.pullOutGapBase+p.pullOutGapPerMps*a.speed,p.pullOutGapBase,K.pullOutMax) and a.corner>=K.passCornerC and not s.alongside and ownBrake<K.passBrakeMax and not braking
        and -target.lat*s.targetSide<K.pullOutTargetLat and M.pullOutTime(e,a,target,frame) and H.seekLate(e,s,a,target,frame) then transition(e,s,'OVT_IN','pull_out',now) end
       -- Affinage 1.62 : en attente, dans l'aspiration de la cible écartée de la trajectoire.
       if s.state=='OVT_ARM' then local sd=H.slipSeek(e,s,a,row,p,profile,frame,now,target,braking,ownBrake,startPhase or firstLap,i,g,m); if sd then desired=sd end end
      end
      if target.long<-(a.length+frame.cars[target.index].length)*0.5-p.overtakeClearMargin then s.clear=s.clear+dt else s.clear=0 end
      if s.clear>=K.clearConfirm and s.state~='OVT_OUT' then
       -- Beta 1.52 : enchaînement sur la voiture suivante soumis aux gardes du déclenchement (plafond anti-zigzag,
       -- inattention, tours lancés, premier tour attentif, paire ignorée sans vraie avance, cible qui cède du même côté),
       -- tentative au journal comme une autre (fin de la précédente, nouvelle cible, écart mini, instant du début).
       local chained=p.overtakeChain and front and front.index~=s.target and front.gap<p.overtakeDetectAhead
       if chained then
        local nextCar=frame.cars[front.index]; local nextState=e.states[front.index]
        local slowNext=nextState.abnormal==true
        local potential=max(front.sa,slowNext and (s.freePace-a.speed)*3.6 or 0)
        local advantage=profile=='C' and K.passAdvantageC or K.passAdvantageJ
        local ignoredNext=front.index==s.passIgnore and now<s.passIgnoreUntil and not slowNext
        -- Plafond anti-zigzag : ni pendant le repos ni plafond atteint ; le délai entre deux changements de côté ne compte
        -- pas (l'enchaînement garde son côté).
        if now<s.driveUntil or activeDirections(s,now)>=K.directionLimit or s.lapseUntil>now
         or yieldStates[nextState.state] and nextState.targetSide==s.targetSide
         or ignoredNext and realAdvantage(e,s,nextState,a,p)~=true then chained=false
        elseif qualiGuard(e,i,front.index) and not slowNext then
         chained=false
         if potential>=advantage and s.qualiHeldFor~=front.index then s.qualiHeldFor=front.index; e.stats.qualiNoPass=(e.stats.qualiNoPass or 0)+1 end
        elseif firstLap and H.firstLapHeld(s,a,nextCar,nextState,ownBrake,potential,advantage) then
         chained=false
         if s.flPassHeldFor~=front.index then s.flPassHeldFor=front.index; e.stats.flPass=(e.stats.flPass or 0)+1 end
        end
        chained=chained and P.corridor(frame.cars,frame.count,i,s.targetSide,K.corridorMin,front.index,g.occLatMax)
        if chained then
         H.passFinished(e,s,'chain',now)
         s.target=front.index; s.clear=0; s.passStall=0; s.passAlongside=false
         U.log(e.log,now,'INFO',string.format('depassement: %s -> %s (enchainement, %.0f m, %+.0f km/h)',a.name,nextCar.name,front.gap,front.sa),i)
         s.passStartAt=now; s.passGap0=front.gap; s.passMinGap=front.gap; s.passMinTg=nil; s.passTg=0; s.passPrevV=nil; s.passName=nextCar.name; s.lastPassTarget=front.index; s.lastPassAt=now
         s.passProgRef=front.gap; s.passProgTime=0
         transition(e,s,'OVT_IN','chain',now)
        end
       end
       if not chained then transition(e,s,'OVT_OUT','clear',now) end
      end
     end
     if s.state=='OVT_OUT' then desired=s.base; if abs(s.offset-M.reachable(s,a,p,g,s.base))<K.centerEpsilon then s.restUntil=now+p.overtakeRestTime; s.target=0; transition(e,s,'DRIVE','pass_end',now) end end
     if s.state=='OVT_IN' or s.state=='OVT_HOLD' then aggression=aggression*K.passAggression; caution=min(caution,max(K.slipCautionMin,caution*K.passCaution)) end
    elseif s.state=='DEFEND' and s.towing then
     -- Beta 1.42 AERO : aspiration cassée, côté tenu jusqu'à la fin de la ligne droite ; retour à la ligne (conduite libre,
     -- jamais compté par le plafond) avant le freinage.
     desired=s.targetSide*min(K.towOffset,p.maxSideOffset)
     local ahead=m.bins>0 and m.run[Delta.bin(a.spline,m.bins)]*frame.length/m.bins or 0
     local req=e.flash.requests[i]
     if now>=s.defendUntil or s.alongside or s.yellow or e.incidents.neutral or e.incidents.red or a.brake>K.ruleBrake or req.untilTime>now or not back
      or not sideFree(row,s.targetSide) or a.corner<p.cornerMin or ahead<K.towReturnTime*a.speed
      or s.towPair>0 and (e.states[s.towPair].state=='OVT_IN' or e.states[s.towPair].state=='OVT_HOLD') then s.towing=false; transition(e,s,'DRIVE','tow_end',now) end
    elseif s.state=='DEFEND' then
     desired=s.targetSide*min(p.defenseMaxOffset,p.maxSideOffset); aggression=aggression*K.defenseAggression; caution=caution*K.defenseCaution
     -- Beta 1.60 (réglage passAid) : attaquant engagé : la défense s'arrête, la voiture tient sa ligne (ni levée ni frein).
     if heldBy>0 then transition(e,s,'DRIVE','held_line',now); desired=s.offset end
     local req=e.flash.requests[i]
     if now>=s.defendUntil or s.alongside or s.yellow or a.brake>K.ruleBrake or req.untilTime>now or not back or not sideFree(row,s.targetSide) then transition(e,s,'DRIVE','defense_end',now) end
    else
     s.base=userSide(s.persona.laneBias,g)
     if row.nearest>K.jitterRange and heldBy==0 then s.base=s.base+(math.sin(now/s.persona.jitterPeriod*math.pi*2+s.persona.phase)+0.5*math.sin(now/s.persona.jitterPeriod2*math.pi*2-s.persona.phase))/1.5*p.personalLineJitter end
     -- Beta 1.42 AERO : dans l'air sale, la variation de ligne de l'IA (mêmes ondes, plus rapides) devient des
     -- micro-corrections ; jamais vers un côté occupé, bornée comme la ligne, jamais comptée comme changement de côté.
     if s.dirty>0 and not row.left and not row.right then
      local t=now*K.dirtyJitterRate
      s.base=s.base+(math.sin(t/s.persona.jitterPeriod*math.pi*2+s.persona.phase)+0.5*math.sin(t/s.persona.jitterPeriod2*math.pi*2-s.persona.phase))/1.5*s.dirty*max(K.dirtyJitterAmp,p.personalLineJitter*K.dirtyJitterGain)
     end
     s.base=s.base+(s.zone.lineOffset or 0)+(s.formOffset or 0) -- Beta 1.61 : ligne de la zone (src/zones.lua), file du tour de formation (src/antics.lua)
     local baseMax=s.formWeave and K.formWeaveMax or K.baseMax -- Correctif 1.61 : zigzag du tour de formation
     s.base=U.clamp(s.base,-baseMax,baseMax); desired=s.base
     local defend=false
     -- Défense : jamais au freinage, quel que soit l'onglet Règles.
     local boost=s.urgency>0 and back and back.index~=frame.player and rival(e,s,a,back,p,frame) and 1+p.finalDefensePct/100*s.urgency or 1
     -- Beta 1.47 (Monza, 4 novembre : déport vers le joueur arrivé à gauche, +51 km/h, dans un virage à droite, sur un tour
     -- de sortie) : défense seulement contre un suiveur nettement d'un côté (au moins K.defenseLatMin m), pas beaucoup plus
     -- rapide (au plus K.defenseSaMax km/h, ou contact à K.defenseTTCMin s au moins), en vraie ligne droite avec de la
     -- ligne droite devant (carte des lignes droites, si apprise), jamais à hauteur, sur un tour de sortie, pendant la garde
     -- après les stands ni près de la jonction des stands.
     -- Beta 1.52 : jugée seulement en course, défense permise (avant, calculée dans tous les profils).
     local defendOk=heldBy==0 and profile=='C' and p.defenseEnabled and not firstLap and back~=nil and abs(back.lat)>=K.defenseLatMin and (back.sa<=K.defenseSaMax or back.ttc>=K.defenseTTCMin) and a.corner>=K.defenseCorner
      and not back.alongside and now>=(s.pitGuardUntil or 0) and not (e.strategy and e.strategy.cars[i] and e.strategy.cars[i].outLap)
      and not (a.pitDistance and a.pitDistance<K.pitZone)
     if defendOk and m.bins>0 and a.splineValid and frame.length>0 then
      -- Carte apprise devant (endroit suivant vu, carte calculée) : sinon, rien à juger.
      local b=Delta.bin(a.spline,m.bins); local nb=b%m.bins+1
      if p.towBreakEnabled and m.at>-math.huge and m.seen[nb]>=K.towMapSeen and m.run[b]*frame.length/m.bins<K.defenseRunTime*a.speed then defendOk=false end
     end
     local junction=e.merge and e.merge.spline or -1
     if defendOk and junction>=0 and frame.length>0 then local after=U.spline(a.spline-junction)*frame.length; if after>=-K.towMergeBefore and after<=K.towMergeAfter then defendOk=false end end
     -- Beta 1.60 (lot 5, course du 11 novembre : « defense: Freddie Slater couvre … » alors qu'elle roulait à 81 km/h
     -- pour 171) : une voiture lente à contourner, en difficulté ou sous K.troubleRatio fois son allure ne défend jamais.
     if defendOk and (s.abnormal==true or e.incidents.cars[i] and e.incidents.cars[i].trouble or (s.freePace or 0)>0 and a.speed<s.freePace*K.troubleRatio) then defendOk=false end
     if defendOk and not s.returning and not startPhase and not s.yellow and a.brake<=K.ruleBrake and s.lapseUntil<=now and profile=='C' and p.defenseEnabled and back and back.gap<p.defenseTriggerGap*boost and back.sa>0 and a.corner>=K.passCornerC and not s.alongside and now>=s.defendCooldown and directionBudget(s,now,p) and not s.defendUsed and e.flash.requests[i].untilTime<=now then
      local laps,upper=lapOrClass(e,s,a,frame.cars[back.index],back,p,profile)
      -- Beta 1.60 (réglage rearAwareness) : défense en un seul mouvement, tôt : jamais quand l'attaquant sera à hauteur
      -- dans l'horizon, est déjà décalé de K.defensePulledLat m ou a déjà déboîté (IA en dépassement). Une ligne par
      -- ligne droite.
      local late=false
      if p.rearAwareness then
       local os=e.states[back.index]
       late=max(0,back.gap)/(back.sa/3.6)<=Rear.horizon(s,p) or abs(back.lat)>=K.defensePulledLat or back.index~=frame.player and (os.state=='OVT_IN' or os.state=='OVT_HOLD')
       if late and laps==0 and not upper and not s.defendLate then
        s.defendLate=true; e.stats.defenceLate=(e.stats.defenceLate or 0)+1
        U.log(e.log,now,'INFO',string.format('defense non lancee: %s, %s deja decale ou trop pres',a.name,frame.cars[back.index].name),i)
       end
      end
      -- Beta 1.61 (classNuance) : voiture à un tour, plus rapide, qui se dédouble : ce n'est pas une lutte pour la
      -- place, aucune défense ; une ligne au plus toutes les K.nuanceLogGap s.
      local unlap=p.classNuance and laps==0 and H.lapsAhead(a,frame.cars[back.index],back,frame.length)>0
      if unlap and (now>=(s.unlapLogAt or -math.huge) or (s.unlapLogAt or 0)-now>K.nuanceLogGap) then
       s.unlapLogAt=now+K.nuanceLogGap; e.stats.unlap=(e.stats.unlap or 0)+1
       U.log(e.log,now,'INFO',string.format('retardataire: %s se dedouble de %s (%+.0f km/h), sans defense',frame.cars[back.index].name,a.name,back.sa),i)
      end
      if not late and not unlap and laps==0 and not upper and (s.defendAttacker~=back.index or s.defendLap~=a.lap) then
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
     if not defend and H.towStart(e,s,a,back,row,p,profile,frame,now,startPhase or firstLap,braking,m,i,g) then defend=true end
     -- Affinage 1.62 : recherche de l'aspiration en ligne droite (H.slipSeek).
     if not defend and s.state=='DRIVE' then local sd=H.slipSeek(e,s,a,row,p,profile,frame,now,front,braking,ownBrake,startPhase or firstLap,i,g,m); if sd then desired=sd end
     elseif (s.seekFront or 0)~=0 then s.seekFront=0; s.seekAt=nil end
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
     local slowPlayer=front~=nil and profile~='C' and front.index==frame.player and H.playerSlow(e,s,frame.cars[front.index],a,p)
     -- Beta 1.59 : hors course, la file derrière une voiture lente compte aussi (voitures 2 à n de la file) ; derrière
     -- elle, le freinage d'AC pour garder l'écart ne retient plus le dépassement en ligne droite (radar inchangé).
     local slowAhead=front and (e.states[front.index].abnormal==true or slowPlayer or profile~='C' and queueSlow(e,frame,front))
     -- Beta 1.59 (journée circuit du 10 novembre : le pilote se range à gauche, l'IA derrière freine derrière lui au lieu
     -- de passer, aucune invitation notée) : hors course, joueur juste devant nettement écarté de la trajectoire en ligne
     -- droite (géométrie de l'invitation) : le freinage d'AC pour garder l'écart ne retient plus le dépassement.
     local playerAside=profile~='C' and front~=nil and front.index==frame.player and front.gap>=0 and front.gap<=K.inviteGap
      and abs(front.lat)>=K.inviteLat and H.inviteGeometry(profile,a,frame.cars[front.index],front)
     -- Relecture 1.59 : seulement si la voiture de devant cause ce freinage (proche, pas en train de s'éloigner) et loin
     -- d'un point de freinage appris.
     local passCorner=straightRules(profile) and K.passCornerC or p.cornerMin
     local slowFree=(slowAhead or playerAside) and profile~='C' and a.corner>=passCorner and front.gap<K.followRange and front.sa>=0
      and FirstLap.nextPoint(e.fl,a,frame.length)>max(a.speed,K.firstLapSpeedMin)*K.firstLapAnticipate
     local minPass=slowAhead and min(K.speedMinPass,K.slowPassRatio*frame.cars[front.index].kmh) or K.speedMinPass
     local canPass=not s.returning and not startPhase and not s.yellow and (not braking or slowFree) and now>=(s.cornerGiveUntil or 0) and s.lapseUntil<=now and p.overtakeEnabled and front and front.gap>=0 and now>=s.restUntil and directionBudget(s,now,p) and not s.zone.noOvertake and not s.zone.passWait and not s.hotspot and not s.alongside
      and a.kmh>=minPass and a.corner>=passCorner and ownBrake<K.passBrakeMax
     -- Beta 1.62 (qualifications, accord tacite de fin de tour) : deux voitures qui préparent leur tour (aucune lancée)
     -- ne se doublent pas dans les K.lapEndMeters derniers mètres avant la ligne ; un épisode compté une fois.
     -- Relecture 1.62 (S7) : seulement entre deux voitures en tour de sortie ; jamais derrière une voiture qui refroidit,
     -- rentre, est lente ou anormale.
     local qc=e.quali and e.quali.cars
     local lapEnd=canPass and profile=='Q' and e.quali and e.quali.active and not e.quali.push[i] and not e.quali.push[front.index]
      and qc and qc[i] and qc[i].out and qc[front.index] and qc[front.index].out and not qc[front.index].cool and not slowAhead
      and a.splineValid and (1-a.spline)*frame.length<K.lapEndMeters
     if lapEnd then canPass=false; if not s.lapEndHeld then s.lapEndHeld=true; e.stats.lapEndHold=(e.stats.lapEndHold or 0)+1 end else s.lapEndHeld=false end
     -- Beta 1.61 (classNuance) : trêve, tour tout juste pris, dédoublement hors ligne droite, classe lente au freinage.
     if canPass and p.classNuance and not passStates[s.state] and M.nuanceGate(e,s,a,front,p,profile,frame,now,i) then canPass=false; refused(e,s,front.index,'nuanceHold') end
     -- Lot 5 : voiture rattrapée à portée et dépassement interdit par l'état de la voiture : raison comptée.
     if not canPass and p.overtakeEnabled and front and front.gap>=0 and front.gap<=p.overtakeDetectAhead and front.sa>=p.overtakeAheadMargin and not passStates[s.state] and not defend and not s.returning then
      refused(e,s,front.index,s.yellow and 'flag' or startPhase and 'start' or (s.zone.noOvertake or s.hotspot) and 'zone' or not directionBudget(s,now,p) and 'budget'
       or (braking and not slowFree or ownBrake>=K.passBrakeMax or a.corner<passCorner) and 'corner' or 'other')
     end
     -- Beta 1.30 : joueur écarté juste devant (invitation) sans dépassement engagé au bout de K.inviteReport s : la raison
     -- au journal, une fois par épisode.
     local inviting=front and front.index==frame.player and front.long>0 and front.gap<=K.inviteGap and abs(front.lat)>=K.inviteLat and abs(front.lat)<=K.inviteLatMax
     if inviting and not passStates[s.state] and not defend then
      s.inviteWait=s.inviteWait+dt
      if s.inviteWait>=K.inviteReport and not s.inviteLogged then
       s.inviteLogged=true
       local why=s.yellow and 'drapeau jaune' or startPhase and 'depart' or s.returning and 'retour a la ligne' or (braking or ownBrake>=K.passBrakeMax) and 'freinage'
        or a.corner<passCorner and 'virage' or now<s.restUntil and 'repos apres manoeuvre' or not directionBudget(s,now,p) and 'plafond anti-zigzag'
        or s.alongside and 'voiture a cote' or a.kmh<minPass and 'trop lent' or not p.overtakeEnabled and 'depassements coupes' or s.zone.noOvertake and 'zone sans depassement' or s.zone.passWait and 'zone d attaque attendue' or s.hotspot and 'point difficile'
        or s.lapseUntil>now and 'inattention' or front.sa<=-K.inviteSa and 'joueur plus rapide'
        or not straightRules(profile) and abs(a.yawRate)*a.speed>K.inviteLatAccel and 'virage' or 'conditions de passage'
       U.log(e.log,now,'INFO',string.format('invitation du joueur non suivie: %s derriere a %.0f m (ecart lateral %.1f m, %+.0f km/h, lacet IA %.3f, joueur %.3f rad/s) : %s',
        a.name,front.gap,abs(front.lat),front.sa,abs(a.yawRate),abs(frame.cars[front.index].yawRate),why),i)
      end
     else s.inviteWait=0; s.inviteLogged=false end
     if canPass and not defend then
      local other=frame.cars[front.index]; local margin=p.overtakeAheadMargin*U.lerp(K.assertMin,K.assertMax,s.persona.assertiveness)*U.lerp(K.gapMarginMin,1,front.gap/K.passMarginRange)
      if faster(p,s,e.states[front.index]) then margin=margin*K.classMargin end
      margin=margin*(s.zone.passMargin or 1) -- Beta 1.61 : zone d'attaque (src/zones.lua), champ absent : neutre
      local slowClass=faster(p,e.states[front.index],s)
      local lapped=not C.solo(profile) and Classes.laps(a,other,front,frame.length)>0
      if p.classNuance and lapped and profile=='C' then margin=margin*K.unlapMargin end -- Beta 1.61 : dédoublement, marge plus large
      local leaderRow=e.perception.rows[front.index]; local ahead=leaderRow and leaderRow.front>0 and leaderRow.neighbors[leaderRow.front]
      local fight=lapped and ahead and other.speed>0 and ahead.gap/other.speed<K.fightTime and abs(ahead.sa)<K.fightSpeed or false
      local advantage=profile=='C' and K.passAdvantageC or K.passAdvantageJ
      local closing=front.gap<=p.overtakeDetectAhead and front.sa>=margin and front.ttc<=p.overtakeHorizon
      local trigger=closing
      local stuck=s.stuck>=p.stuckTime*s.persona.patience
      local otherState=e.states[front.index]
      -- Beta 1.41 : cible anormalement lente (dégâts) : dépassement sans rapprochement exigé (suivie à sa vitesse, l'IA
      -- ne gagnait jamais de terrain), avance et couloir jugés sur l'allure libre ; jamais ignorée.
      local slowTarget=(otherState.abnormal==true or profile~='C' and queueSlow(e,frame,front)) and front.gap<=p.overtakeDetectAhead
      -- Beta 1.41 : paire ignorée après un échec « cible plus rapide » ; vraie avance ici (allure libre).
      local ignored=front.index==s.passIgnore and now<s.passIgnoreUntil and not slowTarget and not (profile=='C' and leadLaps(a,other)>0)
       or front.index==s.lappedHold and now<(s.lappedHoldUntil or 0) and not slowTarget
      -- Beta 1.60 (même séance) : hors course, l'attente ne tient plus quand la cible est de nouveau nettement rattrapée
      -- (K.passReopenSa km/h de plus qu'elle, K.passReopenWait s au moins après l'échec) : la tentative est rejugée
      -- comme une autre (avance, couloir, plafonds) ; une ligne au plus toutes les K.passReopenWait s.
      -- Relecture : une seule réouverture par attente (s.passReopened, remis à zéro avec le compte des échecs) : la
      -- réouverture tient K.passReopenHold s (le temps de juger et d'engager la tentative), puis l'attente reprend ;
      -- la cible oublie aussi son refus de céder à cette voiture (sinon elle ne s'écarte pas pour la tentative).
      -- Beta 1.60 (lot 4, course du Red Bull Ring : cinq attentes de 180 s) : en course aussi, K.passReopenWaitRace s
      -- au moins après l'échec (les boucles des 1.47 et 1.54 tournaient à moins de 15 s d'intervalle).
      if ignored and s.passIgnoreAt~=nil and now-s.passIgnoreAt>=(profile=='C' and K.passReopenWaitRace or K.passReopenWait)
       and (s.passReopened==nil and front.sa>=K.passReopenSa or s.passReopened~=nil and now-s.passReopened<=K.passReopenHold) then
       ignored=false
       if s.passReopened==nil then
        s.passReopened=now; e.stats.passReopen=(e.stats.passReopen or 0)+1
        if otherState.yieldIgnore==i then otherState.yieldIgnore=0; otherState.yieldIgnoreUntil=0 end
        U.log(e.log,now,'INFO',string.format('depassement rejuge: %s -> %s (cible de nouveau rattrapee, %.0f m, %+.0f km/h)',a.name,frame.cars[front.index].name,front.gap,front.sa),i)
       end
      end
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
      -- Beta 1.59 (journée circuit du 10 novembre : 70 cessions, 2 abouties, les suiveurs au même rythme n'attaquaient pas) :
      -- hors course, toute cession qui aurait été accordée à cette IA (H.yieldRefused) est attaquée.
      -- Relecture 1.62 (boucle 1.54 rouverte en journée circuit multi-classes) : une paire en attente n'est plus rouverte par
      -- une cession de classe (classes déduites de l'allure) : seulement par un vrai drapeau bleu (tour) ou un tour lancé.
      local yieldingToMe=(otherState.state=='YIELD_IN' or otherState.state=='YIELD_HOLD') and otherState.target==i and (not ignored or otherState.yieldBlue and not otherState.yieldClass) and front.sa>=-K.cessionSaMin
       and (otherState.yieldBlue or profile~='C' and not H.yieldRefused(e,s,otherState,a,p,profile) or adv==true or adv==nil and front.sa>=advantage)
      local invited=yieldingToMe or front.index==frame.player and abs(front.lat)>=K.inviteLat and front.gap<=K.inviteGap and front.sa>-K.inviteSa
       and H.inviteGeometry(profile,a,other,front) and not busy(frame,front.index,i)
      s.invited=invited and s.invited+dt or 0
      -- Beta 1.60 (lot 3, passage franc) : cible qui lui cède et déjà sortie de la trajectoire : aucun délai.
      local frank=yieldingToMe and frankYield(e,frame,i,front.index,profile,g,front)
      if frank then s.invited=max(s.invited,K.inviteTime) end
      invited=s.invited>=K.inviteTime
      trigger=trigger or invited
      -- Beta 1.47 (boucles : jusqu'à 13 tentatives par paire en 10 min) : paire ignorée après un échec « cible plus rapide »,
      -- plus de dépassement sur simple rapprochement sans vraie avance ici (la retenue et la cession l'étaient déjà).
      -- Beta 1.54 : dès K.passIgnoreStrict échecs sur cette cible, l'avance apprise ne suffit plus (elle s'était trompée).
      if ignored and (adv~=true or s.passIgnoreCount>=K.passIgnoreStrict) and not (stuckTrigger or slowTarget or invited) then if trigger then refused(e,s,front.index,'suspended') end; trigger=false end
      -- Beta 1.51 (qualifications) : IA pas lancée (tour de sortie, refroidissement) : jamais à l'attaque d'une voiture
      -- lancée devant elle, sauf invitation ou voiture anormalement lente.
      -- Beta 1.52 : refus compté une fois par cible, seulement quand un dépassement aurait été tenté (avance suffisante,
      -- ni classe plus lente ni bagarre devant) ; oublié dès que la garde ne s'applique plus.
      local qualiHold=qualiGuard(e,i,front.index) and not slowTarget and not invited
      if not qualiHold then s.qualiHeldFor=nil end
      if trigger and qualiHold then
       trigger=false
       if potential>=advantage and not slowClass and not fight and s.qualiHeldFor~=front.index then s.qualiHeldFor=front.index; e.stats.qualiNoPass=(e.stats.qualiNoPass or 0)+1 end
      end
      -- Beta 1.29 : hors course, pas de riposte sur le joueur qui vient de la doubler, sauf s'il ralentit nettement.
      if passedByPlayer and front.index==frame.player and not invited and front.sa<K.courtesyPassSa and not slowPlayer then trigger=false end
      if trigger and not (potential>=advantage or invited) then refused(e,s,front.index,'advantage') end
      if trigger and (potential>=advantage or invited) and not slowClass and not fight then
       if s.passCandidate~=front.index then s.passCandidate=front.index; s.passConfirm=0 end
       -- Beta 1.31 (journaux du 2 novembre : 12 tentatives sur 14 abandonnées, la cible repartant plus vite) : engagé sur
       -- un seul rapprochement, le dépassement attend que l'IA ait vraiment gagné K.passCloseMin m sur la cible (terrain
       -- gagné suivi en continu) ; un écart de vitesse passager (sortie de virage, freinage plus tôt) ne suffit plus.
       local closingOnly=closing and not stuckTrigger and not invited and not slowTarget
       s.passConfirm=s.passConfirm+dt; s.passLost=0
       -- Relecture 1.62 (M2) : cible qui garde sa ligne (« line ») : son décalage ne dit rien du côté ; côté choisi par
       -- passSide (place au-delà d'elle) et contrôle de place maintenu.
       local lineTarget=yieldingToMe and otherState.yieldLine==true
       local side=invited and not lineTarget and (front.lat>0 and 1 or -1) or passSide(p,profile,s,front,row,other,g,a)
       -- Beta 1.41 : cible anormalement lente (zone morte) : écart de vitesse du dépassement = allure libre moins la
       -- vitesse de la cible (suivie à sa vitesse, l'écart du moment, nul, exigeait le couloir le plus long) ; ailleurs,
       -- l'écart du moment, comme avant (relecture).
       local closingSpeed=max(a.speed-other.speed,slowTarget and free-other.speed or 0,K.corridorSpeedMin)
       local req=U.clamp((front.gap+a.length+other.length+2*p.overtakeClearMargin)*a.speed/closingSpeed,K.corridorMin,K.corridorMax)
       -- Beta 1.61 (classNuance) : classe rapide derrière un amateur (style, Beta 1.60) : couloir libre exigé plus long.
       if p.classNuance and faster(p,s,otherState) and (otherState.persona.style or 0)>=K.classAmStyle then req=min(K.corridorMax*K.classAmCorridor,req*K.classAmCorridor) end
       if p.overtakeSide=='auto' and yieldStates[otherState.state] and not otherState.yieldLine and sideFree(row,-otherState.targetSide) then side=-otherState.targetSide end
       -- Beta 1.60 (lot 3) : cible qui lui cède : toujours du côté opposé à celui où elle s'écarte (avant : chacune
       -- choisissait « le côté qui a de la place », parfois le même).
       -- Le côté de dépassement réglé est une préférence (comme le côté de cession) : jamais du côté où la cible s'écarte.
       if (frank or yieldingToMe) and not otherState.yieldLine and sideFree(row,-otherState.targetSide) then side=-otherState.targetSide end
       -- Beta 1.60 (relecture) : la place se juge sur le côté réellement pris (avant : sur le meilleur côté, alors que
       -- hors course le côté est l'opposé du côté de cession réglé, souvent le bord de la piste). Côté sans
       -- K.passMinRoom m alors que l'autre en a et est libre : l'autre côté ; aucun côté : pas de tentative. Jamais
       -- pour l'invitation du joueur (son côté libéré) ni une voiture lente ; largeurs inconnues : rien ne change.
       local roomOk=true
       if not invited or lineTarget then
        local here,there=sideRoom(s,a,p,g,side),sideRoom(s,a,p,g,-side)
        if here~=nil then
         local need=K.passMinRoom/(yieldingToMe and 2 or 1)
         -- Lot 5 : aucun côté n'a la place maintenant : le côté qui l'aura 2 s plus loin (la trajectoire traverse la
         -- piste), s'il est libre et si la ligne droite laisse le temps d'arriver à hauteur (prochain point de freinage
         -- appris ; Monaco : jamais de tentative sans issue). Sinon la règle d'avant.
         if here<need and there<need then
          local sh,st=M.roomSoon(s,a,p,side*g.offsetSign>0),M.roomSoon(s,a,p,-side*g.offsetSign>0)
          local pick=sh>=need and side or st>=need and sideFree(row,-side) and not (yieldStates[otherState.state] and otherState.targetSide==-side) and -side or 0
          -- Finition 1.61 (relecture) : aucun point de freinage connu : la garde de ligne droite ne peut pas juger ;
          -- règle d'avant (pas de départ du côté qui s'ouvre).
          local np=FirstLap.nextPoint(e.fl,a,frame.length)
          if pick~=0 and np<math.huge then
           if np/max(a.speed,1)>=(front.gap+a.length)/closingSpeed*K.passSoonShare then
            side=pick; here=need; there=0
            if s.soonRoomFor~=front.index then s.soonRoomFor=front.index; e.stats.passSoonRoom=(e.stats.passSoonRoom or 0)+1 end
           else refused(e,s,front.index,'short') end
          end
         end
         if here<need and there>=need and sideFree(row,-side) and not (yieldStates[otherState.state] and otherState.targetSide==-side) then side=-side; here=there; refused(e,s,front.index,'sideRoom') end
         if here<need and not slowTarget then
          roomOk=false; refused(e,s,front.index,'room')
          if s.noRoomFor~=front.index then s.noRoomFor=front.index; e.stats.passNoRoom=(e.stats.passNoRoom or 0)+1 end
         end
        end
       end
       -- Passage franc : la cible a libéré la trajectoire, aucun décalage n'est exigé de l'attaquant.
       if not lineTarget and (frank or yieldingToMe and side==-otherState.targetSide) then roomOk=true end
       local yieldingSame=yieldStates[otherState.state] and otherState.targetSide==side
       -- Beta 1.47 : premier tour attentif : dépassement seulement en vraie ligne droite, hors freinage (le sien, celui de
       -- la cible, ou un point de freinage proche), avec une vraie avance et un couloir plus long ; invitation permise.
       local flHeld=firstLap and not invited and H.firstLapHeld(s,a,other,otherState,ownBrake,potential,advantage)
       if firstLap then req=req*K.firstLapCorridor end
       if flHeld and s.passConfirm>=p.confirmTime then refused(e,s,front.index,'firstlap') end
       if flHeld and s.passConfirm>=p.confirmTime and s.flPassHeldFor~=front.index then s.flPassHeldFor=front.index; e.stats.flPass=(e.stats.flPass or 0)+1 end
       -- Lot 5 : mêmes conditions qu'avant, dans le même ordre ; celle qui retient un départ confirmé est comptée.
       s.passGo=not flHeld and (frank or s.passConfirm>=p.confirmTime) and roomOk
       if s.passGo and not (not closingOnly or s.closeMeters>=(ignored and K.passCloseMin*K.passIgnoreCloseMult or K.passCloseMin)) then s.passGo=false; refused(e,s,front.index,'closing') end
       if s.passGo and not (sideFree(row,side) and not yieldingSame) then s.passGo=false; refused(e,s,front.index,'side') end
       if s.passGo and not P.corridor(frame.cars,frame.count,i,side,req,front.index,g.occLatMax,profile~='C' and (invited or slowTarget or playerAside) and a.speed-K.corridorLeadMargin or nil) then s.passGo=false; refused(e,s,front.index,'corridor') end
       if s.passGo then
        if s.refSeen then for key in pairs(s.refSeen) do s.refSeen[key]=nil end end
        s.target=front.index; s.targetSide=side; s.clear=0; s.abortSlow=0; s.passBlocked=0; s.passStall=0; s.passAlongside=false
        s.passConfirm=0; s.passCandidate=0
        if invited then s.ignoreTarget=front.index; s.ignoreUntil=now+K.inviteRespite end
        -- Beta 1.31 : chaque tentative au journal (déclencheur, écart, avance), et sa fin à la sortie des états de passage.
        U.log(e.log,now,'INFO',string.format('depassement: %s -> %s (%s, %.0f m, %+.0f km/h)',a.name,other.name,yieldingToMe and 'cession' or invited and 'invitation' or slowTarget and 'cible lente' or closingOnly and 'rapprochement' or 'retenue',front.gap,front.sa),i)
        s.passStartAt=now; s.passGap0=front.gap; s.passMinGap=front.gap; s.passMinTg=nil; s.passTg=0; s.passPrevV=nil; s.passName=other.name; s.lastPassTarget=front.index; s.lastPassAt=now
        s.passProgRef=front.gap; s.passProgTime=0
        s.passBrakeFree=slowFree
        if slowTarget then e.stats.slowPass=(e.stats.slowPass or 0)+1; if not otherState.abnormal then e.stats.queuePass=(e.stats.queuePass or 0)+1 end end
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
 -- Beta 1.52 : cession pas jugée à cette image (jaune, neutralisation, freinage, inattention, voiture à côté, évitement,
 -- reprise au calme, attente du départ, cession en cours) : le drapeau bleu en attente (virage) ne tient plus le niveau
 -- abaissé ni ne coupe l'urgence et l'aspiration cassée.
 if not yieldEvaluated then s.bluePending=false end
 if a.corner<K.passCornerC then s.defendUsed=false; s.defendLate=false end
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
 local launch=starting and s.startCare<K.launchCare
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
 if not following or not p.slipstreamEnabled or (a.cornerYaw or a.corner)<K.slipCorner or a.kmh<=K.slipSpeed then s.slipTime=0 end
 -- Affinage 1.61 (essais à Spa du 11 novembre, lignes « suivi du depassement » : attaquant sans aucune limite de l'app
 -- mais prudence 2,0 à 3,5, collé à 7–14 m derrière une cible déjà écartée de 1,4 à 2,7 m pendant 25 s) : la prudence
 -- de suivi et la zone de freinage émulée du rapprochement visaient la cible comme une voiture dans sa trajectoire.
 -- Attaquant décalé d'au moins K.passFreeLat m de sa cible : prudence plafonnée après toutes les règles de la ligne
 -- droite (plus bas) ; le radar et la sécurité au freinage et en virage restent.
 local passFree=H.passFreeOf(s,row,front)
 if passFree then e.stats.passFree=(e.stats.passFree or 0)+dt end
 if following then
  -- Beta 1.50 : en ligne droite du départ et du premier tour, ni prudence de suivi (aspiration, voiture collée).
  if not launch and not straightRun and not passFree then
   caution=caution*U.lerp(K.followCaution,1,(front.gap-K.followMinGap)/K.followGapRange)*s.persona.brakeMargin
   if front.ttc<K.followTTC then caution=caution*K.followTTCMult end
  end
  if p.slipstreamEnabled and (a.cornerYaw or a.corner)>=K.slipCorner and a.kmh>K.slipSpeed then s.slipTime=s.slipTime+dt; if s.slipTime>K.slipTime then caution=min(caution,max(K.slipCautionMin,caution*K.slipCaution)) end else s.slipTime=0 end
  if profile=='C' and front.index==frame.player and front.gap<K.playerFollowGap then caution=caution*K.playerCaution end
 end
 -- Relecture 1.62 (S1) : plafond de l'attaquant décalé appliqué ici, avant les règles de sécurité (radar, intention de la
 -- file, départ, côte à côte, sortie des stands, freinage, usure) : elles ne sont plus annulées.
 -- Affinage 1.62 (12 novembre) : hors du sillage de sa cible, ni air sale (accélérateur entier).
 if passFree then caution=min(caution,K.passFreeCaution); s.dirty=0 end
 -- Beta 1.47 : premier tour attentif : écart en temps (même effet en F1, en GT ou en voiture de route) hors lancement,
 -- et anticipation de chaque freinage du tour (points appris en direct, freinage de la voiture de devant) avec une
 -- voiture à moins de K.firstLapGapTime s devant ; prudence seulement, jamais de frein ni de limite de vitesse.
 -- Beta 1.59 (MJFox : IA presque arrêtées dans les virages lents) : freinage de la voiture de devant compté seulement s'il
 -- est libre (elle-même sans voiture à moins de K.firstLapPointFree s devant) ; un freinage de suivi d'AC dans le peloton
 -- n'est plus une anticipation (258 en 37 s le 10 novembre).
 s.flFree=not front or front.long<=0 or front.gap<0 or FirstLap.headway(front.gap,a.speed)>=K.firstLapPointFree
 if firstLap then
  local close=front~=nil and front.long>0 and front.gap>=0 and FirstLap.headway(front.gap,a.speed)<K.firstLapGapTime
  local approach=false
  if close then
   local fb=frame.cars[front.index].brake; local fs=e.states[front.index]
   approach=FirstLap.nextPoint(e.fl,a,frame.length)<=max(a.speed,K.firstLapSpeedMin)*K.firstLapAnticipate or fs.flFree~=false and fb>(fs.appBrake or 0)+K.brakeEcho and fb>K.ruleBrake
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
 -- Beta 1.60 (relecture) : cible du radar gardée pour le régulateur (src/rear.lua) : temps avant contact, écart de
 -- vitesse et voiture visée (la cible du radar, pas la voiture « devant » de la perception).
 s.radarTTC=math.huge; s.radarSa=0; s.radarIndex=0
 if g.useBrakeAssist then
  local close,closeTTC=nil,math.huge
  -- Beta 1.59 (journée circuit du 10 novembre : le pilote se range à gauche, l'IA derrière freine fort au lieu de
  -- passer) : hors course, voiture devant qui s'écarte latéralement et sera hors de la file au moment du contact
  -- (écart latéral de l'image précédente, K.radarClearMargin m de marge) : pas de freinage ; recouvrement réel inchangé.
  -- Relecture 1.59 : seulement en ligne droite, dans le même sens, pour une voiture qui ne tourne pas (entrée de virage,
  -- tête-à-queue : K.inviteLatAccel) ni en incident, avec une vraie vitesse latérale (K.radarOpenRate m/s, lissée sur
  -- K.radarLatTau s : jamais sur une seule image).
  local latPrev,latAt,latRate,latOpen=s.radarLatPrev,s.radarLatAt,s.radarLatRate,s.radarLatOpen
  if not latPrev then latPrev={}; latAt={}; latRate={}; latOpen={}; s.radarLatPrev=latPrev; s.radarLatAt=latAt; s.radarLatRate=latRate; s.radarLatOpen=latOpen end
  -- Lot 5 (coût par image) : facteur du lissage calculé une fois par voiture (avant : une exponentielle par voisin et
  -- par image) ; même arithmétique que U.ema, résultats identiques au bit près.
  local trackLat=profile~='C' -- Beta 1.61 : une seule garde (hors course) pour le suivi latéral et l'exemption.
  local latK=trackLat and dt>0 and 1-math.exp(-dt/max(0.001,K.radarLatTau)) or 0
  for j=1,row.count do
   local r=row.neighbors[j]; local other=frame.cars[r.index]
   -- Écart latéral de l'image (la perception n'est rafraîchie que toutes les K.perceptionPeriod s).
   -- Beta 1.60 (coût par image) : écart latéral suivi hors course seulement ; en course, l'exemption ci-dessous ne
   -- sert jamais (profile~='C') et le suivi était calculé pour rien, pour chaque voisin, à chaque image.
   local lat,before,rate,held=0,nil,0,0
   if trackLat then
    lat=abs((other.x-a.x)*(-a.lz)+(other.z-a.z)*a.lx); before=latAt[r.index]==s.radarLatFrame and latPrev[r.index] or nil
    if before~=nil and dt>0 then local was=latRate[r.index] or 0; rate=was+((lat-before)/dt-was)*latK end
    -- Écartement tenu K.radarOpenHold s d'affilée (une image de bruit ne suffit pas).
    held=rate>=K.radarOpenRate and (latOpen[r.index] or 0)+dt or 0
    latPrev[r.index]=lat; latAt[r.index]=now; latRate[r.index]=rate; latOpen[r.index]=held
   end
   local reach=(a.width+other.width)*0.5+K.radarLatMargin
   if r.long>0 and r.sa/3.6>K.brakeClosing and abs(r.lat)<=reach then
    local ttc=max(0,r.gap)/(r.sa/3.6)
    local oi=e.incidents.cars[r.index]
    local opening=before~=nil and r.same and a.corner>=p.cornerMin and held>=K.radarOpenHold
     and abs(other.yawRate or 0)*other.speed<=K.inviteLatAccel and not (oi and oi.incident) and lat+rate*ttc>reach+K.radarClearMargin
    if not opening and ttc<closeTTC then close=r; closeTTC=ttc end
   end
  end
  s.radarLatFrame=now
  if close then s.radarTTC=closeTTC; s.radarSa=close.sa; s.radarIndex=close.index end
  if close then
   -- Relecture 1.62 (S1) : avertissement visant la cible déjà écartée de l'attaquant : couvert par son plafond ; toute
   -- autre voiture garde l'avertissement.
   if closeTTC<K.radarWarnTTC and not launch and not straightRun and not (passFree and close.index==s.target) then caution=caution*U.lerp(K.radarCaution,1,closeTTC/K.radarWarnTTC) end
   -- Affinage 1.62 : envol manqué devant : réaction au seuil ordinaire (K.radarTTC), pas à celui du lancement.
   if closeTTC<(launch and not H.bogging(e,close.index,now) and K.radarLaunchTTC or K.radarTTC) then
    radarTarget=U.clamp(close.sa/3.6/K.brakeGain,K.radarMinBrake,K.radarBrakeMax)
    -- Beta 1.47 : départ, avant le premier freinage : freinage plafonné à K.radarStartBrakeMax ; voiture collée derrière
    -- (voir K.radarStartFollowTime et K.radarStartFollowMin ci-dessous) : lever de pied seulement, sans frein (un coup de frein en pleine ligne droite
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
    -- Affinage 1.62 : derrière un envol manqué, jamais de pied tenu (levée dosée, plus bas).
    local pushed=back~=nil and back.long<0 and back.ttc<closeTTC and not (starting and H.bogging(e,close.index,now))
    if straightGeom and pushed and close.sa<K.radarStraightObstacleKmh then straightHold=true; radarTarget=0; H.straightHoldCount(e,s,now,true)
    elseif straightRun and close.sa<K.radarStraightObstacleKmh and closeTTC>=K.firstLapLastTTC and not (starting and H.bogging(e,close.index,now)) then
     local lane=(not row.left or not row.right) and (a.leftWidth or 0)+(a.rightWidth or 0)>=K.radarLaneWidth
     if closeTTC>=K.radarStraightTTC or lane then straightHold=true; radarTarget=0; H.straightHoldCount(e,s,now,false)
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
     -- Beta 1.59 : dans le peloton (rapprochement sous K.radarStraightObstacleKmh km/h), levée dosée selon le temps au
     -- contact, comme en ligne droite (30 % d'accélérateur d'un coup en virage : accordéon de 9 voitures le 10 novembre) ;
     -- vrai obstacle (rapprochement plus rapide) : levée franche, comme avant.
     local liftTo=close.sa<K.radarStraightObstacleKmh and U.lerp(K.radarStartLift,1,U.clamp(closeTTC/K.radarTTC,0,1)) or K.radarStartLift
     if closeTTC>=K.firstLapBrakeTTC or (followed or ownBrake<=K.ruleBrake) and closeTTC>=K.firstLapLastTTC then radarTarget=0; lift=true; cmd.throttleLimit=min(cmd.throttleLimit or 1,liftTo)
     elseif closeTTC>=K.firstLapLastTTC then radarTarget=min(radarTarget,K.radarStartBrakeMax) end
     if not lift and s.radarBrake==0 then e.stats.flBrake=(e.stats.flBrake or 0)+1 end
    end
    if launch and s.radarBrake==0 and not lift and not straightHold then e.startRadar=(e.startRadar or 0)+1 end
    -- Levers de pied du départ comptés (au plus un par voiture et par seconde) pour le bilan du journal.
    if lift and (now>=(s.startLiftAt or -math.huge) or s.startLiftAt-now>1) then s.startLiftAt=now+1; e.startLift=(e.startLift or 0)+1; if firstLap then e.stats.flLift=(e.stats.flLift or 0)+1 end end
    if not straightHold and s.radarBrake==0 and (now>=s.radarLogAt or s.radarLogAt-now>K.radarLogPeriod) then
     s.radarLogAt=now+K.radarLogPeriod
     -- Raison d'une levée de pied ou d'un frein du départ et du premier tour, dite au journal (audit des départs réels).
     -- Beta 1.52 : calculée seulement quand la ligne est écrite.
     local why150=not (starting or firstLap) and '' or not straightGeom and ((starting and s.startAhead or npNear) and 'anticipation du freinage' or 'courbe')
      or close.sa>=K.radarStraightObstacleKmh and 'approche rapide' or closeTTC<K.firstLapLastTTC and string.format('contact %.1f s, dernier recours',closeTTC)
      or string.format('contact %.1f s, aucun couloir libre',closeTTC)
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
  if s.state~='AVOID' then desired=p.startLaneHold and H.laneHold(e,s,a,row,g,frame,now,i) or 0 end
 elseif s.lane~=0 or s.laneActive then s.lane=0; s.laneActive=false
 end
 -- Beta 1.47 : premier tour attentif : agressivité au plus K.firstLapAggr de la base.
 if firstLap then aggression=min(aggression,U.lerp(aggression,s.baseAggression*K.firstLapAggr,s.flW)) end
 local allowLapse=p.lapseEnabled and not s.alongside and s.state~='DEFEND' and s.state~='YIELD_IN' and s.state~='IDLE' and s.state~='CALM'
 s.fatigue=p.enduranceOverlay and now-s.lastContact>K.fatigueTime and K.fatigueGain or 1
 -- Beta 1.60 (bus des modificateurs) : fatigue de l'humeur (src/mood.lua), jamais sous la fatigue existante.
 s.fatigue=max(s.fatigue,s.moodFatigue or 1)
 -- Beta 1.60 (pour tous, sans réglage) : aucune inattention ne commence avec une voiture collée derrière (src/rear.lua).
 -- Beta 1.62 (décision 8 du pilote) : aucune inattention ne commence en virage, au freinage, ni devant une voiture
 -- lancée qui arrive (essais, qualifications).
 -- Beta 1.62 (fusion, décision 8 complétée) : ni à K.lapseBrakeTime s d'un point de freinage connu, ni devant une
 -- voiture nettement plus rapide (K.lapseFastKmh) à moins de K.lapseRearTime s derrière. Relecture 1.62 (S10) : jugés
 -- seulement quand une inattention pourrait commencer (aucun coût à chaque image sinon).
 if now>=s.lapseAt and allowLapse and not s.rearClose and a.corner>=p.cornerMin and ownBrake<=K.ruleBrake
  and not (back~=nil and e.quali and e.quali.active and e.quali.push[back.index] and back.long<0 and back.gap<=max(frame.cars[back.index].speed,1)*K.qualiYieldLead)
  and not (FirstLap.nextPoint(e.fl,a,frame.length)<=max(a.speed,K.firstLapSpeedMin)*K.lapseBrakeTime)
  and not (back~=nil and back.long<0 and back.sa>=K.lapseFastKmh and back.gap<=max(frame.cars[back.index].speed,1)*K.lapseRearTime) then
  s.lapseCount=(s.lapseCount+1)%K.counterMax; Persona.nextLapse(s.persona,g.seed,i,s.lapseCount,p)
  s.lapseUntil=now+s.persona.lapseDuration; s.lapseAt=now+s.persona.lapseInterval/min(K.fatigueMax,s.fatigue)
 end
 if s.lapseUntil>now and allowLapse then
  local ramp=min((s.persona.lapseDuration-(s.lapseUntil-now))/K.lapseRamp,(s.lapseUntil-now)/K.lapseRamp,1)
  if a.corner>=p.cornerMin and ownBrake<=K.ruleBrake then level=level*(1-s.persona.lapseDrop*max(0,ramp)) end -- Beta 1.62 : jamais en virage ni au freinage
 elseif s.lapseUntil<=now then s.lapseUntil=0 end
 -- Beta 1.62 (« sans freiner sur la trajectoire ») : drapeau bleu en attente : léger lever de pied en ligne droite
 -- seulement, jamais dans le virage ni au freinage.
 if s.bluePending and a.corner>=p.cornerMin and ownBrake<=K.ruleBrake then level=level*K.lapCornerLevel end
 if s.alongside and s.state~='AVOID' then aggression=p.section_general and p.aggressionPct/100*K.maxAggression or a.baseAggression or a.aiAggression; desired=s.offset; if passStates[s.state] then caution=caution*K.alongsideCaution end end
 -- Beta 1.62 (journée circuit : « ne jamais coller ») : IA qui ne double pas, à moins de K.jFollowTime s derrière la
 -- voiture de devant : prudence × K.jFollowCaution, l'écart se rouvre au lieu de rester au pare-chocs.
 if profile=='J' and front and front.long>0 and front.gap>=0 and not passStates[s.state] and front.gap<max(a.speed,1)*K.jFollowTime then caution=caution*K.jFollowCaution end
 -- Sortie des stands : prudence accrue derrière une voiture proche (joueur compris).
 local pitGuard=now<s.pitGuardUntil and front and front.gap<K.pitGuardGap
 if pitGuard then caution=caution*K.pitGuardCaution end
 if a.brake>K.brakeEmulationPedal or not passFree and front and front.gap<K.brakeEmulationRange and front.sa/3.6>K.brakeEmulationClosing then
  -- Beta 1.60 (bus des modificateurs) : freinages plus prudents sur pneus usés (src/wear.lua), ici seulement.
  caution=caution*(1+K.brakeEmulationGain*(p.brakeZonePct-100)/100)*s.persona.brakeMargin*(s.wearBrake or 1)
 end
 -- Beta 1.60 (réglage rearAwareness) : intention de la file : la voiture devant celle de devant freine, en ligne droite
 -- (hors premier tour attentif, qui a sa règle) : prudence relevée tôt.
 if p.rearAwareness and front and not firstLap and a.corner>=p.cornerMin and front.gap<K.followRange then
  local fr=e.perception.rows[front.index]; local second=fr.front>0 and fr.neighbors[fr.front] or nil
  local c2=second and second.gap<K.followRange and frame.cars[second.index] or nil
  if c2 and c2.valid and (c2.brake or 0)>K.ruleBrake and c2.speed<a.speed then caution=caution*K.intentCaution end
 end
 -- Beta 1.60 (réglage passAid) : fin de l'engagement avec la tentative (ou changement de cible) ; la voiture qui tient
 -- sa ligne ne répond pas à l'accélérateur (agressivité au plus de base).
 if (s.committed or 0)>0 and not ((s.state=='OVT_IN' or s.state=='OVT_HOLD') and s.committed==s.target) then Priority.release(e,i); s.aidLogged=0 end
 if heldBy>0 then aggression=min(aggression,s.baseAggression) end
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
  -- Beta 1.52 : IA pas lancée : jamais d'appel de phares à une voiture lancée devant elle (essais et qualifications).
  if allowed and qualiGuard(e,i,front.index) then allowed=false end
  -- Beta 1.54 : hors course, jamais d'appel de phares vers une cible ignorée après un échec « cible plus rapide » (elle
  -- ne lui cède plus pendant ce temps : 33 appels en 6 min à la Nordschleife le 9 novembre).
  if allowed and profile~='C' and front.index==s.passIgnore and now<s.passIgnoreUntil then allowed=false end
  -- Beta 1.55 : hors course, pas d'appel vers une voiture qui a cédé K.flashFailLimit fois sans passage, ni juste après
  -- un abandon « suiveur rapide » ou « cède à son suiveur » sur elle.
  if allowed and profile~='C' and (front.index==s.flashMute and now<s.flashMuteUntil or front.index==s.flashHoldTarget and now<s.flashHoldUntil) then allowed=false end
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
 -- Beta 1.59 (19i, règle de course du pilote, tous profils) : à l'entrée d'un virage (freinage ou virage), côte à côte
 -- avec une voiture (joueur compris) dont le nez est devant le sien de plus de K.cornerNoseMargin m : pas de priorité.
 -- L'IA lève le pied (K.cornerGiveLift), quitte son dépassement ou sa défense, garde son écart latéral (jamais vers
 -- l'autre, règle existante) et ne relance pas d'attaque pendant K.cornerGiveHold s ; une ligne par épisode. Nez devant
 -- ou à égalité : elle garde sa ligne. Jamais au lancement ; l'engagement sur une cession (1.59) ne passe jamais avant.
 -- Décidé à l'entrée seulement (K.cornerEntryWindow s après le début du freinage ou du virage) puis tenu tant que les
 -- deux voitures restent côte à côte : un dépassement déjà engagé dans un long virage n'est pas coupé en son milieu.
 -- Relecture 1.59 : virage ou vrai freinage seulement (K.passBrakeMax : le freinage d'AC pour garder l'écart en ligne
 -- droite n'ouvre pas d'épisode) ; épisode clos après K.cornerPhaseGap s sans virage ; une ligne et un compte par épisode.
 -- Beta 1.60 (course à Bakou : deux voitures se cédaient à tour de rôle, et la règle tournait en file derrière la
 -- voiture de sécurité) : jamais sous drapeau jaune, neutralisation ou drapeau rouge ; jamais envers une voiture qui
 -- cède déjà à celle-ci (plus bas).
 local entering=not launch and s.state~='CALM' and not s.yellow and not e.incidents.neutral and not e.incidents.red and (a.corner<p.cornerMin or ownBrake>=K.passBrakeMax)
 s.cornerOut=entering and 0 or (s.cornerOut or 0)+dt
 -- Seulement entre voitures arrivées côte à côte : déjà à la hauteur l'une de l'autre au début du virage.
 if entering and not s.cornerPhase then
  s.cornerPhase=true; s.cornerCounted=false; s.cornerEntryAt=now; s.cornerPair=s.cornerPair or {}
  for k in pairs(s.cornerPair) do s.cornerPair[k]=nil end
  for j=1,row.count do local r=row.neighbors[j]; if r.alongside then s.cornerPair[r.index]=true end end
 elseif not entering and s.cornerOut>K.cornerPhaseGap then s.cornerPhase=false end
 local giveTo=0
 if entering then
  for j=1,row.count do
   local r=row.neighbors[j]; local other=frame.cars[r.index]
   local held=s.cornerGiveTo==r.index or s.cornerPair[r.index] and now-s.cornerEntryAt<=K.cornerEntryWindow
   -- Vraiment côte à côte : décalées d'au moins K.nearLine m (une voiture juste devant, pare-chocs contre pare-chocs,
   -- n'est pas à côté).
   if held and e.states[r.index].cornerGiveTo~=i and r.same and r.alongside and abs(r.lat)>=K.nearLine and abs(r.lat)<=g.occLatMax and r.long+(other.length-a.length)*0.5>K.cornerNoseMargin then giveTo=r.index; break end
  end
 end
 if giveTo>0 then
  -- Le dépassement n'est quitté que si la voiture prioritaire est sa cible (une autre voiture à côté : lever de pied et
  -- écart tenu seulement ; la cible, plus loin devant, n'est pas en cause).
  if passStates[s.state] and s.state~='OVT_OUT' and giveTo==s.target then transition(e,s,'OVT_OUT','corner_priority',now); desired=s.offset
  elseif passStates[s.state] and s.state~='OVT_OUT' then desired=s.offset
  elseif s.state=='DEFEND' then transition(e,s,'DRIVE','corner_priority',now); desired=s.offset end
  -- Lever de pied seulement sans voiture à moins de K.cornerGiveBackGap m derrière (jamais de coupure devant elle).
  s.cornerGiveUntil=now+K.cornerGiveHold
  if s.cornerGiveTo~=giveTo then
   s.cornerGiveTo=giveTo
   if not s.cornerCounted then
    s.cornerCounted=true; e.stats.cornerGive=(e.stats.cornerGive or 0)+1
    U.log(e.log,now,'INFO',string.format('priorite au virage: %s cede a %s (nez derriere)',a.name,frame.cars[giveTo].name),i)
   end
  end
 else s.cornerGiveTo=0 end
 -- Lever de pied progressif (K.cornerLiftRate par seconde, à l'aller comme au retour), jamais avec une voiture à moins
 -- de K.cornerGiveBackGap m derrière (jamais de coupure devant elle).
 local liftTo=giveTo>0 and not (back and back.gap<K.cornerGiveBackGap) and K.cornerGiveLift or 1
 s.cornerLift=U.approach(s.cornerLift or 1,liftTo,K.cornerLiftRate*dt)
 if s.cornerLift<1 then cmd.throttleLimit=min(cmd.throttleLimit or 1,s.cornerLift) end
 -- Beta 1.59 : hors course, dépassement d'une voiture lente ou du joueur rangé lancé malgré le freinage d'AC pour garder
 -- l'écart : écart latéral permis en ligne droite (sinon la tentative restait figée derrière).
 if braking and s.state~='AVOID' and s.state~='CALM' and not (s.passBrakeFree and passStates[s.state] and profile~='C' and a.corner>=p.cornerMin and ownBrake<K.passBrakeMax) then desired=s.offset end
 if s.zone.noYield and yieldStates[s.state] or s.zone.noOvertake and passStates[s.state] then desired=s.base end
 if a.corner<K.returnCornerMin and (s.state=='YIELD_OUT' or s.state=='OVT_OUT' or s.state=='DRIVE') then desired=s.offset end
 if s.state=='IDLE' then desired=s.laneActive and s.lane or 0; s.confirm=0; s.pendingAt=0 end
 if frame.length<=0 or not a.splineValid then desired=0 end
 -- Repos anti-zigzag : jamais au détriment d'un évitement ou d'une récupération en cours.
 -- Beta 1.47 : jamais au détriment d'un drapeau bleu (céder au plus rapide passe avant le plafond).
 if now<s.driveUntil and s.state~='AVOID' and s.state~='CALM' and not (s.yieldBlue and yieldStates[s.state]) then desired=0; if s.state~='IDLE' then transition(e,s,'DRIVE','direction_limit',now) end end
 if rearLeft or rearRight then
  local move=(s.laneActive and desired or M.reachable(s,a,p,g,desired))-s.offset
  if (move<-K.rearLogMove and rearLeft or move>K.rearLogMove and rearRight) and (now>=(s.rearLogAt or -math.huge) or s.rearLogAt-now>K.defenseLogGap) then
   s.rearLogAt=now+K.defenseLogGap; e.stats.rearSide=(e.stats.rearSide or 0)+1
   local by=frame.cars[s.rearSideBy or 0]
   U.log(e.log,now,'INFO',string.format('conscience arriere: %s garde sa ligne, %s arrive cote %s (dans %.1f s, +%.0f km/h)',a.name,by and by.name or '?',move*g.offsetSign<0 and 'gauche' or 'droit',s.rearSideIn or 0,s.rearSideSa or 0),i)
  end
 end
 -- Beta 1.60 : décalage de la cession relevé pour la ligne « cession finie » (voulu, permis par la largeur, atteint).
 local yielding=s.state=='YIELD_IN' or s.state=='YIELD_HOLD'
 if yielding and desired~=0 then
  local allowed=abs(M.reachable(s,a,p,g,desired))
  s.yWant=max(s.yWant or 0,abs(desired))
  if not s.yBound or allowed<s.yBound then s.yBound=allowed end
 end
 local passing=s.state=='OVT_IN' or s.state=='OVT_HOLD'
 if passing and desired~=0 then
  local allowed=abs(M.reachable(s,a,p,g,desired))
  s.pWant=max(s.pWant or 0,abs(desired)); if not s.pBound or allowed<s.pBound then s.pBound=allowed end
 end
 cmd.offset=M.lateral(s,desired,row,a,p,g,dt,now)
 -- Plus grand décalage atteint : côté réel (signe écrit : décalage × offsetSign, positif à droite), mètres dans l'échelle
 -- de ce côté, largeurs de piste à cet instant.
 if yielding and s.yWant and abs(s.offset)>(s.yPeak or 0) then
  local right=s.offset*g.offsetSign>0
  s.yPeak=abs(s.offset); s.yRightSide=right; s.yLeft=a.leftWidth or 0; s.yRight=a.rightWidth or 0; s.yPeakM=s.yPeak*(right and s.yRight or s.yLeft)
 end
 if passing and s.pWant and abs(s.offset)>(s.pPeak or 0) then
  local right=s.offset*g.offsetSign>0
  s.pPeak=abs(s.offset); s.pPeakRight=right; s.pPeakM=s.pPeak*(right and (a.rightWidth or 0) or (a.leftWidth or 0))
 end
 if s.newDirectionLimit then s.newDirectionLimit=false; e.stats.limit=(e.stats.limit or 0)+1; U.log(e.log,now,'WARN',H.limitText(s,now),i) end
 -- Beta 1.31 (têtes-à-queue répétés aux mêmes freinages en descente, Acque Minerali et Rivazza) : en freinage ou en
 -- virage, jamais moins prudente ni plus agressive que sa base. L'aspiration, le dépassement et la poursuite
 -- abaissaient la prudence, lissée sur 0,4 s, jusque dans le freinage. Remontée rapide de la prudence.
 -- Même affinage (séance de Spa à 20 h 47, aide au dépassement engagée : prudence 1,5 à 3,1 à 5–6 m d'une cible écartée
 -- de 3 à 4,5 m, « sans progrès » au bout de 10 à 24 s) : cible décalée, prudence au plus K.passFreeCaution (1 = native) après toutes
 -- les autres règles de la ligne droite ; au freinage et en virage elle remonte à sa base (règle de la Beta 1.31, juste après).
 local protect=ownBrake>K.ruleBrake or a.corner<p.cornerMin
 -- Affinage 1.62 (12 novembre, « à fond du côté libre ») : attaquant décalé de sa cible, en courbe sans freiner : la
 -- prudence ne remonte plus à la base du profil (1,6 à 2,2 hors course : AC gardait ses distances à côté de la cible),
 -- seulement à K.passFreeCornerCaution au plus ; au freinage, la règle de la Beta 1.31 reste entière.
 if protect then caution=max(caution,passFree and ownBrake<=K.ruleBrake and min(s.baseCaution,K.passFreeCornerCaution) or s.baseCaution); aggression=min(aggression,s.baseAggression) end
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
 if s.hotspot then caution=caution*K.hotspotCaution end
 -- Beta 1.59 : plafond gardé sous un drapeau jaune local (la limite de la zone suffit) ; levé seulement sous neutralisation
 -- et drapeau rouge. Sous K.firstLapFloorPct de l'allure apprise à cet endroit (hors évitement et retour au calme) : plus
 -- de prudence ajoutée à une voiture déjà très lente.
 if firstLap and not e.incidents.neutral and not e.incidents.red then
  caution=min(caution,U.lerp(caution,s.baseCaution*K.firstLapCautionMax,s.flW))
  if not s.yellow and s.state~='AVOID' and s.state~='CALM' then
   local pace=Delta.pace(e.delta,e.states,i,Delta.bin(a.spline,e.delta.bins),p.multiClass)
   -- Beta 1.59 (relecture) : allure inconnue (premier tour) : K.yellowUnknownPct de la vitesse maximale vue.
   if pace<=0 then pace=K.yellowUnknownPct*(s.topKmh or 0)/3.6 end
   if pace>K.firstLapFloorMinKmh/3.6 and a.speed<K.firstLapFloorPct*pace then caution=min(caution,U.lerp(caution,s.baseCaution,s.flW)) end
  end
 end
 local tau=s.state=='CALM' or s.state=='AVOID'
 tau=tau and K.fastModulatorTau or s.state=='YIELD_OUT' and K.yieldRecoveryTau or s.yieldBlue and yieldStates[s.state] and K.blueRecoveryTau or K.modulatorTau
 cmd.level=U.ema(cmd.level,U.clamp(level,K.minNativeLevel,K.nativeLevelMax),dt,tau)
 cmd.aggression=U.ema(cmd.aggression,U.clamp(aggression,0,K.maxAggression),dt,aggression<cmd.aggression and protect and K.fastModulatorTau or tau)
 cmd.caution=U.ema(cmd.caution,U.clamp(caution,K.minCaution,K.maxCaution),dt,caution>cmd.caution and protect and K.fastModulatorTau or tau)
 cmd.levelOwned=p.section_general or abs(cmd.level-(a.baseLevel or a.aiLevel))>=K.levelEpsilon
 cmd.aggressionOwned=p.section_general or abs(cmd.aggression-(a.baseAggression or a.aiAggression))>=K.aggrEpsilon
 cmd.cautionOwned=p.section_general or abs(cmd.caution-K.defaultCaution)>=K.cautionEpsilon
 M.trafficCap(cmd,s,a,p,profile,dt)
 -- Beta 1.41 (journées circuit du 3 novembre : cessions sans fin en ligne droite, le niveau ne change pas la vitesse de
 -- pointe) : en cession (pas en sortie), un suiveur à moins de K.yieldCapGap m derrière ou à sa hauteur, en ligne droite
 -- au-delà de K.yieldCapMinKmh km/h : vitesse de pointe réduite de K.yieldTopCut km/h sous l'allure libre apprise à
 -- chaque endroit (inconnue : sous la vitesse du début de la réduction), atteinte en douceur, montant librement avec
 -- elle, rendue dès que la cession s'achève, au virage ou sans suiveur proche.
 -- Beta 1.59 (journées circuit du 10 novembre : 5 cessions abouties sur 139, 59 au bout de la durée maximale) : hors
 -- course, suiveur suivi jusqu'à K.yieldCapGapOff m, vitesse de pointe aussi sous la sienne (K.yieldPassDeltaKmh km/h
 -- de moins, au moins K.trafficMinSpeed), atteinte à K.yieldCapDecelOff km/h par seconde : l'IA lève vraiment le pied.
 local close=false
 local followKmh=math.huge
 local capGap=profile~='C' and K.yieldCapGapOff or K.yieldCapGap
 if s.state=='YIELD_IN' or s.state=='YIELD_HOLD' then
  for j=1,row.count do local r=row.neighbors[j]; if s.followers[r.index] and (r.alongside or r.long<0 and r.gap<capGap) then close=true; followKmh=min(followKmh,frame.cars[r.index].kmh) end end
  -- Beta 1.59 : référence du suiveur la plus haute vue pendant l'épisode : le freinage d'AC du suiveur pour garder son
  -- écart ne fait pas descendre la limite (sinon elle se resserrait jusqu'à K.trafficMinSpeed).
  -- Relecture 1.59 : référence remise à zéro à chaque nouvelle cession seulement (pas à chaque virage, où la limite est
  -- levée : à la sortie, la paire descendait jusqu'au plancher).
  if s.yieldRefStart~=s.yieldStart then s.yieldRefStart=s.yieldStart; s.yieldFollowRef=0 end
  if close and followKmh<math.huge then s.yieldFollowRef=max(s.yieldFollowRef or 0,followKmh); followKmh=s.yieldFollowRef end
 end
 -- Beta 1.59 : hors course, deux suiveurs ou plus en file derrière (pas à sa hauteur) depuis K.yieldQueueTime s :
 -- limite levée pour cet épisode (une voiture tenue sous sa vitesse ferait un bouchon) ; comptée pour le résumé.
 if close and profile~='C' then
  local queued=0
  for j=1,row.count do local r=row.neighbors[j]; if s.followers[r.index] and not r.alongside and r.long<0 and r.gap<K.slowFollowGap then queued=queued+1 end end
  s.yieldQueueFor=queued>=2 and (s.yieldQueueFor or 0)+dt or 0
  if s.yieldQueueFor>K.yieldQueueTime then
   if s.yieldQueueStart~=s.yieldStart then s.yieldQueueStart=s.yieldStart; e.stats.yieldCapQueue=(e.stats.yieldCapQueue or 0)+1 end
   close=false
  end
 end
 -- Beta 1.59 (audit CSP du 10 novembre, point 5) : hors course, jamais de limite pour une IA déjà lente (anormale, ou
 -- sous K.slowRatio fois son allure libre, à défaut celle de sa classe) : la limite la tenait sous son allure, faisait
 -- le bouchon et l'empêchait d'être reconnue comme obstacle (limite de l'app).
 if close and profile~='C' then
  local fleet=e.delta.fleet[p.multiClass and s.class or 1]
  local ref=s.freePace>0 and s.freePace or fleet and fleet[Delta.bin(a.spline,e.delta.bins)] or 0
  if s.abnormal==true or ref>0 and a.speed<ref*K.slowRatio then close=false end
 end
 -- Beta 1.60 (relecture) : jamais de lever de pied pour une cession qui ne peut pas s'écarter (moins de
 -- K.sideMinRoom m de décalage permis du côté de la cession) : ralentir sur la trajectoire ne libère rien.
 if close then local room=sideRoom(s,a,p,g,s.targetSide~=0 and s.targetSide or 1); if room~=nil and s.targetSide~=0 and room<K.sideMinRoom then close=false end end
 -- Beta 1.60 (lot 3, passage franc) : attaquant engagé sur cette voiture (états de passage, cible = elle), à sa hauteur
 -- ou à moins de K.frankLiftGap m, elle-même sortie de la trajectoire d'au moins K.frankOffM m : lever de pied franc
 -- (K.frankDeltaKmh km/h sous lui, à la rampe ordinaire de la cession) ; jamais avec une autre voiture dans sa file à moins
 -- de K.frankThirdGap m derrière elle (règle « pas de coup de frein avec une voiture collée derrière »), jamais une
 -- voiture déjà lente. Hors course et cessions prioritaires de la course.
 local frankLift=false
 s.frankNowKmh=nil
 if close and (profile~='C' or s.yieldBlue) and not s.abnormal then
  local w=s.offset*g.offsetSign>0 and (a.rightWidth or 0) or (a.leftWidth or 0)
  local passer,third=false,false
  for j=1,row.count do
   local r=row.neighbors[j]; local os=e.states[r.index]
   local committed=s.followers[r.index] and os.target==i and (os.state=='OVT_IN' or os.state=='OVT_HOLD')
   -- Affinage 1.62 (Zandvoort, 12 novembre : cible à 157 km/h, limite 157) : attaquant décalé d'elle et à sa hauteur
   -- (AC ne garde aucun écart avec une voiture à côté : pas de spirale) : sa vitesse du moment sert de référence au
   -- lever de pied franc ; derrière elle, la référence reste sa vitesse la plus haute (Beta 1.59).
   if committed and abs(r.lat)>=K.passFreeLat and r.alongside then s.frankNowKmh=min(s.frankNowKmh or math.huge,frame.cars[r.index].kmh) end
   if committed and (r.alongside or r.long<0 and r.gap<K.frankLiftGap) then passer=true
   elseif not committed and r.long<0 and r.gap>=0 and r.gap<K.frankThirdGap and abs(r.lat)<=(a.width+frame.cars[r.index].width)*0.5+K.radarLatMargin then third=true end
  end
  frankLift=passer and not third and (s.yieldLine or w>0 and abs(s.offset-s.base)*w>=K.frankOffM) -- Beta 1.62 : « line », sans décalage
 end
 if frankLift and not s.frankLift then e.stats.frankLift=(e.stats.frankLift or 0)+1 end
 s.frankLift=frankLift
 -- Beta 1.60 (lot 4, Nürburgring GP du 11 novembre en lot 3 : 316 lignes de suivi, l'attaquant n'a aucune limite de
 -- l'app (ni vitesse, ni gaz, ni frein) mais roule à la vitesse de la cible ou moins, décalé hors trajectoire en
 -- virage ; la cible n'était ralentie qu'en ligne droite au-dessus de 80 km/h) : hors course, le lever de pied franc
 -- vaut dès K.frankCapMinKmh km/h. Beta 1.62 (règles par session : « jamais ralentir sur la ligne en virage rapide ») :
 -- la limite ne joue qu'en ligne droite (a.corner tient compte de l'accélération latérale) ; en virage la voiture qui
 -- cède tient son allure et se décale (la descente en virage du lot 4 est retirée).
 if close and a.corner>=p.cornerMin and a.kmh>=(frankLift and profile~='C' and K.frankCapMinKmh or K.yieldCapMinKmh) then
  if not s.yieldCap then
   s.yieldCap=a.kmh-K.yieldTopCut; s.yieldCapNow=a.kmh
   -- Relecture 1.59 : au début d'une limite, référence au moins à la vitesse de l'IA (suiveur collé qui a freiné).
   if profile~='C' and followKmh<math.huge then s.yieldFollowRef=max(s.yieldFollowRef or 0,followKmh,a.kmh); followKmh=s.yieldFollowRef end
  end
  local target=max(K.trafficMinSpeed,s.freePace>0 and s.freePace*3.6-K.yieldTopCut or s.yieldCap)
  if profile~='C' and followKmh<math.huge then target=min(target,max(K.trafficMinSpeed,followKmh-K.yieldPassDeltaKmh)) end
  -- Beta 1.60 (lot 3) : lever de pied franc. La référence du suiveur est sa vitesse la plus haute de la cession : hors
  -- du point le plus rapide, « 15 km/h sous lui » restait au-dessus de la vitesse des deux voitures et rien ne se
  -- passait (Nürburgring GP du 11 novembre : 5 m derrière pendant 25 s, 6 m d'écart latéral). Passage franc : aussi
  -- K.frankDeltaKmh km/h sous l'allure libre de la voiture qui cède à cet endroit (inconnue : sous sa vitesse du
  -- début de la limite).
  if frankLift then
   local own=s.freePace>0 and s.freePace*3.6 or s.yieldCap+K.yieldTopCut
   target=min(target,max(K.trafficMinSpeed,own-K.frankDeltaKmh))
   if followKmh<math.huge then target=min(target,max(K.trafficMinSpeed,followKmh-K.frankDeltaKmh)) end
   if s.frankNowKmh then target=min(target,max(K.trafficMinSpeed,s.frankNowKmh-K.frankDeltaKmh)) end
  end
  s.yieldCapNow=target>=s.yieldCapNow and target or U.approach(s.yieldCapNow,target,(profile~='C' and K.yieldCapDecelOff or K.trafficDecelKmh)*dt)
  cmd.speedLimit=min(cmd.speedLimit,s.yieldCapNow)
 -- Beta 1.59 (règle du pilote : jamais de coup de frein ni de coup d'accélérateur devant une voiture collée) : hors
 -- course, limite rendue en douceur : jamais sous la vitesse du moment, remontée de K.yieldCapReleaseKmh km/h par
 -- seconde, levée une fois K.yieldCapReleaseMargin km/h au-dessus. En course : levée d'un coup, comme avant.
 -- Relecture 1.59 : hors cession et sans voiture proche derrière, levée d'un coup (rien à protéger).
 elseif profile~='C' and s.yieldCapNow and (s.state=='YIELD_IN' or s.state=='YIELD_HOLD' or back and back.gap<capGap) then
  s.yieldCap=nil; s.yieldCapNow=max(s.yieldCapNow,a.kmh)+K.yieldCapReleaseKmh*dt
  if s.yieldCapNow>=a.kmh+K.yieldCapReleaseMargin then s.yieldCapNow=nil else cmd.speedLimit=min(cmd.speedLimit,s.yieldCapNow) end
 else s.yieldCap=nil; s.yieldCapNow=nil end
 -- Sortie des stands : une fois le limiteur levé, jamais de rattrapage brutal de la voiture de devant. Écart de
 -- vitesse permis de 7,5 à 15 km/h selon l'assurance, réduit avec la distance, négatif si elle est trop près.
 if pitGuard then
  local ahead=frame.cars[front.index].kmh
  local margin=K.pitGuardAllowance*U.lerp(0.5,1,s.persona.assertiveness)*U.clamp((front.gap-K.pitGuardMin)/(K.pitGuardGap-K.pitGuardMin),0,1)
  local cap=front.gap<K.pitGuardMin and ahead-K.pitGuardBack or ahead+margin
  cmd.speedLimit=math.min(cmd.speedLimit,math.max(math.min(K.trafficMinSpeed,ahead),cap))
 end
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
 elseif s.playerGap>p.blueFlagRange*K.blueForgetMult or not s.lappedByPlayer then
  -- Beta 1.47 : oubli après K.blueClearTime s seulement (« laisse passer » écrit deux fois en 6 s quand le tour d'écart
  -- vacillait au passage de la ligne).
  s.blueClear=(s.blueClear or 0)+dt
  if s.blueClear>=K.blueClearTime then s.blueWait=0; s.blueYieldLogged=false; s.blueWaitLogged=false; s.blueReason=nil end
 end
 -- Beta 1.60 (lot 5, course du 11 novembre : attardées en piste et pas une ligne de drapeau bleu) : journal des drapeaux
 -- bleus entre IA, en course : IA derrière celle-ci avec un tour d'avance ou plus, à portée ; une ligne quand celle-ci
 -- la laisse passer, une autre si elle tarde plus de K.blueLogTime s, avec la raison ; compteurs de la minute.
 do
  local bn=row.back>0 and row.neighbors[row.back] or nil
  local lapsB=0
  if not flagged and profile=='C' and frame.started and p.blueFlagEnabled and bn and bn.index~=frame.player and bn.gap>=0 and bn.gap<=p.blueFlagRange and (bn.sa>0 or bn.gap<=K.blueCloseGap) then
   lapsB=Classes.laps(a,frame.cars[bn.index],bn,frame.length)
  end
  if flagged then
  elseif lapsB>0 then
   if s.blueAiBy~=bn.index then s.blueAiBy=bn.index; s.blueAiWait=0; s.blueAiFree=0; s.blueAiYield=false; s.blueAiLate=false end
   s.blueAiWait=(s.blueAiWait or 0)+dt; s.blueAiClear=0
   -- Beta 1.62 (relecture M1) : temps sans excuse : aucun veto du directeur (virage, freinage proche, zone d attaque, zone
   -- sans cession, cote occupe, trop lent, voiture pas encore sur le point d arriver) depuis K.blueVetoGrace s.
   if now-(s.blueVetoAt or -math.huge)>K.blueVetoGrace then s.blueAiFree=(s.blueAiFree or 0)+dt end
   if yieldStates[s.state] and s.target==bn.index then
    if not s.blueAiYield then
     s.blueAiYield=true; e.stats.blueAiYield=(e.stats.blueAiYield or 0)+1
     U.log(e.log,now,'INFO',string.format('drapeau bleu IA: %s laisse passer %s (%d tour(s) d avance) apres %.1f s',a.name,frame.cars[bn.index].name,lapsB,s.blueAiWait),i)
    end
   elseif s.blueAiWait>=K.blueLogTime and not s.blueAiLate and not s.blueAiYield then
    s.blueAiLate=true; e.stats.blueAiLate=(e.stats.blueAiLate or 0)+1
    U.log(e.log,now,'INFO',string.format('drapeau bleu IA: %s devant %s depuis %.0f s sans la laisser passer (%s, %.0f m, %+.0f km/h)',a.name,frame.cars[bn.index].name,s.blueAiWait,s.blueReason or 'en attente',bn.gap,bn.sa),i)
   end
  elseif (s.blueAiBy or 0)>0 then
   s.blueAiClear=(s.blueAiClear or 0)+dt
   if s.blueAiClear>=K.blueClearTime then s.blueAiBy=0; s.blueAiWait=0; s.blueAiFree=0; s.blueAiYield=false; s.blueAiLate=false end
  end
 end
 pace(s,a,row,dt,p,e.delta.fleet[p.multiClass and s.class or 1],e.delta.bins)
 if front then s.gap=front.gap; s.sa=front.sa; s.ttc=front.ttc end
end
M.pace=pace
return M
