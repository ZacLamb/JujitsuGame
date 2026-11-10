class_name TouchControls
extends Control
## Phone controls, MMO style: floating joystick (left side), camera drag + pinch zoom (right
## side), auto-run, run toggle, jump and a context button (Roll / Talk / Go).

signal jump_pressed
signal interact_pressed
signal journal_pressed

const DEAD_ZONE := 0.14
const LOOK_SPEED := 3.2          # radians per screen-width of drag
var player: Player
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _look_id := -1
var _look_last := Vector2.ZERO
var _pinch_id := -1
var _pinch_last := Vector2.ZERO
var stick_radius := 80.0
var interact_btn: Button
var jump_btn: Button
var sprint_btn: Button
var autorun_btn: Button
var autorun := false
## Raises the thumb buttons and joystick hint (portrait, where the action bar wraps to two rows).
var lift := 0.0:
	set(v):
		var d := v - lift
		lift = v
		for b in [jump_btn, interact_btn, sprint_btn, autorun_btn]:
			if b:
				b.offset_top -= d
				b.offset_bottom -= d
		queue_redraw()

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
	autorun_btn = _round_button("AUTO", Vector2(-300, -290), Vector2(100, 70))
	autorun_btn.toggle_mode = true
	autorun_btn.toggled.connect(set_autorun)

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

## Auto-run: keeps running forward (camera direction) until toggled off or the stick is used.
func set_autorun(on: bool) -> void:
	autorun = on
	if autorun_btn.button_pressed != on:
		autorun_btn.set_pressed_no_signal(on)
	if player:
		player.autorun = on

## Joystick response: dead zone, then a smooth curve so small pushes walk slowly.
static func shape(v: Vector2) -> Vector2:
	var l := v.length()
	if l < DEAD_ZONE:
		return Vector2.ZERO
	var t := (l - DEAD_ZONE) / (1.0 - DEAD_ZONE)
	t = t * t * (3.0 - 2.0 * t) * 0.35 + t * 0.65
	return v / l * clampf(t, 0.0, 1.0)

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
				if autorun:
					set_autorun(false)
			elif event.position.x >= w * 0.45:
				if _look_id == -1:
					_look_id = event.index
					_look_last = event.position
				elif _pinch_id == -1:
					_pinch_id = event.index
					_pinch_last = event.position
		else:
			if event.index == _stick_id:
				_stick_id = -1
				_stick_vec = Vector2.ZERO
				player.touch_move = Vector2.ZERO
			elif event.index == _look_id:
				_look_id = -1
				_pinch_id = -1
			elif event.index == _pinch_id:
				_pinch_id = -1
		queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == _stick_id:
			var v: Vector2 = event.position - _stick_origin
			# the stick follows the thumb so it can never be "lost" off the edge
			if v.length() > stick_radius * 1.25:
				_stick_origin += v.normalized() * (v.length() - stick_radius * 1.25)
				v = event.position - _stick_origin
			_stick_vec = v.limit_length(stick_radius) / stick_radius
			player.touch_move = shape(_stick_vec)
			queue_redraw()
		elif _pinch_id != -1 and (event.index == _look_id or event.index == _pinch_id):
			# two fingers on the right side: pinch to zoom
			var before := _look_last.distance_to(_pinch_last)
			if event.index == _look_id:
				_look_last = event.position
			else:
				_pinch_last = event.position
			var after := _look_last.distance_to(_pinch_last)
			player.zoom((before - after) * 0.02)
		elif event.index == _look_id:
			player.look((event.position - _look_last) * (LOOK_SPEED / maxf(w, 1.0)))
			_look_last = event.position

func _over_button(p: Vector2) -> bool:
	for b in [jump_btn, interact_btn, sprint_btn, autorun_btn]:
		if b.visible and b.get_global_rect().has_point(p):
			return true
	return false

func release_all() -> void:
	_stick_id = -1
	_look_id = -1
	_pinch_id = -1
	_stick_vec = Vector2.ZERO
	if player:
		player.touch_move = Vector2.ZERO
	if autorun:
		set_autorun(false)
	queue_redraw()

func _draw() -> void:
	var size_v := get_viewport_rect().size
	if _stick_id == -1:
		# faint hint where the joystick lives
		var hint := Vector2(size_v.x * 0.16, size_v.y - 150 - lift)
		draw_circle(hint, stick_radius * 0.8, Color(0, 0, 0, 0.12))
		draw_arc(hint, stick_radius * 0.8, 0, TAU, 40, Color(1, 1, 1, 0.18), 2.0)
		draw_circle(hint, 26, Color(1, 1, 1, 0.18))
		return
	draw_circle(_stick_origin, stick_radius, Color(0, 0, 0, 0.25))
	draw_arc(_stick_origin, stick_radius, 0, TAU, 40, Color(1, 1, 1, 0.4), 3.0)
	var run := _stick_vec.length() > 0.92
	draw_circle(_stick_origin + _stick_vec * stick_radius, 34, Color(1, 0.85, 0.3, 0.7) if run else Color(1, 1, 1, 0.55))
