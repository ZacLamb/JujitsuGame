extends Node3D
## Visual QA: the five classes in their starter kits (front + back), then in their tier sets.
func _ready() -> void:
	Game.test_mode = true
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
	pm.size = Vector2(30, 30)
	floor_.mesh = pm
	floor_.material_override = BodyRig._mat(Color(0.35, 0.5, 0.75))
	add_child(floor_)
	var tier := OS.get_cmdline_user_args().has("tier")
	var rigs: Array = []
	for i in Rpg.STYLE_ORDER.size():
		var st: String = Rpg.STYLE_ORDER[i]
		Game.style = ""
		Game.inventory = {}
		Game.equipped = {}
		for id in Gear.STARTER:
			Game.inventory[id] = true
		Game.equipped = {"jacket": "standard_gi", "pants": "standard_gi_pants", "rash": "rash_white", "spats": "spats_black"}
		Game.kit = "gi"
		Game.style = st
		Game.give_class_kit(true)
		if tier:
			for pid in Gear.SETS[Gear.CLASS_SET[st]].pieces:
				Game.inventory[pid] = true
				Game.equipped[Gear.ITEMS[pid].slot] = pid
		Game.body = "female" if i == 3 else "male"
		var rig := BodyRig.new()
		add_child(rig)
		Game.dress(rig)
		rig.setup(Game.gi_color(), Data.BELTS[2].color, UiKit.skin_tone(0.15 + 0.17 * i), Color(0.1, 0.07, 0.05), i % 4, Game.body)
		rig.position = Vector3((i - 2) * 1.25, 0, 0)
		rig.rotation.y = PI
		rigs.append(rig)
		var l := Label3D.new()
		l.text = Rpg.class_name_of(st)
		l.modulate = Rpg.class_color(st)
		l.font_size = 48
		l.pixel_size = 0.004
		l.outline_size = 10
		l.position = Vector3((i - 2) * 1.25, 2.15, 0)
		add_child(l)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 34
	cam.position = Vector3(0, 1.2, 9.0)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.make_current()
	for f in 30: await get_tree().process_frame
	var tag := "tier" if tier else "kit"
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/classes_%s_front.png" % tag)
	for r in rigs:
		(r as Node3D).rotation.y = 0.0
	for f in 10: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/classes_%s_back.png" % tag)
	get_tree().quit()
