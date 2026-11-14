-- Beta 1.63 (Random776, Overtake : replay vu en pleine course, « course finie » au retour) : pendant un replay, ni
-- arrivée, ni tour, ni changement de session relevés ; au retour, stabilisation (src/hudinfo.lua RK.settle) ; une
-- vraie arrivée reste reconnue. Noms terminés par _163Q. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local H=require('src/hudinfo')
local tests={}
local function race(e,f)
 f.started=false; F.place(f,1,0,150); F.place(f,2,20,140); F.place(f,3,2000,150)
 local me=f.cars[1]; me.position=3; me.lap=2
 F.tick(e,f,0.3); f.started=true; F.tick(e,f,0.3)
 assert(e.hud.started and e.hud.grid==3,'race running')
 return me
end
tests.REPLAY_NO_FALSE_FINISH_163Q=function()
 local e,f=F.scene('C',3); local me=race(e,f)
 local session,startedAt,lapBefore=e.session,e.startedAt,e.hud.lap
 -- Replay : valeurs du moment rejoué (fin de course, autre session, tour en arrière, voitures « arrivées »).
 f.replay=true; f.finished=true; me.finished=true; me.lap=0; f.session=session+3
 for _=1,20 do F.tick(e,f,0.1) end
 assert(not e.hud.finished and e.hud.recapSerial==0,'no finish latched during the replay')
 assert(e.session==session and e.startedAt==startedAt,'no session reset during the replay')
 -- Retour en course : vraies valeurs.
 f.replay=false; f.finished=false; me.finished=false; me.lap=2; f.session=session
 for _=1,10 do F.tick(e,f,0.1) end
 assert(not e.hud.finished and e.hud.recapSerial==0,'back from the replay: race not finished')
 assert(e.hud.started and e.hud.grid==3,'grid place kept ('..e.hud.grid..')')
 assert(e.hud.lap==2 and lapBefore==2,'lap resynchronised')
 -- Une valeur d'arrivée encore vue pendant la stabilisation n'est pas retenue.
 f.replay=true; F.tick(e,f,0.1); f.replay=false; me.finished=true; F.tick(e,f,0.1)
 assert(not e.hud.finished,'settling: no finish latched')
 me.finished=false
 for _=1,math.ceil(H.RK.settle/0.1)+2 do F.tick(e,f,0.1) end
 -- Vraie arrivée : reconnue.
 me.lap=10; me.position=1; me.finished=true; F.tick(e,f,0.3)
 assert(e.hud.finished and e.hud.final==1 and e.hud.recapSerial>0,'real finish still detected')
end
tests.REPLAY_SETTLE_CONSTANT_163Q=function() assert(H.RK.settle==2) end
return tests
