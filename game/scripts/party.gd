class_name Party
extends Node
## Parties of up to five real players, anywhere in the world (the server relays by id, see
## world.js 'party'). The leader's game owns the roster and sends it to everyone; every member
## sends a small status line (health, level, zone) every couple of seconds for the party frames.
##
## Messages: inv / acc / dec / roster / st / chat / bye / kick / nf (name not found)
## Co-op dungeons ride on the same relay (see Coop): dng / join / go / act / tg / s / end ...

signal changed
signal coop_msg(from: int, d: Dictionary, zone: String)
signal trade_msg(from: int, d: Dictionary, zone: String)   # see Trade (same relay)

const MAX := 5
const STATUS_EVERY := 2.0
const STALE := 12.0      # no status for this long: shown as offline
const DROP := 60.0       # ...and this long: out of the party
const INVITE_TIMEOUT := 30.0

var main
var leader := 0
## member id -> {id, name, level, style, faction, hp, zone, seen (seconds since last status)}
var members := {}
var order: Array = []          # member ids, roster order (the leader's)
var pending_invite := {}       # an invite waiting for your answer: {from, name, t}
var _sent := {}                # names you invited -> seconds left
var _st_t := 0.0

func setup(m) -> void:
	main = m
	Net.party_msg.connect(_on_msg)

func me() -> int:
	return Net.my_id

func in_party() -> bool:
	return members.size() > 1

func is_leader() -> bool:
	return in_party() and leader == me()

func others() -> Array:
	return order.filter(func(i): return i != me())

func member(id: int) -> Dictionary:
	return members.get(id, {})

func online(id: int) -> bool:
	return id == me() or float(members.get(id, {}).get("seen", 99.0)) < STALE

## Party members playing right now in your zone (they can join a co-op dungeon).
func here() -> Array:
	return others().filter(func(i): return online(i) and str(members[i].get("zone", "")) == Net.zone)

func _my_row() -> Dictionary:
	var hp := 1.0
	if main and main.combat and main.combat.me:
		hp = main.combat.me.pct()
	return {"id": me(), "name": Game.player_name, "level": Game.player_level(), "style": Game.style,
		"faction": Game.faction(), "hp": snappedf(hp, 0.01), "zone": Net.zone, "seen": 0.0}

# ------------------------------------------------------------ actions
func invite(name_: String) -> void:
	if not Net.connected:
		_sys("Log in (title screen) so you can play with others.")
		return
	name_ = name_.strip_edges()
	if name_ == "" or name_.to_lower() == Game.player_name.to_lower():
		_sys("Usage: /invite Name")
		return
	if in_party() and not is_leader():
		_sys("Only the party leader can invite.")
		return
	if members.size() >= MAX:
		_sys("Your party is full (5).")
		return
	_sent[name_.to_lower()] = INVITE_TIMEOUT
	Net.send_party(0, {"k": "inv", "char": Net.my_char()}, name_)
	_sys(Tx.f("Party invite sent to %s.", name_))

func invite_id(id: int, name_: String) -> void:
	if in_party() and not is_leader():
		_sys("Only the party leader can invite.")
		return
	if members.size() >= MAX:
		_sys("Your party is full (5).")
		return
	_sent[name_.to_lower()] = INVITE_TIMEOUT
	Net.send_party(id, {"k": "inv", "char": Net.my_char()})
	_sys(Tx.f("Party invite sent to %s.", name_))

func answer(accept: bool) -> void:
	if pending_invite.is_empty():
		return
	var from := int(pending_invite.from)
	pending_invite = {}
	if not accept:
		Net.send_party(from, {"k": "dec"})
		return
	if in_party():
		leave(true)
	Net.send_party(from, {"k": "acc", "row": _my_row()})

func leave(quiet := false) -> void:
	if not in_party():
		return
	Net.send_party(others(), {"k": "bye"})
	_clear()
	if not quiet:
		_sys("You left the party.")

func kick(name_: String) -> void:
	if not is_leader():
		_sys("Only the party leader can remove someone.")
		return
	for i in others():
		if str(members[i].name).to_lower() == name_.to_lower():
			Net.send_party(i, {"k": "kick"})
			_drop(i)
			_sys(Tx.f("%s was removed from the party.", str(name_)))
			return
	_sys(Tx.f("%s isn't in your party.", name_))

func promote(name_: String) -> void:
	if not is_leader():
		return
	for i in others():
		if str(members[i].name).to_lower() == name_.to_lower():
			leader = i
			_broadcast_roster()
			_sys(Tx.f("%s now leads the party.", str(members[i].name)))
			return

func say(text: String) -> void:
	if not in_party():
		_sys("You're not in a party. /invite Name to start one.")
		return
	text = text.strip_edges()
	if text == "":
		return
	Net.send_party(others(), {"k": "chat", "text": text})
	_chat(Game.player_name, text)

## Co-op traffic (Coop uses the same relay).
func send(to, d: Dictionary) -> void:
	Net.send_party(to, d)

