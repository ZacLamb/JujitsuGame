"""Coastal kits for Team USA: Everglades (gl_*) and San Diego (sd_*), built with the western kit's
helpers and materials (plus stucco, tile, thatch). python3 -I coastal.py [name ...]"""
import bpy, bmesh, math, sys
from mathutils import Vector

W = {}
src = open("/home/claude/tatame/tools/westbuild/western.py").read().split("\nALL = {")[0]
exec(compile(src, "western.py", "exec"), W)
box, cyl, beam, gable, gable_ends, window, side_window, door, walls, porch, finish, reset = (
    W["box"], W["cyl"], W["beam"], W["gable"], W["gable_ends"], W["window"], W["side_window"], W["door"],
    W["walls"], W["porch"], W["finish"], W["reset"])


def hip(Wd, D, z, rise, over, mat):
    """Hipped roof (all four sides slope), for stucco houses and chickees."""
    w, d = Wd / 2 + over, D / 2 + over
    r = max(0.0, w - d)
    bm = bmesh.new()
    a = bm.verts.new((-r, 0, z + rise)); b = bm.verts.new((r, 0, z + rise))
    c = [bm.verts.new(p) for p in [(-w, -d, z), (w, -d, z), (w, d, z), (-w, d, z)]]
    bm.faces.new([c[0], c[1], b, a]); bm.faces.new([c[2], c[3], a, b])
    bm.faces.new([c[1], c[2], b]); bm.faces.new([c[3], c[0], a])
    me = bpy.data.meshes.new("hip"); bm.normal_update(); bm.to_mesh(me)
    o = bpy.data.objects.new("hip", me); bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(W["M"][mat])
    so = o.modifiers.new("s", "SOLIDIFY"); so.thickness = 0.14 if mat != "thatch" else 0.4; so.offset = -1
    bpy.context.view_layer.objects.active = o; bpy.ops.object.modifier_apply(modifier="s")
    return o


def pilings(Wd, D, h, n=3):
    for i in range(n):
        for j in range(n):
            x = -Wd / 2 + 0.2 + i * (Wd - 0.4) / (n - 1)
            y = -D / 2 + 0.2 + j * (D - 0.4) / (n - 1)
            cyl(0.14, h + 1.0, (x, y, (h - 1.0) / 2), "wood", 8)


def stairs(x, y0, h, run=2.6, w=1.0, axis_y=True):
    steps = max(3, int(h / 0.25))
    for k in range(steps):
        t = (k + 0.5) / steps
        box((w, run / steps + 0.05, 0.08), (x, y0 - run * (1 - t), h * t), "wood")
    beam((x - w / 2, y0 - run, 0.0), (x - w / 2, y0, h + 0.9), 0.08, "wood")
    beam((x + w / 2, y0 - run, 0.0), (x + w / 2, y0, h + 0.9), 0.08, "wood")


# ================================================================== Everglades
def stilt_shack(name="gl_shack", Wd=6.0, D=5.0, H=2.8, lift=1.6):
    """Fish camp shack on pilings: board walls, tin roof, screened front porch, stairs down."""
    reset()
    pilings(Wd, D + 2.0, lift)
    box((Wd + 0.2, D + 2.2, 0.2), (0, -1.0, lift), "wood")                    # deck
    o = box((Wd, D, H), (0, 0, lift + H / 2), "siding")
    gable(Wd, D + 2.0, lift + H, 1.3, 0.35, "tin", along_x=True)
    W["gable_ends"](Wd, D, lift + H, 1.3, "siding", along_x=True) if False else None
    for s in (-1, 1):   # gable infill on the sides
        bm = bmesh.new()
        v = [bm.verts.new(p) for p in [(s * Wd / 2, -D / 2 - 1.0, lift + H), (s * Wd / 2, D / 2 + 1.0, lift + H), (s * Wd / 2, 0, lift + H + 1.3)]]
        bm.faces.new(v)
        me = bpy.data.meshes.new("ge"); bm.to_mesh(me)
        g = bpy.data.objects.new("ge", me); bpy.context.scene.collection.objects.link(g)
        g.data.materials.append(W["M"]["siding"])
    fy = -D / 2
    door(0.8, fy, w=0.9, h=2.0) if False else None
    box((0.9, 0.08, 2.0), (0.9, fy - 0.04, lift + 1.0), "wood")
    window(-1.4, lift + 1.5, fy, w=1.2, h=1.0)
    for x in (-Wd / 2 + 0.1, Wd / 2 - 0.1, -Wd / 6, Wd / 6):              # porch posts + screen
        box((0.12, 0.12, H), (x, fy - 1.9, lift + H / 2), "trim")
    box((Wd, 0.04, H * 0.62), (0, fy - 1.9, lift + 0.4 + H * 0.31), "glass")  # screen mesh
    box((Wd + 0.1, 0.1, 0.8), (0, fy - 1.9, lift + 0.4), "trim")
    stairs(Wd / 2 - 0.7, fy - 2.0, lift, run=2.2, w=0.9)
    cyl(0.3, 0.9, (Wd / 2 - 0.6, D / 2 - 0.6, lift + 0.55), "iron", 10)    # rain barrel
    finish(name)


