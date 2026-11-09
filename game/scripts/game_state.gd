extends Node
## Persistent player progress: XP, rank, achievements, quests, world flags. Saves to user://.

signal achievement_unlocked(id: String)
signal toast(text: String, color: Color)
signal progress_changed

const LEGACY_SAVE := "user://tatame_save.json"   # single-character saves from before character slots
const INDEX_PATH := "user://tatame_chars.json"    # {active: id, chars: [{id, name, style, rank, level, zone, gi, created}]}
const MAX_CHARS := 8
var SAVE_PATH := "user://tatame_char_1.json"      # the active character's file
var char_id := ""
var boot_into := false     # set before a scene reload: skip the title and go straight in
const SAVE_VERSION := 1

var xp := 0
var rank := 0  # 0..4 white belt stripes, 5 = blue belt
var wins := {}  # opponent id -> win count
var losses := {}
var unlocked := {}  # achievement id -> true
var counters := {}  # achievement id -> int
var landmarks := {}
var cups := {}
var flags := {}  # misc quest flags
var inventory := {}  # item id -> true
var equipped := {}   # slot -> item id
var kit := "gi"       # "gi" / "nogi": which outfit is worn (and whose slots count)
var team := {}        # 5v5 lineup: {order: [5 fighter ids incl "you"], coach: id}
var territories := {} # territory id -> {owner: "you", attack_at: unix secs}  (absent = held by its rival)
var quests := {}  # id -> {"state": "active"/"done", "count": {objective_index: n}}
var medals := {}  # "<comp>_<belt>" -> "gold" / "silver" / "bronze" (best result)
var player_name := "Gringo"
var style := ""            # Rpg.STYLES key; "" until chosen
var spec := ""             # Specs id; "" until chosen at level 10
var gi_index := 0
var origin := "gringo"     # Origins id (Tatame's "race")
var body := "male"         # "male" / "female"
var skin_t := 0.35         # skin tone 0..1 (UiKit.skin_tone)
var bar_layout: Array = [] # action bar slots 1-0: ability ids ("" = empty)
var attr_alloc := {}       # attribute -> points spent
var talents := {}          # talent id -> rank
var stripe_xp := 0
var zone := "caceres"
var train := {}            # attribute -> drill successes
var drills_ready := true   # drills refresh after every roll
var daily := {}            # {"last_win": date, "last_try": date, "streak": n, "best": n}
var money := 0           # Reais (R$)
var bag: Array = []       # slot -> {"id": item id, "n": count} or null; size = bag_capacity()
var bags: Array = ["", "", "", ""]   # equipped extra bags (Loot item ids)
var buffs := {}           # item id -> unix time it wears off
var test_mode := false  # set by tests to avoid writing saves

func _ready() -> void:
	_migrate_legacy()
	var idx := _index()
	if str(idx.get("active", "")) != "" and _find_char(idx, str(idx.active)) >= 0:
		_use_slot(str(idx.active))
		load_game()

