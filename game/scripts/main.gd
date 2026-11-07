extends Node
## Scene flow: title -> explore Cáceres <-> roll on the mat.

var world: World
var player: Player
var hud: Hud
var roll: RollScene
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
	hud.touch.jump_pressed.connect(player.do_jump)
	hud.touch.interact_pressed.connect(_interact)
	hud.touch.journal_pressed.connect(hud.toggle_journal)
	hud.play_pressed.connect(_start_game)
	hud.travel_chosen.connect(func(z: String):
		player.input_enabled = true
		if z != "":
			_travel(z))
	hud.daily_requested.connect(_start_daily)
	hud.dialogue_choice.connect(_on_dialogue_choice)
	hud.graphics_changed.connect(func(): if is_instance_valid(world): world.apply_graphics())
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
	if OS.get_cmdline_user_args().has("--autoplay"):
		_start_game()
	_dev_hash()

## QA shortcuts via URL hash, e.g. index.html#roll=rafa or #tp=-36,52
func _dev_hash() -> void:
	if not OS.has_feature("web"):
		return
	var h := str(JavaScriptBridge.eval("window.location.hash || ''"))
	if h == "":
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
			hud._sel_talent = kv[1] if Rpg.TALENTS.has(kv[1]) else ""
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
		"look_left": [KEY_Q], "look_right": [KEY_R], "look_up": [KEY_PAGEUP], "look_down": [KEY_PAGEDOWN],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "interact": [KEY_E, KEY_ENTER],
		"journal": [KEY_J, KEY_TAB], "character": [KEY_C], "confirm": [KEY_SPACE, KEY_ENTER],
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

func _start_game() -> void:
	Sfx.music("explore")
	_in_title = false
	hud.hide_title()
	world.game_started = true
	player.make_current()
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

func _begin_play() -> void:
	player.input_enabled = true
	if Game.xp == 0 and not Game.flags.get("intro_seen", false):
		Game.flags["intro_seen"] = true
		Game.save_game()
		hud.open_dialogue("Cáceres, Mato Grosso",
			"You just moved to town with a white belt and a dream. Follow the golden light: there's a guy in the plaza who rolls every afternoon. Win rolls, earn stripes, and find the academia.",
			"", "Let's go")

func _unhandled_input(event: InputEvent) -> void:
	if _in_title or roll != null or Game.style == "":
		return
	if event.is_action_pressed("journal") and not hud.dialogue_open():
		hud.toggle_journal()
	elif event.is_action_pressed("character") and not hud.dialogue_open():
		if hud.journal.visible:
			hud.toggle_journal()
		else:
			hud.open_character()
	elif event.is_action_pressed("interact") and not hud.dialogue_open() and not hud.journal.visible:
		_interact()
	elif event.is_action_pressed("pause") and hud.journal.visible:
		hud.toggle_journal()

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
		# let physics settle at the new spawn before landmarks/collectibles can trigger
		get_tree().create_timer(0.6).timeout.connect(func(): if is_instance_valid(world): world.game_started = true)
	var sp: Vector3 = Data.ZONES[z].spawn
	var spawn := Vector3(sp.x, world.ground_y(sp.x, sp.z) + 0.5, sp.z)
	player.position = spawn
	world.add_child(player)
	player.teleport(spawn, PI / 2 if z in ["pantanal", "rio"] else 0.0)
	world.attach_player(player)
	world.nearby_changed.connect(_on_nearby)
	world.spot_changed.connect(_on_spot)
	if is_instance_valid(_title_cam):
		world.add_child(_title_cam)

func _travel(z: String) -> void:
	var need := int(Data.ZONES[z].rank)
	if Game.rank < need:
		hud.open_dialogue("Bus driver", "Not yet, amigo. That road is for %s and up." % Data.rank_name(need), "", "Okay")
		return
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
		"quest":
			_open_quest(spot.arg)
		"drill":
			if not Game.drills_ready:
				hud.open_dialogue("Coach", "You're cooked. Go roll with someone, then come back and drill.", "", "Oss")
				return
			_start_drill(spot.arg)

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
	_start_roll("comp", {}, m)

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

func _start_daily() -> void:
	if hud.journal.visible:
		hud.toggle_journal()
	var dc := Game.daily_challenge()
	_start_roll("daily", dc)

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

func _interact() -> void:
	var npc := world.nearby
	if roll != null or hud.dialogue_open() or _drill != null or hud.travel_open():
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
		_start_roll(_talking_to.opp_id)
	else:
		player.input_enabled = true
	_talking_to = null

func _start_roll(opp_id: String, daily: Dictionary = {}, comp: Dictionary = {}) -> void:
	player.input_enabled = false
	world.visible = false
	world.process_mode = Node.PROCESS_MODE_DISABLED
	hud.visible = false
	roll = RollScene.new()
	add_child(roll)
	roll.finished.connect(_end_roll)
	roll.start(opp_id, daily, comp)
	_fit_screen()

func _end_roll(opp_id: String, result: Dictionary, _xp: int) -> void:
	Sfx.music("explore")
	roll.queue_free()
	roll = null
	world.visible = true
	world.process_mode = Node.PROCESS_MODE_INHERIT
	hud.visible = true
	player.make_current()
	player.input_enabled = true
	world.refresh_beacon()
	hud.refresh()
	hud.set_prompt(world.nearby)
	if opp_id == "comp":
		_comp_after_match(result)
		return
	if result.won and opp_id == "leao" and not Game.flags.get("black_belt_ending", false):
		Game.flags["black_belt_ending"] = true
		Game.save_game()
		hud.open_dialogue("Black Belt", "From a tourist on the plaza in Cáceres to a black belt in Rio. Onça, Jacaré, Cachoeira and Leão all put their hands on that belt.\n\nThe journey doesn't end here. Every Daily Challenge is still waiting, and every fighter in Brazil still wants a roll with the gringo black belt. Oss.", "", "Oss")
	if result.won and opp_id == "rafa" and not Game.flags.get("met_professor", false):
		Game.toast.emit("Rafa: the academia is behind the cathedral. Follow the light.", Color(1, 0.95, 0.8))
