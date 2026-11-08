extends Node
## Visual QA for live fight motion: wind-ups, circling, reactions. Saves a frame strip.
var main: Node
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/motion_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(8)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 5: await get_tree().process_frame
	main._start_roll("tiago")
	var roll: RollScene = main.roll
	for i in 10: await get_tree().process_frame
	roll._go_live()
	roll.sim.ai_t = 99.0
	roll.motion.test_input = Vector2(1, 0.6)
	for i in 30: await get_tree().process_frame
	_shot("a_circle")
	roll.motion.test_input = Vector2.ZERO
	roll.sim.opp_control = 2
	roll.sim.opp_cast = {"id": "double_leg", "name": "Double-Leg Takedown", "kind": "move", "t": 0.0, "dur": 6.0, "spend": 2}
	roll.sim.events.append({"e": "cast", "who": "o", "id": "double_leg", "name": "Double-Leg Takedown", "kind": "move", "dur": 3.0, "counter": "base"})
	for i in 25: await get_tree().process_frame
	if not roll.sim.opp_cast.is_empty(): roll.sim.opp_cast.t = 2.6
	for i in 3: await get_tree().process_frame
	_shot("b_windup")
	roll.sim.opp_cast = {}
	roll.sim._land("double_leg", false, 2)
	for i in 14: await get_tree().process_frame
	_shot("c_shot_mid")
	for i in 40: await get_tree().process_frame
	_shot("d_guard")
	roll._defend("frame")
	roll.motion.bump(roll.player_rig, FightMotion.BRACE.frame, 0.5)
	for i in 8: await get_tree().process_frame
	_shot("e_brace")
	get_tree().quit()
