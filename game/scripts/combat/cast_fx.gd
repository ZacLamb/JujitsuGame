class_name CastFX
extends RefCounted
## WoW-style spell effects for techniques. Every move type has a "school" colour; casting draws a
## spinning rune circle at the caster's feet that fills with the cast and lifts sparks; landing
## throws a shockwave ring, a flash and sparks on the target; takedowns and sweeps kick up dust;
## submissions wrap the target in tightening rings; heals rise in green; a tap explodes in gold.
## All effects are cheap: a few additive quads and one small CPU particle burst each.

const SCHOOL := {
	"takedown": Color(1.0, 0.55, 0.15), "throw": Color(1.0, 0.55, 0.15),
	"sweep": Color(0.35, 1.0, 0.5), "guard": Color(0.35, 1.0, 0.5),
	"pass": Color(0.35, 0.65, 1.0), "advance": Color(0.4, 0.8, 1.0),
	"sub": Color(0.78, 0.35, 1.0), "back": Color(1.0, 0.85, 0.25),
	"escape": Color(0.3, 0.95, 1.0), "advice": Color(0.45, 1.0, 0.45), "heal": Color(0.45, 1.0, 0.45),
	"handfight": Color(1.0, 0.95, 0.85), "base": Color(0.75, 0.85, 1.0), "frame": Color(0.75, 0.85, 1.0),
}

static func color_of(ab: Dictionary) -> Color:
	var t := str(ab.get("type", "handfight"))
	if str(ab.get("effect", "")) == "base":
		t = "base"
	return SCHOOL.get(t, Color(1.0, 0.95, 0.85))

# ------------------------------------------------------------ shaders
const RUNE_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float progress = 0.0;
uniform float fade = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float an = fract(a / 6.28318 + 0.5);
	float spin = TIME * 0.6;
	float outer = smoothstep(0.9, 0.93, r) * (1.0 - smoothstep(0.97, 1.0, r));
	float inner = smoothstep(0.62, 0.64, r) * (1.0 - smoothstep(0.66, 0.68, r));
	// rune band: blocky glyphs between the two rings, rotating
	float g = step(0.5, fract((a + spin) * 12.0 / 6.28318)) * step(0.35, fract((a + spin) * 37.0 / 6.28318 + r * 3.0));
	float band = smoothstep(0.7, 0.72, r) * (1.0 - smoothstep(0.86, 0.88, r)) * g;
	// progress arc on the outer ring + a soft inner glow
	float arc = step(an, progress) * smoothstep(0.88, 0.9, r) * (1.0 - smoothstep(0.99, 1.0, r));
	float glow = (1.0 - smoothstep(0.0, 0.62, r)) * 0.18 * progress;
	float v = outer * 0.6 + inner * 0.7 + band * 0.55 + arc * 1.2 + glow;
	ALBEDO = col.rgb * v * 0.9;
	ALPHA = clamp(v, 0.0, 1.0) * fade;
}
"""

const RING_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0);
uniform float t = 0.0;      // 0 -> 1 over the effect
uniform float width = 0.12;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float edge = 1.0 - width;
	float ring = smoothstep(edge - 0.08, edge, r) * (1.0 - smoothstep(0.97, 1.0, r));
	float v = ring * (1.0 - t);
	ALBEDO = col.rgb * v * 0.9;
	ALPHA = v;
}
"""

