class_name RollScene
extends Node3D
## The roll (sparring match): mat, two posed grapplers and a real-time, WoW-style fight.
## RollSim owns the rules; this scene plays its events as animation, sound and UI.
##
## Controls: 1-8 abilities · Q Base · E Frame · R Defend · F Breathe · Space mash.
## Controller: A/B/X/Y = slots 1-4, hold LB for 5-8, D-pad left/up/right = Base/Frame/Defend,
## D-pad down = Breathe, A (or RB) mashes during a submission.

signal finished(opp_id: String, result: Dictionary, xp: int)

enum Phase { INTRO, LIVE, OVER }

const TEAM_YOU := Color(1.0, 0.78, 0.22)    # gold: you
const TEAM_OPP := Color(0.95, 0.28, 0.24)    # red: them
const DEF_KEYS := {"base": "Q", "frame": "E", "defend": "R"}
const DEF_PAD := {"base": "◀", "frame": "▲", "defend": "▶"}

var sim := RollSim.new()
var opp_id := ""
var opp: Dictionary
var phase := Phase.INTRO
var _after_message: Callable
var _message_left := 0.0

var player_rig: BodyRig
var opp_rig: BodyRig
var cam: Camera3D
var cam_angle := 0.6
var _you: Label3D
var _signature: Array = []
var _used_signature := false
var _maxed_grips := false

# UI
var ui: Control
var lbl_clock: Label
var lbl_pos: Label
var lbl_ppts: Label
var lbl_opts: Label
var bar_pstam: ProgressBar
var bar_ostam: ProgressBar
var pips_p: CombatUi.Pips
var pips_o: CombatUi.Pips
var stat_p: Label
var stat_o: Label
var counter_ready: Label
var cast_p: CombatUi.CastBar
var cast_o: CombatUi.CastBar
var alert: CombatUi.CastBar
var bar_box: HBoxContainer
var slots: Array = []
var _bar_key := ""
var def_btns := {}
var breathe_btn: Button
var live_root: Control
var struggle_panel: PanelContainer
var struggle_title: Label
var struggle_bar: ProgressBar
var struggle_btn: Button
var action_panel: PanelContainer
var action_title: Label
var action_body: VBoxContainer
var msg: Label
var floats: Control
var intro_panel: PanelContainer

var daily := {}  # set for Daily Challenge rolls
var comp := {}   # set for competition matches: {id, round_name, opp, final}
var team := {}   # set for 5v5 bouts: {me, them, me_stam, them_stam}
var me_name := ""
var me_rank := 0
var _log: Array = []  # exchange outcomes for the share card (see ShareCard.CODES)

func start(opponent_id: String, daily_challenge: Dictionary = {}, comp_match: Dictionary = {}, team_bout: Dictionary = {}) -> void:
	opp_id = opponent_id
	daily = daily_challenge
	comp = comp_match
	team = team_bout
	me_name = Game.player_name
	me_rank = Game.rank
	if not team.is_empty():
		opp = Team.as_opp(team.them)
		Team.setup_sim(sim, team.me, team.them, float(team.me_stam), float(team.them_stam))
		me_name = str(team.me.name)
		me_rank = int(team.me.get("rank", Game.rank))
	else:
		opp = daily.opp if not daily.is_empty() else (comp.opp if not comp.is_empty() else Data.OPPONENTS[opponent_id])
		sim.setup(opponent_id, Game.level(), Game.knows, -1, Game.mods(), opp if not (daily.is_empty() and comp.is_empty()) else {})
	if not daily.is_empty():
		sim.apply_rule(daily.rule)
	_signature = Rpg.STYLES[Game.style].signature if Game.style != "" and (team.is_empty() or team.me.get("player", false)) else []
	sim.signature = _signature
	_build_world()
	_build_ui()
	_pose_now(0.01)
	Sfx.music("roll")
	var tut := int(Game.flags.get("roll_tut", 0)) < 3
	if tut:
		Game.flags["roll_tut"] = int(Game.flags.get("roll_tut", 0)) + 1
	intro_panel.visible = tut
	var t := 6.0 if tut else 2.4
	if not daily.is_empty():
		var rd: Dictionary = Data.DAILY_RULES[daily.rule]
		_show_message("DAILY CHALLENGE: %s\n%s" % [rd.name, rd.desc], maxf(t, 2.6), _go_live)
	elif not comp.is_empty():
		_show_message("%s  ·  %s\nvs %s (%s)" % [Data.COMPS[comp.id].name.to_upper(), comp.round_name.to_upper(), opp.name, opp.get("academy", "")], t, _go_live)
	else:
		var plan: String = sim.traits.plan
		if plan != "":
			_show_message("SCOUTING REPORT: %s\n%s" % [opp.name.to_upper(), plan], maxf(t, 3.2), _go_live)
		else:
			_show_message("%s: \"Oss!\"  Slap hands, bump fists..." % opp.name, t, _go_live)

