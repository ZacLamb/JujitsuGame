extends Node
## Live duel, two real clients against a local server:
##   WORLD_DEV=1 PORT=3077 node server.js   (in the jujitsugame repo)
##   TATAME_API=http://127.0.0.1:3077 xvfb-run -a godot --rendering-driver opengl3 tests/probe_duel.tscn -- host|guest
var role := "host"
var main: Node
var done := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	Game.test_mode = true
	Game.reset()
	Game.set_identity("texan" if role == "guest" else "carioca", "male", 0.4)
	Game.choose_style("wrestler" if role == "guest" else "guard", "Host" if role == "host" else "Guest", 0)
	Game.set_level(20)
	Game.zone = "caceres"
	Cloud.token = "dev-" + role
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var spot := Vector3(10, 0, 30) if role == "host" else Vector3(11.5, 0, 30)
	main.player.teleport(Vector3(spot.x, main.world.ground_y(spot.x, spot.z) + 0.3, spot.z), 0.0)
	main.player.cam_yaw = 1.2 if role == "host" else -1.2
	main.pvp.finished.connect(func(won, nm, cr):
		print(role, " FINISHED won=", won, " vs ", nm, " cross=", cr, " war_pending=", Game.war_pending)
		done = true)
	# wait for the other client
	var t := 0.0
	while main.remotes.is_empty() and t < 40.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	print(role, " sees remotes=", main.remotes.size(), " net=", Net.connected, " my_id=", Net.my_id)
	if main.remotes.is_empty():
		get_tree().quit()
		return
	var rid: int = main.remotes.keys()[0]
	if role == "host":
		await get_tree().create_timer(2.0).timeout
		main.pvp.invite(rid, main.remotes[rid].char)
	else:
		while main.pvp.state != "invited" and t < 60.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		main.hud._close_dialogue(true)   # Accept
	while main.pvp.state != "host" and main.pvp.state != "guest" and t < 70.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	print(role, " duel state=", main.pvp.state)
	main.player.cam_dist = 7.0
	if role == "host" and main.pvp.opp:
		main.pvp.opp.hp = 60.0   # speed the test up: the guest is nearly done
	var shots := 0
	var keys := ["takedown", "pass", "sub", "sweep", "escape", "advance", "back", "base", "frame", "defend", "breathe"]
	var ft := 0.0
	while not done and ft < 120.0:
		await get_tree().create_timer(0.35).timeout
		ft += 0.35
		var c = main.combat
		if c.me == null or c.me.dead:
			continue
		for k in Game.bar_layout + keys:
			if str(k) != "":
				c.press(str(k))
		if int(ft) % 6 == 0 and shots < 4 and main.pvp.opp != null:
			get_viewport().get_texture().get_image().save_png("/home/claude/shots/duel_%s_%d.png" % [role, shots])
			print(role, " t=", int(ft), " me=", int(c.me.hp), "/", int(c.me.max_hp), " opp=", int(main.pvp.opp.hp), "/", int(main.pvp.opp.max_hp), " pos=", main.pvp.opp.gpos, " top=", main.pvp.opp.ptop)
			shots += 1
	await get_tree().create_timer(3.0).timeout
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/duel_%s_end.png" % role)
	print(role, " END done=", done, " record=", Game.pvp_record)
	get_tree().quit()
