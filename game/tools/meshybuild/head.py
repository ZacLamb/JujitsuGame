"""Fit a Meshy head bust onto a rigged hero body (modular heads).
Usage: python3 -I head.py <head.glb> <body_name> <head_name> [scale_tweak]
Reads /home/claude/meshybuild/<body_name>.json (from skin.py), writes
/home/claude/meshybuild/<body_name>__<head_name>.json in the body's mesh space, weighted to the
body's Neck / Head joints, and the shared head texture <head_name>_albedo.png (512px).
The body's own bald head is removed by trim_body() (run once per body: --trim)."""
import sys, json, os
import numpy as np

W = "/home/claude/meshybuild"
LIFT = 0.035   # head sits this much higher than the body's mid-neck (worker units)
# how much taller than the skull each hairstyle is (scale ignores this extra height)
HAIR = {"fade": 1.03, "curly": 1.06, "blond": 1.1, "goatee": 1.0, "topknot": 1.14, "braid": 1.04, "puff": 1.3, "pixie": 1.08}


def slices(P, z0, z1, n=60, band=None):
    out = []
    H = P[:, 2].max() - P[:, 2].min()
    band = band or H * 0.01
    for z in np.linspace(z0, z1, n):
        s = P[np.abs(P[:, 2] - z) < band]
        if len(s) > 8:
            out.append((z, np.ptp(s[:, 0]), s[:, 0].mean(), s[:, 1].mean(), np.ptp(s[:, 1])))
    return out


