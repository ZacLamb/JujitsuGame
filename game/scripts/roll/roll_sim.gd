class_name RollSim
extends RefCounted
## Pure, real-time match logic for a roll (no nodes) so it can be unit-tested and balanced headless.
##
## The roll is played like a WoW fight:
##  * Your POSITION is your stance: it decides which abilities sit on your 8-slot action bar.
##  * GRIP CONTROL (0-5) is a combo-point resource. Grip abilities build it; techniques spend all of
##    it, and every grip spent makes the technique more likely to land (subs also start deeper).
##  * Every technique is a CAST with a cast bar. The opponent's casts are colour-coded and can be
##    INTERRUPTED with the matching counter: Base (orange: takedowns, sweeps), Frame (blue: passes,
##    advances, back takes, escapes) or Defend (red: submissions). The AI interrupts you the same way
##    when its counter is off cooldown, so baiting it with a grip first is a real tactic.
##  * Submissions that land become a STRUGGLE: mash to finish (or to escape).
## The scene reads `events` (drained each frame) to animate and narrate what happened.

const MATCH_SECONDS := 240.0  # displayed clock (4:00)
const CLOCK_SPEED := 2.4      # displayed seconds per real second
const MAX_CONTROL := 5
const GCD := 0.45             # global cooldown after starting any action
const RESET_PAUSE := 0.85     # both fighters reset after a position change (lets animations play)

const DEF_KINDS := ["base", "frame", "defend"]
const DEF_NAMES := {"base": "Base", "frame": "Frame", "defend": "Defend"}
const DEF_COLORS := {"base": Color(0.98, 0.6, 0.2), "frame": Color(0.35, 0.65, 1.0), "defend": Color(0.95, 0.3, 0.3), "grip": Color(0.75, 0.75, 0.75)}

## Stance abilities: [grip builder, wear-down]. Names change with the position.
const STANCE := {
	"standing": [["Collar & Sleeve", "Hand Fight"], ["Collar & Sleeve", "Hand Fight"]],
	"guard": [["Grip the Hips", "Posture Up"], ["Sleeve Grip", "Break Posture"]],
	"half": [["Crossface", "Flatten Out"], ["Underhook", "Knee Shield"]],
	"side": [["Crossface", "Shoulder Pressure"], ["Frame the Neck", "Bridge"]],
	"mount": [["Head & Arm", "Heavy Hips"], ["Trap the Arm", "Bump"]],
	"back": [["Seatbelt", "Hooks In"], ["Two-on-One", "Shoulder Walk"]],
}

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
var traits := {"aggr": 1.0, "counter": 0.0, "finish": 1.0, "slippery": 1.0, "cardio": 1.0, "fav": [], "plan": ""}
var signature: Array = []   # the player's style moves (sorted first on the bar)

# ---- real-time state
var live := false            # false during intro / after the match
var control := 0
var opp_control := 0
var off_bal := 0.0           # seconds the player is off-balance (opponent techniques land easier)
var opp_off_bal := 0.0
var cast := {}               # player's cast: {id, name, kind, t, dur, spend, move, ai_int_at}
var opp_cast := {}
var cds := {}                # ability id -> seconds left
var gcd := 0.0
var def_cd := 0.0            # player's counter lockout
var opp_counter_cd := 0.0    # AI interrupt cooldown (shown on its frame)
var ai_t := 1.0              # seconds until the AI's next decision
var reset_t := 0.0
var struggle := {}           # {atk_player, sub, value, gain, decay, t, limit}
var events: Array = []
var clock_scale := 1.0       # the scene slows the fight down (pace) and speeds the clock back up
# ---- boss phases (see Boss)
var boss_phases: Array = []
var phase := 0
var special := {}            # current phase's telegraphed special
var special_t := 0.0
var shield := 0              # Heavy Base stacks: your odds drop until you strip them with wear-downs
var cast_mult := 1.0         # enrage: < 1 = faster casts
var aggr_mult := 1.0
var stats := {"interrupts": 0, "interrupted": 0, "landed": 0, "stuffed": 0, "max_control_spent": 0}

