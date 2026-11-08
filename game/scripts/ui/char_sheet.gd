class_name CharSheet
extends RefCounted
## The Character sheet (paper doll, gear slots, attributes, combat stats) and the Talent trees
## (three illustrated trees with tier gates, connector lines and a detail panel). Built in code;
## hud.gd puts each one in its journal tab.

const ATTR_COLORS := {
	"strength": Color(0.93, 0.42, 0.3), "flexibility": Color(0.35, 0.8, 0.5), "grip": Color(0.7, 0.5, 0.95),
	"cardio": Color(0.3, 0.75, 0.95), "iq": Color(0.97, 0.77, 0.28),
}
const ICONS := {
	"shot_speed": "chevron", "sprawl": "shield", "scramble": "loop", "t_snap_down": "link", "t_uchi_mata": "link", "t_flying_armbar": "star",
	"hip_mobility": "wave", "retention": "shield", "t_omoplata": "link", "slippery": "loop", "t_berimbolo": "link", "triangle_master": "triangle",
	"heavy_hips": "down", "heavy_top": "shield", "t_leg_drag": "link", "killer_instinct": "bolt", "t_chokes": "link", "second_wind": "heart",
}

static func _sb(bg: Color, border := Color(1, 1, 1, 0.08), radius := 14, pad := 14) -> StyleBoxFlat:
	var sb := UiKit.box(bg, radius, border, 2)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb

static func _panel(bg: Color, border := Color(1, 1, 1, 0.08), radius := 14, pad := 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(bg, border, radius, pad))
	return p

static func _head(text: String, size := 30, color := UiKit.ACCENT) -> Label:
	var l := UiKit.label(text, size, color)
	if UiKit.head_font():
		l.add_theme_font_override("font", UiKit.head_font())
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

static func _small(text: String, size := 14, color := UiKit.MUTED, wrap := false) -> Label:
	var l := UiKit.label(text, size, color)
	l.add_theme_constant_override("outline_size", 3)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	return l

# ================================================================== widgets
## Segmented attribute bar: each part is [count, color]; empty segments are faint.
class SegBar extends Control:
	var parts: Array = []
	var cap := 20
	func _init() -> void:
		custom_minimum_size = Vector2(180, 12)
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _draw() -> void:
		var gap := 3.0
		var sw := (size.x - gap * (cap - 1)) / cap
		var i := 0
		for p in parts:
			for k in int(p[0]):
				if i < cap:
					draw_rect(Rect2(i * (sw + gap), 0, sw, size.y), p[1])
					draw_rect(Rect2(i * (sw + gap), 0, sw, size.y * 0.35), Color(1, 1, 1, 0.18))
					i += 1
		while i < cap:
			draw_rect(Rect2(i * (sw + gap), 0, sw, size.y), Color(1, 1, 1, 0.07))
			i += 1

