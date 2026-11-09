class_name Rpg
extends RefCounted
## RPG layer: fighting styles ("races"), attributes, talent trees, levels, and the
## modifiers they produce for a roll. Pure data + functions so it's easy to test and tune.

# ---------------------------------------------------------------- attributes
const ATTR_BASE := 5
const ATTR_CAP := 20
const ATTRS := {
	"strength": {"name": "Strength", "short": "STR", "desc": "+1.5% damage with every move, +2% more with passes, takedowns and mount. Harder finishing squeezes."},
	"flexibility": {"name": "Flexibility", "short": "FLX", "desc": "+3% Composure (health). +2% damage with sweeps, guard and escapes."},
	"grip": {"name": "Grip", "short": "GRP", "desc": "+0.5% critical chance. +2% damage with submissions and back takes."},
	"cardio": {"name": "Cardio", "short": "CRD", "desc": "+4 max Gas, +5% Gas regen, moves cost 2% less."},
	"iq": {"name": "Jiu-Jitsu IQ", "short": "IQ", "desc": "Take 3% less damage, +1% critical chance."},
}
const ATTR_ORDER := ["strength", "flexibility", "grip", "cardio", "iq"]

# Training drills at the gyms: one per attribute.
# kind: "mash" (tap fast), "timing" (3 timing bars), "arrows" (5 reaction prompts)
const DRILLS := {
	"strength": {"name": "Kettlebell Swings", "kind": "mash", "tip": "Tap fast. Drive the hips."},
	"grip": {"name": "Rope Climb", "kind": "timing", "tip": "Grab at the right moment, three times."},
	"cardio": {"name": "Shark Tank", "kind": "mash", "tip": "Fresh partner every 30 seconds. Keep going."},
	"flexibility": {"name": "Hip Escape Lane", "kind": "timing", "tip": "Shrimp on time, three lengths."},
	"iq": {"name": "Positional Drilling", "kind": "arrows", "tip": "Read the attack, answer it."},
}

# ---------------------------------------------------------------- styles ("races")
const STYLES := {
	"guard": {"name": "Guard Player", "tag": "Born on the bottom.",
		"desc": "Pulls guard, sweeps and hunts submissions off the back. Hard to pass.",
		"attrs": {"flexibility": 3, "iq": 1}, "signature": ["triangle", "omoplata"],
		"passive": "Bottom techniques (sweeps, guard subs) hit 8% harder. Pull Guard costs no Gas.",
		"gi": Color(0.95, 0.95, 0.93)},
	"wrestler": {"name": "Wrestler", "tag": "Shoot, finish, ride.",
		"desc": "Explosive takedowns and relentless top pressure. Hard to take down.",
		"attrs": {"strength": 2, "cardio": 2}, "signature": ["snap_down"],
		"passive": "Takedowns hit 25% harder. Enemy takedowns hit you 20% softer.",
		"gi": Color(0.15, 0.3, 0.75)},
	"judoka": {"name": "Judoka", "tag": "Grips win fights.",
		"desc": "Dominates the grip fight standing and throws people into side control.",
		"attrs": {"grip": 3, "strength": 1}, "signature": ["osoto_gari", "uchi_mata"],
		"passive": "Throws (Osoto Gari, Uchi Mata) hit 20% harder.",
		"gi": Color(0.95, 0.95, 0.93)},
	"athlete": {"name": "Athlete", "tag": "Gas tank for days.",
		"desc": "Fast, fit and hard to hold down. Wins scrambles and late rounds.",
		"attrs": {"cardio": 3, "flexibility": 1}, "signature": ["flying_armbar"],
		"passive": "+50% Gas regeneration. Escapes are 20% stronger.",
		"gi": Color(0.1, 0.1, 0.12)},
	"passer": {"name": "Pressure Passer", "tag": "Heavy is the head.",
		"desc": "Smashes guards and makes people carry their weight. Lives in mount.",
		"attrs": {"strength": 3, "grip": 1}, "signature": ["leg_drag"],
		"passive": "Passes and Advances hit 15% harder. Enemy sweeps hit you 20% softer.",
		"gi": Color(0.95, 0.95, 0.93)},
}
const STYLE_ORDER := ["guard", "wrestler", "judoka", "athlete", "passer"]

const GI_COLORS := [Color(0.95, 0.95, 0.93), Color(0.15, 0.3, 0.75), Color(0.1, 0.1, 0.12)]
const GI_NAMES := ["White", "Blue", "Black"]

# ---------------------------------------------------------------- talent trees
# tier n needs TIER_REQ[n] points already spent in that tree.
const TIER_REQ := [0, 2, 4, 6]
const TREES := {
	"standing": {"name": "Standing", "pt": "Em Pé", "color": Color(0.95, 0.6, 0.25)},
	"guard": {"name": "Guard", "pt": "Guarda", "color": Color(0.35, 0.75, 0.45)},
	"top": {"name": "Top Game", "pt": "Passagem", "color": Color(0.45, 0.6, 0.95)},
}
const TREE_ORDER := ["standing", "guard", "top"]

