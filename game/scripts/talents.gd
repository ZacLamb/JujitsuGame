class_name TalentTrees
extends RefCounted
## WoW (Dragonflight-style) talent trees: a CLASS tree everyone shares (with your class's own
## technique nodes) and a SPEC tree per specialization. Nodes sit on a 5-column grid, connect to
## the nodes above them, and deeper rows are gated by points spent in that tree. Node kinds:
## passive (round), active / technique (square), choice (octagon: pick one of two).
## Every effect feeds the real-time combat (CombatCore reads the mods built by apply()).

const GATES := {"class": [[3, 6], [6, 14]], "spec": [[3, 5], [5, 11]]}   # [row, points needed]
const COLS := 5

## fx keys (see apply()): dmg {type: f}, ab_dmg {ability: f}, hp f, gas n, regen f, haste f, dr f,
## crit f, cd {ability: f}, aura_dur {down|pinned|exposed: s}, pinned_vuln f, auto_grip f,
## grip_bonus {ability: n}, cost_add {ability: n}, free_sub, second_wind, scramble, tap_heal f,
## tap_gas n, grip_start n, instant_sub, tap_reset, pin_grip, down_dmg f, exec f, base_grip,
## move "id" / moves [..] (learn a technique).
const CLASS := [
	{"id": "c_iron_grip", "name": "Iron Grip", "row": 0, "col": 2, "max": 2, "icon": "link",
		"desc": "Hand Fight deals 15% more damage per rank.", "fx": {"ab_dmg": {"handfight": 0.15}}},
	{"id": "c_good_base", "name": "Good Base", "row": 1, "col": 1, "max": 2, "req": ["c_iron_grip"], "icon": "shield",
		"desc": "+6% maximum Composure per rank.", "fx": {"hp": 0.06}},
	{"id": "c_deep_lungs", "name": "Deep Lungs", "row": 1, "col": 3, "max": 2, "req": ["c_iron_grip"], "icon": "wave",
		"desc": "+12 maximum Gas per rank.", "fx": {"gas": 12}},
	{"id": "c_snap_down", "name": "Snap Down", "row": 2, "col": 0, "max": 1, "kind": "active", "req": ["c_good_base"], "icon": "down",
		"desc": "Learn Snap Down & Go Behind: your Back Take button.", "fx": {"move": "snap_down"}},
	{"id": "c_grip_style", "name": "Grip Style", "row": 2, "col": 2, "max": 1, "kind": "choice", "req": ["c_good_base", "c_deep_lungs"], "icon": "link",
		"choice": [
			{"name": "Two-on-One", "desc": "Your hand fighting (auto attacks) builds Grip 40% of the time instead of 25%.", "fx": {"auto_grip": 0.15}},
			{"name": "Collar Tie", "desc": "Hand Fight builds 2 Grip but costs 5 more Gas.", "fx": {"grip_bonus": {"handfight": 1}, "cost_add": {"handfight": 5}}}]},
	{"id": "c_omoplata", "name": "Omoplata", "row": 2, "col": 4, "max": 1, "kind": "active", "req": ["c_deep_lungs"], "icon": "loop",
		"desc": "Learn the Omoplata: a stronger Submission from guard.", "fx": {"move": "omoplata"}},
	{"id": "c_scramble", "name": "Scramble", "row": 3, "col": 1, "max": 1, "req": ["c_snap_down", "c_grip_style"], "icon": "bolt",
		"desc": "Escape's cooldown is halved.", "fx": {"scramble": true}},
	{"id": "c_pressure", "name": "Pressure", "row": 3, "col": 3, "max": 2, "req": ["c_grip_style", "c_omoplata"], "icon": "chevron",
		"desc": "Pinned lasts 1.5s longer per rank, and Pinned targets take 5% more damage per rank.", "fx": {"aura_dur": {"pinned": 1.5}, "pinned_vuln": 0.05}},
	{"id": "c_uchi_mata", "name": "Uchi Mata", "row": 4, "col": 0, "max": 1, "kind": "active", "req": ["c_scramble"], "icon": "down",
		"desc": "Learn Uchi Mata: a harder-hitting Takedown.", "fx": {"move": "uchi_mata"}},
	{"id": "c_finishing", "name": "Finishing Style", "row": 4, "col": 2, "max": 1, "kind": "choice", "req": ["c_scramble", "c_pressure"], "icon": "bolt",
		"choice": [
			{"name": "Killer Instinct", "desc": "Submissions deal 15% more damage.", "fx": {"ab_dmg": {"sub": 0.15}}},
			{"name": "Patience", "desc": "Submissions cost no Gas.", "fx": {"free_sub": true}}]},
	{"id": "c_leg_drag", "name": "Leg Drag", "row": 4, "col": 4, "max": 1, "kind": "active", "req": ["c_pressure"], "icon": "chevron",
		"desc": "Learn the Leg Drag: a harder-hitting Guard Pass.", "fx": {"move": "leg_drag"}},
	{"id": "c_tough", "name": "Tough as Nails", "row": 5, "col": 1, "max": 2, "req": ["c_uchi_mata", "c_finishing"], "icon": "shield",
		"desc": "Take 5% less damage per rank.", "fx": {"dr": 0.05}},
	{"id": "c_quick_hands", "name": "Quick Hands", "row": 5, "col": 3, "max": 2, "req": ["c_finishing", "c_leg_drag"], "icon": "bolt",
		"desc": "4% haste per rank: faster global cooldown and casts.", "fx": {"haste": 0.04}},
	{"id": "c_berimbolo", "name": "Berimbolo", "row": 6, "col": 0, "max": 1, "kind": "active", "req": ["c_tough"], "icon": "loop",
		"desc": "Learn the Berimbolo: a stronger Back Take.", "fx": {"move": "berimbolo"}},
	{"id": "c_second_wind", "name": "Second Wind", "row": 6, "col": 2, "max": 1, "req": ["c_tough", "c_quick_hands"], "icon": "wave",
		"desc": "Once per fight, dropping below 20% Composure restores 25% of it.", "fx": {"second_wind": true}},
	{"id": "c_chokes", "name": "Choke Specialist", "row": 6, "col": 4, "max": 1, "kind": "active", "req": ["c_quick_hands"], "icon": "bolt",
		"desc": "Learn the D'Arce and the Ezekiel: stronger Submissions.", "fx": {"moves": ["darce", "ezekiel"]}},
	{"id": "c_capstone", "name": "Legacy", "row": 7, "col": 2, "max": 1, "kind": "choice", "req": ["c_second_wind"], "icon": "star", "capstone": true,
		"choice": [
			{"name": "Flying Armbar", "desc": "Learn the Flying Armbar, and your Submissions have no cast time.", "fx": {"move": "flying_armbar", "instant_sub": true}},
			{"name": "Relentless", "desc": "Every tap you finish restores 30 Gas and 10% Composure.", "fx": {"tap_gas": 30, "tap_heal": 0.10}}]},
]

