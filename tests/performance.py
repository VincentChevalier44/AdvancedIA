"""Mesure reproductible du noyau (9, 30 et 60 IA, 20 000 images après chauffe par défaut ; la publication mesure
RELEASE_FRAMES images avec --frames). La version précédente a été mesurée par son propre banc, sur la même machine :
report.py relit sa mesure dans docs/RELEASE_STATUS.json."""
import argparse
import hashlib
import json
import time
from test_pdr import runtime, APP, VERSION

# Images mesurées pour la publication (python tests/performance.py --frames 30000), exigées par report.py.
RELEASE_FRAMES = 30000

def plain(value):
    if hasattr(value, 'items'):
        return {k: plain(v) for k, v in value.items()}
    return value

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--profile', action='store_true')
    parser.add_argument('--frames', type=int, default=20000)
    args=parser.parse_args()
    lua=runtime()
    run=lua.execute((APP/'tests/performance.lua').read_text(encoding='utf-8'))
    results=[plain(run(time.perf_counter,count,args.frames,args.profile)) for count in [9,30,60]]
    output=APP/'tests'/'performance-current-results.json'
    result={'version':VERSION,'profiling':args.profile,'results':results,
            'sources':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (APP/'src').glob('*.lua')}}
    output.write_text(json.dumps(result,indent=2),encoding='utf-8')
    for row in results:
        print(json.dumps({k:v for k,v in row.items() if k not in {'stacks','vmstates'}}),flush=True)
        if args.profile:
            print(sorted(row['stacks'].items(),key=lambda x:x[1],reverse=True)[:12],flush=True)

if __name__=='__main__': main()
