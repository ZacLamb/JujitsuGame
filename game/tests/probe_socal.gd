extends Node
## San Diego: fly in, then a few views (arrival, boardwalk/pier, Garage, cliffs).
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("passer", "Gringo", 0)
	Game.set_level(44)
	Game.money = 1000
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	main._travel("socal")
	for i in 60: await get_tree().process_frame
	if main.hud.has_method("_close_dialogue"):
		main.hud._close_dialogue(false)
	print("zone=", main.world.zone, " money=", Game.money, " flight=", Game.unlocked.has("flight"), " mobs=", main.world.mobs.size(), " obj=", Game.current_objective())
	var p: Player = main.player
	var views := [["arrive", Vector3(-82, 0, 6), PI / 2, 9.0], ["boardwalk", Vector3(10, 0, 22), 0.6, 14.0], ["garage", Vector3(-18, 0, -20), 0.0, 12.0], ["cliffs", Vector3(-60, 0, 30), -0.8, 12.0], ["tacos", Vector3(30, 0, 4), 0.0, 11.0]]
	for v in views:
		p.teleport(Vector3(v[1].x, main.world.ground_y(v[1].x, v[1].z) + 0.3, v[1].z), 0.0)
		p.cam_yaw = v[2]
		p.cam_dist = v[3]
		for i in 40: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/home/claude/shots/socal_%s.png" % v[0])
	get_tree().quit()
