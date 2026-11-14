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
	var ally := false              # AI party member (raids): fights on the player's side
	var role := ""                 # ally role: "tank" / "heal" / "dps"
	var threat := {}               # enemies: unit id -> threat (raids: who the boss attacks)
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
	var seen := {}                 # enemies: how often the player went for each technique type
	var last_type := ""            # enemies: the player's last technique type against them
	var lunge := 0                 # enemies: shots you slipped in a row (each makes the next reach further)
	var approach := 0.0            # player: how fast you're closing on your target (m/s, smoothed)
	var _last_d := -1.0
	var boss_id := ""              # zone bosses (Data.BOSS): signature + second phase
	var sig_t := 9.0               # seconds until the signature is ready
	var phase := 1
	var _stall := 0                # enemies: AI ticks with nothing to do from this position
	var style := ""                # player: guard / wrestler / judoka / athlete / passer
	var crush_t := 0.0             # player (passer): time the target has been under the pin
	var done := 0.0                # damage dealt this fight (the meter)
	var rival := false             # a named fighter who has rolled with you before (remembers your game)

	func has(a: String) -> bool:
		return auras.has(a)
	func down() -> bool:
		return auras.has("down")
	func pct() -> float:
		return hp / max_hp

var units: Array = []
## Live duels: the guest's game only mirrors the host's fight (no logic runs, snapshots drive it).
var puppet := false
var gi := true                # the roll is in the gi (collar / lapel techniques exist); set by WorldCombat

## A unit with a real player's numbers: you, or (live duels, on the host) the other human.
static func pm(u: Unit) -> bool:
	return u.player or bool(u.data.get("pvp_peer", false))
var player: Unit = null
var _next_id := 1
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()

# ------------------------------------------------------------ units
const HP_GROWTH := 0.05
const DMG_GROWTH := 0.045
const HP_CURVE := 0.0009
const ENEMY_DMG := 1.25
const MOB_HP := 1.5

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
	u.style = Game.style
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
	u.boss_id = str(d.get("boss_id", ""))
	# normal mobs last long enough for a few reads (see tests/audit_core.gd); raid units keep the
	# numbers the raid was tuned with
	var raid_unit := bool(d.get("raid", false))
	var hm := 1.0 if raid_unit else MOB_HP
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
		dm = 1.65
	# your first roll (Rafa) is a lesson: normal strength, slower, and he only shoots takedowns
	if bool(d.get("tutor", false)):
		u.elite = false
		hm = MOB_HP
		dm = 0.85
	# enemies keep pace with a typical character of their level (talents, attributes, gear grow
	# the player multiplicatively; see tests/test_balance.gd)
	var lvf := float(u.level - 1)
	# past the first few levels a player's talents and gear outgrow plain mobs; keep them honest
	if kind == "mob" and not u.elite and not raid_unit:
		var over := maxf(0.0, float(u.level) - 3.0)
		hm *= 1.0 + 0.025 * over
		dm *= 1.0 + 0.035 * over
	u.max_hp = (110.0 + 26.0 * u.level) * hm * (1.0 + HP_GROWTH * lvf + HP_CURVE * lvf * lvf)
	u.hp = u.max_hp
	u.dmg = dmg_scale(u.level) * dm * ENEMY_DMG * (1.0 + DMG_GROWTH * lvf)
	u.auto_dmg = u.dmg * 0.5
	u.swing_time = 1.8
	u.abilities = Abilities.enemy_kit(d, u.elite, u.boss)
	u.ai_t = rng.randf_range(1.2, 2.4)
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
	return units.filter(func(o): return not o.player and not o.ally and not o.dead and o.in_combat)

static func friendly(u: Unit) -> bool:
	return u != null and (u.player or u.ally)

## An AI party member (raids). d: {name, level}. role: tank / heal / dps.
func add_ally(d: Dictionary, role: String, level: int) -> Unit:
	var u := Unit.new()
	u.ally = true
	u.role = role
	u.data = d
	u.name = str(d.get("name", "Ally"))
	u.level = level
	var hm: float = {"tank": 1.6, "heal": 0.9, "dps": 1.0}.get(role, 1.0)
	u.max_hp = (140.0 + 18.0 * level) * hm * (1.0 + 0.035 * (level - 1))
	u.hp = u.max_hp
	u.dmg = dmg_scale(level) * (1.0 + 0.03 * (level - 1)) * {"tank": 0.6, "heal": 0.35, "dps": 1.0}.get(role, 1.0)
	u.auto_dmg = u.dmg * 0.7
	u.swing_time = 2.0
	u.max_gas = 100.0
	u.gas = 100.0
	u.gas_regen = 18.0
	u.ai_t = rng.randf_range(0.5, 1.5)
	return _add(u)

## Who an enemy should be fighting: the friendly unit with the most threat on it.
func _top_threat(u: Unit) -> Unit:
	var best: Unit = null
	var bt := -1.0
	for o in units:
		if not friendly(o) or o.dead:
			continue
		var th := float(u.threat.get(o.id, 0.0))
		if th > bt:
			bt = th
			best = o
	return best

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
	_escapes.erase(u.id)
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
	if pm(u):
		var m := u.mods
		c += float(m.get("cost_add", {}).get(str(a.get("id", "")), 0.0))
		c *= float(m.get("cost", 1.0)) * (1.0 - float(m.get("cost_mult", 0.0)))
		if str(a.get("move", "")) in m.get("free_moves", []):
			c = 0.0
		if bool(a.get("finisher", false)) and m.get("free_sub", false):
			c = 0.0
		if u.has("overdrive"):
			c = 0.0
		if str(a.get("type", "")) in OPENING_TYPES and (u.has("opening") or u.has("relentless")):
			c = 0.0
	return maxf(c, 0.0)

func cd_of(u: Unit, a: Dictionary) -> float:
	var c := float(a.get("cd", 0.0))
	if pm(u):
		if str(a.get("type", "")) == "escape" and u.mods.get("scramble", false):
			c *= 0.5
		c *= 1.0 - float(u.mods.get("cd", {}).get(str(a.get("id", "")), 0.0))
		if str(a.get("id", "")) == "spec":
			pass
		c *= 1.0 - float(u.mods.get("cd", {}).get(str(a.get("type", "")), 0.0)) if str(a.get("type", "")) != str(a.get("id", "")) else 1.0
		if u.has("relentless") and str(a.get("type", "")) in OPENING_TYPES:
			c = 0.0
	return maxf(c, 0.0)

func haste(u: Unit) -> float:
	if not pm(u):
		return 1.0
	var h := float(u.mods.get("decision", 1.0))
	if u.has("tempo"):
		h *= 1.0 + TEMPO_HASTE * int(u.auras.tempo.get("n", 1))
	if u.has("overdrive"):
		h *= 1.0 + OVERDRIVE_HASTE
	return h

