class_name VCBillboard3D
extends Sprite3D
## Shows VFX Core 2D effects inside a 3D scene. A small transparent SubViewport
## renders the effects; this Sprite3D displays that texture as a camera-facing
## billboard placed in the world, so the effect is depth-tested (walls and units
## in front hide it) and scales with distance like any 3D object.
##
##   var bb := VCBillboard3D.new()
##   bb.world_size = 3.0            # metres covered by the square
##   add_child(bb)
##   bb.position = Vector3(0, 1.5, 0)
##   bb.play(&"explosion_medium")
##
## Effects play through VfxCore.play_attached() on an anchor at the centre of the
## viewport, so pooling, budget, time_scale, paused and suspended all apply.
## Limits (by design, see docs/3D.md): the effect is a flat card. It turns with
## the camera, never lies on the ground, does not light the 3D scene, and is
## clipped at the square's edge. Best for volumetric-looking, roughly round
## effects (explosions, fire, smoke, sparks, magic bursts, pickups).

## Square viewport size in pixels (effect space). Effects authored for ~1080p
## games look right at 256-512.
@export_range(32, 2048) var viewport_px := 384:
	set(v):
		viewport_px = clampi(v, 32, 2048)
		_apply_size()
## World size of the square in metres.
@export var world_size := 3.0:
	set(v):
		world_size = maxf(v, 0.01) if is_finite(v) else 3.0
		_apply_size()
## Where the effect origin sits in the square: (0.5, 0.5) centre, (0.5, 0.85)
## near the bottom for effects that rise (fire, smoke, columns).
@export var origin := Vector2(0.5, 0.5):
	set(v):
		origin = v.clamp(Vector2.ZERO, Vector2.ONE) if v.is_finite() else Vector2(0.5, 0.5)
		_apply_size()

var _vp: SubViewport
var _layer: CanvasLayer
var _anchor: Node2D


func _init() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shaded = false
	transparent = true
	double_sided = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_vp = SubViewport.new()
	_vp.name = "VfxViewport"
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp, false, Node.INTERNAL_MODE_FRONT)
	# play_attached() hosts effects in the target's CanvasLayer, so they draw here
	_layer = CanvasLayer.new()
	_vp.add_child(_layer)
	_anchor = Node2D.new()
	_anchor.name = "Origin"
	_layer.add_child(_anchor)
	_apply_size()


func _ready() -> void:
	texture = _vp.get_texture()


func _apply_size() -> void:
	if _vp == null:
		return
	_vp.size = Vector2i(viewport_px, viewport_px)
	_anchor.position = Vector2(viewport_px, viewport_px) * origin
	pixel_size = world_size / float(viewport_px)
	offset = (Vector2(0.5, 0.5) - origin) * Vector2(viewport_px, -viewport_px)


## Plays effect `id` on this billboard (same options as VfxCore.play; "offset"
## moves it in viewport pixels). Must be in the tree.
func play(id: StringName, opts: Dictionary = {}) -> VCHandle:
	if not is_inside_tree():
		push_error("VCBillboard3D.play: not in the tree")
		return VCHandle.inert(id)
	return VfxCore.play_attached(id, _anchor, opts)


## Stops (loops fade out) or kills every effect on this billboard.
func stop_all(immediate := false) -> void:
	for host in _layer.get_children():
		if host == _anchor:
			continue
		for c in host.get_children():
			if c is VCEffect2D:
				if immediate:
					(c as VCEffect2D).kill()
				else:
					(c as VCEffect2D).stop()


## The SubViewport the effects render into (for custom setups).
func get_viewport_2d() -> SubViewport:
	return _vp

