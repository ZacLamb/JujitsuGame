class_name CombatCore
extends RefCounted
## WoW-style real-time combat, logic only (no nodes): units with Composure (health), Gas (energy)
## and Grip (combo points); a global cooldown, ability cooldowns, cast bars, interrupts, auras
## (Down = stunned, Pinned, Exposed, Base...), auto-attack hand fighting, crits and AI for enemies.
## WorldCombat feeds it positions and turns its events into animation, sounds and UI.

signal event(e: Dictionary)

const GCD := 1.0
const MELEE := 2.4
const CRIT := 0.08
const CRIT_MULT := 1.75
const OOC_REGEN := 0.05        # fraction of max composure per second, out of combat
const OOC_DELAY := 4.0

class Unit:
	var id := 0
	var name := ""
	var player := false
	var level := 1
	var hp := 100.0
	var max_hp := 100.0
	var gas := 100.0
	var max_gas := 100.0
	var gas_regen := 10.0
	var grip := 0
	var max_grip := 5
	var abilities: Array = []      # ability dicts (see Abilities)
	var cds := {}                  # ability id -> seconds left
	var gcd := 0.0
	var cast := {}                 # {ab, t, dur, target}
	var swing := 1.0
	var swing_time := 2.0
	var auto_dmg := 4.0
	var dmg := 10.0                # damage scale (ability "dmg" multiplies this)
	var auras := {}                # name -> {t, src, ...}
	var target: Unit = null
	var pos := Vector3.ZERO        # fed by WorldCombat each frame
	var mods := {}
	var dead := false
	var elite := false
	var boss := false
	var data := {}                 # mob / opponent dict
	var in_combat := false
	var ooc_t := 99.0
	var ai_t := 2.0
	var last_sub := ""
	var second_wind_used := false
	var known: Array = []          # player: known move ids, strongest first
	var gpos := "standing"         # enemy units: the grappling position with the player
	var ptop := false              # enemy units: is the player the one on top
	var rank := 0

	func has(a: String) -> bool:
		return auras.has(a)
	func down() -> bool:
		return auras.has("down")
	func pct() -> float:
		return hp / max_hp

var units: Array = []
var player: Unit = null
var _next_id := 1
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()

# ------------------------------------------------------------ units
static func dmg_scale(level: int) -> float:
	return 6.0 + 1.5 * float(level)

func add_player(name: String, level: int, mods: Dictionary, abilities: Array) -> Unit:
	var u := Unit.new()
	u.player = true
	u.name = name
	u.level = level
	u.mods = mods
	u.max_hp = (140.0 + 18.0 * level + float(mods.get("hp_flat", 0.0))) * float(mods.get("hp_mult", 1.0))
	u.hp = u.max_hp
	u.max_gas = float(mods.get("stamina_max", 100.0))
	u.gas = u.max_gas
	u.gas_regen = 15.0 * float(mods.get("regen", 1.0))
	u.dmg = dmg_scale(level)
	u.auto_dmg = u.dmg * 0.8
	u.swing_time = 2.0
	u.abilities = abilities
	u.known = Abilities.known_moves()
	return _add(u)

## Enemy from a mob or opponent dict. kind: "mob" | "named" | "boss".
func add_enemy(d: Dictionary, kind: String) -> Unit:
	var u := Unit.new()
	u.data = d
	u.name = str(d.get("name", "?"))
	u.level = Data.display_level(float(d.get("level", 1.0)))
	u.rank = int(d.get("rank", 0))
	u.elite = bool(d.get("elite", false)) or kind != "mob"
	u.boss = kind == "boss" or bool(d.get("rare", false))
	var hm := 1.0
	var dm := 1.0
	if bool(d.get("rare", false)):
		hm = 2.3
		dm = 1.5
	elif kind == "boss":
		hm = 4.0
		dm = 1.5
	elif kind == "named":
		hm = 2.2
		dm = 1.25
	elif u.elite:
		hm = 2.2
		dm = 1.5
	u.max_hp = (110.0 + 26.0 * u.level) * hm
	u.hp = u.max_hp
	u.dmg = dmg_scale(u.level) * dm
	u.auto_dmg = u.dmg * 0.5
	u.swing_time = 1.8
	u.abilities = Abilities.enemy_kit(d, u.elite, u.boss)
	u.ai_t = rng.randf_range(2.5, 4.5)
	return _add(u)