## Small vector icons for the gear slots.
class SlotIcon extends Control:
	var kind := "jacket"
	var col := Color.WHITE
	var accent := Color(0, 0, 0, 0)
	var trim := Color(0, 0, 0, 0)
	var empty := false
	func _init() -> void:
		custom_minimum_size = Vector2(44, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var s := minf(size.x, size.y)
		var o := (size - Vector2(s, s)) / 2.0
		var c := col if not empty else Color(1, 1, 1, 0.16)
		var dk := c.darkened(0.45)
		var tc := trim if trim.a > 0.0 and not empty else dk
		var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
		var poly := func(pts: Array) -> PackedVector2Array:
			var out := PackedVector2Array()
			for q in pts:
				out.append(p.call(q[0], q[1]))
			return out
		var w := maxf(2.0, s * 0.05)
		match kind:
			"jacket":
				draw_colored_polygon(poly.call([[0.3, 0.12], [0.5, 0.3], [0.7, 0.12], [0.92, 0.3], [0.82, 0.48], [0.74, 0.42], [0.74, 0.9], [0.26, 0.9], [0.26, 0.42], [0.18, 0.48], [0.08, 0.3]]), c)
				draw_polyline(poly.call([[0.3, 0.12], [0.5, 0.55], [0.7, 0.12]]), tc, w * 1.6)
				draw_line(p.call(0.26, 0.66), p.call(0.74, 0.66), Color(0.15, 0.12, 0.1) if not empty else c, w * 1.4)
			"pants", "spats":
				var bot := 0.92 if kind == "pants" else 0.7
				draw_colored_polygon(poly.call([[0.25, 0.12], [0.75, 0.12], [0.8, bot], [0.56, bot], [0.5, 0.42], [0.44, bot], [0.2, bot]]), c)
				draw_line(p.call(0.25, 0.2), p.call(0.75, 0.2), dk, w)
			"rash":
				draw_colored_polygon(poly.call([[0.34, 0.12], [0.66, 0.12], [0.92, 0.32], [0.82, 0.46], [0.72, 0.4], [0.72, 0.9], [0.28, 0.9], [0.28, 0.4], [0.18, 0.46], [0.08, 0.32]]), c)
				draw_arc(p.call(0.5, 0.12), s * 0.12, 0.0, PI, 12, dk, w)
			"knees":
				for x0 in [0.22, 0.56]:
					draw_rect(Rect2(p.call(x0, 0.28), Vector2(s * 0.22, s * 0.44)), c)
					draw_line(p.call(x0, 0.5), p.call(x0 + 0.22, 0.5), dk, w)
			"head":
				draw_arc(p.call(0.5, 0.55), s * 0.3, PI, TAU, 24, c, s * 0.12)
				draw_circle(p.call(0.2, 0.58), s * 0.1, c)
				draw_circle(p.call(0.8, 0.58), s * 0.1, c)
			"tape":
				for k in 4:
					var x := 0.22 + k * 0.17
					draw_rect(Rect2(p.call(x, 0.18 + absf(k - 1.5) * 0.06), Vector2(s * 0.12, s * 0.62)), Color(0.86, 0.66, 0.5) if not empty else c.darkened(0.2))
					draw_rect(Rect2(p.call(x - 0.01, 0.4), Vector2(s * 0.14, s * 0.1)), c)
					draw_rect(Rect2(p.call(x - 0.01, 0.6), Vector2(s * 0.14, s * 0.1)), c)
		# pattern hint: a few accent dots
		if accent.a > 0.0 and not empty:
			for q in [[0.42, 0.55], [0.58, 0.7], [0.5, 0.82], [0.62, 0.5]]:
				draw_circle(p.call(q[0], q[1]), s * 0.035, accent)

## 3D paper doll: the player's character on a mat, drag to turn.
class Doll extends SubViewportContainer:
	var vp: SubViewport
	var pivot: Node3D
	var rig: BodyRig
	var _drag := false
	var _yaw := PI - 0.45
	func _init() -> void:
		stretch = true
		custom_minimum_size = Vector2(220, 360)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		tooltip_text = "Drag to turn"
		vp = SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.msaa_3d = Viewport.MSAA_4X
		add_child(vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.62, 0.66, 0.72)
		env.ambient_light_energy = 0.75
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var key := DirectionalLight3D.new()
		key.rotation = Vector3(-0.7, 0.6, 0)
		key.light_energy = 1.25
		key.light_color = Color(1.0, 0.95, 0.86)
		vp.add_child(key)
		var rim := DirectionalLight3D.new()
		rim.rotation = Vector3(-0.3, PI + 0.5, 0)
		rim.light_energy = 0.9
		rim.light_color = Color(0.55, 0.75, 1.0)
		vp.add_child(rim)
		pivot = Node3D.new()
		vp.add_child(pivot)
		var mat := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.85
		cm.bottom_radius = 0.9
		cm.height = 0.06
		cm.radial_segments = 48
		mat.mesh = cm
		mat.material_override = BodyRig._mat(Color(0.12, 0.32, 0.22))
		mat.position.y = -0.03
		pivot.add_child(mat)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.84
		tm.outer_radius = 0.9
		ring.mesh = tm
		ring.scale = Vector3(1, 0.3, 1)
		ring.material_override = BodyRig._mat(UiKit.ACCENT.darkened(0.2))
		pivot.add_child(ring)
		rig = BodyRig.new()
		rig.lod_enabled = false
		pivot.add_child(rig)
		Game.dress(rig)
		rig.setup(Game.gi_color(), Data.BELTS[Game.belt_index()].color, Color(0.86, 0.68, 0.55), Color(0.55, 0.36, 0.18), 0, "male")
		var cam := Camera3D.new()
		cam.fov = 30
		cam.transform = Transform3D(Basis(), Vector3(0, 1.2, 6.2)).looking_at(Vector3(0, 0.98, 0))
		vp.add_child(cam)
		cam.current = true
	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		if not _drag:
			_yaw = lerp_angle(_yaw, PI - 0.45 + sin(Time.get_ticks_msec() / 2600.0) * 0.25, clampf(delta * 1.5, 0, 1))
		pivot.rotation.y = _yaw
		rig.animate_locomotion(delta, 0.0, false)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_drag = e.pressed
		elif e is InputEventMouseMotion and _drag:
			_yaw += e.relative.x * 0.012
		elif e is InputEventScreenDrag:
			_yaw += e.relative.x * 0.012

# ================================================================== character tab
static func build_character(hud) -> Control:
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if Game.style == "":
		page.add_child(UiKit.label("No style chosen yet.", 20))
		return page
	page.add_child(_doll_panel(hud))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	page.add_child(right)
	right.add_child(_attr_panel())
	right.add_child(_stats_panel())
	return page

static func _doll_panel(hud) -> Control:
	var st: Dictionary = Rpg.STYLES[Game.style]
	var belt: Dictionary = Data.BELTS[Game.belt_index()]
	var p := _panel(Color(0.05, 0.08, 0.07, 0.95), Color(belt.color, 0.55))
	p.custom_minimum_size = Vector2(470, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -4)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nv)
	nv.add_child(_head(Game.player_name, 44, UiKit.TEXT))
	nv.add_child(_small("%s  ·  %s" % [st.name, Data.rank_name(Game.rank)], 17, UiKit.ACCENT))
	var lv := Game.player_level()
	var badge := _panel(Color(0, 0, 0, 0.5), UiKit.ACCENT, 30, 8)
	badge.custom_minimum_size = Vector2(76, 76)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", -8)
	badge.add_child(bv)
	bv.add_child(_small("LEVEL", 12, UiKit.MUTED))
	var ll := _head(str(lv), 40)
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(ll)
	(bv.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(badge)

	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 8)
	v.add_child(mid)
	# WoW-style paper doll: slot columns either side of the 3D model, kit switch on top
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 8)
	mid.add_child(lcol)
	for slot in Gear.DOLL_LEFT:
		lcol.add_child(_slot_square(hud, slot))
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 6)
	mid.add_child(centre)
	var kits := HBoxContainer.new()
	kits.alignment = BoxContainer.ALIGNMENT_CENTER
	kits.add_theme_constant_override("separation", 6)
	centre.add_child(kits)
	for k in Gear.KITS:
		var kb := Button.new()
		kb.text = Gear.KIT_NAMES[k].to_upper()
		kb.custom_minimum_size = Vector2(96, 32)
		kb.focus_mode = Control.FOCUS_NONE
		kb.add_theme_font_size_override("font_size", 15)
		var on: bool = Game.kit == k
		kb.add_theme_stylebox_override("normal", UiKit.box(UiKit.ACCENT if on else Color(0, 0, 0, 0.45), 16, UiKit.ACCENT if on else Color(1, 1, 1, 0.15), 2))
		kb.add_theme_stylebox_override("hover", UiKit.box(UiKit.ACCENT.darkened(0.2) if on else Color(0.2, 0.2, 0.2, 0.7), 16, UiKit.ACCENT, 2))
		kb.add_theme_color_override("font_color", Color(0.1, 0.07, 0.02) if on else UiKit.TEXT)
		kb.tooltip_text = "Wear your %s kit. Only the worn kit's gear and set pieces count." % Gear.KIT_NAMES[k]
		kb.pressed.connect(func(): Game.set_kit(k))
		kits.add_child(kb)
	var stage := _panel(Color(0.08, 0.12, 0.1, 0.6), Color(1, 1, 1, 0.05), 12, 0)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.add_child(stage)
	stage.add_child(Doll.new())
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 8)
	mid.add_child(rcol)
	for slot in Gear.DOLL_RIGHT:
		rcol.add_child(_slot_square(hud, slot))
	v.add_child(_sets_box())

	# xp
	var xr := HBoxContainer.new()
	xr.add_theme_constant_override("separation", 10)
	v.add_child(xr)
	var xb := UiKit.bar(Color(0.62, 0.36, 0.95) if not Game.level_capped() else UiKit.ACCENT, Vector2(0, 14))
	xb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xb.max_value = 1.0
	xb.step = 0.0
	xb.value = 1.0 if Game.level_capped() else Game.level_progress()
	xr.add_child(xb)
	var xt := ""
	if lv >= Game.MAX_LEVEL:
		xt = "Max level"
	elif Game.level_capped():
		xt = "Belt cap: beat the zone boss"
	else:
		xt = "%d XP to %d" % [Game.XP_PER_LEVEL - int(Game.level_progress() * Game.XP_PER_LEVEL), lv + 1]
	xr.add_child(_small(xt, 14, UiKit.MUTED))
	# passive + signature
	var pp := _panel(Color(0.97, 0.77, 0.28, 0.08), Color(0.97, 0.77, 0.28, 0.35), 10, 10)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 2)
	pp.add_child(pv)
	pv.add_child(_small("STYLE PASSIVE  ·  " + st.tag.to_upper(), 13, UiKit.ACCENT))
	pv.add_child(_small(st.passive, 15, UiKit.TEXT, true))
	var sig: Array = []
	for mid_ in st.signature:
		sig.append(Data.MOVES[mid_].name)
	pv.add_child(_small("Signature: " + ", ".join(sig), 14, UiKit.MUTED, true))
	v.add_child(pp)
	return p