func setup(opponent_id: String, p_level: float, knows: Callable, seed_value := -1, player_mods: Dictionary = {}, opp_override: Dictionary = {}) -> void:
	mods = player_mods if not player_mods.is_empty() else Rpg.neutral_mods()
	max_stamina = float(mods.stamina_max)
	stamina = max_stamina
	min_stamina = max_stamina
	opp_id = opponent_id
	opp = opp_override if not opp_override.is_empty() else Data.OPPONENTS[opponent_id]
	opp_level = float(opp.level)
	traits = Data.personality(opp, opponent_id)
	player_level = p_level
	known_moves = knows
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	ai_t = rng.randf_range(0.8, 1.6)
	var pid := opponent_id if opp_override.is_empty() else str(opp_override.get("phases_of", ""))
	if Boss.has(pid):
		boss_phases = Boss.phases(pid)
		_enter_phase(0, false)

func _enter_phase(n: int, announce := true) -> void:
	phase = n
	var p: Dictionary = boss_phases[n]
	aggr_mult = float(p.get("aggr", 1.0))
	cast_mult = float(p.get("cast_mult", 1.0))
	special = p.get("special", {})
	special_t = float(special.get("every", 0.0)) * 0.5
	if p.has("fav"):
		traits.fav = p.fav
	if p.has("shield"):
		shield = int(p.shield)
	if announce:
		if p.has("pos") and struggle.is_empty():
			pos = p.pos[0]
			player_top = bool(p.pos[1])
			cast = {}
			opp_cast = {}
			control = 0
			opp_control = 0
			reset_t = RESET_PAUSE
		events.append({"e": "phase", "n": n, "name": p.name, "text": p.text, "shield": shield})

## The counter that answers a cast (specials carry their own).
func cast_counter(c: Dictionary) -> String:
	if c.has("counter"):
		return str(c.counter)
	return counter_kind(str(c.get("id", "grip")))

func start_live() -> void:
	live = true

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

## How much stronger the opponent is than the player (negative = weaker). Difficulty is mostly
## driven by this gap; the opponent's absolute level only adds a gentle intensity ramp.
func gap() -> float:
	return opp_level - player_level

## Which counter answers a technique.
static func counter_kind(move_id: String) -> String:
	if move_id == "grip" or move_id == "wear":
		return "grip"
	match str(Data.MOVES[move_id].type):
		"sub":
			return "defend"
		"takedown", "sweep":
			return "base"
	return "frame"

## Grip Control a technique needs before it can be cast.
static func control_req(move_id: String) -> int:
	var m: Dictionary = Data.MOVES[move_id]
	if m.type == "sub":
		return 2 if int(m.diff) >= 2 else 1
	if m.type in ["guard", "escape"]:
		return 0
	if m.type == "back":
		return 2
	return 1

func stance_names(top: bool) -> Array:
	return STANCE[pos][0 if top else 1]

## The player's action bar for the current stance: up to 8 slots.
## Each slot: {id, name, kind ("grip"|"wear"|"move"), req, cost, cast, cd}
func player_bar() -> Array:
	var names := stance_names(player_top)
	var bar: Array = [
		{"id": "grip", "name": names[0], "kind": "grip", "req": 0, "cost": 2.0, "cast": 0.5, "cd": 1.1},
		{"id": "wear", "name": names[1], "kind": "wear", "req": 0, "cost": 6.0, "cast": 0.75, "cd": 5.0},
	]
	var opts := player_options()
	opts.sort_custom(func(a: String, b: String) -> bool:
		var ka := _bar_key(a)
		var kb := _bar_key(b)
		return ka < kb)
	for id in opts.slice(0, 6):
		bar.append(_move_slot(id))
	return bar

func _bar_key(id: String) -> float:
	var m: Dictionary = Data.MOVES[id]
	var k := 0.0 if m.type != "sub" else 10.0
	if id in signature:
		k -= 5.0
	return k - float(m.rank) * 0.01

