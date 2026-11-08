class_name EnvShaders
extends RefCounted
## Environment shaders (WebGL2 / Compatibility friendly): animated water, wind-swayed grass,
## and terrain with procedural detail on top of the per-vertex ground colors.

static var _water_shader: Shader
static var _grass_shader: Shader
static var _terrain_shader: Shader
static var waters: Array = []   # live water materials; the day/night cycle tints their reflections

const WATER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;
uniform vec4 deep : source_color = vec4(0.05, 0.25, 0.3, 1.0);
uniform vec4 shallow : source_color = vec4(0.2, 0.45, 0.45, 0.85);
uniform vec4 sky_tint : source_color = vec4(0.7, 0.84, 0.95, 1.0);
uniform float amp = 0.08;
uniform float scale = 0.18;
uniform float speed = 1.0;
uniform vec2 flow = vec2(0.0, 0.0);
varying vec3 wpos;

float waves(vec2 p, float t) {
	return sin(p.x * scale + t * 1.3) * 0.5
		+ sin(p.y * scale * 1.4 - t * 1.1) * 0.35
		+ sin((p.x + p.y) * scale * 2.3 + t * 2.1) * 0.15;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wpos.xz + flow * TIME;
	VERTEX.y += waves(p, TIME * speed) * amp;
}

void fragment() {
	float t = TIME * speed;
	vec2 p = wpos.xz + flow * TIME;
	float e = 0.5;
	float hx = waves(p + vec2(e, 0.0), t) - waves(p - vec2(e, 0.0), t);
	float hz = waves(p + vec2(0.0, e), t) - waves(p - vec2(0.0, e), t);
	vec2 q = p * 1.7;
	float r1 = sin(q.x * 1.9 + t * 2.7) * cos(q.y * 1.3 - t * 2.2);
	float r2 = sin(q.x * 0.7 - q.y * 1.6 + t * 1.5);
	vec3 nw = normalize(vec3(-(hx * amp * 3.0 + r1 * 0.035 + r2 * 0.02), 1.0, -(hz * amp * 3.0 + r2 * 0.035)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 base = mix(shallow.rgb, deep.rgb, 0.45 + 0.4 * fres);
	ALBEDO = mix(base, sky_tint.rgb * 0.7, fres * 0.35);
	ALPHA = mix(shallow.a, 1.0, fres * 0.7);
	ROUGHNESS = 0.22;
	SPECULAR = 0.35;
}
"""

const GRASS_CODE := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform vec4 albedo : source_color = vec4(0.3, 0.5, 0.2, 1.0);
uniform float strength = 1.0;

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float gust = sin(TIME * 0.6 + root.x * 0.05) * 0.5 + 0.5;
	float sway = (sin(TIME * 1.8 + root.x * 0.35 + root.z * 0.25) * 0.10
		+ sin(TIME * 3.3 + root.x * 1.1 - root.z * 0.7) * 0.035) * (0.6 + gust * 0.8) * strength;
	float k = clamp(VERTEX.y * 2.4 + 0.5, 0.0, 1.0);
	VERTEX.x += sway * k;
	VERTEX.z += sway * 0.6 * k;
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.9;
}
"""

const TERRAIN_CODE := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

uniform float strata = 0.3;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = vnoise(wpos.xz * 0.3) * 0.55 + vnoise(wpos.xz * 1.6) * 0.3 + vnoise(wpos.xz * 7.0) * 0.15;
	// sedimentary bands on steep faces (sandstone cliffs, rock domes)
	float steep = smoothstep(0.35, 0.8, 1.0 - wnorm.y);
	float band = sin(wpos.y * 2.6 + vnoise(wpos.xz * 0.15) * 4.0) * 0.5 + 0.5;
	float fine = sin(wpos.y * 9.0 + n * 3.0) * 0.5 + 0.5;
	n = mix(n, band * 0.75 + fine * 0.25, steep * strata);
	vec3 c = pow(COLOR.rgb, vec3(1.2));
	float contrast = mix(0.4, 0.95, steep * strata);
	ALBEDO = c * (1.0 - contrast * 0.5 + contrast * n);
	ROUGHNESS = 1.0;
}
"""

static func water(deep: Color, shallow: Color, amp := 0.08, scale := 0.18, flow := Vector2.ZERO) -> ShaderMaterial:
	if _water_shader == null:
		_water_shader = Shader.new()
		_water_shader.code = WATER_CODE
	var m := ShaderMaterial.new()
	m.shader = _water_shader
	m.set_shader_parameter("deep", deep)
	m.set_shader_parameter("shallow", shallow)
	m.set_shader_parameter("amp", amp)
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("flow", flow)
	waters = waters.filter(func(w): return is_instance_valid(w))
	waters.append(m)
	return m

static func set_sky_tint(c: Color) -> void:
	for w in waters:
		if is_instance_valid(w):
			(w as ShaderMaterial).set_shader_parameter("sky_tint", c)

static func grass(c: Color, strength := 1.0) -> ShaderMaterial:
	if _grass_shader == null:
		_grass_shader = Shader.new()
		_grass_shader.code = GRASS_CODE
	var m := ShaderMaterial.new()
	m.shader = _grass_shader
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("strength", strength)
	return m

static func terrain(strata := 0.3) -> ShaderMaterial:
	if _terrain_shader == null:
		_terrain_shader = Shader.new()
		_terrain_shader.code = TERRAIN_CODE
	var m := ShaderMaterial.new()
	m.shader = _terrain_shader
	m.set_shader_parameter("strata", strata)
	return m

const FOLIAGE_CODE := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec4 albedo : source_color = vec4(0.3, 0.5, 0.2, 1.0);
uniform float strength = 1.0;
uniform float base_h = 0.15;
uniform float top_h = 1.4;
void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float k = smoothstep(base_h, top_h, VERTEX.y);
	k *= k;
	float gust = sin(TIME * 0.5 + root.x * 0.04 + root.z * 0.03) * 0.5 + 0.5;
	float sway = sin(TIME * 1.2 + root.x * 0.21 + root.z * 0.17) * (0.5 + gust);
	float flutter = sin(TIME * 4.5 + VERTEX.x * 6.0 + VERTEX.z * 5.0) * 0.15;
	VERTEX.x += (sway * 0.045 + flutter * 0.01) * k * strength;
	VERTEX.z += (sway * 0.03 - flutter * 0.01) * k * strength;
}
void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.9;
}
"""
static var _foliage_shader: Shader
static var _foliage_cache := {}

## Wind-swayed version of a flat-colored model material (trees, bushes).
static func foliage(c: Color, strength := 1.0, top_h := 1.4) -> ShaderMaterial:
	var key := c.to_html() + str(strength) + str(top_h)
	if _foliage_cache.has(key):
		return _foliage_cache[key]
	if _foliage_shader == null:
		_foliage_shader = Shader.new()
		_foliage_shader.code = FOLIAGE_CODE
	var m := ShaderMaterial.new()
	m.shader = _foliage_shader
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("top_h", top_h)
	_foliage_cache[key] = m
	return m

## A plane subdivided enough for vertex waves.
static func water_plane(size: Vector2, cell := 4.0) -> PlaneMesh:
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = int(size.x / cell)
	pm.subdivide_depth = int(size.y / cell)
	return pm
