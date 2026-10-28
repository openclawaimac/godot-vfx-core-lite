class_name VCPool
extends RefCounted
## Instances of one effect scene. acquire() reuses a free instance (no
## instantiate() on the warm path). At max_size it either grows by one (when
## `grow` is on, the pool is below hard_cap and the caller says the particle
## budget has room) or recycles the oldest active one-shot (or the oldest loop
## if all are loops). The pool never exceeds hard_cap.

var id: StringName
var scene: PackedScene
var max_size := 16
## Optional bounded growth past max_size (see acquire()).
var grow := false
var hard_cap := 64
var root: Node
var core: Object  # VfxCore; gets _on_released(effect)

var free: Array[VCEffect2D] = []
var active: Array[VCEffect2D] = []
## Counters (stats and tests).
var instantiated := 0
var recycled := 0
## Instances made past max_size by `grow`.
var grown := 0
## Particles at intensity 1 of one instance (from the first instance).
var base_particles := 0


func _init(p_id: StringName, p_scene: PackedScene, p_root: Node, p_max: int, p_core: Object) -> void:
	id = p_id
	scene = p_scene
	root = p_root
	max_size = maxi(1, p_max)
	core = p_core


func size() -> int:
	return free.size() + active.size()


## `budget_ok`: the global particle budget can take one more instance (only
## used to decide growth past max_size).
func acquire(budget_ok := false) -> VCEffect2D:
	var e: VCEffect2D = null
	if not free.is_empty():
		e = free.pop_back()
	elif size() < max_size:
		e = _new_instance()
	elif grow and budget_ok and size() < hard_cap:
		e = _new_instance()
		if e != null:
			grown += 1
	else:
		e = _oldest_for_recycle()
		if e == null:
			return null
		recycled += 1
		e.kill()  # releases into `free`
		e = free.pop_back()
	if e == null:
		return null
	active.append(e)
	return e


## Creates instances until the pool holds `n` (capped at max_size).
func prewarm(n: int) -> int:
	var made := 0
	while size() < mini(n, max_size):
		free.append(_new_instance())
		made += 1
	return made


func release(e: VCEffect2D) -> void:
	e.generation += 1
	var i := active.find(e)
	if i >= 0:
		active.remove_at(i)
	if free.has(e):
		return
	e.visible = false
	e.process_mode = Node.PROCESS_MODE_DISABLED
	if e.get_parent() != root:
		e.get_parent().remove_child(e)
		root.add_child(e)
	free.append(e)
	if core != null:
		core._on_released(e)


func stop_all() -> void:
	for e in active.duplicate():
		e.kill()


## Frees every instance (pool becomes empty).
func clear() -> void:
	stop_all()
	for e in free:
		if is_instance_valid(e):
			e.queue_free()
	free.clear()
	active.clear()


func _new_instance() -> VCEffect2D:
	var n := scene.instantiate()
	var e := n as VCEffect2D
	if e == null:
		push_error("VfxCore: scene for '%s' has no VCEffect2D root" % id)
		n.free()
		return null
	instantiated += 1
	if instantiated == 1:
		for c in e.get_children():
			if c.has_method(&"vc_base_amount"):
				base_particles += c.vc_base_amount()
	e.pool = self
	e.visible = false
	root.add_child(e)
	e.process_mode = Node.PROCESS_MODE_DISABLED
	return e


func _oldest_for_recycle() -> VCEffect2D:
	for e in active:
		if not e.looping:
			return e
	return active[0] if not active.is_empty() else null
