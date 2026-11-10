class_name Raid
extends Node
## Covil da Sucuri: a five-fighter academy raid. You plus four AI training partners (tank, healer,
## damage, filling whatever your spec isn't) against Grão-Mestre Sucuri, scaled to your level.
## Mechanics: Crushing Kesa (a heavy hit on whoever he's fighting), Takedown Wave (a party-wide
## cast that only your Sprawl stops), students called in at 60% / 30% who go for the healer, and an
## enrage at four minutes.

signal finished(won: bool)
signal warning(head: String, sub: String)

const ARENA_R := 14.0
const PARTY := {
	"tank": {"name": "Bruna", "title": "Anchor", "gi": Color(0.15, 0.3, 0.75), "body": "female", "skin": Color(0.72, 0.52, 0.36)},
	"heal": {"name": "Professor Gil", "title": "Professor", "gi": Color(0.1, 0.1, 0.12), "body": "male", "skin": Color(0.55, 0.38, 0.26)},
	"dps": {"name": "Tiago", "title": "Finisher", "gi": Color(0.95, 0.95, 0.95), "body": "male", "skin": Color(0.86, 0.66, 0.5)},
	"dps2": {"name": "Cida", "title": "Scrambler", "gi": Color(0.95, 0.95, 0.95), "body": "female", "skin": Color(0.55, 0.38, 0.26)},
	"dps3": {"name": "Peixe", "title": "Grinder", "gi": Color(0.15, 0.3, 0.75), "body": "male", "skin": Color(0.62, 0.42, 0.28)},
}

## Every raid shares the mechanics; this is what changes between them.
const RAIDS := {
	"sucuri": {"title": "COVIL DA SUCURI", "boss": "Grão-Mestre Sucuri", "boss_gi": Color(0.2, 0.32, 0.18), "boss_skin": Color(0.5, 0.34, 0.22),
		"party": PARTY, "crush": "Crushing Kesa", "adds": ["Aluno da Sucuri", "Aluna da Sucuri"], "add_gi": Color(0.2, 0.32, 0.18),
		"ach": "raid_sucuri", "prefix": "Sucuri's", "intro": "Bruna holds him, Gil keeps you up. Sprawl (Q) his Takedown Wave!",
		"enrage": "THE SUCURI IS ENRAGED", "victory": "Grão-Mestre Sucuri taps. The academy is yours.", "wipe": "The Sucuri holds the academy. Regroup and try again."},
	"compound": {"title": "THE GOLD COMPOUND", "boss": "Gunnar Sterling", "boss_gi": Color(0.86, 0.68, 0.16), "boss_skin": Color(0.92, 0.76, 0.62),
		"party": {
			"tank": {"name": "Lacey", "title": "Anchor", "gi": Color(0.95, 0.95, 0.95), "body": "female", "skin": Color(0.88, 0.7, 0.55)},
			"heal": {"name": "Coach Mae", "title": "Professor", "gi": Color(0.1, 0.1, 0.12), "body": "female", "skin": Color(0.62, 0.45, 0.32)},
			"dps": {"name": "Travis", "title": "Finisher", "gi": Color(0.15, 0.3, 0.75), "body": "male", "skin": Color(0.55, 0.38, 0.26)},
			"dps2": {"name": "Jolene", "title": "Scrambler", "gi": Color(0.95, 0.95, 0.95), "body": "female", "skin": Color(0.86, 0.66, 0.5)},
			"dps3": {"name": "Duke", "title": "Grinder", "gi": Color(0.8, 0.15, 0.15), "body": "male", "skin": Color(0.78, 0.57, 0.4)}},
		"crush": "Golden Kesa", "adds": ["Gold League Member", "Franchise Coach"], "add_gi": Color(0.86, 0.68, 0.16),
		"ach": "raid_gold", "prefix": "Sterling's", "intro": "Lacey holds him, Coach Mae keeps you up. Sprawl (Q) his Takedown Wave!",
		"enrage": "STERLING IS ENRAGED", "victory": "Gunnar Sterling taps. The swamp gyms are free.", "wipe": "The Sterlings hold the compound. Regroup and try again."},
}

## Team USA's raid lives on their continent; Brasil's in the Pantanal.
static func kind_for_zone(z: String) -> String:
	return "compound" if Data.continent_of(z) == "america" else "sucuri"

