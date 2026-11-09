class_name CombatHud
extends Control
## WoW-style combat UI for WorldCombat: player bars (Composure / Gas / Grip pips) under the unit
## frame, a target frame with its cast bar and auras, the action bar (1-0, Q R F) with cooldown
## sweeps, GCD, out-of-range / no-gas tints and tooltips, the player's cast bar and red error text.

const TYPE_COL := {"handfight": Color(0.78, 0.78, 0.74), "takedown": Color(0.95, 0.45, 0.25), "sweep": Color(0.35, 0.8, 0.5),
	"pass": Color(0.95, 0.75, 0.25), "advance": Color(0.95, 0.6, 0.2), "back": Color(0.6, 0.45, 0.95), "sub": Color(0.95, 0.25, 0.3),
	"escape": Color(0.4, 0.85, 1.0), "guard": Color(0.55, 0.7, 0.95), "defend": Color(0.98, 0.6, 0.2)}
const TYPE_GLYPH := {"handfight": "link", "takedown": "down", "sweep": "loop", "pass": "chevron", "advance": "chevron",
	"back": "loop", "sub": "bolt", "escape": "wave", "guard": "shield", "defend": "shield"}
const ID_ICON := {"base": ["down", Color(1.0, 0.6, 0.2)], "frame": ["chevron", Color(0.4, 0.7, 1.0)], "defend": ["lock", Color(1.0, 0.35, 0.35)],
	"breathe": ["wave", Color(0.45, 0.85, 1.0)], "racial": ["star", Color(0.45, 1.0, 0.55)], "spec": ["star", Color(0.75, 0.5, 1.0)]}
const HP_COL := Color(0.2, 0.75, 0.25)

## [glyph, colour] for an ability's icon.
static func icon_of(a: Dictionary) -> Array:
	var id := str(a.get("id", ""))
	if ID_ICON.has(id):
		return ID_ICON[id]
	var t := str(a.get("type", ""))
	return [TYPE_GLYPH.get(t, "star"), TYPE_COL.get(t, Color(0.8, 0.8, 0.8))]
const GAS_COL := Color(1.0, 0.82, 0.15)

var combat: WorldCombat
var _slots: Array = []
var _tip: Control
var _err: Label
var _flash: Label
var _flash_sub: Label
var _flash_t := 0.0
var _card_root: VBoxContainer
var _cards: Array = []

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	# action bar: 10 numbered + 3 utility buttons, bottom centre
	var bar := HBoxContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -14
	bar.add_theme_constant_override("separation", 3)
	bar.name = "ActionBar"
	add_child(bar)
	for i in 15:
		if i == 10:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(10, 0)
			bar.add_child(gap)
		var b := BarSlot.new()
		b.hud = self
		b.slot = i
		b.custom_minimum_size = Vector2(44, 44)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		var idx := i
		b.pressed.connect(func(): _press(idx))
		b.mouse_entered.connect(func(): _show_tip(idx, b))
		b.mouse_exited.connect(_hide_tip)
		b.draw.connect(func(): _draw_slot(b, idx))
		bar.add_child(b)
		_slots.append(b)
	# "New technique" cards: bottom-right, above the bags, out of the way of the fight
	_card_root = VBoxContainer.new()
	_card_root.anchor_left = 1.0
	_card_root.anchor_right = 1.0
	_card_root.anchor_top = 1.0
	_card_root.anchor_bottom = 1.0
	_card_root.offset_left = -372
	_card_root.offset_right = -14
	_card_root.offset_bottom = -104
	_card_root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card_root.alignment = BoxContainer.ALIGNMENT_END
	_card_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_root)
	_err = Wow.title("", 22, Color(1, 0.2, 0.15))
	_err.anchor_left = 0.5
	_err.anchor_right = 0.5
	_err.offset_left = -300
	_err.offset_right = 300
	_err.offset_top = 96
	_err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_err.add_theme_constant_override("outline_size", 6)
	add_child(_err)
	_flash = Wow.title("", 64, Color(1, 0.3, 0.25))
	_flash.set_anchors_preset(Control.PRESET_CENTER)
	_flash.offset_left = -400
	_flash.offset_right = 400
	_flash.offset_top = -120
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.add_theme_constant_override("outline_size", 10)
	add_child(_flash)
	_flash_sub = Wow.label("", 20, Wow.WHITE, false, HORIZONTAL_ALIGNMENT_CENTER)
	_flash_sub.set_anchors_preset(Control.PRESET_CENTER)
	_flash_sub.offset_left = -400
	_flash_sub.offset_right = 400
	_flash_sub.offset_top = -40
	_flash_sub.add_theme_constant_override("outline_size", 6)
	add_child(_flash_sub)

