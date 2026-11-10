"""Beta 1.53 : couverture de la traduction anglaise du journal (src/journal_en.lua, fenêtre DIAGNOSTICS).
Chaque ligne écrite au journal par les bancs (contrôles PDR et étendus, intégration, empreintes, course 1.42) doit être
reconnue par un modèle de src/journal_en.lua, et sa traduction (noms de pilotes masqués) ne doit garder ni lettre
accentuée ni mot français courant. Exceptions : lignes ERROR (texte de Lua ou de CSP recopié) et lignes DEBUG
« état:raison » (codes). Résultat dans tests/journal-coverage-results.json ; code 1 si une ligne n'est pas couverte."""
import json
import re
import sys
import time
from test_pdr import runtime, APP

HOOK = """
local U=require('src/util'); local base=U.log
rawset(_G,'LOGSEEN',{})
U.log=function(q,t,level,message,index) local k=tostring(level)..'\\t'..tostring(message); LOGSEEN[k]=(LOGSEEN[k] or 0)+1; return base(q,t,level,message,index) end
"""
FRENCH = set('''de du des le la les et sur avec apres pour dans sans depuis voiture voitures arret arrets stands piste
cession cessions depassement depassements joueur pneus pneu niveau drapeau drapeaux fenetre mise jour reglage reglages
retenue retenues attente lance lances tour tours derriere devant aucun aucune oui non etat sortie relance panne usure
strategie carburant securite profil ecart vitesse frein moteur boite carrosserie lente lent immobile garee rendue rendu
prevu prevues ligne droite gauche fin course essais qualifications en au aux un une est pas plus que qui par ou
IA ia jonction emplacement apres reprise annule annulee annulees compose composes demande demandee
cassee bloquee allure ici inconnue inconnu lancement garde gardee gardees rendus rendues coupee coupees
mesure mesuree ouvert ouverte ferme fermee leve levee monte montee prete pret seule seul encore toujours deja
fichier fichiers valeur valeurs origine'''.split())
# Lignes écrites par les bancs eux-mêmes (journal factice des tests unitaires), jamais par l'app.
TEST_ONLY = re.compile(r'flood\d+|ligne \d+|row')
ACCENT = re.compile('[À-ÿ]')
WORD = re.compile(r"[A-Za-zÀ-ÿ]+")

def collect():
    seen = {}
    def suite(name, fn):
        lua = runtime(); lua.execute(HOOK)
        fn(lua)
        for k, v in lua.globals().LOGSEEN.items(): seen[k] = seen.get(k, 0) + int(v)
        print(f'{name}: {len(seen)} distinct lines so far', flush=True)
        return lua
    def pdr(lua):
        for file in [APP/'AdvancedIA.lua', *sorted((APP/'src').glob('*.lua'))]:
            lua.execute('assert(loadstring(...))', file.read_text(encoding='utf-8'))
        tests = lua.execute((APP/'tests/scenarios.lua').read_text(encoding='utf-8'))
        ext = lua.execute((APP/'tests/extended.lua').read_text(encoding='utf-8'))
        for n in ext.keys(): tests[n] = ext[n]
        for n in sorted(tests.keys()):
            try: tests[n]()
            except Exception: pass
    def integration(lua):
        lua.execute("rawset(_G,'HOST',false)")
        lua.execute((APP/'tests/integration_cases.lua').read_text(encoding='utf-8'))((APP/'AdvancedIA.lua').read_text(encoding='utf-8'))
    def golden(lua):
        run = lua.execute((APP/'tests/golden.lua').read_text(encoding='utf-8'))
        for sc in [('track', 30, 20000, 5000), ('rules', 30, 40000, 10000), ('rules', 60, 12000, 3000)]: run(*sc)
    def race(lua): lua.execute("return require('tests/race142')")()
    for name, fn in (('pdr', pdr), ('integration', integration), ('golden', golden), ('race142', race)): suite(name, fn)
    return seen

def check(lines):
    lua = runtime()
    english = lua.eval("function(m) local J=require('src/journal'); local text,rule=J.english(m,true); return text,rule~=nil end")
    problems = []; covered = 0
    for key in sorted(lines):
        level, message = key.split('\t', 1)
        text, matched = english(message)
        if level == 'ERROR' or (level == 'DEBUG' and re.fullmatch(r'[A-Z_]+:\S+', message)) or TEST_ONLY.fullmatch(message): covered += 1; continue
        words = [w for w in WORD.findall(text) if w in FRENCH or w.lower() in FRENCH]
        bad = []
        if not matched: bad.append('no rule')
        if ACCENT.search(text): bad.append('accent')
        if words: bad.append('french: ' + ' '.join(sorted(set(words))))
        if bad: problems.append({'message': message, 'english': text, 'why': bad})
        else: covered += 1
    return covered, problems

def main():
    started = time.perf_counter()
    lines = collect()
    covered, problems = check(lines)
    result = {'ok': not problems, 'lines': len(lines), 'covered': covered, 'problems': problems, 'seconds': round(time.perf_counter()-started, 1)}
    (APP/'tests/journal-coverage-results.json').write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding='utf-8')
    # Une ligne par forme (nombres remplacés par N), avec le nombre de lignes concernées.
    shapes = {}
    for p in problems:
        key = re.sub(r'\d+(\.\d+)?', 'N', p['message'])[:200]
        shapes.setdefault(key, [0, p])[0] += 1
    for key, (count, p) in sorted(shapes.items(), key=lambda x: -x[1][0])[:80]:
        print('NOT COVERED', count, p['why'], '|', p['message'][:200], '|', p['english'][:200])
    print(f"{len(lines)} distinct journal lines, {covered} covered, {len(problems)} problems", flush=True)
    raise SystemExit(bool(problems))

if __name__ == '__main__':
    main()
