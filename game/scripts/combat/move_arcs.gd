class_name MoveArcs
extends RefCounted
## How each technique travels from one position to the next, so a double leg, a hip throw, a trip
## and a guard pull stop looking like the same move. Posed from real footage (Cáceres Jiu-Jitsu,
## Nov 2026): level change and drive for shots, turn-in and load for throws, foot on the hip and
## sit for the guard pull, stand-and-step-around for the toreando, knee through for the knee cut.
##
## An arc is {"actor": [stage...], "other": [stage...], "flip": bool, "land": seconds}.
## A stage: {"k": how far the root has travelled to the final spot (0..1), "d": seconds,
##   "pose": full pose (replaces the blend), "add": deltas on the blend toward the final pose,
##   "pk": pose blend (defaults to k), "meet": 0..1 pull toward the midpoint between the two, "lift"/"side"/"drive": root offsets, "roll": about the line
##   between the two, "face": yaw relative to facing the partner}.

const FAMILY := {
	"double_leg": "shot", "blast_double": "shot", "body_lock_td": "bodylock",
	"single_leg": "single", "high_crotch": "single", "ankle_pick": "ankle",
	"o_goshi": "throw", "seoi_nage": "throw", "harai_goshi": "reap_throw", "uchi_mata": "reap_throw",
	"osoto_gari": "trip", "sumi_gaeshi": "sacrifice", "pull_guard": "pull",
	"snap_down": "snap", "kuzushi_snap": "snap",
	"toreando": "toreando", "x_pass": "toreando", "leg_drag": "toreando",
	"knee_cut_half": "kneecut", "knee_slice": "kneecut",
	"stack_pass": "stack", "over_under": "stack", "smash_pass": "smash",
	"scissor_sweep": "scissor", "hip_bump": "hipbump", "flower_sweep": "pendulum", "lasso_sweep": "pendulum",
	"lumberjack": "hipbump", "upa": "upa", "old_school": "comeup", "deep_half": "comeup"}

static func family(mv: String) -> String:
	return str(FAMILY.get(mv, ""))

static func _s() -> Dictionary:
	return CombatAnim.stance()

static func _m(base: Dictionary, over: Dictionary) -> Dictionary:
	var p := base.duplicate()
	p.merge(over, true)
	return p

