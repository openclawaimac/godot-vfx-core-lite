extends Node
## Autoload "VfxCore": the one-call API of VFX Core 2D.
##
##   var h := VfxCore.play(&"explosion_small", pos, {color = Color.ORANGE, scale = 1.5})
##   VfxCore.play_attached(&"smoke_puff", node)      # follows node, auto-stops when it leaves the tree
##   VfxCore.play_line(&"muzzle_rifle", from, to)     # oriented along from -> to, line layers span it
##   VfxCore.apply(&"some_flash", $Sprite2D)          # material effect on an existing CanvasItem
##   h.stop()                                         # loops; one-shots end themselves
##   VfxCore.warm(&"hit_spark", 8)                    # prewarm a pool
##   VfxCore.play(&"chain_lightning", a, {points = [a, b, c]})  # bolt through points
##   h.set_line(from, to)                             # beams: re-aim every frame
##   VfxCore.list()  VfxCore.info(id)  VfxCore.stats()
##   VfxCore.shake(0.4)                               # camera shake, trauma model (0..1)
##   VfxCore.hit_stop(0.06)                           # freeze-frame on impact
##
## Effects live under this node's "Effects" Node2D in the root viewport, in
## world space, so a Camera2D moves them like any other world node.

const VERSION := "0.5.0-m5"
## The public API is frozen from M2 on (docs/API.md); tests/core/test_api_freeze.gd guards it.
const API_LEVEL := 1

## Global live-particle budget (§6). LOW effects are dropped first, then the
## oldest one-shot is recycled; HIGH effects always play.
var max_live_particles := 3000
## Optional PointLight2D layers (none ship in M1); keep off on web.
var lights_enabled := not OS.has_feature("web")
## Default max instances per effect id. A preset's max_instances overrides it
## per id; nothing ever exceeds POOL_HARD_CAP.
var pool_max_per_id := 16
## z_index of the layer that holds world-space effects (added in M4). The autoload sits
## before the main scene in the tree, so at z 0 effects would draw under the level.
## A play's `z_index` option is relative to this. Lower it to put effects under parts of
## your scene; 0 restores the 0.3 behaviour.
var layer_z_index := 100:
	set(v):
		layer_z_index = clampi(v, RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX)
		if _layer != null:
			_layer.z_index = layer_z_index
const POOL_HARD_CAP := 64
## When true, nothing advances on its own; call step(dt) (tests, capture).
var manual_step := false
## Global time scale for all effects.
var time_scale := 1.0

## Camera shake (trauma model): offset = shake_max_offset * trauma² * noise;
## trauma falls by shake_decay per second. Shake and hit-stop run on unscaled
## time, so a hit-stop does not freeze the shake.
var shake_max_offset := Vector2(24, 18)
var shake_decay := 1.6
## Noise frequency in Hz (higher = more jittery).
var shake_frequency := 18.0
## Camera to shake. null = the viewport's current Camera2D; with no Camera2D
## the root viewport's canvas transform is offset instead.
var shake_camera: Camera2D = null

var _entries: Dictionary = {}   # id -> registry entry (Dictionary)
var _pools: Dictionary = {}     # id -> VCPool
var _presets: Dictionary = {}   # id -> {preset_id -> VCPreset}
var _active: Array[VCEffect2D] = []
var _scratch: Array[VCEffect2D] = []
var _layer: Node2D
var _pool_root: Node2D
var _live := 0
var _warned: Dictionary = {}
var _counters := {"plays": 0, "dropped": 0, "recycled_budget": 0, "over_budget": 0, "unknown": 0}
var _trauma := 0.0
var _shake_t := 0.0
var _shake_snap := 0
var _shake_applied := Vector2.ZERO
var _shake_target: Object = null
var _hs_left := 0.0
var _hs_saved := 1.0
var _hs_on := false
var _ui_hosts: Dictionary = {}  # CanvasLayer instance id -> Node2D host


func _init() -> void:
	for id in VCRegistry.EFFECTS:
		_entries[id] = VCRegistry.EFFECTS[id]


