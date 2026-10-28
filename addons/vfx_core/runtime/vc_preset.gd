@tool
class_name VCPreset
extends Resource
## A named look for one effect: palette, scale, intensity, speed and style.
## Stored as presets/<effect_id>/<preset_id>.tres. Values are clamped when
## applied (see VCParams), never when saved.

@export var preset_id: StringName = &"default"
@export_multiline var description := ""
## Three colour stops: hot, mid, cool. Empty = the effect's authored palette.
@export var palette := PackedColorArray()
@export_range(0.1, 4.0, 0.05) var scale := 1.0
@export_range(0.0, 2.0, 0.05) var intensity := 1.0
@export_range(0.25, 4.0, 0.05) var speed := 1.0
@export_enum("Smooth", "Pixel") var style := 0
@export_range(1, 8, 1) var pixel_size := 3
## For bright scenes: additive layers switch to normal blending with a dark
## fringe, rings get a dark rim and hit_flash an outline (same as the play()
## option `light_bg = true`).
@export var light_background := false
## Layer node names this preset switches off: variants of one effect, such as
## pipe_leak's drips versus its steam jet. Empty = every layer plays.
@export var layers_off := PackedStringArray()

@export_group("Pool")
## Instances kept for this effect id. Read from the id's "default" preset when
## the pool is created. 0 = VfxCore.pool_max_per_id (16).
@export_range(0, 64, 1) var max_instances := 0
## When the pool is full, make extra instances instead of recycling the oldest
## one, up to VfxCore.POOL_HARD_CAP (64) and only while the live-particle budget
## has room. Off = recycle at max_instances.
@export var pool_grow := false
