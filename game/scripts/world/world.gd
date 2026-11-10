class_name World
extends Node3D
## Zone 1: Cáceres, Mato Grosso. Terrain, river, town, academia, fighters, collectibles.

signal nearby_changed(npc: Npc)
signal landmark_entered(id: String)
signal spot_changed(spot: Dictionary)
signal mob_engaged(npc: Npc)

const HALF := 100
const WATER_Y := -1.25

var noise := FastNoiseLite.new()
var player: Player
var fighters := {}  # id -> Npc
var nearby: Npc
var beacon: MeshInstance3D
var _cups := {}  # index -> Node3D
var _nest_found_area: Area3D
var _static: StaticBody3D
var _rng := RandomNumberGenerator.new()
var game_started := false
var zone := "caceres"
var spots: Array = []       # interactable spots: {pos, radius, label, action, arg}
var chests: Chests          # hidden chests (scripts/world/chests.gd)
var nearby_spot: Dictionary = {}
var _jaguar_area: Area3D
var _blocked: Array = []  # Rect2 areas with no trees/houses
var mobs: Array = []      # [{npc: Npc or null, camp: Dictionary, rare: bool, t: respawn seconds left}]
var aggro_grace := 0.0    # seconds during which mobs won't pull you (after a fight, on arrival)

const VENDOR_SPOTS := {"pantanal": [Vector3(-76, 0, 2), "Shop: Bar do Pantaneiro", "Seu Bené"],
	"chapada": [Vector3(38, 0, 44), "Shop: Lanchonete da Trilha", "Dona Lia"],
	"rio": [Vector3(6, 0, 40), "Shop: Quiosque da Orla", "Tio Beto"],
	"socal": [Vector3(-16, 0, 30), "Shop: Surf & Smoothie", "Becky"],
	"texas": [Vector3(36, 0, -14), "Shop: Feed & Tack", "Miss Dolly"],
	"everglades": [Vector3(-78, 0, 6), "Shop: Bait & Tackle", "Earline"],
	"sedona": [Vector3(38, 0, 46), "Shop: Trading Post", "Two Feathers"]}

## Faction quartermasters (Honor gear): two per side, in the starting town and the big city.
const QUARTERMASTERS := {"caceres": [Vector3(-20, 0, 12), "brasil", "Sargento Moura"], "rio": [Vector3(24, 0, -12), "brasil", "Capitã Ivone"],
	"texas": [Vector3(15, 0, 3), "usa", "Sergeant Briggs"], "socal": [Vector3(-70, 0, 2), "usa", "Major Okafor"]}

func _quartermaster(p: Vector3, fid: String, who: String) -> void:
	var b := Vector3(p.x, ground_y(p.x, p.z), p.z)
	var fd := Origins.faction(fid)
	_cyl(0.07, 0.07, 4.6, b + Vector3(-1.2, 2.3, 0), Color(0.75, 0.75, 0.78), 6)
	_box(Vector3(1.6, 1.0, 0.05), b + Vector3(-0.4, 4.0, 0), fd.color, false)
	_box(Vector3(1.6, 0.25, 0.06), b + Vector3(-0.4, 3.65, 0), fd.accent, false)
	_box(Vector3(2.2, 1.0, 0.9), b + Vector3(0.6, 0.5, 0), Color(0.35, 0.25, 0.16))
	_box(Vector3(2.3, 0.08, 1.0), b + Vector3(0.6, 1.04, 0), (fd.color as Color).darkened(0.3), false)
	_label(Tx.f("%s QUARTERMASTER", Tx.s(str(fd.name)).to_upper()), b + Vector3(0, 5.0, 0), 50, (fd.color as Color).lightened(0.35)).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_spot(b + Vector3(0, 0, 1.4), 3.0, Tx.f("Quartermaster: %s (Honor gear)", who), "quartermaster", fid + "|" + who)

func build(z := "caceres") -> void:
	_build_zone(z)
	if QUARTERMASTERS.has(zone):
		var qm: Array = QUARTERMASTERS[zone]
		_quartermaster(qm[0], qm[1], qm[2])
	if zone != "caceres":
		_build_mobs()
		if VENDOR_SPOTS.has(zone):
			var v: Array = VENDOR_SPOTS[zone]
			_spot(v[0], 4.0, v[1], "vendor", v[2])
			var vp: Vector3 = v[0]
			_label(str(v[1]).trim_prefix("Shop: ").to_upper(), Vector3(vp.x, ground_y(vp.x, vp.z) + 2.8, vp.z), 56, Color(1, 0.95, 0.75))
	_build_territories()
	_build_zone_roads()
	chests = Chests.new()
	add_child(chests)
	chests.build(self)
	_dress_props()
	_batch_static()
	apply_graphics()

## Merges static, opaque primitive meshes (houses, walls, posts, mats...) into one mesh per
## material per 40 m cell. Hundreds of draw calls become a few dozen; cells keep culling working.
var day_night: DayNight
var wildlife: Wildlife
var map_footprints: Array = []   # [Rect2 (x, z), Color] buildings and walls for the minimap

var _kit_footprints: Array = []   # kit buildings (TownKit) for the minimap
func _batch_static() -> void:
	map_footprints = _kit_footprints.duplicate()
	for c in get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh and c.visible:
			var mi := c as MeshInstance3D
			var bb: AABB = mi.transform * mi.mesh.get_aabb()
			if bb.size.y >= 1.4 and bb.size.x * bb.size.z >= 1.5 and bb.size.x * bb.size.z < 2500.0:
				var col: Color = (mi.material_override as StandardMaterial3D).albedo_color if mi.material_override is StandardMaterial3D else Color(0.6, 0.6, 0.6)
				map_footprints.append([Rect2(bb.position.x, bb.position.z, bb.size.x, bb.size.z), col])
	var groups := {}
	for c in get_children():
		if not (c is MeshInstance3D) or c.get_child_count() > 0 or c.get_script() != null or not c.visible:
			continue
		var mi := c as MeshInstance3D
		if mi.mesh == null or not (mi.mesh is PrimitiveMesh):
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var cell := Vector2i(floori(mi.position.x / 40.0), floori(mi.position.z / 40.0))
		var key := "%d|%s|%s" % [mat.get_instance_id(), mi.mesh.get_class(), cell]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(mi)
	var merged := 0
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		var st := SurfaceTool.new()
		for mi in list:
			st.append_from((mi as MeshInstance3D).mesh, 0, (mi as MeshInstance3D).transform)
		var out := MeshInstance3D.new()
		out.mesh = st.commit()
		out.material_override = (list[0] as MeshInstance3D).material_override
		out.name = "Batched"
		add_child(out)
		for mi in list:
			remove_child(mi)
			mi.queue_free()
		merged += list.size()
	if OS.is_debug_build() and merged > 0:
		print_verbose(Tx.f("batched %d static meshes", merged))

## Graphics tiers. Low (phones): no sun shadows, short grass distance, 75% 3D resolution.
## High: 2-cascade shadows to 55 m. Ultra (desktop): 4x MSAA, glow, 90 m shadows, far grass.
func apply_graphics() -> void:
	var lvl := Game.graphics_level()
	for c in get_children():
		if c is DirectionalLight3D:
			var sun := c as DirectionalLight3D
			sun.shadow_enabled = lvl > 0
			sun.directional_shadow_max_distance = 90.0 if lvl == 2 else 55.0
		elif c is MultiMeshInstance3D and (c as MultiMeshInstance3D).visibility_range_end > 0.0:
			(c as MultiMeshInstance3D).visibility_range_end = [35.0, 70.0, 110.0][lvl]
		elif c is WorldEnvironment:
			var e := (c as WorldEnvironment).environment
			e.glow_enabled = lvl == 2
			e.glow_intensity = 0.55
			e.glow_bloom = 0.06
			e.glow_hdr_threshold = 0.9
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = 0.75 if lvl == 0 else 1.0
		vp.msaa_3d = Viewport.MSAA_4X if lvl == 2 else (Viewport.MSAA_2X if lvl == 1 else Viewport.MSAA_DISABLED)
	RenderingServer.directional_shadow_atlas_set_size(4096 if lvl == 2 else 2048, true)

func _build_zone(z: String) -> void:
	zone = z
	if zone == "pantanal":
		_build_pantanal()
		return
	if zone == "chapada":
		_build_chapada()
		return
	if zone == "rio":
		_build_rio()
		return
	if zone == "socal":
		_build_socal()
		return
	if zone == "texas":
		_build_texas()
		return
	if zone == "everglades":
		_build_everglades()
		return
	if zone == "sedona":
		_build_sedona()
		return
	noise.seed = 7
	noise.frequency = 0.03
	_rng.seed = 2026
	_static = StaticBody3D.new()
	add_child(_static)
	_blocked = [
		Rect2(-16, -2, 32, 22),     # plaza
		Rect2(-9, -34, 18, 24),     # cathedral
		Rect2(-12, -66, 24, 24),    # academia
		Rect2(18, -34, 26, 22),     # market
		Rect2(66, -12, 30, 24),     # gate
		Rect2(-44, 44, 16, 16),     # nest tree
		Rect2(-64, 22, 16, 16),     # pier
		# Vila Nova (south-east neighbourhood) + outskirts camps
		Rect2(8, 30, 80, 20),       # Rua Vila Nova (E-W) and its houses
		Rect2(16, 16, 8, 16),       # connector from the plaza
		Rect2(42, 48, 8, 40),       # Rua do Campo (N-S)
		Rect2(19, 52, 18, 16),      # Praça Vila Nova
		Rect2(50, 56, 26, 20),      # Quadra da Vila (camp)
		Rect2(-54, 60, 30, 20),     # Prainha (camp)
		Rect2(46, -74, 26, 24),     # Galpão (camp)
	]
	_build_environment()
	_build_terrain()
	_build_water()
	_build_roads_and_plaza()
	_build_cathedral()
	_build_academia()
	_build_market()
	_build_houses()
	_build_trees()
	_build_ground_detail()
	_build_props()
	_build_caceres_life()
	_build_vila_nova()
	_build_gate()
	_build_pier()
	_build_nest_tree()
	_build_capybaras()
	_build_caceres_spots()
	_build_cups()
	_build_landmarks()
	_build_fighters()
	_build_villagers()
	_build_mobs()
	_build_bounds()
	_build_beacon()

# ================================================================ height field
static func _ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func river_x(z: float) -> float:
	return -72.0 + sin(z * 0.035) * 6.0

## Surface height of this zone's water (rivers, wetland, sea).
func water_level() -> float:
	return -0.35 if zone in ["pantanal", "everglades"] else (-1.0 if zone == "sedona" else (-2.0 if zone == "texas" else WATER_Y))

## Walkable roads off the map edge to the neighbouring zones on your faction's road (WoW zone
## lines): side -> the z of the road. Filled from tests/probe_roads.gd (clear of buildings, water).
const ZONE_ROADS := {
	"caceres": {"e": 20.0}, "pantanal": {"w": -40.0, "e": -16.0}, "chapada": {"w": 4.0, "e": 8.0}, "rio": {"w": -24.0},
	"texas": {"e": -24.0}, "everglades": {"w": 42.0, "e": -22.0}, "sedona": {"w": 18.0, "e": -28.0}, "socal": {"w": -16.0},
}

## The zone a road leads to: "w" goes back along the faction's path, "e" onwards.
static func road_target(z: String, side: String) -> String:
	for fid in Origins.FACTIONS:
		var path: Array = Origins.FACTIONS[fid].path
		var i := path.find(z)
		if i >= 0:
			var j := i - 1 if side == "w" else i + 1
			return str(path[j]) if j >= 0 and j < path.size() else ""
	return ""

## Player walked into a zone line? Returns [target zone, side] or [].
func zone_line_at(p: Vector3) -> Array:
	if not ZONE_ROADS.has(zone):
		return []
	for side in ZONE_ROADS[zone]:
		var s := -1.0 if side == "w" else 1.0
		if s * p.x > 91.0 and absf(p.z - float(ZONE_ROADS[zone][side])) < 8.0:
			return [road_target(zone, side), side]
	return []

## Road, posts and a signpost for each zone line ("Pantanal Norte · Lv 11-20 →").
func _build_zone_roads() -> void:
	if not ZONE_ROADS.has(zone):
		return
	for side in ZONE_ROADS[zone]:
		var s := -1.0 if side == "w" else 1.0
		var zc: float = ZONE_ROADS[zone][side]
		var to := road_target(zone, side)
		if to == "":
			continue
		var x := 58.0
		while x < 97.0:
			var px := s * (x + 3.0)
			_box(Vector3(6.2, 0.14, 5.0), Vector3(px, ground_y(px, zc) + 0.05, zc), Color(0.52, 0.46, 0.38), false)
			x += 6.0
		var sp := Vector3(s * 66.0, 0, zc - 4.4)
		var gy := ground_y(sp.x, sp.z)
		_box(Vector3(0.26, 4.4, 0.26), Vector3(sp.x, gy + 2.2, sp.z), Color(0.4, 0.3, 0.2))
		_box(Vector3(4.6, 1.5, 0.14), Vector3(sp.x + s * 1.9, gy + 3.5, sp.z), Color(0.86, 0.78, 0.6), false)
		_box(Vector3(4.8, 0.12, 0.18), Vector3(sp.x + s * 1.9, gy + 4.3, sp.z), Color(0.4, 0.3, 0.2), false)
		var zd: Dictionary = Data.ZONES[to]
		var txt := "%s  %s\n%s" % [Tx.s(str(zd.name)).to_upper(), "→" if s > 0 else "←", Data.zone_levels(to)]
		for face in [1.0, -1.0]:
			var l := _label(txt, Vector3(sp.x + s * 1.9, gy + 3.5, sp.z + face * 0.09), 64, Color(0.2, 0.14, 0.08))
			l.rotation.y = 0.0 if face > 0 else PI
			l.outline_size = 0
		# and a floating name over the road, readable from across the zone
		var far := _label(Tx.s(str(zd.name)).to_upper(), Vector3(s * 88.0, ground_y(s * 88.0, zc) + 5.5, zc), 120, Color(1, 0.9, 0.6))
		far.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		far.outline_size = 14
		# a faint glow where the road leaves the map, so the way out reads from afar
		var glow := _label("· · ·", Vector3(s * 94.0, ground_y(s * 94.0, zc) + 1.6, zc), 90, Color(1, 0.9, 0.6, 0.6))
		glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED


## Terrain height, with the zone-line roads carved through the edge hills (see ZONE_ROADS).
func height(x: float, z: float) -> float:
	var h := _raw_height(x, z)
	if not ZONE_ROADS.has(zone):
		return h
	for side in ZONE_ROADS[zone]:
		var s := -1.0 if side == "w" else 1.0
		var zc: float = ZONE_ROADS[zone][side]
		var t := _ss(58.0, 68.0, s * x) * _ss(9.0, 5.0, absf(z - zc))
		if t > 0.0:
			h = lerpf(h, _raw_height(s * 58.0, zc), t)
	return h

func _raw_height(x: float, z: float) -> float:
	if zone == "pantanal":
		return _height_pantanal(x, z)
	if zone == "chapada":
		return _height_chapada(x, z)
	if zone == "rio":
		return _height_rio(x, z)
	if zone == "socal":
		return _height_socal(x, z)
	if zone == "texas":
		return _height_texas(x, z)
	if zone == "everglades":
		return _height_everglades(x, z)
	if zone == "sedona":
		return _height_sedona(x, z)
	var h := noise.get_noise_2d(x, z) * 1.4
	var town := 1.0 - _ss(38.0, 62.0, maxf(absf(x) * 0.9, absf(z + 15.0) * 0.8))
	h *= 1.0 - town * 0.88
	var e := maxf(absf(x), absf(z))
	var gap := _ss(9.0, 4.0, absf(z)) * _ss(55.0, 70.0, x)
	h += _ss(80.0, 98.0, e) * 14.0 * (1.0 - gap)
	var d := absf(x - river_x(z))
	h = lerpf(h, -2.8, _ss(13.0, 5.0, d))
	return h

func ground_y(x: float, z: float) -> float:
	return height(x, z)

func _ground_color(x: float, z: float, h: float) -> Color:
	if zone == "rio":
		return _rio_color(x, z, h)
	if zone == "socal":
		return _socal_color(x, z, h)
	if zone == "texas":
		return _texas_color(x, z, h)
	if zone == "everglades":
		return _everglades_color(x, z, h)
	if zone == "sedona":
		return _sedona_color(x, z, h)
	var n := noise.get_noise_2d(x * 3.0 + 100.0, z * 3.0) * 0.5 + 0.5
	if zone == "chapada":
		var cg := Color(0.34, 0.38, 0.16).lerp(Color(0.44, 0.43, 0.2), n)
		var slope := absf(height(x, z + 1.5) - height(x, z - 1.5)) + absf(height(x + 1.5, z) - height(x - 1.5, z))
		if slope > 1.6:
			cg = Color(0.62, 0.28, 0.16).lerp(Color(0.72, 0.38, 0.2), n)
		elif h > 5.0:
			cg = cg.lerp(Color(0.62, 0.42, 0.26), 0.35)
		if h < -0.4:
			cg = Color(0.45, 0.38, 0.28)
		return cg
	if zone == "pantanal":
		var g := Color(0.3, 0.45, 0.16).lerp(Color(0.42, 0.5, 0.2), n)
		if h < -0.2:
			g = g.lerp(Color(0.33, 0.27, 0.17), _ss(-0.2, -0.6, h))
		if h > 2.5:
			g = g.lerp(Color(0.38, 0.4, 0.22), _ss(2.5, 8.0, h))
		if absf(z + 4.0) < 3.2:
			g = g.lerp(Color(0.6, 0.47, 0.32), 0.8)
		return g
	var grass := Color(0.24, 0.42, 0.16).lerp(Color(0.34, 0.5, 0.2), n)
	var d := absf(x - river_x(z))
	if d < 17.0:
		grass = grass.lerp(Color(0.86, 0.77, 0.55), _ss(17.0, 12.0, d))
	if h > 3.0:
		grass = grass.lerp(Color(0.5, 0.46, 0.33), _ss(3.0, 9.0, h))
	# dirt roads
	var road := 0.0
	if absf(z + 4.0) < 3.0 and x > -58.0 and x < 82.0:
		road = 1.0
	if absf(x - 9.0) < 2.6 and z > -52.0 and z < -2.0:
		road = 1.0
	if road > 0.0:
		grass = grass.lerp(Color(0.62, 0.45, 0.3), 0.85)
	return grass

# ================================================================ builders
static var _wmat_cache := {}

## World props: soft lambert shading (cel shading is reserved for characters).
func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var key := c.to_html() + str(rough)
	if _wmat_cache.has(key):
		return _wmat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	_wmat_cache[key] = m
	return m

func _box(size: Vector3, pos: Vector3, color: Color, collide := true, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = pos
		cs.rotation.y = rot_y
		_static.add_child(cs)
	return mi

func _cyl(r_top: float, r_bot: float, h: float, pos: Vector3, color: Color, segs := 10, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _mat(color)
	mi.position = pos
	add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = maxf(r_top, r_bot)
		sh.height = h
		cs.shape = sh
		cs.position = pos
		_static.add_child(cs)
	return mi

func _label(text: String, pos: Vector3, size := 96, color := Color.WHITE, rot_y := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 16
	l.modulate = color
	l.position = pos
	l.rotation.y = rot_y
	add_child(l)
	return l

func _is_blocked(x: float, z: float, pad := 0.0) -> bool:
	if ZONE_ROADS.has(zone) and absf(x) > 56.0 - pad:
		for side in ZONE_ROADS[zone]:
			if (x < 0.0) == (side == "w") and absf(z - float(ZONE_ROADS[zone][side])) < 6.0 + pad:
				return true
	for r in _blocked:
		if r.grow(pad).has_point(Vector2(x, z)):
			return true
	if absf(z + 4.0) < 5.0 and x > -60 and x < 84:
		return true
	if absf(x - 9.0) < 4.5 and z > -54 and z < 0:
		return true
	return false

## Sky, haze and sunlight per Team USA zone, so each one reads differently at a glance.
const ZONE_LOOK := {
	"texas": {"top": Color(0.22, 0.46, 0.8), "horizon": Color(0.9, 0.84, 0.7), "fog": Color(0.92, 0.84, 0.68), "density": 0.0024,
		"ambient": Color(0.72, 0.68, 0.62), "sat": 0.98, "sun": Color(1.0, 0.86, 0.66), "sun_rot": Vector3(-38, -60, 0)},
	"everglades": {"top": Color(0.3, 0.5, 0.7), "horizon": Color(0.78, 0.84, 0.8), "fog": Color(0.74, 0.8, 0.74), "density": 0.0042,
		"ambient": Color(0.6, 0.68, 0.64), "sat": 1.0, "sun": Color(1.0, 0.95, 0.85), "sun_rot": Vector3(-55, -20, 0)},
	"sedona": {"top": Color(0.12, 0.34, 0.78), "horizon": Color(0.9, 0.8, 0.7), "fog": Color(0.9, 0.78, 0.66), "density": 0.0014,
		"ambient": Color(0.72, 0.64, 0.6), "sat": 0.98, "sun": Color(1.0, 0.82, 0.62), "sun_rot": Vector3(-32, -75, 0)},
	"socal": {"top": Color(0.2, 0.5, 0.9), "horizon": Color(0.82, 0.9, 0.96), "fog": Color(0.85, 0.9, 0.95), "density": 0.0018,
		"ambient": Color(0.66, 0.72, 0.8), "sat": 1.1, "sun": Color(1.0, 0.95, 0.85), "sun_rot": Vector3(-52, -30, 0)},
}

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.16, 0.4, 0.82)
	psm.sky_horizon_color = Color(0.7, 0.84, 0.95) if zone != "chapada" else Color(0.86, 0.8, 0.72)
	psm.sky_curve = 0.12
	psm.ground_horizon_color = Color(0.55, 0.62, 0.5)
	psm.ground_bottom_color = Color(0.22, 0.28, 0.16)
	psm.sun_angle_max = 20.0
	sky.sky_material = psm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.78)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.88 if zone != "rio" else 0.78
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.08 if zone != "rio" else 1.22
	e.adjustment_contrast = 1.08
	e.fog_enabled = true
	e.fog_light_color = Color(0.72, 0.82, 0.92)
	e.fog_density = 0.0014
	var look: Dictionary = ZONE_LOOK.get(zone, {})
	if not look.is_empty():
		# every zone its own light and air (WoW: Elwynn's green morning vs Durotar's red dust)
		psm.sky_top_color = look.top
		psm.sky_horizon_color = look.horizon
		psm.ground_horizon_color = look.horizon.darkened(0.25)
		e.fog_light_color = look.fog
		e.fog_density = look.density
		e.ambient_light_color = look.ambient
		e.adjustment_saturation = look.sat
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0) if look.is_empty() else look.sun_rot
	sun.light_color = Color(1.0, 0.92, 0.78) if look.is_empty() else look.sun
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.7
	sun.directional_shadow_max_distance = 55.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
	day_night = DayNight.new()
	add_child(day_night)
	day_night.setup(e, psm, sun, e.tonemap_exposure)
	_build_clouds()
	_build_lamps()

## Street lamps: the heads share one emissive material that the day/night cycle brightens.
func _build_lamps() -> void:
	var pts: Array = []
	match zone:
		"caceres":
			for x in range(-50, 72, 16):
				pts.append(Vector3(x, 0, -7.6))
			for z in range(-48, -6, 12):
				pts.append(Vector3(12.4, 0, z))
			for c in [Vector3(-15, 0, -1), Vector3(15, 0, -1), Vector3(-15, 0, 17), Vector3(15, 0, 17)]:
				pts.append(c)
		"pantanal":
			for c in [Vector3(-78, 0, -8), Vector3(-86, 0, 2), Vector3(54, 0, 44), Vector3(66, 0, 44), Vector3(-36, 0, 20)]:
				pts.append(c)
		"chapada":
			for i in 6:
				var a := i * TAU / 6.0
				pts.append(Vector3(42 + cos(a) * 11.0, 0, 42 + sin(a) * 11.0))
			pts.append(Vector3(-76, 0, 36))
		"rio":
			for x in range(-88, 90, 20):
				pts.append(Vector3(x, 0, 25.0))
			for c in [Vector3(32, 0, -36), Vector3(40, 0, -46), Vector3(36, 0, -56), Vector3(-80, 0, 2)]:
				pts.append(c)
		"texas":
			for x in range(-44, 72, 16):
				pts.append(Vector3(x, 0, -3.4))
			for c in [Vector3(-11, 0, 1), Vector3(11, 0, 1), Vector3(-11, 0, 15), Vector3(11, 0, 15), Vector3(76, 0, -6)]:
				pts.append(c)
		"everglades":
			for c in [Vector3(-78, 0, -8), Vector3(-86, 0, 2), Vector3(52, 0, 44), Vector3(68, 0, 44), Vector3(-36, 0, 20), Vector3(32, 0, -34)]:
				pts.append(c)
		"sedona":
			for i in 5:
				pts.append(Vector3(26 + i * 8.0, 0, 46))
			for c in [Vector3(-76, 0, 36), Vector3(36, 0, 4), Vector3(56, 0, 4)]:
				pts.append(c)
		"socal":
			for x in range(-48, 92, 20):
				pts.append(Vector3(x, 0, 25.4))
			for c in [Vector3(-80, 0, 2), Vector3(-8, 0, -30), Vector3(-28, 0, -30), Vector3(42, 0, -2), Vector3(62, 0, -2)]:
				pts.append(c)
	for p in pts:
		var gy := ground_y(p.x, p.z)
		_cyl(0.07, 0.09, 4.2, Vector3(p.x, gy + 2.1, p.z), Color(0.18, 0.18, 0.2), 6)
		var head := MeshInstance3D.new()
		head.mesh = _mk_sphere(0.28, 0.56)
		head.material_override = DayNight.lamp_material()
		head.position = Vector3(p.x, gy + 4.35, p.z)
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(head)

func _build_clouds() -> void:
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(1, 1, 1)
	cm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	cm.emission_enabled = true
	cm.emission = Color(0.55, 0.6, 0.68)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var mesh := BodyRig._sph(1.0, -1, 10)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var xf: Array = []
	for i in 16:
		var c := Vector3(rng.randf_range(-160, 160), rng.randf_range(48, 70), rng.randf_range(-160, 160))
		for k in rng.randi_range(4, 7):
			var sc := rng.randf_range(5, 11)
			xf.append(Transform3D(Basis().scaled(Vector3(sc * 1.4, sc * 0.6, sc)), c + Vector3(rng.randf_range(-12, 12), rng.randf_range(-1.5, 2), rng.randf_range(-6, 6))))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = cm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

