import json, glob, re, sys
keys = json.load(open('i18n/keys.json'))
pt, es = {}, {}
spec = re.compile(r'%[-+0#]*\d*(?:\.\d+)?[sdifxXc%]|\{[a-z]\}')
bad = 0
for f in sorted(glob.glob('i18n/src/b*.json')):
    for idx, p, e in json.load(open(f)):
        if isinstance(idx, int): idx = keys[idx]
        en = idx
        want = sorted(spec.findall(en))
        for lang, t, d in (('pt', p, pt), ('es', e, es)):
            if sorted(spec.findall(t)) != want:
                print('SPEC MISMATCH', lang, idx, repr(en), '->', repr(t)); bad += 1
            # order of %-specifiers must match too (Godot % is positional)
            if [x for x in spec.findall(t) if x.startswith('%') and x != '%%'] != [x for x in spec.findall(en) if x.startswith('%') and x != '%%']:
                print('ORDER', lang, idx, repr(en), '->', repr(t)); bad += 1
            if t != en: d[en] = t
json.dump(pt, open('i18n/pt_BR.json', 'w'), ensure_ascii=False, indent=0, sort_keys=True)
json.dump(es, open('i18n/es.json', 'w'), ensure_ascii=False, indent=0, sort_keys=True)
print('pt', len(pt), 'es', len(es), 'bad', bad)
sys.exit(1 if bad else 0)
