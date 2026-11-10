extends Node
func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	Game.test_mode = true
	Game.reset()
	Game.set_identity("gringo", "male", 0.4)
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(14)
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 5: await get_tree().process_frame
	main._start_game()
	for i in 20: await get_tree().process_frame
	main.hud._close_dialogue(false)
	main.hud.minimap.toggle_big()
	main.hud.minimap.world_view = true
	for i in 10: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/worldmap.png")
	main.hud.minimap.world_view = false
	for i in 4: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/zonemap.png")
	get_tree().quit()
