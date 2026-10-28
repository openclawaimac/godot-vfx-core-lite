@tool
class_name VCHookDestruction
extends Node
## Plays VFX Core effects for a destruction world (Godot Destruction Core's
## DKWorld or anything with the same signals). Add it as a child of the world,
## or point `world_path` at it. No destruction classes are referenced, so this
## file loads even when that addon is not installed.
##
## Signals used (each one is optional):
##   detonated(det: Dictionary, report)        -> explosion + shock ring + shake
##   cells_destroyed(report)                   -> debris per material
##   piece_detached(piece: Dictionary)         -> crumble pebbles (+ falling dust trail)
##   piece_landed(piece: Dictionary, crush, impact: int) -> ground dust
##
## Optional Pro modules (fire and chain reactions). The hook finds them through
## the world (get_extension(&"fire"), get_detonation_router()) on bind and on
## the first ticks, or you pass them with bind_fire() / bind_chain():
##   fire.cell_ignited(cell, inst)            -> looping fire per area (small, then large)
##   fire.cell_burnt_out(cell, mat, inst)     -> smoke + embers when an area goes out
##   fire.trigger_ignited(trigger_id, inst)   -> fuse spark on the lit barrel
##   chain.blast_scheduled(event)             -> fuse spark while a chained blast waits
##   chain.blast_fired(event, report)         -> explosion + shake (once: skipped when
##                                               the world's detonated already played it)
##   chain.blast_fizzled(event)               -> small smoke puff
##   chain.chain_finished(stats)              -> settling dust + lingering smoke for big chains
##
## Every effect id below falls back to a Lite effect when it is not
## registered, so the hook works with the Lite set alone.

## Emitted for every effect the hook plays (useful for sound or tests).
signal played(id: StringName, global_pos: Vector2)
## Camera shake request in 0..1 trauma. Connect it to your camera.
signal shake_requested(trauma: float)

## The destruction world. Empty or ".." means the parent node.
@export var world_path: NodePath = ^".."
@export var enabled := true

@export_group("Detonation")
@export var explode_on_detonation := true
## Radius (px) at which medium and large explosions take over.
@export var radius_medium := 72.0
@export var radius_large := 140.0
## Radius (px) an explosion at scale 1 is made for.
@export var radius_reference := 48.0
@export var ring_on_detonation := true
## Shake trauma for a detonation of radius_reference; scales with radius.
@export_range(0.0, 1.0) var shake_trauma := 0.25
## Trauma floor and ceiling per detonation: small blasts are still felt and a
## huge one never pins the camera at full shake (trauma model: offset ~ trauma²).
@export_range(0.0, 1.0) var shake_min := 0.1
@export_range(0.0, 1.0) var shake_max := 0.7

@export_group("Debris")
@export var debris_on_cells := true
## Material id -> effect id. Unlisted materials use `debris_default`.
@export var debris_map: Dictionary = {
	&"stone": &"debris_stone", &"rock": &"debris_stone", &"bedrock": &"debris_stone",
	&"rubble": &"debris_stone", &"brick": &"debris_brick", &"wood": &"debris_wood",
	&"metal": &"debris_metal", &"steel": &"debris_metal", &"glass": &"debris_glass",
	&"dirt": &"debris_dirt", &"sand": &"debris_dirt", &"ice": &"debris_ice",
	&"crystal": &"debris_crystal", &"gem": &"debris_crystal",
}
@export var debris_default: StringName = &"debris_stone"
## Tint debris with the material's debris_color when the mapped effect is
## missing and the default is used instead.
@export var tint_fallback_debris := true
## Destroyed cells that give intensity 1.
@export var cells_per_intensity := 24.0
## Most debris effects started by one event.
@export_range(1, 8) var max_debris_per_event := 4
## Debris bodies land on the world's surface: each play gets a `floor_y` at the
## first solid cell below its position (scanning down at most `floor_scan_cells`).
## Off, or when the world has no grid, bodies use their effect's own floor offset.
@export var debris_on_world_floor := true
@export_range(1, 512) var floor_scan_cells := 96