# ------------------------------------------------------------ the rotation: procs, bursts, styles
## OPENING (everyone): Hand Fight sometimes finds an opening. Your next positional technique is
## free and off cooldown: the button lights up. This is what you watch your bar for.
## BURST (V, level 6, 90s): one big button per style.
## And each style plays its own way:
##   wrestler  Chain Wrestling: a correct Sprawl resets Takedown (re-shot).   Burst: Relentless.
##   guard     Bottom Game: sweeps hit 20% harder and build +1 Grip.          Burst: Spider Web.
##   passer    Crush: +1 Grip every 3s your target stays Pinned.              Burst: Dead Weight.
##   judoka    Kuzushi: Hand Fight stacks Off-balance; a throw spends it.     Burst: Ippon.
##   athlete   Tempo: every technique you land speeds you up (5 stacks).      Burst: Overdrive.
const OPENING_TYPES := ["takedown", "sweep", "pass", "advance", "back"]
const OPENING_DUR := 8.0
var opening_chance := 0.25
const BURST_CD := 90.0
const BURST_DUR := 12.0
const BURST_LEVEL := 6
const TEMPO_HASTE := 0.04
const TEMPO_MAX := 5
const TEMPO_DUR := 4.0
const OVERDRIVE_HASTE := 0.3
const KUZUSHI_MAX := 3
const KUZUSHI_DUR := 10.0
const KUZUSHI_DMG := 0.2
const KUZUSHI_DOWN := 0.5
const CRUSH_EVERY := 3.0
const WEB_SLOW := 0.65
const WEB_DR := 0.7
const SWEEP_DMG := 1.2
const RESHOOT_DMG := 1.25
const BURST := {
	"wrestler": {"name": "Relentless", "text": "12s: takedowns, sweeps, passes and position changes cost no Gas and have no cooldown. Shoot, shoot again."},
	"guard": {"name": "Spider Web", "text": "12s: tie them up. Their techniques come 35% slower (easier to read) and you take 30% less."},
	"passer": {"name": "Dead Weight", "text": "All your weight on them: Pinned and Exposed for 12s, +2 Grip."},
	"judoka": {"name": "Ippon", "text": "Full Off-balance on your target, and your next throw is a certain critical."},
	"athlete": {"name": "Overdrive", "text": "12s: 30% faster and nothing costs Gas."},
}
const PASSIVE := {
	"wrestler": ["Chain Wrestling", "A correct Sprawl resets your Takedown and the re-shot hits 25% harder."],
	"guard": ["Bottom Game", "Sweeps hit 20% harder and build +1 Grip."],
	"passer": ["Crush", "+1 Grip every 3 seconds your target stays Pinned."],
	"judoka": ["Kuzushi", "Hand Fight stacks Off-balance (3). A throw spends it: +20% damage and a longer Down per stack."],
	"athlete": ["Tempo", "Each technique you land makes you 4% faster for 4s (5 stacks)."],
}

static func burst_ability(style: String) -> Dictionary:
	var b: Dictionary = BURST.get(style, BURST.athlete)
	return {"id": "burst", "name": str(b.name), "type": "burst", "key": "V", "cost": 0.0, "cd": BURST_CD, "harm": style == "passer",
		"gcd": false, "effect": "burst", "text": str(b.text)}

func _stack(u: Unit, name: String, dur: float, cap: int, src: Unit, add := 1) -> int:
	var n := mini(cap, (int(u.auras[name].get("n", 0)) if u.auras.has(name) else 0) + add)
	_aura(u, name, dur, src)
	u.auras[name]["n"] = n
	return n

func _drop(u: Unit, name: String) -> void:
	if u.auras.has(name):
		u.auras.erase(name)
		emit({"t": "aura_off", "u": u, "aura": name})

func _burst(u: Unit, t: Unit) -> void:
	var st := u.style if BURST.has(u.style) else "athlete"
	match st:
		"wrestler":
			_aura(u, "relentless", BURST_DUR, u)
			for k in OPENING_TYPES:
				u.cds.erase(k)
		"guard":
			_aura(u, "web", BURST_DUR, u)
		"passer":
			if t != null and not t.dead:
				_aura(t, "pinned", BURST_DUR, u)
				_aura(t, "exposed", BURST_DUR, u)
				u.grip = mini(u.max_grip, u.grip + 2)
		"judoka":
			_aura(u, "ippon", 15.0, u)
			if t != null and not t.dead and not t.player:
				_stack(t, "kuzushi", KUZUSHI_DUR + 5.0, KUZUSHI_MAX, u, KUZUSHI_MAX)
		_:
			_aura(u, "overdrive", BURST_DUR, u)
	emit({"t": "burst", "u": u, "style": st, "name": str(BURST[st].name)})
	emit({"t": "proc", "u": u, "text": "%s!" % Tx.s(str(BURST[st].name))})

## After the player lands a technique (not the auto hand fighting): procs and style stacks.
func _landed(u: Unit, a: Dictionary, t: Unit) -> void:
	var tp := str(a.get("type", ""))
	if tp == "handfight":
		if not u.has("opening") and rng.randf() < opening_chance:
			_aura(u, "opening", OPENING_DUR, u)
			for k in OPENING_TYPES:
				u.cds.erase(k)
			emit({"t": "proc", "u": u, "text": Tx.s("Opening!")})
			emit({"t": "opening", "u": u})
		if u.style == "judoka" and t != null and not t.dead:
			_stack(t, "kuzushi", KUZUSHI_DUR, KUZUSHI_MAX, u)
	if u.style == "athlete":
		_stack(u, "tempo", TEMPO_DUR, TEMPO_MAX, u)

