extends Node
## Screenshot of the stacked second bar with techniques on it, and the Moves book open.
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("judoka", "Gringo", 0)
	Game.set_level(12)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 10: await get_tree().process_frame
	var tds: Array = Abilities.known_moves()
	var n := 0
	for m in tds:
		if str(Data.MOVES[m].type) in ["takedown", "pass", "sub"] and n < 6:
			Game.bar_set(10 + n, "mv:" + str(m))
			n += 1
	for i in 12: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/bar2_a.png")
	main.hud.open_window("talents", main.hud.TAB_SPELLBOOK)
	for i in 14: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/bar2_b.png")
	get_tree().quit()
