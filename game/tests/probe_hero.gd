extends Node3D
## New hero bodies: idle front/back, a walk frame, gi colours and belt ranks.
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var body: String = args[0] if args.size() > 0 else "hero_gi_m"
	var fem := body.ends_with("_f")
	BodyRig.MESHY["male"] = "res://assets/models/%s.scn" % body
	BodyRig.MESHY["female"] = "res://assets/models/%s.scn" % body
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
	var rows := [[Color(0.96, 0.96, 0.94), 0, 0.2, PI], [Color(0.15, 0.3, 0.75), 2, 0.5, PI], [Color(0.1, 0.1, 0.12), 4, 0.8, PI], [Color(0.96, 0.96, 0.94), 3, 0.35, 0.0], [Color(0.96, 0.96, 0.94), 1, 0.6, PI + 1.3]]
	for i in rows.size():
		var r: Array = rows[i]
		var rig := BodyRig.new()
		add_child(rig)
		rig.head_id = ""
		rig.setup(r[0], Data.BELTS[r[1]].color, UiKit.skin_tone(r[2]), Color(0.1, 0.07, 0.05), 0, "female" if fem else "male")
		rig.position = Vector3((i - 2) * 1.2, 0, 0)
		rig.rotation.y = r[3]
		if i == 4:
			rig.set_meta("walk", true)
		rigs.append(rig)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 34
	cam.position = Vector3(0, 1.1, 8.5)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.make_current()
	for f in 40: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/%s.png" % body)
	cam.fov = 14
	cam.position = Vector3(-1.8, 1.25, 6.0)
	cam.look_at(Vector3(-1.8, 1.15, 0))
	for f in 5: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/%s_face.png" % body)
	if OS.get_cmdline_user_args().has("nohead"):
		for r in rigs:
			for mi in r.find_children("*", "MeshInstance3D", true, false):
				if mi.name == "Head" or mi.get_meta("albedo", "").contains("heads/"):
					mi.visible = false
		cam.fov = 34
		cam.position = Vector3(0, 1.1, 8.5)
		cam.look_at(Vector3(0, 0.95, 0))
		for f in 5: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/home/claude/shots/%s_nohead.png" % body)
	get_tree().quit()
var rigs: Array = []
func _process(d: float) -> void:
	for r in rigs:
		if r.has_meta("walk"):
			r.animate_locomotion(d, 0.5, false)
