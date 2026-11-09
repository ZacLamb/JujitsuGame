extends Node3D
## Cast effect showcase: one fighter per school mid-cast, plus impact / slam / constrict / heal / finisher.
func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.26, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.66)
	e.ambient_light_energy = 0.6
	e.glow_enabled = false
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0)
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	fl.mesh = pm
	fl.material_override = BodyRig._mat(Color(0.18, 0.38, 0.28))
	add_child(fl)
	var types := ["takedown", "sweep", "pass", "sub", "escape", "advice"]
	for i in types.size():
		var rig := BodyRig.new()
		add_child(rig)
		rig.setup(Color(0.96, 0.96, 0.94), Data.BELTS[2].color, UiKit.skin_tone(0.4), Color(0.1, 0.07, 0.05), 0, "male" if i % 2 == 0 else "female")
		rig.position = Vector3((i - 2.5) * 1.9, 0, 0)
		rig.rotation.y = PI
		CastFX.cast_start(rig, {"type": types[i]}, 1.6)
		var l := Label3D.new()
		l.text = types[i].capitalize()
		l.modulate = CastFX.SCHOOL[types[i]]
		l.font_size = 44
		l.pixel_size = 0.004
		l.outline_size = 10
		l.position = rig.position + Vector3(0, 2.3, 0)
		add_child(l)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40
	cam.position = Vector3(0, 3.2, 9.5)
	cam.look_at(Vector3(0, 0.8, 0))
	cam.make_current()
	for f in 50: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/fx_cast.png")
	# landings
	CastFX.impact(self, Vector3(-4.75, 0, 0), {"type": "takedown"}, true)
	CastFX.slam(self, Vector3(-2.85, 0, 0), {"type": "sweep"})
	CastFX.impact(self, Vector3(-0.95, 0, 0), {"type": "pass"})
	CastFX.constrict(self, Vector3(0.95, 0, 0), 1.2)
	CastFX.heal(self, Vector3(4.75, 0, 0))
	CastFX.finisher(self, Vector3(2.85, 0, 0))
	for f in 2: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/fx_land.png")
	get_tree().quit()
