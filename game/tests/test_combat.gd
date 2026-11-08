extends Node
## Headless balance check for CombatCore: a simple rotation vs normal / elite / two mobs.
func _rotate(core: CombatCore, me: CombatCore.Unit) -> void:
	if me.down():
		core.use(me, "escape")
		return
	var t := me.target
	if t and not t.cast.is_empty() and t.cast.ab.get("finisher", false):
		core.use(me, "frame")
	if me.pct() < 0.35:
		core.use(me, "base")
	for id in ["sub", "advance", "takedown", "pass", "back", "sweep", "spec", "handfight"]:
		if id == "sub" and me.grip < 4 and (t == null or t.pct() > 0.25):
			continue
		if core.use(me, id) == "":
			return

func _fight(level: int, mobs: Array) -> Dictionary:
	var core := CombatCore.new()
	core.rng.seed = 7
	var me := core.add_player("You", level, Game.mods(), Abilities.player_kit())
	var es: Array = []
	for m in mobs:
		var u := core.add_enemy(m, "mob")
		u.pos = Vector3(1.0, 0, 0)
		core.engage(u, me)
		es.append(u)
	me.target = es[0]
	if false:
		core.event.connect(func(e):
			if str(e.t) == "dmg":
				print("  dmg %s -> %s %s %d%s hp=%d/%d" % [e.u.name, e.target.name, str(e.ab.get("name", "")), int(e.amount), "!" if e.crit else "", int(e.target.hp), int(e.target.max_hp)]))
	var t := 0.0
	while t < 120.0:
		core.tick(0.05)
		t += 0.05
		if me.dead:
			break
		var alive := es.filter(func(u): return not u.dead)
		if alive.is_empty():
			break
		if me.target == null or me.target.dead:
			me.target = alive[0]
		_rotate(core, me)
	return {"t": snappedf(t, 0.1), "won": not me.dead, "hp": int(me.pct() * 100)}

func _ready() -> void:
	Game.test_mode = true
	Game.reset()
	Game.choose_style("wrestler", "T", 0)
	Game.set_level(5)
	var kit := Abilities.player_kit()
	print("KIT ", kit.map(func(a): return "%s:%s" % [a.get("key", "-"), a.get("name", "-")]))
	var lv := 1.0 + (5 - 1) * 0.55 / 2.0
	var mob := {"name": "Mob", "level": lv, "style": "wrestler"}
	var elite := {"name": "Elite", "level": lv, "style": "passer", "elite": true}
	var rare := {"name": "Rare", "level": lv + 0.3, "style": "guard", "elite": true, "rare": true}
	print("normal   ", _fight(5, [mob]))
	print("two      ", _fight(5, [mob, mob]))
	print("three    ", _fight(5, [mob, mob, mob]))
	print("elite    ", _fight(5, [elite]))
	print("rare     ", _fight(5, [rare]))
	# rules
	var core := CombatCore.new()
	var me := core.add_player("You", 5, Game.mods(), Abilities.player_kit())
	var e := core.add_enemy(mob, "mob")
	e.pos = Vector3(10, 0, 0)
	me.target = e
	print("range: ", core.use(me, "handfight"), " | sub no grip: ", core.block_reason(me, core.ability(me, "sub"), e))
	e.pos = Vector3(1, 0, 0)
	print("advance no control: ", core.block_reason(me, core.ability(me, "advance"), e))
	get_tree().quit()