## A paper-doll slot: square icon with a rarity border; hover shows a WoW-style tooltip.
class SlotSquare extends PanelContainer:
	var item := ""
	var slot := ""
	func _make_custom_tooltip(_for_text: String) -> Object:
		return CharSheet.item_tooltip(item, slot)

static func _slot_square(hud, slot: String) -> Control:
	var id := str(Game.equipped.get(slot, ""))
	var has := id != "" and Gear.ITEMS.has(id)
	var active: bool = slot in Gear.KITS[Game.kit]
	var rc: Color = Gear.rarity_color(id) if has else Color(1, 1, 1, 0.15)
	var b := SlotSquare.new()
	b.item = id if has else ""
	b.slot = slot
	b.tooltip_text = " "
	b.custom_minimum_size = Vector2(66, 66)
	b.modulate = Color(1, 1, 1, 1.0 if active else 0.4)
	var nsb := _sb(Color(rc, 0.1) if has else Color(0, 0, 0, 0.45), rc, 10, 5)
	var hsb := _sb(Color(rc, 0.22) if has else Color(0.1, 0.1, 0.1, 0.7), rc.lightened(0.35), 10, 5)
	nsb.border_width_left = 2
	b.add_theme_stylebox_override("panel", nsb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.mouse_entered.connect(func(): b.add_theme_stylebox_override("panel", hsb))
	b.mouse_exited.connect(func(): b.add_theme_stylebox_override("panel", nsb))
	b.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			hud._want_tab = 2
			hud._fill_journal())
	var ic := SlotIcon.new()
	ic.kind = slot
	ic.empty = not has
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if has:
		var lk := Gear.look(id)
		ic.col = lk.get("color", Color(0.95, 0.95, 0.9))
		if id == "standard_gi" or id == "standard_gi_pants":
			ic.col = Game.gi_color()
		ic.accent = lk.get("accent", Color(0, 0, 0, 0))
		ic.trim = lk.get("trim", Color(0, 0, 0, 0))
	b.add_child(ic)
	return b