func flash(head: String, sub: String) -> void:
	_flash.text = head
	_flash_sub.text = sub
	_flash_t = 3.5

## Slot i: 0-9 = the customizable bar (Game.bar_layout), 10-13 = Base / Frame / Breathe / racial.
func slot_id(i: int) -> String:
	if i < 10:
		return str(Game.bar_layout[i]) if i < Game.bar_layout.size() else ""
	return str(Abilities.UTILITY[i - 10])

func slot_key(i: int) -> String:
	return Abilities.KEYS[i] if i < 10 else str(Abilities.UTILITY_KEYS[Abilities.UTILITY[i - 10]])

func _ability(i: int) -> Dictionary:
	if combat == null or combat.me == null:
		return {}
	var id := slot_id(i)
	return combat.core.ability(combat.me, id) if id != "" else {}

func _press(i: int) -> void:
	var a := _ability(i)
	if not a.is_empty():
		combat.press(str(a.id))

func _process(delta: float) -> void:
	visible = combat != null and combat.me != null
	if not visible:
		return
	_err.text = combat.error_text if combat.error_t > 0.0 else ""
	_err.modulate.a = clampf(combat.error_t, 0.0, 1.0)
	_flash_t = maxf(0.0, _flash_t - delta)
	_flash.modulate.a = clampf(_flash_t, 0.0, 1.0)
	_flash_sub.modulate.a = _flash.modulate.a
	for b in _slots:
		(b as Control).queue_redraw()
	queue_redraw()

# ------------------------------------------------------------ frames (drawn)
func _bar(pos: Vector2, size: Vector2, frac: float, col: Color, text: String, back := Color(0.05, 0.05, 0.06, 0.9)) -> void:
	draw_rect(Rect2(pos - Vector2(1, 1), size + Vector2(2, 2)), Color(0, 0, 0, 0.9))
	draw_rect(Rect2(pos, size), back)
	draw_rect(Rect2(pos, Vector2(size.x * clampf(frac, 0.0, 1.0), size.y)), col)
	draw_rect(Rect2(pos, Vector2(size.x * clampf(frac, 0.0, 1.0), size.y * 0.4)), Color(1, 1, 1, 0.12))
	if text != "":
		var f := Wow.body()
		var fs := int(size.y * 0.85)
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(f, pos + Vector2((size.x - w) / 2.0, size.y * 0.82), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0))
		draw_string(f, pos + Vector2((size.x - w) / 2.0, size.y * 0.82), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))

