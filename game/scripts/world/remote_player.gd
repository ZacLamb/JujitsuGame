class_name RemotePlayer
extends Node3D
## Another logged-in player in your zone: dressed in their gear, class crest on the back, nameplate
## in their class colour, a speech bubble when they /say. Positions arrive 8/s and are smoothed.

var net_id := 0
var char := {}
var rig: BodyRig
var plate: Label3D
var bubble: Label3D
var _target := Vector3.ZERO
var _vel := Vector3.ZERO
var _yaw := 0.0
var _speed := 0.0
var _air := false
var _combat := false
var _bubble_t := 0.0
var _got := false

func setup(id: int, d: Dictionary) -> RemotePlayer:
	net_id = id
	name = "Remote%d" % id
	plate = Label3D.new()
	plate.font = Wow.title_font()
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.no_depth_test = true
	Npc._plate(plate)
	plate.visibility_range_end = 45.0
	plate.position = Vector3(0, 2.25, 0)
	add_child(plate)
	bubble = Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	Npc._plate(bubble)
	bubble.visibility_range_end = 45.0
	bubble.font_size = 26
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.width = 520
	bubble.modulate = Color(1, 1, 0.92)
	bubble.position = Vector3(0, 2.62, 0)
	bubble.visible = false
	add_child(bubble)
	set_char(d.get("char", {}))
	var p := Vector3(float(d.get("x", 0)), float(d.get("y", 0)), float(d.get("z", 0)))
	position = p
	_target = p
	_yaw = float(d.get("yaw", 0))
	return self

func set_char(ch: Dictionary) -> void:
	var same_look := JSON.stringify(ch.get("look", {})) == JSON.stringify(char.get("look", {})) and str(ch.get("body", "")) == str(char.get("body", "")) \
		and float(ch.get("skin", 0)) == float(char.get("skin", -1)) and str(ch.get("head", "")) == str(char.get("head", "-")) and int(ch.get("belt", 0)) == int(char.get("belt", -1)) and rig != null
	char = ch
	refresh_plate()
	if same_look:
		return
	if rig:
		rig.queue_free()
	rig = BodyRig.new()
	rig.bulk = 1.0
	add_child(rig)
	rig.look = Net.dec(ch.get("look", {}))
	rig.build = Rpg.class_build(str(ch.get("style", "")))
	rig.crest = str(ch.get("style", ""))
	rig.head_id = str(ch.get("head", "classic"))
	var belt := clampi(int(ch.get("belt", 0)), 0, Data.BELTS.size() - 1)
	var gi := Color.html(str(ch.get("gi", "f2f2ee"))) if Color.html_is_valid(str(ch.get("gi", ""))) else Color(0.95, 0.95, 0.93)
	rig.setup(gi, Data.BELTS[belt].color, UiKit.skin_tone(float(ch.get("skin", 0.35))), Color(0.55, 0.36, 0.18), 0, str(ch.get("body", "male")))
	rig.rotation.y = _yaw

func net_state(x: float, y: float, z: float, yaw: float, s: float, air: bool, combat: bool) -> void:
	var t := Vector3(x, y, z)
	if not _got or position.distance_to(t) > 12.0:
		position = t   # first update or a teleport: snap
	_vel = (t - _target) / 0.125
	_target = t
	_yaw = yaw
	_speed = s
	_air = air
	_got = true
	if _combat != combat:
		_combat = combat
		if rig:
			rig.combat_ready = combat
		refresh_plate()

func refresh_plate() -> void:
	var st := str(char.get("style", ""))
	var cls := Rpg.class_name_of(st)
	var fid := str(char.get("faction", "brasil"))
	var fname := str(Origins.faction(fid).name)
	plate.text = Tx.f("%s%s\n<Level %d%s · %s>", ["⚔ " if _combat else "", str(char.get("name", "?")), int(char.get("level", 1)), (" " + cls) if cls != "" else "", fname])
	# WoW-style: your own faction reads friendly blue, the other side reads red
	plate.modulate = Color(0.55, 0.8, 1.0) if fid == Game.faction() else Color(1.0, 0.45, 0.4)

func say(text: String) -> void:
	bubble.text = text
	bubble.visible = true
	_bubble_t = clampf(4.0 + text.length() * 0.06, 4.0, 10.0)

func _process(delta: float) -> void:
	# chase the latest position (extrapolate a little so movement doesn't stutter between updates)
	var aim := _target + _vel * 0.06
	position = position.lerp(aim, clampf(delta * 10.0, 0.0, 1.0))
	if rig:
		rig.rotation.y = lerp_angle(rig.rotation.y, _yaw, clampf(delta * 12.0, 0.0, 1.0))
		rig.animate_locomotion(delta, _speed, _air)
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			bubble.visible = false
