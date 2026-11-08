class_name CircuitBoard
extends PanelContainer
## The Circuito board: the five-match road (next opponent revealed, the final's master shown),
## your stacked coaching cards and carried stamina, and the card draft between matches.

signal card_picked(id: String)
signal fight_pressed
signal quit_pressed
signal close_pressed

var run: Circuit.Run
var state := "draft"    # draft / ready / done
var result_text := ""
var _body: VBoxContainer

func _init() -> void:
	anchor_left = 0.06
	anchor_right = 0.94
	anchor_top = 0.06
	anchor_bottom = 0.94
	add_theme_stylebox_override("panel", CharSheet._sb(Color(0.04, 0.03, 0.06, 0.96), Color(0.7, 0.35, 1.0, 0.55), 16, 16))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	sc.add_child(_body)

func show_run(r: Circuit.Run, st: String) -> void:
	run = r
	state = st
	visible = true
	rebuild()

func rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	_body.add_child(head)
	var t := CharSheet._head("CIRCUITO", 40, Color(0.8, 0.55, 1.0))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var best := int(Game.flags.get("circuit_best", 0))
	head.add_child(CharSheet._small("Best run: %d/%d wins" % [best, Circuit.ROUNDS], 15, UiKit.MUTED))
	_body.add_child(CharSheet._small("Five matches, one life. Stamina carries over. Draft a coaching card before every match; the perks stack.", 15, UiKit.MUTED, true))
	_body.add_child(_road())
	_body.add_child(_status())
	match state:
		"draft":
			_body.add_child(CharSheet._head("CHOOSE A COACHING CARD", 26, UiKit.ACCENT))
			_body.add_child(_cards())
		"ready":
			var o := run.current()
			var nx := CharSheet._head("NEXT: %s  ·  %s" % [Circuit.ROUND_NAMES[run.round].to_upper(), str(o.name).to_upper()], 28, UiKit.TEXT)
			_body.add_child(nx)
			var sub := "%s  ·  Lv %d" % [o.get("academy", ""), Data.display_level(float(o.level))]
			if str(o.get("phases_of", "")) != "":
				sub += "  ·  fights in phases, watch for gold specials"
			_body.add_child(CharSheet._small(sub, 15, Color(1, 0.6, 0.4) if str(o.get("phases_of", "")) != "" else UiKit.MUTED))
		"done":
			_body.add_child(CharSheet._head("CAMPEÃO DO CIRCUITO!" if run.champion() else "RUN OVER", 40, UiKit.ACCENT if run.champion() else UiKit.RED))
			_body.add_child(CharSheet._small(result_text, 17, UiKit.TEXT, true))
	_body.add_child(_buttons())

func _road() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for i in run.ladder.size():
		var o: Dictionary = run.ladder[i]
		var done := i < run.round
		var cur := i == run.round and not run.over()
		var fin := i == run.ladder.size() - 1
		var col := Color(1, 0.6, 0.3) if fin else Color(0.7, 0.35, 1.0)
		var p := CharSheet._panel(Color(col.darkened(0.82), 0.95), col if cur else Color(col, 0.3), 12, 8)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.custom_minimum_size = Vector2(0, 84)
		p.modulate.a = 0.45 if done else 1.0
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		p.add_child(v)
		v.add_child(CharSheet._small(Circuit.ROUND_NAMES[i].to_upper(), 12, col.lightened(0.2)))
		var known := done or cur or fin
		v.add_child(CharSheet._small(str(o.name) if known else "???", 16, UiKit.TEXT))
		if done:
			v.add_child(CharSheet._head("WON", 20, Color(0.45, 1.0, 0.55)))
		elif run.lost and i == run.round:
			v.add_child(CharSheet._head("LOST", 20, UiKit.RED))
		elif known:
			v.add_child(CharSheet._small("Lv %d%s" % [Data.display_level(float(o.level)), "  ★ master" if fin else ""], 12, UiKit.MUTED))
		h.add_child(p)
	return h

func _status() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var sv := VBoxContainer.new()
	sv.custom_minimum_size = Vector2(220, 0)
	sv.add_child(CharSheet._small("STAMINA CARRIED", 12, UiKit.MUTED))
	var bar := UiKit.bar(UiKit.GREEN if run.stamina > 0.35 else UiKit.RED, Vector2(200, 12))
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = run.stamina
	sv.add_child(bar)
	sv.add_child(CharSheet._small("%d%%" % int(run.stamina * 100), 14, UiKit.TEXT))
	h.add_child(sv)
	var pv := VBoxContainer.new()
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.add_child(CharSheet._small("YOUR COACHING CARDS", 12, UiKit.MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	pv.add_child(flow)
	if run.perks.is_empty():
		flow.add_child(CharSheet._small("None yet", 14, UiKit.MUTED))
	for id in run.perks:
		var c: Dictionary = Circuit.CARDS[id]
		var chip := CharSheet._panel(Color(Circuit.RARITY[c.rarity].color, 0.15), Circuit.RARITY[c.rarity].color, 14, 6)
		chip.tooltip_text = c.desc
		chip.add_child(CharSheet._small(c.name, 13, UiKit.TEXT))
		flow.add_child(chip)
	h.add_child(pv)
	return h

func _cards() -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 16)
	for id in run.offers:
		var c: Dictionary = Circuit.CARDS[id]
		var rc: Color = Circuit.RARITY[c.rarity].color
		var b := Button.new()
		b.custom_minimum_size = Vector2(230, 200)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UiKit.box(Color(rc.darkened(0.8), 0.95), 16, rc, 2))
		b.add_theme_stylebox_override("hover", UiKit.box(Color(rc.darkened(0.6), 0.98), 16, Color.WHITE, 3))
		b.add_theme_stylebox_override("pressed", UiKit.box(Color(rc.darkened(0.4), 1.0), 16, Color.WHITE, 3))
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 14
		v.offset_right = -14
		v.offset_top = 12
		v.offset_bottom = -12
		v.add_theme_constant_override("separation", 6)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var ic := _CardIcon.new()
		ic.icon = c.icon
		ic.col = rc
		v.add_child(ic)
		var nm := CharSheet._head(str(c.name).to_upper(), 24, UiKit.TEXT)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nm)
		var rl := CharSheet._small(Circuit.RARITY[c.rarity].name, 12, rc)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rl)
		var d := CharSheet._small(c.desc, 14, UiKit.TEXT, true)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(d)
		for ch in v.get_children():
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cid: String = id
		b.pressed.connect(func(): card_picked.emit(cid))
		h.add_child(b)
	return h

func _buttons() -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 12)
	match state:
		"draft":
			h.add_child(_btn("Walk away (keep XP)", quit_pressed, UiKit.MUTED, 240))
		"ready":
			h.add_child(_btn("Fight!", fight_pressed, UiKit.ACCENT, 260))
			h.add_child(_btn("Walk away (keep XP)", quit_pressed, UiKit.MUTED, 240))
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

class _CardIcon extends Control:
	var icon := "star"
	var col := Color.WHITE
	func _init() -> void:
		custom_minimum_size = Vector2(0, 54)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := Vector2(size.x / 2.0, size.y / 2.0)
		draw_circle(c, 25, col.darkened(0.55))
		draw_arc(c, 25, 0, TAU, 32, col, 2.0, true)
		CharSheet.draw_glyph(self, icon, c, 28, Color.WHITE)
