class_name BagUi
extends RefCounted
## Bags (B), the vendor window, item slots and item tooltips.

## One bag slot: quality border, a glyph for the item kind, stack count. Hover shows the tooltip.
class ItemSlot extends Control:
	signal clicked(k: int, right: bool)
	var k := -1
	var id := ""
	var n := 0
	var tip_holder: Control
	var price_mode := ""   # "sell" / "buy": the tooltip shows that price
	var _tip: Control
	func _init() -> void:
		custom_minimum_size = Vector2(52, 52)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(_show_tip)
		mouse_exited.connect(_hide_tip)
	func _exit_tree() -> void:
		_hide_tip()
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			clicked.emit(k, e.button_index == MOUSE_BUTTON_RIGHT)
			accept_event()
		elif e is InputEventScreenTouch and e.pressed:
			clicked.emit(k, false)
			accept_event()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var col := Loot.color(id) if id != "" else Color(1, 1, 1, 0.12)
		if id == "":
			draw_rect(r, Color(0.03, 0.03, 0.04, 0.9))
			draw_rect(r.grow(-1.5), Color(0.3, 0.24, 0.14, 0.6), false, 1.5)
			return
		var it := Loot.item(id)
		var glyph: String = {"junk": "loop", "food": "heart", "bag": "lock", "gear": "shield"}.get(str(it.get("kind", "")), "star")
		if str(it.get("icon", "")) in ["star", "medal"]:
			glyph = "star"
		elif str(it.get("icon", "")) in ["drop", "cup", "bottle", "fish"]:
			glyph = "wave"
		var tint: Color = {"junk": Color(0.6, 0.55, 0.5), "food": Color(0.95, 0.55, 0.3), "bag": Color(0.75, 0.55, 0.3), "gear": Color(0.55, 0.7, 0.95)}.get(str(it.get("kind", "")), Color(0.9, 0.8, 0.4))
		IconArt.draw(self, r, glyph, tint, col if Loot.color(id) != Color.WHITE else Color(0, 0, 0, 0), false, IconArt.item_key(id, it))
		if n > 1:
			var f := CombatUi.font()
			draw_string(f, Vector2(size.x - 22, size.y - 6), str(n), HORIZONTAL_ALIGNMENT_RIGHT, 18, 14, Color.WHITE)
	func _show_tip() -> void:
		_hide_tip()
		if id == "" or tip_holder == null:
			return
		_tip = BagUi.tooltip(id, n, price_mode)
		tip_holder.add_child(_tip)
		_tip.reset_size()
		var gp := global_position + Vector2(size.x + 8, 0)
		var vs := get_viewport_rect().size
		if gp.x + _tip.size.x > vs.x:
			gp.x = global_position.x - _tip.size.x - 8
		gp.y = clampf(gp.y, 4, vs.y - _tip.size.y - 4)
		_tip.global_position = gp
	func _hide_tip() -> void:
		if _tip and is_instance_valid(_tip):
			_tip.queue_free()
		_tip = null

static func tooltip(id: String, n := 1, price_mode := "") -> PanelContainer:
	var it := Loot.item(id)
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.top_level = true
	p.z_index = 100
	p.add_theme_stylebox_override("panel", Wow.tip_box())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.custom_minimum_size = Vector2(290, 0)
	p.add_child(v)
	v.add_child(MoveInfo._line(str(it.get("name", id)), 19, Loot.color(id)))
	var kind := str(it.get("kind", ""))
	var kline: String = {"junk": "Junk  ·  sell it to a vendor", "food": "Food & drink  ·  click to consume", "bag": "Bag  ·  %d slots  ·  click to equip" % int(it.get("slots", 0)), "gear": "Gear  ·  click to add to your wardrobe"}.get(kind, "")
	v.add_child(MoveInfo._line(kline, 13, UiKit.MUTED))
	if kind == "gear":
		var gid := str(it.gear)
		v.add_child(MoveInfo._line(Gear.stat_text(gid), 14, Color(0.45, 1.0, 0.55), true))
		if Game.has_item(gid):
			v.add_child(MoveInfo._line("Already in your wardrobe", 13, UiKit.RED))
	if kind == "food":
		v.add_child(MoveInfo._line("Use: " + str(it.desc), 14, Color(0.45, 1.0, 0.55), true))
	elif str(it.get("desc", "")) != "":
		v.add_child(MoveInfo._line("\"%s\"" % it.desc, 13, Color(1, 0.86, 0.55), true))
	if price_mode == "buy":
		v.add_child(MoveInfo._line("Price: R$ %d" % int(it.get("buy", 0)), 15, Color(1, 0.85, 0.35)))
	elif int(it.get("sell", 0)) > 0:
		v.add_child(MoveInfo._line("Sells for: R$ %d%s" % [int(it.sell) * maxi(1, n), ("  (%d each)" % int(it.sell)) if n > 1 else ""], 14, Color(1, 0.85, 0.35)))
	return p

