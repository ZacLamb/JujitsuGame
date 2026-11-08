extends Node
var main: Node
func _shot(n: String) -> void:
	for i in 20: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/icons_%s.png" % n)
func _find(n: Node, cls: String) -> Node:
	for c in n.get_children():
		if c.has_signal("hovered") and "tid" in c and str(c.tid) != "":
			return c
		var r := _find(c, cls)
		if r:
			return r
	return null

func _ready() -> void:
	Engine.max_physics_steps_per_frame = 60
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(10)
	for id in ["torn_rash", "belt_tip", "mouthguard", "flip_flop", "tape_ball", "bottle", "patch", "medal_scrap", "acai", "coco", "guarana", "tape", "terere", "pao_queijo", "pacu"]:
		Game.add_item(id, 2)
	DayNight.hour = 11.0
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	DayNight.hour = 11.0
	if main.get("combat"):
		main.combat.rebuild_player()
	await _shot("bar")
	main.hud.toggle_bag()
	await _shot("bag")
	main.hud.toggle_bag()
	main.hud.open_window("talents", main.hud.TAB_SPELLBOOK)
	await _shot("book")
	main.hud.open_window("talents", main.hud.TAB_TALENTS)
	for i in 10: await get_tree().process_frame
	var tn = _find(main.hud, "TalentNode")
	if tn:
		tn.hovered.emit(str(tn.tid), true)
	await _shot("talent_tip")
	get_tree().quit()