## Grass tufts and wildflowers: two cheap MultiMeshes for a lot of life.
func _build_ground_detail() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var blade := PrismMesh.new()
	blade.size = Vector3(0.18, 0.42, 0.02)
	var parts := {
		"grass_a": {"mesh": blade, "color": Color(0.32, 0.55, 0.2) if not zone in ["chapada", "sedona"] else Color(0.55, 0.55, 0.25), "xf": []},
		"grass_b": {"mesh": blade, "color": Color(0.42, 0.63, 0.24) if not zone in ["chapada", "sedona"] else Color(0.65, 0.58, 0.3), "xf": []},
		"flower_y": {"mesh": BodyRig._sph(0.07, -1, 6), "color": Color(0.98, 0.85, 0.2), "xf": []},
		"flower_p": {"mesh": BodyRig._sph(0.07, -1, 6), "color": Color(0.9, 0.45, 0.75), "xf": []},
	}
	var placed := 0
	var tries := 0
	while placed < 2600 and tries < 9000:
		tries += 1
		var x := rng.randf_range(-88, 88)
		var z := rng.randf_range(-88, 88)
		if _is_blocked(x, z, 0.5):
			continue
		var gy := ground_y(x, z)
		if gy < -0.25 or gy > 9.0:
			continue
		if zone == "caceres" and absf(x - river_x(z)) < 12.0:
			continue
		if (zone == "rio" or zone == "socal") and ((z > -30.0 and x > -64.0) or z > 16.0):
			continue
		if absf(ground_y(x + 1.0, z) - gy) > 0.8:
			continue
		var roll := rng.randf()
		var key := "grass_a" if roll < 0.5 else ("grass_b" if roll < 0.94 else ("flower_y" if roll < 0.97 else "flower_p"))
		for k in (3 if key.begins_with("grass") else 1):
			var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
			var sc := rng.randf_range(0.7, 1.3)
			var off := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
			var h := 0.18 * sc if key.begins_with("grass") else 0.32
			parts[key].xf.append(Transform3D(b.scaled(Vector3(sc, sc, sc)), Vector3(x, gy + h, z) + off))
		placed += 1
	for k in parts:
		var p: Dictionary = parts[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = p.mesh
		mm.instance_count = p.xf.size()
		for i in p.xf.size():
			mm.set_instance_transform(i, p.xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = EnvShaders.grass(p.color, 1.0 if str(k).begins_with("grass") else 0.6)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 70.0
		add_child(mmi)

func _build_terrain() -> void:
	var step := 2
	var n := HALF * 2 / step + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs: Array = []
	hs.resize(n * n)
	for iz in n:
		for ix in n:
			var x := -HALF + ix * step
			var z := -HALF + iz * step
			hs[iz * n + ix] = height(x, z)
	for iz in n - 1:
		for ix in n - 1:
			var quad := [Vector2i(ix, iz), Vector2i(ix + 1, iz), Vector2i(ix + 1, iz + 1), Vector2i(ix, iz + 1)]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for k in tri:
					var q: Vector2i = quad[k]
					var x := float(-HALF + q.x * step)
					var z := float(-HALF + q.y * step)
					var h: float = hs[q.y * n + q.x]
					st.set_color(_ground_color(x, z, h))
					st.add_vertex(Vector3(x, h, z))
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = EnvShaders.terrain({"chapada": 1.0, "rio": 0.7, "sedona": 1.0}.get(zone, 0.35), {"texas": {"grass": "prairie", "dirt": "caliche"}, "sedona": {"dirt": "caliche"}}.get(zone, {}))
	mi.name = "Terrain"
	add_child(mi)
	# collision: 1 m heightmap
	var w := HALF * 2 + 1
	var data := PackedFloat32Array()
	data.resize(w * w)
	for iz in w:
		for ix in w:
			data[iz * w + ix] = height(-HALF + ix, -HALF + iz)
	var hm := HeightMapShape3D.new()
	hm.map_width = w
	hm.map_depth = w
	hm.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = hm
	_static.add_child(cs)

func _build_water() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = EnvShaders.water_plane(Vector2(60, 220), 3.0)
	# Rio Paraguai: brown-green, flowing south
	mi.material_override = EnvShaders.water(Color(0.1, 0.24, 0.24), Color(0.24, 0.4, 0.36, 0.88), 0.06, 0.22, Vector2(0.0, 0.6))
	mi.position = Vector3(-72, WATER_Y, 0)
	add_child(mi)

## Paving: painted tiling textures in world space (so long streets stay seamless).
static var _pave_cache := {}
func _pave_mat(tex: String, scale: float) -> StandardMaterial3D:
	var key := tex + str(scale)
	if _pave_cache.has(key):
		return _pave_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = EnvShaders.env_tex(tex)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = 0.95
	_pave_cache[key] = m
	return m

## A paved strip laid on the terrain in short segments (follows the ground).
func _street(a: Vector3, b: Vector3, width: float, tex := "cobble", scale := 0.32) -> void:
	var d := b - a
	d.y = 0
	var n := maxi(1, int(ceil(d.length() / 3.0)))
	var yaw := atan2(d.x, d.z)
	for i in n:
		var p0 := a + d * (float(i) / n)
		var p1 := a + d * (float(i + 1) / n)
		var mid := (p0 + p1) * 0.5
		var gy := maxf(ground_y(p0.x, p0.z), ground_y(p1.x, p1.z))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width, 0.16, d.length() / n + 0.35)
		mi.mesh = bm
		mi.material_override = _pave_mat(tex, scale)
		mi.position = Vector3(mid.x, gy + 0.02, mid.z)
		mi.rotation.y = yaw
		mi.set_meta("no_batch", true)
		add_child(mi)

func _build_roads_and_plaza() -> void:
	var gy := ground_y(0, 8)
	var plaza := _box(Vector3(30, 0.3, 20), Vector3(0, gy, 8), Color(0.66, 0.56, 0.45), true)
	# calçada portuguesa: black-and-white wave mosaic
	plaza.material_override = _pave_mat("calcada", 0.16)
	plaza.set_meta("no_batch", true)
	# cobbled main streets through the old centre
	_street(Vector3(-56, 0, -4), Vector3(80, 0, -4), 6.0)
	_street(Vector3(9, 0, -52), Vector3(9, 0, -6), 5.0)
	_street(Vector3(20, 0, 22), Vector3(20, 0, 30), 4.0)
	_cyl(2.6, 2.8, 0.7, Vector3(0, gy + 0.4, 8), Color(0.75, 0.72, 0.65), 16, true)
	var water := _cyl(2.3, 2.3, 0.1, Vector3(0, gy + 0.75, 8), Color(0.3, 0.6, 0.8), 16)
	water.material_override = _mat(Color(0.3, 0.6, 0.85), 0.1)
	_cyl(0.3, 0.4, 2.0, Vector3(0, gy + 1.4, 8), Color(0.8, 0.78, 0.7), 8)
	for p in [Vector3(-9, 0, 2), Vector3(9, 0, 2), Vector3(-9, 0, 14), Vector3(9, 0, 14)]:
		_box(Vector3(2.4, 0.5, 0.7), Vector3(p.x, gy + 0.4, p.z), Color(0.45, 0.3, 0.18), true)
	for p in [Vector3(-13, 0, -0.5), Vector3(13, 0, -0.5), Vector3(-13, 0, 16.5), Vector3(13, 0, 16.5)]:
		_mango_tree(Vector3(p.x, gy, p.z), 1.1)
	_label("PRAÇA", Vector3(0, gy + 3.6, 8), 80, Color(1, 0.95, 0.8))

func _build_cathedral() -> void:
	var c := Vector3(0, ground_y(0, -24), -24)
	# twin-tower colonial church (tools/townbuild/houses.py igreja), façade toward the plaza
	var items: Array = [{"kind": "igreja", "xform": Transform3D(Basis.IDENTITY, c + Vector3(0, -0.05, 0.6)),
		"wall": Color(0.97, 0.95, 0.9), "wood": Color(0.32, 0.2, 0.12)}]
	TownKit.build(self, items)
	# collision: nave + towers
	for sh in [[Vector3(10, 12, 15), Vector3(0, 6, 0.6)], [Vector3(3.4, 20, 3.4), Vector3(-6.3, 10, 7.1)], [Vector3(3.4, 20, 3.4), Vector3(6.3, 10, 7.1)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sh[0]
		cs.shape = bs
		cs.position = c + sh[1]
		_static.add_child(cs)
	_kit_footprints.append([Rect2(c.x - 8, c.z - 7, 16, 16), Color(0.97, 0.95, 0.9)])

func _build_academia() -> void:
	var c := Vector3(0, ground_y(0, -54), -54)
	var wall := Color(0.92, 0.6, 0.25)
	_box(Vector3(18, 0.3, 14), c + Vector3(0, 0.15, 0), Color(0.6, 0.55, 0.5))
	# the hall itself is a Blender model (tools/townbuild/houses.py academia); these boxes only collide
	for b in [[Vector3(0.5, 5, 14), Vector3(-9, 2.5, 0)], [Vector3(0.5, 5, 14), Vector3(9, 2.5, 0)], [Vector3(18, 5, 0.5), Vector3(0, 2.5, -7)]]:
		_box(b[0], c + b[1], wall).visible = false
	for x in [-8.4, -3, 3, 8.4]:
		_box(Vector3(1.1, 5, 0.9), c + Vector3(x, 2.5, 6.55), wall).visible = false
	TownKit.build(self, [{"kind": "academia", "xform": Transform3D(Basis.IDENTITY, c + Vector3(0, -0.02, 0)),
		"wall": Color(0.95, 0.62, 0.28), "wood": Color(0.3, 0.2, 0.12)}])
	_kit_footprints.append([Rect2(c.x - 9, c.z - 7, 18, 14), wall])
	# tatame inside
	for x in 8:
		for z in 6:
			var col := Color(0.13, 0.38, 0.26) if (x + z) % 2 == 0 else Color(0.78, 0.62, 0.22)
			_box(Vector3(1.96, 0.08, 1.96), c + Vector3(-7 + x * 2, 0.34, -5 + z * 2), col, false)
	var sign_l := _label("ACADEMIA ONÇA", c + Vector3(0, 4.82, 7.1), 120, Color(0.2, 0.12, 0.05))
	sign_l.outline_size = 0
	# the founder in bronze on one side of the door, the kids-class mascot on the other
	_statue("statue_mestre", c + Vector3(-6.2, 0, 10.5), 0.25, 1.25, "O MESTRE", "Fundador · Academia Onça")
	var kid := _place_model("mascot_junior", c + Vector3(6.2, 0.55, 10.5), 1.0, -0.25, Vector3(1.2, 1.6, 1.2))
	if kid:
		_box(Vector3(1.4, 0.55, 1.4), c + Vector3(6.2, 0.27, 10.5), Color(0.13, 0.38, 0.26))
		_label("AULA KIDS · 17h", c + Vector3(6.2, 2.25, 10.5), 44, Color(1, 0.9, 0.4))
	_label("JIU-JITSU · OSS", c + Vector3(0, 4.3, 7.35), 70, Color(1, 1, 1))
	var lamp := OmniLight3D.new()
	lamp.position = c + Vector3(0, 4.2, 0)
	lamp.omni_range = 12
	lamp.light_energy = 1.2
	lamp.light_color = Color(1, 0.85, 0.6)
	add_child(lamp)

func _build_market() -> void:
	var colors := [Color(0.85, 0.25, 0.2), Color(0.2, 0.5, 0.85), Color(0.95, 0.75, 0.2), Color(0.2, 0.7, 0.4)]
	var i := 0
	for x in [22, 30, 38]:
		for z in [-17, -27]:
			var gy := ground_y(x, z)
			_box(Vector3(5, 1, 2.4), Vector3(x, gy + 0.5, z), Color(0.5, 0.35, 0.2))
			for px in [-2.3, 2.3]:
				_box(Vector3(0.2, 2.8, 0.2), Vector3(x + px, gy + 1.4, z - 1.0), Color(0.4, 0.3, 0.2), false)
			var awn := _box(Vector3(5.6, 0.15, 3.2), Vector3(x, gy + 2.9, z - 0.2), colors[i % colors.size()], false)
			awn.rotation.x = 0.18
			for k in 6:
				var fruit := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.22
				sm.height = 0.44
				sm.radial_segments = 8
				sm.rings = 4
				fruit.mesh = sm
				var fc: Color = [Color(1, 0.55, 0.1), Color(0.9, 0.2, 0.2), Color(0.95, 0.85, 0.2), Color(0.4, 0.75, 0.25)][(k + i) % 4]
				fruit.material_override = _mat(fc, 0.5)
				fruit.position = Vector3(x - 1.8 + k * 0.7, gy + 1.15, z + 0.3)
				add_child(fruit)
			i += 1
	_label("FEIRA", Vector3(30, ground_y(30, -22) + 4.5, -22), 90, Color(1, 0.9, 0.6))

func _build_houses() -> void:
	# pastel colonial palette (walls) and shutter / door colours
	var palette := [Color(0.97, 0.85, 0.42), Color(0.55, 0.75, 0.92), Color(0.95, 0.6, 0.62), Color(0.6, 0.82, 0.55),
		Color(0.98, 0.95, 0.88), Color(0.96, 0.65, 0.38), Color(0.78, 0.62, 0.86), Color(0.45, 0.72, 0.7)]
	var spots: Array = []   # [position, front direction toward the street]
	for x in range(-52, 66, 10):
		spots.append([Vector3(x, 0, -14), Vector3(0, 0, 1)])
		spots.append([Vector3(x, 0, 6), Vector3(0, 0, -1)])
	for z in range(-46, 0, 10):
		spots.append([Vector3(19, 0, z), Vector3(-1, 0, 0)])
		spots.append([Vector3(-1, 0, z), Vector3(1, 0, 0)])
	var items: Array = []
	for sp in spots:
		var p: Vector3 = sp[0]
		var front: Vector3 = sp[1]
		if _is_blocked(p.x, p.z, 1.0):
			continue
		if absf(p.x - river_x(p.z)) < 20.0:
			continue
		_town_building(items, p, front, palette)
	TownKit.build(self, items)

## Places one kit building (two-storey ones near the plaza and main streets) with collision and a
## minimap footprint. front: direction the façade faces.
func _town_building(items: Array, p: Vector3, front: Vector3, palette: Array, kind := "", fit := 8.6, wood_pal: Array = []) -> void:
	if kind == "":
		var near_centre := Vector2(p.x, p.z).length() < 32.0
		var pool: Array = ["sobrado_a", "sobrado_loja", "casa_b", "casa_d"] if near_centre else ["casa_a", "casa_b", "casa_c", "casa_d", "casa_varanda", "casa_a"]
		kind = pool[_rng.randi() % pool.size()]
	var sz := TownKit.size(kind)
	var sc := minf(1.0, fit / maxf(sz.x, sz.z)) if fit > 0.0 else 1.0
	var gy := ground_y(p.x, p.z)
	var yaw := atan2(front.x, front.z)
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
	var col: Color = palette[_rng.randi() % palette.size()]
	var wp: Array = wood_pal if not wood_pal.is_empty() else SHUTTERS
	var wood: Color = wp[_rng.randi() % wp.size()]
	items.append({"kind": kind, "xform": Transform3D(b, Vector3(p.x, gy - 0.05, p.z)), "wall": col, "wood": wood})
	# collision + footprint (walls only; the roof overhang stays walkable-under)
	var fx := sz.x * sc - 0.8
	var fz := sz.z * sc - 0.8
	var foot := Vector3(fx, 7.0, fz) if front.z != 0.0 else Vector3(fz, 7.0, fx)
	var ab := TownKit.mesh(kind).get_aabb()
	var off := Basis(Vector3.UP, yaw) * (ab.get_center() * sc)
	var q := Vector3(p.x + off.x, 0, p.z + off.z)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = foot
	cs.shape = sh
	cs.position = Vector3(q.x, gy + 3.5, q.z)
	_static.add_child(cs)
	_kit_footprints.append([Rect2(q.x - foot.x / 2, q.z - foot.z / 2, foot.x, foot.z), col])
	_blocked.append(Rect2(q.x - foot.x / 2 - 1, q.z - foot.z / 2 - 1, foot.x + 2, foot.z + 2))

## Colonial facade details on a box house: painted base band (barrado), door with frame,
## windows with shutters and sills, white eave trim. All static boxes, so they batch.
const SHUTTERS := [Color(0.2, 0.45, 0.32), Color(0.2, 0.32, 0.55), Color(0.45, 0.28, 0.16), Color(0.6, 0.15, 0.15)]
func _facade(base: Vector3, size: Vector3, front: Vector3, col: Color) -> void:
	var side := Vector3(front.z, 0, -front.x).abs()   # along the front wall
	var half_front := (size.z if front.z != 0.0 else size.x) * 0.5
	var width := size.x if front.z != 0.0 else size.z
	var face := base + front * (half_front + 0.04)
	var thin := func(along: float, up: float, depth := 0.08) -> Vector3:
		return side * along + Vector3(0, up, 0) + front.abs() * depth
	var white := Color(0.97, 0.96, 0.92)
	var shutter: Color = SHUTTERS[_rng.randi() % SHUTTERS.size()]
	# barrado: darker band around the bottom
	_box(Vector3(size.x + 0.06, 0.55, size.z + 0.06), base + Vector3(0, 0.27, 0), col.darkened(0.35), false)
	# door + frame
	_box(thin.call(1.3, 2.3, 0.06), face + Vector3(0, 1.15, 0), white, false)
	_box(thin.call(1.0, 2.05, 0.1), face + Vector3(0, 1.03, 0) + front * 0.02, shutter.darkened(0.2), false)
	# windows either side of the door
	for sgn in [-1.0, 1.0]:
		var off: float = sgn * minf(width * 0.3, 2.0)
		var wc := face + side * off + Vector3(0, 1.9, 0)
		_box(thin.call(1.05, 1.1, 0.06), wc, white, false)
		_box(thin.call(0.8, 0.85, 0.1), wc + front * 0.02, Color(0.16, 0.2, 0.26), false)
		for sh in [-1.0, 1.0]:
			_box(thin.call(0.42, 0.95, 0.07), wc + side * (sh * 0.72) + front * 0.03, shutter, false)
		_box(thin.call(1.2, 0.08, 0.22), wc + Vector3(0, -0.6, 0) + front * 0.06, white, false)
	# eave trim
	_box(Vector3(size.x + 0.1, 0.18, size.z + 0.1), base + Vector3(0, size.y - 0.09, 0), white, false)

func _mango_tree(p: Vector3, s := 1.0, model := "tree_fat", tint := Color(0.18, 0.42, 0.18)) -> void:
	# trunk collider + the sculpted mango (tools/townbuild/trees.py), swaying in the wind
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.4 * s
	sh.height = 3.0 * s
	cs.shape = sh
	cs.position = p + Vector3(0, 1.5 * s, 0)
	_static.add_child(cs)
	var md := _model_mesh(model, tint)
	if md.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _swaying(md.mesh, model)
	mi.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * 5.2 * s), p) * (md.xf as Transform3D)
	add_child(mi)

func _build_trees() -> void:
	# CC0 models (Kenney Nature Kit), batched with MultiMesh to stay cheap on phones.
	var xf := {"palm": [], "oak": [], "fat": [], "ipe": [], "liveoak": [], "cedar": [], "mesquite": [], "cypress": []}
	var west := zone in ["texas", "sedona"]   # Hill Country / high desert: live oaks, cedars, mesquite
	var placed := 0
	var tries := 0
	while placed < {"caceres": 170, "pantanal": 140, "chapada": 120, "rio": 150, "socal": 70, "texas": 130, "everglades": 140, "sedona": 110}[zone] and tries < 3000:
		tries += 1
		var x := _rng.randf_range(-92, 92)
		var z := _rng.randf_range(-92, 92)
		if _is_blocked(x, z, 2.0):
			continue
		var d := absf(x - river_x(z)) if zone == "caceres" else 50.0
		if d < 10.0:
			continue
		var gy := ground_y(x, z)
		if zone == "rio" and ((z > -30.0 and x > -64.0) or Vector2(x, z).distance_to(SUGARLOAF) < 16.0):
			continue
		if zone == "socal" and ((z > -30.0 and x > -64.0) or z > 16.0):
			continue
		if zone == "chapada" or zone == "rio" or zone == "socal":
			if absf(ground_y(x, z + 2.0) - gy) > 1.2 or absf(ground_y(x + 2.0, z) - gy) > 1.2 or gy < -0.3:
				continue
			d = 40.0
		if zone == "everglades":
			# cypress domes stand right in the water; palms and oaks only on dry ground
			if gy < -0.85:
				continue
			var cb := Basis(Vector3.UP, _rng.randf() * TAU)
			var r := _rng.randf()
			var s := _rng.randf_range(0.8, 1.3)
			if gy < -0.1 or r < 0.45:
				xf.cypress.append(Transform3D(cb.scaled(Vector3.ONE * 5.4 * s), Vector3(x, gy - 0.1, z)))
			elif r < 0.8:
				xf.palm.append(Transform3D(cb.scaled(Vector3.ONE * 5.0 * s), Vector3(x, gy, z)))
			else:
				xf.liveoak.append(Transform3D(cb.scaled(Vector3.ONE * 4.4 * s), Vector3(x, gy, z)))
			placed += 1
			continue
		if zone == "pantanal":
			if gy < -0.15:
				continue
			d = 18.0 if _rng.randf() < (0.45 if zone == "pantanal" else 0.3) else 40.0  # carandá / cabbage palms
		if zone == "texas" or zone == "sedona":
			if gy < -0.5 or absf(ground_y(x, z + 2.0) - gy) > 1.0 or absf(ground_y(x + 2.0, z) - gy) > 1.0 or (zone == "sedona" and gy > 3.0):
				continue
			if zone == "texas" and ((Vector2(x, z).distance_to(Vector2(0, -20)) < 30.0 and absf(x) < 60.0 and z > -40.0 and z < 22.0) or Vector2(x, z).distance_to(Vector2(0, 24)) < 16.0):
				continue   # keep the town centre and the arrival view open
			d = 40.0
		var s := _rng.randf_range(0.8, 1.3)
		var kind := _rng.randf()
		if zone == "texas" or zone == "sedona":
			kind = 0.3 + kind * 0.7   # live oaks and junipers, no palms
		if zone == "sedona":
			s *= 0.7
		var base := Vector3(x, gy, z)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.35 * s
		sh.height = 4.0
		cs.shape = sh
		cs.position = base + Vector3(0, 2, 0)
		_static.add_child(cs)
		var b := Basis(Vector3.UP, _rng.randf() * TAU)
		if west:
			var r := _rng.randf()
			if zone == "texas":
				if r < 0.55:
					xf.liveoak.append(Transform3D(b.scaled(Vector3.ONE * 4.8 * s), base))
				elif r < 0.85:
					xf.cedar.append(Transform3D(b.scaled(Vector3.ONE * 4.2 * s), base))
				else:
					xf.mesquite.append(Transform3D(b.scaled(Vector3.ONE * 4.6 * s), base))
			else:
				if r < 0.6:
					xf.cedar.append(Transform3D(b.scaled(Vector3.ONE * 4.0 * s), base))
				else:
					xf.mesquite.append(Transform3D(b.scaled(Vector3.ONE * 4.4 * s), base))
			placed += 1
			continue
		if zone == "socal":
			# coastal California: fan palms, coast live oaks, chaparral scrub trees, a few jacarandas
			if kind < 0.35:
				xf.palm.append(Transform3D(b.scaled(Vector3.ONE * 6.0 * s), base))
			elif kind < 0.65:
				xf.liveoak.append(Transform3D(b.scaled(Vector3.ONE * 4.2 * s), base))
			elif kind < 0.88:
				xf.mesquite.append(Transform3D(b.scaled(Vector3.ONE * 3.8 * s), base))
			else:
				xf.ipe.append(Transform3D(b.scaled(Vector3.ONE * 4.4 * s), base))
			placed += 1
			continue
		if d < 22.0 or kind < 0.25:
			xf.palm.append(Transform3D(b.scaled(Vector3.ONE * 5.4 * s), base))
		elif kind > 0.85:
			xf.ipe.append(Transform3D(b.scaled(Vector3.ONE * 4.8 * s), base))
		elif kind > 0.55:
			xf.oak.append(Transform3D(b.scaled(Vector3.ONE * 5.0 * s), base))
		else:
			xf.fat.append(Transform3D(b.scaled(Vector3.ONE * 4.8 * s), base))
		placed += 1
	var ipe_col := Color(0.9, 0.45, 0.7) if zone == "pantanal" else Color(0.98, 0.78, 0.15)
	if zone in ["texas", "sedona", "everglades"]:
		ipe_col = {"texas": Color(0.3, 0.42, 0.2), "sedona": Color(0.25, 0.38, 0.25), "everglades": Color(0.22, 0.36, 0.16)}[zone]
	if west:
		_mm("tree_liveoak", xf.liveoak, Color(0.3, 0.38, 0.18))
		_mm("tree_cedar", xf.cedar, Color(0.16, 0.26, 0.15) if zone == "texas" else Color(0.22, 0.32, 0.2))
		_mm("tree_mesquite", xf.mesquite, Color(0.4, 0.5, 0.24))
		_west_flora()
		return
	if zone == "socal":
		ipe_col = Color(0.58, 0.45, 0.85)   # jacaranda
		_mm("tree_liveoak", xf.liveoak, Color(0.28, 0.38, 0.2))
		_mm("tree_mesquite", xf.mesquite, Color(0.42, 0.46, 0.3))
	if zone == "everglades":
		_mm("tree_cypress", xf.cypress, Color(0.34, 0.44, 0.22))
		_mm("tree_liveoak", xf.liveoak, Color(0.22, 0.36, 0.16))
	_mm("tree_palm", xf.palm)
	_mm("tree_oak", xf.oak)
	_mm("tree_fat", xf.fat, Color(0.2, 0.42, 0.18))
	_mm("tree_fat", xf.ipe, ipe_col)

## Ground-level desert plants: prickly pear and yucca (no collision, batched).
func _west_flora() -> void:
	var pear: Array = []
	var yuc: Array = []
	var tries := 0
	var want := 110 if zone == "texas" else 140
	while pear.size() + yuc.size() < want and tries < 3000:
		tries += 1
		var x := _rng.randf_range(-94, 94)
		var z := _rng.randf_range(-94, 94)
		if _is_blocked(x, z, 1.5):
			continue
		if zone == "texas" and Vector2(x, z).distance_to(Vector2(0, -10)) < 34.0:
			continue
		var gy := ground_y(x, z)
		if gy < water_level() + 0.2:
			continue
		var b := Basis(Vector3.UP, _rng.randf() * TAU)
		if _rng.randf() < 0.55:
			pear.append(Transform3D(b.scaled(Vector3.ONE * _rng.randf_range(3.0, 5.0)), Vector3(x, gy - 0.05, z)))
		else:
			yuc.append(Transform3D(b.scaled(Vector3.ONE * _rng.randf_range(3.2, 4.6)), Vector3(x, gy - 0.05, z)))
	_mm("cactus_pear", pear, Color(0.32, 0.48, 0.22), false)
	_mm("yucca", yuc, Color(0.38, 0.5, 0.3), false)

# ---------------------------------------------------------------- CC0 model helpers
static var _model_cache := {}

## Kenney's pastel palette, re-mapped by material name to fit Mato Grosso.
const PALETTE := {
	"grass": Color(0.27, 0.47, 0.18), "leafsGreen": Color(0.24, 0.5, 0.2), "leafs": Color(0.24, 0.5, 0.2),
	"woodBark": Color(0.42, 0.3, 0.2), "woodInner": Color(0.78, 0.66, 0.5), "dirt": Color(0.46, 0.37, 0.28),
	"rock": Color(0.56, 0.53, 0.49), "rockTrack": Color(0.5, 0.47, 0.44), "stone": Color(0.56, 0.53, 0.49),
	"crystal": Color(0.78, 0.68, 0.98), "moss": Color(0.5, 0.54, 0.46), "colorRed": Color(0.86, 0.2, 0.24), "colorYellow": Color(0.98, 0.82, 0.2),
}

## Rock colour per zone (Hill Country limestone, red Sedona sandstone).
const ROCK_TINT := {"texas": Color(0.8, 0.75, 0.6), "sedona": Color(0.72, 0.36, 0.22)}

## Lambert copy of a model material: keeps textures, swaps pastel colors for our palette.
func _prop_mat(src: BaseMaterial3D, leaf_tint := Color(0, 0, 0, 0)) -> Material:
	if src and src.albedo_texture:
		var m := src.duplicate() as BaseMaterial3D
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		m.roughness = 0.8
		return m
	var nm := src.resource_name if src else ""
	var col: Color = PALETTE.get(nm, src.albedo_color.srgb_to_linear() if src else Color(0.5, 0.5, 0.5))
	if nm in ["rock", "rockTrack", "stone"] and ROCK_TINT.has(zone):
		col = ROCK_TINT[zone]
	if nm == "colorRed" and zone == "texas":
		col = Color(0.22, 0.32, 0.85)   # bluebonnets
	if leaf_tint.a > 0.0 and (nm.begins_with("leaf") or nm == "grass"):
		col = leaf_tint
	return _mat(col, 0.9)

## Returns {"mesh": ArrayMesh, "xf": Transform3D} for the first mesh in a model, with lambert
## materials (optionally tinting the foliage surfaces).
func _model_mesh(n: String, leaf_tint := Color(0, 0, 0, 0)) -> Dictionary:
	var key := n + leaf_tint.to_html() + (zone if ROCK_TINT.has(zone) else "")
	if _model_cache.has(key):
		return _model_cache[key]
	var path := "res://assets/models/%s.glb" % n
	if not ResourceLoader.exists(path):
		return {}
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		inst.free()
		return {}
	var mi := found[0] as MeshInstance3D
	var chain := mi.transform
	var p := mi.get_parent()
	while p and p != inst:
		if p is Node3D:
			chain = (p as Node3D).transform * chain
		p = p.get_parent()
	var mesh := (mi.mesh as ArrayMesh).duplicate() as ArrayMesh
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, _prop_mat(mesh.surface_get_material(i) as BaseMaterial3D, leaf_tint))
	var out := {"mesh": mesh, "xf": chain}
	inst.free()
	_model_cache[key] = out
	return out

func _mm(n: String, xforms: Array, leaf_tint := Color(0, 0, 0, 0), shadows := true) -> void:
	if xforms.is_empty():
		return
	var md := _model_mesh(n, leaf_tint)
	if md.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = md.mesh
	if n.begins_with("tree") or n.begins_with("bush") or n == "flower_red":
		mm.mesh = _swaying(md.mesh, n)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, (xforms[i] as Transform3D) * (md.xf as Transform3D))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

## Copy of a model mesh whose flat-colored surfaces sway in the wind (trees bend at the top).
static var _sway_cache := {}
func _swaying(src: Mesh, n: String) -> Mesh:
	var key := str(src.get_instance_id())
	if _sway_cache.has(key):
		return _sway_cache[key]
	var aabb := src.get_aabb()
	var out := (src as ArrayMesh).duplicate() as ArrayMesh
	var strength := 1.0 if n.begins_with("tree") else 0.5
	for i in out.get_surface_count():
		var m := out.surface_get_material(i) as StandardMaterial3D
		if m and m.albedo_texture == null:
			out.surface_set_material(i, EnvShaders.foliage(m.albedo_color, strength, maxf(aabb.end.y, 0.3)))
	_sway_cache[key] = out
	return out

## Place a full model scene (with its own animation, if any).
func _place_model(n: String, pos: Vector3, scale_v: float, rot_y := 0.0, box := Vector3.ZERO) -> Node3D:
	var path := "res://assets/models/%s.glb" % n
	if not ResourceLoader.exists(path):
		return null
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	inst.position = pos
	inst.rotation.y = rot_y
	inst.scale = Vector3.ONE * scale_v
	add_child(inst)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, _prop_mat(mi.mesh.surface_get_material(i) as BaseMaterial3D))
	if box != Vector3.ZERO:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = box
		cs.shape = sh
		cs.position = pos + Vector3(0, box.y / 2.0, 0)
		cs.rotation.y = rot_y
		_static.add_child(cs)
	return inst

