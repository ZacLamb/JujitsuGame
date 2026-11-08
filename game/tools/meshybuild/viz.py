import sys, json, numpy as np, bpy
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
glb, js, out = sys.argv[-3:]
d = json.load(open(js))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
m = [o for o in bpy.data.objects if o.type == 'MESH'][0]
P = np.array([m.matrix_world @ v.co for v in m.data.vertices]) * d['scale'] + np.array(d['off'])
P = P[::7]
J = d['joints']
fig, ax = plt.subplots(1, 2, figsize=(10, 10))
ax[0].scatter(P[:, 0], P[:, 2], s=0.05, c='#999'); ax[1].scatter(P[:, 1], P[:, 2], s=0.05, c='#999')
for k, v in J.items():
    if k.startswith('Pole'): continue
    ax[0].plot(v[0], v[2], 'ro', ms=4); ax[0].annotate(k, (v[0], v[2]), fontsize=6)
    ax[1].plot(v[1], v[2], 'ro', ms=4)
for a in ax: a.set_aspect('equal')
plt.savefig(out, dpi=90)
