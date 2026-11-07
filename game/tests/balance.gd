extends Node
## Difficulty harness: plays thousands of headless matches with modelled human players
## and prints win rates per opponent. Run: godot --headless tests/balance.tscn
## It follows the same exchange flow as RollScene (initiative, choose, timing bar, defend, struggle).

const SKILLS := {
	# choose: seconds to pick a move; sigma: timing error (seconds); rt: defense reaction (mean, sd);
	# acc: correct arrow; tps: taps per second in struggles; smart: 0 random .. 1 optimal picks
	"casual": {"choose": 2.6, "sigma": 0.13, "rt": [0.78, 0.22], "acc": 0.84, "tps": 5.0, "smart": 0.15, "breathe": 0.0},
	"average": {"choose": 1.8, "sigma": 0.09, "rt": [0.62, 0.17], "acc": 0.92, "tps": 7.0, "smart": 0.55, "breathe": 28.0},
	"skilled": {"choose": 1.1, "sigma": 0.06, "rt": [0.48, 0.12], "acc": 0.97, "tps": 9.0, "smart": 0.9, "breathe": 30.0},
}
## Typical progress when a player reaches each zone: belt rank for regulars / boss, RPG level.
const ZONE_PLAYER := {"caceres": [2, 4, 3], "pantanal": [7, 9, 6], "chapada": [12, 14, 9], "rio": [17, 19, 12]}
const N := 160

var rng := RandomNumberGenerator.new()
var sim: RollSim
var sk: Dictionary

func _ready() -> void:
	rng.seed = 99
	Game.test_mode = true
	var only := OS.get_cmdline_user_args()
	var csv: Array[String] = ["zone,opponent,boss,opp_level,player_level,casual,average,skilled"]
	for z in ["caceres", "pantanal", "chapada", "rio"]:
		print("\n== %s ==" % z)
		for id in Data.OPPONENTS:
			if Data.zone_of(id) != z:
				continue
			var o: Dictionary = Data.OPPONENTS[id]
			var boss: bool = o.get("boss", false)
			var prow := _player_for(z, boss)
			var line := "%-11s L%5.2f vs P%5.2f " % [id, float(o.level), Data.rank_level(prow.rank)]
			var row := "%s,%s,%s,%.2f,%.2f" % [z, id, boss, float(o.level), Data.rank_level(prow.rank)]
			for s in ["casual", "average", "skilled"]:
				var w := 0
				for i in N:
					if _play(o, prow, SKILLS[s]):
						w += 1
				line += " %s %3d%%" % [s.substr(0, 3), int(100.0 * w / N)]
				row += ",%d" % int(100.0 * w / N)
			print(line, "  BOSS" if boss else "")
			csv.append(row)
	var f := FileAccess.open("user://balance.csv", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(csv))
		print("\ncsv: ", ProjectSettings.globalize_path("user://balance.csv"))
	get_tree().quit()

func _player_for(z: String, boss: bool) -> Dictionary:
	var zp: Array = ZONE_PLAYER[z]
	var r: int = zp[1] if boss else zp[0]
	Game.reset()
	Game.style = ["guard", "passer", "wrestler", "judoka", "athlete"][rng.randi() % 5]
	Game.rank = r
	# spend attribute points evenly on the style's two best attributes
	var pts := Game.attr_points()
	var keys: Array = Rpg.STYLES[Game.style].attrs.keys()
	if keys.is_empty():
		keys = Rpg.ATTR_ORDER.slice(0, 2)
	for i in pts:
		var k: String = keys[i % mini(2, keys.size())]
		Game.attr_alloc[k] = int(Game.attr_alloc.get(k, 0)) + 1
	return {"rank": r, "mods": Game.mods(), "style": Game.style}

func _knows(id: String) -> bool:
	return Game.knows(id)

