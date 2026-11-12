local C=require('src/config')
local E=require('src/engine')
local S=require('src/snapshot')
local P=require('src/perception')
local M={}
function M.scene(profile,count)
 local g=C.validateGlobals(C.globalDefaults); g.offsetSign=1; g.sideSign=1
 local profiles={J=C.defaults('J'),P=C.defaults('P'),Q=C.defaults('Q'),C=C.defaults('C')}
 for _,p in pairs(profiles) do for _,group in ipairs(C.sections) do p['section_'..group]=group~='traffic' end end
 -- Beta 1.51 : scènes réglées à la main : ni préréglage de la session (g.presetBySession), ni tours lancés des essais
 -- et qualifications (qualiTraffic) ; leurs propres tests les activent.
 g.presetBySession=false; profiles.P.qualiTraffic=false; profiles.Q.qualiTraffic=false
 local e=E.new(g,profiles); local f=S.new()
 f.count=count or 3; f.player=1; f.session=0; f.type=profile=='C' and 3 or profile=='Q' and 2 or 1
 -- Essais : session d'essais déclarée dans race.ini, hors Journée circuit.
 if profile=='P' then f.configType=1; f.configTrackDay=false end
 f.online=false; f.replay=false; f.paused=false; f.started=true; f.finished=false; f.length=10000; f.time=100; f.track='test'; f.left=1000
 for i=1,f.count do
  local a=f.cars[i]
  a.valid=true; a.control=i~=1; a.player=i==1; a.pit=false; a.offtrack=false; a.finished=false
  a.x=0; a.z=(i-2)*1000; a.y=0; a.lx=0; a.lz=1; a.sideDot=1; a.yawRate=0; a.kmh=100; a.speed=100/3.6
 a.spline=(a.z/10000)%1; a.splineValid=true; a.lap=1+math.floor(a.z/10000); a.lapValid=true; a.leftWidth=6; a.rightWidth=6; a.splineLat=0; a.splineLatValid=false
  a.id='car_'..i; a.name='Driver_'..i; a.length=4.4; a.width=1.85; a.stopped=0; a.slip=0
 end
 E.step(e,f,1/60)
 e.startedAt=-100; e.returning=false
 for i=1,f.count do local s=e.states[i]; s.persona.laneBias=0; s.base=0; s.offset=0; s.filtered=0; s.velocity=0; s.direction=0; s.lastDirectionAt=-math.huge; s.directionCount=0; for j=1,6 do s.directions[j]=-math.huge end; s.nextPerception=0 end
 return e,f
end
function M.place(f,i,z,kmh,x)
 local a=f.cars[i]; a.z=z; a.x=x or 0; a.splineLat=a.x; a.spline=(z/f.length)%1; a.lap=1+math.floor(z/f.length); a.kmh=kmh or 100; a.speed=a.kmh/3.6
 return a
end
-- Beta 1.47 : voitures arrêtées côte à côte en travers de la piste à z, réparties sur sa largeur : piste vraiment bloquée
-- (drapeau rouge, décision du pilote).
function M.block(f,list,z)
 local n=#list
 for k,i in ipairs(list) do local a=f.cars[i]; local w=a.leftWidth+a.rightWidth; M.place(f,i,z,0,-a.leftWidth+w*(k-0.5)/n) end
end
-- Mesures latérales comme les donne src/snapshot.lua en jeu (piste droite le long de z, x = écart à la trajectoire) :
--  - écart du départ (splineLat) : IA pilotées seulement, pendant que le moteur le demande (f.laneWanted) ;
--  - voiture lente ou arrêtée hors des stands : distance à la trajectoire et écart selon la piste (lineDist, lineLat) ;
--  - écart selon la piste de toutes les voitures hors des stands quand le jugement des collisions est en service
--    (f.blameWanted : trackLat) ;
--  - largeurs de piste lues 1 et 2 s plus loin pour les IA pilotées : la piste du banc a la même largeur partout, donc
--    les largeurs de la voiture (a.aheadFixed : test qui fixe lui-même ces largeurs, ou une lecture manquée).
-- f.senseOff : test qui fixe lui-même ces mesures (lecture manquée, valeurs particulières).
function M.sense(f)
 if f.senseOff then return end
 local slowKmh=C.K.offLineKmh
 for i=1,f.count do
  local a=f.cars[i]
  if a.valid then
   a.splineLatValid=f.laneWanted==true and a.control==true; a.splineLat=a.splineLatValid and a.x or 0
   local slow=not a.pit and a.kmh<slowKmh
   a.lineDistValid=slow; a.lineDist=slow and math.abs(a.x) or 0; a.lineLatValid=slow; a.lineLat=slow and a.x or 0
   a.trackLatValid=f.blameWanted==true and not a.pit; a.trackLat=a.trackLatValid and a.x or 0
   if not a.aheadFixed then
    local known=a.control==true and (a.leftWidth or 0)>0 and (a.rightWidth or 0)>0
    a.leftAhead=known and a.leftWidth or 0; a.rightAhead=known and a.rightWidth or 0; a.leftAhead2=a.leftAhead; a.rightAhead2=a.rightAhead
   end
  end
 end
end
function M.tick(e,f,seconds,kinematic)
 local n=math.floor(seconds*60+0.5)
 for _=1,n do
  if kinematic then for i=1,f.count do local a=f.cars[i]; a.z=a.z+a.speed/60; a.spline=(a.z/f.length)%1 end end
  M.sense(f)
  E.step(e,f,1/60)
  assert(e.errors==0,'unhandled car error')
  for i=1,f.count do
   local s=e.states[i]; local cmd=e.commands[i]; local row=e.perception.rows[i]
   assert(s.offset==s.offset and math.abs(s.offset)<=0.950001,'offset bound')
   assert(s.directionCount<=6,'direction count')
   if cmd.active then assert(cmd.level>=0.3 and cmd.level<=1.1 and cmd.caution>=0.5 and cmd.caution<=16,'command bound') end
   -- Beta 1.47 : dans la voie des stands, le décalage est rendu à AC (remis à zéro à la sortie) : pas un mouvement.
   local old=not f.cars[i].pit and s.testOffset or nil
   if old and not cmd.gridWake then assert(not(row.left and s.offset<old-1e-9),'movement towards occupied left'); assert(not(row.right and s.offset>old+1e-9),'movement towards occupied right') end
   s.testOffset=not f.cars[i].pit and s.offset or nil
  end
 end
end
function M.rear(e,f,gap,sa,index)
 M.place(f,2,0,100); M.place(f,index or 3,-gap-4.4,100+sa)
 e.states[2].nextPerception=0
end
function M.front(e,f,gap,sa)
 M.place(f,2,0,100+sa); M.place(f,3,gap+4.4,100)
 e.states[2].nextPerception=0
end
function M.yielding(state) return state=='YIELD_IN' or state=='YIELD_HOLD' end
function M.passing(state) return state=='OVT_ARM' or state=='OVT_IN' or state=='OVT_HOLD' end
function M.refresh(e,f,i) P.refresh(e.perception,f.cars,f.count,i,f.length) end
return M
