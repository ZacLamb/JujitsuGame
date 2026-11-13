class_name Pvp
extends Node
## Live duels between two real players (any faction; cross-faction wins count for the Faction War).
##
## The challenger's game is the HOST: it runs the real fight in its CombatCore, with the other
## player as an enemy unit that has no AI (flag "remote") and the guest's real numbers ("pvp_peer").
## The GUEST's game only mirrors it: its CombatCore is a puppet (no logic), its button presses go
## to the host as resolved techniques, and the host sends back snapshots (10/s) plus the combat
## events, so both screens show the same fight with the same animations, numbers and positions.
##
## Messages (relayed by the server, see world.js 'duel'): inv / acc / dec / go / act / s / e / bye.

signal finished(won: bool, opp_name: String, cross: bool)

var duel_id := ""   # the host makes one per duel; both report it for the ranked ladder

const INVITE_TIMEOUT := 20.0
const LINK_TIMEOUT := 8.0
const SNAP_EVERY := 0.1

var main   # Main
var wc     # WorldCombat
var state := ""        # "" | "inviting" | "invited" | "host" | "guest"
var peer := 0          # the other player's net id
var peer_char := {}
var opp_npc: Npc = null
var opp: CombatCore.Unit = null
var _t := 0.0          # invite clock / last message from the peer
var _snap_t := 0.0
var _ended := false

func setup(m) -> void:
	main = m
	wc = m.combat
	Net.duel_msg.connect(_on_msg)
	Net.left.connect(func(id: int):
		if id == peer and state != "":
			_abort(Tx.f("%s left.", str(peer_char.get("name", "Your opponent")))))

func busy() -> bool:
	return state != ""

func is_guest() -> bool:
	return state == "guest"

func cross() -> bool:
	return str(peer_char.get("faction", "brasil")) != Game.faction()

# ------------------------------------------------------------ invites
func invite(id: int, ch: Dictionary) -> void:
	if busy():
		return
	if wc.me.in_combat:
		Game.toast.emit("Finish your fight first.", Color(1, 0.5, 0.4))
		return
	state = "inviting"
	peer = id
	peer_char = ch
	_t = INVITE_TIMEOUT
	Net.send_duel(peer, {"k": "inv", "char": Net.my_char()})
	Game.toast.emit(Tx.f("Duel challenge sent to %s...", str(ch.get("name", "?"))), Color(1, 0.85, 0.4))

func answer(accept: bool) -> void:
	if state != "invited":
		return
	if not accept or wc.me.in_combat:
		Net.send_duel(peer, {"k": "dec"})
		_reset()
		return
	Net.send_duel(peer, {"k": "acc", "stats": _my_stats()})
	_t = LINK_TIMEOUT

func _my_stats() -> Dictionary:
	var me: CombatCore.Unit = wc.me
	return {"mhp": me.max_hp, "dmg": me.dmg, "auto": me.auto_dmg, "mgas": me.max_gas, "regen": me.gas_regen, "swing": me.swing_time,
		"mods": me.mods, "lv": me.level, "name": Game.player_name}

# ------------------------------------------------------------ network
func _on_msg(from: int, d: Dictionary) -> void:
	var k := str(d.get("k", ""))
	if k == "inv":
		if busy() or wc.me.in_combat or main.hud.dialogue_open():
			Net.send_duel(from, {"k": "dec", "why": "busy"})
			return
		state = "invited"
		peer = from
		peer_char = d.get("char", {})
		_t = INVITE_TIMEOUT
		main.ask_duel(peer_char)
		return
	if from != peer:
		return
	_t = LINK_TIMEOUT
	match k:
		"dec":
			if state == "inviting":
				Game.toast.emit(Tx.f("%s declined%s.", [str(peer_char.get("name", "?")), " (busy)" if str(d.get("why", "")) == "busy" else ""]), Color(1, 0.6, 0.4))
				_reset()
		"acc":
			if state == "inviting":
				_start_host(d.get("stats", {}))
		"go":
			if state == "invited":
				duel_id = str(d.get("id", ""))
				_start_guest(d.get("stats", {}))
		"act":
			if state == "host" and opp != null and not opp.dead:
				var a: Dictionary = d.get("ab", {})
				var why: String = wc.core.use_ab(opp, a, wc.me)
				if why != "" and why != "gcd":
					Net.send_duel(peer, {"k": "err", "text": why})
		"sq":
			# the guest mashing in a finish (squeezing or escaping)
			if state == "host" and opp != null and wc.core.in_struggle(opp):
				wc.core.struggle_press(opp)
		"err":
			if state == "guest":
				wc._error(str(d.get("text", "")))
		"s":
			if state == "guest":
				_apply_snapshot(d)
		"e":
			if state == "guest":
				_replay(d.get("e", {}))
		"bye":
			if state == "host" or state == "guest":
				_abort(Tx.f("%s forfeited.", str(peer_char.get("name", "Your opponent"))), true)

