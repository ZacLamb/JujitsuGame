class_name Abilities
extends RefCounted
## Turns the grappling move list into a WoW-style action bar. Each move TYPE is one button whose
## name and strength come from the best move of that type you know (rank), so learning a new
## technique upgrades the button. Enemies get a small kit from their style.

## type -> template. dmg multiplies the attacker's damage scale; grip = combo points gained.
const TEMPLATES := {
	"handfight": {"label": "Hand Fight", "cost": 15.0, "cd": 0.0, "dmg": 0.8, "grip": 1,
		"text": "Fight for grips: steady damage and +1 Grip. Your filler."},
	"takedown": {"label": "Takedown", "cost": 30.0, "cd": 12.0, "dmg": 1.0, "grip": 1, "effect": "down", "dur": 2.0,
		"text": "Take them down: damage, +1 Grip and they're Down (stunned) for %ss."},
	"sweep": {"label": "Sweep", "cost": 25.0, "cd": 10.0, "dmg": 0.9, "grip": 1, "effect": "down", "dur": 1.5,
		"text": "Off-balance and sweep: damage, +1 Grip, Down for %ss."},
	"pass": {"label": "Guard Pass", "cost": 25.0, "cd": 8.0, "dmg": 0.95, "grip": 1, "effect": "pin", "dur": 6.0,
		"text": "Pass and pin: damage, +1 Grip. Pinned for %ss: they deal 25%% less."},
	"advance": {"label": "Advance", "cost": 30.0, "cd": 9.0, "dmg": 1.35, "grip": 2,
		"text": "Climb to a better position: heavy damage and +2 Grip."},
	"back": {"label": "Back Take", "cost": 25.0, "cd": 15.0, "dmg": 0.6, "grip": 2, "effect": "expose", "dur": 8.0,
		"text": "Take the back: +2 Grip. Exposed for %ss: your crit chance on them +25%%."},
	"sub": {"label": "Submission", "cost": 25.0, "cd": 0.0, "cast": 1.2, "dmg": 0.6, "per_grip": 0.6, "finisher": true,
		"text": "Finisher. Spends all Grip: the more Grip, the harder it lands. A 1.2s cast."},
	"escape": {"label": "Escape", "cost": 20.0, "cd": 20.0, "harm": false, "effect": "escape", "gcd": false,
		"text": "Usable while Down. Breaks Down / Pinned / Exposed, restores 12% Composure, +1 Grip."},
	"guard": {"label": "Pull Guard", "cost": 15.0, "cd": 20.0, "harm": false, "effect": "guard", "dur": 6.0,
		"text": "Pull guard and tie them up: you take 40% less damage for %ss."},
}
## Bar order reads like a game plan: grip, take them down, submit, then the tools you earn.
const ORDER := ["handfight", "takedown", "sub", "pass", "escape", "sweep", "back", "guard", "advance", "spec"]
const KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

## Level each ability unlocks at (WoW: you learn spells as you level). The bar fills itself as
## they unlock and the player can rearrange it from the spellbook.
## Easy to learn: level 1 is the whole game in miniature (grip, takedown, submit, sprawl); every
## level after adds one idea.
const UNLOCK := {"handfight": 1, "takedown": 1, "sub": 1, "base": 1, "defend": 2, "breathe": 2, "pass": 3, "frame": 4,
	"racial": 4, "escape": 4, "sweep": 5, "back": 6, "guard": 7, "advance": 8, "spec": 10}
