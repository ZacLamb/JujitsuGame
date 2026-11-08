class_name StyleSelect
extends Control
## Character creation, WoW style: Origin (Tatame's "race") on the left, a live 3D preview in the
## middle, Class (fighting style) with its three specs and their roles on the right, and name /
## body / skin tone / gi colour along the bottom.

signal chosen(style_id: String, player_name: String, gi: int)

const ROLE_INFO := {
	"anchor": {"name": "Anchor", "wow": "Tank", "col": Color(0.4, 0.65, 1.0), "glyph": "shield"},
	"finisher": {"name": "Finisher", "wow": "Burst damage", "col": Color(1.0, 0.4, 0.35), "glyph": "bolt"},
	"scrambler": {"name": "Scrambler", "wow": "Mobile damage", "col": Color(1.0, 0.75, 0.3), "glyph": "loop"},
	"grinder": {"name": "Grinder", "wow": "Control", "col": Color(0.55, 0.9, 0.45), "glyph": "chevron"},
}
const SKINS := [0.0, 0.18, 0.35, 0.55, 0.75, 0.95]

var _style := "guard"
var _origin := "gringo"
var _gi := 0
var _body := "male"
var _skin := 0.35
var _name_edit: LineEdit
var _style_btns := {}
var _origin_btns := {}
var _gi_btns: Array = []
var _skin_btns: Array = []
var _body_btns := {}
var _origin_info: VBoxContainer
var _class_info: VBoxContainer
var _vp: SubViewport
var _rig: BodyRig
var _pivot: Node3D
var _drag := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Wow.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.03, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var title := Wow.title("CREATE YOUR FIGHTER", 34, Wow.GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = 14
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var sub := Wow.label("Origin is where you're from. Class is how you fight. At level 10 you pick a Specialization, and talents shape the rest.", 14, Wow.PALE, false, HORIZONTAL_ALIGNMENT_CENTER)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub.offset_left = -480
	sub.offset_right = 480
	sub.offset_top = 56
	add_child(sub)
	# --- left: origin
	var left := _panel(Vector2(16, 86), Vector2(300, 0), true)
	left.add_child(Wow.title("ORIGIN", 16, Wow.GOLD))
	for id in Origins.ORDER:
		var o: Dictionary = Origins.ORIGINS[id]
		var b := _choice_btn("%s   ·   %s" % [o.name, o.tag])
		b.pressed.connect(func(): _pick_origin(id))
		left.add_child(b)
		_origin_btns[id] = b
	_origin_info = VBoxContainer.new()
	_origin_info.add_theme_constant_override("separation", 3)
	left.add_child(_origin_info)
	# --- right: class
	var right := _panel(Vector2(-16, 86), Vector2(340, 0), false)
	right.add_child(Wow.title("CLASS", 16, Wow.GOLD))
	for id in Rpg.STYLE_ORDER:
		var st: Dictionary = Rpg.STYLES[id]
		var b := _choice_btn("%s   ·   %s" % [st.name, st.tag])
		b.pressed.connect(func(): _pick_style(id))
		right.add_child(b)
		var ct := IconArt.tex("class_" + str(id))
		if ct != null:
			b.icon = ct
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 24)
		_style_btns[id] = b
	_class_info = VBoxContainer.new()
	_class_info.add_theme_constant_override("separation", 3)
	right.add_child(_class_info)
	# --- centre: live preview (drag to turn)
	var vc := SubViewportContainer.new()
	vc.stretch = true
	vc.set_anchors_preset(Control.PRESET_CENTER)
	vc.offset_left = -170
	vc.offset_right = 170
	vc.offset_top = -250
	vc.offset_bottom = 180
	vc.mouse_filter = Control.MOUSE_FILTER_STOP
	vc.gui_input.connect(_preview_input)
	add_child(vc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.size = Vector2i(340, 430)
	vc.add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.8
	env.environment = e
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.6, 0)
	_vp.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 4.3)
	cam.fov = 38
	_vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.92, 0))
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	var disc := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.7
	cy.bottom_radius = 0.7
	cy.height = 0.04
	disc.mesh = cy
	disc.material_override = BodyRig._mat(Color(0.13, 0.38, 0.26))
	_pivot.add_child(disc)
	# --- bottom: name / body / skin / gi / begin
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", Wow.sb(Color(0.04, 0.035, 0.03, 0.95), Wow.FRAME, 4, 12, 2))
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -14
	add_child(bottom)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 8)
	bottom.add_child(bv)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 10)
	r1.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_child(r1)
	r1.add_child(Wow.label("Name", 15, Wow.PALE))
	_name_edit = LineEdit.new()
	_name_edit.text = Game.player_name
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(180, 32)
	r1.add_child(_name_edit)
	r1.add_child(_spacer(12))
	r1.add_child(Wow.label("Body", 15, Wow.PALE))
	for bt in ["male", "female"]:
		var b := Wow.button(bt.capitalize(), Vector2(80, 30))
		b.pressed.connect(func(): _pick_body(bt))
		r1.add_child(b)
		_body_btns[bt] = b
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 8)
	r2.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_child(r2)
	r2.add_child(Wow.label("Skin", 15, Wow.PALE))
	for i in SKINS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		b.focus_mode = Control.FOCUS_NONE
		var t: float = SKINS[i]
		b.pressed.connect(func(): _pick_skin(t))
		r2.add_child(b)
		_skin_btns.append(b)
	r2.add_child(_spacer(16))
	r2.add_child(Wow.label("Gi", 15, Wow.PALE))
	for i in Rpg.GI_COLORS.size():
		var b := Wow.button(Rpg.GI_NAMES[i], Vector2(74, 30))
		var gi := i
		b.pressed.connect(func(): _pick_gi(gi))
		r2.add_child(b)
		_gi_btns.append(b)
	r2.add_child(_spacer(16))
	var go := Wow.button("Begin training", Vector2(190, 38))
	go.add_theme_font_size_override("font_size", 18)
	go.add_theme_color_override("font_color", Wow.GOLD)
	go.pressed.connect(_begin)
	r2.add_child(go)
	_pick_origin(_origin)
	_pick_style(_style)
	_pick_body(_body)
	_pick_skin(_skin)
	_pick_gi(_gi)

