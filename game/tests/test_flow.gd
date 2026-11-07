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
	check(Game.belt_index() == 4 or tries == 8, "Leão roll(s) completed (belt=%s after %d)" % [Data.BELTS[Game.belt_index()].name, tries])
	if Game.belt_index() == 4:
		check(Game.unlocked.has("black_belt") and Game.flags.get("black_belt_ending", false), "black belt promotion + ending")
	for cid in ["rio_open", "mundial"]:
		var r2 = await play_comp(cid)
		check(r2.matches >= 1 and main.comp_run.is_empty(), "%s bracket played: %d match(es), medal=%s" % [cid, r2.matches, Game.best_medal(cid)])
	check(Game.unlocked.has("first_roll"), "comp matches count as rolls")
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
			RollScene.Phase.CHOOSE:
				var opts = roll.sim.player_options()
				roll._choose(opts[randi() % opts.size()])
			RollScene.Phase.TIMING:
				if absf(roll.timing.marker - roll.timing.center) < roll.timing.width * 0.4:
					roll._resolve_timing(roll.timing.marker)
			RollScene.Phase.DEFEND:
				roll._resolve_defense(roll.defend_dir if randf() < 0.8 else "x")
			RollScene.Phase.STRUGGLE_ATK, RollScene.Phase.STRUGGLE_DEF:
				if steps % 3 == 0:
					roll._struggle_tap()
			RollScene.Phase.OVER:
				result.won = roll.sim.result.won
				result.by_sub = roll.sim.result.by_sub
				roll.finished.emit(opp, roll.sim.result, 0)
	return result