const TALENTS := {
	# Standing
	"shot_speed": {"tree": "standing", "tier": 0, "max": 3, "name": "Shot Speed", "desc": "Takedowns +8% timing window per rank."},
	"sprawl": {"tree": "standing", "tier": 0, "max": 2, "name": "Sprawl", "desc": "+20% reaction time against takedowns per rank."},
	"scramble": {"tree": "standing", "tier": 1, "max": 1, "name": "Scramble", "desc": "Missed takedowns are never countered."},
	"t_snap_down": {"tree": "standing", "tier": 1, "max": 1, "name": "Snap Down", "desc": "Learn Snap Down & Go Behind (standing to back control, +4).", "move": "snap_down"},
	"t_uchi_mata": {"tree": "standing", "tier": 2, "max": 1, "name": "Uchi Mata", "desc": "Learn Uchi Mata (throw straight to side control, +2).", "move": "uchi_mata"},
	"t_flying_armbar": {"tree": "standing", "tier": 3, "max": 1, "name": "Flying Armbar", "desc": "Capstone. Learn the Flying Armbar: a submission straight from standing.", "move": "flying_armbar"},
	# Guard
	"hip_mobility": {"tree": "guard", "tier": 0, "max": 3, "name": "Hip Mobility", "desc": "Sweeps and escapes +8% timing window per rank."},
	"retention": {"tree": "guard", "tier": 0, "max": 2, "name": "Guard Retention", "desc": "+20% reaction time against guard passes per rank."},
	"t_omoplata": {"tree": "guard", "tier": 1, "max": 1, "name": "Omoplata", "desc": "Learn the Omoplata from closed guard.", "move": "omoplata"},
	"slippery": {"tree": "guard", "tier": 1, "max": 2, "name": "Slippery", "desc": "Escape submissions 12% faster per rank."},
	"t_berimbolo": {"tree": "guard", "tier": 2, "max": 1, "name": "Berimbolo", "desc": "Learn the Berimbolo (guard to back control, +4).", "move": "berimbolo"},
	"triangle_master": {"tree": "guard", "tier": 3, "max": 1, "name": "Triangle Master", "desc": "Capstone. Triangles and omoplatas start 20% deeper and get +15% timing window."},
	# Top
	"heavy_hips": {"tree": "top", "tier": 0, "max": 3, "name": "Heavy Hips", "desc": "Passes and advances +8% timing window per rank."},
	"heavy_top": {"tree": "top", "tier": 0, "max": 2, "name": "Heavy Top", "desc": "+20% reaction time against sweeps and escapes per rank."},
	"t_leg_drag": {"tree": "top", "tier": 1, "max": 1, "name": "Leg Drag", "desc": "Learn the Leg Drag Pass (guard to side control, +3).", "move": "leg_drag"},
	"killer_instinct": {"tree": "top", "tier": 1, "max": 2, "name": "Killer Instinct", "desc": "Submissions start 8% deeper per rank."},
	"t_chokes": {"tree": "top", "tier": 2, "max": 1, "name": "Choke Specialist", "desc": "Learn the D'Arce (half guard top) and Ezekiel (mount).", "moves": ["darce", "ezekiel"]},
	"second_wind": {"tree": "top", "tier": 3, "max": 1, "name": "Second Wind", "desc": "Capstone. Once per roll, recover 40 stamina when you drop below 20."},
}

static func talents_in(tree: String) -> Array:
	var out: Array = []
	for id in TALENTS:
		if TALENTS[id].tree == tree:
			out.append(id)
	return out

# ---------------------------------------------------------------- levels
## Total XP needed to reach `lvl` (level 1 = 0 XP).
static func xp_for_level(lvl: int) -> int:
	var total := 0
	for l in range(1, lvl):
		total += 50 + 25 * (l - 1)
	return total

static func level_for_xp(xp: int) -> int:
	var lvl := 1
	while xp >= xp_for_level(lvl + 1):
		lvl += 1
	return lvl

const ATTR_POINTS_PER_LEVEL := 1
const LEVELS_PER_TALENT_POINT := 2  # one talent point every other level
const START_TALENT_POINTS := 1

# ---------------------------------------------------------------- modifiers
## Builds the modifier set a roll uses. attrs = final attribute values, talents = {id: rank}.
## [damage, composure] adjustments per class, tuned so every class clears content at the same pace.
const CLASS_TUNE := {"guard": [0.0, 0.0], "wrestler": [0.03, 0.0], "judoka": [-0.15, -0.04], "athlete": [0.05, 0.04], "passer": [0.14, 0.12]}

