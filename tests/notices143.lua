-- Beta 1.43 : annonces des sanctions des IA en panneau dédié de l'overlay (maquette, version 33) : sigle, pilote,
-- sanction et sa raison, étiquette ; jamais reprises en double sur la ligne de session. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local L=require('src/lang')
local Locale=require('src/locale')
local Sanctions=require('src/sanctions')
local K=C.K
local tests={}
local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function speed(f,i,kmh) local a=f.cars[i]; a.kmh=kmh; a.speed=kmh/3.6 end
local function race(count)
 local e,f=F.scene('C',count or 4)
 e.g.overlayMessages=true
 F.tick(e,f,0.1); assert(e.profile=='C')
 return e,f
end
-- Textes des six annonces, en français puis en anglais, comme la maquette.
tests.NOTICE_TEXTS_143=function()
 local function check(lang,want)
  if Locale.current~=lang then Locale.set(lang) end
  local R=L.sanctionTexts.reasons
  local cases={
   {'aiSanction','drive','Lorenzo Brazzoli',R.jumpStart},
   {'aiSanction','stopgo','Kenji Sato',10,R.pitExit},
   {'aiSanction','time','Daniel Okafor',5,R.trackLimits},
   {'aiSanction','throttle','Ana Rossi',5},
   {'aiSanction','giveBack','Tom Brandt','Ana Rossi'},
   {'aiBlackFlag','blackFlag','Marco Weber',R.wrongWay}}
  for k,c in ipairs(cases) do
   local t=Sanctions.new(); local before=t.aiSerial
   Sanctions.aiNotice(t,c[1],'texte',c[2],c[3],c[4],c[5])
   local w=want[k]
   assert(t.aiSerial==before+1,'new serial')
   assert(t.aiTitle==c[3],'driver as the title')
   assert(t.aiCode==w[1],lang..' code '..c[2]..': '..t.aiCode)
   assert(t.aiShort==w[2],lang..' short '..c[2]..': '..t.aiShort)
   assert(t.aiLabel==w[3],lang..' label '..c[2]..': '..t.aiLabel)
   assert(t.aiBlack==(c[2]=='blackFlag'),'black flag style only for the black flag')
   assert(t.aiFallback==L.messages[c[1]][1]..' · texte','fallback: title · text')
  end
 end
 check('fr',{{'DT','Drive-through (faux départ)','Sanction'},{'SG','Stop-and-go de 10 s (ligne de sortie des stands)','Sanction'},
  {'+5','+5 s (limites de piste)','Sanction'},{'CUT','Coupure des gaz 5 s (virage coupé)','Sanction'},
  {'POS','Doit rendre la place à Ana Rossi','Place à rendre'},{'','Drapeau noir (contresens)','Drapeau noir'}})
 check('en',{{'DT','Drive-through (jump start)','Sanction'},{'SG','10 s stop-and-go (pit-exit line)','Sanction'},
  {'+5','+5 s (track limits)','Sanction'},{'CUT','Throttle cut 5 s (corner cut)','Sanction'},
  {'POS','Must give the place back to Ana Rossi','Give the place back'},{'','Black flag (wrong way)','Black flag'}})
 Locale.set('fr')
