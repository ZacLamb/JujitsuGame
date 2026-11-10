class_name Emotes
extends RefCounted
## Emotes (/oss, /wave, /cheer...): a short pose sequence on your fighter, seen by everyone in
## the zone (world.js 'emote'), and a line in nearby chat.

const LIST := {
	"oss": {"you": "You bow. Oss!", "them": "%s bows. Oss!", "cmds": ["/oss", "/bow"]},
	"wave": {"you": "You wave.", "them": "%s waves.", "cmds": ["/wave", "/hi"]},
	"cheer": {"you": "You cheer!", "them": "%s cheers!", "cmds": ["/cheer"]},
	"flex": {"you": "You flex. Strong.", "them": "%s flexes.", "cmds": ["/flex"]},
	"sit": {"you": "You sit down on the mat.", "them": "%s sits down on the mat.", "cmds": ["/sit"]},
	"stretch": {"you": "You stretch it out.", "them": "%s stretches.", "cmds": ["/stretch"]},
	"dance": {"you": "You dance. Ginga!", "them": "%s dances.", "cmds": ["/dance"]},
	"tap": {"you": "You tap the mat. Respect.", "them": "%s taps the mat.", "cmds": ["/tap"]},
	"shrimp": {"you": "You drill a shrimp.", "them": "%s drills a shrimp.", "cmds": ["/shrimp"]},
}

## Command -> emote id ("" if it isn't one).
static func from_cmd(cmd: String) -> String:
	for id in LIST:
		if (LIST[id].cmds as Array).has(cmd.to_lower()):
			return id
	return ""

static func _root(yaw: float, up := 0.0, fwd := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, yaw)
	return Transform3D(b, b * Vector3(0, up, -fwd))

static func _stand() -> Dictionary:
	return {"hip_h": 0.95, "spine": Vector3.ZERO, "neck": Vector3.ZERO, "l_sh": Vector3(0.05, 0, -0.12), "r_sh": Vector3(0.05, 0, 0.12),
		"l_el": Vector3(0.15, 0, 0), "r_el": Vector3(0.15, 0, 0)}

static func _m(over: Dictionary) -> Dictionary:
	var p := _stand()
	p.merge(over, true)
	return p