# ------------------------------------------------------------ characters (slots)
## Every character is its own save: own class, belt, gear, quests, territories. Everyone starts
## at white belt, level 1. Settings (sound, controls, graphics) are shared across characters.
func _index() -> Dictionary:
	if not FileAccess.file_exists(INDEX_PATH):
		return {"active": "", "chars": []}
	var f := FileAccess.open(INDEX_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	return d if typeof(d) == TYPE_DICTIONARY else {"active": "", "chars": []}

func _write_index(d: Dictionary) -> void:
	if test_mode:
		return
	var f := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

static func _find_char(d: Dictionary, id: String) -> int:
	var arr: Array = d.get("chars", [])
	for i in arr.size():
		if str(arr[i].get("id", "")) == id:
			return i
	return -1

func _use_slot(id: String) -> void:
	char_id = id
	SAVE_PATH = "user://tatame_char_%s.json" % id

func _migrate_legacy() -> void:
	if FileAccess.file_exists(INDEX_PATH) or not FileAccess.file_exists(LEGACY_SAVE):
		return
	var src := FileAccess.open(LEGACY_SAVE, FileAccess.READ)
	if not src:
		return
	var txt := src.get_as_text()
	src = null
	var dst := FileAccess.open("user://tatame_char_1.json", FileAccess.WRITE)
	if not dst:
		return
	dst.store_string(txt)
	dst = null
	_write_index({"active": "1", "chars": [{"id": "1"}]})
	_use_slot("1")
	load_game()
	_sync_index()

## Character list for the select screen (newest summary of each).
func characters() -> Array:
	var out: Array = []
	for c in _index().get("chars", []):
		if str(c.get("style", "")) != "":
			out.append(c)
	return out

func can_create() -> bool:
	return characters().size() < MAX_CHARS

## Start a brand-new character: white belt, level 1, nothing carried over.
func new_character() -> void:
	var d := _index()
	var n := 1
	for c in d.chars:
		n = maxi(n, int(str(c.get("id", "0"))) + 1)
	var arr: Array = d.chars.filter(func(c): return str(c.get("style", "")) != "")   # drop unfinished creations
	var id := str(n)
	arr.append({"id": id, "created": int(Time.get_unix_time_from_system())})
	d.chars = arr
	d.active = id
	_write_index(d)
	_use_slot(id)
	reset()

func select_character(id: String) -> void:
	var d := _index()
	if _find_char(d, id) < 0:
		return
	d.active = id
	_write_index(d)
	_use_slot(id)
	reset_state()
	load_game()

func delete_character(id: String) -> void:
	var d := _index()
	var i := _find_char(d, id)
	if i < 0:
		return
	(d.chars as Array).remove_at(i)
	if not test_mode:
		DirAccess.remove_absolute("user://tatame_char_%s.json" % id)
	if str(d.active) == id:
		d.active = ""
		char_id = ""
	_write_index(d)

## Keep the select screen's summary of the active character current (called on every save).
func _sync_index() -> void:
	if test_mode or char_id == "":
		return
	var d := _index()
	var i := _find_char(d, char_id)
	var row := {"id": char_id, "name": player_name, "style": style, "rank": rank, "level": player_level(), "zone": zone, "gi": gi_index,
		"created": int(d.chars[i].get("created", 0)) if i >= 0 else int(Time.get_unix_time_from_system()), "played": int(Time.get_unix_time_from_system())}
	if i >= 0:
		d.chars[i] = row
	else:
		(d.chars as Array).append(row)
	d.active = char_id
	_write_index(d)

# ------------------------------------------------------------ persistence
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func reset() -> void:
	reset_state()
	save_game()
	progress_changed.emit()

func reset_state() -> void:
	player_name = "Gringo"
	xp = 0
	rank = 0
	wins = {}
	losses = {}
	unlocked = {}
	counters = {}
	landmarks = {}
	cups = {}
	flags = {}
	style = ""
	gi_index = 0
	origin = "gringo"
	body = "male"
	skin_t = 0.35
	bar_layout = []
	attr_alloc = {}
	talents = {}
	stripe_xp = 0
	zone = "caceres"
	train = {}
	drills_ready = true
	daily = {}
	medals = {}
	quests = {}
	inventory = {}
	rolled = {}
	for id in Gear.STARTER:
		inventory[id] = true
	equipped = {"jacket": "standard_gi", "pants": "standard_gi_pants", "rash": "rash_white", "spats": "spats_black"}
	kit = "gi"
	team = {}
	territories = {}
	spec = ""
	money = 0
	bags = ["", "", "", ""]
	bag = []
	buffs = {}
	_fit_bag()
	money = 25
	bag[0] = {"id": "acai", "n": 2}
	bag[1] = {"id": "pao_queijo", "n": 3}

func save_game() -> void:
	if test_mode:
		return
	var data := {
		"v": SAVE_VERSION, "xp": xp, "rank": rank, "wins": wins, "losses": losses,
		"unlocked": unlocked, "counters": counters, "landmarks": landmarks,
		"cups": cups, "flags": flags, "name": player_name,
		"style": style, "gi": gi_index, "attrs": attr_alloc, "talents": talents,
		"stripe_xp": stripe_xp, "zone": zone, "train": train, "drills_ready": drills_ready, "daily": daily, "medals": medals, "quests": quests, "inventory": inventory, "equipped": equipped, "kit": kit, "team": team, "territories": territories,
		"money": money, "bag": bag, "bags": bags, "buffs": buffs, "spec": spec,
		"origin": origin, "body": body, "skin_t": skin_t, "bar_layout": bar_layout, "rolled": rolled,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f = null
	_sync_index()

func load_game() -> void:
	if not has_save():
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	xp = int(parsed.get("xp", 0))
	rank = int(parsed.get("rank", 0))
	wins = parsed.get("wins", {})
	losses = parsed.get("losses", {})
	unlocked = parsed.get("unlocked", {})
	counters = parsed.get("counters", {})
	landmarks = parsed.get("landmarks", {})
	cups = parsed.get("cups", {})
	flags = parsed.get("flags", {})
	player_name = str(parsed.get("name", "Gringo"))
	style = str(parsed.get("style", ""))
	gi_index = int(parsed.get("gi", 0))
	origin = str(parsed.get("origin", "gringo"))
	body = str(parsed.get("body", "male"))
	skin_t = float(parsed.get("skin_t", 0.35))
	bar_layout = parsed.get("bar_layout", [])
	attr_alloc = parsed.get("attrs", {})
	talents = parsed.get("talents", {})
	stripe_xp = int(parsed.get("stripe_xp", xp % Data.XP_PER_STRIPE if rank < 4 else 0))
	zone = str(parsed.get("zone", "caceres"))
	train = parsed.get("train", {})
	drills_ready = bool(parsed.get("drills_ready", true))
	daily = parsed.get("daily", {})
	medals = parsed.get("medals", {})
	quests = parsed.get("quests", {})
	rolled = parsed.get("rolled", {})
	for rid in rolled:
		Gear.register_rolled(str(rid), rolled[rid])
	inventory = parsed.get("inventory", {})
	equipped = parsed.get("equipped", {})
	kit = str(parsed.get("kit", "gi"))
	team = parsed.get("team", {})
	territories = parsed.get("territories", {})
	_backfill_gear()
	# saves from before the belt-level system may have spent more points than they now have
	if attr_points() < 0:
		attr_alloc = {}
	# the talent trees were rebuilt: refund anything that isn't a node of the current trees
	for k in talents.keys():
		if TalentTrees.node(str(k), str(parsed.get("spec", ""))).is_empty():
			talents.erase(k)
	if points_left("class") < 0 or points_left("spec") < 0:
		talents = {}

# ------------------------------------------------------------ rank / xp
	money = int(parsed.get("money", 0))
	spec = str(parsed.get("spec", ""))
	bags = parsed.get("bags", ["", "", "", ""])
	while bags.size() < Loot.BAG_SLOTS:
		bags.append("")
	bag = parsed.get("bag", [])
	for k in bag.size():
		if bag[k] != null:
			bag[k] = {"id": str(bag[k].get("id", "")), "n": int(bag[k].get("n", 1))}
	buffs = parsed.get("buffs", {})
	_fit_bag()

func level() -> float:
	return Data.rank_level(rank)

func belt_index() -> int:
	return Data.belt_of(rank)

## Stripe XP fills toward the next stripe; each belt caps at 4 stripes until its boss promotes you.
func xp_into_stripe() -> int:
	return stripe_xp

func at_stripe_cap() -> bool:
	return rank % 5 == 4

func add_xp(amount: int) -> void:
	amount = int(round(amount * xp_mult()))
	var before := player_level()
	xp += amount
	stripe_xp += amount
	while stripe_xp >= stripe_cost(rank) and not at_stripe_cap() and rank < 24:
		stripe_xp -= stripe_cost(rank)
		rank += 1
		toast.emit("New stripe! %s" % Data.rank_name(rank), Data.BELTS[belt_index()].color)
		unlock("first_stripe")
		_announce_new_moves(rank)
	if at_stripe_cap():
		stripe_xp = mini(stripe_xp, stripe_cost(rank) - 1)
	_announce_level(before)
	save_game()
	progress_changed.emit()

func _announce_level(before: int) -> void:
	var after := player_level()
	if after <= before:
		return
	if not test_mode:
		Sfx.play("levelup")
	var tal := after / Rpg.LEVELS_PER_TALENT_POINT - before / Rpg.LEVELS_PER_TALENT_POINT
	var txt := "LEVEL %d!  +%d attribute point%s" % [after, after - before, "" if after - before == 1 else "s"]
	if tal > 0:
		txt += ", +%d talent point%s" % [tal, "" if tal == 1 else "s"]
	toast.emit(txt, Color(0.75, 0.55, 1.0))
	if before < Specs.UNLOCK_LEVEL and after >= Specs.UNLOCK_LEVEL and spec == "":
		toast.emit("Specializations unlocked! Open the Journal (J) > Specs to choose your path.", Color(0.8, 0.6, 1.0))

## Promote to the next belt (called when a zone boss is beaten).
func promote_belt(to_belt: int) -> void:
	if belt_index() >= to_belt:
		return
	var lv_before := player_level()
	rank = to_belt * 5
	stripe_xp = 0
	var b: Dictionary = Data.BELTS[to_belt]
	toast.emit("PROMOTED: %s Belt!" % b.name, b.color)
	unlock({1: "blue_belt", 2: "purple_belt", 3: "brown_belt", 4: "black_belt"}.get(to_belt, ""))
	_announce_new_moves(rank)
	_announce_level(lv_before)
	give_item(Gear.PROMOTION_LOOT.get(to_belt, ""))
	save_game()
	progress_changed.emit()

func promote_to_blue() -> void:
	promote_belt(1)

func _announce_new_moves(r: int) -> void:
	for id in Data.MOVES:
		if int(Data.MOVES[id].rank) == r:
			toast.emit("Technique unlocked: %s" % Data.MOVES[id].name, Color(1, 0.85, 0.4))

func knows(move_id: String) -> bool:
	if Data.MOVES[move_id].has("spec"):
		return str(Data.MOVES[move_id].spec) == spec
	if int(Data.MOVES[move_id].rank) <= rank:
		return style == "" or Data.class_ok(move_id, style)
	if style != "" and move_id in Rpg.STYLES[style].signature:
		return true
	if move_id in TalentTrees.taught_moves(talents, spec):
		return true
	return false

# ------------------------------------------------------------ RPG build
## Keeps the action bar in step with what you can use: newly unlocked abilities drop into their
## usual slot (or the first free one). Returns the ids learned since last time (tutorial cards).
func ensure_bar(pool: Array) -> Array:
	while bar_layout.size() < 10:
		bar_layout.append("")
	var first := not flags.has("abilities_known")
	var known: Array = flags.get("abilities_known", [])
	var fresh: Array = []
	var have := pool.map(func(a): return str(a.id))
	for i in bar_layout.size():
		if str(bar_layout[i]) != "" and not str(bar_layout[i]) in have:
			bar_layout[i] = ""
	for id in have:
		if not id in known:
			known.append(id)
			fresh.append(id)
		if id in Abilities.UTILITY or id in bar_layout:
			continue
		if not id in fresh and not first:
			continue   # the player took it off the bar on purpose
		var want := Abilities.ORDER.find(id)
		if want >= 0 and str(bar_layout[want]) == "":
			bar_layout[want] = id
		else:
			var free := bar_layout.find("")
			if free >= 0:
				bar_layout[free] = id
	flags["abilities_known"] = known
	if first and player_level() > 3:
		fresh = []   # an existing character: no tutorial flood
	return fresh

## Put an ability in a bar slot (moving it if it's already elsewhere; "" clears the slot).
func bar_set(slot: int, id: String) -> void:
	while bar_layout.size() < 10:
		bar_layout.append("")
	if slot < 0 or slot >= 10:
		return
	var old := bar_layout.find(id) if id != "" else -1
	if old >= 0:
		bar_layout[old] = bar_layout[slot]
	bar_layout[slot] = id
	save_game()

## Character creation extras: origin, body and skin tone.
func set_identity(origin_id: String, body_type: String, skin: float) -> void:
	origin = origin_id if Origins.ORIGINS.has(origin_id) else "gringo"
	body = "female" if body_type == "female" else "male"
	skin_t = clampf(skin, 0.0, 1.0)

func skin_color() -> Color:
	return UiKit.skin_tone(skin_t)

func choose_style(id: String, name_: String, gi: int) -> void:
	style = id
	player_name = name_.strip_edges().left(16) if name_.strip_edges() != "" else "Gringo"
	gi_index = clampi(gi, 0, Rpg.GI_COLORS.size() - 1)
	unlock("chose_style")
	save_game()
	progress_changed.emit()

func gi_color() -> Color:
	var jid := str(equipped.get("jacket", ""))
	if jid == "standard_gi" or jid == "":
		return Rpg.GI_COLORS[gi_index]
	return Gear.look(jid).get("color", Rpg.GI_COLORS[gi_index])

## Lapel accent of the equipped jacket (alpha 0 = derive from the gi color).
func lapel_color() -> Color:
	return Gear.look(str(equipped.get("jacket", ""))).get("trim", Color(0, 0, 0, 0))

func rash_color() -> Color:
	return Gear.look(str(equipped.get("rash", ""))).get("color", Color(0, 0, 0, 0))

## What the player's character wears, for BodyRig (slot -> look dict).
func look() -> Dictionary:
	var lk := {"kit": kit}
	for slot in Gear.KITS[kit]:
		var id := str(equipped.get(slot, ""))
		if id == "" or not Gear.ITEMS.has(id):
			continue
		var l: Dictionary = Gear.look(id).duplicate()
		if id == "standard_gi" or id == "standard_gi_pants":
			l["color"] = Rpg.GI_COLORS[gi_index]
		lk[slot] = l
		if slot == "head":
			lk["head_piece"] = Gear.ITEMS[id].get("piece", "Headband")
	return lk

## Applies the equipped gear look to a rig before rig.setup().
func dress(rig: BodyRig) -> void:
	rig.lapel_override = lapel_color()
	rig.rash_color = rash_color()
	rig.look = look()

## Graphics quality: 0 low (phones), 1 high, 2 ultra (desktop default; steps down if slow).
const GFX_NAMES := ["low", "high", "ultra"]

func graphics_level() -> int:
	if Sfx.pref("gfx") != null:
		return clampi(int(Sfx.pref("gfx")), 0, 2)
	if flags.has("gfx"):
		return clampi(int(flags.gfx), 0, 2)
	if flags.has("gfx_low"):  # older saves
		return 0 if bool(flags.gfx_low) else 1
	if OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile"):
		return 0
	return 2

func set_graphics_level(lvl: int, manual := true) -> void:
	Sfx.set_pref("gfx", clampi(lvl, 0, 2))
	if manual:
		Sfx.set_pref("gfx_manual", true)

func graphics_low() -> bool:
	return graphics_level() == 0

func look_key() -> String:
	return "%s|%s|%s|%s|%s" % [gi_color().to_html(), kit, str(equipped), body, str(skin_t)]

# ------------------------------------------------------------ gear
## Item ids that count right now (the active kit's slots).
func worn() -> Array:
	var out: Array = []
	for slot in Gear.KITS[kit]:
		var id := str(equipped.get(slot, ""))
		if id != "" and Gear.ITEMS.has(id):
			out.append(id)
	return out

## Equipped pieces per set (active kit).
func set_counts() -> Dictionary:
	var c := {}
	for id in worn():
		var st := str(Gear.ITEMS[id].get("set", ""))
		if st != "":
			c[st] = int(c.get(st, 0)) + 1
	return c

## Active set bonuses: [{set, n, attrs?, effect?, text?}]
func set_bonuses() -> Array:
	var out: Array = []
	var c := set_counts()
	for st in c:
		var b: Dictionary = Gear.SETS[st].bonus
		for n in [2, 4]:
			if b.has(n) and int(c[st]) >= n:
				var e: Dictionary = (b[n] as Dictionary).duplicate()
				e["set"] = st
				e["n"] = n
				out.append(e)
	return out

## Rolled gear (random drops): id -> saveable data, registered into Gear.ITEMS.
var rolled := {}

func make_rolled(d: Dictionary) -> String:
	var n := int(flags.get("rolled_n", 0)) + 1
	flags["rolled_n"] = n
	var id := "rg_%d" % n
	rolled[id] = d
	Gear.register_rolled(id, d)
	return id

func gear_bonus(k: String) -> int:
	var n := 0
	for id in worn():
		n += int(Gear.ITEMS[id].get("attrs", {}).get(k, 0))
	for b in set_bonuses():
		n += int(b.get("attrs", {}).get(k, 0))
	return n

func has_item(id: String) -> bool:
	return inventory.has(id)

func give_item(id: String, quiet := false) -> bool:
	if id == "" or not Gear.ITEMS.has(id) or inventory.has(id):
		return false
	inventory[id] = true
	var it: Dictionary = Gear.ITEMS[id]
	if Gear.power(id) > 0:
		unlock("first_loot")
	if it.rarity == "legendary":
		unlock("legendary")
	if not quiet:
		toast.emit("LOOT: %s  (%s)" % [it.name, Gear.RARITY[it.rarity].name], Gear.rarity_color(id))
		Sfx.play("collect")
	var cur := str(equipped.get(it.slot, ""))
	if cur == "" or Gear.score(id) > Gear.score(cur):
		equipped[it.slot] = id
		if not quiet:
			toast.emit("Equipped %s" % it.name, Gear.rarity_color(id))
	# a gi jacket from a quest or medal comes with its pants
	if it.slot == "jacket" and Gear.ITEMS.has(id + "_pants") and not it.has("set"):
		give_item(id + "_pants", true)
	save_game()
	progress_changed.emit()
	return true

## A boss win drops one piece of their set you don't own yet (jacket first, then the rest).
func boss_drop(set_id: String) -> String:
	var pieces: Array = Gear.SETS[set_id].pieces
	var missing := pieces.filter(func(p): return not inventory.has(p))
	if missing.is_empty():
		return ""
	var pick: String = missing[0] if not inventory.has(pieces[0]) else missing[randi() % missing.size()]
	give_item(pick)
	return pick

func equip(id: String) -> bool:
	if not inventory.has(id):
		return false
	equipped[Gear.ITEMS[id].slot] = id
	save_game()
	progress_changed.emit()
	return true

# ------------------------------------------------------------ 5v5 teams
## The saved lineup, repaired against who is actually available (falls back to the default).
func team_lineup() -> Dictionary:
	var ok := {}
	for f in Team.roster():
		ok[f.id] = true
	var cok := {}
	for c in Team.coaches():
		cok[c.id] = true
	var order: Array = []
	for id in team.get("order", []):
		if ok.has(id) and not id in order:
			order.append(id)
	var d := Team.default_lineup()
	if not "you" in order:
		order.push_front("you")
	for id in d.order:
		if order.size() >= 5:
			break
		if not id in order:
			order.append(id)
	for f in Team.roster():
		if order.size() >= 5:
			break
		if not f.id in order:
			order.append(f.id)
	var coach := str(team.get("coach", ""))
	if not cok.has(coach) or coach in order:
		coach = d.coach if not d.coach in order else ""
	return {"order": order.slice(0, 5), "coach": coach}

func set_team_lineup(order: Array, coach: String) -> void:
	team = {"order": order, "coach": coach}
	save_game()

## Records a finished 5v5. Returns XP gained.
func record_team(won: bool, lost_fighters: int) -> int:
	counters["team_matches"] = int(counters.get("team_matches", 0)) + 1
	var gained := 0
	if won:
		gained = 90 + 10 * maxi(0, 4 - lost_fighters)
		unlock("team_win")
		if lost_fighters == 0:
			unlock("team_clean")
		bump("team_wins")
		var miss: Array = Gear.SETS.familia.pieces.filter(func(p): return not inventory.has(p))
		if not miss.is_empty():
			give_item(miss[randi() % miss.size()])
	add_xp(gained)
	save_game()
	progress_changed.emit()
	return gained

# ------------------------------------------------------------ Circuito (roguelite runs)
## Records a finished run. wins: matches won (0-5). Returns XP gained.
func record_circuit(wins: int, champion: bool) -> int:
	counters["circuit_runs"] = int(counters.get("circuit_runs", 0)) + 1
	var gained := 25 * wins + (120 if champion else 0)
	flags["circuit_best"] = maxi(int(flags.get("circuit_best", 0)), wins)
	if wins >= Circuit.ROUNDS - 1:
		unlock("circuit_final")
	if champion:
		unlock("circuit_champ")
		bump("circuit_titles")
		give_item("rash_circuito")
	add_xp(gained)
	save_game()
	progress_changed.emit()
	return gained

# ------------------------------------------------------------ academy wars
var clock_override := -1   # tests: fake "now" (unix seconds)

func now() -> int:
	return clock_override if clock_override >= 0 else int(Time.get_unix_time_from_system())

func holds(tid: String) -> bool:
	return territories.has(tid) and str(territories[tid].get("owner", "")) == "you"

## "rival" (theirs), "held" (yours, quiet), "attacked" (yours, counterattack running).
func territory_state(tid: String) -> String:
	if not holds(tid):
		return "rival"
	return "attacked" if now() >= int(territories[tid].get("attack_at", 0)) else "held"

## Seconds left to defend a counterattack before the flag falls.
func defend_left(tid: String) -> int:
	return int(territories[tid].get("attack_at", 0)) + 86400 - now()

func held_in(z: String) -> int:
	var n := 0
	for tid in Data.territories_in(z):
		if holds(tid):
			n += 1
	return n

func capture(tid: String) -> void:
	territories[tid] = {"owner": "you", "attack_at": now() + randi_range(8, 16) * 3600}
	unlock("flag_taken")
	var z: String = Data.TERRITORIES[tid].zone
	if held_in(z) == Data.territories_in(z).size():
		unlock("zone_owner")
	toast.emit("%s is yours! +10%% XP in %s while you hold it." % [Data.TERRITORIES[tid].name, Data.ZONES[z].name], Data.YOUR_ACADEMY_COLOR.lightened(0.3))
	save_game()
	progress_changed.emit()

func defended(tid: String) -> void:
	territories[tid].attack_at = now() + randi_range(8, 16) * 3600
	unlock("flag_defended")
	toast.emit("%s holds! The rivals back off for now." % Data.TERRITORIES[tid].name, Data.YOUR_ACADEMY_COLOR.lightened(0.3))
	save_game()
	progress_changed.emit()

func lose_territory(tid: String) -> void:
	territories.erase(tid)
	toast.emit("%s fell back to %s." % [Data.TERRITORIES[tid].name, Data.TERRITORIES[tid].academy], UiKit.RED)
	save_game()
	progress_changed.emit()

## Flags whose 24-hour defence window ran out fall back to their rivals (call on load / zone entry).
func expire_territories() -> Array:
	var lost: Array = []
	for tid in territories.keys():
		if holds(tid) and territory_state(tid) == "attacked" and defend_left(tid) <= 0:
			territories.erase(tid)
			lost.append(tid)
	if not lost.is_empty():
		save_game()
	return lost

func set_kit(k: String) -> void:
	if not Gear.KITS.has(k) or k == kit:
		return
	kit = k
	save_game()
	progress_changed.emit()

## Gives gear for progress made before gear existed (and the starter kit); migrates old saves.
func _backfill_gear() -> void:
	# v1 saves had one "gi" slot: it becomes the jacket, with matching pants
	if equipped.has("gi"):
		var old := str(equipped.gi)
		equipped.erase("gi")
		if Gear.ITEMS.has(old):
			equipped["jacket"] = old
			if Gear.ITEMS.has(old + "_pants"):
				inventory[old + "_pants"] = true
				equipped["pants"] = old + "_pants"
	for id in inventory.keys():
		if Gear.ITEMS.has(id) and Gear.ITEMS[id].slot == "jacket" and Gear.ITEMS.has(id + "_pants"):
			inventory[id + "_pants"] = true
	for id in Gear.STARTER:
		inventory[id] = true
	for slot_def in [["jacket", "standard_gi"], ["pants", "standard_gi_pants"], ["rash", "rash_white"], ["spats", "spats_black"]]:
		if not equipped.has(slot_def[0]):
			equipped[slot_def[0]] = slot_def[1]
	if not Gear.KITS.has(kit):
		kit = "gi"
	for boss in Gear.BOSS_SET:
		if beaten(boss) and not inventory.has(Gear.SETS[Gear.BOSS_SET[boss]].pieces[0]):
			give_item(Gear.SETS[Gear.BOSS_SET[boss]].pieces[0], true)
	for q in Gear.QUEST_LOOT:
		if quest_state(q) == "done":
			give_item(Gear.QUEST_LOOT[q], true)
	for b in Gear.PROMOTION_LOOT:
		if belt_index() >= b:
			give_item(Gear.PROMOTION_LOOT[b], true)

## WoW-style level tied to the belt: white 1-10, blue 11-20, purple 21-30, brown 31-40, black 41-50.
## Every 2 levels is a stripe; at 4 stripes the level is capped until the zone boss promotes you.
## Each level takes longer than the last (see xp_to_next): ~6 same-level fights at level 1, ~14 at
## 10, ~23 at 30, ~31 at 49 (quests, jobs, dailies and raids speed it up).
const MAX_LEVEL := 50
const XP_PER_LEVEL := 250   # kept for older references: the level-1 cost

## XP from level L to L+1.
static func xp_to_next(lvl: int) -> int:
	var k := lvl - 1
	return 250 + 100 * k + 4 * k * k

## XP for a whole stripe (two levels) starting at rank r.
static func stripe_cost(r: int) -> int:
	return xp_to_next(2 * r + 1) + xp_to_next(2 * r + 2)

func player_level() -> int:
	var l := 1 + 2 * rank
	if stripe_xp >= xp_to_next(l):
		l += 1
	return mini(MAX_LEVEL, l)

func level_capped() -> bool:
	return player_level() >= MAX_LEVEL or (at_stripe_cap() and player_level() >= (belt_index() + 1) * 10 and xp_into_level() >= xp_level_need() - 1)

## XP into the current level, and what the level needs.
func xp_into_level() -> int:
	var l := 1 + 2 * rank
	return stripe_xp if player_level() == l else stripe_xp - xp_to_next(l)

func xp_level_need() -> int:
	return xp_to_next(player_level())

## 0..1 progress through the current level.
func level_progress() -> float:
	if player_level() >= MAX_LEVEL:
		return 1.0
	return clampf(float(xp_into_level()) / float(xp_level_need()), 0.0, 1.0)

## Jump to a level (tests and QA links).
func set_level(lvl: int) -> void:
	lvl = clampi(lvl, 1, MAX_LEVEL)
	rank = mini(24, (lvl - 1) / 2)
	stripe_xp = ((lvl - 1) % 2) * xp_to_next(1 + 2 * rank)

const DRILLS_PER_POINT := 3
const TRAIN_CAP := 5

func train_bonus(k: String) -> int:
	return mini(int(train.get(k, 0)) / DRILLS_PER_POINT, TRAIN_CAP)

## Record a successful drill. Returns true if it earned a permanent attribute point.
func complete_drill(k: String) -> bool:
	var before := train_bonus(k)
	train[k] = int(train.get(k, 0)) + 1
	bump("drills")
	quest_event("drill")
	add_xp(5)
	var gained := train_bonus(k) > before
	if gained:
		toast.emit("Training paid off: +1 %s" % Rpg.ATTRS[k].name, Color(0.6, 0.9, 1.0))
		if attr(k) >= 12:
			unlock("peak")
	save_game()
	progress_changed.emit()
	return gained

func attr(k: String) -> int:
	var v := Rpg.ATTR_BASE + int(attr_alloc.get(k, 0)) + train_bonus(k) + gear_bonus(k)
	if style != "":
		v += int(Rpg.STYLES[style].attrs.get(k, 0))
	v += int(Origins.get_origin(origin).attrs.get(k, 0))
	return v

func attrs() -> Dictionary:
	var d := {}
	for k in Rpg.ATTR_ORDER:
		d[k] = attr(k)
	return d

func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n

func attr_points() -> int:
	return (player_level() - 1) * Rpg.ATTR_POINTS_PER_LEVEL - _sum(attr_alloc)

## Class-tree points: 1 + one every other level. Spec-tree points start once you pick a spec.
func class_points_total() -> int:
	return Rpg.START_TALENT_POINTS + player_level() / Rpg.LEVELS_PER_TALENT_POINT

func spec_points_total() -> int:
	return 0 if spec == "" else maxi(0, (player_level() - Specs.UNLOCK_LEVEL) / 2 + 1)

func points_left(tree: String) -> int:
	var total := class_points_total() if tree == "class" else spec_points_total()
	return total - TalentTrees.spent_in(talents, tree, spec)

func talent_points() -> int:
	return points_left("class") + points_left("spec")

func raise_attr(k: String) -> bool:
	if attr_points() <= 0 or attr(k) >= Rpg.ATTR_CAP:
		return false
	attr_alloc[k] = int(attr_alloc.get(k, 0)) + 1
	if attr(k) >= 12:
		unlock("peak")
	save_game()
	progress_changed.emit()
	return true

func tree_points(tree: String) -> int:
	return TalentTrees.spent_in(talents, tree, spec)

func talent_rank(tid: String) -> int:
	return int(talents.get(tid, 0))

## Gate (points spent in the tree) and path (a learned node right above it) both open.
func talent_unlocked(tid: String) -> bool:
	var nd := TalentTrees.node(tid, spec)
	if nd.is_empty():
		return false
	var tr := TalentTrees.tree_of(tid)
	if tr == "spec" and spec == "":
		return false
	if tree_points(tr) < TalentTrees.gate_need(tr, int(nd.row)):
		return false
	var req: Array = nd.get("req", [])
	if req.is_empty():
		return true
	for r in req:
		if talent_rank(str(r)) > 0:
			return true
	return false

func can_learn(tid: String) -> bool:
	var nd := TalentTrees.node(tid, spec)
	if nd.is_empty() or not talent_unlocked(tid):
		return false
	var full := talent_rank(tid) >= (1 if str(nd.get("kind", "")) == "choice" else int(nd.max))
	return not full and points_left(TalentTrees.tree_of(tid)) > 0

## Learn one rank (choice nodes: option 0 or 1).
func learn(tid: String, choice := 0) -> bool:
	if not can_learn(tid):
		return false
	var nd := TalentTrees.node(tid, spec)
	if str(nd.get("kind", "")) == "choice":
		talents[tid] = clampi(choice, 0, 1) + 1
		toast.emit("Talent: %s" % str(nd.choice[choice].name), Color(0.75, 0.55, 1.0))
	else:
		talents[tid] = talent_rank(tid) + 1
		toast.emit("Talent: %s (%d/%d)" % [nd.name, talents[tid], int(nd.max)], Color(0.75, 0.55, 1.0))
	bump("talented")
	if nd.get("capstone", false):
		unlock("capstone")
	save_game()
	progress_changed.emit()
	return true

## Swap a learned choice node to its other option (free, like WoW).
func swap_choice(tid: String, choice: int) -> void:
	var nd := TalentTrees.node(tid, spec)
	if str(nd.get("kind", "")) == "choice" and talent_rank(tid) > 0:
		talents[tid] = clampi(choice, 0, 1) + 1
		save_game()
		progress_changed.emit()

func reset_talents(tree := "") -> void:
	if tree == "":
		talents = {}
	else:
		for k in talents.keys():
			if TalentTrees.tree_of(k) == tree:
				talents.erase(k)
	save_game()
	progress_changed.emit()

func mods() -> Dictionary:
	var m := Rpg.build_mods(style, attrs(), talents)
	for b in set_bonuses():
		if b.has("effect"):
			m[b.effect] = true
	Specs.apply(m, spec)
	TalentTrees.apply(m, talents, spec)
	Origins.apply(m, origin)
	# gear item levels: flat Composure and % Power from what you're wearing
	var hp_flat := 0
	var pw := 0.0
	for id in worn():
		hp_flat += Gear.composure(id)
		pw += Gear.power_pct(id)
	m["hp_flat"] = float(m.get("hp_flat", 0.0)) + hp_flat
	m["dmg_all"] = float(m.get("dmg_all", 0.0)) + pw / 100.0
	_buff_mods(m)
	return m

# ------------------------------------------------------------ achievements
func unlock(id: String) -> void:
	if unlocked.has(id):
		return
	var a := Data.achievement(id)
	if a.is_empty():
		return
	unlocked[id] = true
	achievement_unlocked.emit(id)
	save_game()

func bump(id: String, amount := 1) -> void:
	var a := Data.achievement(id)
	if a.is_empty():
		return
	counters[id] = int(counters.get(id, 0)) + amount
	if int(counters[id]) >= int(a.get("goal", 1)):
		unlock(id)
	save_game()

func counter(id: String) -> int:
	return int(counters.get(id, 0))

# ------------------------------------------------------------ world
func discover_landmark(id: String) -> bool:
	if landmarks.has(id):
		return false
	landmarks[id] = true
	bump({"pantanal": "p_explorer", "chapada": "c_explorer", "rio": "r_explorer"}.get(Data.LANDMARKS[id].get("zone", "caceres"), "explorer"))
	toast.emit("Discovered: %s" % Data.LANDMARKS[id].name, Color(0.6, 0.9, 1.0))
	save_game()
	progress_changed.emit()
	return true

func collect_key(z: String, i: int) -> String:
	return str(i) if z == "caceres" else "%s_%d" % [z, i]

func collected(z: String, i: int) -> bool:
	return cups.has(collect_key(z, i))

func collected_count(z: String) -> int:
	var n := 0
	for i in Data.COLLECTIBLES[z].size():
		if collected(z, i):
			n += 1
	return n

func collect_cup(i: int, z := "caceres") -> bool:
	var key := collect_key(z, i)
	if cups.has(key):
		return false
	cups[key] = true
	Sfx.play("collect")
	bump({"pantanal": "feathers", "chapada": "crystals", "rio": "coconuts"}.get(z, "terere"))
	toast.emit("%s %d/%d" % [Data.ZONES[z].collect, collected_count(z), Data.COLLECTIBLES[z].size()], Color(0.55, 0.9, 0.4))
	save_game()
	progress_changed.emit()
	return true

## Non-boss fighters beaten in a zone.
func town_wins(z := "") -> int:
	if z == "":
		z = zone
	var n := 0
	for id in Data.OPPONENTS:
		var o: Dictionary = Data.OPPONENTS[id]
		if Data.zone_of(id) == z and not o.get("boss", false) and beaten(id):
			n += 1
	return n

func beaten(id: String) -> bool:
	return int(wins.get(id, 0)) > 0

func zone_beaten(z: String) -> bool:
	for id in Data.OPPONENTS:
		if Data.zone_of(id) == z and not beaten(id):
			return false
	return true

# ------------------------------------------------------------ quests
func current_objective() -> String:
	# already past this zone's belt: point at the furthest zone the player can ride to
	var zi := ["caceres", "pantanal", "chapada", "rio"].find(zone)
	if zi >= 0 and zi < 3 and belt_index() > zi + 1:
		var best := "rio" if rank >= 15 else ("chapada" if rank >= 10 else "pantanal")
		return "You've outgrown %s. Ride the bus to %s, or hunt quests and medals here." % [Data.ZONES[zone].name, Data.ZONES[best].name]
	if zone == "rio":
		if rank >= 20:
			return "Black belt. Oss! Roll anyone, anywhere: the mat is yours."
		if town_wins("rio") < Data.BOSS_REQUIRED_WINS:
			return "Win rolls around Rio (%d/%d)." % [town_wins("rio"), Data.BOSS_REQUIRED_WINS]
		return "Challenge Grão-Mestre Leão at his academia."
	if zone == "chapada":
		if rank >= 15:
			return "Brown belt! Ride the bus to Rio de Janeiro."
		if town_wins("chapada") < Data.BOSS_REQUIRED_WINS:
			return "Win rolls in the Chapada (%d/%d)." % [town_wins("chapada"), Data.BOSS_REQUIRED_WINS]
		return "Challenge Mestre Cachoeira in the village."
	if zone == "pantanal":
		if rank >= 10:
			return "Purple belt! Ride the bus to the Chapada dos Guimarães."
		if not flags.get("met_jacare", false) and town_wins("pantanal") == 0:
			return "Explore the Pantanal and roll with the locals."
		if town_wins("pantanal") < Data.BOSS_REQUIRED_WINS:
			return "Win rolls in the Pantanal (%d/%d)." % [town_wins("pantanal"), Data.BOSS_REQUIRED_WINS]
		return "Challenge Mestre Jacaré at the fazenda."
	if rank >= 5:
		return "Blue belt! Take the Pantanal gate east of town."
	if not flags.get("met_professor", false):
		if town_wins("caceres") == 0:
			return "Roll with Rafa in the town plaza."
		return "Find the academia behind the cathedral."
	if town_wins("caceres") < Data.BOSS_REQUIRED_WINS:
		return "Win rolls around town (%d/%d)." % [town_wins("caceres"), Data.BOSS_REQUIRED_WINS]
	return "Challenge Mestre Onça at the academia."

func side_objectives() -> Array:
	var out: Array = []
	var mc := medal_counts()
	if mc.gold + mc.silver + mc.bronze > 0:
		out.append("Competition medals: %d gold, %d silver, %d bronze" % [mc.gold, mc.silver, mc.bronze])
	var z: Dictionary = Data.ZONES[zone]
	out.append("%s: %d/%d" % [z.collect, collected_count(zone), Data.COLLECTIBLES[zone].size()])
	var lms := Data.landmarks_in(zone)
	var found := 0
	for id in lms:
		if landmarks.has(id):
			found += 1
	out.append("Landmarks in %s: %d/%d" % [z.name, found, lms.size()])
	var total := 0
	var bt := 0
	for id in Data.OPPONENTS:
		if Data.zone_of(id) == zone:
			total += 1
			if beaten(id):
				bt += 1
	out.append("Fighters beaten in %s: %d/%d" % [z.name, bt, total])
	out.append("Drills: %s" % ("ready at the gym" if drills_ready else "roll once to refresh"))
	return out

func _count_beaten() -> int:
	var n := 0
	for id in Data.OPPONENTS:
		if beaten(id):
			n += 1
	return n

# ------------------------------------------------------------ roll results
## Called by the roll scene when a match ends.
func record_roll(opp_id: String, result: Dictionary) -> int:
	var opp: Dictionary = Data.OPPONENTS[opp_id]
	unlock("first_roll")
	var gained := 0
	if result.won:
		wins[opp_id] = int(wins.get(opp_id, 0)) + 1
		var first_time := int(wins[opp_id]) == 1
		if result.by_sub:
			quest_event("sub_wins")
		gained = int(30 + 18 * float(opp.level))
		if result.by_sub:
			gained += 15
			unlock("first_tap")
			var sub: String = result.get("sub", "")
			if sub == "triangle":
				unlock("triangle_win")
			elif sub in ["guard_armbar", "mount_armbar"]:
				unlock("armbar_win")
			elif sub == "rnc":
				unlock("choke_win")
			elif sub in ["straight_ankle", "kneebar"]:
				unlock("leglock_win")
			elif sub == "guillotine":
				unlock("guillotine_win")
		else:
			unlock("points_win")
		if not first_time:
			gained = int(gained * 0.5)
		var zid := Data.zone_of(opp_id)
		if Data.ZONES.has(zid):
			gained = int(gained * (1.0 + 0.1 * held_in(zid)))
		if result.get("signature", false):
			unlock("signature_win")
		if result.get("min_stamina", 0.0) >= 30.0:
			unlock("iron_lungs")
		if int(opp.rank) - rank >= 5:
			unlock("giant_slayer")
		if zone_beaten("caceres"):
			unlock("undefeated")
		if zone_beaten("pantanal"):
			unlock("pantanal_king")
		if zone_beaten("chapada"):
			unlock("chapada_king")
		if zone_beaten("rio"):
			unlock("rio_king")
	else:
		losses[opp_id] = int(losses.get(opp_id, 0)) + 1
		gained = 0   # a loss (tapping out included) pays nothing, like dying in WoW
		if result.by_sub:
			unlock("tapped")
	drills_ready = true
	add_xp(gained)
	if result.won and Gear.BOSS_SET.has(opp_id):
		boss_drop(Gear.BOSS_SET[opp_id])
	if result.won and opp.get("boss", false):
		promote_belt({"caceres": 1, "pantanal": 2, "chapada": 3, "rio": 4}.get(Data.zone_of(opp_id), 1))
	save_game()
	progress_changed.emit()
	return gained

func _all_town_beaten() -> bool:
	for id in Data.OPPONENTS:
		if not beaten(id):
			return false
	return true


# ------------------------------------------------------------ quests
signal quest_progress(id: String)

func quest_state(id: String) -> String:
	return str(quests.get(id, {}).get("state", ""))

## Can the player pick this quest up right now?
func quest_available(id: String) -> bool:
	if quest_state(id) != "":
		return false
	var q: Dictionary = Data.QUESTS[id]
	for r in q.get("requires", []):
		if quest_state(r) != "done":
			return false
	return player_level() >= int(q.min_level)

func quest_locked_by_level(id: String) -> bool:
	var q: Dictionary = Data.QUESTS[id]
	if quest_state(id) != "":
		return false
	for r in q.get("requires", []):
		if quest_state(r) != "done":
			return false
	return player_level() < int(q.min_level)

func accept_quest(id: String) -> void:
	if not quest_available(id):
		return
	quests[id] = {"state": "active", "count": {}}
	toast.emit("Quest accepted: %s" % Data.QUESTS[id].title, Color(1, 0.85, 0.3))
	save_game()
	progress_changed.emit()

## [current, needed] for one objective.
func objective_progress(id: String, i: int) -> Array:
	var o: Dictionary = Data.QUESTS[id].obj[i]
	var cnt := int(quests.get(id, {}).get("count", {}).get(str(i), 0))
	match o.type:
		"collect":
			return [mini(collected_count(o.zone), o.n), o.n]
		"count_landmarks":
			var n := 0
			for lid in Data.landmarks_in(o.zone):
				if landmarks.has(lid):
					n += 1
			return [mini(n, o.n), o.n]
		"landmarks":
			var n2 := 0
			for lid in o.ids:
				if landmarks.has(lid):
					n2 += 1
			return [n2, o.ids.size()]
		"beat":
			var n3 := 0
			for oid in o.ids:
				if beaten(oid):
					n3 += 1
			return [n3, o.ids.size()]
		"medal":
			for b in Data.BELTS.size():
				if str(medals.get("%s_%d" % [o.comp, b], "")) != "":
					return [1, 1]
			return [0, 1]
		"reach":
			return [mini(cnt, 1), 1]
		_:
			return [mini(cnt, int(o.n)), int(o.n)]

func quest_ready(id: String) -> bool:
	if quest_state(id) != "active":
		return false
	for i in Data.QUESTS[id].obj.size():
		var p := objective_progress(id, i)
		if int(p[0]) < int(p[1]):
			return false
	return true

## Event-driven objectives (drills, sub wins, dailies, reach points) count from acceptance.
func quest_event(kind: String, key := "") -> void:
	var changed := false
	for id in quests:
		if quest_state(id) != "active":
			continue
		var objs: Array = Data.QUESTS[id].obj
		for i in objs.size():
			var o: Dictionary = objs[i]
			if o.type != kind:
				continue
			if kind == "reach" and key != "%s:%d" % [id, i]:
				continue
			var was_ready := quest_ready(id)
			quests[id].count[str(i)] = int(quests[id].count.get(str(i), 0)) + 1
			changed = true
			if quest_ready(id) and not was_ready:
				toast.emit("%s: complete! Return to %s." % [Data.QUESTS[id].title, Data.QUEST_GIVERS[Data.QUESTS[id].giver].name], Color(1, 0.85, 0.3))
			quest_progress.emit(id)
	if changed:
		save_game()
		progress_changed.emit()

func complete_quest(id: String) -> int:
	if not quest_ready(id):
		return 0
	quests[id].state = "done"
	var q: Dictionary = Data.QUESTS[id]
	toast.emit("Quest complete: %s  (+%d XP)" % [q.title, int(q.xp)], Color(1, 0.85, 0.3))
	unlock("quest_1")
	bump("quests_10")
	bump("quests_all")
	add_xp(int(q.xp))
	give_item(Gear.QUEST_LOOT.get(id, ""))
	return int(q.xp)

func active_quests(z := "") -> Array:
	var out: Array = []
	for id in quests:
		if quest_state(id) == "active" and (z == "" or Data.QUEST_GIVERS[Data.QUESTS[id].giver].zone == z):
			out.append(id)
	return out

## "!" available, "?" ready to turn in, "…" in progress, "" nothing for this giver.
func giver_marker(giver: String) -> String:
	var progress := false
	var avail := false
	for id in Data.quests_of(giver):
		if quest_ready(id):
			return "?"
		if quest_state(id) == "active":
			progress = true
		elif quest_available(id):
			avail = true
	if avail:
		return "!"
	return "…" if progress else ""

# ------------------------------------------------------------ competitions
func medal_counts() -> Dictionary:
	var out := {"gold": 0, "silver": 0, "bronze": 0}
	for k in medals:
		if out.has(medals[k]):
			out[medals[k]] += 1
	return out

func best_medal(comp_id: String, belt := -1) -> String:
	return str(medals.get("%s_%d" % [comp_id, belt if belt >= 0 else belt_index()], ""))

## One match inside a bracket. Smaller XP than a named rival; the medal is the prize.
func record_comp_match(result: Dictionary, opp_level: float) -> int:
	unlock("first_roll")
	drills_ready = true
	var gained := 0
	if result.won:
		gained = int(20 + 10 * opp_level)
		if result.by_sub:
			quest_event("sub_wins")
			gained += 10
			unlock("first_tap")
		else:
			unlock("points_win")
	elif result.by_sub:
		unlock("tapped")
	add_xp(gained)
	return gained

## Stores the best medal for this comp + belt and pays out. Returns the XP awarded.
func award_medal(comp_id: String, belt: int, medal: String) -> int:
	var key := "%s_%d" % [comp_id, belt]
	var prev := str(medals.get(key, ""))
	if Data.MEDAL_ORDER.find(medal) > Data.MEDAL_ORDER.find(prev):
		medals[key] = medal
	unlock("first_medal")
	var xp_gain: int = {"gold": 260, "silver": 150, "bronze": 90}.get(medal, 0)
	if medal == "gold":
		unlock("first_gold")
		give_item("tape_pro")
		if comp_id == "mundial":
			unlock("world_champ")
			give_item("mundial_gi")
		var regional := 0
		for c in ["copa_caceres", "pantanal_open", "chapada_open", "rio_open"]:
			for b in Data.BELTS.size():
				if str(medals.get("%s_%d" % [c, b], "")) == "gold":
					regional += 1
					break
		counters["grand_slam"] = regional
		if regional >= 4:
			unlock("grand_slam")
	if prev == medal:
		xp_gain = int(xp_gain * 0.4)  # repeat medals still pay, just less
	add_xp(xp_gain)
	save_game()
	progress_changed.emit()
	return xp_gain

# ------------------------------------------------------------ daily challenge
static func today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

static func yesterday_of(date_str: String) -> String:
	var parts := date_str.split("-")
	var unix := Time.get_unix_time_from_datetime_dict({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]), "hour": 12, "minute": 0, "second": 0})
	var y := Time.get_date_dict_from_unix_time(unix - 86400)
	return "%04d-%02d-%02d" % [y.year, y.month, y.day]