# ------------------------------------------------------------ positions (the grappling layer)
## Every fight with your target has a position (standing, guard, half, side, mount, back) and a
## top / bottom. Techniques only work from where they belong, move you along the position graph,
## and dominant spots hit harder and take less.
const POSITIONAL := ["takedown", "sweep", "pass", "advance", "back", "sub", "escape", "guard"]
const DOM_STEP := 0.12   # damage per step of dominance (back on top: +48%)
const DOM := {"standing": 0, "guard": 1, "half": 1, "side": 2, "mount": 3, "back": 4}
const KIND_KEY := {"base": "Q", "frame": "R", "defend": "T"}
const KIND_VERB := {"base": "Sprawl", "frame": "Frame", "defend": "Defend"}
## What the counter is actually called for this technique: you sprawl on a shot, but you can't
## sprawl inside a guard (there you base out against the sweep); you frame a pass, hand-fight a
## back take, hip-escape a mount climb, and defend a submission.
static func counter_verb(a: Dictionary) -> String:
	match str(a.get("type", "")):
		"takedown":
			return "Sprawl"
		"sweep":
			return "Base out"
		"sub":
			return "Defend"
		"back":
			return "Hand fight"
		"advance":
			return "Hip escape"
		"guard":
			return "Posture"
		"escape":
			return "Stay heavy"
	return "Frame"

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
		if not gi and mv in Data.GI_ONLY:
			return false
		return not m.is_empty() and str(m.pos) == pos and (str(m.role) == "any" or str(m.role) == role or pos == "standing")
	if str(a.get("id", "")) == "spec":
		return str(a.move) if ok.call(str(a.move)) else ""
	# a live submission chain: the next link is already there
	if u.has("chain"):
		var nx := str(u.auras.chain.get("next", ""))
		if nx in u.known and str(Data.MOVES[nx].type) == tp and ok.call(nx):
			return nx
	for mv in u.known:
		if str(Data.MOVES[mv].type) == tp and ok.call(mv):
			return mv
	# scramble back up from underneath (never from on top: that would throw away your position)
	if tp == "escape" and pos != "standing" and not pi[1]:
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
	if in_struggle(u):
		return "Busy"
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
			return Tx.f("Not from %s", pos_label(str(pi[0]), bool(pi[1])))
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
			a["name"] = "Technical Stand-Up" if mv == "@stand" else str(Data.MOVES[mv].name)
		elif mv != "":
			a = a.duplicate()
			a["_mv"] = mv
	# the mind game goes both ways: they may be waiting for exactly this
	var tp := str(a.get("type", ""))
	var switched := ""
	if u.player and t != null and not t.player and tp in READ_BACK_TYPES:
		if t.has("expect"):
			var ex := str(t.auras.expect.get("type", ""))
			t.auras.erase("expect")
			emit({"t": "aura_off", "u": t, "aura": "expect"})
			if ex == tp and not (tp == "sub" and t.has("worn")):
				_stuffed(u, t, a)
				return ""
			if ex != tp:
				switched = ex
		_note_habit(u, t, tp)
	if switched != "":
		a = a.duplicate()
		a["dmg"] = float(a.get("dmg", 0.0)) * SWITCH_DMG
		emit({"t": "proc", "u": u, "text": Tx.f("Switch! They bit on the %s", Tx.s(str(Abilities.TEMPLATES.get(switched, {}).get("label", switched))))})
		emit({"t": "switch", "u": u, "target": t, "was": switched})
		_flow(u)
	if u.player and tp == "takedown" and u.approach >= MOMENTUM_SPEED and t != null and not t.player:
		a = a.duplicate()
		a["dmg"] = float(a.get("dmg", 0.0)) * MOMENTUM_DMG
		emit({"t": "proc", "u": u, "text": Tx.s("Momentum!")})
		emit({"t": "momentum", "u": u, "target": t})
	if u.player and t != null and not t.player:
		# style rules (see the rotation block above)
		if tp == "sweep" and u.style == "guard":
			a = a.duplicate()
			a["dmg"] = float(a.get("dmg", 0.0)) * SWEEP_DMG
			a["grip"] = int(a.get("grip", 0)) + 1
		if tp == "takedown":
			if u.has("reshoot"):
				a = a.duplicate()
				a["dmg"] = float(a.get("dmg", 0.0)) * RESHOOT_DMG
				_drop(u, "reshoot")
			if t.has("kuzushi"):
				var kz := int(t.auras.kuzushi.get("n", 1))
				a = a.duplicate()
				a["dmg"] = float(a.get("dmg", 0.0)) * (1.0 + KUZUSHI_DMG * kz)
				a["dur"] = float(a.get("dur", 1.8)) + KUZUSHI_DOWN * kz
				_drop(t, "kuzushi")
				emit({"t": "proc", "u": u, "text": Tx.f("Kuzushi x%d", kz)})
			if u.has("ippon"):
				a = a.duplicate()
				a["_crit"] = true
				_drop(u, "ippon")
	var chained := false
	if u.has("chain") and str(a.get("_mv", "")) != "" and str(a.get("_mv", "")) == str(u.auras.chain.get("next", "")):
		chained = true
		a = a.duplicate()
		a["dmg"] = float(a.get("dmg", 0.0)) * 1.25
		a["name"] = Tx.f("%s (chain)", str(a.get("name", "")))
		u.auras.erase("chain")
		emit({"t": "aura_off", "u": u, "aura": "chain"})
		emit({"t": "proc", "u": u, "text": Tx.f("Chain! %s", str(Data.MOVES[str(a._mv)].name))})
	u.gas -= cost_of(u, a)
	if u.player and tp in OPENING_TYPES:
		_drop(u, "opening")
	if bool(a.get("gcd", true)):
		u.gcd = GCD / haste(u)
	var ct := float(a.get("cast", 0.0)) / haste(u)
	if chained:
		ct *= 0.5
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
	if bool(a.get("sig", false)) and t != null and not t.dead:
		_aura(t, "rattled", 8.0, u)
		emit({"t": "sig_hit", "u": u, "target": t, "ab": a})
	if a.has("heal") and t != null and not t.dead:
		_heal(t, t.max_hp * float(a.heal), u)
		return
	match eff:
		"base", "defend":
			_read(u, eff)
			return
		"guard":
			_aura(u, "guarded", float(a.get("dur", 6.0)) + _extra(u, "guarded"), u)
			_transition(u, u.target, str(a.get("_mv", "")), a)
			return
		"burst":
			_burst(u, t if t != null else u.target)
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
			if pm(u):
				u.grip = mini(u.max_grip, u.grip + 1)
				u.gas = minf(u.max_gas, u.gas + float(u.mods.get("escape_gas", 0.0)))
			_transition(u, u.target if u.player else t, str(a.get("_mv", "")), a)
			return
		"interrupt":
			_read(u, "frame")
			return
	if t == null or t.dead:
		return
	# damage
	var mult := float(a.get("dmg", 0.0))
	if bool(a.get("finisher", false)):
		mult += float(a.get("per_grip", 0.9)) * u.grip
		if pm(u):
			mult *= 1.0 + float(u.mods.get("sub_start", 0.0)) + float(u.mods.get("sub_start_move", {}).get(str(a.get("move", "")), 0.0))
		if u.player and u.has("flow"):
			var fl := int(u.auras.flow.get("n", 1))
			mult *= 1.0 + FLOW_SUB * fl
			a = a.duplicate()
			a["flow"] = fl
			u.auras.erase("flow")
			emit({"t": "aura_off", "u": u, "aura": "flow"})
		u.last_sub = str(a.get("_mv", a.get("move", "sub"))) if not u.player else str(a.get("move", "sub"))
		u.grip = 0
	if mult > 0.0:
		var amount := u.dmg * mult * _type_bonus(u, a)
		var crit_c := CRIT + (0.25 if t.has("exposed") and t.auras.exposed.src == u else 0.0)
		if pm(u):
			var m := u.mods
			crit_c += (float(m.get("perfect", 1.0)) - 1.0) * 0.25 + float(m.get("crit", 0.0))
			crit_c = minf(crit_c, 0.4)
			if t.has("pinned"):
				amount *= 1.0 + float(m.get("pinned_vuln", 0.0))
			if t.down():
				amount *= 1.0 + float(m.get("down_dmg", 0.0))
			if t.pct() < 0.35:
				amount *= 1.0 + float(m.get("exec", 0.0))
		var crit := rng.randf() < crit_c or bool(a.get("_crit", false))
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
			amount *= CRIT_MULT + (0.5 * (float(u.mods.get("struggle_atk", 1.0)) - 1.0) if u.player else 0.0)
			if u.player and bool(a.get("finisher", false)):
				amount *= 1.0 + float(u.mods.get("sub_crit", 0.0))
		_damage(u, t, amount, crit, a)
	if t.dead:
		return
	if u.player:
		_landed(u, a, t)
	_start_chain(u, a)
	var g := int(a.get("grip", 0))
	if pm(u):
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
		var before := dom(u, t) if u.player else 0
		_transition(u, t, str(a.get("_mv", "")), a)
		if u.player and dom(u, t) > before:
			_flow(u)

## The counter for a technique: sprawl / base on takedowns and sweeps, frame on passes and
## positional moves, defend on submissions.
static func counter_kind(a: Dictionary) -> String:
	match str(a.get("type", "")):
		"sub":
			return "defend"
		"takedown", "sweep":
			return "base"
	return "frame"

## Counters are reads. Q Sprawl beats takedowns and sweeps, R Frame beats passes and positional
## moves, T Defend beats submissions. The right one REVERSES the technique: it's stopped, they're
## off-balance (Down) for a moment, and you get a Grip and some Gas back. The wrong one (or one
## pressed with nothing coming) is a WHIFF: all three counters lock for a moment and it costs Gas,
## so guessing or mashing them is worse than not countering at all.
const COUNTER_IDS := ["base", "frame", "defend"]
const COUNTER_CD := 2.5      # each counter after a success
const WHIFF_LOCK := 3.0      # all counters after a whiff
const WHIFF_GAS := 20.0

