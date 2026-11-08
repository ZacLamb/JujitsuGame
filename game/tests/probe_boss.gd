extends Node
## Renders a boss roll mid-phase with a special cast up.
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("passer", "Gringo", 0)
	Game.set_level(14)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	main._start_roll("jacare")
	var roll: RollScene = main.roll
	for i in 10: await get_tree().process_frame
	roll._go_live()
	Engine.time_scale = 0.2
	roll.sim.opp_stamina = 30.0
	for i in 6: await get_tree().process_frame
	roll.sim.special_t = 0.0
	roll.sim.ai_t = 99.0
	roll.sim.opp_cast = {}
	for i in 14: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/boss_phase.png")
	get_tree().quit()
