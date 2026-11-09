extends Node
## Scene flow: title -> explore Cáceres <-> roll on the mat.

var world: World
var player: Player
var hud: Hud
var roll: RollScene
var combat: WorldCombat   # WoW-style open-world fights (mobs, named fighters)
var _talking_to: Npc
var _title_cam: Camera3D
var _title_t := 0.0
var _in_title := true
var _drill: DrillScene
var _pending_spot: Dictionary = {}

func _ready() -> void:
	_register_inputs()
	get_tree().root.size_changed.connect(_fit_screen)
	_fit_screen()
	player = Player.new()
	player.jumped.connect(func():
		Game.bump("jumper")
		Sfx.play("jump", -8.0))
	_make_world(Game.zone if Data.ZONES.has(Game.zone) else "caceres")

	hud = Hud.new()
	add_child(hud)
	hud.touch.player = player
	player.clicked.connect(_on_world_click)
	hud.minimap.set_world(world, player)
	hud.touch.jump_pressed.connect(player.do_jump)
	player.zoom_blocked = func() -> bool: return hud.dialogue_open() or hud.journal.visible or hud.minimap.big or hud.settings_open()
	hud.touch.interact_pressed.connect(_interact)
	hud.touch.journal_pressed.connect(hud.toggle_journal)
	hud.play_pressed.connect(_start_game)
	hud.travel_chosen.connect(func(z: String):
		player.input_enabled = true
		if z != "":
			_travel(z))
	hud.daily_requested.connect(_start_daily)
	hud.shop_closed.connect(func(): player.input_enabled = true)
	hud.dialogue_choice.connect(_on_dialogue_choice)
	hud.graphics_changed.connect(func(): if is_instance_valid(world): world.apply_graphics())
	hud.barber_requested.connect(open_barber)
	hud.journal_toggled.connect(func(open): player.input_enabled = not open and not _in_title)
	Game.progress_changed.connect(func(): if is_instance_valid(world): world.refresh_beacon())

	_title_cam = Camera3D.new()
	_title_cam.fov = 55
	_title_cam.far = 400
	world.add_child(_title_cam)
	_title_cam.make_current()
	_fit_screen()
	# web: hint to the browser that loading finished
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__tatameReady = true;")
	_hook_net()
	gm_panel = GmPanel.new()
	gm_panel.main = self
	hud.root.add_child(gm_panel)
	hud.combat_log.gm_requested.connect(gm_panel.toggle)
	if OS.get_cmdline_user_args().has("--autoplay") or Game.boot_into:
		Game.boot_into = false
		_start_game.call_deferred()
	_dev_hash()

## QA shortcuts via URL hash, e.g. index.html#roll=rafa or #tp=-36,52
func _dev_hash() -> void:
	if not OS.has_feature("web"):
		return
	var h := str(JavaScriptBridge.eval("window.location.hash || ''"))
	# QA only, behind a key: nobody skips the line on a real character (and QA sessions never save)
	if h == "" or not h.contains("qa=" + Data.QA_KEY):
		return
	Game.test_mode = true  # never save QA sessions
	var style_q := "guard"
	for part in h.trim_prefix("#").split("&"):
		if part.begins_with("style="):
			style_q = part.trim_prefix("style=")
	if not h.contains("create=1"):
		Game.choose_style(style_q, "Gringo", 0)
		for part in h.trim_prefix("#").split("&"):
			if part.begins_with("lvl="):
				Game.set_level(int(part.trim_prefix("lvl=")))
				Game.progress_changed.emit()
	_start_game()
	hud._close_dialogue(false)
	for part in h.trim_prefix("#").split("&"):
		var kv := part.split("=")
		if kv.size() != 2:
			continue
		if kv[0] == "roll" and Data.OPPONENTS.has(kv[1]):
			_start_roll(kv[1])
		elif kv[0] == "tp":
			var xz := kv[1].split(",")
			var x := float(xz[0])
			var z := float(xz[1])
			player.teleport(Vector3(x, world.ground_y(x, z) + 1.0, z), float(xz[2]) if xz.size() > 2 else 0.0)
		elif kv[0] == "pos" and roll:
			roll.sim.pos = kv[1]
			roll.sim.player_top = not h.contains("bottom")
			roll._pose_now(0.01)
		elif kv[0] == "atk" and roll:
			roll._opponent_attack()
		elif kv[0] == "sub" and roll:
			roll._start_struggle(kv[1] != "def", "triangle")
		elif kv[0] == "zone" and Data.ZONES.has(kv[1]):
			Game.promote_belt(maxi(Game.belt_index(), int(Data.ZONES[kv[1]].rank) / 5))
			_travel(kv[1])
			hud._close_dialogue(false)
		elif kv[0] == "busmenu":
			hud.open_travel()
		elif kv[0] == "daily":
			_start_daily()
		elif kv[0] == "drill" and Rpg.DRILLS.has(kv[1]):
			_start_drill(kv[1])
		elif kv[0] == "journal":
			hud.toggle_journal()
		elif kv[0] == "char":
			hud._sel_talent = kv[1] if not TalentTrees.node(kv[1]).is_empty() else ""
			hud._want_tab = 1 if hud._sel_talent != "" else 0
			hud.toggle_journal()

## Portrait phones get a portrait base resolution so the UI stays readable.
func _fit_screen() -> void:
	var win := get_tree().root
	var sz := win.size
	var portrait := sz.y > sz.x
	win.content_scale_size = Vector2i(540, 960) if portrait else Vector2i(1280, 720)
	if hud:
		hud.set_portrait(portrait)
	for cam in [_title_cam, player.cam if player else null, roll.cam if roll else null]:
		if cam and is_instance_valid(cam):
			cam.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
			cam.fov = 75.0 if portrait else 60.0

func _register_inputs() -> void:
	var map := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"look_left": [], "look_right": [], "look_up": [KEY_PAGEUP], "look_down": [KEY_PAGEDOWN],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "autorun": [KEY_X, KEY_NUMLOCK], "map": [KEY_M], "interact": [KEY_E],
		"journal": [KEY_J, KEY_L], "target_next": [KEY_TAB],
		"ab_0": [KEY_1], "ab_1": [KEY_2], "ab_2": [KEY_3], "ab_3": [KEY_4], "ab_4": [KEY_5], "ab_5": [KEY_6],
		"ab_6": [KEY_7], "ab_7": [KEY_8], "ab_8": [KEY_9], "ab_9": [KEY_0],
		"ab_base": [KEY_Q], "ab_frame": [KEY_R], "ab_defend": [KEY_T], "ab_breathe": [KEY_F], "ab_racial": [KEY_G], "character": [KEY_C], "talents": [KEY_N], "spellbook": [KEY_P], "confirm": [KEY_SPACE, KEY_ENTER], "bags": [KEY_B, KEY_I],
		"dir_up": [KEY_UP, KEY_W], "dir_down": [KEY_DOWN, KEY_S], "dir_left": [KEY_LEFT, KEY_A], "dir_right": [KEY_RIGHT, KEY_D],
		"pause": [KEY_ESCAPE],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.3)
		for key in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	# gamepad basics
	var pad := {"jump": JOY_BUTTON_A, "interact": JOY_BUTTON_X, "confirm": JOY_BUTTON_A, "journal": JOY_BUTTON_BACK,
		"dir_up": JOY_BUTTON_DPAD_UP, "dir_down": JOY_BUTTON_DPAD_DOWN, "dir_left": JOY_BUTTON_DPAD_LEFT, "dir_right": JOY_BUTTON_DPAD_RIGHT}
	for action in pad:
		var jb := InputEventJoypadButton.new()
		jb.button_index = pad[action]
		InputMap.action_add_event(action, jb)
	for pair in [["move_left", JOY_AXIS_LEFT_X, -1.0], ["move_right", JOY_AXIS_LEFT_X, 1.0], ["move_forward", JOY_AXIS_LEFT_Y, -1.0], ["move_back", JOY_AXIS_LEFT_Y, 1.0],
			["look_left", JOY_AXIS_RIGHT_X, -1.0], ["look_right", JOY_AXIS_RIGHT_X, 1.0], ["look_up", JOY_AXIS_RIGHT_Y, -1.0], ["look_down", JOY_AXIS_RIGHT_Y, 1.0]]:
		var jm := InputEventJoypadMotion.new()
		jm.axis = pair[1]
		jm.axis_value = pair[2]
		InputMap.action_add_event(pair[0], jm)

