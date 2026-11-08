"""Maps the Blender dump into the worker model's skin (bind) space for Godot."""
import json, sys, numpy as np
body = sys.argv[1] if len(sys.argv) > 1 else "male"
d = json.load(open(f'fighter_{body}.json')); s = json.load(open('worker_skeleton.json'))
names = [n for n in d['bones'] if n in s and not n.startswith('Pole')]
A = np.array([d['bones'][n] for n in names]); B = np.array([s[n][1:] for n in names])
ma, mb = A.mean(0), B.mean(0); A0, B0 = A - ma, B - mb
U_, S_, Vt = np.linalg.svd(B0.T @ A0); D = np.eye(3); D[2, 2] = np.sign(np.linalg.det(U_ @ Vt))
R = U_ @ D @ Vt; sc = (S_ * np.diag(D)).sum() / (A0 ** 2).sum(); t = mb - sc * R @ ma
out = {}
for name, p in d['pieces'].items():
    v = np.array(p['v']).reshape(-1, 3); n = np.array(p['n']).reshape(-1, 3)
    v2 = (sc * (R @ v.T)).T + t; n2 = (R @ n.T).T
    i = np.array(p['i']).reshape(-1, 3)[:, ::-1]   # Godot winds front faces clockwise
    out[name] = {"v": np.round(v2, 6).ravel().tolist(), "n": np.round(n2, 5).ravel().tolist(),
                 "b": [int(s[b][0]) for b in p['b']], "w": np.round(p['w'], 5).tolist(),
                 "i": i.ravel().tolist(), "mat": p['mat']}
json.dump(out, open(f'fighter_{body}_godot.json', 'w'))
print("ok", body, len(out))
