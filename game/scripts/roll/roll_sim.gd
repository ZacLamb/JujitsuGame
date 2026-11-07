class_name RollSim
extends RefCounted
## Pure match logic for a roll (no nodes) so it can be unit-tested headless.

const MATCH_SECONDS := 240.0  # displayed clock (4:00)
const CLOCK_SPEED := 2.4      # displayed seconds per real second

var rng := RandomNumberGenerator.new()
var opp_id := ""
var opp: Dictionary
var player_level := 1.0
var opp_level := 1.0
var known_moves: Callable  # func(move_id) -> bool
var mods: Dictionary = {}
var max_stamina := 100.0
var second_wind_used := false
var second_wind_fired := false  # set when it triggers; the UI clears it after announcing

var pos := "standing"
var player_top := true
var player_pts := 0
var opp_pts := 0
var player_adv := 0
var opp_adv := 0
var stamina := 100.0
var opp_stamina := 100.0
var min_stamina := 100.0
var clock := MATCH_SECONDS
var over := false
var result := {}
var log_lines: Array = []

var rule := ""  # daily challenge rule

func setup(opponent_id: String, p_level: float, knows: Callable, seed_value := -1, player_mods: Dictionary = {}, opp_override: Dictionary = {}) -> void:
	mods = player_mods if not player_mods.is_empty() else Rpg.neutral_mods()
	max_stamina = float(mods.stamina_max)
	stamina = max_stamina
	min_stamina = max_stamina
	opp_id = opponent_id
	opp = opp_override if not opp_override.is_empty() else Data.OPPONENTS[opponent_id]
	opp_level = float(opp.level)
	player_level = p_level
	known_moves = knows
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

# ------------------------------------------------------------ queries
func player_options() -> Array:
	var out: Array = []
	for id in Data.moves_for(pos, player_top):
		if known_moves.call(id):
			out.append(id)
	return out

func opp_options() -> Array:
	var out: Array = []
	for id in Data.moves_for(pos, not player_top):
		if int(Data.MOVES[id].rank) <= int(opp.rank) + 2 or id in opp.get("extra", []):
			out.append(id)
	return out

func stamina_factor(s: float) -> float:
	return 0.6 if s < 25.0 else 1.0

## Stamina as a percentage of max (for the low-stamina rule and Iron Lungs).
func stamina_pct() -> float:
	return 100.0 * stamina / max_stamina

func zone_bonus(move_id: String) -> float:
	var m: Dictionary = Data.MOVES[move_id]
	var b := float(mods.zone.get(m.type, 0.0))
	b += float(mods.zone_role.get(m.role, 0.0))
	b += float(mods.zone_move.get(move_id, 0.0))
	return b

## Timing bar parameters for the player's chosen move.
func timing_params(move_id: String) -> Dictionary:
	var m: Dictionary = Data.MOVES[move_id]
	var w := 0.2 + 0.05 * (player_level - opp_level) - 0.035 * float(m.diff)
	w = clampf(w, 0.07, 0.42) * (1.0 + zone_bonus(move_id))
	w = clampf(w, 0.05, 0.5) * stamina_factor(stamina_pct())
	var center := rng.randf_range(0.02 + w * 0.5, 0.98 - w * 0.5)
	center = clampf(lerpf(center, 0.5, 0.3), w * 0.5, 1.0 - w * 0.5)
	var perfect := minf(w * 0.2 * float(mods.perfect), w * 0.45)
	return {"center": center, "width": w, "perfect": perfect, "speed": 0.75 + 0.05 * opp_level + 0.06 * maxf(gap(), 0.0)}

func judge_timing(params: Dictionary, marker: float) -> String:
	var d := absf(marker - float(params.center))
	if d <= float(params.perfect):
		return "perfect"
	if d <= float(params.width) * 0.5:
		return "hit"
	return "miss"

## Seconds the player gets to react to an opponent attack.
## How much stronger the opponent is than the player (negative = weaker). Difficulty is mostly
## driven by this gap; the opponent's absolute level only adds a gentle intensity ramp.
func gap() -> float:
	return opp_level - player_level

func defense_window(attack_id := "") -> float:
	var w := clampf(1.1 - 0.18 * gap() - 0.015 * (opp_level - 1.0), 0.5, 1.7) * float(mods.defense)
	if attack_id != "":
		w *= float(mods.defense_vs.get(Data.MOVES[attack_id].type, 1.0))
	return clampf(w, 0.45, 2.6)

func decision_window() -> float:
	return clampf(5.0 - 0.15 * opp_level - 0.4 * gap(), 2.6, 5.0) * float(mods.decision)

## Chance the opponent attacks first at the start of an exchange.
func opp_initiative_chance() -> float:
	var c := 0.26 + 0.06 * gap() + 0.01 * opp_level
	if opp_stamina < 30.0:
		c *= 0.5
	if pos == "standing":
		c *= float(mods.opp_initiative_standing)
	return clampf(c, 0.1, 0.48)

## Chance a missed technique gets countered.
func counter_chance(missed_id := "") -> float:
	if missed_id != "" and mods.scramble and Data.MOVES[missed_id].type == "takedown":
		return 0.0
	return clampf(0.38 + 0.06 * gap() + 0.01 * opp_level, 0.2, 0.65)

