"""Builds the Tatame fighter models (CC0, original): a sculpted SDF body + face + hair variants and
separate gi / no-gi gear pieces, all skinned to the Quaternius worker skeleton so the game's
retargeting and the existing animations keep working.

Run:  python3 -I build.py [male|female]   ->  /home/claude/tatame/assets/models/fighter_<body>.glb
"""
import sys, math
import numpy as np
import bpy, bmesh
from mathutils import Vector, Matrix
sys.path.insert(0, "/home/claude/charbuild")
import sdf
from sdf import V, sphere, ellipsoid, round_cone, box, plane, smin, union, smax, subtract, intersect, offset, shell

BODY = sys.argv[-1] if sys.argv[-1] in ("male", "female") else "male"
OUT = f"/home/claude/tatame/assets/models/fighter_{BODY}.glb"
FEM = BODY == "female"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="/home/claude/tatame/assets/models/worker.glb")
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
old_mesh = [o for o in bpy.data.objects if o.type == 'MESH']
AW = arm.matrix_world


def J(name):
    b = arm.data.bones[name]
    return np.array(AW @ b.head_local)


# --- joints (world space; z up, front = -y) -----------------------------------------------
CX = J("Hips")[0]
hips, abd, chest, neck, headj = J("Hips"), J("Abdomen"), J("Torso"), J("Neck"), J("Head")
side = {}
for s in ("L", "R"):
    side[s] = dict(clav=J("Shoulder." + s), sh=J("UpperArm." + s), el=J("LowerArm." + s), wr=J("Palm." + s),
                   mid=J("MiddleHand." + s), fing=J("Fingers." + s), th1=J("Thumb1." + s), th2=J("Thumb2." + s),
                   leg=J("UpperLeg." + s), kn=J("LowerLeg." + s), an=J("Foot." + s))
# symmetrise around the hips centre line (the source rig is a few mm off)
for k in side["L"]:
    l, r = side["L"][k], side["R"][k]
    m = (l + r) / 2
    dl = l - m
    side["L"][k] = np.array([CX + abs(dl[0]), m[1], m[2]]) if True else l
    side["R"][k] = np.array([CX - abs(dl[0]), m[1], m[2]])
for s in ("L", "R"):
    side[s]["sgn"] = 1.0 if s == "L" else -1.0
    # the source hands are huge: shorten the hand chain a little
    d = side[s]["fing"] - side[s]["wr"]
    side[s]["fing"] = side[s]["wr"] + d * 0.82
    side[s]["mid"] = side[s]["wr"] + (side[s]["mid"] - side[s]["wr"]) * 0.82
    side[s]["tip"] = side[s]["fing"] + (side[s]["fing"] - side[s]["mid"]) * 0.9
    side[s]["toe"] = side[s]["an"] + np.array([0, -0.42, -0.05])
U = np.linalg.norm(headj - side["L"]["an"]) / 1.62    # ~1 metre in model units (ankle to head base)
ground = side["L"]["an"][2] - 0.085 * U
headc = headj + np.array([0, -0.01, 0.13 * 1.16]) * U
head_top = headc + np.array([0, 0, 0.13 * 1.16]) * U
print("U =", U, "ground", ground)


def P(v):
    return tuple(v)


def lerp(a, b, t):
    return a + (b - a) * t


# --- body ----------------------------------------------------------------------------------
HS = 1.16          # stylised: slightly larger head
MB = 1.2           # muscle bulk on the limbs (grapplers)