var _dbg_t := 0.0

func _process(delta: float) -> void:
	if OS.has_feature("web") and Game.test_mode:
		_dbg_t += delta
		if _dbg_t > 0.5:
			_dbg_t = 0.0
			var p := player.global_position
			JavaScriptBridge.eval("window.__tatameDebug = {x:%.2f,y:%.2f,z:%.2f,fps:%d,roll:%s,phase:%d,input:%s,touch:%s,tsa:%s};" % [p.x, p.y, p.z, Engine.get_frames_per_second(), "true" if roll else "false", roll.phase if roll else -1, "true" if player.input_enabled else "false", "true" if hud.touch.visible else "false", "true" if DisplayServer.is_touchscreen_available() else "false"])
	if _in_title:
		_title_t += delta * 0.07
		var c := Vector3(0, 0, -10)
		_title_cam.position = c + Vector3(sin(_title_t) * 42.0, 16.0, cos(_title_t) * 42.0)
		_title_cam.look_at(c + Vector3(0, 4, 0), Vector3.UP)
	_mouse_process()
	if hud and combat and hud.combat_hud == null:
		hud.set_combat(combat)
	if not _in_title and roll == null:
		_adapt_quality(delta)
	if not _in_title and is_instance_valid(player) and player.get_parent() == world:
		var hs := Vector2(player.velocity.x, player.velocity.z).length()
		Net.update(player.global_position, player.rig.rotation.y, clampf(hs / Player.RUN, 0.0, 1.0), not player.is_on_floor(),
			combat != null and combat.me != null and combat.me.in_combat, delta)

# ------------------------------------------------------------ live world: other players + chat
var remotes := {}   # net id -> RemotePlayer
var gm_panel: GmPanel

func _hook_net() -> void:
	Net.leave_world()
	Net.joined.connect(func(id: int, d: Dictionary):
		if not is_instance_valid(world) or str(d.get("zone", Net.zone)) != world.zone:
			return
		if remotes.has(id) and is_instance_valid(remotes[id]):
			remotes[id].queue_free()
		var rp := RemotePlayer.new().setup(id, d)
		world.add_child(rp)
		remotes[id] = rp)
	Net.left.connect(func(id: int):
		if remotes.has(id):
			if is_instance_valid(remotes[id]):
				remotes[id].queue_free()
			remotes.erase(id))
	Net.moved.connect(func(rows: Array):
		for r in rows:
			var rp = remotes.get(int(r[0]))
			if rp and is_instance_valid(rp):
				rp.net_state(float(r[1]), float(r[2]), float(r[3]), float(r[4]), float(r[5]), bool(r[6]), bool(r[7])))
	Net.char_changed.connect(func(id: int, ch: Dictionary):
		var rp = remotes.get(id)
		if rp and is_instance_valid(rp):
			rp.set_char(ch))
	Net.chat.connect(func(m: Dictionary):
		if str(m.get("ch", "")) == "say" and remotes.has(int(m.get("fid", 0))):
			var rp = remotes[int(m.fid)]
			if is_instance_valid(rp):
				rp.say(str(m.get("text", ""))))

func _clear_remotes() -> void:
	for id in remotes:
		if is_instance_valid(remotes[id]):
			remotes[id].queue_free()
	remotes.clear()

func _start_game() -> void:
	Sfx.music("explore")
	_in_title = false
	hud.hide_title()
	world.game_started = true
	player.make_current()
	Net.enter(world.zone)
	if Game.style == "":
		_show_style_select()
		return
	_begin_play()

func _show_style_select() -> void:
	player.input_enabled = false
	hud.set_exploring(false)
	var sel := StyleSelect.new()
	sel.theme = UiKit.theme()
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	layer.add_child(sel)
	sel.chosen.connect(func(id: String, nm: String, gi: int):
		Game.choose_style(id, nm, gi)
		player.refresh_look()
		layer.queue_free()
		hud.set_exploring(true)
		hud.refresh()
		_begin_play())

## Barber: re-style the fighter without starting over.
func open_barber() -> void:
	if hud.dialogue_open():
		return
	player.input_enabled = false
	var sel := StyleSelect.new()
	sel.barber = true
	sel.theme = UiKit.theme()
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	layer.add_child(sel)
	var done := func():
		layer.queue_free()
		player.input_enabled = true
		player.refresh_look()
		if combat:
			combat.rebuild_player()
		hud.refresh()
	sel.edited.connect(func():
		done.call()
		hud.show_toast("Fresh look. Seu Zé approves.", Wow.GOLD))
	sel.cancelled.connect(done)

func _begin_play() -> void:
	player.input_enabled = true
	if Game.flags.get("spec_reset", false):
		Game.flags.erase("spec_reset")
		Game.save_game()
		hud.open_dialogue("Professor Gil", "Coaching is a Guard Player and Judoka thing now: those are the only classes that can take the Professor spec. Your spec has been reset, so pick a new one from the Talents window (N). No charge.", "", "Oss")
	if Game.xp == 0 and not Game.flags.get("intro_seen", false):
		Game.flags["intro_seen"] = true
		Game.save_game()
		hud.open_dialogue("Cáceres, Mato Grosso",
			"You just moved to town with a white belt and a dream. Follow the golden light: there's a guy in the plaza who rolls every afternoon. Win rolls, earn stripes, and find the academia.",
			"", "Let's go")

# ------------------------------------------------------------ mouse: hover + click to interact
var _hover: Npc = null

## Fighter or quest giver under the mouse (screen-space pick around their chest/head).
func _npc_at(screen: Vector2) -> Npc:
	if world == null or player == null:
		return null
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var best: Npc = null
	var bd := 42.0
	var cands: Array = world.fighters.values() + world.quest_givers.values()
	for n in cands:
		var npc := n as Npc
		var wp := npc.global_position + Vector3(0, 1.3, 0)
		if cam.is_position_behind(wp) or wp.distance_to(cam.global_position) > 60.0:
			continue
		var sp := cam.unproject_position(wp)
		var d := sp.distance_to(screen)
		var reach := bd * clampf(12.0 / maxf(wp.distance_to(cam.global_position), 1.0), 0.5, 2.0)
		if d < reach and d < bd * 2.0:
			bd = d
			best = npc
	return best

