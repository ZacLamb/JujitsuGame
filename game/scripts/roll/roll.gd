class_name RollScene
extends Node3D
## The roll (sparring match): mat, two posed grapplers, and the exchange loop UI.

signal finished(opp_id: String, result: Dictionary, xp: int)

enum Phase { INTRO, CHOOSE, TIMING, DEFEND, STRUGGLE_ATK, STRUGGLE_DEF, MESSAGE, OVER }

const DIRS := ["up", "down", "left", "right"]

var sim := RollSim.new()
var opp_id := ""
var opp: Dictionary
var phase := Phase.INTRO
var phase_t := 0.0
var phase_limit := 0.0
var pending_move := ""
var ai_move := ""
var defend_dir := ""
var struggle := 0.0
var struggle_p := {}
var struggle_sub := ""
var _after_message: Callable
var _message_time := 0.0

var player_rig: BodyRig
var opp_rig: BodyRig
var cam: Camera3D
var cam_angle := 0.6
var _you: Label3D
var _signature: Array = []
var _used_signature := false

# UI
var ui: Control
var lbl_clock: Label
var lbl_pos: Label
var lbl_ppts: Label
var lbl_opts: Label
var bar_pstam: ProgressBar
var bar_ostam: ProgressBar
var action_panel: PanelContainer
var action_title: Label
var action_body: VBoxContainer
var phase_bar: ProgressBar
var msg: Label
var timing: TimingBar
var struggle_bar: ProgressBar

var daily := {}  # set for Daily Challenge rolls

func start(opponent_id: String, daily_challenge: Dictionary = {}) -> void:
	opp_id = opponent_id
	daily = daily_challenge
	opp = daily.opp if not daily.is_empty() else Data.OPPONENTS[opponent_id]
	sim.setup(opponent_id, Game.level(), Game.knows, -1, Game.mods(), opp if not daily.is_empty() else {})
	if not daily.is_empty():
		sim.apply_rule(daily.rule)
	_signature = Rpg.STYLES[Game.style].signature if Game.style != "" else []
	_build_world()
	_build_ui()
	_pose_now(0.01)
	Sfx.music("roll")
	if not daily.is_empty():
		var rd: Dictionary = Data.DAILY_RULES[daily.rule]
		_show_message("DAILY CHALLENGE: %s\n%s" % [rd.name, rd.desc], 2.6, _begin_exchange)
	else:
		_show_message("%s: \"Oss!\"  Slap hands, bump fists..." % opp.name, 1.6, _begin_exchange)

