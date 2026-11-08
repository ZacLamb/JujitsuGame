class_name Circuit
extends RefCounted
## Circuito: a roguelite tournament run. Five matches back to back, one life. Stamina carries over
## (with partial recovery), and after every win you draft 1 of 3 coaching cards whose perks stack
## for the rest of the run. The final is a master you've already beaten, scaled to your level and
## fighting with their raid phases.

const ROUNDS := 5
const RECOVER := 0.4            # stamina back between matches (fraction of max)
const ROUND_NAMES := ["Opening Round", "Round 2", "Quarterfinal", "Semifinal", "Final"]

const RARITY := {"common": {"name": "Common", "color": Color(0.92, 0.92, 0.92), "w": 6.0},
	"rare": {"name": "Rare", "color": Color(0.25, 0.55, 1.0), "w": 3.0},
	"epic": {"name": "Epic", "color": Color(0.7, 0.35, 1.0), "w": 1.2}}

## Coaching cards. Effects are read by perk_mods (before the sim is built) / perk_start (after).
const CARDS := {
	"iron_lungs": {"name": "Iron Lungs", "rarity": "common", "icon": "heart", "desc": "+20 max stamina."},
	"ice_bath": {"name": "Ice Bath", "rarity": "common", "icon": "wave", "desc": "Recover 30% more stamina between matches."},
	"grip_head": {"name": "Grip Head Start", "rarity": "common", "icon": "link", "desc": "Start every match with 2 Grip Control."},
	"film_study": {"name": "Film Study", "rarity": "common", "icon": "shield", "desc": "Their casts take 10% longer."},
	"killer": {"name": "Killer Instinct", "rarity": "rare", "icon": "bolt", "desc": "Your submissions start 10% deeper."},
	"sprawl": {"name": "Sprawl & Brawl", "rarity": "rare", "icon": "down", "desc": "25% more time against takedowns and sweeps."},
	"poker_face": {"name": "Poker Face", "rarity": "rare", "icon": "star", "desc": "They read your techniques 40% less often."},
	"gas_station": {"name": "Gas Station", "rarity": "rare", "icon": "heart", "desc": "Breathe restores 30 stamina instead of 20."},
	"thief": {"name": "Grip Thief", "rarity": "epic", "icon": "link", "desc": "Every interrupt steals an extra grip."},
	"heavy": {"name": "Heavy Pressure", "rarity": "epic", "icon": "chevron", "desc": "Your techniques land 5% more often."},
	"second_wind": {"name": "Second Wind", "rarity": "epic", "icon": "heart", "desc": "Once per match, recover 40 stamina when you drop below 20."},
}

static func count(perks: Array, id: String) -> int:
	return perks.count(id)

## Perks that change the roll modifiers (applied before the sim is built).
static func perk_mods(m: Dictionary, perks: Array) -> void:
	m.stamina_max = float(m.stamina_max) + 20.0 * count(perks, "iron_lungs")
	m.defense = float(m.defense) * pow(1.1, count(perks, "film_study"))
	m.sub_start = float(m.sub_start) + 0.1 * count(perks, "killer")
	for t in ["takedown", "sweep"]:
		m.defense_vs[t] = float(m.defense_vs.get(t, 1.0)) * pow(1.25, count(perks, "sprawl"))
	if count(perks, "poker_face") > 0:
		m["read_resist"] = pow(0.6, count(perks, "poker_face"))
	if count(perks, "gas_station") > 0:
		m["second_breath"] = true
	if count(perks, "thief") > 0:
		m["steal"] = count(perks, "thief")
	if count(perks, "heavy") > 0:
		m["edge"] = float(m.get("edge", 0.0)) + 0.05 * count(perks, "heavy")
	if count(perks, "second_wind") > 0:
		m.second_wind = true

## Perks that change the starting state.
static func perk_start(sim: RollSim, perks: Array) -> void:
	sim.control = mini(RollSim.MAX_CONTROL, 2 * count(perks, "grip_head"))

