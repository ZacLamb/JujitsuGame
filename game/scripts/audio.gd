extends Node
## Sound effects + music with crossfade. Autoloaded as "Sfx".

const SFX := ["click", "hit", "perfect", "miss", "tap", "squeeze", "win", "lose", "levelup", "collect", "jump", "step_ground", "step_sand"]
const SETTINGS := "user://tatame_settings.json"

var muted := false
## Player preferences (kept apart from game progress): volumes, mouse, graphics.
var prefs := {"music": 0.8, "sfx": 0.9, "ambience": 0.8, "mouse": 1.0, "invert_y": false}
var _streams := {}
var _players: Array = []
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _current := ""
var _amb_day: AudioStreamPlayer
var _amb_night: AudioStreamPlayer
var _amb_zone := ""
var _amb_duck := 0.0   # dB; lowered during rolls

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in SFX:
		var p := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(p):
			_streams[n] = load(p)
	for i in 8:
		var pl := AudioStreamPlayer.new()
		add_child(pl)
		_players.append(pl)
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_ensure_bus("Ambience")
	_amb_day = AudioStreamPlayer.new()
	_amb_night = AudioStreamPlayer.new()
	for a in [_amb_day, _amb_night]:
		a.bus = "Ambience"
		a.volume_db = -60.0
		add_child(a)
	for pl in _players:
		pl.bus = "SFX"
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	_music_a.bus = "Music"
	_music_b.bus = "Music"
	add_child(_music_a)
	add_child(_music_b)
	_load_settings()

func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS):
		var f := FileAccess.open(SETTINGS, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			muted = bool(d.get("muted", false))
			for k in d:
				if k != "muted":
					prefs[k] = d[k]
	AudioServer.set_bus_mute(0, muted)
	_apply_volumes()

func _ensure_bus(n: String) -> void:
	if AudioServer.get_bus_index(n) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, n)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")

func _apply_volumes() -> void:
	for pair in [["Music", "music"], ["SFX", "sfx"], ["Ambience", "ambience"]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i >= 0:
			var v := clampf(float(prefs.get(pair[1], 1.0)), 0.0, 1.0)
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(i, v <= 0.001)

func pref(k: String, default_v: Variant = null) -> Variant:
	return prefs.get(k, default_v)

func set_pref(k: String, v: Variant) -> void:
	prefs[k] = v
	_apply_volumes()
	_save()

func _save() -> void:
	var d := prefs.duplicate()
	d["muted"] = muted
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, muted)
	_save()

func play(n: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(n):
		return
	for pl in _players:
		if not pl.playing:
			pl.stream = _streams[n]
			pl.volume_db = vol_db
			pl.pitch_scale = pitch
			pl.play()
			return

func music(n: String) -> void:
	if n == _current:
		return
	_current = n
	var path := "res://assets/audio/music_%s.ogg" % n
	if not ResourceLoader.exists(path):
		return
	var st: AudioStreamOggVorbis = load(path)
	st.loop = true
	var old := _music_a if _music_a.playing else null
	var nxt := _music_b if old == _music_a else _music_a
	nxt.stream = st
	nxt.volume_db = -40.0
	nxt.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(nxt, "volume_db", -9.0, 1.2)
	if old:
		tw.tween_property(old, "volume_db", -40.0, 1.2)
		tw.chain().tween_callback(old.stop)


# ------------------------------------------------------------ ambience
## Zone soundscape: a day layer and a night layer, mixed by the day/night cycle.
func ambience(zone: String) -> void:
	if zone == _amb_zone:
		return
	_amb_zone = zone
	for pair in [[_amb_day, "day"], [_amb_night, "night"]]:
		var pl: AudioStreamPlayer = pair[0]
		var path := "res://assets/audio/amb_%s_%s.ogg" % [zone, pair[1]]
		if zone == "" or not ResourceLoader.exists(path):
			pl.stop()
			continue
		var st: AudioStreamOggVorbis = load(path)
		st.loop = true
		pl.stream = st
		pl.play(randf() * 10.0)

func duck_ambience(on: bool) -> void:
	_amb_duck = -14.0 if on else 0.0

func _process(_delta: float) -> void:
	if _amb_zone == "":
		return
	var day := DayNight.daylight()
	var tgt_day := lerpf(-40.0, -11.0, day) + _amb_duck
	var tgt_night := lerpf(-40.0, -13.0, 1.0 - day) + _amb_duck
	_amb_day.volume_db = lerpf(_amb_day.volume_db, tgt_day, 0.05)
	_amb_night.volume_db = lerpf(_amb_night.volume_db, tgt_night, 0.05)
