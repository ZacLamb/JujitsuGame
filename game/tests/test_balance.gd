extends Node
## Balance sweep: every class, levels 1-50, against same-level opposition. Builds a "typical"
## character for the level (attributes spent, talents learned, a spec at 10+, gear of the level),
## then runs scenario fights on several seeds with a decent rotation (counters 75% of casts).
const LEVELS := [1, 3, 5, 10, 15, 20, 30, 40, 50]
const SEEDS := 6

func _rotate(core: CombatCore, me: CombatCore.Unit, rng: RandomNumberGenerator) -> void:
	if me.down():
		core.use(me, "escape")
		return
	var t := me.target
	if t and not t.cast.is_empty() and float(t.cast.t) > 0.4 and not t.cast.has("_seen"):
		t.cast["_seen"] = true
		if rng.randf() < 0.75:
			core.use(me, {"base": "base", "frame": "frame", "defend": "defend"}[CombatCore.counter_kind(t.cast.ab)])
	if me.pct() < 0.4:
		if core.use(me, "spec") == "" and Game.spec == "professor":
			return
		core.use(me, "breathe")
	for id in ["sub", "spec", "advance", "back", "takedown", "pass", "sweep", "escape", "handfight"]:
		if id == "sub" and me.grip < 3 and (t == null or t.pct() > 0.3):
			continue
		if core.use(me, id) == "":
			return

func _build(style: String, lvl: int) -> void:
	Game.reset()
	Game.choose_style(style, "T", 0)
	Game.set_level(lvl)
	# attributes: class primaries first
	var order: Array = Rpg.STYLES[style].attrs.keys()
	for k in Rpg.ATTR_ORDER:
		if not k in order:
			order.append(k)
	var i := 0
	while Game.attr_points() > 0:
		var k: String = order[i % 3] if i % 4 != 3 else order[3 + (i / 4) % 2]
		Game.attr_alloc[k] = int(Game.attr_alloc.get(k, 0)) + 1
		i += 1
	if lvl >= Specs.UNLOCK_LEVEL:
		Game.spec = str(Specs.list(style)[0].id)
	# talents: learn anything learnable, top to bottom, until out of points
	for pass_n in 30:
		var any := false
		for tr in ["class", "spec"]:
			for nd in TalentTrees.tree(tr, Game.spec):
				if Game.can_learn(str(nd.id)):
					Game.learn(str(nd.id))
					any = true
		if not any:
			break
	# gear: the best named piece per slot at or below the level
	for id in Gear.ITEMS:
		if Gear.ilvl(id) <= lvl and not Gear.ITEMS[id].get("rolled", false):
			Game.give_item(id, true)

func _fight(lvl: int, foes: Array, seed_v: int, kinds: Array) -> Dictionary:
	var core := CombatCore.new()
	core.rng.seed = seed_v
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 31
	var me := core.add_player("You", lvl, Game.mods(), Abilities.player_kit())
	me.known = Abilities.known_moves()
	var es: Array = []
	for i in foes.size():
		var u := core.add_enemy(foes[i], kinds[i])
		u.pos = Vector3(1.0, 0, 0)
		core.engage(u, me)
		es.append(u)
	me.target = es[0]
	var t := 0.0
	while t < 180.0:
		core.tick(0.05)
		t += 0.05
		if me.dead:
			break
		var alive := es.filter(func(u): return not u.dead)
		if alive.is_empty():
			break
		if me.target == null or me.target.dead:
			me.target = alive[0]
		_rotate(core, me, rng)
	return {"t": t, "won": not me.dead and t < 180.0, "hp": me.pct()}

func _scen(lvl: int, name: String, foes: Array, kinds: Array) -> String:
	var w := 0
	var hp := 0.0
	var tt := 0.0
	for s in SEEDS:
		var r := _fight(lvl, foes, 100 + s, kinds)
		if r.won:
			w += 1
			hp += r.hp
		tt += r.t
	return "%s %3d%% hp%3d%% %3ds" % [name, int(100.0 * w / SEEDS), int(100.0 * hp / maxf(1, w)), int(tt / SEEDS)]

func _ready() -> void:
	Game.test_mode = true
	var only: String = OS.get_environment("BAL_STYLE")
	for style in ["guard", "wrestler", "judoka", "athlete", "passer"]:
		if only != "" and style != only:
			continue
		for lvl in LEVELS:
			_build(style, lvl)
			var cl: float = 1.0 + (lvl - 1) * 0.55 / 2.0
			var mob := {"name": "Mob", "level": cl, "style": "balanced", "rank": Game.rank}
			var elite := {"name": "Elite", "level": cl, "style": "pressure", "elite": true, "rank": Game.rank}
			var rare := {"name": "Rare", "level": cl + 0.3, "style": "submission", "elite": true, "rare": true, "rank": Game.rank}
			var final_ := {"name": "Final", "level": Data.rank_level(Game.rank) - 0.45 + 2 * 0.4 + 0.3, "style": "guard", "elite": true, "rank": Game.rank}
			print("%-8s L%-2d %s | %s | %s | %s | %s" % [style, lvl,
				_scen(lvl, "mob", [mob], ["mob"]), _scen(lvl, "two", [mob, mob], ["mob", "mob"]),
				_scen(lvl, "elite", [elite], ["mob"]), _scen(lvl, "rare", [rare], ["mob"]), _scen(lvl, "final", [final_], ["mob"])])
	get_tree().quit()
