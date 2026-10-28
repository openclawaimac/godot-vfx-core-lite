extends Node
## Demo browser: every registered effect, its presets and live parameters.
## Click the stage to play the selected effect there. "Copy code" puts the
## matching VfxCore call on the clipboard.
##
## Command line (after `--`):
##   --reel[=stills_dir]  play a scripted tour of every effect, then quit
##                        (record it with --write-movie).
##   --stress=N           start with N effects kept alive (benchmarks).
##   --shot=path.png      save one screenshot mid-play, then quit.

const ACCENT := Color(1.0, 0.56, 0.24)
const PANEL := Color(0.095, 0.105, 0.13, 0.97)
const PANEL_EDGE := Color(1, 1, 1, 0.06)
const TEXT := Color(0.9, 0.91, 0.94)
const TEXT_DIM := Color(0.6, 0.63, 0.7)
const LEFT_W := 260.0
const RIGHT_W := 330.0
const BAR_H := 44.0
const CATEGORY_NAMES := {&"combat": "Combat", &"destruction": "Destruction", &"pickups": "Pickups",
	&"environment": "Environment", &"elements": "Elements", &"magic": "Magic", &"ui": "UI", &"custom": "Custom",
	&"factory": "Factory", &"survival": "Survival", &"screen": "Sprite & screen", &"status": "Status", &"td": "Tower defense"}

var current: StringName = &""
var stage: Control
var background: VCDemoBackground
var tree: Tree
var search: LineEdit
var title_label: Label
var meta_label: Label
var desc_label: Label
var preset_opt: OptionButton
var color_on: CheckBox
var color_btn: ColorPickerButton
var sliders := {}  # name -> HSlider
var style_opt: OptionButton
var bg_opt: OptionButton
var repeat_chk: CheckBox
## Plays small effects at their registry showcase_scale (store readability);
## the code snippet shows the gameplay call (scale 1 unless the slider moved).
var showcase_chk: CheckBox
## Control that `ui` effects attach to (play_attached on a Control).
var ui_target: Button
var code_label: Label
var stats_label: Label
var stress_slider: HSlider
var stress_mix: CheckBox
var items := {}  # id -> TreeItem
## Sprite that apply() effects (hit_flash) act on; shown only while one is selected.
var target: Sprite2D

var _uses_floor := {}  # id -> bool
var _stress: Array[VCHandle] = []
var _repeat_t := 0.0
var _fps_acc := 0.0
var _fps_frames := 0
var _fps := 0.0
var _theme: Theme


func _ready() -> void:
	_theme = _make_theme()
	var back := CanvasLayer.new()
	back.layer = -1
	# follow the canvas transform so screen_shake (no Camera2D in the demo)
	# moves the backdrop with the world
	back.follow_viewport_enabled = true
	add_child(back)
	background = VCDemoBackground.new()
	back.add_child(background)
	target = Sprite2D.new()
	target.name = "ApplyTarget"
	target.texture = load("res://demo/textures/vc_demo_target.png")
	target.visible = false
	add_child(target)
	var front := CanvasLayer.new()
	front.layer = 1
	add_child(front)
	var root := Control.new()
	root.theme = _theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(root)
	_build(root)
	_fill_tree()
	get_viewport().size_changed.connect(_layout_changed)
	_layout_changed.call_deferred()
	var first: StringName = VfxCore.list()[0] if not VfxCore.list().is_empty() else &""
	select(&"explosion_small" if VfxCore.has(&"explosion_small") else first)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--reel"):
			_reel.call_deferred(a.get_slice("=", 1) if "=" in a else "")
		elif a.begins_with("--stress="):
			stress_slider.value = int(a.get_slice("=", 1))
		elif a.begins_with("--shot="):
			_shot.call_deferred(a.get_slice("=", 1))


# --- public (tests and reel) -----------------------------------------------

## Effect ids listed in the browser.
func listed_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in items:
		out.append(id)
	return out