func _draw() -> void:
	var me: CombatCore.Unit = combat.me
	# player bars, inside the unit frame plate (top-left; the frame is the HUD's, scaled 0.8)
	var x0 := 76.0
	var bw := 196.0
	_bar(Vector2(x0, 33), Vector2(bw, 13), me.pct(), HP_COL, "%d / %d" % [int(me.hp), int(me.max_hp)])
	_bar(Vector2(x0, 48), Vector2(bw, 7), me.gas / me.max_gas, GAS_COL, "")
	for g in me.max_grip:
		var c := Vector2(x0 + 6 + g * 12, 62)
		draw_circle(c, 4.5, Color(0, 0, 0, 0.85))
		draw_circle(c, 3.3, Color(1, 0.35, 0.2) if g < me.grip else Color(0.2, 0.16, 0.12))
	var f := Wow.title_font()
	if me.grip > 0:
		draw_string_outline(f, Vector2(x0 + 4 + me.max_grip * 12, 66), "GRIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color.BLACK)
		draw_string(f, Vector2(x0 + 4 + me.max_grip * 12, 66), "GRIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.55, 0.35))
	_auras(me, Vector2(x0, 76))
	_party_frames(Vector2(14, 98))
	# player cast bar (above the action bar)
	if not me.cast.is_empty():
		var w := 300.0
		var p := Vector2((size.x - w) / 2.0, size.y - 120)
		_bar(p, Vector2(w, 16), float(me.cast.t) / float(me.cast.dur), Color(1, 0.75, 0.2), str(me.cast.ab.name))
	# target frame
	var t: CombatCore.Unit = combat.target
	if t == null:
		return
	var tp := Vector2(300, 12)
	var plate := Wow.sb(Color(0.03, 0.03, 0.05, 0.85), Color(1, 0.82, 0.3, 0.9) if t.elite else Color(Wow.FRAME, 0.9), 4, 0, 2 if t.elite else 1)
	draw_style_box(plate, Rect2(tp, Vector2(270, 74)))
	var nm := "%s" % t.name
	var lvl := "%d%s" % [t.level, "+" if t.elite else ""]
	var ncol := Data.con_color(t.level, Game.player_level())
	draw_string_outline(f, tp + Vector2(10, 22), nm, HORIZONTAL_ALIGNMENT_LEFT, 200, 16, 4, Color.BLACK)
	draw_string(f, tp + Vector2(10, 22), nm, HORIZONTAL_ALIGNMENT_LEFT, 200, 16, Wow.GOLD if not t.dead else Color(0.6, 0.6, 0.6))
	draw_string_outline(f, tp + Vector2(222, 22), lvl, HORIZONTAL_ALIGNMENT_RIGHT, 40, 16, 4, Color.BLACK)
	draw_string(f, tp + Vector2(222, 22), lvl, HORIZONTAL_ALIGNMENT_RIGHT, 40, 16, ncol)
	_bar(tp + Vector2(10, 30), Vector2(250, 20), t.pct(), HP_COL if not t.in_combat else Color(0.85, 0.25, 0.2), "%d%%" % int(round(t.pct() * 100.0)))
	# where the fight is: position, who's on top, and how dominant you are
	var pi: Array = combat.core.pos_info(me, t)
	var dm: int = combat.core.dom(me, t)
	var ptxt := CombatCore.pos_label(str(pi[0]), bool(pi[1])).replace("(top)", "(you on top)").replace("(bottom)", "(you underneath)")
	if dm != 0:
		ptxt += "   %+d" % dm
	var pcol := Color(0.5, 1.0, 0.6) if dm > 0 else (Color(1, 0.5, 0.4) if dm < 0 else Wow.PALE)
	draw_string_outline(Wow.body(), tp + Vector2(12, 66), ptxt, HORIZONTAL_ALIGNMENT_LEFT, 250, 13, 3, Color.BLACK)
	draw_string(Wow.body(), tp + Vector2(12, 66), ptxt, HORIZONTAL_ALIGNMENT_LEFT, 250, 13, pcol)
	if t.elite:
		var tag := ("Boss" if t.data.get("raid", false) else "Rare") if t.boss else "Elite"
		draw_string(Wow.body(), tp + Vector2(222, 66), tag, HORIZONTAL_ALIGNMENT_RIGHT, 40, 11, Color(1, 0.82, 0.3))
	if not t.cast.is_empty():
		var kind := CombatCore.counter_kind(t.cast.ab)
		var kc: Color = {"base": Color(1, 0.6, 0.2), "frame": Color(0.4, 0.75, 1.0), "defend": Color(1, 0.35, 0.35)}[kind]
		_bar(tp + Vector2(10, 82), Vector2(250, 16), float(t.cast.t) / float(t.cast.dur), kc, str(t.cast.ab.name))
		var hint := "%s it!  [%s]" % [CombatCore.KIND_VERB[kind].to_upper(), CombatCore.KIND_KEY[kind]]
		draw_string_outline(Wow.title_font(), tp + Vector2(12, 120), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
		draw_string(Wow.title_font(), tp + Vector2(12, 120), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, kc)
	_auras(t, tp + Vector2(280, 30))

## Raid party: a compact frame per partner under yours (name, role colour, Composure, casting).
func _party_frames(at: Vector2) -> void:
	if combat.raid == null or not is_instance_valid(combat.raid):
		return
	var f := Wow.body()
	var y := at.y
	for n in combat.raid.ally_npcs:
		if not is_instance_valid(n):
			continue
		var u: CombatCore.Unit = combat._unit_of.get(n.get_instance_id())
		var role := str(n.mob.get("role", "dps"))
		var rc: Color = {"tank": Color(0.35, 0.65, 1.0), "heal": Color(0.35, 0.85, 0.78), "dps": Color(1.0, 0.45, 0.35)}.get(role, Color.WHITE)
		draw_rect(Rect2(at.x, y, 196, 30), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(at.x, y, 4, 30), rc)
		var nm := "%s  ·  %s" % [str(n.mob.name), {"tank": "Tank", "heal": "Healer", "dps": "Damage"}.get(role, "")]
		draw_string_outline(f, Vector2(at.x + 9, y + 12), nm, HORIZONTAL_ALIGNMENT_LEFT, 185, 11, 3, Color.BLACK)
		draw_string(f, Vector2(at.x + 9, y + 12), nm, HORIZONTAL_ALIGNMENT_LEFT, 185, 11, Color.WHITE if u else Color(0.6, 0.6, 0.6))
		if u:
			_bar(Vector2(at.x + 8, y + 16), Vector2(184, 10), u.pct(), HP_COL, "")
			if not u.cast.is_empty():
				draw_rect(Rect2(at.x + 8, y + 27, 184.0 * float(u.cast.t) / float(u.cast.dur), 2), Color(1, 0.85, 0.3))
		else:
			draw_string(f, Vector2(at.x + 9, y + 26), "tapped out", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.5, 0.4))
		y += 34

func _auras(u: CombatCore.Unit, at: Vector2) -> void:
	var names := {"down": ["DOWN", Color(1, 0.55, 0.2)], "pinned": ["PIN", Color(0.95, 0.8, 0.3)], "exposed": ["EXP", Color(0.75, 0.55, 1.0)],
		"base": ["BASE", Color(0.98, 0.6, 0.2)], "guarded": ["GRD", Color(0.55, 0.7, 0.95)], "framed": ["FRM", Color(0.4, 0.75, 1.0)],
		"rattled": ["RTL", Color(0.75, 0.3, 0.8)], "lucky": ["LCK", Color(0.4, 1.0, 0.5)], "mate": ["MATE", Color(0.4, 0.85, 0.4)],
		"ginga": ["GNG", Color(0.4, 0.9, 1.0)], "rush": ["RUSH", Color(1.0, 0.45, 0.3)], "game_plan": ["PLAN", Color(0.35, 0.9, 0.8)], "chain": ["CHAIN", Color(1.0, 0.4, 0.55)]}
	var x := 0.0
	for k in u.auras:
		if not names.has(k):
			continue
		var r := Rect2(at + Vector2(x, 0), Vector2(30, 18))
		draw_rect(r, Color(0, 0, 0, 0.85))
		draw_rect(r.grow(-1.5), Color(names[k][1], 0.35))
		draw_string(Wow.body(), r.position + Vector2(2, 13), str(names[k][0]), HORIZONTAL_ALIGNMENT_LEFT, 28, 10, Color.WHITE)
		draw_string(Wow.body(), r.position + Vector2(2, 30), "%d" % ceili(float(u.auras[k].t)), HORIZONTAL_ALIGNMENT_LEFT, 28, 11, Color(1, 1, 0.8))
		x += 34.0

# ------------------------------------------------------------ action buttons
func _draw_slot(b: Button, i: int) -> void:
	var a := _ability(i)
	var r := Rect2(Vector2.ZERO, b.size)
	var me: CombatCore.Unit = combat.me
	if a.is_empty():
		b.draw_rect(r, Color(0.02, 0.02, 0.02, 0.85))
		b.draw_rect(r.grow(-1.5), Color(0.3, 0.24, 0.14, 0.7), false, 1.5)
		b.draw_string(Wow.body(), Vector2(4, 13), slot_key(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5))
		return
	var t := str(a.get("type", "handfight"))
	var st: Array = icon_of(a)
	var col: Color = st[1]
	var inner := r.grow(-4)
	IconArt.draw(b, r, str(st[0]), col, Color(0, 0, 0, 0), false, IconArt.ability_key(a))
	if me.has("chain") and str(a.get("type", "")) == "sub":
		# live submission chain: this button is the next link
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
		b.draw_rect(r.grow(-1.0), Color(1.0, 0.4, 0.55, 0.6 + 0.4 * pulse), false, 3.0)
	var why := combat.core.block_reason(me, a, combat.target if combat.target else null)
	var cd := float(me.cds.get(a.id, 0.0))
	var gcd := me.gcd if bool(a.get("gcd", true)) else 0.0
	# tints: red = out of range / no target, blue = no gas, dark = cooldown
	if why.begins_with("Not from"):
		b.draw_rect(inner, Color(0.05, 0.05, 0.05, 0.72))
	elif why == "Out of range":
		b.draw_rect(inner, Color(0.8, 0.1, 0.1, 0.35))
	elif why == "Not enough gas" or why.begins_with("Needs grip") or why.begins_with("They must"):
		b.draw_rect(inner, Color(0.15, 0.2, 0.6, 0.5))
	var rem := maxf(cd, gcd)
	if rem > 0.0:
		var total := maxf(float(a.get("cd", 0.0)), 1.0) if cd >= gcd else CombatCore.GCD
		var frac := clampf(rem / total, 0.0, 1.0)
		# cooldown wipe (top-down shade, clipped to the button)
		b.draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * frac)), Color(0, 0, 0, 0.62))
		if cd > 1.5:
			var s := str(ceili(cd))
			var f := Wow.title_font()
			var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			b.draw_string_outline(f, Vector2((b.size.x - w) / 2.0, 36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color.BLACK)
			b.draw_string(f, Vector2((b.size.x - w) / 2.0, 36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 0.85))
	# finisher / advance ready glow
	if why == "" and (bool(a.get("finisher", false)) and me.grip >= 3 or str(a.get("needs", "")) == "control"):
		b.draw_rect(r.grow(-1), Color(1, 0.85, 0.3, 0.85), false, 2.0)
	var key := slot_key(i)
	b.draw_string_outline(Wow.body(), Vector2(4, 13), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color.BLACK)
	b.draw_string(Wow.body(), Vector2(4, 13), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.85))

