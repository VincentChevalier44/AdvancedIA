local U=require('src/util')
local M={version=3,release='Beta 1.62',profiles={'J','P','Q','C','H'},schema={},sections={'general','yield','blue','flash','overtake','lateral','human','start','accidents','rules','endurance','weather','traffic','globals','lights','strategy','sanctions'}}
local sectionKeys={}
for _,group in ipairs(M.sections) do sectionKeys[group]='section_'..group end
M.globalRuntimeKeys={'overrideAwareness','useGripBoost','useBrakeAssist','gripPerLevelPct','occLatMin','occLatMax','occMargin','occSpeedGain','seed','levelMode','debugLog'}
-- Préréglages : chaque onglet qui agit dans la session est coché. Départ n'agit qu'en course, Espacement qu'en
-- journée circuit ; la cession ordinaire est sans objet en course, les drapeaux bleus par tours hors course.
-- Les options physiques globales restent désactivées.
local presetSections={
 Nordschleife={general=true,yield=true,flash=true,overtake=true,lateral=true,human=true,accidents=true,rules=true,endurance=true,weather=true,traffic=true,lights=true},
 -- Beta 1.59 : Journée circuit (tout circuit sauf la Nordschleife), mêmes onglets que la Nordschleife.
 Circuit={general=true,yield=true,flash=true,overtake=true,lateral=true,human=true,accidents=true,rules=true,endurance=true,weather=true,traffic=true,lights=true},
 Qualifications={general=true,yield=true,flash=true,overtake=true,lateral=true,human=true,accidents=true,rules=true,endurance=true,weather=true,lights=true,sanctions=true},
 -- Essais : mêmes onglets que les qualifications, sessions d'essais seules ou de week-end.
 Essais={general=true,yield=true,flash=true,overtake=true,lateral=true,human=true,accidents=true,rules=true,endurance=true,weather=true,lights=true,sanctions=true},
 Course={general=true,blue=true,flash=true,overtake=true,lateral=true,human=true,start=true,accidents=true,rules=true,endurance=true,weather=true,lights=true,strategy=true,sanctions=true}}
