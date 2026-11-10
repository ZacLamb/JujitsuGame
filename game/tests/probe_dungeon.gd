extends Node
## Runs a Group Finder dungeon end to end (headless is fine): -- <dungeon id> <level>
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0] if args.size() > 0 else "night"
	var lv: int = int(args[1]) if args.size() > 1 else 24
	Game.test_mode = true
	Game.reset()
	Game.set_identity("texan", "male", 0.4)
	Game.choose_style("passer", "Tex", 0)
	Game.set_level(lv)
	_typical("passer", lv)
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game()
	main.hud._close_dialogue(false)
	main.hud.toggle_finder(main)
	await get_tree().process_frame
	print("finder open=", main.hud.finder != null)
	main.start_dungeon(id)
	var c = main.combat
	var t := 0.0
	var last_stage := -1
	var t0 := Time.get_ticks_msec()
	c.raid_warning.connect(func(h, sb): print("  [", (Time.get_ticks_msec() - t0) / 1000, "s] ", h, " · ", sb))
	var res := {"won": ""}
	main.combat.raid_over.connect(func(w): res.won = "WON" if w else "WIPED")
	var won := ""
	while won == "" and t < 400.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		won = res.won
		var r = c.raid
		if r == null:
			break
		if r.stage != last_stage:
			last_stage = r.stage
			print("  stage ", r.stage, " boss=", r.boss != null, " t=", int(t), " me=", int(c.me.hp))
		if r.boss == null and int(t * 4) % 80 == 0:
			for n in r.trash_npcs:
				if is_instance_valid(n):
					var u = c._unit_of.get(n.get_instance_id())
					if u:
						print("    trash ", u.name, " hp=", int(u.hp), "/", int(u.max_hp), " ic=", u.in_combat, " dead=", u.dead, " d=", snappedf(c.core.dist(u, c.me), 0.1), " tgt=", u.target.name if u.target else "-", " gpos=", u.gpos)
					else:
						print("    trash npc w/o unit ", n.mob.get("name"))
			print("    target=", c.target.name if c.target else "-", " me.ic=", c.me.in_combat)
		if r.boss and int(t * 4) % 12 == 0:
			var al := ""
			for an in r.ally_npcs:
				var au = c._unit_of.get(an.get_instance_id()) if is_instance_valid(an) else null
				al += " %s:%s" % [an.mob.name if is_instance_valid(an) else "?", str(int(au.pct() * 100)) if au else "out"]
			print("    t=", int(t), " boss ", int(r.boss.pct() * 100), "%  me ", int(c.me.pct() * 100), "% gas ", int(c.me.gas), " |", al, " adds=", r.add_npcs.size())
		# a decent player: counter the boss's casts, then fight
		if r.boss and not r.boss.cast.is_empty():
			var ab_id := str(r.boss.cast.ab.get("id", ""))
			if ab_id == "wave":
				c.press("base")
			elif ab_id == "second_breath":
				c.target = r.boss
				c.press("frame")
			elif ab_id == "hidden_choke":
				c.press("defend")
		if c.me.pct() < 0.35:
			c.press("breathe")
		for k in Game.bar_layout:
			if str(k) != "":
				c.press(str(k))
		if c.target == null or c.target.dead:
			c._auto_target()
	won = res.won
	print("RESULT ", id, " lv", lv, ": ", won, " after ", int(t), "s  me=", int(c.me.hp), "/", int(c.me.max_hp), " unlocked=", Game.unlocked.has("dng_" + id))
	get_tree().quit()

## Same "typical character" as tests/test_balance.gd: attributes, spec, talents, named gear.
func _typical(style: String, lvl: int) -> void:
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
	for pass_n in 30:
		var any := false
		for tr in ["class", "spec"]:
			for nd in TalentTrees.tree(tr, Game.spec):
				if Game.can_learn(str(nd.id)):
					Game.learn(str(nd.id))
					any = true
		if not any:
			break
	for id in Gear.ITEMS:
		if Gear.ilvl(id) <= lvl and not Gear.ITEMS[id].get("rolled", false) and Gear.ITEMS[id].get("faction", "") in ["", Game.faction()]:
			Game.give_item(id, true)