# Ultra steps down to High once if the frame rate stays low (unless the player picked it).
var _slow_t := 0.0

func _adapt_quality(delta: float) -> void:
	if Game.graphics_level() != 2 or Sfx.pref("gfx_manual", false) or Game.test_mode:
		return
	var fps := Engine.get_frames_per_second()
	_slow_t = _slow_t + delta if fps > 0 and fps < 30 else maxf(0.0, _slow_t - delta * 2.0)
	if _slow_t > 6.0:
		_slow_t = 0.0
		Game.set_graphics_level(1, false)
		if is_instance_valid(world):
			world.apply_graphics()
		hud.gfx_btn.text = "Gfx: high"
		Game.toast.emit("Graphics lowered to High for smoother play", UiKit.MUTED)

func _mouse_process() -> void:
	if _in_title or roll != null or hud == null or not player.input_enabled or hud.touch.visible:
		if _hover != null:
			_hover = null
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			hud.set_hover("")
		return
	var h := _npc_at(get_viewport().get_mouse_position())
	if h != _hover:
		_hover = h
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if h else Input.CURSOR_ARROW)
		if h == null:
			hud.set_hover("")
		elif h.giver_id != "":
			hud.set_hover("%s  ·  click to talk" % h.display_name)
		else:
			var o: Dictionary = Data.OPPONENTS[h.opp_id]
			hud.set_hover("%s  ·  Lv %d  ·  click to roll" % [o.name, Data.display_level(float(o.level))])
	if _hover:
		hud.place_hover(get_viewport().get_mouse_position())
	# walking to a clicked NPC: interact on arrival
	if player.walk_target != null and is_instance_valid(player.walk_target):
		if player.global_position.distance_to(player.walk_target.global_position) < 2.6:
			var t: Npc = player.walk_target
			player.walk_target = null
			_interact(t)

func _on_world_click(screen: Vector2) -> void:
	if roll != null or hud.dialogue_open() or hud.journal.visible or hud.minimap.big:
		return
	var n := _npc_at(screen)
	if n == null:
		return
	if combat and combat.is_hostile(n):
		combat.set_target_npc(n)   # click a mob to target it (WoW); press an ability to attack
		return
	if player.global_position.distance_to(n.global_position) < 2.8:
		_interact(n)
	else:
		player.walk_target = n
		Game.toast.emit("Walking to %s..." % n.display_name, UiKit.MUTED)

func _unhandled_input(event: InputEvent) -> void:
	if _in_title or roll != null or Game.style == "":
		return
	# Ctrl+G: Game Master window (only opens for server-confirmed GM accounts)
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_G and (event as InputEventKey).ctrl_pressed:
		gm_panel.toggle()
		get_viewport().set_input_as_handled()
		return
	# Enter (or /) opens chat, like WoW
	if event is InputEventKey and event.pressed and not event.echo and hud.combat_log and not hud.dialogue_open():
		var k: int = (event as InputEventKey).keycode
		if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SLASH:
			hud.combat_log.open_input("/" if k == KEY_SLASH else "")
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("journal") and not hud.dialogue_open():
		hud.open_window("journal")
	elif event.is_action_pressed("talents") and not hud.dialogue_open():
		hud.open_window("talents")
	elif event.is_action_pressed("spellbook") and not hud.dialogue_open():
		hud.open_window("talents", Hud.TAB_SPELLBOOK)
	elif event.is_action_pressed("character") and not hud.dialogue_open():
		hud.open_window("character")
	elif event.is_action_pressed("bags") and not hud.dialogue_open() and not hud.journal.visible:
		hud.toggle_bag()
	elif event.is_action_pressed("pause") and hud.shop_open():
		hud.close_shop()
	elif event.is_action_pressed("pause") and hud.bag_panel.visible:
		hud.bag_panel.visible = false
	elif event.is_action_pressed("interact") and not hud.dialogue_open() and not hud.journal.visible and not hud.shop_open():
		_interact()
	elif event.is_action_pressed("map") and not hud.dialogue_open() and not hud.journal.visible:
		hud.minimap.toggle_big()
		player.input_enabled = not hud.minimap.big
	elif event.is_action_pressed("pause") and hud.minimap.big:
		hud.minimap.toggle_big()
		player.input_enabled = true
	elif event.is_action_pressed("pause") and hud.journal.visible:
		hud.toggle_journal()
	elif event.is_action_pressed("pause") and not hud.dialogue_open() and not hud.travel_open():
		hud.toggle_settings()

func _make_world(z: String) -> void:
	if is_instance_valid(world):
		if player.get_parent() == world:
			world.remove_child(player)
		if is_instance_valid(_title_cam) and _title_cam.get_parent() == world:
			world.remove_child(_title_cam)
		world.queue_free()
	world = World.new()
	add_child(world)
	world.build(z)
	world.game_started = false
	if not _in_title:
		for tid in Game.expire_territories():
			Game.toast.emit("%s fell to %s while you were away." % [Data.TERRITORIES[tid].name, Data.TERRITORIES[tid].academy], UiKit.RED)
		world.refresh_flags()
		for tid in Data.territories_in(z):
			if Game.territory_state(tid) == "attacked":
				Game.toast.emit("%s is attacking %s! Defend it within %dh." % [Data.TERRITORIES[tid].academy, Data.TERRITORIES[tid].name, maxi(1, Game.defend_left(tid) / 3600)], Color(1, 0.45, 0.35))
	if not _in_title:
		# let physics settle at the new spawn before landmarks/collectibles can trigger
		get_tree().create_timer(0.6).timeout.connect(func(): if is_instance_valid(world): world.game_started = true)
	var sp: Vector3 = Data.ZONES[z].spawn
	var spawn := Vector3(sp.x, world.ground_y(sp.x, sp.z) + 0.5, sp.z)
	player.position = spawn
	world.add_child(player)
	player.teleport(spawn, PI / 2 if z in ["pantanal", "rio"] else 0.0)
	world.attach_player(player)
	if hud:
		hud.minimap.set_world(world, player)
	Sfx.ambience(z)
	world.nearby_changed.connect(_on_nearby)
	world.spot_changed.connect(_on_spot)
	world.mob_engaged.connect(_on_mob_engaged)
	if combat == null:
		combat = WorldCombat.new()
		combat.name = "WorldCombat"
		add_child(combat)
		combat.setup(world, player)
		combat.player_tapped.connect(_on_player_tapped)
		combat.duel_over.connect(_after_duel)
		combat.bout_over.connect(_on_bout_over)
		combat.raid_over.connect(_on_raid_over)
		combat.raid_warning.connect(func(h, sb): hud.combat_hud.flash(h, sb) if hud.combat_hud else null)
	else:
		combat.set_world(world)
	if hud:
		hud.set_combat(combat)
	if is_instance_valid(_title_cam):
		world.add_child(_title_cam)
	_clear_remotes()
	if not _in_title:
		Net.enter(z)