func _move_slot(id: String) -> Dictionary:
	var m: Dictionary = Data.MOVES[id]
	return {"id": id, "name": m.name, "kind": "move", "req": control_req(id), "cost": player_cost(id),
		"cast": cast_time(id, true), "cd": 4.0 if m.type == "sub" else 2.2}

## Cast time of a technique. The opponent's slow down with your reaction modifiers (IQ, Sprawl...).
func cast_time(move_id: String, by_player: bool) -> float:
	var m: Dictionary = Data.MOVES[move_id]
	var base := 0.7 + 0.14 * float(m.diff) + (0.15 if m.type == "sub" else 0.0)
	if by_player:
		return base / clampf(float(mods.decision), 0.7, 1.6)
	base = 0.62 + 0.12 * float(m.diff) + (0.1 if m.type == "sub" else 0.0)
	if move_id in traits.fav:
		base *= 0.85   # their bread and butter comes out fast
	var s := clampf(1.12 - 0.02 * opp_level - 0.03 * gap(), 0.72, 1.3) * (1.0 - 0.08 * _boss_k())
	if mods.get("roar", false):
		s *= 1.1   # Juba do Leão 4-piece
	s *= cast_mult
	return base * s * float(mods.defense) * float(mods.defense_vs.get(m.type, 1.0))

## Chance a technique lands when its cast completes (spend = grips spent on it).
func technique_chance(move_id: String, by_player: bool, spend: int) -> float:
	var m: Dictionary = Data.MOVES[move_id]
	var g := gap() if by_player else -gap()
	var p := 0.3 + 0.11 * spend - 0.05 * float(m.diff) - 0.07 * clampf(g, -3.0, 3.0)
	if by_player:
		p += zone_bonus(move_id) * 0.6
		if mods.get("champion", false):
			p += 0.04
		p += float(mods.get("edge", 0.0))   # team role matchup
		if shield > 0:
			p *= 0.6   # boss Heavy Base
		if opp_off_bal > 0.0:
			p += 0.28
		if stamina_pct() < 25.0:
			p -= 0.15
		if opp_stamina < 25.0:
			p += 0.12
	else:
		p += 0.015 * clampf(opp_level - 1.0, 0.0, 10.0) - 0.06 + 0.06 * _boss_k()
		if off_bal > 0.0:
			p += 0.28
		if opp_stamina < 25.0:
			p -= 0.15
		if stamina_pct() < 25.0:
			p += 0.12
		p += float(mods.get("opp_edge", 0.0))
		p /= float(mods.defense_vs.get(m.type, 1.0))
	return clampf(p, 0.08, 0.95)

## Chance the AI reads and interrupts one of your technique casts.
func interrupt_chance(move_id := "") -> float:
	if move_id != "" and Data.MOVES.has(move_id) and mods.scramble and Data.MOVES[move_id].type == "takedown":
		return 0.0
	return clampf(0.2 + 0.05 * gap() + 0.008 * opp_level + 0.5 * float(traits.counter) + 0.1 * _boss_k(), 0.06, 0.6) * float(mods.get("read_resist", 1.0))

## Kept for the scramble talent tests: chance a missed technique gets punished.
func counter_chance(missed_id := "") -> float:
	return interrupt_chance(missed_id)

func struggle_params(attacking: bool, sub_id := "") -> Dictionary:
	var gain := 0.075 * clampf(1.0 + 0.08 * (player_level - opp_level), 0.6, 1.35) * stamina_factor(stamina_pct())
	gain *= float(mods.struggle_atk) if attacking else float(mods.struggle_def)
	var decay := (0.22 + 0.06 * gap() + 0.01 * opp_level) if attacking else (0.24 + 0.07 * gap() + 0.01 * opp_level)
	decay *= float(traits.slippery) if attacking else float(traits.finish)
	decay = maxf(decay, 0.12)
	var start := 0.45
	if attacking:
		start = 0.5 + float(mods.sub_start) + float(mods.sub_start_move.get(sub_id, 0.0))
	return {"start": minf(start, 0.85), "gain": gain, "decay": decay, "limit": 7.0}

