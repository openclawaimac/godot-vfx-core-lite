@tool
class_name VCEffect2D
extends Node2D
## One effect: a root node with up to five layer children (particles, sprites,
## shader quads, lines, bodies). The timeline is pure script: each layer has a
## `delay` and its own life, and VfxCore advances every active effect once
## per frame. No AnimationPlayer is used anywhere.
##
## Normally you never touch this node: VfxCore.play() configures and starts a
## pooled instance. You can also drop an effect scene into a level and tick
## `autoplay`, or tick `editor_preview` to see it in the editor.

## Emitted once when a one-shot ends or a stopped loop has faded out.
signal finished
## Emitted at the end of each `duration` cycle of a looping effect.
signal looped

const GROUP := &"vfx_core_effect"

@export var effect_id: StringName = &""
@export_multiline var description := ""
@export var category: StringName = &""
@export var kit_tags := PackedStringArray()
@export var size_class: VCParams.SizeClass = VCParams.SizeClass.S
@export var looping := false
## One-shot: total length in seconds (at speed 1). Loop: one cycle.
@export var duration := 1.0
## Loops: seconds from stop() until `finished` (lets particles fade).
@export var stop_fade := 0.6
@export var priority: VCParams.Priority = VCParams.Priority.NORMAL
## Authored colour stops: hot, mid, cool.
@export var palette := PackedColorArray([Color.WHITE, Color.GRAY, Color.DIM_GRAY])
## Scale the demo and store captures use so a small effect reads at thumbnail
## size (docs/EFFECTS.md). Gameplay default stays `scale = 1`.
@export var showcase_scale := 1.0
## How the effect is meant to be played (docs, demo): play, play_line,
## play_attached, apply, ui (play_attached on a Control), text or screen.
@export var usage: StringName = &"play"
## Standalone use: start on _ready with the default parameters.
@export var autoplay := false
## Editor only: replays the effect in the 2D editor.
@export var editor_preview := false:
	set(v):
		editor_preview = v
		if Engine.is_editor_hint() and is_inside_tree():
			_preview_t = 0.0
			if v:
				configure(null, {})
				start()
			else:
				kill()

# --- resolved parameters (always clamped) ---
var p_scale := VCParams.DEFAULT_SCALE
var p_intensity := VCParams.DEFAULT_INTENSITY
var p_speed := VCParams.DEFAULT_SPEED
var p_style := VCParams.Style.SMOOTH
var p_pixel_size := VCParams.DEFAULT_PIXEL_SIZE
var p_seed := 0
var p_priority := VCParams.Priority.NORMAL
var p_palette := PackedColorArray()
var p_preset: StringName = &"default"
## True when a preset or the color option replaced the authored palette.
var palette_changed := false
## Particles counted against the global budget at launch (VfxCore).
var budget_count := 0
## Brightness and alpha multipliers derived from intensity.
var bright := 1.0
var alpha_mul := 1.0
## Floor for bodies layers in global Y; NAN = use each layer's floor_offset.
var floor_y_global := NAN
## Distance for line layers (play_line); < 0 = layer default.
var line_length := -1.0
## Light-background mode (preset `light_background` or option `light_bg`):
## additive layers switch to normal blending with a dark fringe/rim.
var p_light_bg := false
## Polyline for bolt layers (chain_lightning), in this node's local space.
## Empty = a straight line along +X of `line_length`.
var points := PackedVector2Array()
## Layer names switched off by the preset (VCPreset.layers_off).
var p_layers_off := PackedStringArray()
## Text for text layers (damage_number), from the `text` option.
var p_text := ""
## Target CanvasItem for material layers (VfxCore.apply).
var apply_target: CanvasItem = null
var follow_target: Node = null
var follow_offset := Vector2.ZERO

# --- runtime state ---
var generation := 0
var time := 0.0
var active := false
var stopping := false
var stop_time := 0.0
var rng := RandomNumberGenerator.new()
var pool: RefCounted = null  # VCPool when pooled
var started_msec := 0

var _layers: Array[Node] = []
var _amounts := PackedInt32Array()
var _particles := 0
var _cycle := 0
var _authored_z := 0
var _authored_rotation := 0.0
var _preview_t := 0.0
var _follow_cb := Callable()


