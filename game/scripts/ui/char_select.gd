class_name CharSelect
extends VBoxContainer
## Title-screen character select: one card per character (name, class, belt, level, zone) with
## Play and Delete, plus "New Character". Every new character starts at white belt, level 1:
## no boosts, no carried-over progress. Picking or creating reloads the scene into that save.

var _confirm_del := ""

func _init() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_theme_constant_override("separation", 10)

func _ready() -> void:
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var chars := Game.characters()
	chars.sort_custom(func(a, b): return int(a.get("played", 0)) > int(b.get("played", 0)))
	if not chars.is_empty():
		add_child(_title("CHOOSE YOUR FIGHTER"))
		var grid := HFlowContainer.new()
		grid.alignment = FlowContainer.ALIGNMENT_CENTER
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		grid.custom_minimum_size = Vector2(980, 0)
		add_child(grid)
		for c in chars:
			grid.add_child(_card(c))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	if Game.can_create():
		var nb := UiKit.button("Start Training" if chars.is_empty() else "+  New Character", Vector2(320 if chars.is_empty() else 280, 64 if chars.is_empty() else 52))
		nb.add_theme_font_size_override("font_size", 28 if chars.is_empty() else 20)
		nb.pressed.connect(func():
			Game.new_character()
			_enter())
		row.add_child(nb)
	else:
		row.add_child(UiKit.label("Character slots full (%d). Delete one to start fresh." % Game.MAX_CHARS, 15, UiKit.MUTED))
	add_child(UiKit.label("Every fighter starts at white belt. Earn every stripe.", 15, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

func _card(c: Dictionary) -> Control:
	var rank := int(c.get("rank", 0))
	var belt: Dictionary = Data.BELTS[Data.belt_of(rank)]
	var bc: Color = belt.color
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(300, 0)
	p.add_theme_stylebox_override("panel", UiKit.box(Color(0.04, 0.05, 0.07, 0.92), 14, Color(UiKit.ACCENT, 0.55) if str(c.id) == Game.char_id else Color(1, 1, 1, 0.15), 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var swatch := ColorRect.new()
	swatch.color = Rpg.GI_COLORS[clampi(int(c.get("gi", 0)), 0, Rpg.GI_COLORS.size() - 1)]
	swatch.custom_minimum_size = Vector2(10, 44)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(swatch)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nv)
	nv.add_child(_l(str(c.get("name", "Gringo")), 24, UiKit.TEXT))
	var st: String = str(c.get("style", ""))
	nv.add_child(_l("%s  ·  Level %d" % [Rpg.STYLES[st].name if Rpg.STYLES.has(st) else "?", int(c.get("level", 1))], 15, UiKit.MUTED))
	# belt bar with stripes
	var belt_row := HBoxContainer.new()
	belt_row.add_theme_constant_override("separation", 8)
	v.add_child(belt_row)
	var bar := ColorRect.new()
	bar.color = bc
	bar.custom_minimum_size = Vector2(120, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	belt_row.add_child(bar)
	var stripes := rank % 5
	belt_row.add_child(_l("%s belt%s" % [belt.name, ("  ·  %d stripe%s" % [stripes, "" if stripes == 1 else "s"]) if stripes > 0 else ""], 14, bc.lightened(0.2) if bc.get_luminance() < 0.3 else bc))
	var zn: String = str(c.get("zone", "caceres"))
	v.add_child(_l(Data.ZONES[zn].name if Data.ZONES.has(zn) else zn, 13, UiKit.MUTED))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	v.add_child(btns)
	var play := UiKit.button("Play", Vector2(150, 44))
	play.add_theme_font_size_override("font_size", 20)
	var cid := str(c.id)
	play.pressed.connect(func():
		Game.select_character(cid)
		_enter())
	btns.add_child(play)
	var del := UiKit.button("Delete?  Tap again" if _confirm_del == cid else "Delete", Vector2(120 if _confirm_del != cid else 170, 44))
	del.add_theme_font_size_override("font_size", 15)
	del.add_theme_color_override("font_color", UiKit.RED)
	del.pressed.connect(func():
		if _confirm_del == cid:
			Game.delete_character(cid)
			_confirm_del = ""
		else:
			_confirm_del = cid
		_build())
	btns.add_child(del)
	return p

func _title(t: String) -> Label:
	return UiKit.label(t, 20, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)

## Reload into the chosen save (the world is built for that character's zone).
func _enter() -> void:
	Game.boot_into = true
	get_tree().reload_current_scene()

static func _l(t: String, size: int, col: Color) -> Label:
	var l := UiKit.label(t, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l
