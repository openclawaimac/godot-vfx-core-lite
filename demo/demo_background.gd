class_name VCDemoBackground
extends Control
## Stage backdrop for the demo browser: a few backgrounds so effects can be
## judged on dark (Night), light (Light), mid and sky scenes, plus a checker for alpha.

enum Kind { NIGHT, LIGHT, DUSK, DAY, CHECKER }

const NAMES := ["Night", "Light", "Dusk", "Day", "Checker"]

var kind := Kind.NIGHT:
	set(v):
		kind = v
		queue_redraw()
## Stage rect and floor height in canvas coordinates (set by the demo).
var stage := Rect2(0, 0, 1280, 720):
	set(v):
		stage = v
		queue_redraw()
var floor_y := 560.0:
	set(v):
		floor_y = v
		queue_redraw()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	match kind:
		Kind.NIGHT:
			_gradient(r, Color(0.075, 0.085, 0.12), Color(0.12, 0.13, 0.18))
			_grid(Color(1, 1, 1, 0.025))
			_floor(Color(0.085, 0.085, 0.11), Color(0.25, 0.27, 0.34, 0.9))
		Kind.LIGHT:
			# pale studio grey: the harshest case for additive glows
			_gradient(r, Color(0.86, 0.855, 0.84), Color(0.79, 0.78, 0.765))
			_grid(Color(0, 0, 0, 0.035))
			_floor(Color(0.68, 0.665, 0.64), Color(0.42, 0.40, 0.37, 1.0))
		Kind.DUSK:
			_gradient(r, Color(0.16, 0.13, 0.24), Color(0.43, 0.27, 0.32))
			_grid(Color(1, 1, 1, 0.03))
			_floor(Color(0.13, 0.09, 0.14), Color(0.62, 0.42, 0.44, 0.9))
		Kind.DAY:
			_gradient(r, Color(0.55, 0.69, 0.82), Color(0.85, 0.88, 0.88))
			_grid(Color(0, 0, 0, 0.03))
			_floor(Color(0.42, 0.38, 0.33), Color(0.30, 0.26, 0.22, 1.0))
		Kind.CHECKER:
			draw_rect(r, Color(0.32, 0.32, 0.34))
			var s := 16.0
			var y := 0.0
			while y < size.y:
				var x := 0.0 if int(y / s) % 2 == 0 else s
				while x < size.x:
					draw_rect(Rect2(x, y, s, s), Color(0.42, 0.42, 0.44))
					x += s * 2.0
				y += s
			draw_line(Vector2(stage.position.x, floor_y), Vector2(stage.end.x, floor_y), Color(1, 1, 1, 0.35), 1.0)


func _gradient(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([top, top, bottom, bottom]))


func _grid(c: Color) -> void:
	var step := 48.0
	var x := stage.position.x
	while x < stage.end.x:
		draw_line(Vector2(x, stage.position.y), Vector2(x, floor_y), c, 1.0)
		x += step
	var y := floor_y
	while y > stage.position.y:
		draw_line(Vector2(stage.position.x, y), Vector2(stage.end.x, y), c, 1.0)
		y -= step


func _floor(fill: Color, edge: Color) -> void:
	var r := Rect2(0, floor_y, size.x, size.y - floor_y)
	draw_rect(r, fill)
	draw_line(Vector2(0, floor_y), Vector2(size.x, floor_y), edge, 2.0)
	# faint ground texture: short dashes
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 90:
		var p := Vector2(rng.randf() * size.x, floor_y + 6.0 + pow(rng.randf(), 1.6) * (size.y - floor_y - 6.0))
		draw_line(p, p + Vector2(4.0 + rng.randf() * 10.0, 0), Color(edge, 0.12), 1.0)
