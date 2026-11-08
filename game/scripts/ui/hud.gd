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
var journal: PanelContainer
var journal_tabs: TabContainer
var title: Control
var touch: TouchControls
var journal_btn: Button
var status_panels: Array = []
var touch_mode := false
var _obj_panel: PanelContainer
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
	var panel := PanelContainer.new()
	panel.position = Vector2(14, 14)
	panel.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.45), 14))
	root.add_child(panel)
	status_panels.append(panel)
	rank_box = VBoxContainer.new()
	rank_box.add_theme_constant_override("separation", 6)
	panel.add_child(rank_box)
	rank_label = UiKit.label("", 20)
	rank_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	rank_box.add_child(rank_label)
	chip_holder = HBoxContainer.new()
	rank_box.add_child(chip_holder)
	lvl_label = UiKit.label("", 17, Color(0.6, 0.9, 1.0))
	lvl_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	rank_box.add_child(lvl_label)
	xp_bar = UiKit.bar(XP_COLOR, Vector2(240, 14))
	xp_bar.add_theme_stylebox_override("background", UiKit.box(Color(0.08, 0.05, 0.14, 0.85), 7, Color(0.5, 0.35, 0.8, 0.7), 1))
	rank_box.add_child(xp_bar)

	var right := PanelContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -500
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.offset_right = -14
	right.offset_top = 14
	right.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.45), 14))
	root.add_child(right)
	_obj_panel = right
	status_panels.append(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	var head := HBoxContainer.new()
	rv.add_child(head)
	zone_lbl = UiKit.label("OBJECTIVE", 14, UiKit.ACCENT)
	zone_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zone_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(zone_lbl)
	journal_btn = UiKit.button("Character (C)", Vector2(150, 34))
	journal_btn.add_theme_font_size_override("font_size", 15)
	journal_btn.pressed.connect(open_character)
	head.add_child(journal_btn)
	var snd := UiKit.button("Sound: off" if Sfx.muted else "Sound: on", Vector2(110, 34))
	snd.add_theme_font_size_override("font_size", 15)
	snd.pressed.connect(func():
		Sfx.set_muted(not Sfx.muted)
		snd.text = "Sound: off" if Sfx.muted else "Sound: on")
	head.add_child(snd)
	gfx_btn = UiKit.button("Gfx: " + Game.GFX_NAMES[Game.graphics_level()], Vector2(104, 34))
	var gfx := gfx_btn
	gfx.add_theme_font_size_override("font_size", 15)
	gfx.pressed.connect(func():
		Game.set_graphics_level((Game.graphics_level() + 1) % 3)
		gfx.text = "Gfx: " + Game.GFX_NAMES[Game.graphics_level()]
		graphics_changed.emit())
	head.add_child(gfx)
	objective = UiKit.label("", 19)
	objective.custom_minimum_size = Vector2(380, 0)
	rv.add_child(objective)

func set_portrait(p: bool) -> void:
	if _obj_panel == null:
		return
	if p:
		_obj_panel.anchor_left = 0.0
		_obj_panel.offset_left = 14
		_obj_panel.offset_top = 166
		objective.custom_minimum_size = Vector2(0, 0)
		toasts.offset_top = 276
		toasts.offset_left = -250
		toasts.offset_right = 250
	else:
		_obj_panel.anchor_left = 1.0
		_obj_panel.offset_left = -500
		_obj_panel.offset_top = 14
		objective.custom_minimum_size = Vector2(380, 0)
		toasts.offset_top = 110
		toasts.offset_left = -300
		toasts.offset_right = 300

func refresh() -> void:
	rank_label.text = "%s  ·  %s" % [Game.player_name, Data.rank_name(Game.rank)]
	for c in chip_holder.get_children():
		c.queue_free()
	chip_holder.add_child(UiKit.belt_chip(Game.rank, Vector2(150, 20)))
	var capped := Game.level_capped()
	xp_bar.value = 100.0 * Game.level_progress()
	xp_bar.add_theme_stylebox_override("fill", UiKit.box(XP_CAP_COLOR if capped else XP_COLOR, 7))
	var otext := Game.current_objective()
	for id in Game.active_quests(Game.zone).slice(0, 3):
		var q: Dictionary = Data.QUESTS[id]
		if Game.quest_ready(id):
			otext += "\n•  %s: return to %s" % [q.title, Data.QUEST_GIVERS[q.giver].name]
		else:
			var pr := Game.objective_progress(id, 0)
			otext += "\n•  %s: %s %d/%d" % [q.title, q.obj[0].text, pr[0], pr[1]]
	objective.text = otext
	if Data.ZONES.has(Game.zone):
		zone_lbl.text = "%s  ·  %s" % [Data.ZONES[Game.zone].name.to_upper(), Data.zone_levels(Game.zone).to_upper()]
	var lv := Game.player_level()
	var pts := Game.attr_points() + Game.talent_points()
	var extra := ("\n%d point%s to spend  (C)" % [pts, "" if pts == 1 else "s"]) if pts > 0 else ""
	if capped and lv < Game.MAX_LEVEL:
		lvl_label.text = "Level %d  ·  belt cap: beat the boss%s" % [lv, extra]
	elif capped:
		lvl_label.text = "Level %d  ·  MAX%s" % [lv, extra]
	else:
		lvl_label.text = "Level %d  ·  %d / %d XP%s" % [lv, int(Game.level_progress() * Game.XP_PER_LEVEL), Game.XP_PER_LEVEL, extra]
	lvl_label.add_theme_color_override("font_color", UiKit.ACCENT if pts > 0 else Color(0.78, 0.66, 1.0))
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
	dlg_name = UiKit.label("", 22, UiKit.ACCENT)
	v.add_child(dlg_name)
	dlg_text = UiKit.label("", 22)
	v.add_child(dlg_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	dlg_no = UiKit.button("Later", Vector2(150, 56))
	dlg_no.pressed.connect(func(): _close_dialogue(false))
	row.add_child(dlg_no)
	dlg_yes = UiKit.button("Oss! Let's roll", Vector2(220, 56))
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
	journal = PanelContainer.new()
	journal.anchor_left = 0.06
	journal.anchor_right = 0.94
	journal.anchor_top = 0.08
	journal.anchor_bottom = 0.94
	journal.visible = false
	root.add_child(journal)
	var v := VBoxContainer.new()
	journal.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UiKit.label("JOURNAL", 28, UiKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UiKit.button("Close", Vector2(120, 44))
	close.pressed.connect(toggle_journal)
	head.add_child(close)
	journal_tabs = TabContainer.new()
	journal_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(journal_tabs)

func open_character() -> void:
	_want_tab = 0
	if not journal.visible:
		toggle_journal()
	else:
		_fill_journal()

func toggle_journal() -> void:
	journal.visible = not journal.visible
	minimap.visible = not journal.visible
	if journal.visible:
		journal.move_to_front()
		_fill_journal()
		touch.release_all()
	touch.visible = _touch_allowed()
	journal_toggled.emit(journal.visible)

func _fill_gear() -> void:
	var g := _scroll_tab("Gear")
	var owned := 0
	for id in Gear.ITEMS:
		if Game.has_item(id):
			owned += 1
	g.add_child(UiKit.label("Gear collected: %d / %d   ·   Wearing your %s kit (switch it on the Character tab)" % [owned, Gear.ITEMS.size(), Gear.KIT_NAMES[Game.kit]], 18, UiKit.MUTED))
	for slot in Gear.SLOTS:
		g.add_child(UiKit.label(Gear.SLOT_NAMES[slot].to_upper(), 24, UiKit.ACCENT))
		var cur := str(Game.equipped.get(slot, ""))
		if cur == "":
			g.add_child(UiKit.label("Nothing equipped", 18, UiKit.MUTED))
		for id in Gear.ITEMS:
			var it: Dictionary = Gear.ITEMS[id]
			if it.slot != slot:
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			g.add_child(row)
			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			if Game.has_item(id):
				var nm := UiKit.label("%s%s" % [it.name, "   (equipped)" if id == cur else ""], 20, Gear.rarity_color(id))
				info.add_child(nm)
				info.add_child(UiKit.label("%s  ·  %s" % [Gear.RARITY[it.rarity].name, Gear.stat_text(id)], 16, UiKit.TEXT))
				if it.has("set"):
					info.add_child(UiKit.label("Set: %s (%d/%d worn)" % [Gear.SETS[it.set].name, int(Game.set_counts().get(it.set, 0)), Gear.SETS[it.set].pieces.size()], 15, UiKit.ACCENT))
				info.add_child(UiKit.label(it.desc, 15, UiKit.MUTED))
				if id != cur:
					var b := UiKit.button("Equip", Vector2(110, 44))
					b.add_theme_font_size_override("font_size", 17)
					b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					var iid: String = id
					b.pressed.connect(func():
						Game.equip(iid)
						_want_tab = journal_tabs.current_tab
						_fill_journal())
					row.add_child(b)
			else:
				info.add_child(UiKit.label("???  (%s)" % Gear.RARITY[it.rarity].name, 18, Gear.rarity_color(id).darkened(0.45)))
				info.add_child(UiKit.label("Source: %s" % it.source, 15, UiKit.MUTED))

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
	# Techniques
	var tq := _scroll_tab("Techniques")
	for pos in Data.POSITION_NAMES:
		tq.add_child(UiKit.label(Data.POSITION_NAMES[pos], 22, UiKit.ACCENT))
		for id in Data.MOVES:
			var m: Dictionary = Data.MOVES[id]
			if m.pos != pos:
				continue
			var known := Game.knows(id)
			var who := "" if pos == "standing" else ("  [top]" if m.role == "top" else "  [bottom]")
			var txt := "   %s%s%s" % [m.name, who, "" if known else "  — unlocks at %s" % Data.rank_name(int(m.rank))]
			tq.add_child(UiKit.label(txt, 18, UiKit.TEXT if known else UiKit.MUTED))
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

func _fill_character() -> void:
	var c := _scroll_tab("Character")
	c.add_child(CharSheet.build_character(self))

func _fill_talents() -> void:
	var t := _scroll_tab("Talents")
	var tp := Game.talent_points()
	journal_tabs.set_tab_title(journal_tabs.get_tab_count() - 1, "Talents (%d)" % tp if tp > 0 else "Talents")
	t.add_child(CharSheet.build_talents(self))

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
		"E or click: talk / roll   ·   C: character   ·   J or Tab: journal   ·   M: map   ·   Esc: this menu\n" + \
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
