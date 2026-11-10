extends Node
func _ready() -> void:
	var role: String = OS.get_cmdline_user_args()[0]
	Game.test_mode = true
	Game.reset()
	Game.set_identity("carioca", "male", 0.4)
	Game.choose_style("guard", role.capitalize(), 0)
	Game.zone = "caceres"
	Cloud.token = "dev-" + role
	get_window().size = Vector2i(640, 360)
	Game.set_graphics_level(0)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	main.player.teleport(Vector3(10 if role == "host" else 12, main.world.ground_y(10, 30) + 0.3, 30), 0.0)
	Net.emote.connect(func(id, e): print(role, " got emote ", e, " from ", id))
	var t := 0.0
	while main.remotes.is_empty() and t < 40.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	await get_tree().create_timer(3.0).timeout
	if role == "host":
		main.do_emote("oss")
		await get_tree().create_timer(2.0).timeout
		main.do_emote("dance")
	await get_tree().create_timer(6.0).timeout
	get_tree().quit()