func daily_challenge() -> Dictionary:
	return Data.daily_challenge(today(), rank)

func daily_available() -> bool:
	return str(daily.get("last_win", "")) != today()

func daily_streak() -> int:
	var s := int(daily.get("streak", 0))
	var last := str(daily.get("last_win", ""))
	if last != today() and last != yesterday_of(today()):
		return 0
	return s

## Called when a Daily Challenge roll ends.
func record_daily(result: Dictionary, date_str := "") -> int:
	if date_str == "":
		date_str = today()
	unlock("first_roll")
	drills_ready = true
	daily["last_try"] = date_str
	var gained := 0
	if result.won:
		quest_event("daily_wins")
		if result.by_sub:
			quest_event("sub_wins")
		var last := str(daily.get("last_win", ""))
		if last == date_str:
			gained = 20
		else:
			var streak := int(daily.get("streak", 0)) + 1 if last == yesterday_of(date_str) else 1
			daily["streak"] = streak
			daily["best"] = maxi(int(daily.get("best", 0)), streak)
			daily["last_win"] = date_str
			gained = 120 + 30 * mini(streak, 7)
			unlock("daily_1")
			counters["daily_3"] = streak
			counters["daily_7"] = streak
			if streak >= 3:
				unlock("daily_3")
			if streak >= 7:
				unlock("daily_7")
		if result.by_sub:
			unlock("first_tap")
	else:
		if result.by_sub:
			unlock("tapped")
	add_xp(gained)
	save_game()
	progress_changed.emit()
	return gained

