extends Node
## Team USA quartermaster panel + the Gold Compound raid.
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.set_identity("texan", "male", 0.4)
	Game.choose_style("passer", "Tex", 0)
	Game.set_level(24)
	Game.honor = 1500
	Game.zone = "texas"
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 20: await get_tree().process_frame
	main.player.teleport(Vector3(15, main.world.ground_y(15, 9) + 0.3, 9), 0.0)
	main.player.cam_yaw = 0.0
	for i in 30: await get_tree().process_frame
	main.hud.open_quartermaster("Sergeant Briggs", "usa")
	for i in 10: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/qm_panel.png")
	print("buy=", Game.buy_honor("old_glory_gi"), " honor=", Game.honor)
	main.hud._qm_fill()
	main.hud.qm_panel.queue_free()
	main._travel("everglades", true)
	for i in 30: await get_tree().process_frame
	main.hud._close_dialogue(false)
	main.player.teleport(Vector3(-62, main.world.ground_y(-62, -62) + 0.3, -62), 0.0)
	main.player.cam_yaw = 0.0
	main.player.cam_dist = 12.0
	for i in 30: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/qm_compound.png")
	main._start_raid()
	for i in 60: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/qm_raid.png")
	print("raid=", main.combat.raid != null, " boss=", main.combat.raid.boss.name if main.combat.raid else "")
	get_tree().quit()
