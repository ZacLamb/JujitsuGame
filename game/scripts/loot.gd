class_name Loot
extends RefCounted
## Items that live in your bags (junk to sell, consumable buffs, bags, gear drops), the mobs that
## roam each zone's camps, and what they drop. Money is Reais (R$).

const QUALITY := {
	"junk": {"name": "Junk", "color": Color(0.62, 0.62, 0.62)},
	"common": {"name": "Common", "color": Color(0.95, 0.95, 0.95)},
	"uncommon": {"name": "Uncommon", "color": Color(0.2, 0.9, 0.3)},
	"rare": {"name": "Rare", "color": Color(0.25, 0.55, 1.0)},
	"epic": {"name": "Epic", "color": Color(0.7, 0.35, 1.0)},
}

## kind: junk / food (buff) / bag. stack: max per slot. sell: R$ to a vendor. buy: vendor price (0 = not sold).
## Food buffs last `mins` real minutes; their effect keys are read by buff_mods().
const ITEMS := {
	# --- junk (sell it)
	"torn_rash": {"name": "Torn Rashguard", "kind": "junk", "q": "junk", "stack": 10, "sell": 3, "icon": "shirt", "desc": "Ripped at the collar. Someone's armbar went too far."},
	"belt_tip": {"name": "Frayed Belt Tip", "kind": "junk", "q": "junk", "stack": 10, "sell": 2, "icon": "belt", "desc": "Nobody will miss it."},
	"mouthguard": {"name": "Chewed Mouthguard", "kind": "junk", "q": "junk", "stack": 10, "sell": 2, "icon": "drop", "desc": "Gross. Somebody will still buy it."},
	"flip_flop": {"name": "Lost Chinelo", "kind": "junk", "q": "junk", "stack": 10, "sell": 1, "icon": "shoe", "desc": "Left foot only. The right one is in the river."},
	"tape_ball": {"name": "Wad of Used Tape", "kind": "junk", "q": "junk", "stack": 20, "sell": 1, "icon": "ring", "desc": "Finger tape, balled up after a hard session."},
	"bottle": {"name": "Cracked Squeeze Bottle", "kind": "junk", "q": "junk", "stack": 10, "sell": 2, "icon": "bottle", "desc": "Still smells like tereré."},
	"patch": {"name": "Academy Patch", "kind": "junk", "q": "common", "stack": 10, "sell": 6, "icon": "star", "desc": "Torn off someone's gi. Collectors pay for these."},
	"medal_scrap": {"name": "Bent Medal", "kind": "junk", "q": "common", "stack": 10, "sell": 9, "icon": "medal", "desc": "Third place, Copa Interior 2019."},
	# --- food & drink (buffs)
	"acai": {"name": "Açaí na Tigela", "kind": "food", "q": "common", "stack": 10, "sell": 4, "buy": 14, "icon": "bowl", "mins": 15,
		"effect": {"regen": 0.2}, "desc": "Stamina recovers 20% faster in rolls for 15 min."},
	"coco": {"name": "Água de Coco", "kind": "food", "q": "common", "stack": 10, "sell": 3, "buy": 10, "icon": "bottle", "mins": 15,
		"effect": {"stamina_max": 15.0}, "desc": "+15 max stamina for 15 min."},
	"guarana": {"name": "Guaraná Shot", "kind": "food", "q": "uncommon", "stack": 10, "sell": 6, "buy": 22, "icon": "drop", "mins": 10,
		"effect": {"decision": 0.08}, "desc": "Your techniques cast 8% faster for 10 min."},
	"tape": {"name": "Athletic Tape", "kind": "food", "q": "common", "stack": 10, "sell": 3, "buy": 12, "icon": "ring", "mins": 15,
		"effect": {"defense": 0.08}, "desc": "Taped fingers, iron grips: their casts take 8% longer for 15 min."},
	"terere": {"name": "Tereré Gelado", "kind": "food", "q": "uncommon", "stack": 10, "sell": 5, "buy": 18, "icon": "cup", "mins": 15,
		"effect": {"read_resist": 0.85}, "desc": "Ice-cold yerba mate. They read your techniques 15% less for 15 min."},
	"pao_queijo": {"name": "Pão de Queijo", "kind": "food", "q": "common", "stack": 20, "sell": 2, "buy": 8, "icon": "bread", "mins": 20,
		"effect": {"xp": 0.1}, "desc": "+10% XP from rolls for 20 min."},
	"pacu": {"name": "Pacu Assado", "kind": "food", "q": "rare", "stack": 5, "sell": 15, "icon": "fish", "mins": 30,
		"effect": {"stamina_max": 15.0, "regen": 0.15}, "desc": "Pantanal river fish. +15 max stamina and 15% faster recovery for 30 min."},
	# --- American food & drink (Team USA's vendors and drops)
	"pbj": {"name": "PB&J Sandwich", "kind": "food", "q": "common", "stack": 20, "sell": 2, "buy": 8, "icon": "bread", "mins": 20,
		"effect": {"xp": 0.1}, "desc": "+10% XP from rolls for 20 min."},
	"shake": {"name": "Protein Shake", "kind": "food", "q": "common", "stack": 10, "sell": 3, "buy": 10, "icon": "bottle", "mins": 15,
		"effect": {"stamina_max": 15.0}, "desc": "+15 max stamina for 15 min."},
	"energy_drink": {"name": "Energy Drink", "kind": "food", "q": "uncommon", "stack": 10, "sell": 6, "buy": 22, "icon": "drop", "mins": 10,
		"effect": {"decision": 0.08}, "desc": "Your techniques cast 8% faster for 10 min."},
	"sweet_tea": {"name": "Sweet Tea", "kind": "food", "q": "uncommon", "stack": 10, "sell": 5, "buy": 18, "icon": "cup", "mins": 15,
		"effect": {"read_resist": 0.85}, "desc": "Ice-cold and way too sweet. They read your techniques 15% less for 15 min."},
	"smoothie_bowl": {"name": "Smoothie Bowl", "kind": "food", "q": "common", "stack": 10, "sell": 4, "buy": 14, "icon": "bowl", "mins": 15,
		"effect": {"regen": 0.2}, "desc": "Stamina recovers 20% faster in rolls for 15 min."},
	"brisket": {"name": "Smoked Brisket", "kind": "food", "q": "rare", "stack": 5, "sell": 15, "icon": "bread", "mins": 30,
		"effect": {"stamina_max": 15.0, "xp": 0.1}, "desc": "Twelve hours in Earl's smoker. +15 max stamina and +10% XP for 30 min."},
	"gator_bites": {"name": "Fried Gator Bites", "kind": "food", "q": "rare", "stack": 5, "sell": 15, "icon": "fish", "mins": 30,
		"effect": {"stamina_max": 15.0, "regen": 0.15}, "desc": "Tastes like chicken. +15 max stamina and 15% faster recovery for 30 min."},
	"fish_taco": {"name": "Fish Taco", "kind": "food", "q": "uncommon", "stack": 10, "sell": 5, "buy": 20, "icon": "bread", "mins": 15,
		"effect": {"regen": 0.12, "defense": 0.05}, "desc": "Baja-style. 12% faster recovery and their casts take 5% longer for 15 min."},
	# --- bags
	"bag_lona": {"name": "Canvas Mochila", "kind": "bag", "q": "common", "stack": 1, "sell": 8, "buy": 40, "icon": "bag", "slots": 6, "desc": "A 6-slot bag."},
	"bag_treino": {"name": "Training Duffel", "kind": "bag", "q": "uncommon", "stack": 1, "sell": 25, "buy": 120, "icon": "bag", "slots": 8, "desc": "An 8-slot bag. Fits two gis if you fold them right."},
	"bag_kimono": {"name": "Kimono Travel Bag", "kind": "bag", "q": "rare", "stack": 1, "sell": 60, "icon": "bag", "slots": 10, "desc": "A 10-slot bag. Dropped by elite rollers."},
	"bag_copa": {"name": "Copa Champion's Bag", "kind": "bag", "q": "epic", "stack": 1, "sell": 120, "icon": "bag", "slots": 12, "desc": "A 12-slot bag. Only rare named rollers carry these."},
}

