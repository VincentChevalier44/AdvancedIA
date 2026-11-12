local U=require('src/util')
local C=require('src/config')
local K=C.K
local M={}
function M.fill(out,seed,index,profile,p,stint)
 stint=p.enduranceOverlay and (stint or 0) or 0
 local salt=(profile=='J' and 1 or profile=='Q' and 2 or profile=='P' and 4 or profile=='H' and 5 or 3)*100
 local function r(n) return U.unit(seed,index,salt+n) end
 local function trait(n) return U.unit(seed,index,salt+(stint or 0)*K.stintSalt+n) end
 out.reaction=U.lerp(p.reactMin,p.reactMax,trait(1)); out.awareness=U.lerp(p.awMin,p.awMax,trait(2))
 out.patience=U.lerp(K.personaPatienceMin,K.personaPatienceMax,trait(3))
 out.courtesy=trait(4); out.assertiveness=trait(5); out.paceRank=r(7)
 out.levelSpread=(r(7)*2-1)*p.paceSpreadPct/100
 out.aggrSpread=(r(8)*2-1)*p.aggrSpreadPct/100
 out.cautSpread=(r(9)*2-1)*p.cautSpreadPct/100
 out.brakeMargin=U.lerp(K.personaBrakeMin,K.personaBrakeMax,r(10))
 out.phase=trait(11)*math.pi*2; out.period=U.lerp(K.driftPeriodMin,K.driftPeriodMax,trait(12))
 out.period2=U.lerp(K.driftPeriodMin,K.driftPeriodMax,trait(18))
 out.jitterPeriod=U.lerp(K.jitterPeriodMin,K.jitterPeriodMax,r(13))
 out.jitterPeriod2=U.lerp(K.jitterPeriodMin,K.jitterPeriodMax,r(19)); out.personalSide=r(20)<0.5 and -1 or 1
 -- Marge sous la référence du temps delta : chaque pilote reste un peu dans le vert.
 out.deltaMargin=U.lerp(K.aiDeltaMarginMin,K.aiDeltaMarginMax,r(21))
 out.laneBias=p.laneBiasEnabled and p.yieldSide~='line' and (1-out.paceRank)*p.laneBiasMax*(p.yieldSide=='left' and -1 or 1) or 0 -- Beta 1.62 : « line », aucun biais
 out.lapseInterval=U.lerp(p.lapseIntervalMin,p.lapseIntervalMax,r(14))
 out.lapseDuration=U.lerp(p.lapseDurMin,p.lapseDurMax,r(15))
 out.lapseDrop=U.lerp(p.lapseDropMin,p.lapseDropMax,r(16))/100
 out.holdAfter=U.lerp(p.yieldHoldAfterMin,p.yieldHoldAfterMax,r(17))*out.patience
 out.stintSwing=(U.unit(seed,index,salt+1000+(stint or 0))*2-1)*p.stintLevelSwing/100
 -- Grade Pro-Am stable d'une session à l'autre du week-end : 1 Platinum, 2 Gold, 3 Silver, 4 Bronze.
 out.grade=math.min(4,math.floor(U.unit(seed,index,K.gradeSalt)*4)+1)
 out.gradeLevel=p.proAmEnabled and K.gradeLevel[out.grade] or 1
 out.gradeCaution=p.proAmEnabled and K.gradeCaution[out.grade] or 1
 -- Beta 1.42 : caractère du stratège (stratégie individuelle des arrêts), de prudent (0) à audacieux (1), autour de la
 -- prise de risque moyenne réglée, dispersé selon l'écart entre stratèges ; même tirage pour toute la session.
 out.strategyRisk=U.clamp((p.strategyRiskPct or 50)/100+(r(22)*2-1)*(p.strategySpreadPct or 60)/200,0,1)
 if not p.section_human then
  out.reaction=K.neutralReaction; out.awareness=K.neutralAwareness; out.patience=1; out.courtesy=0.5; out.assertiveness=0.5
  out.brakeMargin=1; out.laneBias=0; out.holdAfter=(p.yieldHoldAfterMin+p.yieldHoldAfterMax)*0.5
 end
 -- Beta 1.60 (tranche C) : style du pilote, de 0 (professionnel posé) à 1 (amateur), d'après le grade et l'assurance.
 out.style=U.clamp(K.styleGradeShare*(out.grade-1)/3+(1-K.styleGradeShare)*(1-out.assertiveness),0,1)
 out.seed=seed; out.profile=profile; out.stint=stint or 0
 return out
end
function M.nextLapse(out,seed,index,event,p)
 local salt=K.lapseSalt+event*3
 out.lapseInterval=U.lerp(p.lapseIntervalMin,p.lapseIntervalMax,U.unit(seed,index,salt))
 out.lapseDuration=U.lerp(p.lapseDurMin,p.lapseDurMax,U.unit(seed,index,salt+1))
 out.lapseDrop=U.lerp(p.lapseDropMin,p.lapseDropMax,U.unit(seed,index,salt+2))/100
end
return M
