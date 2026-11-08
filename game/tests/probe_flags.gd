extends Node
## Renders a territory flag in the world and the world map with territory markers.
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("passer", "Gringo", 0)
	Game.set_level(6)
	Game.capture("t_market")
	Game.capture("t_river")
	Game.territories.t_river.attack_at = Game.now() - 60
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	main.world.refresh_flags()
	var p: Player = main.player
	var fp: Vector3 = Data.TERRITORIES.t_plaza.pos
	p.teleport(fp + Vector3(-3.5, 0.5, 6.0), 0.0)
	p.cam_yaw = -0.45
	p.cam_pitch = -0.12
	p.cam_dist = 5.0
	for i in 90: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/flag_world.png")
	main.hud.minimap.toggle_big()
	for i in 10: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/flag_map.png")
	get_tree().quit()
