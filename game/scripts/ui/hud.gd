class_name Hud
extends CanvasLayer
## Exploration HUD: rank, XP, objective, prompts, toasts, dialogue, journal and title screen.

signal play_pressed
signal dialogue_choice(accepted: bool)
signal journal_toggled(open: bool)
signal travel_chosen(zone: String)
signal daily_requested
signal graphics_changed
signal shop_closed

var root: Control
var minimap: Minimap
var gfx_btn: Button
var rank_box: VBoxContainer
var xp_bar: ProgressBar
var zone_lbl: Label
const XP_COLOR := Color(0.62, 0.36, 1.0)       # experience purple
const XP_CAP_COLOR := Color(0.98, 0.76, 0.24)   # gold when capped at the belt
var rank_label: Label
var chip_holder: Control
var objective: Label
var prompt: Label
var toasts: VBoxContainer
var dialogue: PanelContainer
var dlg_name: Label
var dlg_text: Label
var dlg_yes: Button
var dlg_no: Button
var journal: Wow.Frame
var journal_tabs: TabContainer
var title: Control
var touch: TouchControls
var journal_btn: Button
var status_panels: Array = []
var touch_mode := false
var _obj_panel: Control
var lvl_label: Label
var _sel_talent := ""
var _want_tab := -1

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not touch_mode:
		touch_mode = true
		touch.visible = _touch_allowed()

func _touch_allowed() -> bool:
	return (touch_mode or DisplayServer.is_touchscreen_available()) and not title.visible and not dialogue.visible and not journal.visible

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the settings menu works while the game is paused
	root = Control.new()
	root.theme = UiKit.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_status()
	_build_prompt()
	_build_toasts()
	_build_dialogue()
	_build_journal()
	touch = TouchControls.new()
	minimap = Minimap.new()
	root.add_child(minimap)
	status_panels.append(minimap)
	root.add_child(touch)
	touch.visible = false
	wallet = BagUi.Wallet.new()
	root.add_child(wallet)
	status_panels.append(wallet)
	wallet.open_bags.connect(toggle_bag)
	bag_panel = BagUi.BagPanel.new()
	bag_panel.visible = false
	root.add_child(bag_panel)
	bag_panel.visibility_changed.connect(func(): wallet.visible = not bag_panel.visible and title != null and not title.visible)
	_build_title()
	for p in status_panels:
		p.visible = false
	Game.toast.connect(show_toast)
	Game.achievement_unlocked.connect(_on_achievement)
	Game.progress_changed.connect(refresh)
	refresh()

# ------------------------------------------------------------ status
func _build_status() -> void:
	# --- player unit frame (top-left, like WoW): round emblem + level badge, name, belt, XP
	var uf := Control.new()
	uf.position = Vector2(12, 10)
	uf.size = Vector2(340, 96)
	uf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(uf)
	status_panels.append(uf)
	var plate := Panel.new()
	plate.position = Vector2(40, 8)
	plate.size = Vector2(296, 62)
	var ps := Wow.sb(Color(0.03, 0.03, 0.05, 0.82), Color(Wow.FRAME, 0.9), 4, 0, 1)
	plate.add_theme_stylebox_override("panel", ps)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	uf.add_child(plate)
	_portrait = Wow.Emblem.new()
	_portrait.custom_minimum_size = Vector2(72, 72)
	_portrait.size = Vector2(72, 72)
	_portrait.scale = Vector2(72.0 / 62.0, 72.0 / 62.0)
	uf.add_child(_portrait)
	_lvl_badge = LevelBadge.new()
	_lvl_badge.position = Vector2(46, 50)
	uf.add_child(_lvl_badge)
	rank_box = VBoxContainer.new()   # kept for compatibility with older code
	rank_label = Wow.title("", 15, Wow.GOLD)
	rank_label.position = Vector2(82, 10)
	rank_label.size = Vector2(250, 20)
	uf.add_child(rank_label)
	chip_holder = Control.new()
	chip_holder.position = Vector2(82, 32)
	chip_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	uf.add_child(chip_holder)
	xp_bar = UiKit.bar(XP_COLOR, Vector2(246, 12))
	xp_bar.position = Vector2(82, 52)
	xp_bar.size = Vector2(246, 12)
	xp_bar.add_theme_stylebox_override("background", Wow.sb(Color(0.06, 0.03, 0.1, 0.9), Color(0, 0, 0, 0.9), 2, 0))
	uf.add_child(xp_bar)
	_xp_text = Wow.label("", 11, Wow.WHITE, false, HORIZONTAL_ALIGNMENT_CENTER)
	_xp_text.position = Vector2(82, 49)
	_xp_text.size = Vector2(246, 16)
	uf.add_child(_xp_text)
	lvl_label = Wow.label("", 13, Wow.GREEN)
	lvl_label.position = Vector2(84, 72)
	lvl_label.size = Vector2(260, 18)
	uf.add_child(lvl_label)
	# --- objective tracker (right side, under the round minimap)
	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -330
	right.offset_right = -14
	right.offset_top = 262
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 2)
	root.add_child(right)
	_obj_panel = right
	status_panels.append(right)
	zone_lbl = Wow.title("Objectives", 15, Wow.GOLD)
	right.add_child(zone_lbl)
	var line := ColorRect.new()
	line.color = Color(Wow.GOLD, 0.45)
	line.custom_minimum_size = Vector2(0, 1)
	right.add_child(line)
	objective = Wow.label("", 14, Wow.WHITE, true)
	objective.custom_minimum_size = Vector2(300, 0)
	right.add_child(objective)
	_tracker = VBoxContainer.new()
	_tracker.add_theme_constant_override("separation", 1)
	right.add_child(_tracker)
	# --- micro menu (bottom-right): character, talents, bags, quest log, map, menu
	var micro := HBoxContainer.new()
	micro.anchor_left = 1.0
	micro.anchor_right = 1.0
	micro.anchor_top = 1.0
	micro.anchor_bottom = 1.0
	micro.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	micro.grow_vertical = Control.GROW_DIRECTION_BEGIN
	micro.offset_right = -14
	micro.offset_bottom = -12
	micro.add_theme_constant_override("separation", 3)
	root.add_child(micro)
	status_panels.append(micro)
	for e in [["shield", "Character (C)", func(): open_window("character")], ["star", "Specs, Talents & Spellbook (N)", func(): open_window("talents")],
			["lock", "Bags (B)", toggle_bag], ["link", "Quest Log (L)", func(): open_window("journal")],
			["wave", "World Map (M)", func(): minimap.toggle_big()], ["loop", "Game Menu (Esc)", toggle_settings]]:
		var mb := MicroButton.new()
		mb.glyph = e[0]
		mb.tooltip_text = e[1]
		mb.pressed.connect(e[2])
		micro.add_child(mb)
	journal_btn = null
	gfx_btn = null