func _process(delta: float) -> void:
	if state == "":
		return
	_t -= delta
	if _t <= 0.0:
		if state == "inviting":
			Game.toast.emit(Tx.f("%s didn't answer.", str(peer_char.get("name", "?"))), Color(1, 0.6, 0.4))
			_reset()
		elif state == "invited":
			main.hud._close_dialogue(false)
			_reset()
		else:
			_abort(Tx.f("Lost the connection to %s.", str(peer_char.get("name", "your opponent"))))
		return
	if state == "host" and opp != null:
		_snap_t -= delta
		if _snap_t <= 0.0:
			_snap_t = SNAP_EVERY
			Net.send_duel(peer, _snapshot())
	if state == "guest":
		# the guest keeps the host's fighter facing and chasing it locally (cosmetic)
		if opp != null:
			opp.in_combat = true
			opp.target = wc.me

# ------------------------------------------------------------ start
func _opp_dict(stats: Dictionary) -> Dictionary:
	var od: Dictionary = main.rival_opponent(peer_char)
	od["name"] = str(peer_char.get("name", "?"))
	od["title"] = Tx.f("%s · Live Duel", str(Origins.faction(str(peer_char.get("faction", "brasil"))).long))
	od["remote"] = true
	od["intro"] = "Oss."
	od["win"] = "Good roll."
	od["lose"] = "Oss. Respect."
	od["level"] = 1.0 + float(int(stats.get("lv", peer_char.get("level", 1))) - 1) * 0.55 / 2.0
	return od

func _spawn(stats: Dictionary, host: bool) -> void:
	_hide_remote(true)
	var od := _opp_dict(stats)
	if host:
		od["pvp_peer"] = true
	main.player.input_enabled = true
	opp_npc = wc.start_bout(od, "pvp", false)
	opp = wc.unit_for(opp_npc)
	opp.max_hp = float(stats.get("mhp", opp.max_hp))
	opp.hp = opp.max_hp
	opp.dmg = float(stats.get("dmg", opp.dmg))
	opp.auto_dmg = float(stats.get("auto", opp.auto_dmg))
	opp.max_gas = float(stats.get("mgas", 100.0))
	opp.gas = opp.max_gas
	opp.gas_regen = float(stats.get("regen", 15.0))
	opp.swing_time = float(stats.get("swing", 2.0))
	opp.mods = stats.get("mods", {}) if host else {}
	opp.level = int(stats.get("lv", opp.level))
	opp.elite = false
	opp.boss = false
	wc.me.hp = wc.me.max_hp
	wc.me.gas = wc.me.max_gas
	wc.me.grip = 0
	wc.me.cds.clear()
	wc.me.auras.clear()
	wc.core.engage(opp, wc.me)
	opp.target = wc.me
	wc.target = opp
	opp_npc.in_combat = true
	opp_npc.rig.combat_ready = true
	_ended = false
	Sfx.music("roll")
	main.hud.show_toast(Tx.f("DUEL: %s%s", [str(peer_char.get("name", "?")), "  ·  for %s!" % Origins.faction(Game.faction()).long if cross() else ""]), Color(1, 0.75, 0.3))

func _start_host(stats: Dictionary) -> void:
	state = "host"
	_t = LINK_TIMEOUT
	duel_id = "%x%x" % [randi(), Time.get_ticks_usec()]
	Net.send_duel(peer, {"k": "go", "stats": _my_stats(), "id": duel_id})
	wc.core.event.connect(_forward)
	_spawn(stats, true)

