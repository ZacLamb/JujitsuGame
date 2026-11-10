class_name Wow
extends RefCounted
## WoW-style window chrome, theme and tooltip building blocks: dark framed windows with a centred
## title bar, red close button, a round class emblem breaking the top-left corner and tabs that
## hang under the bottom edge; ornate section banners ("Attributes"); compact label/value rows;
## navy tooltips with gold flavour text. Serif type (Marcellus / Cinzel, both OFL).

const GOLD := Color(1.0, 0.82, 0.0)           # WoW's yellow text
const PALE := Color(1.0, 0.93, 0.72)          # stat labels
const WHITE := Color(0.96, 0.96, 0.94)
const GREEN := Color(0.12, 1.0, 0.12)
const GREY := Color(0.55, 0.55, 0.55)
const RED := Color(1.0, 0.13, 0.13)
const FRAME := Color(0.48, 0.36, 0.2)         # carved wood / bronze trim
const FRAME_HI := Color(0.78, 0.6, 0.32)
const BG := Color(0.06, 0.05, 0.06, 0.97)
const INSET := Color(0.03, 0.03, 0.04, 0.85)
const TIP_BG := Color(0.02, 0.03, 0.1, 0.93)
const TIP_EDGE := Color(0.62, 0.62, 0.68, 0.95)
const PARCH := Color(0.86, 0.76, 0.56)
const INK := Color(0.24, 0.15, 0.06)

static var _body: Font
static var _title: Font
static var _theme: Theme

static func body() -> Font:
	if _body == null and ResourceLoader.exists("res://assets/fonts/marcellus.woff2"):
		_body = UiKit.with_symbols(load("res://assets/fonts/marcellus.woff2"))
	return _body

static func title_font() -> Font:
	if _title == null and ResourceLoader.exists("res://assets/fonts/cinzel_bold.woff2"):
		_title = UiKit.with_symbols(load("res://assets/fonts/cinzel_bold.woff2"))
	return _title

