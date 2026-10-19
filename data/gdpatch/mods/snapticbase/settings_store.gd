extends RefCounted

signal changed(key: String, value: Variant)

const DIR := "user://snapticbase/settings/"
const TYPES := [TYPE_BOOL, TYPE_STRING, TYPE_FLOAT, TYPE_COLOR]

var _path: String
var _defaults := {}
var _values := {}
var _saved := {}


func setup(id: String) -> void:
	_path = DIR + id + ".json"
	if FileAccess.file_exists(_path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(_path))
		if data is Dictionary:
			_saved = data


func define(key: String, default: Variant) -> void:
	if typeof(default) == TYPE_INT:
		default = float(default)
	if typeof(default) == TYPE_COLOR:
		default = Color(default.r, default.g, default.b)
	if not typeof(default) in TYPES:
		push_error("[snaptic] setting %s: use a bool, String, float or Color default" % key)
		return
	_defaults[key] = default
	_values[key] = _from_disk(key, default)


func get_bool(key: String) -> bool:
	return bool(_value(key, false))


func get_string(key: String) -> String:
	return str(_value(key, ""))


func get_number(key: String) -> float:
	return float(_value(key, 0.0))


func get_color(key: String) -> Color:
	return _value(key, Color.WHITE)


func set_value(key: String, value: Variant, persist: bool = true) -> void:
	if not _defaults.has(key):
		push_error("[snaptic] unknown setting " + key)
		return
	var want: int = typeof(_defaults[key])
	if want == TYPE_FLOAT and typeof(value) == TYPE_INT:
		value = float(value)
	if want == TYPE_COLOR and typeof(value) == TYPE_COLOR:
		value = Color(value.r, value.g, value.b)
	if typeof(value) != want:
		push_error("[snaptic] setting %s: wrong value type" % key)
		return
	if value == _values[key]:
		return
	_values[key] = value
	changed.emit(key, value)
	if persist:
		save()


func reset(key: String) -> void:
	if _defaults.has(key):
		set_value(key, _defaults[key])


func is_default(key: String) -> bool:
	return _defaults.has(key) and _values[key] == _defaults[key]


func save() -> void:
	var data := {}
	for key in _values:
		var value: Variant = _values[key]
		data[key] = value.to_html(false) if typeof(value) == TYPE_COLOR else value
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func _value(key: String, fallback: Variant) -> Variant:
	if _values.has(key):
		return _values[key]
	push_error("[snaptic] unknown setting " + key)
	return fallback


func _from_disk(key: String, default: Variant) -> Variant:
	if not _saved.has(key):
		return default
	var raw: Variant = _saved[key]
	match typeof(default):
		TYPE_BOOL:
			return raw if raw is bool else default
		TYPE_STRING:
			return raw if raw is String else default
		TYPE_FLOAT:
			return float(raw) if raw is float or raw is int else default
		TYPE_COLOR:
			if raw is String and Color.html_is_valid(raw):
				return Color.html(raw)
	return default
