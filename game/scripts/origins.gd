class_name Origins
extends RefCounted
## Where you're from: Tatame's "race" (WoW: Human / Orc...). A small attribute bonus, a passive
## and an active "racial" on G. Every origin can play every class; it's flavour plus a nudge.

const ORDER := ["gringo", "carioca", "pantaneiro", "gaucho", "nordestino", "paulista",
	"brazuca", "texan", "floridian", "midwesterner", "new_yorker", "californian"]

## Two factions, like WoW's Alliance and Horde: your origin decides which one you start in.
## Each has its own starting zone, its own road to black belt (Lv 1-50) and its own story.
const FACTIONS := {
	"brasil": {"name": "Brasil", "long": "Time Brasil", "tag": "The home of jiu-jitsu.",
		"desc": "Start in Cáceres, Mato Grosso, and earn your belts on the road to Rio. Old-school, gi-first, every master a legend.",
		"start": "caceres", "path": ["caceres", "pantanal", "chapada", "rio"], "color": Color(0.25, 0.75, 0.35), "accent": Color(1.0, 0.85, 0.2)},
	"usa": {"name": "USA", "long": "Team USA", "tag": "Wrestlers, garages and leg locks.",
		"desc": "Start in Dry Creek, Texas, and fight your way coast to coast to San Diego. Wrestling roots, no-gi innovation, a garage gym on every corner.",
		"start": "texas", "path": ["texas", "everglades", "sedona", "socal"], "color": Color(0.25, 0.45, 0.95), "accent": Color(0.95, 0.3, 0.3)},
}

static func faction_of(id: String) -> String:
	return str(get_origin(id).get("faction", "brasil"))

static func faction(id: String) -> Dictionary:
	return FACTIONS.get(id, FACTIONS.brasil)