func _panel(pos: Vector2, sz: Vector2, on_left: bool) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Wow.sb(Color(0.04, 0.035, 0.03, 0.9), Wow.FRAME, 4, 12, 2))
	if on_left:
		p.position = pos
	else:
		p.anchor_left = 1.0
		p.anchor_right = 1.0
		p.offset_left = pos.x - sz.x
		p.offset_right = pos.x
		p.offset_top = pos.y
	p.custom_minimum_size = sz
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size = Vector2(sz.x - 24, 0)
	p.add_child(v)
	return v

func _choice_btn(text: String) -> Button:
	var b := Wow.button(text, Vector2(0, 30))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	return b

func _spacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c

func _mark(btns: Dictionary, on: String) -> void:
	for k in btns:
		var b: Button = btns[k]
		var sel: bool = k == on
		b.add_theme_color_override("font_color", Wow.GOLD if sel else Wow.WHITE)
		b.add_theme_stylebox_override("normal", Wow.sb(Color(0.25, 0.18, 0.05, 0.95) if sel else Color(0.08, 0.07, 0.06, 0.95), Wow.GOLD if sel else Color(Wow.FRAME, 0.6), 3, 6, 2 if sel else 1))

func _line(v: VBoxContainer, text: String, col: Color, size := 13) -> void:
	var l := Wow.label(text, size, col, true)
	l.custom_minimum_size = Vector2(v.custom_minimum_size.x if v.custom_minimum_size.x > 0 else 270, 0)
	v.add_child(l)

func _pick_origin(id: String) -> void:
	_origin = id
	_mark(_origin_btns, id)
	for c in _origin_info.get_children():
		c.queue_free()
	var o: Dictionary = Origins.ORIGINS[id]
	_origin_info.custom_minimum_size = Vector2(276, 0)
	_origin_info.add_child(Wow.title(str(o.name), 20, Wow.WHITE))
	_line(_origin_info, str(o.desc), Wow.PALE)
	var parts: Array = []
	for k in o.attrs:
		parts.append("+%d %s" % [int(o.attrs[k]), Rpg.ATTRS[k].name])
	_line(_origin_info, ", ".join(parts), Color(0.55, 0.85, 1.0))
	_line(_origin_info, str(o.passive), Wow.GREEN)
	_line(_origin_info, "Racial [G]: %s. %s" % [str(o.racial.name), str(o.racial.text)], Wow.GOLD)