func _add(u: Unit) -> Unit:
	u.id = _next_id
	_next_id += 1
	units.append(u)
	if u.player:
		player = u
	return u

func remove(u: Unit) -> void:
	units.erase(u)
	for o in units:
		if o.target == u:
			o.target = null

func enemies() -> Array:
	return units.filter(func(o): return not o.player and not o.dead)

func engaged_enemies() -> Array:
	return units.filter(func(o): return not o.player and not o.dead and o.in_combat)

func dist(a: Unit, b: Unit) -> float:
	return Vector2(a.pos.x, a.pos.z).distance_to(Vector2(b.pos.x, b.pos.z))

func engage(a: Unit, b: Unit) -> void:
	for u in [a, b]:
		if not u.in_combat:
			u.in_combat = true
			if u.player:
				u.grip = maxi(u.grip, int(u.mods.get("grip_start", 0.0)))
				u.second_wind_used = false
			emit({"t": "combat", "u": u, "on": true})
		u.ooc_t = 0.0
	if a.target == null:
		a.target = b
	if b.target == null:
		b.target = a

func leave_combat(u: Unit) -> void:
	u.ooc_t = 0.0
	if u.in_combat:
		u.in_combat = false
		u.cast = {}
		emit({"t": "combat", "u": u, "on": false})

func emit(e: Dictionary) -> void:
	event.emit(e)

# ------------------------------------------------------------ abilities
func ability(u: Unit, id: String) -> Dictionary:
	for a in u.abilities:
		if str(a.get("id", "")) == id and id != "":
			return a
	return {}

func cost_of(u: Unit, a: Dictionary) -> float:
	var c := float(a.get("cost", 0.0))
	if u.player:
		var m := u.mods
		c += float(m.get("cost_add", {}).get(str(a.get("id", "")), 0.0))
		c *= float(m.get("cost", 1.0)) * (1.0 - float(m.get("cost_mult", 0.0)))
		if str(a.get("move", "")) in m.get("free_moves", []):
			c = 0.0
		if bool(a.get("finisher", false)) and m.get("free_sub", false):
			c = 0.0
	return maxf(c, 0.0)

func cd_of(u: Unit, a: Dictionary) -> float:
	var c := float(a.get("cd", 0.0))
	if u.player:
		if str(a.get("type", "")) == "escape" and u.mods.get("scramble", false):
			c *= 0.5
		c *= 1.0 - float(u.mods.get("cd", {}).get(str(a.get("id", "")), 0.0))
		if str(a.get("id", "")) == "spec":
			pass
		c *= 1.0 - float(u.mods.get("cd", {}).get(str(a.get("type", "")), 0.0)) if str(a.get("type", "")) != str(a.get("id", "")) else 1.0
	return maxf(c, 0.0)

func haste(u: Unit) -> float:
	return float(u.mods.get("decision", 1.0)) if u.player else 1.0

# ------------------------------------------------------------ positions (the grappling layer)
## Every fight with your target has a position (standing, guard, half, side, mount, back) and a
## top / bottom. Techniques only work from where they belong, move you along the position graph,
## and dominant spots hit harder and take less.
const POSITIONAL := ["takedown", "sweep", "pass", "advance", "back", "sub", "escape", "guard"]
const DOM := {"standing": 0, "guard": 1, "half": 1, "side": 2, "mount": 3, "back": 4}
const KIND_KEY := {"base": "Q", "frame": "R", "defend": "T"}
const KIND_VERB := {"base": "Sprawl", "frame": "Frame", "defend": "Defend"}

