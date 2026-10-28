# Public API (v1)

> **Lite edition.** Effect ids marked *(Pro only)* ship in the full pack (VFX Core 2D for Godot 4).
> They are not in Lite: `VfxCore.has(id)` returns false for them, and `play()` reports an unknown effect id.

The API below, including the kit hooks, is **frozen for 1.x**: names, argument lists and meanings stay the same.
New methods and options can be added. `tests/core/test_api_freeze.gd` fails if a frozen
method, property or signal is removed or its argument count changes.

## `VfxCore` (autoload)

| call | returns | notes |
|---|---|---|
| `play(id, pos, opts = {})` | `VCHandle` | One effect at a global position. |
| `play_attached(id, target, opts = {})` | `VCHandle` | Follows `target` (with `offset`). It stops by itself when the target leaves the tree. |
| `play_line(id, from, to, opts = {})` | `VCHandle` | Beams, tracers and trails: the effect spans from `from` to `to`. |
| `apply(id, target, opts = {})` | `VCHandle` | Material effects such as `hit_flash` on a CanvasItem. The original material is restored afterwards. |
| `stop_all()` | | Stops and pools every live effect. |
| `warm(id, count = 4)` | `int` | Prewarms the pool. Returns how many instances are ready. |
| `list(filter = &"")` | `Array[StringName]` | All ids, or the ids whose id or category contains `filter`. |
| `has(id)` / `info(id)` / `presets(id)` | | Registry lookups. `info()` returns category, size, loop, duration, priority, particles, apply, usage, showcase_scale, tags, presets and description. |
| `stats()` | `Dictionary` | Active effects, live particles, pools, drops and recycles. |
| `register(id, scene_path, preset_paths = {}, category = &"custom")` / `unregister(id)` | | Add your own effects. |
| `clear_pools()`, `set_pool_max(id, n)`, `set_pool_grow(id, on)` | | Pool control (see `PERFORMANCE.md`). |
| `live_particles()`, `active_effects()` | | Introspection. |
| `step(dt)` | | Advances every effect by `dt` when `manual_step` is on (tests, replays). |
| `shake(trauma, opts = {})` | | Adds camera-shake trauma (0–1, clamped). See "Camera shake and hit-stop" below. |
| `shake_trauma()` | `float` | The current trauma. |
| `hit_stop(seconds = 0.06, scale = 0.02)` | | Freeze-frame. |
| `is_hit_stopped()` | `bool` | |
| `feedback_step(real_dt)` / `stop_feedback()` | | Advance or reset shake and hit-stop by hand (tests, replays). |

Properties: `max_live_particles` (3000), `lights_enabled`, `pool_max_per_id` (16),
`manual_step`, `time_scale` and `clock` (read-only seconds of effect time; it drives the
anti-strobe re-arm of `hit_flash`).

Camera shake: `shake_max_offset` (Vector2(24, 18) px at trauma 1), `shake_decay` (1.6 trauma per second),
`shake_frequency` (18 Hz) and `shake_camera` (a Camera2D; when it is null, the current viewport camera
is used, or the root canvas transform if there is none).

Layering: `layer_z_index` (100), the z_index of the layer that holds world-space effects. The
autoload sits before the main scene in the tree, so at 0 effects would draw under the level. The
`z_index` option of a play is relative to it.

`hit_stop_holds_screen` (false): during `hit_stop()`, full-screen effects (usage `screen`, such as
`screen_flash` *(Pro only)*) keep fading in real time, so a white flash is never held for the whole freeze.
Set it to true to freeze them too.

An unknown id calls `push_error` with the closest id as a suggestion and returns an inert
handle. It never crashes.

## Options (`opts`)

| key | type | range |
|---|---|---|
| `preset` | StringName | an id from `presets(id)`, e.g. `&"light_bg"`, `&"pixel"` |
| `color` | Color or PackedColorArray | tints the palette; an array replaces it |
| `scale` | float | 0.1–4 |
| `intensity` | float | 0–2 (particle count, within the caps) |
| `speed` | float | 0.25–4 |
| `style` / `pixel_size` | `&"smooth"` or `&"pixel"` / 1–8 | |
| `seed` | int | same seed, same result |
| `priority` | `VCParams.Priority` | LOW, NORMAL, HIGH |
| `normal` / `direction` / `rotation` | Vector2 or float | aims the effect |
| `floor_y` | float | global y where debris and coins bounce |
| `offset` | Vector2 | `play_attached` |
| `z_index` | int | relative to `VfxCore.layer_z_index` (100) |
| `light_bg` | bool | additive layers switch to the light-background blend (same as the `light_bg` preset) |
| `points` | Array of global Vector2 | bolt effects such as `chain_lightning` *(Pro only)*, and path effects such as `conveyor_glow` *(Pro only)* and `cable_pulse` *(Pro only)* |
| `text` | String | `damage_number` *(Pro only)*: the text to show, at most 32 characters (longer text is cut) |

