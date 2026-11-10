extends Node
## Visual QA for a zone: xvfb-run -a godot --rendering-driver opengl3 tests/probe_zone.tscn -- <zone> [origin]
const VIEWS := {
	"texas": [["arrive", Vector3(0, 0, 26), 0.0, 13.0], ["main", Vector3(-30, 0, -7), -PI / 2, 9.0], ["square", Vector3(4, 0, 12), 0.3, 9.0], ["creek", Vector3(-50, 0, 24), 0.58, 12.0], ["chapel", Vector3(-30, 0, -54), 0.2, 14.0], ["ranch", Vector3(16, 0, 56), PI, 16.0]],
	"everglades": [["arrive", Vector3(-82, 0, -4), PI / 2, 10.0], ["trail", Vector3(0, 0, -4), PI / 2, 14.0], ["pit", Vector3(60, 0, 32), PI, 13.0], ["dock", Vector3(26, 0, -40), -PI / 2, 12.0], ["dock2", Vector3(38, 0, -26), 0.0, 5.0], ["fishcamp", Vector3(-40, 0, 10), PI, 12.0]],
	"sedona": [["ghost", Vector3(-64, 0, -40), 0.0, 14.0], ["arrive", Vector3(-80, 0, 40), PI / 2, 10.0], ["bell", Vector3(10, 0, 8), 0.0, 16.0], ["gym", Vector3(46, 0, 12), 0.0, 12.0], ["uptown", Vector3(42, 0, 34), PI, 13.0], ["cathedral", Vector3(-34, 0, -28), 0.0, 16.0], ["mesa", Vector3(30, 0, -48), 0.0, 14.0]],
}
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var z: String = args[0] if args.size() > 0 else "texas"
	var org: String = args[1] if args.size() > 1 else "texan"
	Game.test_mode = true
	Game.reset()
	Game.set_identity(org, "male", 0.4)
	Game.choose_style("passer", "Tex", 0)
	Game.set_level(int(Data.ZONES[z].levels[0]))
	Game.zone = z
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 30: await get_tree().process_frame
	main.hud._close_dialogue(false)
	print("zone=", main.world.zone, " faction=", Game.faction(), " mobs=", main.world.mobs.size(), " obj=", Game.current_objective(), " story=", Game.story_next()[1])
	var p: Player = main.player
	for v in VIEWS[z]:
		p.teleport(Vector3(v[1].x, main.world.ground_y(v[1].x, v[1].z) + 0.3, v[1].z), 0.0)
		p.cam_yaw = v[2]
		p.cam_dist = v[3]
		for i in 40: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/home/claude/shots/%s_%s.png" % [z, v[0]])
	get_tree().quit()
