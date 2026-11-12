-- Beta 1.61, tranche B : mémoire des circuits (noms terminés par _161B). Chargé par tests/extended.lua.
-- Le module ne touche à aucun fichier : les tests jouent l'hôte (t.ioRead lu, texte rendu par P.loaded ; t.ioWrite
-- repris comme le fichier de la session suivante). Scènes du banc avec ce que le jeu donne : clé du circuit posée par
-- l'instantané (f.trackKey), modèle de voiture dans a.id, humidité dans f.wet.
local F=require('tests/fixture')
local C=require('src/config')
local P=require('src/pacemap')
local T=require('src/trackfile')
local D=require('src/director')
local Delta=require('src/delta')
local Classes=require('src/classes')
local Pitloss=require('src/pitloss')
local K=C.K
local tests={}
local function scene(count,on)
 local e,f=F.scene('P',count or 4)
 f.trackKey='test'; f.layout=''
 e.g.trackMemory=on~=false
 C.effectiveGlobals(e.g,e.p,e.runtimeG)
 -- Rien d'appris encore (la première image du banc apprend un endroit par voiture).
 for i=1,f.count do local s=e.states[i]; for b=1,#s.pace do s.pace[b]=0 end; s.paceCount=0; s.paceMean=0 end
 return e,f,e.pacemap,e.delta.bins
end
local function logged(e,text) for _,line in ipairs(e.log) do if tostring(line.message or line[4] or line.text or ''):find(text,1,true) then return true end end return false end
-- Allure apprise d'une voiture : share du tour à la vitesse donnée (m/s), comme le directeur la laisse.
local function learn(e,i,speed,share,bins)
 local s=e.states[i]; local n=math.floor(bins*(share or 1))
 for b=1,bins do s.pace[b]=b<=n and speed or 0 end
 s.paceCount=n; s.paceMean=n>0 and speed or 0
end
-- Une seconde de session : l'hôte lit le fichier demandé (file : texte du disque, nil : aucun fichier).
local function tick(t,e,f,now,file)
 P.observe(t,e,f,now)
 if t.ioRead then t.ioRead=nil; P.loaded(t,e,file,file and 'docs' or nil) end
