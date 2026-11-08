extends Node
## Difficulty harness: plays thousands of headless matches with modelled human players
## and prints win rates per opponent. Run: godot --headless tests/balance.tscn
## It follows the same exchange flow as RollScene (initiative, choose, timing bar, defend, struggle).

const SKILLS := RollBot.SKILLS
## Typical progress when a player reaches each zone: belt rank for regulars / boss, RPG level.
const ZONE_PLAYER := {"caceres": [2, 4, 3], "pantanal": [7, 9, 6], "chapada": [12, 14, 9], "rio": [17, 19, 12]}
const N := 240

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
const DT := 0.05

func _play(o: Dictionary, prow: Dictionary, skill: Dictionary) -> bool:
	sim = RollSim.new()
	sim.setup("bal", Data.rank_level(prow.rank), _knows, rng.randi(), prow.mods, o)
	sim.signature = Rpg.STYLES[prow.style].signature
	var bot := RollBot.with_skill(skill)
	bot.rng.seed = rng.randi()
	return bool(bot.play(sim, DT).won)
