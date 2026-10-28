class_name VCLayerUtil
extends RefCounted
## Helpers shared by the layer scripts.
##
## Layer contract (duck-typed, every layer implements all of these):
##   _vc_setup(effect)                 once, when the effect enters the tree
##   _vc_configure(effect, amount, px) per play, after parameters are resolved
##   _vc_begin()                       timeline starts
##   _vc_update(t, dt)                 every frame (t, dt already speed-scaled)
##   _vc_stop()                        loop asked to stop: stop emitting
##   _vc_end()                         effect finished: hide and reset
##   vc_base_amount() -> int           particles at intensity 1
##   vc_end_time() -> float            last visible moment, at speed 1


## Builds the points of `g` once (cold path): one point per alpha key.
static func init_ramp(g: Gradient, alpha_pts: PackedVector2Array) -> void:
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for p in alpha_pts:
		offs.append(clampf(p.x, 0.0, 1.0))
		cols.append(Color(1, 1, 1, p.y))
	if offs.is_empty():
		offs = PackedFloat32Array([0.0, 1.0])
		cols = PackedColorArray([Color.WHITE, Color.WHITE])
	g.offsets = offs
	g.colors = cols


## Recolours the existing points of `g` in place (no allocation).
static func fill_ramp(g: Gradient, e: VCEffect2D, own: PackedColorArray, alpha_pts: PackedVector2Array,
		pal_from: float, pal_to: float, brightness: float, tint: float) -> void:
	var n := mini(g.get_point_count(), alpha_pts.size())
	for i in n:
		var p := alpha_pts[i]
		var c := e.layer_color(own, lerpf(pal_from, pal_to, p.x), tint)
		var b := brightness * e.bright
		g.set_color(i, Color(c.r * b, c.g * b, c.b * b, c.a * p.y * e.alpha_mul))


## Piecewise-linear lookup in (t, value) keys sorted by t.
static func eval_keys(pts: PackedVector2Array, t: float) -> float:
	if pts.is_empty():
		return 1.0
	if t <= pts[0].x:
		return pts[0].y
	for i in range(1, pts.size()):
		if t <= pts[i].x:
			var a := pts[i - 1]
			var b := pts[i]
			return lerpf(a.y, b.y, (t - a.x) / maxf(b.x - a.x, 0.0001))
	return pts[pts.size() - 1].y


## Picks the material for a layer; additive layers follow light-background mode.
static func style(item: CanvasItem, e: VCEffect2D, blend: int, shade: int, px: int) -> void:
	apply_style(item, e.blend_for(blend), shade, px)


static func apply_style(item: CanvasItem, blend: int, shade: int, px: int) -> void:
	item.material = VCMaterials.get_material(blend, shade, px)
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if px > 0 else CanvasItem.TEXTURE_FILTER_LINEAR
