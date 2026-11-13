extends Node
## Close-up of every grappling position pair as the world fight shows it (side + 3/4 view).
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
	var p := mob.global_position + Vector3(1.2, 0, 0)
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
	for pos in ["guard", "half", "side", "mount", "back"]:
		u.gpos = pos
		u.ptop = true
		u.ai_t = 999.0
		u.cast = {}
		c._show_position(u)
		for i in 40:
			u.ai_t = 999.0
			await get_tree().process_frame
		var mid: Vector3 = (main.player.global_position + mob.global_position) * 0.5 + Vector3(0, 0.4, 0)
		for view in [["side", Vector3(0, 0.9, 3.2)], ["34", Vector3(2.4, 1.8, 2.4)]]:
			var off: Vector3 = view[1]
			var to: Vector3 = mob.global_position - main.player.global_position
			var b := Basis(Vector3.UP, atan2(to.x, to.z) + PI / 2)
			cam.global_position = mid + b * off
			cam.look_at(mid, Vector3.UP)
			for i in 3: await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("/home/claude/shots/pos_%s_%s.png" % [pos, view[0]])
	get_tree().quit()