## Dungeons (Group Finder, K): five-fighter runs from anywhere. Two trash pulls, then a boss with
## its own mix of mechanics, each teaching one of your counters:
##   crush  a heavy hit on whoever holds him (the tank's job; Base Q if it's you)
##   wave   Takedown Wave, a party-wide cast: SPRAWL it (Q)
##   heal   Second Breath, a self-heal cast: FRAME it (R)
##   choke  a long submission cast at you: DEFEND it (T)
##   adds   students at 60% / 30% who go for your healer
const DUNGEONS := {
	"basement": {"title": "THE BASEMENT GYM", "levels": [6, 14], "boss": "Big Sal", "boss_gi": Color(0.35, 0.35, 0.38), "boss_skin": Color(0.82, 0.62, 0.46),
		"trash": [["Basement Grinder", "Basement Grinder"], ["Sweaty Regular", "Basement Grinder", "Mat Hog"]],
		"mechs": ["crush"], "crush": "Sal's Big Squeeze", "adds": [], "add_gi": Color(0.35, 0.35, 0.38), "prefix": "Basement",
		"intro": "Watch his Big Squeeze. Let your tank hold him.", "enrage": "SAL IS FURIOUS", "victory": "Big Sal taps. The basement is quiet.", "wipe": "The basement wins this time."},
	"docks": {"title": "FIGHT CLUB AT THE DOCKS", "levels": [12, 20], "boss": "Capitão Doca", "boss_gi": Color(0.15, 0.3, 0.5), "boss_skin": Color(0.55, 0.38, 0.26),
		"trash": [["Dockhand", "Dockhand"], ["Smuggler", "Dockhand", "Net Thrower"]],
		"mechs": ["crush", "wave"], "crush": "Anchor Drop", "adds": [], "add_gi": Color(0.15, 0.3, 0.5), "prefix": "Dockside",
		"intro": "When he winds up the Takedown Wave, SPRAWL (Q)!", "enrage": "THE CAPTAIN IS ENRAGED", "victory": "Capitão Doca taps. The docks are free.", "wipe": "Thrown in the river. Regroup."},
	"night": {"title": "THE NIGHT TOURNAMENT", "levels": [20, 28], "boss": "The Referee", "boss_gi": Color(0.95, 0.95, 0.95), "boss_skin": Color(0.62, 0.45, 0.32),
		"trash": [["Rigged Finalist", "Bracket Fixer"], ["Paid Judge", "Rigged Finalist", "Bracket Fixer"]],
		"mechs": ["crush", "heal", "adds"], "crush": "Stand-Up Shove", "adds": ["Ringer", "Ringer"], "add_gi": Color(0.1, 0.1, 0.12), "prefix": "Referee's",
		"intro": "He heals himself with Second Breath: FRAME it (R)!", "enrage": "THE REFEREE LOST PATIENCE", "victory": "The Referee taps. Fair brackets again.", "wipe": "Disqualified. Try again."},
	"warehouse": {"title": "THE LUCHA WAREHOUSE", "levels": [28, 36], "boss": "El Toro", "boss_gi": Color(0.8, 0.15, 0.15), "boss_skin": Color(0.66, 0.45, 0.3),
		"trash": [["Masked Luchador", "Masked Luchador"], ["Rudo", "Técnico", "Masked Luchador"]],
		"mechs": ["wave", "choke"], "crush": "Toro Charge", "adds": [], "add_gi": Color(0.8, 0.15, 0.15), "prefix": "Toro's",
		"intro": "SPRAWL (Q) his wave. When he locks a choke on you, DEFEND (T)!", "enrage": "EL TORO SEES RED", "victory": "El Toro taps! The mask stays on.", "wipe": "Pinned for three. Again."},
	"tower": {"title": "STERLING TOWER", "levels": [36, 44], "boss": "The Bodyguard", "boss_gi": Color(0.1, 0.1, 0.12), "boss_skin": Color(0.45, 0.3, 0.2),
		"trash": [["Security Guard", "Security Guard"], ["Lobby Guard", "Personal Trainer", "Security Guard"]],
		"mechs": ["crush", "heal", "choke", "adds"], "crush": "Corporate Crush", "adds": ["Intern", "Intern"], "add_gi": Color(0.86, 0.68, 0.16), "prefix": "Tower",
		"intro": "Frame (R) his Second Breath, Defend (T) his choke, kill the interns!", "enrage": "THE BODYGUARD IS ENRAGED", "victory": "The Bodyguard taps. The penthouse is open.", "wipe": "Escorted out. Regroup."},
	"temple": {"title": "THE HIDDEN TEMPLE", "levels": [44, 50], "boss": "The Old Master", "boss_gi": Color(0.95, 0.92, 0.8), "boss_skin": Color(0.5, 0.36, 0.24),
		"trash": [["Temple Disciple", "Temple Disciple"], ["Senior Disciple", "Temple Guardian", "Temple Disciple"]],
		"mechs": ["crush", "wave", "heal", "choke", "adds"], "crush": "Ancient Kesa", "adds": ["Disciple", "Disciple"], "add_gi": Color(0.95, 0.92, 0.8), "prefix": "Temple",
		"intro": "Everything you've learned: Sprawl (Q), Frame (R), Defend (T).", "enrage": "THE MASTER STOPS PLAYING", "victory": "The Old Master taps... and smiles. Oss.", "wipe": "The Master bows. Come back stronger."},
}
const DUNGEON_ORDER := ["basement", "docks", "night", "warehouse", "tower", "temple"]