func _show_tip(i: int, b: Control) -> void:
	_hide_tip()
	var a := _ability(i)
	_tip = tooltip_for(a, combat.me if combat else null, i < 10)
	if _tip == null:
		return
	add_child(_tip)
	_place_tip.call_deferred(_tip, b)

## A WoW tooltip panel for an ability (fixed-width wrapped lines).
static func tooltip_for(a: Dictionary, me, on_bar := false) -> Control:
	if a.is_empty():
		return null
	var tv: Array = Wow.tip(280)
	var p: PanelContainer = tv[0]
	p.z_index = 200
	var core = null
	var tg = null
	if me != null and Engine.get_main_loop() != null:
		var wc = (Engine.get_main_loop() as SceneTree).root.find_child("WorldCombat", true, false)
		if wc:
			core = wc.core
			tg = wc.target
	for ln in Abilities.tip_lines(a, me, core, tg):
		var l := Wow.tline(tv[1], str(ln[0]), ln[1], int(ln[2]), true)
		l.custom_minimum_size = Vector2(280, 0)
	if on_bar:
		var h := Wow.tline(tv[1], "Drag to move · right-click to clear", Wow.GREY, 11)
		h.custom_minimum_size = Vector2(280, 0)
	return p

func _place_tip(t: Control, b: Control) -> void:
	if not is_instance_valid(t) or not is_instance_valid(b):
		return
	t.reset_size()
	var gp := b.global_position
	var vp := get_viewport_rect().size
	t.global_position = Vector2(clampf(gp.x - t.size.x / 2.0 + 25, 8, vp.x - t.size.x - 8), maxf(8.0, gp.y - t.size.y - 10))

