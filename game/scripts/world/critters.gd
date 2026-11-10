class_name Critters
extends Node3D
## Ground animals that notice you. Same TownKit meshes as before (one MultiMesh per kind), but each
## instance keeps a little state so it can react when the player comes close:
##   capybara  famously calm: turns to watch you; only ambles off if you sprint right at it
##   caiman    hisses and slides away (toward its home pool) when you crowd it
##   jabiru    the big stork takes off when you run near, circles away, lands back home later
##   macaw     perched pairs burst off squawking when you come under the pole, then come back
##   cow       corral cattle turn their heads to watch you, the odd one moos
## Only animals within ~40 m of the player are simulated, a few times a second when idle.

const KINDS := ["an_capybara", "an_caiman", "an_jabiru", "an_macaw", "br_cow"]
const NEAR := 40.0

class C:
	var kind: String
	var home: Vector3
	var home_yaw: float
	var scale: float
	var pos: Vector3
	var yaw: float
	var state := 0      # 0 idle, 1 watching, 2 fleeing/flying, 3 away (hidden), 4 returning
	var t := 0.0        # state timer
	var dir := Vector3.ZERO
	var idx := 0
	var air := 0.0      # height above home while flying
	var cool := 0.0     # sound cooldown

var world: Node3D        # World (height lookups)
var player: Node3D
var _mm := {}            # kind -> MultiMesh
var _list: Array = []    # all C
var _pending: Array = [] # items added before finish()
var _acc := 0.0
var _rng := RandomNumberGenerator.new()

static func is_critter(kind: String) -> bool:
	return kind in KINDS

func add(items: Array) -> void:
	_pending.append_array(items)

## Builds the MultiMeshes once the world has placed everything.
func finish() -> void:
	_rng.seed = 7
	var by_kind := {}
	for it in _pending:
		if not by_kind.has(it.kind):
			by_kind[it.kind] = []
		by_kind[it.kind].append(it)
	for k in by_kind:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = TownKit.mesh(k)
		mm.instance_count = by_kind[k].size()
		for i in by_kind[k].size():
			var it: Dictionary = by_kind[k][i]
			var x: Transform3D = it.xform
			mm.set_instance_transform(i, x)
			mm.set_instance_color(i, it.wall)
			mm.set_instance_custom_data(i, it.wood)
			var c := C.new()
			c.kind = k
			c.home = x.origin
			c.pos = x.origin
			c.scale = x.basis.get_scale().x
			var f := x.basis.z
			c.home_yaw = atan2(f.x, f.z)
			c.yaw = c.home_yaw
			c.idx = i
			c.t = _rng.randf() * 4.0
			_list.append(c)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Critters_" + k
		mmi.multimesh = mm
		add_child(mmi)
		_mm[k] = mm
	_pending.clear()

func _ground(x: float, z: float, fallback: float) -> float:
	if world and world.has_method("height"):
		var h: float = world.height(x, z)
		return h if absf(h - fallback) < 3.0 else fallback
	return fallback

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or _list.is_empty():
		return
	_acc += delta
	# idle animals only need a few updates a second; anything moving updates every frame
	var busy := false
	for c in _list:
		if c.state >= 2:
			busy = true
			break
	if not busy and _acc < 0.2:
		return
	var dt := _acc
	_acc = 0.0
	var pp := player.global_position
	var pv: Vector3 = player.get("velocity") if player.get("velocity") != null else Vector3.ZERO
	var speed := Vector2(pv.x, pv.z).length()
	for c in _list:
		var d := Vector2(pp.x - c.pos.x, pp.z - c.pos.z).length()
		if c.state < 2 and d > NEAR:
			continue
		c.cool = maxf(0.0, c.cool - dt)
		match c.kind:
			"an_capybara": _capybara(c, pp, d, speed, dt)
			"an_caiman": _caiman(c, pp, d, speed, dt)
			"an_jabiru": _bird(c, pp, d, speed, dt, 7.0, 11.0, 45.0)
			"an_macaw": _bird(c, pp, d, speed, dt, 6.0, 9.0, 30.0)
			"br_cow": _cow(c, pp, d, dt)
		_write(c)

func _face(c: C, target: Vector3, dt: float, rate := 3.0) -> void:
	var want := atan2(target.x - c.pos.x, target.z - c.pos.z)
	c.yaw = lerp_angle(c.yaw, want, clampf(dt * rate, 0.0, 1.0))

func _capybara(c: C, pp: Vector3, d: float, speed: float, dt: float) -> void:
	match c.state:
		0, 1:
			if d < 9.0:
				c.state = 1
				_face(c, pp, dt, 1.5)
				if d < 4.5 and speed > Player.WALK + 1.0:
					c.state = 2
					c.t = 2.2
					c.dir = Vector3(c.pos.x - pp.x, 0, c.pos.z - pp.z).normalized()
			else:
				c.state = 0
				c.yaw = lerp_angle(c.yaw, c.home_yaw, clampf(dt, 0.0, 1.0))
		2:
			c.t -= dt
			c.pos += c.dir * 1.6 * dt
			_face(c, c.pos + c.dir, dt, 6.0)
			c.pos.y = _ground(c.pos.x, c.pos.z, c.home.y)
			if c.t <= 0.0:
				c.state = 4
				c.t = 6.0
		4:
			c.t -= dt
			if c.t <= 0.0 and d > 8.0:
				var to := c.home - c.pos
				to.y = 0
				if to.length() < 0.2:
					c.state = 0
				else:
					c.pos += to.normalized() * minf(0.8 * dt, to.length())
					_face(c, c.home, dt, 4.0)
					c.pos.y = _ground(c.pos.x, c.pos.z, c.home.y)

