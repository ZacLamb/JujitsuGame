extends Node
## Finds clear corridors on each zone's west / east edge for walkable zone lines.
func _ready() -> void:
	for z in ["caceres", "pantanal", "chapada", "rio", "texas", "everglades", "sedona", "socal"]:
		var w := World.new()
		add_child(w)
		w.build(z)
		var out := []
		for s in [-1, 1]:
			var best := 999.0
			var best_z := 0.0
			for zc in range(-60, 61, 2):
				var bad := 0.0
				for x in range(60, 96, 3):
					for dz in [-6, -3, 0, 3, 6]:
						var px := float(s * x)
						var pz := float(zc + dz)
						if w._is_blocked(px, pz, 0.5):
							bad += 1.0
						if w._raw_height(px, pz) < w.water_level() + 0.1:
							bad += 0.5
				var score: float = bad * 10.0 + absf(zc) * 0.05
				if score < best:
					best = score
					best_z = zc
			out.append([s, best_z, best])
		print("ROAD ", z, " ", out)
		w.free()
	get_tree().quit()
