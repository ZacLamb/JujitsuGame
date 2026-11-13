class_name Player
extends CharacterBody3D
## Third-person explorer. Keyboard/mouse + virtual joystick input. Camera orbit on drag.

const WALK := 5.0
const RUN := 8.5
const JUMP_V := 5.6
const GRAVITY := 13.0
const STEP_HEIGHT := 0.42

var rig: BodyRig
var yaw_node: Node3D
var pitch_node: Node3D
var arm: SpringArm3D
var cam: Camera3D

var input_enabled := false
var emoting := false   # an emote is playing (moving cancels it)
var rooted := false   # knocked down / finishing in combat: no walking
var touch_move := Vector2.ZERO   # from virtual joystick, -1..1
var touch_sprint := false
var cam_yaw := 0.0
var cam_pitch := -0.32
var cam_dist := 6.0
## Grappling camera: WorldCombat sets these while you're on the ground with someone, and the
## camera eases in on the middle of the pair (and back out when you stand up).
var ground_on := false
var ground_focus := Vector3.ZERO
var _gb := 0.0
var _dragging := false
var _lmb := false
var _rmb := false
var _press_pos := Vector2.ZERO
var _press_ms := 0
var _drag_px := 0.0
var walk_target: Npc = null
var _step_dist := 0.0   # set by click-to-interact; the player walks there
var autorun := false
var _last_look_ms := -100000
const FOLLOW_TOUCH := 1.1   # follow-camera turn rate on phones (rad/s per rad of offset)
const FOLLOW_KEYS := 0.55   # gentler with keyboard + mouse
var last_safe := Vector3.ZERO
var swimming := false
var speed_mult := 1.0   # Game Master speed tool   # chest-deep or more: float at the surface, slower, no jumping

signal jumped
signal clicked(screen_pos: Vector2)

func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	rig = BodyRig.new()
	rig.bulk = 1.0
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
var shake := 0.0   # camera shake (landings, crits, taps); decays

func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)

func refresh_look() -> void:
	var key := Game.look_key()
	if key == _look_key:
		rig.set_belt_color(Data.BELTS[Game.belt_index()].color)
		return
	_look_key = key
	Game.dress(rig)
	rig.setup(Game.gi_color(), Data.BELTS[Game.belt_index()].color, Game.skin_color(), Color(0.55, 0.36, 0.18), 0, Game.body)

func make_current() -> void:
	cam.make_current()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	# mouse orbit (ignore touch-emulated mouse; touch is handled by TouchControls)
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_lmb = event.pressed
			else:
				_rmb = event.pressed
			_dragging = _lmb or _rmb
			if event.pressed:
				_press_pos = event.position
				_press_ms = Time.get_ticks_msec()
				_drag_px = 0.0
			elif event.button_index == MOUSE_BUTTON_LEFT and _drag_px < 6.0 and Time.get_ticks_msec() - _press_ms < 350:
				clicked.emit(event.position)
	elif event is InputEventMouseMotion and _dragging and event.device != InputEvent.DEVICE_ID_EMULATION:
		_drag_px += event.relative.length()
		if _drag_px >= 6.0:
			look(event.relative * 0.005)

var zoom_blocked: Callable   # set by main: true while a panel (big map, menus) owns the wheel

## Zoom is read in _input (before the GUI) so HUD panels under the cursor can't swallow the wheel.
## Mac trackpads send two-finger scroll as pan gestures and pinch as magnify.
func _input(event: InputEvent) -> void:
	if not input_enabled or (zoom_blocked.is_valid() and zoom_blocked.call()):
		return
	if event is InputEventMouseButton and event.pressed:
		var f: float = event.factor if event.factor > 0.0 else 1.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-0.7 * f)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(0.7 * f)
	elif event is InputEventPanGesture:
		zoom(event.delta.y * 0.35)
	elif event is InputEventMagnifyGesture:
		zoom((1.0 - event.factor) * 8.0)

func look(delta: Vector2) -> void:
	delta *= float(Sfx.pref("mouse", 1.0))
	if Sfx.pref("invert_y", false):
		delta.y = -delta.y
	cam_yaw -= delta.x
	cam_pitch = clampf(cam_pitch - delta.y, -1.2, 0.35)
	_last_look_ms = Time.get_ticks_msec()

func zoom(amount: float) -> void:
	cam_dist = clampf(cam_dist + amount, 2.2, 16.0)