var kind := "sucuri"
var cfg: Dictionary = RAIDS.sucuri
var wc   # WorldCombat
var boss_npc: Npc
var boss: CombatCore.Unit
var ally_npcs: Array = []
var add_npcs: Array = []
var level := 1
var t := 0.0
var crush_t := 9.0
var wave_t := 20.0
var _adds_called := {}
var _enraged := false
var over := false
var center := Vector3.ZERO

## The party for your role: everything you aren't, from the academy.
static func party_for(player_role: String) -> Array:
	match player_role:
		"anchor":
			return ["heal", "dps", "dps2", "dps3"]
		"coach":
			return ["tank", "dps", "dps2", "dps3"]
	return ["tank", "heal", "dps", "dps2"]

var dungeon := false
var mechs: Array = ["crush", "wave", "adds"]
var stage := 0                 # dungeons: trash pulls cleared so far
var trash_npcs: Array = []
var heal_t := 16.0
var choke_t := 26.0

func start(world_combat, at: Vector3, lvl: int, raid_kind := "sucuri") -> void:
	dungeon = DUNGEONS.has(raid_kind)
	kind = raid_kind if (RAIDS.has(raid_kind) or dungeon) else "sucuri"
	cfg = DUNGEONS[kind].duplicate() if dungeon else RAIDS[kind]
	if dungeon:
		# your faction's friends from the road fill the party
		var party_src: Dictionary = RAIDS["compound" if Game.faction() == "usa" else "sucuri"]
		cfg["party"] = party_src.party
		cfg["ach"] = "dng_" + kind
	mechs = cfg.get("mechs", ["crush", "wave", "adds"])
	wc = world_combat
	level = lvl
	center = at
	var cl: float = 1.0 + (lvl - 1) * 0.55 / 2.0
	if not dungeon:
		_spawn_boss()
	else:
		_spawn_trash(0)
	var role := Team.player_role()
	var i := 0
	for r in party_for(role):
		var d: Dictionary = (cfg.party as Dictionary)[r].duplicate()
		d["ally"] = true
		d["role"] = "dps" if r.begins_with("dps") else r
		d["level"] = cl
		d["rank"] = Game.rank
		var ang := -0.9 + i * 0.6
		var n := _spawn(d, at + Vector3(sin(ang) * 3.0, 0, cos(ang) * 3.0 + 1.0))
		ally_npcs.append(n)
		wc.unit_for(n)
		i += 1
	warning.emit(str(cfg.title), str(cfg.intro) if not dungeon else "Clear the way: %d pulls, then %s." % [cfg.trash.size(), str(cfg.boss)])

