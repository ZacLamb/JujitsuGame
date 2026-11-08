class_name FightMotion
extends RefCounted
## Keeps the two grapplers alive between technique animations: footwork and circling (you steer
## with WASD / left stick), hand fighting, breathing that gets heavier as the gas tank empties,
## a visible wind-up while a technique is being cast, and short reaction "bumps" (braces,
## recoils, grip yanks) when counters and grips land. Everything is written to BodyRig.layer
## (additive, on top of the tweened pose) and to the shared pair node, so RollSim stays the only
## source of truth for what is actually happening.

var pair: Node3D
var me: BodyRig
var them: BodyRig
var t := 0.0
var yaw_vel := 0.0
var ai_drift := 0.0
var ai_drift_t := 0.0
var step_me := 0.0      # forward/back footwork offset, rig-local metres
var step_them := 0.0
var input := Vector2.ZERO
var test_input := Vector2.ZERO   # probes: pretend the stick is held
var _bumps: Array = []  # [{rig, offs, t, dur}]
var _rng := RandomNumberGenerator.new()

func _init(pair_node: Node3D, player: BodyRig, opponent: BodyRig) -> void:
	pair = pair_node
	me = player
	them = opponent
	_rng.randomize()

## Reads WASD / arrows-free keys and the left stick. Returns (x = circle, y = step in).
static func read_input() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		v.y -= 1.0
	var jx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var jy := -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if absf(jx) > 0.25:
		v.x += jx
	if absf(jy) > 0.25:
		v.y += jy
	return v.limit_length(1.0)

## A reaction that rises and falls once over `dur` seconds.
func bump(rig: BodyRig, offs: Dictionary, dur := 0.5) -> void:
	_bumps.append({"rig": rig, "offs": offs, "t": 0.0, "dur": dur})

func update(delta: float, sim: RollSim, live: bool) -> void:
	t += delta
	var standing := sim.pos == "standing" and sim.struggle.is_empty()
	var locked := not sim.struggle.is_empty()
	input = (read_input() + test_input).limit_length(1.0) if live and not locked else Vector2.ZERO
	# ---- circling: your input plus the opponent's own drift
	ai_drift_t -= delta
	if ai_drift_t <= 0.0:
		ai_drift_t = _rng.randf_range(1.4, 3.2)
		ai_drift = _rng.randf_range(-0.45, 0.45) if standing else 0.0
	var busy := not sim.cast.is_empty() or not sim.opp_cast.is_empty()
	var want := 0.0
	if standing:
		want = input.x * 1.1 + ai_drift * (0.35 if busy else 1.0)
	elif not locked:
		want = input.x * 0.45   # on the ground you can still shift the angle a little
	yaw_vel = lerpf(yaw_vel, want, clampf(delta * 3.0, 0.0, 1.0))
	pair.rotation.y += yaw_vel * delta
	# drift around the mat while standing (keeps it from looking like a turntable)
	if standing:
		var drift := Vector3(sin(t * 0.21) * 0.55, 0, cos(t * 0.17) * 0.45)
		pair.position = pair.position.lerp(drift, clampf(delta * 0.6, 0.0, 1.0))
	# ---- footwork distance (rig-local -Z is "toward the partner")
	var want_me := 0.0
	var want_them := 0.0
	if standing:
		want_me = input.y * 0.16
		want_them = sin(t * 0.9 + 1.3) * 0.06
		if not sim.opp_cast.is_empty():
			want_them += 0.12 * _progress(sim.opp_cast)
		if not sim.cast.is_empty():
			want_me += 0.12 * _progress(sim.cast)
	step_me = lerpf(step_me, want_me, clampf(delta * 6.0, 0.0, 1.0))
	step_them = lerpf(step_them, want_them, clampf(delta * 5.0, 0.0, 1.0))
	me.hips.position.z = -step_me
	them.hips.position.z = -step_them
	me.hips.position.x = 0.0
	them.hips.position.x = 0.0
	# ---- additive layers
	var top_me := sim.player_top
	var lm := _idle(sim.pos, top_me, sim.stamina / maxf(1.0, sim.max_stamina), 0.0, locked, input)
	var lt := _idle(sim.pos, not top_me, sim.opp_stamina / 100.0, 2.1, locked, Vector2.ZERO)
	if not locked:
		_add(lm, _windup(sim.cast, sim.pos, top_me), 1.0)
		_add(lt, _windup(sim.opp_cast, sim.pos, not top_me), 1.0)
		_add(lt, _react(sim.cast), 1.0)
		_add(lm, _react(sim.opp_cast), 1.0)
	var keep: Array = []
	for b in _bumps:
		b.t = float(b.t) + delta
		var k := float(b.t) / float(b.dur)
		if k >= 1.0:
			continue
		keep.append(b)
		var w := sin(PI * k)
		_add(lm if b.rig == me else lt, b.offs, w)
	_bumps = keep
	me.layer = lm
	them.layer = lt

