-- Relecture adversariale 2.0.4, tour 3, angle H (code ajouté du 2.0.2 au 2.0.4). Chargé par tests/extended.lua.
--  H1 : départ de 60 IA : toutes les voitures tenues écrivaient « maintien de ligne » à la même image ; la rafale
--       remplissait la limite de K.logRate lignes par seconde et chassait les autres lignes de la seconde du départ.
--  H2 : « tours du leader indisponibles » dit dès qu'une voiture avait 1 tour et le leader 0 (compteur lu une image après
--       celui des voitures au passage de la ligne : faux avertissement possible dans chaque course).
local F=require('tests/fixture')
local C=require('src/config')
local E=require('src/engine')
local U=require('src/util')
local Pits=require('src/pits')
local K=C.K
local tests={}

local function count(e,text) local n=0; for k=1,e.log.limit do local r=e.log[k]; if r and r.message and r.message:find(text,1,true) then n=n+1 end end return n end
local function grid(n)
 local e,f=F.scene('C',n+1); C.preset('Course','C',e.profiles.C)
 E.changed(e); E.configure(e)
 e.g.offsetSign=-1; e.g.sideSign=-1
 f.started=false
 F.place(f,1,-3000,0)
 for k=1,n do
  local i=k+1; local col=(k%2==1) and 0.1 or 5.5
  F.place(f,i,-(k-1)*8,0,col); f.cars[i].leftWidth=7.5; f.cars[i].rightWidth=7.5
 end
 F.tick(e,f,2)
 return e,f
end

tests.LOCK_REVIEW204H_1=function()
 local n=60
 local e,f=grid(n)
 f.started=true
 for k=1,n do local i=k+1; F.place(f,i,f.cars[i].z,20,f.cars[i].x); f.cars[i].brake=0 end
 F.tick(e,f,0.1,true)
 local held=0; for k=1,n do local s=e.states[k+1]; if s.laneActive and s.lane~=0 then held=held+1 end end
 assert(held>=25,'files held at the green: '..held)
 local lines=count(e,'maintien de ligne: ')
 assert(lines>=1 and lines<=12,'lane-hold lines capped per start: '..lines)
 -- Une autre ligne écrite dans la même seconde passe encore (la limite par seconde n'est pas remplie par la rafale).
 U.log(e.log,e.time,'WARN','ligne 204',-1)
 assert(count(e,'ligne 204')==1,'another line of the start second still logged')
end

tests.LOCK_REVIEW204H_2=function()
 local e,f=F.scene('C',3)
 local p=C.defaults('C'); p.section_rules=true; p.mandatoryStops=1; p.pitWindowOpenPct=20; p.pitWindowClosePct=80
 local run=C.distanceDefault('C',p,{mandatoryManual=true},C.effective('C',p,{}))
 f.sessionLaps=30; f.leaderLaps=0; f.timedRace=false; f.sessionMinutes=0; f.pitWindowStart=0; f.pitWindowEnd=0; f.length=5000
 local t=Pits.new(); local lines={}; t.note=function(level,text) lines[#lines+1]=level..' '..text end
 local function said() local c=0; for _,l in ipairs(lines) do if l:find('tours du leader indisponibles',1,true) then c=c+1 end end return c end
 f.started=true
 -- Passage de la ligne : compteur des voitures à 1, celui du leader encore à 0 pendant une image : pas d'avertissement.
 for i=1,f.count do f.cars[i].lap=1 end
 Pits.update(t,f,e.commands,run,'C',100,1,function() end,false)
 assert(said()==0,'one-frame lag at the line: no warning')
 assert(Pits.leaderLaps(f)==1,'fallback itself still immediate')
 f.leaderLaps=1; Pits.update(t,f,e.commands,run,'C',101,1,function() end,false)
 -- Compteur du leader resté à 0 alors que les voitures ont bouclé 2 tours : dit une fois.
 f.leaderLaps=0; for i=1,f.count do f.cars[i].lap=2 end
 Pits.update(t,f,e.commands,run,'C',102,1,function() end,false)
 for i=1,f.count do f.cars[i].lap=3 end
 Pits.update(t,f,e.commands,run,'C',103,1,function() end,false)
 assert(said()==1,'counter stuck at 0 after 2 laps: said once ('..said()..')')
end

return tests