func _start_guest(stats: Dictionary) -> void:
	state = "guest"
	_t = LINK_TIMEOUT
	wc.core.puppet = true
	_spawn(stats, false)

# ------------------------------------------------------------ guest: presses go to the host
## Returns "" when the press was sent (or the reason it can't be used, shown like any error).
func guest_press(id: String) -> String:
	var core: CombatCore = wc.core
	var me: CombatCore.Unit = wc.me
	var a := core.ability(me, id)
	if a.is_empty():
		return "Not learned yet"
	var why := core.block_reason(me, a, opp)
	if why != "":
		return why
	a = a.duplicate()
	var mv := core.move_for(me, a, opp)
	if mv != "":
		a["_mv"] = mv
		if mv != "@stand" and Data.MOVES.has(mv):
			a["name"] = str(Data.MOVES[mv].name)
		elif mv == "@stand":
			a["name"] = "Technical Stand-Up"
	# the host runs it with the guest's own numbers: bake the cast time with our haste
	a["cast"] = float(a.get("cast", 0.0))
	Net.send_duel(peer, {"k": "act", "ab": a})
	me.gcd = CombatCore.GCD / core.haste(me) if bool(a.get("gcd", true)) else me.gcd   # local feel until the snapshot lands
	return ""

# ------------------------------------------------------------ host -> guest
static func _ser_unit(u: CombatCore.Unit) -> Dictionary:
	var au := {}
	for k in u.auras:
		au[k] = float(u.auras[k].get("t", 0.0))
	var c := {}
	if not u.cast.is_empty():
		var ab: Dictionary = u.cast.ab
		c = {"ab": {"id": ab.get("id", ""), "name": ab.get("name", ""), "type": ab.get("type", ""), "_mv": ab.get("_mv", ""), "finisher": ab.get("finisher", false)},
			"t": float(u.cast.t), "dur": float(u.cast.dur)}
	return {"hp": u.hp, "mhp": u.max_hp, "gas": u.gas, "mgas": u.max_gas, "grip": u.grip, "gcd": u.gcd, "cds": u.cds, "cast": c, "au": au,
		"dead": u.dead, "ic": u.in_combat}

func _snapshot() -> Dictionary:
	var snap := {"k": "s", "h": _ser_unit(wc.me), "g": _ser_unit(opp), "pos": opp.gpos, "ptop": opp.ptop}
	var st: Dictionary = wc.core.struggle
	if not st.is_empty() and _tag(st.atk) != "" and _tag(st.def) != "":
		snap["st"] = {"atk": _tag(st.atk), "m": float(st.meter)}
	return snap

## Guest: a press during the finish goes straight to the host.
func guest_squeeze() -> void:
	Net.send_duel(peer, {"k": "sq"})

## Host side: the guest is "g", the host is "h" (the guest maps them back to its own units).
func _tag(u) -> String:
	if u == null:
		return ""
	if u == wc.me:
		return "h"
	if u == opp:
		return "g"
	return ""

const KEYS := ["ab", "amount", "crit", "aura", "dur", "fresh", "pos", "ptop", "pts", "move", "text", "sub", "on", "tapped", "kind", "whiff"]

func _forward(e: Dictionary) -> void:
	if state != "host":
		return
	var out := {"t": e.t}
	for rk in ["u", "target", "e", "by"]:
		if e.has(rk):
			var tg := _tag(e[rk])
			if tg == "":
				return   # not about this duel
			out[rk] = tg
	for k in KEYS:
		if e.has(k):
			var v = e[k]
			if v is Dictionary:
				v = (v as Dictionary).duplicate()
				v.erase("target")
			out[k] = v
	Net.send_duel(peer, {"k": "e", "e": out})

# ------------------------------------------------------------ guest: mirror
func _unit(tag: String) -> CombatCore.Unit:
	return wc.me if tag == "g" else (opp if tag == "h" else null)