@export_group("Pieces")
@export var crumble_on_detach := true
## Attach dust_trail_falling to a detached piece when the piece dictionary
## has a "node" (Node2D) entry; it stops when that node leaves the tree.
@export var trail_on_detach := true
@export var dust_on_land := true
## Impact (sub-cell units per tick, 256 = one cell) that gives scale 1.
@export var impact_reference := 512.0
## Pieces with at least this many cells also raise a collapse cloud.
@export var collapse_cells := 60

@export_group("Fire (Pro)")
@export var fire_on_ignite := true
## Burning cells are grouped into square areas of this size (world-local px);
## each area plays one looping fire.
@export var fire_area_px := 24.0
## Burning cells in one area that switch it to fire_large.
@export var fire_large_cells := 40
## Most looping fires at once; further areas wait for a free slot.
@export_range(1, 64) var max_fires := 16
@export var smoke_on_burn_out := true
## World ticks between re-counts of every burning area (fixes areas whose cells
## were blown away or carried off by a collapse). 0 = signals only.
@export var fire_check_ticks := 15

@export_group("Chain reactions (Pro)")
@export var fuse_on_schedule := true
@export var puff_on_fizzle := true
## Chains that destroyed at least this many cells end with settling dust and smoke.
@export var finale_cells := 120
## Hit-stop (seconds) for the first blast of radius >= radius_large in each
## chain. 0 = off (the hook never takes the game's own hitstop claim).
@export_range(0.0, 0.3) var hit_stop_big_blast := 0.0

const SUB := 256

var _world: Node
var _warned := {}
var _fire: Object
var _chain: Object
var _areas := {}  # Vector2i -> {"n": int, "h": VCHandle, "big": bool, "pos": Vector2 (local)}
var _ticks := 0
var _last_det: Variant = null  # the det dictionary detonated() last played (dedupe with blast_fired)
var _chains := {}  # chain id -> {"sum": Vector2, "n": int, "stopped": bool}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	bind(get_node_or_null(world_path) if not world_path.is_empty() else get_parent())


## Connects to `world`. Called from _ready(); call it again to switch worlds.
func bind(world: Node) -> void:
	unbind()
	if world == null:
		_warn("world", "VCHookDestruction: no world at '%s'; the hook does nothing." % world_path)
		return
	_world = world
	_connect(&"detonated", _on_detonated)
	_connect(&"cells_destroyed", _on_cells_destroyed)
	_connect(&"piece_detached", _on_piece_detached)
	_connect(&"piece_landed", _on_piece_landed)
	if _world.has_signal(&"ticked") and not _world.is_connected(&"ticked", _on_ticked):
		_world.connect(&"ticked", _on_ticked)
	_discover_pro()


## Connects a fire module (DKFire or anything with its signals). Optional:
## the hook finds the world's "fire" extension by itself.
func bind_fire(fire: Object) -> void:
	_unbind_fire()
	_fire = fire
	if fire == null:
		return
	for pair: Array in _fire_pairs():
		if fire.has_signal(pair[0]) and not fire.is_connected(pair[0], pair[1]):
			fire.connect(pair[0], pair[1])


## Connects a chain reactor (DKChainReactor or anything with its signals).
## Optional: the hook finds the world's detonation router by itself.
func bind_chain(chain: Object) -> void:
	_unbind_chain()
	_chain = chain
	if chain == null:
		return
	for pair: Array in _chain_pairs():
		if chain.has_signal(pair[0]) and not chain.is_connected(pair[0], pair[1]):
			chain.connect(pair[0], pair[1])


func unbind() -> void:
	_unbind_fire()
	_unbind_chain()
	_stop_fires()
	_chains.clear()
	_last_det = null
	if _world == null or not is_instance_valid(_world):
		_world = null
		return
	if _world.has_signal(&"ticked") and _world.is_connected(&"ticked", _on_ticked):
		_world.disconnect(&"ticked", _on_ticked)
	for pair: Array in [[&"detonated", _on_detonated], [&"cells_destroyed", _on_cells_destroyed],
			[&"piece_detached", _on_piece_detached], [&"piece_landed", _on_piece_landed]]:
		if _world.has_signal(pair[0]) and _world.is_connected(pair[0], pair[1]):
			_world.disconnect(pair[0], pair[1])
	_world = null


