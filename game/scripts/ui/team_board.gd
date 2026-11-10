class_name TeamBoard
extends PanelContainer
## The 5v5 board: both lineups with roles, who is on the mat, carried stamina, the matchup edge and a
## bout feed. Before the first bout you reorder your lineup and pick a coach (the draft); between bouts
## you take the mat yourself or simulate the bout.

signal start_pressed
signal play_pressed
signal sim_pressed
signal forfeit_pressed
signal close_pressed

var m: Team.Match
var state := "lineup"     # lineup / between / done
var result_text := ""
var _body: VBoxContainer

func _init() -> void:
	anchor_left = 0.04
	anchor_right = 0.96
	anchor_top = 0.05
	anchor_bottom = 0.95
	add_theme_stylebox_override("panel", CharSheet._sb(Color(0.03, 0.05, 0.05, 0.96), Color(UiKit.ACCENT, 0.5), 16, 16))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	sc.add_child(_body)

func show_match(match_: Team.Match, st: String) -> void:
	m = match_
	state = st
	visible = true
	rebuild()

func rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	_body.add_child(head)
	var t := CharSheet._head(m.title, 36)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_ring())
	var sub := Tx.f("%s  vs  %s   ·   winner stays on, stamina carries over, a draw eliminates both", [Team.TEAM_NAMES[0], m.academy])
	_body.add_child(CharSheet._small(sub, 15, UiKit.MUTED, true))
	_body.add_child(_side(true))
	_body.add_child(_matchup())
	_body.add_child(_side(false))
	if not m.feed.is_empty():
		var fp := CharSheet._panel(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.06), 10, 10)
		var fv := VBoxContainer.new()
		fv.add_theme_constant_override("separation", 2)
		fp.add_child(fv)
		for e in m.feed.slice(maxi(0, m.feed.size() - 4)):
			fv.add_child(CharSheet._small(str(e[0]), 15, e[1], true))
		_body.add_child(fp)
	_body.add_child(_buttons())

## Role ring legend: Finisher > Grinder > Anchor > Scrambler > Finisher.
func _ring() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for r in ["finisher", "grinder", "anchor", "scrambler", "finisher"]:
		var l := CharSheet._small(Team.ROLES[r].name, 13, Team.ROLES[r].color)
		h.add_child(l)
		h.add_child(CharSheet._small(">", 13, UiKit.MUTED))
	h.remove_child(h.get_child(h.get_child_count() - 1))
	h.tooltip_text = "Each role beats the next one in the ring: a favourable matchup lands techniques more often."
	return h

