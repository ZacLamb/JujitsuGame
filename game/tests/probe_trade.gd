extends Node
## Trading between two real clients (local server, WORLD_DEV=1 PORT=3077).
var role := "host"
var main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	Game.test_mode = true
	Game.reset()
	Game.set_identity("carioca" if role == "host" else "gringo", "male", 0.4)
	Game.choose_style("guard" if role == "host" else "wrestler", "Host" if role == "host" else "Guest", 0)
	Game.set_level(12)
	Game.zone = "caceres"
	Cloud.token = "dev-" + role
	get_window().size = Vector2i(1280, 720)
	Game.set_graphics_level(0)
	Game.money = 200
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	if role == "host":
		var rg := Game.make_rolled(Gear.roll(12, RandomNumberGenerator.new(), true, false))
		Game.add_item("gear:" + rg)
		Game.add_item("acai", 3)
	else:
		Game.add_item("pao_queijo", 2)
	var spot := Vector3(10, 0, 30) if role == "host" else Vector3(12, 0, 31)
	main.player.teleport(Vector3(spot.x, main.world.ground_y(spot.x, spot.z) + 0.3, spot.z), 0.0)
	var t := 0.0
	while main.remotes.is_empty() and t < 40.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	print(role, " bag before: ", _bag(), " R$", Game.money)
	if role == "host":
		await get_tree().create_timer(2.0).timeout
		var rid: int = main.remotes.keys()[0]
		main._duel_menu(main.remotes[rid])
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png("/home/claude/shots/player_menu.png")
		main.hud.close_player_menu()
		print("host input after menu=", main.player.input_enabled)
		main.trade.request(rid, "Guest")
	else:
		while main._party_ask != "trade" and t < 60.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		main.hud._close_dialogue(true)
	while not main.trade.is_open() and t < 70.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	print(role, " trade open=", main.trade.is_open())
	await get_tree().create_timer(1.0).timeout
	for k in Game.bag.size():
		if Game.bag[k] != null:
			main.trade.toggle_slot(k)
	if role == "host":
		main.trade.set_money(50)
	await get_tree().create_timer(3.0).timeout
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/trade_%s.png" % role)
	print(role, " sees theirs=", main.trade.theirs.map(func(e): return e.id), " their R$", main.trade.their_money)
	print(role, " lock: ", main.trade.set_lock(true))
	var w := 0.0
	while main.trade.busy() and w < 20.0:
		await get_tree().create_timer(0.25).timeout
		w += 0.25
	await get_tree().create_timer(1.0).timeout
	print(role, " bag after: ", _bag(), " R$", Game.money)
	get_tree().quit()

func _bag() -> Array:
	var out := []
	for s in Game.bag:
		if s != null:
			out.append("%s x%d (%s)" % [s.id, int(s.n), str(Loot.item(str(s.id)).get("name", "?"))])
	return out
