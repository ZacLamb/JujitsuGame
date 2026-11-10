extends Node
## Screens in the language passed with -- lang=pt_BR (title, opening dialogue, journal, settings, a fight).
func _ready() -> void:
	var tag: String = Lang.current
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	_shot("lang_%s_title" % tag)
	Game.test_mode = true
	Game.reset()
	Game.set_identity("gringo", "male", 0.4)
	Game.choose_style("guard", "Zac", 0)
	main._start_game()
	for i in 40: await get_tree().process_frame
	_shot("lang_%s_intro" % tag)
	main.hud._close_dialogue(false)
	for i in 20: await get_tree().process_frame
	_shot("lang_%s_world" % tag)
	main.hud.toggle_journal()
	for i in 10: await get_tree().process_frame
	_shot("lang_%s_journal" % tag)
	main.hud.toggle_journal()
	main.hud.toggle_settings()
	for i in 10: await get_tree().process_frame
	_shot("lang_%s_settings" % tag)
	main.hud.toggle_settings()
	var w: World = main.world
	var c: WorldCombat = main.combat
	var mob: Npc = null
	for e in w.mobs:
		if e.npc and e.camp.id == "quadra":
			mob = e.npc
			break
	var p := mob.global_position + Vector3(2.5, 0, 2.5)
	main.player.teleport(Vector3(p.x, w.ground_y(p.x, p.z) + 1.0, p.z), 0.8)
	for i in 10: await get_tree().process_frame
	c.set_target_npc(mob)
	c.engage_npc(mob)
	for i in 8:
		c.press(str(Game.bar_layout[0]))
		await get_tree().create_timer(0.4).timeout
	_shot("lang_%s_fight" % tag)
	get_tree().quit()

func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/%s.png" % n)
