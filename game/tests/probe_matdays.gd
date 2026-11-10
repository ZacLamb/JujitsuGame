extends Node
func _ready() -> void:
	var w := 1920
	var h := 1080
	for a in OS.get_cmdline_user_args():
		if a.begins_with("w="): w = int(a.substr(2))
		if a.begins_with("h="): h = int(a.substr(2))
	get_window().size = Vector2i(w, h)
	Game.test_mode = true
	Game.reset()
	Game.set_identity("gringo", "male", 0.4)
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(12)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 5: await get_tree().process_frame
	main._start_game()
	for i in 20: await get_tree().process_frame
	main.hud._close_dialogue(false)
	for d in range(1, 4):
		Game.mat_day_claim("2026-11-%02d" % d)
	Game.login["last"] = Game.yesterday_of(Game.today())
	main.hud.show_mat_days(Game.mat_day_claim())
	for i in 10: await get_tree().process_frame
	var r: Rect2 = main.hud.mat_days_panel.get_global_rect()
	print("panel ", r, " vp ", get_viewport().get_visible_rect().size, " inside=", get_viewport().get_visible_rect().encloses(r))
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/matdays_%dx%d.png" % [w, h])
	get_tree().quit()
