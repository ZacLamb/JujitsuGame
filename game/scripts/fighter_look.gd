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

## Textured Meshy bodies: the baked gi / belt / skin texture, recoloured in the shader. mask_tex
## (tools/meshybuild/mask.py) holds R = belt texels, G = bare-skin regions; belt texels take the
## belt colour, bright desaturated texels the gi colour, warm texels the skin tone.
const TEX_CODE := """
shader_type spatial;
render_mode diffuse_toon, specular_disabled;
%STENCIL%
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_disable;
uniform vec4 gi : source_color = vec4(1.0);
uniform vec4 gi_ref : source_color = vec4(0.85, 0.85, 0.85, 1.0);
uniform vec4 belt : source_color = vec4(0.05, 0.05, 0.05, 1.0);
uniform vec4 skin : source_color = vec4(0.6, 0.45, 0.4, 1.0);
uniform vec4 skin_ref : source_color = vec4(0.6, 0.45, 0.4, 1.0);
uniform vec4 pants : source_color = vec4(1.0);
uniform vec4 accent : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform int pattern = 0;
uniform float pscale = 1.0;
uniform float rim_amount = 0.2;
varying vec4 bpw;
%PATLIB%
void vertex() {
	bpw = CUSTOM0;
}
void fragment() {
	vec3 bp = bpw.xyz * pscale;
%PATBODY%
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 mk3 = texture(mask_tex, UV).rgb;
	vec2 mk = mk3.rg;
	vec3 cs = pow(c, vec3(1.0 / 2.2));
	float mx = max(cs.r, max(cs.g, cs.b));
	float mn = min(cs.r, min(cs.g, cs.b));
	float sat = (mx - mn) / max(mx, 0.001);
	float lum = dot(cs, vec3(0.299, 0.587, 0.114));
	float sat_e = sat * smoothstep(0.04, 0.16, mx);   // near-black texels read as neutral
	float gm = smoothstep(0.3, 0.5, lum) * (1.0 - smoothstep(0.08, 0.2, sat)) * (1.0 - mk.g) * (1.0 - mk.r);
	float warm = step(cs.b, cs.g) * step(cs.g, cs.r);
	float sm = warm * smoothstep(0.12, 0.24, sat) * smoothstep(0.06, 0.14, lum) * (1.0 - gm);
	float bm = mk.r;
	vec3 W = vec3(0.2126, 0.7152, 0.0722);
	vec3 o = c;
	vec3 cloth = mix(gi.rgb, pants.rgb, step(0.5, bpw.w));
	cloth = mix(cloth, accent.rgb, clamp(m, 0.0, 1.0) * accent.a);
	o = mix(o, c * (cloth / max(gi_ref.rgb, vec3(0.05))), gm);
	float sk = dot(c, W) / max(dot(skin_ref.rgb, W), 0.01);
	o = mix(o, skin.rgb * clamp(sk, 0.0, 1.0) * 0.88, sm);
	o = mix(o, belt.rgb * clamp(0.6 + lum * 1.6, 0.0, 1.1), bm);
	// no-gi bodies: dark painted cloth takes the gear colour; folds come from its brightness
	float dk = mk3.b * (1.0 - sm);
	vec3 tint = cloth * (0.35 + lum * 2.4);
	o = mix(o, mix(tint, c, step(dot(cloth, W), 0.06)), dk);
	ALBEDO = clamp(o, 0.0, 1.0);
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

static var _tex := {}
static func tex_shader(ref: int) -> Shader:
	if not _tex.has(ref):
		var s := Shader.new()
		var lib := MAIN_CODE.substr(MAIN_CODE.find("vec3 h3("), MAIN_CODE.find("void vertex()") - MAIN_CODE.find("vec3 h3("))
		var a := MAIN_CODE.find("\tfloat m = 0.0;")
		var body := MAIN_CODE.substr(a, MAIN_CODE.find("\tALBEDO = mix(base") - a)
		s.code = TEX_CODE.replace("%STENCIL%", "stencil_mode write, compare_always, %d;" % ref if ref > 0 else "") \
			.replace("%PATLIB%", lib).replace("%PATBODY%", body)
		_tex[ref] = s
	return _tex[ref]

## Material for a textured Meshy body (see TEX_CODE). mi carries the albedo path and colour refs.
static func textured(mi: MeshInstance3D, jacket: Dictionary, pants_l: Dictionary, belt_c: Color, skin_c: Color,
		grow: float, ref := 0, team := Color(0, 0, 0, 0), ink := Color(0.09, 0.07, 0.06)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = tex_shader(ref)
	var gi_c: Color = jacket.get("color", Color.WHITE)
	m.set_shader_parameter("pants", pants_l.get("color", gi_c))
	# one pattern for the whole gi: the jacket's, else the pants'
	var pl: Dictionary = jacket if str(jacket.get("pattern", "none")) != "none" else pants_l
	m.set_shader_parameter("accent", pl.get("accent", Color(0, 0, 0, 0)))
	m.set_shader_parameter("pattern", int(PATTERNS.get(str(pl.get("pattern", "none")), 0)))
	m.set_shader_parameter("pscale", float(pl.get("pscale", 1.0)))
	m.set_shader_parameter("albedo_tex", load(str(mi.get_meta("albedo"))))
	m.set_shader_parameter("mask_tex", load(str(mi.get_meta("albedo")).replace("_albedo", "_mask")))
	m.set_shader_parameter("gi", gi_c)
	m.set_shader_parameter("gi_ref", mi.get_meta("gi_ref", Color(0.85, 0.85, 0.85)))
	m.set_shader_parameter("belt", belt_c)
	m.set_shader_parameter("skin", skin_c)
	m.set_shader_parameter("skin_ref", mi.get_meta("skin_ref", Color(0.6, 0.45, 0.4)))
	m.set_shader_parameter("rim_amount", 0.35 if ref > 0 else 0.15)
	_chain(m, grow, ref, team, ink)
	return m

## Toon-shaded texture as-is (modular heads: their skin and hair are painted, not recoloured).
const PLAIN_CODE := """
shader_type spatial;
render_mode diffuse_toon, specular_disabled;
%STENCIL%
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float rim_amount = 0.2;
uniform vec3 neck_skin = vec3(0.7, 0.5, 0.4);
uniform float neck_mix = 0.0;   // heads: vertex colour R fades the bust's collar to skin
void fragment() {
	ALBEDO = mix(texture(albedo_tex, UV).rgb, neck_skin, COLOR.r * neck_mix);
	ROUGHNESS = 0.85;
	RIM = rim_amount;
	RIM_TINT = 0.5;
}
"""
static var _plain := {}
static func plain_textured(tex: Texture2D, grow: float, ref := 0, team := Color(0, 0, 0, 0), ink := Color(0.09, 0.07, 0.06)) -> ShaderMaterial:
	if not _plain.has(ref):
		var sh := Shader.new()
		sh.code = PLAIN_CODE.replace("%STENCIL%", "stencil_mode write, compare_always, %d;" % ref if ref > 0 else "")
		_plain[ref] = sh
	var m := ShaderMaterial.new()
	m.shader = _plain[ref]
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("rim_amount", 0.35 if ref > 0 else 0.15)
	_chain(m, grow, ref, team, ink)
	return m

static func _chain(m: ShaderMaterial, grow: float, ref: int, team: Color, ink: Color) -> void:
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