## The enemy (if any) casting a technique at u, the u.target first.
func _caster_at(u: Unit) -> Unit:
	if u.target != null and not u.target.dead and not u.target.cast.is_empty():
		return u.target
	for o in units:
		if o.dead or friendly(o) == friendly(u) or o.cast.is_empty():
			continue
		if o.cast.get("target") == u:
			return o
	return null

func _read(u: Unit, kind: String) -> void:
	var t := _caster_at(u)
	if t != null and counter_kind(t.cast.ab) == kind:
		_counter(u, t, kind)
		return
	# whiff: wrong read, or nothing to read
	for id in COUNTER_IDS:
		u.cds[id] = maxf(float(u.cds.get(id, 0.0)), WHIFF_LOCK)
	u.gas = maxf(0.0, u.gas - WHIFF_GAS)
	if u.has("flow"):
		u.auras.erase("flow")
		emit({"t": "aura_off", "u": u, "aura": "flow"})
	var txt := "Whiff!"
	if t != null:
		var right := counter_kind(t.cast.ab)
		txt = Tx.f("Wrong read: %s! [%s]", [Tx.s(counter_verb(t.cast.ab)), KIND_KEY[right]])
		# a wrong guess lets their technique in faster
		t.cast.t = maxf(float(t.cast.t), float(t.cast.dur) - 0.35)
	emit({"t": "miss", "u": u, "target": t, "text": txt, "whiff": true})

## u reads t's cast correctly: the reversal.
func _counter(u: Unit, t: Unit, kind: String) -> void:
	if t == null or t.cast.is_empty():
		return
	var ab: Dictionary = t.cast.ab
	t.cast = {}
	t.cds[ab.get("id", "")] = maxf(float(t.cds.get(ab.get("id", ""), 0.0)), 4.0)
	_aura(t, "down", 1.6 + _extra(u, "down"), u)
	u.grip = mini(u.max_grip, u.grip + 1)
	u.gas = minf(u.max_gas, u.gas + 12.0)
	u.cds[kind] = COUNTER_CD
	if kind == "base" and u.player and u.style == "wrestler" and float(ability(u, "takedown").get("cd", 0.0)) > 0.0:
		u.cds.erase("takedown")
		_aura(u, "reshoot", 6.0, u)
		emit({"t": "proc", "u": u, "text": Tx.s("Re-shot!")})
	if kind == "base":
		_aura(u, "base", 2.0 + _extra(u, "base"), u)
		if pm(u) and u.mods.get("base_grip", false):
			u.grip = mini(u.max_grip, u.grip + 2)
			u.gas = minf(u.max_gas, u.gas + 30.0)
	if bool(ab.get("sig", false)):
		# you read the signature: they're wide open
		_aura(t, "down", 3.2, u)
		_aura(t, "exposed", 8.0, u)
		u.grip = mini(u.max_grip, u.grip + 2)
		u.gas = minf(u.max_gas, u.gas + 25.0)
		emit({"t": "sig_read", "u": u, "target": t, "ab": ab})
	emit({"t": "interrupt", "u": u, "target": t, "ab": ab, "kind": kind, "text": "%s!" % Tx.s(counter_verb(ab))})
	emit({"t": "cast_stop", "u": t})
	# counter-to-counter: elites and bosses read your counter and flow into the next attack
	if not t.player and (t.elite or t.boss) and not bool(ab.get("sig", false)) and rng.randf() < (0.35 if t.boss else 0.2):
		var re := _recounter_move(t, str(ab.get("_mv", "")))
		if re != "":
			t.auras.erase("down")
			emit({"t": "aura_off", "u": t, "aura": "down"})
			var ra := move_ability(re)
			ra["cast"] = float(ra.cast) * 0.8
			ra["name"] = Tx.f("%s (re-counter)", str(ra.name))
			t.cast = {"ab": ra, "t": 0.0, "dur": float(ra.cast), "target": u}
			emit({"t": "proc", "u": t, "text": "Re-counter!"})
			emit({"t": "cast", "u": t, "ab": ra, "target": u, "dur": float(ra.cast)})

## ------------------------------------------------------------ distance on the feet
## Standing, range is a weapon. Step back out of reach as a shot comes in and it misses (a SLIP):
## safer than a read, but it earns nothing and each slip in a row makes their next shot reach further.
## Close the distance fast and shoot (MOMENTUM) and your takedown lands harder.
const SLIP_REACH := 0.9       # extra reach per slip in a row
const SLIP_MAX := 3
const SLIP_STUMBLE := 0.7
const MOMENTUM_SPEED := 2.4   # m/s closing speed
const MOMENTUM_DMG := 1.3

func _track_approach(delta: float) -> void:
	var p := player
	if p == null or p.target == null or p.target.dead or delta <= 0.0:
		if p:
			p.approach = 0.0
			p._last_d = -1.0
		return
	var d := dist(p, p.target)
	if p._last_d >= 0.0:
		p.approach = lerpf(p.approach, (p._last_d - d) / delta, clampf(delta * 8.0, 0.0, 1.0))
	p._last_d = d

## ------------------------------------------------------------ your offense
## FLOW: every technique that improves your position (or a switch that catches them guessing)
## within a few seconds of the last one stacks up, to 3. A submission spends it: harder, and the
## squeeze starts deeper. A technique of theirs landing, or a whiff, breaks it. Spamming one button
## never builds flow; climbing does.
const FLOW_DUR := 7.0
const FLOW_MAX := 3
const FLOW_SUB := 0.15        # submission damage per stack
## READ BACK: opponents notice what you keep going for. Repeat a technique type and they may get
## ready for it (shown on their frame: "Expecting: Pass"). Go for it anyway and it's stuffed; go
## for anything else and they bit on the wrong thing: a SWITCH (+damage, +flow).
const READ_BACK_TYPES := ["takedown", "sweep", "pass", "advance", "back", "sub"]
const SWITCH_DMG := 1.3
const READ_BACK_LEVEL := 6    # normal mobs start reading you once you have options to switch to

func _flow(u: Unit) -> void:
	var n := 1
	if u.has("flow"):
		n = mini(FLOW_MAX, int(u.auras.flow.get("n", 1)) + 1)
	_aura(u, "flow", FLOW_DUR, u)
	u.auras.flow["n"] = n
	if n >= 2:
		emit({"t": "proc", "u": u, "text": Tx.f("Flow x%d", n)})
		emit({"t": "chain", "u": u, "n": n})

## How likely t is to get ready for a technique you repeat (0 = never reads you).
func read_back_chance(t: Unit, u: Unit) -> float:
	if bool(t.data.get("practice", false)) or bool(t.data.get("tutor", false)) or bool(t.data.get("raid", false)):
		return 0.0
	if t.boss:
		return 0.9
	if t.rival:
		return 0.85
	if t.elite:
		return 0.6
	return 0.4 if u.level >= READ_BACK_LEVEL else 0.0

func _note_habit(u: Unit, t: Unit, tp: String) -> void:
	t.seen[tp] = int(t.seen.get(tp, 0)) + 1
	var repeat := t.last_type == tp or int(t.seen[tp]) >= 3
	t.last_type = tp
	if not repeat or t.has("expect") or tp == "sub" and t.has("worn"):
		return
	# rivals come in already knowing your favourite (see habit_prior)
	if rng.randf() >= read_back_chance(t, u):
		return
	_aura(t, "expect", 14.0, u)
	t.auras.expect["type"] = tp
	emit({"t": "expect", "u": t, "target": u, "type": tp})
	emit({"t": "proc", "u": t, "text": Tx.f("Reading you: %s", Tx.s(str(Abilities.TEMPLATES.get(tp, {}).get("label", tp))))})