const UTILITY := ["base", "frame", "defend", "breathe", "racial"]
const UTILITY_KEYS := {"base": "Q", "frame": "R", "defend": "T", "breathe": "F", "racial": "G"}
## How each ability teaches itself the first time you get it.
const TUTORIAL := {
	"handfight": "Target someone (Tab or click) and press 1 to fight for grips. It wears them down and builds Grip (the red dots under your bars).",
	"takedown": "2 takes the fight to the ground with you on top. Positions matter: climb guard, half, side, mount, back and you hit harder.",
	"sub": "3 is how a roll ends. Wear them down until their bar is empty, then submit. When it locks in, mash 3 to SQUEEZE until they tap. Only a submission makes someone tap; more Grip makes it go deeper.",
	"base": "When they shoot a takedown, SPRAWL! flashes in the middle of the screen. Hit Q in time: they're stopped and off-balance. Guess wrong (or mash it) and your counters lock for a moment.",
	"defend": "When they lock a submission, DEFEND! flashes: hit T. Get worn down and they WILL go for the finish, so watch for it.",
	"breathe": "F recovers Gas. Out of combat it also restores Composure.",
	"pass": "4 passes their guard: you climb to side control and they're Pinned (they hit 25% softer).",
	"frame": "When they try to pass or change position, FRAME! flashes: hit R. Now every technique has one right answer: Q, R or T. Read it, don't guess.",
	"escape": "5 gets you out from underneath: side control to guard, mount to half guard, or back to your feet.",
	"sweep": "6 reverses them from the bottom: you end up on top.",
	"back": "7 takes the back: +2 Grip and they're Exposed (you crit them more). The best place to finish from.",
	"guard": "8 pulls guard: you take 40% less damage for a while.",
	"advance": "9 climbs to a better position (side control to mount). Big damage and +2 Grip.",
	"spec": "Your specialization's signature technique.",
	"racial": "Your origin's special ability, on G.",
}

static func _all_kit() -> Array:
	var out: Array = []
	var best := {}
	for id in Data.MOVES:
		var m: Dictionary = Data.MOVES[id]
		if m.has("spec") or not Game.knows(id):
			continue
		var t := str(m.type)
		if not TEMPLATES.has(t):
			continue
		if not best.has(t) or int(m.get("rank", 0)) >= int(Data.MOVES[best[t]].get("rank", 0)):
			best[t] = id
	for t in ORDER:
		var a := {}
		if t == "handfight":
			a = _make("handfight", "", Game.style)
		elif t == "spec":
			var s := Specs.get_spec(Game.spec)
			if not s.is_empty():
				a = _spec_ability(s)
		elif best.has(t):
			a = _make(t, best[t], Game.style)
		if not a.is_empty():
			out.append(a)
	out.append({"id": "base", "name": "Sprawl / Base", "type": "defend", "key": "Q", "cost": 0.0, "cd": 0.0, "harm": false, "gcd": false,
		"effect": "base", "text": "Read it: when they shoot a TAKEDOWN or SWEEP, Sprawl. They're stopped and off-balance, you get Grip and Gas. Guess wrong and your counters lock for a moment."})
	out.append({"id": "frame", "name": "Frame", "type": "defend", "key": "R", "cost": 0.0, "cd": 0.0, "harm": false, "gcd": false,
		"effect": "interrupt", "text": "Read it: when they go for a PASS or a position, Frame. They're stopped and off-balance, you get Grip and Gas. Guess wrong and your counters lock for a moment."})
	out.append({"id": "defend", "name": "Defend", "type": "defend", "key": "T", "cost": 0.0, "cd": 0.0, "harm": false, "gcd": false,
		"effect": "defend", "text": "Read it: when they lock a SUBMISSION, Defend. They're stopped and off-balance, you get Grip and Gas. Guess wrong and your counters lock for a moment."})
	out.append({"id": "breathe", "name": "Breathe", "type": "defend", "key": "F", "cost": 0.0, "cd": 45.0, "harm": false,
		"effect": "breathe", "text": "Slow your breathing: +45 Gas. Out of combat it also restores half your Composure."})
	if Game.style != "":
		out.append(Origins.racial(Game.origin))
	for a in out:
		a["unlock"] = int(UNLOCK.get(str(a.id), 1))
	return out

## Techniques the player knows, strongest first (what the position buttons pick from).
static func known_moves() -> Array:
	var known: Array = []
	for id in Data.MOVES:
		if not Data.MOVES[id].has("spec") and Game.knows(id):
			known.append(id)
	known.sort_custom(func(x, y): return int(Data.MOVES[x].get("rank", 0)) > int(Data.MOVES[y].get("rank", 0)))
	return known