## Spec trees are built from the spec's role (finisher / scrambler / anchor / grinder) around the
## spec's signature move. Mastery and capstone use the spec's own names.
const ROLE := {
	"finisher": [
		{"n": "Tight Squeeze", "d": "Submissions deal 8% more damage per rank.", "fx": {"ab_dmg": {"sub": 0.08}}, "max": 2, "icon": "bolt"},
		{"n": "Grip Hunter", "d": "Start every fight with 2 Grip.", "fx": {"grip_start": 2}, "max": 1, "icon": "link"},
		{"n": "Opportunist", "d": "+4% critical strike chance per rank.", "fx": {"crit": 0.04}, "max": 2, "icon": "star"},
		{"n": "Go for the Kill", "d": "+30% damage to targets below 35% Composure.", "fx": {"exec": 0.30}, "max": 1, "icon": "bolt"},
		[{"n": "Snap", "d": "Submissions cast 40% faster.", "fx": {"haste_sub": 0.4}}, {"n": "Crank", "d": "Submission crits deal 50% extra damage.", "fx": {"sub_crit": 0.5}}],
		{"n": "Exposed Nerve", "d": "Exposed lasts 3s longer per rank.", "fx": {"aura_dur": {"exposed": 3.0}}, "max": 2, "icon": "loop"},
	],
	"scrambler": [
		{"n": "Light Feet", "d": "4% haste per rank.", "fx": {"haste": 0.04}, "max": 2, "icon": "bolt"},
		{"n": "Off-Balance", "d": "Down lasts 0.5s longer per rank.", "fx": {"aura_dur": {"down": 0.5}}, "max": 2, "icon": "down"},
		{"n": "Slippery", "d": "Escape also deals damage and restores 20 Gas.", "fx": {"escape_gas": 20}, "max": 1, "icon": "wave"},
		{"n": "Kick While Down", "d": "+20% damage to Down targets.", "fx": {"down_dmg": 0.20}, "max": 1, "icon": "down"},
		[{"n": "Chain Wrestling", "d": "Takedowns and Sweeps have 30% shorter cooldowns.", "fx": {"cd": {"takedown": 0.3, "sweep": 0.3}}}, {"n": "Back Hunter", "d": "Back Take's cooldown is halved.", "fx": {"cd": {"back": 0.5}}}],
		{"n": "Second Gear", "d": "+15% Gas regeneration per rank.", "fx": {"regen": 0.15}, "max": 2, "icon": "wave"},
	],
	"anchor": [
		{"n": "Heavy", "d": "+6% maximum Composure per rank.", "fx": {"hp": 0.06}, "max": 2, "icon": "shield"},
		{"n": "Frame Work", "d": "Frame's cooldown is 40% shorter.", "fx": {"cd": {"frame": 0.4}}, "max": 1, "icon": "shield"},
		{"n": "Grit", "d": "Take 5% less damage per rank.", "fx": {"dr": 0.05}, "max": 2, "icon": "shield"},
		{"n": "Base and Bounce", "d": "Base also gives 2 Grip and 30 Gas.", "fx": {"base_grip": true}, "max": 1, "icon": "chevron"},
		[{"n": "Iron Guard", "d": "Pull Guard lasts twice as long.", "fx": {"aura_dur": {"guarded": 6.0}}}, {"n": "Endurance", "d": "+25 maximum Gas.", "fx": {"gas": 25}}],
		{"n": "Wear Them Down", "d": "Hand Fight deals 12% more damage per rank.", "fx": {"ab_dmg": {"handfight": 0.12}}, "max": 2, "icon": "link"},
	],
	"grinder": [
		{"n": "Smother", "d": "Pinned lasts 1.5s longer per rank.", "fx": {"aura_dur": {"pinned": 1.5}}, "max": 2, "icon": "chevron"},
		{"n": "Crossface", "d": "Applying Pinned gives +1 Grip.", "fx": {"pin_grip": true}, "max": 1, "icon": "link"},
		{"n": "Heavy Pressure", "d": "Pinned targets take 6% more damage per rank.", "fx": {"pinned_vuln": 0.06}, "max": 2, "icon": "chevron"},
		{"n": "Economy", "d": "Your techniques cost 10% less Gas.", "fx": {"cost_mult": 0.10}, "max": 1, "icon": "wave"},
		[{"n": "Mount Control", "d": "Advance deals 25% more damage.", "fx": {"ab_dmg": {"advance": 0.25}}}, {"n": "Knee on Belly", "d": "Guard Pass deals 25% more damage.", "fx": {"ab_dmg": {"pass": 0.25}}}],
		{"n": "Grind", "d": "+5% damage per rank.", "fx": {"dmg_all": 0.05}, "max": 2, "icon": "bolt"},
	],
}
const _COACH_ROLE := [
	{"n": "Patient Teacher", "d": "+6% maximum Composure per rank.", "fx": {"hp": 0.06}, "max": 2, "icon": "shield"},
	{"n": "Deep Breaths", "d": "Breathe's cooldown is 30% shorter.", "fx": {"cd": {"breathe": 0.3}}, "max": 1, "icon": "wave"},
	{"n": "Fundamentals", "d": "Take 4% less damage per rank.", "fx": {"dr": 0.04}, "max": 2, "icon": "shield"},
	{"n": "Read the Game", "d": "+4% critical strike chance per rank.", "fx": {"crit": 0.04}, "max": 2, "icon": "star"},
	[{"n": "Corner Voice", "d": "Corner Advice heals 10% more.", "fx": {"advice_heal": 0.10}}, {"n": "Fresh Legs", "d": "+20 maximum Gas.", "fx": {"gas": 20}}],
	{"n": "Lead by Example", "d": "+5% damage per rank.", "fx": {"dmg_all": 0.05}, "max": 2, "icon": "bolt"},
]
const CAPSTONE := {
	"coach": {"n": "Black Belt Professor", "d": "Corner Advice's cooldown is halved and it heals 10% more.", "fx": {"cd": {"spec": 0.5}, "advice_heal": 0.10}},
	"finisher": {"n": "Tap Machine", "d": "Finishing a tap resets all of your cooldowns.", "fx": {"tap_reset": true}},
	"scrambler": {"n": "Flow State", "d": "+10% haste, and Escape costs no Gas.", "fx": {"haste": 0.10, "cost_add": {"escape": -20}}},
	"anchor": {"n": "Immovable", "d": "Take 12% less damage; Base lasts 3s longer.", "fx": {"dr": 0.12, "aura_dur": {"base": 3.0}}},
	"grinder": {"n": "Crushing Weight", "d": "Your attacks on Pinned or Down targets deal 20% more damage.", "fx": {"pinned_vuln": 0.20, "down_dmg": 0.20}},
}
# grid slots for a spec tree: [row, col, role-node index]; index -1 = mastery, 99 = capstone
const SPEC_LAYOUT := [[0, 2, -1], [1, 1, 0], [1, 3, 1], [2, 0, 2], [2, 2, 4], [2, 4, 3], [3, 1, 5], [3, 3, -2], [4, 2, -3], [5, 2, 99]]

