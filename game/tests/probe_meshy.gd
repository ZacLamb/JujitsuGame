extends Node3D
## Visual QA for the textured Meshy fighter bodies: idle, walking, guard pair, colour variants.
func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.4, 0.45)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.65, 0.68, 0.72)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_ := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_.mesh = pm
	floor_.material_override = BodyRig._mat(Color(0.35, 0.5, 0.75))
	add_child(floor_)
	var rows := [
		["male", Color(0.96, 0.96, 0.94), Color(0.95, 0.95, 0.95), Color(0.86, 0.66, 0.5), 0.0],
		["female", Color(0.96, 0.96, 0.94), Color(0.15, 0.35, 0.85), Color(0.62, 0.42, 0.3), 0.0],
		["male", Color(0.12, 0.2, 0.55), Color(0.5, 0.2, 0.6), Color(0.42, 0.27, 0.18), 1.0],
		["female", Color(0.1, 0.1, 0.12), Color(0.45, 0.25, 0.12), Color(0.95, 0.78, 0.66), 1.0],
		["male", Color(0.96, 0.96, 0.94), Color(0.08, 0.08, 0.08), Color(0.7, 0.5, 0.36), 0.0],
	]
	for i in rows.size():
		var r: Array = rows[i]
		var rig := BodyRig.new()
		add_child(rig)
		if i == 0:
			rig.look = Gear.set_look(Gear.SETS.keys()[0])
		if i == 3:
			rig.look = Gear.set_look(Gear.SETS.keys()[5 % Gear.SETS.size()])
		rig.setup(r[1], r[2], r[3], Color(0.1, 0.07, 0.05), [0, 0, 3, 0, 2][i], r[0])
		rig.position = Vector3((i - 2) * 1.1, 0, 0)
		rig.rotation.y = PI + (0.5 if i == 2 else 0.0)
		rig.set_meta("walk", r[4])
	# a standing grip-fight pair on the right
	var pr := RollPoses.get_pair("guard")
	for side in ["top", "bottom"]:
		var rig := BodyRig.new()
		add_child(rig)
		rig.setup(Color(0.96, 0.96, 0.94) if side == "top" else Color(0.12, 0.2, 0.55), Color(0.1, 0.1, 0.1), Color(0.8, 0.6, 0.45), Color(0.1, 0.07, 0.05), 4, "male" if side == "top" else "female")
		var xf: Transform3D = pr[side][1]
		rig.apply_pose(pr[side][0])
		rig.transform = Transform3D(xf.basis.rotated(Vector3.UP, 0.9), xf.origin + Vector3(4.3, 0, 0.6))
	var cam := Camera3D.new()
	cam.position = Vector3(1.2, 1.6, 5.2)
	cam.look_at(Vector3(1.2, 0.85, 0))
	cam.fov = 50
	add_child(cam)
	await get_tree().create_timer(1.2).timeout
	for c in get_children():
		if c is BodyRig:
			var b: MeshInstance3D = (c as BodyRig)._pieces.get("Body")
			if b:
				print("RIG ", c.body, " pieces ", (c as BodyRig)._pieces.keys(), " meshy ", (c as BodyRig)._meshy, " belt ", (b.material_override as ShaderMaterial).get_shader_parameter("belt"), " col ", c.belt_color, " mat ", b.material_override)
	for c in get_children():
		if c is BodyRig and c.get_meta("walk", 0.0) > 0.0:
			(c as BodyRig).animate_locomotion(0.1, 1.0)
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/meshy_a.png")
	cam.position = Vector3(0, 1.45, 1.6)
	cam.look_at(Vector3(-1.1, 1.45, 0))
	cam.fov = 40
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/meshy_b.png")
	get_tree().quit()
