class_name CombatUi
extends RefCounted
## Widgets for the real-time roll: action-bar slots, cast bars and Grip Control pips.
## Everything is drawn in code so it stays crisp at any size and needs no icon art.

const KIND_COLORS := {
	"grip": Color(0.78, 0.78, 0.74), "wear": Color(0.72, 0.5, 0.95), "breathe": Color(0.45, 0.85, 1.0), "disengage": Color(0.85, 0.85, 0.85),
	"base": Color(0.98, 0.6, 0.2), "frame": Color(0.35, 0.65, 1.0), "defend": Color(0.95, 0.3, 0.3),
}
const TYPE_ICONS := {
	"takedown": "down", "sweep": "loop", "pass": "chevron", "advance": "chevron", "back": "loop",
	"escape": "wave", "guard": "shield", "sub": "bolt",
}
const PAD_LABELS := ["A", "B", "X", "Y", "LB+A", "LB+B", "LB+X", "LB+Y"]

static func font() -> Font:
	return UiKit.body_font() if UiKit.body_font() else ThemeDB.fallback_font

## Colour of a bar slot or a cast: what it is answered by.
static func slot_color(id: String, kind: String) -> Color:
	if kind in ["grip", "wear", "breathe", "disengage"]:
		return KIND_COLORS[kind]
	return KIND_COLORS[RollSim.counter_kind(id)]

static func slot_icon(id: String, kind: String) -> String:
	match kind:
		"grip":
			return "link"
		"wear":
			return "down"
		"breathe":
			return "wave"
	return TYPE_ICONS.get(str(Data.MOVES[id].type), "star")

## One action-bar button.
class Slot extends Control:
	signal pressed_slot(id: String)
	var id := ""
	var title := ""
	var kind := "move"
	var key := ""
	var req := 0
	var have := 0
	var cd := 0.0
	var cd_max := 1.0
	var usable := true
	var casting := false
	var signature := false
	var _flash := 0.0
	var _hover := false
	func _init() -> void:
		custom_minimum_size = Vector2(88, 88)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _hover = true)
		mouse_exited.connect(func(): _hover = false)
	func flash() -> void:
		_flash = 1.0
	func _process(delta: float) -> void:
		_flash = maxf(0.0, _flash - delta * 3.0)
		queue_redraw()
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			pressed_slot.emit(id)
			accept_event()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var col := CombatUi.slot_color(id, kind)
		var f := CombatUi.font()
		# glow
		if casting or _flash > 0.0 or (usable and _hover):
			var g := StyleBoxFlat.new()
			g.bg_color = Color(0, 0, 0, 0)
			g.shadow_color = Color(col, 0.55 if casting else 0.35 + 0.4 * _flash)
			g.shadow_size = 12
			g.set_corner_radius_all(14)
			draw_style_box(g, r)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.darkened(0.72), 0.95) if usable else Color(0.08, 0.08, 0.08, 0.9)
		sb.border_color = Color(col, 1.0 if usable else 0.35)
		if signature and usable:
			sb.border_color = UiKit.ACCENT
		sb.set_border_width_all(3 if casting else 2)
		sb.set_corner_radius_all(14)
		draw_style_box(sb, r)
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(1, 1, 1, 0.07)
		sh.corner_radius_top_left = 12
		sh.corner_radius_top_right = 12
		draw_style_box(sh, Rect2(Vector2(2, 2), Vector2(size.x - 4, size.y * 0.4)))
		var icol := Color(1, 1, 1, 0.92) if usable else Color(1, 1, 1, 0.25)
		CharSheet.draw_glyph(self, CombatUi.slot_icon(id, kind), Vector2(size.x / 2.0, size.y * 0.4), size.x * 0.36, icol)
		# name (up to two lines)
		var words := title.split(" ")
		var lines: Array = [""]
		for w in words:
			var t: String = (lines[-1] + " " + w).strip_edges()
			if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x > size.x - 8 and lines[-1] != "":
				lines.append(w)
			else:
				lines[-1] = t
		lines = lines.slice(0, 2)
		var y := size.y - 8.0 - 12.0 * (lines.size() - 1)
		for l in lines:
			draw_string_outline(f, Vector2(0, y), l, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, 3, Color(0, 0, 0, 0.9))
			draw_string(f, Vector2(0, y), l, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(1, 1, 1, 0.95 if usable else 0.4))
			y += 12.0
		# keybind
		var kb := StyleBoxFlat.new()
		kb.bg_color = Color(0, 0, 0, 0.75)
		kb.set_corner_radius_all(6)
		var kw := maxf(20.0, f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 8)
		draw_style_box(kb, Rect2(Vector2(4, 4), Vector2(kw, 18)))
		draw_string(f, Vector2(4, 17), key, HORIZONTAL_ALIGNMENT_CENTER, kw, 12, UiKit.ACCENT)
		# grip requirement pips
		for i in req:
			var c := Vector2(size.x - 10 - i * 11, 12)
			var on := i < have
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)]),
				UiKit.ACCENT if on else Color(1, 1, 1, 0.25))
		# cooldown sweep
		if cd > 0.0:
			var k := clampf(cd / maxf(cd_max, 0.01), 0.0, 1.0)
			var ov := StyleBoxFlat.new()
			ov.bg_color = Color(0, 0, 0, 0.62)
			ov.set_corner_radius_all(14)
			draw_style_box(ov, Rect2(Vector2(0, size.y * (1.0 - k)), Vector2(size.x, size.y * k)))
			if cd > 0.6:
				draw_string_outline(f, Vector2(0, size.y * 0.46), "%.0f" % ceilf(cd), HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, 5, Color(0, 0, 0, 0.9))
				draw_string(f, Vector2(0, size.y * 0.46), "%.0f" % ceilf(cd), HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color.WHITE)

