extends Node
## Core-loop audit: plays thousands of fights with different kinds of player and measures what makes
## a fight feel good or bad. Policies:
##   spam1     only ever presses 1 (the filler)
##   mash      presses whatever button is ready, left to right, never counters
##   rotation  a sensible priority list (escape when down, sub at 3+ grip, breathe when low), no counters
##   wrongctr  rotation + counters every cast, but with a random counter key (doesn't read the bar)
##   expert    rotation + the right counter for every cast after a 0.35s reaction
## Run: godot --headless tests/audit_core.tscn   (env AUDIT_LV="3,8,15", AUDIT_N=40)
const POLICIES := ["spam1", "mash", "mashall", "rotation", "wrongctr", "expert"]
const BAR := ["handfight", "takedown", "sub", "pass", "escape", "sweep", "back", "guard", "advance", "spec"]
const PRIO := ["sub", "spec", "advance", "back", "takedown", "pass", "sweep", "escape", "handfight"]
const APM_STEP := 0.2   # a human presses at most ~5 buttons a second

var bal: Node

func _ready() -> void:
	Game.test_mode = true
	bal = load("res://tests/test_balance.gd").new()
	var lvs: Array = []
	for x in OS.get_environment("AUDIT_LV").split(",", false):
		lvs.append(int(x))
	if lvs.is_empty():
		lvs = [2, 5, 10, 20]
	var n := int(OS.get_environment("AUDIT_N")) if OS.get_environment("AUDIT_N") != "" else 30
	var styles: Array = OS.get_environment("AUDIT_STYLES").split(",", false) if OS.get_environment("AUDIT_STYLES") != "" else ["guard", "wrestler", "passer"]
	for lvl in lvs:
		for style in styles:
			bal._build(style, lvl)
			var cl: float = 1.0 + (lvl - 1) * 0.55 / 2.0
			var mob := {"name": "Mob", "level": cl, "style": "balanced", "rank": Game.rank}
			var elite := {"name": "Elite", "level": cl, "style": "pressure", "elite": true, "rank": Game.rank}
			print("\n=== %s L%d (known moves %d, kit %s)" % [style, lvl, Abilities.known_moves().size(), ",".join(Abilities.player_kit().map(func(a): return str(a.id)))])
			for scen in [["mob", [mob]], ["elite", [elite]], ["two", [mob, mob]]]:
				for pol in POLICIES:
					var agg := {}
					for s in n:
						var r := _fight(lvl, scen[1], 1000 + s, pol)
						for k in r:
							agg[k] = float(agg.get(k, 0.0)) + float(r[k])
					var line := "%-6s %-9s" % [scen[0], pol]
					line += " win %3d%%" % int(100.0 * agg.won / n)
					line += " | %4.1fs" % (agg.t / n)
					line += " | hp left %3d%%" % int(100.0 * agg.hp / n)
					line += " | dmg auto %2d%%" % int(100.0 * agg.auto_dmg / maxf(1.0, agg.my_dmg))
					line += " | enemy casts %4.1f/fight" % (agg.e_casts / n)
					line += " (countered %2d%%)" % int(100.0 * agg.countered / maxf(1.0, agg.e_casts))
					line += " | pos changes %4.1f" % (agg.pos_changes / n)
					line += " | presses %4.1f (blocked-by-pos %2d%%)" % [agg.presses / n, int(100.0 * agg.pos_blocked / maxf(1.0, agg.attempts))]
					line += " | idle %2d%%" % int(100.0 * agg.idle / maxf(1.0, agg.ticks))
					line += " | taps by sub %2d%%" % int(100.0 * agg.sub_kill / maxf(1.0, agg.won))
					line += " | down %4.1fs" % (agg.down_t / n)
					line += " | stuffed %.1f switch %.1f chains %.1f" % [float(agg.get("stuffed", 0.0)) / n, float(agg.get("switches", 0.0)) / n, float(agg.get("chains", 0.0)) / n]
					print(line)
	get_tree().quit()

