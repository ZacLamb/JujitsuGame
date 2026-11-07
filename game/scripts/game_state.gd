extends Node
## Persistent player progress: XP, rank, achievements, quests, world flags. Saves to user://.

signal achievement_unlocked(id: String)
signal toast(text: String, color: Color)
signal progress_changed

const SAVE_PATH := "user://tatame_save.json"
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
var player_name := "Gringo"
var style := ""            # Rpg.STYLES key; "" until chosen
var gi_index := 0
var attr_alloc := {}       # attribute -> points spent
var talents := {}          # talent id -> rank
var stripe_xp := 0
var zone := "caceres"
var train := {}            # attribute -> drill successes
var drills_ready := true   # drills refresh after every roll
var daily := {}            # {"last_win": date, "last_try": date, "streak": n, "best": n}
var test_mode := false  # set by tests to avoid writing saves

func _ready() -> void:
	load_game()

# ------------------------------------------------------------ persistence
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func reset() -> void:
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
	attr_alloc = {}
	talents = {}
	stripe_xp = 0
	zone = "caceres"
	train = {}
	drills_ready = true
	daily = {}
	save_game()
	progress_changed.emit()

func save_game() -> void:
	if test_mode:
		return
	var data := {
		"v": SAVE_VERSION, "xp": xp, "rank": rank, "wins": wins, "losses": losses,
		"unlocked": unlocked, "counters": counters, "landmarks": landmarks,
		"cups": cups, "flags": flags, "name": player_name,
		"style": style, "gi": gi_index, "attrs": attr_alloc, "talents": talents,
		"stripe_xp": stripe_xp, "zone": zone, "train": train, "drills_ready": drills_ready, "daily": daily,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

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
	attr_alloc = parsed.get("attrs", {})
	talents = parsed.get("talents", {})
	stripe_xp = int(parsed.get("stripe_xp", xp % Data.XP_PER_STRIPE if rank < 4 else 0))
	zone = str(parsed.get("zone", "caceres"))
	train = parsed.get("train", {})
	drills_ready = bool(parsed.get("drills_ready", true))
	daily = parsed.get("daily", {})

# ------------------------------------------------------------ rank / xp
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
	var before := player_level()
	xp += amount
	var after := player_level()
	if after > before:
		if not test_mode:
			Sfx.play("levelup")
		toast.emit("LEVEL %d!  +%d attribute points, +%d talent point" % [after, Rpg.ATTR_POINTS_PER_LEVEL * (after - before), Rpg.TALENT_POINTS_PER_LEVEL * (after - before)], Color(0.6, 0.9, 1.0))
	stripe_xp += amount
	while stripe_xp >= Data.XP_PER_STRIPE and not at_stripe_cap() and rank < 24:
		stripe_xp -= Data.XP_PER_STRIPE
		rank += 1
		toast.emit("New stripe! %s" % Data.rank_name(rank), Data.BELTS[belt_index()].color)
		unlock("first_stripe")
		_announce_new_moves(rank)
	if at_stripe_cap():
		stripe_xp = mini(stripe_xp, Data.XP_PER_STRIPE - 1)
	save_game()
	progress_changed.emit()

## Promote to the next belt (called when a zone boss is beaten).
func promote_belt(to_belt: int) -> void:
	if belt_index() >= to_belt:
		return
	rank = to_belt * 5
	stripe_xp = 0
	var b: Dictionary = Data.BELTS[to_belt]
	toast.emit("PROMOTED: %s Belt!" % b.name, b.color)
	unlock({1: "blue_belt", 2: "purple_belt", 3: "brown_belt", 4: "black_belt"}.get(to_belt, ""))
	_announce_new_moves(rank)
	save_game()
	progress_changed.emit()

func promote_to_blue() -> void:
	promote_belt(1)

func _announce_new_moves(r: int) -> void:
	for id in Data.MOVES:
		if int(Data.MOVES[id].rank) == r:
			toast.emit("Technique unlocked: %s" % Data.MOVES[id].name, Color(1, 0.85, 0.4))

func knows(move_id: String) -> bool:
	if int(Data.MOVES[move_id].rank) <= rank:
		return true
	if style != "" and move_id in Rpg.STYLES[style].signature:
		return true
	for tid in talents:
		if int(talents[tid]) <= 0 or not Rpg.TALENTS.has(tid):
			continue
		var t: Dictionary = Rpg.TALENTS[tid]
		if t.get("move", "") == move_id or move_id in t.get("moves", []):
			return true
	return false

# ------------------------------------------------------------ RPG build
func choose_style(id: String, name_: String, gi: int) -> void:
	style = id
	player_name = name_.strip_edges().left(16) if name_.strip_edges() != "" else "Gringo"
	gi_index = clampi(gi, 0, Rpg.GI_COLORS.size() - 1)
	unlock("chose_style")
	save_game()
	progress_changed.emit()

func gi_color() -> Color:
	return Rpg.GI_COLORS[gi_index]

func player_level() -> int:
	return Rpg.level_for_xp(xp)

const DRILLS_PER_POINT := 3
const TRAIN_CAP := 5

func train_bonus(k: String) -> int:
	return mini(int(train.get(k, 0)) / DRILLS_PER_POINT, TRAIN_CAP)

## Record a successful drill. Returns true if it earned a permanent attribute point.
func complete_drill(k: String) -> bool:
	var before := train_bonus(k)
	train[k] = int(train.get(k, 0)) + 1
	bump("drills")
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
	var v := Rpg.ATTR_BASE + int(attr_alloc.get(k, 0)) + train_bonus(k)
	if style != "":
		v += int(Rpg.STYLES[style].attrs.get(k, 0))
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

func talent_points() -> int:
	return Rpg.START_TALENT_POINTS + (player_level() - 1) * Rpg.TALENT_POINTS_PER_LEVEL - _sum(talents)

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
	var n := 0
	for tid in talents:
		if Rpg.TALENTS.has(tid) and Rpg.TALENTS[tid].tree == tree:
			n += int(talents[tid])
	return n

func talent_rank(tid: String) -> int:
	return int(talents.get(tid, 0))

func talent_unlocked(tid: String) -> bool:
	var t: Dictionary = Rpg.TALENTS[tid]
	return tree_points(t.tree) >= Rpg.TIER_REQ[int(t.tier)]

func can_learn(tid: String) -> bool:
	var t: Dictionary = Rpg.TALENTS[tid]
	return talent_points() > 0 and talent_rank(tid) < int(t.max) and talent_unlocked(tid)

func learn(tid: String) -> bool:
	if not can_learn(tid):
		return false
	talents[tid] = talent_rank(tid) + 1
	var t: Dictionary = Rpg.TALENTS[tid]
	toast.emit("Talent: %s (%d/%d)" % [t.name, talents[tid], int(t.max)], Rpg.TREES[t.tree].color)
	bump("talented")
	if int(t.tier) == 3:
		unlock("capstone")
	save_game()
	progress_changed.emit()
	return true

func reset_talents() -> void:
	talents = {}
	save_game()
	progress_changed.emit()

func mods() -> Dictionary:
	return Rpg.build_mods(style, attrs(), talents)

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
		else:
			unlock("points_win")
		if not first_time:
			gained = int(gained * 0.5)
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
		gained = 12
		if result.by_sub:
			unlock("tapped")
	drills_ready = true
	add_xp(gained)
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
	var gained := 15
	if result.won:
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