# ================================================================ dressing (tools/propbuild)
## A Blender-built prop at (x, z) on the ground. Skips spots that would land in a building unless
## `inside` (for gym interiors). box > 0 adds a collider.
func _prop(n: String, x: float, z: float, rot := 0.0, box := Vector3.ZERO, inside := false, sc := 1.0) -> void:
	if not inside and _is_blocked(x, z, 0.4):
		return
	_place_model("props/" + n, Vector3(x, ground_y(x, z), z), sc, rot, box)

## Props by zone: gym gear, plaza lamps and boteco tables, market stalls, beach kiosks...
func _dress_props() -> void:
	match zone:
		"caceres":
			var c := Vector3(0, 0, -54)   # Academia Onça
			_prop("heavy_bag", c.x - 7.2, c.z - 5.6, 0.0, Vector3(1.2, 2.4, 0.6), true)
			_prop("heavy_bag", c.x + 7.2, c.z - 5.6, 0.0, Vector3(1.2, 2.4, 0.6), true)
			_prop("mat_stack", c.x - 7.6, c.z + 4.0, 0.3, Vector3(1, 0.5, 2), true)
			_prop("weights", c.x + 7.8, c.z + 2.5, -PI / 2, Vector3(0.5, 0.6, 1.2), true)
			var g := Vector3(59, 0, -64)  # Galpão
			_prop("heavy_bag", g.x - 6.0, g.z - 4.0, 0.0, Vector3(1.2, 2.4, 0.6), true)
			_prop("heavy_bag", g.x + 6.0, g.z - 4.0, 0.0, Vector3(1.2, 2.4, 0.6), true)
			_prop("weights", g.x + 7.0, g.z + 2.0, -PI / 2, Vector3(0.5, 0.6, 1.2), true)
			_prop("mat_stack", g.x - 7.0, g.z + 3.0, 0.0, Vector3(1, 0.5, 2), true)
			for p in [Vector2(-11, 8), Vector2(11, 8), Vector2(0, -2), Vector2(0, 18)]:   # Praça lamps
				_prop("street_lamp", p.x, p.y, 0.0, Vector3(0.3, 3.6, 0.3), true)
			for p in [Vector2(-17, 20), Vector2(-14, 23), Vector2(17, 20)]:   # boteco tables
				_prop("bar_table", p.x, p.y, randf() * TAU)
			var sq := Vector3(28, 0, 60)  # Praça Vila Nova
			_prop("acai_cart", sq.x - 6.5, sq.z + 2.0, 0.4, Vector3(1.4, 1.2, 0.9))
			_prop("street_lamp", sq.x - 8.5, sq.z - 6.5, 0.0, Vector3(0.3, 3.6, 0.3), true)
			_prop("street_lamp", sq.x + 8.5, sq.z + 6.5, 0.0, Vector3(0.3, 3.6, 0.3), true)
			for x in [12.0, 46.0]:   # Feira: two more stalls
				_prop("market_stall", x, -22.0, 0.0, Vector3(2.2, 1.0, 1.0))
			var q := Vector3(62, 0, 66)   # Quadra benches
			_prop("bench", q.x - 4, q.z + 7.6, PI, Vector3(1.8, 0.8, 0.5))
			_prop("bench", q.x + 4, q.z + 7.6, PI, Vector3(1.8, 0.8, 0.5))
			var pr := Vector3(-40, 0, 70)  # Prainha
			_prop("kiosk", pr.x + 11, pr.z - 5, PI, Vector3(2.8, 3, 2.8), true)
			_prop("bar_table", pr.x + 8, pr.z - 1, 0.6, Vector3.ZERO, true)
			_prop("bar_table", pr.x + 13, pr.z + 0, 1.8, Vector3.ZERO, true)
			_prop("hammock", pr.x - 10, pr.z - 4, 0.3, Vector3.ZERO, true)
			_prop("canoe", pr.x - 3, pr.z + 6, 1.1, Vector3(4.2, 0.6, 1.0), true)
			_prop("bus_stop", 20, 4, 0.0, Vector3(2.6, 2.4, 1.2))
		"pantanal":
			_dress_camp("pesca", [["canoe", 1.1], ["pier", 0.0], ["hammock", 0.4], ["bench", 2.0]])
			_dress_camp("fazenda_hands", [["hammock", 0.0], ["bar_table", 0.5], ["bench", 1.2]])
			_dress_near(VENDOR_SPOTS.pantanal[0], [["bar_table", 0.3], ["bar_table", 1.5], ["hammock", 0.8]])
		"chapada":
			_dress_camp("trail", [["bench", 0.3], ["hammock", 1.0]])
			_dress_camp("poco", [["hammock", 0.6], ["bench", 2.4]])
			_dress_near(VENDOR_SPOTS.chapada[0], [["bar_table", 0.0], ["acai_cart", 1.0], ["bench", 2.2]])
		"rio":
			_dress_camp("orla", [["kiosk", 0.0], ["surf_rack", 0.8], ["bar_table", 1.4], ["bar_table", 2.0], ["acai_cart", 2.6]])
			_dress_camp("lapa", [["street_lamp", 0.0], ["street_lamp", 1.6], ["bar_table", 0.7], ["bar_table", 2.2], ["bus_stop", 3.1]])
			_dress_near(VENDOR_SPOTS.rio[0], [["surf_rack", 0.5], ["bar_table", 1.1], ["street_lamp", 2.0]])
		"texas":
			_dress_camp("tailgate", [["bar_table", 0.2], ["bench", 1.2], ["bar_table", 2.0]])
			_dress_camp("creekbed", [["canoe", 0.6], ["hammock", 1.6], ["bench", 2.6]])
			_dress_near(VENDOR_SPOTS.texas[0], [["bench", 0.5], ["market_stall", 1.6]])
			var tg := Vector3(TX_GYM.x, 0, TX_GYM.y)
			_prop("heavy_bag", tg.x - 7.2, tg.z - 5.0, 0.0, Vector3(1.2, 2.4, 0.6), true)
			_prop("weights", tg.x + 7.8, tg.z - 4.0, -PI / 2, Vector3(0.5, 0.6, 1.2), true)
			for p in [Vector2(-17, -12), Vector2(-14, -16), Vector2(-30, -14)]:
				_prop("bar_table", p.x, p.y, randf() * TAU)
		"everglades":
			_dress_camp("airboat", [["canoe", 0.4], ["pier", 0.0], ["bench", 1.8]])
			_dress_camp("hermits", [["hammock", 0.0], ["bar_table", 0.8]])
			_dress_near(VENDOR_SPOTS.everglades[0], [["bar_table", 0.3], ["bar_table", 1.5], ["hammock", 0.8]])
			var gp := Vector3(GL_PIT.x, 0, GL_PIT.y)
			_prop("heavy_bag", gp.x - 7.2, gp.z - 5.0, 0.0, Vector3(1.2, 2.4, 0.6), true)
			_prop("mat_stack", gp.x + 7.6, gp.z + 1.0, 0.3, Vector3(1, 0.5, 2), true)
		"sedona":
			_dress_camp("jeep", [["bench", 0.3], ["acai_cart", 1.4]])
			_dress_camp("vortex", [["hammock", 0.6], ["bench", 2.4]])
			_dress_near(VENDOR_SPOTS.sedona[0], [["bar_table", 0.0], ["acai_cart", 1.0], ["bench", 2.2]])
			var sg := Vector3(SD_GYM.x, 0, SD_GYM.y)
			_prop("heavy_bag", sg.x - 7.2, sg.z - 5.0, 0.0, Vector3(1.2, 2.4, 0.6), true)
			_prop("weights", sg.x + 7.8, sg.z - 4.0, -PI / 2, Vector3(0.5, 0.6, 1.2), true)
		"socal":
			_dress_camp("boardwalk", [["surf_rack", 0.0], ["kiosk", 1.0], ["surf_rack", 2.2], ["bench", 3.0]])
			_dress_camp("hills", [["bench", 0.4], ["hammock", 1.6]])
			_dress_near(VENDOR_SPOTS.socal[0], [["surf_rack", 0.5], ["acai_cart", 1.4], ["bar_table", 2.2]])
			var gg := SOCAL_GYM
			_prop("heavy_bag", gg.x - 7.2, gg.z - 5.0, 0.0, Vector3(1.2, 2.4, 0.6), true)
			_prop("weights", gg.x + 7.8, gg.z - 4.0, -PI / 2, Vector3(0.5, 0.6, 1.2), true)
			_prop("mat_stack", gg.x - 7.6, gg.z + 1.0, 0.3, Vector3(1, 0.5, 2), true)

## Props in a ring just outside a mob camp (so they frame it without blocking the pulls).
func _dress_camp(camp_id: String, items: Array) -> void:
	for camp in Loot.CAMPS.get(zone, []):
		if str(camp.id) == camp_id:
			var c: Vector3 = camp.pos
			var r := float(camp.radius) * MOB_SPREAD + 2.0
			for i in items.size():
				var a: float = float(items[i][1]) * 1.3 + i * 0.4
				_prop(str(items[i][0]), c.x + cos(a) * r, c.z + sin(a) * r, -a)

func _dress_near(p: Vector3, items: Array) -> void:
	for i in items.size():
		var a: float = float(items[i][1]) * 2.0
		_prop(str(items[i][0]), p.x + cos(a) * 6.0, p.z + sin(a) * 6.0, -a + PI / 2)

## A bronze (or stone) statue of a Meshy figure on a pedestal with a plaque label.
func _statue(n: String, pos: Vector3, rot_y: float, scale_v: float, title: String, sub: String,
		metal := Color(0.62, 0.42, 0.22)) -> void:
	var gy := ground_y(pos.x, pos.z)
	var base := Vector3(pos.x, gy, pos.z)
	_box(Vector3(1.6, 0.9, 1.6), base + Vector3(0, 0.45, 0), Color(0.72, 0.7, 0.66))
	_box(Vector3(1.8, 0.15, 1.8), base + Vector3(0, 0.95, 0), Color(0.6, 0.58, 0.55), false)
	var inst := _place_model(n, base + Vector3(0, 1.02, 0), scale_v, rot_y, Vector3(1.2, 3.0, 1.2))
	if inst == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = metal
	mat.metallic = 0.75
	mat.roughness = 0.38
	mat.rim_enabled = true
	mat.rim = 0.25
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, mat)
	var fwd := Vector3(sin(rot_y), 0, cos(rot_y))
	var plaque := _label(title, base + Vector3(0, 0.62, 0) + fwd * 0.82, 40, Color(1, 0.88, 0.55), rot_y)
	plaque.outline_size = 6
	var l2 := _label(sub, base + Vector3(0, 0.38, 0) + fwd * 0.82, 26, Color(0.95, 0.92, 0.85), rot_y)
	l2.outline_size = 4

## Animated CC0 animal (Quaternius). length = rough body length in metres.
func _animal(n: String, pos: Vector3, length: float, rot_y := 0.0) -> void:
	var path := "res://assets/models/%s.glb" % n
	if not ResourceLoader.exists(path):
		return
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	add_child(inst)
	var aabb := AABB()
	var first := true
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src:
				mi.set_surface_override_material(i, BodyRig._mat(src.albedo_color, 0.8))
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	inst.scale = Vector3.ONE * (length / maxf(longest, 0.001))
	inst.position = pos
	inst.rotation.y = rot_y
	var ap := inst.find_children("*", "AnimationPlayer", true, false)
	if not ap.is_empty():
		var player := ap[0] as AnimationPlayer
		var pick := ""
		for a in player.get_animation_list():
			var an := str(a)
			if an.ends_with("Idle") or an.ends_with("Eating") or an.ends_with("Idle_Eating"):
				pick = an
				if _rng.randf() < 0.5:
					break
		if pick != "":
			player.get_animation(pick).loop_mode = Animation.LOOP_LINEAR
			player.play(pick)
			player.seek(_rng.randf() * 2.0)

## Bushes, rocks, flowers, logs: the small stuff that makes a place feel lived in.
func _build_props() -> void:
	var lists := {"bush": [], "bush_large": [], "rock_small": [], "rock_large": [], "flower_red": [], "stump": [], "log": []}
	var want := {"bush": 160, "bush_large": 90, "rock_small": 50, "rock_large": 25, "flower_red": 140, "stump": 12, "log": 10}
	var scale_of := {"bush": 4.5, "bush_large": 5.5, "rock_small": 4.0, "rock_large": 3.2, "flower_red": 2.6, "stump": 4.0, "log": 3.0}
	if zone == "chapada":
		want.rock_small = 110
		want.rock_large = 60
	if zone == "everglades":
		want.bush = 70          # saw palmetto scrub
		want.bush_large = 30
	if zone in ["texas", "sedona"]:
		want.bush = 50          # scrub, not jungle: the cactus, yucca and cedars do the rest
		want.bush_large = 18
		want.flower_red = 220 if zone == "texas" else 40   # Texas: bluebonnet fields
		scale_of.flower_red = 2.0
	for k in want:
		var n := 0
		var tries := 0
		while n < int(want[k]) and tries < 2000:
			tries += 1
			var x := _rng.randf_range(-90, 90)
			var z := _rng.randf_range(-90, 90)
			if _is_blocked(x, z, 1.0):
				continue
			var gy := ground_y(x, z)
			if gy < -0.2 or absf(ground_y(x + 1.0, z) - gy) > 0.9:
				continue
			if zone == "caceres" and absf(x - river_x(z)) < 11.0:
				continue
			if zone == "rio" and ((z > -30.0 and x > -64.0) or Vector2(x, z).distance_to(SUGARLOAF) < 16.0):
				continue
			if zone == "socal" and ((z > -30.0 and x > -64.0) or z > 16.0):
				continue
			var sc: float = scale_of[k] * _rng.randf_range(0.8, 1.25)
			lists[k].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(x, gy - 0.05, z)))
			n += 1
	var scrub := Color(0.4, 0.44, 0.22) if zone in ["texas", "sedona", "socal"] else (Color(0.2, 0.34, 0.16) if zone == "everglades" else Color(0, 0, 0, 0))
	for k in lists:
		_mm(k, lists[k], scrub if k.begins_with("bush") else Color(0, 0, 0, 0), k.begins_with("rock") or k == "log")
	# big rocks get collision
	for t in lists.rock_large:
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 1.1 * (t as Transform3D).basis.get_scale().x / 3.2
		cs.shape = sh
		cs.position = (t as Transform3D).origin + Vector3(0, 0.3, 0)
		_static.add_child(cs)

func _mk_cyl(rt: float, rb: float, h: float) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = 7
	m.rings = 1
	return m

func _mk_sphere(r: float, h: float) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 9
	m.rings = 5
	return m

func _mk_box(s: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = s
	return m

func _build_gate() -> void:
	var x := 80.0
	var gy := ground_y(x, 0)
	for z in [-8.5, 8.5]:
		_box(Vector3(0.8, 6, 0.8), Vector3(x, gy + 3, z), Color(0.4, 0.27, 0.15))
	_box(Vector3(0.8, 0.8, 18), Vector3(x, gy + 5.6, 0), Color(0.4, 0.27, 0.15), false)
	for i in 5:
		_box(Vector3(0.3, 0.3, 17), Vector3(x, gy + 0.6 + i * 0.9, 0), Color(0.55, 0.38, 0.22), false)
	_box(Vector3(1.0, 6, 17), Vector3(x, gy + 3, 0), Color(0, 0, 0), true).visible = false
	var sign_text := "PANTANAL  ·  Lv 11-20\nBus leaves here"
	var l := _label(sign_text, Vector3(x - 0.6, gy + 7.2, 0), 110, Color(1, 0.9, 0.6), -PI / 2)
	l.name = "GateSign"

func refresh_gate() -> void:
	var l := get_node_or_null("GateSign") as Label3D
	if l:
		l.text = "PANTANAL  ·  Lv 11-20\nBus leaves here"

func _build_pier() -> void:
	var z := 30.0
	var x0 := -56.0
	var x1 := river_x(z) + 3.0
	var gy := ground_y(x0, z)
	var length := absf(x0 - x1)
	_box(Vector3(length, 0.3, 3), Vector3((x0 + x1) / 2.0, maxf(gy, WATER_Y) + 0.3, z), Color(0.55, 0.4, 0.25))
	for k in int(length / 3.0):
		_cyl(0.15, 0.15, 3.0, Vector3(x0 - k * 3.0, WATER_Y - 0.6, z + 1.3), Color(0.35, 0.25, 0.15), 6)
		_cyl(0.15, 0.15, 3.0, Vector3(x0 - k * 3.0, WATER_Y - 0.6, z - 1.3), Color(0.35, 0.25, 0.15), 6)
	# a little boat
	var boat := _box(Vector3(5, 0.6, 1.8), Vector3(x1 - 2.0, WATER_Y + 0.1, z + 3.2), Color(0.2, 0.45, 0.7), false)
	boat.rotation.y = 0.2

func _build_nest_tree() -> void:
	var base := Vector3(-36, ground_y(-36, 52), 52)
	_cyl(0.6, 0.9, 11.0, base + Vector3(0, 5.5, 0), Color(0.42, 0.3, 0.2), 9, true)
	var crown := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.5
	sm.height = 3.0
	crown.mesh = sm
	crown.material_override = _mat(Color(0.2, 0.45, 0.2))
	crown.position = base + Vector3(0, 12.3, 0)
	add_child(crown)
	# spiral of rock steps around the trunk
	for i in 10:
		var a := i * 0.95
		var r := 2.2
		var y := 0.9 + i * 1.0
		_box(Vector3(1.8, 0.4, 1.8), base + Vector3(cos(a) * r, y, sin(a) * r), Color(0.55, 0.52, 0.48).darkened(0.03 * i))
	var top_y := 10.6
	_box(Vector3(3.2, 0.4, 3.2), base + Vector3(0, top_y, 0), Color(0.45, 0.32, 0.2))
	# nest + tuiuiú (jabiru stork): white body, black neck, red collar
	_cyl(1.0, 0.7, 0.4, base + Vector3(0.6, top_y + 0.4, 0), Color(0.5, 0.38, 0.22), 10)
	var body := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.45
	bsm.height = 0.7
	body.mesh = bsm
	body.material_override = _mat(Color(0.97, 0.97, 0.97))
	body.position = base + Vector3(0.6, top_y + 1.2, 0)
	add_child(body)
	_cyl(0.12, 0.14, 0.8, base + Vector3(0.6, top_y + 1.85, 0.1), Color(0.05, 0.05, 0.05), 6)
	_cyl(0.16, 0.16, 0.18, base + Vector3(0.6, top_y + 1.55, 0.05), Color(0.85, 0.1, 0.1), 8)
	var beak := _cyl(0.0, 0.07, 0.6, base + Vector3(0.6, top_y + 2.2, -0.3), Color(0.08, 0.08, 0.08), 6)
	beak.rotation.x = -1.3
	_nest_found_area = _area(base + Vector3(0, top_y + 1.0, 0), 2.6)
	_nest_found_area.body_entered.connect(func(b):
		if b is Player:
			if not Game.unlocked.has("nest"):
				Game.toast.emit("A tuiuiú! The bird of the Pantanal.", Color(1, 1, 1))
			Game.unlock("nest"))

func _build_capybaras() -> void:
	for p in [Vector3(-58, 0, 8), Vector3(-60, 0, 12), Vector3(-57, 0, -40)]:
		var gy := ground_y(p.x, p.z)
		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.3
		body.mesh = cm
		body.material_override = _mat(Color(0.5, 0.35, 0.22))
		body.rotation.z = PI / 2
		body.position = Vector3(p.x, gy + 0.45, p.z)
		add_child(body)
		_box(Vector3(0.45, 0.45, 0.5), Vector3(p.x + 0.75, gy + 0.62, p.z), Color(0.45, 0.31, 0.2), false)
		_label("capivara", Vector3(p.x, gy + 1.4, p.z), 36, Color(1, 1, 1, 0.8)).billboard = BaseMaterial3D.BILLBOARD_ENABLED

func _area(pos: Vector3, radius: float) -> Area3D:
	var a := Area3D.new()
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = radius
	cs.shape = sh
	a.add_child(cs)
	a.position = pos
	a.monitorable = false
	add_child(a)
	return a

func _build_cups() -> void:
	var list: Array = Data.COLLECTIBLES[zone]
	for i in list.size():
		var p: Vector3 = list[i]
		var y := ground_y(p.x, p.z) + 0.8
		var holder := Node3D.new()
		holder.position = Vector3(p.x, y, p.z)
		add_child(holder)
		var cup := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.28
		cm.bottom_radius = 0.2
		cm.height = 0.5
		cm.radial_segments = 10
		cup.mesh = cm
		cup.material_override = _mat(Color(0.15, 0.5, 0.25), 0.4)
		holder.add_child(cup)
		if zone == "chapada":
			var qm := PrismMesh.new()
			qm.size = Vector3(0.35, 0.8, 0.35)
			cup.mesh = qm
			cup.material_override = _mat(Color(0.85, 0.75, 1.0), 0.15)
		if zone == "texas":
			# rodeo buckle: a big shiny oval
			var bm := CylinderMesh.new()
			bm.top_radius = 0.34
			bm.bottom_radius = 0.34
			bm.height = 0.08
			cup.mesh = bm
			cup.rotation.x = PI / 2
			cup.scale = Vector3(1.3, 1, 1)
			cup.material_override = _mat(Color(0.85, 0.78, 0.6), 0.25)
		if zone == "everglades":
			var tmh := PrismMesh.new()
			tmh.size = Vector3(0.22, 0.7, 0.18)
			cup.mesh = tmh
			cup.material_override = _mat(Color(0.95, 0.92, 0.82), 0.4)
		if zone == "sedona":
			var qm2 := PrismMesh.new()
			qm2.size = Vector3(0.35, 0.8, 0.35)
			cup.mesh = qm2
			cup.material_override = _mat(Color(0.95, 0.55, 0.85), 0.15)
		if zone == "socal":
			# sand dollar: a flat pale disc
			var sdm := CylinderMesh.new()
			sdm.top_radius = 0.32
			sdm.bottom_radius = 0.32
			sdm.height = 0.06
			cup.mesh = sdm
			cup.rotation.x = 1.2
			cup.material_override = _mat(Color(0.95, 0.9, 0.78), 0.6)
		if zone == "rio":
			# green coconut with a straw
			cup.mesh = _mk_sphere(0.32, 0.6)
			cup.material_override = _mat(Color(0.35, 0.62, 0.2), 0.5)
		if zone == "pantanal":
			# arara feather instead of a cup
			var fm := PrismMesh.new()
			fm.size = Vector3(0.25, 1.0, 0.05)
			cup.mesh = fm
			cup.material_override = _mat([Color(0.9, 0.15, 0.12), Color(0.15, 0.4, 0.9), Color(0.95, 0.8, 0.1)][i % 3], 0.4)
		var straw := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.035
		sm.bottom_radius = 0.035
		sm.height = 0.7
		straw.mesh = sm
		straw.material_override = _mat(Color(0.85, 0.75, 0.4), 0.2)
		straw.position = Vector3(0.08, 0.35, 0)
		straw.rotation.z = -0.25
		holder.add_child(straw)
		straw.visible = zone == "caceres" or zone == "rio"
		# glow via emission instead of a light (lights are expensive on phones)
		var gm := (cup.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		gm.emission_enabled = true
		gm.emission = gm.albedo_color
		gm.emission_energy_multiplier = 0.9
		cup.material_override = gm
		var a := Area3D.new()
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 1.2
		cs.shape = sh
		a.add_child(cs)
		holder.add_child(a)
		a.body_entered.connect(_on_cup.bind(i))
		_cups[i] = holder
		if Game.collected(zone, i):
			holder.visible = false

func _on_cup(body: Node, i: int) -> void:
	if body is Player and game_started and _cups[i].visible:
		_cups[i].visible = false
		Game.collect_cup(i, zone)

# ---------------------------------------------------------------- quests
var quest_givers := {}  # giver id -> Npc
var _reach_nodes := {}  # "quest:objective" -> Node3D

func _build_quests() -> void:
	for g in Data.QUEST_GIVERS:
		var gd: Dictionary = Data.QUEST_GIVERS[g]
		if gd.zone != zone:
			continue
		var p: Vector3 = gd.pos
		var npc := Npc.new()
		add_child(npc)
		npc.setup_quest_giver(g, self)
		npc.position = Vector3(p.x, ground_y(p.x, p.z), p.z)
		npc.rig.rotation.y = PI
		quest_givers[g] = npc
		_spot(npc.position, 2.6, Tx.f("Talk to %s", gd.name), "quest", g)
	refresh_quests()

func refresh_quests() -> void:
	for g in quest_givers:
		quest_givers[g].refresh_marker()
	var want := {}
	for id in Game.active_quests(zone):
		var objs: Array = Data.QUESTS[id].obj
		for i in objs.size():
			if objs[i].type == "reach" and int(Game.objective_progress(id, i)[0]) < 1:
				want["%s:%d" % [id, i]] = objs[i]
	for key in _reach_nodes.keys():
		if not want.has(key):
			_reach_nodes[key].queue_free()
			_reach_nodes.erase(key)
	for key in want:
		if _reach_nodes.has(key):
			continue
		var o: Dictionary = want[key]
		var p: Vector3 = o.pos
		var holder := Node3D.new()
		holder.position = Vector3(p.x, ground_y(p.x, p.z), p.z)
		add_child(holder)
		var ring := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = float(o.radius) * 0.6
		cm.bottom_radius = float(o.radius) * 0.6
		cm.height = 6.0
		cm.cap_top = false
		cm.cap_bottom = false
		cm.radial_segments = 20
		ring.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 0.85, 0.2, 0.22)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring.material_override = m
		ring.position.y = 3.0
		holder.add_child(ring)
		var l := Label3D.new()
		l.text = o.text
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.font_size = 48
		l.pixel_size = 0.009
		l.outline_size = 12
		l.modulate = Color(1, 0.9, 0.4)
		l.position.y = 3.2
		holder.add_child(l)
		var a := Area3D.new()
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = float(o.radius)
		cs.shape = sh
		cs.position.y = 1.0
		a.add_child(cs)
		holder.add_child(a)
		var k: String = key
		a.body_entered.connect(func(b):
			if b is Player and game_started:
				Game.quest_event("reach", k))
		_reach_nodes[key] = holder

func _build_landmarks() -> void:
	_build_quests()
	for id in Data.landmarks_in(zone):
		var lm: Dictionary = Data.LANDMARKS[id]
		var p: Vector3 = lm.pos
		var a := _area(Vector3(p.x, ground_y(p.x, p.z) + 1.0, p.z), lm.radius)
		a.body_entered.connect(func(b):
			if b is Player and game_started and Game.discover_landmark(id):
				landmark_entered.emit(id))

func _build_fighters() -> void:
	for id in Data.OPPONENTS:
		if Data.zone_of(id) != zone:
			continue
		var o: Dictionary = Data.OPPONENTS[id]
		var p: Vector3 = o.pos
		var npc := Npc.new()
		add_child(npc)
		npc.setup_fighter(id, self)
		var y := ground_y(p.x, p.z)
		if id == "onca":
			y = ground_y(0, -54) + 0.38
		elif id == "rafa":
			y = ground_y(0, 8) + 0.15
		elif id == "jacare":
			y = ground_y(64, 58) + 0.4
		elif id == "cachoeira":
			y = ground_y(40, 56) + 0.38
		elif id == "leao":
			y = ground_y(RIO_GYM.x, RIO_GYM.z) + 0.38
		elif id == "dale":
			y = ground_y(SOCAL_GYM.x, SOCAL_GYM.z) + 0.38
		elif id in ["boone", "gator", "sol"]:
			y = ground_y(p.x, p.z) + 0.38
		npc.position = Vector3(p.x, y, p.z)
		npc.rig.rotation.y = PI
		fighters[id] = npc

func _build_villagers() -> void:
	var where := [Vector3(0, 0, 8), Vector3(30, 0, -22), Vector3(-20, 0, -4), Vector3(40, 0, -4), Vector3(0, 0, 8), Vector3(-45, 0, 10), Vector3(12, 0, -30)]
	if zone == "pantanal":
		where = [Vector3(-75, 0, -4), Vector3(-40, 0, 26), Vector3(56, 0, 50), Vector3(38, 0, -30)]
	elif zone == "chapada":
		where = [Vector3(42, 0, 40), Vector3(36, 0, 36), Vector3(-74, 0, 40), Vector3(20, 0, 10)]
	elif zone == "texas":
		where = [Vector3(0, 0, 8), Vector3(20, 0, -10), Vector3(-20, 0, -4), Vector3(40, 0, -4), Vector3(4, 0, 10), Vector3(-30, 0, 28), Vector3(50, 0, 30)]
	elif zone == "everglades":
		where = [Vector3(-75, 0, -4), Vector3(-40, 0, 26), Vector3(56, 0, 46), Vector3(36, 0, -30), Vector3(-18, 0, -40)]
	elif zone == "sedona":
		where = [Vector3(42, 0, 40), Vector3(36, 0, 36), Vector3(-74, 0, 40), Vector3(20, 0, 12), Vector3(50, 0, 44)]
	elif zone == "socal":
		where = [Vector3(-20, 0, 40), Vector3(10, 0, 28), Vector3(60, 0, 44), Vector3(-40, 0, 28), Vector3(30, 0, -8), Vector3(-76, 0, 10), Vector3(48, 0, 60)]
	elif zone == "rio":
		where = [Vector3(0, 0, 40), Vector3(-50, 0, 44), Vector3(40, 0, 44), Vector3(-10, 0, 28), Vector3(30, 0, 27), Vector3(36, 0, -36), Vector3(-80, 0, 10)]
	for i in where.size():
		var v := Npc.new()
		add_child(v)
		v.setup_villager(100 + i, self, where[i])
		var s: Vector3 = where[i]
		v.position = Vector3(s.x + i, ground_y(s.x + i, s.z), s.z)

func _build_bounds() -> void:
	for d in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(2 if d.x != 0 else 210, 80, 2 if d.z != 0 else 210)
		cs.shape = sh
		cs.position = d * 97.0 + Vector3(0, 30, 0)
		_static.add_child(cs)

func _build_beacon() -> void:
	beacon = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.35
	cm.height = 40
	cm.radial_segments = 10
	beacon.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 0.8, 0.25, 0.28)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	beacon.material_override = m
	add_child(beacon)
	refresh_beacon()

