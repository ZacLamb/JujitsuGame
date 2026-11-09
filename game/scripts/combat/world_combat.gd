class_name WorldCombat
extends Node
## Runs CombatCore in the open world: mobs and named fighters become units, chase and fight you
## where you stand (several at once), and every core event becomes animation, floating combat
## text and sound. Owned by Main; the HUD polls `core` for frames / action bar.

signal player_tapped(info: Dictionary)
var tap_pending := false     # the "you tapped" choice is open
var _last_hit := {}          # the enemy ability that last hit you (for the coach's note)
signal ability_learned(a: Dictionary)
signal enemy_tapped(npc: Npc, sub: String)

var core := CombatCore.new()
var world: World
var player: Player
var me: CombatCore.Unit
var target: CombatCore.Unit = null
var _unit_of := {}      # Npc instance id -> Unit
var _npc_of := {}       # Unit id -> Npc
var _finishing := false
var error_text := ""
var error_t := 0.0
const LEASH := 26.0
const CHASE_SPEED := 4.2

func setup(w: World, p: Player) -> void:
	world = w
	player = p
	core.event.connect(_on_event)
	rebuild_player()
	Game.progress_changed.connect(rebuild_player)

## Re-reads level, mods and the known moves (called on level-ups, spec / talent / gear changes).
func rebuild_player() -> void:
	var ratio := me.pct() if me else 1.0
	var mods := Game.mods()
	if me == null:
		me = core.add_player(Game.player_name if "player_name" in Game else "You", Game.player_level(), mods, Abilities.player_kit())
	else:
		me.level = Game.player_level()
		me.mods = mods
		me.max_hp = (140.0 + 18.0 * me.level + float(mods.get("hp_flat", 0.0))) * float(mods.get("hp_mult", 1.0))
		me.max_gas = float(mods.get("stamina_max", 100.0))
		me.gas_regen = 15.0 * float(mods.get("regen", 1.0))
		me.dmg = CombatCore.dmg_scale(me.level)
		me.auto_dmg = me.dmg * 0.8
		me.abilities = Abilities.player_kit()
	me.hp = me.max_hp * ratio
	me.known = Abilities.known_moves()
	if Game.style != "":
		for id in Game.ensure_bar(me.abilities):
			var a := core.ability(me, str(id))
			if not a.is_empty():
				ability_learned.emit(a)
	me.name = "You"

func set_world(w: World) -> void:
	for u in core.units.duplicate():
		if not u.player:
			core.remove(u)
	_unit_of.clear()
	_npc_of.clear()
	target = null
	world = w
	if me:
		core.leave_combat(me)
		me.auras.clear()

# ------------------------------------------------------------ units for npcs
func unit_for(npc: Npc, kind := "") -> CombatCore.Unit:
	if npc == null or not is_instance_valid(npc):
		return null
	var key := npc.get_instance_id()
	if _unit_of.has(key):
		return _unit_of[key]
	var u: CombatCore.Unit
	if not npc.mob.is_empty():
		u = core.add_enemy(npc.mob, "mob")
	elif npc.opp_id != "":
		var o: Dictionary = Data.OPPONENTS[npc.opp_id]
		u = core.add_enemy(o, kind if kind != "" else ("boss" if o.get("boss", false) else "named"))
	else:
		return null
	u.pos = npc.global_position
	_unit_of[key] = u
	_npc_of[u.id] = npc
	return u

func npc_of(u: CombatCore.Unit) -> Npc:
	var n = _npc_of.get(u.id if u else -1)
	return n if n != null and is_instance_valid(n) else null

func is_hostile(npc: Npc) -> bool:
	return npc != null and not npc.mob.is_empty()

## A mob noticed you, or you attacked: start fighting.
func engage_npc(npc: Npc) -> void:
	if me == null or me.dead or _finishing or tap_pending:
		return
	if Time.get_ticks_msec() < int(npc.get_meta("no_aggro_until", 0)):
		return   # just evaded: it walks home before it can be pulled again
	var u := unit_for(npc)
	if u == null or u.dead:
		return
	core.engage(u, me)
	u.target = me
	npc.in_combat = true
	npc.rig.combat_ready = true
	if target == null:
		target = u