func _side(ours: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(CharSheet._small((Tx.f("YOUR TEAM  ·  %s", Team.TEAM_NAMES[0])) if ours else (Tx.f("%s", Tx.s(m.academy).to_upper())), 14, UiKit.ACCENT if ours else Color(1, 0.6, 0.5)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var arr: Array = m.ours if ours else m.theirs
	var idx: int = m.i if ours else m.j
	for k in arr.size():
		row.add_child(_card(arr[k], ours, k, idx))
	row.add_child(_coach_card(ours))
	return v

func _card(f: Dictionary, ours: bool, k: int, idx: int) -> Control:
	var role: Dictionary = Team.ROLES[f.role]
	var out := k < idx
	var on := k == idx and not m.over()
	var c: Color = role.color
	var p := CharSheet._panel(Color(c.darkened(0.82), 0.95), c if on else Color(c, 0.35), 12, 8)
	p.custom_minimum_size = Vector2(168, 118)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if on:
		(p.get_theme_stylebox("panel") as StyleBoxFlat).border_width_left = 3
		(p.get_theme_stylebox("panel") as StyleBoxFlat).shadow_color = Color(c, 0.4)
		(p.get_theme_stylebox("panel") as StyleBoxFlat).shadow_size = 8
	p.modulate.a = 0.35 if out else 1.0
	p.tooltip_text = "%s · %s\n%s" % [f.name, role.name, role.desc]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	p.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var badge := _RoleBadge.new()
	badge.role = f.role
	top.add_child(badge)
	var nm := CharSheet._small(str(f.name), 15, UiKit.TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	top.add_child(nm)
	v.add_child(CharSheet._small(Tx.f("%s  ·  Lv %d%s", [role.name, Data.display_level(float(f.level)), "  ·  YOU" if f.get("player", false) else ""]), 12, c.lightened(0.2)))
	if out:
		v.add_child(CharSheet._head("OUT", 24, UiKit.RED))
	elif on:
		var st := m.stam_ours if ours else m.stam_theirs
		var bar := UiKit.bar(UiKit.GREEN if st > 0.3 else UiKit.RED, Vector2(0, 8))
		bar.max_value = 1.0
		bar.step = 0.0
		bar.value = st
		v.add_child(bar)
		v.add_child(CharSheet._small(Tx.f("ON THE MAT  ·  %d%% gas", int(st * 100)), 12, UiKit.ACCENT))
	else:
		v.add_child(CharSheet._small("#%d in line" % (k + 1), 12, UiKit.MUTED))
	if ours and state == "lineup":
		var arrows := HBoxContainer.new()
		arrows.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(arrows)
		for d in [-1, 1]:
			var b := Button.new()
			b.text = "◀" if d < 0 else "▶"
			b.custom_minimum_size = Vector2(36, 26)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 13)
			b.disabled = (k + d) < 0 or (k + d) >= m.ours.size()
			b.pressed.connect(func():
				var tmp: Dictionary = m.ours[k]
				m.ours[k] = m.ours[k + d]
				m.ours[k + d] = tmp
				_save_lineup()
				rebuild())
			arrows.add_child(b)
	return p

func _coach_card(ours: bool) -> Control:
	var c: Dictionary = m.coach if ours else m.their_coach
	var p := CharSheet._panel(Color(0.2, 0.16, 0.05, 0.6), Color(UiKit.ACCENT, 0.45), 12, 8)
	p.custom_minimum_size = Vector2(170, 118)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	v.add_child(CharSheet._small("COACH (corner)", 12, UiKit.ACCENT))
	v.add_child(CharSheet._small(str(c.get("name", "Nobody")), 15, UiKit.TEXT))
	v.add_child(CharSheet._small(Tx.f("+%d gas between bouts", int(Team.coach_heal(c) + Team.BETWEEN_REGEN)), 12, UiKit.MUTED))
	if ours and state == "lineup":
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.add_theme_font_size_override("font_size", 13)
		var ids: Array = [""]
		ob.add_item("No coach")
		var in_lineup := m.ours.map(func(f): return f.id)
		for cc in Team.coaches():
			if cc.id in in_lineup:
				continue
			ids.append(cc.id)
			ob.add_item(Tx.f("%s%s (+%d)", [cc.name, " ★" if cc.get("boss", false) else "", int(Team.coach_heal(cc))]))
			if cc.id == str(m.coach.get("id", "")):
				ob.select(ob.item_count - 1)
		ob.item_selected.connect(func(ix: int):
			m.coach = Team.find(str(ids[ix])) if str(ids[ix]) != "" else {}
			_save_lineup()
			rebuild())
		v.add_child(ob)
	return p

func _matchup() -> Control:
	var p := CharSheet._panel(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.08), 10, 10)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	if m.over():
		var won := m.won()
		h.add_child(CharSheet._head("VICTORY" if won else "DEFEAT", 40, UiKit.ACCENT if won else UiKit.RED))
		if result_text != "":
			h.add_child(CharSheet._small(result_text, 16, UiKit.TEXT, true))
		return p
	var a := m.current_ours()
	var b := m.current_theirs()
	h.add_child(CharSheet._head(Tx.s(str(a.name)).to_upper(), 30, Team.ROLES[a.role].color.lightened(0.2)))
	h.add_child(CharSheet._head("VS", 26, UiKit.MUTED))
	h.add_child(CharSheet._head(Tx.s(str(b.name)).to_upper(), 30, Team.ROLES[b.role].color.lightened(0.2)))
	var e := Team.edge(str(a.role), str(b.role))
	var et := "Even matchup"
	var ec := UiKit.MUTED
	if e > 0:
		et = Tx.f("EDGE: you (%s beats %s)", [Team.ROLES[a.role].name, Team.ROLES[b.role].name])
		ec = Color(0.45, 1.0, 0.55)
	elif e < 0:
		et = Tx.f("EDGE: them (%s beats %s)", [Team.ROLES[b.role].name, Team.ROLES[a.role].name])
		ec = Color(1.0, 0.5, 0.45)
	h.add_child(CharSheet._small(et, 15, ec))
	return p

func _buttons() -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 12)
	match state:
		"lineup":
			h.add_child(_btn("Start the match", start_pressed, UiKit.ACCENT, 260))
			h.add_child(_btn("Not now", close_pressed, UiKit.MUTED, 160))
		"between":
			var a := m.current_ours()
			if a.get("player", false):
				h.add_child(_btn("Take the mat (fight it yourself)", play_pressed, UiKit.ACCENT, 320))
				h.add_child(_btn("Sim this bout", sim_pressed, Color(0.6, 0.85, 1), 200))
			else:
				h.add_child(_btn(Tx.f("Coach %s from the corner", a.name), sim_pressed, UiKit.ACCENT, 320))
			h.add_child(_btn("Forfeit", forfeit_pressed, UiKit.RED, 140))
		"done":
			h.add_child(_btn("Oss", close_pressed, UiKit.ACCENT, 200))
	return h

func _btn(text: String, sig: Signal, col: Color, w: float) -> Button:
	var b := UiKit.button(text, Vector2(w, 54))
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", col)
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(func(): sig.emit())
	return b

func _save_lineup() -> void:
	Game.set_team_lineup(m.ours.map(func(f): return f.id), str(m.coach.get("id", "")))

class _RoleBadge extends Control:
	var role := "anchor"
	func _init() -> void:
		custom_minimum_size = Vector2(26, 26)
	func _draw() -> void:
		var c: Color = Team.ROLES[role].color
		draw_circle(size / 2.0, 12, c.darkened(0.45))
		draw_arc(size / 2.0, 12, 0, TAU, 24, c, 1.5, true)
		CharSheet.draw_glyph(self, Team.ROLES[role].icon, size / 2.0, 14, Color.WHITE)
