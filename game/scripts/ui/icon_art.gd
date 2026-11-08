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
	if not _cache.has(key):
		var p := DIR + key + ".png"
		_cache[key] = load(p) if ResourceLoader.exists(p) else null
	return _cache[key]

## Key for an ability dictionary: its id (base/frame/...), else its type.
static func ability_key(a: Dictionary) -> String:
	var id := str(a.get("id", ""))
	if tex(id) != null:
		return id
	return str(a.get("type", ""))

## Key for a technique id from Data.MOVES.
static func move_key(mid: String) -> String:
	return str(Data.MOVES.get(mid, {}).get("type", "")) if Data.MOVES.has(mid) else ""

## Key for a bag item: its id if painted, else its icon, else its kind.
static func item_key(id: String, it: Dictionary) -> String:
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
