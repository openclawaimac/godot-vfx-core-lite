@tool
class_name VCLayerPath
extends Node2D
## A textured strip along a path: the effect's `points` option (a polyline,
## e.g. a Line2D's points in global space), or the play_line() segment, or
## `length` px along +X.
##   SCROLL: the texture (chevrons) tiles along the path and scrolls at
##           `scroll_speed` px/s (times the effect speed), e.g. a conveyor belt.
##   PULSE:  a bright head with a fading tail travels from the first point to
##           the last over `life`, e.g. energy along a cable.
## Both ends fade over `end_fade` px. Redrawn every frame (a few quads).

enum Mode { SCROLL, PULSE }

@export var delay := 0.0
@export var life := 1.0
@export var loop := false
@export var mode: Mode = Mode.SCROLL
@export var texture: Texture2D
## Glow drawn at the pulse head (PULSE); null = none.
@export var head_texture: Texture2D
@export var head_size := 3.0
@export var width := 16.0
@export var length := 160.0
## SCROLL: px per texture repeat along the path.
@export var tile := 24.0
@export var scroll_speed := 60.0
## PULSE: tail length in px.
@export var tail := 80.0
@export var end_fade := 10.0
@export var palette_from := 0.0
@export var palette_to := 0.5
@export var brightness := 1.0
@export_range(0.0, 1.0) var tint_strength := 1.0
@export var blend: VCMaterials.Blend = VCMaterials.Blend.ADD
@export var alpha_keys := PackedVector2Array([Vector2(0, 1), Vector2(1, 1)])
## Brightness flicker amount (0 = steady).
@export var flicker := 0.0

const STEP := 12.0

var _effect: VCEffect2D
var _t := 0.0
var _k := 0.0
var _pts := PackedVector2Array()
var _cum := PackedFloat32Array()
var _total := 0.0


func _vc_setup(e: VCEffect2D) -> void:
	_effect = e
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visible = false


func _vc_configure(e: VCEffect2D, _n: int, px: int) -> void:
	VCLayerUtil.style(self, e, blend, VCMaterials.Shade.FLAT, px)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _vc_begin() -> void:
	visible = false


## Path in this layer's space, resampled every STEP px (cumulative lengths in _cum).
func _build_path() -> void:
	var src := PackedVector2Array()
	if _effect.points.size() >= 2:
		var inv := transform.affine_inverse()
		for p in _effect.points:
			src.append(inv * p)
	else:
		var l := _effect.local_line_length()
		src = PackedVector2Array([Vector2.ZERO, Vector2(l if l >= 0.0 else length, 0)])
	_pts.clear()
	_cum.clear()
	_total = 0.0
	_pts.append(src[0])
	_cum.append(0.0)
	for i in range(1, src.size()):
		var a := src[i - 1]
		var b := src[i]
		var d := a.distance_to(b)
		var n := maxi(1, ceili(d / STEP))
		for j in range(1, n + 1):
			_pts.append(a.lerp(b, float(j) / n))
			_total += d / n
			_cum.append(_total)


func _vc_update(t: float, _dt: float) -> void:
	var k := (t - delay) / maxf(life, 0.0001)
	if loop and k >= 0.0:
		k = fposmod(k, 1.0)
	if k < 0.0 or k > 1.0 or _effect.alpha_mul <= 0.0:
		visible = false
		return
	visible = true
	_t = t - delay
	_k = k
	_build_path()
	queue_redraw()


func _color(x: float, a: float) -> Color:
	var c := _effect.layer_color(PackedColorArray(), lerpf(palette_from, palette_to, x), tint_strength)
	var b := brightness * _effect.bright
	if flicker > 0.0:
		b *= 1.0 - flicker * (0.5 + 0.5 * sin(_t * 53.0) * sin(_t * 19.0 + 1.7))
	return Color(c.r * b, c.g * b, c.b * b, c.a * a)


func _draw() -> void:
	if _pts.size() < 2 or _total <= 0.0:
		return
	var a := VCLayerUtil.eval_keys(alpha_keys, _k) * _effect.alpha_mul * _effect.fade_mul()
	var hw := width * 0.5
	var head := (_total + tail) * ease(_k, 0.8) if mode == Mode.PULSE else 0.0
	var scroll := _t * scroll_speed
	# One triangle array for the whole path: a draw call per segment would cost
	# 30+ draw calls on a long belt.
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in range(1, _pts.size()):
		var p0 := _pts[i - 1]
		var p1 := _pts[i]
		var dir := (p1 - p0).normalized()
		var nrm := Vector2(-dir.y, dir.x) * hw
		var s0 := _cum[i - 1]
		var s1 := _cum[i]
		var a0 := a * _edge(s0)
		var a1 := a * _edge(s1)
		if mode == Mode.PULSE:
			a0 *= _tail(head - s0)
			a1 *= _tail(head - s1)
			if a0 <= 0.001 and a1 <= 0.001:
				continue
		var u0 := (s0 - scroll) / tile if mode == Mode.SCROLL else 0.5
		var u1 := (s1 - scroll) / tile if mode == Mode.SCROLL else 0.5
		var c0 := _color(clampf(1.0 - a0, 0.0, 1.0) if mode == Mode.PULSE else 0.0, a0)
		var c1 := _color(clampf(1.0 - a1, 0.0, 1.0) if mode == Mode.PULSE else 0.0, a1)
		var b := pts.size()
		pts.append_array([p0 - nrm, p1 - nrm, p1 + nrm, p0 + nrm])
		cols.append_array([c0, c1, c1, c0])
		uvs.append_array([Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0)])
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	if not idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols, uvs,
			PackedInt32Array(), PackedFloat32Array(), texture.get_rid() if texture != null else RID())
	if mode == Mode.PULSE and head_texture != null and head <= _total + 0.01:
		var hp := _at(head)
		var sz := Vector2(width, width) * head_size
		draw_texture_rect(head_texture, Rect2(hp - sz * 0.5, sz), false, _color(0.0, a * _edge(head)))


func _edge(s: float) -> float:
	if end_fade <= 0.0:
		return 1.0
	return clampf(s / end_fade, 0.0, 1.0) * clampf((_total - s) / end_fade, 0.0, 1.0)


## Tail falloff: 1 at the head (d = 0), 0 at `tail` behind it, 0 ahead of it.
func _tail(d: float) -> float:
	if d < 0.0:
		return 0.0
	return pow(clampf(1.0 - d / maxf(tail, 1.0), 0.0, 1.0), 1.5)


func _at(s: float) -> Vector2:
	for i in range(1, _cum.size()):
		if s <= _cum[i]:
			var f := (s - _cum[i - 1]) / maxf(_cum[i] - _cum[i - 1], 0.0001)
			return _pts[i - 1].lerp(_pts[i], f)
	return _pts[_pts.size() - 1]


func _vc_stop() -> void:
	pass


func _vc_end() -> void:
	visible = false


func vc_base_amount() -> int:
	return 1


func vc_end_time() -> float:
	return delay + life
