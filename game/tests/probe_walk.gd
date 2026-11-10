extends Node
## Walk off Cáceres along the east road -> Pantanal (arrive west), then back.
func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	Game.test_mode = true
	Game.reset()
	Game.set_identity("gringo", "male", 0.4)
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(12)
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 5: await get_tree().process_frame
	main._start_game()
	for i in 20: await get_tree().process_frame
	main.hud._close_dialogue(false)
	var w: World = main.world
	var zc: float = World.ZONE_ROADS.caceres.e
	main.player.teleport(Vector3(70, w.ground_y(70, zc) + 0.5, zc), -PI / 2)
	main.player.cam_yaw = -PI / 2
	for i in 30: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/walk_road.png")
	main.player.teleport(Vector3(93, w.ground_y(93, zc) + 0.5, zc), -PI / 2)
	for i in 30: await get_tree().process_frame
	main.hud._close_dialogue(false)
	for i in 30: await get_tree().process_frame
	print("after walk: zone=", main.world.zone, " pos=", main.player.global_position)
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/walk_arrive.png")
	var p: Vector3 = main.player.global_position
	main.player.teleport(Vector3(-93, main.world.ground_y(-93, p.z) + 0.5, p.z), PI / 2)
	for i in 60: await get_tree().process_frame
	print("back: zone=", main.world.zone, " pos=", main.player.global_position)
	get_tree().quit()