func select(id: StringName) -> void:
	if not VfxCore.has(id):
		return
	current = id
	target.visible = _is_apply(id) or _usage(id) == &"play_attached"
	ui_target.visible = _usage(id) == &"ui"
	var it: TreeItem = items.get(id)
	if it != null and tree.get_selected() != it:
		it.select(0)
		tree.scroll_to_item(it)
	var inf := VfxCore.info(id)
	title_label.text = _pretty(id)
	meta_label.text = "%s  ·  size %s  ·  %d particles  ·  %.2f s%s" % [
		CATEGORY_NAMES.get(inf.get("category", &""), String(inf.get("category", ""))).to_upper(),
		inf.get("size", "?"), int(inf.get("particles", 0)), float(inf.get("duration", 0.0)),
		"  ·  loop" if inf.get("loop", false) else ""]
	desc_label.text = String(inf.get("description", "")).replace("`", "")
	preset_opt.clear()
	for p in VfxCore.presets(id):
		preset_opt.add_item(String(p).capitalize())
		preset_opt.set_item_metadata(preset_opt.item_count - 1, p)
	if preset_opt.item_count == 0:
		preset_opt.add_item("Default")
		preset_opt.set_item_metadata(0, &"default")
	preset_opt.select(0)
	_update_code()


func set_preset(p: StringName) -> void:
	for i in preset_opt.item_count:
		if preset_opt.get_item_metadata(i) == p:
			preset_opt.select(i)
	_update_code()


func set_value(name: String, v: float) -> void:
	sliders[name].value = v


func set_color(c: Variant) -> void:
	color_on.button_pressed = c != null
	if c != null:
		color_btn.color = c
	_update_code()


func set_style_pixel(on: bool) -> void:
	style_opt.select(1 if on else 0)
	_update_code()


func floor_y() -> float:
	return stage.get_global_rect().position.y + stage.size.y * 0.78


func stage_rect() -> Rect2:
	return stage.get_global_rect()


## Plays the selected effect with the current controls at `pos` (canvas space).
func play_at(pos: Vector2) -> VCHandle:
	return _play(current, pos, options())


## The options dictionary for the current controls (what Copy code shows).
func options() -> Dictionary:
	var o := {}
	var p: StringName = preset_opt.get_item_metadata(preset_opt.selected) if preset_opt.selected >= 0 else &"default"
	if p != &"default":
		o["preset"] = p
	if color_on.button_pressed:
		o["color"] = color_btn.color
	for k in ["scale", "intensity", "speed"]:
		if not is_equal_approx(sliders[k].value, 1.0):
			o[k] = snappedf(sliders[k].value, 0.01)
	if style_opt.selected == 1:
		o["style"] = &"pixel"
		o["pixel_size"] = int(sliders["pixel_size"].value)
	return o


# --- UI ----------------------------------------------------------------------