## The bags window: backpack + equipped bags as one grid, bag bar, money.
class BagPanel extends PanelContainer:
	var shop_mode := false
	var _grid: GridContainer
	var _money: Label
	var _bagbar: HBoxContainer
	var _msg: Label
	func _init() -> void:
		anchor_left = 1.0
		anchor_right = 1.0
		anchor_top = 1.0
		anchor_bottom = 1.0
		grow_horizontal = Control.GROW_DIRECTION_BEGIN
		grow_vertical = Control.GROW_DIRECTION_BEGIN
		offset_right = -16
		offset_bottom = -60
		theme = Wow.theme()
		add_theme_stylebox_override("panel", Wow.sb(Wow.BG, Wow.FRAME, 6, 10, 2))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		add_child(v)
		var head := HBoxContainer.new()
		v.add_child(head)
		var t := Wow.title("Bags", 16, Wow.GOLD)
		t.autowrap_mode = TextServer.AUTOWRAP_OFF
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		_money = Wow.label("", 18, Color(1, 0.85, 0.35))
		_money.autowrap_mode = TextServer.AUTOWRAP_OFF
		head.add_child(_money)
		var x := Button.new()
		x.text = "✕"
		x.focus_mode = Control.FOCUS_NONE
		x.pressed.connect(func(): visible = false)
		head.add_child(x)
		_grid = GridContainer.new()
		_grid.columns = 8
		_grid.add_theme_constant_override("h_separation", 4)
		_grid.add_theme_constant_override("v_separation", 4)
		v.add_child(_grid)
		_bagbar = HBoxContainer.new()
		_bagbar.add_theme_constant_override("separation", 4)
		v.add_child(_bagbar)
		_msg = Wow.label("", 13, UiKit.MUTED)
		_msg.autowrap_mode = TextServer.AUTOWRAP_OFF
		v.add_child(_msg)
		Game.bag_changed.connect(func(): if visible: refresh())
		visibility_changed.connect(func(): if visible: refresh())
	func refresh() -> void:
		Game._fit_bag()
		_money.text = "R$ %d   " % Game.money
		for c in _grid.get_children():
			c.queue_free()
		for k in Game.bag_capacity():
			var s := ItemSlot.new()
			s.k = k
			var st = Game.bag[k]
			if st != null:
				s.id = str(st.id)
				s.n = int(st.n)
			s.tip_holder = self
			s.price_mode = "sell" if shop_mode else ""
			s.clicked.connect(_clicked)
			_grid.add_child(s)
		for c in _bagbar.get_children():
			c.queue_free()
		var bl := Wow.label("Bag slots:", 13, UiKit.MUTED)
		bl.autowrap_mode = TextServer.AUTOWRAP_OFF
		_bagbar.add_child(bl)
		for i in Loot.BAG_SLOTS:
			var bs := ItemSlot.new()
			bs.custom_minimum_size = Vector2(40, 40)
			bs.k = i
			bs.id = str(Game.bags[i])
			bs.tip_holder = self
			bs.clicked.connect(func(ix: int, _r: bool):
				var why := Game.unequip_bag(ix)
				_msg.text = why)
			_bagbar.add_child(bs)
		_msg.text = "%d / %d free  ·  %s" % [Game.free_slots(), Game.bag_capacity(), "click to sell" if shop_mode else "click to use"]
	func _clicked(k: int, _right: bool) -> void:
		if Game.bag[k] == null:
			return
		if shop_mode:
			var name_: String = Loot.item(str(Game.bag[k].id)).get("name", "")
			var got := Game.sell_slot(k)
			Sfx.play("click", -6.0)
			_msg.text = "Sold %s for R$ %d" % [name_, got]
			return
		var why := Game.use_slot(k)
		if why != "":
			_msg.text = why
		else:
			Sfx.play("perfect", -10.0, 1.4)

