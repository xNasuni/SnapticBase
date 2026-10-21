extends VBoxContainer

const RESET_ICON := "res://autoloads/button_prompts/kenney_input_prompts/Flairs/Default/flair_arrow_3.png"
const LABEL_WIDTH := 160

var _store
var _style: Callable
var _preview: Control
var _panel: Control
var _rows: Array[Dictionary] = []

func setup(store, style: Callable, preview: Control, panel: Control) -> void:
	_store = store
	_style = style
	_preview = preview
	_panel = panel
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_store.changed.connect(_on_changed)


func add_toggle(label: String, key: String) -> CheckBox:
	var box := CheckBox.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	box.toggled.connect(func(on: bool) -> void: _store.set_value(key, on))
	_row(label, box, key, func() -> void: box.set_pressed_no_signal(_store.get_bool(key)))
	return box


func add_slider(label: String, key: String, min_value: float, max_value: float, step: float = 0.01) -> HSlider:
	var holder := HBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size.x = 48
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(readout)

	var decimals := 0 if step >= 1.0 else 2
	var drag := {"on": false}
	slider.drag_started.connect(func() -> void: drag.on = true)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		drag.on = false
		_store.save())
	slider.value_changed.connect(func(value: float) -> void: _store.set_value(key, value, not drag.on))
	_row(label, holder, key, func() -> void:
		var value: float = _store.get_number(key)
		slider.set_value_no_signal(value)
		readout.text = String.num(value, decimals))
	return slider


func add_choice(label: String, key: String, options: Array) -> OptionButton:
	var drop := OptionButton.new()
	drop.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	for option in options:
		drop.add_item(str(option))
	drop.item_selected.connect(func(index: int) -> void: _store.set_value(key, str(options[index])))
	_row(label, drop, key, func() -> void: drop.select(maxi(options.find(_store.get_string(key)), 0)))
	return drop


func add_text(label: String, key: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(text: String) -> void: _store.set_value(key, text))
	edit.focus_exited.connect(func() -> void: _store.set_value(key, edit.text))
	_row(label, edit, key, func() -> void: edit.text = _store.get_string(key))
	return edit


func add_color(label: String, key: String) -> Button:
	var swatch := StyleBoxFlat.new()
	swatch.set_border_width_all(2)
	swatch.border_color = Color(0.5882353, 0.5882353, 1, 0.5)
	var hover: StyleBoxFlat = swatch.duplicate()
	hover.border_color = Color.WHITE
	var button := Button.new()
	button.custom_minimum_size = Vector2(64, 28)
	button.tooltip_text = "pick a color"
	for state in ["normal", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, swatch)
	button.add_theme_stylebox_override("hover", hover)
	button.pressed.connect(func() -> void:
		_panel.pick_color(_store.get_color(key),
			func(color: Color) -> void: _store.set_value(key, color, false),
			func(color: Color) -> void:
				_store.set_value(key, color)
				_store.save()))
	_row(label, button, key, func() -> void:
		swatch.bg_color = _store.get_color(key)
		hover.bg_color = swatch.bg_color)
	return button


func set_preview(node: Control) -> void:
	_preview.add_child(node)
	_preview.show()


func _row(label: String, control: Control, key: String, refresh: Callable) -> void:
	var row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = label
	caption.custom_minimum_size.x = LABEL_WIDTH
	row.add_child(caption)
	row.add_child(control)

	var reset := Button.new()
	reset.icon = load(RESET_ICON)
	reset.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reset.expand_icon = true
	reset.custom_minimum_size = Vector2(32, 32)
	reset.tooltip_text = "reset to default"
	reset.pressed.connect(_store.reset.bind(key))
	row.add_child(_style.call(reset) if _style.is_valid() else reset)

	var update := func() -> void:
		refresh.call()
		reset.visible = not _store.is_default(key)
	update.call()
	_rows.append({"key": key, "update": update})
	add_child(row)

func _on_changed(changed_key: String, _value: Variant) -> void:
	for row in _rows:
		if row.key == changed_key:
			row.update.call()