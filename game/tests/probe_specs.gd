extends Node
var main: Node
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(12)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	print("choose: ", Game.choose_spec("sub_hunter"), " knows chain_sub=", Game.knows("chain_sub"), " role=", Team.player_role())
	main.hud._want_tab = 3
	main.hud.toggle_journal()
	for i in 10: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/specs.png")
	get_tree().quit()
