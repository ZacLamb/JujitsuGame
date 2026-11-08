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
	u.max_hp = (140.0 + 18.0 * level) * float(mods.get("hp_mult", 1.0))
	u.hp = u.max_hp
	u.max_gas = float(mods.get("stamina_max", 100.0))
	u.gas = u.max_gas
	u.gas_regen = 15.0 * float(mods.get("regen", 1.0))
	u.dmg = dmg_scale(level)
	u.auto_dmg = u.dmg * 0.8
	u.swing_time = 2.0
	u.abilities = abilities
	return _add(u)

## Enemy from a mob or opponent dict. kind: "mob" | "named" | "boss".
func add_enemy(d: Dictionary, kind: String) -> Unit:
	var u := Unit.new()
	u.data = d
	u.name = str(d.get("name", "?"))
	u.level = Data.display_level(float(d.get("level", 1.0)))
	u.elite = bool(d.get("elite", false)) or kind != "mob"
	u.boss = kind == "boss" or bool(d.get("rare", false))
	var hm := 1.0
	var dm := 1.0
	if bool(d.get("rare", false)):
		hm = 2.6
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

## Why `a` can't be used on `t` right now ("" = ok). Shown as a red WoW-style error.
func block_reason(u: Unit, a: Dictionary, t: Unit) -> String:
	if a.is_empty():
		return "Not learned yet"
	if u.dead:
		return "You tapped"
	if u.down() and str(a.type) != "escape":
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
	var needs := str(a.get("needs", ""))
	if needs == "control" and t != null and not (t.down() or t.has("pinned")):
		return "They must be down or pinned"
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
	var a := ability(u, id)
	if t == null:
		t = u.target
	var why := block_reason(u, a, t)
	if why != "":
		return why
	if bool(a.get("harm", true)):
		engage(u, t)
		u.target = t
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
			return
		"guard":
			_aura(u, "guarded", float(a.get("dur", 6.0)) + _extra(u, "guarded"), u)
			return
		"breathe":
			u.gas = minf(u.max_gas, u.gas + 45.0)
			_heal(u, u.max_hp * (0.5 if not u.in_combat else 0.08), u)
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
			return
		"interrupt":
			if t and not t.cast.is_empty():
				var ab: Dictionary = t.cast.ab
				t.cast = {}
				t.cds[ab.id] = maxf(float(t.cds.get(ab.id, 0.0)), 4.0)
				_aura(t, "framed", 2.0, u)
				emit({"t": "interrupt", "u": u, "target": t, "ab": ab})
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
	if t.has("base"):
		amount *= 0.5
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
	# pick: finish when the player is low, else the best ready special
	var ready: Array = u.abilities.filter(func(a): return block_reason(u, a, t) == "")
	if ready.is_empty():
		u.ai_t = 0.5
		return
	var pick: Dictionary = ready[0]
	for a in ready:
		if bool(a.get("finisher", false)) and t.pct() < 0.45:
			pick = a
			break
		if not bool(a.get("finisher", false)) and rng.randf() < 0.6:
			pick = a
	if bool(pick.get("finisher", false)) and t.pct() >= 0.45:
		u.ai_t = 0.6
		return
	use(u, str(pick.id), t)
	u.ai_t = rng.randf_range(3.5, 6.0) * (0.75 if u.boss else 1.0)
