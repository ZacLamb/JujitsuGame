class_name CombatLog
extends PanelContainer
## WoW-style chat frame, bottom-left: XP, loot, quest updates, fight results and other chatter
## scroll here instead of popping up in the middle of the screen. The background is faint until
## you hover it; old lines fade but stay in the scrollback.

const MAX_LINES := 80
var _text: RichTextLabel
var _hover := false
var _idle := 0.0

func _init() -> void:
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 10
	offset_right = 270
	offset_top = -168
	offset_bottom = -14
	mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.32)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	var tab := Wow.label("General  ·  Combat & Loot", 11, Wow.GOLD)
	v.add_child(tab)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_following = true
	_text.fit_content = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.mouse_filter = Control.MOUSE_FILTER_PASS
	_text.add_theme_font_size_override("normal_font_size", 12)
	_text.add_theme_constant_override("outline_size", 3)
	_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	if Wow.body():
		_text.add_theme_font_override("normal_font", Wow.body())
	v.add_child(_text)
	mouse_entered.connect(func(): _hover = true)
	mouse_exited.connect(func(): _hover = false)

func add(text: String, color := Color.WHITE) -> void:
	_text.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text.replace("[", "(").replace("]", ")")])
	if _text.get_paragraph_count() > MAX_LINES:
		_text.remove_paragraph(0)
	_idle = 0.0

func _process(delta: float) -> void:
	_idle += delta
	# like WoW's chat: bright while active or hovered, fades out when nothing new happens
	var target := 1.0 if (_hover or _idle < 15.0) else 0.7
	modulate.a = lerpf(modulate.a, target, clampf(delta * 3.0, 0, 1))
