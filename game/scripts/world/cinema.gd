class_name Cinema
extends Node
## Small in-engine cutscenes: letterbox bars, a free camera that eases between shots, a title card
## and subtitles. Used for the opening, boss entrances and belt promotions.
## Any key / click / tap after the first second skips to the end (await steps return immediately).

signal finished

var cam: Camera3D
var layer: CanvasLayer
var _top: ColorRect
var _bot: ColorRect
var _title: Label
var _kicker: Label
var _sub: Label
var _hint: Label
var _flash: ColorRect
var skipped := false
var active := false
var _t := 0.0
var _host: Node3D
var _restore: Callable
var skippable := true

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## host: a Node3D in the world to hold the camera. restore: called when the scene ends.
func begin(host: Node3D, restore: Callable, fov := 50.0) -> void:
	_host = host
	_restore = restore
	active = true
	skipped = false
	_t = 0.0
	cam = Camera3D.new()
	cam.fov = fov
	cam.far = 400
	host.add_child(cam)
	layer = CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)
	_top = ColorRect.new()
	_bot = ColorRect.new()
	for b in [_top, _bot]:
		b.color = Color.BLACK
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(b)
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var bar := _bar_h()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_top, "offset_bottom", bar, 0.5).from(0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bot, "offset_top", -bar, 0.5).from(0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_kicker = _label(18, Color(1.0, 0.82, 0.45))
	_title = _label(64, Color.WHITE)
	_sub = _label(24, Color(1, 0.97, 0.9))
	_sub.add_theme_font_override("font", Wow.body())
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = _label(13, Color(1, 1, 1, 0.55))
	_hint.text = Tx.s("Press any key to skip")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.modulate.a = 0.0
	_layout()
	get_viewport().size_changed.connect(_layout)
	cam.make_current()

func _bar_h() -> float:
	var vs := get_viewport().get_visible_rect().size
	return clampf(vs.y * 0.11, 34.0, 90.0)

func _label(px: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", Wow.title_font())
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", maxi(4, px / 6))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	layer.add_child(l)
	return l

func _layout() -> void:
	if layer == null or not is_instance_valid(_title):
		return
	var vs := get_viewport().get_visible_rect().size
	var bar := _bar_h()
	var narrow := vs.x < 700.0
	_title.add_theme_font_size_override("font_size", 38 if narrow else 64)
	_sub.add_theme_font_size_override("font_size", 17 if narrow else 24)
	var w := vs.x - 32.0
	_kicker.position = Vector2(16, bar + vs.y * 0.035)
	_kicker.size = Vector2(w, 26)
	_title.position = Vector2(16, bar + vs.y * 0.035 + 22)
	_title.size = Vector2(w, 80)
	_sub.position = Vector2(16 + w * (0.02 if narrow else 0.12), vs.y - bar - (96 if narrow else 84))
	_sub.size = Vector2(w * (0.96 if narrow else 0.76), 80)
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hint.position = Vector2(16, vs.y - bar + 8)
	_hint.size = Vector2(w, 20)

func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	if skippable and _t > 1.0 and is_instance_valid(_hint) and _hint.modulate.a < 0.5:
		_hint.modulate.a = 1.0

func _input(event: InputEvent) -> void:
	if not active:
		return
	var press: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed) or (event is InputEventJoypadButton and event.pressed)
	if press:
		get_viewport().set_input_as_handled()
		if skippable and _t > 1.0:
			skipped = true

## Wait (returns at once when skipped). Use between beats.
func wait(secs: float) -> void:
	var t := 0.0
	while t < secs and not skipped and active:
		await get_tree().process_frame
		t += get_process_delta_time()

## Keep walls and pillars out of the shot: if something stands between the subject and the camera,
## the camera moves in front of it.
func _clear(from: Vector3, look: Vector3) -> Vector3:
	if _host == null or not _host.is_inside_tree():
		return from
	var q := PhysicsRayQueryParameters3D.create(look, from)
	q.collide_with_areas = false
	var hit := _host.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return from
	var d: float = look.distance_to(hit.position)
	if d < 0.9:
		return from          # the subject's own collider, or no room at all
	return look + (from - look).normalized() * maxf(0.9, d - 0.35)

## Cut to a shot.
func cut(from: Vector3, look: Vector3) -> void:
	if cam == null:
		return
	from = _clear(from, look)
	cam.global_position = from
	if from.distance_to(look) > 0.05:
		cam.look_at(look, Vector3.UP)

## Ease the camera to a new position / target over secs (does not wait: follow with wait()).
func move(from: Vector3, look: Vector3, secs: float) -> void:
	if cam == null or skipped:
		cut(from, look)
		return
	from = _clear(from, look)
	var end := Transform3D(Basis(), from).looking_at(look, Vector3.UP)
	var tw := cam.create_tween().set_parallel(true)
	tw.tween_property(cam, "global_position", from, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cam, "quaternion", end.basis.get_rotation_quaternion(), secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func title(kicker: String, text: String, col := Color.WHITE) -> void:
	_kicker.text = kicker
	_title.text = text
	_title.add_theme_color_override("font_color", col)
	for l in [_kicker, _title]:
		l.create_tween().tween_property(l, "modulate:a", 1.0, 0.35)
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2(1.25, 1.25)
	_title.create_tween().tween_property(_title, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A painted portrait card in the lower-left corner (bosses, professors).
var _face: TextureRect
func portrait(tex: Texture2D) -> void:
	if tex == null or layer == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var sz := 132.0 if vs.x < 700.0 else 200.0
	_face = TextureRect.new()
	_face.texture = tex
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_face.size = Vector2(sz, sz)
	_face.position = Vector2(-sz, vs.y - _bar_h() - sz - 96.0)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.draw.connect(func():
		var r := Rect2(Vector2.ZERO, _face.size)
		_face.draw_rect(r, Color(0.05, 0.04, 0.03), false, 5.0)
		_face.draw_rect(r.grow(-3.0), Color(0.9, 0.72, 0.35), false, 2.0))
	layer.add_child(_face)
	_face.create_tween().tween_property(_face, "position:x", 28.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func portrait_off() -> void:
	if _face and is_instance_valid(_face):
		_face.create_tween().tween_property(_face, "modulate:a", 0.0, 0.25)

func title_off() -> void:
	for l in [_kicker, _title]:
		l.create_tween().tween_property(l, "modulate:a", 0.0, 0.3)

func say(text: String) -> void:
	_sub.text = text
	_sub.modulate.a = 0.0
	_sub.create_tween().tween_property(_sub, "modulate:a", 1.0, 0.25)

func say_off() -> void:
	_sub.create_tween().tween_property(_sub, "modulate:a", 0.0, 0.25)

func flash(col := Color.WHITE, secs := 0.5) -> void:
	_flash.color = Color(col.r, col.g, col.b, 0.85)
	_flash.create_tween().tween_property(_flash, "color:a", 0.0, secs)

## Bars slide away, the game's camera and input come back.
func end() -> void:
	if not active:
		return
	active = false
	if is_instance_valid(layer):
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_top, "offset_bottom", 0.0, 0.3)
		tw.tween_property(_bot, "offset_top", 0.0, 0.3)
		for l in [_kicker, _title, _sub, _hint]:
			tw.tween_property(l, "modulate:a", 0.0, 0.2)
	if _restore.is_valid():
		_restore.call()
	if is_instance_valid(cam):
		cam.queue_free()
	finished.emit()
	await get_tree().create_timer(0.35, true, false, true).timeout
	if is_instance_valid(layer):
		layer.queue_free()
	queue_free()
