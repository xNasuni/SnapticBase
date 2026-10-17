extends Control

signal closed

const SnapticBase := preload("mod.gd")

const THEME := "res://ui/_shared/themes/menu_screen_theme.tres"
const CLICK_BUTTON := "res://levels/menu_screen_background/prefabs/click_button/click_button.gd"
const BACK_GROUP := &"back_button"
const FADE := 0.2

var content: MarginContainer

var _tabs: TabContainer
var _actions: HBoxContainer
var _menu: Node
var _under: Control
var _menu_tween: Tween
var _tween: Tween


func build(title: String, size: Vector2) -> void:
	theme = load(THEME)
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	z_index = 2
	visible = false

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)

	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 0)
	center.add_child(frame)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = size
	_tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	frame.add_child(_tabs)

	if title != "":
		content = add_tab(title) as MarginContainer

	_actions = HBoxContainer.new()
	_actions.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.add_child(_actions)


func add_tab(title: String) -> Control:
	var page := MarginContainer.new()
	page.name = title
	for side in ["left", "top", "right", "bottom"]:
		page.add_theme_constant_override("margin_" + side, 8)
	_tabs.add_child(page)
	return page


func add_action(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(callback)
	_actions.add_child(style_button(button))
	return button


func add_back(text: String = "Back") -> Button:
	var button := add_action(text, close)
	button.add_to_group(BACK_GROUP)
	return button


static func style_button(button: Button) -> Button:
	button.set_script(load(CLICK_BUTTON))
	button.pressed.connect(AudioManager.play_sound_effect.bind(SFX.Name.MENU_SELECT))
	button.mouse_entered.connect(AudioManager.play_sound_effect.bind(SFX.Name.MENU_HOVER))
	return button


func open(under: Control = null) -> void:
	if not is_inside_tree():
		SettingsMenu.instance.get_parent().add_child(self)
	_under = under
	_menu = SnapticBase.menu
	var duration := _duration()
	var behind := _behind()
	if behind:
		_menu_tween = Helpers.fade_control(behind, _menu_tween, false, duration, MOUSE_FILTER_IGNORE)
	_tween = Helpers.fade_control(self, _tween, true, duration, MOUSE_FILTER_IGNORE)


func close() -> void:
	var duration := _duration()
	var behind := _behind()
	if behind:
		_menu_tween = Helpers.fade_control(behind, _menu_tween, true, duration, MOUSE_FILTER_IGNORE)
	_tween = Helpers.fade_control(self, _tween, false, duration)
	closed.emit()


func dismiss() -> void:
	_tween = Helpers.fade_control(self, _tween, false, _duration())


func _duration() -> float:
	return _menu.get("tween_duration") if is_instance_valid(_menu) else FADE


func _behind() -> Control:
	if is_instance_valid(_under):
		return _under
	return _menu.get("everything_else") if is_instance_valid(_menu) else null
