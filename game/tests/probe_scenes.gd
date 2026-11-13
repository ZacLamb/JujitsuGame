extends Node
## Plays the staged scenes and saves frames from each beat.
var main: Node
func _shots(tag: String, n: int, gap: float) -> void:
	for i in n:
		await get_tree().create_timer(gap).timeout
		get_viewport().get_texture().get_image().save_png("/home/claude/shots/sc_%s_%d.png" % [tag, i])
func _ready() -> void:
	Game.test_mode = true
	Scenes.force = true
	Game.reset()
	Game.choose_style("guard", "Zac", 0)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 10: await get_tree().process_frame
	main._hook_scenes()
	var which := "opening"
	for a in OS.get_cmdline_user_args():
		which = a
	if which == "opening":
		main.scenes.opening()
		await _shots("open", 8, 2.0)
	elif which == "promo":
		var b: Npc = main._npc_for("onca")
		var bp := b.global_position + Vector3(1.6, 0, 1.6)
		main.player.teleport(Vector3(bp.x, main.world.ground_y(bp.x, bp.z) + 0.3, bp.z), 0.0)
		for i in 20: await get_tree().process_frame
		main.scenes.promotion(1, "onca", Data.BELTS[0].color)
		await _shots("promo", 9, 2.0)
	elif which == "boss":
		var b: Npc = main._npc_for("onca")
		var bp := b.global_position + Vector3(1.8, 0, 1.2)
		main.player.teleport(Vector3(bp.x, main.world.ground_y(bp.x, bp.z) + 0.3, bp.z), 0.0)
		for i in 20: await get_tree().process_frame
		main.scenes.boss_entrance(b, func(): print("FIGHT START"))
		await _shots("boss", 5, 1.6)
	elif which == "flow":
		Game.promote_belt(1)
		var ok := false
		for i in 200:
			await get_tree().process_frame
			if main.scenes.busy:
				ok = true
				break
		print("FLOW promotion started=", ok)
	elif which == "bossfight":
		Game.set_level(10)
		main.combat.rebuild_player()
		var b: Npc = main._npc_for("onca")
		var bp := b.global_position + Vector3(1.6, 0, 1.0)
		main.player.teleport(Vector3(bp.x, main.world.ground_y(bp.x, bp.z) + 0.3, bp.z), 0.0)
		for i in 20: await get_tree().process_frame
		CombatCore.gm_god = true
		main.player.input_enabled = true
		main.combat.duel(b)
		var u = main.combat.unit_for(b)
		print("boss_id=", u.boss_id, " boss=", u.boss)
		u.sig_t = 1.0
		var got := {}
		main.combat.core.event.connect(func(e):
			if str(e.t) in ["signature", "phase"] and not got.has(str(e.t)):
				got[str(e.t)] = true
				print("EV ", e.t)
				await get_tree().create_timer(0.9).timeout
				get_viewport().get_texture().get_image().save_png("/home/claude/shots/sc_bf_%s.png" % str(e.t)))
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 60000 and got.size() < 2:
			await get_tree().create_timer(0.3).timeout
			if got.has("signature") and u.phase == 1:
				u.hp = u.max_hp * 0.45
		await get_tree().create_timer(1.5).timeout
	get_tree().quit()
