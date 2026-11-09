extends Node
## Hidden chests: where they land in every zone, open one, screenshot one up close.
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("judoka", "Gringo", 0)
	Game.set_level(8)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for z in ["caceres", "pantanal", "chapada", "rio"]:
		Game.rank = 20
		main._travel(z)
		for i in 5: await get_tree().process_frame
		var ids: Array = main.world.chests.chests.keys()
		print("CHESTS ", z, " ", ids.size(), " ", ids.map(func(id): return main.world.chests.chests[id].pos.snapped(Vector3.ONE)))
	main._travel("caceres")
	for i in 5: await get_tree().process_frame
	var cs = main.world.chests
	var id: String = cs.chests.keys()[1]
	var c: Dictionary = cs.chests[id]
	var p: Player = main.player
	p.teleport(c.pos + Vector3(2.2, 0.4, 2.2), 0.0)
	p.cam_yaw = atan2(-(c.pos.x - p.global_position.x), -(c.pos.z - p.global_position.z)) + 0.3
	p.cam_dist = 4.0
	for i in 60: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/chest_closed.png")
	var m0 := Game.money
	main._open_chest(id, {})
	print("CHEST opened money +", Game.money - m0, " bag=", Game.bag.filter(func(b): return b != null).map(func(b): return b.id))
	main._open_chest(id, {})
	for i in 50: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/chest_open.png")
	get_tree().quit()
