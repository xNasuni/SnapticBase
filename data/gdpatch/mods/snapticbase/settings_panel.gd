extends "menu_panel.gd"

const SettingsPage := preload("settings_page.gd")
const ColorPopup := preload("color_popup.gd")

var store

var _popup: Control


func setup(settings_store, size: Vector2 = Vector2(560, 300)) -> void:
	store = settings_store
	build("", size)
	add_back()


func add_tab(title: String) -> Control:
	var tab := super(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	tab.add_child(row)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 6.0
	row.add_child(scroll)

	var preview := MarginContainer.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_stretch_ratio = 4.0
	preview.visible = false
	row.add_child(preview)

	var page: Control = SettingsPage.new()
	page.setup(store, style_button, preview, self)
	scroll.add_child(page)
	return page


func pick_color(initial: Color, live: Callable, commit: Callable) -> void:
	if not _popup:
		_popup = ColorPopup.new()
		add_child(_popup)
	_popup.pick(initial, live, commit)
