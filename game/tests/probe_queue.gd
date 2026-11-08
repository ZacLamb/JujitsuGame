extends Node
var main: Node
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(4)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var w: World = main.world
	var pr: Array = w.mobs.filter(func(e): return e.npc != null and e.camp.id == "prainha")
	# bunch them up so the pull is social
	var c: Vector3 = pr[0].npc.global_position
	for i in pr.size():
		pr[i].npc.global_position = c + Vector3(i * 1.5, 0, 0)
	main.player.teleport(c + Vector3(0, 1, 3), 0.0)
	for i in 5: await get_tree().process_frame
	main._start_mob(pr[0].npc)
	for i in 60: await get_tree().process_frame
	print("queue: ", main._mob_queue.size(), " ", main._queue_names())
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/queue.png")
	main.roll._go_live()
	main.roll.sim.stamina = 30.0
	main.roll.sim.player_pts = 4
	main.roll.sim.clock = 0.05
	for i in 30: await get_tree().process_frame
	main.roll.finished.emit("mob", main.roll.sim.result, 0)
	for i in 20: await get_tree().process_frame
	print("next fight: ", main.roll != null and main.roll.mob.get("carry", -1.0), " stam ", main.roll.sim.stamina if main.roll else -1, " queue left ", main._mob_queue.size())
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/queue2.png")
	get_tree().quit()
