-- Beta 1.56 (décision du pilote) : vos limites de piste gérées par l'app, pénalités croissantes, rapport de course en
-- CSV. Tout est coupé par défaut. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local L=require('src/lang')
local Sanctions=require('src/sanctions')
local Penalties=require('src/penalties')
local Applier=require('src/applier')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function logged(e,text) return count(e,text)>0 end
local function out(f,i,on) local a=f.cars[i]; a.wheelsOut=on and 4 or 0; a.offtrack=on end
local function scene(profile,settings,cars)
 local e,f=F.scene(profile,cars or 4)
 if settings then for k,v in pairs(settings) do e.profiles[profile][k]=v end; E.changed(e) end
 F.tick(e,f,0.1); assert(e.profile==profile)
 return e,f
end
local function off(e,f,i,dwell) out(f,i,true); F.tick(e,f,dwell or 0.5); out(f,i,false); F.tick(e,f,K.sanStrikeGap) end
-- Par défaut : aucune sanction pour vous, aucune ligne nouvelle, aucune demande de pénalité, aucun rapport.
tests.PLAYER_LIMITS_OFF_156=function()
 for _,profile in ipairs({'P','Q','C'}) do
  local d=C.defaults(profile)
  assert(d.sanPlayerTrackLimits==false and d.sanEscalation==false and d.sanReport==false,profile..': off by default')
  assert(d.sanPlayerSession=='invalid' and d.sanPlayerPenalty=='time' and d.sanEscalationStep==5 and d.sanEscalationMax==30,profile..': defaults')
 end
 local e,f=scene('C')
 local id=e.penalties.requestId
 for _=1,10 do off(e,f,1) end
 assert(not logged(e,'joueur') and e.sanctions.cars[1].time==0 and e.sanctions.cars[1].strikes==0,'never the player by default')
 assert(e.penalties.requestId==id and e.reportLines==nil,'no penalty request, no report')
end
-- Course : avertissements (comme les IA), puis pénalité de temps au classement corrigé ; jamais vers le drapeau noir.
tests.PLAYER_LIMITS_RACE_TIME_156=function()
 local e,f=scene('C',{sanPlayerTrackLimits=true})
 for _=1,3 do off(e,f,1) end
 assert(count(e,'limites de piste joueur: avertissement')==3 and logged(e,'avertissement 3 / 3'),'three warnings')
 assert(e.incidents.messageKind=='playerSanction','announced to you')
 off(e,f,1)
 local c=e.sanctions.cars[1]
 assert(logged(e,'limites de piste joueur: penalite de temps +5 s, total +5 s') and c.time==5 and c.count==0 and c.trackN==1,'time penalty, not counted')
 assert(not logged(e,'sanction IA: Driver_1'),'player wording only')
 -- Sortie trop courte, au pas, ou aux stands : rien.
 local strikes=c.strikes
 off(e,f,1,0.2); f.cars[1].kmh=30; f.cars[1].speed=30/3.6; off(e,f,1); f.cars[1].kmh=100; f.cars[1].speed=100/3.6
 f.cars[1].pit=true; off(e,f,1); f.cars[1].pit=false
 assert(c.strikes==strikes,'dwell, speed and pits respected')
 -- Deux sorties rapprochées (moins de K.sanStrikeGap s) : une seule comptée.
 out(f,1,true); F.tick(e,f,0.5); out(f,1,false); F.tick(e,f,0.5); out(f,1,true); F.tick(e,f,0.5); out(f,1,false); F.tick(e,f,0.1)
 assert(c.strikes==strikes+1 and c.time==10,'one strike per gap')
 assert(Sanctions.playerSummary(e.sanctions,1)==string.format(L.recapTrackLimits,3,10),'recap line')
 -- Section décochée : plus rien (interrupteur compris dans sanctionSwitches).
 e.profiles.C.section_sanctions=false; E.changed(e); F.tick(e,f,0.1)
 assert(e.run.sanPlayerTrackLimits==false,'section unticked')
 -- Annonces des sanctions des IA coupées : les vôtres restent annoncées.
 local e2,f2=scene('C',{sanPlayerTrackLimits=true,sanMessages=false})
 off(e2,f2,1); assert(e2.incidents.messageKind=='playerSanction','your notices stay on screen')
