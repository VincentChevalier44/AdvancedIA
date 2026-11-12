-- Beta 1.42, relecture adverse des sanctions des IA (n142/review_sanctions.md) : un test par point, par Engine.step.
-- Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local A=require('src/applier')
local Sanctions=require('src/sanctions')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function out(f,i,on) local a=f.cars[i]; a.wheelsOut=on and 4 or 0; a.offtrack=on end
local function speed(f,i,kmh) local a=f.cars[i]; a.kmh=kmh; a.speed=kmh/3.6 end
local function learn(e,i,v) local s=e.states[i]; s.paceCount=e.delta.bins; for b=1,e.delta.bins do s.pace[b]=v end end
local function race(count,settings)
 local e,f=F.scene('C',count or 4)
 if settings then for k,v in pairs(settings) do e.profiles.C[k]=v end; E.changed(e) end
 F.tick(e,f,0.1)
 return e,f
end
-- B1 : un faux départ = une pénalité (par le vrai chemin du moteur), sur un mouvement tenu ; un sursaut ne compte pas.
tests.SANREV_JUMP_ONCE=function()
 local function grid(e,f)
  local g=e.grid; local now=e.time
  e.incidents.standing='lights'; g.phase='lights'; g.since=now-10; g.lightsAt=now; g.outAt=now+10
  g.slots={{spline=f.cars[2].spline,lateral=0}}; g.slotOf[2]=1; g.held[2]=true; speed(f,2,0); F.tick(e,f,1/60)
  return g
 end
 local e,f=race(); local g=grid(e,f)
 F.place(f,2,f.cars[2].z+2,5); F.tick(e,f,1)
 local c=e.sanctions.cars[2]
 assert(c.count==1 and c.pending=='drive' and not c.dq and count(e,'faux depart IA')==1 and g.aiJump[2]=='taken','one jump start, one penalty: '..c.count)
 F.tick(e,f,1); assert(c.count==1,'never re-armed')
 local e2,f2=race(); local g2=grid(e2,f2)
 F.place(f2,2,f2.cars[2].z+2,5); F.tick(e2,f2,0.3); F.place(f2,2,f2.cars[2].z-2,0); F.tick(e2,f2,1)
 assert(not g2.aiJump[2] and e2.sanctions.cars[2].count==0,'a twitch is not a jump start')
end
-- B2 : section décochée en course : tout s'arrête ; réglage d'une source coupé : sa pénalité est annulée.
tests.SANREV_UNTICK=function()
 local e,f=race()
 e.grid.aiJump[2]=true; F.tick(e,f,0.1)
 local c=e.sanctions.cars[2]; local c3=e.sanctions.cars[3]; c3.cutLeft=5; c3.cutSeconds=5
 assert(c.pending=='drive' and e.commands[2].rulePit)
 e.profiles.C.section_sanctions=false; E.changed(e); F.tick(e,f,0.5)
 assert(c.pending=='' and not e.commands[2].rulePit and c3.cutLeft==0 and e.commands[3].throttleLimit==1,'section unticked: nothing left')
 for _=1,3 do f.cars[2].lap=f.cars[2].lap+1; F.tick(e,f,0.2) end
 assert(not c.dq and count(e,'drapeau noir')==0,'no black flag')
 -- Passage de pénalité en cours au moment où la section est décochée : rien ne reste.
 local p,fp=race(); p.sanctions.pitSeen=true; p.grid.aiJump[2]=true; F.tick(p,fp,0.1)
 fp.cars[2].pit=true; F.tick(p,fp,0.5); local cp=p.sanctions.cars[2]; assert(cp.entry)
 p.profiles.C.section_sanctions=false; E.changed(p); F.tick(p,fp,0.2)
 assert(cp.pending=='' and not cp.entry and not p.commands[2].penaltyPass,'pass in progress dropped')
 local s,fs=race(); s.grid.aiJump[2]=true; F.tick(s,fs,0.1)
 s.profiles.C.sanJumpStart=false; E.changed(s); F.tick(s,fs,0.2)
 assert(s.sanctions.cars[2].pending=='' and count(s,'drive-through annule (reglage coupe)')==1,'source switch off: penalty cancelled')