def chickee(name="gl_chickee", Wd=5.5, D=4.0, H=2.6):
    """Seminole chickee: cypress posts, a raised platform, a steep palmetto-thatch roof, no walls."""
    reset()
    for x in (-Wd / 2, 0.0, Wd / 2):
        for y in (-D / 2, D / 2):
            cyl(0.13, H + 0.6, (x, y, (H + 0.6) / 2), "wood", 7)
    box((Wd + 0.2, D + 0.2, 0.15), (0, 0, 0.75), "wood")
    hip(Wd, D, H + 0.5, 2.1, 0.6, "thatch")
    beam((0, -D / 2, H + 0.5), (0, D / 2, H + 0.5), 0.12, "wood")
    finish(name)


def ranger(name="gl_ranger", Wd=6.0, D=5.0, H=3.0, lift=2.4):
    """Park ranger station on stilts, with a lookout tower and a ramp."""
    reset()
    pilings(Wd, D, lift)
    box((Wd + 1.6, D + 1.6, 0.2), (0, 0, lift), "wood")
    walls(0, 0, 0, "siding") if False else None
    box((Wd, D, H), (0, 0, lift + H / 2), "siding")
    hip(Wd, D, lift + H, 1.0, 0.5, "tin")
    fy = -D / 2
    box((1.0, 0.08, 2.1), (0, fy - 0.04, lift + 1.05), "wood")
    for x in (-1.8, 1.8):
        window(x, lift + 1.6, fy, w=1.2, h=1.0)
    for k in range(12):   # deck railing
        a = k / 12
        box((0.06, 0.06, 0.9), (-Wd / 2 - 0.7 + a * (Wd + 1.4), fy - 0.75, lift + 0.55), "trim")
    box((Wd + 1.4, 0.06, 0.06), (0, fy - 0.75, lift + 1.0), "trim")
    stairs(-Wd / 2 - 0.2, fy - 0.8, lift, run=3.2, w=1.1)
    # lookout tower on the back corner
    T = 9.0
    tx, ty = Wd / 2 - 0.6, D / 2 + 1.6
    for sx in (-1, 1):
        for sy in (-1, 1):
            beam((tx + sx * 1.1, ty + sy * 1.1, 0), (tx + sx * 0.8, ty + sy * 0.8, T), 0.14, "wood")
    for z in (3.0, 6.0):
        for k in range(4):
            a, b = k * math.pi / 2 + math.pi / 4, (k + 1) * math.pi / 2 + math.pi / 4
            r = 1.4 - 0.4 * z / T
            beam((tx + math.cos(a) * r, ty + math.sin(a) * r, z - 3), (tx + math.cos(b) * r, ty + math.sin(b) * r, z), 0.06, "wood")
    box((2.4, 2.4, 0.15), (tx, ty, T), "wood")
    box((2.2, 2.2, 1.0), (tx, ty, T + 0.6), "siding")
    box((2.3, 0.05, 0.6), (tx, ty - 1.12, T + 0.75), "glass")
    hip(2.2, 2.2, T + 1.1, 0.8, 0.3, "tin")
    finish(name)


