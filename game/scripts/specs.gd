class_name Specs
extends RefCounted
## Specializations: at level 10 every class picks one of three specs (like a WoW mage picking
## Frost / Fire / Arcane). A spec sets your 5v5 role, adds a passive, and unlocks an exclusive
## technique nobody else can use. Changing spec later costs R$ at any time.

const UNLOCK_LEVEL := 10
const RESPEC_COST := 50

## move: the exclusive technique (Data.MOVES entry with "spec": id).
## mods: additive tweaks applied on top of the class's mods (see apply()).
const SPECS := {
	"guard": [
		{"id": "sub_hunter", "name": "Submission Hunter", "role": "finisher", "move": "chain_sub",
			"desc": "Every guard is a trap. Chains armbars, triangles and omoplatas until something gives.",
			"passive": "Submissions start 15% deeper and land 8% more often.",
			"mods": {"sub_start": 0.15, "zone": {"sub": 0.08}}},
		{"id": "sweeper", "name": "Sweeper", "role": "scrambler", "move": "lumberjack",
			"desc": "Off-balance them, come up on top, collect the points.",
			"passive": "Sweeps land 12% more often; their passes take 15% longer to cast.",
			"mods": {"zone": {"sweep": 0.12}, "defense_vs": {"pass": 1.15}}},
		{"id": "lapel_guard", "name": "Lapel Guard", "role": "anchor", "move": "worm_sweep",
			"desc": "Tie them up in their own gi. Slow, sticky, exhausting to pass.",
			"passive": "+15 max stamina; their passes take 30% longer to cast.",
			"mods": {"stamina_max": 15.0, "defense_vs": {"pass": 1.3}}},
	],
	"wrestler": [
		{"id": "chain_wrestler", "name": "Chain Wrestler", "role": "anchor", "move": "blast_double",
			"desc": "Shot after shot after shot, and impossible to move. Somebody's going down and it isn't you.",
			"passive": "Takedowns land 10% more often and cost 10% less stamina; take 6% less damage.",
			"mods": {"zone": {"takedown": 0.1}, "cost": 0.9, "dr": 0.06}},
		{"id": "rider", "name": "Rider", "role": "finisher", "move": "tilt_back",
			"desc": "Once you're on top, you stay there until they tap.",
			"passive": "Back takes land 12% more often; back chokes start 10% deeper.",
			"mods": {"zone": {"back": 0.12}, "sub_start_move": {"rnc": 0.1, "bow_arrow": 0.1}}},
		{"id": "scrambler", "name": "Scrambler", "role": "scrambler", "move": "peek_out",
			"desc": "Never stuck anywhere. Funky, fast, always moving to the next spot.",
			"passive": "Escapes land 15% more often; stamina recovers 15% faster.",
			"mods": {"zone": {"escape": 0.15}, "regen": 0.15}},
	],
	"judoka": [
		{"id": "thrower", "name": "Thrower", "role": "finisher", "move": "seoi_nage",
			"desc": "Big, clean, ippon throws that land you in side control.",
			"passive": "Takedowns land 12% more often.",
			"mods": {"zone": {"takedown": 0.12}}},
		{"id": "grip_fighter", "name": "Grip Fighter", "role": "anchor", "move": "kuzushi_snap",
			"desc": "Win the grips, win the fight. They never get the grip they want.",
			"passive": "All their casts take 10% longer.",
			"mods": {"defense": 0.1}},
		{"id": "newaza", "name": "Ne-waza", "role": "grinder", "move": "kesa_armlock",
			"desc": "Throw, pin, finish. Judo's ground game: heavy and patient.",
			"passive": "Top techniques land 8% more often.",
			"mods": {"zone_role": {"top": 0.08}}},
	],
	"athlete": [
		{"id": "leg_locker", "name": "Leg Locker", "role": "finisher", "move": "heel_hook",
			"desc": "Every foot is a submission. Modern, dangerous, fast.",
			"passive": "Leg locks start 15% deeper.",
			"mods": {"sub_start_move": {"straight_ankle": 0.15, "kneebar": 0.15, "heel_hook": 0.15}}},
		{"id": "berimbolo", "name": "Berimbolo", "role": "scrambler", "move": "kiss_dragon",
			"desc": "Invert, spin, take the back. Nobody knows where you'll come up.",
			"passive": "Back takes land 12% more often.",
			"mods": {"zone": {"back": 0.12}}},
		{"id": "gas_tank", "name": "Pace Pusher", "role": "grinder", "move": "tech_standup",
			"desc": "Push the pace until they break. Win the last minute every time.",
			"passive": "Stamina recovers 20% faster; every technique hits 5% harder.",
			"mods": {"regen": 0.2, "dmg_all": 0.05}},
	],
	"passer": [
		{"id": "smash", "name": "Smash Passer", "role": "anchor", "move": "over_under",
			"desc": "Slow, heavy, unstoppable. Every inch is theirs to pay for.",
			"passive": "Passes land 10% more often; their sweeps take 20% longer to cast; +15 max stamina.",
			"mods": {"zone": {"pass": 0.1}, "defense_vs": {"sweep": 1.2}, "stamina_max": 15.0}},
		{"id": "speed", "name": "Speed Passer", "role": "scrambler", "move": "x_pass",
			"desc": "Torreando, leg drags, gone. Around the guard before they grip.",
			"passive": "Your techniques cast 8% faster; passes land 6% more often.",
			"mods": {"decision": 0.08, "zone": {"pass": 0.06}}},
		{"id": "mount_hunter", "name": "Mount Hunter", "role": "finisher", "move": "smount_armbar",
			"desc": "Mount is home. Cross chokes, armbars, Ezekiels.",
			"passive": "Advances land 10% more often; submissions start 10% deeper.",
			"mods": {"zone": {"advance": 0.1}, "sub_start": 0.1}},
	],
}

