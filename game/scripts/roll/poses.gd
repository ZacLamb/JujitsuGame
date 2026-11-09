class_name RollPoses
extends RefCounted
## Pose pairs for each position. Frame: the bottom grappler's hips at origin.
## Each entry: {"top": [pose, Transform3D], "bottom": [pose, Transform3D]}.

static func _xf(pos: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)

const LYING := Vector3(PI / 2, 0, 0)

static func get_pair(pos: String) -> Dictionary:
	match pos:
		"standing":
			var stance := {"hip_h": 0.86, "spine": Vector3(-0.3, 0, 0), "neck": Vector3(0.2, 0, 0),
				"l_hip": Vector3(0.35, 0, -0.12), "r_hip": Vector3(-0.05, 0, 0.12),
				"l_kn": Vector3(-0.55, 0, 0), "r_kn": Vector3(-0.35, 0, 0),
				"l_sh": Vector3(1.15, 0, 0.15), "r_sh": Vector3(1.0, 0, -0.15),
				"l_el": Vector3(0.6, 0, 0), "r_el": Vector3(0.75, 0, 0)}
			return {"top": [stance, _xf(Vector3(0, 0, 0.5), 0.0)],
				"bottom": [stance, _xf(Vector3(0, 0, -0.5), PI)]}
		"guard":
			var bottom := {"hip_h": 0.17, "hip_rot": LYING, "neck": Vector3(-0.35, 0, 0),
				"l_hip": Vector3(1.15, 0, -0.6), "r_hip": Vector3(1.15, 0, 0.6),
				"l_kn": Vector3(-1.45, 0, 0), "r_kn": Vector3(-1.45, 0, 0),
				"l_sh": Vector3(1.3, 0, 0.25), "r_sh": Vector3(1.3, 0, -0.25),
				"l_el": Vector3(0.5, 0, 0), "r_el": Vector3(0.5, 0, 0)}
			var top := {"hip_h": 0.58, "spine": Vector3(-0.3, 0, 0), "neck": Vector3(0.25, 0, 0),
				"l_hip": Vector3(0.05, 0, -0.25), "r_hip": Vector3(0.05, 0, 0.25),
				"l_kn": Vector3(-1.55, 0, 0), "r_kn": Vector3(-1.55, 0, 0),
				"l_sh": Vector3(0.95, 0, 0.1), "r_sh": Vector3(0.95, 0, -0.1),
				"l_el": Vector3(0.35, 0, 0), "r_el": Vector3(0.35, 0, 0)}
			return {"top": [top, _xf(Vector3(0, 0, -0.62), PI)],
				"bottom": [bottom, _xf(Vector3.ZERO, 0.0)]}
		"half":
			var bottom := {"hip_h": 0.2, "hip_rot": Vector3(PI / 2, 0, 0.55), "neck": Vector3(-0.3, 0, 0),
				"l_hip": Vector3(0.9, 0, -0.3), "r_hip": Vector3(0.35, 0, 0.25),
				"l_kn": Vector3(-1.5, 0, 0), "r_kn": Vector3(-0.6, 0, 0),
				"l_sh": Vector3(1.2, 0, 0.5), "r_sh": Vector3(0.8, 0, -0.3),
				"l_el": Vector3(0.9, 0, 0), "r_el": Vector3(0.4, 0, 0)}
			var top := {"hip_h": 0.5, "spine": Vector3(-0.85, 0, 0), "neck": Vector3(0.5, 0, 0),
				"l_hip": Vector3(0.3, 0, -0.35), "r_hip": Vector3(-0.1, 0, 0.2),
				"l_kn": Vector3(-1.4, 0, 0), "r_kn": Vector3(-1.2, 0, 0),
				"l_sh": Vector3(1.25, 0, 0.2), "r_sh": Vector3(1.1, 0, -0.3),
				"l_el": Vector3(0.6, 0, 0), "r_el": Vector3(0.4, 0, 0)}
			return {"top": [top, _xf(Vector3(0.05, 0, -0.42), PI)],
				"bottom": [bottom, _xf(Vector3.ZERO, 0.0)]}
		"side":
			var bottom := {"hip_h": 0.17, "hip_rot": LYING, "neck": Vector3(-0.2, 0, 0),
				"l_hip": Vector3(0.6, 0, -0.1), "r_hip": Vector3(0.6, 0, 0.1),
				"l_kn": Vector3(-1.2, 0, 0), "r_kn": Vector3(-1.2, 0, 0),
				"l_sh": Vector3(1.4, 0, 0.3), "r_sh": Vector3(1.0, 0, -0.5),
				"l_el": Vector3(1.4, 0, 0), "r_el": Vector3(0.8, 0, 0)}
			var top := {"hip_h": 0.55, "spine": Vector3(-1.2, 0, 0), "neck": Vector3(0.7, 0, 0),
				"l_hip": Vector3(0.2, 0, -0.3), "r_hip": Vector3(-0.3, 0, 0.3),
				"l_kn": Vector3(-1.5, 0, 0), "r_kn": Vector3(-1.1, 0, 0),
				"l_sh": Vector3(1.4, 0, 0.3), "r_sh": Vector3(1.3, 0, -0.3),
				"l_el": Vector3(0.5, 0, 0), "r_el": Vector3(0.5, 0, 0)}
			return {"top": [top, _xf(Vector3(0.55, 0, 0.35), PI / 2)],
				"bottom": [bottom, _xf(Vector3.ZERO, 0.0)]}
		"mount":
			var bottom := {"hip_h": 0.17, "hip_rot": LYING, "neck": Vector3(-0.25, 0, 0),
				"l_hip": Vector3(0.25, 0, -0.1), "r_hip": Vector3(0.25, 0, 0.1),
				"l_kn": Vector3(-0.5, 0, 0), "r_kn": Vector3(-0.5, 0, 0),
				"l_sh": Vector3(1.45, 0, 0.2), "r_sh": Vector3(1.45, 0, -0.2),
				"l_el": Vector3(0.7, 0, 0), "r_el": Vector3(0.7, 0, 0)}
			var top := {"hip_h": 0.5, "spine": Vector3(-0.15, 0, 0), "neck": Vector3(0.15, 0, 0),
				"l_hip": Vector3(0.6, 0, -0.85), "r_hip": Vector3(0.6, 0, 0.85),
				"l_kn": Vector3(-1.75, 0, 0), "r_kn": Vector3(-1.75, 0, 0),
				"l_sh": Vector3(0.9, 0, 0.2), "r_sh": Vector3(0.9, 0, -0.2),
				"l_el": Vector3(0.6, 0, 0), "r_el": Vector3(0.6, 0, 0)}
			return {"top": [top, _xf(Vector3(0, 0, 0.12), PI)],
				"bottom": [bottom, _xf(Vector3.ZERO, 0.0)]}
		"back":
			var bottom := {"hip_h": 0.17, "spine": Vector3(0.15, 0, 0), "neck": Vector3(-0.1, 0, 0),
				"l_hip": Vector3(1.45, 0, -0.15), "r_hip": Vector3(1.45, 0, 0.15),
				"l_kn": Vector3(-0.35, 0, 0), "r_kn": Vector3(-0.35, 0, 0),
				"l_sh": Vector3(1.6, 0, 0.5), "r_sh": Vector3(1.6, 0, -0.5),
				"l_el": Vector3(1.3, 0, 0), "r_el": Vector3(1.3, 0, 0)}
			var top := {"hip_h": 0.18, "spine": Vector3(-0.15, 0, 0), "neck": Vector3(0.1, 0, 0),
				"l_hip": Vector3(1.3, 0, -0.5), "r_hip": Vector3(1.3, 0, 0.5),
				"l_kn": Vector3(-1.2, 0, 0), "r_kn": Vector3(-1.2, 0, 0),
				"l_sh": Vector3(1.55, 0, 0.75), "r_sh": Vector3(1.5, 0, -0.75),
				"l_el": Vector3(1.5, 0, 0), "r_el": Vector3(1.5, 0, 0)}
			return {"top": [top, _xf(Vector3(0, 0, 0.34), 0.0)],
				"bottom": [bottom, _xf(Vector3.ZERO, 0.0)]}
	return get_pair("standing")

