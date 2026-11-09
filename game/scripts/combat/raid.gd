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

func start(world_combat, at: Vector3, lvl: int) -> void:
	wc = world_combat
	level = lvl
	center = at
	var cl: float = 1.0 + (lvl - 1) * 0.55 / 2.0
	var bd := {"name": "Grão-Mestre Sucuri", "title": "Raid Boss", "level": cl + 0.4, "rank": Game.rank, "style": "pressure",
		"gi": Color(0.2, 0.32, 0.18), "skin": Color(0.5, 0.34, 0.22), "body": "male", "raid": true, "boss": true,
		"win": "The Sucuri always wins.", "lose": "Oss... the academy is yours."}
	boss_npc = _spawn(bd, at + Vector3(0, 0, -5))
	boss_npc.rig.bulk = 1.3
	boss = wc.unit_for(boss_npc, "boss")
	boss.max_hp *= 3.2
	boss.hp = boss.max_hp
	boss.dmg *= 0.9
	var role := Team.player_role()
	var i := 0
	for r in party_for(role):
		var d: Dictionary = PARTY[r].duplicate()
		d["ally"] = true
		d["role"] = "dps" if r.begins_with("dps") else r
		d["level"] = cl
		d["rank"] = Game.rank
		var ang := -0.9 + i * 0.6
		var n := _spawn(d, at + Vector3(sin(ang) * 3.0, 0, cos(ang) * 3.0 + 1.0))
		ally_npcs.append(n)
		wc.unit_for(n)
		i += 1
	warning.emit("COVIL DA SUCURI", "Bruna holds him, Gil keeps you up. Sprawl (Q) his Takedown Wave!")

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
	if over or boss == null or boss.dead:
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
	if crush_t <= 0.0 and boss.target and not boss.target.dead and boss.cast.is_empty():
		crush_t = 12.0
		var tg: CombatCore.Unit = boss.target
		wc.core._damage(boss, tg, boss.dmg * 3.2, false, {"id": "crush", "type": "pass", "name": "Crushing Kesa"})
		wc._float_on(tg, "Crushing Kesa!", Color(1, 0.4, 0.3))
	# Takedown Wave: a long cast at you; only your Sprawl (Q) stops it, or the whole party goes down
	if wave_t <= 0.0 and boss.cast.is_empty() and not boss.down():
		wave_t = 24.0
		var ab := {"id": "wave", "name": "Takedown Wave", "type": "takedown", "cast": 2.8, "dmg": 0.0, "range": 60.0, "_mv": ""}
		boss.cast = {"ab": ab, "t": 0.0, "dur": 2.8, "target": wc.me}
		wc.core.emit({"t": "cast", "u": boss, "ab": ab, "target": wc.me, "dur": 2.8})
		warning.emit("TAKEDOWN WAVE!", "SPRAWL IT! [Q]")
	# students join the fight
	for th in [0.6, 0.3]:
		if boss.pct() <= th and not _adds_called.has(th):
			_adds_called[th] = true
			_call_students()
	if t >= 240.0 and not _enraged:
		_enraged = true
		boss.dmg *= 2.0
		warning.emit("THE SUCURI IS ENRAGED", "Finish it now!")

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
		var d := {"name": ["Aluno da Sucuri", "Aluna da Sucuri"][k], "title": "Student", "level": cl - 0.3, "rank": Game.rank,
			"style": "balanced", "gi": Color(0.2, 0.32, 0.18), "skin": Color(0.7, 0.5, 0.35), "body": ["male", "female"][k]}
		var n := _spawn(d, center + Vector3(-6 + 12 * k, 0, -7))
		add_npcs.append(n)
		var u = wc.unit_for(n, "mob")
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
		var gear_id := Game.make_rolled(_epic_roll())
		Game.add_item("gear:" + gear_id)
		var xp := 120 + 25 * level
		Game.add_xp(xp)
		Game.money += 60 + 6 * level
		Game.unlock("raid_sucuri")
		Game.toast.emit("Raid cleared! +%d XP, R$ %d" % [xp, 60 + 6 * level], Color(1, 0.85, 0.35))
		Game.toast.emit("Looted: %s" % str(Gear.ITEMS[gear_id].name), Gear.rarity_color(gear_id))
		Game.save_game()
	for n in ally_npcs + add_npcs + [boss_npc]:
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

func _epic_roll() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var d := Gear.roll(level + 2, rng, true, true)
	d["rarity"] = "epic"
	d["name"] = "Sucuri's " + str(d.name).split(" ", false, 1)[1]
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
