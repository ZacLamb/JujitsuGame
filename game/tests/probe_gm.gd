extends Node
## GM QA: a normal account can't open the GM window or use GM ops; a GM account sees players + tools.
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("judoka", "GameMaster", 0)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	# 1) normal account
	var done := [false]
	Cloud.authenticate("register", "normal%d@example.com" % (randi() % 100000), "oss12345", func(e): done[0] = true)
	for i in 300:
		await get_tree().process_frame
		if done[0]: break
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 120: await get_tree().process_frame
	main.gm_panel.toggle()
	Net.send_gm("kick", {"target": 1})
	for i in 30: await get_tree().process_frame
	print("GM normal: connected=", Net.connected, " gm=", Net.gm, " panel_visible=", main.gm_panel.visible)
	# 2) GM account
	Net.stop()
	Cloud.logout()
	done = [false]
	var em := "gmtest@example.com"
	Cloud.authenticate("register", em, "oss12345", func(e):
		if e != "":
			Cloud.authenticate("login", em, "oss12345", func(_e): done[0] = true)
		else:
			done[0] = true)
	for i in 300:
		await get_tree().process_frame
		if done[0]: break
	Net.enter(main.world.zone)
	for i in 120: await get_tree().process_frame
	print("GM gm: connected=", Net.connected, " gm=", Net.gm)
	main.gm_panel.toggle()
	for i in 60: await get_tree().process_frame
	print("GM panel_visible=", main.gm_panel.visible, " rows=", main.gm_panel._players.get_child_count())
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/gm_live.png")
	main.gm_panel._tabs.current_tab = 2
	for i in 20: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/gm_tools.png")
	get_tree().quit()
