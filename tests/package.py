"""Archive de distribution reproductible : seulement ce que le jeu charge (point d'entrée, manifeste, icône, modules,
sons, zones de circuit, polices) et les notices du pilote. Le banc de tests et la documentation technique restent dans
le dossier de l'app (jamais chargés par le jeu) ; les paquets des versions précédentes sont retirés de dist.
Avant l'archive : la version annoncée par le README est celle du manifeste, et aucune page ne pointe vers dist/."""
from pathlib import Path
import hashlib
import re
import zipfile
from test_pdr import APP, VERSION

# Notices livrées ; le README est livré sans la bannière (docs/ n'est pas livré).
NOTES = ['README.md', 'CHANGELOG.md', 'LICENSE']
BANNER = re.compile(r'^<p align="center"><img src="docs/[^"]+"[^>]*></p>\n\n?', re.M)


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
    for folder, patterns in [('src', ['*.lua']), ('tracks', ['*.md', '*.lua']), ('sounds', ['*.wav']), ('fonts', ['*/*.ttf', '*/OFL.txt'])]:
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
            if path.name == 'README.md' and path.parent == APP:
                text, count = BANNER.subn('', path.read_bytes().decode('utf-8'), count=1)
                assert count == 1, 'README banner not found'
                info = zipfile.ZipInfo.from_file(path, name)
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, text.encode('utf-8'), compresslevel=9)
            else:
                archive.write(path, name)
    with zipfile.ZipFile(output) as archive:
        names = archive.namelist()
        assert archive.testzip() is None
        assert not any('_vendor' in name or '/tests/' in name or '/docs/' in name for name in names)
        # Beta 1.33 : jamais la sauvegarde locale de la mise à jour ; toujours le module de mise à jour (une version
        # sans lui ne pourrait plus se mettre à jour, l'app la refuse).
        assert not any(name.startswith('apps/lua/AdvancedIA/backup/') for name in names)
        for name in ('manifest.ini', 'AdvancedIA.lua', 'src/update.lua', 'src/remote.lua', *('fonts/' + f for f in fonts())):
            assert 'apps/lua/AdvancedIA/' + name in names, name
        assert 'docs/' not in archive.read('apps/lua/AdvancedIA/README.md').decode('utf-8').split('\n', 1)[0]
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.sha256').write_text(digest + '  ' + output.name + '\n', encoding='ascii')
    print(f'{output.name}: {len(files)} files, {output.stat().st_size} bytes, SHA256 {digest}')


if __name__ == '__main__':
    main()
