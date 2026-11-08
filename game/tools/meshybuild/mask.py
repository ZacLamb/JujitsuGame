"""Bakes a recolour mask texture for a Meshy body: R = belt texels, G = bare skin regions (head,
hands, feet). Rasterises the triangles in UV space using the per-vertex region flags from skin.py
and the albedo's darkness. Usage: python3 mask.py meshy_male"""
import sys, json, numpy as np
from PIL import Image, ImageFilter
nm = sys.argv[1]
d = json.load(open(f"{nm}.json"))
alb = np.asarray(Image.open(f"{nm}_albedo.png").convert("RGB")).astype(np.float32) / 255
N = alb.shape[0]
UV = np.array(d["uv"]) * (N - 1)
C = np.array(d["c"])
I = np.array(d["i"])
reg_r = np.zeros((N, N), np.float32)
reg_g = np.zeros((N, N), np.float32)
for t in I:
    p = UV[t]
    r = C[t, 0].mean(); g = C[t, 1].mean()
    if r < 0.01 and g < 0.01:
        continue
    x0, y0 = np.floor(p.min(0)).astype(int); x1, y1 = np.ceil(p.max(0)).astype(int)
    x0, y0 = max(x0 - 1, 0), max(y0 - 1, 0); x1, y1 = min(x1 + 1, N - 1), min(y1 + 1, N - 1)
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    a, b, c = p
    den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(den) < 1e-9:
        continue
    l1 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
    l2 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
    l3 = 1 - l1 - l2
    inside = (l1 >= -0.02) & (l2 >= -0.02) & (l3 >= -0.02)
    sl = (slice(y0, y1 + 1), slice(x0, x1 + 1))
    if r > 0.01:
        reg_r[sl] = np.maximum(reg_r[sl], inside * r)
    if g > 0.01:
        reg_g[sl] = np.maximum(reg_g[sl], inside * g)
lum = alb @ np.array([0.299, 0.587, 0.114], np.float32)
mx = alb.max(2); mn = alb.min(2)
sat = (mx - mn) / np.maximum(mx, 1e-3) * np.clip((mx - 0.04) / 0.12, 0, 1)
dark = np.clip((0.3 - lum) / 0.12, 0, 1) * np.clip((0.45 - sat) / 0.15, 0, 1)
belt = reg_r * (1 - reg_g) * dark
img = np.stack([belt, reg_g, np.zeros_like(belt)], 2)
out = Image.fromarray((img * 255).astype(np.uint8))
# dilate into the gutters so mip levels don't bleed the gi in
out = out.filter(ImageFilter.MaxFilter(3))
out.save(f"{nm}_mask.png")
print(nm, "belt texels", int((belt > 0.5).sum()), "skin texels", int((reg_g > 0.5).sum()))
