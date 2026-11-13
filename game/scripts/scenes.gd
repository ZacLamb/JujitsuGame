class_name Scenes
extends Node
## The staged moments: the opening, a boss stepping onto the mat, a belt promotion, a new stripe.
## Each is a short Cinema sequence over the live world (no separate scene files). All skippable.

var main: Node            # main.gd
var busy := false
static var force := false   # probes: play scenes even in test mode
var _extras: Array = []   # temporary bodies (students) to clean up
var _frozen: Array = []   # npcs held still for a scene

func _init(m: Node) -> void:
	main = m

func _yaw(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)

func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, main.world.ground_y(p.x, p.z), p.z)

func _begin(fov := 50.0) -> Cinema:
	busy = true
	var c := Cinema.new()
	add_child(c)
	main.player.input_enabled = false
	main.hud.root.visible = false
	c.begin(main.world, func():
		main.player.make_current()
		main.player.input_enabled = true
		main.hud.root.visible = true
		for e in _extras:
			if is_instance_valid(e):
				e.queue_free()
		_extras.clear()
		for n in _frozen:
			if is_instance_valid(n):
				n.in_combat = false
				n.rig.release()
		_frozen.clear()
		busy = false, fov)
	return c

func _hold(npc: Npc) -> void:
	if npc and not npc.in_combat:
		npc.in_combat = true     # Npc stops walking / turning while WorldCombat (or a scene) owns it
		_frozen.append(npc)

## A stand-in body (a student in the line, a professor when the boss isn't around).
func _extra(at: Vector3, yaw: float, gi: Color, belt: Color, skin_t: float, body := "") -> BodyRig:
	var holder := Node3D.new()
	main.world.add_child(holder)
	holder.global_position = _ground(at)
	var rig := BodyRig.new()
	holder.add_child(rig)
	rig.setup(gi, belt, UiKit.skin_tone(skin_t), Color(0.1 + 0.25 * skin_t, 0.07, 0.04), -1, body)
	rig.rotation.y = yaw
	_extras.append(holder)
	return rig

# ------------------------------------------------------------ the opening
## A new character's first minute: where you are, who's waiting, where to go.
func opening() -> void:
	if busy or (Game.test_mode and not force):
		return
	var usa := Game.faction() == "usa"
	var p: Player = main.player
	var pp: Vector3 = p.global_position
	var first := _first_roll_npc()
	var c := _begin(48.0)
	var zd: Dictionary = Data.ZONES.get(Game.zone, {})
	var fwd := Basis(Vector3.UP, p.rig.rotation.y) * Vector3(0, 0, -1)
	# 1. the town from above, drifting down
	c.cut(pp + Vector3(-26, 30, 34), pp + Vector3(0, 2, -10))
	c.move(pp + Vector3(-10, 13, 20), pp + Vector3(0, 1.5, -6), 5.5)
	await c.wait(0.6)
	c.title(Tx.s("TEXAS HILL COUNTRY, USA") if usa else Tx.s("MATO GROSSO, BRAZIL"), str(zd.get("name", "Cáceres")).to_upper(), Color(1.0, 0.86, 0.5))
	await c.wait(3.6)
	c.title_off()
	# 2. you, one bag and a white belt
	c.cut(pp + fwd * 3.4 + Vector3(1.2, 0.9, 0), pp + Vector3(0, 1.25, 0))
	c.move(pp + fwd * 2.4 + Vector3(-0.8, 1.3, 0), pp + Vector3(0, 1.3, 0), 4.0)
	c.say(Tx.s("New town. One bag, a white belt, and nobody here knows your name.") if not usa
		else Tx.s("Home again. One duffel, a white belt, and a garage gym behind the feed store."))
	await c.wait(3.8)
	# 3. the first person who'll roll with you
	if first:
		_hold(first)
		var fp: Vector3 = first.global_position
		first.rig.rotation.y = _yaw(fp, pp)
		var side := Basis(Vector3.UP, first.rig.rotation.y) * Vector3(1, 0, 0)
		var to_me := (pp - fp).normalized()
		c.cut(fp + to_me * 3.2 + side * 1.0 + Vector3(0, 1.1, 0), fp + Vector3(0, 1.3, 0))
		c.move(fp + to_me * 2.3 + side * 0.4 + Vector3(0, 1.35, 0), fp + Vector3(0, 1.35, 0), 4.0)
		first.rig.action(Emotes.frames("wave", first.rig.rotation.y))
		var nm := first.display_name
		c.say((Tx.f("%s: \"Ei, gringo! You train? Come roll. Loser buys the açaí.\"", nm)) if not usa
			else Tx.f("%s: \"Hey, new kid! You train? Come roll. Loser buys the brisket.\"", nm))
		await c.wait(4.0)
		# 4. over your shoulder: that's where you're going
		var back := -fwd
		c.cut(pp + back * 2.6 + Vector3(0.9, 1.9, 0), fp + Vector3(0, 1.0, 0))
		c.move(pp + back * 1.8 + Vector3(0.7, 1.75, 0), fp + Vector3(0, 1.0, 0), 3.0)
		c.say(Tx.s("Follow the golden light. Win rolls, earn your stripes, find the academy."))
		await c.wait(3.2)
	c.say_off()
	await c.end()
	Game.toast.emit(Tx.f("Walk to %s and press [%s] to roll.", [first.display_name if first else "the plaza", Keys.label("interact")]), Color(1, 0.95, 0.8))