## [position, is u on top] for u fighting t (one of them must be the player).
func pos_info(u: Unit, t: Unit) -> Array:
	if t == null or u == null:
		return ["standing", false]
	var e := t if u.player else u
	if e.player:
		return ["standing", false]
	return [e.gpos, e.ptop if u.player else not e.ptop]

## How dominant u is over t: +4 on the back ... -4 with their back taken.
func dom(u: Unit, t: Unit) -> int:
	var pi := pos_info(u, t)
	if str(pi[0]) == "standing":
		return 0
	var d := int(DOM.get(str(pi[0]), 0))
	if str(pi[0]) == "guard":
		return 1 if pi[1] else 0     # closed guard is a fine place to be on the bottom
	return d if pi[1] else -d

static func pos_label(pos: String, top: bool) -> String:
	if pos == "standing":
		return "Standing"
	return "%s (%s)" % [Data.POSITION_NAMES.get(pos, pos), "top" if top else "bottom"]

## The technique an ability button means right now (strongest known move of that type from this
## position), "@stand" for a generic scramble up, or "" if there's nothing from here.
func move_for(u: Unit, a: Dictionary, t: Unit) -> String:
	if str(a.get("effect", "")) == "advice":
		return ""   # Corner Advice is not a technique
	var tp := str(a.get("type", ""))
	if not u.player or not (tp in POSITIONAL or str(a.get("id", "")) == "spec"):
		return str(a.get("_mv", a.get("move", "")))
	var pi := pos_info(u, t)
	var pos := str(pi[0])
	var role := "top" if pi[1] else "bottom"
	var ok := func(mv: String) -> bool:
		var m: Dictionary = Data.MOVES.get(mv, {})
		return not m.is_empty() and str(m.pos) == pos and (str(m.role) == "any" or str(m.role) == role or pos == "standing")
	if str(a.get("id", "")) == "spec":
		return str(a.move) if ok.call(str(a.move)) else ""
	for mv in u.known:
		if str(Data.MOVES[mv].type) == tp and ok.call(mv):
			return mv
	if tp == "escape" and pos != "standing" and (pos in ["guard", "half"] or pi[1]):
		return "@stand"
	return ""

## Why `a` can't be used on `t` right now ("" = ok). Shown as a red WoW-style error.
func block_reason(u: Unit, a: Dictionary, t: Unit) -> String:
	if a.is_empty():
		return "Not learned yet"
	if u.dead:
		return "You tapped"
	if u.down() and str(a.type) != "escape" and not str(a.get("effect", "")) in ["jeitinho", "advice"]:
		return "You're down!"
	if not u.cast.is_empty():
		return "Busy"
	if float(u.cds.get(a.id, 0.0)) > 0.0:
		return "Not ready yet"
	if bool(a.get("gcd", true)) and u.gcd > 0.0:
		return "gcd"
	if u.gas < cost_of(u, a):
		return "Not enough gas"
	if bool(a.get("finisher", false)) and u.grip < 1:
		return "Needs grip (build it first)"
	if bool(a.get("ooc", false)) and u.in_combat:
		return "Can't do that in combat"
	if u.player and (str(a.get("type", "")) in POSITIONAL or str(a.get("id", "")) == "spec") and str(a.get("effect", "")) != "advice":
		var pi := pos_info(u, t if t != null else u.target)
		if move_for(u, a, t if t != null else u.target) == "":
			return "Not from %s" % pos_label(str(pi[0]), bool(pi[1]))
	if bool(a.get("harm", true)):
		if t == null or t.dead:
			return "No target"
		if t.player == u.player:
			return "Invalid target"
		if dist(u, t) > float(a.get("range", MELEE)):
			return "Out of range"
	return ""

## Starts (or instantly resolves) an ability. Returns "" or the error text.
func use(u: Unit, id: String, t: Unit = null) -> String:
	return use_ab(u, ability(u, id), t)

