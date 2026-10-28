// VFX Core 2D: ring body shared by vc_ring (additive) and vc_ring_mix
// (light backgrounds). Returns (band strength, haze strength).
uniform sampler2D noise_tex : repeat_enable, filter_linear;
// ring half-thickness as a fraction of the radius
uniform float thickness = 0.12;
// 0..1 life, used to scroll the noise breakup
uniform float progress = 0.0;
// inner haze strength (soft fill inside the ring)
uniform float fill = 0.25;
uniform float breakup = 0.35;

vec2 vc_ring_terms(vec2 UVv, vec2 frag) {
	vec2 uv = vc_snap_uv(UVv, frag);
	vec2 p = uv * 2.0 - 1.0;
	float r = length(p);
	// angular coordinate spans whole noise tiles, so the seam is invisible
	float ang = atan(p.y, p.x) / 6.2831853;
	float n = texture(noise_tex, vec2(ang * 6.0, progress * 0.35)).r;
	float n2 = texture(noise_tex, p * 0.55 + vec2(0.37, progress * 0.25)).r;
	float centre = 1.0 - thickness;
	float d = (r - centre) / max(thickness, 0.001);
	// crisp outer (leading) edge, softer inner (trailing) edge
	float band = d > 0.0 ? exp(-d * d * 4.0) : exp(-d * d * 1.6);
	float lead = 1.0 - smoothstep(0.95, 1.0, r);
	float brk = mix(1.0, smoothstep(0.15, 0.85, n) * 1.7, breakup);
	float haze = smoothstep(0.0, centre, r);
	haze = haze * haze * fill * (0.6 + 0.8 * n2) * (1.0 - progress);
	// dark rim just outside the leading edge (used by the light-background ring)
	float rim = exp(-pow((r - 1.0 + thickness * 0.1) / max(thickness * 0.55, 0.004), 2.0)) * lead;
	return vec2(clamp((band * brk + haze) * lead, 0.0, 1.0), rim * brk);
}
