extends Node
## Languages. English is the source text; every other language is a JSON table in res://i18n
## (English text -> translation), loaded into Godot's TranslationServer at start-up.
##
## How text gets translated:
##   * Labels, buttons, tooltips, 3D labels: automatically, when their text is an exact key.
##   * Formatted text ("Win rolls around %s (%d/%d)."): through Tx.f(), which translates the
##     pattern and any text arguments (a quest title, an item name...).
## Adding text: run tools/i18n_extract.py (lists every display string in i18n/keys.json), add
## [english, portuguese, spanish] rows to a file in i18n/src/, then run tools/i18n_merge.py
## (checks that %s / %d placeholders match and writes i18n/pt_BR.json and i18n/es.json).
## Missing translations simply show the English text.

const LANGS := {"en": "English", "pt_BR": "Português (Brasil)", "es": "Español"}
const ORDER := ["en", "pt_BR", "es"]

var current := "en"
signal changed

func _ready() -> void:
	for code in ORDER:
		if code == "en":
			continue
		var p := "res://i18n/%s.json" % code
		if not FileAccess.file_exists(p):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if not d is Dictionary:
			continue
		var t := Translation.new()
		t.locale = code
		for k in d:
			if str(d[k]) != "":
				t.add_message(str(k), str(d[k]))
		TranslationServer.add_translation(t)
	var saved := _saved()
	for arg in OS.get_cmdline_user_args():   # tests / probes: -- lang=pt_BR
		if str(arg).begins_with("lang="):
			saved = str(arg).substr(5)
	set_lang(saved if saved != "" else detect(), false)

## The player's system / browser language, if we have it.
static func detect() -> String:
	var l := OS.get_locale()
	if l.begins_with("pt"):
		return "pt_BR"
	if l.begins_with("es"):
		return "es"
	return "en"

func set_lang(code: String, save := true) -> void:
	if not LANGS.has(code):
		code = "en"
	current = code
	TranslationServer.set_locale(code)
	if save:
		Sfx.set_pref("lang", code)   # the shared settings file (Sfx owns it)
	changed.emit()

const SETTINGS := "user://tatame_settings.json"

func _saved() -> String:
	if not FileAccess.file_exists(SETTINGS):
		return ""
	var x = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	return str(x.get("lang", "")) if x is Dictionary else ""
