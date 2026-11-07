class_name World
extends Node3D
## Zone 1: Cáceres, Mato Grosso. Terrain, river, town, academia, fighters, collectibles.

signal nearby_changed(npc: Npc)
signal landmark_entered(id: String)
signal spot_changed(spot: Dictionary)

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
var nearby_spot: Dictionary = {}
var _jaguar_area: Area3D
var _blocked: Array = []  # Rect2 areas with no trees/houses

func build(z := "caceres") -> void:
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
	_build_gate()
	_build_pier()
	_build_nest_tree()
	_build_capybaras()
	_build_caceres_spots()
	_build_cups()
	_build_landmarks()
	_build_fighters()
	_build_villagers()
	_build_bounds()
	_build_beacon()

# ================================================================ height field
static func _ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func river_x(z: float) -> float:
	return -72.0 + sin(z * 0.035) * 6.0

func height(x: float, z: float) -> float:
	if zone == "pantanal":
		return _height_pantanal(x, z)
	if zone == "chapada":
		return _height_chapada(x, z)
	if zone == "rio":
		return _height_rio(x, z)
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
	for r in _blocked:
		if r.grow(pad).has_point(Vector2(x, z)):
			return true
	if absf(z + 4.0) < 5.0 and x > -60 and x < 84:
		return true
	if absf(x - 9.0) < 4.5 and z > -54 and z < 0:
		return true
	return false

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
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.7
	sun.directional_shadow_max_distance = 55.0
	add_child(sun)
	_build_clouds()

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
		"grass_a": {"mesh": blade, "color": Color(0.32, 0.55, 0.2) if zone != "chapada" else Color(0.55, 0.55, 0.25), "xf": []},
		"grass_b": {"mesh": blade, "color": Color(0.42, 0.63, 0.24) if zone != "chapada" else Color(0.65, 0.58, 0.3), "xf": []},
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
		if zone == "rio" and ((z > -30.0 and x > -64.0) or z > 16.0):
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
		var mat := (_mat(p.color) as StandardMaterial3D).duplicate() as StandardMaterial3D
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mmi.material_override = mat
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
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	mi.material_override = m
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
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 220)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.36, 0.38, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.4
	m.metallic_specular = 0.3
	mi.material_override = m
	mi.position = Vector3(-72, WATER_Y, 0)
	add_child(mi)

func _build_roads_and_plaza() -> void:
	var gy := ground_y(0, 8)
	_box(Vector3(30, 0.3, 20), Vector3(0, gy, 8), Color(0.66, 0.56, 0.45), true)
	# checkered calçada stripes (Portuguese pavement nod)
	for i in 6:
		_box(Vector3(30, 0.02, 1.2), Vector3(0, gy + 0.16, -0.5 + i * 3.4), Color(0.36, 0.3, 0.26), false)
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
	var cream := Color(0.95, 0.92, 0.84)
	_box(Vector3(10, 9, 15), c + Vector3(0, 4.5, 0), cream)
	_box(Vector3(10.6, 0.6, 15.6), c + Vector3(0, 9.2, 0), Color(0.6, 0.35, 0.25), false)
	for sx in [-1, 1]:
		_box(Vector3(3.2, 17, 3.2), c + Vector3(4.2 * sx, 8.5, 7), cream)
		var spire := _cyl(0.0, 2.2, 4.0, c + Vector3(4.2 * sx, 19.0, 7), Color(0.35, 0.5, 0.55), 4)
		spire.rotation.y = PI / 4
		_box(Vector3(1.2, 1.6, 0.2), c + Vector3(4.2 * sx, 13.5, 8.65), Color(0.15, 0.15, 0.2), false)
	_box(Vector3(3, 5, 0.3), c + Vector3(0, 2.5, 7.6), Color(0.35, 0.22, 0.12), false)
	var cross_v := _box(Vector3(0.3, 2.2, 0.3), c + Vector3(0, 11.0, 7.4), Color(0.9, 0.8, 0.4), false)
	_box(Vector3(1.4, 0.3, 0.3), c + Vector3(0, 11.4, 7.4), Color(0.9, 0.8, 0.4), false)

