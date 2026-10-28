class_name VCHandle
extends RefCounted
## Returned by every VfxCore.play*() call. Safe to keep after the effect has
## finished: once the pooled instance is reused, the handle goes dead
## (is_alive() == false) and every call on it is a no-op.

var id: StringName = &""
var _effect: VCEffect2D = null
var _generation := -1


static func make(effect: VCEffect2D) -> VCHandle:
	var h := VCHandle.new()
	h._effect = effect
	h._generation = effect.generation
	h.id = effect.effect_id
	return h


## An inert handle (unknown id, dropped by the budget). Never alive.
static func inert(p_id: StringName = &"") -> VCHandle:
	var h := VCHandle.new()
	h.id = p_id
	return h


func is_alive() -> bool:
	return _effect != null and is_instance_valid(_effect) and _effect.generation == _generation and _effect.active


## Loops fade out and then finish; one-shots end at once.
func stop() -> void:
	if is_alive():
		_effect.stop()


## Ends the effect immediately (no fade).
func kill() -> void:
	if is_alive():
		_effect.kill()


## Live parameter change: color, scale, intensity, speed, style, pixel_size,
## direction. Values are clamped. Returns false on a dead handle or unknown name.
func set_param(param: StringName, value: Variant) -> bool:
	if not is_alive():
		return false
	return _effect.set_param(param, value)


## Re-aims a line or beam effect: moves it to `from`, points it at `to` and
## stretches line/bolt layers to the distance. Call it every frame for beams
## that track moving ends. Returns false on a dead handle.
func set_line(from: Vector2, to: Vector2) -> bool:
	if not is_alive() or not from.is_finite() or not to.is_finite():
		return false
	_effect.set_line_global(from, to)
	return true


## Replaces the polyline of a bolt effect (chain_lightning) with global points.
func set_points(points: PackedVector2Array) -> bool:
	if not is_alive():
		return false
	_effect.set_points_global(points)
	return true


## The effect node while alive, else null. Do not keep the reference: the
## node is pooled and will be reused for other plays.
func get_effect() -> VCEffect2D:
	return _effect if is_alive() else null
