class_name BeachLife
extends Node3D
## Copacabana extras: sunbathers on towels, a beach volleyball game, surfers riding the swell
## and a small crowd at a kiosk. Pure scenery (no interaction).

const LYING := Vector3(PI / 2, 0, 0)
var world: World
var _surfers: Array = []      # [rig, board, x0, speed, z, phase]
var _players: Array = []      # volleyball rigs
var _ball: MeshInstance3D
var _rally_t := 0.0
var _from := 0
var _to := 2
var _jump_until := {}
var _rng := RandomNumberGenerator.new()

func setup(w: World) -> void:
	world = w
	_rng.seed = 5150
	_sunbathers()
	_volleyball()
	_surf()
	_kiosk_crowd()

func _rig(shirt: Color, skin_t: float, female: bool) -> BodyRig:
	var r := BodyRig.new()
	add_child(r)
	r.setup(shirt, shirt.darkened(0.3), UiKit.skin_tone(skin_t), Color(0.12, 0.08, 0.05), -1, "female" if female else "male", true)
	return r

func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, world.ground_y(x, z), z)

func _sunbathers() -> void:
	var towels := [Color(0.95, 0.3, 0.3), Color(0.2, 0.6, 0.9), Color(0.98, 0.8, 0.2), Color(0.3, 0.75, 0.45), Color(0.95, 0.55, 0.75)]
	var spots := [Vector3(-56, 0, 40), Vector3(-8, 0, 44), Vector3(14, 0, 38), Vector3(38, 0, 42), Vector3(56, 0, 39), Vector3(-4, 0, 36)]
	for i in spots.size():
		var p := _ground(spots[i].x, spots[i].z)
		var yaw := _rng.randf_range(-0.6, 0.6) + (PI if i % 2 == 0 else 0.0)
		var towel := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.03, 1.9)
		towel.mesh = bm
		towel.material_override = BodyRig._mat(towels[i % towels.size()])
		towel.position = p + Vector3(0, 0.02, 0)
		towel.rotation.y = yaw
		add_child(towel)
		var r := _rig(Color(0.15, 0.3, 0.75) if i % 3 == 0 else Color(0.9, 0.2, 0.3), _rng.randf(), i % 2 == 1)
		r.lod_enabled = true
		var sitting := i % 3 == 2
		var pose := {}
		if sitting:
			pose = {"hip_h": 0.24, "spine": Vector3(0.25, 0, 0), "l_hip": Vector3(1.45, 0, -0.15), "r_hip": Vector3(1.2, 0, 0.15),
				"l_kn": Vector3(-0.4, 0, 0), "r_kn": Vector3(-1.2, 0, 0), "l_sh": Vector3(-0.5, 0, 0.3), "r_sh": Vector3(-0.5, 0, -0.3),
				"l_el": Vector3(0.1, 0, 0), "r_el": Vector3(0.1, 0, 0)}
		else:
			pose = {"hip_h": 0.15, "hip_rot": LYING, "neck": Vector3(-0.2, 0, 0), "l_hip": Vector3(0.05, 0, -0.1), "r_hip": Vector3(0.25, 0, 0.12),
				"r_kn": Vector3(-0.5, 0, 0), "l_sh": Vector3(2.6, 0, 0.4), "r_sh": Vector3(0.2, 0, -0.35), "l_el": Vector3(1.6, 0, 0)}
		r.position = p + Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.55 if not sitting else 0.2)
		r.rotation.y = yaw
		r.apply_pose(pose)

func _volleyball() -> void:
	var at := [Vector3(-32.5, 0, 44.2), Vector3(-27.5, 0, 44.6), Vector3(-32.0, 0, 48.0), Vector3(-27.0, 0, 47.7)]
	for i in at.size():
		var r := _rig([Color(0.98, 0.8, 0.2), Color(0.2, 0.55, 0.3)][i / 2], _rng.randf(), i % 2 == 0)
		r.position = _ground(at[i].x, at[i].z)
		r.rotation.y = 0.0 if i < 2 else PI
		_players.append(r)
	_ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	_ball.mesh = sm
	_ball.material_override = BodyRig._mat(Color(0.98, 0.95, 0.9))
	add_child(_ball)

