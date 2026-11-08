"""Decimate a Meshy character, skin it to an armature built on its estimated joints, dump JSON.
python3 -I skin.py <glb> <joints.json> <name> <faces>"""
import sys, json, numpy as np, bpy, bmesh
from mathutils import Vector
GLB, JS, NAME, FACES = sys.argv[-4], sys.argv[-3], sys.argv[-2], int(sys.argv[-1])
d = json.load(open(JS)); J = {k: Vector(v) for k, v in d['joints'].items()}
S, OFF = d['scale'], Vector(d['off'])
# worker hierarchy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="/home/claude/tatame/assets/models/worker.glb")
wa = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
PARENT = {b.name: (b.parent.name if b.parent else None) for b in wa.data.bones}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
m = [o for o in bpy.data.objects if o.type == 'MESH'][0]
# bake transform into skin space
m.data.transform(m.matrix_world); m.matrix_world.identity()
from mathutils import Matrix
m.data.transform(Matrix.Translation(OFF) @ Matrix.Scale(S, 4))
bpy.context.view_layer.objects.active = m; m.select_set(True)
# weld coincident verts (Meshy splits along UV seams) so heat weighting sees one surface
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0005); bpy.ops.object.mode_set(mode='OBJECT')
n0 = len(m.data.polygons)
dec = m.modifiers.new('dec', 'DECIMATE'); dec.ratio = FACES / n0; dec.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier='dec')
print('faces', n0, '->', len(m.data.polygons))
# armature on the joints
CHILD = {"Hips": "Abdomen", "Abdomen": "Torso", "Torso": "Neck", "Neck": "Head", "Head": None,
         "UpperLeg": "LowerLeg", "LowerLeg": "Foot", "Foot": None, "Shoulder": "UpperArm",
         "UpperArm": "LowerArm", "LowerArm": "Palm", "Palm": "Fingers", "Fingers": "Tip"}
DEFORM = ["Hips", "Abdomen", "Torso", "Neck", "Head"] + [p + s for s in (".L", ".R") for p in
          ("Shoulder", "UpperArm", "LowerArm", "Palm", "Fingers", "UpperLeg", "LowerLeg", "Foot")]
ad = bpy.data.armatures.new('A'); ao = bpy.data.objects.new('A', ad); bpy.context.scene.collection.objects.link(ao)
bpy.context.view_layer.objects.active = ao; bpy.ops.object.mode_set(mode='EDIT')
for n in DEFORM:
    base, side = (n.split('.') + [''])[:2]
    side = '.' + side if side else ''
    b = ad.edit_bones.new(n); b.head = J[n]
    c = CHILD.get(base)
    if c and (c + side) in J:
        b.tail = J[c + side]
    elif c and c in J:
        b.tail = J[c]
    elif base == "Head":
        b.tail = J[n] + Vector((0, 0, 0.22))
    elif base == "Foot":
        b.tail = J[n] + Vector((0, -0.14, -0.06))
    if (b.tail - b.head).length < 0.01:
        b.tail = b.head + Vector((0, 0, 0.05))
for n in DEFORM:
    p = PARENT.get(n)
    while p and p not in DEFORM:
        p = PARENT.get(p)
    if p:
        ad.edit_bones[n].parent = ad.edit_bones[p]
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT'); m.select_set(True); ao.select_set(True)
bpy.context.view_layer.objects.active = ao
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
vg = {g.index: g.name for g in m.vertex_groups}
empty = [g.name for g in m.vertex_groups if not any(g.index in [x.group for x in v.groups] for v in list(m.data.vertices)[::7])]
print('empty groups', empty)
# texture
img = None
mat = m.data.materials[0]
for nd in mat.node_tree.nodes:
    if nd.type == 'TEX_IMAGE' and any(l.to_socket.name == 'Base Color' for l in nd.outputs[0].links):
        img = nd.image
img.scale(1024, 1024)
img.filepath_raw = f"/home/claude/meshybuild/{NAME}_albedo.png"; img.file_format = 'PNG'; img.save()
# dump (split per-loop for UVs)
me = m.data; me.calc_loop_triangles()
uvl = me.uv_layers.active.data
V, N, UV, B, Wt, I = [], [], [], [], [], []
key = {}
nobones = 0
for t in me.loop_triangles:
    tri = []
    for li, vi in zip(t.loops, t.vertices):
        uv = tuple(round(x, 5) for x in uvl[li].uv)
        k = (vi, uv)
        if k not in key:
            key[k] = len(V)
            v = me.vertices[vi]
            V.append(list(v.co)); N.append(list(me.corner_normals[li].vector) if hasattr(me, 'corner_normals') else list(v.normal))
            UV.append([uv[0], 1 - uv[1]])
            gs = sorted([(g.weight, vg[g.group]) for g in v.groups if g.weight > 0.01], reverse=True)[:4]
            if not gs:
                nobones += 1
                # nearest joint fallback
                best = min(DEFORM, key=lambda n: (J[n] - v.co).length)
                gs = [(1.0, best)]
            tot = sum(w for w, _ in gs)
            gs = [(w / tot, n) for w, n in gs] + [(0.0, gs[0][1])] * (4 - len(gs))
            B.append([n for _, n in gs]); Wt.append([w for w, _ in gs])
        tri.append(key[k])
    I.append(tri)
# recolour masks: r = trunk area below the chest (where the belt lives)
px = np.array(img.pixels[:]).reshape(1024, 1024, 4)[:, :, :3]
def samp(u, v):
    return px[min(1023, max(0, int((1 - v) * 1024))), min(1023, max(0, int(u * 1024)))] if False else px[min(1023, max(0, int(v * 1023))), min(1023, max(0, int(u * 1023)))]
C = []
skin_s, gi_s = [], []
chest_z = J["Torso"].z + 0.04
for k in range(len(V)):
    top = B[k][0]
    trunk = top in ("Hips", "Abdomen", "Torso", "UpperLeg.L", "UpperLeg.R")
    z = V[k][2]
    r = 1.0 if (trunk and -0.32 < z < chest_z and abs(V[k][0]) < 0.3) else 0.0
    g = 1.0 if top in ("Head", "Palm.L", "Palm.R", "Fingers.L", "Fingers.R", "Foot.L", "Foot.R") else 0.0
    C.append([r, g, 0.0])
    u, v_ = UV[k][0], 1 - UV[k][1]
    c = samp(u, v_)
    mxv, mnv = c.max(), c.min(); sat = (mxv - mnv) / max(mxv, 1e-3); lum = c @ np.array([.299, .587, .114])
    if top == "Head" and c[0] > c[1] > c[2] and 0.2 < sat < 0.7 and lum > 0.2:
        skin_s.append(c)
    if lum > 0.45 and sat < 0.12:
        gi_s.append(c)
SKIN_REF = np.median(np.array(skin_s), 0).tolist() if skin_s else [0.7, 0.5, 0.4]
GI_REF = np.median(np.array(gi_s), 0).tolist() if gi_s else [0.85, 0.85, 0.85]
print('skin_ref', np.round(SKIN_REF, 3), len(skin_s), 'gi_ref', np.round(GI_REF, 3), len(gi_s))
print('verts', len(V), 'tris', len(I), 'unweighted', nobones)
json.dump({"joints": {k: list(v) for k, v in J.items()}, "v": V, "n": N, "uv": UV, "b": B, "w": Wt, "i": I, "c": C, "skin_ref": SKIN_REF, "gi_ref": GI_REF},
          open(f"/home/claude/meshybuild/{NAME}.json", "w"))
