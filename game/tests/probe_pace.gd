extends Node
func _ready() -> void:
	Game.test_mode = true
	var bal = load("res://tests/test_balance.gd").new()
	var aud = load("res://tests/audit_core.gd").new()
	for lv in [2, 6, 12, 20]:
		bal._build("wrestler", lv)
		for pol in ["expert", "mash"]:
			var t := 0.0
			var w := 0.0
			for sd in 8:
				var r: Dictionary = aud._fight(lv, [{"name": "Mob", "level": (lv - 1) * 0.55 / 2.0 + 1.0, "style": "balanced", "rank": Game.rank}], 100 + sd, pol, "mob")
				t += float(r.t)
				w += float(r.won)
			print("L%d %s: %.0fs avg, won %d/8" % [lv, pol, t / 8.0, w])
	get_tree().quit()
