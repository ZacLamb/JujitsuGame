class_name Wildlife
extends Node3D
## Ambient life: bird flocks circling overhead (zone-specific species) and butterflies drifting
## around the player. Everything is one MultiMesh per group; wings flap in the vertex shader.

const FLAP_CODE := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform float flap_speed = 9.0;
uniform float flap_amount = 0.9;
void vertex() {
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float f = sin(TIME * flap_speed + ph);
	VERTEX.y += abs(VERTEX.x) * f * flap_amount;
}
void fragment() {
	ALBEDO = COLOR.rgb;
}
"""
static var _flap: Shader

class Flock:
	var mm: MultiMesh
	var center: Vector3
	var radius: float
	var height: float
	var speed: float
	var phases: Array = []

var flocks: Array = []
var butterflies: MultiMesh
var _bf_state: Array = []       # [anchor offset, phase]
var _t := 0.0
var _player: Node3D

static func _bird_mesh(span: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := span * 0.5
	# two wing triangles meeting at the body line (x = 0); +z is the tail
	for v in [Vector3(0, 0, -0.35 * h), Vector3(-h, 0, 0.1 * h), Vector3(0, 0, 0.3 * h),
			Vector3(0, 0, -0.35 * h), Vector3(0, 0, 0.3 * h), Vector3(h, 0, 0.1 * h)]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
	return st.commit()

static func _material(speed: float, amount: float) -> ShaderMaterial:
	if _flap == null:
		_flap = Shader.new()
		_flap.code = FLAP_CODE
	var m := ShaderMaterial.new()
	m.shader = _flap
	m.set_shader_parameter("flap_speed", speed)
	m.set_shader_parameter("flap_amount", amount)
	return m

func setup(zone: String, player: Node3D) -> void:
	_player = player
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(zone)
	# species per zone: [colors, count, span, height, radius, centers]
	var specs := {
		"caceres": [[Color(0.95, 0.95, 0.95), Color(0.5, 0.5, 0.55)], 9, 0.7, 16.0, 26.0, [Vector3(-60, 0, 0), Vector3(20, 0, -30)]],
		"pantanal": [[Color(0.9, 0.15, 0.12), Color(0.15, 0.4, 0.9), Color(0.98, 0.95, 0.9)], 10, 0.9, 14.0, 30.0, [Vector3(10, 0, 20), Vector3(-40, 0, -40), Vector3(50, 0, -10)]],
		"chapada": [[Color(0.1, 0.1, 0.1)], 6, 1.6, 30.0, 34.0, [Vector3(20, 0, -20), Vector3(-30, 0, -50)]],
		"rio": [[Color(0.95, 0.95, 0.95), Color(0.15, 0.15, 0.17)], 8, 1.2, 22.0, 40.0, [Vector3(0, 0, 70), Vector3(60, 0, 50)]],
		"socal": [[Color(0.95, 0.95, 0.95), Color(0.6, 0.62, 0.66)], 9, 1.1, 20.0, 40.0, [Vector3(-20, 0, 66), Vector3(50, 0, 56)]],
	}
	var sp: Array = specs.get(zone, specs.caceres)
	for c in sp[5]:
		var f := Flock.new()
		f.center = c
		f.radius = float(sp[4]) * rng.randf_range(0.7, 1.1)
		f.height = float(sp[3]) + rng.randf_range(-3, 4)
		f.speed = rng.randf_range(0.12, 0.2) * (0.6 if zone == "chapada" else 1.0)
		f.mm = MultiMesh.new()
		f.mm.transform_format = MultiMesh.TRANSFORM_3D
		f.mm.use_colors = true
		f.mm.use_custom_data = true
		f.mm.mesh = _bird_mesh(float(sp[2]))
		f.mm.instance_count = int(sp[1])
		for i in f.mm.instance_count:
			var cols: Array = sp[0]
			f.mm.set_instance_color(i, cols[i % cols.size()])
			f.mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
			f.phases.append([rng.randf() * TAU, rng.randf_range(-3, 3), rng.randf_range(-2, 2)])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = f.mm
		mi.material_override = _material(4.5 if zone == "chapada" else 9.0, 0.25 if zone == "chapada" else 0.9)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		flocks.append(f)
	# butterflies (not in Rio's sand or at night they hide via scale)
	butterflies = MultiMesh.new()
	butterflies.transform_format = MultiMesh.TRANSFORM_3D
	butterflies.use_colors = true
	butterflies.use_custom_data = true
	butterflies.mesh = _bird_mesh(0.22)
	butterflies.instance_count = 14
	var bcols := [Color(1.0, 0.8, 0.1), Color(0.3, 0.6, 1.0), Color(1.0, 0.45, 0.1), Color(0.95, 0.95, 0.95)]
	for i in butterflies.instance_count:
		butterflies.set_instance_color(i, bcols[i % bcols.size()])
		butterflies.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
		_bf_state.append([Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14)), rng.randf() * TAU])
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = butterflies
	bmi.material_override = _material(16.0, 1.4)
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bmi.visibility_range_end = 40.0
	add_child(bmi)

func _process(delta: float) -> void:
	_t += delta
	for f in flocks:
		var fl: Flock = f
		for i in fl.mm.instance_count:
			var ph: Array = fl.phases[i]
			var a: float = _t * fl.speed + float(ph[0]) * 0.15 + i * 0.09
			var r := fl.radius + float(ph[1]) + sin(_t * 0.3 + i) * 2.0
			var p := fl.center + Vector3(cos(a) * r, fl.height + float(ph[2]) + sin(_t * 0.7 + i) * 0.8, sin(a) * r)
			var tangent := Vector3(-sin(a), 0, cos(a))
			var b := Basis.looking_at(tangent, Vector3.UP).rotated(tangent.normalized(), -0.3)
			fl.mm.set_instance_transform(i, Transform3D(b, p))
	if _player == null or not is_instance_valid(_player):
		return
	var day := DayNight.daylight()
	var anchor := _player.global_position
	for i in butterflies.instance_count:
		var st: Array = _bf_state[i]
		var ph: float = st[1]
		var off: Vector3 = st[0]
		var p := anchor + off + Vector3(sin(_t * 0.5 + ph) * 3.0, 0.6 + absf(sin(_t * 1.3 + ph)) * 0.9, cos(_t * 0.4 + ph * 1.3) * 3.0)
		var heading := Vector3(cos(_t * 0.5 + ph), 0, -sin(_t * 0.4 + ph * 1.3))
		var b := Basis.looking_at(heading if heading.length() > 0.01 else Vector3.FORWARD, Vector3.UP)
		butterflies.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * (1.0 if day > 0.5 else 0.001)), p))
