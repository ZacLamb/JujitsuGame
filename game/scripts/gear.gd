class_name Gear
extends RefCounted
## Gear, WoW-style: paper-doll slots, the quality ladder, item sets with 2/4-piece bonuses, and two
## kits (gi / no-gi) like saved equipment sets. Every item carries a `look` (colour, trim, pattern)
## that dresses the sculpted fighter model, so sets have a signature style (Onça rosettes, Jacaré
## scales, Véu waves, Leão's gold mane).
##
## Gis are authored once in GIS and become two items: the jacket (<id>) and the pants (<id>_pants).

const SLOTS := ["head", "jacket", "pants", "rash", "spats", "knees", "tape"]
const SLOT_NAMES := {"head": "Head", "jacket": "Gi Jacket", "pants": "Gi Pants", "rash": "Rashguard",
	"spats": "Spats", "knees": "Knee Sleeves", "tape": "Finger Tape"}
## Paper-doll columns (left / right of the character), like the WoW character pane.
const DOLL_LEFT := ["head", "jacket", "rash", "tape"]
const DOLL_RIGHT := ["pants", "spats", "knees"]
## Which slots count (and show) in each kit. Rashguards go under the gi too.
const KITS := {"gi": ["head", "jacket", "pants", "rash", "knees", "tape"], "nogi": ["head", "rash", "spats", "knees", "tape"]}
const KIT_NAMES := {"gi": "Gi", "nogi": "No-Gi"}

const RARITY := {
	"common": {"name": "Common", "color": Color(0.92, 0.92, 0.92)},
	"uncommon": {"name": "Uncommon", "color": Color(0.2, 0.9, 0.25)},
	"rare": {"name": "Rare", "color": Color(0.25, 0.55, 1.0)},
	"epic": {"name": "Epic", "color": Color(0.7, 0.35, 1.0)},
	"legendary": {"name": "Legendary", "color": Color(1.0, 0.55, 0.1)},
}

## Gis: jacket + matching pants. attrs go on the jacket, pants_attrs on the pants.
## look: color (cloth), trim (lapels/collar/cuffs), pattern + accent + pscale (shader pattern).
const GIS := {
	"standard_gi": {"name": "Standard Gi", "rarity": "common", "attrs": {}, "pants_attrs": {},
		"look": {"color": Color(0.96, 0.96, 0.94)},
		"source": "Your first gi", "desc": "Pearl weave, a little stiff, smells like new."},
	"terere_gi": {"name": "Tereré Green Gi", "rarity": "uncommon", "attrs": {"cardio": 1}, "pants_attrs": {},
		"look": {"color": Color(0.22, 0.5, 0.3), "trim": Color(0.95, 0.85, 0.4)},
		"source": "Quest: Tereré Run", "desc": "Dona Lurdes's late husband's gi. Still smells like lemon."},
	"onca_gi": {"name": "Onça Pintada Gi", "rarity": "rare", "set": "onca", "attrs": {"grip": 2, "strength": 1}, "pants_attrs": {"grip": 1},
		"look": {"color": Color(0.9, 0.68, 0.26), "trim": Color(0.12, 0.09, 0.07), "pattern": "spots", "accent": Color(0.14, 0.1, 0.07)},
		"source": "Mestre Onça", "desc": "Gold weave with black lapels. Onça's old competition gi."},
	"pantaneiro_gi": {"name": "Pantaneiro Gi", "rarity": "rare", "attrs": {"cardio": 2, "flexibility": 1}, "pants_attrs": {"cardio": 1},
		"look": {"color": Color(0.2, 0.45, 0.5), "trim": Color(0.85, 0.7, 0.4)},
		"source": "Quest: Submission Hunter", "desc": "Light enough to dry in the Pantanal sun in ten minutes."},
	"jacare_gi": {"name": "Jacaré Hide Gi", "rarity": "epic", "set": "jacare", "attrs": {"strength": 2, "grip": 2}, "pants_attrs": {"strength": 1, "flexibility": 1},
		"look": {"color": Color(0.32, 0.4, 0.2), "trim": Color(0.62, 0.56, 0.3), "pattern": "scales", "accent": Color(0.17, 0.22, 0.1)},
		"source": "Mestre Jacaré", "desc": "Heavy, rough and impossible to grip. Like its owner."},
	"red_cliff_gi": {"name": "Red Cliff Gi", "rarity": "rare", "attrs": {"flexibility": 2, "iq": 1}, "pants_attrs": {"flexibility": 1},
		"look": {"color": Color(0.7, 0.32, 0.2), "trim": Color(0.95, 0.9, 0.8), "pattern": "stripes", "accent": Color(0.6, 0.26, 0.16)},
		"source": "Quest: Crystal Clear", "desc": "Dyed with Chapada clay. Every wash it gets redder."},
	"veu_gi": {"name": "Véu de Noiva Gi", "rarity": "epic", "set": "veu", "attrs": {"flexibility": 2, "cardio": 2}, "pants_attrs": {"cardio": 1, "iq": 1},
		"look": {"color": Color(0.72, 0.86, 0.96), "trim": Color(0.2, 0.35, 0.55), "pattern": "waves", "accent": Color(0.95, 0.98, 1.0)},
		"source": "Mestre Cachoeira", "desc": "Flows like the waterfall. Slips every grip."},
	"copacabana_gi": {"name": "Copacabana Gi", "rarity": "rare", "attrs": {"cardio": 1, "grip": 1, "iq": 1}, "pants_attrs": {"iq": 1},
		"look": {"color": Color(0.3, 0.6, 0.9), "trim": Color(0.98, 0.85, 0.2), "pattern": "waves", "accent": Color(0.25, 0.52, 0.82)},
		"source": "Quest: Beach Session", "desc": "Sky blue with gold collar. Sand not included (it's included)."},
	"leao_gi": {"name": "Lion's Mane Gi", "rarity": "legendary", "set": "leao", "attrs": {"strength": 2, "grip": 2, "iq": 2}, "pants_attrs": {"strength": 1, "iq": 1},
		"look": {"color": Color(0.08, 0.08, 0.09), "trim": Color(0.95, 0.72, 0.2), "pattern": "mane", "accent": Color(0.85, 0.6, 0.15)},
		"source": "Grão-Mestre Leão", "desc": "Black with a gold collar. Leão wore it to his first world title."},
	"mundial_gi": {"name": "Campeão Mundial Gi", "rarity": "legendary", "set": "mundial", "attrs": {"strength": 2, "grip": 2, "cardio": 2, "flexibility": 2, "iq": 2}, "pants_attrs": {"cardio": 1, "grip": 1},
		"look": {"color": Color(0.97, 0.97, 0.95), "trim": Color(0.95, 0.72, 0.2)},
		"source": "Gold at the Campeonato Mundial", "desc": "White and gold. Only world champions wear this one."},
}

