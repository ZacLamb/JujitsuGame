class_name Coop
extends Node
## Co-op dungeons and raids with your party (see Party). Same model as live duels (Pvp):
##
## The party LEADER's game is the HOST: it runs the real run (Raid) in its CombatCore. Each
## partner is an ally unit there with their own real numbers and no AI ("remote", "pvp_peer"),
## positioned from their live-world position. AI partners only fill the roles nobody real covers.
## Every GUEST's game mirrors it: its CombatCore is a puppet; the host sends spawns, snapshots
## (10/s: health, casts, auras, positions, targets) and the combat events, and the guest's
## presses go back to the host as resolved techniques.
##
## Messages (Party relay): dng / join / nojoin / go / act / tg / s / end / quit

const GATHER := 15.0      # the leader waits this long for answers
const LINK := 10.0        # no word from the other side for this long: out
const SNAP_EVERY := 0.1

var main
var wc   # WorldCombat
var party: Party
var state := ""          # "" | "gather" | "host" | "asked" | "wait" | "guest"
var kind := ""
var at := Vector3.ZERO
var lvl := 1
var host := 0            # guest: the leader's id
var my_uid := 0          # guest: my unit id in the host's game
var _t := 0.0
var _snap_t := 0.0

# host
var _joined := {}        # peer -> {role, stats, mob}
var _asked: Array = []
var _known := {}         # unit id -> true (already sent to guests)
var _events: Array = []
var _heard := {}         # peer -> seconds since their last message
var acts := 0            # partner techniques run (tests / stats)

# guest
var _loc := {}           # host unit id -> local Unit
var _npc := {}           # host unit id -> mirror Npc
var _last_target = null

func setup(m, p: Party) -> void:
	main = m
	wc = m.combat
	party = p
	party.coop_msg.connect(_on_msg)

func busy() -> bool:
	return state != ""

func is_host() -> bool:
	return state == "host"

func is_guest() -> bool:
	return state == "guest"

func _send(to, d: Dictionary) -> void:
	party.send(to, d)

func _guests() -> Array:
	return _joined.keys()

# ------------------------------------------------------------ leader: gather the party
## The leader picked a dungeon (Group Finder) with partners online in the zone.
func gather(raid_kind: String) -> void:
	if busy():
		return
	state = "gather"
	kind = raid_kind
	_joined = {}
	_asked = party.here()
	_t = GATHER
	var fwd := Vector3(sin(main.player.rig.global_rotation.y), 0, cos(main.player.rig.global_rotation.y))
	at = main.player.global_position + fwd * 7.0
	lvl = Game.player_level()
	_send(_asked, {"k": "dng", "kind": kind, "lv": lvl, "zone": Net.zone})
	Game.toast.emit(Tx.f("Asking your party to join %s...", _title(kind)), Color(1, 0.85, 0.4))

static func _title(k: String) -> String:
	var c: Dictionary = Raid.DUNGEONS.get(k, Raid.RAIDS.get(k, {}))
	return Tx.s(str(c.get("title", k))).capitalize()

func _begin_host() -> void:
	state = "host"
	_t = LINK
	_known = {}
	_events = []
	var humans: Array = []
	for p in _joined:
		var j: Dictionary = _joined[p]
		humans.append({"peer": p, "role": j.role, "stats": j.stats, "mob": char_mob(j.char)})
		_heard[p] = 0.0
		_hide_remote(p, true)
	wc.core.event.connect(_forward)
	main.start_coop_raid(kind, at, humans)
	if wc.raid == null:
		_abort_host("Couldn't start.")
		return
	wc.raid.warning.connect(_fwd_warning)
	wc.raid.finished.connect(_on_raid_finished)
	for p in _joined:
		var u: CombatCore.Unit = wc.raid.humans.get(p)
		_send(p, {"k": "go", "kind": kind, "at": [at.x, at.y, at.z], "uid": u.id if u else 0, "lv": wc.raid.level})

