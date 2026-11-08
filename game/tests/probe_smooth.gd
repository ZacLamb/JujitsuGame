extends Node
## Measures motion jerk in a live fight: per-frame bone rotation jumps with / without PoseSmoother.
var main: Node
var _prev := {}
func _jumps(rig: BodyRig) -> float:
	var sk := rig.skel
	var mx := 0.0
	for i in sk.get_bone_count():
		var q := sk.get_bone_global_pose(i).basis.get_rotation_quaternion()
		if _prev.has(i):
			mx = maxf(mx, rad_to_deg((_prev[i] as Quaternion).angle_to(q)))
		_prev[i] = q
	return mx
func _run(roll: RollScene, frames: int) -> Array:
	var out := []
	_prev.clear()
	for f in frames:
		if f % 40 == 0:
			roll.sim._land(["double_leg", "scissor_sweep"][(f / 40) % 2], false, 2)
		await get_tree().process_frame
		out.append(_jumps(roll.player_rig))
	out.sort()
	return out
func _ready() -> void:
	Engine.max_fps = 60
	Game.test_mode = true
	Game.reset()
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(8)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	for i in 5: await get_tree().process_frame
	main._start_roll("tiago")
	var roll: RollScene = main.roll
	for i in 10: await get_tree().process_frame
	roll._go_live()
	roll.sim.ai_t = 99.0
	for on in [false, true]:
		roll.player_rig.smoother.active = on
		roll.player_rig.smoother.reset()
		var a: Array = await _run(roll, 320)
		print("SMOOTH ", on, "  p50 %.1f  p95 %.1f  p99 %.1f  max %.1f deg/frame" % [a[a.size() / 2], a[int(a.size() * 0.95)], a[int(a.size() * 0.99)], a[-1]])
	get_tree().quit()
