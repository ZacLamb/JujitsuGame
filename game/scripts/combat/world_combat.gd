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
var pvp: Pvp = null   # live duels (set by Main)
var coop: Coop = null # party dungeons (set by Main)
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
	if npc.mob.has("ally"):
		u = core.add_ally(npc.mob, str(npc.mob.get("role", "dps")), Game.player_level())
	elif not npc.mob.is_empty():
		u = core.add_enemy(npc.mob, kind if kind != "" else "mob")
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
	return npc != null and not npc.mob.is_empty() and not npc.mob.has("ally")

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
	Game.toast.emit(Tx.f("%s squares up!", u.name), Color(1, 0.6, 0.4))

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
	if coop and coop.is_guest():
		var cw := coop.guest_press(slot_id)
		if cw != "" and cw != "gcd":
			_error(cw)
		return
	if pvp and pvp.is_guest():
		var gw := pvp.guest_press(slot_id)
		if gw != "" and gw != "gcd":
			_error(gw)
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
		if npc.mob.has("mirror") or npc.mob.has("remote"):
			_drive_net(npc, u, delta)
		elif u.ally and not u.dead:
			_drive_ally(npc, u, delta)
		elif u.in_combat and not u.dead:
			_traits(npc, u)
			if npc.has_meta("flee_to"):
				_flee(npc, u, delta)
			else:
				_drive_npc(npc, u, delta)
	# a ground fight only lasts while you're tangled up with that one opponent
	var g := _ground_unit()
	if g and not core.puppet and (g != target or g.dead or core.dist(me, g) > 3.2 or not g.in_combat):
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

## Mob personalities in a fight: runners bolt for help at 20%, callers shout for a campmate at 50%.
func _traits(npc: Npc, u: CombatCore.Unit) -> void:
	var tr := str(npc.mob.get("trait", ""))
	if tr == "hunter" and not npc.has_meta("hunter_grip"):
		npc.set_meta("hunter_grip", true)
		u.grip = maxi(u.grip, 2)
	if tr == "caller" and u.pct() < 0.5 and not npc.has_meta("called"):
		npc.set_meta("called", true)
		var f := _campmate(npc, 20.0)
		if f:
			_float(npc, Tx.f("Ô, %s! Help!", str(f.mob.name).split(" ")[0]), Color(1, 0.6, 0.3), 0.8)
			engage_npc(f)
	if tr == "runner" and u.pct() < 0.2 and not npc.has_meta("ran") and u.gpos == "standing":
		var f := _campmate(npc, 30.0)
		npc.set_meta("ran", true)
		if f:
			npc.set_meta("flee_to", f)
			npc.set_meta("flee_t", 4.0)
			u.cast = {}
			_float(npc, "Runs for help!", Color(1, 0.75, 0.3), 0.8)

func _campmate(npc: Npc, radius: float) -> Npc:
	var best: Npc = null
	var bd := radius
	for e in world.mobs:
		var o: Npc = e.npc
		if o == null or o == npc or not is_instance_valid(o) or o.in_combat or not o.visible:
			continue
		if str(o.mob.get("camp", "")) != str(npc.mob.get("camp", "")):
			continue
		var d := o.global_position.distance_to(npc.global_position)
		if d < bd:
			bd = d
			best = o
	return best

func _flee(npc: Npc, u: CombatCore.Unit, delta: float) -> void:
	var f: Npc = npc.get_meta("flee_to")
	var left := float(npc.get_meta("flee_t")) - delta
	npc.set_meta("flee_t", left)
	u.ai_t = 0.5
	if f == null or not is_instance_valid(f) or left <= 0.0 or f.global_position.distance_to(npc.global_position) < 2.5:
		npc.remove_meta("flee_to")
		if f and is_instance_valid(f):
			engage_npc(f)
		return
	var to := f.global_position - npc.global_position
	to.y = 0
	npc.global_position += to.normalized() * CHASE_SPEED * 1.15 * delta
	npc.global_position.y = world.ground_y(npc.global_position.x, npc.global_position.z)
	npc.rig.rotation.y = lerp_angle(npc.rig.rotation.y, atan2(-to.x, -to.z), clampf(delta * 9.0, 0, 1))
	npc.rig.animate_locomotion(delta, 1.0)