const BACKPACK := 16
const BAG_SLOTS := 4

## What a vendor sells, by zone.
const VENDOR := {
	"caceres": ["acai", "coco", "tape", "pao_queijo", "guarana", "terere", "bag_lona", "bag_treino"],
	"pantanal": ["acai", "coco", "tape", "terere", "guarana", "bag_lona", "bag_treino"],
	"chapada": ["acai", "coco", "tape", "guarana", "terere", "bag_treino"],
	"rio": ["acai", "coco", "tape", "guarana", "terere", "pao_queijo", "bag_treino"],
	"socal": ["smoothie_bowl", "shake", "tape", "energy_drink", "fish_taco", "bag_treino", "bag_kimono"],
	"texas": ["pbj", "shake", "tape", "sweet_tea", "energy_drink", "bag_lona", "bag_treino"],
	"everglades": ["pbj", "shake", "tape", "sweet_tea", "energy_drink", "bag_lona", "bag_treino"],
	"sedona": ["smoothie_bowl", "shake", "tape", "energy_drink", "sweet_tea", "bag_treino"],
}

static func item(id: String) -> Dictionary:
	if id.begins_with("gear:"):
		var gid := id.trim_prefix("gear:")
		if not Gear.ITEMS.has(gid):
			return {}
		var g: Dictionary = Gear.ITEMS[gid]
		var q := str(g.get("rarity", "common"))
		return {"name": g.name, "kind": "gear", "q": q if QUALITY.has(q) else "uncommon", "stack": 1,
			"sell": {"common": 5, "uncommon": 18, "rare": 45, "epic": 110}.get(q, 10) + Gear.ilvl(gid), "icon": {"rash": "shirt", "tape": "ring"}.get(str(g.slot), "gi"), "desc": g.get("desc", ""), "gear": gid}
	return ITEMS.get(id, {})

