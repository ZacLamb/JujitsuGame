class_name TownKit
extends RefCounted
## Colonial buildings from tools/townbuild/houses.py (Blender), dressed with the painted tiling
## textures (assets/textures/env). Every building type is drawn as one MultiMesh: per-instance
## colour = wall tint, per-instance custom data = shutter / door tint. Surfaces are matched by the
## material names the Blender script gives them (wall, base, trim, roof, wood, glass, iron).

const KINDS := ["casa_a", "casa_b", "casa_c", "casa_d", "casa_varanda", "sobrado_a", "sobrado_loja", "igreja", "academia"]

const CODE := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.4;
uniform int tint = 0;          // 0 none, 1 instance colour (walls), 2 instance custom (wood)
uniform vec3 mult = vec3(1.0);
uniform float rough = 0.9;
varying vec3 wpos;
varying vec3 wnrm;
varying vec4 icol;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	icol = tint == 1 ? COLOR : (tint == 2 ? INSTANCE_CUSTOM : vec4(1.0));
}
void fragment() {
	vec3 w = pow(abs(wnrm), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 t = texture(tex, wpos.zy * scale).rgb * w.x + texture(tex, wpos.xz * scale).rgb * w.y + texture(tex, wpos.xy * scale).rgb * w.z;
	vec3 base = tint == 0 ? t : t * icol.rgb * 1.25;
	ALBEDO = base * mult;
	ROUGHNESS = rough;
}
"""
static var _shader: Shader
static var _mats := {}
static var _meshes := {}

static func _mat(kind: String) -> Material:
	if _mats.has(kind):
		return _mats[kind]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	var m := ShaderMaterial.new()
	m.shader = _shader
	match kind:
		"wall":
			m.set_shader_parameter("tex", EnvShaders.env_tex("plaster")); m.set_shader_parameter("tint", 1); m.set_shader_parameter("scale", 0.35)
		"base":
			m.set_shader_parameter("tex", EnvShaders.env_tex("plaster")); m.set_shader_parameter("tint", 1); m.set_shader_parameter("mult", Vector3(0.55, 0.55, 0.55))
		"trim":
			m.set_shader_parameter("tex", EnvShaders.env_tex("plaster")); m.set_shader_parameter("mult", Vector3(1.04, 1.03, 1.0))
		"roof":
			m.set_shader_parameter("tex", EnvShaders.env_tex("roof")); m.set_shader_parameter("scale", 0.55)
		"wood":
			m.set_shader_parameter("tex", EnvShaders.env_tex("wood")); m.set_shader_parameter("tint", 2); m.set_shader_parameter("scale", 0.9)
		"glass":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.13, 0.17, 0.22)
			g.roughness = 0.15
			g.metallic_specular = 0.8
			_mats[kind] = g
			return g
		"iron":
			var ir := StandardMaterial3D.new()
			ir.albedo_color = Color(0.08, 0.08, 0.09)
			ir.roughness = 0.6
			_mats[kind] = ir
			return ir
	_mats[kind] = m
	return m

## The building's mesh with every surface re-dressed (cached per kind).
static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var sc: Node = (load("res://assets/models/town/%s.glb" % kind) as PackedScene).instantiate()
	var src: MeshInstance3D = sc.find_children("*", "MeshInstance3D", true, false)[0]
	var m := (src.mesh as ArrayMesh).duplicate() as ArrayMesh
	for i in m.get_surface_count():
		var nm := ""
		var sm := m.surface_get_material(i)
		if sm:
			nm = sm.resource_name
		if src.get_surface_override_material(i):
			nm = src.get_surface_override_material(i).resource_name
		m.surface_set_material(i, _mat(nm if nm in ["wall", "base", "trim", "roof", "wood", "glass", "iron"] else "trim"))
	sc.free()
	_meshes[kind] = m
	return m

static func size(kind: String) -> Vector3:
	return mesh(kind).get_aabb().size

## One MultiMeshInstance3D per kind. items: [{kind, xform, wall: Color, wood: Color}]
static func build(parent: Node3D, items: Array) -> void:
	var by_kind := {}
	for it in items:
		if not by_kind.has(it.kind):
			by_kind[it.kind] = []
		by_kind[it.kind].append(it)
	for k in by_kind:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh(k)
		mm.instance_count = by_kind[k].size()
		for i in by_kind[k].size():
			var it: Dictionary = by_kind[k][i]
			mm.set_instance_transform(i, it.xform)
			mm.set_instance_color(i, it.wall)
			mm.set_instance_custom_data(i, it.wood)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Town_" + k
		mmi.multimesh = mm
		parent.add_child(mmi)
