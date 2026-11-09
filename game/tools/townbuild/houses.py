"""Brazilian colonial building kit for Tatame, modelled in Blender from script and exported as GLB.
python3 -I houses.py  ->  assets/models/town/<name>.glb

Every building is one mesh whose surfaces use named materials the game re-dresses with tiling
textures (scripts/world/town_kit.gd): wall (tinted per house), base (barrado band, darker tint),
trim (white plaster: pilasters, cornices, frames, sills), roof (terracotta tiles), wood (shutters and
doors, tinted per house), glass, iron (balcony railings). Origin: centre of the footprint at ground
level; the front faces -Y in Blender (+Z... -Z in Godot after the glTF axis swap, see town_kit.gd).
"""
import bpy, bmesh, math, os
from mathutils import Vector

OUT = "/home/claude/tatame/assets/models/town"
os.makedirs(OUT, exist_ok=True)
MATS = ["wall", "base", "trim", "roof", "wood", "glass", "iron"]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    global M
    M = {}
    for n in MATS:
        m = bpy.data.materials.new(n)
        M[n] = m


def obj_box(size, loc, mat, name="b"):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(M[mat])
    o.name = name
    return o


def obj_cyl(r, h, loc, mat, v=8, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, vertices=v, rotation=rot)
    o = bpy.context.object
    o.data.materials.append(M[mat])
    return o


def cut(target, size, loc):
    """Boolean-subtract a box (window / door opening) from the wall shell."""
    c = obj_box(size, loc, "wall", "cutter")
    mod = target.modifiers.new("cut", "BOOLEAN")
    mod.operation = 'DIFFERENCE'
    mod.object = c
    mod.solver = 'EXACT'
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(c)


def hip_roof(W, D, z, pitch, over, mat="roof", gable=False):
    """Hipped (or gabled) roof slab with overhang and a little thickness."""
    w, d = W / 2 + over, D / 2 + over
    rise = min(w, d) * math.tan(math.radians(pitch))
    bm = bmesh.new()
    if gable:
        v = [bm.verts.new(p) for p in [(-w, -d, z), (w, -d, z), (w, d, z), (-w, d, z), (-w, 0, z + rise * d / w * 1.0), (w, 0, z + rise * d / w * 1.0)]]
        rise_g = d * math.tan(math.radians(pitch))
        v[4].co.z = z + rise_g; v[5].co.z = z + rise_g
        bm.faces.new([v[0], v[1], v[5], v[4]])
        bm.faces.new([v[2], v[3], v[4], v[5]])
        bm.faces.new([v[1], v[2], v[5]])
        bm.faces.new([v[3], v[0], v[4]])
    else:
        ridge = max(0.0, w - d) if w > d else max(0.0, d - w)
        if w >= d:
            a = bm.verts.new((-ridge, 0, z + rise)); b = bm.verts.new((ridge, 0, z + rise))
            c = [bm.verts.new(p) for p in [(-w, -d, z), (w, -d, z), (w, d, z), (-w, d, z)]]
            bm.faces.new([c[0], c[1], b, a]); bm.faces.new([c[2], c[3], a, b])
            bm.faces.new([c[1], c[2], b]); bm.faces.new([c[3], c[0], a])
        else:
            a = bm.verts.new((0, -ridge, z + rise)); b = bm.verts.new((0, ridge, z + rise))
            c = [bm.verts.new(p) for p in [(-w, -d, z), (w, -d, z), (w, d, z), (-w, d, z)]]
            bm.faces.new([c[1], c[2], b, a]); bm.faces.new([c[3], c[0], a, b])
            bm.faces.new([c[0], c[1], a]); bm.faces.new([c[2], c[3], b])
    me = bpy.data.meshes.new("roof")
    bm.normal_update()
    bm.to_mesh(me)
    o = bpy.data.objects.new("roof", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(M[mat])
    so = o.modifiers.new("s", "SOLIDIFY"); so.thickness = 0.12; so.offset = -1
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="s")
    # eave fascia (white trim under the tiles)
    obj_box((2 * w, 0.06, 0.16), (0, -d, z - 0.1), "trim"); obj_box((2 * w, 0.06, 0.16), (0, d, z - 0.1), "trim")
    obj_box((0.06, 2 * d, 0.16), (-w, 0, z - 0.1), "trim"); obj_box((0.06, 2 * d, 0.16), (w, 0, z - 0.1), "trim")
    return o