def regions():
    """Body volumes by region so clothing can be offset from exactly the same shapes."""
    u = U
    sw = 1.0 if not FEM else 0.9    # shoulder width factor
    hw = 1.0 if not FEM else 1.1    # hip width factor
    R = {"torso": [], "pelvis": [], "neck": [], "arm": {"L": [], "R": []}, "hand": {"L": [], "R": []},
         "leg": {"L": [], "R": []}, "foot": {"L": [], "R": []}}
    R["pelvis"].append(ellipsoid(P(hips + V(0, 0.005, -0.03) * u), (0.165 * u * hw, 0.115 * u, 0.13 * u)))
    R["torso"].append(round_cone(P(hips - V(0, 0, 0.02) * u), P(neck - V(0, 0, 0.12) * u), 0.135 * u * hw, 0.155 * u * sw))
    R["torso"].append(ellipsoid(P(lerp(abd, chest, 0.35)), (0.148 * u * (0.9 if FEM else 1), 0.105 * u, 0.2 * u)))
    R["torso"].append(ellipsoid(P(lerp(chest, neck, 0.4) + V(0, -0.005, 0) * u), (0.185 * u * sw, 0.122 * u, 0.24 * u)))
    for s in ("L", "R"):
        g = side[s]["sgn"]
        if not FEM:
            R["torso"].append(ellipsoid(P(lerp(chest, neck, 0.5) + V(g * 0.07 * u, -0.072 * u, 0)), (0.08 * u, 0.048 * u, 0.066 * u)))
        else:
            R["torso"].append(sphere(P(lerp(chest, neck, 0.35) + V(g * 0.062 * u, -0.08 * u, 0)), 0.06 * u))
        # traps
        R["torso"].append(round_cone(P(neck + V(0, 0.015 * u, -0.03 * u)), P(side[s]["sh"] + V(0, 0.01 * u, 0.01 * u)), 0.07 * u, 0.06 * u))
    R["neck"].append(round_cone(P(neck - V(0, 0, 0.06) * u), P(headj + V(0, 0.005, 0.02) * u), 0.07 * u * (0.86 if FEM else 1), 0.06 * u))
    for s in ("L", "R"):
        d = side[s]
        g = d["sgn"]
        A = R["arm"][s]
        A.append(sphere(P(d["sh"] + V(g * 0.01, 0, -0.005) * u), 0.078 * u * sw * MB))                       # deltoid
        A.append(round_cone(P(d["sh"]), P(d["el"]), 0.06 * u * sw * MB, 0.046 * u * MB))                    # upper arm
        A.append(ellipsoid(P(lerp(d["sh"], d["el"], 0.45) + V(0, -0.012 * u, 0)), (0.12 * u, 0.05 * u * MB, 0.05 * u * MB)))
        A.append(round_cone(P(d["el"]), P(d["wr"]), 0.047 * u * MB, 0.033 * u * MB))                        # forearm
        A.append(ellipsoid(P(lerp(d["el"], d["wr"], 0.3)), (0.1 * u, 0.05 * u * MB, 0.046 * u * MB)))
        H = R["hand"][s]
        hd = (d["mid"] - d["wr"]) / np.linalg.norm(d["mid"] - d["wr"])
        H.append(ellipsoid(P(d["wr"] + hd * 0.05 * u), (0.045 * u, 0.04 * u, 0.022 * u)))          # palm
        H.append(round_cone(P(d["wr"] + hd * 0.075 * u), P(d["wr"] + hd * 0.115 * u + V(0, -0.012, -0.015) * u), 0.026 * u, 0.022 * u))  # curled fingers
        H.append(round_cone(P(d["wr"] + hd * 0.03 * u + V(0, -0.025, 0) * u), P(d["wr"] + hd * 0.07 * u + V(0, -0.04, -0.01) * u), 0.014 * u, 0.012 * u))  # thumb
        L = R["leg"][s]
        L.append(round_cone(P(d["leg"] + V(0, 0, 0.02 * u)), P(d["kn"]), 0.088 * u * hw * MB, 0.056 * u * MB))
        L.append(ellipsoid(P(lerp(d["leg"], d["kn"], 0.35) + V(g * 0.005 * u, -0.01 * u, 0)), (0.08 * u * MB, 0.08 * u * MB, 0.15 * u)))
        L.append(round_cone(P(d["kn"]), P(d["an"]), 0.052 * u * MB, 0.034 * u * MB))
        L.append(ellipsoid(P(lerp(d["kn"], d["an"], 0.3) + V(0, 0.018 * u, 0)), (0.05 * u * MB, 0.052 * u * MB, 0.11 * u)))
        foot = smin([round_cone(P(d["an"] + V(0, 0.01 * u, -0.03 * u)), P(d["toe"]), 0.04 * u, 0.036 * u),
                     ellipsoid(P(d["an"] + V(0, 0.025 * u, -0.05 * u)), (0.037 * u, 0.047 * u, 0.037 * u))], 0.02 * u)
        R["foot"][s].append(intersect(foot, plane((0, 0, -1), -ground)))
    return R


