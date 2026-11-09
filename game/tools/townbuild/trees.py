"""Stylized trees for Tatame (Blender, from script). Replaces assets/models/tree_{fat,oak,palm}.glb
in place: same names, same material slots (leafsGreen, woodBark) and roughly the same unit size,
so the world's placement code and wind shader keep working. python3 -I trees.py"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix, noise

OUT = "/home/claude/tatame/assets/models"


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    global LEAF, BARK
    LEAF = bpy.data.materials.new("leafsGreen")
    BARK = bpy.data.materials.new("woodBark")


def blob(center, r, seed, mat, squash=0.8, detail=2):
    """A lumpy foliage clump: subdivided icosphere pushed around by noise."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=detail, radius=r, location=center)
    o = bpy.context.object
    for v in o.data.vertices:
        p = v.co.copy()
        n = noise.noise(p * 2.2 + Vector((seed, seed * 1.7, seed * 0.3)))
        v.co = p * (1.0 + 0.22 * n)
        v.co.z *= squash
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


def trunk(path, r0, r1, mat, sides=7):
    """Tapered tube along a list of points."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(path):
        t = i / (len(path) - 1)
        r = r0 + (r1 - r0) * t
        d = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        a = d.orthogonal().normalized()
        b = d.cross(a)
        ring = [bm.verts.new(p + (a * math.cos(k / sides * 2 * math.pi) + b * math.sin(k / sides * 2 * math.pi)) * r) for k in range(sides)]
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            bm.faces.new([rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]])
    me = bpy.data.meshes.new("trunk")
    bm.to_mesh(me)
    o = bpy.data.objects.new("trunk", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_smooth()
    return o


def finish(name, height):
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    # normalise to the old model's unit height, base at the origin
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    zmin = min(v.co.z for v in o.data.vertices)
    zmax = max(v.co.z for v in o.data.vertices)
    s = height / (zmax - zmin)
    for v in o.data.vertices:
        v.co = Vector((v.co.x * s, v.co.y * s, (v.co.z - zmin) * s))
    bpy.ops.export_scene.gltf(filepath=f"{OUT}/{name}.glb", export_format='GLB', use_selection=True, export_yup=True)
    print("saved", name, "tris", sum(len(p.vertices) - 2 for p in o.data.polygons))


def mango(name="tree_fat", seed=3, height=1.15):
    """Broad mango / fig: short thick trunk, a few limbs, a wide dome of clumps."""
    reset()
    random.seed(seed)
    trunk([Vector((0, 0, 0)), Vector((0.02, 0, 0.7)), Vector((0.05, 0.03, 1.4)), Vector((0.0, 0.05, 1.9))], 0.32, 0.16, BARK)
    for ang in (0.3, 2.4, 4.3):
        a = Vector((math.cos(ang), math.sin(ang), 0))
        trunk([Vector((0, 0, 1.2)), Vector((0, 0, 1.2)) + a * 0.7 + Vector((0, 0, 0.6)), Vector((0, 0, 1.2)) + a * 1.2 + Vector((0, 0, 1.1))], 0.14, 0.06, BARK, 6)
    clumps = [(Vector((0, 0, 2.7)), 1.5)]
    for i in range(9):
        ang = i / 9 * 2 * math.pi + random.uniform(-0.2, 0.2)
        rr = random.uniform(1.1, 1.6)
        clumps.append((Vector((math.cos(ang) * rr, math.sin(ang) * rr, random.uniform(2.1, 2.9))), random.uniform(0.85, 1.15)))
    for i, (c, r) in enumerate(clumps):
        blob(c, r, seed + i * 3.1, LEAF, squash=0.78)
    finish(name, height)


def oak(name="tree_oak", seed=7, height=1.23):
    """Tall cerrado tree: slender trunk, taller layered crown."""
    reset()
    random.seed(seed)
    trunk([Vector((0, 0, 0)), Vector((0.05, 0, 1.2)), Vector((-0.04, 0.04, 2.4)), Vector((0.02, 0, 3.3))], 0.22, 0.09, BARK)
    for i in range(4):
        ang = i * 1.7 + 0.4
        a = Vector((math.cos(ang), math.sin(ang), 0))
        z = 1.6 + i * 0.4
        trunk([Vector((0, 0, z)), Vector((0, 0, z)) + a * 0.6 + Vector((0, 0, 0.5))], 0.08, 0.04, BARK, 5)
    for i in range(8):
        ang = random.uniform(0, 2 * math.pi)
        rr = random.uniform(0.2, 0.9)
        z = random.uniform(2.6, 3.9)
        blob(Vector((math.cos(ang) * rr, math.sin(ang) * rr, z)), random.uniform(0.7, 1.0), seed + i * 2.3, LEAF, squash=0.85)
    blob(Vector((0, 0, 4.2)), 0.8, seed + 50, LEAF, squash=0.9)
    finish(name, height)


def palm(name="tree_palm", seed=11, height=1.36):
    """Coconut palm: curved ringed trunk, drooping V-folded fronds, a few coconuts."""
    reset()
    random.seed(seed)
    path = [Vector((math.sin(t * 1.4) * 0.6 * t, 0, t * 5.0)) for t in [i / 10 for i in range(11)]]
    trunk(path, 0.2, 0.13, BARK, 8)
    for i in range(1, 10):   # growth rings
        p = path[i]
        bpy.ops.mesh.primitive_torus_add(major_radius=0.2 - i * 0.007, minor_radius=0.03, location=p, major_segments=8, minor_segments=4)
        o = bpy.context.object; o.data.materials.append(BARK)
    top = path[-1]
    bm = bmesh.new()
    n_fronds = 10
    for f in range(n_fronds):
        ang = f / n_fronds * 2 * math.pi + random.uniform(-0.15, 0.15)
        d = Vector((math.cos(ang), math.sin(ang), 0))
        side = Vector((-d.y, d.x, 0))
        L = random.uniform(2.2, 2.8)
        lift = random.uniform(0.3, 0.8)
        segs = 8
        prev = None
        for k in range(segs + 1):
            t = k / segs
            c = top + d * (L * t) + Vector((0, 0, lift * math.sin(t * math.pi * 0.6) - 1.6 * t * t))
            w = 0.42 * math.sin(math.pi * min(1.0, t * 1.15 + 0.05))
            fold = Vector((0, 0, -0.12 * w / 0.42))
            row = [bm.verts.new(c + side * w + fold), bm.verts.new(c), bm.verts.new(c - side * w + fold)]
            if prev:
                bm.faces.new([prev[0], prev[1], row[1], row[0]])
                bm.faces.new([prev[1], prev[2], row[2], row[1]])
            prev = row
    me = bpy.data.meshes.new("fronds")
    bm.to_mesh(me)
    o = bpy.data.objects.new("fronds", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(LEAF)
    sol = o.modifiers.new("s", "SOLIDIFY"); sol.thickness = 0.03
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="s")
    bpy.ops.object.shade_smooth()
    for i in range(4):
        ang = i * 1.6
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=top + Vector((math.cos(ang) * 0.18, math.sin(ang) * 0.18, -0.25)), segments=8, ring_count=5)
        c = bpy.context.object; c.data.materials.append(BARK)
    finish(name, height)


if __name__ == "__main__":
    mango()
    oak()
    palm()
