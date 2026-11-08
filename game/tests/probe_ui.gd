extends Node
## Renders the Character and Talents journal tabs for visual QA.
var main: Node
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(17)
	Game.raise_attr("flexibility")
	Game.raise_attr("flexibility")
	Game.raise_attr("iq")
	Game.learn("hip_mobility")
	Game.learn("hip_mobility")
	Game.learn("retention")
	Game.learn("t_omoplata")
	Game.learn("shot_speed")
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 10: await get_tree().process_frame
	main.hud.open_character()
	for i in 30: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/ui%s_char.png" % str(get_viewport().get_visible_rect().size.y))
	main.hud._sel_talent = "slippery"
	main.hud._want_tab = 1
	main.hud._fill_journal()
	for i in 30: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/ui%s_tal.png" % str(get_viewport().get_visible_rect().size.y))
	get_tree().quit()