func _build_academia() -> void:
	var c := Vector3(0, ground_y(0, -54), -54)
	var wall := Color(0.92, 0.6, 0.25)
	_box(Vector3(18, 0.3, 14), c + Vector3(0, 0.15, 0), Color(0.6, 0.55, 0.5))
	_box(Vector3(0.5, 5, 14), c + Vector3(-9, 2.5, 0), wall)
	_box(Vector3(0.5, 5, 14), c + Vector3(9, 2.5, 0), wall)
	_box(Vector3(18, 5, 0.5), c + Vector3(0, 2.5, -7), wall)
	_box(Vector3(19, 0.4, 15), c + Vector3(0, 5.2, 0), Color(0.3, 0.3, 0.32), false)
	# front pillars, open front facing +Z
	for x in [-9, -3, 3, 9]:
		_box(Vector3(0.6, 5, 0.6), c + Vector3(x, 2.5, 7), wall)
	# tatame inside
	for x in 8:
		for z in 6:
			var col := Color(0.13, 0.38, 0.26) if (x + z) % 2 == 0 else Color(0.78, 0.62, 0.22)
			_box(Vector3(1.96, 0.08, 1.96), c + Vector3(-7 + x * 2, 0.34, -5 + z * 2), col, false)
	_label("ACADEMIA ONÇA", c + Vector3(0, 6.3, 7.4), 140, Color(0.98, 0.82, 0.3))
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
	var palette := [Color(0.97, 0.85, 0.35), Color(0.45, 0.7, 0.9), Color(0.95, 0.55, 0.6), Color(0.55, 0.8, 0.5), Color(0.98, 0.95, 0.88), Color(0.95, 0.6, 0.3)]
	var spots: Array = []
	for x in range(-52, 66, 10):
		spots.append(Vector3(x, 0, -14))
		spots.append(Vector3(x, 0, 6))
	for z in range(-46, 0, 10):
		spots.append(Vector3(19, 0, z))
		spots.append(Vector3(-1, 0, z))
	for p in spots:
		if _is_blocked(p.x, p.z, 1.0):
			continue
		if absf(p.x - river_x(p.z)) < 20.0:
			continue
		var w := _rng.randf_range(5, 7)
		var d := _rng.randf_range(5, 6.5)
		var hgt := _rng.randf_range(3.2, 4.2)
		var gy := ground_y(p.x, p.z)
		var col: Color = palette[_rng.randi() % palette.size()]
		_box(Vector3(w, hgt, d), Vector3(p.x, gy + hgt / 2.0, p.z), col)
		var roof := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(w + 0.6, 1.6, d + 0.6)
		roof.mesh = pm
		roof.material_override = _mat(Color(0.72, 0.33, 0.2))
		roof.position = Vector3(p.x, gy + hgt + 0.8, p.z)
		add_child(roof)
		var door_z: float = p.z + d / 2.0 + 0.02 if p.z < -4 else p.z - d / 2.0 - 0.02
		_box(Vector3(1.1, 2.0, 0.08), Vector3(p.x, gy + 1.0, door_z), col.darkened(0.55), false)
		_blocked.append(Rect2(p.x - w / 2 - 1, p.z - d / 2 - 1, w + 2, d + 2))

func _mango_tree(p: Vector3, s := 1.0) -> void:
	_cyl(0.25 * s, 0.35 * s, 3.0 * s, p + Vector3(0, 1.5 * s, 0), Color(0.4, 0.28, 0.18), 7, true)
	var c := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.2 * s
	sm.height = 3.6 * s
	sm.radial_segments = 9
	sm.rings = 5
	c.mesh = sm
	c.material_override = _mat(Color(0.18, 0.42, 0.18))
	c.position = p + Vector3(0, 3.9 * s, 0)
	add_child(c)

