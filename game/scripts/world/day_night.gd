class_name DayNight
extends Node3D
## Day/night cycle: 1 in-game hour per real minute (a full day in 24 minutes). Drives the sun
## (or moon), sky, fog and ambient colors, stars, and the glow of street lamps.

const SECONDS_PER_HOUR := 60.0
static var hour := 8.5          # shared across zones so a bus ride keeps the time
static var lamp_mat: StandardMaterial3D

var env: Environment
var sky: ProceduralSkyMaterial
var sun: DirectionalLight3D
var base_horizon := Color(0.7, 0.84, 0.95)
var base_exposure := 0.88
var stars: MultiMeshInstance3D
var _star_mat: StandardMaterial3D
var frozen := false             # tests / screenshots

const DAY_TOP := Color(0.16, 0.4, 0.82)
const GOLD_TOP := Color(0.32, 0.36, 0.66)
const NIGHT_TOP := Color(0.05, 0.08, 0.19)
const GOLD_HORIZON := Color(1.0, 0.6, 0.34)
const NIGHT_HORIZON := Color(0.15, 0.19, 0.34)
const DAY_AMBIENT := Color(0.62, 0.68, 0.78)
const NIGHT_AMBIENT := Color(0.48, 0.53, 0.72)
const SUN_DAY := Color(1.0, 0.92, 0.78)
const SUN_GOLD := Color(1.0, 0.56, 0.3)
const MOON := Color(0.7, 0.76, 0.95)

static func lamp_material() -> StandardMaterial3D:
	if lamp_mat == null:
		lamp_mat = StandardMaterial3D.new()
		lamp_mat.albedo_color = Color(1.0, 0.9, 0.65)
		lamp_mat.emission_enabled = true
		lamp_mat.emission = Color(1.0, 0.78, 0.45)
		lamp_mat.emission_energy_multiplier = 0.0
	return lamp_mat

func setup(e: Environment, s: ProceduralSkyMaterial, light: DirectionalLight3D, exposure: float) -> void:
	env = e
	sky = s
	sun = light
	base_horizon = s.sky_horizon_color
	base_exposure = exposure
	_build_stars()
	apply()

func _build_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	mm.mesh = q
	mm.instance_count = 420
	for i in mm.instance_count:
		# upper hemisphere, radius 300
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.08, 1.0), rng.randf_range(-1, 1)).normalized()
		var p := dir * 300.0
		var t := Transform3D(Basis.looking_at(-dir), p).scaled_local(Vector3.ONE * rng.randf_range(0.6, 1.6))
		mm.set_instance_transform(i, t)
	stars = MultiMeshInstance3D.new()
	stars.multimesh = mm
	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.albedo_color = Color(1, 1, 1, 0)
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_star_mat.disable_fog = true
	_star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	stars.material_override = _star_mat
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)

static func clock_text() -> String:
	var h := int(hour) % 24
	var m := int((hour - floorf(hour)) * 60.0)
	return "%02d:%02d" % [h, m]

## 0 at night, 1 in full day.
static func daylight() -> float:
	var elev := sin((hour - 6.0) / 12.0 * PI) * 70.0
	return clampf((elev + 5.0) / 18.0, 0.0, 1.0)

func _process(delta: float) -> void:
	if not frozen:
		hour = fmod(hour + delta / SECONDS_PER_HOUR, 24.0)
	apply()
	var cam := get_viewport().get_camera_3d()
	if cam and stars:
		stars.global_position = cam.global_position

func apply() -> void:
	if env == null:
		return
	var elev := sin((hour - 6.0) / 12.0 * PI) * 70.0     # sun height in degrees
	var d := clampf((elev + 5.0) / 18.0, 0.0, 1.0)
	d = d * d * (3.0 - 2.0 * d)
	var gold := clampf(1.0 - absf(elev - 6.0) / 16.0, 0.0, 1.0) * clampf((elev + 6.0) / 6.0, 0.0, 1.0)
	# sky
	var top := NIGHT_TOP.lerp(DAY_TOP, d).lerp(GOLD_TOP, gold * 0.6)
	var hor := NIGHT_HORIZON.lerp(base_horizon, d).lerp(GOLD_HORIZON, gold * 0.85)
	sky.sky_top_color = top
	sky.sky_horizon_color = hor
	sky.ground_horizon_color = hor.darkened(0.25)
	env.fog_light_color = hor.lerp(top, 0.25)
	EnvShaders.set_sky_tint(hor.lerp(top, 0.35))
	env.ambient_light_color = NIGHT_AMBIENT.lerp(DAY_AMBIENT, d).lerp(Color(1.0, 0.75, 0.6), gold * 0.25)
	env.ambient_light_energy = lerpf(0.52, 0.42, d)
	env.tonemap_exposure = base_exposure * lerpf(1.22, 1.0, d)
	# sun by day, moon by night
	if elev > -2.0:
		sun.rotation_degrees = Vector3(-maxf(elev, 4.0), -35.0 + (hour - 12.0) * 6.0, 0)
		sun.light_color = SUN_DAY.lerp(SUN_GOLD, gold)
		sun.light_energy = lerpf(0.3, 1.05, d)
	else:
		var night_t := fmod(hour + 6.0, 24.0) / 12.0  # 0 at 18:00 .. 1 at 06:00
		sun.rotation_degrees = Vector3(-(18.0 + sin(night_t * PI) * 40.0), 150.0 + night_t * 60.0, 0)
		sun.light_color = MOON
		sun.light_energy = 0.45
	sun.shadow_opacity = lerpf(0.45, 0.7, d)
	_star_mat.albedo_color.a = clampf(1.0 - d * 1.6, 0.0, 0.95)
	stars.visible = d < 0.6
	lamp_material().emission_energy_multiplier = (1.0 - d) * 3.2