func _build(root: Control) -> void:
	var cols := HBoxContainer.new()
	cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.add_theme_constant_override("separation", 0)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cols)

	# left: header, search, effect list
	var left := _panel(cols, LEFT_W)
	var lv := _vbox(left, 10)
	var brand := Label.new()
	brand.text = "VFX CORE 2D"
	brand.add_theme_font_size_override("font_size", 20)
	brand.add_theme_color_override("font_color", TEXT)
	lv.add_child(brand)
	var sub := Label.new()
	sub.text = "Effect browser"
	sub.add_theme_color_override("font_color", TEXT_DIM)
	lv.add_child(sub)
	search = LineEdit.new()
	search.placeholder_text = "Search effects"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t): _fill_tree())
	lv.add_child(search)
	tree = Tree.new()
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.item_selected.connect(_on_tree_selected)
	tree.item_activated.connect(func(): play_at(stage_rect().get_center()))
	lv.add_child(tree)
	var hint := Label.new()
	hint.text = "Click the stage to play.\nSpace: play at centre."
	hint.add_theme_color_override("font_color", TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 12)
	lv.add_child(hint)

	# centre: stage + stats bar
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(mid)
	stage = Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.gui_input.connect(_on_stage_input)
	stage.resized.connect(_layout_changed)
	ui_target = Button.new()
	ui_target.text = "  Upgrade  "
	ui_target.name = "UiTarget"
	ui_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_target.visible = false
	stage.add_child(ui_target)
	mid.add_child(stage)
	var bar := PanelContainer.new()
	bar.custom_minimum_size.y = BAR_H
	bar.add_theme_stylebox_override("panel", _box(PANEL, 0, Vector4(12, 6, 12, 6)))
	mid.add_child(bar)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 14)
	bar.add_child(bh)
	stats_label = Label.new()
	stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_label.clip_text = true
	stats_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stats_label.add_theme_color_override("font_color", TEXT_DIM)
	stats_label.add_theme_font_size_override("font_size", 13)
	bh.add_child(stats_label)
	var sl := Label.new()
	sl.text = "Stress"
	sl.add_theme_color_override("font_color", TEXT_DIM)
	bh.add_child(sl)
	stress_slider = HSlider.new()
	stress_slider.min_value = 0
	stress_slider.max_value = 150
	stress_slider.step = 10
	stress_slider.custom_minimum_size.x = 120
	stress_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(stress_slider)
	var sv := Label.new()
	sv.custom_minimum_size.x = 30
	sv.text = "0"
	stress_slider.value_changed.connect(func(v): sv.text = str(int(v)))
	bh.add_child(sv)
	stress_mix = CheckBox.new()
	stress_mix.text = "Mix all"
	stress_mix.button_pressed = true
	bh.add_child(stress_mix)

	# right: info + controls
	var right := _panel(cols, RIGHT_W)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_theme_constant_override("separation", 8)
	scroll.add_child(rv)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", TEXT)
	rv.add_child(title_label)
	meta_label = Label.new()
	meta_label.add_theme_font_size_override("font_size", 11)
	meta_label.add_theme_color_override("font_color", ACCENT)
	rv.add_child(meta_label)
	desc_label = Label.new()
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_color_override("font_color", TEXT_DIM)
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.custom_minimum_size.x = RIGHT_W - 40
	rv.add_child(desc_label)
	rv.add_child(_sep())

	preset_opt = OptionButton.new()
	preset_opt.item_selected.connect(func(_i): _update_code())
	_row(rv, "Preset", preset_opt)
	var ch := HBoxContainer.new()
	color_on = CheckBox.new()
	color_on.text = "Tint"
	color_on.toggled.connect(func(_b): _update_code())
	ch.add_child(color_on)
	color_btn = ColorPickerButton.new()
	color_btn.color = Color("3fb8ff")
	color_btn.custom_minimum_size = Vector2(80, 28)
	color_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_btn.color_changed.connect(func(_c): color_on.button_pressed = true; _update_code())
	ch.add_child(color_btn)
	_row(rv, "Color", ch)
	_slider(rv, "scale", "Scale", VCParams.SCALE_MIN, 3.0, 0.05, 1.0)
	_slider(rv, "intensity", "Intensity", VCParams.INTENSITY_MIN, VCParams.INTENSITY_MAX, 0.05, 1.0)
	_slider(rv, "speed", "Speed", VCParams.SPEED_MIN, 3.0, 0.05, 1.0)
	style_opt = OptionButton.new()
	style_opt.add_item("Smooth")
	style_opt.add_item("Pixel")
	style_opt.item_selected.connect(func(_i): _update_code())
	_row(rv, "Style", style_opt)
	_slider(rv, "pixel_size", "Pixel size", VCParams.PIXEL_MIN, VCParams.PIXEL_MAX, 1, VCParams.DEFAULT_PIXEL_SIZE)
	bg_opt = OptionButton.new()
	for n in VCDemoBackground.NAMES:
		bg_opt.add_item(n)
	bg_opt.item_selected.connect(func(i): background.kind = i)
	_row(rv, "Background", bg_opt)
	rv.add_child(_sep())

	var bh2 := HBoxContainer.new()
	bh2.add_theme_constant_override("separation", 8)
	var play := Button.new()
	play.text = "Play"
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.custom_minimum_size.y = 36
	play.add_theme_stylebox_override("normal", _box(ACCENT.darkened(0.1), 8))
	play.add_theme_stylebox_override("hover", _box(ACCENT, 8))
	play.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.25), 8))
	play.add_theme_color_override("font_color", Color(0.1, 0.07, 0.05))
	play.add_theme_color_override("font_hover_color", Color(0.1, 0.07, 0.05))
	play.pressed.connect(func(): play_at(stage_rect().get_center()))
	bh2.add_child(play)
	repeat_chk = CheckBox.new()
	repeat_chk.text = "Repeat"
	bh2.add_child(repeat_chk)
	showcase_chk = CheckBox.new()
	showcase_chk.text = "Showcase size"
	showcase_chk.tooltip_text = "Small effects play at their showcase scale (x1.15-1.6) so they read in a small window. In a game, scale = 1 is the default."
	showcase_chk.button_pressed = true
	bh2.add_child(showcase_chk)
	rv.add_child(bh2)
	var reset := Button.new()
	reset.text = "Reset controls"
	reset.pressed.connect(_reset_controls)
	rv.add_child(reset)
	rv.add_child(_sep())

	var ch2 := HBoxContainer.new()
	var cl := Label.new()
	cl.text = "CODE"
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cl.add_theme_font_size_override("font_size", 11)
	cl.add_theme_color_override("font_color", TEXT_DIM)
	ch2.add_child(cl)
	var copy := Button.new()
	copy.text = "Copy code"
	copy.pressed.connect(func(): DisplayServer.clipboard_set(code_label.text); copy.text = "Copied"; get_tree().create_timer(1.2).timeout.connect(func(): copy.text = "Copy code"))
	ch2.add_child(copy)
	rv.add_child(ch2)
	var code_panel := PanelContainer.new()
	code_panel.add_theme_stylebox_override("panel", _box(Color(0.05, 0.055, 0.07), 6, Vector4(10, 8, 10, 8)))
	rv.add_child(code_panel)
	code_label = Label.new()
	code_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code_label.custom_minimum_size.x = RIGHT_W - 60
	code_label.add_theme_font_override("font", _mono())
	code_label.add_theme_font_size_override("font_size", 12)
	code_label.add_theme_color_override("font_color", Color(0.75, 0.88, 0.78))
	code_panel.add_child(code_label)


