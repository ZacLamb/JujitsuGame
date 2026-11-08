extends Node
## Renders the 5v5 team board (lineup + mid-match) and a live team bout.
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/team_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(8)
	for id in ["rafa", "cida", "tiago", "peixe", "onca"]:
		Game.wins[id] = 1
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 5: await get_tree().process_frame
	main._open_team("caceres")
	for i in 10: await get_tree().process_frame
	_shot("lineup")
	main.team_board.start_pressed.emit()
	main._team_sim()
	main._team_sim()
	for i in 10: await get_tree().process_frame
	_shot("between")
	main._team_play()
	for i in 40: await get_tree().process_frame
	main.roll._go_live()
	for i in 60: await get_tree().process_frame
	_shot("bout")
	get_tree().quit()
