extends Node
## Sound effects + music with crossfade. Autoloaded as "Sfx".

const SFX := ["click", "hit", "perfect", "miss", "tap", "squeeze", "win", "lose", "levelup", "collect", "jump"]
const SETTINGS := "user://tatame_settings.json"

var muted := false
var _streams := {}
var _players: Array = []
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _current := ""

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
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	add_child(_music_a)
	add_child(_music_b)
	_load_settings()

func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS):
		var f := FileAccess.open(SETTINGS, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			muted = bool(d.get("muted", false))
	AudioServer.set_bus_mute(0, muted)

func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, muted)
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"muted": muted}))

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
