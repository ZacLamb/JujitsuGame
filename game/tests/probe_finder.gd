extends Node
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.set_identity("carioca", "male", 0.4)
	Game.choose_style("guard", "Biel", 0)
	Game.set_level(26)
	Game.unlocked["dng_basement"] = true
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 20: await get_tree().process_frame
	main.hud.toggle_finder(main)
	for i in 10: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/finder.png")
	main.start_dungeon("night")
	main.player.cam_dist = 11.0
	for i in 200: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/finder_run.png")
	get_tree().quit()
