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

## WoW-style nameplate: the same size on screen at any distance, so it never fills the view
## when the camera is close.
const PLATE_PX := 0.0007
static func _plate(l: Label3D) -> void:
	l.fixed_size = true
	l.visibility_range_end = 26.0        # only nearby plates, like WoW
	l.visibility_range_end_margin = 4.0
	l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	l.font_size = 30
	l.pixel_size = PLATE_PX
	l.outline_size = 8
	l.line_spacing = -6.0

func setup_fighter(id: String, w) -> Npc:
	opp_id = id
	world = w
	var o: Dictionary = Data.OPPONENTS[id]
	display_name = o.name
	rig = BodyRig.new()
	add_child(rig)
	rig.setup(o.gi, Data.BELTS[Data.belt_of(int(o.rank))].color, o.skin, Color(0.12, 0.08, 0.05), -1, o.get("body", "male"))
	tag = Label3D.new()
	tag.font = Wow.title_font()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	_plate(tag)
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

# ------------------------------------------------------------ mobs
## A roaming mob: wanders its camp; aggressive ones walk up and challenge you when you get close.
var mob := {}
var in_combat := false   # WorldCombat drives movement / facing while true
var camp_radius := 8.0
const AGGRO_RANGE := 6.5   # metres; camps are spaced so you can pull one at a time
var _chasing := false
var _queue_pos := Vector3.INF   # waiting at the edge of your fight for the winner
var _queue_look := Vector3.ZERO
signal engaged(npc: Npc)

func queue_at(pos: Vector3, look: Vector3) -> void:
	_queue_pos = pos
	_queue_look = look
	_chasing = false
	if tag:
		tag.visible = false   # the fight HUD lists who's waiting

func unqueue() -> void:
	_queue_pos = Vector3.INF
	_chasing = false
	_target = _home
	if tag:
		tag.visible = true

func setup_mob(m: Dictionary, w, center: Vector3, radius: float) -> Npc:
	mob = m
	world = w
	wander = true
	camp_radius = radius
	rng.randomize()
	_home = center
	display_name = str(m.name)
	rig = BodyRig.new()
	add_child(rig)
	if m.get("rare", false) or m.get("elite", false):
		rig.bulk = 1.14   # elites and rares are built heavier
	rig.setup(m.gi, Data.BELTS[Data.belt_of(int(m.rank))].color, m.skin, Color(0.12, 0.08, 0.05), -1, str(m.get("body", "male")))
	tag = Label3D.new()
	tag.font = Wow.title_font()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	_plate(tag)
	tag.position = Vector3(0, 2.25, 0)
	add_child(tag)
	refresh_mob_tag()
	_pick_target()
	return self

func refresh_mob_tag() -> void:
	var lv := Data.display_level(float(mob.level))
	var kind := ""
	if mob.get("rare", false):
		kind = "  ★ Rare Elite"
	elif mob.get("elite", false):
		kind = "  Elite"
	if mob.get("revenge", false):
		kind += "  ⚔ Revenge"
	var tr := str(mob.get("trait", ""))
	if tr != "":
		kind += "  <%s>" % str(Loot.TRAITS.get(tr, tr))
	tag.text = "%s\nLv %d%s" % [mob.name, lv, kind]
	tag.modulate = Data.con_color(lv, Game.player_level())
	if mob.get("rare", false):
		tag.outline_modulate = Color(0.5, 0.5, 0.6)

