-- Beta 1.61, tranche D : départs (noms terminés par _161D). Chargé par tests/extended.lua.
-- Réglage startRealism (section Départ, course) : tirages du départ, envols manqués, zigzag et deux files du tour de
-- formation, faux départs gradués, IA qui vole le départ (src/antics.lua, src/grid.lua, src/formation.lua, moteur).
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local Antics=require('src/antics')
local Grid=require('src/grid')
local Formation=require('src/formation')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function speed(f,i,kmh) local a=f.cars[i]; a.kmh=kmh; a.speed=kmh/3.6 end
-- Course : grille arrêtée derrière la ligne (place = indice), réglage startRealism posé.
local function race(n,on,settings)
 local e,f=F.scene('C',n or 6)
 e.profiles.C.startRealism=on~=false; e.profiles.C.playerPenalties=true
 if settings then for k,v in pairs(settings) do e.profiles.C[k]=v end end
 E.changed(e)
 for i=1,f.count do f.cars[i].position=i; F.place(f,i,-(10+(i-1)*8),0) end
 F.tick(e,f,1/60)
 return e,f
end
-- Circuit de 4 km (un tour de formation n'a lieu que sous K.formationMaxLength m), grille derrière la ligne.
local function formRace(n,on,want,seed)
 local e,f=F.scene('C',n); f.length=4000
 e.profiles.C.startRealism=on; e.profiles.C.raceStart=want; if seed then e.g.seed=seed end
 E.changed(e); e.gridCaps=true
 for i=1,f.count do f.cars[i].position=i; F.place(f,i,-(10+(i-1)*8),0) end
 F.tick(e,f,1/60)
 return e,f
end
-- Feu vert d'AC : front montant de la session.
local function acStart(e,f) f.started=false; F.tick(e,f,1/60); f.started=true; F.tick(e,f,1/60) end
-- Feux de la grille de l'app allumés, joueur (voiture 1) à sa place et à l'arrêt, extinction dans « lead » s.
local function lights(e,f,lead)
 local g=e.grid; local now=e.time
 e.incidents.standing='lights'; g.phase='lights'; g.since=now-10; g.lightsAt=now; g.outAt=now+lead
 g.slots={{spline=f.cars[1].spline,lateral=0}}; g.slotOf[1]=1; g.refSet=false; g.jump=false
 speed(f,1,0); F.tick(e,f,1/60)
 assert(g.refSet,'player placed and still: reference taken')
 return g
end
-- Réglage coupé (défaut) : aucun tirage, aucun plafond, aucun décalage, la grille juge comme avant.
tests.START_REALISM_OFF_IDENTICAL_161D=function()
 for _,x in ipairs({'J','P','Q','C'}) do assert(C.defaults(x).startRealism==false,'off by default in profile '..x) end
 local e,f=race(6,false); acStart(e,f); F.tick(e,f,0.5)
 local t=e.antics
 assert(t.kind=='' and t.serial==0 and not t.active and e.grid.realism==false,'switch off: nothing drawn')
 assert(count(e,'depart: reactions')==0 and count(e,'tour de formation: depart par rangees')==0,'no line')
 for i=1,f.count do assert(e.states[i].formOffset==nil,'no lateral offset '..i) end
 -- Grille : faux départ du joueur jugé comme avant (une ligne, l'ancienne ; grade « jump » seulement).
 local g=lights(e,f,0.3)
 F.place(f,1,f.cars[1].z+2,5); F.tick(e,f,0.5)
 assert(count(e,'faux depart du joueur: 2.0 m, 5 km/h')==1 and count(e,'faux depart du joueur: faux depart')==0,'old line only')
 assert(g.jumpGrade=='jump' and e.jumpDue==true and e.jumpJudgeAt==nil and e.penalties.jumpMult==nil,'old sanction path, no grade, no relief')
end
-- App rechargée ou réglage coché en pleine course, nouvelle session déjà lancée : aucun tirage, aucun plafond.
tests.ANTIC_NO_DRAW_MID_RACE_161D=function()
 local e,f=F.scene('C',6); e.incidents.restartSerial=3
 e.profiles.C.startRealism=true; E.changed(e)
 F.tick(e,f,0.5)
 assert(e.antics.active and e.antics.kind=='' and e.antics.serial==0,'switch ticked while racing: nothing drawn')
 assert(count(e,'depart: reactions')==0,'no start line')
 -- Une vraie relance ensuite : accordéon tiré une fois.
 e.incidents.restartSerial=4; F.tick(e,f,1/60)
 assert(e.antics.serial==1 and e.antics.kind=='restart','a real restart is drawn')
end
tests.RACESTART_DEFAULT_UNCHANGED_161D=function()
 assert(C.defaults('C').raceStart=='standing','standing start by default')
 local e,f=race(4,true); acStart(e,f)
 assert(not e.incidents.formation and e.formation.phase=='none' and e.incidents.rollGreenAt==nil,'startRealism never starts a formation lap or a rolling start')
 assert(e.antics.kind=='ac','AC standing start drawn')
end
-- Même graine et même numéro de départ : même tirage ; un nouveau départ tire de nouveau ; réactions dans leurs bornes.
tests.ANTIC_DRAW_DETERMINISTIC_161D=function()
 local a,fa=race(8,true); acStart(a,fa)
 local b,fb=race(8,true); acStart(b,fb)
 assert(a.antics.serial==1 and a.antics.kind=='ac' and count(a,'depart: reactions')==1,'one draw, one line')
 for i=2,8 do
  assert(a.antics.react[i]==b.antics.react[i] and a.antics.poor[i]==b.antics.poor[i],'same seed, same start: same draw '..i)
  assert(a.antics.react[i]>=K.anticReactMin and a.antics.react[i]<=K.anticReactMax,'reaction in range '..i)
 end
 assert(a.antics.react[1]==0 and not a.antics.poor[1],'the player is never drawn')
 local first={}; for i=2,8 do first[i]=a.antics.react[i] end
 acStart(a,fa)
 local same=true; for i=2,8 do if a.antics.react[i]~=first[i] then same=false end end
 assert(a.antics.serial==2 and not same,'a restarted race draws again')
end
tests.ANTIC_REACTION_RANGE_161D=function()
 local e,f=race(24,true)
 local t=Antics.new()
 for seed=1,20 do
  Antics.start(t,e,f,e.time,'ac',seed)
  for i=2,24 do assert(t.react[i]>=K.anticReactMin and t.react[i]<=K.anticReactMax,'range') end
 end
 -- Départ lancé : seulement à partir de la troisième rangée, aucun envol manqué.
 Antics.start(t,e,f,e.time,'roll',3)
 for i=2,24 do
  local row=math.floor((f.cars[i].position+1)/2)
  assert((t.react[i]>0)==(row>=K.anticAccordionRow) and not t.poor[i],'rolling start: accordion from row '..K.anticAccordionRow..' '..i)
 end
end
-- Envols manqués : K.anticPoorMax au plus, jamais deux dans la même colonne sur deux rangées qui se suivent ; plus
-- nombreux sous la pluie.
tests.ANTIC_POOR_BOUNDED_161D=function()
 local e,f=race(24,true)
 local dry,wet=0,0
 for pass=1,2 do
  -- Même numéro de départ dans les deux passes : seuls la pluie et son gain changent le tirage.
  local t=Antics.new(); f.wet=pass==2 and 1 or 0
  for seed=1,80 do
   Antics.start(t,e,f,e.time,'grid',seed)
   assert(t.poorCount<=K.anticPoorMax,'at most '..K.anticPoorMax)
   local n=0
   for i=2,24 do
    if t.poor[i] then
     n=n+1; assert(t.bog[i]>=K.anticBogTimeMin and t.bog[i]<=K.anticBogTimeMax,'bog time in range')
     for j=2,24 do if j~=i and t.poor[j] then assert(math.abs(f.cars[i].position-f.cars[j].position)~=2,'never stacked in a column') end end
    end
   end
   assert(n==t.poorCount and not t.poor[1],'count, never the player')
   if pass==1 then dry=dry+n else wet=wet+n end
  end
 end
 assert(dry>0 and wet>dry,'some poor starts, more in the rain: '..dry..' '..wet)
end
-- Plafonds : jamais sous K.throttleMin (aucune voiture tenue à l'arrêt), tout est rendu à la fin de la fenêtre.
tests.ANTIC_NO_STATIONARY_161D=function()
 local e,f=race(6,true); local t=e.antics
 Antics.start(t,e,f,e.time,'ac',1)
 for i=1,6 do t.poor[i]=false; t.react[i]=0 end
 t.react[2]=0.3; t.react[3]=0.1; t.poor[3]=true; t.bog[3]=1
 local function at(since) for i=1,6 do e.commands[i].throttleLimit=1 end; Antics.launch(t,e,f,t.at+since); end
 at(0.05)
 assert(e.commands[2].throttleLimit==K.throttleMin and e.commands[3].throttleLimit==K.throttleMin,'reaction: ceiling at the lowest throttle')
 assert(e.commands[1].throttleLimit==1 and e.commands[4].throttleLimit==1,'player and undrawn cars untouched')
 at(0.1); assert(math.abs(e.commands[3].throttleLimit-K.anticBogThrottle)<1e-9,'poor start: from the bog throttle')
 at(0.6); assert(math.abs(e.commands[3].throttleLimit-(K.anticBogThrottle+(1-K.anticBogThrottle)*0.5))<1e-9,'then a ramp')
 at(0.35); assert(e.commands[2].throttleLimit==1,'reaction over')
 at(1.2); assert(e.commands[3].throttleLimit==1,'poor start over')
 for since=0,2,0.05 do at(since); for i=1,6 do assert(e.commands[i].throttleLimit>=K.throttleMin,'never below the lowest throttle') end end
 assert(K.throttleMin>0 and K.anticBogThrottle>K.throttleMin,'a car is never held still')
 -- Départ lancé : simple rampe, jamais le plancher de gaz.
 Antics.start(t,e,f,e.time,'roll',1); for i=1,6 do t.react[i]=0 end; t.react[5]=0.4
 at(0); assert(math.abs(e.commands[5].throttleLimit-K.anticRollThrottle)<1e-9,'rolling: ramp from '..K.anticRollThrottle)
 at(0.2); assert(e.commands[5].throttleLimit>K.anticRollThrottle and e.commands[5].throttleLimit<1,'ramp')
end
-- Voiture collée derrière : l'envol manqué ne descend pas sous K.anticBogFloor.
tests.ANTIC_GOVERNED_161D=function()
 local e,f=race(6,true); local t=e.antics
 Antics.start(t,e,f,e.time,'grid',1)
 for i=1,6 do t.poor[i]=false; t.react[i]=0 end
 t.poor[3]=true; t.bog[3]=1; t.poor[4]=true; t.bog[4]=1
 e.states[3].rearClose=true; e.states[4].rearClose=false
 for i=1,6 do e.commands[i].throttleLimit=1 end
 Antics.launch(t,e,f,t.at+0.01)
 assert(e.commands[3].throttleLimit>=K.anticBogFloor and e.commands[3].throttleLimit<1,'followed: floored at '..K.anticBogFloor)
 assert(e.commands[4].throttleLimit<K.anticBogFloor,'not followed: the real bog')
end
-- Grades aux bornes.
tests.JUMP_GRADES_161D=function()
 local g=Antics.grade
 assert(g(K.jumpCreepMin,1,0,true,false)=='creep' and g(K.jumpCreepMeters,1,0,true,false)=='creep','creep at its bounds')
 assert(g(K.jumpCreepMin-0.01,1,0,true,false)=='none' and g(K.jumpCreepMeters+0.01,1,0,true,false)=='none','outside: nothing')
 assert(g(0.4,K.jumpCreepKmh,0,true,false)=='none' and g(0.4,1,0,false,false)=='none','creep needs low speed and a car still at lights out')
 assert(g(2,5,0.2,false,true)=='jump','jump')
 assert(g(K.jumpFlagrantMeters,5,0.2,false,true)=='flagrant' and g(K.jumpFlagrantMeters-0.01,5,0.2,false,true)=='jump','flagrant by distance')
 assert(g(2,5,K.jumpFlagrantLead+0.01,false,true)=='flagrant' and g(2,5,K.jumpFlagrantLead,false,true)=='jump','flagrant by lead')
 assert(Antics.lower('flagrant')=='jump' and Antics.lower('jump')=='creep' and Antics.lower('creep')=='none','one grade lower')
end
-- Mouvement sur la grille : averti, aucune pénalité.
tests.JUMP_PLAYER_CREEP_NO_PENALTY_161D=function()
 local e,f=race(4,true); local g=lights(e,f,0.5)
 F.place(f,1,f.cars[1].z+0.4,1); F.tick(e,f,0.1)
 speed(f,1,0); F.tick(e,f,0.6)
 assert(g.jumpGrade=='creep' and not g.jump,'creep graded at lights out: '..tostring(g.jumpGrade))
 assert(count(e,'faux depart du joueur: mouvement sur la grille, averti (0.4 m')==1,'warned in the journal')
 assert(not e.jumpDue and not e.penalties.jumpPending and e.jumpGrade==nil,'no penalty')
 F.tick(e,f,K.jumpJudgeTime+1); assert(not e.penalties.jumpPending and e.penalties.count==0,'never a penalty')
end
-- Faux départ et faux départ flagrant ; pénalité doublée ; avantage rendu : un cran plus bas.
tests.JUMP_FLAGRANT_DOUBLE_161D=function()
 local e,f=race(4,true); lights(e,f,0.3)
 F.place(f,1,f.cars[1].z+2,5); F.tick(e,f,0.5)
 assert(count(e,'faux depart du joueur: faux depart (2.0 m')==1 and e.jumpGrade=='jump' and e.jumpDue and e.penalties.jumpMult==nil,'jump: the usual penalty')
 assert(e.jumpJudgeAt~=nil and e.jumpPlace==1,'judged again later, place taken')
 local q,fq=race(4,true); lights(q,fq,0.3)
 F.place(fq,1,fq.cars[1].z+5,20); F.tick(q,fq,0.5)
 assert(count(q,'faux depart du joueur: faux depart flagrant (5.0 m')==1 and q.jumpGrade=='flagrant','flagrant')
 assert(q.penalties.jumpMult==K.jumpFlagrantMult,'penalty multiplied')
 -- La pénalité servie est doublée (chemin des pénalités).
 -- Finition 1.61 (relecture) : chemin réel, sans champ forcé : parti de la pole, rien rendu, jugé puis servi.
 speed(fq,1,0); fq.cars[1].position=1; F.tick(q,fq,K.jumpJudgeTime+1)
 assert(q.jumpGrade=='flagrant' and q.jumpJudgeAt==nil,'judged: flagrant kept')
 F.place(fq,1,K.jumpServeDistance+10,100); fq.cars[1].position=1
 speed(fq,1,100); F.tick(q,fq,K.penaltyCooldown+1)
 assert(q.penalties.reason=='jump' and q.penalties.seconds==q.run.penaltySeconds*K.jumpFlagrantMult,'served doubled: '..tostring(q.penalties.seconds))
 assert(q.penalties.jumpMult==nil,'multiplier used once')
end
tests.JUMP_RELIEF_161D=function()
 -- Flagrant, pas devant sa place après K.jumpJudgeTime s : jugé « faux départ » (pénalité simple).
 local e,f=race(4,true); lights(e,f,0.3)
 F.place(f,1,f.cars[1].z+5,20); F.tick(e,f,0.5)
 assert(e.jumpGrade=='flagrant' and e.penalties.jumpMult==K.jumpFlagrantMult,'flagrant first')
 speed(f,1,0); f.cars[1].position=2
 F.tick(e,f,K.jumpJudgeTime+0.2)
 assert(count(e,'juge un cran plus bas (avantage rendu, place 2 pour 1)')==1 and e.jumpGrade=='jump' and e.penalties.jumpMult==nil and e.jumpDue,'one place given back: one grade lower, penalty kept single')
 -- Finition 1.61 (relecture) : parti de la pole et toujours en tête : rien n'est rendu, flagrant maintenu.
 local o,fo=race(4,true); lights(o,fo,0.3)
 F.place(fo,1,fo.cars[1].z+5,20); F.tick(o,fo,0.5)
 assert(o.jumpPlace==1,'from pole')
 speed(fo,1,0); fo.cars[1].position=1
 F.tick(o,fo,K.jumpJudgeTime+0.2)
 assert(count(o,'juge un cran plus bas')==0 and o.jumpGrade=='flagrant' and o.penalties.jumpMult==K.jumpFlagrantMult,'pole kept: nothing given back')
 -- Faux départ simple, avantage rendu : averti, plus de pénalité.
 local q,fq=race(4,true); lights(q,fq,0.3)
 F.place(fq,1,fq.cars[1].z+2,5); F.tick(q,fq,0.5)
 speed(fq,1,0); fq.cars[1].position=2
 F.tick(q,fq,K.jumpJudgeTime+0.2)
 assert(count(q,'juge un cran plus bas')==1 and not q.jumpDue and not q.penalties.jumpPending and q.jumpGrade=='creep','jump given back: a warning')
 -- Devant sa place : rien n'est rendu.
 -- Finition 1.61 (relecture) : chemin réel : le joueur part de la troisième case de la grille de l'app.
 local r,fr=race(4,true); lights(r,fr,0.3); r.grid.slotOf[1]=3
 F.place(fr,1,fr.cars[1].z+2,5); F.tick(r,fr,0.5)
 assert(r.jumpPlace==3,'place of the grid slot: '..tostring(r.jumpPlace))
 speed(fr,1,0); fr.cars[1].position=2
 F.tick(r,fr,K.jumpJudgeTime+0.2)
 assert(count(r,'juge un cran plus bas')==0 and r.jumpGrade=='jump' and r.jumpJudgeAt==nil,'ahead of its place: judged as it is')
 -- Ligne passée et distance faite avant d'être rejugé : la pénalité attend le jugement, puis elle est servie simple.
 local s,fs=race(4,true); lights(s,fs,0.3)
 F.place(fs,1,fs.cars[1].z+5,20); F.tick(s,fs,0.5)
 assert(s.jumpGrade=='flagrant' and s.jumpLap==0,'flagrant, lap of the start noted')
 F.place(fs,1,K.jumpServeDistance+10,100); fs.cars[1].position=2
 F.tick(s,fs,1)
 assert(s.jumpDue and not s.penalties.jumpPending and s.penalties.count==0,'line crossed: not served before being judged again')
 F.tick(s,fs,K.jumpJudgeTime)
 assert(not s.jumpDue and s.jumpGrade=='jump' and (s.penalties.jumpPending or s.penalties.reason=='jump'),'served once judged')
 assert(s.penalties.jumpMult==nil and (s.penalties.reason~='jump' or s.penalties.seconds==s.run.penaltySeconds),'single penalty after the relief')
end
-- IA qui vole le départ : seulement avec la sanction du faux départ, une au plus, relevée aussitôt.
local function aiGrid(e,f)
 local g=e.grid; local now=e.time
 e.incidents.standing='lights'; g.phase='lights'; g.since=now-10; g.lightsAt=now; g.outAt=now+5; g.slots={}
 for i=2,f.count do g.slots[i-1]={spline=f.cars[i].spline,lateral=0}; g.slotOf[i]=i-1; g.held[i]=true; speed(f,i,0) end
 return g
end
tests.AI_JUMP_ONLY_WITH_SANCTION_161D=function()
 local chance=K.anticJumpChance; K.anticJumpChance=1.1
 local ok,err=pcall(function()
  local e,f=race(6,true,{sanJumpStart=false}); aiGrid(e,f)
  assert(Antics.jumper(e.antics,e,f,7)==0,'no jump-start sanction: no AI jumps')
  for i=1,K.maxCars do assert(e.grid.aiRelease[i]==nil,'nothing released') end
  local q,fq=race(6,true,{sanJumpStart=true}); aiGrid(q,fq)
  assert(Antics.jumper(q.antics,q,fq,7)>0,'with the sanction: one AI may jump')
  K.anticJumpChance=0
  assert(Antics.jumper(q.antics,q,fq,7)==0,'chance 0: never')
 end)
 K.anticJumpChance=chance; assert(ok,err)
end
tests.AI_JUMP_ONE_PER_START_161D=function()
 local chance=K.anticJumpChance; K.anticJumpChance=1.1
 local ok,err=pcall(function()
  local e,f=race(8,true,{sanJumpStart=true}); local g=aiGrid(e,f)
  local j=Antics.jumper(e.antics,e,f,11); local n=0
  for i=1,K.maxCars do if g.aiRelease[i] then n=n+1; assert(g.aiRelease[i]>=K.anticJumpLeadMin and g.aiRelease[i]<=K.anticJumpLeadMax,'lead in range') end end
  assert(n==1 and j>1 and g.aiRelease[j],'one car, an AI: '..n)
  assert(K.anticJumpLeadMax<=K.jumpFlagrantLead,'an AI jump is never flagrant by its lead')
  -- Avant son avance : retenue comme les autres ; à son avance : lâchée, faux départ relevé une fois.
  local t={standing='lights',cars={},gridLit=0}; for i=1,K.maxCars do t.cars[i]={incident=false,since=0} end
  local lead=g.aiRelease[j]
  for i=1,f.count do e.commands[i].stopHold=false; e.commands[i].gridWake=false end
  Grid.step(g,t,f,g.outAt-lead-0.05,e.commands,1,0,e.log,e.states,nil)
  assert(e.commands[j].stopHold==true and not g.aiJump[j],'held until its moment')
  for i=1,f.count do e.commands[i].stopHold=false end
  Grid.step(g,t,f,g.outAt-lead+0.01,e.commands,1,0,e.log,e.states,nil)
  assert(e.commands[j].stopHold==false and e.commands[j].gridWake==true,'released early')
  assert(g.aiJump[j]==true and g.aiJumpGrade[j]=='jump' and count(e,'faux depart IA: '..f.cars[j].name..', faux depart (')==1,'jump start recorded once')
  for i=2,f.count do if i~=j then assert(e.commands[i].stopHold==true and not g.aiJump[i],'the others stay held '..i) end end
  Grid.step(g,t,f,g.outAt-lead+0.03,e.commands,1,0,e.log,e.states,nil)
  assert(count(e,'faux depart IA: ')==1,'once')
 end)
 K.anticJumpChance=chance; assert(ok,err)
end
-- Sanction d'une IA : flagrant compté deux fois vers le drapeau noir, seulement avec le réglage.
tests.AI_JUMP_FLAGRANT_COUNT_161D=function()
 local e,f=race(4,true,{sanJumpStart=true}); F.tick(e,f,K.sanGraceStart+1)
 e.grid.aiJump[2]=true; e.grid.aiJumpGrade[2]='flagrant'; F.tick(e,f,0.1)
 assert(e.grid.aiJump[2]=='taken' and e.sanctions.cars[2].count==2,'flagrant: counted twice ('..e.sanctions.cars[2].count..')')
 e.grid.aiJump[3]=true; e.grid.aiJumpGrade[3]='jump'; F.tick(e,f,0.1)
 assert(e.sanctions.cars[3].count==1,'jump: counted once')
 local q,fq=race(4,false,{sanJumpStart=true}); F.tick(q,fq,K.sanGraceStart+1)
 q.grid.aiJump[2]=true; q.grid.aiJumpGrade[2]='flagrant'; F.tick(q,fq,0.1)
 assert(q.sanctions.cars[2].count==1,'switch off: as before')
end
-- Zigzag : conditions, jamais le joueur, deux files à l'appel du départ lancé.
tests.WEAVE_CONDITIONS_161D=function()
 local e,f=F.scene('C',5); e.profiles.C.startRealism=true; E.changed(e); F.tick(e,f,0.2)
 -- Voitures 3, 4, 5 à 1000, 2000, 3000 m de la ligne passée ; la voiture 2 est sur la ligne.
 assert(Antics.mayWeave(e,f,3),'straight, clear, far from the line: weave')
 assert(not Antics.mayWeave(e,f,2),'within '..K.weaveStopBefore..' m of the line: no weave')
 f.cars[3].yawRate=0.2; assert(not Antics.mayWeave(e,f,3),'corner: no weave'); f.cars[3].yawRate=0
 e.states[3].zone.noOvertake=true; assert(not Antics.mayWeave(e,f,3),'no-manoeuvre zone: no weave'); e.states[3].zone.noOvertake=false
 speed(f,3,20); assert(not Antics.mayWeave(e,f,3),'too slow: no weave'); speed(f,3,100)
 F.place(f,4,f.cars[3].z+K.weaveClear-5,100); F.tick(e,f,0.2)
 assert(not Antics.mayWeave(e,f,3) and not Antics.mayWeave(e,f,4),'a car within '..K.weaveClear..' m: no weave')
 F.place(f,4,f.cars[3].z+K.weaveClear+20,100); F.tick(e,f,0.2)
 assert(Antics.mayWeave(e,f,3),'clear again')
end
tests.WEAVE_NEVER_PLAYER_161D=function()
 local e,f=F.scene('C',5); e.profiles.C.startRealism=true; E.changed(e); F.tick(e,f,0.2)
 local t=e.antics; local inc=e.incidents
 assert(t.active,'switch on')
 F.place(f,1,5000,100); F.tick(e,f,0.2)
 inc.formation=true
 local peak=0
 for k=1,240 do Antics.weave(t,e,f,e.time+k/60,1/60); peak=math.max(peak,math.abs(e.states[3].formOffset or 0)); assert(e.states[1].formOffset==nil,'the player is never moved') end
 -- Correctif 1.61 (décision du pilote) : zigzag du tour de formation d'un bord à l'autre (K.formWeaveAmp).
 assert(peak>0.4 and peak<=K.formWeaveAmp+1e-9,'car 3 weaves within its amplitude: '..peak)
 assert(e.states[2].formOffset==nil,'car near the line does not weave')
 -- Fin du tour de formation : plus aucun décalage.
 inc.formation=false; Antics.weave(t,e,f,e.time+5,1/60)
 for i=1,5 do assert(e.states[i].formOffset==nil,'cleared '..i) end
 -- Réglage coupé : rien.
 local q,fq=F.scene('C',5); F.tick(q,fq,0.2); q.incidents.formation=true
 for k=1,60 do Antics.weave(q.antics,q,fq,q.time+k/60,1/60) end
 for i=1,5 do assert(q.states[i].formOffset==nil,'switch off: no offset') end
end
tests.ROLLING_TWO_FILES_161D=function()
 local e,f=F.scene('C',6); e.profiles.C.startRealism=true; E.changed(e); F.tick(e,f,0.2)
 for i=1,6 do f.cars[i].position=i end
 local t=e.antics; local inc=e.incidents
 inc.formation=true; inc.rollCall=true
 for k=1,180 do Antics.weave(t,e,f,e.time+k/60,1/60) end
 local sign=e.g.offsetSign<0 and -1 or 1
 for i=2,6 do
  local want=(i%2==1 and -1 or 1)*K.gridColumn*sign
  assert(math.abs((e.states[i].formOffset or 0)-want)<1e-9,'two files: odd places on the pole side '..i..' '..tostring(e.states[i].formOffset))
 end
 assert(e.states[1].formOffset==nil,'never the player')
 -- Amené progressivement (jamais un saut).
 local q,fq=F.scene('C',4); q.profiles.C.startRealism=true; E.changed(q); F.tick(q,fq,0.2)
 for i=1,4 do fq.cars[i].position=i end
 q.incidents.formation=true; q.incidents.rollCall=true
 Antics.weave(q.antics,q,fq,q.time,1/60)
 assert(math.abs(q.states[2].formOffset)<=K.formOffsetRate/60+1e-9,'ramped: '..tostring(q.states[2].formOffset))
end
-- Tour de formation : envol par rangées, allure de la tête selon l'endroit du tour.
tests.FORMATION_ROWS_161D=function()
 local e,f=formRace(6,true,'formation'); acStart(e,f)
 local t=e.antics; local inc=e.incidents
 assert(inc.formation and t.kind=='form','formation lap drawn as a getaway by rows')
 assert(count(e,'tour de formation: depart par rangees, zigzags oui, deux files a 0 m de la ligne')==1 and count(e,'depart: reactions')==0,'its own line')
 for i=2,6 do assert(math.abs(t.rowDelay[i]-(math.floor((i+1)/2)-1)*K.formLaunchGap)<1e-9,'row delay '..i) end
 for i=1,6 do e.commands[i].throttleLimit=1 end
 Antics.launch(t,e,f,t.at+K.formLaunchGap*0.5)
 assert(e.commands[2].throttleLimit==1 and e.commands[3].throttleLimit==K.throttleMin and e.commands[6].throttleLimit==K.throttleMin,'row 1 goes, the rows behind wait')
 assert(e.commands[1].throttleLimit==1,'never the player')
 for i=1,6 do e.commands[i].throttleLimit=1 end
 Antics.launch(t,e,f,t.at+K.formLaunchGap*1.5)
 assert(e.commands[3].throttleLimit==1 and e.commands[4].throttleLimit==1 and e.commands[5].throttleLimit==K.throttleMin,'row 2 goes next')
 -- Allure : lente à la sortie de la grille, vive au milieu, lente à la fin.
 local p=e.run; local base=Formation.pace(p); local L=4000
 assert(inc.formationKmh==base*K.formSlowMult,'slow out of the grid')
 assert(Formation.profile(p,K.formOutDistance-1,L,L)==base*K.formSlowMult and Formation.profile(p,K.formOutDistance,2000,L)==base*K.formBriskMult,'brisk in the middle')
 assert(Formation.profile(p,L*K.relaunchTravel,K.formBunchDistance,L)==base*K.formSlowMult and Formation.profile(p,L*K.relaunchTravel,K.formBunchDistance+1,L)==base*K.formBriskMult,'slow again over the last metres')
 assert(Formation.profile(p,K.formOutDistance+10,K.formBunchDistance-100,L)==base*K.formBriskMult,'not slowed when the line is passed at the very start of the lap')
 -- Réglage coupé : l'allure fixe de la 1.60.
 local q,fq=formRace(6,false,'formation'); acStart(q,fq)
 assert(q.incidents.formation and q.incidents.formationKmh==Formation.pace(q.run) and q.antics.kind=='','switch off: the 1.60 formation lap')
 -- Et pendant le tour (relecture 1.62) : l'allure ne suit pas le profil quand le réglage est coupé.
 F.tick(q,fq,0.5)
 assert(q.incidents.formation and q.incidents.formationKmh==Formation.pace(q.run),'switch off: fixed pace during the lap')
end
-- Départ lancé : la voiture de tête choisit son moment dans la zone ; jamais plus tard que la 1.60.
tests.ROLLING_POLE_GREEN_161D=function()
 local lo,hi=math.huge,0
 for seed=1,12 do
  local e,f=formRace(4,true,'rolling',seed); acStart(e,f)
  local at=e.incidents.rollGreenAt
  assert(e.incidents.formation and at and at>=K.rollGreenBefore and at<=K.rollZoneFrom,'green inside the zone: '..tostring(at))
  lo=math.min(lo,at); hi=math.max(hi,at)
 end
 assert(hi>lo,'drawn from the seed')
 local q,fq=formRace(4,false,'rolling'); acStart(q,fq)
 assert(q.incidents.formation and q.incidents.rollGreenAt==nil,'switch off: the 1.60 green')
 assert(K.rollZoneFrom>=K.rollGreenBefore,'the zone ends where the 1.60 green was')
end
-- Banc des départs (modèle simplifié de l'IA d'AC, 24 IA et le joueur). Départ arrêté d'AC avec trois envols manqués
-- forcés (part du plateau à 1, toujours K.anticPoorMax au plus) : tout le monde boucle son tour, pas plus de contacts
-- au premier virage que réglage coupé.
tests.START_BENCH_POOR_STARTERS_161D=function()
 local run=require('tests/startbench147')
 local share=K.anticPoorShare
 local ok,err=pcall(function()
  for _,sc in ipairs({{'monza','f1',1},{'monza','f1',3},{'short','gt3',3}}) do
   local scene=sc[1]..'/'..sc[2]..' seed '..sc[3]
   -- Beta 1.62 : « Realistic race » active les départs réalistes : réglage coupé à la main pour la référence.
   local off=run(sc[1],sc[2],{mode='app',seed=sc[3],tune=function(e) e.profiles.C.startRealism=false; E.changed(e) end})
   K.anticPoorShare=1
   local on=run(sc[1],sc[2],{mode='app',seed=sc[3],tune=function(e) e.profiles.C.startRealism=true; E.changed(e) end})
   K.anticPoorShare=share
   local function n(r,text) local c=0; for k=1,r.log.limit do local row=r.log[k]; if row and row.message and row.message:find(text,1,true) then c=c+1 end end return c end
   assert(n(off,'depart: reactions')==0 and n(on,'depart: reactions')==1,scene..': one draw with the switch on')
   assert(on.engine.antics.serial==1 and n(on,string.format('%d depart(s) manque(s)',K.anticPoorMax))==1,scene..': three poor starters')
   assert(on.finished==off.finished,scene..': every AI completes its lap ('..on.finished..' / '..off.finished..')')
   assert(on.contactsFirst<=off.contactsFirst and on.contacts<=off.contacts,scene..': no more contacts than with the switch off ('..on.contactsFirst..'/'..off.contactsFirst..' first corner, '..on.contacts..'/'..off.contacts..' in all)')
  end
 end)
 K.anticPoorShare=share; assert(ok,err)
end
-- Tour de formation réaliste (envol par rangées, zigzags, allure variable, deux files, vert choisi par la tête) puis
-- départ lancé : comme en 1.60, tout le monde boucle ses deux tours sans contact au premier virage.
tests.START_BENCH_ROLLING_REALISM_161D=function()
 local run=require('tests/startbench147')
 for _,sc in ipairs({{'short','gt3'},{'monza','f1'}}) do
  local r=run(sc[1],sc[2],{mode='app',seed=1,laps=2,formation=true,seconds=900,tune=function(e) e.profiles.C.raceStart='rolling'; e.profiles.C.startRealism=true; E.changed(e) end})
  local scene=sc[1]..'/'..sc[2]
  local function n(text) local c=0; for k=1,r.log.limit do local row=r.log[k]; if row and row.message and row.message:find(text,1,true) then c=c+1 end end return c end
  assert(n('tour de formation: depart par rangees')==1 and n('lance le depart a')==1 and n('abandonne')==0,scene..': realistic formation lap, the pole car starts the race')
  assert(r.finished==24,scene..': formation lap and first racing lap completed by every AI ('..r.finished..')')
  assert(r.contactsFirst==0 and r.contacts<=2,scene..': no contact into the first corner ('..r.contactsFirst..', '..r.contacts..' in all)')
 end
end
-- Finition 1.61 (relecture) : « flagrant » mesuré au vrai départ (au-dessus de K.jumpSpeed km/h), pas au moment où le
-- mouvement est relevé : une voiture qui glisse lentement 2,5 s avant l'extinction reste un faux départ simple.
tests.JUMP_FLAGRANT_FROM_LAUNCH_161D=function()
 local e,f=race(4,true); lights(e,f,2.5)
 F.place(f,1,f.cars[1].z+1.5,2); F.tick(e,f,3)
 assert(e.grid.jump and e.jumpGrade=='jump','slow roll long before the lights: jump, not flagrant ('..tostring(e.jumpGrade)..')')
 local q,fq=race(4,true); lights(q,fq,2.5)
 F.place(fq,1,fq.cars[1].z+1.5,20); F.tick(q,fq,3)
 assert(q.jumpGrade=='flagrant','real launch 2.5 s before the lights: flagrant ('..tostring(q.jumpGrade)..')')
end

return tests