end
-- M1 : coupure des gaz : distance selon l'approche, reprise au-delà de 50 m, ligne droite par l'accélération latérale.
tests.SANREV_CUT_SAFETY=function()
 local e,f=race(); local c=e.sanctions.cars[2]
 local function arm() c.cutLeft=5; c.cutSeconds=5; c.cutWait=0; c.rejoinAt=-math.huge end
 arm(); F.place(f,2,0,150); F.place(f,3,-60,210); e.states[2].nextPerception=0; F.tick(e,f,0.5)
 assert(e.commands[2].throttleLimit==1 and c.cutBlocked,'60 m behind at +60 km/h: unsafe')
 F.place(f,2,0,150); F.place(f,3,-40,150); F.tick(e,f,0.5)
 assert(e.commands[2].throttleLimit==1,'hysteresis: 40 m after a block is still too close')
 F.place(f,3,-80,150); F.tick(e,f,1); assert(e.commands[2].throttleLimit<1,'beyond 50 m: served')
 arm(); F.place(f,3,3000,150); f.cars[2].yawRate=0.08; F.tick(e,f,1)
 local lat=0.08*150/3.6; assert(lat>K.sanStraightLat and c.cutLeft==5 and c.cutWait>0.9,'lateral acceleration '..lat..' m/s2: not a straight')
 f.cars[2].yawRate=0; c.rejoinAt=e.time; F.tick(e,f,1); assert(c.cutLeft==5,'never right after a rejoin')
 f.cars[2].pit=true; local w=c.cutWait; F.tick(e,f,1); assert(c.cutWait==w,'no deferral counted in the pit lane')
end
-- M2 : place à rendre : jamais pour une attardée ; annulée sous drapeau jaune ; jamais sous le plancher de vitesse.
tests.SANREV_GIVEBACK=function()
 local e,f=race(); learn(e,2,40); learn(e,3,40)
 F.place(f,2,0,140); F.place(f,3,30,120); f.cars[3].lap=f.cars[2].lap-1
 F.refresh(e,f,2); out(f,2,true); F.tick(e,f,0.5)
 out(f,2,false); F.tick(e,f,0.2)
 assert(next(e.sanctions.cars[2].watch)==nil and e.sanctions.cars[2].owedTo==0,'a lapped car is never watched nor owed')
 local g,fg=race(); learn(g,2,40); learn(g,3,40)
 F.place(fg,2,0,140); F.place(fg,3,30,120); F.refresh(g,fg,2); out(fg,2,true); F.tick(g,fg,0.4)
 F.place(fg,2,40,140); F.place(fg,3,30,120); F.tick(g,fg,0.2); out(fg,2,false); F.tick(g,fg,0.2)
 local c=g.sanctions.cars[2]
 assert(c.owedTo==3,'pass off track: place owed')
 local limit=g.commands[2].yellowLimit
 assert(limit>=c.owedOther-K.sanGiveBackFloorDrop-1e-6 and limit>=40*3.6*K.sanGiveBackPaceFloor-1e-6,'speed floor: '..limit)
 g.states[3].yellow=true; Sanctions.update(g.sanctions,g,fg,g.time+0.01,1/60)
 assert(c.owedTo==0 and count(g,'annulee (drapeau jaune)')==1,'cancelled under yellow')
