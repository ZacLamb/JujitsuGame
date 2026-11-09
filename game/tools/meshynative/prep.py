"""Meshy-rigged character (GLB, Mixamo skeleton) -> the textures BodyRig's gear shader needs.

  python3 -I tools/meshynative/prep.py <rigged.glb> <name> [gi|nogi]

Writes assets/models/native/<name>_albedo.png (1024px), <name>_mask.png (R = belt, G = face/head:
never recoloured as cloth) and <name>.json (skin_ref / gi_ref colours for the recolour maths).
The belt is found by shape: dark, unsaturated texels on the waist band between the hands.
"""
import sys, json, struct, io, os
import numpy as np
from PIL import Image, ImageFilter

src, name = sys.argv[1], sys.argv[2]
kit = sys.argv[3] if len(sys.argv) > 3 else ("nogi" if "nogi" in name else "gi")
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "native")
os.makedirs(OUT, exist_ok=True)
N = 1024

b = open(src, "rb").read()
jl = struct.unpack("<I", b[12:16])[0]
J = json.loads(b[20:20 + jl])
bin_off = 20 + jl + 8
BIN = b[bin_off:]
CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def acc(i):
    a = J["accessors"][i]
    bv = J["bufferViews"][a["bufferView"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    dt = np.dtype(CT[a["componentType"]])
    nc = NC[a["type"]]
    stride = bv.get("byteStride", 0)
    if stride and stride != dt.itemsize * nc:
        raw = np.frombuffer(BIN, np.uint8, count=stride * a["count"], offset=off).reshape(a["count"], stride)
        return np.frombuffer(raw[:, :dt.itemsize * nc].tobytes(), dt).reshape(a["count"], nc)
    return np.frombuffer(BIN, dt, count=a["count"] * nc, offset=off).reshape(a["count"], nc)


prim = J["meshes"][0]["primitives"][0]
P = acc(prim["attributes"]["POSITION"]).astype(np.float64)
UV = acc(prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
I = acc(prim["indices"]).reshape(-1, 3)

# joints in mesh space: inverse of each inverse bind matrix
skin = J["skins"][0]
ibm = acc(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
jpos = {}
for k, ni in enumerate(skin["joints"]):
    jpos[J["nodes"][ni]["name"].split(":")[-1]] = np.linalg.inv(ibm[k])[:3, 3]
hy = jpos["Hips"][1]
ny = jpos["Neck"][1]
hdy = jpos["Head"][1]
JW = acc(prim["attributes"]["JOINTS_0"]).astype(int)
WW = acc(prim["attributes"]["WEIGHTS_0"]).astype(np.float64)
if WW.max() > 1.5:
    WW = WW / 255.0
head_j = [k for k, ni in enumerate(skin["joints"]) if any(h in J["nodes"][ni]["name"] for h in ("Head", "headfront"))]
headw = (np.isin(JW, head_j) * WW).sum(1)
neck_j = [k for k, ni in enumerate(skin["joints"]) if "Neck" in J["nodes"][ni]["name"]]
hairw = headw + (np.isin(JW, neck_j) * WW).sum(1)   # ponytails / braids hang off the head + neck
# long hair hanging down the back (braids are often skinned to the spine): every UV island that
# reaches the head, is mostly dark and is small (not the torso) counts as hair
behind = np.zeros(len(P), bool)
if kit == "nogi":
    _bv = J["bufferViews"][J["images"][J["textures"][J["materials"][prim.get("material", 0)]["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]]["bufferView"]]
    _A0 = np.asarray(Image.open(io.BytesIO(BIN[_bv.get("byteOffset", 0):_bv.get("byteOffset", 0) + _bv["byteLength"]])).convert("RGB").resize((256, 256))).astype(np.float32) / 255
    _px = np.clip((UV * 255).astype(int), 0, 255)
    _lum = _A0[_px[:, 1], _px[:, 0]] @ np.array([0.299, 0.587, 0.114], np.float32)
    par = np.arange(len(P))
    def _f(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    for t in I:
        ra = _f(t[0])
        for v in t[1:]:
            rb = _f(v)
            if rb != ra:
                par[rb] = ra
    roots = np.array([_f(i) for i in range(len(P))])
    for r in np.unique(roots):
        m = roots == r
        if headw[m].max() > 0.5 and (_lum[m] < 0.18).mean() > 0.5 and m.sum() < 600:
            behind |= m
y0, y1 = P[:, 1].min(), P[:, 1].max()
H = y1 - y0

# base colour texture
mat = J["materials"][prim.get("material", 0)]
ti = mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]
img = J["images"][J["textures"][ti]["source"]]
bv = J["bufferViews"][img["bufferView"]]
alb = Image.open(io.BytesIO(BIN[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])).convert("RGB")
alb = alb.resize((N, N), Image.LANCZOS)
alb.save(os.path.join(OUT, f"{name}_albedo.png"))
A = np.asarray(alb).astype(np.float32) / 255

# per-triangle region flags rasterised in UV space
reg_r = np.zeros((N, N), np.float32)
reg_g = np.zeros((N, N), np.float32)
reg_h = np.zeros((N, N), np.float32)   # anything hanging off the head/neck (long hair): never cloth
pix = UV * (N - 1)
for t in I:
    q = P[t]
    cy = q[:, 1].mean()
    cx = np.abs(q[:, 0]).max()
    r = 1.0 if (kit == "gi" and hy - 0.16 * H < cy < hy + 0.11 * H and cx < 0.16 * H) else 0.0
    # face / hair: skinned (mostly) to the head bones, so collars and big trapezius muscles stay cloth
    g = 1.0 if headw[t].mean() > 0.6 else 0.0
    hh = 1.0 if (kit == "nogi" and ((hairw[t].max() > 0.25 and cy > hy) or behind[t].any())) else 0.0
    if r == 0.0 and g == 0.0 and hh == 0.0:
        continue
    p = pix[t]
    x0, yy0 = np.floor(p.min(0)).astype(int); x1, yy1 = np.ceil(p.max(0)).astype(int)
    x0, yy0 = max(x0 - 1, 0), max(yy0 - 1, 0); x1, yy1 = min(x1 + 1, N - 1), min(yy1 + 1, N - 1)
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(yy0, yy1 + 1) + 0.5)
    a_, b_, c_ = p
    den = (b_[1] - c_[1]) * (a_[0] - c_[0]) + (c_[0] - b_[0]) * (a_[1] - c_[1])
    if abs(den) < 1e-9:
        continue
    l1 = ((b_[1] - c_[1]) * (xs - c_[0]) + (c_[0] - b_[0]) * (ys - c_[1])) / den
    l2 = ((c_[1] - a_[1]) * (xs - c_[0]) + (a_[0] - c_[0]) * (ys - c_[1])) / den
    inside = (l1 >= -0.02) & (l2 >= -0.02) & (1 - l1 - l2 >= -0.02)
    sl = (slice(yy0, yy1 + 1), slice(x0, x1 + 1))
    if r:
        reg_r[sl] = np.maximum(reg_r[sl], inside * r)
    if g:
        reg_g[sl] = np.maximum(reg_g[sl], inside * g)
    if hh:
        reg_h[sl] = 1.0   # whole (padded) box: hair strands are often smaller than a texel

lum = A @ np.array([0.299, 0.587, 0.114], np.float32)
mx = A.max(2); mn = A.min(2)
sat = (mx - mn) / np.maximum(mx, 1e-3) * np.clip((mx - 0.04) / 0.12, 0, 1)   # near-black reads as neutral
dark = np.clip((0.3 - lum) / 0.1, 0, 1) * np.clip((0.4 - sat) / 0.15, 0, 1)
belt = reg_r * (1 - reg_g) * dark
# no-gi: the dark rashguard / shorts (B channel) get tinted to the gear colour by brightness
dark_cloth = np.zeros_like(belt)
if kit == "nogi":
    dark_cloth = np.clip((0.32 - lum) / 0.12, 0, 1) * np.clip((0.45 - sat) / 0.2, 0, 1) * (1 - reg_g) * (1 - reg_h)
    dark_cloth = np.asarray(Image.fromarray((dark_cloth * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(5))).astype(np.float32) / 255
# small belt islands fade out in the mip chain: grow them more
grow = 7 if (belt > 0.5).sum() < 6000 else 3
bimg = Image.fromarray((belt * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(grow))
rest = Image.fromarray((np.stack([np.zeros_like(belt), reg_g, dark_cloth], 2) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
mask = Image.merge("RGB", (bimg, rest.split()[1], rest.split()[2]))
mask.save(os.path.join(OUT, f"{name}_mask.png"))

# reference colours: the painted skin and the painted cloth
used = np.zeros((N, N), bool)
uvp = np.clip(pix.astype(int), 0, N - 1)
used[uvp[:, 1], uvp[:, 0]] = True
used = np.asarray(Image.fromarray(used.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(9))) > 0
warm = (A[..., 0] > A[..., 1]) & (A[..., 1] > A[..., 2]) & (sat > 0.2) & (sat < 0.7) & (mx > 0.25) & used & (reg_g < 0.5)
cloth = (lum > 0.55) & (sat < 0.12) & used & (reg_g < 0.5) & (reg_r < 0.5)
skin_ref = np.median(A[warm], 0).tolist() if warm.sum() > 50 else [0.75, 0.55, 0.42]
gi_ref = np.median(A[cloth], 0).tolist() if cloth.sum() > 50 else [0.85, 0.85, 0.85]
json.dump({"skin_ref": skin_ref, "gi_ref": gi_ref, "kit": kit, "hips_y": float(hy), "height": float(H)},
          open(os.path.join(OUT, f"{name}.json"), "w"))
print(name, kit, "belt px", int((belt > 0.5).sum()), "skin_ref", np.round(skin_ref, 3), "gi_ref", np.round(gi_ref, 3),
      "verts", len(P), "H", round(H, 3))