static var _spec_cache := {}

static func spec_tree(spec_id: String) -> Array:
	if spec_id == "":
		return []
	if _spec_cache.has(spec_id):
		return _spec_cache[spec_id]
	var s := Specs.get_spec(spec_id)
	if s.is_empty():
		return []
	var role := str(s.role)
	var lib: Array = _COACH_ROLE if role == "coach" else ROLE.get(role, ROLE.finisher)
	var mv: Dictionary = Data.MOVES.get(str(s.move), {})
	var mname := Specs.ADVICE_NAME if role == "coach" else str(mv.get("name", s.name))
	var out: Array = []
	var ids := {}
	for slot in SPEC_LAYOUT:
		var r: int = slot[0]
		var c: int = slot[1]
		var k: int = slot[2]
		var nd := {"row": r, "col": c}
		nd["id"] = "s_%s_%d_%d" % [spec_id, r, c]
		if k == -1 and role == "coach":
			nd.merge({"name": "Mastery", "max": 2, "icon": "star",
				"desc": "Corner Advice heals 8% more per rank.", "fx": {"advice_heal": 0.08}})
		elif k == -1:
			nd.merge({"name": "Mastery", "max": 2, "icon": "star",
				"desc": Tx.f("Your signature, %s, deals 15%% more damage per rank.", mname), "fx": {"ab_dmg": {"spec": 0.15}}})
		elif k == -2:
			nd.merge({"name": "Signature Drill", "max": 1, "icon": "bolt",
				"desc": Tx.f("%s's cooldown is 35%% shorter.", mname), "fx": {"cd": {"spec": 0.35}}})
		elif k == -3:
			nd.merge({"name": "Game Plan", "max": 1, "kind": "choice", "icon": "loop", "choice": [
				{"name": "Aggressive", "desc": "+6% damage.", "fx": {"dmg_all": 0.06}},
				{"name": "Defensive", "desc": "Take 6% less damage.", "fx": {"dr": 0.06}}]})
		elif k == 99:
			var cap: Dictionary = CAPSTONE.get(role, CAPSTONE.finisher)
			nd.merge({"name": str(cap.n), "max": 1, "capstone": true, "icon": "star", "desc": str(cap.d), "fx": cap.fx})
		else:
			var e = lib[k]
			if e is Array:
				nd.merge({"name": "Style", "max": 1, "kind": "choice", "icon": "link", "choice": [
					{"name": str(e[0].n), "desc": str(e[0].d), "fx": e[0].fx}, {"name": str(e[1].n), "desc": str(e[1].d), "fx": e[1].fx}]})
			else:
				nd.merge({"name": str(e.n), "max": int(e.get("max", 1)), "icon": str(e.get("icon", "chevron")), "desc": str(e.d), "fx": e.fx})
		ids["%d_%d" % [r, c]] = nd.id
		out.append(nd)
	# connections: each node links to the nearest nodes one row up
	for nd in out:
		var req: Array = []
		for o in out:
			if int(o.row) == int(nd.row) - 1 and absi(int(o.col) - int(nd.col)) <= 2:
				req.append(o.id)
		nd["req"] = req
	_spec_cache[spec_id] = out
	return out

