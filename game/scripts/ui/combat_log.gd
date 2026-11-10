class_name CombatLog
extends PanelContainer
## WoW-style chat frame, bottom-left: XP, loot, quest updates, fight results and, when you're
## logged in, live chat with other players (Say / Zone / World / whispers). Enter opens the input
## line; /help lists the commands. The background is faint until you hover it; old lines fade but
## stay in the scrollback.

const MAX_LINES := 120
const CH := {
	"say": {"tag": "", "color": Color(1, 1, 1)},
	"zone": {"tag": "[Zone] ", "color": Color(1.0, 0.76, 0.6)},
	"world": {"tag": "[World] ", "color": Color(1.0, 0.86, 0.5)},
	"whisper": {"tag": "", "color": Color(1.0, 0.5, 1.0)},
	"party": {"tag": "[Party] ", "color": Color(0.55, 0.78, 1.0)},
	"sys": {"tag": "", "color": Color(1.0, 0.95, 0.35)},
	"announce": {"tag": "[Game Master] ", "color": Color(0.4, 0.75, 1.0)},
}
const CH_NAMES := {"say": "Say", "zone": "Zone", "world": "World", "whisper": "Whisper", "party": "Party"}

signal emote_requested(id: String)
static var typing := false
var party: Party = null   # set by Main
var trade: Trade = null   # set by Main
signal gm_requested   # the player reads this so WASD doesn't walk while you type

var _text: RichTextLabel
var _input: LineEdit
var _chan_lbl: Label
var _chat_btn: Button
var _hover := false
var _idle := 0.0
var channel := "zone"   # sticky, like WoW
var whisper_to := ""

func _init() -> void:
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 10
	offset_right = 330
	offset_top = -196
	offset_bottom = -14
	mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.32)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var tab := Wow.label("General  ·  Combat & Loot", 11, Wow.GOLD)
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tab)
	_chat_btn = Button.new()
	_chat_btn.text = "Chat"
	_chat_btn.flat = true
	_chat_btn.focus_mode = Control.FOCUS_NONE
	_chat_btn.add_theme_font_size_override("font_size", 11)
	_chat_btn.add_theme_color_override("font_color", Wow.GOLD)
	_chat_btn.custom_minimum_size = Vector2(0, 16)
	_chat_btn.visible = false
	_chat_btn.pressed.connect(func(): open_input())
	head.add_child(_chat_btn)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_following = true
	_text.fit_content = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.mouse_filter = Control.MOUSE_FILTER_PASS
	_text.add_theme_font_size_override("normal_font_size", 12)
	_text.add_theme_constant_override("outline_size", 3)
	_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	if Wow.body():
		_text.add_theme_font_override("normal_font", Wow.body())
	v.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	_chan_lbl = Wow.label("Zone:", 12, CH.zone.color)
	row.add_child(_chan_lbl)
	_input = LineEdit.new()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.max_length = 200
	_input.add_theme_font_size_override("font_size", 12)
	_input.custom_minimum_size = Vector2(0, 22)
	_input.placeholder_text = "Type a message  ·  /help"
	_input.context_menu_enabled = false
	row.add_child(_input)
	row.visible = false
	_input.text_submitted.connect(_submit)
	_input.text_changed.connect(_on_typed)
	_input.focus_exited.connect(func(): close_input())
	_input.gui_input.connect(func(e: InputEvent):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			_input.text = ""
			close_input()
			_input.accept_event())
	mouse_entered.connect(func(): _hover = true)
	mouse_exited.connect(func(): _hover = false)

func _ready() -> void:
	Net.chat.connect(add_chat)
	Net.status_changed.connect(func(): _chat_btn.visible = Net.connected)

func add(text: String, color := Color.WHITE) -> void:
	_line("[color=#%s]%s[/color]" % [color.to_html(false), _esc(text)])

func _line(bb: String) -> void:
	_text.append_text(bb + "\n")
	if _text.get_paragraph_count() > MAX_LINES:
		_text.remove_paragraph(0)
	_idle = 0.0

static func _esc(t: String) -> String:
	return t.replace("[", "[lb]")

## A chat message from the server (Net.chat).
func add_chat(m: Dictionary) -> void:
	var ch := str(m.get("ch", "sys"))
	var cc: Color = CH.get(ch, CH.sys).color
	var text := _esc(str(m.get("text", "")))
	if ch == "sys":
		_line("[color=#%s]%s[/color]" % [cc.to_html(false), text])
		return
	if ch == "announce":
		_line("[color=#66bfff][Game Master] %s[/color]" % text)
		return
	var nm := str(m.get("from", "?"))
	var who := "[color=#%s]%s[/color]" % [Rpg.class_color(str(m.get("style", ""))).to_html(false), _esc(nm)]
	if m.get("gm", false):
		who = "[color=#66bfff][lb]GM[rb][/color] " + who
	if m.get("watch", false):
		who = "[color=#888888](%s)[/color] " % _esc(str(m.get("zone", "?"))) + who
	var body := ""
	match ch:
		"say":
			body = Tx.s("%s says: %s") % [who, text]
		"whisper":
			if m.get("echo", false):
				body = Tx.s("To %s: %s") % [_esc(str(m.get("to", ""))), text]
			else:
				body = Tx.s("%s whispers: %s") % [who, text]
				Sfx.play("click", -10.0)
		_:
			body = "%s%s: %s" % [Tx.s(CH[ch].tag).replace("[", "[lb]"), who, text]
	_line("[color=#%s]%s[/color]" % [cc.to_html(false), body])

