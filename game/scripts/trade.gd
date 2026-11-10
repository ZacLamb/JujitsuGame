class_name Trade
extends Node
## Player-to-player trading, WoW-style: both sides put bag items (whole stacks) and R$ on the
## table; any change clears both "Accept"s; when both accept, each game checks its own side
## and says OK, and only when both OKs are in does anything change hands.
## Rolled gear travels with its stats (it gets a fresh id in the new owner's save).
##
## Messages (Party relay): tr_req / tr_acc / tr_dec / tr_offer / tr_lock / tr_ok / tr_cancel

signal changed      # the window redraws
signal closed

const MAX_ITEMS := 6
const REQ_TIMEOUT := 25.0
const LINK := 30.0

var main
var party: Party
var state := ""          # "" | "asking" | "asked" | "open"
var peer := 0
var peer_name := ""
var mine: Array = []     # bag slot indices you're offering
var my_money := 0
var theirs: Array = []   # [{id, n, def?}]
var their_money := 0
var my_ver := 0
var their_ver := 0
var my_lock := false
var their_lock := false
var _my_ok := false
var _their_ok := false
var _t := 0.0
var _ping_t := 0.0

func setup(m, p: Party) -> void:
	main = m
	party = p
	party.trade_msg.connect(_on_msg)

func busy() -> bool:
	return state != ""

func is_open() -> bool:
	return state == "open"

func _send(d: Dictionary) -> void:
	Net.send_party(peer, d)

# ------------------------------------------------------------ requests
func request(id: int, name_: String) -> void:
	if busy():
		return
	if main.combat.me.in_combat:
		Game.toast.emit("Finish your fight first.", Color(1, 0.5, 0.4))
		return
	state = "asking"
	peer = id
	peer_name = name_
	_t = REQ_TIMEOUT
	Net.send_party(id, {"k": "tr_req", "name": Game.player_name})
	Game.toast.emit(Tx.f("Trade request sent to %s...", name_), Color(1, 0.85, 0.4))

func request_name(name_: String) -> void:
	name_ = name_.strip_edges()
	if name_ == "":
		return
	for id in main.remotes:
		var rp = main.remotes[id]
		if is_instance_valid(rp) and str(rp.char.get("name", "")).to_lower() == name_.to_lower():
			request(int(id), str(rp.char.get("name", name_)))
			return
	Game.toast.emit(Tx.f("%s has to be nearby (same zone) to trade.", name_), Color(1, 0.6, 0.4))

func answer(accept: bool) -> void:
	if state != "asked":
		return
	if not accept or main.combat.me.in_combat:
		_send({"k": "tr_dec"})
		_reset()
		return
	_send({"k": "tr_acc"})
	_open()

func _open() -> void:
	state = "open"
	_t = LINK
	mine = []
	theirs = []
	my_money = 0
	their_money = 0
	my_ver = 0
	their_ver = 0
	my_lock = false
	their_lock = false
	_my_ok = false
	_their_ok = false
	main.hud.open_trade(self)
	changed.emit()

func cancel(tell := true) -> void:
	if state == "":
		return
	if tell:
		_send({"k": "tr_cancel"})
	var was_open := state == "open"
	_reset()
	if was_open:
		Game.toast.emit("Trade cancelled.", Color(1, 0.7, 0.5))
	closed.emit()

# ------------------------------------------------------------ the table
## Clicking a bag item while the window is open puts it on (or takes it off) the table.
func toggle_slot(k: int) -> String:
	if state != "open":
		return ""
	if mine.has(k):
		mine.erase(k)
	else:
		if k < 0 or k >= Game.bag.size() or Game.bag[k] == null:
			return ""
		if mine.size() >= MAX_ITEMS:
			return "The trade window is full (6)."
		mine.append(k)
	_offer_changed()
	return ""

func set_money(v: int) -> void:
	if state != "open":
		return
	v = clampi(v, 0, Game.money)
	if v == my_money:
		return
	my_money = v
	_offer_changed()

func _offer_changed() -> void:
	my_ver += 1
	my_lock = false
	their_lock = false
	_my_ok = false
	_their_ok = false
	_send({"k": "tr_offer", "v": my_ver, "items": _my_items(), "money": my_money})
	changed.emit()

func _my_items() -> Array:
	var out: Array = []
	for k in mine:
		var s = Game.bag[k] if k < Game.bag.size() else null
		if s == null:
			continue
		var e := {"id": str(s.id), "n": int(s.n)}
		var gid := str(s.id).trim_prefix("gear:") if str(s.id).begins_with("gear:") else ""
		if gid != "" and Game.rolled.has(gid):
			e["def"] = Game.rolled[gid]
		out.append(e)
	return out

## Accept (or take it back).
func set_lock(on: bool) -> String:
	if state != "open":
		return ""
	if on:
		if mine.is_empty() and my_money == 0 and theirs.is_empty() and their_money == 0:
			return "Put something on the table first."
		if Game.free_slots() + mine.size() < theirs.size():
			return "Not enough room in your bags."
		if my_money > Game.money:
			return "Not enough R$."
	my_lock = on
	_send({"k": "tr_lock", "on": on, "v": their_ver})
	changed.emit()
	_try_ok()
	return ""