end
-- Essais et qualifications : tour invalidé dans l'app, ou avertissement seulement.
tests.PLAYER_LIMITS_PRACTICE_156=function()
 local e,f=scene('P',{sanPlayerTrackLimits=true})
 f.sectorCount=3; f.cars[1].sector=0
 out(f,1,true); F.tick(e,f,0.5); out(f,1,false); F.tick(e,f,0.1)
 assert(count(e,'tour invalide joueur (app): secteur 1')==1 and e.sanctions.cars[1].invalidLap==f.cars[1].lap,'lap invalidated in the app')
 assert(not logged(e,'tour invalide IA: Driver_1'),'player wording')
 local e2,f2=scene('Q',{sanPlayerTrackLimits=true,sanPlayerSession='notice'})
 out(f2,1,true); F.tick(e2,f2,0.5); out(f2,1,false); F.tick(e2,f2,0.1)
 assert(logged(e2,'limites de piste joueur: sortie au secteur') and e2.sanctions.cars[1].invalidLap<0,'warning only')
 -- Sortie au pas (moins de K.sanOutKmh km/h) : rien.
 local e3,f3=scene('P',{sanPlayerTrackLimits=true}); f3.cars[1].kmh=20; f3.cars[1].speed=20/3.6
 out(f3,1,true); F.tick(e3,f3,0.5); out(f3,1,false); F.tick(e3,f3,0.1)
 assert(not logged(e3,'tour invalide joueur (app)'),'a crawl off the track is not track limits')
 assert(C.hidden('C','sanPlayerSession') and not C.hidden('P','sanPlayerSession') and C.hidden('P','sanPlayerPenalty'),'shown where it applies')
end
-- La règle des zones ignorées (trajectoire des IA hors des limites) ne vous concerne pas et vos sorties ne la nourrissent
-- jamais.
tests.PLAYER_LIMITS_NO_HOTSPOT_156=function()
 local e,f=scene('P',{sanPlayerTrackLimits=true},6)
 for k,i in ipairs({2,3,4}) do F.place(f,i,5000+(k-1)*5,100) end
 F.place(f,1,5010,100); F.tick(e,f,0.5)
 for _,i in ipairs({2,3,4}) do out(f,i,true); F.tick(e,f,0.5); out(f,i,false); F.tick(e,f,0.2) end
 assert(count(e,'limites de piste IA: zone ignoree')==1,'zone ignored for the AI')
 out(f,1,true); F.tick(e,f,0.5); out(f,1,false); F.tick(e,f,0.1)
 assert(logged(e,'tour invalide joueur (app)'),'still counted for you')
 for _,seen in pairs(e.sanctions.line) do assert(seen[1]==nil,'never in the hotspot data') end
end
-- Coupure des gaz d'AC : même canal que les pénalités sous drapeau, jamais comptée vers la disqualification ;
-- confirmée par l'écriture, sinon du temps à la place (et plus jamais écrite).
tests.PLAYER_LIMITS_THROTTLE_156=function()
 local t=Penalties.new(); t.lastAt=10
 assert(Penalties.requestTrackLimits(t,5,10.5)==nil,'never over a decision not yet written')
 local id=Penalties.requestTrackLimits(t,5,12)
 assert(id==1 and t.kind=='slow' and t.seconds==5 and t.reason=='limits' and t.count==0,'throttle cut, not counted')
 t.disqualified=true; assert(Penalties.requestTrackLimits(t,5,20)==nil,'never after a black flag')
 local e,f=scene('C',{sanPlayerTrackLimits=true,sanPlayerPenalty='throttle',sanTrackWarnings=0})
 e.penaltyCap=true
 out(f,1,true); F.tick(e,f,1); out(f,1,false); F.tick(e,f,0.1)
 local c=e.sanctions.cars[1]
 assert(logged(e,'limites de piste joueur: coupure des gaz 5 s demandee a AC') and c.cutRequest==e.penalties.requestId and c.time==0,'requested')
 e.penaltyWritten=c.cutRequest; F.tick(e,f,0.1); assert(c.cutRequest==0 and c.time==0,'written by AC: nothing more')
 F.tick(e,f,K.sanStrikeGap)
 out(f,1,true); F.tick(e,f,1); out(f,1,false); F.tick(e,f,0.1)
 local asked=c.cutRequest; assert(asked>0,'second request')
 F.tick(e,f,K.sanPlayerCutConfirm+0.1)
 assert(c.cutRequest==0 and e.penalties.cancelled==asked and c.time==5 and logged(e,', coupure des gaz refusee par AC'),'not written: time instead, never written later')
 -- Capacité absente : du temps tout de suite.
 local e2,f2=scene('C',{sanPlayerTrackLimits=true,sanPlayerPenalty='throttle',sanTrackWarnings=0})
 e2.penaltyCap=false; out(f2,1,true); F.tick(e2,f2,1); out(f2,1,false); F.tick(e2,f2,0.1)
 assert(e2.sanctions.cars[1].time==5 and e2.penalties.reason~='limits','no native penalty: time')
 -- Remplacée par du temps : l'applicateur ne l'écrit jamais ensuite.
 local a={allowed=true,penaltyServed=0}
 Applier.penalty(a,{online=false,replay=false,paused=false,player=1},{requestId=3,cancelled=3,kind='slow',seconds=5})
 assert(a.penaltyServed==3 and a.penaltyWritten==nil,'cancelled: served without a write')