# ------------------------------------------------------------ typing
func open_input(prefill := "") -> void:
	if not Net.connected:
		add_chat({"ch": "sys", "text": "Log in from the title screen to chat with other players."})
		return
	(_input.get_parent() as Control).visible = true
	_set_channel(channel)
	_input.text = prefill
	_input.caret_column = prefill.length()
	_input.grab_focus()
	typing = true
	_idle = 0.0

func close_input() -> void:
	typing = false
	if _input.has_focus():
		_input.release_focus()
	(_input.get_parent() as Control).visible = false

func _set_channel(ch: String) -> void:
	channel = ch
	var n: String = CH_NAMES.get(ch, "Say")
	_chan_lbl.text = (Tx.f("To %s:", whisper_to)) if ch == "whisper" else Tx.s(n) + ":"
	_chan_lbl.add_theme_color_override("font_color", CH.get(ch, CH.say).color)

## WoW-style: typing "/z " or "/w name " switches the channel on the spot.
func _on_typed(t: String) -> void:
	var sw := {"/p ": "party", "/party ": "party", "/s ": "say", "/say ": "say", "/z ": "zone", "/zone ": "zone", "/g ": "world", "/world ": "world", "/1 ": "world"}
	for k in sw:
		if t.to_lower() == k:
			_set_channel(sw[k])
			_input.text = ""
			return
	var low := t.to_lower()
	if (low.begins_with("/w ") or low.begins_with("/whisper ")) and t.ends_with(" ") and t.split(" ", false).size() == 2:
		whisper_to = t.split(" ", false)[1]
		_set_channel("whisper")
		_input.text = ""
	elif low == "/r " and Net.last_whisper != "":
		whisper_to = Net.last_whisper
		_set_channel("whisper")
		_input.text = ""

func _submit(t: String) -> void:
	t = t.strip_edges()
	_input.text = ""
	close_input()
	if t == "":
		return
	if t.begins_with("/"):
		_command(t)
		return
	if channel == "whisper":
		Net.send_chat("whisper", t, whisper_to)
	elif channel == "party":
		if party:
			party.say(t)
	else:
		Net.send_chat(channel, t)

func _command(t: String) -> void:
	var parts := t.split(" ", false)
	var cmd := parts[0].to_lower()
	var emo := Emotes.from_cmd(cmd)
	if emo != "":
		emote_requested.emit(emo)
		return
	if cmd == "/e" or cmd == "/emotes":
		var all: Array = []
		for id in Emotes.LIST:
			all.append(str(Emotes.LIST[id].cmds[0]))
		add_chat({"ch": "sys", "text": Tx.f("Emotes: %s", "  ".join(all))})
		return
	var rest := t.substr(parts[0].length()).strip_edges()
	match cmd:
		"/s", "/say":
			_set_channel("say")
			if rest != "":
				Net.send_chat("say", rest)
		"/z", "/zone":
			_set_channel("zone")
			if rest != "":
				Net.send_chat("zone", rest)
		"/g", "/world", "/1":
			_set_channel("world")
			if rest != "":
				Net.send_chat("world", rest)
		"/w", "/whisper", "/t", "/tell":
			if parts.size() < 3:
				add_chat({"ch": "sys", "text": "Usage: /w Name message"})
				return
			whisper_to = parts[1]
			_set_channel("whisper")
			Net.send_chat("whisper", rest.substr(parts[1].length()).strip_edges(), parts[1])
		"/r", "/reply":
			if Net.last_whisper == "":
				add_chat({"ch": "sys", "text": "No one has whispered you yet."})
				return
			whisper_to = Net.last_whisper
			_set_channel("whisper")
			if rest != "":
				Net.send_chat("whisper", rest, whisper_to)
		"/who":
			Net.who()
		"/p", "/party":
			_set_channel("party")
			if rest != "" and party:
				party.say(rest)
		"/invite", "/inv":
			if party:
				party.invite(rest)
		"/leave", "/leaveparty":
			if party:
				party.leave()
		"/trade":
			if trade:
				trade.request_name(rest)
		"/kick":
			if party:
				party.kick(rest)
		"/promote":
			if party:
				party.promote(rest)
		"/gm":
			gm_requested.emit()
		"/ignore":
			if rest == "":
				add_chat({"ch": "sys", "text": Tx.f("Ignoring: %s", (", ".join(Net.ignored.keys()) if not Net.ignored.is_empty() else "no one"))})
				return
			Net.set_ignored(parts[1], true)
			add_chat({"ch": "sys", "text": Tx.f("%s is now ignored. /unignore %s to undo.", [parts[1], parts[1]])})
		"/unignore":
			if parts.size() > 1:
				Net.set_ignored(parts[1], false)
				add_chat({"ch": "sys", "text": Tx.f("%s is no longer ignored.", parts[1])})
		"/report":
			if parts.size() < 2:
				add_chat({"ch": "sys", "text": "Usage: /report Name reason"})
				return
			Net.report(parts[1], rest.substr(parts[1].length()).strip_edges())
		_:
			add_chat({"ch": "sys", "text": "Chat: Enter to type. /s say (nearby, speech bubble) · /z zone · /g world · /w Name whisper · /r reply · /p party · /invite Name · /leave · /trade Name · /oss /wave /dance (/e for all) · /who · /ignore Name · /report Name reason"})

func _process(delta: float) -> void:
	_idle += delta
	# like WoW's chat: bright while active or hovered, fades out when nothing new happens
	var target := 1.0 if (_hover or typing or _idle < 15.0) else 0.7
	modulate.a = lerpf(modulate.a, target, clampf(delta * 3.0, 0, 1))