## Celebration / kneel poses for match end.
static func victory() -> Dictionary:
	return {"hip_h": 0.95, "l_sh": Vector3(0.2, 0, -2.6), "r_sh": Vector3(0.2, 0, 2.6),
		"l_el": Vector3(0.3, 0, 0), "r_el": Vector3(0.3, 0, 0)}

static func defeated() -> Dictionary:
	return {"hip_h": 0.2, "spine": Vector3(-0.5, 0, 0), "neck": Vector3(0.5, 0, 0),
		"l_hip": Vector3(1.5, 0, -0.2), "r_hip": Vector3(1.5, 0, 0.2),
		"l_kn": Vector3(-0.3, 0, 0), "r_kn": Vector3(-0.3, 0, 0),
		"l_sh": Vector3(0.6, 0, 0.1), "r_sh": Vector3(0.6, 0, -0.1),
		"l_el": Vector3(0.6, 0, 0), "r_el": Vector3(0.6, 0, 0)}

# ---------------------------------------------------------------- transitions
## Mid-transition "flavor" applied on top of the halfway blend between the old and new pose,
## so a takedown dives and lands, a sweep rolls the top player over, a pass steps around, etc.
## Returns {"actor": {pose deltas + "lift"/"side"}, "other": {...}} for the move type.
static func flavor(move_type: String) -> Dictionary:
	match move_type:
		"takedown":
			return {"actor": {"hip_h": -0.32, "spine": Vector3(-0.8, 0, 0), "l_sh": Vector3(0.6, 0, -0.3), "r_sh": Vector3(0.6, 0, 0.3), "drive": 0.35},
				"other": {"lift": 0.4, "hip_rot": Vector3(0.7, 0, 0), "l_sh": Vector3(0, 0, -0.9), "r_sh": Vector3(0, 0, 0.9), "l_hip": Vector3(0.6, 0, 0)}}
		"sweep":
			return {"actor": {"hip_h": 0.22, "l_hip": Vector3(0.5, 0, 0), "r_hip": Vector3(0.5, 0, 0), "l_kn": Vector3(1.0, 0, 0), "r_kn": Vector3(1.0, 0, 0)},
				"other": {"lift": 0.55, "roll": 1.1, "l_sh": Vector3(0, 0, -0.8), "r_sh": Vector3(0, 0, 0.8)}}
		"pass":
			return {"actor": {"hip_h": 0.22, "spine": Vector3(-0.4, 0, 0), "side": 0.45, "l_kn": Vector3(0.6, 0, 0)},
				"other": {"hip_rot": Vector3(0, 0, 0.45), "l_hip": Vector3(0.5, 0, 0), "r_hip": Vector3(0.5, 0, 0)}}
		"back":
			return {"actor": {"side": 0.5, "spine": Vector3(-0.5, 0, 0), "hip_h": 0.1},
				"other": {"hip_rot": Vector3(0, 0, 0.6), "spine": Vector3(-0.3, 0, 0)}}
		"advance":
			return {"actor": {"hip_h": 0.18, "l_kn": Vector3(0.5, 0, 0), "spine": Vector3(-0.3, 0, 0)},
				"other": {"hip_rot": Vector3(0, 0, -0.25)}}
		"escape", "guard":
			return {"actor": {"hip_rot": Vector3(0, 0, 0.6), "side": -0.35, "l_kn": Vector3(-0.6, 0, 0)},
				"other": {"hip_h": 0.08, "spine": Vector3(0.2, 0, 0)}}
	return {"actor": {}, "other": {}}