## A remote player as a raid fighter (their name, gi, skin and build).
static func char_mob(ch: Dictionary) -> Dictionary:
	var gi := Color.html(str(ch.get("gi", "f2f2ee"))) if Color.html_is_valid(str(ch.get("gi", ""))) else Color(0.95, 0.95, 0.93)
	var lv := clampi(int(ch.get("level", 1)), 1, 60)
	return {"name": str(ch.get("name", "?")), "title": "Party", "rank": clampi(int(ch.get("belt", 0)) * 5 + 2, 0, 24),
		"level": 1.0 + float(lv - 1) * 0.55 / 2.0, "gi": gi, "skin": UiKit.skin_tone(float(ch.get("skin", 0.35))),
		"body": str(ch.get("body", "male")), "style": "balanced", "look": ch.get("look", {}), "cls": str(ch.get("style", "")),
		"head": str(ch.get("head", "classic"))}

# ------------------------------------------------------------ guest: asked to join
func answer(accept: bool) -> void:
	if state != "asked":
		return
	if not accept or wc.me.in_combat or (wc.raid != null and is_instance_valid(wc.raid)):
		_send(host, {"k": "nojoin"})
		_reset()
		return
	state = "wait"
	_t = GATHER + 5.0
	var me: CombatCore.Unit = wc.me
	var stats := {"mhp": me.max_hp, "dmg": me.dmg, "auto": me.auto_dmg, "mgas": me.max_gas, "regen": me.gas_regen,
		"swing": me.swing_time, "mods": me.mods, "lv": me.level}
	_send(host, {"k": "join", "role": Team.player_role(), "stats": stats, "char": Net.my_char()})
	Game.toast.emit("Waiting for the party...", Color(1, 0.85, 0.4))

# ------------------------------------------------------------ network
func _on_msg(from: int, d: Dictionary, zone: String) -> void:
	var k := str(d.get("k", ""))
	if k == "dng":
		if from != party.leader or busy():
			_send(from, {"k": "nojoin", "why": "busy"})
			return
		if zone != Net.zone:
			_send(from, {"k": "nojoin", "why": "zone"})
			Game.toast.emit(Tx.f("Your party is starting %s in %s. Travel there to join the next one.", [_title(str(d.kind)), str(Data.ZONES.get(zone, {}).get("name", zone))]), Color(1, 0.8, 0.5))
			return
		state = "asked"
		host = from
		kind = str(d.get("kind", ""))
		_t = GATHER
		main.ask_coop(str(party.member(from).get("name", "?")), _title(kind))
		return
	if state == "host" or state == "gather":
		_heard[from] = 0.0
	match k:
		"join":
			if state == "gather" and _asked.has(from):
				_joined[from] = {"role": str(d.get("role", "dps")), "stats": d.get("stats", {}), "char": d.get("char", {})}
				Game.toast.emit(Tx.f("%s is in.", str(party.member(from).get("name", "?"))), Color(0.6, 1.0, 0.6))
				_asked.erase(from)
				if _asked.is_empty():
					_begin_host()
		"nojoin":
			if state == "gather" and _asked.has(from):
				_asked.erase(from)
				Game.toast.emit(Tx.f("%s can't come.", str(party.member(from).get("name", "?"))), Color(1, 0.7, 0.5))
				if _asked.is_empty():
					_begin_host()
		"act":
			if state == "host":
				_remote_act(from, d)
		"tg":
			if state == "host":
				_remote_target(from, int(d.get("t", 0)))
		"quit":
			if state == "host":
				_remote_gone(from, "%s left the run.")
			elif from == host and (state == "guest" or state == "wait"):
				_guest_end(false, "The leader ended the run.")
		"go":
			if state == "wait" and from == host:
				_begin_guest(d)
		"s":
			if state == "guest" and from == host:
				_t = LINK
				_apply(d)
		"end":
			if from == host and (state == "guest" or state == "wait"):
				_guest_end(bool(d.get("won", false)))
		"err":
			if state == "guest":
				wc._error(str(d.get("text", "")))

func _process(delta: float) -> void:
	if state == "":
		return
	_t -= delta
	match state:
		"gather":
			if _t <= 0.0:
				_begin_host()
		"asked":
			if _t <= 0.0:
				if main.hud.dialogue_open():
					main.hud._close_dialogue(false)
				_send(host, {"k": "nojoin"})
				_reset()
		"wait":
			if _t <= 0.0:
				Game.toast.emit("The party started without you.", Color(1, 0.7, 0.5))
				_reset()
		"host":
			_host_tick(delta)
		"guest":
			if _t <= 0.0:
				_guest_end(false, "Lost the connection to the party leader.")
				return
			_guest_tick(delta)

