extends Node
func _ready() -> void:
	Game.test_mode = true
	var bal = load("res://tests/test_balance.gd").new()
	var aud = load("res://tests/audit_core.gd").new()
	for row in [[12, 12], [12, 6], [12, 2], [30, 30], [30, 20], [30, 10], [60, 60], [60, 40], [60, 10]]:
		var lv: int = row[0]
		var ml: int = row[1]
		bal._build("wrestler", lv)
		var t := 0.0
		var w := 0.0
		var hp := 0.0
		for sd in 8:
			var r: Dictionary = aud._fight(lv, [{"name": "Mob", "level": (ml - 1) * 0.55 / 2.0 + 1.0, "style": "balanced", "rank": Game.rank}], 100 + sd, "expert", "mob")
			t += float(r.t)
			w += float(r.won)
			hp += float(r.hp)
		print("player L%d vs mob L%d: %.0fs avg, won %d/8, hp left %.0f%%" % [lv, ml, t / 8.0, w, 100.0 * hp / 8.0])
	get_tree().quit()