## A named fighter accepted your challenge: they fight you right here.
func duel(npc: Npc) -> void:
	var u := unit_for(npc)
	if u == null:
		return
	u.dead = false
	u.hp = u.max_hp
	target = u
	engage_npc(npc)
	Game.toast.emit("%s squares up!" % u.name, Color(1, 0.6, 0.4))

func set_target_npc(npc: Npc) -> void:
	target = unit_for(npc)

## Tab: nearest living enemy you're not already targeting.
func target_next() -> void:
	var cands: Array = []
	var stack: Array = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Npc and is_hostile(n) and (n as Npc).visible:
			var d := (n as Npc).global_position.distance_to(player.global_position)
			if d < 30.0:
				cands.append([d, n])
		else:
			stack.append_array(n.get_children())
	if cands.is_empty():
		_error("No enemies nearby")
		return
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var cur := npc_of(target)
	var idx := 0
	for i in cands.size():
		if cands[i][1] == cur:
			idx = (i + 1) % cands.size()
	target = unit_for(cands[idx][1])

# ------------------------------------------------------------ player input
func press(slot_id: String) -> void:
	if me == null or me.dead or _finishing:
		return
	var a := core.ability(me, slot_id)
	if a.is_empty():
		_error("Not learned yet")
		return
	# no target for an attack: grab the nearest enemy in reach
	if bool(a.get("harm", true)) and (target == null or target.dead):
		_auto_target()
	var why := core.use(me, slot_id, target)
	if why == "gcd":
		return
	if why != "":
		_error(why)

func _auto_target() -> void:
	var best: Npc = null
	var bd := 8.0
	var stack: Array = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Npc and is_hostile(n) and (n as Npc).visible:
			var d := (n as Npc).global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = n
		else:
			stack.append_array(n.get_children())
	if best:
		target = unit_for(best)

func _error(t: String) -> void:
	error_text = t
	error_t = 1.6
	Sfx.play("miss", -12.0)

func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.input_enabled:
		return
	for i in 10:
		if event.is_action_pressed("ab_%d" % i):
			var id: String = str(Game.bar_layout[i]) if i < Game.bar_layout.size() else ""
			if id == "":
				_error("Empty slot (drag a move here from your Moves book, P)")
			else:
				press(id)
			get_viewport().set_input_as_handled()
			return
	for k in ["base", "frame", "defend", "breathe", "racial"]:
		if event.is_action_pressed("ab_" + k):
			press(k)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("target_next"):
		target_next()
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if me == null or world == null or player == null:
		return
	error_t = maxf(0.0, error_t - delta)
	me.pos = player.global_position
	for u in core.units.duplicate():
		if u.player:
			continue
		var npc := npc_of(u)
		if npc == null:
			core.remove(u)
			continue
		u.pos = npc.global_position
		if u.in_combat and not u.dead:
			_drive_npc(npc, u, delta)
	# a ground fight only lasts while you're tangled up with that one opponent
	var g := _ground_unit()
	if g and (g != target or g.dead or core.dist(me, g) > 3.2 or not g.in_combat):
		if not _finishing:
			core.stand_up(g)
	core.tick(delta)
	if target and (target.dead and npc_of(target) == null or not core.units.has(target)):
		target = null
	# face your target while standing and fighting
	if me.in_combat and target and not target.dead and not player.rig.in_action() and _ground_unit() == null:
		var hv := Vector2(player.velocity.x, player.velocity.z).length()
		if hv < 0.3:
			var to := target.pos - player.global_position
			player.rig.rotation.y = lerp_angle(player.rig.rotation.y, atan2(-to.x, -to.z), clampf(delta * 10.0, 0, 1))
	player.rig.combat_ready = me.in_combat
	player.rooted = me.down() or _finishing or _ground_unit() != null