func _travel(z: String) -> void:
	# open world: nobody stops you, but the driver will tell you what you're in for
	var lo := int(Data.ZONES[z].levels[0])
	if Game.player_level() < lo - 2:
		Game.toast.emit("Careful: %s is a level %s zone and you're level %d. Locals there hit hard." % [Data.ZONES[z].name, Data.zone_levels(z).trim_prefix("Lv "), Game.player_level()], Color(1.0, 0.5, 0.35))
	Game.zone = z
	Game.save_game()
	_make_world(z)
	player.make_current()
	player.input_enabled = true
	hud.set_prompt(null)
	hud.refresh()
	var zd: Dictionary = Data.ZONES[z]
	Game.toast.emit("%s  ·  %s  ·  %s" % [zd.name, zd.sub, Data.zone_levels(z)], UiKit.ACCENT)
	if z == "pantanal":
		Game.unlock("travel")
		if not Game.flags.get("pantanal_intro", false):
			Game.flags["pantanal_intro"] = true
			Game.save_game()
			hud.open_dialogue("Pantanal Norte", "The world's biggest wetland. Jaguars, jacarés, and the toughest open mats in Mato Grosso. Mestre Jacaré runs the fazenda gym to the northeast. Beat %d locals to earn a roll with him." % Data.BOSS_REQUIRED_WINS, "", "Vamos")

	if z == "rio" and not Game.flags.get("rio_intro", false):
		Game.flags["rio_intro"] = true
		Game.save_game()
		hud.open_dialogue("Rio de Janeiro", "The city where jiu-jitsu grew up. Train on the sand at Copacabana, roll with the kids on the morro, and climb Corcovado if your legs still work. Grão-Mestre Leão gives black belts at his academia behind the beach. Beat %d locals first." % Data.BOSS_REQUIRED_WINS, "", "Oss")

func _on_nearby(npc: Npc) -> void:
	hud.set_prompt(npc)
	if npc == null:
		_on_spot(world.nearby_spot)

func _on_spot(spot: Dictionary) -> void:
	if world.nearby != null:
		return
	hud.set_spot_prompt(spot)

func _use_spot(spot: Dictionary) -> void:
	match spot.action:
		"travel":
			_travel(spot.arg)
		"travel_menu":
			player.input_enabled = false
			hud.open_travel()
		"daily":
			_start_daily()
		"comp":
			_open_comp(spot.arg)
		"team":
			_open_team(str(spot.arg))
		"circuit":
			_open_circuit()
		"territory":
			_open_territory(str(spot.arg))
		"quest":
			_open_quest(spot.arg)
		"vendor":
			player.input_enabled = false
			hud.open_shop(str(spot.arg))
		"barber":
			open_barber()
		"chest":
			_open_chest(str(spot.arg), spot)
		"job":
			_open_job(str(spot.arg))
		"raid":
			_raid_prompt = true
			player.input_enabled = false
			hud.open_dialogue("Covil da Sucuri", "Grão-Mestre Sucuri took over the old gym and he's teaching his students to crush everyone in town. Five fighters walk in: you and four academy partners who fill the roles you don't (a tank to hold him, Professor Gil to keep you in it, finishers).\n\nHis Crushing Kesa flattens whoever he's fighting. When he starts his Takedown Wave, SPRAWL (Q) or the whole party goes down. At 60%% and 30%% his students come for your Professor.\n\nScaled to your level. Tap and the whole party resets.", "Gather the party", "Not now")
		"drill":
			if not Game.drills_ready:
				hud.open_dialogue("Coach", "You're cooked. Go roll with someone, then come back and drill.", "", "Oss")
				return
			_start_drill(spot.arg)

## Hidden chest: money, food, maybe a bag or rolled gear; XP the first time you find it.
func _open_chest(id: String, spot: Dictionary) -> void:
	var loot: Dictionary = world.chests.open(id)
	if loot.is_empty():
		Game.toast.emit("Empty. Someone beat you to it: it refills in %dh." % ceili(Chests.refill_left(id) / 3600.0), Wow.GREY)
		return
	Sfx.play("collect", -4.0)
	Game.money += int(loot.money)
	var got: Array = []
	for it in loot.items:
		if Game.add_item(str(it)) == 0:
			got.append(str(it))
		else:
			Game.toast.emit("Bags full: %s left in the chest." % str(Loot.item(str(it)).get("name", it)), UiKit.RED)
	Game.toast.emit("%s! R$ %d" % ["Golden chest" if loot.golden else "Hidden chest", int(loot.money)], Color(1, 0.85, 0.35))
	for it in got:
		Game.toast.emit("Looted: %s" % str(Loot.item(it).get("name", it)), Loot.color(it))
	if loot.first:
		Game.add_xp(int(loot.xp))
		Game.toast.emit("Discovered! +%d XP  ·  hidden chests in %s: %d/%d" % [int(loot.xp), Data.ZONES[world.zone].name, world.chests.found_count(), world.chests.chests.size()], UiKit.ACCENT)
		Game.unlock("chest_first")
		if world.chests.found_count() >= world.chests.chests.size():
			Game.unlock("chest_zone")
	Game.bump("chest_hunter")
	Game.save_game()
	hud.set_spot_prompt(spot)
	hud.refresh()

# ------------------------------------------------------------ quests
var _quest_prompt := ""  # "offer:<id>" / "turnin:<id>" / "info" while a quest dialogue is open

func _open_quest(giver: String) -> void:
	var g: Dictionary = Data.QUEST_GIVERS[giver]
	var ids := Data.quests_of(giver)
	player.input_enabled = false
	for id in ids:
		if Game.quest_ready(id):
			var q: Dictionary = Data.QUESTS[id]
			_quest_prompt = "turnin:" + id
			hud.open_dialogue(g.name, "%s\n\n%s\n\nReward: %d XP" % [q.title.to_upper(), q.done, int(q.xp)], "Complete quest", "Later")
			return
	for id in ids:
		if Game.quest_state(id) == "active":
			var q: Dictionary = Data.QUESTS[id]
			var lines: Array[String] = [q.title.to_upper(), ""]
			for i in q.obj.size():
				var pr := Game.objective_progress(id, i)
				lines.append("•  %s: %d/%d" % [q.obj[i].text, pr[0], pr[1]])
			_quest_prompt = "info"
			hud.open_dialogue(g.name, "\n".join(lines) + "\n\nCome back when it's done.", "", "Okay")
			return
	for id in ids:
		if Game.quest_available(id):
			var q: Dictionary = Data.QUESTS[id]
			var objs: Array[String] = []
			for o in q.obj:
				objs.append("•  " + str(o.text))
			_quest_prompt = "offer:" + id
			hud.open_dialogue(g.name, "%s\n\n%s\n\n%s\nReward: %d XP" % [q.title.to_upper(), q.offer, "\n".join(objs), int(q.xp)], "Accept", "Not now")
			return
	for id in ids:
		if Game.quest_locked_by_level(id):
			_quest_prompt = "info"
			hud.open_dialogue(g.name, "I might have something for you later. Come back at level %d." % int(Data.QUESTS[id].min_level), "", "Okay")
			return
	_quest_prompt = "info"
	hud.open_dialogue(g.name, "Obrigado for everything, gringo. Oss!", "", "Oss")

# ------------------------------------------------------------ competitions
var comp_run: Dictionary = {}   # the bracket in progress (see Data.comp_bracket)
var _comp_prompt := ""          # "enter" / "next" / "done" while a comp dialogue is open

