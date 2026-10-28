// VFX Core 2D: alpha-blended sprites and particles (smoke, dust, debris).
shader_type canvas_item;
render_mode blend_mix;
#include "res://addons/vfx_core/shaders/vc_common.gdshaderinc"

void vertex() {
	vc_vcol = COLOR;
}

void fragment() {
	vec4 t = texture(TEXTURE, vc_snap_uv(UV, FRAGCOORD.xy));
	COLOR = vc_shade(t, vc_vcol, FRAGCOORD.xy);
}
