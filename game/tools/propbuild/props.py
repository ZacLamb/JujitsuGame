"""Low-poly world props for Tatame, modelled from primitives in Blender and exported as GLB with
flat colours (the game's toon look).  python3 -I props.py   ->  assets/models/props/<name>.glb"""
import bpy, math, os
from mathutils import Vector
OUT = "/home/claude/tatame/assets/models/props"
os.makedirs(OUT, exist_ok=True)
_mats = {}

def mat(name, rgb, rough=0.8):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*[c ** 2.2 for c in rgb], 1)
    b.inputs["Roughness"].default_value = rough
    _mats[name] = m
    return m

def _done(o, m, bevel=0.0):
    o.data.materials.append(m)
    if bevel > 0:
        mod = o.modifiers.new("b", "BEVEL"); mod.width = bevel; mod.segments = 1
    return o

def box(size, loc, m, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object; o.scale = size
    return _done(o, m, bevel)

def cyl(r, h, loc, m, rot=(0, 0, 0), v=12, r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, rotation=rot, vertices=v)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, location=loc, rotation=rot, vertices=v)
    return _done(bpy.context.object, m)

def sphere(r, loc, m, scale=(1, 1, 1), seg=10):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=seg, ring_count=max(6, seg // 2))
    o = bpy.context.object; o.scale = scale
    bpy.ops.object.shade_smooth()
    return _done(o, m)

def export(name):
    for o in bpy.context.scene.objects:
        o.select_set(o.type == 'MESH')
    bpy.context.view_layer.objects.active = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
    bpy.ops.object.convert(target='MESH')
    bpy.ops.object.join()
    bpy.ops.export_scene.gltf(filepath=f"{OUT}/{name}.glb", export_format='GLB', export_yup=True, export_apply=True)
    print("prop", name, len(bpy.context.object.data.polygons))

def new():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()

WOOD = (0.55, 0.36, 0.2); DARKWOOD = (0.36, 0.23, 0.13); METAL = (0.42, 0.44, 0.47); BLACK = (0.08, 0.08, 0.09)
RED = (0.85, 0.22, 0.18); YELLOW = (0.98, 0.8, 0.18); GREEN = (0.15, 0.55, 0.3); BLUE = (0.18, 0.42, 0.78)
WHITE = (0.94, 0.93, 0.9); STRAW = (0.86, 0.72, 0.42); SAND = (0.9, 0.82, 0.6)

# 1 heavy bag on a stand
new()
for x in (-0.55, 0.55):
    box((0.08, 0.08, 2.4), (x, 0, 1.2), mat("m", METAL))
box((1.25, 0.1, 0.1), (0, 0, 2.38), mat("m", METAL))
cyl(0.012, 0.35, (0, 0, 2.15), mat("m", METAL), v=6)
cyl(0.2, 1.05, (0, 0, 1.45), mat("bag", RED), v=16)
cyl(0.205, 0.08, (0, 0, 1.92), mat("blk", BLACK), v=16)
cyl(0.205, 0.08, (0, 0, 0.98), mat("blk", BLACK), v=16)
box((1.3, 0.6, 0.06), (0, 0, 0.03), mat("blk", BLACK))
export("heavy_bag")

# 2 wooden bench
new()
w = mat("w", WOOD)
for y in (-0.12, 0.0, 0.12):
    box((1.8, 0.1, 0.05), (0, y, 0.45), w, bevel=0.01)
for x in (-0.75, 0.75):
    box((0.08, 0.36, 0.43), (x, 0, 0.21), mat("d", DARKWOOD))
for z in (0.62, 0.78):
    box((1.8, 0.04, 0.1), (0, 0.2, z), w, bevel=0.01)
export("bench")

# 3 beach kiosk (quiosque) with a thatched roof
new()
for x in (-1.3, 1.3):
    for y in (-1.3, 1.3):
        cyl(0.08, 2.6, (x, y, 1.3), mat("d", DARKWOOD), v=8)
cyl(2.3, 1.1, (0, 0, 3.05), mat("s", STRAW), v=10, r2=0.15)
box((2.6, 0.5, 1.05), (0, -1.1, 0.52), mat("w", WOOD), bevel=0.02)
box((2.7, 0.6, 0.06), (0, -1.1, 1.08), mat("c", (0.95, 0.6, 0.2)))
for i, c in enumerate([RED, YELLOW, GREEN]):
    cyl(0.07, 0.25, (-0.6 + i * 0.6, -1.1, 1.24), mat("can%d" % i, c), v=8)
for x in (-0.9, 0.9):
    cyl(0.18, 0.06, (x, -1.75, 0.7), mat("st", RED), v=10)
    cyl(0.04, 0.68, (x, -1.75, 0.34), mat("m", METAL), v=6)
export("kiosk")

# 4 wooden canoe
new()
hull = sphere(1.0, (0, 0, 0.18), mat("h", (0.42, 0.62, 0.72)), scale=(2.2, 0.48, 0.32), seg=16)
box((4.6, 1.2, 0.4), (0, 0, 0.55), mat("cut", WOOD))
mod = hull.modifiers.new("cut", "BOOLEAN"); mod.object = bpy.data.objects["Cube"]; mod.operation = 'DIFFERENCE'
bpy.context.view_layer.objects.active = hull; bpy.ops.object.modifier_apply(modifier="cut")
bpy.data.objects.remove(bpy.data.objects["Cube"])
for x in (-0.7, 0.7):
    box((0.08, 0.86, 0.04), (x, 0, 0.3), mat("w", WOOD))
box((0.06, 0.06, 1.6), (0.2, 0.25, 0.4), mat("w", WOOD), rot=(0.4, 1.2, 0))
export("canoe")

# 5 açaí cart with umbrella
new()
box((1.4, 0.8, 0.8), (0, 0, 0.75), mat("cart", (0.42, 0.16, 0.45)), bevel=0.03)
box((1.45, 0.85, 0.05), (0, 0, 1.17), mat("top", WHITE))
for x in (-0.55, 0.55):
    cyl(0.25, 0.08, (x, 0.45, 0.25), mat("blk", BLACK), rot=(math.pi / 2, 0, 0), v=14)
cyl(0.025, 1.4, (0, 0, 1.85), mat("m", METAL), v=6)
cyl(1.1, 0.35, (0, 0, 2.55), mat("umb", YELLOW), v=12, r2=0.05)
box((0.5, 0.4, 0.04), (0, -0.42, 0.95), mat("sign", (0.98, 0.95, 0.85)), rot=(0.2, 0, 0))
export("acai_cart")

# 6 street lamp
new()
cyl(0.07, 3.6, (0, 0, 1.8), mat("p", (0.18, 0.22, 0.2)), v=8)
box((0.06, 0.6, 0.06), (0, 0.3, 3.5), mat("p", (0.18, 0.22, 0.2)))
cyl(0.18, 0.25, (0, 0.6, 3.35), mat("p", (0.18, 0.22, 0.2)), v=8, r2=0.06)
sphere(0.12, (0, 0.6, 3.2), mat("glow", (1.0, 0.92, 0.6), 0.3), seg=8)
cyl(0.18, 0.3, (0, 0, 0.15), mat("p", (0.18, 0.22, 0.2)), v=8)
export("street_lamp")

# 7 hammock between two posts
new()
for x in (-1.6, 1.6):
    cyl(0.07, 1.9, (x, 0, 0.95), mat("d", DARKWOOD), v=8)
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0.75))
o = bpy.context.object; o.scale = (3.0, 0.75, 1)
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.subdivide(number_cuts=8); bpy.ops.object.mode_set(mode='OBJECT')
for v in o.data.vertices:
    v.co.z -= (1 - (v.co.x * 2) ** 2) * 0.55