# ------------------------------------------------------------ host
func _host_tick(delta: float) -> void:
	if wc.raid == null or not is_instance_valid(wc.raid):
		return
	# partners stand where their own game says they are
	for p in wc.raid.humans:
		var u: CombatCore.Unit = wc.raid.humans[p]
		var n: Npc = wc.npc_of(u) if u else null
		var rp = main.remotes.get(p)
		if n and rp and is_instance_valid(rp):
			n.set_meta("net_pos", rp.global_position)
			n.set_meta("net_yaw", rp.rig.rotation.y if rp.rig else 0.0)
		_heard[p] = float(_heard.get(p, 0.0)) + delta
		if float(_heard[p]) > LINK and u != null and not u.dead:
			_remote_gone(p, "%s lost connection.")
			return
	_snap_t -= delta
	if _snap_t > 0.0:
		return
	_snap_t = SNAP_EVERY
	var sp: Array = []
	var live := {}
	for u in wc.core.units:
		live[u.id] = true
		if _known.has(u.id):
			continue
		_known[u.id] = true
		sp.append(_spawn_entry(u))
	var rm: Array = []
	for id in _known.keys():
		if not live.has(id):
			rm.append(id)
			_known.erase(id)
	var us: Array = []
	for u in wc.core.units:
		us.append(_ser(u))
	var msg := {"k": "s", "u": us, "e": _events}
	if not sp.is_empty():
		msg["sp"] = sp
	if not rm.is_empty():
		msg["rm"] = rm
	_events = []
	_send(_guests(), msg)

func _spawn_entry(u: CombatCore.Unit) -> Dictionary:
	var d := {}
	var peer := 0
	if u.player:
		d = char_mob(Net.my_char())
		d["ally"] = true
		d["role"] = "dps"
		peer = Net.my_id
	else:
		var n: Npc = wc.npc_of(u)
		if n:
			d = n.mob.duplicate()
			peer = int(d.get("peer", 0))
		else:
			d = {"name": u.name, "level": 1.0, "rank": 0, "gi": Color(0.9, 0.9, 0.9), "skin": Color(0.7, 0.5, 0.35)}
	for key in ["intro", "win", "lose", "extra", "zone", "camp"]:
		d.erase(key)
	return {"i": u.id, "d": Net.enc(d), "b": u.boss, "al": CombatCore.friendly(u), "p": peer, "r": u.role}

func _ser(u: CombatCore.Unit) -> Dictionary:
	var au := {}
	for key in u.auras:
		au[key] = snappedf(float(u.auras[key].get("t", 0.0)), 0.1)
	var c := {}
	if not u.cast.is_empty():
		var ab: Dictionary = u.cast.ab
		var ct = u.cast.get("target")
		c = {"ab": {"id": ab.get("id", ""), "name": ab.get("name", ""), "type": ab.get("type", ""), "_mv": ab.get("_mv", ""), "finisher": ab.get("finisher", false)},
			"t": snappedf(float(u.cast.t), 0.01), "dur": snappedf(float(u.cast.dur), 0.01), "tg": ct.id if ct else 0}
	var n = wc.npc_of(u) if not u.player else null
	var yaw: float = main.player.rig.rotation.y if u.player else (n.rig.rotation.y if n and n.rig else 0.0)
	var o := {"i": u.id, "hp": snappedf(u.hp, 0.1), "mhp": snappedf(u.max_hp, 0.1), "c": c, "au": au, "d": u.dead, "ic": u.in_combat,
		"x": snappedf(u.pos.x, 0.01), "z": snappedf(u.pos.z, 0.01), "y": snappedf(yaw, 0.01), "tg": u.target.id if u.target else 0}
	if CombatCore.pm(u):   # real players: everything their own HUD shows
		o["gas"] = snappedf(u.gas, 0.1)
		o["mgas"] = u.max_gas
		o["grip"] = u.grip
		o["gcd"] = snappedf(u.gcd, 0.01)
		var cds := {}
		for key in u.cds:
			cds[key] = snappedf(float(u.cds[key]), 0.05)
		o["cds"] = cds
	return o