func _fight(lvl: int, foes: Array, seed_v: int, pol: String, kind := "mob") -> Dictionary:
	var core := CombatCore.new()
	core.rng.seed = seed_v
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 31 + pol.hash()
	var me := core.add_player("You", lvl, Game.mods(), Abilities.player_kit())
	me.known = Abilities.known_moves()
	var es: Array = []
	for f in foes:
		var u := core.add_enemy(f, kind)
		u.pos = Vector3(1.0, 0, 0)
		es.append(u)
	core.engage(me, es[0])
	for u in es:
		core.engage(u, me)
	me.target = es[0]
	var st := {"won": 0.0, "t": 0.0, "hp": 0.0, "auto_dmg": 0.0, "my_dmg": 0.0, "e_casts": 0.0, "countered": 0.0,
		"pos_changes": 0.0, "presses": 0.0, "attempts": 0.0, "pos_blocked": 0.0, "idle": 0.0, "ticks": 0.0, "sub_kill": 0.0, "down_t": 0.0}
	core.event.connect(_on_ev.bind(st, me))
	var t := 0.0
	var next_press := 0.0
	while t < 180.0:
		core.tick(0.05)
		t += 0.05
		st.ticks += 1
		if me.down():
			st.down_t += 0.05
		if me.dead:
			break
		var alive := es.filter(func(u): return not u.dead)
		if alive.is_empty():
			break
		if me.target == null or me.target.dead:
			me.target = alive[0]
		# idle: nothing on the bar is usable right now (gcd aside)
		var any := false
		for a in me.abilities:
			var why := core.block_reason(me, a, me.target)
			if why == "" and str(a.id) in BAR:
				any = true
				break
		if not any and me.gcd <= 0.0 and me.cast.is_empty():
			st.idle += 1
		if t < next_press:
			continue
		next_press = t + APM_STEP
		_act(core, me, rng, pol, st)
	st.t = t
	st.won = 1.0 if not me.dead and t < 180.0 else 0.0
	st.hp = me.pct() if st.won > 0 else 0.0
	return st

func _on_ev(e: Dictionary, st: Dictionary, me) -> void:
	match str(e.t):
		"dmg":
			if e.u == me:
				st.my_dmg += float(e.amount)
				if str(e.ab.get("id", "")) == "auto":
					st.auto_dmg += float(e.amount)
		"cast":
			if e.u != me:
				st.e_casts += 1
		"interrupt":
			if e.u == me:
				st.countered += 1
		"position":
			st.pos_changes += 1
		"stuffed":
			st["stuffed"] = float(st.get("stuffed", 0.0)) + 1.0
		"switch":
			st["switches"] = float(st.get("switches", 0.0)) + 1.0
		"chain":
			st["chains"] = float(st.get("chains", 0.0)) + 1.0
		"tap":
			if e.by == me and str(e.get("sub", "")) != "":
				st.sub_kill += 1
		"struggle":
			if not e.on:
				var mine: bool = e.u == me
				st["struggles"] = float(st.get("struggles", 0.0)) + 1.0
				if mine and not e.tapped:
					st["escaped_from_me"] = float(st.get("escaped_from_me", 0.0)) + 1.0
				if not mine and not e.tapped:
					st["i_escaped"] = float(st.get("i_escaped", 0.0)) + 1.0

func _try(core: CombatCore, me, id: String, st: Dictionary) -> bool:
	var a := core.ability(me, id)
	if a.is_empty():
		return false
	st.attempts += 1
	var why := core.use(me, id)
	if why == "":
		st.presses += 1
		return true
	if why.begins_with("Not from"):
		st.pos_blocked += 1
	return false

func _counter(core: CombatCore, me, rng: RandomNumberGenerator, pol: String, st: Dictionary) -> bool:
	var t = me.target
	for e in core.engaged_enemies():
		if not e.cast.is_empty() and float(e.cast.t) > 0.35 and not e.cast.has("_seen"):
			e.cast["_seen"] = true
			var kind := CombatCore.counter_kind(e.cast.ab)
			if pol == "wrongctr":
				kind = ["base", "frame", "defend"][rng.randi() % 3]
			me.target = e
			var ok := _try(core, me, kind, st)
			me.target = t
			return ok
	return false

func _act(core: CombatCore, me, rng: RandomNumberGenerator, pol: String, st: Dictionary) -> void:
	if core.in_struggle(me):
		# the finish: everyone but the 1-spammer mashes (one press per input step)
		if pol != "spam1":
			core.struggle_press(me)
			st["struggle_presses"] = float(st.get("struggle_presses", 0.0)) + 1.0
		return
	match pol:
		"spam1":
			_try(core, me, "handfight", st)
		"mash", "mashall":
			var ids := BAR.duplicate()
			if pol == "mashall":
				ids.append_array(["base", "frame", "defend", "base", "frame", "defend"])
			ids.shuffle()
			for id in ids:
				if _try(core, me, id, st):
					return
		_:
			if pol in ["expert", "wrongctr"] and _counter(core, me, rng, pol, st):
				return
			if me.down():
				_try(core, me, "escape", st)
				return
			if me.pct() < 0.4 and _try(core, me, "breathe", st):
				return
			for id in PRIO:
				if pol == "expert" and me.target != null and me.target.has("expect") and str(me.target.auras.expect.get("type", "")) == id and not (id == "sub" and me.target.has("worn")):
					continue   # they're waiting for it: switch it up
				if id == "sub" and me.grip < 3 and (me.target == null or me.target.pct() > 0.3):
					continue
				if _try(core, me, id, st):
					return
