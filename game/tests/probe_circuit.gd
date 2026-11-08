extends Node
## Renders the Circuito board (draft + mid-run).
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/circuit_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("athlete", "Gringo", 0)
	Game.set_level(10)
	Game.wins["onca"] = 1
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	main._open_circuit()
	for i in 10: await get_tree().process_frame
	_shot("draft")
	main.circuit_board.card_picked.emit(main.circuit_run.offers[0])
	main._circuit_after({"won": true, "me_stam": 0.55})
	main.circuit_board.card_picked.emit(main.circuit_run.offers[1])
	main._circuit_after({"won": true, "me_stam": 0.4})
	for i in 10: await get_tree().process_frame
	_shot("mid")
	get_tree().quit()
