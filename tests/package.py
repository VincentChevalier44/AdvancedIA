"""Archive de distribution reproductible : seulement ce que le jeu charge (point d'entrée, manifeste, icône, modules,
sons, zones de circuit, polices) et les notices du pilote. Le banc de tests et la documentation technique restent dans
le dossier de l'app (jamais chargés par le jeu) ; les paquets des versions précédentes sont retirés de dist.
Avant l'archive : la version annoncée par le README est celle du manifeste, et aucune page ne pointe vers dist/."""
from pathlib import Path
import hashlib
import re
import zipfile
from test_pdr import APP, VERSION

# Notices livrées. Beta 1.63 (paquet allégé, décision du pilote) : le README livré est une notice courte
# (tests/README_package.md ; le guide complet reste sur GitHub) et le CHANGELOG livré ne garde que la version du
# paquet. Les deux restent livrés : la mise à jour intégrée n'efface jamais un fichier retiré d'un paquet.
NOTES = ['README.md', 'CHANGELOG.md', 'LICENSE']
REPO = 'https://github.com/VincentChevalier44/AdvancedIA'
LONG_OPEN = re.compile(r'\[(=*)\[')


def _long_end(text, m):
    close = text.find(']' + m.group(1) + ']', m.end())
    return len(text) if close < 0 else close + len(m.group(1)) + 2


def strip_lua(text):
    """Beta 1.63 : chaque ligne qui n'est qu'un commentaire court (« -- … ») devient vide ; le nombre de lignes ne
    change pas (les numéros des erreurs restent justes). Jamais une ligne commencée dans une chaîne longue, un
    commentaire long ou une chaîne courte continuée ; jamais un commentaire long (--[[ … ]]) ni un commentaire placé
    après du code."""
    covered = []  # (début, fin) des chaînes et commentaires longs et des chaînes courtes
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith('--', i):
            m = LONG_OPEN.match(text, i + 2)
            if m:
                end = _long_end(text, m)
                covered.append((i, end))
                i = end
            else:
                nl = text.find('\n', i)
                i = n if nl < 0 else nl
        elif c in '"\'':
            j = i + 1
            while j < n and text[j] != c:
                if text[j] == '\\':
                    j += 1
                elif text[j] == '\n':
                    break
                j += 1
            covered.append((i, j + 1))
            i = j + 1
        elif c == '[' and LONG_OPEN.match(text, i):
            end = _long_end(text, LONG_OPEN.match(text, i))
            covered.append((i, end))
            i = end
        else:
            i += 1
    out, pos, k = [], 0, 0
    for line in text.splitlines(keepends=True):
        while k < len(covered) and covered[k][1] <= pos:
            k += 1
        inside = k < len(covered) and covered[k][0] < pos < covered[k][1]
        body = line.rstrip('\r\n')
        stripped = body.lstrip()
        if not inside and stripped.startswith('--') and not LONG_OPEN.match(stripped, 2):
            out.append(line[len(body):])
        else:
            out.append(line)
        pos += len(line)
    result = ''.join(out)
    assert result.count('\n') == text.count('\n'), 'line count changed'
    return result


def packaged_readme():
    """Notice courte livrée dans le paquet (le README complet, avec sa bannière, reste sur GitHub)."""
    return (APP / 'tests/README_package.md').read_text(encoding='utf-8').replace('{VERSION}', VERSION)


def packaged_changelog():
    """Seulement la section de la version du paquet, et le lien vers l'historique complet sur GitHub."""
    full = (APP / 'CHANGELOG.md').read_text(encoding='utf-8')
    found = re.search(r'^## ' + re.escape(VERSION) + r'\b.*?(?=^## |\Z)', full, re.S | re.M)
    assert found, f'CHANGELOG: no section for {VERSION}'
    return ('# Changelog\n\nThis package lists the changes of ' + VERSION + ' only. Full history: '
            + REPO + '/blob/main/CHANGELOG.md\n\n' + found.group(0).rstrip() + '\n')


