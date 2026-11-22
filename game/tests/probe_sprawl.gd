extends Node
## Side view of the sprawl: player flat on the shooter.
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(8)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var w: World = main.world
	var c: WorldCombat = main.combat
	var mob: Npc = null
	for e in w.mobs:
		if e.npc and e.camp.id == "quadra":
			mob = e.npc
			break
	var p := mob.global_position + Vector3(1.5, 0, 0)
	main.player.teleport(Vector3(p.x, w.ground_y(p.x, p.z) + 0.2, p.z), 0.0)
	for i in 20: await get_tree().process_frame
	w.aggro_grace = 999.0
	var u := c.unit_for(mob)
	c.set_target_npc(mob)
	c.engage_npc(mob)
	CombatCore.gm_god = true
	main.hud.visible = false
	main.hud.root.visible = false
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.current = true
	cam.fov = 45
	u.ai_t = 999.0
	var td: Dictionary = c.core.ability(u, "e_take")
	u.cast = {"ab": td, "t": 0.0, "dur": 1.4, "target": c.me}
	c.core.emit({"t": "cast", "u": u, "ab": td, "target": c.me, "dur": 1.4})
	await get_tree().create_timer(0.9).timeout
	c.me.cds.clear()
	c.press("base")
	var tiles: Array = []
	for k in 3:
		await get_tree().create_timer([0.3, 0.05, 0.6][k]).timeout
		print("t", k, " hips ", snappedf(main.player.rig.hips.position.y, 0.01), " in_action ", main.player.rig.in_action(), " dist ", snappedf(main.player.global_position.distance_to(mob.global_position), 0.01), " rigpos ", main.player.rig.position, " mobrig ", mob.rig.position, " err ", c.error_text)
		var mid: Vector3 = (main.player.global_position + mob.global_position) * 0.5 + Vector3(0, 0.5, 0)
		var to: Vector3 = mob.global_position - main.player.global_position
		var b := Basis(Vector3.UP, atan2(to.x, to.z) + PI / 2)
		cam.global_position = mid + b * Vector3(0.5, 2.2, 4.2)
		cam.look_at(mid, Vector3.UP)
		for i in 2: await get_tree().process_frame
		var im := get_viewport().get_texture().get_image()
		im = im.get_region(Rect2i(160, 60, 960, 576))
		im.resize(400, 240)
		tiles.append(im)
	var yy: float = c._yaw_to(c.me, u)
	main.player.rig.action([CombatAnim.sprawl(yy)[1]], true)
	print("in_action ", main.player.rig.in_action(), " grounded ", c._grounded(c.me))
	await get_tree().create_timer(0.5).timeout
	print("hips y ", main.player.rig.hips.position.y)
	for i in 2: await get_tree().process_frame
	var im2 := get_viewport().get_texture().get_image()
	im2 = im2.get_region(Rect2i(160, 60, 960, 576))
	im2.resize(400, 240)
	tiles[2] = im2
	var sheet := Image.create(1200, 240, false, tiles[0].get_format())
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 400, 240), Vector2i(i * 400, 0))
	sheet.save_png("/home/claude/shots/sprawl_sheet.png")
	get_tree().quit()