func _boss() -> bool:
	return bool(opp.get("boss", false))

## Boss sharpness ramps up across the zones (Onça is a gentler first boss).
func _boss_k() -> float:
	return clampf(opp_level / 7.0, 0.3, 1.0) if _boss() else 0.0

func cooldown(id: String) -> float:
	return float(cds.get(id, 0.0))

## Why an ability can't be used right now ("" = usable).
func block_reason(slot: Dictionary) -> String:
	if not live or over or not struggle.is_empty():
		return "busy"
	if reset_t > 0.0 or not cast.is_empty():
		return "busy"
	if gcd > 0.0 or cooldown(slot.id) > 0.0:
		return "cooldown"
	if control < int(slot.req):
		return "control"
	if stamina < float(slot.cost) * 0.5:
		return "stamina"
	return ""

# ------------------------------------------------------------ player actions
## Start an ability by id (from player_bar). Returns "" or the block reason.
func use(id: String) -> String:
	var slot := {}
	for s in player_bar():
		if s.id == id:
			slot = s
	if slot.is_empty():
		return "unknown"
	var why := block_reason(slot)
	if why != "":
		return why
	var spend := control if slot.kind == "move" else 0
	cast = {"id": id, "name": slot.name, "kind": slot.kind, "t": 0.0, "dur": float(slot.cast), "spend": spend, "ai_int_at": -1.0}
	gcd = GCD
	# the AI decides now whether it will read this one
	if opp_counter_cd <= 0.0 and opp_cast.is_empty():
		var ic := interrupt_chance(id if slot.kind == "move" else "")
		if slot.kind != "move":
			ic *= 0.25   # it sometimes bites on a grip (and burns its counter)
		if rng.randf() < ic:
			cast.ai_int_at = float(slot.cast) * rng.randf_range(0.35, 0.85)
	events.append({"e": "cast", "who": "p", "id": id, "name": slot.name, "kind": slot.kind, "dur": float(slot.cast)})
	return ""

## Breathe: a channel that restores stamina (and leaves you open).
func breathe() -> String:
	if not live or over or not struggle.is_empty() or reset_t > 0.0 or not cast.is_empty() or gcd > 0.0:
		return "busy"
	if cooldown("breathe") > 0.0:
		return "cooldown"
	cast = {"id": "breathe", "name": "Breathe", "kind": "breathe", "t": 0.0, "dur": 1.4, "spend": 0, "ai_int_at": -1.0}
	gcd = GCD
	events.append({"e": "cast", "who": "p", "id": "breathe", "name": "Breathe", "kind": "breathe", "dur": 1.4})
	return ""

## Disengage: step back and walk away (open-world fights only). Only from standing; a 1.8s
## channel they can grab you out of. No win, no loss, no rewards.
const DISENGAGE_TIME := 1.8
var can_disengage := false

func disengage() -> String:
	if not can_disengage:
		return "locked"
	if not live or over or not struggle.is_empty() or reset_t > 0.0 or not cast.is_empty():
		return "busy"
	if pos != "standing":
		return "grounded"
	cast = {"id": "disengage", "name": "Disengage", "kind": "disengage", "t": 0.0, "dur": DISENGAGE_TIME, "spend": 0, "ai_int_at": -1.0}
	gcd = GCD
	if opp_counter_cd <= 0.0 and opp_cast.is_empty() and rng.randf() < 0.35 * float(traits.aggr):
		cast.ai_int_at = DISENGAGE_TIME * rng.randf_range(0.4, 0.85)   # they grab you back
	events.append({"e": "cast", "who": "p", "id": "disengage", "name": "Disengage", "kind": "disengage", "dur": DISENGAGE_TIME})
	return ""