## WoW-style item tooltip: name in quality colour, slot, stats, set pieces and set bonuses.
static func item_tooltip(id: String, slot: String) -> Control:
	var p := _panel(Color(0.03, 0.04, 0.06, 0.97), Color(1, 1, 1, 0.25), 8, 10)
	p.custom_minimum_size = Vector2(300, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	if id == "":
		v.add_child(_small(Gear.SLOT_NAMES.get(slot, slot), 16, UiKit.TEXT))
		v.add_child(_small("Empty. Bosses, quests and medals drop gear.", 13, UiKit.MUTED, true))
		return p
	var it: Dictionary = Gear.ITEMS[id]
	v.add_child(_small(it.name, 17, Gear.rarity_color(id), true))
	var meta := HBoxContainer.new()
	v.add_child(meta)
	var sl := _small(Gear.SLOT_NAMES[it.slot], 13, UiKit.TEXT)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(sl)
	meta.add_child(_small(Gear.RARITY[it.rarity].name, 13, Gear.rarity_color(id)))
	for k in Rpg.ATTR_ORDER:
		var val := int(it.attrs.get(k, 0))
		if val > 0:
			v.add_child(_small("+%d %s" % [val, Rpg.ATTRS[k].name], 14, UiKit.TEXT))
	if it.has("set"):
		var st: Dictionary = Gear.SETS[it.set]
		var have := int(Game.set_counts().get(it.set, 0))
		v.add_child(_small(" ", 6))
		v.add_child(_small("%s (%d/%d)" % [st.name, have, st.pieces.size()], 14, UiKit.ACCENT))
		for pid in st.pieces:
			var worn: bool = pid in Game.worn()
			v.add_child(_small("   " + Gear.ITEMS[pid].name, 13, Color(1, 0.95, 0.7) if worn else Color(0.55, 0.55, 0.55)))
		for line in Gear.set_lines(it.set):
			var on := have >= int(line[0])
			v.add_child(_small("(%d) Set: %s" % [line[0], line[1]], 13, Color(0.35, 1.0, 0.35) if on else Color(0.55, 0.55, 0.55), true))
	v.add_child(_small(" ", 6))
	v.add_child(_small("\"%s\"" % it.desc, 13, Color(1, 0.82, 0.3), true))
	v.add_child(_small("Source: %s" % it.source, 12, UiKit.MUTED, true))
	return p

## Active / partial set bonuses under the paper doll.
static func _sets_box() -> Control:
	var c := Game.set_counts()
	var p := _panel(Color(0, 0, 0, 0.3), Color(1, 1, 1, 0.08), 10, 10)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	if c.is_empty():
		v.add_child(_small("SET BONUSES", 13, UiKit.ACCENT))
		v.add_child(_small("Wear 2 or 4 pieces of a set (boss drops) to unlock bonuses.", 13, UiKit.MUTED, true))
		return p
	for st in c:
		var sd: Dictionary = Gear.SETS[st]
		v.add_child(_small("%s  %d/%d" % [sd.name.to_upper(), int(c[st]), sd.pieces.size()], 14, UiKit.ACCENT))
		for line in Gear.set_lines(st):
			var on := int(c[st]) >= int(line[0])
			v.add_child(_small("(%d) %s" % [line[0], line[1]], 13, Color(0.35, 1.0, 0.35) if on else Color(0.55, 0.55, 0.55), true))
	return p

static func _attr_panel() -> Control:
	var p := _panel(Color(0.05, 0.08, 0.07, 0.95))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var hd := HBoxContainer.new()
	v.add_child(hd)
	var t := _head("ATTRIBUTES", 30)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.add_child(t)
	var ap := Game.attr_points()
	var pill := _panel(Color(0.97, 0.77, 0.28, 0.9) if ap > 0 else Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 20, 6)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pl := _small("%d point%s to spend" % [ap, "" if ap == 1 else "s"] if ap > 0 else "No points  ·  +1 every level", 15, Color(0.1, 0.08, 0.02) if ap > 0 else UiKit.MUTED)
	pl.add_theme_constant_override("outline_size", 0)
	pill.add_child(pl)
	hd.add_child(pill)
	# legend
	var lg := HBoxContainer.new()
	lg.add_theme_constant_override("separation", 14)
	v.add_child(lg)
	for e in [["Base + training", [Color(0.78, 0.78, 0.74)]], ["Style", [ATTR_COLORS.strength.darkened(0.25), ATTR_COLORS.flexibility.darkened(0.25), ATTR_COLORS.cardio.darkened(0.25)]], ["Your points", [UiKit.ACCENT]], ["Gear", [Color(0.45, 0.95, 0.45)]]]:
		var sws := HBoxContainer.new()
		sws.add_theme_constant_override("separation", 1)
		for c in e[1]:
			var sw := ColorRect.new()
			sw.color = c
			sw.custom_minimum_size = Vector2(12 / (e[1] as Array).size() + 1, 12)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sws.add_child(sw)
		lg.add_child(sws)
		lg.add_child(_small(e[0], 12))
	for k in Rpg.ATTR_ORDER:
		v.add_child(_attr_row(k, ap))
	return p

static func _attr_row(k: String, ap: int) -> Control:
	var a: Dictionary = Rpg.ATTRS[k]
	var col: Color = ATTR_COLORS[k]
	var row := _panel(Color(col, 0.06), Color(col, 0.18), 10, 6)
	row.tooltip_text = a.desc
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var badge := _panel(col.darkened(0.35), col, 10, 0)
	badge.custom_minimum_size = Vector2(48, 48)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bl := _head(a.short, 22, UiKit.TEXT)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bl)
	h.add_child(badge)
	var mv := VBoxContainer.new()
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.add_theme_constant_override("separation", 3)
	h.add_child(mv)
	var top := HBoxContainer.new()
	mv.add_child(top)
	var nm := UiKit.label(a.name, 18)
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var gb := Game.gear_bonus(k)
	if gb > 0:
		var gl := _small("+%d gear" % gb, 14, Color(0.45, 0.95, 0.45))
		gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(gl)
	var val := _head(str(Game.attr(k)), 28, col.lightened(0.2))
	top.add_child(val)
	var cap := _small(" / %d" % Rpg.ATTR_CAP, 13)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(cap)
	var style_b := int(Rpg.STYLES[Game.style].attrs.get(k, 0)) if Game.style != "" else 0
	var alloc := int(Game.attr_alloc.get(k, 0))
	var bar := SegBar.new()
	bar.cap = Rpg.ATTR_CAP
	bar.parts = [[Rpg.ATTR_BASE + Game.train_bonus(k), Color(0.78, 0.78, 0.74)], [style_b, col.darkened(0.25)], [alloc, UiKit.ACCENT], [gb, Color(0.45, 0.95, 0.45)]]
	bar.tooltip_text = "Base %d · Training +%d · Style +%d · Points +%d · Gear +%d" % [Rpg.ATTR_BASE, Game.train_bonus(k), style_b, alloc, gb]
	mv.add_child(bar)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(42, 42)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus.focus_mode = Control.FOCUS_NONE
	plus.add_theme_font_size_override("font_size", 26)
	var can := ap > 0 and Game.attr(k) < Rpg.ATTR_CAP
	plus.disabled = not can
	plus.add_theme_stylebox_override("normal", UiKit.box(UiKit.ACCENT.darkened(0.15), 23, UiKit.ACCENT.lightened(0.3), 2))
	plus.add_theme_stylebox_override("hover", UiKit.box(UiKit.ACCENT, 23, Color.WHITE, 2))
	plus.add_theme_stylebox_override("pressed", UiKit.box(UiKit.ACCENT.darkened(0.3), 23, Color.WHITE, 2))
	plus.add_theme_stylebox_override("disabled", UiKit.box(Color(1, 1, 1, 0.04), 23, Color(1, 1, 1, 0.08), 1))
	plus.add_theme_color_override("font_color", Color(0.12, 0.08, 0.02))
	plus.add_theme_color_override("font_hover_color", Color(0.12, 0.08, 0.02))
	plus.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.15))
	plus.tooltip_text = "Raise %s" % a.name
	plus.pressed.connect(func(): Game.raise_attr(k))
	h.add_child(plus)
	return row