func _panel(parent: Control, w: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size.x = w
	p.add_theme_stylebox_override("panel", _box(PANEL, 0, Vector4(16, 16, 16, 16), PANEL_EDGE))
	parent.add_child(p)
	return p


func _vbox(parent: Control, sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	parent.add_child(v)
	return v


func _row(parent: Control, label: String, ctl: Control) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 84
	l.add_theme_color_override("font_color", TEXT_DIM)
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	parent.add_child(h)


func _slider(parent: Control, key: String, label: String, lo: float, hi: float, step: float, def: float) -> void:
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = def
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.set_meta(&"default", def)
	var v := Label.new()
	v.custom_minimum_size.x = 40
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.text = _fmt(def, step)
	s.value_changed.connect(func(x): v.text = _fmt(x, step); _update_code())
	h.add_child(s)
	h.add_child(v)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(parent, label, h)
	sliders[key] = s


func _fmt(x: float, step: float) -> String:
	return str(int(x)) if step >= 1.0 else "%.2f" % x


func _sep() -> HSeparator:
	var s := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.07)
	line.thickness = 1
	s.add_theme_stylebox_override("separator", line)
	s.add_theme_constant_override("separation", 10)
	return s


func _box(c: Color, radius: int, margins := Vector4(10, 6, 10, 6), border := Color.TRANSPARENT) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = c
	b.set_corner_radius_all(radius)
	b.content_margin_left = margins.x
	b.content_margin_top = margins.y
	b.content_margin_right = margins.z
	b.content_margin_bottom = margins.w
	if border.a > 0.0:
		b.border_color = border
		b.set_border_width_all(1)
	return b


func _mono() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["DejaVu Sans Mono", "Menlo", "Consolas", "monospace"])
	return f


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_color(&"font_color", &"Label", TEXT)
	for cls in [&"Button", &"OptionButton"]:
		t.set_stylebox(&"normal", cls, _box(Color(0.16, 0.17, 0.21), 6))
		t.set_stylebox(&"hover", cls, _box(Color(0.2, 0.21, 0.26), 6))
		t.set_stylebox(&"pressed", cls, _box(Color(0.13, 0.14, 0.17), 6))
		t.set_stylebox(&"focus", cls, _box(Color.TRANSPARENT, 6, Vector4(10, 6, 10, 6), Color(ACCENT, 0.6)))
		t.set_color(&"font_color", cls, TEXT)
		t.set_color(&"font_hover_color", cls, Color.WHITE)
	t.set_stylebox(&"normal", &"LineEdit", _box(Color(0.06, 0.065, 0.085), 6, Vector4(10, 7, 10, 7)))
	t.set_stylebox(&"focus", &"LineEdit", _box(Color.TRANSPARENT, 6, Vector4(10, 7, 10, 7), Color(ACCENT, 0.6)))
	t.set_stylebox(&"panel", &"Tree", _box(Color(0.06, 0.065, 0.085), 8, Vector4(6, 6, 6, 6)))
	t.set_stylebox(&"focus", &"Tree", StyleBoxEmpty.new())
	t.set_stylebox(&"selected", &"Tree", _box(Color(ACCENT, 0.22), 5))
	t.set_stylebox(&"selected_focus", &"Tree", _box(Color(ACCENT, 0.28), 5))
	t.set_stylebox(&"hovered", &"Tree", _box(Color(1, 1, 1, 0.05), 5))
	t.set_color(&"font_color", &"Tree", TEXT)
	t.set_color(&"font_selected_color", &"Tree", Color.WHITE)
	t.set_constant(&"v_separation", &"Tree", 6)
	t.set_constant(&"draw_relationship_lines", &"Tree", 0)
	t.set_constant(&"draw_guides", &"Tree", 0)
	t.set_constant(&"item_margin", &"Tree", 14)
	t.set_stylebox(&"slider", &"HSlider", _box(Color(0.2, 0.21, 0.26), 3, Vector4(0, 2, 0, 2)))
	t.set_stylebox(&"grabber_area", &"HSlider", _box(Color(ACCENT, 0.75), 3, Vector4(0, 2, 0, 2)))
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", _box(ACCENT, 3, Vector4(0, 2, 0, 2)))
	t.set_color(&"font_color", &"CheckBox", TEXT)
	return t


