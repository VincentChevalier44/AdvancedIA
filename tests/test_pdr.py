"""Banc LuaJIT du PDR. Aucun fichier du jeu n'est modifié par les tests."""
from pathlib import Path
import configparser
import json
import re
import sys
import time
sys.path.insert(0,str(Path(__file__).parent/'_vendor'))
from lupa.luajit21 import LuaRuntime

APP = Path(__file__).resolve().parents[1]
_manifest = configparser.ConfigParser()
_manifest.read(APP/'manifest.ini',encoding='utf-8')
VERSION = _manifest['ABOUT']['VERSION']

def runtime(root=APP):
    """LuaJIT avec les globales du jeu à faux et une métatable stricte des globales ; modules lus dans root."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path = ... .. '/?.lua;' .. package.path", Path(root).as_posix())
    lua.execute("""
      script={}; HUMANAI=false
      ac={}; physics={}; ui={}; rgbm=false; vec2=false; vec4=false
      setmetatable(_G, {
        __index=function(_,k) error('undeclared global read: '..tostring(k),2) end,
        __newindex=function(_,k) error('undeclared global write: '..tostring(k),2) end
      })
    """)
    return lua

def catalog():
    """Situations cataloguées dans le PDR (lignes « | T01 | » des tableaux), chacune portée par un test du même nom."""
    return re.findall(r'^\| ([TFQRMLPSE]\d{2}) \|', (APP/'HumanAI_PDR_v1.0.md').read_text(encoding='utf-8'), re.M)

def main():
    lua = runtime()
    for file in [APP/'AdvancedIA.lua', *sorted((APP/'src').glob('*.lua'))]:
        lua.execute('assert(loadstring(...))', file.read_text(encoding='utf-8'))
    tests = lua.execute((APP/'tests/scenarios.lua').read_text(encoding='utf-8'))
    extended = lua.execute((APP/'tests/extended.lua').read_text(encoding='utf-8'))
    for name in extended.keys():
        assert name not in tests
        tests[name] = extended[name]
    names = catalog()
    assert names and all(name in tests for name in names), [name for name in names if name not in tests]
    results = {}
    for name in sorted(tests.keys()):
        started = time.perf_counter()
        try:
            tests[name]()
            results[name] = {'ok': True, 'seconds': round(time.perf_counter()-started,4)}
            print(f'PASS {name}', flush=True)
        except Exception as exc:
            results[name] = {'ok': False, 'error': str(exc)}
            print(f'FAIL {name}: {exc}', flush=True)
    (APP/'tests/results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    failures = sum(not item.get('ok',True) for item in results.values())
    print(f'{len(results)} checks, {failures} failures',flush=True)
    raise SystemExit(bool(failures))

if __name__ == '__main__':
    main()
