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
	UiKit.with_symbols(ThemeDB.fallback_font)
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
	hud.ui_scale_changed.connect(_fit_screen)
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
	hud.combat_log.academy_requested.connect(hud.toggle_academy)
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
	# Interface size (Esc > Graphics): a smaller UI is a bigger base resolution. Desktops default to
	# 85%; phones keep 100% so buttons stay thumb-sized.
	var phone := DisplayServer.is_touchscreen_available() or minf(sz.x, sz.y) < 520
	var ui := clampf(float(Sfx.pref("ui_scale", 1.0 if phone else 0.85)), 0.6, 1.3)
	# landscape phones get a shorter base so text stays readable on a ~390px-tall screen
	var base := Vector2(540, 960) if portrait else (Vector2(1280, 640) if phone else Vector2(1280, 720))
	win.content_scale_size = Vector2i(base / ui)
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
		"pause": [KEY_ESCAPE], "finder": [KEY_K], "arena": [KEY_H], "academy": [KEY_O], "fullscreen": [KEY_F11],
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
	Keys.load_saved()   # the player's own bindings (Esc > Keys)

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
	_check_zone_line(delta)
	_rival_process()
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

# ------------------------------------------------------------ rival shadows (faction PvP)
## Walk up to a player from the other faction and challenge their shadow: an AI fighter built from
## their character (level, belt, class, gi). Wins count for your side of the Faction War.
var _rival: RemotePlayer = null
var _rival_cd := {}   # name -> unix time of the last shadow roll (no farming the same player)
const RIVAL_COOLDOWN := 600

func _rival_process() -> void:
	var best: RemotePlayer = null
	if not _in_title and is_instance_valid(world) and world.nearby == null and world.nearby_spot.is_empty() and roll == null \
			and not hud.dialogue_open() and is_instance_valid(player) and (combat == null or combat.me == null or not combat.me.in_combat):
		var bd := 3.2
		for id in remotes:
			var rp = remotes[id]
			if not is_instance_valid(rp) or not rp.visible:
				continue
			var d: float = rp.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = rp
	if best != _rival:
		_rival = best
		if best == null:
			hud.set_prompt(null)
		else:
			var nm := str(best.char.get("name", "?"))
			var wait := int(_rival_cd.get(nm, 0)) + RIVAL_COOLDOWN - int(Time.get_unix_time_from_system())
			hud.prompt.text = Tx.f("[%s]  %s  (%s, Lv %d)  ·  duel · party · trade", [Keys.label("interact"), nm, str(Origins.faction(str(best.char.get("faction", ""))).long), int(best.char.get("level", 1))])
			hud.touch.interact_btn.visible = true
			hud.touch.interact_btn.text = "ROLL"

func rival_opponent(ch: Dictionary) -> Dictionary:
	var lv := clampi(int(ch.get("level", 1)), 1, 60)
	var styles := {"guard": "guard", "wrestler": "pressure", "judoka": "balanced", "athlete": "back", "passer": "pressure"}
	var gi := Color.html(str(ch.get("gi", "f2f2ee"))) if Color.html_is_valid(str(ch.get("gi", ""))) else Color(0.95, 0.95, 0.93)
	var fac := Origins.faction(str(ch.get("faction", "brasil")))
	var extras: Array = []
	for mid in Data.MOVES:
		if int(Data.MOVES[mid].rank) <= lv / 2 and int(Data.MOVES[mid].rank) != 99 and randf() < 0.3:
			extras.append(mid)
	return {"name": Tx.f("%s's Shadow", str(ch.get("name", "?"))), "title": str(fac.long), "rank": clampi(int(ch.get("belt", 0)) * 5 + 2, 0, 24),
		"level": 1.0 + float(lv - 1) * 0.55 / 2.0, "gi": gi, "skin": UiKit.skin_tone(float(ch.get("skin", 0.35))),
		"body": str(ch.get("body", "male")), "style": styles.get(str(ch.get("style", "")), "balanced"), "extra": extras, "zone": "",
		"intro": Tx.f("For %s!", fac.long), "win": "Not today. Tell your side.", "lose": "Oss. Your faction trains hard."}

# ------------------------------------------------------------ live duels (see Pvp)
var pvp: Pvp = null
var _duel_ask := ""          # "menu" (you picked a player) / "incoming" (someone challenged you)
var party: Party = null      # your party (see Party)
var coop: Coop = null        # party dungeons and raids (see Coop)
var trade: Trade = null      # player-to-player trades (see Trade)

# ------------------------------------------------------------ ranked arena (see ArenaPanel, server.js)
var _arena_busy := false
var _arena_opp := {}

func start_arena() -> void:
	if not Cloud.logged_in():
		Game.toast.emit("Log in (title screen) to play ranked.", Color(1, 0.6, 0.4))
		return
	if _arena_busy or combat.me.in_combat or (combat.raid != null and is_instance_valid(combat.raid)) or (pvp and pvp.busy()) or (coop and coop.busy()):
		Game.toast.emit("Finish what you're doing first.", Color(1, 0.5, 0.4))
		return
	_arena_busy = true
	Game.toast.emit("Finding a ranked opponent...", Color(1, 0.85, 0.4))
	Cloud.arena_match(func(code: int, d: Dictionary):
		_arena_busy = false
		if code != 200 or not d.has("opp"):
			Game.toast.emit(str(d.get("error", "The arena is closed right now.")), Color(1, 0.6, 0.4))
			return
		var o: Dictionary = d.opp
		_arena_opp = o
		var ch: Dictionary = o.get("char") if o.get("char") is Dictionary else {}
		if ch.is_empty():   # a house fighter
			ch = {"name": str(o.name), "level": int(o.get("level", 1)), "faction": str(o.get("faction", "brasil")), "belt": clampi(int(o.get("level", 1)) / 12, 0, 4),
				"skin": randf(), "body": "male" if randf() < 0.7 else "female", "gi": ["f2f2ee", "1f3c99", "141416"][randi() % 3]}
		ch = ch.duplicate()
		ch["level"] = int(o.get("level", ch.get("level", 1)))   # the ladder's record of their level
		var od := rival_opponent(ch)
		od["name"] = str(o.name)
		od["title"] = Tx.f("Ranked · %d", int(o.get("rating", 1000)))
		od["intro"] = "Ranked. Oss."
		od["win"] = "The ladder's a long climb."
		od["lose"] = "Oss. See you on the ladder."
		# their rating sharpens the shadow: a 1300 plays tighter than a 900
		od["level"] = float(od.level) + clampf((float(o.get("rating", 1000)) - 1000.0) / 400.0, -0.4, 0.6)
		Game.toast.emit(Tx.f("Ranked: %s (%d)", [str(o.name), int(o.get("rating", 1000))]), Wow.GOLD)
		_bout(od, "arena", true))