REG = None


def body_sdf():
    R = REG
    parts = R["torso"] + R["pelvis"] + R["neck"]
    for s in ("L", "R"):
        parts += R["arm"][s] + R["hand"][s] + R["leg"][s] + R["foot"][s]
    return smin(parts, 0.03 * U)


def head_sdf():
    u = U * HS
    hc = headc
    cran = ellipsoid(P(hc + V(0, 0.01, 0.01) * u), (0.085 * u, 0.1 * u, 0.105 * u))
    jaw = ellipsoid(P(hc + V(0, -0.03, -0.055) * u), (0.068 * u * (0.92 if FEM else 1), 0.075 * u, 0.06 * u))
    chin = sphere(P(hc + V(0, -0.075, -0.085) * u), 0.026 * u)
    nose = round_cone(P(hc + V(0, -0.095, 0.0) * u), P(hc + V(0, -0.11, -0.03) * u), 0.012 * u, 0.016 * u)
    brow = ellipsoid(P(hc + V(0, -0.075, 0.035) * u), (0.07 * u, 0.03 * u, 0.018 * u))
    ears = [ellipsoid(P(hc + V(g * 0.088, 0.005, -0.005) * u), (0.014 * u, 0.025 * u, 0.034 * u)) for g in (1, -1)]
    cheeks = [sphere(P(hc + V(g * 0.045, -0.07, -0.02) * u), 0.03 * u) for g in (1, -1)]
    h = smin([cran, jaw, chin, brow] + cheeks, 0.02 * u)
    h = smin([h, nose], 0.008 * u)
    h = smin([h] + ears, 0.006 * u)
    for g in (1, -1):
        h = subtract(h, sphere(P(hc + V(g * 0.034, -0.1, 0.012) * u), 0.017 * u), 0.008 * u)
    return h


def face_sdf():
    """Eyes and brows (dark), a separate mesh so they can be coloured."""
    u = U * HS
    hc = headc
    parts = []
    for g in (1, -1):
        parts.append(ellipsoid(P(hc + V(g * 0.034, -0.088, 0.012) * u), (0.011 * u, 0.006 * u, 0.013 * u)))
        parts.append(round_cone(P(hc + V(g * 0.018, -0.1, 0.038) * u), P(hc + V(g * 0.052, -0.088, 0.04) * u), 0.006 * u, 0.0045 * u))
    return union(parts)


HAIR_STYLES = ["short", "buzz", "bun", "curly", "long", "ponytail"]


def hair_sdf(style):
    u = U * HS
    hc = headc
    skull = ellipsoid(P(hc + V(0, 0.012, 0.01) * u), (0.09 * u, 0.105 * u, 0.11 * u))
    # hairline: keep above the brow, behind the ears
    cut = lambda P: np.maximum(-(P[:, 2] - (hc[2] + 0.02 * u)) - np.maximum(P[:, 1] - (hc[1] - 0.02 * u), 0) * 2.2, -1e9)
    base = lambda P: np.maximum(skull(P) - (0.012 if style == "buzz" else 0.022) * u, cut(P))
    if style in ("short", "buzz"):
        return base
    if style == "curly":
        rng = np.random.default_rng(3)
        blobs = []
        for i in range(70):
            th = rng.uniform(0, 2 * math.pi)
            ph = rng.uniform(0.0, 1.25)
            dirv = np.array([math.sin(ph) * math.cos(th), math.sin(ph) * math.sin(th) * 1.1, math.cos(ph)])
            if dirv[1] < -0.55 and dirv[2] < 0.4:
                continue
            c = hc + V(0, 0.012, 0.01) * u + dirv * np.array([0.095, 0.11, 0.115]) * u
            blobs.append(sphere(P(c), 0.03 * u))
        return smin([base] + blobs, 0.012 * u)
    if style == "bun":
        return smin([base, sphere(P(hc + V(0, 0.085, 0.09) * u), 0.045 * u)], 0.015 * u)
    if style == "ponytail":
        tie = hc + V(0, 0.11, 0.03) * u
        return smin([base, sphere(P(tie), 0.03 * u),
                     round_cone(P(tie + V(0, 0.02, -0.01) * u), P(tie + V(0, 0.05, -0.2) * u), 0.032 * u, 0.018 * u)], 0.012 * u)
    if style == "long":
        back = round_cone(P(hc + V(0, 0.05, 0.02) * u), P(hc + V(0, 0.07, -0.2) * u), 0.085 * u, 0.07 * u)
        back = intersect(back, plane((0, -1, 0), -(hc[1] + 0.0 * u)))
        return smin([base, back], 0.02 * u)
    return base


