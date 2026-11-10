"""Texas Hill Country / desert flora for Team USA zones (Blender, from script).
python3 -I flora.py  ->  assets/models/{tree_liveoak,tree_mesquite,tree_cedar,cactus_pear,yucca}.glb
Same material slots as the Brazilian trees (leafsGreen, woodBark) so the world's tinting and the
wind shader keep working; heights are normalised the same way (world code scales them ~5x)."""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector
sys.path.insert(0, "/home/claude/tatame/tools/townbuild")
os.environ.setdefault("NOBUILD", "1")
import importlib.util
spec = importlib.util.spec_from_file_location("trees", "/home/claude/tatame/tools/townbuild/trees.py")
T = importlib.util.module_from_spec(spec)
src = open("/home/claude/tatame/tools/townbuild/trees.py").read()
src = src.split("\nif __name__")[0]   # helpers only, don't rebuild the Brazilian trees
exec(compile(src, "trees.py", "exec"), T.__dict__)


def liveoak(name="tree_liveoak", seed=21, height=1.05):
    """Live oak: short twisted trunk, long near-horizontal limbs, a wide, low, flat-topped canopy."""
    T.reset()
    random.seed(seed)
    T.trunk([Vector((0, 0, 0)), Vector((0.1, 0.05, 0.6)), Vector((0.05, 0.12, 1.1))], 0.36, 0.24, T.BARK, 8)
    for i in range(5):
        ang = i / 5 * 2 * math.pi + random.uniform(-0.3, 0.3)
        a = Vector((math.cos(ang), math.sin(ang), 0))
        L = random.uniform(2.0, 2.8)
        p0 = Vector((0.05, 0.1, 1.0))
        T.trunk([p0, p0 + a * L * 0.4 + Vector((0, 0, 0.5)), p0 + a * L * 0.8 + Vector((0, 0, 0.55)), p0 + a * L + Vector((0, 0, 0.9))], 0.17, 0.05, T.BARK, 6)
    clumps = [(Vector((0, 0, 2.3)), 1.4)]
    for i in range(14):
        ang = i / 14 * 2 * math.pi + random.uniform(-0.2, 0.2)
        rr = random.uniform(1.4, 2.7)
        clumps.append((Vector((math.cos(ang) * rr, math.sin(ang) * rr, random.uniform(1.8, 2.4))), random.uniform(0.75, 1.05)))
    for i, (c, r) in enumerate(clumps):
        T.blob(c, r, seed + i * 2.7, T.LEAF, squash=0.55)
    T.finish(name, height)


def mesquite(name="tree_mesquite", seed=33, height=0.95):
    """Mesquite: multi-stemmed, leaning, wiry branches, thin airy clumps."""
    T.reset()
    random.seed(seed)
    tips = []
    for s in range(3):
        ang = s * 2.1 + 0.3
        a = Vector((math.cos(ang), math.sin(ang), 0))
        p = [Vector((0, 0, 0)), a * 0.3 + Vector((0, 0, 0.9)), a * 0.9 + Vector((0, 0, 1.7)), a * 1.3 + Vector((0, 0, 2.3))]
        T.trunk(p, 0.13, 0.05, T.BARK, 6)
        tips.append(p[-1]); tips.append(p[-2])
    for i, c in enumerate(tips):
        for k in range(2):
            o = Vector((random.uniform(-0.6, 0.6), random.uniform(-0.6, 0.6), random.uniform(0.0, 0.5)))
            T.blob(c + o, random.uniform(0.5, 0.75), seed + i * 4.1 + k, T.LEAF, squash=0.5, detail=1)
    T.finish(name, height)


def cedar(name="tree_cedar", seed=45, height=1.1):
    """Ashe juniper ('cedar'): dense, dark, roughly conical, from the ground up."""
    T.reset()
    random.seed(seed)
    T.trunk([Vector((0, 0, 0)), Vector((0, 0, 1.0))], 0.16, 0.1, T.BARK, 6)
    for i in range(9):
        z = 0.6 + i * 0.38
        r = 1.35 * (1.0 - i / 10) + 0.25
        for k in range(3):
            ang = random.uniform(0, 2 * math.pi)
            rr = random.uniform(0.0, r * 0.45)
            T.blob(Vector((math.cos(ang) * rr, math.sin(ang) * rr, z)), r * random.uniform(0.6, 0.8), seed + i * 3 + k, T.LEAF, squash=0.75, detail=1)
    T.finish(name, height)


