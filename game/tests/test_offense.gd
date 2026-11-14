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
	# --- distance on the feet: step out of range and the shot misses; run in and shoot for momentum
	var core5 := CombatCore.new()
	core5.rng.seed = 5
	var me5 := core5.add_player("You", 8, Game.mods(), Abilities.player_kit())
	me5.known = Abilities.known_moves()
	var e5 := core5.add_enemy({"name": "Mob", "level": 4.85, "style": "wrestler", "rank": Game.rank}, "mob")
	e5.pos = Vector3(1.5, 0, 0)
	core5.engage(e5, me5)
	core5.engage(me5, e5)
	me5.target = e5
	cnt = {}
	core5.event.connect(_ev)
	var hp0 := me5.hp
	var slipped := false
	for i in 400:
		core5.tick(0.05)
		if not e5.cast.is_empty() and str(e5.cast.ab.get("type", "")) == "takedown":
			me5.pos = Vector3(-6.0, 0, 0)        # back out of reach while it's coming
			slipped = true
		elif slipped and e5.cast.is_empty():
			break
	print("slip events %d, lunge %d, pos %s" % [cnt.get("slip", 0), e5.lunge, e5.gpos])
	check(int(cnt.get("slip", 0)) >= 1 and e5.gpos == "standing", "stepping out of range didn't make the takedown miss")
	check(e5.lunge >= 1, "a slipped shot didn't extend their next reach")
	var core6 := CombatCore.new()
	var me6 := core6.add_player("You", 8, Game.mods(), Abilities.player_kit())
	me6.known = Abilities.known_moves()
	var e6 := core6.add_enemy({"name": "Mob", "level": 4.85, "style": "balanced", "rank": Game.rank}, "mob")
	e6.pos = Vector3(8.0, 0, 0)
	e6.ai_t = 999.0
	me6.target = e6
	core6.engage(me6, e6)
	cnt = {}
	core6.event.connect(_ev)
	for i in 30:
		me6.pos.x += 0.2            # 4 m/s toward them
		core6.tick(0.05)
	core6.use(me6, "takedown")
	print("approach %.1f m/s, momentum events %d" % [me6.approach, cnt.get("momentum", 0)])
	check(int(cnt.get("momentum", 0)) == 1, "running in and shooting didn't give momentum")
	# --- zone bosses: the signature fires, phase two happens, a good reader still wins
	var aud = load("res://tests/audit_core.gd").new()
	bal._build("guard", 10)
	var o: Dictionary = Data.OPPONENTS["onca"].duplicate()
	o["boss_id"] = "onca"
	var bw := {"expert": 0.0, "mash": 0.0}
	var sigs := 0.0
	var phases := 0.0
	var bt := 0.0
	for pol in ["expert", "mash"]:
		for sd in 8:
			cnt = {}
			var r: Dictionary = aud._fight(10, [o], 900 + sd, pol, "boss")
			bw[pol] += float(r.won)
			if pol == "expert":
				bt += float(r.t)
				sigs += float(r.get("sigs", 0.0))
				phases += float(r.get("phases", 0.0))
	print("boss onca L10: expert %d/8 mash %d/8, signatures %.1f/fight, phase two in %d/8, %.0fs" % [bw.expert, bw.mash, sigs / 8.0, phases, bt / 8.0])
	check(bw.expert >= 6, "an expert reader can't beat the zone boss")
	check(bw.mash <= bw.expert, "mashing beats the boss as well as reading")
	check(sigs >= 8, "the boss signature rarely fires")
	check(phases >= 6, "phase two rarely happens")
	_rotation(bal)
	# --- rested XP: time away banks XP, rolls spend it for double
	bal._build("guard", 8)
	Game.rested = 0
	Game.accrue_rest(int(Time.get_unix_time_from_system()) - 6 * 3600)
	var need := Game.xp_level_need()
	check(absi(Game.rested - need / 2) <= 2 and Game.rest_note == Game.rested, "6h away banked %d of a %d level" % [Game.rested, need])
	Game.accrue_rest(int(Time.get_unix_time_from_system()) - 400 * 3600)
	check(Game.rested == Game.rest_cap(), "rested didn't cap")
	Game.rested = 20
	var x0 := Game.xp
	var m := Game.xp_mult()
	Game.add_xp(30, true)
	check(Game.xp - x0 == int(round(30 * m)) + 20 and Game.rested == 0, "rested bonus wrong: +%d xp, %d left" % [Game.xp - x0, Game.rested])
	x0 = Game.xp
	Game.rested = 50
	Game.add_xp(30)
	check(Game.xp - x0 == int(round(30 * m)) and Game.rested == 50, "quest XP spent rested")
	Game.rested = 0
	print("PASS (0 failures)" if fails == 0 else "FAILED (%d failures)" % fails)
	get_tree().quit()

## One fresh fight for a style: the player, a tough standing mob that holds still.
func _setup(bal, style: String, lvl := 12) -> Array:
	bal._build(style, lvl)
	var core := CombatCore.new()
	core.rng.seed = 7
	var me := core.add_player("You", lvl, Game.mods(), Abilities.player_kit())
	me.known = Abilities.known_moves()
	var e := core.add_enemy({"name": "Mob", "level": lvl + 4, "style": "balanced", "rank": Game.rank}, "elite")
	e.pos = Vector3(1, 0, 0)
	e.ai_t = 999.0
	me.target = e
	core.engage(me, e)
	core.engage(e, me)
	cnt = {}
	core.event.connect(_ev)
	return [core, me, e]

