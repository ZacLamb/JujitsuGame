class_name IconArt
extends RefCounted
## Shared icon painter for action buttons, bag items and spellbook entries: a dark metal bevel,
## a radial "lit" background in the icon's colour, a glyph with drop shadow and glow, a gloss
## highlight, and an optional quality-coloured edge (items) or gold ring (ready / proc).

const DIR := "res://assets/icons/"
static var _cache := {}

## Painted icon for a key (ability id/type, item id/icon), or null when there is none.
static func tex(key: String) -> Texture2D:
	if key == "":
		return null
	if key == "racial" and Game.faction() == "usa":
		key = "racial_usa"
	if not _cache.has(key):
		var p := DIR + key + ".png"
		_cache[key] = load(p) if ResourceLoader.exists(p) else null
	return _cache[key]

## Key for an ability dictionary: its id (base/frame/...), else its type.
static func ability_key(a: Dictionary) -> String:
	var id := str(a.get("id", ""))
	if id == "spec" and Game.spec != "" and tex("spec_" + Game.spec) != null:
		return "spec_" + Game.spec   # your signature wears your spec's crest
	if tex(id) != null:
		return id
	return str(a.get("type", ""))

## Key for a technique id from Data.MOVES.
static func move_key(mid: String) -> String:
	return str(Data.MOVES.get(mid, {}).get("type", "")) if Data.MOVES.has(mid) else ""

## Key for a bag item: its id if painted, else its icon, else its kind.
static func item_key(id: String, it: Dictionary) -> String:
	if it.has("gear") and tex(gear_key(str(it.gear))) != null:
		return gear_key(str(it.gear))
	for k in [id, str(it.get("icon", "")), str(it.get("kind", ""))]:
		if tex(k) != null:
			return k
	return ""

static func draw(ci: CanvasItem, r: Rect2, glyph: String, col: Color, edge := Color(0, 0, 0, 0), dim := false, key := "") -> void:
	var c := r.get_center()
	var painted := tex(key)
	if painted != null:
		_draw_painted(ci, r, painted, edge, dim)
		return
	# outer frame: black rim, bronze bevel (light top-left, dark bottom-right)
	ci.draw_rect(r, Color(0.02, 0.02, 0.02, 1.0))
	var f := r.grow(-1.5)
	ci.draw_rect(f, Color(0.42, 0.32, 0.16))
	ci.draw_line(f.position, Vector2(f.end.x, f.position.y), Color(0.85, 0.7, 0.4), 1.5)
	ci.draw_line(f.position, Vector2(f.position.x, f.end.y), Color(0.75, 0.6, 0.32), 1.5)
	ci.draw_line(Vector2(f.position.x, f.end.y), f.end, Color(0.18, 0.12, 0.06), 1.5)
	ci.draw_line(Vector2(f.end.x, f.position.y), f.end, Color(0.18, 0.12, 0.06), 1.5)
	var inner := r.grow(-4.0)
	# radial background: lit centre fading to a dark rim
	var base := col.darkened(0.72)
	ci.draw_rect(inner, base)
	var rad := minf(inner.size.x, inner.size.y) * 0.5
	for k in 6:
		var t := float(k) / 6.0
		ci.draw_circle(c + Vector2(0, -rad * 0.12), rad * (1.05 - t * 0.85), Color(col.darkened(0.55 - t * 0.4), 0.22 + t * 0.06))
	# vignette corners
	ci.draw_rect(inner, Color(0, 0, 0, 0.0))
	# glyph: shadow, glow, body
	var gs := minf(inner.size.x, inner.size.y) * 0.56
	CharSheet.draw_glyph(ci, glyph, c + Vector2(1.5, 2.0), gs, Color(0, 0, 0, 0.7))
	CharSheet.draw_glyph(ci, glyph, c, gs * 1.06, Color(col.lightened(0.5), 0.25))
	CharSheet.draw_glyph(ci, glyph, c, gs, col.lightened(0.45) if not dim else Color(0.55, 0.55, 0.55))
	# gloss on the top half
	var g := PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y),
		Vector2(inner.end.x, inner.position.y + inner.size.y * 0.32), Vector2(inner.position.x, inner.position.y + inner.size.y * 0.48)])
	ci.draw_colored_polygon(g, Color(1, 1, 1, 0.08))
	# inner shadow line
	ci.draw_rect(inner, Color(0, 0, 0, 0.55), false, 1.0)
	if edge.a > 0.0:
		ci.draw_rect(r.grow(-1.0), edge, false, 2.0)
	if dim:
		ci.draw_rect(inner, Color(0, 0, 0, 0.45))