func _connect(sig: StringName, cb: Callable) -> void:
	if not _world.has_signal(sig):
		_warn(String(sig), "VCHookDestruction: '%s' has no signal '%s'; skipped." % [_world.name, sig])
		return
	if not _world.is_connected(sig, cb):
		_world.connect(sig, cb)


func _fire_pairs() -> Array:
	return [[&"cell_ignited", _on_cell_ignited], [&"cell_burnt_out", _on_cell_burnt_out],
		[&"trigger_ignited", _on_trigger_ignited]]


func _chain_pairs() -> Array:
	return [[&"blast_scheduled", _on_blast_scheduled], [&"blast_fired", _on_blast_fired],
		[&"blast_fizzled", _on_blast_fizzled], [&"chain_finished", _on_chain_finished]]


func _unbind_fire() -> void:
	if _fire != null and is_instance_valid(_fire):
		for pair: Array in _fire_pairs():
			if _fire.has_signal(pair[0]) and _fire.is_connected(pair[0], pair[1]):
				_fire.disconnect(pair[0], pair[1])
	_fire = null


func _unbind_chain() -> void:
	if _chain != null and is_instance_valid(_chain):
		for pair: Array in _chain_pairs():
			if _chain.has_signal(pair[0]) and _chain.is_connected(pair[0], pair[1]):
				_chain.disconnect(pair[0], pair[1])
	_chain = null


## Finds Pro modules the world knows about (they may be attached after the
## hook's _ready, so this runs again on the first world ticks).
func _discover_pro() -> void:
	if _world == null:
		return
	if _fire == null and _world.has_method(&"get_extension"):
		var f: Variant = _world.get_extension(&"fire")
		if f is Object and f.has_signal(&"cell_ignited"):
			bind_fire(f)
	if _chain == null and _world.has_method(&"get_detonation_router"):
		var c: Variant = _world.get_detonation_router()
		if c is Object and c.has_signal(&"blast_fired"):
			bind_chain(c)


# --- handlers ---------------------------------------------------------------

func _on_detonated(det: Dictionary, _report: Variant = null) -> void:
	if not enabled:
		return
	_last_det = det
	_play_blast(det)


func _play_blast(det: Dictionary) -> void:
	var pos := _to_global(det.get("pos", Vector2.ZERO))
	var radius: float = float(det.get("radius", radius_reference)) * _cell_scale()
	var ratio := radius / maxf(radius_reference, 1.0)
	if explode_on_detonation:
		var id := &"explosion_small"
		var sc := ratio
		if radius >= radius_large and VfxCore.has(&"explosion_large"):
			id = &"explosion_large"
			sc = radius / radius_large
		elif radius >= radius_medium and VfxCore.has(&"explosion_medium"):
			id = &"explosion_medium"
			sc = radius / radius_medium
		_play(id, pos, {"scale": clampf(sc, 0.4, 3.0)})
	if ring_on_detonation:
		_play(&"shock_ring", pos, {"scale": clampf(ratio, 0.4, 3.0)})
		if radius >= radius_large and VfxCore.has(&"shockwave_distort"):
			_play(&"shockwave_distort", pos, {"scale": clampf(radius / radius_large, 0.5, 3.0)})
	if shake_trauma > 0.0:
		shake_requested.emit(clampf(shake_trauma * ratio, shake_min, shake_max))


func _on_cells_destroyed(report: Variant) -> void:
	if not enabled or not debris_on_cells or report == null:
		return
	var cells: PackedInt32Array = report.get("destroyed") if "destroyed" in report else PackedInt32Array()
	if cells.is_empty():
		return
	var mats: Variant = report.get("destroyed_mat") if "destroyed_mat" in report else null
	# group destroyed cells by material index: [sum_x, sum_y, count]
	var groups := {}
	for k in cells.size():
		var mi := int(mats[k]) if mats != null and k < mats.size() else -1
		var c := _cell_center(cells[k])
		var g: Array = groups.get(mi, [0.0, 0.0, 0])
		g[0] += c.x
		g[1] += c.y
		g[2] += 1
		groups[mi] = g
	var order := groups.keys()
	order.sort_custom(func(a, b): return groups[a][2] > groups[b][2])
	for n in mini(order.size(), max_debris_per_event):
		var mi: int = order[n]
		var g: Array = groups[mi]
		var count: int = g[2]
		var centre := Vector2(g[0] / count, g[1] / count)
		var mat: Variant = _material(mi)
		var mat_id: StringName = mat.id if mat != null and "id" in mat else &""
		var id: StringName = debris_map.get(mat_id, debris_default)
		var opts := {"intensity": clampf(count / maxf(cells_per_intensity, 1.0), 0.25, 2.0)}
		if not VfxCore.has(id):
			id = debris_default
			if tint_fallback_debris and mat != null and "debris_color" in mat:
				opts["color"] = mat.debris_color
		_play(id, _to_global(centre), opts)


