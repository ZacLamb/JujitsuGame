extends Node
## In-world WoW-style combat: engage a mob, play a rotation, capture mid-fight / finisher frames.
var main: Node
var log_lines: Array = []
var ground_shot := {}
func _later_shot(n: String) -> void:
	await get_tree().create_timer(0.7).timeout
	_shot(n)
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/wc_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Engine.max_physics_steps_per_frame = 60
	Game.reset()
	Game.choose_style("wrestler", "Gringo", 0)
	Game.set_level(6)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var w: World = main.world
	var c: WorldCombat = main.combat
	c.core.event.connect(func(e):
		if str(e.t) == "position":
			log_lines.append("POS %s top=%s by %s +%d" % [e.pos, e.ptop, e.by.name, e.pts])
			if str(e.pos) != "standing" and not ground_shot.has(str(e.pos)):
				ground_shot[str(e.pos)] = true
				_later_shot("g_" + str(e.pos))
		elif str(e.t) == "cast" and str(e.ab.get("type", "")) == "sub" and not ground_shot.has("sub"):
			ground_shot["sub"] = true
			_later_shot("s_sub_" + str(e.ab.get("_mv", "")))
		elif str(e.t) == "proc":
			log_lines.append("PROC %s: %s" % [e.u.name, str(e.text)])
		elif str(e.t) in ["tap", "interrupt"]:
			log_lines.append("%s %s %s" % [e.t, e.u.name, str(e.get("text", ""))]))
	var mob: Npc = null
	for e in w.mobs:
		if e.npc and e.camp.id == "quadra":
			mob = e.npc
			break
	var p := mob.global_position + Vector3(2.5, 0, 2.5)
	main.player.teleport(Vector3(p.x, w.ground_y(p.x, p.z) + 1.0, p.z), 0.8)
	main.player.input_enabled = true
	for i in 20: await get_tree().process_frame
	c.set_target_npc(mob)
	_shot("a_target")
	c.engage_npc(mob)
	var t0 := Time.get_ticks_msec()
	var shots := {1500: "b_fight", 3200: "c_fight2"}
	while Time.get_ticks_msec() - t0 < 90000:
		await get_tree().create_timer(0.25).timeout
		var el := Time.get_ticks_msec() - t0
		for k in shots.keys():
			if el > k:
				_shot(shots[k])
				shots.erase(k)
		if c.target == null:
			break
		var why := []
		var tg = c.target
		if tg and not tg.cast.is_empty() and float(tg.cast.t) > 0.5:
			c.core.use(c.me, {"base": "base", "frame": "frame", "defend": "defend"}[CombatCore.counter_kind(tg.cast.ab)])
		for id in ["sub", "advance", "back", "takedown", "pass", "sweep", "handfight"]:
			if id == "sub" and c.me.grip < 4:
				continue
			var r := c.core.use(c.me, id, c.target)
			why.append(r)
			if r == "":
				break
		if el % 3000 < 300:
			print("T ", el, " why ", why, " d ", snappedf(c.core.dist(c.me, c.target), 0.1), " hp ", int(c.target.hp), " cast ", not c.me.cast.is_empty(), " gas ", int(c.me.gas), " grip ", c.me.grip, " tin ", c.target.in_combat, " min ", c.me.in_combat, " dead ", c.target.dead)
		if c._finishing:
			await get_tree().create_timer(0.9).timeout
			_shot("d_finish")
			await get_tree().create_timer(1.6).timeout
			break
	await get_tree().create_timer(0.8).timeout
	_shot("e_after")
	print("LOG ", log_lines)
	print("XP ", Game.stripe_xp, " me hp ", int(c.me.hp), "/", int(c.me.max_hp))
	get_tree().quit()