## Answer the opponent's cast with a counter. Right counter = interrupt; wrong one = locked out.
func defend(kind: String) -> String:
	if not live or over or not struggle.is_empty() or def_cd > 0.0:
		return "busy"
	if opp_cast.is_empty():
		def_cd = 0.6
		events.append({"e": "whiff", "kind": kind})
		return "nothing"
	var need := cast_counter(opp_cast)
	if need == "grip" or need == kind:
		_interrupt_opp(kind)
		return ""
	def_cd = 1.6
	spend(3.0)
	events.append({"e": "wrong", "kind": kind, "need": need})
	return "wrong"

func _interrupt_opp(kind: String) -> void:
	var was: Dictionary = opp_cast
	opp_cast = {}
	def_cd = 0.9
	spend(3.0)
	if mods.get("flow", false):
		recover(6.0)   # Véu de Noiva 4-piece
	if was.kind == "special":
		opp_stamina = maxf(0.0, opp_stamina - 15.0)
		opp_control = 0
		opp_off_bal = 2.6
		control = mini(MAX_CONTROL, control + 2)
		stats.interrupts += 1
		ai_t = maxf(ai_t, 1.2)
	elif was.kind == "move":
		opp_stamina = maxf(0.0, opp_stamina - float(Data.MOVES[was.id].cost) * 0.5)
		opp_control = 0
		opp_off_bal = 1.8
		control = mini(MAX_CONTROL, control + 1 + int(mods.get("steal", 0)))
		stats.interrupts += 1
		ai_t = maxf(ai_t, 0.9)
	else:
		opp_control = maxi(0, opp_control - 1)
	events.append({"e": "interrupt", "by": "p", "id": was.id, "name": was.name, "kind": kind, "was": was.kind})

## Mash during a submission struggle (either side).
func tap() -> void:
	if struggle.is_empty():
		return
	struggle.value = minf(1.0, float(struggle.value) + float(struggle.gain))
	spend(0.6)
	if float(struggle.value) >= 1.0:
		_end_struggle(true)   # finished it, or broke the grip

# ------------------------------------------------------------ main loop
func tick(delta: float) -> void:
	if over:
		return
	clock = maxf(0.0, clock - delta * CLOCK_SPEED * clock_scale)
	opp_stamina = minf(100.0, opp_stamina + delta * (2.0 + 0.4 * opp_level) * float(traits.cardio))
	if live:
		_live_tick(delta)
	if clock <= 0.0 and not over:
		if not struggle.is_empty():
			_end_struggle(not struggle.atk_player)   # bell rings mid-submission: it was escaped
		finish_on_points()
		events.append({"e": "over"})

func _live_tick(delta: float) -> void:
	for k in cds.keys():
		cds[k] = float(cds[k]) - delta
		if cds[k] <= 0.0:
			cds.erase(k)
	gcd = maxf(0.0, gcd - delta)
	def_cd = maxf(0.0, def_cd - delta)
	opp_counter_cd = maxf(0.0, opp_counter_cd - delta)
	off_bal = maxf(0.0, off_bal - delta)
	opp_off_bal = maxf(0.0, opp_off_bal - delta)
	if not struggle.is_empty():
		_struggle_tick(delta)
		return
	if not boss_phases.is_empty() and phase + 1 < boss_phases.size() and Boss.triggered(boss_phases[phase + 1], self):
		_enter_phase(phase + 1)
	if reset_t > 0.0:
		reset_t -= delta
		return
	if cast.is_empty() or cast.kind == "breathe":
		recover(delta * 2.5 * float(mods.regen))
	# player cast
	if not cast.is_empty():
		cast.t = float(cast.t) + delta
		if float(cast.ai_int_at) >= 0.0 and float(cast.t) >= float(cast.ai_int_at) and opp_cast.is_empty():
			_ai_interrupts()
		elif float(cast.t) >= float(cast.dur):
			_resolve_player()
	if over or reset_t > 0.0 or not struggle.is_empty():
		return
	# opponent cast
	if not opp_cast.is_empty():
		opp_cast.t = float(opp_cast.t) + delta
		if float(opp_cast.t) >= float(opp_cast.dur):
			_resolve_opp()
	elif reset_t <= 0.0:
		ai_t -= delta
		if not special.is_empty():
			special_t -= delta
		if not special.is_empty() and special_t <= 0.0 and opp_stamina > 8.0:
			_cast_special()
		elif ai_t <= 0.0:
			_ai_think()