func _open_comp(comp_id: String) -> void:
	var c: Dictionary = Data.COMPS[comp_id]
	if Game.rank < int(c.min_rank):
		hud.open_dialogue(c.name, "%s\n\nBlack belts only. Come back when Leão ties one around your waist." % c.blurb, "", "Okay")
		return
	var nonce := int(Game.counters.get("comp_entries", 0))
	comp_run = Data.comp_bracket(comp_id, Game.rank, Game.player_name, nonce)
	var belt: String = Data.BELTS[comp_run.belt].name
	var best := Game.best_medal(comp_id)
	var lines: Array[String] = [c.blurb, "", "Division: %s Belt  ·  %d in the bracket" % [belt, comp_run.entries.size()]]
	if best != "":
		lines.append("Your best here at %s belt: %s" % [belt.to_lower(), best.capitalize()])
	lines.append("")
	lines.append("First round: %s (%s)" % [comp_run.path[0].name, comp_run.path[0].academy])
	lines.append("Lose once and you're out. Win the final for gold.")
	_comp_prompt = "enter"
	player.input_enabled = false
	hud.open_dialogue(c.name, "\n".join(lines), "Enter the bracket", "Not now")

func _comp_start_match() -> void:
	if comp_run.round == 0:
		Game.counters["comp_entries"] = int(Game.counters.get("comp_entries", 0)) + 1
	var rd: int = comp_run.round
	var m := {"id": comp_run.id, "round_name": Data.round_name(comp_run.rounds, rd), "opp": comp_run.path[rd], "final": rd == comp_run.rounds - 1}
	Game.toast.emit("%s: %s (%s)" % [m.round_name, m.opp.name, str(m.opp.get("academy", ""))], Color(1, 0.85, 0.35))
	_bout(m.opp, "comp", bool(m.final))

func _comp_after_match(result: Dictionary) -> void:
	var c: Dictionary = Data.COMPS[comp_run.id]
	var rd: int = comp_run.round
	var rounds: int = comp_run.rounds
	var medal := ""
	if result.won and rd == rounds - 1:
		medal = "gold"
	elif not result.won and rd == rounds - 1:
		medal = "silver"
	elif not result.won and rd == rounds - 2:
		medal = "bronze"
	if result.won and rd < rounds - 1:
		comp_run.round = rd + 1
		var nxt: Dictionary = comp_run.path[rd + 1]
		_comp_prompt = "next"
		player.input_enabled = false
		hud.open_dialogue(c.name, "%s won!\n\nNext up, the %s: %s (%s), %s guy." % [Data.round_name(rounds, rd), Data.round_name(rounds, rd + 1).to_lower(), nxt.name, nxt.academy, nxt.style], "Next match", "Withdraw")
		return
	var belt: int = comp_run.belt
	var text := ""
	if medal != "":
		var xp := Game.award_medal(comp_run.id, belt, medal)
		Sfx.play("win" if medal == "gold" else "levelup")
		var head: String = {"gold": "GOLD MEDAL! Campeão!", "silver": "SILVER MEDAL", "bronze": "BRONZE MEDAL"}[medal]
		var body: String = {"gold": "Top of the podium at the %s. The whole academy is in the group chat." % c.name,
			"silver": "Lost a tough final, but you're on the podium at the %s." % c.name,
			"bronze": "Semifinal loss, but bronze at the %s is a real medal. Shake it off, oss." % c.name}[medal]
		text = "%s\n\n%s\n\n+%d XP" % [head, body, xp]
	else:
		text = "Out in the %s. It happens to everyone; the bracket resets next time you enter." % Data.round_name(rounds, rd).to_lower()
	comp_run = {}
	_comp_prompt = "done"
	player.input_enabled = false
	hud.open_dialogue(c.name, text, "", "Oss")

# ------------------------------------------------------------ 5v5 team challenge
var team_match: Team.Match = null
var team_board: TeamBoard

var _territory_prompt := ""

## A territory flag: take it (3v3 vs the holding academy), defend it, or check on it.
func _open_territory(tid: String) -> void:
	var t: Dictionary = Data.TERRITORIES[tid]
	var st := Game.territory_state(tid)
	player.input_enabled = false
	match st:
		"rival":
			_territory_prompt = tid
			hud.open_dialogue("Territory: %s" % t.name, "%s plant their flag here. Take it with a 3v3: their best three against your first three (set your lineup on any Team Challenge board).\n\nHold it for +10%% XP from rolls in %s. Rivals will come back for it." % [t.academy, Data.ZONES[t.zone].name], "Challenge for the flag", "Not now")
		"attacked":
			_territory_prompt = tid
			hud.open_dialogue("Territory: %s" % t.name, "%s are back for %s! Defend it in a 3v3 within %dh or the flag falls." % [t.academy, t.name, maxi(1, Game.defend_left(tid) / 3600)], "Defend it", "Later")
		_:
			var left := int(Game.territories[tid].attack_at) - Game.now()
			hud.open_dialogue("Territory: %s" % t.name, "Gringo BJJ holds %s. Everything quiet: the rivals regroup for about %dh." % [t.name, maxi(1, left / 3600)], "", "Oss")

func _territory_fight(tid: String) -> void:
	var t: Dictionary = Data.TERRITORIES[tid]
	_open_team(str(t.zone), tid)

func _open_team(zone: String, territory := "") -> void:
	if team_board == null:
		team_board = TeamBoard.new()
		hud.root.add_child(team_board)
		team_board.start_pressed.connect(func():
			team_board.show_match(team_match, "between"))
		team_board.play_pressed.connect(_team_play)
		team_board.sim_pressed.connect(_team_sim)
		team_board.forfeit_pressed.connect(func():
			Game.record_team(false, team_match.ours.size())
			_team_close())
		team_board.close_pressed.connect(_team_close)
	var nonce := int(Game.counters.get("team_matches", 0))
	if territory != "":
		var td: Dictionary = Data.TERRITORIES[territory]
		team_match = Team.new_match(zone, Game.team_lineup(), nonce + hash(territory), 3, td.academy)
		team_match.territory = territory
	else:
		team_match = Team.new_match(zone, Game.team_lineup(), nonce)
	player.input_enabled = false
	hud.minimap.visible = false
	team_board.result_text = ""
	team_board.show_match(team_match, "lineup")

func _team_play() -> void:
	# your own bout is a real-time fight; teammates' bouts are called from the corner (simulated)
	if not bool(team_match.current_ours().get("player", false)):
		_team_sim()
		return
	team_board.visible = false
	_bout(team_match.current_theirs(), "team", false)

func _team_sim() -> void:
	var ours: Dictionary = team_match.current_ours()
	var stam: float = team_match.stam_ours
	# a Professor in the corner: teammates fight fresher and sharper
	if Game.spec == "professor" and not bool(ours.get("player", false)):
		ours = ours.duplicate()
		ours["level"] = float(ours.get("level", 1.0)) + 0.35
		stam = minf(1.0, stam + 0.25)
		Game.toast.emit("Coaching %s from the corner" % str(ours.name), Team.ROLES.coach.color)
	var r := Team.sim_bout(ours, team_match.current_theirs(), stam, team_match.stam_theirs)
	_team_after(r, float(r.me_stam), float(r.them_stam))