func _spawn_boss() -> void:
	var cl: float = 1.0 + (level - 1) * 0.55 / 2.0
	var bd := {"name": str(cfg.boss), "title": "Dungeon Boss" if dungeon else "Raid Boss", "level": cl + 0.4, "rank": Game.rank, "style": "pressure",
		"gi": cfg.boss_gi, "skin": cfg.boss_skin, "body": "male", "raid": true, "boss": true,
		"win": "Next time.", "lose": "Oss..."}
	boss_npc = _spawn(bd, center + Vector3(0, 0, -5))
	boss_npc.rig.bulk = 1.3
	boss = wc.unit_for(boss_npc, "boss")
	boss.max_hp *= 1.7 if dungeon else 3.2
	boss.hp = boss.max_hp
	boss.dmg *= 0.75 if dungeon else 0.9
	if dungeon and Team.player_role() == "anchor":
		boss.dmg *= 0.85   # you're the tank: no Lacey to share the beating

## A trash pull: they run straight at the party (no need to pull them).
func _spawn_trash(i: int) -> void:
	var cl: float = 1.0 + (level - 1) * 0.55 / 2.0
	var names: Array = cfg.trash[i]
	trash_npcs = []
	for k in names.size():
		var d := {"name": str(names[k]), "title": "Pull %d" % (i + 1), "level": cl - 0.15, "rank": Game.rank,
			"style": ["pressure", "guard", "back", "submission"][k % 4], "gi": cfg.add_gi, "skin": Color(0.96, 0.8, 0.68).lerp(Color(0.36, 0.22, 0.14), randf()),
			"body": "female" if randf() < 0.3 else "male"}
		var n := _spawn(d, center + Vector3(-3.0 + k * 3.0, 0, -6))
		trash_npcs.append(n)
		var u = wc.unit_for(n, "mob")
		u.max_hp *= 0.8
		u.hp = u.max_hp
	warning.emit("PULL %d / %d" % [i + 1, cfg.trash.size()], "Here they come!")
	# engage on the next frame (allies are spawned after this the first time)
	_engage_trash.call_deferred()

func _engage_trash() -> void:
	for n in trash_npcs:
		if not is_instance_valid(n):
			continue
		var u = wc.unit_for(n)
		if u == null:
			continue
		wc.core.engage(u, wc.me)
		u.target = wc.me
		n.in_combat = true
		n.rig.combat_ready = true
		for an in ally_npcs:
			var au = wc.unit_for(an)
			if au and not au.dead:
				wc.core.engage(au, u)
				an.in_combat = true
	if wc.target == null:
		wc.target = wc.unit_for(trash_npcs[0]) if not trash_npcs.is_empty() and is_instance_valid(trash_npcs[0]) else null

func _trash_alive() -> bool:
	for n in trash_npcs:
		if is_instance_valid(n):
			var u = wc._unit_of.get(n.get_instance_id())
			if u != null and not u.dead:
				return true
	return false

func _spawn(d: Dictionary, pos: Vector3) -> Npc:
	var m := d.duplicate()
	m["mob"] = true
	m["raid"] = true
	m["aggro"] = false
	if not m.has("level"):
		m["level"] = 1.0
	var w = wc.world
	pos.y = w.ground_y(pos.x, pos.z)
	var n := Npc.new()
	w.add_child(n)
	n.setup_mob(m, w, pos, 100.0)
	n.global_position = pos
	n._player = wc.player
	n.wander = false
	if m.has("ally"):
		n.tag.modulate = Color(0.45, 1.0, 0.5)
		n.tag.text = "%s\n<%s>" % [str(m.name), str(m.title)]
	return n

func pull() -> void:
	# everyone engages; the tank opens so he starts on her
	for n in ally_npcs:
		var u = wc.unit_for(n)
		if u.role == "tank":
			boss.threat[u.id] = 200.0
		wc.core.engage(u, boss)
		u.target = boss
		n.in_combat = true
	wc.core.engage(wc.me, boss)
	boss_npc.in_combat = true
	boss_npc.rig.combat_ready = true
	boss.target = wc.core._top_threat(boss)

var _pulled := false