func _arena_after(won: bool) -> void:
	Cloud.arena_result(won, func(code: int, d: Dictionary):
		if code != 200:
			Game.toast.emit(str(d.get("error", "Couldn't record the result.")), Color(1, 0.6, 0.4))
			return
		var delta := int(d.get("delta", 0))
		var me = d.get("board", {}).get("me")
		var r := int(me.rating) if me is Dictionary else 0
		Game.toast.emit(Tx.f("Rating %s%d  →  %d", ["+" if delta >= 0 else "", delta, r]), Color(0.6, 1.0, 0.6) if delta >= 0 else Color(1, 0.6, 0.5))
		if won:
			Game.unlock("arena_win")
			Game.add_xp(25 + 6 * Game.player_level())
			Game.add_war(10, "ranked win")
			if r >= 1200:
				Game.unlock("arena_1200")
		Game.save_game()
		hud.refresh())

func _ranked_toast(delta: int, me) -> void:
	var r := int(me.rating) if me is Dictionary else 0
	Game.toast.emit(Tx.f("Ranked duel: rating %s%d  →  %d", ["+" if delta >= 0 else "", delta, r]), Color(0.6, 1.0, 0.6) if delta >= 0 else Color(1, 0.6, 0.5))

var _arena_claimed := false

## Last week's payout (once per account; the server remembers).
func _arena_claim() -> void:
	if _arena_claimed or not Cloud.logged_in():
		return
	_arena_claimed = true
	Cloud.arena_claim(func(code: int, d: Dictionary):
		if code != 200 or not d.get("reward") is Dictionary:
			return
		var rw: Dictionary = d.reward
		var honor: int = {"champion": 1500, "podium": 1000, "top10": 600}.get(str(rw.tier), 250)
		Game.honor += honor
		if str(rw.tier) == "champion":
			Game.unlock("arena_champion")
		Game.save_game()
		hud.open_dialogue("Ranked Arena", Tx.f("Last week (%s) you finished #%d at %d rating.\n\n+%d Honor. Spend it at your quartermaster.", [str(rw.week), int(rw.place), int(rw.rating), honor]), "", "Oss"))

func ask_trade(who: String) -> void:
	_party_ask = "trade"
	player.input_enabled = false
	hud.open_dialogue("Trade", Tx.f("%s wants to trade with you.", who), "Open trade", "Decline")
var _party_ask := ""         # "party" (an invite) / "coop" (your leader is starting a run)

func ask_party(ch: Dictionary) -> void:
	_party_ask = "party"
	player.input_enabled = false
	hud.open_dialogue("Party", Tx.f("%s (%s, level %d) invites you to their party.\n\nRun dungeons and raids together, see each other's health, and talk on /p.", [str(ch.get("name", "?")), Origins.faction(str(ch.get("faction", ""))).long, int(ch.get("level", 1))]), "Join the party", "Decline")

func ask_coop(leader_name: String, title: String) -> void:
	if hud.dialogue_open():
		hud._close_dialogue(false)
	_party_ask = "coop"
	player.input_enabled = false
	hud.open_dialogue(title, Tx.f("%s is starting %s with the party. Join them? You'll be brought to the entrance.", [leader_name, title]), "Join", "Not this time")

## Leader: the party said yes (or time ran out); the run starts here with the real players in it.
func start_coop_raid(kind: String, at: Vector3, humans: Array) -> void:
	hud.close_finder()
	player.input_enabled = true
	_raid_kind = kind if Raid.DUNGEONS.has(kind) else ""
	combat.start_raid(at, kind, humans)

func coop_guest_started(kind: String) -> void:
	hud.close_finder()
	if hud.journal.visible:
		hud.toggle_journal()
	player.input_enabled = true
	_raid_kind = kind if Raid.DUNGEONS.has(kind) else ""

func coop_guest_over(kind: String, won: bool) -> void:
	_raid_kind = kind if Raid.DUNGEONS.has(kind) else ""
	combat.raid_over.emit(won)

## The run with your party, or on your own.
func _party_run(kind: String) -> bool:
	if party and party.is_leader() and not party.here().is_empty():
		coop.gather(kind)
		return true
	if party and party.in_party() and not party.is_leader() and not party.here().is_empty():
		Game.toast.emit("Your party leader starts group runs. Going on your own.", Color(1, 0.8, 0.5))
	return false
var _duel_rp: RemotePlayer = null
var _duel_party := false     # the menu's second button invites them to your party