static func _progress(c: Dictionary) -> float:
	if c.is_empty():
		return 0.0
	return clampf(float(c.get("t", 0.0)) / maxf(0.05, float(c.get("dur", 1.0))), 0.0, 1.0)

static func _add(into: Dictionary, offs: Dictionary, w: float) -> void:
	for k in offs:
		if k == "hip_h":
			into[k] = float(into.get(k, 0.0)) + float(offs[k]) * w
		else:
			into[k] = (into.get(k, Vector3.ZERO) as Vector3) + (offs[k] as Vector3) * w

## Breathing, footwork bounce and hand fighting (standing) or grip fighting / guard work (ground).
func _idle(pos: String, top: bool, gas: float, ph: float, locked: bool, inp: Vector2) -> Dictionary:
	var tired := clampf(1.0 - gas, 0.0, 1.0)
	var br_rate := 1.5 + 1.6 * tired
	var br := sin(t * br_rate + ph) * (0.025 + 0.06 * tired)
	var out := {"spine": Vector3(br, 0, 0), "neck": Vector3(-br * 0.6, 0, 0)}
	if locked:
		out["hip_rot"] = Vector3(0, 0, sin(t * 7.0 + ph) * 0.03)
		return out
	var energy := lerpf(1.0, 0.45, tired)
	if pos == "standing":
		var moving := inp.length()
		var bounce_rate := 5.2 + 2.5 * moving
		out["hip_h"] = sin(t * bounce_rate + ph) * (0.018 + 0.02 * moving) * energy - 0.02 * moving
		out["hip_rot"] = Vector3(0, sin(t * 0.8 + ph) * 0.08, sin(t * 1.9 + ph) * 0.06 * energy)
		out["l_kn"] = Vector3(-0.08 - sin(t * bounce_rate + ph) * 0.06 * energy, 0, 0)
		out["r_kn"] = Vector3(-0.08 + sin(t * bounce_rate + ph) * 0.06 * energy, 0, 0)
		# hand fight: alternating reaches, swats and pulls
		var a := t * 2.6 + ph
		out["l_sh"] = Vector3(sin(a) * 0.28 * energy, 0, sin(a * 0.7) * 0.12)
		out["r_sh"] = Vector3(sin(a * 1.13 + 1.9) * 0.28 * energy, 0, -sin(a * 0.8 + 0.6) * 0.12)
		out["l_el"] = Vector3(maxf(0.0, -sin(a)) * 0.35 * energy, 0, 0)
		out["r_el"] = Vector3(maxf(0.0, -sin(a * 1.13 + 1.9)) * 0.35 * energy, 0, 0)
		out["spine"] = (out.spine as Vector3) + Vector3(-0.06 * inp.y, 0, 0)
		return out
	var g := t * 1.9 + ph
	if top:
		out["spine"] = (out.spine as Vector3) + Vector3(sin(g * 0.6) * 0.06, 0, sin(g * 0.45) * 0.05)
		out["l_sh"] = Vector3(sin(g) * 0.16 * energy, 0, 0)
		out["r_sh"] = Vector3(sin(g + 2.2) * 0.16 * energy, 0, 0)
		out["hip_rot"] = Vector3(0, 0, sin(g * 0.5) * 0.05)
	else:
		out["l_hip"] = Vector3(sin(g) * 0.16 * energy, 0, 0)
		out["r_hip"] = Vector3(sin(g + PI) * 0.16 * energy, 0, 0)
		out["l_sh"] = Vector3(sin(g * 1.3 + 1.0) * 0.18 * energy, 0, 0)
		out["r_sh"] = Vector3(sin(g * 1.3 + 2.6) * 0.18 * energy, 0, 0)
		out["hip_rot"] = Vector3(0, 0, sin(g * 0.6) * 0.07)
	return out

