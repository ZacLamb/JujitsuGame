"""Second pass: letterless display patterns ("%s  ·  %s", "%s\n%s") whose arguments are data
names. Wrap them in Tx.f too, so the text arguments get translated. Dry run unless --write."""
import re, sys, glob, importlib.util
spec = importlib.util.spec_from_file_location('cm', 'tools/i18n_codemod.py')
src_mod = open('tools/i18n_codemod.py').read().split('total = 0')[0]
ns = {}; exec(src_mod, ns)
def ok(lit):
    if '%s' not in lit: return False
    if any(x in lit for x in ('#', '|', '/', 'res:', '_', '%0', ':%', '%s:%s', '[color', '[b]')): return False
    words = re.sub(r'%[-+ 0-9.]*[sdif]', '', lit)
    return not re.search(r'[A-Za-zÀ-ÿ]', words)
ns['is_display'] = ok
FILES = ['scripts/main.gd', 'scripts/game_state.gd'] + [g for g in glob.glob('scripts/ui/*.gd') if 'combat_log' not in g] + glob.glob('scripts/roll/*.gd') + ['scripts/combat/raid.gd', 'scripts/world/npc.gd', 'scripts/world/world.gd']
total = 0
for f in FILES:
    s = open(f).read()
    t, c = ns['process'](s)
    if c:
        total += c
        if '--write' in sys.argv: open(f, 'w').write(t)
        else:
            import difflib
            for l in difflib.unified_diff(s.splitlines(), t.splitlines(), lineterm='', n=0):
                if l.startswith('+') and not l.startswith('+++'): print(f, l.strip()[:160])
print('wrapped', total)
