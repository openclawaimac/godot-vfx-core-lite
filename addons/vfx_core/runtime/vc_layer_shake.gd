@tool
class_name VCLayerShake
extends Node
## Camera feedback as an effect layer: adds shake trauma (scaled by the
## effect's intensity) and an optional hit-stop when the timeline reaches
## `delay`. Lets `VfxCore.play(&"screen_shake", pos)` and presets drive
## VfxCore.shake() / VfxCore.hit_stop(). Pixel style snaps the shake offset
## to whole pixel blocks.

@export var delay := 0.0
@export_range(0.0, 1.0) var trauma := 0.4
## Freeze-frame seconds (real time); 0 = none.
@export var hit_stop := 0.0
@export_range(0.01, 1.0) var hit_stop_scale := 0.02

var _effect: VCEffect2D
var _done := false
var _px := 0


func _vc_setup(e: VCEffect2D) -> void:
	_effect = e


func _vc_configure(_e: VCEffect2D, _n: int, px: int) -> void:
	_px = px


func _vc_begin() -> void:
	_done = false


func _vc_update(t: float, _dt: float) -> void:
	if _done or t < delay:
		return
	_done = true
	var core := get_tree().root.get_node_or_null(^"VfxCore") if is_inside_tree() else null
	if core == null:
		return
	var k := _effect.p_intensity if _effect != null else 1.0
	if trauma > 0.0 and k > 0.0:
		core.shake(trauma * k, {"pixel_size": _px})
	if hit_stop > 0.0 and k > 0.0:
		core.hit_stop(hit_stop, hit_stop_scale)


func _vc_stop() -> void:
	pass


func _vc_end() -> void:
	_done = false


func vc_base_amount() -> int:
	return 0


func vc_end_time() -> float:
	return delay + maxf(hit_stop, 0.05)