func _ready() -> void:
	add_to_group(GROUP)
	_authored_z = z_index
	_authored_rotation = rotation
	_collect_layers()
	if Engine.is_editor_hint():
		set_process(true)
		return
	set_process(pool == null)
	if autoplay and pool == null:
		configure(null, {})
		start()


func _collect_layers() -> void:
	_layers.clear()
	for c in get_children():
		if c.has_method(&"_vc_update"):
			_layers.append(c)
			c._vc_setup(self)
	_amounts.resize(_layers.size())


func _is_off(i: int) -> bool:
	return not p_layers_off.is_empty() and p_layers_off.has(String(_layers[i].name))


func get_layers() -> Array[Node]:
	return _layers


func _process(delta: float) -> void:
	# Pooled effects are advanced by VfxCore; this path is for standalone and
	# editor preview only.
	if Engine.is_editor_hint():
		if editor_preview:
			if active:
				advance(delta)
			else:
				_preview_t += delta
				if _preview_t > 0.6:
					_preview_t = 0.0
					configure(null, {})
					start()
		return
	if active:
		advance(delta)


# ---------------------------------------------------------------- parameters

func reset_params() -> void:
	p_scale = VCParams.DEFAULT_SCALE
	p_intensity = VCParams.DEFAULT_INTENSITY
	p_speed = VCParams.DEFAULT_SPEED
	p_style = VCParams.Style.SMOOTH
	p_pixel_size = VCParams.DEFAULT_PIXEL_SIZE
	p_seed = 0
	p_priority = priority
	p_palette = palette.duplicate()
	p_preset = &"default"
	palette_changed = false
	floor_y_global = NAN
	line_length = -1.0
	p_light_bg = false
	points = PackedVector2Array()
	p_text = ""
	p_layers_off = PackedStringArray()
	apply_target = null
	follow_offset = Vector2.ZERO
	z_index = _authored_z
	rotation = _authored_rotation


## Resets everything, then applies the preset and the play() options.
## Unknown option keys are ignored; values are clamped.
func configure(preset: VCPreset, opts: Dictionary) -> void:
	reset_params()
	if preset != null:
		p_preset = preset.preset_id
		p_scale = VCParams.clamp_scale(preset.scale)
		p_intensity = VCParams.clamp_intensity(preset.intensity)
		p_speed = VCParams.clamp_speed(preset.speed)
		p_style = VCParams.clamp_style(preset.style)
		p_pixel_size = VCParams.clamp_pixel_size(preset.pixel_size)
		p_light_bg = preset.light_background
		p_layers_off = preset.layers_off
		if preset.palette.size() >= 3:
			p_palette = preset.palette.slice(0, 3)
			palette_changed = true
	for k in opts:
		_set_param_raw(StringName(k), opts[k])
	_apply_params()


## Live change from a handle. Returns false for unknown names.
func set_param(param: StringName, value: Variant) -> bool:
	var ok := _set_param_raw(param, value)
	if ok:
		_apply_params(false)
	return ok


func _set_param_raw(k: StringName, v: Variant) -> bool:
	match k:
		&"scale":
			p_scale = VCParams.clamp_scale(v)
		&"intensity":
			p_intensity = VCParams.clamp_intensity(v)
		&"speed":
			p_speed = VCParams.clamp_speed(v)
		&"style":
			p_style = VCParams.clamp_style(v)
		&"pixel_size":
			p_pixel_size = VCParams.clamp_pixel_size(v)
		&"seed":
			p_seed = VCParams.clamp_int(v, -2147483648, 2147483647, 0)
		&"priority":
			p_priority = VCParams.clamp_priority(v, priority)
		&"color", &"palette":
			var pal := VCParams.resolve_palette(v, palette)
			if not pal.is_empty():
				p_palette = pal
				palette_changed = true
		&"direction", &"normal":
			if v is Vector2 and v.is_finite() and v != Vector2.ZERO:
				rotation = v.angle()
			elif (v is float or v is int) and is_finite(float(v)):
				rotation = float(v)
		&"rotation":
			if (v is float or v is int) and is_finite(float(v)):
				rotation = float(v)
		&"floor_y":
			if (v is float or v is int) and is_finite(float(v)):
				floor_y_global = float(v)
		&"z_index":
			if v is int:
				z_index = clampi(v, RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX)
		&"offset":
			if v is Vector2 and v.is_finite():
				follow_offset = v
		&"light_bg":
			if v is bool:
				p_light_bg = v
		&"text":
			if v is String or v is StringName or v is int or v is float:
				p_text = str(v).left(32)
		&"preset", &"points":
			pass  # resolved by VfxCore (preset before configure, points after placing)
		_:
			return false
	return true


