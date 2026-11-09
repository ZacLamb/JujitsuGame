extends Node3D
## Meshy-rigged (native) bodies: idle clip, walk, run, an in-world attack pose, and a guard pair.
## xvfb-run -a godot --rendering-driver opengl3 tests/probe_native.tscn -- [gi|nogi] [male|female]
var rigs: Array = []
var t := 0.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var kit: String = args[0] if args.size() > 0 else "nogi"
	var body: String = args[1] if args.size() > 1 else "male"
	var preset: String = args[2] if args.size() > 2 else "classic"
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
	var gis := [Color(0.96, 0.96, 0.94), Color(0.15, 0.3, 0.75), Color(0.1, 0.1, 0.12), Color(0.8, 0.15, 0.15), Color(0.2, 0.6, 0.3)]
	var belts := [0, 2, 4, 3, 1]
	for i in 5:
		var holder := Node3D.new()
		add_child(holder)
		holder.position = Vector3((i - 2) * 1.25, 0, 0)
		var rig := BodyRig.new()
		rig.head_id = preset
		holder.add_child(rig)
		if kit == "nogi":
			rig.look = {"kit": "nogi", "rash": {"color": gis[i]}, "spats": {"color": gis[i]}}
		rig.setup(gis[i], Data.BELTS[belts[i]].color, UiKit.skin_tone([0.05, 0.5, 0.95, 0.3, 0.7][i]), Color(0.1, 0.07, 0.05), 0, body)
		rig.rotation.y = PI if i != 3 else 0.0
		rigs.append(rig)
	print("native=", rigs[0].native, " clips=", rigs[0]._anim_names.keys(), " bones ok=", rigs[0]._bones.values().filter(func(b): return b < 0).size(), " missing")
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 34
	cam.position = Vector3(0, 1.1, 8.5)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.make_current()
	for f in 50: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/native_%s_%s_%s.png" % [kit, body, preset])
	# grappling: rig 4 takes an in-world attack pose (pose system -> retarget onto the Mixamo bones)
	rigs[4].action(CombatAnim.attack("sub", rigs[4].rotation.y), true)
	print("knockdown clip: ", rigs[0].action_clip("KnockDown", true))
	await get_tree().create_timer(2.3).timeout
	print("kd anim=", rigs[0].anim.current_animation, " pos=", rigs[0].anim.current_animation_position, " playing=", rigs[0].anim.is_playing(), " mode=", rigs[0]._anim_mode, " lod=", rigs[0]._lod)
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/native_%s_%s_pose.png" % [kit, body])
	# get up: pose frames take over from the lying clip with a crossfade
	rigs[0].release(CombatAnim.getup(rigs[0].rotation.y))
	for f in 8: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/native_%s_%s_xfade.png" % [kit, body])
	for f in 50: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/native_%s_%s_pose.png" % [kit, body])
	cam.fov = 16
	cam.position = Vector3(-1.25, 1.35, 5.0)
	cam.look_at(Vector3(-1.25, 1.25, 0))
	for f in 5: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/native_%s_%s_face.png" % [kit, body])
	get_tree().quit()

func _process(d: float) -> void:
	t += d
	if rigs.size() < 5:
		return
	rigs[1].combat_ready = true
	rigs[1].animate_locomotion(d, 0.35, false)
	rigs[2].move_back = true
	rigs[2].animate_locomotion(d, 0.3, false)
	rigs[3].combat_ready = true
	rigs[3].animate_locomotion(d, 0.0, false)
