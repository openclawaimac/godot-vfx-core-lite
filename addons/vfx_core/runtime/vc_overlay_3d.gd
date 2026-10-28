class_name VCOverlay3D
extends Node
## Plays 2D VFX Core effects at 3D positions: each point is projected to the
## screen with Camera3D.unproject_position() and re-projected every frame, so
## the effect stays on its spot while the camera moves. Effects behind the
## camera are hidden. Made for top-down and angled RTS cameras.
##
##   var overlay := VCOverlay3D.new()
##   overlay.camera_path = ^"../Camera3D"
##   add_child(overlay)
##   overlay.play(&"explosion_medium", unit.global_position)

## The camera to project with. Empty = the viewport's current 3D camera.
@export var camera_path: NodePath
## Effect scale at `reference_distance` from the camera; 0 turns distance
## scaling off.
@export var reference_distance := 0.0
@export_range(0.1, 4.0) var min_distance_scale := 0.35
@export_range(0.1, 4.0) var max_distance_scale := 2.0

var _tracked: Array = []  # [VCHandle, Vector3, base_scale, to: Variant(Vector3|null), points3: Array]


func camera() -> Camera3D:
	if not camera_path.is_empty():
		var c := get_node_or_null(camera_path) as Camera3D
		if c != null:
			return c
	return get_viewport().get_camera_3d() if is_inside_tree() else null


## Screen position of `world` (viewport pixels).
func project(world: Vector3) -> Vector2:
	var c := camera()
	return c.unproject_position(world) if c != null else Vector2.ZERO


## False when `world` is behind the camera (or there is no camera).
func is_in_front(world: Vector3) -> bool:
	var c := camera()
	return c != null and not c.is_position_behind(world)


## Plays `id` at a 3D point and keeps it there. Option `to` (Vector3) aims the
## effect from the point toward `to` on screen (muzzles, beams); `points`
## given as Vector3s (chain_lightning) are projected too. Every frame the
## position, the `to` end, the points and the distance scale are refreshed.
func play(id: StringName, world: Vector3, opts: Dictionary = {}) -> VCHandle:
	var o := opts.duplicate()
	var base_scale: float = float(o.get("scale", 1.0))
	o["scale"] = base_scale * _distance_scale(world)
	var pts3: Array = []
	if o.has("points") and o["points"] is Array and not o["points"].is_empty() and o["points"][0] is Vector3:
		pts3 = (o["points"] as Array).filter(func(q): return q is Vector3)
		o["points"] = _project_all(pts3)
	var h: VCHandle
	var to: Variant = null
	if o.has("to") and o["to"] is Vector3:
		to = o["to"]
		o.erase("to")
		h = VfxCore.play_line(id, project(world), project(to), o)
	else:
		h = VfxCore.play(id, project(world), o)
	if h.is_alive():
		_tracked.append([h, world, base_scale, to, pts3])
		_update(_tracked[-1])
	return h


func _project_all(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q: Vector3 in pts:
		out.append(project(q))
	return out


## Number of effects still followed by the overlay.
func tracked_count() -> int:
	return _tracked.size()


func _process(_delta: float) -> void:
	refresh()


## Re-projects every live effect (called each frame; call it after moving the
## camera yourself when you step time manually).
func refresh() -> void:
	var keep: Array = []
	for t: Array in _tracked:
		if (t[0] as VCHandle).is_alive():
			_update(t)
			keep.append(t)
	_tracked = keep


func _update(t: Array) -> void:
	var e := (t[0] as VCHandle).get_effect()
	if e == null:
		return
	var world: Vector3 = t[1]
	var ds := _distance_scale(world)
	if reference_distance > 0.0:
		e.p_scale = VCParams.clamp_scale(float(t[2]) * ds)
		e.scale = Vector2(e.p_scale, e.p_scale)
	if t[3] is Vector3:
		e.set_line_global(project(world), project(t[3]))
	else:
		e.global_position = project(world)
	if not (t[4] as Array).is_empty():
		e.set_points_global(_project_all(t[4]))
	e.visible = is_in_front(world)


func _distance_scale(world: Vector3) -> float:
	var c := camera()
	if reference_distance <= 0.0 or c == null:
		return 1.0
	var d := maxf(c.global_position.distance_to(world), 0.001)
	return clampf(reference_distance / d, min_distance_scale, max_distance_scale)