Invalid values (NaN, INF, out of range) are clamped or replaced with the default.

### Usage per effect

`info(id)["usage"]` names the call each effect is built for: `play`, `play_line`, `play_attached`,
`ui`, `text`, `screen` or `apply`. `EFFECTS.md` lists it per effect.

- **`ui` effects on a Control** (`play_attached(&"ui_star_pop", button)` *(Pro only)*) are hosted in a `VfxCoreUI`
  Node2D in the Control's CanvasLayer (or the root), not inside the Control. Containers and layouts
  are therefore never changed, and `mouse_filter` stays as it was (the effect itself ignores the mouse).
  When the Control or its HUD is freed, its effects are killed.
- **`screen` effects** (`screen_flash` *(Pro only)*, `chromatic_kick` *(Pro only)*, `damage_vignette` *(Pro only)*, `screen_shake` *(Pro only)*) ignore the position.
- **`showcase_scale`** is the scale the demo's "Showcase size" checkbox and the store captures use
  (S effects 1.5, M 1.15, unless an effect sets its own). Gameplay defaults are always scale 1.

## Camera shake and hit-stop

```gdscript
VfxCore.shake(0.4)                    # trauma; the offset is shake_max_offset * trauma² * smooth noise
VfxCore.shake(0.3, {"pixel_size": 4}) # snap the offset to whole 4 px blocks
VfxCore.hit_stop(0.06)                # 60 ms freeze at Engine.time_scale 0.02, then restore
# VfxCore.play(&"screen_shake", Vector2.ZERO, {"preset": &"impact"})  # shake + short hit-stop  (Pro only)
```

- **Trauma** adds up to at most 1 and falls by `shake_decay` per second. The offset is applied to
  `Camera2D.offset` and removed again, so your own camera offset is kept.
- **Hit-stop** sets `Engine.time_scale` for `seconds` of real time (at most 1 s) and then restores the
  previous value. A new call while one runs extends it and never shortens it. Everything that uses
  `delta` freezes, including effects, so an impact holds on its brightest frame.
- Shake and hit-stop run on unscaled time. `stop_feedback()` resets both at once, for example on a scene change.

## `VCHandle`

| call | notes |
|---|---|
| `id` | the effect id |
| `is_alive()` | false once the effect has finished or been recycled |
| `stop()` | loops fade out; one-shots end early |
| `kill()` | removes the effect at once |
| `set_param(name, value)` | live change of a clamped option (`color`, `intensity`, ...) |
| `set_line(from, to)` | moves a beam or trail (call it every frame for `beam_*`) |
| `set_points(points)` | new polyline for bolt effects (`chain_lightning` *(Pro only)*) |
| `get_effect()` | the `VCEffect2D` while alive; do not keep it, because it is pooled |

Every call on a dead or inert handle is safe and returns `false` or `null`.

## `VCEffect2D`

Signals: `finished` (one-shots), `looped` (each cycle of a loop). Group: `vfx_core_effect`.
A scene can be dragged into the editor and set to `autoplay`.

## `VCOverlay3D`

Plays 2D effects at 3D positions for 3D games (RTS cameras).

| call | notes |
|---|---|
| `camera_path`, `reference_distance`, `min_distance_scale`, `max_distance_scale` | exports |
| `play(id, world_pos, opts = {})` | projects and re-projects every frame; hidden behind the camera |
| `project(world)` / `is_in_front(world)` / `camera()` | helpers |
| `tracked_count()` / `refresh()` | introspection, manual update |

## Hooks

`VCHookDestruction`, `VCHookTowerDefense`, `VCHookRTS`, `VCHookFactory` and `VCHookSurvival`; see
`HOOKS.md`. They share the `played(id, pos)` signal and, where it applies, `shake_requested(trauma)`.
The five hooks are frozen for 1.x: their public methods, exported properties and signals
keep their names and meanings in 1.x; new ones can be added. `test_api_freeze.gd` checks them.
