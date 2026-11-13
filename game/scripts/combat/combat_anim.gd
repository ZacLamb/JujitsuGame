class_name CombatAnim
extends RefCounted
## Short pose sequences for in-world combat. Each builds BodyRig.action() frames
## ([pose, root Transform3D, seconds]) around the rig's current spot and a facing yaw.

static func stance() -> Dictionary:
	return {"hip_h": 0.84, "spine": Vector3(-0.32, 0, 0), "neck": Vector3(0.22, 0, 0),
		"l_hip": Vector3(0.38, 0, -0.14), "r_hip": Vector3(-0.06, 0, 0.14),
		"l_kn": Vector3(-0.6, 0, 0), "r_kn": Vector3(-0.4, 0, 0),
		"l_sh": Vector3(1.05, 0, 0.18), "r_sh": Vector3(0.9, 0, -0.18),
		"l_el": Vector3(0.9, 0, 0), "r_el": Vector3(1.0, 0, 0)}

static func _m(base: Dictionary, over: Dictionary) -> Dictionary:
	var p := base.duplicate()
	p.merge(over, true)
	return p

static func _root(yaw: float, fwd := 0.0, up := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, yaw)
	return Transform3D(b, b * Vector3(0, up, -fwd))

## Attack animation for an ability type. yaw: facing toward the target.
static func attack(kind: String, yaw: float) -> Array:
	var s := stance()
	match kind:
		"handfight", "auto":
			var reach := _m(s, {"spine": Vector3(-0.45, 0, 0), "l_sh": Vector3(1.55, 0, 0.12), "r_sh": Vector3(1.3, 0, -0.2), "l_el": Vector3(0.2, 0, 0), "r_el": Vector3(0.55, 0, 0)})
			var pull := _m(s, {"spine": Vector3(-0.2, 0, 0), "l_sh": Vector3(1.0, 0, 0.25), "l_el": Vector3(1.6, 0, 0), "r_sh": Vector3(1.1, 0, -0.1), "r_el": Vector3(1.3, 0, 0)})
			return [[reach, _root(yaw, 0.12), 0.12, Tween.EASE_OUT], [pull, _root(yaw, -0.05), 0.14], [s, _root(yaw), 0.2]]
		"takedown":
			var dip := _m(s, {"hip_h": 0.66, "spine": Vector3(-0.6, 0, 0), "l_kn": Vector3(-1.1, 0, 0), "r_kn": Vector3(-0.9, 0, 0)})
			var shot := {"hip_h": 0.52, "spine": Vector3(-1.05, 0, 0), "neck": Vector3(0.65, 0, 0),
				"l_hip": Vector3(1.25, 0, -0.1), "r_hip": Vector3(-0.35, 0, 0.1), "l_kn": Vector3(-1.7, 0, 0), "r_kn": Vector3(-0.3, 0, 0),
				"l_sh": Vector3(1.35, 0, 0.35), "r_sh": Vector3(1.35, 0, -0.35), "l_el": Vector3(1.0, 0, 0), "r_el": Vector3(1.0, 0, 0)}
			return [[dip, _root(yaw, -0.1), 0.14], [shot, _root(yaw, 0.85), 0.2, Tween.EASE_OUT], [shot, _root(yaw, 0.85), 0.12], [s, _root(yaw), 0.32]]
		"sweep":
			var kick := _m(s, {"hip_h": 0.78, "spine": Vector3(-0.15, 0, 0.2), "l_hip": Vector3(1.35, 0, 0.35), "l_kn": Vector3(-0.15, 0, 0),
				"r_kn": Vector3(-0.6, 0, 0), "l_sh": Vector3(1.4, 0, 0.3), "r_sh": Vector3(0.7, 0, -0.6), "r_el": Vector3(1.5, 0, 0)})
			return [[kick, _root(yaw, 0.3), 0.16, Tween.EASE_OUT], [kick, _root(yaw, 0.3), 0.08], [s, _root(yaw), 0.3]]
		"pass", "advance", "e_press":
			var press := {"hip_h": 0.68, "spine": Vector3(-0.95, 0, 0), "neck": Vector3(0.55, 0, 0),
				"l_hip": Vector3(0.65, 0, -0.25), "r_hip": Vector3(0.25, 0, 0.25), "l_kn": Vector3(-1.25, 0, 0), "r_kn": Vector3(-0.95, 0, 0),
				"l_sh": Vector3(1.0, 0, 0.25), "r_sh": Vector3(1.0, 0, -0.25), "l_el": Vector3(1.3, 0, 0), "r_el": Vector3(1.3, 0, 0)}
			var step := _m(press, {"l_hip": Vector3(0.2, 0, -0.5), "r_hip": Vector3(0.8, 0, 0.3)})
			return [[press, _root(yaw, 0.45), 0.18, Tween.EASE_OUT], [step, _root(yaw + 0.4, 0.55), 0.18], [s, _root(yaw), 0.3]]
		"back":
			var spin := _m(s, {"hip_h": 0.72, "spine": Vector3(-0.7, 0, 0.3), "l_sh": Vector3(1.6, 0, 0.6), "r_sh": Vector3(1.5, 0, -0.6), "l_el": Vector3(1.2, 0, 0), "r_el": Vector3(1.2, 0, 0)})
			return [[spin, _root(yaw + 0.9, 0.6), 0.22, Tween.EASE_OUT], [spin, _root(yaw + 0.6, 0.5), 0.12], [s, _root(yaw), 0.3]]
		"escape":
			var bridge := _m(s, {"hip_h": 0.9, "spine": Vector3(0.35, 0, 0), "l_sh": Vector3(0.6, 0, 0.6), "r_sh": Vector3(0.6, 0, -0.6)})
			return [[bridge, _root(yaw, -0.35), 0.18, Tween.EASE_OUT], [s, _root(yaw), 0.3]]
		"guard", "defend", "base":
			var base := _m(s, {"hip_h": 0.74, "spine": Vector3(-0.15, 0, 0), "l_hip": Vector3(0.5, 0, -0.35), "r_hip": Vector3(-0.2, 0, 0.35),
				"l_sh": Vector3(1.2, 0, 0.45), "r_sh": Vector3(1.2, 0, -0.45), "l_el": Vector3(1.8, 0, 0), "r_el": Vector3(1.8, 0, 0)})
			return [[base, _root(yaw, -0.1), 0.16, Tween.EASE_OUT], [base, _root(yaw, -0.1), 0.3], [s, _root(yaw), 0.25]]
	return [[s, _root(yaw), 0.2]]