## The actor visibly sets the technique up while the cast bar fills.
func _windup(c: Dictionary, pos: String, top: bool) -> Dictionary:
	if c.is_empty():
		return {}
	var p := _progress(c)
	var e := p * p * (3.0 - 2.0 * p)
	var shake := sin(t * 38.0) * 0.03 * maxf(0.0, p - 0.7) / 0.3
	var kind := str(c.get("kind", ""))
	match kind:
		"breathe":
			return {"spine": Vector3(0.12 * e + sin(t * 2.2) * 0.06, 0, 0), "l_sh": Vector3(-0.25 * e, 0, 0), "r_sh": Vector3(-0.25 * e, 0, 0)}
		"grip":
			var yank := sin(t * 9.0) * 0.12
			return {"l_sh": Vector3(0.45 * e + yank, 0, 0), "r_sh": Vector3(0.3 * e - yank, 0, 0), "l_el": Vector3(-0.3 * e, 0, 0), "spine": Vector3(-0.1 * e, 0, 0)}
		"wear":
			return {"spine": Vector3(-0.28 * e, 0, 0), "hip_h": -0.07 * e, "l_sh": Vector3(0.25 * e, 0, 0), "r_sh": Vector3(0.25 * e, 0, 0), "neck": Vector3(0.15 * e, 0, 0)}
		"special":
			return {"spine": Vector3(-0.45 * e + shake * 3.0, 0, 0), "hip_h": -0.15 * e, "l_sh": Vector3(0.6 * e, 0, 0), "r_sh": Vector3(0.6 * e, 0, 0), "hip_rot": Vector3(0, 0, shake * 2.0)}
	var id := str(c.get("id", ""))
	if not Data.MOVES.has(id):
		return {}
	var ty := str(Data.MOVES[id].type)
	var out: Dictionary = {}
	match ty:
		"takedown":
			out = {"hip_h": -0.26 * e, "spine": Vector3(-0.55 * e, 0, 0), "l_kn": Vector3(-0.5 * e, 0, 0), "r_kn": Vector3(-0.35 * e, 0, 0), "l_sh": Vector3(0.35 * e, 0, 0), "r_sh": Vector3(0.35 * e, 0, 0)}
		"guard":
			out = {"hip_h": -0.2 * e, "l_hip": Vector3(0.5 * e, 0, 0), "l_sh": Vector3(0.45 * e, 0, 0), "r_sh": Vector3(0.45 * e, 0, 0)}
		"sweep":
			out = {"l_hip": Vector3(0.45 * e, 0, 0), "r_hip": Vector3(0.25 * e, 0, 0), "hip_rot": Vector3(0, 0, 0.3 * e), "l_sh": Vector3(0.4 * e, 0, 0)}
		"pass":
			out = {"spine": Vector3(-0.3 * e, 0, 0), "hip_h": 0.12 * e, "hip_rot": Vector3(0, 0.25 * e, 0.15 * e), "l_kn": Vector3(0.3 * e, 0, 0)}
		"back":
			out = {"hip_rot": Vector3(0, 0.45 * e, 0), "spine": Vector3(-0.25 * e, 0, 0), "l_sh": Vector3(0.4 * e, 0, 0)}
		"advance":
			out = {"hip_h": 0.1 * e, "spine": Vector3(-0.22 * e, 0, 0), "l_kn": Vector3(0.35 * e, 0, 0)}
		"escape":
			out = {"hip_rot": Vector3(0, 0, 0.35 * e), "l_kn": Vector3(-0.5 * e, 0, 0), "l_sh": Vector3(0.5 * e, 0, 0), "r_sh": Vector3(0.5 * e, 0, 0)}
		"sub":
			if pos != "standing" and not top:
				out = {"l_hip": Vector3(0.45 * e, 0, 0), "r_hip": Vector3(0.45 * e, 0, 0), "l_sh": Vector3(0.5 * e, 0, 0), "r_sh": Vector3(0.5 * e, 0, 0), "l_el": Vector3(-0.4 * e, 0, 0)}
			else:
				out = {"spine": Vector3(-0.25 * e, 0, 0), "l_sh": Vector3(0.55 * e, 0, 0), "r_sh": Vector3(0.55 * e, 0, 0), "l_el": Vector3(-0.45 * e, 0, 0), "r_el": Vector3(-0.3 * e, 0, 0)}
	if not out.is_empty():
		out["hip_rot"] = (out.get("hip_rot", Vector3.ZERO) as Vector3) + Vector3(0, 0, shake)
	return out

