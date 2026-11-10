"""Wrap display format strings in Tx.f():   "Beat %s (%d)" % [a, b]  ->  Tx.f("Beat %s (%d)", [a, b])
Run once over scripts/ (idempotent: already-wrapped strings are skipped)."""
import re, sys, glob

def is_display(lit):
    if any(x in lit for x in ("res://", "user://", ".json", "window.", "http", ".png", ".scn", "%0", "#")):
        return False
    words = re.sub(r'%[-+ 0-9.]*[sdif]', ' ', lit)
    if not re.search(r'[A-Za-zÀ-ÿ]{2,}', words):
        return False
    if ' ' not in lit and (not re.match(r'^[A-ZÀ-Ý]', lit) or '%' in lit):
        return False
    if ';' in lit or 'stencil' in lit:
        return False
    if re.fullmatch(r'[a-z0-9_:%.]+', lit):
        return False
    return True

def scan_string(s, i):
    # s[i] == '"'; returns index after closing quote
    j = i + 1
    while j < len(s):
        if s[j] == '\\':
            j += 2
            continue
        if s[j] == '"':
            return j + 1
        j += 1
    return j

def operand_end(s, i):
    n = len(s)
    if i < n and s[i] in '[(':
        depth = 0
        j = i
        while j < n:
            c = s[j]
            if c == '"':
                j = scan_string(s, j)
                continue
            if c in '[({':
                depth += 1
            elif c in '])}':
                depth -= 1
                if depth == 0:
                    return j + 1
            j += 1
        return n
    # identifier / number / string chain with .attr, [idx], (call)
    j = i
    if j < n and s[j] == '"':
        j = scan_string(s, j)
    else:
        if j < n and s[j] == '-':
            j += 1
        while j < n and (s[j].isalnum() or s[j] in '_.'):
            j += 1
    while j < n and s[j] in '[(':
        j = operand_end(s, j)
        while j < n and (s[j].isalnum() or s[j] in '_.'):
            j += 1
    return j

def process(src):
    out = []
    i = 0
    n = len(src)
    count = 0
    while i < n:
        c = src[i]
        if c == '#':   # comment to end of line
            k = src.find('\n', i)
            k = n if k < 0 else k
            out.append(src[i:k]); i = k; continue
        if c == '"':
            if src[i:i+3] == '"""':
                k = src.find('"""', i + 3) + 3
                out.append(src[i:k]); i = k; continue
            k = scan_string(src, i)
            lit = src[i+1:k-1]
            m = re.match(r'[ \t]*%[ \t]*', src[k:])
            prev = src[max(0, i-6):i]
            if m and is_display(lit) and not prev.endswith('Tx.f(') and not prev.endswith('Tx.s('):
                a = k + m.end()
                e = operand_end(src, a)
                rhs = src[a:e].strip()
                if rhs:
                    out.append('Tx.f("%s", %s)' % (lit, rhs))
                    count += 1
                    i = e
                    continue
            out.append(src[i:k]); i = k; continue
        out.append(c); i += 1
    return ''.join(out), count

total = 0
for f in sorted(glob.glob('scripts/**/*.gd', recursive=True)):
    if f.endswith('tx.gd') or f.endswith('lang.gd'):
        continue
    s = open(f).read()
    t, c = process(s)
    if c:
        open(f, 'w').write(t)
        total += c
        print(c, f)
print('wrapped', total)