func _go_live() -> void:
	if phase != Phase.INTRO:
		return
	intro_panel.visible = false
	phase = Phase.LIVE
	sim.start_live()
	_live_ui(true)
	_float("ROLL!", Vector2(0.5, 0.42), UiKit.ACCENT, 46)
	Sfx.play("perfect", -6.0, 0.8)

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
	if not team.is_empty() and not team.me.get("player", false):
		var tm: Dictionary = team.me
		player_rig.setup(tm.get("gi", Color.WHITE), Data.BELTS[Data.belt_of(me_rank)].color, tm.get("skin", Color(0.7, 0.5, 0.35)), Color(0.12, 0.08, 0.05), -1, str(tm.get("body", "male")))
	else:
		Game.dress(player_rig)
		player_rig.setup(Game.gi_color(), Data.BELTS[Game.belt_index()].color, Color(0.86, 0.68, 0.55), Color(0.55, 0.36, 0.18), 0, "male")
	player_rig.set_fighter(TEAM_YOU, 1)
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
	if Gear.BOSS_SET.has(opp_id):
		opp_rig.look = Gear.set_look(Gear.BOSS_SET[opp_id])   # bosses wear their own set
	opp_rig.setup(opp.gi, Data.BELTS[Data.belt_of(int(opp.rank))].color, opp.skin, Color(0.12, 0.08, 0.05), -1, opp.get("body", "male"))
	opp_rig.set_fighter(TEAM_OPP, 2)
	_ring_p = _team_ring(TEAM_YOU)
	_ring_o = _team_ring(TEAM_OPP)

	cam = Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.make_current()

var _ring_p: MeshInstance3D
var _ring_o: MeshInstance3D

