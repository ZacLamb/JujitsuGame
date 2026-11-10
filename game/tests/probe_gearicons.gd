extends Node
## Gear icons in the character sheet, wardrobe and bags.
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.set_identity("gringo", "male", 0.4)
	Game.choose_style("guard", "Zac", 0)
	Game.set_level(30)
	for id in ["onca_gi", "onca_gi_pants", "rash_blue", "jacare_knees", "onca_headband", "lobo_spats"]:
		Game.give_item(id, true)
	for id in ["onca_gi", "onca_gi_pants", "onca_headband"]:
		Game.equip(id)
	for id in ["gear:polvo_gi", "gear:selecao_rash", "gear:touro_knees", "gear:leao_tape"]:
		Game.add_item(id)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 20: await get_tree().process_frame
	main.hud.open_window("character")
	for i in 15: await get_tree().process_frame
	_shot("icons_char")
	main.hud.open_window("character", main.hud.TAB_GEAR)
	for i in 15: await get_tree().process_frame
	_shot("icons_wardrobe")
	main.hud.toggle_journal()
	main.hud.toggle_bag()
	for i in 15: await get_tree().process_frame
	_shot("icons_bag")
	get_tree().quit()

func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/%s.png" % n)