## A rival who remembers how you beat them starts the fight already waiting for it.
func expect_now(t: Unit, tp: String) -> void:
	if tp == "" or not tp in READ_BACK_TYPES:
		return
	_aura(t, "expect", 14.0, player)
	t.auras.expect["type"] = tp
	emit({"t": "expect", "u": t, "target": player, "type": tp})

## They were ready for it: your technique is stuffed, you pay for it and they get a grip.
func _stuffed(u: Unit, t: Unit, a: Dictionary) -> void:
	u.gas = maxf(0.0, u.gas - cost_of(u, a))
	if bool(a.get("gcd", true)):
		u.gcd = GCD / haste(u)
	var cd := cd_of(u, a)
	if cd > 0.0:
		u.cds[a.id] = cd
	t.grip = mini(t.max_grip, t.grip + 1)
	_aura(u, "down", 0.9, t)
	if u.has("flow"):
		u.auras.erase("flow")
		emit({"t": "aura_off", "u": u, "aura": "flow"})
	emit({"t": "miss", "u": u, "target": t, "text": Tx.s("Stuffed! They saw it coming"), "stuffed": true, "ab": a})
	emit({"t": "stuffed", "u": t, "target": u, "ab": a})

## A submission that didn't end it opens the next link of its chain for a few seconds.
func _start_chain(u: Unit, a: Dictionary) -> void:
	var mv := str(a.get("_mv", ""))
	if not u.player or str(a.get("type", "")) != "sub" or not Data.CHAINS.has(mv):
		return
	var nx: String = Data.CHAINS[mv]
	if not nx in u.known:
		return
	_aura(u, "chain", 6.0, u)
	u.auras.chain["next"] = nx
	emit({"t": "proc", "u": u, "text": "%s → %s" % [str(Data.MOVES[mv].name), str(Data.MOVES[nx].name)]})

## An elite's answer to your counter: the classic follow-up (sprawl -> front headlock, frame -> back
## take, defended choke -> the chain's next sub), or any other technique from here.
func _recounter_move(t: Unit, countered: String) -> String:
	if Data.CHAINS.has(countered):
		var nx: String = Data.CHAINS[countered]
		if Data.MOVES.has(nx) and str(Data.MOVES[nx].pos) == t.gpos and (gi or not nx in Data.GI_ONLY) \
				and (t.gpos == "standing" or str(Data.MOVES[nx].role) in ["any", "bottom" if t.ptop else "top"]):
			return nx
	var ty := str(Data.MOVES.get(countered, {}).get("type", ""))
	var opts: Array = []
	for mv in Data.MOVES:
		var m: Dictionary = Data.MOVES[mv]
		if m.has("spec") or int(m.get("rank", 0)) > t.rank + 3 or str(m.pos) != t.gpos or str(m.type) == ty:
			continue
		if not gi and mv in Data.GI_ONLY:
			continue
		if not str(m.type) in POSITIONAL or str(m.type) == "escape":
			continue
		if t.gpos != "standing" and str(m.role) != "any" and str(m.role) != ("bottom" if t.ptop else "top"):
			continue
		opts.append(mv)
	return "" if opts.is_empty() else str(opts[rng.randi() % opts.size()])

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
	if not pm(u):
		return 1.0
	var m := u.mods
	var b := 1.0 + float(m.get("zone", {}).get(str(a.type), 0.0)) + float(m.get("zone_move", {}).get(str(a.get("move", "")), 0.0))
	b += float(m.get("dmg_all", 0.0)) + float(m.get("ab_dmg", {}).get(str(a.get("id", "")), 0.0))
	b += float(m.get("zone_role", {}).get(str(a.get("role", "any")), 0.0)) * 0.5
	return b

static var gm_god := false   # Game Master test tool: the player takes no damage

func _damage(src: Unit, t: Unit, amount: float, crit: bool, a: Dictionary) -> void:
	if gm_god and t.player:
		amount = 0.0
	if bool(t.data.get("practice", false)) or bool(src.data.get("practice", false)):
		emit({"t": "dmg", "u": src, "target": t, "amount": 0.0, "crit": false, "ab": a})
		return   # drilling: nobody gets hurt
	var dm := dom(src, t)
	if dm != 0:
		amount *= 1.0 + DOM_STEP * dm if dm > 0 else 1.0 / (1.0 - DOM_STEP * dm)
	if t.has("defending"):
		amount *= 0.8
	if t.has("base"):
		amount *= 0.5
	if t.has("ginga"):
		amount *= 0.3
	if t.has("guarded"):
		amount *= 0.6
	if t.has("web"):
		amount *= WEB_DR
	if src.has("pinned"):
		amount *= 0.75
	# turtles shell up: hard to hurt until you've passed (side / mount / back on top)
	if str(t.data.get("trait", "")) == "turtle" and friendly(src) and not (t.gpos in ["side", "mount", "back"] and t.ptop):
		amount *= 0.5
	if pm(t):
		amount *= 1.0 - clampf(float(t.mods.get("dr", 0.0)), 0.0, 0.6)
		amount /= float(t.mods.get("defense", 1.0))
		amount /= float(t.mods.get("defense_vs", {}).get(str(a.get("type", "")), 1.0))
	amount = maxf(1.0, round(amount))
	# only a submission makes someone tap: anything else wears them down to their last bit of
	# Composure, and then the next submission finishes it
	var fin := bool(a.get("finisher", false))
	var duel := pm(t) or pm(src)   # the rule is about YOUR rolls (raid partners and adds go down normally)
	if not duel:
		pass
	elif fin and not _resolving and (t.has("worn") or t.hp - amount < 1.0) and struggle.is_empty() and not t.dead:
		# the finish: a short squeeze-and-tap struggle instead of an instant tap
		_start_struggle(src, t, a)
		return
	elif fin and t.has("worn"):
		amount = maxf(amount, t.hp)
	elif not fin and t.hp - amount < 1.0:
		amount = maxf(0.0, t.hp - 1.0)
		if not t.has("worn"):
			_aura(t, "worn", 9999.0, src)
			emit({"t": "proc", "u": t, "text": "Worn down!"})
	t.hp -= amount
	src.done += amount
	if src.player and not t.player and str(a.get("id", "")) != "auto":
		t.lunge = 0
	if t.player and t.has("flow") and str(a.get("type", "")) in POSITIONAL:
		t.auras.erase("flow")
		emit({"t": "aura_off", "u": t, "aura": "flow"})
	if not friendly(t) and friendly(src):
		t.threat[src.id] = float(t.threat.get(src.id, 0.0)) + amount * (3.0 if src.role == "tank" else 1.0)
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
	if src != null and friendly(src):
		for e in units:
			if not friendly(e) and e.in_combat and not e.threat.is_empty():
				e.threat[src.id] = float(e.threat.get(src.id, 0.0)) + (u.hp - before) * 0.4
	if u.hp - before >= 1.0:
		emit({"t": "heal", "u": src, "target": u, "amount": round(u.hp - before)})
	if u.has("worn") and u.pct() > 0.08:
		u.auras.erase("worn")
		emit({"t": "aura_off", "u": u, "aura": "worn"})

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
	_track_approach(delta)
	if puppet:
		return
	if not struggle.is_empty():
		_tick_struggle(delta)
	for u in units.duplicate():
		if u.dead:
			continue
		if not struggle.is_empty() and (u == struggle.atk or u == struggle.def):
			continue   # locked together in the finish
		_tick_unit(u, delta)

