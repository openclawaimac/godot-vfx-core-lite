// VFX Core 2D: the ring for light backgrounds. Normal blending: the
// band keeps its colour and a thin dark rim runs outside the leading edge, so
// a white or pale ring stays readable on a bright scene.
shader_type canvas_item;
render_mode blend_mix;
#include "res://addons/vfx_core/shaders/vc_common.gdshaderinc"
#include "res://addons/vfx_core/shaders/vc_ring.gdshaderinc"

uniform float rim_strength = 0.75;

void vertex() {
	vc_vcol = COLOR;
}

void fragment() {
	vec2 a = vc_ring_terms(UV, FRAGCOORD.xy);
	float band = a.x;
	float rim = a.y * rim_strength * (1.0 - band);
	vec3 dark = vc_vcol.rgb * 0.18;
	float tot = clamp(band + rim, 0.0, 1.0);
	vec3 rgb = mix(dark, vc_vcol.rgb, band / max(band + rim, 0.001));
	COLOR = vc_shade(vec4(1.0, 1.0, 1.0, 1.0), vec4(rgb, vc_vcol.a * tot), FRAGCOORD.xy);
}
