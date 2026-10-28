@tool
class_name VCLayerMaterial
extends Node
## Swaps a ShaderMaterial onto VfxCore.apply()'s target CanvasItem for `life`
## seconds, drives one float uniform over time, then restores the target's
## original material. Nested applies on one target restore correctly.

const META_ORIG := &"_vc_orig_material"
const META_COUNT := &"_vc_apply_count"
const META_PEAK := &"_vc_flash_peak"

@export var delay := 0.0
@export var life := 0.2
@export var shader: Shader
## Float uniform animated over life.
@export var param: StringName = &"amount"
@export var param_keys := PackedVector2Array([Vector2(0, 1), Vector2(1, 0)])
## vec4 uniform that receives the effect's hot palette colour ("" = none).
@export var color_param: StringName = &"tint"
## Palette position sent to color_param (0 = hot/white end, 1 = cool end).
@export_range(0.0, 1.0) var color_at := 0.5
## vec4 uniform that receives the palette's cool end (two-tone flashes: a hot
## peak that settles into a tint). "" = none.
@export var tail_param: StringName = &""
## Anti-strobe: a new apply within `rearm` seconds of the last full peak on the
## same target skips the peak and starts at `rearm_skip` of the curve, so rapid
## hits keep a steady tint instead of blinking white. 0 = off.
@export var rearm := 0.0
@export_range(0.0, 1.0) var rearm_skip := 0.3
## Repeat the curve every `life` (status tints, outline pulses); after stop()
## the curve fades out over the effect's stop_fade.
@export var loop := false
## Hide the target when the effect ends (dissolve, burn_away, ghost_fade: the
## sprite is gone). The original material is still restored, so set
## `visible = true` again before reusing a pooled sprite.
@export var hide_at_end := false
## Sent to the shader's `additive` uniform when it has one: 1 = brighten
## (add the tint), 0 = replace toward the tint. Light-background mode always
## uses 0 (an added white is invisible on a pale scene), and so does a
## coloured tint (an added red on a pale sprite clips to white): additive
## only applies while the flash colour is near white.
@export var additive := false
## Fixed shader uniforms set once (e.g. {"pattern": 2, "burn": 1.0}).
@export var shader_params := {}

var _effect: VCEffect2D
var _mat: ShaderMaterial
var _target: CanvasItem
var _on := false
var _k0 := 0.0
var _has_time := false


func _vc_setup(e: VCEffect2D) -> void:
	_effect = e
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_has_time = shader != null and _has_uniform(&"vc_time")
	if shader != null and _has_uniform(&"noise_tex"):
		_mat.set_shader_parameter(&"noise_tex", VCMaterials.NOISE)
	for k in shader_params:
		_mat.set_shader_parameter(StringName(k), shader_params[k])


func _vc_configure(e: VCEffect2D, _n: int, px: int) -> void:
	if color_param != &"":
		_mat.set_shader_parameter(color_param, e.palette_color(color_at))
	if tail_param != &"":
		_mat.set_shader_parameter(tail_param, e.palette_color(1.0))
	if shader != null and _has_uniform(&"outline"):
		_mat.set_shader_parameter(&"outline", 1.0 if e.p_light_bg else 0.0)
	if shader != null and _has_uniform(&"pixel_size"):
		_mat.set_shader_parameter(&"pixel_size", float(px))
	if shader != null and _has_uniform(&"additive"):
		var fc := e.palette_color(color_at)
		var white := minf(fc.r, minf(fc.g, fc.b)) > 0.85
		_mat.set_shader_parameter(&"additive", 1.0 if additive and white and not e.p_light_bg else 0.0)
	if shader != null and _has_uniform(&"seed"):
		_mat.set_shader_parameter(&"seed", e.rng.randf() * 64.0)


func _has_uniform(n: StringName) -> bool:
	for u in shader.get_shader_uniform_list():
		if StringName(u["name"]) == n:
			return true
	return false


func _vc_begin() -> void:
	_on = false
	_target = _effect.apply_target


func _vc_update(t: float, _dt: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = null
		return
	var k := (t - delay) / maxf(life, 0.0001)
	if k < 0.0:
		return
	if loop:
		k = fposmod(k, 1.0)
	if not _on:
		_on = true
		_k0 = 0.0
		var now := _clock()
		if rearm > 0.0 and _target.has_meta(META_PEAK) and now - float(_target.get_meta(META_PEAK)) < rearm:
			_k0 = rearm_skip
		else:
			_target.set_meta(META_PEAK, now)
		if not _target.has_meta(META_ORIG):
			_target.set_meta(META_ORIG, _target.material)
			_target.set_meta(META_COUNT, 0)
		_target.set_meta(META_COUNT, int(_target.get_meta(META_COUNT)) + 1)
		_target.material = _mat
	k = _k0 + k * (1.0 - _k0)
	_mat.set_shader_parameter(param, VCLayerUtil.eval_keys(param_keys, clampf(k, 0.0, 1.0)) * _effect.alpha_mul * _effect.fade_mul())
	if _has_time:
		_mat.set_shader_parameter(&"vc_time", t)


func _vc_stop() -> void:
	pass


func _vc_end() -> void:
	if _on and hide_at_end and _target != null and is_instance_valid(_target) and _effect.time >= _effect.duration - 0.001:
		_target.visible = false
	if _on and _target != null and is_instance_valid(_target):
		var n := int(_target.get_meta(META_COUNT, 1)) - 1
		if n <= 0:
			_target.material = _target.get_meta(META_ORIG, null)
			_target.remove_meta(META_ORIG)
			_target.remove_meta(META_COUNT)
		else:
			_target.set_meta(META_COUNT, n)
			# the newest apply still running keeps its own material on the target
	_on = false
	_target = null


## VfxCore's effect clock (looked up at run time: the build tools run without
## the autoload).
func _clock() -> float:
	var core := get_tree().root.get_node_or_null(^"VfxCore") if is_inside_tree() else null
	return float(core.get(&"clock")) if core != null else 0.0


func vc_base_amount() -> int:
	return 0


func vc_end_time() -> float:
	return delay + life