## Three distinct cards, weighted by rarity.
static func offer(rng: RandomNumberGenerator) -> Array:
	var pool: Array = CARDS.keys()
	var out: Array = []
	while out.size() < 3 and not pool.is_empty():
		var tot := 0.0
		for id in pool:
			tot += float(RARITY[CARDS[id].rarity].w)
		var r := rng.randf() * tot
		for id in pool:
			r -= float(RARITY[CARDS[id].rarity].w)
			if r <= 0.0:
				out.append(id)
				pool.erase(id)
				break
	return out

## The ladder: four generated opponents, then a beaten master (with phases) as the final.
static func make_ladder(nonce: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("circuito-%d-%d" % [Game.rank / 5, nonce])
	var pl := Game.level()
	var out: Array = []
	var gis := [Color(0.95, 0.95, 0.95), Color(0.15, 0.3, 0.75), Color(0.1, 0.1, 0.12)]
	var styles := ["guard", "pressure", "back", "submission", "balanced"]
	for i in ROUNDS - 1:
		var nm := "%s %s" % [Data.COMP_FIRST[rng.randi() % Data.COMP_FIRST.size()], Data.COMP_LAST[rng.randi() % Data.COMP_LAST.size()]]
		var st: String = styles[rng.randi() % styles.size()]
		out.append({"id": "c%d" % i, "name": nm, "role": Team.STYLE_ROLE.get(st, "anchor"), "style": st,
			"academy": Data.ACADEMIES[rng.randi() % Data.ACADEMIES.size()],
			"gi": gis[rng.randi() % gis.size()], "skin": Color(0.96, 0.8, 0.68).lerp(Color(0.36, 0.22, 0.14), rng.randf()),
			"body": "female" if rng.randf() < 0.3 else "male", "extra": [], "rank": clampi(Game.rank + rng.randi_range(-1, 2), 0, 24),
			"level": pl - 0.15 + i * 0.4 + rng.randf_range(-0.1, 0.1),
			"win_line": "Good luck in the next round.", "lose_line": "Next time, gringo."})
	var masters: Array = []
	for id in Boss.PHASES:
		if Game.beaten(id):
			masters.append(id)
	if masters.is_empty():
		masters = ["onca"]
	var mid: String = masters[rng.randi() % masters.size()]
	var f := Team.from_opponent(mid)
	f["level"] = pl + 1.3
	f["rank"] = clampi(maxi(int(f.rank), Game.rank), 0, 24)
	f["phases_of"] = mid
	f["academy"] = "Guest of honour"
	f["win_line"] = "The Circuito is mine. Come back stronger."
	f["lose_line"] = "Campeão do Circuito. You earned it."
	out.append(f)
	return out

## A run in progress.
class Run:
	var ladder: Array = []
	var round := 0
	var perks: Array = []
	var stamina := 1.0
	var offers: Array = []
	var rng := RandomNumberGenerator.new()
	var lost := false
	var feed: Array = []

	func current() -> Dictionary:
		return ladder[round] if round < ladder.size() else {}

	func over() -> bool:
		return lost or round >= ladder.size()

	func champion() -> bool:
		return not lost and round >= ladder.size()

	## Record a match (result from the roll, stamina 0..1 after it).
	func apply(r: Dictionary, me_stam: float) -> void:
		var o := current()
		if r.get("won", false):
			feed.append(["%s: beat %s" % [Circuit.ROUND_NAMES[round], o.name], Color(0.45, 1.0, 0.55)])
			round += 1
			var rec := Circuit.RECOVER + 0.3 * Circuit.count(perks, "ice_bath")
			stamina = clampf(me_stam + rec, 0.15, 1.0)
			if round < ladder.size():
				offers = Circuit.offer(rng)
		else:
			feed.append(["%s: lost to %s" % [Circuit.ROUND_NAMES[round], o.name], Color(1.0, 0.5, 0.45)])
			lost = true

static func new_run(nonce: int) -> Run:
	var r := Run.new()
	r.ladder = make_ladder(nonce)
	r.rng.seed = hash("circuito-cards-%d" % nonce)
	r.offers = offer(r.rng)   # a first card before the opening round
	return r