func _surf() -> void:
	for i in 3:
		var r := _rig([Color(0.1, 0.1, 0.12), Color(0.15, 0.35, 0.8), Color(0.9, 0.3, 0.2)][i], _rng.randf(), i == 1)
		r.apply_pose({"hip_h": 0.62, "spine": Vector3(-0.35, 0, 0.2), "l_hip": Vector3(0.75, 0, -0.35), "r_hip": Vector3(0.3, 0, 0.35),
			"l_kn": Vector3(-1.1, 0, 0), "r_kn": Vector3(-0.8, 0, 0), "l_sh": Vector3(0.3, 0, -1.25), "r_sh": Vector3(0.1, 0, 1.3),
			"l_el": Vector3(0.3, 0, 0), "r_el": Vector3(0.3, 0, 0)})
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.55, 0.07, 2.1)
		board.mesh = bm
		board.material_override = BodyRig._mat([Color(0.98, 0.95, 0.85), Color(0.98, 0.8, 0.2), Color(0.3, 0.75, 0.9)][i])
		add_child(board)
		_surfers.append([r, board, _rng.randf_range(-60, 60), _rng.randf_range(2.2, 3.4) * (1 if i % 2 == 0 else -1), _rng.randf_range(64, 74), _rng.randf() * TAU])

func _kiosk_crowd() -> void:
	for p in [Vector3(7.0, 0, 35.6), Vector3(9.3, 0, 35.9), Vector3(34.6, 0, 35.7)]:
		var r := _rig([Color(0.95, 0.95, 0.95), Color(0.4, 0.7, 0.9), Color(0.95, 0.6, 0.3)][_rng.randi() % 3], _rng.randf(), _rng.randf() < 0.5)
		r.position = _ground(p.x, p.z)
		r.rotation.y = 0.0   # facing the kiosk (-Z)

func _process(delta: float) -> void:
	# volleyball rally: the ball arcs between players; the receiver jumps
	if _ball:
		_rally_t += delta / 1.5
		if _rally_t >= 1.0:
			_rally_t = 0.0
			_from = _to
			_to = (_from + 2 + _rng.randi_range(0, 1)) % 4
			if (_from < 2) == (_to < 2):
				_to = (_to + 2) % 4
		var a: Vector3 = _players[_from].position + Vector3(0, 2.2, 0)
		var b: Vector3 = _players[_to].position + Vector3(0, 2.2, 0)
		var p := a.lerp(b, _rally_t)
		p.y += sin(_rally_t * PI) * 3.2
		_ball.position = p
		if _rally_t > 0.82 and not _jump_until.has(_to):
			_jump_until[_to] = 0.5
			(_players[_to] as BodyRig)._play_locomotion(0.0, true)
		for k in _jump_until.keys():
			_jump_until[k] -= delta
			if _jump_until[k] <= 0.0:
				_jump_until.erase(k)
				(_players[k] as BodyRig)._play_locomotion(0.0, false)
	# surfers ride along the swell and turn around at the ends
	var t := Time.get_ticks_msec() / 1000.0
	for s in _surfers:
		var r: BodyRig = s[0]
		var board: MeshInstance3D = s[1]
		s[2] = float(s[2]) + float(s[3]) * delta
		if absf(float(s[2])) > 75.0:
			s[3] = -float(s[3])
		var x: float = s[2]
		var z: float = float(s[4]) + sin(t * 0.4 + float(s[5])) * 3.0
		var bob := sin(t * 1.6 + x * 0.1) * 0.18
		var pos := Vector3(x, World.WATER_Y + 0.12 + bob, z)
		var yaw := PI / 2 if float(s[3]) > 0.0 else -PI / 2
		board.position = pos
		board.rotation = Vector3(sin(t * 1.6 + x * 0.1) * 0.08, yaw, sin(t * 1.1) * 0.12)
		r.position = pos + Vector3(0, 0.05, 0)
		r.rotation.y = yaw + PI / 2