## The easiest named fighter in this zone (Rafa in Cáceres).
func _first_roll_npc() -> Npc:
	var best: Npc = null
	var lv := 999.0
	for id in main.world.fighters:
		var o: Dictionary = Data.OPPONENTS.get(id, {})
		var n: Npc = main.world.fighters[id]
		if o.is_empty() or not is_instance_valid(n) or o.get("boss", false):
			continue
		var l := float(o.get("level", 99.0)) - (50.0 if o.get("tutor", false) else 0.0)
		if l < lv:
			lv = l
			best = n
	return best

# ------------------------------------------------------------ a boss steps onto the mat
func boss_entrance(npc: Npc, after: Callable) -> void:
	if busy or (Game.test_mode and not force) or npc == null or not Data.BOSS.has(npc.opp_id):
		after.call()
		return
	var o: Dictionary = Data.OPPONENTS[npc.opp_id]
	var b: Dictionary = Data.BOSS[npc.opp_id]
	var p: Player = main.player
	var bp: Vector3 = npc.global_position
	var pp: Vector3 = p.global_position
	_hold(npc)
	npc.rig.rotation.y = _yaw(bp, pp)
	p.rig.rotation.y = _yaw(pp, bp)
	var to_me := (pp - bp).normalized()
	var side := Vector3(-to_me.z, 0, to_me.x)
	var col: Color = Data.BELTS[Data.belt_of(int(o.rank))].color
	var c := _begin(42.0)
	Sfx.play("squeeze", -6.0, 0.55)
	# low, looking up at them
	c.cut(bp + to_me * 2.1 + side * 0.5 + Vector3(0, 0.45, 0), bp + Vector3(0, 1.5, 0))
	c.move(bp + to_me * 1.5 + side * 0.2 + Vector3(0, 0.6, 0), bp + Vector3(0, 1.55, 0), 3.0)
	npc.rig.action(Emotes.frames("flex", npc.rig.rotation.y))
	c.title(Tx.s(str(o.title)).to_upper(), str(o.name).to_upper(), col.lightened(0.25))
	await c.wait(2.6)
	c.say(Tx.f("Signature: ★ %s ★  Read it and they're wide open. Miss it and it hurts.", str(b.sig_name)))
	# both of you, side on
	var mid := (bp + pp) * 0.5
	c.move(mid + side * 4.2 + Vector3(0, 1.3, 0), mid + Vector3(0, 1.1, 0), 2.2)
	npc.rig.action(Emotes.frames("oss", npc.rig.rotation.y))
	p.rig.action(Emotes.frames("oss", p.rig.rotation.y))
	await c.wait(2.6)
	c.title_off()
	c.say_off()
	await c.end()
	after.call()

# ------------------------------------------------------------ belt promotion
const BELT_LINE := {
	1: "You walked in here a tourist. You leave a blue belt. This one you had to survive for.",
	2: "Purple. Now you stop collecting techniques and start having a game of your own.",
	3: "Brown belt. The details are yours now. Sharpen them until there's nothing left to cut.",
	4: "I'm not giving you this. You took it, one roll at a time. Black belt. Now the real jiu-jitsu starts."}

