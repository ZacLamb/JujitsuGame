"""Estimate worker-skeleton joint positions on a Meshy A-pose character mesh.
Usage: python3 -I joints.py <glb> <out.json>"""
import sys, json, math
import numpy as np
import bpy
from scipy.spatial import cKDTree
from scipy.sparse.csgraph import connected_components
from scipy.sparse import coo_matrix

GLB, OUT = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
W = {k: np.array(v[1:]) for k, v in json.load(open("/home/claude/charbuild/worker_skeleton.json")).items()}
wmin = np.array([-1, -1, -0.997]); wmax = np.array([1, 1, 1.0])
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=GLB)
m = [o for o in bpy.data.objects if o not in before and o.type == 'MESH'][0]
P = np.array([m.matrix_world @ v.co for v in m.data.vertices])
mn, mx = P.min(0), P.max(0)
# scale/translate the meshy model so height and ground match the worker
s = (wmax[2] - wmin[2]) / (mx[2] - mn[2])
off = np.array([0, 0, wmin[2]]) - np.array([(mn[0] + mx[0]) / 2 * s, 0, mn[2] * s])
# centre y on the hip area later
P = P * s + off
H = P[:, 2].max() - P[:, 2].min()
z0 = P[:, 2].min()
print("scale", s, "H", H)

def slice_clusters(z, band=0.012, link=0.03):
    sel = P[np.abs(P[:, 2] - z) < band]
    if len(sel) < 3:
        return []
    t = cKDTree(sel[:, :2])
    pairs = t.query_pairs(link, output_type='ndarray')
    g = coo_matrix((np.ones(len(pairs)), (pairs[:, 0], pairs[:, 1])), shape=(len(sel), len(sel)))
    n, lab = connected_components(g, directed=False)
    out = []
    for k in range(n):
        pts = sel[lab == k]
        if len(pts) > 15:
            out.append(pts)
    return out

wz = lambda name: W[name][2]
wH = wmax[2] - wmin[2]
def fz(name):  # worker joint height as fraction of height -> meshy height
    return z0 + (W[name][2] - wmin[2]) / wH * H

J = {}
CX = (P[:, 0].min() + P[:, 0].max()) / 2
# legs: clusters at a few heights
legs = {}
for nm in ("UpperLeg", "LowerLeg", "Foot"):
    z = fz(nm + ".L")
    zz = z if nm != "UpperLeg" else z0 + (fz("UpperLeg.L") - z0) * 0.8
    cl = slice_clusters(zz)
    cl = sorted(cl, key=lambda c: -len(c))[:2]
    cents = sorted([c.mean(0) for c in cl], key=lambda c: c[0])
    if len(cents) == 2:
        legs[nm] = cents
    print(nm, "slice", round(zz, 3), [c.round(3) for c in cents])
for nm in ("UpperLeg", "LowerLeg", "Foot"):
    z = fz(nm + ".L")
    for side, i in (("R", 0), ("L", 1)):
        c = legs.get(nm, legs.get("LowerLeg"))[i]
        J[nm + "." + side] = np.array([c[0], c[1], z])
# foot joint y: ankle sits at back part of foot cluster -> use LowerLeg y
for side in "LR":
    J["Foot." + side][1] = J["LowerLeg." + side][1]
# spine: centre of torso slices
for nm in ("Hips", "Abdomen", "Torso", "Neck", "Head", "Body", "Bone"):
    z = fz(nm)
    cl = slice_clusters(z)
    if cl:
        # pick the cluster closest to centre x
        c = min(cl, key=lambda c: abs(c.mean(0)[0] - CX))
        ctr = c.mean(0)
    else:
        ctr = np.array([CX, 0, z])
    J[nm] = np.array([CX, ctr[1], z])
# arms: walk down from shoulder height; outermost clusters
arm_pts = {"L": [], "R": []}
zs = np.linspace(fz("UpperArm.L"), z0 + 0.25 * H, 60)
for z in zs:
    cl = slice_clusters(z, band=0.008, link=0.02)
    if len(cl) < 3:
        continue
    cl = sorted(cl, key=lambda c: c.mean(0)[0])
    lc, rc = cl[-1], cl[0]  # +x = L
    for side, c in (("L", lc), ("R", rc)):
        ctr = c.mean(0)
        if abs(ctr[0] - CX) > 0.12:
            arm_pts[side].append(ctr)
for side in "LR":
    a = np.array(arm_pts[side])
    print(side, "arm samples", len(a), a[:1].round(3), a[-1:].round(3))
    tip = a[np.argmin(a[:, 2])]
    sgn = 1 if side == "L" else -1
    sh_z = fz("UpperArm." + side)
    # shoulder joint: inside the deltoid, at the worker height fraction
    sh_x = CX + sgn * abs(W["UpperArm." + side][0] - W["Hips"][0]) * (H / wH)
    top = a[np.argmax(a[:, 2])]
    sh = np.array([sh_x, top[1], sh_z])
    # hand length ~ 0.1 H, fingertips at tip
    d = tip - sh
    L = np.linalg.norm(d)
    u = d / L
    # bend: use the sample curve: wrist = point on curve 0.105H above tip along curve
    order = np.argsort(-a[:, 2])
    curve = a[order]
    seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(curve, axis=0), axis=1))]
    tot = seg[-1]
    def at(s_):
        return np.array([np.interp(s_, seg, curve[:, k]) for k in range(3)])
    wrist = at(tot - 0.1 * H)
    upper_len = np.linalg.norm(wrist - sh)
    ez = sh[2] + (wrist[2] - sh[2]) * 0.47
    if ez <= curve[0, 2]:
        elbow = np.array([np.interp(-ez, -curve[:, 2], curve[:, k]) for k in range(3)])
    else:
        t_ = (ez - sh[2]) / (curve[0, 2] - sh[2])
        elbow = sh + (curve[0] - sh) * t_
    elbow[1] = elbow[1] + 0.015  # elbow sits a little behind the sleeve centre
    J["UpperArm." + side] = sh
    J["LowerArm." + side] = elbow
    J["Palm." + side] = wrist
    J["MiddleHand." + side] = wrist + (tip - wrist) * 0.35
    J["Fingers." + side] = wrist + (tip - wrist) * 0.6
    J["Thumb1." + side] = wrist + (tip - wrist) * 0.3
    J["Thumb2." + side] = wrist + (tip - wrist) * 0.5
    J["Shoulder." + side] = np.array([CX + sgn * 0.6 * abs(sh_x - CX), J["Torso"][1], fz("Shoulder." + side)])
    J["Tip." + side] = tip
for side in "LR":
    J["PoleTarget." + side] = J["LowerLeg." + side] + np.array([0, -0.6, -0.09])
json.dump({"scale": s, "off": off.tolist(), "joints": {k: v.tolist() for k, v in J.items()},
           "worker": {k: v.tolist() for k, v in W.items()}}, open(OUT, "w"), indent=1)
print("ok")