func _enter_tree() -> void:
	if _layer == null:
		_layer = Node2D.new()
		_layer.name = "Effects"
		_layer.z_index = layer_z_index
		add_child(_layer)
		_pool_root = _layer


func _process(delta: float) -> void:
	# unscaled frame time for shake and hit-stop (Engine.time_scale is >= 0.01
	# while a hit-stop runs, so this stays exact under Movie Maker too)
	var ts := Engine.time_scale
	var real := delta / ts if ts > 0.0 else delta
	var stopped := _hs_on
	feedback_step(real)
	if not manual_step:
		step(delta * time_scale)
		if stopped and not hit_stop_holds_screen and real > delta:
			_step_screen((real - delta) * time_scale)


## Full-screen effects (usage `screen`: screen_flash, chromatic_kick, damage_vignette, ...)
## keep running in real time during a hit_stop(), so a white flash fades on schedule
## instead of being held on screen for the whole freeze (photosensitivity). Set true to
## freeze them with everything else, as before M4.
var hit_stop_holds_screen := false


func _step_screen(dt: float) -> void:
	_scratch.assign(_active)
	for e in _scratch:
		if e.active and e.usage == &"screen":
			e.advance(dt)


## Seconds of effect time since start (advances with step(), so it follows
## time_scale and manual stepping). Read-only.
var clock := 0.0


## Advances every active effect by `dt` seconds.
func step(dt: float) -> void:
	clock += dt
	_scratch.assign(_active)
	for e in _scratch:
		if e.active:
			e.advance(dt)


# ---------------------------------------------------------------- public API

## Plays effect `id` at global position `pos`. Options: color (Color tint or
## 3 colours), scale, intensity, speed, style ("smooth"/"pixel"), pixel_size,
## seed, preset, direction/normal (Vector2 or radians), rotation, priority,
## floor_y, z_index, light_bg (bool), points (global Vector2 array for bolt
## effects such as chain_lightning). Unknown ids give an error and an inert handle.
func play(id: StringName, pos: Vector2, opts: Dictionary = {}) -> VCHandle:
	var e := _spawn(id, opts)
	if e == null:
		return VCHandle.inert(id)
	e.global_position = pos
	if opts.has("points"):
		e.set_points_global(opts["points"])
	return _launch(e)


## Plays `id` on `target` (Node2D or Control) and follows it every frame. The
## effect stops when the target leaves the tree. Option `offset` (Vector2).
func play_attached(id: StringName, target: Node, opts: Dictionary = {}) -> VCHandle:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		push_error("VfxCore.play_attached: target is null or not in the tree")
		return VCHandle.inert(id)
	var e := _spawn(id, opts)
	if e == null:
		return VCHandle.inert(id)
	_host_for(e, target)
	e.follow(target, e.follow_offset)
	return _launch(e)


## Plays `id` at `from`, rotated toward `to`; line layers span the distance.
func play_line(id: StringName, from: Vector2, to: Vector2, opts: Dictionary = {}) -> VCHandle:
	var e := _spawn(id, opts)
	if e == null:
		return VCHandle.inert(id)
	e.set_line_global(from, to)
	e._apply_params(false)
	return _launch(e)


## Runs a material effect on an existing CanvasItem; the original material is
## restored when it ends.
func apply(id: StringName, target: CanvasItem, opts: Dictionary = {}) -> VCHandle:
	if target == null or not is_instance_valid(target):
		push_error("VfxCore.apply: target is null")
		return VCHandle.inert(id)
	var e := _spawn(id, opts)
	if e == null:
		return VCHandle.inert(id)
	e.apply_target = target
	if target is Node2D:
		e.global_position = (target as Node2D).global_position
	return _launch(e)


## Adds camera-shake trauma (0..1, clamped; offset grows with trauma²).
## Options: pixel_size (int) snaps the offset to whole blocks for pixel art.
func shake(trauma: float, opts: Dictionary = {}) -> void:
	if not is_finite(trauma) or trauma <= 0.0:
		return
	_trauma = clampf(_trauma + trauma, 0.0, 1.0)
	_shake_snap = clampi(int(opts.get("pixel_size", 0)), 0, 8)