## Everything that isn't a gi. look as above.
const OTHER := {
	# ---------------- rashguards (under the gi at the collar, or the whole top in no-gi)
	"rash_white": {"slot": "rash", "name": "Ranked Rashguard (White)", "rarity": "common", "attrs": {},
		"look": {"color": Color(0.95, 0.95, 0.93)}, "source": "Starter gear", "desc": "Everyone starts somewhere."},
	"rash_blue": {"slot": "rash", "name": "Ranked Rashguard (Blue)", "rarity": "uncommon", "attrs": {"cardio": 1},
		"look": {"color": Color(0.15, 0.35, 0.85)}, "source": "Promotion to blue belt", "desc": "Ranked colors, blue belt edition."},
	"rash_purple": {"slot": "rash", "name": "Ranked Rashguard (Purple)", "rarity": "uncommon", "attrs": {"cardio": 1, "flexibility": 1},
		"look": {"color": Color(0.45, 0.2, 0.65)}, "source": "Promotion to purple belt", "desc": "Ranked colors, purple belt edition."},
	"rash_brown": {"slot": "rash", "name": "Ranked Rashguard (Brown)", "rarity": "rare", "attrs": {"cardio": 1, "strength": 1, "iq": 1},
		"look": {"color": Color(0.42, 0.26, 0.13)}, "source": "Promotion to brown belt", "desc": "Ranked colors, brown belt edition."},
	"rash_black": {"slot": "rash", "name": "Ranked Rashguard (Black)", "rarity": "epic", "attrs": {"cardio": 2, "strength": 1, "iq": 1},
		"look": {"color": Color(0.08, 0.08, 0.08)}, "source": "Promotion to black belt", "desc": "Ranked colors. The last one."},
	"rash_arara": {"slot": "rash", "name": "Arara Rashguard", "rarity": "rare", "attrs": {"flexibility": 1, "cardio": 1},
		"look": {"color": Color(0.9, 0.2, 0.15), "pattern": "feathers", "accent": Color(0.15, 0.4, 0.9)},
		"source": "Quest: Feathers for the Festival", "desc": "Red, blue and gold, like the birds."},
	"rash_projeto": {"slot": "rash", "name": "Projeto Social Rashguard", "rarity": "epic", "attrs": {"iq": 2, "cardio": 1},
		"look": {"color": Color(0.98, 0.8, 0.2), "pattern": "stripes", "accent": Color(0.15, 0.5, 0.25)},
		"source": "Quest: Kids' Class", "desc": "Signed by forty kids from the morro."},
	"jacare_rash": {"slot": "rash", "name": "Jacaré Hide Rashguard", "rarity": "epic", "set": "jacare", "attrs": {"strength": 1, "cardio": 1},
		"look": {"color": Color(0.26, 0.32, 0.16), "pattern": "scales", "accent": Color(0.14, 0.18, 0.08)},
		"source": "Mestre Jacaré", "desc": "Second skin, swamp edition."},
	"veu_rash": {"slot": "rash", "name": "Véu de Noiva Rashguard", "rarity": "epic", "set": "veu", "attrs": {"flexibility": 1, "cardio": 1},
		"look": {"color": Color(0.18, 0.32, 0.52), "pattern": "waves", "accent": Color(0.7, 0.86, 0.96)},
		"source": "Mestre Cachoeira", "desc": "Cold as the pool under the falls."},
	# ---------------- spats (no-gi)
	"spats_black": {"slot": "spats", "name": "Training Spats", "rarity": "common", "attrs": {},
		"look": {"color": Color(0.1, 0.1, 0.12)}, "source": "Starter gear", "desc": "Black, plain, honest."},
	"veu_spats": {"slot": "spats", "name": "Véu de Noiva Spats", "rarity": "epic", "set": "veu", "attrs": {"flexibility": 2},
		"look": {"color": Color(0.18, 0.32, 0.52), "pattern": "waves", "accent": Color(0.7, 0.86, 0.96)},
		"source": "Mestre Cachoeira", "desc": "Matching set. The waterfall approves."},
	# ---------------- knees
	"jacare_knees": {"slot": "knees", "name": "Jacaré Knee Sleeves", "rarity": "epic", "set": "jacare", "attrs": {"strength": 1, "flexibility": 1},
		"look": {"color": Color(0.2, 0.24, 0.12), "pattern": "scales", "accent": Color(0.12, 0.15, 0.07)},
		"source": "Mestre Jacaré", "desc": "Armour for the knee-slice."},
	# ---------------- head
	"onca_headband": {"slot": "head", "name": "Onça Headband", "rarity": "rare", "set": "onca", "attrs": {"iq": 1}, "piece": "Headband",
		"look": {"color": Color(0.9, 0.68, 0.26), "pattern": "spots", "accent": Color(0.14, 0.1, 0.07), "pscale": 1.6},
		"source": "Mestre Onça", "desc": "Keeps the sweat out of your eyes and the fear in theirs."},
	"leao_earguards": {"slot": "head", "name": "Lion's Ear Guards", "rarity": "legendary", "set": "leao", "attrs": {"iq": 1, "strength": 1}, "piece": "EarGuards",
		"look": {"color": Color(0.1, 0.1, 0.11), "pattern": "mane", "accent": Color(0.9, 0.65, 0.15)},
		"source": "Grão-Mestre Leão", "desc": "No cauliflower for kings."},
	# ---------------- finger tape
	"tape_basic": {"slot": "tape", "name": "Finger Tape", "rarity": "uncommon", "attrs": {"grip": 1},
		"look": {"color": Color(0.96, 0.96, 0.92)}, "source": "Quest: Shrimping 101", "desc": "Kaique's spare roll. Tape the ring and middle fingers."},
	"tape_climber": {"slot": "tape", "name": "Climber's Tape", "rarity": "rare", "attrs": {"grip": 2},
		"look": {"color": Color(0.85, 0.75, 0.55)}, "source": "Quest: Iron Grip", "desc": "Nanda swears by it on the cliffs."},
	"tape_pro": {"slot": "tape", "name": "Competition Tape", "rarity": "epic", "attrs": {"grip": 3},
		"look": {"color": Color(0.2, 0.2, 0.22)}, "source": "Gold medal at any competition", "desc": "Pre-cut strips, perfect tension, podium-tested."},
	"onca_tape": {"slot": "tape", "name": "Onça Claw Tape", "rarity": "rare", "set": "onca", "attrs": {"grip": 2},
		"look": {"color": Color(0.12, 0.09, 0.07)}, "source": "Mestre Onça", "desc": "Black tape. Grips like claws."},
	"leao_tape": {"slot": "tape", "name": "Lion's Paw Tape", "rarity": "legendary", "set": "leao", "attrs": {"grip": 3},
		"look": {"color": Color(0.95, 0.72, 0.2)}, "source": "Grão-Mestre Leão", "desc": "Gold tape. You will be seen."},
}

