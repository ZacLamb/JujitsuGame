class_name Hud
extends CanvasLayer
## Exploration HUD: rank, XP, objective, prompts, toasts, dialogue, journal and title screen.

signal barber_requested
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
	_rebind_input(event)
	if _rebinding == "" and event.is_action_pressed("fullscreen") and not event.is_echo():
		toggle_fullscreen()
	if event is InputEventScreenTouch and not touch_mode:
		touch_mode = true
		touch.visible = _touch_allowed()
		apply_layout()

func _touch_allowed() -> bool:
	return (touch_mode or DisplayServer.is_touchscreen_available()) and not title.visible and not dialogue.visible and not journal.visible

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the settings menu works while the game is paused
	root = Control.new()
	root.theme = UiKit.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.resized.connect(func(): apply_layout.call_deferred())
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
	uf.position = Vector2(10, 8)
	uf.size = Vector2(340, 96)
	uf.scale = Vector2(0.8, 0.8)   # compact, like WoW's player frame
	uf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(uf)
	status_panels.append(uf)
	var plate := Panel.new()
	plate.position = Vector2(40, 8)
	plate.size = Vector2(296, 70)
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
	# one frame, WoW-style: name + belt on top, then Composure / Gas / Grip (drawn by CombatHud)
	rank_label = Wow.title("", 15, Wow.GOLD)
	rank_label.position = Vector2(82, 10)
	rank_label.size = Vector2(150, 20)
	uf.add_child(rank_label)
	chip_holder = Control.new()
	chip_holder.position = Vector2(236, 15)
	chip_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	uf.add_child(chip_holder)
	# XP: a thin full-width bar just above the action bar, like WoW
	var xpw := 716.0
	xp_bar = UiKit.bar(XP_COLOR, Vector2(xpw, 8))
	xp_bar.anchor_left = 0.5
	xp_bar.anchor_right = 0.5
	xp_bar.anchor_top = 1.0
	xp_bar.anchor_bottom = 1.0
	xp_bar.offset_left = -xpw / 2.0
	xp_bar.offset_right = xpw / 2.0
	xp_bar.offset_top = -69
	xp_bar.offset_bottom = -61
	xp_bar.add_theme_stylebox_override("background", Wow.sb(Color(0.06, 0.03, 0.1, 0.9), Color(0, 0, 0, 0.9), 1, 0))
	xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(xp_bar)
	status_panels.append(xp_bar)
	_xp_text = Wow.label("", 11, Wow.WHITE, false, HORIZONTAL_ALIGNMENT_CENTER)
	_xp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_xp_text.offset_top = -4
	_xp_text.offset_bottom = 4
	_xp_text.add_theme_constant_override("outline_size", 3)
	xp_bar.add_child(_xp_text)
	# unspent points: a small gold notice above the XP bar (the level badge glows too)
	lvl_label = Wow.label("", 13, Wow.GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
	lvl_label.anchor_left = 0.5
	lvl_label.anchor_right = 0.5
	lvl_label.anchor_top = 1.0
	lvl_label.anchor_bottom = 1.0
	lvl_label.offset_left = -300
	lvl_label.offset_right = 300
	lvl_label.offset_top = -90
	lvl_label.offset_bottom = -72
	root.add_child(lvl_label)
	status_panels.append(lvl_label)
	# --- objective tracker (right side, under the round minimap)
	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -330
	right.offset_right = -14
	right.offset_top = 214
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
	var micro := HFlowContainer.new()
	_micro = micro
	micro.alignment = FlowContainer.ALIGNMENT_END
	micro.add_theme_constant_override("v_separation", 2)
	micro.anchor_left = 1.0
	micro.anchor_right = 1.0
	micro.anchor_top = 1.0
	micro.anchor_bottom = 1.0
	micro.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	micro.grow_vertical = Control.GROW_DIRECTION_BEGIN
	micro.offset_right = -14
	micro.offset_bottom = -14
	micro.add_theme_constant_override("h_separation", 2)
	root.add_child(micro)
	status_panels.append(micro)
	for e in [["shield", "Character (C)", func(): open_window("character")], ["star", "Specs, Talents & Moves (N)", func(): open_window("talents")],
			["lock", "Bags (B)", toggle_bag], ["link", "Quest Log (L)", func(): open_window("journal")],
			["triangle", "Group Finder: dungeons (K)", func(): toggle_finder(get_parent())],
			["bolt", "Ranked Arena (H)", func(): toggle_arena()], ["flag", "Academy (O)", func(): toggle_academy()],
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
		custom_minimum_size = Vector2(29, 36)
		focus_mode = Control.FOCUS_NONE
		var n := Wow.button_box(Color(0.12, 0.08, 0.07), Wow.FRAME)
		var h := Wow.button_box(Color(0.22, 0.15, 0.1), Wow.FRAME_HI)
		add_theme_stylebox_override("normal", n)
		add_theme_stylebox_override("hover", h)
		add_theme_stylebox_override("pressed", h)
	func _draw() -> void:
		CharSheet.draw_glyph(self, glyph, size / 2.0, 17, Wow.GOLD)

const STYLE_GLYPH := {"guard": "loop", "wrestler": "down", "judoka": "link", "athlete": "bolt", "passer": "chevron"}

var _micro: HFlowContainer
var _win_bottom := 0.0   # windows stop above the bar/XP/micro menu (set by apply_layout)

## Places every HUD block for the current screen so none of them overlap: desktop (mouse) and touch,
## landscape and portrait. Called on resize, on rotation and when touch is first used.
func apply_layout() -> void:
	if root == null or combat_hud == null or combat_hud.bar == null:
		return
	var vs := root.size
	if vs.x <= 0.0:
		return
	var portrait := vs.y > vs.x
	var is_touch := touch_mode or DisplayServer.is_touchscreen_available()
	# action bar: one row if it fits, else wraps (10 moves, then the counters)
	var rows := 1 if vs.x - 20.0 >= CombatHud.BAR_W + 1.0 else 2
	var bw := CombatHud.BAR_W + 1.0 if rows == 1 else CombatHud.BAR_W2 + 1.0
	var bar_h := rows * 44.0 + (rows - 1) * 3.0
	var bar: HFlowContainer = combat_hud.bar
	bar.offset_left = -bw / 2.0
	bar.offset_right = bw / 2.0
	bar.offset_bottom = -14
	bar.offset_top = -14 - bar_h
	var bar_top := vs.y - 14.0 - bar_h
	var bar_l := (vs.x - bw) / 2.0
	var bar_r := (vs.x + bw) / 2.0
	# XP bar and the points notice just above it
	var xw := minf(716.0, bw)
	xp_bar.offset_left = -xw / 2.0
	xp_bar.offset_right = xw / 2.0
	xp_bar.offset_bottom = -(vs.y - bar_top) - 3.0
	xp_bar.offset_top = xp_bar.offset_bottom - 8.0
	lvl_label.offset_bottom = xp_bar.offset_top - 3.0
	lvl_label.offset_top = lvl_label.offset_bottom - 18.0
	lvl_label.offset_left = -minf(300.0, vs.x * 0.5 - 10.0)
	lvl_label.offset_right = -lvl_label.offset_left
	var hud_top := vs.y + lvl_label.offset_top    # everything along the bottom sits below this line
	_win_bottom = hud_top - 4.0
	# micro menu + wallet: bottom-right beside the bar when there's room (desktop), otherwise up top
	var nb := _micro.get_child_count()
	var mw := nb * 29.0 + (nb - 1) * 2.0
	if not is_touch and vs.x - bar_r - 14.0 >= mw + 8.0:
		_micro.custom_minimum_size = Vector2(mw, 0)
		_set_corner(_micro, 1.0, 1.0, -14.0 - mw, -50.0, -14.0, -14.0)
		_set_corner(wallet, 1.0, 1.0, -14.0 - 260.0, -96.0, -16.0, -56.0)
	elif not is_touch:
		# narrow desktop window: stack them above the bar's right end
		_micro.custom_minimum_size = Vector2(mw, 0)
		var b := -(vs.y - hud_top) - 4.0
		_set_corner(_micro, 1.0, 1.0, -14.0 - mw, b - 36.0, -14.0, b)
		_win_bottom = vs.y + b - 84.0
		_set_corner(wallet, 1.0, 1.0, -14.0 - 260.0, b - 80.0, -16.0, b - 40.0)
	else:
		# touch: top centre (landscape) or top-right in two rows (portrait), clear of the thumbs
		var cols := nb if not portrait else ceili(nb / 2.0)
		var w2 := cols * 29.0 + (cols - 1) * 2.0
		_micro.custom_minimum_size = Vector2(w2, 0)
		if portrait:
			_set_anchor_box(_micro, Vector2(1, 0), Rect2(-14.0 - w2, 8.0, w2, 74.0))
			_set_anchor_box(wallet, Vector2(1, 0), Rect2(-14.0 - 200.0, 86.0, 200.0, 36.0))
		else:
			var mx := vs.x * 0.5 + 40.0
			_set_anchor_box(_micro, Vector2(0, 0), Rect2(mx, 8.0, w2, 36.0))
			_set_anchor_box(wallet, Vector2(0, 0), Rect2(mx, 48.0, w2, 36.0))
	# chat
	var cw := 262.0
	if is_touch and portrait:
		combat_log.anchor_left = 1.0
		combat_log.anchor_right = 1.0
		combat_log.anchor_top = 0.0
		combat_log.anchor_bottom = 0.0
		combat_log.offset_left = -14.0 - minf(cw, vs.x * 0.45)
		combat_log.offset_right = -14.0
		combat_log.offset_top = 130.0
		combat_log.offset_bottom = 260.0
	elif is_touch:
		# left side, under the party frames and above the joystick
		combat_log.anchor_left = 0.0
		combat_log.anchor_right = 0.0
		combat_log.anchor_top = 0.0
		combat_log.anchor_bottom = 0.0
		combat_log.offset_left = 10.0
		combat_log.offset_right = 10.0 + cw
		combat_log.offset_top = 300.0
		combat_log.offset_bottom = maxf(360.0, vs.y - 270.0)
	else:
		combat_log.anchor_left = 0.0
		combat_log.anchor_right = 0.0
		combat_log.anchor_top = 1.0
		combat_log.anchor_bottom = 1.0
		var room := bar_l - 20.0
		if room >= 220.0:
			combat_log.offset_left = 10.0
			combat_log.offset_right = 10.0 + minf(cw, room)
			combat_log.offset_bottom = -14.0
			combat_log.offset_top = -214.0
		else:
			combat_log.offset_left = 10.0
			combat_log.offset_right = 10.0 + cw
			combat_log.offset_bottom = -(vs.y - hud_top) - 4.0
			combat_log.offset_top = combat_log.offset_bottom - 180.0
	# objectives: right column (landscape) or left column under the frame (portrait)
	if portrait:
		_obj_panel.anchor_left = 0.0
		_obj_panel.anchor_right = 0.0
		_obj_panel.offset_left = 14
		_obj_panel.offset_right = 14 + (vs.x * 0.5 - 24.0 if is_touch else vs.x - 28.0)
		_obj_panel.offset_top = 96 if is_touch else 130
		objective.custom_minimum_size = Vector2(0, 0)
	else:
		_obj_panel.anchor_left = 1.0
		_obj_panel.anchor_right = 1.0
		_obj_panel.offset_left = -330
		_obj_panel.offset_right = -14
		_obj_panel.offset_top = 214
		objective.custom_minimum_size = Vector2(300, 0)
	# touch buttons and the joystick sit above the bar
	if is_touch and touch:
		touch.lift = (vs.y - hud_top) - 60.0 if portrait else 0.0
	if bag_panel:
		bag_panel.offset_bottom = -(vs.y - hud_top) - 6.0 if (is_touch or vs.x - bar_r < 480.0) else -60.0

static func _set_corner(c: Control, ax: float, ay: float, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b
	c.grow_vertical = Control.GROW_DIRECTION_END if ay == 0.0 else Control.GROW_DIRECTION_BEGIN

static func _set_anchor_box(c: Control, anchor: Vector2, r: Rect2) -> void:
	_set_corner(c, anchor.x, anchor.y, r.position.x, r.position.y, r.end.x, r.end.y)

func set_portrait(p: bool) -> void:
	if _obj_panel == null:
		return
	toasts.offset_top = 276 if p else 110
	toasts.offset_left = -250 if p else -300
	toasts.offset_right = -toasts.offset_left
	apply_layout.call_deferred()

func refresh() -> void:
	rank_label.text = Game.player_name
	for c in chip_holder.get_children():
		c.queue_free()
	var chip := UiKit.belt_chip(Game.rank, Vector2(92, 10))
	chip.tooltip_text = Data.rank_name(Game.rank)
	chip_holder.add_child(chip)
	var capped := Game.level_capped()
	xp_bar.value = 100.0 * Game.level_progress()
	xp_bar.add_theme_stylebox_override("fill", Wow.sb(XP_CAP_COLOR if capped else XP_COLOR, Color(0, 0, 0, 0), 2, 0))
	var lv := Game.player_level()
	_portrait.glyph = STYLE_GLYPH.get(Game.style, "shield")
	_portrait.key = ("spec_" + Game.spec) if Game.spec != "" else ("class_" + Game.style)
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
		_xp_text.text = Tx.f("Level %d  ·  %d / %d XP", [lv, Game.xp_into_level(), Game.xp_level_need()])
	var parts: Array = []
	if Game.attr_points() > 0:
		parts.append(Tx.f("%d attribute point%s [C]", [Game.attr_points(), "" if Game.attr_points() == 1 else "s"]))
	if Game.talent_points() > 0:
		parts.append(Tx.f("%d talent point%s [N]", [Game.talent_points(), "" if Game.talent_points() == 1 else "s"]))
	lvl_label.text = (Tx.s("✦ Spend ") + "  ·  ".join(parts)) if not parts.is_empty() else ""
	# objective tracker
	objective.text = Game.current_objective()
	for c in _tracker.get_children():
		c.queue_free()
	# main story always on top (orange), like WoW's campaign tracker
	var sn := Game.story_next()
	if not (sn[0] as Dictionary).is_empty():
		_tracker.add_child(Wow.label(str(sn[0].name), 14, Color(1.0, 0.6, 0.2)))
		_tracker.add_child(Wow.label("  - " + str(sn[1]), 13, Wow.WHITE, true))
	for id in Game.active_quests(Game.zone).slice(0, 4):
		var q: Dictionary = Data.QUESTS[id]
		if q.get("story", false):
			continue
		_tracker.add_child(Wow.label(str(q.title), 14, Wow.GOLD))
		if Game.quest_ready(id):
			_tracker.add_child(Wow.label(Tx.f("  - Return to %s", Data.QUEST_GIVERS[q.giver].name), 13, Wow.GREEN))
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
	prompt.text = "[%s]  %s%s" % [Keys.label("interact"), spot.label, extra]
	touch.interact_btn.visible = true
	touch.interact_btn.text = "TALK" if spot.action == "quest" else "GO"

func set_prompt(npc: Npc) -> void:
	if npc == null:
		prompt.text = ""
		touch.interact_btn.visible = false
		return
	if not npc.mob.is_empty():
		prompt.text = Tx.f("[%s] / [%s]  Attack %s (Lv %d)    [%s] target", [Keys.label("interact"), Keys.label("ab_0"), npc.mob.name, Data.display_level(float(npc.mob.level)), Keys.label("target_next")])
		touch.interact_btn.visible = true
		touch.interact_btn.text = "ROLL"
		return
	var o: Dictionary = Data.OPPONENTS[npc.opp_id]
	var verb := "Talk to" if Data.OPPONENTS[npc.opp_id].get("boss", false) else "Challenge"
	prompt.text = "[%s]  %s %s" % [Keys.label("interact"), verb, o.name]
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
	combat_log = CombatLog.new()
	root.add_child(combat_log)
	status_panels.append(combat_log)

var combat_hud: CombatHud

var party: Party = null
var trade_panel: TradePanel = null
var arena_panel: ArenaPanel = null
signal arena_requested   # "Find a ranked match"

var academy_panel: AcademyPanel

func toggle_academy() -> void:
	if academy_panel and is_instance_valid(academy_panel):
		academy_panel.queue_free()
		academy_panel = null
		return
	academy_panel = AcademyPanel.new()
	root.add_child(academy_panel)

func toggle_arena() -> void:
	if arena_panel and is_instance_valid(arena_panel):
		arena_panel.queue_free()
		arena_panel = null
		return
	arena_panel = ArenaPanel.new()
	root.add_child(arena_panel)
	arena_panel.find_match.connect(func(): arena_requested.emit())

func set_party(p: Party) -> void:
	party = p

## The trade window, with your bags open beside it.
func open_trade(t: Trade) -> void:
	if trade_panel and is_instance_valid(trade_panel):
		trade_panel.queue_free()
	trade_panel = TradePanel.new(t)
	root.add_child(trade_panel)
	bag_panel.trade = t
	bag_panel.shop_mode = false
	bag_panel.visible = true
	bag_panel.refresh()
	bag_panel.move_to_front()
	t.changed.connect(func(): if bag_panel.visible: bag_panel.refresh())
	t.closed.connect(func(): bag_panel.refresh() if bag_panel.visible else null)

var _pmenu: PanelContainer = null

## A small menu of actions about another player (duel, party, trade, whisper...).
## options: [[label, Callable], ...]
func player_menu(title_: String, body: String, options: Array) -> void:
	close_player_menu()
	var p := PanelContainer.new()
	p.theme = Wow.theme()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.add_theme_stylebox_override("panel", Wow.sb(Wow.BG, Wow.FRAME, 6, 14, 2))
	root.add_child(p)
	_pmenu = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(420, 0)
	p.add_child(v)
	v.add_child(Wow.title(title_, 20, Wow.GOLD))
	var l := Wow.label(body, 14, Wow.PALE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	for o in options:
		var b := Wow.button(str(o[0]), Vector2(0, 38))
		var cb: Callable = o[1]
		b.pressed.connect(func():
			close_player_menu()
			cb.call())
		v.add_child(b)
	var x := Wow.button("Close", Vector2(0, 32))
	x.pressed.connect(close_player_menu)
	v.add_child(x)
	prompt.visible = false
	player_menu_toggled.emit(true)

signal player_menu_toggled(open: bool)

func close_player_menu() -> void:
	if _pmenu and is_instance_valid(_pmenu):
		_pmenu.queue_free()
		_pmenu = null
		prompt.visible = true
		player_menu_toggled.emit(false)

func player_menu_open() -> bool:
	return _pmenu != null and is_instance_valid(_pmenu)

func set_combat(c: WorldCombat) -> void:
	if combat_hud == null:
		combat_hud = CombatHud.new()
		root.add_child(combat_hud)
		combat_hud.visible = title == null or not title.visible   # no action bar on the title screen
		# just above the player frame (its bars sit inside the frame plate), below windows / dialogue
		root.move_child(combat_hud, status_panels[0].get_index() + 1 if not status_panels.is_empty() else 0)
		apply_layout.call_deferred()   # the bar exists now: size and place it
	combat_hud.combat = c
	if not c.roll_report.is_connected(combat_hud.show_report):
		c.roll_report.connect(combat_hud.show_report)
	if not c.ability_learned.is_connected(combat_hud.learned):
		c.ability_learned.connect(combat_hud.learned)

func flash_message(head: String, sub: String) -> void:
	if combat_hud:
		combat_hud.flash(head, sub)

## Only the big moments get a banner in the middle of the screen; everything else (XP, loot,
## quest progress, fight chatter) goes to the combat log, bottom-left.
const BANNER_PREFIX := ["LEVEL", "PROMOTED", "New stripe", "Achievement", "Quest complete", "Discovered", "Specializations unlocked"]
var combat_log: CombatLog

func _is_banner(text: String) -> bool:
	for p in BANNER_PREFIX:
		if text.begins_with(p):
			return true
	return text.contains("  ·  ") or text.contains(" is yours!")

func show_toast(text: String, color := Color.WHITE) -> void:
	if combat_log:
		combat_log.add(text, color)
	if not _is_banner(text):
		return
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.7), 12, color * Color(1, 1, 1, 0.8)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 19, color, HORIZONTAL_ALIGNMENT_CENTER)
	p.add_child(l)
	toasts.add_child(p)
	if toasts.get_child_count() > 2:
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
	show_toast(Tx.f("Achievement unlocked: %s", a.name), UiKit.ACCENT)

# ------------------------------------------------------------ dialogue
func _build_dialogue() -> void:
	dialogue = PanelContainer.new()
	dialogue.anchor_left = 0.08
	dialogue.anchor_right = 0.92
	dialogue.anchor_top = 1.0
	dialogue.anchor_bottom = 1.0
	dialogue.offset_bottom = -92   # sits above the action bar
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

# ------------------------------------------------------------ passport (main story)
func _passport_box() -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Wow.sb(Color(0.12, 0.08, 0.04, 0.85), Color(0.75, 0.55, 0.2), 6, 10, 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	v.add_child(UiKit.label("PASSAPORTE DO TATAME", 24, Color(1.0, 0.8, 0.35)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	for ch in Data.chapters_for(Game.faction()):
		var got: bool = Game.stamps.has(str(ch.stamp))
		var st := PanelContainer.new()
		st.custom_minimum_size = Vector2(150, 74)
		var c: Color = ch.color
		st.add_theme_stylebox_override("panel", Wow.sb(c.darkened(0.55) if got else Color(0.08, 0.07, 0.06, 0.9), c if got else Color(0.35, 0.3, 0.25), 37, 6, 3 if got else 1))
		var sv := VBoxContainer.new()
		sv.alignment = BoxContainer.ALIGNMENT_CENTER
		st.add_child(sv)
		var l1 := UiKit.label(str(ch.stamp) if got else "?", 16, c.lightened(0.3) if got else Color(0.45, 0.42, 0.38))
		l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(l1)
		var l2 := UiKit.label(Data.ZONES[ch.zone].name, 12, Color(0.75, 0.7, 0.6) if got else Color(0.4, 0.37, 0.33))
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(l2)
		row.add_child(st)
	var nx := Game.story_next()
	var chd: Dictionary = nx[0]
	if not chd.is_empty():
		v.add_child(UiKit.label(str(chd.name), 18, chd.color))
	var nl := UiKit.label(str(nx[1]), 17, UiKit.TEXT)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nl)
	# path
	if Game.path == "":
		v.add_child(UiKit.label(Tx.f("Path: not chosen yet (%s offers the choice at blue belt)", ("Coach Mae" if Game.faction() == "usa" else "Professora Tati")), 16, UiKit.MUTED))
	else:
		var pd: Dictionary = Data.PATHS[Game.path]
		var pl := UiKit.label(Tx.f("Path: %s  ·  +%d%% technique damage in your %s kit%s", [pd.name, int(Data.PATH_MASTERY * 100), pd.name,
			"" if Game.kit == Game.path else "  (you're in the other kit now)"]), 16, Color(0.6, 0.9, 1.0))
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(pl)
		var ph := HBoxContainer.new()
		v.add_child(ph)
		var other := "nogi" if Game.path == "gi" else "gi"
		var rb := UiKit.button(Tx.f("Retrain to %s (R$ %d)", [Data.PATHS[other].name, Data.PATH_RETRAIN_COST]), Vector2(260, 34))
		rb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		rb.add_theme_font_size_override("font_size", 14)
		rb.pressed.connect(func():
			if rb.text.begins_with("Sure?"):
				if Game.set_path(other):
					_fill_journal()
			else:
				rb.text = "Sure? Tap again")
		ph.add_child(rb)
	return pc

# ------------------------------------------------------------ group finder (dungeons)
var finder: PanelContainer = null

func close_finder() -> void:
	if finder and is_instance_valid(finder):
		finder.queue_free()
	finder = null

func toggle_finder(main_node) -> void:
	if finder and is_instance_valid(finder):
		close_finder()
		return
	finder = PanelContainer.new()
	finder.theme = Wow.theme()
	finder.anchor_left = 0.5
	finder.anchor_right = 0.5
	finder.anchor_top = 0.5
	finder.anchor_bottom = 0.5
	finder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	finder.grow_vertical = Control.GROW_DIRECTION_BOTH
	finder.add_theme_stylebox_override("panel", Wow.sb(Wow.BG, Wow.FRAME, 6, 14, 2))
	root.add_child(finder)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(640, 0)
	finder.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Wow.title("GROUP FINDER", 22, Wow.GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Wow.button("Close", Vector2(90, 32))
	x.pressed.connect(close_finder)
	head.add_child(x)
	var intro := Wow.label("Five-fighter dungeons: you plus four friends from the road who fill the roles you don't. Two pulls, then a boss. Everything scales to your level; the level range is where it's meant to be run.", 14, UiKit.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	if party and party.in_party():
		var here: Array = party.here()
		var ptxt := ""
		if party.is_leader():
			ptxt = Tx.f("Your party: %d here with you. They're asked to join when you pick a run; AI partners fill the rest.", here.size()) if not here.is_empty() else "Your party: nobody is in this zone with you. Partners have to be in your zone to join."
		else:
			ptxt = "Your party leader starts group runs. Anything you pick here, you run on your own."
		var pl := Wow.label(ptxt, 14, Color(0.55, 0.85, 1.0))
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(pl)
	else:
		var pl := Wow.label("Got friends online? /invite Name (or walk up to them and press E) to form a party and run it together.", 13, UiKit.MUTED)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(pl)
	var lv := Game.player_level()
	var mech_names := {"crush": "heavy hits", "wave": "Sprawl (Q)", "heal": "Frame (R)", "choke": "Defend (T)", "adds": "adds"}
	for id in Raid.DUNGEON_ORDER:
		var d: Dictionary = Raid.DUNGEONS[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		var mid := (int(d.levels[0]) + int(d.levels[1])) / 2
		var col := Data.con_color(mid, lv)
		var done := Game.unlocked.has("dng_" + id)
		var lab := Wow.label(Tx.f("%s%s\nLv %d-%d  ·  boss: %s  ·  %s", [str(d.title).capitalize(), "  ✓" if done else "", int(d.levels[0]), int(d.levels[1]), str(d.boss),
			", ".join((d.mechs as Array).map(func(m): return mech_names.get(m, m)))]), 15, col)
		lab.autowrap_mode = TextServer.AUTOWRAP_OFF
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		var b := Wow.button("Enter", Vector2(110, 40))
		b.disabled = lv < int(d.levels[0]) - 4
		if b.disabled:
			b.text = Tx.f("Lv %d", (int(d.levels[0]) - 4))
		b.pressed.connect(func(): main_node.start_dungeon(id))
		row.add_child(b)
	var raid_l := Wow.label("Raids (bigger, harder, tier sets): Covil da Sucuri in the Pantanal (Time Brasil) and the Gold Compound in the Everglades (Team USA). Walk up to their gates.", 13, Color(0.7, 0.55, 1.0))
	raid_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(raid_l)

# ------------------------------------------------------------ quartermaster (Honor gear)
var qm_panel: PanelContainer = null
var _qm := {}

func _qm_fill() -> void:
	var list: VBoxContainer = _qm.list
	(_qm.bal as Label).text = Tx.f("Your Honor: %s   ·   earned with every war point   ·   needs Lv %d", [_thousands(Game.honor), Gear.HONOR_MIN_LEVEL])
	for c in list.get_children():
		c.queue_free()
	for id in Gear.SETS[_qm.set].pieces:
		var it: Dictionary = Gear.ITEMS[id]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		list.add_child(h)
		var ic := CharSheet.SlotIcon.new()
		ic.kind = str(it.slot)
		ic.gear_id = id
		ic.custom_minimum_size = Vector2(48, 48)
		h.add_child(ic)
		var nm := Wow.label(Tx.f("%s\n%s", [it.name, Gear.stat_text(id)]), 14, Gear.rarity_color(id))
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		var owned := Game.inventory.has(id)
		var b := Wow.button("Owned" if owned else Tx.f("%s Honor", _thousands(int(Gear.HONOR_PRICES[id]))), Vector2(130, 40))
		b.disabled = owned
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func():
			var why := Game.buy_honor(id)
			(_qm.msg as Label).text = why if why != "" else Tx.f("Bought %s.", it.name)
			Sfx.play("click" if why == "" else "miss", -6.0)
			_qm_fill.call_deferred())
		h.add_child(b)

func open_quartermaster(who: String, fid: String) -> void:
	if qm_panel and is_instance_valid(qm_panel):
		qm_panel.queue_free()
	var fd := Origins.faction(fid)
	qm_panel = PanelContainer.new()
	qm_panel.theme = Wow.theme()
	qm_panel.anchor_top = 0.5
	qm_panel.anchor_bottom = 0.5
	qm_panel.offset_left = 24
	qm_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	qm_panel.add_theme_stylebox_override("panel", Wow.sb(Wow.BG, fd.color, 6, 12, 2))
	root.add_child(qm_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(420, 0)
	qm_panel.add_child(v)
	v.add_child(Wow.title(Tx.f("%s  ·  %s Quartermaster", [who, fd.long]), 17, (fd.color as Color).lightened(0.35)))
	var bal := Wow.label("", 15, Color(1, 0.85, 0.35))
	v.add_child(bal)
	var msg := Wow.label("", 14, UiKit.MUTED)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var set_id := "selecao" if fid == "brasil" else "old_glory"
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	v.add_child(list)
	_qm = {"list": list, "bal": bal, "msg": msg, "set": set_id}
	_qm_fill()
	var bonus: Dictionary = Gear.SETS[set_id].bonus
	var bl := Wow.label(Tx.f("Set: 2 pieces: +1 %s.  4 pieces: %s", [Rpg.ATTRS[bonus[2].attrs.keys()[0]].name, bonus[4].text]), 13, Color(0.6, 0.9, 1.0))
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(bl)
	v.add_child(msg)
	var close := Wow.button("Done", Vector2(120, 40))
	close.pressed.connect(func():
		if is_instance_valid(qm_panel):
			qm_panel.queue_free()
		qm_panel = null)
	v.add_child(close)

## Faction War: this week's score, Brasil vs USA, the top fighters on each side and your share.
func _war_box() -> Control:
	var pc := PanelContainer.new()
	var mine := Origins.faction(Game.faction())
	pc.add_theme_stylebox_override("panel", Wow.sb(Color(0.05, 0.06, 0.1, 0.88), (mine.color as Color).darkened(0.1), 6, 10, 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	var w: Dictionary = Game.war
	v.add_child(UiKit.label(Tx.f("FACTION WAR%s", (("  ·  " + str(w.week)) if w.has("week") else "")), 24, Color(1.0, 0.8, 0.35)))
	var b := int(w.get("brasil", 0))
	var u := int(w.get("usa", 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var fb: Dictionary = Origins.FACTIONS.brasil
	var fu: Dictionary = Origins.FACTIONS.usa
	var lb := UiKit.label(Tx.f("%s  %s", [fb.long, _thousands(b)]), 18, (fb.color as Color).lightened(0.3))
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(lb)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(240, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = 0.5 if b + u == 0 else float(b) / float(b + u)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fb.color
	var bg := StyleBoxFlat.new()
	bg.bg_color = fu.color
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	var lu := UiKit.label(Tx.f("%s  %s", [_thousands(u), fu.long]), 18, (fu.color as Color).lightened(0.3))
	lu.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(lu)
	var lines: Array = []
	if not w.has("week"):
		lines.append("The war report loads from the server (web version, online).")
	lines.append(Tx.f("You fight for %s. Every win adds points: rolls 5, bosses 25, street rollers 1-10, medals 5-20, territories 15, daily 10, rival shadows 15.", mine.long))
	lines.append(Tx.f("Honor: %s. Every war point is also Honor, spent on faction gear at your quartermaster (%s).", [_thousands(Game.honor), "Cáceres and Rio" if Game.faction() == "brasil" else "Dry Creek and San Diego"]))
	if Cloud.logged_in():
		lines.append(Tx.f("Your points this week: %s%s", [_thousands(Game.war_mine), ("  (%d waiting to send)" % Game.war_pending) if Game.war_pending > 0 else ""]))
	else:
		lines.append(Tx.f("Log in (title screen) so your points count for %s.", mine.long))
	var last: Dictionary = w.get("last", {})
	if str(last.get("winner", "")) != "":
		var wf: Dictionary = Origins.faction(str(last.winner))
		lines.append(Tx.f("Last week: %s won %s to %s.%s", [wf.long, _thousands(maxi(int(last.brasil), int(last.usa))), _thousands(mini(int(last.brasil), int(last.usa))),
			("  Spoils of war: +%d%% XP for you all week." % int(Game.WAR_SPOILS * 100)) if Game.war_spoils() else "  Win this week for +5% XP next week."]))
	for t in lines:
		var l := UiKit.label(str(t), 15, UiKit.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	var top: Dictionary = w.get("top", {})
	if not top.is_empty():
		var tr := HBoxContainer.new()
		tr.add_theme_constant_override("separation", 24)
		v.add_child(tr)
		for f in ["brasil", "usa"]:
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tr.add_child(col)
			col.custom_minimum_size = Vector2(240, 0)
			col.add_child(UiKit.label(Tx.f("Top %s", Origins.FACTIONS[f].name), 15, (Origins.FACTIONS[f].color as Color).lightened(0.3)))
			var arr: Array = top.get(f, [])
			if arr.is_empty():
				col.add_child(UiKit.label("nobody yet", 14, UiKit.MUTED))
			for i in arr.size():
				col.add_child(UiKit.label(Tx.f("%d. %s  %s", [i + 1, str(arr[i].name), _thousands(int(arr[i].points))]), 14, UiKit.TEXT))
	return pc

static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

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
const TAB_TEAM := 8
const WINDOWS := {
	"character": {"tabs": [0, 2], "names": ["Character", "Wardrobe"], "size": Vector2(1040, 560), "at": "left", "glyph": "shield"},
	"talents": {"tabs": [3, 1, 6], "names": ["Specialization", "Talents", "Moves"], "size": Vector2(1180, 660), "at": "center", "glyph": "star"},
	"journal": {"tabs": [4, 5, 7, 8], "names": ["Quests", "Achievements", "Fighters", "Team"], "size": Vector2(920, 600), "at": "center", "glyph": "link"},
}
var _window := "character"

static func window_of(tab: int) -> String:
	for w in WINDOWS:
		if tab in WINDOWS[w].tabs:
			return w
	return "journal"

func open_window(w: String, tab := -1) -> void:
	if journal.visible and _window == w and (tab < 0 or tab == _want_tab):
		toggle_journal()
		return
	_want_tab = int(WINDOWS[w].tabs[0]) if w != "talents" else (TAB_TALENTS if Game.talent_points() > 0 or Game.spec != "" else TAB_SPECS)
	if tab >= 0:
		_want_tab = tab
	if not journal.visible:
		toggle_journal()
	else:
		_fill_journal()

func _layout_window() -> void:
	var g: Dictionary = WINDOWS[_window]
	var vs := root.size if root.size.x > 0 else Vector2(1280, 720)
	# windows live between the player frame and the action bar (never over the bar)
	var top := 92.0 if vs.x > vs.y else 128.0
	var bottom := _win_bottom if _win_bottom > top + 200.0 else vs.y - 72.0
	var sz: Vector2 = g.size
	sz = Vector2(minf(sz.x, vs.x - 60), minf(sz.y, bottom - top))
	journal.size = sz
	var y := top + floorf((bottom - top - sz.y) * 0.5)
	journal.position = Vector2(48, top) if g.at == "left" else Vector2(floorf((vs.x - sz.x) * 0.5), y)
	var cur := journal_tabs.current_tab
	journal.set_tabs(g.names, (g.tabs as Array).find(cur))
	var st: String = Rpg.STYLES[Game.style].name if Rpg.STYLES.has(Game.style) else ""
	match _window:
		"character":
			journal.title_lbl.text = Game.player_name
		"talents":
			journal.title_lbl.text = {TAB_SPECS: "Specialization", TAB_TALENTS: "Talents", TAB_SPELLBOOK: "Moves"}.get(cur, "Talents") + ("  ·  " + st if st != "" else "")
		_:
			journal.title_lbl.text = {TAB_QUESTS: "Quest Log", TAB_ACHIEVEMENTS: "Achievements", TAB_FIGHTERS: "Fighters", TAB_TEAM: Tx.s("Team  ·  ") + Tx.s(Team.TEAM_NAMES[0])}.get(cur, "Journal")
	var sp := Specs.get_spec(Game.spec)
	journal.set_emblem(str(sp.get("role", "")) if false else str(g.glyph), Team.ROLES[sp.role].color if not sp.is_empty() else Wow.GOLD)

func open_character() -> void:
	open_window("character")

func toggle_journal() -> void:
	journal.visible = not journal.visible
	minimap.visible = not journal.visible
	# a window takes the screen: the chat and the objective tracker step aside instead of overlapping
	if combat_log and not title.visible:
		combat_log.visible = not journal.visible
	if _obj_panel:
		_obj_panel.visible = not journal.visible
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
	v.add_child(Wow.label(Tx.f("Wardrobe  ·  %d / %d collected  ·  wearing your %s kit  ·  click an item to wear it", [owned, Gear.ITEMS.size(), Gear.KIT_NAMES[Game.kit]]), 14, Wow.GOLD))
	for slot in Gear.SLOTS:
		v.add_child(Wow.banner(Gear.SLOT_NAMES[slot]))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		v.add_child(row)
		var cur := str(Game.equipped.get(slot, ""))
		for id in Gear.ITEMS:
			var it: Dictionary = Gear.ITEMS[id]
			if it.slot != slot or not Gear.class_ok(str(id), Game.style):
				continue   # other classes' kits and tier sets aren't shown (like WoW's appearance tab)
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
	ic.gear_id = id
	ic.empty = false   # every piece has art now: uncollected ones show dimmed
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
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL   # short pages (talents) get the whole window
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
	q.add_child(_passport_box())
	q.add_child(_war_box())
	q.add_child(_daily_box())
	q.add_child(UiKit.label(Tx.s("Next belt: ") + Tx.s(Game.current_objective()), 20, UiKit.ACCENT))
	var held := 0
	var hot: Array = []
	for tid in Data.TERRITORIES:
		if Game.holds(tid):
			held += 1
			if Game.territory_state(tid) == "attacked":
				hot.append(Data.TERRITORIES[tid].name)
	var tl := Tx.f("Academy wars: Gringo BJJ holds %d / %d territories.", [held, Data.TERRITORIES.size()])
	if not hot.is_empty():
		tl += Tx.f("  UNDER ATTACK: %s", ", ").join(hot)
	q.add_child(UiKit.label(tl, 18, Color(1, 0.45, 0.35) if not hot.is_empty() else Color(0.55, 0.9, 0.65)))
	var act := Game.active_quests()
	if not act.is_empty():
		q.add_child(UiKit.label("Quest log", 22, UiKit.ACCENT))
		for id in act:
			var qd: Dictionary = Data.QUESTS[id]
			var gz: String = Data.QUEST_GIVERS[qd.giver].zone
			var head := Tx.f("%s  (%s, %s)", [qd.title, Data.QUEST_GIVERS[qd.giver].name, Data.ZONES[gz].name])
			if qd.get("story", false):
				head = Tx.s("[Main Story] ") + head
			q.add_child(UiKit.label(head, 20, Color(1, 0.85, 0.3) if Game.quest_ready(id) else (Color(1.0, 0.65, 0.25) if qd.get("story", false) else UiKit.TEXT)))
			for i in qd.obj.size():
				var pr := Game.objective_progress(id, i)
				q.add_child(UiKit.label("     %s: %d/%d%s" % [qd.obj[i].text, pr[0], pr[1], "  (done)" if pr[0] >= pr[1] else ""], 17, UiKit.MUTED))
	var ndone := 0
	for id in Data.QUESTS:
		if Game.quest_state(id) == "done":
			ndone += 1
	q.add_child(UiKit.label(Tx.f("Quests completed: %d / %d", [ndone, Data.QUESTS.size()]), 18, UiKit.MUTED))
	for s in Game.side_objectives():
		q.add_child(UiKit.label("•  " + s, 20))
	q.add_child(UiKit.label(Tx.f("Next stripe: %d / %d XP%s", [Game.xp_into_stripe(), Game.stripe_cost(Game.rank), "  (stripe cap: beat %s to promote)" % Data.OPPONENTS[Data.ZONES[Game.zone].boss].name if Game.at_stripe_cap() and Data.ZONES.has(Game.zone) else ""]), 18, UiKit.MUTED))
	if Cloud.community_url != "":
		var cb := UiKit.button(Cloud.community_label, Vector2(260, 52))
		cb.pressed.connect(func(): UiKit.open_url(Cloud.community_url))
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
	journal_tabs.set_tab_title(journal_tabs.get_tab_count() - 1, Tx.f("Achievements %d/%d", [Game.unlocked.size(), Data.ACHIEVEMENTS.size()]))
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
		f.add_child(UiKit.label(Tx.f("%s — %s, Lv %d  (%s)", [o.name, o.title, Data.display_level(float(o.level)), rec]), 19, Data.con_color(Data.display_level(float(o.level)), Game.player_level())))
		var pl := Data.personality(o, id)
		if pl.plan != "" and (Game.beaten(id) or int(Game.losses.get(id, 0)) > 0 or Data.zone_of(id) == Game.zone):
			var favs: Array[String] = []
			for mv in pl.fav:
				favs.append(str(Data.MOVES[mv].name))
			f.add_child(UiKit.label(Tx.f("     %s  Favorites: %s.", [pl.plan, ", ".join(favs)]), 16, UiKit.MUTED))
	_fill_team()
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
	journal_tabs.set_tab_title(journal_tabs.get_tab_count() - 1, Tx.f("Talents (%d)", tp) if tp > 0 else "Talents")
	t.add_child(CharSheet.build_talents_wow(self))
	t.get_parent().set_meta("wow", true)

func _daily_box() -> Control:
	var dc := Game.daily_challenge()
	var rd: Dictionary = Data.DAILY_RULES[dc.rule]
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiKit.box(Color(0.25, 0.2, 0.05, 0.6), 12, UiKit.ACCENT))
	var v := VBoxContainer.new()
	box.add_child(v)
	v.add_child(UiKit.label(Tx.f("DAILY CHALLENGE  ·  %s", Game.today()), 22, UiKit.ACCENT))
	v.add_child(UiKit.label(Tx.f("%s — %s", [rd.name, rd.desc]), 19))
	v.add_child(UiKit.label(Tx.f("Opponent: %s (%s)   ·   Streak: %d   ·   Best: %d", [dc.opp.name, Data.rank_name(int(dc.opp.rank)), Game.daily_streak(), int(Game.daily.get("best", 0))]), 17, UiKit.MUTED))
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
	var l := UiKit.label(Tx.f("%s — %s%s", [title_, desc, prog]), 19, UiKit.ACCENT if got else UiKit.TEXT)
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
	v.add_child(UiKit.label("TRAVEL  ·  Where to?", 30, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var my_c := Data.continent_of(Game.zone)
	for cont in Data.CONTINENTS:
		var head := Tx.s(str(Data.CONTINENTS[cont])).to_upper() + ("   ·   bus" if cont == my_c else Tx.f("   ·   flight R$ %d", Data.FLIGHT_COST))
		v.add_child(UiKit.label(head, 20, Color(1.0, 0.8, 0.35) if cont == my_c else Color(0.55, 0.85, 1.0)))
		for z in Data.ZONES:
			if Data.continent_of(z) != cont:
				continue
			var zd: Dictionary = Data.ZONES[z]
			# open world: every zone is reachable; it just tells you if it's above your level
			var lo := int(zd.levels[0])
			var here: bool = z == Game.zone
			var txt := Tx.f("%s  ·  %s", [zd.name, Data.zone_levels(z)])
			if here:
				txt += "   (you are here)"
			elif Game.player_level() < lo - 2:
				txt += Tx.f("   (dangerous: you're level %d)", Game.player_level())
			var fly: bool = cont != my_c
			if fly and Game.money < Data.FLIGHT_COST:
				txt += Tx.f("   (need R$ %d)", Data.FLIGHT_COST)
			var b := UiKit.button(txt, Vector2(0, 50))
			b.disabled = here or (fly and Game.money < Data.FLIGHT_COST)
			if not here and Game.player_level() < lo - 2:
				b.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
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
	v.add_child(UiKit.label("An open-world jiu-jitsu adventure  ·  Time Brasil vs Team USA", 20, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	v.add_child(spacer)
	var lr := lang_row()
	lr.alignment = BoxContainer.ALIGNMENT_CENTER
	var tfs := UiKit.button("Full screen", Vector2(170, 48))
	tfs.pressed.connect(func():
		var going_full := not is_fullscreen()
		toggle_fullscreen()
		tfs.text = Tx.s("Exit full screen") if going_full else Tx.s("Full screen"))
	lr.add_child(tfs)
	v.add_child(lr)
	var cs_box := VBoxContainer.new()   # holds the character screen so it can be rebuilt
	v.add_child(cs_box)
	cs_box.add_child(CharSelect.new())
	var how := UiKit.label("", 16, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var how_text := func():
		how.text = Tx.s("Explore with WASD / joystick · drag to look · wheel to zoom · Space to jump · E to talk or fight\n") + \
			Tx.s("Fights: 1-0 your moves · Tab target · Q / R / T counter their cast · F breathe · G origin racial")
	how_text.call()
	v.add_child(how)
	# a new language: rebuild the character screen (its text is formatted when built)
	Lang.changed.connect(func():
		how_text.call()
		if is_instance_valid(cs_box) and title.visible:
			for c in cs_box.get_children():
				c.queue_free()
			cs_box.add_child(CharSelect.new()))
	# the community button: the server sets the link (COMMUNITY_URL), so it can appear late
	var cb := UiKit.button(Cloud.community_label, Vector2(280, 52))
	cb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cb.pressed.connect(func(): UiKit.open_url(Cloud.community_url))
	cb.visible = Cloud.community_url != ""
	v.add_child(cb)
	Cloud.config_loaded.connect(func():
		if is_instance_valid(cb):
			cb.text = Cloud.community_label
			cb.visible = Cloud.community_url != "")

func _process(_d: float) -> void:
	_zone_banner_tick(_d)
	# the "[E] Attack ..." prompt has no business on screen mid-fight
	if prompt and combat_hud and combat_hud.combat and combat_hud.combat.me:
		prompt.visible = not combat_hud.combat.me.in_combat
		# upright phone: the menu icons share the top-right with the opponent's frame, so they step aside mid-fight
		var vs := get_viewport().get_visible_rect().size
		var crowded: bool = touch_mode and vs.y > vs.x * 1.2 and combat_hud.combat.me.in_combat
		if _micro and _micro.visible == crowded:
			_micro.visible = not crowded
			if wallet:
				wallet.visible = not crowded and not bag_panel.visible and not (title != null and title.visible)
	# no action bar / combat frames behind the title screen
	if combat_hud:
		var host := get_parent()
		var want: bool = not (title != null and title.visible) and not (host != null and "_in_title" in host and host._in_title)
		if combat_hud.visible != want:
			combat_hud.visible = want

func hide_title() -> void:
	title.visible = false
	apply_layout.call_deferred()
	for p in status_panels:
		p.visible = true
	if combat_hud:
		combat_hud.visible = true
	touch.visible = _touch_allowed()

func set_exploring(on: bool) -> void:
	root.visible = on

# ------------------------------------------------------------ zone banner
## WoW-style zone name across the top of the screen when you arrive: green for your faction's
## land, red for the other side's.
var _zb: VBoxContainer
var _zb_t := 0.0
func zone_banner(title_: String, sub: String, friendly: bool) -> void:
	if _zb == null:
		_zb = VBoxContainer.new()
		_zb.anchor_left = 0.5
		_zb.anchor_right = 0.5
		_zb.offset_left = -500
		_zb.offset_right = 500
		_zb.offset_top = 222   # below the toasts
		_zb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_zb.add_theme_constant_override("separation", 0)
		root.add_child(_zb)
		for k in 2:
			var l := Wow.title("", 54 if k == 0 else 22, Wow.GOLD)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.add_theme_constant_override("outline_size", 10 if k == 0 else 6)
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			_zb.add_child(l)
	var t := _zb.get_child(0) as Label
	var u := _zb.get_child(1) as Label
	var portrait := root.size.y > root.size.x
	# landscape: centred, clear of the objective tracker on the right; portrait: under the minimap
	var half := root.size.x * 0.5 - 14.0 if portrait else minf(500.0, root.size.x * 0.5 - 350.0)
	_zb.offset_left = -half
	_zb.offset_right = half
	_zb.offset_top = 430.0 if portrait else 222.0
	t.add_theme_font_size_override("font_size", 38 if portrait or half < 300.0 else 54)
	u.add_theme_font_size_override("font_size", 18 if portrait or half < 300.0 else 22)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	u.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.text = Tx.s(title_).to_upper()
	u.text = sub
	t.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35) if friendly else Color(1.0, 0.42, 0.32))
	u.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	_zb_t = 5.0
	_zb.modulate.a = 0.0
	_zb.visible = true

func _zone_banner_tick(delta: float) -> void:
	if _zb == null or _zb_t <= 0.0:
		return
	_zb_t -= delta
	var a := clampf((5.0 - _zb_t) / 0.6, 0.0, 1.0) * clampf(_zb_t / 1.2, 0.0, 1.0)
	if combat_hud and combat_hud.combat and combat_hud.combat.me and combat_hud.combat.me.in_combat:
		a = 0.0   # a fight's read calls own the middle of the screen
	_zb.modulate.a = a
	if _zb_t <= 0.0:
		_zb.visible = false

# ------------------------------------------------------------ Mat Days (daily login rewards)
var mat_days_panel: PanelContainer

## The 7-day track with today's reward highlighted. info comes from Game.mat_day_claim().
func show_mat_days(info: Dictionary) -> void:
	if info.is_empty():
		return
	if mat_days_panel and is_instance_valid(mat_days_panel):
		mat_days_panel.queue_free()
	var vs := root.size if root.size.x > 0 else Vector2(1280, 720)
	var narrow := vs.x < 760.0
	var p := PanelContainer.new()
	mat_days_panel = p
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.add_theme_stylebox_override("panel", Wow.sb(Wow.BG, Wow.FRAME, 6, 16, 3))
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var t := Wow.title("MAT DAYS", 30, Wow.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var streak := int(info.streak)
	var sub := Tx.f("Day %d in a row. Log in every day: miss one and the week starts over.", streak)
	if bool(info.get("reset", false)):
		sub = Tx.s("You missed a day, so the week starts over. Show up tomorrow!")
	v.add_child(Wow.label(sub, 15, Wow.PALE, true, HORIZONTAL_ALIGNMENT_CENTER))
	var grid := GridContainer.new()
	grid.columns = 4 if narrow else 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var today := int(info.day)
	var rewards: Array = info.rewards
	for i in rewards.size():
		var done := i < today
		var now := i == today
		var cell := PanelContainer.new()
		var edge := Wow.GOLD if now else (Wow.FRAME if not done else Color(0.25, 0.6, 0.25))
		var bg := Color(0.18, 0.13, 0.04, 0.95) if now else Wow.INSET
		cell.add_theme_stylebox_override("panel", Wow.sb(bg, edge, 4, 6, 3 if now else 1))
		cell.custom_minimum_size = Vector2(112 if narrow else 118, 112)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 3)
		cell.add_child(cv)
		var head := Wow.label(Tx.f("Day %d", i + 1) + ("  ✓" if done else ""), 15, Wow.GOLD if now else (Wow.GREEN if done else Wow.GREY), false, HORIZONTAL_ALIGNMENT_CENTER)
		cv.add_child(head)
		var body := Wow.label(Game.mat_day_text(rewards[i]), 13, Wow.WHITE if (now or not done) else Wow.GREY, true, HORIZONTAL_ALIGNMENT_CENTER)
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cv.add_child(body)
		if now:
			cv.add_child(Wow.label("TODAY", 12, Wow.GOLD, false, HORIZONTAL_ALIGNMENT_CENTER))
		if i == 6:
			cell.tooltip_text = Tx.s("Day 7 is the big one, and then the week begins again.")
		grid.add_child(cell)
	var got := Tx.s("You got: ") + ", ".join(PackedStringArray(info.lines))
	v.add_child(Wow.label(got, 16, Wow.GREEN, true, HORIZONTAL_ALIGNMENT_CENTER))
	var best := int(Game.login.get("best", streak))
	v.add_child(Wow.label(Tx.f("Best streak: %d days", best), 13, Wow.GREY, false, HORIZONTAL_ALIGNMENT_CENTER))
	var ok := Wow.button("Oss!", Vector2(160, 40))
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func():
		p.queue_free()
		mat_days_panel = null)
	v.add_child(ok)
	p.custom_minimum_size.x = minf(vs.x - 32.0, 900.0)
	Sfx.play("collect")

# ------------------------------------------------------------ settings (Esc)
signal quit_to_title
signal ui_scale_changed
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

## Full screen: the browser's Fullscreen API on the web (it needs a click or key press, which
## both the button and the key are), a real full-screen window on desktop builds.
static func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

static func toggle_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_fullscreen() else DisplayServer.WINDOW_MODE_FULLSCREEN)

var _key_btns := {}
var _rebinding := ""

func _start_rebind(act: String) -> void:
	_rebinding = act
	for a in _key_btns:
		(_key_btns[a] as Button).text = Keys.label(a) if a != act else Tx.s("Press a key…")

func _redraw_bar() -> void:
	if combat_hud:
		for sl in combat_hud._slots:
			(sl as Control).queue_redraw()

func _refresh_key_btns() -> void:
	for a in _key_btns:
		if is_instance_valid(_key_btns[a]):
			(_key_btns[a] as Button).text = Keys.label(a)

func _rebind_input(event: InputEvent) -> void:
	if _rebinding == "" or not settings_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		var k: int = (event as InputEventKey).physical_keycode
		var act := _rebinding
		_rebinding = ""
		if k == KEY_ESCAPE:
			_refresh_key_btns()
			return
		if k in Keys.RESERVED:
			show_toast("That key is reserved (menu and chat).", Color(1, 0.6, 0.4))
			_refresh_key_btns()
			return
		var bumped := Keys.bind(act, k)
		_refresh_key_btns()
		if bumped != "":
			show_toast(Tx.f("%s was on %s: it's unbound now.", [OS.get_keycode_string(k), Tx.s(bumped)]), Color(1, 0.8, 0.4))
		_redraw_bar()

func _set_head(t: String) -> Label:
	var l := UiKit.label(t, 20, UiKit.ACCENT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

func _slider_row(parent: Control, text: String, value: float, min_v: float, max_v: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var l := UiKit.label(text, 16)
	l.custom_minimum_size = Vector2(150, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = 0.05
	sl.value = value
	sl.custom_minimum_size = Vector2(120, 24)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_NONE
	var val := UiKit.label("%d%%" % int(value * 100), 15, UiKit.MUTED)
	val.custom_minimum_size = Vector2(48, 0)
	sl.value_changed.connect(func(v):
		val.text = "%d%%" % int(v * 100)
		on_change.call(v))
	row.add_child(sl)
	row.add_child(val)

## Language buttons (used in settings and on the title screen). Labels are the languages'
## own names, so they never get translated.
static func lang_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var btns: Array = []
	for code in Lang.ORDER:
		var b := UiKit.button(Lang.LANGS[code], Vector2(230, 48))
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.toggle_mode = true
		b.button_pressed = Lang.current == code
		btns.append(b)
		row.add_child(b)
	for i in btns.size():
		var c: String = Lang.ORDER[i]
		(btns[i] as Button).pressed.connect(func():
			Lang.set_lang(c)
			for j in btns.size():
				(btns[j] as Button).set_pressed_no_signal(Lang.ORDER[j] == c))
	return row

func _build_settings() -> void:
	var vs := root.size if root.size.x > 0 else Vector2(1280, 720)
	settings_panel = PanelContainer.new()
	settings_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	settings_panel.anchor_left = 0.5
	settings_panel.anchor_right = 0.5
	settings_panel.anchor_top = 0.5
	settings_panel.anchor_bottom = 0.5
	settings_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	settings_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	settings_panel.custom_minimum_size = Vector2(minf(1000, vs.x - 40), 0)
	root.add_child(settings_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	settings_panel.add_child(v)
	v.add_child(UiKit.label("PAUSED  ·  SETTINGS", 30, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	# two columns, scrolling if the screen is short; the buttons stay pinned at the bottom
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, minf(500.0 if vs.x >= 760.0 else 760.0, vs.y - 230))
	v.add_child(sc)
	var cols := BoxContainer.new()
	cols.vertical = vs.x < 760.0   # one column on narrow (portrait) screens
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14 if cols.vertical else 28)
	sc.add_child(cols)
	var lc := VBoxContainer.new()
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lc.add_theme_constant_override("separation", 6)
	cols.add_child(lc)
	var rc := VBoxContainer.new()
	rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rc.add_theme_constant_override("separation", 6)
	cols.add_child(rc)
	lc.add_child(_set_head("Language"))
	var lb := lang_row()
	for c in lb.get_children():
		(c as Control).custom_minimum_size = Vector2(0, 34)
		(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(c as Button).add_theme_font_size_override("font_size", 15)
	lc.add_child(lb)
	lc.add_child(_set_head("Sound"))
	var mute := CheckButton.new()
	mute.text = "Mute all sound"
	mute.button_pressed = Sfx.muted
	mute.focus_mode = Control.FOCUS_NONE
	mute.toggled.connect(func(on): Sfx.set_muted(on))
	lc.add_child(mute)
	_slider_row(lc, "Music", float(Sfx.pref("music", 0.8)), 0.0, 1.0, func(x): Sfx.set_pref("music", x))
	_slider_row(lc, "Ambience", float(Sfx.pref("ambience", 0.8)), 0.0, 1.0, func(x): Sfx.set_pref("ambience", x))
	_slider_row(lc, "Effects", float(Sfx.pref("sfx", 0.9)), 0.0, 1.0, func(x):
		Sfx.set_pref("sfx", x)
		Sfx.play("click", -6.0))
	lc.add_child(_set_head("Controls"))
	_slider_row(lc, "Interface size", float(Sfx.pref("ui_scale", 0.85 if not DisplayServer.is_touchscreen_available() else 1.0)), 0.6, 1.3, func(x):
		Sfx.set_pref("ui_scale", x)
		ui_scale_changed.emit())
	_slider_row(lc, "Mouse sensitivity", float(Sfx.pref("mouse", 1.0)), 0.3, 2.5, func(x): Sfx.set_pref("mouse", x))
	_slider_row(lc, "Fight speed", float(Sfx.pref("fight_speed", 0.7)), 0.4, 1.0, func(x): Sfx.set_pref("fight_speed", x))
	var hints := CheckButton.new()
	hints.text = "Button hints in fights"
	hints.button_pressed = bool(Sfx.pref("hints", Game.player_level() < 15))
	hints.focus_mode = Control.FOCUS_NONE
	hints.toggled.connect(func(on): Sfx.set_pref("hints", on))
	lc.add_child(hints)
	var inv := CheckButton.new()
	inv.text = "Invert camera up/down"
	inv.button_pressed = bool(Sfx.pref("invert_y", false))
	inv.focus_mode = Control.FOCUS_NONE
	inv.toggled.connect(func(on): Sfx.set_pref("invert_y", on))
	lc.add_child(inv)
	rc.add_child(_set_head("Graphics"))
	var fs := UiKit.button("Exit full screen" if is_fullscreen() else "Full screen", Vector2(0, 34))
	fs.add_theme_font_size_override("font_size", 15)
	fs.pressed.connect(func():
		var going_full := not is_fullscreen()
		toggle_fullscreen()
		fs.text = Tx.s("Exit full screen") if going_full else Tx.s("Full screen"))
	rc.add_child(fs)
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 6)
	rc.add_child(gr)
	var btns: Array = []
	for i in 3:
		var b := UiKit.button(["Low (phones)", "High", "Ultra (desktop)"][i], Vector2(0, 34))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
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
				gfx_btn.text = Tx.s("Gfx: ") + Tx.s(Game.GFX_NAMES[bi])
			graphics_changed.emit())
	var kh := HBoxContainer.new()
	kh.add_child(_set_head("Keys"))
	var ksp := Control.new()
	ksp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kh.add_child(ksp)
	var kreset := UiKit.button("Reset keys", Vector2(0, 28))
	kreset.add_theme_font_size_override("font_size", 13)
	kh.add_child(kreset)
	rc.add_child(kh)
	rc.add_child(UiKit.label("Click a key, then press the new one (Esc cancels). Mouse: left drag look, right drag turn, both run, wheel zoom.", 13, UiKit.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	rc.add_child(grid)
	_key_btns = {}
	for row_ in Keys.LIST:
		var act: String = row_[0]
		var d := UiKit.label(str(row_[1]), 14, UiKit.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_OFF
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(d)
		var kb := UiKit.button(Keys.label(act), Vector2(96, 26))
		kb.add_theme_font_size_override("font_size", 14)
		kb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		kb.pressed.connect(func(): _start_rebind(act))
		grid.add_child(kb)
		_key_btns[act] = kb
	kreset.pressed.connect(func():
		Keys.reset()
		_refresh_key_btns()
		_redraw_bar()
		show_toast("Keys reset to the defaults.", UiKit.ACCENT))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var narrow := vs.x < 760.0
	var resume := UiKit.button("Resume", Vector2(130 if narrow else 180, 44))
	resume.pressed.connect(toggle_settings)
	row.add_child(resume)
	var barb := UiKit.button("Barber (change look)", Vector2(180 if narrow else 230, 44))
	barb.pressed.connect(func():
		toggle_settings()
		barber_requested.emit())
	row.add_child(barb)
	# the scroll area is only as tall as it needs to be (capped by the screen)
	var cap := sc.custom_minimum_size.y
	(func():
		if is_instance_valid(sc):
			sc.custom_minimum_size.y = minf(cols.get_combined_minimum_size().y + 4, cap)).call_deferred()
	var quit := UiKit.button("Title screen", Vector2(130 if narrow else 180, 44))
	quit.pressed.connect(func():
		get_tree().paused = false
		Game.save_game()
		get_tree().reload_current_scene())
	row.add_child(quit)
	if narrow:
		for b in [resume, barb, quit]:
			(b as Button).add_theme_font_size_override("font_size", 15)
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
## Is this rank-99 technique taught by your class's talent tree (or its signature)?
func _class_teaches(id: String) -> bool:
	if Rpg.STYLES.has(Game.style) and id in Rpg.STYLES[Game.style].signature:
		return true
	for n in TalentTrees.class_tree():
		var fx: Dictionary = n.get("fx", {})
		if str(fx.get("move", "")) == id or id in fx.get("moves", []):
			return true
		for ch in n.get("choice", []):
			if str(ch.get("fx", {}).get("move", "")) == id:
				return true
	return false

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
		sub = Tx.f("Specializations unlock at level %d (you're level %d).", [Specs.UNLOCK_LEVEL, Game.player_level()])
	elif cur.is_empty():
		sub = "Choose your path. Your first choice is free; switching later costs R$ %d." % Specs.RESPEC_COST
	else:
		sub = Tx.f("Switching specialization costs R$ %d  ·  you have R$ %d", [Specs.RESPEC_COST, Game.money])
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
	em.key = "spec_" + str(sp.id)
	em.custom_minimum_size = Vector2(0, 66)
	var emc := CenterContainer.new()
	var art := IconArt.tex("spec_" + str(sp.id))
	if art != null:
		# big painted crest in a bronze frame (gold when active)
		var fr := PanelContainer.new()
		var fs := Wow.sb(Color(0, 0, 0, 1), Wow.GOLD if mine else Wow.FRAME, 3, 6, 3)
		fr.add_theme_stylebox_override("panel", fs)
		var tr := TextureRect.new()
		tr.texture = art
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.custom_minimum_size = Vector2(112, 112)
		if not mine and Game.spec != "":
			tr.modulate = Color(0.75, 0.75, 0.75)
		fr.add_child(tr)
		emc.add_child(fr)
	else:
		emc.add_child(em)
	col.add_child(emc)
	col.add_child(Wow.title(str(sp.name), 19, Wow.WHITE))
	(col.get_child(col.get_child_count() - 1) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(Wow.label(Tx.f("%s%s", [role.name, "  ·  ACTIVE" if mine else ""]), 13, rc.lightened(0.25), false, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(Wow.label(str(sp.desc), 13, Wow.PALE, true, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(Wow.banner("Passive"))
	col.add_child(Wow.label(str(sp.passive), 13, Wow.GREEN, true))
	col.add_child(Wow.banner("Technique"))
	if str(sp.move) == "":
		# Professor: Corner Advice instead of a technique
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var ic2 := SpellIcon.new()
		ic2.col = Team.ROLES.coach.color
		ic2.glyph = "star"
		ic2.key = "t_secondwind"
		ic2.glow = true
		hb.add_child(ic2)
		var tv2 := VBoxContainer.new()
		tv2.add_theme_constant_override("separation", -2)
		tv2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tv2.add_child(Wow.label(Specs.ADVICE_NAME, 15, Wow.WHITE))
		tv2.add_child(Wow.label("Heal 20%, +30 Gas, +15% damage for 10s", 12, Wow.GREY))
		hb.add_child(tv2)
		col.add_child(hb)
	else:
		var e := SpellEntry.new()
		e.move_id = str(sp.move)
		e.add_theme_constant_override("separation", 8)
		var ic := SpellIcon.new()
		ic.col = CombatUi.KIND_COLORS[RollSim.counter_kind(str(sp.move))]
		ic.glyph = CombatUi.slot_icon(str(sp.move), "move")
		ic.key = IconArt.move_key(str(sp.move))
		ic.glow = true
		e.add_child(ic)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -2)
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(Wow.label(str(Data.MOVES[sp.move].name), 15, Wow.WHITE))
		tv.add_child(Wow.label(Tx.f("%s  ·  hover for details", MoveInfo.TYPE_NAMES.get(str(Data.MOVES[sp.move].type), "")), 12, Wow.GREY))
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
		b.text = Tx.f("Unlocks at level %d", Specs.UNLOCK_LEVEL)
		b.disabled = true
	else:
		var cost := Game.spec_cost(sp.id)
		b.text = "Activate" if cost == 0 else Tx.f("Activate  (R$ %d)", cost)
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
	# --- abilities: drag them onto the action bar
	var ah := Wow.title("Your Moves", 19, Color(0.45, 0.2, 0.05))
	ah.add_theme_constant_override("outline_size", 0)
	v.add_child(ah)
	var asub := Wow.label("Drag a move onto your action bar · right-click a bar slot to clear it · new ones unlock as you level", 13, Color(0.35, 0.24, 0.12))
	asub.add_theme_constant_override("outline_size", 0)
	v.add_child(asub)
	var ag := GridContainer.new()
	ag.columns = 3
	ag.add_theme_constant_override("h_separation", 18)
	ag.add_theme_constant_override("v_separation", 8)
	v.add_child(ag)
	var me = combat_hud.combat.me if combat_hud and combat_hud.combat else null
	for a in Abilities.player_kit():
		ag.add_child(AbilityEntry.make(a, me, true))
	for a in Abilities.future_kit():
		ag.add_child(AbilityEntry.make(a, me, false))
	var known_n := 0
	for id in Data.MOVES:
		if Game.knows(id):
			known_n += 1
	var th := Wow.title("Technique library", 19, Color(0.45, 0.2, 0.05))
	th.add_theme_constant_override("outline_size", 0)
	v.add_child(th)
	var sub := Wow.label(Tx.f("%d techniques known. Each move button uses the strongest technique of its kind you know.", known_n), 13, Color(0.35, 0.24, 0.12))
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
			# other classes' techniques aren't in your book (not every class learns every move)
			if not Data.class_ok(id, Game.style) or (int(m.rank) == 99 and not m.has("spec") and not Game.knows(id) and not _class_teaches(id)):
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

## A spellbook ability: icon + name + where it sits on your bar. Drag it onto a bar slot.
class AbilityEntry extends HBoxContainer:
	var ab := {}
	var me
	var ready_ := true
	var _tip: Control
	static func make(a: Dictionary, unit, have: bool) -> AbilityEntry:
		var e := AbilityEntry.new()
		e.ab = a
		e.me = unit
		e.ready_ = have
		e.add_theme_constant_override("separation", 8)
		e.custom_minimum_size = Vector2(300, 46)
		var ic := SpellIcon.new()
		var icn: Array = CombatHud.icon_of(a)
		ic.col = icn[1]
		ic.glyph = str(icn[0])
		ic.key = IconArt.ability_key(a)
		ic.known = have
		ic.glow = str(a.id) in ["spec", "racial"] and have
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		e.add_child(ic)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -2)
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		e.add_child(tv)
		var nm := Wow.label(str(a.get("name", "")), 16, Wow.INK if have else Color(0.45, 0.4, 0.33))
		nm.add_theme_constant_override("outline_size", 0)
		tv.add_child(nm)
		var where := ""
		if not have:
			where = Tx.f("Unlocks at level %d", int(a.get("unlock", 1)))
		elif str(a.id) in Abilities.UTILITY:
			where = Tx.f("Always on your bar [%s]", Keys.label("ab_" + str(a.id)))
		else:
			var i := Game.bar_layout.find(str(a.id))
			where = (Tx.f("On your bar [%s]", Keys.label("ab_%d" % i))) if i >= 0 else "Not on your bar: drag it there"
		var sl := Wow.label(where, 12, Color(0.4, 0.3, 0.18) if have else Color(0.5, 0.25, 0.2))
		sl.add_theme_constant_override("outline_size", 0)
		tv.add_child(sl)
		return e
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG if ready_ else Control.CURSOR_ARROW
		mouse_entered.connect(func():
			_tip = CombatHud.tooltip_for(ab, me)
			if _tip == null:
				return
			_tip.top_level = true
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
	func _get_drag_data(_at: Vector2) -> Variant:
		if not ready_ or str(ab.id) in Abilities.UTILITY:
			return null
		var prev := Label.new()
		prev.text = str(ab.get("name", ""))
		prev.add_theme_font_override("font", Wow.title_font())
		prev.add_theme_font_size_override("font_size", 16)
		set_drag_preview(prev)
		return {"ability": str(ab.id), "from_slot": -1}

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
	var key := ""
	func _init() -> void:
		custom_minimum_size = Vector2(44, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		if true:
			IconArt.draw(self, r, glyph, col, Wow.GOLD if glow else Color(0, 0, 0, 0), not known, key)
			return
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
	ic.key = IconArt.move_key(id)
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
		subt = (Tx.f("%s spec", Specs.get_spec(str(m.spec)).name)) if m.has("spec") else Tx.f("Unlocks at %s", Data.rank_name(int(m.rank)))
	elif m.role != "any":
		subt += "  ·  " + ("top" if m.role == "top" else "bottom")
	var sl := Wow.label(subt, 12, Color(0.4, 0.3, 0.18))
	sl.add_theme_constant_override("outline_size", 0)
	tv.add_child(sl)
	return h

# ------------------------------------------------------------ team tab
## Your 5v5 squad: lineup order (who steps on first), bench swaps, coach, the role ring and records.
var _team_sel := 4   # lineup slot a bench swap replaces

func _fill_team() -> void:
	var sc := ScrollContainer.new()
	sc.name = "Team"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.set_meta("wow", true)
	journal_tabs.add_child(sc)
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(page)
	if Game.style == "":
		return
	var lu := Game.team_lineup()
	var order: Array = lu.order
	# --- lineup
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	page.add_child(left)
	left.add_child(Wow.banner("Lineup  ·  first on the mat at the top"))
	_team_sel = clampi(_team_sel, 0, order.size() - 1)
	for i in order.size():
		var f := Team.find(str(order[i]))
		if f.is_empty():
			continue
		left.add_child(_team_row(f, i, order, lu.coach))
	left.add_child(Wow.banner("Coach  ·  corner between bouts"))
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	if Wow.body():
		ob.add_theme_font_override("font", Wow.body())
	ob.add_theme_font_size_override("font_size", 14)
	var ids: Array = [""]
	ob.add_item("No coach")
	for c in Team.coaches():
		if c.id in order:
			continue
		ids.append(c.id)
		ob.add_item(Tx.f("%s%s  (+%d gas)", [c.name, "  ★ master" if c.get("boss", false) else "", int(Team.coach_heal(c) + Team.BETWEEN_REGEN)]))
		if c.id == str(lu.coach):
			ob.select(ob.item_count - 1)
	ob.item_selected.connect(func(ix: int):
		Game.set_team_lineup(order, str(ids[ix]))
		_refill_keep())
	left.add_child(ob)
	left.add_child(Wow.banner("Role Ring"))
	var ring := HBoxContainer.new()
	ring.alignment = BoxContainer.ALIGNMENT_CENTER
	ring.add_theme_constant_override("separation", 6)
	for r in ["finisher", "grinder", "anchor", "scrambler", "finisher"]:
		ring.add_child(Wow.label(Team.ROLES[r].name, 14, Team.ROLES[r].color))
		ring.add_child(Wow.label("›", 14, Wow.GREY))
	ring.remove_child(ring.get_child(ring.get_child_count() - 1))
	left.add_child(ring)
	left.add_child(Wow.label("Each role beats the next: a favourable matchup lands techniques more often. Winner stays on, stamina carries over, a draw eliminates both.", 12, Wow.GREY, true))
	# --- bench + records
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(330, 0)
	right.add_theme_constant_override("separation", 4)
	page.add_child(right)
	right.add_child(Wow.banner(Tx.f("Bench  ·  swap into slot %d", (_team_sel + 1))))
	var bench := Team.roster().filter(func(f): return not f.id in order)
	if bench.is_empty():
		right.add_child(Wow.label("Beat fighters around the world to recruit them.", 13, Wow.GREY, true))
	for f in bench:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var badge := TeamBoard._RoleBadge.new()
		badge.role = f.role
		h.add_child(badge)
		var nl := Wow.label(Tx.f("%s  ·  Lv %d %s", [f.name, Data.display_level(float(f.level)), Team.ROLES[f.role].name]), 13, Wow.WHITE)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(nl)
		var sw := Wow.button("Swap in", Vector2(76, 24))
		var fid: String = f.id
		sw.disabled = str(order[_team_sel]) == "you"
		sw.tooltip_text = "You always fight; pick another slot to swap" if sw.disabled else ""
		sw.pressed.connect(func():
			var o2: Array = order.duplicate()
			o2[_team_sel] = fid
			Game.set_team_lineup(o2, str(lu.coach) if str(lu.coach) != fid else "")
			_refill_keep())
		h.add_child(sw)
		right.add_child(h)
	right.add_child(Wow.banner("Record"))
	right.add_child(Wow.stat_row("Team matches:", str(int(Game.counters.get("team_matches", 0)))))
	right.add_child(Wow.stat_row("Team wins:", str(Game.counter("team_wins"))))
	right.add_child(Wow.stat_row("Circuito best:", Tx.f("%d / %d wins", [int(Game.flags.get("circuit_best", 0)), Circuit.ROUNDS])))
	right.add_child(Wow.stat_row("Circuito titles:", str(Game.counter("circuit_titles"))))
	var held := 0
	for tid in Data.TERRITORIES:
		if Game.holds(tid):
			held += 1
	right.add_child(Wow.stat_row("Territories held:", "%d / %d" % [held, Data.TERRITORIES.size()], Wow.GREEN if held > 0 else Wow.WHITE))
	right.add_child(Wow.label("Team matches start from the team boards at each zone's gym.", 12, Wow.GREY, true))

func _team_row(f: Dictionary, i: int, order: Array, coach: String) -> Control:
	var role: Dictionary = Team.ROLES[f.role]
	var p := PanelContainer.new()
	var sel := i == _team_sel
	p.add_theme_stylebox_override("panel", Wow.sb(Color(role.color.darkened(0.85), 0.9), Wow.GOLD if sel else Color(role.color, 0.4), 3, 6, 2 if sel else 1))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_team_sel = i
			_refill_keep())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	h.add_child(Wow.title("%d" % (i + 1), 18, Wow.GOLD))
	var badge := TeamBoard._RoleBadge.new()
	badge.role = f.role
	h.add_child(badge)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nv)
	nv.add_child(Wow.label(str(f.name) + ("  (you)" if f.get("player", false) else ""), 15, Wow.WHITE))
	nv.add_child(Wow.label(Tx.f("%s  ·  Lv %d  ·  %s", [role.name, Data.display_level(float(f.level)), Data.rank_name(int(f.rank))]), 12, role.color.lightened(0.2)))
	for d in [-1, 1]:
		var b := Wow.button("▲" if d < 0 else "▼", Vector2(28, 24))
		b.disabled = i + d < 0 or i + d >= order.size()
		b.pressed.connect(func():
			var o2: Array = order.duplicate()
			var t = o2[i]
			o2[i] = o2[i + d]
			o2[i + d] = t
			_team_sel = i + d
			Game.set_team_lineup(o2, coach)
			_refill_keep())
		h.add_child(b)
	return p

func _refill_keep() -> void:
	_want_tab = journal_tabs.current_tab
	_fill_journal()
