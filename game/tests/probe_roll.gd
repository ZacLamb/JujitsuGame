extends Node
## Renders the real-time roll UI for visual QA.
var main: Node
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/roll_%s.png" % n)
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
	for i in 20: await get_tree().process_frame
	_shot("intro")
	roll._go_live()
	Engine.time_scale = 0.15
	roll.sim.ai_t = 99.0
	roll._use("grip")
	for i in 40: await get_tree().process_frame
	roll._use("grip")
	for i in 12: await get_tree().process_frame
	# force an opponent technique cast so the alert shows
	roll.sim.cast = {}
	roll.sim.opp_control = 2
	roll.sim.opp_cast = {"id": "double_leg", "name": "Double-Leg Takedown", "kind": "move", "t": 0.0, "dur": 2.5, "spend": 2}
	roll.sim.events.append({"e": "cast", "who": "o", "id": "double_leg", "name": "Double-Leg Takedown", "kind": "move", "dur": 2.5, "counter": "base"})
	for i in 10: await get_tree().process_frame
	_shot("live")
	roll.sim.opp_cast = {}
	roll.sim.pos = "mount"
	roll.sim.player_top = true
	roll.sim.control = 4
	for i in 20: await get_tree().process_frame
	_shot("mount")
	roll.sim._land("mount_armbar", true, 4)
	for i in 6: await get_tree().process_frame
	roll._struggle_tap()
	roll._struggle_tap()
	for i in 4: await get_tree().process_frame
	_shot("struggle")
	get_tree().quit()