func _team_after(result: Dictionary, me_stam: float, them_stam: float) -> void:
	player.input_enabled = false
	team_match.apply(result, me_stam, them_stam)
	Sfx.play("hit" if result.get("won", false) else "miss", -4.0)
	if team_match.over():
		var won := team_match.won()
		var xp := Game.record_team(won, team_match.i)
		var tid := team_match.territory
		if tid != "":
			if won:
				if Game.holds(tid):
					Game.defended(tid)
				else:
					Game.capture(tid)
			elif Game.territory_state(tid) == "attacked":
				Game.lose_territory(tid)
			world.refresh_flags()
		team_board.result_text = ("%s beat %s, %d fighters left standing.  +%d XP" % [Team.TEAM_NAMES[0], team_match.academy, team_match.ours.size() - team_match.i, xp]) if won else ("%s win this one.  +%d XP" % [team_match.academy, xp])
		Sfx.play("win" if won else "lose")
		team_board.show_match(team_match, "done")
	else:
		team_board.show_match(team_match, "between")

func _team_close() -> void:
	if team_board:
		team_board.visible = false
	team_match = null
	hud.minimap.visible = true
	player.input_enabled = true

# ------------------------------------------------------------ Circuito (roguelite runs)
var circuit_run: Circuit.Run = null
var circuit_board: CircuitBoard

func _open_circuit() -> void:
	if circuit_board == null:
		circuit_board = CircuitBoard.new()
		hud.root.add_child(circuit_board)
		circuit_board.card_picked.connect(func(id: String):
			circuit_run.perks.append(id)
			circuit_run.offers = []
			Sfx.play("collect")
			circuit_board.show_run(circuit_run, "ready"))
		circuit_board.fight_pressed.connect(_circuit_fight)
		circuit_board.quit_pressed.connect(func(): _circuit_finish())
		circuit_board.close_pressed.connect(_circuit_close)
	circuit_run = Circuit.new_run(int(Game.counters.get("circuit_runs", 0)))
	player.input_enabled = false
	hud.minimap.visible = false
	circuit_board.result_text = ""
	circuit_board.show_run(circuit_run, "draft")

func _circuit_fight() -> void:
	circuit_board.visible = false
	_bout(circuit_run.current(), "circuit", circuit_run.round >= 4)

func _circuit_after(result: Dictionary) -> void:
	player.input_enabled = false
	circuit_run.apply(result, float(result.get("me_stam", 1.0)))
	if circuit_run.over():
		_circuit_finish()
	else:
		circuit_board.show_run(circuit_run, "draft")

func _circuit_finish() -> void:
	var wins := circuit_run.round
	var champ := circuit_run.champion()
	var xp := Game.record_circuit(wins, champ)
	circuit_board.result_text = ("Five straight wins, the last against a master at full strength. +%d XP and the Circuito Champion Rashguard." % xp) if champ else ("%d win%s this run. +%d XP. The road resets every run; the cards will be different next time." % [wins, "" if wins == 1 else "s", xp])
	if not champ and not circuit_run.lost:
		circuit_run.lost = true
	Sfx.play("win" if champ else "levelup")
	circuit_board.show_run(circuit_run, "done")

func _circuit_close() -> void:
	if circuit_board:
		circuit_board.visible = false
	circuit_run = null
	hud.minimap.visible = true
	player.input_enabled = true

func _start_daily() -> void:
	if hud.journal.visible:
		hud.toggle_journal()
	var dc := Game.daily_challenge()
	_daily_rule = str(dc.rule)
	Game.toast.emit("Daily Challenge: %s" % str(dc.opp.name), Color(1, 0.85, 0.35))
	_bout(dc.opp, "daily", false)

func _start_drill(attr: String) -> void:
	player.input_enabled = false
	hud.set_exploring(false)
	_drill = DrillScene.new()
	add_child(_drill)
	_drill.finished.connect(func(a: String, ok: bool):
		_drill.queue_free()
		_drill = null
		hud.set_exploring(true)
		player.input_enabled = true
		Game.drills_ready = false
		if ok:
			Game.complete_drill(a)
		else:
			Game.save_game()
		hud.refresh())
	_drill.start(attr)

func _interact(target: Npc = null) -> void:
	var npc: Npc = target if target != null else world.nearby
	if roll != null or hud.dialogue_open() or _drill != null or hud.travel_open():
		return
	if npc != null and npc.giver_id != "":
		_open_quest(npc.giver_id)
		return
	if npc != null and not npc.mob.is_empty():
		combat.set_target_npc(npc)
		combat.engage_npc(npc)
		return
	if npc == null:
		if not world.nearby_spot.is_empty():
			_use_spot(world.nearby_spot)
		return
	_talking_to = npc
	player.input_enabled = false
	var o: Dictionary = Data.OPPONENTS[npc.opp_id]
	if npc.opp_id == "onca":
		if not Game.flags.get("met_professor", false):
			Game.flags["met_professor"] = true
			Game.save_game()
			Game.progress_changed.emit()
		if Game.rank >= 5 and Game.beaten("onca"):
			hud.open_dialogue("Mestre Onça", "Blue belt suits you. The bus to the Pantanal leaves from the east gate. Want to roll anyway?")
			return
		if Game.town_wins() < Data.BOSS_REQUIRED_WINS:
			hud.open_dialogue("Mestre Onça", "So you're the gringo everyone's talking about. Before you step on my mat, beat %d fighters around town. You have %d. Vai!" % [Data.BOSS_REQUIRED_WINS, Game.town_wins()], "", "Oss")
			return
		hud.open_dialogue("Mestre Onça", o.intro, "Oss! Roll with Mestre Onça")
		return
	if npc.opp_id == "jacare" and not Game.beaten("jacare"):
		Game.flags["met_jacare"] = true
		if Game.town_wins("pantanal") < Data.BOSS_REQUIRED_WINS:
			hud.open_dialogue("Mestre Jacaré", "Onça's student, eh? Beat %d of my locals first. You have %d. The swamp will teach you." % [Data.BOSS_REQUIRED_WINS, Game.town_wins("pantanal")], "", "Oss")
			return
	var intro: String = o.intro
	if Game.beaten(npc.opp_id):
		intro = "Rematch? I've been drilling. (Reduced XP for rematches.)"
	hud.open_dialogue("%s  ·  %s" % [o.name, Data.rank_name(int(o.rank))], intro)

