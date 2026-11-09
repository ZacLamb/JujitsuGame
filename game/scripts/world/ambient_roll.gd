class_name AmbientRoll
extends Node3D
## Two locals rolling on a mat: they flow through positions (guard, half, side, mount, back),
## sweep and pass, slap hands and reset. Pure ambience: the world trains around you.

const FLOW := [["guard", "pass"], ["half", "pass"], ["side", "advance"], ["mount", "back"], ["back", "escape"], ["guard", "sweep"], ["mount", "escape"], ["half", "sweep"], ["side", "escape"]]
var a: BodyRig
var b: BodyRig
var _i := 0
var _t := 0.0
var _a_top := true

func setup(gi_a: Color, gi_b: Color, skin_a: float, skin_b: float, belt_a: Color, belt_b: Color) -> AmbientRoll:
	a = BodyRig.new()
	add_child(a)
	a.setup(gi_a, belt_a, UiKit.skin_tone(skin_a), Color(0.12, 0.08, 0.05))
	b = BodyRig.new()
	add_child(b)
	b.setup(gi_b, belt_b, UiKit.skin_tone(skin_b), Color(0.12, 0.08, 0.05))
	_i = randi() % FLOW.size()
	_t = randf_range(0.2, 2.0)
	return self

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = randf_range(2.8, 4.5)
	if not is_visible_in_tree():
		return
	var step: Array = FLOW[_i % FLOW.size()]
	_i += 1
	# a sweep or an escape flips who's on top
	if str(step[1]) in ["sweep", "escape"] and _i % 2 == 0:
		_a_top = not _a_top
	var pair := RollPoses.get_pair(str(step[0]))
	var top := a if _a_top else b
	var bot := b if _a_top else a
	var fl := RollPoses.flavor(str(step[1]))
	for side in [["top", top], ["bottom", bot]]:
		var rig: BodyRig = side[1]
		var pose: Dictionary = pair[side[0]][0]
		var xf: Transform3D = pair[side[0]][1]
		var partner: BodyRig = bot if rig == top else top
		var mid_p := BodyRig.lerp_pose(rig.current_pose(), pose, 0.5)
		var mid_r: Transform3D = rig.current_root().interpolate_with(xf, 0.5)
		var res := RollPoses.apply_flavor(mid_p, mid_r, fl.actor if rig == top else fl.other, partner.position - rig.position)
		rig.action([[res[0], res[1], 0.5], [pose, xf, 0.7]], true)
