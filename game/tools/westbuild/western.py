"""Western / Texas Hill Country building kit for Team USA (Blender from script, exported as GLB).
python3 -I western.py [name ...]  ->  assets/models/town/tx_<name>.glb

Same conventions as tools/townbuild/houses.py (origin at the centre of the footprint on the
ground, front faces -Y in Blender = +Z in Godot), but its own materials, which TownKit dresses
with the western textures: siding (clapboard, tinted per building), brick, stone (limestone),
tin (corrugated roofs), trim (painted wood), wood (doors, posts, boardwalks), glass, iron, base.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector

OUT = "/home/claude/tatame/assets/models/town"
MATS = ["siding", "brick", "stone", "tin", "trim", "wood", "glass", "iron", "base", "stucco", "tile", "thatch", "tank"]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    global M
    M = {n: bpy.data.materials.new(n) for n in MATS}


def box(size, loc, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    o.data.materials.append(M[mat])
    return o


def cyl(r, h, loc, mat, v=10, rot=(0, 0, 0), r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, vertices=v, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, location=loc, vertices=v, rotation=rot)
    o = bpy.context.object
    o.data.materials.append(M[mat])
    return o


def beam(a, b, t, mat):
    """A square beam from point a to point b (struts, braces, rafters), built straight from vertices."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    u = d.orthogonal().normalized() * (t / 2)
    v = d.cross(u).normalized() * (t / 2)
    bm = bmesh.new()
    ring = lambda p: [bm.verts.new(p + u + v), bm.verts.new(p - u + v), bm.verts.new(p - u - v), bm.verts.new(p + u - v)]
    r0, r1 = ring(a), ring(b)
    for k in range(4):
        bm.faces.new([r0[k], r0[(k + 1) % 4], r1[(k + 1) % 4], r1[k]])
    bm.faces.new(list(reversed(r0))); bm.faces.new(r1)
    me = bpy.data.meshes.new("beam"); bm.normal_update(); bm.to_mesh(me)
    o = bpy.data.objects.new("beam", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(M[mat])
    return o


def gable(W, D, z, rise, over, mat="tin", along_x=True):
    """Gable roof (ridge along X by default) with a little thickness."""
    w, d = W / 2 + over, D / 2 + over
    bm = bmesh.new()
    if along_x:
        v = [bm.verts.new(p) for p in [(-w, -d, z), (w, -d, z), (w, d, z), (-w, d, z), (-w, 0, z + rise), (w, 0, z + rise)]]
        bm.faces.new([v[0], v[1], v[5], v[4]]); bm.faces.new([v[2], v[3], v[4], v[5]])
    else:
        v = [bm.verts.new(p) for p in [(-w, -d, z), (w, -d, z), (w, d, z), (-w, d, z), (0, -d, z + rise), (0, d, z + rise)]]
        bm.faces.new([v[1], v[2], v[5], v[4]]); bm.faces.new([v[3], v[0], v[4], v[5]])
    me = bpy.data.meshes.new("roof")
    bm.normal_update(); bm.to_mesh(me)
    o = bpy.data.objects.new("roof", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(M[mat])
    so = o.modifiers.new("s", "SOLIDIFY"); so.thickness = 0.1; so.offset = -1
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="s")
    return o


def gable_ends(W, D, z, rise, mat, along_x=True):
    """Triangular wall infill under a gable."""
    for s in (-1, 1):
        bm = bmesh.new()
        if along_x:
            x = s * W / 2
            v = [bm.verts.new(p) for p in [(x, -D / 2, z), (x, D / 2, z), (x, 0, z + rise)]]
        else:
            y = s * D / 2
            v = [bm.verts.new(p) for p in [(-W / 2, y, z), (W / 2, y, z), (0, y, z + rise)]]
        bm.faces.new(v)
        me = bpy.data.meshes.new("gend"); bm.to_mesh(me)
        o = bpy.data.objects.new("gend", me)
        bpy.context.scene.collection.objects.link(o)
        o.data.materials.append(M[mat])
        so = o.modifiers.new("s", "SOLIDIFY"); so.thickness = 0.2
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="s")


