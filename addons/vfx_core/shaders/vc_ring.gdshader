// VFX Core 2D: procedural expanding ring drawn on one quad.
// The quad covers the ring's outer radius; UV (0..1) maps to [-1, 1].
shader_type canvas_item;
render_mode blend_add;
#include "res://addons/vfx_core/shaders/vc_common.gdshaderinc"
#include "res://addons/vfx_core/shaders/vc_ring.gdshaderinc"

void vertex() {
	vc_vcol = COLOR;
}

void fragment() {
	vec2 a = vc_ring_terms(UV, FRAGCOORD.xy);
	COLOR = vc_shade(vec4(1.0, 1.0, 1.0, a.x), vc_vcol, FRAGCOORD.xy);
}
