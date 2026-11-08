extends SceneTree
## Builds res://assets/models/fighter_<body>.scn from the charbuild dump: one MeshInstance3D per
## body / hair / gear piece, skinned with the worker model's bind indices, with generated LODs.
## Run: godot --headless -s tools/import_fighter.gd -- male
func _init():
	var body := "male"
	if OS.get_cmdline_user_args().size() > 0:
		body = OS.get_cmdline_user_args()[0]
	var txt := FileAccess.get_file_as_string("/home/claude/charbuild/fighter_%s_godot.json" % body)
	var d: Dictionary = JSON.parse_string(txt)
	var root := Node3D.new()
	root.name = "Fighter"
	for piece in d:
		var p: Dictionary = d[piece]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var fv: Array = p.v
		var fn: Array = p.n
		for k in range(0, fv.size(), 3):
			v.append(Vector3(fv[k], fv[k + 1], fv[k + 2]))
			n.append(Vector3(fn[k], fn[k + 1], fn[k + 2]))
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		# bind-space position for pattern shaders (UV = x,y  UV2.x = z)
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		for q in v:
			uv.append(Vector2(q.x, q.y))
			uv2.append(Vector2(q.z, 0.0))
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_BONES] = PackedInt32Array(p.b)
		arr[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array(p.w)
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array(p.i)
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, null, str(p.mat))
		im.generate_lods(25.0, 60.0, [])
		var mesh := im.get_mesh()
		var mi := MeshInstance3D.new()
		mi.name = piece
		mi.mesh = mesh
		root.add_child(mi)
		mi.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	var path := "res://assets/models/fighter_%s.scn" % body
	print("save ", path, " -> ", ResourceSaver.save(ps, path, ResourceSaver.FLAG_COMPRESS))
	quit()