func use_ab(u: Unit, a: Dictionary, t: Unit = null) -> String:
	if t == null:
		t = u.target
	var why := block_reason(u, a, t)
	if why != "":
		return why
	if bool(a.get("harm", true)):
		engage(u, t)
		u.target = t
	if u.player:
		var mv := move_for(u, a, t)
		if mv != "" and mv != str(a.get("move", "")) or mv == "@stand":
			a = a.duplicate()
			a["_mv"] = mv
			a["name"] = "Scramble Up" if mv == "@stand" else str(Data.MOVES[mv].name)
		elif mv != "":
			a = a.duplicate()
			a["_mv"] = mv
	u.gas -= cost_of(u, a)
	if bool(a.get("gcd", true)):
		u.gcd = GCD / haste(u)
	var ct := float(a.get("cast", 0.0)) / haste(u)
	if u.player and bool(a.get("finisher", false)):
		if u.mods.get("instant_sub", false):
			ct = 0.0
		ct *= 1.0 - float(u.mods.get("haste_sub", 0.0))
	if ct > 0.0:
		u.cast = {"ab": a, "t": 0.0, "dur": ct, "target": t}
		emit({"t": "cast", "u": u, "ab": a, "target": t, "dur": ct})
	else:
		_resolve(u, a, t)
	return ""

