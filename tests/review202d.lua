-- Affinage 2.0.2 d (vidéo du pilote, départs : de la 15e à la dernière place, file unique sur la trajectoire, l'autre
-- côté vide ; replay de Monza du 15 novembre, AC_151126-110812 : la file de la grille à +5,5 m de la trajectoire la
-- rejoint en 10 à 14 s, en pleine ligne droite) : en course, la position latérale de la place sur la grille est tenue
-- après le feu vert jusqu'au premier freinage de la voiture (au plus K.startFilesMax s), même avec « Maintien de ligne
-- au départ » décoché ; « Premier tour attentif » décoché : rien. Chargé par tests/extended.lua.
local F=require('tests/fixture')
local C=require('src/config')
local E=require('src/engine')
local K=C.K
local tests={}

-- Grille en deux colonnes (replay) : voiture 2 sur la place décalée (+5,5 m du côté large), voiture 3 sur la trajectoire,
-- voiture 4 décalée deux rangs derrière. Réglage « Maintien de ligne au départ » décoché (défaut).
local function grid(sign,care)
 local e,f=F.scene('C',4); C.preset('Course','C',e.profiles.C)
 assert(not e.profiles.C.startLaneHold,'lane hold setting off by default')
 e.profiles.C.firstLapCare=care; e.profiles.C.startDelay=2; e.profiles.C.startRelax=25; E.changed(e); E.configure(e); e.g.offsetSign=sign
 f.started=false
 F.place(f,1,-3000,0); F.place(f,2,0,0,5.5); F.place(f,3,-8,0,0.1); F.place(f,4,-16,0,5.5)
 for i=2,4 do f.cars[i].leftWidth=7.5; f.cars[i].rightWidth=7.5 end
 F.tick(e,f,2)
 return e,f
end

tests.LOCK_START_TWO_ABREAST_202=function()
 for _,sign in ipairs({1,-1}) do
  local e,f=grid(sign,true)
  local s2,s3,s4=e.states[2],e.states[3],e.states[4]
  assert(s2.lane~=0 and s4.lane~=0,'grid side latched without the lane hold setting ('..s2.lane..', sign '..sign..')')
  assert(s3.lane==0,'car on the racing line: nothing to hold')
  -- Feu vert, voitures en file, personne à côté, aucun freinage : la place est tenue en pleine ligne droite (2.0.1 :
  -- rendue après K.laneRelease s, la file rejoignait la trajectoire).
  f.started=true
  for t=1,12 do
   F.place(f,2,t*45,160,5.5); F.place(f,3,t*45-8,160,0.1); F.place(f,4,t*45-60,160,5.5)
   F.tick(e,f,1,true)
  end
  assert(s2.laneActive and math.abs(e.commands[2].offset-s2.lane)<1e-6 and s2.lane~=0,'two abreast down the straight ('..e.commands[2].offset..')')
  assert(s4.laneActive and math.abs(e.commands[4].offset-s4.lane)<1e-6,'back of the grid keeps its side')
  -- Premier freinage de la voiture : encore tenue pendant le freinage, puis rendue à la trajectoire par la rampe.
  f.cars[2].brake=0.7
  F.tick(e,f,1,true)
  assert(s2.filesDone and math.abs(e.commands[2].offset-s2.lane)<1e-6,'held while braking')
  f.cars[2].brake=0
  F.tick(e,f,K.laneRelease+0.6,true)
  assert(s2.lane==0 and math.abs(e.commands[2].offset)<math.abs(5.5/7.5),'released after the braking zone: ramps back')
  -- Borne de temps : sans freinage, rendue au plus K.startFilesMax s après le lancement.
  local e5,f5=grid(sign,true); f5.started=true
  F.tick(e5,f5,K.startFilesMax+1,true)
  assert(e5.states[2].lane==0 and not e5.states[2].laneActive,'released at the time cap')
 end
 -- Point de freinage connu à moins de K.startFilesMerge s : rendue à la trajectoire seulement dans un trou de la file de
 -- la trajectoire (voiture 3 sur la trajectoire 8 m derrière : tenue ; voiture 3 à 100 m : rendue).
 for _,sign in ipairs({1,-1}) do
  local e,f=grid(sign,true); local s2=e.states[2]
  f.started=true
  local function at(z2,z3) F.place(f,2,z2,200,5.5); F.place(f,3,z3,200,0.1); F.place(f,4,z2-200,200,5.5) end
  for t=1,4 do at(t*55,t*55-8); F.tick(e,f,1,true) end
  assert(s2.laneActive and s2.lane~=0,'held on the straight')
  e.fl.count=1; e.fl.points[1]=((f.cars[2].z+f.cars[2].speed*(K.startFilesMerge-1))/f.length)%1
  at(f.cars[2].z+5,f.cars[2].z-3); F.tick(e,f,0.5,true)
  assert(not s2.filesDone and s2.lane~=0,'car on the line just behind: kept two abreast (sign '..sign..')')
  at(f.cars[2].z+5,f.cars[2].z-100); F.tick(e,f,K.laneRelease+0.6,true)
  assert(s2.filesDone and s2.lane==0,'hole in the line file before the braking point: merges (sign '..sign..')')
 end
 -- « Premier tour attentif » décoché (ou onglet Départ décoché) : rien n'est tenu.
 local e,f=grid(1,false)
 assert(e.states[2].lane==0 and math.abs(e.commands[2].offset)<1e-6,'first lap care off: no two files')
 -- Hors course : rien.
 local e2,f2=F.scene('P',3); f2.started=false; F.place(f2,1,-3000,0); F.place(f2,2,0,0,5.5); F.tick(e2,f2,2)
 assert(e2.states[2].lane==0,'practice: nothing held')
end

tests.K_202D=function()
 assert(K.startFiles==true and K.startFilesMax==25 and K.startFilesMerge==5 and K.startFilesGapBack==15 and K.startFilesGapTime==2 and K.startFilesGapAhead==20 and K.startFilesLineWidth==0.5,'2.0.2 d constants')
end

return tests