## Each class's tree teaches its own techniques: the six technique nodes (in tree order) and the
## capstone's first choice. Not every class learns every move.
const TEACH_NODES := ["c_snap_down", "c_omoplata", "c_uchi_mata", "c_leg_drag", "c_berimbolo", "c_chokes"]
const CLASS_TEACH := {
	"guard": {"nodes": [["sumi_gaeshi"], ["omoplata"], ["triangle_armbar"], ["berimbolo"], ["gogoplata"], ["darce", "ezekiel"]], "cap": "flying_armbar"},
	"wrestler": {"nodes": [["snap_down"], ["high_crotch"], ["uchi_mata"], ["leg_drag"], ["darce"], ["ezekiel", "baseball_choke"]], "cap": "crucifix"},
	"judoka": {"nodes": [["uchi_mata"], ["sumi_gaeshi"], ["snap_down"], ["omoplata"], ["ezekiel"], ["darce", "baseball_choke"]], "cap": "flying_armbar"},
	"athlete": {"nodes": [["imanari_roll"], ["berimbolo"], ["snap_down"], ["omoplata"], ["twister"], ["darce", "triangle_armbar"]], "cap": "flying_armbar"},
	"passer": {"nodes": [["leg_drag"], ["baseball_choke"], ["high_crotch"], ["darce"], ["crucifix"], ["ezekiel", "twister"]], "cap": "twister"},
}
static var _class_cache := {}

