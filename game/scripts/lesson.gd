class_name Lesson
extends Node
## The first lesson: a professor's drill that teaches the fight one idea at a time, on a partner
## who can't hurt you. Each step says one thing, waits until you've done it, then moves on.
## Starts for a new character after the opening; /lesson replays it.

signal finished(done: bool)

var main
var wc: WorldCombat
var npc: Npc
var foe: CombatCore.Unit
var step := -1
var _need := 0
var _wait := 0.0
var _recast := 0.0
var _kind := ""
var _layer: CanvasLayer
var _title: Label
var _body: Label
var _over := false

const STEPS := [
	{"id": "intro", "text": "Three things win a roll: GRIPS, POSITION, SUBMISSION. Your partner won't fight back yet. Follow along.", "secs": 4.5},
	{"id": "grip", "text": "Fight for grips: press [%s] twice. Each one builds Grip, the red dots under your bars. Grip is what powers a submission.", "key": "handfight", "need": 2},
	{"id": "takedown", "text": "Take the fight to the ground: press [%s]. You land on top.", "key": "takedown"},
	{"id": "climb", "text": "Position decides how hard you hit. Climb to a better one: [%s] passes the guard. The ladder under their name shows where you are.", "key": "pass"},
	{"id": "escape", "text": "Now you're stuck underneath. Get out: press [%s]. Escape works even when you're Down.", "key": "escape"},
	{"id": "read_td", "text": "Now they attack. The technique's name appears in the middle of the screen. A TAKEDOWN or a SWEEP is stopped by Sprawl / Base: press [%s] before the bar runs out.", "key": "base", "cast": "base"},
	{"id": "read_pass", "text": "A PASS or a change of position is stopped by Frame: press [%s].", "key": "frame", "cast": "frame"},
	{"id": "read_sub", "text": "A SUBMISSION is stopped by Defend: press [%s]. Miss this one in a real roll and you tap.", "key": "defend", "cast": "defend"},
	{"id": "mixed", "text": "Three in a row, and this time nobody tells you which. Read the name: takedown or sweep, pass, or submission. Sprawl, Frame or Defend.", "cast": "mixed", "need": 3},
	{"id": "finish", "text": "Only a submission ends a roll. They're worn down: press [%s], then mash it to squeeze until they tap.", "key": "sub"},
]

func start(m) -> void:
	main = m
	wc = m.combat
	npc = wc.start_bout({"name": Tx.s("Training Partner"), "title": "Lesson", "style": "balanced", "level": 1.0, "practice": true,
		"scripted": true, "reps": 999, "intro": "Oss.", "win": "Oss.", "lose": "Oss."}, "lesson", false)
	foe = wc.unit_for(npc)
	wc.coach = true
	wc.core.event.connect(_ev)
	_build()
	_go(0)

func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 30
	add_child(_layer)
	var p := PanelContainer.new()
	# left of the fight, clear of the technique name in the middle and the objectives on the right
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = 16
	p.offset_right = 396
	p.offset_top = -150
	p.grow_vertical = Control.GROW_DIRECTION_END
	p.add_theme_stylebox_override("panel", Wow.sb(Color(0.05, 0.04, 0.03, 0.9), Color(1.0, 0.82, 0.35), 6, 12, 2))
	_layer.add_child(p)
	var vs := get_viewport().get_visible_rect().size
	if vs.x < 900.0:
		# phones: a strip across the top, under the frames
		p.anchor_top = 0.0
		p.anchor_bottom = 0.0
		p.offset_left = 8
		p.offset_right = vs.x - 8.0
		p.offset_top = 96
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	_title = Wow.title("", 15, Wow.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_title)
	var skip := Button.new()
	skip.text = Tx.s("Skip lesson")
	skip.focus_mode = Control.FOCUS_NONE
	skip.add_theme_font_size_override("font_size", 12)
	skip.pressed.connect(func(): end(false))
	h.add_child(skip)
	_body = Wow.label("", 16, Wow.WHITE, true)
	_body.custom_minimum_size = Vector2(0, 52)
	v.add_child(_body)

func _key(id: String) -> String:
	if id in Abilities.UTILITY:
		return Keys.label("ab_" + id)
	var i := Game.bar_layout.find(id)
	return Keys.label("ab_%d" % i) if i >= 0 else "?"