## Like WoW, not every class can heal: only these can take the Professor (coach) spec.
## Guard Player and Judoka fill every role; Wrestler and Passer tank or deal damage; the Athlete
## is the pure damage class.
const COACH_CLASSES := ["guard", "judoka"]

## The Professor: the support spec ("healer") for Guard Players and Judokas. Its signature is
## Corner Advice (heal + Game Plan buff) instead of a technique, and teammates you coach from the
## corner in team matches fight sharper.
const PROFESSOR := {"id": "professor", "name": "Professor", "role": "coach", "move": "",
	"desc": "The voice in the corner. Keeps you calm, keeps the plan, keeps teammates alive.",
	"passive": "Breathe heals 10% more. Teammates you coach in team matches start their bouts fresher and sharper.",
	"mods": {"breathe_heal": 0.10}}
const ADVICE_NAME := "Corner Advice"

static func list(style: String) -> Array:
	var out: Array = SPECS.get(style, []).duplicate()
	if not out.is_empty() and style in COACH_CLASSES:
		out.append(PROFESSOR)
	return out

static func get_spec(id: String) -> Dictionary:
	if id == "professor":
		return PROFESSOR
	for st in SPECS:
		for s in SPECS[st]:
			if s.id == id:
				return s
	return {}

static func style_of(id: String) -> String:
	if id == "professor":
		return Game.style
	for st in SPECS:
		for s in SPECS[st]:
			if s.id == id:
				return st
	return ""

## Folds a spec's passive into the roll modifiers.
static func apply(m: Dictionary, spec_id: String) -> void:
	var s := get_spec(spec_id)
	if s.is_empty():
		return
	var mm: Dictionary = s.mods
	for k in mm:
		match k:
			"zone", "zone_role", "zone_move", "sub_start_move":
				for t in mm[k]:
					m[k][t] = float(m[k].get(t, 0.0)) + float(mm[k][t])
			"defense_vs":
				for t in mm[k]:
					m[k][t] = float(m[k].get(t, 1.0)) * float(mm[k][t])
			"stamina_max", "sub_start":
				m[k] = float(m[k]) + float(mm[k])
			"regen", "decision", "defense":
				m[k] = float(m[k]) * (1.0 + float(mm[k]))
			"cost":
				m[k] = float(m[k]) * float(mm[k])
			_:
				m[k] = float(m.get(k, 0.0)) + float(mm[k])