func _drive_npc(npc: Npc, u: CombatCore.Unit, delta: float) -> void:
	var t := u.target
	var home_d: float = (npc.global_position - npc._home).length() if not npc.mob.is_empty() else 0.0
	if _finishing and t != null and t.dead:
		return   # watching the tap
	if t == null or t.dead or home_d > npc.camp_radius + LEASH or core.dist(u, me) > 45.0:
		_evade(npc, u)
		return
	if u.down() or not u.cast.is_empty() or npc.rig.in_action() or u.gpos != "standing":
		return
	var to := t.pos - npc.global_position
	to.y = 0
	var d := to.length()
	var speed := 0.0
	if d > 1.5:
		var step := minf(CHASE_SPEED * delta, d - 1.4)
		npc.global_position += to.normalized() * step
		npc.global_position.y = world.ground_y(npc.global_position.x, npc.global_position.z)
		speed = 0.8
	npc.rig.rotation.y = lerp_angle(npc.rig.rotation.y, atan2(-to.x, -to.z), clampf(delta * 9.0, 0, 1))
	npc.rig.animate_locomotion(delta, speed)

## Leashed (you ran away / pulled it too far): it walks home at full health, like WoW evading.
func _evade(npc: Npc, u: CombatCore.Unit, quiet := false) -> void:
	if npc.mob.has("bout"):
		_finish_bout(npc, u, false, "", true)   # you left the mat: forfeit
		return
	if not u.in_combat and not npc.in_combat:
		return   # already evading: say it once
	npc.set_meta("no_aggro_until", Time.get_ticks_msec() + 6000)
	core.leave_combat(u)
	u.hp = u.max_hp
	u.auras.clear()
	u.target = null
	u.grip = 0
	npc.in_combat = false
	npc.rig.combat_ready = false
	npc.rig.release()
	npc._chasing = false
	npc._target = npc._home
	if not quiet:
		_float(npc, "Evade", Color(1, 1, 1))
	if not npc.mob.is_empty():
		pass
	elif npc.opp_id != "":
		_end_duel(npc, u, false, true)
	if core.engaged_enemies().is_empty():
		core.leave_combat(me)

# ------------------------------------------------------------ events -> visuals
## The enemy unit grappling the player on the ground, if any.
func _ground_unit() -> CombatCore.Unit:
	for u in core.units:
		if not u.player and not u.dead and u.gpos != "standing":
			return u
	return null

func _grounded(u: CombatCore.Unit) -> bool:
	if u == null:
		return false
	if u.player:
		return _ground_unit() != null
	return u.gpos != "standing"

## Both bodies go to the position's pair pose, where they are (or stand back up).
func _show_position(e: CombatCore.Unit) -> void:
	var npc := npc_of(e)
	if npc == null:
		return
	var pr := player.rig
	var nr := npc.rig
	if e.gpos == "standing":
		pr.release(CombatAnim.getup(pr.rotation.y))
		nr.release(CombatAnim.getup(nr.rotation.y))
		return
	var pair := RollPoses.get_pair(e.gpos)
	var mid := (player.global_position + npc.global_position) * 0.5
	var to := npc.global_position - player.global_position
	var yaw := atan2(-to.x, -to.z)
	var anchor := Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, world.ground_y(mid.x, mid.z), mid.z))
	var top_rig := pr if e.ptop else nr
	var bot_rig := nr if e.ptop else pr
	for pair_side in [["top", top_rig], ["bottom", bot_rig]]:
		var rig: BodyRig = pair_side[1]
		var pose: Dictionary = pair[pair_side[0]][0]
		var xf: Transform3D = pair[pair_side[0]][1]
		var local: Transform3D = (rig.get_parent() as Node3D).global_transform.affine_inverse() * anchor * xf
		rig.action([[pose, local, 0.45]], true)

