extends Node
## Faction war panel + a rival shadow roll.
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.set_identity("carioca", "male", 0.5)
	Game.choose_style("guard", "Biel", 0)
	Game.set_level(14)
	Game.war = {"week": "2026-W46", "brasil": 12340, "usa": 9870, "top": {"brasil": [{"name": "Biel", "points": 840}, {"name": "Lu", "points": 610}], "usa": [{"name": "Tex", "points": 920}]},
		"last": {"week": "2026-W45", "brasil": 20110, "usa": 18050, "winner": "brasil"}}
	Game.war_mine = 840
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 20: await get_tree().process_frame
	main.hud.open_window("journal", 4)
	for i in 20: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/war_panel.png")
	main.hud.toggle_journal()
	var rp := RemotePlayer.new().setup(77, {"char": {"name": "Tex", "level": 15, "belt": 1, "style": "wrestler", "faction": "usa", "gi": "1a3fbf", "skin": 0.3, "body": "male"},
		"x": main.player.global_position.x + 1.5, "y": main.player.global_position.y, "z": main.player.global_position.z + 1.0})
	main.world.add_child(rp)
	main.remotes[77] = rp
	for i in 20: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/war_rival_prompt.png")
	print("rival=", main._rival != null, " prompt=", main.hud.prompt.text)
	main._interact()
	for i in 90: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/war_rival_bout.png")
	get_tree().quit()