## Abilities you have right now (your spellbook / what the bar can hold).
static func player_kit() -> Array:
	var lv := Game.player_level()
	return _all_kit().filter(func(a): return int(a.unlock) <= lv)

## Abilities still to come, greyed out in the spellbook (WoW shows future spells).
static func future_kit() -> Array:
	var lv := Game.player_level()
	return _all_kit().filter(func(a): return int(a.unlock) > lv)

static func _make(t: String, move_id: String, style: String) -> Dictionary:
	var tp: Dictionary = TEMPLATES[t]
	var a := tp.duplicate(true)
	a["id"] = t
	a["type"] = t
	a["move"] = move_id
	if move_id != "":
		var m: Dictionary = Data.MOVES[move_id]
		a["name"] = str(m.name)
		a["role"] = str(m.get("role", "any"))
		# higher-rank techniques hit a little harder (talent techniques, rank 99, count as belt 12)
		var rk := int(m.get("rank", 0))
		rk = 12 if rk >= 99 else mini(rk, 24)
		a["dmg"] = float(a.get("dmg", 0.0)) * (1.0 + 0.02 * rk + 0.03 * int(m.get("diff", 0)))
	else:
		a["name"] = {"guard": "Collar & Sleeve", "wrestler": "Underhooks", "judoka": "Kumikata", "athlete": "Hand Fighting", "passer": "Grip Break"}.get(style, "Hand Fight")
	a["text"] = str(a.text).replace("%ss", "%ss" % str(a.get("dur", ""))).replace("%%", "%")
	return a

static func _spec_ability(s: Dictionary) -> Dictionary:
	if str(s.id) == "professor":
		return {"id": "spec", "type": "advice", "name": Specs.ADVICE_NAME, "cost": 0.0, "cd": 30.0, "harm": false,
			"gcd": true, "effect": "advice", "dmg": 0.0, "grip": 0,
			"text": "Your corner calls it: heal 20% Composure, +30 Gas, and Game Plan (+15% damage) for 10s. Works while Down or Pinned."}
	var m: Dictionary = Data.MOVES.get(str(s.move), {})
	var t := str(m.get("type", "sub"))
	var a := {"id": "spec", "type": t, "move": str(s.move), "name": str(m.get("name", s.name)), "cost": 30.0, "cd": 30.0,
		"dmg": 1.6, "grip": 2, "text": Tx.f("%s signature. Big damage and +2 Grip.", str(s.name))}
	match t:
		"sub":
			a.merge({"finisher": true, "cast": 0.8, "dmg": 0.9, "per_grip": 0.75, "grip": 0,
				"text": Tx.f("%s signature finisher: a fast 0.8s cast that hits harder per Grip.", str(s.name))}, true)
		"takedown", "sweep":
			a.merge({"effect": "down", "dur": 2.5}, true)
			a.text = Tx.f("%s signature: big damage, +2 Grip, Down for 2.5s.", str(s.name))
		"pass", "advance":
			a.merge({"effect": "pin", "dur": 8.0}, true)
			a.text = Tx.f("%s signature: big damage, +2 Grip, Pinned for 8s.", str(s.name))
		"back":
			a.merge({"effect": "expose", "dur": 10.0}, true)
			a.text = Tx.f("%s signature: big damage, +2 Grip, Exposed for 10s.", str(s.name))
		"escape":
			a.merge({"harm": false, "effect": "escape", "dmg": 0.0, "gcd": false}, true)
			a.text = Tx.f("%s signature: break free and recover.", str(s.name))
	return a

