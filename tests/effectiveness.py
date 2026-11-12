"""Beta 1.59: settings-effectiveness gate. Every profile setting must be live.

Static check: the setting is read by a runtime module other than the declarations and the settings window
(src/ui.lua). The only exceptions are settings listed in UI_ONLY, which are drawn by the interface itself.

Dynamic check: the same generic scene runs twice, with the setting at two ends (on/off, min/max, first/last choice),
in a profile where it applies. The engine's commands and its journal must change, or a targeted test in tests/ must
name the setting (a situation the generic scene cannot build: rain, a stop, a sanction...).

A setting that fails both checks is reported as DEAD and fails the gate. Results go to
tests/effectiveness-results.json.
"""
import json
import re
from test_pdr import APP, runtime

DECLARATIONS = {'config.lua', 'lang.lua', 'lang_en.lua', 'presets.lua', 'tips.lua', 'tips_en.lua', 'groups.lua', 'ui.lua'}
# Settings read only by the interface (window, overlay and the player's panel drawn by src/ui.lua and AdvancedIA.lua).
UI_ONLY = set()
# Settings frozen on purpose (hidden in the window, always one value): reported, never dead.
FIXED = {'lightsYellow': 'yellow panels always on, switch hidden since Beta 1.59'}
SCENE = r"""
local F=require('tests/fixture')
local C=require('src/config')
local E=require('src/engine')
local key,value,profile=...
local e,f=F.scene(profile,5)
local p=e.profiles[profile]
for _,g in ipairs(C.sections) do p['section_'..g]=true end
p[key]=value; E.changed(e)
f.sessionLaps=12; f.leaderLaps=3; f.timedRace=false
for i=1,f.count do f.cars[i].lap=3 end
-- Peloton : joueur derrière deux IA proches, une IA plus lente devant, une IA arrêtée en piste plus loin.
F.place(f,1,-60,160); F.place(f,2,0,150); F.place(f,3,25,150,1.5); F.place(f,4,300,90); F.place(f,5,1500,0)
f.cars[3].slip=0
local sum=0
local function mix(x) if type(x)=='number' and x==x and x<1e8 then sum=(sum*31+math.floor(x*1000+0.5))%2147483647 elseif x==true then sum=(sum*31+7)%2147483647 end end
for step=1,240 do
 F.tick(e,f,1/30,true)
 if step%10==0 then
  for i=2,f.count do local c=e.commands[i]
   mix(c.offset); mix(c.level); mix(c.caution); mix(c.aggression); mix(c.speedLimit); mix(c.brake); mix(c.throttleLimit); mix(c.yellowLimit); mix(c.rulePit); mix(c.levelScale)
   local s=e.states[i]; mix(s.offset)
  end
 end
end
local lines=0
for k=1,e.log.limit do local r=e.log[k]; if r and r.message then lines=lines+1; for b=1,#r.message,7 do sum=(sum*31+r.message:byte(b))%2147483647 end end end
return sum,lines
"""


def main():
    lua = runtime()
    for file in [APP/'AdvancedIA.lua', *sorted((APP/'src').glob('*.lua'))]:
        lua.execute('assert(loadstring(...))', file.read_text(encoding='utf-8'))
    config = lua.eval("require('src/config')")
    scene = lua.eval('function(...) local f=assert(loadstring(...)); return f end')(SCENE)
    files = [APP/'AdvancedIA.lua', *sorted((APP/'src').glob('*.lua'))]
    sources = {p.name: p.read_text(encoding='utf-8') for p in files if p.name not in DECLARATIONS}
    tests = {p.name: p.read_text(encoding='utf-8') for p in (APP/'tests').glob('*.lua') if p.name != 'fixture.lua'}
    rows, dead = [], []
    for s in config['schema'].values():
        key = s['key']
        word = re.compile(r'\b'+re.escape(key)+r'\b')
        readers = sorted(n for n, src in sources.items() if word.search(src))
        named = sorted(n for n, src in tests.items() if word.search(src))
        race, practice, hidden = config['raceKeys'][key], config['sanctionPracticeKeys'][key], config['hidden']
        profile = 'C' if race or config['sanctionRaceKeys'][key] or s['group'] in ('rules', 'strategy') else 'Q' if practice else next(
            (p for p in ('J', 'Q', 'C', 'P') if not hidden(p, key)), 'C')
        if s['choices']:
            choices = list(s['choices'].values()); ends = (choices[0], choices[-1])
        elif s['min'] is not None:
            ends = (s['min'], s['max'])
        else:
            ends = (True, False)
        a, b = scene(key, ends[0], profile), scene(key, ends[1], profile)
        moved = a != b
        # Beta 1.60: a setting whose slice is not delivered (config.pendingKeys) is hidden and held at its default: reported, never dead.
        status = 'pending' if config['pendingKeys'][key] else 'live' if readers and moved else 'targeted' if readers and named else 'ui' if key in UI_ONLY else 'fixed' if key in FIXED else 'DEAD'
        if status == 'DEAD':
            dead.append(key)
        rows.append({'key': key, 'profile': profile, 'ends': [str(x) for x in ends], 'readers': readers,
                     'tests': named[:6], 'scene_changes': moved, 'status': status})
    # Beta 1.61: a pending GLOBAL setting (config.pendingGlobals) is reported too.
    for key in sorted(config['pendingGlobals']):
        rows.append({'key': key, 'status': 'pending', 'readers': [], 'tests': [], 'profile': 'global'})
    counts = {k: sum(1 for r in rows if r['status'] == k) for k in ('live', 'targeted', 'ui', 'fixed', 'pending', 'DEAD')}
    (APP/'tests/effectiveness-results.json').write_text(json.dumps({'ok': not dead, 'counts': counts, 'dead': dead, 'rows': rows},
                                                                    ensure_ascii=False, indent=1)+'\n', encoding='utf-8')
    print(f"{len(rows)} settings: {counts['live']} change the generic scene, {counts['targeted']} covered by a targeted test, "
          f"{counts['ui']} interface only, {counts['fixed']} fixed on purpose, {counts['pending']} pending (hidden), {counts['DEAD']} dead{(': '+', '.join(dead)) if dead else ''}")
    assert not dead, 'dead settings: '+', '.join(dead)


if __name__ == '__main__':
    main()
