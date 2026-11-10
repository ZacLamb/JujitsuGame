class_name Herd
extends Node3D
## A slow cattle drive (comitiva pantaneira) that walks a loop through the zone: one MultiMesh of
## zebu cattle following a path, each with its own offset, gait bob and pace.

var world: World
var path: PackedVector2Array = PackedVector2Array()
var _lens: Array = []
var _total := 0.0
var _mm: MultiMesh
var _xf0: Transform3D
var _state: Array = []   # per cow: [distance along path, side offset, bob phase, scale]
var speed := 1.1

func setup(w: World, pts: PackedVector2Array, count := 12, kind := "br_cow", colors: Array = []) -> void:
	world = w
	path = pts
	_total = 0.0
	for i in path.size():
		var a := path[i]
		var b := path[(i + 1) % path.size()]
		_lens.append(a.distance_to(b))
		_total += a.distance_to(b)
	var mesh := TownKit.mesh(kind)
	if colors.is_empty():
		colors = [Color(0.95, 0.94, 0.9), Color(0.86, 0.85, 0.82), Color(0.72, 0.7, 0.68)]
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in count:
		_state.append([i * 2.6 + rng.randf_range(-0.6, 0.6), rng.randf_range(-1.8, 1.8), rng.randf() * TAU, rng.randf_range(0.9, 1.1)])
		_mm.set_instance_color(i, colors[i % colors.size()])
		_mm.set_instance_custom_data(i, colors[(i + 1) % colors.size()].darkened(0.3) if kind != "br_cow" else Color(0.3, 0.28, 0.26))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	add_child(mmi)
	_update(0.0)

func _at(d: float) -> Array:
	d = fposmod(d, _total)
	for i in path.size():
		if d <= _lens[i]:
			var a := path[i]
			var b := path[(i + 1) % path.size()]
			return [a.lerp(b, d / maxf(_lens[i], 0.01)), (b - a).normalized()]
		d -= _lens[i]
	return [path[0], Vector2(1, 0)]

func _process(delta: float) -> void:
	_update(delta)

func _update(delta: float) -> void:
	if _mm == null or world == null:
		return
	for i in _state.size():
		var s: Array = _state[i]
		s[0] = float(s[0]) + speed * delta * (0.92 + 0.08 * sin(float(s[2])))
		s[2] = float(s[2]) + delta * 4.0
		var pd: Array = _at(float(s[0]))
		var p: Vector2 = pd[0]
		var dir: Vector2 = pd[1]
		var side := Vector2(-dir.y, dir.x) * float(s[1])
		var q := p + side
		var gy := maxf(world.ground_y(q.x, q.y), world.water_level() - 0.5)
		var yaw := atan2(dir.x, dir.y)   # kit models face +Z
		var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * float(s[3]))
		_mm.set_instance_transform(i, Transform3D(b, Vector3(q.x, gy + absf(sin(float(s[2]))) * 0.05, q.y)))
