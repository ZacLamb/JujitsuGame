extends Node
## Rotation HUD: aura icons, a lit proc button, the burst button, target of target, the meter.
var main: Node
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/rot_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Engine.max_physics_steps_per_frame = 60
	Game.reset()
	var style := "judoka"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("style="):
			style = a.substr(6)
	Game.choose_style(style, "Gringo", 0)
	Game.set_level(8)
	main = load("res://main.tscn").instantiate()
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
	var p := mob.global_position + Vector3(1.6, 0, 1.6)
	main.player.teleport(Vector3(p.x, w.ground_y(p.x, p.z) + 1.0, p.z), 0.8)
	for i in 20: await get_tree().process_frame
	c.set_target_npc(mob)
	c.engage_npc(mob)
	c.core.opening_chance = 1.0
	CombatCore.gm_god = true
	var me: CombatCore.Unit = c.me
	for i in 3:
		await get_tree().create_timer(1.1).timeout
		print("hf: ", c.core.use(me, "handfight"))
	await get_tree().create_timer(0.3).timeout
	print("auras me ", me.auras.keys(), " tgt ", c.target.auras.keys() if c.target else "-")
	_shot("a_proc")
	print("burst: ", c.core.use(me, "burst"))
	c.core._aura(c.target, "pinned", 9.0, me)
	c.core._aura(c.target, "exposed", 4.0, me)
	c.core._aura(me, "flow", 7.0, me)
	me.auras.flow["n"] = 3
	await get_tree().create_timer(1.3).timeout
	Input.warp_mouse(Vector2(78 + 13, 76 + 13))
	await get_tree().create_timer(0.4).timeout
	_shot("b_burst")
	CombatCore.gm_god = false
	get_tree().quit()