## A fighter whose position comes over the network: co-op partners on the host (from their own
## game, via their live-world position) and everything on a co-op guest's screen (snapshots).
func _drive_net(npc: Npc, u: CombatCore.Unit, delta: float) -> void:
	npc.rig.combat_ready = u.in_combat
	if not npc.has_meta("net_pos") or npc.rig.in_action() or u.gpos != "standing":
		npc.rig.animate_locomotion(delta, 0.0)
		return
	var goal: Vector3 = npc.get_meta("net_pos")
	var to := goal - npc.global_position
	to.y = 0
	var d := to.length()
	if d > 12.0:
		npc.global_position = goal   # too far behind: snap
	else:
		npc.global_position += to * clampf(delta * 8.0, 0.0, 1.0)
	npc.global_position.y = world.ground_y(npc.global_position.x, npc.global_position.z)
	var yaw := float(npc.get_meta("net_yaw", npc.rig.rotation.y))
	if u.target != null and not u.target.dead and u.in_combat and d < 0.4:
		var f := u.target.pos - npc.global_position
		if f.length() > 0.05:
			yaw = atan2(-f.x, -f.z)
	npc.rig.rotation.y = lerp_angle(npc.rig.rotation.y, yaw, clampf(delta * 9.0, 0, 1))
	npc.rig.animate_locomotion(delta, clampf(d * 1.5, 0.0, 1.0) if d > 0.08 else 0.0)

## A raid partner: stand around your target (spread out), or follow you between pulls.
func _drive_ally(npc: Npc, u: CombatCore.Unit, delta: float) -> void:
	npc.rig.combat_ready = u.in_combat
	if u.down() or not u.cast.is_empty() or npc.rig.in_action():
		return
	var t := u.target
	var goal: Vector3
	var reach := 1.6
	if t != null and not t.dead and u.in_combat:
		var idx := float(u.id % 5)
		var ang := idx * 1.25
		goal = t.pos + Vector3(sin(ang), 0, cos(ang)) * (1.6 if u.role != "heal" else 5.0)
		reach = 0.4
	else:
		goal = player.global_position + Vector3(sin(u.id * 1.7), 0, cos(u.id * 1.7)) * 2.5
		reach = 1.5
	var to := goal - npc.global_position
	to.y = 0
	var d := to.length()
	var speed := 0.0
	if d > reach:
		npc.global_position += to.normalized() * minf(CHASE_SPEED * 1.1 * delta, d)
		npc.global_position.y = world.ground_y(npc.global_position.x, npc.global_position.z)
		speed = 0.8
	var face := (t.pos - npc.global_position) if (t != null and not t.dead and u.in_combat) else to
	if face.length() > 0.05:
		npc.rig.rotation.y = lerp_angle(npc.rig.rotation.y, atan2(-face.x, -face.z), clampf(delta * 9.0, 0, 1))
	npc.rig.animate_locomotion(delta, speed)