func _hide_tip() -> void:
	if _tip:
		_tip.queue_free()
		_tip = null

# ------------------------------------------------------------ "New technique" tutorial cards
var _card_queue: Array = []

func learned(a: Dictionary) -> void:
	_card_queue.append(a)
	if _card_root.get_child_count() == 0:
		_next_card()

func _next_card() -> void:
	if _card_queue.is_empty() or not is_inside_tree():
		return
	var a: Dictionary = _card_queue.pop_front()
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Wow.sb(Color(0.04, 0.035, 0.03, 0.94), Wow.GOLD, 4, 12, 2))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var st: Array = icon_of(a)
	var ikey := IconArt.ability_key(a)
	icon.draw.connect(func():
		IconArt.draw(icon, Rect2(Vector2.ZERO, icon.size), str(st[0]), st[1], Wow.GOLD, false, ikey))
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(Wow.title("NEW TECHNIQUE", 11, Wow.GREEN))
	var slot := Game.bar_layout.find(str(a.id))
	var key: String = Abilities.KEYS[slot] if slot >= 0 else str(Abilities.UTILITY_KEYS.get(str(a.id), ""))
	var nm := Wow.title("%s%s" % [str(a.name), ("  [%s]" % key) if key != "" else "  (Moves book, P)"], 15, Wow.WHITE)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(250, 0)
	v.add_child(nm)
	var body := Wow.label(str(Abilities.TUTORIAL.get(str(a.id), a.get("text", ""))), 12, Wow.PALE, true)
	body.custom_minimum_size = Vector2(250, 0)
	v.add_child(body)
	var ok := Wow.button("Got it", Vector2(70, 22))
	ok.add_theme_font_size_override("font_size", 12)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(func():
		p.queue_free()
		_next_card.call_deferred())
	v.add_child(ok)
	_card_root.add_child(p)
	Sfx.play("levelup", -10.0)
	var tw := p.create_tween()
	p.modulate.a = 0.0
	tw.tween_property(p, "modulate:a", 1.0, 0.3)
	tw.tween_interval(9.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.queue_free()
			_next_card.call_deferred())

