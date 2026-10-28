@tool
class_name VCLayerSprite
extends Sprite2D
## A single animated sprite: flashes, glows, flame tongues. Scale, alpha and
## colour are keyed over `life` (no AnimationPlayer).

@export var delay := 0.0
@export var life := 0.2
@export var scale_from := Vector2(0.3, 0.3)
@export var scale_to := Vector2(1.0, 1.0)
## Godot ease() curve for the scale: < 0 in-out, 0..1 ease-out, > 1 ease-in.
@export var scale_ease := 0.4
@export var alpha_keys := PackedVector2Array([Vector2(0, 1), Vector2(1, 0)])
@export var palette_from := 0.0
@export var palette_to := 0.5
@export var blend: VCMaterials.Blend = VCMaterials.Blend.ADD
@export var shade: VCMaterials.Shade = VCMaterials.Shade.FLAT
## Optional neutral palette for this layer (e.g. grey smoke); empty = the effect palette.
@export var own_palette := PackedColorArray()
@export var brightness := 1.0
@export_range(0.0, 1.0) var tint_strength := 1.0
## Random rotation per play, degrees (±).
@export var angle_jitter := 0.0
## Random scale variation per play (fraction).
@export var scale_jitter := 0.0
## Brightness flicker amount (0 = steady).
@export var flicker := 0.0
## Counts as particles for the budget (a sprite is one quad).
@export var budget_weight := 1
## Repeat the scale/alpha cycle every `life` seconds (looping effects); fades
## out over the effect's stop_fade after stop().
@export var loop := false
## Sit at the far end of play_line()'s segment (beam impact glow).
@export var anchor_end := false
## Constant rotation in degrees per second (rune circles, shields).
@export var spin := 0.0
@export var end_length := 160.0
## Local offset travelled over `life` (a rising "+", a sweeping shine).
@export var move := Vector2.ZERO
@export var move_ease := 0.4

var _effect: VCEffect2D
var _authored_rot := 0.0
var _rot := 0.0
var _sj := 1.0
var _fl_seed := 0.0
var _authored_pos := Vector2.ZERO


func _vc_setup(e: VCEffect2D) -> void:
	_effect = e
	_authored_rot = rotation
	_authored_pos = position
	visible = false


func _vc_configure(e: VCEffect2D, _n: int, px: int) -> void:
	VCLayerUtil.style(self, e, blend, shade, px)
	_rot = _authored_rot + deg_to_rad(e.rng.randf_range(-angle_jitter, angle_jitter))
	_sj = 1.0 + e.rng.randf_range(-scale_jitter, scale_jitter)
	_fl_seed = e.rng.randf() * 100.0


func _vc_begin() -> void:
	visible = false
	rotation = _rot


func _vc_update(t: float, _dt: float) -> void:
	var k := (t - delay) / maxf(life, 0.0001)
	if loop and k >= 0.0:
		k = fposmod(k, 1.0)
	if anchor_end:
		var l := _effect.local_line_length()
		position.x = _authored_pos.x + (l if l >= 0.0 else end_length)
	if k < 0.0 or k > 1.0 or _effect.alpha_mul <= 0.0:
		visible = false
		return
	visible = true
	if move != Vector2.ZERO and not anchor_end:
		position = _authored_pos + move * ease(k, move_ease)
	if spin != 0.0:
		rotation = _rot + deg_to_rad(spin) * (t - delay)
	scale = scale_from.lerp(scale_to, ease(k, scale_ease)) * _sj
	var c := _effect.layer_color(own_palette, lerpf(palette_from, palette_to, k), tint_strength)
	var a := VCLayerUtil.eval_keys(alpha_keys, k) * _effect.alpha_mul * _effect.fade_mul()
	var b := brightness * _effect.bright
	if flicker > 0.0:
		b *= 1.0 - flicker * (0.5 + 0.5 * sin(t * 61.0 + _fl_seed) * sin(t * 23.0 + _fl_seed * 2.0))
	self_modulate = Color(c.r * b, c.g * b, c.b * b, c.a * a)


func _vc_stop() -> void:
	pass


func _vc_end() -> void:
	visible = false


func vc_base_amount() -> int:
	return budget_weight


func vc_end_time() -> float:
	return delay + life
