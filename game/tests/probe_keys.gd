extends Node
func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 5: await get_tree().process_frame
	main._start_game()
	for i in 20: await get_tree().process_frame
	main.hud._close_dialogue(false)
	Keys.reset()
	print("before W=", Keys.label("move_forward"), " dir_up=", InputMap.action_get_events("dir_up").map(func(e): return OS.get_keycode_string(e.physical_keycode) if e is InputEventKey else "pad"))
	var bumped := Keys.bind("move_forward", KEY_Q)
	print("bind Q->forward bumped=", bumped, " forward=", Keys.label("move_forward"), " base=", Keys.label("ab_base"), " dir_up=", InputMap.action_get_events("dir_up").map(func(e): return OS.get_keycode_string(e.physical_keycode) if e is InputEventKey else "pad"))
	print("saved=", Sfx.pref("keys", {}))
	main.hud.toggle_settings()
	for i in 6: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/keys_settings.png")
	main.hud.toggle_settings()
	Keys.reset()
	print("after reset forward=", Keys.label("move_forward"), " base=", Keys.label("ab_base"), " saved=", Sfx.pref("keys", {}))
	get_tree().quit()