func promotion(to_belt: int, boss_id: String, old_color: Color) -> void:
	if busy or (Game.test_mode and not force):
		return
	var p: Player = main.player
	var pp: Vector3 = p.global_position
	var belt: Dictionary = Data.BELTS[to_belt]
	var col: Color = belt.color
	var yaw: float = p.rig.rotation.y
	var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	var right := Basis(Vector3.UP, yaw) * Vector3(1, 0, 0)
	var c := _begin(46.0)
	p.rig.release()
	p.rig.set_belt_color(old_color)        # the old belt, until it's tied
	# the professor: the boss you just beat if they're here, otherwise a stand-in
	var prof_pos := pp + fwd * 1.25
	var prof: BodyRig
	var prof_name := Tx.s("Professor")
	var boss: Npc = main._npc_for(boss_id) if boss_id != "" else null
	if boss and boss.global_position.distance_to(pp) < 30.0:
		_hold(boss)
		boss.global_position = _ground(prof_pos)
		boss.rig.release()
		boss.rig.rotation.y = _yaw(prof_pos, pp)
		prof = boss.rig
		prof_name = boss.display_name
	else:
		prof = _extra(prof_pos, _yaw(prof_pos, pp), Color(0.1, 0.1, 0.12), Data.BELTS[4].color, 0.6)
	# the line: students down both sides, facing in
	var students: Array = []
	var gis := [Color(0.95, 0.95, 0.95), Color(0.15, 0.3, 0.75), Color(0.1, 0.1, 0.12), Color(0.95, 0.95, 0.95)]
	for i in 4:
		for s in [-1.0, 1.0]:
			var at: Vector3 = pp + fwd * (0.6 - 1.25 * i + 1.2) + right * (2.3 * s)
			var b_i: int = clampi(to_belt - 1 + (i % 2), 0, 4)
			var r := _extra(at, _yaw(at, pp + fwd * 0.6), gis[(i + int(s > 0)) % gis.size()], Data.BELTS[b_i].color, fposmod(0.17 * i + 0.3 * s, 1.0), "female" if (i + int(s > 0)) % 3 == 0 else "")
			students.append(r)
	Sfx.music("explore")
	# 1. the whole mat
	c.cut(pp + fwd * 0.6 - fwd * 7.5 + Vector3(0, 3.6, 0) + right * 2.0, pp + fwd * 0.6 + Vector3(0, 1.0, 0))
	c.move(pp - fwd * 5.0 + Vector3(0, 2.4, 0) + right * 1.2, pp + fwd * 0.6 + Vector3(0, 1.1, 0), 4.0)
	c.title(Game.player_name.to_upper(), Tx.s("PROMOTION"), Color(1.0, 0.86, 0.5))
	c.say(Tx.f("%s: \"Everybody on the mat. Line up.\"", prof_name))
	await c.wait(3.4)
	c.title_off()
	# 2. face to face
	c.cut(pp + fwd * 0.6 + right * 2.6 + Vector3(0, 1.45, 0), pp + fwd * 0.6 + Vector3(0, 1.2, 0))
	c.move(pp + fwd * 0.6 + right * 2.0 + Vector3(0, 1.4, 0), pp + fwd * 0.6 + Vector3(0, 1.15, 0), 5.0)
	c.say(Tx.f("%s: \"%s\"", [prof_name, Tx.s(str(BELT_LINE.get(to_belt, BELT_LINE[1])))]))
	await c.wait(4.4)
	# 3. the belt goes on
	var tie := {"hip_h": 0.9, "spine": Vector3(-0.45, 0, 0), "neck": Vector3(-0.25, 0, 0),
		"l_sh": Vector3(0.75, 0, 0.25), "r_sh": Vector3(0.75, 0, -0.25), "l_el": Vector3(0.7, 0, 0), "r_el": Vector3(0.7, 0, 0)}
	var tie2 := tie.duplicate()
	tie2["l_el"] = Vector3(1.1, 0, 0)
	tie2["r_el"] = Vector3(0.4, 0, 0)
	var pr := Transform3D(Basis(Vector3.UP, prof.rotation.y), prof.position)
	prof.action([[tie, pr, 0.4], [tie2, pr, 0.35], [tie, pr, 0.35], [tie2, pr, 0.35], [tie, pr, 0.35]], true)
	c.say_off()
	c.move(pp + fwd * 0.6 + right * 1.5 + Vector3(0, 1.15, 0), pp + fwd * 0.3 + Vector3(0, 1.0, 0), 1.8)
	await c.wait(1.8)
	p.rig.set_belt_color(col)
	c.flash(col.lightened(0.4), 0.9)
	Sfx.play("levelup", 0.0)
	Sfx.play("perfect", -4.0)
	CastFX.heal(main.world, pp + Vector3(0, 0.2, 0))
	UiKit.buzz(120)
	c.title(Game.player_name.to_upper(), Tx.f("%s BELT", Tx.s(str(belt.name)).to_upper()), col.lightened(0.15) if col.get_luminance() < 0.25 else col)
	# 4. everyone
	prof.release()
	prof.action(Emotes.frames("oss", prof.rotation.y))
	p.rig.action(Emotes.frames("oss", yaw))
	for i in students.size():
		var r: BodyRig = students[i]
		r.action(Emotes.frames("cheer" if i % 2 == 0 else "flex", r.rotation.y))
	c.move(pp - fwd * 4.2 + Vector3(0, 2.0, 0) - right * 1.6, pp + fwd * 0.5 + Vector3(0, 1.2, 0), 4.5)
	await c.wait(2.2)
	c.say(Tx.s("The whole room: \"OSS!\""))
	for r in students:
		(r as BodyRig).action(Emotes.frames("cheer", (r as BodyRig).rotation.y))
	await c.wait(2.6)
	c.title_off()
	c.say_off()
	p.refresh_look()
	await c.end()
	p.refresh_look()
	# the whole server hears about it
	Net.send_promo(to_belt)
	main.hud.combat_log.add_chat({"ch": "sys", "text": Tx.f("You were promoted to %s Belt. Oss!", Tx.s(str(belt.name)))})

# ------------------------------------------------------------ a new stripe
## Not a cutscene: a beat. You bow, the tape goes on, the belt flashes.
func stripe(rank: int) -> void:
	if busy or (Game.test_mode and not force):
		return
	var p: Player = main.player
	if main.combat.me.in_combat or p.rig.in_action():
		return
	p.rig.action(Emotes.frames("oss", p.rig.rotation.y))
	p.emoting = true
	p.punch(5.0)
	Sfx.play("perfect", -5.0)
	CastFX.heal(main.world, p.global_position + Vector3(0, 0.2, 0))
	main.hud.flash_message(Tx.s("NEW STRIPE"), Data.rank_name(rank))