static func _draw_painted(ci: CanvasItem, r: Rect2, t: Texture2D, edge: Color, dim: bool) -> void:
	ci.draw_rect(r, Color(0.02, 0.02, 0.02, 1.0))
	var f := r.grow(-1.5)
	ci.draw_rect(f, Color(0.42, 0.32, 0.16))
	ci.draw_line(f.position, Vector2(f.end.x, f.position.y), Color(0.85, 0.7, 0.4), 1.5)
	ci.draw_line(f.position, Vector2(f.position.x, f.end.y), Color(0.75, 0.6, 0.32), 1.5)
	ci.draw_line(Vector2(f.position.x, f.end.y), f.end, Color(0.18, 0.12, 0.06), 1.5)
	ci.draw_line(Vector2(f.end.x, f.position.y), f.end, Color(0.18, 0.12, 0.06), 1.5)
	var inner := r.grow(-3.0)
	ci.draw_texture_rect(t, inner, false, Color(0.5, 0.5, 0.5) if dim else Color.WHITE)
	ci.draw_rect(inner, Color(0, 0, 0, 0.6), false, 1.0)
	if edge.a > 0.0:
		ci.draw_rect(r.grow(-1.0), edge, false, 2.0)
	if dim:
		ci.draw_rect(inner, Color(0, 0, 0, 0.4))

## Painted texture clipped to a polygon (talent circles / diamonds, round emblems).
static func draw_in_poly(ci: CanvasItem, pts: PackedVector2Array, t: Texture2D, tint := Color.WHITE) -> void:
	var lo := pts[0]
	var hi := pts[0]
	for q in pts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var sz := hi - lo
	var side := maxf(sz.x, sz.y)
	var org := lo + (sz - Vector2(side, side)) / 2.0
	var uvs := PackedVector2Array()
	for q in pts:
		uvs.append((q - org) / side)
	ci.draw_colored_polygon(pts, tint, uvs, t)

## Circle as a polygon.
static func circle(c: Vector2, r: float, n := 40) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		out.append(c + Vector2(cos(TAU * i / n), sin(TAU * i / n)) * r)
	return out

## Painted icon for a talent node: techniques show their move; passives show what they do.
static func talent_key(nd: Dictionary, spec_id := "") -> String:
	var fx: Dictionary = nd.get("fx", {})
	if str(nd.get("kind", "")) == "choice":
		var ch: Array = nd.get("choice", [])
		var pick := Game.talent_rank(str(nd.get("id", ""))) - 1
		if not ch.is_empty():
			fx = ch[clampi(pick, 0, ch.size() - 1)].get("fx", {})
	if bool(nd.get("capstone", false)) or str(nd.get("name", "")) in ["Tap Machine", "Flow State", "Immovable", "Crushing Weight"]:
		return "capstone"
	if str(nd.get("name", "")) == "Mastery" and spec_id != "":
		return "spec_" + spec_id
	if fx.has("move"):
		return move_key(str(fx.move))
	if fx.has("moves"):
		return move_key(str(fx.moves[0]))
	var ad: Dictionary = fx.get("aura_dur", {})
	var dmg: Dictionary = fx.get("ab_dmg", {})
	if fx.has("hp") or fx.has("dr") or ad.has("guarded") or ad.has("base"):
		return "t_tough"
	if fx.has("gas") or fx.has("regen") or fx.has("cost_mult") or fx.has("escape_gas") or fx.has("cost") :
		return "t_lungs"
	if fx.has("haste") or fx.has("haste_sub"):
		return "t_haste"
	if fx.has("crit") or fx.has("sub_crit") or ad.has("exposed"):
		return "t_crit"
	if fx.has("exec") or fx.has("free_sub") or fx.has("instant_sub") or dmg.has("sub"):
		return "t_squeeze"
	if fx.has("pinned_vuln") or fx.has("pin_grip") or ad.has("pinned") or dmg.has("advance") or dmg.has("pass"):
		return "t_pressure"
	if fx.has("down_dmg") or ad.has("down"):
		return "t_offbalance"
	if fx.has("grip_start") or fx.has("auto_grip") or fx.has("grip_bonus") or fx.has("base_grip"):
		return "t_grip"
	if fx.has("cd") or fx.has("scramble"):
		return "t_drill"
	if fx.has("second_wind") or fx.has("tap_heal") or fx.has("tap_gas") or fx.has("tap_reset"):
		return "t_secondwind"
	return "t_damage"

## Photographed gear icon (tools/icon_studio): g_<gear id>.
static func gear_key(gid: String) -> String:
	return "g_" + gid
