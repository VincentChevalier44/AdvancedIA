-- Beta 1.63 (décision du pilote, 13 novembre : carnage du premier tour de nouveau au même virage) : zones dangereuses
-- gardées par circuit, TOUJOURS (même « Mémoire des circuits » coupée), dans un petit fichier à part
-- (Documents\Assetto Corsa\AdvancedIA\danger\<circuit>.ini, codec src/trackfile.lua). Rien d'autre n'est gardé quand
-- la mémoire des circuits est coupée. Aucun accès aux fichiers ici : l'hôte (AdvancedIA.lua) lit et écrit.
-- Une zone : position (part du tour), niveau (1 ou 2, part retirée DK.dangerPct de src/incidents.lua), nombre
-- d'incidents, nombre de lancements, lancements de suite sans incident (quiet), allure de la flotte à cet endroit
-- (km/h : repli du premier tour, allure encore inconnue) et date (texte, pour le pilote).
-- Évolution d'un lancement à l'autre (M.loaded) : chaque chargement compte un lancement de plus sans incident ; une
-- zone de nouveau armée pendant ce lancement (M.armed) repart à zéro et monte au niveau 2. quiet >= DF.lower : niveau 2
-- ramené à 1 ; quiet >= DF.drop : zone oubliée.
local Trackfile=require('src/trackfile')
local M={}
local DF={folder='danger',kind='danger',maxBytes=16384,maxZones=12,lower=3,drop=5,mergeMeters=150,title='AdvancedIA - zones dangereuses du circuit'}
M.DF=DF
-- Correctif 1.63 (Imola, 13 novembre : jonction des stands inconnue au drapeau rouge du premier tour) : jonction des
-- stands (part du tour, -1 : inconnue) gardée aussi, pour poser la voiture de sécurité à la sortie des stands.
function M.new() return {zones={},n=0,key='',loaded=false,dirty=false,lines=0,junction=-1} end
-- Zones lues d'un fichier : liste triée, bornée, chaque valeur vérifiée ; nil et la raison si le fichier est refusé.
function M.decode(text,track,layout,length)
 local doc,why=Trackfile.parse(text,DF.maxBytes,DF.maxZones)
 if not doc then return nil,why end
 local ok,lengthOK=Trackfile.check(doc,DF.kind,track,layout,length)
 if not ok then return nil,lengthOK end
 if not lengthOK then return {},-1 end
 local out={}
 local junction=Trackfile.number(doc.head.junction,0,1) or -1
 for _,section in ipairs(doc.sections) do
  local v=section.values
  local spline=Trackfile.number(v.spline,0,1)
  local level=Trackfile.integer(v.level,1,2)
  if spline and level then
   out[#out+1]={spline=spline%1,level=level,count=Trackfile.integer(v.count,0,1e6) or 0,sessions=Trackfile.integer(v.sessions,0,1e6) or 0,
    quiet=Trackfile.integer(v.quiet,0,1e6) or 0,kmh=Trackfile.number(v.kmh,0,1000) or 0,date=Trackfile.text(v.date,32) or ''}
  end
 end
 return out,junction
end
-- Texte du fichier (tri par position).
function M.encode(t,head)
 local sections={}
 for k=1,t.n do
  local z=t.zones[k]
  sections[k]={name='zone'..k,spline=math.floor(z.spline*1e6+0.5)/1e6,level=z.level,count=z.count,sessions=z.sessions,quiet=z.quiet,
   kmh=math.floor((z.kmh or 0)*10+0.5)/10,date=z.date or ''}
 end
 local h={kind=DF.kind,track=head.track,layout=head.layout,length=head.length,serial=0}
 if (t.junction or -1)>=0 then h.junction=math.floor(t.junction*1e6+0.5)/1e6 end
 return Trackfile.build(DF.title,h,sections)
end
-- Chargement d'un lancement : vieillissement (un lancement de plus), zones trop calmes baissées ou oubliées.
-- Rend le nombre de zones gardées.
function M.loaded(t,list,key,junction)
 for k=#t.zones,1,-1 do t.zones[k]=nil end
 t.n=0; t.key=key or ''; t.loaded=true; t.junction=junction or -1
 for _,z in ipairs(list or {}) do
  z.sessions=z.sessions+1; z.quiet=z.quiet+1
  if z.quiet>=DF.drop then t.dirty=true
  else
   if z.level>1 and z.quiet>=DF.lower then z.level=1 end
   t.n=t.n+1; t.zones[t.n]=z
   if t.n>=DF.maxZones then break end
  end
 end
 table.sort(t.zones,function(a,b) return a.spline<b.spline end)
 if t.n>0 or (list and #list>0) then t.dirty=true end
 return t.n
end
-- Jonction relevée pendant ce lancement (src/merge.lua) : gardée si elle est nouvelle ou a bougé de plus de DF.mergeMeters
-- m ; rend vrai s'il faut enregistrer.
function M.junctionSeen(t,spline,length)
 if spline<0 or length<=0 then return false end
 if (t.junction or -1)>=0 and math.abs(((spline-t.junction+0.5)%1)-0.5)*length<=DF.mergeMeters then return false end
 t.junction=spline; t.dirty=true
 return true
end
-- Point difficile armé ou relevé pendant ce lancement (src/incidents.lua) : zone créée, ou zone gardée retrouvée
-- (à DF.mergeMeters m près) : incident compté, calme remis à zéro, niveau 2 si elle avait déjà servi un lancement.
function M.armed(t,spline,length,level,kmh,date)
 if length<=0 then return end
 for k=1,t.n do
  local z=t.zones[k]
  local d=math.abs(((spline-z.spline+0.5)%1)-0.5)*length
  if d<=DF.mergeMeters then
   z.count=math.min(1e6,z.count+1)
   if z.quiet>0 or z.sessions>0 then z.level=2 end
   z.level=math.max(z.level,level or 1); z.quiet=0
   if kmh and kmh>0 then z.kmh=kmh end
   z.date=date or z.date; t.dirty=true
   return z
  end
 end
 if t.n>=DF.maxZones then return nil end
 t.n=t.n+1
 local z={spline=spline%1,level=level or 1,count=1,sessions=0,quiet=0,kmh=kmh or 0,date=date or ''}
 t.zones[t.n]=z; t.dirty=true
 table.sort(t.zones,function(a,b) return a.spline<b.spline end)
 return z
end
-- Part retirée à l'endroit spline et allure de repli de la zone (km/h, 0 : aucune) ; before / after : étendue de la
-- zone (m) devant et après sa position, pct : parts par niveau (src/incidents.lua, DK).
-- Affinage 1.64 s1 : troisième valeur, position de la zone retenue devant la voiture (m ; négative : zone dépassée).
function M.cut(t,spline,length,before,after,pct)
 local cut,kmh,at=0,0,0
 if t.n==0 or length<=0 then return 0,0,0 end
 for k=1,t.n do
  local z=t.zones[k]
  local ahead=(((z.spline-spline)+0.5)%1-0.5)*length
  if ahead<=before and ahead>=-after then
   local p=pct[z.level] or pct[1]
   if p>cut then cut=p; kmh=z.kmh or 0; at=ahead end
  end
 end
 return cut,kmh,at
end
return M
