extends Node
## Meshy statues / mascot / gi stand in Cáceres.
var main: Node
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/props_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var w: World = main.world
	w.aggro_grace = 999.0
	for spot in [["a_academia", Vector3(0, 0, -40)], ["b_praca", Vector3(0, 0, 26)], ["c_galpao", Vector3(52, 0, -52)], ["d_prainha", Vector3(-32, 0, 78)]]:
		var p: Vector3 = spot[1]
		main.player.teleport(Vector3(p.x, w.ground_y(p.x, p.z) + 1.0, p.z), 0.0)
		for i in 40: await get_tree().process_frame
		_shot(spot[0])
	get_tree().quit()