func _drive_npc(npc: Npc, u: CombatCore.Unit, delta: float) -> void:
	var t := u.target
	var home_d: float = (npc.global_position - npc._home).length() if not npc.mob.is_empty() and not npc.mob.has("raid") else 0.0
	if _finishing and t != null and t.dead:
		return   # watching the tap
	if npc.mob.has("raid") and (t == null or t.dead):
		t = core._top_threat(u)
		u.target = t
		if t == null:
			return
	if npc.mob.has("raid") and (t == null or t.dead or core.dist(u, me) > 45.0):
		u.target = me   # raid / dungeon enemies never evade: they come back for the party
		t = me
	elif t == null or t.dead or home_d > npc.camp_radius + LEASH or core.dist(u, me) > 45.0:
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
func _show_position(e: CombatCore.Unit, mv := "", by: CombatCore.Unit = null) -> void:
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
	# the move's arc: a takedown dives and lands, a sweep rolls the top player over, a pass steps
	# around, a back take slides behind (same flavors the roll scene used)
	var tp := str(Data.MOVES.get(mv, {}).get("type", ""))
	var fl := RollPoses.flavor(tp) if tp != "" else {}
	var actor_rig: BodyRig = _rig_of(by) if by else null
	for pair_side in [["top", top_rig], ["bottom", bot_rig]]:
		var rig: BodyRig = pair_side[1]
		var pose: Dictionary = pair[pair_side[0]][0]
		var xf: Transform3D = pair[pair_side[0]][1]
		var parent := rig.get_parent() as Node3D
		var local: Transform3D = parent.global_transform.affine_inverse() * anchor * xf
		if fl.is_empty() or actor_rig == null:
			rig.action([[pose, local, 0.45]], true)
			continue
		var partner: BodyRig = bot_rig if rig == top_rig else top_rig
		var toward: Vector3 = parent.global_transform.basis.inverse() * (partner.global_position - rig.global_position)
		var mid_p := BodyRig.lerp_pose(rig.current_pose(), pose, 0.5)
		var mid_r: Transform3D = rig.current_root().interpolate_with(local, 0.5)
		var res := RollPoses.apply_flavor(mid_p, mid_r, fl.actor if rig == actor_rig else fl.other, toward)
		rig.action([[res[0], res[1], 0.34], [pose, local, 0.46]], true)
	if tp in ["takedown", "sweep"]:
		get_tree().create_timer(0.62).timeout.connect(func():
			player.add_shake(0.75)
			Sfx.play("hit", -1.0, 0.6)
			UiKit.buzz(45))

## A submission being set up: both bodies move part of the way into the finish, so you see the
## armbar / triangle / choke coming (and know to Defend it).
func _show_sub_setup(u: CombatCore.Unit, t: CombatCore.Unit, mv: String) -> void:
	var ar := _rig_of(u)
	var dr := _rig_of(t)
	if ar == null or dr == null or not Data.MOVES.has(mv):
		return
	var e := t if u.player else u
	var pr := RollPoses.sub_pair(mv, e.gpos, true)
	var yaw := _yaw_to(u, t)
	var anchor := Transform3D(Basis(Vector3.UP, yaw + PI), t.pos)
	for side in [[ar, pr.atk], [dr, pr.def]]:
		var rig: BodyRig = side[0]
		var fin: Array = side[1]
		var parent := rig.get_parent() as Node3D
		var local: Transform3D = parent.global_transform.affine_inverse() * anchor * fin[1]
		var p := BodyRig.lerp_pose(rig.current_pose(), fin[0], 0.65)
		var r: Transform3D = rig.current_root().interpolate_with(local, 0.65)
		rig.action([[p, r, 0.5]], true)

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
			_show_position(e.e, str(e.get("move", "")), e.get("by"))
			var mvd: Dictionary = Data.MOVES.get(str(e.get("move", "")), {})
			var pn := _node_of(e.e)
			if pn and str(mvd.get("type", "")) in ["takedown", "sweep", "pass", "back", "advance"]:
				CastFX.slam(world, pn.global_position, {"type": str(mvd.type)})
			var mover := _node_of(e.by)
			if int(e.pts) > 0 and mover:
				_float(mover, "+%d  %s" % [int(e.pts), Data.POSITION_NAMES.get(str(e.pos), "")], Color(0.5, 1.0, 0.6), 0.9)
			elif mover and str(e.pos) != "standing":
				_float(mover, str(Data.POSITION_NAMES.get(str(e.pos), "")), Color(0.8, 0.85, 1.0), 0.7)
			Sfx.play("hit", -6.0, 0.8)
		"use":
			var a: Dictionary = e.ab
			if raid and is_instance_valid(raid):
				raid.on_use(u, a)
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
			var ca: Dictionary = e.get("ab", {})
			var tg: CombatCore.Unit = e.get("target")
			_fx_cast(u, ca, float(e.get("dur", 1.0)), tg)
			if str(ca.get("type", "")) == "sub" and tg and (_grounded(u) or _grounded(tg) or str(Data.MOVES.get(str(ca.get("_mv", "")), {}).get("pos", "")) == "standing"):
				_show_sub_setup(u, tg, str(ca.get("_mv", "")))
				Sfx.play("squeeze", -8.0)
			elif r and not _grounded(u):
				r.action(CombatAnim.squeeze(_yaw_to(u, e.get("target"))), true)
				Sfx.play("squeeze", -10.0)
		"cast_stop":
			_fx_stop(u, false)
			var r := _rig_of(u)
			var eu: CombatCore.Unit = u if not u.player else u.target
			if eu and not eu.player and eu.gpos != "standing" and not u.dead:
				_show_position(eu)   # the submission was defended: back to the position
			elif r and not u.down() and not u.dead and not _grounded(u):
				r.release(CombatAnim.attack("handfight", r.rotation.y))
		"dmg":
			var t: CombatCore.Unit = e.target
			if t.player:
				_last_hit = {"ab": e.ab, "by": u.name}
			var n := _node_of(t)
			_fx_stop(u, true)
			if n and str(e.ab.get("id", "")) != "auto":
				CastFX.impact(world, n.global_position, e.ab, bool(e.crit))
			var col := Color(1, 1, 1)
			if t.player:
				col = Color(1, 0.25, 0.2)
			elif bool(e.crit):
				col = Color(1, 0.85, 0.2)
			var txt := str(int(e.amount)) + ("!" if bool(e.crit) else "")
			if n:
				_float(n, txt, col, 1.35 if bool(e.crit) else 1.0)
			if bool(e.crit) and (u.player or t.player):
				player.add_shake(0.45)
				Sfx.play("hit", -3.0, 1.15)
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
			_fx_stop(u, true)
			if n:
				CastFX.heal(world, n.global_position)
			if n:
				_float(n, "+%d" % int(e.amount), Color(0.3, 1, 0.4))
		"aura":
			if str(e.aura) == "down":
				var r := _rig_of(u)
				if r and not _grounded(u) and not r.action_clip("KnockDown", true):
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
			_fx_stop(e.target, false)
			if n:
				CastFX.interrupted(world, n.global_position)
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