## Applies a flavor dict to a pose; returns the pose plus root offsets.
static func apply_flavor(pose: Dictionary, root: Transform3D, f: Dictionary, toward: Vector3) -> Array:
	var p := pose.duplicate()
	for k in f:
		match k:
			"hip_h":
				p.hip_h = float(p.get("hip_h", 0.95)) + float(f[k])
			"lift", "side", "drive", "roll":
				pass
			_:
				p[k] = (p.get(k, Vector3.ZERO) as Vector3) + (f[k] as Vector3)
	var r := root
	var fwd := toward
	fwd.y = 0
	if fwd.length() > 0.01:
		fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	r.origin += Vector3.UP * float(f.get("lift", 0.0)) + side * float(f.get("side", 0.0)) + fwd * float(f.get("drive", 0.0))
	if f.has("roll"):
		r.basis = Basis(fwd if fwd.length() > 0.01 else Vector3.FORWARD, float(f.roll)) * r.basis
	return [p, r]

# ---------------------------------------------------------------- submissions
const SUB_FAMILY := {"chain_sub": "triangle", "kesa_armlock": "armbar", "heel_hook": "leglock", "smount_armbar": "armbar", "guard_armbar": "armbar", "mount_armbar": "armbar", "flying_armbar": "armbar",
	"triangle": "triangle", "omoplata": "omoplata", "rnc": "back_choke", "bow_arrow": "back_choke",
	"cross_collar": "collar", "ezekiel": "collar", "americana": "keylock", "top_kimura": "keylock",
	"half_kimura": "keylock", "darce": "headlock", "guillotine": "headlock", "kimura_guard": "keylock",
	"back_armbar": "armbar", "straight_ankle": "leglock", "kneebar": "leglock", "north_south": "headlock",
	"mounted_triangle": "collar", "gogoplata": "triangle", "triangle_armbar": "triangle", "toe_hold": "leglock",
	"imanari_roll": "leglock", "paper_cutter": "collar", "baseball_choke": "collar", "twister": "back_choke",
	"crucifix": "headlock"}