const KEYS := ["ab", "amount", "crit", "aura", "dur", "fresh", "text", "sub", "on", "how"]

func _forward(e: Dictionary) -> void:
	if state != "host" or str(e.t) == "position":
		return   # ground positions are between you and one opponent; partners stand
	var out := {"t": e.t}
	for rk in ["u", "target", "e", "by"]:
		if e.has(rk):
			var x = e[rk]
			out[rk] = x.id if x != null else 0
	for key in KEYS:
		if e.has(key):
			var v = e[key]
			if v is Dictionary:
				v = (v as Dictionary).duplicate()
				v.erase("target")
			out[key] = v
	_events.append(out)

func _fwd_warning(h: String, sb: String) -> void:
	_events.append({"t": "warn", "h": h, "s": sb})

func _unit(id: int) -> CombatCore.Unit:
	for u in wc.core.units:
		if u.id == id:
			return u
	return null

func _remote_act(from: int, d: Dictionary) -> void:
	if wc.raid == null:
		return
	var u: CombatCore.Unit = wc.raid.humans.get(from)
	if u == null or u.dead or not wc.core.units.has(u):
		return
	var a: Dictionary = (d.get("ab", {}) as Dictionary).duplicate()
	a["_mv"] = ""   # no ground transitions for partners: their techniques hit, the pair stays standing
	var t := _unit(int(d.get("t", 0)))
	acts += 1
	var why: String = wc.core.use_ab(u, a, t)
	if why != "" and why != "gcd":
		_send(from, {"k": "err", "text": why})

func _remote_target(from: int, id: int) -> void:
	if wc.raid == null:
		return
	var u: CombatCore.Unit = wc.raid.humans.get(from)
	var t := _unit(id)
	if u == null or u.dead or t == null or t.dead or CombatCore.friendly(t):
		return
	u.target = t
	wc.core.engage(u, t)

func _remote_gone(p: int, why: String) -> void:
	var u: CombatCore.Unit = wc.raid.humans.get(p) if wc.raid else null
	_joined.erase(p)
	_hide_remote(p, false)
	Game.toast.emit(Tx.f(why, str(party.member(p).get("name", "A partner"))), Color(1, 0.6, 0.4))
	if u != null and not u.dead and wc.core.units.has(u):
		u.hp = 0.0
		u.dead = true
		var n: Npc = wc.npc_of(u)
		if n:
			wc._raid_tap(n, u)
	if _joined.is_empty() and wc.raid:
		wc.raid.coop = false   # just you now: a normal run

func _on_raid_finished(won: bool) -> void:
	if state != "host":
		return
	_host_tick(1.0)   # flush the last events
	_send(_guests(), {"k": "end", "won": won})
	_end_host()

func _abort_host(msg: String) -> void:
	Game.toast.emit(msg, Color(1, 0.6, 0.4))
	_send(_guests(), {"k": "quit"})
	_end_host()

func _end_host() -> void:
	if wc.core.event.is_connected(_forward):
		wc.core.event.disconnect(_forward)
	for p in _joined:
		_hide_remote(p, false)
	_reset()

## Leaving the run on purpose (walk away / title screen).
func quit() -> void:
	if state == "host":
		_abort_host("You ended the run.")
		if wc.raid and is_instance_valid(wc.raid) and not wc.raid.over:
			wc.raid.end(false)
	elif state == "guest" or state == "wait":
		_send(host, {"k": "quit"})
		_guest_end(false, "You left the run.")

# ------------------------------------------------------------ guest
func _begin_guest(d: Dictionary) -> void:
	state = "guest"
	_t = LINK
	my_uid = int(d.get("uid", 0))
	lvl = int(d.get("lv", Game.player_level()))
	kind = str(d.get("kind", kind))
	var a: Array = d.get("at", [0, 0, 0])
	at = Vector3(float(a[0]), float(a[1]), float(a[2]))
	_loc = {my_uid: wc.me}
	_npc = {}
	wc.core.puppet = true
	main.coop_guest_started(kind)
	var p := at + Vector3(randf_range(-2.0, 2.0), 0, 2.5)
	main.player.teleport(Vector3(p.x, wc.world.ground_y(p.x, p.z) + 0.3, p.z), main.player.rig.rotation.y)
	wc.me.hp = wc.me.max_hp
	wc.me.gas = wc.me.max_gas
	wc.me.dead = false
	_hide_remote(host, true)
	Game.toast.emit(Tx.f("%s with your party!", _title(kind)), Color(1, 0.85, 0.4))