# ------------------------------------------------------------ cast effects (CastFX)
var _cast_fx := {}   # unit id -> rune circle node

func _fx_cast(u: CombatCore.Unit, ab: Dictionary, dur: float, tg: CombatCore.Unit) -> void:
	_fx_stop(u, false)
	var n := _node_of(u)
	if n == null:
		return
	_cast_fx[u.id] = CastFX.cast_start(n, ab, dur)
	if str(ab.get("type", "")) == "sub" and tg:
		var tn := _node_of(tg)
		if tn:
			CastFX.constrict(world, tn.global_position, dur)

func _fx_stop(u, success: bool) -> void:
	if u == null or not _cast_fx.has(u.id):
		return
	CastFX.cast_stop(_cast_fx[u.id], success)
	_cast_fx.erase(u.id)

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
	_fx_stop(by, true)
	var vn := _node_of(victim)
	if vn:
		CastFX.finisher(world, vn.global_position)
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
	if npc and npc.mob.has("raid"):
		_raid_tap(npc, victim)
		return
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
			Game.toast.emit(Tx.f("Revenge! +%d XP", bonus), Color(1, 0.55, 0.3))
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
		Game.toast.emit(Tx.f("+%d XP", xp), Color(0.6, 0.85, 1.0))
	if money > 0:
		Game.toast.emit(Tx.f("Looted R$ %d", money), Color(1, 0.85, 0.3))
	for it in items:
		var info := Loot.item(str(it))
		Game.toast.emit(Tx.f("Looted: %s", str(info.get("name", it))), Loot.color(str(it)))

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

# ------------------------------------------------------------ raids
var raid: Raid = null
signal raid_warning(head: String, sub: String)
signal raid_over(won: bool)

