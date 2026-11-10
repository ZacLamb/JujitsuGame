"""List every piece of player-facing English text in scripts/ -> i18n/keys.json (sorted, unique).
Translators fill i18n/<lang>.json with {english: translation}; missing entries stay English."""
import re, glob, json, os

def visible(lit, next_ch):
    if next_ch == ':':
        return False   # dictionary key
    if any(x in lit for x in ("res://", "user://", ".json", "window.", "http", ".png", ".scn", ".glb", "stencil", "\\u", "_mv")):
        return False
    if ';' in lit and '{' in lit:
        return False
    words = re.sub(r'%[-+ 0-9.]*[sdif]', ' ', lit)
    if not re.search(r'[A-Za-zÀ-ÿ]{2,}', words):
        return False
    if re.fullmatch(r'[a-z0-9_:%./#-]+', lit):
        return False   # ids, keys, actions
    if ' ' not in lit and not re.match(r'^[A-ZÀ-Ý¡¿]', lit):
        return False
    if ' ' not in lit and ('%' in lit or '_' in lit):
        return False
    return True

keys = set()
for f in sorted(glob.glob('scripts/**/*.gd', recursive=True)):
    s = open(f).read()
    # strip comments (outside strings) roughly: only lines starting with #
    s = re.sub(r'(?m)^\s*#.*$', '', s)
    for m in re.finditer(r'"((?:[^"\\\n]|\\.)*)"(\s*:)?', s):
        lit = m.group(1)
        nxt = ':' if m.group(2) else ''
        if visible(lit, nxt):
            keys.add(lit.encode().decode('unicode_escape').encode('latin1').decode('utf-8') if '\\' in lit else lit)
keys = sorted(keys)
os.makedirs('i18n', exist_ok=True)
json.dump(keys, open('i18n/keys.json', 'w'), ensure_ascii=False, indent=0)
print(len(keys), 'keys', sum(len(k) for k in keys), 'chars')