def airboat(name="gl_airboat"):
    """Flat aluminium hull, raised driver seat, a caged aircraft propeller at the back."""
    reset()
    box((2.0, 4.4, 0.4), (0, 0, 0.2), "trim")
    o = box((2.0, 1.0, 0.4), (0, -2.5, 0.35), "trim")
    o.rotation_euler = (0.4, 0, 0); bpy.context.view_layer.objects.active = o; bpy.ops.object.transform_apply(rotation=True)
    for s in (-1, 1):
        box((0.06, 4.4, 0.35), (s * 1.0, 0, 0.55), "iron")
    box((0.7, 0.7, 1.0), (0, 0.7, 0.9), "iron")                    # seat stand
    box((0.6, 0.5, 0.12), (0, 0.7, 1.45), "base")
    box((0.6, 0.1, 0.5), (0, 0.95, 1.7), "base")
    box((0.6, 0.6, 0.6), (0, 1.5, 0.75), "iron")                   # engine
    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.05, location=(0, 2.0, 1.5), rotation=(math.pi / 2, 0, 0))
    bpy.context.object.data.materials.append(W["M"]["iron"])
    for k in range(4):
        a = k * math.pi / 2
        beam((0, 2.0, 1.5), (math.cos(a), 2.0, 1.5 + math.sin(a)), 0.03, "iron")
    for k in range(2):
        a = k * math.pi
        box((0.12, 0.04, 0.9), (math.cos(a) * 0.45, 1.85, 1.5 + math.sin(a) * 0.45), "wood", rot=(0, -a + math.pi / 2, 0))
    beam((-0.9, 1.6, 0.5), (-0.6, 2.0, 1.4), 0.05, "iron"); beam((0.9, 1.6, 0.5), (0.6, 2.0, 1.4), 0.05, "iron")
    finish(name)


# ================================================================== San Diego
def bungalow(name="sd_bungalow", Wd=8.0, D=7.0, H=3.1):
    """Beach bungalow: board-and-batten walls, low gable, deep porch, big front windows."""
    reset()
    walls(Wd, D, H, "siding")
    box((Wd + 0.1, D + 0.1, 0.4), (0, 0, 0.2), "stone")
    gable(Wd, D, H, 1.3, 0.7, "tin", along_x=False)
    W["gable_ends"](Wd, D, H, 1.3, "siding", along_x=False)
    fy = -D / 2
    door(Wd * 0.25, fy, w=1.0)
    window(-Wd * 0.18, 1.65, fy, w=2.2, h=1.4, panes=True)
    for k in (-1, 1):
        side_window(Wd / 2, 1.7, k * D * 0.2)
        side_window(-Wd / 2, 1.7, k * D * 0.2)
    porch(Wd, 1.8, 2.7, fy, posts=3, rail=True)
    finish(name)


def spanish(name="sd_spanish", Wd=8.0, D=8.0, H=6.4, shop=True):
    """Spanish revival: white stucco, red tile hip roof, arched shop windows, iron balcony."""
    reset()
    walls(Wd, D, H, "stucco")
    hip(Wd, D, H, 1.6, 0.6, "tile")
    fy = -D / 2
    if shop:
        for sx in (-1, 1):
            window(sx * Wd * 0.27, 1.5, fy, w=2.2, h=2.0, panes=False, cap=False, frame="wood")
            bpy.ops.mesh.primitive_cylinder_add(radius=1.1, depth=0.1, location=(sx * Wd * 0.27, fy + 0.07, 2.5), rotation=(math.pi / 2, 0, 0), vertices=16)
            bpy.context.object.data.materials.append(W["M"]["glass"])
        door(0, fy, w=1.1, h=2.6, frame="wood")
    else:
        door(-Wd * 0.25, fy, w=1.1, frame="wood")
        window(Wd * 0.2, 1.7, fy, w=1.2, h=1.5, frame="wood")
    if H > 5.0:
        for x in (-Wd * 0.27, Wd * 0.27):
            window(x, 4.8, fy, w=1.1, h=1.6, frame="wood")
        box((Wd * 0.7, 0.9, 0.12), (0, fy - 0.45, 3.9), "stucco")            # balcony slab
        for k in range(14):
            box((0.03, 0.03, 0.85), (-Wd * 0.35 + k * Wd * 0.7 / 13, fy - 0.85, 4.38), "iron")
        box((Wd * 0.7, 0.05, 0.05), (0, fy - 0.85, 4.82), "iron")
    zw = 4.8 if H > 5.0 else 1.8
    for k in (-1, 1):
        side_window(Wd / 2, zw, k * D * 0.2, frame="wood")
        side_window(-Wd / 2, zw, k * D * 0.2, frame="wood")
    finish(name)


