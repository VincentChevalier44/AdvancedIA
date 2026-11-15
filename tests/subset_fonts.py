# Beta 2.0.1 : ne jamais écrire le résultat par-dessus un dossier de polices déjà livré (fonts/, fonts2/) : la mise à jour
# en jeu ne peut pas remplacer une police chargée. Nouveau contenu = nouveau dossier, contrôlé par tests/assets_check.py.
import sys,os,glob,shutil
sys.path.insert(0, sys.argv[1])
from fontTools import subset
from fontTools.ttLib import TTFont
src=sys.argv[2]; out=sys.argv[3]
RANGES=[(0x20,0x7E),(0xA0,0x24F),(0x250,0x2AF),(0x2B0,0x2FF),(0x2070,0x209F),(0x2150,0x218F),(0x300,0x36F),(0x370,0x3FF),(0x400,0x52F),(0x1E00,0x1EFF),
        (0x2000,0x206F),(0x20A0,0x20CF),(0x2100,0x214F),(0x2190,0x21FF),(0x2200,0x22FF),(0x25A0,0x25FF),(0xFB00,0xFB06)]
uni=[c for a,b in RANGES for c in range(a,b+1)]
for ff in sorted(glob.glob(os.path.join(src,'fonts','*','*.ttf'))):
    o=subset.Options(); o.layout_features=['*']; o.name_IDs=['*']; o.name_languages=['*']; o.name_legacy=True
    o.hinting=True; o.legacy_kern=True; o.notdef_outline=True; o.glyph_names=False; o.drop_tables=[]
    o.symbol_cmap=True; o.recalc_bounds=False
    f=TTFont(ff); before=os.path.getsize(ff); cmap=set(f.getBestCmap())
    s=subset.Subsetter(o); s.populate(unicodes=uni); s.subset(f)
    rel=os.path.relpath(ff,src); dst=os.path.join(out,rel); os.makedirs(os.path.dirname(dst),exist_ok=True)
    f.save(dst); after=os.path.getsize(dst); kept=set(TTFont(dst).getBestCmap())
    lost=sorted(cmap-kept)
    print(rel, before, '->', after, 'glyphs', len(cmap), '->', len(kept), 'dropped blocks', sorted({hex(c>>8<<8) for c in lost})[:20])