# ------------------------------------------------------------ bags, money, buffs
signal bag_changed

func bag_capacity() -> int:
	var n := Loot.BACKPACK
	for b in bags:
		if str(b) != "":
			n += int(Loot.item(str(b)).get("slots", 0))
	return n

func _fit_bag() -> void:
	while bag.size() < bag_capacity():
		bag.append(null)

func free_slots() -> int:
	var n := 0
	for k in bag_capacity():
		if k >= bag.size() or bag[k] == null:
			n += 1
	return n

## Adds items, stacking first. Returns how many didn't fit (bags full).
func add_item(id: String, n := 1) -> int:
	var it := Loot.item(id)
	if it.is_empty():
		return n
	_fit_bag()
	var stack := int(it.get("stack", 1))
	for k in bag_capacity():
		if n <= 0:
			break
		var s = bag[k]
		if s != null and s.id == id and int(s.n) < stack:
			var put := mini(n, stack - int(s.n))
			s.n = int(s.n) + put
			n -= put
	for k in bag_capacity():
		if n <= 0:
			break
		if bag[k] == null:
			var put := mini(n, stack)
			bag[k] = {"id": id, "n": put}
			n -= put
	bag_changed.emit()
	return n

func count_item(id: String) -> int:
	var c := 0
	for s in bag:
		if s != null and s.id == id:
			c += int(s.n)
	return c

