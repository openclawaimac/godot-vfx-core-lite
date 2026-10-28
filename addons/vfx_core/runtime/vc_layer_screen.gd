@tool
class_name VCLayerScreen
extends Node2D
## Full-screen quad for screen effects (flash, vignette, chromatic kick). It
## covers the viewport whatever the camera does: every frame it takes the
## inverse of the viewport's canvas transform. One float uniform (`param`) is
## keyed over `life`; `color_param` gets the palette colour. Draws in the
## world canvas, above world effects and below HUD CanvasLayers.

@export var delay := 0.0
@export var life := 0.25
@export var shader: Shader
@export var param: StringName = &"amount"
@export var param_keys := PackedVector2Array([Vector2(0, 1), Vector2(1, 0)])
@export var color_param: StringName = &"tint"
@export_range(0.0, 1.0) var color_at := 0.0
## Repeat the curve every `life` (loops); fades over stop_fade after stop().
@export var loop := false

var _effect: VCEffect2D
var _mat: ShaderMaterial
var _size := Vector2.ZERO


func _vc_setup(e: VCEffect2D) -> void:
	_effect = e
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	material = _mat
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 8
	z_as_relative = false
	visible = false


func _vc_configure(e: VCEffect2D, _n: int, px: int) -> void:
	if shader == null:
		return
	if color_param != &"":
		_mat.set_shader_parameter(color_param, e.palette_color(color_at))
	_mat.set_shader_parameter(&"light_bg", 1.0 if e.p_light_bg else 0.0)
	_mat.set_shader_parameter(&"pixel_size", float(px))


func _vc_begin() -> void:
	visible = false


func _vc_update(t: float, _dt: float) -> void:
	var k := (t - delay) / maxf(life, 0.0001)
	if loop and k >= 0.0:
		k = fposmod(k, 1.0)
	if k < 0.0 or k > 1.0 or not is_inside_tree():
		visible = false
		return
	visible = true
	var vp := get_viewport()
	global_transform = vp.get_canvas_transform().affine_inverse()
	var s := vp.get_visible_rect().size
	if s != _size:
		_size = s
		queue_redraw()
	# intensity above 1 strengthens the effect (a stronger chromatic split)
	var boost := 1.0 + maxf(_effect.p_intensity - 1.0, 0.0) * 0.6
	_mat.set_shader_parameter(param, VCLayerUtil.eval_keys(param_keys, k) * _effect.alpha_mul * boost * _effect.fade_mul())


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _size), Color.WHITE)


func _vc_stop() -> void:
	pass


func _vc_end() -> void:
	visible = false


func vc_base_amount() -> int:
	return 1


func vc_end_time() -> float:
	return delay + life