func _on_piece_detached(piece: Dictionary) -> void:
	if not enabled or not crumble_on_detach:
		return
	var r := _piece_rect(piece)
	var w_cells := maxf(float(piece.get("w", 1)), 1.0)
	var node: Variant = piece.get("node")
	if trail_on_detach and node is Node2D and is_instance_valid(node) and (node as Node2D).is_inside_tree() \
			and VfxCore.has(&"dust_trail_falling"):
		VfxCore.play_attached(&"dust_trail_falling", node)
		played.emit(&"dust_trail_falling", (node as Node2D).global_position)
	if VfxCore.has(&"crumble_pebbles"):
		_play(&"crumble_pebbles", _to_global(Vector2(r.get_center().x, r.end.y)), {"scale": clampf(w_cells / 8.0, 0.5, 2.0)})
	else:
		_play(&"debris_stone", _to_global(Vector2(r.get_center().x, r.end.y)),
				{"intensity": 0.35, "scale": clampf(w_cells / 12.0, 0.5, 1.5)})


func _on_piece_landed(piece: Dictionary, _crush: Variant = null, impact: int = 0) -> void:
	if not enabled or not dust_on_land:
		return
	var r := _piece_rect(piece)
	var ground := _to_global(Vector2(r.get_center().x, r.end.y))
	var force := clampf(float(impact) / maxf(impact_reference, 1.0), 0.3, 2.0)
	var width_px := r.size.x * _global_scale()
	var sc := clampf(width_px / 96.0, 0.5, 3.0)
	var id := &"dust_impact_ground" if VfxCore.has(&"dust_impact_ground") else &"dust_puff"
	_play(id, ground, {"scale": sc, "intensity": force})
	if _cell_count(piece) >= collapse_cells:
		if VfxCore.has(&"dust_collapse_cloud"):
			_play(&"dust_collapse_cloud", ground, {"scale": sc})
		else:
			_play(&"smoke_puff", ground, {"scale": sc * 1.2, "intensity": 0.8})


# --- Pro: fire -------------------------------------------------------------

func _on_ticked(_tick: int = 0) -> void:
	_ticks += 1
	if _ticks <= 3 and (_fire == null or _chain == null):
		_discover_pro()
	if fire_check_ticks > 0 and _ticks % fire_check_ticks == 0 and not _areas.is_empty():
		_recount_fires()


func _area_of(cell: int) -> Vector2i:
	var c := _cell_center(cell)
	var a := maxf(fire_area_px, 1.0)
	return Vector2i(floori(c.x / a), floori(c.y / a))


func _area_rect(k: Vector2i) -> Rect2:
	var a := maxf(fire_area_px, 1.0)
	return Rect2(Vector2(k) * a, Vector2(a, a))


func _on_cell_ignited(cell: int, _inst: int = 0) -> void:
	if not enabled or not fire_on_ignite:
		return
	var k := _area_of(cell)
	var ar: Dictionary = _areas.get(k, {})
	if ar.is_empty():
		if _areas.size() >= max_fires:
			return
		ar = {"n": 0, "h": null, "big": false, "pos": _cell_center(cell)}
		_areas[k] = ar
	ar["n"] = int(ar["n"]) + 1
	_update_fire(k, ar)


func _on_cell_burnt_out(cell: int, _mat: int = 0, _inst: int = 0) -> void:
	var k := _area_of(cell)
	if not _areas.has(k):
		return
	var ar: Dictionary = _areas[k]
	ar["n"] = int(ar["n"]) - 1
	if int(ar["n"]) <= 0:
		_put_out(k)