def window(x, z, wall_y, w=1.0, h=1.5, inward=1, frame="trim", panes=True, cap=True):
    """Sash window set into the wall plane y=wall_y (front: inward=+1)."""
    box((w, 0.05, h), (x, wall_y + inward * 0.08, z), "glass")
    if panes:
        box((w, 0.04, 0.05), (x, wall_y + inward * 0.05, z), frame)
        box((0.04, 0.04, h), (x, wall_y + inward * 0.05, z), frame)
    t = 0.12
    box((w + 2 * t, 0.08, t), (x, wall_y - inward * 0.03, z + h / 2 + t / 2), frame)
    box((w + 2 * t, 0.08, t), (x, wall_y - inward * 0.03, z - h / 2 - t / 2), frame)
    box((t, 0.08, h), (x - w / 2 - t / 2, wall_y - inward * 0.03, z), frame)
    box((t, 0.08, h), (x + w / 2 + t / 2, wall_y - inward * 0.03, z), frame)
    box((w + 0.35, 0.2, 0.07), (x, wall_y - inward * 0.1, z - h / 2 - t - 0.02), frame)   # sill
    if cap:
        box((w + 0.45, 0.16, 0.12), (x, wall_y - inward * 0.08, z + h / 2 + t + 0.06), frame)


def side_window(x, z, y, w=0.9, h=1.4, frame="trim"):
    """Window on a side wall (wall plane x=const, facing +-X)."""
    s = 1 if x > 0 else -1
    box((0.05, w, h), (x - s * 0.08, y, z), "glass")
    t = 0.12
    box((0.08, w + 2 * t, t), (x + s * 0.03, y, z + h / 2 + t / 2), frame)
    box((0.08, w + 2 * t, t), (x + s * 0.03, y, z - h / 2 - t / 2), frame)
    box((0.08, t, h), (x + s * 0.03, y - w / 2 - t / 2, z), frame)
    box((0.08, t, h), (x + s * 0.03, y + w / 2 + t / 2, z), frame)


def door(x, wall_y, w=1.1, h=2.3, inward=1, glass_top=True, frame="trim"):
    box((w, 0.08, h), (x, wall_y + inward * 0.08, h / 2), "wood")
    if glass_top:
        box((w * 0.6, 0.05, h * 0.35), (x, wall_y + inward * 0.03, h * 0.7), "glass")
    t = 0.14
    box((w + 2 * t, 0.09, t), (x, wall_y - inward * 0.03, h + t / 2), frame)
    box((t, 0.09, h + t), (x - w / 2 - t / 2, wall_y - inward * 0.03, (h + t) / 2), frame)
    box((t, 0.09, h + t), (x + w / 2 + t / 2, wall_y - inward * 0.03, (h + t) / 2), frame)


def walls(W, D, H, mat):
    """Closed wall block (no interiors: windows are set in, not cut through)."""
    return box((W, D, H), (0, 0, H / 2), mat)


def porch(W, P, z_roof, front_y, posts=4, rail=True, boardwalk=True, roof_mat="tin"):
    """Covered front porch / boardwalk: wooden floor, posts, a shed roof sloping away from the wall."""
    y0 = front_y - P / 2
    if boardwalk:
        box((W, P, 0.25), (0, y0, 0.12), "wood")
        for k in range(int(W / 0.6)):
            box((0.03, P, 0.02), (-W / 2 + 0.3 + k * 0.6, y0, 0.255), "base")
    for k in range(posts):
        x = -W / 2 + 0.2 + k * (W - 0.4) / (posts - 1)
        box((0.18, 0.18, z_roof), (x, front_y - P + 0.15, z_roof / 2), "trim")
    box((W + 0.2, 0.2, 0.22), (0, front_y - P + 0.15, z_roof - 0.05), "trim")
    o = box((W + 0.4, P + 0.4, 0.08), (0, y0, z_roof + 0.2), roof_mat)
    o.rotation_euler = (-0.18, 0, 0)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(rotation=True)
    if rail:
        for side in (-1, 1):
            xa = side * (W / 2 - 0.2)
            box((0.06, P - 0.3, 0.06), (xa, y0 + 0.05, 1.0), "trim")
            for k in range(6):
                box((0.04, 0.04, 0.75), (xa, front_y - 0.2 - k * (P - 0.4) / 5, 0.62), "trim")