func _rig_of(u: CombatCore.Unit) -> BodyRig:
	if u == null:
		return null
	if u.player:
		return player.rig
	var n := npc_of(u)
	return n.rig if n else null

func _node_of(u: CombatCore.Unit) -> Node3D:
	if u == null:
		return null
	return player if u.player else npc_of(u)

func _yaw_to(u: CombatCore.Unit, t: CombatCore.Unit) -> float:
	if t == null:
		var r := _rig_of(u)
		return r.rotation.y if r else 0.0
	var to := t.pos - u.pos
	return atan2(-to.x, -to.z)

func _on_event(e: Dictionary) -> void:
	var u: CombatCore.Unit = e.get("u")
	match str(e.t):
		"position":
			_show_position(e.e)
			var mover := _node_of(e.by)
			if int(e.pts) > 0 and mover:
				_float(mover, "+%d  %s" % [int(e.pts), Data.POSITION_NAMES.get(str(e.pos), "")], Color(0.5, 1.0, 0.6), 0.9)
			elif mover and str(e.pos) != "standing":
				_float(mover, str(Data.POSITION_NAMES.get(str(e.pos), "")), Color(0.8, 0.85, 1.0), 0.7)
			Sfx.play("hit", -6.0, 0.8)
		"use":
			var a: Dictionary = e.ab
			var r := _rig_of(u)
			if r and not u.down() and not _grounded(u) and not _grounded(e.get("target")):
				var kind := str(a.get("type", "handfight"))
				if str(a.get("effect", "")) == "base":
					kind = "base"
				if kind == "sub":
					kind = "handfight"
				r.action(CombatAnim.attack(kind, _yaw_to(u, e.get("target"))))
			if u.player:
				Sfx.play("click", -14.0)
		"cast":
			var r := _rig_of(u)
			if r and not _grounded(u):
				r.action(CombatAnim.squeeze(_yaw_to(u, e.get("target"))), true)
				Sfx.play("squeeze", -10.0)
		"cast_stop":
			var r := _rig_of(u)
			if r and not u.down() and not u.dead and not _grounded(u):
				r.release(CombatAnim.attack("handfight", r.rotation.y))
		"dmg":
			var t: CombatCore.Unit = e.target
			if t.player:
				_last_hit = {"ab": e.ab, "by": u.name}
			var n := _node_of(t)
			var col := Color(1, 1, 1)
			if t.player:
				col = Color(1, 0.25, 0.2)
			elif bool(e.crit):
				col = Color(1, 0.85, 0.2)
			var txt := str(int(e.amount)) + ("!" if bool(e.crit) else "")
			if n:
				_float(n, txt, col, 1.35 if bool(e.crit) else 1.0)
			var tr := _rig_of(t)
			if tr and not tr.in_action() and not t.down() and not t.dead and not _grounded(t):
				tr.action(CombatAnim.recoil(tr.rotation.y))
			if str(e.ab.get("id", "")) == "auto":
				var ar := _rig_of(u)
				if ar and not ar.in_action() and not u.down() and not _grounded(u):
					ar.action(CombatAnim.attack("auto", _yaw_to(u, t)))
				Sfx.play("hit", -16.0, randf_range(0.9, 1.1))
			else:
				Sfx.play("perfect" if bool(e.crit) else "hit", -8.0)
		"heal":
			var n := _node_of(e.target)
			if n:
				_float(n, "+%d" % int(e.amount), Color(0.3, 1, 0.4))
		"aura":
			if str(e.aura) == "down":
				var r := _rig_of(u)
				if r and not _grounded(u):
					r.action(CombatAnim.fall(r.rotation.y), true)
				var n := _node_of(u)
				if n and bool(e.fresh):
					_float(n, "Down!", Color(1, 0.6, 0.2))
			elif bool(e.fresh):
				var n := _node_of(u)
				var names := {"pinned": "Pinned", "exposed": "Exposed", "base": "Base", "guarded": "Guard", "framed": "Framed"}
				if n and names.has(str(e.aura)):
					_float(n, str(names[str(e.aura)]), Color(0.75, 0.8, 1.0), 0.8)
		"aura_off":
			if str(e.aura) == "down" and not u.dead:
				var r := _rig_of(u)
				if r and not _grounded(u):
					r.release(CombatAnim.getup(r.rotation.y))
		"interrupt":
			var n := _node_of(e.target)
			if n:
				_float(n, str(e.get("text", "Interrupted")), Color(0.6, 0.85, 1.0))
		"miss":
			if u.player:
				_error(str(e.get("text", "Missed")))
		"proc":
			var n := _node_of(u)
			if n:
				_float(n, str(e.text), Color(0.4, 1, 0.6))
		"tap":
			_on_tap(u, e.get("by"), str(e.get("sub", "")))
		"combat":
			if u.player:
				if bool(e.on):
					Sfx.music("roll")
				else:
					Sfx.music("explore")

