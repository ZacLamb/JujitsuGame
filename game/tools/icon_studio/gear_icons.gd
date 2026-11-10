extends Node3D
## Gear icon studio: photographs every Gear.ITEMS piece on its own (the sculpted fighter model's
## gear meshes, with the item's real colours and pattern shader) and writes
## res://assets/icons/g_<id>.png (128 px, dark backdrop tinted by rarity).
## Run: godot --rendering-driver opengl3 tools/icon_studio/gear_icons.tscn [-- only=<id>]
const PIECES := {"jacket": ["Jacket", "JacketTrim"], "pants": ["Pants"], "rash": ["Rash"], "spats": ["Spats"],
	"knees": ["KneeSleeves"], "tape": ["Tape"]}
## slot -> [bones to centre on, view size (m), vertical nudge]
const FRAME := {"jacket": [["Torso", "Abdomen", "Hips"], 1.42, 0.25], "rash": [["Torso", "Abdomen", "Hips"], 1.32, 0.25],
	"pants": [["UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R"], 1.45, -0.02],
	"spats": [["UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R"], 1.3, 0.02],
	"knees": [["LowerLeg.L", "LowerLeg.R"], 0.75, 0.04], "tape": [["MiddleHand.L", "MiddleHand.R"], 0.85, 0.0], "head": [["Head"], 0.5, 0.1]}
const OUT := "res://assets/icons/g_%s.png"
const RES := 256

var vp: SubViewport
var cam: Camera3D

func _ready() -> void:
	BodyRig.use_meshy = false
	vp = SubViewport.new()
	vp.size = Vector2i(RES, RES)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, -0.5, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.2, 2.4, 0)
	fill.light_energy = 0.45
	vp.add_child(fill)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	cam.make_current()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("only="):
			only = str(a).substr(5)
	var n := 0
	if only == "bases":
		# white "tint bases" (transparent) for rolled drops: the game tints them with the drop's colour
		var bases := {"jacket": "", "pants": "", "rash": "", "spats": "", "knees": "", "head_Headband": "Headband", "head_EarGuards": "EarGuards"}
		for b in bases:
			var slot: String = str(b).split("_")[0]
			Gear.ITEMS["_tb"] = {"slot": slot, "name": "base", "rarity": "common", "attrs": {}, "look": {"color": Color(0.97, 0.97, 0.97)}, "piece": bases[b]}
			if await _shoot("_tb", "res://assets/icons/tb_%s.png" % b):
				n += 1
		Gear.ITEMS.erase("_tb")
		print("tint bases written: ", n)
		get_tree().quit()
		return
	for id in Gear.ITEMS:
		if only == "dark":
			if (Gear.look(id).get("color", Color.WHITE) as Color).get_luminance() > 0.15:
				continue
		elif only != "" and id != only:
			continue
		if await _shoot(str(id)):
			n += 1
	print("gear icons written: ", n)
	get_tree().quit()

func _shoot(id: String, out_path := "") -> bool:
	var it: Dictionary = Gear.ITEMS[id]
	var slot := str(it.slot)
	if slot == "tape":   # the tape mesh is a mitten-shaped blob on its own: keeps the drawn icon
		return false
	var lk: Dictionary = Gear.look(id).duplicate()
	if id == "standard_gi" or id == "standard_gi_pants":
		lk["color"] = Rpg.GI_COLORS[0]
	var look := {"kit": "nogi" if slot in ["rash", "spats", "knees"] else "gi"}
	look[slot] = lk
	var keep: Array = PIECES.get(slot, [])
	if slot == "head":
		look["head_piece"] = str(it.get("piece", "Headband"))
		keep = [look.head_piece]
	if slot == "jacket":
		look["pants"] = {"color": lk.color}
	var rig := BodyRig.new()
	rig.look = look
	rig.body = "male"
	vp.add_child(rig)
	rig.setup(lk.get("color", Color.WHITE), Color(0.1, 0.1, 0.1), Color(0.86, 0.66, 0.52), Color(0.1, 0.08, 0.06), 4, "male")
	rig.rotation.y = PI + 0.35
	for f in 6:
		await get_tree().process_frame
	var shown := 0
	for pn in rig._pieces:
		var mi: MeshInstance3D = rig._pieces[pn]
		mi.visible = keep.has(str(pn))
		shown += 1 if mi.visible else 0
	for c in rig.find_children("*", "MeshInstance3D", true, false):
		if not rig._pieces.values().has(c):
			(c as MeshInstance3D).visible = false
	if shown == 0:
		print("no mesh for ", id, " slot ", slot, " pieces ", rig._pieces.keys())
		rig.queue_free()
		return false
	# frame the slot's body region from the skeleton
	var fr: Array = FRAME[slot]
	var ctr := Vector3.ZERO
	for bn in fr[0]:
		ctr += _bone(rig, str(bn))
	ctr /= float((fr[0] as Array).size())
	ctr.y += float(fr[2])
	cam.size = float(fr[1])
	cam.position = ctr + Vector3(0, 0.12, 6.0)
	cam.far = 100.0
	cam.look_at(ctr)
	for f in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shot := vp.get_texture().get_image()
	rig.queue_free()
	if out_path != "":   # transparent, no backdrop
		shot.convert(Image.FORMAT_RGBA8)
		shot.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		shot.save_png(ProjectSettings.globalize_path(out_path))
		return true
	var img := _backdrop(Gear.rarity_color(id), (lk.get("color", Color.WHITE) as Color).get_luminance() < 0.15)
	shot.convert(Image.FORMAT_RGBA8)
	img.blend_rect(shot, Rect2i(0, 0, RES, RES), Vector2i.ZERO)
	img.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path(OUT % id))
	return true

## Dark radial backdrop, lit faintly in the rarity colour.
## Dark gear gets a lighter, cooler backdrop so it doesn't vanish.
func _backdrop(rc: Color, dark_item := false) -> Image:
	var img := Image.create(RES, RES, false, Image.FORMAT_RGBA8)
	var c := Vector2(RES, RES) * 0.5
	for y in RES:
		for x in RES:
			var d := clampf(Vector2(x, y).distance_to(c) / (RES * 0.62), 0.0, 1.0)
			var base := Color(0.3, 0.32, 0.36) if dark_item else Color(0.09, 0.08, 0.07)
			var col := base.lerp(rc.darkened(0.4 if dark_item else 0.55), (1.0 - d) * 0.55).darkened(d * 0.5)
			img.set_pixel(x, y, Color(col, 1.0))
	return img

func _bone(rig: BodyRig, bn: String) -> Vector3:
	var sk: Skeleton3D = rig.skel
	var i := sk.find_bone(bn)
	if i < 0:
		var names := []
		for k in sk.get_bone_count(): names.append(sk.get_bone_name(k))
		print("missing bone ", bn, " have ", names)
		return rig.global_position + Vector3(0, 1.0, 0)
	return (sk.global_transform * sk.get_bone_global_pose(i)).origin
