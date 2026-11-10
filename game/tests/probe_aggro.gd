extends Node
## Walk up to an aggressive mob and check it pulls you: -- <zone>
func _ready() -> void:
	var z: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "pantanal"
	Game.test_mode = true
	Game.reset()
	Game.set_identity("gringo", "male", 0.4)
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(int(Data.ZONES[z].levels[0]))
	Game.flags["pantanal_intro"] = true
	Game.zone = z
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 30: await get_tree().process_frame
	main.hud._close_dialogue(false)
	var w: World = main.world
	print("mobs=", w.mobs.size(), " grace=", w.aggro_grace, " started=", w.game_started, " input=", main.player.input_enabled, " title=", main._in_title)
	var tried := 0
	for e in w.mobs:
		var n: Npc = e.npc
		if n == null or not bool(n.mob.get("aggro", false)):
			continue
		var at := n.global_position + Vector3(4.5, 0, 0)
		main.player.teleport(Vector3(at.x, w.ground_y(at.x, at.z) + 0.3, at.z), 0.0)
		w.aggro_grace = 0.0
		for i in 120: await get_tree().process_frame
		var engaged: bool = main.combat != null and main.combat.core.engaged_enemies().size() > 0
		print(n.mob.name, " lv", n.mob.level, " disp=", Data.display_level(float(n.mob.level)), " plv=", Game.player_level(), " chasing=", n._chasing, " in_combat=", n.in_combat, " engaged=", engaged, " grace=", w.aggro_grace, " roll=", main.roll, " dlg=", main.hud.dialogue_open())
		tried += 1
		if tried >= 3:
			break
	get_tree().quit()
