local C=require('src/config')
local L=require('src/lang')
local U=require('src/util')
local Flash=require('src/flash')
local Zones=require('src/zones')
local Engine=require('src/engine')
local Caps=require('src/caps')
local Adapter=require('src/applier')
local callable=Adapter.callable
local Presets=require('src/presets')
local Panel=require('src/panel')
local Snapshot=require('src/snapshot')
local T=require('src/tips')
local W=require('src/widgets')
local Locale=require('src/locale')
local Update=require('src/update')
local Groups=require('src/groups')
local Cspgui=require('src/cspgui')
local Journal=require('src/journal')
local K=C.K
local M={}
-- Identifiant « préfixe..clé » mémorisé : même chaîne à chaque image, aucune concaténation dans le dessin.
local idCache={}
local function idOf(prefix,key)
 local t=idCache[prefix]
 if not t then t={}; idCache[prefix]=t end
 local s=t[key]
 if not s then s=prefix..key; t[key]=s end
 return s
end
-- Texte formaté mémorisé par emplacement (v.memo, refait au changement de langue) : reconstruit seulement quand le
-- modèle ou une valeur change ; aucune chaîne neuve d'une image à l'autre sinon.
local function fmt(v,slot,pattern,a,b,c,d)
 local m=v.memo[slot]
 if not m then m={}; v.memo[slot]=m end
 if m.p~=pattern or m.a~=a or m.b~=b or m.c~=c or m.d~=d then m.p=pattern; m.a=a; m.b=b; m.c=c; m.d=d; m.text=string.format(pattern,a,b,c,d) end
 return m.text
end
-- Infobulles préparées une seule fois par langue : lignes coupées à la main (setTooltip ne coupe pas les lignes),
-- séparateur décimal de la langue, valeur par défaut du profil ; aucun texte n'est construit pendant le dessin.
local function wrap(source) return U.wrapText(source,K.uiTipWidth) end
M.wrap=wrap
local function number(value)
 local text=string.format('%.3f',value):gsub('0+$',''):gsub('%.$','')
 return (text:gsub('%.',L.decimalMark))
end
local function shown(s,value)
 if s.choices then return L.choices[value] or tostring(value) end
 if type(value)=='boolean' then return value and L.tipOn or L.tipOff end
 return number(value)
end
local function wrapAll(source) local out={}; for key,text in pairs(source) do out[key]=wrap(text) end; return out end
local function globalTips()
 local out={}
 for key,text in pairs(T.globals) do
  local default=C.globalDefaults[key]; local bounds=C.globalBounds[key]; local value
  if key=='levelMode' then for j,x in ipairs(C.globalChoices.levelMode) do if x==default then value=L.levelModeLabels[j] end end
  elseif type(default)=='boolean' then value=default and L.tipOn or L.tipOff
  elseif type(default)=='string' then value=L.choices[default] or default
  else value=number(default)..(bounds and string.format(L.tipRange,number(bounds[1]),number(bounds[2])) or '') end
  -- Beta 1.39 (maquette) : la note des messages masqués passe dans l'infobulle de l'interrupteur.
  if key=='overlayBlockMessages' then text=text..'\n\n'..L.overlayBlockedNote end
  out[key]=wrap(text..'\n\n'..string.format(L.tipGlobalDefault,value))
 end
 return out
end
-- Vues de l'onglet Règles de course (Beta 1.19) : les arrêts aux stands et la voiture de sécurité n'apparaissent que
-- sous le titre de leur interrupteur ; « Règles de course actives » montre tout le reste des règles.
-- Beta 1.51 : arrêt obligatoire oui ou non, réglé par son seul interrupteur (vue « switch », jamais affichée).
local ruleViews={switch={mandatoryStops=true},stops={pitWindowOpenPct=true,pitWindowClosePct=true,pitTyres=true,pitRepair=true,pitCompoundChange=true,minPitTime=true,maxStintMin=true,pitFuel=true,pitsClosed=true,pitMessage=true},
 safety={safetyCarSpeedKmh=true,safetyCarEscalation=true,restartOvertake=true}}
-- Interrupteurs indépendants des jeux de règles (Beta 1.19, C.switchKeys) : le jeu choisi reste surligné quand on les change.
local function ruleView(key) for name,keys in pairs(ruleViews) do if keys[key] then return name end end return 'all' end
-- Jeu de règles du profil visé (en-tête, onglet Règles de course, bloc des règles) : refait seulement après une
-- modification (révision du moteur, édition de la fenêtre) ou pour un autre profil visé, jamais à chaque image.
local function ruleCategoryOf(v,e)
 local target=C.solo(v.view) and 'C' or v.view
 if v.ruleEdits~=v.edits or v.ruleRevision~=e.revision or v.ruleTarget~=target then v.ruleEdits=v.edits; v.ruleRevision=e.revision; v.ruleTarget=target; v.ruleCategory=C.ruleCategory(target,e.profiles[target],C.switchKeys) end
 return v.ruleCategory,target