def lifeguard(name="sd_lifeguard"):
    """The beach lifeguard tower: a little cabin on stilts, ramp down to the sand, a flag pole."""
    reset()
    lift = 2.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl(0.1, lift, (sx * 1.1, sy * 1.1, lift / 2), "trim", 6)
    beam((-1.1, -1.1, 0.3), (1.1, 1.1, lift - 0.2), 0.06, "trim")
    box((3.4, 3.4, 0.15), (0, 0, lift), "wood")
    box((2.6, 2.4, 2.0), (0, 0.3, lift + 1.0), "siding")
    box((2.5, 0.05, 0.9), (0, -0.92, lift + 1.35), "glass")
    for sx in (-1, 1):
        box((0.05, 2.0, 0.9), (sx * 1.31, 0.3, lift + 1.35), "glass")
    hip(2.6, 2.4, lift + 2.0, 0.7, 0.5, "tin")
    o = box((1.0, 4.6, 0.1), (0, -3.7, lift / 2), "wood")
    o.rotation_euler = (-math.atan2(lift, 4.4), 0, 0); bpy.context.view_layer.objects.active = o; bpy.ops.object.transform_apply(rotation=True)
    for k in range(10):
        box((3.2 if k == 0 else 0.05, 0.05, 0.8 if k else 0.05), (-1.65 + k * 0.33 if k else 0, -1.65, lift + 0.45), "trim")
    cyl(0.04, 3.0, (1.4, 1.4, lift + 2.4), "iron", 5)
    finish(name)


def surf_shop(name="sd_surfshop", Wd=9.0, D=8.0, H=4.0):
    """Flat-roof stucco surf shop with a glass front and an awning (the game paints the sign)."""
    reset()
    walls(Wd, D, H, "stucco")
    fy = -D / 2
    box((Wd + 0.3, D + 0.3, 0.3), (0, 0, H + 0.1), "trim")
    box((Wd, 0.3, 1.1), (0, fy - 0.05, H + 0.75), "stucco")                 # parapet / sign band
    window(-Wd * 0.22, 1.5, fy, w=Wd * 0.42, h=2.2, panes=False, cap=False, frame="iron")
    door(Wd * 0.3, fy, w=1.3, h=2.5, frame="iron")
    o = box((Wd - 0.6, 1.8, 0.06), (0, fy - 0.9, 2.9), "tin")
    o.rotation_euler = (0.3, 0, 0); bpy.context.view_layer.objects.active = o; bpy.ops.object.transform_apply(rotation=True)
    for k in range(3):
        b = box((0.55, 0.08, 2.3), (Wd / 2 + 0.25, -1.5 + k * 0.8, 1.2), "trim")
        b.rotation_euler = (0, 0.18, 0)
    finish(name)

# ================================================================== Sedona / Arizona
def adobe(name="az_adobe", Wd=7.0, D=7.0, H=3.6, portal=True):
    """Pueblo Revival: rounded stucco walls, flat roof behind a soft parapet, protruding vigas,
    deep-set windows with painted (turquoise) frames, and a wooden portal porch."""
    reset()
    walls(Wd, D, H, "stucco")
    # soft parapet: slightly rounded lumps on top of every wall
    for sx in (-1, 1):
        box((0.35, D + 0.1, 0.5), (sx * (Wd / 2 - 0.12), 0, H + 0.2), "stucco")
    for sy in (-1, 1):
        box((Wd + 0.1, 0.35, 0.5), (0, sy * (D / 2 - 0.12), H + 0.2), "stucco")
    box((Wd - 0.6, D - 0.6, 0.1), (0, 0, H - 0.1), "base")
    for k in range(6):   # vigas through the front and side walls
        x = -Wd / 2 + 0.6 + k * (Wd - 1.2) / 5
        cyl(0.11, 0.9, (x, -D / 2 - 0.3, H - 0.45), "wood", 7, rot=(math.pi / 2, 0, 0))
    fy = -D / 2
    door(-Wd * 0.22, fy, w=1.0, h=2.2, frame="wood")
    window(Wd * 0.22, 1.7, fy, w=1.1, h=1.2, frame="wood")
    for k in (-1, 1):
        side_window(Wd / 2, 1.7, k * D * 0.2, w=0.8, h=1.0, frame="wood")
        side_window(-Wd / 2, 1.7, k * D * 0.2, w=0.8, h=1.0, frame="wood")
    if portal:
        P = 2.2
        for k in range(4):
            x = -Wd / 2 + 0.3 + k * (Wd - 0.6) / 3
            cyl(0.13, 2.7, (x, fy - P, 1.35), "wood", 8)
            box((0.6, 0.22, 0.22), (x, fy - P, 2.72), "wood")   # corbel
        box((Wd, 0.28, 0.28), (0, fy - P, 2.95), "wood")
        box((Wd + 0.2, P + 0.3, 0.12), (0, fy - P / 2, 3.12), "base")
        for k in range(10):
            box((0.08, P + 0.2, 0.08), (-Wd / 2 + 0.2 + k * (Wd - 0.4) / 9, fy - P / 2, 3.03), "wood")
        box((Wd, P, 0.15), (0, fy - P / 2, 0.07), "stone")
    finish(name)