def check_docs():
    """README à jour (version du manifeste) ; aucun lien vers dist/, qui n'est jamais versionné."""
    readme = (APP / 'README.md').read_text(encoding='utf-8')
    found = re.search(r'\*\*Current version:\*\* (Beta \d+(?:\.\d+)*)', readme)
    assert found and found.group(1) == VERSION, f'README: current version {found and found.group(1)} instead of {VERSION}'
    pages = [p for p in APP.rglob('*.md') if not {'_vendor', 'dist', 'backup'} & set(p.relative_to(APP).parts)]
    for page in pages:
        for target in re.findall(r'\]\(([^)\s]+)\)', page.read_text(encoding='utf-8')):
            assert not re.match(r'(\./)?(\.\./)*dist/', target), f'{page.relative_to(APP).as_posix()}: link to {target}'


def fonts():
    """Polices exigées par l'app (src/applier.lua, fontFiles) et la licence de chaque famille."""
    source = (APP / 'src/applier.lua').read_text(encoding='utf-8')
    block = re.search(r'local fontFiles=\{(.*?)\}', source, re.S).group(1)
    names = re.findall(r"'([^']+\.ttf)'", block)
    assert names, 'fontFiles not found in src/applier.lua'
    return names + sorted({name.split('/')[0] + '/OFL.txt' for name in names})


def main():
    check_docs()
    files = [APP / name for name in ['AdvancedIA.lua', 'manifest.ini', 'icon.png', *NOTES]]
    for folder, patterns in [('src', ['*.lua']), ('tracks', ['*.md', '*.lua']), ('sounds', ['*.wav']), ('fonts2', ['*/*.ttf', '*/OFL.txt'])]:
        for pattern in patterns:
            files.extend((APP / folder).glob(pattern))
    files = sorted({p for p in files if p.is_file()})
    dist = APP / 'dist'
    dist.mkdir(exist_ok=True)
    output = dist / f'AdvancedIA-{VERSION.replace(" ", "-")}.zip'
    for old in [*dist.glob('AdvancedIA-*.zip'), *dist.glob('AdvancedIA-*.sha256')]:
        if old.stem != output.stem:
            old.unlink()
    prefix = Path('apps/lua/AdvancedIA')
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            name = (prefix / path.relative_to(APP)).as_posix()
            text = None
            if path.name == 'README.md' and path.parent == APP:
                text = packaged_readme()
            elif path.name == 'CHANGELOG.md' and path.parent == APP:
                text = packaged_changelog()
            elif path.suffix == '.lua':
                text = strip_lua(path.read_bytes().decode('utf-8'))
            if text is None:
                archive.write(path, name)
            else:
                info = zipfile.ZipInfo.from_file(path, name)
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, text.encode('utf-8'), compresslevel=9)
    with zipfile.ZipFile(output) as archive:
        names = archive.namelist()
        assert archive.testzip() is None
        assert not any('_vendor' in name or '/tests/' in name or '/docs/' in name for name in names)
        # Beta 1.33 : jamais la sauvegarde locale de la mise à jour ; toujours le module de mise à jour (une version
        # sans lui ne pourrait plus se mettre à jour, l'app la refuse).
        assert not any(name.startswith('apps/lua/AdvancedIA/backup/') for name in names)
        for name in ('manifest.ini', 'AdvancedIA.lua', 'src/update.lua', 'src/remote.lua', *('fonts2/' + f for f in fonts())):
            assert 'apps/lua/AdvancedIA/' + name in names, name
        assert 'docs/' not in archive.read('apps/lua/AdvancedIA/README.md').decode('utf-8').split('\n', 1)[0]
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.sha256').write_text(digest + '  ' + output.name + '\n', encoding='ascii')
    print(f'{output.name}: {len(files)} files, {output.stat().st_size} bytes, SHA256 {digest}')


if __name__ == '__main__':
    main()