# ------------------------------------------------------------ feints (depth for later levels)
## Elites and bosses sometimes FEINT: halfway through a technique they switch to one with a
## different counter (shoot -> pass, pass -> choke). Only once you know all three counters, and
## only once per technique. A fast read beats it; a slow one has to read again.
const FEINT_CHANCE := 0.3
const FEINT_CHANCE_BOSS := 0.4

func _maybe_feint(u: Unit, c: Dictionary) -> void:
	if u.player or c.has("feinted") or c.has("_nofeint") or not (u.elite or u.boss or bool(u.data.get("practice", false))):
		return
	var t: Unit = c.target
	if t == null or not t.player or float(c.t) < float(c.dur) * 0.45:
		return
	c["_nofeint"] = true   # decide once per technique
	for k in COUNTER_IDS:
		if ability(t, k).is_empty():
			return
	if rng.randf() > (FEINT_CHANCE_BOSS if u.boss else FEINT_CHANCE):
		return
	var kind := counter_kind(c.ab)
	var opts: Array = []
	var top := not u.ptop
	for mv in Data.MOVES:
		var m: Dictionary = Data.MOVES[mv]
		if m.has("spec") or str(m.pos) != u.gpos or not str(m.type) in POSITIONAL or str(m.type) == "escape":
			continue
		if u.gpos != "standing" and str(m.role) != "any" and str(m.role) != ("top" if top else "bottom"):
			continue
		if str(m.type) == "sub" and u.grip < 1 and not t.has("worn"):
			continue
		var ab := move_ability(mv)
		if counter_kind(ab) != kind:
			opts.append(ab)
	if opts.is_empty():
		return
	var na: Dictionary = opts[rng.randi() % opts.size()]
	na["name"] = Tx.f("%s (feint)", str(na.name))
	na["feint"] = true
	c.ab = na
	c["feinted"] = true
	c.t = float(c.dur) * 0.3
	emit({"t": "proc", "u": u, "text": "Feint!"})
	emit({"t": "feint", "u": u, "target": t, "ab": na})

# ------------------------------------------------------------ the finish (squeeze / escape)
## A submission that would end the roll becomes a short struggle. `meter` is how deep the
## submission is (0 = they escaped, 1 = tap). The attacker squeezes (mash), the defender fights
## it (mash); time running out goes to whoever is ahead. A player squeezing a normal enemy taps
## them even without mashing (easy to learn); elites and bosses fight back, so mash. When YOU are
## caught, mash to escape: you get out, heal a little and they're thrown off-balance.
var struggle := {}            # {atk, def, ab, meter, t, dur}
var _resolving := false       # applying a struggle's tap (don't start another)
var _escapes := {}            # unit id -> escapes this fight (reset when they leave combat)
const STRUGGLE_DUR := 3.0
const SQUEEZE_PRESS := 0.1    # meter per press (player squeezing)
const ESCAPE_PRESS := 0.065   # meter per press (player escaping)

func _start_struggle(atk: Unit, def: Unit, a: Dictionary) -> void:
	# every escape in the same fight makes the next one harder (you're tiring)
	var tired := int(_escapes.get(def.id, 0))
	var start := 0.4 + 0.04 * float(atk.grip) + 0.15 * tired + 0.07 * float(a.get("flow", 0))
	struggle = {"atk": atk, "def": def, "ab": a, "meter": clampf(start, 0.3, 0.85), "t": 0.0, "dur": STRUGGLE_DUR, "tired": tired}
	atk.cast = {}
	def.cast = {}
	emit({"t": "struggle", "u": atk, "target": def, "ab": a, "on": true})

## The defender's / attacker's automatic pressure per second (the side that isn't you).
func _struggle_rates() -> Vector2:
	var atk: Unit = struggle.atk
	var def: Unit = struggle.def
	var fill := 0.15                       # a submission sinks in on its own
	var drain := 0.0
	if pm(atk) and not pm(def):
		drain = 0.22 if def.boss else (0.13 if def.elite else 0.0)
	elif pm(def) and not pm(atk):
		fill = (0.42 if atk.boss else (0.34 if atk.elite else 0.27)) * (1.0 + 0.25 * float(struggle.get("tired", 0)))
	return Vector2(fill, drain)

## A press from a unit in the struggle (squeeze if attacking, fight it if defending).
func struggle_press(u: Unit) -> void:
	if struggle.is_empty():
		return
	if u == struggle.atk:
		struggle.meter = minf(1.0, float(struggle.meter) + SQUEEZE_PRESS)
	elif u == struggle.def:
		struggle.meter = maxf(0.0, float(struggle.meter) - ESCAPE_PRESS)

func in_struggle(u: Unit) -> bool:
	return not struggle.is_empty() and (u == struggle.atk or u == struggle.def)

func _tick_struggle(delta: float) -> void:
	var atk: Unit = struggle.atk
	var def: Unit = struggle.def
	if atk.dead or def.dead or not units.has(atk) or not units.has(def):
		struggle = {}
		return
	var r := _struggle_rates()
	struggle.t = float(struggle.t) + delta
	struggle.meter = clampf(float(struggle.meter) + (r.x - r.y) * delta, 0.0, 1.0)
	var m := float(struggle.meter)
	var over := float(struggle.t) >= float(struggle.dur)
	if m >= 1.0 or (over and m >= 0.5):
		_end_struggle(true)
	elif m <= 0.0 or over:
		_end_struggle(false)

func _end_struggle(tapped: bool) -> void:
	var atk: Unit = struggle.atk
	var def: Unit = struggle.def
	var a: Dictionary = struggle.ab
	struggle = {}
	emit({"t": "struggle", "u": atk, "target": def, "ab": a, "on": false, "tapped": tapped})
	if tapped:
		atk.last_sub = str(a.get("_mv", a.get("move", "sub")))
		def.auras.erase("worn")
		def.hp = 1.0
		_resolving = true
		_damage(atk, def, 1.0, false, a)
		_resolving = false
	else:
		# they fought it off: a breath back, and the attacker is off-balance
		def.auras.erase("worn")
		emit({"t": "aura_off", "u": def, "aura": "worn"})
		_escapes[def.id] = int(_escapes.get(def.id, 0)) + 1
		_heal(def, def.max_hp * 0.08, def)
		_aura(atk, "down", 1.2, def)
		emit({"t": "proc", "u": def, "text": "Escaped!"})

