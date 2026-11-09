class_name BodyRig
extends Node3D
## Stylized low-poly grappler built from primitives, with named joints that can be posed
## and tweened. Limbs hang along -Y; +X rotation swings a limb forward (toward -Z).

const JOINTS := ["spine", "neck", "l_sh", "l_el", "r_sh", "r_el", "l_hip", "l_kn", "r_hip", "r_kn"]

var gi_color := Color(0.95, 0.95, 0.93)
var belt_color := Color(0.95, 0.95, 0.93)
var skin_color := Color(0.78, 0.57, 0.4)
var hair_color := Color(0.12, 0.08, 0.05)

var hips: Node3D
var lapel_override := Color(0, 0, 0, 0)  # alpha 0 = derive from the gi
var rash_color := Color(0, 0, 0, 0)      # alpha 0 = no rashguard showing
var build := Vector2.ONE                 # class build: (width, height) multipliers
var crest := ""                          # class id: its crest is painted on the back
var _crest_node: Node3D
var joints := {}
var _walk_t := 0.0
var _tween: Tween

static var _mat_cache := {}
static var _outline: StandardMaterial3D

## Shared toon material (cel shading + soft rim). Used by characters and the world.
static func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var key := c.to_html() + str(rough)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON if rough < 0.5 else BaseMaterial3D.SPECULAR_DISABLED
	m.rim_enabled = true
	m.rim = 0.18
	m.rim_tint = 0.6
	_mat_cache[key] = m
	return m

