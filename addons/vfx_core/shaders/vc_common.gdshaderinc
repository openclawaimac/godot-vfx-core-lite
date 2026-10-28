// VFX Core 2D: shared canvas_item helpers. Written from first principles
// for this pack (no third-party shader code).
//
// pixel_size > 0 switches to pixel style: every fragment samples the texture
// at the centre of a screen-aligned pixel_size block (so all effects share one
// pixel grid), alpha is quantised to five levels with a 4x4 ordered dither and colours are
// posterised.

uniform float pixel_size = 0.0;
// 0 = multiply (glows, smoke), 1 = lit (greyscale shading mapped onto COLOR,
// with a specular lift; used for solid objects like debris and coins),
// 2 = heat (texture luminance is temperature: hot texels lift toward white,
// cool texels keep a darker COLOR; used for fireballs on any background).
uniform int shade_mode = 0;
// > 0 = light-background mode (see VCMaterials.Blend.LIGHT_BG): the soft
// fringe of a glow is darkened and the body is lifted to full opacity, so a
// white flash keeps a dark rim on a bright scene.
uniform float edge_dark = 0.0;

// Godot's fragment COLOR already holds texture * vertex colour. We sample the
// texture ourselves (snapped in pixel style), so each shader copies the
// vertex colour (modulate, particle colour) into this varying in vertex().
varying vec4 vc_vcol;

const float VC_BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

vec2 vc_snap_uv(vec2 uv, vec2 frag) {
	if (pixel_size < 0.5) {
		return uv;
	}
	vec2 cell = (floor(frag / pixel_size) + 0.5) * pixel_size;
	vec2 off = cell - frag;
	return uv + dFdx(uv) * off.x + dFdy(uv) * off.y;
}

float vc_dither(vec2 frag) {
	vec2 c = mod(floor(frag / max(pixel_size, 1.0)), 4.0);
	return (VC_BAYER[int(c.y) * 4 + int(c.x)] + 0.5) / 16.0;
}

vec4 vc_shade(vec4 tex, vec4 col, vec2 frag) {
	vec3 rgb;
	if (shade_mode == 1) {
		float l = tex.r;
		rgb = col.rgb * l * 1.5 + vec3(pow(l, 5.0) * 0.5);
	} else if (shade_mode == 2) {
		float l = tex.r;
		vec3 hot = mix(col.rgb, vec3(1.0, 0.97, 0.9), 0.7);
		rgb = col.rgb * (0.4 + 0.7 * l) + hot * pow(l, 4.0) * 0.75 * col.a;
	} else {
		rgb = col.rgb * tex.rgb;
	}
	float a = col.a * tex.a;
	if (edge_dark > 0.0) {
		float body = smoothstep(0.08, 0.55, tex.a);
		rgb = mix(rgb * 0.22, rgb, body * edge_dark + (1.0 - edge_dark));
		a = col.a * clamp(tex.a * 1.6, 0.0, 1.0);
	}
	if (pixel_size >= 0.5) {
		// five alpha levels, dithered between them; the faintest fringe is cut
		// so thin smoke does not turn into a sparse dot screen
		a = a < 0.07 ? 0.0 : clamp(floor(a * 5.0 + vc_dither(frag)) / 5.0, 0.0, 1.0);
		rgb = floor(rgb * 7.0 + 0.5) / 7.0;
	}
	return vec4(rgb, a);
}
