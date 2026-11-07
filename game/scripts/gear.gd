class_name Gear
extends RefCounted
## Gear: gis, rashguards and finger tape. Each piece adds attribute points and shows on the
## character. Rarity uses the WoW color ladder. Sources are bosses, quests, promotions and medals.

const SLOTS := ["gi", "rash", "tape"]
const SLOT_NAMES := {"gi": "Gi", "rash": "Rashguard", "tape": "Finger tape"}

const RARITY := {
	"common": {"name": "Common", "color": Color(0.92, 0.92, 0.92)},
	"uncommon": {"name": "Uncommon", "color": Color(0.2, 0.9, 0.25)},
	"rare": {"name": "Rare", "color": Color(0.25, 0.55, 1.0)},
	"epic": {"name": "Epic", "color": Color(0.7, 0.35, 1.0)},
	"legendary": {"name": "Legendary", "color": Color(1.0, 0.55, 0.1)},
}

## color: gi/rash color. lapel: optional lapel/collar accent. attrs: attribute bonuses.
const ITEMS := {
	# ---------------- gis
	"standard_gi": {"slot": "gi", "name": "Standard Gi", "rarity": "common", "attrs": {},
		"source": "Your first gi", "desc": "Pearl weave, a little stiff, smells like new."},
	"terere_gi": {"slot": "gi", "name": "Tereré Green Gi", "rarity": "uncommon", "attrs": {"cardio": 1},
		"color": Color(0.22, 0.5, 0.3), "lapel": Color(0.95, 0.85, 0.4),
		"source": "Quest: Tereré Run", "desc": "Dona Lurdes's late husband's gi. Still smells like lemon."},
	"onca_gi": {"slot": "gi", "name": "Onça Pintada Gi", "rarity": "rare", "attrs": {"grip": 2, "strength": 1},
		"color": Color(0.88, 0.66, 0.24), "lapel": Color(0.12, 0.09, 0.07),
		"source": "Defeat Mestre Onça", "desc": "Gold weave with black lapels. Onça's old competition gi."},
	"pantaneiro_gi": {"slot": "gi", "name": "Pantaneiro Gi", "rarity": "rare", "attrs": {"cardio": 2, "flexibility": 1},
		"color": Color(0.2, 0.45, 0.5), "lapel": Color(0.85, 0.7, 0.4),
		"source": "Quest: Submission Hunter", "desc": "Light enough to dry in the Pantanal sun in ten minutes."},
	"jacare_gi": {"slot": "gi", "name": "Jacaré Hide Gi", "rarity": "epic", "attrs": {"strength": 2, "grip": 2},
		"color": Color(0.32, 0.38, 0.2), "lapel": Color(0.6, 0.55, 0.3),
		"source": "Defeat Mestre Jacaré", "desc": "Heavy, rough and impossible to grip. Like its owner."},
	"red_cliff_gi": {"slot": "gi", "name": "Red Cliff Gi", "rarity": "rare", "attrs": {"flexibility": 2, "iq": 1},
		"color": Color(0.7, 0.32, 0.2), "lapel": Color(0.95, 0.9, 0.8),
		"source": "Quest: Crystal Clear", "desc": "Dyed with Chapada clay. Every wash it gets redder."},
	"veu_gi": {"slot": "gi", "name": "Véu de Noiva Gi", "rarity": "epic", "attrs": {"flexibility": 2, "cardio": 2},
		"color": Color(0.7, 0.85, 0.95), "lapel": Color(0.2, 0.35, 0.55),
		"source": "Defeat Mestre Cachoeira", "desc": "Flows like the waterfall. Slips every grip."},
	"copacabana_gi": {"slot": "gi", "name": "Copacabana Gi", "rarity": "rare", "attrs": {"cardio": 1, "grip": 1, "iq": 1},
		"color": Color(0.3, 0.6, 0.9), "lapel": Color(0.98, 0.85, 0.2),
		"source": "Quest: Beach Session", "desc": "Sky blue with gold collar. Sand not included (it's included)."},
	"leao_gi": {"slot": "gi", "name": "Lion's Mane Gi", "rarity": "legendary", "attrs": {"strength": 2, "grip": 2, "iq": 2},
		"color": Color(0.08, 0.08, 0.09), "lapel": Color(0.95, 0.72, 0.2),
		"source": "Defeat Grão-Mestre Leão", "desc": "Black with a gold collar. Leão wore it to his first world title."},
	"mundial_gi": {"slot": "gi", "name": "Campeão Mundial Gi", "rarity": "legendary", "attrs": {"strength": 2, "grip": 2, "cardio": 2, "flexibility": 2, "iq": 2},
		"color": Color(0.96, 0.96, 0.94), "lapel": Color(0.95, 0.72, 0.2),
		"source": "Gold at the Campeonato Mundial", "desc": "White and gold. Only world champions wear this one."},
	# ---------------- rashguards (show at the collar)
	"rash_white": {"slot": "rash", "name": "Ranked Rashguard (White)", "rarity": "common", "attrs": {},
		"color": Color(0.95, 0.95, 0.93), "source": "Starter gear", "desc": "Everyone starts somewhere."},
	"rash_blue": {"slot": "rash", "name": "Ranked Rashguard (Blue)", "rarity": "uncommon", "attrs": {"cardio": 1},
		"color": Color(0.15, 0.35, 0.85), "source": "Promotion to blue belt", "desc": "Ranked colors, blue belt edition."},
	"rash_purple": {"slot": "rash", "name": "Ranked Rashguard (Purple)", "rarity": "uncommon", "attrs": {"cardio": 1, "flexibility": 1},
		"color": Color(0.45, 0.2, 0.65), "source": "Promotion to purple belt", "desc": "Ranked colors, purple belt edition."},
	"rash_brown": {"slot": "rash", "name": "Ranked Rashguard (Brown)", "rarity": "rare", "attrs": {"cardio": 1, "strength": 1, "iq": 1},
		"color": Color(0.42, 0.26, 0.13), "source": "Promotion to brown belt", "desc": "Ranked colors, brown belt edition."},
	"rash_black": {"slot": "rash", "name": "Ranked Rashguard (Black)", "rarity": "epic", "attrs": {"cardio": 2, "strength": 1, "iq": 1},
		"color": Color(0.08, 0.08, 0.08), "source": "Promotion to black belt", "desc": "Ranked colors. The last one."},
	"rash_arara": {"slot": "rash", "name": "Arara Rashguard", "rarity": "rare", "attrs": {"flexibility": 1, "cardio": 1},
		"color": Color(0.9, 0.2, 0.15), "source": "Quest: Feathers for the Festival", "desc": "Red, blue and gold, like the birds."},
	"rash_projeto": {"slot": "rash", "name": "Projeto Social Rashguard", "rarity": "epic", "attrs": {"iq": 2, "cardio": 1},
		"color": Color(0.98, 0.8, 0.2), "source": "Quest: Kids' Class", "desc": "Signed by forty kids from the morro."},
	# ---------------- finger tape
	"tape_basic": {"slot": "tape", "name": "Finger Tape", "rarity": "uncommon", "attrs": {"grip": 1},
		"source": "Quest: Shrimping 101", "desc": "Kaique's spare roll. Tape the ring and middle fingers."},
	"tape_climber": {"slot": "tape", "name": "Climber's Tape", "rarity": "rare", "attrs": {"grip": 2},
		"source": "Quest: Iron Grip", "desc": "Nanda swears by it on the cliffs."},
	"tape_pro": {"slot": "tape", "name": "Competition Tape", "rarity": "epic", "attrs": {"grip": 3},
		"source": "Gold medal at any competition", "desc": "Pre-cut strips, perfect tension, podium-tested."},
}

## Which item each source hands out.
const BOSS_LOOT := {"onca": "onca_gi", "jacare": "jacare_gi", "cachoeira": "veu_gi", "leao": "leao_gi"}
const QUEST_LOOT := {"terere_run": "terere_gi", "shrimping": "tape_basic", "sub_hunter": "pantaneiro_gi",
	"festival_feathers": "rash_arara", "crystal_clear": "red_cliff_gi", "iron_grip": "tape_climber",
	"beach_session": "copacabana_gi", "kids_class": "rash_projeto"}
const PROMOTION_LOOT := {1: "rash_blue", 2: "rash_purple", 3: "rash_brown", 4: "rash_black"}

static func power(id: String) -> int:
	var n := 0
	for k in ITEMS[id].attrs:
		n += int(ITEMS[id].attrs[k])
	return n

static func rarity_color(id: String) -> Color:
	return RARITY[ITEMS[id].rarity].color

static func stat_text(id: String) -> String:
	var parts: Array[String] = []
	for k in Rpg.ATTR_ORDER:
		var v := int(ITEMS[id].attrs.get(k, 0))
		if v > 0:
			parts.append("+%d %s" % [v, Rpg.ATTRS[k].name])
	return ", ".join(parts) if not parts.is_empty() else "No bonus"
