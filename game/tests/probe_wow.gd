extends Node
var main: Node
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/wow_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(17)
	Game.raise_attr("flexibility")
	Game.learn("hip_mobility")
	Game.choose_spec("sub_hunter")
	for id in ["onca_gi", "onca_gi_pants", "onca_tape", "rash_arara"]:
		Game.give_item(id, true)
	Game.equip("onca_gi")
	Game.equip("onca_gi_pants")
	Game.equip("onca_tape")
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 10: await get_tree().process_frame
	main.hud.open_window("character")
	for i in 20: await get_tree().process_frame
	_shot("char")
	main.hud._want_tab = 6
	main.hud._fill_journal()
	for i in 10: await get_tree().process_frame
	_shot("spells")
	main.hud._want_tab = 1
	main.hud._fill_journal()
	for i in 10: await get_tree().process_frame
	_shot("talents")
	main.hud._want_tab = 4
	main.hud._fill_journal()
	for i in 10: await get_tree().process_frame
	_shot("quests")
	main.hud._want_tab = 2
	main.hud._fill_journal()
	for i in 10: await get_tree().process_frame
	_shot("gear")
	get_tree().quit()
