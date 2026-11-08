class_name RollBot
extends RefCounted
## A modelled human driving the player side of a RollSim: reaction time, counter accuracy, pacing,
## patience with grips, baiting, mashing. Used by the balance harness and to simulate team bouts.

const SKILLS := {
	# rt: reaction to an opponent cast (mean, sd); acc: picks the right counter; react: bothers to
	# answer; apm: actions per second when free; spend: grips before committing; tps: struggle taps
	# per second; bait: grips first when the AI's counter is ready; breathe: stamina % to breathe at
	"casual": {"rt": [0.85, 0.25], "acc": 0.65, "react": 0.5, "apm": 0.9, "spend": 1, "tps": 5.0, "bait": 0.1, "breathe": 0.0},
	"average": {"rt": [0.65, 0.18], "acc": 0.8, "react": 0.72, "apm": 1.4, "spend": 2, "tps": 7.0, "bait": 0.4, "breathe": 25.0},
	"skilled": {"rt": [0.45, 0.12], "acc": 0.94, "react": 0.9, "apm": 2.2, "spend": 3, "tps": 9.0, "bait": 0.8, "breathe": 28.0},
}

var sk: Dictionary
var rng := RandomNumberGenerator.new()
var _think := 0.0
var _react_at := -1.0
var _seen := {}
var _tap := 0.0

func _init(skill := "average", seed_value := -1) -> void:
	sk = SKILLS[skill] if SKILLS.has(skill) else skill_between(0.5)
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

## A skill blend: 0 = casual, 0.5 = average, 1 = skilled.
static func skill_between(t: float) -> Dictionary:
	var a: Dictionary = SKILLS.casual if t < 0.5 else SKILLS.average
	var b: Dictionary = SKILLS.average if t < 0.5 else SKILLS.skilled
	var k := clampf(t * 2.0 if t < 0.5 else (t - 0.5) * 2.0, 0.0, 1.0)
	var out := {}
	for key in a:
		if key == "rt":
			out[key] = [lerpf(a.rt[0], b.rt[0], k), lerpf(a.rt[1], b.rt[1], k)]
		elif key == "spend":
			out[key] = int(round(lerpf(a.spend, b.spend, k)))
		else:
			out[key] = lerpf(float(a[key]), float(b[key]), k)
	return out

static func with_skill(d: Dictionary) -> RollBot:
	var b := RollBot.new()
	b.sk = d
	return b

## Advances the bot by dt (call after sim.tick(dt)).
func step(sim: RollSim, dt: float) -> void:
	if sim.over:
		return
	if not sim.struggle.is_empty():
		_tap += float(sk.tps) * dt * rng.randf_range(0.8, 1.2)
		while _tap >= 1.0 and not sim.struggle.is_empty():
			_tap -= 1.0
			sim.tap()
		return
	if not sim.opp_cast.is_empty():
		if sim.opp_cast != _seen:
			_seen = sim.opp_cast
			var worth: bool = sim.opp_cast.kind == "move" or rng.randf() < 0.15
			_react_at = maxf(0.12, rng.randfn(float(sk.rt[0]), float(sk.rt[1]))) if worth and rng.randf() < float(sk.react) else -1.0
		if _react_at >= 0.0 and float(sim.opp_cast.t) >= _react_at:
			_react_at = -1.0
			var need := RollSim.counter_kind(sim.opp_cast.id)
			var k := need if need != "grip" else "frame"
			if rng.randf() > float(sk.acc):
				k = ["base", "frame", "defend"][rng.randi() % 3]
			sim.defend(k)
		return
	_think -= dt
	if _think > 0.0:
		return
	_think = rng.randf_range(0.6, 1.4) / float(sk.apm)
	if float(sk.breathe) > 0.0 and sim.stamina_pct() < float(sk.breathe) and sim.cooldown("breathe") <= 0.0:
		sim.breathe()
		return
	var best := ""
	var best_s := -1.0
	for slot in sim.player_bar():
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

## Plays a whole match headless. Returns sim.result.
func play(sim: RollSim, dt := 0.05) -> Dictionary:
	sim.start_live()
	var guard := 0
	while not sim.over and guard < 20000:
		guard += 1
		sim.tick(dt)
		sim.events.clear()
		step(sim, dt)
	if not sim.over:
		sim.finish_on_points()
	return sim.result