func _float(n: Node3D, text: String, col: Color, size := 1.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Wow.title_font()
	l.fixed_size = true
	l.font_size = int(40 * size)
	l.pixel_size = 0.0008
	l.outline_size = 9
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.top_level = true
	n.add_child(l)
	l.global_position = n.global_position + Vector3(randf_range(-0.35, 0.35), 2.15, randf_range(-0.2, 0.2))
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y + 1.1, 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)

# ------------------------------------------------------------ taps (WoW: the kill)
func _on_tap(victim: CombatCore.Unit, by: CombatCore.Unit, sub: String) -> void:
	_finishing = true
	var gu := victim if not victim.player else by
	if gu:
		gu.gpos = "standing"
	if victim.player:
		world.aggro_grace = 15.0   # nobody else jumps you while you're tapping
	var vr := _rig_of(victim)
	var ar := _rig_of(by)
	var sub_id: String = sub if sub != "" and Data.MOVES.has(sub) else ["guard_armbar", "rnc", "triangle", "kimura"][randi() % 4]
	if not Data.MOVES.has(sub_id):
		sub_id = "guard_armbar"
	# the finish: both bodies go to the submission, the loser taps three times
	if vr and ar:
		var pr := RollPoses.sub_pair(sub_id, "guard", true)
		var yaw := _yaw_to(by, victim)
		var anchor := Transform3D(Basis(Vector3.UP, yaw + PI), victim.pos)
		var a_local: Transform3D = (ar.get_parent() as Node3D).global_transform.affine_inverse() * anchor * pr.atk[1]
		var d_local: Transform3D = (vr.get_parent() as Node3D).global_transform.affine_inverse() * anchor * pr.def[1]
		ar.action([[pr.atk[0], a_local, 0.45]], true)
		var fr: Array = [[pr.def[0], d_local, 0.45]]
		fr.append_array(RollPoses.tap_frames(pr.def[0], d_local))
		vr.action(fr, true)
	Sfx.play("squeeze", -6.0)
	var by_name := by.name if by else "?"
	var winner_npc := npc_of(by) if victim.player else null
	await get_tree().create_timer(2.1).timeout
	Sfx.play("lose" if victim.player else "win", -6.0)
	if ar:
		ar.release(CombatAnim.getup(ar.rotation.y))
	_finishing = false
	if victim.player:
		_player_tapped(by_name, winner_npc)
		return
	var npc := npc_of(victim)
	if npc == null:
		core.remove(victim)
		return
	if vr:
		vr.release()
	npc.in_combat = false
	npc.rig.combat_ready = false
	if npc.mob.has("bout"):
		_finish_bout(npc, victim, true, sub_id)
		if core.engaged_enemies().is_empty():
			core.leave_combat(me)
		return
	if not npc.mob.is_empty():
		var loot := Game.record_mob({"won": true, "by_sub": true, "sub": sub_id}, npc.mob)
		_reward_toasts(int(loot.xp), int(loot.money), loot.items)
		if npc.mob.get("revenge", false):
			var bonus := int(loot.xp) / 2 + 5
			Game.add_xp(bonus)
			Game.toast.emit("Revenge! +%d XP" % bonus, Color(1, 0.55, 0.3))
		core.remove(victim)
		_unit_of.erase(npc.get_instance_id())
		_npc_of.erase(victim.id)
		if target == victim:
			target = null
		world.mob_done(npc, true)
		world.refresh_mob_tags()
	else:
		_end_duel(npc, victim, true, false, sub_id)
	if core.engaged_enemies().is_empty():
		core.leave_combat(me)
	enemy_tapped.emit(npc, sub_id)

