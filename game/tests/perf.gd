extends Node
## Render stats per zone (draw calls, objects, primitives) from typical viewpoints.
## Run under xvfb with --rendering-driver opengl3.
var main: Node
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(41)
	Game.flags["gfx"] = 0 if OS.get_cmdline_user_args().has("--low") else (2 if OS.get_cmdline_user_args().has("--ultra") else 1)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var views := {"caceres": [Vector3(0, 0, 24), Vector3(0, 0, -50)], "pantanal": [Vector3(-82, 0, -4), Vector3(50, 0, 50)],
		"chapada": [Vector3(-80, 0, 40), Vector3(40, 0, 50)], "rio": [Vector3(-84, 0, 6), Vector3(0, 0, 40)]}
	for z in views:
		if z != "caceres":
			main._travel(z)
			main.hud._close_dialogue(false)
		for v in views[z]:
			main.player.teleport(Vector3(v.x, main.world.ground_y(v.x, v.z) + 0.5, v.z), 0.6)
			for i in 20: await get_tree().process_frame
			if z == "caceres" and v == views[z][0]:
				get_viewport().get_texture().get_image().save_png("/home/claude/shots/gfx_%d.png" % Game.graphics_level())
			print("%-9s %-18s draws %4d  objects %4d  prims %7d  nodes %5d" % [z, str(Vector2(v.x, v.z)),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	var cats := {}
	for n in main.world.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var k := g.get_class()
		var p := g.get_parent()
		if p is BodyRig or (p and p.get_parent() is BodyRig) or g.find_parent("*Rig*") or (p and p.get_class() == "Skeleton3D"):
			k += " (character)"
		elif g.get_parent() != main.world:
			k += " (model/child)"
		cats[k] = int(cats.get(k, 0)) + 1
	print(cats)
	get_tree().quit()
