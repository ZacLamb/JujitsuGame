extends Node
## Stills of each stage of a technique's arc (side view): one row per move.
func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(8)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	var w: World = main.world
	var c: WorldCombat = main.combat
	var mob: Npc = null
	for e in w.mobs:
		if e.npc and e.camp.id == "quadra":
			mob = e.npc
			break
	var p := mob.global_position + Vector3(1.2, 0, 0)
	main.player.teleport(Vector3(p.x, w.ground_y(p.x, p.z) + 0.2, p.z), 0.0)
	for i in 20: await get_tree().process_frame
	w.aggro_grace = 999.0
	var u := c.unit_for(mob)
	c.set_target_npc(mob)
	c.engage_npc(mob)
	CombatCore.gm_god = true
	main.hud.visible = false
	main.hud.root.visible = false
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.current = true
	cam.fov = 45
	var moves: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("moves="):
			moves = Array(a.substr(6).split(","))
	var tiles: Array = []
	var cols := 5
	for mv in moves:
		var md: Dictionary = Data.MOVES[mv]
		var from := str(md.get("pos", "standing"))
		var res: Array = md.get("result", ["side", true])
		var actor_top_after: bool = res[1]
		# start position: actor is the player
		u.ai_t = 999.0
		u.cast = {}
		u.gpos = from
		u.ptop = str(md.get("role", "top")) == "top" if from != "standing" else false
		if from == "standing":
			main.player.rig.release(CombatAnim.getup(main.player.rig.rotation.y))
			mob.rig.release(CombatAnim.getup(mob.rig.rotation.y))
		else:
			c._show_position(u)
		for i in 22:
			u.ai_t = 999.0
			await get_tree().process_frame
		var pr: BodyRig = main.player.rig
		var nr: BodyRig = mob.rig
		u.gpos = str(res[0])
		u.ptop = actor_top_after
		var pair := RollPoses.get_pair(u.gpos)
		var mid: Vector3 = (main.player.global_position + mob.global_position) * 0.5
		var to: Vector3 = mob.global_position - main.player.global_position
		var yaw := atan2(-to.x, -to.z)
		var anchor := Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, w.ground_y(mid.x, mid.z), mid.z))
		var arc := MoveArcs.arc(mv)
		var fr := {}
		for side in [["top", pr if u.ptop else nr], ["bottom", nr if u.ptop else pr]]:
			var rig: BodyRig = side[1]
			var mate: BodyRig = nr if rig == pr else pr
			var parent := rig.get_parent() as Node3D
			var local: Transform3D = parent.global_transform.affine_inverse() * anchor * pair[side[0]][1]
			var tw: Vector3 = parent.global_transform.basis.inverse() * (mate.global_position - rig.global_position)
			fr[rig] = MoveArcs.frames(rig.current_pose(), rig.current_root(), arc.actor if rig == pr else arc.other, pair[side[0]][0], local, tw, bool(arc.get("flip", false)) and rig != pr)
		var n: int = maxi(fr[pr].size(), fr[nr].size())
		var b := Basis(Vector3.UP, atan2(to.x, to.z) - PI / 2)
		cam.global_position = mid + Vector3(0, 0.5, 0) + b * Vector3(0.5, 0.9, 3.6)
		cam.look_at(mid + Vector3(0, 0.6, 0), Vector3.UP)
		for i in cols:
			var shown := false
			for rig in [pr, nr]:
				var f: Array = fr[rig]
				var j: int = i - 1
				if i == 0:
					continue
				j = mini(j, f.size() - 1)
				if f[j][2] < 0.01:
					j -= 1
				rig._enter_pose_mode()
				rig.apply_pose(f[j][0])
				rig.position = f[j][1].origin
				rig.quaternion = f[j][1].basis.get_rotation_quaternion()
				rig._action_until = INF
				shown = true
			for k in 3: await get_tree().process_frame
			var im := get_viewport().get_texture().get_image()
			im = im.get_region(Rect2i(290, 100, 700, 520))
			im.resize(320, 238)
			tiles.append(im)
	var rows := moves.size()
	var sheet := Image.create(320 * cols, 238 * rows, false, tiles[0].get_format())
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 320, 238), Vector2i((i % cols) * 320, (i / cols) * 238))
	sheet.save_png("/home/claude/shots/arc_sheet.png")
	get_tree().quit()