var _portrait: Wow.Emblem
var _lvl_badge: Control
var _xp_text: Label
var _tracker: VBoxContainer

## Small round level number on the portrait.
class LevelBadge extends Control:
	var level := 1
	var hot := false
	func _init() -> void:
		size = Vector2(28, 28)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, 13, Color(0, 0, 0, 0.9))
		draw_circle(c, 11.5, Wow.FRAME)
		draw_circle(c, 10, Color(0.08, 0.06, 0.05))
		var f: Font = Wow.body() if Wow.body() else ThemeDB.fallback_font
		draw_string(f, Vector2(0, c.y + 5), str(level), HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Wow.GREEN if hot else Wow.GOLD)

## Square micro-menu button with a glyph (WoW's bottom-right buttons).
class MicroButton extends Button:
	var glyph := "star"
	func _init() -> void:
		custom_minimum_size = Vector2(34, 40)
		focus_mode = Control.FOCUS_NONE
		var n := Wow.button_box(Color(0.12, 0.08, 0.07), Wow.FRAME)
		var h := Wow.button_box(Color(0.22, 0.15, 0.1), Wow.FRAME_HI)
		add_theme_stylebox_override("normal", n)
		add_theme_stylebox_override("hover", h)
		add_theme_stylebox_override("pressed", h)
	func _draw() -> void:
		CharSheet.draw_glyph(self, glyph, size / 2.0, 20, Wow.GOLD)

const STYLE_GLYPH := {"guard": "loop", "wrestler": "down", "judoka": "link", "athlete": "bolt", "passer": "chevron"}

func set_portrait(p: bool) -> void:
	if _obj_panel == null:
		return
	if p:
		_obj_panel.anchor_left = 0.0
		_obj_panel.offset_left = 14
		_obj_panel.offset_top = 130
		objective.custom_minimum_size = Vector2(0, 0)
		toasts.offset_top = 276
		toasts.offset_left = -250
		toasts.offset_right = 250
	else:
		_obj_panel.anchor_left = 1.0
		_obj_panel.offset_left = -330
		_obj_panel.offset_top = 262
		objective.custom_minimum_size = Vector2(300, 0)
		toasts.offset_top = 110
		toasts.offset_left = -300
		toasts.offset_right = 300

func refresh() -> void:
	rank_label.text = Game.player_name
	for c in chip_holder.get_children():
		c.queue_free()
	var chip := UiKit.belt_chip(Game.rank, Vector2(246, 14))
	chip_holder.add_child(chip)
	var bt := Wow.label(Data.rank_name(Game.rank), 11, Wow.WHITE if Data.belt_of(Game.rank) != 0 else Color(0.15, 0.12, 0.1), false, HORIZONTAL_ALIGNMENT_LEFT)
	bt.position = Vector2(6, -1)
	bt.add_theme_constant_override("outline_size", 2 if Data.belt_of(Game.rank) != 0 else 0)
	chip_holder.add_child(bt)
	var capped := Game.level_capped()
	xp_bar.value = 100.0 * Game.level_progress()
	xp_bar.add_theme_stylebox_override("fill", Wow.sb(XP_CAP_COLOR if capped else XP_COLOR, Color(0, 0, 0, 0), 2, 0))
	var lv := Game.player_level()
	_portrait.glyph = STYLE_GLYPH.get(Game.style, "shield")
	var sp := Specs.get_spec(Game.spec)
	_portrait.col = Team.ROLES[sp.role].color if not sp.is_empty() else Wow.GOLD
	_portrait.queue_redraw()
	var pts := Game.attr_points() + Game.talent_points()
	(_lvl_badge as LevelBadge).level = lv
	(_lvl_badge as LevelBadge).hot = pts > 0
	_lvl_badge.queue_redraw()
	if capped and lv < Game.MAX_LEVEL:
		_xp_text.text = "Belt cap: beat the boss"
	elif capped:
		_xp_text.text = "Max level"
	else:
		_xp_text.text = "%d / %d XP" % [int(Game.level_progress() * Game.XP_PER_LEVEL), Game.XP_PER_LEVEL]
	var parts: Array = []
	if Game.attr_points() > 0:
		parts.append("%d attribute (C)" % Game.attr_points())
	if Game.talent_points() > 0:
		parts.append("%d talent (N)" % Game.talent_points())
	lvl_label.text = ("Points to spend: " + ", ".join(parts)) if not parts.is_empty() else ""
	# objective tracker
	objective.text = Game.current_objective()
	for c in _tracker.get_children():
		c.queue_free()
	for id in Game.active_quests(Game.zone).slice(0, 4):
		var q: Dictionary = Data.QUESTS[id]
		_tracker.add_child(Wow.label(str(q.title), 14, Wow.GOLD))
		if Game.quest_ready(id):
			_tracker.add_child(Wow.label("  - Return to %s" % Data.QUEST_GIVERS[q.giver].name, 13, Wow.GREEN))
		else:
			var pr := Game.objective_progress(id, 0)
			_tracker.add_child(Wow.label("  - %d/%d %s" % [pr[0], pr[1], q.obj[0].text], 13, Wow.WHITE, true))
	zone_lbl.text = "Objectives"
	if journal.visible:
		_fill_journal()

