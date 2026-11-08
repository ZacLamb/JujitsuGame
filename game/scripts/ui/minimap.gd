class_name Minimap
extends Control
## WoW-style minimap (corner) and full-zone world map (M). The terrain image is rendered once
## per zone from the world's height/color functions with hillshading; icons are drawn live.

const MAP_RES := 2.0          # metres per map pixel
const MINI_SIZE := 148.0
const MINI_RANGE := 70.0      # metres from the player to the minimap edge

var world: World
var player: Player
var tex: ImageTexture
var big := false              # full-screen world map
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func set_world(w: World, p: Player) -> void:
	world = w
	player = p
	tex = _render_terrain(w)
	queue_redraw()

static func _render_terrain(w: World) -> ImageTexture:
	var n := int(World.HALF * 2 / MAP_RES)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.6, 0.75, -0.3).normalized()
	for iz in n:
		for ix in n:
			var x := -World.HALF + (ix + 0.5) * MAP_RES
			var z := -World.HALF + (iz + 0.5) * MAP_RES
			var h := w.height(x, z)
			var c: Color
			if h < World.WATER_Y + 0.05 or (w.zone == "rio" and h < -1.1):
				c = Color(0.18, 0.42, 0.55)
			else:
				c = w._ground_color(x, z, h)
				var nx := w.height(x - 1.5, z) - w.height(x + 1.5, z)
				var nz := w.height(x, z - 1.5) - w.height(x, z + 1.5)
				var nrm := Vector3(nx, 3.0, nz).normalized()
				var shade := clampf(nrm.dot(light), 0.0, 1.0)
				c = c.darkened(0.25 - shade * 0.25).lightened(maxf(0.0, shade - 0.85) * 0.6)
			img.set_pixel(ix, iz, c)
	return ImageTexture.create_from_image(img)

func toggle_big() -> void:
	big = not big
	mouse_filter = Control.MOUSE_FILTER_STOP if big else Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	if world and is_visible_in_tree():
		queue_redraw()

# ------------------------------------------------------------ drawing
func _mini_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var s := MINI_SIZE if vs.x > 700 else 120.0
	if vs.y > vs.x:   # portrait phones: under the status panel, top-left
		return Rect2(Vector2(14, 270), Vector2(s, s))
	return Rect2(Vector2(vs.x - s - 26, 38), Vector2(s, s))   # top-right, round, like WoW

func _draw() -> void:
	if world == null or player == null or tex == null:
		return
	if big:
		_draw_big()
	else:
		_draw_mini()

## world (x, z) -> point inside rect, centred on c with `range` metres to the edge
func _to_rect(p: Vector3, rect: Rect2, c: Vector2, range_m: float) -> Vector2:
	var rel := (Vector2(p.x, p.z) - c) / range_m
	return rect.get_center() + rel * rect.size * 0.5