static func _stats_panel() -> Control:
	var p := _panel(Color(0.05, 0.08, 0.07, 0.95))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(_head("ON THE MAT", 26))
	var m := Game.mods()
	var pct := func(x: float) -> String: return ("+%d%%" % roundi((x - 1.0) * 100.0)) if x >= 1.0 else ("%d%%" % roundi((x - 1.0) * 100.0))
	var wins := 0
	for k in Game.wins:
		wins += int(Game.wins[k])
	var losses := 0
	for k in Game.losses:
		losses += int(Game.losses[k])
	var mc := Game.medal_counts()
	var tiles := [
		["Stamina", str(int(m.stamina_max)), "Gas tank for a roll. Cardio raises it.", ATTR_COLORS.cardio],
		["Recovery", pct.call(float(m.regen)), "Stamina regained between exchanges.", ATTR_COLORS.cardio],
		["Technique cost", pct.call(float(m.cost)), "Stamina each technique costs.", ATTR_COLORS.cardio],
		["Reaction time", pct.call(float(m.defense)), "Time to answer an attack. IQ raises it.", ATTR_COLORS.iq],
		["Perfect window", pct.call(float(m.perfect)), "Size of the perfect-timing zone.", ATTR_COLORS.iq],
		["Squeeze", pct.call(float(m.struggle_atk)), "Finishing power on submissions.", ATTR_COLORS.strength],
		["Escape", pct.call(float(m.struggle_def)), "How fast you break out of submissions.", ATTR_COLORS.flexibility],
		["Sub depth", "+%d%%" % roundi(float(m.sub_start) * 100.0), "How deep your submissions start.", ATTR_COLORS.grip],
		["Record", "%d–%d" % [wins, losses], "Wins and losses across every roll.", UiKit.TEXT],
		["Medals", "%d·%d·%d" % [mc.gold, mc.silver, mc.bronze], "Gold · silver · bronze.", UiKit.ACCENT],
	]
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	v.add_child(g)
	for t in tiles:
		var tile := _panel(Color(t[3], 0.07), Color(t[3], 0.22), 10, 8)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.tooltip_text = t[2]
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -4)
		tile.add_child(tv)
		tv.add_child(_head(t[1], 28, (t[3] as Color).lightened(0.15)))
		var cl := _small(str(t[0]).to_upper(), 11)
		cl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tv.add_child(cl)
		g.add_child(tile)
	return p

# ================================================================== talents tab
## One talent node: rounded square icon with rank badge and name underneath.
class TalentNode extends Control:
	signal picked(tid: String)
	signal learn_requested(tid: String)
	signal hovered(tid: String, on: bool)
	var tid := ""
	var tree_col := Color.WHITE
	var icon := "chevron"
	var rank := 0
	var max_rank := 1
	var unlocked := false
	var can_learn := false
	var selected := false
	var capstone := false
	var technique := false
	var title := ""
	var show_name := true
	var _hover := false
	var S := 64.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func():
			_hover = true
			hovered.emit(tid, true)
			queue_redraw())
		mouse_exited.connect(func():
			_hover = false
			hovered.emit(tid, false)
			queue_redraw())
	func configure(id: String, s := 56.0) -> void:
		tid = id
		var t: Dictionary = Rpg.TALENTS[id]
		tree_col = Rpg.TREES[t.tree].color
		icon = CharSheet.ICONS.get(id, "chevron")
		rank = Game.talent_rank(id)
		max_rank = int(t.max)
		unlocked = Game.talent_unlocked(id)
		can_learn = Game.can_learn(id)
		capstone = int(t.tier) == 3
		technique = t.has("move") or t.has("moves")
		title = t.name
		S = s * (1.15 if capstone else 1.0)
		custom_minimum_size = Vector2(maxf(S + 36, 98), S + (30 if show_name else 8))
	func _process(_d: float) -> void:
		if can_learn and rank == 0:
			queue_redraw()   # pulsing "available" glow
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_RIGHT or (e.button_index == MOUSE_BUTTON_LEFT and (e.double_click or selected)):
				learn_requested.emit(tid)
			elif e.button_index == MOUSE_BUTTON_LEFT:
				picked.emit(tid)
			accept_event()
	func _draw() -> void:
		var sq := Rect2(Vector2((size.x - S) / 2.0, 4), Vector2(S, S))
		var maxed := rank >= max_rank
		var lit := unlocked or rank > 0
		var bg := tree_col.darkened(0.55) if lit else Color(0.1, 0.11, 0.11)
		var border := Color(1, 1, 1, 0.14)
		var bw := 2
		if maxed:
			border = UiKit.ACCENT
			bw = 3
		elif rank > 0:
			border = tree_col.lightened(0.2)
			bw = 3
		elif can_learn:
			border = Color(0.35, 1.0, 0.5)
			bw = 3
		elif unlocked:
			border = Color(tree_col, 0.5)
		# glow
		if can_learn or maxed or selected or _hover:
			var g := StyleBoxFlat.new()
			g.bg_color = Color(0, 0, 0, 0)
			var gc := UiKit.ACCENT if maxed else (Color(0.35, 1.0, 0.5) if can_learn else tree_col)
			if selected:
				gc = Color.WHITE
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0) if can_learn and rank == 0 else 1.0
			g.shadow_color = Color(gc, 0.25 + 0.3 * pulse)
			g.shadow_size = int(10 + 6 * pulse)
			g.set_corner_radius_all(14 if not capstone else int(S / 2))
			draw_style_box(g, sq)
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(bw)
		sb.set_corner_radius_all(14 if not capstone else int(S / 2))
		sb.anti_aliasing = true
		draw_style_box(sb, sq)
		# sheen
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(1, 1, 1, 0.08 if lit else 0.03)
		sh.corner_radius_top_left = 12 if not capstone else int(S / 2)
		sh.corner_radius_top_right = sh.corner_radius_top_left
		draw_style_box(sh, Rect2(sq.position + Vector2(bw, bw), Vector2(S - bw * 2, S * 0.42)))
		var gcol := Color(1, 1, 1, 0.95) if lit else Color(1, 1, 1, 0.22)
		if maxed:
			gcol = Color(1.0, 0.93, 0.7)
		CharSheet.draw_glyph(self, icon, sq.get_center(), S * 0.5, gcol)
		# technique marker (unlocks a move)
		if technique:
			var c := sq.position + Vector2(10, 10)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)]), UiKit.ACCENT if lit else Color(1, 1, 1, 0.25))
		if selected:
			var ss := StyleBoxFlat.new()
			ss.draw_center = false
			ss.border_color = Color.WHITE
			ss.set_border_width_all(2)
			ss.set_corner_radius_all(17 if not capstone else int(S / 2) + 4)
			draw_style_box(ss, sq.grow(5))
		# rank pill
		var font := UiKit.body_font() if UiKit.body_font() else ThemeDB.fallback_font
		var txt := "%d/%d" % [rank, max_rank]
		var pr := Rect2(sq.end - Vector2(34, 16), Vector2(38, 22))
		var ps := StyleBoxFlat.new()
		ps.bg_color = Color(0.04, 0.04, 0.04, 0.95)
		ps.border_color = border if lit else Color(1, 1, 1, 0.15)
		ps.set_border_width_all(1)
		ps.set_corner_radius_all(8)
		draw_style_box(ps, pr)
		var tc := UiKit.ACCENT if maxed else (Color(0.45, 1.0, 0.55) if rank > 0 or can_learn else Color(1, 1, 1, 0.4))
		draw_string(font, pr.position + Vector2(0, 16), txt, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, 13, tc)
		if not unlocked and rank == 0:
			CharSheet.draw_glyph(self, "lock", sq.position + Vector2(S - 12, 12), 14, Color(1, 1, 1, 0.45))
		if show_name:
			var fs := 13
			while fs > 10 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 2:
				fs -= 1
			draw_string_outline(font, Vector2(0, sq.end.y + 20), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, 4, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2(0, sq.end.y + 20), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, UiKit.TEXT if lit else Color(1, 1, 1, 0.4))

