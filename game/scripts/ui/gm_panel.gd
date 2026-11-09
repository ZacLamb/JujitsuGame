class_name GmPanel
extends PanelContainer
## Game Master window (Ctrl+G or /gm). Only opens when the server has confirmed this account is a
## GM (Net.gm, from the role in the database). Live-world actions (players, kick, mute, reports,
## announcements, watch, invisible) all go through the server, which checks the role again; the
## test tools only change your own local character.

var main   # main.gd
var _tabs: TabContainer
var _players: VBoxContainer
var _reports: VBoxContainer
var _announce: LineEdit
var _status: Label

func _init() -> void:
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -380
	offset_right = 380
	offset_top = -280
	offset_bottom = 280
	add_theme_stylebox_override("panel", Wow.sb(Color(0.03, 0.05, 0.09, 0.96), Color(0.3, 0.6, 1.0), 4, 12, 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Wow.label("GAME MASTER", 22, Color(0.45, 0.75, 1.0))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Wow.button("Close", Vector2(80, 28))
	x.pressed.connect(func(): visible = false)
	head.add_child(x)
	_status = Wow.label("", 12, Wow.GREY)
	v.add_child(_status)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	_build_live()
	_build_growth()
	_build_reports()
	_build_tools()
	Net.gm_data.connect(_on_gm_data)

func _scroll(n: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = n
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 5)
	sc.add_child(v)
	return v

func _row(parent: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	return h

func _btn(parent: Control, text: String, cb: Callable, w := 0.0) -> Button:
	var b := Wow.button(text, Vector2(w, 28))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

# ------------------------------------------------------------ growth (the lead magnet)
var _growth: Label

func _build_growth() -> void:
	var v := _scroll("Growth")
	_btn(_row(v), "Refresh", _load_growth)
	_growth = Wow.label("Press Refresh.", 16, Wow.WHITE)
	_growth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_growth)
	var help := Wow.label("Railway variables: COMMUNITY_URL / COMMUNITY_LABEL (the in-game community button) and SIGNUP_WEBHOOK_URL (every new account is sent there, e.g. a GHL inbound webhook).", 13, Wow.GREY)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)

func _load_growth() -> void:
	_growth.text = "Loading..."
	Cloud._req(HTTPClient.METHOD_GET, "/api/stats", null, func(code: int, d: Dictionary):
		if code != 200:
			_growth.text = str(d.get("error", "Couldn't load (%d)." % code))
			return
		var opt := 0 if int(d.players) == 0 else int(round(100.0 * int(d.optin) / int(d.players)))
		_growth.text = "Accounts: %d   (last 24h: %d · last 7 days: %d)\nOpted in to emails: %d  (%d%%)\nAccounts with characters saved: %d\nOnline now: %d\nCommunity button: %s" % [
			int(d.players), int(d.last24), int(d.last7), int(d.optin), opt, int(d.saves), int(d.online), Cloud.community_url if Cloud.community_url != "" else "not set (COMMUNITY_URL)"])

# ------------------------------------------------------------ live world
func _build_live() -> void:
	var v := _scroll("Live World")
	var r := _row(v)
	_btn(r, "Refresh players", func(): Net.send_gm("list"))
	var watch := CheckButton.new()
	watch.text = "Watch all chat"
	watch.toggled.connect(func(on): Net.send_gm("watch", {"on": on}))
	r.add_child(watch)
	var inv := CheckButton.new()
	inv.text = "Invisible"
	inv.toggled.connect(func(on): Net.send_gm("invisible", {"on": on}))
	r.add_child(inv)
	var ar := _row(v)
	_announce = LineEdit.new()
	_announce.placeholder_text = "Server-wide announcement..."
	_announce.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ar.add_child(_announce)
	_btn(ar, "Announce", func():
		if _announce.text.strip_edges() != "":
			Net.send_gm("announce", {"text": _announce.text})
			_announce.text = "")
	v.add_child(Wow.label("Online players", 15, Wow.GOLD))
	_players = VBoxContainer.new()
	_players.add_theme_constant_override("separation", 3)
	v.add_child(_players)

func _fill_players(list: Array) -> void:
	for c in _players.get_children():
		c.queue_free()
	if list.is_empty():
		_players.add_child(Wow.label("Nobody online.", 13, Wow.GREY))
	for p in list:
		var r := _row(_players)
		var tag := "%s%s  ·  Lv %d %s  ·  %s (%d, %d)%s%s" % ["[GM] " if p.get("gm", false) else "", str(p.name), int(p.level),
			Rpg.class_name_of(str(p.style)), Data.ZONES.get(str(p.zone), {}).get("name", str(p.zone)), int(p.x), int(p.z),
			"  ·  fighting" if int(p.get("combat", 0)) else "", "  ·  MUTED" if p.get("muted", false) else ""]
		var l := Wow.label(tag, 13, Rpg.class_color(str(p.style)))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		var id := int(p.id)
		_btn(r, "Go to", func(): Net.send_gm("goto", {"target": id}))
		_btn(r, "Mute 10m", func(): Net.send_gm("mute", {"target": id, "minutes": 10}); Net.send_gm("list"))
		_btn(r, "Unmute", func(): Net.send_gm("mute", {"target": id, "minutes": 0}); Net.send_gm("list"))
		_btn(r, "Kick", func(): Net.send_gm("kick", {"target": id, "reason": "Removed by a Game Master"}); Net.send_gm("list"))

# ------------------------------------------------------------ reports
func _build_reports() -> void:
	var v := _scroll("Reports")
	_btn(_row(v), "Load latest reports", func(): Net.send_gm("reports"))
	_reports = VBoxContainer.new()
	_reports.add_theme_constant_override("separation", 8)
	v.add_child(_reports)

func _fill_reports(list: Array) -> void:
	for c in _reports.get_children():
		c.queue_free()
	if list.is_empty():
		_reports.add_child(Wow.label("No reports.", 13, Wow.GREY))
	for r in list:
		var when := Time.get_datetime_string_from_unix_time(int(r.at)).replace("T", " ")
		_reports.add_child(Wow.label("#%d  %s  ·  reported %s by %s" % [int(r.id), when, str(r.target), str(r.reporter)], 14, Wow.GOLD))
		_reports.add_child(Wow.label("Reason: " + (str(r.reason) if str(r.reason) != "" else "(none given)"), 13, Wow.WHITE, true))
		var ctx := Wow.label(str(r.context) if str(r.context) != "" else "(no recent chat)", 12, Wow.GREY, true)
		ctx.custom_minimum_size = Vector2(700, 0)
		_reports.add_child(ctx)

# ------------------------------------------------------------ test tools (your character only)
func _build_tools() -> void:
	var v := _scroll("Test Tools")
	v.add_child(Wow.label("These change only YOUR character (and its cloud save). Use a test character.", 13, Color(1, 0.6, 0.4), true))
	var r1 := _row(v)
	r1.add_child(Wow.label("Level", 14, Wow.PALE))
	for lv in [1, 10, 20, 30, 40, 50]:
		_btn(r1, str(lv), func(): Game.set_level(lv); _done("Level %d" % lv))
	var r2 := _row(v)
	_btn(r2, "+R$ 1000", func(): Game.money += 1000; _done("+R$ 1000"))
	_btn(r2, "Class tier set", func():
		var st := str(Gear.CLASS_SET.get(Game.style, ""))
		if st != "":
			for pid in Gear.SETS[st].pieces:
				Game.give_item(pid, true)
			_done("Tier set added to your wardrobe"))
	_btn(r2, "Refill chests + daily", func():
		Game.flags.erase("chests")
		Game.daily = {}
		Game.drills_ready = true
		if main and is_instance_valid(main.world) and main.world.chests:
			for id in main.world.chests.chests:
				main.world.chests.refresh(id)
		_done("Chests and daily reset"))
	var r3 := _row(v)
	var god := CheckButton.new()
	god.text = "God mode (no damage)"
	god.toggled.connect(func(on): CombatCore.gm_god = on; _done("God mode " + ("on" if on else "off")))
	r3.add_child(god)
	r3.add_child(Wow.label("Speed", 14, Wow.PALE))
	for k in [1.0, 2.0, 4.0]:
		_btn(r3, "x%d" % int(k), func():
			if main:
				main.player.speed_mult = k
			_done("Speed x%d" % int(k)))
	var r4 := _row(v)
	r4.add_child(Wow.label("Zone", 14, Wow.PALE))
	for z in Data.ZONES:
		var zz: String = z
		_btn(r4, str(Data.ZONES[z].name), func():
			if main:
				main._travel(zz, true)
			_done("Travelled to " + str(Data.ZONES[zz].name)))
	var r5 := _row(v)
	r5.add_child(Wow.label("Time", 14, Wow.PALE))
	for h in [[6.0, "Dawn"], [12.0, "Noon"], [18.0, "Sunset"], [22.0, "Night"]]:
		var hh: float = h[0]
		_btn(r5, str(h[1]), func(): DayNight.hour = hh; _done("Time set to " + str(h[1])))

func _done(what: String) -> void:
	Game.save_game()
	Game.progress_changed.emit()
	if main and main.hud:
		main.hud.refresh()
	_status.text = "Done: " + what

# ------------------------------------------------------------ server replies
func _on_gm_data(kind: String, d: Dictionary) -> void:
	match kind:
		"list":
			_fill_players(d.get("players", []))
		"reports":
			_fill_reports(d.get("reports", []))
		"goto":
			if main == null:
				return
			var z := str(d.get("zone", ""))
			if z != "" and z != main.world.zone and Data.ZONES.has(z):
				main._travel(z, true)
			main.player.teleport(Vector3(float(d.x), float(d.y) + 0.5, float(d.z)) + Vector3(1.5, 0, 1.5), main.player.cam_yaw)
			_status.text = "Teleported to %s" % str(d.get("name", "?"))

func toggle() -> void:
	if not Net.gm:
		Game.toast.emit("Game Master tools: log in with a GM account (and be connected to the live world).", Wow.GREY)
		return
	visible = not visible
	if visible:
		Net.send_gm("list")
		_status.text = "Signed in as a Game Master · %d online" % Net.online