func _duel_menu(rp: RemotePlayer) -> void:
	if pvp == null or pvp.busy() or hud.player_menu_open():
		return
	_duel_rp = rp
	if not hud.player_menu_toggled.is_connected(_on_player_menu):
		hud.player_menu_toggled.connect(_on_player_menu)
	player.input_enabled = false
	var ch: Dictionary = rp.char
	var rid := int(rp.net_id)
	var other := str(ch.get("faction", "brasil")) != Game.faction()
	var nm := str(ch.get("name", "?"))
	var wait := int(_rival_cd.get(nm, 0)) + RIVAL_COOLDOWN - int(Time.get_unix_time_from_system())
	var txt := Tx.f("%s  ·  %s, level %d.", [nm, Origins.faction(str(ch.get("faction", ""))).long, int(ch.get("level", 1))])
	var opts: Array = []
	opts.append([Tx.s("Challenge to a live duel") + (Tx.s(" (Faction War: 20 points)") if other else ""), func(): pvp.invite(rid, rp.char)])
	if other and wait <= 0:
		opts.append([Tx.s("Fight their shadow (an AI copy, no need to ask)"), func(): _start_rival(rp)])
	elif other:
		txt += Tx.f("\n\n(Their shadow needs %d min to recover.)", ceili(wait / 60.0))
	if party and not party.members.has(rid) and (not party.in_party() or party.is_leader()):
		opts.append([Tx.s("Invite to party"), func(): party.invite_id(rid, nm)])
	if trade and not trade.busy():
		opts.append([Tx.s("Trade"), func(): trade.request(rid, nm)])
	opts.append([Tx.s("Whisper"), func(): hud.combat_log.open_input("/w %s " % nm)])
	hud.player_menu(nm, txt, opts)

## /oss, /wave...: your fighter does it, and everyone in the zone sees it.
func do_emote(id: String) -> void:
	if combat.me.in_combat or player.rooted or (player.rig.in_action() and not player.emoting):
		return
	player.rig.action(Emotes.frames(id, player.rig.rotation.y))
	player.emoting = true
	Net.send_emote(id)
	hud.combat_log.add_chat({"ch": "sys", "text": Tx.s(str(Emotes.LIST[id].you))})

func _on_net_emote(id: int, e: String) -> void:
	var rp = remotes.get(id)
	if rp == null or not is_instance_valid(rp) or not Emotes.LIST.has(e):
		return
	rp.emote(e)
	if rp.global_position.distance_to(player.global_position) < 40.0:
		hud.combat_log.add_chat({"ch": "sys", "text": Tx.f(str(Emotes.LIST[e].them), str(rp.char.get("name", "?")))})

func _on_player_menu(open: bool) -> void:
	if not open and not hud.dialogue_open():
		player.input_enabled = true

func ask_duel(ch: Dictionary) -> void:
	_duel_ask = "incoming"
	player.input_enabled = false
	var other := str(ch.get("faction", "brasil")) != Game.faction()
	hud.open_dialogue("Duel!", Tx.f("%s (%s, level %d) challenges you to a live duel.%s", [str(ch.get("name", "?")), Origins.faction(str(ch.get("faction", ""))).long, int(ch.get("level", 1)),
		"\n\nFor the Faction War: a win is worth 20 points." if other else ""]), "Accept", "Decline")

func _on_pvp_finished(won: bool, opp_name: String, cross: bool) -> void:
	var xp := Game.record_pvp(won, cross)
	if Cloud.logged_in() and pvp.duel_id != "":
		var did := pvp.duel_id
		pvp.duel_id = ""
		Cloud.arena_live(did, won, func(code: int, d: Dictionary):
			if code != 200:
				return
			if bool(d.get("counted", false)):
				_ranked_toast(int(d.get("delta", 0)), d.get("board", {}).get("me"))
			elif bool(d.get("pending", false)):
				# the other player's report closes it: look again in a moment
				get_tree().create_timer(4.0).timeout.connect(func():
					var before = Cloud.arena.get("me")
					var r0 := int(before.rating) if before is Dictionary else 1000
					Cloud.arena_board(func(c2: int, b: Dictionary):
						if c2 == 200 and b.get("me") is Dictionary and int(b.me.rating) != r0:
							_ranked_toast(int(b.me.rating) - r0, b.me))))
	await get_tree().create_timer(1.6).timeout
	if won:
		Game.toast.emit(Tx.f("You beat %s in a live duel!%s", [opp_name, ("  +%d XP" % xp) if xp > 0 else ""]), Wow.GOLD)
	else:
		Game.toast.emit(Tx.f("%s won the duel. Oss.", opp_name), Color(1, 0.7, 0.5))
	hud.refresh()

func _start_rival(rp: RemotePlayer) -> void:
	var nm := str(rp.char.get("name", "?"))
	if int(_rival_cd.get(nm, 0)) + RIVAL_COOLDOWN > int(Time.get_unix_time_from_system()):
		return
	_rival_cd[nm] = int(Time.get_unix_time_from_system())
	_rival = null
	hud.set_prompt(null)
	Game.toast.emit(Tx.f("Rival shadow: %s  (%s)", [nm, Origins.faction(str(rp.char.get("faction", ""))).long]), Color(1.0, 0.5, 0.4))
	_bout(rival_opponent(rp.char), "rival", false)

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
	if not hud.arena_requested.is_connected(start_arena):
		hud.arena_requested.connect(start_arena)
	get_tree().create_timer(8.0).timeout.connect(func(): if Game.style != "": _arena_claim())
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
		if Game.zone != world.zone:
			_make_world(Game.zone)
			player.make_current()
			Net.enter(Game.zone)
			world.game_started = true
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
	if Data.ZONES.has(Game.zone):
		var zd: Dictionary = Data.ZONES[Game.zone]
		hud.zone_banner(str(zd.name), "%s  ·  %s" % [Tx.s(str(zd.sub)), Data.zone_levels(Game.zone)], true)
		_note_visit(Game.zone, false)
	if Game.flags.get("spec_reset", false):
		Game.flags.erase("spec_reset")
		Game.save_game()
		hud.open_dialogue("Professor Gil", "Coaching is a Guard Player and Judoka thing now: those are the only classes that can take the Professor spec. Your spec has been reset, so pick a new one from the Talents window (N). No charge.", "", "Oss")
	if Game.xp == 0 and not Game.flags.get("intro_seen", false) and Game.faction() == "usa":
		Game.flags["intro_seen"] = true
		Game.save_game()
		hud.open_dialogue("Dry Creek, Texas",
			"Hill Country. One stoplight, two barbecue joints and a garage gym behind the feed store. Follow the golden light: Coach Mae's students roll on the town square every afternoon. Win rolls, earn stripes, and find Lone Star BJJ.",
			"", "Let's go")
	elif Game.xp == 0 and not Game.flags.get("intro_seen", false):
		Game.flags["intro_seen"] = true
		Game.save_game()
		hud.open_dialogue("Cáceres, Mato Grosso",
			"You just moved to town with a white belt and a dream. Follow the golden light: there's a guy in the plaza who rolls every afternoon. Win rolls, earn stripes, and find the academia.",
			"", "Let's go")
	# Mat Days: the first login of the day claims the next reward (not on a brand-new character)
	if Game.xp > 0:
		var md := Game.mat_day_claim()
		if not md.is_empty():
			_show_mat_days_when_free(md)

