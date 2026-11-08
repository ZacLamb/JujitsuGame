class_name MoveInfo
extends RefCounted
## WoW-style tooltips for techniques and abilities: what it is, what it costs, what stops it,
## your live odds against this opponent, and where it leaves you. Used by the action bar in a
## roll (live numbers) and by the Journal (reference numbers, no opponent).

const DESC := {
	"double_leg": "Change levels, shoot through both legs and drive them to the mat.",
	"single_leg": "Snatch one leg, run the pipe and finish on top of their half guard.",
	"pull_guard": "Sit to closed guard on your terms. Free, safe, no points.",
	"osoto_gari": "Break their posture back over the heel and reap the leg out. They land hard, you land in side control.",
	"scissor_sweep": "Knee across the belly, shin chops the leg, collar pulls them over.",
	"hip_bump": "Sit up, post a hand and bump them over with your hips.",
	"guard_armbar": "Climb your hips, swing the leg over the head and extend the elbow.",
	"triangle": "Shoot a leg over the neck, lock the figure four and squeeze.",
	"arm_drag_back": "Drag the arm across, climb to the back and sink a hook.",
	"toreando": "Grab the knees, throw the legs to one side and sprint around.",
	"knee_cut_half": "Stand to open the guard and cut a knee through to half.",
	"old_school": "Underhook, grab the ankle and come up on top.",
	"recover_guard": "Frame, swing the leg free and close your guard again.",
	"half_kimura": "Catch the posting arm in a figure four and turn the shoulder.",
	"knee_slice": "Crossface, slide the knee over the thigh and land in side control.",
	"top_kimura": "Trap the arm from the top and crank it behind the back.",
	"mount_up": "Slide the knee across the belly and climb to mount.",
	"americana": "Pin the wrist to the mat and paint the floor with their elbow.",
	"shrimp_guard": "Frame on the neck and hip, shrimp out and put the guard back in.",
	"underhook_half": "Dig an underhook and come to your knees in half guard.",
	"mount_armbar": "Climb high, swing over the head and fall back with the arm.",
	"cross_collar": "Feed the collar deep, cross the second grip and pull the elbows to the mat.",
	"mount_to_back": "When they turn to escape, follow them and take the back.",
	"upa": "Trap an arm and a foot, bridge high and roll them over.",
	"elbow_knee": "Frame, shrimp and slide the knee inside to get half guard back.",
	"rnc": "Arm under the chin, hand to the bicep, squeeze. The classic.",
	"bow_arrow": "Collar grip, catch the leg and pull like a bowstring.",
	"back_escape": "Two-on-one the choking hand, slide down and turn in.",
	"flower_sweep": "Pendulum the leg and pull the arm: they fall straight to mount.",
	"knee_on_belly": "Pop up onto their stomach: heavy, uncomfortable, points.",
	"guillotine": "They shot carelessly: wrap the neck and close the guard.",
	"kimura_guard": "Sit up, catch the wrist and break the grip behind their back.",
	"deep_half": "Get under them, lift the leg and come up behind.",
	"back_armbar": "From the back, fall to the side and pull the arm straight.",
	"straight_ankle": "Sit back with the foot under your armpit and arch.",
	"north_south": "Arm around the neck from north-south, sprawl and squeeze.",
	"mounted_triangle": "From high mount, trap head and arm between your legs.",
	"kneebar": "Isolate the leg and hyper-extend the knee against your hips.",
	"snap_down": "Snap the head down and spin behind for the back.",
	"uchi_mata": "Inner-thigh throw: lift through the legs and launch them.",
	"flying_armbar": "Jump guard straight into the armbar. Spectacular when it works.",
	"omoplata": "Shoulder lock with your legs: sit up and turn it.",
	"berimbolo": "Invert under them and spin to the back.",
	"leg_drag": "Drag the legs across your hip and pin them sideways.",
	"darce": "Arm under the neck and armpit, walk around and squeeze.",
	"ezekiel": "Sleeve choke from mount: the hand rides inside your own gi.",
}

const TYPE_NAMES := {"takedown": "Takedown", "guard": "Guard pull", "sweep": "Sweep", "sub": "Submission",
	"back": "Back take", "pass": "Guard pass", "advance": "Advance", "escape": "Escape"}