def window(x, z, wall_y, w=1.0, h=1.3, depth=0.22, shutters=True, french=False, inward=1):
    """Recessed window at (x, z centre) on the wall plane y=wall_y (front: inward=+1 into the house)."""
    y_in = wall_y + inward * depth
    obj_box((w, 0.04, h), (x, y_in, z), "glass")
    # muntins
    obj_box((0.05, 0.05, h), (x, y_in - inward * 0.03, z), "trim")
    obj_box((w, 0.05, 0.05), (x, y_in - inward * 0.03, z + h * 0.15), "trim")
    # frame + sill
    t = 0.12
    obj_box((w + 2 * t, 0.06, t), (x, wall_y - inward * 0.02, z + h / 2 + t / 2), "trim")
    obj_box((t, 0.06, h + t), (x - w / 2 - t / 2, wall_y - inward * 0.02, z + t / 2), "trim")
    obj_box((t, 0.06, h + t), (x + w / 2 + t / 2, wall_y - inward * 0.02, z + t / 2), "trim")
    if not french:
        obj_box((w + 0.3, 0.22, 0.08), (x, wall_y - inward * 0.09, z - h / 2 - 0.04), "trim")
    # cornice cap over the window
    obj_box((w + 0.45, 0.14, 0.1), (x, wall_y - inward * 0.06, z + h / 2 + t + 0.05), "trim")
    if shutters:
        for s in (-1, 1):
            o = obj_box((w / 2 - 0.02, 0.05, h - 0.04), (x + s * (w / 2 + t + w / 4 + 0.02), wall_y - inward * 0.06, z), "wood")
            # board lines
            for k in (-1, 1):
                obj_box((0.03, 0.065, h - 0.1), (x + s * (w / 2 + t + w / 4 + 0.02) + k * w / 8, wall_y - inward * 0.065, z), "base")


def door(x, wall_y, w=1.15, h=2.3, double=True, inward=1, arch=False):
    y_in = wall_y + inward * 0.2
    if double:
        for s in (-1, 1):
            obj_box((w / 2 - 0.03, 0.06, h - 0.05), (x + s * w / 4, y_in, h / 2), "wood")
            for zz in (0.55, 1.45):
                obj_box((w / 2 - 0.18, 0.07, 0.6), (x + s * w / 4, y_in - inward * 0.02, zz), "base")
    else:
        obj_box((w - 0.05, 0.06, h - 0.05), (x, y_in, h / 2), "wood")
    t = 0.14
    obj_box((w + 2 * t, 0.07, t), (x, wall_y - inward * 0.025, h + t / 2), "trim")
    obj_box((t, 0.07, h + t), (x - w / 2 - t / 2, wall_y - inward * 0.025, (h + t) / 2), "trim")
    obj_box((t, 0.07, h + t), (x + w / 2 + t / 2, wall_y - inward * 0.025, (h + t) / 2), "trim")
    obj_box((w + 0.5, 0.16, 0.12), (x, wall_y - inward * 0.07, h + t + 0.08), "trim")
    obj_box((w + 0.3, 0.35, 0.12), (x, wall_y - inward * 0.18, 0.06), "trim")   # step


def railing(x, z, wall_y, w):
    """Small iron balcony: stone slab + railing."""
    obj_box((w + 0.4, 0.6, 0.12), (x, wall_y - 0.3, z), "trim")
    obj_box((w + 0.4, 0.04, 0.04), (x, wall_y - 0.58, z + 0.85), "iron")
    for k in range(int((w + 0.4) / 0.14) + 1):
        xx = x - (w + 0.4) / 2 + k * 0.14
        obj_cyl(0.012, 0.8, (xx, wall_y - 0.58, z + 0.45), "iron", 5)
    for s in (-1, 1):
        obj_box((0.04, 0.6, 0.04), (x + s * (w + 0.4) / 2, wall_y - 0.3, z + 0.85), "iron")


def shell(W, D, H, wall=0.25):
    """Hollow wall box (so openings show depth)."""
    o = obj_box((W, D, H), (0, 0, H / 2), "wall", "walls")
    inner = obj_box((W - 2 * wall, D - 2 * wall, H + 0.2), (0, 0, H / 2), "wall", "inner")
    mod = o.modifiers.new("hollow", "BOOLEAN"); mod.operation = 'DIFFERENCE'; mod.object = inner; mod.solver = 'EXACT'
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="hollow")
    bpy.data.objects.remove(inner)
    # a floor/ceiling slab inside so you can't see through a window
    obj_box((W - 0.1, D - 0.1, 0.1), (0, 0, H - 0.05), "base")
    obj_box((W - 2 * wall, 0.05, H - 0.2), (0, 0, H / 2), "base")   # dark interior divider
    return o


