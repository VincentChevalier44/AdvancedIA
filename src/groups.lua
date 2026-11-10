-- Sous-groupes des réglages (Beta 1.35, refonte « Racing 26 ») : pour chaque section, ses intertitres (titre et
-- sous-titre dans L.subgroups) et ses réglages dans l'ordre de la maquette. Une clé absente du schéma est ignorée
-- (réglage d'une autre version) ; un réglage du schéma qu'aucun sous-groupe ne cite est montré à la fin, sous
-- « Autres réglages » : aucun réglage ne peut disparaître de la fenêtre.
-- Règles de course : trois vues (règles actives, arrêt obligatoire, voiture de sécurité).
local M={}
M.sections={
 general={{'generalPace',{'levelPct','aggressionPct','caution','brakeZonePct'}},
  {'generalSpread',{'paceSpreadPct','aggrSpreadPct','cautSpreadPct'}},
  {'generalStart',{'pitExitSpread','spawnMode','spawnMinCars','spawnPitPct','spawnGapVariation','floodRangeKm'}}},
 human={{'humanReact',{'reactMin','reactMax','awMin','awMax'}},
  {'humanLine',{'paceDriftPct','personalLineJitter','laneBiasEnabled','laneBiasMax'}},
  {'humanLapse',{'lapseEnabled','lapseIntervalMin','lapseIntervalMax','lapseDurMin','lapseDurMax','lapseDropMin','lapseDropMax'}},
  {'humanMistakes',{'mistakesEnabled','mistakeRate'}}},
 lateral={{'lateralSpeed',{'rampSpeed','rampAccel','lowPassTau'}},
  {'lateralLimits',{'maxSideOffset','cornerMin','cornerYawRef','lateralCooldown','emergencyReleaseFactor'}}},
 start={{'startStanding',{'startDelay','startCautionMult','startAggrMult','startRelax','startLaneHold','firstLapCare'}}},
 yield={{'yieldOrdinary',{'yieldEnabled','yieldSide','yieldOffset','yieldDetectBehind','yieldBehindMargin','yieldHorizon','confirmTime'}},
  {'yieldHold',{'yieldHoldMin','yieldHoldAfterMin','yieldHoldAfterMax','yieldMaxHold'}},
  {'yieldSlow',{'yieldSlowdownPct','inviteSlowdownPct'}},
  {'yieldPressure',{'pressureEnabled','pressureGap','pressureTime'}},
  {'yieldQuali',{'qualiTraffic','qualiCoolLaps','qualiRuns'}}},
 blue={{'blueFlags',{'blueFlagEnabled','blueFlagRange','blueFlagSide'}}},
 flash={{'flashPlayer',{'flashMode','flashRange','flashMinAdvantage','flashCloseAdvantage','flashRequestTTL'}},
  {'flashAI',{'flashObliviousPct','flashMaxReactors','hornEnabled','aiFlashEnabled'}}},
 overtake={{'overtakeTrigger',{'overtakeEnabled','overtakeSide','overtakeDetectAhead','overtakeAheadMargin','overtakeHorizon','stuckTime','stuckPaceRatio'}},
  {'overtakeMove',{'overtakeOffset','pullOutGapBase','pullOutGapPerMps','overtakeClearMargin','overtakeRestTime','overtakeChain','slipstreamEnabled'}},
  {'overtakeDefense',{'defenseEnabled','defenseMaxOffset','defenseCooldown','defenseTriggerGap'}},
  {'overtakeAero',{'towBreakEnabled','towBreakRange','towBreakStraight','dirtyAirEnabled','dirtyAirGap','dirtyAirLiftPct'}},
  {'overtakeFinal',{'finalLapsEnabled','finalLaps','finalAggressionPct','finalDefensePct'}}},
 traffic={{'trafficGap',{'trafficGapSeconds','trafficDensityGain','trafficVariation','trafficMaxReduction'}}},
 accidents={{'accObstacles',{'obstacleEnabled','obstacleSpeedKmh','obstacleDetect','obstacleLevelDrop','obstacleCautionMult'}},
  {'accInvolved',{'avoidOffset','contactRecovery','incidentStop','incidentStopMin','incidentStopMax','rejoinGap','damagePit'}},
  {'accYellow',{'yellowEnabled','yellowBefore','yellowAfter','yellowHold','yellowDecel'}},
  {'accDouble',{'zoneDeltaPct','slowZoneKmh','yellowSpeedKmh'}},
  {'accPlayer',{'yellowHud','flagPanel','yellowMessage','deltaBeeps'}},
  {'accPenalties',{'playerPenalties','deltaTolerance','penaltySeconds','penaltyDisqualify','aiPenalties'}}},
 endurance={{'endOverlay',{'enduranceOverlay','stintLevelSwing','stintDegradationPct'}},
  {'endClasses',{'multiClass','classGapPct','classYieldMargin'}}},
 weather={{'weatherRain',{'weatherAdaptation','weatherTyresEnabled','rainGripBoostPct'}},
  {'weatherOutLap',{'outLapEnabled','outLapLevelPct'}},
  {'weatherWear',{'lockWearEnabled','lockWearGain','lockFlatSpotKm'}},
  {'weatherMessages',{'weatherMessage'}}},
 -- Beta 1.42 : stratégie des IA (course) et sanctions des IA (essais, qualifications et course).
 strategy={{'strategyPlan',{'strategyEnabled','strategyTyreWearPct','strategyFuelMarginLaps','strategyUndercut','strategyStartVariety'}},
  {'strategyCharacter',{'strategyRiskPct','strategySpreadPct'}},
  {'strategyFailures',{'failuresEnabled','failureRate','failureLossPct'}}},
 sanctions={{'sanctionsTrack',{'sanTrackLimits','sanTrackWarnings','sanCutPenalty','sanCutSeconds'}},
  {'sanctionsProcedure',{'sanJumpStart','sanPitSpeed','sanPitExit','sanProcedureKind'}},
  {'sanctionsFlags',{'sanWrongWay','sanWrongWaySeconds','sanServeLaps'}},
  {'sanctionsServe',{'sanStopGoSeconds','sanTimeSeconds','sanUnservedTime','sanGiveBack','sanGiveBackSeconds'}},
  {'sanctionsDisplay',{'sanMessages','sanReport'}},
  -- Beta 1.59 : réglages de la 1.56 rangés dans leurs intertitres (plus sous « Autres réglages »), à la même place.
  {'sanctionsEscalation',{'sanEscalation','sanEscalationStep','sanEscalationMax'}},
  {'sanctionsPlayer',{'sanPlayerTrackLimits','sanPlayerSession','sanPlayerPenalty'}}},
 -- Panneaux lumineux (Beta 1.37) : l'état du circuit est dessiné à part, en tête de la section.
 lights={{'lightsColours',{'lightsYellow','lightsRed','lightsBlue','lightsWhite','lightsOrange','lightsGreen'}},
  {'lightsDurations',{'lightsGreenTime','lightsHold'}}},
 -- Règles de course. Étape B (Beta 1.34) : relance après drapeau rouge (redRestart) et dépassement après la relance.
 rules_all={{'rulesCommon',{'noMoveBraking','neutralization','majorIncidentTime','neutralizationHold'}},
  {'rulesNeutral',{'fcyDeltaPct','fcySpeedKmh','vscDeltaPct'}},
  {'rulesRed',{'redFlagEnabled','redFlagCars','redDeltaPct','redFlagSpeedKmh','redFlagHold','redFlagWork','redRestart'}},
  {'rulesF1',{'overtakeMode','overtakeModeGap','overtakeModeBoostPct'}},
  {'rulesDrs',{'drsAssist','rulesDrs','rulesDrsLaps','aiDrs','drsBeepVolume'}},
  {'rulesGT',{'bopEnabled','bopStrengthPct','proAmEnabled'}},
  {'rulesEndurance',{'predictableSlowClass'}}},
 -- Beta 1.52 (relecture) : arrêt obligatoire réglé par son seul interrupteur (vue « switch » de src/ui.lua, jamais
 -- affichée), plus cité ici.
 rules_stops={{'stopsWindow',{'pitWindowOpenPct','pitWindowClosePct','pitMessage'}},
  {'stopsEach',{'pitTyres','pitRepair','pitCompoundChange','minPitTime','maxStintMin'}},
  {'stopsFuel',{'pitFuel','pitsClosed'}}},
 rules_safety={{'safetyOut',{'safetyCarEscalation','safetyCarSpeedKmh','restartOvertake'}}}}
-- Beta 1.59 : réglages jamais montrés (valeur gardée sans effet) : lightsYellow est figé à vrai (M.validate), la case
-- n'avait rien à régler.
M.hidden={lightsYellow=true}
-- Liste des groupes affichés d'une section : chaque entrée {id=, controls={...}} ; controls d'après la liste fournie
-- (contrôles de la section, dans l'ordre du schéma). Le résultat est mémorisé par section (même liste de contrôles).
local built={}
function M.build(section,controls)
 local key=section
 local hit=built[key]
 if hit and hit.source==controls then return hit.list end
 local byKey={}; for _,control in ipairs(controls) do byKey[control.schema.key]=control end
 local used={}; local list={}
 for _,entry in ipairs(M.sections[section] or {}) do
  local group={id=entry[1],controls={}}
  for _,k in ipairs(entry[2]) do local control=byKey[k]; if control and not used[k] and not M.hidden[k] then used[k]=true; group.controls[#group.controls+1]=control end end
  if #group.controls>0 then list[#list+1]=group end
 end
 local rest={id='other',controls={}}
 for _,control in ipairs(controls) do local k=control.schema.key; if not used[k] and not M.hidden[k] then rest.controls[#rest.controls+1]=control end end
 if #rest.controls>0 then list[#list+1]=rest end
 built[key]={source=controls,list=list}
 return list
end
return M