end
-- Pénalités croissantes : 5, 10, 15… au plus sanEscalationMax (jamais moins que sanTimeSeconds) ; coupées : 5, 5, 5.
tests.ESCALATION_FORMULA_156=function()
 local function run(settings)
  local e,f=scene('C',settings)
  for _=1,6 do off(e,f,2,0.5) end
  return e,e.sanctions.cars[2]
 end
 local e,c=run({sanTrackWarnings=3})
 assert(c.time==15 and c.trackN==3 and not logged(e,'recidive'),'off: 5, 5, 5 '..c.time)
 e,c=run({sanTrackWarnings=3,sanEscalation=true})
 assert(c.time==30 and c.trackTime==30 and logged(e,'penalite de temps +15 s (limites de piste, recidive 3), total +30 s'),'5, 10, 15: '..c.time)
 local kept=0; for _,hit in pairs(c.lineHits) do if hit.kind=='time' then kept=math.max(kept,hit.seconds) end end
 assert(kept==15,'seconds actually added kept for a refund: '..kept)
 e,c=run({sanTrackWarnings=3,sanEscalation=true,sanEscalationMax=8})
 assert(c.time==21,'capped at 8: '..c.time)
 e,c=run({sanTrackWarnings=3,sanEscalation=true,sanEscalationMax=5,sanTimeSeconds=6})
 assert(c.time==18,'never below the base penalty: '..c.time)
 assert(not e.penalties.ai.dq[2] and not c.dq,'never a black flag from track limits')
