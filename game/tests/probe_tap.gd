extends Node
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/tap_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Scenes.force = true
	Engine.max_physics_steps_per_frame = 60
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var w: World = main.world
	var c: WorldCombat = main.combat
	var mob: Npc = null
	for e in w.mobs:
		if e.npc and e.camp.id == "quadra":
			mob = e.npc
			break
	var p := mob.global_position + Vector3(1.4, 0, 1.4)
	main.player.teleport(Vector3(p.x, w.ground_y(p.x, p.z) + 1.0, p.z), 0.8)
	for i in 20: await get_tree().process_frame
	c.set_target_npc(mob)
	c.engage_npc(mob)
	var u := c.unit_for(mob)
	u.ai_t = 0.2
	var got := false
	for i in 60:
		await get_tree().create_timer(0.15).timeout
		if not u.cast.is_empty() and float(u.cast.t) > 0.5:
			_shot("a_incoming")
			print("incoming: ", u.cast.ab.name, " prompt: ", main.hud.combat_hud._read_btn.text)
			got = true
			break
	print("saw cast ", got)
	c._player_tapped(u.name, mob)
	await get_tree().create_timer(1.5).timeout
	print("dialogue open: ", main.hud.dialogue_open(), " input ", main.player.input_enabled, " hp ", snappedf(c.me.pct(), 0.01), " tap_pending ", c.tap_pending)
	_shot("b_after")
	get_tree().quit()