## Theme for everything inside a WoW window: serif text, small sizes, bronze buttons.
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 15
	if body():
		t.default_font = body()
	t.set_color("font_color", "Label", WHITE)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "Label", 3)
	t.set_stylebox("normal", "Button", button_box(Color(0.42, 0.06, 0.05), FRAME))
	t.set_stylebox("hover", "Button", button_box(Color(0.55, 0.09, 0.07), FRAME_HI))
	t.set_stylebox("pressed", "Button", button_box(Color(0.3, 0.04, 0.03), FRAME_HI))
	t.set_stylebox("disabled", "Button", button_box(Color(0.16, 0.12, 0.11), Color(FRAME, 0.4)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", GOLD)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.6))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", GREY)
	t.set_font_size("font_size", "Button", 14)
	t.set_stylebox("panel", "PanelContainer", sb(INSET, Color(FRAME, 0.5), 4, 8))
	t.set_stylebox("background", "ProgressBar", sb(Color(0, 0, 0, 0.7), Color(FRAME, 0.6), 2, 0))
	t.set_stylebox("fill", "ProgressBar", sb(Color(0.1, 0.6, 0.1), Color(0, 0, 0, 0), 2, 0))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	for k in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		t.set_stylebox(k, "CheckButton", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckButton", WHITE)
	t.set_color("font_hover_color", "CheckButton", GOLD)
	t.set_color("font_pressed_color", "CheckButton", WHITE)
	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	_theme = t
	return t

static func sb(bg: Color, border := Color(0, 0, 0, 0), radius := 4, pad := 8, bw := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s

static func button_box(bg: Color, edge: Color) -> StyleBoxFlat:
	var s := sb(bg, edge, 3, 12, 1)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 2
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

static func tip_box(edge := TIP_EDGE) -> StyleBoxFlat:
	var s := sb(TIP_BG, edge, 4, 10, 1)
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 6
	return s

static func label(text: String, size := 15, color := WHITE, wrap := false, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = Tx.disp(text)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if body():
		l.add_theme_font_override("font", body())
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func title(text: String, size := 16, color := GOLD) -> Label:
	var l := label(text, size, color)
	if title_font():
		l.add_theme_font_override("font", title_font())
	return l

static func button(text: String, min_size := Vector2(0, 26)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	if body():
		b.add_theme_font_override("font", body())
	b.add_theme_font_size_override("font_size", 14)
	for k in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(k, theme().get_stylebox(k, "Button"))
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.6))
	b.add_theme_color_override("font_disabled_color", GREY)
	return b

## Ornate section banner ("Item Level", "Attributes", "Enhancements").
class Banner extends Control:
	var text := ""
	func _init(t := "") -> void:
		text = t
		custom_minimum_size = Vector2(0, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := Rect2(Vector2(6, 3), size - Vector2(12, 6))
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.1, 0.08, 0.07, 0.95)
		bg.border_color = Wow.FRAME
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(3)
		draw_style_box(bg, r)
		draw_rect(Rect2(r.position + Vector2(3, 3), r.size - Vector2(6, 6)), Color(Wow.FRAME_HI, 0.25), false, 1.0)
		for sx in [-1.0, 1.0]:   # little end caps
			var cx: float = size.x * 0.5 + sx * (size.x * 0.5 - 6)
			var pts := PackedVector2Array([Vector2(cx, size.y * 0.5 - 7), Vector2(cx + sx * 6, size.y * 0.5), Vector2(cx, size.y * 0.5 + 7)])
			draw_colored_polygon(pts, Wow.FRAME_HI)
		var f: Font = Wow.body() if Wow.body() else ThemeDB.fallback_font
		var fs := 15
		var tt := Tx.s(text)
		var w := f.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(f, Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.35), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.35), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wow.WHITE)

static func banner(text: String) -> Control:
	return Banner.new(text)

## "Agility:          2,644" rows.
static func stat_row(l: String, value: String, vcol := WHITE, tip := "") -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var a := label(l, 14, PALE)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	var b := label(value, 14, vcol, false, HORIZONTAL_ALIGNMENT_RIGHT)
	h.add_child(b)
	if tip != "":
		h.tooltip_text = tip
		h.mouse_filter = Control.MOUSE_FILTER_PASS
	return h

## Tooltip helpers: tip() returns [panel, vbox].
static func tip(width := 300.0, edge := TIP_EDGE) -> Array:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", tip_box(edge))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.custom_minimum_size = Vector2(width, 0)
	p.add_child(v)
	return [p, v]

static func tline(v: Control, text: String, color := WHITE, size := 14, wrap := false) -> Label:
	var l := label(text, size, color, wrap)
	l.add_theme_constant_override("outline_size", 2)
	v.add_child(l)
	return l

static func tpair(v: Control, a: String, b: String, color := WHITE) -> void:
	var h := HBoxContainer.new()
	var la := label(a, 14, color)
	la.add_theme_constant_override("outline_size", 2)
	la.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(la)
	var lb := label(b, 14, color, false, HORIZONTAL_ALIGNMENT_RIGHT)
	lb.add_theme_constant_override("outline_size", 2)
	h.add_child(lb)
	v.add_child(h)

static func tgap(v: Control, h := 5) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(c)

# ------------------------------------------------------------------------- window
## A framed window: title bar, close button, emblem, body, tabs hanging off the bottom.
class Frame extends Control:
	signal close_pressed
	signal tab_pressed(i: int)
	var frame: PanelContainer
	var body: MarginContainer
	var title_lbl: Label
	var tabs_row: HBoxContainer
	var emblem_glyph := "shield"
	var emblem_col := Wow.GOLD
	var _emblem: Control
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		theme = Wow.theme()
		frame = PanelContainer.new()
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.offset_bottom = -30
		var fs := Wow.sb(Wow.BG, Wow.FRAME, 6, 0, 3)
		fs.shadow_color = Color(0, 0, 0, 0.6)
		fs.shadow_size = 14
		frame.add_theme_stylebox_override("panel", fs)
		add_child(frame)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		frame.add_child(col)
		# title bar
		var bar := PanelContainer.new()
		var bs := Wow.sb(Color(0.13, 0.1, 0.09), Wow.FRAME, 4, 0, 1)
		bs.border_width_top = 0
		bs.border_width_left = 0
		bs.border_width_right = 0
		bar.add_theme_stylebox_override("panel", bs)
		bar.custom_minimum_size = Vector2(0, 30)
		col.add_child(bar)
		var bh := HBoxContainer.new()
		bar.add_child(bh)
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(70, 0)
		bh.add_child(sp)
		title_lbl = Wow.label("", 15, Wow.WHITE, false, HORIZONTAL_ALIGNMENT_CENTER)
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bh.add_child(title_lbl)
		var x := Button.new()
		x.text = "✕"
		x.focus_mode = Control.FOCUS_NONE
		x.custom_minimum_size = Vector2(26, 24)
		x.add_theme_font_size_override("font_size", 13)
		x.add_theme_color_override("font_color", Color(1, 0.85, 0.6))
		x.add_theme_stylebox_override("normal", Wow.button_box(Color(0.62, 0.08, 0.05), Wow.FRAME_HI))
		x.add_theme_stylebox_override("hover", Wow.button_box(Color(0.8, 0.12, 0.08), Color(1, 0.85, 0.5)))
		x.add_theme_stylebox_override("pressed", Wow.button_box(Color(0.45, 0.05, 0.03), Wow.FRAME_HI))
		x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		x.pressed.connect(func(): close_pressed.emit())
		bh.add_child(x)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(4, 0)
		bh.add_child(gap)
		body = MarginContainer.new()
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for k in ["left", "right", "top", "bottom"]:
			body.add_theme_constant_override("margin_" + k, 10)
		col.add_child(body)
		tabs_row = HBoxContainer.new()
		tabs_row.anchor_top = 1.0
		tabs_row.anchor_bottom = 1.0
		tabs_row.offset_top = -33
		tabs_row.offset_left = 24
		tabs_row.add_theme_constant_override("separation", 2)
		add_child(tabs_row)
		_emblem = Emblem.new()
		_emblem.position = Vector2(-16, -16)
		add_child(_emblem)
	func set_emblem(glyph: String, col: Color) -> void:
		(_emblem as Emblem).glyph = glyph
		(_emblem as Emblem).col = col
		_emblem.queue_redraw()
	func set_tabs(names: Array, current: int) -> void:
		for c in tabs_row.get_children():
			c.queue_free()
		for i in names.size():
			var b := Button.new()
			b.text = str(names[i])
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 14)
			if Wow.body():
				b.add_theme_font_override("font", Wow.body())
			var on := i == current
			var s := Wow.sb(Color(0.16, 0.12, 0.1) if on else Color(0.08, 0.06, 0.06), Wow.FRAME_HI if on else Wow.FRAME, 4, 14, 2 if on else 1)
			s.border_width_top = 0
			s.corner_radius_top_left = 0
			s.corner_radius_top_right = 0
			s.content_margin_top = 8 if on else 4
			s.content_margin_bottom = 6
			for k in ["normal", "hover", "pressed"]:
				b.add_theme_stylebox_override(k, s)
			b.add_theme_color_override("font_color", Wow.GOLD if on else Color(0.85, 0.75, 0.5))
			b.add_theme_color_override("font_hover_color", Wow.WHITE)
			var ix: int = i
			b.pressed.connect(func(): tab_pressed.emit(ix))
			tabs_row.add_child(b)