static func color(id: String) -> Color:
	var it := item(id)
	return QUALITY.get(str(it.get("q", "common")), QUALITY.common).color

# ------------------------------------------------------------------ mobs
## Mob camps per zone. Each camp keeps `count` mobs alive inside `radius`, respawning after
## `respawn` seconds. level is relative to the zone's base level; aggro mobs walk up and challenge
## you when you get close. A camp can hold one rare (named) spawn with its own timer.
const CAMPS := {
	"caceres": [
		{"id": "quadra", "name": "Street Rollers", "title": "Quadra da Vila", "pos": Vector3(62, 0, 66), "radius": 9.0, "count": 4,
			"lv": [1.0, 1.6], "aggro": false, "respawn": 45.0, "styles": ["balanced", "guard", "pressure"],
			"names": ["Rato de Quadra", "Moleque da Vila", "Skatista Folgado", "Garoto do Futsal"]},
		{"id": "prainha", "name": "Beach Rollers", "title": "Prainha do Rio", "pos": Vector3(-34, 0, 70), "radius": 10.0, "count": 4,
			"lv": [1.4, 2.2], "aggro": true, "respawn": 50.0, "styles": ["guard", "submission", "balanced"],
			"names": ["Pescador Bravo", "Banhista Marrento", "Surfista de Rio", "Vendedor de Picolé"],
			"rare": {"name": "Zé do Barco", "title": "Rare", "lv": 2.8, "respawn": 300.0, "style": "submission"}},
		{"id": "galpao", "name": "Warehouse Gym Rats", "title": "Galpão", "pos": Vector3(58, 0, -62), "radius": 8.0, "count": 3,
			"lv": [2.4, 3.2], "aggro": true, "elite": true, "respawn": 70.0, "styles": ["pressure", "back", "submission"],
			"names": ["Rato de Academia", "Leão de Chácara", "Estivador", "Segurança Brabo"]},
	],
	"pantanal": [
		{"id": "fazenda_hands", "name": "Ranch Hands", "title": "Curral", "pos": Vector3(40, 0, 30), "radius": 10.0, "count": 4,
			"lv": [4.4, 5.6], "aggro": true, "respawn": 50.0, "styles": ["pressure", "balanced"],
			"names": ["Peão", "Boiadeiro", "Vaqueiro", "Laçador"],
			"rare": {"name": "Tião Sucuri", "title": "Rare", "lv": 6.3, "respawn": 300.0, "style": "back"}},
		{"id": "pesca", "name": "Fishing Camp Rollers", "title": "Acampamento de Pesca", "pos": Vector3(-30, 0, -20), "radius": 9.0, "count": 4,
			"lv": [4.6, 5.6], "aggro": true, "respawn": 50.0, "styles": ["guard", "submission", "balanced"],
			"names": ["Pescador de Pacu", "Piloteiro", "Isqueiro", "Barqueiro"]},
		{"id": "garimpo", "name": "Garimpo Brutes", "title": "Garimpo", "pos": Vector3(-60, 0, -50), "radius": 8.0, "count": 3,
			"lv": [5.6, 6.4], "aggro": true, "elite": true, "respawn": 70.0, "styles": ["pressure", "back"],
			"names": ["Garimpeiro", "Capataz", "Bateador"],
			"rare": {"name": "Zé Pepita", "title": "Rare", "lv": 7.0, "respawn": 360.0, "style": "pressure"}},
	],
	"chapada": [
		{"id": "trail", "name": "Trail Grapplers", "title": "Trilha", "pos": Vector3(-20, 0, 30), "radius": 10.0, "count": 4,
			"lv": [7.5, 8.6], "aggro": true, "respawn": 50.0, "styles": ["guard", "submission", "balanced"],
			"names": ["Trilheiro", "Escalador", "Guia Local", "Mochileiro"]},
		{"id": "poco", "name": "Waterfall Bathers", "title": "Poço da Cachoeira", "pos": Vector3(60, 0, 10), "radius": 9.0, "count": 4,
			"lv": [7.2, 8.0], "aggro": false, "respawn": 45.0, "styles": ["balanced", "guard"],
			"names": ["Banhista", "Turista Perdido", "Fotógrafo", "Hippie da Chapada"]},
		{"id": "mirante", "name": "Plateau Grapplers", "title": "Mirante", "pos": Vector3(40, 0, -30), "radius": 9.0, "count": 4,
			"lv": [7.8, 8.8], "aggro": true, "respawn": 50.0, "styles": ["pressure", "submission", "back"],
			"names": ["Vigia do Mirante", "Escalador Bravo", "Guarda-Parque", "Rapel Boy"]},
		{"id": "caverna", "name": "Cave Dwellers", "title": "Caverna", "pos": Vector3(-60, 0, -40), "radius": 8.0, "count": 3,
			"lv": [8.6, 9.4], "aggro": true, "elite": true, "respawn": 70.0, "styles": ["submission", "back", "guard"],
			"names": ["Morador da Gruta", "Espeleólogo", "Eremita"],
			"rare": {"name": "Velho da Gruta", "title": "Rare", "lv": 10.0, "respawn": 360.0, "style": "submission"}},
	],
	"rio": [
		{"id": "orla", "name": "Beach Grapplers", "title": "Orla", "pos": Vector3(-30, 0, 50), "radius": 12.0, "count": 5,
			"lv": [10.0, 11.2], "aggro": true, "respawn": 45.0, "styles": ["guard", "pressure", "back", "submission"],
			"names": ["Carioca Marrento", "Rato de Praia", "Altinha Boy", "Ambulante"],
			"rare": {"name": "Capitão Areia", "title": "Rare", "lv": 12.2, "respawn": 300.0, "style": "pressure"}},
		{"id": "lapa", "name": "Lapa Night Crowd", "title": "Arcos da Lapa", "pos": Vector3(-70, 0, -20), "radius": 10.0, "count": 5,
			"lv": [10.6, 11.6], "aggro": true, "elite": true, "respawn": 60.0, "styles": ["pressure", "back", "submission", "guard"],
			"names": ["Sambista", "Malandro", "Capoeirista", "Segurança da Lapa"],
			"rare": {"name": "Zé Navalha", "title": "Rare", "lv": 12.8, "respawn": 360.0, "style": "back"}},
	],
	"texas": [
		{"id": "tailgate", "name": "Friday Night Tailgate", "title": "Stadium Lot", "pos": Vector3(62, 0, 66), "radius": 9.0, "count": 4,
			"lv": [1.0, 1.6], "aggro": false, "respawn": 45.0, "styles": ["balanced", "guard", "pressure"],
			"names": ["Linebacker", "Band Kid", "Cheer Dad", "Tailgate Uncle"]},
		{"id": "creekbed", "name": "Creek Bed Rollers", "title": "Creek Bed", "pos": Vector3(-34, 0, 66), "radius": 10.0, "count": 4,
			"lv": [1.4, 2.2], "aggro": true, "respawn": 50.0, "styles": ["guard", "submission", "balanced"],
			"names": ["Tube Floater", "Cliff Jumper", "Fisherman", "Sunburnt Tourist"],
			"rare": {"name": "Big Bubba", "title": "Rare", "lv": 2.8, "respawn": 300.0, "style": "pressure"}},
		{"id": "oilfield", "name": "Oilfield Roughnecks", "title": "Pump Jacks", "pos": Vector3(58, 0, -62), "radius": 8.0, "count": 3,
			"lv": [2.4, 3.2], "aggro": true, "elite": true, "respawn": 70.0, "styles": ["pressure", "back", "submission"],
			"names": ["Roughneck", "Derrick Hand", "Tool Pusher", "Mud Engineer"]},
	],
	"everglades": [
		{"id": "airboat", "name": "Airboat Crew", "title": "Airboat Launch", "pos": Vector3(30, 0, -64), "radius": 10.0, "count": 4,
			"lv": [4.4, 5.6], "aggro": true, "respawn": 50.0, "styles": ["pressure", "balanced"],
			"names": ["Airboat Pilot", "Deckhand", "Tour Barker", "Mechanic"],
			"rare": {"name": "Swamp Ape", "title": "Rare", "lv": 6.3, "respawn": 300.0, "style": "back"}},
		{"id": "hermits", "name": "Hammock Hermits", "title": "Hermit Hammock", "pos": Vector3(-52, 0, -36), "radius": 9.0, "count": 4,
			"lv": [4.6, 5.6], "aggro": true, "respawn": 50.0, "styles": ["guard", "submission", "balanced"],
			"names": ["Hermit", "Frog Gigger", "Moonshiner", "Off-Grid Prepper"]},
		{"id": "poachers", "name": "Gator Poachers", "title": "Poacher Camp", "pos": Vector3(-56, 0, 62), "radius": 8.0, "count": 3,
			"lv": [5.6, 6.4], "aggro": true, "elite": true, "respawn": 70.0, "styles": ["pressure", "back"],
			"names": ["Poacher", "Skinner", "Lookout"],
			"rare": {"name": "Gator Grady", "title": "Rare", "lv": 7.0, "respawn": 360.0, "style": "pressure"}},
	],
	"sedona": [
		{"id": "jeep", "name": "Jeep Tour Crowd", "title": "Jeep Trail", "pos": Vector3(-20, 0, 30), "radius": 10.0, "count": 4,
			"lv": [7.5, 8.6], "aggro": true, "respawn": 50.0, "styles": ["guard", "submission", "balanced"],
			"names": ["Jeep Tourist", "Selfie Hiker", "Trail Runner", "Mountain Biker"]},
		{"id": "vortex", "name": "Vortex Seekers", "title": "Vortex Circle", "pos": Vector3(66, 0, 10), "radius": 9.0, "count": 4,
			"lv": [7.2, 8.0], "aggro": false, "respawn": 45.0, "styles": ["balanced", "guard"],
			"names": ["Energy Healer", "Drum Circle Guy", "Aura Reader", "Retreat Guest"]},
		{"id": "mesa", "name": "Mesa Climbers", "title": "Mesa Wall", "pos": Vector3(44, 0, -40), "radius": 9.0, "count": 4,
			"lv": [7.8, 8.8], "aggro": true, "respawn": 50.0, "styles": ["pressure", "submission", "back"],
			"names": ["Free Soloist", "Belayer", "Boulderer", "Canyoneer"]},
		{"id": "ghosttown", "name": "Ghost Town Miners", "title": "Ghost Town", "pos": Vector3(-64, 0, -54), "radius": 8.0, "count": 3,
			"lv": [8.6, 9.4], "aggro": true, "elite": true, "respawn": 70.0, "styles": ["submission", "back", "guard"],
			"names": ["Old Prospector", "Claim Jumper", "Mule Skinner"],
			"rare": {"name": "Dusty Pete", "title": "Rare", "lv": 10.0, "respawn": 360.0, "style": "submission"}},
	],
	"socal": [
		{"id": "boardwalk", "name": "Boardwalk Crowd", "title": "Boardwalk", "pos": Vector3(-30, 0, 34), "radius": 12.0, "count": 5,
			"lv": [11.4, 12.4], "aggro": true, "respawn": 45.0, "styles": ["guard", "balanced", "back"],
			"names": ["Skater Bro", "Spring Breaker", "Surf Instructor", "Roller Blader", "Muscle Beach Guy"],
			"rare": {"name": "Big Wave Dave", "title": "Rare", "lv": 13.4, "respawn": 300.0, "style": "pressure"}},
		{"id": "gold_gym", "name": "Gold League Members", "title": "Gold League USA", "pos": Vector3(46, 0, -2), "radius": 9.0, "count": 4,
			"lv": [12.0, 13.0], "aggro": true, "elite": true, "respawn": 60.0, "styles": ["pressure", "submission", "balanced"],
			"names": ["Gold Member", "Franchise Coach", "Paid Black Belt", "Brand Ambassador"]},
		{"id": "hills", "name": "Canyon Wrestlers", "title": "Canyon", "pos": Vector3(60, 0, -62), "radius": 10.0, "count": 4,
			"lv": [12.2, 13.2], "aggro": true, "respawn": 50.0, "styles": ["pressure", "back"],
			"names": ["Ex-Wrestler", "Trail Runner", "Rancher", "Hiker"],
			"rare": {"name": "Coyote", "title": "Rare", "lv": 14.0, "respawn": 360.0, "style": "back"}},
	],
}

