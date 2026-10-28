@tool
class_name VCLayerBodies
extends Node2D
## Simulated solid pieces (debris chunks, coins): gravity, spin, bounce on a
## floor, friction, settle and fade. CPUParticles2D has no collision, so this
## layer integrates its own bodies and draws them in one _draw() call. All
## randomness comes from the effect's seeded RNG (deterministic per seed).
## Gravity is world-down regardless of the effect's rotation.

@export var delay := 0.0
@export var base_amount := 16
@export var texture: Texture2D
@export var hframes := 1
@export var vframes := 1
@export var size_min := 8.0
@export var size_max := 16.0
@export var speed_min := 120.0
@export var speed_max := 320.0
## Launch direction in the effect's local space (degrees, -90 = up).
@export var direction_deg := -90.0
## Half-angle of the launch cone, degrees.
@export var spread := 70.0
@export var emit_radius := 6.0
@export var gravity := 980.0
@export_range(0.0, 1.0) var bounce := 0.35
## Horizontal and spin damping applied at each bounce.
@export_range(0.0, 1.0) var friction := 0.55
## Air drag per second.
@export var drag := 0.4
@export var spin_min := -720.0
@export var spin_max := 720.0
## Coins: fake a 3D flip by squashing the width with cos(phase).
@export var flip := false
@export var flip_speed := 9.0
@export var life_min := 0.9
@export var life_max := 1.5
## Seconds of fade at the end of each body's life.
@export var fade := 0.35
## Floor below the spawn point (local units, scaled with the effect) when
## play() gets no floor_y.
@export var floor_offset := 48.0
@export var palette_from := 0.3
@export var palette_to := 0.7
@export var blend: VCMaterials.Blend = VCMaterials.Blend.MIX
@export var shade: VCMaterials.Shade = VCMaterials.Shade.LIT
## Optional neutral palette for this layer (e.g. grey smoke); empty = the effect palette.
@export var own_palette := PackedColorArray()
@export var brightness := 1.0
@export_range(0.0, 1.0) var tint_strength := 1.0
## Pieces shrink to this fraction while fading.
@export var end_scale := 0.6
## Pop-in: pieces scale from pop_from to 1 with a small overshoot over
## pop_time seconds (0 = off).
@export var pop_time := 0.0
@export var pop_from := 0.35
## Coins: a glint (glint_texture) flares on each piece as its face turns to
## the viewer. 0 = off; 1 = full size (glint_size × piece size).
@export_range(0.0, 1.0) var glint := 0.0
@export var glint_texture: Texture2D
@export var glint_size := 1.6

var _effect: VCEffect2D
var _n := 0
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _rot := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _size := PackedFloat32Array()
var _life := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _frame := PackedInt32Array()
var _col := PackedColorArray()
var _age := 0.0
var _started := false
var _floor := 48.0
var _frame_px := Vector2(1, 1)


func _vc_setup(e: VCEffect2D) -> void:
	_effect = e
	visible = false
	if texture != null:
		_frame_px = Vector2(texture.get_width() / float(hframes), texture.get_height() / float(vframes))


func _ensure(n: int) -> void:
	if _pos.size() >= n:
		return
	_pos.resize(n)
	_vel.resize(n)
	_rot.resize(n)
	_spin.resize(n)
	_size.resize(n)
	_life.resize(n)
	_phase.resize(n)
	_frame.resize(n)
	_col.resize(n)


func _vc_configure(e: VCEffect2D, n: int, px: int) -> void:
	_n = n
	_ensure(n)
	VCLayerUtil.style(self, e, blend, shade, px)
	var r := e.rng
	var frames := maxi(1, hframes * vframes)
	var base := deg_to_rad(direction_deg) + e.rotation
	var half := deg_to_rad(spread)
	for i in n:
		var ang := base + r.randf_range(-half, half)
		var sp := r.randf_range(speed_min, speed_max)
		var off := Vector2.from_angle(r.randf() * TAU) * r.randf() * emit_radius
		_pos[i] = off
		_vel[i] = Vector2.from_angle(ang) * sp
		_rot[i] = r.randf() * TAU
		_spin[i] = deg_to_rad(r.randf_range(spin_min, spin_max))
		_size[i] = r.randf_range(size_min, size_max)
		_life[i] = r.randf_range(life_min, life_max)
		_phase[i] = r.randf() * TAU
		_frame[i] = r.randi() % frames
		var c := e.layer_color(own_palette, r.randf_range(palette_from, palette_to), tint_strength)
		var shade_j := r.randf_range(0.85, 1.1) * brightness * e.bright
		_col[i] = Color(c.r * shade_j, c.g * shade_j, c.b * shade_j, c.a)