def body_neck(d):
    V = np.array(d["v"])
    J = d["joints"]
    nz, hz = J["Neck"][2], J["Head"][2]
    top = V[:, 2].max()
    core = V[(np.abs(V[:, 0]) < 0.12)]
    zc = nz + 0.45 * (hz - nz)                       # mid-neck: well above the collar and shoulders
    sl = slices(core, zc - 0.01, zc + 0.01, 3, 0.008)
    z, w, cx, cy, yw = sl[len(sl) // 2]
    return {"z": z, "w": w, "c": (cx, cy), "top": top, "yw": yw}


def trim_body(name):
    """Drop the body's bald head above the neck (the modular head replaces it)."""
    d = json.load(open(f"{W}/{name}.json"))
    if "neck" in d:
        print("already trimmed", name, "(rebuild the body with build.sh first)")
        return
    nk = body_neck(d)
    cut = nk["z"] + 0.012
    V = np.array(d["v"])
    J = d["joints"]
    rxy = np.hypot(V[:, 0] - nk["c"][0], V[:, 1] - nk["c"][1])
    # only the neck column above the cut (and anything at head height) goes; the shoulders stay
    keep_v = ~(((V[:, 2] > cut) & (rxy < nk["w"] * 0.5 + 0.012)) | (V[:, 2] > J["Head"][2] + 0.02))
    I = [t for t in d["i"] if all(keep_v[k] for k in t)]
    used = sorted({k for t in I for k in t})
    remap = {o: n for n, o in enumerate(used)}
    for key in ("v", "n", "uv", "b", "w", "c"):
        if key in d and len(d[key]) == len(V):
            d[key] = [d[key][k] for k in used]
    d["i"] = [[remap[k] for k in t] for t in I]
    d["neck"] = nk | {"cut": cut}
    json.dump(d, open(f"{W}/{name}.json", "w"))
    print("trimmed", name, "neck z", round(nk["z"], 3), "w", round(nk["w"], 3), "verts", len(used))


def fit_head(glb, body, hname, tweak=1.0):
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb)
    m = [o for o in bpy.data.objects if o not in before and o.type == 'MESH'][0]
    bpy.context.view_layer.objects.active = m
    m.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.0005); bpy.ops.object.mode_set(mode='OBJECT')
    dec = m.modifiers.new('dec', 'DECIMATE'); dec.ratio = min(1.0, 7000 / len(m.data.polygons)); dec.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier='dec')
    d = json.load(open(f"{W}/{body}.json"))
    nk = d["neck"]
    J = d["joints"]
    P = np.array([v.co[:] for v in m.data.vertices])
    mn, mx = P.min(0), P.max(0)
    H = mx[2] - mn[2]
    # the head's neck: narrowest full-width slice between the shoulders and the jaw
    prof = []
    for t in np.linspace(0.2, 0.6, 41):
        sl_ = P[np.abs(P[:, 2] - (mn[2] + t * H)) < H * 0.006]
        if len(sl_) > 8:
            prof.append((np.ptp(sl_[:, 0]), mn[2] + t * H, sl_[:, 0].mean(), sl_[:, 1].mean()))
    w_h, z_h, cx_h, cy_h = min(prof)
    # scale by the head's height above the neck (minus its hair volume) vs the body's bald head
    hair = HAIR.get(hname, 1.0)
    s = (nk["top"] - nk["z"]) / ((mx[2] - z_h) / hair) * 0.92 * tweak
    print(hname, "neck z", round(z_h, 3), "-> s", round(s, 4))
    off = np.array([nk["c"][0], nk["c"][1], nk["z"] + LIFT]) - np.array([cx_h, cy_h, z_h]) * s
    # keep the neck a little below the body's cut so it tucks into the collar
    keep_z = z_h - ((LIFT + 0.05) / s)   # the neck reaches down past the body's cut into the collar
    me = m.data
    me.calc_loop_triangles()
    uvl = me.uv_layers.active.data
    hz, nz_ = J["Head"][2], J["Neck"][2]
    V, N, UV, B, Wt, I = [], [], [], [], [], []
    key = {}
    for t in me.loop_triangles:
        if min(me.vertices[i].co[2] for i in t.vertices) < keep_z:
            continue
        tri = []
        for li, vi in zip(t.loops, t.vertices):
            uv = tuple(round(x, 5) for x in uvl[li].uv)
            k = (vi, uv)
            if k not in key:
                key[k] = len(V)
                p = np.array(me.vertices[vi].co[:]) * s + off
                V.append(p.tolist())
                N.append(list(me.corner_normals[li].vector) if hasattr(me, 'corner_normals') else list(me.vertices[vi].normal))
                UV.append([uv[0], 1 - uv[1]])
                # weights: Head above the jaw, blending to Neck down the neck
                a = float(np.clip((p[2] - nz_) / max(hz - nz_, 1e-3), 0, 1))
                B.append(["Head", "Neck", "Torso", "Hips"]); Wt.append([a, 1 - a, 0.0, 0.0])
            tri.append(key[k])
        I.append(tri)
    img = None
    for nd in m.data.materials[0].node_tree.nodes:
        if nd.type == 'TEX_IMAGE' and any(l.to_socket.name == 'Base Color' for l in nd.outputs[0].links):
            img = nd.image
    tex = f"{W}/{hname}_albedo.png"
    if not os.path.exists(tex):
        img.scale(512, 512)
        img.filepath_raw = tex; img.file_format = 'PNG'; img.save()
    # skin tone of this face: warm, mid-saturated texels sampled at the vertices low on the face
    px = np.array(img.pixels[:]).reshape(img.size[1], img.size[0], 4)[:, :, :3]
    samp = []
    for k in range(len(V)):
        if V[k][2] < hz - 0.01 and V[k][2] > nk["z"]:
            u, v_ = UV[k][0], UV[k][1]
            c = px[min(img.size[1] - 1, int((1 - v_) * (img.size[1] - 1))), min(img.size[0] - 1, int(u * (img.size[0] - 1)))]
            mxv, mnv = c.max(), c.min(); sat = (mxv - mnv) / max(mxv, 1e-3)
            if c[0] > c[1] > c[2] and 0.15 < sat < 0.75 and mxv > 0.12:
                samp.append(c)
    skin = np.median(np.array(samp), 0).tolist() if samp else [0.7, 0.5, 0.4]
    # the bottom of these busts is a painted shirt collar: fade the neck to this face's skin tone
    # (vertex colour R, read by FighterLook's head shader) from the narrowest neck slice down
    col = [[float(np.clip((nk["z"] + LIFT - v_[2]) / 0.03, 0, 1)), 0, 0] for v_ in V]
    out = {"joints": J, "v": V, "n": N, "uv": UV, "b": B, "w": Wt, "i": I, "c": col,
           "skin_ref": skin, "gi_ref": [0.85, 0.85, 0.85], "mesh_name": "Head",
           "albedo": f"res://assets/models/heads/{hname}_albedo.png"}
    json.dump(out, open(f"{W}/{body}__{hname}.json", "w"))
    print(hname, "verts", len(V), "tris", len(I), "skin", np.round(skin, 3))


if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if a[0] == "--trim":
        trim_body(a[1])
    else:
        fit_head(a[0], a[1], a[2], float(a[3]) if len(a) > 3 else 1.0)