# --- gear (gi + no-gi) ---------------------------------------------------------------------
def torso_core():
    """Torso + arms (no hands/legs): the base for jacket and rashguard offsets."""
    R = REG
    return smin(R["torso"] + R["pelvis"] + R["arm"]["L"] + R["arm"]["R"], 0.04 * U)


def arm_cut(f, s_frac, sides=("L", "R")):
    """Cuts sleeves at a fraction of the forearm (0 = elbow, 1 = wrist)."""
    for s in sides:
        d = side[s]
        n = d["wr"] - d["el"]
        n = n / np.linalg.norm(n)
        p = lerp(d["el"], d["wr"], s_frac)
        f = intersect(f, plane(tuple(n), float(n @ p)))
    return f


def legs_core():
    R = REG
    return smin(R["pelvis"] + R["torso"][:1] + R["leg"]["L"] + R["leg"]["R"], 0.03 * U)


def vneck_sdf():
    """Negative inside the V opening of the jacket (front only)."""
    u = U
    vtip = lerp(chest, neck, 0.3) + V(0, -0.13, 0) * u
    return lambda Pp: np.maximum.reduce([
        (-((Pp[:, 2] - vtip[2]) - np.abs(Pp[:, 0] - CX) * 2.4)) / 2.6,
        (Pp[:, 1] - (neck[1] - 0.04 * u)),
        Pp[:, 2] - (neck[2] + 0.2 * u)])


def neckhole_sdf():
    u = U
    return round_cone(P(neck - V(0, 0, 0.03) * u), P(headc), 0.08 * u, 0.08 * u)


def jacket_base():
    u = U
    j = offset(torso_core(), 0.022 * u)
    skirt_top = lerp(hips, abd, 0.2)
    skirt = round_cone(P(skirt_top), P(hips - V(0, 0, 0.15) * u), 0.185 * u * (1.08 if FEM else 1), 0.2 * u)
    skirt = smax(skirt, plane((0, 0, -1), -(hips[2] - 0.14 * u)), 0.025 * u)
    j = smin([j, skirt], 0.03 * u)
    return arm_cut(j, 0.88)


def jacket_sdf():
    u = U
    j = jacket_base()
    j = subtract(j, vneck_sdf(), 0.006 * u)
    return subtract(j, neckhole_sdf(), 0.01 * u)


def jacket_trim_sdf():
    """Lapels + collar and sleeve cuffs: a thin layer on top of the jacket in the trim colour."""
    u = U
    jb = jacket_base()
    vn = vneck_sdf()
    nh = neckhole_sdf()
    # lapels: a strip of the jacket surface running along the V opening and round the collar
    lap_band = lambda Pp: np.maximum(np.minimum(np.abs(vn(Pp) - 0.024 * u), np.abs(nh(Pp) - 0.024 * u)) - 0.024 * u,
                                     -np.minimum(vn(Pp), nh(Pp)))
    lap = intersect(shell(jb, 0.016 * u, -0.006 * u), lap_band)
    cuff = intersect(shell(jb, 0.012 * u, -0.004 * u), lambda Pp: np.minimum(seg_band(Pp, "L"), seg_band(Pp, "R")))
    return union([lap, cuff])


def seg_band(Pp, s):
    d = side[s]
    n = (d["wr"] - d["el"]) / np.linalg.norm(d["wr"] - d["el"])
    p = lerp(d["el"], d["wr"], 0.88)
    t = (Pp - p) @ n
    sidek = np.where(np.sign(Pp[:, 0] - CX) == d["sgn"], 0.0, 1e9)
    return np.maximum(t, -t - 0.05 * U) + sidek