func _fill_tree() -> void:
	var keep := current
	tree.clear()
	items.clear()
	var root := tree.create_item()
	var q := search.text.strip_edges().to_lower() if search != null else ""
	var by_cat := {}
	for id in VfxCore.list():
		var inf := VfxCore.info(id)
		if q != "" and not (q in String(id) or q in String(inf.get("description", "")).to_lower()):
			continue
		var cat: StringName = inf.get("category", &"custom")
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(id)
	var cats := by_cat.keys()
	cats.sort_custom(func(a, b): return String(a) < String(b))
	for cat in cats:
		var head := tree.create_item(root)
		head.set_text(0, "%s  %d" % [String(CATEGORY_NAMES.get(cat, String(cat).capitalize())).to_upper(), by_cat[cat].size()])
		head.set_selectable(0, false)
		head.set_custom_color(0, TEXT_DIM)
		head.set_custom_font_size(0, 11)
		var ids: Array = by_cat[cat]
		ids.sort_custom(func(a, b): return String(a) < String(b))
		for id: StringName in ids:
			var it := tree.create_item(head)
			it.set_text(0, _pretty(id))
			it.set_metadata(0, id)
			it.set_tooltip_text(0, String(VfxCore.info(id).get("description", "")))
			items[id] = it
	if items.has(keep):
		items[keep].select(0)


func _on_tree_selected() -> void:
	var it := tree.get_selected()
	if it != null and it.get_metadata(0) is StringName and it.get_metadata(0) != current:
		select(it.get_metadata(0))


func _reset_controls() -> void:
	for k in sliders:
		sliders[k].value = sliders[k].get_meta(&"default")
	color_on.button_pressed = false
	style_opt.select(0)
	preset_opt.select(0)
	_update_code()