s = o.modifiers.new("s", "SOLIDIFY"); s.thickness = 0.03
_done(o, mat("cloth", (0.92, 0.3, 0.25)))
for i, c in enumerate([YELLOW, GREEN, BLUE]):
    box((0.4, 0.78, 0.02), (-0.8 + i * 0.8, 0, 0.25 + abs(i - 1) * 0.12), mat("stripe%d" % i, c))
export("hammock")

# 8 bar table + plastic chairs (yellow "boteco" set)
new()
y = mat("y", YELLOW, 0.5)
cyl(0.45, 0.04, (0, 0, 0.72), y, v=16)
cyl(0.04, 0.7, (0, 0, 0.36), y, v=8)
cyl(0.25, 0.03, (0, 0, 0.015), y, v=12)
for a in (0, math.pi):
    cx, cy = math.cos(a) * 0.8, math.sin(a) * 0.8
    box((0.42, 0.42, 0.04), (cx, cy, 0.45), y)
    box((0.04, 0.42, 0.45), (cx + 0.2 * (1 if a == 0 else -1), cy, 0.68), y)
    for dx in (-0.18, 0.18):
        for dy in (-0.18, 0.18):
            cyl(0.02, 0.44, (cx + dx, cy + dy, 0.22), y, v=6)
cyl(0.035, 0.24, (0.1, 0, 0.86), mat("bottle", (0.35, 0.22, 0.1), 0.2), v=8)
export("bar_table")

