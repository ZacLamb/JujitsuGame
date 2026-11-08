extends SceneTree
## Builds res://assets/models/meshy_<name>.scn from tools/meshybuild output: one textured "Body"
## MeshInstance3D with its own Skin. The mesh stays in its A-pose; each bind pose maps the mesh's
## own joint (head + bone direction, stretched to the worker's bone length) onto the worker
## skeleton's bone, so every existing animation and the BodyRig retargeting drive it unchanged.
## Run: godot --headless -s tools/import_meshy.gd -- meshy_male
const WORKER_CHILD := {"Hips": "Abdomen", "Abdomen": "Torso", "Torso": "Neck", "Neck": "Head",
	"Shoulder": "UpperArm", "UpperArm": "LowerArm", "LowerArm": "Palm", "Palm": "Fingers",
	"UpperLeg": "LowerLeg", "LowerLeg": "Foot"}

func _init():
	var nm := "meshy_male"
	if OS.get_cmdline_user_args().size() > 0:
		nm = OS.get_cmdline_user_args()[0]
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("/home/claude/meshybuild/%s.json" % nm))
	var inst: Node3D = (load("res://assets/models/worker.glb") as PackedScene).instantiate()
	get_root().add_child(inst)
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var wmi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
	var wskin: Skin = wmi.skin
	var bind_of := {}   # bone name -> bind index
	var wh := {}        # bone name -> worker head (skin space)
	for i in wskin.get_bind_count():
		var bn := wskin.get_bind_name(i)
		if bn == "":
			bn = sk.get_bone_name(wskin.get_bind_bone(i))
		bind_of[bn] = i
		wh[bn] = wskin.get_bind_pose(i).affine_inverse().origin
	var J: Dictionary = d.joints
	var mh := func(n: String) -> Vector3:
		var a: Array = J[n]
		return Vector3(a[0], a[1], a[2])
	var skin := wskin.duplicate() as Skin
	var fmap := {}   # bind index -> mesh-to-worker transform
	for bnv in bind_of:
		var bn := str(bnv)
		if not J.has(bn):
			continue
		var base: String = bn.get_slice(".", 0)
		var side: String = ("." + bn.get_slice(".", 1)) if bn.contains(".") else ""
		var f := Transform3D.IDENTITY
		var m0: Vector3 = mh.call(bn)
		var w0: Vector3 = wh[bn]
		var ch := str(WORKER_CHILD.get(base, ""))
		if base in ["MiddleHand", "Fingers", "Thumb1", "Thumb2"]:
			ch = ""
		if ch != "" and J.has(ch + side) and wh.has(ch + side):
			var md: Vector3 = mh.call(ch + side) - m0
			var wd: Vector3 = wh[ch + side] - w0
			var rot := Basis(Quaternion(md.normalized(), wd.normalized()))
			# stretch along the bone so joint ends meet (thickness unchanged)
			var k := wd.length() / maxf(md.length(), 1e-4)
			var ax := md.normalized()
			var st := Basis.IDENTITY
			for c in 3:
				var e := Vector3.ZERO
				e[c] = 1.0
				st[c] = e + ax * ax.dot(e) * (k - 1.0)
			f = Transform3D(rot * st, w0 - (rot * st) * m0)
		else:
			# hands / fingers / head / feet: follow the parent bone's rotation rigidly
			var par := ""
			if base in ["Fingers", "MiddleHand", "Thumb1", "Thumb2"]:
				par = "LowerArm" + side
			elif base == "Palm":
				par = "LowerArm" + side
			elif base == "Foot":
				par = "LowerLeg" + side
			var rot := Basis.IDENTITY
			if par != "":
				var pc: String = "Palm" + side if par.begins_with("LowerArm") else "Foot" + side
				var md: Vector3 = mh.call(pc) - mh.call(par)
				var wd: Vector3 = wh[pc] - wh[par]
				rot = Basis(Quaternion(md.normalized(), wd.normalized()))
			f = Transform3D(rot, w0 - rot * m0)
		skin.set_bind_pose(bind_of[bn], wskin.get_bind_pose(bind_of[bn]) * f)
		fmap[bind_of[bn]] = f
	# mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	for a in d.v:
		v.append(Vector3(a[0], a[1], a[2]))
	for a in d.n:
		n.append(Vector3(a[0], a[1], a[2]))
	for a in d.uv:
		uv.append(Vector2(a[0], a[1]))
	for a in d.get("c", []):
		col.append(Color(a[0], a[1], a[2], 1.0))
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	for k in d.b.size():
		for j in 4:
			var bn: String = d.b[k][j]
			bones.append(int(bind_of.get(bn, bind_of["Hips"])))
			wts.append(float(d.w[k][j]))
	# worker-space rest position per vertex (CUSTOM0.xyz) for the gear pattern shader, plus how much
	# the vertex belongs to the legs (CUSTOM0.w) so pants can take their own colour
	var leg_ids := []
	for ln in ["UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R", "Foot.L", "Foot.R"]:
		leg_ids.append(bind_of[ln])
	var cust := PackedFloat32Array()
	for k in v.size():
		var rp := Vector3.ZERO
		var legw := 0.0
		for j in 4:
			var bi := bones[k * 4 + j]
			var w := wts[k * 4 + j]
			var f: Transform3D = fmap.get(bi, Transform3D.IDENTITY)
			rp += (f * v[k]) * w
			if bi in leg_ids:
				legw += w
		cust.append(rp.x); cust.append(rp.y); cust.append(rp.z); cust.append(legw)
	arr[Mesh.ARRAY_CUSTOM0] = cust

	var idx := PackedInt32Array()
	for t in d.i:
		idx.append(int(t[0])); idx.append(int(t[2])); idx.append(int(t[1]))   # Godot winds clockwise
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	if col.size() == v.size():
		arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = wts
	arr[Mesh.ARRAY_INDEX] = idx
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, null, "Body",
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	im.generate_lods(25.0, 60.0, [])
	var root := Node3D.new()
	root.name = "Fighter"
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = im.get_mesh()
	mi.skin = skin
	mi.set_meta("own_skin", true)
	mi.set_meta("albedo", "res://assets/models/%s_albedo.png" % nm)
	var sr: Array = d.get("skin_ref", [0.6, 0.45, 0.4])
	var gr: Array = d.get("gi_ref", [0.85, 0.85, 0.85])
	mi.set_meta("skin_ref", Color(sr[0], sr[1], sr[2]))
	mi.set_meta("gi_ref", Color(gr[0], gr[1], gr[2]))
	root.add_child(mi)
	mi.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	var path := "res://assets/models/%s.scn" % nm
	print("save ", path, " -> ", ResourceSaver.save(ps, path, ResourceSaver.FLAG_COMPRESS), " verts ", v.size())
	quit()
