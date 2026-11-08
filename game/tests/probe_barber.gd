extends Node
var main: Node
func _shot(n: String) -> void:
	for i in 30: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/barber_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Engine.max_physics_steps_per_frame = 60
	Game.reset()
	Game.set_identity("gringo", "male", 0.35)
	Game.choose_style("guard", "Gringo", 0)
	Game.money = 150
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	main.open_barber()
	var sel: StyleSelect = null
	for c in main.get_children():
		if c is CanvasLayer and c.get_child_count() > 0 and c.get_child(0) is StyleSelect:
			sel = c.get_child(0)
	sel._pick_origin("carioca")
	sel._pick_body("female")
	sel._pick_skin(0.75)
	sel._pick_gi(1)
	await _shot("a_open")
	sel._begin()
	await _shot("b_after")
	print("BARBER origin=", Game.origin, " body=", Game.body, " gi=", Game.gi_index, " money=", Game.money, " style=", Game.style)
	get_tree().quit()
