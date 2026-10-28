@tool
class_name VCLayerRing
extends Node2D
## Expanding ring drawn as one quad with the vc_ring shader.

@export var delay := 0.0
@export var life := 0.35
@export var radius_from := 8.0
@export var radius_to := 64.0
@export var radius_ease := 0.35
## Half-thickness as a fraction of the radius, over life.
@export var thickness_from := 0.35
@export var thickness_to := 0.04
@export var alpha_keys := PackedVector2Array([Vector2(0, 1), Vector2(0.6, 0.6), Vector2(1, 0)])
@export var palette_from := 0.0
@export var palette_to := 0.6
## Optional neutral palette for this layer (e.g. grey smoke); empty = the effect palette.
@export var own_palette := PackedColorArray()
@export var brightness := 1.0
@export_range(0.0, 1.0) var tint_strength := 1.0
@export_range(0.0, 1.0) var fill := 0.25
@export_range(0.0, 1.0) var breakup := 0.35
## Vertical squash (1 = circle; < 1 reads as a ground ring in side view).
@export var squash := 1.0
## Repeat every `life` (looping effects such as shields); fades on stop.
@export var loop := false
## Screen-space refraction instead of a glowing band (shockwave_distort).
@export var distort := false
## Refraction strength in screen pixels (distort only).
@export var distort_strength := 18.0

var _effect: VCEffect2D
var _mat: ShaderMaterial
var _radius := 0.0
var _k := -1.0
var _tex: Texture2D = preload("res://addons/vfx_core/textures/vc_glow.png")


var _mats := {}


func _vc_setup(e: VCEffect2D) -> void:
	_effect = e
	_use_kind(2 if distort else 0)
	visible = false


## One material per kind, made on first use and kept with this instance.
func _use_kind(kind: int) -> void:
	if not _mats.has(kind):
		_mats[kind] = VCMaterials.new_ring_material(kind)
	_mat = _mats[kind]
	material = _mat


func _vc_configure(e: VCEffect2D, _n: int, px: int) -> void:
	_use_kind(2 if distort else (1 if e.p_light_bg else 0))
	if distort:
		_mat.set_shader_parameter(&"strength", distort_strength)
	_mat.set_shader_parameter(&"pixel_size", float(px))
	_mat.set_shader_parameter(&"fill", fill)
	_mat.set_shader_parameter(&"breakup", breakup)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if px > 0 else CanvasItem.TEXTURE_FILTER_LINEAR
	rotation = e.rng.randf() * TAU if squash >= 0.999 else 0.0


func _vc_begin() -> void:
	visible = false
	_k = -1.0


func _vc_update(t: float, _dt: float) -> void:
	var k := (t - delay) / maxf(life, 0.0001)
	if loop and k >= 0.0:
		k = fposmod(k, 1.0)
	if k < 0.0 or k > 1.0 or _effect.alpha_mul <= 0.0:
		visible = false
		return
	visible = true
	_k = k
	_radius = lerpf(radius_from, radius_to, ease(k, radius_ease))
	_mat.set_shader_parameter(&"thickness", lerpf(thickness_from, thickness_to, k))
	_mat.set_shader_parameter(&"progress", k)
	var c := _effect.layer_color(own_palette, lerpf(palette_from, palette_to, k), tint_strength)
	var b := brightness * _effect.bright
	self_modulate = Color(c.r * b, c.g * b, c.b * b, c.a * VCLayerUtil.eval_keys(alpha_keys, k) * _effect.alpha_mul * _effect.fade_mul())
	queue_redraw()


func _draw() -> void:
	if _k < 0.0:
		return
	var r := _radius
	draw_texture_rect(_tex, Rect2(-r, -r * squash, r * 2.0, r * 2.0 * squash), false)


func _vc_stop() -> void:
	pass


func _vc_end() -> void:
	visible = false
	_k = -1.0


func vc_base_amount() -> int:
	return 1


func vc_end_time() -> float:
	return delay + life