static func arc(mv: String) -> Dictionary:
	var s := _s()
	match family(mv):
		"shot":
			# level change, penetration step with the lead knee down, drive through both legs
			var dip := _m(s, {"hip_h": 0.62, "spine": Vector3(-0.65, 0, 0), "l_kn": Vector3(-1.15, 0, 0), "r_kn": Vector3(-0.95, 0, 0),
				"l_sh": Vector3(1.2, 0, 0.2), "r_sh": Vector3(1.2, 0, -0.2), "l_el": Vector3(0.6, 0, 0), "r_el": Vector3(0.6, 0, 0)})
			var pen := {"hip_h": 0.5, "spine": Vector3(-1.0, 0, 0), "neck": Vector3(0.6, 0, 0),
				"l_hip": Vector3(1.25, 0, -0.1), "l_kn": Vector3(-1.7, 0, 0), "r_hip": Vector3(-0.4, 0, 0.1), "r_kn": Vector3(-0.55, 0, 0),
				"l_sh": Vector3(1.3, 0, 0.5), "r_sh": Vector3(1.3, 0, -0.5), "l_el": Vector3(1.1, 0, 0), "r_el": Vector3(1.1, 0, 0)}
			var scooped := {"hip_h": 0.62, "hip_rot": Vector3(0.5, 0, 0), "spine": Vector3(-0.5, 0, 0), "neck": Vector3(0.2, 0, 0),
				"l_hip": Vector3(0.55, 0, -0.12), "r_hip": Vector3(0.45, 0, 0.12), "l_kn": Vector3(-0.3, 0, 0), "r_kn": Vector3(-0.4, 0, 0),
				"l_sh": Vector3(1.5, 0, -0.9), "r_sh": Vector3(1.5, 0, 0.9), "l_el": Vector3(0.3, 0, 0), "r_el": Vector3(0.3, 0, 0)}
			var react := _m(s, {"hip_h": 0.8, "spine": Vector3(-0.5, 0, 0), "l_sh": Vector3(0.7, 0, 0.1), "r_sh": Vector3(0.7, 0, -0.1), "l_el": Vector3(0.5, 0, 0), "r_el": Vector3(0.5, 0, 0)})
			return {"actor": [{"k": 0.08, "d": 0.16, "pose": dip}, {"k": 0.3, "d": 0.2, "pose": pen, "meet": 1.0, "drive": 0.3}],
				"other": [{"k": 0.0, "d": 0.16, "pose": react}, {"k": 0.0, "d": 0.2, "pose": scooped, "lift": 0.05}], "land": 0.62}
		"bodylock":
			# chest to chest, hands locked low around the waist, step outside and fold them backward
			var lock := _m(s, {"hip_h": 0.76, "spine": Vector3(-0.3, 0, 0), "l_sh": Vector3(1.05, 0, 0.55), "r_sh": Vector3(1.05, 0, -0.55),
				"l_el": Vector3(1.3, 0, 0), "r_el": Vector3(1.3, 0, 0), "l_kn": Vector3(-0.9, 0, 0), "r_kn": Vector3(-0.8, 0, 0)})
			var fold := _m(lock, {"hip_h": 0.6, "spine": Vector3(-0.75, 0, 0), "l_hip": Vector3(0.9, 0, -0.3), "l_kn": Vector3(-1.3, 0, 0)})
			var bent := {"hip_h": 0.78, "hip_rot": Vector3(0.6, 0, 0), "spine": Vector3(0.35, 0, 0), "neck": Vector3(-0.2, 0, 0),
				"l_hip": Vector3(0.7, 0, -0.2), "r_hip": Vector3(0.5, 0, 0.2), "l_kn": Vector3(-0.9, 0, 0), "r_kn": Vector3(-0.8, 0, 0),
				"l_sh": Vector3(1.3, 0, -0.6), "r_sh": Vector3(1.3, 0, 0.6), "l_el": Vector3(0.5, 0, 0), "r_el": Vector3(0.5, 0, 0)}
			return {"actor": [{"k": 0.35, "d": 0.2, "pose": lock}, {"k": 0.6, "d": 0.22, "pose": fold, "side": 0.2}],
				"other": [{"k": 0.05, "d": 0.2, "pose": _m(s, {"spine": Vector3(0.05, 0, 0), "hip_h": 0.88})}, {"k": 0.5, "d": 0.22, "pose": bent}], "land": 0.66}
		"single":
			# head inside, one leg hugged high; they hop on the other foot, then get run down
			var dip := _m(s, {"hip_h": 0.66, "spine": Vector3(-0.6, 0, 0), "l_kn": Vector3(-1.05, 0, 0), "r_kn": Vector3(-0.9, 0, 0)})
			var hug := {"hip_h": 0.68, "spine": Vector3(-0.6, 0, 0.15), "neck": Vector3(0.4, 0, 0),
				"l_hip": Vector3(0.75, 0, -0.25), "l_kn": Vector3(-1.1, 0, 0), "r_hip": Vector3(-0.25, 0, 0.2), "r_kn": Vector3(-0.6, 0, 0),
				"l_sh": Vector3(1.0, 0, 0.45), "r_sh": Vector3(1.0, 0, -0.45), "l_el": Vector3(1.7, 0, 0), "r_el": Vector3(1.7, 0, 0)}
			var hop := _m(s, {"hip_h": 0.9, "spine": Vector3(-0.5, 0, 0), "l_hip": Vector3(1.35, 0, -0.1), "l_kn": Vector3(-0.45, 0, 0),
				"r_hip": Vector3(0.0, 0, 0.1), "r_kn": Vector3(-0.2, 0, 0),
				"l_sh": Vector3(1.25, 0, 0.2), "r_sh": Vector3(1.25, 0, -0.2), "l_el": Vector3(0.5, 0, 0), "r_el": Vector3(0.5, 0, 0)})
			var tip := _m(hop, {"hip_h": 0.72, "hip_rot": Vector3(0.6, 0, 0.25), "l_sh": Vector3(1.4, 0, -0.8), "r_sh": Vector3(1.4, 0, 0.8)})
			return {"actor": [{"k": 0.1, "d": 0.14, "pose": dip}, {"k": 0.45, "d": 0.2, "pose": hug, "side": 0.15}, {"k": 0.7, "d": 0.18, "pose": hug, "drive": 0.15}],
				"other": [{"k": 0.0, "d": 0.14}, {"k": 0.1, "d": 0.2, "pose": hop}, {"k": 0.45, "d": 0.18, "pose": tip}], "land": 0.78}
		"ankle":
			# collar hand snaps them forward, the other hand picks the ankle off the mat
			var pick := {"hip_h": 0.42, "spine": Vector3(-1.15, 0, 0), "neck": Vector3(0.7, 0, 0),
				"l_hip": Vector3(1.3, 0, -0.1), "l_kn": Vector3(-1.9, 0, 0), "r_hip": Vector3(-0.3, 0, 0.1), "r_kn": Vector3(-1.2, 0, 0),
				"l_sh": Vector3(1.15, 0, 0.1), "l_el": Vector3(0.1, 0, 0), "r_sh": Vector3(1.9, 0, -0.2), "r_el": Vector3(0.4, 0, 0)}
			var sat := {"hip_h": 0.4, "hip_rot": Vector3(0.7, 0, 0), "spine": Vector3(-0.2, 0, 0), "neck": Vector3(0.2, 0, 0),
				"l_hip": Vector3(1.35, 0, -0.1), "l_kn": Vector3(-0.2, 0, 0), "r_hip": Vector3(0.6, 0, 0.15), "r_kn": Vector3(-1.2, 0, 0),
				"l_sh": Vector3(-0.5, 0, -0.3), "r_sh": Vector3(-0.5, 0, 0.3), "l_el": Vector3(0.2, 0, 0), "r_el": Vector3(0.2, 0, 0)}
			return {"actor": [{"k": 0.1, "d": 0.14, "pose": _m(s, {"l_sh": Vector3(1.7, 0, 0.1), "l_el": Vector3(0.5, 0, 0), "spine": Vector3(-0.45, 0, 0)})}, {"k": 0.5, "d": 0.2, "pose": pick}],
				"other": [{"k": 0.0, "d": 0.14, "pose": _m(s, {"spine": Vector3(-0.6, 0, 0)})}, {"k": 0.35, "d": 0.2, "pose": sat}], "land": 0.6}
		"throw", "reap_throw":
			# turn in with your back to them, load them on the hips, bend and they go over the top
			var reap := family(mv) == "reap_throw"
			var turn_in := {"hip_h": 0.68, "spine": Vector3(-0.25, 0, 0), "neck": Vector3(0.15, 0, 0),
				"l_hip": Vector3(0.5, 0, -0.3), "r_hip": Vector3(0.5, 0, 0.3), "l_kn": Vector3(-1.0, 0, 0), "r_kn": Vector3(-1.0, 0, 0),
				"l_sh": Vector3(1.9, 0, 0.3), "l_el": Vector3(1.2, 0, 0), "r_sh": Vector3(0.5, 0, 0.9), "r_el": Vector3(1.1, 0, 0)}
			var load := {"hip_h": 0.78, "spine": Vector3(-1.2, 0, 0), "neck": Vector3(0.3, 0, 0),
				"l_hip": Vector3(0.95, 0, -0.3), "r_hip": Vector3(0.95, 0, 0.3), "l_kn": Vector3(-0.4, 0, 0), "r_kn": Vector3(-0.4, 0, 0),
				"l_sh": Vector3(1.1, 0, 0.4), "l_el": Vector3(1.4, 0, 0), "r_sh": Vector3(0.9, 0, 0.5), "r_el": Vector3(1.2, 0, 0)}
			if reap:
				load = _m(load, {"hip_h": 0.82, "spine": Vector3(-1.3, 0, 0), "r_hip": Vector3(-0.75, 0, 0.15), "r_kn": Vector3(-0.1, 0, 0), "l_kn": Vector3(-0.3, 0, 0)})
			var pulled := _m(s, {"hip_h": 0.92, "spine": Vector3(-0.6, 0, 0), "l_sh": Vector3(1.5, 0, 0.1), "r_sh": Vector3(1.5, 0, -0.1),
				"l_el": Vector3(0.3, 0, 0), "r_el": Vector3(0.3, 0, 0), "l_kn": Vector3(-0.2, 0, 0), "r_kn": Vector3(-0.2, 0, 0)})
			var over := {"hip_h": 1.12, "hip_rot": Vector3(-1.55, 0, 0), "spine": Vector3(-0.3, 0, 0), "neck": Vector3(0.3, 0, 0),
				"l_hip": Vector3(0.35, 0, -0.2), "r_hip": Vector3(-0.2, 0, 0.2), "l_kn": Vector3(-0.4, 0, 0), "r_kn": Vector3(-0.3, 0, 0),
				"l_sh": Vector3(1.6, 0, 0.2), "r_sh": Vector3(1.6, 0, -0.2), "l_el": Vector3(0.3, 0, 0), "r_el": Vector3(0.3, 0, 0)}
			var falling := _m(over, {"hip_h": 0.8, "hip_rot": Vector3(-3.3, 0, 0), "l_hip": Vector3(1.0, 0, -0.2), "r_hip": Vector3(0.8, 0, 0.2)})
			return {"actor": [{"k": 0.2, "d": 0.2, "pose": turn_in, "meet": 0.9, "face": PI * 0.85}, {"k": 0.2, "d": 0.2, "pose": load, "meet": 0.9, "face": PI * 0.85},
					{"k": 0.4, "d": 0.16, "pose": load, "meet": 0.6, "face": PI * 0.5}],
				"other": [{"k": 0.1, "d": 0.2, "pose": pulled, "meet": 0.6}, {"k": 0.2, "d": 0.2, "pose": over, "meet": 1.0, "drive": 0.15}, {"k": 0.8, "d": 0.16, "pose": falling}],
				"flip": true, "land": 0.72}
		"trip":
			# chest to chest, the reaping leg swings past and then cuts their leg out backward
			var step := _m(s, {"hip_h": 0.86, "spine": Vector3(-0.1, 0, 0), "r_hip": Vector3(1.1, 0, 0.1), "r_kn": Vector3(-0.2, 0, 0), "l_kn": Vector3(-0.5, 0, 0),
				"l_sh": Vector3(1.5, 0, 0.2), "l_el": Vector3(0.9, 0, 0), "r_sh": Vector3(1.6, 0, -0.2), "r_el": Vector3(0.7, 0, 0)})
			var reap_p := _m(step, {"hip_h": 0.84, "spine": Vector3(-0.8, 0, 0), "r_hip": Vector3(-0.95, 0, 0.1), "r_kn": Vector3(-0.1, 0, 0),
				"l_sh": Vector3(1.0, 0, 0.2), "r_sh": Vector3(1.0, 0, -0.2)})
			var tipped := {"hip_h": 0.7, "hip_rot": Vector3(0.85, 0, 0), "spine": Vector3(0.1, 0, 0), "neck": Vector3(0.3, 0, 0),
				"l_hip": Vector3(1.25, 0, -0.15), "l_kn": Vector3(-0.2, 0, 0), "r_hip": Vector3(0.3, 0, 0.15), "r_kn": Vector3(-0.7, 0, 0),
				"l_sh": Vector3(1.6, 0, -0.9), "r_sh": Vector3(1.6, 0, 0.9), "l_el": Vector3(0.3, 0, 0), "r_el": Vector3(0.3, 0, 0)}
			return {"actor": [{"k": 0.45, "d": 0.2, "pose": step, "side": -0.15}, {"k": 0.55, "d": 0.18, "pose": reap_p}],
				"other": [{"k": 0.05, "d": 0.2, "pose": _m(s, {"spine": Vector3(0.15, 0, 0), "hip_h": 0.86})}, {"k": 0.45, "d": 0.18, "pose": tipped}], "land": 0.6}
		"sacrifice":
			# sit under them, foot in the hip, and throw them overhead as you roll up on top
			var sit := {"hip_h": 0.3, "hip_rot": Vector3(0.9, 0, 0), "spine": Vector3(-0.3, 0, 0), "neck": Vector3(0.2, 0, 0),
				"l_hip": Vector3(1.5, 0, -0.1), "l_kn": Vector3(-1.2, 0, 0), "r_hip": Vector3(1.2, 0, 0.2), "r_kn": Vector3(-1.4, 0, 0),
				"l_sh": Vector3(1.6, 0, 0.2), "r_sh": Vector3(1.6, 0, -0.2), "l_el": Vector3(0.8, 0, 0), "r_el": Vector3(0.8, 0, 0)}
			var kick := _m(sit, {"hip_h": 0.2, "hip_rot": Vector3(1.55, 0, 0), "l_hip": Vector3(1.9, 0, -0.1), "l_kn": Vector3(-0.3, 0, 0)})
			var over := {"hip_h": 1.0, "hip_rot": Vector3(-1.6, 0, 0), "spine": Vector3(-0.3, 0, 0), "l_hip": Vector3(0.3, 0, -0.2), "r_hip": Vector3(0.1, 0, 0.2),
				"l_kn": Vector3(-0.4, 0, 0), "r_kn": Vector3(-0.4, 0, 0), "l_sh": Vector3(1.6, 0, 0.2), "r_sh": Vector3(1.6, 0, -0.2)}
			return {"actor": [{"k": 0.3, "d": 0.22, "pose": sit}, {"k": 0.4, "d": 0.18, "pose": kick}],
				"other": [{"k": 0.25, "d": 0.22, "pose": _m(s, {"spine": Vector3(-0.8, 0, 0)})}, {"k": 0.55, "d": 0.18, "pose": over},
					{"k": 0.85, "d": 0.16, "pose": _m(over, {"hip_h": 0.6, "hip_rot": Vector3(-3.4, 0, 0)})}], "flip": true, "land": 0.74}
		"pull":
			# collar and sleeve, foot on the hip, sit and bring them down into the guard
			var foot := _m(s, {"hip_h": 0.84, "spine": Vector3(0.1, 0, 0), "l_hip": Vector3(1.25, 0, -0.05), "l_kn": Vector3(-1.0, 0, 0), "r_kn": Vector3(-0.5, 0, 0),
				"l_sh": Vector3(1.5, 0, 0.15), "r_sh": Vector3(1.5, 0, -0.15), "l_el": Vector3(0.8, 0, 0), "r_el": Vector3(0.8, 0, 0)})
			var sit := {"hip_h": 0.32, "hip_rot": Vector3(0.7, 0, 0), "spine": Vector3(-0.3, 0, 0), "neck": Vector3(0.1, 0, 0),
				"l_hip": Vector3(1.4, 0, -0.3), "r_hip": Vector3(1.2, 0, 0.3), "l_kn": Vector3(-1.3, 0, 0), "r_kn": Vector3(-1.5, 0, 0),
				"l_sh": Vector3(1.4, 0, 0.2), "r_sh": Vector3(1.4, 0, -0.2), "l_el": Vector3(1.2, 0, 0), "r_el": Vector3(1.2, 0, 0)}
			var bowed := _m(s, {"spine": Vector3(-0.65, 0, 0), "l_sh": Vector3(1.3, 0, 0.1), "r_sh": Vector3(1.3, 0, -0.1)})
			var knees := {"hip_h": 0.56, "spine": Vector3(-0.7, 0, 0), "neck": Vector3(0.4, 0, 0), "l_hip": Vector3(0.6, 0, -0.2), "r_hip": Vector3(0.25, 0, 0.2),
				"l_kn": Vector3(-1.4, 0, 0), "r_kn": Vector3(-1.5, 0, 0), "l_sh": Vector3(1.0, 0, 0.15), "r_sh": Vector3(1.0, 0, -0.15), "l_el": Vector3(0.4, 0, 0), "r_el": Vector3(0.4, 0, 0)}
			return {"actor": [{"k": 0.25, "d": 0.24, "pose": foot}, {"k": 0.7, "d": 0.22, "pose": sit}],
				"other": [{"k": 0.2, "d": 0.24, "pose": bowed}, {"k": 0.7, "d": 0.22, "pose": knees}], "land": 0.0}
		"snap":
			# hands on the collar, yank the head to the mat and circle behind
			var up := _m(s, {"l_sh": Vector3(1.7, 0, 0.15), "r_sh": Vector3(1.7, 0, -0.15), "l_el": Vector3(0.6, 0, 0), "r_el": Vector3(0.6, 0, 0)})
			var yank := _m(s, {"hip_h": 0.76, "spine": Vector3(-0.5, 0, 0), "l_sh": Vector3(0.7, 0, 0.15), "r_sh": Vector3(0.7, 0, -0.15), "l_el": Vector3(0.3, 0, 0), "r_el": Vector3(0.3, 0, 0)})
			var down := {"hip_h": 0.43, "spine": Vector3(-1.5, 0, 0), "neck": Vector3(0.1, 0, 0), "l_hip": Vector3(0.25, 0, -0.2), "r_hip": Vector3(0.15, 0, 0.2),
				"l_kn": Vector3(-1.75, 0, 0), "r_kn": Vector3(-1.7, 0, 0), "l_sh": Vector3(1.45, 0, 0.35), "r_sh": Vector3(1.45, 0, -0.35), "l_el": Vector3(0.75, 0, 0), "r_el": Vector3(0.75, 0, 0)}
			return {"actor": [{"k": 0.1, "d": 0.14, "pose": up}, {"k": 0.5, "d": 0.2, "pose": yank, "side": 0.5}],
				"other": [{"k": 0.0, "d": 0.14}, {"k": 0.35, "d": 0.2, "pose": down}], "land": 0.0}
		"toreando":
			# stand up bent over their legs, pin the knees, throw them aside and step around
			var stand := {"hip_h": 0.74, "spine": Vector3(-1.0, 0, 0), "neck": Vector3(0.5, 0, 0),
				"l_hip": Vector3(0.6, 0, -0.3), "r_hip": Vector3(0.6, 0, 0.3), "l_kn": Vector3(-0.75, 0, 0), "r_kn": Vector3(-0.75, 0, 0),
				"l_sh": Vector3(0.95, 0, 0.1), "r_sh": Vector3(0.95, 0, -0.1), "l_el": Vector3(0.15, 0, 0), "r_el": Vector3(0.15, 0, 0)}
			var step := _m(stand, {"l_hip": Vector3(0.95, 0, -0.45), "r_hip": Vector3(0.2, 0, 0.2), "l_sh": Vector3(0.95, 0, 0.5), "r_sh": Vector3(0.95, 0, 0.3)})
			return {"actor": [{"k": 0.1, "d": 0.22, "pose": stand, "drive": -0.2}, {"k": 0.6, "d": 0.24, "pose": step, "side": 0.55}],
				"other": [{"k": 0.15, "d": 0.22, "add": {"hip_rot": Vector3(0, 0, 0.45), "l_kn": Vector3(-0.2, 0, 0), "r_kn": Vector3(-0.2, 0, 0)}},
					{"k": 0.6, "d": 0.24, "add": {"hip_rot": Vector3(0, 0, 0.85), "l_hip": Vector3(0.3, 0, 0), "r_hip": Vector3(0.3, 0, 0)}}], "land": 0.0}
		"kneecut":
			# one foot planted, the other knee slices down across their thigh to the mat
			var post := {"hip_h": 0.56, "spine": Vector3(-0.55, 0, 0), "neck": Vector3(0.35, 0, 0),
				"l_hip": Vector3(1.3, 0, -0.45), "l_kn": Vector3(-1.6, 0, 0), "r_hip": Vector3(0.35, 0, 0.1), "r_kn": Vector3(-1.9, 0, 0),
				"l_sh": Vector3(1.3, 0, 0.3), "l_el": Vector3(0.9, 0, 0), "r_sh": Vector3(1.0, 0, -0.2), "r_el": Vector3(0.5, 0, 0)}
			var slice := _m(post, {"hip_h": 0.42, "spine": Vector3(-1.0, 0, 0), "neck": Vector3(0.6, 0, 0), "l_hip": Vector3(0.9, 0, -0.5), "r_hip": Vector3(0.1, 0, 0.2), "r_kn": Vector3(-1.2, 0, 0)})
			return {"actor": [{"k": 0.25, "d": 0.22, "pose": post, "side": 0.15}, {"k": 0.7, "d": 0.22, "pose": slice}],
				"other": [{"k": 0.25, "d": 0.22, "add": {"hip_rot": Vector3(0, 0, 0.4)}}, {"k": 0.7, "d": 0.22, "add": {"hip_rot": Vector3(0, 0, 0.6)}}], "land": 0.0}
		"stack":
			# arms under the legs, drive forward and fold their knees over their own face
			var under := {"hip_h": 0.5, "spine": Vector3(-0.9, 0, 0), "neck": Vector3(0.5, 0, 0), "l_hip": Vector3(0.9, 0, -0.3), "r_hip": Vector3(0.9, 0, 0.3),
				"l_kn": Vector3(-1.5, 0, 0), "r_kn": Vector3(-1.5, 0, 0), "l_sh": Vector3(1.0, 0, 0.5), "r_sh": Vector3(1.0, 0, -0.5), "l_el": Vector3(1.5, 0, 0), "r_el": Vector3(1.5, 0, 0)}
			var drive := _m(under, {"hip_h": 0.68, "spine": Vector3(-1.2, 0, 0), "l_hip": Vector3(0.25, 0, -0.3), "r_hip": Vector3(0.25, 0, 0.3), "l_kn": Vector3(-0.45, 0, 0), "r_kn": Vector3(-0.45, 0, 0)})
			return {"actor": [{"k": 0.1, "d": 0.24, "pose": under, "drive": 0.15}, {"k": 0.4, "d": 0.22, "pose": drive, "drive": 0.25}],
				"other": [{"k": 0.1, "d": 0.24, "pk": 0.0, "add": {"hip_rot": Vector3(0.45, 0, 0), "hip_h": 0.15, "l_hip": Vector3(0.5, 0, 0), "r_hip": Vector3(0.5, 0, 0), "l_kn": Vector3(0.9, 0, 0), "r_kn": Vector3(0.9, 0, 0)}},
					{"k": 0.4, "d": 0.22, "pk": 0.0, "add": {"hip_rot": Vector3(0.8, 0, 0), "hip_h": 0.28, "l_hip": Vector3(0.8, 0, 0), "r_hip": Vector3(0.8, 0, 0), "l_kn": Vector3(1.3, 0, 0), "r_kn": Vector3(1.3, 0, 0)}}], "land": 0.0}
		"smash":
			# hips down and heavy, flatten their knees to one side and walk the chest over
			var flat := {"hip_h": 0.34, "spine": Vector3(-1.15, 0, 0), "neck": Vector3(0.75, 0, 0), "l_hip": Vector3(-0.75, 0, -0.4), "r_hip": Vector3(-0.7, 0, 0.4),
				"l_kn": Vector3(-0.15, 0, 0), "r_kn": Vector3(-0.15, 0, 0), "l_sh": Vector3(1.5, 0, 0.45), "r_sh": Vector3(1.5, 0, -0.45), "l_el": Vector3(0.9, 0, 0), "r_el": Vector3(0.9, 0, 0)}
			return {"actor": [{"k": 0.35, "d": 0.28, "pose": flat}, {"k": 0.7, "d": 0.2, "pose": flat, "side": 0.15}],
				"other": [{"k": 0.35, "d": 0.28, "add": {"hip_rot": Vector3(0, 0, 0.8)}}, {"k": 0.7, "d": 0.2, "add": {"hip_rot": Vector3(0, 0, 0.5)}}], "land": 0.0}
		"scissor":
			# on one hip, top shin across the belly, bottom leg chops their knee out
			return {"actor": [{"k": 0.1, "d": 0.2, "pk": 0.0, "add": {"hip_rot": Vector3(0, 0, 0.8), "l_hip": Vector3(-0.2, 0, 0.3), "l_kn": Vector3(0.5, 0, 0), "r_hip": Vector3(-1.0, 0, 0), "r_kn": Vector3(1.4, 0, 0)}},
					{"k": 0.5, "d": 0.22, "pk": 0.3, "add": {"hip_rot": Vector3(0, 0, 0.5), "r_hip": Vector3(0.4, 0, 0), "lift": 0.0}}],
				"other": [{"k": 0.1, "d": 0.2, "pk": 0.0, "add": {"spine": Vector3(-0.45, 0, 0), "l_sh": Vector3(0.4, 0, 0), "r_sh": Vector3(0.4, 0, 0)}},
					{"k": 0.5, "d": 0.22, "lift": 0.2, "roll": 1.15, "add": {"l_sh": Vector3(0, 0, -0.8), "r_sh": Vector3(0, 0, 0.8)}}], "land": 0.62}
		"hipbump", "comeup":
			# sit up into them, post a hand behind, and bump the hips through
			var situp := {"hip_h": 0.34, "hip_rot": Vector3(0.45, 0, 0.35), "spine": Vector3(-0.35, 0, 0), "neck": Vector3(0.15, 0, 0),
				"l_hip": Vector3(1.0, 0, -0.4), "r_hip": Vector3(1.0, 0, 0.4), "l_kn": Vector3(-1.6, 0, 0), "r_kn": Vector3(-1.6, 0, 0),
				"l_sh": Vector3(1.9, 0, 0.3), "l_el": Vector3(1.0, 0, 0), "r_sh": Vector3(-0.6, 0, -0.2), "r_el": Vector3(0.1, 0, 0)}
			var bump := _m(situp, {"hip_h": 0.6, "hip_rot": Vector3(-0.1, 0, 0.5), "l_hip": Vector3(0.3, 0, -0.4), "r_hip": Vector3(0.3, 0, 0.4)})
			return {"actor": [{"k": 0.15, "d": 0.22, "pose": situp}, {"k": 0.55, "d": 0.2, "pose": bump}],
				"other": [{"k": 0.05, "d": 0.22, "pk": 0.0, "add": {"spine": Vector3(0.3, 0, 0)}},
					{"k": 0.5, "d": 0.2, "pk": 0.4, "add": {"hip_rot": Vector3(0.5, 0, 0), "l_sh": Vector3(0, 0, -0.7), "r_sh": Vector3(0, 0, 0.7)}}], "land": 0.6}
		"pendulum":
			# one leg swings wide like a pendulum and they tip over the trapped arm
			return {"actor": [{"k": 0.1, "d": 0.22, "pk": 0.0, "add": {"hip_rot": Vector3(0, 0, -0.5), "l_hip": Vector3(0.2, 0, -1.0), "l_kn": Vector3(1.6, 0, 0), "r_hip": Vector3(0.3, 0, 0)}},
					{"k": 0.5, "d": 0.22, "pk": 0.3, "add": {"hip_rot": Vector3(0, 0, 0.5), "l_hip": Vector3(-0.6, 0, 0.3), "l_kn": Vector3(1.2, 0, 0)}}],
				"other": [{"k": 0.1, "d": 0.22, "pk": 0.0, "add": {"spine": Vector3(-0.5, 0, 0)}},
					{"k": 0.5, "d": 0.22, "lift": 0.35, "roll": 1.3, "add": {"l_sh": Vector3(0, 0, -0.8), "r_sh": Vector3(0, 0, 0.8)}}], "land": 0.64}
		"upa":
			# trap an arm and a foot, bridge the hips high and roll them over a shoulder
			return {"actor": [{"k": 0.0, "d": 0.2, "pk": 0.0, "add": {"hip_h": 0.36, "hip_rot": Vector3(-0.4, 0, 0), "l_hip": Vector3(-0.3, 0, 0), "r_hip": Vector3(-0.3, 0, 0), "l_kn": Vector3(-0.9, 0, 0), "r_kn": Vector3(-0.9, 0, 0)}},
					{"k": 0.5, "d": 0.22, "pk": 0.4, "add": {"hip_h": 0.25, "hip_rot": Vector3(0, 0, 0.9)}}],
				"other": [{"k": 0.0, "d": 0.2, "pk": 0.0, "lift": 0.34, "add": {"spine": Vector3(-0.55, 0, 0), "l_sh": Vector3(0.6, 0, 0), "r_sh": Vector3(0.6, 0, 0)}},
					{"k": 0.5, "d": 0.22, "lift": 0.3, "roll": 1.2}], "land": 0.62}
	return {}