-- Valeurs propres à un préréglage, au-delà des valeurs par défaut du profil. Multi-classes partout : sans écart
-- d'allure d'au moins classGapPct, une grille d'une seule classe reste une seule classe.
local presetValues={
 -- Beta 1.62 (décision 7 du pilote) : « Realistic race » avec les options de course pertinentes (aide au dépassement,
 -- conscience de l'arrière, sanctions des IA, départs réalistes, personnalités dynamiques, pilotage fin, rythme selon
 -- l'usure, stratégie avancée) ; départ arrêté (raceStart) et vos contacts (sanPlayerContact) jamais imposés.
 -- Beta 1.62 (choix du pilote, 12 novembre) : options pertinentes dans chaque préréglage. Partout : pilotage fin,
 -- personnalités dynamiques, rythme selon l'usure, conscience de l'arrière (sauf l'aide au dépassement hors course), météo en
 -- direct. Essais et qualifications : arrêt pour dégâts, vrais passages (qualiRuns). Course : arrêt pour dégâts, stratégies
 -- de départ variées. Journée circuit : pas d'arrêt pour dégâts (sans effet en profil J) ni de nuance des classes
 -- (onglet Drapeaux bleus sans objet hors course). Jamais imposés : mémoire des circuits, départ lancé ou formation, vos contacts.
 -- Journée circuit (règles du pilote) : tour de chauffe progressif après la sortie des stands (outLapEnabled).
 Nordschleife={multiClass=true,outLapEnabled=true,fineInputs=true,dynamicPersona=true,wearPace=true,rearAwareness=true,weatherLive=true},Qualifications={multiClass=true,fineInputs=true,dynamicPersona=true,wearPace=true,rearAwareness=true,weatherLive=true,damagePit=true,qualiRuns=true},
 Course={multiClass=true,overtakeSide='auto',passAid=true,rearAwareness=true,sanContact=true,startRealism=true,dynamicPersona=true,fineInputs=true,wearPace=true,strategySmart=true,weatherLive=true,damagePit=true,strategyStartVariety=true},
 -- Beta 1.59 : Journée circuit : appels de phares plus rares et moins insistants (valeurs de la course).
 -- Relecture d'ensemble 1.62 : biais de ligne coupé, sans effet quand le plus lent garde sa ligne.
 -- Beta 1.62 (décision 1 du pilote) : journée circuit hors Nordschleife : le plus lent garde sa ligne (yieldSide='line').
 Circuit={multiClass=true,yieldSide='line',laneBiasEnabled=false,overtakeSide='auto',flashRange=150,flashMinAdvantage=15,outLapEnabled=true,fineInputs=true,dynamicPersona=true,wearPace=true,rearAwareness=true,weatherLive=true},
 Essais={multiClass=true,levelPct=97,aggressionPct=40,paceSpreadPct=6,lapseEnabled=true,overtakeChain=true,fineInputs=true,dynamicPersona=true,wearPace=true,rearAwareness=true,weatherLive=true,damagePit=true,qualiRuns=true}}
-- Version 1.2.0 des préréglages intégrés, figée : un profil resté identique est mis à jour une seule fois.
local legacySections={
 Nordschleife={general=true,yield=true,flash=true,overtake=true,lateral=true,human=true,start=true,weather=true,traffic=true},
 Qualifications={general=true,yield=true,flash=true,overtake=true,lateral=true,human=true,start=true,weather=true},
 Essais={general=true,yield=true,flash=true,overtake=true,lateral=true,human=true,start=true,weather=true},
 Course={general=true,blue=true,flash=true,overtake=true,lateral=true,human=true,start=true,weather=true}}
local legacyGroups={general=true,yield=true,blue=true,flash=true,overtake=true,lateral=true,human=true,start=true,endurance=true,weather=true,traffic=true,globals=true}
local legacyCandidates={J={'Nordschleife','Endurance'},P={'Essais'},Q={'Qualifications'},C={'Course','Endurance'}}
-- Règles de course : valeurs par catégorie, appliquées ensemble aux profils Essais, Qualifications et Course.
M.ruleCategories={'base','F1','F1_2026','GT','Endurance'}
M.ruleProfiles={'P','Q','C'}
-- Valeurs tirées des règlements (F1 2025 et 2026, WEC 2026, GT World Challenge 2026) : double jaune au temps de secteur
-- +15 % (F1, défaut de toutes les catégories) ; FCY réelle à 80 km/h fixes, rendue par un delta +150 % (du même ordre
-- sur la plupart des circuits) ; Slow Zone d'endurance à 80 km/h ; stands fermés sous FCY (GT et WEC) et pendant trois
-- tours de voiture de sécurité (WEC 2026, art. 14.5) ; stands ouverts sous FCY en GT World Challenge (SRO 2026, art. 39.4 :
-- seule la FCY courte les ferme) ; arrêt GT Sprint entre 25 et 35 min sur 60, sans temps minimal ; F1 avec fenêtre
-- de 20 à 95 % de la course, pneus changés sous drapeau rouge ; F1 2025 avec DRS ; F1 2026 avec Overtake Mode
-- et aileron mobile sans attente (pluie et drapeaux le coupent toujours). Ravitaillement interdit en F1 (depuis 2010) et en
-- GT World Challenge Sprint : plein prévu au départ ; autorisé en endurance (WEC) : ravitaillement à l'arrêt,
-- libre au fil de la course (fin de relais, réservoir), pneus neufs et réparations à chaque arrêt (Beta 1.20). Voiture de
-- sécurité en escalade : VSC, FCY ou zone jaune d'abord, voiture de sécurité si l'incident s'aggrave, comme le fait la
-- direction de course ; activée par défaut en course avec tous les jeux de règles (Beta 1.19).
M.rulePresets={
 base={},
 F1={neutralization='vsc',mandatoryStops=1,pitWindowOpenPct=20,pitWindowClosePct=95,pitCompoundChange=true,redFlagWork=true,pitFuel='plan',redRestart='standing'},
 F1_2026={neutralization='vsc',mandatoryStops=1,pitWindowOpenPct=20,pitWindowClosePct=95,pitCompoundChange=true,redFlagWork=true,overtakeMode=true,rulesDrsLaps=0,pitFuel='plan',redRestart='standing'},
 GT={neutralization='fcy',fcyDeltaPct=150,mandatoryStops=1,pitWindowOpenPct=42,pitWindowClosePct=58,bopEnabled=true,proAmEnabled=true,pitFuel='plan'},
 Endurance={neutralization='fcy',fcyDeltaPct=150,slowZoneKmh=80,yellowSpeedKmh=80,maxStintMin=50,pitsClosed='pitFcySc',bopEnabled=true,proAmEnabled=true,predictableSlowClass=true,pitFuel='refuel',pitTyres=true,pitRepair=true}}
-- Préréglage intégré recommandé de chaque profil. Beta 1.52 (relecture) : appliqué à chaque nouvelle session détectée
-- (préréglage de la session, Beta 1.51, M.sessionPreset) ; préréglage de la session coupé : une seule fois, à un profil
-- jamais réglé, lorsque la détection l'active.
M.recommended={J='Nordschleife',P='Essais',Q='Qualifications',C='Course'}
-- Réglages qui comptent quelque chose (réactions, voitures, arrêts) : valeurs entières.
M.integerKeys={flashMaxReactors=true,redFlagCars=true,mandatoryStops=true,penaltySeconds=true,penaltyDisqualify=true,rulesDrsLaps=true,sanTrackWarnings=true,sanServeLaps=true,finalLaps=true,sanEscalationStep=true,sanEscalationMax=true}
-- Réglages des pénalités (jamais en journée circuit) et de la surcouche Endurance (journée circuit et course).
M.penaltyKeys={playerPenalties=true,deltaTolerance=true,penaltySeconds=true,penaltyDisqualify=true,aiPenalties=true}
M.overlayKeys={enduranceOverlay=true,stintLevelSwing=true,stintDegradationPct=true}
-- Réglages sans effet dans un profil : masqués dans l'interface et ramenés à leur valeur par défaut (pénalités en
-- journée circuit, surcouche Endurance en essais et en qualifications).
-- Sessions hors week-end de course (journée circuit, hotlap) : ni pénalités, ni règles de championnat.
function M.solo(profile) return profile=='J' or profile=='H' end
-- Répartition des IA (Beta 1.26) : ni en course ni en hotlap ; portée d'AI flood de CSP en journée circuit seulement.
-- Beta 1.52 (relecture) : sorties des stands étalées comprises (src/traffic.lua, M.mode : jamais en course ni en hotlap).
M.spawnKeys={pitExitSpread=true,spawnMode=true,spawnMinCars=true,spawnPitPct=true,spawnGapVariation=true,floodRangeKm=true}
-- Beta 1.42 (demande du pilote) : stratégie et pannes des IA, aspiration cassée et urgence des derniers tours en course
-- seulement ; sanctions des IA en essais, qualifications et course (hors course : tours invalidés et contresens seuls).
M.raceKeys={strategyEnabled=true,strategyTyreWearPct=true,strategyFuelMarginLaps=true,strategyUndercut=true,strategyRiskPct=true,strategySpreadPct=true,
 failuresEnabled=true,failureRate=true,failureLossPct=true,towBreakEnabled=true,towBreakRange=true,towBreakStraight=true,
 finalLapsEnabled=true,finalLaps=true,finalAggressionPct=true,finalDefensePct=true}
M.sanctionKeys={sanTrackLimits=true,sanTrackWarnings=true,sanCutPenalty=true,sanCutSeconds=true,sanJumpStart=true,sanPitSpeed=true,sanPitExit=true,
 sanProcedureKind=true,sanWrongWay=true,sanWrongWaySeconds=true,sanServeLaps=true,sanStopGoSeconds=true,sanTimeSeconds=true,sanUnservedTime=true,
 sanGiveBack=true,sanGiveBackSeconds=true,sanMessages=true,
 -- Beta 1.56 (décision du pilote) : limites de piste du joueur, pénalités croissantes, rapport de course (tous coupés par défaut).
 sanPlayerTrackLimits=true,sanPlayerSession=true,sanPlayerPenalty=true,sanEscalation=true,sanEscalationStep=true,sanEscalationMax=true,sanReport=true}
M.sanctionRaceKeys={sanTrackWarnings=true,sanCutPenalty=true,sanCutSeconds=true,sanJumpStart=true,sanPitSpeed=true,sanPitExit=true,sanProcedureKind=true,
 sanServeLaps=true,sanStopGoSeconds=true,sanTimeSeconds=true,sanUnservedTime=true,sanGiveBack=true,sanGiveBackSeconds=true,
 sanPlayerPenalty=true,sanEscalation=true,sanEscalationStep=true,sanEscalationMax=true,sanReport=true}
-- Beta 1.56 : vos sorties en essais et qualifications, masqué en course.
M.sanctionPracticeKeys={sanPlayerSession=true}
-- Interrupteurs des sanctions : tous coupés quand la section est décochée.
M.sanctionSwitches={'sanTrackLimits','sanCutPenalty','sanJumpStart','sanPitSpeed','sanPitExit','sanWrongWay','sanUnservedTime','sanGiveBack','sanMessages','sanPlayerTrackLimits','sanEscalation','sanReport'}
function M.hidden(profile,key) return M.solo(profile) and (M.penaltyKeys[key] or M.sanctionKeys[key]) or profile~='C' and (M.raceKeys[key] or M.sanctionRaceKeys[key] or M.raceOnlyKeys[key]) or (profile=='P' or profile=='Q' or profile=='H') and M.overlayKeys[key] or (profile=='C' or profile=='H') and M.spawnKeys[key] or key=='floodRangeKm' and profile~='J' or key=='qualiTraffic' and profile~='P' and profile~='Q' or key=='qualiRuns' and profile~='P' and profile~='Q' or key=='qualiCoolLaps' and profile~='Q' or profile=='C' and M.sanctionPracticeKeys[key] or key=='damagePit' and M.solo(profile) or false end
-- Préférences du pilote (panneau, messages, drapeau du HUD, DRS) : conservées au chargement d'un préréglage intégré.
M.preferenceKeys={'flagPanel','yellowHud','yellowMessage','pitMessage','drsAssist','drsBeepVolume','deltaBeeps'}
-- Clés ajoutées depuis la 1.3.0 (préréglages personnels antérieurs et préréglages intégrés 1.2.0).
local newKeys={}
-- Relecture 1.59 : lecture seule pour les tests (clés absentes des anciens préréglages intégrés).
function M.isNewKey(key) return newKeys[key]==true end
local function add(group,key,label,lo,hi,j,q,c,choices)
  -- Profil Essais (P) : valeurs préparées des qualifications.
  -- Profil Hotlap (H) : valeurs de la journée circuit (aucune IA dans ces sessions).
  M.schema[#M.schema+1]={group=group,sectionKey=sectionKeys[group],key=key,label=label,min=lo,max=hi,defaults={J=j,P=q,Q=q,C=c,H=j},choices=choices}
  if newKeys.open then newKeys[key]=true end
end
local function n(g,k,l,a,b,j,q,c) add(g,k,l,a,b,j,q,c) end
local function b(g,k,l,j,q,c) add(g,k,l,nil,nil,j,q,c) end
local function e(g,k,l,j,q,c,opts) add(g,k,l,nil,nil,j,q,c,opts) end
n('general','levelPct','Niveau (%)',40,110,95,100,100)
n('general','aggressionPct','Agressivité (%)',0,100,55,45,80)
n('general','caution','Prudence',0.5,8,1.6,2.2,1.2)
n('general','brakeZonePct','Zone de freinage émulée (%)',50,150,100,100,100)
n('general','paceSpreadPct','Dispersion du niveau (%)',0,20,8,3,2)
n('general','aggrSpreadPct','Dispersion d’agressivité (%)',0,30,12,8,10)
n('general','cautSpreadPct','Dispersion de prudence (%)',0,30,12,8,8)
newKeys.open=true
n('general','pitExitSpread','Sorties des stands étalées, essais et qualifications (s par IA, 0 = libre)',0,30,0,10,0)
-- Beta 1.26 (demande du pilote) : répartition des IA en début de session, à partir de spawnMinCars IA : sur tout le
-- circuit (défaut en journée circuit), sorties des stands étalées (défaut en essais et qualifications) ou laissée au
-- jeu ; jamais en course (départ sur la grille). Portée d'AI flood de CSP en journée circuit, sous le seuil.
e('general','spawnMode','Répartition des IA en début de session','track','pits','native',{'native','pits','track'})
n('general','spawnMinCars','Répartir à partir de (IA)',2,60,10,10,10)
n('general','spawnPitPct','IA laissées aux stands au départ (%)',0,50,25,25,25)
n('general','spawnGapVariation','Variation des écarts au départ (%)',0,100,100,100,100)
n('general','floodRangeKm','Portée d’AI flood de CSP, sous le seuil (km)',1,5,1,1,1)
newKeys.open=nil
b('yield','yieldEnabled','Cession ordinaire',true,true,false)
-- Beta 1.62 (décision 1 du pilote, pour R1) : « line » : le plus lent garde sa ligne et lève le pied, le plus rapide se décale.
e('yield','yieldSide','Côté de cession','right','right','right',{'left','right','auto','line'})
n('yield','yieldOffset','Décalage de cession',0.2,0.95,0.65,0.8,0.6)
n('yield','yieldDetectBehind','Détection arrière (m)',30,400,100,200,80)
n('yield','yieldBehindMargin','Avantage du suiveur (km/h)',1,30,6,4,6)
n('yield','yieldHorizon','Horizon arrière (s)',3,30,10,12,8)
n('yield','confirmTime','Confirmation (s)',0.1,2,0.6,0.4,0.5)
n('yield','yieldHoldMin','Maintien minimal (s)',0.3,5,1,1,1)
n('yield','yieldHoldAfterMin','Maintien après passage min. (s)',0.2,6,0.8,0.6,0.8)
n('yield','yieldHoldAfterMax','Maintien après passage max. (s)',0.2,6,2.2,1.6,1.8)
n('yield','yieldSlowdownPct','Ralentissement en cession (%)',0,20,6,8,6)
n('yield','inviteSlowdownPct','Invitation supplémentaire (%)',0,25,10,10,10)
n('yield','yieldMaxHold','Durée maximale de cession (s)',8,60,25,25,25)
-- Beta 1.51 (demande du pilote) : essais et qualifications, priorité aux voitures en tour lancé (src/quali.lua).
b('yield','qualiTraffic','Essais et qualifications : priorité aux tours lancés',false,true,false)
-- Beta 1.51 : qualifications, tours de refroidissement des IA entre deux séries de tours lancés (comme en F1).
b('yield','qualiCoolLaps','Qualifications : tours de refroidissement des IA',false,true,false)
M.schema[#M.schema].defaults.P=false
-- Beta 1.59 (décision du pilote) : vrais passages en piste des IA en essais et qualifications (src/runs.lua), coupé.
newKeys.open=true
b('yield','qualiRuns','Essais et qualifications : vrais passages en piste des IA',false,false,false)
newKeys.open=nil
b('yield','pressureEnabled','Réaction à la pression',true,true,false)
n('yield','pressureGap','Distance de pression (m)',5,30,15,15,15)
n('yield','pressureTime','Durée de pression (s)',1,15,4,3,4)
b('blue','blueFlagEnabled','Drapeaux bleus',false,true,true)
n('blue','blueFlagRange','Portée du drapeau bleu (m)',50,400,150,200,150)
e('blue','blueFlagSide','Côté sous drapeau bleu','auto','auto','auto',{'auto','left','right'})
e('flash','flashMode','Appels de phares','always','always','lapped',{'never','lapped','always'})
n('flash','flashRange','Portée des appels (m)',40,250,200,200,150)
n('flash','flashMinAdvantage','Avantage pour appel (km/h)',3,40,12,8,15)
n('flash','flashCloseAdvantage','Avantage à courte distance (km/h)',-10,15,-5,-5,6)
n('flash','flashRequestTTL','Durée d’une demande (s)',3,20,8,8,8)
n('flash','flashObliviousPct','Inattention au premier appel (%)',0,40,10,5,10)
n('flash','flashMaxReactors','Nombre de réactions',1,3,3,3,3)
b('flash','hornEnabled','Klaxon en complément',false,false,false)
newKeys.open=true
b('flash','aiFlashEnabled','Appels de phares entre IA',true,true,true)
newKeys.open=nil
b('overtake','overtakeEnabled','Dépassements',true,true,true)
e('overtake','overtakeSide','Côté de dépassement','left','left','left',{'opposite','auto','left','right'})
n('overtake','overtakeOffset','Décalage de dépassement',0.2,0.95,0.7,0.65,0.6)
n('overtake','overtakeDetectAhead','Détection avant (m)',20,200,60,50,50)
n('overtake','overtakeAheadMargin','Avantage pour dépasser (km/h)',1,30,8,10,3)
n('overtake','overtakeHorizon','Horizon avant (s)',2,20,6,6,6)
n('overtake','overtakeClearMargin','Marge après dépassement (m)',8,40,18,20,10)
n('overtake','overtakeRestTime','Repos après dépassement (s)',0,10,2,3,1)
b('overtake','overtakeChain','Enchaîner les dépassements',true,false,true)
n('overtake','stuckTime','Confirmation de retenue (s)',0.5,10,2,3,1.2)
n('overtake','stuckPaceRatio','Seuil d’allure retenue',0.8,0.99,0.93,0.93,0.95)
n('overtake','pullOutGapBase','Distance de déboîtement (m)',4,15,8,8,8)
n('overtake','pullOutGapPerMps','Gain de déboîtement (s)',0,0.5,0.25,0.25,0.25)
b('overtake','slipstreamEnabled','Aspiration',true,true,true)
b('overtake','defenseEnabled','Défense',true,true,true)
n('overtake','defenseMaxOffset','Décalage maximal de défense',0.1,0.5,0.35,0.35,0.35)
n('overtake','defenseCooldown','Repos entre défenses (s)',2,30,8,8,8)
n('overtake','defenseTriggerGap','Distance de défense (m)',5,25,12,12,12)
-- Beta 1.42 (demande du pilote) : aspiration cassée en ligne droite, air sale derrière une voiture, urgence des derniers
-- tours. Course seulement pour l'aspiration et la fin de course (M.raceKeys).
newKeys.open=true
b('overtake','towBreakEnabled','Casser l’aspiration en ligne droite',false,false,true)
n('overtake','towBreakRange','Aspiration à casser : distance (m)',10,60,30,30,30)
n('overtake','towBreakStraight','Ligne droite minimale (m)',200,1500,400,400,400)
b('overtake','dirtyAirEnabled','Air sale derrière une voiture',false,true,true)
n('overtake','dirtyAirGap','Air sale : distance (m)',5,40,20,20,20)
n('overtake','dirtyAirLiftPct','Air sale : gaz relâchés en virage (%)',0,10,3,3,3)
b('overtake','finalLapsEnabled','Urgence des derniers tours',false,false,true)
n('overtake','finalLaps','Derniers tours concernés',1,10,3,3,3)
n('overtake','finalAggressionPct','Agressivité en plus (%)',0,50,15,15,15)
n('overtake','finalDefensePct','Défense renforcée (%)',0,100,40,40,40)
newKeys.open=nil
n('lateral','rampSpeed','Vitesse de déplacement latéral',0.1,1,0.3,0.3,0.45)
n('lateral','rampAccel','Accélération latérale',0.5,4,1.5,1.5,2)
n('lateral','lowPassTau','Lissage latéral (s)',0.05,1,0.25,0.25,0.2)
n('lateral','maxSideOffset','Décalage maximal',0.3,0.95,0.85,0.85,0.8)
n('lateral','cornerMin','Seuil de ligne droite',0,1,0.35,0.35,0.5)
n('lateral','cornerYawRef','Référence de rotation (rad/s)',0.2,1.2,0.5,0.5,0.5)
n('lateral','lateralCooldown','Repos entre directions (s)',0.3,5,1.2,1.2,1)
n('lateral','emergencyReleaseFactor','Facteur de relâchement',1,4,2,2,2)
n('human','reactMin','Réaction minimale (s)',0.1,2,0.25,0.2,0.2)
n('human','reactMax','Réaction maximale (s)',0.1,2,0.9,0.6,0.6)
n('human','awMin','Attention minimale (s)',0.2,5,0.6,0.4,0.4)
n('human','awMax','Attention maximale (s)',0.2,5,2,1.2,1.2)
n('human','paceDriftPct','Variation lente du rythme (%)',0,6,2,1,1)
n('human','personalLineJitter','Variation de trajectoire',0,0.15,0.05,0.03,0.02)
b('human','lapseEnabled','Petites baisses de concentration',true,false,false)
n('human','lapseIntervalMin','Intervalle minimal (s)',20,900,60,120,120)
n('human','lapseIntervalMax','Intervalle maximal (s)',20,900,300,600,600)
n('human','lapseDurMin','Durée minimale (s)',0.5,8,1.5,1,1)
n('human','lapseDurMax','Durée maximale (s)',0.5,8,3,2,2)
n('human','lapseDropMin','Perte minimale de rythme (%)',0,25,6,3,3)
n('human','lapseDropMax','Perte maximale de rythme (%)',0,25,12,7,7)
b('human','laneBiasEnabled','Ligne liée à l’allure',true,false,false)
n('human','laneBiasMax','Biais maximal de ligne',0,0.4,0.25,0.25,0.25)
newKeys.open=true
b('human','mistakesEnabled','Erreurs de pilotage des IA (blocages, patinage)',true,true,true)
n('human','mistakeRate','Erreurs : fréquence (par heure et par IA)',0,6,1,0.5,0.5)
newKeys.open=nil
n('start','startDelay','Attente au départ (s)',0,30,0,0,2)
n('start','startCautionMult','Prudence au départ',1,3,1,1,1.3)
n('start','startAggrMult','Agressivité au départ',0.2,1,1,1,0.8)
n('start','startRelax','Détente après départ (s)',2,30,12,12,25)
b('start','startLaneHold','Maintien de ligne au départ',false,false,false)
-- Beta 1.47 (idée du pilote) : premier tour attentif, en course, au départ et à chaque relance (src/firstlap.lua).
newKeys.open=true
b('start','firstLapCare','Premier tour attentif (départ et relances)',false,false,true)
newKeys.open=nil
-- Accidents : mêmes clés d'obstacle qu'en 1.2.0 (onglet Départ), pour un retour arrière sans perte.
b('accidents','obstacleEnabled','Évitement des voitures arrêtées ou accidentées',true,true,true)
n('accidents','obstacleSpeedKmh','Vitesse d’obstacle (km/h)',5,50,25,25,25)
n('accidents','obstacleDetect','Détection d’obstacle (m)',50,300,150,150,150)
n('accidents','obstacleLevelDrop','Réduction près d’obstacle (%)',0,50,25,25,25)
n('accidents','obstacleCautionMult','Prudence près d’obstacle',1,3,1.5,1.5,1.5)
newKeys.open=true
n('accidents','avoidOffset','Écart d’évitement',0.3,0.9,0.6,0.6,0.6)
b('accidents','contactRecovery','Récupération après contact',true,true,true)
b('accidents','incidentStop','Arrêt des IA accidentées',true,true,true)
n('accidents','incidentStopMin','Arrêt minimal (s)',1,15,3,3,3)
n('accidents','incidentStopMax','Arrêt maximal (s)',1,30,8,8,8)
n('accidents','rejoinGap','Piste libre derrière pour repartir (m)',30,300,120,120,120)
b('accidents','yellowEnabled','Drapeaux jaunes (zone d’incident)',true,true,true)
n('accidents','yellowBefore','Début de zone avant l’incident (m)',50,800,300,300,300)
n('accidents','yellowAfter','Fin de zone après l’incident (m)',0,300,50,50,50)
n('accidents','yellowHold','Maintien après dégagement (s)',0,60,10,10,10)
n('accidents','yellowDecel','Décélération d’approche (m/s²)',2,10,5,5,5)
n('accidents','zoneDeltaPct','Double jaune : temps de référence plus lent de (%)',5,200,15,15,15)
n('accidents','slowZoneKmh','Double jaune : Slow Zone à vitesse fixe (km/h, 0 = temps delta)',0,150,0,0,0)
n('accidents','yellowSpeedKmh','Double jaune : vitesse de repli, allure inconnue (km/h)',30,200,50,50,50)
b('accidents','yellowHud','Drapeau jaune natif d’AC sur le HUD',false,false,false)
b('accidents','flagPanel','Panneau de drapeaux AdvancedIA en conduite',true,true,true)
b('accidents','yellowMessage','Messages d’incident à l’écran',true,true,true)
b('accidents','deltaBeeps','Delta : bips sonores',true,true,true)
b('accidents','playerPenalties','Pénalités du joueur sous drapeau',false,true,true)
n('accidents','deltaTolerance','Delta : tolérance aux mini-secteurs (s)',0,1,0.5,0.5,0.5)
n('accidents','penaltySeconds','Pénalité : coupure des gaz (s)',2,15,5,5,5)
n('accidents','penaltyDisqualify','Infractions tolérées avant disqualification',1,20,5,5,5)
b('accidents','aiPenalties','Sanctions des IA sous drapeau',false,true,true)
-- Beta 1.59 (décision du pilote) : arrêt aux stands pour dégâts (course, essais, qualifications ; coupé par défaut).
-- Relecture 1.59 : déjà dans un bloc de clés nouvelles ouvert plus haut (un bloc imbriqué le refermait trop tôt).
b('accidents','damagePit','Arrêt aux stands pour dégâts',false,false,false)
b('rules','noMoveBraking','Pas de changement de trajectoire au freinage',true,true,true)
e('rules','neutralization','Neutralisation après un incident majeur','local','local','local',{'local','fcy','vsc','sc'})
n('rules','majorIncidentTime','Incident majeur : immobilisation en piste (s)',5,60,15,15,15)
n('rules','fcySpeedKmh','FCY : vitesse de repli, allure inconnue (km/h)',40,150,80,80,80)
n('rules','fcyDeltaPct','FCY : temps de référence plus lent de (%)',10,150,50,50,50)
n('rules','vscDeltaPct','VSC : temps de référence plus lent de (%)',10,80,30,30,30)
n('rules','neutralizationHold','Durée minimale de neutralisation (s)',10,180,30,30,30)
b('rules','safetyCarEscalation','Voiture de sécurité sur incident aggravé',false,true,true)
e('rules','restartOvertake','Dépassement permis après la relance','line','line','line',{'line','scIn'})
b('rules','redFlagEnabled','Drapeau rouge sur accident grave (essais, qualifications, course)',true,true,true)
n('rules','redFlagCars','Drapeau rouge : voitures immobilisées en piste',2,10,3,3,3)
n('rules','redFlagSpeedKmh','Drapeau rouge : vitesse de repli, allure inconnue (km/h)',40,150,80,80,80)
n('rules','redDeltaPct','Drapeau rouge : temps de référence plus lent de (%)',10,200,60,60,60)
n('rules','redFlagHold','Drapeau rouge : interruption minimale (s)',20,600,60,60,60)
b('rules','redFlagWork','Drapeau rouge : pneus changés aux stands (arrêt compté)',false,false,false)
e('rules','redRestart','Relance après drapeau rouge','rolling','rolling','rolling',{'rolling','standing'})
n('rules','mandatoryStops','Arrêt obligatoire en course',0,1,0,0,0)
n('rules','pitWindowOpenPct','Ouverture de la fenêtre (% de course)',5,95,25,25,25)
n('rules','pitWindowClosePct','Fermeture de la fenêtre (% de course)',5,100,75,75,75)
b('rules','pitTyres','Pneus neufs à chaque arrêt (règles d’arrêt actives)',true,true,true)
b('rules','pitRepair','Réparations à chaque arrêt en course (carrosserie, suspensions, moteur)',true,true,true)
b('rules','pitCompoundChange','Changer de composé sec (F1)',false,false,false)
n('rules','minPitTime','Temps d’arrêt minimal (s, 0 = libre)',0,120,0,0,0)
n('rules','maxStintMin','Relais maximal (min, 0 = libre)',0,240,0,0,0)
e('rules','pitFuel','Carburant aux arrêts forcés','refuel','refuel','refuel',{'refuel','plan','ac'})
e('rules','pitsClosed','Stands fermés sous neutralisation','open','open','open',{'open','pitFcy','pitFcySc'})
b('rules','pitMessage','Message d’ouverture de la fenêtre d’arrêt',true,true,true)
b('rules','overtakeMode','Overtake Mode (F1 2026, moins d’une seconde à la détection)',false,false,false)
n('rules','overtakeModeGap','Overtake Mode : écart de détection (s)',0.3,2,1,1,1)
n('rules','overtakeModeBoostPct','Overtake Mode : gain de niveau (%)',0,5,2,2,2)
b('rules','drsAssist','DRS du joueur : bip et panneau',true,true,true)
b('rules','rulesDrs','DRS : règles de course (pluie, drapeaux, départ, voiture de sécurité, drapeau rouge)',false,true,true)
n('rules','rulesDrsLaps','DRS : tours du leader avant activation (départ, voiture de sécurité, drapeau rouge)',0,5,1,1,1)
b('rules','aiDrs','DRS des IA : ouverture dans les zones',true,true,true)
n('rules','drsBeepVolume','Bips (DRS et delta) : volume (%)',25,400,200,200,200)
b('rules','bopEnabled','BoP : rythmes resserrés dans chaque classe',false,false,false)
n('rules','bopStrengthPct','BoP : correction maximale (%)',0,5,2,2,2)
b('rules','proAmEnabled','Grades Pro-Am (Bronze à Platinum)',false,false,false)
b('rules','predictableSlowClass','Classe lente : trajectoire prévisible',false,false,false)
newKeys.open=nil
b('endurance','enduranceOverlay','Surcouche Endurance',false,false,false)
b('endurance','multiClass','Multi-classes',false,false,false)
n('endurance','classGapPct','Écart entre classes (%)',3,25,8,8,8)
n('endurance','classYieldMargin','Avantage interclasse (km/h)',1,15,4,4,4)
n('endurance','stintLevelSwing','Variation entre relais (%)',0,8,3,3,3)
n('endurance','stintDegradationPct','Dégradation d’un relais (%)',0,5,1,1,1)
b('weather','weatherAdaptation','Adapter le rythme à la météo',true,true,true)
b('weather','weatherTyresEnabled','Gérer les pneus secs et pluie',true,true,true)
newKeys.open=true
b('weather','weatherMessage','Message à l’écran au changement de météo',true,true,true)
newKeys.open=nil
n('weather','rainGripBoostPct','Compensation pluie sans pneu pluie (%)',0,30,15,15,15)
-- Beta 1.42 (demande du pilote) : tour de sortie à pneus froids, blocages liés à l'usure des pneus en fin de relais.
newKeys.open=true
b('weather','outLapEnabled','Tour de sortie : chauffe des pneus',false,true,true)
n('weather','outLapLevelPct','Tour de sortie : niveau réduit de (%)',0,15,7,7,7)
b('weather','lockWearEnabled','Blocages liés à l’usure des pneus',false,true,true)
n('weather','lockWearGain','Blocages : gain en fin de relais',0,3,1.5,1.5,1.5)
n('weather','lockFlatSpotKm','Méplat : usure ajoutée par blocage (km)',0,5,1,1,1)
newKeys.open=nil
-- Panneaux lumineux du circuit (Beta 1.37, section propre, demande du pilote) : couleurs envoyées aux panneaux (le jaune
-- toujours), durée du vert, tenue avant une couleur moins importante. Les défauts redonnent la Beta 1.36 à l'identique.
-- Beta 1.52 (relecture) : lightsYellow est purement visuel, une case figée (toujours vraie, M.validate) qui montre que le
-- jaune est toujours envoyé ; gardée dans le schéma, déjà enregistrée dans les préréglages et leurs signatures.
newKeys.open=true
b('lights','lightsYellow','Jaune · drapeau jaune, voiture de sécurité, VSC, FCY',true,true,true)
b('lights','lightsRed','Rouge · drapeau rouge',true,true,true)
b('lights','lightsBlue','Bleu · drapeau bleu vers vous',true,true,true)
b('lights','lightsWhite','Blanc · véhicule très lent devant',true,true,true)
b('lights','lightsOrange','Orange · piste glissante',true,true,true)
b('lights','lightsGreen','Vert · fin de zone, de neutralisation et relance',true,true,true)
n('lights','lightsGreenTime','Durée du vert (s)',0,15,5,5,5)
n('lights','lightsHold','Délai avant une couleur moins importante (s)',0.5,5,1.5,1.5,1.5)
newKeys.open=nil
-- Beta 1.42 (demande du pilote) : stratégie individuelle des IA (course seulement) et sanctions des IA (essais,
-- qualifications et course), sections propres.
newKeys.open=true
b('strategy','strategyEnabled','Stratégie individuelle des arrêts aux stands',false,false,true)
n('strategy','strategyTyreWearPct','Usure des pneus avant l’arrêt (%)',10,95,30,30,30)
n('strategy','strategyFuelMarginLaps','Marge de carburant (tours)',0,3,1,1,1)
b('strategy','strategyUndercut','Undercut et overcut (réaction aux arrêts des rivaux)',false,false,true)
n('strategy','strategyRiskPct','Prise de risque moyenne (%)',0,100,50,50,50)
n('strategy','strategySpreadPct','Écart entre stratèges (%)',0,100,60,60,60)
b('strategy','failuresEnabled','Pannes mécaniques progressives',false,false,true)
n('strategy','failureRate','Pannes : fréquence (par heure et par IA)',0,2,0.05,0.05,0.05)
n('strategy','failureLossPct','Panne : perte de rythme maximale (%)',3,30,12,12,12)
-- Beta 1.59 (décision du pilote) : stratégies de départ variées (course, coupé par défaut).
-- Relecture 1.59 : déjà dans un bloc de clés nouvelles ouvert plus haut (un bloc imbriqué le refermait trop tôt).
b('strategy','strategyStartVariety','Stratégies de départ variées',false,false,false)
b('sanctions','sanTrackLimits','Limites de piste (au moins trois roues dehors)',false,true,true)
n('sanctions','sanTrackWarnings','Avertissements avant pénalité (course)',0,5,3,3,3)
b('sanctions','sanCutPenalty','Virage coupé avec gain de temps : coupure des gaz',false,false,true)
n('sanctions','sanCutSeconds','Coupure des gaz (s)',2,15,5,5,5)
b('sanctions','sanJumpStart','Faux départ',false,false,true)
b('sanctions','sanPitSpeed','Excès de vitesse dans les stands',false,false,true)
b('sanctions','sanPitExit','Ligne de sortie des stands franchie',false,false,true)
e('sanctions','sanProcedureKind','Pénalité des infractions de procédure','drive','drive','drive',{'drive','stopgo','time'})
b('sanctions','sanWrongWay','Contresens : drapeau noir',false,true,true)
n('sanctions','sanWrongWaySeconds','Contresens toléré (s)',2,15,5,5,5)
n('sanctions','sanServeLaps','Tours pour purger une pénalité (drapeau noir ensuite)',1,5,3,3,3)
n('sanctions','sanStopGoSeconds','Stop-and-go : arrêt (s)',5,30,10,10,10)
n('sanctions','sanTimeSeconds','Pénalité de temps (s)',1,30,5,5,5)
b('sanctions','sanUnservedTime','Pénalité non purgée ajoutée au résultat',false,false,true)
b('sanctions','sanGiveBack','Place à rendre après un dépassement hors piste',false,false,true)
n('sanctions','sanGiveBackSeconds','Délai pour rendre la place (s)',5,30,15,15,15)
b('sanctions','sanMessages','Annonces des sanctions des IA à l’écran',false,true,true)
-- Beta 1.56 (décision du pilote) : vos limites de piste gérées par l'app (mêmes règles que les IA, jamais votre voiture
-- pilotée), pénalités de limites de piste croissantes (IA et joueur), rapport de course en CSV. Tous coupés par défaut.
b('sanctions','sanPlayerTrackLimits','Vos limites de piste gérées par l’app',false,false,false)
e('sanctions','sanPlayerSession','Vos sorties en essais et qualifications','invalid','invalid','invalid',{'invalid','notice'})
e('sanctions','sanPlayerPenalty','Votre pénalité en course (limites de piste, contacts)','time','time','time',{'time','throttle'})
b('sanctions','sanEscalation','Pénalités croissantes en cas de récidive',false,false,false)
n('sanctions','sanEscalationStep','Hausse à chaque récidive (s)',1,30,5,5,5)
n('sanctions','sanEscalationMax','Pénalité maximale par sortie (s)',5,60,30,30,30)
b('sanctions','sanReport','Rapport de course (fichier CSV)',false,false,false)
-- Beta 1.60 (étape de base) : neuf réglages, tous coupés ou neutres dans tous les profils et tous les préréglages
-- intégrés ; clés nouvelles (anciens préréglages personnels : valeur par défaut). Voir M.pendingKeys en fin de fichier.
b('human','fineInputs','Pilotage plus fin (gaz progressifs, erreurs à la limite)',false,false,false)
b('human','dynamicPersona','Personnalités dynamiques (phase de course, fatigue, pression)',false,false,false)
b('lateral','rearAwareness','Conscience de l’arrière',false,false,false)
b('overtake','passAid','Aide au dépassement (le défenseur tient sa ligne)',false,false,false)
b('weather','wearPace','Rythme selon l’usure, la gomme et le carburant',false,false,false)
b('strategy','strategySmart','Stratégie avancée (temps perdu aux stands, piste libre, voiture de sécurité)',false,false,false)
e('start','raceStart','Départ de la course','standing','standing','standing',{'standing','formation','rolling'})
b('sanctions','sanContact','Collisions et drapeaux bleus : sanctions des IA',false,false,false)
b('sanctions','sanPlayerContact','Collisions : vous êtes jugé aussi',false,false,false)
-- Beta 1.61 (étape de base) : trois réglages de profil, coupés dans tous les profils et tous les préréglages intégrés ;
-- clés nouvelles. Le quatrième, trackMemory, est global (fin de fichier). Voir M.pendingKeys en fin de fichier.
b('blue','classNuance','Retardataires et classes : comportement nuancé',false,false,false)
b('start','startRealism','Départs réalistes (réactions, tour de formation, faux départs gradués)',false,false,false)
b('weather','weatherLive','Météo en direct (rythme progressif, pneus anticipés)',false,false,false)
newKeys.open=nil
n('traffic','trafficGapSeconds','Intervalle de base (s)',0.5,5,2.5,2.5,2.5)
n('traffic','trafficDensityGain','Distance ajoutée par IA (m)',0.5,5,2.8,2.8,2.8)
n('traffic','trafficVariation','Variation des espacements (%)',0,50,45,45,45)
n('traffic','trafficMaxReduction','Réduction maximale de vitesse (%)',2,20,14,14,14)
M.globalDefaults={schemaVersion=1,enabled=true,autoProfile=true,manualProfile='J',offsetSign=0,sideSign=0,
 overrideAwareness=false,levelMode='auto',useGripBoost=false,gripPerLevelPct=0.004,useBrakeAssist=true,
 flashField='',occLatMin=0.3,occLatMax=5.5,occMargin=6,occSpeedGain=0.8,seed=19731019,debugLog=false,loadedPreset='',builtinMarks='',presetBySession=true,presetsUsed=false,dataRevision=0,safetyCarModel='ferrari_458_s3',safetyCarPicked=false,journal=true,panelOpacity=86,panelShow='info',overlayX=-1,overlayY=-1,overlayScale=1,overlayLocked=true,overlayBackground='solid',overlayContent=100,overlayClickThrough=true,overlayHideReplay=true,overlayHidePits=false,trackLights=true,overlayEnabled=true,overlaySession=true,overlayExplain=true,overlayRecap=true,overlayNativeBox=true,overlayMessages=true,overlayBlockMessages=true,cspHideMessages=true,cspHideFlags=true,cspMessagesLost=false,floodBackup='',panelInfoTime=0,windowCompacted=false,language='en',updateCheck=true}
M.globalBounds={panelOpacity={0,100},panelInfoTime={0,60},overlayX={-1,16000},overlayY={-1,16000},overlayScale={0.5,2.5},overlayContent={30,100},dataRevision={0,1000},offsetSign={-1,1},sideSign={-1,1},gripPerLevelPct={0,0.01},occLatMin={0.1,1},occLatMax={2,8},occMargin={2,15},occSpeedGain={0,2},seed={0,2147483647}}
M.globalChoices={language={'en','fr'},panelShow={'info','always'},overlayBackground={'solid','ghost','transparent'},manualProfile={'J','P','Q','C','H'},levelMode={'auto','native','grip','none'},flashField={'','highBeams','headlightsActive','lowBeams','flashingLightsActive'}}
-- Constantes physiques et temporisations : unique source des valeurs de comportement.
M.K={maxCars=61,paceBins=400,logLines=200,logRate=20,logDedup=5,maxZones=64,maxZoneBytes=65536,
 maxPatterns=8,maxPatternLength=32,dtMax=0.25,teleport=40,perceptionPeriod=0.1,metaPeriod=1,classPeriod=60,classCycles=2,
 neighbors=8,neighborRange=400,fallbackRange=80,sameDirection=0.5,coherenceFloor=15,coherenceRatio=0.35,occLatMax=5.5,
 minLength=3.5,maxLength=6.5,minWidth=1.5,maxWidth=2.3,length=4.4,width=1.85,
 speedTau=0.4,yawTau=0.3,ttcEpsilon=0.1,nearLine=0.3,overlapMargin=2,
 freeRange=80,paceAlpha=0.3,paceRatioAlpha=0.05,paceRatioMin=40,paceMinBins=40,speedMinYield=20,speedMinPass=30,
 latYield=4,latPass=3.2,pressureSa=8,pressureResetTime=1,pressureResetRange=1.5,
 nearYield=25,nearYieldMargin=0.5,confirmReset=0.3,pendingTTL=12,detectMax=400,
 courtesyMin=1.25,courtesyMax=0.75,yieldMarginRange=50,gapMarginMin=0.5,
 holdFloor=1,passBuffer=3,lostRange=1.3,slowLostTime=2.5,slowLostGap=15,ignoreFollower=10,
 invitationGap=25,invitationTime=12,invitationRamp=4,urgentAmp=1.1,cornerAmpMin=0.4,
 assertMin=1.3,assertMax=0.7,passMarginRange=40,stuckGapMin=10,stuckGapTime=1.5,
 passAdvantageJ=4,passAdvantageC=3,passCornerC=0.6,passBrakeMax=0.3,pullOutMax=22,
 corridorMin=40,corridorMax=250,corridorSpeedMin=1.5,abortBlocked=0.4,abortSlowTime=3,abortGap=5,
 abortFollowerSpeed=25,abortFollowerGap=30,passHoldMax=4,holdProgress=0.5,clearConfirm=0.6,alongsideBuffer=3,
 followRange=60,followMinGap=5,followGapRange=30,followCaution=1.35,followTTC=3,followTTCMult=1.1,
 slipCorner=0.9,slipTime=1,slipSpeed=150,slipCaution=0.85,slipCautionMin=0.6,
 brakeClosing=2,brakeGain=10,brakeMax=0.6,
 defenseChance=0.3,defenseAssert=0.5,defenseTime=2.5,defenseAggression=1.2,defenseCaution=0.9,
 obstacleTime=2,stoppedTime=10,slipDegrees=35,obstacleBlockedLevel=0.6,obstacleClear=12,
 contactDrop=25,contactWindow=0.3,contactRange=6,calmTime=4,calmExitSpeed=40,
 driftPeriodMin=90,driftPeriodMax=240,jitterPeriodMin=7,jitterPeriodMax=19,jitterRange=40,baseMax=0.25,
 lapseRamp=0.3,playerFollowGap=8,playerCaution=1.15,lateralSpeedBase=100,lateralSpeedFloor=30,
 lateralRateMin=0.6,lateralRateMax=1.6,blockedRelease=0.3,directionLimit=6,directionWindow=60,directionRest=20,sideDeadband=0.05,
 pitOffsetMax=0.5,pitZone=60,pitExitDelay=2,stintExitDelay=3,stintExitCautionTime=8,stintExitCaution=1.3,
 stintDuration=2400,wetLevel=0.1,wetCaution=0.4,wetAggression=0.25,wetDetect=0.3,
 fatigueTime=5400,fatigueGain=1.3,fatigueMax=2,timeWrap=86400,
 classMax=4,classConfirm=0.7,classReaction=0.8,classFightSpeed=15,classCorner=0.7,classMargin=0.5,
 lapTolerance=0.02,lapRangeMult=1.5,lapSpeed=3,lapConfirm=0.3,lapReaction=0.8,lapCorner=0.7,lapCornerLevel=0.92,
 fightTime=2,fightSpeed=4,flashBurst=1.5,flashHoldMin=0.8,flashHoldMax=4,
 flashDebounce=0.15,flashDedup=0.4,flashLearnTime=6,flashPropagation=0.5,
 flashLat=6,flashSpeed=30,flashCloseGap=60,flashCatchMargin=5,courtesyRange=30,courtesyTime=20,courtesyAggression=0.35,courtesyPassSa=25,stuckRadius=15,inviteReport=3,brakeEcho=0.03,passCloseMin=4,closeMemory=5,realPassGap=20,realPassWindow=20,flashSecondTime=4,flashReact=0.6,flashConfirm=0.1,
 flashMargin=0.5,flashHorizon=1.5,flashUrgentCount=3,flashReactionMin=0.15,flashReactionMax=1.45,
 personaPatienceMin=0.7,personaPatienceMax=1.4,personaBrakeMin=0.9,personaBrakeMax=1.15,
 writePeriod=0.2,readbackPeriod=2,offsetEpsilon=0.002,levelEpsilon=0.005,aggrEpsilon=0.01,cautionEpsilon=0.02,gripEpsilon=0.001,
 capabilityFailures=3,carErrorTime=5,carErrorMax=3,saveDelay=1,maxCaution=16,maxAggression=0.95,
 probeLevel=1.05,probeDelay=0.3,probeTolerance=0.01,gripBase=1.2,calibrationOffset=0.5,
 calibrationTime=3,calibrationMinMove=0.15,calibrationRange=100,calibrationSpeed=60,calibrationCorner=0.95,
 calibrationPairGap=50,calibrationPairMax=150,calibrationMinWidth=2.5,calibrationActiveCorner=0.6,calibrationAlignment=0.98,
 classPatternClassMax=4,defaultLevel=1,defaultAggression=0.5,defaultCaution=1,modulatorTau=0.4,fastModulatorTau=0.15,
 minNativeLevel=0.3,yieldReachedEpsilon=0.03,centerEpsilon=0.03,yieldAggression=0.5,yieldHoldCaution=1.1,yieldRecoveryTau=1.5,
 passAggression=1.15,passCaution=0.7,alongsideCaution=0.8,avoidAggression=0.6,calmLevel=0.95,calmAggression=0.5,calmCaution=1.3,
 blueSlowdown=0.08,blueRecoveryTau=0.8,blueTrainHold=1,lostSaRatio=0.3,returnCornerMin=0.35,
 brakeEmulationGain=0.8,brakeEmulationPedal=0.2,brakeEmulationRange=80,brakeEmulationClosing=3,
 counterMax=2147483647,blockedYieldTime=3,blockedYieldGap=10,lapseSalt=50000,stintSalt=10000,performanceWindow=60,maxAppWindows=256,metadataLength=128,maxCapabilities=128,
 uiTipWidth=72,maxPresets=16,presetNameBytes=64,
 neutralReaction=0.3,neutralAwareness=0.5,trafficPeriod=0.5,trafficMinGap=15,trafficDensityCapacity=0.65,trafficMaxCapacity=0.9,
 trafficDecelKmh=4,trafficAccelKmh=8,trafficMinSpeed=30,trafficLogDelay=60,trafficFasterMargin=0.03,targetLostGrace=1,spreadDelay=1,spreadPlanDelay=0.5,spreadReport=8,spreadPlayerGap=300,spreadSpeed=50,spreadLaunchWait=0.5,spreadCheck=3,spreadTroubleKmh=10,spreadRetry=2,spreadReached=100,spreadTroubleLines=6,slowRatio=0.6,slowMinPaceKmh=60,slowMinKmh=15,slowFollowGap=60,slowLogTime=20,slowEnd=8,slowSettle=10,spreadMinGap=15,spreadWindow=60,spreadMaxKmh=30,trackDayExitSpeed=40,trackDayExitMaxTotal=600,floodPeriod=2,floodMinLength=7000,floodRound=50,messageProbe='AdvancedIA',probeFrames=90,probeTime=0.1,parkReturnPeriod=10,blueCloseGap=40,blueSlack=5,radarLatMargin=0.4,radarWarnTTC=2.5,radarCaution=1.4,radarTTC=1.2,radarMinBrake=0.08,radarBrakeMax=0.45,radarApply=1.5,radarRelease=0.8,radarLogPeriod=15,contactLogPeriod=10,contactLogBudget=3,towWindow=3,blueLogTime=3,pitExitWindow=60,pitExitSalt=7717,pitExitJitter=0.6,pitExitMaxTotal=180,pitExitSessionShare=0.25,pitExitMinGap=2,
 repairBase=3,repairBodyMin=5,repairBodyRate=0.1,repairSuspensionMin=0.02,repairSuspensionRate=40,repairEngineMin=990,repairEngineTime=30,repairMax=60,engineLifeNew=1000,trafficArmSpeed=60,trafficEpisode=6,trafficCycle=18,unlimitedSpeed=1e9,
 wrongWaySpeed=10,wrongWayTime=2,spinSpeed=15,spinTime=0.6,incidentClear=2,incidentMaxAge=120,crashSettle=4,rejoinWaitMax=10,rejoinSpeed=30,crashSalt=60000,stopPulse=1.5,stopPulsePeriod=0.5,
 yellowApproach=800,yellowNoPass=150,playerFlagLead=150,playerFlagLeadMax=800,flagLeadTime=1.25,gridGrace=6,gridMax=120,gridFirst=6,gridPitch=8,gridSlotRadius=4,gridApproachDecel=1.5,gridBrakeFrom=25,gridHoldDistance=1.5,gridColumn=0.35,gridColumnFrom=200,gridStillKmh=2,gridCrawlKmh=8,gridApproachKmh=80,gridBrakeMargin=3,gridBrakeScale=30,gridBrakeMin=0.1,gridNodeRange=400,gridLights=5,lightStep=1,lightsOutMin=0.2,lightsOutMax=3,jumpDistance=1,jumpSpeed=3,goShow=2,jumpShow=8,gridOvershoot=25,gridPassedShow=500,gridSideBySide=0.5,gridFormFrom=500,relaunchTravel=0.5,jumpServeDistance=150,jumpServeMax=30,slowGrace=10,flagsHiddenRead=5,cspLiveWait=15,cspWritesMax=8,slowLogGap=10,flagNone=0,flagCaution=2,flagStart=1,flagStop=5,flagReturnToPits=8,flagFasterCar=12,flagSlippery=3,flagSlowVehicle=6,flagFinished=13,flagOneLapLeft=14,penaltyMandatoryPits=1,penaltyTeleportToPits=2,
 ruleBrake=0.2,aiFlashGap=40,aiFlashCooldown=8,aiFlashPulses=2,aiFlashInterval=0.4,overtakeDetect=0.95,vscEnding=12,restartMax=600,redReleaseFirst=5,redReleaseGap=2,scClosedLaps=3,
 journalPeriod=2,journalSummary=60,journalKeep=3,journalMaxBytes=4194304,
 -- Mise à jour depuis GitHub (Beta 1.33) : vérification une fois par lancement, après updateDelay s de jeu ; lignes des
 -- notes de version montrées ; information de l'overlay aux stands, updateNotice s, une fois par lancement.
 updateDelay=10,bootFrames=10,bootUIFrames=3,updateNotes=8,updateNotice=6,
 queueGap=15,pillFontMin=11,deltaBoxMin=12,deltaStart=1,laneMin=0.5,laneBias=0.3,laneRelease=1,deltaCap=3,deltaJump=150,deltaMinKmh=30,miniSectorLength=250,miniSectorsMin=8,miniSectorsMax=60,fleetBinsPerFrame=4,scMergeMargin=30,singleYellowPct=15,passGiveBack=10,giveBackMin=5,giveBackDrop=25,queueKeep=15,queueClose=0.5,aiDeltaMarginMin=0.02,aiDeltaMarginMax=0.06,slipperyShow=30,slipperyGrace=30,lightsHold=1.5,lightsFiles=64,lightsBytes=4194304,slowVehicleRange=300,slowVehicleBehind=10,slowVehicleTime=3,slowVehicleRatio=0.5,meatballShow=20,meatballBody=100,meatballSuspension=0.2,meatballEngine=600,meatballGearbox=0.4,playerDamagePeriod=1,warningShow=10,safetySkinPattern='safety',drsLateLoad=60,drsLapsMax=99,drsAiBrake=0.2,drsAiCorner=0.5,drsAiKmh=80,drsAiRetry=1,drsAiCloseRetry=0.1,mistakeCheck=1,mistakeStartMin=60,mistakeArm=15,mistakeCooldown=180,mistakeGap=60,mistakeCalm=180,mistakeLapse=4,mistakeWet=2,mistakeWetCause=0.3,mistakeSkill=5,mistakeSkillMin=0.5,mistakeSkillMax=3,mistakeWeak=0.95,mistakePlayerGap=40,mistakeMinKmh=50,mistakeBrakePedal=0.6,mistakeBrakeKmh=120,mistakeGasPedal=0.8,mistakeCorner=0.6,mistakeTractionKmh=180,mistakeSeverity=1.4,mistakeSalt=80000,mistakeBrakeMin=0.4,mistakeBrakeMax=0.9,mistakeTractionMin=0.3,mistakeTractionMax=0.7,deltaBeepFile='sounds/delta-beep.wav',deltaBeepNegative=0.15,deltaBeepNear=0.2,deltaBeepFast=0.3,deltaBeepMid=0.5,deltaBeepMedium=0.6,deltaBeepFar=1,deltaBeepSlow=1.2,slipperyStripes=6,flagBlinkTime=5,pitRemindTime=15,pitCompoundGrace=3,pitNoticeCounted=4,pitNoticeSame=8,pitPlanPeriod=2,pitPlanNotice=8,heldMessageMax=5,pitHintTime=20,pitHintMinSpeed=15,pitHintSector=0.67,pitEntryMinKmh=40,pitRemindLate=0.2,aiPenaltyDecel=3,inviteLatMax=6,inviteCurve=0.001,passArmMax=20,carNameMax=96,passStallSa=2,passStallTime=8,pullOutTargetLat=1,pitGuardTime=15,pitGuardGap=80,pitGuardMin=12,pitGuardAllowance=15,pitGuardBack=5,pitGuardCaution=1.5,inviteLat=2,inviteGap=40,inviteTime=0.6,inviteSa=3,inviteClear=60,inviteRespite=20,aiPenaltyFactor=0.7,penaltyBlackFlag=4,penaltyReleaseBlackFlag=5,journalMarker='.AdvancedIA.journal',drsBeepFile='sounds/drs-available-beep.wav',penaltyBrakeMargin=2.5,incidentStopSpeed=10,obstacleClosing=15,penaltyCooldown=20,passWatch=40,noticeTime=8,penaltySlowDown=3,avoidClearMargin=10,avoidRecheck=1,crashWindow=30,neutralMax=600,neutralRecoverTime=20,stuckRecoverTime=30,trackRecoverTime=8,brokenRecoverTime=3,ruleDecision=5,calibrationRetry=60,laneMaxOffset=0.7,hudMessageTime=5,hudMessageMin=2,hudMessageMax=10,recapPassGap=40,recapPeriod=0.1,hudStripPeriod=0.25,hudFuelWarn=2,hudLapTime=5,hudWidth=600,hudTop=0.07,hudStripH=26,hudBandH=82,hudExplainLine=16,hudPillH=24,hudPad=8,hudHandle=18,hudGhost=0.5,scKickPeriod=2,startCareRise=4,startCareFall=0.6,radarLaunchTTC=0.8,brokenSuspension=0.5,brokenEngine=50,brokenGearbox=0.9,damageReadSpeed=25,
 redFlagMax=300,compactWidth=900,compactHeight=700,fuelReserveLaps=0.6,fuelMargin=1.03,fuelAlpha=0.3,fuelLapShare=0.5,fuelLapTimeMin=20,fuelStep=1,redFlagMaxCap=1800,redLapFactor=1.25,redPitMargin=60,redRecoverTime=8,redStopSpeed=5,redStopTime=5,greenShow=5,greenZoneShow=3,panelPeriod=0.25,panelWrap=58,
 bopGain=0.5,bopPeriod=60,scCatchUp=40,scQueueGap=60,scCallTime=10,scEscalateCars=2,scEscalateTime=30,scMinOut=60,scExitMax=90,scStuckTime=20,scInMax=300,scPlaceJunction=200,scPlaceFirstOut=250,scPlaceOnTrack=30,scPlaceLeader=200,scPlaceFree=80,scPlaceStep=50,scPlaceSteps=8,scPlaceMax=15,scLeadKmh=80,scLeadGap=120,scParkingMax=90,redExitWait=20,redExitWaitPlayer=45,redExitClear=10,restartRetakeRange=300,scPlaceReach=100,parkPeriod=2,maxCarList=4000,carReadMax=24,carReadBudget=0.004,uiSlowFrame=0.05,uiSlowFirst=0.5,uiSlowLogs=8,pitSpread=0.85,pitSalt=8152,pitConcurrent=3,pitLastStint=0.95,gradeSalt=70000,gradeLevel={1,0.99,0.975,0.96},gradeCaution={1,1,1.05,1.1},
 weatherPeriod=1,weatherConfirm=15,weatherWetOn=0.12,weatherWetOff=0.05,weatherRainOn=0.1,weatherRainOff=0.02,weatherWaterOn=0.03,weatherWaterOff=0.01,weatherHeavy=0.6,maxTyreCompounds=32,tyreCatalogBudget=2,tyreStopSpeed=1,tyreSalt=90000,spawnWindow=15,enduranceSuggestionSeconds=3600}
M.timerFields={'since','aiFlashAt','stintStart','pitExitUntil','pitCautionUntil','pitGuardUntil','pendingUntil','holdUntil','ignoreUntil','restUntil','nextPerception',
 'defendUntil','defendCooldown','calmUntil','speedWindowStart','lastContact','lapseAt','errorUntil','lastDirectionAt','driveUntil','yieldStart'}
M.optionalTimerFields={'pendingAt','lapseUntil','slowTeleportAt','flashMuteUntil','flashHoldUntil','flashFailAt','noAdvAt','cornerGiveUntil','cornerEntryAt','blueVetoAt'}
-- Beta 1.41 (journées circuit du 3 novembre : île de Man, Nordschleife) : trafic des IA. Table à part, versée dans K.
local traffic141={
 -- Chronomètre du coût par image : boucle d'essai de os.preciseClock au lancement.
 clockProbeLoops=20000,
 -- IA anormalement lente en tête de file (dégâts, IA native) : obstacle au bout de slowObstacleTime s ; une voiture
 -- devant à moins de slowLeadMargin km/h de plus fait partie de la même file. Derrière elle, dépassement permis dès
 -- slowPassRatio fois sa vitesse ; endommagée (suspension, carrosserie) et lente slowPitTime s : rentrée aux stands.
 slowObstacleTime=5,slowLeadMargin=5,slowPassRatio=0.8,slowPitTime=30,slowPitSuspension=0.2,slowPitBody=150,
 -- Rythme relatif de longue durée de chaque IA (allure / allure de sa classe, constante longRatioTau s), connu après
 -- longRatioMin s de conduite libre : « anormalement lente » = plus lente que slowRatio fois sa propre allure habituelle.
 longRatioTau=60,longRatioMin=20,
 -- Dépassement sur cession ou sur retenue : cible qui ne s'éloigne pas de plus de cessionSaMin km/h, allure libre plus
 -- rapide de passFreeMargin ici, au plus retainLossMax m perdus sur elle (retenue).
 cessionSaMin=2,passFreeMargin=0.03,retainLossMax=5,
 -- Cible repartie plus vite : paire ignorée passIgnore s, multiplié par passIgnoreGrowth à chaque nouvel échec (au plus
 -- passIgnoreMax s), compte oublié après passIgnoreForget s sans échec.
 passIgnore=45,passIgnoreGrowth=4,passIgnoreMax=600,passIgnoreForget=600,
 -- Cession : suiveur qui ne se rapproche plus (moins de followerStallSa km/h, au-delà de followerStallGap m) pendant
 -- followerStallTime s : perdu.
 followerStallTime=6,followerStallSa=1,followerStallGap=2,
 -- IA qui cède, suiveur à moins de yieldCapGap m ou à sa hauteur, en ligne droite au-delà de yieldCapMinKmh km/h :
 -- vitesse de pointe réduite de yieldTopCut km/h.
 yieldTopCut=8,yieldCapGap=25,yieldCapMinKmh=80,
 -- Allure apprise par endroit : au plus paceBinMeters m par endroit sur les longs circuits (400 endroits au moins,
 -- paceBinsMax au plus).
 paceBinMeters=50,paceBinsMax=1300,
 -- Sortie des stands : jonction apprise (voie des stands quittée après mergeLearnPit s, à moins de mergeLearnKmh km/h,
 -- moyenne mergeAlpha, écart de plus de mergeOutlier m écarté) ; voitures de la voie vues en piste de mergeBefore m
 -- avant la jonction à mergeAfter m après ; IA retenue de mergeHoldZone à mergeHoldMin m avant la jonction tant qu'une
 -- voiture en piste (au moins mergeTrafficKmh km/h) y arrive dans les mergeWindow s (plus le temps d'y rouler à
 -- mergeCrawl m/s au moins, mergeWindowMax s au plus) ou la passe à moins de mergeClear m ; mergeHoldMax s au plus.
 -- Relecture : journée circuit seulement ; retenue commencée seulement pour une IA qui roule (mergeHoldStartKmh km/h)
 -- et a dépassé son emplacement de mergeBoxClear m ; vue en piste seulement si elle roule (mergeSeenKmh km/h), ou au
 -- pas (mergeSeenCrawl km/h) à moins de mergeSeenNear m de la jonction.
 mergeLearnPit=5,mergeLearnKmh=120,mergeAlpha=0.3,mergeOutlier=200,mergeBefore=100,mergeAfter=50,mergeHoldZone=80,mergeHoldMin=5,
 mergeWindow=3,mergeWindowMax=5,mergeCrawl=10,mergeTrafficKmh=30,mergeClear=15,mergeHoldMax=10,
 mergeHoldStartKmh=5,mergeBoxClear=15,mergeSeenKmh=15,mergeSeenCrawl=3,mergeSeenNear=30,
 -- Panneaux lumineux du circuit : au plus lightsTotalBytes octets lus en tout (lightsFiles fichiers, lightsBytes chacun),
 -- une fois par circuit (Melbourne, layout_f1_2026 : 23 inclusions, plus les leurs).
 lightsTotalBytes=8388608,
}
for key,value in pairs(traffic141) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.50 : départ en ligne droite (radar avant : contact en s, approche modérée en km/h, largeur de piste en m pour
-- un couloir libre) ; voiture de sécurité sortie par la voie des stands (attente native d'AC et freinage forcé, s,
-- renouvelés toutes les scHoldPeriod s ; sortie de
-- l'emplacement et de la voie, s ; avance voulue sur le meneur à la sortie, s ; attente maximale de l'appel, s ; écart
-- des IA derrière elle au tour de relance, s ; sorties tolérées malgré l'attente) ; hors de la vue du joueur (m devant
-- et derrière lui, au plus s avant le retour au stand) ; vitesse plancher du meneur (m/s).
local k150={radarStraightTTC=0.6,radarStraightObstacleKmh=60,radarLaneWidth=8,scHoldTime=600,scHoldStop=2,scHoldPeriod=1,scLeaveMax=40,scExitLogPeriod=5,scLaneMax=45,
 scExitLead=20,scCallMaxWait=90,scExitGap=3,scEscapeMax=2,scHideAhead=800,scHideBehind=300,scHideMax=60,scLeaderMinSpeed=10,pitHintLatchSlack=200,
 -- Place rendue par une IA après un dépassement interdit sous neutralisation ou au tour de relance : attente maximale (s).
 aiGiveBackMax=30}
for key,value in pairs(k150) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.51 (demande du pilote, qualifications) : tours lancés en essais et qualifications (src/quali.lua).
-- Tour de sortie : de la sortie de la voie des stands au passage de la ligne ; ligne passée moins de qualiOutGrace s
-- après la sortie (ligne juste après la sortie des stands) : un tour de plus. Joueur (ou IA) en tour de
-- refroidissement : plus lent que qualiCoolRatio fois l'allure de la flotte ici (corrigée de son rythme, borné entre
-- qualiCoolPaceMin et 1) pendant qualiCoolTime s, jusqu'à la ligne. Cession prioritaire : voiture lancée derrière à
-- qualiYieldTime s au plus, qui se rapproche d'au moins qualiYieldSa km/h (ou à moins de qualiYieldNear m). Avis au
-- joueur : IA lancée à qualiWarnTime s au plus derrière lui, au plus une fois toutes les qualiWarnRepeat s par IA.
local k151={qualiOutGrace=30,qualiCoolRatio=0.75,qualiCoolPaceMin=0.85,qualiCoolTime=4,qualiCoolMinKmh=30,qualiYieldTime=3,qualiYieldSa=5,qualiYieldNear=30,
 qualiYieldRange=1.5,qualiWarnTime=3,qualiWarnRepeat=30,qualiLogGap=20,
 -- Tours de refroidissement des IA (qualifications) : après qualiPushMin à qualiPushMax tours lancés de suite (tiré par
 -- IA), un tour au niveau abaissé de qualiCoolLevel, atteint en qualiCoolRamp s, rendu en qualiCoolRelease s après la
 -- ligne ; jamais quand il reste moins de qualiCoolLate tours (temps de la session restant, dernier tour de l'IA, au
 -- moins qualiCoolLapMin s par tour) : le dernier essai compte.
 qualiCoolLevel=0.18,qualiCoolRamp=4,qualiCoolRelease=3,qualiPushMin=1,qualiPushMax=2,qualiCoolLate=2.5,qualiCoolLapMin=60,qualiCoolSalt=7151}
for key,value in pairs(k151) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.52 (relecture du pilotage des IA) : valeurs en dur nommées. Lancement du départ tant que la prudence de départ
-- (0 à 1) reste sous launchCare ; bornes des commandes de niveau et de prudence : nativeLevelMax et minCaution (bloc k152c) ;
-- attente du drapeau bleu oubliée au-delà de blueForgetMult fois la portée du drapeau bleu ; côté de dépassement par
-- défaut (deux côtés occupés) : droite au-dessus de passSideAssert d'assurance ; jonction des stands déplacée après
-- mergeOutlierCount sorties de suite loin d'elle.
local k152a={launchCare=0.5,blueForgetMult=2,passSideAssert=0.5,mergeOutlierCount=3}
for key,value in pairs(k152a) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.52 : instants des états des IA jamais décalés jusqu'ici au recalage du temps (nil et infinis laissés tels quels).
for _,key in ipairs({'passedByPlayerAt','qualiLogAt','lastPassAt','passStartAt','maneuverAt','laneSeen','laneAt','straightHoldAt','defendLogAt','startLiftAt','radarLogAt'}) do M.timerFields[#M.timerFields+1]=key end
-- Relecture 1.52, domaine B : clé du préréglage de la session (octets au plus, place gardée pour les profils servis),
-- sel du tirage de l'extinction des feux, distance du joueur à sa place (au mètre sous gridGapFine m, puis par
-- gridGapStep m), marge de vitesse d'une file d'attente au-dessus de l'allure d'obstacle (km/h), vitesse minimale (m/s)
-- de l'écart en temps entre rivaux de la stratégie.
local k152b={presetSessionKeyMax=256,presetSessionProfilesMax=8,lightsOutSalt=9134,gridGapFine=20,gridGapStep=10,queueSpeedMargin=5,strategyRivalMinSpeed=10}
for key,value in pairs(k152b) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.52 (relecture, réglages et interface) : longueurs des options globales en texte (copie de la configuration
-- d'AI flood, marques des préréglages, préfixe « builtin: » ou « custom: » du dernier préréglage chargé, octets) ;
-- plafonds des mémoires de l'interface (largeurs mesurées par l'overlay, majuscules et mesures du kit de dessin,
-- entrées) ; clignotement des drapeaux de l'overlay (Hz) ; pas des curseurs de l'overlay (échelle, opacité et contenu
-- en %, durée des informations en s) ; tolérance unique d'un réglage modifié ou d'un curseur déplacé.
local k152d={floodBackupBytes=512,builtinMarksBytes=128,loadedPresetPrefix=16,
 uiMeasureCache=3000,uiUpperCache=1000,uiDrawCache=6000,hudBlinkHz=2,
 overlayScaleStep=0.05,panelOpacityStep=5,overlayContentStep=5,panelInfoStep=1,uiEpsilon=1e-6}
for key,value in pairs(k152d) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.52 (relecture de la couche hôte) : délai minimal entre deux changements de pneus d'une IA (s) ; niveau écrit au
-- plus en mode natif (110 %) ; facteur d'adhérence de la météo au plus ; prudence écrite au moins ; niveau d'origine lu
-- au plus dans le point de reprise ; taille maximale d'un texte gardé dans ac.store (point de reprise) ; drapeau de
-- l'app resté affiché après une restitution : restitution renvoyée toutes les flagLeftoverDelay s ; fenêtre de réglages
-- ouverte hors des menus refermée au plus toutes les windowCheckPeriod s.
local k152c={tyreWriteGap=5,nativeLevelMax=1.1,weatherGripMax=1.3,minCaution=0.5,levelReadMax=2,storeMaxBytes=65536,flagLeftoverDelay=1,windowCheckPeriod=1,
 -- Copie laissée par la mise à jour de l'ancienne version ACAdvancedIA (src/oldinstall.lua, M.tidy) : effacée seulement
 -- si elle compte au plus oldWorkMaxFiles fichiers et dossiers, sur oldWorkMaxDepth niveaux au plus.
 oldWorkMaxFiles=4000,oldWorkMaxDepth=8}
for key,value in pairs(k152c) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.52 (décision du pilote) : mise à jour d'une app compagne (SpotterEnginer), signalée à l'accueil, jamais
-- installée par AdvancedIA. L'app la publie elle-même dans la mémoire de la partie (contrat v1, au plus
-- companionUpdateBytes octets, versions de companionVersionBytes octets au plus), relue toutes les
-- companionUpdatePeriod s.
local k152e={companionUpdatePeriod=10,companionUpdateBytes=200,companionVersionBytes=32}
for key,value in pairs(k152e) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.54 (journée circuit du 9 novembre à la Nordschleife : une IA a relancé six fois la même cible, chaque fois
-- « cible plus rapide », avec 33 appels de phares en 6 min) : à partir de passIgnoreStrict échecs « cible plus rapide »
-- sur la même cible, l'attente de la paire ne laisse plus passer qu'une cible anormalement lente ou une invitation
-- (avant : aussi un simple rapprochement avec une avance d'allure apprise, qui échouait de la même façon).
local k154={passIgnoreStrict=2}
for key,value in pairs(k154) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.55 (audit des journaux du 9 novembre, choix du pilote) :
-- - hors course, tentative de dépassement pas encore côte à côte abandonnée sans passProgressGain m gagnés sur la cible
--   en passProgressTime s, et au plus passAttemptMax s sauf terrain gagné dans les passCapGrace dernières secondes ;
-- - cession ordinaire (rapprochement) seulement à un suiveur vraiment plus rapide ici (yieldNeedAdvantage), refus noté une
--   fois par suiveur et par épisode (oublié après yieldNoAdvForget s sans refus) ;
-- - hors course, après flashFailLimit cessions sur appel de phares sans passage (compte oublié après flashFailForget s),
--   plus d'appel vers cette voiture pendant flashMuteTime s ; flashAfterAbort s sans appel vers la cible après un abandon
--   « suiveur rapide » ou « cède à son suiveur » ;
-- - essais et qualifications : avis « une voiture lancée arrive » seulement sur un rapprochement confirmé : écart en
--   temps au même point de la piste (relevé à l'entrée de chaque case, jusqu'à qualiCatchWatch s) réduit d'au moins
--   qualiCatchRateLong s par seconde sur qualiCatchSpanLong s, ou qualiCatchRateShort sur qualiCatchSpanShort s,
--   rattrapage prévu sous qualiCatchProject s, confirmé dans les qualiCatchWindow s après son arrivée à qualiWarnTime s
--   au plus (oubliée après qualiCatchForget s hors de portée) ; jamais en mètres ni en km/h (ils bondissent à chaque
--   freinage) ;
-- - drapeau pluie de CSP revenu sur piste sèche : consigne « sec » redonnée au plus une fois par rainReassertGap s ;
--   gommes de chaque modèle notées une fois par session (contrôle toutes les tyreModelsPeriod s).
local k155={passProgressGain=3,passProgressTime=8,passAttemptMax=15,passCapGrace=4,yieldNeedAdvantage=true,yieldNoAdvForget=60,
 flashFailLimit=2,flashFailForget=180,flashMuteTime=120,flashAfterAbort=20,rainReassertGap=10,tyreModelsPeriod=1,
 qualiCatchWatch=8,qualiCatchSpanLong=3,qualiCatchRateLong=0.1,qualiCatchSpanShort=1,qualiCatchRateShort=0.3,
 qualiCatchProject=15,qualiCatchWindow=6,qualiCatchForget=2,qualiCatchFill=8,qualiCatchSamples=16}
for key,value in pairs(k155) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.56 (décision du pilote) : vos limites de piste, pénalités croissantes, rapport de course.
-- - coupure des gaz demandée à AC : écriture attendue sanPlayerCutConfirm s, sinon pénalité de temps ; jamais par-dessus
--   une pénalité décidée il y a moins de sanPlayerQueueGap s (pas encore écrite) ;
-- - rapport : écrit quand toutes les voitures sont arrivées, ou sanReportAfterFinish s après votre arrivée ; sanReportKeep
--   fichiers gardés (rotation comme le journal), au plus sanReportMaxBytes octets.
local k156={sanPlayerCutConfirm=2,sanPlayerQueueGap=1,sanReportAfterFinish=90,sanReportKeep=5,sanReportMaxBytes=262144,sanReportFile='AdvancedIA-race'}
for key,value in pairs(k156) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.57 (Ved, Overtake) : suspension « en ligne » nommée : longueur gardée du texte d'une erreur de lecture
-- (caractères) et écart minimal entre deux lignes d'une suspension du même genre qui revient (s).
local k157={readErrorChars=120,onlineLogGap=60}
for key,value in pairs(k157) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.58 (MJFox, Overtake ; vu aussi par le pilote) : voiture gardée par l'app entrée dans la voie des stands (arrivée,
-- arrêt) : décalage ramené à 0 à laneReleaseRate par seconde (pas d'image au plus laneReleaseStep s), puis niveau,
-- agressivité, prudence, grip et vitesse rendus à AC ; ce que l'app tient exprès (garée, retenue, voiture de sécurité) reste.
-- Arrêt demandé : au plus pitRequestServiceMax passages servis à l'emplacement pendant une même demande sans arrêt compté.
local k158={laneReleaseRate=1,laneReleaseStep=0.1,pitRequestServiceMax=2}
for key,value in pairs(k158) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.59 : versions de SpotterEnginer dont le bouton de mise à jour reste grisé (signalé par sa session) : l'accueil
-- dit de l'installer une fois à la main depuis GitHub.
-- Rappel d'arrêt du joueur (Beta 1.59, demande du pilote) : au plus une fois par tour, pitHintShow s sans entrée des
-- stands connue. Plan d'arrêt de SpotterEnginer (contrat v1, clé publiée par lui) : relu toutes les sePlanPeriod s, figé
-- après sePlanStale s du temps du moteur sans horodatage nouveau, texte de sePlanBytes octets au plus.
local k159={companionManualVersions={['1.1.0']=true,['1.1.1']=true},pitHintShow=10,
 sePlanKey='SpotterEnginer.pitplan',sePlanPeriod=1,sePlanStale=6,sePlanBytes=160,sePlanLapMax=1000,
 -- Drapeaux jaunes (course de 10 tours du 10 novembre : 28 incidents, 13 annonces) : tête-à-queue compté seulement avec
 -- une perte de vitesse (K.contactDrop km/h) ou presque arrêté ; voiture arrêtée hors piste à plus de offClearLat m de la
 -- trajectoire depuis offClearTime s : dégagée ; point difficile (hotspotCount incidents à moins de hotspotMeters m en
 -- hotspotWindow s) : prudence x hotspotCaution et aucun dépassement commencé à moins de hotspotMeters m, oublié après
 -- hotspotForget s sans incident ; urgence des derniers tours au plus finalLapsShare de la course ; pannes espacées de
 -- failureGap s dans le plateau.
 offClearTime=15,offClearLat=8,hotspotCount=3,hotspotMeters=100,hotspotWindow=300,hotspotCaution=1.15,hotspotForget=1800,
 hotspotRecent=24,hotspotMax=8,
 -- Relecture 1.59 : plancher du double jaune, dégagement hors piste (bord + offClearEdge m, tenu offClearBack s), point
 -- difficile (oubli en course, pas dans les hotspotStartGrace premières secondes, au plus hotspotLengthShare du tour),
 -- plancher du premier tour jusqu'aux épingles lentes (firstLapFloorMinKmh).
 doubleFloorKmh=40,offClearEdge=2,offClearBack=2,hotspotForgetRace=600,hotspotStartGrace=120,hotspotLengthShare=0.25,firstLapFloorMinKmh=25,finalLapsShare=0.2,failureGap=300,
 -- Premier tour attentif (MJFox, Overtake) : sous firstLapFloorPct de l'allure apprise ici, plus de prudence ajoutée.
 firstLapFloorPct=0.6}
for key,value in pairs(k159) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.42 : constantes de l'étape de schéma (facteur de niveau, limite d'accélérateur), puis un bloc réservé par fourche.
local k142schema={levelScaleMin=0.7,throttleMin=0.3,throttleEpsilon=0.01}
-- Beta 1.42 : aspiration cassée, air sale, urgence des derniers tours (fourche AERO).
local k142aero={towCorner=0.9,towSpeed=150,towLat=1.2,towSaMin=-5,towMapSpeed=60,towMapAlpha=0.1,towMapSeen=3,towStraightShare=0.8,towMapPeriod=5,
 towMinAheadTime=6,towReturnTime=3,towHoldMax=8,towOffset=0.45,towCooldown=20,towPairCooldown=60,towChance=0.5,towAssert=0.4,towSalt=7,
 dirtyAirLat=1.5,dirtyAirSpeed=80,dirtyAirFull=5,dirtyJitterAmp=0.02,dirtyJitterGain=0.5,dirtyJitterRate=3,dirtyLogPeriod=30,finalRange=80,
 -- Relecture 1.42 : suiveur trop rapide pour une cassure (km/h), sortie des stands sans cassure (m avant et après la jonction).
 towSaMax=12,towMergeBefore=100,towMergeAfter=500,towLatSide=0.5}