end
-- Textes de la fenêtre dans la langue en cours (Beta 1.16) : infobulles, libellés des choix, des motifs et des
-- préréglages intégrés ; refaits au changement de langue, avec les textes mémorisés du panneau de drapeaux.
local function texts(v)
 v.tips={ui=wrapAll(T.ui),tabs=wrapAll(T.tabs),sections=wrapAll(T.sections),profiles=wrapAll(T.profiles),presets=wrapAll(T.presets),rules=wrapAll(T.rules)}
 v.globalTips=globalTips(); v.customTips={}
 for _,controls in pairs(v.controls) do
  for _,control in ipairs(controls) do
   local s=control.schema
   -- Textes de la langue précédente (valeur affichée, défaut, découpe des choix) refaits à la prochaine image.
   control.defaultFor=nil; control.valueFor=nil; control.fitLang=nil
   local body=wrap(T.settings[s.key] or s.label)
   local range=s.min and string.format(L.tipRange,number(s.min),number(s.max)) or ''
   for _,p in ipairs(C.profiles) do control.hint[p]=body..'\n\n'..wrap(string.format(L.tipDefault,L.profiles[p],shown(s,s.defaults[p]))..range) end
   -- Beta 1.38 : libellés courts de la maquette (L.choiceShort) dans les cases ; les infobulles gardent les longs.
   local short=L.choiceShort[s.key]
   if s.choices then for j,x in ipairs(s.choices) do control.labels[j]=short and short[x] or L.choices[x] or x end end
  end
 end
 -- Descriptions des sections (Beta 1.38 : celles de la maquette ; les infobulles de la liste gardent les longues).
 v.descriptions={}; for _,group in ipairs(C.sections) do v.descriptions[group]=L.sectionDescs[group] or T.tabs[group] or '' end
 v.descriptions.overlay=L.sectionDescs.overlay or T.tabs.overlay or ''
 local function same(profile) return function() return profile end end
 v.builtinList={{L.presetJ,'Nordschleife','J',same('J')},{L.presetP,'Essais','P',same('P')},{L.presetQ,'Qualifications','Q',same('Q')},{L.presetC,'Course','C',same('C')},
  {L.presetE,'Endurance','E',function(view) return (view=='Q' or view=='P') and 'C' or view=='H' and 'J' or view end}}
 v.builtinNames={Nordschleife=L.presetJ,Essais=L.presetP,Qualifications=L.presetQ,Course=L.presetC,Endurance=L.presetE}
 -- Textes mémorisés (préréglage chargé, liste des voitures, version, delta, pastilles, message) : refaits à la
 -- prochaine image.
 -- Infobulles du diagnostic (Beta 1.39) : état de la calibration, zone de freinage émulée ; coupées une fois.
 v.calibrationTips={}; for phase,text in pairs(L.calibration) do v.calibrationTips[phase]=wrap(text) end
 v.brakeTip=wrap(L.brakeEmulation)
 -- Beta 1.52 (relecture) : textes qui citent une constante (longueur d'un nom, taille de la bibliothèque, durée de
 -- l'apprentissage des appels de phares), formatés une fois par langue depuis K.
 v.invalidNameText=string.format(L.invalidPresetName,K.presetNameBytes); v.saveFailedText=string.format(L.presetSaveFailed,K.maxPresets)
 v.learnText=string.format(L.learnShort,K.flashLearnTime); v.learningText=string.format(L.learning,K.flashLearnTime)
 v.updateLine=nil; v.loadedFor=nil; v.carFilterBuilt=nil; v.panelVersion=nil; v.infrFor=nil; v.updateCodeFor=nil; v.deltaHundredths=nil; v.giveBackName=nil; v.blueTenths=nil; v.presetMessage=''
 -- Textes et mesures de la fenêtre refaits à la prochaine image (Beta 1.35) : textes mémorisés (v.memo), ligne des
 -- panneaux lumineux du diagnostic, place à rejoindre de l'overlay.
 v.setupFor=nil; v.memo={}; v.placeSlot=nil; v.placeMeters=nil; v.lightOpts={}; v.activeFor=nil
end
function M.new(e,host,calibration,dirty)
 local v={e=e,host=host,calibration=calibration,dirty=dirty,open={patternRows=true},controls={},logFilter=1,patternInvalid=false,category='general',keptRules={},
  patternRows={},patternFragments={},patternSource=false,patternProfile='',presetName='',presetMessage='',derived={},signatureValues={},builtinSignatures={},
  builtinConfigs={Nordschleife={J=C.preset('Nordschleife','J',{})},Essais={P=C.preset('Essais','P',{})},Qualifications={Q=C.preset('Qualifications','Q',{})},Course={C=C.preset('Course','C',{})},Endurance={J=C.preset('Endurance','J',{}),C=C.withRules('Endurance','C',C.preset('Endurance','C',{}))}}}
 v.patternIds={}; v.patternClassIds={}; v.patternClearIds={}
 for i=1,K.maxPatterns do v.patternRows[i]={pattern='',class=1}; v.patternIds[i]='pattern_'..i; v.patternClassIds[i]='pattern_class_'..i; v.patternClearIds[i]='pattern_clear_'..i end
 for _,s in ipairs(C.schema) do
  local control={schema=s,labels={},hint={},id='set_'..s.key,idMinus='set_'..s.key..'_minus',idPlus='set_'..s.key..'_plus'}
  if s.choices then control.choiceIds=W.choiceIds(control.id,#s.choices) end
  local controls=v.controls[s.group]
  if not controls then controls={}; v.controls[s.group]=controls end
  if s.min then control.step=W.step(s.min,s.max,C.integerKeys[s.key]) end
  controls[#controls+1]=control
 end
 v.tab='home'; v.statusLines={}; v.warnings={}; v.scrolls={}; v.contentHeights={}; v.loadedName=''; v.debugRows={}; v.customActive={}
 v.splits={}; v.warningKinds={}
 v.rulesView='all'; v.ruleLists={all={},stops={},safety={},switch={}}
 for _,control in ipairs(v.controls.rules) do local list=v.ruleLists[ruleView(control.schema.key)]; list[#list+1]=control end
 v.edits=0; v.modifiedMemo={}; v.entrySigs=setmetatable({},{__mode='k'}); v.entryTexts=setmetatable({},{__mode='k'}); v.builtinMemo={}
 local save=v.dirty
 v.dirty=function() v.edits=(v.edits+1)%K.counterMax; save() end
 texts(v)
 -- Commandes dessinées : fonctions de dessin et de saisie de CSP requises ; sinon un message remplace la fenêtre.
 v.drawable=true
 for _,name in ipairs({'invisibleButton','itemHovered','itemActive','mouseClicked','mouseDown','mouseLocalPos','mouseWheel','dwriteDrawText','measureDWriteText',
  'pushDWriteFont','popDWriteFont','drawRectFilled','drawLine','drawCircleFilled','pushClipRect','popClipRect','setCursor','getCursor','availableSpace','inputText','setNextItemWidth'}) do
  if not callable(ui[name]) then v.drawable=false end
 end
 return v
end
local function text(value)
 if callable(ui.textWrapped) then ui.textWrapped(value) else ui.text(value) end
end
-- Polices de l'app et icône de l'en-tête : cherchées une seule fois, par la fenêtre ou par l'overlay.
local function fontsOnce(v)
 if v.fontsChecked then return end
 v.fontsChecked=true; W.setFonts(Adapter.fontDir(v.host)); v.logo=Adapter.appFile('icon.png')
end
local function mark(v) Engine.changed(v.e); v.dirty() end
-- Entier groupé par milliers (séparateur de la langue), pour la taille du journal.
local function groupDigits(n)
 local s=string.format('%d',math.floor(n))
 local out=s:reverse():gsub('(%d%d%d)','%1'..L.thousands):reverse()
 if out:sub(1,#L.thousands)==L.thousands then out=out:sub(#L.thousands+1) end
 return out
end
-- Préréglage chargé pour le profil affiché (Beta 1.39, maquette) : un préréglage appliqué à un autre profil laisse
-- « Aucun préréglage actif » ici. Nom lu au changement du préréglage, marque relue au changement des marques ou du
-- profil ; préréglage personnel : profil de son entrée (aucune table neuve).
local function loadedHere(v,e,view)
 local g=e.g
 if v.hereFor~=g.loadedPreset then v.hereFor=g.loadedPreset; v.hereKind,v.hereName=g.loadedPreset:match('^([^:]+):(.*)$'); v.hereMarks=nil end
 if v.hereKind=='builtin' then
  if v.hereMarks~=g.builtinMarks or v.hereView~=view then v.hereMarks=g.builtinMarks; v.hereView=view; v.hereBuiltin=C.mark(g,view)==v.hereName end
  return v.hereBuiltin
 elseif v.hereKind=='custom' then
  for i=1,K.maxPresets do local entry=v.host.presets[i]; if entry and entry.name==v.hereName then return entry.profile==view end end
 end
 return true
end
-- Un profil modifié à la main est réglé : aucun préréglage automatique ne le remplacera.
local function touch(v,p) p.configured=true; mark(v) end
local globalSliders={'occLatMin','occLatMax','occMargin','occSpeedGain','gripPerLevelPct'}
-- Profil automatique conservé : le préréglage règle son profil, la détection choisit toujours la session.
local function presetTarget(v,profile)
 if not v.e.g.autoProfile then Engine.select(v.e,profile) end
 v.view=profile; v.viewFor=v.e.profile
 v.presetMessage=v.e.profile~=profile and string.format(L.presetAppliedTo,L.profiles[profile]) or ''
end
-- Beta 1.29 (demande du pilote) : un préréglage intégré règle tout son profil, règles de championnat comprises (arrêt
-- obligatoire, voiture de sécurité, jeu de règles) ; seules les préférences du pilote et les motifs de classes restent.
-- Essais, Qualifications et Course : ses règles valent pour tout le week-end ; Endurance multi-classes en course y met
-- les règles Endurance (FCY, Slow Zone, BoP, Pro-Am). Journée circuit : le week-end de course reste tel quel.
local function loadBuiltin(v,name,profile)
 local e=v.e
 C.applyBuiltin(e.g,e.profiles,name,profile,false,v.keptRules)
 -- Beta 1.38 (demande du pilote) : préréglage visant un autre profil (Endurance depuis les essais, Course depuis les
 -- qualifications...) : appliqué à ce profil, le profil affiché reste et aucune tuile ne s'allume.
 if profile==v.view then presetTarget(v,profile) else v.presetMessage=string.format(L.presetAppliedTo,L.profiles[profile]) end
 v.presetName=''
 mark(v)
end
-- Allumé quand le profil visé par le bouton porte ce préréglage (préférences du pilote et motifs de classes exclus ;
-- règles de championnat comprises depuis la Beta 1.29). Beta 1.29 (demande du pilote) : seulement pour le profil affiché,
-- et seulement si le pilote y a chargé ce préréglage ; aucun bouton n'est présélectionné.
local noGlobals={}
local function builtinActive(v,name,profile,label)
 local e=v.e
 local candidate=v.builtinConfigs[name][profile]
 -- Les deux signatures finissent par les mêmes réglages globaux : comparées sans eux ; celle du préréglage intégré
 -- (jamais modifié) est calculée une seule fois, celle du profil après chaque modification (révision du moteur,
 -- édition de la fenêtre), jamais à chaque image.
 local active=false
 if candidate~=nil and profile==v.view and C.mark(e.g,profile)==name then
  local key=idOf(name,profile); local memo=v.builtinMemo[key]
  if not memo then memo={}; v.builtinMemo[key]=memo end
  if memo.edits~=v.edits or memo.revision~=e.revision then
   memo.edits=v.edits; memo.revision=e.revision
   local expected=v.builtinSignatures[key]
   if not expected then expected=Presets.signature(profile,candidate,noGlobals,v.signatureValues,C.presetMatchSkip); v.builtinSignatures[key]=expected end
   memo.active=Presets.signature(profile,e.profiles[profile],noGlobals,v.signatureValues,C.presetMatchSkip)==expected
  end
  active=memo.active
 end
 if active then v.activePreset=label end
 return active
end
-- Base des voitures (dossiers content/cars), lue à la demande par étapes (Beta 1.39 : une part à chaque image, jamais
-- tout d'un coup), gardée pour la session ; liste vide tant qu'elle n'est pas finie.
local noCars={}
local function carDatabase(v)
 if v.carList then return v.carList end
 local loader=v.carLoader
 if not loader then loader=Snapshot.carLoader(); v.carLoader=loader end
 if Snapshot.carStep(loader,Adapter.clock,v.host) then
  v.carList=loader.list; v.carNames={}; v.carLoader=nil
  for _,car in ipairs(v.carList) do v.carNames[car.id]=car.name end
  return v.carList
 end
 return noCars,loader
end
-- Fenêtre de réglages « Racing 26 » (Beta 1.35, refonte de Vincent, canevas « AdvancedIA — Refonte UI ») : en-tête
-- fixe de 84 px (marque, version, mise à jour, session, état, langue, activation, panique ; onglets inclinés et choix
-- du profil affiché), puis Accueil, Réglages, Règles de course et Diagnostic. Commandes dessinées par src/widgets ;
-- seules les saisies de texte et la liste des voitures restent natives. Identifiants des commandes inchangés.
local tabs={'home','settings','rules','diagnostic'}
local sidebar={{'drive','general','human','lateral','start'},{'traffic','yield','blue','flash','overtake','traffic'},
 {'race','accidents','sanctions','strategy','lights','endurance','weather'},{'advanced','globals','overlay'}}
local languageOrder={'fr','en'}
local languageLabels={fr='FR',en='EN'}
local HEADER=84
-- Part de la largeur d'une ligne de choix au-delà de laquelle le texte du défaut n'est plus affiché à droite (il reste
-- dans l'infobulle) : le libellé garde sa place.
local DEFAULT_SHARE=0.45
local PAD=14
local GAP=8
-- Saisie de texte native posée sur un cadre dessiné (seulement si entièrement visible dans la zone qui défile).
local function input(id,x,y,w,value,tip,err)
 if not W.visible(y,28) then return value,false end
 W.inputFrame(x,y,w,28,false,err)
 local sc=ui.StyleColor
 local styled=type(sc)=='table' and sc.FrameBg and sc.Text and callable(ui.pushStyleColor)
 if styled then local c=W.colors(); ui.pushStyleColor(sc.FrameBg,c.bg); ui.pushStyleColor(sc.Text,c.text) end
 -- Canevas réduit (fenêtre de moins de 900 px) : la saisie native garde sa police ; marges internes réduites pour
 -- qu'elle tienne dans son cadre, puis centrée.
 local s=W.frame().s; local dy=4; local padded=false
 if s<1 and callable(ui.frameHeight) and callable(ui.textLineHeight) and callable(ui.pushStyleVar) and callable(ui.popStyleVar) and type(ui.StyleVar)=='table' and ui.StyleVar.FramePadding then
  local room=26*s; local fh=ui.frameHeight()
  if type(fh)=='number' and fh>room then
   local line=ui.textLineHeight()
   if type(line)=='number' then ui.pushStyleVar(ui.StyleVar.FramePadding,vec2(4*s,math.max(0,(room-line)/2))); padded=true; fh=math.max(line,room) end
  end
  if type(fh)=='number' then dy=math.max(1,(28-fh/s)/2) end
 end
 ui.setCursor(W.point(x+1,y+dy)); ui.setNextItemWidth((w-2)*s)
 local result,changed=ui.inputText(W.hashId(id),value)
 if padded then ui.popStyleVar(1) end
 if styled then ui.popStyleColor(2) end
 W.help(tip,x,y,w,28,5)
 return result,changed
end
-- Valeur affichée d'un réglage numérique : virgule décimale, entiers sans décimale.
local function valueText(s,value)
 -- Valeur nulle nommée (Beta 1.37 : « pas de vert »).
 if value==0 and L.zeroValues[s.key] then return L.zeroValues[s.key] end
 if C.integerKeys[s.key] then return string.format('%.0f',value) end
 return number(value)
end
-- Texte mémorisé d'un nombre entier (aucune chaîne neuve tant qu'il ne change pas).
local intTexts={}
local function intText(n)
 local t=intTexts[n]
 if not t then t=string.format('%d',n); intTexts[n]=t end
 return t
end
local function shortLabel(s) return L.shortLabels[s.key] or s.label end
-- Réglage modifié : différent de la valeur par défaut du profil affiché.
local function modified(s,value,view)
 local d=s.defaults[view]
 if type(value)=='number' and type(d)=='number' then return math.abs(value-d)>K.uiEpsilon end
 return value~=d
end
local function segmentFits(control,w)
 if control.fitW~=w or control.fitLang~=Locale.current then
  control.fitW=w; control.fitLang=Locale.current
  local cell=w/#control.labels-6; local ok=true
  for _,label in ipairs(control.labels) do if W.width(W.upper(label),11,'cond')>cell then ok=false; break end end
  control.fits=ok
 end
 return control.fits
end
-- Une commande de réglage (.st / .r) dans une colonne de largeur w ; renvoie sa hauteur. Clic droit : valeur par
-- défaut du profil affiché.
-- Pastilles des couleurs de la section Panneaux lumineux (valeur ac.FlagType de chaque réglage).
local lightSwatch={lightsYellow=K.flagCaution,lightsRed=K.flagStop,lightsBlue=K.flagFasterCar,lightsWhite=K.flagSlowVehicle,lightsOrange=K.flagSlippery,lightsGreen=K.flagStart}
local function toggleOpts(v,key,value)
 local sw=lightSwatch[key]
 if not sw then return nil end
 local o=v.lightOpts[key]
 if not o then o={}; v.lightOpts[key]=o end
 o.swatch=v.lightColors and v.lightColors[sw]; o.forced=key=='lightsYellow'
 -- Beta 1.38 (maquette) : note du jaune toujours, celle du rouge seulement quand il est coupé.
 o.note=(key=='lightsYellow' or value==false) and L.lightNotes[key] or nil
 return o
end
local function settingControl(v,control,view,p,x,y,w,locked)
 local c=W.colors(); local s=control.schema; local tip=control.hint[view]
 local value,changed,reset=p[s.key],false,false
 local mod=modified(s,value,view)
 if s.min then
  if W.visible(y,44) then
   local lx=x
   if mod then W.marker(lx,y+9); lx=lx+12 end
   local vt=control.valueFor==value and control.valueShown or valueText(s,value)
   control.valueFor=value; control.valueShown=vt
   local vw=W.width(vt,11,'mono')
   W.cell(shortLabel(s),lx,y+5,w-vw-14-(lx-x),12,c.body)
   W.right(vt,x+w,y+6,11,mod and c.cyan or c.text,'mono')
   W.help(tip,x,y,w,20,4)
   local step=control.step
   local result,right=W.slider(control.id,x+26,y+24,w-52,value,s.min,s.max,step,tip,s.defaults[view])
   if result then value=result; changed=true end
   reset=right
   local minus=W.pm(control.idMinus,'−',x,y+23,tip)
   local plus=W.pm(control.idPlus,'+',x+w-20,y+23,tip)
   if minus then value=math.max(s.min,value-step); changed=true elseif plus then value=math.min(s.max,value+step); changed=true end
   if changed and C.integerKeys[s.key] then value=math.floor(value+0.5) end
   W.rect(x,y+43,w,1,c.ruleSoft)
  end
  if reset then value=s.defaults[view]; changed=value~=p[s.key] end
  if changed then p[s.key]=value; C.validate(view,p,p); touch(v,p) end
  return 44
 elseif s.choices then
  local h=46
  if W.visible(y,h) then
   local at=1; for i,x0 in ipairs(s.choices) do if x0==value then at=i; break end end
   local lx=x
   if mod then W.marker(lx,y+9); lx=lx+12 end
   if control.defaultFor~=view then
    control.defaultFor=view; local d=1; for i,x0 in ipairs(s.choices) do if x0==s.defaults[view] then d=i end end
    -- En minuscules, comme la maquette (« défaut : gauche ») ; refait seulement au changement de profil ou de langue.
    control.defaultText=string.format(L.defaultValue,(control.labels[d] or ''):lower())
   end
   -- Texte du défaut à droite seulement s'il laisse sa place au libellé ; sinon il reste dans l'infobulle.
   local dw=W.labelWidth(control.defaultText)
   local room=dw<=w*DEFAULT_SHARE
   W.cell(shortLabel(s),lx,y+5,(room and w-dw-12 or w)-(lx-x),12,c.body)
   if room then W.label(control.defaultText,x+w-dw,y+6) end
   W.help(tip,x,y,w,20,4)
   local picked,right
   if #s.choices<=3 and segmentFits(control,w) then picked,right=W.segment(control.id,control.labels,x,y+22,w,22,at,tip)
   else
    local clicked; clicked,right=W.cycle(control.id,control.labels[at],x,y+22,w,22,tip)
    if clicked then picked=at%#s.choices+1 end
    local active=W.frame().active; for i=1,#s.choices do active[control.choiceIds[i]]=i==at end
   end
   if picked and picked~=at then value=s.choices[picked]; changed=true end
   reset=right
   W.rect(x,y+h-1,w,1,c.ruleSoft)
  end
  if reset then value=s.defaults[view]; changed=value~=p[s.key] end
  if changed then p[s.key]=value; C.validate(view,p,p); touch(v,p) end
  return h
 end
 local opts=toggleOpts(v,s.key,value)
 -- Jaune des panneaux : toujours actif (allumé, grisé, sans effet).
 if opts and opts.forced then locked=true end
 local h=W.toggleHeight(opts)
 if W.visible(y,h) then
  local clicked,right=W.toggle(control.id,shortLabel(s),x,y,w,value==true,tip,locked,mod and not locked,opts)
  if clicked then value=not value; changed=true end
  reset=right and not locked
 end
 if reset then value=s.defaults[view]; changed=value~=p[s.key] end
 if changed then p[s.key]=value; C.validate(view,p,p); touch(v,p) end
 return h
end
-- Note d'un réglage masqué dans ce profil (pénalités en journée circuit, surcouche Endurance en essais et en
-- qualifications, répartition des IA en course et en hotlap) ; nil sans note.
local function hiddenNote(view,key,shown)
 if C.penaltyKeys[key] or C.sanctionKeys[key] and C.solo(view) then return not shown.penalties and 'penalties' or nil end
 -- Beta 1.42 : stratégie, pannes, aspiration cassée, fin de course et sanctions de course : course seulement.
 if C.raceKeys[key] or C.sanctionRaceKeys[key] then return not shown.race and 'race' or nil end
 if key=='enduranceOverlay' then return 'endurance' end
 if key=='spawnMode' then return 'spawn' end
 if key=='floodRangeKm' and not C.hidden(view,'spawnMode') then return 'flood' end
 -- Beta 1.51 : tours lancés (essais et qualifications), refroidissements des IA (qualifications).
 if key=='qualiTraffic' then return 'quali' end
 -- Beta 1.56 : vos sorties en essais et qualifications, masquées en course.
 if C.sanctionPracticeKeys[key] then return not shown.quali and 'quali' or nil end
 if key=='qualiCoolLaps' then return not C.hidden(view,'qualiTraffic') and 'qualiQ' or not shown.quali and 'quali' or nil end
 return nil
end
local noteTexts={quali='qualiOnlySetting',qualiQ='qualifyingOnlySetting',race='raceOnlySetting',penalties='penaltiesTrackDay',endurance='enduranceNotAvailable',spawn='spawnNotAvailable',flood='floodNotAvailable'}
-- Hauteur estimée d'un sous-groupe (répartition des deux colonnes) : titre 30, curseur 44, choix 46, interrupteur 28.
local heightShown={}
local function groupHeight(group,view)
 local h=30
 for k in pairs(heightShown) do heightShown[k]=nil end
 for _,control in ipairs(group.controls) do
  local s=control.schema
  if C.hidden(view,s.key) then local note=hiddenNote(view,s.key,heightShown); if note then heightShown[note]=true; h=h+36 end
  else h=h+(s.min and 44 or s.choices and 46 or (L.lightNotes[s.key] and 42 or 28)) end
 end
 return h
end
-- Réglages qui dépendent d'un interrupteur (Beta 1.38, maquette) : grisés tant qu'il est coupé.
local dependsOn={overtakeModeGap='overtakeMode',overtakeModeBoostPct='overtakeMode',bopStrengthPct='bopEnabled'}
-- Sous-groupe : intertitre (titre et sous-titre), puis ses réglages ; renvoie la hauteur dessinée.
local function drawGroup(v,group,view,p,x,y,w,shown,lockedKey)
 local c=W.colors(); local top=y
 local titles=L.subgroups[group.id] or L.subgroups.other
 if W.visible(y,24) then W.heading(titles[1],x,y,w,titles[2]) end
 y=y+30
 for k in pairs(shown) do shown[k]=nil end
 for _,control in ipairs(group.controls) do
  local s=control.schema
  if C.hidden(view,s.key) then
   local note=hiddenNote(view,s.key,shown)
   if note then
    shown[note]=true
    local text=L[noteTexts[note]]
    local h=#W.lines(text,w,12)*W.lineHeight(12)+12
    if W.visible(y,h) then W.paragraph(text,x,y+6,w,12,c.label); W.rect(x,y+h-1,w,1,c.ruleSoft) end
    y=y+h
   end
  else
   local h=settingControl(v,control,view,p,x,y,w,lockedKey==s.key)
   local parent=dependsOn[s.key]
   if parent and p[parent]~=true and W.visible(y,h) then W.rect(x,y,w,h,c.veil) end
   y=y+h
   -- Jaune natif du HUD remplacé par les panneaux lumineux : note sous sa ligne (maquette).
   if lockedKey==s.key then y=y+W.paragraph(L.yellowHudLocked,x+2,y+3,w-4,11,c.label)+8 end
  end
 end
 return y-top
end
-- Répartition en deux colonnes équilibrées (mémorisée par liste et par profil affiché).
local function split(v,key,list,view)
 local memo=v.splits[key]
 if not memo then memo={cols={}}; v.splits[key]=memo end
 if memo.list~=list or memo.view~=view then
  memo.list=list; memo.view=view
  local total=0; for _,g in ipairs(list) do total=total+groupHeight(g,view) end
  local acc=0; local left=0
  for i,g in ipairs(list) do
   local h=groupHeight(g,view)
   if left==0 or acc+h/2<=total/2 then memo.cols[i]=1; acc=acc+h; left=left+1 else memo.cols[i]=2 end
  end
  for i=#list+1,#memo.cols do memo.cols[i]=nil end
 end
 return memo.cols
end
-- Réglages d'une section en sous-groupes, sur deux colonnes si la largeur le permet ; renvoie le bas du contenu.
-- single (Beta 1.38) : une seule colonne (couleurs et durées des panneaux lumineux, maquette).
local function groupColumns(v,key,list,view,p,x,y,w,lockedKey,single)
 local two=w>=560 and not single
 local cw=two and (w-18)/2 or w
 local cols=split(v,key,list,view)
 local yl,yr=y,y
 v.groupShown=v.groupShown or {}
 for i,group in ipairs(list) do
  if two and cols[i]==2 then yr=yr+(yr>y and 8 or 0); yr=yr+drawGroup(v,group,view,p,x+cw+18,yr,cw,v.groupShown,lockedKey)
  else yl=yl+(yl>y and 8 or 0); yl=yl+drawGroup(v,group,view,p,x,yl,cw,v.groupShown,lockedKey) end
 end
 return math.max(yl,yr)
end
-- Bloc des règles de championnat (colonne de gauche de l'onglet Règles de course) : une ligne par jeu de règles (nom,
-- caractéristiques, puce « Actif »), puis la réinitialisation.
local function ruleBlock(v,e,x,y,w)
 local c=W.colors()
 local category,target=ruleCategoryOf(v,e)
 local top=y
 local note=C.solo(v.view) and L.ruleJ or L.rulePresets
 local nh=#W.lines(note,w-20,12)*W.lineHeight(12)
 local listH=#C.ruleCategories*43
 local tail=#W.lines(L.ruleRaceOnly,w-20,12)*W.lineHeight(12)
 local height=8+24+6+nh+6+listH+6+tail+8+28+10
 W.panel(x,y,w,height)
 y=y+8
 if W.visible(y,24) then W.heading(L.ruleSetsHeading,x+10,y,w-20) end
 y=y+30
 if W.visible(y,nh) then W.paragraph(note,x+10,y,w-20,12,c.label) end
 y=y+nh+6
 for _,name in ipairs(C.ruleCategories) do
  if W.visible(y,40) then
   local active=category==name
   if W.row(idOf('rules_',name),x+10,y,w-20,40,active,v.tips.rules[name]) then
    C.applyRules(name,e.profiles); v.presetMessage=string.format(L.ruleApplied,L.ruleNames[name]); mark(v)
   end
   local cw=active and W.chipWidth(L.chipActive) or 0
   W.cell(W.upper(L.ruleNames[name]),x+20,y+5,w-44-cw,13,active and c.cyanText or c.text,'cond')
   W.cell(L.ruleMeta[name] or '',x+20,y+22,w-44-cw,11,c.label,'mono')
   if active then W.chip(L.chipActive,x+w-20-cw,y+12,'C') end
  end
  y=y+43
 end
 y=y+3
 if W.visible(y,tail) then W.paragraph(L.ruleRaceOnly,x+10,y,w-20,12,c.label) end
 y=y+tail+8
 if W.visible(y,28) then
  -- Jeu de règles le plus proche : refait seulement après une modification ou pour un autre profil visé.
  if v.closestEdits~=v.edits or v.closestRevision~=e.revision or v.closestTarget~=target then
   v.closestEdits=v.edits; v.closestRevision=e.revision; v.closestTarget=target; v.closestName=C.closestRuleCategory(target,e.profiles[target],C.switchKeys)
  end
  local name=v.closestName
  if v.rulesResetFor~=name then v.rulesResetFor=name; v.rulesResetText=string.format(L.rulesResetTo,L.ruleNames[name]) end
  if W.button('rules_reset',v.rulesResetText,x+10,y,w-20,28,false,v.tips.ui.rulesReset,'outline') then
   C.applyRules(name,e.profiles); v.presetMessage=string.format(L.ruleApplied,L.ruleNames[name]); mark(v)
  end
 end
 y=y+38
 return top+math.max(height,y-top)+8
end
-- Voiture de sécurité : modèle choisi et sa présence sur la grille, étapes de sa sortie, saisie du dossier, filtre et
-- liste de la base des voitures.
-- Phases de la bande (maquette) : garée, appelée, en piste, rentre ce tour, aux stands ; lignes de la base montrées.
local safetyStrip={parked=1,call=2,exit=2,place=2,out=3,['in']=4,parking=5}
local SAFETY_ROWS=8
local function safetyBlock(v,e,x,y,w)
 local c=W.colors(); local g=e.g
 local list,loading=carDatabase(v)
 local found=g.safetyCarModel~='' and e.incidents.safety>0
 if W.visible(y,24) then
  W.heading(L.safetyGridHeading,x,y,w)
  if g.safetyCarModel~='' then W.chipRight(found and L.safetyPresent or L.safetyAbsent,x+w,y+3,found and 'g' or 'a') end
 end
 y=y+30
 if g.safetyCarModel~='' then
  if W.visible(y,56) then
   W.rect(x,y,w,56,c.select); W.frameRect(x,y,w,56,c.selectLine)
   W.cell(W.upper(v.carNames and v.carNames[g.safetyCarModel] or g.safetyCarModel),x+12,y+8,w-140,20,c.text,'display')
   local phase=found and (L.safetyPhases[e.incidents.safetyPhase] or '') or L.safetyMissing
   W.cell(fmt(v,'safetyLine','%s · %s',g.safetyCarModel,phase),x+12,y+34,w-140,11,c.muted,'mono')
   if W.button('safety_clear',L.safetyClearShort,x+w-112,y+14,100,28,false,v.tips.ui.safetyClear) then g.safetyCarModel=''; v.dirty() end
  end
  y=y+64
  -- Phase de la voiture de sécurité (Beta 1.38, maquette) : cinq barres, la phase en cours en cyan.
  if W.visible(y,26) then
   local current=found and safetyStrip[e.incidents.safetyPhase] or 0
   local bw=(w-12)/5
   for i=1,5 do
    local bx=x+(i-1)*(bw+3)
    W.para(bx,y,bw,5,i==current and c.cyan or c.rule,1.5)
    W.cell(W.upper(L.safetyPhaseStrip[i]),bx,y+10,bw,11,i==current and c.cyanText or c.label,'label')
   end
  end
  y=y+30
  if e.safetyAmbiguous then y=y+W.message(L.safetyAmbiguous,x,y,w,'wn')+6 end
  if e.safetyOneMake then y=y+W.message(L.safetyOneMake,x,y,w,'wn')+6 end
 else
  y=y+W.message(fmt(v,'safetyNone','%s%s',L.safetyCar,L.safetyNone),x,y,w,'mut')+6
 end
 -- Étapes de la sortie (1 à 4).
 if W.visible(y,24) then W.heading(L.safetyStepsHeading,x,y,w) end
 y=y+30
 for i,step in ipairs(L.safetySteps) do
  local h=#W.lines(step,w-30,12)*W.lineHeight(12)+6
  if W.visible(y,h) then
   -- Étapes 1 et 2 (incident, aggravation) en ambre, 3 et 4 (voiture en piste, relance) en cyan (maquette).
   W.rect(x,y,20,18,i<=2 and c.warnBack or c.select); W.text(intText(i),x+6,y+2,11,i<=2 and c.warn or c.cyanText,'mono')
   W.paragraph(step,x+30,y+1,w-30,12,c.body)
  end
  y=y+math.max(h,24)
 end
 y=y+4
 -- Filtre puis modèle, côte à côte, libellés au-dessus (Beta 1.38, maquette).
 local half=(w-10)/2
 if W.visible(y,14) then W.label(L.safetyFilter,x,y); W.label(L.safetyModel,x+half+10,y) end
 y=y+18
 v.carFilter=input('safety_filter',x,y,half,v.carFilter or '',v.tips.ui.safetyFilter) or ''
 local value,changed=input('safety_model',x+half+10,y,half,g.safetyCarModel,v.tips.ui.safetyModel)
 if changed and type(value)=='string' and #value<=K.metadataLength and value:match('^[%w_%-%.]*$') then g.safetyCarModel=value; g.safetyCarPicked=true; v.dirty() end
 y=y+36
 -- Base des voitures en lignes (nom, puis dossier en chiffres alignés), filtrée par une partie du nom affiché ou du
 -- dossier, refaite seulement quand le filtre change ; au plus SAFETY_ROWS lignes, les autres comptées.
 if v.carFilterRaw~=v.carFilter then v.carFilterRaw=v.carFilter; v.carFilterLower=v.carFilter:lower() end
 local filter=v.carFilterLower; local rows=v.carRows or {}; v.carRows=rows
 if v.carFilterBuilt~=filter or v.carRowsFor~=list then
  v.carFilterBuilt=filter; v.carRowsFor=list; local n=0
  for _,car in ipairs(list) do if filter=='' or car.key:find(filter,1,true) then n=n+1; rows[n]=car end end
  for j=#rows,n+1,-1 do rows[j]=nil end
  v.carMoreText=n>SAFETY_ROWS and string.format(L.safetyMore,n-SAFETY_ROWS) or nil
 end
 -- Lecture de la base en cours : « n / N » à la place des lignes.
 if loading then y=y+W.message(fmt(v,'carLoading',L.carLoading,loading.read,#loading.folders),x,y,w,'mut')+4 end
 for i=1,math.min(#rows,SAFETY_ROWS) do
  local car=rows[i]
  if W.visible(y,28) then
   local picked=car.id==g.safetyCarModel
   if W.row(idOf('safety_pick_',i),x,y,w,28,picked,v.tips.ui.safetyPick) then g.safetyCarModel=car.id; g.safetyCarPicked=true; v.dirty() end
   local iw=W.width(car.id,11,'mono')
   W.cell(car.name,x+10,y+8,w-iw-30,12,picked and c.cyanText or c.text)
   W.right(car.id,x+w-10,y+9,11,c.label,'mono')
  end
  y=y+31
 end
 if v.carMoreText then y=y+W.message(v.carMoreText,x,y,w,'mut')+4 end
 y=y+4
 return y+W.message(L.safetyGridNote,x,y,w,'mut')+8
end
-- Motifs de classes : saisie libre, ou les huit associations motif → classe (segment des classes, effacement).
local function patternBlock(v,p,x,y,w)
 local c=W.colors()
 if v.patternSource~=p.classPatterns or v.patternProfile~=v.view then
  local rows=C.patterns(p.classPatterns)
  for i=1,K.maxPatterns do local r=v.patternRows[i]; r.pattern=rows[i] and rows[i].pattern or ''; r.class=rows[i] and rows[i].class or 1 end
  v.patternSource=p.classPatterns; v.patternProfile=v.view; v.patternAdded=nil
 end
 local used=0; for i=1,K.maxPatterns do if v.patternRows[i].pattern~='' then used=used+1 end end
 if v.patternCountFor~=used then v.patternCountFor=used; v.patternCountText=string.format(L.patternCount,used,K.maxPatterns) end
 if W.visible(y,24) then W.heading(L.patternsHeading,x,y,w,v.patternCountText,'mono') end
 y=y+30
 if W.visible(y,28) and W.toggle('pattern_rows',L.patternRows,x,y,w,v.open.patternRows==true,v.tips.ui.patternRows) then v.open.patternRows=not v.open.patternRows end
 y=y+34
 if not v.open.patternRows then
  if W.visible(y,28) then W.label(L.patterns,x,y+8) end
  local value,changed=input('patterns',x+230,y,w-230,p.classPatterns,v.tips.ui.patterns,v.patternInvalid)
  if changed then local _,valid=C.patterns(value); v.patternInvalid=not valid; if valid then p.classPatterns=value; touch(v,p) end end
  y=y+34
  if v.patternInvalid then y=y+W.message(L.patternInvalid,x,y,w,'er')+6 end
  return y+W.message(L.patternHelp,x,y,w,'mut')+8
 end
 if W.visible(y,20) then W.label(L.patternColumn,x+28,y+4); W.label(L.classColumn,x+w-186,y+4) end
 y=y+22
 local edited=false
 -- Lignes montrées (Beta 1.38, maquette) : celles remplies, au moins une, plus celles ajoutées par « + Ajouter une ligne ».
 local lastUsed=0; for i=1,K.maxPatterns do if v.patternRows[i].pattern~='' then lastUsed=i end end
 local shownRows=math.min(K.maxPatterns,math.max(1,lastUsed,v.patternAdded or 0))
 for i=1,shownRows do
  local row=v.patternRows[i]
  if W.visible(y,28) then W.text(intText(i),x,y+7,11,c.label,'mono') end
  local text,textChanged=input(v.patternIds[i],x+28,y,w-28-196,row.pattern,v.tips.ui.patternRow)
  if textChanged then row.pattern=text; edited=true end
  if W.visible(y,28) then
   local picked=W.segment(v.patternClassIds[i],v.classLabels,x+w-186,y+3,150,22,row.class,v.tips.ui.classRow)
   if picked and picked~=row.class then row.class=picked; edited=true end
   if W.icon(v.patternClearIds[i],'close',x+w-28,y,v.tips.ui.patternClear) and row.pattern~='' then row.pattern=''; edited=true end
  end
  y=y+32
 end
 if W.visible(y,26) then
  local bw=math.max(150,W.width(W.upper(L.patternAdd),12,'display')+30)
  if W.button('pattern_add',L.patternAdd,x,y,bw,26,false,v.tips.ui.patternRows,shownRows>=K.maxPatterns and 'disabled' or 'outline') then v.patternAdded=shownRows+1 end
 end
 y=y+32
 if edited then
  local count=0; local valid=true
  for i=1,K.maxPatterns do
   local r=v.patternRows[i]
   if r.pattern~='' then
    if #r.pattern>K.maxPatternLength or not r.pattern:match('^[%w_%-]+$') then valid=false end
    count=count+1; v.patternFragments[count]=r.pattern..':'..r.class
   end
  end
  for i=#v.patternFragments,count+1,-1 do v.patternFragments[i]=nil end
  v.patternInvalid=not valid
  if valid then p.classPatterns=table.concat(v.patternFragments,','); v.patternSource=p.classPatterns; p.configured=true; Engine.changed(v.e); v.dirty() end
 end
 if v.patternInvalid then y=y+W.message(L.patternInvalid,x,y,w,'er')+6 end
 return y+W.message(L.patternHelp,x,y,w,'mut')+8
end
-- Interrupteur d'un réglage global (options globales, overlay) : clic pour basculer, clic droit pour la valeur par
-- défaut, comme les curseurs.
local function globalSwitch(v,g,id,key,label,x,y,w,tip)
 local clicked,right=W.toggle(id,label,x,y,w,g[key]==true,tip,false,g[key]~=C.globalDefaults[key])
 if clicked then g[key]=not g[key]; v.dirty()
 elseif right and g[key]~=C.globalDefaults[key] then g[key]=C.globalDefaults[key]; v.dirty() end
end
-- Choix global en segment s'il tient dans sa largeur, sinon bouton à défilement (polices de secours plus larges) ;
-- renvoie l'indice choisi (ou nil) et le clic droit.
local function globalChoice(id,labels,x,y,w,at,tip)
 if W.segmentFits(labels,w) then return W.segment(id,labels,x,y,w,22,at,tip) end
 local clicked,right=W.cycle(id,labels[at],x,y,w,22,tip)
 local active=W.frame().active; local ids=W.choiceIds(id,#labels)
 for i=1,#labels do active[ids[i]]=i==at end
 return clicked and at%#labels+1 or nil,right
end
-- Réglage global à curseur (options globales, overlay) : libellé, valeur, curseur avec repère du défaut.
local function globalSlider(v,g,id,key,label,valueLabel,x,y,w,step,tip)
 local c=W.colors(); local bounds=C.globalBounds[key]
 if W.visible(y,44) then
  local mod=math.abs((g[key] or 0)-(C.globalDefaults[key] or 0))>K.uiEpsilon
  local lx=x; if mod then W.marker(lx,y+9); lx=lx+12 end
  local vw=W.width(valueLabel,11,'mono')
  W.cell(label,lx,y+5,w-vw-14-(lx-x),12,c.body)
  W.right(valueLabel,x+w,y+6,11,mod and c.cyan or c.text,'mono')
  W.help(tip,x,y,w,20,4)
  local result,right=W.slider(id,x,y+24,w,g[key],bounds[1],bounds[2],step,tip,C.globalDefaults[key])
  if right then result=C.globalDefaults[key] end
  if result then g[key]=result; C.validateGlobals(g,g); v.dirty() end
  W.rect(x,y+43,w,1,c.ruleSoft)
 end
 return 44
end
-- Libellé d'un choix global et « défaut : … » à droite, s'il laisse sa place au libellé (comme les choix des sections ;
-- Beta 1.38, maquette).
local function choiceHead(label,default,x,y,w)
 local c=W.colors()
 local dw=default and W.labelWidth(default) or 0
 local room=default~=nil and dw<=w*DEFAULT_SHARE
 W.cell(label,x,y+5,room and w-dw-12 or w,12,c.body)
 if room then W.label(default,x+w-dw,y+6) end
end
-- Options globales (toutes les sessions) : niveau et aides, occupation latérale, personnalités.
local function globalBlock(v,e,x,y,w)
 local c=W.colors(); local g=e.g; local tips=v.globalTips
 local two=w>=560; local cw=two and (w-18)/2 or w
 local yl,yr=y,y
 -- Niveau et aides.
 if W.visible(yl,24) then W.heading(L.subgroups.globalsLevel[1],x,yl,cw,L.subgroups.globalsLevel[2]) end
 yl=yl+30
 if W.visible(yl,46) then
  choiceHead(L.levelRequested,v.levelDefault,x,yl,cw); W.help(tips.levelMode,x,yl,cw,20,4)
  local at=1; for j,x0 in ipairs(C.globalChoices.levelMode) do if x0==g.levelMode then at=j end end
  local clicked,right=W.cycle('global_levelMode',L.levelModeLabels[at],x,yl+22,cw,22,tips.levelMode)
  if clicked then g.levelMode=C.globalChoices.levelMode[at%#C.globalChoices.levelMode+1]; v.dirty()
  elseif right and g.levelMode~=C.globalDefaults.levelMode then g.levelMode=C.globalDefaults.levelMode; v.dirty() end
  W.rect(x,yl+45,cw,1,c.ruleSoft)
 end
 yl=yl+46
 for _,item in ipairs(v.globalSwitches) do
  local key=item[1]
  if W.visible(yl,28) then globalSwitch(v,g,idOf('global_',key),key,item[2],x,yl,cw,tips[key]) end
  yl=yl+28
  -- Bonus de grip par point de niveau : juste sous son interrupteur (Beta 1.38, maquette).
  if key=='useGripBoost' then
   if v.gripFor~=g.gripPerLevelPct then v.gripFor=g.gripPerLevelPct; v.gripText=number(g.gripPerLevelPct) end
   yl=yl+globalSlider(v,g,'global_gripPerLevelPct','gripPerLevelPct',L.globalLabels.gripPerLevelPct,v.gripText,x,yl,cw,W.step(C.globalBounds.gripPerLevelPct[1],C.globalBounds.gripPerLevelPct[2]),tips.gripPerLevelPct)
  end
 end
 -- Occupation latérale et personnalités (seconde colonne).
 local rx=two and x+cw+18 or x
 if not two then yr=yl+8 end
 if W.visible(yr,24) then W.heading(L.subgroups.globalsOccupation[1],rx,yr,cw,L.subgroups.globalsOccupation[2]) end
 yr=yr+30
 for _,key in ipairs(globalSliders) do
  if key~='gripPerLevelPct' then
   local bounds=C.globalBounds[key]
   yr=yr+globalSlider(v,g,idOf('global_',key),key,L.globalShort[key] or L.globalLabels[key],number(g[key]),rx,yr,cw,W.step(bounds[1],bounds[2]),tips[key])
  end
 end
 -- Personnalités (maquette, Beta 1.39) : en pleine largeur sous les deux colonnes, hors du voile d'une section
 -- décochée. Renvoie le bas de la liste des réglages, puis le bas du bloc.
 local listBottom=math.max(yl,yr)
 local py=listBottom+8
 if W.visible(py,24) then W.heading(L.subgroups.globalsSeed[1],x,py,w,L.subgroups.globalsSeed[2]) end
 py=py+30
 if W.visible(py,46) then
  W.cell(L.seed,x,py+4,w-140,12,c.body); W.help(tips.seed,x,py,w-140,46,4)
  if v.seedFor~=g.seed then v.seedFor=g.seed; v.seedText=string.format('%.0f',g.seed) end
  W.text(v.seedText,x,py+22,18,c.text,'mono')
  if W.button('reroll',L.reroll,x+w-130,py+10,130,28,false,v.tips.ui.reroll,'primary') then g.seed=math.floor(U.unit(g.seed,1,1)*C.globalBounds.seed[2]); mark(v) end
 end
 py=py+52
 py=py+W.paragraph(L.rerollNote,x,py,w,12,c.label)+8
 return listBottom,py+8
end
-- État de la section (trafic, météo, accidents, arrêts) au-dessus de ses réglages.
local function statusLines(v,e,group,view,p,out)
 if group=='traffic' then
  out[#out+1]=fmt(v,'traffic',L.trafficStats,e.traffic.connected,e.traffic.count)
  if view~='J' then out[#out+1]=L.trafficOnlyJ end
  if not v.host.caps.speed.available then out[#out+1]=L.trafficUnavailable end
 elseif group=='weather' and e.frame then
  local wet,known,fallback=0,0,0
  for i=1,e.frame.count do local a=e.frame.cars[i]
   if a.valid and a.control and not a.player then
    if a.tyresKnown then known=known+1 end
    if a.nativeRainTyres then wet=wet+1 end
    if e.commands[i].weatherManaged and (e.commands[i].weatherGrip or 1)>1 then fallback=fallback+1 end
   end
  end
  out[#out+1]=fmt(v,'weather',L.weatherStatus,e.frame.wet*100,wet,fallback,known)
 elseif group=='strategy' then
  if view~='C' then out[#out+1]=L.strategyOnlyRace end
 elseif group=='sanctions' then
  if C.solo(view) then out[#out+1]=L.sanctionsWeekend elseif view~='C' then out[#out+1]=L.sanctionsPractice end
 elseif group=='accidents' then
  local t=e.incidents
  out[#out+1]=fmt(v,'accidents',L.accidentStatus,t.activeCount,t.zoneCount,t.holdCount,L.neutralNames[t.neutral and t.neutralMode or 'none'])
  if t.red then out[#out+1]=fmt(v,'red',L.redStatus,t.redInPits,t.redTotal) end
 elseif group=='rules' and v.rulesView=='stops' and view=='C' and p.mandatoryStops>0 then
  local pits=e.pits
  out[#out+1]=fmt(v,'pits',L.pitStatus,L.pitStates[pits.state],pits.csp and L.pitSourceCsp or L.pitSourceRules,pits.done,pits.total)
  if pits.progress<0 and not pits.csp then out[#out+1]=L.pitProgressUnknown end
 end
 return out
end
-- Réglages de l'overlay en jeu (Beta 1.25, refonte Racing 26) : taille et fond, apparence, contenu, affichages
-- d'Assetto Corsa, comportement, puis les panneaux lumineux du circuit (Beta 1.32).
local overlayContentKeys={'overlaySession','overlayExplain','overlayRecap'}
local overlayNativeKeys={'overlayNativeBox','overlayMessages','overlayBlockMessages','cspHideMessages','cspHideFlags'}
local overlayBehaviourKeys={'overlayClickThrough','overlayHideReplay','overlayHidePits'}
local overlayResetKeys={'overlayX','overlayY','overlayScale','overlayLocked','overlayBackground','overlayContent','panelOpacity','panelShow','panelInfoTime',
 'overlaySession','overlayExplain','overlayRecap','overlayNativeBox','overlayMessages','overlayBlockMessages','cspHideMessages','cspHideFlags','cspMessagesLost',
 'overlayClickThrough','overlayHideReplay','overlayHidePits'}
local backgroundKeys=C.globalChoices.overlayBackground
local function switchList(v,g,keys,titles,x,y,w)
 if W.visible(y,24) then W.heading(titles[1],x,y,w,titles[2]) end
 y=y+30
 for _,key in ipairs(keys) do
  if W.visible(y,28) then
   local before=g[key]
   globalSwitch(v,g,idOf('overlay_',key),key,L.overlayShort[key] or L.overlaySwitches[key],x,y,w,v.globalTips[key])
   -- Beta 1.40 : recocher l'option rend une nouvelle chance au masquage par CSP (messages perdus par l'overlay).
   if key=='cspHideMessages' and g[key]~=before then g.cspMessagesLost=false end
  end
  y=y+28
 end
 return y
end
-- Options de CSP tenues par l'app (Beta 1.40) : état sous leurs interrupteurs, texte et genre ; nil s'il n'y a rien à dire.
local cspTexts={waiting={'cspWaiting','mut'},pending={'cspPending','wn'},readonly={'cspReadonly','wn'},capped={'cspCapped','wn'},applied={'cspApplied','gr'}}
local function cspStatus(host,g)
 if g.cspMessagesLost and g.cspHideMessages then return L.cspLost,'wn' end
 local t=host.cspgui and cspTexts[Cspgui.view(host.cspgui)]
 if t then return L[t[1]],t[2] end
 return nil
end
-- Drapeaux d'AC masqués par l'app, pas encore appliqués par CSP (effet au prochain lancement du jeu).
local function flagsNext(host) return host.cspgui~=nil and Cspgui.pending(host.cspgui,'HIDE_RACE_FLAGS') end
local function overlayBlock(v,e,x,y,w)
 local c=W.colors(); local g=e.g; local tips=v.globalTips
 local two=w>=560; local cw=two and (w-18)/2 or w
 local yl,yr=y,y
 -- Taille et fond.
 if W.visible(yl,24) then W.heading(L.subgroups.overlaySize[1],x,yl,cw,L.subgroups.overlaySize[2]) end
 yl=yl+30
 if v.scaleFor~=g.overlayScale then v.scaleFor=g.overlayScale; v.scaleText=number(g.overlayScale)..'×' end
 yl=yl+globalSlider(v,g,'overlay_scale','overlayScale',L.overlayScale,v.scaleText,x,yl,cw,K.overlayScaleStep,tips.overlayScale)
 if W.visible(yl,46) then
  choiceHead(L.overlayBackground,v.backgroundDefault,x,yl,cw); W.help(tips.overlayBackground,x,yl,cw,20,4)
  local at=1; for i,k in ipairs(backgroundKeys) do if k==g.overlayBackground then at=i end end
  local picked,right=globalChoice('overlay_background',v.backgroundLabels,x,yl+22,cw,at,tips.overlayBackground)
  if picked and picked~=at then g.overlayBackground=backgroundKeys[picked]; v.dirty()
  elseif right and g.overlayBackground~=C.globalDefaults.overlayBackground then g.overlayBackground=C.globalDefaults.overlayBackground; v.dirty() end
  W.rect(x,yl+45,cw,1,c.ruleSoft)
 end
 yl=yl+46+8
 -- Apparence.
 if W.visible(yl,24) then W.heading(L.subgroups.overlayLook[1],x,yl,cw,L.subgroups.overlayLook[2]) end
 yl=yl+30
 if v.opacityFor~=g.panelOpacity then v.opacityFor=g.panelOpacity; v.opacityText=string.format('%.0f',g.panelOpacity) end
 yl=yl+globalSlider(v,g,'panel_opacity','panelOpacity',L.overlayOpacity,v.opacityText,x,yl,cw,K.panelOpacityStep,tips.panelOpacity)
 if v.contentFor~=g.overlayContent then v.contentFor=g.overlayContent; v.contentText=string.format('%.0f',g.overlayContent) end
 yl=yl+globalSlider(v,g,'overlay_content','overlayContent',L.overlayContent,v.contentText,x,yl,cw,K.overlayContentStep,tips.overlayContent)
 if W.visible(yl,46) then
  choiceHead(L.overlayShow,v.showDefault,x,yl,cw); W.help(tips.panelShow,x,yl,cw,20,4)
  local at=g.panelShow=='always' and 2 or 1
  local picked,right=globalChoice('panel_show',v.showLabels,x,yl+22,cw,at,tips.panelShow)
  if picked and picked~=at then g.panelShow=picked==2 and 'always' or 'info'; v.dirty()
  elseif right and g.panelShow~=C.globalDefaults.panelShow then g.panelShow=C.globalDefaults.panelShow; v.dirty() end
  W.rect(x,yl+45,cw,1,c.ruleSoft)
 end
 yl=yl+46
 if v.infoFor~=g.panelInfoTime then v.infoFor=g.panelInfoTime; v.infoText=g.panelInfoTime>0 and string.format('%.0f',g.panelInfoTime) or L.overlayInfoAlways end
 yl=yl+globalSlider(v,g,'panel_info_time','panelInfoTime',L.overlayInfoTime,v.infoText,x,yl,cw,K.panelInfoStep,tips.panelInfoTime)
 -- Contenu, affichages d'AC, comportement (seconde colonne).
 local rx=two and x+cw+18 or x
 if not two then yr=yl+8 end
 yr=switchList(v,g,overlayContentKeys,L.subgroups.overlayContents,rx,yr,cw)+8
 yr=switchList(v,g,overlayNativeKeys,L.subgroups.overlayNative,rx,yr,cw)
 local cspText,cspKind=cspStatus(v.host,g)
 if cspText then yr=yr+4+W.message(cspText,rx,yr+4,cw,cspKind)+4 end
 yr=yr+8
 yr=switchList(v,g,overlayBehaviourKeys,L.subgroups.overlayBehaviour,rx,yr,cw)
 y=math.max(yl,yr)+10
 -- Panneaux lumineux du circuit : réglés dans leur section (Beta 1.37), une ligne y mène.
 if W.visible(y,24) then
  local lw=W.linkWidth(L.lightsLink)
  W.rect(x,y,w,1,c.ruleSoft)
  W.cell(L.overlayLightsLink,x,y+8,w-lw-12,12,c.body)
  if W.link('overlay_lights',L.lightsLink,x+w-lw,y+7,v.tips.tabs.lights) then v.category='lights'; v.presetMessage='' end
 end
 return y+30
end
-- Neutralisation affichée avec le jaune des panneaux (« · VSC », Beta 1.38) ; texte vide sinon.
local phaseTexts={vsc='lightsPhaseVsc',fcy='lightsPhaseFcy',sc='lightsPhaseSc'}
local function lightsPhase(e,value)
 local t=e.incidents
 local key=value==K.flagCaution and t.neutral and phaseTexts[t.neutralMode]
 return key and L[key] or ''
end
-- Section Panneaux lumineux (Beta 1.37) : état du circuit en tête (lecture de sa configuration, couleur en cours).
local function lightsStatus(v,p,x,y,w)
 local c=W.colors(); local host=v.host
 if W.visible(y,24) then W.heading(L.subgroups.lightsStatus[1],x,y,w,L.subgroups.lightsStatus[2]) end
 y=y+30
 local status=host.trackLights==true and fmt(v,'lightsOn',L.trackLightsOn,host.trackLightsSource) or host.trackLights==false and L.trackLightsOff or L.trackLightsUnknown
 y=y+W.message(status,x,y,w,host.trackLights==true and 'gr' or 'mut')+6
 if host.trackLights~=true then y=y+W.paragraph(L.lightsNoEffect,x,y,w,12,c.label)+6 end
 if host.trackLights==true and C.on(p,'lights') then
  local value=host.flagOverride and host.flagValue or 0
  if W.visible(y,18) then
   W.circle(x+7,y+8,7,v.lightColors[value] or c.rule)
   -- Couleur et neutralisation en cours (« jaune · VSC », maquette).
   W.cell(fmt(v,'lightsState2','%s%s',fmt(v,'lightsState',L.trackLightsState,L.lightNames[value] or ''),lightsPhase(v.e,value)),x+22,y+1,w-22,12,c.body)
  end
  y=y+24
 end
 return y
end
-- Section Panneaux lumineux (Beta 1.38, maquette) : légende des six couleurs (nom en demi-gras, texte replié, durée du
-- vert), puis l'avertissement du rouge. Lignes coupées une fois par largeur, langue et durée du vert.
local function legendRows(v,p,lw)
 local green=p.lightsGreenTime or 0
 local m=v.legendMemo
 if m and m.w==lw and m.green==green and m.lang==Locale.current then return m end
 m={w=lw,green=green,lang=Locale.current}; v.legendMemo=m
 for i,item in ipairs(L.lightLegend) do
  local desc=item[2]
  if i==1 and green>0 then desc=desc..string.format(L.lightsGreenFor,number(green)) end
  local lines=W.lines(item[1]..' · '..desc,lw-26,12)
  local row={name=item[1],first=(lines[1] or ''):sub(#item[1]+1),rest={},nameW=W.width(item[1],12,'sb')}
  for k=2,#lines do row.rest[k-1]=lines[k] end
  m[i]=row
 end
 return m
end
local function lightsLegend(v,p,x,y,w)
 local c=W.colors(); local host=v.host; local two=w>=560
 local lw=two and (w-18)/2 or w
 if W.visible(y,24) then W.heading(L.lightsLegendTitle[1],x,y,w,L.lightsLegendTitle[2]) end
 y=y+32
 local rows=legendRows(v,p,lw)
 local lh=W.lineHeight(12); local n=#L.lightLegend; local step=two and 2 or 1
 for i=1,n,step do
  local h=0
  for k=i,math.min(n,i+step-1) do
   local row=rows[k]
   local cx=two and x+(k-i)*(lw+18) or x
   local rh=(1+#row.rest)*lh
   if W.visible(y,rh) then
    W.circle(cx+7,y+8,7,v.legendColors[k])
    W.text(row.name,cx+22,y+1,12,c.text,'sb')
    W.text(row.first,cx+22+row.nameW,y+1,12,c.muted)
    for j,line in ipairs(row.rest) do W.text(line,cx+22,y+1+j*lh,12,c.muted) end
   end
   h=math.max(h,rh)
  end
  y=y+h+7
 end
 y=y+2
 if host.trackLights==true and C.on(p,'lights') and p.lightsRed~=false and host.raceFlagsHidden~=true then y=y+W.message(flagsNext(host) and L.trackLightsRedNext or L.trackLightsRed,x,y,w,'wn')+6 end
 return y
end
-- « Active pour : » et une puce par profil (cyan : section cochée dans ce profil) ; un clic coche ou décoche la section
-- de ce profil, comme son interrupteur.
local function activeFor(v,e,x,y,w)
 if W.visible(y,20) then
  local lx=x
  W.label(L.lightsActiveFor,lx,y+3); lx=lx+W.labelWidth(L.lightsActiveFor)+8
  for _,profile in ipairs(C.profiles) do
   local cw=W.chipWidth(L.shortProfiles[profile])
   if lx+cw>x+w then break end
   local target=e.profiles[profile]
   local on=C.on(target,'lights')
   local id=idOf('lights_on_',profile)
   if W.hit(id,lx,y+1,cw,17) then target.section_lights=not on; on=not on; touch(v,target) end
   W.frame().active[id]=on
   -- Cochée : puce cyan pleine (maquette).
   W.chip(L.shortProfiles[profile],lx,y+1,on and 'C' or 'n'); W.help(v.tips.sections.lights,lx,y+1,cw,17,5)
   lx=lx+cw+4
  end
 end
 return y+26
end
-- Réinitialisation d'une section (Beta 1.24) : valeurs par défaut du profil affiché, comme le clic droit sur un réglage ;
-- préférences du pilote, motifs de classes et réglages fixés par le jeu de règles gardés. Options globales : seulement
-- celles de l'onglet, jamais le sens latéral mesuré, la graine, la langue ni la voiture de sécurité.
local globalResetKeys={'levelMode','useGripBoost','useBrakeAssist','overrideAwareness','debugLog','occLatMin','occLatMax','occMargin','occSpeedGain','gripPerLevelPct'}
local function resetSection(v,e,group,view,p)
 if group=='globals' then
  for _,key in ipairs(globalResetKeys) do e.g[key]=C.globalDefaults[key] end
  v.presetMessage=string.format(L.sectionResetDone,L.categories.globals); v.resetGroup=group; v.resetText=v.presetMessage; mark(v); return
 end
 if group=='overlay' then
  for _,key in ipairs(overlayResetKeys) do e.g[key]=C.globalDefaults[key] end
  v.presetMessage=L.overlayResetDone; v.resetGroup=group; v.resetText=v.presetMessage; mark(v); return
 end
 local defaults=C.defaults(view)
 for _,s in ipairs(C.schema) do if s.group==group and not C.kept(view,s.key) then p[s.key]=defaults[s.key] end end
 C.validate(view,p,p); v.presetMessage=string.format(L.sectionResetDone,L.categories[group]); v.resetGroup=group; v.resetText=v.presetMessage; touch(v,p)
end
-- Sections actives du profil et nombre de sections (l'overlay à part) : même compte pour l'accueil et la liste des
-- réglages (« / 14 » de la maquette).
local function sectionsOn(p) local on=0; for _,group in ipairs(C.sections) do if C.on(p,group) then on=on+1 end end; return on,#C.sections end
-- Nombre de réglages modifiés d'une section (différents du défaut du profil affiché). Beta 1.52 (relecture) : compte
-- mémorisé par section, refait seulement après une modification (édition de la fenêtre, révision du moteur) ou pour un
-- autre profil affiché, jamais à chaque image.
local function modifiedCount(v,group,view,p)
 local m=v.modifiedMemo[group]
 if not m then m={}; v.modifiedMemo[group]=m end
 if m.edits~=v.edits or m.revision~=v.e.revision or m.view~=view or m.p~=p then
  local n=0
  for _,control in ipairs(v.controls[group] or {}) do local s=control.schema; if not C.hidden(view,s.key) and modified(s,p[s.key],view) then n=n+1 end end
  m.edits=v.edits; m.revision=v.e.revision; m.view=view; m.p=p; m.count=n
 end
 return m.count
end
-- Contenu défilant de la section choisie : état, blocs propres (overlay, options globales, voiture de sécurité, motifs),
-- puis les sous-groupes de réglages.
local function sectionContent(v,e,group,view,p,x,top,w,listKey,controls)
 local y=top
 local status=statusLines(v,e,group,view,p,v.statusLines)
 for i=#status,1,-1 do y=y+W.message(status[i],x,y,w,'ok')+4; status[i]=nil end
 if #v.statusLines==0 and y>top then y=y+4 end
 if group=='overlay' then return overlayBlock(v,e,x,y,w)-top end
 -- Beta 1.38 (maquette) : section décochée pour ce profil : contenu montré grisé (voile du fond, 42 %), toujours
 -- réglable ; son message est en tête du volet.
 local from=y
 if group=='lights' then y=lightsStatus(v,p,x,y,w)+8 end
 local bottom,listBottom
 if group=='globals' then listBottom,bottom=globalBlock(v,e,x,y,w)
 else
  local list=Groups.build(listKey,controls)
  -- Jaune natif du HUD remplacé par les panneaux lumineux seulement sur un circuit équipé, section Panneaux lumineux
  -- cochée pour le profil affiché (ailleurs il sert encore) ; sa note est sous sa ligne.
  local locked=group=='accidents' and C.on(p,'lights') and v.host.trackLights==true and 'yellowHud' or nil
  y=groupColumns(v,idOf(listKey,view),list,view,p,x,y,w,locked,group=='lights')
  listBottom=y
  if group=='rules' and v.rulesView=='safety' then y=safetyBlock(v,e,x,y+12,w) end
  if group=='endurance' then y=patternBlock(v,p,x,y+12,w) end
  if group=='lights' then y=lightsLegend(v,p,x,y+12,w) end
  bottom=y+8
 end
 -- Voile (maquette, Beta 1.39) : seulement la liste des réglages et l'état du circuit ; ni la légende, ni les
 -- personnalités, motifs et base des voitures.
 if not C.on(p,group) then W.rect(x-2,from,w+4,listBottom-from,W.colors().veil) end
 return bottom-top
end
-- Langue de l'interface : textes de la fenêtre et du panneau de drapeaux refaits aussitôt ; choix enregistré.
local function language(v,code)
 local e=v.e
 e.g.language=code
 Locale.set(code); texts(v)
 local panel=e.panel; panel.key=''; panel.infractions=-1; panel.drsLaps=-1; panel.at=-math.huge
 v.dirty()
end
-- Mise à jour depuis GitHub (Beta 1.33) : actions des boutons (en-tête, accueil, diagnostic) et texte de l'état,
-- refait seulement quand l'état ou l'option change.
local function updateAct(v,action)
 local h=v.host; local u,port=h.updater,h.updatePort
 if not u or not port then return end
 local now=h.updateNow or v.e.time
 if action=='install' then Update.install(u,port,h.updateStopped)
 elseif action=='cancel' then Update.cancel(u)
 elseif action=='check' then Update.check(u,port,now)
 elseif action=='rollback' then Update.rollback(u,port,h.updateStopped)
 elseif action=='notes' then port.open(u.release and u.release.page or Update.page) end
end
local function megabytes(bytes) return (string.format('%.1f',bytes/1048576):gsub('%.',L.decimalMark)) end
local updateErrors={errNet=true,errHash=true,errWrite=true,errFormat=true,errRate=true}
local function updateText(v,u,view)
 if u.serial~=v.updateSerial then v.updateSerial=u.serial; v.updateClock=Adapter.clockText():sub(12,16); v.updateLine=nil end
 local flag=v.e.g.updateCheck==true
 if v.updateLine and v.updateView==view and v.updateFlag==flag then return v.updateLine end
 local s=L.updateStates; local r=u.release; local text
 if (view=='success' or view=='rolledback' or view=='interrupted') and u.updated and u.phase~='restarting' then
  text=string.format(L.updateDone[u.updated.kind],u.updated.from,u.updated.to)
 elseif view=='uptodate' then text=string.format(s.uptodate,v.updateClock or '')
 elseif view=='downloading' and r then text=string.format(s.downloading,r.version,megabytes(r.zip.size))
 elseif view=='installing' then text=string.format(s.installing,u.installed)
 elseif view=='ready' then text=string.format(s.ready,r and r.version or '')
 elseif view=='done' then text=string.format(s.done,r and r.version or '')..(u.restartLate and ' '..L.updateRestartLate or '')
 elseif view=='rolledback' then text=string.format(s.rolledback,u.previous or '')..(u.restartLate and ' '..L.updateRestartLate or '')
 elseif view=='broken' then text=string.format(s.broken,u.brokenFile or '')
 elseif view=='unchecked' then text=flag and s.soon or s.unchecked
 else text=s[view] or '' end
 if (view=='errNet' or view=='errRate') and u.status>0 then text=text..string.format(L.updateStatus,u.status) end
 if u.detail~='' and (view=='errWrite' or view=='errHash' or view=='errNet') then text=text..string.format(L.updateDetail,u.detail) end
 v.updateLine=text; v.updateView=view; v.updateFlag=flag
 return text
end
-- Puce du bloc « Mises à jour » selon l'état affiché (MajBloc).
local updateChips={uptodate={'chipUpToDate','g'},checking={'chipChecking','c'},available={'chipAvailable','C'},downloading={'chipDownloading','c'},
 verifying={'chipChecking','c'},installing={'chipInstalling','c'},ready={'chipReady','c'},done={'chipInstalled','g'},driving={'chipDriving','n'},
 errNet={'chipError','r'},errHash={'chipError','r'},errWrite={'chipError','r'},errFormat={'chipError','r'},errRate={'chipError','r'},broken={'chipError','r'},
 none={'chipNone','n'},interrupted={'chipRestored','o'},success={'chipUpToDate','g'},rolledback={'chipRolledBack','g'},unchecked={'chipUnchecked','n'}}
local updateKinds={uptodate='ok',success='ok',done='ok',rolledback='ok',checking='mut',downloading='mut',verifying='mut',installing='mut',ready='mut',
 none='mut',unchecked='mut',driving='mut',interrupted='wo',errNet='er',errHash='er',errWrite='er',errFormat='er',errRate='er',broken='er'}
-- États où les notes de version sont masquées (vérification, installation : maquette, Beta 1.38) ; montrées pendant
-- le téléchargement (Beta 1.39, maquette).
local updateBusyViews={checking=true,verifying=true,installing=true,ready=true,done=true}
-- Bloc « Mises à jour » du diagnostic (MajBloc) : versions, état, notes de la version publiée et lien, commande
-- principale (annuler, installer, réessayer), option du lancement, puis « Vérifier maintenant » et retour arrière.
local function updateBlock(v,e,host,x,y,w)
 local u,port=host.updater,host.updatePort
 if not u or not port then return y end
 local c=W.colors(); local tips=v.tips.ui
 local top=y
 local view=port.ready and Update.view(u,host.updateStopped) or 'unchecked'
 local r=u.release
 local newer=Update.fresh(u)
 local stopped=host.updateStopped
 -- Hauteur connue d'avance (fond du panneau) : notes et lien, message, boutons.
 local notes=r and (newer or view=='success') and not updateBusyViews[view] and math.min(K.updateNotes,#r.notes) or 0
 -- Version disponible (Beta 1.39, maquette) : aucun message, les versions et le bouton suffisent.
 local message=port.ready and (view~='available' and updateText(v,u,view) or '') or L.updateUnavailable
 local mh=message~='' and #W.lines(message,w-33,12)*W.lineHeight(12)+8 or 0
 local kh=#W.lines(L.updateKept,w-20,12)*W.lineHeight(12)
 local height=8+24+8+18+(newer and 16 or 0)+mh+(notes>0 and notes*18+30 or 0)+(r and 22 or 0)+(port.ready and (34+30+32) or 0)+kh+12
 W.panel(x,y,w,height)
 y=y+8
 local chip=updateChips[view] or updateChips.unchecked
 if W.visible(y,24) then W.heading(L.updateHeading,x+10,y,w-20); W.chipRight(L[chip[1]],x+w-10,y+3,chip[2]) end
 y=y+32
 if v.updateVersions~=u.serial then
  v.updateVersions=u.serial
  v.updateInstalledText=string.format(L.updateInstalled,u.installed)
  v.updateAvailableText=newer and string.format(L.updateAvailableFull,r.version,r.published) or nil
 end
 if W.visible(y,16) then W.cell(v.updateInstalledText,x+10,y,w-20,12,c.muted) end
 y=y+18
 if v.updateAvailableText then if W.visible(y,16) then W.cell(v.updateAvailableText,x+10,y,w-20,12,c.cyanText) end; y=y+16 end
 if message~='' then y=y+W.message(message,x+10,y,w-20,updateKinds[view] or 'mut')+8 end
 if notes>0 then
  if W.visible(y,16) then W.label(fmt(v,'notesOf',L.updateNotesOf,r.version),x+10,y) end
  y=y+16
  -- Lignes des notes préfixées une seule fois par version publiée.
  if not r.noteRows then r.noteRows={}; for i,n in ipairs(r.notes) do r.noteRows[i]=n~='' and '· '..n or '' end end
  if W.visible(y,notes*18+4) then
   W.rect(x+10,y,w-20,notes*18+4,c.bg)
   for i=1,notes do if r.noteRows[i]~='' then W.cell(r.noteRows[i],x+18,y+3+(i-1)*18,w-36,12,c.soft) end end
  end
  y=y+notes*18+10
 end
 -- Lien « Tout lire sur GitHub » (MajBloc), dès qu'une version publiée est connue, même à jour.
 if r then
  if W.visible(y,16) and W.link('update_notes',L.updateNotesLink,x+10,y,tips.updateNotes) then updateAct(v,'notes') end
  y=y+22
 end
 if port.ready then
  local checkShown=false
  -- Vérification au plus une par minute (limite de requêtes de GitHub) : bouton grisé entre deux.
  local cooling=Update.busy(u) or (host.updateNow or e.time)-u.askedAt<Update.checkGap
  if W.visible(y,28) then
   -- Phases annulables : celles du module de mise à jour (rien n'est encore copié dans le dossier de l'app).
   if Update.cancelable[u.phase] then
    if W.button('update_cancel',L.updateCancel,x+10,y,w-20,28,false,tips.updateCancel) then updateAct(v,'cancel') end
   elseif newer and Update.offered(u) then
    -- En conduite : bouton grisé et sans effet (copie seulement à l'arrêt).
    if W.button('update_install',L.updateButton,x+10,y,w-20,28,stopped,stopped and tips.updateInstall or tips.updateDriving,stopped and 'primary' or 'disabled') then updateAct(v,'install') end
   elseif view=='none' then
    -- Aucune version publiée (maquette, Beta 1.39) : « Vérifier maintenant » à la place de l'action, en contour.
    checkShown=true
    if W.button('update_check',L.updateCheckNow,x+10,y,w-20,28,false,tips.updateCheck,cooling and 'disabled' or 'outline') then updateAct(v,'check') end
   elseif updateErrors[view] then
    checkShown=true
    if W.button('update_check',L.updateRetry,x+10,y,w-20,28,false,tips.updateCheck,cooling and 'disabled' or 'outline') then updateAct(v,'check') end
   end
  end
  y=y+34
  if W.visible(y,28) and W.toggle('global_updateCheck',L.updateToggle,x+10,y,w-20,e.g.updateCheck,tips.updateToggle) then e.g.updateCheck=not e.g.updateCheck; v.dirty() end
  y=y+30
  if W.visible(y,24) then
   -- Retour arrière montré dès qu'une version précédente est gardée : grisé pendant une opération ou en conduite.
   local busy=Update.busy(u)
   local back=u.previous~=nil
   local half=(w-26)/2
   local bw=back and half or w-20
   if not checkShown and W.button('update_check',L.updateCheckNow,x+10,y,bw,24,false,tips.updateCheck,cooling and 'disabled' or nil) then updateAct(v,'check') end
   if back then
    if v.rollbackFor~=u.previous then v.rollbackFor=u.previous; v.rollbackText=string.format(L.updateRollback,u.previous) end
    local bx=checkShown and x+10 or x+16+half
    if W.button('update_rollback',v.rollbackText,bx,y,checkShown and w-20 or half,24,false,stopped and tips.updateRollback or tips.updateDriving,(busy or not stopped) and 'disabled' or nil) then updateAct(v,'rollback') end
   end
  end
  y=y+32
 end
 y=y+W.paragraph(L.updateKept,x+10,y,w-20,12,c.label)+12
 return top+math.max(height,y-top)+8
end
-- Puce d'état de l'en-tête (ACTIF · COURSE, APP COUPÉE, PANIQUE, EN LIGNE, EN ATTENTE, IA NATIVES).
-- Pause : commandes figées, état du moteur toujours valable (chiffres de l'accueil affichés) ; rediffusion, session
-- finie, circuit sans spline, image anormale, accès refusé : commandes suspendues (ambre), jamais « actif ».
local suspendedGuards={replay=true,finished=true,spline=true,dt=true,access=true}
-- Voitures IA de la session (pilotables), comptées une fois par image du moteur.
local aiEngine,aiFrame,aiValue=nil,-1,0
local function aiCars(e)
 if aiEngine~=e or aiFrame~=e.frames then
  aiEngine=e; aiFrame=e.frames; aiValue=0
  local frame=e.frame
  if frame then for i=1,frame.count do local a=frame.cars[i]; if a.valid and a.control and not a.player then aiValue=aiValue+1 end end end
 end
 return aiValue
end
-- Beta 1.57 : garde affichée : une garde « online » prend le genre de sa suspension (mode alt-online de CSP, lecture
-- impossible) pour ses textes ; la puce, le bandeau et leur style restent ceux d'« online ».
local function guardId(e)
 local kind=e.guard=='online' and e.guardKind
 return kind=='alt' and 'altonline' or kind=='read' and 'readerror' or e.guard
end
local function stateKey(e)
 if not e.g.enabled then return 'disabled' end
 if e.panic then return 'panic' end
 if e.guard=='online' then return 'online' end
 if e.guard=='init' or not e.frame then return 'init' end
 if e.guard=='nosections' then return 'native' end
 if e.guard=='paused' then return 'paused' end
 if suspendedGuards[e.guard] then return 'suspended' end
 -- Beta 1.36 : moteur prêt mais aucune IA dans la session (seul en piste) : jamais « actif ».
 return aiCars(e)>0 and 'ready' or 'noai'
end
-- Chiffres en direct : moteur prêt ou en pause.
local function live(e) return e.guard=='ready' or e.guard=='paused' end
local pillKinds={ready='g',noai='n',paused='n',suspended='a',disabled='n',panic='r',online='a',init='n',native='n'}
-- Session détectée (accueil, en-tête) : genre (déclaré par race.ini, sinon lu par CSP) et source ; textes de la langue.
local function sessionKind(frame)
 if not frame then return nil,nil end
 local declared=frame.configType>=1
 local kind=declared and frame.configType or frame.type
 return declared and frame.configTrackDay and L.trackDaySession or L.sessionTypes[kind] or L.sessionTypes[0],declared and L.sourceRace or L.sourceCSP
end
-- En-tête (84 px) : marque, version et mise à jour ; session et garde ; état, langue, activation, panique ; onglets et
-- profil affiché ; filet cyan.
local function headerBar(v,e)
 local c=W.colors(); local fw=W.frame().w; local host=v.host
 -- Bandeau « en ligne » masqué par « Compris » : de nouveau montré dès que la garde change (tous les onglets).
 if v.bannerHide and v.bannerHide~=guardId(e) then v.bannerHide=nil end
 local x=14
 if v.logo and callable(ui.drawImage) then pcall(ui.drawImage,v.logo,W.point(10,2),W.point(54,46)); x=58 end
 W.text('ADVANCED',x,10,23,c.text,'display')
 local bw=W.width('ADVANCED',23,'display')
 W.text('IA',x+bw,10,23,c.cyan,'display')
 x=x+bw+W.width('IA',23,'display')+9
 if not v.versionChip then v.versionChip='β'..(C.release:gsub('^Beta ','')) end
 local vw=W.width(v.versionChip,11,'mono')+10
 W.frameRect(x,15,vw,18,c.rule); W.text(v.versionChip,x+5,17,11,c.label,'mono')
 W.help(v.tips.ui.version,x,15,vw,18,3)
 x=x+vw+8
 -- Mise à jour : bouton d'un clic quand une version plus récente est connue ; état pendant l'installation.
 local u,port=host.updater,host.updatePort
 if u and port and port.ready then
  local view=Update.view(u,host.updateStopped)
  if Update.offered(u) and (view=='available' or view=='driving') then
   if v.updateHeaderFor~=u.release.version then v.updateHeaderFor=u.release.version; v.updateHeaderText=string.format(L.updateHeader,(u.release.version:gsub('^Beta ',''))) end
   local w=math.min(190,W.width(W.upper(v.updateHeaderText),12,'display')+30)
   if W.button('update_header',v.updateHeaderText,x,12,w,24,view=='available',view=='available' and v.tips.ui.updateInstall or v.tips.ui.updateDriving,view=='available' and 'primary' or 'disabled') then updateAct(v,'install') end
   x=x+w+8
  elseif L.updateBusy[view] and not Update.reported(u) then
   x=x+W.chip(L.updateBusy[view],x,15,'c')+8
  end
 end
 -- Partie droite, de droite à gauche : panique, activation, langue, état.
 local right=fw-12
 local panic=e.panic
 local pw=math.max(98,W.width(W.upper(panic and L.resumeShort or L.panicShort),13,'display')+56)
 local px=right-pw
 if W.button('panic',panic and L.resumeShort or L.panicShort,px,12,pw,24,panic,panic and v.tips.ui.resume or v.tips.ui.panic,panic and 'resume' or 'danger','warn') then
  e.panic=not e.panic; if not e.panic then Engine.reset(e,e.time,true) end
 end
 local ax=px-8-62
 local clicked=W.hit('enabled',ax,12,62,24)
 W.frame().active.enabled=e.g.enabled==true
 W.switchShape(ax+4,16,e.g.enabled==true,false,false)
 W.text(L.appLabel,ax+40,17,12,e.g.enabled and c.text or c.label,'cond')
 W.help(v.tips.ui.enabled,ax,12,62,24,5)
 if clicked then e.g.enabled=not e.g.enabled; v.dirty() end
 local codes=v.languageCodes
 local lx=ax-8-28*#codes
 local at=1; for i,code in ipairs(codes) do if Locale.current==code then at=i end end
 local picked=W.segment('lang',v.languageLabels,lx,12,28*#codes,24,at,v.tips.ui.language,v.languageIds)
 if picked and codes[picked]~=Locale.current then language(v,codes[picked]) end
 local key=stateKey(e)
 local pill=key=='online' and guardId(e) or key
 if v.pillFor~=pill or v.pillProfile~=e.profile then
  v.pillFor=pill; v.pillProfile=e.profile
  v.pillText=(key=='ready' or key=='paused' or key=='noai') and L.pillStates[key]..L.shortProfiles[e.profile] or L.pillStates[pill] or L.pillStates[key]
 end
 -- Puce d'état à point de couleur (Beta 1.38, maquette).
 local cw=W.dotChipWidth(v.pillText)
 local sx=lx-10-cw
 local s=pillKinds[key]
 W.dotChip(v.pillText,sx,15,s)
 W.help(v.tips.ui.status,sx,15,cw,18,3)
 -- Milieu : session (circuit / profil) et garde (IA pilotées · état).
 local mx=x+6
 local mw=sx-12-mx
 if mw>60 then
  W.rect(mx,10,1,28,c.ruleHead)
  local frame=e.frame
  local track=frame and frame.track or false
  if v.sessionFor~=track or v.sessionProfile~=e.profile then v.sessionFor=track; v.sessionProfile=e.profile; v.sessionLine=frame and (frame.trackName~='' and frame.trackName or frame.track~='' and frame.track or L.noSession)..' / '..L.profiles[e.profile] or L.noSession end
  W.cell(W.upper(v.sessionLine),mx+12,9,mw-12,14,c.text,'cond')
  local ready=live(e)
  -- Garde (Beta 1.38, maquette) : prête, la session détectée, sa source et le profil en cours (« Prêt · course
  -- (race.ini) → profil Course (auto) ») ; sinon le texte de la garde. Refait seulement quand l'un d'eux change.
  local kind,source=sessionKind(frame)
  local gid=guardId(e)
  if v.guardFor~=gid or v.guardCount~=e.activeCount or v.guardKind~=kind or v.guardProfile~=e.profile or v.guardAuto~=e.g.autoProfile then
   v.guardFor=gid; v.guardCount=e.activeCount; v.guardKind=kind; v.guardProfile=e.profile; v.guardAuto=e.g.autoProfile
   v.carsLine=ready and string.format(L.headerCars,e.activeCount) or L.headerNoCars
   v.guardLine=' · '..(e.guard=='ready' and kind and string.format(L.guardReady,kind,source,L.profiles[e.profile],e.g.autoProfile and L.guardAuto or L.guardManual) or L.guards[gid] or L.guards[e.guard] or e.guard)
  end
  local cwid=math.min(W.width(v.carsLine,12,'sb'),mw-12)
  W.cell(v.carsLine,mx+12,27,mw-12,12,ready and c.cyanText or c.muted,'sb')
  W.cell(v.guardLine,mx+12+cwid,27,math.max(0,mw-12-cwid),12,c.label)
  W.help(v.tips.ui.status,mx,8,mw,32,3)
 end
 -- Onglets inclinés (-14°), sigle du jeu de règles sur « Règles de course ».
 local tx=12
 local category=ruleCategoryOf(v,e)
 for _,tab in ipairs(tabs) do
  local label=L.tabs[tab]
  local tw=W.width(label,14,'display')+24
  local sup=tab=='rules' and category and L.ruleShort[category] or nil
  local sw=sup and W.width(sup,11,'mono')+10 or 0
  local w=tw+sw
  local clicked,hover,pressed=W.hit(idOf('tab_',tab),tx,48,w,34)
  local current=v.tab==tab
  W.frame().active[idOf('tab_',tab)]=current
  local fill=current and c.cyan or pressed and c.control or hover and c.block or nil
  if fill then W.quad(tx+8,48,tx+w+8,48,tx+w,82,tx,82,fill) end
  W.text(label,tx+12,56,14,current and c.ink or hover and c.text or c.muted,'display')
  if sup then
   local sx2=tx+tw-4
   W.rect(sx2,54,sw-4,15,current and c.ink or c.select)
   W.text(sup,sx2+3,55,11,current and c.cyan or c.cyanText,'mono')
  end
  W.help(v.tips.ui[idOf('tab_',tab)],tx,48,w,34,3)
  if clicked then if v.tab~=tab then v.presetMessage='' end; v.tab=tab end
  tx=tx+w+4
 end
 -- Profil affiché : avec le profil automatique, le clic affiche sans figer la détection ; sans lui, il choisit le
 -- profil utilisé. Point vert : profil en cours.
 local labels,widths=v.profileLabels,v.profileWidths
 local pw2=v.profileTotal
 if fw-12-pw2<=tx+8 then labels,widths,pw2=v.profileCodes,v.profileCodeWidths,v.profileCodeTotal end
 local psx=fw-12-pw2
 do
  local lw=W.labelWidth(L.profileLabel)
  if psx-8-lw>tx+8 then W.label(L.profileLabel,psx-8-lw,58) end
  local at=1; for i,profile in ipairs(C.profiles) do if profile==v.view then at=i end end
  local cxp=psx
  W.rect(psx,53,pw2,24,c.bg)
  for i,profile in ipairs(C.profiles) do
   local w=widths[profile]
   local id=idOf('profile_',profile)
   local clicked2,hover2,pressed2=W.hit(id,cxp,53,w,24)
   W.frame().active[id]=i==at
   if i==at then W.rect(cxp,53,w,24,c.cyan) elseif pressed2 then W.rect(cxp,53,w,24,c.controlHover) elseif hover2 then W.rect(cxp,53,w,24,c.control) end
   W.text(labels[profile],cxp+8,58,12,i==at and c.ink or hover2 and c.text or c.muted,'cond')
   if profile==e.profile and key~='init' then W.circle(cxp+w-9,65,3,i==at and c.ink or c.ok) end
   W.help(v.tips.profiles[profile],cxp,53,w,24,5)
   if clicked2 then
    if e.g.autoProfile then v.view=profile; v.viewFor=e.profile else Engine.select(e,profile); v.view=profile; v.viewFor=profile; v.dirty() end
   end
   cxp=cxp+w
  end
  W.frameRect(psx,53,pw2,24,c.ruleHead)
 end
 W.rect(0,82,fw,2,c.cyan)
end
-- Bandeau d'état global (app coupée, panique, en ligne, initialisation) en tête de l'accueil ; renvoie sa hauteur.
local bannerStyles={disabled={'neutralBack','muted','ruleHover'},panic={'dangerBack','dangerText','dangerLine'},online={'warnBack','warn','warnLine'},init={'panel','muted','rule'}}
local function banner(v,e,x,y,w)
 local key=stateKey(e)
 local style=bannerStyles[key]
 -- « Compris » (en ligne, Beta 1.38) : bandeau masqué jusqu'au prochain changement de garde (vu par l'en-tête).
 local gid=guardId(e)
 if not style or key=='online' and v.bannerHide==gid then return 0 end
 local c=W.colors(); local texts=key=='online' and L.banners[gid] or L.banners[key]
 local tw=W.width(W.upper(texts[1]),13,'cond')
 local bw=texts[3] and math.max(110,W.width(W.upper(texts[3]),12,'display')+34) or 0
 local h=math.max(40,#W.lines(texts[2],w-tw-bw-44,12)*W.lineHeight(12)+14)
 W.rect(x,y,w,h,c[style[1]]); W.frameRect(x,y,w,h,c[style[3]])
 W.text(W.upper(texts[1]),x+10,y+(h-15)/2,13,c[style[2]],'cond')
 W.paragraph(texts[2],x+tw+24,y+7,w-tw-bw-44,12,c.body)
 if texts[3] and W.button('banner_action',texts[3],x+w-bw-10,y+(h-26)/2,bw,26,false,v.tips.ui.bannerAction,key=='disabled' and 'primary' or key=='panic' and 'resume' or key=='online' and 'default' or 'outline') then
  if key=='disabled' then e.g.enabled=true; v.dirty()
  elseif key=='panic' then e.panic=false; Engine.reset(e,e.time,true)
  elseif key=='init' then v.tab='diagnostic'
  elseif key=='online' then v.bannerHide=gid end
 end
 return h+8
end
-- Point à vérifier : texte et genre (lien), dans les listes réutilisées de la fenêtre.
local function addWarning(v,text,kind) local list=v.warnings; list[#list+1]=text; v.warningKinds[#list]=kind or '' end
-- Signature du profil affiché : refaite seulement après un changement (révision du moteur, édition de la fenêtre,
-- profil affiché) ; celle d'un préréglage personnel, une fois par préréglage chargé.
local function currentSignature(v,e,view,p)
 if v.sigRev~=e.revision or v.sigEdits~=v.edits or v.sigView~=view or v.sigP~=p then
  v.sigRev=e.revision; v.sigEdits=v.edits; v.sigView=view; v.sigP=p; v.sigNow=Presets.signature(view,p,e.g,v.signatureValues)
 end
 return v.sigNow
end
local function entrySignature(v,entry)
 local s=v.entrySigs[entry]
 if not s then s=Presets.signature(entry.profile,entry.p,entry.g,v.signatureValues); v.entrySigs[entry]=s end
 return s
end
-- Points à vérifier (Beta 1.10) : texte, lien vers la section concernée.
-- spotter : fenêtre de SpotterEnginer (Beta 1.52), ouverte par l'hôte.
local warnTargets={spotter={},signs={'diagnostic'},endurance={'settings','endurance'},weather={'settings','weather'},tabs={'settings','accidents'},lights={'settings','lights'},acpenalties={'settings','sanctions'}}
local function openTarget(v,kind)
 local t=warnTargets[kind]
 if not t then return end
 if kind=='spotter' then if v.host and v.host.openCompanion then v.host.openCompanion() end return end
 v.tab=t[1]; if t[2] then v.category=t[2] end
end
-- Tuile de chiffre (État en direct) : libellé, valeur (mono, ou texte avec pastille de couleur).
local function kpi(x,y,w,label,value,warn,dot,mono,live)
 local c=W.colors()
 W.rect(x,y,w,54,warn and c.warnBack or c.block)
 if warn then W.rect(x,y,w,2,c.warn) end
 W.label(label,x+9,y+8,warn and c.warnSoft or nil)
 local col=warn and c.warn or live and c.text or c.disabledText
 local vx=x+9
 if dot then W.circle(vx+6,y+36,6,dot); vx=vx+19 end
 W.cell(value,vx,y+25,w-(vx-x)-8,mono and 20 or 18,col,mono and 'mono' or 'cond')
end
-- Accueil (refonte Racing 26) : à gauche la session et les préréglages intégrés ; à droite l'état en direct, les points
-- à vérifier et les préréglages personnels. Deux colonnes qui défilent chacune à la molette.
local function homeTab(v,e,host)
 local c=W.colors(); local view=v.view; local p=e.profiles[view]
 local fw,fh=W.frame().w,W.frame().h
 local top=HEADER+10
 top=top+banner(v,e,PAD,top,fw-2*PAD)
 local height=fh-top-12
 local cw=(fw-2*PAD-GAP)/2
 local lx,rx=PAD,PAD+cw+GAP
 -- Préréglage actif (intégré ou personnel), connu avant le dessin : une seule ligne d'état, sous les intégrés.
 v.activePreset=nil
 for _,item in ipairs(v.builtinList) do builtinActive(v,item[2],item[4](view),item[1]) end
 local custom=v.customActive
 local now=currentSignature(v,e,view,p)
 for i=1,K.maxPresets do
  local entry=host.presets[i]
  custom[i]=entry~=nil and view==entry.profile and now==entrySignature(v,entry)
  if custom[i] and not v.activePreset then v.activePreset=entry.name end
 end
 -- Colonne de gauche : session, puis préréglages intégrés.
 local offset=W.scroll(v.scrolls,'home_left',lx,top,cw,height,v.contentHeights.homeLeft or 0)
 W.clip(lx,top,cw,height)
 local y=top-offset; local x=lx; local w=cw-6
 local frame=e.frame
 local detected
 if frame then
  local label,source=sessionKind(frame)
  detected=fmt(v,'detected',L.sessionDetected,label,source)
  if not e.g.autoProfile then detected=fmt(v,'detectedManual','%s%s',detected,L.manualOverride) end
 else detected=L.noSessionYet end
 local hint=e.g.autoProfile and L.autoHintOn or L.autoHintOff
 local dh=#W.lines(detected,w-210,12)*W.lineHeight(12)
 local hh=#W.lines(hint,w-24,12)*W.lineHeight(12)
 local viewNote=view~=e.profile and fmt(v,'viewing',L.viewing,L.profiles[view],L.profiles[e.profile]) or nil
 local vh=viewNote and #W.lines(viewNote,w-24,12)*W.lineHeight(12)+6 or 0
 local sh=8+24+10+16+34+math.max(0,dh-14)+8+hh+vh+12
 W.panel(x,y,w,sh)
 if W.visible(y+8,24) then W.heading(L.sessionHeading,x+12,y+8,w-24); W.chipRight(e.g.autoProfile and L.chipAuto or L.chipManual,x+w-12,y+11,e.g.autoProfile and 'g' or 'a') end
 local yy=y+42
 if W.visible(yy,60) then
  W.label(L.currentProfile,x+12,yy)
  -- Nom du profil réduit (30 à 18) pour ne jamais passer sous le bloc du profil automatique.
  W.titleFit(L.profiles[e.profile],x+12,yy+16,w-24-198,30,18)
  W.paragraph(detected,x+12,yy+50,w-210,12,c.muted)
  -- Profil automatique : interrupteur dans son bloc.
  local bx=x+w-12-190
  local clicked,hover=W.hit('auto',bx,yy+12,190,34)
  W.frame().active.auto=e.g.autoProfile==true
  W.rect(bx,yy+12,190,34,hover and c.blockHover or c.block)
  W.text(L.auto,bx+10,yy+21,12,c.body)
  W.switchShape(bx+150,yy+21,e.g.autoProfile,hover,false)
  W.help(v.tips.ui.auto,bx,yy+12,190,34,5)
  if clicked then
   e.g.autoProfile=not e.g.autoProfile
   if e.g.autoProfile and e.frame then e.profile=C.autoProfile(e.frame); e.p=e.profiles[e.profile] end
   if not e.g.autoProfile then e.g.manualProfile=e.profile end
   v.viewFor=nil; mark(v)
  end
 end
 yy=yy+50+math.max(14,dh)+8
 if W.visible(yy,hh) then W.paragraph(hint,x+12,yy,w-24,12,c.label) end
 yy=yy+hh+6
 if viewNote then W.paragraph(viewNote,x+12,yy,w-24,12,c.cyanText); yy=yy+vh end
 y=y+math.max(sh,yy-y+6)+GAP
 -- Préréglages intégrés : tuiles (Endurance sur toute la largeur), ligne d'état et restauration.
 local tileW=(w-24-6)/2
 local rows=math.ceil((#v.builtinList-1)/2)+1
 local line
 local lineKind
 if v.activePreset then line=fmt(v,'presetLine','%s%s',L.activePreset,v.activePreset); lineKind='ok'
 elseif e.g.loadedPreset~='' and loadedHere(v,e,view) then line=fmt(v,'presetLine','%s%s%s',L.loadedPreset,v.loadedName,L.presetModified); lineKind='mut'
 else line=L.noActivePreset; lineKind='mut' end
 local restore=fmt(v,'restore','%s%s',L.restoreShort,L.profiles[view])
 local rw=math.max(130,W.width(W.upper(restore),12,'display')+34)
 local lh=math.max(28,#W.lines(line,w-24-rw-33,12)*W.lineHeight(12)+12)
 local ph=8+24+8+rows*(70+6)+4+lh+12+34
 W.panel(x,y,w,ph)
 if W.visible(y+8,24) then W.heading(L.builtinHeading,x+12,y+8,w-24,L.builtinTarget) end
 local ty=y+40
 for k,item in ipairs(v.builtinList) do
  local label,name,target=item[1],item[2],item[4](view)
  local wide=k==#v.builtinList and #v.builtinList%2==1
  local bx=x+12+(wide and 0 or ((k-1)%2)*(tileW+6)); local by=ty+math.floor((k-1)/2)*76
  if W.visible(by,70) then
   local active=builtinActive(v,name,target,label)
   if W.tile(idOf('builtin_',name),label,active and L.chipActive or L.shortProfiles[target] or '',active and 'C' or 'n',v.presetDescs[name],bx,by,wide and w-24 or tileW,70,active,v.tips.presets[item[3]]) then loadBuiltin(v,name,target) end
  end
 end
 local sy=ty+rows*76+4
 -- Beta 1.51 : préréglage de la session, appliqué à chaque nouvelle session détectée (profil automatique).
 if W.visible(sy,28) and W.toggle('global_presetBySession',L.presetBySession,x+12,sy,w-24,e.g.presetBySession,v.tips.ui.presetBySession) then e.g.presetBySession=not e.g.presetBySession; v.dirty() end
 sy=sy+34
 if W.visible(sy,lh) then
  W.rect(x+12,sy,w-24,lh,c.block)
  W.message(line,x+22,sy+(lh-W.lineHeight(12)*#W.lines(line,w-24-rw-33,12))/2,w-24-rw-22,lineKind)
  if W.button('restore',restore,x+w-12-rw-8,sy+(lh-26)/2,rw,26,false,v.tips.ui.restore,'outline') then
   -- Beta 1.52 (relecture) : préréglage chargé dans ce profil oublié aussi (marque et dernier préréglage chargé).
   local here=e.g.loadedPreset~='' and loadedHere(v,e,view)
   C.restore(view,p); C.setMark(e.g,view,''); if here then e.g.loadedPreset='' end; touch(v,p)
  end
 end
 y=y+ph+GAP
 W.clip(); v.contentHeights.homeLeft=y+offset-top
 -- Colonne de droite : état en direct, points à vérifier, préréglages personnels.
 offset=W.scroll(v.scrolls,'home',rx,top,cw,height,v.contentHeights.home or 0)
 W.clip(rx,top,cw,height)
 x=rx; y=top-offset
 local t=e.incidents; local liveNow=live(e)
 local on,total=sectionsOn(p)
 if v.sectionsFor~=on then v.sectionsFor=on; v.sectionsText=string.format(L.sectionsActive,on,total) end
 W.panel(x,y,w,8+24+8+2*(54+5)+8)
 if W.visible(y+8,24) then W.heading(L.stateHeading,x+12,y+8,w-24,v.sectionsText,'mono') end
 local ky=y+40; local unit=(w-24-5*5)/6
 if W.visible(ky,54) then
  local dash='—'
  kpi(x+12,ky,unit*2+5,L.kpiCars,liveNow and intText(e.activeCount) or dash,false,nil,true,liveNow)
  kpi(x+12+2*(unit+5)+0,ky,unit*2+5,L.kpiIncidents,liveNow and intText(t.activeCount) or dash,false,nil,true,liveNow)
  kpi(x+12+4*(unit+5),ky,unit*2+5,L.kpiZones,liveNow and intText(t.zoneCount) or dash,false,nil,true,liveNow)
 end
 ky=ky+59
 if W.visible(ky,54) then
  local neutral=t.neutral and t.neutralMode or nil
  kpi(x+12,ky,unit*3+10,L.kpiNeutral,neutral and W.upper(L.neutralNames[neutral]) or (liveNow and L.neutralNames.none or '—'),neutral~=nil,nil,false,liveNow)
  local value=host.flagOverride and host.flagValue or 0
  local lightText=host.trackLights==false and L.kpiLightsNone or not C.on(e.p,'lights') and L.kpiLightsOff or host.trackLights==nil and (e.frame and e.guard~='init' and L.kpiLightsUnknown or L.kpiLightsNone) or value~=0 and fmt(v,'kpiLights','%s%s',L.lightShort[value] or '',lightsPhase(e,value)) or L.kpiLightsIdle
  kpi(x+12+3*(unit+5)+5,ky,unit*3+5,L.kpiLights,lightText,false,value~=0 and v.lightColors[value] or c.rule,false,liveNow)
 end
 y=y+8+24+8+2*59+8+GAP
 -- Points à vérifier : barre ambre, texte, lien vers la section concernée.
 local warnings=v.warnings; for i=#warnings,1,-1 do warnings[i]=nil end
 local kinds=v.warningKinds
 if e.frame and e.frame.conflict~='' then addWarning(v,fmt(v,'conflict','%s%s',L.conflict,e.frame.conflict)) end
 if e.g.offsetSign==0 and C.needsOffset(C.effective(view,p,v.derived)) then addWarning(v,L.unavailableSigns,'signs') end
 if e.frame and e.frame.left>K.enduranceSuggestionSeconds and not p.enduranceOverlay and view~='Q' and view~='P' and view~='H' then addWarning(v,L.enduranceSuggestion,'endurance') end
 if C.any(p) and not C.on(p,'weather') then addWarning(v,L.weatherOff,'weather') end
 if host.raceFlagsHidden==false then addWarning(v,flagsNext(host) and L.nativeFlagsNext or L.nativeFlagsShown) end
 if p.configured and not C.on(p,'accidents') and not C.on(p,'rules') then addWarning(v,L.newTabsOff,'tabs') end
 if host.oldSettings then addWarning(v,L.oldSettings) end
 -- Beta 1.56 : vos limites de piste gérées par l'app, pénalités d'AC encore actives (double sanction possible).
 if e.acPenaltyWarned then addWarning(v,L.acPenaltiesOn,'acpenalties') end
 if host.upgraded and #host.upgraded>0 then
  if v.upgradedFor~=host.upgraded or v.upgradedCount~=#host.upgraded then v.upgradedFor=host.upgraded; v.upgradedCount=#host.upgraded; v.upgradedList=table.concat(host.upgraded,', ') end
  addWarning(v,fmt(v,'upgraded','%s%s',L.upgraded,v.upgradedList))
 end
 if host.trackLights==true and C.on(e.p,'lights') and e.p.lightsRed~=false and host.raceFlagsHidden==false then addWarning(v,flagsNext(host) and L.lightsRedNext or L.lightsRedWarning,'lights') end
 -- Beta 1.52 : SpotterEnginer signale sa propre mise à jour (jamais installée d'ici) : lien vers sa fenêtre. Texte refait
 -- seulement quand l'état relu change (une table neuve toutes les K.companionUpdatePeriod s au plus).
 local cu=host.companionUpdate
 if cu and (cu.state=='available' and cu.latest or cu.state=='incompatible') then
  if v.companionFor~=cu then
   v.companionFor=cu
   v.companionText=cu.state=='available' and string.format(L.companionAvailable,cu.latest,cu.installed) or cu.needs and cu.needs~='?' and string.format(L.companionNeeds,cu.needs) or L.companionNeedsUnknown
  end
  addWarning(v,v.companionText,'spotter')
 end
 -- Mise à jour (Beta 1.33) : nouvelle version (bouton d'un clic) ou compte rendu de la dernière opération.
 local u=host.updater; local offered=u~=nil and host.updatePort~=nil and host.updatePort.ready and Update.offered(u)
 local report=u~=nil and u.updated~=nil and not offered
 if report and v.updateReportFor~=u.serial then v.updateReportFor=u.serial; v.updateReportText=string.format(L.updateDone[u.updated.kind],u.updated.from,u.updated.to) end
 local count=#warnings+(offered and 1 or 0)+(report and 1 or 0)
 if v.warnCountFor~=count then v.warnCountFor=count; v.warnCountText=string.format(L.warningsCount,count) end
 -- Hauteur du panneau : lignes coupées à la largeur du texte (lien à droite).
 local textW=w-24-18-90
 local wh=0
 for _,text in ipairs(warnings) do wh=wh+#W.lines(text,textW,12)*W.lineHeight(12)+14 end
 if offered then wh=wh+W.lineHeight(12)+14+4 end
 if report then wh=wh+#W.lines(v.updateReportText or '',textW,12)*W.lineHeight(12)+14 end
 if count==0 then wh=W.lineHeight(12)+14 end
 local warnH=8+24+4+wh+6
 W.panel(x,y,w,warnH)
 if W.visible(y+8,24) then
  W.heading(L.warningsHeading,x+12,y+8,w-24)
  W.chipRight(v.warnCountText,x+w-12,y+11,count>0 and 'a' or 'n')
 end
 local wy=y+36
 if count==0 then W.message(L.noWarnings,x+12,wy+7,w-24,'mut') end
 for i,text in ipairs(warnings) do
  local hgt=#W.lines(text,textW,12)*W.lineHeight(12)+14
  if W.visible(wy,hgt) then
   W.quad(x+15.6,wy+8,x+19.6,wy+8,x+16,wy+21,x+12,wy+21,c.warn)
   W.paragraph(text,x+30,wy+7,textW,12,c.body)
   local kind=kinds[i]
   if warnTargets[kind] then
    local label=L.warnLinks[kind]
    local lw=W.linkWidth(label)
    if W.link(idOf('warn_',kind),label,x+w-12-lw,wy+8,v.tips.ui.warnLink) then openTarget(v,kind) end
   end
  end
  wy=wy+hgt; if i<#warnings or offered or report then W.rect(x+12,wy-1,w-24,1,c.ruleSoft) end
 end
 if offered then
  if v.updateAlertFor~=u.release.version then v.updateAlertFor=u.release.version; v.updateAlertText=string.format(L.updateAlert,u.release.version) end
  if W.visible(wy,W.lineHeight(12)+18) then
   W.quad(x+15.6,wy+8,x+19.6,wy+8,x+16,wy+21,x+12,wy+21,c.cyan)
   -- Une ligne (maquette) : texte, lien des notes, puis le bouton à droite.
   local stopped=host.updateStopped
   local bw=math.max(110,W.width(W.upper(L.updateButton),12,'display')+26)
   local lw=W.linkWidth(L.notesLink)
   W.cell(v.updateAlertText,x+30,wy+7,w-24-18-bw-lw-24,12,c.body)
   if W.link('update_home_notes',L.notesLink,x+w-12-bw-10-lw,wy+8,v.tips.ui.updateNotes) then updateAct(v,'notes') end
   if W.button('update_home',L.updateButton,x+w-12-bw,wy+3,bw,24,stopped,stopped and v.tips.ui.updateInstall or v.tips.ui.updateDriving,stopped and 'primary' or 'disabled') then updateAct(v,'install') end
  end
  wy=wy+W.lineHeight(12)+14+4
 elseif report then
  local hgt=#W.lines(v.updateReportText,textW,12)*W.lineHeight(12)+14
  if W.visible(wy,hgt) then
   W.quad(x+15.6,wy+8,x+19.6,wy+8,x+16,wy+21,x+12,wy+21,c.ok)
   local rh=W.paragraph(v.updateReportText,x+30,wy+7,textW,12,c.body)
   -- « Affichée une seule fois » (maquette) : à la suite, en gris, si elle tient sur la dernière ligne.
   local lines=W.lines(v.updateReportText,textW,12); local lw2=W.width(lines[#lines] or '',12)
   if lw2+W.width(L.updateOnce,12)<=textW then W.text(L.updateOnce,x+30+lw2,wy+7+rh-W.lineHeight(12),12,c.label) end
   local lw=W.linkWidth(L.notesLink)
   if W.link('update_home_notes',L.notesLink,x+w-12-lw,wy+8,v.tips.ui.updateNotes) then updateAct(v,'notes') end
  end
  wy=wy+hgt
 end
 y=y+math.max(warnH,wy-y+6)+GAP
 -- Préréglages personnels : nom et enregistrement en tête, puis la bibliothèque.
 local saved=0; for i=1,K.maxPresets do if host.presets[i] then saved=saved+1 end end
 if v.customCountFor~=saved then v.customCountFor=saved; v.customCountText=string.format(L.customCount,saved,K.maxPresets) end
 local py=y
 W.panel(x,py,w,v.customPanelH or 120)
 if W.visible(py+8,24) then W.heading(L.customPresets,x+12,py+8,w-24,v.customCountText,'mono') end
 y=py+40
 local sw=110
 -- Nom refusé : cadre rouge (Beta 1.38, maquette).
 v.presetName=input('preset_name',x+12,y,w-24-sw-6,v.presetName,v.tips.ui.presetName,v.presetMessage==v.invalidNameText) or v.presetName
 if W.visible(y,28) and W.button('save_preset',L.savePresetShort,x+w-12-sw,y,sw,28,false,v.tips.ui.savePreset,'primary') then
  local entry=Presets.capture(v.presetName,view,p,e.g)
  if not entry then v.presetMessage=v.invalidNameText
  elseif Adapter.savePreset(host,entry) then
   -- Beta 1.52 (relecture) : préréglage personnel enregistré depuis ce profil : marque « Perso », comme à son chargement.
   e.g.loadedPreset='custom:'..entry.name; e.g.presetsUsed=true; C.setMark(e.g,view,C.personalMark); v.presetMessage=L.presetSaved; v.dirty()
  else v.presetMessage=v.saveFailedText end
 end
 y=y+34
 local bytes=#(v.presetName or '')
 if v.bytesFor~=bytes then v.bytesFor=bytes; v.bytesText=string.format(L.presetBytes,bytes,K.presetNameBytes) end
 if v.noteFor~=view then v.noteFor=view; v.noteText=string.format(L.presetTargetNote,L.profiles[view]) end
 local bw2=W.width(v.bytesText,11,'mono')
 if W.visible(y,16) then W.right(v.bytesText,x+w-12,y+1,11,bytes>K.presetNameBytes and c.danger or c.label,'mono') end
 y=y+W.paragraph(v.noteText,x+12,y,w-24-bw2-10,12,c.label)+6
 if v.presetMessage~='' then
  local kind=(v.presetMessage==v.invalidNameText or v.presetMessage==v.saveFailedText or v.presetMessage==L.presetDeleteFailed) and 'er' or 'ok'
  y=y+W.message(v.presetMessage,x+12,y,w-24,kind)+6
 end
 local any=false
 for i=1,K.maxPresets do
  local entry=host.presets[i]
  if entry then
   any=true
   -- Identifiant et clé d'infobulle du préréglage, faits une fois par préréglage.
   local names=v.entryTexts[entry]
   if not names or names.name~=entry.name or names.profile~=entry.profile then names={name=entry.name,profile=entry.profile,id='custom:'..entry.name,tip=entry.name..'|'..entry.profile}; v.entryTexts[entry]=names end
   local id=names.id
   local tip=v.customTips[names.tip]
   if not tip then tip=wrap(string.format(L.tipCustom,entry.name,L.profiles[entry.profile] or entry.profile)..'\n\n'..T.ui.customPreset); v.customTips[names.tip]=tip end
   if W.visible(y,30) then
    local chip=L.shortProfiles[entry.profile] or entry.profile
    local chw=W.chipWidth(chip)
    if W.row(idOf('custom_',i),x+12,y,w-24-28,30,custom[i],tip) then
     -- Beta 1.29 : préréglage personnel d'essais, de qualifications ou de course : ses règles pour tout le week-end.
     local profile=Presets.apply(entry,e.profiles,e.g); e.profiles[profile].configured=true; C.spreadRules(profile,e.profiles); C.setMark(e.g,profile,C.personalMark); presetTarget(v,profile)
     e.g.loadedPreset=id; e.g.presetsUsed=true; mark(v)
     v.presetName=entry.name
    end
    local nw=w-24-28-20-chw-12
    local ns=W.shrink(entry.name,nw,12,9,'sb')
    W.cell(entry.name,x+22,y+8+(12-ns)*0.5,nw,ns,custom[i] and c.cyanText or c.text,'sb')
    W.chip(chip,x+w-12-28-8-chw,y+7,'n')
    W.rect(x+w-12-28,y,28,30,c.block)
    if W.icon(idOf('custom_delete_',i),'trash',x+w-12-28,y+1,v.tips.ui.deletePreset) then
     if Adapter.deletePreset(host,i) then
      -- Beta 1.52 (relecture) : préréglage chargé supprimé : sa marque « Perso » aussi, dans le profil de son entrée.
      if e.g.loadedPreset==id then e.g.loadedPreset=''; if C.mark(e.g,entry.profile)==C.personalMark then C.setMark(e.g,entry.profile,'') end end
      if v.presetName==entry.name then v.presetName='' end
      v.presetMessage=L.presetDeleted..entry.name; v.dirty()
     else v.presetMessage=L.presetDeleteFailed end
    end
   end
   y=y+33
  end
 end
 if not any then y=y+W.message(L.noCustomPresets,x+12,y+2,w-24,'mut')+8 end
 y=y+8
 -- Hauteur du panneau gardée pour son fond à l'image suivante (il dépend de la liste et des messages).
 v.customPanelH=y-py
 W.clip(); v.contentHeights.home=y+offset-top+GAP
end
-- Partie droite des onglets Réglages et Règles de course : titre, puces, réinitialisation, description, état, puis les
-- réglages qui défilent à la molette.
local function sectionPane(v,e,group,view,p,opts)
 local c=W.colors(); local fw,fh=W.frame().w,W.frame().h
 local x=opts.x; local w=fw-PAD-x
 local top=HEADER+10; local bottom=fh-12
 W.panel(x,top,w,bottom-top)
 local ix=x+14; local iw=w-28
 -- Réinitialisation à droite, puis titre et puces dans la place restante : titre réduit (24 à 16) pour garder les
 -- puces, puce de portée puis d'état retirées si elles ne tiennent toujours pas ; rien ne passe sous le bouton.
 local rw=0
 if opts.reset then
  local label=group=='overlay' and L.overlayReset or L.sectionReset
  rw=math.max(150,W.width(W.upper(label),13,'display')+34)
  if W.button(idOf('reset_',group),label,x+w-14-rw,top+9,rw,28,false,v.tips.ui.sectionReset,'outline') then resetSection(v,e,group,view,p) end
 end
 local limit=x+w-14-(rw>0 and rw+10 or 0)
 local upper=W.upper(opts.title or L.groups[group] or L.globals)
 local scopeW=opts.scope and W.chipWidth(opts.scope)+6 or 0
 local stateW=opts.state and W.chipWidth(opts.state) or 0
 -- Panneaux lumineux (Beta 1.38, maquette) : interrupteur de la section dans la ligne du titre.
 local titleSwitch=group=='lights' and v.tab=='settings'
 if titleSwitch and stateW>0 then stateW=stateW+44 end
 local size=W.shrink(upper,math.max(40,limit-ix-10-scopeW-stateW),24,16,'display')
 local tw=W.width(upper,size,'display')
 if ix+tw+10+scopeW+stateW>limit then scopeW=0 end
 if ix+tw+10+scopeW+stateW>limit then stateW=0 end
 local room=limit-ix-(scopeW+stateW>0 and scopeW+stateW+10 or 0)
 W.cell(upper,ix,top+10+(24-size)*0.5,room,size,c.text,'display')
 local cx=ix+math.min(tw,room)+10
 if scopeW>0 then cx=cx+W.chip(opts.scope,cx,top+14,opts.scopeKind or 'c')+6 end
 if stateW>0 then
  cx=cx+W.chip(opts.state,cx,top+14,opts.stateKind or 'g')+10
  if titleSwitch and W.switch('section_lights_title',cx,top+15,C.on(p,'lights'),v.tips.sections.lights) then p.section_lights=not C.on(p,'lights'); touch(v,p) end
 end
 local y=top+44
 local desc=opts.description or v.descriptions[group] or ''
 local dh=W.paragraph(desc,ix,y,iw,12,c.label)
 -- Réglages modifiés (Beta 1.38, maquette) : en cyan à la suite de la description, sur sa dernière ligne s'il y tient.
 if opts.modified and opts.modified>0 then
  if v.modFor~=opts.modified then v.modFor=opts.modified; v.modText=string.format(opts.modified==1 and L.modifiedOne or L.modifiedMany,opts.modified) end
  local lines=W.lines(desc,iw,12)
  local lw=desc~='' and W.width(lines[#lines] or '',12)+5 or 0
  if lw+W.width(v.modText,12)<=iw then W.text(v.modText,ix+lw,y+math.max(0,#lines-1)*W.lineHeight(12),12,c.cyanText)
  else dh=dh+W.paragraph(v.modText,ix,y+dh,iw,12,c.cyanText) end
 end
 y=y+dh+6
 if group=='lights' then y=activeFor(v,e,ix,y,iw) end
 -- Section décochée pour ce profil (Beta 1.38) : message en tête du volet, contenu grisé dessous.
 if group~='overlay' and not C.on(p,group) then y=y+W.message(group=='rules' and L.rulesOff or L.sectionOff,ix,y,iw,'wn')+6 end
 -- Confirmation de la réinitialisation de cette section seulement (onglet Réglages ; l'onglet Règles de course a la
 -- sienne) : jamais un autre message (accueil, arrivé par un lien des points à vérifier).
 if v.tab=='settings' and v.resetGroup==group and v.presetMessage~='' and v.presetMessage==v.resetText then y=y+W.message(v.presetMessage,ix,y,iw,'ok')+6 end
 -- Overlay en jeu : verrou et replacement en tête.
 if group=='overlay' then
  local g=e.g; local bw=(iw-6)/2
  if W.button('overlay_lock',g.overlayLocked and L.overlayUnlock or L.overlayLock,ix,y,bw,28,not g.overlayLocked,v.globalTips.overlayLocked,g.overlayLocked and 'primary' or nil) then g.overlayLocked=not g.overlayLocked; v.dirty() end
  if W.button('overlay_recenter',L.overlayRecenter,ix+bw+6,y,bw,28,false,v.tips.ui.overlayRecenter) then g.overlayX=-1; g.overlayY=-1; g.overlayScale=1; v.dirty() end
  y=y+34
  if not g.overlayLocked then y=y+W.message(L.overlayHint,ix,y,iw,'ok')+6 end
 end
 local height=bottom-8-y
 local key=opts.key or idOf(group,view)
 local offset=W.scroll(v.scrolls,key,ix,y,iw+6,height,v.contentHeights[key] or 0)
 W.clip(ix,y,iw+6,height)
 v.contentHeights[key]=sectionContent(v,e,group,view,p,ix,y-offset,iw-6,opts.listKey or group,opts.controls or v.controls[group] or {})+12
 W.clip()
end
local function settingsTab(v,e)
 local c=W.colors(); local view=v.view; local p=e.profiles[view]
 local fh=W.frame().h
 local top=HEADER+10; local navW=228
 W.panel(PAD,top,navW,fh-12-top)
 -- En-tête de la liste : profil affiché, sections actives.
 local on,total=sectionsOn(p)
 if v.navFor~=on or v.navView~=view then v.navFor=on; v.navView=view; v.navTitle=string.format(L.navTitle,L.profiles[view]); v.navCount=string.format(L.navCount,on,total) end
 W.label(v.navTitle,PAD+10,top+10,c.soft); W.right(v.navCount,PAD+navW-10,top+10,11,c.label,'mono')
 W.rect(PAD,top+29,navW,1,c.ruleHead)
 local listTop=top+30; local height=fh-12-listTop-4
 local offset=W.scroll(v.scrolls,'nav',PAD,listTop,navW,height,v.contentHeights.nav or 0)
 W.clip(PAD,listTop,navW,height)
 local y=listTop+2-offset
 -- Beta 1.42 : 17 sections ; lignes resserrées (24 px au moins) si la liste dépasse la hauteur de la fenêtre.
 local items=0; for _,block in ipairs(sidebar) do items=items+#block-1 end
 local rowH=28
 if #sidebar*30+items*28>height then rowH=math.max(24,math.floor((height-4-#sidebar*30)/items)) end
 for _,block in ipairs(sidebar) do
  if W.visible(y,22) then W.text(W.upper(L.sidebar[block[1]]),PAD+10,y+8,11,c.group,'label') end
  y=y+26
  for i=2,#block do
   local group=block[i]
   if W.visible(y,rowH) then
    local selected=v.category==group
    local sectionOn=group=='overlay' or C.on(p,group)
    local count=group~='overlay' and group~='globals' and modifiedCount(v,group,view,p) or 0
    local clicked=W.nav(idOf('cat_',group),L.categories[group],PAD,y,navW,selected,not sectionOn,count>0 and intText(count) or '',v.tips.tabs[group],rowH)
    if group~='overlay' then
     if W.switch(idOf('section_',group),PAD+navW-38,y+math.floor((rowH-16)/2),C.on(p,group),v.tips.sections[group]) then p[idOf('section_',group)]=not C.on(p,group); touch(v,p) end
    end
    if clicked then if v.category~=group then v.presetMessage='' end; v.category=group end
   end
   y=y+rowH
  end
  y=y+4
 end
 W.clip(); v.contentHeights.nav=y+offset-listTop+8
 local group=v.category
 local sectionOn=group=='overlay' or C.on(p,group)
 v.paneOpts=v.paneOpts or {}
 local o=v.paneOpts
 o.x=PAD+navW+GAP; o.title=nil; o.description=nil; o.key=nil; o.listKey=nil; o.controls=nil; o.reset=true
 -- Overlay et options globales : valables pour tous les profils (puce neutre) ; le reste : profil affiché.
 local everywhere=group=='overlay' or group=='globals'
 o.scope=everywhere and L.scopeAll or fmt(v,'scope',L.scopeProfile,L.profiles[view]); o.scopeKind=everywhere and 'n' or 'c'
 -- Overlay : toujours actif, puce « Active » (Beta 1.38, maquette).
 o.state=sectionOn and L.chipSectionOn or L.chipSectionOff; o.stateKind=sectionOn and 'g' or 'a'
 o.modified=group~='overlay' and group~='globals' and modifiedCount(v,group,view,p) or 0
 sectionPane(v,e,group,view,p,o)
end
-- Ligne de la colonne de gauche de l'onglet Règles de course : le titre affiche ses réglages à droite (surligné), seul
-- l'interrupteur change l'état ; en journée circuit et en hotlap, arrêt obligatoire et voiture de sécurité grisés.
local function ruleRow(v,name,switch,label,x,y,w,on,tip,switchTip,disabled)
 local id=idOf('rules_view_',name); local selected=v.rulesView==name
 if not W.visible(y,28) then return false,false end
 local clicked=W.nav(id,label,x,y,w,selected,disabled,nil,tip)
 local toggled=W.switch(switch,x+w-38,y+6,on,switchTip,disabled)
 return clicked and not disabled,toggled
end
-- Onglet Règles de course (Beta 1.17, refonte Racing 26) : à gauche les trois vues (avec leur interrupteur) et les jeux
-- de règles de championnat ; à droite les réglages de la vue choisie.
local function rulesTab(v,e)
 local c=W.colors(); local view=v.view; local p=e.profiles[view]
 local fh=W.frame().h
 local top=HEADER+10; local lw=252
 local height=fh-12-top
 local offset=W.scroll(v.scrolls,'rules_left',PAD,top,lw,height,v.contentHeights.rulesLeft or 0)
 W.clip(PAD,top,lw,height)
 local y=top-offset
 local race=e.profiles.C
 local solo=C.solo(view)
 if solo then v.rulesView='all' end
 local soloH=solo and #W.lines(L.raceSwitchesSolo,lw-22,12)*W.lineHeight(12)+10 or 0
 local navH=8+3*28+soloH+4
 W.panel(PAD,y,lw-6,navH)
 local ny=y+4
 local on=C.on(p,'rules')
 local shown,toggled=ruleRow(v,'all','section_rules',L.rulesToggle,PAD,ny,lw-6,on,v.tips.ui.rulesViewAll,v.tips.sections.rules)
 if toggled then p.section_rules=not on; touch(v,p) elseif shown then v.rulesView='all' end
 -- Arrêt obligatoire et voiture de sécurité (Beta 1.18) : état du profil Course (ils n'agissent qu'en course), réglés
 -- ensemble pour les Essais, Qualifications et Course ; chaque jeu de règles les règle aussi. Beta 1.29 : en journée
 -- circuit et en hotlap, où rien de cela n'agit, interrupteurs éteints et sans effet, réglages de course non affichés.
 local stops=not solo and race.mandatoryStops>0
 shown,toggled=ruleRow(v,'stops','mandatory_stop',L.mandatorySwitch,PAD,ny+28,lw-6,stops,v.tips.ui.rulesViewStops,v.tips.ui.mandatoryStop,solo)
 if not solo then
  if toggled then C.weekendSwitch(e.profiles,'mandatoryStops',not stops); mark(v) elseif shown then v.rulesView='stops' end
 end
 local safety=not solo and race.safetyCarEscalation==true
 shown,toggled=ruleRow(v,'safety','safety_switch',L.safetySwitch,PAD,ny+56,lw-6,safety,v.tips.ui.rulesViewSafety,v.tips.ui.safetySwitch,solo)
 if not solo then
  if toggled then C.weekendSwitch(e.profiles,'safetyCarEscalation',not safety); mark(v) elseif shown then v.rulesView='safety' end
 end
 if solo and W.visible(ny+88,soloH) then W.paragraph(L.raceSwitchesSolo,PAD+11,ny+88,lw-28,12,c.label) end
 y=y+navH+GAP
 -- Ce que fera la voiture de sécurité en course : aucune voiture choisie alors qu'elle servirait (repli VSC ou FCY,
 -- prioritaire), neutralisation « Voiture de sécurité » choisie (elle sort de toute façon). En course, voiture choisie
 -- absente de la grille : la VSC ou la FCY continue (Beta 1.19).
 local used=race.neutralization=='sc' or race.safetyCarEscalation
 local note=not solo and (used and e.g.safetyCarModel=='' and L.safetySwitchNoCar or used and e.profile=='C' and e.frame and e.incidents.safety==0 and L.safetySwitchNotOnGrid or race.neutralization=='sc' and L.safetySwitchDirect)
 if note then y=y+W.message(note,PAD+4,y,lw-14,'wn')+GAP end
 if v.presetMessage~='' and v.tab=='rules' then y=y+W.message(v.presetMessage,PAD+4,y,lw-14,'ok')+GAP end
 y=ruleBlock(v,e,PAD,y,lw-6)
 W.clip(); v.contentHeights.rulesLeft=y+offset-top
 -- Arrêts aux stands et voiture de sécurité : réglages du profil Course, le seul où ils agissent (comme leurs
 -- interrupteurs) ; le reste des règles : profil affiché.
 local rv=v.rulesView
 v.paneOpts=v.paneOpts or {}
 local o=v.paneOpts
 local category=ruleCategoryOf(v,e)
 o.x=PAD+lw+GAP; o.reset=false; o.modified=0; o.state=category and L.ruleNames[category] or L.ruleCustomShort; o.stateKind='C'
 if rv=='all' then
  o.title=nil; o.description=nil; o.key='rules'..view..rv; o.listKey='rules_all'; o.controls=v.ruleLists.all
  o.scope=fmt(v,'scope',L.scopeProfile,L.profiles[view]); o.scopeKind='c'
  sectionPane(v,e,'rules',view,p,o)
 else
  o.title=rv=='stops' and L.stopsTitle or L.safetySwitch; o.description=rv=='stops' and L.sectionDescs.stops or L.sectionDescs.safety
  o.key=idOf('rules',rv); o.listKey=idOf('rules_',rv); o.controls=v.ruleLists[rv]
  o.scope=fmt(v,'scope',L.scopeProfile,L.profiles.C); o.scopeKind='c'
  sectionPane(v,e,'rules','C',race,o)
 end
end
-- Diagnostic (refonte Racing 26) : à gauche les mises à jour, la calibration, les phares et les zones, le journal, les
-- capacités CSP et les fonctions IA exposées ; à droite le tableau des IA pilotées, les performances et le journal
-- circulaire filtrable. Chaque zone défile à la molette.
-- Beta 1.42 : course des IA (stratégies, sanctions) dans le Diagnostic : lignes préparées et mises en cache par les
-- modules ({text=, kind=}), bloc montré seulement s'il y en a.
local function raceRows(list,x,y,w,c)
 for k=1,#list do
  local row=list[k]
  if W.visible(y,18) then W.cell(row.text or '',x+12,y+3,w-24,11,row.kind=='warn' and c.warn or row.kind=='text' and c.text or c.soft,'mono') end
  y=y+18
 end
 return y
end
local function aiRaceBlock(e,x,y,w)
 local a,b=e.strategy.rows,e.sanctions.rows
 local n=#a+#b
 if n==0 then return y end
 local c=W.colors()
 local h=40+n*18
 if W.visible(y,h) then W.panel(x,y,w,h); W.heading(L.aiRaceHeading,x+12,y+7,w-24,L.aiRaceNote,'body',c.label) end
 local ry=raceRows(a,x,y+34,w,c)
 raceRows(b,x,ry,w,c)
 return y+h+GAP
end
local function diagnosticTab(v,e,host)
 local c=W.colors(); local frame=e.frame
 local fw,fh=W.frame().w,W.frame().h
 local top=HEADER+10; local bottom=fh-12
 local lw=330
 local height=bottom-top
 local offset=W.scroll(v.scrolls,'diag_left',PAD,top,lw,height,v.contentHeights.diagLeft or 0)
 W.clip(PAD,top,lw,height)
 local x=PAD; local w=lw-8
 local y=top-offset
 y=updateBlock(v,e,host,x,y,w)
 if frame then
  -- Ligne CSP (maquette, Beta 1.39) : libellés discrets, valeurs en clair ; morceaux refaits au changement.
  if v.cspFor~=frame.patch or v.cspTrack~=frame.track or v.cspLength~=frame.length then
   v.cspFor=frame.patch; v.cspTrack=frame.track; v.cspLength=frame.length
   local parts=v.cspParts or {}; v.cspParts=parts
   parts[1]=L.patch; parts[2]=frame.patch; parts[3]=' · '..L.track; parts[4]=frame.track; parts[5]=' · '..L.splineLabel; parts[6]=string.format(L.meters,frame.length)
  end
  if W.visible(y,14) then
   local cx=x+2
   for i=1,6 do local part=v.cspParts[i]; W.text(part,cx,y,11,i%2==0 and c.soft or c.label,'mono'); cx=cx+W.width(part,11,'mono') end
  end
  y=y+20
 end
 -- Calibration des signes.
 local ch=8+24+8+28+8
 W.panel(x,y,w,ch)
 if W.visible(y+8,24) then
  W.heading(L.signs,x+10,y+8,w-20)
  local phase=v.calibration.phase
  W.chipRight(L.calibrationShort[phase] or phase,x+w-10,y+11,phase=='ready' and 'g' or 'c')
 end
 if W.visible(y+40,28) then
  if v.signOffset~=e.g.offsetSign or v.signSide~=e.g.sideSign then
   v.signOffset=e.g.offsetSign; v.signSide=e.g.sideSign; v.signText=e.g.offsetSign..' / '..e.g.sideSign
  end
  -- Une ligne (maquette, Beta 1.39) : libellé et signes en chiffres alignés, l'état est dans la puce (son texte long en
  -- infobulle), puis « Relancer » à droite.
  local bw=math.max(90,W.width(W.upper(L.calibrateShort),12,'display')+26)
  local lw=math.min(W.width(L.signLabel,12),math.max(40,w-30-bw-70))
  W.cell(L.signLabel,x+10,y+46,lw,12,c.soft)
  W.text(v.signText,x+18+lw,y+46,12,c.text,'mono')
  local stateTip=v.calibrationTips[v.calibration.phase]
  if stateTip then W.help(stateTip,x+10,y+40,w-30-bw,24,4) end
  if W.button('calibrate',L.calibrateShort,x+w-10-bw,y+40,bw,24,false,v.tips.ui.calibrate,'outline') then e.recalibrateRequested=true end
 end
 y=y+ch+GAP
 -- Phares et zones.
 local half=(w-20-12)/2
 local zh=8+24+8+18+30+30+8
 W.panel(x,y,w,zh)
 if W.visible(y+8,24) then W.heading(L.diagFlash,x+10,y+8,half); W.heading(L.diagZones,x+22+half,y+8,half,intText(#e.zones),'mono') end
 if W.visible(y+40,80) then
  if v.flashFor~=e.g.flashField or v.flashEvent~=e.flash.eventId or v.flashCount~=e.flash.eventCount then
   v.flashFor=e.g.flashField; v.flashEvent=e.flash.eventId; v.flashCount=e.flash.eventCount
   v.flashText=L.field..(e.g.flashField~='' and e.g.flashField or L.unlearned)
   v.flashEventText=L.event..e.flash.eventId..' / '..e.flash.eventCount
  end
  W.cell(v.flashText,x+10,y+42,half,12,e.g.flashField~='' and c.soft or c.warn)
  -- Dernier événement des phares (Beta 1.39) : en infobulle du champ.
  W.help(v.flashEventText,x+10,y+40,half,18,4)
  if W.button('learn',v.learnText,x+10,y+62,half,26,e.flash.learnUntil>e.time,v.tips.ui.learn,'outline') then Flash.learn(e.flash,e.time) end
  if e.flash.learnUntil>e.time then W.cell(v.learningText,x+10,y+92,half,11,c.cyanText) end
  local zx=x+22+half; local zw=(half-4)/2
  if frame then
   if W.button('mark_start',L.markStartShort,zx,y+40,zw,26,e.zoneStart>=0,v.tips.ui.markStart) and frame.player>0 then e.zoneStart=frame.cars[frame.player].spline end
   if W.button('mark_end',L.markEndShort,zx+zw+4,y+40,zw,26,false,v.tips.ui.markEnd) and e.zoneStart>=0 and frame.player>0 and #e.zones<K.maxZones then
    e.zones[#e.zones+1]={from=e.zoneStart,to=frame.cars[frame.player].spline,noYield=true,noOvertake=true,maxOffset=K.pitOffsetMax,note=''}; e.zoneStart=-1
   end
   if W.button('export',L.exportZones,zx,y+70,half,26,false,v.tips.ui.export,'outline') then host.clipboard(Zones.export(e.zones)) end
  end
  W.help(v.tips.ui.zoneCount,x+22+half,y+8,half,24,4)
 end
 y=y+zh+GAP
 -- Journal de session.
 -- Journal (maquette, Beta 1.39) : fin du chemin et taille groupée par milliers, refaites au changement.
 if host.journalPath and (v.journalFor~=host.journalPath or v.journalBytesFor~=(host.journalBytes or 0)) then
  v.journalFor=host.journalPath; v.journalBytesFor=host.journalBytes or 0
  local path=host.journalPath:gsub('\\','/')
  local tail=path:match('([^/]+/[^/]+)$') or path
  v.journalText=string.format(L.journalShort,(tail~=path and '…/' or '')..tail,groupDigits(v.journalBytesFor))
 end
 local journalText=host.journalPath and v.journalText or L.journalOff
 local jh=8+24+8+#W.lines(journalText,w-20,11,'mono')*W.lineHeight(11)+10
 W.panel(x,y,w,jh)
 if W.visible(y+8,24) then
  W.heading(L.journalHeading,x+10,y+8,w-60)
  if W.switch('journal',x+w-42,y+11,e.g.journal,v.tips.ui.journal) then e.g.journal=not e.g.journal; v.dirty() end
 end
 if W.visible(y+40,jh-40) then W.paragraph(journalText,x+10,y+40,w-20,11,c.label,'mono') end
 y=y+jh+GAP
 -- Capacités CSP : grille de deux colonnes, état à droite de chaque ligne.
 local names=Caps.names
 local ready=0; for _,name in ipairs(names) do local r=host.caps[name].reason; if r=='ready' or r=='present' then ready=ready+1 end end
 if v.capsFor~=ready then v.capsFor=ready; v.capsReady=intText(ready); v.capsTotal=' / '..#names end
 local rows=math.ceil(#names/2)
 -- Beta 1.53 : mode natif détaillé (CSP accepte 0 à 2) avec l'état de la relecture ; textes refaits au changement seul.
 local caps=host.caps; local levelNote
 if caps.levelMode=='native' then
  levelNote=fmt(v,'capsLevel',not caps.probeDone and L.levelNativePending or caps.clampProven and L.levelNativeClamped or L.levelNativeRead,caps.probeRead or 0)
 else levelNote=caps.probeDone and L.choices[caps.levelMode] or L.probe end
 -- Beta 1.57 : champs de CSP absents de cette version (lus comme absents), après le mode de niveau.
 local frame=e.frame; local missing=frame and ((frame.missingSim or '')~='' or (frame.missingCar or '')~='')
 local notesText=missing and fmt(v,'capsNotes','%s%s · %s',L.levelMode,levelNote,fmt(v,'capsMissing',L.cspMissingFields,frame.missingSim~='' and frame.missingSim or '–',frame.missingCar~='' and frame.missingCar or '–'))
  or fmt(v,'capsNotes','%s%s',L.levelMode,levelNote)
 local nh=#W.lines(notesText,w-20,12)*W.lineHeight(12)+#W.lines(L.gripUnits,w-20,11)*W.lineHeight(11)+8
 local kh=8+24+6+rows*20+6+nh+8
 W.panel(x,y,w,kh)
 if W.visible(y+8,24) then
  -- Compteur (maquette, Beta 1.39) : capacités prêtes en vert, total en gris.
  W.heading(L.capabilities,x+10,y+8,w-20)
  local tw=W.width(v.capsTotal,11,'mono'); local rw=W.width(v.capsReady,11,'mono')
  W.text(v.capsTotal,x+w-10-tw,y+14,11,c.label,'mono'); W.text(v.capsReady,x+w-10-tw-rw,y+14,11,c.ok,'mono')
 end
 local cy=y+38; local colW=(w-20-12)/2
 for i,name in ipairs(names) do
  local cap=host.caps[name]
  local cx=x+10+((i-1)%2)*(colW+12); local ry=cy+math.floor((i-1)/2)*20
  if W.visible(ry,20) then
   local state=L.capShort[cap.reason] or cap.reason
   local col=cap.reason=='missing' and c.warn or cap.reason=='failures' and c.dangerText or cap.reason=='ready' and c.ok or c.muted
   local sw=W.width(W.upper(state),11,'label')+12
   W.cell(v.capLabels[name],cx,ry+3,colW-sw-4,12,c.soft)
   W.circle(cx+colW-sw+3,ry+10,3,col)
   W.text(W.upper(state),cx+colW-sw+9,ry+4,11,col,'label')
   W.rect(cx,ry+19,colW,1,c.block)
   -- Infobulle : nom long de la capacité (s'il diffère du nom court) et son état, faite une fois par état.
   local tips=v.capTips[name]; local tip=tips[cap.reason]
   if not tip then tip=(v.capLong[name]~=v.capLabels[name] and v.capLong[name]..'\n' or '')..(L.capStates[cap.reason] or cap.reason); tips[cap.reason]=tip end
   W.help(tip,cx,ry,colW,20,3)
  end
 end
 local ny=cy+rows*20+6
 if W.visible(ny,nh) then
  local notesTop=ny
  ny=ny+W.paragraph(notesText,x+10,ny,w-20,12,c.label)
  W.paragraph(L.gripUnits,x+10,ny,w-20,11,c.label)
  -- Zone de freinage émulée (Beta 1.39) : en infobulle des notes, absente de la maquette.
  W.help(v.brakeTip,x+10,notesTop,w-20,nh,4)
 end
 y=y+kh+GAP
 -- Fonctions IA exposées par CSP : en-tête cliquable (nombre, flèche), noms seulement.
 local count=#host.aiFunctions
 if v.apiFor~=count then v.apiFor=count; v.apiText=string.format(L.apiCount,count); v.apiOpenText=v.apiText..'  ▴'; v.apiClosedText=v.apiText..'  ▾' end
 local open=v.open.apiList==true
 local ah=4+28+(open and count*20+8 or 0)+4
 W.panel(x,y,w,ah)
 if W.visible(y+4,28) then
  local clicked,hover=W.hit('api_list',x+8,y+4,w-16,28)
  W.frame().active.api_list=open
  if hover then W.rect(x+8,y+4,w-16,28,c.block) end
  W.bar(x+12,y+12,c.cyan)
  W.text(W.upper(L.apiList),x+23,y+10,13,hover and c.text or c.soft,'cond')
  W.right(open and v.apiOpenText or v.apiClosedText,x+w-12,y+11,11,c.label,'mono')
  W.help(v.tips.ui.apiList,x+8,y+4,w-16,28,5)
  if clicked then v.open.apiList=not open end
 end
 if open then
  local fy=y+36
  W.rect(x+10,fy-2,w-20,1,c.rule)
  for _,name in ipairs(host.aiFunctions) do
   if W.visible(fy,20) then W.cell(name,x+12,fy+3,w-24,12,c.soft,'mono'); W.rect(x+10,fy+19,w-20,1,c.block) end
   fy=fy+20
  end
 end
 y=y+ah+GAP
 y=aiRaceBlock(e,x,y,w)
 W.clip(); v.contentHeights.diagLeft=y+offset-top
 -- Colonne de droite : IA pilotées, performances, journal circulaire.
 local rx=PAD+lw+GAP; local rw=fw-PAD-rx
 local tableH=math.max(140,(bottom-top-GAP*2-82)*0.55)
 W.panel(rx,top,rw,tableH)
 if v.carsFor~=e.activeCount then v.carsFor=e.activeCount; v.carsNote=string.format(L.carsNote,e.activeCount) end
 W.heading(L.carsHeading,rx+12,top+7,rw-24,v.carsNote,'body',c.label)
 local cols=v.diagCols
 local tw=rw-16
 -- Beta 1.53 : colonne N / A / P élargie (niveau demandé > niveau appliqué quand ils diffèrent).
 cols[1][2]=0; cols[2][2]=tw-402; cols[3][2]=tw-262; cols[4][2]=tw-206; cols[5][2]=tw-40
 cols[1][3]=tw-412; cols[2][3]=134; cols[3][3]=48; cols[4][3]=160; cols[5][3]=40
 for _,col in ipairs(cols) do W.label(col[1],rx+8+col[2],top+36) end
 local tableTop=top+54; local tableBodyH=tableH-58
 local tableOffset=W.scroll(v.scrolls,'diag_cars',rx+4,tableTop,rw-8,tableBodyH,v.contentHeights.diagCars or 0)
 W.clip(rx+4,tableTop,rw-8,tableBodyH)
 y=tableTop-tableOffset
 local rowsData=v.debugRows
 local n=0
 if frame then
  for i=1,frame.count do
   local a,s,cmd=frame.cars[i],e.states[i],e.commands[i]
   if a.control then
    n=n+1
    if W.visible(y,20) then
     local row=rowsData[i]; if not row then row={}; rowsData[i]=row end
     -- Textes refaits seulement quand les valeurs affichées (arrondies) changent : aucune chaîne neuve à chaque image.
     local off=math.floor(cmd.offset*100+0.5); local lv=math.floor(cmd.level*100+0.5); local ag=math.floor(cmd.aggression*100+0.5)
     local ca=math.floor(cmd.caution*10+0.5); local gp=s.gap<math.huge and math.floor(s.gap+0.5) or -1
     -- Beta 1.53 : niveau réellement écrit dans la voiture (plafond 100 % si CSP refuse plus, sonde, restitution).
     local hs=host.cars[i]; local la=hs and hs.owned and hs.level and math.floor(hs.level*100+0.5) or lv
     if row.id~=a.index or row.name~=a.name or row.off~=off or row.lv~=lv or row.la~=la or row.ag~=ag or row.ca~=ca or row.gp~=gp then
      row.id=a.index; row.name=a.name; row.off=off; row.lv=lv; row.la=la; row.ag=ag; row.ca=ca; row.gp=gp
      row.car=string.format('%02d %s',a.index,a.name~='' and a.name or a.id)
      row.offset=string.format('%+.2f',off/100)
      row.nap=la~=lv and string.format('%.2f>%.2f / %.2f / %.1f',lv/100,la/100,ag/100,ca/10) or string.format('%.2f / %.2f / %.1f',lv/100,ag/100,ca/10)
      row.gap=gp>=0 and string.format('%d m',gp) or '—'
     end
     if n%2==0 then W.rect(rx+4,y,rw-8,20,c.rowAlt) end
     local sx=rx+8
     local stateCol=s.state=='DRIVE' and c.label or (s.state=='AVOID' or s.state=='CALM') and c.warn or c.cyanText
     W.cell(row.car,sx+cols[1][2],y+4,cols[1][3],11,c.text,'mono')
     W.cell(L.states[s.state] or s.state,sx+cols[2][2],y+4,cols[2][3],11,stateCol,'mono')
     W.cell(row.offset,sx+cols[3][2],y+4,cols[3][3],11,c.soft,'mono')
     W.cell(row.nap,sx+cols[4][2],y+4,cols[4][3],11,c.soft,'mono')
     W.right(row.gap,sx+cols[5][2]+cols[5][3],y+4,11,c.soft,'mono')
     W.help(L.reasons[s.reason] or s.reason,rx+4,y,rw-8,20,3)
    end
    y=y+20
   end
  end
 end
 W.clip(); v.contentHeights.diagCars=y+tableOffset-tableTop
 -- Performances : quatre tuiles.
 local py=top+tableH+GAP
 W.panel(rx,py,rw,82)
 W.heading(L.performance,rx+12,py+7,rw-24,L.perfScope)
 local tile=(rw-24-15)/4
 -- Valeurs affichées (au millième) comparées une à une : textes refaits seulement quand l'une change.
 local mean,peak=math.floor(e.meanFrame*1000+0.5),math.floor(e.maxFrame*1000+0.5); local rejected=host.rejected+(frame and frame.invalid or 0)+(frame and frame.errors or 0)
 if v.perfFor~=mean or v.perfPeak~=peak or v.perfErr~=e.errors or v.perfHost~=host.errors or v.perfRej~=rejected or v.perfTimer~=(host.timer~=nil) then
  v.perfFor=mean; v.perfPeak=peak; v.perfErr=e.errors; v.perfHost=host.errors; v.perfRej=rejected; v.perfTimer=host.timer~=nil
  v.perfMean=host.timer and string.format('%.3f',e.meanFrame) or '—'
  v.perfMax=host.timer and string.format('%.3f',e.maxFrame) or '—'
  v.perfErrors=string.format('%d · %d',e.errors,host.errors)
  v.perfRejected=intText(rejected)
 end
 local items=v.perfItems
 items[1][2]=v.perfMean; items[2][2]=v.perfMax; items[3][2]=v.perfErrors; items[4][2]=v.perfRejected
 for i,item in ipairs(items) do
  local tx=rx+12+(i-1)*(tile+5)
  W.rect(tx,py+36,tile,40,c.block)
  W.label(item[1],tx+8,py+41)
  W.text(item[2],tx+8,py+55,15,i==3 and (e.errors+host.errors==0 and c.ok or c.danger) or c.text,'mono')
  -- Unité des temps (maquette) : « ms » en petit après la moyenne et le maximum.
  if i<=2 and host.timer then W.text(L.perfUnit,tx+8+W.width(item[2],15,'mono'),py+59,11,c.label,'mono') end
 end
 W.help(host.timer and v.tips.ui.performance or L.runtimeTiming,rx,py,rw,82,2)
 -- Journal circulaire, filtrable par niveau.
 local ly=py+82+GAP
 local lh=bottom-ly
 W.panel(rx,ly,rw,lh)
 W.heading(L.logs,rx+12,ly+7,rw-24-210)
 local picked=W.segment('log_filter',v.logLabels,rx+rw-12-210,ly+6,210,22,v.logFilter,v.tips.ui.filter)
 if picked then v.logFilter=picked end
 local logTop=ly+36; local logHeight=math.max(40,lh-44)
 W.rect(rx+8,logTop,rw-16,logHeight,c.bg)
 local logOffset=W.scroll(v.scrolls,'diag_log',rx+8,logTop,rw-16,logHeight,v.contentHeights.diagLog or 0)
 W.clip(rx+8,logTop,rw-16,logHeight)
 y=logTop+3-logOffset
 for k=0,e.log.count-1 do
  local r=e.log[(e.log.head-k-1)%K.logLines+1]
  if v.logFilter==1 or r.level==L.logLevels[v.logFilter] then
   if W.visible(y,18) then
    -- Beta 1.53 : ligne traduite dans la langue de l'interface (le fichier du journal reste en français), refaite
    -- seulement pour une ligne nouvelle ou au changement de langue.
    if r.shownText==nil or r.shownSerial~=r.serial or r.shownLang~=Locale.current then
     r.shownSerial=r.serial; r.shownLang=Locale.current
     r.shownText=string.format('%.1f %s [%d] %s',r.time,r.level,r.index,Locale.current=='fr' and r.message or (Journal.english(r.message)))
    end
    W.cell(r.shownText,rx+14,y+2,rw-30,11,r.level=='ERROR' and c.dangerText or r.level=='WARN' and c.warn or r.level=='DEBUG' and c.label or c.muted,'mono')
   end
   y=y+18
  end
 end
 W.clip(); v.contentHeights.diagLog=y+logOffset-logTop+6
end
-- Taille compacte de la fenêtre de réglages (Beta 1.14), pour l'applicateur.
function M.compactSize() return vec2(K.compactWidth,K.compactHeight) end
-- Textes et mesures de la fenêtre qui dépendent de la langue (refaits au changement de langue), couleurs des panneaux
-- lumineux ; mesurés pendant le dessin (police chargée).
local function windowSetup(v)
 if v.setupFor==Locale.current then return end
 v.setupFor=Locale.current
 local c=W.colors()
 v.languageCodes={}; v.languageLabels={}; v.languageIds={}
 local known={}; for _,code in ipairs(Locale.codes) do known[code]=true end
 for _,code in ipairs(languageOrder) do if known[code] then v.languageCodes[#v.languageCodes+1]=code; v.languageLabels[#v.languageLabels+1]=languageLabels[code]; v.languageIds[#v.languageIds+1]='lang_'..code end end
 v.profileLabels={}; v.profileWidths={}; v.profileCodes={}; v.profileCodeWidths={}; v.profileTotal=0; v.profileCodeTotal=0
 for _,profile in ipairs(C.profiles) do
  local label=W.upper(L.shortProfiles[profile])
  v.profileLabels[profile]=label; v.profileWidths[profile]=W.width(label,12,'cond')+26
  local code=label:match('^[%z\1-\127\194-\244][\128-\191]*') or label
  v.profileCodes[profile]=code; v.profileCodeWidths[profile]=W.width(code,12,'cond')+26
  v.profileTotal=v.profileTotal+v.profileWidths[profile]; v.profileCodeTotal=v.profileCodeTotal+v.profileCodeWidths[profile]
 end
 v.presetDescs=L.presetDescs
 v.globalSwitches={{'useGripBoost',L.grip},{'useBrakeAssist',L.brake},{'overrideAwareness',L.awareness},{'debugLog',L.debugLog}}
 v.backgroundLabels={L.backgrounds.solid,L.backgrounds.ghost,L.backgrounds.transparent}
 v.showLabels={L.choiceShort.panelShow.info,L.choices.always}
 -- Défauts des choix globaux (« défaut : … », maquette), en minuscules comme ceux des sections.
 local function lower(label) return label and string.format(L.defaultValue,label:lower()) or nil end
 local level=1; for i,k in ipairs(C.globalChoices.levelMode) do if k==C.globalDefaults.levelMode then level=i end end
 v.levelDefault=lower(L.levelModeLabels[level])
 local back=1; for i,k in ipairs(backgroundKeys) do if k==C.globalDefaults.overlayBackground then back=i end end
 v.backgroundDefault=lower(v.backgroundLabels[back])
 v.showDefault=lower(C.globalDefaults.panelShow=='always' and v.showLabels[2] or v.showLabels[1])
 v.logLabels={}; for i,level in ipairs(L.logLevels) do v.logLabels[i]=level end
 v.diagCols={{L.colCar,0,0},{L.colState,0,0},{L.colOffset,0,0},{L.colNAP,0,0},{L.colGap,0,0}}
 v.perfItems={{L.perfLabels[1],''},{L.perfLabels[2],''},{L.perfLabels[3],''},{L.perfLabels[4],''}}
 v.classLabels={}; for i=1,K.classPatternClassMax do v.classLabels[i]=intText(i) end
 v.lightColors={[K.flagStart]=c.ok,[K.flagCaution]=c.flagYellow,[K.flagSlippery]=c.orangeDot,[K.flagStop]=c.flagRed,[K.flagSlowVehicle]=c.flagWhite,[K.flagFasterCar]=c.flagBlue}
 v.legendColors={c.ok,c.flagYellow,c.flagRed,c.flagWhite,c.orangeDot,c.flagBlue}
 -- Noms courts des capacités (maquette, Beta 1.38) ; les états longs restent dans l'infobulle.
 v.capLabels={}; v.capLong={}; v.capTips={}
 for _,name in ipairs(Caps.names) do v.capLong[name]=L[name..'Label'] or L[name] or name; v.capLabels[name]=L.capNames[name] or v.capLong[name]; v.capTips[name]={} end
 v.versionChip=nil; v.pillFor=nil; v.sessionFor=nil; v.guardFor=nil; v.navFor=nil; v.rulesResetFor=nil; v.capsFor=nil; v.apiFor=nil; v.carsFor=nil
 v.sectionsFor=nil; v.warnCountFor=nil; v.customCountFor=nil; v.bytesFor=nil; v.noteFor=nil; v.patternCountFor=nil; v.modFor=nil
 v.updateVersions=nil; v.updateHeaderFor=nil; v.updateAlertFor=nil; v.updateReportFor=nil; v.rollbackFor=nil; v.flashFor=nil; v.cspFor=nil; v.journalFor=nil; v.perfFor=nil
 v.scaleFor=nil; v.opacityFor=nil; v.contentFor=nil; v.infoFor=nil; v.seedFor=nil; v.gripFor=nil; v.guardKind=nil
end
local function drawWindow(v,e,host)
 windowSetup(v)
 headerBar(v,e)
 if v.tab=='home' then homeTab(v,e,host)
 elseif v.tab=='settings' then settingsTab(v,e)
 elseif v.tab=='rules' then rulesTab(v,e)
 else diagnosticTab(v,e,host) end
end
-- Onglet, section et vue des règles affichés (Beta 1.39), pour situer une image lente dans le journal ; texte fait
-- seulement quand une image est lente.
function M.where(v)
 if v.tab=='settings' then return 'reglages/'..tostring(v.category) end
 if v.tab=='rules' then return 'regles/'..tostring(v.rulesView) end
 return tostring(v.tab)
end
function M.main(v)
 local e,host=v.e,v.host
 if not v.drawable then
  text(string.format(L.titleVersion,C.release)); text(L.cspTooOld)
  return
 end
 fontsOnce(v)
 v.frameNo=(v.frameNo or 0)+1
 -- Profil affiché (consulté, réglé) distinct du profil en cours : retour au profil en cours à chaque changement de
 -- session, ou à chaque image sans le profil automatique.
 if not e.g.autoProfile or v.viewFor~=e.profile then v.view=e.profile; v.viewFor=e.profile end
 if e.g.loadedPreset~=v.loadedFor then
  v.loadedFor=e.g.loadedPreset
  local kind,name=e.g.loadedPreset:match('^([^:]+):(.*)$')
  if kind=='builtin' then name=v.builtinNames[name] or name end
  v.loadedName=name or e.g.loadedPreset
 end
 W.begin('main')
 -- Erreur de dessin : polices et découpes refermées dans la même image, puis l'erreur remonte (journalisée une fois).
 local ok,err=pcall(drawWindow,v,e,host)
 W.finish()
 if not ok then error(err,0) end
end
-- Overlay « Racing 26 » (Beta 1.35, Hud de la maquette) : fond à coin coupé à l'opacité réglée, bande d'accent en haut
-- à la couleur du drapeau ; drapeau à gauche (aplat et sigle, pastille de lettres SC, VSC, RS, SS au même gabarit,
-- damier, diagonale, disque, bandes) ; consigne au centre (titre condensé extra-gras, détail) ; à droite le temps delta
-- (vert positif, rouge négatif et clignotant) ou la place à rejoindre ; en bas, pastilles d'état en parallélogramme.
-- Rouge et bleu clignotent, comme les voyants d'un volant ; un nouveau drapeau aussi, quelques secondes. Texte TrueType
-- à la taille voulue (DWrite, polices de l'app) ; sans lui, texte simple.
local panelColors,panelAlpha
-- alpha : opacité du contenu (Beta 1.25) ; palette refaite seulement quand elle change.
local function faded(col,alpha) return rgbm(col.r,col.g,col.b,(col.mult or col.m or 1)*alpha) end
local function panelPalette(alpha)
 alpha=alpha or 1
 if panelColors==nil or panelColors and panelAlpha~=alpha then
  panelColors=false; panelAlpha=alpha
  local values={red={0.882,0.039,0.118,1},yellow={1,0.824,0.122,1},blue={0.184,0.482,1,1},green={0.18,0.878,0.498,1},pit={0.949,0.953,0.961,1},
   back={0.075,0.078,0.082,0.86},ink={0.067,0.071,0.078,1},over={1,0.353,0.306,1},amber={1,0.761,0.239,1},orange={1,0.478,0.102,1},
   under={0.18,0.878,0.498,1},overBack={0.227,0.086,0.078,0.94},underBack={0.055,0.165,0.106,0.94},amberBack={0.18,0.141,0.063,0.94},
   off={0.165,0.18,0.212,1},best={0.698,0.424,1,1},
   blueSide={0.122,0.373,0.878,1},underLabel={0.624,0.851,0.722,1},overLabel={1,0.706,0.678,1}}
  local out={}
  for key,c in pairs(values) do local ok,color=pcall(rgbm,c[1],c[2],c[3],c[4]*alpha); if not ok then return false end; out[key]=color end
  if pcall(vec2,0,0) and callable(ui.drawRectFilled) and callable(ui.windowSize) and callable(ui.getCursor)
   and (callable(ui.dwriteDrawTextClipped) or callable(ui.drawText)) then
   -- Teintes neutres communes aux fenêtres (une seule palette) ; seules les couleurs des drapeaux sont propres au panneau.
   local w=W.colors(); out.text=faded(w.text,alpha); out.dim=faded(w.muted,alpha); out.label=faded(w.label,alpha); out.pillBack=faded(w.control,alpha); out.drsBack=faded(w.panel,alpha)
   out.accent=faded(w.cyan,alpha); panelColors=out
  end
 end
 return panelColors
end
local flagColors={lap='pit',red='red',sc='yellow',scIn='yellow',fcy='yellow',vsc='yellow',vscEnd='yellow',restart='green',yellow='yellow',zone='yellow',zone1='yellow',native='yellow',blue='blue',green='green',pit='pit',slippery='yellow',black='ink',penalty='ink',checkered='ink',white='pit',
 slow='pit',warning='ink',meatball='orange',update='accent',rolling='yellow',standing='yellow',lights='yellow',go='green',jump='red',start='green',finish='pit'}
-- Sigle inscrit dans le drapeau (rouge, bleu et vert parlent d'eux-mêmes) ; double jaune : « !! ».
local flagCodes={fcy='FCY',yellow='!',zone='!!',zone1='!',native='!',pit='P'}
-- Pastille de lettres (cadre et lettres jaunes sur fond noir) : voiture de sécurité, VSC, départ lancé ou arrêté, feux.
local badgeCodes={sc='SC',scIn='SC',vsc='VSC',vscEnd='VSC',rolling='RS',standing='SS'}
-- Points réutilisés (src/widgets) et cadres de texte réutilisés : aucune table ni point neufs à chaque image ; chaque
-- appel de dessin les consomme aussitôt.
local pv=W.vec
local R1,R2,ROW,LIGHTS={},{},{},{}
local function box(t,x1,y1,x2,y2) t[1]=x1; t[2]=y1; t[3]=x2; t[4]=y2; return t end
-- Alignements DWrite (ui.Alignment) : début, centre, fin.
local START,CENTER,FINISH=-1,0,1
-- Texte dans un cadre {x1,y1,x2,y2}, aligné, éventuellement replié ; sans DWrite : texte simple en haut à gauche.
local function write(text,size,r,color,align,wrap)
 if callable(ui.dwriteDrawTextClipped) then
  ui.dwriteDrawTextClipped(text,size,pv(r[1],r[2]),pv(r[3],r[4]),align,wrap and START or CENTER,wrap==true,color)
 else ui.drawText(text,pv(r[1],r[2]),color) end
end
-- Polices de l'overlay : celles de la fenêtre (src/widgets), poussées seulement si DWrite est complet, et seulement
-- quand la police change (une seule poussée à la fois) ; tout est dépilé en fin de dessin, même après une erreur.
local fontable=nil
local overlayFont=nil
local overlayDepth=0
local function font(role,on)
 if fontable==nil then fontable=callable(ui.pushDWriteFont) and callable(ui.popDWriteFont) and callable(ui.dwriteDrawTextClipped) end
 if not fontable or not on then return end
 local name=W.fonts()[role] or W.fonts().body
 if overlayFont==name then return end
 if overlayDepth>0 then ui.popDWriteFont(); overlayDepth=overlayDepth-1 end
 ui.pushDWriteFont(name); overlayDepth=overlayDepth+1; overlayFont=name
end
local function fontRelease() while overlayDepth>0 do ui.popDWriteFont(); overlayDepth=overlayDepth-1 end; overlayFont=nil end
-- Largeurs mesurées par police poussée, taille et texte : mémorisées (vidées au-delà de K.uiMeasureCache), comme celles du kit.
local measured,measuredCount={},0
local function textWidth(text,size)
 local key=overlayFont or ''
 local byFont=measured[key]
 if not byFont then byFont={}; measured[key]=byFont end
 local bySize=byFont[size]
 if not bySize then bySize={}; byFont[size]=bySize end
 local hit=bySize[text]
 if hit then return hit end
 local width=#text*size*0.55
 if callable(ui.measureDWriteText) then local ok,s=pcall(ui.measureDWriteText,text,size); if ok and s and s.x then width=s.x end end
 measuredCount=measuredCount+1
 if measuredCount>K.uiMeasureCache then measured={}; measuredCount=0 end
 bySize[text]=width
 return width
end
-- Plus grande taille (au plus size) qui fait tenir le texte sur une ligne de la largeur donnée.
local function fitSize(text,size,width)
 local w=textWidth(text,size)
 return w>width and math.max(10,size*width/w) or size
end
-- Disposition du bandeau (pure, testée) : une bande à hauteur de fenêtre (drapeau, titre et consigne courte sur une
-- ligne, delta à droite), la version en petit dans le coin haut droit ; la ligne des pastilles n'est réservée que si
-- elles existent. Jamais de chevauchement, de 360 × 80 (taille minimale) à 900 × 220, quel que soit le haut du contenu.
-- edge : haut de l'overlay (bande d'accent tout en haut, au-dessus de la ligne de session) ; thick : son épaisseur.
-- Rectangle {x1,y1,x2,y2} réécrit dans sa table (créée une seule fois).
local function rect4(t,a,b,c,d) t=t or {}; t[1]=a; t[2]=b; t[3]=c; t[4]=d; return t end
function M.flagLayout(w,h,top,delta,pills,edge,thick,out)
 local pad,gap,bar=6,10,4
 -- Beta 1.36 : out, table gardée d'une image à l'autre (overlay) ; ses rectangles sont réécrits, jamais recréés.
 local l=out or {}
 l.delta=nil; l.detail=nil; l.pills=nil
 local pillH=pills and U.clamp((h-top)*0.24,14,22) or 0
 local bandBottom=h-(pills and pillH+6 or 2)
 local bandH=math.max(20,bandBottom-top)
 local at=edge or top
 l.accent=rect4(l.accent,0,at,w,at+(thick or 3))
 l.version=rect4(l.version,w-pad-70,top+1,w-pad,top+11)
 local side=U.clamp(bandH-10,16,w*0.16)
 local fy=top+(bandH-side)*0.5
 l.flag=rect4(l.flag,bar+pad,fy,bar+pad+side,fy+side)
 local textX=l.flag[3]+gap; local right=w-pad
 -- Delta à droite, sous la version, sa largeur suivant la hauteur disponible ; trop bas pour être lisible, aucun.
 if delta then
  local boxH=math.min(bandH-14,58)
  if boxH>=2*K.deltaBoxMin then
   local boxW=U.clamp(boxH*1.9,70,w*0.26)
   local by=top+12+(bandH-12-boxH)*0.5
   l.deltaBox=rect4(l.deltaBox,right-boxW,by,right,by+boxH); l.delta=l.deltaBox; right=right-boxW-gap
  end
 end
 if pills then l.pillsBox=rect4(l.pillsBox,bar+pad,h-pillH-2,w-pad,h-2); l.pills=l.pillsBox end
 -- Sans delta, le titre s'arrête avant la version (même hauteur) ; la consigne, dessous, va jusqu'au bord.
 local titleH=U.clamp(bandH*0.5,13,40)
 local ty=top+math.max(2,(bandH-titleH-math.max(11,bandH*0.32))*0.5)
 l.title=rect4(l.title,textX,ty,l.delta and right or math.min(right,l.version[1]-gap),ty+titleH)
 l.fontTitle=math.max(12,titleH*0.82)
 local detailH=U.clamp(bandH*0.32,11,22)
 if bandBottom-l.title[4]>=detailH*0.8 then l.detailBox=rect4(l.detailBox,textX,l.title[4],right,math.min(bandBottom,l.title[4]+detailH)); l.detail=l.detailBox; l.fontDetail=U.clamp(detailH*0.82,10,17) end
 l.fontPill=math.max(K.pillFontMin,pillH*0.62)
 return l
end
-- Quadrilatère plein (pastilles, coin coupé) ; sans la fonction, rectangle englobant.
local function quad(x1,y1,x2,y2,x3,y3,x4,y4,color)
 if callable(ui.drawQuadFilled) then ui.drawQuadFilled(pv(x1,y1),pv(x2,y2),pv(x3,y3),pv(x4,y4),color)
 else ui.drawRectFilled(pv(math.min(x1,x4),math.min(y1,y2)),pv(math.max(x2,x3),math.max(y3,y4)),color,0) end
end
-- Fond à coin coupé (12 px à l'échelle) en haut à droite.
local function cutBack(x1,y1,x2,y2,cut,color)
 ui.drawRectFilled(pv(x1,y1),pv(x2-cut,y2),color,0)
 ui.drawRectFilled(pv(x2-cut,y1+cut),pv(x2,y2),color,0)
 if callable(ui.drawTriangleFilled) then ui.drawTriangleFilled(pv(x2-cut,y1),pv(x2,y1+cut),pv(x2-cut,y1+cut),color) end
end
-- Badge DRS (jamais un drapeau ; Beta 1.38, maquette) : aplat clair, « DRS » à l'encre, sans cadre ; effacé dès que
-- l'aileron s'ouvre.
local function drsBadge(colors,f)
 ui.drawRectFilled(pv(f[1],f[2]),pv(f[3],f[4]),colors.text,0)
 font('display',true); write('DRS',(f[3]-f[1])*0.36,f,colors.ink,CENTER); font('display',false)
end
-- Numéro de la version proposée dans le drapeau « mise à jour » (« 1.38 »), refait au changement.
local function updateCode(v,version)
 if v.updateCodeFor~=version then v.updateCodeFor=version; v.updateCodeText=(version or ''):gsub('^Beta ','') end
 return v.updateCodeText
end
-- Pastille du compteur d'infractions (avertissement), refaite au changement.
local function infractionText(v,count,max)
 if v.infrFor~=count or v.infrMax~=max then v.infrFor=count; v.infrMax=max; v.infrText=string.format(L.infractionPill,count,max) end
 return v.infrText
end
-- Pastille de lettres (SC, VSC, RS, SS, feux) : fond noir, cadre et lettres jaunes.
local function badge(colors,f,code,edge)
 local p1,p2=pv(f[1],f[2]),pv(f[3],f[4])
 ui.drawRectFilled(p1,p2,colors.ink,0)
 if callable(ui.drawRect) then ui.drawRect(p1,p2,edge,0,nil,math.max(2,(f[3]-f[1])*0.045)) end
 font('display',true); write(code,(f[3]-f[1])*(#code>2 and 0.34 or 0.44),f,edge,CENTER); font('display',false)
end
-- Damier quatre sur quatre (arrivée) ; drapeau de pénalité noir et blanc en diagonale, comme celui d'AC.
local function checker(colors,f)
 local w=(f[3]-f[1])/4; local h=(f[4]-f[2])/4
 for i=0,3 do for j=0,3 do ui.drawRectFilled(pv(f[1]+i*w,f[2]+j*h),pv(f[1]+(i+1)*w,f[2]+(j+1)*h),(i+j)%2==0 and colors.pit or colors.ink,0) end end
end
local function diagonal(colors,f)
 ui.drawRectFilled(pv(f[1],f[2]),pv(f[3],f[4]),colors.pit,0)
 if callable(ui.drawTriangleFilled) then ui.drawTriangleFilled(pv(f[3],f[2]),pv(f[3],f[4]),pv(f[1],f[4]),colors.ink)
 else ui.drawRectFilled(pv((f[1]+f[3])*0.5,(f[2]+f[4])*0.5),pv(f[3],f[4]),colors.ink,0) end
end
-- Voiture endommagée (Beta 1.32) : drapeau noir à disque orange.
local function meatball(colors,f)
 ui.drawRectFilled(pv(f[1],f[2]),pv(f[3],f[4]),colors.ink,0)
 local r=math.min(f[3]-f[1],f[4]-f[2])*0.23
 if r>0 and callable(ui.drawCircleFilled) then ui.drawCircleFilled(pv((f[1]+f[3])*0.5,(f[2]+f[4])*0.5),r,colors.orange,24) end
end
-- Drapeau à bandes jaunes et rouges verticales (piste glissante).
local function stripes(colors,f)
 local n=K.slipperyStripes; local w=(f[3]-f[1])/n
 for k=0,n-1 do ui.drawRectFilled(pv(f[1]+k*w,f[2]),pv(f[1]+(k+1)*w,f[4]),k%2==0 and colors.yellow or colors.red,0) end
end
-- Feux de départ (étape B, Beta 1.34) : K.gridLights disques, allumés en rouge un par un, éteints au départ.
local function startLights(colors,r,lit)
 local n=K.gridLights; local d=math.min((r[3]-r[1])/(n*1.5),(r[4]-r[2])*0.7)
 local gap=d*0.5; local total=n*d+(n-1)*gap
 local x=r[1]+((r[3]-r[1])-total)*0.5+d*0.5; local y=(r[2]+r[4])*0.5
 if not callable(ui.drawCircleFilled) then return end
 for k=1,n do ui.drawCircleFilled(pv(x+(k-1)*(d+gap),y),d*0.5,k<=lit and colors.red or colors.off,24) end
end
-- Texte du delta au centième, virgule décimale, signe toujours affiché ; refait seulement quand la valeur change.
local function deltaText(v,value)
 local hundredths=math.floor(value*100+0.5)
 if hundredths~=v.deltaHundredths then
  v.deltaHundredths=hundredths
  v.deltaText=(string.format('%+.2f',hundredths/100):gsub('%.',L.decimalMark))
  v.deltaPill=string.format(L.deltaPill,v.deltaText)
 end
 return v.deltaText
end
-- Tuile du temps delta : vert positif, rouge négatif (fond clignotant).
local function deltaBox(v,colors,r,value,blink)
 -- Signe lu sur la valeur affichée (au centième) : « +0,00 » n'est jamais rouge.
 local negative=math.floor(value*100+0.5)<0
 ui.drawRectFilled(pv(r[1],r[2]),pv(r[3],r[4]),negative and (blink and colors.overBack or colors.pillBack) or colors.underBack,0)
 if callable(ui.drawRect) then ui.drawRect(pv(r[1],r[2]),pv(r[3],r[4]),negative and colors.over or colors.under,0,nil,1.5) end
 local h=r[4]-r[2]
 font('label',true); write(L.deltaLabel,h*0.16,box(R1,r[1],r[2]+2,r[3],r[2]+h*0.26),negative and colors.overLabel or colors.underLabel,CENTER); font('label',false)
 local text=deltaText(v,value)
 font('mono',true); write(text,math.min(h*0.5,fitSize(text,h*0.5,(r[3]-r[1])*0.92)),box(R2,r[1],r[2]+h*0.22,r[3],r[4]-2),negative and colors.over or colors.under,CENTER); font('mono',false)
end
-- Tuile de la place à rejoindre (départ arrêté, étape B) : libellé, place, distance.
local function placeBox(colors,r,label,value)
 ui.drawRectFilled(pv(r[1],r[2]),pv(r[3],r[4]),colors.pillBack,0)
 if callable(ui.drawRect) then ui.drawRect(pv(r[1],r[2]),pv(r[3],r[4]),colors.yellow,0,nil,1.5) end
 local h=r[4]-r[2]
 font('label',true); write(label,h*0.16,box(R1,r[1],r[2]+2,r[3],r[2]+h*0.26),colors.dim,CENTER); font('label',false)
 font('mono',true); write(value,math.min(h*0.42,fitSize(value,h*0.42,(r[3]-r[1])*0.9)),box(R2,r[1],r[2]+h*0.22,r[3],r[4]-2),colors.yellow,CENTER); font('mono',false)
end
-- Écart de la voiture qui prend un tour (drapeau bleu, Beta 1.39, maquette) : case en parallélogramme à droite du titre,
-- centrée dans la place du delta.
local function blueBox(colors,r,text,u)
 local h=math.min(30*u,r[4]-r[2]); local size=15*u
 font('cond',true)
 local bw=math.min(r[3]-r[1],textWidth(text,size)+size*1.6)
 local y1=r[2]+(r[4]-r[2]-h)*0.5; local x2=r[3]; local x1=x2-bw; local slant=h*0.27
 quad(x1+slant,y1,x2,y1,x2-slant,y1+h,x1,y1+h,colors.blueSide)
 write(text,size,box(R1,x1,y1,x2,y1+h),colors.text,CENTER)
 font('cond',false)
end
-- Pastilles d'état, de gauche à droite (la plus urgente d'abord) : texte réduit pour qu'elles tiennent sur la ligne,
-- jamais sous une taille lisible ; à défaut, les moins urgentes cèdent leur place.
-- Largeur totale des n premières pastilles (fonction du module : aucune fermeture créée à chaque image).
local function pillsWidth(list,n,size) local sum=0; for k=1,n do sum=sum+textWidth(list[k].text,size)+size*1.6+6 end; return sum end
-- blink : moitié des alternances ; une pastille urgente y prend le fond du bandeau (clignotement).
local function pillRow(row,size,list,count,blink,back)
 local width=row[3]-row[1]
 font('cond',true)
 local need=pillsWidth(list,count,size)
 if need>width then size=math.max(K.pillFontMin,size*width/need) end
 while count>1 and pillsWidth(list,count,size)>width do count=count-1 end
 local x=row[1]; local h=row[4]-row[2]; local slant=h*0.27
 for k=1,count do
  local item=list[k]; local w=math.min(textWidth(item.text,size)+size*1.6,row[3]-x)
  if w<size*2 then break end
  local fill=item.blink and not blink and back or item.fill
  if fill then quad(x+slant,row[2],x+w,row[2],x+w-slant,row[4],x,row[4],fill) end
  if item.edge then quad(x+slant,row[2],x+w,row[2],x+w-slant*0.92,row[2]+1.5,x+slant*0.92,row[2]+1.5,item.edge); quad(x+slant*0.08,row[4]-1.5,x+w-slant*1.08,row[4]-1.5,x+w-slant,row[4],x,row[4],item.edge) end
  write(item.text,size,box(R1,x,row[2],x+w,row[4]),item.color,CENTER)
  x=x+w+6
 end
 font('cond',false)
end
local function pill(v,count,text,color,fill,edge,blinking)
 count=count+1; local item=v.pillItems[count]
 if not item then item={}; v.pillItems[count]=item end
 item.text=W.upper(text); item.color=color; item.fill=fill; item.edge=edge; item.blink=blinking==true
 return count
end
-- Textes des pastilles qui changent (secondes restantes, écart) : refaits seulement quand la valeur affichée change.
local function giveBackText(v,name,seconds)
 if name~=v.giveBackName or seconds~=v.giveBackSeconds then v.giveBackName=name; v.giveBackSeconds=seconds; v.giveBackText=string.format(L.giveBack,name,seconds) end
 return v.giveBackText
end
local function blueText(v,gap)
 local tenths=math.floor(gap*10+0.5)
 if tenths~=v.blueTenths then v.blueTenths=tenths; v.blueText=string.format(L.blueGap,(string.format('%.1f',tenths/10):gsub('%.',L.decimalMark))) end
 return v.blueText
end
-- Textes de l'étape B (feux, place à rejoindre), refaits seulement quand ils changent.
local function lightsCode(v,lit)
 if v.lightsLit~=lit then v.lightsLit=lit; v.lightsCodeText=string.format('%d/%d',lit,K.gridLights) end
 return v.lightsCodeText
end
-- Départ arrêté (Beta 1.35) : distance telle que la grille la donne (au mètre sous 20 m, arrondie à 10 m au-delà) ;
-- à sa place (à l'arrêt) : « en place » ; au-delà de sa place : « place dépassée » et sa distance. Textes refaits au
-- changement.
local function placeText(v,slot,distance,placed,passed)
 local meters=distance and math.floor(distance+0.5) or -1
 local state=placed and 1 or passed and 2 or 0
 if v.placeSlot~=slot or v.placeMeters~=meters or v.placeState~=state then
  v.placeSlot=slot; v.placeMeters=meters; v.placeState=state
  v.placeLabel=string.format(L.placeLabel,slot)
  -- Beta 1.36 : place dépassée avec sa distance en arrière quand la grille la donne.
  v.placeValue=state==1 and L.gridPlaced or state==2 and (meters>0 and string.format(L.gridPassedBy,meters) or L.gridPassed) or meters>=0 and string.format(L.placeMeters,meters) or slot
 end
 return v.placeLabel,v.placeValue
end
-- Parties de l'overlay (Beta 1.25), en unités de référence (K.hudWidth de large) : ligne de session en haut, bandeau du
-- drapeau, explication ou récapitulatif de course, pastilles. Table réutilisée ; nil : rien à afficher. force : overlay
-- déverrouillé, toujours visible pour être placé.
local parts={}
-- Annonce de sanction d'une IA (Beta 1.43, maquette) : dans le bandeau seulement quand il est libre (rien d'affiché, ou
-- une simple information : vert, départ, tour, mise à jour) ; sinon le drapeau du joueur garde le bandeau et l'annonce
-- passe sur la ligne de session, comme avant.
local aiFree={green=true,start=true,lap=true,update=true}
function M.overlayParts(v,force)
 local e=v.e; local g=e.g; local panel=e.panel; local now=e.time; local hud=e.hud
 local idle=not Panel.visible(panel,g,now)
 parts.idle=idle
 local ai=g.overlayMessages and hud~=nil and now<hud.aiUntil
 parts.ai=ai and (idle or aiFree[panel.kind]==true) or false
 parts.aiStrip=ai and not parts.ai or false
 parts.message=g.overlayMessages and hud~=nil and (now<hud.msgUntil or ai)
 parts.strip=g.overlaySession and hud~=nil and hud.stripCount>0 or parts.message
 parts.band=not idle or parts.ai or g.panelShow=='always' or force==true
 if not parts.band and not parts.strip then return nil end
 parts.recap=parts.band and not idle and not parts.ai and panel.finish and g.overlayRecap and hud~=nil and #hud.recap>1
 parts.lines=parts.recap and #hud.recap-1 or parts.band and not idle and not parts.ai and g.overlayExplain and panel.explain~='' and 2 or 0
 parts.notice=now<panel.noticeUntil
 parts.giveBack=e.penalties.giveBack>0 and e.frame and e.frame.cars[e.penalties.giveBack] or nil
 parts.pitCall=not idle and panel.kind=='red' and panel.redPit==false
 parts.blueGap=not idle and panel.kind=='blue' and panel.blueGap or nil
 parts.closed=e.incidents.pitsClosed and panel.kind~='red'
 -- Beta 1.38 (maquette) : compteur d'infractions sous l'avertissement, rappel des stands sous la voiture endommagée
 -- et, depuis la Beta 1.39, sous l'arrêt obligatoire.
 parts.infraction=not idle and panel.decided=='warning' and (panel.infractions or 0)>0
 parts.repair=not idle and (panel.kind=='meatball' or panel.kind=='pit')
 parts.pills=parts.band and (not idle and (panel.noPass or panel.drsBlocked) or parts.notice or parts.giveBack~=nil or parts.pitCall or parts.blueGap~=nil and e.delta.value~=nil or parts.closed or parts.infraction or parts.repair) and true or false
 return parts
end
-- Hauteur de l'overlay en unités de référence.
function M.overlayHeight(p)
 local h=K.hudPad
 if p.strip then h=h+K.hudStripH end
 if p.band then h=h+K.hudBandH end
 if p.lines>0 then h=h+p.lines*K.hudExplainLine+6 end
 if p.pills then h=h+K.hudPillH+4 end
 return h
end
-- Ligne de session (bandeau) : libellé discret, valeur en chiffres alignés, de gauche à droite tant qu'il y a
-- la place ; message d'AC à droite (en rouge s'il signale une faute).
local function sessionStrip(v,colors,e,p,y,w,u)
 local hud=e.hud; local pad=K.hudPad*u; local h=K.hudStripH*u
 ui.drawRectFilled(pv(pad,y+2*u),pv(w-pad-12*u,y+h-2*u),v.stripColor,0)
 local x=pad+8*u; local limit=w-pad-20*u
 -- Logo de l'app en tête de la ligne (maquette, Beta 1.38), si l'image et la fonction existent.
 if v.logo and callable(ui.drawImage) then
  local s=20*u; local iy=y+(h-s)*0.5
  pcall(ui.drawImage,v.logo,pv(x-3*u,iy),pv(x-3*u+s,iy+s)); x=x+s+3*u
 end
 if p.message then
  local size=11*u
  -- Beta 1.43 : étiquette de l'annonce d'une IA (jaune) quand le bandeau la montre ; son texte (repli) quand un drapeau
  -- occupe le bandeau ; sinon le message d'AC. Le plus récent des deux l'emporte.
  local now=e.time; local recent=now<hud.msgUntil and hud.msgAt>hud.aiAt
  local text=p.ai and not recent and hud.aiLabel or p.aiStrip and not recent and hud.aiFallback or hud.msgText
  local color=p.ai and not recent and colors.yellow or (not recent and p.aiStrip or not hud.msgIllegal) and colors.amber or colors.over
  font('body',true)
  local mw=math.min(textWidth(text,size),(limit-x)*0.6)
  write(text,size,box(R1,limit-mw,y,limit,y+h),color,FINISH)
  font('body',false)
  limit=limit-mw-14*u
 end
 if not e.g.overlaySession then return end
 -- Largeurs mesurées par police (libellés, puis valeurs), puis dessin : quatre poussées de police en tout.
 local ls,vs=10*u,13*u
 local n=hud.stripCount; local widths=v.stripWidths
 if not widths then widths={}; v.stripWidths=widths end
 font('label',true); for k=1,n do widths[2*k-1]=textWidth(hud.strip[k].label,ls) end; font('label',false)
 font('mono',true); for k=1,n do widths[2*k]=textWidth(hud.strip[k].value,vs) end; font('mono',false)
 local shown=0; local cx=x
 for k=1,n do
  local lw,vw=widths[2*k-1],widths[2*k]
  if cx+lw+5*u+vw>limit then break end
  shown=k; cx=cx+lw+5*u+vw+16*u
 end
 font('label',true); cx=x
 for k=1,shown do local lw,vw=widths[2*k-1],widths[2*k]; write(hud.strip[k].label,ls,box(R1,cx,y,cx+lw+2,y+h),colors.label,START); cx=cx+lw+5*u+vw+16*u end
 font('label',false)
 font('mono',true); cx=x
 for k=1,shown do
  local it=hud.strip[k]; local lw,vw=widths[2*k-1],widths[2*k]
  write(it.value,vs,box(R1,cx+lw+5*u,y,cx+lw+5*u+vw+2,y+h),it.warn and colors.amber or it.best and colors.best or colors.text,START); cx=cx+lw+5*u+vw+16*u
 end
 font('mono',false)
end
-- Contenu de l'overlay (Beta 1.25, refonte Racing 26) : fond à coin coupé à l'opacité réglée (opaque, atténué ou
-- transparent), bande d'accent, ligne de session, bandeau du drapeau (drapeau, titre, consigne, delta ou place),
-- explication de ce qui se passe ou récapitulatif de course, pastilles ; tout à l'échelle de la largeur. Renvoie la
-- hauteur dessinée (pixels).
local function flags(v,force)
 local e=v.e; local panel=e.panel; local g=e.g; local now=e.time
 local p=M.overlayParts(v,force)
 if not p then return 0 end
 local alpha=(g.overlayContent or 100)/100
 local colors=panelPalette(alpha)
 if not colors then ui.text(p.idle and L.flagTitles.clear or panel.title); ui.text(p.idle and '' or panel.short); return 0 end
 v.pillItems=v.pillItems or {}
 local size=ui.windowSize(); local start=ui.getCursor()
 local w=size.x; local u=w/K.hudWidth; local top=math.max(0,start.y)
 local idle=p.idle and not p.ai; local kind=p.ai and 'ai' or idle and 'clear' or panel.kind
 local hud=e.hud
 local delta=not p.ai and e.delta.value or nil
 -- Fond : opacité réglée, atténuée ou nulle ; couleurs refaites seulement quand elles changent.
 local mode=g.overlayBackground
 local bgAlpha=mode=='transparent' and 0 or g.panelOpacity/100*(mode=='ghost' and K.hudGhost or 1)
 if v.backAlpha~=bgAlpha or v.stripAlpha~=alpha then
  v.backAlpha=bgAlpha; v.stripAlpha=alpha
  v.backColor=rgbm(0.075,0.078,0.082,bgAlpha); v.stripColor=rgbm(0,0,0,0.5*math.max(bgAlpha,0.5)*alpha)
 end
 local back=v.backColor
 -- Mise à jour (Beta 1.38, maquette) : fond teinté de cyan, au moins à 90 %.
 if kind=='update' then
  if v.updateBackFor~=bgAlpha then v.updateBackFor=bgAlpha; v.updateBack=rgbm(0.024,0.133,0.176,math.max(bgAlpha,0.9)) end
  back=v.updateBack
 end
 local height=M.overlayHeight(p)*u
 if bgAlpha>0 or kind=='update' then cutBack(0,top,w,top+height,12*u,back) end
 local y=top+K.hudPad*0.5*u
 if p.strip then sessionStrip(v,colors,e,p,y,w,u); y=y+K.hudStripH*u end
 if not p.band then v.drawnHeight=height; return height end
 local bandTop=y
 -- Beta 1.48 : case « REPRISE » (place de l'ordre figé au drapeau rouge) aux stands.
 local restartBox=not idle and not (kind=='standing' and panel.slotText~=nil) and panel.restartBox or nil
 local place=not idle and (kind=='standing' and panel.slotText~=nil or restartBox~=nil)
 local blueSide=not idle and kind=='blue' and panel.blueGap or nil
 local boxed=delta~=nil or place or blueSide~=nil
 v.flagBoxes=v.flagBoxes or {}
 local l=M.flagLayout(w,y+K.hudBandH*u,y,boxed,false,top,3*u,v.flagBoxes)
 -- Clignotement à K.hudBlinkHz Hz : rouge et bleu tout le temps, tout nouveau drapeau quelques secondes.
 local blink=(now*K.hudBlinkHz)%1<0.5
 local flashing=not idle and (kind=='red' or kind=='blue' or kind=='jump' or now-(kind=='ai' and hud.aiAt or panel.changedAt)<K.flagBlinkTime)
 local flagColor=kind=='drs' and colors.text or kind=='clear' and colors.dim or colors[flagColors[kind] or 'yellow']
 local shown=flashing and not blink and back or flagColor
 local dark=kind=='black' or kind=='penalty' or kind=='checkered' or kind=='warning' or kind=='ai' and hud.aiBlack
 local accent=dark and (flashing and not blink and back or colors.text) or shown
 -- Bande d'accent (3 px à l'échelle, couleur du drapeau) tout en haut de l'overlay, jusqu'au coin coupé, sous les textes.
 local a=l.accent
 ui.drawRectFilled(pv(a[1],a[2]),pv(math.max(1,a[3]-12*u),a[4]),accent,0)
 local f=l.flag
 local code=badgeCodes[kind] or kind=='lights' and lightsCode(v,panel.lit or 0) or kind=='ai' and not hud.aiBlack and hud.aiCode or nil
 if kind=='clear' then if callable(ui.drawRect) then ui.drawRect(pv(f[1],f[2]),pv(f[3],f[4]),colors.dim,0,nil,2) end
 elseif kind=='drs' then drsBadge(colors,f)
 elseif code then badge(colors,f,code,flashing and not blink and colors.off or colors.yellow)
 elseif kind=='slippery' then stripes(colors,f)
 elseif kind=='checkered' then checker(colors,f)
 elseif kind=='penalty' or kind=='warning' then diagonal(colors,f)
 elseif kind=='meatball' then meatball(colors,f)
 elseif kind=='black' or kind=='ai' then
  -- Drapeau noir, aussi pour l'annonce du drapeau noir d'une IA (maquette : noir, bord blanc, sans sigle).
  ui.drawRectFilled(pv(f[1],f[2]),pv(f[3],f[4]),colors.ink,0)
  if callable(ui.drawRect) then ui.drawRect(pv(f[1],f[2]),pv(f[3],f[4]),accent,0,nil,2) end
 else
  ui.drawRectFilled(pv(f[1],f[2]),pv(f[3],f[4]),shown,0)
  local sigle=kind=='lap' and panel.lapCode or kind=='yellow' and panel.double and '!!' or kind=='update' and updateCode(v,panel.updateVersion) or flagCodes[kind]
  if sigle and sigle~='' then font('display',true); write(sigle,(f[3]-f[1])*(#sigle>2 and 0.34 or #sigle>1 and 0.44 or 0.6),f,(kind=='red' or kind=='blue') and colors.text or colors.ink,CENTER); font('display',false) end
 end
 if place and l.delta and restartBox then placeBox(colors,l.delta,L.restart.box,restartBox)
 elseif place and l.delta then local label,value=placeText(v,panel.slotText,panel.slotDistance,panel.slotPlaced,panel.slotPassed); placeBox(colors,l.delta,label,value)
 elseif delta and l.delta then deltaBox(v,colors,l.delta,delta,blink) elseif delta then deltaText(v,delta)
 elseif blueSide and l.delta then blueBox(colors,l.delta,W.upper(blueText(v,blueSide)),u) end
 local title=kind=='ai' and hud.aiTitle or idle and L.flagTitles.clear or panel.title
 local short=kind=='ai' and hud.aiShort or idle and L.flagShort.clear or panel.short
 font('display',true); write(title,fitSize(title,l.fontTitle,l.title[3]-l.title[1]),l.title,idle and colors.dim or colors.text,START); font('display',false)
 -- Feux de départ (étape B) : à droite du titre, à la place du delta.
 if not idle and (kind=='lights' or kind=='go' or kind=='jump') and not l.delta then
  local r=box(LIGHTS,l.title[3]-math.min(150*u,(l.title[3]-l.title[1])*0.45),l.title[2],l.title[3],l.title[4])
  startLights(colors,r,kind=='lights' and (panel.lit or 0) or 0)
 end
 if l.detail then font('body',true); write(short,fitSize(short,l.fontDetail,l.detail[3]-l.detail[1]),l.detail,kind=='lap' and panel.lapRecord and colors.best or kind~='ai' and panel.finish and colors.text or colors.dim,START); font('body',false) end
 y=bandTop+K.hudBandH*u
 -- Explication de ce qui se passe, ou récapitulatif de course (une ligne par élément), alignées sur le titre.
 if p.lines>0 then
  local x1=l.title[1]; local right=w-K.hudPad*u; local lineH=K.hudExplainLine*u
  if p.recap then
   local hud=e.hud
   font('body',true)
   for k=2,#hud.recap do write(hud.recap[k],12*u,box(R1,x1,y,right,y+lineH),k==2 and colors.text or colors.dim,START); y=y+lineH end
   font('body',false)
  else
   font('body',true); write(panel.explain,11.5*u,box(R1,x1,y,right,y+2*lineH),colors.dim,START,true); font('body',false); y=y+2*lineH
  end
  y=y+6*u
 end
 if p.pills then
  local row=box(ROW,l.flag[1],y,w-K.hudPad*u,y+K.hudPillH*u)
  local count=0
  if p.notice then count=pill(v,count,panel.notice,colors.text,colors.overBack,colors.over,true) end
  local giveBack=p.giveBack
  if giveBack then count=pill(v,count,giveBackText(v,giveBack.name~='' and giveBack.name or giveBack.id,math.max(0,math.ceil(e.penalties.giveBackUntil-now))),colors.amber,colors.amberBack,colors.amber,true) end
  if delta and not l.delta then
   local late=math.floor(delta*100+0.5)<0
   count=pill(v,count,v.deltaPill,late and colors.over or colors.under,late and colors.overBack or colors.underBack,nil,late)
  end
  if p.pitCall then count=pill(v,count,L.pitPill,colors.ink,colors.pit,nil,true) end
  if p.blueGap and delta then count=pill(v,count,blueText(v,p.blueGap),colors.text,colors.blue,nil,false) end
  if p.closed then count=pill(v,count,L.pitClosedPill,colors.ink,colors.amber,nil,false) end
  if p.infraction then count=pill(v,count,infractionText(v,panel.infractions,panel.infractionMax),colors.ink,colors.amber,nil,false) end
  if p.repair then count=pill(v,count,L.pitPill,colors.ink,colors.pit,nil,false) end
  if panel.noPass and not idle then
   if panel.passed then count=pill(v,count,panel.passBad,colors.ink,colors.over,nil,true)
   else count=pill(v,count,panel.passOk,colors.under,colors.underBack,nil,false) end
  end
  -- Beta 1.48 : place de la reprise tenue (verte) ou à reprendre (ambre, dépassement permis).
  if panel.restartPill and not idle then
   if panel.restartRetake then count=pill(v,count,panel.restartPill,colors.ink,colors.amber,nil,false)
   else count=pill(v,count,panel.restartPill,colors.under,colors.underBack,nil,false) end
  end
  if panel.drsBlocked and not idle then count=pill(v,count,panel.drsText,colors.over,colors.overBack,nil,false) end
  pillRow(row,math.max(K.pillFontMin,K.hudPillH*u*0.58),v.pillItems,count,blink,back)
  y=y+K.hudPillH*u+4*u
 end
 v.drawnHeight=height
 return height
end
-- Contenu de l'overlay, polices dépilées en fin de dessin, même après une erreur (renvoyée ensuite).
function M.flags(v,force)
 local ok,result=pcall(flags,v,force)
 fontRelease()
 if not ok then error(result,0) end
 return result
end
-- Case de session d'AC (tour, temps restant, RACE OVER), masquée tant que la ligne de session de l'overlay la
-- remplace ; rendue dès que ce n'est plus le cas (réglage coupé, overlay masqué, déchargement).
local function nativeBox(v,hide)
 if v.sessionBoxHidden==hide then return end
 if Adapter.sessionBox(hide) then v.sessionBoxHidden=hide end
end
function M.restoreNative(v) if v.sessionBoxHidden then nativeBox(v,false) end end
local function screenSize() return Adapter.screen() or vec2(1920,1080) end
-- Contenu de la fenêtre transparente, puis, déverrouillée : glisser pour déplacer, coin bas droit pour la taille,
-- clic droit pour verrouiller ; verrouillée sans clics traversants : clic droit pour déverrouiller.
local function hudContent(v)
 local g=v.e.g
 M.flags(v,not g.overlayLocked)
 local w,h=v.hudW,v.hudH
 if not g.overlayLocked then
  local hw=K.hudHandle*g.overlayScale
  ui.setCursor(vec2(0,0)); ui.invisibleButton('##aai_overlay_move',vec2(w,math.max(1,h-hw)))
  local moving=ui.itemActive()
  local lock=ui.itemHovered() and ui.mouseClicked(1)
  ui.setCursor(vec2(0,math.max(0,h-hw))); ui.invisibleButton('##aai_overlay_move2',vec2(math.max(1,w-hw),hw))
  moving=moving or ui.itemActive()
  lock=lock or ui.itemHovered() and ui.mouseClicked(1)
  ui.setCursor(vec2(math.max(0,w-hw),math.max(0,h-hw))); ui.invisibleButton('##aai_overlay_size',vec2(hw,hw))
  local sizing=ui.itemActive()
  if moving or sizing then
   local d=ui.mouseDelta()
   if moving then g.overlayX=v.hudX+d.x; g.overlayY=v.hudY+d.y end
   if sizing then
    local k=math.abs(d.x)>=math.abs(d.y) and d.x/w or d.y/h
    local bounds=C.globalBounds.overlayScale
    g.overlayScale=U.clamp(g.overlayScale*(1+k),bounds[1],bounds[2]); g.overlayX=v.hudX; g.overlayY=v.hudY
   end
   v.hudMoved=true
  elseif v.hudMoved then v.hudMoved=false; C.validateGlobals(g,g); v.dirty() end
  if lock then g.overlayLocked=true; v.dirty() end
  -- Décor déverrouillé : cadre et poignée de taille cyan, consigne en capitales.
  local c=W.colors()
  if callable(ui.drawRect) then ui.drawRect(vec2(0,0),vec2(w,h),c.cyan,0,nil,1.5) end
  if callable(ui.drawTriangleFilled) then ui.drawTriangleFilled(vec2(w,h-hw),vec2(w,h),vec2(w-hw,h),c.cyan) end
  font('cond',true); write(L.hudUnlocked,10*g.overlayScale,box(R1,0,h-hw,math.max(1,w-hw-4),h),c.cyan,FINISH); font('cond',false)
 elseif callable(ui.windowHovered) and ui.windowHovered() and ui.mouseClicked(1) then g.overlayLocked=false; v.dirty() end
end
-- Overlay en jeu (Beta 1.25) : fenêtre transparente dessinée par l'app (rappel IN_GAME du
-- manifeste), à la position et à l'échelle réglées (position automatique : centrée, en haut), gardée dans l'écran ;
-- masquée en rediffusion ou aux stands si réglé. Clics traversants une fois verrouillée (réglage).
function M.hud(v)
 local e=v.e; local g=e.g
 -- Bandeau « en ligne » masqué par « Compris » : remis dès que la garde change, fenêtre fermée comprise.
 if v.bannerHide and v.bannerHide~=guardId(e) then v.bannerHide=nil end
 fontsOnce(v)
 if not callable(ui.transparentWindow) then nativeBox(v,false); return end
 local frame=e.frame; local player=frame and frame.player>0 and frame.cars[frame.player] or nil
 local hidden=not frame or frame.replay and g.overlayHideReplay or g.overlayHidePits and player~=nil and player.pit
 local unlocked=not g.overlayLocked
 local p=not hidden and M.overlayParts(v,unlocked) or nil
 nativeBox(v,not hidden and g.overlayNativeBox and g.overlaySession)
 if not p then return end
 local s=g.overlayScale; local w=K.hudWidth*s; local h=M.overlayHeight(p)*s
 local screen=screenSize()
 local x=g.overlayX>=0 and g.overlayX or (screen.x-w)*0.5
 local y=g.overlayY>=0 and g.overlayY or screen.y*K.hudTop
 x=U.clamp(x,0,math.max(0,screen.x-w)); y=U.clamp(y,0,math.max(0,screen.y-h))
 v.hudX=x; v.hudY=y; v.hudW=w; v.hudH=h
 -- Polices dépilées dans la fenêtre qui les a poussées, même après une erreur (renvoyée ensuite).
 if not v.hudDraw then v.hudDraw=function() local ok,err=pcall(hudContent,v); fontRelease(); if not ok then error(err,0) end end end
 -- Position et taille gardées d'une image à l'autre (Beta 1.36 : aucun point créé à chaque image).
 if v.hudPos then v.hudPos.x=x; v.hudPos.y=y; v.hudSize.x=w; v.hudSize.y=h else v.hudPos=vec2(x,y); v.hudSize=vec2(w,h) end
 ui.transparentWindow('AdvancedIA_overlay',v.hudPos,v.hudSize,true,unlocked or not g.overlayClickThrough,v.hudDraw)
end
return M