func _resolve(u: Unit, a: Dictionary, t: Unit) -> void:
	var cd := cd_of(u, a)
	if cd > 0.0:
		u.cds[a.id] = cd
	var eff := str(a.get("effect", ""))
	emit({"t": "use", "u": u, "ab": a, "target": t})
	match eff:
		"base":
			_aura(u, "base", float(a.get("dur", 5.0)) + _extra(u, "base"), u)
			if u.player and u.mods.get("base_grip", false):
				u.grip = mini(u.max_grip, u.grip + 2)
				u.gas = minf(u.max_gas, u.gas + 30.0)
			_counter(u, u.target, "base")
			return
		"defend":
			_aura(u, "defending", 3.0, u)
			_counter(u, u.target, "defend")
			return
		"guard":
			_aura(u, "guarded", float(a.get("dur", 6.0)) + _extra(u, "guarded"), u)
			_transition(u, u.target, str(a.get("_mv", "")), a)
			return
		"lucky":
			_aura(u, "lucky", 20.0, u)
			return
		"jeitinho":
			for k in ["down", "pinned"]:
				if u.auras.has(k):
					u.auras.erase(k)
					emit({"t": "aura_off", "u": u, "aura": k})
			return
		"lasso":
			u.grip = mini(u.max_grip, u.grip + 2)
			return
		"mate":
			_aura(u, "mate", 6.0, u)
			return
		"ginga":
			_aura(u, "ginga", 3.0, u)
			return
		"rush":
			_aura(u, "rush", 8.0, u)
			return
		"breathe":
			u.gas = minf(u.max_gas, u.gas + 45.0)
			_heal(u, u.max_hp * ((0.5 if not u.in_combat else 0.08) + float(u.mods.get("breathe_heal", 0.0))), u)
			return
		"advice":
			# Professor: the corner's voice. Heal, refill gas, and a damage buff
			_heal(u, u.max_hp * (0.20 + float(u.mods.get("advice_heal", 0.0))), u)
			u.gas = minf(u.max_gas, u.gas + 30.0)
			_aura(u, "game_plan", 10.0, u)
			emit({"t": "proc", "u": u, "text": "Corner: \"Breathe. Stick to the plan.\""})
			return
		"escape":
			for k in ["down", "pinned", "exposed"]:
				if u.auras.has(k):
					u.auras.erase(k)
					emit({"t": "aura_off", "u": u, "aura": k})
			_heal(u, u.max_hp * 0.12, u)
			if u.player:
				u.grip = mini(u.max_grip, u.grip + 1)
				u.gas = minf(u.max_gas, u.gas + float(u.mods.get("escape_gas", 0.0)))
			_transition(u, u.target if u.player else t, str(a.get("_mv", "")), a)
			return
		"interrupt":
			if t and not t.cast.is_empty():
				_counter(u, t, "frame")
			else:
				emit({"t": "miss", "u": u, "target": t, "text": "Nothing to frame"})
			return
	if t == null or t.dead:
		return
	# damage
	var mult := float(a.get("dmg", 0.0))
	if bool(a.get("finisher", false)):
		mult += float(a.get("per_grip", 0.9)) * u.grip
		if u.player:
			mult *= 1.0 + float(u.mods.get("sub_start", 0.0)) + float(u.mods.get("sub_start_move", {}).get(str(a.get("move", "")), 0.0))
		u.last_sub = str(a.get("move", "sub"))
		u.grip = 0
	if mult > 0.0:
		var amount := u.dmg * mult * _type_bonus(u, a)
		var crit_c := CRIT + (0.25 if t.has("exposed") and t.auras.exposed.src == u else 0.0)
		if u.player:
			var m := u.mods
			crit_c += (float(m.get("perfect", 1.0)) - 1.0) * 0.5 + float(m.get("crit", 0.0))
			if t.has("pinned"):
				amount *= 1.0 + float(m.get("pinned_vuln", 0.0))
			if t.down():
				amount *= 1.0 + float(m.get("down_dmg", 0.0))
			if t.pct() < 0.35:
				amount *= 1.0 + float(m.get("exec", 0.0))
		var crit := rng.randf() < crit_c
		if u.has("lucky"):
			crit = true
			u.auras.erase("lucky")
			emit({"t": "aura_off", "u": u, "aura": "lucky"})
		if u.has("rush"):
			amount *= 1.2
		if u.has("game_plan"):
			amount *= 1.15
		if u.has("rattled"):
			amount *= 0.85
		if crit:
			amount *= CRIT_MULT * (float(u.mods.get("struggle_atk", 1.0)) if u.player else 1.0)
			if u.player and bool(a.get("finisher", false)):
				amount *= 1.0 + float(u.mods.get("sub_crit", 0.0))
		_damage(u, t, amount, crit, a)
	if t.dead:
		return
	var g := int(a.get("grip", 0))
	if u.player:
		g += int(u.mods.get("grip_bonus", {}).get(str(a.get("id", "")), 0.0))
	if g > 0:
		u.grip = mini(u.max_grip, u.grip + g)
	match eff:
		"down":
			_aura(t, "down", float(a.get("dur", 1.8)) + _extra(u, "down"), u)
		"pin":
			_aura(t, "pinned", float(a.get("dur", 6.0)) + _extra(u, "pinned"), u)
			if u.player and u.mods.get("pin_grip", false):
				u.grip = mini(u.max_grip, u.grip + 1)
		"expose":
			_aura(t, "exposed", float(a.get("dur", 8.0)) + _extra(u, "exposed"), u)
	if not t.dead:
		_transition(u, t, str(a.get("_mv", "")), a)

## The counter for a technique: sprawl / base on takedowns and sweeps, frame on passes and
## positional moves, defend on submissions.
static func counter_kind(a: Dictionary) -> String:
	match str(a.get("type", "")):
		"sub":
			return "defend"
		"takedown", "sweep":
			return "base"
	return "frame"

## u answers t's cast with a counter of `kind`. The right counter stops it cold (+1 Grip); the
## wrong one only buys a little time.
func _counter(u: Unit, t: Unit, kind: String) -> void:
	if t == null or t.cast.is_empty():
		return
	var ab: Dictionary = t.cast.ab
	if counter_kind(ab) == kind:
		t.cast = {}
		t.cds[ab.get("id", "")] = maxf(float(t.cds.get(ab.get("id", ""), 0.0)), 4.0)
		_aura(t, "framed", 1.5, u)
		u.grip = mini(u.max_grip, u.grip + 1)
		emit({"t": "interrupt", "u": u, "target": t, "ab": ab, "text": "%s!" % KIND_VERB[kind]})
	elif kind == "frame":
		t.cast.dur = float(t.cast.dur) + 0.7
		emit({"t": "miss", "u": u, "target": t, "text": "Wrong counter: %s it! [%s]" % [KIND_VERB[counter_kind(ab)], KIND_KEY[counter_kind(ab)]]})