def finish(name):
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.uv.cube_project(cube_size=2.0)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.export_scene.gltf(filepath=f"{OUT}/{name}.glb", export_format='GLB', use_selection=True, export_apply=True,
                              export_materials='EXPORT', export_yup=True)
    print("saved", name, "tris", sum(len(p.vertices) - 2 for p in o.data.polygons))


# ================================================================== buildings
def store(name="tx_store", W=7.0, D=10.0, H=4.2, mat="siding", shop=True):
    """Main Street store: false front rising over a gable roof, display windows, boardwalk porch."""
    reset()
    walls(W, D, H, mat)
    fy = -D / 2
    gable(W, D, H, 1.4, 0.3, "tin", along_x=False)
    gable_ends(W, D, H, 1.4, mat, along_x=False)
    # false front: taller than the roof, stepped top, a cap moulding and a sign board
    FH = 2.4
    box((W + 0.1, 0.3, FH), (0, fy - 0.05, H + FH / 2 - 0.1), mat)
    box((W * 0.45, 0.3, 0.5), (0, fy - 0.05, H + FH + 0.12), mat)
    box((W + 0.4, 0.45, 0.16), (0, fy - 0.1, H + FH - 0.05), "trim")
    box((W * 0.45 + 0.3, 0.45, 0.14), (0, fy - 0.1, H + FH + 0.42), "trim")
    box((W * 0.75, 0.08, 1.0), (0, fy - 0.24, H + 0.95), "trim")          # sign board (game paints the name)
    for sx in (-1, 1):
        box((0.3, 0.42, H + FH), (sx * (W / 2 - 0.1), fy - 0.06, (H + FH) / 2), "trim")
    if shop:
        for sx in (-1, 1):
            window(sx * W * 0.27, 1.55, fy, w=W * 0.3, h=2.0, panes=False, cap=False)
            box((W * 0.3 + 0.2, 0.25, 0.5), (sx * W * 0.27, fy - 0.1, 0.25), "trim")    # kick panel
        door(0, fy, w=1.2, h=2.6)
        box((W * 0.85, 0.06, 0.45), (0, fy - 0.02, 3.15), "glass")                    # transom strip
    else:
        door(-W * 0.25, fy, w=1.1)
        window(W * 0.2, 1.7, fy, w=1.3, h=1.6)
    for k in (-1, 1):
        side_window(W / 2, 1.8, k * D * 0.22)
        side_window(-W / 2, 1.8, k * D * 0.22)
    porch(W, 2.4, 3.3, fy, posts=3, rail=False)
    finish(name)


def brick_block(name="tx_brick", W=8.0, D=11.0, H=7.6):
    """Two-storey brick commercial block: shopfront below, tall windows above, corbelled cornice, awning."""
    reset()
    walls(W, D, H, "brick")
    fy = -D / 2
    for x in (-W * 0.3, 0.0, W * 0.3):
        window(x, 5.4, fy, w=1.1, h=1.9, frame="stone")
        box((1.5, 0.2, 0.35), (x, fy - 0.08, 6.6), "stone")          # stone lintel
    for sx in (-1, 1):
        window(sx * W * 0.26, 1.6, fy, w=W * 0.3, h=2.1, panes=False, cap=False, frame="iron")
    door(0, fy, w=1.3, h=2.7, frame="iron")
    box((W + 0.1, 0.25, 0.5), (0, fy - 0.08, 3.25), "iron")          # storefront beam
    for k in range(9):                                                 # corbel teeth
        box((0.4, 0.3, 0.3), (-W / 2 + 0.4 + k * (W - 0.8) / 8, fy - 0.12, H - 0.5), "brick")
    box((W + 0.4, 0.6, 0.3), (0, fy - 0.15, H - 0.1), "stone")
    box((W + 0.3, D + 0.3, 0.2), (0, 0, H + 0.05), "stone")
    box((W * 0.55, 0.12, 0.7), (0, fy - 0.08, H + 0.45), "brick")    # name plate parapet
    box((W * 0.55 + 0.2, 0.25, 0.12), (0, fy - 0.1, H + 0.85), "stone")
    o = box((W - 0.4, 1.6, 0.06), (0, fy - 0.85, 3.6), "tin")        # canvas-ish awning
    o.rotation_euler = (0.35, 0, 0)
    bpy.context.view_layer.objects.active = o; bpy.ops.object.transform_apply(rotation=True)
    for k in (-1, 1):
        side_window(W / 2, 5.4, k * D * 0.25, frame="stone")
        side_window(-W / 2, 5.4, k * D * 0.25, frame="stone")
    finish(name)


