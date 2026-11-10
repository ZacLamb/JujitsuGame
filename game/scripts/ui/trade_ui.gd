class_name TradePanel
extends PanelContainer
## The trade window (see Trade): your side, their side, R$, Accept / Cancel.

var trade: Trade
var _mine: GridContainer
var _theirs: GridContainer
var _money: SpinBox
var _their_money: Label
var _my_state: Label
var _their_state: Label
var _accept: Button
var _msg: Label
var _title: Label

func _init(t: Trade) -> void:
	trade = t
	theme = Wow.theme()
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = -380
	offset_right = 120
	offset_top = -210
	offset_bottom = 150
	add_theme_stylebox_override("panel", Wow.sb(Wow.BG, Wow.FRAME, 6, 12, 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	_title = Wow.title("", 20, Wow.GOLD)
	v.add_child(_title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	v.add_child(cols)
	var a := _column(cols, "You")
	_mine = a[0]
	_my_state = a[1]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	(a[2] as VBoxContainer).add_child(row)
	row.add_child(Wow.label("R$", 15, Color(1, 0.85, 0.35)))
	_money = SpinBox.new()
	_money.min_value = 0
	_money.step = 1
	_money.custom_minimum_size = Vector2(130, 0)
	_money.value_changed.connect(func(x): trade.set_money(int(x)))
	row.add_child(_money)
	var b := _column(cols, "Them")
	_theirs = b[0]
	_their_state = b[1]
	_their_money = Wow.label("", 15, Color(1, 0.85, 0.35))
	(b[2] as VBoxContainer).add_child(_their_money)
	var hint := Wow.label("Click items in your bags to put them on the table (click again to take them back). Changing anything clears both Accepts.", 13, UiKit.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(470, 0)
	v.add_child(hint)
	_msg = Wow.label("", 13, Color(1, 0.6, 0.4))
	v.add_child(_msg)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)
	_accept = Wow.button("Accept", Vector2(150, 36))
	_accept.pressed.connect(func(): _msg.text = trade.set_lock(not trade.my_lock))
	btns.add_child(_accept)
	var c := Wow.button("Cancel", Vector2(150, 36))
	c.pressed.connect(func(): trade.cancel())
	btns.add_child(c)
	trade.changed.connect(refresh)
	trade.closed.connect(queue_free)
	Game.bag_changed.connect(func(): if is_instance_valid(self): refresh())
	refresh()

func _column(parent: Control, head: String) -> Array:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	parent.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := Wow.label(head, 16, Wow.WHITE)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var st := Wow.label("", 13, Color(0.4, 1.0, 0.5))
	h.add_child(st)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	v.add_child(g)
	return [g, st, v]

func refresh() -> void:
	if trade.state != "open":
		return
	_title.text = Tx.f("Trade with %s", trade.peer_name)
	for c in _mine.get_children():
		c.queue_free()
	for c in _theirs.get_children():
		c.queue_free()
	for i in Trade.MAX_ITEMS:
		var s := BagUi.ItemSlot.new()
		s.tip_holder = self
		if i < trade.mine.size():
			var k: int = trade.mine[i]
			var st = Game.bag[k] if k < Game.bag.size() else null
			if st != null:
				s.id = str(st.id)
				s.n = int(st.n)
				s.k = k
				s.clicked.connect(func(kk: int, _r: bool): _msg.text = trade.toggle_slot(kk))
		_mine.add_child(s)
		var o := BagUi.ItemSlot.new()
		o.tip_holder = self
		if i < trade.theirs.size():
			var e: Dictionary = trade.theirs[i]
			o.id = str(e.get("show", e.get("id", "")))
			o.n = int(e.get("n", 1))
		_theirs.add_child(o)
	_money.max_value = Game.money
	_money.set_value_no_signal(trade.my_money)
	_their_money.text = "R$ %d" % trade.their_money
	_my_state.text = Tx.s("Accepted") if trade.my_lock else ""
	_their_state.text = Tx.s("Accepted") if trade.their_lock else ""
	_accept.text = Tx.s("Unaccept") if trade.my_lock else Tx.s("Accept")