## Finishing positions: {"atk": [pose, xf], "def": [pose, xf]}. pos/atk_top give the
## position the submission comes from, used by the families that stay in place.
static func sub_pair(sub_id: String, pos: String, atk_top: bool) -> Dictionary:
	var fam: String = SUB_FAMILY.get(sub_id, "keylock")
	match fam:
		"armbar":
			# classic juji gatame: defender flat, attacker perpendicular with legs across the chest
			var d := {"hip_h": 0.17, "hip_rot": LYING, "neck": Vector3(-0.3, 0, 0),
				"l_hip": Vector3(0.6, 0, -0.15), "r_hip": Vector3(0.15, 0, 0.15),
				"l_kn": Vector3(-1.3, 0, 0), "r_kn": Vector3(-0.25, 0, 0),
				"l_sh": Vector3(1.55, 0, 0.0), "l_el": Vector3(0.0, 0, 0),
				"r_sh": Vector3(1.0, 0, -0.6), "r_el": Vector3(1.6, 0, 0)}
			var a := {"hip_h": 0.24, "hip_rot": LYING, "neck": Vector3(-0.5, 0, 0),
				"l_hip": Vector3(0.55, 0, -0.16), "r_hip": Vector3(0.35, 0, 0.16),
				"l_kn": Vector3(-0.3, 0, 0), "r_kn": Vector3(-0.25, 0, 0),
				"l_sh": Vector3(1.2, 0, 0.35), "r_sh": Vector3(1.2, 0, -0.35),
				"l_el": Vector3(1.5, 0, 0), "r_el": Vector3(1.5, 0, 0)}
			return {"atk": [a, _xf(Vector3(-0.3, 0, 0.8), -PI / 2)], "def": [d, _xf(Vector3.ZERO, 0.0)]}
		"triangle":
			var a := {"hip_h": 0.22, "hip_rot": LYING, "neck": Vector3(-0.6, 0, 0),
				"l_hip": Vector3(1.75, 0, -0.35), "r_hip": Vector3(1.55, 0, 0.45),
				"l_kn": Vector3(-1.9, 0, 0), "r_kn": Vector3(-1.6, 0, 0),
				"l_sh": Vector3(1.4, 0, 0.3), "r_sh": Vector3(1.4, 0, -0.3),
				"l_el": Vector3(1.4, 0, 0), "r_el": Vector3(1.4, 0, 0)}
			var d := {"hip_h": 0.52, "spine": Vector3(-1.25, 0, 0), "neck": Vector3(0.75, 0, 0),
				"l_hip": Vector3(0.1, 0, -0.25), "r_hip": Vector3(0.1, 0, 0.25),
				"l_kn": Vector3(-1.6, 0, 0), "r_kn": Vector3(-1.6, 0, 0),
				"l_sh": Vector3(1.55, 0, 0.05), "l_el": Vector3(0.1, 0, 0),
				"r_sh": Vector3(0.6, 0, -0.4), "r_el": Vector3(0.8, 0, 0)}
			return {"atk": [a, _xf(Vector3.ZERO, 0.0)], "def": [d, _xf(Vector3(0, 0, -0.5), PI)]}
		"leglock":
			# attacker sits past the feet hugging one leg; defender flat, leg trapped
			var d := {"hip_h": 0.17, "hip_rot": LYING, "neck": Vector3(-0.45, 0, 0),
				"l_hip": Vector3(0.75, 0, -0.05), "l_kn": Vector3(-0.05, 0, 0),
				"r_hip": Vector3(0.45, 0, 0.25), "r_kn": Vector3(-1.2, 0, 0),
				"l_sh": Vector3(0.9, 0, 0.5), "r_sh": Vector3(0.9, 0, -0.5), "l_el": Vector3(0.6, 0, 0), "r_el": Vector3(0.6, 0, 0)}
			var a := {"hip_h": 0.24, "spine": Vector3(0.75, 0, 0), "neck": Vector3(-0.35, 0, 0),
				"l_hip": Vector3(1.35, 0, -0.35), "r_hip": Vector3(1.25, 0, 0.3),
				"l_kn": Vector3(-0.5, 0, 0), "r_kn": Vector3(-0.9, 0, 0),
				"l_sh": Vector3(1.0, 0, 0.55), "r_sh": Vector3(1.0, 0, -0.55), "l_el": Vector3(1.9, 0, 0), "r_el": Vector3(1.9, 0, 0)}
			return {"atk": [a, _xf(Vector3(0.0, 0, -1.25), PI)], "def": [d, _xf(Vector3.ZERO, 0.0)]}
		"omoplata":
			var a := {"hip_h": 0.2, "hip_rot": Vector3(PI / 2, 0, 0.9), "neck": Vector3(-0.3, 0, 0),
				"l_hip": Vector3(1.5, 0, -0.6), "r_hip": Vector3(0.9, 0, 0.3),
				"l_kn": Vector3(-1.9, 0, 0), "r_kn": Vector3(-1.2, 0, 0),
				"l_sh": Vector3(1.1, 0, 0.6), "r_sh": Vector3(1.3, 0, -0.2),
				"l_el": Vector3(1.2, 0, 0), "r_el": Vector3(1.0, 0, 0)}
			var d := {"hip_h": 0.38, "spine": Vector3(-1.45, 0, 0.3), "neck": Vector3(0.6, 0, 0),
				"l_hip": Vector3(0.3, 0, -0.3), "r_hip": Vector3(0.3, 0, 0.3),
				"l_kn": Vector3(-1.4, 0, 0), "r_kn": Vector3(-1.4, 0, 0),
				"l_sh": Vector3(0.4, 0, 1.2), "l_el": Vector3(1.7, 0, 0),
				"r_sh": Vector3(1.4, 0, -0.2), "r_el": Vector3(0.3, 0, 0)}
			return {"atk": [a, _xf(Vector3.ZERO, 0.0)], "def": [d, _xf(Vector3(0.25, 0, -0.45), PI + 0.5)]}
	# families that keep the current position and change the arms
	var base := get_pair(pos)
	var at: Array = base.top if atk_top else base.bottom
	var de: Array = base.bottom if atk_top else base.top
	var a2: Dictionary = (at[0] as Dictionary).duplicate()
	var d2: Dictionary = (de[0] as Dictionary).duplicate()
	match fam:
		"back_choke":
			a2.merge({"l_sh": Vector3(1.7, 0, 1.05), "l_el": Vector3(1.9, 0, 0), "r_sh": Vector3(2.1, 0, -0.5), "r_el": Vector3(2.1, 0, 0), "neck": Vector3(0.25, 0, 0)}, true)
			d2.merge({"l_sh": Vector3(2.3, 0, 0.45), "l_el": Vector3(2.0, 0, 0), "r_sh": Vector3(2.3, 0, -0.45), "r_el": Vector3(2.0, 0, 0), "neck": Vector3(-0.35, 0, 0)}, true)
		"collar":
			a2.merge({"spine": Vector3(-0.65, 0, 0), "l_sh": Vector3(1.5, 0, 0.45), "l_el": Vector3(1.7, 0, 0), "r_sh": Vector3(1.5, 0, -0.45), "r_el": Vector3(1.7, 0, 0)}, true)
			d2.merge({"l_sh": Vector3(1.9, 0, 0.2), "l_el": Vector3(0.5, 0, 0), "r_sh": Vector3(1.9, 0, -0.2), "r_el": Vector3(0.5, 0, 0), "neck": Vector3(-0.45, 0, 0)}, true)
		"keylock":
			a2.merge({"spine": Vector3(-0.7, 0, 0.2), "l_sh": Vector3(1.2, 0, 0.7), "l_el": Vector3(1.8, 0, 0), "r_sh": Vector3(1.0, 0, -0.4), "r_el": Vector3(1.6, 0, 0)}, true)
			d2.merge({"r_sh": Vector3(0.4, 0, -1.5), "r_el": Vector3(1.7, 0, 0), "neck": Vector3(-0.2, 0, 0.3)}, true)
		"headlock":
			a2.merge({"spine": Vector3(-1.1, 0, 0), "l_sh": Vector3(1.5, 0, 0.85), "l_el": Vector3(2.0, 0, 0), "r_sh": Vector3(1.5, 0, -0.85), "r_el": Vector3(2.0, 0, 0)}, true)
			d2.merge({"neck": Vector3(0.6, 0, 0), "l_sh": Vector3(1.6, 0, 0.1), "l_el": Vector3(0.6, 0, 0)}, true)
	return {"atk": [a2, at[1]], "def": [d2, de[1]]}

## The defender's free hand taps three times.
static func tap_frames(pose: Dictionary, root: Transform3D) -> Array:
	var up := pose.duplicate()
	up["l_sh"] = Vector3(2.2, 0, 0.6)
	up["l_el"] = Vector3(0.6, 0, 0)
	var down := pose.duplicate()
	down["l_sh"] = Vector3(1.3, 0, 0.5)
	down["l_el"] = Vector3(0.2, 0, 0)
	var out: Array = []
	for i in 3:
		out.append([up, root, 0.12])
		out.append([down, root, 0.1])
	return out