func _nearest_unbeaten(z: String) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for id in Data.OPPONENTS:
		if Data.zone_of(id) != z or Data.OPPONENTS[id].get("boss", false) or Game.beaten(id):
			continue
		var p: Vector3 = Data.OPPONENTS[id].pos
		var d := p.distance_to(player.global_position) if player else p.length()
		if d < bd:
			bd = d
			best = p
	return best

func objective_target() -> Vector3:
	if zone in ["texas", "everglades", "sedona"]:
		var bid: String = Data.ZONES[zone].boss
		if Game.beaten(bid):
			var road: Array = Origins.FACTIONS.usa.path
			var bus: Vector3 = {"texas": Vector3(80, 0, 0), "everglades": Vector3(-82, 0, -4), "sedona": Vector3(-80, 0, 40)}[zone]
			return bus if road.find(zone) < 3 else Data.OPPONENTS[bid].pos
		if Game.town_wins(zone) < Data.BOSS_REQUIRED_WINS:
			var tu := _nearest_unbeaten(zone)
			if tu != Vector3.INF:
				return tu
		return Data.OPPONENTS[bid].pos
	if zone == "socal":
		if Game.town_wins("socal") < Data.BOSS_REQUIRED_WINS:
			var ts := _nearest_unbeaten("socal")
			if ts != Vector3.INF:
				return ts
		return Data.OPPONENTS.dale.pos
	if zone == "rio":
		if Game.rank >= 20:
			return Data.OPPONENTS.leao.pos
		if Game.town_wins("rio") < Data.BOSS_REQUIRED_WINS:
			var t := _nearest_unbeaten("rio")
			if t != Vector3.INF:
				return t
		return Data.OPPONENTS.leao.pos
	if zone == "chapada":
		if Game.rank >= 15:
			return Data.ZONES.chapada.spawn
		if Game.town_wins("chapada") < Data.BOSS_REQUIRED_WINS:
			var bc := Vector3.ZERO
			var bdc := INF
			for id in Data.OPPONENTS:
				if Data.zone_of(id) != "chapada" or Data.OPPONENTS[id].get("boss", false) or Game.beaten(id):
					continue
				var pc: Vector3 = Data.OPPONENTS[id].pos
				var dc := pc.distance_to(player.global_position) if player else pc.length()
				if dc < bdc:
					bdc = dc
					bc = pc
			if bdc < INF:
				return bc
		return Data.OPPONENTS.cachoeira.pos
	if zone == "pantanal":
		if Game.rank >= 10:
			return Data.ZONES.pantanal.spawn  # the bus to the Chapada
		var best_p := Vector3.ZERO
		var bdp := INF
		if Game.town_wins("pantanal") < Data.BOSS_REQUIRED_WINS:
			for id in Data.OPPONENTS:
				if Data.zone_of(id) != "pantanal" or Data.OPPONENTS[id].get("boss", false) or Game.beaten(id):
					continue
				var p2: Vector3 = Data.OPPONENTS[id].pos
				var d2 := p2.distance_to(player.global_position) if player else p2.length()
				if d2 < bdp:
					bdp = d2
					best_p = p2
		if bdp < INF:
			return best_p
		return Data.OPPONENTS.jacare.pos
	if Game.rank >= 5:
		return Vector3(76, 0, 0)
	if not Game.beaten("rafa") and not Game.flags.get("met_professor", false):
		return Data.OPPONENTS.rafa.pos
	if not Game.flags.get("met_professor", false):
		return Data.OPPONENTS.onca.pos
	if Game.town_wins() < Data.BOSS_REQUIRED_WINS:
		var best := Vector3.ZERO
		var bd := INF
		for id in Data.OPPONENTS:
			if id == "onca" or Game.beaten(id) or Data.zone_of(id) != "caceres":
				continue
			var p: Vector3 = Data.OPPONENTS[id].pos
			var d := p.distance_to(player.global_position) if player else p.length()
			if d < bd:
				bd = d
				best = p
		if bd < INF:
			return best
	return Data.OPPONENTS.onca.pos

func refresh_beacon() -> void:
	var t := objective_target()
	beacon.position = Vector3(t.x, ground_y(t.x, t.z) + 20.0, t.z)
	for id in fighters:
		fighters[id].refresh_tag()
	refresh_quests()
	refresh_gate()

func attach_player(p: Player) -> void:
	if wildlife == null:
		wildlife = Wildlife.new()
		add_child(wildlife)
		wildlife.setup(zone, p)
	player = p
	for id in fighters:
		fighters[id].set_player(p)
	for e in mobs:
		if e.npc:
			(e.npc as Npc).set_player(p)
	aggro_grace = 4.0

func _process(_delta: float) -> void:
	if _falls_mat:
		_falls_mat.uv1_offset.y -= _delta * 1.2
	if player == null:
		return
	for i in _cups:
		var h: Node3D = _cups[i]
		if h.visible:
			h.rotation.y += _delta * 2.0
	var best: Npc = null
	var bd := 3.4
	for id in fighters:
		var n: Npc = fighters[id]
		var d := n.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = n
	aggro_grace = maxf(0.0, aggro_grace - _delta)
	for e in mobs:
		if e.npc == null:
			e.t = float(e.t) - _delta
			if float(e.t) <= 0.0:
				_spawn_mob(e)
			continue
		var mn: Npc = e.npc
		if not mn.visible:
			continue
		var md := mn.global_position.distance_to(player.global_position)
		if md < bd:
			bd = md
			best = mn
	if best != nearby:
		nearby = best
		nearby_changed.emit(nearby)
	var bs: Dictionary = {}
	if best == null:
		var sd := INF
		for sp in spots:
			var dd: float = Vector2(sp.pos.x - player.global_position.x, sp.pos.z - player.global_position.z).length()
			if dd < float(sp.radius) and dd < sd:
				sd = dd
				bs = sp
	if bs != nearby_spot:
		nearby_spot = bs
		spot_changed.emit(bs)
	# deep water: the player swims (Player handles it); a heads-up the first time
	if player.swimming and not Game.flags.get("swam", false):
		Game.flags["swam"] = true
		Game.toast.emit("Swimming. Watch for piranhas: head back to the bank whenever you like.", Color(0.6, 0.85, 1))


# ================================================================ interactable spots
func _spot(pos: Vector3, radius: float, label: String, action: String, arg := "") -> void:
	spots.append({"pos": pos, "radius": radius, "label": label, "action": action, "arg": arg})

const DRILL_COLORS := {"strength": Color(0.85, 0.3, 0.25), "grip": Color(0.75, 0.6, 0.35), "cardio": Color(0.3, 0.7, 0.9), "flexibility": Color(0.4, 0.8, 0.45), "iq": Color(0.95, 0.8, 0.3)}

func _drill_station(k: String, pos: Vector3) -> void:
	var gy := ground_y(pos.x, pos.z)
	var base := Vector3(pos.x, gy + 0.35, pos.z)
	var c: Color = DRILL_COLORS[k]
	match k:
		"strength":
			var kb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.28
			sm.height = 0.56
			kb.mesh = sm
			kb.material_override = _mat(Color(0.15, 0.15, 0.15), 0.4)
			kb.position = base + Vector3(0, 0.3, 0)
			add_child(kb)
		"grip":
			_cyl(0.05, 0.05, 4.6, base + Vector3(0, 2.3, 0), Color(0.8, 0.7, 0.45), 6)
			_box(Vector3(1.4, 0.15, 0.15), base + Vector3(0, 4.6, 0), Color(0.3, 0.3, 0.3), false)
		"cardio":
			_box(Vector3(1.2, 0.1, 2.6), base + Vector3(0, 0.05, 0), Color(0.2, 0.2, 0.22), false)
		"flexibility":
			_box(Vector3(0.9, 0.06, 2.0), base + Vector3(0, 0.03, 0), c.darkened(0.3), false)
		"iq":
			var dummy := BodyRig.new()
			add_child(dummy)
			dummy.setup(Color(0.35, 0.25, 0.18), Color(0.2, 0.15, 0.1), Color(0.35, 0.25, 0.18), Color(0.35, 0.25, 0.18))
			dummy.position = base - Vector3(0, 0.35, 0)
			dummy.apply_pose({"hip_h": 0.2, "l_hip": Vector3(1.5, 0, -0.2), "r_hip": Vector3(1.5, 0, 0.2), "l_sh": Vector3(0.3, 0, 0.2), "r_sh": Vector3(0.3, 0, -0.2)})
	var l := _label(Rpg.DRILLS[k].name + "\n" + Rpg.ATTRS[k].name, base + Vector3(0, 2.1, 0), 40, c)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.0055
	_spot(base, 1.9, Tx.f("Drill: %s (%s)", [Rpg.DRILLS[k].name, Rpg.ATTRS[k].name]), "drill", k)

## Barbearia do Seu Zé: a little open-air barbershop (pole, chair, mirror, Seu Zé). Talking to him
## opens the Barber screen to restyle your fighter.
func _barbershop(p: Vector3) -> void:
	var gy := ground_y(p.x, p.z)
	var b := Vector3(p.x, gy, p.z)
	_box(Vector3(4.2, 0.14, 3.4), b + Vector3(0, 0.07, 0), Color(0.82, 0.8, 0.76), false)
	# back wall with mirror and awning
	_box(Vector3(4.2, 2.8, 0.25), b + Vector3(0, 1.4, -1.6), Color(0.3, 0.55, 0.62))
	_box(Vector3(1.4, 1.0, 0.06), b + Vector3(0, 1.6, -1.45), Color(0.75, 0.85, 0.9), false)
	var awn := _box(Vector3(4.6, 0.12, 1.8), b + Vector3(0, 2.9, -0.8), Color(0.85, 0.2, 0.2), false)
	awn.rotation.x = 0.2
	# barber chair
	_box(Vector3(0.7, 0.45, 0.7), b + Vector3(0, 0.45, -0.3), Color(0.55, 0.12, 0.12))
	_box(Vector3(0.7, 0.8, 0.12), b + Vector3(0, 0.95, -0.62), Color(0.55, 0.12, 0.12))
	_cyl(0.08, 0.12, 0.25, b + Vector3(0, 0.12, -0.3), Color(0.7, 0.7, 0.72), 10)
	# striped pole
	for i in 6:
		_cyl(0.11, 0.11, 0.3, b + Vector3(2.4, 0.35 + i * 0.3, -1.3), [Color(0.85, 0.15, 0.15), Color(0.95, 0.95, 0.95), Color(0.15, 0.3, 0.8)][i % 3], 10)
	_cyl(0.14, 0.14, 0.12, b + Vector3(2.4, 2.2, -1.3), Color(0.75, 0.75, 0.78), 10)
	# Seu Zé, scissors in hand (idle)
	var ze := BodyRig.new()
	add_child(ze)
	ze.setup(Color(0.95, 0.95, 0.93), Color(0.2, 0.2, 0.22), UiKit.skin_tone(0.6), Color(0.85, 0.85, 0.85), -1, "", true)
	ze.position = b + Vector3(-1.0, 0.14, 0.2)
	ze.rotation.y = 0.5
	var l := _label("Seu Zé\n<Barber>", b + Vector3(-1.0, 2.55, 0.2), 40, Color(1, 0.9, 0.6))
	l.no_depth_test = true
	l.outline_size = 8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0007
	l.font_size = 30
	l.visibility_range_end = 26.0
	_label("BARBEARIA", b + Vector3(0, 3.3, -1.4), 48, Color(1, 0.95, 0.8))
	_spot(b + Vector3(-0.6, 0, 1.2), 3.5, "Barber: Seu Zé (change your look)", "barber")

## A mat with two locals rolling on it (ambience).
func _ambient_mat(p: Vector3, yaw: float) -> void:
	var b := Vector3(p.x, ground_y(p.x, p.z), p.z)
	var mat := _box(Vector3(3.2, 0.08, 3.2), b + Vector3(0, 0.04, 0), Color(0.15, 0.35, 0.6), false)
	mat.rotation.y = yaw
	var gis := [Color(0.95, 0.95, 0.95), Color(0.15, 0.3, 0.75), Color(0.1, 0.1, 0.12)]
	var belts := [Color(0.95, 0.95, 0.95), Color(0.15, 0.35, 0.85), Color(0.45, 0.2, 0.65)]
	var r := AmbientRoll.new()
	add_child(r)
	r.position = b + Vector3(0, 0.08, 0)
	r.rotation.y = yaw
	r.setup(gis[_rng.randi() % 3], gis[_rng.randi() % 3], _rng.randf(), _rng.randf(), belts[_rng.randi() % 3], belts[_rng.randi() % 3])

## A bico: the person who needs a hand, with a "?" over them while the job is open today.
func _job_spot(p: Vector3, j: Dictionary) -> void:
	var b := Vector3(p.x, ground_y(p.x, p.z), p.z)
	var who := BodyRig.new()
	add_child(who)
	var fem: bool = str(j.who).begins_with("Dona")
	who.setup(Color(0.85, 0.75, 0.55) if not fem else Color(0.9, 0.5, 0.6), Color(0.3, 0.25, 0.2), UiKit.skin_tone(_rng.randf_range(0.3, 0.8)), Color(0.15, 0.1, 0.06), -1, "female" if fem else "", true)
	who.position = b
	who.rotation.y = _rng.randf() * TAU
	var l := _label(Tx.f("%s\n<Needs a hand>", str(j.who)), b + Vector3(0, 2.3, 0), 30, Color(1, 0.9, 0.55))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0007
	l.no_depth_test = true
	l.visibility_range_end = 26.0
	_spot(b + Vector3(0, 0, 1.2), 3.0, Tx.f("Bico: %s (%s)", [str(j.name), str(j.who)]), "job", str(j.id))

## Covil da Sucuri: the raid entrance (a green-and-black banner on two posts and a mat).
func _raid_gate(p: Vector3, title := "COVIL DA SUCURI", spot := "Raid: Covil da Sucuri (you + 4 partners)", col := Color(0.6, 1.0, 0.55)) -> void:
	var b := Vector3(p.x, ground_y(p.x, p.z), p.z)
	_box(Vector3(5.0, 0.1, 4.0), b + Vector3(0, 0.05, 0), Color(0.18, 0.32, 0.2), false)
	for x in [-2.2, 2.2]:
		_cyl(0.09, 0.09, 3.2, b + Vector3(x, 1.6, -1.8), Color(0.25, 0.2, 0.15), 8)
	_box(Vector3(4.6, 1.0, 0.08), b + Vector3(0, 2.7, -1.8), Color(0.08, 0.2, 0.1), false)
	_label(title, b + Vector3(0, 2.75, -1.7), 44, col)
	var l := _label("Raid  ·  5 fighters", b + Vector3(0, 2.05, -1.7), 28, Color(1, 0.9, 0.6))
	l.no_depth_test = false
	_spot(b + Vector3(0, 0, 0.5), 3.5, spot, "raid")

func _build_caceres_spots() -> void:
	_spot(Vector3(74, 0, 0), 6.0, "Take the bus", "travel_menu")
	var c := Vector3(0, 0, -54)
	var xs := [-7.0, -3.5, 0.0, 3.5, 7.0]
	for i in Rpg.ATTR_ORDER.size():
		_drill_station(Rpg.ATTR_ORDER[i], c + Vector3(xs[i], 0, -5.2))
	_challenge_board(Vector3(12, 0, -44))
	_comp_board(Vector3(-12, 0, -44), "copa_caceres")

# ================================================================ zone 2: Pantanal
func _height_pantanal(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 1.0 + 0.15
	var n2 := noise.get_noise_2d(x * 0.6 + 300.0, z * 0.6 - 120.0)
	h = lerpf(h, -0.8, _ss(-0.22, -0.38, n2))
	for lg in [[Vector2(10, 20), 13.0], [Vector2(42, -52), 12.0]]:
		var dd: float = Vector2(x, z).distance_to(lg[0])
		h = lerpf(h, -0.85, _ss(lg[1], lg[1] - 5.0, dd))
	for fl in [[Vector2(64, 58), 16.0], [Vector2(-40, 26), 15.0], [Vector2(-18, -48), 9.0], [Vector2(-82, -4), 11.0], [Vector2(72, 68), 8.0]]:
		var df: float = Vector2(x, z).distance_to(fl[0])
		h = lerpf(h, 0.2, _ss(fl[1], fl[1] - 4.0, df))
	h = lerpf(h, 0.12, _ss(5.0, 3.0, absf(z + 4.0)))
	var e := maxf(absf(x), absf(z))
	h += _ss(82.0, 98.0, e) * 10.0
	return h

func _build_pantanal() -> void:
	noise.seed = 31
	noise.frequency = 0.025
	_rng.seed = 2027
	_static = StaticBody3D.new()
	add_child(_static)
	_blocked = [
		Rect2(-92, -14, 22, 20),   # bus stop
		Rect2(48, 42, 34, 34),     # fazenda
		Rect2(-56, 10, 32, 32),    # ranch
		Rect2(-28, -58, 20, 20),   # tower
		Rect2(30, -64, 24, 30),    # dock + lagoon 2
		Rect2(-6, 4, 32, 34),      # lagoon 1
		Rect2(-70, -70, 12, 12),   # jaguar tree
	]
	_build_environment()
	_build_terrain()
	var water := MeshInstance3D.new()
	water.mesh = EnvShaders.water_plane(Vector2(200, 200), 4.0)
	# Pantanal wetland: still, tea-colored, mirror-like
	water.material_override = EnvShaders.water(Color(0.08, 0.14, 0.09), Color(0.22, 0.28, 0.16, 0.88), 0.025, 0.25)
	water.position = Vector3(0, -0.35, 0)
	add_child(water)
	_build_trees()
	_build_ground_detail()
	_build_props()
	for p in [Vector3(-34, 0, 34), Vector3(-46, 0, 18)]:
		_animal("deer", Vector3(p.x, ground_y(p.x, p.z), p.z), 1.6, _rng.randf() * TAU)
	_animal("fox", Vector3(70, ground_y(70, -20), -20), 0.9, 1.0)
	for p in [Vector3(-2, 0, 10), Vector3(22, 0, 30), Vector3(30, 0, -46)]:
		_animal("frog", Vector3(p.x, maxf(ground_y(p.x, p.z), -0.3), p.z), 0.25, _rng.randf() * TAU)
	_place_model("tent", Vector3(-58, ground_y(-58, 10), 10), 4.0, 0.9, Vector3(3.0, 2.2, 2.6))
	_place_model("campfire", Vector3(-55, ground_y(-55, 13), 13), 3.0)
	_animal("shiba", Vector3(-40, ground_y(-40, 30), 30), 0.9, 0.3)
	_p_bus_stop()
	_p_fazenda()
	_p_ranch()
	_p_tower()
	_p_dock()
	_p_lagoon_bridge()
	_p_marsh()
	_p_wildlife()
	_build_cups()
	_build_landmarks()
	_build_fighters()
	_build_villagers()
	_build_bounds()
	_build_beacon()

func _p_bus_stop(at := Vector3(-82, 0, -4), title := "TRANSPANTANEIRA") -> void:
	var c := Vector3(at.x, ground_y(at.x, at.z), at.z)
	_box(Vector3(4, 0.2, 2.4), c + Vector3(0, 2.6, -2.5), Color(0.25, 0.4, 0.3), false)
	for x in [-1.8, 1.8]:
		_box(Vector3(0.15, 2.6, 0.15), c + Vector3(x, 1.3, -3.5), Color(0.3, 0.3, 0.3))
	_box(Vector3(3, 0.4, 0.6), c + Vector3(0, 0.4, -3.3), Color(0.5, 0.35, 0.2))
	var bus := _box(Vector3(2.6, 2.8, 8.0), c + Vector3(-4.5, 1.6, 0), Color(0.95, 0.75, 0.15))
	for i in 4:
		_box(Vector3(0.05, 0.9, 1.4), c + Vector3(-3.17, 2.2, -2.7 + i * 1.8), Color(0.2, 0.3, 0.4), false)
	_label(title, c + Vector3(0, 3.6, -2.5), 70, Color(1, 0.9, 0.6))
	_spot(c, 6.0, "Take the bus", "travel_menu")

func _p_fazenda() -> void:
	var c := Vector3(64, ground_y(64, 58), 58)
	# open-air mat pavilion with a thatched roof
	for x in [-6.0, 6.0]:
		for z in [-5.0, 5.0]:
			_box(Vector3(0.4, 4.0, 0.4), c + Vector3(x, 2.0, z), Color(0.4, 0.28, 0.18))
	var roof := MeshInstance3D.new()
	var rm := PrismMesh.new()
	rm.size = Vector3(14, 2.2, 12)
	roof.mesh = rm
	roof.material_override = _mat(Color(0.72, 0.6, 0.35))
	roof.position = c + Vector3(0, 5.1, 0)
	add_child(roof)
	for x in 6:
		for z in 5:
			var col := Color(0.13, 0.38, 0.26) if (x + z) % 2 == 0 else Color(0.78, 0.62, 0.22)
			_box(Vector3(1.96, 0.1, 1.96), c + Vector3(-5 + x * 2, 0.25, -4 + z * 2), col, false)
	_label("FAZENDA JACARÉ", c + Vector3(0, 6.6, 6.2), 120, Color(0.98, 0.82, 0.3))
	# ranch house
	var h := Vector3(74, ground_y(74, 70), 70)
	_box(Vector3(10, 3.6, 7), h + Vector3(0, 1.8, 0), Color(0.97, 0.95, 0.9))
	var hr := MeshInstance3D.new()
	var hpm := PrismMesh.new()
	hpm.size = Vector3(11, 1.8, 8)
	hr.mesh = hpm
	hr.material_override = _mat(Color(0.72, 0.33, 0.2))
	hr.position = h + Vector3(0, 4.5, 0)
	add_child(hr)
	_box(Vector3(1.2, 2.2, 0.1), h + Vector3(0, 1.1, -3.55), Color(0.35, 0.22, 0.12), false)
	# drill stations along the pavilion's west side
	var zs := [-7.0, -3.5, 0.0, 3.5, 7.0]
	for i in Rpg.ATTR_ORDER.size():
		_drill_station(Rpg.ATTR_ORDER[i], c + Vector3(-9.0, 0, zs[i]))
	_challenge_board(c + Vector3(0, 0, -9.0))
	_comp_board(c + Vector3(4.0, 0, -9.0), "pantanal_open")

func _p_ranch() -> void:
	var c := Vector3(-40, ground_y(-40, 26), 26)
	for i in 28:
		var a := i * TAU / 28.0
		if a > 4.4 and a < 5.2:
			continue  # opening
		var p := c + Vector3(cos(a) * 11.0, 0, sin(a) * 11.0)
		_box(Vector3(0.2, 1.3, 0.2), p + Vector3(0, 0.65, 0), Color(0.45, 0.32, 0.2), false)
		var nxt := c + Vector3(cos(a + TAU / 28.0) * 11.0, 0, sin(a + TAU / 28.0) * 11.0)
		var rail := _box(Vector3(0.12, 0.12, p.distance_to(nxt)), (p + nxt) / 2.0 + Vector3(0, 1.0, 0), Color(0.55, 0.4, 0.25), false)
		rail.look_at(nxt + Vector3(0, 1.0, 0), Vector3.UP)
	for i in 5:
		var cp := c + Vector3(_rng.randf_range(-7, 7), 0, _rng.randf_range(-7, 7))
		var cow := _box(Vector3(0.8, 0.8, 1.8), cp + Vector3(0, 0.9, 0), Color(0.95, 0.93, 0.88), false, _rng.randf() * TAU)
		var head := _box(Vector3(0.45, 0.45, 0.5), Vector3(0, 0.25, -1.05), Color(0.9, 0.88, 0.82), false)
		remove_child(head)
		cow.add_child(head)
		head.position = Vector3(0, 0.25, -1.05)
		for k in 4:
			var leg := _box(Vector3(0.15, 0.6, 0.15), Vector3(0.28 * (1 if k % 2 == 0 else -1), -0.6, 0.6 * (1 if k < 2 else -1)), Color(0.85, 0.83, 0.78), false)
			remove_child(leg)
			cow.add_child(leg)
			leg.position = Vector3(0.28 * (1 if k % 2 == 0 else -1), -0.6, 0.6 * (1 if k < 2 else -1))

func _p_tower() -> void:
	var c := Vector3(-18, ground_y(-18, -50), -50)
	for x in [-1.5, 1.5]:
		for z in [-1.5, 1.5]:
			_box(Vector3(0.3, 13, 0.3), c + Vector3(x, 6.5, z), Color(0.42, 0.3, 0.2))
	for i in 12:
		var a := i * 0.9
		_box(Vector3(1.6, 0.25, 1.6), c + Vector3(cos(a) * 3.0, 0.9 + i * 1.0, sin(a) * 3.0), Color(0.55, 0.4, 0.25))
	_box(Vector3(4.4, 0.3, 4.4), c + Vector3(0, 12.9, 0), Color(0.5, 0.36, 0.22))
	_label("RANGER TOWER", c + Vector3(0, 14.6, 0), 60, Color(1, 0.95, 0.8)).billboard = BaseMaterial3D.BILLBOARD_ENABLED

func _p_dock() -> void:
	var c := Vector3(38, ground_y(38, -38), -38)
	_box(Vector3(3, 0.25, 14), Vector3(40, 0.15, -46), Color(0.55, 0.4, 0.25))
	for k in 5:
		_cyl(0.12, 0.12, 2.0, Vector3(38.6, -0.6, -40 - k * 3.0), Color(0.35, 0.25, 0.15), 6)
		_cyl(0.12, 0.12, 2.0, Vector3(41.4, -0.6, -40 - k * 3.0), Color(0.35, 0.25, 0.15), 6)
	var boat := _box(Vector3(1.6, 0.5, 4.6), Vector3(43.5, -0.25, -50), Color(0.25, 0.5, 0.35), false)
	boat.rotation.y = 0.15

## Reeds along the water's edge and water lilies on the open water.
func _p_marsh() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var reed := PrismMesh.new()
	reed.size = Vector3(0.07, 1.5, 0.02)
	var head := CylinderMesh.new()
	head.top_radius = 0.045
	head.bottom_radius = 0.045
	head.height = 0.28
	head.radial_segments = 5
	head.rings = 1
	var pad := CylinderMesh.new()
	pad.top_radius = 0.42
	pad.bottom_radius = 0.42
	pad.height = 0.02
	pad.radial_segments = 9
	pad.rings = 1
	var bloom := SphereMesh.new()
	bloom.radius = 0.11
	bloom.height = 0.16
	bloom.radial_segments = 6
	bloom.rings = 3
	var reeds: Array = []
	var heads: Array = []
	var pads: Array = []
	var blooms: Array = []
	var tries := 0
	while tries < 9000 and (reeds.size() < 900 or pads.size() < 260):
		tries += 1
		var x := rng.randf_range(-90, 90)
		var z := rng.randf_range(-90, 90)
		if absf(z + 4.0) < 4.0:   # keep the Transpantaneira road clear
			continue
		var h := ground_y(x, z)
		if h > -0.45 and h < 0.15 and reeds.size() < 900:
			# a clump at the waterline
			for k in rng.randi_range(4, 9):
				var p := Vector3(x + rng.randf_range(-0.7, 0.7), 0, z + rng.randf_range(-0.7, 0.7))
				var s := rng.randf_range(0.7, 1.25)
				var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12))
				var y := maxf(ground_y(p.x, p.z), -0.35)
				reeds.append(Transform3D(b.scaled(Vector3.ONE * s), Vector3(p.x, y + 0.75 * s, p.z)))
				if rng.randf() < 0.35:
					heads.append(Transform3D(b, Vector3(p.x, y + 1.35 * s, p.z)))
		elif h < -0.7 and pads.size() < 260:
			var py := -0.33
			pads.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.6, 1.3)), Vector3(x, py, z)))
			if rng.randf() < 0.18:
				blooms.append(Transform3D(Basis(), Vector3(x + 0.1, py + 0.07, z)))
	for set in [[reeds, reed, EnvShaders.grass(Color(0.45, 0.55, 0.24), 1.4)], [heads, head, _mat(Color(0.35, 0.22, 0.12))],
			[pads, pad, _mat(Color(0.22, 0.45, 0.2))], [blooms, bloom, _mat(Color(0.98, 0.6, 0.8))]]:
		var list: Array = set[0]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = set[1]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = set[2]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 90.0
		add_child(mmi)