const POINTS := {"guard": 2, "half": 2, "side": 3, "mount": 4, "back": 4}

## Moves the pair along the position graph after technique `mv` by u against t.
func _transition(u: Unit, t: Unit, mv: String, a: Dictionary) -> void:
	if t == null or mv == "":
		return
	var e := t if u.player else u
	if e.player:
		return
	var newpos := ""
	var u_top := false
	if mv == "@stand":
		newpos = "standing"
	else:
		var r = Data.MOVES.get(mv, {}).get("result", "")
		if not r is Array:
			return
		newpos = str(r[0])
		u_top = bool(r[1])
	var player_top := u_top if u.player else not u_top
	if newpos == e.gpos and (player_top == e.ptop or newpos == "standing"):
		return
	var pts := 0
	if u_top and newpos != "standing" and str(a.get("type", "")) != "escape":
		pts = int(POINTS.get(newpos, 0))
		if newpos == "side" and str(a.get("type", "")) != "pass":
			pts = 2
	e.gpos = newpos
	e.ptop = player_top
	emit({"t": "position", "e": e, "pos": newpos, "ptop": player_top, "by": u, "pts": pts, "move": mv})

## Back to standing (target switched, someone walked off, a tap...).
func stand_up(e: Unit) -> void:
	if e != null and not e.player and e.gpos != "standing":
		e.gpos = "standing"
		e.ptop = false
		emit({"t": "position", "e": e, "pos": "standing", "ptop": false, "by": e, "pts": 0, "move": ""})

func _extra(u: Unit, aura: String) -> float:
	return float(u.mods.get("aura_dur", {}).get(aura, 0.0)) if u.player else 0.0

func _type_bonus(u: Unit, a: Dictionary) -> float:
	if not u.player:
		return 1.0
	var m := u.mods
	var b := 1.0 + float(m.get("zone", {}).get(str(a.type), 0.0)) + float(m.get("zone_move", {}).get(str(a.get("move", "")), 0.0))
	b += float(m.get("dmg_all", 0.0)) + float(m.get("ab_dmg", {}).get(str(a.get("id", "")), 0.0))
	b += float(m.get("zone_role", {}).get(str(a.get("role", "any")), 0.0)) * 0.5
	return b

func _damage(src: Unit, t: Unit, amount: float, crit: bool, a: Dictionary) -> void:
	var dm := dom(src, t)
	if dm != 0:
		amount *= 1.0 + 0.08 * dm if dm > 0 else 1.0 / (1.0 - 0.08 * dm)
	if t.has("defending"):
		amount *= 0.8
	if t.has("base"):
		amount *= 0.5
	if t.has("ginga"):
		amount *= 0.3
	if t.has("guarded"):
		amount *= 0.6
	if src.has("pinned"):
		amount *= 0.75
	if t.player:
		amount *= 1.0 - clampf(float(t.mods.get("dr", 0.0)), 0.0, 0.6)
		amount /= float(t.mods.get("defense", 1.0))
		amount /= float(t.mods.get("defense_vs", {}).get(str(a.get("type", "")), 1.0))
	amount = maxf(1.0, round(amount))
	t.hp -= amount
	engage(src, t)
	emit({"t": "dmg", "u": src, "target": t, "amount": amount, "crit": crit, "ab": a})
	if t.player and not t.second_wind_used and t.mods.get("second_wind", false) and t.pct() < 0.2 and t.hp > 0.0:
		t.second_wind_used = true
		_heal(t, t.max_hp * 0.25, t)
		emit({"t": "proc", "u": t, "text": "Second Wind!"})
	if t.hp <= 0.0:
		t.hp = 0.0
		t.dead = true
		t.cast = {}
		var how := src.last_sub if bool(a.get("finisher", false)) else ""
		emit({"t": "tap", "u": t, "by": src, "sub": how})
		if src.player and not t.player:
			src.gas = minf(src.max_gas, src.gas + float(src.mods.get("tap_gas", 0.0)))
			_heal(src, src.max_hp * float(src.mods.get("tap_heal", 0.0)), src)
			if src.mods.get("tap_reset", false):
				src.cds.clear()
		if not t.player:
			_check_ooc(src)