def pants_sdf():
    u = U
    p = offset(legs_core(), 0.03 * u)
    # stop above the ankle and below the jacket/belt line
    for s in ("L", "R"):
        d = side[s]
        n = (d["an"] - d["kn"]) / np.linalg.norm(d["an"] - d["kn"])
        cut_p = lerp(d["kn"], d["an"], 0.85)
        p = intersect(p, lambda Pp, n=n, c=cut_p, s=s: np.where(
            (np.sign(Pp[:, 0] - CX) == side[s]["sgn"]), Pp @ n - n @ c, -1e9))
    p = intersect(p, plane((0, 0, 1), float(lerp(hips, abd, 0.45)[2])))
    return p


def belt_sdf():
    u = U
    c = lerp(hips, abd, 0.55)
    band = lambda Pp: np.maximum(np.abs(Pp[:, 2] - c[2]) - 0.022 * u,
                                 ellipsoid(P(c), (0.185 * u * (1.06 if FEM else 1), 0.13 * u, 0.5 * u))(Pp) * 1.0)
    band = shell(offset(torso_core(), 0.0), 0.05 * u, 0.03 * u)
    band = intersect(band, lambda Pp: np.abs(Pp[:, 2] - c[2]) - 0.024 * u)
    knot = ellipsoid(P(c + V(0, -0.16, 0) * u), (0.032 * u, 0.02 * u, 0.028 * u))
    tails = [round_cone(P(c + V(g * 0.012, -0.155, -0.01) * u), P(c + V(g * 0.045, -0.165, -0.14) * u), 0.015 * u, 0.012 * u) for g in (1, -1)]
    return smin([band, knot] + tails, 0.006 * u)


def rash_sdf(long_sleeve=True):
    u = U
    core = torso_core()
    r = offset(core, 0.008 * u)
    r = arm_cut(r, 0.9 if long_sleeve else -0.45)
    r = intersect(r, plane((0, 0, -1), -(hips[2] - 0.07 * u)))
    r = subtract(r, round_cone(P(neck - V(0, 0, 0.0) * u), P(headc), 0.058 * u, 0.06 * u), 0.008 * u)
    return r


def spats_sdf():
    u = U
    p = offset(legs_core(), 0.016 * u)
    for s in ("L", "R"):
        d = side[s]
        n = (d["an"] - d["kn"]) / np.linalg.norm(d["an"] - d["kn"])
        cut_p = lerp(d["kn"], d["an"], 0.55)
        p = intersect(p, lambda Pp, n=n, c=cut_p, s=s: np.where(
            (np.sign(Pp[:, 0] - CX) == side[s]["sgn"]), Pp @ n - n @ c, -1e9))
    p = intersect(p, plane((0, 0, 1), float(lerp(hips, abd, 0.8)[2])))
    return p


def knee_sdf():
    u = U
    parts = []
    for s in ("L", "R"):
        d = side[s]
        a = lerp(d["leg"], d["kn"], 0.75)
        b = lerp(d["kn"], d["an"], 0.25)
        parts.append(round_cone(P(a), P(b), 0.074 * u, 0.068 * u))
    return union(parts)


def earguard_sdf():
    u = U * HS
    hc = headc
    cups = [ellipsoid(P(hc + V(g * 0.1, 0.005, -0.005) * u), (0.022 * u, 0.04 * u, 0.05 * u)) for g in (1, -1)]
    strap = shell(ellipsoid(P(hc + V(0, 0.01, 0.0) * u), (0.1 * u, 0.115 * u, 0.125 * u)), 0.012 * u, 0.004 * u)
    strap = intersect(strap, lambda Pp: np.abs(Pp[:, 1] - (hc[1] + 0.01 * u)) - 0.018 * u)
    strap = intersect(strap, plane((0, 0, -1), -(hc[2] - 0.02 * u)))
    return smin(cups + [strap], 0.01 * u)


def headband_sdf():
    u = U * HS
    hc = headc
    b = shell(ellipsoid(P(hc + V(0, 0.012, 0.01) * u), (0.09 * u, 0.105 * u, 0.11 * u)), 0.03 * u, 0.012 * u)
    return intersect(b, lambda Pp: np.abs((Pp[:, 2] - (hc[2] + 0.055 * u)) + (Pp[:, 1] - hc[1]) * 0.35) - 0.016 * u)