func _process(delta: float) -> void:
	if over:
		return
	if dungeon and boss == null:
		# a stray (knocked away, lost its target): pull it back into the fight
		for n in trash_npcs:
			if is_instance_valid(n):
				var tu = wc._unit_of.get(n.get_instance_id())
				if tu != null and not tu.dead and not tu.in_combat:
					if n.global_position.distance_to(center) > 20.0:
						n.global_position = center + Vector3(randf_range(-3, 3), 0, -5)
						n.global_position.y = wc.world.ground_y(n.global_position.x, n.global_position.z)
					wc.core.engage(tu, wc.me)
					tu.target = wc.me
					n.in_combat = true
		if not _trash_alive():
			stage += 1
			if stage < cfg.trash.size():
				_spawn_trash(stage)
			else:
				_spawn_boss()
				warning.emit(str(cfg.boss).to_upper(), str(cfg.intro))
				# he walks in and the party goes straight at him
				wc.core.engage(boss, wc.me)
				boss.target = wc.me
				wc.target = boss
		return
	if boss == null or boss.dead:
		return
	if not _pulled and boss.in_combat:
		_pulled = true
		pull()
	if not boss.in_combat:
		return
	t += delta
	crush_t -= delta
	wave_t -= delta
	# Crushing Kesa: a heavy hit on whoever he's fighting
	if crush_t <= 0.0 and "crush" in mechs and boss.target and not boss.target.dead and boss.cast.is_empty():
		crush_t = 12.0
		var tg: CombatCore.Unit = boss.target
		wc.core._damage(boss, tg, boss.dmg * (2.6 if dungeon else 3.2), false, {"id": "crush", "type": "pass", "name": str(cfg.crush)})
		wc._float_on(tg, str(cfg.crush) + "!", Color(1, 0.4, 0.3))
	# Takedown Wave: a long cast at you; only your Sprawl (Q) stops it, or the whole party goes down
	heal_t -= delta
	choke_t -= delta
	# Second Breath: he heals himself unless someone Frames (R) it
	if "heal" in mechs and heal_t <= 0.0 and boss.cast.is_empty() and not boss.down() and boss.pct() < 0.9:
		heal_t = 20.0
		var hab := {"id": "second_breath", "name": "Second Breath", "type": "advance", "cast": 3.0, "heal": 0.12, "harm": false, "range": 60.0}
		boss.cast = {"ab": hab, "t": 0.0, "dur": 3.0, "target": boss}
		wc.core.emit({"t": "cast", "u": boss, "ab": hab, "target": boss, "dur": 3.0})
		warning.emit("SECOND BREATH!", "FRAME IT! [R]")
	# a long submission at you: Defend (T) or eat it
	if "choke" in mechs and choke_t <= 0.0 and boss.cast.is_empty() and not boss.down():
		choke_t = 23.0
		var cab := {"id": "hidden_choke", "name": "Hidden Choke", "type": "sub", "cast": 3.2, "dmg": 3.0, "finisher": true, "per_grip": 0.0, "range": 60.0, "_mv": "rnc"}
		boss.cast = {"ab": cab, "t": 0.0, "dur": 3.2, "target": wc.me}
		wc.core.emit({"t": "cast", "u": boss, "ab": cab, "target": wc.me, "dur": 3.2})
		warning.emit("HIDDEN CHOKE!", "DEFEND IT! [T]")
	if wave_t <= 0.0 and "wave" in mechs and boss.cast.is_empty() and not boss.down():
		wave_t = 24.0
		var ab := {"id": "wave", "name": "Takedown Wave", "type": "takedown", "cast": 2.8, "dmg": 0.0, "range": 60.0, "_mv": ""}
		boss.cast = {"ab": ab, "t": 0.0, "dur": 2.8, "target": wc.me}
		wc.core.emit({"t": "cast", "u": boss, "ab": ab, "target": wc.me, "dur": 2.8})
		warning.emit("TAKEDOWN WAVE!", "SPRAWL IT! [Q]")
	# students join the fight
	for th in [0.6, 0.3]:
		if "adds" in mechs and boss.pct() <= th and not _adds_called.has(th):
			_adds_called[th] = true
			_call_students()
	if t >= (180.0 if dungeon else 240.0) and not _enraged:
		_enraged = true
		boss.dmg *= 2.0
		warning.emit(str(cfg.enrage), "Finish it now!")

func on_use(u: CombatCore.Unit, ab: Dictionary) -> void:
	if u != boss or str(ab.get("id", "")) != "wave":
		return
	# the wave lands: everyone close takes a beating and goes Down
	for o in wc.core.units.duplicate():
		if CombatCore.friendly(o) and not o.dead and wc.core.dist(o, boss) < 9.0:
			wc.core._damage(boss, o, boss.dmg * 1.8, false, {"id": "wave_hit", "type": "takedown", "name": "Takedown Wave"})
			if not o.dead:
				wc.core._aura(o, "down", 1.5, boss)
	wc.player.add_shake(0.9)