def dressing(W, D, H, base_h=0.6, pilasters=True):
    obj_box((W + 0.06, D + 0.06, base_h), (0, 0, base_h / 2), "base")          # barrado
    if pilasters:
        for sx in (-1, 1):
            for sy in (-1, 1):
                obj_box((0.3, 0.3, H), (sx * (W / 2 - 0.1), sy * (D / 2 - 0.1), H / 2), "trim")
    # cornice: two stacked bands
    obj_box((W + 0.16, D + 0.16, 0.16), (0, 0, H - 0.08), "trim")
    obj_box((W + 0.3, D + 0.3, 0.1), (0, 0, H + 0.05), "trim")


def finish(name):
    # join everything into one mesh (surfaces by material), smooth-free flat look, export
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
    bpy.ops.object.mode_set(mode='OBJECT')
    # box-projected UVs in metres (the game uses world triplanar anyway; this is a fallback)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.uv.cube_project(cube_size=2.0); bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.export_scene.gltf(filepath=f"{OUT}/{name}.glb", export_format='GLB', use_selection=True, export_apply=True,
                              export_materials='EXPORT', export_yup=True)
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    print("saved", name, "tris", tris)


# ---------------------------------------------------------------- the buildings
def casa(name, W=7.0, D=6.5, H=3.6, layout="dww", parapet=False, gable=False):
    """One-storey colonial house. layout: front openings left->right (d door, w window)."""
    reset()
    s = shell(W, D, H)
    n = len(layout)
    xs = [(-W / 2 + W * (i + 0.5) / n) for i in range(n)]
    fy = -D / 2
    for x, k in zip(xs, layout):
        if k == "d":
            cut(s, (1.15, 0.8, 2.3 * 2), (x, fy, 0.0))
        else:
            cut(s, (1.0, 0.8, 1.3), (x, fy, 1.75))
    # side windows
    for sx in (-1, 1):
        cut(s, (0.8, 1.0, 1.3), (sx * W / 2, 0.6, 1.75))
    dressing(W, D, H)
    for x, k in zip(xs, layout):
        if k == "d":
            door(x, fy)
        else:
            window(x, 1.75, fy)
    for sx in (-1, 1):
        # side windows face +-X: build at the front then rotate is fiddly; simple glass + trim instead
        obj_box((0.04, 0.8, 1.3), (sx * (W / 2 - 0.2), 0.6, 1.75), "glass")
        obj_box((0.08, 1.04, 0.12), (sx * (W / 2 + 0.02), 0.6, 2.46), "trim")
        obj_box((0.22, 1.1, 0.08), (sx * (W / 2 + 0.09), 0.6, 1.06), "trim")
    if parapet:
        # platibanda: the façade rises above the eaves and hides the roof, with a crest in the middle
        obj_box((W + 0.1, 0.25, 1.0), (0, fy + 0.0, H + 0.5), "wall")
        obj_box((W + 0.3, 0.4, 0.14), (0, fy, H + 1.06), "trim")
        obj_box((W + 0.2, 0.3, 0.16), (0, fy, H + 0.08), "trim")
        obj_box((1.4, 0.3, 0.5), (0, fy, H + 1.35), "trim")
        for sx in (-1, 1):
            obj_box((0.32, 0.32, 1.25), (sx * (W / 2 - 0.1), fy, H + 0.62), "trim")
        hip_roof(W - 0.2, D - 0.6, H + 0.1, 18, 0.25, gable=gable)
    else:
        hip_roof(W, D, H + 0.1, 24, 0.55, gable=gable)
    finish(name)