func _try_ok() -> void:
	if not (my_lock and their_lock) or _my_ok:
		return
	if not _valid():
		cancel()
		Game.toast.emit("Something in the trade changed. Cancelled.", Color(1, 0.6, 0.4))
		return
	_my_ok = true
	_send({"k": "tr_ok", "v": my_ver})
	_try_finish()

func _valid() -> bool:
	if my_money > Game.money:
		return false
	for k in mine:
		if k >= Game.bag.size() or Game.bag[k] == null:
			return false
	return Game.free_slots() + mine.size() >= theirs.size()

func _try_finish() -> void:
	if not (_my_ok and _their_ok):
		return
	# take ours (highest slot first, so indices stay valid), then add theirs
	var gave: Array = []
	var ks := mine.duplicate()
	ks.sort()
	ks.reverse()
	for k in ks:
		var s = Game.bag[k]
		if s != null:
			gave.append(Loot.item(str(s.id)).get("name", s.id))
			Game.bag[k] = null
	Game.money -= my_money
	var got: Array = []
	for e in theirs:
		var id := str(e.get("id", ""))
		if e.has("def") and e.def is Dictionary:
			id = "gear:" + Game.make_rolled(e.def)
		if Loot.item(id).is_empty():
			continue
		Game.add_item(id, int(e.get("n", 1)))
		got.append(str(Loot.item(id).get("name", id)))
	Game.money += their_money
	Game.bag_changed.emit()
	Game.save_game()
	var nm := peer_name
	var line := Tx.f("Trade with %s done.", nm)
	if not got.is_empty() or their_money > 0:
		line += " " + Tx.f("Received: %s", ", ".join(got.map(func(x): return Tx.s(str(x)))) + ("" if their_money == 0 else "%sR$ %d" % [", " if not got.is_empty() else "", their_money]))
	Game.toast.emit(line, Color(0.6, 1.0, 0.6))
	Sfx.play("collect", -4.0)
	_reset()
	closed.emit()

# ------------------------------------------------------------ network
func _on_msg(from: int, d: Dictionary, _zone: String) -> void:
	var k := str(d.get("k", ""))
	if k == "tr_req":
		if busy() or main.hud.dialogue_open() or main.combat.me.in_combat:
			Net.send_party(from, {"k": "tr_dec", "why": "busy"})
			return
		state = "asked"
		peer = from
		peer_name = str(d.get("name", "?"))
		_t = REQ_TIMEOUT
		main.ask_trade(peer_name)
		return
	if from != peer:
		return
	_t = LINK
	match k:
		"tr_dec":
			if state == "asking":
				Game.toast.emit(Tx.f("%s declined%s.", [peer_name, " (busy)" if str(d.get("why", "")) == "busy" else ""]), Color(1, 0.6, 0.4))
				_reset()
		"tr_acc":
			if state == "asking":
				_open()
		"tr_offer":
			if state == "open":
				their_ver = int(d.get("v", 0))
				theirs = []
				for e in (d.get("items", []) as Array).slice(0, MAX_ITEMS):
					if not e is Dictionary:
						continue
					var row := {"id": str(e.get("id", "")), "n": clampi(int(e.get("n", 1)), 1, 99)}
					if e.get("def") is Dictionary:
						var df: Dictionary = e.def
						if not (df.has("slot") and df.has("name") and df.has("rarity")) or not Gear.SLOTS.has(str(df.slot)):
							continue
						df["name"] = str(df.name).left(40)
						row["def"] = df
						var tmp := "tr%d_%d" % [peer, theirs.size()]
						Gear.register_rolled(tmp, df)   # so the window can show it
						row["show"] = "gear:" + tmp
					elif Loot.item(row.id).is_empty():
						continue
					theirs.append(row)
				their_money = maxi(0, int(d.get("money", 0)))
				my_lock = false
				their_lock = false
				_my_ok = false
				_their_ok = false
				changed.emit()
		"tr_lock":
			if state == "open" and int(d.get("v", -1)) == my_ver:
				their_lock = bool(d.get("on", false))
				changed.emit()
				_try_ok()
		"tr_ok":
			if state == "open" and int(d.get("v", -1)) == their_ver and their_lock:
				_their_ok = true
				_try_finish()
		"tr_cancel":
			if state != "":
				var was := state == "open"
				_reset()
				if was:
					Game.toast.emit(Tx.f("%s cancelled the trade.", peer_name), Color(1, 0.7, 0.5))
				closed.emit()

func _process(delta: float) -> void:
	if state == "":
		return
	_t -= delta
	if _t <= 0.0:
		if state == "asked" and main.hud.dialogue_open():
			main.hud._close_dialogue(false)
		elif state == "asking":
			Game.toast.emit(Tx.f("%s didn't answer.", peer_name), Color(1, 0.6, 0.4))
		cancel(state == "open")
		return
	if state == "open":
		if main.combat.me.in_combat:
			cancel()
			return
		_ping_t -= delta
		if _ping_t <= 0.0:
			_ping_t = 8.0
			_send({"k": "tr_ping"})

func _reset() -> void:
	state = ""
	mine = []
	theirs = []
	my_money = 0
	their_money = 0
	my_lock = false
	their_lock = false
	_my_ok = false
	_their_ok = false

func _exit_tree() -> void:
	if state != "":
		Net.send_party(peer, {"k": "tr_cancel"})