func _p_lagoon_bridge() -> void:
	# boardwalk across Lagoa dos Jacarés
	_box(Vector3(2.4, 0.25, 34), Vector3(10, 0.25, 20), Color(0.58, 0.43, 0.27))
	for k in 12:
		_cyl(0.12, 0.12, 1.6, Vector3(8.9, -0.5, 4 + k * 3.0), Color(0.35, 0.25, 0.15), 6)
		_cyl(0.12, 0.12, 1.6, Vector3(11.1, -0.5, 4 + k * 3.0), Color(0.35, 0.25, 0.15), 6)

func _p_wildlife() -> void:
	# jacarés (caimans) sunbathing on the lagoon edges
	for p in [Vector3(1, 0, 14), Vector3(19, 0, 27), Vector3(4, 0, 30), Vector3(33, 0, -55), Vector3(50, 0, -48)]:
		var gy := maxf(ground_y(p.x, p.z), -0.4)
		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.28
		cm.height = 2.2
		body.mesh = cm
		body.material_override = _mat(Color(0.2, 0.25, 0.15))
		body.rotation = Vector3(PI / 2, _rng.randf() * TAU, 0)
		body.position = Vector3(p.x, gy + 0.05, p.z)
		body.scale = Vector3(1, 1, 0.55)
		add_child(body)
		var lab := _label("jacaré", Vector3(p.x, gy + 1.0, p.z), 36, Color(1, 1, 1, 0.8))
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# capybaras near the water
	for p in [Vector3(-4, 0, 6), Vector3(-2, 0, 8), Vector3(24, 0, 12), Vector3(30, 0, -40)]:
		var gy2 := ground_y(p.x, p.z)
		var cap := MeshInstance3D.new()
		var ccm := CapsuleMesh.new()
		ccm.radius = 0.4
		ccm.height = 1.3
		cap.mesh = ccm
		cap.material_override = _mat(Color(0.5, 0.35, 0.22))
		cap.rotation.z = PI / 2
		cap.position = Vector3(p.x, gy2 + 0.45, p.z)
		add_child(cap)
	# araras (macaws) perched on poles
	for i in 8:
		var x := _rng.randf_range(-80, 80)
		var z := _rng.randf_range(-80, 80)
		if _is_blocked(x, z, 2.0) or ground_y(x, z) < 0.0:
			continue
		var gy3 := ground_y(x, z)
		_cyl(0.08, 0.1, 5.0, Vector3(x, gy3 + 2.5, z), Color(0.4, 0.3, 0.2), 6)
		var bird := _box(Vector3(0.3, 0.55, 0.3), Vector3(x, gy3 + 5.3, z), [Color(0.9, 0.15, 0.12), Color(0.15, 0.4, 0.9)][i % 2], false)
		_box(Vector3(0.12, 0.6, 0.08), Vector3(x, gy3 + 4.8, z + 0.15), Color(0.95, 0.8, 0.1), false)
	# the onça pintada (jaguar), lounging on a branch
	var t := Vector3(-64, ground_y(-64, -64), -64)
	_cyl(0.5, 0.8, 7.0, t + Vector3(0, 3.5, 0), Color(0.42, 0.3, 0.2), 8, true)
	var branch := _box(Vector3(4.5, 0.4, 0.5), t + Vector3(1.8, 4.2, 0), Color(0.42, 0.3, 0.2), false)
	var crown := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.0
	sm.height = 3.0
	crown.mesh = sm
	crown.material_override = _mat(Color(0.18, 0.38, 0.16))
	crown.position = t + Vector3(0, 7.5, 0)
	add_child(crown)
	var jag := MeshInstance3D.new()
	var jm := CapsuleMesh.new()
	jm.radius = 0.32
	jm.height = 1.6
	jag.mesh = jm
	jag.material_override = _mat(Color(0.88, 0.62, 0.22))
	jag.rotation.z = PI / 2
	jag.position = t + Vector3(2.2, 4.75, 0)
	add_child(jag)
	for k in 6:
		var spot := MeshInstance3D.new()
		var spm := SphereMesh.new()
		spm.radius = 0.08
		spm.height = 0.16
		spot.mesh = spm
		spot.material_override = _mat(Color(0.1, 0.08, 0.05))
		spot.position = t + Vector3(1.6 + k * 0.22, 5.0 + (k % 2) * 0.06, (k % 3 - 1) * 0.15)
		add_child(spot)
	_box(Vector3(0.4, 0.35, 0.35), t + Vector3(3.1, 4.85, 0), Color(0.88, 0.62, 0.22), false)
	_jaguar_area = _area(t + Vector3(2, 1, 0), 8.0)
	_jaguar_area.body_entered.connect(func(b):
		if b is Player and game_started:
			if not Game.unlocked.has("jaguar"):
				Game.toast.emit("An onça pintada! Don't make eye contact.", Color(1, 0.8, 0.4))
			Game.unlock("jaguar"))


# ================================================================ zone 3: Chapada dos Guimarães
const FALLS_X := 20.0

func _height_chapada(x: float, z: float) -> float:
	var low := noise.get_noise_2d(x, z) * 1.2 + 0.2
	var high := 7.5 + noise.get_noise_2d(x * 0.7 + 50.0, z * 0.7) * 0.9
	var edge := -11.0 + sin(x * 0.06) * 3.0
	var t := _ss(edge + 2.5, edge - 2.5, z)
	# hiking trail: a long ramp up the cliff
	var trail := _ss(5.0, 3.0, absf(x + 44.0))
	if trail > 0.0:
		t = lerpf(t, _ss(6.0, -34.0, z), trail)
	var h := lerpf(low, high, t)
	# plunge pool under the waterfall
	h = lerpf(h, -1.4, _ss(8.0, 4.0, Vector2(x, z).distance_to(Vector2(FALLS_X, edge + 7.0))))
	for fl in [[Vector2(42, 48), 20.0], [Vector2(-80, 40), 11.0]]:
		h = lerpf(h, 0.25, _ss(fl[1], fl[1] - 5.0, Vector2(x, z).distance_to(fl[0])))
	h = lerpf(h, high, _ss(10.0, 6.0, Vector2(x, z).distance_to(Vector2(30, -70))))
	var e := maxf(absf(x), absf(z))
	h += _ss(82.0, 98.0, e) * 9.0
	return h

func cliff_z(x: float) -> float:
	return -11.0 + sin(x * 0.06) * 3.0

func _build_chapada() -> void:
	noise.seed = 77
	noise.frequency = 0.03
	_rng.seed = 2028
	_static = StaticBody3D.new()
	add_child(_static)
	_blocked = [
		Rect2(-92, 28, 22, 22),    # bus
		Rect2(22, 30, 40, 40),     # village + gym
		Rect2(-48, -64, 36, 30),   # rock city
		Rect2(20, -80, 20, 20),    # mirante
		Rect2(-72, -18, 14, 14),   # cave
		Rect2(10, -22, 20, 30),    # waterfall + pool
		Rect2(-50, -40, 12, 50),   # trail
	]
	_build_environment()
	_build_terrain()
	_build_trees()
	_build_ground_detail()
	_build_props()
	_c_wildlife()
	_p_bus_stop(Vector3(-80, 0, 40), "CHAPADA DOS GUIMARÃES")
	_c_waterfall()
	_c_village()
	_c_rock_city()
	_c_mirante()
	_c_cave()
	_c_trail()
	_build_cups()
	_build_landmarks()
	_build_fighters()
	_build_villagers()
	_build_bounds()
	_build_beacon()

var _falls_mat: StandardMaterial3D

func _c_waterfall() -> void:
	var cz := cliff_z(FALLS_X)
	var top := ground_y(FALLS_X, cz - 4.0)
	_falls_mat = StandardMaterial3D.new()
	_falls_mat.albedo_color = Color(0.85, 0.93, 1.0, 0.7)
	_falls_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_falls_mat.emission_enabled = true
	_falls_mat.emission = Color(0.5, 0.6, 0.7)
	_falls_mat.emission_energy_multiplier = 0.4
	_falls_mat.uv1_scale = Vector3(1, 3, 1)
	var f := MeshInstance3D.new()
	var fm := QuadMesh.new()
	fm.size = Vector2(4.5, top + 1.4)
	f.mesh = fm
	f.material_override = _falls_mat
	f.position = Vector3(FALLS_X, (top - 1.4) / 2.0, cz + 2.6)
	add_child(f)
	var pool := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 7.0
	pm.bottom_radius = 7.0
	pm.height = 0.05
	pm.radial_segments = 24
	pool.mesh = pm
	pool.material_override = EnvShaders.water(Color(0.06, 0.3, 0.34), Color(0.28, 0.58, 0.58, 0.82), 0.0, 0.5)
	pool.position = Vector3(FALLS_X, -0.55, cz + 7.0)
	add_child(pool)
	var mist := _label("VÉU DE NOIVA", Vector3(FALLS_X, top + 2.5, cz), 90, Color(1, 1, 1, 0.9))
	mist.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var secret := _area(Vector3(FALLS_X, ground_y(FALLS_X, cz + 2.0) + 1.0, cz + 2.0), 1.8)
	secret.body_entered.connect(func(b):
		if b is Player and game_started:
			if not Game.unlocked.has("behind_falls"):
				Game.toast.emit("Behind the veil... cold, loud, and beautiful.", Color(0.7, 0.9, 1.0))
			Game.unlock("behind_falls"))

func _gym(c: Vector3, title: String, wall: Color, usa := false) -> void:
	_box(Vector3(18, 0.3, 14), c + Vector3(0, 0.15, 0), Color(0.6, 0.55, 0.5))
	if usa:
		# American garage gym: corrugated metal walls, steel posts, a gable tin roof, navy / black mats
		var tin := TownKit._mat("tin")
		for wpos in [[Vector3(0.3, 5, 14), Vector3(-9, 2.5, 0)], [Vector3(0.3, 5, 14), Vector3(9, 2.5, 0)], [Vector3(18, 5, 0.3), Vector3(0, 2.5, 7)]]:
			var w := _box(wpos[0], c + wpos[1], wall)
			w.material_override = tin
		for x in [-9, -3, 3, 9]:
			_box(Vector3(0.35, 5, 0.35), c + Vector3(x, 2.5, -7), Color(0.2, 0.22, 0.25))
		var roof := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(19.4, 1.6, 15.2)
		roof.mesh = pm
		roof.material_override = tin
		roof.position = c + Vector3(0, 5.8, 0)
		add_child(roof)
		_box(Vector3(19.4, 0.25, 15.2), c + Vector3(0, 5.0, 0), Color(0.2, 0.2, 0.22), false)
	else:
		_box(Vector3(0.5, 5, 14), c + Vector3(-9, 2.5, 0), wall)
		_box(Vector3(0.5, 5, 14), c + Vector3(9, 2.5, 0), wall)
		_box(Vector3(18, 5, 0.5), c + Vector3(0, 2.5, 7), wall)
		_box(Vector3(19, 0.4, 15), c + Vector3(0, 5.2, 0), Color(0.3, 0.3, 0.32), false)
		for x in [-9, -3, 3, 9]:
			_box(Vector3(0.6, 5, 0.6), c + Vector3(x, 2.5, -7), wall)
	for x in 8:
		for z in 6:
			var col := Color(0.13, 0.38, 0.26) if (x + z) % 2 == 0 else Color(0.78, 0.62, 0.22)
			if usa:
				col = Color(0.12, 0.18, 0.42) if (x + z) % 2 == 0 else Color(0.07, 0.07, 0.08)
			_box(Vector3(1.96, 0.08, 1.96), c + Vector3(-7 + x * 2, 0.34, -5 + z * 2), col, false)
	_label(title, c + Vector3(0, 6.3, -7.4), 130, Color(0.98, 0.82, 0.3), PI)
	var lamp := OmniLight3D.new()
	lamp.position = c + Vector3(0, 4.2, 0)
	lamp.omni_range = 12
	lamp.light_energy = 1.2
	lamp.light_color = Color(1, 0.85, 0.6)
	add_child(lamp)

func _c_village() -> void:
	var g := Vector3(40, ground_y(40, 56), 56)
	_gym(g, "ACADEMIA CACHOEIRA", Color(0.78, 0.45, 0.3))
	var xs := [-7.0, -3.5, 0.0, 3.5, 7.0]
	for i in Rpg.ATTR_ORDER.size():
		_drill_station(Rpg.ATTR_ORDER[i], g + Vector3(xs[i], 0, 5.0))
	_challenge_board(g + Vector3(-12, 0, -9))
	_comp_board(g + Vector3(12, 0, -9), "chapada_open")
	var palette := [Color(0.97, 0.85, 0.35), Color(0.95, 0.55, 0.6), Color(0.98, 0.95, 0.88), Color(0.95, 0.6, 0.3), Color(0.55, 0.8, 0.5)]
	for i in 6:
		var a := -0.3 + i * 0.55
		var p := Vector3(42 + cos(a) * 15.0, 0, 40 + sin(a) * -15.0)
		var gy := ground_y(p.x, p.z)
		var col: Color = palette[i % palette.size()]
		_box(Vector3(5, 3.5, 5), Vector3(p.x, gy + 1.75, p.z), col)
		var roof := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(5.6, 1.5, 5.6)
		roof.mesh = pm
		roof.material_override = _mat(Color(0.72, 0.33, 0.2))
		roof.position = Vector3(p.x, gy + 4.25, p.z)
		add_child(roof)
	# crystal shop stand for Joaquim
	var cs := Vector3(50, ground_y(50, 34), 34)
	_box(Vector3(3, 1, 1.2), cs + Vector3(0, 0.5, 0), Color(0.45, 0.32, 0.2))
	for k in 5:
		var cr := MeshInstance3D.new()
		var crm := PrismMesh.new()
		crm.size = Vector3(0.25, 0.5, 0.25)
		cr.mesh = crm
		cr.material_override = _mat([Color(0.85, 0.75, 0.95), Color(0.95, 0.95, 1.0), Color(0.75, 0.6, 0.9)][k % 3], 0.2)
		cr.position = cs + Vector3(-1.2 + k * 0.6, 1.25, 0)
		add_child(cr)

func _c_rock_city() -> void:
	for i in 26:
		var x := _rng.randf_range(-46, -14)
		var z := _rng.randf_range(-64, -36)
		if Vector2(x, z).distance_to(Vector2(-30, -40)) < 4.0 or Vector2(x, z).distance_to(Vector2(-8, -58)) < 4.0:
			continue
		var gy := ground_y(x, z)
		var h := _rng.randf_range(3.0, 9.0)
		var w := _rng.randf_range(1.5, 3.5)
		var col := Color(0.72, 0.38, 0.22).lerp(Color(0.85, 0.55, 0.32), _rng.randf())
		_box(Vector3(w, h, w * _rng.randf_range(0.7, 1.3)), Vector3(x, gy + h / 2.0 - 0.3, z), col, true, _rng.randf() * TAU)
		if _rng.randf() < 0.4:
			_box(Vector3(w * 1.3, 0.8, w * 1.1), Vector3(x, gy + h + 0.1, z), col.darkened(0.1), false, _rng.randf() * TAU)

func _c_mirante() -> void:
	var c := Vector3(30, ground_y(30, -70), -70)
	_box(Vector3(10, 0.3, 10), c + Vector3(0, 0.1, 0), Color(0.75, 0.72, 0.65))
	var ob := _cyl(0.0, 0.9, 7.0, c + Vector3(0, 3.6, 0), Color(0.9, 0.88, 0.8), 4, true)
	ob.rotation.y = PI / 4
	for i in 4:
		var a := i * PI / 2
		_box(Vector3(10 if i % 2 == 0 else 0.15, 1.0, 0.15 if i % 2 == 0 else 10), c + Vector3(sin(a) * 5.0, 0.6, cos(a) * 5.0), Color(0.4, 0.3, 0.2), false)
	var l := _label("CENTRO GEODÉSICO\nDA AMÉRICA DO SUL", c + Vector3(0, 8.2, 0), 70, Color(1, 0.95, 0.8))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED

func _c_cave() -> void:
	var cz := cliff_z(-64)
	var c := Vector3(-64, ground_y(-64, cz + 4.0), cz + 3.0)
	_box(Vector3(1.2, 5.0, 1.5), c + Vector3(-3, 2.5, 0), Color(0.6, 0.3, 0.18))
	_box(Vector3(1.2, 5.0, 1.5), c + Vector3(3, 2.5, 0), Color(0.6, 0.3, 0.18))
	_box(Vector3(7.2, 1.4, 1.5), c + Vector3(0, 5.2, 0), Color(0.6, 0.3, 0.18))
	_box(Vector3(5, 4.6, 0.2), c + Vector3(0, 2.3, -1.6), Color(0.03, 0.03, 0.03), false)
	var lamp := OmniLight3D.new()
	lamp.position = c + Vector3(0, 1.5, 1.5)
	lamp.light_color = Color(0.7, 0.6, 1.0)
	lamp.omni_range = 5.0
	lamp.light_energy = 1.0
	add_child(lamp)
	_label("ARÕE JARI", c + Vector3(0, 6.6, 0.6), 60, Color(1, 0.9, 0.7))

func _c_trail() -> void:
	# wooden steps and a handrail along the cliff trail
	for i in 14:
		var z := 4.0 - i * 2.8
		var gy := ground_y(-44, z)
		_box(Vector3(0.12, 1.0, 0.12), Vector3(-40.5, gy + 0.5, z), Color(0.45, 0.32, 0.2), false)
	var trail_sign := _label("TRILHA DO MIRANTE", Vector3(-44, ground_y(-44, 8) + 2.4, 8), 60, Color(1, 0.95, 0.8))
	trail_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED


## Tournament poster board: opens the bracket for this zone's competition.
func _comp_board(pos: Vector3, comp_id: String) -> void:
	var gy := ground_y(pos.x, pos.z)
	var wood := Color(0.4, 0.28, 0.18)
	_box(Vector3(0.15, 2.6, 0.15), Vector3(pos.x - 1.0, gy + 1.3, pos.z), wood, false)
	_box(Vector3(0.15, 2.6, 0.15), Vector3(pos.x + 1.0, gy + 1.3, pos.z), wood, false)
	_box(Vector3(2.4, 1.6, 0.1), Vector3(pos.x, gy + 2.1, pos.z), Color(0.55, 0.12, 0.12), false)
	var nm: String = Tx.s(Data.COMPS[comp_id].name).to_upper()
	for side in [1, -1]:
		var l := _label(("TOURNAMENT\n%s" if Data.continent_of(zone) == "america" else "CAMPEONATO\n%s") % nm, Vector3(pos.x, gy + 2.15, pos.z + 0.07 * side), 40, Color(1, 0.88, 0.4), 0.0 if side == 1 else PI)
		l.pixel_size = 0.0055
	var medal := _cyl(0.22, 0.22, 0.05, Vector3(pos.x, gy + 3.15, pos.z), Color(0.98, 0.78, 0.2), 14)
	medal.rotation.x = PI / 2
	_spot(Vector3(pos.x, gy, pos.z), 2.4, Data.COMPS[comp_id].name, "comp", comp_id)
	if comp_id != "mundial":
		_team_board(pos + Vector3(3.4, 0, 0))
		_circuit_board(pos + Vector3(6.8, 0, 0))

# ------------------------------------------------------------ academy wars
var flags := {}   # territory id -> {cloth: MeshInstance3D, label: Label3D}

## A flag pole per territory, in the holding academy's colours (yours: green and gold).
func _build_territories() -> void:
	flags.clear()
	for tid in Data.territories_in(zone):
		var t: Dictionary = Data.TERRITORIES[tid]
		var p: Vector3 = t.pos
		var gy := ground_y(p.x, p.z)
		_cyl(0.06, 0.08, 4.2, Vector3(p.x, gy + 2.1, p.z), Color(0.85, 0.85, 0.82), 8)
		_cyl(0.5, 0.6, 0.18, Vector3(p.x, gy + 0.09, p.z), Color(0.45, 0.42, 0.38), 12)
		var cloth := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.5, 0.95, 0.04)
		cloth.mesh = bm
		cloth.position = Vector3(p.x + 0.8, gy + 3.6, p.z)
		add_child(cloth)
		var lbl := _label("", Vector3(p.x, gy + 4.7, p.z), 56, Color.WHITE)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.pixel_size = 0.006
		flags[tid] = {"cloth": cloth, "label": lbl}
		_spot(Vector3(p.x, gy, p.z), 2.6, Tx.f("Territory: %s", t.name), "territory", tid)
	refresh_flags()

func refresh_flags() -> void:
	for tid in flags:
		var t: Dictionary = Data.TERRITORIES[tid]
		var st := Game.territory_state(tid)
		var c: Color = Data.YOUR_ACADEMY_COLOR if st != "rival" else Data.ACADEMY_COLORS.get(t.academy, Color(0.6, 0.6, 0.6))
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = st == "attacked"
		m.emission = Color(1, 0.2, 0.15)
		m.emission_energy_multiplier = 0.8
		(flags[tid].cloth as MeshInstance3D).material_override = m
		var l: Label3D = flags[tid].label
		match st:
			"rival":
				l.text = "%s\n%s" % [Tx.s(t.name).to_upper(), t.academy]
				l.modulate = Color(1, 0.85, 0.75)
			"held":
				l.text = Tx.f("%s\nGringo BJJ", Tx.s(t.name).to_upper())
				l.modulate = Color(0.6, 1, 0.7)
			"attacked":
				l.text = Tx.f("%s\nUNDER ATTACK!", Tx.s(t.name).to_upper())
				l.modulate = Color(1, 0.4, 0.35)

## The Circuito board (purple): roguelite tournament runs.
func _circuit_board(pos: Vector3) -> void:
	var gy := ground_y(pos.x, pos.z)
	var wood := Color(0.4, 0.28, 0.18)
	_box(Vector3(0.15, 2.4, 0.15), Vector3(pos.x - 0.9, gy + 1.2, pos.z), wood, false)
	_box(Vector3(0.15, 2.4, 0.15), Vector3(pos.x + 0.9, gy + 1.2, pos.z), wood, false)
	_box(Vector3(2.2, 1.4, 0.1), Vector3(pos.x, gy + 2.0, pos.z), Color(0.32, 0.14, 0.45), false)
	for side in [1, -1]:
		var l := _label("CIRCUITO\n5 lutas · 1 vida", Vector3(pos.x, gy + 2.05, pos.z + 0.07 * side), 40, Color(0.92, 0.75, 1.0), 0.0 if side == 1 else PI)
		l.pixel_size = 0.0055
	_spot(Vector3(pos.x, gy, pos.z), 2.2, "Circuito (5 fights, 1 life)", "circuit", zone)

## The 5v5 team challenge board (green and gold), next to each zone's competition board.
func _team_board(pos: Vector3) -> void:
	var gy := ground_y(pos.x, pos.z)
	var wood := Color(0.4, 0.28, 0.18)
	_box(Vector3(0.15, 2.4, 0.15), Vector3(pos.x - 0.9, gy + 1.2, pos.z), wood, false)
	_box(Vector3(0.15, 2.4, 0.15), Vector3(pos.x + 0.9, gy + 1.2, pos.z), wood, false)
	_box(Vector3(2.2, 1.4, 0.1), Vector3(pos.x, gy + 2.0, pos.z), Color(0.1, 0.42, 0.28), false)
	for side in [1, -1]:
		var l := _label("TEAM CHALLENGE\n5 v 5" if Data.continent_of(zone) == "america" else "DESAFIO DE EQUIPES\n5 v 5", Vector3(pos.x, gy + 2.05, pos.z + 0.07 * side), 40, Color(0.98, 0.82, 0.22), 0.0 if side == 1 else PI)
		l.pixel_size = 0.0055
	_spot(Vector3(pos.x, gy, pos.z), 2.2, "Team Challenge (5v5)", "team", zone)

func _challenge_board(pos: Vector3) -> void:
	var gy := ground_y(pos.x, pos.z)
	_box(Vector3(0.15, 2.2, 0.15), Vector3(pos.x - 0.9, gy + 1.1, pos.z), Color(0.4, 0.28, 0.18), false)
	_box(Vector3(0.15, 2.2, 0.15), Vector3(pos.x + 0.9, gy + 1.1, pos.z), Color(0.4, 0.28, 0.18), false)
	_box(Vector3(2.2, 1.3, 0.1), Vector3(pos.x, gy + 1.9, pos.z), Color(0.15, 0.25, 0.2), false)
	var l := _label("DAILY\nCHALLENGE" if Data.continent_of(zone) == "america" else "DESAFIO\nDO DIA", Vector3(pos.x, gy + 1.95, pos.z + 0.07), 44, UiKit.ACCENT)
	l.pixel_size = 0.006
	var l2 := _label("DAILY\nCHALLENGE" if Data.continent_of(zone) == "america" else "DESAFIO\nDO DIA", Vector3(pos.x, gy + 1.95, pos.z - 0.07), 44, UiKit.ACCENT, PI)
	l2.pixel_size = 0.006
	_spot(Vector3(pos.x, gy, pos.z), 2.4, "Daily Challenge board", "daily")


func _build_caceres_life() -> void:
	# parked cars along the main street (Kenney Car Kit)
	var cars := ["sedan", "taxi", "van", "police_car", "truck", "sedan", "taxi"]
	var xs := [-42.0, -28.0, 18.0, 36.0, 48.0, 58.0, -12.0]
	for i in cars.size():
		var x: float = xs[i]
		var z := -8.6 if i % 2 == 0 else 0.6
		if _is_blocked(x, z, 0.0) and not (absf(z + 4.0) < 5.0):
			continue
		_place_model(cars[i], Vector3(x, ground_y(x, z), z), 1.7, PI / 2 if i % 2 == 0 else -PI / 2, Vector3(4.6, 2.0, 2.4))
	# street dogs and cats (Quaternius animals)
	_animal("shiba", Vector3(8, ground_y(8, 18), 18), 0.9, 2.4)
	_animal("pug", Vector3(-6, ground_y(-6, 0), 0), 0.55, 0.8)
	_animal("cat", Vector3(14, ground_y(14, -10), -10), 0.5, -1.2)
	_animal("cat", Vector3(-3, ground_y(-3, -46), -46), 0.45, 0.4)
	_animal("shiba", Vector3(26, ground_y(26, -14), -14), 0.85, -0.6)
	_animal("frog", Vector3(-58, ground_y(-58, 14), 14), 0.22, 1.0)
	# tereré stand in the plaza
	_place_model("barrel", Vector3(11, ground_y(11, 12) + 0.15, 12), 4.0, 0.0, Vector3(0.8, 1.0, 0.8))
	_place_model("crate", Vector3(12.3, ground_y(12, 12) + 0.15, 12.2), 2.0, 0.3)

func _c_wildlife() -> void:
	_animal("deer", Vector3(-20, ground_y(-20, 30), 30), 1.7, 0.5)
	_animal("fox", Vector3(60, ground_y(60, -40), -40), 0.9, 2.0)
	_animal("fox", Vector3(-40, ground_y(-40, -70), -70), 0.85, -0.7)
	_place_model("crystal_rock", Vector3(-60, ground_y(-60, -6), -6), 3.0, 0.4, Vector3(2.4, 1.6, 2.4))
	_place_model("crystal_rock", Vector3(-68, ground_y(-68, -4), -4), 2.4, 1.9, Vector3(2.0, 1.3, 2.0))
	_place_model("tent", Vector3(-70, ground_y(-70, 48), 48), 4.0, 0.6, Vector3(3.0, 2.2, 2.6))
	_place_model("campfire", Vector3(-66, ground_y(-66, 46), 46), 3.0)


# ================================================================ zone 4: Rio de Janeiro
const CRISTO := Vector2(-46, -62)
const MORRO := Vector2(38, -52)
const SUGARLOAF := Vector2(82, 66)
const RIO_GYM := Vector3(10, 0, -24)