## Round class emblem breaking the top-left corner (like WoW's portrait ring).
class Emblem extends Control:
	var glyph := "shield"
	var key := ""   # painted icon (IconArt); falls back to the glyph
	var col := Wow.GOLD
	func _init() -> void:
		custom_minimum_size = Vector2(62, 62)
		size = Vector2(62, 62)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, 31, Color(0, 0, 0, 0.6))
		draw_circle(c, 29, Wow.FRAME)
		draw_circle(c, 25, Color(0.05, 0.08, 0.14))
		draw_arc(c, 29, 0, TAU, 48, Wow.FRAME_HI, 2.0, true)
		var painted := IconArt.tex(key)
		if painted != null:
			IconArt.draw_in_poly(self, IconArt.circle(c, 25.5), painted)
			draw_arc(c, 25.5, 0, TAU, 48, Color(0, 0, 0, 0.7), 1.5, true)
		else:
			draw_arc(c, 24.5, 0, TAU, 48, Color(col, 0.7), 1.5, true)
			CharSheet.draw_glyph(self, glyph, c, 30, col)

## Parchment page (spellbook).
static func parchment() -> StyleBoxFlat:
	var s := sb(PARCH, Color(0.45, 0.32, 0.16), 4, 18, 2)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	return s

## Re-skins app-style controls built with UiKit: serif fonts (titles for display type), optional
## size scale, bronze buttons for buttons that don't have their own look.
static func reskin(n: Node, scale := 1.0, buttons := true) -> void:
	if n == null:
		return
	for c in n.find_children("*", "", true, false):
		if c is Label:
			var l := c as Label
			var cur: Font = l.get_theme_font("font") if l.has_theme_font_override("font") else null
			if cur != null and (cur == body() or cur == title_font()):
				continue
			var head := cur != null and cur == UiKit.head_font()
			if scale != 1.0:
				var fs := l.get_theme_font_size("font_size")
				l.add_theme_font_size_override("font_size", maxi(11, roundi(fs * (scale * 0.84 if head else scale))))
			if head and title_font():
				l.add_theme_font_override("font", title_font())
			elif body():
				l.add_theme_font_override("font", body())
		elif c is Button:
			var b := c as Button
			if body():
				b.add_theme_font_override("font", body())
			if scale != 1.0:
				b.add_theme_font_size_override("font_size", maxi(12, roundi(b.get_theme_font_size("font_size") * scale)))
			if buttons and not b.has_theme_stylebox_override("normal") and not (b is CheckButton):
				for k in ["normal", "hover", "pressed", "disabled"]:
					b.add_theme_stylebox_override(k, theme().get_stylebox(k, "Button"))
				b.add_theme_color_override("font_color", GOLD)
