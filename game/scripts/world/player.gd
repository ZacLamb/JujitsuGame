class_name Player
extends CharacterBody3D
## Third-person explorer. Keyboard/mouse + virtual joystick input. Camera orbit on drag.

const WALK := 5.0
const RUN := 8.5
const JUMP_V := 5.6
const GRAVITY := 13.0

var rig: BodyRig
var yaw_node: Node3D
var pitch_node: Node3D
var arm: SpringArm3D
var cam: Camera3D

var input_enabled := false
var touch_move := Vector2.ZERO   # from virtual joystick, -1..1
var touch_sprint := false
var cam_yaw := 0.0
var cam_pitch := -0.32
var cam_dist := 6.0
var _dragging := false
var autorun := false
var _last_look_ms := -100000
const FOLLOW_TOUCH := 1.1   # follow-camera turn rate on phones (rad/s per rad of offset)
const FOLLOW_KEYS := 0.55   # gentler with keyboard + mouse
var last_safe := Vector3.ZERO

signal jumped

func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	rig = BodyRig.new()
	add_child(rig)
	refresh_look()
	Game.progress_changed.connect(refresh_look)

	yaw_node = Node3D.new()
	yaw_node.position.y = 1.5
	add_child(yaw_node)
	yaw_node.top_level = true
	pitch_node = Node3D.new()
	yaw_node.add_child(pitch_node)
	arm = SpringArm3D.new()
	arm.spring_length = cam_dist
	arm.margin = 0.3
	arm.collision_mask = 1
	var sph := SphereShape3D.new()
	sph.radius = 0.25
	arm.shape = sph
	arm.add_excluded_object(get_rid())
	pitch_node.add_child(arm)
	cam = Camera3D.new()
	cam.fov = 62
	cam.far = 400
	arm.add_child(cam)
	cam.position = Vector3(0, 0, 0)
	last_safe = global_position

var _look_key := ""

func refresh_look() -> void:
	var key := Game.look_key()
	if key == _look_key:
		rig.set_belt_color(Data.BELTS[Game.belt_index()].color)
		return
	_look_key = key
	Game.dress(rig)
	rig.setup(Game.gi_color(), Data.BELTS[Game.belt_index()].color, Color(0.86, 0.68, 0.55), Color(0.55, 0.36, 0.18), 0, "male")

func make_current() -> void:
	cam.make_current()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	# mouse orbit (ignore touch-emulated mouse; touch is handled by TouchControls)
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam_dist = clampf(cam_dist - 0.6, 3.0, 12.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_dist = clampf(cam_dist + 0.6, 3.0, 12.0)
	elif event is InputEventMouseMotion and _dragging and event.device != InputEvent.DEVICE_ID_EMULATION:
		look(event.relative * 0.005)

func look(delta: Vector2) -> void:
	cam_yaw -= delta.x
	cam_pitch = clampf(cam_pitch - delta.y, -1.2, 0.35)
	_last_look_ms = Time.get_ticks_msec()

func zoom(amount: float) -> void:
	cam_dist = clampf(cam_dist + amount, 3.0, 12.0)

func _physics_process(delta: float) -> void:
	var dir2 := Vector2.ZERO
	var sprint := false
	if input_enabled:
		dir2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if touch_move.length() > 0.05:
			dir2 = touch_move
		if InputMap.has_action("autorun") and Input.is_action_just_pressed("autorun"):
			autorun = not autorun
		if autorun and (Input.is_action_pressed("move_back") or Input.is_action_pressed("move_forward")):
			autorun = false
		if autorun and dir2 == Vector2.ZERO:
			dir2 = Vector2(0, -1)
		sprint = Input.is_action_pressed("sprint") or touch_sprint or touch_move.length() > 0.92
		var kl := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if kl != Vector2.ZERO:
			look(kl * delta * 2.4)
	var basis_y := Basis(Vector3.UP, cam_yaw)
	var move := basis_y * Vector3(dir2.x, 0, dir2.y)
	if move.length() > 1.0:
		move = move.normalized()
	var speed := RUN if sprint else WALK
	var target_v := move * speed
	velocity.x = move_toward(velocity.x, target_v.x, delta * 40.0)
	velocity.z = move_toward(velocity.z, target_v.z, delta * 40.0)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif input_enabled and Input.is_action_just_pressed("jump"):
		do_jump()
	move_and_slide()

	if is_on_floor() and global_position.y > -0.5:
		last_safe = global_position
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.2:
		var face := atan2(-velocity.x, -velocity.z)
		rig.rotation.y = lerp_angle(rig.rotation.y, face, clampf(delta * 12.0, 0, 1))
		# follow camera: swing in behind the runner unless the player is steering the camera
		if input_enabled and Time.get_ticks_msec() - _last_look_ms > 1200:
			var off := wrapf(face - cam_yaw, -PI, PI)
			if absf(off) < 2.3:
				var rate := FOLLOW_TOUCH if touch_move.length() > 0.05 or autorun else FOLLOW_KEYS
				cam_yaw += off * clampf(delta * rate * clampf(hspeed / RUN, 0.3, 1.0), 0.0, 1.0)
	rig.animate_locomotion(delta, clampf(hspeed / RUN, 0.0, 1.0), not is_on_floor())

	yaw_node.global_position = yaw_node.global_position.lerp(global_position + Vector3(0, 1.5, 0), clampf(delta * 12.0, 0, 1))
	yaw_node.rotation.y = cam_yaw
	pitch_node.rotation.x = cam_pitch
	arm.spring_length = lerpf(arm.spring_length, cam_dist, clampf(delta * 6.0, 0, 1))

func do_jump() -> void:
	if is_on_floor():
		velocity.y = JUMP_V
		jumped.emit()

func teleport(p: Vector3, yaw := 0.0) -> void:
	global_position = p
	velocity = Vector3.ZERO
	cam_yaw = yaw
	rig.rotation.y = yaw
	if yaw_node:
		yaw_node.global_position = p + Vector3(0, 1.5, 0)
