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
	Cloud.changed.connect(_build)

func _build() -> void:
	for c in get_children():
		if c != _panel:
			c.queue_free()
	_account_row()
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

# ------------------------------------------------------------ account
var _panel: PanelContainer = null

func _account_row() -> void:
	if not Cloud.available():
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var nowrap := func(l: Label) -> Label:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		return l
	if Cloud.logged_in():
		row.add_child(nowrap.call(UiKit.label("Signed in as %s" % Cloud.email, 16, Color(0.6, 1.0, 0.65))))
		if Cloud.status != "" and not Cloud.status.begins_with("Logged in"):
			row.add_child(nowrap.call(UiKit.label("·  " + Cloud.status, 14, UiKit.MUTED)))
		var lo := UiKit.button("Log out", Vector2(110, 36))
		lo.pressed.connect(Cloud.logout)
		row.add_child(lo)
	else:
		var b := UiKit.button("Log in / Create account", Vector2(270, 40))
		b.pressed.connect(_open_panel)
		row.add_child(b)
		row.add_child(nowrap.call(UiKit.label(Cloud.status if Cloud.status != "" else "Save your fighters to your account and play on any device.", 14, UiKit.MUTED)))

func _open_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		return
	_panel = PanelContainer.new()
	_panel.top_level = true
	_panel.add_theme_stylebox_override("panel", Wow.sb(Color(0.04, 0.035, 0.03, 0.97), Wow.FRAME, 6, 20, 2))
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(420, 0)
	_panel.add_child(v)
	for l in [UiKit.label("Your Tatame account", 26, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), UiKit.label("Your fighters follow you to any device.", 15, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)]:
		l.custom_minimum_size = Vector2(420, 0)
		v.add_child(l)
	var em := LineEdit.new()
	em.placeholder_text = "Email"
	em.custom_minimum_size = Vector2(0, 42)
	v.add_child(em)
	var pw := LineEdit.new()
	pw.placeholder_text = "Password (8+ characters)"
	pw.secret = true
	pw.custom_minimum_size = Vector2(0, 42)
	v.add_child(pw)
	var err := UiKit.label("", 15, UiKit.RED, HORIZONTAL_ALIGNMENT_CENTER)
	err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	err.custom_minimum_size = Vector2(420, 0)
	v.add_child(err)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var go := func(mode: String):
		err.text = "One moment..."
		err.add_theme_color_override("font_color", UiKit.MUTED)
		Cloud.authenticate(mode, em.text.strip_edges(), pw.text, func(e: String):
			if e == "":
				_close_panel()
			else:
				err.text = e
				err.add_theme_color_override("font_color", UiKit.RED))
	var li := UiKit.button("Log in", Vector2(130, 46))
	li.pressed.connect(func(): go.call("login"))
	row.add_child(li)
	var rg := UiKit.button("Create account", Vector2(170, 46))
	rg.pressed.connect(func(): go.call("register"))
	row.add_child(rg)
	var cx := UiKit.button("Cancel", Vector2(100, 46))
	cx.pressed.connect(_close_panel)
	row.add_child(cx)
	pw.text_submitted.connect(func(_t): go.call("login"))
	_place_panel.call_deferred()
	em.grab_focus()

func _place_panel() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	_panel.size = _panel.get_combined_minimum_size()
	_panel.position = (get_viewport_rect().size - _panel.size) / 2.0

func _close_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

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
