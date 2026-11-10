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
	Game.money = 400
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 5: await get_tree().process_frame
	main._start_game()
	for i in 20: await get_tree().process_frame
	main.hud._close_dialogue(false)
	Cloud.token = "probe"
	var top := [{"id": 1, "name": "Gracie Pantanal", "tag": "GPT", "faction": "brasil", "members": 14, "points": 820},
		{"id": 2, "name": "Lone Star Grapplers", "tag": "LSG", "faction": "usa", "members": 9, "points": 610},
		{"id": 3, "name": "Cáceres Top Team", "tag": "CTT", "faction": "brasil", "members": 6, "points": 240}]
	Cloud.academy_view = {"mine": null, "top": top, "cost": 250}
	main.hud.toggle_academy()
	for i in 5: await get_tree().process_frame
	main.hud.academy_panel._draw()
	main.hud.academy_panel._status.text = ""
	for i in 5: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/acad_none_%dx%d.png" % [w, h])
	Cloud.academy_view = {"mine": {"id": 1, "name": "Gracie Pantanal", "tag": "GPT", "motto": "Position before submission.", "faction": "brasil", "my_rank": "leader", "me": 1, "points": 820,
		"members": [{"id": 1, "name": "Gringo", "style": "guard", "level": 12, "rank": "leader", "online": true},
			{"id": 2, "name": "Bia", "style": "judoka", "level": 15, "rank": "professor", "online": true},
			{"id": 3, "name": "Tico", "style": "wrestler", "level": 7, "rank": "student", "online": false},
			{"id": 4, "name": "Duda", "style": "passer", "level": 10, "rank": "student", "online": false}]}, "top": top, "cost": 250}
	main.hud.academy_panel._draw()
	for i in 5: await get_tree().process_frame
	var r: Rect2 = main.hud.academy_panel.get_global_rect()
	print("panel ", r, " vp ", get_viewport().get_visible_rect().size, " inside=", get_viewport().get_visible_rect().encloses(r))
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/acad_mine_%dx%d.png" % [w, h])
	get_tree().quit()
