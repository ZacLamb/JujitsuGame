extends Node
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.set_identity("carioca", "male", 0.4)
	Game.choose_style("guard", "Zac", 0)
	get_window().size = Vector2i(640, 480)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	main.player.cam_dist = 4.0
	main.player.cam_yaw = PI
	for i in 20: await get_tree().process_frame
	for id in Emotes.LIST:
		var fr := Emotes.frames(id, main.player.rig.rotation.y)
		main.player.rig.action(fr)
		var tot := 0.0
		for f in fr: tot += float(f[2])
		await get_tree().create_timer(minf(tot * 0.45, 2.0)).timeout
		get_viewport().get_texture().get_image().save_png("/home/claude/shots/emote_%s.png" % id)
		await get_tree().create_timer(tot * 0.55 + 0.3).timeout
	get_tree().quit()