## Item sets. Bonuses unlock at 2 and 4 equipped pieces (in the active kit). An effect id hooks
## into the roll (see Game.mods and RollSim).
const SETS := {
	"onca": {"name": "Onça Pintada", "pieces": ["onca_gi", "onca_gi_pants", "onca_tape", "onca_headband"],
		"bonus": {2: {"attrs": {"grip": 1}}, 4: {"effect": "pounce", "text": "Pounce: you start every new position with 1 Grip Control."}}},
	"jacare": {"name": "Couro de Jacaré", "pieces": ["jacare_gi", "jacare_gi_pants", "jacare_rash", "jacare_knees"],
		"bonus": {2: {"attrs": {"strength": 1}}, 4: {"effect": "death_roll", "text": "Death Roll: your landed sweeps and takedowns drain 15 of their stamina."}}},
	"veu": {"name": "Véu de Noiva", "pieces": ["veu_gi", "veu_gi_pants", "veu_rash", "veu_spats"],
		"bonus": {2: {"attrs": {"flexibility": 1}}, 4: {"effect": "flow", "text": "Flow: every interrupt refunds 6 stamina."}}},
	"leao": {"name": "Juba do Leão", "pieces": ["leao_gi", "leao_gi_pants", "leao_earguards", "leao_tape"],
		"bonus": {2: {"attrs": {"iq": 1}}, 4: {"effect": "roar", "text": "Roar: their casts take 10% longer."}}},
	"mundial": {"name": "Campeão Mundial", "pieces": ["mundial_gi", "mundial_gi_pants"],
		"bonus": {2: {"effect": "champion", "text": "Champion: your techniques are 4% more likely to land."}}},
}