# ------------------------------------------------------------ prompt
func _build_prompt() -> void:
	prompt = UiKit.label("", 24, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	prompt.anchor_left = 0.2
	prompt.anchor_right = 0.8
	prompt.anchor_top = 0.72
	prompt.anchor_bottom = 0.72
	root.add_child(prompt)

# ------------------------------------------------------------ mouse hover tooltip
var _hover_lbl: Label

func set_hover(text: String) -> void:
	if _hover_lbl == null:
		_hover_lbl = UiKit.label("", 17, UiKit.TEXT)
		_hover_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		_hover_lbl.add_theme_stylebox_override("normal", UiKit.box(Color(0.05, 0.07, 0.06, 0.88), 8, UiKit.ACCENT.darkened(0.3), 1))
		_hover_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(_hover_lbl)
	_hover_lbl.text = text
	_hover_lbl.visible = text != ""
	_hover_lbl.reset_size()

func place_hover(mouse: Vector2) -> void:
	if _hover_lbl and _hover_lbl.visible:
		_hover_lbl.position = mouse + Vector2(18, 14)

func set_spot_prompt(spot: Dictionary) -> void:
	if spot.is_empty():
		prompt.text = ""
		touch.interact_btn.visible = false
		return
	var extra := ""
	if spot.action == "drill" and not Game.drills_ready:
		extra = "  (roll first)"
	prompt.text = "[E]  %s%s" % [spot.label, extra]
	touch.interact_btn.visible = true
	touch.interact_btn.text = "TALK" if spot.action == "quest" else "GO"

func set_prompt(npc: Npc) -> void:
	if npc == null:
		prompt.text = ""
		touch.interact_btn.visible = false
		return
	if not npc.mob.is_empty():
		prompt.text = "[E]  Roll with %s (Lv %d)" % [npc.mob.name, Data.display_level(float(npc.mob.level))]
		touch.interact_btn.visible = true
		touch.interact_btn.text = "ROLL"
		return
	var o: Dictionary = Data.OPPONENTS[npc.opp_id]
	var verb := "Talk to" if Data.OPPONENTS[npc.opp_id].get("boss", false) else "Roll with"
	prompt.text = "[E]  %s %s" % [verb, o.name]
	touch.interact_btn.visible = true
	touch.interact_btn.text = "TALK" if Data.OPPONENTS[npc.opp_id].get("boss", false) else "ROLL"

# ------------------------------------------------------------ toasts
func _build_toasts() -> void:
	toasts = VBoxContainer.new()
	toasts.anchor_left = 0.5
	toasts.anchor_right = 0.5
	toasts.offset_left = -300
	toasts.offset_right = 300
	toasts.offset_top = 110
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.add_theme_constant_override("separation", 8)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)

func show_toast(text: String, color := Color.WHITE) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.7), 12, color * Color(1, 1, 1, 0.8)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 21, color, HORIZONTAL_ALIGNMENT_CENTER)
	p.add_child(l)
	toasts.add_child(p)
	if toasts.get_child_count() > 4:
		toasts.get_child(0).queue_free()
	var tw := p.create_tween()
	p.modulate.a = 0.0
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)

func _on_achievement(id: String) -> void:
	var a := Data.achievement(id)
	Sfx.play("perfect", -4.0)
	show_toast("Achievement unlocked: %s" % a.name, UiKit.ACCENT)

