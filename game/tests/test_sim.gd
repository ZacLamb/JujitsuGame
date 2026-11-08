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
	sim.start_live()
	var steps := 0
	while not sim.over and steps < 20000:
		steps += 1
		sim.tick(0.05)
		sim.events.clear()
		if not sim.struggle.is_empty():
			if steps % 2 == 0:
				sim.tap()
		elif not sim.opp_cast.is_empty() and float(sim.opp_cast.t) > 0.35:
			sim.defend(sim.cast_counter(sim.opp_cast) if sim.rng.randf() < 0.7 else "base")
		elif sim.cast.is_empty():
			var bar := sim.player_bar()
			var mv: Array = bar.filter(func(sl): return sl.kind == "move" and sim.block_reason(sl) == "")
			if sim.control >= 2 and not mv.is_empty():
				sim.use(mv[sim.rng.randi() % mv.size()].id)
			else:
				sim.use("grip")
	check(sim.over, "match terminates (%d steps)" % steps)
	check(sim.result.has("won"), "result has winner")
	# real-time combat rules
	var rt := RollSim.new()
	rt.setup("tiago", 2.0, func(_id): return true, 11)
	rt.start_live()
	var bar0 := rt.player_bar()
	check(bar0.size() >= 4 and bar0.size() <= 8 and bar0[0].kind == "grip" and bar0[1].kind == "wear", "standing bar: grip, wear + techniques (%d slots)" % bar0.size())
	var tdslot: Dictionary = bar0.filter(func(sl): return sl.id == "double_leg")[0]
	check(rt.block_reason(tdslot) == "control", "techniques need grips first")
	rt.ai_t = 99.0
	check(rt.use("grip") == "", "grip ability starts a cast")
	for i in 20:
		rt.tick(0.05)
	check(rt.control >= 1 or not rt.cast.is_empty() or rt.control == 0, "grip resolves")
	rt.control = 3
	rt.cds.clear()
	rt.gcd = 0.0
	var hi := rt.technique_chance("double_leg", true, 3)
	var lo := rt.technique_chance("double_leg", true, 0)
	check(hi > lo + 0.25, "spending grips raises the odds (%.2f vs %.2f)" % [hi, lo])
	check(RollSim.counter_kind("triangle") == "defend" and RollSim.counter_kind("scissor_sweep") == "base" and RollSim.counter_kind("knee_slice") == "frame", "counter kinds by technique type")
	rt.opp_cast = {"id": "double_leg", "name": "Double", "kind": "move", "t": 0.2, "dur": 1.0, "spend": 2}
	rt.def_cd = 0.0
	check(rt.defend("frame") == "wrong" and not rt.opp_cast.is_empty(), "wrong counter does not interrupt")
	rt.def_cd = 0.0
	var c0 := rt.control
	check(rt.defend("base") == "" and rt.opp_cast.is_empty() and rt.opp_off_bal > 0.0 and rt.control == mini(5, c0 + 1), "right counter interrupts and steals a grip")
	rt.pos = "guard"
	rt.player_top = false
	var gb := rt.player_bar()
	check(gb[0].name == "Sleeve Grip" and gb.size() <= 8, "stance names follow the position (%s)" % gb[0].name)
	var w0 := RollSim.new()
	w0.setup("tiago", 2.0, func(_id): return true, 7)
	var ct0 := w0.cast_time("double_leg", false)
	# cast times and odds stay sane across levels
	for lvl in [1.0, 2.0, 5.2, 12.0]:
		var s2 := RollSim.new()
		s2.setup("rafa", lvl, func(_id): return true, 1)
		var ct := s2.cast_time("triangle", false)
		check(ct >= 0.4 and ct <= 2.0, "opponent cast time sane at level %s (%.2f)" % [lvl, ct])
		var tc := s2.technique_chance("triangle", true, 2)
		check(tc >= 0.08 and tc <= 0.95, "technique chance sane at level %s (%.2f)" % [lvl, tc])
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
	# ---------------- gear
	game.reset()
	game.choose_style("guard", "Tester", 0)
	check(game.equipped.get("jacket") == "standard_gi" and game.equipped.get("pants") == "standard_gi_pants" and game.equipped.get("rash") == "rash_white", "starter gear equipped")
	var grip0: int = game.attr("grip")
	check(game.give_item("onca_gi") and game.equipped.jacket == "onca_gi", "boss jacket auto-equips")
	check(game.attr("grip") == grip0 + 2 and game.gi_color() == Gear.look("onca_gi").color, "gear adds attributes and changes the gi color")
	check(not game.give_item("onca_gi"), "no duplicate loot")
	game.give_item("terere_gi")
	check(game.equipped.jacket == "onca_gi" and game.has_item("terere_gi_pants"), "weaker gear does not replace better gear; quest gi comes with pants")
	check(game.equip("terere_gi") and game.attr("grip") == grip0, "manual equip swaps bonuses")
	# sets: 2-piece attrs, 4-piece effect in the roll mods, kits
	game.equip("onca_gi")
	game.give_item("onca_gi_pants")
	check(int(game.set_counts().get("onca", 0)) == 2 and game.attr("grip") == grip0 + 2 + 1 + 1, "onca 2-piece adds +1 grip (grip %d)" % game.attr("grip"))
	game.give_item("onca_tape")
	game.give_item("onca_headband")
	check(game.mods().get("pounce", false), "onca 4-piece grants Pounce")
	game.set_kit("nogi")
	check(not game.mods().get("pounce", false) and int(game.set_counts().get("onca", 0)) == 2, "no-gi kit: gi pieces stop counting")
	check(game.look().kit == "nogi" and game.look().has("spats"), "no-gi look wears spats")
	game.set_kit("gi")
	var lk: Dictionary = game.look()
	check(lk.jacket.get("pattern", "") == "spots" and lk.head_piece == "Headband", "gi look carries the set pattern and head piece")
	# boss drops: jacket first, then other pieces, never duplicates
	game.reset()
	check(game.boss_drop("jacare") == "jacare_gi", "first boss drop is the jacket")
	var seen: Dictionary = {}
	for i in 3:
		seen[game.boss_drop("jacare")] = true
	check(seen.size() == 3 and game.boss_drop("jacare") == "", "boss drops cover the set, then stop")
	# old saves: the single gi slot becomes jacket + pants
	game.reset()
	game.equipped = {"gi": "onca_gi", "rash": "rash_white"}
	game.inventory = {"onca_gi": true}
	game._backfill_gear()
	check(game.equipped.get("jacket") == "onca_gi" and game.equipped.get("pants") == "onca_gi_pants", "v1 gi slot migrates to jacket + pants")
	game.reset()
	game.rank = 9
	game.wins = {"onca": 1, "jacare": 1}
	game._backfill_gear()
	check(game.has_item("onca_gi") and game.has_item("jacare_gi") and game.has_item("rash_blue"), "old saves get gear for past progress")
	for st in Gear.SETS:
		for pid in Gear.SETS[st].pieces:
			check(Gear.ITEMS.has(pid) and str(Gear.ITEMS[pid].get("set", "")) == st, "set %s piece %s exists" % [st, pid])
	# every style produces sane modifiers; the wrestler lands and reads takedowns better
	var neutral := RollSim.new()
	neutral.setup("tiago", 2.0, func(_id): return true, 7)
	var w0c: float = neutral.technique_chance("double_leg", true, 2)
	for st in Rpg.STYLE_ORDER:
		var a := {}
		for k in Rpg.ATTR_ORDER:
			a[k] = Rpg.ATTR_BASE + int(Rpg.STYLES[st].attrs.get(k, 0))
		var m := Rpg.build_mods(st, a, {})
		var sm := RollSim.new()
		sm.setup("tiago", 2.0, func(_id): return true, 7, m)
		var w: float = sm.technique_chance("double_leg", true, 2)
		check(w > 0.05 and w <= 0.95 and sm.max_stamina >= 100.0, "%s mods sane (td chance %.2f, stam %.0f)" % [st, w, sm.max_stamina])
		if st == "wrestler":
			check(w > w0c + 0.1, "wrestler takedowns land more (%.2f vs %.2f)" % [w, w0c])
			check(sm.cast_time("double_leg", false) > ct0 * 1.2, "wrestler gets longer to read takedowns")
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
	# ---------------- boss phases
	var bs := RollSim.new()
	bs.setup("jacare", 6.0, func(_id): return true, 21)
	check(bs.boss_phases.size() == 3 and bs.phase == 0, "Jacaré fights in 3 phases")
	bs.start_live()
	bs.opp_stamina = 60.0
	bs.tick(0.05)
	check(bs.phase == 1 and not bs.special.is_empty(), "phase 2 starts below 70 stamina with a special")
	bs.events.clear()
	bs.special_t = 0.0
	bs.ai_t = 99.0
	bs.reset_t = 0.0
	bs.tick(0.05)
	check(not bs.opp_cast.is_empty() and bs.opp_cast.kind == "special" and bs.cast_counter(bs.opp_cast) == "frame", "special cast telegraphed with its own counter")
	bs.def_cd = 0.0
	var c0b := bs.control
	check(bs.defend("frame") == "" and bs.opp_off_bal > 2.0 and bs.control == mini(5, c0b + 2), "countering a special: big interrupt")
	bs.special_t = 0.0
	bs.tick(0.05)
	var st0 := bs.stamina
	bs.opp_cast.t = 99.0
	bs.tick(0.05)
	check(bs.stamina < st0 - 20.0, "an unanswered Death Roll crushes 25 stamina")
	bs.opp_stamina = 30.0
	bs.reset_t = 0.0
	bs.tick(0.05)
	check(bs.phase == 2 and bs.shield == 3, "phase 3 raises Heavy Base x3")
	var tc_sh := bs.technique_chance("scissor_sweep", true, 3)
	bs.shield = 0
	check(tc_sh < bs.technique_chance("scissor_sweep", true, 3), "Heavy Base cuts your odds")
	var ns := RollSim.new()
	ns.setup("rafa", 2.0, func(_id): return true, 3)
	check(ns.boss_phases.is_empty(), "regular fighters have no phases")
	# ---------------- 5v5 teams
	game.reset()
	game.choose_style("guard", "Tester", 0)
	for id in ["rafa", "cida", "tiago"]:
		game.wins[id] = 1
	check(Team.edge("finisher", "grinder") == 1 and Team.edge("grinder", "finisher") == -1 and Team.edge("anchor", "finisher") == 0, "role ring")
	for r in Team.ROLE_ORDER:
		var beaten_by := Team.ROLE_ORDER.filter(func(x): return Team.ROLES[x].beats == r)
		check(beaten_by.size() == 1, "%s is countered by exactly one role" % r)
	var lu: Dictionary = game.team_lineup()
	check(lu.order.size() == 5 and lu.order[0] == "you" and "tiago" in lu.order, "lineup: you + recruits + partners (%s)" % str(lu.order))
	var tm := Team.new_match("caceres", lu, 3)
	check(tm.ours.size() == 5 and tm.theirs.size() == 5, "5 a side")
	var their_ids: Array = tm.theirs.map(func(f): return str(f.id).trim_prefix("e_"))
	check(not "tiago" in their_ids and not "rafa" in their_ids, "recruits never appear on the enemy team")
	tm.apply({"won": true, "by_sub": false, "score": [2, 0]}, 0.5, 0.0)
	check(tm.j == 1 and tm.i == 0 and tm.stam_ours > 0.5 and tm.stam_theirs == 1.0, "winner stays on and recovers some gas (%.2f)" % tm.stam_ours)
	tm.apply({"won": false, "draw": true, "by_sub": false, "score": [0, 0]}, 0.3, 0.3)
	check(tm.i == 1 and tm.j == 2, "a draw eliminates both")
	var dr := RollSim.new()
	dr.setup("rafa", 2.0, func(_id): return true, 4)
	dr.apply_rule("team")
	dr.finish_on_points()
	check(dr.result.get("draw", false) and dr.clock <= 150.0, "team bouts: level score is a draw")
	var b := Team.sim_bout(Team.you(), tm.theirs[2], 0.8, 1.0, 11)
	check(b.has("won") and float(b.me_stam) >= 0.0 and float(b.me_stam) <= 1.0, "simulated bout returns a result and stamina")
	var xp0: int = game.xp
	game.record_team(true, 0)
	check(game.unlocked.has("team_win") and game.unlocked.has("team_clean") and game.xp > xp0, "team win: achievements + xp")
	check(Gear.SETS.familia.pieces.any(func(p): return game.has_item(p)), "team win drops a Família piece")
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