## A cast bar: name, coloured fill, time left. Also used for the opponent's big centre alert.
class CastBar extends Control:
	var title := ""
	var col := Color.WHITE
	var t := 0.0
	var dur := 1.0
	var tag := ""       # e.g. "BASE" on the opponent's alert
	var big := false
	var special := false
	var interrupted := 0.0
	var landed := 0.0
	func _init() -> void:
		custom_minimum_size = Vector2(300, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(delta: float) -> void:
		interrupted = maxf(0.0, interrupted - delta)
		landed = maxf(0.0, landed - delta)
		queue_redraw()
	func _draw() -> void:
		var f := CombatUi.font()
		var r := Rect2(Vector2.ZERO, size)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.72)
		bg.border_color = Color(col, 0.9)
		bg.set_border_width_all(2)
		bg.set_corner_radius_all(8)
		if big:
			bg.shadow_color = Color(col, 0.45)
			bg.shadow_size = 10
		if special:
			bg.border_color = UiKit.ACCENT
			bg.set_border_width_all(4)
			bg.shadow_color = Color(UiKit.ACCENT, 0.4 + 0.3 * sin(Time.get_ticks_msec() / 90.0))
			bg.shadow_size = 18
		draw_style_box(bg, r)
		var k := clampf(t / maxf(dur, 0.01), 0.0, 1.0)
		var fill := StyleBoxFlat.new()
		fill.bg_color = col if interrupted <= 0.0 else Color(0.5, 0.5, 0.5)
		fill.set_corner_radius_all(6)
		draw_style_box(fill, Rect2(Vector2(3, 3), Vector2((size.x - 6) * k, size.y - 6)))
		draw_rect(Rect2(Vector2(3, 3), Vector2((size.x - 6) * k, (size.y - 6) * 0.4)), Color(1, 1, 1, 0.18))
		var fs := 22 if big else 14
		var label := title
		if interrupted > 0.0:
			label = "INTERRUPTED"
		var ty := size.y / 2.0 + fs * 0.36
		var left_pad := 10.0
		if tag != "" and interrupted <= 0.0:
			var tw := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 4).x + 16
			var tb := StyleBoxFlat.new()
			tb.bg_color = col.darkened(0.45)
			tb.border_color = Color.WHITE
			tb.set_border_width_all(1)
			tb.set_corner_radius_all(6)
			draw_style_box(tb, Rect2(Vector2(6, 5), Vector2(tw, size.y - 10)))
			draw_string(f, Vector2(6, ty - 1), tag, HORIZONTAL_ALIGNMENT_CENTER, tw, fs - 4, Color.WHITE)
			left_pad = tw + 14
		draw_string_outline(f, Vector2(left_pad, ty), label, HORIZONTAL_ALIGNMENT_LEFT, size.x - left_pad - 50, fs, 5, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2(left_pad, ty), label, HORIZONTAL_ALIGNMENT_LEFT, size.x - left_pad - 50, fs, Color.WHITE)
		if interrupted <= 0.0:
			var left := maxf(0.0, dur - t)
			draw_string_outline(f, Vector2(0, ty), "%.1f" % left, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 10, fs - 2, 4, Color(0, 0, 0, 0.9))
			draw_string(f, Vector2(0, ty), "%.1f" % left, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 10, fs - 2, Color(1, 1, 1, 0.9))

## Grip Control pips (5 diamonds).
class Pips extends Control:
	var n := 0
	var col := UiKit.ACCENT
	var right_to_left := false
	func _init() -> void:
		custom_minimum_size = Vector2(5 * 22, 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		for i in RollSim.MAX_CONTROL:
			var x := 11.0 + i * 22.0
			if right_to_left:
				x = size.x - 11.0 - i * 22.0
			var c := Vector2(x, size.y / 2.0)
			var on := i < n
			var pts := PackedVector2Array([c + Vector2(0, -9), c + Vector2(8, 0), c + Vector2(0, 9), c + Vector2(-8, 0)])
			draw_colored_polygon(pts, col if on else Color(0, 0, 0, 0.5))
			pts.append(pts[0])
			draw_polyline(pts, Color(col, 0.9) if on else Color(1, 1, 1, 0.25), 1.5, true)
			if on:
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(4, -1), c + Vector2(-4, -1)]), Color(1, 1, 1, 0.5))
