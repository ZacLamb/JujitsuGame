extends Node3D
## Lines up the western building kit for a look: xvfb-run -a godot --rendering-driver opengl3 tests/probe_westkit.tscn
func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.75, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.8)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.6, 0.55, 0.35)
	ground.material_override = gm
	add_child(ground)
	var kinds := ["tx_longhorn", "br_cow", "br_chalana", "br_voadeira", "br_galpao", "br_casa_morro2", "br_predio_low"]
	var items: Array = []
	var x := 0.0
	var walls := [Color(0.85, 0.75, 0.55), Color(0.6, 0.7, 0.75), Color(0.9, 0.9, 0.86), Color(0.7, 0.2, 0.15)]
	for i in kinds.size():
		var k: String = kinds[i]
		var sz := TownKit.size(k)
		x += sz.x / 2.0 + 3.0
		var wall: Color = walls[i % walls.size()] if k != "tx_barn" else Color(0.65, 0.16, 0.13)
		items.append({"kind": k, "xform": Transform3D(Basis(), Vector3(x, 0, 0)), "wall": wall, "wood": Color(0.45, 0.32, 0.22)})
		x += sz.x / 2.0
	TownKit.build(self, items)
	var cam := Camera3D.new()
	add_child(cam)
	get_window().size = Vector2i(1600, 700)
	var shots := [[Vector3(4, 2.5, 7), Vector3(4, 0.8, 0)], [Vector3(30, 8, 26), Vector3(30, 3, 0)]]
	for i in shots.size():
		cam.position = shots[i][0]
		cam.look_at(shots[i][1])
		for f in 6: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/home/claude/shots/westkit_%d.png" % i)
	print("x total ", x)
	get_tree().quit()
