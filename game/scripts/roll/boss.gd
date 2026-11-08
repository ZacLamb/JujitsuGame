class_name Boss
extends RefCounted
## Raid-style phases for the masters. A phase starts when its trigger fires (the master's stamina
## drops below a value, or you take the lead) and can change position, favourites, speed (enrage),
## add a telegraphed SPECIAL (long gold cast, one specific counter), raise a SHIELD (stacks that
## cut your odds until stripped with wear-downs) or SILENCE your counters.
##
## Specials: sweep (they reverse you +2), crush (-25 stamina, grips lost), deep_sub (a submission
## starts nearly finished), roar (counters locked 3.5s, -15 stamina).

const PHASES := {
	"onca": [
		{"name": "Stalking", "text": "Onça circles, patient. Build your grips.", "aggr": 0.9},
		{"name": "Jaguar Guard", "when": {"opp_stam": 65}, "text": "Onça pulls you into his guard and hunts the triangle!",
			"pos": ["guard", true], "aggr": 1.1, "fav": ["triangle", "guard_armbar", "scissor_sweep"],
			"special": {"id": "pounce", "name": "POUNCE", "counter": "base", "dur": 2.7, "every": 12.0, "effect": "sweep",
				"hint": "a huge sweep: BASE"}},
		{"name": "Cornered Cat", "when": {"opp_stam": 30}, "text": "Cornered! Onça goes all out.", "aggr": 1.2, "cast_mult": 0.93,
			"special": {"id": "pounce", "name": "POUNCE", "counter": "base", "dur": 2.4, "every": 10.0, "effect": "sweep",
				"hint": "a huge sweep: BASE"}},
	],
	"jacare": [
		{"name": "Ambush", "text": "Jacaré waits in the shallows.", "aggr": 0.9},
		{"name": "Death Roll", "when": {"opp_stam": 70}, "text": "Jacaré starts rolling. Frame or get crushed!", "aggr": 1.1,
			"special": {"id": "death_roll", "name": "DEATH ROLL", "counter": "frame", "dur": 2.4, "every": 10.0, "effect": "crush",
				"hint": "crushing pressure: FRAME"}},
		{"name": "Swamp Weight", "when": {"opp_stam": 35}, "text": "Jacaré sinks his hips: HEAVY BASE. Wear him down to strip it.",
			"shield": 3, "aggr": 1.15,
			"special": {"id": "death_roll", "name": "DEATH ROLL", "counter": "frame", "dur": 2.2, "every": 11.0, "effect": "crush",
				"hint": "crushing pressure: FRAME"}},
	],
	"cachoeira": [
		{"name": "Still Water", "text": "Cachoeira flows around your grips.", "aggr": 1.0},
		{"name": "Undertow", "when": {"opp_stam": 70}, "text": "The current turns. Watch for the Undertow!", "aggr": 1.15,
			"special": {"id": "undertow", "name": "UNDERTOW", "counter": "defend", "dur": 2.1, "every": 8.0, "effect": "deep_sub",
				"hint": "a deep submission: DEFEND"}},
		{"name": "Flood", "when": {"opp_stam": 35}, "text": "The waterfall floods: everything comes faster.", "aggr": 1.35, "cast_mult": 0.82,
			"special": {"id": "undertow", "name": "UNDERTOW", "counter": "defend", "dur": 1.9, "every": 6.5, "effect": "deep_sub",
				"hint": "a deep submission: DEFEND"}},
	],
	"leao": [
		{"name": "The King", "text": "Leão measures you.", "aggr": 1.0},
		{"name": "Roar", "when": {"opp_stam": 72, "player_lead": true}, "text": "Leão ROARS. Answer it or lose your counters!", "aggr": 1.15,
			"special": {"id": "roar", "name": "ROAR", "counter": "base", "dur": 2.0, "every": 9.0, "effect": "roar",
				"hint": "a roar that silences you: BASE"}},
		{"name": "King's Weight", "when": {"opp_stam": 38}, "text": "Leão bears down: HEAVY BASE and he speeds up.", "shield": 2,
			"aggr": 1.3, "cast_mult": 0.85,
			"special": {"id": "mane", "name": "LION'S MANE", "counter": "defend", "dur": 2.0, "every": 8.0, "effect": "deep_sub",
				"hint": "a deep choke: DEFEND"}},
	],
}

static func has(opp_id: String) -> bool:
	return PHASES.has(opp_id)

static func phases(opp_id: String) -> Array:
	return PHASES.get(opp_id, [])

## Does phase p's trigger fire for this sim state?
static func triggered(p: Dictionary, sim: RollSim) -> bool:
	var w: Dictionary = p.get("when", {})
	if w.is_empty():
		return false
	if w.has("opp_stam") and sim.opp_stamina < float(w.opp_stam):
		return true
	if w.get("player_lead", false) and sim.player_pts > sim.opp_pts:
		return true
	return false
