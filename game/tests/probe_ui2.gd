extends Node
var main: Node
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/ui2_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(6)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	for i in 10: await get_tree().process_frame
	_shot("dialogue")
	main.hud._close_dialogue(false)
	main.hud.toggle_settings()
	for i in 6: await get_tree().process_frame
	_shot("settings")
	main.hud.toggle_settings()
	main.hud.minimap.toggle_big()
	for i in 6: await get_tree().process_frame
	_shot("map")
	main.hud.minimap.toggle_big()
	main._start_roll("tiago")
	for i in 10: await get_tree().process_frame
	main.roll._go_live()
	main.roll.sim.ai_t = 99.0
	main.roll._use("grip")
	for i in 12: await get_tree().process_frame
	_shot("fight")
	get_tree().quit()
