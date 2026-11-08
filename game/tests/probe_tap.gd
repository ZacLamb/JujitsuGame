extends Node
## Get tapped by a mob: gloat, coach's note, the choice, no evade spam, revenge tag.
var main: Node
var evades := 0
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/tap_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Engine.max_physics_steps_per_frame = 60
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(3)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var w: World = main.world
	var c: WorldCombat = main.combat
	c.core.event.connect(func(e): pass)
	var mob: Npc = null
	for e in w.mobs:
		if e.npc and e.camp.id == "quadra":
			mob = e.npc
			break
	var p := mob.global_position + Vector3(1.5, 0, 1.5)
	main.player.teleport(Vector3(p.x, w.ground_y(p.x, p.z) + 1.0, p.z), 0.8)
	main.player.input_enabled = true
	for i in 10: await get_tree().process_frame
	c.engage_npc(mob)
	c.me.hp = 8.0
	var t0 := Time.get_ticks_msec()
	while not c.tap_pending and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	for i in 10: await get_tree().process_frame
	var n := 0
	for l in mob.find_children("*", "Label3D", true, false):
		if (l as Label3D).text == "Evade":
			n += 1
	print("TAP pending ", c.tap_pending, " evade labels ", n, " revenge ", mob.mob.get("revenge", false), " tag ", mob.tag.text.replace("\n", " | "))
	_shot("a_dialog")
	main.hud._close_dialogue(true)
	for i in 10: await get_tree().process_frame
	print("AFTER hp ", int(c.me.hp), "/", int(c.me.max_hp), " rattled ", c.me.has("rattled"), " input ", main.player.input_enabled)
	_shot("b_after")
	get_tree().quit()
