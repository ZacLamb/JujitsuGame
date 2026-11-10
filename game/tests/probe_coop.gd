extends Node
## Party + co-op dungeon, two real clients against a local server:
##   WORLD_DEV=1 PORT=3077 node server.js   (in the jujitsugame repo)
##   TATAME_API=http://127.0.0.1:3077 xvfb-run -a godot --rendering-driver opengl3 tests/probe_coop.tscn -- host|guest
var role := "host"
var main: Node
var over := false
var won := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	Game.test_mode = true
	Game.reset()
	Game.set_identity("carioca" if role == "host" else "gringo", "male" if role == "host" else "female", 0.4)
	Game.choose_style("guard" if role == "host" else "wrestler", "Host" if role == "host" else "Guest", 0)
	Game.set_level(10)
	Game.zone = "caceres"
	Cloud.token = "dev-" + role
	get_window().size = Vector2i(800, 450)
	Game.set_graphics_level(0)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var spot := Vector3(10, 0, 30) if role == "host" else Vector3(12, 0, 31)
	main.player.teleport(Vector3(spot.x, main.world.ground_y(spot.x, spot.z) + 0.3, spot.z), 0.0)
	main.combat.raid_over.connect(func(w): over = true; won = w; print(role, " RAID OVER won=", w))
	var t := 0.0
	while main.remotes.is_empty() and t < 40.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	print(role, " sees remotes=", main.remotes.size(), " my_id=", Net.my_id)
	if main.remotes.is_empty():
		get_tree().quit()
		return
	if role == "host":
		await get_tree().create_timer(2.0).timeout
		main.party.invite("Guest")
		while not main.party.in_party() and t < 60.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		print("host party=", main.party.order, " leader=", main.party.leader)
		await get_tree().create_timer(3.0).timeout   # a status round so the guest's zone is known
		get_viewport().get_texture().get_image().save_png("/home/claude/shots/coop_party_host.png")
		main.start_dungeon("basement")
		print("host coop state=", main.coop.state)
	else:
		while main._party_ask != "party" and t < 60.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		get_viewport().get_texture().get_image().save_png("/home/claude/shots/coop_invite_guest.png")
		main.hud._close_dialogue(true)
		while main._party_ask != "coop" and t < 90.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		print("guest party=", main.party.order, " leader=", main.party.leader, " ask=", main._party_ask)
		main.hud._close_dialogue(true)
	while main.coop.state != "host" and main.coop.state != "guest" and t < 110.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	print(role, " coop=", main.coop.state)
	main.player.cam_dist = 9.0
	var keys := ["takedown", "pass", "sub", "sweep", "escape", "advance", "back", "base", "frame", "defend", "breathe"]
	var ft := 0.0
	var shots := 0
	while not over and ft < 400.0:
		await get_tree().create_timer(0.35).timeout
		ft += 0.35
		var c = main.combat
		if c.me != null and not c.me.dead:
			if role == "guest" and c.target == null:
				c._auto_target()
			if role == "guest" and c.target != null and c.core.dist(c.me, c.target) > 1.8:
				var tp: Vector3 = c.target.pos + Vector3(1.2, 0, 0.8)
				main.player.teleport(Vector3(tp.x, main.world.ground_y(tp.x, tp.z) + 0.3, tp.z), main.player.rig.rotation.y)
			for k in Game.bar_layout + keys:
				if str(k) != "":
					c.press(str(k))
		if ft >= 12.0 * (shots + 1) and shots < 8:
			get_viewport().get_texture().get_image().save_png("/home/claude/shots/coop_%s_%d.png" % [role, shots])
			var units := []
			for u in c.core.units:
				var uid: int = u.id if role == "host" else main.coop._uid_of(u)
				units.append("%s#%d:%d%s" % [u.name, uid, int(u.hp), "x" if u.dead else ""])
			print(role, " t=", int(ft), " units=", units)
			shots += 1
	await get_tree().create_timer(4.0).timeout
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/coop_%s_end.png" % role)
	print(role, " ACTS=", main.coop.acts)
	print(role, " END over=", over, " won=", won, " xp=", Game.xp, " bag=", Game.bag.size() if "bag" in Game else -1)
	get_tree().quit()