## Character material: toon + inked outline pass.
static func _cmat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var key := "c" + c.to_html() + str(rough)
	if _mat_cache.has(key):
		return _mat_cache[key]
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.albedo_color = Color(0.09, 0.07, 0.06)
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.grow = true
		_outline.grow_amount = 0.011
	var m := (_mat(c, rough) as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.next_pass = _outline
	_mat_cache[key] = m
	return m

var hair_style := -1  # 0 short, 1 buzz, 2 bun, 3 curly, 4 bald, 5 long

# ---- skinned model mode (CC0 Quaternius characters driven by this rig)
# The female model (rogue.glb) has a hood baked into its head that does not recolor cleanly yet,
# so both body types use the worker model until a better CC0 female base is added.
const MODELS := {"male": "res://assets/models/worker.glb", "female": "res://assets/models/worker.glb"}
## Sculpted fighter meshes (tools/charbuild) skinned to the worker skeleton: body, face, hair styles
## and every gear piece as its own mesh.
const FIGHTERS := {"male": "res://assets/models/fighter_male.scn", "female": "res://assets/models/fighter_female.scn"}
## Textured Meshy bodies (tools/import_meshy.gd): used for plain gi looks; gear with patterns, no-gi
## and casual clothes keep the sculpted piece models above.
static var MESHY := {"male": "res://assets/models/hero_gi_m.scn", "female": "res://assets/models/hero_gi_f.scn"}
static var MESHY_NOGI := {"male": "res://assets/models/hero_nogi_m.scn", "female": "res://assets/models/hero_nogi_f.scn"}
## Modular faces (tools/meshybuild/heads.sh). Any face fits any body; NPCs pick by hash.
const HEADS := ["fade", "curly", "blond", "goatee", "topknot", "braid", "puff", "pixie"]
const HEAD_NAMES := {"fade": "Fade & beard", "curly": "Curls", "blond": "Surfer", "goatee": "Old guard",
	"topknot": "Top knot", "braid": "Braid", "puff": "Puff", "pixie": "Pixie"}
const HEADS_M := ["fade", "curly", "blond", "goatee", "topknot"]
const HEADS_F := ["braid", "puff", "pixie"]
var _meshy_path := ""
static var use_meshy := true
var _meshy := false
## Body width for the Meshy bodies (1 = as modelled). 0 = pick from the look hash (0.92-1.1) so
## NPCs sharing a body still read as lighter / heavier builds.
var bulk := 0.0
## In-world combat (WorldCombat): stance when idle, short pose actions that lock locomotion.
var combat_ready := false
var _in_stance := false
var _action_until := 0.0

func in_action() -> bool:
	return Time.get_ticks_msec() * 0.001 < _action_until

## Plays [pose, root, seconds(, ease)] frames; locomotion waits until they finish (hold = until release()).
func action(frames: Array, hold := false) -> void:
	if frames.is_empty() or skel == null:
		return
	var tot := 0.0
	for f in frames:
		tot += float(f[2])
	_action_until = INF if hold else Time.get_ticks_msec() * 0.001 + tot
	_in_stance = false
	tween_frames(frames)

func release(frames: Array = []) -> void:
	_action_until = 0.0
	if not frames.is_empty():
		action(frames)
var smoother: PoseSmoother
const HAIR_NAMES := ["short", "buzz", "bun", "curly", "", "long", "ponytail"]
var look := {}            # gear look (Game.dress); empty = derived from the setup colours
var _pieces := {}         # piece name -> MeshInstance3D
var _team := Color(0, 0, 0, 0)
var _ref := 0
static var use_models := true
var body := ""            # "male" / "female"; "" picks from a hash
var casual := false       # villagers: shirt + pants, no belt
var skinned: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var _anim_mode := true
var _anim_names := {}
var _bones := {}
var _foot_rel := {}
var _belt_node: Node3D
var _model_scale := 1.0

func setup(gi: Color, belt: Color, skin: Color, hair := Color(0.12, 0.08, 0.05), style := -1, body_type := "", is_casual := false) -> BodyRig:
	gi_color = gi
	belt_color = belt
	skin_color = skin
	hair_color = hair
	casual = is_casual
	var h := absi(hash(gi.to_html() + skin.to_html() + hair.to_html()))
	hair_style = style if style >= 0 else h % 6
	body = body_type if body_type != "" else "male"
	_build()
	if use_models and ResourceLoader.exists(MODELS.get(body, "")):
		_build_skinned()
	return self

func set_belt_color(c: Color) -> void:
	if _meshy and _pieces.has("Body"):
		belt_color = c
		((_pieces.Body as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("belt", c)
		return
	if _pieces.has("Belt"):
		belt_color = c
		((_pieces.Belt as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("base", c)
		return
	belt_color = c
	for n in hips.find_children("Belt*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = _cmat(c, 0.7)
	if _belt_node:
		for n in _belt_node.get_children():
			(n as MeshInstance3D).material_override = _cmat(c, 0.7)
	if skel:
		_collect_lod()
		_apply_lod()

func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE, mname := "", outline := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _cmat(color) if outline else _mat(color)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	if mname != "":
		mi.name = mname
	parent.add_child(mi)
	return mi

static func _cyl(rt: float, rb: float, h: float, segs := 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m

static func _sph(r: float, h := -1.0, segs := 14) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h if h > 0 else r * 2.0
	m.radial_segments = segs
	m.rings = segs / 2
	return m

static func _cap(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0 + 0.01)
	m.radial_segments = 12
	m.rings = 4
	return m

func _capsule(parent: Node3D, radius: float, length: float, color: Color, offset := Vector3.ZERO, mname := "") -> MeshInstance3D:
	return _mesh(parent, _cap(radius, length), color, offset, Vector3.ZERO, Vector3.ONE, mname)

func _pivot(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = n
	p.position = pos
	parent.add_child(p)
	joints[n] = p
	return p

func _build() -> void:
	for c in get_children():
		c.queue_free()
	joints.clear()
	var gi := gi_color
	var gi_dark := gi.darkened(0.16)
	var skin := skin_color
	hips = Node3D.new()
	hips.name = "Hips"
	hips.position = Vector3(0, 0.95, 0)
	add_child(hips)

	# --- pelvis: gi pants seat + jacket skirt + belt with knot and tails
	_mesh(hips, _cap(0.17, 0.4), gi, Vector3(0, 0.0, 0), Vector3(0, 0, PI / 2), Vector3(1, 1, 0.85))
	_mesh(hips, _cyl(0.19, 0.225, 0.26), gi, Vector3(0, -0.02, 0), Vector3.ZERO, Vector3(1, 1, 0.8))
	_mesh(hips, _cyl(0.196, 0.196, 0.075, 16), belt_color, Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1, 1, 0.82), "BeltBand")
	_mesh(hips, _sph(0.045), belt_color, Vector3(0, 0.12, -0.165), Vector3.ZERO, Vector3(1.3, 1, 0.8), "BeltKnot")
	for side in [-1, 1]:
		_mesh(hips, BoxMesh.new(), belt_color, Vector3(0.045 * side, 0.02, -0.168), Vector3(0, 0, 0.22 * side), Vector3(0.055, 0.2, 0.02), "BeltTail%d" % side)

	# --- torso: tapered jacket, lapels, collar
	var spine := _pivot(hips, "spine", Vector3(0, 0.1, 0))
	_mesh(spine, _cyl(0.235, 0.19, 0.5, 14), gi, Vector3(0, 0.27, 0), Vector3.ZERO, Vector3(1, 1, 0.72))
	_mesh(spine, _sph(0.24), gi, Vector3(0, 0.5, 0), Vector3.ZERO, Vector3(1.0, 0.45, 0.72))
	for side in [-1, 1]:
		_mesh(spine, BoxMesh.new(), gi_dark, Vector3(0.055 * side, 0.32, -0.165), Vector3(0, 0, -0.38 * side), Vector3(0.06, 0.42, 0.02))
	_mesh(spine, _cyl(0.085, 0.11, 0.07, 14), gi_dark, Vector3(0, 0.6, 0.0))
	# a little patch on the shoulder (academy patch)
	_mesh(spine, BoxMesh.new(), Color(0.95, 0.75, 0.2), Vector3(0.26, 0.43, 0.0), Vector3(0, 0, 0.3), Vector3(0.02, 0.07, 0.07), "", false)

	# --- head
	var neck := _pivot(spine, "neck", Vector3(0, 0.62, 0))
	_mesh(neck, _cyl(0.055, 0.065, 0.1), skin, Vector3(0, 0.03, 0))
	var head := _mesh(neck, _sph(0.125, -1, 16), skin, Vector3(0, 0.17, 0), Vector3.ZERO, Vector3(0.95, 1.1, 1.0))
	head.name = "Head"
	for side in [-1, 1]:
		_mesh(neck, _sph(0.03), skin, Vector3(0.122 * side, 0.165, 0.01), Vector3.ZERO, Vector3(0.6, 1, 0.9))
		# eyes: white + pupil, brows
		_mesh(neck, _sph(0.022), Color(0.97, 0.97, 0.95), Vector3(0.045 * side, 0.185, -0.112), Vector3.ZERO, Vector3(1, 1.1, 0.6), "", false)
		_mesh(neck, _sph(0.012), Color(0.08, 0.06, 0.05), Vector3(0.045 * side, 0.183, -0.124), Vector3.ZERO, Vector3.ONE, "", false)
		_mesh(neck, BoxMesh.new(), hair_color.darkened(0.2), Vector3(0.046 * side, 0.218, -0.115), Vector3(0, 0, -0.18 * side), Vector3(0.05, 0.012, 0.012), "", false)
	_mesh(neck, PrismMesh.new(), skin.darkened(0.08), Vector3(0, 0.155, -0.128), Vector3(-PI / 2 + 0.3, 0, 0), Vector3(0.03, 0.04, 0.03), "", false)
	_mesh(neck, BoxMesh.new(), skin.darkened(0.35), Vector3(0, 0.115, -0.118), Vector3.ZERO, Vector3(0.04, 0.008, 0.01), "", false)
	_build_hair(neck)

	# --- arms: wide gi sleeves, wrists, hands
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var sh := _pivot(spine, side + "_sh", Vector3(0.27 * sx, 0.5, 0))
		_mesh(sh, _sph(0.085), gi, Vector3(0, -0.02, 0))
		_mesh(sh, _cyl(0.088, 0.078, 0.3), gi, Vector3(0, -0.15, 0))
		var el := _pivot(sh, side + "_el", Vector3(0, -0.3, 0))
		_mesh(el, _sph(0.074), gi, Vector3.ZERO)
		_mesh(el, _cyl(0.078, 0.07, 0.2), gi, Vector3(0, -0.1, 0))
		_mesh(el, _cyl(0.04, 0.038, 0.06), skin, Vector3(0, -0.22, 0))
		_mesh(el, _sph(0.055), skin, Vector3(0, -0.275, -0.01), Vector3.ZERO, Vector3(0.85, 1.15, 0.7))

	# --- legs: gi pants, cuffs, feet
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var hp := _pivot(hips, side + "_hip", Vector3(0.11 * sx, -0.02, 0))
		_mesh(hp, _cyl(0.105, 0.088, 0.44), gi, Vector3(0, -0.2, 0))
		var kn := _pivot(hp, side + "_kn", Vector3(0, -0.43, 0))
		_mesh(kn, _sph(0.088), gi, Vector3.ZERO)
		_mesh(kn, _cyl(0.088, 0.078, 0.36), gi, Vector3(0, -0.18, 0))
		_mesh(kn, _cyl(0.05, 0.045, 0.06), skin, Vector3(0, -0.385, 0))
		_mesh(kn, _cap(0.05, 0.24), skin, Vector3(0, -0.44, -0.06), Vector3(PI / 2, 0, 0), Vector3(1.1, 1, 0.6))

func _build_hair(neck: Node3D) -> void:
	var hc := hair_color
	match hair_style:
		0:  # short
			_mesh(neck, _sph(0.133, -1, 16), hc, Vector3(0, 0.205, 0.012), Vector3.ZERO, Vector3(1, 0.62, 1.04))
			_mesh(neck, _sph(0.06), hc, Vector3(0, 0.265, -0.07), Vector3.ZERO, Vector3(1.6, 0.6, 0.9))
		1:  # buzz cut
			_mesh(neck, _sph(0.129, -1, 16), hc, Vector3(0, 0.2, 0.008), Vector3.ZERO, Vector3(0.98, 0.6, 1.0))
		2:  # bun
			_mesh(neck, _sph(0.133, -1, 16), hc, Vector3(0, 0.205, 0.012), Vector3.ZERO, Vector3(1, 0.62, 1.04))
			_mesh(neck, _sph(0.06), hc, Vector3(0, 0.29, 0.09))
		3:  # curly
			for i in 9:
				var a := i * TAU / 9.0
				_mesh(neck, _sph(0.05), hc, Vector3(cos(a) * 0.09, 0.25 + 0.02 * sin(a * 2.0), sin(a) * 0.09 + 0.01))
			_mesh(neck, _sph(0.07), hc, Vector3(0, 0.29, 0.01))
		4:  # bald with a beard
			_mesh(neck, _sph(0.075), hc, Vector3(0, 0.105, -0.075), Vector3.ZERO, Vector3(1.3, 0.8, 0.7))
		5:  # long, tied back
			_mesh(neck, _sph(0.133, -1, 16), hc, Vector3(0, 0.205, 0.015), Vector3.ZERO, Vector3(1, 0.65, 1.06))
			_mesh(neck, _cap(0.045, 0.22), hc, Vector3(0, 0.12, 0.13), Vector3(0.3, 0, 0))

# ------------------------------------------------------------ posing
## pose = {"root_pos": Vector3, "root_rot": Vector3, "hip_h": float, joint_name: Vector3, ...}
func apply_pose(pose: Dictionary) -> void:
	_enter_pose_mode()
	hips.position.y = pose.get("hip_h", 0.95)
	hips.rotation = pose.get("hip_rot", Vector3.ZERO)
	for j in JOINTS:
		(joints[j] as Node3D).rotation = pose.get(j, Vector3.ZERO)

func tween_pose(pose: Dictionary, root: Transform3D, dur := 0.45) -> void:
	_enter_pose_mode()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "position", root.origin, dur)
	_tween.tween_property(self, "quaternion", root.basis.get_rotation_quaternion(), dur)
	_tween.tween_property(hips, "position:y", pose.get("hip_h", 0.95), dur)
	_tween.tween_property(hips, "rotation", pose.get("hip_rot", Vector3.ZERO), dur)
	for j in JOINTS:
		_tween.tween_property(joints[j], "rotation", pose.get(j, Vector3.ZERO), dur)

## Snapshot of the current pose + root, in the same shape tween_pose takes.
func current_pose() -> Dictionary:
	var p := {"hip_h": hips.position.y, "hip_rot": hips.rotation}
	for j in JOINTS:
		p[j] = (joints[j] as Node3D).rotation
	return p

func current_root() -> Transform3D:
	return Transform3D(Basis(quaternion), position)

## Plays keyframes in sequence: each frame is [pose, root Transform3D, seconds].
func tween_frames(frames: Array) -> void:
	_enter_pose_mode()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	var first := true
	for f in frames:
		var pose: Dictionary = f[0]
		var root: Transform3D = f[1]
		var dur: float = f[2]
		var ease_kind: int = f[3] if f.size() > 3 else Tween.EASE_IN_OUT
		if not first:
			_tween.chain()
		first = false
		_tween.tween_property(self, "position", root.origin, dur).set_trans(Tween.TRANS_CUBIC).set_ease(ease_kind)
		_tween.parallel().tween_property(self, "quaternion", root.basis.get_rotation_quaternion(), dur).set_trans(Tween.TRANS_CUBIC).set_ease(ease_kind)
		_tween.parallel().tween_property(hips, "position:y", pose.get("hip_h", 0.95), dur).set_trans(Tween.TRANS_CUBIC).set_ease(ease_kind)
		_tween.parallel().tween_property(hips, "rotation", pose.get("hip_rot", Vector3.ZERO), dur).set_trans(Tween.TRANS_CUBIC).set_ease(ease_kind)
		for j in JOINTS:
			_tween.parallel().tween_property(joints[j], "rotation", pose.get(j, Vector3.ZERO), dur).set_trans(Tween.TRANS_CUBIC).set_ease(ease_kind)

static func lerp_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {"hip_h": lerpf(float(a.get("hip_h", 0.95)), float(b.get("hip_h", 0.95)), t),
		"hip_rot": (a.get("hip_rot", Vector3.ZERO) as Vector3).lerp(b.get("hip_rot", Vector3.ZERO), t)}
	for j in JOINTS:
		out[j] = (a.get(j, Vector3.ZERO) as Vector3).lerp(b.get(j, Vector3.ZERO), t)
	return out

## Procedural walk / idle cycle for exploration. speed01: 0 idle .. 1 run.
func animate_locomotion(delta: float, speed01: float, airborne := false) -> void:
	if skel:
		if in_action():
			return
		# in a fight and standing still: hold a grappling stance instead of the idle clip
		if combat_ready and speed01 < 0.05 and not airborne:
			if _anim_mode or not _in_stance:
				_in_stance = true
				tween_pose(CombatAnim.stance(), current_root(), 0.22)
			return
		_in_stance = false
		_play_locomotion(speed01, airborne)
		return
	if airborne:
		var air := {"hip_h": 0.95, "l_hip": Vector3(0.6, 0, 0), "l_kn": Vector3(-1.0, 0, 0),
			"r_hip": Vector3(0.2, 0, 0), "r_kn": Vector3(-0.5, 0, 0),
			"l_sh": Vector3(0.4, 0, -0.6), "r_sh": Vector3(0.4, 0, 0.6), "l_el": Vector3(0.6, 0, 0), "r_el": Vector3(0.6, 0, 0)}
		_blend_to(air, delta * 10.0)
		return
	_walk_t += delta * lerpf(1.5, 11.0, speed01)
	var s := sin(_walk_t)
	var amp := lerpf(0.04, 0.75, speed01)
	var pose := {
		"hip_h": 0.95 + absf(cos(_walk_t)) * 0.05 * speed01 - 0.02,
		"spine": Vector3(-0.08 * speed01, 0, 0),
		"l_hip": Vector3(s * amp, 0, 0), "r_hip": Vector3(-s * amp, 0, 0),
		"l_kn": Vector3(-maxf(0.0, -s) * amp * 1.3 - 0.05, 0, 0), "r_kn": Vector3(-maxf(0.0, s) * amp * 1.3 - 0.05, 0, 0),
		"l_sh": Vector3(-s * amp * 0.8, 0, -0.12), "r_sh": Vector3(s * amp * 0.8, 0, 0.12),
		"l_el": Vector3(0.3 + 0.4 * speed01, 0, 0), "r_el": Vector3(0.3 + 0.4 * speed01, 0, 0),
	}
	if speed01 < 0.05:
		var breathe := sin(_walk_t * 0.8) * 0.03
		pose["spine"] = Vector3(breathe, 0, 0)
		pose["hip_h"] = 0.95
	_blend_to(pose, delta * 14.0)

func _blend_to(pose: Dictionary, t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	hips.position.y = lerpf(hips.position.y, pose.get("hip_h", 0.95), t)
	hips.rotation = hips.rotation.lerp(pose.get("hip_rot", Vector3.ZERO), t)
	for j in JOINTS:
		var n := joints[j] as Node3D
		n.rotation = n.rotation.lerp(pose.get(j, Vector3.ZERO), t)


# ================================================================ skinned model support
## Class crest on the back (WoW tabard-style): the painted class icon in a ring of class colour.
const CREST_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 ring : source_color = vec4(1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	vec3 c = texture(tex, (p / 0.8) * 0.5 + 0.5).rgb;
	float edge = smoothstep(0.78, 0.82, r);
	c = mix(c, ring.rgb, edge);
	c = mix(c, ring.rgb * 0.35, smoothstep(0.93, 0.97, r));
	ALBEDO = c * 0.92;
}
"""
static var _crest_shader: Shader

func _build_crest() -> void:
	if _crest_node and is_instance_valid(_crest_node):
		_crest_node.queue_free()
	_crest_node = null
	if crest == "" or casual or not skel:
		return
	var tx := IconArt.tex("class_" + crest)
	if tx == null:
		return
	if _crest_shader == null:
		_crest_shader = Shader.new()
		_crest_shader.code = CREST_CODE
	_crest_node = Node3D.new()
	_crest_node.name = "Crest"
	add_child(_crest_node)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.3, 0.3)
	q.mesh = qm
	var m := ShaderMaterial.new()
	m.shader = _crest_shader
	m.set_shader_parameter("tex", tx)
	m.set_shader_parameter("ring", Rpg.class_color(crest))
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crest_node.add_child(q)

func _update_crest() -> void:
	if not _crest_node or _bones.get("Abdomen", -1) < 0 or _bones.get("Neck", -1) < 0:
		return
	var sx := skel.global_transform
	var ab := (sx * skel.get_bone_global_pose(_bones["Abdomen"])).origin
	var nk := (sx * skel.get_bone_global_pose(_bones["Neck"])).origin
	var right := global_transform.basis.x
	if _bones["UpperArm.L"] >= 0 and _bones["UpperArm.R"] >= 0:
		right = (sx * skel.get_bone_global_pose(_bones["UpperArm.R"])).origin - (sx * skel.get_bone_global_pose(_bones["UpperArm.L"])).origin
	var b := _frame(right, nk - ab)
	var gs := global_transform.basis.get_scale()
	_crest_node.global_transform = Transform3D(b.scaled(gs * build.x), ab.lerp(nk, CREST_UP + (0.1 if _meshy_path.contains("_gi_") else 0.0)) + b.z * ((CREST_BACK + (0.06 if _meshy_path.contains("_gi_") else 0.0)) if _meshy else 0.26) * gs.x * build.x)

const CREST_UP := 0.72
const CREST_BACK := 0.27

func _build_skinned() -> void:
	for n in [_torso_parts, _hair_node]:
		if n and is_instance_valid(n):
			n.queue_free()
	for g in _gi_parts:
		if is_instance_valid(g.node):
			(g.node as Node).queue_free()
	_gi_parts.clear()
	_torso_parts = null
	_hair_node = null
	_belt_node = null
	# hide the primitive body; it stays as an invisible pose guide
	for m in hips.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).visible = false
	var sc: PackedScene = load(MODELS[body])
	skinned = sc.instantiate()
	skinned.rotation.y = PI  # models face +Z; this rig faces -Z
	add_child(skinned)
	var sk := skinned.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		skinned.queue_free()
		skinned = null
		return
	skel = sk[0]
	smoother = PoseSmoother.new()
	skel.add_child(smoother)
	var ap := skinned.find_children("*", "AnimationPlayer", true, false)
	anim = ap[0] if not ap.is_empty() else null
	if anim:
		for a in anim.get_animation_list():
			var short := str(a).get_slice("|", 1) if str(a).contains("|") else str(a)
			short = short.trim_prefix("Man_")
			if not _anim_names.has(short) or str(a).contains("|"):
				_anim_names[short] = a
			for loop_name in ["Idle", "Walk", "Run"]:
				if short == loop_name:
					anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	for n in ["Hips", "Abdomen", "Torso", "Neck", "Head", "UpperArm.L", "LowerArm.L", "UpperArm.R", "LowerArm.R",
			"UpperLeg.L", "LowerLeg.L", "UpperLeg.R", "LowerLeg.R", "Foot.L", "Foot.R", "Palm.L", "Palm.R", "Fist.L", "Fist.R"]:
		_bones[n] = skel.find_bone(n)
	_bones["Hand.L"] = _bones["Palm.L"] if _bones["Palm.L"] >= 0 else _bones["Fist.L"]
	_bones["Hand.R"] = _bones["Palm.R"] if _bones["Palm.R"] >= 0 else _bones["Fist.R"]
	# scale so the model's hips sit where this rig's hips are
	# skeleton-to-model transform (independent of being in the tree)
	var chain := skel.transform
	var p := skel.get_parent()
	while p and p != skinned:
		if p is Node3D:
			chain = (p as Node3D).transform * chain
		p = p.get_parent()
	var hy := (chain * skel.get_bone_global_rest(_bones["Hips"])).origin.y
	_model_scale = 0.95 / maxf(hy, 0.01)
	skinned.scale = Vector3.ONE * _model_scale
	for side in ["L", "R"]:
		var lb: int = _bones["LowerLeg." + side]
		var fb: int = _bones["Foot." + side]
		if lb >= 0 and fb >= 0:
			_foot_rel[side] = skel.get_bone_global_rest(lb).affine_inverse() * skel.get_bone_global_rest(fb)
	if ResourceLoader.exists(FIGHTERS.get(body, "")):
		_attach_fighter()
	else:
		_recolor()
		if not casual:
			_build_skinned_belt()
		if body == "female":
			_build_ponytail()
	if body == "female":
		skinned.scale *= Vector3(0.95, 0.94, 0.95)
	if _meshy:
		var w := bulk
		if w <= 0.0:
			w = 0.92 + float(absi(hash(gi_color.to_html() + skin_color.to_html() + belt_color.to_html())) % 1000) / 1000.0 * 0.18
		skinned.scale *= Vector3(w, 1.0, w)
	skinned.scale *= Vector3(build.x, build.y, build.x)
	_build_crest()
	_play_locomotion(0.0, false)
	_collect_lod()

## The worker model's shoes share the "Eyes" material; split them into a "Feet" surface (once per
## mesh) so fighters can be barefoot on the mats.
static var _barefoot_cache := {}
static func _barefoot(src: Mesh) -> Mesh:
	if _barefoot_cache.has(src):
		return _barefoot_cache[src]
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		var arr := src.surface_get_arrays(i)
		var mat := src.surface_get_material(i)
		var nm := mat.resource_name if mat else ""
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var fmt: int = src.surface_get_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		# Eyes: shoes are the triangles below the waist. Skin: bare legs are below the shorts' hem.
		var cut := 0.0 if nm == "Eyes" else -0.3
		var split_name := "Feet" if nm == "Eyes" else "Legs"
		if (nm != "Eyes" and nm != "Skin") or idx.is_empty():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
			out.surface_set_material(out.get_surface_count() - 1, mat)
			continue
		var keep := PackedInt32Array()
		var low := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var zc := (verts[idx[t]].z + verts[idx[t + 1]].z + verts[idx[t + 2]].z) / 3.0
			var dst := low if zc < cut else keep
			dst.append(idx[t]); dst.append(idx[t + 1]); dst.append(idx[t + 2])
		for pair in [[keep, mat], [low, null]]:
			if (pair[0] as PackedInt32Array).is_empty():
				continue
			var a2 := arr.duplicate()
			a2[Mesh.ARRAY_INDEX] = pair[0]
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2, [], {}, fmt)
			var fm := StandardMaterial3D.new()
			fm.resource_name = split_name
			out.surface_set_material(out.get_surface_count() - 1, pair[1] if pair[1] else fm)
	_barefoot_cache[src] = out
	return out

## The base models are flat-shaded low poly. Averaging normals across shared positions (with a
## crease limit so feet and fingers keep their edges) makes bodies read as rounded, defined shapes.
static var _smooth_cache := {}
static func _smoothed(src: Mesh) -> Mesh:
	if src == null or not (src is ArrayMesh):
		return src
	if _smooth_cache.has(src):
		return _smooth_cache[src]
	var acc := {}
	var all: Array = []
	for i in src.get_surface_count():
		var arr := src.surface_get_arrays(i)
		all.append(arr)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx = PackedInt32Array(range(v.size()))
		for t in range(0, idx.size() - 2, 3):
			var a := v[idx[t]]
			var b := v[idx[t + 1]]
			var c := v[idx[t + 2]]
			var fn := (b - a).cross(c - a)
			for vi in [idx[t], idx[t + 1], idx[t + 2]]:
				var key := v[vi].snapped(Vector3.ONE * 0.0005)
				acc[key] = (acc.get(key, Vector3.ZERO) as Vector3) + fn
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		var arr: Array = all[i]
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		if n.size() == v.size():
			var nn := PackedVector3Array()
			nn.resize(n.size())
			for k in v.size():
				var sm: Vector3 = acc.get(v[k].snapped(Vector3.ONE * 0.0005), n[k])
				sm = sm.normalized() if sm.length() > 1e-9 else n[k]
				if sm.dot(n[k]) < 0.0:
					sm = -sm
				nn[k] = sm if sm.dot(n[k]) > 0.35 else n[k]
			arr[Mesh.ARRAY_NORMAL] = nn
			arr[Mesh.ARRAY_TANGENT] = null
		var fmt: int = src.surface_get_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(src.surface_get_primitive_type(i), arr, [], {}, fmt)
		out.surface_set_material(i, src.surface_get_material(i))
		out.surface_set_name(i, src.surface_get_name(i))
	_smooth_cache[src] = out
	return out

func _recolor() -> void:
	var gi := gi_color
	var pants := gi if not casual else Color(0.2, 0.25, 0.4).lerp(gi.darkened(0.5), 0.3)
	for mi in skinned.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name.begins_with("NurbsPath") or m.name == "Rogue_001":
			m.visible = false  # rogue's dagger strap and hood
			continue
		if m.mesh:
			m.mesh = _smoothed(m.mesh)
		if not casual and m.mesh:
			m.mesh = _barefoot(m.mesh)
		# world scale of this mesh relative to the rig, so the outline stays ~1 cm thick
		var chain := m.transform
		var p := m.get_parent()
		while p and p != self:
			if p is Node3D:
				chain = (p as Node3D).transform * chain
			p = p.get_parent()
		var wscale := maxf(chain.basis.get_scale().x, 1e-4)
		var outline := StandardMaterial3D.new()
		outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outline.albedo_color = Color(0.09, 0.07, 0.06)
		outline.cull_mode = BaseMaterial3D.CULL_FRONT
		outline.grow = true
		outline.grow_amount = 0.012 / wscale
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			var nm := src.resource_name if src else ""
			var col: Color
			match nm:
				"Shirt", "UnderShirt", "White", "Material.006":
					col = gi
				"Detail":
					col = gi.darkened(0.15)
				"Pants", "Legs":
					col = pants
				"Skin", "Socks", "Boots", "Feet":
					col = skin_color
				"Hair":
					col = hair_color
				"Eyes", "Eye", "Pupil":
					col = Color(0.08, 0.06, 0.05) if nm != "Eye" else Color(0.95, 0.95, 0.93)
				_:
					col = gi
			var mat := (_mat(col, 0.8) as StandardMaterial3D).duplicate() as StandardMaterial3D
			mat.next_pass = outline
			m.set_surface_override_material(i, mat)

# ------------------------------------------------------------ sculpted fighter model
func _attach_fighter() -> void:
	_pieces.clear()
	var base: MeshInstance3D = null
	for mi in skinned.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).skin != null and base == null:
			base = mi
		else:
			(mi as Node).queue_free()
	if base == null:
		return
	_meshy = _wants_meshy()
	if _meshy:
		var nogi := str(current_look().get("kit", "gi")) != "gi"
		_meshy_path = str((MESHY_NOGI if nogi else MESHY)[body])
		if head_id == "":
			var pool: Array = HEADS_F if body == "female" else HEADS_M
			head_id = pool[absi(hash(gi_color.to_html() + skin_color.to_html() + hair_color.to_html())) % pool.size()]
		var ms: Node3D = (load(_meshy_path) as PackedScene).instantiate()
		var bmi := ms.get_node("Body") as MeshInstance3D
		bmi.owner = null
		ms.remove_child(bmi)
		base.get_parent().add_child(bmi)
		bmi.skeleton = bmi.get_path_to(base.get_node(base.skeleton))
		_pieces["Body"] = bmi
		ms.free()
		# Sculpted hair / head gear are built for the cartoon cranium and sit wrong on these realistic
		# heads, so Meshy bodies show neither (head gear stats still apply).
		base.queue_free()
		_attach_head(bmi)
		_apply_materials()
		return
	var parts: Node3D = (load(FIGHTERS[body]) as PackedScene).instantiate()
	var want := _wanted_pieces()
	for c in parts.get_children():
		var mi := c as MeshInstance3D
		if not want.has(str(mi.name)):
			continue
		mi.owner = null
		parts.remove_child(mi)
		base.get_parent().add_child(mi)
		mi.skin = base.skin
		mi.skeleton = mi.get_path_to(base.get_node(base.skeleton))
		_pieces[str(mi.name)] = mi
	parts.free()
	base.queue_free()
	_apply_materials()

## Modular heads: a face + hair mesh fitted to this body's neck (assets/models/heads/<body>__<id>.scn),
## skinned to the same skeleton. The face sets the skin tone, so the body is tinted to match it.
var head_id := ""
var _head_mi: MeshInstance3D

func _attach_head(bmi: MeshInstance3D) -> void:
	_head_mi = null
	if head_id == "":
		return
	var bname := _meshy_path.get_file().get_basename()
	var path := "res://assets/models/heads/%s__%s.scn" % [bname, head_id]
	if not ResourceLoader.exists(path):
		return
	var hs: Node3D = (load(path) as PackedScene).instantiate()
	var hmi := hs.get_node("Head") as MeshInstance3D
	hmi.owner = null
	hs.remove_child(hmi)
	bmi.get_parent().add_child(hmi)
	hmi.skeleton = hmi.get_path_to(bmi.get_node(bmi.skeleton))
	hs.free()
	_head_mi = hmi
	_pieces["Head"] = hmi
	skin_color = hmi.get_meta("skin_ref", skin_color)

func _wants_meshy() -> bool:
	# every look (gi, no-gi, villagers' casual clothes) uses the textured hero bodies now
	return use_meshy and ResourceLoader.exists(MESHY.get(body, "")) and ResourceLoader.exists(MESHY_NOGI.get(body, ""))

## The look actually worn: gear look if set, else derived from the setup colours.
func current_look() -> Dictionary:
	if not look.is_empty():
		return look
	if casual:
		return {"kit": "casual", "rash": {"color": gi_color},
			"pants": {"color": Color(0.2, 0.25, 0.4).lerp(gi_color.darkened(0.5), 0.3)}}
	var trim := gi_color.darkened(0.12) if gi_color.v > 0.5 else gi_color.lightened(0.15)
	if lapel_override.a > 0.0:
		trim = lapel_override
	var lk := {"kit": "gi", "jacket": {"color": gi_color, "trim": trim}, "pants": {"color": gi_color}}
	if rash_color.a > 0.0:
		lk["rash"] = {"color": rash_color}
	return lk

func _hair_piece() -> String:
	var st := hair_style
	if body == "female" and st in [0, 1, 4]:
		st = 6   # ponytail
	var n: String = HAIR_NAMES[clampi(st, 0, HAIR_NAMES.size() - 1)]
	return "" if n == "" else "Hair_" + n

func _wanted_pieces() -> Dictionary:
	var lk := current_look()
	var w := {"Body": {"color": skin_color}, "Face": {"color": Color(0.08, 0.06, 0.05)}}
	var hp := _hair_piece()
	if hp != "":
		w[hp] = {"color": hair_color}
	match str(lk.get("kit", "gi")):
		"gi":
			var j: Dictionary = lk.get("jacket", {"color": gi_color})
			w["Jacket"] = j
			w["JacketTrim"] = {"color": j.get("trim", (j.get("color", gi_color) as Color).darkened(0.12))}
			w["Pants"] = lk.get("pants", {"color": j.get("color", gi_color)})
			w["Belt"] = {"color": belt_color}
			if lk.has("rash"):
				w["Rash"] = lk.rash
		"nogi":
			w["Rash"] = lk.get("rash", {"color": Color(0.1, 0.1, 0.12)})
			w["Spats"] = lk.get("spats", {"color": Color(0.1, 0.1, 0.12)})
			if lk.has("knees"):
				w["KneeSleeves"] = lk.knees
		"casual":
			w["Rash"] = lk.get("rash", {"color": gi_color})
			w["Pants"] = lk.get("pants", {"color": Color(0.2, 0.25, 0.4)})
	if lk.has("tape") and not casual:
		w["Tape"] = lk.tape
	if lk.has("head"):
		w[str(lk.get("head_piece", "Headband"))] = lk.head
	return w

## (Re)builds every piece's material: toon + pattern, ink outline, team x-ray in rolls.
func _apply_materials() -> void:
	if _pieces.is_empty():
		return
	var want := _wanted_pieces()
	var any: MeshInstance3D = _pieces.values()[0]
	var chain := any.transform
	var p := any.get_parent()
	while p and p != self:
		if p is Node3D:
			chain = (p as Node3D).transform * chain
		p = p.get_parent()
	var wscale := maxf(chain.basis.get_scale().x, 1e-4)
	var grow := (0.013 if _ref > 0 else 0.009) / wscale
	if _meshy:
		var bm: MeshInstance3D = _pieces.Body
		var jk: Dictionary = want.get("Jacket", {"color": gi_color})
		var pt: Dictionary = want.get("Pants", jk)
		if not want.has("Jacket"):   # no-gi: rashguard on top, spats (or casual pants) below
			jk = want.get("Rash", {"color": gi_color})
			pt = want.get("Spats", want.get("Pants", jk))
		bm.material_override = FighterLook.textured(bm, jk, pt, belt_color, skin_color, grow * 0.8, _ref, _team)
		if _head_mi:
			var hm := FighterLook.plain_textured(load(str(_head_mi.get_meta("albedo"))), grow * 0.35, _ref, _team)
			hm.set_shader_parameter("neck_skin", Vector3(skin_color.r, skin_color.g, skin_color.b))
			hm.set_shader_parameter("neck_mix", 1.0)
			_head_mi.material_override = hm
		_collect_lod()
		return
	for n in _pieces:
		var mi: MeshInstance3D = _pieces[n]
		var lk: Dictionary = want.get(n, {"color": Color.WHITE})
		var g := 0.0 if n == "Face" else grow
		mi.material_override = FighterLook.material(lk, g, _ref, _team)
	_collect_lod()

## Gi pieces the base model lacks (long sleeves, full-length pants, lapels, jacket skirt, belt).
## Each piece follows two skeleton bones every frame, so it works for both clips and grappling poses.
var _gi_parts: Array = []   # [{node, a, b, t0, t1}] limb tubes
var _torso_parts: Node3D    # lapels + skirt + belt, follows a torso frame

func _tube(r0: float, r1: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r0
	c.bottom_radius = r1
	c.height = 1.0
	c.radial_segments = 20
	c.rings = 2
	mi.mesh = c
	mi.material_override = _cmat(col, 0.85)
	add_child(mi)
	return mi

func _limb(a: String, b: String, t0: float, t1: float, r0: float, r1: float, col: Color) -> void:
	if _bones.get(a, -1) < 0 or _bones.get(b, -1) < 0:
		return
	_gi_parts.append({"node": _tube(r1, r0, col), "a": _bones[a], "b": _bones[b], "t0": t0, "t1": t1})

## A rounded cap where two gi tubes meet (elbow, knee).
func _joint(bone: String, r: float, col: Color) -> void:
	if _bones.get(bone, -1) < 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _sph(r, -1.0, 18)
	mi.material_override = _cmat(col, 0.85)
	add_child(mi)
	_gi_parts.append({"node": mi, "a": _bones[bone], "b": -1, "t0": 0.0, "t1": 0.0})

func _build_skinned_belt() -> void:
	var gi := gi_color
	var cuff := gi.darkened(0.08)
	for sd in ["L", "R"]:
		# sleeves: loose over the upper arm, ending just above the wrist
		_limb("UpperArm." + sd, "LowerArm." + sd, 0.14, 1.12, 0.106, 0.1, gi)
		_limb("LowerArm." + sd, "Hand." + sd, -0.08, 0.84, 0.096, 0.078, cuff)
		# pants: from the shorts' hem down to just above the ankle
		_limb("UpperLeg." + sd, "LowerLeg." + sd, 0.3, 1.06, 0.13, 0.104, gi)
		_limb("LowerLeg." + sd, "Foot." + sd, -0.04, 0.9, 0.102, 0.088, gi)
		_joint("LowerArm." + sd, 0.1, gi)
		_joint("LowerLeg." + sd, 0.12, gi)
	_torso_parts = Node3D.new()
	_torso_parts.name = "GiTorso"
	add_child(_torso_parts)
	var lapel := gi.darkened(0.12) if gi.v > 0.5 else gi.lightened(0.1)
	if lapel_override.a > 0.0:
		lapel = lapel_override
	# rashguard peeking out of the collar
	if rash_color.a > 0.0:
		var rg := MeshInstance3D.new()
		rg.mesh = BoxMesh.new()
		rg.material_override = _cmat(rash_color)
		rg.position = Vector3(0, 0.66, -0.128)
		rg.scale = Vector3(0.15, 0.26, 0.02)
		_torso_parts.add_child(rg)
	# jacket skirt below the belt
	var skirt := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 1.0
	sc.bottom_radius = 1.1
	sc.height = 0.24
	sc.radial_segments = 28
	sc.rings = 2
	skirt.mesh = sc
	skirt.material_override = _cmat(gi)
	skirt.scale = Vector3(0.232, 1, 0.19)
	skirt.position = Vector3(0, -0.12, 0)
	_torso_parts.add_child(skirt)
	# lapels: two collar strips crossing into a V, left over right
	for sd in [-1, 1]:
		var lp := MeshInstance3D.new()
		lp.mesh = BoxMesh.new()
		lp.material_override = _cmat(lapel)
		var top := Vector3(0.085 * sd, 0.78, -0.135)
		var bot := Vector3(-0.06 * sd, 0.04, -0.205)
		var d := top - bot
		lp.position = (top + bot) * 0.5
		lp.basis = Basis(Vector3(1, 0, 0).slide(d.normalized()).normalized(), d.normalized(), Vector3(1, 0, 0).slide(d.normalized()).normalized().cross(d.normalized()))
		lp.scale = Vector3(0.062, d.length(), 0.03)
		lp.position.z -= 0.003 * sd
		_torso_parts.add_child(lp)
	# belt: band + knot + tails
	_belt_node = Node3D.new()
	_belt_node.name = "SkinnedBelt"
	_torso_parts.add_child(_belt_node)
	var band := MeshInstance3D.new()
	band.mesh = _cyl(1.0, 1.0, 0.075, 32)
	band.material_override = _cmat(belt_color, 0.7)
	band.scale = Vector3(0.235, 1, 0.195)
	_belt_node.add_child(band)
	var knot := MeshInstance3D.new()
	knot.mesh = _sph(0.045)
	knot.material_override = _cmat(belt_color, 0.7)
	knot.position = Vector3(0, 0, -0.2)
	knot.scale = Vector3(1.4, 1, 0.8)
	_belt_node.add_child(knot)
	for sd in [-1, 1]:
		var tail := MeshInstance3D.new()
		tail.mesh = BoxMesh.new()
		tail.material_override = _cmat(belt_color, 0.7)
		tail.position = Vector3(0.05 * sd, -0.11, -0.205)
		tail.rotation.z = 0.25 * sd
		tail.scale = Vector3(0.06, 0.2, 0.02)
		_belt_node.add_child(tail)

var _hair_node: Node3D

## Female fighters: tied-back hair (bun tie + ponytail) that follows the head.
func _build_ponytail() -> void:
	_hair_node = Node3D.new()
	_hair_node.name = "Ponytail"
	add_child(_hair_node)
	var cap := MeshInstance3D.new()
	cap.mesh = _sph(1.0, -1.0, 16)
	cap.material_override = _cmat(hair_color, 0.6)
	cap.scale = Vector3(0.152, 0.1, 0.155)
	cap.position = Vector3(0, 0.215, 0.05)
	_hair_node.add_child(cap)
	var tie := MeshInstance3D.new()
	tie.mesh = _sph(0.06)
	tie.material_override = _cmat(hair_color.darkened(0.1), 0.6)
	tie.position = Vector3(0, 0.17, 0.16)
	_hair_node.add_child(tie)
	var tail := MeshInstance3D.new()
	tail.mesh = _cap(0.05, 0.34)
	tail.material_override = _cmat(hair_color, 0.6)
	tail.position = Vector3(0, 0.02, 0.2)
	tail.rotation.x = 0.28
	_hair_node.add_child(tail)

func _update_hair() -> void:
	if not _hair_node or _bones["Head"] < 0 or _bones["Neck"] < 0:
		return
	var sx := skel.global_transform
	var hd := sx * skel.get_bone_global_pose(_bones["Head"])
	var nk := (sx * skel.get_bone_global_pose(_bones["Neck"])).origin
	var right := hd.basis.x
	if _bones["UpperArm.L"] >= 0 and _bones["UpperArm.R"] >= 0:
		right = (sx * skel.get_bone_global_pose(_bones["UpperArm.R"])).origin - (sx * skel.get_bone_global_pose(_bones["UpperArm.L"])).origin
	var b := _frame(right, hd.origin - nk)
	var gs := global_transform.basis.get_scale()
	_hair_node.global_transform = Transform3D(b.scaled(gs), hd.origin)

func _update_gi_parts() -> void:
	var sx := skel.global_transform
	for g in _gi_parts:
		if not is_instance_valid(g.node):
			continue
		var pa: Vector3 = (sx * skel.get_bone_global_pose(g.a)).origin
		if int(g.b) < 0:
			(g.node as Node3D).global_position = pa
			(g.node as Node3D).global_basis = Basis.from_scale(global_transform.basis.get_scale())
			continue
		var pb: Vector3 = (sx * skel.get_bone_global_pose(g.b)).origin
		var p0: Vector3 = pa.lerp(pb, g.t0)
		var p1: Vector3 = pa.lerp(pb, g.t1)
		var d := p1 - p0
		var ln := d.length()
		if ln < 1e-4:
			continue
		var y := d / ln
		var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var x := ref.cross(y).normalized()
		(g.node as Node3D).global_transform = Transform3D(Basis(x, y * ln, y.cross(x)), (p0 + p1) * 0.5)
	if _torso_parts and _bones["Abdomen"] >= 0 and _bones["Neck"] >= 0:
		var ab := (sx * skel.get_bone_global_pose(_bones["Abdomen"])).origin
		var nk := (sx * skel.get_bone_global_pose(_bones["Neck"])).origin
		var right := Vector3.RIGHT
		if _bones["UpperArm.L"] >= 0 and _bones["UpperArm.R"] >= 0:
			right = (sx * skel.get_bone_global_pose(_bones["UpperArm.R"])).origin - (sx * skel.get_bone_global_pose(_bones["UpperArm.L"])).origin
		var up := nk - ab
		var b := _frame(right, up)
		var gs := global_transform.basis.get_scale()
		_torso_parts.global_transform = Transform3D(b.scaled(gs), ab + b.y * 0.05 * gs.y)

func _play_locomotion(speed01: float, airborne: bool) -> void:
	if not anim:
		return
	_anim_mode = true
	var want := "Idle"
	# hysteresis so the clip doesn't flicker when speed hovers at a threshold
	var cur := anim.current_animation
	var run_at := 0.55 if cur == _anim_names.get("Run", "") else 0.66
	var walk_at := 0.03 if cur == _anim_names.get("Walk", "") or cur == _anim_names.get("Run", "") else 0.08
	if airborne and _anim_names.has("Jump"):
		want = "Jump"
	elif speed01 > run_at and _anim_names.has("Run"):
		want = "Run"
	elif speed01 > walk_at and _anim_names.has("Walk"):
		want = "Walk"
	var full: String = _anim_names.get(want, "")
	if full == "":
		return
	if anim.current_animation != full or not anim.is_playing():
		anim.play(full, 0.3)
	# keep cadence continuous across the walk -> run switch (no foot-skate jump)
	if want == "Walk":
		anim.speed_scale = lerpf(0.75, 1.25, clampf(speed01 / 0.62, 0.0, 1.0))
	elif want == "Run":
		anim.speed_scale = lerpf(0.85, 1.1, clampf((speed01 - 0.62) / 0.38, 0.0, 1.0))
	else:
		anim.speed_scale = 1.0

func _enter_pose_mode() -> void:
	if skel and _anim_mode:
		_anim_mode = false
		if anim:
			anim.stop()

# ------------------------------------------------------------ fighter readability
## Esports-style readability for rolls: a thicker team-tinted outline and an x-ray silhouette in the
## team colour wherever the other fighter (or anything) hides this one. `ref` must differ per fighter.
func set_fighter(team: Color, ref: int) -> void:
	lod_enabled = false
	_lod = 0
	if not _pieces.is_empty():
		_team = team
		_ref = ref
		_apply_materials()
		_apply_lod()
		return
	var themed := {}
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if hips.is_ancestor_of(mi) or not mi.visible:
			continue
		if mi.material_override:
			mi.material_override = _themed(mi.material_override, team, ref, themed)
		elif mi.mesh:
			for i in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(i)
				if m:
					mi.set_surface_override_material(i, _themed(m, team, ref, themed))

static func _themed(m: Material, team: Color, ref: int, cache: Dictionary) -> Material:
	if not (m is StandardMaterial3D):
		return m
	if cache.has(m):
		return cache[m]
	var t := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
	var ol := t.next_pass as StandardMaterial3D
	if ol:
		ol = ol.duplicate() as StandardMaterial3D
		ol.albedo_color = Color(0.07, 0.05, 0.05).lerp(team.darkened(0.25), 0.45)
		ol.grow_amount *= 1.6
		t.next_pass = ol
	t.rim = 0.35
	t.rim_tint = 0.3
	t.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY
	t.stencil_reference = ref
	t.stencil_color = Color(team, 0.42)
	cache[m] = t
	return t

# ------------------------------------------------------------ level of detail
## 0 full (outlines) · 1 mid (no outlines) · 2 far (no gi details) · 3 not drawn
const LOD_DIST := [18.0, 40.0, 85.0]
var lod_enabled := true
var force_hidden := false   # e.g. the world body while its fight rig is on screen
var _lod := 0
var _lod_t := 0.0
var _lod_surfaces: Array = []   # [MeshInstance3D, surface index or -1, full material, plain material]
static var _plain_cache := {}

static func _plain_of(m: Material) -> Material:
	if m == null or m.next_pass == null:
		return m
	var id := m.get_instance_id()
	if not _plain_cache.has(id):
		var p := m.duplicate() as Material
		p.next_pass = null
		_plain_cache[id] = p
	return _plain_cache[id]

func _collect_lod() -> void:
	_lod_surfaces.clear()
	_lod = 0
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if hips.is_ancestor_of(mi):
			continue
		if mi.material_override:
			_lod_surfaces.append([mi, -1, mi.material_override, _plain_of(mi.material_override)])
		elif mi.mesh:
			for i in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(i)
				if m:
					_lod_surfaces.append([mi, i, m, _plain_of(m)])

func _update_lod(delta: float) -> void:
	_lod_t -= delta
	if _lod_t > 0.0:
		return
	_lod_t = 0.3 + randf() * 0.1
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var k: float = [0.6, 1.0, 1.4][Game.graphics_level()]
	var d := cam.global_position.distance_to(global_position)
	var lod := 3
	for i in LOD_DIST.size():
		if d < float(LOD_DIST[i]) * k:
			lod = i
			break
	if lod != _lod:
		_lod = lod
		_apply_lod()

func _apply_lod() -> void:
	visible = _lod < 3 and not force_hidden
	if smoother:
		smoother.active = _lod < 2
		if _lod >= 2:
			smoother.reset()
	for e in _lod_surfaces:
		if not is_instance_valid(e[0]):
			continue
		var mi := e[0] as MeshInstance3D
		var m: Material = e[2] if _lod == 0 else e[3]
		if int(e[1]) < 0:
			mi.material_override = m
		else:
			mi.set_surface_override_material(int(e[1]), m)
	for g in _gi_parts:
		if is_instance_valid(g.node):
			(g.node as Node3D).visible = _lod < 2
	if _torso_parts:
		for c in _torso_parts.get_children():
			if c != _belt_node:
				(c as Node3D).visible = _lod < 2

## WoW-style heroic proportions on the realistic bodies: a touch more head, bigger hands and feet,
## heavier shoulders, so fighters read clearly from the camera distance the game is played at.
## Applied as bone scale after animation / retargeting, so every clip and grappling pose keeps it.
static var HERO_SCALE := {"Head": 1.03, "Palm.L": 1.22, "Palm.R": 1.22, "Foot.L": 1.12, "Foot.R": 1.12,
	"Shoulder.L": 1.06, "Shoulder.R": 1.06}
var _hero_ids := []

func _hero_proportions() -> void:
	if not _meshy or skel == null:
		return
	if _hero_ids.is_empty():
		for n in HERO_SCALE:
			var b := skel.find_bone(n)
			if b >= 0:
				_hero_ids.append([b, Vector3.ONE * float(HERO_SCALE[n])])
	for e in _hero_ids:
		skel.set_bone_pose_scale(e[0], e[1])

func _process(_delta: float) -> void:
	if not skel:
		return
	if lod_enabled:
		_update_lod(_delta)
		if _lod >= 2:
			if not _anim_mode:
				_retarget()
			return
	var layered := not _anim_mode and not layer.is_empty()
	if layered:
		_layer_apply(1.0)
	if not _anim_mode:
		_retarget()
	if not casual:
		_update_gi_parts()
	_update_hair()
	_update_crest()
	_hero_proportions()
	if layered:
		_layer_apply(-1.0)

## Additive "live" motion on top of the tweened pose (breathing, hand fighting, wind-ups, braces).
## Keys: joint names / "hip_rot" -> Vector3 rotation offsets, "hip_h" -> float. Applied only while
## the skeleton is driven, then removed, so tweens keep owning the base pose.
var layer := {}

func _layer_apply(sign_: float) -> void:
	for k in layer:
		match k:
			"hip_h":
				hips.position.y += float(layer[k]) * sign_
			"hip_rot":
				hips.rotation += (layer[k] as Vector3) * sign_
			_:
				if joints.has(k):
					(joints[k] as Node3D).rotation += (layer[k] as Vector3) * sign_

## Drive the skinned skeleton so its segments point the same way as this rig's (hidden) joints.
func _retarget() -> void:
	skel.reset_bone_poses()
	var sx := skel.global_transform
	var J := func(n: String, off := Vector3.ZERO) -> Vector3: return (joints[n] as Node3D).to_global(off)
	var hips_w := hips.global_position
	var neck_w: Vector3 = J.call("neck")
	# 1) hips: full frame (up + left/right), and position
	var hb: int = _bones["Hips"]
	var cur := sx * skel.get_bone_global_pose(hb)
	var up_c := ((sx * skel.get_bone_global_pose(_bones["Neck"])).origin - cur.origin).normalized()
	var rt_c := ((sx * skel.get_bone_global_pose(_bones["UpperLeg.R"])).origin - (sx * skel.get_bone_global_pose(_bones["UpperLeg.L"])).origin).normalized()
	var up_t := (neck_w - hips_w).normalized()
	var rt_t := ((J.call("r_hip") as Vector3) - (J.call("l_hip") as Vector3)).normalized()
	var bc := _frame(rt_c, up_c)
	var bt := _frame(rt_t, up_t)
	var new_w := Transform3D((bt * bc.inverse()) * cur.basis, hips_w + (cur.origin - (sx * skel.get_bone_global_pose(hb)).origin))
	new_w.origin = hips_w - up_t * 0.02
	_set_global(hb, new_w)
	# 2) chains: align each bone so its child joint points toward the rig's matching joint
	_aim("Abdomen", "Neck", J.call("spine"), neck_w)
	_aim("Neck", "Head", neck_w, J.call("neck", Vector3(0, 0.25, 0)))
	for s in ["L", "R"]:
		var k := "l" if s == "L" else "r"
		_aim("UpperArm." + s, "LowerArm." + s, J.call(k + "_sh"), J.call(k + "_el"))
		_aim("LowerArm." + s, "Hand." + s, J.call(k + "_el"), J.call(k + "_el", Vector3(0, -0.27, 0)))
		_aim("UpperLeg." + s, "LowerLeg." + s, J.call(k + "_hip"), J.call(k + "_kn"))
		var lb: int = _bones["LowerLeg." + s]
		var foot_t: Vector3 = J.call(k + "_kn", Vector3(0, -0.43, 0))
		var knee_t: Vector3 = J.call(k + "_kn")
		var fb: int = _bones["Foot." + s]
		if fb >= 0 and lb >= 0:
			# the lower leg points at where the foot should be
			var lcur := sx * skel.get_bone_global_pose(lb)
			var rel: Transform3D = _foot_rel.get(s, Transform3D())
			var fcur: Transform3D = sx * (skel.get_bone_global_pose(lb) * rel)
			_rotate_toward(lb, lcur, fcur.origin - lcur.origin, foot_t - knee_t)
			# then glue the (IK-driven) foot bone to the end of the lower leg
			var foot_g: Transform3D = skel.get_bone_global_pose(lb) * rel
			var par := skel.get_bone_parent(fb)
			var local := (skel.get_bone_global_pose(par).affine_inverse() if par >= 0 else Transform3D()) * foot_g
			skel.set_bone_pose_position(fb, local.origin)
			skel.set_bone_pose_rotation(fb, local.basis.get_rotation_quaternion())

static func _frame(right: Vector3, up: Vector3) -> Basis:
	var x := right.normalized()
	var y := (up - x * up.dot(x)).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _aim(bone: String, child: String, from_w: Vector3, to_w: Vector3) -> void:
	var b: int = _bones.get(bone, -1)
	var c: int = _bones.get(child, -1)
	if b < 0 or c < 0:
		return
	var sx := skel.global_transform
	var cur := sx * skel.get_bone_global_pose(b)
	var child_w := (sx * skel.get_bone_global_pose(c)).origin
	_rotate_toward(b, cur, child_w - cur.origin, to_w - from_w)

func _rotate_toward(b: int, cur_w: Transform3D, dir_c: Vector3, dir_t: Vector3) -> void:
	if dir_c.length() < 1e-5 or dir_t.length() < 1e-5:
		return
	var q := Quaternion(dir_c.normalized(), dir_t.normalized())
	var new_w := Transform3D(Basis(q) * cur_w.basis, cur_w.origin)
	_set_global(b, new_w)

func _set_global(b: int, world: Transform3D) -> void:
	var g := skel.global_transform.affine_inverse() * world
	var par := skel.get_bone_parent(b)
	var local := (skel.get_bone_global_pose(par).affine_inverse() if par >= 0 else Transform3D()) * g
	skel.set_bone_pose_rotation(b, local.basis.get_rotation_quaternion())
	if b == _bones["Hips"]:
		skel.set_bone_pose_position(b, local.origin)