## Team-coloured floor ring under a fighter (esports readability).
func _team_ring(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	tm.rings = 32
	mi.mesh = tm
	mi.scale = Vector3(1, 0.05, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

var _shake := 0.0
var _sub_pose := {}          # RollPoses.sub_pair result while a submission is locked in
var _sub_by_player := false

## Plays a move as a short arc (dive, roll, step around...) instead of a straight blend.
func _animate_move(id: String, actor_player: bool) -> void:
	var m: Dictionary = Data.MOVES[id]
	var pair := RollPoses.get_pair(sim.pos)
	var actor := player_rig if actor_player else opp_rig
	var other := opp_rig if actor_player else player_rig
	var fl := RollPoses.flavor(str(m.type))
	for rig in [actor, other]:
		var is_top: bool = (rig == player_rig) == sim.player_top
		var fin: Array = pair.top if is_top else pair.bottom
		var mid_p := BodyRig.lerp_pose(rig.current_pose(), fin[0], 0.5)
		var mid_r: Transform3D = rig.current_root().interpolate_with(fin[1], 0.5)
		var partner: BodyRig = other if rig == actor else actor
		var res := RollPoses.apply_flavor(mid_p, mid_r, fl.actor if rig == actor else fl.other, partner.position - rig.position)
		rig.tween_frames([[res[0], res[1], 0.3], [fin[0], fin[1], 0.4]])
	if m.type in ["takedown", "sweep"]:
		get_tree().create_timer(0.62).timeout.connect(_impact)

## Landing: camera shake, a puff of dust off the mat, a thud.
func _impact() -> void:
	if not is_inside_tree():
		return
	_shake = 0.6
	UiKit.buzz(45)
	Sfx.play("hit", -2.0, 0.6)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 26
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0, -2.5, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.92, 0.85, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = mat
	p.position = (player_rig.position + opp_rig.position) * 0.5 + Vector3(0, 0.1, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

func _process(delta: float) -> void:
	# broadcast camera: side-on to the fighters (like a fighting game), swaying slowly
	cam_angle += delta
	var yaw := PI / 2 + sin(cam_angle * 0.11) * 0.5
	var radius := 4.1
	var h := 2.0
	if not sim.struggle.is_empty():
		radius = 3.1
		h = 1.6
	var target := Vector3(sin(yaw) * radius, h, cos(yaw) * radius)
	cam.position = cam.position.lerp(target, clampf(delta * 3.0, 0, 1)) if cam.position != Vector3.ZERO else target
	cam.look_at(Vector3(0, 0.45, 0), Vector3.UP)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.6)
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.12
	if _you:
		_you.global_position = (player_rig.joints["neck"] as Node3D).global_position + Vector3(0, 0.55, 0)
	for pr in [[_ring_p, player_rig], [_ring_o, opp_rig]]:
		if pr[0]:
			var hp: Vector3 = ((pr[1] as BodyRig).hips as Node3D).global_position
			(pr[0] as MeshInstance3D).position = Vector3(hp.x, 0.06, hp.z)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			var cb := _after_message
			_after_message = Callable()
			if cb.is_valid():
				cb.call()
	if phase == Phase.LIVE:
		sim.tick(delta)
		if sim.second_wind_fired:
			sim.second_wind_fired = false
			_float("SECOND WIND! +40", Vector2(0.25, 0.3), Color(0.5, 1, 0.6), 30)
		_drain_events()
	_refresh_hud()

# ================================================================= poses
func _pose_now(dur := 0.5) -> void:
	var pair := RollPoses.get_pair(sim.pos)
	var top_rig := player_rig if sim.player_top else opp_rig
	var bot_rig := opp_rig if sim.player_top else player_rig
	top_rig.tween_pose(pair.top[0], pair.top[1], dur)
	bot_rig.tween_pose(pair.bottom[0], pair.bottom[1], dur)

# ================================================================= events
func _drain_events() -> void:
	var evs := sim.events
	sim.events = []
	for ev in evs:
		_on_event(ev)

func _on_event(ev: Dictionary) -> void:
	var who_p: bool = ev.get("who", "") == "p"
	match ev.e:
		"cast":
			if who_p:
				for s in slots:
					if s.id == ev.id:
						s.flash()
				cast_p.title = ev.name
				cast_p.col = CombatUi.slot_color(ev.id, ev.kind)
				cast_p.interrupted = 0.0
			else:
				var c: String = ev.get("counter", "grip")
				cast_o.title = ev.name
				cast_o.col = CombatUi.KIND_COLORS["grip" if c == "grip" else c]
				cast_o.interrupted = 0.0
				if ev.kind == "move":
					alert.title = "%s" % ev.name
					alert.col = CombatUi.KIND_COLORS[c]
					alert.tag = RollSim.DEF_NAMES[c].to_upper()
					alert.interrupted = 0.0
					Sfx.play("click", -4.0, 0.7)
		"grip":
			if who_p:
				_float("+GRIP  %d" % ev.n, Vector2(0.3, 0.55), UiKit.ACCENT, 24)
				Sfx.play("hit", -14.0, 1.6)
				if int(ev.n) >= RollSim.MAX_CONTROL and not _maxed_grips:
					_maxed_grips = true
					Game.bump("grip_master")
			else:
				_float("+GRIP", Vector2(0.7, 0.55), Color(1, 0.75, 0.6), 20)
		"wear":
			if who_p:
				_float("%s  -10 gas" % ev.name, Vector2(0.7, 0.5), Color(0.8, 0.65, 1), 22)
			else:
				_float("%s  -8 gas" % ev.name, Vector2(0.3, 0.5), Color(0.8, 0.65, 1), 22)
		"breathed":
			_float("+20 STAMINA", Vector2(0.3, 0.5), Color(0.5, 0.9, 1), 24)
		"interrupt":
			if ev.by == "p":
				cast_o.interrupted = 0.7
				if ev.was == "move":
					alert.interrupted = 0.8
					_float("INTERRUPTED!", Vector2(0.5, 0.3), UiKit.ACCENT, 44)
					Sfx.play("perfect")
					Game.bump("perfect")
					_log.append("B")
					_lean(player_rig, opp_rig)
				else:
					_float("GRIP STRIPPED", Vector2(0.7, 0.55), Color(0.85, 0.85, 0.8), 20)
					Sfx.play("hit", -10.0, 1.3)
			else:
				cast_p.interrupted = 0.7
				if ev.was == "move":
					_float("READ!  %s stuffs it" % opp.name, Vector2(0.5, 0.3), UiKit.RED, 34)
					Sfx.play("miss")
					_log.append("R")
					_lean(opp_rig, player_rig)
				else:
					_float("Grip stripped", Vector2(0.3, 0.55), Color(1, 0.6, 0.55), 20)
		"wrong":
			_float("WRONG COUNTER (needed %s)" % RollSim.DEF_NAMES.get(ev.need, "?").to_upper(), Vector2(0.5, 0.62), UiKit.RED, 24)
			Sfx.play("miss", -8.0)
		"whiff":
			_float("Nothing to counter", Vector2(0.5, 0.62), UiKit.MUTED, 18)
		"stuffed":
			var m: Dictionary = Data.MOVES[ev.id]
			if who_p:
				_message("%s shuts down your %s." % [opp.name, m.name], 1.4)
				_float("STUFFED", Vector2(0.3, 0.42), UiKit.RED, 30)
				Sfx.play("miss")
				_log.append("R")
			else:
				_message("You shut down the %s." % m.name, 1.4)
				_float("DEFENDED", Vector2(0.7, 0.42), Color(0.6, 1, 0.7), 28)
				Sfx.play("hit", -3.0, 1.25)
				_log.append("B")
			_shake = 0.15
		"landed":
			alert.title = ""
			_animate_move(ev.id, who_p)
			if who_p:
				_count_player_move(ev.id)
				if ev.id in _signature:
					_used_signature = true
				_message(_call(ev.id, me_name, opp.name), 2.0)
				_log.append("Y" if int(ev.get("spent", 0)) >= 4 else "G")
				Sfx.play("hit")
				if int(Data.MOVES[ev.id].pts) > 0:
					_float("+%d" % int(Data.MOVES[ev.id].pts), Vector2(0.3, 0.38), UiKit.ACCENT, 40)
			else:
				_message(_call(ev.id, opp.name, me_name), 2.0)
				_log.append("O")
				Sfx.play("miss", -4.0, 0.8)
				if int(Data.MOVES[ev.id].pts) > 0:
					_float("+%d" % int(Data.MOVES[ev.id].pts), Vector2(0.7, 0.38), UiKit.RED, 36)
		"sub":
			alert.title = ""
			_start_struggle(who_p, ev.id)
		"escaped":
			_sub_escaped(ev.who == "o")
		"tap":
			_sub_finished(ev.who == "o")
		"over":
			if not sim.result.get("by_sub", false):
				_message("TIME!  The bell rings.", 1.5)
				_after(1.2, _end_match)

func _after(seconds: float, then: Callable) -> void:
	get_tree().create_timer(seconds).timeout.connect(func():
		if is_inside_tree():
			then.call())

## A quick lean-in when someone reads a technique.
func _lean(winner: BodyRig, loser: BodyRig) -> void:
	_shake = 0.2
	UiKit.buzz(25)
	var d := (loser.position - winner.position)
	d.y = 0
	if d.length() < 0.01:
		return
	var tw := create_tween()
	tw.tween_property(winner, "position", winner.position + d.normalized() * 0.12, 0.08)
	tw.tween_property(winner, "position", winner.position, 0.18)

# ================================================================= submissions
func _start_struggle(attacking: bool, sub_id: String) -> void:
	var atk_rig := player_rig if attacking else opp_rig
	var def_rig := opp_rig if attacking else player_rig
	var atk_top: bool = sim.player_top if attacking else not sim.player_top
	_sub_pose = RollPoses.sub_pair(sub_id, sim.pos, atk_top)
	_sub_by_player = attacking
	atk_rig.tween_pose(_sub_pose.atk[0], _sub_pose.atk[1], 0.55)
	def_rig.tween_pose(_sub_pose.def[0], _sub_pose.def[1], 0.55)
	var m: Dictionary = Data.MOVES[sub_id]
	var flavor: String = Data.SUB_FLAVOR.get(sub_id, "")
	if attacking:
		struggle_title.text = "%s!  Finish it: %s" % [m.name, flavor] if flavor != "" else "%s!  Finish it!" % m.name
		struggle_btn.text = "SQUEEZE!  (Space / A)"
		struggle_bar.add_theme_stylebox_override("fill", UiKit.box(UiKit.ACCENT, 6))
	else:
		struggle_title.text = "Caught in a %s!  ESCAPE!" % m.name
		struggle_btn.text = "FIGHT THE HANDS!  (Space / A)"
		struggle_bar.add_theme_stylebox_override("fill", UiKit.box(UiKit.RED, 6))
	struggle_panel.visible = true
	_shake = 0.2

func _struggle_tap() -> void:
	if sim.struggle.is_empty():
		return
	sim.tap()
	_squeeze_pulse()
	Sfx.play("squeeze", -6.0, randf_range(0.9, 1.2))
	_drain_events()

## Commentary line for a landed technique, with the points it scored.
func _call(move_id: String, attacker: String, defender: String) -> String:
	var t := Data.commentary(move_id, attacker, defender)
	var pts := int(Data.MOVES[move_id].pts)
	if pts > 0:
		t += "  +%d" % pts
	return t

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

## Each tap in a struggle: the attacker squeezes, the defender pulls at the grip.
func _squeeze_pulse() -> void:
	if _sub_pose.is_empty():
		return
	var key := "atk" if _sub_by_player else "def"
	var base: Array = _sub_pose[key]
	var p: Dictionary = (base[0] as Dictionary).duplicate()
	if _sub_by_player:
		p.hip_h = float(p.get("hip_h", 0.95)) + 0.05
		p["spine"] = (p.get("spine", Vector3.ZERO) as Vector3) + Vector3(-0.12, 0, 0)
		p["l_el"] = (p.get("l_el", Vector3.ZERO) as Vector3) + Vector3(0.2, 0, 0)
	else:
		p["l_sh"] = (p.get("l_sh", Vector3.ZERO) as Vector3) + Vector3(0.3, 0, 0.2)
		p["r_sh"] = (p.get("r_sh", Vector3.ZERO) as Vector3) + Vector3(0.3, 0, -0.2)
		p["hip_rot"] = (p.get("hip_rot", Vector3.ZERO) as Vector3) + Vector3(0, 0, randf_range(-0.12, 0.12))
	player_rig.tween_frames([[p, base[1], 0.06], [base[0], base[1], 0.1]])
	UiKit.buzz(12)

func _sub_finished(player_won: bool) -> void:
	struggle_panel.visible = false
	_log.append("S" if player_won else "X")
	if not _sub_pose.is_empty():
		var tapper := opp_rig if player_won else player_rig
		tapper.tween_frames(RollPoses.tap_frames(_sub_pose.def[0], _sub_pose.def[1]))
		_shake = 0.25
		UiKit.buzz(70)
	Sfx.play("tap")
	var m: Dictionary = Data.MOVES.get(sim.result.get("sub", ""), {"name": "submission"})
	if player_won:
		_message("TAP! TAP! %s taps to your %s!" % [opp.name, m.name], 1.6)
	else:
		_message("You tap to the %s. Tap early, tap often." % m.name, 1.6)
	_after(1.5, _end_match)

func _sub_escaped(attacker_was_player: bool) -> void:
	struggle_panel.visible = false
	_sub_pose = {}
	if attacker_was_player:
		_message("%s escapes! Advantage to you." % opp.name, 1.4)
	else:
		Game.bump("escapes")
		_message("You escape! Hand fight won.", 1.4)
	_pose_now()

func _tap_out() -> void:
	if phase != Phase.LIVE:
		return
	sim.finish_by_sub(false, "tap")
	struggle_panel.visible = false
	_log.append("X")
	_message("You tap. Smart. Live to roll another day.", 1.2)
	_after(1.0, _end_match)

func _end_match() -> void:
	if phase == Phase.OVER:
		return
	if not sim.over:
		sim.finish_on_points()
	phase = Phase.OVER
	_live_ui(false)
	action_panel.visible = true
	var res := sim.result
	res["signature"] = _used_signature and res.won
	var xp := 0
	if not team.is_empty():
		res["me_stam"] = sim.stamina / sim.max_stamina
		res["them_stam"] = sim.opp_stamina / 100.0
	elif not daily.is_empty():
		xp = Game.record_daily(res, daily.date)
	elif not comp.is_empty():
		xp = Game.record_comp_match(res, float(opp.level))
	else:
		xp = Game.record_roll(opp_id, res)
	Sfx.play("win" if res.won else "lose")
	var winner := player_rig if res.won else opp_rig
	var loser := opp_rig if res.won else player_rig
	winner.tween_pose(RollPoses.victory(), Transform3D(Basis(), Vector3(0, 0, 0.6)), 0.8)
	loser.tween_pose(RollPoses.defeated(), Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -0.7)), 0.8)
	_clear_action()
	var head := "VICTORY" if res.won else "DEFEAT"
	if res.get("draw", false):
		head = "DRAW: BOTH OUT"
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
	if team.is_empty():
		action_body.add_child(UiKit.label("+%d XP   ·   %s" % [xp, Data.rank_name(Game.rank)], 22, Color(0.6, 0.9, 1), HORIZONTAL_ALIGNMENT_CENTER))
	else:
		action_body.add_child(UiKit.label("%s leaves the mat with %d%% stamina" % [me_name if res.won else opp.name, int(100.0 * float(res.me_stam if res.won else res.them_stam))], 20, Color(0.6, 0.9, 1), HORIZONTAL_ALIGNMENT_CENTER))
	if not daily.is_empty():
		action_body.add_child(ShareCard.squares(_log))
		var text := ShareCard.build_text(daily, res, _log, Vector2i(sim.player_pts, sim.opp_pts), int(Game.daily.get("streak", 0)))
		var sh := UiKit.button("Share result", Vector2(320, 56))
		sh.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		sh.add_theme_color_override("font_color", UiKit.ACCENT)
		sh.pressed.connect(func():
			var st := ShareCard.share(text)
			sh.text = "Shared!" if st == "shared" else "Copied! Paste it in the group chat")
		action_body.add_child(sh)
	var back_text := "Back to %s" % Data.ZONES[Game.zone].name
	if not comp.is_empty():
		back_text = "Continue"
	if not team.is_empty():
		back_text = "Back to the team board"
	var back := UiKit.button(back_text, Vector2(320, 64))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): finished.emit(opp_id, res, xp))
	action_body.add_child(back)