func _ready_up(me: CombatCore.Unit) -> void:
	me.gcd = 0.0
	me.gas = me.max_gas

## Procs, bursts and the five styles.
func _rotation(bal) -> void:
	# --- Opening: Hand Fight finds it, the next takedown is free and off cooldown
	var f := _setup(bal, "passer")
	var core: CombatCore = f[0]
	var me: CombatCore.Unit = f[1]
	var e: CombatCore.Unit = f[2]
	check(not core.ability(me, "burst").is_empty(), "no burst ability at level 12")
	core.opening_chance = 0.0
	core.use(me, "takedown")
	e.auras.erase("down")
	core.stand_up(e)
	check(float(me.cds.get("takedown", 0.0)) > 5.0, "takedown has no cooldown to reset")
	_ready_up(me)
	core.opening_chance = 1.0
	core.use(me, "handfight")
	check(me.has("opening") and not me.cds.has("takedown"), "hand fight didn't open them up / reset the takedown")
	_ready_up(me)
	check(core.cost_of(me, core.ability(me, "takedown")) == 0.0, "the opening technique isn't free")
	e.auras.erase("expect")
	core.use(me, "takedown")
	check(not me.has("opening") and me.gas == me.max_gas, "the opening wasn't spent by the takedown")
	print("opening: procs %d" % int(cnt.get("opening", 0)))
	# --- passer: Crush builds grip under the pin; Dead Weight pins and exposes
	core.opening_chance = 0.0
	me.grip = 0
	core._aura(e, "pinned", 20.0, me)
	for i in 70:
		core.tick(0.1)
	check(me.grip >= 2, "Crush gave %d grip in 7s of pin" % me.grip)
	e.auras.erase("pinned")
	_ready_up(me)
	check(core.use(me, "burst") == "", "Dead Weight couldn't be used")
	check(e.has("pinned") and e.has("exposed") and float(me.cds.get("burst", 0.0)) > 80.0, "Dead Weight didn't pin and expose")
	# --- wrestler: a correct sprawl resets the takedown; Relentless removes cooldowns
	f = _setup(bal, "wrestler")
	core = f[0]; me = f[1]; e = f[2]
	core.opening_chance = 0.0
	core.use(me, "takedown")
	e.auras.erase("down")
	core.stand_up(e)
	check(me.cds.has("takedown"), "wrestler takedown has no cooldown")
	var td: Dictionary = core.ability(e, "e_take")
	e.cast = {"ab": td, "t": 0.0, "dur": 1.4, "target": me}
	me.cds.erase("base")
	core.use(me, "base")
	check(not me.cds.has("takedown") and me.has("reshoot"), "a correct sprawl didn't reset the takedown")
	_ready_up(me)
	core.use(me, "burst")
	check(me.has("relentless"), "Relentless didn't start")
	e.auras.erase("down")
	e.auras.erase("expect")
	core.use(me, "takedown")
	check(not me.cds.has("takedown") and me.gas == me.max_gas, "Relentless takedown still cost gas or went on cooldown")
	# --- judoka: Kuzushi stacks, the throw spends it; Ippon is a certain crit
	f = _setup(bal, "judoka")
	core = f[0]; me = f[1]; e = f[2]
	core.opening_chance = 0.0
	for i in 3:
		_ready_up(me)
		core.use(me, "handfight")
	check(e.has("kuzushi") and int(e.auras.kuzushi.n) == 3, "Kuzushi didn't stack to 3")
	_ready_up(me)
	core.use(me, "burst")
	check(me.has("ippon"), "Ippon didn't start")
	var hp0 := e.hp
	_ready_up(me)
	e.auras.erase("expect")
	core.use(me, "takedown")
	check(not e.has("kuzushi") and not me.has("ippon") and float(e.auras.get("down", {}).get("t", 0.0)) > 3.0, "the throw didn't spend Kuzushi / Ippon")
	print("judoka: ippon throw hit %d of %d" % [int(hp0 - e.hp), int(e.max_hp)])
	# --- athlete: Tempo speeds the global cooldown; Overdrive is free
	f = _setup(bal, "athlete")
	core = f[0]; me = f[1]; e = f[2]
	core.opening_chance = 0.0
	var h0 := core.haste(me)
	for i in 5:
		_ready_up(me)
		core.use(me, "handfight")
	check(me.has("tempo") and int(me.auras.tempo.n) == 5 and core.haste(me) > h0 * 1.19, "Tempo didn't stack")
	_ready_up(me)
	core.use(me, "burst")
	_ready_up(me)
	core.use(me, "handfight")
	check(me.has("overdrive") and me.gas == me.max_gas, "Overdrive hand fight cost gas")
	# --- guard: sweeps build more grip; Spider Web slows their techniques
	f = _setup(bal, "guard")
	core = f[0]; me = f[1]; e = f[2]
	core.opening_chance = 0.0
	core.use(me, "burst")
	check(me.has("web"), "Spider Web didn't start")
	td = core.ability(e, "e_take")
	e.cast = {"ab": td, "t": 0.0, "dur": 1.4, "target": me}
	for i in 14:
		core.tick(0.1)
	check(not e.cast.is_empty(), "Spider Web didn't slow their takedown")
	bal._build("guard", 8)