func _show_mat_days_when_free(md: Dictionary, tries := 0) -> void:
	get_tree().create_timer(1.2).timeout.connect(func():
		if hud.dialogue_open() or hud.journal.visible or roll != null:
			if tries < 60:
				_show_mat_days_when_free(md, tries + 1)
			return
		hud.show_mat_days(md)
		hud.refresh())

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
		hud.gfx_btn.text = Tx.s("Gfx: high")
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
			hud.set_hover(Tx.f("%s  ·  click to talk", h.display_name))
		else:
			var o: Dictionary = Data.OPPONENTS[h.opp_id]
			hud.set_hover(Tx.f("%s  ·  Lv %d  ·  click to roll", [o.name, Data.display_level(float(o.level))]))
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
		Game.toast.emit(Tx.f("Walking to %s...", n.display_name), UiKit.MUTED)

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
	elif event.is_action_pressed("finder") and not hud.dialogue_open():
		hud.toggle_finder(self)
	elif event.is_action_pressed("arena") and not hud.dialogue_open():
		hud.toggle_arena()
	elif event.is_action_pressed("academy") and not hud.dialogue_open():
		hud.toggle_academy()
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
			Game.toast.emit(Tx.f("%s fell to %s while you were away.", [Data.TERRITORIES[tid].name, Data.TERRITORIES[tid].academy]), UiKit.RED)
		world.refresh_flags()
		for tid in Data.territories_in(z):
			if Game.territory_state(tid) == "attacked":
				Game.toast.emit(Tx.f("%s is attacking %s! Defend it within %dh.", [Data.TERRITORIES[tid].academy, Data.TERRITORIES[tid].name, maxi(1, Game.defend_left(tid) / 3600)]), Color(1, 0.45, 0.35))
	if not _in_title:
		# let physics settle at the new spawn before landmarks/collectibles can trigger
		get_tree().create_timer(0.6).timeout.connect(func(): if is_instance_valid(world): world.game_started = true)
	var sp: Vector3 = Data.ZONES[z].spawn
	var spawn := Vector3(sp.x, world.ground_y(sp.x, sp.z) + 0.5, sp.z)
	player.position = spawn
	world.add_child(player)
	player.teleport(spawn, PI / 2 if z in ["pantanal", "rio", "socal", "everglades", "sedona"] else 0.0)
	world.attach_player(player)
	if hud:
		hud.minimap.set_world(world, player)
	Sfx.ambience(z)
	Sfx.music_zone = z
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
		pvp = Pvp.new()
		add_child(pvp)
		pvp.setup(self)
		combat.pvp = pvp
		pvp.finished.connect(_on_pvp_finished)
		party = Party.new()
		party.name = "Party"
		add_child(party)
		party.setup(self)
		trade = Trade.new()
		trade.name = "Trade"
		add_child(trade)
		trade.setup(self, party)
		coop = Coop.new()
		coop.name = "Coop"
		add_child(coop)
		coop.setup(self, party)
		combat.coop = coop
		if hud and hud.combat_log:
			hud.combat_log.party = party
			hud.combat_log.trade = trade
			hud.combat_log.emote_requested.connect(do_emote)
		Net.emote.connect(_on_net_emote)
		if hud:
			hud.set_party(party)
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

## Zone visits for the travel achievements (WoW's explorer feats).
func _note_visit(z: String, walked: bool) -> void:
	var seen: Array = Game.flags.get("visited", [])
	var mine_start: String = Origins.faction(Game.faction()).start
	if not seen.has(mine_start):
		seen.append(mine_start)   # you started there
	Game.flags["visited"] = seen
	if not seen.has(z):
		seen.append(z)
		if walked:
			Game.unlock("on_foot")
	for fid in Origins.FACTIONS:
		var path: Array = Origins.FACTIONS[fid].path
		if path.all(func(q): return seen.has(q)):
			Game.unlock("road_brasil" if fid == "brasil" else "road_usa")
	var conts := {}
	for q in seen:
		conts[Data.continent_of(q)] = true
	if conts.size() >= 2:
		Game.unlock("two_continents")
	Game.save_game()

## Walked off the map along a zone road: load the neighbour, arriving on its matching road.
var _zone_line_cd := 0.0
func _check_zone_line(delta: float) -> void:
	_zone_line_cd = maxf(0.0, _zone_line_cd - delta)
	if _zone_line_cd > 0.0 or _in_title or roll != null or world == null or not player.input_enabled:
		return
	if combat and combat.me and combat.me.in_combat:
		return
	var hit: Array = world.zone_line_at(player.global_position)
	if hit.is_empty() or str(hit[0]) == "":
		return
	_zone_line_cd = 3.0
	_travel(str(hit[0]), true, "e" if hit[1] == "w" else "w")