## A tooltip panel for an action-bar ability. sim may be null (Journal); pace converts sim seconds
## to real seconds for display.
static func panel(id: String, sim: RollSim = null, pace := 1.0, spec_name := "", signature := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiKit.box(Color(0.03, 0.04, 0.06, 0.96), 10, Color(1, 1, 1, 0.25), 1))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.custom_minimum_size = Vector2(330, 0)
	p.add_child(v)
	var mv: Dictionary = Data.MOVES.get(id, {})
	if mv.is_empty():
		_basic(v, id, sim, pace)
		return p
	var counter := RollSim.counter_kind(id)
	var cc: Color = RollSim.DEF_COLORS[counter]
	v.add_child(_line(str(mv.name), 20, Color.WHITE))
	var sub := "%s  ·  %s" % [TYPE_NAMES.get(str(mv.type), str(mv.type).capitalize()), Data.role_label(str(mv.pos), str(mv.role) == "top") if str(mv.role) != "any" else "Standing"]
	if signature:
		sub += "  ·  Signature"
	if spec_name != "":
		sub += "  ·  " + spec_name
	v.add_child(_line(sub, 13, Color(1, 0.82, 0.3) if signature else UiKit.MUTED))
	# costs row (two columns like WoW)
	var cast := (sim.cast_time(id, true) if sim else 0.7 + 0.14 * float(mv.diff) + (0.15 if mv.type == "sub" else 0.0)) / maxf(pace, 0.1)
	var cost := sim.player_cost(id) if sim else float(mv.cost)
	var cd := 4.0 if mv.type == "sub" else 2.2
	v.add_child(_pair("%.1f sec cast" % cast, "%d stamina" % int(round(cost))))
	var req := RollSim.control_req(id)
	v.add_child(_pair("Needs %d grip%s" % [req, "" if req == 1 else "s"] if req > 0 else "No grips needed", "%.0f sec cooldown" % (cd / maxf(pace, 0.1))))
	# what stops it
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UiKit.box(Color(cc, 0.25), 6, cc, 1))
	chip.add_child(_line(" %s " % RollSim.DEF_NAMES[counter].to_upper(), 12, cc.lightened(0.3)))
	hb.add_child(chip)
	hb.add_child(_line("stops it (they can read you while you cast)", 13, UiKit.MUTED))
	v.add_child(hb)
	# live odds
	if sim:
		var have := sim.control
		var now := sim.technique_chance(id, true, have)
		var full := sim.technique_chance(id, true, RollSim.MAX_CONTROL)
		var col := Color(0.45, 1.0, 0.55) if now >= 0.55 else (Color(1, 0.85, 0.35) if now >= 0.35 else Color(1, 0.5, 0.45))
		v.add_child(_line("Chance right now: %d%%   (with %d grips: %d%%)" % [int(now * 100), RollSim.MAX_CONTROL, int(full * 100)], 15, col))
		var notes: Array = []
		if sim.opp_off_bal > 0.0:
			notes.append("they're off-balance")
		if sim.stamina_pct() < 25.0:
			notes.append("you're gassed")
		if sim.opp_stamina < 25.0:
			notes.append("they're gassed")
		if sim.shield > 0:
			notes.append("Heavy Base up")
		if not notes.is_empty():
			v.add_child(_line("(" + ", ".join(notes) + ")", 12, UiKit.MUTED))
	else:
		v.add_child(_line("Each grip you spend adds about 11% to land it.", 13, UiKit.MUTED))
	# outcome
	var outcome := ""
	if str(mv.type) == "sub":
		outcome = "Locks the submission: mash to finish. Spent grips make it start deeper."
	elif mv.result is Array:
		var r: Array = mv.result
		outcome = "Lands you: %s" % Data.role_label(str(r[0]), bool(r[1]))
		if int(mv.pts) > 0:
			outcome += "   ·   +%d points" % int(mv.pts)
	v.add_child(_line(outcome, 14, Color(0.6, 0.85, 1.0), true))
	v.add_child(_line("\"%s\"" % DESC.get(id, ""), 13, Color(1, 0.86, 0.55), true))
	return p

static func _basic(v: VBoxContainer, id: String, sim: RollSim, pace: float) -> void:
	match id:
		"grip":
			v.add_child(_line("Grip Fight", 20, Color.WHITE))
			v.add_child(_pair("%.1f sec cast" % (0.5 / pace), "2 stamina"))
			v.add_child(_line("+1 Grip Control (+2 while they're off-balance). Techniques spend all your grips: more grips, better odds and deeper submissions.", 14, UiKit.TEXT, true))
			v.add_child(_line("Any counter strips it.", 13, UiKit.MUTED))
		"wear":
			v.add_child(_line("Wear Them Down", 20, Color.WHITE))
			v.add_child(_pair("%.1f sec cast" % (0.75 / pace), "6 stamina"))
			v.add_child(_line("Drains 10 of their stamina and strips one of their grips. Breaks a boss's Heavy Base.", 14, UiKit.TEXT, true))
		"breathe":
			v.add_child(_line("Breathe", 20, Color.WHITE))
			v.add_child(_pair("%.1f sec channel" % (1.4 / pace), "free"))
			v.add_child(_line("Recover 20 stamina. You can't counter while you breathe, so pick your moment.", 14, UiKit.TEXT, true))
		"base", "frame", "defend":
			var c: Color = RollSim.DEF_COLORS[id]
			v.add_child(_line(RollSim.DEF_NAMES[id], 20, c.lightened(0.2)))
			v.add_child(_line({"base": "Stops takedowns and sweeps (orange casts).", "frame": "Stops passes, back takes and escapes (blue casts).", "defend": "Stops submissions (red casts)."}[id], 14, UiKit.TEXT, true))
			v.add_child(_line("Any counter also strips a grip attempt. The wrong counter locks you out briefly.", 13, UiKit.MUTED, true))

static func _line(t: String, size: int, col: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(330, 0)
	return l

static func _pair(a: String, b: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var la := _line(a, 14, UiKit.TEXT)
	la.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(la)
	var lb := _line(b, 14, UiKit.TEXT)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(lb)
	return h