-- Beta 1.42 : stratégie des IA, tour de sortie, usure et blocages, pannes (fourche STRATEGY).
local k142strategy={
 -- Stratégie : lignes du Diagnostic, seuil d'usure selon la prise de risque (±15 %), marge de carburant (×0,5 à ×1,5),
 -- rival « proche » (même tour, moins de 2,5 s), réactions (overcut, couverture, undercut), arrêt sous neutralisation.
 strategyRows=6,strategyRiskWear=0.3,strategyWearMin=0.1,strategyWearMax=0.98,strategyRiskFuel=1,strategyRivalLap=0.5,strategyRivalGap=2.5,
 strategyOvercutWear=0.85,strategyOvercutLaps=2,strategyCoverLaps=4,strategyBoldRisk=0.6,strategyUndercutLaps=3,strategyNeutralLaps=5,strategyLastLaps=2,
 strategyWearRateMax=0.25,strategyWearAlpha=0.4,strategyPlanLogGap=120,strategyWindowMargin=0.1,strategyRetry=5,
 strategyCauseLog={fuel='carburant',undercut='undercut',overcut='overcut',cover='couverture d un undercut',neutral='sous neutralisation',failure='panne',weather='meteo'},
 -- Tour de sortie : une ligne pour les départs des stands de la première minute, pneus « chauds » à 5 °C de leur optimum.
 -- Relecture 1.42 : résumé sur toute la sortie étalée (jusqu'à 3 min).
 outLapSummaryTime=200,outLapTempMargin=5,outLapMax=150,outLapRelease=8,
 -- Pannes : tirage toutes les 10 s, jamais dans les 10 derniers % de la course ; perte montée en 60 à 180 s, au moins la
 -- moitié de la perte réglée ; accélérateur jamais sous 0,8 ; arrêt demandé 10 s après le début ; réparation 8 à 20 s.
 failureCheck=10,failureLateRace=0.9,failureMinKmh=60,failureSalt=91000,failureSessionSalt=7919,failureRampMin=60,failureRampMax=180,failureLossMin=0.5,
 failureRepairMin=8,failureRepairMax=20,failureThrottleMin=0.8,failureThrottleShare=0.5,failurePitDelay=10,
 failureKindLog={leak='fuite',battery='batterie',overheat='surchauffe',puncture='crevaison lente'},
 wheelNames={'avant gauche','avant droit','arriere gauche','arriere droit'},
 -- Blocages et usure : comptée au-delà de 30 % d'usure, moitié du gain sans asymétrie ; au plus 15 km ajoutés par relais.
 lockWearStart=0.3,lockWearBase=0.5,lockWearMaxKm=15,lockWearCause=1.2,lockWearReset=0.2,lockWearNew=0.05,
 -- Relecture 1.42 : échelle de l'usure vérifiée (pneu vu sous 10 %, puis +1 point sur un tour suivant ; ligne après 5
 -- tours sinon), carburant critique (moins de 1,5 tour), réserve des 2 derniers tours (0,1 tour), contrôle 3 s après la
 -- sortie des stands (pneus changés si l'usure a baissé de lockWearReset, arrêt pneus contrôlé au-delà de 25 % ;
 -- carburant ajouté d'au moins 1 L), batterie vue au-dessus de 1 % (voiture hybride).
 wearTrustLow=0.1,wearTrustRise=0.01,wearProbeLaps=5,strategyCriticalFuel=1.5,strategyEndReserve=0.1,strategyCheckDelay=3,
 strategyTyreCheckMin=0.25,strategyFuelGainMin=1,kersSeenMin=0.01}
-- Beta 1.42 : sanctions des IA (fourche SANCTIONS).
local k142sanctions={
 -- Sortie des limites (au moins trois roues dehors) : durée minimale, vitesse minimale (jamais un tête-à-queue au pas),
 -- délai entre deux sorties comptées ; endroit ignoré dès K.sanLineCars IA différentes y sortent (cases de
 -- K.sanLineMeters m, K.sanLineBinsMax au plus).
 sanOutDwell=0.3,sanOutKmh=40,sanStrikeGap=4,sanLineCars=3,sanLineMeters=25,sanLineBinsMax=4000,
 -- Virage coupé : gain minimal (s) sur une portion de K.sanCutMinDist à K.sanCutMaxDist m ; coupure des gaz progressive
 -- vers K.sanCutThrottle (rampe par seconde), en ligne droite (accélération latérale K.sanStraightLat m/s² au plus), sans freinage,
 -- au-dessus de K.sanCutMinKmh km/h, personne à moins de K.sanCutBehind m derrière ; sinon pénalité de temps après
 -- K.sanCutDeferMax s.
 sanCutGain=0.3,sanCutMinDist=10,sanCutMaxDist=600,sanCutBinsMax=400,sanCutThrottle=0.35,sanCutRampDown=1.3,sanCutRampUp=2,
 sanCutMinKmh=80,sanCutBehind=30,sanCutDeferMax=90,sanCutBrake=0.1,
 -- Course : rien de jugé les K.sanGraceStart premières secondes ; aucun arrêt de pénalité avant K.sanServeAfterStart s.
 sanGraceStart=30,sanServeAfterStart=30,
 -- Voie des stands : excès de vitesse après K.sanPitSpeedGrace s dans la voie, au-delà de K.sanPitSpeedMargin km/h,
 -- K.sanPitSpeedDwell s de suite (limite d'AC, K.sanPitLimitDefault sans lecture) ; sortie plus de K.sanPitExitMargin m
 -- avant la jonction apprise (K.sanPitExitSamples sorties au moins, K.sanPitExitLane s dans la voie).
 sanPitSpeedGrace=4,sanPitSpeedMargin=6,sanPitSpeedDwell=1.5,sanPitLimitDefault=80,sanPitExitMargin=40,sanPitExitSamples=3,sanPitExitLane=5,
 -- Contresens au-dessus de K.sanWrongWayKmh km/h ; drive-through non purgé : K.sanDriveTime s au résultat (stop-and-go :
 -- son arrêt en plus) ; place à rendre : dépassement jusqu'à K.sanGiveBackWindow s après le retour en piste.
 sanWrongWayKmh=20,sanDriveTime=20,sanGiveBackWindow=3,
 -- Diagnostic et annonces : K.sanRowsMax événements, K.sanClassRows lignes de classement, K.sanClassLog places au
 -- journal ; une annonce toutes les K.sanNoticeGap s au plus ; app arrêtée plus de K.sanIdleGap s : états passagers oubliés.
 sanRowsMax=8,sanClassRows=4,sanClassLog=20,sanNoticeGap=6,sanIdleGap=1,
 -- Passage de pénalité : pas de tour de sortie (stratégie, cmd.noOutLap) jusqu'à K.sanNoOutLap s après la sortie de la voie.
 sanNoOutLap=2}
-- Fusion 1.42 : fin de relais étirée (tours au-delà du seuil d'usure, multipliés par 0,5 + prise de risque) ; pas de
-- couverture avec des pneus usés à moins de strategyCoverWear fois le seuil ; rythme relatif borné (départ arrêté).
local k142merge={strategyStretchLaps=2,strategyCoverWear=0.35,paceRatioLow=0.6,paceRatioHigh=1.4,
 -- Relecture SANCTIONS : faux départ d'une IA (mouvement tenu aiJumpDwell s, plus de aiJumpMinMove m) ; coupure des gaz
 -- (voiture derrière à moins de max(sanCutBehind, sanCutBehindTime s d'approche) ou collision dans moins de sanCutTtc s,
 -- reprise au-delà de sanCutResume m ; ligne droite : accélération latérale d'au plus sanStraightLat m/s² ; jamais dans
 -- les sanCutAfterRejoin s après un retour en piste ni les sanCutAfterStart s après le départ) ; place à rendre (plancher
 -- de vitesse : allure de la voiture doublée moins sanGiveBackFloorDrop km/h, au moins sanGiveBackPaceFloor fois l'allure
 -- apprise ; annulée si la voiture doublée roule sous sanGiveBackSlowPace fois la sienne) ; pénalité jamais purgeable
 -- (aucune IA entrée aux stands après sanNoPitLaps tours d'appel) ; sortie due à une manœuvre de l'app (décalage au-delà
 -- de sanAppOffset) ; vitesse limite des stands lue sous sanPitLimitMin km/h ignorée ; sortie de la voie confirmée après
 -- sanLaneDebounce s ; zone ignorée : sanLineCars IA en sanLineWindow s, oubliée après sanLineDecay s sans sortie.
 aiJumpDwell=0.5,aiJumpMinMove=1,sanCutBehindTime=4,sanCutTtc=5,sanCutResume=50,sanStraightLat=2,sanCutAfterRejoin=3,sanCutAfterStart=10,
 sanGiveBackFloorDrop=25,sanGiveBackPaceFloor=0.7,sanGiveBackSlowPace=0.6,sanNoPitLaps=2,sanAppOffset=0.3,sanPitLimitMin=40,sanLaneDebounce=1,
 sanLineWindow=300,sanLineDecay=1800}
-- Beta 1.44 (essais du 4 novembre : l'IA restait derrière le joueur qui ralentissait et se rangeait) : hors course, joueur
-- « lent » sous playerSlowRatio fois l'allure libre de l'IA ici (inconnue : sous speedMinPass*playerCrawlRatio km/h) ;
-- invitation hors course jusqu'à inviteLatAccel m/s² d'accélération latérale ; voiture sortie des stands depuis moins de
-- mergeExitGrace s jamais prise pour une voiture qui arrive à la jonction ; véhicule lent devant le joueur : au moins
-- slowVehicleAhead m devant lui pour être relevé (gardé ensuite jusqu'à slowVehicleBehind m derrière).
local k144={playerSlowRatio=0.85,playerCrawlRatio=1.25,inviteLatAccel=4,mergeExitGrace=10,slowVehicleAhead=10}
-- Beta 1.47 (journaux du 4 novembre) : départ (lancement tenu jusqu'au premier freinage, radar plafonné), défense,
-- boucles de dépassement, cessions inutiles hors course, limites de piste après un contact, drapeau bleu, journal.
local k147={startYaw=0.2,startYawHold=0.3,startBrakeKmh=80,startAnticipate=2.5,radarStartBrakeMax=0.18,radarStartFollowTime=0.6,radarStartFollowMin=8,radarStartLift=0.3,
 defenseLatMin=0.5,defenseSaMax=20,defenseTTCMin=1.5,defenseCorner=0.9,defenseRunTime=2,defenseLogGap=20,passIgnoreCloseMult=2.5,
 followerStallTimeOff=3.5,sanContactGrace=3,blueClearTime=5,fuelLogStep=5,flagLeftoverTries=3}
-- Beta 1.47 : premier tour attentif (src/firstlap.lua). Fin : ligne franchie (passage dans les firstLapLineGrace s
-- ignoré), peloton étiré (plus de firstLapSpread s devant et derrière pendant firstLapSpreadTime s), firstLapMax s ;
-- rendu en firstLapRelease s. Écart en temps : prudence jusqu'à x firstLapFollowCaution sous firstLapGapMin s, rien
-- au-delà de firstLapGapTime s. Anticipation : prudence x firstLapBrakeCaution à moins de firstLapAnticipate s d'un
-- point de freinage appris (IA libre devant, personne à moins de firstLapPointFree s, depuis firstLapPointKmh km/h,
-- en ligne droite) ou derrière une voiture qui freine, avec une voiture à moins de firstLapGapTime s devant. Radar :
-- levée de pied seule au-dessus de firstLapBrakeTTC s du contact. Dépassement : vraie ligne droite (firstLapPassCorner),
-- avance x firstLapPassMargin, couloir x firstLapCorridor. Évitement : voiture sous firstLapAvoidPct de l'allure du
-- peloton. Agressivité au plus firstLapAggr de la base. Écarts en temps : vitesse plancher firstLapSpeedMin m/s.
-- Prudence d'ensemble au plus firstLapCautionMax fois la prudence de base (hors jaune, neutralisation, rouge).
-- Double jaune, allure inconnue (IA) : repli à yellowUnknownPct de la vitesse maximale vue de la voiture (vitesses au-delà
-- de topKmhMax km/h ignorées), au moins yellowSpeedKmh.
-- Drapeau rouge (décision du pilote) : voitures immobilisées depuis redIncidentStill s à cause d'un incident (dégâts,
-- tête-à-queue, plus de redOffLine m hors de la trajectoire ou hors piste, ou arrêtée seule), jamais celles qui attendent
-- intactes dans la file ; piste bloquée : aucun passage de redPassWidth m entre les voitures accidentées à moins de
-- redBlockSpan m (gabarit plus redBlockMargin m), largeur inconnue redTrackHalf m de chaque côté.
local k147fl={firstLapLineGrace=10,firstLapSpread=2,firstLapSpreadTime=3,firstLapMax=180,firstLapRelease=3,firstLapPointMerge=50,
 firstLapPoints=32,firstLapPointKmh=60,firstLapPointCorner=0.8,firstLapPointFree=1,firstLapSpeedMin=10,firstLapGapMin=0.25,firstLapGapTime=0.8,
 firstLapFollowCaution=1.3,firstLapAnticipate=2,firstLapBrakeCaution=1.25,firstLapCareRise=1,firstLapCareFall=0.5,firstLapBrakeTTC=0.8,firstLapLastTTC=0.4,
 firstLapPassCorner=0.97,firstLapPassMargin=1.5,firstLapCorridor=1.3,firstLapAvoidPct=0.3,firstLapAggr=0.85,firstLapCautionMax=2,
 yellowUnknownPct=0.35,topKmhMax=450,
 redIncidentStill=10,redOffLine=4,redBlockSpan=40,redBlockMargin=0.3,redPassWidth=2.5,redTrackHalf=5}
for _,block in ipairs({k142schema,k142aero,k142strategy,k142sanctions,k142merge,k144,k147,k147fl}) do for key,value in pairs(block) do assert(M.K[key]==nil,key); M.K[key]=value end end
for _,key in ipairs({'passIgnoreUntil','yieldIgnoreUntil'}) do M.timerFields[#M.timerFields+1]=key end
-- Beta 1.41 (sessions du 3 novembre, Beta 1.40) : bandeaux qu'AC dessine lui-même malgré l'option de CSP « Hide system
-- messages » (coupe de piste, pénalités ; textes relevés dans acs.exe et dans les journaux) ; motifs Lua sur le titre
-- ou la description en majuscules. L'overlay ne les reprend plus (pas de doublon).
M.acDrawnMessages={'^CUT DETECTED','LAP WILL NOT COUNT','^PENALTY','SLOW DOWN FOR','SLOW DOWN TO','BEFORE THE END OF CURRENT LAP',
 'DRIVE ?%-?THROUGH','STOP ?& ?GO','STOP AND GO','JUMP ?%-?START','DISQUALIFIED'}
function M.defaults(profile)
 local r={schemaVersion=M.version,classPatterns='',configured=false}
 for _,s in ipairs(M.schema) do r[s.key]=s.defaults[profile] end
 for _,group in ipairs(M.sections) do r['section_'..group]=false end
 -- Hotlap : onglet Règles seul coché (règles de base) ; drapeaux, panneau et bip du DRS, aucune IA à piloter.
 if profile=='H' then r.section_rules=true end
 -- Panneaux lumineux (Beta 1.37) : cochés dans chaque profil.
 r.section_lights=true
 return r
end
-- Onglets différents du défaut du profil (Hotlap : onglet Règles coché par défaut).
function M.sectionsChanged(profile,p)
 for _,group in ipairs(M.sections) do
  local key=sectionKeys[group]
  if (p[key]==true)~=(profile=='H' and group=='rules' or group=='lights') then return true end
 end
 return false
end
function M.anySection(p)
 for _,group in ipairs(M.sections) do if group~='lights' and p[sectionKeys[group]]==true then return true end end
 return false
end
local function choice(v,list) for _,x in ipairs(list) do if x==v then return true end end return false end
function M.patterns(text,out)
 out=out or {}; for i=#out,1,-1 do out[i]=nil end
 if type(text)~='string' or #text>M.K.maxPatterns*(M.K.maxPatternLength+4) then return out,false end
 for pattern,class in text:gmatch('([%w_%-]+)%s*:%s*([1-4])') do
  if #pattern>M.K.maxPatternLength or #out>=M.K.maxPatterns then return out,false end
  out[#out+1]={pattern=pattern:lower(),class=tonumber(class)}
 end
 local rest=text:gsub('[%w_%-]+%s*:%s*[1-4]',''):gsub('[%s,;]','')
 return out,rest==''
end
function M.validate(profile,input,out)
 out=out or {}; local errors=0
 -- Migration v0 : mêmes clés reconnues. Version future (Beta 1.35 : après un retour à une version précédente) : chaque
 -- clé connue validée une à une, sections gardées, numéro le plus haut gardé à l'enregistrement ; jamais les défauts.
 if input.schemaVersion~=nil and (not U.finite(input.schemaVersion) or input.schemaVersion<0 or input.schemaVersion%1~=0) then input=M.defaults(profile); errors=errors+1 end
 local newer=input.schemaVersion~=nil and input.schemaVersion>M.version
 for _,s in ipairs(M.schema) do
  local v=input[s.key]; local good
  -- Beta 1.51 (demande du pilote) : arrêt obligatoire oui ou non ; 2 ou 3 arrêts enregistrés avant deviennent 1.
  if s.key=='mandatoryStops' and U.finite(v) and v>1 and v<=3 then v=1 end
  if s.min then good=U.finite(v) and v>=s.min and v<=s.max
  elseif s.choices then good=choice(v,s.choices) else good=type(v)=='boolean' end
  if not good then v=s.defaults[profile]; if not (input.schemaVersion==2 and (s.key=='weatherTyresEnabled' or s.key=='rainGripBoostPct')) then errors=errors+1 end end
  out[s.key]=v
 end
 for _,group in ipairs(M.sections) do
  local active=(input.schemaVersion==M.version or input.schemaVersion==2 or newer) and input[sectionKeys[group]]==true
  -- Panneaux lumineux (Beta 1.37) : section absente d'un enregistrement plus ancien, cochée comme son défaut.
  if group=='lights' and input[sectionKeys[group]]==nil then active=true end
  if group=='weather' and input.schemaVersion==2 then active=input.section_endurance==true and input.weatherAdaptation==true end
  out[sectionKeys[group]]=active
 end
 for _,s in ipairs(M.schema) do if M.hidden(profile,s.key) then out[s.key]=s.defaults[profile] end end
 for _,pair in ipairs({{'yieldHoldAfterMin','yieldHoldAfterMax'},{'reactMin','reactMax'},{'awMin','awMax'},{'lapseIntervalMin','lapseIntervalMax'},{'lapseDurMin','lapseDurMax'},{'lapseDropMin','lapseDropMax'},{'incidentStopMin','incidentStopMax'},{'pitWindowOpenPct','pitWindowClosePct'}}) do
  if out[pair[1]]>out[pair[2]] then out[pair[2]]=out[pair[1]]; errors=errors+1 end
 end
 local _,valid=M.patterns(input.classPatterns); out.classPatterns=valid and input.classPatterns or ''
 if not valid then errors=errors+1 end
 for key in pairs(M.integerKeys) do out[key]=math.floor(out[key]+0.5) end
 -- Jaune des panneaux : signal de base, toujours envoyé.
 out.lightsYellow=true
 out.schemaVersion=newer and input.schemaVersion or M.version
 -- Migration : un profil ayant déjà une section active est considéré comme réglé.
 out.configured=input.configured==true or M.sectionsChanged(profile,out)
 return out,errors
end
function M.validateGlobals(input,out)
 out=out or {}; local errors=0
 -- Version future : clés connues validées une à une (retour à une version précédente), numéro le plus haut gardé.
 if input.schemaVersion~=nil and (not U.finite(input.schemaVersion) or input.schemaVersion<0 or input.schemaVersion%1~=0) then input=M.globalDefaults; errors=errors+1 end
 local newer=input.schemaVersion~=nil and input.schemaVersion>M.version
 for k,d in pairs(M.globalDefaults) do
  local v=input[k]; local valid=type(v)==type(d)
  if type(d)=='number' then valid=U.finite(v); local r=M.globalBounds[k]; if valid and r then valid=v>=r[1] and v<=r[2] end end
  if M.globalChoices[k] then valid=choice(v,M.globalChoices[k]) end
  if k=='floodBackup' then valid=type(v)=='string' and #v<=M.K.floodBackupBytes and not v:find('%c') end
  if k=='loadedPreset' then valid=type(v)=='string' and #v<=M.K.presetNameBytes+M.K.loadedPresetPrefix and not v:find('%c') end
  if k=='builtinMarks' then valid=type(v)=='string' and #v<=M.K.builtinMarksBytes and v:match('^[%w=,]*$')~=nil end
  if k=='safetyCarModel' then valid=type(v)=='string' and #v<=M.K.metadataLength and v:match('^[%w_%-%.]*$')~=nil end
  if (k=='offsetSign' or k=='sideSign') and valid then valid=v==-1 or v==0 or v==1 end
  if not valid then v=d; errors=errors+1 end
  out[k]=v
 end
 out.seed=math.floor(out.seed); out.dataRevision=math.floor(out.dataRevision); out.schemaVersion=newer and input.schemaVersion or M.version
 if out.loadedPreset~='' then out.presetsUsed=true end
 return out,errors
end
-- Relecture 1.62 (S8, puis sans état global) : track et length (circuit de la session, facultatifs) choisissent la base
-- de « Multi-class endurance » en journée circuit ; inconnus : « Journée circuit ».
function M.preset(name,profile,out,track,length)
 local p=(name=='Nordschleife' or name=='Circuit') and 'J' or name=='Essais' and 'P' or name=='Qualifications' and 'Q' or name=='Endurance' and profile or 'C'
 out=M.validate(p,M.defaults(p),out)
 -- Beta 1.62 (audit des règles, I2 ; relecture S8) : « Multi-class endurance » en journée circuit : base du circuit de
 -- la session, Nordschleife (serrer à droite) sur la Nordschleife, « Journée circuit » ailleurs.
 local base=presetSections[name] and name or p=='J' and (track~=nil and M.trackDayPreset(track,length or 0) or 'Circuit') or 'Course'
 local sections=presetSections[base]
 for _,group in ipairs(M.sections) do out['section_'..group]=sections[group]==true end
 for key,value in pairs(presetValues[base]) do out[key]=value end
 local endurance=name=='Endurance' and profile~='Q' and profile~='P'
 if endurance then out.section_endurance=true; out.enduranceOverlay=true; out.multiClass=true; out.lapseEnabled=true end
 -- Beta 1.62 (décision 7 du pilote) : multi-classes en course : retardataires et classes nuancés.
 if name=='Endurance' and profile=='C' then out.classNuance=true end
 out.configured=true
 return out
end
function M.on(p,group) return p[sectionKeys[group]]==true end
function M.any(p)
 for _,group in ipairs(M.sections) do if group~='globals' and group~='lights' and M.on(p,group) then return true end end
 return false
end
-- Les valeurs sauvegardées restent intactes ; seules les sections cochées sont appliquées.
function M.effective(profile,p,out)
 out=out or {}
 for _,s in ipairs(M.schema) do
  if p[s.sectionKey]==true then out[s.key]=p[s.key] else out[s.key]=s.defaults[profile] end
 end
 for _,group in ipairs(M.sections) do local key=sectionKeys[group]; out[key]=p[key]==true end
 out.classPatterns=M.on(p,'endurance') and p.classPatterns or ''
 -- Beta 1.59 (décision du pilote) : onglet Général décoché = IA d'origine, aussi au début de la session : ni répartition
 -- des IA ni sorties des stands étalées par l'app (AI flood de CSP rendu, src/flood.lua).
 if not M.on(p,'general') then out.paceSpreadPct=0; out.aggrSpreadPct=0; out.cautSpreadPct=0; out.brakeZonePct=100; out.spawnMode='native'; out.pitExitSpread=0 end
 if not M.on(p,'yield') then out.yieldEnabled=false; out.pressureEnabled=false; out.qualiTraffic=false; out.qualiCoolLaps=false end
 if not M.on(p,'blue') then out.blueFlagEnabled=false end
 if not M.on(p,'flash') then out.flashMode='never'; out.hornEnabled=false; out.aiFlashEnabled=false end
 if not M.on(p,'overtake') then out.overtakeEnabled=false; out.defenseEnabled=false; out.slipstreamEnabled=false end
 if not M.on(p,'human') then out.paceDriftPct=0; out.personalLineJitter=0; out.laneBiasEnabled=false; out.lapseEnabled=false; out.mistakesEnabled=false end
 if not M.on(p,'start') then out.startDelay=0; out.startRelax=0; out.startCautionMult=1; out.startAggrMult=1; out.startLaneHold=false; out.firstLapCare=false end
 if not M.on(p,'accidents') then
  out.obstacleEnabled=false; out.contactRecovery=false; out.incidentStop=false; out.yellowEnabled=false; out.yellowHud=false; out.playerPenalties=false; out.aiPenalties=false
  -- Neutralisations et drapeau rouge restent signalés (et leur delta bipé) tant que l'onglet Règles agit.
  if M.on(p,'rules') then out.yellowMessage=p.yellowMessage; out.flagPanel=p.flagPanel; out.deltaBeeps=p.deltaBeeps else out.yellowMessage=false; out.flagPanel=false; out.deltaBeeps=false end
 end
 if not M.on(p,'rules') then
  out.noMoveBraking=false; out.neutralization='local'; out.mandatoryStops=0; out.minPitTime=0; out.maxStintMin=0
  out.overtakeMode=false; out.bopEnabled=false; out.proAmEnabled=false; out.predictableSlowClass=false; out.redFlagEnabled=false; out.drsAssist=false
  -- Ni DRS coupé par les règles, ni DRS des IA ouvert par l'app : décocher l'onglet arrête toute la section.
  out.rulesDrs=false; out.aiDrs=false; out.pitsClosed='open'; out.redFlagWork=false; out.pitRepair=false
  -- Beta 1.52 (relecture) : voiture de sécurité en escalade coupée aussi (src/incidents.lua), défaut vrai en course.
  out.safetyCarEscalation=false
 end
 -- Volume des bips : préférence du pilote, aussi pour le delta d'une zone jaune quand l'onglet Règles est décoché.
 out.drsBeepVolume=p.drsBeepVolume
 if not M.on(p,'endurance') then out.enduranceOverlay=false; out.multiClass=false; out.stintLevelSwing=0; out.stintDegradationPct=0 end
 if not M.on(p,'weather') then out.weatherAdaptation=false; out.weatherTyresEnabled=false; out.rainGripBoostPct=0; out.weatherMessage=false end
 -- Beta 1.42 : fonctions des sections décochées coupées (aspiration, air sale, fin de course, pneus, stratégie, sanctions).
 if not M.on(p,'overtake') then out.towBreakEnabled=false; out.dirtyAirEnabled=false; out.finalLapsEnabled=false end
 if not M.on(p,'weather') then out.outLapEnabled=false; out.lockWearEnabled=false end
 if not M.on(p,'strategy') then out.strategyEnabled=false; out.failuresEnabled=false end
 if not M.on(p,'sanctions') then for _,key in ipairs(M.sanctionSwitches) do out[key]=false end end
 -- Beta 1.60 : réglages des sections décochées coupés (départ : départ arrêté d'AC).
 if not M.on(p,'human') then out.fineInputs=false; out.dynamicPersona=false end
 if not M.on(p,'lateral') then out.rearAwareness=false end
 if not M.on(p,'overtake') then out.passAid=false end
 if not M.on(p,'weather') then out.wearPace=false end
 if not M.on(p,'strategy') then out.strategySmart=false end
 if not M.on(p,'start') then out.raceStart='standing' end
 return out
end
function M.effectiveGlobals(g,p,out)
 out=out or {}; for key,value in pairs(g) do out[key]=value end
 if not M.on(p,'globals') then
  for _,key in ipairs(M.globalRuntimeKeys) do out[key]=M.globalDefaults[key] end
 end
 return out
end
-- Relecture 1.62 (S9) : la défense n'agit qu'en course (profile connu : ignorée ailleurs).
function M.needsOffset(p,profile)
 return p.yieldEnabled or p.blueFlagEnabled or p.flashMode~='never' or p.overtakeEnabled or p.defenseEnabled and (profile==nil or profile=='C') or p.obstacleEnabled or p.laneBiasEnabled or p.personalLineJitter>0 or p.multiClass
end
local function equal(a,b) return a==b or type(a)=='number' and type(b)=='number' and math.abs(a-b)<1e-6 end
-- Valeurs de la 1.2.0 changées depuis : espacement de la journée circuit (Beta 1.20).
local trafficOld={trafficGapSeconds=1.2,trafficVariation=35,trafficMaxReduction=10}
-- Départ de course jusqu'à la Beta 1.23 (profil Course) : prudence ×1,6 et agressivité ×0,6, trop frileux en peloton.
local startOld={startCautionMult=1.6,startAggrMult=0.6}
-- Départ de course jusqu'à la Beta 1.26 (profil Course) : attente de 12 s, détente de 12 s, maintien de ligne ;
-- la Beta 1.27 reprend le profil personnalisé « Course Test » du pilote (1 s, 25 s, sans maintien de ligne).
-- Reconnaissance des préréglages 1.2.0 : seules l'attente et la détente y figuraient.
local startOld126={startDelay=12,startRelax=12}
local startMoved127={startDelay=12,startRelax=12,startLaneHold=true}
-- Portée des appels de phares jusqu'à la Beta 1.28 (aussi celle des préréglages 1.2.0).
local flashOld128={J=120,P=150,Q=150,C=100,H=120}
local flashCloseOld128={J=5,P=4,Q=4,C=6,H=5}
-- Interrupteurs indépendants des jeux de règles (Beta 1.19) : ignorés pour reconnaître un jeu (interface, journal).
M.switchKeys={mandatoryStops=true,safetyCarEscalation=true}
-- Préréglage intégré 1.2.0 resté strictement identique dans ce profil, ou nil.
function M.legacyMatch(profile,p)
 if p.classPatterns~='' then return nil end
 local base=M.validate(profile,M.defaults(profile),{})
 for _,name in ipairs(legacyCandidates[profile] or {}) do
  local endurance=name=='Endurance'
  local sections=legacySections[endurance and (profile=='J' and 'Nordschleife' or 'Course') or name]
  local same=true
  for _,s in ipairs(M.schema) do
   if not newKeys[s.key] then
    local expected=trafficOld[s.key] or s.key=='flashRange' and flashOld128[profile] or s.key=='flashCloseAdvantage' and flashCloseOld128[profile] or profile=='C' and (startOld[s.key] or startOld126[s.key]) or base[s.key]
    if endurance and (s.key=='enduranceOverlay' or s.key=='multiClass' or s.key=='lapseEnabled') then expected=true end
    if not equal(p[s.key],expected) then same=false; break end
   end
  end
  for _,group in ipairs(M.sections) do
   if not same then break end
   local expected=legacyGroups[group]==true and (sections[group]==true or endurance and group=='endurance')
   if group~='lights' and p['section_'..group]~=expected then same=false end
  end
  if same then return name end
 end
 return nil
end
-- Profil ou préréglage personnel antérieur à la 1.3.0 : l'évitement des obstacles suit ses clés dans l'onglet Accidents,
-- sans les nouveautés (drapeaux jaunes, arrêt des IA accidentées).
function M.upgradeObstacles(p) if p.section_start==true and not p.section_accidents then p.section_accidents=true; p.yellowEnabled=false; p.incidentStop=false end end
-- Migration unique des données enregistrées. 1.2.0 : un profil identique à un préréglage intégré reçoit sa version
-- 1.3.0 ; un profil modifié reste tel quel, sauf l'évitement des obstacles qui suit ses clés dans l'onglet Accidents.
-- Révisions par profil, communes aux profils enregistrés et aux préréglages personnels (from : révision des données).
-- Révision 5 (Beta 1.8) : temps delta assoupli ; un profil resté sur l'ancien défaut (0,10 s) passe au nouveau.
-- Beta 1.52 (relecture) : le maintien de ligne au départ, coupé par défaut dans tous les profils, n'a plus de migration.
-- Révision 6 (Beta 1.9) : règles GT conformes au règlement SRO (stands ouverts sous FCY) ; seuls les
-- profils qui portaient exactement les anciennes règles GT changent. Renvoie la liste des changements faits.
-- _preset : vrai pour un préréglage personnel (src/presets.lua) ; plus lu depuis la Beta 1.52, gardé pour ses appels.
-- Clés de règles apparues après les révisions qui jugent un jeu de règles : ignorées par ces révisions.
local keys18={safetyCarEscalation=true}
M.dataRevision=22
function M.migrateProfile(profile,p,from,_preset,out)
 out=out or {}
 if from<5 and equal(p.deltaTolerance,0.1) then p.deltaTolerance=M.defaults(profile).deltaTolerance; out[#out+1]=profile..':delta' end
 if from<6 and not M.solo(profile) and p.pitsClosed=='pitFcy' then
  p.pitsClosed='open'
  if M.ruleCategory(profile,p,keys18)=='GT' then out[#out+1]=profile..':regles GT' else p.pitsClosed='pitFcy' end
 end
 -- Révision 7 (Beta 1.12) : erreurs de pilotage dans toutes les sessions ; l'ancien défaut hors course (décoché)
 -- prend le nouveau, et la fréquence de la journée circuit restée à l'ancien défaut aussi.
 if from<7 and profile~='C' then
  if p.mistakesEnabled==false then p.mistakesEnabled=true end
  if M.solo(profile) and equal(p.mistakeRate,0.5) then p.mistakeRate=M.defaults(profile).mistakeRate end
 end
 -- Révision 8 (Beta 1.15) : un profil Hotlap encore vide et jamais réglé prend son défaut (onglet Règles seul).
 if from<8 and profile=='H' and not p.configured and not M.anySection(p) then p.section_rules=true end
 -- Révision 7 : carburant ; un jeu de règles F1 ou GT resté intact (lu avec le défaut, ravitaillement) le suit.
 if from<7 and not M.solo(profile) and p.pitFuel=='refuel' then
  p.pitFuel='plan'
  local category=M.ruleCategory(profile,p,keys18)
  if category~='F1' and category~='F1_2026' and category~='GT' then p.pitFuel='refuel' end
 end
 -- Révisions 10 et 11 (Beta 1.18 et 1.19) : voiture de sécurité en escalade, activée par défaut en course avec tous les
 -- jeux de règles (essais, qualifications et course, comme son interrupteur).
 if from<11 and not M.solo(profile) then p.safetyCarEscalation=true end
 -- Révision 12 (Beta 1.20) : espacement de la journée circuit élargi ; des valeurs restées aux anciens défauts les
 -- suivent, des valeurs réglées restent telles quelles.
 if from<12 then
  local moved=false
  for key,old in pairs(trafficOld) do if equal(p[key],old) then p[key]=M.defaults(profile)[key]; moved=true end end
  if moved and profile=='J' then out[#out+1]='J:espacement' end
 end
 -- Révision 16 (Beta 1.27) : départ de course du pilote ; des valeurs restées aux anciens défauts les suivent.
 if from<16 and profile=='C' then
  local moved=false
  for key,old in pairs(startMoved127) do if equal(p[key],old) then p[key]=M.defaults('C')[key]; moved=true end end
  if moved then out[#out+1]='C:depart' end
 end
 -- Révision 17 (Beta 1.29, demande du pilote) : appels de phares vus de plus loin et compris collé derrière ; des
 -- valeurs restées aux anciens défauts les suivent, des valeurs réglées restent telles quelles.
 if from<17 then
  local moved=false
  if equal(p.flashRange,flashOld128[profile]) then p.flashRange=M.defaults(profile).flashRange; moved=true end
  if equal(p.flashCloseAdvantage,flashCloseOld128[profile]) and not equal(p.flashCloseAdvantage,M.defaults(profile).flashCloseAdvantage) then p.flashCloseAdvantage=M.defaults(profile).flashCloseAdvantage; moved=true end
  if moved then out[#out+1]=profile..':phares' end
 end
 -- Révision 13 (Beta 1.24) : départ de course moins frileux ; des valeurs restées aux anciens défauts les suivent.
 if from<13 and profile=='C' then
  local moved=false
  for key,old in pairs(startOld) do if equal(p[key],old) then p[key]=M.defaults('C')[key]; moved=true end end
  if moved then out[#out+1]='C:depart' end
 end
 -- Révision 19 (Beta 1.42, demande du pilote) : stratégie et sanctions des IA ; un profil de week-end dont les règles de
 -- course sont cochées les reçoit cochées (Course : stratégie et sanctions ; Essais, Qualifications : sanctions).
 if from<19 and p.section_rules==true then
  if profile=='C' and not (p.section_strategy==true and p.section_sanctions==true) then p.section_strategy=true; p.section_sanctions=true; out[#out+1]='C:strategie et sanctions'
  elseif (profile=='P' or profile=='Q') and p.section_sanctions~=true then p.section_sanctions=true; out[#out+1]=profile..':sanctions' end
 end
 -- Révision 20 (Beta 1.47) : usure des pneus mesurée en jeu à 1 à 1,4 % par tour : le seuil de 75 % n'était jamais
 -- atteint ; un profil resté à l'ancien défaut prend le nouveau (30 %), une valeur réglée reste telle quelle.
 if from<20 and equal(p.strategyTyreWearPct,75) then p.strategyTyreWearPct=M.defaults(profile).strategyTyreWearPct; out[#out+1]=profile..':usure des pneus 30 %' end
 -- Révision 21 (Beta 1.49, demande du pilote) : attente au départ de course de 2 s au lieu de 1 ; un profil Course
 -- resté à l'ancien défaut prend le nouveau, une valeur réglée reste telle quelle.
 if from<21 and profile=='C' and equal(p.startDelay,1) then p.startDelay=M.defaults('C').startDelay; out[#out+1]='C:attente au depart 2 s' end
 return out
end
-- customs : préréglages personnels déjà lus (tableau de 1 à K.maxPresets, trous permis), pour la révision 22.
function M.migrate(g,profiles,customs)
 if g.dataRevision>=M.dataRevision then return nil end
 local upgraded={}
 -- Révision 4 (Beta 1.6) : première installation (aucune donnée enregistrée, aucun profil réglé) : comme un clic sur
 -- « Règles de base » ; Essais, Qualifications et Course reçoivent leur préréglage recommandé et les règles de base,
 -- la Journée circuit reste sans commande. Une installation existante n'est jamais modifiée.
 local fresh=g.dataRevision==0 and not g.presetsUsed
 -- Un profil compte comme réglé s'il l'est, ou si ses onglets diffèrent de son défaut (Hotlap : onglet Règles).
 for _,profile in ipairs(M.profiles) do
  local p=profiles[profile]
  if p.configured or M.sectionsChanged(profile,p) then fresh=false end
 end
 if g.dataRevision<1 then
  for _,profile in ipairs(M.profiles) do
   local p=profiles[profile]
   local name=M.legacyMatch(profile,p)
   if name then M.preset(name,profile,p); upgraded[#upgraded+1]=profile..':'..name else M.upgradeObstacles(p) end
  end
 end
 -- Révision 2 (1.5.0) : panneau de drapeaux seul, choix du pilote ; le drapeau jaune natif n'est plus imposé.
 if g.dataRevision<2 then for _,profile in ipairs(M.profiles) do profiles[profile].yellowHud=false end end
 -- Révision 3 (Beta 1.4) : jeux de règles réels.
 if g.dataRevision<3 then
  for _,profile in ipairs(M.profiles) do
   local name=M.migrateRules(profile,profiles[profile])
   if name and name~='base' then upgraded[#upgraded+1]=profile..':regles '..name end
  end
 end
 if fresh then M.applyRules('base',profiles) end
 for _,profile in ipairs(M.profiles) do M.migrateProfile(profile,profiles[profile],g.dataRevision,false,upgraded) end
 -- Révision 9 (Beta 1.16) : interface en anglais à la première installation ; une installation existante, utilisée
 -- jusque-là en français, le reste.
 if g.dataRevision<9 and not fresh then g.language='fr' end
 -- Révision 11 (Beta 1.19) : voiture de sécurité par défaut, la Ferrari 458 Italia Stage 3 du jeu de base, si aucune
 -- n'était choisie ; un modèle déjà choisi l'a été par le pilote.
 if g.dataRevision<11 and not fresh then g.safetyCarPicked=g.safetyCarModel~='' and g.safetyCarModel~=M.globalDefaults.safetyCarModel end
 if g.dataRevision<11 and g.safetyCarModel=='' then g.safetyCarModel=M.globalDefaults.safetyCarModel end
 -- Révision 13 (Beta 1.24) : radar avant (léger freinage d'appoint progressif) activé par défaut.
 if g.dataRevision<13 and g.useBrakeAssist==false then g.useBrakeAssist=true end
 -- Révision 14 (Beta 1.25) : sens latéral perdu (0 / 0) sur une installation existante, jamais remesuré depuis (une
 -- seule tentative par lancement) : aucun déplacement latéral n'était plus écrit. Il reprend la convention d'AC,
 -- -1 / -1, mesurée sur cette installation jusqu'à la Beta 1.8 ; la mesure la confirme ou la corrige ensuite.
 local restored=g.dataRevision<14 and not fresh and g.offsetSign==0 and g.sideSign==0
 if restored then g.offsetSign=-1; g.sideSign=-1 end
 -- Révision 15 (Beta 1.26, demande du pilote) : messages d'origine d'AC masqués par défaut, repris sur l'overlay.
 if g.dataRevision<15 then g.overlayBlockMessages=true end
 -- Révision 18 (Beta 1.37) : l'option globale des panneaux lumineux (Beta 1.32 à 1.36) devient la section propre de
 -- chaque profil ; l'option décochée par le pilote décoche la section partout (choix gardé). La clé globale n'est plus
 -- lue qu'ici.
 if g.dataRevision<18 and g.trackLights==false then for _,profile in ipairs(M.profiles) do profiles[profile].section_lights=false end end
 -- Révision 22 (Beta 1.52, relecture) : préréglage personnel chargé avant la Beta 1.51 (aucune marque « Perso ») : marqué
 -- une seule fois dans son profil, que le préréglage de la session ne le remplace pas.
 if g.dataRevision<22 and customs then local profile=M.markPersonal(g,customs); if profile then upgraded[#upgraded+1]=profile..':preset personnel garde' end end
 g.dataRevision=M.dataRevision
 return upgraded,fresh,restored
end
-- Règles d'une catégorie, appliquées ensemble aux profils Essais, Qualifications et Course : clés de l'onglet
-- Règles de course (hors préférences du pilote) et réglages de double jaune propres à une catégorie (delta de zone,
-- Slow Zone, repli) de chaque profil de week-end ; un profil jamais réglé reçoit d'abord son préréglage recommandé.
-- Ces clés forment un axe indépendant des préréglages de session, qui les conservent.
local zoneRuleKeys={zoneDeltaPct=true,slowZoneKmh=true,yellowSpeedKmh=true}
M.ruleSchema={}
M.keptKeySet={classPatterns=true}; for _,key in ipairs(M.preferenceKeys) do M.keptKeySet[key]=true end
for _,s in ipairs(M.schema) do if s.group=='rules' and not M.keptKeySet[s.key] or zoneRuleKeys[s.key] then M.ruleSchema[#M.ruleSchema+1]=s end end
M.ruleKeySet={}
for _,s in ipairs(M.ruleSchema) do M.keptKeySet[s.key]=true; M.ruleKeySet[s.key]=true end
-- Beta 1.29 (demande du pilote) : un préréglage intégré ou personnel règle tout son profil, règles de championnat
-- comprises ; il ne garde que les préférences du pilote et les motifs de classes, aussi ignorés pour le reconnaître.
M.presetKeptKeySet={classPatterns=true}; for _,key in ipairs(M.preferenceKeys) do M.presetKeptKeySet[key]=true end
-- Beta 1.51 : tuile d'un préréglage intégré allumée sans comparer les règles de championnat (réglées pour le week-end,
-- gardées par le préréglage de la session).
M.presetMatchSkip={}; for key in pairs(M.presetKeptKeySet) do M.presetMatchSkip[key]=true end; for _,s in ipairs(M.ruleSchema) do M.presetMatchSkip[s.key]=true end
-- Réglage gardé par « Restaurer » et par un préréglage intégré : préférences du pilote, motifs de classes et règles de
-- championnat choisies ; en journée circuit, qu'aucun jeu de règles ne règle, les règles reviennent aussi au défaut.
function M.kept(profile,key) return M.keptKeySet[key] and (not M.solo(profile) or not M.ruleKeySet[key]) end
local function ruleValue(values,s,profile) local value=values[s.key]; if value==nil then return s.defaults[profile] end return value end
function M.restore(profile,p)
 local kept={}
 for _,group in ipairs(M.sections) do kept['section_'..group]=p['section_'..group] end
 for key in pairs(M.keptKeySet) do if M.kept(profile,key) then kept[key]=p[key] end end
 M.validate(profile,M.defaults(profile),p)
 for key,value in pairs(kept) do p[key]=value end
 M.validate(profile,p,p)
 return p
end
local function applyValues(category,profile,p) for _,s in ipairs(M.ruleSchema) do p[s.key]=ruleValue(M.rulePresets[category],s,profile) end end
-- Interrupteurs de l'onglet Règles de course (Beta 1.18) : arrêt obligatoire et voiture de sécurité, réglés ensemble pour
-- les Essais, Qualifications et Course comme les jeux de règles ; un profil jamais réglé reçoit d'abord son préréglage
-- recommandé. Beta 1.51 : arrêt obligatoire oui ou non (1 ou 0).
function M.weekendSwitch(profiles,key,on)
 for _,profile in ipairs(M.ruleProfiles) do
  local p=profiles[profile]
  if not (p.configured or M.anySection(p)) and M.recommended[profile] then M.preset(M.recommended[profile],profile,p) end
  if key=='mandatoryStops' then p.mandatoryStops=on and 1 or 0 else p[key]=on==true end
  p.configured=true
  M.validate(profile,p,p)
 end
end
-- Beta 1.59 : jeu de règles figé pendant une course lancée (feux éteints, pas encore finie) : fenêtre d'arrêt,
-- pénalités et neutralisation en cours ne doivent jamais devenir incohérentes. Raccourci de l'accueil seulement.
function M.rulesLocked(profile,frame)
 return profile=='C' and frame~=nil and frame.started==true and frame.finished~=true
end
function M.applyRules(category,profiles)
 if not M.rulePresets[category] then return false end
 for _,profile in ipairs(M.ruleProfiles) do
  local p=profiles[profile]
  if not p.configured and not M.anySection(p) and M.recommended[profile] then M.preset(M.recommended[profile],profile,p) end
  applyValues(category,profile,p)
  p.section_rules=true; p.configured=true
  M.validate(profile,p,p)
 end
 return true
end
-- Beta 1.29 : préréglage d'essais, de qualifications ou de course : ses règles de championnat valent pour tout le
-- week-end, comme un jeu de règles ou un interrupteur de l'onglet Règles de course. Seules les valeurs sont copiées
-- (onglet Règles laissé tel quel, profil jamais réglé laissé tel quel : son préréglage recommandé les garde ensuite).
-- Journée circuit et hotlap n'y touchent jamais.
function M.spreadRules(from,profiles)
 if M.solo(from) then return false end
 local source=profiles[from]
 for _,profile in ipairs(M.ruleProfiles) do
  local p=profiles[profile]
  if profile~=from then
   for _,s in ipairs(M.ruleSchema) do p[s.key]=source[s.key] end
   M.validate(profile,p,p)
  end
 end
 return true
end
-- Marques des préréglages, une par profil (« J=Nordschleife,C=Endurance,Q=Perso ») : préréglage intégré allumé pour le
-- profil qu'il règle, après un clic du pilote (Beta 1.29) ou appliqué comme préréglage de la session (Beta 1.51) ;
-- « Perso » (M.personalMark) : préréglage personnel chargé ou enregistré dans ce profil, jamais remplacé par la session.
function M.mark(g,profile)
 for x,name in (g.builtinMarks or ''):gmatch('(%u)=(%w+)') do if x==profile then return name end end
 return ''
end
function M.setMark(g,profile,name)
 local parts={}
 for _,x in ipairs(M.profiles) do local value=x==profile and (name or '') or M.mark(g,x); if value~='' then parts[#parts+1]=x..'='..value end end
 g.builtinMarks=table.concat(parts,',')
end
-- Beta 1.51 (demande du pilote) : préréglage intégré allumé et appliqué dès qu'une session est détectée (essais :
-- Essais libres, qualifications : Qualifications tour lancé, course : Course réaliste, journée circuit, Nordschleife
-- comprise : Nordschleife Touristenfahrten). Un autre préréglage intégré choisi par le pilote pour ce profil (Endurance
-- multi-classes) est gardé ; un préréglage personnel chargé dans ce profil (marque « Perso ») n'est jamais remplacé ;
-- hotlap : aucun. Inverse la règle de la Beta 1.29 (préréglage recommandé appliqué une seule fois, sans tuile allumée).
local builtinProfiles={Nordschleife={J=true},Circuit={J=true},Essais={P=true},Qualifications={Q=true},Course={C=true},Endurance={J=true,C=true}}
M.personalMark='Perso'
-- Beta 1.52 (relecture, révision 22) : dernier préréglage chargé personnel (« custom:<nom> ») encore présent dans la
-- bibliothèque customs : marque « Perso » posée dans le profil de son entrée ; renvoie ce profil, ou nil.
function M.markPersonal(g,customs)
 local name=type(g.loadedPreset)=='string' and g.loadedPreset:match('^custom:(.+)$')
 if not name then return nil end
 for i=1,M.K.maxPresets do
  local entry=customs[i]
  if entry and entry.name==name then M.setMark(g,entry.profile,M.personalMark); return entry.profile end
 end
 return nil
end
-- Beta 1.59 : journée circuit : Nordschleife Touristenfahrten sur la Nordschleife (nom avec « nordschleife », ou
-- « nurburgring » / « nuerburgring » de plus de K.nordschleifeMinLength m), Journée circuit partout ailleurs.
function M.isNordschleife(track,length)
 local name=tostring(track or ''):lower()
 if name:find('nordschleife',1,true) then return true end
 return (name:find('nurburgring',1,true) or name:find('nuerburgring',1,true)) and (tonumber(length) or 0)>M.K.nordschleifeMinLength or false
end
function M.trackDayPreset(track,length) return M.isNordschleife(track,length) and 'Nordschleife' or 'Circuit' end
function M.sessionPreset(g,profile,track,length)
 if profile=='H' or not M.recommended[profile] then return nil end
 local mark=M.mark(g,profile)
 if mark==M.personalMark then return nil end
 if profile=='J' and track~=nil and (mark=='Nordschleife' or mark=='Circuit' or not builtinProfiles[mark]) then return M.trackDayPreset(track,length) end
 if builtinProfiles[mark] and builtinProfiles[mark][profile] then return mark end
 return M.recommended[profile]
end
-- Préréglage intégré name chargé dans le profil : préférences du pilote et motifs de classes gardés. keepRules (préréglage
-- de la session, appliqué tout seul) : règles de championnat du profil gardées (jeu de règles, arrêt obligatoire, voiture
-- de sécurité réglés pour le week-end), rien n'est copié aux autres profils. Sinon (clic du pilote, Beta 1.29) : règles
-- du préréglage, valables pour tout le week-end.
function M.applyBuiltin(g,profiles,name,profile,keepRules,kept,track,length)
 local p=profiles[profile]; kept=kept or {}
 for key in pairs(kept) do kept[key]=nil end
 for key in pairs(M.presetKeptKeySet) do kept[key]=p[key] end
 if keepRules then for _,s in ipairs(M.ruleSchema) do kept[s.key]=p[s.key] end end
 M.preset(name,profile,p,track,length)
 for key,value in pairs(kept) do p[key]=value end
 M.validate(profile,p,p)
 if not keepRules then if name=='Endurance' and profile=='C' then M.applyRules('Endurance',profiles) else M.spreadRules(profile,profiles) end end
 g.loadedPreset='builtin:'..name; g.presetsUsed=true; M.setMark(g,profile,name)
end
-- Préréglage intégré portant un jeu de règles (Endurance en course), pour le reconnaître.
function M.withRules(category,profile,p) applyValues(category,profile,p); return M.validate(profile,p,p) end
-- Axe et jeux de règles de la Beta 1.3, figés : un profil enregistré resté sur l'un d'eux reçoit sa version Beta 1.4.
local axis13={'noMoveBraking','neutralization','majorIncidentTime','fcySpeedKmh','fcyDeltaPct','vscDeltaPct','neutralizationHold',
 'redFlagEnabled','redFlagCars','redFlagSpeedKmh','redDeltaPct','redFlagHold','mandatoryStops','pitWindowOpenPct',
 'pitWindowClosePct','pitTyres','pitCompoundChange','minPitTime','maxStintMin','pitMessage','overtakeMode','overtakeModeGap',
 'overtakeModeBoostPct','rulesDrs','rulesDrsLaps','aiDrs','bopEnabled','bopStrengthPct','proAmEnabled','predictableSlowClass','yellowSpeedKmh'}
local presets13={base={},F1={neutralization='vsc',mandatoryStops=1,pitWindowOpenPct=20,pitWindowClosePct=80,pitCompoundChange=true,overtakeMode=true},
 GT={neutralization='fcy',mandatoryStops=1,pitWindowOpenPct=30,pitWindowClosePct=70,minPitTime=50,bopEnabled=true,proAmEnabled=true},
 Endurance={neutralization='fcy',yellowSpeedKmh=80,maxStintMin=50,bopEnabled=true,proAmEnabled=true,predictableSlowClass=true}}
local schemaByKey={}; for _,s in ipairs(M.schema) do schemaByKey[s.key]=s end
local oldZoneDelta=70
local function category13(profile,p)
 for _,name in ipairs({'base','F1','GT','Endurance'}) do
  local values=presets13[name]; local same=true
  for _,key in ipairs(axis13) do
   local expected=values[key]; if expected==nil then expected=schemaByKey[key].defaults[profile] end
   if not equal(p[key],expected) then same=false; break end
  end
  if same then return name end
 end
 return nil
end
-- Profil (ou préréglage personnel) enregistré avant la Beta 1.4 : un jeu de règles de la Beta 1.3 resté intact devient
-- celui de la Beta 1.4 (F1 : F1 2025) ; le double jaune quitte l'ancien défaut (+70 %), un réglage du pilote est gardé.
-- Renvoie la catégorie appliquée, ou nil.
function M.migrateRules(profile,p)
 local zone=p.zoneDeltaPct
 local name=not M.solo(profile) and category13(profile,p) or nil
 if name then applyValues(name,profile,p) end
 if not equal(zone,oldZoneDelta) then p.zoneDeltaPct=zone elseif not name then p.zoneDeltaPct=schemaByKey.zoneDeltaPct.defaults[profile] end
 return name
end
-- skip : clés ignorées (révisions antérieures à ces clés).
-- Jeu de règles le plus proche (le moins de réglages différents ; à égalité, le premier de la liste) : réinitialisation d'un
-- jeu retouché (Beta 1.19).
function M.closestRuleCategory(profile,p,skip)
 local best,count=nil,math.huge
 for _,category in ipairs(M.ruleCategories) do
  local values=M.rulePresets[category]; local n=0
  for _,s in ipairs(M.ruleSchema) do if not (skip and skip[s.key]) and not equal(p[s.key],ruleValue(values,s,profile)) then n=n+1 end end
  if n<count then best,count=category,n end
 end
 return best
end
function M.ruleCategory(profile,p,skip)
 for _,category in ipairs(M.ruleCategories) do
  local values=M.rulePresets[category]; local same=true
  for _,s in ipairs(M.ruleSchema) do
   if not (skip and skip[s.key]) and not equal(p[s.key],ruleValue(values,s,profile)) then same=false; break end
  end
  if same then return category end
 end
 return nil
end
-- Modes Content Manager : Journée circuit = session « Track Day » de type essais ; Essai et essais d'un
-- week-end = essais déclarés sous un autre nom. Sans race.ini lisible, les essais restent en Journée circuit.
function M.autoProfile(frame)
 local declared=frame.configType~=nil and frame.configType>=1 and frame.configType<=7
 local kind=declared and frame.configType or frame.type
 -- Journée circuit Content Manager : session « Track Day », déclarée en essais (TYPE 1, 66 race.ini archivés) ou en
 -- qualifications (TYPE 2, relevé le 29 octobre 2026) ; jamais prise pour des qualifications.
 if declared and frame.configTrackDay and (kind==1 or kind==2) then return 'J' end
 if kind==3 then return 'C' elseif kind==2 then return 'Q' end
 if kind==1 and declared and not frame.configTrackDay then return 'P' end
 -- Hotlap, time attack, drift, drag : sessions sans IA, profil Hotlap.
 if kind>=4 and kind<=7 then return 'H' end
 return 'J'
end
-- Beta 1.59 (H-A, décision du pilote) : vrais passages en piste des IA (src/runs.lua). Qualifications : un tour lancé
-- (un second, rarement, si le premier est gâché), attente à l'emplacement ; essais : programme tiré au sort (poids).
local k159ha={runsSalt=15901,runsWeights={quali=0.30,long=0.25,tyre=0.15,fuel=0.15,setup=0.15},runsSecondChance=0.35,
 runsLongMin=8,runsLongMax=14,runsTyreMin=4,runsTyreMax=7,runsFuelMin=5,runsFuelMax=8,runsSetupMin=2,runsSetupMax=3,
 runsTimeMargin=1.1,runsFuelReserveLaps=1.5,runsHeavyLaps=10,runsLongFuelMargin=1.05,
 runsBoxQMin=60,runsBoxQMax=150,runsBoxPMin=90,runsBoxPMax=300,runsConcurrent=3}
for key,value in pairs(k159ha) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.59 (fourche H-B) : stratégies de départ variées (src/startvar.lua) et arrêt aux stands pour dégâts
-- (src/damagepit.lua). Dureté des gommes d'après leurs noms : nom long (sans espaces ni tirets, motif le plus précis
-- d'abord), puis nom court ; rang plus bas = plus tendre. Seuils de dégâts estimés (docs/VALIDATION.md).
local k159hb={startVarietyShare=0.4,startVarietyBias=0.3,startVarietySalt=1597,startVarietyPlaces=64,compoundPirelliBase=8,
 compoundHardnessLong={{'hyper',0},{'ultra',1},{'extrasoft',2},{'supersoft',2},{'soft',3},{'medium',4},{'extrahard',6},{'superhard',6},{'hard',5}},
 compoundHardnessShort={HS=0,US=1,ES=2,SS=2,S=3,M=4,H=5,EH=6,SH=6},
 damagePitScanPeriod=2,damagePitBody=80,damagePitSuspension=0.08,damagePitGearbox=0.3,damagePitEngine=700,damagePitConfirm=3,
 damagePitMinLapsLeft=2,damagePitUnsafe=0.3,damagePitRegrowBody=40,damagePitRegrowSuspension=0.05,
 damagePitRegrowEngine=150}
for key,value in pairs(k159hb) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.59 : stratégies de départ variées, course seulement (arrêt pour dégâts masqué en journée circuit et en hotlap : M.hidden).
M.raceKeys.strategyStartVariety=true
-- Beta 1.59 (export/import) : fichier des préréglages et réglages des profils (src/presetfile.lua) : version du format,
-- taille lue au plus (octets), dossier dans Documents\Assetto Corsa et nom du fichier.
local k159hc={presetFileFormat=1,presetFileMaxBytes=524288,presetFolder='AdvancedIA',presetFileName='AdvancedIA-presets.ini'}
for key,value in pairs(k159hc) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.59 (trafic des journées circuit, 10 novembre) : hors course, IA lente au rythme habituel inconnu jugée sous
-- slowUnknownRatio fois l'allure de sa classe ; cession refusée seulement à un suiveur plus lent de yieldRefuseKmh km/h ;
-- en cession, vitesse de pointe sous celle du suiveur (yieldPassDeltaKmh de moins), suiveur suivi jusqu'à
-- yieldCapGapOff m, baisse à yieldCapDecelOff km/h par seconde, levée à yieldCapReleaseKmh km/h par seconde ; limite
-- levée après yieldQueueTime s avec deux voitures en file ; file d'une voiture lente remontée sur slowQueueLinks voitures ;
-- Journée circuit hors Nordschleife (plus de nordschleifeMinLength m pour un Nürburgring) ; radar : marge radarClearMargin m
-- pour une voiture qui se range ; priorité à l'entrée du virage au nez devant de plus de cornerNoseMargin m (décidée dans
-- les cornerEntryWindow s, lever de pied à cornerGiveLift par cornerLiftRate par seconde, sans voiture à moins de
-- cornerGiveBackGap m derrière, pas de nouvelle attaque pendant cornerGiveHold s).
local k159t={slowUnknownRatio=0.5,yieldRefuseKmh=3,yieldPassDeltaKmh=15,yieldCapGapOff=40,yieldCapDecelOff=6,nordschleifeMinLength=15000,radarClearMargin=0.3,radarOpenRate=0.5,radarLatTau=0.2,radarOpenHold=0.15,corridorLeadMargin=1.5,cornerPhaseGap=0.5,yieldQueueTime=3,slowQueueLinks=6,cornerNoseMargin=2.2,cornerGiveLift=0.8,cornerGiveHold=1.5,cornerEntryWindow=1,cornerGiveBackGap=20,cornerLiftRate=1,yieldCapReleaseKmh=8,yieldCapReleaseMargin=15}
for key,value in pairs(k159t) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.60 (étape de base). Visibilité des neuf réglages : course seulement (stratégie avancée, départ, collisions du
-- joueur) ; collisions des IA : essais, qualifications et course (M.sanctionKeys).
M.raceKeys.strategySmart=true; M.raceKeys.raceStart=true
M.sanctionKeys.sanContact=true; M.sanctionKeys.sanPlayerContact=true; M.sanctionRaceKeys.sanPlayerContact=true
for _,key in ipairs({'sanContact','sanPlayerContact'}) do M.sanctionSwitches[#M.sanctionSwitches+1]=key end
-- Réglages en attente de leur tranche : jamais montrés (src/groups.lua, M.hidden) et tenus à leur valeur par défaut tant que la
-- tranche qui les fait agir n'est pas livrée (règle du pilote : aucun réglage visible sans effet). Chaque tranche
-- supprime SA ligne ci-dessous, et seulement elle ; une version publiée sans une tranche garde la ligne de celle-ci.
M.pendingKeys={}
do
 local effective=M.effective
 local default={}; for _,s in ipairs(M.schema) do default[s.key]=s.defaults end
 function M.effective(profile,p,out)
  out=effective(profile,p,out)
  for key in pairs(M.pendingKeys) do out[key]=default[key][profile] end
  return out
 end
end
-- Constantes lues par plusieurs tranches de la Beta 1.60 (blocs des tranches : k160a à k160e, ajoutés après celui-ci).
local k160={rollCallDistance=500}
for key,value in pairs(k160) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.60, tranche B : responsabilité des collisions (src/blame.lua). Positions relevées toutes les blameSample s ;
-- frottement sous blameMinKmh km/h d'écart sans suite : personne ; départ : blameStartGrace s, sauf choc par l'arrière
-- à plus de blameStartKmh km/h ; carambolage : voiture déjà touchée par une autre depuis moins de blameChain s ; retour
-- en piste depuis moins de blameRejoin s ; changement de ligne : au moins blameMoveMin m en blameCutTime s et
-- blameMoveRatio fois plus que l'autre ; suites jugées blameOutcome s après (grave : perte de contrôle, sortie, ou
-- blamePlaces places perdues) ; blameWarnings avertissements ; drive-through si l'autre reste arrêtée blameOutTime s ;
-- un dossier par paire, rouvert blamePairGap s après la dernière image de contact.
local k160b={blameSample=0.25,blameMinKmh=3,blameStartGrace=20,blameStartKmh=30,blameChain=2,blameRejoin=3,blameCutTime=1,blameMoveRatio=2,blameOutcome=6,
 blamePlaces=2,blameWarnings=2,blameOutTime=15,blameMoveMin=1,blamePairGap=3}
for key,value in pairs(k160b) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.60, tranche C (réglages fineInputs et dynamicPersona, src/mood.lua, src/mistakes.lua). Remise des gaz en sortie
-- de virage : sortie reconnue quand la rectitude repasse exitCornerFrom après exitMinCorner s en virage, accélérateur à
-- exitGas au moins ; plafond de exitFromPro (professionnel) à exitFromAm (amateur), rendu en exitTimePro à exitTimeAm s
-- (allongé de exitWetGain sur piste mouillée, raccourci de exitPassFactor en dépassement), jamais sous exitFromRear avec
-- une voiture collée derrière, écrit par pas de exitStep ; après un gros freinage, roue libre à coastThrottle pendant au
-- plus coastTimeAm s (amateur). Erreur à la limite : dérive de limitSlipDeg degrés tenue limitSlipTime s en sortie, une
-- chance limitChance (× le risque du pilote), patinage de gravité limitSeverity pendant limitTimeMin à limitTimeMax s, au
-- plus une par IA toutes les limitCooldown s. Style du pilote : grade pour styleGradeShare, le reste selon l'assurance.
-- Humeur : stress (suiveur à moins de moodPressTime s depuis moodPressHold s : moodStressRise par seconde ; contact,
-- erreur, place perdue), retombée en moodStressDecay s (× moodDecayPro à moodDecayAm), gains moodGainPro à moodGainAm ;
-- fatigue : relais de moodFatigueStint s, plus moodFatigueRace sur la course, moodFatigueRest rendu par un arrêt ;
-- agressivité selon la phase de la course (phaseEarly jusqu'à phaseEarlyEnd, phaseLate sur les phaseLateShare derniers) ;
-- effets bornés (moodAggrMin à moodAggrMax) ; une ligne de journal par IA au plus toutes les moodLogGap s.
local k160c={exitCornerFrom=0.5,exitMinCorner=0.6,exitGas=0.5,exitFromPro=0.85,exitFromAm=0.7,exitTimePro=0.4,exitTimeAm=1.4,exitWetGain=0.5,exitPassFactor=0.5,exitFromRear=0.9,exitStep=0.05,coastBrake=0.1,coastThrottle=0.5,coastTimeAm=0.3,limitSlipDeg=6,limitSlipTime=0.3,limitChance=0.08,limitSeverity=0.75,limitTimeMin=0.2,limitTimeMax=0.5,limitCooldown=90,styleGradeShare=0.7,
 moodPressTime=0.6,moodPressHold=2,moodStressRise=0.05,moodStressContact=0.3,moodStressMistake=0.2,moodStressPlace=0.15,moodStressDecay=45,moodDecayPro=0.7,moodDecayAm=1.3,moodGainPro=0.7,moodGainAm=1.3,moodFatigueStint=3600,moodFatigueRace=0.3,moodFatigueRest=0.5,phaseEarly=0.95,phaseEarlyEnd=0.1,phaseLate=1.08,phaseLateShare=0.15,moodAggrGain=0.12,moodAggrMin=0.85,moodAggrMax=1.15,moodCautionStress=0.1,moodCautionFatigue=0.08,moodLevelFatigue=0.012,moodRiskStress=0.5,moodLapseFatigue=0.3,moodLogGap=120,moodLogStress=0.6,moodLogFatigue=0.6,moodPeriod=1,moodStepMax=2}
for key,value in pairs(k160c) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.60, tranche D (réglages wearPace et strategySmart). Temps perdu aux stands appris (moyenne glissante pitLossAlpha,
-- voie entre pitLossMin et pitLossMax s, journal à chaque variation de pitLossLogStep s, tour neutralisé appris sur les
-- voitures à plus de pitLossMinSpeed m/s) ; rival à moins de smartRivalGap s ; sortie des stands : arrêt dû,
-- voiture plus lente de rejoinSlowPct à moins de rejoinAhead s, file de rejoinTrain voitures dans
-- rejoinTrainSpan s, arrêt retardé de rejoinDelayMax tours au plus ; neutralisation : arrêt peu coûteux à partir de
-- scMinWear × le seuil d'usure et de scGainMin s gagnées, décision des audacieux (arrêt à plus de scStayOutLaps tours)
-- après scDecideDelay s, restent en piste si scStayOutShare des voitures devant sont appelées ; clé de SpotterEnginer
-- (seStrategyKey, seStrategyBytes octets, figée après seStrategyStale s, gain et perte bornés à seStrategyMax s) ; clé
-- publiée strategyPubKey, au plus toutes les strategyPubPeriod s. Rythme : usure sans effet sous wearPaceStart, perte
-- wearPaceAtThreshold au seuil puis wearPaceCliff à 100 % ; compoundPaceStep par cran de gomme (compoundPaceMax au plus) ;
-- fuelPace entre réservoir plein et vide ; surchauffe de wearHotDelta °C tenue wearHotTime s : wearHotPct ; total entre
-- -wearScaleMaxLoss et +wearScaleMaxGain, étalé à wearScaleRate par seconde, revu toutes les wearPeriod s ; freinages plus
-- prudents de wearBrakeCaution, remise des gaz plus longue de wearExitGain ; journal par pas de wearLogStep, espacé de
-- wearLogGap s.
local k160d={pitLossAlpha=0.3,pitLossMin=8,pitLossMax=120,pitLossLogStep=1,pitLossMinSpeed=5,smartRivalGap=1.5,rejoinAhead=4,rejoinSlowPct=0.01,rejoinTrain=3,rejoinTrainSpan=6,rejoinDelayMax=2,
 scMinWear=0.5,scGainMin=8,scStayOutLaps=6,scStayOutShare=0.5,scDecideDelay=1,seStrategyKey='SpotterEnginer.strategy',seStrategyBytes=160,seStrategyStale=6,seStrategyMax=600,
 strategyPubKey='AdvancedIA.strategy',strategyPubPeriod=1,
 wearPaceStart=0.3,wearPaceAtThreshold=0.015,wearPaceCliff=0.04,compoundPaceStep=0.0035,compoundPaceMax=0.007,fuelPace=0.012,wearHotDelta=15,wearHotTime=10,wearHotPct=0.005,
 wearScaleMaxLoss=0.05,wearScaleMaxGain=0.01,wearBrakeCaution=0.08,wearExitGain=0.5,wearScaleRate=0.01,wearLogStep=0.005,wearLogGap=60,wearPeriod=1}
for key,value in pairs(k160d) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.60, tranche E (départ de la course : tour de formation, départ lancé). formationMaxLength : au-delà, le tour
-- durerait plus que K.neutralMax ; allure de la tête : max(fcySpeedKmh, formationMinKmh) x formationSpeedMult ;
-- rollGreenBefore : drapeau vert du départ lancé quand la tête est à cette distance de la ligne ; rollClearAhead :
-- aucun vert avec un incident à moins de cette distance après la ligne (formationExtraLaps tour(s) de plus au
-- maximum) ; rollT1Min / rollT1Max : premier virage attentif imposé après un départ lancé (fin au premier freinage
-- terminé, jamais avant rollT1Min s, au plus rollT1Max s).
local k160e={formationMaxLength=7500,formationMinKmh=80,formationSpeedMult=1.25,formationExtraLaps=1,rollGreenBefore=100,rollClearAhead=400,rollT1Min=4,rollT1Max=25}
for key,value in pairs(k160e) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.60 (fusion des tranches) : formationGrace : délai après le feu vert d'AC pendant lequel le joueur n'est pas jugé
-- pour un dépassement au tour de formation (envol).
local k160m={formationGrace=8}
for key,value in pairs(k160m) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.59.1 (rapport de bedstyboi, Donington, 11 novembre) : distance à la trajectoire lue pour une voiture hors piste
-- sous offLineKmh km/h (dégagement des voitures arrêtées hors piste, qui n'était jugé qu'au départ d'une course) ;
-- voiture en incident en piste qui ne s'éloigne pas de K.stuckRadius m en trackWedgedTime s : dépannée ; voiture
-- accidentée ou tout juste repartie : dépassable sous drapeau pendant passAfterIncident s ; écart latéral selon le sens
-- de la piste (drapeau rouge, piste bloquée) : second point de la trajectoire lineAheadMeters m plus loin.
local k159n={offLineKmh=25,trackWedgedTime=45,passAfterIncident=30,lineAheadMeters=5}
for key,value in pairs(k159n) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.60, tranche A (src/rear.lua, src/director.lua). Conscience de l'arrière : rapprochement minimal (km/h), horizon
-- (s, du pilote le moins au plus attentif), tenue du côté (s), arrivée rapide (km/h, s au contact, portée en m, part de
-- la confirmation), attaquant déjà décalé (m), prudence de l'intention, mouvement noté au journal (m). Voiture collée
-- derrière : distance minimale (m), temps (s), éloignement permis (km/h). Régulateur sans coup de frein : descente de
-- l'accélérateur (par s) et plancher, descente de la limite de vitesse (km/h par s), du niveau (par s), frein du radar
-- au plus, dernier recours (s au contact), montée de la prudence (par s). Aide au dépassement : écart latéral et
-- distance de l'engagement (m), ligne tenue (s), gain de niveau, durée (s), attente par paire (s), cible qui s'éloigne
-- (km/h), minuteries retenues (s).
local k160a={rearMinSa=5,rearHorizonMin=1,rearHorizonMax=2,rearHold=0.5,rearFastSa=25,rearYieldTtc=6,rearFastRange=250,rearFastConfirm=0.5,defensePulledLat=2.2,intentCaution=1.1,rearLogMove=0.05,rearCloseMin=8,rearCloseTime=0.7,rearCloseSa=10,rearThrottleRate=0.6,rearThrottleFloor=0.7,rearCapDecel=6,rearLevelRate=0.03,rearBrakeMax=0.12,rearLastTtc=0.8,rearCautionRate=0.5,commitLat=1.5,commitGap=8,holdLineTime=1.5,passAidLevel=0.015,passAidMax=6,passAidPairCooldown=30,passAidSaMax=5,passAidHold=4,passReopenSa=25,passReopenWait=10,yieldOverallMargin=0.01,yieldRefuseOverallKmh=8,passMinRoom=1.2}
for key,value in pairs(k160a) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.60 (fusion, relecture indépendante et journaux du 11 novembre).
-- Borne de décalage vers le grand côté de la piste (src/director.lua, M.reachable) : part du côté au plus, mètres hors
-- de la trajectoire au plus, marge au bord (m, en plus de la demi-voiture) ; largeurs lues plus loin (s, s, m au moins).
-- Jugement des collisions : période de lecture de l'écart latéral à la piste (s) ; virage : accélération latérale (m/s²).
-- Voiture lente : déplacement (m) sous lequel la distance à la trajectoire n'est pas relue.
-- SpotterEnginer : première version qui connaît le tour de formation et le départ lancé (X, Y, Z).
-- Voiture en difficulté sous drapeau : part de l'allure permise sous laquelle elle l'est, durée (s).
-- Côté sans place (m de décalage permis) : cession ou dépassement de l'autre côté ; côté de piste compté au plus (m) ;
-- durée (s) d'une réouverture de l'attente après deux échecs.
local k160m2={reachWideShare=0.8,reachWideMeters=4,reachEdgeMargin=0.5,reachLook1=1,reachLook2=2,reachLookMin=15,blameLatPeriod=0.1,blameCornerG=3,lineStill=0.05,seStartMinMajor=1,seStartMinMinor=3,seStartMinPatch=4,troubleRatio=0.5,troubleTime=3,sideMinRoom=1,reachSideMax=6,passReopenHold=8,reachLookPeriod=0.1,reachLookStagger=0.016}
for key,value in pairs(k160m2) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.60 (course de Bakou du 11 novembre, décisions du pilote) : voiture de sécurité à son allure libre (réglage
-- « Vitesse de la voiture de sécurité » retiré). scNominalKmh : allure nominale gardée pour ce qui a besoin d'un nombre
-- (peloton sous l'allure d'appel, durée des stands fermés, attente du regroupement, retour au stand après le vert) ;
-- scCatchPct : rattrapage des voitures hors de la file, à leur allure propre plus lente de ce pourcentage ; scPacePct :
-- allure libre bornée à l'allure de la voiture juste derrière elle, plus lente de ce pourcentage (jamais un peloton
-- distancé par une voiture de sécurité plus rapide que lui) ; scWatch : portée (m) de la surveillance « doublée » ;
-- scOverlapDrop : km/h de moins qu'elle pour une voiture à sa hauteur ; scPassedMax : délai (s) pour rendre la place ;
-- scLeaveStill : immobile à son emplacement depuis ce délai (s) après sa libération : posée en piste sans attendre
-- scLeaveMax ; scBunchGap : écart (m) au plus entre deux voitures de la file ; scBunchLaps : tours (à scNominalKmh)
-- d'attente du regroupement au plus avant « rentre ce tour ».
local k160s={scNominalKmh=120,scCatchPct=10,scPacePct=25,scWatch=200,scOverlapDrop=10,scPassedMax=60,scLeaveStill=10,scBunchGap=150,scBunchLaps=1}
for key,value in pairs(k160s) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.60, lot 3 (essais du pilote du 11 novembre : les IA s'écartent mais la voiture de derrière hésite, on arrive au
-- virage suivant et tout recommence ; tours de chauffe impossibles à distinguer des tours lancés).
-- Passage franc : cible qui cède à cette IA et vraiment sortie de la trajectoire (frankOffM m de décalage, ou
-- frankClear m de jeu latéral entre les deux voitures) : tentative lancée sans délai de confirmation, gain de niveau
-- borné (frankLevel pendant frankMax s), la voiture qui cède lève franchement le pied tant que l'attaquant engagé est
-- à sa hauteur ou à moins de frankLiftGap m (frankDeltaKmh km/h sous lui en ligne droite, à la rampe
-- ordinaire de la cession ; frankYieldLevel de niveau en moins ailleurs), jamais avec une autre voiture dans sa file à moins de
-- frankThirdGap m derrière elle ; la cession dure au plus frankYieldExtra s de plus tant que l'attaquant est là.
-- Tours de chauffe : qualiOutLevel de niveau en moins pendant le tour de sortie des essais et qualifications (rampe de
-- qualiOutRamp s) ; qualiYieldLead : voiture lancée vue jusqu'à ce temps (s) derrière une voiture qui ne l'est pas.
-- nameRefresh : période (s) de mise à jour du niveau et de l'agressivité affichés après le nom d'un pilote.
-- frankTracePeriod, frankTraceGap : ligne de suivi d'un dépassement sur cession (toutes les frankTracePeriod s, cible à
-- moins de frankTraceGap m) : vitesses, niveaux et limites des deux voitures (quelle limite retient l'attaquant).
local k160w={frankOffM=1,frankClear=0.4,frankLevel=0.02,frankMax=8,frankDeltaKmh=30,frankLiftGap=20,frankThirdGap=25,frankYieldLevel=0.06,frankYieldExtra=15,
 qualiOutLevel=0.12,qualiOutRamp=3,qualiYieldLead=6,nameRefresh=1,frankTracePeriod=2,frankTraceGap=30}
for key,value in pairs(k160w) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.60 (lot 4) : « cible plus rapide » jugé sur l'écart en temps (abortTgGrow s de plus que le plus petit de la
-- tentative ; vitesse d'au moins abortTgSpeed m/s pour le calcul) ; réouverture d'une attente en course après
-- passReopenWaitRace s.
-- Relecture du lot 3 : sideFollowerLat m (suiveur déjà décalé), teleportPath (saut en multiples du chemin parcouru),
-- scDownKmh (voiture de sécurité en difficulté).
local k160x={abortTgGrow=0.1,abortTgSpeed=10,passReopenWaitRace=20,sideFollowerLat=1,teleportPath=1.5,scDownKmh=40,frankCapMinKmh=50}
for key,value in pairs(k160x) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.60, lot 5 (course du pilote du 11 novembre au Nürburgring, relecture du lot 3) : attente d'un dépassement
-- bornée en course, journal des drapeaux bleus entre IA, voiture de sécurité (allure libre bornée et hystérésis, attente
-- du regroupement, enveloppe de freinage du rattrapage, place non rendue), voiture en difficulté en tête de file
-- seulement, arrêt obligatoire étalé pour un plan limité par les pneus.
local k160y={passSoonShare=1,passIgnoreMaxRace=180,scFreeMargin=20,scFreeGap=80,scBunchMax=180,scGiveNear=15,scGiveStuck=8,scGiveFloor=60,troubleAheadGap=30,planSpreadLaps=2}
for key,value in pairs(k160y) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.61 (étape de base). Réglage global « Mémoire des circuits » (coupé ; options globales). Départs réalistes :
-- course seulement. Réglages en attente de leur tranche, comme en 1.60 : jamais montrés, tenus à leur défaut ; chaque
-- tranche supprime SA ligne ci-dessous, et seulement elle (trackMemory : la première des tranches A et B livrée).
M.globalDefaults.trackMemory=false
M.raceKeys.startRealism=true
-- Relecture d'ensemble 1.62 : réglages affichés là où ils n'ont aucun effet. Départ arrêté et premier tour attentif : course
-- seulement (lus avec profile=='C') ; espacement : journée circuit seulement (src/traffic.lua) ; cession ordinaire et
-- pression : hors course seulement (les drapeaux bleus gardent leurs propres réglages). Masqués dans l'interface seulement
-- (M.uiHidden) : jamais remis à leur défaut par M.validate, pour ne rien changer aux valeurs enregistrées ni à la
-- reconnaissance des anciens préréglages.
M.startUiKeys={startDelay=true,startCautionMult=true,startAggrMult=true,startRelax=true,startLaneHold=true,firstLapCare=true}
M.trackDayOnlyKeys={trafficGapSeconds=true,trafficDensityGain=true,trafficVariation=true,trafficMaxReduction=true}
M.notRaceKeys={yieldEnabled=true,pressureEnabled=true,pressureGap=true,pressureTime=true}
function M.uiHidden(profile,key) return M.hidden(profile,key) or profile~='C' and M.startUiKeys[key] or profile~='J' and M.trackDayOnlyKeys[key] or profile=='C' and M.notRaceKeys[key] or false end
M.pendingGlobals={} -- réglage global trackMemory livré (tranches A et B) ; la table reste (ui.lua, effectiveness.py)
do
 local effectiveGlobals=M.effectiveGlobals
 function M.effectiveGlobals(g,p,out)
  out=effectiveGlobals(g,p,out)
  for key in pairs(M.pendingGlobals) do out[key]=M.globalDefaults[key] end
  return out
 end
end
-- Constantes lues par plusieurs tranches de la Beta 1.61 (blocs des tranches : k161a à k161e, ajoutés après celui-ci).
-- Fichiers par circuit (src/trackfile.lua) : dans Documents\Assetto Corsa\<presetFolder>\<zoneFolder ou paceFolder>,
-- nommés <clé du circuit>.ini (clé d'au plus trackKeyMax caractères) ; longueur du circuit à trackLengthTol près
-- (fraction) ; format trackFileFormat, au plus trackFileMaxBytes octets, trackFileMaxSections sections,
-- trackFileMaxKeys clés par section et trackFileMaxValue caractères par valeur.
local k161={trackLengthTol=0.01,trackKeyMax=96,zoneFolder='tracks',paceFolder='pace',trackFileFormat=1,trackFileMaxBytes=262144,trackFileMaxSections=512,trackFileMaxKeys=32,trackFileMaxValue=8192}
for key,value in pairs(k161) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.61, tranche C (réglage classNuance) : retardataires et classes, voir src/nuance.lua. blueCatchTime : temps
-- d'arrivée de la voiture qui prend un tour ; blueBrakeTime, classNoDiveTime : attente avant un point de freinage ;
-- blueZoneTime : zone d'attaque préférée ; blueFastSa, blueSlowMin : niveau rendu ; nuanceBattleTime, blueTruceAfter :
-- trêve ; unlapMargin, relapHold, relapSa : dédoublement ; classSideLat, classAmCorridor, classTrainTime : classes ;
-- bluePlayerOrderTime, blueStartGrace, blueTrainRange, trafficKeyBytes : drapeau bleu du joueur et clé annexe ;
-- nuanceLogGap : écart entre deux lignes d'un même genre pour une voiture.
local k161c={blueCatchTime=5,blueBrakeTime=2,blueZoneTime=4,blueFastSa=20,blueSlowMin=0.02,nuanceBattleTime=1,blueTruceAfter=2,unlapMargin=1.3,relapHold=10,relapSa=8,
 classSideLat=1.5,classNoDiveTime=2,classAmCorridor=1.2,classTrainTime=2,bluePlayerOrderTime=2,blueStartGrace=30,blueTrainRange=200,trafficKeyBytes=160,nuanceLogGap=20,classAmStyle=0.6}
for key,value in pairs(k161c) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.61 (tranche A) : zones par circuit (src/zones.lua, src/zonelearn.lua). Fichier au format zoneFormat, note
-- d'au plus zoneNote caractères, au plus zoneLearntMax zones apprises, zoneBrakeMax points de freinage, attackMax zones
-- d'attaque. Zone apprise : appliquée après zoneConfirmSessions sessions, oubliée après zoneForgetSessions sessions
-- sans confirmation. Point de freinage : brakeLearnHits freinages de brakeLearnCars voitures au moins dans la session.
-- Zone d'attaque : marge de dépassement x attackMargin dedans ; à moins de attackWaitTime s de son début, un
-- dépassement attend, sauf rapprochement de plus de attackNoWaitSa km/h, voiture retenue depuis attackStuckTime s,
-- voiture à un tour ou classe plus lente devant ; apprise de attackLearnPasses dépassements réussis à moins de
-- attackMergeMeters m, longue de attackMinMeters à attackMaxMeters m. Ligne d'une zone : prise par lineShareDefault
-- des IA (tirage lineSalt), installée en lineRamp s. Enregistrement des zones apprises : au plus toutes les
-- zoneSavePeriod s.
local k161a={zoneFormat=1,zoneLearntMax=64,zoneNote=64,zoneConfirmSessions=2,zoneForgetSessions=10,brakeLearnHits=5,brakeLearnCars=2,zoneBrakeMax=48,
 attackMargin=0.8,attackWaitTime=6,attackNoWaitSa=20,attackStuckTime=8,attackLearnPasses=4,attackMergeMeters=150,attackMaxMeters=600,attackMinMeters=120,attackMax=8,
 lineRamp=1.5,lineShareDefault=0.5,lineSalt=1613,zoneSavePeriod=300,lineWet=0.1}
for key,value in pairs(k161a) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.61, tranche B (mémoire du circuit, src/pacemap.lua ; réglage global trackMemory). Fichier d'allure : format
-- paceMapFormat, au plus paceMapMaxBytes octets et paceMapModels modèles (nom d'au plus paceMapNameMax caractères),
-- compteurs d'au plus paceMapSerialMax ; vitesse d'au plus paceMapMaxSpeed dixièmes de m/s ; valeur isolée (écart de plus
-- de paceMapSpike à la médiane de ses voisins) écartée ; modèle gardé s'il connaît paceMapMinShare du tour.
-- Fusion : paceMapAlpha par session, valeur de session sous paceMapLow × gardé ignorée, bornée à paceMapHigh × gardé ;
-- session mouillée plus de paceMapWetShare de son temps : non retenue. Sauvegarde toutes les paceMapSavePeriod s au
-- plus (écriture de plus de paceMapSlowMs ms : fin de session seulement) ; note du départ après paceMapStartNote s.
-- A priori : donné au directeur après priorRatioMin endroits appris, rythme borné de priorRatioLow à priorRatioHigh
-- (lissage priorRatioAlpha) ; jamais au-dessus de priorWetMax d'humidité.
local k161b={paceMapFormat=1,paceMapMaxBytes=262144,paceMapModels=32,paceMapNameMax=64,paceMapSerialMax=100000,paceMapAlpha=0.3,paceMapLow=0.7,paceMapHigh=1.15,
 paceMapMinShare=0.5,paceMapWetShare=0.1,paceMapMaxSpeed=1200,paceMapSpike=0.4,paceMapSavePeriod=300,paceMapSlowMs=30,paceMapStartNote=5,
 priorRatioMin=10,priorRatioLow=0.8,priorRatioHigh=1.2,priorRatioAlpha=0.1,priorWetMax=0.1}
for key,value in pairs(k161b) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.61 (tranche D, réglage startRealism). Tour de formation : envol rangée par rangée (formLaunchGap s),
-- allure de la tête lente sur formOutDistance m puis sur les formBunchDistance derniers mètres (formSlowMult), vive
-- entre les deux (formBriskMult) ; zigzag (weaveAmp, période weavePeriodMin à weavePeriodMax s, weaveClear m libres,
-- plus de weaveStopBefore m avant la ligne, au-dessus de weaveMinKmh, sous weaveLatAccel m/s² : ligne droite), décalage
-- amené à formOffsetRate par seconde ; départ lancé : vert entre rollZoneFrom m et rollGreenBefore m de la ligne.
-- Envol : réaction anticReactMin à anticReactMax s ; envols manqués : anticPoorShare du plateau (x 1+anticWetGain
-- sous la pluie), anticPoorMax au plus, accélérateur de anticBogThrottle à 1 en anticBogTimeMin à anticBogTimeMax s,
-- jamais sous anticBogFloor avec une voiture collée derrière ; départs lancés : rampe depuis anticRollThrottle à
-- partir de la rangée anticAccordionRow ; tirages oubliés anticTail s après le dernier plafond.
-- Faux départs : mouvement sur la grille de jumpCreepMin à jumpCreepMeters m sous jumpCreepKmh km/h, flagrant à
-- jumpFlagrantMeters m ou jumpFlagrantLead s d'avance (pénalité x jumpFlagrantMult), rejugé après jumpJudgeTime s ;
-- IA qui vole le départ : chance anticJumpChance par départ, anticJumpLeadMin à anticJumpLeadMax s d'avance.
local k161d={formLaunchGap=0.6,formBunchDistance=800,formOutDistance=300,formSlowMult=0.75,formBriskMult=1.15,formOffsetRate=0.25,
 weaveAmp=0.35,weaveClear=25,weaveStopBefore=600,weavePeriodMin=2,weavePeriodMax=3.5,weaveMinKmh=40,weaveLatAccel=1.5,rollZoneFrom=300,
 anticReactMin=0.05,anticReactMax=0.4,anticPoorShare=0.12,anticPoorMax=3,anticBogThrottle=0.75,anticBogTimeMin=0.8,anticBogTimeMax=1.8,anticBogFloor=0.85,
 anticWetGain=1,anticSalt=1619,anticAccordionRow=3,anticRollThrottle=0.7,anticTail=1,
 jumpCreepMin=0.2,jumpCreepMeters=0.6,jumpCreepKmh=3,jumpFlagrantMeters=4,jumpFlagrantLead=0.5,jumpFlagrantMult=2,jumpJudgeTime=5,
 anticJumpChance=0.03,anticJumpLeadMin=0.1,anticJumpLeadMax=0.35}
for key,value in pairs(k161d) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.61, tranche E (réglage weatherLive, src/wx.lua et src/weather.lua). Tendance : pentes lissées sur wxTrendTau s,
-- pente minimale wxSlopeMin par seconde, bascule estimée au plus à wxEtaMax s. Rythme : humidité effective suivie avec
-- wxPaceTau s, pneus secs sur le mouillé × (1+wxSlickPenalty), intermédiaires sous forte pluie × (1+wxInterHeavy),
-- pneus pluie sous wxDryLine : humidité équivalente wxWetOnDry ; talent sous la pluie de wxSkillMin à wxSkillMax ;
-- première pluie : × wxOnsetCaution pendant wxOnsetTime s en pneus secs ; borne wxWetMax. Pneus : seuils décalés de
-- ± wxRiskSpan selon l'audace, arrêt anticipé si la bascule est attendue sous wxAnticipate s (audace >= wxGambleRisk ou
-- arrêt prévu sous wxComboLaps tours) à partir de wxPitEntryFrom du tour, averse courte : wxShowerTime s, pneu pluie
-- choisi sur l'eau projetée à wxProjectTime s (au plus ± wxProjectMax), pas de retour avant wxMinStint s, wxPitWave arrêts météo appelés à la
-- fois ; une ligne de tendance par wxLogGap s au plus ; clé annexe d'au plus weatherKeyBytes octets.
local k161e={wxPeriod=1,wxTrendTau=60,wxSlopeMin=0.0005,wxEtaMax=900,wxPaceTau=8,wxSlickPenalty=0.5,wxInterHeavy=0.2,wxDryLine=0.15,wxWetOnDry=0.3,
 wxSkillMin=0.8,wxSkillMax=1.2,wxSkillSalt=1621,wxOnsetTime=90,wxOnsetCaution=1.1,wxWetMax=1.6,wxRiskSpan=0.08,wxAnticipate=90,wxGambleRisk=0.65,
 wxComboLaps=3,wxPitEntryFrom=0.7,wxShowerTime=180,wxProjectTime=300,wxProjectMax=0.3,wxMinStint=240,wxPitWave=3,wxLogGap=60,weatherKeyBytes=160,wxRetry=60,wxCallMax=180}
for key,value in pairs(k161e) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Finition 1.61 : attente fixe après un échec contre une attardée en course (s), délai de grâce de la clé trafic.
local k161f={passLappedHold=10}
for key,value in pairs(k161f) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Affinage 1.61 (courses de Zandvoort et de Spa, essais de Spa du 11 novembre) : attaquant décalé de sa cible sans
-- prudence de suivi envers elle (m), écart en temps qui doit grandir en course avant « cible plus rapide » (s),
-- déboîtement dans l'aspiration (m) et rapprochement minimal pris pour juger la ligne droite qui reste (m/s).
local k161t={passFreeLat=1.2,abortTgGrowRace=0.3,pullOutCloseGap=8,pullOutClosingMin=1,passFreeCaution=1}
for key,value in pairs(k161t) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Affinage 1.61 (coût en jeu, Spa 40 IA) : métadonnées des voitures relues par tranches de metaCarsPerFrame voitures
-- par image (avant : toutes dans la même image, chaque seconde) ; image plus lente que slowFrameMs ms : une ligne de
-- journal par poste (au plus slowFrameLogs par lancement, slowFrameGap s entre deux).
local k161u={metaCarsPerFrame=8,slowFrameMs=40,slowFrameLogs=20,slowFrameGap=10}
for key,value in pairs(k161u) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Correctif 1.61 (Spa, 11 novembre : tour de formation puis départ arrêté) : grille du circuit acceptée jusqu'à
-- gridNodeAfter m après la ligne, emplacement au latéral jusqu'à gridNodeLatMax ramené à gridLatClamp ; feux au plus
-- gridWaitMax s après la première IA retenue ; retardataire à plus de gridLateRoll m de sa place : continue pendant les
-- feux. Tour de formation (départs réalistes) : zigzag d'un bord à l'autre (formWeaveAmp, borne formWeaveMax, à
-- formWeaveEdge m du bord en plus de la demi-voiture, rampe formWeaveRate par seconde et pilotage formWeaveRampMult fois
-- plus vif), arrêté formWeaveStopBefore m avant la ligne et à moins de formAheadBrakeTime s d'une voiture qui freine
-- (frein au-dessus de formAheadBrake) ; freinages de chauffe de formBrakeTime s (limite baissée de formBrakeDrop km/h,
-- jamais sous formBrakeFloor) tous les formBrakeEveryMin à formBrakeEveryMax s, personne à moins de formBrakeClear m
-- derrière ; coup d'accélérateur avant la place (formBurstFrom à formBurstTo m, +formBurstKmh km/h pendant
-- formBurstTime s, borné par l'arrêt à formBurstDecel m/s²).
local k161v={gridPlayerWait=25,gridNodeAfter=400,gridNodeLatMax=1.6,gridLatClamp=0.85,gridWaitMax=12,gridWaitFirstMax=18,formWeaveFullKmh=80,formWeaveFastKmh=140,formWeaveFastShare=0.35,gridLateRoll=30,
 formWeaveAmp=0.85,formWeaveMax=0.85,formWeaveEdge=0.6,formWeaveRate=0.9,formWeaveRampMult=3,formWeaveStopBefore=800,
 formAheadBrakeTime=1,formAheadBrake=0.2,formBrakeTime=0.6,formBrakeDrop=30,formBrakeFloor=60,formBrakeEveryMin=8,
 formBrakeEveryMax=15,formBrakeClear=40,formBurstFrom=80,formBurstTo=45,formBurstKmh=12,formBurstTime=0.7,formBurstDecel=3}
for key,value in pairs(k161v) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.62 (règles par session, partie pilotage, src/director.lua) : accélération latérale (m/s²) qui fait d'une
-- courbe un virage (a.corner = 0) ; journée circuit : suivi à au moins jFollowTime s (prudence × jFollowCaution),
-- marge latérale jPassMargin m du passage franc « line » ; qualifications : cession dès le seuil ordinaire avec une
-- voiture lancée à moins de qualiSacrificeTime s, pas de dépassement entre voitures pas lancées dans les lapEndMeters
-- derniers mètres ; essais : relais long, suiveur plus rapide au tour d'au moins practiceLapMargin.
local k162a={cornerLatRef=10,jFollowTime=1,jFollowCaution=1.4,jPassMargin=0.5,qualiSacrificeTime=2,lapEndMeters=600,practiceLapMargin=0.015}
for key,value in pairs(k162a) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.62, règles par session (partie R2, hors pilotage) :
--  qualifications : tour de sortie, voiture devant à moins de qualiExitGap s : niveau abaissé de qualiGapLevel au plus
--  (rampe qualiOutRamp), seulement avant qualiGapUntil du tour, baisse totale du tour de sortie au plus qualiOutMaxDrop ;
--  écart en temps mesuré à qualiGapMinSpeed m/s au moins ; vrais passages : tour fautif refait au plus runsRedoMax fois ;
--  course : drapeau bleu de plus toutes les blueIgnoreStep s d'attente, pénalité au blueIgnoreMax-ième ; emplacement
--  retenu tant qu'une voiture lancée dans la voie (plus de boxLaneKmh km/h) est à moins de boxReleaseGap m derrière, au
--  plus boxReleaseMax s, voiture à l'arrêt (sous boxReleaseStill km/h) ; tour de formation : file étirée au-delà de
--  formationMaxGap m (dix longueurs) depuis formationGapTime s, tête ralentie à formationWaitMult ;
--  journée circuit : attente de la piste libre après une sortie au plus rejoinWaitMaxJ s.
local k162b={qualiExitGap=2,qualiGapLevel=0.08,qualiGapUntil=0.6,qualiOutMaxDrop=0.2,qualiGapMinSpeed=10,runsRedoMax=2,
 blueIgnoreStep=6,blueIgnoreMax=3,blueVetoGrace=2,boxLaneKmh=20,boxReleaseGap=60,boxReleaseMax=8,boxReleaseStill=3,boxReleaseCatch=15,
 formationMaxGap=44,formationGapTime=4,formationWaitMult=0.8,rejoinWaitMaxJ=30}
for key,value in pairs(k162b) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Beta 1.62 (audit, I4) : réglages sans effet hors course, masqués hors du profil Course.
-- Relecture 1.62 (S9) : la défense et ses trois réglages, masqués hors course.
M.raceOnlyKeys={defenseEnabled=true,defenseMaxOffset=true,defenseCooldown=true,defenseTriggerGap=true}
-- Beta 1.62 (fusion R1 + R2) : inattentions loin d'un point de freinage et d'une voiture nettement plus rapide derrière.
local k162c={lapseBrakeTime=3,lapseRearTime=6,lapseFastKmh=15}
for key,value in pairs(k162c) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Affinage 1.62 (sessions du 12 novembre) : prudence au plus passFreeCornerCaution en courbe pour un attaquant décalé de
-- sa cible (hors freinage) ; bord du grand côté des manœuvres à au moins reachWideEdge m de la carrosserie (vibreurs et
-- murs comptés dans la largeur de certains circuits : Monaco) ; départ : voiture devant encore dans son envol manqué
-- (et anticBogGrace s après) : jamais de « pied tenu » derrière elle.
local k162q={passFreeCornerCaution=1,reachWideEdge=1.2,anticBogGrace=1}
for key,value in pairs(k162q) do assert(M.K[key]==nil,key); M.K[key]=value end
-- Affinage 1.62 (12 novembre, demande de la communauté) : recherche de l'aspiration en ligne droite (src/director.lua,
-- slipSeek) : voiture de devant écartée d'au moins seekLat m (au plus seekLatMax), à moins de seekTime s et seekRange m,
-- rattrapée d'au plus seekSaMax km/h (contact à seekTTC s au moins) ; seekAheadTime s de ligne droite devant pour
-- commencer, retour à la ligne sous seekReturnTime s ; recalage si l'écart dépasse seekSettleLat m, au plus toutes les
-- seekSettle s ; déboîtement retenu jusqu'à seekPullMargin s du temps juste nécessaire.
local k162s={seekLat=1,seekLatMax=5,seekTime=2,seekRange=90,seekSaMax=25,seekTTC=3,seekAheadTime=5,seekReturnTime=3,seekSettleLat=0.4,seekSettle=1.5,seekPullMargin=1.5,seekLogGap=20}
for key,value in pairs(k162s) do assert(M.K[key]==nil,key); M.K[key]=value end
return M