## Starts Covil da Sucuri around `at` (the party spawns, the boss waits for your pull).
func start_raid(at: Vector3, kind := "", humans: Array = []) -> void:
	if raid != null and is_instance_valid(raid):
		return
	raid = Raid.new()
	add_child(raid)
	raid.warning.connect(func(h, sb): raid_warning.emit(h, sb))
	raid.finished.connect(func(won):
		if me.dead:   # co-op: you sat out the end, tapped
			me.dead = false
			me.hp = me.max_hp
			me.gas = me.max_gas
			player.rig.release(CombatAnim.getup(player.rig.rotation.y))
		raid_over.emit(won)
		raid = null)
	var lvl := Game.player_level()
	for h in humans:
		lvl = maxi(lvl, int(h.get("stats", {}).get("lv", 1)))
	raid.start(self, at, lvl, kind if kind != "" else Raid.kind_for_zone(world.zone), humans)
	target = raid.boss

## Somebody in the raid tapped: a partner sits out, a student is done, the boss means victory.
func _raid_tap(npc: Npc, victim: CombatCore.Unit) -> void:
	var vr := npc.rig
	if victim.ally:
		_float(npc, Tx.f("%s tapped!", victim.name), Color(1, 0.5, 0.4), 0.8)
		core.remove(victim)
		_unit_of.erase(npc.get_instance_id())
		_npc_of.erase(victim.id)
		npc.in_combat = false
		if vr:
			vr.release()
		if raid and raid.coop and not raid.over and raid.humans_alive() == 0:
			_raid_wipe()
		return
	if raid and victim == raid.boss:
		Sfx.play("win", -2.0)
		raid.warning.emit("VICTORY!", str(raid.cfg.victory))
		raid.end(true)
		target = null
		core.leave_combat(me)
		return
	core.remove(victim)
	_unit_of.erase(npc.get_instance_id())
	_npc_of.erase(victim.id)
	if target == victim:
		target = raid.boss if raid else null
	npc.in_combat = false
	if vr:
		vr.release()
	get_tree().create_timer(2.5).timeout.connect(func(): if is_instance_valid(npc): npc.queue_free())

func _float_on(u: CombatCore.Unit, text: String, col: Color) -> void:
	var n := _node_of(u)
	if n:
		_float(n, text, col, 0.9)

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
## Co-op: you're out of this run, the party fights on (you watch until it ends).
func _sit_out() -> void:
	core.leave_combat(me)
	me.auras.clear()
	me.cast = {}
	me.grip = 0
	me.dead = true
	me.hp = 0.0
	target = null
	Game.toast.emit("You tapped. Your party fights on: hang in there.", Color(1, 0.6, 0.4))

## Everyone real is out: the whole party resets, nobody loses anything but pride.
func _raid_wipe() -> void:
	raid.warning.emit("WIPE", str(raid.cfg.wipe))
	raid.end(false)
	core.leave_combat(me)
	me.auras.clear()
	me.grip = 0
	me.dead = false
	me.hp = me.max_hp
	me.gas = me.max_gas
	target = null
	player.rig.release(CombatAnim.getup(player.rig.rotation.y))

func _player_tapped(by_name: String, winner: Npc = null) -> void:
	if coop and coop.is_guest():
		_sit_out()
		return
	if raid != null and is_instance_valid(raid) and not raid.over:
		if raid.coop and raid.humans_alive() > 0:
			_sit_out()
			return
		_raid_wipe()
		return
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
			return Keys.fill("Coach: \"Their %s has a cast bar under their name. Hit R to Frame it before it lands.\"") % Tx.s(str(ab.get("name", "submission")))
		"takedown", "sweep":
			return Keys.fill("Coach: \"When they put you Down, Escape (it works while you're Down) and get your base back.\"")
		"pass":
			return Keys.fill("Coach: \"Pinned means you hit softer. Escape breaks the pin; Base (Q) halves the damage while you work.\"")
	if core.engaged_enemies().size() > 1:
		return Keys.fill("Coach: \"Too many at once. Pull one at a time, and press Base (Q) the moment it gets ugly.\"")
	return Keys.fill("Coach: \"Build Grip before you go for the finish, and don't be afraid of Base (Q) and Breathe (F).\"")

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
