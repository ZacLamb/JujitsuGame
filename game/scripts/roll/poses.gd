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
			return {"top": [stance, _xf(Vector3(0, 0, 0.42), 0.0)],
				"bottom": [stance, _xf(Vector3(0, 0, -0.42), PI)]}
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