func _reward_toasts(xp: int, money: int, items: Array) -> void:
	if xp > 0:
		Game.toast.emit("+%d XP" % xp, Color(0.6, 0.85, 1.0))
	if money > 0:
		Game.toast.emit("Looted R$ %d" % money, Color(1, 0.85, 0.3))
	for it in items:
		var info := Loot.item(str(it))
		Game.toast.emit("Looted: %s" % str(info.get("name", it)), Loot.color(str(it)))

## A named fighter's duel ended (won / lost / walked away).
func _end_duel(npc: Npc, u: CombatCore.Unit, won: bool, walked := false, sub := "") -> void:
	var opp := npc.opp_id
	core.remove(u)
	_unit_of.erase(npc.get_instance_id())
	_npc_of.erase(u.id)
	if target == u:
		target = null
	npc.in_combat = false
	npc.rig.combat_ready = false
	npc.rig.release()
	if walked:
		return
	var xp := Game.record_roll(opp, {"won": won, "by_sub": true, "sub": sub if won else "tap", "signature": false, "min_stamina": 0.0})
	if won:
		_reward_toasts(xp, 0, [])
	npc.refresh_tag()
	duel_over.emit(opp, won)

signal duel_over(opp_id: String, won: bool)

# ------------------------------------------------------------ event bouts (comps, team, daily)
## tag: "comp" / "team" / "daily". info: {sub, gas (0..1), their_hp (0..1), forfeit}
signal bout_over(tag: String, won: bool, info: Dictionary)

## Spawns the opponent on the mat in front of you and starts the fight (real-time, your moves).
func start_bout(opp: Dictionary, tag: String, elite := false) -> Npc:
	var m := opp.duplicate()
	m["mob"] = true
	m["bout"] = tag
	m["elite"] = elite
	m["rare"] = false
	m["aggro"] = false
	m["title"] = str(opp.get("title", "Opponent"))
	for k in ["gi", "skin"]:
		if not m.has(k):
			m[k] = Color(0.95, 0.95, 0.95) if k == "gi" else Color(0.7, 0.5, 0.35)
	if not m.has("rank"):
		m["rank"] = Game.rank
	var fwd := Vector3(sin(player.rig.global_rotation.y), 0, cos(player.rig.global_rotation.y)) if player.rig else Vector3.FORWARD
	var pos: Vector3 = player.global_position + fwd.normalized() * 3.0
	pos.y = world.ground_y(pos.x, pos.z)
	var npc := Npc.new()
	world.add_child(npc)
	npc.setup_mob(m, world, pos, 6.0)
	npc.global_position = pos
	npc._player = player
	npc.wander = false
	var u := unit_for(npc)
	u.hp = u.max_hp
	me.hp = me.max_hp
	me.gas = me.max_gas
	me.grip = 0
	target = u
	engage_npc(npc)
	_float(npc, "FIGHT!", Color(1, 0.85, 0.35), 1.3)
	return npc