func _apply(d: Dictionary) -> void:
	for e in d.get("sp", []):
		_mirror_spawn(e)
	for id in d.get("rm", []):
		_mirror_remove(int(id))
	for s in d.get("u", []):
		var u: CombatCore.Unit = _loc.get(int(s.get("i", 0)))
		if u != null:
			_apply_unit(u, s)
	for e in d.get("e", []):
		_replay(e)

func _mirror_spawn(e: Dictionary) -> void:
	var id := int(e.get("i", 0))
	if id == my_uid or _loc.has(id):
		return
	var m: Dictionary = Net.dec(e.get("d", {}))
	m["mirror"] = true
	m["raid"] = true
	m["mob"] = true
	m["aggro"] = false
	if bool(e.get("al", false)):
		m["ally"] = true
		m["role"] = str(e.get("r", "dps"))
	else:
		m.erase("ally")
	for key in ["gi", "skin"]:
		if not m.get(key) is Color:
			m[key] = Color(0.9, 0.9, 0.9) if key == "gi" else Color(0.7, 0.5, 0.35)
	if not m.has("level"):
		m["level"] = 1.0
	if not m.has("rank"):
		m["rank"] = 0
	var pos := at
	pos.y = wc.world.ground_y(pos.x, pos.z)
	var n := Npc.new()
	wc.world.add_child(n)
	n.setup_mob(m, wc.world, pos, 100.0)
	n.global_position = pos
	n._player = main.player
	n.wander = false
	if m.has("ally"):
		n.tag.modulate = Color(0.45, 1.0, 0.5)
		n.tag.text = "%s\n<%s>" % [str(m.name), Tx.s(str(m.get("title", "Party")))]
	var u: CombatCore.Unit = wc.unit_for(n, "boss" if bool(e.get("b", false)) else "mob")
	if u == null:
		n.queue_free()
		return
	u.boss = bool(e.get("b", false))
	_loc[id] = u
	_npc[id] = n
	var peer := int(e.get("p", 0))
	if peer != 0:
		_hide_remote(peer, true)
		n.set_meta("peer", peer)

func _mirror_remove(id: int) -> void:
	var u: CombatCore.Unit = _loc.get(id)
	var nv = _npc.get(id)
	var n: Npc = nv if is_instance_valid(nv) else null
	_loc.erase(id)
	_npc.erase(id)
	if u != null and u != wc.me:
		wc.core.remove(u)
		if wc.target == u:
			wc.target = null
	if n and is_instance_valid(n):
		wc._unit_of.erase(n.get_instance_id())
		if u:
			wc._npc_of.erase(u.id)
		if n.has_meta("peer"):
			_hide_remote(int(n.get_meta("peer")), false)
		get_tree().create_timer(2.5).timeout.connect(func(): if is_instance_valid(n): n.queue_free())

func _apply_unit(u: CombatCore.Unit, s: Dictionary) -> void:
	u.hp = float(s.get("hp", u.hp))
	u.max_hp = float(s.get("mhp", u.max_hp))
	u.in_combat = bool(s.get("ic", u.in_combat))
	var was_dead := u.dead
	u.dead = bool(s.get("d", u.dead))
	var au := {}
	for key in s.get("au", {}):
		var t := float(s.au[key])
		au[key] = {"t": t, "dur": t, "src": u}
	u.auras = au
	var c: Dictionary = s.get("c", {})
	u.cast = {} if c.is_empty() else {"ab": c.ab, "t": float(c.t), "dur": float(c.dur), "target": _loc.get(int(c.get("tg", 0)))}
	u.target = _loc.get(int(s.get("tg", 0)))
	if s.has("gas"):
		u.gas = float(s.gas)
		u.max_gas = float(s.get("mgas", u.max_gas))
		u.grip = int(s.get("grip", u.grip))
		u.gcd = float(s.get("gcd", 0.0))
		u.cds = (s.get("cds", {}) as Dictionary).duplicate()
	if u == wc.me:
		if u.dead and not was_dead:
			wc.target = null
		return
	var n: Npc = wc.npc_of(u)
	if n:
		var p := Vector3(float(s.get("x", 0.0)), 0.0, float(s.get("z", 0.0)))
		p.y = wc.world.ground_y(p.x, p.z)
		n.set_meta("net_pos", p)
		n.set_meta("net_yaw", float(s.get("y", 0.0)))
		n.in_combat = u.in_combat