# ================================================================= world
func _pm(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	var boss: bool = opp.get("boss", false)
	psm.sky_top_color = Color(0.2, 0.42, 0.75) if not boss else Color(0.12, 0.1, 0.1)
	psm.sky_horizon_color = Color(0.7, 0.84, 0.95) if not boss else Color(0.25, 0.18, 0.14)
	psm.ground_bottom_color = Color(0.2, 0.25, 0.15)
	psm.ground_horizon_color = Color(0.6, 0.55, 0.4)
	sky.sky_material = psm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.78)
	e.ambient_light_energy = 0.42
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.1
	e.tonemap_exposure = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.05 if not boss else 0.7
	sun.light_color = Color(1, 0.94, 0.85)
	sun.shadow_enabled = true
	add_child(sun)
	if boss:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0, 4, 0)
		lamp.omni_range = 9
		lamp.light_energy = 2.0
		lamp.light_color = Color(1, 0.85, 0.6)
		add_child(lamp)

	# ground
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	ground.material_override = _pm(Color(0.2, 0.32, 0.14) if not boss else Color(0.3, 0.2, 0.13))
	add_child(ground)
	# tatame: 6x6 tiles, alternating
	for x in 6:
		for z in 6:
			var t := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.98, 0.05, 0.98)
			t.mesh = bm
			var c := Color(0.13, 0.38, 0.26) if (x + z) % 2 == 0 else Color(0.78, 0.62, 0.22)
			if x == 0 or z == 0 or x == 5 or z == 5:
				c = Color(0.12, 0.2, 0.42)
			t.material_override = _pm(c, 0.6)
			t.position = Vector3(x - 2.5, 0.025, z - 2.5)
			add_child(t)
	if boss:
		for i in 3:
			var wall := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(12, 5, 0.3)
			wall.mesh = wm
			wall.material_override = _pm(Color(0.75, 0.62, 0.42))
			wall.position = Vector3(0, 2.5, -6)
			wall.rotation.y = i * PI / 2
			wall.position = Vector3(sin(i * PI / 2) * -6, 2.5, cos(i * PI / 2) * -6)
			add_child(wall)
		var banner := Label3D.new()
		banner.text = "ACADEMIA ONÇA"
		banner.font_size = 160
		banner.modulate = Color(0.1, 0.1, 0.1)
		banner.position = Vector3(0, 3.6, -5.8)
		add_child(banner)

	# spectators
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(opp_id)
	for i in 5:
		var s := BodyRig.new()
		add_child(s)
		var skin := UiKit.skin_tone(rng.randf())
		var gi := Color(0.95, 0.95, 0.95) if rng.randf() < 0.6 else Color(0.15, 0.3, 0.75)
		s.setup(gi, Data.BELTS[rng.randi_range(0, 2)].color, skin)
		var a := -0.9 + i * 0.45 + PI
		s.position = Vector3(sin(a) * 4.6, 0, cos(a) * 4.6)
		s.look_at(Vector3(0, 0, 0), Vector3.UP)
		s.rotation.x = 0
		s.animate_locomotion(0.016, 0.0)

	player_rig = BodyRig.new()
	add_child(player_rig)
	player_rig.setup(Game.gi_color(), Data.BELTS[Game.belt_index()].color, Color(0.86, 0.68, 0.55), Color(0.55, 0.36, 0.18), 0, "male")
	var you := Label3D.new()
	you.text = "YOU"
	you.font_size = 40
	you.pixel_size = 0.0035
	you.outline_size = 10
	you.modulate = UiKit.ACCENT
	you.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	you.no_depth_test = true
	you.name = "YouMarker"
	add_child(you)
	_you = you
	opp_rig = BodyRig.new()
	add_child(opp_rig)
	opp_rig.setup(opp.gi, Data.BELTS[Data.belt_of(int(opp.rank))].color, opp.skin, Color(0.12, 0.08, 0.05), -1, opp.get("body", "male"))

	cam = Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.make_current()

func _process(delta: float) -> void:
	cam_angle += delta * 0.12
	var radius := 4.4
	var h := 2.3
	if phase in [Phase.STRUGGLE_ATK, Phase.STRUGGLE_DEF]:
		radius = 3.2
		h = 1.7
	var target := Vector3(sin(cam_angle) * radius, h, cos(cam_angle) * radius)
	cam.position = cam.position.lerp(target, clampf(delta * 3.0, 0, 1)) if cam.position != Vector3.ZERO else target
	cam.look_at(Vector3(0, 0.45, 0), Vector3.UP)
	if _you:
		_you.global_position = (player_rig.joints["neck"] as Node3D).global_position + Vector3(0, 0.55, 0)
	_tick_phase(delta)
	_refresh_hud()

# ================================================================= poses
func _pose_now(dur := 0.5) -> void:
	var pair := RollPoses.get_pair(sim.pos)
	var top_rig := player_rig if sim.player_top else opp_rig
	var bot_rig := opp_rig if sim.player_top else player_rig
	top_rig.tween_pose(pair.top[0], pair.top[1], dur)
	bot_rig.tween_pose(pair.bottom[0], pair.bottom[1], dur)

# ================================================================= flow
func _set_phase(p: Phase, limit := 0.0) -> void:
	phase = p
	action_panel.visible = p != Phase.MESSAGE
	phase_t = 0.0
	phase_limit = limit
	phase_bar.visible = limit > 0.0

