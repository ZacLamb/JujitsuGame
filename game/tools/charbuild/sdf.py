"""Signed-distance sculpting helpers (numpy). Shapes are functions P(N,3) -> d(N).
Smooth unions blend anatomy into one clean surface; marching cubes turns it into a mesh."""
import numpy as np
from skimage import measure


def V(*a):
    return np.array(a, dtype=float)


def sphere(c, r):
    c = V(*c)
    return lambda P: np.linalg.norm(P - c, axis=1) - r


def ellipsoid(c, rad, rot=None):
    """Approximate SDF of an ellipsoid (iq's bound), optional 3x3 rotation (world->local rows)."""
    c = V(*c)
    rad = V(*rad)
    R = np.eye(3) if rot is None else np.asarray(rot)

    def f(P):
        q = (P - c) @ R.T
        k0 = np.linalg.norm(q / rad, axis=1)
        k1 = np.linalg.norm(q / (rad * rad), axis=1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
    return f


def round_cone(a, b, r1, r2):
    """Exact SDF of a capsule tapering from radius r1 at a to r2 at b (iq)."""
    a = V(*a)
    b = V(*b)
    ba = b - a
    l2 = ba @ ba
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2

    def f(P):
        pa = P - a
        y = pa @ ba
        z = y - l2
        xv = pa * l2 - np.outer(y, ba)
        x2 = np.einsum('ij,ij->i', xv, xv)
        y2 = y * y * l2
        z2 = z * z * l2
        k = np.sign(rr) * rr * rr * x2
        out = np.empty(len(P))
        m1 = np.sign(z) * a2 * z2 > k
        m2 = np.sign(y) * a2 * y2 < k
        m3 = ~(m1 | m2)
        out[m1] = np.sqrt(x2[m1] + z2[m1]) * il2 - r2
        out[m2] = np.sqrt(x2[m2] + y2[m2]) * il2 - r1
        out[m3] = (np.sqrt(x2[m3] * a2 * il2) + y[m3] * rr) * il2 - r1
        return out
    return f


def box(c, half, rot=None, r=0.0):
    c = V(*c)
    half = V(*half)
    R = np.eye(3) if rot is None else np.asarray(rot)

    def f(P):
        q = np.abs((P - c) @ R.T) - half
        return np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(np.max(q, axis=1), 0) - r
    return f


def plane(n, d):
    """Half-space n.p > d is OUTSIDE (positive)."""
    n = V(*n)
    n = n / np.linalg.norm(n)
    return lambda P: P @ n - d


def smin(fs, k):
    def f(P):
        d = fs[0](P)
        for g in fs[1:]:
            d2 = g(P)
            h = np.clip(0.5 + 0.5 * (d2 - d) / k, 0, 1)
            d = d2 * (1 - h) + d * h - k * h * (1 - h)
        return d
    return f


def union(fs):
    def f(P):
        d = fs[0](P)
        for g in fs[1:]:
            d = np.minimum(d, g(P))
        return d
    return f


def smax(a, b, k):
    """Smooth intersection."""
    def f(P):
        d1, d2 = a(P), b(P)
        h = np.clip(0.5 - 0.5 * (d2 - d1) / k, 0, 1)
        return d2 * (1 - h) + d1 * h + k * h * (1 - h)
    return f


def subtract(a, b, k=0.0):
    nb = lambda P: -b(P)
    if k > 0:
        return smax(a, nb, k)
    return lambda P: np.maximum(a(P), -b(P))


def intersect(a, b):
    return lambda P: np.maximum(a(P), b(P))


def offset(f, o):
    return lambda P: f(P) - o


def shell(f, outer, inner):
    """Hollow layer between offsets inner..outer of f (clothing)."""
    return lambda P: np.maximum(f(P) - outer, -(f(P) - inner))


def mesh(f, lo, hi, step):
    lo = np.asarray(lo, float)
    hi = np.asarray(hi, float)
    n = np.ceil((hi - lo) / step).astype(int) + 1
    xs = [lo[i] + np.arange(n[i]) * step for i in range(3)]
    G = np.stack(np.meshgrid(*xs, indexing='ij'), -1).reshape(-1, 3)
    d = np.empty(len(G))
    for s in range(0, len(G), 400000):
        d[s:s + 400000] = f(G[s:s + 400000])
    d = d.reshape(n)
    if d.min() > 0 or d.max() < 0:
        return None, None
    verts, faces, _, _ = measure.marching_cubes(d, 0.0, spacing=(step, step, step))
    return verts + lo, faces