def tape_sdf():
    u = U
    parts = []
    for s in ("L", "R"):
        d = side[s]
        hd = (d["mid"] - d["wr"]) / np.linalg.norm(d["mid"] - d["wr"])
        for t in (0.085, 0.105):
            c = d["wr"] + hd * t * u + V(0, -0.006, -0.008) * u
            parts.append(round_cone(P(c - hd * 0.006 * u), P(c + hd * 0.006 * u), 0.03 * u, 0.028 * u))
        parts.append(round_cone(P(d["wr"] - hd * 0.01 * u), P(d["wr"] + hd * 0.02 * u), 0.04 * u, 0.042 * u))
    return union(parts)


# --- meshing, skinning ---------------------------------------------------------------------
SEGS = []


def seg(bone, a, b):
    SEGS.append((bone, np.asarray(a, float), np.asarray(b, float)))


seg("Hips", hips - V(0, 0, 0.06) * U, lerp(hips, abd, 0.5))
seg("Abdomen", lerp(hips, abd, 0.5), lerp(abd, chest, 0.5))
seg("Torso", lerp(abd, chest, 0.5), neck - V(0, 0, 0.03) * U)
seg("Neck", neck - V(0, 0, 0.03) * U, headj)
seg("Head", headj, head_top)
for s in ("L", "R"):
    d = side[s]
    seg("Shoulder." + s, d["clav"], d["sh"])
    seg("UpperArm." + s, d["sh"], d["el"])
    seg("LowerArm." + s, d["el"], d["wr"])
    seg("Palm." + s, d["wr"], d["mid"])
    seg("MiddleHand." + s, d["mid"], d["fing"])
    seg("Fingers." + s, d["fing"], d["tip"])
    seg("Thumb1." + s, d["th1"], d["th2"])
    seg("Thumb2." + s, d["th2"], d["th2"] + (d["th2"] - d["th1"]) * 0.6)
    seg("UpperLeg." + s, d["leg"], d["kn"])
    seg("LowerLeg." + s, d["kn"], d["an"])
    seg("Foot." + s, d["an"], d["toe"])