## The other fighter senses it coming: weight back, hands up.
func _react(c: Dictionary) -> Dictionary:
	if c.is_empty() or str(c.get("kind", "")) == "breathe":
		return {}
	var p := _progress(c) * 0.35
	return {"spine": Vector3(0.18 * p, 0, 0), "l_sh": Vector3(0.3 * p, 0, 0), "r_sh": Vector3(0.3 * p, 0, 0), "hip_h": -0.04 * p}

# ------------------------------------------------------------------ reaction presets
const BRACE := {
	"base": {"hip_h": -0.12, "l_kn": Vector3(-0.35, 0, 0), "r_kn": Vector3(-0.35, 0, 0), "spine": Vector3(-0.15, 0, 0)},
	"frame": {"l_sh": Vector3(0.7, 0, 0), "r_sh": Vector3(0.7, 0, 0), "l_el": Vector3(-0.55, 0, 0), "r_el": Vector3(-0.55, 0, 0)},
	"defend": {"l_el": Vector3(0.8, 0, 0), "r_el": Vector3(0.8, 0, 0), "l_sh": Vector3(0.25, 0, 0.25), "r_sh": Vector3(0.25, 0, -0.25), "spine": Vector3(-0.18, 0, 0), "neck": Vector3(0.3, 0, 0)},
}
const RECOIL := {"spine": Vector3(0.35, 0, 0), "hip_h": -0.05, "l_sh": Vector3(-0.3, 0, 0), "r_sh": Vector3(-0.3, 0, 0), "neck": Vector3(-0.25, 0, 0)}
const LUNGE := {"spine": Vector3(-0.5, 0, 0), "hip_h": -0.14, "l_sh": Vector3(0.5, 0, 0), "r_sh": Vector3(0.5, 0, 0)}
const YANK := {"l_sh": Vector3(-0.45, 0, 0), "r_sh": Vector3(-0.25, 0, 0), "spine": Vector3(0.12, 0, 0)}
const PULLED := {"spine": Vector3(-0.25, 0, 0), "neck": Vector3(0.2, 0, 0), "hip_h": -0.03}
const SLUMP := {"spine": Vector3(-0.2, 0, 0), "neck": Vector3(0.35, 0, 0), "hip_h": -0.06}
const STUMBLE := {"hip_rot": Vector3(0, 0, 0.18), "spine": Vector3(0.15, 0, 0)}
