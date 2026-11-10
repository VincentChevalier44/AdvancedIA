local U=require('src/util')
local K=require('src/config').K
local abs,min,max=math.abs,math.min,math.max
local M={}
function M.new()
 local p={rows={},order={},rank={},count=0,stamp=nil}
 for i=1,K.maxCars do
  local r={neighbors={},count=0,front=0,back=0,left=false,right=false,nearest=math.huge,free=true}
  for j=1,K.maxCars do r.neighbors[j]={index=0,long=0,lat=0,gap=0,sa=0,ttc=math.huge,same=false,alongside=false} end
  p.rows[i]=r; p.order[i]=i; p.rank[i]=i
 end
 return p
end
function M.relative(a,b,length,out)
 local dx,dz=b.x-a.x,b.z-a.z
 local long=dx*a.lx+dz*a.lz
 local lat=dx*(-a.lz)+dz*a.lx
 local gap=abs(long)-(a.length+b.length)*0.5
 local same=a.lx*b.lx+a.lz*b.lz>K.sameDirection; local coherent=true
 local range=length>0 and K.neighborRange or K.fallbackRange
 if dx*dx+dz*dz>range*range then same=false end
 if length>0 and a.splineValid and b.splineValid then
  local ds=U.spline(b.spline-a.spline)*length
  if abs(ds-long)>max(K.coherenceFloor,K.coherenceRatio*abs(ds)) then same=false; coherent=false end
 end
 local closing=long>=0 and a.speed-b.speed or b.speed-a.speed
 out.long=long; out.lat=lat; out.gap=gap; out.sa=closing*3.6
 out.ttc=closing>K.ttcEpsilon and max(0,gap)/closing or math.huge
 out.same=same; out.coherent=coherent; out.index=b.slot
 out.alongside=abs(long)<=(a.length+b.length)*0.5+K.alongsideBuffer
 return out
end
-- L'occupation est recalculée chaque image, même entre deux perceptions à 10 Hz.
function M.occupancy(cars,count,i,g,r)
 local a=cars[i]; r.left=false; r.right=false; local nearest2=math.huge
 for j=1,count do
  local b=cars[j]
  -- Une voiture hors piste juste à côté (elle rejoint) compte aussi : jamais de mouvement vers elle.
  if i~=j and b.valid and not b.pit then
   local dx,dz=b.x-a.x,b.z-a.z; local d2=dx*dx+dz*dz
   nearest2=min(nearest2,d2)
   -- Beta 1.35 : une voiture compte seulement si |long| <= portée et |lat| <= occLatMax (ou le recouvrement), donc à
   -- moins de racine(portée maximale² + occLatMax²) : au-delà, sautée sans projection (même résultat, bien moins de
   -- calcul à 60 voitures).
   local far=(a.length+b.length)*0.5+g.occMargin+g.occSpeedGain*abs(a.speed-b.speed)
   local long,lat,reach=0,0,-1
   if d2<=far*far+g.occLatMax*g.occLatMax then
    long=dx*a.lx+dz*a.lz; lat=-dx*a.lz+dz*a.lx
    local closing=max(0,long>0 and a.speed-b.speed or b.speed-a.speed)
    reach=(a.length+b.length)*0.5+g.occMargin+g.occSpeedGain*closing
   end
   if abs(long)<=reach then
    if abs(lat)<g.occLatMin and abs(long)<=(a.length+b.length)*0.5+K.overlapMargin then r.left=true; r.right=true
    elseif lat>=g.occLatMin and lat<=g.occLatMax then r.left=true
    elseif lat<=-g.occLatMin and lat>=-g.occLatMax then r.right=true end
   end
  end
 end
 r.nearest=math.sqrt(nearest2)
end
function M.prepare(self,cars,count,stamp)
 if stamp~=nil and self.stamp==stamp and self.count==count then return end
 self.stamp=stamp
 if self.count~=count then for j=1,count do self.order[j]=j end; self.count=count end
 -- Le tri précédent reste presque ordonné ; départage déterministe par indice.
 for j=2,count do
  local value=self.order[j]; local v=cars[value].spline; local n=j-1
  while n>0 and (cars[self.order[n]].spline>v or cars[self.order[n]].spline==v and self.order[n]>value) do self.order[n+1]=self.order[n]; n=n-1 end
  self.order[n+1]=value
 end
 for j=1,count do self.rank[self.order[j]]=j end
end
function M.refresh(self,cars,count,i,length,stamp)
 local a=cars[i]; local row=self.rows[i]
 row.count=0; row.front=0; row.back=0; row.free=true
 M.prepare(self,cars,count,stamp)
 local at=self.rank[i]
 -- Même sélection circulaire de huit voisins de chaque côté, sans boucle imbriquée.
 for j=1,count do
  local b=cars[j]
  local distance=abs(self.rank[j]-at)
  local selected=b.player or distance<=K.neighbors or distance>=count-K.neighbors
  -- Beta 1.41 : une voiture de la voie des stands près de la jonction (a.merging, moteur) est vue comme en piste (radar
  -- avant, obstacle, dépassement) ; jamais dans l'occupation latérale (les voies des stands longent souvent la piste).
  if j~=i and selected and b.valid and (not b.pit or b.merging) and not b.offtrack then
   local rel=row.neighbors[row.count+1]; M.relative(a,b,length,rel)
   if rel.same then
    row.count=row.count+1
    if rel.long>=0 and abs(rel.lat)<=K.latPass and (row.front==0 or rel.gap<row.neighbors[row.front].gap) then row.front=row.count end
    if rel.long<0 and abs(rel.lat)<=K.latYield and (row.back==0 or rel.gap<row.neighbors[row.back].gap) then row.back=row.count end
    if rel.long>0 and rel.gap<K.freeRange then row.free=false end
   end
  end
 end
end
function M.find(row,slot)
 for j=1,row.count do if row.neighbors[j].index==slot then return row.neighbors[j] end end
 return nil
end
-- Beta 1.59 : leadSpeed (m/s, facultatif) : une voiture du couloir nettement devant (au-delà de la longueur de l'IA) et au
-- moins aussi rapide ne le ferme pas (elle passe la même cible et s'éloigne : file derrière le joueur rangé).
function M.corridor(cars,count,i,side,distance,ignore,latMax,leadSpeed)
 local a=cars[i]
 for j=1,count do
  local b=cars[j]
  if j~=i and j~=ignore and b.valid and not b.pit then
   local dx,dz=b.x-a.x,b.z-a.z; local long=dx*a.lx+dz*a.lz; local lat=-dx*a.lz+dz*a.lx
   local same=a.lx*b.lx+a.lz*b.lz>K.sameDirection
   if same and long>=-b.length and long<=distance and -lat*side>=K.nearLine and abs(lat)<=(latMax or K.occLatMax)
    and not (leadSpeed and long>a.length+b.length and b.speed>=leadSpeed) then return false end
  end
 end
 return true
end
return M