func _travel(z: String, free := false, arrive := "") -> void:
	# open world: nobody stops you, but the driver will tell you what you're in for
	var lo := int(Data.ZONES[z].levels[0])
	# another continent: a flight
	if Data.continent_of(z) != Data.continent_of(Game.zone) and not free:
		if Game.money < Data.FLIGHT_COST:
			Game.toast.emit(Tx.f("A flight to %s costs R$ %d.", [Data.CONTINENTS[Data.continent_of(z)], Data.FLIGHT_COST]), Color(1.0, 0.5, 0.35))
			return
		Game.money -= Data.FLIGHT_COST
		Game.toast.emit(Tx.f("Flight booked: R$ %d. Passport out, gringo.", Data.FLIGHT_COST), Color(0.55, 0.85, 1.0))
		Game.unlock("flight")
	if Game.player_level() < lo - 2:
		Game.toast.emit(Tx.f("Careful: %s is a level %s zone and you're level %d. Locals there hit hard.", [Data.ZONES[z].name, Data.zone_levels(z).trim_prefix("Lv "), Game.player_level()]), Color(1.0, 0.5, 0.35))
	Game.zone = z
	Game.save_game()
	_make_world(z)
	if arrive != "" and World.ZONE_ROADS.get(z, {}).has(arrive):
		var sx := -1.0 if arrive == "w" else 1.0
		var zc: float = World.ZONE_ROADS[z][arrive]
		var at := Vector3(sx * 84.0, world.ground_y(sx * 84.0, zc) + 0.5, zc)
		player.teleport(at, -PI / 2 if sx < 0 else PI / 2)   # facing into the zone
	player.make_current()
	player.input_enabled = true
	hud.set_prompt(null)
	hud.refresh()
	var zd: Dictionary = Data.ZONES[z]
	hud.zone_banner(str(zd.name), "%s  ·  %s" % [Tx.s(str(zd.sub)), Data.zone_levels(z)], Origins.faction_of_zone(z) == Game.faction())
	Sfx.music("explore")
	_note_visit(z, arrive != "")
	if z == "pantanal":
		Game.unlock("travel")
		if not Game.flags.get("pantanal_intro", false):
			Game.flags["pantanal_intro"] = true
			Game.save_game()
			hud.open_dialogue("Pantanal Norte", Tx.f("The world's biggest wetland. Jaguars, jacarés, and the toughest open mats in Mato Grosso. Mestre Jacaré runs the fazenda gym to the northeast. Beat %d locals to earn a roll with him.", Data.BOSS_REQUIRED_WINS), "", "Vamos")

	if z == "socal" and not Game.flags.get("socal_intro", false):
		Game.flags["socal_intro"] = true
		Game.save_game()
		if Game.faction() == "usa":
			hud.open_dialogue("San Diego, California", "The end of the road west. Surfers on the boardwalk, wrestlers in the garages, leg lock nerds who've watched every instructional ever made. The Gold League's headquarters sits on the hill, and Coach Dale's Garage is the last holdout on the coast. Find Professor Rae by the shuttle stop.", "", "Let's roll")
		else:
			hud.open_dialogue("San Diego, California", Tx.f("América do Norte. Here, you're the Brazilian. Surfers on the boardwalk, wrestlers in the garages, leg lock nerds who have watched every instructional ever made. Coach Dale runs The Garage up the hill. Beat %d locals first. And watch out for the gold gis: the Liga Ouro's money comes from here.", Data.BOSS_REQUIRED_WINS), "", "Let's roll")

	if z == "everglades" and not Game.flags.get("everglades_intro", false):
		Game.flags["everglades_intro"] = true
		Game.save_game()
		hud.open_dialogue("Saw Grass Landing, Florida", Tx.f("The Everglades. Sawgrass to the horizon, airboats, pythons, and gators in every ditch. Captain Gator trains his crew in a tin shed called the Gator Pit, out east past the water. Beat %d locals to earn a roll with him.", Data.BOSS_REQUIRED_WINS), "", "Let's go")
	if z == "sedona" and not Game.flags.get("sedona_intro", false):
		Game.flags["sedona_intro"] = true
		Game.save_game()
		hud.open_dialogue("Red Rock, Arizona", Tx.f("Red sandstone towers, juniper and sage, and crystal shops on every corner. Master Sol's Vortex Jiu-Jitsu sits at the foot of the mesas. He taught half the coaches in the country. Beat %d locals first.", Data.BOSS_REQUIRED_WINS), "", "Let's go")
	if z == "rio" and not Game.flags.get("rio_intro", false):
		Game.flags["rio_intro"] = true
		Game.save_game()
		hud.open_dialogue("Rio de Janeiro", Tx.f("The city where jiu-jitsu grew up. Train on the sand at Copacabana, roll with the kids on the morro, and climb Corcovado if your legs still work. Grão-Mestre Leão gives black belts at his academia behind the beach. Beat %d locals first.", Data.BOSS_REQUIRED_WINS), "", "Oss")

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
		"quartermaster":
			var parts := str(spot.arg).split("|")
			if parts[0] != Game.faction():
				player.input_enabled = false
				hud.open_dialogue(parts[1], Tx.f("%s colours? Not at my table. Go earn your Honor with your own side.", Origins.faction(Game.faction()).long), "", "Fair enough")
				return
			hud.open_quartermaster(parts[1], parts[0])
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
			if Raid.kind_for_zone(world.zone) == "compound":
				hud.open_dialogue("The Gold Compound", "Gunnar Sterling, the man behind Gold League USA, built a compound in the swamp where his franchise coaches train. Five fighters walk in: you and four friends from the road who fill the roles you don't (Lacey holds him, Coach Mae keeps you in it, finishers).\n\nHis Golden Kesa flattens whoever he's fighting. When he starts his Takedown Wave, SPRAWL (Q) or the whole party goes down. At 60%% and 30%% his franchise coaches come for Coach Mae.\n\nScaled to your level. Tap and the whole party resets.", "Gather the party", "Not now")
				return
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
		Game.toast.emit(Tx.f("Empty. Someone beat you to it: it refills in %dh.", ceili(Chests.refill_left(id) / 3600.0)), Wow.GREY)
		return
	Sfx.play("collect", -4.0)
	Game.money += int(loot.money)
	var got: Array = []
	for it in loot.items:
		if Game.add_item(str(it)) == 0:
			got.append(str(it))
		else:
			Game.toast.emit(Tx.f("Bags full: %s left in the chest.", str(Loot.item(str(it)).get("name", it))), UiKit.RED)
	Game.toast.emit("%s! R$ %d" % ["Golden chest" if loot.golden else "Hidden chest", int(loot.money)], Color(1, 0.85, 0.35))
	for it in got:
		Game.toast.emit(Tx.f("Looted: %s", str(Loot.item(it).get("name", it))), Loot.color(it))
	if loot.first:
		Game.add_xp(int(loot.xp))
		Game.toast.emit(Tx.f("Discovered! +%d XP  ·  hidden chests in %s: %d/%d", [int(loot.xp), Data.ZONES[world.zone].name, world.chests.found_count(), world.chests.chests.size()]), UiKit.ACCENT)
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
	# the blue-belt choice: Gi or No-Gi
	for id in ids:
		if Game.quest_state(id) == "active" and Data.QUESTS[id].get("path_choice", false) and Game.path == "":
			_open_path_choice(g.name, id, "gi")
			return
	for id in ids:
		if Game.quest_ready(id):
			var q: Dictionary = Data.QUESTS[id]
			_quest_prompt = "turnin:" + id
			hud.open_dialogue(g.name, Tx.f("%s\n\n%s\n\nReward: %d XP", [Tx.s(q.title).to_upper(), q.done, int(q.xp)]), "Complete quest", "Later")
			return
	for id in ids:
		if Game.quest_state(id) == "active":
			var q: Dictionary = Data.QUESTS[id]
			var lines: Array[String] = [Tx.s(q.title).to_upper(), ""]
			for i in q.obj.size():
				var pr := Game.objective_progress(id, i)
				lines.append("•  %s: %d/%d" % [q.obj[i].text, pr[0], pr[1]])
			_quest_prompt = "info"
			hud.open_dialogue(g.name, "\n".join(lines) + Tx.s("\n\nCome back when it's done."), "", "Okay")
			return
	for id in ids:
		if Game.quest_available(id):
			var q: Dictionary = Data.QUESTS[id]
			var objs: Array[String] = []
			for o in q.obj:
				objs.append("•  " + str(o.text))
			_quest_prompt = "offer:" + id
			hud.open_dialogue(g.name, Tx.f("%s\n\n%s\n\n%s\nReward: %d XP", [Tx.s(q.title).to_upper(), q.offer, "\n".join(objs), int(q.xp)]), "Accept", "Not now")
			return
	for id in ids:
		if Game.quest_locked_by_level(id):
			_quest_prompt = "info"
			hud.open_dialogue(g.name, Tx.f("I might have something for you later. Come back at level %d.", int(Data.QUESTS[id].min_level)), "", "Okay")
			return
	_quest_prompt = "info"
	hud.open_dialogue(g.name, "Obrigado for everything, gringo. Oss!", "", "Oss")