# ------------------------------------------------------------ network
func _on_msg(from: int, d: Dictionary, zone: String) -> void:
	var k := str(d.get("k", ""))
	if k.begins_with("tr_"):
		trade_msg.emit(from, d, zone)
		return
	match k:
		"nf":
			_sys(Tx.f("Nobody called %s is online.", str(d.get("name", "?"))))
			_sent.erase(str(d.get("name", "")).to_lower())
		"inv":
			var ch: Dictionary = d.get("char", {})
			if from == 0 or (in_party() and members.has(from)):
				return
			if not pending_invite.is_empty() or main.hud.dialogue_open() or main.combat.me.in_combat:
				Net.send_party(from, {"k": "dec", "why": "busy"})
				return
			pending_invite = {"from": from, "name": str(ch.get("name", "?")), "t": INVITE_TIMEOUT}
			main.ask_party(ch)
		"dec":
			_sys(Tx.f("%s declined%s.", [_name_of(from, d), " (busy)" if str(d.get("why", "")) == "busy" else ""]))
		"acc":
			var row: Dictionary = d.get("row", {})
			if not _sent.has(str(row.get("name", "")).to_lower()):
				return   # an invite we never sent (or that expired)
			_sent.erase(str(row.get("name", "")).to_lower())
			if members.size() >= MAX:
				Net.send_party(from, {"k": "full"})
				return
			if not in_party():
				leader = me()
				members = {me(): _my_row()}
				order = [me()]
			row["id"] = from
			row["seen"] = 0.0
			row["zone"] = zone
			members[from] = row
			order.append(from)
			_broadcast_roster()
			_sys(Tx.f("%s joined the party.", str(row.get("name", "?"))))
			changed.emit()
		"full":
			_sys("That party is full.")
		"roster":
			if from != int(d.get("leader", 0)):
				return
			var ids: Array = []
			var nm := {}
			for r in d.get("m", []):
				var id := int(r.get("id", 0))
				ids.append(id)
				var old: Dictionary = members.get(id, {})
				var row: Dictionary = (r as Dictionary).duplicate()
				row["id"] = id
				row["seen"] = float(old.get("seen", 0.0))
				nm[id] = row
			if not ids.has(me()):
				_clear()
				return
			var fresh := not in_party()
			leader = from
			order = ids
			members = nm
			members[me()] = _my_row()
			if fresh:
				_sys(Tx.f("You joined %s's party. /p to talk to them.", str(members[leader].get("name", "?"))))
			changed.emit()
		"st":
			if members.has(from):
				var row: Dictionary = members[from]
				for key in ["name", "level", "style", "faction", "hp"]:
					if d.has(key):
						row[key] = d[key]
				row["zone"] = zone
				row["seen"] = 0.0
				changed.emit()
		"chat":
			if members.has(from) and not Net.ignored.has(str(members[from].name).to_lower()):
				_chat(str(members[from].name), str(d.get("text", "")))
		"bye":
			if members.has(from):
				_sys(Tx.f("%s left the party.", str(members[from].name)))
				_drop(from)
		"kick":
			if from == leader and in_party():
				_clear()
				_sys("You were removed from the party.")
		_:
			if members.has(from) or k in ["dng", "join", "nojoin"]:
				coop_msg.emit(from, d, zone)

func _process(delta: float) -> void:
	if not pending_invite.is_empty():
		pending_invite.t = float(pending_invite.t) - delta
		if float(pending_invite.t) <= 0.0:
			if main.hud.dialogue_open():
				main.hud._close_dialogue(false)
			pending_invite = {}
	for n in _sent.keys():
		_sent[n] = float(_sent[n]) - delta
		if float(_sent[n]) <= 0.0:
			_sent.erase(n)
	if not in_party():
		return
	members[me()] = _my_row()
	_st_t -= delta
	if _st_t <= 0.0:
		_st_t = STATUS_EVERY
		var r := _my_row()
		r.erase("id")
		r.erase("seen")
		r.erase("zone")
		r["k"] = "st"
		Net.send_party(others(), r)
		changed.emit()
	for i in others():
		var row: Dictionary = members[i]
		row["seen"] = float(row.get("seen", 0.0)) + delta
		if float(row.seen) > DROP:
			_sys(Tx.f("%s went offline and left the party.", str(row.name)))
			_drop(i)
			return

# ------------------------------------------------------------ roster
func _broadcast_roster() -> void:
	var rows: Array = []
	for i in order:
		var r: Dictionary = (members[i] as Dictionary).duplicate()
		r.erase("seen")
		rows.append(r)
	Net.send_party(others(), {"k": "roster", "leader": leader, "m": rows})
	changed.emit()

func _drop(id: int) -> void:
	members.erase(id)
	order.erase(id)
	if members.size() <= 1:
		_clear()
		_sys("The party disbanded.")
		return
	if id == leader:
		leader = int(order[0])   # everyone picks the same new leader: the next in line
		if leader == me():
			_sys("You lead the party now.")
	if is_leader():
		_broadcast_roster()
	changed.emit()

func _clear() -> void:
	members = {}
	order = []
	leader = 0
	changed.emit()

func _name_of(id: int, d := {}) -> String:
	if members.has(id):
		return str(members[id].name)
	return str(d.get("name", "They"))

func _sys(t: String) -> void:
	if main and main.hud and main.hud.combat_log:
		main.hud.combat_log.add_chat({"ch": "sys", "text": Tx.s(t)})

func _chat(who: String, text: String) -> void:
	if main and main.hud and main.hud.combat_log:
		main.hud.combat_log.add_chat({"ch": "party", "from": who, "text": text})

func _exit_tree() -> void:
	if in_party():
		Net.send_party(others(), {"k": "bye"})
