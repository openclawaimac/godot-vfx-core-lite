@tool
extends EditorPlugin
## Optional: enabling the plugin registers the VfxCore autoload. Adding the
## autoload by hand (res://addons/vfx_core/runtime/vfx_core.gd) works the same.

const AUTOLOAD := "VfxCore"
const PATH := "res://addons/vfx_core/runtime/vfx_core.gd"


func _enable_plugin() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD):
		add_autoload_singleton(AUTOLOAD, PATH)


func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD):
		remove_autoload_singleton(AUTOLOAD)
