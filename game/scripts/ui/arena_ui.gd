class_name ArenaPanel
extends PanelContainer
## Ranked Arena (H): this week's ladder, your rating, find a match, last week's podium.

signal find_match

var _body: VBoxContainer
var _find: Button

func _init() -> void:
	theme = Wow.theme()
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	add_theme_stylebox_override("panel", Wow.sb(Wow.BG, Wow.FRAME, 6, 14, 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(620, 0)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Wow.title("RANKED ARENA", 22, Wow.GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Wow.button("Close", Vector2(90, 32))
	x.pressed.connect(queue_free)
	head.add_child(x)
	var intro := Wow.label("Weekly ladder. Every match is a real player's build (their shadow, played by the AI), picked near your rating. Win and you climb; they drop a little. Ratings reset every Monday; last week's top players get paid in Honor.", 13, UiKit.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	v.add_child(_body)
	_find = Wow.button("Find a ranked match", Vector2(0, 42))
	_find.pressed.connect(func():
		find_match.emit()
		queue_free())
	v.add_child(_find)
	Cloud.arena_changed.connect(func(): if is_instance_valid(self): refresh())
	refresh()
	if Cloud.logged_in():
		Cloud.arena_board()

func refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
	if not Cloud.logged_in():
		_line("Log in (title screen) to play ranked.", Color(1, 0.6, 0.4))
		_find.disabled = true
		return
	var a: Dictionary = Cloud.arena
	if a.is_empty():
		_line("Loading...", UiKit.MUTED)
		return
	var me = a.get("me")
	if me is Dictionary:
		var played := int(me.wins) + int(me.losses)
		_line(Tx.f("Your rating: %d   ·   %d-%d   ·   %s", [int(me.rating), int(me.wins), int(me.losses),
			(Tx.f("#%d this week", int(me.rank)) if int(me.rank) > 0 else Tx.s("unranked"))]), Wow.GOLD, 17)
		if played < int(a.get("pay_min", 5)):
			_line(Tx.f("Play %d more this week to qualify for the payout.", int(a.get("pay_min", 5)) - played), UiKit.MUTED)
	else:
		_line("You're not on this week's ladder yet: your first match puts you on at 1000.", Wow.PALE)
	_line(Tx.f("This week (%s)", str(a.get("week", ""))), Wow.WHITE, 16)
	var top: Array = a.get("top", [])
	if top.is_empty():
		_line("Nobody yet. Be the first.", UiKit.MUTED)
	for i in top.size():
		var r: Dictionary = top[i]
		var col := Origins.faction(str(r.get("faction", "brasil"))).color as Color
		_line("%2d.  %s   %d   (%d-%d)   %s %d" % [i + 1, str(r.name), int(r.rating), int(r.wins), int(r.losses), Tx.s("Lv"), int(r.get("level", 1))],
			col.lightened(0.35) if i >= 3 else Wow.GOLD)
	var last: Dictionary = a.get("last", {})
	var lt: Array = last.get("top", [])
	if not lt.is_empty():
		var names: Array = []
		for i in lt.size():
			names.append("%s %s (%d)" % [["🥇", "🥈", "🥉"][i], str(lt[i].name), int(lt[i].rating)])
		_line(Tx.f("Last week (%s): %s", [str(last.get("week", "")), "   ".join(names)]), Wow.PALE)
	_line("Weekly payout: #1 1500 Honor and the Arena Champion title · top 3 1000 · top 10 600 · everyone with 5+ matches 250.", UiKit.MUTED, 12)

func _line(t: String, col: Color, size := 14) -> void:
	var l := Wow.label(t, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