## Simple vector glyphs (no icon art needed).
static func draw_glyph(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(2.0, s * 0.11)
	match kind:
		"chevron", "down":
			var dir := -1.0 if kind == "chevron" else 1.0
			for k in 3:
				var y := c.y + (k - 1) * s * 0.3 * -dir
				ci.draw_polyline(PackedVector2Array([Vector2(c.x - s * 0.38, y - dir * s * 0.16), Vector2(c.x, y + dir * s * 0.16), Vector2(c.x + s * 0.38, y - dir * s * 0.16)]),
					Color(col, 1.0 - k * 0.25), w, true)
		"shield":
			var pts := PackedVector2Array([c + Vector2(0, -s * 0.5), c + Vector2(s * 0.42, -s * 0.34), c + Vector2(s * 0.36, s * 0.12), c + Vector2(0, s * 0.52),
				c + Vector2(-s * 0.36, s * 0.12), c + Vector2(-s * 0.42, -s * 0.34)])
			ci.draw_colored_polygon(pts, Color(col, 0.25))
			pts.append(pts[0])
			ci.draw_polyline(pts, col, w, true)
			ci.draw_line(c + Vector2(0, -s * 0.36), c + Vector2(0, s * 0.36), Color(col, 0.7), w * 0.7, true)
		"loop":
			ci.draw_arc(c, s * 0.38, 0.5, TAU - 0.4, 28, col, w, true)
			var e := c + Vector2(cos(TAU - 0.4), sin(TAU - 0.4)) * s * 0.38
			ci.draw_colored_polygon(PackedVector2Array([e + Vector2(-s * 0.2, -s * 0.02), e + Vector2(s * 0.1, -s * 0.2), e + Vector2(s * 0.12, s * 0.14)]), col)
		"wave":
			var pts := PackedVector2Array()
			for i in 21:
				var x := -0.45 + i * 0.045
				pts.append(c + Vector2(x * s, sin(x * 12.0) * s * 0.18 - s * 0.12))
			ci.draw_polyline(pts, col, w, true)
			var pts2 := PackedVector2Array()
			for pt in pts:
				pts2.append(pt + Vector2(0, s * 0.3))
			ci.draw_polyline(pts2, Color(col, 0.6), w, true)
		"link":
			ci.draw_arc(c + Vector2(-s * 0.15, 0), s * 0.27, 0, TAU, 28, col, w, true)
			ci.draw_arc(c + Vector2(s * 0.15, 0), s * 0.27, 0, TAU, 28, Color(col, 0.65), w, true)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var r := s * (0.52 if i % 2 == 0 else 0.22)
				var a := -PI / 2 + i * PI / 5
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			ci.draw_colored_polygon(pts, col)
		"triangle":
			var pts := PackedVector2Array([c + Vector2(0, -s * 0.45), c + Vector2(s * 0.46, s * 0.36), c + Vector2(-s * 0.46, s * 0.36), c + Vector2(0, -s * 0.45)])
			ci.draw_polyline(pts, col, w * 1.2, true)
			ci.draw_circle(c + Vector2(0, s * 0.1), s * 0.1, col)
		"bolt":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.1, -s * 0.52), c + Vector2(-s * 0.3, s * 0.06), c + Vector2(-s * 0.02, s * 0.06),
				c + Vector2(-s * 0.12, s * 0.52), c + Vector2(s * 0.3, -s * 0.08), c + Vector2(s * 0.02, -s * 0.08)]), col)
		"heart":
			var pts := PackedVector2Array()
			for i in 40:
				var t := i / 40.0 * TAU
				pts.append(c + Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) * s * 0.028)
			ci.draw_colored_polygon(pts, col)
		"lock":
			ci.draw_arc(c + Vector2(0, -s * 0.15), s * 0.28, PI, TAU, 12, col, maxf(1.5, s * 0.12), true)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.4, -s * 0.12), Vector2(s * 0.8, s * 0.6)), col)