func _heal(u: Unit, amount: float, src: Unit) -> void:
	var before := u.hp
	u.hp = minf(u.max_hp, u.hp + amount)
	if u.hp - before >= 1.0:
		emit({"t": "heal", "u": src, "target": u, "amount": round(u.hp - before)})

func _aura(u: Unit, name: String, dur: float, src: Unit) -> void:
	var fresh := not u.auras.has(name)
	u.auras[name] = {"t": dur, "dur": dur, "src": src}
	if name == "down":
		u.cast = {}
	emit({"t": "aura", "u": u, "aura": name, "dur": dur, "fresh": fresh})

func _check_ooc(p: Unit) -> void:
	if engaged_enemies().is_empty():
		leave_combat(p)

# ------------------------------------------------------------ tick
func tick(delta: float) -> void:
	for u in units.duplicate():
		if u.dead:
			continue
		_tick_unit(u, delta)

func _tick_unit(u: Unit, delta: float) -> void:
	u.gcd = maxf(0.0, u.gcd - delta)
	for k in u.cds.keys():
		u.cds[k] = float(u.cds[k]) - delta
		if u.cds[k] <= 0.0:
			u.cds.erase(k)
	for k in u.auras.keys():
		u.auras[k].t = float(u.auras[k].t) - delta
		if u.auras[k].t <= 0.0:
			u.auras.erase(k)
			emit({"t": "aura_off", "u": u, "aura": k})
	u.gas = minf(u.max_gas, u.gas + u.gas_regen * delta)
	if u.has("mate"):
		u.hp = minf(u.max_hp, u.hp + u.max_hp * 0.25 / 6.0 * delta)
	if not u.in_combat:
		u.ooc_t += delta
		if u.ooc_t > OOC_DELAY and u.hp < u.max_hp:
			u.hp = minf(u.max_hp, u.hp + u.max_hp * (OOC_REGEN if u.player else 0.5) * delta)
		if u.player:
			u.grip = 0 if u.ooc_t > 6.0 else u.grip
		return
	u.ooc_t = 0.0
	# casting
	if not u.cast.is_empty():
		var c: Dictionary = u.cast
		var t: Unit = c.target
		if u.down() or (t != null and t.dead):
			u.cast = {}
			emit({"t": "cast_stop", "u": u})
		else:
			c.t = float(c.t) + delta
			if float(c.t) >= float(c.dur):
				u.cast = {}
				emit({"t": "cast_stop", "u": u})
				if t != null and dist(u, t) <= float(c.ab.get("range", MELEE)) + 1.0:
					_resolve(u, c.ab, t)
				else:
					emit({"t": "miss", "u": u, "target": t, "text": "Out of range"})
	# auto attack (hand fighting)
	var tg := u.target
	if tg != null and not tg.dead and not u.down() and u.cast.is_empty() and dist(u, tg) <= MELEE:
		u.swing -= delta
		if u.swing <= 0.0:
			u.swing = u.swing_time / haste(u)
			var crit := rng.randf() < CRIT
			_damage(u, tg, u.auto_dmg * (CRIT_MULT if crit else 1.0) * rng.randf_range(0.85, 1.15), crit, {"id": "auto", "type": "auto", "name": "Hand fighting"})
			if u.player and rng.randf() < 0.25 + float(u.mods.get("auto_grip", 0.0)):
				u.grip = mini(u.max_grip, u.grip + 1)
	if not u.player:
		_ai(u, delta)

