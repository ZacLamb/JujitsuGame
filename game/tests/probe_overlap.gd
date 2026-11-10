extends Node
## HUD overlap audit at a window size: -- w=1920 h=1080 [touch]. Prints every visible HUD block
## (by name) and every pair that overlaps, then saves a screenshot.
var main: Node
func _ready() -> void:
	var w := 1920
	var h := 1080
	var tag := ""
	var force_touch := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("w="): w = int(a.substr(2))
		if a.begins_with("h="): h = int(a.substr(2))
		if a == "touch": force_touch = true
		if a.begins_with("ui="): Sfx.prefs["ui_scale"] = float(a.substr(3))
	get_window().size = Vector2i(w, h)
	Game.test_mode = true
	Game.reset()
	Game.set_identity("gringo", "male", 0.4)
	Game.choose_style("guard", "Gringo", 0)
	Game.set_level(12)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 5: await get_tree().process_frame
	main._start_game()
	for i in 20: await get_tree().process_frame
	main.hud._close_dialogue(false)
	if force_touch:
		main.hud.touch_mode = true
		main.hud.touch.visible = true
	main._fit_screen()
	for i in 10: await get_tree().process_frame
	var items := _blocks()
	print("viewport ", get_viewport().get_visible_rect().size, " window ", Vector2(w, h))
	for it in items:
		print("  ", it[0], " ", it[1])
	var bad := 0
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Rect2 = items[i][1]
			var b: Rect2 = items[j][1]
			var x := a.intersection(b)
			if x.size.x > 2 and x.size.y > 2:
				print("OVERLAP ", items[i][0], " x ", items[j][0], " ", x)
				bad += 1
	print("overlaps: ", bad)
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/ov_%dx%d%s.png" % [w, h, "t" if force_touch else ""])
	# and with each window open
	for win in ["character", "talents", "journal"]:
		main.hud.open_window(win)
		for i in 6: await get_tree().process_frame
		var r: Rect2 = main.hud.journal.get_global_rect()
		for it in _blocks():
			if str(it[0]) in ["player frame", "action bar", "micro menu", "chat"]:
				var x: Rect2 = r.intersection(it[1])
				if x.size.x > 2 and x.size.y > 2:
					print("OVERLAP window ", win, " x ", it[0], " ", x)
		var vr := get_viewport().get_visible_rect()
		if not vr.encloses(r.grow(-1)):
			print("OFFSCREEN window ", win, " ", r)
		get_viewport().get_texture().get_image().save_png("/home/claude/shots/ov_%dx%d_%s.png" % [w, h, win])
		main.hud.toggle_journal()
		for i in 3: await get_tree().process_frame
	main.hud.toggle_settings()
	for i in 6: await get_tree().process_frame
	var sr: Rect2 = main.hud.settings_panel.get_global_rect()
	if not get_viewport().get_visible_rect().encloses(sr.grow(-1)):
		print("OFFSCREEN settings ", sr)
	get_viewport().get_texture().get_image().save_png("/home/claude/shots/ov_%dx%d_settings.png" % [w, h])
	get_tree().quit()

func _blocks() -> Array:
	var hud = main.hud
	var out: Array = []
	var mr: Rect2 = hud.minimap._mini_rect()
	out.append(["minimap", mr.grow(10)])
	var named := {}
	named["player frame"] = hud.get("_player_frame")
	for c in hud.root.get_children():
		if c is Control and c.visible and c != hud.minimap and not (c is Label and (c as Label).text.strip_edges() == "") and (c as CanvasItem).modulate.a > 0.05:
			var r: Rect2 = (c as Control).get_global_rect()
			var vs := get_viewport().get_visible_rect().size
			if c == hud.touch or (r.size.x >= vs.x - 2 and r.size.y >= vs.y - 2):
				continue   # full-screen layers
			if r.size.x < 4 or r.size.y < 4:
				continue
			out.append([_name(c), r])
	if hud.touch.visible:
		for b in [hud.touch.jump_btn, hud.touch.sprint_btn, hud.touch.autorun_btn]:
			out.append(["touch " + b.text, (b as Control).get_global_rect()])
		var vs2 := get_viewport().get_visible_rect().size
		out.append(["joystick", Rect2(Vector2(vs2.x * 0.16, vs2.y - 150 - hud.touch.lift) - Vector2(80, 80), Vector2(160, 160))])
	if hud.combat_hud:
		for c in hud.combat_hud.get_children():
			if c is Control and c.visible and not (c is Label and (c as Label).text.strip_edges() == ""):
				var r2: Rect2 = (c as Control).get_global_rect()
				if r2.size.x > 4 and r2.size.y > 4:
					out.append([_name(c), r2])
	return out

func _name(c: Node) -> String:
	if c.name == "ActionBar":
		return "action bar"
	if (c is HBoxContainer or c is HFlowContainer) and c.get_child_count() >= 6 and c.get_child(0).get_class() == "Button":
		return "micro menu"
	if c.get_script() and str(c.get_script().resource_path).ends_with("combat_log.gd"):
		return "chat"
	return "%s(%s)" % [c.name, c.get_class()]