def seg_dist(Pts, a, b):
    ab = b - a
    t = np.clip(((Pts - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(Pts - (a + np.outer(t, ab)), axis=1)


def weights(Pts, tau=0.035):
    D = np.stack([seg_dist(Pts, a, b) for (_, a, b) in SEGS], 1)
    # keep each side's limbs to its own side of the body
    for i, (bone, a, b) in enumerate(SEGS):
        if bone.endswith(".L") or bone.endswith(".R"):
            g = 1.0 if bone.endswith(".L") else -1.0
            wrong = (Pts[:, 0] - CX) * g < -0.02 * U
            D[wrong, i] += 10.0
    dmin = D.min(1, keepdims=True)
    W = np.exp(-(D - dmin) / (tau * U))
    idx = np.argsort(-W, 1)[:, :4]
    out = np.zeros_like(W)
    rows = np.arange(len(Pts))[:, None]
    out[rows, idx] = W[rows, idx]
    out /= out.sum(1, keepdims=True)
    return out


def bbox(margin=0.06):
    lo = np.array([CX - 1.2 * U, hips[1] - 0.45 * U, ground - 0.02 * U])
    hi = np.array([CX + 1.2 * U, hips[1] + 0.45 * U, head_top[2] + 0.12 * U])
    return lo, hi


def region(c, ext):
    c = np.asarray(c)
    return c - ext, c + ext


def make(name, f, lo, hi, step, target_tris, mat_name, smooth_iters=2):
    v, fa = sdf.mesh(f, lo, hi, step)
    if v is None:
        print("EMPTY", name)
        return None
    me = bpy.data.meshes.new(name)
    me.from_pydata(v.tolist(), [], fa[:, ::-1].tolist())
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=step * 0.05)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    n0 = len(me.polygons)
    if smooth_iters:
        mod = ob.modifiers.new("sm", 'SMOOTH')
        mod.iterations = smooth_iters
        mod.factor = 0.5
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if n0 > target_tris:
        mod = ob.modifiers.new("dec", 'DECIMATE')
        mod.ratio = target_tris / n0
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in me.polygons:
        p.use_smooth = True
    mat = bpy.data.materials.get(mat_name) or bpy.data.materials.new(mat_name)
    me.materials.append(mat)
    # skin
    pts = np.array([list(vv.co) for vv in me.vertices])
    W = weights(pts)
    groups = {}
    for i, (bone, _, _) in enumerate(SEGS):
        groups[bone] = ob.vertex_groups.get(bone) or ob.vertex_groups.new(name=bone)
    for vi in range(len(pts)):
        for i in np.nonzero(W[vi] > 1e-3)[0]:
            groups[SEGS[i][0]].add([vi], float(W[vi, i]), 'REPLACE')
    ob.parent = arm
    ob.matrix_parent_inverse = AW.inverted()
    am = ob.modifiers.new("Armature", 'ARMATURE')
    am.object = arm
    print(f"{name}: {n0} -> {len(me.polygons)} tris")
    return ob


for o in old_mesh:
    bpy.data.objects.remove(o, do_unlink=True)

REG = regions()
lo, hi = bbox()
S = 0.012 * U
make("Body", smin([body_sdf(), head_sdf()], 0.025 * U), lo, hi, S, 4200, "Skin", 2)
hl, hh = region(headc, np.array([0.16, 0.16, 0.18]) * U)
make("Face", face_sdf(), hl, hh, 0.004 * U, 300, "Eyes", 0)
for st in HAIR_STYLES:
    lo2, hi2 = region(headc - V(0, 0, 0.08) * U, np.array([0.17, 0.2, 0.25]) * U)
    make("Hair_" + st, hair_sdf(st), lo2, hi2, 0.006 * U, 900, "Hair", 1)
G = 0.014 * U
make("Jacket", jacket_sdf(), lo, hi, G, 3000, "Jacket", 2)
make("JacketTrim", jacket_trim_sdf(), lo, hi, 0.008 * U, 900, "Trim", 1)
make("Pants", pants_sdf(), lo, hi, G, 1800, "Pants", 2)
make("Belt", belt_sdf(), lo, hi, 0.006 * U, 700, "Belt", 1)
make("Rash", rash_sdf(True), lo, hi, G, 2400, "Rash", 2)
make("Spats", spats_sdf(), lo, hi, G, 1400, "Spats", 2)
make("KneeSleeves", knee_sdf(), lo, hi, 0.01 * U, 600, "Knees", 1)
make("EarGuards", earguard_sdf(), hl, hh + V(0.05, 0.05, 0.05) * U, 0.005 * U, 500, "Headgear", 1)
make("Headband", headband_sdf(), hl, hh, 0.005 * U, 400, "Headgear", 1)
make("Tape", tape_sdf(), lo, hi, 0.005 * U, 500, "Tape", 1)

# --- dump for the Godot importer (keeps the original skeleton, rests and animations) ---------
import json
dump = {"bones": {b.name: list(AW @ b.head_local) for b in arm.data.bones}, "pieces": {}}
for ob in bpy.data.objects:
    if ob.type != 'MESH':
        continue
    me = ob.data
    me.calc_loop_triangles()
    vg = {g.index: g.name for g in ob.vertex_groups}
    verts, norms, bones, wts = [], [], [], []
    for v in me.vertices:
        verts.extend(list(ob.matrix_world @ v.co))
        norms.extend(list((ob.matrix_world.to_3x3() @ v.normal).normalized()))
        gs = sorted([(g.weight, vg[g.group]) for g in v.groups if g.weight > 1e-3], reverse=True)[:4]
        tot = sum(w for w, _ in gs) or 1.0
        gs += [(0.0, "Hips")] * (4 - len(gs))
        bones.extend([n for _, n in gs])
        wts.extend([w / tot for w, _ in gs])
    tris = []
    for t in me.loop_triangles:
        tris.extend(list(t.vertices))
    dump["pieces"][ob.name] = {"v": verts, "n": norms, "b": bones, "w": wts, "i": tris,
                               "mat": me.materials[0].name if me.materials else ""}
OUTJ = f"/home/claude/charbuild/fighter_{BODY}.json"
json.dump(dump, open(OUTJ, "w"))
print("wrote", OUTJ, {k: len(p["i"]) // 3 for k, p in dump["pieces"].items()})
