class_name VCMaterials
extends RefCounted
## Shared ShaderMaterials for particle and sprite layers, cached by
## (blend, shade, pixel size), so playing an effect never creates a material.

## MIX: normal alpha blending. ADD: additive glow (reads on dark scenes).
## LIGHT_BG: what ADD layers become when an effect plays with `light_bg`:
## normal blending with a darkened soft fringe, so white glows keep a dark
## outline on bright backgrounds instead of washing out.
enum Blend { MIX, ADD, LIGHT_BG }
enum Shade { FLAT, LIT, HEAT }

const SHADER_MIX := preload("res://addons/vfx_core/shaders/vc_sprite_mix.gdshader")
const SHADER_ADD := preload("res://addons/vfx_core/shaders/vc_sprite_add.gdshader")
const SHADER_RING := preload("res://addons/vfx_core/shaders/vc_ring.gdshader")
const SHADER_RING_MIX := preload("res://addons/vfx_core/shaders/vc_ring_mix.gdshader")
const SHADER_DISTORT := preload("res://addons/vfx_core/shaders/vc_distort.gdshader")
const NOISE := preload("res://addons/vfx_core/textures/vc_noise.png")

static var _cache: Dictionary = {}


## `pixel` is the pixel block size in screen pixels; 0 = smooth style.
static func get_material(blend: int, shade: int, pixel: int) -> ShaderMaterial:
	var key := blend * 1000 + shade * 100 + pixel
	var m: ShaderMaterial = _cache.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = SHADER_ADD if blend == Blend.ADD else SHADER_MIX
		m.set_shader_parameter(&"edge_dark", 1.0 if blend == Blend.LIGHT_BG else 0.0)
		m.set_shader_parameter(&"pixel_size", float(pixel))
		m.set_shader_parameter(&"shade_mode", shade)
		_cache[key] = m
	return m


## A ring needs per-instance uniforms, so each ring layer owns one material.
## `kind`: 0 = additive ring, 1 = light-background ring (normal blending with a
## dark rim), 2 = screen-space refraction ring (distortion).
static func new_ring_material(kind := 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = [SHADER_RING, SHADER_RING_MIX, SHADER_DISTORT][clampi(kind, 0, 2)]
	m.set_shader_parameter(&"noise_tex", NOISE)
	return m


static func cached_count() -> int:
	return _cache.size()
