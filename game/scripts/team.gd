class_name Team
extends RefCounted
## 5v5 team elimination (Quintet-style). Each side lines up five fighters plus a coach in the
## corner. The winner of a bout stays on the mat and carries their stamina into the next one; a
## draw eliminates both. First team out of fighters loses.
##
## Roles form a counter ring (the drafting layer): Finisher > Grinder > Anchor > Scrambler > Finisher.
## Recruits are fighters you've beaten; academy partners fill empty spots early on. Beaten masters
## can coach.

const ROLES := {
	"anchor": {"name": "Anchor", "color": Color(0.35, 0.65, 1.0), "icon": "shield", "beats": "scrambler",
		"desc": "Hard to wear down: +25% stamina, and whoever survives a bout with them loses 10 more stamina."},
	"finisher": {"name": "Finisher", "color": Color(0.95, 0.32, 0.3), "icon": "bolt", "beats": "grinder",
		"desc": "Submissions start deeper and squeeze harder."},
	"scrambler": {"name": "Scrambler", "color": Color(0.35, 0.82, 0.45), "icon": "loop", "beats": "finisher",
		"desc": "Reads and escapes: 15% more time to answer, faster submission escapes."},
	"grinder": {"name": "Grinder", "color": Color(0.72, 0.5, 0.95), "icon": "down", "beats": "anchor",
		"desc": "Heavy wear-downs, and whoever survives a bout with them loses 15 more stamina."},
}
const ROLE_ORDER := ["anchor", "finisher", "scrambler", "grinder"]
const EDGE := 0.07               # technique chance swing for a favourable matchup
const BETWEEN_REGEN := 25.0      # stamina a survivor gets back between bouts
const STYLE_ROLE := {"submission": "finisher", "back": "finisher", "pressure": "grinder", "guard": "scrambler", "balanced": "anchor"}
const PLAYER_ROLE := {"guard": "finisher", "wrestler": "grinder", "judoka": "anchor", "athlete": "scrambler", "passer": "grinder"}
const PARTNERS := [
	{"id": "p_kaique", "name": "Kaique", "role": "scrambler", "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.62, 0.42, 0.28), "body": "male"},
	{"id": "p_nanda", "name": "Nanda", "role": "finisher", "gi": Color(0.15, 0.3, 0.75), "skin": Color(0.8, 0.6, 0.45), "body": "female"},
	{"id": "p_beto", "name": "Beto", "role": "anchor", "gi": Color(0.1, 0.1, 0.12), "skin": Color(0.45, 0.3, 0.2), "body": "male"},
	{"id": "p_lu", "name": "Lu", "role": "grinder", "gi": Color(0.95, 0.95, 0.95), "skin": Color(0.9, 0.72, 0.58), "body": "female"},
]
const TEAM_NAMES := ["Gringo BJJ"]

# ------------------------------------------------------------ fighters
static func role_of(id: String, o: Dictionary) -> String:
	if o.has("role"):
		return str(o.role)
	var st := str(o.get("style", ""))
	if STYLE_ROLE.has(st):
		return STYLE_ROLE[st]
	return ROLE_ORDER[absi(hash(id)) % ROLE_ORDER.size()]

static func player_role() -> String:
	return PLAYER_ROLE.get(Game.style, "anchor")

static func you() -> Dictionary:
	return {"id": "you", "name": Game.player_name, "level": Game.level(), "rank": Game.rank, "role": player_role(), "player": true,
		"gi": Game.gi_color(), "skin": Color(0.86, 0.68, 0.55), "body": "male"}

static func from_opponent(id: String) -> Dictionary:
	var o: Dictionary = Data.OPPONENTS[id]
	return {"id": id, "name": o.name, "level": float(o.level), "rank": int(o.rank), "role": role_of(id, o),
		"gi": o.gi, "skin": o.skin, "body": o.get("body", "male"), "style": o.get("style", "balanced"),
		"extra": o.get("extra", []), "boss": o.get("boss", false)}

## Academy training partners: always available, a bit behind your level.
static func partner(i: int) -> Dictionary:
	var p: Dictionary = PARTNERS[i % PARTNERS.size()].duplicate()
	p["level"] = maxf(1.0, Game.level() - 0.6)
	p["rank"] = maxi(0, Game.rank - 2)
	p["style"] = {"scrambler": "guard", "finisher": "submission", "anchor": "balanced", "grinder": "pressure"}[p.role]
	p["extra"] = []
	p["partner"] = true
	return p

## Everyone you can put in the lineup: you, beaten fighters (not masters), then partners.
static func roster() -> Array:
	var out: Array = [you()]
	for id in Data.OPPONENTS:
		if Game.beaten(id) and not Data.OPPONENTS[id].get("boss", false):
			out.append(from_opponent(id))
	for i in PARTNERS.size():
		out.append(partner(i))
	return out

## Coaches: beaten masters (stronger corner) and recruits.
static func coaches() -> Array:
	var out: Array = []
	for id in Data.OPPONENTS:
		if Game.beaten(id) and Data.OPPONENTS[id].get("boss", false):
			out.append(from_opponent(id))
	for f in roster():
		if not f.get("player", false):
			out.append(f)
	return out

static func find(id: String) -> Dictionary:
	if id == "you":
		return you()
	if Data.OPPONENTS.has(id):
		return from_opponent(id)
	for i in PARTNERS.size():
		if PARTNERS[i].id == id:
			return partner(i)
	return {}

## Stamina the coach gives back between bouts (on top of BETWEEN_REGEN).
static func coach_heal(c: Dictionary) -> float:
	if c.is_empty():
		return 0.0
	return (6.0 + 1.6 * float(c.level)) * (1.5 if c.get("boss", false) else 1.0)

static func edge(a_role: String, b_role: String) -> int:
	if ROLES[a_role].beats == b_role:
		return 1
	if ROLES[b_role].beats == a_role:
		return -1
	return 0

## The default lineup: you + the four strongest others, strongest coach.
static func default_lineup() -> Dictionary:
	var r := roster()
	var others := r.filter(func(f): return not f.get("player", false))
	others.sort_custom(func(a, b): return float(a.level) > float(b.level))
	var order: Array = ["you"]
	for f in others.slice(0, 4):
		order.append(f.id)
	var cs := coaches()
	cs.sort_custom(func(a, b): return coach_heal(a) > coach_heal(b))
	var coach := ""
	for c in cs:
		if not c.id in order:
			coach = c.id
			break
	return {"order": order, "coach": coach}

# ------------------------------------------------------------ enemy academies
static func make_enemy(zone: String, nonce: int, exclude: Array = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-team-%d-%d" % [zone, Game.rank / 5, nonce])
	var academy: String = Data.ACADEMIES[rng.randi() % Data.ACADEMIES.size()]
	var pl := Game.level()
	var locals: Array = []
	for id in Data.OPPONENTS:
		if Data.zone_of(id) == zone and not Data.OPPONENTS[id].get("boss", false) and not id in exclude:
			locals.append(id)
	var fighters: Array = []
	var used := {}
	var gis := [Color(0.95, 0.95, 0.95), Color(0.15, 0.3, 0.75), Color(0.1, 0.1, 0.12)]
	for i in 5:
		var f: Dictionary
		if i < 2 and not locals.is_empty():
			var id: String = locals[rng.randi() % locals.size()]
			if used.has(id):
				id = locals[(locals.find(id) + 1) % locals.size()]
			used[id] = true
			f = from_opponent(id)
			f["id"] = "e_" + id
		else:
			var nm := "%s %s" % [Data.COMP_FIRST[rng.randi() % Data.COMP_FIRST.size()], Data.COMP_LAST[rng.randi() % Data.COMP_LAST.size()]]
			var role: String = ROLE_ORDER[rng.randi() % ROLE_ORDER.size()]
			f = {"id": "e%d" % i, "name": nm, "role": role, "gi": gis[rng.randi() % gis.size()],
				"skin": Color(0.96, 0.8, 0.68).lerp(Color(0.36, 0.22, 0.14), rng.randf()), "body": "female" if rng.randf() < 0.3 else "male",
				"style": {"scrambler": "guard", "finisher": "submission", "anchor": "balanced", "grinder": "pressure"}[role],
				"extra": [], "rank": clampi(Game.rank + rng.randi_range(-2, 1), 0, 24)}
		# a gentle ramp through their lineup: openers below your level, the anchor of the team above
		f["level"] = pl + 0.1 + i * 0.35 + rng.randf_range(-0.15, 0.15)
		f["rank"] = clampi(int(f.get("rank", Game.rank)), 0, 24)
		fighters.append(f)
	var coach := {"name": "Professor %s" % Data.COMP_LAST[rng.randi() % Data.COMP_LAST.size()], "level": pl, "boss": false}
	return {"academy": academy, "fighters": fighters, "coach": coach}

# ------------------------------------------------------------ bouts
## The opponent dictionary RollSim and RollScene expect, from a team fighter.
static func as_opp(f: Dictionary) -> Dictionary:
	return {"name": f.name, "title": ROLES[f.role].name, "rank": int(f.get("rank", 0)), "level": float(f.level),
		"gi": f.get("gi", Color(0.95, 0.95, 0.95)), "skin": f.get("skin", Color(0.7, 0.5, 0.35)), "body": f.get("body", "male"),
		"style": f.get("style", "balanced"), "extra": f.get("extra", []), "zone": "",
		"intro": "Oss.", "win": "Next!", "lose": "Good roll. Your team's got this."}

## Attributes for a non-player fighter: points by level, leaning into the role.
static func _attrs(f: Dictionary) -> Dictionary:
	var lean: String = {"anchor": "cardio", "finisher": "grip", "scrambler": "flexibility", "grinder": "strength"}[f.role]
	var pts := int(float(f.level) * 1.2)
	var a := {}
	for k in Rpg.ATTR_ORDER:
		a[k] = Rpg.ATTR_BASE + pts / 6
	a[lean] = int(a[lean]) + pts / 2
	return a

## Role effects + matchup edge on top of a fighter's base mods.
static func bout_mods(me: Dictionary, them: Dictionary) -> Dictionary:
	var m: Dictionary = Game.mods() if me.get("player", false) else Rpg.build_mods("", _attrs(me), {})
	m = m.duplicate(true)
	match str(me.role):
		"anchor":
			m.stamina_max = float(m.stamina_max) * 1.25
		"finisher":
			m.sub_start = float(m.sub_start) + 0.1
			m.struggle_atk = float(m.struggle_atk) * 1.15
		"scrambler":
			m.defense = float(m.defense) * 1.15
			m.struggle_def = float(m.struggle_def) * 1.2
		"grinder":
			m["wear_dmg"] = 18.0
	var e := edge(str(me.role), str(them.role))
	if e > 0:
		m["edge"] = EDGE
	elif e < 0:
		m["opp_edge"] = EDGE
	return m

static func knows_fn(f: Dictionary) -> Callable:
	if f.get("player", false):
		return Game.knows
	var rank := int(f.get("rank", 0))
	var extra: Array = f.get("extra", [])
	return func(id: String) -> bool: return int(Data.MOVES[id].rank) <= rank + 2 or id in extra

## Sets a RollSim up for a team bout (the same setup live and simulated).
static func setup_sim(sim: RollSim, me: Dictionary, them: Dictionary, me_stam: float, them_stam: float, seed_value := -1) -> void:
	sim.setup("team", float(me.level), knows_fn(me), seed_value, bout_mods(me, them), as_opp(them))
	sim.apply_rule("team")
	match str(them.role):   # the AI side's role leans its personality
		"anchor":
			sim.traits.cardio = float(sim.traits.cardio) * 1.3
		"finisher":
			sim.traits.finish = float(sim.traits.finish) * 1.25
		"scrambler":
			sim.traits.slippery = float(sim.traits.slippery) * 1.2
		"grinder":
			sim.traits.aggr = float(sim.traits.aggr) * 1.15
	sim.stamina = sim.max_stamina * clampf(me_stam, 0.05, 1.0)
	sim.min_stamina = sim.stamina
	sim.opp_stamina = 100.0 * clampf(them_stam, 0.05, 1.0)
	if me.get("player", false) and Game.style != "":
		sim.signature = Rpg.STYLES[Game.style].signature

## Simulates a bout with a bot on our side. Returns {won, draw, by_sub, sub, score, me_stam, them_stam}.
static func sim_bout(me: Dictionary, them: Dictionary, me_stam: float, them_stam: float, seed_value := -1) -> Dictionary:
	var sim := RollSim.new()
	setup_sim(sim, me, them, me_stam, them_stam, seed_value)
	var bot := RollBot.with_skill(RollBot.skill_between(0.5))
	if seed_value >= 0:
		bot.rng.seed = seed_value + 7
	var r: Dictionary = bot.play(sim).duplicate()
	r["me_stam"] = sim.stamina / sim.max_stamina
	r["them_stam"] = sim.opp_stamina / 100.0
	return r

# ------------------------------------------------------------ the match
## A 5v5 in progress. ours/theirs: arrays of fighter dicts in lineup order.
class Match:
	var ours: Array = []
	var theirs: Array = []
	var coach := {}
	var their_coach := {}
	var academy := ""
	var zone := ""
	var i := 0        # our fighter on the mat
	var j := 0        # theirs
	var stam_ours := 1.0
	var stam_theirs := 1.0
	var feed: Array = []   # [text, colour]
	var bouts := 0

	func current_ours() -> Dictionary:
		return ours[i] if i < ours.size() else {}

	func current_theirs() -> Dictionary:
		return theirs[j] if j < theirs.size() else {}

	func over() -> bool:
		return i >= ours.size() or j >= theirs.size()

	func won() -> bool:
		return j >= theirs.size() and i < ours.size()

	## Applies a bout result (from our fighter's side). me_stam / them_stam: 0..1 after the bout.
	func apply(r: Dictionary, me_stam: float, them_stam: float) -> void:
		bouts += 1
		var a := current_ours()
		var b := current_theirs()
		var how := "by %s" % Data.MOVES[r.sub].name if r.get("by_sub", false) and Data.MOVES.has(str(r.get("sub", ""))) else ("on points %d-%d" % [r.score[0], r.score[1]] if r.has("score") else "")
		if r.get("draw", false):
			feed.append(["Draw: %s and %s are both out." % [a.name, b.name], Color(0.8, 0.8, 0.75)])
			i += 1
			j += 1
			stam_ours = 1.0
			stam_theirs = 1.0
			return
		if r.won:
			feed.append(["%s beats %s %s." % [a.name, b.name, how], Color(0.45, 1.0, 0.55)])
			j += 1
			stam_ours = clampf(me_stam + (Team.BETWEEN_REGEN + Team.coach_heal(coach)) / 100.0 - Team._drain(b), 0.1, 1.0)
			stam_theirs = 1.0
		else:
			feed.append(["%s beats %s %s." % [b.name, a.name, how], Color(1.0, 0.5, 0.45)])
			i += 1
			stam_theirs = clampf(them_stam + (Team.BETWEEN_REGEN + Team.coach_heal(their_coach) * 0.7) / 100.0 - Team._drain(a), 0.1, 1.0)
			stam_ours = 1.0

static func _drain(loser: Dictionary) -> float:
	match str(loser.get("role", "")):
		"anchor":
			return 0.10
		"grinder":
			return 0.15
	return 0.0

static func new_match(zone: String, lineup: Dictionary, nonce: int) -> Match:
	var m := Match.new()
	m.zone = zone
	var e := make_enemy(zone, nonce, lineup.order)
	m.theirs = e.fighters
	m.their_coach = e.coach
	m.academy = e.academy
	for id in lineup.order:
		var f := find(str(id))
		if not f.is_empty():
			m.ours.append(f)
	m.coach = find(str(lineup.get("coach", "")))
	return m
