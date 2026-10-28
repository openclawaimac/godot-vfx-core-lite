// VFX Core 2D: hit flash for VfxCore.apply(). Pushes the target's colour
// toward `tint` by `amount` (0 = untouched, 1 = solid tint) and keeps its alpha,
// so the sprite's silhouette flashes. Works on Sprite2D, AnimatedSprite2D,
// TextureRect and other CanvasItems that draw a texture.
// `outline` > 0 (light-background mode) also draws a dark rim along the
// silhouette edge while the flash is on, so a pale flash still reads on a
// bright scene.
shader_type canvas_item;

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
// colour the flash settles into as `amount` falls (two-tone: a hot peak, then
// a tint); alpha 0 = one colour
uniform vec4 tint_tail : source_color = vec4(1.0, 1.0, 1.0, 0.0);
// 1 = additive: the tint is added on top, so the sprite brightens and keeps
// its detail while the flash fades (default white flash on dark scenes);
// 0 = replace toward the tint (coloured flashes, light-background mode)
uniform float additive : hint_range(0.0, 1.0) = 0.0;
uniform float outline : hint_range(0.0, 1.0) = 0.0;
uniform vec4 outline_color : source_color = vec4(0.12, 0.07, 0.05, 1.0);
uniform float outline_px = 3.0;

// 1 inside the texture rect, 0 outside (so a fully opaque sprite still has an edge)
float vc_in(vec2 uv) {
	vec2 i = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return i.x * i.y;
}

void fragment() {
	vec4 c = COLOR;
	float k = clamp(amount, 0.0, 1.0);
	vec3 col = mix(tint.rgb, mix(tint_tail.rgb, tint.rgb, smoothstep(0.55, 0.9, k)), tint_tail.a);
	vec3 add_rgb = min(c.rgb + col * k * tint.a * 1.15, vec3(1.0));
	c.rgb = mix(mix(c.rgb, col, k * tint.a), add_rgb, additive);
	if (outline > 0.0) {
		vec2 o = TEXTURE_PIXEL_SIZE * outline_px;
		vec2 u1 = UV + vec2(o.x, 0.0);
		vec2 u2 = UV - vec2(o.x, 0.0);
		vec2 u3 = UV + vec2(0.0, o.y);
		vec2 u4 = UV - vec2(0.0, o.y);
		float a1 = texture(TEXTURE, u1).a * vc_in(u1);
		float a2 = texture(TEXTURE, u2).a * vc_in(u2);
		float a3 = texture(TEXTURE, u3).a * vc_in(u3);
		float a4 = texture(TEXTURE, u4).a * vc_in(u4);
		float mn = min(min(a1, a2), min(a3, a4));
		float mx = max(max(a1, a2), max(a3, a4));
		// any texel on the silhouette border (inside or just outside)
		float edge = clamp(max(c.a - mn, mx - c.a) * 2.0, 0.0, 1.0);
		float e = edge * outline * smoothstep(0.0, 0.25, k);
		c.rgb = mix(c.rgb, outline_color.rgb, e);
		c.a = max(c.a, e * outline_color.a);
	}
	COLOR = c;
}
