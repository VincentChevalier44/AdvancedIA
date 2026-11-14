-- Affinage 1.63 (décision du pilote du 13 novembre, questionnaire : « jaune d'avertissement seul ») : voiture lente tenue
-- au bord devant le joueur : drapeau jaune d'avertissement (panneau, panneaux lumineux, champ yellow du pont), sans
-- limite de vitesse, delta, interdiction de doubler, pénalité ni zone. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Lights=require('src/lights')
local B=require('src/bridge')
local K=C.K
local tests={}
local function logged(e,text) for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then return true end end return false end
local function learned(e,first,last,speed)
 for i=first,last do
  local s=e.states[i]; s.paceCount=e.delta.bins
  for b=1,e.delta.bins do s.pace[b]=speed end
  s.longRatio=1; s.longRatioTime=K.longRatioMin
 end
end
-- Joueur (voiture 1) gap m derrière une IA anormalement lente (voiture 2, 40 km/h, sa classe à 200).
local function scene(sign,gap,frames)
 local e,f=F.scene('C',4); e.g.offsetSign=sign; e.g.sideSign=sign; e.startedAt=-100; e.p.personalLineJitter=0; E.changed(e)
 f.length=60611; F.tick(e,f,1/60)
 learned(e,2,4,200/3.6)
 for _=1,frames do
  F.place(f,2,1000,40); F.place(f,1,1000-gap,200); F.place(f,3,-10000,200); F.place(f,4,30000,200)
  F.tick(e,f,1/60)
 end
 return e,f
end
tests.LOCK_SLOW_WARN_YELLOW_163=function()
 for _,sign in ipairs({1,-1}) do
  local e,f=scene(sign,300,(K.slowObstacleTime+4)*60)
  local t=e.incidents
  assert(e.states[2].edgePin,'slow car pinned to the edge ('..sign..')')
  assert(t.playerWarn and t.playerWarnSlot==2,'warning yellow for the player ('..sign..')')
  -- Aucune règle : ni zone, ni interdiction de doubler, ni limite, ni delta, ni neutralisation.
  assert(t.zoneCount==0 and not t.playerZone and not t.playerNoPass and not t.playerInside and not t.neutral and not t.red,'no zone, no rule ('..sign..')')
  assert(not t.playerYellow,'not a real yellow zone ('..sign..')')
  for i=1,4 do local cmd=e.commands[i]; assert((cmd.yellowLimit or K.unlimitedSpeed)>=K.unlimitedSpeed,'no speed limit for car '..i) end
  assert(not e.states[3].yellow and not e.states[4].yellow,'AI not under a yellow')
  assert(not (e.delta.zone and e.delta.zone.on),'no delta')
  -- Affichage : panneau, panneaux lumineux, pont.
  assert(e.panel.kind=='slowWarn','overlay panel: '..tostring(e.panel.kind))
  local flag,why=Lights.decide(e.lights,t,f,e.run,e.profile,e.time)
  assert(flag==K.flagCaution and why=='voiture lente au bord','track light panels yellow: '..tostring(why))
  assert(logged(e,'jaune d avertissement'),'logged')
  local out={cars={}}; for k=0,B.layout.maxCars-1 do out.cars[k]={} end
  B.publish(B.new('test'),out,e,f)
  assert(out.yellow==true and out.noPass==false and out.zone==false and out.neutral==false,'bridge: yellow only (no pass ban, no zone)')
 end
 -- Sens latéral inconnu : la voiture lente n'est pas tenue au bord, donc pas d'avertissement (seule une voiture rangée
 -- au bord en porte un).
 local unknown=scene(0,300,(K.slowObstacleTime+4)*60)
 assert(unknown.states[2].abnormal and not unknown.states[2].edgePin and not unknown.incidents.playerWarn,'not pinned: no warning')
 -- Trop loin devant : rien.
 local far=scene(1,1500,(K.slowObstacleTime+4)*60)
 assert(not far.incidents.playerWarn,'too far ahead: no warning')
 -- Allure retrouvée : l'avertissement s'arrête.
 local e,f=scene(1,300,(K.slowObstacleTime+4)*60)
 for _=1,(K.slowEnd+2)*60 do F.place(f,2,1000,200); F.place(f,1,700,200); F.tick(e,f,1/60) end
 assert(not e.incidents.playerWarn,'normal pace again: warning over')
end
return tests
