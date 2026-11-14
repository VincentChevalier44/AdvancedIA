"""Beta 1.63 : vidage des lignes de commentaire dans le paquet (tests/package.py, strip_lua). Cas limites : chaînes et
commentaires longs, commentaire après du code, chaîne courte contenant « -- », fins de ligne CRLF. Puis tout le code de
l'app : même nombre de lignes, et aucune ligne qui n'était pas un commentaire n'est modifiée."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from package import strip_lua, APP  # noqa: E402


def check(src, expected):
    got = strip_lua(src)
    assert got == expected, f'\n{src!r}\n-> {got!r}\nexpected {expected!r}'


check('-- a\nlocal x=1 -- b\n  -- c\n', '\nlocal x=1 -- b\n\n')
check('local s=[[\n-- kept\n]]\n-- gone\n', 'local s=[[\n-- kept\n]]\n\n')
check('local s=[==[\n-- kept ]]\n]==]\n', 'local s=[==[\n-- kept ]]\n]==]\n')
check('--[[ long\n-- kept\n]]\nx=1\n', '--[[ long\n-- kept\n]]\nx=1\n')
check("local a='--not' -- c\n-- gone\r\nb=2\r\n", "local a='--not' -- c\n\r\nb=2\r\n")
check('x=t[ [[a]] ]\n-- gone\n', 'x=t[ [[a]] ]\n\n')
check('---doc\n  ---- more\n', '\n\n')

files = [APP / 'AdvancedIA.lua', *sorted((APP / 'src').glob('*.lua'))]
changed = 0
for path in files:
    text = path.read_bytes().decode('utf-8')
    out = strip_lua(text)
    a, b = text.splitlines(keepends=True), out.splitlines(keepends=True)
    assert len(a) == len(b), path
    for old, new in zip(a, b):
        if old != new:
            assert old.lstrip().startswith('--') and new.strip() == '', (path, old)
            changed += 1
print(f'strip_lua: {len(files)} files, {changed} comment lines emptied, every other line unchanged')