func _draw_mini() -> void:
	var r := _mini_rect()
	var pp := player.global_position
	var c := Vector2(pp.x, pp.z)
	# terrain region around the player
	var px := (c + Vector2(World.HALF, World.HALF)) / MAP_RES
	var half := MINI_RANGE / MAP_RES
	var src := Rect2(px - Vector2(half, half), Vector2(half, half) * 2.0)
	var ctr := r.get_center()
	var rad := r.size.x * 0.5
	draw_circle(ctr, rad + 9, Color(0, 0, 0, 0.6))
	# round terrain: a textured polygon with UVs into the zone image
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var ts := Vector2(tex.get_width(), tex.get_height())
	for i in 48:
		var a := TAU * i / 48.0
		var p := ctr + Vector2(cos(a), sin(a)) * rad
		pts.append(p)
		uvs.append((src.position + (p - r.position) / r.size * src.size) / ts)
	draw_colored_polygon(pts, Color.WHITE, uvs, tex)
	_round = true
	_draw_icons(r, c, MINI_RANGE, false)
	_draw_player(ctr, 1.0)
	_round = false
	# bronze bezel
	draw_arc(ctr, rad + 4, 0, TAU, 64, Wow.FRAME, 8.0, true)
	draw_arc(ctr, rad + 8, 0, TAU, 64, Color(0, 0, 0, 0.8), 1.5, true)
	draw_arc(ctr, rad + 1, 0, TAU, 64, Wow.FRAME_HI, 1.5, true)
	var f: Font = Wow.body()
	if f:
		# zone name plate above, clock to the right (like WoW's minimap header)
		var zn: String = Data.ZONES[world.zone].name
		var plate := Rect2(Vector2(ctr.x - 92, r.position.y - 30), Vector2(184, 22))
		var ps := StyleBoxFlat.new()
		ps.bg_color = Color(0.03, 0.03, 0.05, 0.85)
		ps.border_color = Wow.FRAME
		ps.set_border_width_all(1)
		ps.set_corner_radius_all(3)
		draw_style_box(ps, plate)
		draw_string_outline(f, plate.position + Vector2(0, 16), zn, HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, 14, 3, Color(0, 0, 0))
		draw_string(f, plate.position + Vector2(0, 16), zn, HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, 14, Wow.GOLD)
		var ck := "%s  ·  %s" % [Data.zone_levels(world.zone), DayNight.clock_text()]
		draw_string_outline(f, Vector2(r.position.x, r.end.y + 26), ck, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, 3, Color(0, 0, 0))
		draw_string(f, Vector2(r.position.x, r.end.y + 26), ck, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, Wow.PALE)
		var np := ctr + Vector2(0, -rad - 4)
		draw_circle(np, 9, Color(0.08, 0.06, 0.05))
		draw_arc(np, 9, 0, TAU, 20, Wow.FRAME_HI, 1.5, true)
		draw_string(f, np + Vector2(-9, 5), "N", HORIZONTAL_ALIGNMENT_CENTER, 18, 13, Wow.WHITE)

func _draw_big() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.72))
	var s := minf(vs.x, vs.y) - 120.0
	var r := Rect2((vs - Vector2(s, s)) * 0.5 + Vector2(0, 20), Vector2(s, s))
	draw_rect(r.grow(6), Color(0.05, 0.05, 0.05))
	draw_texture_rect(tex, r, false)
	_draw_icons(r, Vector2.ZERO, World.HALF, true)
	var pp := player.global_position
	_draw_player(_to_rect(pp, r, Vector2.ZERO, World.HALF), 1.3)
	draw_rect(r.grow(6), Wow.FRAME, false, 5.0)
	var f := Wow.title_font()
	if f:
		var t := "%s  ·  %s" % [Data.ZONES[world.zone].name.to_upper(), Data.zone_levels(world.zone).to_upper()]
		draw_string_outline(f, Vector2(r.position.x, r.position.y - 16), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 8, Color(0, 0, 0))
		draw_string(f, Vector2(r.position.x, r.position.y - 16), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UiKit.ACCENT)
	var bf := Wow.body()
	if bf:
		var legend := "! quest  ·  ? turn in  ·  dots: fighters  ·  flags: territories (green yours, red under attack)  ·  star: objective  ·  M closes"
		draw_string(bf, Vector2(r.position.x, r.end.y + 30), legend, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 15, UiKit.MUTED)

func _draw_player(at: Vector2, k: float) -> void:
	# arrow points where the character faces; a faint cone shows the camera
	var ry := player.rig.rotation.y
	var fwd := Vector2(-sin(ry), -cos(ry))
	var cy := player.cam_yaw
	var cdir := Vector2(-sin(cy), -cos(cy))
	var cone := PackedVector2Array([at])
	for i in 9:
		cone.append(at + cdir.rotated(-0.5 + i * 0.125) * 46.0 * k)
	draw_colored_polygon(cone, Color(1, 1, 1, 0.13))
	var side := Vector2(-fwd.y, fwd.x)
	var tip := at + fwd * 11.0 * k
	var pts := PackedVector2Array([tip, at - fwd * 7.0 * k + side * 7.0 * k, at - fwd * 3.0 * k, at - fwd * 7.0 * k - side * 7.0 * k])
	draw_colored_polygon(pts, Color(1, 0.88, 0.3))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0), 1.5)

