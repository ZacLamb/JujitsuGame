class_name PoseSmoother
extends SkeletonModifier3D
## Runs after the animation player / BodyRig retargeting and eases every bone toward the pose it was
## given this frame (critically-damped style exponential smoothing). Removes the snaps between
## animation clips and fight poses, keyframe corners and reaction bumps, at ~50 ms of lag.

var rate := 16.0          # higher = tighter follow
var _rot: Array[Quaternion] = []
var _pos: Array[Vector3] = []
var _primed := false

## Forget the history (next frame snaps to the given pose): call after teleports / scene changes.
func reset() -> void:
	_primed = false

func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var n := sk.get_bone_count()
	if not _primed or _rot.size() != n:
		_rot.resize(n)
		_pos.resize(n)
		for i in n:
			_rot[i] = sk.get_bone_pose_rotation(i)
			_pos[i] = sk.get_bone_pose_position(i)
		_primed = true
		return
	var t := 1.0 - exp(-rate * clampf(delta, 0.0, 0.1))
	for i in n:
		var q := _rot[i].slerp(sk.get_bone_pose_rotation(i), t)
		var p := _pos[i].lerp(sk.get_bone_pose_position(i), t)
		_rot[i] = q
		_pos[i] = p
		sk.set_bone_pose_rotation(i, q)
		sk.set_bone_pose_position(i, p)
