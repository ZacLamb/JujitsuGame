class_name Chests
extends Node3D
## Hidden chests: six per zone, tucked into the quiet corners of the map (far from roads, gyms and
## camps), one of them a golden chest in the most out-of-the-way spot. A faint sparkle shows up
## only when you're close. Money, food, bags and rolled gear at the zone's level; the first time you
## find one you also get XP. Each chest refills a day after you loot it.

const PER_ZONE := 6
const REFILL_S := 20 * 3600
const SPARKLE_RANGE := 16.0

var world   # World
var chests := {}   # id -> {node, lid, spark, pos, golden}

func build(w) -> void:
	world = w
	name = "Chests"
	for c in _place():
		_make(c)

## Picks spots: dry, flat, not on roads or buildings, away from everything people walk to.
func _place() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(world.zone + "chests")) + 99
	var avoid: Array = []   # Vector2 points of interest
	for id in Data.landmarks_in(world.zone):
		var lp: Vector3 = Data.LANDMARKS[id].pos
		avoid.append(Vector2(lp.x, lp.z))
	for sp in world.spots:
		avoid.append(Vector2(sp.pos.x, sp.pos.z))
	for p in Data.COLLECTIBLES.get(world.zone, []):
		avoid.append(Vector2(p.x, p.z))
	for cp in Loot.CAMPS.get(world.zone, []):
		var cc: Vector3 = cp.pos
		avoid.append(Vector2(cc.x, cc.z))
	var sp0: Vector3 = Data.ZONES[world.zone].spawn
	avoid.append(Vector2(sp0.x, sp0.z))
	var cands: Array = []
	for i in 900:
		var x := rng.randf_range(-80.0, 80.0)
		var z := rng.randf_range(-80.0, 80.0)
		var h: float = world.ground_y(x, z)
		if h < World.WATER_Y + 0.5 or world._is_blocked(x, z, 2.5):
			continue
		var slope := 0.0
		for d in [Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
			slope = maxf(slope, absf(world.ground_y(x + d.x, z + d.y) - h))
		if slope > 0.6:
			continue
		var md := 42.0
		for a in avoid:
			md = minf(md, (a as Vector2).distance_to(Vector2(x, z)))
		if md < 12.0:
			continue
		cands.append({"pos": Vector3(x, h, z), "score": md + rng.randf() * 8.0})
	cands.sort_custom(func(a, b): return a.score > b.score)
	var out: Array = []
	for c in cands:
		var ok := true
		for o in out:
			if (o.pos as Vector3).distance_to(c.pos) < 26.0:
				ok = false
				break
		if ok:
			out.append(c)
		if out.size() >= PER_ZONE:
			break
	for i in out.size():
		out[i]["id"] = "%s_%d" % [world.zone, i]
		out[i]["golden"] = i == 0   # the most remote one
		out[i]["yaw"] = rng.randf() * TAU
	return out

static func _m(c: Color, rough := 0.8, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _make(c: Dictionary) -> void:
	var golden: bool = c.golden
	var root := Node3D.new()
	root.position = c.pos
	root.rotation.y = c.yaw
	add_child(root)
	var wood := _m(Color(0.42, 0.26, 0.13) if not golden else Color(0.3, 0.16, 0.08))
	var band := _m(Color(0.55, 0.5, 0.42) if not golden else Color(1.0, 0.78, 0.25), 0.35)
	_box(root, Vector3(0.95, 0.5, 0.6), Vector3(0, 0.25, 0), wood)
	for x in [-0.38, 0.38]:
		_box(root, Vector3(0.07, 0.52, 0.63), Vector3(x, 0.25, 0), band)
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.5, -0.3)   # hinge at the back edge
	root.add_child(lid)
	_box(lid, Vector3(0.97, 0.2, 0.62), Vector3(0, 0.1, 0.3), wood)
	for x in [-0.38, 0.38]:
		_box(lid, Vector3(0.07, 0.22, 0.65), Vector3(x, 0.1, 0.3), band)
	_box(lid, Vector3(0.14, 0.16, 0.05), Vector3(0, 0.0, 0.62), band)   # lock
	var col := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.95, 0.7, 0.6)
	cs.shape = sh
	cs.position.y = 0.35
	col.add_child(cs)
	root.add_child(col)
	# the hint: a slow, bobbing glint you only notice up close
	var spark := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.35, 0.35)
	spark.mesh = qm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = _star_tex()
	sm.albedo_color = Color(1, 0.92, 0.55) if golden else Color(1, 1, 0.85)
	spark.material_override = sm
	spark.position = Vector3(0.2, 0.95, 0.1)
	spark.visibility_range_end = SPARKLE_RANGE
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(spark)
	chests[c.id] = {"node": root, "lid": lid, "spark": spark, "pos": c.pos, "golden": golden}
	world._spot(c.pos, 2.4, "", "chest", c.id)
	refresh(c.id)