func _height_rio(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := noise.get_noise_2d(x, z) * 0.5 + 0.45
	# beach slopes into the Atlantic
	h = lerpf(h, 0.35, _ss(30.0, 34.0, z))
	h = lerpf(h, -2.8, _ss(50.0, 63.0, z))
	# Corcovado (forest mountain with the statue), the morro, Arpoador rock, Sugarloaf
	h += 22.0 * _ss(46.0, 6.0, p.distance_to(CRISTO))
	h += 9.0 * _ss(32.0, 6.0, p.distance_to(MORRO))
	h += 4.5 * _ss(11.0, 3.0, p.distance_to(Vector2(-78, 52)))
	h += 31.0 * _ss(14.0, 5.0, p.distance_to(SUGARLOAF))
	# green ridges behind the city
	var e := maxf(absf(x), absf(z))
	h += _ss(82.0, 98.0, e) * 10.0 * (1.0 - _ss(28.0, 40.0, z))
	# flat pads: bus station, gym
	h = lerpf(h, 0.5, _ss(13.0, 8.0, p.distance_to(Vector2(-84, 6))))
	h = lerpf(h, 0.5, _ss(14.0, 10.0, p.distance_to(Vector2(RIO_GYM.x, RIO_GYM.z))))
	return h

func _rio_color(x: float, z: float, h: float) -> Color:
	var n := noise.get_noise_2d(x * 3.0 + 100.0, z * 3.0) * 0.5 + 0.5
	var slope := absf(height(x, z + 1.5) - height(x, z - 1.5)) + absf(height(x + 1.5, z) - height(x - 1.5, z))
	if Vector2(x, z).distance_to(SUGARLOAF) < 15.0 or (slope > 2.6 and h > 3.0):
		return Color(0.5, 0.47, 0.44).lerp(Color(0.6, 0.57, 0.52), n)
	if z > 31.0:
		var sand := Color(0.8, 0.66, 0.44).lerp(Color(0.86, 0.73, 0.5), n)
		return sand.lerp(Color(0.7, 0.62, 0.46), _ss(-0.4, -1.3, h))
	if z > 17.0 and z <= 25.0:
		return Color(0.24, 0.24, 0.26)  # Avenida Atlântica
	if z > 25.0:
		return Color(0.8, 0.78, 0.74)
	var morro := _ss(30.0, 18.0, Vector2(x, z).distance_to(MORRO))
	if morro > 0.0:
		return Color(0.3, 0.42, 0.18).lerp(Color(0.58, 0.44, 0.3), morro)
	if x > -64.0 and z > -34.0 and h < 2.0:
		return Color(0.6, 0.58, 0.54).lerp(Color(0.66, 0.64, 0.6), n)  # city pavement
	return Color(0.17, 0.34, 0.14).lerp(Color(0.26, 0.42, 0.18), n)  # Tijuca forest

func _build_rio() -> void:
	noise.seed = 21
	noise.frequency = 0.03
	_rng.seed = 2030
	_static = StaticBody3D.new()
	add_child(_static)
	_blocked = [
		Rect2(-98, -8, 28, 26),     # bus station
		Rect2(-4, -38, 28, 28),     # gym
		Rect2(-66, -16, 140, 32),   # city blocks
		Rect2(-100, 16, 200, 90),   # avenue, calçadão, beach, sea
		Rect2(10, -82, 56, 56),     # morro
		Rect2(-56, -72, 20, 20),    # statue
	]
	_build_environment()
	_build_terrain()
	_r_ocean()
	_r_calcadao()
	_r_buildings()
	_build_trees()
	_build_ground_detail()
	_build_props()
	_r_beach_life()
	var bl := BeachLife.new()
	add_child(bl)
	bl.setup(self)
	_r_cristo()
	_r_morro()
	_r_sugarloaf()
	_p_bus_stop(Vector3(-84, 0, 6), "RODOVIÁRIA · RIO")
	var g := Vector3(RIO_GYM.x, ground_y(RIO_GYM.x, RIO_GYM.z), RIO_GYM.z)
	_gym(g, "ACADEMIA LEÃO", Color(0.92, 0.9, 0.84))
	var xs := [-7.0, -3.5, 0.0, 3.5, 7.0]
	for i in Rpg.ATTR_ORDER.size():
		_drill_station(Rpg.ATTR_ORDER[i], g + Vector3(xs[i], 0, 5.0))
	_challenge_board(g + Vector3(-12, 0, 9))
	_comp_board(g + Vector3(12, 0, 9), "rio_open")
	_comp_board(g + Vector3(12, 0, -10), "mundial")
	_label("ARPOADOR", Vector3(-78, ground_y(-78, 52) + 3.5, 52), 80, Color(1, 0.9, 0.7)).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_build_cups()
	_build_landmarks()
	_build_fighters()
	_build_villagers()
	_build_bounds()
	_build_beacon()

func _r_ocean() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = EnvShaders.water_plane(Vector2(420, 180), 4.0)
	# the Atlantic: bigger swells rolling toward the beach
	mi.material_override = EnvShaders.water(Color(0.02, 0.2, 0.36), Color(0.1, 0.52, 0.6, 0.86), 0.22, 0.09, Vector2(0.0, -0.8))
	mi.position = Vector3(0, WATER_Y, 140)
	add_child(mi)
	# a line of surf where the waves break
	var foam := MeshInstance3D.new()
	var fm := PlaneMesh.new()
	fm.size = Vector2(400, 1.6)
	foam.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1, 1, 1, 0.55)
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foam.material_override = fmat
	foam.position = Vector3(0, WATER_Y + 0.03, 57.5)
	add_child(foam)

## The black-and-white wave pavement along the beach.
func _r_calcadao() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell := 0.5
	var x := -98.0
	while x < 98.0:
		var z := 25.5
		while z < 30.5:
			var cx := x + cell * 0.5
			var cz := z + cell * 0.5
			var wave := sin((cz - 28.0) * 2.2 + sin(cx * 0.55) * 1.7)
			var c := Color(0.08, 0.08, 0.08) if wave > 0.0 else Color(0.86, 0.85, 0.8)
			var y := ground_y(cx, cz) + 0.04
			st.set_color(c)
			for v in [Vector3(x, y, z), Vector3(x + cell, y, z), Vector3(x + cell, y, z + cell), Vector3(x, y, z), Vector3(x + cell, y, z + cell), Vector3(x, y, z + cell)]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
			z += cell
		x += cell
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.9
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# palms along the promenade
	var palms: Array = []
	var px := -90.0
	while px < 90.0:
		palms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * 5.6), Vector3(px, ground_y(px, 31.5), 31.5)))
		px += 9.0
	_mm("tree_palm", palms)
	# kiosks
	var kx := -70.0
	while kx < 80.0:
		var gy := ground_y(kx, 33.5)
		_box(Vector3(2.6, 2.2, 2.6), Vector3(kx, gy + 1.1, 33.5), Color(0.95, 0.95, 0.92))
		_cyl(0.0, 2.3, 1.0, Vector3(kx, gy + 2.7, 33.5), Color(0.15, 0.55, 0.35), 8)
		_box(Vector3(2.7, 0.3, 0.3), Vector3(kx, gy + 1.0, 32.1), Color(0.98, 0.8, 0.2), false)
		kx += 26.0
	# yellow taxis and cars on the Avenida
	var cars := ["taxi", "taxi", "sedan", "taxi", "van", "taxi", "police_car", "taxi"]
	for i in cars.size():
		var cx := -76.0 + i * 20.0 + _rng.randf_range(-3, 3)
		var cz := 19.5 if i % 2 == 0 else 23.0
		_place_model(cars[i], Vector3(cx, ground_y(cx, cz), cz), 1.7, PI / 2 if i % 2 == 0 else -PI / 2, Vector3(4.6, 2.0, 2.4))

## High-rises facing the beach, like the Avenida Atlântica skyline.
func _r_buildings() -> void:
	var cols := [Color(0.88, 0.84, 0.74), Color(0.86, 0.72, 0.56), Color(0.66, 0.76, 0.8), Color(0.92, 0.72, 0.62), Color(0.74, 0.8, 0.68), Color(0.85, 0.85, 0.82), Color(0.95, 0.85, 0.55)]
	var x := -60.0
	var i := 0
	while x < 70.0:
		var w := _rng.randf_range(7.0, 8.6)
		var h := _rng.randf_range(12.0, 30.0)
		var gy := ground_y(x, 9.0)
		var col: Color = cols[i % cols.size()]
		_box(Vector3(w, h, 10), Vector3(x, gy + h / 2.0, 9.0), col)
		# balconies + dark glass bands on the beach side
		var y := 3.0
		while y < h - 1.0:
			_box(Vector3(w * 0.92, 1.1, 0.12), Vector3(x, gy + y + 0.7, 14.05), Color(0.2, 0.3, 0.38), false)
			_box(Vector3(w + 0.4, 0.18, 0.9), Vector3(x, gy + y, 14.4), col.darkened(0.08), false)
			y += 3.2
		_box(Vector3(w + 0.2, 0.5, 10.2), Vector3(x, gy + h + 0.25, 9.0), col.darkened(0.2), false)
		# shorter block behind
		var h2 := _rng.randf_range(6.0, 14.0)
		_box(Vector3(w, h2, 7), Vector3(x, gy + h2 / 2.0, -6.0), cols[(i + 3) % cols.size()].darkened(0.05))
		x += w + _rng.randf_range(1.2, 2.6)
		if i % 3 == 2:
			x += 7.0  # cross street down to the beach
		i += 1

func _r_beach_life() -> void:
	var cols := [Color(0.95, 0.3, 0.25), Color(0.98, 0.8, 0.2), Color(0.2, 0.55, 0.9), Color(0.3, 0.75, 0.4), Color(0.95, 0.55, 0.75), Color(1, 1, 1)]
	for i in 34:
		var x := _rng.randf_range(-86, 74)
		var z := _rng.randf_range(36, 50)
		if Vector2(x, z).distance_to(Vector2(22, 40)) < 4.0 or Vector2(x, z).distance_to(Vector2(-30, 42)) < 6.0 or Vector2(x, z).distance_to(Vector2(-78, 52)) < 11.0:
			continue
		var gy := ground_y(x, z)
		_cyl(0.04, 0.04, 2.2, Vector3(x, gy + 1.1, z), Color(0.85, 0.85, 0.85), 5)
		_cyl(0.0, 1.35, 0.5, Vector3(x, gy + 2.2, z), cols[i % cols.size()], 10)
		if i % 3 == 0:
			_box(Vector3(0.8, 0.05, 1.8), Vector3(x + 1.2, gy + 0.05, z + 0.3), cols[(i + 2) % cols.size()], false, _rng.randf())
	# volleyball court next to Luana
	var vc := Vector3(-30, ground_y(-30, 46), 46)
	for sx in [-4.5, 4.5]:
		_cyl(0.06, 0.06, 2.6, vc + Vector3(sx, 1.3, 0), Color(0.9, 0.9, 0.9), 6)
	_box(Vector3(9, 0.9, 0.04), vc + Vector3(0, 2.1, 0), Color(0.15, 0.15, 0.15, 0.8), false)
	# sand mats where the beach crew trains
	_box(Vector3(6, 0.12, 6), Vector3(22, ground_y(22, 40) + 0.06, 40), Color(0.15, 0.4, 0.75), false)
	_animal("crab", Vector3(-10, ground_y(-10, 52), 52), 0.4, 0.3)
	_animal("crab", Vector3(30, ground_y(30, 53), 53), 0.35, 2.0)
	_animal("crab", Vector3(-60, ground_y(-60, 50), 50), 0.4, -1.0)
	_animal("pug", Vector3(-20, ground_y(-20, 28), 28), 0.55, 1.2)
	_animal("shiba", Vector3(40, ground_y(40, 28), 28), 0.85, -2.0)

## A generic robed statue with outstretched arms on the summit.
func _r_cristo() -> void:
	var top := Vector3(CRISTO.x, ground_y(CRISTO.x, CRISTO.y), CRISTO.y)
	var stone := Color(0.9, 0.9, 0.86)
	_box(Vector3(10, 0.4, 10), top + Vector3(0, 0.1, 0), Color(0.75, 0.72, 0.68))
	_box(Vector3(3, 3.4, 3), top + Vector3(0, 1.9, 0), Color(0.82, 0.8, 0.76))
	_cyl(0.7, 1.25, 6.2, top + Vector3(0, 6.7, 0), stone, 10)
	_box(Vector3(8.4, 0.8, 0.8), top + Vector3(0, 9.0, 0), stone, false)
	_cyl(0.45, 0.45, 0.9, top + Vector3(0, 10.2, 0), stone, 10)
	var head := MeshInstance3D.new()
	head.mesh = _mk_sphere(0.6, 1.2)
	head.material_override = _mat(stone)
	head.position = top + Vector3(0, 11.1, 0)
	add_child(head)
	for k in 4:
		var a := k * PI / 2
		_box(Vector3(10 if k % 2 == 0 else 0.15, 1.0, 0.15 if k % 2 == 0 else 10), top + Vector3(sin(a) * 5.0, 0.7, cos(a) * 5.0), Color(0.4, 0.3, 0.2), false)
	var summit := _area(top + Vector3(0, 1.0, 0), 6.0)
	summit.body_entered.connect(func(b):
		if b is Player and game_started:
			if not Game.unlocked.has("cristo"):
				Game.toast.emit("The whole city below, arms wide open.", Color(0.9, 0.95, 1.0))
			Game.unlock("cristo"))

## Hillside community: stacked, brightly painted houses and the social-project mats.
func _r_morro() -> void:
	var cols := [Color(0.95, 0.45, 0.3), Color(0.98, 0.8, 0.3), Color(0.35, 0.65, 0.85), Color(0.5, 0.8, 0.45), Color(0.95, 0.6, 0.75), Color(0.92, 0.92, 0.88), Color(0.85, 0.55, 0.35)]
	var n := 0
	var tries := 0
	while n < 46 and tries < 600:
		tries += 1
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(7.0, 28.0)
		var x := MORRO.x + cos(a) * r
		var z := MORRO.y + sin(a) * r
		if absf(x - 36.0) < 3.5 or Vector2(x, z).distance_to(Vector2(36, -42)) < 6.0 or z > -26.0:
			continue
		var gy := minf(minf(ground_y(x - 1.4, z - 1.4), ground_y(x + 1.4, z + 1.4)), minf(ground_y(x + 1.4, z - 1.4), ground_y(x - 1.4, z + 1.4)))
		var hh := _rng.randf_range(2.4, 3.2)
		var rot := _rng.randf_range(-0.3, 0.3)
		_box(Vector3(3.0, hh + 1.0, 3.0), Vector3(x, gy + (hh + 1.0) / 2.0 - 0.5, z), cols[n % cols.size()], true, rot)
		_box(Vector3(0.7, 1.2, 0.05), Vector3(x, gy + 0.6, z + 1.53), Color(0.25, 0.18, 0.12), false, rot)
		if _rng.randf() < 0.45:
			_box(Vector3(2.6, 2.2, 2.6), Vector3(x + 0.2, gy + hh + 1.6, z - 0.2), cols[(n + 3) % cols.size()], true, rot + 0.1)
		if _rng.randf() < 0.5:
			_cyl(0.5, 0.5, 0.8, Vector3(x + 0.8, gy + hh + 0.9, z + 0.8), Color(0.2, 0.35, 0.75), 8)  # water tank
		n += 1
	# Tatu's free class: mats in a cleared square
	var mc := Vector3(36, ground_y(36, -42), -42)
	_box(Vector3(7, 0.3, 7), mc + Vector3(0, 0.05, 0), Color(0.6, 0.55, 0.5))
	for ix in 3:
		for iz in 3:
			_box(Vector3(1.96, 0.06, 1.96), mc + Vector3(-2 + ix * 2, 0.23, -2 + iz * 2), Color(0.13, 0.38, 0.26) if (ix + iz) % 2 == 0 else Color(0.85, 0.7, 0.2), false)
	_label("PROJETO SOCIAL", mc + Vector3(0, 3.6, -4), 70, Color(1, 0.95, 0.75)).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_animal("cat", Vector3(30, ground_y(30, -46) + 0.1, -46), 0.45, 1.0)
	_animal("cat", Vector3(44, ground_y(44, -58) + 0.1, -58), 0.45, -0.8)

func _r_sugarloaf() -> void:
	var st := Vector3(62, ground_y(62, 40), 40)
	_box(Vector3(5, 4, 4), st + Vector3(0, 2, -1.5), Color(0.85, 0.82, 0.75))
	_box(Vector3(5.6, 0.4, 4.6), st + Vector3(0, 4.2, -1.5), Color(0.4, 0.4, 0.42), false)
	var a := st + Vector3(0, 4.0, -1.5)
	var b := Vector3(SUGARLOAF.x, ground_y(SUGARLOAF.x, SUGARLOAF.y) + 0.5, SUGARLOAF.y)
	var d := b - a
	var cable := MeshInstance3D.new()
	cable.mesh = _mk_box(Vector3(0.06, 0.06, d.length()))
	cable.material_override = _mat(Color(0.15, 0.15, 0.15))
	add_child(cable)
	cable.global_transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP), (a + b) * 0.5)
	var car := _box(Vector3(2.0, 1.6, 2.6), a.lerp(b, 0.42) - Vector3(0, 1.1, 0), Color(0.95, 0.75, 0.2), false)
	car.look_at(car.global_position + Vector3(d.x, 0, d.z).normalized(), Vector3.UP)
	_label("PÃO DE AÇÚCAR", b + Vector3(0, 3.0, 0), 110, Color(1, 1, 1, 0.95)).billboard = BaseMaterial3D.BILLBOARD_ENABLED


# ================================================================ Vila Nova (Cáceres expansion)
## A new neighbourhood south-east of the plaza: a long street of houses, a small square with the
## Mercadinho (vendor), and the Quadra da Vila (an outdoor court where street rollers hang out).
## Plus two outskirts camps: the Prainha on the river and the Galpão warehouse gym (elites).
func _road(a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	d.y = 0
	var n := maxi(1, int(d.length() / 6.0))
	var step := d / n
	for i in n:
		var c := a + step * (i + 0.5)
		var gy := ground_y(c.x, c.z)
		var size := Vector3(absf(step.x) + 0.2 if absf(step.x) > 0.1 else w, 0.14, absf(step.z) + 0.2 if absf(step.z) > 0.1 else w)
		_box(size, Vector3(c.x, gy + 0.05, c.z), Color(0.42, 0.4, 0.38), false)

func _house(p: Vector3, front: Vector3, palette: Array) -> void:
	var w := _rng.randf_range(5, 7)
	var d := _rng.randf_range(5, 6.5)
	var hgt := _rng.randf_range(3.2, 4.4)
	var gy := ground_y(p.x, p.z)
	var col: Color = palette[_rng.randi() % palette.size()]
	var size := Vector3(w, hgt, d) if front.z != 0.0 else Vector3(d, hgt, w)
	_box(size, Vector3(p.x, gy + hgt / 2.0, p.z), col)
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(size.x + 0.6, 1.6, size.z + 0.6)
	roof.mesh = pm
	roof.material_override = _mat(Color(0.72, 0.33, 0.2))
	roof.position = Vector3(p.x, gy + hgt + 0.8, p.z)
	if front.x != 0.0:
		roof.rotation.y = PI / 2
		pm.size = Vector3(size.z + 0.6, 1.6, size.x + 0.6)
	add_child(roof)
	_facade(Vector3(p.x, gy, p.z), size, front, col)

func _build_vila_nova() -> void:
	var palette := [Color(0.97, 0.85, 0.35), Color(0.45, 0.7, 0.9), Color(0.95, 0.55, 0.6), Color(0.55, 0.8, 0.5), Color(0.98, 0.95, 0.88), Color(0.95, 0.6, 0.3), Color(0.7, 0.55, 0.85)]
	_road(Vector3(20, 0, 18), Vector3(20, 0, 40), 5.0)
	_road(Vector3(10, 0, 40), Vector3(84, 0, 40), 6.0)
	_road(Vector3(46, 0, 40), Vector3(46, 0, 86), 5.0)
	for x in range(12, 84, 9):
		if absf(x - 20) < 4 or absf(x - 46) < 5:
			continue
		_house(Vector3(x, 0, 33.5), Vector3(0, 0, 1), palette)
		if x < 19 or x > 37:
			if absf(x - 46) >= 6:
				_house(Vector3(x, 0, 46.5), Vector3(0, 0, -1), palette)
	for z in [74, 83]:
		_house(Vector3(39.5, 0, z), Vector3(1, 0, 0), palette)
	_label("VILA NOVA", Vector3(30, ground_y(30, 40) + 4.0, 40), 90, Color(1, 0.95, 0.8))
	# Praça Vila Nova + Mercadinho (vendor)
	var sq := Vector3(28, ground_y(28, 60), 60)
	_box(Vector3(16, 0.24, 14), sq + Vector3(0, 0.08, 0), Color(0.68, 0.6, 0.5), false)
	_mango_tree(sq + Vector3(-5, 0, -4), 1.0)
	_mango_tree(sq + Vector3(5, 0, 4), 0.9)
	for bx in [-3.0, 3.0]:
		_box(Vector3(2.4, 0.5, 0.7), sq + Vector3(bx, 0.35, 3.5), Color(0.45, 0.3, 0.18), true)
	var shop := sq + Vector3(0, 0, -5.5)
	_box(Vector3(6, 3.2, 3.4), shop + Vector3(0, 1.6, -0.6), Color(0.95, 0.75, 0.35))
	var awn := _box(Vector3(6.6, 0.15, 2.2), shop + Vector3(0, 3.1, 1.4), Color(0.2, 0.6, 0.35), false)
	awn.rotation.x = 0.25
	_box(Vector3(5, 1.0, 1.0), shop + Vector3(0, 0.5, 1.4), Color(0.5, 0.35, 0.2))
	_label("MERCADINHO DO SEU JORGE", shop + Vector3(0, 4.0, 1.2), 56, Color(1, 0.95, 0.75))
	_spot(shop + Vector3(0, 0, 3.0), 4.0, "Shop: Mercadinho do Seu Jorge", "vendor", "Seu Jorge")
	_barbershop(sq + Vector3(11.5, 0, -2.0))
	for j in Data.JOBS.get("caceres", []):
		_job_spot(sq + (j.at as Vector3), j)
	# locals rolling on mats around town
	_ambient_mat(sq + Vector3(-4.0, 0, 9.0), 0.4)
	_ambient_mat(sq + Vector3(-20.0, 0, -4.0), 1.9)
	_raid_gate(sq + Vector3(-12.0, 0, 6.0))
	# a gi on a stand by the counter: what's for sale
	if _place_model("gi_mannequin", shop + Vector3(3.6, 0, 1.5), 1.0, -0.35, Vector3(0.9, 1.7, 0.6)):
		_cyl(0.05, 0.05, 0.1, shop + Vector3(3.6, 0.05, 1.5), Color(0.3, 0.3, 0.3), 8)
	# Quadra da Vila (camp)
	var q := Vector3(62, ground_y(62, 66), 66)
	_box(Vector3(20, 0.2, 12), q + Vector3(0, 0.06, 0), Color(0.3, 0.45, 0.55), false)
	_box(Vector3(19, 0.02, 0.15), q + Vector3(0, 0.18, 0), Color(1, 1, 1), false)
	_box(Vector3(0.15, 0.02, 11), q + Vector3(0, 0.18, 0), Color(1, 1, 1), false)
	for gx in [-9.6, 9.6]:
		_box(Vector3(0.15, 1.6, 3.0), q + Vector3(gx, 0.8, 0), Color(0.95, 0.95, 0.95), false)
	for k in 12:
		var fx := -10.5 + k * (21.0 / 11.0)
		_box(Vector3(0.12, 2.6, 0.12), q + Vector3(fx, 1.3, -6.4), Color(0.5, 0.5, 0.5), false)
	_label("QUADRA DA VILA", q + Vector3(0, 3.6, -6.4), 70, Color(1, 0.85, 0.5))
	# Prainha (camp): sand on the riverbank, umbrellas
	var pr := Vector3(-40, 0, 70)
	_box(Vector3(26, 0.16, 16), Vector3(pr.x, ground_y(pr.x, pr.z) + 0.02, pr.z), Color(0.92, 0.84, 0.62), false)
	var umb := [Color(0.95, 0.3, 0.25), Color(0.2, 0.55, 0.9), Color(1, 0.85, 0.2)]
	for k in 3:
		var up := pr + Vector3(-8 + k * 8, 0, -4 + (k % 2) * 7)
		var gy := ground_y(up.x, up.z)
		_cyl(0.06, 0.06, 2.4, Vector3(up.x, gy + 1.2, up.z), Color(0.9, 0.9, 0.9), 6)
		_cyl(0.0, 1.6, 0.6, Vector3(up.x, gy + 2.5, up.z), umb[k], 8)
	_label("PRAINHA DO RIO", Vector3(pr.x, ground_y(pr.x, pr.z) + 3.2, pr.z - 7), 70, Color(1, 0.9, 0.6))
	# Galpão (elite camp): an open-front warehouse gym
	var g := Vector3(59, ground_y(59, -64), -64)
	_box(Vector3(16, 0.2, 10), g + Vector3(0, 0.1, 0), Color(0.55, 0.52, 0.5))
	_box(Vector3(16, 5, 0.4), g + Vector3(0, 2.5, -5), Color(0.6, 0.62, 0.66))
	_box(Vector3(0.4, 5, 10), g + Vector3(-8, 2.5, 0), Color(0.6, 0.62, 0.66))
	_box(Vector3(0.4, 5, 10), g + Vector3(8, 2.5, 0), Color(0.6, 0.62, 0.66))
	_box(Vector3(17, 0.3, 11), g + Vector3(0, 5.15, 0), Color(0.45, 0.47, 0.5), false)
	for x in 6:
		for z in 4:
			var col := Color(0.13, 0.38, 0.26) if (x + z) % 2 == 0 else Color(0.25, 0.25, 0.28)
			_box(Vector3(1.96, 0.08, 1.96), g + Vector3(-5 + x * 2, 0.25, -3 + z * 2), col, false)
	_label("GALPÃO  ·  ELITE", g + Vector3(0, 6.2, 5.2), 80, Color(1, 0.55, 0.35))
	_statue("statue_faixa_preta", g + Vector3(-10.5, 0, 6.5), 0.5, 1.2, "FAIXA PRETA", "Only the elite train here", Color(0.18, 0.18, 0.2))
	# a second vendor at the Feira
	_spot(Vector3(30, 0, -19), 4.0, "Shop: Barraca da Dona Cida", "vendor", "Dona Cida")

# ================================================================ mobs
const MOB_SPREAD := 1.6   # camps cover more ground than their nominal radius
const MOB_GAP := 9.0       # min metres between mobs of one camp at spawn

func _build_mobs() -> void:
	for camp in Loot.CAMPS.get(zone, []):
		var c: Dictionary = camp
		var p: Vector3 = c.pos
		if zone != "caceres":
			_label(Tx.f("%s  ·  Lv %d-%d", [Tx.s(str(c.title)).to_upper(), Data.display_level(float(c.lv[0])), Data.display_level(float(c.lv[1]))]), Vector3(p.x, ground_y(p.x, p.z) + 3.4, p.z - c.radius), 56, Color(1, 0.85, 0.5))
		for i in int(c.count):
			var e := {"npc": null, "camp": c, "rare": false, "t": 0.0}
			mobs.append(e)
			_spawn_mob(e)
		if c.has("rare"):
			var r := {"npc": null, "camp": c, "rare": true, "t": _rng.randf_range(20.0, float(c.rare.respawn))}
			mobs.append(r)

func _spawn_mob(e: Dictionary) -> void:
	var c: Dictionary = e.camp
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var m := Loot.make_mob(c, rng, bool(e.rare))
	var n := Npc.new()
	add_child(n)
	var p: Vector3 = c.pos
	var rad := float(c.radius) * MOB_SPREAD
	n.setup_mob(m, self, p, rad)
	# spread the camp out (WoW-style pulls): keep MOB_GAP metres from the camp's other mobs
	var at := p
	var best := -1.0
	for k in 24:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * rad * 0.9
		var cand := p + Vector3(cos(a) * r, 0, sin(a) * r)
		var near := INF
		for o in mobs:
			if o.npc and is_instance_valid(o.npc) and o.camp == c:
				near = minf(near, Vector2(cand.x, cand.z).distance_to(Vector2(o.npc.position.x, o.npc.position.z)))
		if near >= MOB_GAP:
			at = cand
			break
		if near > best:
			best = near
			at = cand
	n.position = Vector3(at.x, ground_y(at.x, at.z), at.z)
	if player:
		n.set_player(player)
	n.engaged.connect(func(npc): if game_started: mob_engaged.emit(npc))
	e.npc = n

## Called after a fight: a beaten mob despawns and respawns later; a winner walks home.
func mob_done(npc: Npc, beaten: bool) -> void:
	aggro_grace = 6.0
	for e in mobs:
		if e.npc == npc:
			if beaten:
				npc.queue_free()
				e.npc = null
				var c: Dictionary = e.camp
				e.t = float(c.rare.respawn) if bool(e.rare) else float(c.respawn)
			else:
				npc.visible = true
				npc.position = c_home(e)
			return

func c_home(e: Dictionary) -> Vector3:
	var p: Vector3 = e.camp.pos
	return Vector3(p.x, ground_y(p.x, p.z), p.z)

func refresh_mob_tags() -> void:
	for e in mobs:
		if e.npc:
			(e.npc as Npc).refresh_mob_tag()

# ================================================================ San Diego (América do Norte)
## Pacific beach town: chaparral hills to the north, a strip of bungalows and shops, the coast
## highway, a concrete boardwalk, wide sand, a long wooden pier, and sandstone cliffs to the west.
const SOCAL_GYM := Vector3(-18, 0, -40)
const SOCAL_GOLD := Vector2(52, -16)

func _height_socal(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := noise.get_noise_2d(x, z) * 0.5 + 0.45
	h = lerpf(h, 0.35, _ss(30.0, 34.0, z))
	h = lerpf(h, -2.8, _ss(50.0, 62.0, z))
	# Sunset Cliffs: a sandstone shelf on the west coast that drops straight into the Pacific
	var cliff := _ss(-50.0, -60.0, x) * _ss(24.0, 32.0, z)
	h = lerpf(h, 4.2 + noise.get_noise_2d(x * 2.0, z * 2.0) * 0.6, cliff * (1.0 - _ss(54.0, 58.0, z)))
	h = lerpf(h, -2.8, cliff * _ss(56.0, 60.0, z))
	# chaparral hills and canyons inland
	h += _ss(-36.0, -80.0, z) * (5.0 + noise.get_noise_2d(x * 0.6, z * 0.6) * 4.0)
	var e := maxf(absf(x), absf(z))
	h += _ss(82.0, 98.0, e) * 9.0 * (1.0 - _ss(28.0, 40.0, z))
	# flat pads: shuttle stop, the Garage, the Gold League gym
	h = lerpf(h, 0.5, _ss(13.0, 8.0, p.distance_to(Vector2(-82, 6))))
	h = lerpf(h, 0.5, _ss(15.0, 11.0, p.distance_to(Vector2(SOCAL_GYM.x, SOCAL_GYM.z))))
	h = lerpf(h, 0.5, _ss(12.0, 8.0, p.distance_to(SOCAL_GOLD)))
	return h

func _socal_color(x: float, z: float, h: float) -> Color:
	var n := noise.get_noise_2d(x * 3.0 + 100.0, z * 3.0) * 0.5 + 0.5
	if x < -54.0 and z > 26.0 and h > 1.2:
		return Color(0.78, 0.56, 0.36).lerp(Color(0.86, 0.66, 0.44), n)   # sandstone
	if z > 31.0:
		var sand := Color(0.78, 0.66, 0.46).lerp(Color(0.84, 0.72, 0.52), n)
		return sand.lerp(Color(0.72, 0.66, 0.52), _ss(-0.4, -1.3, h))
	if z > 25.5:
		return Color(0.62, 0.6, 0.57)       # boardwalk concrete
	if z > 17.0:
		return Color(0.22, 0.22, 0.24)      # coast highway
	if x > -64.0 and z > -30.0 and h < 2.0:
		var lawn := Color(0.4, 0.55, 0.22).lerp(Color(0.48, 0.6, 0.26), n)
		return lawn if fmod(absf(x) + 4.0, 18.0) < 9.0 and z > 0.0 else Color(0.5, 0.49, 0.47).lerp(Color(0.56, 0.55, 0.52), n)
	return Color(0.5, 0.48, 0.3).lerp(Color(0.6, 0.54, 0.36), n)   # dry chaparral

func _build_socal() -> void:
	noise.seed = 33
	noise.frequency = 0.03
	_rng.seed = 2040
	_static = StaticBody3D.new()
	add_child(_static)
	_blocked = [
		Rect2(-98, -8, 28, 26),     # shuttle stop
		Rect2(-34, -56, 32, 30),    # the Garage
		Rect2(38, -30, 28, 28),     # Gold League gym
		Rect2(-66, -6, 140, 22),    # bungalows + shops
		Rect2(-100, 16, 200, 90),   # highway, boardwalk, beach, sea
		Rect2(18, -20, 24, 18),     # taco trucks
	]
	_build_environment()
	_build_terrain()
	_r_ocean()
	_s_boardwalk()
	_s_town()
	_build_trees()
	_build_ground_detail()
	_build_props()
	_s_beach()
	_s_pier()
	_s_cliffs()
	_s_tacos()
	_s_gold_gym()
	_p_bus_stop(Vector3(-82, 0, 6), "AIRPORT SHUTTLE")
	var g := Vector3(SOCAL_GYM.x, ground_y(SOCAL_GYM.x, SOCAL_GYM.z), SOCAL_GYM.z)
	_gym(g, "THE GARAGE", Color(0.55, 0.57, 0.6))
	_label("THE GARAGE", g + Vector3(0, 3.4, 7.4), 140, Color(0.98, 0.82, 0.3))
	_box(Vector3(10, 1.6, 0.1), g + Vector3(0, 3.4, 7.3), Color(0.15, 0.15, 0.17), false)
	# roll-up doors: the Garage is an old auto shop
	for x in [-6.0, 0.0, 6.0]:
		_box(Vector3(5.2, 1.4, 0.2), g + Vector3(x, 4.2, -7.0), Color(0.75, 0.75, 0.72), false)
	var xs := [-7.0, -3.5, 0.0, 3.5, 7.0]
	for i in Rpg.ATTR_ORDER.size():
		_drill_station(Rpg.ATTR_ORDER[i], g + Vector3(xs[i], 0, 5.0))
	_challenge_board(g + Vector3(-12, 0, 9))
	_comp_board(g + Vector3(12, 0, 9), "socal_open")
	_build_cups()
	_build_landmarks()
	_build_fighters()
	_build_villagers()
	_build_bounds()
	_build_beacon()

## Concrete boardwalk with a low sea wall, palms and a bike lane; cars on the coast highway.
func _s_boardwalk() -> void:
	var px := -52.0
	var palms: Array = []
	while px < 92.0:
		palms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * 6.4), Vector3(px, ground_y(px, 26.6), 26.6)))
		px += 8.0
	_mm("tree_palm", palms)
	for x in range(-52, 96, 12):
		_box(Vector3(11.6, 0.6, 0.5), Vector3(x, ground_y(x, 31.2) + 0.3, 31.2), Color(0.86, 0.84, 0.8))
	# bike lane stripe
	_box(Vector3(146, 0.02, 0.12), Vector3(20, ground_y(20, 29.0) + 0.05, 29.0), Color(0.95, 0.8, 0.2), false)
	var cars := ["sedan", "van", "sedan", "police_car", "sedan", "van", "sedan"]
	for i in cars.size():
		var cx := -60.0 + i * 22.0 + _rng.randf_range(-3, 3)
		var cz := 19.5 if i % 2 == 0 else 23.0
		_place_model(cars[i], Vector3(cx, ground_y(cx, cz), cz), 1.7, PI / 2 if i % 2 == 0 else -PI / 2, Vector3(4.6, 2.0, 2.4))
	_label("THE BOARDWALK", Vector3(0, ground_y(0, 28) + 4.2, 28), 90, Color(1, 0.95, 0.8)).billboard = BaseMaterial3D.BILLBOARD_ENABLED