func _apply_params(reseed := true) -> void:
	scale = Vector2(p_scale, p_scale)
	bright = lerpf(0.55, 1.0, minf(p_intensity, 1.0)) + maxf(p_intensity - 1.0, 0.0) * 0.25
	alpha_mul = clampf(p_intensity * 2.0, 0.0, 1.0)
	if reseed:
		if p_seed != 0:
			rng.seed = hash(p_seed)
		else:
			rng.randomize()
	# particle amounts: intensity scales counts, the hard cap always wins
	var total := 0
	for i in _layers.size():
		var n: int = roundi(_layers[i].vc_base_amount() * p_intensity)
		if _layers[i].vc_base_amount() > 0 and p_intensity > 0.0:
			n = maxi(n, 1)
		if _is_off(i):
			n = 0
		_amounts[i] = n
		total += n
	if total > VCParams.HARD_CAP:
		var k := float(VCParams.HARD_CAP) / total
		total = 0
		for i in _layers.size():
			_amounts[i] = int(floor(_amounts[i] * k))
			total += _amounts[i]
	_particles = total
	var px := p_pixel_size if p_style == VCParams.Style.PIXEL else 0
	for i in _layers.size():
		_layers[i]._vc_configure(self, _amounts[i], px)


## Sum of particles over all layers with the current parameters.
func particle_count() -> int:
	return _particles


## Particles at intensity 1 (what the size-class budget is checked against).
## Particles at intensity 1 with the current preset (layers it switches off
## via VCPreset.layers_off don't count).
func base_particle_count() -> int:
	var n := 0
	for i in _layers.size():
		if not _is_off(i):
			n += _layers[i].vc_base_amount()
	return n


func size_class_cap() -> int:
	return VCParams.CLASS_CAP[size_class]


## Latest time (at speed 1) at which any layer is still visible.
func computed_end_time() -> float:
	var t := 0.0
	for l in _layers:
		t = maxf(t, l.vc_end_time())
	return t


## Palette colour at x (0 = hot, 1 = cool) with the user's colour applied.
## `tint_strength` < 1 keeps part of the authored colour.
func palette_color(x: float, tint_strength := 1.0) -> Color:
	var c := VCParams.sample(p_palette, x)
	if tint_strength < 1.0:
		c = VCParams.sample(palette, x).lerp(c, tint_strength)
	return c


## Colour for a layer. A layer with its own palette (neutral smoke, dust)
## uses it, and leans toward the user's palette only by `tint_strength` when
## a colour or preset palette was given.
func layer_color(own: PackedColorArray, x: float, tint_strength := 1.0) -> Color:
	if own.is_empty():
		return palette_color(x, tint_strength)
	var c := VCParams.sample(own, x)
	if palette_changed and tint_strength > 0.0:
		var u := VCParams.sample(p_palette, x)
		var l := c.get_luminance() / maxf(u.get_luminance(), 0.05)
		c = c.lerp(Color(minf(u.r * l, 1.0), minf(u.g * l, 1.0), minf(u.b * l, 1.0), c.a), tint_strength)
	return c


## Blend a layer should use: additive layers become LIGHT_BG in light mode.
func blend_for(b: int) -> int:
	return VCMaterials.Blend.LIGHT_BG if p_light_bg and b == VCMaterials.Blend.ADD else b


## play_line() distance in local units (undoes the effect scale); < 0 = none.
func local_line_length() -> float:
	return line_length / maxf(p_scale, 0.0001) if line_length >= 0.0 else -1.0