func _ai_interrupts() -> void:
	var was: Dictionary = cast
	cast = {}
	opp_counter_cd = 4.2
	opp_stamina = maxf(0.0, opp_stamina - 3.0)
	if was.kind == "move":
		failed_attempt(was.id, true)
		control = 0
		off_bal = 1.6
		opp_control = mini(MAX_CONTROL, opp_control + 1)
		cds[was.id] = 2.0
		stats.interrupted += 1
	else:
		control = maxi(0, control - 1)
	events.append({"e": "interrupt", "by": "o", "id": was.id, "name": was.name, "was": was.kind})

func _resolve_player() -> void:
	var c: Dictionary = cast
	cast = {}
	match c.kind:
		"disengage":
			if pos != "standing":
				events.append({"e": "whiff", "kind": "disengage"})
				return
			over = true
			live = false
			result = {"won": false, "disengaged": true, "by_sub": false, "sub": "", "min_stamina": 100.0 * min_stamina / max_stamina, "score": [player_pts, opp_pts]}
			events.append({"e": "disengaged"})
		"breathe":
			recover(30.0 if mods.get("second_breath", false) else 20.0)
			cds["breathe"] = 6.0
			events.append({"e": "breathed"})
		"grip":
			spend(2.0 * float(mods.cost))
			var gain := 2 if opp_off_bal > 0.0 else 1
			control = mini(MAX_CONTROL, control + gain)
			cds["grip"] = 1.1
			events.append({"e": "grip", "who": "p", "n": control})
		"wear":
			spend(6.0 * float(mods.cost))
			opp_stamina = maxf(0.0, opp_stamina - float(mods.get("wear_dmg", 10.0)))
			opp_control = maxi(0, opp_control - 1)
			control = mini(MAX_CONTROL, control + 1)
			cds["wear"] = 5.0
			events.append({"e": "wear", "who": "p", "name": c.name})
			if shield > 0:
				shield -= 1
				events.append({"e": "shield", "left": shield})
		"move":
			var id: String = c.id
			var spent := int(c.spend)
			stats.max_control_spent = maxi(int(stats.max_control_spent), spent)
			var m: Dictionary = Data.MOVES[id]
			cds[id] = 4.0 if m.type == "sub" else 2.2
			if rng.randf() < technique_chance(id, true, spent):
				control = 0
				_land(id, true, spent)
			else:
				failed_attempt(id, true)
				control = maxi(0, control - maxi(1, spent / 2))
				off_bal = 1.2
				opp_control = mini(MAX_CONTROL, opp_control + 1)
				stats.stuffed += 1
				events.append({"e": "stuffed", "who": "p", "id": id})

func _resolve_opp() -> void:
	var c: Dictionary = opp_cast
	opp_cast = {}
	match c.kind:
		"special":
			_special_lands(c)
		"grip":
			opp_stamina = maxf(0.0, opp_stamina - 2.0)
			opp_control = mini(MAX_CONTROL, opp_control + (2 if off_bal > 0.0 else 1))
			events.append({"e": "grip", "who": "o", "n": opp_control})
		"wear":
			opp_stamina = maxf(0.0, opp_stamina - 5.0)
			spend(8.0)
			control = maxi(0, control - 1)
			opp_control = mini(MAX_CONTROL, opp_control + 1)
			events.append({"e": "wear", "who": "o", "name": c.name})
		"move":
			var id: String = c.id
			var spent := int(c.spend)
			if rng.randf() < technique_chance(id, false, spent):
				opp_control = 0
				_land(id, false, spent)
			else:
				failed_attempt(id, false)
				opp_control = maxi(0, opp_control - maxi(1, spent / 2))
				opp_off_bal = 1.2
				control = mini(MAX_CONTROL, control + 1)
				events.append({"e": "stuffed", "who": "o", "id": id})
	ai_t = _ai_delay()