var _round := false

func _clip(p: Vector2, r: Rect2) -> bool:
	if _round:
		return p.distance_to(r.get_center()) < r.size.x * 0.5 - 4.0
	return r.grow(-3).has_point(p)

func _draw_icons(r: Rect2, c: Vector2, range_m: float, labels: bool) -> void:
	var f := Wow.body()
	var plv := Game.player_level()
	# buildings and walls, drawn crisp on top of the soft terrain
	for fp in world.map_footprints:
		var rr: Rect2 = fp[0]
		var a := _to_rect(Vector3(rr.position.x, 0, rr.position.y), r, c, range_m)
		var b := _to_rect(Vector3(rr.end.x, 0, rr.end.y), r, c, range_m)
		var box := Rect2(a, b - a).abs()
		if not r.intersects(box) or (_round and not _clip(box.get_center(), r)):
			continue
		box = box.intersection(r)
		var col: Color = fp[1]
		draw_rect(box, col.lerp(Color(0.85, 0.82, 0.76), 0.35))
		draw_rect(box, Color(0, 0, 0, 0.45), false, 1.0)
	# landmarks (world map only)
	if labels and f:
		for id in Data.landmarks_in(world.zone):
			var lm: Dictionary = Data.LANDMARKS[id]
			var p := _to_rect(lm.pos, r, c, range_m)
			var known := Game.landmarks.has(id)
			var t: String = lm.name if known else "???"
			draw_circle(p, 5, Color(1, 1, 1, 0.8) if known else Color(1, 1, 1, 0.3))
			draw_string_outline(f, p + Vector2(8, 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(0, 0, 0, 0.9))
			draw_string(f, p + Vector2(8, 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1) if known else Color(0.75, 0.75, 0.75))
	# spots: bus, gym boards, drills
	for sp in world.spots:
		var p2 := _to_rect(sp.pos, r, c, range_m)
		if not _clip(p2, r):
			continue
		match str(sp.action):
			"travel_menu", "travel":
				draw_rect(Rect2(p2 - Vector2(6, 4), Vector2(12, 8)), Color(0.98, 0.78, 0.2))
				draw_rect(Rect2(p2 - Vector2(6, 4), Vector2(12, 8)), Color(0, 0, 0), false, 1.5)
				if labels and f:
					draw_string(f, p2 + Vector2(9, 5), "Bus", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.9, 0.5))
			"comp":
				draw_circle(p2, 5, Color(0.85, 0.2, 0.2))
			"daily":
				draw_circle(p2, 4, Color(0.4, 0.8, 1.0))
			"territory":
				var st := Game.territory_state(str(sp.arg))
				var tc: Color = Data.YOUR_ACADEMY_COLOR.lightened(0.3) if st == "held" else (Color(1, 0.3, 0.25) if st == "attacked" else Data.ACADEMY_COLORS.get(Data.TERRITORIES[sp.arg].academy, Color.GRAY))
				draw_line(p2 + Vector2(-3, 7), p2 + Vector2(-3, -8), Color(0, 0, 0), 3.0)
				draw_colored_polygon(PackedVector2Array([p2 + Vector2(-3, -8), p2 + Vector2(7, -5), p2 + Vector2(-3, -1)]), tc)
				draw_polyline(PackedVector2Array([p2 + Vector2(-3, -8), p2 + Vector2(7, -5), p2 + Vector2(-3, -1)]), Color(0, 0, 0), 1.0)
				if labels and f:
					draw_string_outline(f, p2 + Vector2(9, 4), Data.TERRITORIES[sp.arg].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0))
					draw_string(f, p2 + Vector2(9, 4), Data.TERRITORIES[sp.arg].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tc)
	# fighters, colored by difficulty; beaten ones fade
	for id in world.fighters:
		var npc: Npc = world.fighters[id]
		var p3 := _to_rect(npc.global_position, r, c, range_m)
		if not _clip(p3, r):
			continue
		var o: Dictionary = Data.OPPONENTS[id]
		var col := Data.con_color(Data.display_level(float(o.level)), plv)
		if Game.beaten(id):
			col = col.darkened(0.45)
		var boss: bool = o.get("boss", false)
		draw_circle(p3, 6.5 if boss else 4.5, Color(0, 0, 0))
		draw_circle(p3, 5.0 if boss else 3.3, col)
		if labels and f:
			draw_string_outline(f, p3 + Vector2(8, 4), o.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0))
			draw_string(f, p3 + Vector2(8, 4), o.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	# mobs (small dots in their con colour) and vendors (gold coin)
	for e in world.mobs:
		if e.npc == null or not (e.npc as Npc).visible:
			continue
		var pm := _to_rect((e.npc as Npc).global_position, r, c, range_m)
		if not _clip(pm, r):
			continue
		var mc := Data.con_color(Data.display_level(float(e.npc.mob.level)), plv)
		draw_circle(pm, 3.2 if not bool(e.rare) else 5.0, Color(0, 0, 0))
		draw_circle(pm, 2.2 if not bool(e.rare) else 3.8, mc if not bool(e.rare) else Color(0.85, 0.85, 0.95))
	for sp2 in world.spots:
		if str(sp2.action) != "vendor":
			continue
		var pv := _to_rect(sp2.pos, r, c, range_m)
		if not _clip(pv, r):
			continue
		draw_circle(pv, 6, Color(0, 0, 0))
		draw_circle(pv, 4.8, Color(1, 0.8, 0.2))
		if labels and f:
			draw_string_outline(f, pv + Vector2(8, 4), str(sp2.label).trim_prefix("Shop: "), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0))
			draw_string(f, pv + Vector2(8, 4), str(sp2.label).trim_prefix("Shop: "), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.85, 0.35))
	# quest givers
	for g in world.quest_givers:
		var mk := Game.giver_marker(g)
		if mk == "":
			continue
		var p4 := _to_rect(world.quest_givers[g].global_position, r, c, range_m)
		if not _clip(p4, r):
			continue
		var t2 := "?" if mk == "…" else mk
		var qc := Color(0.65, 0.65, 0.65) if mk == "…" else Color(1, 0.85, 0.15)
		var hf := Wow.title_font()
		if hf:
			draw_string_outline(hf, p4 + Vector2(-5, 9), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 6, Color(0, 0, 0))
			draw_string(hf, p4 + Vector2(-5, 9), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, qc)
	# objective star (clamped to the minimap edge like WoW)
	var obj := world.objective_target()
	var p5 := _to_rect(obj, r, c, range_m)
	var inner := r.grow(-10)
	if _round:
		var cc := r.get_center()
		var lim := r.size.x * 0.5 - 10.0
		if p5.distance_to(cc) > lim:
			p5 = cc + (p5 - cc).normalized() * lim
	elif not inner.has_point(p5):
		var ctr := r.get_center()
		var d := p5 - ctr
		var k := minf(absf(inner.size.x * 0.5 / maxf(absf(d.x), 0.001)), absf(inner.size.y * 0.5 / maxf(absf(d.y), 0.001)))
		p5 = ctr + d * minf(k, 1.0)
	var pulse := 1.0 + 0.15 * sin(_t * 5.0)
	_star(p5, 9.0 * pulse, Color(1, 0.85, 0.2))

func _star(at: Vector2, rad: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * PI / 5
		var rr := rad if i % 2 == 0 else rad * 0.45
		pts.append(at + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0), 1.5)