func _open_path_choice(speaker: String, qid: String, which: String) -> void:
	var p: Dictionary = Data.PATHS[which]
	var names: Array[String] = []
	for mid in p.moves:
		names.append(str(Data.MOVES[mid].name))
	_quest_prompt = "path_%s:%s" % [which, qid]
	var body := Tx.f("%s PATH  ·  %s\n\n%s\n\nSignature techniques (learned first, +%d%% damage in your path's kit):\n%s", [
		Tx.s(str(p.name)).to_upper(), p.lineage, p.desc, int(Data.PATH_MASTERY * 100), ", ".join(names)])
	if which == "gi":
		hud.open_dialogue(speaker, body + Tx.s("\n\nYou'll still train No-Gi; its signatures come about 10 levels later."), "Choose the Gi path", "Show me No-Gi")
	else:
		hud.open_dialogue(speaker, body + Tx.s("\n\nYou'll still train in the gi; its signatures come about 10 levels later."), "Choose the No-Gi path", "Not yet")

# ------------------------------------------------------------ competitions
var comp_run: Dictionary = {}   # the bracket in progress (see Data.comp_bracket)
var _comp_prompt := ""          # "enter" / "next" / "done" while a comp dialogue is open

func _open_comp(comp_id: String) -> void:
	var c: Dictionary = Data.COMPS[comp_id]
	if Game.rank < int(c.min_rank):
		hud.open_dialogue(c.name, Tx.f("%s\n\nBlack belts only. Come back when Leão ties one around your waist.", c.blurb), "", "Okay")
		return
	var nonce := int(Game.counters.get("comp_entries", 0))
	comp_run = Data.comp_bracket(comp_id, Game.rank, Game.player_name, nonce)
	var belt: String = Data.BELTS[comp_run.belt].name
	var best := Game.best_medal(comp_id)
	var lines: Array[String] = [c.blurb, "", Tx.f("Division: %s Belt  ·  %d in the bracket", [belt, comp_run.entries.size()])]
	if best != "":
		lines.append(Tx.f("Your best here at %s belt: %s", [belt.to_lower(), best.capitalize()]))
	lines.append("")
	lines.append(Tx.f("First round: %s (%s)", [comp_run.path[0].name, comp_run.path[0].academy]))
	lines.append("Lose once and you're out. Win the final for gold.")
	_comp_prompt = "enter"
	player.input_enabled = false
	hud.open_dialogue(c.name, "\n".join(lines), "Enter the bracket", "Not now")