def house(name="tx_house", W=10.0, D=7.5, H=3.2):
    """Ranch house: board siding, gable roof, full-width porch with rail, stone chimney."""
    reset()
    walls(W, D, H, "siding")
    fy = -D / 2
    gable(W, D, H, 1.9, 0.5, "tin")
    gable_ends(W, D, H, 1.9, "siding")
    box((W + 0.1, D + 0.1, 0.5), (0, 0, 0.25), "stone")             # pier-and-beam skirt
    door(0.6, fy, w=1.0)
    for x in (-W * 0.3, W * 0.32):
        window(x, 1.75, fy, w=1.1, h=1.4)
        for s in (-1, 1):   # shutters
            box((0.45, 0.06, 1.45), (x + s * 0.88, fy - 0.06, 1.75), "wood")
    for k in (-1, 1):
        side_window(W / 2, 1.75, k * D * 0.2)
        side_window(-W / 2, 1.75, k * D * 0.2)
    porch(W, 2.2, 2.8, fy, posts=5)
    cyl(0.0, 0.0, (0, 0, 0), "stone") if False else None
    box((1.1, 0.9, H + 2.8), (-W / 2 + 1.2, D / 2 - 1.0, (H + 2.8) / 2), "stone")   # chimney
    finish(name)


def courthouse(name="tx_courthouse", W=22.0, D=14.0, H=8.4):
    """County courthouse: limestone, two floors of tall windows, columned portico, clock tower + dome."""
    reset()
    walls(W, D, H, "stone")
    fy = -D / 2
    box((W + 0.4, D + 0.4, 0.9), (0, 0, 0.45), "stone")              # plinth
    box((W + 0.5, D + 0.5, 0.35), (0, 0, H - 0.1), "trim")           # cornice
    box((W + 0.2, D + 0.2, 0.2), (0, 0, 4.25), "trim")               # floor band
    for fl, z in ((0, 2.4), (1, 6.3)):
        for k in range(8):
            x = -W / 2 + 1.5 + k * (W - 3.0) / 7
            if abs(x) < 3.5:
                continue
            window(x, z, fy, w=1.0, h=2.0, frame="trim")
            window(x, z, -fy, w=1.0, h=2.0, frame="trim", inward=-1)
        for k in (-1, 0, 1):
            side_window(W / 2, z, k * D * 0.3, w=1.0, h=2.0)
            side_window(-W / 2, z, k * D * 0.3, w=1.0, h=2.0)
    # portico: steps, six columns, pediment
    P = 3.2
    for s in range(4):
        box((10.0 - s * 0.4, P + 1.4 - s * 0.35, 0.25), (0, fy - (P + 1.4) / 2 + s * 0.17, 0.12 + s * 0.25), "stone")
    for k in range(6):
        x = -4.0 + k * 1.6
        cyl(0.32, H - 1.4, (x, fy - P + 0.4, 1.0 + (H - 1.4) / 2), "trim", 14)
        box((0.8, 0.8, 0.3), (x, fy - P + 0.4, 1.15), "stone")
        box((0.8, 0.8, 0.25), (x, fy - P + 0.4, H - 0.3), "trim")
    box((10.4, P + 0.6, 0.6), (0, fy - P / 2 + 0.2, H + 0.1), "trim")
    bm = bmesh.new()
    v = [bm.verts.new(p) for p in [(-5.2, fy - P - 0.1, H + 0.4), (5.2, fy - P - 0.1, H + 0.4), (0, fy - P - 0.1, H + 2.2)]]
    bm.faces.new(v)
    me = bpy.data.meshes.new("ped"); bm.to_mesh(me)
    o = bpy.data.objects.new("ped", me); bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(M["stone"])
    so = o.modifiers.new("s", "SOLIDIFY"); so.thickness = P + 0.6
    bpy.context.view_layer.objects.active = o; bpy.ops.object.modifier_apply(modifier="s")
    gable(10.4, P + 0.6, H + 0.4, 1.8, 0.2, "tin", along_x=False)
    door(0, fy, w=2.0, h=3.4)
    # hipped roof (low) behind
    gable(W, D, H + 0.1, 1.6, 0.4, "tin")
    gable_ends(W, D, H + 0.1, 1.6, "stone")
    # clock tower: square base, clock faces, octagonal drum, dome, lantern, flag pole
    TZ = H + 1.6
    box((4.6, 4.6, 4.2), (0, 0, TZ + 2.1), "stone")
    box((5.0, 5.0, 0.3), (0, 0, TZ + 4.25), "trim")
    for ang in range(4):
        a = ang * math.pi / 2
        p = Vector((math.sin(a) * 2.32, -math.cos(a) * 2.32, TZ + 2.4))
        c = cyl(1.0, 0.1, p, "trim", 24, rot=(math.pi / 2, 0, a))
        c2 = cyl(0.85, 0.12, p + Vector((math.sin(a) * 0.02, -math.cos(a) * 0.02, 0)), "glass", 24, rot=(math.pi / 2, 0, a))
        beam(p + Vector((math.sin(a) * 0.1, -math.cos(a) * 0.1, 0)), p + Vector((math.sin(a) * 0.1, -math.cos(a) * 0.1, 0.6)), 0.07, "iron")
        beam(p + Vector((math.sin(a) * 0.1, -math.cos(a) * 0.1, 0)), p + Vector((math.sin(a) * 0.1 + math.cos(a) * 0.45, -math.cos(a) * 0.1 + math.sin(a) * 0.45, 0)), 0.07, "iron")
    cyl(1.9, 2.0, (0, 0, TZ + 5.4), "stone", 8)
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        box((0.5, 0.08, 1.2), (math.cos(a) * 1.92, math.sin(a) * 1.92, TZ + 5.4), "glass", rot=(0, 0, a + math.pi / 2))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=2.0, location=(0, 0, TZ + 6.3), segments=16, ring_count=8)
    d = bpy.context.object
    d.scale = (1, 1, 0.85); bpy.ops.object.transform_apply(scale=True)
    d.data.materials.append(M["tin"])
    cyl(0.45, 1.2, (0, 0, TZ + 8.5), "trim", 8)
    cyl(0.55, 0.6, (0, 0, TZ + 9.3), "tin", 8, r2=0.0)
    cyl(0.05, 2.8, (0, 0, TZ + 10.6), "iron", 6)
    finish(name)