func _mob_process(delta: float) -> bool:
	if mob.is_empty() or _player == null:
		return false
	if _queue_pos != Vector3.INF:
		var tq := _queue_pos - global_position
		tq.y = 0
		if tq.length() > 0.4:
			global_position += tq.normalized() * minf(3.0 * delta, tq.length())
			global_position.y = world.ground_y(global_position.x, global_position.z)
			rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-tq.x, -tq.z), clampf(delta * 8.0, 0, 1))
			rig.animate_locomotion(delta, 0.5)
		else:
			var lk := _queue_look - global_position
			rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-lk.x, -lk.z), clampf(delta * 4.0, 0, 1))
			rig.animate_locomotion(delta, 0.0)
		return true
	var to_p: Vector3 = _player.global_position - global_position
	to_p.y = 0
	var d := to_p.length()
	var home_d := (global_position - _home).length()
	var can_aggro: bool = mob.get("aggro", false) and world.aggro_grace <= 0.0 and Time.get_ticks_msec() >= int(get_meta("no_aggro_until", 0)) and Data.display_level(float(mob.level)) >= Game.player_level() - 6
	if can_aggro and d < AGGRO_RANGE and home_d < camp_radius + 10.0:
		_chasing = true
	elif _chasing and (d > 14.0 or home_d > camp_radius + 12.0 or world.aggro_grace > 0.0):
		_chasing = false
		_target = _home
	if not _chasing:
		return false
	if d < 1.9:
		_chasing = false
		engaged.emit(self)
		return true
	global_position += to_p.normalized() * 3.4 * delta
	global_position.y = world.ground_y(global_position.x, global_position.z)
	rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-to_p.x, -to_p.z), clampf(delta * 8.0, 0, 1))
	rig.animate_locomotion(delta, 0.7)
	return true

# ------------------------------------------------------------ quest givers
const FEMALE_GIVERS := ["lurdes", "rosa", "lia", "ana", "cristal", "nanda", "jaci", "dandara"]
var giver_id := ""
var marker: Label3D

func setup_quest_giver(id: String, w) -> Npc:
	giver_id = id
	world = w
	var g: Dictionary = Data.QUEST_GIVERS[id]
	display_name = g.name
	rig = BodyRig.new()
	add_child(rig)
	var shirt: Color = g.shirt
	rig.setup(shirt, shirt.darkened(0.4), UiKit.skin_tone(float(g.skin)), Color(0.15, 0.09, 0.05), -1, "female" if id in FEMALE_GIVERS else "", true)
	tag = Label3D.new()
	tag.font = Wow.title_font()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	_plate(tag)
	tag.position = Vector3(0, 2.2, 0)
	tag.text = g.name
	tag.modulate = Color(0.85, 1.0, 0.85)
	add_child(tag)
	marker = Label3D.new()
	marker.font = Wow.title_font()
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.fixed_size = true
	marker.font_size = 80
	marker.pixel_size = 0.0009
	marker.outline_size = 14
	marker.outline_modulate = Color(0.25, 0.15, 0.0)
	marker.position = Vector3(0, 3.1, 0)
	if UiKit.head_font():
		marker.font = UiKit.head_font()
	add_child(marker)
	refresh_marker()
	return self

func refresh_marker() -> void:
	if marker == null:
		return
	var m := Game.giver_marker(giver_id)
	marker.text = "?" if m == "…" else m
	marker.modulate = Color(0.6, 0.6, 0.6) if m == "…" else Color(1.0, 0.85, 0.15)
	marker.visible = m != ""

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
	var r := camp_radius if not mob.is_empty() else 14.0
	_target = _home + Vector3(rng.randf_range(-r, r), 0, rng.randf_range(-r, r))
	_wait = rng.randf_range(1.0, 4.0)

func _process(delta: float) -> void:
	if tag:
		tag.visible = not in_combat   # the target frame names who you're fighting; no stacked plates
	if in_combat:
		return
	if _mob_process(delta):
		return
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
	if marker:
		marker.position.y = 3.1 + sin(Time.get_ticks_msec() * 0.004) * 0.12
	# fighters and quest givers idle and face the player when near
	var speed := 0.0
	if _player and global_position.distance_to(_player.global_position) < 8.0:
		var to2 := _player.global_position - global_position
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-to2.x, -to2.z), clampf(delta * 5.0, 0, 1))
	rig.animate_locomotion(delta, speed)
