extends Node
## Every zone: is everything a player has to reach actually reachable? NPCs, quest givers,
## collectibles, quest spots, camps, vendors, spawns: not under water, not inside a wall, not on a
## cliff face, inside the map. godot --headless tests/test_world_audit.tscn [-- zone]
var fails := 0

func _ready() -> void:
	Game.test_mode = true
	var only: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	for z in Data.ZONES:
		if only != "" and z != only:
			continue
		await _audit(z)
	print("PASS (0 failures)" if fails == 0 else "FAILED: %d" % fails)
	get_tree().quit()

func _points(z: String) -> Array:
	var pts: Array = []
	for id in Data.OPPONENTS:
		if Data.zone_of(id) == z:
			pts.append(["fighter " + id, Data.OPPONENTS[id].pos, not Data.OPPONENTS[id].get("boss", false)])
	for id in Data.QUEST_GIVERS:
		if Data.QUEST_GIVERS[id].zone == z:
			pts.append(["giver " + id, Data.QUEST_GIVERS[id].pos, true])
	var cl: Array = Data.COLLECTIBLES.get(z, [])
	for i in cl.size():
		pts.append(["collectible %d" % i, cl[i], false])
	for id in Data.TERRITORIES:
		if Data.TERRITORIES[id].zone == z:
			pts.append(["territory " + id, Data.TERRITORIES[id].pos, true])
	for c in Loot.CAMPS.get(z, []):
		pts.append(["camp " + str(c.id), c.pos, false])
	pts.append(["spawn", Data.ZONES[z].spawn, true])
	if World.VENDOR_SPOTS.has(z):
		pts.append(["vendor", World.VENDOR_SPOTS[z][0], true])
	if World.QUARTERMASTERS.has(z):
		pts.append(["quartermaster", World.QUARTERMASTERS[z][0], true])
	for qid in Data.QUESTS:
		var q: Dictionary = Data.QUESTS[qid]
		if Data.QUEST_GIVERS[q.giver].zone != z:
			continue
		for o in q.obj:
			if o.type == "reach":
				pts.append(["quest spot " + qid, o.pos, false])
	return pts

func _audit(z: String) -> void:
	var w := World.new()
	add_child(w)
	w.build(z)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := w.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.2
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	var bad := 0
	for p in _points(z):
		var nm: String = p[0]
		var v: Vector3 = p[1]
		if nm == "quartermaster":
			v += Vector3(0, 0, 1.4)   # you stand at the counter, not in it
		var solid: bool = p[2]   # people stand here: must not be inside geometry
		var why := _why(w, space, q, v, solid)
		if why != "":
			bad += 1
			fails += 1
			var fix := ""
			for r in range(1, 14):
				for k in 16:
					var a := k * TAU / 16.0
					var c := v + Vector3(cos(a) * r, 0, sin(a) * r)
					if _why(w, space, q, c, true) == "":
						fix = "  -> try (%d, %d)" % [roundi(c.x), roundi(c.z)]
						break
				if fix != "":
					break
			printerr("FAIL: %s  %s at (%.0f, %.0f): %s%s" % [z, nm, v.x, v.z, why, fix])
	print("%s: %d points checked, %d bad" % [z, _points(z).size(), bad])
	w.queue_free()
	await get_tree().process_frame

func _why(w: World, space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D, v: Vector3, solid: bool) -> String:
		var gy := w.ground_y(v.x, v.z)
		var why := ""
		if absf(v.x) > 93.0 or absf(v.z) > 93.0:
			why = "outside the map"
		elif gy < w.water_level() - 0.25:
			why = "under water (ground %.1f, water %.1f)" % [gy, w.water_level()]
		else:
			var slope := maxf(absf(w.ground_y(v.x + 1.0, v.z) - w.ground_y(v.x - 1.0, v.z)), absf(w.ground_y(v.x, v.z + 1.0) - w.ground_y(v.x, v.z - 1.0))) / 2.0
			if slope > 0.9:
				why = "on a cliff face (slope %.2f)" % slope
			elif solid:
				q.transform = Transform3D(Basis(), Vector3(v.x, gy + 0.95, v.z))
				var hits := space.intersect_shape(q, 4)
				if not hits.is_empty():
					why = "inside geometry"
		return why