func _take(k: int, n := 1) -> void:
	var s = bag[k]
	if s == null:
		return
	s.n = int(s.n) - n
	if int(s.n) <= 0:
		bag[k] = null

func add_money(amount: int) -> void:
	money = maxi(0, money + amount)
	bag_changed.emit()

## Use the item in a bag slot: eat/drink (buff), equip a bag, or learn a gear drop.
func use_slot(k: int) -> String:
	if k < 0 or k >= bag.size() or bag[k] == null:
		return ""
	var id: String = bag[k].id
	var it := Loot.item(id)
	match str(it.get("kind", "")):
		"food":
			buffs[id] = int(Time.get_unix_time_from_system()) + int(it.mins) * 60
			_take(k)
			toast.emit("%s: %s" % [it.name, it.desc], Loot.color(id))
		"bag":
			var free := bags.find("")
			if free < 0:
				return "Your bag slots are full."
			bags[free] = id
			_take(k)
			_fit_bag()
			toast.emit("Equipped %s (+%d slots)" % [it.name, int(it.slots)], Loot.color(id))
		"gear":
			var gid: String = it.gear
			if has_item(gid):
				return "Already in your wardrobe. Sell it to a vendor."
			give_item(gid)
			equip(gid)
			_take(k)
		_:
			return "Sell this to a vendor."
	save_game()
	bag_changed.emit()
	progress_changed.emit()
	return ""

