class_name FighterLook
extends RefCounted
## Materials for the sculpted fighter models: one toon shader that paints gear patterns (jaguar
## rosettes, croc scales, stripes...) from bind-space coordinates stored in UV/UV2, so a pattern
## sticks to the cloth while the body animates. Each material chains an ink outline pass and, in
## rolls, an x-ray pass in the fighter's team colour (stencil: shows where another body hides it).

const PATTERNS := {"none": 0, "spots": 1, "scales": 2, "stripes": 3, "waves": 4, "camo": 5, "mane": 6, "feathers": 7}

const MAIN_CODE := """
shader_type spatial;
render_mode diffuse_toon, specular_disabled;
%STENCIL%
uniform vec4 base : source_color = vec4(1.0);
uniform vec4 accent : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform int pattern = 0;
uniform float pscale = 1.0;
uniform float rim_amount = 0.2;
varying vec3 bp;

vec3 h3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}
vec2 worley(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int x = -1; x <= 1; x++) for (int y = -1; y <= 1; y++) for (int z = -1; z <= 1; z++) {
		vec3 g = vec3(float(x), float(y), float(z));
		vec3 o = h3(i + g);
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return vec2(d1, d2);
}
float vn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h3(i).x, b = h3(i + vec3(1, 0, 0)).x, c = h3(i + vec3(0, 1, 0)).x, d = h3(i + vec3(1, 1, 0)).x;
	float e = h3(i + vec3(0, 0, 1)).x, g = h3(i + vec3(1, 0, 1)).x, hh = h3(i + vec3(0, 1, 1)).x, k = h3(i + vec3(1, 1, 1)).x;
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(hh, k, f.x), f.y), f.z);
}

void vertex() {
	bp = vec3(UV.x, UV.y, UV2.x) * pscale;
}

void fragment() {
	float m = 0.0;
	if (pattern == 1) {        // jaguar rosettes
		vec2 w = worley(bp * 13.0);
		m = smoothstep(0.42, 0.36, w.x) - smoothstep(0.24, 0.18, w.x) * 0.9;
	} else if (pattern == 2) { // croc scales
		vec2 w = worley(bp * vec3(16.0, 16.0, 11.0));
		m = 1.0 - smoothstep(0.02, 0.09, w.y - w.x);
	} else if (pattern == 3) { // diagonal stripes
		m = step(0.62, fract((bp.x * 0.7 + bp.z + bp.y * 0.3) * 7.0));
	} else if (pattern == 4) { // waterfall waves
		m = smoothstep(0.55, 0.6, sin(bp.z * 34.0 + sin(bp.x * 14.0 + bp.y * 9.0) * 1.8) * 0.5 + 0.5);
	} else if (pattern == 5) { // camo
		float n = vn(bp * 7.0) * 0.65 + vn(bp * 15.0) * 0.35;
		m = smoothstep(0.52, 0.56, n);
	} else if (pattern == 6) { // lion's mane: gold rises over the shoulders
		float s = vn(vec3(bp.x * 22.0, bp.y * 22.0, 0.0));
		m = smoothstep(0.38 + s * 0.12, 0.62, bp.z / max(pscale, 0.001));
	} else if (pattern == 7) { // macaw feathers
		vec2 w = worley(bp * vec3(10.0, 10.0, 20.0));
		m = smoothstep(0.3, 0.2, w.x);
	}
	ALBEDO = mix(base.rgb, accent.rgb, clamp(m, 0.0, 1.0) * accent.a);
	ROUGHNESS = 0.85;
	RIM = rim_amount;
	RIM_TINT = 0.5;
}
"""

const OUTLINE_CODE := """
shader_type spatial;
render_mode unshaded, cull_front, specular_disabled, shadows_disabled;
uniform vec4 ink : source_color = vec4(0.09, 0.07, 0.06, 1.0);
uniform float grow = 0.01;
void vertex() {
	VERTEX += NORMAL * grow;
}
void fragment() {
	ALBEDO = ink.rgb;
}
"""

const XRAY_CODE := """
shader_type spatial;
render_mode unshaded, depth_test_inverted, depth_draw_never, blend_mix, cull_back, shadows_disabled, specular_disabled;
stencil_mode read, compare_not_equal, %REF%;
uniform vec4 team : source_color = vec4(1.0, 0.8, 0.2, 0.42);
void fragment() {
	ALBEDO = team.rgb;
	ALPHA = team.a;
}
"""

static var _main := {}
static var _xray := {}
static var _outline: Shader

static func main_shader(ref: int) -> Shader:
	if not _main.has(ref):
		var s := Shader.new()
		s.code = MAIN_CODE.replace("%STENCIL%", "stencil_mode write, compare_always, %d;" % ref if ref > 0 else "")
		_main[ref] = s
	return _main[ref]

static func xray_shader(ref: int) -> Shader:
	if not _xray.has(ref):
		var s := Shader.new()
		s.code = XRAY_CODE.replace("%REF%", str(ref))
		_xray[ref] = s
	return _xray[ref]

static func outline_shader() -> Shader:
	if _outline == null:
		_outline = Shader.new()
		_outline.code = OUTLINE_CODE
	return _outline

## A gear / skin material. look: {color, accent, pattern, pscale}. grow: outline width in mesh units
## (0 = no outline). ref > 0 enables the team x-ray (rolls only).
static func material(look: Dictionary, grow: float, ref := 0, team := Color(0, 0, 0, 0), ink := Color(0.09, 0.07, 0.06)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = main_shader(ref)
	m.set_shader_parameter("base", look.get("color", Color.WHITE))
	var acc: Color = look.get("accent", Color(0, 0, 0, 0))
	m.set_shader_parameter("accent", acc)
	m.set_shader_parameter("pattern", int(PATTERNS.get(str(look.get("pattern", "none")), 0)))
	m.set_shader_parameter("pscale", float(look.get("pscale", 1.0)))
	m.set_shader_parameter("rim_amount", 0.35 if ref > 0 else 0.2)
	var last: Material = m
	if grow > 0.0:
		var o := ShaderMaterial.new()
		o.shader = outline_shader()
		o.set_shader_parameter("grow", grow)
		o.set_shader_parameter("ink", ink if ref == 0 else ink.lerp(team.darkened(0.25), 0.45))
		m.next_pass = o
		last = o
	if ref > 0:
		var x := ShaderMaterial.new()
		x.shader = xray_shader(ref)
		x.set_shader_parameter("team", Color(team, 0.42))
		last.next_pass = x
	return m
