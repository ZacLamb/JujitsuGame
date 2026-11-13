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

var bar: HFlowContainer
const BAR_W := 15 * 44 + 15 * 3 + 10   # one row: 10 moves, a gap, 5 counters
const BAR_W2 := 10 * 44 + 10 * 3 + 10   # two rows: the 10 moves (+gap), then the counters

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	# action bar: 10 numbered + 3 utility buttons, bottom centre
	bar = HFlowContainer.new()   # wraps to two rows on narrow (portrait) screens; Hud.apply_layout sizes it
	bar.alignment = FlowContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("v_separation", 3)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -14
	bar.add_theme_constant_override("h_separation", 3)
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
	_build_read()

## The read: one big, clickable / tappable call in the middle of the screen. When an enemy
## attempts a technique you can counter it says which key (SPRAWL! [Q]); when your opponent is
## worn down it says finish it (SUBMIT! [3]). Everything a new player needs, in one place.
var _read_btn: Button
var _read_kind := ""
var _read_frac := 0.0
var _read_col := Color.WHITE
var _read_t := 0.0
const READ_COL := {"base": Color(1, 0.6, 0.2), "frame": Color(0.4, 0.75, 1.0), "defend": Color(1, 0.35, 0.35), "sub": Color(0.45, 1.0, 0.5),
	"squeeze": Color(0.45, 1.0, 0.5), "escape": Color(1, 0.35, 0.35)}

func _build_read() -> void:
	_read_btn = Button.new()
	_read_btn.focus_mode = Control.FOCUS_NONE
	_read_btn.anchor_left = 0.5
	_read_btn.anchor_right = 0.5
	_read_btn.anchor_top = 0.5
	_read_btn.anchor_bottom = 0.5
	_read_btn.offset_left = -190
	_read_btn.offset_right = 190
	_read_btn.offset_top = -235   # upper middle: clear of the two bodies
	_read_btn.offset_bottom = -165
	_read_btn.add_theme_font_override("font", Wow.title_font())
	_read_btn.add_theme_font_size_override("font_size", 34)
	_read_btn.add_theme_constant_override("outline_size", 8)
	_read_btn.add_theme_color_override("font_outline_color", Color.BLACK)
	_read_btn.visible = false
	_read_btn.pressed.connect(func():
		if _read_kind in ["squeeze", "escape"]:
			combat.press("sub")
		elif _read_kind != "":
			combat.press(_read_kind))
	add_child(_read_btn)

## Key label for an ability id wherever it sits (utility keys, or its slot on the bar).
func _key_for(id: String) -> String:
	if id in Abilities.UTILITY:
		return Keys.label("ab_" + id)
	var i := Game.bar_layout.find(id)
	return Keys.label("ab_%d" % i) if i >= 0 else "?"

## Beginner hints: a soft pulse on the one or two buttons that make sense right now (from where
## you are in the fight). On until level 15; Esc > Controls turns them off (or on for good).
var _hints: Array = []
const HINT_UNTIL := 15

func _hints_on() -> bool:
	var pref = Sfx.pref("hints", null)
	if pref != null:
		return bool(pref)
	return Game.player_level() < HINT_UNTIL

func _usable(id: String, t: CombatCore.Unit) -> bool:
	var a := combat.core.ability(combat.me, id)
	if a.is_empty():
		return false
	var why := combat.core.block_reason(combat.me, a, t)
	return why == "" or why == "gcd"