func _tick_unit(u: Unit, delta: float) -> void:
	if u.boss_id != "" and u.in_combat:
		u.sig_t = maxf(0.0, u.sig_t - delta)
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
			c.t = float(c.t) + delta * (WEB_SLOW if t != null and t.has("web") and not u.player else 1.0)
			_maybe_feint(u, c)
			if float(c.t) >= float(c.dur):
				u.cast = {}
				emit({"t": "cast_stop", "u": u})
				if t != null and dist(u, t) <= float(c.ab.get("range", MELEE)) + 1.0 + SLIP_REACH * u.lunge:
					u.lunge = 0
					_resolve(u, c.ab, t)
				elif t != null and t.player and not u.player and u.gpos == "standing":
					# you stepped out of range: the shot hits air. No reversal (that takes a read), but
					# they stumble for a beat, and their next shot reaches further so backing off forever fails
					u.lunge = mini(SLIP_MAX, u.lunge + 1)
					u.cds[c.ab.get("id", "")] = maxf(float(u.cds.get(c.ab.get("id", ""), 0.0)), 3.0)
					_aura(u, "down", SLIP_STUMBLE, t)
					u.ai_t = minf(u.ai_t, 1.4)
					emit({"t": "slip", "u": t, "target": u, "ab": c.ab})
					emit({"t": "miss", "u": u, "target": t, "text": "Out of range"})
				else:
					emit({"t": "miss", "u": u, "target": t, "text": "Out of range"})
	# passer: every few seconds under the pin is another grip
	if u.player and u.style == "passer":
		var pt := u.target
		if pt != null and not pt.dead and pt.has("pinned") and pt.auras.pinned.src == u:
			u.crush_t += delta
			if u.crush_t >= CRUSH_EVERY:
				u.crush_t = 0.0
				if u.grip < u.max_grip:
					u.grip += 1
					emit({"t": "proc", "u": u, "text": Tx.s("Crush: +1 Grip")})
		else:
			u.crush_t = 0.0
	# auto attack (hand fighting)
	var tg := u.target
	if tg != null and not tg.dead and not u.down() and u.cast.is_empty() and dist(u, tg) <= MELEE:
		u.swing -= delta
		if u.swing <= 0.0:
			u.swing = u.swing_time / haste(u)
			var crit := rng.randf() < CRIT
			_damage(u, tg, u.auto_dmg * (CRIT_MULT if crit else 1.0) * rng.randf_range(0.85, 1.15), crit, {"id": "auto", "type": "auto", "name": "Hand fighting"})
			if pm(u) and rng.randf() < 0.25 + float(u.mods.get("auto_grip", 0.0)):
				u.grip = mini(u.max_grip, u.grip + 1)
	if u.ally and not bool(u.data.get("remote", false)):
		_ally_ai(u, delta)
	elif not u.player and not bool(u.data.get("remote", false)):
		_ai(u, delta)

# ------------------------------------------------------------ party AI (raids)
func _ally_ai(u: Unit, delta: float) -> void:
	if u.down() or not u.cast.is_empty():
		return
	u.ai_t -= delta
	if u.ai_t > 0.0:
		return
	u.ai_t = rng.randf_range(0.9, 1.4)
	var foes := engaged_enemies()
	if foes.is_empty():
		return
	var boss: Unit = null
	for f in foes:
		if f.boss:
			boss = f
	match u.role:
		"heal":
			# mend the lowest friendly under 75%
			var low: Unit = null
			for o in units:
				if friendly(o) and not o.dead and o.pct() < 0.75 and (low == null or o.pct() < low.pct()):
					low = o
			if low != null and float(u.cds.get("mend", 0.0)) <= 0.0:
				u.cds["mend"] = 2.5
				var ab := {"id": "mend", "name": "Corner Advice", "type": "advice", "harm": false, "cast": 1.4, "heal": 0.22, "range": 40.0}
				u.cast = {"ab": ab, "t": 0.0, "dur": 1.4, "target": low}
				emit({"t": "cast", "u": u, "ab": ab, "target": low, "dur": 1.4})
				return
			u.target = boss if boss else foes[0]
		"tank":
			# hold the boss: taunt it back when it turns, Base on cooldown under pressure
			var tgt: Unit = boss if boss else foes[0]
			u.target = tgt
			if tgt.target != u and float(u.cds.get("taunt", 0.0)) <= 0.0:
				u.cds["taunt"] = 8.0
				var top := 0.0
				for k in tgt.threat:
					top = maxf(top, float(tgt.threat[k]))
				tgt.threat[u.id] = top * 1.1 + 50.0
				tgt.target = u
				emit({"t": "proc", "u": u, "text": "Taunt!"})
				return
			if u.pct() < 0.5 and not u.has("base") and float(u.cds.get("base", 0.0)) <= 0.0:
				u.cds["base"] = 15.0
				_aura(u, "base", 5.0, u)
				return
		_:
			# damage: adds first (they go for the healer), then the boss
			var add: Unit = null
			for f in foes:
				if not f.boss:
					add = f
			u.target = add if add else (boss if boss else foes[0])
	var t := u.target
	if t == null or t.dead or dist(u, t) > MELEE:
		return
	if float(u.cds.get("big", 0.0)) <= 0.0 and u.role != "heal":
		u.cds["big"] = 10.0
		var crit := rng.randf() < CRIT
		_damage(u, t, u.dmg * 2.2 * (CRIT_MULT if crit else 1.0), crit, {"id": "big", "type": "pass", "name": "Pressure Pass" if u.role == "tank" else "Takedown"})
	elif float(u.cds.get("hit", 0.0)) <= 0.0:
		u.cds["hit"] = 3.0
		_damage(u, t, u.dmg * 1.1, false, {"id": "hit", "type": "handfight", "name": "Grip Fight"})

# ------------------------------------------------------------ enemy AI
func _ai(u: Unit, delta: float) -> void:
	# raids: fight whoever has the most threat
	if not u.threat.is_empty():
		var top := _top_threat(u)
		if top != null and top != u.target and not u.has("taunted"):
			u.target = top
	var t := u.target
	if t == null or t.dead or u.down() or not u.cast.is_empty():
		return
	u.ai_t -= delta
	if u.ai_t > 0.0 or dist(u, t) > MELEE:
		return
	if bool(u.data.get("practice", false)):
		_practice_ai(u, t)
		return
	if u.boss_id != "" and t.player:
		if _boss_turn(u, t):
			return
	var pace: Vector2 = (AI_PACE_RAID if bool(u.data.get("raid", false)) and not u.boss else AI_PACE_BOSS if u.boss else (AI_PACE_ELITE if u.elite else AI_PACE)) * float(u.data.get("pace", 1.0)) * float(arch_of(u).get("pace", 1.0))
	# grappling the player: real techniques from this position
	if t.player and (t.target == u or u.gpos != "standing"):
		var mv := _ai_move(u, t)
		if mv != "":
			var why := use_ab(u, move_ability(mv), t)
			if why == "":
				u.ai_t = rng.randf_range(pace.x, pace.y)
				return
	# otherwise: the standing kit (hand fighting pressure)
	# the standing kit's takedown and standing choke make no sense once the fight is on the ground
	var grounded := u.gpos != "standing"
	var ready: Array = u.abilities.filter(func(a): return block_reason(u, a, t) == "" and (not bool(a.get("finisher", false)) or t.has("worn")) and _ai_allowed(u, t, str(a.get("type", ""))) \
		and not (grounded and str(a.get("type", "")) in ["takedown", "sub"] and not t.has("worn")))
	if ready.is_empty():
		u.ai_t = 0.5
		# nothing they know from here: they disengage and the roll restarts on the feet
		if grounded and t.player and not in_struggle(u) and not u.has("pinned"):
			u._stall += 1
			if u._stall >= 3:
				u._stall = 0
				stand_up(u)
				emit({"t": "proc", "u": u, "text": Tx.s("Back to the feet")})
				u.ai_t = 1.0
		return
	u._stall = 0
	use(u, str(ready[rng.randi() % ready.size()].id), t)
	u.ai_t = rng.randf_range(pace.x, pace.y)

## ------------------------------------------------------------ zone bosses
const SIG_CD := 20.0
const SIG_CAST := 2.6
const SIG_DMG := 2.4

