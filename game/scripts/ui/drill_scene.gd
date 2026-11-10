class_name DrillScene
extends CanvasLayer
## Training drill minigames. Each drill trains one attribute.

signal finished(attr: String, success: bool)

const DIRS := ["up", "down", "left", "right"]

var attr := ""
var kind := ""
var _root: Control
var _title: Label
var _body: VBoxContainer
var _info: Label
var _t := 0.0
var _limit := 0.0
var _active := false
# mash
var _meter := 0.0
var _bar: ProgressBar
# timing
var _timing: TimingBar
var _round := 0
var _hits := 0
var _rounds := 3
# arrows
var _dir := ""
var _arrow_holder: HBoxContainer

## An odd job around town reuses a drill's minigame: {id, name, attr, kind, tip, done, fail}.
var job := {}

func start(attr_id: String, job_d: Dictionary = {}) -> void:
	attr = attr_id
	job = job_d
	var d: Dictionary = Rpg.DRILLS[attr].duplicate()
	if not job.is_empty():
		d["name"] = job.name
		d["tip"] = job.tip
		d["kind"] = job.get("kind", d.kind)
	kind = d.kind
	layer = 6
	_root = Control.new()
	_root.theme = UiKit.theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.2
	panel.anchor_bottom = 0.2
	panel.grow_vertical = Control.GROW_DIRECTION_END
	_root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	_title = UiKit.label((Tx.f("%s  ·  uses your %s", [d.name, Rpg.ATTRS[attr].name])) if not job.is_empty() else (Tx.f("%s  ·  %s", [d.name, Rpg.ATTRS[attr].name])), 32, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_title)
	_info = UiKit.label(d.tip, 20, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_info)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 14)
	v.add_child(_body)
	match kind:
		"mash":
			_bar = UiKit.bar(UiKit.ACCENT, Vector2(480, 30))
			_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			_body.add_child(_bar)
			var b := UiKit.button("TAP!  (Space)", Vector2(320, 84))
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			b.add_theme_font_size_override("font_size", 30)
			b.button_down.connect(_tap)
			_body.add_child(b)
			_meter = 0.15
			_limit = 6.0
		"timing":
			_timing = TimingBar.new()
			_timing.custom_minimum_size = Vector2(520, 46)
			_timing.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			_body.add_child(_timing)
			var g := UiKit.button("GO!  (Space)", Vector2(300, 74))
			g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			g.add_theme_font_size_override("font_size", 28)
			g.button_down.connect(_stop_timing)
			_body.add_child(g)
			_next_timing()
		"arrows":
			_rounds = 5
			_arrow_holder = HBoxContainer.new()
			_arrow_holder.alignment = BoxContainer.ALIGNMENT_CENTER
			_body.add_child(_arrow_holder)
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 14)
			for dd in ["left", "up", "down", "right"]:
				var ab := UiKit.button("", Vector2(96, 76))
				var gl := ArrowGlyph.make(dd, 52)
				gl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
				gl.offset_left = -26
				gl.offset_top = -26
				gl.offset_right = 26
				gl.offset_bottom = 26
				ab.add_child(gl)
				ab.button_down.connect(_answer.bind(dd))
				row.add_child(ab)
			_body.add_child(row)
			_next_arrow()
	_active = true

func _skill() -> float:
	return float(Game.attr(attr) - Rpg.ATTR_BASE)

func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	match kind:
		"mash":
			_meter = maxf(0.0, _meter - delta * 0.16)
			_bar.value = _meter * 100.0
			_info.text = "%.1f s" % maxf(0.0, _limit - _t)
			if _meter >= 1.0:
				_finish(true)
			elif _t >= _limit:
				_finish(false)
		"timing":
			if _t >= 4.0:
				_stop_timing()
		"arrows":
			if _t >= _limit:
				_answer("")

func _unhandled_input(event: InputEvent) -> void:
	if not _active or event.is_echo():
		return
	match kind:
		"mash":
			if event.is_action_pressed("confirm"):
				_tap()
		"timing":
			if event.is_action_pressed("confirm"):
				_stop_timing()
		"arrows":
			for d in DIRS:
				if event.is_action_pressed("dir_" + d):
					_answer(d)
					return

func _tap() -> void:
	if _active and kind == "mash":
		_meter = minf(1.0, _meter + 0.055 + 0.003 * _skill())
		if _meter >= 1.0:
			_bar.value = 100.0
			_finish(true)

func _next_timing() -> void:
	_t = 0.0
	var w := clampf(0.22 + 0.012 * _skill(), 0.12, 0.4)
	var c := randf_range(0.15 + w / 2.0, 0.85 - w / 2.0)
	_timing.start({"center": c, "width": w, "perfect": w * 0.2, "speed": 1.0 + 0.1 * _round})
	_info.text = Tx.f("Rep %d of %d  ·  hits: %d", [_round + 1, _rounds, _hits])

func _stop_timing() -> void:
	if not _active or kind != "timing" or not _timing.running:
		return
	var m := _timing.stop()
	var ok := absf(m - _timing.center) <= _timing.width * 0.5
	_timing.flash_color = Color(0.2, 0.9, 0.4, 0.5) if ok else Color(1, 0.2, 0.2, 0.5)
	if ok:
		_hits += 1
	_round += 1
	if _round >= _rounds:
		_finish(_hits >= 2)
	else:
		_active = false
		get_tree().create_timer(0.5).timeout.connect(func():
			_active = true
			_next_timing())

func _next_arrow() -> void:
	_t = 0.0
	_limit = clampf(1.3 + 0.04 * _skill(), 0.8, 2.0)
	_dir = DIRS[randi() % DIRS.size()]
	for c in _arrow_holder.get_children():
		c.queue_free()
	_arrow_holder.add_child(ArrowGlyph.make(_dir, 80, UiKit.ACCENT))
	_info.text = Tx.f("Prompt %d of %d  ·  correct: %d", [_round + 1, _rounds, _hits])

func _answer(d: String) -> void:
	if not _active or kind != "arrows":
		return
	if d == _dir:
		_hits += 1
	_round += 1
	if _round >= _rounds:
		_finish(_hits >= 4)
	else:
		_next_arrow()

func _finish(success: bool) -> void:
	_active = false
	for c in _body.get_children():
		c.queue_free()
	_title.text = "Good session!" if success else "Rough session."
	_info.text = Tx.f("Keep drilling. Every 3 good sessions = +1 %s (max +%d).", [Rpg.ATTRS[attr].name, Game.TRAIN_CAP]) if success else "No progress this time. Roll with someone, then try again."
	if not job.is_empty():
		_title.text = "Job done!" if success else "Not this time."
		_info.text = str(job.done) if success else str(job.fail)
	var b := UiKit.button("Back", Vector2(220, 60))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): finished.emit(str(job.id) if not job.is_empty() else attr, success))
	_body.add_child(b)