func _tick_phase(delta: float) -> void:
	if phase == Phase.OVER:
		return
	phase_t += delta
	if phase in [Phase.CHOOSE, Phase.TIMING, Phase.DEFEND, Phase.STRUGGLE_ATK, Phase.STRUGGLE_DEF]:
		sim.tick(delta)
		if phase == Phase.CHOOSE:
			sim.regen_tick(delta)
		if sim.second_wind_fired:
			sim.second_wind_fired = false
			msg.text = "SECOND WIND! +40 stamina"
			msg.modulate.a = 1.0
			create_tween().tween_property(msg, "modulate:a", 0.0, 1.5).set_delay(0.8)
	if phase_limit > 0.0:
		phase_bar.value = 100.0 * (1.0 - phase_t / phase_limit)
	match phase:
		Phase.MESSAGE:
			if phase_t >= _message_time:
				var cb := _after_message
				_after_message = Callable()
				if cb.is_valid():
					cb.call()
		Phase.CHOOSE:
			if sim.over:
				_end_match()
			elif phase_t >= phase_limit:
				_show_message("Too slow! %s takes the initiative." % opp.name, 0.8, _opponent_attack)
		Phase.TIMING:
			if phase_t >= phase_limit:
				_resolve_timing(-1.0)
		Phase.DEFEND:
			if phase_t >= phase_limit:
				_resolve_defense("")
		Phase.STRUGGLE_ATK, Phase.STRUGGLE_DEF:
			struggle -= float(struggle_p.decay) * delta
			struggle_bar.value = struggle * 100.0
			var wob := sin(phase_t * 30.0) * 0.03
			player_rig.hips.rotation.z += wob * delta * 10.0
			opp_rig.hips.rotation.z -= wob * delta * 10.0
			if phase == Phase.STRUGGLE_ATK:
				if struggle >= 1.0:
					_sub_finished(true)
				elif struggle <= 0.0 or phase_t >= phase_limit:
					_sub_escaped(true)
			else:
				if struggle >= 1.0:
					_sub_escaped(false)
				elif struggle <= 0.0:
					_sub_finished(false)
				elif phase_t >= phase_limit:
					if struggle >= 0.5:
						_sub_escaped(false)
					else:
						_sub_finished(false)

func _begin_exchange() -> void:
	if sim.over:
		_end_match()
		return
	_pose_now()
	if not sim.opp_options().is_empty() and sim.rng.randf() < sim.opp_initiative_chance():
		_show_message("%s grips up and goes first!" % opp.name, 0.7, _opponent_attack)
	else:
		_enter_choose()

func _enter_choose() -> void:
	_clear_action()
	action_title.text = "Your move  ·  %s" % Data.role_label(sim.pos, sim.player_top)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	action_body.add_child(flow)
	var i := 1
	for id in sim.player_options():
		var m: Dictionary = Data.MOVES[id]
		var b := UiKit.button("%d  %s" % [i, m.name], Vector2(230, 58))
		b.tooltip_text = m.type
		if id in _signature:
			b.text += "  (signature)"
			b.add_theme_color_override("font_color", UiKit.ACCENT)
		elif m.type == "sub":
			b.add_theme_color_override("font_color", Color(1, 0.6, 0.55))
		elif int(m.pts) > 0:
			b.text += "  (+%d)" % int(m.pts)
		b.pressed.connect(_choose.bind(id))
		flow.add_child(b)
		i += 1
	var br := UiKit.button("%d  Breathe" % i, Vector2(170, 58))
	br.add_theme_color_override("font_color", Color(0.6, 0.85, 1))
	br.pressed.connect(_breathe)
	flow.add_child(br)
	_set_phase(Phase.CHOOSE, sim.decision_window())

func _choose(id: String) -> void:
	if phase != Phase.CHOOSE:
		return
	pending_move = id
	_clear_action()
	var m: Dictionary = Data.MOVES[id]
	action_title.text = "%s  ·  stop in the GREEN (gold = perfect)" % m.name
	timing = TimingBar.new()
	timing.custom_minimum_size = Vector2(560, 46)
	timing.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	action_body.add_child(timing)
	var go := UiKit.button("GO!  (Space / tap)", Vector2(320, 70))
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.add_theme_font_size_override("font_size", 28)
	go.button_down.connect(func(): _resolve_timing(timing.marker))
	action_body.add_child(go)
	timing.start(sim.timing_params(id))
	_set_phase(Phase.TIMING, 4.0)

func _breathe() -> void:
	if phase != Phase.CHOOSE:
		return
	sim.recover(24)
	var next := _opponent_attack if sim.rng.randf() < 0.5 else _begin_exchange
	_show_message("You breathe, settle your grips and recover.", 0.9, next)