# 9 stack of folded tatami mats
new()
for i in range(5):
    c = GREEN if i % 2 == 0 else (0.86, 0.68, 0.22)
    box((1.0, 2.0, 0.08), (0.01 * (i % 2), 0.02 * (i % 3), 0.04 + i * 0.085), mat("mat%d" % (i % 2), c), bevel=0.01)
export("mat_stack")

# 10 kettlebells and a dumbbell rack
new()
box((1.2, 0.4, 0.08), (0, 0, 0.4), mat("m", METAL))
for x in (-0.55, 0.55):
    box((0.06, 0.4, 0.4), (x, 0, 0.2), mat("m", METAL))
for i, sc in enumerate([0.12, 0.14, 0.16]):
    sphere(sc, (-0.4 + i * 0.4, 0, sc), mat("kb", BLACK, 0.4), seg=10)
    cyl(0.018, 0.16, (-0.4 + i * 0.4, 0, sc * 2 + 0.05), mat("kb", BLACK, 0.4), rot=(0, math.pi / 2, 0), v=6)
for i in range(3):
    cyl(0.02, 0.32, (-0.35 + i * 0.35, 0, 0.5), mat("m", METAL), rot=(0, math.pi / 2, 0), v=6)
    for dx in (-0.12, 0.12):
        cyl(0.06, 0.05, (-0.35 + i * 0.35 + dx, 0, 0.5), mat("blk", BLACK), rot=(0, math.pi / 2, 0), v=10)
export("weights")

# 11 wooden fishing pier segment (4 m)
new()
for i in range(8):
    box((0.48, 2.0, 0.08), (-1.75 + i * 0.5, 0, 0.6), mat("w", WOOD), bevel=0.01)
for x in (-1.9, 1.9):
    for y in (-0.9, 0.9):
        cyl(0.09, 2.0, (x, y, -0.35), mat("d", DARKWOOD), v=8)
export("pier")

# 12 market stall with striped awning
new()
box((2.2, 1.0, 0.9), (0, 0, 0.45), mat("w", WOOD), bevel=0.02)
for x in (-1.05, 1.05):
    for y in (-0.45, 0.45):
        cyl(0.04, 2.3, (x, y, 1.15), mat("d", DARKWOOD), v=6)
for i in range(6):
    box((0.4, 1.35, 0.05), (-1.0 + i * 0.4, -0.15, 2.3), mat("aw%d" % (i % 2), RED if i % 2 == 0 else WHITE), rot=(0.25, 0, 0))
for i, c in enumerate([(0.95, 0.55, 0.15), (0.9, 0.2, 0.15), (0.35, 0.65, 0.2), (0.98, 0.85, 0.2)]):
    for k in range(3):
        sphere(0.09, (-0.8 + i * 0.5 + (k - 1) * 0.12, -0.2 + (k % 2) * 0.15, 0.98), mat("f%d" % i, c), seg=8)
export("market_stall")

# 13 surfboard rack
new()
for x in (-0.9, 0.9):
    box((0.08, 0.5, 1.6), (x, 0, 0.8), mat("w", WOOD))
box((1.9, 0.08, 0.08), (0, -0.2, 1.1), mat("w", WOOD))
for i, c in enumerate([BLUE, YELLOW, RED, WHITE]):
    sphere(1.0, (-0.6 + i * 0.4, 0.05, 0.95), mat("sb%d" % i, c, 0.3), scale=(0.17, 0.05, 0.9), seg=12)
export("surf_rack")

# 14 bus stop shelter
new()
box((2.6, 0.08, 2.2), (0, 0.6, 1.1), mat("gl", (0.65, 0.8, 0.85), 0.2))
for x in (-1.25, 1.25):
    box((0.08, 0.08, 2.4), (x, 0.6, 1.2), mat("m", METAL))
    box((0.08, 0.08, 2.4), (x, -0.4, 1.2), mat("m", METAL))
box((2.8, 1.3, 0.08), (0, 0.1, 2.42), mat("roof", BLUE))
box((2.0, 0.35, 0.06), (0, 0.35, 0.48), mat("w", WOOD))
box((0.9, 0.04, 0.5), (0, -0.45, 2.0), mat("sign", YELLOW))
export("bus_stop")