func _call_students() -> void:
	warning.emit("STUDENTS JOIN!", "They're going for your Professor. Take them down!")
	var healer: CombatCore.Unit = null
	for n in ally_npcs:
		var u = wc.unit_for(n)
		if u and u.role == "heal":
			healer = u
	var cl: float = 1.0 + (level - 1) * 0.55 / 2.0
	for k in 2:
		var d := {"name": cfg.adds[k], "title": "Student", "level": cl - 0.3, "rank": Game.rank,
			"style": "balanced", "gi": cfg.add_gi, "skin": Color(0.7, 0.5, 0.35), "body": ["male", "female"][k]}
		var n := _spawn(d, center + Vector3(-6 + 12 * k, 0, -7))
		add_npcs.append(n)
		var u = wc.unit_for(n, "mob")
		if dungeon:
			u.max_hp *= 0.6
			u.hp = u.max_hp
			u.dmg *= 0.7
		var tgt: CombatCore.Unit = healer if healer else wc.me
		u.threat[tgt.id] = 999.0
		wc.core.engage(u, tgt)
		u.target = tgt
		n.in_combat = true
		n.rig.combat_ready = true

func end(won: bool) -> void:
	if over:
		return
	over = true
	if won:
		# your class's tier set first (one missing piece per clear), then rolled epics
		var gear_id := ""
		if dungeon:
			gear_id = Game.make_rolled(_epic_roll() if randf() < 0.35 else _rare_roll())
		else:
			gear_id = Game.missing_tier_piece()
			if gear_id == "":
				gear_id = Game.make_rolled(_epic_roll())
		Game.add_item("gear:" + gear_id)
		var xp := (90 + 20 * level) if dungeon else (120 + 25 * level)
		Game.add_xp(xp)
		Game.money += (40 + 4 * level) if dungeon else (60 + 6 * level)
		Game.unlock(str(cfg.ach))
		if dungeon:
			Game.bump("dungeons_all")
		else:
			Game.add_war(30, "raid")
		Game.toast.emit("%s cleared! +%d XP, R$ %d" % ["Dungeon" if dungeon else "Raid", xp, (40 + 4 * level) if dungeon else (60 + 6 * level)], Color(1, 0.85, 0.35))
		Game.toast.emit("Looted: %s" % str(Gear.ITEMS[gear_id].name), Gear.rarity_color(gear_id))
		Game.save_game()
	for n in ally_npcs + add_npcs + trash_npcs + [boss_npc]:
		if is_instance_valid(n):
			var u = wc._unit_of.get(n.get_instance_id())
			if u:
				wc.core.remove(u)
				wc._unit_of.erase(n.get_instance_id())
				wc._npc_of.erase(u.id)
			n.in_combat = false
			var nn: Npc = n
			get_tree().create_timer(3.0).timeout.connect(func(): if is_instance_valid(nn): nn.queue_free())
	finished.emit(won)
	queue_free()

func _rare_roll() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var d := Gear.roll(level + 1, rng, true, false)
	d["rarity"] = "rare"
	d["name"] = str(cfg.prefix) + " " + str(d.name).split(" ", false, 1)[1]
	d["ilvl"] = level + 1
	var pts := 3 + level / 12
	var pair: Array = ["strength", "grip"]
	for sfx in Gear.SUFFIXES:
		if str(d.name).ends_with(sfx):
			pair = Gear.SUFFIXES[sfx]
	var attrs := {}
	for i in pts:
		attrs[pair[i % 2]] = int(attrs.get(pair[i % 2], 0)) + 1
	d["attrs"] = attrs
	return d

func _epic_roll() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var d := Gear.roll(level + 2, rng, true, true)
	d["rarity"] = "epic"
	d["name"] = str(cfg.prefix) + " " + str(d.name).split(" ", false, 1)[1]
	d["ilvl"] = level + 3
	var pts := 5 + level / 12
	var pair: Array = ["strength", "grip"]
	for sfx in Gear.SUFFIXES:
		if str(d.name).ends_with(sfx):
			pair = Gear.SUFFIXES[sfx]
	var attrs := {}
	for i in pts:
		attrs[pair[i % 2]] = int(attrs.get(pair[i % 2], 0)) + 1
	d["attrs"] = attrs
	return d