func _resolve_timing(marker: float) -> void:
	if phase != Phase.TIMING:
		return
	var params := {"center": timing.center, "width": timing.width, "perfect": timing.perfect}
	timing.stop()
	var j := "miss" if marker < 0.0 else sim.judge_timing(params, marker)
	var m: Dictionary = Data.MOVES[pending_move]
	if j == "perfect":
		Game.bump("perfect")
		sim.recover(6)
		Sfx.play("perfect")
	elif j == "hit":
		Sfx.play("hit")
	else:
		Sfx.play("miss")
	timing.flash_color = Color(1, 0.85, 0.3, 0.6) if j == "perfect" else (Color(0.2, 0.9, 0.4, 0.5) if j == "hit" else Color(1, 0.2, 0.2, 0.5))
	_set_phase(Phase.MESSAGE)
	if j == "miss":
		sim.failed_attempt(pending_move, true)
		var next := _opponent_attack if sim.rng.randf() < sim.counter_chance(pending_move) else _begin_exchange
		var t := "%s shuts down your %s." % [opp.name, m.name]
		if next == _opponent_attack:
			t += " Counter!"
		_show_message(t, 1.0, next)
		return
	var r := sim.apply_move(pending_move, true)
	_count_player_move(pending_move)
	if pending_move in _signature:
		_used_signature = true
	if r.sub:
		_start_struggle(true, pending_move)
		if j == "perfect":
			struggle = minf(0.9, struggle + 0.15)
			action_title.text += "  (deep grip!)"
	else:
		_pose_now()
		var prefix := "PERFECT! " if j == "perfect" else ""
		_show_message(prefix + r.text, 1.1, _begin_exchange)

func _count_player_move(id: String) -> void:
	var m: Dictionary = Data.MOVES[id]
	match m.type:
		"takedown": Game.bump("takedowns")
		"sweep": Game.bump("sweeps")
		"pass":
			if int(m.pts) > 0:
				Game.bump("passes")
		"back": Game.bump("backs")
		"advance": pass

