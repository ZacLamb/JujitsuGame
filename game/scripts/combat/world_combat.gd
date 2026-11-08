class_name WorldCombat
extends Node
## Runs CombatCore in the open world: mobs and named fighters become units, chase and fight you
## where you stand (several at once), and every core event becomes animation, floating combat
## text and sound. Owned by Main; the HUD polls `core` for frames / action bar.

signal player_tapped(by_name: String)
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
		me.max_hp = (140.0 + 18.0 * me.level) * float(mods.get("hp_mult", 1.0))
		me.max_gas = float(mods.get("stamina_max", 100.0))
		me.gas_regen = 15.0 * float(mods.get("regen", 1.0))
		me.dmg = CombatCore.dmg_scale(me.level)
		me.auto_dmg = me.dmg * 0.8
		me.abilities = Abilities.player_kit()
	me.hp = me.max_hp * ratio
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
			var a: Dictionary = me.abilities[i] if i < me.abilities.size() else {}
			press(str(a.get("id", "")) if not a.is_empty() else "")
			get_viewport().set_input_as_handled()
			return
	for k in ["base", "frame", "breathe"]:
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
	core.tick(delta)
	if target and (target.dead and npc_of(target) == null or not core.units.has(target)):
		target = null
	# face your target while standing and fighting
	if me.in_combat and target and not target.dead and not player.rig.in_action():
		var hv := Vector2(player.velocity.x, player.velocity.z).length()
		if hv < 0.3:
			var to := target.pos - player.global_position
			player.rig.rotation.y = lerp_angle(player.rig.rotation.y, atan2(-to.x, -to.z), clampf(delta * 10.0, 0, 1))
	player.rig.combat_ready = me.in_combat
	player.rooted = me.down() or _finishing

func _drive_npc(npc: Npc, u: CombatCore.Unit, delta: float) -> void:
	var t := u.target
	var home_d: float = (npc.global_position - npc._home).length() if not npc.mob.is_empty() else 0.0
	if t == null or t.dead or home_d > npc.camp_radius + LEASH or core.dist(u, me) > 45.0:
		_evade(npc, u)
		return
	if u.down() or not u.cast.is_empty() or npc.rig.in_action():
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
func _evade(npc: Npc, u: CombatCore.Unit) -> void:
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
	_float(npc, "Evade", Color(1, 1, 1))
	if not npc.mob.is_empty():
		pass
	elif npc.opp_id != "":
		_end_duel(npc, u, false, true)
	if core.engaged_enemies().is_empty():
		core.leave_combat(me)

# ------------------------------------------------------------ events -> visuals
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
		"use":
			var a: Dictionary = e.ab
			var r := _rig_of(u)
			if r and not u.down():
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
			if r:
				r.action(CombatAnim.squeeze(_yaw_to(u, e.get("target"))), true)
				Sfx.play("squeeze", -10.0)
		"cast_stop":
			var r := _rig_of(u)
			if r and not u.down() and not u.dead:
				r.release(CombatAnim.attack("handfight", r.rotation.y))
		"dmg":
			var t: CombatCore.Unit = e.target
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
			if tr and not tr.in_action() and not t.down() and not t.dead:
				tr.action(CombatAnim.recoil(tr.rotation.y))
			if str(e.ab.get("id", "")) == "auto":
				var ar := _rig_of(u)
				if ar and not ar.in_action() and not u.down():
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
				if r:
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
				if r:
					r.release(CombatAnim.getup(r.rotation.y))
		"interrupt":
			var n := _node_of(e.target)
			if n:
				_float(n, "Interrupted", Color(0.6, 0.85, 1.0))
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
	l.font_size = int(54 * size)
	l.pixel_size = 0.006
	l.outline_size = 12
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
	await get_tree().create_timer(2.1).timeout
	Sfx.play("lose" if victim.player else "win", -6.0)
	if ar:
		ar.release(CombatAnim.getup(ar.rotation.y))
	_finishing = false
	if victim.player:
		_player_tapped(by_name)
		return
	var npc := npc_of(victim)
	if npc == null:
		core.remove(victim)
		return
	if vr:
		vr.release()
	npc.in_combat = false
	npc.rig.combat_ready = false
	if not npc.mob.is_empty():
		var loot := Game.record_mob({"won": true, "by_sub": true, "sub": sub_id}, npc.mob)
		_reward_toasts(int(loot.xp), int(loot.money), loot.items)
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

## You tapped: no XP. Back on your feet at the zone's spawn with half Composure; fights reset.
func _player_tapped(by_name: String) -> void:
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
				_evade(npc, u)
	core.leave_combat(me)
	me.dead = false
	me.hp = me.max_hp * 0.5
	me.auras.clear()
	me.grip = 0
	target = null
	player.rig.release()
	world.aggro_grace = 10.0
	player_tapped.emit(by_name)