## A mob's opponent dict (same shape the roll takes for generated opponents).
static func make_mob(camp: Dictionary, rng: RandomNumberGenerator, rare := false) -> Dictionary:
	var lv: float
	var nm: String
	var st: String
	if rare:
		var r: Dictionary = camp.rare
		lv = float(r.lv)
		nm = str(r.name)
		st = str(r.style)
	else:
		lv = rng.randf_range(float(camp.lv[0]), float(camp.lv[1]))
		nm = str(camp.names[rng.randi() % camp.names.size()])
		st = str(camp.styles[rng.randi() % camp.styles.size()])
	var elite: bool = camp.get("elite", false) or rare
	var gis := [Color(0.95, 0.95, 0.95), Color(0.15, 0.3, 0.75), Color(0.1, 0.1, 0.12)]
	var rank := clampi(int((lv - 1.0) / 0.55), 0, 24)
	return {"name": nm, "title": "Rare" if rare else ("Elite" if elite else camp.name), "rank": rank, "level": lv,
		"gi": gis[rng.randi() % gis.size()], "skin": Color(0.96, 0.8, 0.68).lerp(Color(0.36, 0.22, 0.14), rng.randf()),
		"body": "female" if rng.randf() < 0.25 else "male", "style": st, "extra": [], "zone": "",
		"intro": "Oss.", "win": ["Next!", "Too easy.", "Come back when you've trained.", "That's my spot, gringo."][rng.randi() % 4],
		"lose": ["Good roll.", "Ah, you got me.", "Again tomorrow?", "Oss. Respect."][rng.randi() % 4],
		"mob": true, "elite": elite, "rare": rare, "camp": camp.id, "aggro": camp.get("aggro", false),
		"trait": "" if rare else _trait(rng)}