# ------------------------------------------------------------------ one match
func _play(o: Dictionary, prow: Dictionary, skill: Dictionary) -> bool:
	sk = skill
	sim = RollSim.new()
	sim.setup("bal", Data.rank_level(prow.rank), _knows, rng.randi(), prow.mods, o)
	var guard := 0
	while not sim.over and guard < 400:
		guard += 1
		if not sim.opp_options().is_empty() and sim.rng.randf() < sim.opp_initiative_chance():
			_defend()
		else:
			_choose()
	if not sim.over:
		sim.finish_on_points()
	return bool(sim.result.won)

func _tick(t: float, regen := false) -> void:
	sim.tick(t)
	if regen:
		sim.regen_tick(t)

func _gauss(m: float, sd: float) -> float:
	return rng.randfn(m, sd)

func _choose() -> void:
	if sim.over:
		return
	var t := maxf(0.4, _gauss(float(sk.choose), float(sk.choose) * 0.3))
	var win := sim.decision_window()
	if t > win:
		_tick(win, true)
		_defend()
		return
	_tick(t, true)
	if float(sk.breathe) > 0.0 and sim.stamina_pct() < float(sk.breathe):
		sim.recover(24)
		if sim.rng.randf() < 0.5:
			_defend()
		return
	var opts := sim.player_options()
	if opts.is_empty():
		_defend()
		return
	var id := _pick(opts)
	_tick(_gauss(1.3, 0.3))
	var p := sim.timing_params(id)
	var err := absf(_gauss(0.0, float(sk.sigma) * float(p.speed)))
	var j := sim.judge_timing(p, float(p.center) + err)
	if j == "perfect":
		sim.recover(6)
	if j == "miss":
		sim.failed_attempt(id, true)
		if sim.rng.randf() < sim.counter_chance(id):
			_defend()
		return
	var r := sim.apply_move(id, true)
	if r.sub:
		_struggle(true, id)

func _pick(opts: Array) -> String:
	if rng.randf() > float(sk.smart):
		return opts[rng.randi() % opts.size()]
	var best := ""
	var bs := -INF
	for id in opts:
		var m: Dictionary = Data.MOVES[id]
		var score := float(m.pts) * 1.0 - float(m.diff) * 0.8
		if m.type == "sub":
			score = 3.5 if (sim.player_top and sim.pos in ["mount", "back", "side"]) else 1.0
			score -= float(m.diff) * 0.6
		if m.type in ["escape", "guard"] and not sim.player_top:
			score += 1.5
		score += rng.randf() * 0.8
		if score > bs:
			bs = score
			best = id
	return best

func _defend() -> void:
	if sim.over:
		return
	var ai := sim.ai_pick_move()
	if ai == "":
		return
	var win := sim.defense_window(ai)
	var rt := maxf(0.2, _gauss(float(sk.rt[0]), float(sk.rt[1])))
	_tick(minf(rt, win))
	if rt <= win and rng.randf() < float(sk.acc):
		sim.spend(4)
		sim.failed_attempt(ai, false)
		if rt < win * 0.4:
			_choose()
		return
	sim.spend(6)
	var r := sim.apply_move(ai, false)
	if r.sub:
		_struggle(false, ai)

func _struggle(attacking: bool, sub_id: String) -> void:
	var p := sim.struggle_params(attacking, sub_id)
	var s := float(p.start)
	var t := 0.0
	var dt := 0.05
	var tps := maxf(2.0, _gauss(float(sk.tps), 1.0))
	while true:
		t += dt
		s -= float(p.decay) * dt
		s = minf(1.0, s + float(p.gain) * tps * dt)
		sim.spend(0.6 * tps * dt)
		sim.tick(dt)
		if attacking:
			if s >= 1.0:
				sim.finish_by_sub(true, sub_id)
				return
			if s <= 0.0 or t >= float(p.limit):
				sim.failed_attempt(sub_id, true)
				return
		else:
			if s >= 1.0:
				sim.failed_attempt(sub_id, false)
				return
			if s <= 0.0:
				sim.finish_by_sub(false, sub_id)
				return
			if t >= float(p.limit):
				if s >= 0.5:
					sim.failed_attempt(sub_id, false)
				else:
					sim.finish_by_sub(false, sub_id)
				return
