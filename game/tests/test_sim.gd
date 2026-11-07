extends Node
## Headless tests for match logic. Run: godot --headless --path . -s tests/test_sim.gd

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: ", msg)
	else:
		print("ok   ", msg)

func _ready() -> void:
	await get_tree().process_frame
	var data = get_node("/root/Data")
	var game = get_node("/root/Game")
	game.test_mode = true
	check(data != null, "Data autoload present")
	# every move references valid positions and results
	for id in data.MOVES:
		var m: Dictionary = data.MOVES[id]
		check(data.POSITION_NAMES.has(m.pos), "%s has valid pos" % id)
		if typeof(m.result) != TYPE_STRING:
			check(data.POSITION_NAMES.has(m.result[0]), "%s result valid" % id)
	# every position/role has at least one rank-0 option (no dead ends at white belt)
	for p in data.POSITION_NAMES:
		for top in [true, false]:
			var any0 := false
			for id in data.moves_for(p, top):
				if int(data.MOVES[id].rank) == 0:
					any0 = true
			check(any0, "white belt has a move in %s top=%s" % [p, top])
	# simulate many AI-vs-AI style matches to make sure nothing stalls
	var sim := RollSim.new()
	sim.setup("onca", 3.2, func(id): return int(data.MOVES[id].rank) <= 4, 42)
	var steps := 0
	while not sim.over and steps < 5000:
		steps += 1
		var mine: Array = sim.player_options()
		check(not mine.is_empty() or steps > 1, "player has options")
		if sim.rng.randf() < 0.5 and not mine.is_empty():
			var mv: String = mine[sim.rng.randi() % mine.size()]
			var tp = sim.timing_params(mv)
			var j = sim.judge_timing(tp, sim.rng.randf())
			if j != "miss":
				var r = sim.apply_move(mv, true)
				if r.sub and sim.rng.randf() < 0.3:
					sim.finish_by_sub(true, mv)
		else:
			var ai = sim.ai_pick_move()
			if ai != "" and sim.rng.randf() < 0.4:
				var r2 = sim.apply_move(ai, false)
				if r2.sub and sim.rng.randf() < 0.3:
					sim.finish_by_sub(false, ai)
		sim.tick(0.5)
	check(sim.over, "match terminates (%d steps)" % steps)
	check(sim.result.has("won"), "result has winner")
	# timing params stay sane across levels
	for lvl in [1.0, 2.0, 5.2]:
		var s2 := RollSim.new()
		s2.setup("rafa", lvl, func(_id): return true, 1)
		var tp2 = s2.timing_params("triangle")
		check(tp2.width >= 0.04 and tp2.width <= 0.42, "zone width sane at level %s" % lvl)
		check(tp2.center - tp2.width / 2 >= 0.0 and tp2.center + tp2.width / 2 <= 1.0, "zone inside bar")
	# progression
	game.reset()
	var gained = game.record_roll("rafa", {"won": true, "by_sub": true, "sub": "triangle", "min_stamina": 50.0})
	check(gained > 0 and game.xp == gained, "xp awarded")
	check(game.unlocked.has("first_tap") and game.unlocked.has("triangle_win"), "sub achievements")
	game.add_xp(1000)
	check(game.rank == 4, "white belt caps at 4 stripes (rank=%d)" % game.rank)
	game.record_roll("onca", {"won": true, "by_sub": false, "min_stamina": 10.0})
	check(game.rank == 5 and game.unlocked.has("blue_belt"), "boss win promotes to blue")
	# ---------------- RPG layer
	game.reset()
	check(game.player_level() == 1 and game.talent_points() == Rpg.START_TALENT_POINTS and game.attr_points() == 0, "fresh character: level 1, 1 talent point")
	game.choose_style("wrestler", "Tester", 1)
	check(game.attr("strength") == 7 and game.attr("cardio") == 7, "wrestler starts +2 STR +2 CRD")
	check(game.knows("snap_down") and not game.knows("omoplata"), "style signature known, others not")
	check(not game.can_learn("scramble"), "tier 2 locked with 0 points in tree")
	check(game.learn("shot_speed"), "learn tier-1 talent")
	check(not game.learn("shot_speed"), "no points left")
	game.set_level(11)
	check(game.player_level() == 11 and game.belt_index() == 1, "level 11 is blue belt")
	check(game.attr_points() == 10 and game.talent_points() == 5, "points per level (attr=%d tal=%d)" % [game.attr_points(), game.talent_points()])
	game.learn("shot_speed")
	check(game.can_learn("scramble"), "tier 2 opens at 2 points")
	game.learn("t_snap_down")
	game.learn("sprawl")
	game.learn("t_uchi_mata")
	check(game.knows("uchi_mata"), "talent unlocks technique")
	for i in 10:
		game.raise_attr("grip")
	check(game.attr("grip") == 15 and game.unlocked.has("peak"), "attributes raise + Peak Physique")
	check(not game.raise_attr("grip"), "no attribute points left")
	game.reset_talents()
	check(game.talent_points() == 6 and not game.knows("uchi_mata"), "reset refunds talents")
	# every style produces sane modifiers and wider takedowns for the wrestler
	var neutral := RollSim.new()
	neutral.setup("tiago", 2.0, func(_id): return true, 7)
	var w0: float = neutral.timing_params("double_leg").width
	for st in Rpg.STYLE_ORDER:
		var a := {}
		for k in Rpg.ATTR_ORDER:
			a[k] = Rpg.ATTR_BASE + int(Rpg.STYLES[st].attrs.get(k, 0))
		var m := Rpg.build_mods(st, a, {})
		var sm := RollSim.new()
		sm.setup("tiago", 2.0, func(_id): return true, 7, m)
		var w: float = sm.timing_params("double_leg").width
		check(w > 0.05 and w <= 0.5 and sm.max_stamina >= 100.0, "%s mods sane (td zone %.3f, stam %.0f)" % [st, w, sm.max_stamina])
		if st == "wrestler":
			check(w > w0 * 1.2, "wrestler takedown window wider (%.3f vs %.3f)" % [w, w0])
		if st == "guard":
			check(sm.player_cost("pull_guard") == 0.0, "guard player pulls guard for free")
		if st == "athlete":
			check(sm.max_stamina > 110.0, "athlete has more stamina")
	var sw := RollSim.new()
	sw.setup("rafa", 1.0, func(_id): return true, 3, Rpg.build_mods("", {}, {"second_wind": 1}))
	sw.spend(85)
	check(sw.stamina > 40.0 and sw.second_wind_used, "second wind fires once (stamina %.0f)" % sw.stamina)
	sw.spend(30)
	sw.spend(30)
	check(sw.stamina < 20.0, "second wind does not fire twice")
	var sc := RollSim.new()
	sc.setup("rafa", 1.0, func(_id): return true, 3, Rpg.build_mods("", {}, {"scramble": 1}))
	check(sc.counter_chance("double_leg") == 0.0 and sc.counter_chance("triangle") > 0.0, "scramble blocks takedown counters only")
	var onca := RollSim.new()
	onca.setup("onca", 3.0, func(_id): return true, 3)
	onca.pos = "half"
	onca.player_top = false
	check("darce" in onca.opp_options(), "boss uses talent techniques (D'Arce)")
	# every talent technique exists and every talent tree is reachable
	for tid in Rpg.TALENTS:
		var t: Dictionary = Rpg.TALENTS[tid]
		if t.has("move"):
			check(Data.MOVES.has(t.move), "talent %s move exists" % tid)
	for st in Rpg.STYLES:
		for mid in Rpg.STYLES[st].signature:
			check(Data.MOVES.has(mid), "%s signature %s exists" % [st, mid])
	# ---------------- belts, zones, drills
	game.reset()
	game.add_xp(450)
	check(game.rank == 4 and game.at_stripe_cap(), "white belt caps at 4 stripes (rank %d)" % game.rank)
	game.promote_belt(1)
	check(game.rank == 5 and game.stripe_xp == 0, "promotion to blue resets stripe progress")
	game.add_xp(250)
	check(game.rank == 7, "blue belt earns stripes from XP (rank %d)" % game.rank)
	game.add_xp(2000)
	check(game.rank == 9, "blue belt caps at 4 stripes (rank %d)" % game.rank)
	game.record_roll("jacare", {"won": true, "by_sub": false, "min_stamina": 10.0})
	check(game.rank == 10 and game.unlocked.has("purple_belt"), "Mestre Jacaré promotes to purple")
	for id in data.OPPONENTS:
		var z: String = data.zone_of(id)
		check(data.ZONES.has(z), "%s in a valid zone" % id)
		var o: Dictionary = data.OPPONENTS[id]
		for mid in o.get("extra", []):
			check(data.MOVES.has(mid), "%s extra move %s exists" % [id, mid])
	for z in data.ZONES:
		check(data.COLLECTIBLES.has(z) and data.landmarks_in(z).size() == 6, "zone %s has collectibles + 6 landmarks" % z)
		var boss: String = data.ZONES[z].boss
		check(data.OPPONENTS[boss].get("boss", false) and data.zone_of(boss) == z, "zone %s boss %s" % [z, boss])
	game.reset()
	check(game.collect_cup(0, "pantanal") and game.collected_count("pantanal") == 1 and game.collected_count("caceres") == 0, "collectibles tracked per zone")
	var base_flex: int = game.attr("flexibility")
	for i in 3:
		game.complete_drill("flexibility")
	check(game.attr("flexibility") == base_flex + 1, "3 drills = +1 attribute")
	for i in 30:
		game.complete_drill("flexibility")
	check(game.train_bonus("flexibility") == game.TRAIN_CAP, "drill bonus caps at %d" % game.TRAIN_CAP)
	check(game.unlocked.has("drills"), "Drill Sergeant achievement")
	game.zone = "pantanal"
	check(game.current_objective().contains("Pantanal"), "pantanal objective: " + game.current_objective())
	# ---------------- chapada + daily
	game.reset()
	game.promote_belt(2)
	game.record_roll("cachoeira", {"won": true, "by_sub": true, "sub": "rnc", "min_stamina": 50.0})
	check(game.rank == 15 and game.unlocked.has("brown_belt"), "Mestre Cachoeira promotes to brown (rank %d)" % game.rank)
	var d1: Dictionary = data.daily_challenge("2026-11-07", 5)
	var d2: Dictionary = data.daily_challenge("2026-11-07", 5)
	var d3: Dictionary = data.daily_challenge("2026-11-08", 5)
	check(d1.rule == d2.rule and d1.opp.name == d2.opp.name, "daily challenge is the same for everyone on a date")
	check(data.DAILY_RULES.has(d1.rule) and data.DAILY_RULES.has(d3.rule), "daily rules valid")
	for rname in data.DAILY_RULES:
		var sm := RollSim.new()
		sm.setup("daily", 3.0, func(_id): return true, 5, {}, d1.opp)
		sm.apply_rule(rname)
		check(not sm.player_options().is_empty() or not sm.opp_options().is_empty(), "rule %s leaves moves available (%s top=%s)" % [rname, sm.pos, sm.player_top])
	var so := RollSim.new()
	so.setup("daily", 3.0, func(_id): return true, 5, {}, d1.opp)
	so.apply_rule("sub_only")
	so.player_pts = 20
	so.finish_on_points()
	check(not so.result.won, "submission-only: points don't win")
	game.reset()
	game.record_daily({"won": true, "by_sub": true}, "2026-11-05")
	game.record_daily({"won": true, "by_sub": false}, "2026-11-06")
	var g3 = game.record_daily({"won": true, "by_sub": false}, "2026-11-07")
	check(int(game.daily.streak) == 3 and game.unlocked.has("daily_3"), "3-day streak (streak %d)" % int(game.daily.streak))
	check(g3 > 150, "streak boosts daily XP (%d)" % g3)
	var g4 = game.record_daily({"won": true, "by_sub": false}, "2026-11-07")
	check(g4 == 20 and int(game.daily.streak) == 3, "replaying the same day gives practice XP only")
	game.record_daily({"won": true, "by_sub": false}, "2026-11-09")
	check(int(game.daily.streak) == 1, "missing a day resets the streak")
	check(game.yesterday_of("2026-03-01") == "2026-02-28", "date math across months")
	print("\n%s (%d failures)" % ["PASS" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
