class_name Keys
extends RefCounted
## Rebindable keyboard controls (Esc > Keys). A binding replaces the action's first key; other
## keys on it (the arrow keys on movement, say) stay. Saved in the settings file (Sfx prefs "keys")
## and applied at start-up after main registers the defaults.

## [action, label] in the order the settings list shows them.
const LIST := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Strafe left"], ["move_right", "Strafe right"],
	["jump", "Jump"], ["sprint", "Run"], ["autorun", "Auto-run"], ["interact", "Talk / roll / use"], ["target_next", "Next target"],
	["ab_0", "Move 1"], ["ab_1", "Move 2"], ["ab_2", "Move 3"], ["ab_3", "Move 4"], ["ab_4", "Move 5"],
	["ab_5", "Move 6"], ["ab_6", "Move 7"], ["ab_7", "Move 8"], ["ab_8", "Move 9"], ["ab_9", "Move 10"],
	["ab_base", "Sprawl / Base"], ["ab_frame", "Frame"], ["ab_defend", "Defend"], ["ab_breathe", "Breathe"], ["ab_racial", "Origin racial"],
	["character", "Character"], ["talents", "Talents"], ["spellbook", "Moves"], ["bags", "Bags"], ["journal", "Quest log"],
	["map", "World map"], ["finder", "Group finder"], ["arena", "Ranked arena"],
]
## Fight-pad directions follow the movement keys.
const MIRROR := {"move_forward": "dir_up", "move_back": "dir_down", "move_left": "dir_left", "move_right": "dir_right"}
## Never bindable: they belong to the game menu, chat and the mouse.
const RESERVED := [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]

static var _defaults := {}   # action -> its first default keycode (for Reset)

static func remember_defaults() -> void:
	for row in LIST:
		var k := primary(str(row[0]))
		if k != KEY_NONE:
			_defaults[row[0]] = k

static func primary(action: String) -> int:
	if not InputMap.has_action(action):
		return KEY_NONE
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return (ev as InputEventKey).physical_keycode
	return KEY_NONE

## The key a player presses for an action, as text ("W", "Shift", "1").
static func label(action: String) -> String:
	var k := primary(action)
	if k == KEY_NONE:
		return "-"
	var s := OS.get_keycode_string(k)
	return s if s != "" else "?"

static func _set_primary(action: String, key: int) -> void:
	var evs := InputMap.action_get_events(action)
	var first := true
	for ev in evs:
		if ev is InputEventKey and first:
			InputMap.action_erase_event(action, ev)
			first = false
	var ne := InputEventKey.new()
	ne.physical_keycode = key
	# put the new key first so labels show it
	var rest := InputMap.action_get_events(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, ne)
	for ev in rest:
		if not (ev is InputEventKey and (ev as InputEventKey).physical_keycode == key):
			InputMap.action_add_event(action, ev)

## Binds key to action. Returns the label of an action that lost the key to it ("" if none).
static func bind(action: String, key: int, save := true) -> String:
	if key in RESERVED:
		return ""
	var bumped := ""
	for row in LIST:
		var other: String = row[0]
		if other == action:
			continue
		for ev in InputMap.action_get_events(other):
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
				InputMap.action_erase_event(other, ev)
				bumped = str(row[1])
				if MIRROR.has(other):
					_strip(MIRROR[other], key)
	var old := primary(action)
	_set_primary(action, key)
	if MIRROR.has(action):
		var mirror: String = MIRROR[action]
		_strip(mirror, old)
		_strip(mirror, key)
		var me := InputEventKey.new()
		me.physical_keycode = key
		InputMap.action_add_event(mirror, me)
	if save:
		_save()
	return bumped

static func _strip(action: String, key: int) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
			InputMap.action_erase_event(action, ev)

static func _save() -> void:
	var d := {}
	for row in LIST:
		var a: String = row[0]
		var k := primary(a)
		if k != KEY_NONE and k != int(_defaults.get(a, KEY_NONE)):
			d[a] = k
	Sfx.set_pref("keys", d)

static func load_saved() -> void:
	remember_defaults()
	var d = Sfx.pref("keys", {})
	if d is Dictionary:
		for a in d:
			if InputMap.has_action(str(a)):
				bind(str(a), int(d[a]), false)

static func reset() -> void:
	for a in _defaults:
		bind(str(a), int(_defaults[a]), false)
	Sfx.set_pref("keys", {})
