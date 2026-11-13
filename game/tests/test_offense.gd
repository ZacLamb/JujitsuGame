extends Node
## Offense depth: skill XP, flow chains, opponents reading your habits, rivals remembering you.
var fails := 0
var cnt := {}

func _ev(ev: Dictionary) -> void:
	cnt[str(ev.t)] = int(cnt.get(str(ev.t), 0)) + 1

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", msg)

func _ready() -> void:
	Game.test_mode = true
	# --- skill XP: a clean S pays more than a sloppy C, and both are >= 0
	var s := WorldCombat.skill_bonus({"xp": 100, "grade": "S", "best_streak": 5, "chains": 2, "reads": 4, "caught": 0, "whiffs": 0})
	var c := WorldCombat.skill_bonus({"xp": 100, "grade": "C", "best_streak": 0, "chains": 0, "reads": 0, "caught": 3, "whiffs": 2})
	print("skill bonus S=%d C=%d" % [s, c])
	check(s >= 80 and c == 0, "skill bonus S=%d C=%d" % [s, c])
	# --- read back
	var bal = load("res://tests/test_balance.gd").new()
	bal._build("guard", 8)
	for seed_v in 30:
		var core := CombatCore.new()
		core.rng.seed = seed_v
		var me := core.add_player("You", 8, Game.mods(), Abilities.player_kit())
		me.known = Abilities.known_moves()
		var e := core.add_enemy({"name": "Mob", "level": 4.85, "style": "balanced", "rank": Game.rank}, "mob")
		e.pos = Vector3(1, 0, 0)
		core.engage(me, e)
		core.engage(e, me)
		me.target = e
		e.ai_t = 999.0   # hold still: we're testing the player's side
		core.event.connect(_ev)
		# takedown, then pass twice: the second pass may be expected
		core.use(me, "takedown")
		me.gcd = 0.0
		me.cds.clear()
		me.gas = me.max_gas
		e.auras.erase("down")
		e.gpos = "guard"
		e.ptop = true
		for i in 3:
			if e.has("expect"):
				var ex := str(e.auras.expect.type)
				if seed_v % 2 == 0:
					core.use(me, ex)          # walk into it
				else:
					me.grip = 3
					for alt in CombatCore.READ_BACK_TYPES:
						if alt != ex and core.block_reason(me, core.ability(me, alt), e) == "":
							core.use(me, alt)
							break
			else:
				core.use(me, "pass")
			me.gcd = 0.0
			me.cds.clear()
			me.gas = me.max_gas
			me.auras.erase("down")
			e.gpos = "guard"
			e.ptop = true
	var seen_expect: int = cnt.get("expect", 0)
	var stuffed: int = cnt.get("stuffed", 0)
	var switched: int = cnt.get("switch", 0)
	print("expects %d stuffed %d switches %d flow chains %d" % [seen_expect, stuffed, switched, cnt.get("chain", 0)])
	check(seen_expect >= 5, "mobs at L8 never read a repeated technique")
	check(stuffed >= 2, "walking into an expected technique wasn't stuffed")
	check(switched >= 2, "switching away from an expected technique didn't count")
	# a level-3 player isn't read by normal mobs
	var core2 := CombatCore.new()
	var me2 := core2.add_player("You", 3, Game.mods(), Abilities.player_kit())
	var e2 := core2.add_enemy({"name": "Mob", "level": 2.0, "style": "balanced", "rank": 0}, "mob")
	check(core2.read_back_chance(e2, me2) == 0.0, "normal mobs read a level 3 player")
	# --- flow: climbing builds it, the sub spends it
	var core3 := CombatCore.new()
	var me3 := core3.add_player("You", 8, Game.mods(), Abilities.player_kit())
	me3.known = Abilities.known_moves()
	var e3 := core3.add_enemy({"name": "Mob", "level": 4.85, "style": "balanced", "rank": Game.rank}, "mob")
	e3.pos = Vector3(1, 0, 0)
	core3.engage(me3, e3)
	me3.target = e3
	e3.ai_t = 999.0
	core3.use(me3, "takedown")
	me3.gcd = 0.0
	me3.cds.clear()
	for alt in ["pass", "advance", "back"]:
		if core3.use(me3, alt) == "":
			break
	print("flow after takedown+climb: ", me3.auras.get("flow", {}).get("n", 0), " pos ", e3.gpos)
	check(me3.has("flow") and int(me3.auras.flow.n) >= 2, "takedown -> climb didn't build flow x2")
	# --- rival memory
	check(WorldCombat.rival_fav({"pass": 4.0, "takedown": 1.0, "_rolls": 2}) == "pass", "rival didn't pick the favourite")
	check(WorldCombat.rival_fav({"pass": 1.0, "takedown": 1.0, "sweep": 1.0}) == "", "rival read a habit that isn't there")
	# --- jiu-jitsu rules
	for mv in Data.MOVES:
		var m: Dictionary = Data.MOVES[mv]
		check(str(m.pos) in ["standing", "guard", "half", "side", "mount", "back"], "%s: bad position" % mv)
		if str(m.type) == "takedown":
			check(str(m.pos) == "standing", "%s: a takedown that isn't from standing" % mv)
		if str(m.type) in ["sweep", "escape"] and str(m.pos) != "standing":
			check(str(m.role) == "bottom", "%s: a sweep / escape from the top" % mv)
		if str(m.type) in ["pass", "advance"]:
			check(str(m.role) == "top", "%s: a pass from the bottom" % mv)
		if str(m.pos) in ["side", "mount", "back"] and str(m.role) == "bottom":
			check(str(m.type) in ["escape", "sweep"], "%s: attacking from under %s" % [mv, m.pos])
	for st in ["wrestler", "judoka", "guard", "athlete", "passer", "pressure", "submission", "back", "balanced"]:
		for a in Abilities.enemy_kit({"style": st}, false, false):
			var nm := str(a.name)
			for bad in ["Sweep", "Triangle", "Americana", "Rear Naked", "Knee Cut", "Collar Choke", "Ankle Lock"]:
				check(not nm.contains(bad) or nm.contains("Standing"), "%s enemy standing kit has %s" % [st, nm])
	# no-gi: nobody reaches for a collar
	var core4 := CombatCore.new()
	core4.gi = false
	var me4 := core4.add_player("You", 20, Game.mods(), Abilities.player_kit())
	var e4 := core4.add_enemy({"name": "Mob", "level": 10.0, "style": "judoka", "rank": 30}, "mob")
	core4.engage(e4, me4)
	for pos in ["mount", "side", "back"]:
		e4.gpos = pos
		e4.ptop = false
		e4.grip = 3
		for i in 60:
			check(not core4._ai_move(e4, me4) in Data.GI_ONLY, "enemy used a gi choke in no-gi")
	print("PASS (0 failures)" if fails == 0 else "FAILED (%d failures)" % fails)
	get_tree().quit()
