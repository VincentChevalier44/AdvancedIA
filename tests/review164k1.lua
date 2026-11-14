-- Affinage 1.64 k1 (Monza S16, 14 novembre) : (A) Levratti et Courtois, accidentés à la Parabolique (314,9 s), ramenés
-- aux stands par AC à 330,7 s entre deux essais de redémarrage de l'app, puis abandonnés à leur emplacement (« bloqués sur
-- le frein ») ; (B) fin de peloton au premier freinage du premier tour : Kruuda à 9 m, 43 km/h plus vite, suiveur à 7 m,
-- garde à 0,8 s puis levée seule : chocs à 24 et 13 km/h. Noms LOCK_*_164 (tests/LOCKS.md). Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local K=C.K
local tests={}

tests.K_164K1=function()
 assert(K.rejoinNoRetire==true and K.rejoinNoRetireMax==60 and K.flTailSa==30 and K.recoverRetire==true)
end

-- (A) IA arrêtée en piste après un incident (hors premier tour) : protégée du renvoi d'AC tant qu'elle n'est pas jugée
-- incapable de rouler ; jamais aux stands ; jamais au-delà de K.rejoinNoRetireMax s d'immobilité.
tests.LOCK_CRASHED_NO_RETIRE_164=function()
 local e,f=F.scene('C',3); F.place(f,1,-4000,120); F.place(f,2,-3000,200); F.place(f,3,5166,0); F.tick(e,f,3)
 local c=e.incidents.cars[3]
 assert(c.incident,'scene: crashed car stopped on track')
 F.place(f,3,5166,0); F.tick(e,f,0.5)
 assert(e.commands[3].noRetire==true,'crashed car kept from AC send-to-pits while it may restart')
 assert(e.commands[2].noRetire~=true,'a running car is not concerned')
 -- Jugée incapable de rouler : protection levée (dépannage de l'app comme avant).
 c.cannot='ne repart pas apres 3 essai(s)'; F.place(f,3,5166,0); F.tick(e,f,1/60)
 assert(e.commands[3].noRetire~=true,'cannot drive any more: no protection')
 c.cannot=nil
 -- Aux stands : jamais.
 f.cars[3].pit=true; F.place(f,3,5166,0); f.cars[3].pit=true; F.tick(e,f,1/60)
 assert(e.commands[3].noRetire~=true,'in the pit lane: no protection'); f.cars[3].pit=false
 -- Borne : au-delà de K.rejoinNoRetireMax s d'immobilité, plus de protection (borne réduite le temps du test).
 local max=K.rejoinNoRetireMax
 local okb,errb=pcall(function()
  local g,h=F.scene('C',3); F.place(h,1,-4000,120); F.place(h,2,-3000,200); F.place(h,3,5166,0); F.tick(g,h,3)
  local d=g.incidents.cars[3]; K.rejoinNoRetireMax=(d.still or 0)+1
  for _=1,4 do d.cannot=nil; F.place(h,3,5166,0); F.tick(g,h,0.5) end
  assert(d.incident and not d.cannot,'scene: still a crashed car')
  assert(g.commands[3].noRetire~=true,'bounded at K.rejoinNoRetireMax s')
 end)
 K.rejoinNoRetireMax=max; assert(okb,errb)
 -- Coupée : comportement d'avant.
 local old=K.rejoinNoRetire; K.rejoinNoRetire=false
 local ok,err=pcall(function()
  local g,h=F.scene('C',3); F.place(h,1,-4000,120); F.place(h,2,-3000,200); F.place(h,3,5166,0); F.tick(g,h,3); F.place(h,3,5166,0); F.tick(g,h,0.5)
  assert(g.commands[3].noRetire~=true,'rule off: as before')
 end)
 K.rejoinNoRetire=old; assert(ok,err)
end

local function scene(sign)
 local e,f=F.scene('C',4); e.g.offsetSign=sign; e.g.sideSign=sign
 local p=e.profiles.C; p.startDelay=0; p.startRelax=0; p.personalLineJitter=0
 E.changed(e)
 for i=1,f.count do f.cars[i].sideDot=sign end
 return e,f
end
-- (B) Premier tour, zone de freinage : voiture devant ralentie, rapprochement de 43 km/h à `gap` m, suiveur à 7 m.
local function tail(sign,gap,sa)
 local e,f=scene(sign)
 F.place(f,1,-5000,100)
 local function put()
  F.place(f,4,-7-4.4,145,0); F.place(f,2,0,145,0); F.place(f,3,gap+4.4,145-sa,0)
  for i=2,4 do f.cars[i].yawRate=0.25; f.cars[i].brake=0.6 end
 end
 put(); f.started=true; F.tick(e,f,0.1)
 local s=e.states[2]; local first=nil
 for n=1,20 do put(); s.flW=1; s.flOn=true; s.flAge=0; s.flLap=f.cars[2].lap or 0; s.flSpread=0; e.fl.on=true; s.nextPerception=0; F.tick(e,f,1/60)
  local acted=(e.stats.flLift or 0)+(e.stats.flBrake or 0)+(e.stats.flZoneBrake or 0)+(e.startLift or 0); if not first and acted>0 then first=n end end
 return first or 99,e
end
local function ref(sign,gap,sa)
 local old=K.flTailSa; K.flTailSa=1000
 local ok,v=pcall(tail,sign,gap,sa)
 K.flTailSa=old; assert(ok,v); return v
end
tests.LOCK_LAP1_TAIL_BRAKE_164=function()
 for _,sign in ipairs({-1,1}) do
  -- S16 : 12 m, 43 km/h plus vite (1,0 s), zone de freinage, suiveur à 7 m : réaction au seuil ordinaire (avant : rien
  -- avant 0,8 s, la levée venait trop tard : chocs à 24 et 13 km/h).
  local now,old=tail(sign,12,43),ref(sign,12,43)
  assert(now<99 and old==99,sign..': radar reacts at 1.0 s on a fast approach (before: not before 0.8 s) ('..now..' vs '..old..')')
  -- Même gestes qu'avant une fois dans la garde (9 m, 0,75 s) : réaction présente dans les deux cas.
  assert(tail(sign,9,43)<99 and ref(sign,9,43)<99,sign..': within the guard: reacts as before')
  -- Rapprochement modéré (25 km/h à 7 m) : premier tour inchangé.
  assert(tail(sign,7,25)==ref(sign,7,25),sign..': moderate approach unchanged')
 end
end

-- Décision du pilote (14 novembre) : en course, IA dépannée hors drapeau rouge (ici moteur cassé, immobile en piste à la
-- Parabolique, 5166 m) : abandon, garée à son stand jusqu'à la fin, journal ; essais : comportement d'avant.
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function broken(profile)
 local e,f=F.scene(profile,3); F.place(f,1,-4000,120); F.place(f,2,-3000,200); F.place(f,3,5166,0); f.cars[3].engineLife=0
 local recovered=false
 for _=1,40 do F.place(f,3,5166,0); f.cars[3].engineLife=0; F.tick(e,f,0.25); if e.commands[3].recover then recovered=true; break end end
 return e,f,recovered
end
tests.LOCK_RECOVERED_RETIRE_164=function()
 local e,f,rec=broken('C')
 assert(rec and e.commands[3].recoverReason=='cassee','scene: broken car recovered ('..tostring(e.commands[3].recoverReason)..')')
 assert(e.states[3].retirePending=='cassee','race: retirement pending until it reaches its pit box')
 -- Arrivée à son stand (déplacement d'AC) : abandon, garée, une ligne.
 f.cars[3].pit=true; f.cars[3].inPitBox=true; F.tick(e,f,1/60)
 assert(e.states[3].retired,'retired once in its pit box')
 assert(e.commands[3].scPark and e.commands[3].parkReason=='retired','parked until the end')
 assert(count(e,'IA abandonnee:')==1,'one journal line')
 F.tick(e,f,1/60); assert(e.outRace[3]==true,'out of the race for pits, grid and frozen order (next frame)')
 -- Pont v2 : champ retired de la voiture (index d'AC 2), jamais pour les autres ; version 2.
 local B=require('src/bridge')
 assert(B.layout.version==2 and B.layout.dataKey=='ACAdvancedIA.Bridge.Data.v2','bridge layout v2')
 -- Pont v2 complet : retired à la fin des champs de la v1, suivi seulement de lastReason (tests/review164p.lua).
 local last=B.layout.car[#B.layout.car-1]; assert(last[1]=='retired' and last[2]=='bool' and B.layout.car[#B.layout.car][1]=='lastReason','retired appended at the end of the car struct')
 local out={cars={}}; for k=0,B.layout.maxCars-1 do out.cars[k]={} end
 B.publish(B.new('test'),out,e,f)
 assert(out.cars[2].retired==true and out.cars[1].retired==false and out.cars[0].retired==false,'bridge: retired published for that car only')
 -- Elle ressort de son emplacement : toujours garée (ramenée).
 f.cars[3].pit=false; f.cars[3].inPitBox=false; F.place(f,3,100,20); F.tick(e,f,1/60)
 assert(e.commands[3].scPark and e.commands[3].parkReason=='retired','still parked out of its box')
 -- Essais : pas d'abandon (comportement d'avant).
 local g,h,rec2=broken('P')
 assert(rec2,'scene: practice recovery')
 h.cars[3].pit=true; h.cars[3].inPitBox=true; F.tick(g,h,1/60)
 assert(not g.states[3].retired and g.commands[3].parkReason~='retired','practice: no retirement')
 -- Règle coupée : comportement d'avant.
 local old=K.recoverRetire; K.recoverRetire=false
 local ok,err=pcall(function()
  local m,n,rec3=broken('C'); assert(rec3,'scene'); n.cars[3].pit=true; n.cars[3].inPitBox=true; F.tick(m,n,1/60)
  assert(not m.states[3].retired,'rule off: as before')
 end)
 K.recoverRetire=old; assert(ok,err)
end
return tests