## Beach bungalows and a few two-storey shops between the hills and the highway.
func _s_town() -> void:
	# beach bungalows, Spanish-revival shops and a surf shop facing the ocean (tools/westbuild/coastal.py)
	var cols := [Color(0.96, 0.94, 0.88), Color(0.62, 0.8, 0.86), Color(0.98, 0.84, 0.66), Color(0.86, 0.92, 0.84), Color(0.95, 0.7, 0.6), Color(0.78, 0.84, 0.96)]
	var stucco := [Color(0.97, 0.95, 0.9), Color(0.96, 0.88, 0.76), Color(0.93, 0.8, 0.72), Color(0.95, 0.93, 0.85)]
	var wood := [Color(0.35, 0.5, 0.6), Color(0.45, 0.32, 0.22), Color(0.3, 0.55, 0.5), Color(0.42, 0.36, 0.3)]
	var pool := ["sd_bungalow", "sd_spanish", "sd_bungalow", "sd_spanish_house", "sd_surfshop", "sd_bungalow", "sd_spanish", "sd_spanish_house"]
	var items: Array = []
	var x := -58.0
	var i := 0
	while x < 34.0:
		var kind: String = pool[i % pool.size()]
		var ab := TownKit.mesh(kind).get_aabb()
		var w := ab.size.x
		if x + w > 34.0:
			break   # leave the east end open (fighters stand there)
		x += w * 0.5
		var zc := 15.2 - ab.end.z
		var pal: Array = cols if kind == "sd_bungalow" else stucco
		_town_building(items, Vector3(x, 0, zc), Vector3(0, 0, 1), pal, kind, 0.0, wood)
		if kind == "sd_surfshop":
			_label("SURF SHOP", Vector3(x, ground_y(x, zc) + 4.75, zc + 4.2), 64, Color(0.1, 0.45, 0.6))
		x += w * 0.5 + _rng.randf_range(1.6, 3.0)
		if i % 4 == 3:
			x += 6.0   # side street up to the hills
		i += 1
	TownKit.build(self, items)
	_label("OCEAN BEACH", Vector3(-20, ground_y(-20, 16) + 8.5, 16), 100, Color(1, 0.92, 0.75)).billboard = BaseMaterial3D.BILLBOARD_ENABLED

func _s_beach() -> void:
	var cols := [Color(0.95, 0.3, 0.25), Color(0.98, 0.8, 0.2), Color(0.2, 0.55, 0.9), Color(0.3, 0.75, 0.4), Color(1, 1, 1)]
	for i in 22:
		var x := _rng.randf_range(-48, 88)
		var z := _rng.randf_range(36, 49)
		if absf(x - 48.0) < 5.0 or Vector2(x, z).distance_to(Vector2(22, 42)) < 5.0 or Vector2(x, z).distance_to(Vector2(36, 40)) < 4.0:
			continue
		var gy := ground_y(x, z)
		_cyl(0.04, 0.04, 2.2, Vector3(x, gy + 1.1, z), Color(0.85, 0.85, 0.85), 5)
		_cyl(0.0, 1.35, 0.5, Vector3(x, gy + 2.2, z), cols[i % cols.size()], 10)
		if i % 3 == 0:
			_box(Vector3(0.8, 0.05, 1.8), Vector3(x + 1.2, gy + 0.05, z + 0.3), cols[(i + 2) % cols.size()], false, _rng.randf())
	# lifeguard towers (Kim's post is the one by the pier)
	var towers: Array = []
	for p in [Vector3(37, 0, 40), Vector3(-30, 0, 41), Vector3(80, 0, 42)]:
		_town_building(towers, p, Vector3(0, 0, 1), [Color(0.3, 0.62, 0.82)], "sd_lifeguard", 0.0, [Color(0.85, 0.8, 0.7)])
	TownKit.build(self, towers)
	_label("LIFEGUARD", Vector3(37, ground_y(37, 40) + 3.95, 40 + 1.0), 44, Color(1, 0.3, 0.25))
	# Tyler's sand mats + surf rack
	_box(Vector3(6, 0.12, 6), Vector3(22, ground_y(22, 42) + 0.06, 42), Color(0.12, 0.2, 0.45), false)
	_animal("crab", Vector3(-20, ground_y(-20, 52), 52), 0.4, 0.3)
	_animal("crab", Vector3(66, ground_y(66, 53), 53), 0.35, 2.0)
	_animal("pug", Vector3(-10, ground_y(-10, 28.5), 28.5), 0.55, 1.2)
	_animal("shiba", Vector3(60, ground_y(60, 28.5), 28.5), 0.85, -2.0)

## Long wooden pier on pilings, out past the surf.
func _s_pier() -> void:
	var x := 48.0
	var deck := Color(0.55, 0.42, 0.3)
	var z := 32.0
	while z < 96.0:
		var top := maxf(ground_y(x, z), WATER_Y) + 2.0
		top = maxf(top, 1.6)
		_box(Vector3(4.6, 0.3, 4.2), Vector3(x, top, z + 2.0), deck)
		for sx in [-2.0, 2.0]:
			var gy := ground_y(x + sx, z + 2.0)
			_cyl(0.16, 0.16, top - gy + 0.2, Vector3(x + sx, (top + gy) * 0.5, z + 2.0), Color(0.36, 0.28, 0.2), 6)
			_box(Vector3(0.12, 0.9, 4.2), Vector3(x + sx * 1.15, top + 0.6, z + 2.0), deck.darkened(0.2), false)
		z += 4.0
	# ramp from the boardwalk up onto the deck
	var r := _box(Vector3(4.6, 0.3, 4.6), Vector3(x, ground_y(x, 30.5) + 0.8, 30.5), deck)
	r.rotation.x = -0.28
	# café at the end
	_box(Vector3(6, 3.0, 5), Vector3(x, 4.6, 92), Color(0.9, 0.9, 0.86))
	_box(Vector3(6.6, 0.3, 5.6), Vector3(x, 6.2, 92), Color(0.2, 0.5, 0.55), false)
	_label("OCEAN BEACH PIER", Vector3(x, 5.6, 34), 80, Color(1, 1, 1, 0.95)).billboard = BaseMaterial3D.BILLBOARD_ENABLED

func _s_cliffs() -> void:
	var c := Vector3(-72, ground_y(-72, 46), 46)
	# a bench on the edge to watch the sunset, a few rocks
	_prop("bench", c.x + 2, c.z - 3, PI, Vector3(1.8, 0.8, 0.5))
	for i in 7:
		var a := _rng.randf() * TAU
		var rp := c + Vector3(cos(a) * _rng.randf_range(4, 14), 0, sin(a) * _rng.randf_range(3, 8))
		_box(Vector3(1.4, 0.9, 1.1) * _rng.randf_range(0.7, 1.5), Vector3(rp.x, ground_y(rp.x, rp.z) + 0.3, rp.z), Color(0.74, 0.52, 0.34), true, _rng.randf())
	_label("SUNSET CLIFFS", c + Vector3(0, 3.6, 0), 80, Color(1, 0.8, 0.55)).billboard = BaseMaterial3D.BILLBOARD_ENABLED

## Taco Truck Row: three food trucks, picnic tables and string lights.
func _s_tacos() -> void:
	var c := Vector3(30, ground_y(30, -12), -12)
	_box(Vector3(22, 0.12, 14), c + Vector3(0, 0.05, 0), Color(0.36, 0.36, 0.38), false)
	var tc := [Color(0.95, 0.85, 0.3), Color(0.9, 0.35, 0.3), Color(0.3, 0.7, 0.6)]
	for i in 3:
		var p := c + Vector3(-7 + i * 7, 0, -4.5)
		_box(Vector3(5.0, 2.6, 2.4), p + Vector3(0, 1.6, 0), tc[i])
		_box(Vector3(3.0, 0.9, 0.1), p + Vector3(0, 2.1, 1.22), Color(0.15, 0.15, 0.17), false)
		var aw := _box(Vector3(3.4, 0.08, 1.0), p + Vector3(0, 2.75, 1.6), Color(0.95, 0.95, 0.9), false)
		aw.rotation.x = 0.3
		for wx in [-1.6, 1.6]:
			_cyl(0.35, 0.35, 0.3, p + Vector3(wx, 0.35, 1.25), Color(0.1, 0.1, 0.1), 10)
	for i in 4:
		_prop("bar_table", c.x - 6 + i * 4, c.z + 2.5, _rng.randf() * TAU)
	for i in 8:
		var bulb := MeshInstance3D.new()
		bulb.mesh = _mk_sphere(0.12, 0.24)
		bulb.material_override = DayNight.lamp_material()
		bulb.position = c + Vector3(-9 + i * 2.5, 3.4 - sin(i * 0.4) * 0.3, 0.5)
		add_child(bulb)
	_label("TACO TRUCK ROW", c + Vector3(0, 4.6, -4.5), 80, Color(1, 0.85, 0.45)).billboard = BaseMaterial3D.BILLBOARD_ENABLED

## Gold League USA: a franchise box gym with a gold sign (and its elite members outside).
func _s_gold_gym() -> void:
	var c := Vector3(SOCAL_GOLD.x, ground_y(SOCAL_GOLD.x, SOCAL_GOLD.y), SOCAL_GOLD.y)
	_box(Vector3(18, 6, 10), c + Vector3(0, 3, -4), Color(0.16, 0.16, 0.18))
	_box(Vector3(18.4, 0.5, 10.4), c + Vector3(0, 6.25, -4), Color(0.86, 0.68, 0.16), false)
	_box(Vector3(14, 2.4, 0.1), c + Vector3(0, 2.2, 1.05), Color(0.25, 0.35, 0.42), false)
	_label("GOLD LEAGUE USA", c + Vector3(0, 7.4, 1.2), 110, Color(1, 0.82, 0.25))
	# parking lot in front
	_box(Vector3(22, 0.1, 12), c + Vector3(0, 0.04, 8), Color(0.3, 0.3, 0.32), false)
	for k in 6:
		_box(Vector3(0.12, 0.02, 4.5), c + Vector3(-9 + k * 3.6, 0.1, 9), Color(0.95, 0.95, 0.95), false)

# ================================================================ Team USA zones
## A gym on its own pad with the usual drill stations, challenge board and competition board.
func _usa_gym(c2: Vector2, title: String, wall: Color, comp: String) -> Vector3:
	var g := Vector3(c2.x, ground_y(c2.x, c2.y), c2.y)
	_gym(g, title, wall, true)
	_label(title, g + Vector3(0, 6.0, 7.6), 100, Color(0.98, 0.82, 0.3))
	var xs := [-7.0, -3.5, 0.0, 3.5, 7.0]
	for i in Rpg.ATTR_ORDER.size():
		_drill_station(Rpg.ATTR_ORDER[i], g + Vector3(xs[i], 0, 5.0))
	_challenge_board(g + Vector3(-12, 0, 9))
	_comp_board(g + Vector3(12, 0, 9), comp)
	return g

func _gator(p: Vector3) -> void:
	var gy := maxf(ground_y(p.x, p.z), -0.4)
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 2.6
	body.mesh = cm
	body.material_override = _mat(Color(0.18, 0.22, 0.13))
	body.rotation = Vector3(PI / 2, _rng.randf() * TAU, 0)
	body.position = Vector3(p.x, gy + 0.05, p.z)
	body.scale = Vector3(1, 1, 0.5)
	add_child(body)
	var lab := _label("gator", Vector3(p.x, gy + 1.0, p.z), 36, Color(1, 1, 1, 0.8))
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED

# ---------------------------------------------------------------- Dry Creek, Texas (Lv 1-10)
const TX_GYM := Vector2(0, -52)

func creek_x(z: float) -> float:
	return -63.0 + sin(z * 0.04) * 4.0

func _height_texas(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 1.6 + 0.3
	var town := 1.0 - _ss(36.0, 58.0, maxf(absf(x) * 0.85, absf(z + 12.0) * 0.8))
	h *= 1.0 - town * 0.9
	# rolling hill country rising to the edges (open to the east where the highway leaves)
	var e := maxf(absf(x), absf(z))
	var gap := _ss(9.0, 4.0, absf(z)) * _ss(55.0, 70.0, x)
	h += _ss(78.0, 98.0, e) * 12.0 * (1.0 - gap)
	# Dry Creek: limestone banks and a deep swimming hole
	# a dry, white limestone bed most of the year; water only stands in the swimming hole
	var d := absf(x - creek_x(z))
	h = lerpf(h, -1.5 + noise.get_noise_2d(x * 4.0, z * 4.0) * 0.25, _ss(10.0, 4.5, d))
	h = lerpf(h, -3.2, _ss(10.0, 4.0, Vector2(x, z).distance_to(Vector2(creek_x(6.0), 6.0))))
	# flat pads: gym, rodeo grounds, stadium
	h = lerpf(h, 0.3, _ss(15.0, 11.0, Vector2(x, z).distance_to(TX_GYM)))
	h = lerpf(h, 0.3, _ss(20.0, 15.0, Vector2(x, z).distance_to(Vector2(52, 40))))
	h = lerpf(h, 0.3, _ss(16.0, 12.0, Vector2(x, z).distance_to(Vector2(62, 68))))
	return h

func _texas_color(x: float, z: float, h: float) -> Color:
	var n := noise.get_noise_2d(x * 3.0 + 100.0, z * 3.0) * 0.5 + 0.5
	if h < -0.6:
		return Color(0.8, 0.76, 0.64).lerp(Color(0.86, 0.83, 0.74), _ss(-0.9, -1.5, h) * n)   # white limestone creek bed
	if Vector2(x, z).distance_to(Vector2(0, 8)) < 13.0:
		return Color(0.36, 0.52, 0.22).lerp(Color(0.42, 0.58, 0.26), n)   # courthouse lawn
	if Vector2(x, z).distance_to(Vector2(52, 40)) < 15.0:
		return Color(0.62, 0.5, 0.36).lerp(Color(0.68, 0.56, 0.4), n)   # arena dirt
	var g := Color(0.66, 0.58, 0.32).lerp(Color(0.56, 0.56, 0.3), n)   # golden prairie, greener in the draws
	if h > 4.0:
		g = g.lerp(Color(0.5, 0.48, 0.34), _ss(4.0, 10.0, h))
	return g

func _build_texas() -> void:
	noise.seed = 41
	noise.frequency = 0.03
	_rng.seed = 2050
	_static = StaticBody3D.new()
	add_child(_static)
	_blocked = [
		Rect2(-16, -2, 32, 22),     # square
		Rect2(-12, -30, 24, 18),    # courthouse
		Rect2(-14, -66, 28, 26),    # gym
		Rect2(-56, -10, 130, 7),    # Main Street
		Rect2(-56, -16, 130, 20),   # storefronts
		Rect2(30, 22, 42, 38),      # rodeo
		Rect2(48, 54, 30, 26),      # stadium lot
		Rect2(68, -12, 30, 24),     # bus stop
		Rect2(40, -74, 30, 26),     # oilfield
		Rect2(20, -34, 22, 20),     # feed store
		Rect2(30, -50, 18, 18),     # water tower
	]
	_build_environment()
	_build_terrain()
	var mi := MeshInstance3D.new()
	mi.mesh = EnvShaders.water_plane(Vector2(30, 30), 3.0)
	mi.material_override = EnvShaders.water(Color(0.04, 0.3, 0.3), Color(0.25, 0.65, 0.6, 0.85), 0.04, 0.12, Vector2(0.0, 0.2))
	mi.position = Vector3(creek_x(6.0), -2.0, 6.0)   # the swimming hole (spring-fed, clear and green)
	add_child(mi)
	_tx_town()
	_tx_rodeo()
	_tx_outskirts()
	_build_trees()
	_build_ground_detail()
	_build_props()
	_p_bus_stop(Vector3(80, 0, 0), "GREYHOUND")
	var g := _usa_gym(TX_GYM, "LONE STAR BJJ", Color(0.78, 0.72, 0.6), "dry_creek_open")
	_box(Vector3(0.1, 2.2, 3.4), g + Vector3(-9.3, 2.6, 0), Color(0.75, 0.15, 0.15), false)   # flag on the wall
	_box(Vector3(0.11, 0.7, 1.2), g + Vector3(-9.31, 3.3, -1.1), Color(0.15, 0.25, 0.6), false)
	_build_cups()
	_build_landmarks()
	_build_fighters()
	_build_villagers()
	_build_bounds()
	_build_beacon()

func _tx_storefront(x: float, z: float, front: float, col: Color, sign: String) -> void:
	var gy := ground_y(x, z)
	var w := _rng.randf_range(6.0, 7.5)
	var h := _rng.randf_range(3.6, 4.6)
	_box(Vector3(w, h, 7), Vector3(x, gy + h / 2.0, z), col)
	# western false front, taller than the roof
	_box(Vector3(w + 0.2, 1.6, 0.3), Vector3(x, gy + h + 0.6, z + front * 3.55), col.darkened(0.12), false)
	_box(Vector3(w * 0.75, 1.0, 0.1), Vector3(x, gy + 1.6, z + front * 3.56), Color(0.22, 0.3, 0.38), false)
	# wooden porch roof
	_box(Vector3(w, 0.15, 1.8), Vector3(x, gy + 2.9, z + front * 4.4), Color(0.45, 0.32, 0.2), false)
	for sx in [-w / 2.0 + 0.3, w / 2.0 - 0.3]:
		_box(Vector3(0.15, 2.9, 0.15), Vector3(x + sx, gy + 1.45, z + front * 5.2), Color(0.45, 0.32, 0.2), false)
	if sign != "":
		_label(sign, Vector3(x, gy + h + 0.6, z + front * 3.75), 48, Color(1, 0.95, 0.85), 0.0 if front > 0 else PI)

## Western kit colours: weathered paint on clapboard, and door / shutter colours.
const TX_PAINT := [Color(0.86, 0.78, 0.62), Color(0.62, 0.7, 0.74), Color(0.92, 0.9, 0.84), Color(0.74, 0.52, 0.38), Color(0.6, 0.66, 0.52), Color(0.85, 0.7, 0.48)]
const TX_WOOD := [Color(0.42, 0.3, 0.2), Color(0.34, 0.25, 0.18), Color(0.46, 0.4, 0.33), Color(0.38, 0.28, 0.2)]

func _tx_town() -> void:
	# Main Street and the side street down to the square
	_road(Vector3(-52, 0, -7), Vector3(74, 0, -7), 6.0)
	_road(Vector3(0, 0, -7), Vector3(0, 0, 20), 5.0)
	var items: Array = []
	# south side of Main Street: false-front stores and brick blocks facing the street
	var signs := ["HARDWARE", "SALOON", "BOOTS", "", "POST OFFICE", "PAWN", "BAKERY", "", "BARBER", "TACOS", "GENERAL STORE", "PHARMACY"]
	var i := 0
	for x in range(-46, 64, 9):
		if absf(x) < 12 or absf(x - 30) < 8:
			continue
		if x == 17:
			i += 1
			continue   # keep the square open to the east (the quartermaster stands there)
		var kind: String = ["tx_store", "tx_brick", "tx_store", "tx_store_plain"][i % 4]
		var zc := -3.6 + TownKit.mesh(kind).get_aabb().end.z   # boardwalk edge on the sidewalk
		_town_building(items, Vector3(x, 0, zc), Vector3(0, 0, -1), TX_PAINT, kind, 0.0, TX_WOOD)
		if signs[i % signs.size()] != "":
			var sh: float = {"tx_store": 5.15, "tx_store_plain": 4.75, "tx_brick": 8.05}[kind]
			var face: float = {"tx_store": 5.3, "tx_store_plain": 4.8, "tx_brick": 5.62}[kind]
			_label(signs[i % signs.size()], Vector3(x, ground_y(x, zc) + sh, zc - face), 52, Color(0.98, 0.93, 0.8) if kind != "tx_brick" else Color(0.95, 0.88, 0.65), PI)
		i += 1
	# north side, west of the courthouse
	for x in [-44.0, -35.0]:
		var kind: String = "tx_store" if x < -40.0 else "tx_brick"
		_town_building(items, Vector3(x, 0, -10.4 - TownKit.mesh(kind).get_aabb().end.z), Vector3(0, 0, 1), TX_PAINT, kind, 0.0, TX_WOOD)
	# the courthouse: limestone, portico and clock tower over the square
	var c := Vector3(0, ground_y(0, -21), -21)
	_town_building(items, Vector3(0, 0, -21), Vector3(0, 0, 1), [Color.WHITE], "tx_courthouse", 0.0)
	_label("DRY CREEK COUNTY COURTHOUSE", c + Vector3(0, 8.5, 10.36), 50, Color(0.3, 0.24, 0.16))
	# Earl's BBQ (a plain store with a smoker out back) and the Feed & Tack barn
	var bb := Vector3(-24, ground_y(-24, -20), -20)
	_town_building(items, Vector3(-24, 0, -21), Vector3(0, 0, 1), [Color(0.55, 0.36, 0.26)], "tx_store_plain", 0.0, TX_WOOD)
	_cyl(0.7, 0.7, 2.4, bb + Vector3(4.2, 1.0, 3.0), Color(0.12, 0.12, 0.12), 10)   # smoker
	_cyl(0.18, 0.18, 2.2, bb + Vector3(4.2, 3.0, 3.0), Color(0.12, 0.12, 0.12), 6)
	_label("EARL'S BBQ", bb + Vector3(0, 4.7, 3.6), 56, Color(1, 0.75, 0.4))
	var fd := Vector3(30, ground_y(30, -26), -26)
	_town_building(items, Vector3(30, 0, -26), Vector3(0, 0, 1), [Color(0.62, 0.15, 0.12)], "tx_barn", 0.0, [Color(0.5, 0.35, 0.22)])
	for k in 4:
		_cyl(0.7, 0.7, 1.3, fd + Vector3(-5 + k * 1.6, 0.7, 9.6), Color(0.85, 0.72, 0.38), 10)
	_label("FEED & TACK", fd + Vector3(0, 5.4, 8.25), 64, Color(1, 0.95, 0.85))
	# water tower over the rooftops, with the town's name on the tank
	var wt := Vector3(40, ground_y(40, -42), -42)
	_town_building(items, Vector3(40, 0, -42), Vector3(0, 0, 1), [Color.WHITE], "tx_watertower", 0.0)
	var tl := _label("DRY CREEK", wt + Vector3(0, 12.2, 3.36), 120, Color(0.15, 0.25, 0.55))
	tl.no_depth_test = false
	# ranch houses on the south side, porches to the street
	for x in [-44.0, -34.0, 30.0, 40.0]:
		_town_building(items, Vector3(x, 0, 31), Vector3(0, 0, -1), TX_PAINT, "tx_house" if int(x) % 20 != 0 else "tx_house_small", 0.0, TX_WOOD)
	# the white chapel on the rise to the north-west: you can see its steeple from the square
	_town_building(items, Vector3(-36, 0, -78), Vector3(0, 0, 1), [Color(0.95, 0.95, 0.92)], "tx_chapel", 0.0, [Color(0.45, 0.3, 0.2)])
	# a ranch out past the creek bed: barn, house, windmill
	_town_building(items, Vector3(24, 0, 80), Vector3(-1, 0, 0), [Color(0.6, 0.14, 0.12)], "tx_barn", 0.0, [Color(0.5, 0.35, 0.22)])
	_town_building(items, Vector3(8, 0, 82), Vector3(0, 0, -1), TX_PAINT, "tx_house_small", 0.0, TX_WOOD)
	for wm in [Vector2(32, 66), Vector2(-74, -72), Vector2(-82, 34), Vector2(84, -40)]:
		var wy := ground_y(wm.x, wm.y)
		items.append({"kind": "tx_windmill", "xform": Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(wm.x, wy - 0.05, wm.y)), "wall": Color.WHITE, "wood": Color(0.45, 0.32, 0.2)})
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 1.2
		sh.height = 8.0
		cs.shape = sh
		cs.position = Vector3(wm.x, wy + 4.0, wm.y)
		_static.add_child(cs)
	TownKit.build(self, items)
	_tx_fences()
	_tx_limestone()
	# the square: gazebo and benches
	var sq := Vector3(0, ground_y(0, 8), 8)
	for k in 8:
		var a := k * TAU / 8.0
		_cyl(0.12, 0.12, 2.6, sq + Vector3(cos(a) * 2.6, 1.3, sin(a) * 2.6), Color(0.95, 0.95, 0.92), 6)
	_cyl(0.0, 3.4, 1.4, sq + Vector3(0, 3.3, 0), Color(0.75, 0.2, 0.2), 8)
	_box(Vector3(6, 0.3, 6), sq + Vector3(0, 0.15, 0), Color(0.9, 0.88, 0.84))
	for p in [Vector2(-9, 4), Vector2(9, 4), Vector2(-9, 13), Vector2(9, 13)]:
		_prop("bench", p.x, p.y, 0.0 if p.y < 8 else PI, Vector3(1.8, 0.8, 0.5))
	_label("COURTHOUSE SQUARE", sq + Vector3(0, 5.2, 0), 70, Color(1, 0.95, 0.8)).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Dottie's diner and Earl's BBQ
	var dn := Vector3(20, ground_y(20, 20), 20)
	_box(Vector3(9, 3.4, 5), dn + Vector3(0, 1.7, 0), Color(0.85, 0.85, 0.88))
	_box(Vector3(9.2, 0.4, 5.2), dn + Vector3(0, 3.6, 0), Color(0.85, 0.3, 0.35), false)
	_box(Vector3(7, 1.2, 0.1), dn + Vector3(0, 1.8, -2.55), Color(0.25, 0.35, 0.45), false)
	_label("DOTTIE'S DINER", dn + Vector3(0, 4.4, -2.6), 56, Color(1, 0.4, 0.45), PI)
	# swimming hole: rope swing tree and a lifeguard chair
	var sh := Vector3(creek_x(6.0) + 8.0, 0, 6.0)
	_mango_tree(Vector3(sh.x, ground_y(sh.x, sh.z), sh.z - 6.0), 1.2, "tree_liveoak", Color(0.24, 0.34, 0.16))
	_box(Vector3(0.05, 4.0, 0.05), Vector3(sh.x - 2.0, ground_y(sh.x, sh.z - 6) + 3.0, sh.z - 6.0), Color(0.75, 0.65, 0.45), false)
	var ch := Vector3(-50, ground_y(-50, -12), -12)
	for sx in [-0.6, 0.6]:
		_box(Vector3(0.12, 2.2, 0.12), ch + Vector3(sx, 1.1, 0), Color(0.95, 0.95, 0.95), false)
	_box(Vector3(1.4, 0.15, 1.0), ch + Vector3(0, 2.2, 0), Color(0.85, 0.2, 0.2), false)
	_animal("pug", Vector3(4, ground_y(4, 14), 14), 0.55, 1.2)
	_animal("cat", Vector3(-20, ground_y(-20, -14), -14), 0.45, 0.5)