# ------------------------------------------------------------ dialogue
func _build_dialogue() -> void:
	dialogue = PanelContainer.new()
	dialogue.anchor_left = 0.08
	dialogue.anchor_right = 0.92
	dialogue.anchor_top = 1.0
	dialogue.anchor_bottom = 1.0
	dialogue.offset_bottom = -20
	dialogue.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dialogue.visible = false
	root.add_child(dialogue)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	dialogue.add_child(v)
	dialogue.add_theme_stylebox_override("panel", Wow.parchment())
	dialogue.theme = Wow.theme()
	dialogue.anchor_left = 0.22
	dialogue.anchor_right = 0.78
	dlg_name = Wow.title("", 20, Color(0.45, 0.2, 0.05))
	dlg_name.add_theme_constant_override("outline_size", 0)
	v.add_child(dlg_name)
	dlg_text = Wow.label("", 17, Wow.INK, true)
	dlg_text.add_theme_constant_override("outline_size", 0)
	v.add_child(dlg_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	dlg_no = Wow.button("Later", Vector2(130, 34))
	dlg_no.pressed.connect(func(): _close_dialogue(false))
	row.add_child(dlg_no)
	dlg_yes = Wow.button("Oss! Let's roll", Vector2(190, 34))
	dlg_yes.pressed.connect(func(): _close_dialogue(true))
	row.add_child(dlg_yes)

func open_dialogue(speaker: String, text: String, yes_text := "Oss! Let's roll", no_text := "Later") -> void:
	dlg_name.text = speaker
	dlg_text.text = text
	dlg_yes.text = yes_text
	dlg_yes.visible = yes_text != ""
	dlg_no.text = no_text
	dialogue.visible = true
	prompt.visible = false
	touch.release_all()
	touch.visible = false

func _close_dialogue(accepted: bool) -> void:
	dialogue.visible = false
	prompt.visible = true
	touch.visible = _touch_allowed()
	dialogue_choice.emit(accepted)

func dialogue_open() -> bool:
	return dialogue.visible

# ------------------------------------------------------------ journal
func _build_journal() -> void:
	journal = Wow.Frame.new()
	journal.visible = false
	root.add_child(journal)
	journal.close_pressed.connect(toggle_journal)
	journal.tab_pressed.connect(func(i: int):
		var g: Dictionary = WINDOWS[_window]
		_want_tab = int(g.tabs[i])
		_fill_journal())
	journal_tabs = TabContainer.new()
	journal_tabs.tabs_visible = false
	journal_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	journal.body.add_child(journal_tabs)

## Journal tab indices (built in _fill_journal) grouped into WoW-like windows.
const TAB_CHARACTER := 0
const TAB_TALENTS := 1
const TAB_GEAR := 2
const TAB_SPECS := 3
const TAB_QUESTS := 4
const TAB_ACHIEVEMENTS := 5
const TAB_SPELLBOOK := 6
const TAB_FIGHTERS := 7
const WINDOWS := {
	"character": {"tabs": [0, 2], "names": ["Character", "Wardrobe"], "size": Vector2(860, 530), "at": "left", "glyph": "shield"},
	"talents": {"tabs": [3, 1, 6], "names": ["Specialization", "Talents", "Spellbook"], "size": Vector2(1160, 580), "at": "center", "glyph": "star"},
	"journal": {"tabs": [4, 5, 7], "names": ["Quests", "Achievements", "Fighters"], "size": Vector2(900, 540), "at": "center", "glyph": "link"},
}
var _window := "character"

static func window_of(tab: int) -> String:
	for w in WINDOWS:
		if tab in WINDOWS[w].tabs:
			return w
	return "journal"

func open_window(w: String) -> void:
	if journal.visible and _window == w:
		toggle_journal()
		return
	_want_tab = int(WINDOWS[w].tabs[0]) if w != "talents" else (TAB_TALENTS if Game.talent_points() > 0 or Game.spec != "" else TAB_SPECS)
	if not journal.visible:
		toggle_journal()
	else:
		_fill_journal()

func _layout_window() -> void:
	var g: Dictionary = WINDOWS[_window]
	var vs := root.size if root.size.x > 0 else Vector2(1280, 720)
	var sz: Vector2 = g.size
	sz = Vector2(minf(sz.x, vs.x - 40), minf(sz.y, vs.y - 60))
	journal.size = sz
	# below the player frame (top-left) so the emblem doesn't cover it, tabs above the screen edge
	journal.position = Vector2(48, 140) if g.at == "left" else Vector2(floorf((vs.x - sz.x) * 0.5), maxf(100.0, vs.y - sz.y - 44.0))
	if journal.position.y + sz.y + 32 > vs.y:
		journal.position.y = maxf(8.0, vs.y - sz.y - 34)
	var cur := journal_tabs.current_tab
	journal.set_tabs(g.names, (g.tabs as Array).find(cur))
	var st: String = Rpg.STYLES[Game.style].name if Rpg.STYLES.has(Game.style) else ""
	match _window:
		"character":
			journal.title_lbl.text = Game.player_name
		"talents":
			journal.title_lbl.text = {TAB_SPECS: "Specialization", TAB_TALENTS: "Talents", TAB_SPELLBOOK: "Spellbook"}.get(cur, "Talents") + ("  ·  " + st if st != "" else "")
		_:
			journal.title_lbl.text = {TAB_QUESTS: "Quest Log", TAB_ACHIEVEMENTS: "Achievements", TAB_FIGHTERS: "Fighters"}.get(cur, "Journal")
	var sp := Specs.get_spec(Game.spec)
	journal.set_emblem(str(sp.get("role", "")) if false else str(g.glyph), Team.ROLES[sp.role].color if not sp.is_empty() else Wow.GOLD)

func open_character() -> void:
	open_window("character")

func toggle_journal() -> void:
	journal.visible = not journal.visible
	minimap.visible = not journal.visible
	if wallet:
		wallet.visible = not journal.visible and not bag_panel.visible
	if journal.visible:
		journal.move_to_front()
		if _want_tab < 0:
			_want_tab = int(WINDOWS[_window].tabs[0]) if journal_tabs.get_tab_count() == 0 else journal_tabs.current_tab
		_fill_journal()
		touch.release_all()
	touch.visible = _touch_allowed()
	journal_toggled.emit(journal.visible)

func _fill_gear() -> void:
	var sc := ScrollContainer.new()
	sc.name = "Gear"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	journal_tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	sc.add_child(v)
	var owned := 0
	for id in Gear.ITEMS:
		if Game.has_item(id):
			owned += 1
	v.add_child(Wow.label("Wardrobe  ·  %d / %d collected  ·  wearing your %s kit  ·  click an item to wear it" % [owned, Gear.ITEMS.size(), Gear.KIT_NAMES[Game.kit]], 14, Wow.GOLD))
	for slot in Gear.SLOTS:
		v.add_child(Wow.banner(Gear.SLOT_NAMES[slot]))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		v.add_child(row)
		var cur := str(Game.equipped.get(slot, ""))
		for id in Gear.ITEMS:
			var it: Dictionary = Gear.ITEMS[id]
			if it.slot != slot:
				continue
			row.add_child(_wardrobe_item(str(id), slot, cur == id))

func _wardrobe_item(id: String, slot: String, worn: bool) -> Control:
	var have := Game.has_item(id)
	var rc: Color = Gear.rarity_color(id)
	var b := CharSheet.SlotSquare.new()
	b.item = id
	b.slot = slot
	b.tooltip_text = " "
	b.custom_minimum_size = Vector2(46, 46)
	var st := Wow.sb(Color(rc.darkened(0.8), 0.95) if have else Color(0.03, 0.03, 0.04, 0.9), rc if have else Color(rc, 0.25), 3, 3, 3 if worn else 1)
	if worn:
		st.border_color = Wow.GOLD
		st.shadow_color = Color(Wow.GOLD, 0.35)
		st.shadow_size = 5
	b.add_theme_stylebox_override("panel", st)
	b.modulate = Color(1, 1, 1, 1.0 if have else 0.45)
	var ic := CharSheet.SlotIcon.new()
	ic.kind = slot
	ic.empty = not have
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if have:
		var lk := Gear.look(id)
		ic.col = lk.get("color", Color(0.95, 0.95, 0.9))
		if id == "standard_gi" or id == "standard_gi_pants":
			ic.col = Game.gi_color()
		ic.accent = lk.get("accent", Color(0, 0, 0, 0))
		ic.trim = lk.get("trim", Color(0, 0, 0, 0))
	b.add_child(ic)
	if have and not worn:
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				Game.equip(id)
				_want_tab = journal_tabs.current_tab
				_fill_journal())
	return b

