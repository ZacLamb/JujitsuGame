class_name StyleSelect
extends Control
## Character creation: name, gi color, fighting style.

signal chosen(style_id: String, player_name: String, gi: int)

var _style := "guard"
var _gi := 0
var _name_edit: LineEdit
var _cards := {}
var _gi_buttons: Array = []
var _detail: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.04, 0.88)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", UiKit.box(Color(0.06, 0.09, 0.08, 0.98), 0, Color(1, 1, 1, 0.1)))
	outer.add_child(bottom)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	bottom.add_child(bar)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	scroll.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)
	v.add_child(UiKit.label("CHOOSE YOUR PATH", 44, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label("Every style can learn everything. Your style decides where you start and what you're best at.", 18, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 18)
	row.add_theme_constant_override("v_separation", 10)
	v.add_child(row)
	var nb := HBoxContainer.new()
	nb.add_theme_constant_override("separation", 8)
	var nl := UiKit.label("Name", 20)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nb.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.text = Game.player_name
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(220, 48)
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.add_theme_stylebox_override("normal", UiKit.box(Color(0, 0, 0, 0.5), 10, Color(1, 1, 1, 0.25)))
	_name_edit.add_theme_stylebox_override("focus", UiKit.box(Color(0, 0, 0, 0.6), 10, UiKit.ACCENT))
	nb.add_child(_name_edit)
	row.add_child(nb)
	var gb := HBoxContainer.new()
	gb.add_theme_constant_override("separation", 8)
	var gl := UiKit.label("Gi", 20)
	gl.autowrap_mode = TextServer.AUTOWRAP_OFF
	gb.add_child(gl)
	for i in Rpg.GI_COLORS.size():
		var b := UiKit.button(Rpg.GI_NAMES[i], Vector2(96, 48))
		b.pressed.connect(_pick_gi.bind(i))
		gb.add_child(b)
		_gi_buttons.append(b)
	row.add_child(gb)

	var grid := HFlowContainer.new()
	grid.alignment = FlowContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	for id in Rpg.STYLE_ORDER:
		var card := _card(id)
		grid.add_child(card)
		_cards[id] = card

	_detail = UiKit.label("", 18, UiKit.TEXT)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_detail)
	var go := UiKit.button("Begin training", Vector2(240, 64))
	go.add_theme_font_size_override("font_size", 24)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func(): chosen.emit(_style, _name_edit.text, _gi))
	bar.add_child(go)
	_pick_style(_style)
	_pick_gi(0)

func _card(id: String) -> Button:
	var st: Dictionary = Rpg.STYLES[id]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(228, 190)
	b.clip_contents = true
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14
	v.offset_right = -14
	v.offset_top = 12
	v.offset_bottom = -12
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	b.add_child(v)
	var t := UiKit.label(st.name, 26, UiKit.ACCENT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var tag := UiKit.label(st.tag, 17, UiKit.MUTED)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tag)
	var parts: Array = []
	for k in Rpg.ATTR_ORDER:
		if st.attrs.has(k):
			parts.append("+%d %s" % [st.attrs[k], Rpg.ATTRS[k].name])
	var a := UiKit.label(", ".join(parts), 17, Color(0.6, 0.9, 1.0))
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(a)
	var sig: Array = []
	for mid in st.signature:
		sig.append(Data.MOVES[mid].name)
	var s := UiKit.label("Signature: " + ", ".join(sig), 17, UiKit.TEXT)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(s)
	b.pressed.connect(_pick_style.bind(id))
	return b

func _pick_style(id: String) -> void:
	_style = id
	for k in _cards:
		var on: bool = k == id
		var c: Button = _cards[k]
		c.add_theme_stylebox_override("normal", UiKit.box(Color(0.22, 0.2, 0.08, 0.95) if on else Color(0.1, 0.14, 0.12, 0.95), 14, UiKit.ACCENT if on else Color(1, 1, 1, 0.12), 3 if on else 2))
		c.add_theme_stylebox_override("hover", c.get_theme_stylebox("normal"))
	var st: Dictionary = Rpg.STYLES[id]
	_detail.text = "%s — %s\n%s" % [st.name, st.desc, st.passive]
	_pick_gi(Rpg.GI_COLORS.find(st.gi) if _gi == 0 else _gi)

func _pick_gi(i: int) -> void:
	_gi = maxi(i, 0)
	for j in _gi_buttons.size():
		var b: Button = _gi_buttons[j]
		b.add_theme_stylebox_override("normal", UiKit.box(Rpg.GI_COLORS[j].darkened(0.55), 10, UiKit.ACCENT if j == _gi else Color(1, 1, 1, 0.15), 3 if j == _gi else 2))
