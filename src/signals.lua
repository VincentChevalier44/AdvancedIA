-- Beta 1.64 (décision du pilote du 14 novembre) : clignotants des IA. CSP n'a pas de fonction de clignotants par voiture,
-- mais ac.setTurningLights agit sur la « voiture cible » (ac.setTargetCar) : l'applicateur choisit l'IA, commande ses
-- clignotants, puis rend aussitôt la cible au joueur. Le SDK prévient que l'effet sur une IA peut être annulé quelques
-- images plus tard : la commande est renvoyée à chaque image tant qu'une IA clignote, et une seule fois pour l'éteindre.
-- Quand : IA qui s'écarte ou se tient à l'écart pour laisser passer (journée circuit, essais, qualifications ; en course,
-- seulement au drapeau bleu ou pour une classe plus rapide), du côté où elle va ; IA anormalement lente tenue au bord :
-- feux de détresse. Jamais pendant une attaque ou une défense, jamais pour le joueur. Le côté passe par le sens latéral
-- mesuré (aucun clignotant tant qu'il est inconnu). Certaines voitures n'ont pas de clignotants, ou les ont inversés dans
-- leur modèle : rien à y faire depuis une app.
local K=require('src/config').K
local M={NONE=0,LEFT=1,RIGHT=2,HAZARDS=3}
local yielding={YIELD_IN=true,YIELD_HOLD=true}
-- Mode voulu pour une voiture (pur) : s état du directeur, offset décalage commandé, sign sens latéral mesuré.
function M.mode(s,offset,sign,profile,player)
 if player or not s then return M.NONE end
 if s.edgePin then return M.HAZARDS end
 if sign==0 or not yielding[s.state] then return M.NONE end
 if profile=='C' and not (s.yieldBlue or s.yieldClass) then return M.NONE end
 local o=offset or 0
 if math.abs(o)<K.signalMinOffset then return M.NONE end
 return o*sign>0 and M.RIGHT or M.LEFT
end
-- Moteur, fin d'image : cmd.signal de chaque voiture (0 si le réglage est coupé ou l'app hors service).
function M.decide(e,frame)
 local on=e.p and e.p.aiTurnSignals==true
 local sign=e.g and e.g.offsetSign or 0
 local active=0
 for i=1,K.maxCars do
  local cmd=e.commands[i]
  if on and i<=frame.count then
   local a=frame.cars[i]
   local m=(a.valid and a.control and not a.pit) and M.mode(e.states[i],cmd.offset,sign,e.profile,a.player) or M.NONE
   cmd.signal=m
   if m~=M.NONE then active=active+1 end
  else cmd.signal=M.NONE end
 end
 return active
end
-- Applicateur : commande envoyée à chaque image tant qu'une IA clignote, une fois pour l'éteindre ; la cible est rendue
-- au joueur (index AC, 0 sans joueur) dans le même appel (write du port).
local function noteOnce(a,frame,commands,cap)
 local key=a.sessionToken or 'session'
 if a.signalsNoted==key then return end
 local wanted=false
 for i=1,frame.count do if (commands[i].signal or M.NONE)~=M.NONE then wanted=true; break end end
 if not wanted then return end
 a.signalsNoted=key
 if a.note then a.note('INFO',(cap and cap.available) and 'clignotants des IA: actifs' or 'clignotants des IA: indisponibles (CSP sans voiture cible ni clignotants)',-1) end
end
function M.write(a,frame,commands,Caps)
 local cap=a.caps.turnSignals
 noteOnce(a,frame,commands,cap)
 if not cap or not cap.available then return 0 end
 local back=(frame.player or 0)>0 and frame.cars[frame.player] and frame.cars[frame.player].index or 0
 local sent=0
 for i=1,frame.count do
  local car=frame.cars[i]; local c=a.cars[i]; local want=commands[i].signal or M.NONE
  if car.player then want=M.NONE end
  local had=c.signal or M.NONE
  if want~=M.NONE or had~=M.NONE then
   if car.valid and Caps.call(a.caps,'turnSignals',car.index,want,back) then sent=sent+1 end
   c.signal=want
  end
 end
 return sent
end
-- Restitution (app coupée, déchargée, panique) : clignotants éteints sur chaque IA qui clignotait.
function M.release(a,frame,Caps)
 local cap=a.caps.turnSignals
 if not cap then return end
 local back=frame and (frame.player or 0)>0 and frame.cars and frame.cars[frame.player] and frame.cars[frame.player].index or 0
 for i=1,K.maxCars do
  local c=a.cars[i]
  if (c.signal or M.NONE)~=M.NONE then
   local car=frame and frame.cars and frame.cars[i]
   if car and car.valid then Caps.restoreCall(a.caps,'turnSignals',car.index,M.NONE,back) end
   c.signal=M.NONE
  end
 end
end
return M