func _scroll_tab(name_: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name_
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	journal_tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return v

func _fill_journal() -> void:
	var cur := journal_tabs.current_tab
	if _want_tab >= 0:
		cur = _want_tab
		_want_tab = -1
	for c in journal_tabs.get_children():
		journal_tabs.remove_child(c)
		c.queue_free()
	_fill_character()
	_fill_talents()
	_fill_gear()
	_fill_specs()
	# Quests
	var q := _scroll_tab("Quests")
	q.add_child(_daily_box())
	q.add_child(UiKit.label("Main: " + Game.current_objective(), 22, UiKit.ACCENT))
	var held := 0
	var hot: Array = []
	for tid in Data.TERRITORIES:
		if Game.holds(tid):
			held += 1
			if Game.territory_state(tid) == "attacked":
				hot.append(Data.TERRITORIES[tid].name)
	var tl := "Academy wars: Gringo BJJ holds %d / %d territories." % [held, Data.TERRITORIES.size()]
	if not hot.is_empty():
		tl += "  UNDER ATTACK: %s" % ", ".join(hot)
	q.add_child(UiKit.label(tl, 18, Color(1, 0.45, 0.35) if not hot.is_empty() else Color(0.55, 0.9, 0.65)))
	var act := Game.active_quests()
	if not act.is_empty():
		q.add_child(UiKit.label("Quest log", 22, UiKit.ACCENT))
		for id in act:
			var qd: Dictionary = Data.QUESTS[id]
			var gz: String = Data.QUEST_GIVERS[qd.giver].zone
			var head := "%s  (%s, %s)" % [qd.title, Data.QUEST_GIVERS[qd.giver].name, Data.ZONES[gz].name]
			q.add_child(UiKit.label(head, 20, Color(1, 0.85, 0.3) if Game.quest_ready(id) else UiKit.TEXT))
			for i in qd.obj.size():
				var pr := Game.objective_progress(id, i)
				q.add_child(UiKit.label("     %s: %d/%d%s" % [qd.obj[i].text, pr[0], pr[1], "  (done)" if pr[0] >= pr[1] else ""], 17, UiKit.MUTED))
	var ndone := 0
	for id in Data.QUESTS:
		if Game.quest_state(id) == "done":
			ndone += 1
	q.add_child(UiKit.label("Quests completed: %d / %d" % [ndone, Data.QUESTS.size()], 18, UiKit.MUTED))
	for s in Game.side_objectives():
		q.add_child(UiKit.label("•  " + s, 20))
	q.add_child(UiKit.label("Next stripe: %d / %d XP%s" % [Game.xp_into_stripe(), Data.XP_PER_STRIPE, "  (stripe cap: beat %s to promote)" % Data.OPPONENTS[Data.ZONES[Game.zone].boss].name if Game.at_stripe_cap() and Data.ZONES.has(Game.zone) else ""], 18, UiKit.MUTED))
	if Data.COMMUNITY_URL != "":
		var cb := UiKit.button(Data.COMMUNITY_LABEL, Vector2(260, 52))
		cb.pressed.connect(func(): UiKit.open_url(Data.COMMUNITY_URL))
		q.add_child(cb)
	var reset := UiKit.button("Reset progress", Vector2(200, 44))
	reset.add_theme_font_size_override("font_size", 16)
	reset.pressed.connect(func():
		if reset.text == "Tap again to confirm":
			Game.reset()
			get_tree().reload_current_scene()
		else:
			reset.text = "Tap again to confirm")
	q.add_child(reset)
	# Achievements
	var a := _scroll_tab("Achievements")
	journal_tabs.set_tab_title(journal_tabs.get_tab_count() - 1, "Achievements %d/%d" % [Game.unlocked.size(), Data.ACHIEVEMENTS.size()])
	for ach in Data.ACHIEVEMENTS:
		var got := Game.unlocked.has(ach.id)
		if ach.get("hidden", false) and not got:
			a.add_child(_ach_row(false, "???", "Hidden achievement", ""))
			continue
		var prog := ""
		if ach.has("goal") and not got:
			prog = "  (%d/%d)" % [mini(Game.counter(ach.id), int(ach.goal)), int(ach.goal)]
		a.add_child(_ach_row(got, ach.name, ach.desc, prog))
	_fill_spellbook()
	# Fighters
	var f := _scroll_tab("Fighters")
	for id in Data.OPPONENTS:
		var o: Dictionary = Data.OPPONENTS[id]
		var rec := "W %d · L %d" % [int(Game.wins.get(id, 0)), int(Game.losses.get(id, 0))]
		f.add_child(UiKit.label("%s — %s, Lv %d  (%s)" % [o.name, o.title, Data.display_level(float(o.level)), rec], 19, Data.con_color(Data.display_level(float(o.level)), Game.player_level())))
		var pl := Data.personality(o, id)
		if pl.plan != "" and (Game.beaten(id) or int(Game.losses.get(id, 0)) > 0 or Data.zone_of(id) == Game.zone):
			var favs: Array[String] = []
			for mv in pl.fav:
				favs.append(str(Data.MOVES[mv].name))
			f.add_child(UiKit.label("     %s  Favorites: %s." % [pl.plan, ", ".join(favs)], 16, UiKit.MUTED))
	journal_tabs.current_tab = clampi(cur, 0, journal_tabs.get_tab_count() - 1)
	_window = window_of(journal_tabs.current_tab)
	_wowify(journal_tabs.get_child(journal_tabs.current_tab))
	_layout_window()

func _fill_character() -> void:
	var sc := ScrollContainer.new()
	sc.name = "Character"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	journal_tabs.add_child(sc)
	var page := CharSheet.build_character_wow(self)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(page)

func _fill_talents() -> void:
	var t := _scroll_tab("Talents")
	var tp := Game.talent_points()
	journal_tabs.set_tab_title(journal_tabs.get_tab_count() - 1, "Talents (%d)" % tp if tp > 0 else "Talents")
	t.add_child(CharSheet.build_talents_wow(self))
	t.get_parent().set_meta("wow", true)

func _daily_box() -> Control:
	var dc := Game.daily_challenge()
	var rd: Dictionary = Data.DAILY_RULES[dc.rule]
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiKit.box(Color(0.25, 0.2, 0.05, 0.6), 12, UiKit.ACCENT))
	var v := VBoxContainer.new()
	box.add_child(v)
	v.add_child(UiKit.label("DAILY CHALLENGE  ·  %s" % Game.today(), 22, UiKit.ACCENT))
	v.add_child(UiKit.label("%s — %s" % [rd.name, rd.desc], 19))
	v.add_child(UiKit.label("Opponent: %s (%s)   ·   Streak: %d   ·   Best: %d" % [dc.opp.name, Data.rank_name(int(dc.opp.rank)), Game.daily_streak(), int(Game.daily.get("best", 0))], 17, UiKit.MUTED))
	var b := UiKit.button("Take today's challenge" if Game.daily_available() else "Won today! Replay for practice", Vector2(320, 50))
	b.pressed.connect(func(): daily_requested.emit())
	v.add_child(b)
	return box