func _caiman(c: C, pp: Vector3, d: float, speed: float, dt: float) -> void:
	match c.state:
		0, 1:
			if d < 8.0:
				c.state = 1
				_face(c, pp, dt, 1.0)
				if d < 3.6 or (d < 6.0 and speed > Player.WALK + 1.0):
					c.state = 2
					c.t = 1.1
					c.dir = Vector3(c.pos.x - pp.x, 0, c.pos.z - pp.z).normalized()
					if c.cool <= 0.0:
						Sfx.play("hiss", -6.0, _rng.randf_range(0.85, 1.1))
						c.cool = 6.0
			else:
				c.state = 0
		2:
			# a fast belly slide away, settling a little lower (into the mud/water)
			c.t -= dt
			c.pos += c.dir * 4.5 * dt
			c.pos.y = _ground(c.pos.x, c.pos.z, c.home.y) - 0.12
			c.yaw = lerp_angle(c.yaw, atan2(c.dir.x, c.dir.z), clampf(dt * 8.0, 0.0, 1.0))
			if c.t <= 0.0:
				c.state = 4
				c.t = 10.0
		4:
			c.t -= dt
			if c.t <= 0.0 and d > 10.0:
				var to := c.home - c.pos
				to.y = 0
				if to.length() < 0.2:
					c.state = 0
					c.pos = c.home
				else:
					c.pos += to.normalized() * minf(0.7 * dt, to.length())
					_face(c, c.home, dt, 3.0)
					c.pos.y = _ground(c.pos.x, c.pos.z, c.home.y)

## Birds: take off when crowded, climb away in a curve, vanish, then glide back home.
func _bird(c: C, pp: Vector3, d: float, speed: float, dt: float, walk_r: float, run_r: float, away_s: float) -> void:
	match c.state:
		0, 1:
			var r := run_r if speed > Player.WALK + 1.0 else walk_r
			if d < r:
				c.state = 2
				c.t = 0.0
				var away := Vector3(c.pos.x - pp.x, 0, c.pos.z - pp.z).normalized()
				c.dir = away.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
				if c.cool <= 0.0:
					Sfx.play("wings", -4.0 if c.kind == "an_jabiru" else -2.0, _rng.randf_range(0.9, 1.15) * (0.8 if c.kind == "an_jabiru" else 1.2))
					c.cool = 4.0
			elif d < r + 6.0:
				c.state = 1
				_face(c, pp, dt, 2.0)
			else:
				c.state = 0
		2:
			c.t += dt
			var fwd := 6.0 if c.kind == "an_jabiru" else 9.0
			c.pos += c.dir * fwd * dt
			c.air += (3.0 + c.t * 2.5) * dt
			c.dir = c.dir.rotated(Vector3.UP, dt * 0.35)
			c.pos.y = c.home.y + c.air
			c.yaw = lerp_angle(c.yaw, atan2(c.dir.x, c.dir.z), clampf(dt * 6.0, 0.0, 1.0))
			if c.t > 6.0:
				c.state = 3
				c.t = away_s
		3:
			c.t -= dt
			if c.t <= 0.0 and d > 14.0:
				# glide back in from above
				c.state = 4
				c.air = 14.0
				c.pos = c.home + Vector3(0, c.air, 0) - Vector3(sin(c.home_yaw), 0, cos(c.home_yaw)) * 18.0
		4:
			var to := c.home - c.pos
			var hd := Vector2(to.x, to.z).length()
			if hd < 0.3:
				c.pos = c.home
				c.air = 0.0
				c.yaw = c.home_yaw
				c.state = 0
			else:
				var step := minf(5.0 * dt, hd)
				var h := Vector3(to.x, 0, to.z).normalized()
				c.pos += h * step
				c.air = maxf(0.0, c.air - step * (c.air / maxf(hd, 0.01)))
				c.pos.y = c.home.y + c.air
				c.yaw = lerp_angle(c.yaw, atan2(h.x, h.z), clampf(dt * 5.0, 0.0, 1.0))

func _cow(c: C, pp: Vector3, d: float, dt: float) -> void:
	if d < 9.0:
		_face(c, pp, dt, 1.2)
		if c.state == 0 and c.cool <= 0.0 and _rng.randf() < 0.25:
			Sfx.play("moo", -10.0, _rng.randf_range(0.85, 1.1))
			c.cool = 25.0
		c.state = 1
	else:
		c.state = 0
		c.yaw = lerp_angle(c.yaw, c.home_yaw, clampf(dt * 0.6, 0.0, 1.0))

func _write(c: C) -> void:
	var b := Basis(Vector3.UP, c.yaw).scaled(Vector3.ONE * c.scale)
	var mm: MultiMesh = _mm[c.kind]
	if c.state == 3:
		mm.set_instance_transform(c.idx, Transform3D(Basis().scaled(Vector3.ONE * 0.001), c.home + Vector3(0, -50, 0)))
		return
	if c.state == 2 and (c.kind == "an_jabiru" or c.kind == "an_macaw"):
		# lean into the climb
		b = Basis(Vector3.UP, c.yaw) * Basis(Vector3.RIGHT, -0.35)
		b = b.scaled(Vector3.ONE * c.scale)
	mm.set_instance_transform(c.idx, Transform3D(b, c.pos))

## Test/probe helper: counts per state.
func states() -> Dictionary:
	var out := {}
	for c in _list:
		var k := "%s:%d" % [c.kind, c.state]
		out[k] = int(out.get(k, 0)) + 1
	return out