## Vendor window: what they sell (click to buy) + sell-all-junk. Your bags open alongside.
class ShopPanel extends PanelContainer:
	signal closed
	var vendor := ""
	var _list: VBoxContainer
	var _msg: Label
	func _init() -> void:
		anchor_left = 0.0
		anchor_top = 0.5
		anchor_bottom = 0.5
		offset_left = 24
		grow_vertical = Control.GROW_DIRECTION_BOTH
		theme = Wow.theme()
		add_theme_stylebox_override("panel", Wow.sb(Wow.BG, Wow.FRAME, 6, 12, 2))
	func build(vendor_name: String) -> void:
		vendor = vendor_name
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		v.custom_minimum_size = Vector2(360, 0)
		add_child(v)
		var t := Wow.title(vendor, 17, Wow.GOLD)
		t.autowrap_mode = TextServer.AUTOWRAP_OFF
		v.add_child(t)
		v.add_child(Wow.label("\"Olha o açaí! Fresquinho!\"  ·  Click your bag items to sell them.", 13, UiKit.MUTED))
		_list = VBoxContainer.new()
		_list.add_theme_constant_override("separation", 4)
		v.add_child(_list)
		for id in Loot.VENDOR.get(Game.zone, Loot.VENDOR.caceres):
			_list.add_child(_row(str(id)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var junk := Wow.button("Sell all junk", Vector2(170, 44))
		junk.add_theme_font_size_override("font_size", 16)
		junk.pressed.connect(func():
			var got := Game.sell_junk()
			_msg.text = "Sold your junk for R$ %d" % got if got > 0 else "No junk to sell."
			Sfx.play("click", -6.0))
		row.add_child(junk)
		var close := Wow.button("Tchau!", Vector2(120, 44))
		close.add_theme_font_size_override("font_size", 16)
		close.pressed.connect(func(): closed.emit())
		row.add_child(close)
		_msg = Wow.label("", 14, UiKit.MUTED)
		_msg.autowrap_mode = TextServer.AUTOWRAP_OFF
		v.add_child(_msg)
	func _row(id: String) -> Control:
		var it := Loot.item(id)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var s := ItemSlot.new()
		s.id = id
		s.n = 1
		s.tip_holder = self
		s.price_mode = "buy"
		s.custom_minimum_size = Vector2(44, 44)
		s.clicked.connect(func(_k, _r): _buy(id))
		h.add_child(s)
		var nm := Wow.label(str(it.name), 16, Loot.color(id))
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		var b := Wow.button("R$ %d" % int(it.buy), Vector2(92, 40))
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
		b.pressed.connect(func(): _buy(id))
		h.add_child(b)
		return h
	func _buy(id: String) -> void:
		var why := Game.buy(id)
		_msg.text = why if why != "" else "Bought %s." % Loot.item(id).name
		Sfx.play("click" if why == "" else "miss", -6.0)

## Small HUD widget: money, bag fill, active buff chips. Click to open the bags.
class Wallet extends VBoxContainer:
	signal open_bags
	var _money: Button
	var _buffs: HBoxContainer
	var _t := 0.0
	func _init() -> void:
		anchor_left = 1.0
		anchor_right = 1.0
		anchor_top = 1.0
		anchor_bottom = 1.0
		grow_horizontal = Control.GROW_DIRECTION_BEGIN
		grow_vertical = Control.GROW_DIRECTION_BEGIN
		offset_right = -16
		offset_bottom = -60    # sits above the micro menu
		alignment = BoxContainer.ALIGNMENT_END
		add_theme_constant_override("separation", 4)
		_buffs = HBoxContainer.new()
		_buffs.alignment = BoxContainer.ALIGNMENT_END
		_buffs.add_theme_constant_override("separation", 4)
		add_child(_buffs)
		_money = Button.new()
		_money.focus_mode = Control.FOCUS_NONE
		_money.add_theme_font_size_override("font_size", 16)
		_money.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
		_money.add_theme_stylebox_override("normal", Wow.sb(Color(0.03, 0.03, 0.05, 0.85), Wow.FRAME, 3, 10))
		_money.add_theme_stylebox_override("hover", Wow.sb(Color(0.1, 0.08, 0.06, 0.9), Wow.FRAME_HI, 3, 10))
		if Wow.body():
			_money.add_theme_font_override("font", Wow.body())
		_money.add_theme_font_size_override("font_size", 14)
		_money.pressed.connect(func(): open_bags.emit())
		add_child(_money)
		Game.bag_changed.connect(refresh)
		refresh()
	func _process(delta: float) -> void:
		_t -= delta
		if _t <= 0.0:
			_t = 1.0
			refresh()
	func refresh() -> void:
		_money.text = "R$ %d   ·   Bags %d/%d   [B]" % [Game.money, Game.bag_capacity() - Game.free_slots(), Game.bag_capacity()]
		for c in _buffs.get_children():
			c.queue_free()
		var active := Game.active_buffs()
		for id in active:
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", UiKit.box(Color(Loot.color(id).darkened(0.7), 0.9), 8, Loot.color(id), 1))
			chip.tooltip_text = "%s\n%s" % [Loot.item(id).name, Loot.item(id).desc]
			var l := Wow.label("%s %d:%02d" % [str(Loot.item(id).name).split(" ")[0], int(active[id]) / 60, int(active[id]) % 60], 12, UiKit.TEXT)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			chip.add_child(l)
			_buffs.add_child(chip)
