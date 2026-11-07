class_name ArrowGlyph
extends Control
## Draws a direction arrow (no font glyph dependency, so it renders on every platform).

var dir := "up"
var color := Color.WHITE

static func make(d: String, sz: float, c := Color.WHITE) -> ArrowGlyph:
	var a := ArrowGlyph.new()
	a.dir = d
	a.color = c
	a.custom_minimum_size = Vector2(sz, sz)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return a

func _draw() -> void:
	var s := size
	var c := s / 2.0
	var r := minf(s.x, s.y) * 0.42
	# arrow pointing up, then rotated
	var pts := PackedVector2Array([
		Vector2(0, -r), Vector2(r * 0.85, 0), Vector2(r * 0.32, 0),
		Vector2(r * 0.32, r), Vector2(-r * 0.32, r), Vector2(-r * 0.32, 0), Vector2(-r * 0.85, 0)])
	var ang: float = {"up": 0.0, "right": PI / 2, "down": PI, "left": -PI / 2}[dir]
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + p.rotated(ang))
	draw_colored_polygon(out, color)
