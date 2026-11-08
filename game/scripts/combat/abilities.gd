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
	"advance": {"label": "Advance", "cost": 30.0, "cd": 9.0, "dmg": 1.35, "grip": 2, "needs": "control",
		"text": "Climb to mount: heavy damage and +2 Grip. Only on a Down or Pinned target."},
	"back": {"label": "Back Take", "cost": 25.0, "cd": 15.0, "dmg": 0.6, "grip": 2, "effect": "expose", "dur": 8.0,
		"text": "Take the back: +2 Grip. Exposed for %ss: your crit chance on them +25%%."},
	"sub": {"label": "Submission", "cost": 25.0, "cd": 0.0, "cast": 1.2, "dmg": 0.6, "per_grip": 0.6, "finisher": true,
		"text": "Finisher. Spends all Grip: the more Grip, the harder it lands. A 1.2s cast."},
	"escape": {"label": "Escape", "cost": 20.0, "cd": 20.0, "harm": false, "effect": "escape", "gcd": false,
		"text": "Usable while Down. Breaks Down / Pinned / Exposed, restores 12% Composure, +1 Grip."},
	"guard": {"label": "Pull Guard", "cost": 15.0, "cd": 20.0, "harm": false, "effect": "guard", "dur": 6.0,
		"text": "Pull guard and tie them up: you take 40% less damage for %ss."},
}
const ORDER := ["handfight", "takedown", "sweep", "pass", "advance", "back", "sub", "spec", "escape", "guard"]
const KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

## The player's bar: ten slots (an empty dict = not learned yet) + Base / Frame / Breathe utilities.
static func player_kit() -> Array:
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
	for i in ORDER.size():
		var t: String = ORDER[i]
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
			a["key"] = KEYS[i]
		out.append(a)
	out.append({"id": "base", "name": "Base", "type": "defend", "key": "Q", "cost": 0.0, "cd": 30.0, "harm": false, "gcd": false,
		"effect": "base", "dur": 5.0, "text": "Get your base: take 50% less damage for 5s."})
	out.append({"id": "frame", "name": "Frame", "type": "defend", "key": "R", "cost": 10.0, "cd": 12.0, "gcd": false,
		"effect": "interrupt", "text": "Frame and stop whatever they're casting. Interrupts the cast and locks it out for 4s."})
	out.append({"id": "breathe", "name": "Breathe", "type": "defend", "key": "F", "cost": 0.0, "cd": 45.0, "harm": false,
		"effect": "breathe", "text": "Slow your breathing: +45 Gas. Out of combat it also restores half your Composure."})
	return out

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
		# higher-rank techniques hit a little harder
		a["dmg"] = float(a.get("dmg", 0.0)) * (1.0 + 0.04 * int(m.get("rank", 0)) + 0.03 * int(m.get("diff", 0)))
	else:
		a["name"] = {"guard": "Collar & Sleeve", "wrestler": "Underhooks", "judoka": "Kumikata", "athlete": "Hand Fighting", "passer": "Grip Break"}.get(style, "Hand Fight")
	a["text"] = str(a.text).replace("%ss", "%ss" % str(a.get("dur", ""))).replace("%%", "%")
	return a

static func _spec_ability(s: Dictionary) -> Dictionary:
	var m: Dictionary = Data.MOVES.get(str(s.move), {})
	var t := str(m.get("type", "sub"))
	var a := {"id": "spec", "type": t, "move": str(s.move), "name": str(m.get("name", s.name)), "cost": 30.0, "cd": 30.0,
		"dmg": 1.6, "grip": 2, "text": "%s signature. Big damage and +2 Grip." % str(s.name)}
	match t:
		"sub":
			a.merge({"finisher": true, "cast": 0.8, "dmg": 0.9, "per_grip": 0.75, "grip": 0,
				"text": "%s signature finisher: a fast 0.8s cast that hits harder per Grip." % str(s.name)}, true)
		"takedown", "sweep":
			a.merge({"effect": "down", "dur": 2.5}, true)
			a.text = "%s signature: big damage, +2 Grip, Down for 2.5s." % str(s.name)
		"pass", "advance":
			a.merge({"effect": "pin", "dur": 8.0}, true)
			a.text = "%s signature: big damage, +2 Grip, Pinned for 8s." % str(s.name)
		"back":
			a.merge({"effect": "expose", "dur": 10.0}, true)
			a.text = "%s signature: big damage, +2 Grip, Exposed for 10s." % str(s.name)
		"escape":
			a.merge({"harm": false, "effect": "escape", "dmg": 0.0, "gcd": false}, true)
			a.text = "%s signature: break free and recover." % str(s.name)
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
static func tip_lines(a: Dictionary, u) -> Array:
	var out: Array = []
	out.append([str(a.get("name", "")), Wow.WHITE, 16])
	var lab := str(TEMPLATES.get(str(a.get("type", "")), {}).get("label", str(a.get("type", "")).capitalize()))
	if str(a.get("id", "")) == "spec":
		lab = "Spec Signature"
	out.append([lab, Wow.GOLD, 12])
	var bits: Array = []
	if float(a.get("cost", 0.0)) > 0.0:
		bits.append("%d Gas" % int(a.cost))
	if float(a.get("cast", 0.0)) > 0.0:
		bits.append("%.1f sec cast" % float(a.cast))
	else:
		bits.append("Instant")
	if float(a.get("cd", 0.0)) > 0.0:
		bits.append("%d sec cooldown" % int(a.cd))
	if bool(a.get("harm", true)):
		bits.append("Melee range")
	out.append([" · ".join(bits), Wow.PALE, 12])
	if u != null and float(a.get("dmg", 0.0)) > 0.0:
		var lo := int(u.dmg * float(a.dmg))
		if bool(a.get("finisher", false)):
			out.append(["Hits for %d, +%d per Grip (you have %d)." % [lo, int(u.dmg * float(a.get("per_grip", 0.9))), u.grip], Wow.GREEN, 13])
		else:
			out.append(["Hits for about %d." % lo, Wow.GREEN, 13])
	out.append([str(a.get("text", "")), Wow.GOLD.lerp(Wow.WHITE, 0.6), 13])
	return out
