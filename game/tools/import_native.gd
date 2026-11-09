extends SceneTree
## Meshy-rigged character (GLB with its own Mixamo skeleton, skin weights and animation clips) ->
## res://assets/models/native/<name>.scn for BodyRig's native mode.
##   python3 -I tools/meshynative/prep.py <file.glb> <name>      (textures, mask, reference colours)
##   godot --headless -s tools/import_native.gd -- <file.glb> <name>
## The mesh keeps Meshy's own skinning. Embedded materials are dropped (BodyRig dresses the body with
## the gear shader), each vertex gets CUSTOM0 = rest position + leg weight for gi patterns / pants,
## and the locomotion clips loop.
const LOOPS := ["Idle", "Walking", "Running", "Combat_Stance", "Walk_Fight_Forward", "Walk_Fight_Back", "Walk_Backward"]

func _init():
	var a := OS.get_cmdline_user_args()
	var src: String = a[0]
	var nm: String = a[1]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(src, st) != OK:
		push_error("cannot read " + src)
		quit(1)
		return
	var root: Node3D = doc.generate_scene(st)
	get_root().add_child(root)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/native/%s.json" % nm))
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	# leg weight per vertex (pants colour) + rest position (pattern space)
	var leg := {}
	for b in sk.get_bone_count():
		var bn := sk.get_bone_name(b)
		if bn.contains("UpLeg") or bn.contains("Leg") or bn.contains("Foot") or bn.contains("Toe"):
			leg[b] = true
	var skin := mi.skin
	var bind_bone := []
	for i in skin.get_bind_count():
		var bb := skin.get_bind_bone(i)
		if bb < 0:
			bb = sk.find_bone(skin.get_bind_name(i))
		bind_bone.append(bb)
	var src_mesh := mi.mesh as ArrayMesh
	var out := ArrayMesh.new()
	for s in src_mesh.get_surface_count():
		var arr := src_mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(v.size(), 1)
		var cust := PackedFloat32Array()
		var h: float = float(meta.get("height", 1.7))
		for k in v.size():
			var lw := 0.0
			for j in per:
				var bi := bones[k * per + j]
				if bi < bind_bone.size() and leg.has(bind_bone[bi]):
					lw += wts[k * per + j]
			var rp := v[k] / maxf(h, 0.01) * 1.9
			cust.append(rp.x); cust.append(rp.y); cust.append(rp.z); cust.append(lw)
		arr[Mesh.ARRAY_CUSTOM0] = cust
		var fmt := src_mesh.surface_get_format(s) & ~Mesh.ARRAY_FORMAT_CUSTOM0
		fmt |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	mi.mesh = out
	mi.name = "Body"
	mi.set_meta("albedo", "res://assets/models/native/%s_albedo.png" % nm)
	var sr: Array = meta.skin_ref
	var gr: Array = meta.gi_ref
	mi.set_meta("skin_ref", Color(sr[0], sr[1], sr[2]))
	mi.set_meta("gi_ref", Color(gr[0], gr[1], gr[2]))
	mi.set_meta("native", true)
	# loops
	var names := []
	for an in ap.get_animation_list():
		names.append(str(an))
		var short := str(an).get_slice("|", 1) if str(an).contains("|") else str(an)
		for l in LOOPS:
			if short == l or short.begins_with(l + "_") or (l == "Idle" and short.begins_with("Idle")):
				ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		# in-place: the game moves the character, so drop the hips' horizontal travel (keep the bob/fall)
		var anm := ap.get_animation(an)
		for t in anm.get_track_count():
			if anm.track_get_type(t) == Animation.TYPE_POSITION_3D and str(anm.track_get_path(t)).ends_with("Hips"):
				var k0: Vector3 = anm.track_get_key_value(t, 0)
				for k in anm.track_get_key_count(t):
					var v: Vector3 = anm.track_get_key_value(t, k)
					anm.track_set_key_value(t, k, Vector3(k0.x, v.y, k0.z))
	ap.stop()
	# own everything, then save
	root.get_parent().remove_child(root)
	root.name = "Native"
	for n in root.find_children("*", "", true, false):
		n.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	var path := "res://assets/models/native/%s.scn" % nm
	print("save ", path, " -> ", ResourceSaver.save(ps, path, ResourceSaver.FLAG_COMPRESS), " anims ", names)
	quit()