## Intro / blocking message (calls `then` when it ends).
func _show_message(text: String, seconds: float, then: Callable) -> void:
	_message(text, seconds)
	_message_left = seconds
	_after_message = then

## Commentary line (non-blocking).
func _message(text: String, seconds := 1.6) -> void:
	msg.text = text
	msg.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(msg, "modulate:a", 0.0, 0.35)

## Floating combat text at a screen fraction.
func _float(text: String, at: Vector2, col: Color, size := 24) -> void:
	var l := UiKit.label(text, size, col, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_constant_override("outline_size", 8)
	floats.add_child(l)
	var vs := floats.size
	l.reset_size()
	l.position = Vector2(vs.x * at.x - l.size.x / 2.0, vs.y * at.y) + Vector2(randf_range(-20, 20), 0)
	l.scale = Vector2(0.6, 0.6)
	l.pivot_offset = l.size / 2.0
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 60, 1.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)

# ================================================================= input
func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if phase == Phase.INTRO:
		if (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed() and _message_left > 0.6:
			_message_left = 0.05   # skip the intro
		return
	if phase != Phase.LIVE:
		return
	if event is InputEventKey and event.pressed:
		var k: int = event.physical_keycode
		if not sim.struggle.is_empty():
			if k in [KEY_SPACE, KEY_ENTER]:
				_struggle_tap()
				get_viewport().set_input_as_handled()
			return
		if k >= KEY_1 and k <= KEY_8:
			_use_index(k - KEY_1)
		elif k == KEY_Q:
			_defend("base")
		elif k == KEY_E:
			_defend("frame")
		elif k == KEY_R:
			_defend("defend")
		elif k == KEY_F:
			_breathe()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		var b: int = event.button_index
		if not sim.struggle.is_empty():
			if b in [JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]:
				_struggle_tap()
			return
		var face := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y].find(b)
		if face >= 0:
			var lb := Input.is_joy_button_pressed(event.device, JOY_BUTTON_LEFT_SHOULDER)
			_use_index(face + (4 if lb else 0))
		elif b == JOY_BUTTON_DPAD_LEFT:
			_defend("base")
		elif b == JOY_BUTTON_DPAD_UP:
			_defend("frame")
		elif b == JOY_BUTTON_DPAD_RIGHT:
			_defend("defend")
		elif b == JOY_BUTTON_DPAD_DOWN:
			_breathe()