func _comp_start_match() -> void:
	if comp_run.round == 0:
		Game.counters["comp_entries"] = int(Game.counters.get("comp_entries", 0)) + 1
	var rd: int = comp_run.round
	var m := {"id": comp_run.id, "round_name": Data.round_name(comp_run.rounds, rd), "opp": comp_run.path[rd], "final": rd == comp_run.rounds - 1}
	Game.toast.emit(Tx.f("%s: %s (%s)", [m.round_name, m.opp.name, str(m.opp.get("academy", ""))]), Color(1, 0.85, 0.35))
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
		hud.open_dialogue(c.name, Tx.f("%s won!\n\nNext up, the %s: %s (%s), %s guy.", [Data.round_name(rounds, rd), Data.round_name(rounds, rd + 1).to_lower(), nxt.name, nxt.academy, nxt.style]), "Next match", "Withdraw")
		return
	var belt: int = comp_run.belt
	var text := ""
	if medal != "":
		var xp := Game.award_medal(comp_run.id, belt, medal)
		Sfx.play("win" if medal == "gold" else "levelup")
		var head: String = {"gold": "GOLD MEDAL! Campeão!", "silver": "SILVER MEDAL", "bronze": "BRONZE MEDAL"}[medal]
		var body: String = {"gold": Tx.f("Top of the podium at the %s. The whole academy is in the group chat.", c.name),
			"silver": Tx.f("Lost a tough final, but you're on the podium at the %s.", c.name),
			"bronze": Tx.f("Semifinal loss, but bronze at the %s is a real medal. Shake it off, oss.", c.name)}[medal]
		text = Tx.f("%s\n\n%s\n\n+%d XP", [head, body, xp])
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
			hud.open_dialogue(Tx.f("Territory: %s", t.name), Tx.f("%s plant their flag here. Take it with a 3v3: their best three against your first three (set your lineup on any Team Challenge board).\n\nHold it for +10%% XP from rolls in %s. Rivals will come back for it.", [t.academy, Data.ZONES[t.zone].name]), "Challenge for the flag", "Not now")
		"attacked":
			_territory_prompt = tid
			hud.open_dialogue(Tx.f("Territory: %s", t.name), Tx.f("%s are back for %s! Defend it in a 3v3 within %dh or the flag falls.", [t.academy, t.name, maxi(1, Game.defend_left(tid) / 3600)]), "Defend it", "Later")
		_:
			var left := int(Game.territories[tid].attack_at) - Game.now()
			hud.open_dialogue(Tx.f("Territory: %s", t.name), Tx.f("Gringo BJJ holds %s. Everything quiet: the rivals regroup for about %dh.", [t.name, maxi(1, left / 3600)]), "", "Oss")

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
		Game.toast.emit(Tx.f("Coaching %s from the corner", str(ours.name)), Team.ROLES.coach.color)
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
		team_board.result_text = (Tx.f("%s beat %s, %d fighters left standing.  +%d XP", [Team.TEAM_NAMES[0], team_match.academy, team_match.ours.size() - team_match.i, xp])) if won else (Tx.f("%s win this one.  +%d XP", [team_match.academy, xp]))
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
	circuit_board.result_text = (Tx.f("Five straight wins, the last against a master at full strength. +%d XP and the Circuito Champion Rashguard.", xp)) if champ else ("%d win%s this run. +%d XP. The road resets every run; the cards will be different next time." % [wins, "" if wins == 1 else "s", xp])
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
	Game.toast.emit(Tx.f("Daily Challenge: %s", str(dc.opp.name)), Color(1, 0.85, 0.35))
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
		elif _rival != null and is_instance_valid(_rival):
			_duel_menu(_rival)
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
			hud.open_dialogue("Mestre Onça", Tx.f("So you're the gringo everyone's talking about. Before you step on my mat, beat %d fighters around town. You have %d. Vai!", [Data.BOSS_REQUIRED_WINS, Game.town_wins()]), "", "Oss")
			return
		hud.open_dialogue("Mestre Onça", o.intro, "Oss! Roll with Mestre Onça")
		return
	if npc.opp_id == "jacare" and not Game.beaten("jacare"):
		Game.flags["met_jacare"] = true
		if Game.town_wins("pantanal") < Data.BOSS_REQUIRED_WINS:
			hud.open_dialogue("Mestre Jacaré", Tx.f("Onça's student, eh? Beat %d of my locals first. You have %d. The swamp will teach you.", [Data.BOSS_REQUIRED_WINS, Game.town_wins("pantanal")]), "", "Oss")
			return
	if npc.opp_id in ["boone", "gator", "sol"] and not Game.beaten(npc.opp_id):
		var zid := Data.zone_of(npc.opp_id)
		if Game.town_wins(zid) < Data.BOSS_REQUIRED_WINS:
			var gate := {"boone": "So you're the new kid everybody's talking about. Before you step on my mat, beat %d fighters around town. You have %d. Go on.",
				"gator": "Boone's student, huh? Beat %d of my swamp rats first. You have %d. The swamp will teach you.",
				"sol": "Patience. Roll with %d people in this valley first. You have %d. The desert decides when you're ready."}
			hud.open_dialogue(str(o.name), gate[npc.opp_id] % [Data.BOSS_REQUIRED_WINS, Game.town_wins(zid)], "", "Oss")
			return
	var intro: String = o.intro
	if Game.beaten(npc.opp_id):
		intro = "Rematch? I've been drilling. (Reduced XP for rematches.)"
	hud.open_dialogue(Tx.f("%s  ·  %s", [o.name, Data.rank_name(int(o.rank))]), intro)

func _on_dialogue_choice(accepted: bool) -> void:
	if _party_ask != "":
		var pk := _party_ask
		_party_ask = ""
		player.input_enabled = true
		if pk == "party":
			party.answer(accepted)
		elif pk == "trade":
			trade.answer(accepted)
		else:
			coop.answer(accepted)
		return
	if _duel_ask != "":
		var kind := _duel_ask
		_duel_ask = ""
		player.input_enabled = true
		if kind == "incoming":
			pvp.answer(accepted)
		elif _duel_rp and is_instance_valid(_duel_rp):
			var rid := -1
			for id in remotes:
				if remotes[id] == _duel_rp:
					rid = id
			if accepted and rid >= 0:
				pvp.invite(rid, _duel_rp.char)

			elif not accepted and str(_duel_rp.char.get("faction", "brasil")) != Game.faction():
				var nm := str(_duel_rp.char.get("name", "?"))
				if int(_rival_cd.get(nm, 0)) + RIVAL_COOLDOWN <= int(Time.get_unix_time_from_system()):
					_start_rival(_duel_rp)
		return
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
		if accepted and not _party_run(Raid.kind_for_zone(world.zone)):
			_start_raid()
		elif accepted:
			player.input_enabled = true
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
		if parts[0] == "path_gi" or parts[0] == "path_nogi":
			var giver_id: String = Data.QUESTS[parts[1]].giver
			if accepted:
				Game.set_path("gi" if parts[0] == "path_gi" else "nogi")
				_open_quest(giver_id)
				return
			if parts[0] == "path_gi":
				_open_path_choice(Data.QUEST_GIVERS[giver_id].name, parts[1], "nogi")
				return
			player.input_enabled = true
			return
		if accepted and parts[0] == "offer":
			Game.accept_quest(parts[1])
			if Data.QUESTS[parts[1]].get("path_choice", false) and Game.path == "":
				_open_quest(Data.QUESTS[parts[1]].giver)
				return
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
				Game.toast.emit(Tx.f("You withdraw from the %s.", Data.COMPS[comp_run.id].name), UiKit.MUTED)
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
		roll.announce(Tx.f("%s is waiting for the winner!", npc.mob.name))

