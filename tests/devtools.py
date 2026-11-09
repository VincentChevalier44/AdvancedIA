"""Outils de développement (hors jeu) : comparaison d'arborescences, sauvegarde et installation jeu fermé.

  python devtools.py tree <dossier A> <dossier B>
  python devtools.py install <dossier préparé> <copie de référence de l'app installée> <version installée> <nouvelle version>

L'installation refuse si Assetto Corsa tourne, sauvegarde l'app et les réglages dans _AdvancedIA_archives, copie
les fichiers changés, puis vérifie la copie.

Chemins : ADVANCEDIA_GAME (dossier d'Assetto Corsa) et ADVANCEDIA_SETTINGS (réglages des apps Lua de CSP) ; par
défaut, ceux de la machine de l'auteur."""
import hashlib
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

GAME = Path(os.environ.get('ADVANCEDIA_GAME', 'D:/SteamLibrary/steamapps/common/assettocorsa'))
LIVE = GAME / 'apps/lua/AdvancedIA'
ARCHIVES = GAME / '_AdvancedIA_archives'
SETTINGS = Path(os.environ.get('ADVANCEDIA_SETTINGS', Path.home() / 'Documents/Assetto Corsa/cfg/extension/state/lua/app'))
SKIP = {'__pycache__'}
# Mise à jour depuis l'app (Beta 1.33) : sauvegarde, dépôt et repères propres à chaque installation, jamais copiés ni
# retirés par l'installation, jamais comparés.
LOCAL = {'backup'}


def files(root):
    root = Path(root)
    out = {}
    for p in root.rglob('*'):
        parts = p.relative_to(root).parts
        if p.is_file() and not SKIP & set(parts) and parts[0] not in LOCAL:
            out[p.relative_to(root).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return out


def tree(a, b, quiet=False):
    fa, fb = files(a), files(b)
    diffs = sorted(k for k in fa.keys() | fb.keys() if fa.get(k) != fb.get(k))
    if not quiet:
        for k in diffs:
            print(('MODIFIE ' if k in fa and k in fb else 'SEUL A ' if k in fa else 'SEUL B ') + k)
        print(f'{len(fa)} | {len(fb)} fichiers ; différences : {len(diffs)}')
    return diffs


def running():
    out = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq acs.exe'], capture_output=True, text=True).stdout
    return 'acs.exe' in out.lower()


def install(stage, baseline, current, new):
    if running():
        raise SystemExit('ARRET : jeu ouvert')
    # L'app installée doit être celle dont la version préparée est partie : un fichier ajouté depuis serait retiré.
    if tree(baseline, LIVE, quiet=True):
        tree(baseline, LIVE)
        raise SystemExit('ARRET : l app installée a changé depuis la copie de référence')
    ARCHIVES.mkdir(exist_ok=True)
    app_zip = ARCHIVES / f'AdvancedIA-{current}-sauvegarde-avant-{new}.zip'
    set_zip = ARCHIVES / f'AdvancedIA-reglages-{current}-avant-{new}.zip'
    for target, root, names in ((app_zip, LIVE, None), (set_zip, SETTINGS, ('AdvancedIA.ini', 'AdvancedIA.ini.bak'))):
        with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as z:
            paths = [root / n for n in names] if names else [p for p in root.rglob('*') if p.is_file()]
            for p in paths:
                if p.exists():
                    z.write(p, Path('AdvancedIA') / p.relative_to(root) if not names else p.name)
        with zipfile.ZipFile(target) as z:
            if z.testzip() is not None:
                raise SystemExit(f'ARRET : archive illisible {target}')
    print(f'sauvegardes : {app_zip.name}, {set_zip.name}')
    if running():
        raise SystemExit('ARRET : jeu ouvert avant la copie')
    diffs = tree(stage, LIVE, quiet=True)
    for rel in diffs:
        src, dst = Path(stage) / rel, LIVE / rel
        if src.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            # Date de modification neuve : CSP a gardé l'ancien code de la 1.44 après une copie qui conservait
            # les dates (shutil.copy2) ; le contenu est copié, la date est celle de la copie.
            shutil.copyfile(src, dst)
            os.utime(dst, None)
            print('COPIE ' + rel)
        elif dst.exists():
            dst.unlink()
            print('RETIRE ' + rel)
    left = tree(stage, LIVE, quiet=True)
    print('vérification après copie : ' + ('OK' if not left else f'{len(left)} différence(s)'))
    if left:
        raise SystemExit(1)


if __name__ == '__main__':
    if sys.argv[1] == 'tree':
        sys.exit(1 if tree(sys.argv[2], sys.argv[3]) else 0)
    if sys.argv[1] == 'install':
        install(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
