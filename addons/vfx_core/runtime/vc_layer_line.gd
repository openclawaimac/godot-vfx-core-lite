@tool
class_name VCLayerLine
extends Line2D
## A streak along the effect's +X axis: tracer, beam or slash. With
## VfxCore.play_line() the length is the distance between the two points.

@export var delay := 0.0
@export var life := 0.12
## Length when not driven by play_line().
@export var length := 160.0
## Where the head is (0..1 of length) at the start and end of life.
@export var head_from := 0.15
@export var head_to := 1.0
## Streak length as a fraction of the full length.
@export var streak := 0.45
@export var width_from := 3.0
@export var width_to := 1.0
@export var palette_from := 0.0
@export var palette_to := 0.3
@export var blend: VCMaterials.Blend = VCMaterials.Blend.ADD
@export var brightness := 1.0
@export_range(0.0, 1.0) var tint_strength := 1.0
@export var alpha_keys := PackedVector2Array([Vector2(0, 1), Vector2(1, 0)])
@export var start_offset := 0.0
## Repeat every `life` (looping beams); fades with the effect's stop_fade.
@export var loop := false
## Width flicker for beams (0 = steady).
@export var flicker := 0.0

var _effect: VCEffect2D
var _grad: Gradient
var _len := 0.0


func _vc_setup(e: VCEffect2D) -> void:
	_effect = e
	_grad = Gradient.new()
	_grad.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	_grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.8), Color.WHITE])
	gradient = _grad
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	clear_points()
	add_point(Vector2.ZERO)
	add_point(Vector2.ZERO)
	visible = false


func _vc_configure(e: VCEffect2D, _n: int, px: int) -> void:
	VCLayerUtil.style(self, e, blend, VCMaterials.Shade.FLAT, px)
	# play_line distances are global; undo the effect's scale
	_len = _target_len(e)
	var hot := e.palette_color(palette_from, tint_strength)
	var cool := e.palette_color(palette_to, tint_strength)
	_grad.set_color(0, Color(cool.r, cool.g, cool.b, 0.0))
	_grad.set_color(1, Color(cool.r, cool.g, cool.b, 0.75))
	_grad.set_color(2, Color(hot.r, hot.g, hot.b, 1.0))


func _vc_begin() -> void:
	visible = false


func _vc_update(t: float, _dt: float) -> void:
	var k := (t - delay) / maxf(life, 0.0001)
	if loop and k >= 0.0:
		k = fposmod(k, 1.0)
	_len = _target_len(_effect)
	if k < 0.0 or k > 1.0 or _effect.alpha_mul <= 0.0:
		visible = false
		return
	visible = true
	var head := start_offset + lerpf(head_from, head_to, ease(k, 0.6)) * (_len - start_offset)
	var tail := maxf(start_offset, head - streak * _len)
	set_point_position(0, Vector2(tail, 0))
	set_point_position(1, Vector2(head, 0))
	width = lerpf(width_from, width_to, k)
	if flicker > 0.0:
		width *= 1.0 - flicker * (0.5 + 0.5 * sin(t * 53.0) * sin(t * 31.0 + 1.3))
	var b := brightness * _effect.bright
	self_modulate = Color(b, b, b, VCLayerUtil.eval_keys(alpha_keys, k) * _effect.alpha_mul * _effect.fade_mul())


func _vc_stop() -> void:
	pass


func _vc_end() -> void:
	visible = false


func vc_base_amount() -> int:
	return 1


func vc_end_time() -> float:
	return delay + life


func _target_len(e: VCEffect2D) -> float:
	var l := e.local_line_length()
	return l if l >= 0.0 else length


## Current end point in the effect's local space (tests use it).
func head_position() -> Vector2:
	return get_point_position(1)


func target_length() -> float:
	return _len
