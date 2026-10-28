@tool
class_name VCLayerBolt
extends Line2D
## A jagged or straight bolt between points: lightning, beams, chains. The
## path is the effect's `points` (chain_lightning) or a straight segment along
## +X of play_line()'s distance (`length` otherwise). It is re-jittered every
## `refresh` seconds and follows VCHandle.set_line()/set_points() each frame.

const MAX_POINTS := 96
const BEAM := preload("res://addons/vfx_core/textures/vc_beam.png")

@export var delay := 0.0
@export var life := 0.3
## Repeat every `life` (looping beams); fades with the effect's stop_fade.
@export var loop := false
@export var length := 200.0
## Distance between jitter points in pixels.
@export var segment := 18.0
## Sideways jitter amplitude in pixels (0 = straight beam).
@export var jag := 12.0
## Seconds between re-jitters (0 = once per play).
@export var refresh := 0.05
@export var width_from := 4.0
@export var width_to := 2.0
## Random width flicker (0 = steady).
@export var flicker := 0.0
@export var palette_from := 0.0
@export var palette_to := 0.4
@export var blend: VCMaterials.Blend = VCMaterials.Blend.ADD
@export var brightness := 1.0
@export_range(0.0, 1.0) var tint_strength := 1.0
@export var alpha_keys := PackedVector2Array([Vector2(0, 1), Vector2(1, 0)])
## Start this far along the path (e.g. past a muzzle), in pixels.
@export var start_offset := 0.0
## Random rotation of the whole bolt per play, degrees (±); radial arcs.
@export var angle_jitter := 0.0

var _effect: VCEffect2D
var _rng := RandomNumberGenerator.new()
var _slot := -1
var _base_len := -1.0
var _base_pts := PackedVector2Array()
var _buf := PackedVector2Array()
var _authored_rot := 0.0


func _vc_setup(e: VCEffect2D) -> void:
	_effect = e
	_authored_rot = rotation
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	joint_mode = Line2D.LINE_JOINT_ROUND
	texture_mode = Line2D.LINE_TEXTURE_STRETCH
	var c := Curve.new()
	c.add_point(Vector2(0, 0.55))
	c.add_point(Vector2(0.12, 1))
	c.add_point(Vector2(0.88, 1))
	c.add_point(Vector2(1, 0.55))
	width_curve = c
	visible = false


func _vc_configure(e: VCEffect2D, _n: int, px: int) -> void:
	VCLayerUtil.style(self, e, blend, VCMaterials.Shade.FLAT, px)
	_rng.seed = e.rng.randi()
	rotation = _authored_rot + deg_to_rad(e.rng.randf_range(-angle_jitter, angle_jitter))
	texture = BEAM
	_slot = -1


func _vc_begin() -> void:
	visible = false
	_slot = -1


func _vc_update(t: float, _dt: float) -> void:
	var k := (t - delay) / maxf(life, 0.0001)
	if loop and k >= 0.0:
		k = fposmod(k, 1.0)
	if k < 0.0 or k > 1.0 or _effect.alpha_mul <= 0.0:
		visible = false
		return
	visible = true
	var slot := int(floor((t - delay) / refresh)) if refresh > 0.0 else 0
	if slot != _slot or _path_changed():
		_slot = slot
		_rebuild()
	var w := lerpf(width_from, width_to, k)
	if flicker > 0.0:
		w *= 1.0 - flicker * _rng.randf()
	width = w
	var c := _effect.palette_color(lerpf(palette_from, palette_to, k), tint_strength)
	var b := brightness * _effect.bright
	var a := VCLayerUtil.eval_keys(alpha_keys, k) * _effect.alpha_mul * _effect.fade_mul()
	self_modulate = Color(c.r * b, c.g * b, c.b * b, a)


func _path_changed() -> bool:
	if _effect.points.size() >= 2:
		return _effect.points != _base_pts
	var l := _effect.local_line_length()
	return not is_equal_approx(l, _base_len)


func _rebuild() -> void:
	var path := _effect.points
	_base_pts = path
	_base_len = _effect.local_line_length()
	if path.size() < 2:
		var l := _base_len if _base_len >= 0.0 else length
		path = PackedVector2Array([Vector2(start_offset, 0), Vector2(maxf(l, start_offset + 1.0), 0)])
	_buf.clear()
	_buf.append(path[0])
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var d := b - a
		var dist := d.length()
		var n := clampi(int(dist / maxf(segment, 2.0)), 1, MAX_POINTS / maxi(path.size() - 1, 1))
		var nrm := Vector2(-d.y, d.x) / maxf(dist, 0.0001)
		for j in range(1, n + 1):
			var u := float(j) / n
			var p := a + d * u
			if j < n and jag > 0.0:
				p += nrm * _rng.randf_range(-jag, jag) * sin(u * PI)
			_buf.append(p)
	points = _buf


func _vc_stop() -> void:
	pass


func _vc_end() -> void:
	visible = false


func vc_base_amount() -> int:
	return 1


func vc_end_time() -> float:
	return delay + life


## Number of points in the current path (tests use it).
func path_point_count() -> int:
	return get_point_count()


func path_end() -> Vector2:
	return get_point_position(get_point_count() - 1) if get_point_count() > 0 else Vector2.ZERO
