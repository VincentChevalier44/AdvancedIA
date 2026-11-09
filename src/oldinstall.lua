-- Beta 1.49 : l'app s'appelle AdvancedIA (dossier apps/lua/AdvancedIA). Une ancienne version restée dans
-- apps/lua/ACAdvancedIA (son manifeste ; un dossier vide est sans effet) est chargée aussi par CSP et pilote les IA :
-- les deux apps ne doivent jamais commander ensemble. Cette app ne commande alors rien (IA, drapeaux, options de CSP,
-- AI flood, pont, mise à jour) et affiche seulement la consigne, dans sa fenêtre et sur l'écran de conduite, en
-- français et en anglais (aucun réglage n'est lu) ; une ligne au journal et au journal de CSP.
local M={}
M.folder='ACAdvancedIA'
M.textFr='L\'ancienne version ACAdvancedIA est encore installée (apps/lua/ACAdvancedIA) : fermez le jeu, supprimez ce dossier, puis relancez. Les deux apps ne doivent jamais tourner ensemble.'
M.textEn='The old ACAdvancedIA version is still installed (apps/lua/ACAdvancedIA): close the game, delete that folder, then restart. The two apps must never run together.'
M.journalText='ancienne version ACAdvancedIA encore installee (apps/lua/ACAdvancedIA/manifest.ini) : app inerte, rien n est commande'
local amber,back=nil,nil
local function colors()
 if not amber then amber=rgbm(1,0.62,0.1,1); back=rgbm(0.04,0.043,0.055,0.94) end
end
function M.window(release)
 colors()
 local size=ui.windowSize()
 ui.drawRectFilled(vec2(0,0),vec2(size.x,size.y),back)
 ui.drawRectFilled(vec2(0,0),vec2(size.x,4),amber)
 ui.setCursor(vec2(20,20)); ui.textColored('AdvancedIA '..tostring(release),amber)
 ui.setCursor(vec2(20,48)); ui.textWrapped(M.textFr)
 ui.setCursor(vec2(20,112)); ui.textWrapped(M.textEn)
end
function M.overlay()
 colors()
 local screen=ac.getUI().windowSize
 local w=math.max(320,math.min(760,screen.x-40)); local h=110
 ui.transparentWindow('AdvancedIA_overlay',vec2((screen.x-w)/2,60),vec2(w,h),true,false,function()
  ui.drawRectFilled(vec2(0,0),vec2(w,h),back)
  ui.drawRectFilled(vec2(0,0),vec2(6,h),amber)
  ui.setCursor(vec2(18,10)); ui.textWrapped(M.textFr)
  ui.setCursor(vec2(18,60)); ui.textWrapped(M.textEn)
 end)
end
-- Beta 1.52 : copie laissée par la mise à jour de l'ancienne version (cfg/extension/state/<oldWork>), effacée une fois
-- celle-ci désinstallée (Applier.oldWorkLeftover, appelé par AdvancedIA.lua).
M.oldWork='ACAdvancedIA-update'
-- Tout l'état de l'app inerte : journal (une ligne), puis rappels de l'interface protégés (une erreur n'arrête rien).
function M.run(script,Applier,release)
 local host={}
 pcall(function()
  if Applier.journalOpen(host) then
   local clock=Applier.clockText()
   Applier.journalWrite(host,'=== AdvancedIA '..tostring(release)..' : lancement '..clock..' ===\n'..clock..string.format(' %9.1f %-5s %3d %s\n',0,'WARN',-1,M.journalText))
  end
 end)
 pcall(function() if ac and type(ac.log)=='function' then ac.log('AdvancedIA: '..M.textEn) end end)
 local function none() end
 script.update=none; script.HUMANAI__UPDATE=none; script.HUMANAI__MENU=none
 script.HUMANAI__MAIN=function() pcall(M.window,release) end
 script.HUMANAI__HUD=function() pcall(M.overlay) end
 M.active=true
end
return M
