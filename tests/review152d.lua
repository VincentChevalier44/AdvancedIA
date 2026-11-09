-- Beta 1.52 (relecture, domaine D : réglages, préréglages et interface) : onglet Règles décoché, préréglages personnels
-- anciens relus avec le défaut de leur profil, révision 15 des préréglages, marque « Perso » posée par la révision 22
-- des données, sorties étalées masquées en course et en hotlap. Chargé par tests/extended.lua.
local C=require('src/config')
local Presets=require('src/presets')
local tests={}
-- Préréglage enregistré par une version où les clés « missing » n'existaient pas : ac.storage les rend avec le défaut
-- de la disposition (Presets.layout, profil J).
local function oldPreset(name,profile,revision,missing,values)
 local store=Presets.layout(); store.name='Ancien'; store.profile=profile; store.revision=revision
 local full=C.preset(name,profile,{})
 for k,v in pairs(values or {}) do full[k]=v end
 for k,v in pairs(full) do if not missing[k] then store['p_'..k]=v end end
 return assert(Presets.decode(store)).p,full
end
local function profiles()
 local out={}; for _,x in ipairs(C.profiles) do out[x]=C.validate(x,C.defaults(x)) end
 return out
end
tests.REVIEW152D_RULES_OFF_SAFETY_CAR=function()
 -- Onglet Règles décoché en course : voiture de sécurité en escalade coupée comme le reste de l'onglet.
 local p=C.preset('Course','C',{}); assert(C.effective('C',p).safetyCarEscalation,'rules on: escalation kept')
 p.section_rules=false
 local eff=C.effective('C',p)
 assert(eff.safetyCarEscalation==false and eff.neutralization=='local' and not eff.redFlagEnabled,'rules off: no safety car escalation')
 assert(p.safetyCarEscalation==true,'stored value untouched')
end
tests.REVIEW152D_PRESET_REV13_KEYS_142=function()
 -- Préréglage Course de révision 13 (Beta 1.29 à 1.41) : clés de la 1.42 absentes, prises au défaut du profil.
 local missing={section_strategy=true,section_sanctions=true,dirtyAirEnabled=true,outLapEnabled=true,lockWearEnabled=true,firstLapCare=true,qualiTraffic=true,qualiCoolLaps=true}
 for k in pairs(C.raceKeys) do missing[k]=true end
 for k in pairs(C.sanctionKeys) do missing[k]=true end
 local p,full=oldPreset('Course','C',13,missing)
 assert(p.section_strategy and p.section_sanctions,'sections of 1.42 ticked (revision 19)')
 assert(p.strategyEnabled and p.failuresEnabled and p.sanJumpStart and p.dirtyAirEnabled and p.outLapEnabled and p.lockWearEnabled and p.towBreakEnabled,'1.42 keys at the race defaults')
 assert(p.firstLapCare==full.firstLapCare and p.firstLapCare,'first lap care at the race default')
 assert(p.strategyTyreWearPct==C.defaults('C').strategyTyreWearPct,'tyre wear at the race default')
 -- Préréglage Qualifications de révision 13 : sanctions des essais et qualifications au défaut du profil.
 local q=oldPreset('Qualifications','Q',13,missing)
 assert(q.sanTrackLimits and q.sanWrongWay and q.sanMessages and q.qualiTraffic and q.qualiCoolLaps,'qualifying sanctions and flying laps at their defaults')
end
tests.REVIEW152D_PRESET_REV14_KEYS_147_151=function()
 -- Révision 14 (Beta 1.42 à 1.51) : clés plus récentes relues au défaut de la disposition, prises au défaut du profil.
 local q=oldPreset('Qualifications','Q',14,{qualiTraffic=true,qualiCoolLaps=true})
 assert(q.qualiTraffic==true and q.qualiCoolLaps==true,'qualifying preset of revision 14: flying laps on')
 local pr=oldPreset('Essais','P',14,{qualiTraffic=true})
 assert(pr.qualiTraffic==true and pr.qualiCoolLaps==false,'practice preset: flying laps on, cool-down laps hidden')
 local c=oldPreset('Course','C',14,{firstLapCare=true})
 assert(c.firstLapCare==true,'race preset of revision 14: first lap care on')
 -- Révisions 20 et 21 des données rejouées pour la révision 14 : anciens défauts suivis, réglages gardés.
 local r=oldPreset('Course','C',14,{},{strategyTyreWearPct=75,startDelay=1})
 assert(r.strategyTyreWearPct==30 and r.startDelay==C.defaults('C').startDelay,'old defaults follow (revisions 20 and 21)')
 local kept=oldPreset('Course','C',14,{},{strategyTyreWearPct=60,startDelay=5})
 assert(kept.strategyTyreWearPct==60 and kept.startDelay==5,'tuned values kept')
 -- Révision 15 : enregistrée par cette version, choix du pilote gardé tel quel.
 local p=C.preset('Qualifications','Q',{}); p.qualiTraffic=false
 local g=C.validateGlobals(C.globalDefaults)
 local encoded=Presets.encode(assert(Presets.capture('Q sans priorite','Q',p,g)))
 assert(encoded.revision==15 and Presets.revision==15,'saved at revision 15')
 local again=assert(Presets.decode(encoded))
 assert(again.p.qualiTraffic==false,'revision 15: driver choice kept')
 local cp=C.preset('Course','C',{}); cp.firstLapCare=false; cp.strategyTyreWearPct=75
 local cagain=assert(Presets.decode(Presets.encode(assert(Presets.capture('C','C',cp,g)))))
 assert(cagain.p.firstLapCare==false and cagain.p.strategyTyreWearPct==75,'revision 15: no migration replayed')
