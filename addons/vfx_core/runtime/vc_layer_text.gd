@tool
class_name VCLayerText
extends Node2D
## Pop-up text (damage numbers): pops in, rises and fades over `life`. Uses
## Godot's built-in fallback font (no bundled font file), with a dark outline
## so it reads on light and dark scenes. The string comes from the `text`
## play option (`VfxCore.play(&"damage_number", pos, {text = "42"})`).

@export var delay := 0.0
@export var life := 0.8
@export var text := "99"
@export var font_size := 30
@export var outline_size := 8
@export var outline_color := Color(0.06, 0.04, 0.05, 0.95)
## Pixels the text rises over its life (local units, before scale).
@export var rise := 56.0
@export var rise_ease := 0.35
## Pop: scale overshoot at the start (1 = none) over `pop_time` of life.
@export var pop := 1.45
@export_range(0.01, 1.0) var pop_time := 0.18
## Random sideways drift (±px over life) so stacked numbers separate.
@export var drift := 18.0
@export var palette_from := 0.0
@export var palette_to := 0.35
@export var brightness := 1.0
@export var alpha_keys := PackedVector2Array([Vector2(0, 1), Vector2(0.6, 1), Vector2(1, 0)])

var _effect: VCEffect2D
var _text := ""
var _drift := 0.0
var _font: Font
var _col := Color.WHITE


func _vc_setup(e: VCEffect2D) -> void:
	_effect = e
	visible = false


func _vc_configure(e: VCEffect2D, _n: int, px: int) -> void:
	_text = e.p_text if e.p_text != "" else text
	_drift = e.rng.randf_range(-drift, drift)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if px > 0 else CanvasItem.TEXTURE_FILTER_LINEAR
	_font = ThemeDB.fallback_font


func _vc_begin() -> void:
	visible = false


func _vc_update(t: float, _dt: float) -> void:
	var k := (t - delay) / maxf(life, 0.0001)
	if k < 0.0 or k > 1.0 or _effect.alpha_mul <= 0.0:
		visible = false
		return
	visible = true
	position = Vector2(_drift * k, -rise * ease(k, rise_ease))
	var s := 1.0
	if k < pop_time:
		var q := k / pop_time
		s = lerpf(0.4, pop, ease(minf(q * 1.6, 1.0), 0.4)) if q < 0.62 else lerpf(pop, 1.0, (q - 0.62) / 0.38)
	if _effect.is_pixel():
		position = position.round()
	scale = Vector2(s, s)
	var c := _effect.palette_color(lerpf(palette_from, palette_to, k))
	var b := brightness * _effect.bright
	_col = Color(minf(c.r * b, 1.0), minf(c.g * b, 1.0), minf(c.b * b, 1.0), 1.0)
	modulate = Color(1, 1, 1, VCLayerUtil.eval_keys(alpha_keys, k) * _effect.alpha_mul)
	queue_redraw()


func _draw() -> void:
	if _font == null or _text == "":
		return
	var w := _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2(-w * 0.5, font_size * 0.36)
	draw_string_outline(_font, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, outline_color)
	draw_string(_font, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _col)


func _vc_stop() -> void:
	pass


func _vc_end() -> void:
	visible = false


func vc_base_amount() -> int:
	return 1


func vc_end_time() -> float:
	return delay + life