func _update_code() -> void:
	if code_label == null or current == &"":
		return
	var parts: Array[String] = []
	var o := options()
	if _floor_effect(current):
		parts.append('"floor_y": ground_y')
	for k in o:
		parts.append('"%s": %s' % [k, _lit(o[k])])
	var call := 'VfxCore.play(&"%s", position' % current
	match _usage(current):
		&"apply":
			call = 'VfxCore.apply(&"%s", $Sprite2D' % current
		&"play_attached":
			call = 'VfxCore.play_attached(&"%s", $Sprite2D' % current
		&"ui":
			call = 'VfxCore.play_attached(&"%s", $Button' % current
		&"play_line":
			call = 'VfxCore.play_line(&"%s", from, to' % current
		&"text":
			parts.push_front('"text": "42"')
	code_label.text = call + (", {\n\t" + ",\n\t".join(parts) + "\n})" if not parts.is_empty() else ")")


func _lit(v: Variant) -> String:
	if v is StringName:
		return '&"%s"' % v
	if v is Color:
		return 'Color("%s")' % v.to_html(false)
	if v is float:
		return str(snappedf(v, 0.01))
	return str(v)


func _pretty(id: StringName) -> String:
	return String(id).replace("_", " ").capitalize()


func _is_apply(id: StringName) -> bool:
	return bool(VfxCore.info(id).get("apply", false))


func _usage(id: StringName) -> StringName:
	return VfxCore.info(id).get("usage", &"play")


func _floor_effect(id: StringName) -> bool:
	if not _uses_floor.has(id):
		var found := false
		var ps: PackedScene = load(VfxCore.info(id)["path"])
		var e := ps.instantiate()
		for c in e.get_children():
			if c is VCLayerBodies:
				found = true
		e.free()
		_uses_floor[id] = found
	return _uses_floor[id]


# --- playing -------------------------------------------------------------------

func _play(id: StringName, pos: Vector2, opts: Dictionary) -> VCHandle:
	var o := opts.duplicate()
	o["floor_y"] = floor_y()
	if id == &"hit_spark" and not o.has("normal"):
		o["normal"] = Vector2.UP
	if showcase_chk != null and showcase_chk.button_pressed:
		o["scale"] = float(o.get("scale", 1.0)) * float(VfxCore.info(id).get("showcase_scale", 1.0))
	match _usage(id):
		&"apply":
			# material effects act on the demo crate, wherever the click was
			o.erase("floor_y")
			return VfxCore.apply(id, target, o)
		&"play_attached":
			target.position = Vector2(pos.x, floor_y() - target.texture.get_height() * 0.5)
			return VfxCore.play_attached(id, target, o)
		&"ui":
			ui_target.position = stage.get_global_transform().affine_inverse() * pos - ui_target.size * 0.5
			return VfxCore.play_attached(id, ui_target, o)
		&"play_line":
			var half := 160.0 * float(o.get("scale", 1.0))
			return VfxCore.play_line(id, pos - Vector2(half, 0), pos + Vector2(half, 0), o)
		&"text":
			if not o.has("text"):
				o["text"] = str(randi_range(12, 99))
		&"screen":
			pos = stage_rect().get_center()
	return VfxCore.play(id, pos, o)


func _on_stage_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		play_at(stage.get_global_transform() * ev.position)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_SPACE:
		play_at(stage_rect().get_center())


func _layout_changed() -> void:
	if stage == null:
		return
	background.stage = stage_rect()
	background.floor_y = floor_y()
	target.position = Vector2(stage_rect().get_center().x, floor_y() - target.texture.get_height() * 0.5)
	ui_target.position = stage.size * 0.5 - ui_target.size * 0.5


