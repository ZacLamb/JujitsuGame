extends Node
var main: Node
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/env_%s.png" % n)
func _view(pos: Vector3, look: Vector3) -> void:
	main.player.teleport(Vector3(pos.x, main.world.ground_y(pos.x, pos.z) + 0.5, pos.z), 0.0)
	var cam: Camera3D = main.player.cam
	main.player.set_physics_process(false)
	main.player.yaw_node.global_position = main.player.global_position + Vector3(0, 1.5, 0)
	var d := (look - pos)
	main.player.cam_yaw = atan2(-d.x, -d.z)
	main.player.yaw_node.rotation.y = main.player.cam_yaw
	main.player.pitch_node.rotation.x = -0.18
	for i in 30: await get_tree().process_frame
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(35)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	main.hud.visible = false
	DayNight.hour = float(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 12.0
	main.world.day_night.frozen = true
	await _view(Vector3(-52, 0, 6), Vector3(-80, 0, -10))
	_shot("river")
	main._travel("pantanal")
	main.hud._close_dialogue(false)
	main.hud.visible = false
	main.world.day_night.frozen = true
	await _view(Vector3(-4, 0, 10), Vector3(14, 0, 24))
	_shot("pantanal")
	main._travel("rio")
	main.hud._close_dialogue(false)
	main.hud.visible = false
	main.world.day_night.frozen = true
	await _view(Vector3(10, 0, 46), Vector3(30, 0, 80))
	_shot("ocean")
	get_tree().quit()