def barn(name="tx_barn", W=12.0, D=16.0, H=4.2):
    """Red barn: gambrel roof, big sliding doors with white X braces, hay loft door."""
    reset()
    walls(W, D, H, "siding")
    fy = -D / 2
    # gambrel profile extruded along Y
    pts = [(-W / 2 - 0.4, H - 0.1), (-W * 0.33, H + 2.4), (0, H + 3.6), (W * 0.33, H + 2.4), (W / 2 + 0.4, H - 0.1)]
    bm = bmesh.new()
    front = [bm.verts.new((x, -D / 2 - 0.4, z)) for x, z in pts]
    back = [bm.verts.new((x, D / 2 + 0.4, z)) for x, z in pts]
    for i in range(len(pts) - 1):
        bm.faces.new([front[i], front[i + 1], back[i + 1], back[i]])
    me = bpy.data.meshes.new("gam"); bm.normal_update(); bm.to_mesh(me)
    o = bpy.data.objects.new("gam", me); bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(M["tin"])
    so = o.modifiers.new("s", "SOLIDIFY"); so.thickness = 0.12
    bpy.context.view_layer.objects.active = o; bpy.ops.object.modifier_apply(modifier="s")
    for y in (-D / 2, D / 2):   # gambrel end walls
        bm = bmesh.new()
        v = [bm.verts.new((x, y, z)) for x, z in [(-W / 2, H), (-W * 0.33 + 0.2, H + 2.3), (0, H + 3.45), (W * 0.33 - 0.2, H + 2.3), (W / 2, H)]]
        bm.faces.new(v)
        me = bpy.data.meshes.new("ge"); bm.to_mesh(me)
        g = bpy.data.objects.new("ge", me); bpy.context.scene.collection.objects.link(g)
        g.data.materials.append(M["siding"])
        so = g.modifiers.new("s", "SOLIDIFY"); so.thickness = 0.2
        bpy.context.view_layer.objects.active = g; bpy.ops.object.modifier_apply(modifier="s")
    # doors
    DW, DH = 5.0, 3.6
    box((DW, 0.1, DH), (0, fy - 0.05, DH / 2), "siding")
    for s in (-1, 1):
        cx = s * DW / 4
        for e in ((-DW / 4, 0.1), (DW / 4, 0.1)):
            pass
        box((DW / 2, 0.14, 0.18), (cx, fy - 0.1, 0.15), "trim")
        box((DW / 2, 0.14, 0.18), (cx, fy - 0.1, DH - 0.1), "trim")
        box((0.18, 0.14, DH), (cx - DW / 4 + 0.09, fy - 0.1, DH / 2), "trim")
        box((0.18, 0.14, DH), (cx + DW / 4 - 0.09, fy - 0.1, DH / 2), "trim")
        beam((cx - DW / 4 + 0.15, fy - 0.12, 0.2), (cx + DW / 4 - 0.15, fy - 0.12, DH - 0.2), 0.16, "trim")
        beam((cx + DW / 4 - 0.15, fy - 0.12, 0.2), (cx - DW / 4 + 0.15, fy - 0.12, DH - 0.2), 0.16, "trim")
    box((DW + 1.0, 0.2, 0.2), (0, fy - 0.15, DH + 0.2), "iron")     # door rail
    box((1.8, 0.1, 1.6), (0, fy - 0.05, H + 1.6), "wood")             # loft door
    for e in ((0, H + 0.75), (0, H + 2.45)):
        box((2.0, 0.14, 0.16), (0, fy - 0.1, e[1]), "trim")
    box((0.2, 0.2, 1.4), (0, fy - 0.9, H + 2.9), "wood")              # hay hoist beam
    for x in (-W / 2 + 0.1, W / 2 - 0.1):
        box((0.2, 0.2, H), (x, fy - 0.05, H / 2), "trim")
    finish(name)


