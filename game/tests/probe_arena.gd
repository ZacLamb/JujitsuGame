extends Node
## Ranked arena against a local server with a database (ARENA_TOKEN = a session token).
var main: Node
var done := false
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.set_identity("carioca", "male", 0.4)
	Game.choose_style("guard", "Zac", 0)
	Game.set_level(14)
	Game.zone = "caceres"
	Cloud.token = OS.get_environment("ARENA_TOKEN")
	get_window().size = Vector2i(1280, 720)
	Game.set_graphics_level(0)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	await get_tree().create_timer(2.0).timeout
	main.hud.toggle_arena()
	await get_tree().create_timer(3.0).timeout
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/arena_panel.png")
	main.hud.toggle_arena()
	main.combat.bout_over.connect(func(tag, won, _i): print("bout ", tag, " won=", won); done = true)
	main.start_arena()
	var t := 0.0
	while not done and t < 120.0:
		await get_tree().create_timer(0.35).timeout
		t += 0.35
		for k in Game.bar_layout + ["takedown", "pass", "sub", "base", "frame", "defend", "breathe"]:
			if str(k) != "":
				main.combat.press(str(k))
		if int(t) == 6:
			get_viewport().get_texture().get_image().save_png("/home/claude/shots/arena_fight.png")
	await get_tree().create_timer(5.0).timeout
	print("board me=", Cloud.arena.get("me"))
	main.hud.toggle_arena()
	await get_tree().create_timer(3.0).timeout
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/arena_after.png")
	get_tree().quit()
