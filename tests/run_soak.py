import json
import hashlib
import time
from test_pdr import runtime, APP, VERSION

lua=runtime()
source=[APP/'AdvancedIA.lua',APP/'manifest.ini',*sorted((APP/'src').glob('*.lua'))]
hashes={p.relative_to(APP).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in source}
bench=lua.execute((APP/'tests/soak.lua').read_text(encoding='utf-8'))
def progress(frames,total,memory):
    print(f'{frames}/{total} frames; memory={memory:.1f} KB',flush=True)
result=dict(bench(time.perf_counter,progress))
result['version']=VERSION
result['sources']=hashes
(APP/'tests/soak-results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2),flush=True)
raise SystemExit(0 if result['ok'] else 1)
