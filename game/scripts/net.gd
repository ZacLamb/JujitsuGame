extends Node
## Live world connection (the Railway server's /ws): other players in your zone and chat.
## Only when logged in (Cloud); offline play is unchanged. Reconnects on its own.

signal joined(id: int, d: Dictionary)      # another player appeared in your zone
signal left(id: int)
signal moved(rows: Array)                   # [[id, x, y, z, yaw, speed, air, combat], ...]
signal char_changed(id: int, ch: Dictionary)
signal chat(m: Dictionary)                  # {ch, from, fid, style, text, to?, echo?} or {ch:"sys", text}
signal status_changed

var ws: WebSocketPeer
var my_id := 0
var online := 0
var zone := ""
var connected := false
var ignored := {}        # lower-case name -> true (saved)
var last_whisper := ""   # for /r
var _want := false       # in the world (not the title screen)
var _retry := 0.0
var _backoff := 2.0
var _pos_t := 0.0
var _last_pos := []
var _char_key := ""

const PREFS := "user://tatame_chat.json"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if FileAccess.file_exists(PREFS):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PREFS))
		if d is Dictionary:
			for n in d.get("ignored", []):
				ignored[str(n).to_lower()] = true
	Cloud.changed.connect(func():
		if not Cloud.logged_in():
			stop())
	Game.progress_changed.connect(_send_char_if_changed)

## Called by main when the player enters the world / a zone.
func enter(z: String) -> void:
	_want = true
	zone = z
	if connected:
		_send({"t": "zone", "zone": zone})
	elif Cloud.logged_in() and ws == null:
		_connect()

func leave_world() -> void:
	_want = false
	stop()

func stop() -> void:
	if ws:
		ws.close()
	ws = null
	if connected:
		connected = false
		status_changed.emit()

func _url() -> String:
	var b := Cloud.base
	if b.begins_with("https://"):
		return "wss://" + b.trim_prefix("https://") + "/ws"
	return "ws://" + b.trim_prefix("http://") + "/ws"

func _connect() -> void:
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	if ws.connect_to_url(_url()) != OK:
		ws = null
		_retry = _backoff

func _process(delta: float) -> void:
	if ws == null:
		if _want and Cloud.logged_in() and _retry > 0.0:
			_retry -= delta
			if _retry <= 0.0:
				_connect()
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not connected and my_id == -1:
			pass
		if not connected and my_id == 0:
			my_id = -1
			_send({"t": "hello", "token": Cloud.token, "char": my_char()})
		while ws.get_available_packet_count() > 0:
			var d = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if d is Dictionary:
				_on_msg(d)
	elif st == WebSocketPeer.STATE_CLOSED:
		var code := ws.get_close_code()
		ws = null
		my_id = 0
		var was := connected
		connected = false
		if was:
			status_changed.emit()
			chat.emit({"ch": "sys", "text": "Disconnected from the live world. Reconnecting..."})
		if code == 4003:   # not logged in: wait for a new login
			_retry = 0.0
		elif code != 4000:
			_retry = _backoff
			_backoff = minf(_backoff * 1.6, 30.0)

func _on_msg(d: Dictionary) -> void:
	match str(d.get("t", "")):
		"welcome":
			my_id = int(d.id)
			online = int(d.get("online", 1))
			connected = true
			_backoff = 2.0
			status_changed.emit()
			if zone != "":
				_send({"t": "zone", "zone": zone})
			chat.emit({"ch": "sys", "text": "Connected to the live world · %d online. Press Enter to chat, /help for commands." % online})
		"zone_list":
			for p in d.get("players", []):
				joined.emit(int(p.id), p)
		"join":
			joined.emit(int(d.id), d)
		"leave":
			left.emit(int(d.id))
		"st":
			moved.emit(d.get("p", []))
		"char":
			char_changed.emit(int(d.id), d.get("char", {}))
		"chat":
			if ignored.has(str(d.get("from", "")).to_lower()) and not d.get("echo", false):
				return
			if str(d.get("ch", "")) == "whisper" and not d.get("echo", false):
				last_whisper = str(d.get("from", ""))
			chat.emit(d)
		"sys":
			chat.emit({"ch": "sys", "text": str(d.get("text", ""))})

func _send(m: Dictionary) -> void:
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(m))

## Position (8/s, only when it changed).
func update(p: Vector3, yaw: float, speed01: float, air: bool, in_combat: bool, delta: float) -> void:
	if not connected:
		return
	_pos_t -= delta
	if _pos_t > 0.0:
		return
	_pos_t = 0.125
	var row := [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(yaw, 0.01), snappedf(speed01, 0.02), air, in_combat]
	if row == _last_pos:
		return
	_last_pos = row
	_send({"t": "pos", "x": row[0], "y": row[1], "z": row[2], "yaw": row[3], "s": row[4], "air": air, "c": in_combat})

func send_chat(ch: String, text: String, to := "") -> void:
	if not connected:
		chat.emit({"ch": "sys", "text": "Log in (title screen) to chat with other players."})
		return
	var m := {"t": "chat", "ch": ch, "text": text}
	if to != "":
		m["to"] = to
	_send(m)

func who() -> void:
	_send({"t": "who"})

func report(name_: String, reason: String) -> void:
	_send({"t": "report", "name": name_, "reason": reason})

func set_ignored(name_: String, on: bool) -> void:
	if on:
		ignored[name_.to_lower()] = true
	else:
		ignored.erase(name_.to_lower())
	var f := FileAccess.open(PREFS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"ignored": ignored.keys()}))

# ------------------------------------------------------------ what others see of you
func my_char() -> Dictionary:
	return {"name": Game.player_name, "style": Game.style, "level": Game.player_level(), "belt": Game.belt_index(),
		"body": Game.body, "skin": Game.skin_t, "gi": Game.gi_color().to_html(), "look": enc(Game.look())}

func _send_char_if_changed() -> void:
	if not connected:
		return
	var c := my_char()
	var k := JSON.stringify(c)
	if k == _char_key:
		return
	_char_key = k
	_send({"t": "char", "char": c})

## Colours don't survive JSON: {"_c": "rrggbbaa"} stands in for one.
static func enc(v):
	if v is Color:
		return {"_c": (v as Color).to_html(true)}
	if v is Dictionary:
		var o := {}
		for k in v:
			o[str(k)] = enc(v[k])
		return o
	if v is Array:
		return (v as Array).map(func(x): return enc(x))
	return v

static func dec(v):
	if v is Dictionary:
		if v.size() == 1 and v.has("_c"):
			return Color.html(str(v._c))
		var o := {}
		for k in v:
			o[k] = dec(v[k])
		return o
	if v is Array:
		return (v as Array).map(func(x): return dec(x))
	return v
