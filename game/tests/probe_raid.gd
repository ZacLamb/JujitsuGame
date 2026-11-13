extends Node
## Raid: spawn, pull, a bot fights with counters for up to 4 minutes; logs mechanics + result.
var main: Node
var log_lines: Array = []
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/raid_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Engine.max_physics_steps_per_frame = 60
	Game.reset()
	Game.choose_style(OS.get_environment("RS") if OS.get_environment("RS") != "" else "guard", "Gringo", 0)
	Game.set_level(int(OS.get_environment("RL")) if OS.get_environment("RL") != "" else 15)
	Game.spec = str(Specs.list(Game.style)[0].id)
	for pass_n in 20:
		for tr in ["class", "spec"]:
			for nd in TalentTrees.tree(tr, Game.spec):
				if Game.can_learn(str(nd.id)):
					Game.learn(str(nd.id))
	for id in Gear.ITEMS:
		if Gear.ilvl(id) <= Game.player_level() and not Gear.ITEMS[id].get("rolled", false):
			Game.give_item(id, true)
	DayNight.hour = 11.0
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var c: WorldCombat = main.combat
	c.rebuild_player()
	c.core.event.connect(func(e):
		var k := str(e.t)
		if k == "tap":
			log_lines.append("TAP %s by %s" % [e.u.name, e.by.name if e.by else "?"])
		elif k == "interrupt":
			log_lines.append("COUNTER %s" % str(e.get("text", "")))
		elif k == "proc" and not e.u.player:
			log_lines.append("PROC %s: %s" % [e.u.name, str(e.text)]))
	c.raid_warning.connect(func(h, sb): log_lines.append("WARN %s" % h))
	var won = null
	c.raid_over.connect(func(w): won = w)
	main.player.teleport(Vector3(20, main.world.ground_y(20, 40) + 1, 40), 0.0)
	for i in 10: await get_tree().process_frame
	main._start_raid()
	for i in 30: await get_tree().process_frame
	_shot("a_party")
	c.engage_npc(c.raid.boss_npc)
	c.core.use(c.me, "handfight", c.raid.boss)
	var t0 := Time.get_ticks_msec()
	var shot_done := false
	var rng := RandomNumberGenerator.new()
	while won == null and Time.get_ticks_msec() - t0 < 400000:
		await get_tree().create_timer(0.2).timeout
		if c.raid == null:
			break
		if c.core.in_struggle(c.me):
			c.press("sub")
			c.press("sub")
			continue
		var tg = c.target if c.target and not c.target.dead else c.raid.boss
		c.target = tg
		# walk to melee range of the target
		var to: Vector3 = tg.pos - main.player.global_position
		to.y = 0
		if to.length() > 2.0:
			main.player.global_position += to.normalized() * minf(1.2, to.length() - 1.6)
		if not tg.cast.is_empty() and not tg.cast.has("_seen") and float(tg.cast.t) > 0.5:
			tg.cast["_seen"] = true
			if rng.randf() < 0.8:
				c.core.use(c.me, {"base": "base", "frame": "frame", "defend": "defend"}[CombatCore.counter_kind(tg.cast.ab)])
		if c.raid and not c.raid.boss.cast.is_empty() and str(c.raid.boss.cast.ab.id) == "wave" and not c.raid.boss.cast.has("_seen") and float(c.raid.boss.cast.t) > 0.6:
			c.raid.boss.cast["_seen"] = true
			c.target = c.raid.boss
			if rng.randf() < 0.8:
				c.core.use(c.me, "base", c.raid.boss)
		if c.me.down():
			c.core.use(c.me, "escape")
		for id in ["sub", "spec", "advance", "back", "takedown", "pass", "sweep", "handfight"]:
			if id == "sub" and c.me.grip < 3:
				continue
			if c.core.use(c.me, id, c.target) == "":
				break
		if not shot_done and c.raid and c.raid.t > 20.0:
			shot_done = true
			_shot("b_fight")
	_shot("c_end")
	for l in log_lines: print(l)
	print("RAID RESULT won=", won, " t=", (Time.get_ticks_msec() - t0) / 1000.0, "s")
	get_tree().quit()