def windmill(name="tx_windmill"):
    """Aermotor-style farm windmill: steel lattice tower, multi-blade wheel, tail vane, stock tank."""
    reset()
    T = 9.0
    base_r, top_r = 1.3, 0.35
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        beam((math.cos(a) * base_r, math.sin(a) * base_r, 0), (math.cos(a) * top_r, math.sin(a) * top_r, T), 0.09, "iron")
    for lvl in range(5):
        z0 = lvl * T / 5
        z1 = (lvl + 1) * T / 5
        r0 = base_r + (top_r - base_r) * z0 / T
        r1 = base_r + (top_r - base_r) * z1 / T
        for k in range(4):
            a, b = k * math.pi / 2 + math.pi / 4, (k + 1) * math.pi / 2 + math.pi / 4
            beam((math.cos(a) * r0, math.sin(a) * r0, z0), (math.cos(b) * r1, math.sin(b) * r1, z1), 0.04, "iron")
            beam((math.cos(a) * r1, math.sin(a) * r1, z1), (math.cos(b) * r1, math.sin(b) * r1, z1), 0.05, "iron")
    box((0.9, 0.9, 0.15), (0, 0, T), "wood")
    box((0.3, 0.9, 0.35), (0, -0.2, T + 0.35), "iron")               # gearbox
    hub = Vector((0, -0.75, T + 0.4))
    cyl(0.18, 0.3, hub, "iron", 10, rot=(math.pi / 2, 0, 0))
    for k in range(18):
        a = k * 2 * math.pi / 18
        tip = hub + Vector((math.cos(a) * 1.6, 0, math.sin(a) * 1.6))
        mid = hub + Vector((math.cos(a) * 0.95, 0, math.sin(a) * 0.95))
        box((0.16, 0.02, 1.1), mid, "tin", rot=(0, -a + math.pi / 2, 0))
    bpy.ops.mesh.primitive_torus_add(major_radius=1.6, minor_radius=0.03, location=hub, rotation=(math.pi / 2, 0, 0))
    bpy.context.object.data.materials.append(M["iron"])
    bpy.ops.mesh.primitive_torus_add(major_radius=0.7, minor_radius=0.03, location=hub, rotation=(math.pi / 2, 0, 0))
    bpy.context.object.data.materials.append(M["iron"])
    beam((0, -0.1, T + 0.4), (0, 2.2, T + 0.5), 0.06, "iron")
    box((0.04, 1.4, 0.9), (0, 2.4, T + 0.55), "tin")                 # tail vane
    cyl(0.03, T, (0, -0.2, T / 2), "iron", 5)                          # pump rod
    cyl(1.5, 0.7, (2.4, 0, 0.35), "tin", 20)                           # stock tank
    cyl(1.4, 0.06, (2.4, 0, 0.6), "glass", 20)
    finish(name)