## Mob personalities (WoW-style variety): runners flee for help, callers shout for a campmate,
## turtles shell up until you pass or take the back, hunters live for the submission.
const TRAITS := {"runner": "Runner", "caller": "Caller", "turtle": "Turtle", "hunter": "Sub Hunter"}
static func _trait(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	if r < 0.5:
		return ""
	if r < 0.64:
		return "runner"
	if r < 0.78:
		return "caller"
	if r < 0.89:
		return "turtle"
	return "hunter"

## What a beaten mob drops: {money, items: [id...]}.
static func roll_loot(mob: Dictionary, zone: String, rng: RandomNumberGenerator) -> Dictionary:
	var lv := float(mob.level)
	var elite: bool = mob.get("elite", false)
	var rare: bool = mob.get("rare", false)
	var money := int(rng.randf_range(2.0, 5.0) + lv * rng.randf_range(1.0, 2.0))
	if elite:
		money *= 2
	if rare:
		money *= 4
	var items: Array = []
	var junk := ["torn_rash", "belt_tip", "mouthguard", "flip_flop", "tape_ball", "bottle"]
	if rng.randf() < 0.75:
		items.append(junk[rng.randi() % junk.size()])
	if rng.randf() < 0.18 + (0.2 if elite else 0.0):
		items.append(["patch", "medal_scrap"][rng.randi() % 2])
	if rng.randf() < 0.22 + (0.15 if elite else 0.0):
		var food := ["acai", "coco", "tape", "pao_queijo", "terere", "guarana"]
		if Data.continent_of(zone) == "america":
			food = ["smoothie_bowl", "shake", "tape", "pbj", "sweet_tea", "energy_drink"]
		if zone == "pantanal":
			food.append("pacu")
		if zone == "texas" and rng.randf() < 0.3:
			food.append("brisket")
		if zone == "everglades":
			food.append("gator_bites")
		if zone == "socal":
			food.append("fish_taco")
		items.append(food[rng.randi() % food.size()])
	if rng.randf() < 0.04 + (0.1 if elite else 0.0) or rare:
		items.append("bag_lona" if rng.randf() < 0.6 and not elite else ("bag_kimono" if not rare else "bag_copa"))
	# gear: zone set pieces and odds and ends
	if rng.randf() < 0.05 + (0.12 if elite else 0.0) + (0.5 if rare else 0.0):
		var pool: Array = []
		for gid in Gear.ITEMS:
			var g: Dictionary = Gear.ITEMS[gid]
			if g.has("set") or g.has("class") or gid in Gear.STARTER:
				continue   # set pieces come from masters; starter kit everyone already has
			var rq := str(g.get("rarity", ""))
			# item level near the mob's level (WoW-style): no level-2 tape off a level-25 mob
			var dl := Data.display_level(lv)
			if absi(Gear.ilvl(gid) - dl) > 8:
				continue
			if rq in ["common", "uncommon"] or (rq == "rare" and (elite or rare)):
				pool.append(gid)
		# most drops are rolled pieces (random rarity + stats at the mob's level); some are named items
		if pool.is_empty() or rng.randf() < 0.7:
			items.append("gear:" + Game.make_rolled(Gear.roll(Data.display_level(lv), rng, elite, rare)))
		else:
			items.append("gear:" + str(pool[rng.randi() % pool.size()]))
	# elite bosses at the top of the world sometimes drop a piece of your class tier set
	if elite and Data.display_level(lv) >= 25 and rng.randf() < 0.07:
		var tp := Game.missing_tier_piece()
		if tp != "":
			items.append("gear:" + tp)
	return {"money": money, "items": items}
