extends Node
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/dummy_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Engine.max_physics_steps_per_frame = 60
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(3)
	var L := {}
	for id in Abilities.LESSON_SET:
		L[id] = true
	Game.flags["learned"] = L
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var w: World = main.world
	var c: WorldCombat = main.combat
	c.rebuild_player()
	var dummy: Npc = null
	var spar: Npc = null
	var mob: Npc = null
	for e in w.mobs:
		if e.npc and e.npc.mob.get("dummy", false):
			if e.npc.mob.spar: spar = e.npc
			else: dummy = e.npc
		elif e.npc and mob == null:
			mob = e.npc
	print("dummies: ", dummy != null, " ", spar != null, " at ", dummy.global_position)
	var p := dummy.global_position + Vector3(-1.2, 0, 1.2)
	main.player.teleport(Vector3(p.x, w.ground_y(p.x, p.z) + 1.0, p.z), 0.8)
	for i in 20: await get_tree().process_frame
	var me := c.me
	print("bar before: ", Game.bar_layout, " has guard ability: ", not c.core.ability(me, "guard").is_empty())
	_shot("a_nodummy")
	c.set_target_npc(dummy)
	await get_tree().create_timer(0.3).timeout
	me = c.me
	print("drilling ", Game.drilling, " temp ", Game.drill_temp(), " has guard: ", not c.core.ability(c.me, "guard").is_empty())
	_shot("a_drill")
	for i in 3:
		me.gcd = 0.0; me.cds.clear(); me.gas = me.max_gas
		c.press("guard"); print("press guard err: ", c.error_text if c.error_t > 0 else "")
		await get_tree().create_timer(0.5).timeout
		c.core.stand_up(c.target)
	await get_tree().create_timer(0.6).timeout
	print("guard learned: ", Game.ab_learned("guard"), " locked now: ", c.core.ability(c.me, "guard").get("locked", false))
	for i in 4:
		c.me.gcd = 0.0; c.me.gas = c.me.max_gas
		c.press("handfight")
		await get_tree().create_timer(0.4).timeout
	print("bar after learn: ", Game.bar_layout)
	_shot("c_learned")
	print("dummy hp ", snappedf(c.target.pct(), 0.01), " done ", c.me.done, " xp ", Game.xp)
	_shot("b_hit")
	# sparring dummy throws something
	c.core.leave_combat(c.me)
	var p2 := spar.global_position + Vector3(-1.2, 0, 1.2)
	main.player.teleport(Vector3(p2.x, w.ground_y(p2.x, p2.z) + 1.0, p2.z), 0.8)
	c.set_target_npc(spar)
	c.engage_npc(spar)
	var su := c.unit_for(spar)
	spar.set_meta("dummy_t", 0.3)
	var saw := false
	for i in 30:
		await get_tree().create_timer(0.2).timeout
		if not su.cast.is_empty():
			saw = true
			print("spar casts: ", su.cast.ab.name)
			break
	var hp0 := c.me.hp
	await get_tree().create_timer(3.4).timeout
	print("spar cast seen ", saw, " player hp change ", c.me.hp - hp0)
	get_tree().quit()
