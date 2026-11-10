extends Node
## Every window at a desktop browser size (-- w=1728 h=1000) for layout checks.
var main: Node
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/sz_%s.png" % n)
func _ready() -> void:
	var w := 1728
	var h := 1000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("w="): w = int(a.substr(2))
		if a.begins_with("h="): h = int(a.substr(2))
	get_window().size = Vector2i(w, h)
	Game.test_mode = true
	Game.reset()
	Game.set_identity("gringo", "male", 0.4)
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(12)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 5: await get_tree().process_frame
	main._start_game()
	for i in 20: await get_tree().process_frame
	main.hud._close_dialogue(false)
	for i in 10: await get_tree().process_frame
	_shot("world")
	main.hud.toggle_settings()
	for i in 6: await get_tree().process_frame
	_shot("settings")
	main.hud.toggle_settings()
	for win in ["character", "talents", "journal"]:
		main.hud.open_window(win)
		for i in 8: await get_tree().process_frame
		_shot(win)
		main.hud.toggle_journal()
		for i in 3: await get_tree().process_frame
	main.hud.open_window("talents", main.hud.TAB_SPELLBOOK)
	for i in 8: await get_tree().process_frame
	_shot("moves")
	main.hud.toggle_journal()
	main.hud.toggle_bag()
	for i in 8: await get_tree().process_frame
	_shot("bags")
	main.hud.toggle_bag()
	main.hud.toggle_finder(main)
	for i in 8: await get_tree().process_frame
	_shot("finder")
	main.hud.toggle_finder(main)
	main.hud.toggle_arena()
	for i in 8: await get_tree().process_frame
	_shot("arena")
	get_tree().quit()
