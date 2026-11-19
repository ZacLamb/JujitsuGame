extends Node
## Plays the first lesson with a scripted player and screenshots it.
var main: Node
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/lesson_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Scenes.force = true
	Engine.max_physics_steps_per_frame = 60
	Game.reset()
	Game.choose_style("wrestler", "Gringo", 0)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 20: await get_tree().process_frame
	var c: WorldCombat = main.combat
	print("kit: ", c.me.abilities.map(func(a): return a.id), " bar ", Game.bar_layout)
	main.start_lesson()
	var L: Lesson = main.lesson
	var t0 := Time.get_ticks_msec()
	var last := -1
	var shots := {5: "read", 8: "mixed", 9: "finish"}
	while is_instance_valid(L) and not L._over and Time.get_ticks_msec() - t0 < 100000:
		await get_tree().create_timer(0.35).timeout
		if not is_instance_valid(L) or L._over:
			break
		if L.step != last:
			last = L.step
			print("STEP ", L.step, " ", Lesson.STEPS[L.step].id if L.step < Lesson.STEPS.size() else "end")
		var s: Dictionary = Lesson.STEPS[L.step] if L.step < Lesson.STEPS.size() else {}
		if s.is_empty() or L._wait > 0.0:
			continue
		var me := c.me
		me.gcd = 0.0
		match str(s.id):
			"grip": c.press("handfight")
			"takedown": c.press("takedown")
			"climb": c.press("pass")
			"escape": c.press("escape")
			"read_td", "read_pass", "read_sub", "mixed":
				if not L.foe.cast.is_empty() and float(L.foe.cast.t) > 1.0:
					if shots.has(L.step):
						_shot(shots[L.step]); shots.erase(L.step)
					c.press(CombatCore.counter_kind(L.foe.cast.ab))
			"finish":
				if shots.has(L.step):
					_shot(shots[L.step]); shots.erase(L.step)
				c.press("sub")
	print("lesson over: ", not is_instance_valid(L) or L._over, " done flag ", Game.flags.get("lesson_done", false), " secs ", (Time.get_ticks_msec() - t0) / 1000.0)
	get_tree().quit()