func _compute_hints() -> Array:
	var me: CombatCore.Unit = combat.me
	var core: CombatCore = combat.core
	var t: CombatCore.Unit = combat.target
	if not _hints_on() or t == null or t.dead or not t.in_combat or not me.cast.is_empty() or core.in_struggle(me):
		return []
	if t.has("worn"):
		return ["sub"] if _usable("sub", t) else []
	if me.down():
		return ["escape"] if _usable("escape", t) else []
	var pi: Array = core.pos_info(me, t)
	var out: Array = []
	var order: Array
	if str(pi[0]) == "standing":
		order = ["takedown"]
	elif bool(pi[1]):
		order = ["back", "advance", "pass"]
	else:
		order = ["sweep", "escape", "back"]
	for id in order:
		if _usable(id, t):
			out.append(id)
			break
	if me.grip >= 3 and _usable("sub", t):
		out.append("sub")
	if out.is_empty() and _usable("handfight", t):
		out.append("handfight")
	return out

func _update_read(delta: float) -> void:
	_hints = _compute_hints()
	var me: CombatCore.Unit = combat.me
	var core: CombatCore = combat.core
	var kind := ""
	var text := ""
	var frac := 0.0
	if core.in_struggle(me):
		var att: bool = core.struggle.atk == me
		kind = "squeeze" if att else "escape"
		text = (Tx.s("SQUEEZE!") if att else Tx.s("ESCAPE!")) + "  " + Tx.f("mash [%s]", _key_for("sub") if att else _key_for("defend") if not core.ability(me, "defend").is_empty() else _key_for("sub"))
		var m := float(core.struggle.meter)
		frac = m if att else 1.0 - m
	elif me.in_combat and not me.dead:
		var c: CombatCore.Unit = core._caster_at(me)
		var t: CombatCore.Unit = combat.target
		if c != null and not core.ability(me, CombatCore.counter_kind(c.cast.ab)).is_empty():
			kind = CombatCore.counter_kind(c.cast.ab)
			text = "%s!  [%s]" % [Tx.s(CombatCore.KIND_VERB[kind]).to_upper(), _key_for(kind)]
			frac = 1.0 - float(c.cast.t) / maxf(0.01, float(c.cast.dur))
		elif t != null and not t.dead and t.has("worn"):
			kind = "sub"
			var why := core.block_reason(me, core.ability(me, "sub"), t)
			if why == "" or why == "gcd" or why == "Busy":
				text = "%s  [%s]" % [Tx.s("SUBMIT!"), _key_for("sub")]
			else:
				text = Tx.s("WORN DOWN: get to a submission!")
				kind = ""
			frac = -1.0
		elif me.has("worn"):
			text = Tx.s("WORN DOWN: escape or defend the finish!")
			frac = -1.0
	_read_t += delta
	_read_btn.visible = text != ""
	if text == "":
		_read_kind = ""
		return
	if _read_kind != kind or _read_btn.text != text:
		_read_kind = kind
		_read_btn.text = text
		_read_col = READ_COL.get(kind, Color(1, 0.45, 0.35))
		var box := Wow.sb(Color(0.04, 0.03, 0.03, 0.88), _read_col, 8, 10, 4)
		for st in ["normal", "hover", "pressed", "disabled"]:
			_read_btn.add_theme_stylebox_override(st, box)
		for st in ["font_color", "font_hover_color", "font_pressed_color"]:
			_read_btn.add_theme_color_override(st, _read_col)
		_read_btn.disabled = kind == ""
		_read_btn.pivot_offset = Vector2(190, 35)
		_read_btn.scale = Vector2(1.18, 1.18)
		_read_btn.create_tween().tween_property(_read_btn, "scale", Vector2.ONE, 0.14)
	_read_frac = frac
	if kind in ["squeeze", "escape"]:
		_read_btn.scale = Vector2.ONE * (1.0 + 0.04 * sin(_read_t * 22.0))
	# worn-down calls pulse
	if frac < 0.0:
		_read_btn.modulate.a = 0.75 + 0.25 * sin(_read_t * 8.0)
	else:
		_read_btn.modulate.a = 1.0

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
	return Keys.label("ab_%d" % i) if i < 10 else Keys.label("ab_" + str(Abilities.UTILITY[i - 10]))

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
	var in_title := false
	var n: Node = get_parent()
	while n != null:
		if "_in_title" in n:
			in_title = bool(n._in_title)
			break
		n = n.get_parent()
	visible = combat != null and combat.me != null and not in_title
	if not visible:
		return
	_update_read(delta)
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
		var w := f.get_string_size(Tx.s(text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(f, pos + Vector2((size.x - w) / 2.0, size.y * 0.82), Tx.s(text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0))
		draw_string(f, pos + Vector2((size.x - w) / 2.0, size.y * 0.82), Tx.s(text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))

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
		draw_string_outline(f, Vector2(x0 + 4 + me.max_grip * 12, 66), Tx.s("GRIP"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color.BLACK)
		draw_string(f, Vector2(x0 + 4 + me.max_grip * 12, 66), Tx.s("GRIP"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.55, 0.35))
	_auras(me, Vector2(x0, 76))
	_party_frames(Vector2(14, 98))
	# the read's timer: how long until their technique lands
	if _read_btn and _read_btn.visible and _read_frac >= 0.0:
		var rr := Rect2(_read_btn.position + Vector2(10, _read_btn.size.y + 4), Vector2(_read_btn.size.x - 20, 8))
		draw_rect(rr.grow(1), Color(0, 0, 0, 0.85))
		draw_rect(Rect2(rr.position, Vector2(rr.size.x * _read_frac, rr.size.y)), _read_col)
	_draw_ladder()
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
	var nm := Tx.f("%s", t.name)
	var lvl := Tx.f("%d%s", [t.level, "+" if t.elite else ""])
	var ncol := Data.con_color(t.level, Game.player_level())
	draw_string_outline(f, tp + Vector2(10, 22), Tx.s(nm), HORIZONTAL_ALIGNMENT_LEFT, 200, 16, 4, Color.BLACK)
	draw_string(f, tp + Vector2(10, 22), Tx.s(nm), HORIZONTAL_ALIGNMENT_LEFT, 200, 16, Wow.GOLD if not t.dead else Color(0.6, 0.6, 0.6))
	draw_string_outline(f, tp + Vector2(222, 22), Tx.s(lvl), HORIZONTAL_ALIGNMENT_RIGHT, 40, 16, 4, Color.BLACK)
	draw_string(f, tp + Vector2(222, 22), Tx.s(lvl), HORIZONTAL_ALIGNMENT_RIGHT, 40, 16, ncol)
	_bar(tp + Vector2(10, 30), Vector2(250, 20), t.pct(), HP_COL if not t.in_combat else Color(0.85, 0.25, 0.2), "%d%%" % int(round(t.pct() * 100.0)))
	# where the fight is: position, who's on top, and how dominant you are
	var pi: Array = combat.core.pos_info(me, t)
	var dm: int = combat.core.dom(me, t)
	var ptxt := CombatCore.pos_label(str(pi[0]), bool(pi[1])).replace("(top)", "(you on top)").replace("(bottom)", "(you underneath)")
	if dm != 0:
		ptxt += "   %+d" % dm
	var pcol := Color(0.5, 1.0, 0.6) if dm > 0 else (Color(1, 0.5, 0.4) if dm < 0 else Wow.PALE)
	draw_string_outline(Wow.body(), tp + Vector2(12, 66), Tx.s(ptxt), HORIZONTAL_ALIGNMENT_LEFT, 250, 13, 3, Color.BLACK)
	draw_string(Wow.body(), tp + Vector2(12, 66), Tx.s(ptxt), HORIZONTAL_ALIGNMENT_LEFT, 250, 13, pcol)
	if t.elite:
		var tag := ("Boss" if t.data.get("raid", false) else "Rare") if t.boss else "Elite"
		draw_string(Wow.body(), tp + Vector2(222, 66), Tx.s(tag), HORIZONTAL_ALIGNMENT_RIGHT, 40, 11, Color(1, 0.82, 0.3))
	if not t.cast.is_empty():
		var kind := CombatCore.counter_kind(t.cast.ab)
		var kc: Color = {"base": Color(1, 0.6, 0.2), "frame": Color(0.4, 0.75, 1.0), "defend": Color(1, 0.35, 0.35)}[kind]
		_bar(tp + Vector2(10, 82), Vector2(250, 16), float(t.cast.t) / float(t.cast.dur), kc, str(t.cast.ab.name))
	_auras(t, tp + Vector2(280, 30))

## The position ladder under the target frame: where the fight is, and who's on top.
const LADDER := ["standing", "guard", "half", "side", "mount", "back"]
func _draw_ladder() -> void:
	var t: CombatCore.Unit = combat.target
	if t == null or t.dead or not t.in_combat:
		return
	var pi: Array = combat.core.pos_info(combat.me, t)
	var here := str(pi[0])
	var top := bool(pi[1])
	var x := 310.0
	var y := 92.0 if t.cast.is_empty() else 116.0
	var f := Wow.body()
	for i in LADDER.size():
		var pos: String = LADDER[i]
		var nm := Tx.s("Standing") if pos == "standing" else Tx.s(str(Data.POSITION_NAMES.get(pos, pos)))
		var w := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10.0
		var on := pos == here
		var col := Wow.GREY
		if on:
			col = Wow.PALE if pos == "standing" else (Color(0.45, 1.0, 0.55) if top else Color(1.0, 0.45, 0.4))
		var r := Rect2(Vector2(x, y), Vector2(w, 16))
		draw_rect(r, Color(0, 0, 0, 0.75 if on else 0.45))
		if on:
			draw_rect(r, col, false, 1.5)
		draw_string(f, Vector2(x + 5, y + 12), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		x += w + 3.0
		if x > 300.0 + 560.0:
			break
	if here != "standing":
		var who := Tx.s("you on top") if top else Tx.s("you underneath")
		draw_string_outline(f, Vector2(x + 4, y + 12), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
		draw_string(f, Vector2(x + 4, y + 12), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 1.0, 0.55) if top else Color(1.0, 0.45, 0.4))

## Party frames under yours: raid / dungeon partners (AI and real), or your party out in the world.
func _party_frames(at: Vector2) -> void:
	var y := at.y
	if combat.raid != null and is_instance_valid(combat.raid):
		for n in combat.raid.ally_npcs:
			if not is_instance_valid(n):
				continue
			var u: CombatCore.Unit = combat._unit_of.get(n.get_instance_id())
			y = _pframe(at.x, y, str(n.mob.name), str(n.mob.get("role", "dps")), u, n.mob.has("remote"))
		return
	var co: Coop = combat.coop
	if co and co.is_guest():
		for id in co._npc:
			var nv = co._npc[id]
			if not is_instance_valid(nv):
				continue
			var n: Npc = nv
			if not n.mob.has("ally"):
				continue
			var u: CombatCore.Unit = co._loc.get(id)
			y = _pframe(at.x, y, str(n.mob.name), str(n.mob.get("role", "dps")), u if u and not u.dead else null, n.has_meta("peer"))
		return
	var pt: Party = co.party if co else null
	if pt == null or not pt.in_party():
		return
	var f := Wow.body()
	for i in pt.others():
		var row: Dictionary = pt.members[i]
		var on := pt.online(i)
		var away := on and str(row.get("zone", "")) != Net.zone
		var rc := Rpg.class_color(str(row.get("style", "")))
		draw_rect(Rect2(at.x, y, 196, 30), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(at.x, y, 4, 30), rc if on else Color(0.4, 0.4, 0.4))
		var nm := "%s%s  ·  %s %d" % ["★ " if i == pt.leader else "", str(row.get("name", "?")), Tx.s("Lv"), int(row.get("level", 1))]
		draw_string_outline(f, Vector2(at.x + 9, y + 12), nm, HORIZONTAL_ALIGNMENT_LEFT, 185, 11, 3, Color.BLACK)
		draw_string(f, Vector2(at.x + 9, y + 12), nm, HORIZONTAL_ALIGNMENT_LEFT, 185, 11, Color.WHITE if on else Color(0.6, 0.6, 0.6))
		if not on:
			draw_string(f, Vector2(at.x + 9, y + 26), Tx.s("offline"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.7))
		elif away:
			var zn := Tx.s(str(Data.ZONES.get(str(row.get("zone", "")), {}).get("name", str(row.get("zone", "?")))))
			draw_string(f, Vector2(at.x + 9, y + 26), zn, HORIZONTAL_ALIGNMENT_LEFT, 185, 11, Color(0.75, 0.75, 0.6))
		else:
			_bar(Vector2(at.x + 8, y + 16), Vector2(184, 10), float(row.get("hp", 1.0)), HP_COL, "")
		y += 34

func _pframe(x: float, y: float, name_: String, role: String, u: CombatCore.Unit, human: bool) -> float:
	var f := Wow.body()
	var rc: Color = {"tank": Color(0.35, 0.65, 1.0), "heal": Color(0.35, 0.85, 0.78), "dps": Color(1.0, 0.45, 0.35)}.get(role, Color.WHITE)
	draw_rect(Rect2(x, y, 196, 30), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x, y, 4, 30), rc)
	var nm := "%s%s  ·  %s" % ["◆ " if human else "", Tx.s(name_), Tx.s({"tank": "Tank", "heal": "Healer", "dps": "Damage"}.get(role, ""))]
	draw_string_outline(f, Vector2(x + 9, y + 12), nm, HORIZONTAL_ALIGNMENT_LEFT, 185, 11, 3, Color.BLACK)
	draw_string(f, Vector2(x + 9, y + 12), nm, HORIZONTAL_ALIGNMENT_LEFT, 185, 11, (Color(0.55, 0.85, 1.0) if human else Color.WHITE) if u else Color(0.6, 0.6, 0.6))
	if u:
		_bar(Vector2(x + 8, y + 16), Vector2(184, 10), u.pct(), HP_COL, "")
		if not u.cast.is_empty():
			draw_rect(Rect2(x + 8, y + 27, 184.0 * float(u.cast.t) / maxf(0.01, float(u.cast.dur)), 2), Color(1, 0.85, 0.3))
	else:
		draw_string(f, Vector2(x + 9, y + 26), Tx.s("tapped out"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.5, 0.4))
	return y + 34

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
			var w := f.get_string_size(Tx.s(s), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			b.draw_string_outline(f, Vector2((b.size.x - w) / 2.0, 36), Tx.s(s), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color.BLACK)
			b.draw_string(f, Vector2((b.size.x - w) / 2.0, 36), Tx.s(s), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 0.85))
	# finisher / advance ready glow
	if why == "" and (bool(a.get("finisher", false)) and me.grip >= 3 or str(a.get("needs", "")) == "control"):
		b.draw_rect(r.grow(-1), Color(1, 0.85, 0.3, 0.85), false, 2.0)
	if str(a.id) in _hints:
		# beginner hint: the button glows and breathes
		var hp := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
		b.draw_rect(inner, Color(0.55, 1.0, 0.6, 0.12 + 0.18 * hp))
		b.draw_rect(r.grow(-1.5), Color(0.55, 1.0, 0.6, 0.65 + 0.35 * hp), false, 3.5)
		b.draw_rect(r.grow(-5.0), Color(1, 1, 1, 0.25 * hp), false, 1.5)
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
	var key: String = Keys.label("ab_%d" % slot) if slot >= 0 else (Keys.label("ab_" + str(a.id)) if str(a.id) in Abilities.UTILITY else "")
	var nm := Wow.title(Tx.f("%s%s", [str(a.name), ("  [%s]" % key) if key != "" else "  (Moves book, P)"]), 15, Wow.WHITE)
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