func sell_slot(k: int) -> int:
	if k < 0 or k >= bag.size() or bag[k] == null:
		return 0
	var it := Loot.item(str(bag[k].id))
	var got := int(it.get("sell", 0)) * int(bag[k].n)
	bag[k] = null
	money += got
	save_game()
	bag_changed.emit()
	return got

func sell_junk() -> int:
	var got := 0
	for k in bag.size():
		if bag[k] != null and str(Loot.item(str(bag[k].id)).get("kind", "")) == "junk":
			got += sell_slot(k)
	return got

func buy(id: String) -> String:
	var it := Loot.item(id)
	var price := int(it.get("buy", 0))
	if price <= 0:
		return "Not for sale."
	if money < price:
		return "Not enough R$."
	if add_item(id) > 0:
		return "Your bags are full."
	money -= price
	save_game()
	bag_changed.emit()
	return ""

## Unequip an extra bag back into the backpack (only if its slots are empty).
func unequip_bag(i: int) -> String:
	if str(bags[i]) == "":
		return ""
	var start := Loot.BACKPACK
	for b in range(i):
		if str(bags[b]) != "":
			start += int(Loot.item(str(bags[b])).get("slots", 0))
	var n := int(Loot.item(str(bags[i])).get("slots", 0))
	for k in range(start, start + n):
		if k < bag.size() and bag[k] != null:
			return "Empty that bag first."
	var id: String = bags[i]
	for k in n:
		bag.remove_at(start)
	bags[i] = ""
	add_item(id)
	save_game()
	bag_changed.emit()
	return ""