## Current shake trauma (0..1).
func shake_trauma() -> float:
	return _trauma


## Freeze-frame: sets Engine.time_scale to `scale` (clamped 0.01..1) for
## `seconds` of real time, then restores the previous time scale. A new call
## while one runs extends it (never shortens). Everything that uses delta
## freezes, including effects, so an impact holds on its brightest frame.
## Full-screen effects are the exception: they keep fading in real time (see
## `hit_stop_holds_screen`).
func hit_stop(seconds: float = 0.06, scale: float = 0.02) -> void:
	if not is_finite(seconds) or seconds <= 0.0:
		return
	seconds = minf(seconds, 1.0)
	if not _hs_on:
		_hs_on = true
		_hs_saved = Engine.time_scale
	_hs_left = maxf(_hs_left, seconds)
	Engine.time_scale = clampf(scale, 0.01, 1.0) if is_finite(scale) else 0.02


func is_hit_stopped() -> bool:
	return _hs_on


## Advances shake and hit-stop by `real_dt` seconds of unscaled time. Called
## every frame; call it yourself only when you drive time by hand.
func feedback_step(real_dt: float) -> void:
	if _hs_on:
		_hs_left -= real_dt
		if _hs_left <= 0.0:
			_hs_on = false
			_hs_left = 0.0
			Engine.time_scale = _hs_saved
	_update_shake(real_dt)


## Ends any shake and hit-stop now (restores the camera and time scale).
func stop_feedback() -> void:
	_trauma = 0.0
	_unapply_shake()
	if _hs_on:
		_hs_on = false
		_hs_left = 0.0
		Engine.time_scale = _hs_saved


## Ends every active effect immediately.
func stop_all() -> void:
	for p: VCPool in _pools.values():
		p.stop_all()


## Prewarms the pool of `id` with `count` instances. Returns instances created.
func warm(id: StringName, count: int = 4) -> int:
	var p := _pool(id)
	return p.prewarm(count) if p != null else 0


## Ids, optionally filtered by a substring of the id or the category.
func list(filter: StringName = &"") -> Array[StringName]:
	var out: Array[StringName] = []
	var f := String(filter)
	for id: StringName in _entries:
		if f == "" or String(id).contains(f) or String(_entries[id].get("category", "")) == f:
			out.append(id)
	out.sort_custom(func(a, b): return String(a) < String(b))
	return out


func has(id: StringName) -> bool:
	return _entries.has(id)


## Registry data for `id` (path, category, size, loop, duration, presets, ...).
func info(id: StringName) -> Dictionary:
	return _entries[id].duplicate(true) if _entries.has(id) else {}