func _build_trees() -> void:
	# CC0 models (Kenney Nature Kit), batched with MultiMesh to stay cheap on phones.
	var xf := {"palm": [], "oak": [], "fat": [], "ipe": []}
	var placed := 0
	var tries := 0
	while placed < {"caceres": 170, "pantanal": 140, "chapada": 120, "rio": 150}[zone] and tries < 3000:
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
		if zone == "chapada" or zone == "rio":
			if absf(ground_y(x, z + 2.0) - gy) > 1.2 or absf(ground_y(x + 2.0, z) - gy) > 1.2 or gy < -0.3:
				continue
			d = 40.0
		if zone == "pantanal":
			if gy < -0.15:
				continue
			d = 18.0 if _rng.randf() < 0.45 else 40.0  # carandá palms are everywhere
		var s := _rng.randf_range(0.8, 1.3)
		var kind := _rng.randf()
		var base := Vector3(x, gy, z)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.35 * s
		sh.height = 4.0
		cs.shape = sh
		cs.position = base + Vector3(0, 2, 0)
		_static.add_child(cs)
		var b := Basis(Vector3.UP, _rng.randf() * TAU)
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
	_mm("tree_palm", xf.palm)
	_mm("tree_oak", xf.oak)
	_mm("tree_fat", xf.fat, Color(0.2, 0.42, 0.18))
	_mm("tree_fat", xf.ipe, ipe_col)

# ---------------------------------------------------------------- CC0 model helpers
static var _model_cache := {}

## Kenney's pastel palette, re-mapped by material name to fit Mato Grosso.
const PALETTE := {
	"grass": Color(0.27, 0.47, 0.18), "leafsGreen": Color(0.24, 0.5, 0.2), "leafs": Color(0.24, 0.5, 0.2),
	"woodBark": Color(0.42, 0.3, 0.2), "woodInner": Color(0.78, 0.66, 0.5), "dirt": Color(0.46, 0.37, 0.28),
	"rock": Color(0.56, 0.53, 0.49), "rockTrack": Color(0.5, 0.47, 0.44), "stone": Color(0.56, 0.53, 0.49),
	"crystal": Color(0.78, 0.68, 0.98), "colorRed": Color(0.86, 0.2, 0.24), "colorYellow": Color(0.98, 0.82, 0.2),
}

## Lambert copy of a model material: keeps textures, swaps pastel colors for our palette.
func _prop_mat(src: BaseMaterial3D, leaf_tint := Color(0, 0, 0, 0)) -> Material:
	if src and src.albedo_texture:
		var m := src.duplicate() as BaseMaterial3D
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		m.roughness = 0.8
		return m
	var nm := src.resource_name if src else ""
	var col: Color = PALETTE.get(nm, src.albedo_color.srgb_to_linear() if src else Color(0.5, 0.5, 0.5))
	if leaf_tint.a > 0.0 and (nm.begins_with("leaf") or nm == "grass"):
		col = leaf_tint
	return _mat(col, 0.9)

## Returns {"mesh": ArrayMesh, "xf": Transform3D} for the first mesh in a model, with lambert
## materials (optionally tinting the foliage surfaces).
func _model_mesh(n: String, leaf_tint := Color(0, 0, 0, 0)) -> Dictionary:
	var key := n + leaf_tint.to_html()
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
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, (xforms[i] as Transform3D) * (md.xf as Transform3D))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

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
			var sc: float = scale_of[k] * _rng.randf_range(0.8, 1.25)
			lists[k].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(x, gy - 0.05, z)))
			n += 1
	for k in lists:
		_mm(k, lists[k], Color(0, 0, 0, 0), k.begins_with("rock") or k == "log")
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
	var sign_text := "PANTANAL\nBlue belts only" if Game.rank < 5 else "PANTANAL\nBus leaves here"
	var l := _label(sign_text, Vector3(x - 0.6, gy + 7.2, 0), 110, Color(1, 0.9, 0.6), -PI / 2)
	l.name = "GateSign"

func refresh_gate() -> void:
	var l := get_node_or_null("GateSign") as Label3D
	if l:
		l.text = "PANTANAL\nBlue belts only" if Game.rank < 5 else "PANTANAL\nBus leaves here"

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
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.5, 1, 0.5)
		glow.light_energy = 0.8
		glow.omni_range = 2.5
		holder.add_child(glow)
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

func _build_landmarks() -> void:
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
		npc.position = Vector3(p.x, y, p.z)
		npc.rig.rotation.y = PI
		fighters[id] = npc

