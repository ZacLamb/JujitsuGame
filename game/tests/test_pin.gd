extends Node
## A named technique on the bar throws exactly that technique, shares its kind's cooldown, and
## is blocked from the wrong position.
var fails := 0
var moves: Array = []
func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", msg)
func _ready() -> void:
	Game.test_mode = true
	var bal = load("res://tests/test_balance.gd").new()
	bal._build("judoka", 12)
	var known := Abilities.known_moves()
	print("known takedowns: ", known.filter(func(m): return str(Data.MOVES[m].type) == "takedown"))
	var tds: Array = known.filter(func(m): return str(Data.MOVES[m].type) == "takedown")
	check(tds.size() >= 2, "need two takedowns to choose between")
	for pick in tds:
		var core := CombatCore.new()
		core.rng.seed = 3
		var me := core.add_player("You", 12, Game.mods(), Abilities.player_kit())
		me.known = known
		var e := core.add_enemy({"name": "Mob", "level": 4.0, "style": "balanced", "rank": Game.rank}, "mob")
		e.pos = Vector3(1, 0, 0)
		core.engage(me, e)
		me.target = e
		e.ai_t = 999.0
		moves = []
		core.event.connect(func(ev): if str(ev.t) == "position": moves.append(str(ev.get("move", ""))))
		var a := core.ability(me, "mv:" + str(pick))
		check(not a.is_empty() and str(a.id) == "takedown" and str(a.name) == str(Data.MOVES[pick].name), "pinned ability for %s" % pick)
		var why := core.use(me, "mv:" + str(pick))
		check(why == "", "use %s: %s" % [pick, why])
		check(moves.size() == 1 and moves[0] == pick, "threw %s, wanted %s" % [str(moves), pick])
		check(float(me.cds.get("takedown", 0.0)) > 0.0, "shares the takedown cooldown")
		# now on the ground: the standing technique must not fire
		me.gcd = 0.0
		me.cds.clear()
		me.gas = me.max_gas
		var why2 := core.use(me, "mv:" + str(pick))
		check(why2 != "", "%s should be blocked on the ground" % pick)
	check(CombatCore.new().ability(CombatCore.Unit.new(), "mv:nope").is_empty(), "unknown technique is empty")
	# layout: the bar holds 20, technique ids survive ensure_bar
	Game.ensure_bar(Abilities.player_kit())
	Game.bar_set(12, "mv:" + str(tds[0]))
	Game.ensure_bar(Abilities.player_kit())
	check(Game.bar_id(12) == "mv:" + str(tds[0]), "row-two slot kept: " + Game.bar_id(12))
	check(CombatHud.layout_index(CombatHud.ROW2 + 2) == 12 and CombatHud.layout_index(11) == -1, "slot mapping")
	print("PASS (0 failures)" if fails == 0 else "FAILED (%d)" % fails)
	get_tree().quit()
