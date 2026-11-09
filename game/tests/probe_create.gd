extends Node
## Character creation screen + first steps (tutorial cards, intro dialogue vs action bar).
var main: Node
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/create_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Engine.max_physics_steps_per_frame = 60
	Game.reset()
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	for i in 30: await get_tree().process_frame
	var sel: StyleSelect = null
	for c in main.get_children():
		if c is CanvasLayer and c.get_child_count() > 0 and c.get_child(0) is StyleSelect:
			sel = c.get_child(0)
	sel._pick_origin("carioca")
	sel._pick_style("wrestler")
	sel._pick_body("female")
	sel._pick_head(6)
	for i in 30: await get_tree().process_frame
	_shot("a_screen")
	sel._begin()
	for i in 40: await get_tree().process_frame
	_shot("b_intro")
	main.hud._close_dialogue(false)
	for i in 10: await get_tree().process_frame
	Engine.max_physics_steps_per_frame = 8
	Game.set_level(4)
	Game.progress_changed.emit()
	for i in 3: await get_tree().process_frame
	_shot("c_learned")
	main.hud.open_window("talents", Hud.TAB_SPELLBOOK)
	for i in 20: await get_tree().process_frame
	_shot("d_spellbook")
	main.hud.toggle_journal()
	# hover tooltip on bar slot 2
	var cb: CombatHud = main.hud.combat_hud
	cb._show_tip(1, cb._slots[1])
	for i in 6: await get_tree().process_frame
	_shot("e_tip")
	get_tree().quit()