## Keyframes for one body: from where it is now, through the stages, to its final pose and spot.
## toward: direction to the partner in the rig's parent space.
static func frames(cur_pose: Dictionary, cur_root: Transform3D, stages: Array, pose: Dictionary, local: Transform3D, toward: Vector3, flip := false, last := 0.36) -> Array:
	var fwd := toward
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP)
	var out: Array = []
	for st in stages:
		var k := float(st.get("k", 0.5))
		var p: Dictionary
		if st.has("pose"):
			p = (st.pose as Dictionary).duplicate()
		else:
			p = BodyRig.lerp_pose(cur_pose, pose, float(st.get("pk", k)))
		var add: Dictionary = st.get("add", {})
		for key in add:
			if key == "hip_h":
				p.hip_h = float(p.get("hip_h", 0.95)) + float(add[key])
			elif add[key] is Vector3:
				p[key] = (p.get(key, Vector3.ZERO) as Vector3) + (add[key] as Vector3)
		var r: Transform3D = cur_root.interpolate_with(local, k)
		if st.has("meet"):
			# close the gap: toward the spot halfway between where the two of them started
			var m := cur_root.origin + Vector3(toward.x, 0, toward.z) * 0.5
			var o := r.origin.lerp(Vector3(m.x, r.origin.y, m.z), float(st.meet))
			r.origin = o
		r.origin += Vector3.UP * float(st.get("lift", 0.0)) + side * float(st.get("side", 0.0)) + fwd * float(st.get("drive", 0.0))
		if st.has("face"):
			r.basis = Basis(Vector3.UP, atan2(-fwd.x, -fwd.z) + float(st.face))
		if st.has("roll"):
			r.basis = Basis(fwd, float(st.roll)) * r.basis
		out.append([p, r, float(st.get("d", 0.2)), Tween.EASE_IN_OUT, Tween.TRANS_SINE])
	if flip:
		# thrown head over heels: keep turning the same way and land on the back, then quietly
		# swap to the equivalent un-wound rotation so the next move doesn't spin back
		var landed := pose.duplicate()
		var hr: Vector3 = landed.get("hip_rot", Vector3.ZERO)
		landed["hip_rot"] = Vector3(hr.x - TAU, hr.y, hr.z)
		out.append([landed, local, last, Tween.EASE_OUT])
		out.append([pose, local, 0.001])
	else:
		out.append([pose, local, last, Tween.EASE_OUT])
	return out
