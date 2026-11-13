extends Node
## A brand-new player's first roll with Rafa, played by a human-ish bot (0.4s reactions, misses
## some reads, never guesses). Captures the intro, the first read call, worn down, and the end.
var main: Node
var shots := {}
func _shot(n: String) -> void:
	if shots.has(n):
		return
	shots[n] = true
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/fr_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	for i in 10: await get_tree().process_frame
	main.hud._close_dialogue(false)
	var w: World = main.world
	var c: WorldCombat = main.combat
	var rafa: Npc = null
	var stack: Array = [w]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Npc and (n as Npc).opp_id == "rafa":
			rafa = n
		stack.append_array(n.get_children())
	var p := rafa.global_position + Vector3(1.6, 0, 0)
	main.player.teleport(Vector3(p.x, w.ground_y(p.x, p.z) + 0.3, p.z), 0.0)
	main.player.cam_yaw = -PI / 2
	for i in 15: await get_tree().process_frame
	main._interact(rafa)
	for i in 10: await get_tree().process_frame
	_shot("a_intro")
	print("INTRO: ", main.hud.dialogue_open())
	main.hud._close_dialogue(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var t0 := Time.get_ticks_msec()
	var seen := {}
	var reads := 0
	var hits := 0
	while Time.get_ticks_msec() - t0 < 80000:
		await get_tree().create_timer(0.2).timeout
		var tg = c.target
		if tg == null or c._finishing:
			break
		if not tg.cast.is_empty():
			_shot("b_read")
			var key := str(tg.cast.ab.get("id", "")) + str(tg.cast.get("dur", 0))
			if float(tg.cast.t) > 0.4 and not seen.has(key):
				seen[key] = true
				reads += 1
				if rng.randf() < 0.75:
					c.press(CombatCore.counter_kind(tg.cast.ab))
					hits += 1
				continue
		if tg.has("worn"):
			_shot("c_worn")
		if c.me.down():
			c.press("escape")
			continue
		for id in ["sub", "takedown", "handfight"]:
			if id == "sub" and c.me.grip < 3 and not tg.has("worn"):
				continue
			if c.core.use(c.me, id, tg) == "":
				break
	await get_tree().create_timer(1.2).timeout
	_shot("d_end")
	print("RESULT won=", Game.beaten("rafa"), " reads=", reads, " countered=", hits, " my hp=", int(c.me.hp), "/", int(c.me.max_hp), " t=", (Time.get_ticks_msec() - t0) / 1000.0)
	await get_tree().create_timer(2.0).timeout
	_shot("e_after")
	get_tree().quit()
