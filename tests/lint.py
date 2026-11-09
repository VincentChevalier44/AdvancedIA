"""Analyse lexicale des portées Lua via luaparser (pas une recherche par regex)."""
from pathlib import Path
import json
import sys
sys.path.insert(0,str(Path(__file__).parent/'_vendor'))
from luaparser import ast
from luaparser.astnodes import Node

APP=Path(__file__).resolve().parents[1]
STANDARD={'require','type','tostring','tonumber','pairs','ipairs','next','pcall','xpcall','error','assert','rawget','math','string','table','select','unpack','setmetatable'}

class Checker:
    def __init__(self,path):
        self.path=path
        self.scopes=[{}]
        self.errors=[]
        self.allowed=set(STANDARD)
        if path.name in {'snapshot.lua','applier.lua'}: self.allowed|={'ac','physics'}
        # Lecture de la base des voitures (content/cars), seulement dans le module de lecture.
        if path.name=='snapshot.lua': self.allowed|={'io','vec3'}
        # Journal de session sur disque : écriture et horodatage, seulement dans l'applicateur.
        if path.name=='applier.lua': self.allowed|={'io','os','vec3','vec4'}
        if path.name in {'ui.lua','widgets.lua'}: self.allowed|={'ui','rgbm','vec2'}
        # Beta 1.49 : consigne de l'app inerte (ancienne version installée), dessinée et dite au journal de CSP.
        if path.name=='oldinstall.lua': self.allowed|={'ui','rgbm','vec2','ac'}
        # Mise à jour depuis GitHub (Beta 1.33) : réseau, empreinte, zips et redémarrage, seulement dans le port.
        if path.name=='remote.lua': self.allowed|={'_G','ac','io','os'}
        if path.name=='AdvancedIA.lua': self.allowed|={'_G','HUMANAI','script'}
    def report(self,node,message):
        token=getattr(node,'_first_token',None)
        self.errors.append(f'{self.path.name}:{getattr(token,"line",0)}: {message}')
    def declare(self,node):
        if type(node).__name__=='Name': self.scopes[-1][node.id]=[node,0]
    def name(self,node,write=False):
        for scope in reversed(self.scopes):
            if node.id in scope:
                if not write: scope[node.id][1]+=1
                return
        if node.id not in self.allowed or (write and node.id!='HUMANAI'):
            self.report(node,('global write: ' if write else 'global read: ')+node.id)
    def end_scope(self):
        for name,(node,reads) in self.scopes.pop().items():
            if reads==0 and not name.startswith('_'): self.report(node,'unused local: '+name)
    def block(self,node,new=True):
        if new: self.scopes.append({})
        self.visit(node)
        if new: self.end_scope()
    def visit(self,node,write=False):
        if isinstance(node,list):
            for item in node: self.visit(item)
            return
        if not isinstance(node,Node): return
        kind=type(node).__name__
        if kind=='Name': self.name(node,write); return
        if kind=='Index':
            self.visit(node.value)
            if str(node.notation).endswith('SQUARE'): self.visit(node.idx)
            return
        if kind=='Field':
            if node.between_brackets: self.visit(node.key)
            self.visit(node.value); return
        if kind=='Invoke':
            self.visit(node.source); self.visit(node.args); return
        if kind=='LocalAssign':
            self.visit(node.values)
            for target in node.targets: self.declare(target)
            return
        if kind=='Assign':
            self.visit(node.values)
            for target in node.targets: self.visit(target,True)
            return
        if kind in {'LocalFunction','Function','AnonymousFunction','Method'}:
            if kind=='LocalFunction': self.declare(node.name)
            elif kind in {'Function','Method'}: self.visit(node.name,True)
            self.scopes.append({})
            for arg in node.args: self.declare(arg)
            self.visit(node.body)
            self.end_scope(); return
        if kind=='Fornum':
            self.visit(node.start); self.visit(node.stop); self.visit(node.step)
            self.scopes.append({}); self.declare(node.target); self.visit(node.body); self.end_scope(); return
        if kind=='Forin':
            self.visit(node.iter); self.scopes.append({})
            for target in node.targets: self.declare(target)
            self.visit(node.body); self.end_scope(); return
        if kind in {'While','Repeat'}:
            self.scopes.append({}); self.visit(node.test); self.visit(node.body); self.end_scope(); return
        if kind in {'If','ElseIf'}:
            self.visit(node.test); self.block(node.body); self.visit(node.orelse); return
        if kind=='Else': self.block(node.body); return
        if kind=='Do': self.block(node.body); return
        if kind=='Call' and type(node.func).__name__=='Name' and node.func.id=='require':
            if len(node.args)!=1 or type(node.args[0]).__name__!='String': self.report(node,'dynamic require forbidden')
            else:
                value=node.args[0].s
                if isinstance(value,bytes): value=value.decode()
                if value not in {'bit','ffi'} and not (value.startswith('src/') and '..' not in value): self.report(node,'external require: '+value)
        for key,value in vars(node).items():
            if not key.startswith('_') and key!='comments': self.visit(value)
    def run(self):
        self.visit(ast.parse(self.path.read_text(encoding='utf-8')))
        self.end_scope()
        return self.errors

# Champs lus sur les structures FFI de CSP : un membre non déclaré lève une erreur dans le jeu (pas dans l'hôte de test).
def sdk_fields():
    import re
    declared=json.loads((APP/'tests/sdk-fields.json').read_text(encoding='utf-8'))
    source=(APP/'src/snapshot.lua').read_text(encoding='utf-8')
    errors=[]
    for prefix,cls in (('r','ac.StateSim'),('raw','ac.StateCar')):
        for name in sorted(set(re.findall(r'\b'+prefix+r'\.(\w+)',source))):
            if name not in declared[cls]: errors.append(f'snapshot.lua: {prefix}.{name} absent de {cls}')
    return errors

def duplicates(path):
    """Une fonction de module ou locale définie deux fois au même niveau : la seconde masque la première sans erreur
    (régression 1.5.0 : U.wrap de texte masquait U.wrap d'angle)."""
    tree=ast.parse(path.read_text(encoding='utf-8'))
    seen={}; errors=[]
    for node in tree.body.body:
        kind=type(node).__name__; name=None
        if kind in ('Function','Method'): name=ast.to_lua_source(node.name).strip()
        elif kind=='LocalFunction': name='local '+node.name.id
        elif kind=='Assign':
            for target in node.targets:
                # Membres du module seulement : les bascules comme newKeys.open sont voulues.
                if type(target).__name__=='Index' and ast.to_lua_source(target).strip().startswith('M.'): name=ast.to_lua_source(target).strip()
        if name:
            line=getattr(getattr(node,'_first_token',None),'line',0)
            if name in seen: errors.append(f'{path.name}:{line}: duplicate definition: {name} (first at line {seen[name]})')
            else: seen[name]=line
    return errors
def main():
    files=[APP/'AdvancedIA.lua',*sorted((APP/'src').glob('*.lua'))]
    errors=[error for file in files for error in Checker(file).run()]+[error for file in files for error in duplicates(file)]+sdk_fields()
    for error in errors: print(error)
    print(f'{len(files)} Lua files, {len(errors)} lint errors')
    # Résultat structuré, lu par report.py.
    result={'ok':not errors,'files':len(files),'errors':errors}
    (APP/'tests/lint-results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    raise SystemExit(bool(errors))

if __name__=='__main__': main()
