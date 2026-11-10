"""Tiling textures for the Team USA (western / Hill Country) kit. python3 -I textures.py
Writes assets/textures/env/{siding,brick,limestone,tin,prairie,caliche}.jpg (512x512, seamless)."""
import numpy as np
from PIL import Image, ImageFilter

OUT = "/home/claude/tatame/assets/textures/env"
N = 512
rng = np.random.default_rng(7)


def tnoise(scale, octaves=4, seed=0):
    """Seamless value noise (sum of octaves), 0..1."""
    r = np.random.default_rng(seed)
    acc = np.zeros((N, N))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        g = max(2, int(scale * 2 ** o))
        grid = r.random((g, g))
        img = Image.fromarray((grid * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
        # make it wrap: blend with rolled copy
        a = np.asarray(img, dtype=float) / 255
        acc += a * amp
        tot += amp
        amp *= 0.5
    acc /= tot
    # wrap by mirrored cross-fade
    w = np.linspace(0, 1, N)
    fx = np.minimum(w, 1 - w) * 2
    acc = acc * fx[None, :] + np.roll(acc, N // 2, axis=1) * (1 - fx[None, :])
    acc = acc * fx[:, None] + np.roll(acc, N // 2, axis=0) * (1 - fx[:, None])
    return (acc - acc.min()) / (acc.max() - acc.min() + 1e-9)


def save(name, rgb):
    Image.fromarray(np.clip(rgb * 255, 0, 255).astype(np.uint8)).save(f"{OUT}/{name}.jpg", quality=90)
    print("saved", name)


y = np.arange(N)[:, None].repeat(N, 1)
x = np.arange(N)[None, :].repeat(N, 0)

# clapboard siding: 8 boards per tile, each with a shadow lip at the bottom and wood grain
n = tnoise(3, 3, 1)
grain = tnoise(40, 2, 2)
board = (y % 64) / 64.0
shade = 0.88 + 0.1 * board - 0.35 * (board > 0.9) - 0.12 * (board < 0.06)
v = shade * (0.9 + 0.08 * n + 0.05 * (np.sin(x / 7.0 + grain * 9) * 0.5))
save("siding", np.stack([v * 0.93, v * 0.92, v * 0.9], -1))

# brick: running bond, 16 courses, mortar lines, per-brick tone
course = y // 32
off = (course % 2) * 32
bx = (x + off) // 64
tone = np.random.default_rng(3).random((20, 20))
t = tone[course % 16, bx % 8]
mortar = ((y % 32) < 3) | (((x + off) % 64) < 3)
n2 = tnoise(12, 3, 4)
r = 0.62 + 0.12 * t + 0.08 * n2
col = np.stack([r, r * 0.42, r * 0.32], -1)
col[mortar] = np.stack([0.78 + 0.05 * n2, 0.75 + 0.05 * n2, 0.7 + 0.05 * n2], -1)[mortar]
save("brick", col)

# limestone blocks: big cut blocks, pale cream, pitted
course = y // 64
off = (course % 2) * 64
joint = ((y % 64) < 2) | (((x + off) % 128) < 2)
pits = tnoise(30, 2, 6)
n3 = tnoise(5, 4, 5)
v = 0.86 + 0.08 * n3 - 0.1 * (pits > 0.82)
col = np.stack([v * 0.98, v * 0.93, v * 0.8], -1)
col[joint] *= 0.72
save("limestone", col)

# corrugated tin: vertical ribs, a little rust
rib = 0.5 + 0.5 * np.cos(x / N * 2 * np.pi * 16)
rust = tnoise(6, 4, 8)
v = 0.62 + 0.25 * rib
col = np.stack([v, v * 1.0, v * 1.03], -1)
rm = np.clip((rust - 0.62) * 1.2, 0, 0.35)[..., None]
col = col * (1 - rm) + np.stack([0.5 * v, 0.3 * v, 0.18 * v], -1) * rm
save("tin", col)

# prairie: dry golden grass with green flecks and bare patches
n4 = tnoise(6, 5, 9)
blades = tnoise(80, 2, 10)
v = 0.75 + 0.2 * blades
base = np.stack([0.78 * v, 0.66 * v, 0.38 * v], -1)
green = np.stack([0.45 * v, 0.55 * v, 0.28 * v], -1)
g = np.clip((n4 - 0.55) * 3, 0, 1)[..., None]
col = base * (1 - g) + green * g
bare = np.clip((0.25 - n4) * 4, 0, 1)[..., None]
col = col * (1 - bare) + np.stack([0.72 * v, 0.62 * v, 0.48 * v], -1) * bare
save("prairie", col)

# caliche: pale chalky dirt with pebbles
n5 = tnoise(8, 5, 11)
peb = tnoise(60, 1, 12)
v = 0.8 + 0.12 * n5 - 0.15 * (peb > 0.8)
save("caliche", np.stack([v * 0.9, v * 0.83, v * 0.7], -1))

# thatch (palmetto fronds on a chickee roof): long overlapping straw strands in rows
n6 = tnoise(4, 4, 13)
strands = tnoise(90, 1, 14)
rows = (y % 48) / 48.0
v = 0.62 + 0.25 * strands - 0.25 * (rows > 0.85) + 0.08 * n6
save("thatch", np.stack([v * 0.78, v * 0.66, v * 0.42], -1))

# stucco: soft, lumpy plaster (tinted per building in game)
n7 = tnoise(10, 5, 15)
v = 0.88 + 0.08 * n7
save("stucco", np.stack([v, v * 0.98, v * 0.95], -1))
