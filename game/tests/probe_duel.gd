extends Node
func _ready() -> void:
	Game.test_mode = true
	Scenes.force = true
	Engine.max_physics_steps_per_frame = 60
	Game.reset()
	Game.choose_style("wrestler", "Gringo", 0)
	Game.set_level(8)
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 20: await get_tree().process_frame
	var c: WorldCombat = main.combat
	var o: Dictionary = Data.OPPONENTS["onca"].duplicate()
	c.start_bout(o, "arena", false)
	CombatCore.gm_god = true
	await get_tree().create_timer(1.2).timeout
	c.core._aura(c.me, "down", 2.5, c.target)
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/duel.png")
	CombatCore.gm_god = false
	get_tree().quit()
