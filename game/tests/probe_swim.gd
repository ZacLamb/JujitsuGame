extends Node
## Swimming QA: drop into deep water, float, swim to the bank and climb out (Cáceres river, Pantanal).
func _ready() -> void:
	Game.test_mode = true
	Engine.max_physics_steps_per_frame = 60
	Game.reset()
	Game.choose_style("athlete", "Gringo", 0)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var p: Player = main.player
	var w: World = main.world
	var rx: float = w.river_x(10.0)
	p.teleport(Vector3(rx, w.water_level() - 0.5, 10.0), 0.0)
	var ys: Array = []
	for i in 120:
		await get_tree().physics_frame
		if i % 20 == 0:
			ys.append(snappedf(p.global_position.y, 0.01))
	print("SWIM float ys=", ys, " swimming=", p.swimming, " wl=", w.water_level())
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/swim_a.png")
	# swim east to the town bank
	p.cam_yaw = -PI / 2
	Input.action_press("move_forward")
	var out := -1
	for i in 900:
		await get_tree().physics_frame
		if not p.swimming and p.is_on_floor() and out < 0:
			out = i
		if out > 0 and i > out + 60:
			break
	Input.action_release("move_forward")
	print("SWIM out at frame ", out, " pos=", p.global_position.snapped(Vector3.ONE * 0.1), " swimming=", p.swimming, " on_floor=", p.is_on_floor())
	get_tree().quit()
