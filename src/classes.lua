local C=require('src/config')
local K=C.K
local M={}
function M.new() return {patterns={},order={},nextAt=0,bopAt=0,values={}} end
function M.configure(self,p) local _,valid=C.patterns(p.classPatterns,self.patterns); return valid end
-- Tours d'avance de b sur a. lapCount compte les tours terminés : au départ d'une grille placée avant la ligne, une voiture
-- encore avant la ligne paraît avoir un tour d'avance sur celle qui vient de la franchir. Sans tour terminé, aucun.
function M.laps(a,b,rel,length)
 if length<=0 or not a.lapValid or not b.lapValid or not a.splineValid or not b.splineValid or b.lap<1 then return 0 end
 local delta=(b.lap+b.spline)-(a.lap+a.spline)-rel.long/length
 return math.max(0,math.floor(delta+K.lapTolerance))
end
function M.update(self,cars,states,count,p,now)
 if now<self.nextAt then return end
 self.nextAt=now+K.classPeriod
 local n=0
 for i=1,count do
  local s=states[i]; s.manualClass=false
  for j=1,#self.patterns do local pat=self.patterns[j]
   if cars[i].id:lower():find(pat.pattern,1,true) then s.class=pat.class; s.classified=true; s.manualClass=true; break end
  end
  -- Beta 1.61 (tranche B) : tant que la voiture n'a pas appris assez d'endroits, la moyenne de l'allure gardée du
  -- circuit (s.priorMean, src/pacemap.lua) en tient lieu : les classes existent dès le premier virage.
  local mean=s.paceCount>=K.paceMinBins and s.paceMean or (s.priorMean or 0)
  s.classMean=mean
  if (s.paceCount>=K.paceMinBins or mean>0) and cars[i].valid then
   n=n+1; self.order[n]=i; local at=n
   while at>1 and states[self.order[at-1]].classMean<mean do self.order[at]=self.order[at-1]; at=at-1 end
   self.order[at]=i
  end
 end
 local class,previous=1,0
 for rank=1,n do
  local s=states[self.order[rank]]
  if previous>0 and (previous-s.classMean)/math.max(1,previous)>p.classGapPct/100 then class=math.min(K.classMax,class+1) end
  previous=s.classMean
  if not s.manualClass then
   if s.classCandidate==class then s.classCycles=math.min(K.classCycles,s.classCycles+1) else s.classCandidate=class; s.classCycles=1 end
   if s.classCycles>=K.classCycles then s.class=class; s.classified=true end
  end
 end
end
-- BoP émulée : dans chaque classe, le niveau des IA converge lentement vers l'allure médiane de la classe,
-- correction bornée ; le lest et la bride des voitures ne sont jamais modifiés.
function M.balance(self,cars,states,count,p,now)
 if not p.bopEnabled then for i=1,count do states[i].bop=0 end; return end
 if now<self.bopAt then return end
 self.bopAt=now+K.bopPeriod
 local limit=p.bopStrengthPct/100
 for class=1,K.classMax do
  local n=0
  for i=1,count do
   local s=states[i]
   if s.class==class and s.paceCount>=K.paceMinBins and cars[i].valid and not cars[i].player and not cars[i].safetyCar then
    n=n+1; self.values[n]=s.paceMean
   end
  end
  for j=#self.values,n+1,-1 do self.values[j]=nil end
  if n>=2 then
   table.sort(self.values); local median=self.values[math.floor((n+1)/2)]
   for i=1,count do
    local s=states[i]
    if s.class==class and s.paceCount>=K.paceMinBins and cars[i].valid and not cars[i].player and median>0 then
     s.bop=math.max(-limit,math.min(limit,(s.bop or 0)+K.bopGain*(median-s.paceMean)/median))
    end
   end
  end
 end
end
return M
