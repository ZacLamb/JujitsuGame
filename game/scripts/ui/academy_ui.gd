class_name AcademyPanel
extends PanelContainer
## Academies (player guilds), WoW guild-window style. Not in one: found your own (name, tag,
## motto, R$ 250) or join one from your side of the war. In one: banner, motto, weekly points,
## the roster with who's online, and leader/professor tools. Members get +5% XP and an <ACADEMY>
## tag on their name plate; /a talks to the whole academy. Lives on the server (Cloud).

var _body: VBoxContainer
var _status: Label
var _busy := false
var _sc: ScrollContainer
var _cap := 520.0

func _ready() -> void:
	theme = Wow.theme()
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	add_theme_stylebox_override("panel", Wow.sb(Wow.BG, Wow.FRAME, 6, 16, 3))
	var vs := get_parent_area_size() if get_parent() else Vector2(1280, 720)
	custom_minimum_size = Vector2(minf(720.0, vs.x - 32.0), 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Wow.title("ACADEMY", 28, Wow.GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Wow.button("✕", Vector2(40, 34))
	x.pressed.connect(queue_free)
	head.add_child(x)
	_status = Wow.label("", 14, Wow.PALE, true)
	v.add_child(_status)
	var sc := ScrollContainer.new()
	_sc = sc
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cap = minf(560.0, vs.y - 200.0)
	sc.custom_minimum_size = Vector2(0, 60)
	v.add_child(sc)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	sc.add_child(_body)
	if not Cloud.logged_in():
		_status.text = Tx.s("Academies live on the server. Log in from the title screen to found or join one.")
		return
	Cloud.academy_changed.connect(_draw)
	_status.text = Tx.s("Loading...")
	if Game.academy.is_empty():
		Cloud.academy_call("", {}, _after)
	else:
		Cloud.academy_call("me", {}, _after)   # refreshes your name/level on the roster too

func _after(code: int, d: Dictionary) -> void:
	_busy = false
	if not is_instance_valid(self):
		return
	if code != 200:
		_status.text = str(d.get("error", Tx.s("Couldn't reach the server.")))
		_status.add_theme_color_override("font_color", Wow.RED)
		if code == 0 or Cloud.academy_view.is_empty():
			return
	else:
		_status.text = ""
	_draw()

func _call(action: String, body := {}) -> void:
	if _busy:
		return
	_busy = true
	_status.remove_theme_color_override("font_color")
	_status.text = Tx.s("Working...")
	Cloud.academy_call(action, body, _after)

func _clear() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()

func _draw() -> void:
	if not is_instance_valid(_body):
		return
	_clear()
	var d := Cloud.academy_view
	if d.is_empty():
		return
	var mine = d.get("mine")
	if mine is Dictionary:
		_draw_mine(mine, d)
	else:
		_draw_none(d)
	_draw_top(d)
	_fit.call_deferred()

## The list area is as tall as its content, up to the screen's room, then it scrolls.
func _fit() -> void:
	if is_instance_valid(_sc) and is_instance_valid(_body):
		_sc.custom_minimum_size.y = minf(_body.get_combined_minimum_size().y + 4.0, _cap)

# ------------------------------------------------------------ not in an academy
func _draw_none(d: Dictionary) -> void:
	_body.add_child(Wow.label(Tx.s("Train with a crew. Members get +5% XP, an <ACADEMY> tag over their name, academy chat (/a) and a shared weekly score from the faction war."), 15, Wow.WHITE, true))
	_body.add_child(Wow.banner("Found an academy"))
	var cost := int(d.get("cost", 250))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 6)
	_body.add_child(g)
	var name_e := _field(g, "Name", "Gracie Pantanal", 28)
	var tag_e := _field(g, "Tag", "GPT", 4)
	var motto_e := _field(g, "Motto", "Position before submission.", 60)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_body.add_child(row)
	var found := Wow.button(Tx.f("Found it (R$ %d)", cost), Vector2(220, 38))
	found.disabled = Game.money < cost
	row.add_child(found)
	if Game.money < cost:
		row.add_child(Wow.label(Tx.f("You have R$ %d.", Game.money), 14, Wow.RED))
	found.pressed.connect(func():
		if Game.money < cost:
			return
		_busy = true
		_status.text = Tx.s("Working...")
		Cloud.academy_call("create", {"name": name_e.text.strip_edges(), "tag": tag_e.text.strip_edges(), "motto": motto_e.text.strip_edges()}, func(code: int, r: Dictionary):
			if code == 200:
				Game.add_money(-cost)
				Game.toast.emit(Tx.f("You founded %s. Oss!", str(Game.academy.get("name", ""))), Wow.GOLD)
				Sfx.play("levelup")
			_after(code, r)))
	_body.add_child(Wow.banner("Join one"))
	var any := false
	for a in d.get("top", []):
		if str(a.faction) != Game.faction():
			continue
		any = true
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var l := Wow.label("<%s> %s" % [a.tag, a.name], 16, Wow.GREEN)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		r.add_child(l)
		r.add_child(Wow.label(Tx.f("%d members · %d pts", [int(a.members), int(a.points)]), 14, Wow.GREY))
		var j := Wow.button("Join", Vector2(80, 30))
		var aid := int(a.id)
		j.pressed.connect(func(): _call("join", {"id": aid}))
		r.add_child(j)
		_body.add_child(r)
	if not any:
		_body.add_child(Wow.label(Tx.s("No academies on your side yet. Found the first one!"), 14, Wow.GREY))

func _field(g: GridContainer, label: String, hint: String, maxlen: int) -> LineEdit:
	g.add_child(Wow.label(label, 15, Wow.PALE))
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.max_length = maxlen
	e.custom_minimum_size = Vector2(0, 32)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.focus_entered.connect(func(): CombatLog.typing = true)   # WASD doesn't walk while typing
	e.focus_exited.connect(func(): CombatLog.typing = false)
	g.add_child(e)
	return e

# ------------------------------------------------------------ your academy
const RANK_NAMES := {"leader": "Leader", "professor": "Professor", "student": "Student"}

func _draw_mine(m: Dictionary, d: Dictionary) -> void:
	var t := Wow.title("<%s>  %s" % [m.tag, m.name], 24, Wow.GREEN)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(t)
	if str(m.motto) != "":
		_body.add_child(Wow.label("\"%s\"" % m.motto, 15, Wow.PALE, true, HORIZONTAL_ALIGNMENT_CENTER))
	var place := 0
	var top: Array = d.get("top", [])
	for i in top.size():
		if int(top[i].id) == int(m.id):
			place = i + 1
	var members: Array = m.members
	var on := 0
	for x in members:
		if x.online:
			on += 1
	var line := Tx.f("This week: %d points", int(m.points)) + ((" · " + Tx.f("#%d of all academies", place)) if place > 0 else "") + " · " + Tx.f("%d / %d online", [on, members.size()])
	_body.add_child(Wow.label(line, 14, Wow.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER))
	_body.add_child(Wow.label(Tx.s("Perk: +5% XP from everything. Talk to everyone with /a."), 13, Wow.GREEN, true, HORIZONTAL_ALIGNMENT_CENTER))
	_body.add_child(Wow.banner("Roster"))
	var my_rank := str(m.my_rank)
	var me := int(m.me)
	for x in members:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var dot := Wow.label("●", 14, Wow.GREEN if x.online else Wow.GREY)
		r.add_child(dot)
		var nm := Wow.label(str(x.name), 15, Rpg.class_color(str(x.style)) if x.online else Wow.GREY)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		r.add_child(nm)
		r.add_child(Wow.label(Tx.f("Lv %d", int(x.level)), 14, Wow.PALE))
		var rk := Wow.label(Tx.s(RANK_NAMES.get(str(x.rank), "Student")), 14, Wow.GOLD if x.rank == "leader" else Wow.WHITE)
		rk.custom_minimum_size = Vector2(84, 0)
		r.add_child(rk)
		var xid := int(x.id)
		if xid != me:
			if my_rank == "leader":
				_small(r, "Demote" if x.rank == "professor" else "Professor", func(): _call("rank", {"id": xid, "op": "student" if x.rank == "professor" else "professor"}))
				_small(r, "Lead", func(): _confirm(Tx.f("Make %s the leader? You become a professor.", str(x.name)), func(): _call("rank", {"id": xid, "op": "leader"})))
			if my_rank == "leader" or (my_rank == "professor" and x.rank == "student"):
				_small(r, "Remove", func(): _confirm(Tx.f("Remove %s from the academy?", str(x.name)), func(): _call("rank", {"id": xid, "op": "kick"})))
		_body.add_child(r)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(row)
	if my_rank == "leader":
		var me_e := LineEdit.new()
		me_e.placeholder_text = Tx.s("New motto")
		me_e.max_length = 60
		me_e.custom_minimum_size = Vector2(220, 34)
		me_e.focus_entered.connect(func(): CombatLog.typing = true)
		me_e.focus_exited.connect(func(): CombatLog.typing = false)
		row.add_child(me_e)
		var mb := Wow.button("Set motto", Vector2(110, 34))
		mb.pressed.connect(func(): _call("motto", {"motto": me_e.text.strip_edges()}))
		row.add_child(mb)
	var leave := Wow.button("Leave academy", Vector2(150, 34))
	var warn := Tx.s("Leave your academy?") + ("\n" + Tx.s("You're the leader: it passes to your longest-serving professor (or closes if you're the last one).") if my_rank == "leader" else "")
	leave.pressed.connect(func(): _confirm(warn, func(): _call("leave")))
	row.add_child(leave)

func _small(r: HBoxContainer, text: String, cb: Callable) -> void:
	var b := Wow.button(text, Vector2(0, 26))
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	r.add_child(b)

func _confirm(text: String, yes: Callable) -> void:
	_clear()
	_body.add_child(Wow.label(text, 16, Wow.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)
	var y := Wow.button("Yes", Vector2(120, 36))
	y.pressed.connect(yes)
	row.add_child(y)
	var n := Wow.button("Cancel", Vector2(120, 36))
	n.pressed.connect(_draw)
	row.add_child(n)
	_fit.call_deferred()

# ------------------------------------------------------------ leaderboard
func _draw_top(d: Dictionary) -> void:
	var top: Array = d.get("top", [])
	if top.is_empty():
		return
	_body.add_child(Wow.banner("Top academies this week"))
	for i in mini(top.size(), 10):
		var a: Dictionary = top[i]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		r.add_child(Wow.label("%d." % (i + 1), 14, Wow.GOLD))
		var fac := Origins.faction(str(a.faction))
		var l := Wow.label("<%s> %s" % [a.tag, a.name], 15, Color(0.55, 0.8, 1.0) if str(a.faction) == Game.faction() else Color(1.0, 0.45, 0.4))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		r.add_child(l)
		r.add_child(Wow.label("%s · %s" % [str(fac.name), Tx.f("%d pts", int(a.points))], 13, Wow.GREY))
		_body.add_child(r)