func _process(delta: float) -> void:
	_fps_acc += delta
	_fps_frames += 1
	if _fps_acc >= 0.5:
		_fps = _fps_frames / _fps_acc
		_fps_acc = 0.0
		_fps_frames = 0
		var s := VfxCore.stats()
		stats_label.text = "%d FPS  ·  %d effects  ·  %d / %d particles  ·  %d draws" % [
			roundi(_fps), s["active"], s["live_particles"], s["max_live_particles"],
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
	if repeat_chk.button_pressed and current != &"":
		_repeat_t -= delta
		if _repeat_t <= 0.0:
			play_at(stage_rect().get_center())
			_repeat_t = float(VfxCore.info(current).get("duration", 1.0)) + 0.35
	_run_stress()


func _run_stress() -> void:
	var want := int(stress_slider.value)
	_stress = _stress.filter(func(h: VCHandle): return h.is_alive())
	if want == 0:
		return
	var r := stage_rect().grow(-40)
	# the mix uses world effects only (no sprite, UI, text or screen effects)
	var ids := VfxCore.list().filter(func(i: StringName): return _usage(i) in [&"play", &"play_line"]) if stress_mix.button_pressed else [current]
	if ids.is_empty():
		return
	var spawn := mini(want - _stress.size(), 6)
	for i in spawn:
		var id: StringName = ids[randi() % ids.size()]
		var p := Vector2(randf_range(r.position.x, r.end.x), randf_range(r.position.y + 40, floor_y()))
		_stress.append(_play(id, p, {"priority": VCParams.Priority.LOW, "scale": randf_range(0.7, 1.2)}))


## Screenshot of the UI with the selected effect mid-play, then quit.
func _shot(path: String) -> void:
	var delay := 0.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-delay="):
			delay = float(a.get_slice("=", 1))
	await _wait(delay)
	play_at(stage_rect().get_center())
	await _wait(0.3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


# --- reel ------------------------------------------------------------------------

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _still(dir: String, name: String) -> void:
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))


## One play; the rifle fires a short three-round burst.
func _burst(id: StringName, at: Vector2) -> void:
	var n := 3 if id == &"muzzle_rifle" else 1
	for i in n:
		play_at(at)
		if i < n - 1:
			await _wait(0.11)


## Scripted tour used for the promo reel: every effect, a few variations, then
## a stress pass. Quits at the end.
func _reel(stills: String) -> void:
	if stills != "":
		DirAccess.make_dir_recursive_absolute(stills)
	await _wait(0.6)
	var r := stage_rect()
	var c := Vector2(r.get_center().x, floor_y() - r.size.y * 0.28)
	var ground := floor_y()
	var order: Array[StringName] = [&"explosion_small", &"shock_ring", &"smoke_puff", &"debris_stone",
		&"dust_puff", &"muzzle_rifle", &"hit_spark", &"coin_burst"]
	# seconds after a play when the effect reads best in a still
	var shot_t := {&"muzzle_rifle": 0.03, &"hit_spark": 0.05, &"explosion_small": 0.16, &"shock_ring": 0.18}
	for id in order:
		if not VfxCore.has(id):
			continue
		select(id)
		_reset_controls()
		var small := id in [&"muzzle_rifle", &"hit_spark"]
		if small:
			set_value("scale", 1.6)
		var low := id in [&"dust_puff", &"debris_stone", &"coin_burst", &"hit_spark"]
		var y := ground - 2.0 if low else c.y
		var xs := [0.5, 0.2, 0.8] if id != &"muzzle_rifle" else [0.3, 0.06, 0.62]
		var st: float = shot_t.get(id, 0.3)
		await _wait(0.3)
		# 1) default
		await _burst(id, Vector2(r.position.x + r.size.x * xs[0], y))
		await _wait(st)
		await _still(stills, "%s_default" % id)
		await _wait(1.1)
		# 2) the other presets side by side
		var ps := VfxCore.presets(id)
		for k in range(1, mini(ps.size(), 3)):
			set_preset(ps[k])
			await _burst(id, Vector2(r.position.x + r.size.x * xs[k], y))
			if k < mini(ps.size(), 3) - 1:
				await _wait(0.12)
		await _wait(st)
		await _still(stills, "%s_presets" % id)
		await _wait(1.1)
		# 3) any colour, any scale
		set_preset(&"default")
		set_color(Color("49c6ff") if id != &"coin_burst" else Color("c07bff"))
		set_value("scale", 2.2 if small else 1.4)
		await _burst(id, Vector2(r.position.x + r.size.x * xs[0], y))
		await _wait(st)
		await _still(stills, "%s_tinted" % id)
		await _wait(1.2)
	# stress finale
	select(&"explosion_small")
	_reset_controls()
	stress_mix.button_pressed = true
	stress_slider.value = 40
	await _wait(2.5)
	await _still(stills, "stress_40")
	stress_slider.value = 80
	await _wait(2.5)
	await _still(stills, "stress_80")
	stress_slider.value = 0
	await _wait(1.6)
	get_tree().quit()