func _finish_bout(npc: Npc, u: CombatCore.Unit, won: bool, sub := "", forfeit := false) -> void:
	if npc.has_meta("bout_done"):
		return
	npc.set_meta("bout_done", true)
	var tag := str(npc.mob.bout)
	var info := {"sub": sub, "gas": me.gas / maxf(1.0, me.max_gas), "their_hp": u.pct(), "forfeit": forfeit}
	core.remove(u)
	_unit_of.erase(npc.get_instance_id())
	_npc_of.erase(u.id)
	if target == u:
		target = null
	npc.in_combat = false
	npc.rig.combat_ready = false
	npc.rig.release()
	if won:
		_float(npc, str(npc.mob.get("lose", "Oss.")), Color(0.8, 0.9, 1.0), 0.75)
	else:
		_float(npc, str(npc.mob.get("win", "Oss.")), Color(1, 0.85, 0.5), 0.75)
	get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(npc): npc.queue_free())
	bout_over.emit(tag, won, info)

## You tapped: no XP. Back on your feet at the zone's spawn with half Composure; fights reset.
func _player_tapped(by_name: String, winner: Npc = null) -> void:
	# a competition / team / daily bout: the loss goes to that event, not the open-world tap flow
	var bout_npc: Npc = null
	for u in core.units.duplicate():
		var bn := npc_of(u)
		if bn and bn.mob.has("bout") and u.in_combat:
			bout_npc = bn
			_finish_bout(bn, u, false, "tap")
	if bout_npc != null:
		for u in core.units.duplicate():
			var on := npc_of(u)
			if on and not u.player and u.in_combat:
				_evade(on, u, true)
		core.leave_combat(me)
		me.auras.clear()
		me.grip = 0
		me.dead = false
		me.hp = me.max_hp
		me.gas = me.max_gas
		target = null
		player.rig.release(CombatAnim.getup(player.rig.rotation.y))
		return
	for u in core.units.duplicate():
		if u.player:
			continue
		var npc := npc_of(u)
		if npc and u.in_combat:
			if npc.opp_id != "" and npc.mob.is_empty():
				Game.record_roll(npc.opp_id, {"won": false, "by_sub": true, "sub": "tap"})
				npc.refresh_tag()
				_end_duel(npc, u, false, true)
			else:
				_evade(npc, u, true)
	# the winner gloats, and now you owe them one
	if winner and not winner.mob.is_empty():
		winner.mob["revenge"] = true
		winner.refresh_mob_tag()
		_float(winner, str(winner.mob.get("win", "Next!")), Color(1, 0.85, 0.5), 0.75)
		winner.rig.action([[RollPoses.victory(), winner.rig.current_root(), 0.5], [RollPoses.victory(), winner.rig.current_root(), 1.2]])
	core.leave_combat(me)
	me.auras.clear()
	me.grip = 0
	target = null
	tap_pending = true
	var ab: Dictionary = _last_hit.get("ab", {})
	player_tapped.emit({"by": by_name, "how": str(ab.get("name", "")), "lesson": _lesson(ab)})

## The coach's note after a tap: what got you and how to stop it.
func _lesson(ab: Dictionary) -> String:
	match str(ab.get("type", "")):
		"sub":
			return "Coach: \"Their %s has a cast bar under their name. Hit R to Frame it before it lands.\"" % str(ab.get("name", "submission"))
		"takedown", "sweep":
			return "Coach: \"When they put you Down, Escape (it works while you're Down) and get your base back.\""
		"pass":
			return "Coach: \"Pinned means you hit softer. Escape breaks the pin; Base (Q) halves the damage while you work.\""
	if core.engaged_enemies().size() > 1:
		return "Coach: \"Too many at once. Pull one at a time, and press Base (Q) the moment it gets ugly.\""
	return "Coach: \"Build Grip before you go for the finish, and don't be afraid of Base (Q) and Breathe (F).\""

## The player chose how to come back from a tap.
func resolve_tap(shake_off: bool) -> void:
	tap_pending = false
	me.dead = false
	player.rig.release(CombatAnim.getup(player.rig.rotation.y))
	if shake_off:
		me.hp = me.max_hp * 0.35
		core._aura(me, "rattled", 60.0, me)
	else:
		me.hp = me.max_hp
	me.gas = me.max_gas
	world.aggro_grace = 8.0
