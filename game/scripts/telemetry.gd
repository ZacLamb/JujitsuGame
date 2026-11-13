class_name Telemetry
## Anonymous play stats for tuning the core loop: one line per fight and one ping per play day.
## No names, emails or chat: a random device id, the level, the zone and how the fight went.
## Only in the web build (needs the Railway server); never in tests.

const DEVICE_FILE := "user://tatame_device.txt"
static var _device := ""

static func device() -> String:
	if _device != "":
		return _device
	if FileAccess.file_exists(DEVICE_FILE):
		var f := FileAccess.open(DEVICE_FILE, FileAccess.READ)
		if f:
			_device = f.get_as_text().strip_edges()
	if _device.length() < 8:
		var c := Crypto.new()
		_device = c.generate_random_bytes(12).hex_encode()
		var w := FileAccess.open(DEVICE_FILE, FileAccess.WRITE)
		if w:
			w.store_string(_device)
	return _device

static func _on() -> bool:
	return not Game.test_mode and Cloud.available()

## Entered the world (once per play session).
static func session() -> void:
	if not _on():
		return
	Cloud._req(HTTPClient.METHOD_POST, "/api/t/session", {"d": device(), "lv": Game.player_level(), "st": Game.style}, func(_c, _r): pass)

## One fight, won / lost / left. rep is the roll report (see WorldCombat._track).
static func fight(rep: Dictionary, hp_frac: float) -> void:
	if not _on():
		return
	var out := "won" if bool(rep.get("won", false)) else ("lost" if bool(rep.get("lost", false)) else "left")
	Cloud._req(HTTPClient.METHOD_POST, "/api/t/fight", {
		"d": device(), "lv": int(rep.get("level", Game.player_level())), "z": str(rep.get("zone", "")),
		"o": out, "s": snappedf(float(rep.get("secs", 0.0)), 0.1), "g": str(rep.get("grade", "")),
		"r": int(rep.get("reads", 0)), "c": int(rep.get("caught", 0)), "w": int(rep.get("whiffs", 0)),
		"e": int(rep.get("escapes", 0)), "f": int(rep.get("feints", 0)), "ch": int(rep.get("chains", 0)),
		"hp": snappedf(hp_frac, 0.01), "foe": str(rep.get("foe", "")).left(40), "k": str(rep.get("kind", "mob")),
		"b": int(rep.get("bonus", 0)), "st": Game.style}, func(_c, _r): pass)
