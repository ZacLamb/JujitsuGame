class_name TouchControls
extends Control
## Virtual joystick (left half) + camera drag (right half) + action buttons.

signal jump_pressed
signal interact_pressed
signal journal_pressed

var player: Player
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _look_id := -1
var _look_last := Vector2.ZERO
var stick_radius := 80.0
var interact_btn: Button
var jump_btn: Button
var sprint_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	jump_btn = _round_button("JUMP", Vector2(-190, -180), Vector2(120, 120))
	jump_btn.button_down.connect(func(): jump_pressed.emit())
	interact_btn = _round_button("ROLL", Vector2(-340, -160), Vector2(120, 100))
	interact_btn.add_theme_color_override("font_color", UiKit.ACCENT)
	interact_btn.button_down.connect(func(): interact_pressed.emit())
	interact_btn.visible = false
	sprint_btn = _round_button("RUN", Vector2(-175, -310), Vector2(100, 80))
	sprint_btn.toggle_mode = true
	sprint_btn.toggled.connect(func(on): if player: player.touch_sprint = on)

func _round_button(text: String, offset: Vector2, size_v: Vector2) -> Button:
	var b := UiKit.button(text, size_v)
	b.add_theme_stylebox_override("normal", UiKit.box(Color(0, 0, 0, 0.35), int(size_v.y / 2), Color(1, 1, 1, 0.35)))
	b.add_theme_stylebox_override("pressed", UiKit.box(Color(0.3, 0.24, 0.08, 0.7), int(size_v.y / 2), UiKit.ACCENT))
	b.add_theme_stylebox_override("hover", UiKit.box(Color(0, 0, 0, 0.35), int(size_v.y / 2), Color(1, 1, 1, 0.35)))
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = offset.x
	b.offset_top = offset.y
	b.offset_right = offset.x + size_v.x
	b.offset_bottom = offset.y + size_v.y
	add_child(b)
	return b

func _input(event: InputEvent) -> void:
	if not visible or player == null or not player.input_enabled:
		return
	var w := get_viewport_rect().size.x
	if event is InputEventScreenTouch:
		if event.pressed:
			if _over_button(event.position):
				return
			if event.position.x < w * 0.45 and _stick_id == -1:
				_stick_id = event.index
				_stick_origin = event.position
				_stick_vec = Vector2.ZERO
			elif _look_id == -1 and event.position.x >= w * 0.45:
				_look_id = event.index
				_look_last = event.position
		else:
			if event.index == _stick_id:
				_stick_id = -1
				_stick_vec = Vector2.ZERO
				player.touch_move = Vector2.ZERO
			elif event.index == _look_id:
				_look_id = -1
		queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == _stick_id:
			var v: Vector2 = event.position - _stick_origin
			_stick_vec = v.limit_length(stick_radius) / stick_radius
			player.touch_move = _stick_vec
			queue_redraw()
		elif event.index == _look_id:
			player.look((event.position - _look_last) * 0.006)
			_look_last = event.position

func _over_button(p: Vector2) -> bool:
	for b in [jump_btn, interact_btn, sprint_btn]:
		if b.visible and b.get_global_rect().has_point(p):
			return true
	return false

func release_all() -> void:
	_stick_id = -1
	_look_id = -1
	_stick_vec = Vector2.ZERO
	if player:
		player.touch_move = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	if _stick_id == -1:
		return
	draw_circle(_stick_origin, stick_radius, Color(0, 0, 0, 0.25))
	draw_arc(_stick_origin, stick_radius, 0, TAU, 40, Color(1, 1, 1, 0.4), 3.0)
	draw_circle(_stick_origin + _stick_vec * stick_radius, 34, Color(1, 1, 1, 0.55))