func _land(id: String, by_player: bool, spent: int) -> void:
	var r := apply_move(id, by_player)
	if by_player:
		stats.landed += 1
	if r.sub:
		var p := struggle_params(by_player, id)
		var start := float(p.start) + 0.05 * float(spent - 2) * (1.0 if by_player else -1.0)
		struggle = {"atk_player": by_player, "sub": id, "value": clampf(start, 0.2, 0.9), "gain": p.gain, "decay": p.decay, "t": 0.0, "limit": p.limit, "spent": spent}
		cast = {}
		opp_cast = {}
		events.append({"e": "sub", "who": "p" if by_player else "o", "id": id})
		return
	if by_player and mods.get("death_roll", false) and Data.MOVES[id].type in ["sweep", "takedown"]:
		opp_stamina = maxf(0.0, opp_stamina - 15.0)   # Couro de Jacaré 4-piece
	# position changed: grips are lost, the bar swaps, both fighters reset
	control = 1 if mods.get("pounce", false) else 0   # Onça Pintada 4-piece
	opp_control = 0
	off_bal = 0.0
	opp_off_bal = 0.0
	cast = {}
	opp_cast = {}
	reset_t = RESET_PAUSE
	ai_t = RESET_PAUSE + _ai_delay() * 0.6
	events.append({"e": "landed", "who": "p" if by_player else "o", "id": id, "text": r.text, "spent": spent})

func _struggle_tick(delta: float) -> void:
	struggle.t = float(struggle.t) + delta
	struggle.value = float(struggle.value) - float(struggle.decay) * delta
	var atk: bool = struggle.atk_player
	if atk:
		if float(struggle.value) <= 0.0 or float(struggle.t) >= float(struggle.limit):
			_end_struggle(false)
	else:
		if float(struggle.value) <= 0.0:
			_end_struggle(false)
		elif float(struggle.t) >= float(struggle.limit):
			_end_struggle(float(struggle.value) >= 0.5)

## player_won_struggle: the player finished their sub, or escaped the opponent's.
func _end_struggle(player_won_struggle: bool) -> void:
	var s: Dictionary = struggle
	struggle = {}
	var atk: bool = s.atk_player
	if atk and player_won_struggle:
		finish_by_sub(true, s.sub)
		events.append({"e": "tap", "who": "o", "id": s.sub})
	elif not atk and not player_won_struggle:
		finish_by_sub(false, s.sub)
		events.append({"e": "tap", "who": "p", "id": s.sub})
	else:
		failed_attempt(s.sub, atk)
		reset_t = RESET_PAUSE
		ai_t = RESET_PAUSE + 0.6
		events.append({"e": "escaped", "who": "o" if atk else "p", "id": s.sub})

# ------------------------------------------------------------ AI
func _ai_delay() -> float:
	var d := clampf(1.25 - 0.04 * opp_level - 0.1 * gap(), 0.45, 1.6) / clampf(float(traits.aggr) * aggr_mult, 0.6, 2.0)
	if opp_stamina < 30.0:
		d *= 1.5
	return d * rng.randf_range(0.75, 1.25)

func ai_pick_move() -> String:
	var opts := opp_options()
	if opts.is_empty():
		return ""
	var style: String = opp.get("style", "balanced")
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
		if id in traits.fav:
			w *= 3.0
		# stuck under a dominant position: getting out comes first
		if m.type == "escape" and pos in ["mount", "back", "side"]:
			w *= 1.8
		weights[id] = w
		total += w
	var r := rng.randf() * total
	for id in opts:
		r -= float(weights[id])
		if r <= 0.0:
			return id
	return opts[0]