def varanda(name, W=8.0, D=7.0, H=3.4):
    """House with a front porch (varanda): columns, low wall, roof extends over it."""
    reset()
    P = 2.0  # porch depth
    s = shell(W, D - P, H)
    s.location.y = P / 2
    bpy.ops.object.select_all(action='DESELECT'); s.select_set(True); bpy.context.view_layer.objects.active = s
    bpy.ops.object.transform_apply(location=True)
    fy = -(D - P) / 2 + P / 2
    cut(s, (1.15, 0.8, 4.6), (0, fy, 0.0))
    for x in (-2.4, 2.4):
        cut(s, (1.1, 0.8, 1.3), (x, fy, 1.75))
    obj_box((W + 0.06, D - P + 0.06, 0.6), (0, P / 2, 0.3), "base")
    for sx in (-1, 1):
        for sy in (fy, (D - P) / 2 + P / 2):
            obj_box((0.3, 0.3, H), (sx * (W / 2 - 0.1), sy, H / 2), "trim")
    door(0, fy)
    for x in (-2.4, 2.4):
        window(x, 1.75, fy, w=1.1)
    # porch floor, columns and parapet wall
    obj_box((W, P, 0.3), (0, -D / 2 + P / 2, 0.15), "base")
    for x in (-W / 2 + 0.25, -W / 6, W / 6, W / 2 - 0.25):
        obj_cyl(0.13, H - 0.3, (x, -D / 2 + 0.25, 0.3 + (H - 0.3) / 2), "trim", 10)
        obj_box((0.36, 0.36, 0.2), (x, -D / 2 + 0.25, 0.4), "trim")
    for x0, x1 in ((-W / 2 + 0.25, -0.8), (0.8, W / 2 - 0.25)):
        obj_box((x1 - x0, 0.22, 0.75), ((x0 + x1) / 2, -D / 2 + 0.25, 0.3 + 0.37), "wall")
        obj_box((x1 - x0 + 0.1, 0.3, 0.08), ((x0 + x1) / 2, -D / 2 + 0.25, 0.3 + 0.78), "trim")
    obj_box((W + 0.3, D + 0.3, 0.12), (0, 0, H + 0.04), "trim")
    hip_roof(W, D, H + 0.1, 22, 0.5)
    finish(name)


def sobrado(name, W=7.5, D=7.0, H=6.6, shop=False):
    """Two-storey town house: ground floor door + windows (or a shop with three wide doors),
    first floor French windows with iron balconies."""
    reset()
    s = shell(W, D, H)
    fy = -D / 2
    xs = (-W / 3, 0, W / 3)
    for x in xs:
        if shop:
            cut(s, (1.5, 0.8, 5.4), (x, fy, 0.0))
        elif x == 0:
            cut(s, (1.15, 0.8, 4.6), (x, fy, 0.0))
        else:
            cut(s, (1.0, 0.8, 1.3), (x, fy, 1.75))
        cut(s, (1.0, 0.8, 2.2), (x, fy, 4.6))   # French windows upstairs
    dressing(W, D, H)
    obj_box((W + 0.12, D + 0.12, 0.18), (0, 0, 3.35), "trim")   # floor band between storeys
    for x in xs:
        if shop:
            door(x, fy, w=1.5, h=2.7)
        elif x == 0:
            door(x, fy)
        else:
            window(x, 1.75, fy)
        window(x, 4.6, fy, w=1.0, h=2.2, french=True)
        railing(x, 3.55, fy, 1.0)
    hip_roof(W, D, H + 0.1, 22, 0.55)
    finish(name)


if __name__ == "__main__" and not os.environ.get("ONLY"):
    casa("casa_a", 7.0, 6.5, 3.6, "wdw")
    casa("casa_b", 7.5, 6.5, 3.8, "wdww", parapet=True)
    casa("casa_c", 6.0, 6.0, 3.5, "dw", gable=True)
    casa("casa_d", 8.0, 6.5, 3.7, "wwdw", parapet=True)
    varanda("casa_varanda", 8.0, 7.5, 3.4)
    sobrado("sobrado_a", 7.5, 7.0, 6.6)
    sobrado("sobrado_loja", 8.0, 7.0, 6.6, shop=True)