func _physics_process(delta: float) -> void:
	var dir2 := Vector2.ZERO
	var sprint := false
	var keys_ok := input_enabled and not CombatLog.typing
	if keys_ok:
		dir2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if touch_move.length() > 0.05:
			dir2 = touch_move
		if InputMap.has_action("autorun") and Input.is_action_just_pressed("autorun"):
			autorun = not autorun
		if autorun and (Input.is_action_pressed("move_back") or Input.is_action_pressed("move_forward")):
			autorun = false
		# WoW: both mouse buttons held runs forward
		if _lmb and _rmb and dir2 == Vector2.ZERO:
			dir2 = Vector2(0, -1)
		if dir2 != Vector2.ZERO and not autorun:
			walk_target = null
		if autorun and dir2 == Vector2.ZERO:
			dir2 = Vector2(0, -1)
		sprint = Input.is_action_pressed("sprint") or touch_sprint or touch_move.length() > 0.92
		var kl := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if kl != Vector2.ZERO:
			look(kl * delta * 2.4)
	if rooted:
		dir2 = Vector2.ZERO
	var basis_y := Basis(Vector3.UP, cam_yaw)
	var move := basis_y * Vector3(dir2.x, 0, dir2.y)
	if walk_target != null and not rooted:
		if not is_instance_valid(walk_target) or not input_enabled:
			walk_target = null
		elif dir2 == Vector2.ZERO:
			var to := walk_target.global_position - global_position
			to.y = 0
			move = to.normalized() if to.length() > 0.1 else Vector3.ZERO
	if move.length() > 1.0:
		move = move.normalized()
	var wl: float = (get_parent() as World).water_level() if get_parent() is World else -INF
	swimming = global_position.y < wl - 0.8
	# WoW backpedal: S alone walks backwards, still facing forward
	var back := dir2.y > 0.4 and absf(dir2.x) < 0.6 and walk_target == null and not swimming
	var speed := (RUN if sprint else WALK) * speed_mult
	if back:
		speed = WALK * 0.65 * speed_mult
	if swimming:
		speed = WALK * 0.6
	var target_v := move * speed
	# ease into and out of a run (accelerate a bit softer than we brake)
	var accel := 22.0 if target_v.length() > Vector2(velocity.x, velocity.z).length() else 30.0
	velocity.x = move_toward(velocity.x, target_v.x, delta * accel)
	velocity.z = move_toward(velocity.z, target_v.z, delta * accel)
	if swimming:
		# buoyancy: settle with the chest at the waterline
		velocity.y = lerpf(velocity.y, ((wl - 1.15) - global_position.y) * 5.0, clampf(delta * 6.0, 0, 1))
	elif not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif keys_ok and Input.is_action_just_pressed("jump"):
		do_jump()
	var hvel := Vector3(velocity.x, 0, velocity.z)
	move_and_slide()
	# step up small ledges (plaza curbs, gym floors, mats) instead of stopping dead
	# climbing out of the water onto a bank counts as a step too
	if is_on_wall() and hvel.length() > 0.5 and (is_on_floor() or swimming):
		var step := Vector3.UP * STEP_HEIGHT
		var fwd := hvel.normalized() * 0.3
		if not test_move(global_transform, step) and not test_move(global_transform.translated(step), fwd):
			global_position += step + fwd
			velocity.y = 0.0

	if is_on_floor() and not swimming:
		last_safe = global_position
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.2:
		var face := atan2(-velocity.x, -velocity.z)
		if (_rmb or back) and input_enabled:
			face = cam_yaw  # right mouse held / backpedalling: the character faces where the camera looks
		if not rig.in_action():
			rig.rotation.y = lerp_angle(rig.rotation.y, face, clampf(delta * 12.0, 0, 1))
		# follow camera: swing in behind the runner unless the player is steering the camera
		if input_enabled and Time.get_ticks_msec() - _last_look_ms > 1200:
			var off := wrapf(face - cam_yaw, -PI, PI)
			if absf(off) < 2.3:
				var rate := FOLLOW_TOUCH if touch_move.length() > 0.05 or autorun else FOLLOW_KEYS
				cam_yaw += off * clampf(delta * rate * clampf(hspeed / RUN, 0.3, 1.0), 0.0, 1.0)
	# moving against the way the body faces (backpedal, or strafing back with the mouse held)
	var fwd := Vector3(-sin(rig.rotation.y), 0, -cos(rig.rotation.y))
	rig.move_back = hspeed > 0.2 and Vector3(velocity.x, 0, velocity.z).normalized().dot(fwd) < -0.3
	if emoting and hspeed > 0.5 and rig.in_action():   # walking off cancels an emote
		emoting = false
		rig.release()
	if emoting and not rig.in_action():
		emoting = false
	rig.animate_locomotion(delta, clampf(hspeed / RUN, 0.0, 1.0), not is_on_floor() and not swimming)
	# footsteps
	if is_on_floor() and hspeed > 1.0:
		_step_dist += hspeed * delta
		if _step_dist > (1.55 if hspeed < WALK + 0.5 else 2.1):
			_step_dist = 0.0
			var sand := get_parent() is World and (get_parent() as World).zone in ["rio", "socal"] and global_position.z > 31.0
			Sfx.play("step_sand" if sand else "step_ground", -15.0, randf_range(0.85, 1.15))

	_gb = move_toward(_gb, 1.0 if ground_on else 0.0, delta * 2.2)
	var gb := _gb * _gb * (3.0 - 2.0 * _gb)
	var focus := (global_position + Vector3(0, 1.5, 0)).lerp(ground_focus, gb)
	yaw_node.global_position = yaw_node.global_position.lerp(focus, clampf(delta * 12.0, 0, 1))
	yaw_node.rotation.y = cam_yaw
	pitch_node.rotation.x = lerpf(cam_pitch, minf(cam_pitch, -0.42), gb)
	arm.spring_length = lerpf(arm.spring_length, lerpf(cam_dist, minf(cam_dist, 3.9), gb), clampf(delta * 6.0, 0, 1))
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 2.2)
		var k := shake * shake * 0.18
		cam.h_offset = randf_range(-k, k)
		cam.v_offset = randf_range(-k, k)
	elif cam.h_offset != 0.0 or cam.v_offset != 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0

func do_jump() -> void:
	if is_on_floor() and not swimming:
		velocity.y = JUMP_V
		jumped.emit()

func teleport(p: Vector3, yaw := 0.0) -> void:
	global_position = p
	velocity = Vector3.ZERO
	cam_yaw = yaw
	rig.rotation.y = yaw
	if rig.smoother:
		rig.smoother.reset()
	if yaw_node:
		yaw_node.global_position = p + Vector3(0, 1.5, 0)