static func build_mods(style_id: String, attrs: Dictionary, talents: Dictionary) -> Dictionary:
	var m := {
		"zone": {},            # move type -> additive fraction (0.1 = +10%)
		"zone_role": {"top": 0.0, "bottom": 0.0, "any": 0.0},
		"zone_move": {},       # move id -> additive fraction
		"defense": 1.0,        # reaction time multiplier (all attacks)
		"defense_vs": {},      # opponent move type -> multiplier
		"struggle_atk": 1.0, "struggle_def": 1.0,
		"sub_start": 0.0, "sub_start_move": {},
		"perfect": 1.0, "decision": 1.0,
		"stamina_max": 100.0, "regen": 1.0, "cost": 1.0,
		"opp_initiative_standing": 1.0,
		"free_moves": [],      # stamina-free techniques
		"scramble": false, "second_wind": false,
		"hp_mult": 1.0, "crit": 0.0, "dmg_all": 0.0,
	}
	var d := func(k: String) -> float: return float(attrs.get(k, ATTR_BASE)) - ATTR_BASE
	# attributes
	for t in ["pass", "advance", "takedown"]:
		_add(m.zone, t, 0.02 * d.call("strength"))
	m.struggle_atk += 0.03 * d.call("strength")
	for t in ["sweep", "guard", "escape"]:
		_add(m.zone, t, 0.02 * d.call("flexibility"))
	m.struggle_def += 0.03 * d.call("flexibility")
	for t in ["sub", "back"]:
		_add(m.zone, t, 0.02 * d.call("grip"))
	m.stamina_max += 4.0 * d.call("cardio")
	m.regen += 0.05 * d.call("cardio")
	m.cost = clampf(1.0 - 0.02 * d.call("cardio"), 0.7, 1.2)
	m.defense += 0.03 * d.call("iq")
	m.perfect += 0.04 * d.call("iq")
	m.decision += 0.04 * d.call("iq")
	# real-time fights: every point (from levels, gear and sets) shows up in the numbers
	m.dmg_all += 0.015 * d.call("strength")
	m.hp_mult += 0.03 * d.call("flexibility")
	m.crit += 0.005 * d.call("grip")
	# style passives
	match style_id:
		"guard":
			m.zone_role.bottom += 0.15
			m.free_moves.append("pull_guard")
		"wrestler":
			_add(m.zone, "takedown", 0.25)
			_mul(m.defense_vs, "takedown", 1.25)
		"judoka":
			m.opp_initiative_standing = 0.6
			for id in ["osoto_gari", "uchi_mata"]:
				_add(m.zone_move, id, 0.2)
		"athlete":
			m.regen += 0.5
			_add(m.zone, "escape", 0.2)
		"passer":
			_add(m.zone, "pass", 0.15)
			_add(m.zone, "advance", 0.15)
			_mul(m.defense_vs, "sweep", 1.25)
			_mul(m.defense_vs, "escape", 1.25)
	# class tuning from the balance sweep (tests/test_balance.gd)
	m["dmg_all"] = float(m.get("dmg_all", 0.0)) + float(CLASS_TUNE.get(style_id, [0.0, 0.0])[0])
	m["hp_mult"] = float(m.get("hp_mult", 1.0)) + float(CLASS_TUNE.get(style_id, [0.0, 0.0])[1])
	# talents
	var r := func(id: String) -> int: return int(talents.get(id, 0))
	_add(m.zone, "takedown", 0.08 * r.call("shot_speed"))
	_mul(m.defense_vs, "takedown", 1.0 + 0.2 * r.call("sprawl"))
	m.scramble = r.call("scramble") > 0
	_add(m.zone, "sweep", 0.08 * r.call("hip_mobility"))
	_add(m.zone, "escape", 0.08 * r.call("hip_mobility"))
	_mul(m.defense_vs, "pass", 1.0 + 0.2 * r.call("retention"))
	m.struggle_def += 0.12 * r.call("slippery")
	if r.call("triangle_master") > 0:
		for id in ["triangle", "omoplata"]:
			_add(m.zone_move, id, 0.15)
			m.sub_start_move[id] = 0.2
	_add(m.zone, "pass", 0.08 * r.call("heavy_hips"))
	_add(m.zone, "advance", 0.08 * r.call("heavy_hips"))
	_mul(m.defense_vs, "sweep", 1.0 + 0.2 * r.call("heavy_top"))
	_mul(m.defense_vs, "escape", 1.0 + 0.2 * r.call("heavy_top"))
	m.sub_start += 0.08 * r.call("killer_instinct")
	m.second_wind = r.call("second_wind") > 0
	return m

static func _add(d: Dictionary, k: String, v: float) -> void:
	d[k] = float(d.get(k, 0.0)) + v

static func _mul(d: Dictionary, k: String, v: float) -> void:
	d[k] = float(d.get(k, 1.0)) * v

## Neutral modifiers (used for tests and as a fallback).
static func neutral_mods() -> Dictionary:
	return build_mods("", {}, {})