def igreja(name="igreja"):
    """Twin-tower colonial church (igreja matriz). Footprint ~11 x 17; façade faces -Y (Godot +Z)."""
    reset()
    W, D, H = 10.0, 15.0, 9.0
    s = shell(W, D, H, wall=0.4)
    s.location.y = 0.8
    bpy.ops.object.select_all(action='DESELECT'); s.select_set(True); bpy.context.view_layer.objects.active = s
    bpy.ops.object.transform_apply(location=True)
    fy = -D / 2 + 0.8
    # arched main door + two windows over it + a round rose window in the pediment
    cut(s, (2.2, 1.2, 7.6), (0, fy, 0.0))
    for x in (-2.6, 2.6):
        cut(s, (1.0, 1.2, 2.4), (x, fy, 5.4))
    for sx in (-1, 1):
        for y in (-3.0, 1.0, 5.0):
            cut(s, (1.2, 1.0, 2.6), (sx * W / 2, y + 0.8, 5.4))
    obj_box((W + 0.1, D + 0.1, 0.8), (0, 0.8, 0.4), "base")
    for sx in (-1, 1):
        for y in (fy, D / 2 + 0.8):
            obj_box((0.45, 0.45, H), (sx * (W / 2 - 0.1), y, H / 2), "trim")
    obj_box((W + 0.2, D + 0.2, 0.25), (0, 0.8, H - 0.12), "trim")
    # door: arch frame + wooden doors
    obj_box((2.1, 0.08, 3.6), (0, fy + 0.3, 1.8), "wood")
    obj_cyl(1.05, 0.08, (0, fy + 0.3, 3.6), "wood", 16, rot=(math.pi / 2, 0, 0))
    obj_box((0.3, 0.2, 3.7), (-1.25, fy - 0.05, 1.85), "trim"); obj_box((0.3, 0.2, 3.7), (1.25, fy - 0.05, 1.85), "trim")
    bpy.ops.mesh.primitive_torus_add(major_radius=1.2, minor_radius=0.15, location=(0, fy - 0.05, 3.7), rotation=(math.pi / 2, 0, 0), major_segments=20, minor_segments=6)
    t = bpy.context.object; t.data.materials.append(M["trim"])
    for x in (-2.6, 2.6):
        window(x, 5.4, fy, w=1.0, h=2.4, shutters=False)
    # pediment (triangular gable) with rose window, cornice, cross
    bm = bmesh.new()
    v = [bm.verts.new(p) for p in [(-W / 2, 0, 0), (W / 2, 0, 0), (0, 0, 3.0)]]
    bm.faces.new(v)
    me = bpy.data.meshes.new("ped"); bm.to_mesh(me)
    o = bpy.data.objects.new("ped", me); bpy.context.scene.collection.objects.link(o)
    o.location = (0, fy - 0.0, H); o.data.materials.append(M["wall"])
    so = o.modifiers.new("s", "SOLIDIFY"); so.thickness = 0.4
    bpy.context.view_layer.objects.active = o; bpy.ops.object.modifier_apply(modifier="s")
    for sgn in (-1, 1):
        obj_box((5.6, 0.5, 0.22), (sgn * 2.5, fy - 0.1, H + 1.5), "trim").rotation_euler = (0, -sgn * math.atan2(3.0, W / 2), 0)
    obj_cyl(0.75, 0.2, (0, fy - 0.15, H + 1.2), "trim", 20, rot=(math.pi / 2, 0, 0))
    obj_cyl(0.58, 0.24, (0, fy - 0.15, H + 1.2), "glass", 20, rot=(math.pi / 2, 0, 0))
    obj_box((0.22, 0.22, 1.6), (0, fy, H + 3.6), "iron"); obj_box((0.9, 0.22, 0.22), (0, fy, H + 3.9), "iron")
    # nave roof
    hip_roof(W, D, H + 0.15, 28, 0.4, gable=True)
    for o in bpy.context.scene.objects:
        if o.name.startswith("roof"):
            o.location.y += 0.8
    # two bell towers
    for sx in (-1, 1):
        x = sx * (W / 2 + 1.3)
        TW = 3.2
        obj_box((TW, TW, 15.0), (x, fy + 1.0, 7.5), "wall")
        obj_box((TW + 0.1, TW + 0.1, 0.8), (x, fy + 1.0, 0.4), "base")
        for k in (6.0, 11.0):
            obj_box((TW + 0.3, TW + 0.3, 0.25), (x, fy + 1.0, k), "trim")
        for dx in (-1, 1):
            for dy in (-1, 1):
                obj_box((0.35, 0.35, 15.0), (x + dx * (TW / 2 - 0.1), fy + 1.0 + dy * (TW / 2 - 0.1), 7.5), "trim")
        # belfry openings (dark recesses on all four sides) + a bell
        for ax, ay, sxw, syw in ((0, -1, 1.2, 0.1), (0, 1, 1.2, 0.1), (-1, 0, 0.1, 1.2), (1, 0, 0.1, 1.2)):
            obj_box((sxw, syw, 2.2), (x + ax * (TW / 2 + 0.01), fy + 1.0 + ay * (TW / 2 + 0.01), 12.7), "glass")
        window(x, 8.5, fy + 1.0 - TW / 2, w=0.8, h=1.6, shutters=False)
        obj_box((TW + 0.5, TW + 0.5, 0.35), (x, fy + 1.0, 15.1), "trim")
        bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=TW * 0.72, radius2=0, depth=4.2, location=(x, fy + 1.0, 17.4), rotation=(0, 0, math.pi / 4))
        sp = bpy.context.object; sp.data.materials.append(M["roof"])
        obj_cyl(0.1, 1.0, (x, fy + 1.0, 20.0), "iron", 6)
    finish(name)


if __name__ == "__main__" and os.environ.get("ONLY", "igreja") == "igreja":
    igreja()