func presets(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if _entries.has(id):
		for p in _entries[id].get("presets", []):
			out.append(StringName(p))
	return out


func stats() -> Dictionary:
	var pooled := 0
	var inst := 0
	var rec := 0
	var grown := 0
	for p: VCPool in _pools.values():
		pooled += p.free.size()
		inst += p.instantiated
		rec += p.recycled
		grown += p.grown
	return {
		"active": _active.size(), "pooled": pooled, "instantiated": inst,
		"live_particles": _live, "max_live_particles": max_live_particles,
		"plays": _counters["plays"], "dropped": _counters["dropped"],
		"recycled_pool": rec, "grown_pool": grown, "recycled_budget": _counters["recycled_budget"],
		"over_budget": _counters["over_budget"], "unknown": _counters["unknown"],
	}


## Registers an extra effect scene (your own effects, tests). `preset_paths`
## maps preset id -> .tres path.
func register(id: StringName, scene_path: String, preset_paths: Dictionary = {}, category: StringName = &"custom") -> void:
	_entries[id] = {"path": scene_path, "category": category, "presets": preset_paths.keys(), "preset_paths": preset_paths}
	_presets.erase(id)


func unregister(id: StringName) -> void:
	if _pools.has(id):
		(_pools[id] as VCPool).clear()
		_pools.erase(id)
	_entries.erase(id)
	_presets.erase(id)


## Frees all pooled instances (they are recreated on demand).
func clear_pools() -> void:
	for p: VCPool in _pools.values():
		p.clear()
	_pools.clear()
	_active.clear()
	_live = 0


## Pool size for `id`, clamped to 1..POOL_HARD_CAP. Overrides the preset.
func set_pool_max(id: StringName, n: int) -> void:
	var p := _pool(id)
	if p != null:
		p.max_size = clampi(n, 1, POOL_HARD_CAP)


## Lets the pool of `id` grow past its max (up to POOL_HARD_CAP) while the
## particle budget has room, instead of recycling the oldest instance.
func set_pool_grow(id: StringName, on: bool) -> void:
	var p := _pool(id)
	if p != null:
		p.grow = on


func get_pool(id: StringName) -> VCPool:
	return _pools.get(id)


func live_particles() -> int:
	return _live


func active_effects() -> Array[VCEffect2D]:
	return _active


# ---------------------------------------------------------------- internals

func _pool(id: StringName) -> VCPool:
	var p: VCPool = _pools.get(id)
	if p != null:
		return p
	if not _entries.has(id):
		return null
	var scene: PackedScene = load(_entries[id]["path"])
	if scene == null:
		push_error("VfxCore: could not load scene for '%s'" % id)
		return null
	var n := pool_max_per_id
	var grow := false
	var def := _preset(id, &"default")
	if def != null:
		if def.max_instances > 0:
			n = def.max_instances
		grow = def.pool_grow
	p = VCPool.new(id, scene, _pool_root, clampi(n, 1, POOL_HARD_CAP), self)
	p.grow = grow
	p.hard_cap = POOL_HARD_CAP
	_pools[id] = p
	return p


func _preset(id: StringName, preset_id: StringName) -> VCPreset:
	var by_id: Dictionary = _presets.get(id, {})
	if by_id.has(preset_id):
		return by_id[preset_id]
	var entry: Dictionary = _entries[id]
	var path := ""
	if entry.has("preset_paths"):
		path = entry["preset_paths"].get(preset_id, "")
	elif preset_id in entry.get("presets", []):
		path = "res://addons/vfx_core/presets/%s/%s.tres" % [id, preset_id]
	var pr: VCPreset = load(path) if path != "" and ResourceLoader.exists(path) else null
	if pr == null and preset_id != &"default":
		_warn_once("preset:%s:%s" % [id, preset_id], "VfxCore: '%s' has no preset '%s', using default" % [id, preset_id])
	by_id[preset_id] = pr
	_presets[id] = by_id
	return pr


func _spawn(id: StringName, opts: Dictionary) -> VCEffect2D:
	if not _entries.has(id):
		_counters["unknown"] += 1
		push_error("VfxCore: unknown effect id '%s'%s" % [id, _suggest(id)])
		return null
	var p := _pool(id)
	if p == null:
		return null
	var e := p.acquire(_live + p.base_particles <= max_live_particles)
	if e == null:
		return null
	var preset_id: StringName = StringName(opts.get("preset", &"default"))
	e.configure(_preset(id, preset_id), opts)
	return e


func _launch(e: VCEffect2D) -> VCHandle:
	if not _make_room(e):
		_counters["dropped"] += 1
		e.pool.release(e)
		return VCHandle.inert(e.effect_id)
	_counters["plays"] += 1
	_active.append(e)
	e.budget_count = e.particle_count()
	_live += e.budget_count
	e.start()
	# start() may finish instantly (zero duration); handle still reports it
	return VCHandle.make(e)


## Frees budget for `e`. Returns false when `e` must be dropped.
func _make_room(e: VCEffect2D) -> bool:
	var need := e.particle_count()
	if _live + need <= max_live_particles:
		return true
	# 1) drop active LOW effects, oldest first
	var i := 0
	while _live + need > max_live_particles and i < _active.size():
		var a := _active[i]
		if a.p_priority == VCParams.Priority.LOW:
			_counters["recycled_budget"] += 1
			a.kill()
		else:
			i += 1
	if _live + need <= max_live_particles:
		return true
	# 2) a LOW newcomer is dropped rather than evicting anything else
	if e.p_priority == VCParams.Priority.LOW:
		return false
	# 3) recycle the oldest NORMAL one-shots
	i = 0
	while _live + need > max_live_particles and i < _active.size():
		var a := _active[i]
		if not a.looping and a.p_priority == VCParams.Priority.NORMAL:
			_counters["recycled_budget"] += 1
			a.kill()
		else:
			i += 1
	if _live + need <= max_live_particles:
		return true
	# 4) HIGH always plays (over budget, counted); NORMAL is dropped
	if e.p_priority == VCParams.Priority.HIGH:
		_counters["over_budget"] += 1
		return true
	return false


func _on_released(e: VCEffect2D) -> void:
	var i := _active.find(e)
	if i >= 0:
		_active.remove_at(i)
		_live -= e.budget_count
		e.budget_count = 0


# ---------------------------------------------------------------- shake

func _update_shake(dt: float) -> void:
	_unapply_shake()
	if _trauma <= 0.0 or not is_inside_tree():
		return
	_shake_t += dt
	_trauma = maxf(_trauma - shake_decay * dt, 0.0)
	var k := _trauma * _trauma
	var f := shake_frequency * TAU
	var t := _shake_t
	var n := Vector2(sin(t * f) * 0.6 + sin(t * f * 1.73 + 1.3) * 0.3 + sin(t * f * 3.1 + 4.1) * 0.1,
		sin(t * f * 1.13 + 2.2) * 0.6 + sin(t * f * 1.91 + 0.4) * 0.3 + sin(t * f * 2.87 + 5.3) * 0.1)
	var off := shake_max_offset * k * n
	if _shake_snap > 0:
		off = (off / _shake_snap).round() * _shake_snap
	var cam := shake_camera if shake_camera != null and is_instance_valid(shake_camera) else get_viewport().get_camera_2d()
	if cam != null:
		cam.offset += off
		_shake_target = cam
	else:
		var vp := get_viewport()
		var xf := vp.canvas_transform
		xf.origin += off
		vp.canvas_transform = xf
		_shake_target = vp
	_shake_applied = off


func _unapply_shake() -> void:
	if _shake_target != null and is_instance_valid(_shake_target) and _shake_applied != Vector2.ZERO:
		if _shake_target is Camera2D:
			(_shake_target as Camera2D).offset -= _shake_applied
		elif _shake_target is Viewport:
			var vp := _shake_target as Viewport
			var xf := vp.canvas_transform
			xf.origin -= _shake_applied
			vp.canvas_transform = xf
	_shake_applied = Vector2.ZERO
	_shake_target = null


# ---------------------------------------------------------------- UI hosting

## Effects attached to a Control inside a CanvasLayer (HUD) are drawn in that
## layer, on top of its UI, so they line up with the Control on screen. The
## host is a Node2D: nothing is added inside containers and no Control is
## created, so layout and mouse input are untouched. The pool moves the
## effect back when it ends.
func _host_for(e: VCEffect2D, target: Node) -> void:
	if not (target is CanvasItem):
		return
	var cl := (target as CanvasItem).get_canvas_layer_node()
	if cl == null:
		return
	var key := cl.get_instance_id()
	var host: Node2D = _ui_hosts.get(key)
	if host == null or not is_instance_valid(host):
		host = Node2D.new()
		host.name = "VfxCoreUI"
		host.tree_exiting.connect(_on_host_exiting.bind(host))
		cl.add_child(host)
		_ui_hosts[key] = host
	elif host.get_index() != cl.get_child_count() - 1:
		cl.move_child(host, -1)
	if e.get_parent() != host:
		e.get_parent().remove_child(e)
		host.add_child(e)


func _on_host_exiting(host: Node2D) -> void:
	for c in host.get_children():
		if c is VCEffect2D:
			(c as VCEffect2D).kill()


func _suggest(id: StringName) -> String:
	var best := ""
	var best_s := 0.0
	for k in _entries:
		var s := String(id).similarity(String(k))
		if s > best_s:
			best_s = s
			best = String(k)
	return " (did you mean '%s'?)" % best if best != "" and best_s > 0.3 else ""


func _warn_once(key: String, msg: String) -> void:
	if not _warned.has(key):
		_warned[key] = true
		push_warning(msg)