def watertower(name="tx_watertower"):
    """Town water tower: four legs with cross bracing, a round tank (the game paints the town name), cone cap."""
    reset()
    L = 10.0
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        beam((math.cos(a) * 3.0, math.sin(a) * 3.0, 0), (math.cos(a) * 2.3, math.sin(a) * 2.3, L), 0.22, "iron")
    for lvl in (3.0, 6.5):
        r = 3.0 - 0.7 * lvl / L
        for k in range(4):
            a, b = k * math.pi / 2 + math.pi / 4, (k + 1) * math.pi / 2 + math.pi / 4
            beam((math.cos(a) * r, math.sin(a) * r, lvl), (math.cos(b) * r, math.sin(b) * r, lvl), 0.1, "iron")
            beam((math.cos(a) * r, math.sin(a) * r, lvl - 3.0 if lvl > 3 else 0.2), (math.cos(b) * r, math.sin(b) * r, lvl), 0.05, "iron")
    cyl(0.35, L, (0, 0, L / 2), "iron", 8)                            # riser pipe
    cyl(3.3, 4.0, (0, 0, L + 2.2), "trim", 28)                        # tank
    box((6.8, 6.8, 0.15), (0, 0, L + 0.15), "iron")                   # catwalk
    bpy.ops.mesh.primitive_torus_add(major_radius=3.45, minor_radius=0.04, location=(0, 0, L + 1.2))
    bpy.context.object.data.materials.append(M["iron"])
    for k in range(24):
        a = k * 2 * math.pi / 24
        cyl(0.03, 1.0, (math.cos(a) * 3.45, math.sin(a) * 3.45, L + 0.7), "iron", 4)
    cyl(3.5, 1.6, (0, 0, L + 5.0), "trim", 28, r2=0.25)
    cyl(0.2, 0.5, (0, 0, L + 6.0), "trim", 8)
    beam((2.4, -2.4, 0.2), (2.4, -2.4, L), 0.06, "iron")              # ladder rails
    beam((2.7, -2.1, 0.2), (2.7, -2.1, L), 0.06, "iron")
    finish(name)