func _on_dialogue_choice(accepted: bool) -> void:
	if _job_prompt != "":
		var jid := _job_prompt
		_job_prompt = ""
		if accepted:
			_start_job(jid)
		else:
			player.input_enabled = true
		return
	if _raid_prompt:
		_raid_prompt = false
		if accepted:
			_start_raid()
		else:
			player.input_enabled = true
		return
	if _tap_prompt:
		_tap_prompt = false
		combat.resolve_tap(accepted)
		if not accepted:
			var sp: Vector3 = Data.ZONES[Game.zone].spawn
			player.teleport(Vector3(sp.x, world.ground_y(sp.x, sp.z) + 0.5, sp.z), 0.0)
		player.input_enabled = true
		return
	if _quest_prompt != "":
		var qp := _quest_prompt
		_quest_prompt = ""
		var parts := qp.split(":")
		if accepted and parts[0] == "offer":
			Game.accept_quest(parts[1])
		elif accepted and parts[0] == "turnin":
			Game.complete_quest(parts[1])
			# another quest from the same giver? offer it right away
			for nid in Data.quests_of(Data.QUESTS[parts[1]].giver):
				if Game.quest_available(nid):
					_open_quest(Data.QUESTS[parts[1]].giver)
					return
		player.input_enabled = true
		return
	if _territory_prompt != "":
		var tp := _territory_prompt
		_territory_prompt = ""
		if accepted:
			_territory_fight(tp)
		else:
			player.input_enabled = true
		return
	if _comp_prompt != "":
		var what := _comp_prompt
		_comp_prompt = ""
		if accepted and what in ["enter", "next"]:
			_comp_start_match()
		else:
			if what == "next":
				Game.toast.emit("You withdraw from the %s." % Data.COMPS[comp_run.id].name, UiKit.MUTED)
			comp_run = {}
			player.input_enabled = true
		return
	if accepted and _talking_to != null:
		player.input_enabled = true
		combat.duel(_talking_to)
	else:
		player.input_enabled = true
	_talking_to = null

var _hidden_npc: Npc

## The world NPC for an opponent id (the one you walked up to), if there is one nearby.
func _npc_for(opp_id: String) -> Npc:
	if world.nearby and world.nearby.opp_id == opp_id:
		return world.nearby
	var stack: Array = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Npc and (n as Npc).opp_id == opp_id and opp_id != "":
			return n
		stack.append_array(n.get_children())
	return null

var _mob_npc: Npc

## Walk up to a mob (or get pulled by one): the fight starts right there.
func _start_mob(npc: Npc) -> void:
	if roll != null or npc == null or npc.mob.is_empty():
		return
	_mob_npc = npc
	npc.unqueue()
	_start_roll("mob", {}, {}, {}, npc.mob)
	# social pull: aggressive campmates standing close by want the winner (like pulling a WoW pack)
	for e in world.mobs:
		var o: Npc = e.npc
		if o == null or o == npc or not o.visible or not bool(e.camp.get("aggro", false)):
			continue
		if str(e.camp.id) == str(npc.mob.get("camp", "")) and o.global_position.distance_to(npc.global_position) < 6.0:
			_queue_mob(o)
	if roll:
		roll.set_queue(_queue_names())

## Grappling is one-on-one, so extra mobs don't pile on: they line up at the edge of your fight
## ("winner stays on"). Win and the next one steps straight in, with your stamina carried over
## (+20% breather). Lose and the line breaks up. Pull carefully.
var _mob_queue: Array = []
const MOB_QUEUE_MAX := 3

func _queue_mob(npc: Npc) -> void:
	if npc == null or npc == _mob_npc or npc in _mob_queue or _mob_queue.size() >= MOB_QUEUE_MAX:
		return
	_mob_queue.append(npc)
	var c: Vector3 = roll.anchor.origin if roll else player.global_position
	var at := c + Vector3(3.5, 0, 0)
	if roll:
		# line up across the mat from the broadcast camera, so they're in view but not in the way
		var b: Basis = roll.pair.global_transform.basis
		var side := float(_mob_queue.size() - 2) * 2.0
		at = c - b.x.normalized() * 3.8 + b.z.normalized() * side
	npc.queue_at(at, c)
	if roll:
		roll.set_queue(_queue_names())
		roll.announce("%s is waiting for the winner!" % npc.mob.name)

func _queue_names() -> Array:
	var out: Array = []
	for q in _mob_queue:
		if is_instance_valid(q):
			out.append("%s (Lv %d)" % [q.mob.name, Data.display_level(float(q.mob.level))])
	return out

func _on_mob_engaged(npc: Npc) -> void:
	if combat and roll == null and not _in_title:
		combat.engage_npc(npc)
		return
	if roll != null and _mob_npc != null:
		_queue_mob(npc)
		return
	if roll != null or _in_title or hud.dialogue_open() or hud.journal.visible or hud.travel_open() or _drill != null or not player.input_enabled:
		return
	Game.toast.emit("%s wants to roll!" % npc.mob.name, Color(1, 0.6, 0.4))
	_start_mob(npc)

## You tapped in the open world: no XP, a gloating winner, a coach's note, and a choice.
var _tap_prompt := false

func _on_player_tapped(info: Dictionary) -> void:
	_tap_prompt = true
	player.input_enabled = false
	var how := " with a %s" % str(info.how) if str(info.how) != "" else ""
	hud.open_dialogue("You tapped to %s%s" % [str(info.by), how],
		"No XP for this one, and they won't let you forget it (⚔ Revenge: beat them for bonus XP).\n\n%s\n\nShake it off and get up right here (35%% Composure, Rattled: -15%% damage for 60s), or walk it off back at the academy (full Composure)." % str(info.lesson),
		"Shake it off", "Back to the academy")

# ------------------------------------------------------------ bicos (odd jobs around town)
var _job_prompt := ""

func _job(id: String) -> Dictionary:
	for z in Data.JOBS:
		for j in Data.JOBS[z]:
			if str(j.id) == id:
				return j
	return {}

func _open_job(id: String) -> void:
	var j := _job(id)
	if j.is_empty():
		return
	player.input_enabled = false
	if str(Game.flags.get("job_" + id, "")) == Game.today():
		hud.open_dialogue(str(j.who), "Obrigado again for today! Come back tomorrow, there's always something.", "", "Oss")
		return
	_job_prompt = id
	hud.open_dialogue("%s  ·  %s" % [str(j.who), str(j.name)], str(j.ask), "Help out", "Not now")

func _start_job(id: String) -> void:
	var j := _job(id)
	player.input_enabled = false
	hud.set_exploring(false)
	_drill = DrillScene.new()
	add_child(_drill)
	_drill.finished.connect(func(jid: String, ok: bool):
		_drill.queue_free()
		_drill = null
		hud.set_exploring(true)
		player.input_enabled = true
		Game.flags["job_" + jid] = Game.today()
		if ok:
			Game.add_xp(int(j.xp))
			Game.money += int(j.money)
			Game.toast.emit("%s: +%d XP, R$ %d" % [str(j.name), int(j.xp), int(j.money)], Color(1, 0.85, 0.35))
			if str(j.get("item", "")) != "":
				Game.add_item(str(j.item))
				Game.toast.emit("Received: %s" % str(Loot.item(str(j.item)).get("name", j.item)), Color(0.95, 0.9, 0.7))
			Game.bump("jobs_done")
		Game.save_game()
		hud.refresh())
	_drill.start(str(j.attr), j)

# ------------------------------------------------------------ raids
var _raid_prompt := false

func _start_raid() -> void:
	player.input_enabled = true
	var fwd := Vector3(sin(player.rig.global_rotation.y), 0, cos(player.rig.global_rotation.y))
	combat.start_raid(player.global_position + fwd * 7.0)

func _on_raid_over(won: bool) -> void:
	await get_tree().create_timer(2.5).timeout
	player.input_enabled = false
	if won:
		hud.open_dialogue("Covil da Sucuri", "The Sucuri taps! The old gym is open again, and his students are already asking to train with you.\n\nYour loot is in your bags. Run it again any time: he scales to your level.", "", "Oss")
	else:
		hud.open_dialogue("Covil da Sucuri", "Wiped. Watch the cast bar: Sprawl (Q) the Takedown Wave, and help your partners with the students when they come for Gil.", "", "Oss")
	hud.refresh()