## An action-bar button: click / key to use, drag to rearrange, drop spellbook entries on it.
class BarSlot extends Button:
	var hud: CombatHud
	var slot := 0
	func _get_drag_data(_at: Vector2) -> Variant:
		var id := hud.slot_id(slot)
		if id == "" or slot >= 10:
			return null
		var prev := Label.new()
		prev.text = str(hud._ability(slot).get("name", id))
		prev.add_theme_font_override("font", Wow.title_font())
		prev.add_theme_font_size_override("font_size", 16)
		set_drag_preview(prev)
		return {"ability": id, "from_slot": slot}
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return slot < 10 and data is Dictionary and data.has("ability") and not str(data.ability) in Abilities.UTILITY
	func _drop_data(_at: Vector2, data: Variant) -> void:
		Game.bar_set(slot, str(data.ability))
	func _notification(what: int) -> void:
		# dragged off the bar onto nothing: take it off (WoW)
		if what == NOTIFICATION_DRAG_END and is_instance_valid(hud) and not get_viewport().gui_is_drag_successful():
			var d = get_viewport().gui_get_drag_data()
			if d is Dictionary and int(d.get("from_slot", -1)) == slot:
				Game.bar_set(slot, "")
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT and slot < 10:
			Game.bar_set(slot, "")
			accept_event()