func _on_trigger_ignited(trigger_id: int, _inst: int = 0) -> void:
	if not enabled or not fuse_on_schedule:
		return
	var pos: Variant = _trigger_pos(trigger_id)
	if pos != null:
		_play(_fuse_id(), _to_global(pos), {"scale": 0.6})


func _update_fire(k: Vector2i, ar: Dictionary) -> void:
	var big := int(ar["n"]) >= fire_large_cells and VfxCore.has(&"fire_large")
	var h: Variant = ar["h"]
	if h != null and h.is_alive() and big == bool(ar["big"]):
		return
	var id := &"fire_large" if big else &"fire_small"
	if not VfxCore.has(id):
		return
	if h != null and h.is_alive():
		h.stop()
	var pos := _to_global(ar["pos"])
	ar["h"] = VfxCore.play(id, pos, {"scale": clampf(fire_area_px / 24.0, 0.5, 2.0) * _global_scale()})
	ar["big"] = big
	played.emit(id, pos)


func _put_out(k: Vector2i) -> void:
	var ar: Dictionary = _areas[k]
	_areas.erase(k)
	var h: Variant = ar["h"]
	if h != null and h.is_alive():
		h.stop()
	if enabled and smoke_on_burn_out:
		var pos := _to_global(ar["pos"])
		_play(&"smoke_puff", pos, {"scale": 0.8 if bool(ar["big"]) else 0.5, "intensity": 0.6})
		if VfxCore.has(&"embers_rising"):
			_play(&"embers_rising", pos, {"intensity": 0.5})


func _recount_fires() -> void:
	if _fire == null or not is_instance_valid(_fire) or not _fire.has_method(&"burning_in_rect"):
		return
	for k: Vector2i in _areas.keys():
		var ar: Dictionary = _areas[k]
		ar["n"] = (_fire.burning_in_rect(_area_rect(k)) as PackedInt32Array).size()
		if int(ar["n"]) <= 0:
			_put_out(k)
		else:
			_update_fire(k, ar)


func _stop_fires() -> void:
	for ar: Dictionary in _areas.values():
		var h: Variant = ar["h"]
		if h != null and h.is_alive():
			h.stop()
	_areas.clear()


## Looping fires the hook is playing now.
func fire_count() -> int:
	return _areas.size()


# --- Pro: chain reactions ---------------------------------------------------

func _fuse_id() -> StringName:
	return &"sparks_short_circuit" if VfxCore.has(&"sparks_short_circuit") else &"hit_spark"


func _on_blast_scheduled(event: Dictionary) -> void:
	if not enabled or not fuse_on_schedule:
		return
	var now: Variant = _chain.get("tick_count") if _chain != null and is_instance_valid(_chain) else null
	if now != null and int(event.get("due", 0)) <= int(now):
		return  # fires this tick: the blast itself is the effect
	_play(_fuse_id(), _to_global(event.get("pos", Vector2.ZERO)), {"scale": 0.5})


func _on_blast_fired(event: Dictionary, _report: Variant = null) -> void:
	if not enabled:
		return
	if not is_same(event, _last_det):
		_play_blast(event)  # a router whose world did not emit detonated
	_last_det = null
	var chain := int(event.get("chain", -1))
	var st: Dictionary = _chains.get(chain, {"sum": Vector2.ZERO, "n": 0, "stopped": false})
	st["sum"] += Vector2(event.get("pos", Vector2.ZERO))
	st["n"] += 1
	_chains[chain] = st
	var radius := float(event.get("radius", 0.0)) * _cell_scale()
	if hit_stop_big_blast > 0.0 and radius >= radius_large and not st["stopped"]:
		st["stopped"] = true
		VfxCore.hit_stop(hit_stop_big_blast)


func _on_blast_fizzled(event: Dictionary) -> void:
	if enabled and puff_on_fizzle:
		_play(&"smoke_puff", _to_global(event.get("pos", Vector2.ZERO)), {"scale": 0.5, "intensity": 0.5})