end
-- M3 : pénalité jamais purgeable (aucune IA aux stands) : temps ; stop-and-go sans retenue d'AC : drive-through.
tests.SANREV_NO_PIT=function()
 local e,f=race(); e.grid.aiJump[2]=true; F.tick(e,f,0.1)
 local c=e.sanctions.cars[2]; local a=f.cars[2]
 for _=1,K.sanNoPitLaps+1 do F.tick(e,f,0.5); a.lap=a.lap+1; F.tick(e,f,0.1) end
 assert(c.pending=='' and not c.dq and count(e,'voie des stands jamais prise par les IA')==1 and c.time==K.sanDriveTime,'converted to a time penalty')
 local s,fs=race(4,{sanProcedureKind='stopgo'}); s.stopCap=false; s.grid.aiJump[2]=true; F.tick(s,fs,0.1)
 assert(s.sanctions.cars[2].pending=='drive','stop-and-go impossible: drive-through')
end
-- M4 : aucune ligne de classement corrigé sans pénalité de temps ; places d'AC des arrivées seulement permutées.
tests.SANREV_CLASSIFICATION=function()
 local e,f=race(5)
 for i=1,5 do f.cars[i].position=i end
 F.tick(e,f,0.5)
 f.time=1000; f.cars[2].finished=true; f.cars[2].lap=10; F.tick(e,f,0.1)
 assert(#e.sanctions.classRows==0 and count(e,'classement corrige')==0,'no penalty: nothing')
 e.sanctions.cars[3].time=10
 f.time=1003; f.cars[3].finished=true; f.cars[3].lap=10; F.tick(e,f,0.1)
 f.time=1005; f.cars[4].finished=true; f.cars[4].lap=10; F.tick(e,f,0.1)
 assert(Sanctions.position(e.sanctions,4)==3 and Sanctions.position(e.sanctions,3)==4 and Sanctions.position(e.sanctions,2)==2,'AC places 2,3,4 permuted')
 local n=count(e,'classement corrige'); F.tick(e,f,1); assert(count(e,'classement corrige')==n,'journal line only on change')
end
-- M5 : point de reprise réécrit au changement de session.
tests.SANREV_RESET_DIRTY=function()
 local e=race(); e.sanctions.cars[2].time=10; e.sanctions.dirty=false
 Sanctions.reset(e.sanctions,e.time); assert(e.sanctions.dirty,'checkpoint rewritten after a reset')
end
-- M6 : limites de piste jamais vers le drapeau noir ; sortie pendant une manœuvre de l'app ignorée.
tests.SANREV_TRACK_LIMITS=function()
 local e,f=race(4,{sanTrackWarnings=0,penaltyDisqualify=2})
 for _=1,6 do out(f,2,true); F.tick(e,f,0.5); out(f,2,false); F.tick(e,f,K.sanStrikeGap) end
 local c=e.sanctions.cars[2]; assert(c.time==6*e.run.sanTimeSeconds and not c.dq,'time penalties, no black flag: '..c.time)
 local m,fm=race()
 -- Module seul (le directeur réécrit l'état à chaque image) : IA en dépassement pendant toute la sortie.
 out(fm,2,true); for k=1,30 do m.states[2].state='OVT_IN'; Sanctions.update(m.sanctions,m,fm,m.time+k/60,1/60) end
 out(fm,2,false); Sanctions.update(m.sanctions,m,fm,m.time+0.6,1/60)
 assert(m.sanctions.cars[2].strikes==0,'exit while the app moves the car: ignored')
end
-- Vitesse limite des stands douteuse : 80 km/h ; contresens hors piste : rien ; plus aucun tour : pas de drapeau noir.
tests.SANREV_MINORS=function()
 local e,f=race(); f.pitsSpeedLimit=20; local a=f.cars[2]; a.pit=true; speed(f,2,75); F.tick(e,f,8)
 assert(count(e,'stands IA')==0,'pit speed limit under 40 km/h ignored')
 local w,fw=race(); local b=fw.cars[3]; out(fw,3,true); speed(fw,3,40)
 for _=1,8*60 do b.z=b.z-b.speed/60; b.spline=(b.z/fw.length)%1; F.tick(w,fw,1/60) end
 assert(not w.sanctions.cars[3].dq,'reversing off track is not the wrong way')
 -- Beta 1.60 (contresens jugé sur l'orientation) : voiture retournée, nez en avant contre le sens, hors piste : jamais
 -- sanctionnée (Beta 1.42m), même si elle avance vraiment à contresens.
 local w2,fw2=race(); local b2=fw2.cars[3]; out(fw2,3,true); speed(fw2,3,40)
 for _=1,8*60 do b2.lx=0; b2.lz=-1; b2.z=b2.z-b2.speed/60; b2.spline=(b2.z/fw2.length)%1; F.tick(w2,fw2,1/60) end
 assert(not w2.sanctions.cars[3].dq,'nose-first the wrong way, off track: not sanctioned')
 local l,fl=race(); l.sanctions.pitSeen=true; fl.sessionLaps=10; fl.leaderLaps=10
 local c=l.sanctions.cars[2]; c.pending='drive'; c.pendingReason='jumpStart'; c.pendingLaps=5; c.could=true; c.issueLap=-5
 fl.cars[2].lap=fl.cars[2].lap+1; F.tick(l,fl,0.1)
 assert(not c.dq,'no black flag when no laps are left')
end
-- Drapeau « dans la voie » d'AC instable un instant pendant un drive-through : même passage, pénalité pas encore purgée.
tests.SANREV_LANE_FLICKER=function()
 local e,f=race(); e.sanctions.pitSeen=true; e.grid.aiJump[2]=true; F.tick(e,f,0.1)
 local c=e.sanctions.cars[2]; local a=f.cars[2]
 a.pit=true; F.tick(e,f,1); assert(c.entry,'penalty pass')
 a.pit=false; F.tick(e,f,0.3); a.pit=true; F.tick(e,f,1)
 assert(c.entry and c.pending=='drive','a flicker of the pit-lane flag is not an exit')
 a.pit=false; F.tick(e,f,K.sanLaneDebounce+0.1); assert(c.pending=='','served at the real exit')
end
-- Zone où la trajectoire des IA sort : trois IA en peu de temps, avertissements déjà donnés rendus.
tests.SANREV_LINE_REFUND=function()
 local e,f=race(6)
 for k,i in ipairs({2,3,4}) do F.place(f,i,5000+(k-1)*10,120) end
 F.tick(e,f,0.5)
 out(f,2,true); F.tick(e,f,0.5); out(f,2,false); F.tick(e,f,0.2)
 assert(e.sanctions.cars[2].strikes==1,'first warning')
 out(f,3,true); F.tick(e,f,0.5); out(f,3,false); F.tick(e,f,0.2)
 out(f,4,true); F.tick(e,f,0.5); out(f,4,false); F.tick(e,f,0.2)
 assert(count(e,'zone ignoree a ')==1 and count(e,'sanction annulee (zone ignoree)')==2 and e.sanctions.cars[2].strikes==0 and e.sanctions.cars[3].strikes==0,'zone ignored, warnings given back')
end
-- Accélérateur : rendu exactement à 1 au-dessus de 0,99.
tests.SANREV_THROTTLE_RETURN=function()
 local host=require('tests/host').create(true); local e,f=F.scene('C')
 local a=A.new(); assert(A.access(a))
 for _,cmd in ipairs(e.commands) do cmd.active=false end
 local cmd=e.commands[2]; cmd.active=true; cmd.offset=0; cmd.levelOwned=true; cmd.aggressionOwned=false; cmd.cautionOwned=false; cmd.level=0.9; cmd.speedLimit=K.unlimitedSpeed
 cmd.throttleLimit=0.5; A.apply(a,f,e.commands,e.g,1); assert(host.throttleLimits[1]==0.5)
 cmd.throttleLimit=0.995; A.apply(a,f,e.commands,e.g,2); assert(host.throttleLimits[1]==1 and a.cars[2].throttle==nil,'exactly 1 above 0.99')
end
return tests
