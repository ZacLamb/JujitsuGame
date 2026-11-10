extends Node
## Critters react: walk/run the player up to one of each kind and print the state counts.
func _ready() -> void:
	var z: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "pantanal"
	Game.test_mode = true
	Game.reset()
	Game.set_identity("gringo", "male", 0.4)
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(int(Data.ZONES[z].levels[0]))
	Game.flags["pantanal_intro"] = true
	Game.zone = z
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 20: await get_tree().process_frame
	main.hud._close_dialogue(false)
	var cr: Critters = main.world.critters
	print("critters ", cr._list.size(), " ", cr.states())
	var p: Player = main.player
	var seen := {}
	for c in cr._list:
		if seen.has(c.kind):
			continue
		seen[c.kind] = true
		var at: Vector3 = c.home + Vector3(2.5, 0, 2.5)
		p.teleport(Vector3(at.x, main.world.ground_y(at.x, at.z) + 0.3, at.z), 0.0)
		p.velocity = Vector3(9, 0, 0)
		for i in 30: await get_tree().process_frame
		print(c.kind, " state=", c.state, " moved=", snappedf((c.pos - c.home).length(), 0.01))
		p.cam_yaw = atan2(c.home.x - at.x, c.home.z - at.z) + PI
		p.cam_dist = 7.0
		get_viewport().get_texture().get_image().save_png("/home/claude/shots/crit_%s.png" % c.kind)
	print("after ", cr.states())
	get_tree().quit()