func _pick_style(id: String) -> void:
	_style = id
	_mark(_style_btns, id)
	for c in _class_info.get_children():
		c.queue_free()
	var st: Dictionary = Rpg.STYLES[id]
	_class_info.custom_minimum_size = Vector2(316, 0)
	_class_info.add_child(Wow.title(str(st.name), 20, Wow.WHITE))
	_line(_class_info, str(st.desc), Wow.PALE)
	var parts: Array = []
	for k in Rpg.ATTR_ORDER:
		if st.attrs.has(k):
			parts.append("+%d %s" % [st.attrs[k], Rpg.ATTRS[k].name])
	_line(_class_info, ", ".join(parts), Color(0.55, 0.85, 1.0))
	_line(_class_info, str(st.passive), Wow.GREEN)
	var sig: Array = []
	for mid in st.signature:
		sig.append(Data.MOVES[mid].name)
	_line(_class_info, "Signature: " + ", ".join(sig), Wow.GOLD)
	_class_info.add_child(Wow.title("SPECIALIZATIONS (level %d)" % Specs.UNLOCK_LEVEL, 13, Wow.GOLD))
	for sp in Specs.list(id):
		var ri: Dictionary = ROLE_INFO.get(str(sp.role), ROLE_INFO.finisher)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(30, 30)
		var col: Color = ri.col
		var gl: String = ri.glyph
		var stx := IconArt.tex("spec_" + str(sp.id))
		ic.draw.connect(func():
			if stx != null:
				ic.draw_rect(Rect2(0, 0, 30, 30), Color(0.42, 0.32, 0.16))
				ic.draw_texture_rect(stx, Rect2(1.5, 1.5, 27, 27), false)
			else:
				ic.draw_circle(Vector2(15, 15), 13, col.darkened(0.55))
				CharSheet.draw_glyph(ic, gl, Vector2(15, 15), 15, col))
		h.add_child(ic)
		var l := Wow.label("%s  ·  %s (%s)" % [str(sp.name), str(ri.name), str(ri.wow)], 13, col)
		h.add_child(l)
		h.tooltip_text = str(sp.desc)
		_class_info.add_child(h)
	if _gi_btns.size() > 0:
		_pick_gi(Rpg.GI_COLORS.find(st.gi) if Rpg.GI_COLORS.has(st.gi) else _gi)

func _pick_body(b: String) -> void:
	_body = b
	_mark(_body_btns, b)
	_preview()

func _pick_skin(t: float) -> void:
	_skin = t
	for i in _skin_btns.size():
		var b: Button = _skin_btns[i]
		var sel: bool = absf(SKINS[i] - t) < 0.01
		b.add_theme_stylebox_override("normal", Wow.sb(UiKit.skin_tone(SKINS[i]), Wow.GOLD if sel else Color(0, 0, 0, 0.8), 15, 0, 3 if sel else 1))
		b.add_theme_stylebox_override("hover", b.get_theme_stylebox("normal"))
	_preview()

func _pick_gi(i: int) -> void:
	_gi = maxi(i, 0)
	for j in _gi_btns.size():
		var b: Button = _gi_btns[j]
		var sel := j == _gi
		b.add_theme_stylebox_override("normal", Wow.sb(Rpg.GI_COLORS[j].darkened(0.5), Wow.GOLD if sel else Color(Wow.FRAME, 0.6), 3, 6, 2 if sel else 1))
	_preview()

func _preview() -> void:
	if _pivot == null:
		return
	if _rig and is_instance_valid(_rig):
		_rig.queue_free()
	_rig = BodyRig.new()
	_rig.lod_enabled = false
	_rig.bulk = 1.0
	_pivot.add_child(_rig)
	_rig.setup(Rpg.GI_COLORS[_gi], Data.BELTS[0].color, UiKit.skin_tone(_skin), Color(0.2, 0.12, 0.06), 0, _body)
	_rig.rotation.y = PI

func _process(delta: float) -> void:
	if _pivot and not _drag:
		_pivot.rotation.y += delta * 0.35
	if _rig and is_instance_valid(_rig):
		_rig.animate_locomotion(delta, 0.0)

func _preview_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		_pivot.rotation.y += e.relative.x * 0.01

func _begin() -> void:
	Game.set_identity(_origin, _body, _skin)
	chosen.emit(_style, _name_edit.text, _gi)
