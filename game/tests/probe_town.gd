extends Node
## Environment QA: fixed camera shots around Cáceres (street, plaza, aerial) for before/after.
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("passer", "Gringo", 0)
	Game.set_level(12)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	main.hud.visible = false
	var tag: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "now"
	var shots := [["street", Vector3(30, 0, -4), PI * 0.5 + 0.25, -0.12, 7.0], ["plaza", Vector3(-4, 0, 14), -0.25, -0.12, 11.0],
		["houses", Vector3(-30, 0, -4), -PI * 0.5 + 0.3, -0.1, 6.0], ["aerial", Vector3(0, 0, 10), 0.3, -0.75, 40.0], ["academia", Vector3(9, 0, -36), 0.35, -0.1, 6.0]]
	var p: Player = main.player
	for s in shots:
		p.teleport(s[1] + Vector3(0, main.world.ground_y(s[1].x, s[1].z) + 0.3, 0), s[2])
		p.cam_yaw = s[2]
		p.cam_pitch = s[3]
		p.cam_dist = s[4]
		for i in 50: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/home/claude/shots/town_%s_%s.png" % [s[0], tag])
	get_tree().quit()
