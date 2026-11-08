extends Node3D
## Renders the generated fighter model (gi and no-gi loadouts) for visual QA.
const COLS := {"Body": Color(0.86, 0.66, 0.5), "Face": Color(0.1, 0.07, 0.06), "Jacket": Color(0.96, 0.96, 0.94),
	"JacketTrim": Color(0.75, 0.76, 0.8), "Pants": Color(0.96, 0.96, 0.94), "Belt": Color(0.15, 0.35, 0.85),
	"Rash": Color(0.1, 0.1, 0.12), "Spats": Color(0.1, 0.1, 0.12), "KneeSleeves": Color(0.15, 0.15, 0.17),
	"EarGuards": Color(0.85, 0.2, 0.2), "Headband": Color(0.95, 0.75, 0.2), "Tape": Color(0.95, 0.95, 0.9)}
func _dress(inst: Node, show: Array, hair: String) -> void:
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var n: String = mi.name
		var vis: bool = n in show or n == "Hair_" + hair
		mi.visible = vis
		var c: Color = COLS.get(n, Color(0.3, 0.2, 0.12))
		mi.material_override = BodyRig._mat(c)
func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.4, 0.45)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.64, 0.7)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var body: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "male"
	var sc: PackedScene = load("res://assets/models/worker.glb")
	var parts: PackedScene = load("res://assets/models/fighter_%s.scn" % body)
	var looks := [
		[["Body", "Face"], "short", PI],
		[["Body", "Face", "Jacket", "JacketTrim", "Pants", "Belt", "Rash"], "curly", PI],
		[["Body", "Face", "Rash", "Spats", "KneeSleeves", "EarGuards", "Tape"], "buzz", PI + 0.5],
		[["Body", "Face", "Jacket", "JacketTrim", "Pants", "Belt", "Headband"], "ponytail", PI * 0.25],
	]
	for i in looks.size():
		var inst: Node3D = sc.instantiate()
		inst.rotation.y = PI + float(looks[i][2])
		inst.position = Vector3((i - 1.5) * 1.6, 0, 0)
		inst.scale = Vector3.ONE * 0.45
		add_child(inst)
		var base: MeshInstance3D = inst.find_children("BaseHuman", "MeshInstance3D", true, false)[0]
		var pr: Node3D = parts.instantiate()
		for c in pr.get_children():
			pr.remove_child(c)
			base.get_parent().add_child(c)
			(c as MeshInstance3D).skin = base.skin
			(c as MeshInstance3D).skeleton = (c as MeshInstance3D).get_path_to(base.get_node(base.skeleton))
		base.queue_free()
		for ico in inst.find_children("Icosphere", "MeshInstance3D", true, false):
			ico.queue_free()
		_dress(inst, looks[i][0], looks[i][1])
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		for a in ap.get_animation_list():
			if str(a).ends_with("Idle"):
				ap.play(a)
		var sk: Node3D = inst
		var aabb_h := 0.0
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			aabb_h = maxf(aabb_h, (mi as MeshInstance3D).get_aabb().size.y)
		print("model height (local) ", aabb_h, " scale ", inst.scale)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 32
	cam.position = Vector3(0, 1.0, 9.5)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.make_current()
	for f in 20: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/model_%s.png" % body)
	cam.fov = 18
	cam.position = Vector3(-0.8, 1.25, 4.0)
	cam.look_at(Vector3(-0.8, 1.15, 0))
	for f in 5: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/model_%s_face.png" % body)
	get_tree().quit()
