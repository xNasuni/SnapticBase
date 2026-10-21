extends Control

const SIZE := 180
const ACCENT := Color(0.5882353, 0.5882353, 1)

var _picker: ColorPicker
var _initial: Color
var _live: Callable
var _commit: Callable
var _opened_frame := -10

var _box: VBoxContainer
var _active := false

func _init() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	z_index = 1
	visible = false

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.14, 0.97)
	style.set_border_width_all(2)
	style.border_color = ACCENT
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)

	_box = VBoxContainer.new()
	card.add_child(_box)

	var done := Button.new()
	done.text = "Done"
	done.tooltip_text = "apply this color"
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.pressed.connect(_finish)
	_box.add_child(done)
	
	visibility_changed.connect(_on_visibility_changed)

func _build_picker() -> void:
	if _picker:
		_picker.queue_free()
	_picker = ColorPicker.new()
	_picker.edit_alpha = false
	_picker.sampler_visible = false
	_picker.color_modes_visible = false
	_picker.sliders_visible = false
	_picker.presets_visible = false
	_picker.can_add_swatches = false
	_picker.add_theme_constant_override("sv_width", SIZE)
	_picker.add_theme_constant_override("sv_height", SIZE)
	_picker.color_changed.connect(func(color: Color) -> void: _live.call(color))
	_box.add_child(_picker)
	_box.move_child(_picker, 0)

	var hex := _hex()
	if hex:
		hex.tooltip_text = "hex code"

func pick(initial: Color, live: Callable, commit: Callable) -> void:
	_initial = initial
	_live = live
	_commit = commit
	_build_picker()
	_picker.color = initial
	_active = true
	_opened_frame = Engine.get_process_frames()
	show()

func _on_visibility_changed() -> void:
	if _active and not is_visible_in_tree():
		_active = false
		_live.call(_initial)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not _just_opened():
		_cancel()
		accept_event()


func _just_opened() -> bool:
	return Engine.get_process_frames() - _opened_frame <= 1


func _input(event: InputEvent) -> void:
	if not visible or _just_opened():
		return
	if event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_finish()
		get_viewport().set_input_as_handled()


func _hex() -> LineEdit:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused is LineEdit and _picker.is_ancestor_of(focused):
		return focused
	var found := _picker.find_children("*", "LineEdit", true, false)
	return found.back() if not found.is_empty() else null


func _finish() -> void:
	var hex := _hex()
	if hex and Color.html_is_valid(hex.text):
		_picker.color = Color.html(hex.text)
	_active = false
	hide()
	_commit.call(_picker.color)


func _cancel() -> void:
	_active = false
	hide()
	_live.call(_initial)