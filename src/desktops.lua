-- Beta 1.64 (demande du pilote du 14 novembre) : overlay réglable par bureau d'applications d'AC. L'overlay est dessiné
-- par le rappel IN_GAME (pas une fenêtre d'AC) : la visibilité par bureau d'AC ne s'y applique pas. Le bureau courant est
-- lu à chaque image dans ac.getUI().currentDesktop (0 à 3 ; illisible : bureau inconnu, overlay affiché comme avant).
-- Réglage global overlayDesk1..4 (vrai par défaut : rien ne change pour qui n'y touche pas). Seul le dessin est coupé :
-- moteur, pont, journal et messages continuent.
local M={count=4,keys={'overlayDesk1','overlayDesk2','overlayDesk3','overlayDesk4'}}
local texts={
 fr={title='Bureaux d’applications',subtitle='overlay affiché sur',label='Bureau %d',current='Bureau %d (actuel)',
  unknown='Bureau actuel : illisible (overlay affiché partout)',
  tip='Overlay affiché ou masqué sur ce bureau d’applications d’AC. Changez de bureau avec la commande « Next desktop » d’AC : chaque bureau garde son propre choix. Sur un bureau masqué, l’app continue de tout gérer, seul l’affichage disparaît.',
  parts='Éléments sur ce bureau',partsDesk='Éléments sur le bureau %d',partsUnknown='Bureau actuel illisible : éléments réglables seulement sur un bureau connu.',
  line='Ligne de session',panel='Panneau des drapeaux',info='Explication et récapitulatif',pills='Pastilles de consignes',
  reset='Replacer',resetAll='Tout replacer sur ce bureau',ghost='%s : glisser pour placer à part',
  partsTip='Chaque élément de l’overlay est affiché ou masqué sur ce bureau seulement. Pour le placer : « Déplacer l’overlay », puis glisser l’élément hors du panneau (il devient une fenêtre à part sur ce bureau) ; clic droit pour verrouiller. « Replacer » le remet affiché, sous le panneau.',
  resetTip='Remet cet élément affiché et à sa place par défaut, sur ce bureau seulement.'},
 en={title='App desktops',subtitle='overlay shown on',label='Desktop %d',current='Desktop %d (current)',
  unknown='Current desktop: unreadable (overlay shown everywhere)',
  tip='Shows or hides the overlay on this AC app desktop. Use AC’s « Next desktop » control to switch; each desktop keeps its own choice. On a hidden desktop the app keeps running everything, only the display goes away.',
  parts='Elements on this desktop',partsDesk='Elements on desktop %d',partsUnknown='Current desktop unreadable: elements can only be set on a known desktop.',
  line='Session line',panel='Flag panel',info='Explanation and recap',pills='Instruction pills',
  reset='Reset',resetAll='Reset all on this desktop',ghost='%s: drag to place apart',
  partsTip='Each overlay element is shown or hidden on this desktop only. To place one: « Move overlay », then drag the element out of the panel (it becomes its own window on this desktop); right-click to lock. « Reset » shows it again, under the panel.',
  resetTip='Shows this element again at its default place, on this desktop only.'},
}
-- Bureau courant, 1 à 4, ou nil (valeur brute lue par l'applicateur : absente, illisible ou hors plage).
function M.current(value)
 if value==nil then return nil end
 local ok,n=pcall(tonumber,value)
 if not ok or not n or n~=math.floor(n) or n<0 or n>=M.count then return nil end
 return n+1
end
-- Overlay dessiné sur ce bureau ? Bureau inconnu : oui (comme avant la 1.64).
function M.visible(g,index)
 if index==nil or type(g)~='table' then return true end
 return g[M.keys[index]]~=false
end
function M.text(g,key)
 local t=texts[type(g)=='table' and g.language=='fr' and 'fr' or 'en']
 return t[key]
end
-- Affinage 1.64 t1 (demande du pilote du 14 novembre : « placer l'overlay où je veux, à un endroit différent sur chaque
-- bureau ») : position de l'overlay gardée par bureau d'applications d'AC, dans le réglage global overlayLayout (texte de
-- chiffres seulement, jamais exécuté) : « x,y,sx,sy » par bureau, séparés par « ; ». x,y : panneau des drapeaux (ou tout
-- l'overlay quand la ligne de session y est attachée) ; sx,sy : ligne de session détachée. -1 : position par défaut
-- (x,y : position globale overlayX/overlayY d'avant la 1.64, sinon centré en haut ; sx,sy : attachée au panneau).
M.layoutBytes=160
local empty={x=-1,y=-1,sx=-1,sy=-1}
local cache={text=nil,list={}}
local function num(t)
 local n=tonumber(t)
 if not n or n~=n or n==math.huge or n==-math.huge then return -1 end
 n=math.floor(n+0.5)
 if n<-1 or n>16000 then return -1 end
 return n
end
function M.validLayout(text)
 return type(text)=='string' and #text<=M.layoutBytes and text:match('^[%d,;%-]*$')~=nil
end
local function parse(text)
 if cache.text==text then return cache.list end
 local list={}
 local n=0
 for part in ((M.validLayout(text) and text or '')..';'):gmatch('([^;]*);') do
  n=n+1
  if n>M.count then break end
  local a,b,c,d=part:match('^(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)$')
  if a then list[n]={x=num(a),y=num(b),sx=num(c),sy=num(d)} end
 end
 cache.text=text; cache.list=list
 return list
end
-- Position gardée pour ce bureau (1 à 4) ; bureau inconnu ou rien de gardé : tout à -1 (positions d'avant).
function M.layout(g,index)
 if index==nil or type(g)~='table' then return empty end
 return parse(g.overlayLayout)[index] or empty
end
-- Écrit la position de ce bureau (les autres bureaux sont gardés) ; nil : position par défaut.
function M.setLayout(g,index,x,y,sx,sy)
 if index==nil or type(g)~='table' then return end
 local list=parse(g.overlayLayout)
 local out={}
 for n=1,M.count do
  local l=n==index and {x=num(x or -1),y=num(y or -1),sx=num(sx or -1),sy=num(sy or -1)} or list[n] or empty
  out[n]=l.x..','..l.y..','..l.sx..','..l.sy
 end
 local text=table.concat(out,';')
 if text=='-1,-1,-1,-1;-1,-1,-1,-1;-1,-1,-1,-1;-1,-1,-1,-1' then text='' end
 g.overlayLayout=text
end
-- Ligne de session détachée du panneau sur ce bureau ?
function M.detached(g,index)
 local l=M.layout(g,index)
 return l.sx>=0 and l.sy>=0
end
-- Affinage 1.64 u2 (demande du pilote : « comme SuperHUD, chaque élément de l'overlay à une place différente sur chaque
-- bureau, affiché sur un bureau et pas sur un autre ») : éléments de l'overlay, chacun affiché ou masqué et placé par
-- bureau. line : ligne de session (sa place reste dans overlayLayout, sx,sy, depuis t1) ; panel : panneau des drapeaux
-- (drapeau, titre, consigne, delta, place, feux, annonce d'une IA ; place x,y d'overlayLayout) ; info : explication ou
-- récapitulatif d'arrivée ; pills : pastilles de consignes. Réglage global overlayParts (texte de chiffres seulement,
-- jamais exécuté) : « masque,ix,iy,px,py » par bureau, séparés par « ; » ; masque : éléments masqués sur ce bureau
-- (line 1, panel 2, info 4, pills 8) ; ix,iy / px,py : explication / pastilles détachées (-1 : sous le panneau).
-- Rien de gardé : tout affiché, tout attaché (comme avant).
M.elements={'line','panel','info','pills'}
M.bits={line=1,panel=2,info=4,pills=8}
M.partsBytes=160
local noParts={mask=0,ix=-1,iy=-1,px=-1,py=-1}
local partsCache={text=nil,list={}}
function M.validParts(text)
 return type(text)=='string' and #text<=M.partsBytes and text:match('^[%d,;%-]*$')~=nil
end
local function parseParts(text)
 if partsCache.text==text then return partsCache.list end
 local list={}
 local n=0
 for part in ((M.validParts(text) and text or '')..';'):gmatch('([^;]*);') do
  n=n+1
  if n>M.count then break end
  local m,a,b,c,d=part:match('^(%d+),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)$')
  if m then
   local mask=tonumber(m) or 0
   if mask<0 or mask>15 then mask=0 end
   list[n]={mask=mask,ix=num(a),iy=num(b),px=num(c),py=num(d)}
  end
 end
 partsCache.text=text; partsCache.list=list
 return list
end
-- Éléments de ce bureau (1 à 4) ; bureau inconnu ou rien de gardé : tout affiché, tout attaché.
function M.parts(g,index)
 if index==nil or type(g)~='table' then return noParts end
 return parseParts(g.overlayParts)[index] or noParts
end
local function writeParts(g,index,mask,ix,iy,px,py)
 local list=parseParts(g.overlayParts)
 local out={}
 for n=1,M.count do
  local l=n==index and {mask=mask,ix=num(ix or -1),iy=num(iy or -1),px=num(px or -1),py=num(py or -1)} or list[n] or noParts
  out[n]=l.mask..','..l.ix..','..l.iy..','..l.px..','..l.py
 end
 local text=table.concat(out,';')
 if text=='0,-1,-1,-1,-1;0,-1,-1,-1,-1;0,-1,-1,-1,-1;0,-1,-1,-1,-1' then text='' end
 g.overlayParts=text
end
-- Élément affiché sur ce bureau ? Bureau inconnu : oui.
function M.shown(g,index,element)
 local bit=M.bits[element]
 if index==nil or not bit then return true end
 return math.floor(M.parts(g,index).mask/bit)%2==0
end
function M.setShown(g,index,element,on)
 local bit=M.bits[element]
 if index==nil or type(g)~='table' or not bit then return end
 local l=M.parts(g,index)
 local hidden=math.floor(l.mask/bit)%2==1
 local mask=l.mask
 if on and hidden then mask=mask-bit elseif not on and not hidden then mask=mask+bit end
 writeParts(g,index,mask,l.ix,l.iy,l.px,l.py)
end
-- Place d'un élément détaché sur ce bureau (x,y), ou nil s'il est attaché (panneau : jamais détaché, il porte le reste).
function M.place(g,index,element)
 if index==nil or type(g)~='table' then return nil end
 if element=='line' then local l=M.layout(g,index); if l.sx>=0 and l.sy>=0 then return l.sx,l.sy end; return nil end
 local l=M.parts(g,index)
 if element=='info' and l.ix>=0 and l.iy>=0 then return l.ix,l.iy end
 if element=='pills' and l.px>=0 and l.py>=0 then return l.px,l.py end
 return nil
end
-- Détache (x,y) ou rattache (nil) un élément sur ce bureau ; les autres bureaux et éléments sont gardés.
function M.setPlace(g,index,element,x,y)
 if index==nil or type(g)~='table' then return end
 if element=='line' then local l=M.layout(g,index); M.setLayout(g,index,l.x,l.y,x,y); return end
 local l=M.parts(g,index)
 if element=='info' then writeParts(g,index,l.mask,x,y,l.px,l.py)
 elseif element=='pills' then writeParts(g,index,l.mask,l.ix,l.iy,x,y) end
end
-- Élément remis par défaut sur ce bureau : affiché, attaché (panneau : remis à sa place par défaut).
function M.resetElement(g,index,element)
 if index==nil or type(g)~='table' then return end
 M.setShown(g,index,element,true)
 if element=='panel' then local l=M.layout(g,index); M.setLayout(g,index,nil,nil,l.sx,l.sy)
 else M.setPlace(g,index,element,nil,nil) end
end
-- Tous les éléments de ce bureau remis par défaut (affichés, attachés).
function M.resetParts(g,index)
 if index==nil or type(g)~='table' then return end
 writeParts(g,index,0,-1,-1,-1,-1)
end
return M
