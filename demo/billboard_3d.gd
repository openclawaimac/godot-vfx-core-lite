extends Node3D
## 3D demo (1.1): VFX Core 2D effects on VCBillboard3D cards in a lit 3D scene.
## Everything is built in code. The camera orbits so the pillars pass in front
## of the effects (billboards are depth-tested). Run: F6 on demo/billboard_3d.tscn.
## Space pauses all effects (VfxCore.paused); F toggles 4x fast-forward
## (Engine.time_scale), which effects follow.

const LOOPS := [
	# [effect, position, world size, origin y]
	[&"campfire", Vector3(-0.3, 0.3, 0.0), 4.5, 0.85],
	[&"fire_large", Vector3(-4, 2.0, -2), 4.5, 0.85],
	[&"smoke_column", Vector3(4.5, 1.0, -1), 5.0, 0.9],
]
# ids missing from the installed pack (Lite) are skipped
const BURSTS := [&"explosion_medium", &"hit_spark", &"teleport_in", &"coin_burst",
	&"burst_frost", &"explosion_small", &"burst_heal", &"enemy_death_burst", &"smoke_puff"]
const SPOTS := [Vector3(2.5, 1.2, 2.5), Vector3(-2.5, 1.2, 2.0), Vector3(-1.0, 1.4, -4.0),
	Vector3(3.5, 1.2, -4.0), Vector3(0.0, 2.2, 3.5), Vector3(-5.0, 1.2, 3.0)]

var _t := 0.0
var _next := 0.6
var _n := 0
var _cam: Camera3D
var _pool: Array[VCBillboard3D] = []
var _hud: Label
var _bursts: Array[StringName] = []


func _ready() -> void:
	_build_world()
	for id in BURSTS:
		if VfxCore.has(id):
			_bursts.append(id)
	if _bursts.is_empty():
		_bursts.assign(VfxCore.list())
	for l in LOOPS:
		var bb := _card(l[2], l[3])
		bb.position = l[1]
		if VfxCore.has(l[0]):
			bb.play(l[0], {"seed": 3})
		else:
			bb.origin = Vector2(0.5, 0.5)
			_pool.append(bb)
	for i in SPOTS.size():
		var bb := _card(3.4, 0.5)
		bb.position = SPOTS[i]
		_pool.append(bb)
	_place_camera()


func _card(size_m: float, origin_y: float) -> VCBillboard3D:
	var bb := VCBillboard3D.new()
	bb.world_size = size_m
	bb.viewport_px = 384
	bb.origin = Vector2(0.5, origin_y)
	add_child(bb)
	return bb


func _process(delta: float) -> void:
	if VfxCore.paused:
		return
	_t += delta
	_place_camera()
	if _t >= _next:
		_next += 1.1
		var bb := _pool[_n % _pool.size()]
		bb.play(_bursts[_n % _bursts.size()], {"seed": _n})
		_n += 1


func _unhandled_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_SPACE:
		VfxCore.paused = not VfxCore.paused
	elif k.keycode == KEY_F:
		Engine.time_scale = 1.0 if Engine.time_scale > 1.0 else 4.0
	_hud.text = _hud_text()


func _hud_text() -> String:
	return "Space: pause effects%s   F: fast-forward%s" % [
		" (on)" if VfxCore.paused else "", " (4x)" if Engine.time_scale > 1.0 else ""]


func _place_camera() -> void:
	var a := 0.4 + _t * 0.3
	var r := 9.5 + sin(_t * 0.4) * 1.2
	_cam.position = Vector3(cos(a) * r, 3.4 + sin(_t * 0.3) * 0.6, sin(a) * r)
	_cam.look_at(Vector3(0, 1.2, 0))


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.11, 0.13, 0.19)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.72)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	ground.material_override = _mat(Color(0.24, 0.27, 0.22))
	add_child(ground)
	var boxes := [[Vector3(-4, 1.0, -2), Vector3(2, 2, 2), Color(0.38, 0.4, 0.45)],
		[Vector3(4.5, 0.5, -1), Vector3(1, 1, 3), Color(0.4, 0.27, 0.25)],
		[Vector3(1.6, 1.6, 0.4), Vector3(0.6, 3.2, 0.6), Color(0.45, 0.42, 0.36)],
		[Vector3(-1.4, 1.6, -1.2), Vector3(0.6, 3.2, 0.6), Color(0.45, 0.42, 0.36)],
		[Vector3(0.2, 1.6, 2.0), Vector3(0.6, 3.2, 0.6), Color(0.45, 0.42, 0.36)],
		[Vector3(-0.3, 0.25, 0.0), Vector3(1.6, 0.1, 1.6), Color(0.3, 0.3, 0.32)]]
	for b in boxes:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[1]
		mi.mesh = bm
		mi.position = b[0]
		mi.material_override = _mat(b[2])
		add_child(mi)
	_cam = Camera3D.new()
	_cam.fov = 55
	add_child(_cam)
	_cam.current = true
	var ui := CanvasLayer.new()
	add_child(ui)
	var title := _label(ui, 34, Vector2(28, 18))
	title.text = "VFX Core 2D 1.1 · VCBillboard3D"
	var note := _label(ui, 22, Vector2(28, 64))
	note.text = "2D effects on depth-tested billboards in a 3D scene. Pillars hide them; cards face the camera."
	_hud = _label(ui, 18, Vector2(28, 100))
	_hud.text = _hud_text()


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _label(ui: CanvasLayer, px: int, at: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", Color(0.97, 0.97, 0.98))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 7)
	l.position = at
	ui.add_child(l)
	return l
