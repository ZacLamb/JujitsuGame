extends Node
## Vila Nova, mobs, bags, vendor and a mob fight's loot.
var main: Node
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/mobs_%s.png" % n)
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(3)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var w: World = main.world
	print("mobs: ", w.mobs.size(), " camps ok")
	for e in w.mobs:
		if e.npc:
			var p: Vector3 = e.npc.global_position
			print("  ", e.camp.id, " ", e.npc.mob.name, " lv", snappedf(e.npc.mob.level, 0.1), " y=", snappedf(p.y, 0.1))
	main.player.teleport(Vector3(46, w.ground_y(46, 30) + 1.0, 30), PI)
	w.aggro_grace = 999.0
	for i in 40: await get_tree().process_frame
	_shot("a_vilanova")
	main.player.teleport(Vector3(56, w.ground_y(56, 56) + 1.0, 56), PI * 0.8)
	for i in 40: await get_tree().process_frame
	_shot("b_quadra")
	# bags + vendor
	Game.add_item("torn_rash", 3)
	Game.add_item("terere", 2)
	Game.add_item("gear:" + str(Gear.ITEMS.keys()[3]))
	Game.add_item("bag_lona")
	main.hud.open_shop("Seu Jorge")
	for i in 6: await get_tree().process_frame
	_shot("c_shop")
	main.hud.close_shop()
	# a mob fight, won, to see loot
	var mob_npc: Npc = null
	for e in w.mobs:
		if e.npc:
			mob_npc = e.npc
			break
	main._start_mob(mob_npc)
	for i in 10: await get_tree().process_frame
	main.roll._go_live()
	main.roll.sim.player_pts = 4
	main.roll.sim.clock = 0.05
	for i in 90: await get_tree().process_frame
	_shot("d_loot")
	print("bag used: ", Game.bag_capacity() - Game.free_slots(), " money ", Game.money)
	get_tree().quit()