end
tests.REVIEW152D_MIGRATION_22_PERSONAL_MARK=function()
 -- Installation de la Beta 1.50 : préréglage personnel chargé, sans marque « Perso ».
 local g=C.validateGlobals(C.globalDefaults); g.dataRevision=21; g.presetsUsed=true; g.loadedPreset='custom:Mon Q'
 local customs={[3]={name='Mon Q',profile='Q'},[5]={name='Autre',profile='C'}}
 assert(C.sessionPreset(g,'Q')=='Qualifications','before: the session preset would replace it')
 local upgraded=C.migrate(g,profiles(),customs)
 assert(g.dataRevision==C.dataRevision and C.dataRevision==22,'revision 22')
 assert(C.mark(g,'Q')==C.personalMark and C.sessionPreset(g,'Q')==nil,'personal mark set: never replaced by the session')
 assert(C.mark(g,'C')=='' and C.sessionPreset(g,'C')=='Course','other profiles untouched')
 local listed=false; for _,x in ipairs(upgraded) do if x:find('Q:',1,true)==1 then listed=true end end
 assert(listed,'listed in the upgrade notice')
 -- Une seule fois : marque effacée ensuite par le pilote (Restaurer), jamais reposée.
 C.setMark(g,'Q',''); assert(C.migrate(g,profiles(),customs)==nil and C.mark(g,'Q')=='','runs once')
 -- Préréglage supprimé, préréglage intégré ou aucune bibliothèque : aucune marque.
 local g2=C.validateGlobals(C.globalDefaults); g2.dataRevision=21; g2.loadedPreset='custom:Disparu'; C.migrate(g2,profiles(),customs)
 assert(g2.builtinMarks=='','deleted preset: no mark')
 local g3=C.validateGlobals(C.globalDefaults); g3.dataRevision=21; g3.loadedPreset='builtin:Course'; C.migrate(g3,profiles(),customs)
 assert(g3.builtinMarks=='','built-in preset: no mark')
 assert(C.markPersonal({loadedPreset='custom:Autre',builtinMarks='J=Nordschleife'},customs)=='C','profile of the entry')
end
tests.REVIEW152D_SPAWN_KEYS_AND_SWITCH=function()
 -- Sorties étalées : masquées en course et en hotlap (sans effet), ramenées au défaut.
 assert(C.hidden('C','pitExitSpread') and C.hidden('H','pitExitSpread') and not C.hidden('P','pitExitSpread') and not C.hidden('Q','pitExitSpread') and not C.hidden('J','pitExitSpread'),'hidden in race and hotlap')
 local p=C.defaults('C'); p.pitExitSpread=20; assert(C.validate('C',p).pitExitSpread==0,'race: back to its default')
 -- Arrêt obligatoire oui ou non : 1 ou 0.
 local all=profiles(); for _,x in ipairs(C.ruleProfiles) do all[x].configured=true end
 C.weekendSwitch(all,'mandatoryStops',true); assert(all.C.mandatoryStops==1 and all.Q.mandatoryStops==1,'switch on: one stop')
 C.weekendSwitch(all,'mandatoryStops',false); assert(all.C.mandatoryStops==0,'switch off: none')
 -- Longueurs des options globales en texte nommées dans K.
 local g=C.validateGlobals(C.globalDefaults); g.floodBackup=string.rep('a',C.K.floodBackupBytes+1); g.builtinMarks=string.rep('a',C.K.builtinMarksBytes+1)
 local out,errors=C.validateGlobals(g); assert(out.floodBackup=='' and out.builtinMarks=='' and errors==2,'too long: defaults')
end
return tests