func _queue_names() -> Array:
	var out: Array = []
	for q in _mob_queue:
		if is_instance_valid(q):
			out.append(Tx.f("%s (Lv %d)", [q.mob.name, Data.display_level(float(q.mob.level))]))
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
	Game.toast.emit(Tx.f("%s wants to roll!", npc.mob.name), Color(1, 0.6, 0.4))
	_start_mob(npc)

## You tapped in the open world: no XP, a gloating winner, a coach's note, and a choice.
var _tap_prompt := false

func _on_player_tapped(info: Dictionary) -> void:
	_tap_prompt = true
	player.input_enabled = false
	var how := Tx.f(" with a %s", str(info.how)) if str(info.how) != "" else ""
	hud.open_dialogue(Tx.f("You tapped to %s%s", [str(info.by), how]),
		Tx.f("No XP for this one, and they won't let you forget it (⚔ Revenge: beat them for bonus XP).\n\n%s\n\nShake it off and get up right here (35%% Composure, Rattled: -15%% damage for 60s), or walk it off back at the academy (full Composure).", str(info.lesson)),
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
	hud.open_dialogue(Tx.f("%s  ·  %s", [str(j.who), str(j.name)]), str(j.ask), "Help out", "Not now")

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
			Game.toast.emit(Tx.f("%s: +%d XP, R$ %d", [str(j.name), int(j.xp), int(j.money)]), Color(1, 0.85, 0.35))
			if str(j.get("item", "")) != "":
				Game.add_item(str(j.item))
				Game.toast.emit(Tx.f("Received: %s", str(Loot.item(str(j.item)).get("name", j.item))), Color(0.95, 0.9, 0.7))
			Game.bump("jobs_done")
		Game.save_game()
		hud.refresh())
	_drill.start(str(j.attr), j)

# ------------------------------------------------------------ raids
var _raid_prompt := false

var _raid_kind := ""

func _start_raid(kind := "") -> void:
	player.input_enabled = true
	_raid_kind = kind
	var fwd := Vector3(sin(player.rig.global_rotation.y), 0, cos(player.rig.global_rotation.y))
	combat.start_raid(player.global_position + fwd * 7.0, kind)

## Group Finder (K): enter a dungeon from anywhere.
func start_dungeon(id: String) -> void:
	if combat.me.in_combat or (combat.raid != null and is_instance_valid(combat.raid)) or (pvp and pvp.busy()):
		Game.toast.emit("Finish what you're doing first.", Color(1, 0.5, 0.4))
		return
	hud.close_finder()
	if (coop and coop.busy()):
		Game.toast.emit("Finish what you're doing first.", Color(1, 0.5, 0.4))
		return
	if _party_run(id):
		return
	Game.toast.emit(Tx.f("Entering %s...", str(Raid.DUNGEONS[id].title).capitalize()), Color(1, 0.85, 0.4))
	_start_raid(id)

func _on_raid_over(won: bool) -> void:
	await get_tree().create_timer(2.5).timeout
	player.input_enabled = false
	if Raid.DUNGEONS.has(_raid_kind):
		var dd: Dictionary = Raid.DUNGEONS[_raid_kind]
		if won:
			hud.open_dialogue(str(dd.title).capitalize(), Tx.f("%s\n\nYour loot is in your bags. Run it again any time from the Group Finder (K): it scales to your level.", str(dd.victory)), "", "Oss")
		else:
			hud.open_dialogue("Wiped", Tx.f("%s\n\nRead the cast bars: Sprawl (Q) takedown waves, Frame (R) his Second Breath, Defend (T) chokes aimed at you. Kill the adds before they reach your healer.", str(dd.wipe)), "", "Oss")
		_raid_kind = ""
		hud.refresh()
		return
	if won and Raid.kind_for_zone(world.zone) == "compound":
		hud.open_dialogue("The Gold Compound", "Gunnar Sterling taps! His franchise coaches are tearing up their contracts.\n\nYour loot is in your bags. Run it again any time: he scales to your level.", "", "Oss")
	elif won:
		hud.open_dialogue("Covil da Sucuri", "The Sucuri taps! The old gym is open again, and his students are already asking to train with you.\n\nYour loot is in your bags. Run it again any time: he scales to your level.", "", "Oss")
	else:
		hud.open_dialogue("Wiped", "Watch the cast bar: Sprawl (Q) the Takedown Wave, and help your partners with the students when they come for your Professor.", "", "Oss")
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
		"pvp":
			if pvp:
				pvp.on_bout_over(won, bool(info.get("forfeit", false)))
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
		"arena":
			await get_tree().create_timer(1.6).timeout
			_arena_after(won)
		"rival":
			var rx := Game.record_rival(res)
			await get_tree().create_timer(1.6).timeout
			if won:
				Game.toast.emit(Tx.f("Shadow beaten! +%d XP for %s.", [rx, Origins.faction(Game.faction()).long]), Wow.GOLD)
		"daily":
			var xp := Game.record_daily(res)
			await get_tree().create_timer(1.6).timeout
			player.input_enabled = false
			if won:
				hud.open_dialogue("Daily Challenge", Tx.f("Won! Streak: %d day%s.\n\n+%d XP. Same time tomorrow.", [Game.daily_streak(), "" if Game.daily_streak() == 1 else "s", xp]), "", "Oss")
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
			Game.toast.emit(Tx.f("Next challenger: %s!", next.mob.name), Color(1, 0.6, 0.4))
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