func _opponent_attack() -> void:
	if sim.over:
		_end_match()
		return
	ai_move = sim.ai_pick_move()
	if ai_move == "":
		_enter_choose()
		return
	defend_dir = DIRS[sim.rng.randi() % DIRS.size()]
	var m: Dictionary = Data.MOVES[ai_move]
	_clear_action()
	action_title.text = "%s goes for a %s!" % [opp.name, m.name]
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 16)
	var dl := UiKit.label("DEFEND", 54, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	dl.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(dl)
	head.add_child(ArrowGlyph.make(defend_dir, 70, UiKit.ACCENT))
	action_body.add_child(head)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	for d in ["left", "up", "down", "right"]:
		var b := UiKit.button("", Vector2(96, 76))
		var g := ArrowGlyph.make(d, 52)
		g.set_anchors_preset(Control.PRESET_CENTER)
		g.offset_left = -26
		g.offset_top = -26
		g.offset_right = 26
		g.offset_bottom = 26
		b.add_child(g)
		b.button_down.connect(_resolve_defense.bind(d))
		row.add_child(b)
	action_body.add_child(row)
	action_body.add_child(UiKit.label("Arrow keys / WASD or tap the matching arrow", 16, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_set_phase(Phase.DEFEND, sim.defense_window(ai_move))

func _resolve_defense(dir: String) -> void:
	if phase != Phase.DEFEND:
		return
	var m: Dictionary = Data.MOVES[ai_move]
	var quick := phase_t < phase_limit * 0.4
	_set_phase(Phase.MESSAGE)
	if dir == defend_dir:
		Sfx.play("hit", -3.0, 1.25)
		sim.spend(4)
		sim.failed_attempt(ai_move, false)
		if quick:
			_show_message("Great reaction! You stuff the %s. Your initiative!" % m.name, 0.9, _enter_choose)
		else:
			_show_message("You defend the %s." % m.name, 0.9, _begin_exchange)
		return
	sim.spend(6)
	Sfx.play("miss")
	var r := sim.apply_move(ai_move, false)
	if r.sub:
		_start_struggle(false, ai_move)
	else:
		_pose_now()
		_show_message(r.text, 1.1, _begin_exchange)

func _start_struggle(attacking: bool, sub_id: String) -> void:
	struggle_sub = sub_id
	struggle_p = sim.struggle_params(attacking, sub_id)
	struggle = float(struggle_p.start)
	_clear_action()
	var m: Dictionary = Data.MOVES[sub_id]
	var flavor: String = Data.SUB_FLAVOR.get(sub_id, "")
	if attacking:
		action_title.text = "%s!  Finish it: %s" % [m.name, flavor]
	else:
		action_title.text = "%s is caught in a %s!  ESCAPE!" % ["You", m.name]
	struggle_bar = UiKit.bar(UiKit.ACCENT if attacking else UiKit.RED, Vector2(520, 30))
	struggle_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	struggle_bar.value = struggle * 100.0
	action_body.add_child(struggle_bar)
	var tap := UiKit.button("SQUEEZE!" if attacking else "FIGHT THE HANDS!", Vector2(360, 86))
	tap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tap.add_theme_font_size_override("font_size", 32)
	tap.button_down.connect(_struggle_tap)
	action_body.add_child(tap)
	action_body.add_child(UiKit.label("Mash Space or tap fast", 16, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_set_phase(Phase.STRUGGLE_ATK if attacking else Phase.STRUGGLE_DEF, float(struggle_p.limit))

func _struggle_tap() -> void:
	if phase in [Phase.STRUGGLE_ATK, Phase.STRUGGLE_DEF]:
		struggle = minf(1.0, struggle + float(struggle_p.gain))
		Sfx.play("squeeze", -6.0, randf_range(0.9, 1.2))
		if struggle >= 1.0:
			struggle_bar.value = 100.0
			if phase == Phase.STRUGGLE_ATK:
				_sub_finished(true)
			else:
				_sub_escaped(false)
		sim.spend(0.6)

func _sub_finished(player_won: bool) -> void:
	sim.finish_by_sub(player_won, struggle_sub)
	Sfx.play("tap")
	var m: Dictionary = Data.MOVES.get(struggle_sub, {"name": "submission"})
	if player_won:
		_show_message("TAP! TAP! %s taps to your %s!" % [opp.name, m.name], 1.4, _end_match)
	else:
		_show_message("You tap to the %s. Tap early, tap often." % m.name, 1.4, _end_match)

func _sub_escaped(attacker_was_player: bool) -> void:
	_set_phase(Phase.MESSAGE)
	if attacker_was_player:
		sim.failed_attempt(struggle_sub, true)
		_show_message("%s escapes! Advantage to you." % opp.name, 1.0, _begin_exchange)
	else:
		Game.bump("escapes")
		sim.failed_attempt(struggle_sub, false)
		_show_message("You escape! Hand fight won.", 1.0, _begin_exchange)
	_pose_now()

func _tap_out() -> void:
	if phase == Phase.OVER:
		return
	sim.finish_by_sub(false, "tap")
	_set_phase(Phase.MESSAGE)
	_show_message("You tap. Smart. Live to roll another day.", 1.0, _end_match)

func _end_match() -> void:
	if phase == Phase.OVER:
		return
	if not sim.over:
		sim.finish_on_points()
	_set_phase(Phase.OVER)
	var res := sim.result
	res["signature"] = _used_signature and res.won
	var xp := Game.record_daily(res, daily.date) if not daily.is_empty() else Game.record_roll(opp_id, res)
	Sfx.play("win" if res.won else "lose")
	var winner := player_rig if res.won else opp_rig
	var loser := opp_rig if res.won else player_rig
	winner.tween_pose(RollPoses.victory(), Transform3D(Basis(), Vector3(0, 0, 0.6)), 0.8)
	loser.tween_pose(RollPoses.defeated(), Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -0.7)), 0.8)
	_clear_action()
	var head := "VICTORY" if res.won else "DEFEAT"
	action_title.text = ""
	var big := UiKit.label(head, 56, UiKit.ACCENT if res.won else UiKit.RED, HORIZONTAL_ALIGNMENT_CENTER)
	action_body.add_child(big)
	var how := ""
	if res.by_sub:
		if res.sub == "tap":
			how = "You tapped out."
		else:
			how = "by %s" % Data.MOVES[res.sub].name
	else:
		how = "on points  %d – %d   (adv %d – %d)" % [sim.player_pts, sim.opp_pts, sim.player_adv, sim.opp_adv]
	action_body.add_child(UiKit.label(how, 24, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var line: String = opp.win if res.won else opp.lose
	action_body.add_child(UiKit.label("%s: \"%s\"" % [opp.name, line], 20, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	action_body.add_child(UiKit.label("+%d XP   ·   %s" % [xp, Data.rank_name(Game.rank)], 22, Color(0.6, 0.9, 1), HORIZONTAL_ALIGNMENT_CENTER))
	var back := UiKit.button("Back to %s" % Data.ZONES[Game.zone].name, Vector2(320, 64))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): finished.emit(opp_id, res, xp))
	action_body.add_child(back)

func _show_message(text: String, seconds: float, then: Callable) -> void:
	msg.text = text
	msg.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(msg, "modulate:a", 0.0, 0.3)
	_message_time = seconds
	_after_message = then
	_set_phase(Phase.MESSAGE)
	action_panel.visible = false

# ================================================================= input
func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	match phase:
		Phase.TIMING:
			if event.is_action_pressed("confirm"):
				_resolve_timing(timing.marker)
		Phase.DEFEND:
			for d in DIRS:
				if event.is_action_pressed("dir_" + d):
					_resolve_defense(d)
					return
		Phase.STRUGGLE_ATK, Phase.STRUGGLE_DEF:
			if event.is_action_pressed("confirm"):
				_struggle_tap()
		Phase.CHOOSE:
			if event is InputEventKey and event.pressed:
				var n: int = event.keycode - KEY_1
				var opts := sim.player_options()
				if n >= 0 and n < opts.size():
					_choose(opts[n])
				elif n == opts.size():
					_breathe()

# ================================================================= UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.theme = UiKit.theme()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	# top bar
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 12
	top.add_theme_constant_override("separation", 12)
	ui.add_child(top)
	var pbox := _fighter_box(Game.player_name, Game.rank, true)
	pbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(pbox)
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	lbl_clock = UiKit.label("4:00", 40, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	mid.add_child(lbl_clock)
	lbl_pos = UiKit.label("", 18, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_pos.custom_minimum_size = Vector2(110, 0)
	mid.add_child(lbl_pos)
	top.add_child(mid)
	var obox := _fighter_box(str(opp.name), int(opp.rank), false)
	obox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(obox)

	var tapbtn := UiKit.button("Tap out", Vector2(110, 40))
	tapbtn.add_theme_font_size_override("font_size", 16)
	tapbtn.anchor_left = 1.0
	tapbtn.anchor_right = 1.0
	tapbtn.offset_left = -126
	tapbtn.offset_right = -16
	tapbtn.offset_top = 150
	tapbtn.offset_bottom = 190
	tapbtn.pressed.connect(_tap_out)
	ui.add_child(tapbtn)

	msg = UiKit.label("", 30, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	msg.set_anchors_preset(Control.PRESET_CENTER)
	msg.anchor_left = 0.05
	msg.anchor_right = 0.95
	msg.anchor_top = 0.36
	msg.anchor_bottom = 0.36
	msg.offset_left = 0
	msg.offset_right = 0
	ui.add_child(msg)

	# action panel at the bottom
	action_panel = PanelContainer.new()
	action_panel.anchor_left = 0.0
	action_panel.anchor_right = 1.0
	action_panel.anchor_top = 1.0
	action_panel.anchor_bottom = 1.0
	action_panel.offset_left = 12
	action_panel.offset_right = -12
	action_panel.offset_bottom = -12
	action_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ui.add_child(action_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	action_panel.add_child(v)
	action_title = UiKit.label("", 22, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(action_title)
	phase_bar = UiKit.bar(Color(0.95, 0.95, 0.9, 0.8), Vector2(200, 6))
	phase_bar.visible = false
	v.add_child(phase_bar)
	action_body = VBoxContainer.new()
	action_body.add_theme_constant_override("separation", 12)
	v.add_child(action_body)

func _fighter_box(title: String, rank: int, is_player: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var name_l := UiKit.label(title, 18, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT if is_player else HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_child(name_l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN if is_player else BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	var chip := UiKit.belt_chip(rank, Vector2(96, 20))
	var pts := UiKit.label("0", 34, UiKit.ACCENT)
	pts.autowrap_mode = TextServer.AUTOWRAP_OFF
	if is_player:
		row.add_child(chip)
		row.add_child(pts)
		lbl_ppts = pts
	else:
		row.add_child(pts)
		row.add_child(chip)
		lbl_opts = pts
	v.add_child(row)
	var st := UiKit.bar(UiKit.GREEN, Vector2(160, 12))
	st.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if is_player else Control.SIZE_SHRINK_END
	v.add_child(st)
	if is_player:
		bar_pstam = st
	else:
		bar_ostam = st
	return v

func _clear_action() -> void:
	for c in action_body.get_children():
		c.queue_free()

func _refresh_hud() -> void:
	lbl_clock.text = sim.clock_text()
	lbl_pos.text = Data.POSITION_NAMES[sim.pos]
	lbl_ppts.text = "%d" % sim.player_pts + ("  A%d" % sim.player_adv if sim.player_adv > 0 else "")
	lbl_opts.text = ("A%d  " % sim.opp_adv if sim.opp_adv > 0 else "") + "%d" % sim.opp_pts
	bar_pstam.max_value = sim.max_stamina
	bar_pstam.value = sim.stamina
	bar_ostam.value = sim.opp_stamina
	var low := sim.stamina_pct() < 25.0
	bar_pstam.add_theme_stylebox_override("fill", UiKit.box(UiKit.RED if low else UiKit.GREEN, 6))