end
local function flat(bins,speed) local data={}; for b=1,bins do data[b]=speed end return data end
local function fileOf(bins,models,extra)
 local sections={}
 for _,m in ipairs(models) do sections[#sections+1]={name='model.'..m[1],sessions=m[3] or 1,last=m[4] or 1,data=type(m[2])=='string' and m[2] or P.encode(m[2],bins),mean=999,count=1} end
 for _,s in ipairs(extra or {}) do sections[#sections+1]=s end
 return T.build('test',{kind='pace',track='test',layout='',length=10000,serial=5,bins=bins},sections)
end
tests.TRACK_MEMORY_SWITCH_LIVE_161B=function()
 assert(next(C.pendingGlobals)==nil,'trackMemory delivered: nothing pending')
 local g={}; for key,value in pairs(C.globalDefaults) do g[key]=value end
 assert(C.effectiveGlobals(g,C.defaults('P')).trackMemory==false,'off by default')
 g.trackMemory=true; assert(C.effectiveGlobals(g,C.defaults('P')).trackMemory==true,'on when ticked')
end
tests.PACEMAP_ROUNDTRIP_161B=function()
 local e,f,t,bins=scene(4)
 local data={}; for b=1,bins do data[b]=40+(b%7)*0.3 end
 local text=P.encode(data,bins)
 assert(#text==bins*3 and not text:find('%X'),'three hexadecimal digits per place')
 local back,why,mean,count=P.decode(text,bins)
 assert(back and why==nil and count==bins,'decoded')
 for b=1,bins do assert(math.abs(back[b]-data[b])<=0.05+1e-9,'place '..b) end
 assert(math.abs(mean-41)<0.2,'mean recomputed')
 tick(t,e,f,1,fileOf(bins,{{'car_2',data,3,4}}))
 assert(t.loaded and t.models.car_2 and t.models.car_2.sessions==3 and t.models.car_2.last==4 and t.serial==5,'model read')
 assert(logged(e,'memoire du circuit: test, allure de 1 modele(s) (3 session(s))'),'load line')
end
tests.PACEMAP_REJECT_FILE_161B=function()
 local function try(file,place,reason,setup)
  local e,f,t=scene(4)
  if setup then setup(f) end
  P.observe(t,e,f,1); assert(t.ioRead=='test' or setup,'read asked once'); t.ioRead=nil
  P.loaded(t,e,file,place)
  assert(next(t.models)==nil and t.pit==nil,'nothing kept: '..reason)
  assert(logged(e,'memoire du circuit: fichier ignore ('..reason..')'),'reason logged: '..reason)
 end
 local e0,_,_,bins=scene(4); assert(e0)
 local good=fileOf(bins,{{'car_2',flat(bins,50)}})
 try(nil,'big','taille')
 try(string.rep('x',K.paceMapMaxBytes+1),'docs','taille')
 try('[AdvancedIA]\nformat=99\nkind=pace\n','docs','format')
 try('garbage = [',nil and 'docs' or 'docs','syntaxe')
 try(good:gsub('kind=pace','kind=zones'),'docs','format')
 try(good:gsub('track=test','track=other'),'docs','circuit')
 try(good:gsub('layout=','layout=gp'),'docs','circuit')
 try(good:gsub('length=10000','length=9000'),'docs','longueur')
 try(good:gsub('bins='..bins,'bins='..(bins+1)),'docs','endroits')
 try(good:gsub('serial=5','serial='..(K.paceMapSerialMax+1)),'docs','format')
end
tests.PACEMAP_REJECT_MODEL_161B=function()
 local e,f,t,bins=scene(4)
 local ok=P.encode(flat(bins,50),bins)
 local half={}; for b=1,bins do half[b]=b<bins*K.paceMapMinShare-2 and 50 or 0 end
 local file=fileOf(bins,{
  {'short',ok:sub(1,-4)},{'nothex',ok:sub(1,-2)..'G'},{'fast',string.format('%03X',K.paceMapMaxSpeed+1)..ok:sub(4)},
  {'fewplaces',half},{'counters',flat(bins,50),1,9},{'good',flat(bins,50),2,5},{'player:good-car.v2',flat(bins,45),1,1}},
  {{name='model.'..string.rep('a',K.paceMapNameMax+1),sessions=1,last=1,data=ok},{name='model.player:',sessions=1,last=1,data=ok}})
 tick(t,e,f,1,file)
 assert(t.models.good and t.models['player:good-car.v2'],'valid models kept')
 for _,name in ipairs({'short','nothex','fast','fewplaces','counters'}) do assert(t.models[name]==nil,name..' dropped') end
 assert(#t.order==2,'only the two valid models')
 assert(logged(e,'modele short ignore (longueur)') and logged(e,'modele nothex ignore (chiffres)') and logged(e,'modele fast ignore (vitesse)'),'reasons')
 assert(logged(e,'modele fewplaces ignore (endroits)') and logged(e,'modele counters ignore (compteurs)') and logged(e,'modele ? ignore (nom)'),'reasons 2')
 assert(P.modelName('ks_ferrari_488_gt3') and P.modelName('player:a') and not P.modelName('a/b') and not P.modelName('..\\x') and not P.modelName('') and not P.modelName(7),'model names')
end
tests.PACEMAP_SPIKE_AND_MEAN_161B=function()
 local _,_,_,bins=scene(4)
 local data=flat(bins,50); data[10]=50*(1+K.paceMapSpike)+1; data[20]=50*(1+K.paceMapSpike)-1
 local back,_,mean,count=P.decode(P.encode(data,bins),bins)
 assert(back[10]==0,'isolated value set to unknown')
 assert(back[20]>0,'value inside the bound kept')
 assert(count==bins-1 and math.abs(mean-(50*(bins-2)+data[20])/(bins-1))<0.01,'mean and count recomputed from the data, never read')
end
tests.PACEMAP_MERGE_161B=function()
 local e,f,t,bins=scene(4)
 for i=2,4 do f.cars[i].id='gt3' end
 local base=flat(bins,50); base[5]=0
 tick(t,e,f,1,fileOf(bins,{{'gt3',base,2,5}}))
 learn(e,2,60,1,bins); learn(e,3,60,1,bins); learn(e,4,60,1,bins)
 e.states[2].pace[7]=30; e.states[3].pace[7]=30; e.states[4].pace[7]=30
 e.states[2].pace[8]=52; e.states[3].pace[8]=52; e.states[4].pace[8]=52
 tick(t,e,f,2)
 assert(P.mergeModel(t,e,'gt3'),'merged')
 local m=t.models.gt3
 assert(math.abs(m.data[1]-(50+(50*K.paceMapHigh-50)*K.paceMapAlpha))<1e-9,'too fast: cut to the high bound, then alpha')
 assert(m.data[7]==50,'too slow (traffic, damage): ignored')
 assert(math.abs(m.data[8]-(50+2*K.paceMapAlpha))<1e-9,'alpha')
 assert(m.data[5]==60,'place never seen before takes the session value')
 assert(m.sessions==3 and m.last==6,'one more session, confirmed at the next serial')
 local first=m.data[8]
 assert(P.mergeModel(t,e,'gt3') and t.models.gt3.data[8]==first and t.models.gt3.sessions==3,'a second save in the same session does not compound')
 assert(m.base[8]==50,'the map read at load is the reference of the session')
 -- Médiane des voitures du modèle ; voiture anormalement lente écartée.
 e.states[2].pace[9]=40; e.states[3].pace[9]=52; e.states[4].pace[9]=54
 P.mergeModel(t,e,'gt3'); assert(math.abs(t.models.gt3.data[9]-(50+2*K.paceMapAlpha))<1e-9,'median of the cars')
 e.states[3].paceCount=0; e.states[2].pace[9]=44; e.states[4].pace[9]=56
 P.mergeModel(t,e,'gt3'); assert(math.abs(t.models.gt3.data[9]-(50+6*K.paceMapAlpha))<1e-9,'two cars: the upper one')
 e.states[4].abnormalFor=3
 P.mergeModel(t,e,'gt3'); assert(math.abs(t.models.gt3.data[9]-(50-6*K.paceMapAlpha))<1e-9,'abnormally slow car left out')
 -- Modèle qui n'a pas appris assez du tour : rien.
 learn(e,2,60,K.paceMapMinShare-0.1,bins); learn(e,3,0,0,bins); learn(e,4,0,0,bins); e.states[4].abnormalFor=0
 assert(not P.mergeModel(t,e,'gt3'),'too little of the lap learnt')
end
tests.PACEMAP_SESSION_END_AND_WET_161B=function()
 local e,f,t,bins=scene(4)
 for i=2,4 do f.cars[i].id='gt3' end
 tick(t,e,f,1,nil)
 assert(logged(e,'memoire du circuit: rien de connu pour test'),'no file')
 for i=1,4 do learn(e,i,50,1,bins) end
 for now=2,20 do tick(t,e,f,now) end
 P.sessionEnd(t,e,21)
 local text=assert(t.ioWrite,'file asked at the session end'); assert(t.ioKey=='test')
 local doc=assert(T.parse(text,K.paceMapMaxBytes))
 assert(T.check(doc,'pace','test','',10000) and T.serial(doc)==1 and doc.head.bins==tostring(bins),'header')
 local names={}; for _,s in ipairs(doc.sections) do names[s.name]=s.values end
 assert(names['model.gt3'] and names['model.player:car_1'] and names['model.gt3'].sessions=='1' and names['model.gt3'].last=='1','AI model and player model apart')
 assert(t.serial==1 and t.models.gt3.base==t.models.gt3.data,'next session starts from what was kept')
 -- Session suivante mouillée : ni gardée ni utilisée.
 t.ioWrite=nil; P.reset(t)
 f.wet=K.priorWetMax+0.05
 for i=1,4 do learn(e,i,30,1,bins) end
 for now=30,60 do tick(t,e,f,now) end
 assert(e.states[2].priorMap==nil and e.states[2].prior==nil,'wet track: the kept pace is not used')
 P.sessionEnd(t,e,61)
 assert(t.ioWrite==nil and logged(e,'session non retenue (piste mouillee)'),'wet session not kept')
 assert(t.models.gt3.data[1]==50 and t.serial==1,'kept map untouched')
end
tests.PACEMAP_LRU_161B=function()
 local e,f,t,bins=scene(4)
 tick(t,e,f,1,nil)
 for n=1,K.paceMapModels+1 do
  local name=string.format('m%02d',n); t.order[#t.order+1]=name
  t.models[name]={base=flat(bins,40),data=flat(bins,40),mean=40,count=bins,sessions=1,last=n==7 and 0 or n+10}
 end
 local text,kept=P.text(t)
 assert(kept==K.paceMapModels and #text<=K.paceMapMaxBytes,'cap on the number of models, file under the size cap')
 assert(t.models.m07==nil and not text:find('[model.m07]',1,true) and text:find('[model.m01]',1,true),'the least recently confirmed model goes first')
 assert(#t.order==K.paceMapModels,'order list follows')
end
tests.PRIOR_RATIO_AND_LIVE_WINS_161B=function()
 local e,f,t,bins=scene(4)
 for i=2,4 do f.cars[i].id='gt3' end
 tick(t,e,f,1,fileOf(bins,{{'gt3',flat(bins,50)}}))
 tick(t,e,f,2)
 local s=e.states[2]; local a=f.cars[2]
 assert(s.priorMap==t.models.gt3.base and s.priorMean==50,'kept map attached at once (delta, classes)')
 assert(s.prior==nil,'not given to the driver logic before the car has learnt enough places')
 local b=Delta.bin(a.spline,bins)
 s.pace[b]=75; s.paceCount=K.priorRatioMin-1
 tick(t,e,f,3); assert(s.prior==nil and s.priorRatio==K.priorRatioHigh,'ratio learnt and clamped high, still too few places')
 s.paceCount=K.priorRatioMin
 tick(t,e,f,4); assert(s.prior==t.models.gt3.base,'prior given once priorRatioMin places are known')
 s.pace[b]=20; for now=5,80 do tick(t,e,f,now) end
 assert(math.abs(s.priorRatio-K.priorRatioLow)<0.01,'ratio clamped low')
 -- Le directeur : la valeur de la session gagne toujours ; l'a priori seulement là où rien n'est connu.
 local row={free=false}
 s.pace[b]=44; D.pace(s,a,row,1/60,e.run,nil,bins); assert(s.freePace==44,'live value wins')
 s.pace[b]=0; D.pace(s,a,row,1/60,e.run,nil,bins); assert(math.abs(s.freePace-50*s.priorRatio)<1e-9,'prior × ratio where nothing is known')
 s.prior=nil; D.pace(s,a,row,1/60,e.run,nil,bins); assert(s.freePace==0,'no prior: unknown as before')
 -- Delta : dernier repli avant la vitesse fixe, rapport 1.
 assert(Delta.pace(e.delta,e.states,2,b,false)==50,'delta reference falls back on the kept map')
 s.pace[b]=61; s.paceCount=K.paceMinBins; assert(Delta.pace(e.delta,e.states,2,b,false)==61,'live value first')
 s.priorMap=nil; s.pace[b]=0; assert(Delta.pace(e.delta,e.states,2,b,false)==0,'nothing known')
end
tests.PRIOR_CAR_CHANGED_AND_UNKNOWN_MODEL_161B=function()
 local e,f,t,bins=scene(4)
 f.cars[2].id='gt3'; f.cars[3].id='lmp'; f.cars[4].id='unknown_car'
 tick(t,e,f,1,fileOf(bins,{{'gt3',flat(bins,50)},{'lmp',flat(bins,62)},{'player:gt3',flat(bins,48)}}))
 tick(t,e,f,2)
 assert(e.states[2].priorMean==50 and e.states[3].priorMean==62 and e.states[4].priorMap==nil,'by car model; no record: nothing')
 assert(e.states[1].priorMap==nil,'the player has its own record, by its own model')
 f.cars[1].id='gt3'; tick(t,e,f,3); assert(e.states[1].priorMean==48,'player map kept apart from the AI map of the same model')
 e.states[2].priorRatio=1.1; e.states[2].priorN=4
 f.cars[2].id='lmp'; tick(t,e,f,4)
 assert(e.states[2].priorMean==62 and e.states[2].priorN==0 and e.states[2].prior==nil,'car changed: other model, ratio learnt again')
 assert(t.known==3 and t.unknown==1,'counts for the journal')
end
tests.PRIOR_CLASSES_FROM_START_161B=function()
 local e,f,t,bins=scene(5)
 f.cars[2].id='lmp'; f.cars[3].id='lmp'; f.cars[4].id='gt3'; f.cars[5].id='gt3'
 local p=e.run; local classes=Classes.new()
 local function cycles(from) for k=1,K.classCycles do Classes.update(classes,f.cars,e.states,f.count,p,from+k*K.classPeriod) end end
 cycles(0)
 for i=2,5 do assert(not e.states[i].classified,'nothing known at the first corner without the memory') end
 tick(t,e,f,1,fileOf(bins,{{'lmp',flat(bins,70)},{'gt3',flat(bins,70*(1-p.classGapPct/100)-3)}}))
 tick(t,e,f,2)
 cycles(10000)
 assert(e.states[2].classified and e.states[2].class==1 and e.states[3].class==1,'faster model: class 1 from the kept mean')
 assert(e.states[4].classified and e.states[4].class==2 and e.states[5].class==2,'slower model: class 2')
 -- Dès que la voiture a appris assez d'endroits, sa moyenne de la session remplace l'a priori.
 learn(e,4,71,1,bins); learn(e,5,71,1,bins); learn(e,2,70,1,bins); learn(e,3,70,1,bins)
 cycles(20000); assert(e.states[4].class==1 and e.states[5].class==1,'live means replace the kept ones')
end
tests.PITLOSS_KEPT_161B=function()
 local e,f,t,bins=scene(4)
 local lane=(K.pitLossMin+K.pitLossMax)/2
 local file=fileOf(bins,{{'car_2',flat(bins,50)}},{{name='pit',laneTime=lane,frac=0.08,samples=9}})
 tick(t,e,f,1,file); tick(t,e,f,2)
 assert(e.pitloss.known and e.pitloss.laneTime==lane and e.pitloss.frac==0.08 and e.pitloss.samples==9,'pit loss known from the first lap')
 Pitloss.sample(e.pitloss,lane+2,0.09)
 local rec=Pitloss.export(e.pitloss); assert(rec.samples==10 and rec.laneTime>lane,'exported with the new sample')
 assert(not Pitloss.import(e.pitloss,{laneTime=lane,frac=0.5,samples=3}),'never over what the session knows')
 local blank=Pitloss.new()
 assert(Pitloss.export(blank)==nil,'nothing learnt: nothing to keep')
 assert(not Pitloss.import(blank,{laneTime=K.pitLossMax+1,frac=0.1,samples=2}) and not Pitloss.import(blank,{laneTime=lane,frac=1,samples=2}) and not Pitloss.import(blank,{laneTime=lane,frac=0.1}) and not Pitloss.import(blank,'x'),'bounds of 1.60')
 -- Enregistrement refusé à la lecture : bornes.
 local e2,f2,t2=scene(4)
 tick(t2,e2,f2,1,fileOf(bins,{{'car_2',flat(bins,50)}},{{name='pit',laneTime=K.pitLossMax+5,frac=0.08,samples=9}}))
 assert(t2.pit==nil,'pit record out of bounds dropped')
 -- Gardé à la fin de la session, avec l'allure.
 for i=1,4 do learn(e,i,50,1,bins) end
 for now=3,10 do tick(t,e,f,now) end
 P.sessionEnd(t,e,11)
 assert(t.ioWrite:find('[pit]',1,true) and t.ioWrite:find('samples=10',1,true),'pit record written')
end
tests.SAVE_STEPS_161B=function()
 local e,f,t,bins=scene(4)
 f.cars[2].id='gt3'; f.cars[3].id='gt3'; f.cars[4].id='lmp'
 f.cars[1].pit=true
 tick(t,e,f,1,nil)
 for i=1,4 do learn(e,i,50,1,bins) end
 local now=2
 while now<K.paceMapSavePeriod+2 and not t.saving do tick(t,e,f,now); now=now+1 end
 assert(t.saving and now>=K.paceMapSavePeriod,'periodic save only after the period (player in the pits)')
 local steps=0
 while t.saving and steps<20 do assert(t.ioWrite==nil,'no write before the text is ready'); P.observe(t,e,f,now+steps*0.01); steps=steps+1 end
 assert(steps>=3 and t.ioWrite,'one model per frame (three models), then one write')
 local doc=assert(T.parse(t.ioWrite,K.paceMapMaxBytes)); assert(#doc.sections==3 and T.serial(doc)==1,'three models, serial of the session')
 -- L'hôte écrit : durée notée ; écriture lente : plus de sauvegarde périodique.
 local text=t.ioWrite; t.ioWrite=nil
 P.written(t,e,'docs',K.paceMapSlowMs+1,#text,3)
 assert(logged(e,'memoire du circuit: enregistree (3 modele(s), '..#text..' octets, '..(K.paceMapSlowMs+1)..' ms)') and t.slow,'save line with the milliseconds; slow write remembered')
 e.states[2].paceCount=e.states[2].paceCount-1
 for k=1,K.paceMapSavePeriod*2+5 do tick(t,e,f,now+k) end
 assert(t.saving==nil and t.ioWrite==nil,'after a slow write: session change only')
 P.sessionEnd(t,e,now+K.paceMapSavePeriod*3); assert(t.ioWrite and T.serial(T.parse(t.ioWrite,K.paceMapMaxBytes))==1,'session end still saves, same serial for the session')
 P.written(t,e,nil,0,0); assert(logged(e,'memoire du circuit: enregistrement impossible'),'failed write told')
 -- Rien de nouveau appris : pas de sauvegarde périodique.
 local e2,f2,t2=scene(4); f2.cars[1].pit=true
 tick(t2,e2,f2,1,nil)
 for k=2,K.paceMapSavePeriod*3 do tick(t2,e2,f2,k) end
 assert(t2.ioWrite==nil,'nothing learnt: nothing written')
 -- Joueur en piste : attendue jusqu'à deux périodes.
 local e3,f3,t3,b3=scene(4); tick(t3,e3,f3,1,nil); for i=1,4 do learn(e3,i,50,1,b3) end
 for k=2,K.paceMapSavePeriod*2-2 do tick(t3,e3,f3,k) end
 assert(not t3.saving and not t3.ioWrite,'player on track: waits')
 for k=K.paceMapSavePeriod*2-1,K.paceMapSavePeriod*2+3 do tick(t3,e3,f3,k) end
 assert(t3.saving or t3.ioWrite,'forced after twice the period')
end
tests.MEMORY_OFF_NO_IO_161B=function()
 local e,f,t,bins=scene(4,false)
 assert(e.runtimeG.trackMemory==false,'off')
 for i=1,4 do learn(e,i,50,1,bins) end
 for now=1,K.paceMapSavePeriod*2+5 do P.observe(t,e,f,now) end
 P.sessionEnd(t,e,1000)
 assert(t.ioRead==nil and t.ioWrite==nil and not t.loaded and not t.on,'switch off: no read, no write')
 for i=1,4 do local s=e.states[i]; assert(s.prior==nil and s.priorMap==nil and s.priorMean==nil,'no field set') end
 assert(P.status(t)==nil,'nothing to show')
 -- Allumé puis coupé : tout est retiré.
 e.runtimeG.trackMemory=true
 tick(t,e,f,2000,fileOf(bins,{{'car_2',flat(bins,50)}})); tick(t,e,f,2001)
 assert(e.states[2].priorMap~=nil and P.status(t)~=nil,'on: attached')
 e.runtimeG.trackMemory=false; P.observe(t,e,f,2002)
 assert(e.states[2].priorMap==nil and e.states[2].prior==nil and next(t.models)==nil and not t.loaded,'off again: detached and forgotten')
 -- Jamais en ligne, en rediffusion, ni sans clé de circuit.
 e.runtimeG.trackMemory=true
 f.online=true; P.observe(t,e,f,2003); assert(t.ioRead==nil,'online: nothing'); f.online=false
 f.replay=true; P.observe(t,e,f,2004); assert(t.ioRead==nil,'replay: nothing'); f.replay=false
 f.trackKey=''; P.observe(t,e,f,2005); assert(t.ioRead==nil and not t.on,'track without a safe file name: nothing read or written'); f.trackKey='test'
 P.observe(t,e,f,2006); assert(t.ioRead=='test','asked again once allowed')
end
tests.TRACK_OR_PLACES_CHANGED_161B=function()
 local e,f,t,bins=scene(4)
 tick(t,e,f,1,fileOf(bins,{{'car_2',flat(bins,50)}})); tick(t,e,f,2)
 assert(e.states[2].priorMap,'attached')
 f.trackKey='test__gp'; f.layout='gp'
 P.observe(t,e,f,3)
 assert(t.ioRead=='test__gp' and next(t.models)==nil and e.states[2].priorMap==nil,'other layout: other file, old map dropped')
 t.ioRead=nil; P.loaded(t,e,fileOf(bins,{{'car_2',flat(bins,50)}}),'docs')
 assert(next(t.models)==nil and logged(e,'fichier ignore (circuit)'),'file of another layout refused')
end
tests.FORGET_161B=function()
 local e,f,t,bins=scene(4)
 tick(t,e,f,1,fileOf(bins,{{'car_2',flat(bins,50)}},{{name='pit',laneTime=(K.pitLossMin+K.pitLossMax)/2,frac=0.08,samples=9}})); tick(t,e,f,2)
 t.forgetWanted=true; tick(t,e,f,3)
 assert(next(t.models)==nil and t.pit==nil and e.states[2].priorMap==nil,'forgotten')
 local doc=assert(T.parse(assert(t.ioWrite),K.paceMapMaxBytes))
 assert(#doc.sections==0 and T.check(doc,'pace','test','',10000),'an empty, valid file is written; nothing is deleted')
 assert(logged(e,'memoire du circuit: oubliee pour test'),'told')
 local off=P.new(); assert(not P.forget(off,e,4),'switch off: nothing')
end
return tests