end
-- Rapport : CSV (RFC 4180), ordre corrigé puis voitures non arrivées, en-tête fixe ; une fois par course.
tests.REPORT_CSV_156=function()
 local e,f=scene('C',{sanReport=true},4)
 f.cars[3].name='Dupont, "JP"'
 F.tick(e,f,0.1)
 assert(e.sanctions.raceSeen,'race seen')
 local t=e.sanctions
 t.cars[2].finishAt=10; t.cars[2].finishPos=1; t.cars[2].corrected=2; t.cars[2].finishLaps=5
 t.cars[3].finishAt=11; t.cars[3].finishPos=2; t.cars[3].corrected=1; t.cars[3].finishLaps=5
 local lines=Sanctions.report(t,e,f,false)
 assert(lines[1]:find('# AdvancedIA '..C.release..', {date}, test, ',1,true) and lines[1]:find('complete=0',1,true),'first line')
 local header=select(2,lines[2]:gsub(',',','))+1; assert(header==22,'22 columns (Beta 1.60 : colonne contacts ajoutée à la fin)')
 assert(lines[3]:find('^1,2,"Dupont, ""JP""",car_3,'),'quoted, corrected order: '..lines[3])
 assert(lines[4]:find('^2,1,Driver_2,',1),'second')
 assert(#lines==6 and lines[5]:find(',0,1,',1,true) or lines[6]:find(',0,1,',1,true),'unfinished cars last, player flagged')
 -- Une fois par course : arrivée de tous, puis plus rien ; changement de session sans rapport : partiel.
 for i=1,f.count do f.cars[i].finished=true end
 Sanctions.watch(t,f,e,e.time)
 assert(e.reportLines and t.reportDone and e.reportLines[1]:find('complete=1',1,true),'written once the race is complete')
 e.reportLines=nil; Sanctions.watch(t,f,e,e.time+1); assert(e.reportLines==nil and Sanctions.flushReport(t,e,f)==nil,'only once')
 local e2,f2=scene('C',{sanReport=true}); F.tick(e2,f2,0.1)
 f2.session=f2.session+1; F.tick(e2,f2,0.1)
 assert(e2.reportLines and e2.reportLines[1]:find('complete=0',1,true),'partial report on a session change')
 local e3,f3=scene('C'); f3.session=f3.session+1; F.tick(e3,f3,0.1); assert(e3.reportLines==nil,'off: never')
end
-- Écriture : rotation comme le journal (5 gardés), date à l'écriture, jamais de chemin complet en cas d'échec.
tests.REPORT_WRITE_156=function()
 local files={}; local moves={}
 local saved={open=io.open,fileExists=io.fileExists,move=io.move,getFolder=ac.getFolder,FolderID=ac.FolderID}
 io.fileExists=function(p) return files[p]~=nil end
 io.move=function(a,b) moves[#moves+1]=a..'>'..b; files[b]=files[a]; files[a]=nil; return true end
 io.open=function(p,mode) local buf={}; return {write=function(_,x) buf[#buf+1]=x end,close=function() files[p]=table.concat(buf) end} end
 ac.getFolder=function() return 'LOGS' end; ac.FolderID={Logs=1}
 local ok1,name=Applier.reportWrite({},{'# AdvancedIA X, {date}, t, 5 laps, complete=1','h','r1'})
 for n=1,6 do Applier.reportWrite({},{'# AdvancedIA X, {date}, t, 5 laps, complete=1','h','r'..n}) end
 local okEmpty=Applier.reportWrite({},{})
 io.open,io.fileExists,io.move,ac.getFolder,ac.FolderID=saved.open,saved.fileExists,saved.move,saved.getFolder,saved.FolderID
 assert(ok1 and name=='AdvancedIA-race.csv' and not okEmpty,'written, empty refused')
 assert(files['LOGS/AdvancedIA-race.csv']:find('r6\n',1,true) and not files['LOGS/AdvancedIA-race.csv']:find('{date}',1,true),'latest, dated')
 assert(files['LOGS/AdvancedIA-race.4.csv'] and not files['LOGS/AdvancedIA-race.5.csv'],'five kept')
 io.open=function() return nil end
 local ok2,why=Applier.reportWrite({},{'x'})
 io.open=saved.open
 assert(ok2==false and not tostring(why):find('/',1,true),'failure reason, never a path')
end
-- Pénalités d'AC actives alors que l'app gère vos limites : prévenu une fois (journal, accueil, overlay) ; bandeau de
-- coupe d'AC vu : noté une fois.
tests.PLAYER_AC_PENALTIES_WARN_156=function()
 local e,f=scene('C',{sanPlayerTrackLimits=true})
 assert(not e.acPenaltyWarned,'unknown: no warning')
 local e2,f2=F.scene('C',4); e2.profiles.C.sanPlayerTrackLimits=true; E.changed(e2); f2.penaltiesEnabled=true; f2.allowedTyresOut=-1
 F.tick(e2,f2,0.1); F.tick(e2,f2,0.1)
 assert(count(e2,'limites de piste joueur: penalites d AC actives (roues dehors autorisees -1)')==1 and e2.acPenaltyWarned,'warned once')
 e2.g.overlayMessages=true
 E.message(e2,'CUT DETECTED','LAP WILL NOT COUNT','',0); E.message(e2,'CUT DETECTED','LAP WILL NOT COUNT','',0)
 assert(count(e2,'AC sanctionne encore les coupes')==1,'AC cut banner noted once')
 local e3,f3=F.scene('C',4); f3.penaltiesEnabled=true; F.tick(e3,f3,0.1)
 assert(not logged(e3,'limites de piste joueur'),'off: nothing')
 assert(L.groups.sanctions=='Sanctions' and L.messages.playerSanction and L.acPenaltiesOn and L.choices.throttle and L.choices.invalid and L.choices.notice,'texts')
end
return tests
