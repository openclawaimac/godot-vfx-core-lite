# Quickstart (5 minutes)

1. Copy `addons/vfx_core` into your project.
2. Enable *VFX Core 2D Lite for Godot 4* in *Project Settings → Plugins*. Or add the autoload yourself: name it `VfxCore` and point it at `res://addons/vfx_core/runtime/vfx_core.gd`.
3. Play an effect on click:

   ```gdscript
   func _unhandled_input(event: InputEvent) -> void:
       if event is InputEventMouseButton and event.pressed:
           VfxCore.play(&"explosion_small", get_global_mouse_position())
   ```

4. Change the colour and the size:

   ```gdscript
   VfxCore.play(&"explosion_small", pos, {"color": Color("49c6ff"), "scale": 1.6})
   VfxCore.play(&"coin_burst", pos, {"floor_y": ground_y, "preset": &"pixel"})
   ```

5. Attach an effect to a node, and stop it with its handle:

   ```gdscript
   var h := VfxCore.play_attached(&"smoke_puff", $Enemy, {"offset": Vector2(0, -12)})
   # later
   h.stop()   # looping effects fade out; one-shots end at once
   ```

   The Lite set has no looping effects. Attached one-shots follow the node and stop when it leaves the tree.

6. Add the Destruction hook. Put a `VCHookDestruction` node under your `DKWorld` and it handles the rest:

   ```gdscript
   var hook := VCHookDestruction.new()
   $DKWorld.add_child(hook)
   hook.shake_requested.connect(_on_shake)   # optional: your camera shake, trauma 0..1
   ```

   The tower defense, RTS, factory and survival hooks ship in the full pack (VFX Core 2D for Godot 4).

7. Flash a sprite when it takes a hit:

   ```gdscript
   VfxCore.apply(&"hit_flash", $Sprite2D, {"preset": &"damage"})
   ```

8. Open `demo/demo.tscn` to browse the effects, try the controls and copy the matching code.