# ------------------------------------------------------------ event bouts in real time
var _daily_rule := ""

func _bout(opp: Dictionary, tag: String, elite := false) -> void:
	if hud.dialogue_open():
		hud._close_dialogue(false)
	if hud.journal.visible:
		hud.toggle_journal()
	player.input_enabled = true
	hud.minimap.visible = true
	combat.start_bout(opp, tag, elite)

func _on_bout_over(tag: String, won: bool, info: Dictionary) -> void:
	var res := {"won": won, "by_sub": not bool(info.get("forfeit", false)), "sub": str(info.get("sub", "")) if won else "tap",
		"signature": false, "min_stamina": float(info.get("gas", 1.0))}
	match tag:
		"comp":
			await get_tree().create_timer(1.6).timeout
			_comp_after_match(res)
		"team":
			await get_tree().create_timer(1.6).timeout
			if team_match == null:
				return
			team_board.visible = true
			_team_after(res, float(info.get("gas", 1.0)), 0.0 if won else float(info.get("their_hp", 1.0)))
		"circuit":
			await get_tree().create_timer(1.6).timeout
			if circuit_run == null:
				return
			circuit_board.visible = true
			res["me_stam"] = float(info.get("gas", 1.0))
			_circuit_after(res)
		"daily":
			var xp := Game.record_daily(res)
			await get_tree().create_timer(1.6).timeout
			player.input_enabled = false
			if won:
				hud.open_dialogue("Daily Challenge", "Won! Streak: %d day%s.\n\n+%d XP. Same time tomorrow." % [Game.daily_streak(), "" if Game.daily_streak() == 1 else "s", xp], "", "Oss")
			else:
				hud.open_dialogue("Daily Challenge", "Not today. The challenge stays open until midnight: rest, then run it back.", "", "Oss")
	hud.refresh()

## A named fighter's duel ended (story beats that used to follow a roll).
func _after_duel(opp_id: String, won: bool) -> void:
	world.refresh_beacon()
	hud.refresh()
	if won and opp_id == "leao" and not Game.flags.get("black_belt_ending", false):
		Game.flags["black_belt_ending"] = true
		Game.save_game()
		hud.open_dialogue("Black Belt", "From a tourist on the plaza in Cáceres to a black belt in Rio. Onça, Jacaré, Cachoeira and Leão all put their hands on that belt.\n\nThe journey doesn't end here. Every Daily Challenge is still waiting, and every fighter in Brazil still wants a roll with the gringo black belt. Oss.", "", "Oss")
	if won and opp_id == "rafa" and not Game.flags.get("met_professor", false):
		Game.toast.emit("Rafa: the academia is behind the cathedral. Follow the light.", Color(1, 0.95, 0.8))

func _start_roll(opp_id: String, daily: Dictionary = {}, comp: Dictionary = {}, team_bout: Dictionary = {}, mob: Dictionary = {}) -> void:
	player.input_enabled = false
	hud.visible = false
	# Fights happen where you stand: the pair takes the spot between you and your opponent, the
	# world keeps living around you, and the world-side bodies hide while the fight rigs take over.
	var npc := _mob_npc if opp_id == "mob" else _npc_for(opp_id)
	var me_pos: Vector3 = player.global_position
	var mid := me_pos
	var face := Vector3(sin(player.rig.global_rotation.y), 0, cos(player.rig.global_rotation.y)) if player.rig else Vector3.FORWARD
	if npc and npc.global_position.distance_to(me_pos) < 6.0:
		mid = (me_pos + npc.global_position) * 0.5
		face = npc.global_position - me_pos
	else:
		mid = me_pos + face.normalized() * 0.5
	face.y = 0
	var to_me := -face.normalized() if face.length() > 0.01 else Vector3.BACK
	mid.y = world.ground_y(mid.x, mid.z)
	_hidden_npc = npc
	if npc:
		npc.visible = false
		npc.process_mode = Node.PROCESS_MODE_DISABLED
	if player.rig:
		player.rig.force_hidden = true
		player.rig.visible = false
	roll = RollScene.new()
	roll.in_world = true
	roll.anchor = Transform3D(Basis(Vector3.UP, atan2(to_me.x, to_me.z)), mid)
	roll.ground_fn = world.ground_y
	add_child(roll)
	roll.finished.connect(_end_roll)
	roll.start(opp_id, daily, comp, team_bout, mob)
	Sfx.duck_ambience(true)
	_fit_screen()

func _end_roll(opp_id: String, result: Dictionary, _xp: int) -> void:
	Sfx.music("explore")
	Sfx.duck_ambience(false)
	roll.queue_free()
	roll = null
	world.visible = true
	world.process_mode = Node.PROCESS_MODE_INHERIT
	if is_instance_valid(_hidden_npc):
		_hidden_npc.visible = true
		_hidden_npc.process_mode = Node.PROCESS_MODE_INHERIT
	_hidden_npc = null
	if player.rig:
		player.rig.force_hidden = false
		player.rig.visible = true
	hud.visible = true
	player.make_current()
	player.input_enabled = true
	world.refresh_beacon()
	hud.refresh()
	hud.set_prompt(world.nearby)
	if opp_id == "mob":
		if is_instance_valid(_mob_npc):
			world.mob_done(_mob_npc, bool(result.won))
		if result.get("disengaged", false):
			world.aggro_grace = 10.0
		_mob_npc = null
		world.refresh_mob_tags()
		var next: Npc = null
		while not _mob_queue.is_empty() and next == null:
			var q = _mob_queue.pop_front()
			if is_instance_valid(q) and q.visible:
				next = q
		if result.won and next != null:
			next.mob["carry"] = clampf(float(result.get("me_stam", 1.0)) + 0.2, 0.25, 1.0)
			Game.toast.emit("Next challenger: %s!" % next.mob.name, Color(1, 0.6, 0.4))
			_start_mob.call_deferred(next)
			return
		if next:
			next.unqueue()
		for q in _mob_queue:
			if is_instance_valid(q):
				q.unqueue()
		_mob_queue.clear()
		return
	if opp_id == "comp":
		_comp_after_match(result)
		return
	if opp_id == "team":
		_team_after(result, float(result.get("me_stam", 1.0)), float(result.get("them_stam", 1.0)))
		return
	if opp_id == "circuit":
		_circuit_after(result)
		return
	if result.won and opp_id == "leao" and not Game.flags.get("black_belt_ending", false):
		Game.flags["black_belt_ending"] = true
		Game.save_game()
		hud.open_dialogue("Black Belt", "From a tourist on the plaza in Cáceres to a black belt in Rio. Onça, Jacaré, Cachoeira and Leão all put their hands on that belt.\n\nThe journey doesn't end here. Every Daily Challenge is still waiting, and every fighter in Brazil still wants a roll with the gringo black belt. Oss.", "", "Oss")
	if result.won and opp_id == "rafa" and not Game.flags.get("met_professor", false):
		Game.toast.emit("Rafa: the academia is behind the cathedral. Follow the light.", Color(1, 0.95, 0.8))