## Enemy kit: a takedown-ish opener, a pressure move and a submission finisher (bosses get more).
static func enemy_kit(d: Dictionary, elite: bool, boss: bool) -> Array:
	var st := str(d.get("style", "balanced"))
	var kit: Array = []
	var td := {"wrestler": "Double-Leg Takedown", "judoka": "Osoto Gari", "guard": "Scissor Sweep", "athlete": "Single-Leg Takedown", "passer": "Knee Cut"}
	kit.append({"id": "e_take", "name": td.get(st, "Takedown"), "type": "takedown", "cost": 0.0, "cd": 11.0, "cast": 1.4,
		"dmg": 1.5, "grip": 2, "effect": "down", "dur": 1.4})
	kit.append({"id": "e_press", "name": "Heavy Pressure" if st in ["passer", "wrestler"] else "Grip Break", "type": "pass",
		"cost": 0.0, "cd": 8.0, "dmg": 1.15, "grip": 1, "effect": "pin" if elite else "", "dur": 5.0})
	var subs := {"guard": "Triangle Choke", "wrestler": "Guillotine", "judoka": "Cross Collar Choke", "athlete": "Straight Ankle Lock", "passer": "Americana"}
	kit.append({"id": "e_sub", "name": subs.get(st, "Rear Naked Choke"), "type": "sub", "cost": 0.0, "cd": 14.0, "cast": 2.2,
		"dmg": 1.6, "per_grip": 0.5, "finisher": true})
	if boss:
		kit.append({"id": "e_burst", "name": "Scramble", "type": "sweep", "cost": 0.0, "cd": 16.0, "cast": 0.0, "dmg": 2.2, "grip": 2})
	for a in kit:
		a["gcd"] = true
	return kit

## Tooltip lines for an ability: [[text, color], ...] (HUD renders with Wow fonts).
static func tip_lines(a: Dictionary, u, core = null, t = null) -> Array:
	var out: Array = []
	if core != null and u != null and str(a.get("type", "")) in CombatCore.POSITIONAL:
		var mv: String = core.move_for(u, a, t)
		var pi: Array = core.pos_info(u, t)
		var here := CombatCore.pos_label(str(pi[0]), bool(pi[1]))
		if mv == "":
			out.append([Tx.f("%s: nothing from %s", [str(TEMPLATES.get(str(a.type), {}).get("label", a.type)), here]), Wow.RED, 15])
		elif mv == "@stand":
			out.append(["Scramble Up", Wow.WHITE, 16])
			out.append([Tx.f("From %s: back to your feet", here), Wow.GREEN, 12])
		else:
			var m: Dictionary = Data.MOVES[mv]
			out.append([str(m.name), Wow.WHITE, 16])
			var res = m.result
			var to := "submission" if not res is Array else CombatCore.pos_label(str(res[0]), bool(res[1]))
			out.append([Tx.f("From %s  →  %s", [here, to]), Wow.GREEN, 12])
	else:
		out.append([str(a.get("name", "")), Wow.WHITE, 16])
	var lab := str(TEMPLATES.get(str(a.get("type", "")), {}).get("label", str(a.get("type", "")).capitalize()))
	if str(a.get("id", "")) == "spec":
		lab = "Spec Signature"
	out.append([lab, Wow.GOLD, 12])
	var bits: Array = []
	if float(a.get("cost", 0.0)) > 0.0:
		bits.append(Tx.f("%d Gas", int(a.cost)))
	if float(a.get("cast", 0.0)) > 0.0:
		bits.append(Tx.f("%.1f sec cast", float(a.cast)))
	else:
		bits.append("Instant")
	if float(a.get("cd", 0.0)) > 0.0:
		bits.append(Tx.f("%d sec cooldown", int(a.cd)))
	if bool(a.get("harm", true)):
		bits.append("Melee range")
	out.append([" · ".join(bits), Wow.PALE, 12])
	if u != null and float(a.get("dmg", 0.0)) > 0.0:
		var bonus: float = core._type_bonus(u, a) if core != null else 1.0
		var lo := int(u.dmg * float(a.dmg) * bonus)
		if bool(a.get("finisher", false)):
			out.append([Tx.f("Hits for %d, +%d per Grip (you have %d).", [lo, int(u.dmg * float(a.get("per_grip", 0.9)) * bonus), u.grip]), Wow.GREEN, 13])
		else:
			out.append([Tx.f("Hits for about %d.", lo), Wow.GREEN, 13])
		if u.player:
			out.append(["Grows with your level, Strength and gear.", Wow.GREY, 11])
	out.append([str(a.get("text", "")), Wow.GOLD.lerp(Wow.WHITE, 0.6), 13])
	return out
