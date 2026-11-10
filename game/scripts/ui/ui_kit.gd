class_name UiKit
extends RefCounted
## Shared theme + small widget helpers. Built in code so the whole UI stays text-diffable.

const BG := Color(0.06, 0.09, 0.08, 0.86)
const PANEL := Color(0.09, 0.13, 0.11, 0.92)
const ACCENT := Color(0.97, 0.77, 0.28)       # Brazil gold
const GREEN := Color(0.12, 0.62, 0.36)
const RED := Color(0.86, 0.27, 0.24)
const TEXT := Color(0.96, 0.95, 0.9)
const MUTED := Color(0.7, 0.74, 0.7)

static var _theme: Theme
static var _body_font: Font
static var _head_font: Font

## The web build has no system fonts to fall back on, so symbols the text fonts lack (✕ ✓ ★ → ▶)
## would draw as boxes: every font gets a tiny DejaVu subset as its fallback.
static var _symbols: Font
static func with_symbols(f: Font) -> Font:
	if f == null:
		return f
	if _symbols == null and ResourceLoader.exists("res://assets/fonts/symbols.ttf"):
		_symbols = load("res://assets/fonts/symbols.ttf")
	if _symbols and f is FontFile and not (f as FontFile).fallbacks.has(_symbols):
		var fb := (f as FontFile).fallbacks
		fb.append(_symbols)
		(f as FontFile).fallbacks = fb
	return f

static func body_font() -> Font:
	if _body_font == null and ResourceLoader.exists("res://assets/fonts/Nunito-Bold.woff2"):
		_body_font = with_symbols(load("res://assets/fonts/Nunito-Bold.woff2"))
	return _body_font

static func head_font() -> Font:
	if _head_font == null and ResourceLoader.exists("res://assets/fonts/BebasNeue.woff2"):
		_head_font = with_symbols(load("res://assets/fonts/BebasNeue.woff2"))
	return _head_font

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 22
	if body_font():
		t.default_font = body_font()
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 5)
	t.set_stylebox("normal", "Button", box(Color(0.14, 0.2, 0.17, 0.95), 12, Color(1, 1, 1, 0.12)))
	t.set_stylebox("hover", "Button", box(Color(0.19, 0.28, 0.23, 0.98), 12, ACCENT))
	t.set_stylebox("pressed", "Button", box(Color(0.3, 0.24, 0.08, 1.0), 12, ACCENT))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 12, ACCENT))
	t.set_stylebox("disabled", "Button", box(Color(0.1, 0.12, 0.11, 0.7), 12, Color(1, 1, 1, 0.05)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	t.set_font_size("font_size", "Button", 22)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 16, Color(1, 1, 1, 0.08)))
	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.55), 6))
	t.set_stylebox("fill", "ProgressBar", box(GREEN, 6))
	t.set_stylebox("panel", "TabContainer", box(PANEL, 12))
	t.set_stylebox("tab_selected", "TabContainer", box(Color(0.2, 0.28, 0.23), 10, ACCENT))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(0.1, 0.14, 0.12), 10))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(0.16, 0.22, 0.18), 10))
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	_theme = t
	return t

static func box(c: Color, radius := 12, border := Color(0, 0, 0, 0), bw := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

static func label(text: String, size := 22, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = Tx.disp(text)
	l.add_theme_font_size_override("font_size", size)
	if size >= 30 and head_font():
		l.add_theme_font_override("font", head_font())
		l.add_theme_font_size_override("font_size", int(size * 1.18))
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func button(text: String, min_size := Vector2(160, 56)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): Sfx.play("click", -10.0))
	return b

static func bar(color: Color, min_size := Vector2(220, 16)) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = min_size
	p.show_percentage = false
	p.max_value = 100
	p.add_theme_stylebox_override("fill", box(color, 6))
	return p

## A small belt chip with stripes, drawn with panels.
static func belt_chip(rank: int, size := Vector2(120, 22)) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = size
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var belt := Panel.new()
	var bi := Data.belt_of(rank)
	belt.add_theme_stylebox_override("panel", box(Data.BELTS[bi].color, 4, Color(0, 0, 0, 0.6), 1))
	belt.position = Vector2.ZERO
	belt.size = size
	belt.custom_minimum_size = size
	holder.add_child(belt)
	var tip := Panel.new()
	tip.add_theme_stylebox_override("panel", box(Color(0.05, 0.05, 0.05) if bi != 4 else Color(0.75, 0.1, 0.1), 2))
	tip.position = Vector2(size.x * 0.62, 2)
	tip.size = Vector2(size.x * 0.3, size.y - 4)
	tip.custom_minimum_size = tip.size
	holder.add_child(tip)
	for i in Data.stripes_of(rank):
		var s := Panel.new()
		s.add_theme_stylebox_override("panel", box(Color(0.97, 0.97, 0.97), 1))
		s.position = Vector2(size.x * 0.64 + i * (size.x * 0.065), 2)
		s.size = Vector2(size.x * 0.035, size.y - 4)
		s.custom_minimum_size = s.size
		holder.add_child(s)
	return holder

## Natural skin tone from 0 (light) to 1 (dark).
static func skin_tone(t: float) -> Color:
	return Color(0.96, 0.8, 0.68).lerp(Color(0.36, 0.22, 0.14), clampf(t, 0.0, 1.0))

static func open_url(url: String) -> void:
	if url == "":
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open(%s, '_blank')" % JSON.stringify(url))
	else:
		OS.shell_open(url)

## Short vibration on phones that support it (Android browsers; iOS ignores it).
static func buzz(ms := 20) -> void:
	if OS.has_feature("web_android") or OS.has_feature("android"):
		Input.vibrate_handheld(ms)