## One tree's node field: tier rows, gate labels and connector lines.
class TreeGrid extends Control:
	const ROW := 112.0
	const GUTTER := 34.0
	var tree := ""
	var nodes := {}   # tier -> [TalentNode]
	func _init() -> void:
		custom_minimum_size = Vector2(226, ROW * 4 + 6)
		mouse_filter = Control.MOUSE_FILTER_PASS
		resized.connect(_layout)
	func add_node(n: TalentNode, tier: int) -> void:
		if not nodes.has(tier):
			nodes[tier] = []
		nodes[tier].append(n)
		add_child(n)
	func _layout() -> void:
		for tier in nodes:
			var arr: Array = nodes[tier]
			for i in arr.size():
				var n: TalentNode = arr[i]
				var fx := 0.5 if arr.size() == 1 else (0.27 + 0.46 * i / float(arr.size() - 1))
				n.size = n.custom_minimum_size
				n.position = Vector2(GUTTER + (size.x - GUTTER) * fx - n.size.x / 2.0, tier * ROW + 14)
		queue_redraw()
	func _anchor(n: TalentNode, top: bool) -> Vector2:
		var sq_top := n.position + Vector2(n.size.x / 2.0, 4)
		return sq_top if top else n.position + Vector2(n.size.x / 2.0, n.size.y + 2)
	func _draw() -> void:
		var col: Color = Rpg.TREES[tree].color
		var pts := Game.tree_points(tree)
		var font := UiKit.body_font() if UiKit.body_font() else ThemeDB.fallback_font
		for tier in 4:
			var y := tier * ROW + 4
			var open: bool = pts >= int(Rpg.TIER_REQ[tier])
			if tier > 0:
				draw_dashed_line(Vector2(GUTTER, y), Vector2(size.x - 6, y), Color(col, 0.3) if open else Color(1, 1, 1, 0.07), 1.0, 6.0)
			# tier badge in the left gutter: roman tier number + points needed
			var bc := Vector2(GUTTER * 0.5, y + ROW * 0.42)
			draw_circle(bc, 13, Color(col.darkened(0.5), 0.9) if open else Color(0, 0, 0, 0.45))
			draw_arc(bc, 13, 0, TAU, 24, Color(col, 0.9) if open else Color(1, 1, 1, 0.15), 1.5, true)
			draw_string(font, bc + Vector2(-13, 5), ["I", "II", "III", "IV"][tier], HORIZONTAL_ALIGNMENT_CENTER, 26, 13, UiKit.TEXT if open else Color(1, 1, 1, 0.35))
			if tier > 0:
				if open:
					draw_string(font, bc + Vector2(-17, 30), "%d pts" % Rpg.TIER_REQ[tier], HORIZONTAL_ALIGNMENT_CENTER, 34, 10, Color(col, 0.8))
				else:
					CharSheet.draw_glyph(self, "lock", bc + Vector2(0, 26), 11, Color(1, 1, 1, 0.35))
					draw_string(font, bc + Vector2(-17, 46), "%d pts" % Rpg.TIER_REQ[tier], HORIZONTAL_ALIGNMENT_CENTER, 34, 10, Color(1, 1, 1, 0.35))
		# connectors (behind the nodes, since children draw on top)
		for tier in 3:
			if not nodes.has(tier) or not nodes.has(tier + 1):
				continue
			var a: Array = nodes[tier]
			var b: Array = nodes[tier + 1]
			var lit: bool = pts >= int(Rpg.TIER_REQ[tier + 1])
			for j in b.size():
				var froms: Array = [a[j]] if a.size() == b.size() else a
				for f in froms:
					var p0 := _anchor(f, false) + Vector2(0, 2)
					var p1 := _anchor(b[j], true) - Vector2(0, 4)
					var c := col if lit else Color(1, 1, 1, 0.1)
					draw_line(p0, p1, Color(0, 0, 0, 0.5), 7.0, true)
					draw_line(p0, p1, c, 3.0, true)
					if lit:
						var d := (p1 - p0).normalized()
						var nrm := Vector2(-d.y, d.x)
						draw_colored_polygon(PackedVector2Array([p1, p1 - d * 10 + nrm * 6, p1 - d * 10 - nrm * 6]), c)

static func build_talents(hud) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tp := Game.talent_points()
	var spent := 0
	for tr in Rpg.TREE_ORDER:
		spent += Game.tree_points(tr)
	# header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	page.add_child(head)
	var pill := _panel(Color(0.97, 0.77, 0.28, 0.92) if tp > 0 else Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 22, 8)
	var pv := HBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	pill.add_child(pv)
	var pn := _head(str(tp), 34, Color(0.12, 0.08, 0.02) if tp > 0 else UiKit.MUTED)
	pv.add_child(pn)
	var pt := _small("TALENT POINT%s\nAVAILABLE" % ("" if tp == 1 else "S"), 12, Color(0.12, 0.08, 0.02) if tp > 0 else UiKit.MUTED)
	pt.add_theme_constant_override("outline_size", 0)
	pt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pv.add_child(pt)
	head.add_child(pill)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", 0)
	head.add_child(hv)
	hv.add_child(UiKit.label("%d spent  ·  next point at level %d" % [spent, _next_tp_level()], 18))
	hv.add_child(_small("Click a talent to inspect it. Click again, double-click or right-click to learn. Deeper tiers open at 2 / 4 / 6 points in a tree.", 14, UiKit.MUTED, true))
	var rs := UiKit.button("Reset", Vector2(110, 44))
	rs.add_theme_font_size_override("font_size", 16)
	rs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rs.tooltip_text = "Refund every talent point"
	rs.disabled = spent == 0
	rs.pressed.connect(func():
		hud._sel_talent = ""
		Game.reset_talents())
	head.add_child(rs)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	var detail := _panel(Color(0.04, 0.06, 0.05, 0.97), Color(1, 1, 1, 0.1), 14, 16)
	detail.custom_minimum_size = Vector2(260, 0)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	detail.add_child(dv)
	var show := func(tid: String) -> void: _fill_detail(hud, detail, dv, tid)
	var learn := func(tid: String) -> void:
		hud._sel_talent = tid
		if not Game.learn(tid):
			hud._fill_journal()
	for tree in Rpg.TREE_ORDER:
		body.add_child(_tree_panel(hud, tree, show, learn))
	body.add_child(detail)
	show.call(hud._sel_talent)
	return page