## The class tree for a style: the shared layout with that class's techniques.
static func class_tree(style: String = "") -> Array:
	if style == "":
		style = Game.style
	if not CLASS_TEACH.has(style):
		return CLASS
	if _class_cache.has(style):
		return _class_cache[style]
	var ct: Dictionary = CLASS_TEACH[style]
	var out: Array = []
	for n0 in CLASS:
		var n: Dictionary = n0.duplicate(true)
		var k := TEACH_NODES.find(str(n.id))
		if k >= 0:
			var mvs: Array = ct.nodes[k]
			var names: Array = []
			for m in mvs:
				names.append(str(Data.MOVES[m].name))
			n["name"] = str(names[0]) if mvs.size() == 1 else "%s & %s" % [names[0], names[1]]
			if mvs.size() == 1:
				var tp := str(Data.MOVES[mvs[0]].type)
				n["fx"] = {"move": mvs[0]}
				n["desc"] = Tx.f("Learn %s: a stronger %s from %s.", [names[0], MoveInfo.TYPE_NAMES.get(tp, tp), str(Data.MOVES[mvs[0]].pos)])
			else:
				n["fx"] = {"moves": mvs}
				n["desc"] = Tx.f("Learn %s and %s.", [names[0], names[1]])
		elif str(n.id) == "c_capstone":
			var cap := str(ct.cap)
			n.choice[0]["name"] = str(Data.MOVES[cap].name)
			n.choice[0]["desc"] = Tx.f("Learn the %s, and your Submissions have no cast time.", str(Data.MOVES[cap].name))
			n.choice[0]["fx"] = {"move": cap, "instant_sub": true}
		out.append(n)
	_class_cache[style] = out
	return out