## BodyRig.action() frames for an emote, facing yaw.
static func frames(id: String, yaw: float) -> Array:
	var r := _root(yaw)
	var st := _stand()
	match id:
		"oss":
			var bow := _m({"spine": Vector3(-0.85, 0, 0), "neck": Vector3(-0.15, 0, 0), "hip_h": 0.92})
			return [[bow, r, 0.45], [bow, r, 0.9], [st, r, 0.45]]
		"wave":
			var a := _m({"r_sh": Vector3(0.25, 0, 2.45), "r_el": Vector3(0.9, 0, 0)})
			var b := _m({"r_sh": Vector3(0.25, 0, 2.05), "r_el": Vector3(1.3, 0, 0)})
			return [[a, r, 0.25], [b, r, 0.2], [a, r, 0.2], [b, r, 0.2], [a, r, 0.2], [st, r, 0.35]]
		"cheer":
			var up := _m({"l_sh": Vector3(0.2, 0, -2.7), "r_sh": Vector3(0.2, 0, 2.7), "l_el": Vector3(0.2, 0, 0), "r_el": Vector3(0.2, 0, 0)})
			var low := _m({"hip_h": 0.88, "l_sh": Vector3(0.6, 0, -2.2), "r_sh": Vector3(0.6, 0, 2.2), "l_el": Vector3(0.8, 0, 0), "r_el": Vector3(0.8, 0, 0)})
			return [[up, _root(yaw, 0.12), 0.18], [low, r, 0.2], [up, _root(yaw, 0.12), 0.18], [low, r, 0.2], [up, _root(yaw, 0.1), 0.25], [st, r, 0.4]]
		"flex":
			var fl := _m({"l_sh": Vector3(0.1, 0, -1.55), "r_sh": Vector3(0.1, 0, 1.55), "l_el": Vector3(2.1, 0, 0), "r_el": Vector3(2.1, 0, 0), "spine": Vector3(0.1, 0, 0)})
			return [[fl, r, 0.35], [fl, r, 1.4], [st, r, 0.4]]
		"sit":
			var sit := {"hip_h": 0.28, "spine": Vector3(0.05, 0, 0), "neck": Vector3(0.05, 0, 0),
				"l_hip": Vector3(1.45, 0, -0.55), "r_hip": Vector3(1.45, 0, 0.55), "l_kn": Vector3(-2.3, 0, 0), "r_kn": Vector3(-2.3, 0, 0),
				"l_sh": Vector3(0.5, 0, -0.1), "r_sh": Vector3(0.5, 0, 0.1), "l_el": Vector3(0.9, 0, 0), "r_el": Vector3(0.9, 0, 0)}
			return [[sit, r, 0.6], [sit, r, 6.0], [st, r, 0.6]]
		"stretch":
			var s1 := _m({"l_sh": Vector3(0.1, 0, -2.9), "r_sh": Vector3(0.1, 0, 2.9), "l_el": Vector3(0.05, 0, 0), "r_el": Vector3(0.05, 0, 0), "spine": Vector3(0.15, 0, 0)})
			var s2 := _m({"l_sh": Vector3(0.1, 0, -2.9), "r_sh": Vector3(0.1, 0, 2.9), "spine": Vector3(0.1, 0, 0.35)})
			var s3 := _m({"l_sh": Vector3(0.1, 0, -2.9), "r_sh": Vector3(0.1, 0, 2.9), "spine": Vector3(0.1, 0, -0.35)})
			return [[s1, r, 0.5], [s2, r, 0.6], [s3, r, 0.8], [s1, r, 0.5], [st, r, 0.5]]
		"dance":
			var out: Array = []
			for i in 4:
				var sd := 1.0 if i % 2 == 0 else -1.0
				var d1 := _m({"hip_h": 0.86, "spine": Vector3(0, 0, 0.18 * sd), "l_sh": Vector3(0.9, 0, -0.6 - 0.6 * sd), "r_sh": Vector3(0.9, 0, 0.6 - 0.6 * sd),
					"l_el": Vector3(1.4, 0, 0), "r_el": Vector3(1.4, 0, 0), "l_kn": Vector3(-0.5 if sd > 0 else -0.1, 0, 0), "r_kn": Vector3(-0.1 if sd > 0 else -0.5, 0, 0)})
				out.append([d1, _root(yaw + 0.25 * sd), 0.28])
			out.append([st, r, 0.35])
			return out
		"tap":
			var kneel := {"hip_h": 0.5, "spine": Vector3(-0.5, 0, 0), "l_hip": Vector3(1.4, 0, 0), "r_hip": Vector3(0.2, 0, 0),
				"l_kn": Vector3(-1.5, 0, 0), "r_kn": Vector3(-1.9, 0, 0), "r_sh": Vector3(1.6, 0, 0.1), "r_el": Vector3(0.3, 0, 0), "l_sh": Vector3(0.6, 0, 0)}
			var hit := kneel.duplicate()
			hit["r_sh"] = Vector3(1.2, 0, 0.1)
			return [[kneel, r, 0.4], [hit, r, 0.12], [kneel, r, 0.15], [hit, r, 0.12], [kneel, r, 0.15], [hit, r, 0.12], [st, r, 0.5]]
		"shrimp":
			var lie := {"hip_h": 0.18, "spine": Vector3(1.4, 0, 0), "neck": Vector3(-0.3, 0, 0), "l_hip": Vector3(0.9, 0, 0), "r_hip": Vector3(0.9, 0, 0),
				"l_kn": Vector3(-1.4, 0, 0), "r_kn": Vector3(-1.4, 0, 0), "l_sh": Vector3(0.9, 0, 0), "r_sh": Vector3(0.9, 0, 0)}
			var push := lie.duplicate()
			push["l_hip"] = Vector3(0.2, 0, 0)
			push["l_kn"] = Vector3(-0.3, 0, 0)
			push["spine"] = Vector3(1.4, 0, 0.4)
			return [[lie, r, 0.5], [push, _root(yaw, 0.0, -0.25), 0.3], [lie, _root(yaw, 0.0, -0.25), 0.3], [push, _root(yaw, 0.0, -0.5), 0.3], [lie, _root(yaw, 0.0, -0.5), 0.3], [st, r, 0.7]]
	return []