func _go(i: int) -> void:
	step = i
	if i >= STEPS.size():
		end(true)
		return
	var s: Dictionary = STEPS[i]
	_need = int(s.get("need", 1))
	_wait = float(s.get("secs", 0.0))
	_kind = ""
	var txt := Tx.s(str(s.text))
	if s.has("key"):
		txt = txt.replace("[%s]", "[%s]" % _key(str(s.key)))
	_title.text = Tx.f("FIRST LESSON  ·  %d / %d", [i + 1, STEPS.size()])
	_body.text = txt
	var me: CombatCore.Unit = wc.me
	me.gcd = 0.0
	me.gas = me.max_gas
	me.cds.clear()
	for k in ["down", "pinned", "exposed"]:
		me.auras.erase(k)
		foe.auras.erase(k)
	# the reads use the plain technique name, as a real roll will: only the step text says the answer
	wc.coach = not s.has("cast")
	match str(s.id):
		"grip", "takedown":
			wc.core.stand_up(foe)
		"escape":
			foe.gpos = "side"
			foe.ptop = false
			wc.core.emit({"t": "position", "e": foe, "pos": "side", "ptop": false, "by": foe, "pts": 0, "move": ""})
		"climb":
			if foe.gpos == "standing" or not foe.ptop:
				foe.gpos = "guard"
				foe.ptop = true
				wc.core.emit({"t": "position", "e": foe, "pos": "guard", "ptop": true, "by": foe, "pts": 0, "move": ""})
		"read_td", "read_pass", "read_sub", "mixed":
			wc.core.stand_up(foe)
			_recast = 2.2
		"finish":
			foe.data["practice"] = false
			foe.gpos = "mount"
			foe.ptop = true
			wc.core.emit({"t": "position", "e": foe, "pos": "mount", "ptop": true, "by": me, "pts": 0, "move": ""})
			foe.hp = 1.0
			wc.core._aura(foe, "worn", 9999.0, me)
			me.grip = 3
	Sfx.play("read", -10.0)

func _process(delta: float) -> void:
	if _over or step < 0 or step >= STEPS.size():
		return
	if not is_instance_valid(npc) or not wc.core.units.has(foe) or wc.me.dead:
		end(false)
		return
	wc.me.gas = wc.me.max_gas
	var s: Dictionary = STEPS[step]
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_go(step + 1)
		return
	if s.has("cast") and foe.cast.is_empty() and not foe.down():
		_recast -= delta
		if _recast <= 0.0:
			_recast = 2.4
			var want := str(s.cast)
			if want == "mixed":
				want = ["base", "frame", "defend"][randi() % 3]
			_kind = want
			wc.core.script_cast(foe, wc.me, want, 4.0 if str(s.cast) != "mixed" else 3.0)
	if str(s.id) == "finish" and foe.hp > 1.0:
		foe.hp = 1.0

func _ev(e: Dictionary) -> void:
	if _over or step < 0 or step >= STEPS.size():
		return
	var s: Dictionary = STEPS[step]
	var u: CombatCore.Unit = e.get("u")
	match str(s.id):
		"grip":
			if str(e.t) == "use" and u == wc.me and str(e.ab.get("id", "")) == "handfight":
				_hit()
		"takedown":
			if str(e.t) == "position" and e.get("by") == wc.me and str(e.pos) != "standing":
				_hit()
		"climb":
			if str(e.t) == "position" and e.get("by") == wc.me and str(e.pos) in ["side", "mount", "back", "half"] and bool(e.ptop):
				_hit()
		"escape":
			if str(e.t) == "position" and e.get("by") == wc.me:
				_hit()
		"read_td", "read_pass", "read_sub", "mixed":
			if str(e.t) == "interrupt" and u == wc.me:
				_hit()
			elif str(e.t) == "miss" and u == wc.me and bool(e.get("whiff", false)):
				_say_wrong()
			elif str(e.t) == "use" and u == foe:
				_say_wrong()

func _say_wrong() -> void:
	var right: String = _kind if _kind in ["base", "frame", "defend"] else ""
	if right == "":
		return
	var verb: String = {"base": "Sprawl / Base", "frame": "Frame", "defend": "Defend"}[right]
	wc._float(wc.player, Tx.f("That one was %s [%s]", [Tx.s(verb), _key(right)]), Color(1.0, 0.6, 0.4), 0.9)
	wc.me.cds.clear()
	_recast = 2.6

func _hit() -> void:
	_need -= 1
	if _need > 0:
		_recast = 1.6
		return
	_wait = 1.1   # a beat to see it land, then the next idea

## The partner tapped (the last step), the player skipped, or the bout ended some other way.
func end(done: bool) -> void:
	if _over:
		return
	_over = true
	wc.coach = false
	if wc.core.event.is_connected(_ev):
		wc.core.event.disconnect(_ev)
	if is_instance_valid(_layer):
		_layer.queue_free()
	if not done and is_instance_valid(npc) and wc.core.units.has(foe):
		wc._finish_bout(npc, foe, true, "", false)
	Game.flags["lesson_done"] = true
	for id in Abilities.LESSON_SET:
		Game.learn_ab(id)
	Game.save_game()
	wc.rebuild_player.call_deferred()
	finished.emit(done)
	queue_free()
