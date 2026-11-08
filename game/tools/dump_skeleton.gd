extends SceneTree
## Writes the worker model's skin bind heads (mesh space) + bind indices for the fighter builder.
func _init():
	var inst: Node3D = (load("res://assets/models/worker.glb") as PackedScene).instantiate()
	get_root().add_child(inst)
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
	var skin: Skin = mi.skin
	var out := {}
	for i in skin.get_bind_count():
		var nm := skin.get_bind_name(i)
		if nm == "":
			nm = sk.get_bone_name(skin.get_bind_bone(i))
		var o := skin.get_bind_pose(i).affine_inverse().origin
		out[nm] = [i, o.x, o.y, o.z]
	var f := FileAccess.open("/home/claude/charbuild/worker_skeleton.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	print("binds: ", out.size(), " mesh ", mi.name, " xf ", mi.transform)
	quit()