## Held while casting a submission: reach and squeeze.
static func squeeze(yaw: float) -> Array:
	var sq := {"hip_h": 0.72, "spine": Vector3(-0.65, 0, 0), "neck": Vector3(0.45, 0, 0),
		"l_hip": Vector3(0.55, 0, -0.2), "r_hip": Vector3(0.5, 0, 0.2), "l_kn": Vector3(-1.05, 0, 0), "r_kn": Vector3(-1.0, 0, 0),
		"l_sh": Vector3(1.25, 0, 0.7), "r_sh": Vector3(1.25, 0, -0.7), "l_el": Vector3(2.05, 0, 0), "r_el": Vector3(2.05, 0, 0)}
	return [[sq, _root(yaw, 0.35), 0.25, Tween.EASE_OUT]]

static func recoil(yaw: float) -> Array:
	var s := stance()
	var hit := _m(s, {"spine": Vector3(0.15, 0, 0), "neck": Vector3(-0.3, 0, 0), "hip_h": 0.88})
	return [[hit, _root(yaw, -0.18), 0.08, Tween.EASE_OUT], [s, _root(yaw), 0.22]]

## A sprawl: hips drop, legs shoot back, chest drives down onto their shot (then back to stance).
static func sprawl(yaw: float) -> Array:
	var s := stance()
	var sp := _m(s, {"hip_h": 0.5, "spine": Vector3(-0.95, 0, 0), "neck": Vector3(0.6, 0, 0),
		"l_hip": Vector3(-0.55, 0, -0.15), "r_hip": Vector3(-0.5, 0, 0.15), "l_kn": Vector3(-0.25, 0, 0), "r_kn": Vector3(-0.3, 0, 0),
		"l_sh": Vector3(1.1, 0, 0.45), "r_sh": Vector3(1.1, 0, -0.45), "l_el": Vector3(1.2, 0, 0), "r_el": Vector3(1.2, 0, 0)})
	return [[sp, _root(yaw, -0.35), 0.1, Tween.EASE_OUT], [sp, _root(yaw, -0.35), 0.28], [s, _root(yaw), 0.3]]

## A frame: arms extend, posture braces back (then back to stance).
static func brace(yaw: float) -> Array:
	var s := stance()
	var fr := _m(s, {"spine": Vector3(0.25, 0, 0), "l_sh": Vector3(1.45, 0, 0.25), "r_sh": Vector3(1.45, 0, -0.25),
		"l_el": Vector3(0.15, 0, 0), "r_el": Vector3(0.15, 0, 0), "hip_h": 0.88})
	return [[fr, _root(yaw, 0.12), 0.08, Tween.EASE_OUT], [fr, _root(yaw, 0.12), 0.22], [s, _root(yaw), 0.25]]

## Knocked down: fall onto the back and hold (released with getup()).
static func fall(yaw: float) -> Array:
	var down: Dictionary = RollPoses.get_pair("guard").bottom[0]
	var mid := _m(stance(), {"hip_h": 0.45, "spine": Vector3(0.6, 0, 0), "l_kn": Vector3(-1.2, 0, 0), "r_kn": Vector3(-1.2, 0, 0)})
	return [[mid, _root(yaw, -0.25), 0.16, Tween.EASE_IN], [down, _root(yaw, -0.45), 0.2, Tween.EASE_OUT]]

static func getup(yaw: float) -> Array:
	var kneel := _m(stance(), {"hip_h": 0.45, "spine": Vector3(-0.6, 0, 0), "l_hip": Vector3(1.4, 0, 0), "l_kn": Vector3(-1.6, 0, 0), "r_hip": Vector3(0.2, 0, 0), "r_kn": Vector3(-1.9, 0, 0)})
	return [[kneel, _root(yaw, -0.2), 0.22], [stance(), _root(yaw), 0.25]]