func _replay(e: Dictionary) -> void:
	var tt := str(e.get("t", ""))
	if tt == "warn":
		wc.raid_warning.emit(str(e.get("h", "")), str(e.get("s", "")))
		return
	var out := {"t": tt}
	for rk in ["u", "target", "e", "by"]:
		if e.has(rk):
			var u = _loc.get(int(e[rk]))
			if u == null and (rk == "u" or rk == "target" or rk == "e") and int(e[rk]) != 0:
				return   # about a fighter this screen doesn't have (yet / any more)
			out[rk] = u
	for key in KEYS:
		if e.has(key):
			out[key] = e[key]
	if tt == "cast" and out.get("u") != null:
		var cu: CombatCore.Unit = out.u
		cu.cast = {"ab": out.get("ab", {}), "t": 0.0, "dur": float(out.get("dur", 1.0)), "target": out.get("target")}
	if tt == "tap":
		var v: CombatCore.Unit = out.get("u")
		if v:
			v.dead = true
			v.hp = 0.0
			v.cast = {}
	wc.core.emit(out)

func _guest_tick(_delta: float) -> void:
	# let the host know whom you're fighting (auto attacks follow your target)
	if wc.target != _last_target:
		_last_target = wc.target
		if wc.target != null:
			var tid := _uid_of(wc.target)
			if tid != 0:
				_send(host, {"k": "tg", "t": tid})

func _uid_of(u: CombatCore.Unit) -> int:
	for id in _loc:
		if _loc[id] == u:
			return int(id)
	return 0

## A press on a guest's screen: checked locally, then run by the host with your numbers.
func guest_press(id: String) -> String:
	var core: CombatCore = wc.core
	var me: CombatCore.Unit = wc.me
	var a := core.ability(me, id)
	if a.is_empty():
		return "Not learned yet"
	if bool(a.get("harm", true)) and (wc.target == null or wc.target.dead):
		wc._auto_target()
	var t: CombatCore.Unit = wc.target if bool(a.get("harm", true)) else me
	var why := core.block_reason(me, a, t)
	if why != "":
		return why
	a = a.duplicate()
	var mv := core.move_for(me, a, t)
	if mv != "" and mv != "@stand" and Data.MOVES.has(mv):
		a["name"] = str(Data.MOVES[mv].name)
	_send(host, {"k": "act", "ab": a, "t": _uid_of(t) if t != me else my_uid})
	me.gcd = CombatCore.GCD / core.haste(me) if bool(a.get("gcd", true)) else me.gcd
	return ""

func _guest_end(won: bool, msg := "") -> void:
	var was := state == "guest"
	for id in _npc.keys():
		_mirror_remove(int(id))
	_hide_remote(host, false)
	wc.core.puppet = false
	wc.core.leave_combat(wc.me)
	wc.me.dead = false
	wc.me.hp = wc.me.max_hp
	wc.me.gas = wc.me.max_gas
	wc.me.auras.clear()
	wc.me.cast = {}
	wc.target = null
	main.player.rig.release(CombatAnim.getup(main.player.rig.rotation.y))
	var k := kind
	var lv := lvl
	_reset()
	if msg != "":
		Game.toast.emit(msg, Color(1, 0.6, 0.4))
	if was:
		if won:
			Raid.reward(k, lv)
		main.coop_guest_over(k, won)

# ------------------------------------------------------------ shared
func _hide_remote(p: int, hide: bool) -> void:
	var rp = main.remotes.get(p)
	if rp and is_instance_valid(rp):
		rp.visible = not hide

func _reset() -> void:
	state = ""
	_joined = {}
	_asked = []
	_known = {}
	_events = []
	_loc = {}
	_npc = {}
	_last_target = null
	my_uid = 0

func _exit_tree() -> void:
	if state == "host":
		_send(_guests(), {"k": "quit"})
	elif state == "guest" or state == "wait":
		_send(host, {"k": "quit"})
