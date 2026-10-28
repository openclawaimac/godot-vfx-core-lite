class_name VCParams
extends RefCounted
## Parameter ranges, defaults and clamping shared by every effect.
## All user input (play() options, presets, handle.set_param) goes through
## these helpers, so an effect never sees an out-of-range or non-finite value.

enum Style { SMOOTH, PIXEL }
enum Priority { LOW, NORMAL, HIGH }
enum SizeClass { S, M, L, NONE }

const SCALE_MIN := 0.1
const SCALE_MAX := 4.0
const INTENSITY_MIN := 0.0
const INTENSITY_MAX := 2.0
const SPEED_MIN := 0.25
const SPEED_MAX := 4.0
const PIXEL_MIN := 1
const PIXEL_MAX := 8

const DEFAULT_SCALE := 1.0
const DEFAULT_INTENSITY := 1.0
const DEFAULT_SPEED := 1.0
const DEFAULT_PIXEL_SIZE := 3

## Particle budget per size class at intensity 1 (sum over all layers).
const CLASS_CAP := {SizeClass.S: 32, SizeClass.M: 64, SizeClass.L: 128, SizeClass.NONE: 32}
## Hard cap per effect at any intensity and scale.
const HARD_CAP := 160
## Maximum layers per effect.
const MAX_LAYERS := 5


## Returns `v` clamped to [lo, hi]; a non-number, NaN or INF gives `def`.
static func clamp_float(v: Variant, lo: float, hi: float, def: float) -> float:
	if not (v is float or v is int):
		return def
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return def
	return clampf(f, lo, hi)


static func clamp_int(v: Variant, lo: int, hi: int, def: int) -> int:
	if v is int:
		return clampi(v, lo, hi)
	if v is float:
		if is_nan(v) or is_inf(v):
			return def
		return clampi(roundi(v), lo, hi)
	return def


static func clamp_scale(v: Variant) -> float:
	return clamp_float(v, SCALE_MIN, SCALE_MAX, DEFAULT_SCALE)


static func clamp_intensity(v: Variant) -> float:
	return clamp_float(v, INTENSITY_MIN, INTENSITY_MAX, DEFAULT_INTENSITY)


static func clamp_speed(v: Variant) -> float:
	return clamp_float(v, SPEED_MIN, SPEED_MAX, DEFAULT_SPEED)


static func clamp_pixel_size(v: Variant) -> int:
	return clamp_int(v, PIXEL_MIN, PIXEL_MAX, DEFAULT_PIXEL_SIZE)


static func clamp_style(v: Variant) -> int:
	if v is StringName or v is String:
		return Style.PIXEL if String(v).to_lower() == "pixel" else Style.SMOOTH
	if (v is int or v is float) and (int(v) == Style.SMOOTH or int(v) == Style.PIXEL) and float(v) == int(v):
		return int(v)
	return Style.SMOOTH


static func clamp_priority(v: Variant, def: int) -> int:
	if v is StringName or v is String:
		match String(v).to_lower():
			"low": return Priority.LOW
			"high": return Priority.HIGH
			"normal": return Priority.NORMAL
		return def
	return clamp_int(v, Priority.LOW, Priority.HIGH, def)


static func color_ok(c: Color) -> bool:
	for k in [c.r, c.g, c.b, c.a]:
		if is_nan(k) or is_inf(k):
			return false
	return true


## Interprets a `color` option. Returns a 3-stop palette (hot, mid, cool) or
## an empty array when the option is unusable. A single Color is a tint:
## the authored palette keeps its brightness ramp and takes the new hue.
static func resolve_palette(opt: Variant, authored: PackedColorArray) -> PackedColorArray:
	if opt is Color:
		if not color_ok(opt):
			return PackedColorArray()
		return tint_palette(authored, opt)
	if opt is PackedColorArray or opt is Array:
		var out := PackedColorArray()
		for c in opt:
			if c is Color and color_ok(c):
				out.append(c)
		if out.size() >= 3:
			return out.slice(0, 3)
		if out.size() == 1:
			return tint_palette(authored, out[0])
		return PackedColorArray()
	if opt is Gradient:
		var g: Gradient = opt
		return PackedColorArray([g.sample(0.0), g.sample(0.5), g.sample(1.0)])
	return PackedColorArray()


## Recolours a palette: each stop keeps its luminance; hot stops stay close
## to white so cores still read as hot.
static func tint_palette(src: PackedColorArray, tint: Color) -> PackedColorArray:
	var out := PackedColorArray()
	var t := Color(tint.r, tint.g, tint.b, 1.0)
	var tl := maxf(0.05, t.get_luminance())
	for c in src:
		var l := c.get_luminance()
		var col := Color(t.r * l / tl, t.g * l / tl, t.b * l / tl, c.a)
		var m := maxf(col.r, maxf(col.g, col.b))
		if m > 1.0:
			col = Color(col.r / m, col.g / m, col.b / m, c.a)
		var hot := smoothstep(0.72, 1.0, l) * 0.65
		col = col.lerp(Color(1, 1, 1, c.a), hot)
		col.a = c.a * tint.a
		out.append(col)
	return out


## Samples a 3-stop palette at x in [0, 1].
static func sample(pal: PackedColorArray, x: float) -> Color:
	if pal.is_empty():
		return Color.WHITE
	if pal.size() == 1:
		return pal[0]
	x = clampf(x, 0.0, 1.0) * (pal.size() - 1)
	var i := mini(int(x), pal.size() - 2)
	return pal[i].lerp(pal[i + 1], x - i)
