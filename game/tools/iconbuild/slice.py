"""Slice a 4x4 painted icon sheet into 128px PNGs. Finds the black gutters by scanning
row/column brightness, falling back to an even split."""
import sys
from PIL import Image
import numpy as np

def cuts(profile, n=4):
    L = len(profile)
    out = [0]
    for k in range(1, n):
        c = int(L * k / n)
        w = L // 14
        seg = profile[c - w:c + w]
        out.append(c - w + int(np.argmin(seg)))
    out.append(L)
    return out

def main(sheet, names, outdir, size=128):
    im = Image.open(sheet).convert("RGB")
    a = np.asarray(im).astype(float).mean(axis=2)
    xs = cuts(a.mean(axis=0)); ys = cuts(a.mean(axis=1))
    names = names.split(",")
    for j in range(4):
        for i in range(4):
            n = names[j * 4 + i]
            x0, x1, y0, y1 = xs[i], xs[i + 1], ys[j], ys[j + 1]
            # trim gutter: shrink until edge rows/cols are not black
            tile = np.asarray(im.crop((x0, y0, x1, y1))).astype(float).mean(axis=2)
            t, b, l, r = 0, tile.shape[0], 0, tile.shape[1]
            while t < b // 4 and tile[t, :].mean() < 18: t += 1
            while b > tile.shape[0] * 3 // 4 and tile[b - 1, :].mean() < 18: b -= 1
            while l < r // 4 and tile[:, l].mean() < 18: l += 1
            while r > tile.shape[1] * 3 // 4 and tile[:, r - 1].mean() < 18: r -= 1
            pad = 4
            box = (x0 + l + pad, y0 + t + pad, x0 + r - pad, y0 + b - pad)
            w, h = box[2] - box[0], box[3] - box[1]
            s = min(w, h); cx, cy = box[0] + w // 2, box[1] + h // 2
            box = (cx - s // 2, cy - s // 2, cx - s // 2 + s, cy - s // 2 + s)
            im.crop(box).resize((size, size), Image.LANCZOS).save(f"{outdir}/{n}.png")
            print(n, box)

if __name__ == "__main__":
    main(*sys.argv[1:4])
