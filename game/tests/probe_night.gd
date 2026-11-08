extends Node
var main: Node
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	DayNight.hour = 23.0
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	DayNight.hour = 23.0
	for i in 60: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/night.png")
	get_tree().quit()