static func tree(tree_id: String, spec_id := "") -> Array:
	return class_tree() if tree_id == "class" else spec_tree(spec_id)

static func node(id: String, spec_id := "") -> Dictionary:
	for n in class_tree():
		if n.id == id:
			return n
	if id.begins_with("s_"):
		for n in spec_tree(spec_id if spec_id != "" else _spec_of(id)):
			if n.id == id:
				return n
	return {}

static func _spec_of(id: String) -> String:
	for st in Specs.SPECS:
		for s in Specs.SPECS[st]:
			if id.begins_with("s_%s_" % s.id):
				return s.id
	return ""

static func tree_of(id: String) -> String:
	return "spec" if id.begins_with("s_") else "class"

## Points a node costs / holds: choice nodes store 1 or 2 (which option) but cost 1.
static func spent_in(talents: Dictionary, tree_id: String, spec_id: String) -> int:
	var n := 0
	for nd in tree(tree_id, spec_id):
		var v := int(talents.get(nd.id, 0))
		n += (1 if v > 0 else 0) if str(nd.get("kind", "")) == "choice" else v
	return n

static func gate_need(tree_id: String, row: int) -> int:
	var need := 0
	for g in GATES[tree_id]:
		if row >= int(g[0]):
			need = int(g[1])
	return need

## Effects of a learned node (choice nodes: the picked option).
static func fx_of(nd: Dictionary, val: int) -> Dictionary:
	if str(nd.get("kind", "")) == "choice":
		var ch: Array = nd.choice
		return ch[clampi(val - 1, 0, ch.size() - 1)].fx
	return nd.get("fx", {})

## Folds every learned node into the combat / roll modifiers.
static func apply(m: Dictionary, talents: Dictionary, spec_id: String) -> void:
	for tid in ["class", "spec"]:
		for nd in tree(tid, spec_id):
			var v := int(talents.get(nd.id, 0))
			if v <= 0:
				continue
			var ranks := 1 if str(nd.get("kind", "")) == "choice" else v
			var fx := fx_of(nd, v)
			for k in fx:
				var val = fx[k]
				match k:
					"dmg":
						for t in val:
							m.zone[t] = float(m.zone.get(t, 0.0)) + float(val[t]) * ranks
					"ab_dmg", "cd", "aura_dur", "grip_bonus", "cost_add":
						if not m.has(k):
							m[k] = {}
						for a in val:
							m[k][a] = float(m[k].get(a, 0.0)) + float(val[a]) * ranks
					"hp":
						m["hp_mult"] = float(m.get("hp_mult", 1.0)) + float(val) * ranks
					"gas":
						m.stamina_max = float(m.stamina_max) + float(val) * ranks
					"regen":
						m.regen = float(m.regen) * (1.0 + float(val) * ranks)
					"haste":
						m.decision = float(m.decision) * (1.0 + float(val) * ranks)
					"move", "moves":
						pass
					_:
						if val is bool:
							m[k] = val
						else:
							m[k] = float(m.get(k, 0.0)) + float(val) * ranks

## Moves taught by learned nodes.
static func taught_moves(talents: Dictionary, spec_id: String) -> Array:
	var out: Array = []
	for tid in ["class", "spec"]:
		for nd in tree(tid, spec_id):
			var v := int(talents.get(nd.id, 0))
			if v <= 0:
				continue
			var fx := fx_of(nd, v)
			if fx.has("move"):
				out.append(str(fx.move))
			for mv in fx.get("moves", []):
				out.append(str(mv))
	return out