## Active buffs: {id: seconds left}. Expired ones are cleared.
func active_buffs() -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var out := {}
	for id in buffs.keys():
		var left := int(buffs[id]) - now
		if left <= 0:
			buffs.erase(id)
		else:
			out[id] = left
	return out

func _buff_mods(m: Dictionary) -> void:
	for id in active_buffs():
		var e: Dictionary = Loot.item(id).get("effect", {})
		for k in e:
			match k:
				"regen":
					m.regen = float(m.regen) * (1.0 + float(e[k]))
				"stamina_max":
					m.stamina_max = float(m.stamina_max) + float(e[k])
				"decision":
					m.decision = float(m.decision) * (1.0 + float(e[k]))
				"defense":
					m.defense = float(m.defense) * (1.0 + float(e[k]))
				"read_resist":
					m["read_resist"] = float(m.get("read_resist", 1.0)) * float(e[k])

func xp_mult() -> float:
	var x := 1.0 + float(Origins.get_origin(origin).mods.get("xp_bonus", 0.0))
	for id in active_buffs():
		x += float(Loot.item(id).get("effect", {}).get("xp", 0.0))
	return x

## A beaten (or lost-to) mob: XP, money and loot. Returns {xp, money, items, lost: [ids that didn't fit]}.
func record_mob(result: Dictionary, mob: Dictionary) -> Dictionary:
	unlock("first_roll")
	drills_ready = true
	var lv := float(mob.level)
	var out := {"xp": 0, "money": 0, "items": [], "lost": []}
	if not result.won:
		return out   # no XP for losing / tapping out
	var gained := int(16 + 9 * lv)
	if mob.get("elite", false):
		gained = int(gained * 1.6)
	if mob.get("rare", false):
		gained *= 3
	if result.by_sub:
		gained += 8
		quest_event("sub_wins")
	# grey mobs (far below you) give almost nothing, like WoW
	if Data.display_level(lv) < player_level() - 6:
		gained = int(gained * 0.15)
	out.xp = gained
	add_xp(gained)
	bump("mob_kills")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var loot := Loot.roll_loot(mob, zone, rng)
	out.money = int(loot.money)
	money += out.money
	for id in loot.items:
		if add_item(str(id)) > 0:
			out.lost.append(id)
		else:
			out.items.append(id)
	save_game()
	bag_changed.emit()
	return out

# ------------------------------------------------------------ specs
func can_choose_spec() -> bool:
	return style != "" and player_level() >= Specs.UNLOCK_LEVEL

func spec_cost(id: String) -> int:
	return 0 if spec == "" or spec == id else Specs.RESPEC_COST

func choose_spec(id: String) -> String:
	if Specs.style_of(id) != style:
		return "That spec belongs to another class."
	if not can_choose_spec():
		return "Specs unlock at level %d." % Specs.UNLOCK_LEVEL
	if id == spec:
		return ""
	var cost := spec_cost(id)
	if money < cost:
		return "Changing spec costs R$ %d." % cost
	money -= cost
	reset_talents("spec")
	spec = id
	var s := Specs.get_spec(id)
	toast.emit("Specialization: %s. New %s: %s" % [s.name, "ability" if str(s.move) == "" else "technique", Specs.ADVICE_NAME if str(s.move) == "" else str(Data.MOVES[s.move].name)], Color(0.75, 0.55, 1.0))
	save_game()
	progress_changed.emit()
	return ""