func _apply_unit(u: CombatCore.Unit, s: Dictionary, other: CombatCore.Unit) -> void:
	u.hp = float(s.get("hp", u.hp))
	u.max_hp = float(s.get("mhp", u.max_hp))
	u.gas = float(s.get("gas", u.gas))
	u.max_gas = float(s.get("mgas", u.max_gas))
	u.grip = int(s.get("grip", u.grip))
	u.gcd = float(s.get("gcd", 0.0))
	u.cds = (s.get("cds", {}) as Dictionary).duplicate()
	var au := {}
	for k in s.get("au", {}):
		var t := float(s.au[k])
		au[k] = {"t": t, "dur": t, "src": other}
	u.auras = au
	var c: Dictionary = s.get("cast", {})
	u.cast = {} if c.is_empty() else {"ab": c.ab, "t": float(c.t), "dur": float(c.dur), "target": other}
	u.in_combat = bool(s.get("ic", true))

func _apply_snapshot(d: Dictionary) -> void:
	if opp == null or _ended:
		return
	_apply_unit(wc.me, d.get("g", {}), opp)
	_apply_unit(opp, d.get("h", {}), wc.me)
	opp.gpos = str(d.get("pos", "standing"))
	opp.ptop = not bool(d.get("ptop", false))
	# mirror the finish so the guest sees SQUEEZE / ESCAPE and its meter
	var st: Dictionary = d.get("st", {})
	if st.is_empty():
		wc.core.struggle = {}
	else:
		var atk: CombatCore.Unit = _unit(str(st.atk))
		var def: CombatCore.Unit = wc.me if atk == opp else opp
		wc.core.struggle = {"atk": atk, "def": def, "ab": {}, "meter": float(st.m), "t": 0.0, "dur": CombatCore.STRUGGLE_DUR}

func _replay(e: Dictionary) -> void:
	if opp == null or _ended:
		return
	var out := {"t": str(e.get("t", ""))}
	for rk in ["u", "target", "e", "by"]:
		if e.has(rk):
			out[rk] = _unit(str(e[rk]))
	for k in KEYS:
		if e.has(k):
			out[k] = e[k]
	if out.t == "position":
		out["ptop"] = not bool(e.get("ptop", false))
		opp.gpos = str(e.get("pos", "standing"))
		opp.ptop = bool(out.ptop)
	if out.t == "cast" and out.get("u") != null:
		var cu: CombatCore.Unit = out.u
		cu.cast = {"ab": out.get("ab", {}), "t": 0.0, "dur": float(out.get("dur", 1.0)), "target": out.get("target")}
	if out.t == "tap":
		var v: CombatCore.Unit = out.get("u")
		if v:
			v.dead = true
			v.hp = 0.0
			v.cast = {}
	if out.get("u") == null and str(e.get("u", "")) != "":
		return
	wc.core.emit(out)

# ------------------------------------------------------------ the end
## WorldCombat finished the "pvp" bout (a tap on either screen).
func on_bout_over(won: bool, forfeit := false) -> void:
	if state != "host" and state != "guest":
		return
	if _ended:
		return
	if forfeit:
		Net.send_duel(peer, {"k": "bye"})   # we left the mat: they win
	_ended = true
	var nm := str(peer_char.get("name", "?"))
	var cr := cross()
	_cleanup()
	finished.emit(won, nm, cr)

func _abort(msg: String, they_forfeited := false) -> void:
	if state == "host" or state == "guest":
		Game.toast.emit(msg, Color(1, 0.6, 0.4))
		var nm := str(peer_char.get("name", "?"))
		var cr := cross()
		if opp_npc and is_instance_valid(opp_npc) and opp != null and wc.core.units.has(opp):
			_ended = true
			wc._finish_bout(opp_npc, opp, they_forfeited, "", not they_forfeited)
		if not _ended:
			_ended = true
		_cleanup()
		if they_forfeited:
			finished.emit(true, nm, cr)
		wc.core.leave_combat(wc.me)
	_reset()

func forfeit() -> void:
	if state == "host" or state == "guest":
		Net.send_duel(peer, {"k": "bye"})
		_abort("You walked away from the duel.")

func _cleanup() -> void:
	if state == "host" and wc.core.event.is_connected(_forward):
		wc.core.event.disconnect(_forward)
	wc.core.puppet = false
	wc.me.dead = false
	wc.me.hp = maxf(wc.me.hp, wc.me.max_hp * 0.5)
	_hide_remote(false)
	_reset()

func _reset() -> void:
	state = ""
	opp = null
	opp_npc = null

func _hide_remote(hide: bool) -> void:
	var rp = main.remotes.get(peer)
	if rp and is_instance_valid(rp):
		rp.visible = not hide
