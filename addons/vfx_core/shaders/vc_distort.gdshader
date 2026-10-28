// VFX Core 2D: screen-space refraction ring (shockwave). Samples the
// screen behind the quad through hint_screen_texture and pushes it outward
// around the ring band. Works on Compatibility, Mobile and Forward+.
shader_type canvas_item;
render_mode blend_mix;
#include "res://addons/vfx_core/shaders/vc_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float thickness = 0.12;
uniform float progress = 0.0;
uniform float fill = 0.0;
uniform float breakup = 0.2;
// refraction strength in screen pixels at full alpha
uniform float strength = 18.0;

void vertex() {
	vc_vcol = COLOR;
}

void fragment() {
	vec2 uv = vc_snap_uv(UV, FRAGCOORD.xy);
	vec2 p = uv * 2.0 - 1.0;
	float r = length(p);
	float centre = 1.0 - thickness;
	float d = (r - centre) / max(thickness, 0.001);
	float band = exp(-d * d * 2.5) * (1.0 - smoothstep(0.96, 1.0, r));
	float n = texture(noise_tex, vec2(atan(p.y, p.x) / 6.2831853 * 5.0, progress * 0.3)).r;
	band *= mix(1.0, 0.6 + 0.8 * n, breakup);
	vec2 dir = r > 0.0001 ? p / r : vec2(0.0);
	// d < 0 inside the band pulls inward, d > 0 pushes outward: a lens edge
	vec2 off = dir * band * sign(d + 0.0001) * strength * vc_vcol.a * SCREEN_PIXEL_SIZE;
	vec3 c = textureLod(screen_tex, SCREEN_UV - off, 0.0).rgb;
	// a faint highlight on the band so it is visible on flat colour too
	c += vc_vcol.rgb * band * 0.12 * vc_vcol.a;
	COLOR = vec4(c, clamp(band * 4.0, 0.0, 1.0) * step(0.001, vc_vcol.a));
}