## Post-and-rail ranch fences along the roads out of town (the Hill Country look).
func _tx_fences() -> void:
	var runs := [[Vector2(-30, 44), Vector2(30, 44)], [Vector2(-60, 44), Vector2(-40, 44)], [Vector2(76, 10), Vector2(96, 10)],
		[Vector2(76, -12), Vector2(96, -12)], [Vector2(-12, 60), Vector2(-12, 92)], [Vector2(12, 60), Vector2(12, 70)], [Vector2(-90, -50), Vector2(-60, -90)]]
	var wood := Color(0.48, 0.38, 0.28)
	for r in runs:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var n := maxi(1, int(a.distance_to(b) / 3.0))
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			if _is_blocked(p.x, p.y, 0.5):
				continue
			var gy := ground_y(p.x, p.y)
			_box(Vector3(0.18, 1.3, 0.18), Vector3(p.x, gy + 0.65, p.y), wood, false)
			if k < n:
				var q := a.lerp(b, float(k + 1) / n)
				if _is_blocked(q.x, q.y, 0.5):
					continue
				var m := (p + q) * 0.5
				var gm := (gy + ground_y(q.x, q.y)) * 0.5
				for hgt in [0.55, 1.05]:
					var rail := _box(Vector3(0.08, 0.12, p.distance_to(q) + 0.1), Vector3(m.x, gm + hgt, m.y), wood.lightened(0.08), false)
					rail.rotation.y = atan2(q.x - p.x, q.y - p.y)

## Pale limestone ledges and boulders on the hills and along the creek (Hill Country bones).
func _tx_limestone() -> void:
	var xf := {"rock_large": [], "rock_tall": [], "rock_small": []}
	var placed := 0
	var tries := 0
	while placed < 70 and tries < 1500:
		tries += 1
		var x := _rng.randf_range(-94, 94)
		var z := _rng.randf_range(-94, 94)
		if _is_blocked(x, z, 3.0) or Vector2(x, z).distance_to(Vector2(0, -12)) < 40.0:
			continue
		var gy := ground_y(x, z)
		var creek := absf(x - creek_x(z)) < 13.0
		var hill := maxf(absf(x), absf(z)) > 74.0
		if not creek and not hill and _rng.randf() > 0.25:
			continue
		var kind: String = ["rock_large", "rock_tall", "rock_small", "rock_large"][_rng.randi() % 4]
		var sc := _rng.randf_range(1.6, 3.4) * (1.4 if hill else 1.0)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc * 1.4, sc * 0.6, sc))
		xf[kind].append(Transform3D(b, Vector3(x, gy - 0.3, z)))
		placed += 1
	for k in xf:
		_mm(k, xf[k], Color(0, 0, 0, 0))

func _tx_rodeo() -> void:
	var r := Vector3(52, ground_y(52, 40), 40)
	for k in 28:
		var a := k * TAU / 28.0
		var p := r + Vector3(cos(a) * 13.0, 0, sin(a) * 9.0)
		_box(Vector3(0.2, 1.6, 0.2), Vector3(p.x, ground_y(p.x, p.z) + 0.8, p.z), Color(0.5, 0.36, 0.22), false)
		var a2 := (k + 1) * TAU / 28.0
		var p2 := r + Vector3(cos(a2) * 13.0, 0, sin(a2) * 9.0)
		if k % 7 != 0:
			var mid := (p + p2) * 0.5
			var rail := _box(Vector3(0.1, 0.12, p.distance_to(p2)), Vector3(mid.x, ground_y(mid.x, mid.z) + 1.3, mid.z), Color(0.55, 0.4, 0.25), false)
			rail.rotation.y = atan2(p2.x - p.x, p2.z - p.z)
	# bleachers
	for row in 4:
		_box(Vector3(14, 0.3, 1.0), r + Vector3(0, 0.5 + row * 0.6, -12.0 - row * 1.0), Color(0.75, 0.75, 0.78), true)
	_label("DRY CREEK RODEO", r + Vector3(0, 4.6, -14.5), 90, Color(1, 0.85, 0.5))
	_animal("deer", Vector3(70, ground_y(70, 24), 24), 1.5, 0.4)

func _tx_outskirts() -> void:
	# Friday-night football: stadium lot
	var st := Vector3(62, ground_y(62, 68), 68)
	_box(Vector3(22, 0.1, 14), st + Vector3(0, 0.04, 0), Color(0.3, 0.3, 0.32), false)
	for k in 3:
		_place_model(["truck", "sedan", "truck"][k], st + Vector3(-7 + k * 7, 0, -3), 1.7, 0.2 * k, Vector3(4.6, 2.0, 2.4))
	for row in 5:
		_box(Vector3(20, 0.3, 1.0), st + Vector3(0, 0.6 + row * 0.7, 9.0 + row * 1.0), Color(0.75, 0.75, 0.78), true)
	_cyl(0.2, 0.2, 14.0, st + Vector3(-11, 7.0, 6.0), Color(0.6, 0.6, 0.62), 6)
	_cyl(0.2, 0.2, 14.0, st + Vector3(11, 7.0, 6.0), Color(0.6, 0.6, 0.62), 6)
	_label("GO MUSTANGS", st + Vector3(0, 5.6, 13.6), 90, Color(0.95, 0.3, 0.3), PI)
	# oilfield: pump jacks
	var of := Vector3(58, ground_y(58, -62), -62)
	for k in 3:
		var p := of + Vector3(-8 + k * 8, 0, -4 + (k % 2) * 6)
		var gy := ground_y(p.x, p.z)
		_box(Vector3(1.4, 2.4, 0.6), Vector3(p.x, gy + 1.2, p.z), Color(0.25, 0.25, 0.28))
		var beam := _box(Vector3(6.0, 0.5, 0.5), Vector3(p.x, gy + 2.7, p.z), Color(0.35, 0.36, 0.4), false)
		beam.rotation.z = 0.15 * (1 if k % 2 == 0 else -1)
		_box(Vector3(0.6, 1.4, 0.8), Vector3(p.x + 3.0, gy + 2.2, p.z), Color(0.25, 0.25, 0.28), false)
	_label("PUMP JACKS", of + Vector3(0, 4.4, 0), 70, Color(1, 0.85, 0.5)).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# creek bed camp: tubes and a cooler
	var cb := Vector3(-34, 0, 66)
	for k in 3:
		var tp := cb + Vector3(-6 + k * 5, 0, (k % 2) * 4)
		var tube := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.35
		tm.outer_radius = 0.75
		tube.mesh = tm
		tube.material_override = _mat([Color(0.95, 0.3, 0.25), Color(0.2, 0.55, 0.9), Color(1, 0.85, 0.2)][k])
		tube.position = Vector3(tp.x, ground_y(tp.x, tp.z) + 0.2, tp.z)
		add_child(tube)

# ---------------------------------------------------------------- Saw Grass Landing, Everglades (Lv 11-20)
const GL_PIT := Vector2(60, 52)

func _height_everglades(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 0.9 + 0.1
	var n2 := noise.get_noise_2d(x * 0.6 + 300.0, z * 0.6 - 120.0)
	h = lerpf(h, -0.9, _ss(-0.15, -0.32, n2))   # sloughs everywhere
	for lg in [[Vector2(42, -54), 14.0], [Vector2(-10, 46), 12.0], [Vector2(70, 0), 10.0]]:
		h = lerpf(h, -0.9, _ss(lg[1], lg[1] - 5.0, Vector2(x, z).distance_to(lg[0])))
	for fl in [[GL_PIT, 17.0], [Vector2(-40, 26), 15.0], [Vector2(-18, -48), 10.0], [Vector2(-82, -4), 11.0], [Vector2(10, 20), 10.0], [Vector2(30, -64), 10.0], [Vector2(-52, -36), 10.0], [Vector2(-56, 62), 9.0], [Vector2(36, -34), 6.0], [Vector2(-62, -72), 13.0]]:
		h = lerpf(h, 0.25, _ss(fl[1], fl[1] - 4.0, Vector2(x, z).distance_to(fl[0])))
	h = lerpf(h, 0.3, _ss(5.0, 3.0, absf(z + 4.0)))   # Tamiami Trail on its causeway
	var e := maxf(absf(x), absf(z))
	h += _ss(84.0, 98.0, e) * 6.0
	return h

func _everglades_color(x: float, z: float, h: float) -> Color:
	var n := noise.get_noise_2d(x * 3.0 + 100.0, z * 3.0) * 0.5 + 0.5
	if absf(z + 4.0) < 2.8:
		return Color(0.28, 0.28, 0.3)
	var g := Color(0.5, 0.52, 0.26).lerp(Color(0.58, 0.56, 0.3), n)   # sawgrass
	if h < -0.2:
		g = g.lerp(Color(0.3, 0.27, 0.18), _ss(-0.2, -0.6, h))
	if Vector2(x, z).distance_to(Vector2(10, 20)) < 10.0:
		g = Color(0.26, 0.38, 0.16)   # hammock under the trees
	return g

func _build_everglades() -> void:
	noise.seed = 52
	noise.frequency = 0.028
	_rng.seed = 2051
	_static = StaticBody3D.new()
	add_child(_static)
	_blocked = [
		Rect2(-92, -14, 22, 20),   # bus stop
		Rect2(44, 38, 34, 30),     # gator pit
		Rect2(-56, 12, 32, 30),    # fish camp
		Rect2(-28, -58, 20, 20),   # ranger station
		Rect2(28, -48, 22, 28),    # dock and its path
		Rect2(-100, -7, 200, 6),   # the trail
		Rect2(-74, -86, 24, 26),   # the gold compound
	]
	_build_environment()
	_build_terrain()
	var water := MeshInstance3D.new()
	water.mesh = EnvShaders.water_plane(Vector2(200, 200), 4.0)
	water.material_override = EnvShaders.water(Color(0.07, 0.13, 0.09), Color(0.2, 0.3, 0.18, 0.86), 0.03, 0.25)
	water.position = Vector3(0, -0.35, 0)
	add_child(water)
	_road(Vector3(-96, 0, -4), Vector3(96, 0, -4), 5.0)
	_build_trees()
	_build_ground_detail()
	_build_props()
	_p_bus_stop(Vector3(-82, 0, -4), "TAMIAMI TRAIL")
	var g := _usa_gym(GL_PIT, "THE GATOR PIT", Color(0.6, 0.62, 0.64), "glades_open")
	# corrugated tin roof stripes + big fans
	for k in 7:
		_box(Vector3(19, 0.05, 0.4), g + Vector3(0, 5.45, -6 + k * 2.0), Color(0.5, 0.52, 0.54), false)
	for sx in [-8.6, 8.6]:
		var fan := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.7
		tm.outer_radius = 0.85
		fan.mesh = tm
		fan.material_override = _mat(Color(0.2, 0.2, 0.22))
		fan.position = g + Vector3(sx, 3.2, 0)
		fan.rotation.z = PI / 2
		add_child(fan)
	_gl_dock()
	_gl_compound()
	_gl_fishcamp()
	_gl_ranger()
	_gl_hammock()
	for p in [Vector3(1, 0, 40), Vector3(-14, 0, 50), Vector3(40, 0, -56), Vector3(48, 0, -48), Vector3(70, 0, 4), Vector3(66, 0, -4)]:
		_gator(p)
	for p in [Vector3(-2, 0, 12), Vector3(24, 0, 26)]:
		_animal("deer", Vector3(p.x, ground_y(p.x, p.z), p.z), 1.4, _rng.randf() * TAU)
	for p in [Vector3(-6, 0, 30), Vector3(36, 0, -46)]:
		_animal("frog", Vector3(p.x, maxf(ground_y(p.x, p.z), -0.3), p.z), 0.25, _rng.randf() * TAU)
	_label("THE EVERGLADES", Vector3(0, 6.0, -4), 110, Color(0.85, 1, 0.8)).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_build_cups()
	_build_landmarks()
	_build_fighters()
	_build_villagers()
	_build_bounds()
	_build_beacon()

func _gl_dock() -> void:
	var c := Vector3(38, 0, -40)
	for k in 5:
		_box(Vector3(3.0, 0.25, 2.2), Vector3(c.x, 0.1, c.z - 2.0 - k * 2.2), Color(0.5, 0.4, 0.3))
		for sx in [-1.4, 1.4]:
			_cyl(0.12, 0.12, 1.6, Vector3(c.x + sx, -0.6, c.z - 2.0 - k * 2.2), Color(0.35, 0.28, 0.2), 6)
	var boats: Array = []
	for k in 3:
		var b := Vector3(c.x + (-3.6 if k % 2 == 0 else 3.6), -0.42, c.z - 4.0 - k * 3.4)
		boats.append({"kind": "gl_airboat", "xform": Transform3D(Basis(Vector3.UP, PI + (k - 1) * 0.08), b), "wall": Color.WHITE,
			"wood": [Color(0.75, 0.2, 0.15), Color(0.2, 0.45, 0.7), Color(0.9, 0.75, 0.2)][k]})
	TownKit.build(self, boats)
	_label("AIRBOAT TOURS", c + Vector3(0, 3.0, 1.0), 70, Color(1, 0.9, 0.5)).billboard = BaseMaterial3D.BILLBOARD_ENABLED

## The Gold Compound: Gunnar Sterling's gated training camp in the swamp (raid entrance).
func _gl_compound() -> void:
	var c := Vector3(-62, ground_y(-62, -74), -74)
	_box(Vector3(14, 4.5, 8), c + Vector3(0, 2.25, -4), Color(0.16, 0.16, 0.18))
	_box(Vector3(14.4, 0.4, 8.4), c + Vector3(0, 4.7, -4), Color(0.86, 0.68, 0.16), false)
	for k in 9:
		_box(Vector3(0.12, 2.4, 0.12), c + Vector3(-8 + k * 2.0, 1.2, 4.0), Color(0.5, 0.5, 0.52), false)
	_box(Vector3(16, 0.08, 0.05), c + Vector3(0, 2.2, 4.0), Color(0.55, 0.55, 0.58), false)
	_label("STERLING", c + Vector3(0, 5.6, 0.2), 90, Color(1, 0.82, 0.25))
	_raid_gate(c + Vector3(0, 0, 7.0), "THE GOLD COMPOUND", "Raid: The Gold Compound (you + 4 partners)", Color(1, 0.82, 0.3))

func _gl_fishcamp() -> void:
	var c := Vector3(-40, ground_y(-40, 26), 26)
	var items: Array = []
	var cols := [Color(0.55, 0.68, 0.7), Color(0.85, 0.82, 0.7), Color(0.62, 0.74, 0.62)]
	for k in 3:
		var p := c + Vector3(-9 + k * 9, 0, -7 + (k % 2) * 12)
		_town_building(items, p, Vector3(0, 0, 1) if k % 2 == 0 else Vector3(0, 0, -1), [cols[k]], "gl_shack", 0.0, [Color(0.4, 0.3, 0.22)])
	_town_building(items, c + Vector3(9, 0, 9), Vector3(-1, 0, 0), [Color.WHITE], "gl_chickee", 0.0, [Color(0.4, 0.3, 0.22)])
	TownKit.build(self, items)
	_place_model("campfire", c + Vector3(0, 0, 2), 3.0)
	_label("FISH CAMP", c + Vector3(0, 6.2, 0), 80, Color(1, 0.9, 0.6)).billboard = BaseMaterial3D.BILLBOARD_ENABLED

func _gl_ranger() -> void:
	var c := Vector3(-18, ground_y(-18, -50), -50)
	var items: Array = []
	_town_building(items, Vector3(-18, 0, -50), Vector3(0, 0, 1), [Color(0.45, 0.55, 0.4)], "gl_ranger", 0.0, [Color(0.35, 0.26, 0.18)])
	TownKit.build(self, items)
	_label("RANGER STATION", c + Vector3(0, 7.0, -1), 70, Color(0.85, 1, 0.75)).billboard = BaseMaterial3D.BILLBOARD_ENABLED

func _gl_hammock() -> void:
	var c := Vector2(10, 20)
	var xf: Array = []
	for k in 14:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(2.0, 9.0)
		var p := Vector3(c.x + cos(a) * r, 0, c.y + sin(a) * r)
		xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(5.0, 6.5)), Vector3(p.x, ground_y(p.x, p.z), p.z)))
	_mm("tree_liveoak", xf, Color(0.2, 0.34, 0.15))
	# chickees along the trail, Miccosukee-style rest stops
	var items: Array = []
	for p in [Vector3(-60, 0, 6), Vector3(22, 0, 6), Vector3(70, 0, -14)]:
		if not _is_blocked(p.x, p.z, 2.0):
			_town_building(items, p, Vector3(0, 0, -1), [Color.WHITE], "gl_chickee", 0.0, [Color(0.4, 0.3, 0.22)])
	TownKit.build(self, items)

# ---------------------------------------------------------------- Red Rock, Sedona (Lv 21-30)
const SD_GYM := Vector2(46, -6)
const BELL_ROCK := Vector2(10, -16)
const CATHEDRAL := Vector2(-34, -52)
const AIRPORT_MESA := Vector2(30, -70)

func _height_sedona(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := noise.get_noise_2d(x, z) * 1.3 + 0.4
	# Bell Rock: a steep bell-shaped butte
	h += 15.0 * _ss(13.0, 4.0, p.distance_to(BELL_ROCK))
	# Cathedral Rock: a ridge of spires
	h += 12.0 * _ss(16.0, 6.0, p.distance_to(CATHEDRAL)) * (0.8 + 0.2 * sin(x * 0.7))
	# Airport Mesa: flat-topped, climbable from the south
	var mesa := _ss(26.0, 10.0, p.distance_to(AIRPORT_MESA))
	h = lerpf(h, 7.5, mesa)
	# Oak Creek Canyon on the west side
	var cx := -66.0 + sin(z * 0.05) * 4.0
	h = lerpf(h, -1.8, _ss(9.0, 3.5, absf(x - cx)) * _ss(30.0, 10.0, absf(z + 8.0)))
	# red walls around the valley
	var e := maxf(absf(x), absf(z))
	h += _ss(76.0, 96.0, e) * 16.0 * (1.0 - _ss(22.0, 30.0, Vector2(x, z).distance_to(Vector2(-90, 40))))
	for fl in [[SD_GYM, 15.0], [Vector2(42, 40), 22.0], [Vector2(-80, 40), 11.0], [Vector2(-64, -54), 9.0]]:
		h = lerpf(h, 0.4, _ss(fl[1], fl[1] - 5.0, p.distance_to(fl[0])))
	return h

func _sedona_color(x: float, z: float, h: float) -> Color:
	var n := noise.get_noise_2d(x * 3.0 + 100.0, z * 3.0) * 0.5 + 0.5
	var slope := absf(height(x, z + 1.5) - height(x, z - 1.5)) + absf(height(x + 1.5, z) - height(x - 1.5, z))
	if slope > 1.8 or h > 4.0:
		var band := sin(h * 1.6) * 0.5 + 0.5   # sandstone layers
		return Color(0.72, 0.32, 0.18).lerp(Color(0.84, 0.5, 0.3), band * 0.7 + n * 0.3)
	if h < -0.6:
		return Color(0.4, 0.5, 0.3)   # creek bottom
	if Vector2(x, z).distance_to(Vector2(42, 40)) < 18.0:
		return Color(0.72, 0.58, 0.44).lerp(Color(0.78, 0.64, 0.5), n)   # Uptown plaza
	var g := Color(0.7, 0.42, 0.28).lerp(Color(0.62, 0.5, 0.32), n)   # red dirt with sage
	return g

func _build_sedona() -> void:
	noise.seed = 63
	noise.frequency = 0.03
	_rng.seed = 2052
	_static = StaticBody3D.new()
	add_child(_static)
	_blocked = [
		Rect2(-92, 28, 22, 22),    # shuttle
		Rect2(32, -20, 28, 28),    # gym
		Rect2(22, 22, 40, 36),     # uptown
		Rect2(-6, -32, 32, 32),    # bell rock
		Rect2(-52, -70, 36, 36),   # cathedral
		Rect2(14, -86, 32, 32),    # airport mesa
		Rect2(-74, -64, 20, 20),   # ghost town
	]
	_build_environment()
	_build_terrain()
	var creek := MeshInstance3D.new()
	creek.mesh = EnvShaders.water_plane(Vector2(16, 60), 3.0)
	creek.material_override = EnvShaders.water(Color(0.08, 0.24, 0.22), Color(0.3, 0.55, 0.45, 0.85), 0.05, 0.22, Vector2(0.0, 0.5))
	creek.position = Vector3(-66, -1.0, -8)
	add_child(creek)
	_build_trees()
	_build_ground_detail()
	_build_props()
	_p_bus_stop(Vector3(-80, 0, 40), "SEDONA SHUTTLE")
	var g := _usa_gym(SD_GYM, "VORTEX JIU-JITSU", Color(0.86, 0.66, 0.5), "red_rock_open")
	_sd_uptown()
	_sd_cathedral()
	_sd_mesa()
	_sd_ghost_town()
	_label("BELL ROCK", Vector3(BELL_ROCK.x, ground_y(BELL_ROCK.x, BELL_ROCK.y) + 3.0, BELL_ROCK.y), 110, Color(1, 0.85, 0.7)).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label("OAK CREEK", Vector3(-60, ground_y(-60, -8) + 3.0, -8), 80, Color(0.8, 1, 0.85)).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_animal("deer", Vector3(-52, ground_y(-52, -20), -20), 1.5, 0.3)
	_animal("fox", Vector3(60, ground_y(60, -30), -30), 0.9, 1.4)
	_animal("fox", Vector3(-20, ground_y(-20, 60), 60), 0.9, -0.6)
	_build_cups()
	_build_landmarks()
	_build_fighters()
	_build_villagers()
	_build_bounds()
	_build_beacon()

func _sd_uptown() -> void:
	var c := Vector3(42, ground_y(42, 40), 40)
	# Pueblo Revival shops (tools/westbuild/coastal.py): soft stucco, vigas, turquoise frames
	var cols := [Color(0.82, 0.58, 0.44), Color(0.86, 0.68, 0.52), Color(0.76, 0.5, 0.38), Color(0.88, 0.76, 0.62)]
	var trims := [Color(0.25, 0.6, 0.6), Color(0.3, 0.5, 0.65), Color(0.5, 0.36, 0.24)]
	var shops := ["CRYSTALS", "GALLERY", "TACOS", "JEEP TOURS", "COFFEE"]
	var kinds := ["az_adobe", "az_pueblo", "az_adobe", "az_adobe_small", "az_pueblo"]
	var items: Array = []
	for k in 5:
		var kind: String = kinds[k]
		var ab := TownKit.mesh(kind).get_aabb()
		var x := c.x - 17.0 + k * 8.5
		var zc := 47.0 + ab.end.z
		_town_building(items, Vector3(x, 0, zc), Vector3(0, 0, -1), cols, kind, 0.0, trims)
		var wall_d: float = {"az_adobe": 3.5, "az_pueblo": 4.5, "az_adobe_small": 2.75}[kind]
		var hh: float = {"az_adobe": 3.6, "az_pueblo": 3.4, "az_adobe_small": 3.2}[kind]
		var sl := _label(shops[k], Vector3(x, ground_y(x, zc) + hh + 0.45, zc - wall_d - 0.25), 72, Color(1, 0.94, 0.82), PI)
		sl.outline_size = 12
	TownKit.build(self, items)
	# turquoise trim shop with crystals out front
	for k in 5:
		_place_model("crystal", c + Vector3(-12 + k * 2.4, 0, 6.5), 0.7, _rng.randf() * TAU)
	_label("UPTOWN", c + Vector3(0, 7.0, 4), 100, Color(1, 0.9, 0.75)).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_place_model("van", c + Vector3(-14, 0, -6), 1.7, 0.4, Vector3(4.6, 2.0, 2.4))
	_place_model("truck", c + Vector3(12, 0, -8), 1.7, -0.3, Vector3(4.6, 2.0, 2.4))

func _sd_cathedral() -> void:
	var c := Vector3(CATHEDRAL.x, 0, CATHEDRAL.y)
	for k in 4:
		var p := c + Vector3(-6 + k * 4.0, 0, -2 + (k % 2) * 3)
		var gy := ground_y(p.x, p.z)
		var h := 8.0 + k % 2 * 4.0
		_cyl(0.8, 2.2, h, Vector3(p.x, gy + h / 2.0 - 0.5, p.z), Color(0.74, 0.34, 0.2), 7, true)
	_label("CATHEDRAL ROCK", Vector3(c.x, ground_y(c.x, c.z + 14) + 4.0, c.z + 14), 100, Color(1, 0.8, 0.65)).billboard = BaseMaterial3D.BILLBOARD_ENABLED

func _sd_mesa() -> void:
	var c := Vector3(AIRPORT_MESA.x, ground_y(AIRPORT_MESA.x, AIRPORT_MESA.y), AIRPORT_MESA.y)
	_cyl(0.06, 0.06, 2.0, c + Vector3(0, 1.0, 0), Color(0.3, 0.3, 0.3), 6)
	_label("AIRPORT MESA VORTEX", c + Vector3(0, 3.0, 0), 80, Color(0.9, 0.8, 1.0)).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	for k in 9:   # a stone spiral where people meditate
		var a := k * 0.8
		var r := 1.0 + k * 0.35
		_box(Vector3(0.5, 0.3, 0.5), c + Vector3(cos(a) * r, 0.15, sin(a) * r), Color(0.6, 0.5, 0.42), false)

func _sd_ghost_town() -> void:
	var c := Vector3(-64, ground_y(-64, -54), -54)
	# an old mining camp: bleached, unpainted western storefronts and a cabin
	var items: Array = []
	var weathered := [Color(0.62, 0.56, 0.48), Color(0.55, 0.5, 0.44), Color(0.66, 0.6, 0.52)]
	var spots := [[Vector3(-8, 0, -3), "tx_store_plain", Vector3(0, 0, 1)], [Vector3(0, 0, -3), "tx_store", Vector3(0, 0, 1)], [Vector3(8, 0, 4), "tx_house_small", Vector3(-1, 0, 0)]]
	for sp in spots:
		_town_building(items, c + sp[0], sp[2], weathered, sp[1], 0.0, [Color(0.4, 0.34, 0.28)])
	TownKit.build(self, items)
	_label("GHOST TOWN", c + Vector3(0, 4.4, 0), 80, Color(1, 0.85, 0.6)).billboard = BaseMaterial3D.BILLBOARD_ENABLED