static var _star: Texture2D
static func _star_tex() -> Texture2D:
	if _star:
		return _star
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var p := Vector2(x - 15.5, y - 15.5) / 15.5
			var a := clampf(1.0 - absf(p.x) * 6.0, 0, 1) * clampf(1.0 - absf(p.y), 0, 1) + clampf(1.0 - absf(p.y) * 6.0, 0, 1) * clampf(1.0 - absf(p.x), 0, 1)
			a = maxf(a, clampf(1.0 - p.length() * 2.2, 0, 1))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0, 1)))
	_star = ImageTexture.create_from_image(img)
	return _star

## Seconds until this chest refills (0 = full).
static func refill_left(id: String) -> int:
	var t := int(Game.flags.get("chests", {}).get(id, 0))
	return maxi(0, t + REFILL_S - int(Time.get_unix_time_from_system()))

func refresh(id: String) -> void:
	var c: Dictionary = chests[id]
	var full := refill_left(id) == 0
	(c.lid as Node3D).rotation.x = 0.0 if full else -1.9
	(c.spark as Node3D).visible = full
	for sp in world.spots:
		if sp.action == "chest" and sp.arg == id:
			if full:
				sp.label = Tx.f("Open the %s", ("golden chest" if c.golden else "hidden chest"))
			else:
				sp.label = Tx.f("Empty chest  ·  refills in %dh", ceili(refill_left(id) / 3600.0))

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for id in chests:
		var s: Node3D = chests[id].spark
		if s.visible:
			s.position.y = 0.95 + sin(t * 2.0 + float(hash(id) % 7)) * 0.08
			s.rotation.z = t
			(s as MeshInstance3D).transparency = 0.35 + 0.35 * sin(t * 3.1 + float(hash(id) % 5))

## Opens a chest: returns {money, items, xp, first, golden} or {} if it's empty.
func open(id: String) -> Dictionary:
	if not chests.has(id) or refill_left(id) > 0:
		return {}
	var c: Dictionary = chests[id]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var lv: Array = Data.ZONES[world.zone].levels
	var plv := clampi(Game.player_level(), int(lv[0]), int(lv[1]))
	var golden: bool = c.golden
	var loot := {"money": int((12 + plv * 4) * (2.5 if golden else 1.0) * rng.randf_range(0.8, 1.3)), "items": [], "golden": golden}
	var food := ["acai", "coco", "pao_queijo", "terere", "guarana"]
	if Data.continent_of(world.zone) == "america":
		food = ["smoothie_bowl", "shake", "pbj", "sweet_tea", "energy_drink"]
	loot.items.append(food[rng.randi() % food.size()])
	if rng.randf() < (0.65 if not golden else 1.0):
		loot.items.append("gear:" + Game.make_rolled(Gear.roll(plv + (2 if golden else 0), rng, golden, golden)))
	if rng.randf() < (0.12 if not golden else 0.4):
		loot.items.append("bag_lona" if not golden else "bag_kimono")
	if rng.randf() < 0.3:
		loot.items.append(["patch", "medal_scrap"][rng.randi() % 2])
	var found: Dictionary = Game.flags.get("chests_found", {})
	loot["first"] = not found.has(id)
	loot["xp"] = (40 + plv * 12) * (2 if golden else 1) if loot.first else 0
	found[id] = true
	Game.flags["chests_found"] = found
	var opened: Dictionary = Game.flags.get("chests", {})
	opened[id] = int(Time.get_unix_time_from_system())
	Game.flags["chests"] = opened
	# lid swings open
	var tw := create_tween()
	tw.tween_property(c.lid, "rotation:x", -1.9, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	(c.spark as Node3D).visible = false
	refresh(id)
	return loot

## Hidden chests found in this zone (for the toast and the map).
func found_count() -> int:
	var n := 0
	var found: Dictionary = Game.flags.get("chests_found", {})
	for id in chests:
		if found.has(id):
			n += 1
	return n