## Bosses drop pieces of their set (one you don't own each win, the jacket first).
const BOSS_SET := {"onca": "onca", "jacare": "jacare", "cachoeira": "veu", "leao": "leao"}
const QUEST_LOOT := {"terere_run": "terere_gi", "shrimping": "tape_basic", "sub_hunter": "pantaneiro_gi",
	"festival_feathers": "rash_arara", "crystal_clear": "red_cliff_gi", "iron_grip": "tape_climber",
	"beach_session": "copacabana_gi", "kids_class": "rash_projeto"}
const PROMOTION_LOOT := {1: "rash_blue", 2: "rash_purple", 3: "rash_brown", 4: "rash_black"}
## Items that come as a pair: getting the jacket also gives the pants (quests, medals).
const STARTER := ["standard_gi", "standard_gi_pants", "rash_white", "spats_black"]

static var ITEMS := {}

static func _static_init() -> void:
	for id in GIS:
		var g: Dictionary = GIS[id]
		var base := {"rarity": g.rarity, "look": g.look, "source": g.source}
		if g.has("set"):
			base["set"] = g.set
		var j := base.duplicate()
		j.merge({"slot": "jacket", "name": g.name + " Jacket", "attrs": g.attrs, "desc": g.desc, "gi": id})
		ITEMS[id] = j
		var p := base.duplicate()
		p.merge({"slot": "pants", "name": g.name + " Pants", "attrs": g.pants_attrs, "desc": "Matching pants.", "gi": id})
		ITEMS[id + "_pants"] = p
	for id in OTHER:
		ITEMS[id] = OTHER[id]

static func power(id: String) -> int:
	var n := 0
	for k in ITEMS[id].attrs:
		n += int(ITEMS[id].attrs[k])
	return n

static func rarity_color(id: String) -> Color:
	return RARITY[ITEMS[id].rarity].color

static func look(id: String) -> Dictionary:
	return ITEMS.get(id, {}).get("look", {})

static func stat_text(id: String) -> String:
	var parts: Array[String] = []
	for k in Rpg.ATTR_ORDER:
		var v := int(ITEMS[id].attrs.get(k, 0))
		if v > 0:
			parts.append("+%d %s" % [v, Rpg.ATTRS[k].name])
	return ", ".join(parts) if not parts.is_empty() else "No bonus"

## Text lines for a set's bonuses, e.g. ["(2) +1 Grip", "(4) Pounce: ..."].
static func set_lines(set_id: String) -> Array:
	var out: Array = []
	var b: Dictionary = SETS[set_id].bonus
	for n in [2, 4]:
		if not b.has(n):
			continue
		var t := ""
		for k in b[n].get("attrs", {}):
			t += "+%d %s " % [int(b[n].attrs[k]), Rpg.ATTRS[k].name]
		if b[n].has("text"):
			t += str(b[n].text)
		out.append([n, t.strip_edges()])
	return out

## The full look of a boss in their own set (so Onça wears the rosettes when you fight him).
static func set_look(set_id: String) -> Dictionary:
	var lk := {"kit": "gi"}
	for pid in SETS[set_id].pieces:
		var it: Dictionary = ITEMS[pid]
		lk[it.slot] = it.look
		if it.slot == "head":
			lk["head_piece"] = it.get("piece", "Headband")
	return lk