func _use_index(i: int) -> void:
	if i >= 0 and i < slots.size():
		_use(slots[i].id)

func _use(id: String) -> void:
	if phase != Phase.LIVE:
		return
	var why := sim.use(id)
	match why:
		"control":
			_float("Need more grips", Vector2(0.5, 0.66), UiKit.ACCENT, 20)
		"stamina":
			_float("Too tired", Vector2(0.5, 0.66), UiKit.RED, 20)
	_drain_events()

func _defend(kind: String) -> void:
	if phase != Phase.LIVE:
		return
	sim.defend(kind)
	if def_btns.has(kind):
		var b: Button = def_btns[kind]
		var tw := create_tween()
		b.scale = Vector2(0.92, 0.92)
		tw.tween_property(b, "scale", Vector2.ONE, 0.12)
	_drain_events()

func _breathe() -> void:
	if phase == Phase.LIVE:
		sim.breathe()
		_drain_events()

# ================================================================= UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.theme = UiKit.theme()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	# unit frames + clock
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 12
	top.add_theme_constant_override("separation", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(top)
	var pbox := _fighter_box(me_name, me_rank, true)
	pbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(pbox)
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_BEGIN
	mid.add_theme_constant_override("separation", -4)
	lbl_clock = UiKit.label("4:00", 40, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	mid.add_child(lbl_clock)
	lbl_pos = UiKit.label("", 17, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_pos.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl_pos.custom_minimum_size = Vector2(170, 0)
	mid.add_child(lbl_pos)
	top.add_child(mid)
	var obox := _fighter_box(str(opp.name), int(opp.rank), false)
	obox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(obox)

	var tapbtn := UiKit.button("Tap out", Vector2(100, 36))
	tapbtn.add_theme_font_size_override("font_size", 15)
	tapbtn.focus_mode = Control.FOCUS_NONE
	tapbtn.anchor_left = 1.0
	tapbtn.anchor_right = 1.0
	tapbtn.offset_left = -116
	tapbtn.offset_right = -16
	tapbtn.offset_top = 196
	tapbtn.offset_bottom = 232
	tapbtn.pressed.connect(_tap_out)
	ui.add_child(tapbtn)

	msg = UiKit.label("", 26, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	msg.anchor_left = 0.1
	msg.anchor_right = 0.9
	msg.anchor_top = 0.155
	msg.anchor_bottom = 0.155
	msg.add_theme_constant_override("outline_size", 8)
	msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(msg)

	floats = Control.new()
	floats.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	floats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(floats)

	# opponent's big cast alert (boss-mod style)
	alert = CombatUi.CastBar.new()
	alert.big = true
	alert.anchor_left = 0.5
	alert.anchor_right = 0.5
	alert.anchor_top = 0.3
	alert.anchor_bottom = 0.3
	alert.offset_left = -260
	alert.offset_right = 260
	alert.offset_bottom = 44
	alert.custom_minimum_size = Vector2(520, 44)
	ui.add_child(alert)

	live_root = VBoxContainer.new()
	live_root.anchor_left = 0.0
	live_root.anchor_right = 1.0
	live_root.anchor_top = 1.0
	live_root.anchor_bottom = 1.0
	live_root.offset_bottom = -14
	live_root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	live_root.add_theme_constant_override("separation", 8)
	live_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(live_root)
	var lv := live_root as VBoxContainer
	cast_p = CombatUi.CastBar.new()
	cast_p.custom_minimum_size = Vector2(380, 26)
	cast_p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lv.add_child(cast_p)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(row)
	# counters
	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 4)
	row.add_child(dbox)
	var dl := UiKit.label("COUNTERS", 12, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	dl.autowrap_mode = TextServer.AUTOWRAP_OFF
	dbox.add_child(dl)
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 6)
	dbox.add_child(drow)
	for kind in RollSim.DEF_KINDS:
		var c: Color = CombatUi.KIND_COLORS[kind]
		var b := Button.new()
		b.text = "%s\n%s" % [RollSim.DEF_NAMES[kind], DEF_KEYS[kind]]
		b.custom_minimum_size = Vector2(74, 74)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_stylebox_override("normal", UiKit.box(c.darkened(0.6), 12, c, 2))
		b.add_theme_stylebox_override("hover", UiKit.box(c.darkened(0.4), 12, Color.WHITE, 2))
		b.add_theme_stylebox_override("pressed", UiKit.box(c.darkened(0.2), 12, Color.WHITE, 3))
		b.add_theme_stylebox_override("disabled", UiKit.box(Color(0.08, 0.08, 0.08, 0.9), 12, Color(c, 0.3), 2))
		b.tooltip_text = {"base": "Answers takedowns and sweeps (orange casts)", "frame": "Answers passes, back takes and escapes (blue casts)", "defend": "Answers submissions (red casts)"}[kind]
		b.pivot_offset = Vector2(37, 37)
		b.pressed.connect(_defend.bind(kind))
		drow.add_child(b)
		def_btns[kind] = b
	breathe_btn = Button.new()
	breathe_btn.text = "Breathe\nF"
	breathe_btn.custom_minimum_size = Vector2(74, 74)
	breathe_btn.focus_mode = Control.FOCUS_NONE
	breathe_btn.add_theme_font_size_override("font_size", 15)
	var bc: Color = CombatUi.KIND_COLORS.breathe
	breathe_btn.add_theme_stylebox_override("normal", UiKit.box(bc.darkened(0.65), 12, Color(bc, 0.7), 2))
	breathe_btn.add_theme_stylebox_override("hover", UiKit.box(bc.darkened(0.45), 12, Color.WHITE, 2))
	breathe_btn.add_theme_stylebox_override("disabled", UiKit.box(Color(0.08, 0.08, 0.08, 0.9), 12, Color(bc, 0.25), 2))
	breathe_btn.tooltip_text = "Recover stamina. Leaves you open for a moment."
	breathe_btn.pressed.connect(_breathe)
	drow.add_child(breathe_btn)
	# action bar
	var abox := VBoxContainer.new()
	abox.add_theme_constant_override("separation", 4)
	row.add_child(abox)
	var al := UiKit.label("TECHNIQUES", 12, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	al.autowrap_mode = TextServer.AUTOWRAP_OFF
	abox.add_child(al)
	bar_box = HBoxContainer.new()
	bar_box.add_theme_constant_override("separation", 6)
	abox.add_child(bar_box)

	struggle_panel = PanelContainer.new()
	struggle_panel.anchor_left = 0.5
	struggle_panel.anchor_right = 0.5
	struggle_panel.anchor_top = 0.5
	struggle_panel.anchor_bottom = 0.5
	struggle_panel.offset_left = -300
	struggle_panel.offset_right = 300
	struggle_panel.offset_top = 40
	struggle_panel.visible = false
	ui.add_child(struggle_panel)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	struggle_panel.add_child(sv)
	struggle_title = UiKit.label("", 24, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	sv.add_child(struggle_title)
	struggle_bar = UiKit.bar(UiKit.ACCENT, Vector2(540, 30))
	struggle_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sv.add_child(struggle_bar)
	struggle_btn = UiKit.button("SQUEEZE!", Vector2(400, 80))
	struggle_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	struggle_btn.focus_mode = Control.FOCUS_NONE
	struggle_btn.add_theme_font_size_override("font_size", 28)
	struggle_btn.button_down.connect(_struggle_tap)
	sv.add_child(struggle_btn)

	# end-of-match panel
	action_panel = PanelContainer.new()
	action_panel.anchor_left = 0.5
	action_panel.anchor_right = 0.5
	action_panel.anchor_top = 1.0
	action_panel.anchor_bottom = 1.0
	action_panel.offset_left = -360
	action_panel.offset_right = 360
	action_panel.offset_bottom = -16
	action_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	action_panel.visible = false
	ui.add_child(action_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	action_panel.add_child(v)
	action_title = UiKit.label("", 22, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(action_title)
	action_body = VBoxContainer.new()
	action_body.add_theme_constant_override("separation", 12)
	v.add_child(action_body)

	_build_intro_panel()
	_live_ui(false)

func _build_intro_panel() -> void:
	intro_panel = PanelContainer.new()
	intro_panel.anchor_left = 0.5
	intro_panel.anchor_right = 0.5
	intro_panel.anchor_top = 0.5
	intro_panel.anchor_bottom = 0.5
	intro_panel.offset_left = -330
	intro_panel.offset_right = 330
	intro_panel.offset_top = -40
	intro_panel.add_theme_stylebox_override("panel", UiKit.box(Color(0.04, 0.06, 0.05, 0.94), 16, UiKit.ACCENT, 2))
	ui.add_child(intro_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	intro_panel.add_child(v)
	v.add_child(UiKit.label("HOW TO ROLL", 26, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	for line in [
		"Your position is your stance: the technique bar changes with it.",
		"Grip abilities build GRIP CONTROL (◆). Techniques spend all of it: more grips, better odds, deeper submissions.",
		"Watch their cast bar and answer with the matching counter: BASE (orange), FRAME (blue), DEFEND (red).",
		"They can read you too. Bait their counter with a grip before you commit.",
		"Lock a submission? Mash SPACE to finish it, or to escape theirs.",
	]:
		v.add_child(UiKit.label("•  " + line, 16))
	v.add_child(UiKit.label("Keys: 1-8 techniques · Q/E/R counters · F breathe   ·   Pad: A/B/X/Y (LB for 5-8) · D-pad counters", 13, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label("Press any key to start", 14, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))

func _live_ui(on: bool) -> void:
	live_root.visible = on
	alert.visible = on

func _fighter_box(title: String, rank: int, is_player: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var st := UiKit.bar(UiKit.GREEN, Vector2(220, 12))
	st.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if is_player else Control.SIZE_SHRINK_END
	v.add_child(st)
	var pr := HBoxContainer.new()
	pr.alignment = BoxContainer.ALIGNMENT_BEGIN if is_player else BoxContainer.ALIGNMENT_END
	pr.add_theme_constant_override("separation", 8)
	v.add_child(pr)
	var pips := CombatUi.Pips.new()
	pips.right_to_left = not is_player
	pips.col = UiKit.ACCENT if is_player else Color(1, 0.55, 0.45)
	var status := UiKit.label("", 14, UiKit.RED)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	if is_player:
		pr.add_child(pips)
		pr.add_child(status)
	else:
		counter_ready = UiKit.label("", 13, Color(0.6, 0.85, 1))
		counter_ready.autowrap_mode = TextServer.AUTOWRAP_OFF
		pr.add_child(counter_ready)
		pr.add_child(status)
		pr.add_child(pips)
	var cb := CombatUi.CastBar.new()
	cb.custom_minimum_size = Vector2(300, 22)
	cb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if is_player else Control.SIZE_SHRINK_END
	cb.visible = false
	v.add_child(cb)
	if is_player:
		bar_pstam = st
		pips_p = pips
		stat_p = status
		cb.queue_free()
	else:
		bar_ostam = st
		pips_o = pips
		stat_o = status
		cast_o = cb
	return v

func _rebuild_bar() -> void:
	var bar := sim.player_bar()
	var key := "%s|%s|" % [sim.pos, sim.player_top]
	for s in bar:
		key += str(s.id) + ","
	if key == _bar_key:
		return
	_bar_key = key
	for c in bar_box.get_children():
		c.queue_free()
	slots.clear()
	var pad := not Input.get_connected_joypads().is_empty()
	for i in bar.size():
		var s: Dictionary = bar[i]
		var sl := CombatUi.Slot.new()
		sl.id = s.id
		sl.title = s.name
		sl.kind = s.kind
		sl.req = int(s.req)
		sl.cd_max = float(s.cd)
		sl.signature = s.id in _signature
		sl.key = CombatUi.PAD_LABELS[i] if pad else str(i + 1)
		var m_desc := ""
		if s.kind == "move":
			var m: Dictionary = Data.MOVES[s.id]
			m_desc = "%s · %s · needs %d grip%s%s" % [str(m.type).capitalize(), RollSim.DEF_NAMES[RollSim.counter_kind(s.id)] + "-able", int(s.req), "" if int(s.req) == 1 else "s", ("  ·  +%d pts" % int(m.pts)) if int(m.pts) > 0 else ""]
		elif s.kind == "grip":
			m_desc = "+1 Grip Control (+2 if they are off-balance)"
		else:
			m_desc = "Drains their stamina and strips a grip"
		sl.tooltip_text = "%s\n%s" % [s.name, m_desc]
		sl.pressed_slot.connect(_use)
		bar_box.add_child(sl)
		slots.append(sl)
	if phase == Phase.LIVE:
		var t := create_tween()
		bar_box.modulate.a = 0.3
		t.tween_property(bar_box, "modulate:a", 1.0, 0.25)

func _refresh_hud() -> void:
	lbl_clock.text = sim.clock_text()
	lbl_pos.text = Data.role_label(sim.pos, sim.player_top)
	lbl_ppts.text = "%d" % sim.player_pts + ("  A%d" % sim.player_adv if sim.player_adv > 0 else "")
	lbl_opts.text = ("A%d  " % sim.opp_adv if sim.opp_adv > 0 else "") + "%d" % sim.opp_pts
	bar_pstam.max_value = sim.max_stamina
	bar_pstam.value = sim.stamina
	bar_ostam.value = sim.opp_stamina
	var low := sim.stamina_pct() < 25.0
	bar_pstam.add_theme_stylebox_override("fill", UiKit.box(UiKit.RED if low else UiKit.GREEN, 6))
	pips_p.n = sim.control
	pips_o.n = sim.opp_control
	stat_p.text = "OFF-BALANCE" if sim.off_bal > 0.0 else ""
	stat_o.text = "OFF-BALANCE" if sim.opp_off_bal > 0.0 else ""
	stat_o.add_theme_color_override("font_color", Color(0.5, 1, 0.6))
	counter_ready.text = "◆ Counter ready" if sim.opp_counter_cd <= 0.0 else "Counter %.0fs" % ceilf(sim.opp_counter_cd)
	counter_ready.modulate.a = 1.0 if sim.opp_counter_cd <= 0.0 else 0.45
	if phase != Phase.LIVE:
		return
	_rebuild_bar()
	var bar := sim.player_bar()
	for i in mini(slots.size(), bar.size()):
		var sl: CombatUi.Slot = slots[i]
		var s: Dictionary = bar[i]
		sl.have = sim.control
		var cd := sim.cooldown(sl.id)
		sl.cd = maxf(cd, sim.gcd)
		sl.cd_max = float(s.cd) if cd >= sim.gcd else RollSim.GCD
		sl.usable = sim.control >= int(s.req) and sim.stamina >= float(s.cost) * 0.5
		sl.casting = not sim.cast.is_empty() and sim.cast.id == sl.id
	# cast bars
	cast_p.visible = not sim.cast.is_empty() or cast_p.interrupted > 0.0
	if not sim.cast.is_empty():
		cast_p.t = float(sim.cast.t)
		cast_p.dur = float(sim.cast.dur)
	cast_o.visible = not sim.opp_cast.is_empty() or cast_o.interrupted > 0.0
	if not sim.opp_cast.is_empty():
		cast_o.t = float(sim.opp_cast.t)
		cast_o.dur = float(sim.opp_cast.dur)
	var big: bool = not sim.opp_cast.is_empty() and sim.opp_cast.kind == "move"
	alert.visible = (big or alert.interrupted > 0.0) and alert.title != ""
	if big:
		alert.t = float(sim.opp_cast.t)
		alert.dur = float(sim.opp_cast.dur)
	for k in def_btns:
		(def_btns[k] as Button).disabled = sim.def_cd > 0.0
	breathe_btn.disabled = sim.cooldown("breathe") > 0.0
	if not sim.struggle.is_empty():
		struggle_bar.value = float(sim.struggle.value) * 100.0

func _clear_action() -> void:
	for c in action_body.get_children():
		c.queue_free()