func _vc_begin() -> void:
	_age = 0.0
	_started = false
	visible = false
	# simulate in a world-aligned frame: cancel the effect's rotation
	rotation = -_effect.rotation
	if is_nan(_effect.floor_y_global):
		_floor = floor_offset
	else:
		var s := maxf(_effect.p_scale, 0.0001)
		_floor = (_effect.floor_y_global - _effect.global_position.y) / s


func _vc_update(t: float, dt: float) -> void:
	if t < delay:
		return
	if not _started:
		_started = true
		visible = _n > 0
		dt = t - delay
	_age += dt
	# fixed sub-steps keep bounces stable at low frame rates
	var steps := clampi(ceili(dt / 0.02), 1, 8)
	var h := dt / steps
	for _s in steps:
		for i in _n:
			var v := _vel[i]
			v.y += gravity * h
			v *= maxf(0.0, 1.0 - drag * h)
			var p := _pos[i] + v * h
			if p.y > _floor and v.y > 0.0:
				p.y = _floor
				v.y = -v.y * bounce
				v.x *= friction
				_spin[i] *= friction
				if absf(v.y) < 30.0:
					v.y = 0.0
			_pos[i] = p
			_vel[i] = v
			_rot[i] += _spin[i] * h
			if flip:
				_phase[i] += flip_speed * h * (0.6 + absf(v.x) / 300.0)
	queue_redraw()


func _draw() -> void:
	if not _started or texture == null:
		return
	var region_size := _frame_px
	for i in _n:
		var k := _age / _life[i]
		if k >= 1.0:
			continue
		var fade_k := clampf((_life[i] - _age) / maxf(fade, 0.0001), 0.0, 1.0)
		var s := _size[i] * lerpf(end_scale, 1.0, fade_k) * _pop(i)
		var sx := s
		var c := _col[i]
		if flip:
			var cs := cos(_phase[i])
			sx = s * maxf(0.12, absf(cs))
			var sheen := 0.8 + 0.35 * absf(cs)
			c = Color(c.r * sheen, c.g * sheen, c.b * sheen, c.a)
		c.a *= fade_k * _effect.alpha_mul
		var f := _frame[i]
		var region := Rect2(Vector2(f % hframes, f / hframes) * region_size, region_size)
		draw_set_transform(_pos[i], 0.0 if flip else _rot[i], Vector2(sx / region_size.x, s / region_size.y))
		draw_texture_rect_region(texture, Rect2(-region_size * 0.5, region_size), region, c)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if glint > 0.0 and glint_texture != null and flip:
		# second pass, so all glints batch into one draw call after the pieces
		var gs := glint_texture.get_size()
		for i in _n:
			if _age >= _life[i]:
				continue
			var cs := cos(_phase[i])
			var g := pow(maxf(0.0, cs), 10.0) * glint
			if g < 0.05:
				continue
			var fade_k := clampf((_life[i] - _age) / maxf(fade, 0.0001), 0.0, 1.0)
			var s := _size[i] * glint_size * g * _pop(i)
			var c := Color(1.6, 1.5, 1.3, g * fade_k * _effect.alpha_mul)
			draw_set_transform(_pos[i] + Vector2(-0.18, -0.2) * _size[i], 0.0, Vector2(s / gs.x, s / gs.y))
			draw_texture_rect(glint_texture, Rect2(-gs * 0.5, gs), false, c)
		draw_set_transform_matrix(Transform2D.IDENTITY)


## Pop-in scale for piece i (1 when pop_time is 0 or over).
func _pop(_i: int) -> float:
	if pop_time <= 0.0 or _age >= pop_time:
		return 1.0
	var k := _age / pop_time
	# back-out ease: overshoots ~10 % then settles at 1
	var b := 1.0 + 2.7 * pow(k - 1.0, 3.0) + 1.7 * pow(k - 1.0, 2.0)
	return lerpf(pop_from, 1.0, b)


func _vc_stop() -> void:
	pass


func _vc_end() -> void:
	visible = false
	_started = false


func vc_base_amount() -> int:
	return base_amount


func vc_end_time() -> float:
	return delay + life_max


## Initial launch velocities (tests check determinism with them).
func debug_velocities() -> PackedVector2Array:
	return _vel.slice(0, _n)


func debug_positions() -> PackedVector2Array:
	return _pos.slice(0, _n)


func floor_local() -> float:
	return _floor
