extends Node
## Live path: press pinned techniques in a real fight and grab frames mid-arc.
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("judoka", "Gringo", 0)
	Game.set_level(12)
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
	Game.bar_set(10, "mv:o_goshi")
	var seq := ["mv:o_goshi", "mv:knee_slice", "mv:toreando"]
	var n := 0
	for id in seq:
		u.ai_t = 999.0
		c.me.gcd = 0.0
		c.me.cds.clear()
		c.me.gas = c.me.max_gas
		c.me.grip = 3
		c.press(id)
		print(id, " -> err='", c.error_text if c.error_t > 0.0 else "", "' pos=", u.gpos, " top=", u.ptop)
		for k in 3:
			for i in 2:
				u.ai_t = 999.0
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("/home/claude/shots/throw_%d.png" % n)
			n += 1
		for i in 10:
			u.ai_t = 999.0
			await get_tree().process_frame
	get_tree().quit()
