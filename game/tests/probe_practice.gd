extends Node
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(6)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	for i in 10: await get_tree().process_frame
	main.hud._close_dialogue(false)
	var c: WorldCombat = main.combat
	var spots: Array = main.world.spots.filter(func(s): return s.action == "reads")
	print("reads spots: ", spots.size())
	main._start_practice()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var seen := {}
	var t0 := Time.get_ticks_msec()
	var shot := false
	while Time.get_ticks_msec() - t0 < 90000 and not c.practice.is_empty():
		await get_tree().create_timer(0.1).timeout
		var pu = c.practice.get("u")
		if int(Time.get_ticks_msec() / 100) % 50 == 0:
			print("casts ", c.practice.casts, " reads ", c.practice.reads, " pdown ", pu.down(), " d ", snappedf(c.core.dist(c.me, pu), 0.1), " aiT ", snappedf(pu.ai_t, 0.1), " in_combat ", pu.in_combat)
		if pu == null:
			break
		if not pu.cast.is_empty() and float(pu.cast.t) > 0.45 and not seen.has(pu.cast):
			seen[pu.cast] = true
			if not shot:
				shot = true
				get_viewport().get_texture().get_image().save_png("/home/claude/shots/practice.png")
			if rng.randf() < 0.85:
				c.press(CombatCore.counter_kind(pu.cast.ab))
	print("loop end: practice=", c.practice.keys(), " elapsed=", (Time.get_ticks_msec() - t0) / 1000.0)
	await get_tree().create_timer(2.0).timeout
	print("dialog: ", main.hud.dialogue_open(), " best=", Game.flags.get("practice_best", -1), " hp=", int(c.me.hp), "/", int(c.me.max_hp))
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/practice_end.png")
	get_tree().quit()
