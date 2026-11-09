extends Node
## Main story: passport panel + Tati in front of the academia + the Liga recruiter at the plaza.
var main: Node
func shot(n: String) -> void:
	for f in 20: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/story_%s.png" % n)

func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.style = "guard"
	Game.player_name = "Gringo"
	Game.set_level(12)
	Game.quests["s1_passport"] = {"state": "done", "count": {}}
	Game.quests["s1_liga"] = {"state": "done", "count": {}}
	Game.quests["s1_training"] = {"state": "active", "count": {}}
	Game.stamps = ["Academia Onça"]
	Game.path = "gi"
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	await get_tree().create_timer(1.0).timeout
	# Tati at the academia
	var tati: Node3D = main.world.quest_givers.get("tati")
	if tati:
		main.player.teleport(tati.global_position + Vector3(2, 0.5, 9), 0.0)
		main.player.cam_yaw = 0.0
	await shot("tati")
	var v: Node3D = main.world.fighters.get("valdir")
	if v:
		main.player.teleport(v.global_position + Vector3(-1, 0.5, 6), 0.0)
	await shot("valdir")
	main.hud.open_window("journal", 4)
	await shot("passport")
	main.hud.open_window("journal", 4)
	await get_tree().process_frame
	if main.hud.journal.visible:
		main.hud.toggle_journal()
	for zz in [["pantanal", "iracema", "brutus"], ["chapada", "iara", "rico"], ["rio", "bia", "dourado"]]:
		main._travel(zz[0])
		await get_tree().create_timer(2.0).timeout
		for who in [zz[1], zz[2]]:
			var n: Node3D = main.world.quest_givers.get(who, main.world.fighters.get(who))
			if n == null:
				print("MISSING ", who)
				continue
			print(who, " at ", n.global_position)
			main.player.teleport(n.global_position + Vector3(1.5, 0.5, 7), 0.0)
			main.player.cam_yaw = 0.0
			await shot(who)
	get_tree().quit()