const FLASH_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0);
uniform float t = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float rays = pow(abs(sin(a * 4.0 + t * 3.0)), 8.0) * (1.0 - smoothstep(0.1, 1.0, r)) * 0.7;
	float core = 1.0 - smoothstep(0.0, 0.55, r);
	float v = (core + rays) * (1.0 - t);
	ALBEDO = mix(col.rgb, vec3(1.0), core * 0.35) * v * 1.1;
	ALPHA = clamp(v, 0.0, 1.0);
}
"""

static var _sh := {}
static func _shader(code: String) -> Shader:
	if not _sh.has(code):
		var s := Shader.new()
		s.code = code
		_sh[code] = s
	return _sh[code]

static func _quad(code: String, size: float, c: Color, flat := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	if flat:
		q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _shader(code)
	m.set_shader_parameter("col", c)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static var _spark_mat: StandardMaterial3D
static func _sparks(parent: Node3D, pos: Vector3, c: Color, n := 18, speed := 3.5, up := false, life := 0.7) -> void:
	if _spark_mat == null:
		_spark_mat = StandardMaterial3D.new()
		_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_spark_mat.vertex_color_use_as_albedo = true
		_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0, 1) ** 2))
		_spark_mat.albedo_texture = ImageTexture.create_from_image(img)
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	p.mesh = q
	p.material_override = _spark_mat
	p.one_shot = true
	p.explosiveness = 0.9 if not up else 0.2
	p.amount = n
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 180.0 if not up else 25.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6.0, 0) if not up else Vector3(0, 1.5, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var grad := Gradient.new()
	grad.set_color(0, Color(c.lightened(0.4), 1.0))
	grad.set_color(1, Color(c, 0.0))
	p.color_ramp = grad
	p.top_level = true
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)

# ------------------------------------------------------------ effects
## Starts a cast circle under a unit; returns the node so it can be stopped. Progress fills itself.
static func cast_start(holder: Node3D, ab: Dictionary, dur: float) -> Node3D:
	var c := color_of(ab)
	var root := Node3D.new()
	root.name = "CastFX"
	holder.add_child(root)
	root.position = Vector3(0, 0.06, 0)
	var rune := _quad(RUNE_CODE, 2.2, c)
	root.add_child(rune)
	var m: ShaderMaterial = rune.material_override
	rune.scale = Vector3.ONE * 0.6
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(rune, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): m.set_shader_parameter("progress", v), 0.0, 1.0, maxf(dur, 0.1))
	# rising motes around the caster's hands / body for the whole cast
	var motes := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	motes.mesh = q
	_sparks(root, Vector3.ZERO, c, 1, 0.1)   # warms the shared material
	motes.material_override = _spark_mat
	motes.amount = 14
	motes.lifetime = 0.9
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	motes.emission_ring_radius = 0.55
	motes.emission_ring_inner_radius = 0.35
	motes.emission_ring_height = 0.1
	motes.emission_ring_axis = Vector3.UP
	motes.direction = Vector3.UP
	motes.spread = 10.0
	motes.initial_velocity_min = 0.8
	motes.initial_velocity_max = 1.6
	motes.gravity = Vector3(0, 0.6, 0)
	var grad := Gradient.new()
	grad.set_color(0, Color(c.lightened(0.5), 1.0))
	grad.set_color(1, Color(c, 0.0))
	motes.color_ramp = grad
	root.add_child(motes)
	motes.emitting = true
	return root

static func cast_stop(fx: Node3D, success := true) -> void:
	if fx == null or not is_instance_valid(fx):
		return
	for c in fx.get_children():
		if c is CPUParticles3D:
			(c as CPUParticles3D).emitting = false
	var rune: MeshInstance3D = null
	for c in fx.get_children():
		if c is MeshInstance3D:
			rune = c
	if rune:
		var m: ShaderMaterial = rune.material_override
		var tw := fx.create_tween().set_parallel(true)
		tw.tween_property(rune, "scale", Vector3.ONE * (1.35 if success else 0.4), 0.25)
		tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, 0.25)
		tw.chain().tween_callback(fx.queue_free)
	else:
		fx.queue_free()

## A technique lands on target (impact at chest height + shockwave on the ground).
static func impact(world: Node3D, at: Vector3, ab: Dictionary, crit := false) -> void:
	var c := color_of(ab)
	var k := 1.5 if crit else 1.0
	var ring := _quad(RING_CODE, 0.6, c)
	world.add_child(ring)
	ring.global_position = Vector3(at.x, at.y + 0.08, at.z)
	var rm: ShaderMaterial = ring.material_override
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * 5.0 * k, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float): rm.set_shader_parameter("t", v), 0.0, 1.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)
	var fl := _quad(FLASH_CODE, 1.0, c, false)
	world.add_child(fl)
	fl.global_position = at + Vector3(0, 1.1, 0)
	var fm: ShaderMaterial = fl.material_override
	var tw2 := fl.create_tween().set_parallel(true)
	tw2.tween_property(fl, "scale", Vector3.ONE * 1.8 * k, 0.3).set_ease(Tween.EASE_OUT)
	tw2.tween_method(func(v: float): fm.set_shader_parameter("t", v), 0.0, 1.0, 0.35)
	tw2.chain().tween_callback(fl.queue_free)
	_sparks(world, at + Vector3(0, 1.1, 0), c, 22 if crit else 14, 4.5 * k)

## Bodies hit the mat (takedown, sweep, throw): a dust puff ring in the move's colour.
static func slam(world: Node3D, at: Vector3, ab: Dictionary) -> void:
	var c := color_of(ab)
	var dust := Color(0.8, 0.7, 0.55)
	var ring := _quad(RING_CODE, 0.8, dust.lerp(c, 0.4))
	world.add_child(ring)
	ring.global_position = at + Vector3(0, 0.07, 0)
	var rm: ShaderMaterial = ring.material_override
	rm.set_shader_parameter("width", 0.35)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * 6.0, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tw.tween_method(func(v: float): rm.set_shader_parameter("t", v), 0.0, 1.0, 0.6)
	tw.chain().tween_callback(ring.queue_free)
	_sparks(world, at + Vector3(0, 0.2, 0), dust, 20, 2.5)

## Submission: rings tighten around the target at chest height.
static func constrict(world: Node3D, at: Vector3, dur: float) -> void:
	var c: Color = SCHOOL.sub
	for i in 3:
		var ring := _quad(RING_CODE, 2.4, c)
		world.add_child(ring)
		ring.global_position = at + Vector3(0, 0.5 + i * 0.35, 0)
		var rm: ShaderMaterial = ring.material_override
		rm.set_shader_parameter("width", 0.08)
		var tw := ring.create_tween().set_parallel(true)
		tw.tween_property(ring, "scale", Vector3.ONE * 0.35, maxf(dur, 0.6)).set_delay(i * 0.15).set_trans(Tween.TRANS_SINE)
		tw.tween_property(ring, "rotation:y", TAU, maxf(dur, 0.6))
		tw.chain().tween_callback(ring.queue_free)

static func heal(world: Node3D, at: Vector3) -> void:
	_sparks(world, at + Vector3(0, 0.3, 0), SCHOOL.heal, 22, 2.2, true, 1.2)
	var ring := _quad(RING_CODE, 1.6, SCHOOL.heal)
	world.add_child(ring)
	ring.global_position = at + Vector3(0, 0.08, 0)
	var rm: ShaderMaterial = ring.material_override
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "global_position:y", at.y + 2.0, 0.9)
	tw.tween_method(func(v: float): rm.set_shader_parameter("t", v), 0.0, 1.0, 0.9)
	tw.chain().tween_callback(ring.queue_free)

static func interrupted(world: Node3D, at: Vector3) -> void:
	_sparks(world, at + Vector3(0, 1.2, 0), Color(0.6, 0.85, 1.0), 16, 3.0)

## The finish: a golden burst and a tall shockwave.
static func finisher(world: Node3D, at: Vector3) -> void:
	var gold := Color(1.0, 0.82, 0.3)
	impact(world, at, {"type": "back"}, true)
	_sparks(world, at + Vector3(0, 0.6, 0), gold, 40, 6.0)
	var ring := _quad(RING_CODE, 1.0, gold)
	world.add_child(ring)
	ring.global_position = at + Vector3(0, 0.1, 0)
	var rm: ShaderMaterial = ring.material_override
	rm.set_shader_parameter("width", 0.06)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * 14.0, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float): rm.set_shader_parameter("t", v), 0.0, 1.0, 0.9)
	tw.chain().tween_callback(ring.queue_free)
