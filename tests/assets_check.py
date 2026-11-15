"""Contrôle bloquant de publication (Beta 2.0.1) : un fichier chargé en continu par le jeu (police, son, image) ne change
jamais à un chemin déjà livré par une version publiée.

L'app en cours garde ces fichiers ouverts (polices chargées par DirectWrite) : la mise à jour en jeu ne peut pas les
remplacer (1.62 -> 2.0.0 refusée pour des polices réduites). Un nouveau contenu va donc dans un nouveau chemin (fonts2/).

Usage : python tests/assets_check.py <nouveau paquet.zip> <paquet publié.zip> [<paquet publié.zip> ...]
"""
import sys
import zipfile
from pathlib import PurePosixPath

PREFIX = 'apps/lua/AdvancedIA/'
LOADED = {'.ttf', '.otf', '.wav', '.ogg', '.png', '.jpg', '.jpeg', '.dds', '.bmp'}


def assets(path):
    with zipfile.ZipFile(path) as archive:
        return {name[len(PREFIX):]: archive.read(name) for name in archive.namelist()
                if name.startswith(PREFIX) and not name.endswith('/') and PurePosixPath(name).suffix.lower() in LOADED}


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    new = assets(sys.argv[1])
    bad = []
    for published in sys.argv[2:]:
        old = assets(published)
        for rel, data in sorted(new.items()):
            if rel in old and old[rel] != data:
                bad.append(f'{rel} (différent de {PurePosixPath(published.replace(chr(92), "/")).name})')
    if bad:
        print('ECHEC : fichiers chargés en continu modifiés à un chemin déjà livré (la mise à jour en jeu ne pourrait pas les remplacer) :')
        for line in bad:
            print('  ' + line)
        return 1
    print(f'OK : {len(new)} fichiers chargés en continu, aucun modifié à un chemin déjà livré ({len(sys.argv) - 2} version(s) publiée(s))')
    return 0


if __name__ == '__main__':
    sys.exit(main())
