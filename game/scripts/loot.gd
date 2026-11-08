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
}

static func item(id: String) -> Dictionary:
	if id.begins_with("gear:"):
		var gid := id.trim_prefix("gear:")
		if not Gear.ITEMS.has(gid):
			return {}
		var g: Dictionary = Gear.ITEMS[gid]
		var q := str(g.get("rarity", "common"))
		return {"name": g.name, "kind": "gear", "q": q if QUALITY.has(q) else "uncommon", "stack": 1,
			"sell": {"common": 5, "uncommon": 18, "rare": 45, "epic": 110}.get(q, 10), "icon": "gi", "desc": g.get("desc", ""), "gear": gid}
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
	],
	"chapada": [
		{"id": "trail", "name": "Trail Grapplers", "title": "Trilha", "pos": Vector3(-20, 0, 30), "radius": 10.0, "count": 4,
			"lv": [7.5, 8.6], "aggro": true, "respawn": 50.0, "styles": ["guard", "submission", "balanced"],
			"names": ["Trilheiro", "Escalador", "Guia Local", "Mochileiro"]},
	],
	"rio": [
		{"id": "orla", "name": "Beach Grapplers", "title": "Orla", "pos": Vector3(-30, 0, 50), "radius": 12.0, "count": 5,
			"lv": [10.0, 11.2], "aggro": true, "respawn": 45.0, "styles": ["guard", "pressure", "back", "submission"],
			"names": ["Carioca Marrento", "Rato de Praia", "Altinha Boy", "Ambulante"],
			"rare": {"name": "Capitão Areia", "title": "Rare", "lv": 12.2, "respawn": 300.0, "style": "pressure"}},
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
		"mob": true, "elite": elite, "rare": rare, "camp": camp.id, "aggro": camp.get("aggro", false)}

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
		if zone == "pantanal":
			food.append("pacu")
		items.append(food[rng.randi() % food.size()])
	if rng.randf() < 0.04 + (0.1 if elite else 0.0) or rare:
		items.append("bag_lona" if rng.randf() < 0.6 and not elite else ("bag_kimono" if not rare else "bag_copa"))
	# gear: zone set pieces and odds and ends
	if rng.randf() < 0.05 + (0.12 if elite else 0.0) + (0.5 if rare else 0.0):
		var pool: Array = []
		for gid in Gear.ITEMS:
			var g: Dictionary = Gear.ITEMS[gid]
			if g.has("set") or gid in Gear.STARTER:
				continue   # set pieces come from masters; starter kit everyone already has
			var rq := str(g.get("rarity", ""))
			if rq in ["common", "uncommon"] or (rq == "rare" and (elite or rare)):
				pool.append(gid)
		if not pool.is_empty():
			items.append("gear:" + str(pool[rng.randi() % pool.size()]))
	return {"money": money, "items": items}