func _ai_think() -> void:
	ai_t = _ai_delay()
	if opp_stamina < 12.0:
		return   # gassed: hangs on
	var mv := ai_pick_move()
	var top := not player_top
	var names: Array = STANCE[pos][0 if top else 1]
	var want := 0
	if mv != "":
		want = control_req(mv) + (1 if Data.MOVES[mv].type == "sub" else 0) + (1 if opp_level > 6.0 else 0)
	if mv != "" and opp_control >= mini(want, MAX_CONTROL) and opp_control >= control_req(mv):
		var dur := cast_time(mv, false)
		opp_cast = {"id": mv, "name": Data.MOVES[mv].name, "kind": "move", "t": 0.0, "dur": dur, "spend": opp_control}
		events.append({"e": "cast", "who": "o", "id": mv, "name": Data.MOVES[mv].name, "kind": "move", "dur": dur, "counter": counter_kind(mv)})
	elif rng.randf() < 0.18 and opp_stamina > 40.0:
		opp_cast = {"id": "wear", "name": names[1], "kind": "wear", "t": 0.0, "dur": 0.9, "spend": 0}
		events.append({"e": "cast", "who": "o", "id": "wear", "name": names[1], "kind": "wear", "dur": 0.9, "counter": "grip"})
	else:
		opp_cast = {"id": "grip", "name": names[0], "kind": "grip", "t": 0.0, "dur": 0.7, "spend": 0}
		events.append({"e": "cast", "who": "o", "id": "grip", "name": names[0], "kind": "grip", "dur": 0.7, "counter": "grip"})

func _cast_special() -> void:
	special_t = float(special.every)
	var dur := float(special.dur) * float(mods.defense)
	opp_cast = {"id": "special:" + str(special.id), "name": special.name, "kind": "special", "t": 0.0, "dur": dur,
		"spend": 0, "counter": special.counter, "effect": special.effect}
	events.append({"e": "cast", "who": "o", "id": opp_cast.id, "name": special.name, "kind": "special", "dur": dur,
		"counter": special.counter, "hint": special.get("hint", "")})

func _special_lands(c: Dictionary) -> void:
	opp_stamina = maxf(0.0, opp_stamina - 6.0)
	match str(c.effect):
		"sweep":
			cast = {}
			pos = "mount"
			player_top = false
			opp_pts += 2
			control = 0
			reset_t = RESET_PAUSE
			log_lines.append(Tx.f("%s: %s  +2", [opp.name, c.name]))
		"crush":
			spend(25.0)
			control = 0
			cast = {}
			if player_top or pos == "standing":
				pos = "side"
				player_top = false
				opp_pts += 3
			reset_t = RESET_PAUSE * 0.6
		"roar":
			spend(15.0)
			def_cd = 3.5
			control = maxi(0, control - 2)
		"deep_sub":
			var sid := ""
			for id in opp_options():
				if Data.MOVES[id].type == "sub":
					sid = id
					break
			if sid == "":
				spend(20.0)
			else:
				var p := struggle_params(false, sid)
				struggle = {"atk_player": false, "sub": sid, "value": 0.28, "gain": p.gain, "decay": p.decay, "t": 0.0, "limit": p.limit, "spent": 4}
				cast = {}
				events.append({"e": "special_landed", "id": c.id, "name": c.name, "effect": c.effect})
				events.append({"e": "sub", "who": "o", "id": sid})
				ai_t = _ai_delay()
				return
	events.append({"e": "special_landed", "id": c.id, "name": c.name, "effect": c.effect})
	ai_t = _ai_delay()

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
		return {"sub": true, "text": Tx.f("%s locks in a %s!", ["You" if actor_player else opp.name, m.name])}
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
	var text := Tx.f("%s: %s", [who, m.name])
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

## Passive recovery (kept for tools that tick stamina directly).
func regen_tick(delta: float) -> void:
	recover(delta * 2.5 * float(mods.regen))

func finish_by_sub(player_won: bool, sub_id: String) -> void:
	over = true
	live = false
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
		"team":
			clock = 150.0   # 5v5 elimination bouts are short; a draw eliminates both

func finish_on_points() -> void:
	over = true
	live = false
	var won: bool
	if rule == "team" and player_pts == opp_pts and player_adv == opp_adv:
		result = {"won": false, "draw": true, "by_sub": false, "sub": "", "min_stamina": 100.0 * min_stamina / max_stamina,
			"score": [player_pts, opp_pts]}
		return
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
