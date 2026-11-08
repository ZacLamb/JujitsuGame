extends Node
## Difficulty harness: plays thousands of headless matches with modelled human players
## and prints win rates per opponent. Run: godot --headless tests/balance.tscn
## It follows the same exchange flow as RollScene (initiative, choose, timing bar, defend, struggle).

const SKILLS := {
	# rt: reaction to an opponent cast (mean, sd); acc: picks the right counter; apm: actions per second
	# when free; spend: grips they wait for before a technique (0 = spams); tps: struggle taps per second;
	# bait: chance to grip first when the AI's counter is ready; breathe: stamina % that makes them breathe
	"casual": {"rt": [0.85, 0.25], "acc": 0.65, "react": 0.5, "apm": 0.9, "spend": 1, "tps": 5.0, "bait": 0.1, "breathe": 0.0},
	"average": {"rt": [0.65, 0.18], "acc": 0.8, "react": 0.72, "apm": 1.4, "spend": 2, "tps": 7.0, "bait": 0.4, "breathe": 25.0},
	"skilled": {"rt": [0.45, 0.12], "acc": 0.94, "react": 0.9, "apm": 2.2, "spend": 3, "tps": 9.0, "bait": 0.8, "breathe": 28.0},
}
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
	sk = skill
	sim = RollSim.new()
	sim.setup("bal", Data.rank_level(prow.rank), _knows, rng.randi(), prow.mods, o)
	sim.signature = Rpg.STYLES[prow.style].signature
	sim.start_live()
	var think := 0.0
	var react_at := -1.0     # when the bot will answer the current opponent cast
	var seen_cast := {}
	var tap_acc := 0.0
	var guard := 0
	while not sim.over and guard < 20000:
		guard += 1
		sim.tick(DT)
		sim.events.clear()
		if sim.over:
			break
		if not sim.struggle.is_empty():
			tap_acc += float(sk.tps) * DT * rng.randf_range(0.8, 1.2)
			while tap_acc >= 1.0 and not sim.struggle.is_empty():
				tap_acc -= 1.0
				sim.tap()
			continue
		# defend
		if not sim.opp_cast.is_empty():
			if sim.opp_cast != seen_cast:
				seen_cast = sim.opp_cast
				var worth: bool = sim.opp_cast.kind == "move" or rng.randf() < 0.15
				react_at = maxf(0.12, rng.randfn(float(sk.rt[0]), float(sk.rt[1]))) if worth and rng.randf() < float(sk.react) else -1.0
			if react_at >= 0.0 and float(sim.opp_cast.t) >= react_at:
				react_at = -1.0
				var need := RollSim.counter_kind(sim.opp_cast.id)
				var k := need if need != "grip" else "frame"
				if rng.randf() > float(sk.acc):
					k = ["base", "frame", "defend"][rng.randi() % 3]
				sim.defend(k)
			continue
		# act
		think -= DT
		if think > 0.0:
			continue
		think = rng.randf_range(0.6, 1.4) / float(sk.apm)
		if float(sk.breathe) > 0.0 and sim.stamina_pct() < float(sk.breathe) and sim.cooldown("breathe") <= 0.0:
			sim.breathe()
			continue
		var bar := sim.player_bar()
		var best := ""
		var best_s := -1.0
		for slot in bar:
			if slot.kind != "move" or sim.block_reason(slot) != "":
				continue
			var m: Dictionary = Data.MOVES[slot.id]
			var sc := rng.randf()
			if m.type == "sub":
				sc += 0.6 if sim.player_top and sim.pos in ["mount", "back", "side"] else 0.2
			if m.type in ["escape", "guard"] and not sim.player_top:
				sc += 0.5
			if sc > best_s:
				best_s = sc
				best = slot.id
		var want := int(sk.spend)
		if best != "" and (sim.control >= want or sim.control >= RollSim.MAX_CONTROL) and not (sim.opp_counter_cd <= 0.0 and rng.randf() < float(sk.bait) and sim.control < RollSim.MAX_CONTROL):
			sim.use(best)
		elif sim.use("grip") != "":
			sim.use("wear")
	if not sim.over:
		sim.finish_on_points()
	return bool(sim.result.won)
