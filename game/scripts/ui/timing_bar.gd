class_name TimingBar
extends Control
## Ping-pong marker over a bar with a success zone and a perfect zone.

var center := 0.5
var width := 0.25
var perfect := 0.05
var speed := 1.0
var marker := 0.0
var running := false
var _t := 0.0
var flash_color := Color(0, 0, 0, 0)

func start(params: Dictionary) -> void:
	center = params.center
	width = params.width
	perfect = params.perfect
	speed = params.speed
	_t = randf() * 0.3
	running = true
	flash_color = Color(0, 0, 0, 0)
	queue_redraw()

func stop() -> float:
	running = false
	return marker

func _process(delta: float) -> void:
	if running:
		_t += delta * speed
		marker = pingpong(_t, 1.0)
		queue_redraw()
	elif flash_color.a > 0.0:
		flash_color.a = maxf(0.0, flash_color.a - delta * 2.0)
		queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(UiKit.box(Color(0, 0, 0, 0.6), 10, Color(1, 1, 1, 0.2)), r)
	var zx := (center - width * 0.5) * size.x
	draw_rect(Rect2(zx, 4, width * size.x, size.y - 8), Color(0.12, 0.62, 0.36, 0.9))
	var px := (center - perfect) * size.x
	draw_rect(Rect2(px, 4, perfect * 2.0 * size.x, size.y - 8), UiKit.ACCENT)
	var mx := marker * size.x
	draw_rect(Rect2(mx - 3, -6, 6, size.y + 12), Color.WHITE)
	if flash_color.a > 0.0:
		draw_rect(r, flash_color)