def prickly_pear(name="cactus_pear", seed=57, height=0.32):
    """Prickly pear: flat oval pads stacked at angles, a few red fruit on the rims."""
    T.reset()
    random.seed(seed)
    fruit = bpy.data.materials.new("colorRed")

    def pad(c, ang, tilt, s):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, location=c, segments=12, ring_count=8)
        o = bpy.context.object
        o.scale = (0.42 * s, 0.1 * s, 0.55 * s)
        o.rotation_euler = (0, tilt, ang)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        o.data.materials.append(T.LEAF)
        bpy.ops.object.shade_smooth()
        return o

    pads = [(Vector((0, 0, 0.5)), 0.0, 0.0, 1.0)]
    frontier = [pads[0]]
    for gen in range(2):
        new = []
        for (c, ang, tilt, s) in frontier:
            for k in range(random.randint(2, 3)):
                a2 = ang + random.uniform(-0.8, 0.8)
                t2 = random.uniform(-0.7, 0.7)
                s2 = s * random.uniform(0.75, 0.9)
                off = Vector((math.cos(ang) * math.sin(t2) * 0.5, math.sin(ang) * math.sin(t2) * 0.5, 0.75 * s))
                new.append((c + off, a2, t2, s2))
        pads += new
        frontier = new
    for (c, ang, tilt, s) in pads:
        pad(c, ang, tilt, s)
    for (c, ang, tilt, s) in frontier[:5]:
        bpy.ops.mesh.primitive_ico_sphere_add(radius=0.07, location=c + Vector((0, 0, 0.55 * s)), subdivisions=1)
        bpy.context.object.data.materials.append(fruit)
    T.finish(name, height)


def yucca(name="yucca", seed=69, height=0.38):
    """Yucca: a rosette of stiff sword leaves and one tall flower stalk."""
    T.reset()
    random.seed(seed)
    bm = bmesh.new()
    for i in range(34):
        ang = i * 2.399 + random.uniform(-0.1, 0.1)
        up = random.uniform(0.35, 1.2)
        d = Vector((math.cos(ang) * math.cos(up), math.sin(ang) * math.cos(up), math.sin(up)))
        side = Vector((-math.sin(ang), math.cos(ang), 0)) * 0.05
        L = random.uniform(0.9, 1.3)
        base = Vector((0, 0, 0.25))
        v = [bm.verts.new(base + side), bm.verts.new(base - side), bm.verts.new(base + d * L)]
        bm.faces.new(v)
    me = bpy.data.meshes.new("leaves"); bm.to_mesh(me)
    o = bpy.data.objects.new("leaves", me); bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(T.LEAF)
    so = o.modifiers.new("s", "SOLIDIFY"); so.thickness = 0.02
    bpy.context.view_layer.objects.active = o; bpy.ops.object.modifier_apply(modifier="s")
    T.trunk([Vector((0, 0, 0.2)), Vector((0.05, 0, 1.6)), Vector((0.02, 0.03, 2.6))], 0.04, 0.02, T.BARK, 5)
    cream = bpy.data.materials.new("woodInner")
    for k in range(10):
        z = 1.9 + k * 0.08
        bpy.ops.mesh.primitive_ico_sphere_add(radius=0.12 - k * 0.006, location=(0.03 + random.uniform(-0.08, 0.08), random.uniform(-0.08, 0.08), z), subdivisions=1)
        bpy.context.object.data.materials.append(cream)
    T.finish(name, height)


if __name__ == "__main__":
    T.OUT = "/home/claude/tatame/assets/models"
    for f in (liveoak, mesquite, cedar, prickly_pear, yucca):
        f()