def chapel(name="tx_chapel", W=7.0, D=12.0, H=4.6):
    """White clapboard chapel with a tall steeple: the Hill Country landmark on the hill."""
    reset()
    walls(W, D, H, "siding")
    fy = -D / 2
    gable(W, D, H, 3.2, 0.4, "tin", along_x=False)
    gable_ends(W, D, H, 3.2, "siding", along_x=False)
    box((W + 0.1, D + 0.1, 0.45), (0, 0, 0.22), "stone")
    door(0, fy - 1.6, w=1.4, h=2.8)
    # steeple: square tower in front, belfry with louvres, spire
    box((2.6, 2.6, H + 2.4), (0, fy - 1.3, (H + 2.4) / 2), "siding")
    box((2.9, 2.9, 0.2), (0, fy - 1.3, H + 2.45), "trim")
    box((2.2, 2.2, 1.8), (0, fy - 1.3, H + 3.45), "siding")
    for ang in range(4):
        a = ang * math.pi / 2
        box((1.0, 0.1, 1.2), (math.sin(a) * 1.11, fy - 1.3 - math.cos(a) * 1.11, H + 3.45), "wood", rot=(0, 0, a))
    box((2.5, 2.5, 0.16), (0, fy - 1.3, H + 4.4), "trim")
    cyl(1.45, 5.0, (0, fy - 1.3, H + 6.9), "tin", 4, r2=0.04, rot=(0, 0, math.pi / 4))
    box((0.1, 0.1, 1.2), (0, fy - 1.3, H + 9.8), "trim")
    box((0.6, 0.1, 0.1), (0, fy - 1.3, H + 9.95), "trim")
    for k in (-1, 1):
        for y in (-D * 0.25, D * 0.05, D * 0.35):
            side_window(k * W / 2, 2.3, y, w=0.9, h=2.2)
    window(0, H + 1.5, fy - 2.6, w=0.7, h=0.9)
    finish(name)


def metal_gym(name="tx_gym", W=20.0, D=14.0, H=5.0):
    """Metal building gym (the Texas garage-gym look): tin walls, roll-up doors, office front."""
    reset()
    walls(W, D, H, "tin")
    fy = -D / 2
    gable(W, D, H, 1.4, 0.4, "tin", along_x=True)
    gable_ends(W, D, H, 1.4, "tin", along_x=True)
    box((W + 0.1, D + 0.1, 0.4), (0, 0, 0.2), "stone")
    for x in (-5.5, 5.5):
        box((4.2, 0.12, 3.8), (x, fy - 0.04, 1.9), "trim")             # roll-up doors (open: dark)
        box((3.9, 0.14, 3.5), (x, fy - 0.03, 1.75), "base")
        for k in range(9):
            box((4.2, 0.16, 0.05), (x, fy - 0.08, 0.3 + k * 0.4), "trim")
    box((5.0, 1.0, 3.6), (0, fy - 0.4, 1.8), "brick")                  # office / entry
    door(0, fy - 0.9, w=1.4, h=2.5, frame="iron")
    box((5.4, 1.4, 0.15), (0, fy - 0.6, 3.65), "iron")
    box((W * 0.6, 0.1, 1.0), (0, fy - 0.06, H - 0.6), "trim")          # sign band
    for k in (-1, 0, 1):
        side_window(W / 2, 3.6, k * 3.5, w=1.6, h=0.7, frame="iron")
        side_window(-W / 2, 3.6, k * 3.5, w=1.6, h=0.7, frame="iron")
    finish(name)


ALL = {"store": store, "store_plain": lambda: store("tx_store_plain", W=6.0, D=9.0, H=3.8, shop=False),
       "brick": brick_block, "house": house, "house_small": lambda: house("tx_house_small", W=8.0, D=6.5, H=3.0),
       "courthouse": courthouse, "barn": barn, "windmill": windmill, "watertower": watertower,
       "chapel": chapel, "gym": metal_gym}

if __name__ == "__main__":
    want = [a for a in sys.argv[1:] if a in ALL] or list(ALL)
    for k in want:
        ALL[k]()