## 1 while running, fading to 0 over `stop_fade` after a loop was stopped.
func fade_mul() -> float:
	return 1.0 - clampf(stop_time / maxf(stop_fade, 0.0001), 0.0, 1.0) if stopping else 1.0


## Re-aims the effect: placed at `from`, rotated toward `to`, line layers span
## the distance. Used by play_line() and VCHandle.set_line() (beams).
func set_line_global(from: Vector2, to: Vector2) -> void:
	global_position = from
	global_rotation = (to - from).angle()
	line_length = from.distance_to(to)


## Sets the bolt polyline from global points (chain_lightning). The effect
## stays where it is; points are stored in local space.
func set_points_global(pts: Variant) -> void:
	points = PackedVector2Array()
	if not (pts is PackedVector2Array or pts is Array):
		return
	var inv := global_transform.affine_inverse()
	for q in pts:
		if q is Vector2 and q.is_finite():
			points.append(inv * q)


# ---------------------------------------------------------------- timeline

func start() -> void:
	time = 0.0
	_cycle = 0
	stopping = false
	stop_time = 0.0
	active = true
	started_msec = Time.get_ticks_msec()
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	for i in _layers.size():
		var l := _layers[i]
		if _is_off(i):
			if l is CanvasItem:
				l.visible = false
				l.set_meta(&"_vc_off", true)
			continue
		if l.has_meta(&"_vc_off"):
			l.remove_meta(&"_vc_off")
			l.visible = true
		l._vc_begin()
	_update_follow()
	advance(0.0)


func advance(dt: float) -> void:
	if not active:
		return
	var d := dt * p_speed
	time += d
	_update_follow()
	if not active:
		return
	for i in _layers.size():
		if not _is_off(i):
			_layers[i]._vc_update(time, d)
	if stopping:
		stop_time += d
		if stop_time >= stop_fade:
			_finish()
	elif looping:
		if time >= duration * (_cycle + 1):
			_cycle += 1
			looped.emit()
	elif time >= duration:
		_finish()


## Loops: stop emitting, fade for `stop_fade`, then finish. One-shots: end now.
func stop() -> void:
	if not active or stopping:
		return
	if not looping:
		_finish()
		return
	stopping = true
	stop_time = 0.0
	for l in _layers:
		l._vc_stop()


## Ends immediately, no fade.
func kill() -> void:
	if active:
		_finish()


func _finish() -> void:
	active = false
	stopping = false
	for l in _layers:
		l._vc_end()
	_unfollow()
	finished.emit()
	if pool != null:
		pool.release(self)
	elif not Engine.is_editor_hint():
		visible = false


# ---------------------------------------------------------------- following

func follow(target: Node, offset := Vector2.ZERO) -> void:
	_unfollow()
	follow_target = target
	follow_offset = offset
	if target != null:
		_follow_cb = _on_follow_exit
		target.tree_exiting.connect(_follow_cb, CONNECT_ONE_SHOT)


func _unfollow() -> void:
	if follow_target != null and is_instance_valid(follow_target) and _follow_cb.is_valid():
		if follow_target.tree_exiting.is_connected(_follow_cb):
			follow_target.tree_exiting.disconnect(_follow_cb)
	follow_target = null
	_follow_cb = Callable()


func _on_follow_exit() -> void:
	follow_target = null
	# hosted in a UI canvas layer that may go away with the target: end now
	if pool != null and get_parent() != pool.root:
		kill()
	else:
		stop()


func _update_follow() -> void:
	if follow_target == null:
		return
	if not is_instance_valid(follow_target) or not follow_target.is_inside_tree():
		follow_target = null
		stop()
		return
	if follow_target is Node2D:
		global_position = (follow_target as Node2D).global_position + follow_offset
	elif follow_target is Control:
		var c := follow_target as Control
		global_position = c.get_global_rect().get_center() + follow_offset


# ---------------------------------------------------------------- helpers

## True when the layer is in pixel style (layers use it to pick filtering).
func is_pixel() -> bool:
	return p_style == VCParams.Style.PIXEL


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if effect_id == &"":
		w.append("effect_id is empty")
	if _layers.size() > VCParams.MAX_LAYERS:
		w.append("more than %d layers" % VCParams.MAX_LAYERS)
	return w