def pueblo(name="az_pueblo", Wd=10.0, D=9.0):
    """Two stepped storeys, like a pueblo: the upper block set back with a roof terrace and a ladder."""
    reset()
    H1, H2 = 3.4, 3.0
    box((Wd, D, H1), (0, 0, H1 / 2), "stucco")
    box((Wd * 0.55, D * 0.6, H2), (Wd * 0.18, D * 0.15, H1 + H2 / 2), "stucco")
    for (w, d, z, cx, cy) in ((Wd, D, H1, 0, 0), (Wd * 0.55, D * 0.6, H1 + H2, Wd * 0.18, D * 0.15)):
        for sx in (-1, 1):
            box((0.32, d + 0.1, 0.45), (cx + sx * (w / 2 - 0.12), cy, z + 0.18), "stucco")
        for sy in (-1, 1):
            box((w + 0.1, 0.32, 0.45), (cx, cy + sy * (d / 2 - 0.12), z + 0.18), "stucco")
        for k in range(5):
            x = cx - w / 2 + 0.5 + k * (w - 1.0) / 4
            cyl(0.1, 0.8, (x, cy - d / 2 - 0.28, z - 0.4), "wood", 7, rot=(math.pi / 2, 0, 0))
    fy = -D / 2
    door(-Wd * 0.3, fy, w=1.0, h=2.2, frame="wood")
    for x in (-Wd * 0.05, Wd * 0.3):
        window(x, 1.7, fy, w=1.0, h=1.1, frame="wood")
    window(Wd * 0.18, H1 + 1.6, -D * 0.15, w=1.0, h=1.0, frame="wood")
    for k in range(2):   # ladder up to the terrace
        beam((-Wd * 0.25 + k * 0.6, fy - 0.9, 0), (-Wd * 0.25 + k * 0.6, fy + 0.6, H1 + 1.2), 0.08, "wood")
    for k in range(7):
        t = (k + 0.5) / 7
        beam((-Wd * 0.25, fy - 0.9 + 1.5 * t, (H1 + 1.2) * t), (-Wd * 0.25 + 0.6, fy - 0.9 + 1.5 * t, (H1 + 1.2) * t), 0.05, "wood")
    for k in (-1, 1):
        side_window(Wd / 2, 1.7, k * D * 0.2, w=0.8, h=1.0, frame="wood")
        side_window(-Wd / 2, 1.7, k * D * 0.2, w=0.8, h=1.0, frame="wood")
    finish(name)


ALL = {"adobe": adobe, "adobe_small": lambda: adobe("az_adobe_small", Wd=5.5, D=5.5, H=3.2, portal=False), "pueblo": pueblo, "shack": stilt_shack, "chickee": chickee, "ranger": ranger, "airboat": airboat,
       "bungalow": bungalow, "spanish": spanish, "spanish_house": lambda: spanish("sd_spanish_house", Wd=9.0, D=8.0, H=3.6, shop=False),
       "lifeguard": lifeguard, "surfshop": surf_shop}

if __name__ == "__main__":
    want = [a for a in sys.argv[1:] if a in ALL] or list(ALL)
    for k in want:
        ALL[k]()
