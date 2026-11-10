extends Node
## Guards the core fight loop (see tests/audit_core.gd for the full sweep). Fails if:
##  * spamming 1 can win (the finish must be a submission you choose to go for)
##  * an expert reader doesn't win reliably, or ends no healthier than a masher
##  * a win ends any other way than a submission
##  * enemies don't attempt enough techniques to read
const LEVELS := [1, 4, 8]
const N := 6
var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", msg)

func _ready() -> void:
	Game.test_mode = true
	var bal = load("res://tests/test_balance.gd").new()
	var aud = load("res://tests/audit_core.gd").new()
	for lvl in LEVELS:
		bal._build("guard", lvl)
		var cl: float = 1.0 + (lvl - 1) * 0.55 / 2.0
		var mob := {"name": "Mob", "level": cl, "style": "balanced", "rank": Game.rank}
		var res := {}
		for pol in ["spam1", "mash", "expert"]:
			var agg := {}
			for s in N:
				var r: Dictionary = aud._fight(lvl, [mob], 500 + s, pol)
				for k in r:
					agg[k] = float(agg.get(k, 0.0)) + float(r[k])
			res[pol] = agg
		var sp: Dictionary = res.spam1
		var ma: Dictionary = res.mash
		var ex: Dictionary = res.expert
		print("L%d  spam1 %d/%d  mash %d/%d hp%d%%  expert %d/%d hp%d%%  casts %.1f" % [lvl, sp.won, N, ma.won, N, 100.0 * ma.hp / N, ex.won, N, 100.0 * ex.hp / N, ex.e_casts / N])
		check(sp.won == 0.0, "L%d: spamming 1 won a fight" % lvl)
		check(ex.won >= N - 1, "L%d: expert won only %d/%d" % [lvl, ex.won, N])
		check(ex.hp > ma.hp, "L%d: expert not healthier than a masher" % lvl)
		check(ex.sub_kill >= ex.won and ma.sub_kill >= ma.won, "L%d: a win that wasn't a submission" % lvl)
		check(ex.e_casts / N >= 1.5 and ma.e_casts / N >= 2.0, "L%d: too few enemy techniques to read" % lvl)
	print("PASS (0 failures)" if fails == 0 else "FAILED (%d failures)" % fails)
	get_tree().quit()
