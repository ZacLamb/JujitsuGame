class_name Npc
extends Node3D
## A fighter you can challenge, or a wandering townsperson.

var opp_id := ""
var display_name := ""
var rig: BodyRig
var tag: Label3D
var wander := false
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _wait := 0.0
var _player: Node3D
var world  # World, for ground height
var rng := RandomNumberGenerator.new()

func setup_fighter(id: String, w) -> Npc:
	opp_id = id
	world = w
	var o: Dictionary = Data.OPPONENTS[id]
	display_name = o.name
	rig = BodyRig.new()
	add_child(rig)
	rig.setup(o.gi, Data.BELTS[Data.belt_of(int(o.rank))].color, o.skin, Color(0.12, 0.08, 0.05), -1, o.get("body", "male"))
	tag = Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = false
	tag.font_size = 48
	tag.pixel_size = 0.0115
	tag.outline_size = 14
	tag.position = Vector3(0, 2.25, 0)
	add_child(tag)
	refresh_tag()
	return self

func setup_villager(seed_v: int, w, area_center: Vector3) -> Npc:
	world = w
	wander = true
	rng.seed = seed_v
	_home = area_center
	rig = BodyRig.new()
	add_child(rig)
	var shirts := [Color(0.9, 0.35, 0.3), Color(0.25, 0.55, 0.85), Color(0.95, 0.8, 0.3), Color(0.35, 0.7, 0.4), Color(0.85, 0.85, 0.85), Color(0.7, 0.4, 0.75)]
	var skin := UiKit.skin_tone(rng.randf())
	var shirt: Color = shirts[rng.randi() % shirts.size()]
	rig.setup(shirt, shirt.darkened(0.4), skin, Color(rng.randf_range(0.05, 0.4), 0.06, 0.03), -1, "", true)
	_pick_target()
	return self

func refresh_tag() -> void:
	if tag == null:
		return
	var o: Dictionary = Data.OPPONENTS[opp_id]
	var mark := "  (beaten)" if Game.beaten(opp_id) else ""
	var lv := Data.display_level(float(o.level))
	var plv := Game.player_level()
	var lv_txt := "Lv ??" if lv - plv >= 10 else "Lv %d" % lv
	if o.get("boss", false):
		lv_txt += " Boss"
	tag.text = "%s%s\n%s · %s" % [o.name, mark, lv_txt, Data.BELTS[Data.belt_of(int(o.rank))].name + " Belt"]
	tag.modulate = Data.con_color(lv, plv)

func set_player(p: Node3D) -> void:
	_player = p

func _pick_target() -> void:
	_target = _home + Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
	_wait = rng.randf_range(1.0, 4.0)

func _process(delta: float) -> void:
	if wander:
		if _wait > 0.0:
			_wait -= delta
			rig.animate_locomotion(delta, 0.0)
			return
		var to := _target - global_position
		to.y = 0
		if to.length() < 0.5:
			_pick_target()
			return
		var step := to.normalized() * 1.6 * delta
		global_position += step
		global_position.y = world.ground_y(global_position.x, global_position.z)
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-to.x, -to.z), clampf(delta * 6.0, 0, 1))
		rig.animate_locomotion(delta, 0.3)
		return
	# fighters idle and face the player when near
	var speed := 0.0
	if _player and global_position.distance_to(_player.global_position) < 8.0:
		var to2 := _player.global_position - global_position
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-to2.x, -to2.z), clampf(delta * 5.0, 0, 1))
	rig.animate_locomotion(delta, speed)