func struggle_params(attacking: bool, sub_id := "") -> Dictionary:
	var gain := 0.075 * clampf(1.0 + 0.08 * (player_level - opp_level), 0.6, 1.35) * stamina_factor(stamina_pct())
	gain *= float(mods.struggle_atk) if attacking else float(mods.struggle_def)
	var decay := (0.22 + 0.06 * gap() + 0.01 * opp_level) if attacking else (0.24 + 0.07 * gap() + 0.01 * opp_level)
	decay = maxf(decay, 0.12)
	var start := 0.45
	if attacking:
		start = 0.5 + float(mods.sub_start) + float(mods.sub_start_move.get(sub_id, 0.0))
	return {"start": minf(start, 0.85), "gain": gain, "decay": decay, "limit": 7.0}

# ------------------------------------------------------------ AI
func ai_pick_move() -> String:
	var opts := opp_options()
	if opts.is_empty():
		return ""
	var style: String = opp.get("style", "balanced")
	var best := ""
	var total := 0.0
	var weights := {}
	for id in opts:
		var m: Dictionary = Data.MOVES[id]
		var w := 1.0
		match m.type:
			"sub":
				w = 0.6 + 0.15 * opp_level
				if style == "submission": w *= 2.0
			"sweep", "pass", "advance", "takedown":
				w = 1.4
				if style == "pressure" and m.type in ["pass", "advance", "takedown"]: w *= 1.8
			"back":
				w = 1.2
				if style == "back": w *= 2.5
			"guard":
				w = 0.5
				if style == "guard": w *= 4.0
			"escape":
				w = 1.6
		weights[id] = w
		total += w
	var r := rng.randf() * total
	for id in opts:
		r -= float(weights[id])
		if r <= 0.0:
			return id
	return opts[0]

# ------------------------------------------------------------ state changes
## Apply a successful move. actor_player: true if the player performed it.
## Returns {"sub": bool, "text": String}.
func apply_move(move_id: String, actor_player: bool) -> Dictionary:
	var m: Dictionary = Data.MOVES[move_id]
	var cost := float(m.cost)
	if actor_player:
		spend(player_cost(move_id))
	else:
		opp_stamina = maxf(0.0, opp_stamina - cost)
	if typeof(m.result) == TYPE_STRING and m.result == "sub":
		return {"sub": true, "text": "%s locks in a %s!" % ["You" if actor_player else opp.name, m.name]}
	var res: Array = m.result
	pos = res[0]
	var actor_top: bool = res[1]
	player_top = actor_top if actor_player else not actor_top
	var pts := int(m.pts)
	if actor_player:
		player_pts += pts
	else:
		opp_pts += pts
	var who: String = "You" if actor_player else str(opp.name)
	var text := "%s: %s" % [who, m.name]
	if pts > 0:
		text += "  +%d" % pts
	log_lines.append(text)
	return {"sub": false, "text": text}

func failed_attempt(move_id: String, actor_player: bool) -> void:
	var m: Dictionary = Data.MOVES[move_id]
	if actor_player:
		spend(player_cost(move_id) * 0.6)
		if m.type == "sub":
			player_adv += 1  # near-submission earns an advantage
	else:
		opp_stamina = maxf(0.0, opp_stamina - float(m.cost) * 0.6)
		if m.type == "sub":
			opp_adv += 1

func player_cost(move_id: String) -> float:
	if move_id in mods.free_moves:
		return 0.0
	return float(Data.MOVES[move_id].cost) * float(mods.cost)

func spend(amount: float) -> void:
	stamina = clampf(stamina - amount, 0.0, max_stamina)
	if mods.second_wind and not second_wind_used and stamina < 20.0:
		second_wind_used = true
		second_wind_fired = true
		stamina = minf(max_stamina, stamina + 40.0)
	min_stamina = minf(min_stamina, stamina)

func recover(amount: float) -> void:
	stamina = clampf(stamina + amount, 0.0, max_stamina)

## Passive recovery while choosing a technique.
func regen_tick(delta: float) -> void:
	recover(delta * 2.5 * float(mods.regen))

func tick(delta: float) -> void:
	if over:
		return
	clock = maxf(0.0, clock - delta * CLOCK_SPEED)
	opp_stamina = minf(100.0, opp_stamina + delta * (2.0 + 0.4 * opp_level))
	if clock <= 0.0:
		finish_on_points()

func finish_by_sub(player_won: bool, sub_id: String) -> void:
	over = true
	result = {"won": player_won, "by_sub": true, "sub": sub_id, "min_stamina": 100.0 * min_stamina / max_stamina,
		"score": [player_pts, opp_pts]}

## Daily challenge rules change the starting state.
func apply_rule(r: String) -> void:
	rule = r
	match r:
		"bad_spot":
			pos = "mount"
			player_top = false
		"back_taken":
			pos = "back"
			player_top = false
		"top_start":
			pos = "mount"
			player_top = true
		"tired":
			stamina = max_stamina * 0.5
			min_stamina = stamina
		"sprint":
			clock = 120.0

func finish_on_points() -> void:
	over = true
	var won: bool
	if rule == "sub_only":
		won = false
	elif player_pts != opp_pts:
		won = player_pts > opp_pts
	elif player_adv != opp_adv:
		won = player_adv > opp_adv
	else:
		won = stamina_pct() >= opp_stamina  # referee decision: who looked fresher
	result = {"won": won, "by_sub": false, "sub": "", "min_stamina": 100.0 * min_stamina / max_stamina,
		"score": [player_pts, opp_pts]}

func clock_text() -> String:
	var s := int(ceil(clock))
	return "%d:%02d" % [s / 60, s % 60]
