extends Node
## Live world QA: log in to a local server (TATAME_API), enter Cáceres with bots around, chat.
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("passer", "Gringo", 0)
	Game.set_level(14)
	var done := [false, ""]
	Cloud.authenticate("register", "live%d@example.com" % (randi() % 100000), "oss12345", func(e): done[0] = true; done[1] = e)
	for i in 600:
		await get_tree().process_frame
		if done[0]: break
	print("LIVE auth err='", done[1], "'")
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var p: Player = main.player
	p.teleport(Vector3(-1.5, 0.3, 24.5), 0.0)
	p.cam_dist = 6.5
	p.cam_pitch = -0.28
	p.cam_yaw = 0.35
	for i in 240: await get_tree().process_frame
	print("LIVE connected=", Net.connected, " remotes=", main.remotes.size())
	Net.send_chat("zone", "Oss everyone! Pressure Passer LF raid group")
	main.hud.combat_log.open_input()
	main.hud.combat_log._input.text = "/w Kaio hey, want to roll?"
	for i in 60: await get_tree().process_frame
	main.hud.combat_log._submit(main.hud.combat_log._input.text)
	for i in 120: await get_tree().process_frame
	main.hud.combat_log.open_input()
	main.hud.combat_log._input.text = "nice"
	for i in 30: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/live_world.png")
	main.hud.combat_log.close_input()
	# the remote players up close (back crest + nameplates)
	if main.remotes.size() > 0:
		var rp: Node3D = main.remotes.values()[0]
		p.teleport(rp.global_position + Vector3(2.5, 0.3, 2.5), 0.0)
		p.cam_yaw = atan2(-(rp.global_position.x - p.global_position.x), -(rp.global_position.z - p.global_position.z))
		p.cam_dist = 3.5
	for i in 60: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/live_close.png")
	get_tree().quit()