static func _next_tp_level() -> int:
	var lv := Game.player_level()
	return lv + (Rpg.LEVELS_PER_TALENT_POINT - lv % Rpg.LEVELS_PER_TALENT_POINT)

static func _tree_panel(hud, tree: String, show: Callable, learn: Callable) -> Control:
	var info: Dictionary = Rpg.TREES[tree]
	var col: Color = info.color
	var p := _panel(Color(col.darkened(0.86), 0.97), Color(col, 0.45), 16, 12)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -6)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nv)
	nv.add_child(_head(info.name.to_upper(), 32, col.lightened(0.15)))
	nv.add_child(_small(info.pt, 14, Color(col, 0.75)))
	var pts := Game.tree_points(tree)
	var pc := _head(str(pts), 40, UiKit.TEXT if pts > 0 else Color(1, 1, 1, 0.3))
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pc)
	var bar := UiKit.bar(col, Vector2(0, 8))
	bar.max_value = Rpg.TIER_REQ[3] + 1
	bar.value = mini(pts, Rpg.TIER_REQ[3] + 1)
	bar.show_percentage = false
	v.add_child(bar)
	var grid := TreeGrid.new()
	grid.tree = tree
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	for tid in Rpg.talents_in(tree):
		var n := TalentNode.new()
		n.configure(tid)
		n.selected = tid == hud._sel_talent
		n.picked.connect(func(id: String):
			hud._sel_talent = id
			hud._want_tab = hud.journal_tabs.current_tab
			hud._fill_journal())
		n.learn_requested.connect(learn)
		n.hovered.connect(func(id: String, on: bool): show.call(id if on else hud._sel_talent))
		grid.add_node(n, int(Rpg.TALENTS[tid].tier))
	return p

static func _fill_detail(hud, panel: PanelContainer, dv: VBoxContainer, tid: String) -> void:
	if not is_instance_valid(dv):
		return
	for c in dv.get_children():
		c.queue_free()
	if tid == "" or not Rpg.TALENTS.has(tid):
		panel.add_theme_stylebox_override("panel", _sb(Color(0.04, 0.06, 0.05, 0.97), Color(1, 1, 1, 0.1), 14, 16))
		dv.add_child(_head("YOUR BUILD", 30))
		for tree in Rpg.TREE_ORDER:
			var info: Dictionary = Rpg.TREES[tree]
			var row := HBoxContainer.new()
			var l := UiKit.label(info.name, 17, info.color)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			row.add_child(_head(str(Game.tree_points(tree)), 24, UiKit.TEXT))
			dv.add_child(row)
			var b := UiKit.bar(info.color, Vector2(0, 6))
			b.max_value = 7
			b.value = Game.tree_points(tree)
			b.show_percentage = false
			dv.add_child(b)
		var learned: Array = []
		for id in Rpg.TALENTS:
			if Game.talent_rank(id) > 0:
				learned.append("%s %d/%d" % [Rpg.TALENTS[id].name, Game.talent_rank(id), int(Rpg.TALENTS[id].max)])
		dv.add_child(_small("Learned", 13, UiKit.ACCENT))
		dv.add_child(_small(", ".join(learned) if not learned.is_empty() else "Nothing yet. Spend your first point on a tier 1 talent.", 15, UiKit.TEXT, true))
		dv.add_child(_small("Tip: diamonds mark talents that teach a new technique. The bottom of each tree is a capstone.", 13, UiKit.MUTED, true))
		return
	var t: Dictionary = Rpg.TALENTS[tid]
	var info: Dictionary = Rpg.TREES[t.tree]
	var col: Color = info.color
	panel.add_theme_stylebox_override("panel", _sb(Color(col.darkened(0.88), 0.98), Color(col, 0.7), 14, 16))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	dv.add_child(top)
	var n := TalentNode.new()
	n.show_name = false
	n.configure(tid, 58)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.custom_minimum_size = Vector2(n.S + 14, n.S + 14)
	top.add_child(n)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tv)
	var nm := _head(t.name.to_upper(), 30, UiKit.TEXT)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(nm)
	var kind := "Capstone" if int(t.tier) == 3 else ("Technique" if t.has("move") or t.has("moves") else "Passive")
	tv.add_child(_small("%s  ·  Tier %d  ·  %s" % [info.name, int(t.tier) + 1, kind], 14, col.lightened(0.2)))
	# rank pips
	var rank := Game.talent_rank(tid)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 6)
	dv.add_child(pips)
	for i in int(t.max):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(34, 10)
		pip.add_theme_stylebox_override("panel", UiKit.box(UiKit.ACCENT if i < rank else Color(1, 1, 1, 0.1), 4))
		pips.add_child(pip)
	pips.add_child(_small("  Rank %d / %d" % [rank, int(t.max)], 14, UiKit.ACCENT if rank > 0 else UiKit.MUTED))
	dv.add_child(UiKit.label(t.desc, 18))
	if t.has("move") and Game.style != "" and t.move in Rpg.STYLES[Game.style].signature:
		dv.add_child(_small("You already know this from your style. It still counts toward deeper tiers.", 14, UiKit.MUTED, true))
	var why := ""
	var ok := false
	if rank >= int(t.max):
		why = "Maxed out."
		ok = true
	elif not Game.talent_unlocked(tid):
		why = "Locked: spend %d points in %s (you have %d)." % [Rpg.TIER_REQ[int(t.tier)], info.name, Game.tree_points(t.tree)]
	elif Game.talent_points() <= 0:
		why = "No talent points. Next one at level %d." % _next_tp_level()
	if why != "":
		dv.add_child(_small(why, 15, UiKit.ACCENT if ok else Color(1.0, 0.55, 0.45), true))
	else:
		var lb := UiKit.button("Learn  ·  1 point", Vector2(0, 54))
		lb.add_theme_stylebox_override("normal", UiKit.box(Color(0.15, 0.45, 0.25), 12, Color(0.4, 1.0, 0.55), 2))
		lb.add_theme_stylebox_override("hover", UiKit.box(Color(0.2, 0.58, 0.32), 12, Color.WHITE, 2))
		lb.pressed.connect(func():
			hud._sel_talent = tid
			Game.learn(tid))
		dv.add_child(lb)