# ------------------------------------------------------------ enemy AI
func _ai(u: Unit, delta: float) -> void:
	var t := u.target
	if t == null or t.dead or u.down() or not u.cast.is_empty():
		return
	u.ai_t -= delta
	if u.ai_t > 0.0 or dist(u, t) > MELEE:
		return
	# grappling the player: real techniques from this position
	if t.player and (t.target == u or u.gpos != "standing"):
		var mv := _ai_move(u, t)
		if mv != "":
			var why := use_ab(u, move_ability(mv), t)
			if why == "":
				u.ai_t = rng.randf_range(3.0, 5.5) * (0.75 if u.boss else 1.0)
				return
	# otherwise: the standing kit (hand fighting pressure)
	var ready: Array = u.abilities.filter(func(a): return block_reason(u, a, t) == "" and not bool(a.get("finisher", false)))
	if ready.is_empty():
		u.ai_t = 0.5
		return
	use(u, str(ready[rng.randi() % ready.size()].id), t)
	u.ai_t = rng.randf_range(3.5, 6.0) * (0.75 if u.boss else 1.0)

const E_CAST := {"takedown": 1.4, "sweep": 1.3, "pass": 1.5, "advance": 1.3, "back": 1.4, "sub": 2.2, "escape": 1.2, "guard": 0.9}
const E_DMG := {"takedown": 1.4, "sweep": 1.2, "pass": 1.2, "advance": 1.4, "back": 0.9, "sub": 1.3, "escape": 0.4, "guard": 0.3}

## An enemy's cast of technique mv (cast bar, damage, the position change on landing).
static func move_ability(mv: String) -> Dictionary:
	var m: Dictionary = Data.MOVES[mv]
	var t := str(m.type)
	var a := {"id": "m_" + mv, "name": str(m.name), "type": t, "cast": float(E_CAST.get(t, 1.3)), "cd": 0.0, "cost": 0.0,
		"dmg": float(E_DMG.get(t, 1.0)) * (1.0 + 0.03 * int(m.get("diff", 0))), "grip": 0 if t == "sub" else 1, "_mv": mv}
	if t == "sub":
		a["finisher"] = true
		a["per_grip"] = 0.45
	if t == "takedown":
		a["effect"] = "down"
		a["dur"] = 1.2
	return a

## What an enemy goes for from its spot: escape or sweep from underneath, pass and climb on top,
## submit when it has the grips and you're fading.
func _ai_move(u: Unit, t: Unit) -> String:
	var top := not u.ptop
	var role := "top" if top else "bottom"
	var cap := u.rank + (3 if u.boss else 1)
	var picks: Array = []
	var total := 0.0
	for mv in Data.MOVES:
		var m: Dictionary = Data.MOVES[mv]
		if m.has("spec") or int(m.get("rank", 0)) > cap or str(m.pos) != u.gpos:
			continue
		if u.gpos != "standing" and str(m.role) != "any" and str(m.role) != role:
			continue
		var tp := str(m.type)
		if not tp in POSITIONAL:
			continue
		var w := 1.0
		match tp:
			"sub":
				w = 0.0 if u.grip < 1 else (3.0 if t.pct() < 0.5 or dom(u, t) >= 2 else 0.8)
			"escape", "sweep":
				w = 3.0 if not top else 1.0
			"pass", "advance", "back":
				w = 2.5
			"takedown":
				w = 2.0
			"guard":
				w = 0.7
		if w <= 0.0:
			continue
		picks.append([mv, w])
		total += w
	if picks.is_empty():
		return ""
	var r := rng.randf() * total
	for p in picks:
		r -= float(p[1])
		if r <= 0.0:
			return str(p[0])
	return str(picks[-1][0])
