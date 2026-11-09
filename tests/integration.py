import json
import configparser
from test_pdr import runtime, APP

lua=runtime()
manifest=configparser.ConfigParser()
manifest.read(APP/'manifest.ini',encoding='utf-8')
# Beta 1.25 : un seul rappel de dessin, l'overlay en jeu (IN_GAME) ; aucune mise à jour hors de script.update.
assert not manifest.has_section('SIM_CALLBACKS') and dict(manifest['UI_CALLBACKS'])=={'in_game':'HUMANAI__HUD'}
assert manifest['CORE']['LAZY']=='NONE'
assert 'SETUP' in manifest['WINDOW_0']['FLAGS'].split(',') and manifest['WINDOW_0']['GROUP']=='SETTINGS'
# Beta 1.45 : ni fond ni marge de CSP autour de la fenêtre (plus de cadre gris), comme SetupLab ; l'app peint tout.
assert 'NO_BACKGROUND' in manifest['WINDOW_0']['FLAGS'].split(',') and manifest['WINDOW_0'].get('PADDING')=='0,0'
assert 'background_color' not in manifest['WINDOW_0']
# Overlay en jeu : plus une fenêtre d'app (Beta 1.25), la fenêtre de réglages reste la seule.
assert not manifest.has_section('WINDOW_1')
lua.execute("rawset(_G,'HOST',false)")
import os
if os.environ.get('INT_FILTER'): lua.execute("rawset(_G,'INT_FILTER',...)", os.environ['INT_FILTER'])
# La version écrite dans le journal de session est celle du manifeste.
assert lua.eval("require('src/config').release")==manifest['ABOUT']['VERSION']
run=lua.execute((APP/'tests/integration_cases.lua').read_text(encoding='utf-8'))
cases=run((APP/'AdvancedIA.lua').read_text(encoding='utf-8'))
result={'ok':True,'cases':list(cases.values())}
# Filtre (INT_FILTER, campagne de mutations) : résultat partiel, jamais écrit à la place du résultat complet.
if not os.environ.get('INT_FILTER'):
    (APP/'tests/integration-results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False),flush=True)
