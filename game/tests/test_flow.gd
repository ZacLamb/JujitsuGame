extends Node
## Bot plays full rolls through the real scenes. Run: godot --headless --path . res://tests/test_flow.tscn

var main: Node
var fails := 0
var frames := 0

func check(c: bool, m: String) -> void:
	if not c:
		fails += 1
		printerr("FAIL: ", m)
	else:
		print("ok   ", m)

func _ready() -> void:
	Game.test_mode = true
	Engine.time_scale = 10.0
	Game.reset()
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	check(main.get_children().any(func(c): return c is CanvasLayer and c.get_child_count() > 0 and c.get_child(0) is StyleSelect), "new game shows style select")
	for c in main.get_children():
		if c is CanvasLayer and c.get_child_count() > 0 and c.get_child(0) is StyleSelect:
			c.get_child(0).chosen.emit("judoka", "Bot", 2)
	await get_tree().process_frame
	check(Game.style == "judoka" and Game.gi_index == 2, "style chosen")
	main.hud._close_dialogue(false)
	check(main.player.input_enabled, "player can move after intro")
	var talents_by_style := {"judoka": ["shot_speed", "sprawl", "t_snap_down", "t_uchi_mata"], "guard": ["hip_mobility", "retention", "t_omoplata", "slippery"],
		"wrestler": ["shot_speed", "shot_speed", "scramble"], "athlete": ["hip_mobility", "heavy_hips"], "passer": ["heavy_hips", "heavy_top", "t_leg_drag", "killer_instinct"]}
	for st in Rpg.STYLE_ORDER:
		Game.reset()
		Game.choose_style(st, "Bot", 0)
		Game.set_level(5)
		for t in talents_by_style[st]:
			Game.learn(t)
		while Game.attr_points() > 0:
			Game.raise_attr(Rpg.ATTR_ORDER[randi() % 5])
		for opp in ["rafa", "tiago", "onca"]:
			var r = await play_roll(opp, true)
			check(r.done, "[%s] roll vs %s completed (won=%s by_sub=%s)" % [st, opp, r.won, r.by_sub])
	check(Game.unlocked.has("first_roll"), "first_roll unlocked")
	# ---- quests: accept from a giver, progress, turn in
	check(main.world.quest_givers.has("kaique") and main.world.quest_givers["kaique"].marker.visible, "Kaique has a quest marker")
	main._open_quest("juninho")
	check(main._quest_prompt == "offer:know_town", "Juninho offers Know the Town")
	main.hud._close_dialogue(true)
	check(Game.quest_state("know_town") == "active", "quest accepted")
	for lid in ["plaza", "cathedral", "academia", "market"]:
		Game.discover_landmark(lid)
	check(Game.quest_ready("know_town") and main.world.quest_givers["juninho"].marker.text == "?", "objective done, giver shows ?")
	var lv_before: int = Game.player_level()
	main._open_quest("juninho")
	main.hud._close_dialogue(true)
	check(Game.quest_state("know_town") == "done" and Game.unlocked.has("quest_1"), "quest turned in (lv %d -> %d)" % [lv_before, Game.player_level()])
	main._open_quest("kaique")
	main.hud._close_dialogue(true)
	Game.complete_drill("strength")
	Game.complete_drill("cardio")
	check(Game.quest_ready("shrimping"), "drill quest counts drills after accepting")
	main._open_quest("rosa")
	main.hud._close_dialogue(true)
	await get_tree().process_frame
	check(main.world._reach_nodes.size() == 1, "lost belt marker appears")
	Game.quest_event("reach", "lost_faixa:0")
	await get_tree().process_frame
	check(Game.quest_ready("lost_faixa") and main.world._reach_nodes.is_empty(), "reaching the spot completes it")
	main.hud._close_dialogue(false)
	# ---- travel to the Pantanal and play it through
	Game.reset()
	Game.choose_style("athlete", "Bot", 1)
	Game.set_level(8)
	for t in ["hip_mobility", "hip_mobility", "heavy_hips", "heavy_hips", "t_leg_drag", "killer_instinct"]:
		Game.learn(t)
	while Game.attr_points() > 0:
		Game.raise_attr(Rpg.ATTR_ORDER[randi() % 5])
	main._travel("pantanal")
	await get_tree().process_frame
	check(Game.zone == "caceres", "white belt cannot ride to the Pantanal")
	main.hud._close_dialogue(false)
	Game.promote_belt(1)
	main._travel("pantanal")
	await get_tree().process_frame
	check(Game.zone == "pantanal" and main.world.zone == "pantanal", "blue belt travels to the Pantanal")
	check(main.world.fighters.size() == 5 and main.world.fighters.has("jacare"), "pantanal fighters spawned (%d)" % main.world.fighters.size())
	check(main.world.spots.size() >= 6, "pantanal has bus + drill spots (%d)" % main.world.spots.size())
	main.hud._close_dialogue(false)
	for opp in ["bruna", "zeca", "tuca", "neide", "jacare"]:
		var r = await play_roll(opp, true)
		check(r.done, "[pantanal] roll vs %s completed (won=%s by_sub=%s)" % [opp, r.won, r.by_sub])
	# drill minigame end to end
	Game.drills_ready = true
	var before_train := int(Game.train.get("cardio", 0))
	main._start_drill("cardio")
	await get_tree().process_frame
	for i in 200:
		if main._drill == null:
			break
		if main._drill._active:
			main._drill._tap()
		else:
			for c in main._drill._body.get_children():
				if c is Button and c.text == "Back":
					c.pressed.emit()
					break
		await get_tree().process_frame
	check(main._drill == null and int(Game.train.get("cardio", 0)) == before_train + 1, "cardio drill completes and counts (drill=%s train=%s before=%d)" % [main._drill, Game.train, before_train])
	check(not Game.drills_ready, "drills need a roll to refresh")
	# ---- bus network to the Chapada
	Game.promote_belt(2)
	main._use_spot({"action": "travel_menu", "arg": ""})
	check(main.hud.travel_open(), "bus opens the travel menu")
	main.hud._close_travel()
	main.hud.travel_chosen.emit("chapada")
	await get_tree().process_frame
	check(main.world.zone == "chapada" and main.world.fighters.size() == 6, "purple belt rides to the Chapada (%d fighters)" % main.world.fighters.size())
	var py: float = main.player.global_position.y
	check(py > -1.0 and py < 3.0, "player spawns on the ground in the Chapada (y=%.2f)" % py)
	check(main.world.ground_y(-30, -50) > 5.0 and main.world.ground_y(40, 50) < 1.5, "plateau high, village low")
	main.hud._close_dialogue(false)
	for opp in ["iara", "biro", "joaquim", "rita", "gaucho", "cachoeira"]:
		var r = await play_roll(opp, true)
		check(r.done, "[chapada] roll vs %s completed (won=%s by_sub=%s)" % [opp, r.won, r.by_sub])
	# ---- competitions: the Mundial is black belts only
	main._open_comp("mundial")
	check(main.comp_run.is_empty() and main.hud.dialogue_open(), "Mundial locked below black belt")
	main.hud._close_dialogue(false)
	# ---- brown belt rides to Rio for the black belt
	Game.promote_belt(3)
	main.hud.travel_chosen.emit("rio")
	await get_tree().process_frame
	check(main.world.zone == "rio" and main.world.fighters.size() == 6, "brown belt rides to Rio (%d fighters)" % main.world.fighters.size())
	var ry: float = main.player.global_position.y
	check(ry > -1.0 and ry < 3.0, "player spawns on the ground in Rio (y=%.2f)" % ry)
	check(main.world.ground_y(-46, -62) > 18.0 and main.world.ground_y(0, 62) < -1.3, "Corcovado high, ocean low")
	main.hud._close_dialogue(false)
	for opp in ["dudu", "luana", "baiano", "tatu", "bia"]:
		var r = await play_roll(opp, true)
		check(r.done, "[rio] roll vs %s completed (won=%s by_sub=%s)" % [opp, r.won, r.by_sub])
	var tries := 0
	while Game.belt_index() < 4 and tries < 8:
		await play_roll("leao", true)
		main.hud._close_dialogue(false)
		tries += 1
	check(Game.has_item("leao_gi") == (Game.belt_index() == 4), "Leão drops his gi when beaten")
	check(Game.belt_index() == 4 or tries == 8, "Leão roll(s) completed (belt=%s after %d)" % [Data.BELTS[Game.belt_index()].name, tries])
	if Game.belt_index() == 4:
		check(Game.unlocked.has("black_belt") and Game.flags.get("black_belt_ending", false), "black belt promotion + ending")
	for cid in ["rio_open", "mundial"]:
		var r2 = await play_comp(cid)
		check(r2.matches >= 1 and main.comp_run.is_empty(), "%s bracket played: %d match(es), medal=%s" % [cid, r2.matches, Game.best_medal(cid)])
	check(Game.unlocked.has("first_roll"), "comp matches count as rolls")
	# ---- 5v5 team challenge: board spot, lineup, one live bout, the rest simulated
	var tspot: Dictionary = {}
	for sp in main.world.spots:
		if sp.action == "team":
			tspot = sp
	check(not tspot.is_empty(), "zone has a team challenge board")
	main._use_spot(tspot)
	check(main.team_match != null and main.team_board.visible and main.team_board.state == "lineup", "team board opens on the lineup")
	main.team_board.start_pressed.emit()
	main.team_board.play_pressed.emit()
	check(main.roll != null and not main.roll.team.is_empty(), "taking the mat starts a team bout")
	var tb = await play_roll_existing("team")
	check(tb.done and main.team_match != null and main.team_match.bouts == 1, "team bout finished and recorded on the board")
	var guard_t := 0
	while main.team_match != null and not main.team_match.over() and guard_t < 12:
		main.team_board.sim_pressed.emit()
		guard_t += 1
	check(main.team_match.over() and main.team_board.state == "done", "team match ends (won=%s, bouts=%d)" % [main.team_match.won(), main.team_match.bouts])
	main.team_board.close_pressed.emit()
	check(main.team_match == null and main.player.input_enabled, "closing the board returns to the world")
	# ---- Circuito: draft a card, fight the opening round live, walk away
	var cspot: Dictionary = {}
	for sp in main.world.spots:
		if sp.action == "circuit":
			cspot = sp
	check(not cspot.is_empty(), "zone has a Circuito board")
	main._use_spot(cspot)
	check(main.circuit_run != null and main.circuit_board.state == "draft", "Circuito opens on the card draft")
	main.circuit_board.card_picked.emit(main.circuit_run.offers[0])
	check(main.circuit_run.perks.size() == 1 and main.circuit_board.state == "ready", "card drafted")
	main.circuit_board.fight_pressed.emit()
	check(main.roll != null and not main.roll.team.is_empty(), "Circuito match starts a roll")
	var cr = await play_roll_existing("circuit")
	check(cr.done and main.circuit_run != null, "Circuito match finished (won=%s)" % cr.won)
	if not main.circuit_run.over():
		main.circuit_board.quit_pressed.emit()
	check(main.circuit_board.state == "done" and int(Game.counters.get("circuit_runs", 0)) == 1, "run recorded")
	main.circuit_board.close_pressed.emit()
	check(main.circuit_run == null and main.player.input_enabled, "back to the world after the run")
	# ---- academy wars: challenge a flag, sim the 3v3
	var fspot: Dictionary = {}
	for sp in main.world.spots:
		if sp.action == "territory":
			fspot = sp
	check(not fspot.is_empty(), "zone has territory flags")
	main._use_spot(fspot)
	check(main.hud.dialogue_open(), "territory dialogue")
	main.hud._close_dialogue(true)
	check(main.team_match != null and main.team_match.territory == str(fspot.arg) and main.team_match.ours.size() == 3, "3v3 territory fight on the team board")
	main.team_board.start_pressed.emit()
	var g3 := 0
	while not main.team_match.over() and g3 < 8:
		main.team_board.sim_pressed.emit()
		g3 += 1
	var took: bool = main.team_match.won()
	check(Game.holds(str(fspot.arg)) == took, "flag changes hands only on a win (won=%s)" % took)
	main.team_board.close_pressed.emit()
	# ---- daily challenge through the real roll scene
	main._start_daily()
	check(main.roll != null and not main.roll.daily.is_empty(), "daily challenge starts a roll")
	var rr = await play_roll_existing("daily")
	check(rr.done and Game.daily.has("last_try"), "daily challenge recorded (won=%s)" % rr.won)
	main._travel("caceres")
	await get_tree().process_frame
	check(main.world.zone == "caceres" and main.world.fighters.has("onca"), "bus back to Cáceres")
	print("rank after rolls: ", Data.rank_name(Game.rank), " xp=", Game.xp, " achievements=", Game.unlocked.keys())
	# walking: push the player forward for a bit and confirm movement + floor
	Engine.time_scale = 1.0
	var p0: Vector3 = main.player.global_position
	main.player.touch_move = Vector2(0, -1)
	for i in 60:
		await get_tree().physics_frame
	main.player.touch_move = Vector2.ZERO
	check(main.player.global_position.distance_to(p0) > 2.0, "player walks (%.1fm)" % main.player.global_position.distance_to(p0))
	check(main.player.global_position.y > -1.0, "player stays above ground")
	# ---- desktop mouse: click a fighter to walk over and challenge them
	main.player.walk_target = null
	var target: Npc = main.world.fighters["rafa"]
	main.player.teleport(target.global_position + Vector3(0, 1, -9), 0.0)
	await get_tree().physics_frame
	main.player.walk_target = target
	var arrived := false
	for i in 400:
		await get_tree().physics_frame
		if main.hud.dialogue_open():
			arrived = true
			break
	check(arrived and main._talking_to == target, "click-to-interact walks to the fighter and opens the challenge")
	main.hud._close_dialogue(false)
	main.hud.minimap.toggle_big()
	check(main.hud.minimap.big and main.world.map_footprints.size() > 10, "world map opens with building footprints (%d)" % main.world.map_footprints.size())
	main.hud.minimap.toggle_big()
	main.player.input_enabled = true
		# ---- phone controls: joystick, follow camera, pinch zoom, auto-run
	var tc: TouchControls = main.hud.touch
	tc.visible = true
	check(TouchControls.shape(Vector2(0.1, 0)) == Vector2.ZERO and TouchControls.shape(Vector2(1, 0)).is_equal_approx(Vector2(1, 0)), "joystick dead zone and full push")
	var w: float = tc.get_viewport_rect().size.x
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = Vector2(w * 0.15, 400)
	ev.pressed = true
	tc._input(ev)
	var dr := InputEventScreenDrag.new()
	dr.index = 0
	dr.position = Vector2(w * 0.15 + 80, 400)   # push right
	tc._input(dr)
	var yaw0: float = main.player.cam_yaw
	var pa: Vector3 = main.player.global_position
	for i in 90:
		await get_tree().physics_frame
	check(main.player.global_position.distance_to(pa) > 2.0, "joystick moves the player")
	check(absf(wrapf(main.player.cam_yaw - yaw0, -PI, PI)) > 0.2, "follow camera swings behind the runner")
	ev.pressed = false
	tc._input(ev)
	var d0: float = main.player.cam_dist
	var t1 := InputEventScreenTouch.new(); t1.index = 1; t1.position = Vector2(w * 0.6, 300); t1.pressed = true
	var t2 := InputEventScreenTouch.new(); t2.index = 2; t2.position = Vector2(w * 0.8, 300); t2.pressed = true
	tc._input(t1)
	tc._input(t2)
	var d2 := InputEventScreenDrag.new(); d2.index = 2; d2.position = Vector2(w * 0.7, 300)
	tc._input(d2)
	check(main.player.cam_dist > d0, "pinch in zooms the camera out (%.1f -> %.1f)" % [d0, main.player.cam_dist])
	t1.pressed = false
	t2.pressed = false
	tc._input(t2)
	tc._input(t1)
	tc.set_autorun(true)
	var pr: Vector3 = main.player.global_position
	for i in 60:
		await get_tree().physics_frame
	check(main.player.global_position.distance_to(pr) > 2.0, "auto-run moves without touching")
	tc.release_all()
	check(not main.player.autorun, "releasing controls stops auto-run")
	print("\n%s (%d failures)" % ["PASS" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)

func play_comp(cid: String) -> Dictionary:
	main._open_comp(cid)
	var size: int = main.comp_run.get("entries", []).size()
	check(main.hud.dialogue_open() and size >= 8, "%s bracket opens (%d entries)" % [cid, size])
	main.hud._close_dialogue(true)
	var matches := 0
	while matches < 6 and main.roll != null:
		await play_roll_existing("comp")
		matches += 1
		if main._comp_prompt == "next":
			main.hud._close_dialogue(true)
		else:
			break
	main.hud._close_dialogue(false)
	return {"matches": matches}

func play_roll(opp: String, skilled: bool) -> Dictionary:
	main._start_roll(opp)
	return await play_roll_existing(opp)

func play_roll_existing(opp: String) -> Dictionary:
	var roll: RollScene = main.roll
	var steps := 0
	var result := {"done": false, "won": false, "by_sub": false}
	while steps < 20000:
		steps += 1
		await get_tree().process_frame
		if main.roll == null:
			result.done = true
			break
		match roll.phase:
			RollScene.Phase.LIVE:
				var sim: RollSim = roll.sim
				if not sim.struggle.is_empty():
					if steps % 3 == 0:
						roll._struggle_tap()
				elif not sim.opp_cast.is_empty() and float(sim.opp_cast.t) > 0.3:
					var need := sim.cast_counter(sim.opp_cast)
					roll._defend((need if need != "grip" else "frame") if randf() < 0.8 else "base")
				elif sim.cast.is_empty() and steps % 10 == 0:
					var moves: Array = sim.player_bar().filter(func(sl): return sl.kind == "move" and sim.block_reason(sl) == "")
					if not moves.is_empty() and sim.control >= 2:
						roll._use(moves[randi() % moves.size()].id)
					else:
						roll._use("grip")
			RollScene.Phase.OVER:
				if roll.action_body.get_child_count() > 0:
					result.won = roll.sim.result.won
					result.by_sub = roll.sim.result.by_sub
					roll.finished.emit(opp, roll.sim.result, 0)
	return result