## Phase two at half composure, and the signature technique. Returns true if the boss acted.
func _boss_turn(u: Unit, t: Unit) -> bool:
	var b: Dictionary = Data.BOSS.get(u.boss_id, {})
	if b.is_empty() or in_struggle(u):
		return false
	if u.phase == 1 and u.pct() <= 0.5:
		u.phase = 2
		for k in ["down", "pinned", "exposed", "expect"]:
			if u.auras.has(k):
				u.auras.erase(k)
				emit({"t": "aura_off", "u": u, "aura": k})
		stand_up(u)                       # they shake you off: back to the feet
		_heal(u, u.max_hp * 0.12, u)
		_aura(u, "rush", 12.0, u)
		u.grip = mini(u.max_grip, u.grip + 2)
		u.sig_t = 2.5
		u.ai_t = 2.0
		emit({"t": "phase", "u": u, "target": t, "text": str(b.get("phase", ""))})
		return true
	if u.sig_t > 0.0 or t.has("worn"):
		return false
	var mv := str(b.get("sig", ""))
	if not Data.MOVES.has(mv):
		return false
	# the signature starts from wherever its technique lives: the boss resets the position to get there
	var m: Dictionary = Data.MOVES[mv]
	if str(m.pos) != u.gpos or (u.gpos != "standing" and str(m.role) != "any" and str(m.role) != ("bottom" if u.ptop else "top")):
		if str(m.pos) == "standing":
			stand_up(u)
		else:
			u.gpos = str(m.pos)
			u.ptop = str(m.role) == "bottom"      # player on top when the boss attacks from the bottom
			emit({"t": "position", "e": u, "pos": u.gpos, "ptop": u.ptop, "by": u, "pts": 0, "move": ""})
	var a := move_ability(mv)
	a["name"] = str(b.get("sig_name", a.name))
	a["cast"] = SIG_CAST / (1.15 if u.phase == 2 else 1.0)
	a["dmg"] = SIG_DMG
	a["sig"] = true
	a["_nofeint"] = true
	if str(a.get("type", "")) == "sub":
		a["finisher"] = false             # a signature choke hurts and rattles; the tap still has to be earned
	u.sig_t = SIG_CD * (0.75 if u.phase == 2 else 1.0)
	u.cast = {"ab": a, "t": 0.0, "dur": float(a.cast), "target": t, "_nofeint": true}
	u.ai_t = rng.randf_range(AI_PACE_BOSS.x, AI_PACE_BOSS.y)
	emit({"t": "signature", "u": u, "target": t, "ab": a})
	emit({"t": "cast", "u": u, "ab": a, "target": t, "dur": float(a.cast)})
	return true

## Fighting styles: every enemy style has habits you learn to read. Weights multiply how often
## they go for each kind of technique; the target frame shows the name and a tip.
const ARCH := {
	"pressure": {"name": "Pressure Passer", "tip": "Smashes and pins: FRAME the passes", "w": {"pass": 3.0, "advance": 2.2, "takedown": 1.4, "sweep": 0.5, "guard": 0.0, "sub": 1.2}},
	"guard": {"name": "Guard Player", "tip": "Pulls guard and sweeps: SPRAWL the sweeps", "w": {"guard": 4.0, "sweep": 3.0, "escape": 1.6, "takedown": 0.3, "sub": 1.3}},
	"submission": {"name": "Sub Hunter", "tip": "Hunts submissions: be ready to DEFEND", "w": {"sub": 2.4, "back": 1.4, "pass": 0.8}, "sub_grip": 0},
	"back": {"name": "Back Taker", "tip": "Wants your back: FRAME the back takes", "w": {"back": 3.5, "sub": 1.2, "takedown": 1.2}},
	"wrestler": {"name": "Wrestler", "tip": "Shoots constantly: SPRAWL", "w": {"takedown": 3.2, "pass": 1.5, "advance": 1.5, "sub": 0.6, "guard": 0.0}, "pace": 0.85},
	"judoka": {"name": "Judoka", "tip": "Throws from the grips: SPRAWL", "w": {"takedown": 3.0, "sub": 1.0, "guard": 0.0}},
	"athlete": {"name": "Scrambler", "tip": "Fast and slippery: keep reading", "w": {"escape": 2.2, "sweep": 2.0, "takedown": 1.5}, "pace": 0.85},
	"passer": {"name": "Pressure Passer", "tip": "Smashes and pins: FRAME the passes", "w": {"pass": 3.0, "advance": 2.2, "takedown": 1.4, "sweep": 0.5, "guard": 0.0}},
}

static func arch_of(u: Unit) -> Dictionary:
	return ARCH.get(str(u.data.get("style", "balanced")), {})

## How often enemies attempt something (seconds between attempts).
const AI_PACE := Vector2(2.3, 3.3)
const AI_PACE_ELITE := Vector2(2.2, 3.2)
const AI_PACE_BOSS := Vector2(1.8, 2.8)
const AI_PACE_RAID := Vector2(3.0, 5.0)   # raid adds: the party's job is the boss

## The academy practice partner: techniques you can read, one every couple of seconds, any kind
## you know the counter for (and feints once you know all three).
func _practice_ai(u: Unit, t: Unit) -> void:
	if u.gpos != "standing":
		stand_up(u)   # reset between reps
	var kinds: Array = []
	for k in COUNTER_IDS:
		if not ability(t, k).is_empty():
			kinds.append(k)
	if kinds.is_empty():
		return
	var want: String = kinds[rng.randi() % kinds.size()]
	var opts: Array = []
	for mv in Data.MOVES:
		var m: Dictionary = Data.MOVES[mv]
		if m.has("spec") or not str(m.type) in POSITIONAL or str(m.type) == "escape" or int(m.get("rank", 0)) > 10:
			continue
		var ab := move_ability(mv)
		if counter_kind(ab) == want:
			opts.append(ab)
	if opts.is_empty():
		return
	var ab: Dictionary = opts[rng.randi() % opts.size()]
	ab["cast"] = float(ab.cast) * float(u.data.get("speed", 1.0))
	u.cast = {"ab": ab, "t": 0.0, "dur": float(ab.cast), "target": t}
	emit({"t": "cast", "u": u, "ab": ab, "target": t, "dur": float(ab.cast)})
	u.ai_t = rng.randf_range(0.7, 1.2)

## Easy to learn: a normal enemy only casts techniques the player has the counter for (a level 1
## player only ever has to Sprawl). Bosses, rares and other players use everything. A worn-down
## target can always be submitted.
func _ai_allowed(u: Unit, t: Unit, tp: String) -> bool:
	if u.boss or bool(u.data.get("rare", false)) or not t.player:
		return true
	if tp == "sub" and t.has("worn"):
		return true
	var need := ""
	match tp:
		"takedown", "sweep":
			need = "base"
		"sub":
			need = "defend"
		"pass", "advance", "back", "guard", "escape":
			need = "frame"
		_:
			return true
	return not ability(t, need).is_empty()

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
		if not gi and mv in Data.GI_ONLY:
			continue
		if u.gpos != "standing" and str(m.role) != "any" and str(m.role) != role:
			continue
		var tp := str(m.type)
		if not tp in POSITIONAL:
			continue
		if not _ai_allowed(u, t, tp):
			continue
		var w := 1.0
		match tp:
			"sub":
				w = 0.0 if u.grip < int(arch_of(u).get("sub_grip", 1)) and not t.has("worn") else (3.0 if t.pct() < 0.5 or dom(u, t) >= 2 else 0.8)
				if t.has("worn"):
					w = 20.0   # finish it
				if str(u.data.get("trait", "")) == "hunter":
					w = 0.0 if u.grip < 1 else w * 3.0
			"escape", "sweep":
				w = 3.0 if not top else 1.0
			"pass", "advance", "back":
				w = 2.5
			"takedown":
				w = 2.0
			"guard":
				w = 0.7
		w *= float(arch_of(u).get("w", {}).get(tp, 1.0))
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
