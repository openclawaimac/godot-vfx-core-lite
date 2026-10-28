// VFX Core 2D: additive sprites and particles (flashes, fire, sparks).
shader_type canvas_item;
render_mode blend_add;
#include "res://addons/vfx_core/shaders/vc_common.gdshaderinc"

void vertex() {
	vc_vcol = COLOR;
}

void fragment() {
	vec4 t = texture(TEXTURE, vc_snap_uv(UV, FRAGCOORD.xy));
	// blend_add already weights the source by alpha
	COLOR = vc_shade(t, vc_vcol, FRAGCOORD.xy);
}