const ORIGINS := {
	"gringo": {"name": "Gringo", "tag": "New in town.",
		"desc": "Moved to Brazil with a white belt and a dream. Everyone wants to roll with the foreigner, and you learn from every one of them.",
		"attrs": {"iq": 1}, "passive": "Fast Learner: +10% experience from every source.", "mods": {"xp_bonus": 0.10},
		"racial": {"name": "Beginner's Luck", "effect": "lucky", "cd": 120.0,
			"text": "Your next attack is a guaranteed critical hit."}},
	"carioca": {"name": "Carioca", "tag": "Raised on the sand.",
		"desc": "Grew up training on Rio's beaches between surf sessions. Loose, playful and impossible to pin down.",
		"attrs": {"flexibility": 1}, "passive": "Beach Lungs: +10% Gas regeneration.", "mods": {"regen_mult": 0.10},
		"racial": {"name": "Jeitinho", "effect": "jeitinho", "cd": 120.0, "gcd": false, "harm": false,
			"text": "There's always a way out: instantly break free of Down and Pinned. Usable while Down."}},
	"pantaneiro": {"name": "Pantaneiro", "tag": "Ranch-strong.",
		"desc": "Ranch hand from the Pantanal wetlands. Roping cattle since you could walk gave you a grip like a vice.",
		"attrs": {"grip": 1}, "passive": "Ranch Hands: +5% maximum Composure.", "mods": {"hp": 0.05},
		"racial": {"name": "Laço", "effect": "lasso", "cd": 90.0, "gcd": false, "harm": false,
			"text": "Rope them in: instantly gain 2 Grip."}},
	"gaucho": {"name": "Gaúcho", "tag": "Built for the cold.",
		"desc": "From the far south, where the winters are hard and so are the people. Doesn't break.",
		"attrs": {"strength": 1}, "passive": "Thick Skin: take 3% less damage.", "mods": {"dr": 0.03},
		"racial": {"name": "Chimarrão", "effect": "mate", "cd": 120.0, "gcd": false, "harm": false,
			"text": "A gourd of mate between rounds: restore 25% Composure over 6 seconds."}},
	"nordestino": {"name": "Nordestino", "tag": "Capoeira in the blood.",
		"desc": "From the northeast, where you learned capoeira's ginga before you learned the guard. Rhythm and timing.",
		"attrs": {"flexibility": 1}, "passive": "Ginga Rhythm: 3% haste.", "mods": {"haste": 0.03},
		"racial": {"name": "Ginga", "effect": "ginga", "cd": 120.0, "gcd": false, "harm": false,
			"text": "Sway out of everything: take 70% less damage for 3 seconds."}},
	"paulista": {"name": "Paulista", "tag": "Big-city competitor.",
		"desc": "From São Paulo, where every gym is a competition team and every roll is a final.",
		"attrs": {"cardio": 1}, "passive": "Competitor: +3% critical strike chance.", "mods": {"crit": 0.03},
		"racial": {"name": "Rush Hour", "effect": "rush", "cd": 120.0, "gcd": false, "harm": false,
			"text": "Turn it up: deal 20% more damage for 8 seconds."}},
	# ---------------- Team USA
	"brazuca": {"name": "Brazuca", "tag": "Brazilian in the States.", "faction": "usa",
		"desc": "Grew up in Brazil, moved to Texas for work, found a garage gym on the first week. Everyone wants to roll with the Brazilian.",
		"attrs": {"iq": 1}, "passive": "Saudade: +10% experience from every source.", "mods": {"xp_bonus": 0.10},
		"racial": {"name": "Beginner's Luck", "effect": "lucky", "cd": 120.0,
			"text": "Your next attack is a guaranteed critical hit."}},
	"texan": {"name": "Texan", "tag": "Raised on a ranch.", "faction": "usa",
		"desc": "Hill Country born, roping steers and wrestling in the high school gym. Hands like a vice.",
		"attrs": {"grip": 1}, "passive": "Ranch Hands: +5% maximum Composure.", "mods": {"hp": 0.05},
		"racial": {"name": "Lasso", "effect": "lasso", "cd": 90.0, "gcd": false, "harm": false,
			"text": "Rope them in: instantly gain 2 Grip."}},
	"floridian": {"name": "Floridian", "tag": "Somehow always gets away.", "faction": "usa",
		"desc": "Swamp kid. Airboats, gators and hurricanes. Nothing holds you down for long.",
		"attrs": {"flexibility": 1}, "passive": "Humid Lungs: +10% Gas regeneration.", "mods": {"regen_mult": 0.10},
		"racial": {"name": "Slippery", "effect": "jeitinho", "cd": 120.0, "gcd": false, "harm": false,
			"text": "There's always a way out: instantly break free of Down and Pinned. Usable while Down."}},
	"midwesterner": {"name": "Midwesterner", "tag": "Farm strong, polite about it.", "faction": "usa",
		"desc": "Iowa wrestling room, sub-zero winters, never complains. Apologises while crushing you.",
		"attrs": {"strength": 1}, "passive": "Thick Skin: take 3% less damage.", "mods": {"dr": 0.03},
		"racial": {"name": "Hotdish", "effect": "mate", "cd": 120.0, "gcd": false, "harm": false,
			"text": "Comfort food between rounds: restore 25% Composure over 6 seconds."}},
	"new_yorker": {"name": "New Yorker", "tag": "No time to waste.", "faction": "usa",
		"desc": "Basement gyms in the city that never sleeps. Every roll is a competition, every round a final.",
		"attrs": {"cardio": 1}, "passive": "Competitor: +3% critical strike chance.", "mods": {"crit": 0.03},
		"racial": {"name": "Hustle", "effect": "rush", "cd": 120.0, "gcd": false, "harm": false,
			"text": "Turn it up: deal 20% more damage for 8 seconds."}},
	"californian": {"name": "Californian", "tag": "Chill until it isn't.", "faction": "usa",
		"desc": "Surf in the morning, no-gi at noon, leg locks by night. Loose, relaxed and impossible to rattle.",
		"attrs": {"flexibility": 1}, "passive": "Flow State: 3% haste.", "mods": {"haste": 0.03},
		"racial": {"name": "Hang Loose", "effect": "ginga", "cd": 120.0, "gcd": false, "harm": false,
			"text": "Go limp and roll with it: take 70% less damage for 3 seconds."}},
}

static func get_origin(id: String) -> Dictionary:
	return ORIGINS.get(id, ORIGINS.gringo)

static func apply(m: Dictionary, id: String) -> void:
	var o := get_origin(id)
	for k in o.mods:
		var v := float(o.mods[k])
		match k:
			"hp":
				m["hp_mult"] = float(m.get("hp_mult", 1.0)) + v
			"haste":
				m.decision = float(m.decision) * (1.0 + v)
			"regen_mult":
				m.regen = float(m.regen) * (1.0 + v)
			_:
				m[k] = float(m.get(k, 0.0)) + v

static func racial(id: String) -> Dictionary:
	var o := get_origin(id)
	var r: Dictionary = o.racial.duplicate()
	r["id"] = "racial"
	r["type"] = "racial"
	r["key"] = "G"
	r["cost"] = 0.0
	if not r.has("harm"):
		r["harm"] = false
	return r
