-- Beta 1.63 (demande du pilote) : décompte 3, 2, 1 puis « GO » à la fin d'une VSC ou d'une FCY (src/panel.lua).
-- Noms terminés par _163H3. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local E=require('src/engine')
local C=require('src/config')
local tests={}
local function scene(mode)
 local e,f=F.scene('C',4); e.profiles.C.neutralization=mode; e.profiles.C.yellowEnabled=false; E.changed(e)
 F.place(f,4,6000,0); F.tick(e,f,18)
 assert(e.incidents.neutral and e.incidents.neutralMode==mode,mode..' started')
 F.place(f,4,6000,100)
 return e,f
end
-- Suit le panneau image par image jusqu'au vert : titres du décompte vus, image du « GO » et image du vert.
local function follow(e,f,limit)
 local seen,goAt,greenAt,frames={},nil,nil,0
 while frames<limit do
  F.tick(e,f,1/60); frames=frames+1
  if e.panel.kind=='countdown' then seen[#seen+1]=e.panel.title end
  if e.panel.kind=='resumeGo' and not goAt then goAt=frames end
  if not e.incidents.neutral and not greenAt then greenAt=frames end
  if greenAt and frames>greenAt+90 then break end
 end
 local titles={}
 for _,s in ipairs(seen) do if titles[#titles]~=s then titles[#titles+1]=s end end
 return table.concat(titles,','),goAt,greenAt
end
tests.VSC_COUNTDOWN_163H3=function()
 local e,f=scene('vsc')
 for _=1,600 do F.tick(e,f,0.1); if e.incidents.ending then break end end
 assert(e.incidents.ending,'VSC ending announced')
 assert(e.panel.kind~='countdown','no countdown before the last seconds')
 local titles,goAt,greenAt=follow(e,f,60*(C.K.vscEnding+3))
 assert(titles=='3,2,1','countdown 3,2,1 ('..titles..')')
 assert(goAt and greenAt and math.abs(goAt-greenAt)<=1,'GO on the green frame ('..tostring(goAt)..' / '..tostring(greenAt)..')')
 F.tick(e,f,1.2); assert(e.panel.kind~='resumeGo','GO shown about one second only')
end
tests.FCY_COUNTDOWN_163H3=function()
 local e,f=scene('fcy')
 local titles,goAt,greenAt=follow(e,f,60*120)
 assert(greenAt,'FCY lifted')
 assert(titles=='3,2,1','countdown 3,2,1 ('..titles..')')
 assert(goAt and math.abs(goAt-greenAt)<=1,'GO on the green frame ('..tostring(goAt)..' / '..tostring(greenAt)..')')
end
tests.NO_COUNTDOWN_UNDER_SC_163H3=function()
 -- Voiture de sécurité (et tour de relance) : jamais de décompte, même à quelques secondes de la levée prévue.
 local e,f=scene('vsc')
 local t=e.incidents
 -- Tour de relance d'un drapeau rouge (mené en FCY ou SC) : pas de décompte non plus.
 for _,mode in ipairs({'sc','fcy'}) do
  t.neutralMode=mode; t.ending=false; t.relaunch=(mode=='fcy'); t.neutralUntil=e.time+2
  e.panel.at=-math.huge; e.panel.goUntil=nil
  require('src/panel').update(e.panel,t,f,e.run,'C',e.time,nil,e)
  assert(e.panel.kind~='countdown' and e.panel.kind~='resumeGo',mode..': no countdown ('..e.panel.kind..')')
 end
end
-- Fin de VSC annulée par un nouvel incident : ni décompte resté affiché ni « GO ».
tests.VSC_COUNTDOWN_CANCELLED_163H3=function()
 local e,f=F.scene('C',4); e.profiles.C.neutralization='vsc'; e.profiles.C.yellowEnabled=false; e.profiles.C.majorIncidentTime=5; E.changed(e)
 F.place(f,4,6000,0); F.tick(e,f,8); F.place(f,4,6000,100)
 for _=1,600 do F.tick(e,f,0.1); if e.incidents.ending then break end end
 assert(e.incidents.ending)
 F.place(f,3,3000,0)
 for _=1,60*(e.run.majorIncidentTime+2) do F.tick(e,f,1/60) end
 assert(e.incidents.neutral and not e.incidents.ending,'VSC goes on')
 assert(e.panel.kind~='countdown' and e.panel.kind~='resumeGo','countdown gone when the VSC goes on')
end
-- Verrou (règle du pilote : comportement validé verrouillé, tests/LOCKS.md) : décompte VSC et FCY, jamais sous SC.
tests.LOCK_VSC_COUNTDOWN_163=function()
 tests.VSC_COUNTDOWN_163H3(); tests.FCY_COUNTDOWN_163H3(); tests.NO_COUNTDOWN_UNDER_SC_163H3(); tests.VSC_COUNTDOWN_CANCELLED_163H3()
end
return tests