end
-- Moteur : la sanction relevée devient l'annonce dédiée (pilote, sigle, sanction), en même temps que le message
-- d'avant ; une annonce toutes les K.sanNoticeGap s au plus, drapeau noir toujours ; journal inchangé.
tests.NOTICE_ENGINE_143=function()
 local e,f=race(5)
 local a=f.cars[2]
 a.pit=false; F.tick(e,f,K.sanLaneDebounce+0.5); a.pit=true; speed(f,2,120)
 F.tick(e,f,K.sanPitSpeedGrace+K.sanPitSpeedDwell+0.3)
 assert(e.sanctions.cars[2].pending=='drive','drive-through issued')
 local h=e.hud
 assert(h.aiTitle=='Driver_2' and h.aiCode=='DT' and h.aiShort=='Drive-through (excès de vitesse dans les stands)' and h.aiLabel=='Sanction','dedicated notice')
 assert(not h.aiBlack and h.aiUntil>e.time and h.aiUntil<=e.time+K.hudMessageTime,'shown for the message time')
 assert(e.incidents.messageKind=='aiSanction','same on-screen message as before (AC shows it when the overlay does not)')
 assert(count(e,'sanction IA: Driver_2 drive-through (exces de vitesse dans les stands)')==1,'journal unchanged')
 -- Deuxième sanction aussitôt : pas d'annonce (au plus une toutes les K.sanNoticeGap s).
 local serial=e.sanctions.aiSerial
 local gap=K.sanNoticeGap; K.sanNoticeGap=60
 local b=f.cars[3]; b.pit=false; F.tick(e,f,K.sanLaneDebounce+0.5); b.pit=true; speed(f,3,120); F.tick(e,f,K.sanPitSpeedGrace+K.sanPitSpeedDwell+0.3)
 K.sanNoticeGap=gap
 assert(e.sanctions.cars[3].pending=='drive','second drive-through issued')
 assert(e.sanctions.aiSerial==serial and h.aiTitle=='Driver_2','rate limited: at most one notice every K.sanNoticeGap s')
 -- Drapeau noir : toujours annoncé, style du drapeau noir, sans sigle.
 local c=f.cars[4]; speed(f,4,40); c.lz=-1 -- Beta 1.60 : contresens = nez en premier contre le sens de la piste (voiture retournée)
 for _=1,math.floor((e.run.sanWrongWaySeconds+0.5)*60) do c.z=c.z-c.speed/60; c.spline=(c.z/f.length)%1; F.tick(e,f,1/60) end
 assert(e.sanctions.cars[4].dq,'black flag')
 assert(h.aiTitle=='Driver_4' and h.aiBlack and h.aiCode=='' and h.aiShort=='Drapeau noir (contresens)' and h.aiLabel=='Drapeau noir','black flag notice')
 -- Changement de session : plus d'annonce affichée, aucune reprise de l'ancienne.
 f.session=f.session+1; F.tick(e,f,0.1); assert(h.aiUntil<e.time,'forgotten at session change')
 F.tick(e,f,0.5); assert(h.aiUntil<e.time,'old notice never shown again')
end
-- Overlay sans reprise des messages d'AC : aucune annonce dédiée (AC affiche lui-même le message, comme avant).
tests.NOTICE_OVERLAY_OFF_143=function()
 local e,f=race(3)
 e.g.overlayMessages=false
 local c=f.cars[3]; speed(f,3,40); c.lz=-1
 for _=1,math.floor((e.run.sanWrongWaySeconds+0.5)*60) do c.z=c.z-c.speed/60; c.spline=(c.z/f.length)%1; F.tick(e,f,1/60) end
 assert(e.sanctions.cars[3].dq and e.incidents.messageKind=='aiBlackFlag','black flag message for AC')
 assert(e.hud.aiUntil<e.time and e.hud.aiTitle=='','no dedicated notice')
end
-- Retour de l'annonce de l'app par ac.onMessage : jamais reprise en double sur la ligne de session, notée au journal
-- comme avant ; une autre annonce de l'app (pas une sanction d'IA) reste reprise.
tests.NOTICE_NO_DUPLICATE_143=function()
 local e,f=race(3)
 local title,text=L.messages.aiSanction[1],'Driver_2 : drive-through (faux départ)'
 e.ownTitle=title; e.ownText=text; e.ownAi=true
 local before=e.hud.msgUntil
 E.message(e,title,text,nil,5)
 assert(e.hud.msgUntil==before,'no generic duplicate on the session line')
 assert(count(e,'message d AC: '..title..' : '..text)==1,'journal line as before')
 E.message(e,title,text,nil,5); assert(count(e,'message d AC: '..title)==1,'logged once per title')
 e.ownAi=false; e.ownTitle='Pénalité'; e.ownText='Faux départ'
 E.message(e,'Pénalité','Faux départ',nil,5)
 assert(e.hud.msgUntil>e.time and e.hud.msgTitle=='Pénalité','the player own announcements are still shown')
end
return tests
