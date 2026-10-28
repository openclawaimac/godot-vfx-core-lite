@tool
class_name VCLayerParticles
extends CPUParticles2D
## Particle layer (CPUParticles2D: identical on Forward+, Mobile,
## Compatibility and web). Set the usual CPUParticles2D fields for motion;
## the fields below drive timing and colour. `amount` is overwritten per play
## from base_amount × intensity.

@export var delay := 0.0
## Particles at intensity 1.
@export var base_amount := 8
@export var blend: VCMaterials.Blend = VCMaterials.Blend.MIX
@export var shade: VCMaterials.Shade = VCMaterials.Shade.FLAT
## In light-background mode, a MIX layer also gets the dark soft rim of the
## LIGHT_BG blend (pale snow, water drops). ADD layers always switch.
@export var rim_on_light := false
## Palette position at birth and at death (0 = hot, 1 = cool).
@export var palette_from := 0.0
@export var palette_to := 1.0
## Alpha over life as (t, alpha) keys.
@export var alpha_keys := PackedVector2Array([Vector2(0, 1), Vector2(1, 0)])
## Optional neutral palette for this layer (e.g. grey smoke); empty = the effect palette.
@export var own_palette := PackedColorArray()
@export var brightness := 1.0
## 0 = ignore the user's colour (e.g. neutral smoke), 1 = fully recoloured.
@export_range(0.0, 1.0) var tint_strength := 1.0
## Random rotation of the whole layer per play, in degrees (±).
@export var angle_jitter := 0.0
## Emit along a segment on +X: the emission rectangle spans play_line()'s
## distance (or `span_length`), e.g. a fire strip.
@export var span_line := false
@export var span_length := 160.0
## Sit at the far end of the line (beam impacts); follows set_line() updates.
@export var anchor_end := false

## Each particle picks one of the three palette colours at random (confetti);
## pair it with a white `own_palette` and tint_strength 0 so the lifetime ramp
## only carries alpha.
@export var random_colors := false

var _effect: VCEffect2D
var _ramp: Gradient
var _init_ramp: Gradient
var _started := false
var _authored_rot := 0.0
var _authored_pos := Vector2.ZERO


func _vc_setup(e: VCEffect2D) -> void:
	_effect = e
	_authored_rot = rotation
	_authored_pos = position
	_ramp = Gradient.new()
	VCLayerUtil.init_ramp(_ramp, alpha_keys)
	color_ramp = _ramp
	emitting = false
	use_fixed_seed = true


func _vc_configure(e: VCEffect2D, n: int, px: int) -> void:
	if n > 0 and amount != n:
		amount = n
	visible = n > 0
	VCLayerUtil.fill_ramp(_ramp, e, own_palette, alpha_keys, palette_from, palette_to, brightness, tint_strength)
	var bl := VCMaterials.Blend.LIGHT_BG if rim_on_light and e.p_light_bg else blend
	VCLayerUtil.style(self, e, bl, shade, px)
	if random_colors:
		if _init_ramp == null:
			_init_ramp = Gradient.new()
			_init_ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
			_init_ramp.offsets = PackedFloat32Array([0.0, 0.34, 0.67])
			_init_ramp.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
		for i in 3:
			_init_ramp.set_color(i, e.palette_color(i * 0.5))
		color_initial_ramp = _init_ramp
	speed_scale = e.p_speed
	seed = e.rng.randi()
	rotation = _authored_rot + deg_to_rad(e.rng.randf_range(-angle_jitter, angle_jitter))
	position = _authored_pos
	if span_line:
		var l := e.local_line_length()
		l = span_length if l < 0.0 else l
		emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		emission_rect_extents.x = maxf(l * 0.5, 1.0)
		position.x = _authored_pos.x + l * 0.5
	_place_end()


func _place_end() -> void:
	if anchor_end and _effect != null:
		var l := _effect.local_line_length()
		position.x = _authored_pos.x + (l if l >= 0.0 else span_length)


func _vc_begin() -> void:
	_started = false
	emitting = false


func _vc_update(t: float, _dt: float) -> void:
	if anchor_end:
		_place_end()
	if not _started and t >= delay and visible:
		_started = true
		restart(true)
		emitting = true


func _vc_stop() -> void:
	emitting = false


func _vc_end() -> void:
	emitting = false
	_started = false


func vc_base_amount() -> int:
	return base_amount


func vc_end_time() -> float:
	if not one_shot:
		return delay + lifetime
	# emission spreads over lifetime * (1 - explosiveness); each particle lives `lifetime`
	return delay + lifetime * (2.0 - explosiveness)