func _on_chain_finished(stats: Dictionary) -> void:
	var chain := int(stats.get("chain", -1))
	var st: Dictionary = _chains.get(chain, {})
	_chains.erase(chain)
	if not enabled or int(stats.get("destroyed", 0)) < finale_cells or int(st.get("n", 0)) == 0:
		return
	var pos := _to_global(st["sum"] / float(st["n"]))
	var sc := clampf(float(stats.get("destroyed", 0)) / (finale_cells * 2.0), 0.8, 2.5)
	_play(&"dust_settle" if VfxCore.has(&"dust_settle") else &"dust_puff", pos, {"scale": sc})
	if VfxCore.has(&"smoke_lingering"):
		_play(&"smoke_lingering", pos, {"scale": sc})


func _trigger_pos(id: int) -> Variant:
	if _chain == null or not is_instance_valid(_chain) or not _chain.has_method(&"get_triggers"):
		return null
	var t: Variant = (_chain.get_triggers() as Dictionary).get(id)
	return t.get("pos") if t is Dictionary else null


# --- world helpers (duck-typed) --------------------------------------------

func _play(id: StringName, pos: Vector2, opts: Dictionary) -> void:
	if debris_on_world_floor and not opts.has("floor_y"):
		var fy: Variant = _floor_below(pos)
		if fy != null:
			opts["floor_y"] = fy
	VfxCore.play(id, pos, opts)
	played.emit(id, pos)


func _to_global(p: Variant) -> Vector2:
	var v := Vector2(p) if p is Vector2 or p is Vector2i else Vector2.ZERO
	return _world.to_global(v) if _world is Node2D else v


func _global_scale() -> float:
	return absf((_world as Node2D).global_scale.x) if _world is Node2D else 1.0


func _cell_scale() -> float:
	return _global_scale()


func _cell_px() -> int:
	var grid: Variant = _world.get("grid") if _world != null else null
	return int(grid.cell_px) if grid != null and "cell_px" in grid else 4


func _cell_center(i: int) -> Vector2:
	var grid: Variant = _world.get("grid")
	if grid != null and grid.has_method("cell_center") and grid.has_method("coord"):
		return grid.cell_center(grid.coord(i))
	var w := int(grid.width) if grid != null and "width" in grid else 1
	var cp := _cell_px()
	return Vector2((i % w + 0.5) * cp, (i / w + 0.5) * cp)


func _material(i: int) -> Variant:
	if i < 0:
		return null
	var mats: Variant = _world.get("materials")
	return mats.at(i) if mats != null and mats.has_method("at") else null


## Number of cells in a piece ("cells" is a cell list in DK, or a count).
func _cell_count(p: Dictionary) -> int:
	var c: Variant = p.get("cells")
	if c is int or c is float:
		return int(c)
	if c is Array or c is PackedInt32Array or c is PackedInt64Array:
		return c.size()
	return int(p.get("w", 1)) * int(p.get("h", 1))


func _piece_rect(p: Dictionary) -> Rect2:
	var cp := float(_cell_px())
	return Rect2(float(p.get("x0", 0)) * cp, float(p.get("y0", 0)) * cp + float(p.get("fy", 0)) * cp / SUB,
			float(p.get("w", 1)) * cp, float(p.get("h", 1)) * cp)


func _warn(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(msg)


## Global y of the top of the first solid cell below `global_pos` (out of the
## solid it starts in first, so a blast inside a wall lands on the floor below
## it), or null when the world has no usable grid or nothing solid is near.
func _floor_below(global_pos: Vector2) -> Variant:
	var g: Object = _world.get(&"grid") if _world != null else null
	if g == null or not g.has_method(&"world_to_cell") or not g.has_method(&"is_solid") or not g.has_method(&"in_bounds"):
		return null
	var local := (_world as Node2D).to_local(global_pos) if _world is Node2D else global_pos
	var c: Vector2i = g.world_to_cell(local)
	if not g.in_bounds(c):
		return null
	var n := 0
	while n < floor_scan_cells and g.in_bounds(c) and g.is_solid(c):
		c.y += 1
		n += 1
	while n < floor_scan_cells and g.in_bounds(c) and not g.is_solid(c):
		c.y += 1
		n += 1
	if n >= floor_scan_cells or not g.in_bounds(c):
		return null
	var px := float(g.get(&"cell_px"))
	var top := Vector2(local.x, float(c.y) * px)
	return (_world as Node2D).to_global(top).y if _world is Node2D else top.y