func _build_villagers() -> void:
	var where := [Vector3(0, 0, 8), Vector3(30, 0, -22), Vector3(-20, 0, -4), Vector3(40, 0, -4), Vector3(0, 0, 8), Vector3(-45, 0, 10), Vector3(12, 0, -30)]
	if zone == "pantanal":
		where = [Vector3(-75, 0, -4), Vector3(-40, 0, 26), Vector3(56, 0, 50), Vector3(38, 0, -30)]
	elif zone == "chapada":
		where = [Vector3(42, 0, 40), Vector3(36, 0, 36), Vector3(-74, 0, 40), Vector3(20, 0, 10)]
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
	refresh_gate()

func attach_player(p: Player) -> void:
	player = p
	for id in fighters:
		fighters[id].set_player(p)

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
	# don't let the player drown
	if zone == "caceres" and player.global_position.y < WATER_Y + 0.2:
		player.teleport(player.last_safe + (player.last_safe - Vector3(river_x(player.last_safe.z), 0, player.last_safe.z)).normalized() * 2.0 * Vector3(1, 0, 1), player.cam_yaw)
		Game.toast.emit("Too deep! Piranhas. Back to the bank.", Color(0.6, 0.85, 1))


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
	_spot(base, 1.9, "Drill: %s (%s)" % [Rpg.DRILLS[k].name, Rpg.ATTRS[k].name], "drill", k)

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
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	water.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.13, 0.2, 0.13, 0.9)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.7
	wm.metallic_specular = 0.2
	water.material_override = wm
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
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.2, 0.42, 0.45, 0.85)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.5
	pool.material_override = wm
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

func _gym(c: Vector3, title: String, wall: Color) -> void:
	_box(Vector3(18, 0.3, 14), c + Vector3(0, 0.15, 0), Color(0.6, 0.55, 0.5))
	_box(Vector3(0.5, 5, 14), c + Vector3(-9, 2.5, 0), wall)
	_box(Vector3(0.5, 5, 14), c + Vector3(9, 2.5, 0), wall)
	_box(Vector3(18, 5, 0.5), c + Vector3(0, 2.5, 7), wall)
	_box(Vector3(19, 0.4, 15), c + Vector3(0, 5.2, 0), Color(0.3, 0.3, 0.32), false)
	for x in [-9, -3, 3, 9]:
		_box(Vector3(0.6, 5, 0.6), c + Vector3(x, 2.5, -7), wall)
	for x in 8:
		for z in 6:
			var col := Color(0.13, 0.38, 0.26) if (x + z) % 2 == 0 else Color(0.78, 0.62, 0.22)
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
	var nm: String = Data.COMPS[comp_id].name.to_upper()
	for side in [1, -1]:
		var l := _label("CAMPEONATO\n%s" % nm, Vector3(pos.x, gy + 2.15, pos.z + 0.07 * side), 40, Color(1, 0.88, 0.4), 0.0 if side == 1 else PI)
		l.pixel_size = 0.0055
	var medal := _cyl(0.22, 0.22, 0.05, Vector3(pos.x, gy + 3.15, pos.z), Color(0.98, 0.78, 0.2), 14)
	medal.rotation.x = PI / 2
	_spot(Vector3(pos.x, gy, pos.z), 2.4, Data.COMPS[comp_id].name, "comp", comp_id)

func _challenge_board(pos: Vector3) -> void:
	var gy := ground_y(pos.x, pos.z)
	_box(Vector3(0.15, 2.2, 0.15), Vector3(pos.x - 0.9, gy + 1.1, pos.z), Color(0.4, 0.28, 0.18), false)
	_box(Vector3(0.15, 2.2, 0.15), Vector3(pos.x + 0.9, gy + 1.1, pos.z), Color(0.4, 0.28, 0.18), false)
	_box(Vector3(2.2, 1.3, 0.1), Vector3(pos.x, gy + 1.9, pos.z), Color(0.15, 0.25, 0.2), false)
	var l := _label("DESAFIO\nDO DIA", Vector3(pos.x, gy + 1.95, pos.z + 0.07), 44, UiKit.ACCENT)
	l.pixel_size = 0.006
	var l2 := _label("DESAFIO\nDO DIA", Vector3(pos.x, gy + 1.95, pos.z - 0.07), 44, UiKit.ACCENT, PI)
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
	var pm := PlaneMesh.new()
	pm.size = Vector2(420, 180)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.45, 0.58, 0.88)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.25
	m.metallic_specular = 0.6
	mi.material_override = m
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
