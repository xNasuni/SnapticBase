extends "menu_panel.gd"

const SIZE := Vector2(560, 400)
const ICON := 56
const ACCENT := Color(0.5882353, 0.5882353, 1)

var _blank: Texture2D
var _clear: Texture2D
var _icons: Array[Texture2D] = []
var _pic: TextureRect
var _gap: Control
var _entries: Array = []
var _name: Label
var _meta: Label
var _desc: Label
var _settings: Button
var _website: Button
var _current := 0

func setup(entries: Array) -> void:
	_entries = entries
	build("Mods", SIZE)

	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_blank = ImageTexture.create_from_image(image)
	_clear = ImageTexture.create_from_image(Image.create(16, 16, false, Image.FORMAT_RGBA8))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	content.add_child(row)

	var list := _column(row, 3.6)
	row.add_child(_line(VSeparator.new(), true))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 7.0
	row.add_child(right)
	var detail := _column(right, 1.0)
	detail.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL

	detail.add_theme_constant_override("separation", 0)
	var header := HBoxContainer.new()
	detail.add_child(header)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 24)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_name)
	var corner := Control.new()
	corner.custom_minimum_size = Vector2(ICON, 0)
	header.add_child(corner)
	_pic = TextureRect.new()
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_pic.size = Vector2(ICON, ICON)
	corner.add_child(_pic)
	_meta = Label.new()
	_meta.add_theme_color_override("font_color", ACCENT)
	detail.add_child(_meta)
	_gap = Control.new()
	detail.add_child(_gap)
	_desc = Label.new()
	_desc.add_theme_font_size_override("font_size", 14)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_child(_desc)
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(button_row)
	_settings = Button.new()
	_settings.text = "Settings"
	_settings.disabled = true
	_settings.pressed.connect(func() -> void: SnapticBase.open_settings(_entries[_current].id, self))
	button_row.add_child(style_button(_settings))
	_website = Button.new()
	_website.text = "Website"
	_website.pressed.connect(func() -> void: OS.shell_open(_entries[_current].website))
	button_row.add_child(style_button(_website))

	var group := ButtonGroup.new()
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.text = e.name
		button.icon = _clear
		button.expand_icon = true
		button.add_theme_constant_override("h_separation", button.get_theme_constant("h_separation") + 4)
		var pic := TextureRect.new()
		_icons.append(_icon(e.dir))
		pic.texture = _icons[i]
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		pic.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		pic.offset_left = button.get_theme_stylebox("normal").get_margin(SIDE_LEFT) + 2
		pic.offset_right = pic.offset_left + 27
		pic.offset_top = -14
		pic.offset_bottom = 13
		button.add_child(pic)
		button.clip_text = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("icon_max_width", 24)
		button.pressed.connect(_select.bind(i))
		list.add_child(style_button(button))

	add_back()
	if list.get_child_count() > 0:
		list.get_child(0).button_pressed = true
		_select(0)


func _line(sep: Separator, vertical: bool) -> Separator:
	var line := StyleBoxLine.new()
	line.color = Color.WHITE
	line.thickness = 2
	line.vertical = vertical
	sep.add_theme_stylebox_override("separator", line)
	return sep


func _column(row: Control, ratio: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = ratio
	row.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	scroll.add_child(column)
	return column


func _select(i: int) -> void:
	_current = i
	var e: Dictionary = _entries[i]
	_settings.disabled = not SnapticBase.has_settings(e.id)
	_settings.tooltip_text = "no settings for this mod" if _settings.disabled else "open settings"
	_name.text = e.name
	var meta: String = "v" + e.version
	if not e.authors.is_empty():
		meta += "  by " + ", ".join(e.authors)
	_meta.text = meta
	_desc.text = e.description if e.description != "" else "no description"
	_website.disabled = e.website == ""
	_website.tooltip_text = "no website for this mid" if _website.disabled else e.website
	_pic.texture = _icons[i]
	_fit_gap()

func _fit_gap() -> void:
	if not is_inside_tree():
		await tree_entered
	await get_tree().process_frame
	await get_tree().process_frame
	_gap.custom_minimum_size.y = 4.0
	await get_tree().process_frame
	_gap.custom_minimum_size.y = maxf(4.0, ICON + 4.0 - (_meta.position.y + _meta.size.y))

func _icon(dir: String) -> Texture2D:
	var path := dir.path_join("icon.png")
	if dir == "" or not FileAccess.file_exists(path):
		path = get_script().resource_path.get_base_dir().path_join("default.png")
	return SnapticBase.load_asset(path) as Texture2D if FileAccess.file_exists(path) else _blank