func _ach_row(got: bool, title_: String, desc: String, prog: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var box := Panel.new()
	box.custom_minimum_size = Vector2(22, 22)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_stylebox_override("panel", UiKit.box(UiKit.ACCENT if got else Color(0, 0, 0, 0.3), 5, UiKit.ACCENT if got else Color(1, 1, 1, 0.3)))
	row.add_child(box)
	var l := UiKit.label("%s — %s%s" % [title_, desc, prog], 19, UiKit.ACCENT if got else UiKit.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row

# ------------------------------------------------------------ travel menu
var _travel_panel: PanelContainer

func open_travel() -> void:
	if _travel_panel:
		_travel_panel.queue_free()
	_travel_panel = PanelContainer.new()
	_travel_panel.anchor_left = 0.1
	_travel_panel.anchor_right = 0.9
	_travel_panel.anchor_top = 0.18
	_travel_panel.anchor_bottom = 0.18
	_travel_panel.grow_vertical = Control.GROW_DIRECTION_END
	root.add_child(_travel_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_travel_panel.add_child(v)
	v.add_child(UiKit.label("BUS  ·  Where to?", 30, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	for z in Data.ZONES:
		var zd: Dictionary = Data.ZONES[z]
		var locked := Game.rank < int(zd.rank)
		var here: bool = z == Game.zone
		var txt := "%s  ·  %s" % [zd.name, Data.zone_levels(z)]
		if here:
			txt += "   (you are here)"
		elif locked:
			txt += "   (needs %s)" % Data.rank_name(int(zd.rank))
		var b := UiKit.button(txt, Vector2(0, 58))
		b.disabled = locked or here
		b.pressed.connect(func():
			_close_travel()
			travel_chosen.emit(z))
		v.add_child(b)
	var c := UiKit.button("Stay here", Vector2(200, 50))
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.pressed.connect(func():
		_close_travel()
		travel_chosen.emit(""))
	v.add_child(c)
	prompt.visible = false
	touch.release_all()
	touch.visible = false

func _close_travel() -> void:
	if _travel_panel:
		_travel_panel.queue_free()
		_travel_panel = null
	prompt.visible = true
	touch.visible = _touch_allowed()

func travel_open() -> bool:
	return _travel_panel != null

# ------------------------------------------------------------ title
func _build_title() -> void:
	title = Control.new()
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(title)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(shade)
	var v := VBoxContainer.new()
	v.anchor_left = 0.08
	v.anchor_right = 0.92
	v.anchor_top = 0.06
	v.anchor_bottom = 0.97
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.add_theme_constant_override("separation", 8)
	title.add_child(v)
	v.add_child(UiKit.label("TATAME", 84, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label("OPEN MAT BRASIL", 34, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label("An open-world jiu-jitsu adventure  ·  Zone 1: Cáceres, Mato Grosso", 20, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	v.add_child(spacer)
	v.add_child(CharSelect.new())
	var how := UiKit.label(
		"Explore with WASD / joystick · drag to look · wheel to zoom · Space to jump · E to roll\n" +
		"Fights: 1-8 techniques · Q / E / R counters · F breathe · WASD circle · mash Space to finish or escape",
		16, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(how)
	if Data.COMMUNITY_URL != "":
		var cb := UiKit.button(Data.COMMUNITY_LABEL, Vector2(280, 52))
		cb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cb.pressed.connect(func(): UiKit.open_url(Data.COMMUNITY_URL))
		v.add_child(cb)

func hide_title() -> void:
	title.visible = false
	for p in status_panels:
		p.visible = true
	touch.visible = _touch_allowed()

func set_exploring(on: bool) -> void:
	root.visible = on

# ------------------------------------------------------------ settings (Esc)
signal quit_to_title
var settings_panel: PanelContainer

func _unhandled_input(event: InputEvent) -> void:
	if settings_open() and event.is_action_pressed("pause"):
		toggle_settings()
		get_viewport().set_input_as_handled()

func settings_open() -> bool:
	return settings_panel != null and settings_panel.visible

func toggle_settings() -> void:
	if settings_open():
		settings_panel.queue_free()
		settings_panel = null
		get_tree().paused = false
		touch.visible = _touch_allowed()
		journal_toggled.emit(false)
		return
	_build_settings()
	get_tree().paused = true
	touch.release_all()
	touch.visible = false
	journal_toggled.emit(true)

func _slider_row(parent: Control, text: String, value: float, min_v: float, max_v: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var l := UiKit.label(text, 19)
	l.custom_minimum_size = Vector2(190, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = 0.05
	sl.value = value
	sl.custom_minimum_size = Vector2(260, 28)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_NONE
	var val := UiKit.label("%d%%" % int(value * 100), 17, UiKit.MUTED)
	val.custom_minimum_size = Vector2(60, 0)
	sl.value_changed.connect(func(v):
		val.text = "%d%%" % int(v * 100)
		on_change.call(v))
	row.add_child(sl)
	row.add_child(val)

func _build_settings() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	settings_panel.anchor_left = 0.5
	settings_panel.anchor_right = 0.5
	settings_panel.anchor_top = 0.5
	settings_panel.anchor_bottom = 0.5
	settings_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	settings_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	settings_panel.custom_minimum_size = Vector2(780, 0)
	root.add_child(settings_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	settings_panel.add_child(v)
	v.add_child(UiKit.label("PAUSED  ·  SETTINGS", 34, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label("Sound", 22, UiKit.ACCENT))
	var mute := CheckButton.new()
	mute.text = "Mute all sound"
	mute.button_pressed = Sfx.muted
	mute.focus_mode = Control.FOCUS_NONE
	mute.toggled.connect(func(on): Sfx.set_muted(on))
	v.add_child(mute)
	_slider_row(v, "Music", float(Sfx.pref("music", 0.8)), 0.0, 1.0, func(x): Sfx.set_pref("music", x))
	_slider_row(v, "Ambience", float(Sfx.pref("ambience", 0.8)), 0.0, 1.0, func(x): Sfx.set_pref("ambience", x))
	_slider_row(v, "Effects", float(Sfx.pref("sfx", 0.9)), 0.0, 1.0, func(x):
		Sfx.set_pref("sfx", x)
		Sfx.play("click", -6.0))
	v.add_child(UiKit.label("Controls", 22, UiKit.ACCENT))
	_slider_row(v, "Mouse sensitivity", float(Sfx.pref("mouse", 1.0)), 0.3, 2.5, func(x): Sfx.set_pref("mouse", x))
	_slider_row(v, "Fight speed", float(Sfx.pref("fight_speed", 0.7)), 0.4, 1.0, func(x): Sfx.set_pref("fight_speed", x))
	var inv := CheckButton.new()
	inv.text = "Invert camera up/down"
	inv.button_pressed = bool(Sfx.pref("invert_y", false))
	inv.focus_mode = Control.FOCUS_NONE
	inv.toggled.connect(func(on): Sfx.set_pref("invert_y", on))
	v.add_child(inv)
	v.add_child(UiKit.label("Graphics", 22, UiKit.ACCENT))
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 10)
	v.add_child(gr)
	var btns: Array = []
	for i in 3:
		var b := UiKit.button(["Low (phones)", "High", "Ultra (desktop)"][i], Vector2(180, 48))
		b.toggle_mode = true
		b.button_pressed = Game.graphics_level() == i
		btns.append(b)
		gr.add_child(b)
	for i in 3:
		var bi: int = i
		(btns[i] as Button).pressed.connect(func():
			Game.set_graphics_level(bi)
			for j in 3:
				(btns[j] as Button).set_pressed_no_signal(j == bi)
			if gfx_btn:
				gfx_btn.text = "Gfx: " + Game.GFX_NAMES[bi]
			graphics_changed.emit())
	v.add_child(UiKit.label("Keys", 22, UiKit.ACCENT))
	var keys := "WASD / arrows: move   ·   Shift: run   ·   Space: jump   ·   X: auto-run\n" + \
		"Left drag: look   ·   Right drag: turn   ·   Both buttons: run forward   ·   Wheel: zoom\n" + \
		"E or click: talk / roll   ·   C: character   ·   N: specs, talents & spellbook   ·   L / J: quest log   ·   B: bags   ·   M: map   ·   Esc: this menu\n" + \
		"In a roll: 1-8 techniques   ·   Q / E / R: Base / Frame / Defend   ·   F: breathe   ·   WASD: circle & step   ·   mash Space: squeeze / escape"
	v.add_child(UiKit.label(keys, 16, UiKit.MUTED))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var resume := UiKit.button("Resume", Vector2(200, 56))
	resume.pressed.connect(toggle_settings)
	row.add_child(resume)
	var quit := UiKit.button("Title screen", Vector2(200, 56))
	quit.pressed.connect(func():
		get_tree().paused = false
		Game.save_game()
		get_tree().reload_current_scene())
	row.add_child(quit)
	settings_panel.theme = Wow.theme()
	settings_panel.add_theme_stylebox_override("panel", Wow.sb(Wow.BG, Wow.FRAME, 6, 18, 3))
	Wow.reskin(settings_panel, 0.8)

# ------------------------------------------------------------ bags & vendors
var wallet: BagUi.Wallet
var bag_panel: BagUi.BagPanel
var shop_panel: BagUi.ShopPanel

func toggle_bag() -> void:
	if shop_open():
		return
	bag_panel.shop_mode = false
	bag_panel.visible = not bag_panel.visible
	if bag_panel.visible:
		bag_panel.move_to_front()

func shop_open() -> bool:
	return shop_panel != null and is_instance_valid(shop_panel)

func open_shop(vendor_name: String) -> void:
	if shop_open():
		return
	shop_panel = BagUi.ShopPanel.new()
	root.add_child(shop_panel)
	shop_panel.build(vendor_name)
	shop_panel.closed.connect(close_shop)
	bag_panel.shop_mode = true
	bag_panel.visible = true
	bag_panel.refresh()
	bag_panel.move_to_front()

func close_shop() -> void:
	if shop_open():
		shop_panel.queue_free()
	shop_panel = null
	bag_panel.shop_mode = false
	bag_panel.visible = false
	shop_closed.emit()

# ------------------------------------------------------------ specs tab
func _fill_specs() -> void:
	var sc := ScrollContainer.new()
	sc.name = "Specs"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.set_meta("wow", true)
	journal_tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	if Game.style == "":
		return
	var cur := Specs.get_spec(Game.spec)
	var sub := ""
	if not Game.can_choose_spec():
		sub = "Specializations unlock at level %d (you're level %d)." % [Specs.UNLOCK_LEVEL, Game.player_level()]
	elif cur.is_empty():
		sub = "Choose your path. Your first choice is free; switching later costs R$ %d." % Specs.RESPEC_COST
	else:
		sub = "Switching specialization costs R$ %d  ·  you have R$ %d" % [Specs.RESPEC_COST, Game.money]
	v.add_child(Wow.label(sub, 14, Wow.PALE, false, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	for sp in Specs.list(Game.style):
		row.add_child(_spec_card(sp))

## WoW spec column: big emblem, name, role, description, passive, its technique, Activate.
func _spec_card(sp: Dictionary) -> Control:
	var role: Dictionary = Team.ROLES[sp.role]
	var rc: Color = role.color
	var mine: bool = Game.spec == sp.id
	var p := PanelContainer.new()
	var st := Wow.sb(Color(0.03, 0.03, 0.045, 0.96), Wow.GOLD if mine else Color(Wow.FRAME, 0.8), 4, 14, 2 if mine else 1)
	if mine:
		st.shadow_color = Color(Wow.GOLD, 0.25)
		st.shadow_size = 8
	p.add_theme_stylebox_override("panel", st)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	var em := Wow.Emblem.new()
	em.glyph = str(role.icon)
	em.col = rc
	em.custom_minimum_size = Vector2(0, 66)
	var emc := CenterContainer.new()
	emc.add_child(em)
	col.add_child(emc)
	col.add_child(Wow.title(str(sp.name), 19, Wow.WHITE))
	(col.get_child(col.get_child_count() - 1) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(Wow.label("%s%s" % [role.name, "  ·  ACTIVE" if mine else ""], 13, rc.lightened(0.25), false, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(Wow.label(str(sp.desc), 13, Wow.PALE, true, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(Wow.banner("Passive"))
	col.add_child(Wow.label(str(sp.passive), 13, Wow.GREEN, true))
	col.add_child(Wow.banner("Technique"))
	var e := SpellEntry.new()
	e.move_id = str(sp.move)
	e.add_theme_constant_override("separation", 8)
	var ic := SpellIcon.new()
	ic.col = CombatUi.KIND_COLORS[RollSim.counter_kind(str(sp.move))]
	ic.glyph = CombatUi.slot_icon(str(sp.move), "move")
	ic.glow = true
	e.add_child(ic)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(Wow.label(str(Data.MOVES[sp.move].name), 15, Wow.WHITE))
	tv.add_child(Wow.label("%s  ·  hover for details" % MoveInfo.TYPE_NAMES.get(str(Data.MOVES[sp.move].type), ""), 12, Wow.GREY))
	e.add_child(tv)
	col.add_child(e)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)
	var b := Wow.button("", Vector2(0, 30))
	if mine:
		b.text = "Active"
		b.disabled = true
	elif not Game.can_choose_spec():
		b.text = "Unlocks at level %d" % Specs.UNLOCK_LEVEL
		b.disabled = true
	else:
		var cost := Game.spec_cost(sp.id)
		b.text = "Activate" if cost == 0 else "Activate  (R$ %d)" % cost
		var sid: String = sp.id
		b.pressed.connect(func():
			var why := Game.choose_spec(sid)
			if why != "":
				show_toast(why, UiKit.RED)
			_want_tab = journal_tabs.current_tab
			_fill_journal())
	col.add_child(b)
	return p

func _wowify(n: Node) -> void:
	if n == null or n.has_meta("wow"):
		return
	n.set_meta("wow", true)
	for c in n.find_children("*", "", true, false):
		if c is Label:
			var l := c as Label
			if l.has_theme_font_override("font") and (l.get_theme_font("font") == Wow.body() or l.get_theme_font("font") == Wow.title_font()):
				continue
			var fs := l.get_theme_font_size("font_size")
			var head := l.has_theme_font_override("font") and l.get_theme_font("font") == UiKit.head_font()
			l.add_theme_font_size_override("font_size", maxi(11, roundi(fs * (0.62 if head else 0.74))))
			if head and Wow.title_font():
				l.add_theme_font_override("font", Wow.title_font())
			elif Wow.body():
				l.add_theme_font_override("font", Wow.body())
			l.add_theme_constant_override("outline_size", 3)
		elif c is Button and not (c as Button).has_theme_stylebox_override("normal"):
			var b := c as Button
			b.add_theme_font_size_override("font_size", maxi(12, roundi(b.get_theme_font_size("font_size") * 0.7)))
			if Wow.body():
				b.add_theme_font_override("font", Wow.body())
			for k in ["normal", "hover", "pressed", "disabled"]:
				b.add_theme_stylebox_override(k, Wow.theme().get_stylebox(k, "Button"))
			b.add_theme_color_override("font_color", Wow.GOLD)
			if b.custom_minimum_size.y > 30:
				b.custom_minimum_size = Vector2(b.custom_minimum_size.x * 0.75, 30)

# ------------------------------------------------------------ spellbook
## WoW-style spellbook: a parchment page of technique "spells" (icon + name + where it's used),
## grouped by position. Hover any one for its full tooltip. Locked ones are greyed with the belt
## that unlocks them.
func _fill_spellbook() -> void:
	var sc := ScrollContainer.new()
	sc.name = "Spellbook"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	journal_tabs.add_child(sc)
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", Wow.parchment())
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(page)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	page.add_child(v)
	var head := Wow.title(Rpg.STYLES[Game.style].name if Rpg.STYLES.has(Game.style) else "Techniques", 26, Wow.INK)
	head.add_theme_constant_override("outline_size", 0)
	v.add_child(head)
	var known_n := 0
	for id in Data.MOVES:
		if Game.knows(id):
			known_n += 1
	var sub := Wow.label("%d techniques known  ·  hover for details  ·  your class signature and spec techniques glow" % known_n, 13, Color(0.35, 0.24, 0.12))
	sub.add_theme_constant_override("outline_size", 0)
	v.add_child(sub)
	var tip_layer := Control.new()
	tip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pos in Data.POSITION_NAMES:
		var ids: Array = []
		for id in Data.MOVES:
			var m: Dictionary = Data.MOVES[id]
			if m.pos != pos:
				continue
			if m.has("spec") and Specs.style_of(str(m.spec)) != Game.style:
				continue
			ids.append(id)
		ids.sort_custom(func(a, b):
			var ka := (0 if Game.knows(a) else 1) * 100 + int(Data.MOVES[a].rank)
			var kb := (0 if Game.knows(b) else 1) * 100 + int(Data.MOVES[b].rank)
			return ka < kb)
		var ph := Wow.title(str(Data.POSITION_NAMES[pos]), 17, Color(0.45, 0.2, 0.05))
		ph.add_theme_constant_override("outline_size", 0)
		v.add_child(ph)
		var line := ColorRect.new()
		line.color = Color(0.45, 0.32, 0.16, 0.5)
		line.custom_minimum_size = Vector2(0, 1)
		v.add_child(line)
		var g := GridContainer.new()
		g.columns = 3
		g.add_theme_constant_override("h_separation", 18)
		g.add_theme_constant_override("v_separation", 8)
		v.add_child(g)
		for id in ids:
			g.add_child(_spell_entry(str(id)))

class SpellEntry extends HBoxContainer:
	var move_id := ""
	var _tip: Control
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func():
			_tip = MoveInfo.panel(move_id, null, clampf(float(Sfx.pref("fight_speed", 0.7)), 0.4, 1.0))
			_tip.top_level = true
			_tip.z_index = 100
			add_child(_tip)
			_tip.reset_size()
			var gp := global_position + Vector2(size.x + 6, -4)
			var vs := get_viewport_rect().size
			if gp.x + _tip.size.x > vs.x:
				gp.x = global_position.x - _tip.size.x - 6
			gp.y = clampf(gp.y, 4, vs.y - _tip.size.y - 4)
			_tip.global_position = gp)
		mouse_exited.connect(func():
			if _tip and is_instance_valid(_tip):
				_tip.queue_free()
			_tip = null)

class SpellIcon extends Control:
	var col := Color.WHITE
	var glyph := "star"
	var known := true
	var glow := false
	func _init() -> void:
		custom_minimum_size = Vector2(44, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		var bg := StyleBoxFlat.new()
		bg.bg_color = col.darkened(0.55) if known else Color(0.3, 0.27, 0.22)
		bg.border_color = Color(1, 0.85, 0.35) if glow else Color(0.35, 0.25, 0.12)
		bg.set_border_width_all(3 if glow else 2)
		bg.set_corner_radius_all(6)
		draw_style_box(bg, r)
		CharSheet.draw_glyph(self, glyph, size / 2.0, 24, col.lightened(0.35) if known else Color(0.55, 0.52, 0.45))

func _spell_entry(id: String) -> Control:
	var m: Dictionary = Data.MOVES[id]
	var known := Game.knows(id)
	var h := SpellEntry.new()
	h.move_id = id
	h.add_theme_constant_override("separation", 8)
	h.custom_minimum_size = Vector2(320, 46)
	var ic := SpellIcon.new()
	ic.col = CombatUi.KIND_COLORS[RollSim.counter_kind(id)]
	ic.glyph = CombatUi.slot_icon(id, "move")
	ic.known = known
	var sig: bool = Rpg.STYLES.has(Game.style) and id in Rpg.STYLES[Game.style].signature
	ic.glow = known and (sig or m.has("spec"))
	h.add_child(ic)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv)
	var nm := Wow.label(str(m.name), 16, Wow.INK if known else Color(0.45, 0.4, 0.33))
	nm.add_theme_constant_override("outline_size", 0)
	tv.add_child(nm)
	var subt: String = str(MoveInfo.TYPE_NAMES.get(str(m.type), str(m.type)))
	if not known:
		subt = ("%s spec" % Specs.get_spec(str(m.spec)).name) if m.has("spec") else "Unlocks at %s" % Data.rank_name(int(m.rank))
	elif m.role != "any":
		subt += "  ·  " + ("top" if m.role == "top" else "bottom")
	var sl := Wow.label(subt, 12, Color(0.4, 0.3, 0.18))
	sl.add_theme_constant_override("outline_size", 0)
	tv.add_child(sl)
	return h
