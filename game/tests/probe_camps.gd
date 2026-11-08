extends Node
## Prints terrain info at candidate camp positions per zone.
const CANDS := {
	"pantanal": [Vector3(40, 0, 30), Vector3(-50, 0, 40), Vector3(10, 0, -60), Vector3(-30, 0, -20), Vector3(70, 0, -10), Vector3(-60, 0, -50)],
	"chapada": [Vector3(-20, 0, 30), Vector3(40, 0, -30), Vector3(-60, 0, -40), Vector3(60, 0, 10), Vector3(0, 0, -60), Vector3(-50, 0, 60)],
	"rio": [Vector3(-30, 0, 50), Vector3(40, 0, 50), Vector3(-70, 0, -20), Vector3(60, 0, -40), Vector3(-80, 0, 40), Vector3(10, 0, -60)],
}
func _ready() -> void:
	Game.test_mode = true
	for z in CANDS:
		var w := World.new()
		add_child(w)
		w.build(z)
		for p in CANDS[z]:
			var ys: Array = []
			for d in [Vector2(0, 0), Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]:
				ys.append(snappedf(w.ground_y(p.x + d.x, p.z + d.y), 0.1))
			print(z, " ", p, " y=", ys, " blocked=", w._is_blocked(p.x, p.z, 3.0))
		w.queue_free()
		await get_tree().process_frame
	get_tree().quit()
