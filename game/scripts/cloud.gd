extends Node
## Accounts + cloud saves (the Railway server's /api). Optional: without an account the game
## plays offline exactly as before. Logged in, every save is uploaded a few seconds later, and
## logging in on another device brings your characters down (merged with any local ones).

signal changed   # login state changed or characters were pulled

const AUTH_PATH := "user://tatame_auth.json"
const CHAR_FILE := "user://tatame_char_%s.json"

var token := ""
var role := "player"   # from /api/me; "gm" = Game Master (set on the server, GM_EMAILS)
var email := ""
var status := ""   # short line for the title screen ("Saved to cloud", errors...)
var base := ""
var _push_t := -1.0
var _war_t := 5.0        # faction war: send pending points / refresh the report
var _war_busy := false
signal war_changed

func _ready() -> void:
	if OS.has_feature("web"):
		var o = JavaScriptBridge.eval("window.location.origin", true)
		base = str(o) if o != null else ""
	elif OS.get_environment("TATAME_API") != "":
		base = OS.get_environment("TATAME_API")
	_load_auth()
	Game.saved.connect(func():
		if logged_in():
			_push_t = 4.0)
	if logged_in():
		_req(HTTPClient.METHOD_GET, "/api/me", null, func(code: int, d: Dictionary):
			if code == 401:
				_set_auth("", "")
				status = "Session expired: log in again."
				changed.emit()
			elif code == 200:
				role = str(d.get("role", "player"))
				changed.emit()
				pull(false))

func available() -> bool:
	return base != ""

func logged_in() -> bool:
	return token != "" and available()

func _process(delta: float) -> void:
	_war_t -= delta
	if _war_t <= 0.0 and available() and not _war_busy:
		_war_t = 60.0
		war_sync()
	if _push_t > 0.0:
		_push_t -= delta
		if _push_t <= 0.0:
			push()

# ------------------------------------------------------------ faction war
## Logged in with points waiting: send them (the reply carries the report). Otherwise just refresh it.
func war_sync() -> void:
	_war_busy = true
	if logged_in() and Game.war_pending > 0 and Game.style != "":
		var n := Game.war_pending
		_req(HTTPClient.METHOD_POST, "/api/war", {"faction": Game.faction(), "points": n, "name": Game.player_name}, func(code: int, d: Dictionary):
			_war_busy = false
			if code == 200:
				Game.war_pending = maxi(0, Game.war_pending - n)
				Game.war_mine = int(d.get("mine", Game.war_mine))
				if d.has("war"):
					Game.war = d.war
					war_changed.emit())
		return
	_req(HTTPClient.METHOD_GET, "/api/war", null, func(code: int, d: Dictionary):
		_war_busy = false
		if code == 200:
			Game.war = d
			war_changed.emit())

# ------------------------------------------------------------ account
## mode: "login" or "register". cb(error_text) ("" = ok).
func authenticate(mode: String, e: String, pw: String, cb: Callable) -> void:
	_req(HTTPClient.METHOD_POST, "/api/" + mode, {"email": e, "password": pw}, func(code: int, d: Dictionary):
		if code != 200:
			cb.call(str(d.get("error", "Couldn't reach the server (%d)." % code)))
			return
		_set_auth(str(d.token), str(d.email))
		status = "Logged in as %s" % email
		pull(true)
		cb.call(""))

func logout() -> void:
	if logged_in():
		_req(HTTPClient.METHOD_POST, "/api/logout", {}, func(_c, _d): pass)
	_set_auth("", "")
	status = "Logged out. Your characters stay on this device."
	changed.emit()

# ------------------------------------------------------------ sync
## Uploads the index and every character file.
func push() -> void:
	if not logged_in():
		return
	var idx := _read_json(Game.INDEX_PATH)
	var chars := {}
	for c in idx.get("chars", []):
		var id := str(c.get("id", ""))
		var d := _read_json(CHAR_FILE % id)
		if not d.is_empty():
			chars[id] = d
	var body := {"data": {"index": idx, "chars": chars, "at": Time.get_unix_time_from_system()}}
	_req(HTTPClient.METHOD_PUT, "/api/saves", body, func(code: int, d: Dictionary):
		status = "Saved to your account" if code == 200 else str(d.get("error", "Cloud save failed (%d)" % code))
		changed.emit())

## Downloads your characters. After an explicit login (merge = true) local-only characters are kept
## and merged in; on a normal start the newer side wins.
func pull(merge: bool) -> void:
	_req(HTTPClient.METHOD_GET, "/api/saves", null, func(code: int, d: Dictionary):
		if code != 200:
			return
		var data = d.get("data")
		if data == null or typeof(data) != TYPE_DICTIONARY:
			push()   # a new account: upload what's on this device
			return
		var local_idx := _read_json(Game.INDEX_PATH)
		var local_at := float(local_idx.get("_at", 0.0))
		if not merge and float(data.get("at", 0.0)) <= local_at:
			push()
			return
		_apply(data, merge)
		status = "Characters loaded from your account"
		changed.emit()
		if merge:
			push())

func _apply(data: Dictionary, merge: bool) -> void:
	var idx: Dictionary = data.get("index", {"active": "", "chars": []})
	var chars: Dictionary = data.get("chars", {})
	var out_chars: Array = (idx.get("chars", []) as Array).duplicate(true)
	var used := {}
	for c in out_chars:
		used[str(c.get("id", ""))] = true
	# local characters that aren't on the account come along (re-numbered if the id is taken)
	if merge:
		var local := _read_json(Game.INDEX_PATH)
		for c in local.get("chars", []):
			var lid := str(c.get("id", ""))
			if str(c.get("style", "")) == "":
				continue
			var same := false
			for s in out_chars:
				if str(s.get("id", "")) == lid and str(s.get("name", "")) == str(c.get("name", "")) and str(s.get("style", "")) == str(c.get("style", "")):
					same = true
			if same:
				continue
			var nid := lid
			var k := 1
			while used.has(nid):
				k += 1
				nid = str(k)
			var save := _read_json(CHAR_FILE % lid)
			if save.is_empty():
				continue
			var cc: Dictionary = c.duplicate()
			cc["id"] = nid
			out_chars.append(cc)
			chars[nid] = save
			used[nid] = true
	for id in chars:
		_write_json(CHAR_FILE % str(id), chars[id])
	idx["chars"] = out_chars
	idx["_at"] = float(data.get("at", Time.get_unix_time_from_system()))
	_write_json(Game.INDEX_PATH, idx)

# ------------------------------------------------------------ plumbing
func _req(method: int, path: String, body, cb: Callable) -> void:
	if not available():
		cb.call(0, {"error": "Accounts work in the web version."})
		return
	var h := HTTPRequest.new()
	h.timeout = 20.0
	add_child(h)
	h.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray):
		var parsed = JSON.parse_string(bytes.get_string_from_utf8())
		h.queue_free()
		cb.call(code, parsed if typeof(parsed) == TYPE_DICTIONARY else {}))
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var err := h.request(base + path, headers, method, JSON.stringify(body) if body != null else "")
	if err != OK:
		h.queue_free()
		cb.call(0, {"error": "Couldn't reach the server."})

func _set_auth(t: String, e: String) -> void:
	token = t
	email = e
	if Game.test_mode:
		return
	_write_json(AUTH_PATH, {"token": t, "email": e})

func _load_auth() -> void:
	var d := _read_json(AUTH_PATH)
	token = str(d.get("token", ""))
	email = str(d.get("email", ""))

static func _read_json(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	return d if typeof(d) == TYPE_DICTIONARY else {}

static func _write_json(p: String, d: Dictionary) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
