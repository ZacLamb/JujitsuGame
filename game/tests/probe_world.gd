extends Node
## Third-person shot of the player among NPCs (visual QA for character models).
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
	var p: Player = main.player
	var npc: Node3D = null
	for n in main.world.find_children("*", "Npc", true, false):
		npc = n
		break
	if npc:
		var to: Vector3 = npc.global_position
		p.teleport(to + Vector3(1.6, 0.3, 2.6), 0.0)
		p.cam_yaw = atan2(-(to.x - p.global_position.x), -(to.z - p.global_position.z)) + 0.35
		p.cam_dist = 4.2
	for i in 90: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/world_chars.png")
	get_tree().quit()
