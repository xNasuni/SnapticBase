extends Node

const Toml := preload("toml.gd")

const MODS_DIR := "res://gdpatch/mods/"
const MENU_SCENE := "res://ui/menu_screen/menu_screen_ui.tscn"
const MENU_LIST := "Everything Else/TitleMarginContainer/VBoxContainer/MenuButtons"
const MENU_TEMPLATE := "Options"
const DEFAULT_ANCHOR := "Play"

static var menu: Node
static var mods: Array[Dictionary] = []

static var _node: Node
static var _dir := ""

static var _menu_entries: Array[Dictionary] = []
static var _scene_hooks: Dictionary = {}
static var _menu_queued := false
static var _settings_stores := {}
static var _settings_pages := {}
static var _settings_panels := {}
static var _mods_menu: Control
static var _configs := {}
static var _startup_done := false
static var _menu_hooked := false

func _init() -> void:
	_dir = get_script().resource_path.get_base_dir().path_join("")

func _ready() -> void:
	if is_instance_valid(_node) and _node != self:
		queue_free()
		return

	_node = self
	name = "SnapticBase"
	_hook_menu()
	register("snapticbase", _dir)
	_log("snapticbase %s started" % version())
	get_tree().node_added.connect(_on_node_added)
	add_menu_button("Mods", _show_mods)


static func register(id: String, dir: String = "") -> Dictionary:
	_boot()
	var existing := get_mod(id)
	if not existing.is_empty():
		return existing

	if _gdpatch_mod(id) == null:
		push_error("[snapticbase] register: gdpatch doesn't have mod with id " + id)
		return {}

	var info := {
		"id": id,
		"dir": dir.path_join("") if dir != "" else "",
		"name": _meta(id, "name", id),
		"version": _meta(id, "version", ""),
		"authors": _meta(id, "authors", []),
		"description": _meta(id, "description", ""),
		"website": _meta(id, "website", ""),
		"dependencies": _dependencies(id),
	}

	mods.append(info)
	_log("registered %s %s" % [id, info.version])
	return info

static func check_dependencies() -> Array[String]:
	var installed := {}
	for m in GDPatch.get_mods():
		installed[_mod_id(m)] = true

	var problems: Array[String] = []
	for id in installed:
		for spec in _dependencies(id):
			var problem := _dependency_problem(str(spec), installed)
			if problem != "":
				problems.append("%s: %s" % [id, problem])

	for problem in problems:
		push_error("[snapticbase] dependency: " + problem)
	return problems

static func config(id: String) -> Dictionary:
	if not _configs.has(id):
		var data := Toml.parse_file(MODS_DIR + id + "/gdpatch_mod.toml")
		var block = data.get("snapticbase")
		_configs[id] = block if block is Dictionary else {}
	return _configs[id]


static func _dependencies(id: String) -> Array:
	var value = config(id).get("dependencies")
	return value if value is Array else []


static func _gdpatch_mod(id: String) -> Variant:
	for m in GDPatch.get_mods():
		if _mod_id(m) == id:
			return m
	return null


static func _mod_id(m: Variant) -> String:
	if m is String or m is StringName:
		return str(m)
	return str(m.get("id"))


static func _dependency_problem(spec: String, installed: Dictionary) -> String:
	var parts := spec.strip_edges().split("@", true, 1)
	var dep := parts[0].strip_edges()
	if not installed.has(dep):
		return "requires %s, which is not loaded" % dep
	if parts.size() < 2:
		return ""

	var want := parts[1].strip_edges()
	var op := "="
	for candidate in [">=", "<=", ">", "<", "="]:
		if want.begins_with(candidate):
			op = candidate
			want = want.substr(candidate.length()).strip_edges()
			break

	var have := str(_meta(dep, "version", ""))
	if _parse_version(have, false).is_empty():
		return "%s has an invalid version '%s'" % [dep, have]
	if _parse_version(want).is_empty():
		return "invalid version requirement '%s' for %s" % [want, dep]
	if version_satisfies(have, op, want):
		return ""
	return "requires %s %s%s, found %s" % [dep, "" if op == "=" else op, want, have]


# this regex captures all the edge cases I can think of that might be used
# hopefully I don't have to ever change this to not introduce anything backwards incompatible
const _VERSION_RE := "^v?((?:\\d+|x)(?:\\.(?:\\d+|x))*)(\\*)?(?:-([^+*]*)(\\*)?)?(?:\\+([^*]*)(\\*)?)?$"

static func _parse_version(text: String, allow_wildcards := true) -> Dictionary:
	var re := RegEx.create_from_string(_VERSION_RE)
	var m := re.search(text.strip_edges())
	if m == null:
		return {}
	var v := {
		"nums": m.get_string(1).split("."),
		"any": m.get_start(2) != -1,
		"has_label": m.get_start(3) != -1,
		"label": m.get_string(3),
		"label_glob": m.get_start(4) != -1,
		"has_build": m.get_start(5) != -1,
		"build": m.get_string(5),
		"build_glob": m.get_start(6) != -1,
	}
	var wildcard: bool = v.any or v.label_glob or v.build_glob or "x" in v.nums
	if wildcard and not allow_wildcards:
		return {}
	if not wildcard and ((v.has_label and v.label.is_empty()) or (v.has_build and v.build.is_empty())):
		return {}
	return v

static func _part(v: Dictionary, i: int) -> String:
	return v.nums[i] if i < v.nums.size() else "0"

static func _tag_matches(want: String, glob: bool, have: String) -> bool:
	return have.begins_with(want) if glob else have == want

# public facing!
static func version_matches(version: String, pattern: String) -> bool:
	var v := _parse_version(version, false)
	var p := _parse_version(pattern)
	if v.is_empty() or p.is_empty():
		return false

	for i in (p.nums.size() if p.any else maxi(p.nums.size(), v.nums.size())):
		if _part(p, i) != "x" and int(_part(p, i)) != int(_part(v, i)):
			return false

	if p.has_label:
		if not v.has_label or not _tag_matches(p.label, p.label_glob, v.label):
			return false
	elif v.has_label and not p.any:
		return false

	return not p.has_build or (v.has_build and _tag_matches(p.build, p.build_glob, v.build))

# the actual operator comparison
static func version_satisfies(have: String, op: String, want: String) -> bool:
	if op == "=":
		return version_matches(have, want)
	var v := _parse_version(have, false)
	var p := _parse_version(want)
	if v.is_empty() or p.is_empty() or (v.has_label and not p.has_label and not p.any):
		return false
	var cmp := compare_versions(have, want)
	match op:
		">=": return cmp >= 0
		"<=": return cmp <= 0
		">": return cmp > 0
		"<": return cmp < 0
	return false


static func version_family(version: String) -> String:
	return ".".join(version.trim_prefix("v").split("+")[0].split("-")[0].split(".").slice(0, 2)) + ".x"


static func compare_versions(a: String, b: String) -> int:
	var pa := _parse_version(a)
	var pb := _parse_version(b)
	if pa.is_empty() or pb.is_empty():
		return 0
	for i in maxi(pa.nums.size(), pb.nums.size()):
		var x := int(_part(pa, i)) if _part(pa, i) != "x" else 0
		var y := int(_part(pb, i)) if _part(pb, i) != "x" else 0
		if x != y:
			return -1 if x < y else 1
	if pa.has_label != pb.has_label:
		return 1 if pb.has_label else -1
	return signi(pa.label.naturalnocasecmp_to(pb.label))


static func _meta(id: String, key: String, default: Variant) -> Variant:
	var mod = _gdpatch_mod(id)
	var meta = mod.get("meta") if mod != null else null
	var value = meta.get(key) if meta else null
	return default if value == null else value


static func version() -> String:
	return str(_meta("snapticbase", "version", "no verison"))


static func get_mod(id: String) -> Dictionary:
	for m in mods:
		if m.id == id:
			return m
	return {}


static func add_menu_button(label: String, callback: Callable) -> void:
	_add_menu_entry(label, callback, DEFAULT_ANCHOR, false)


static func add_menu_button_below(label: String, callback: Callable, anchor: String) -> void:
	_add_menu_entry(label, callback, anchor, false)


static func add_menu_button_above(label: String, callback: Callable, anchor: String) -> void:
	_add_menu_entry(label, callback, anchor, true)


static func settings(id: String) -> RefCounted:
	_boot()
	if not _settings_stores.has(id):
		var store: RefCounted = load(_dir + "settings_store.gd").new()
		store.setup(id)
		_settings_stores[id] = store
	return _settings_stores[id]


static func add_settings_page(id: String, builder: Callable) -> void:
	_settings_pages[id] = builder


static func has_settings(id: String) -> bool:
	return _settings_pages.has(id)


static func open_settings(id: String, under: Control = null) -> void:
	if not has_settings(id):
		return
	if not is_instance_valid(_settings_panels.get(id)):
		var panel: Control = load(_dir + "settings_panel.gd").new()
		panel.setup(settings(id))
		_settings_pages[id].call(panel)
		_settings_panels[id] = panel
	_settings_panels[id].open(under)


static func create_panel(title: String, size: Vector2 = Vector2(560, 300)) -> Control:
	_boot()
	var panel: Control = load(_dir + "menu_panel.gd").new()
	panel.build(title, size)
	return panel


static func on_scene(path: String, callback: Callable) -> void:
	_boot()
	if not _scene_hooks.has(path):
		_scene_hooks[path] = []
	_scene_hooks[path].append(callback)
	var pending: Array[Node] = [_tree().root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.scene_file_path == path:
			_run_hook.call_deferred(callback, node)
		pending.append_array(node.get_children())


static func load_asset(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("[snapticbase] asset not found: " + path)
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	match path.get_extension().to_lower():
		"png", "jpg", "jpeg", "webp":
			var image := Image.new()
			var err := ERR_FILE_UNRECOGNIZED
			match path.get_extension().to_lower():
				"png":
					err = image.load_png_from_buffer(bytes)
				"webp":
					err = image.load_webp_from_buffer(bytes)
				_:
					err = image.load_jpg_from_buffer(bytes)
			if err != OK:
				return null
			image.generate_mipmaps()
			return ImageTexture.create_from_image(image)
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			return mp3
		"wav":
			return _wav(bytes)
		"txt", "json", "cfg", "md":
			return bytes.get_string_from_utf8()
	return bytes


static func _boot() -> void:
	if is_instance_valid(_node):
		return
	var instance := new()
	_node = instance
	_tree().root.add_child.call_deferred(instance)
	_hook_menu()


static func _hook_menu() -> void:
	if _menu_hooked:
		return
	_menu_hooked = true
	on_scene(MENU_SCENE, _on_menu_scene)


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _run_hook(callback: Callable, node: Node) -> void:
	if not is_instance_valid(node) or not callback.is_valid():
		return
	var done: Array = node.get_meta("snaptic_hooks", [])
	if callback in done:
		return
	done.append(callback)
	node.set_meta("snaptic_hooks", done)
	callback.call(node)


func _on_node_added(node: Node) -> void:
	for callback in _scene_hooks.get(node.scene_file_path, []):
		_run_hook.call_deferred(callback, node)


static func _on_menu_scene(node: Node) -> void:
	menu = node
	if not _startup_done:
		_startup_done = true
		var problems := check_dependencies()
		var ids: Array[String] = []
		for m in mods:
			ids.append(m.id)
		var text := ", ".join(ids) if not ids.is_empty() else "none"
		var warning := ""
		if not problems.is_empty():
			warning = "%d dependency problem%s, check log" % [problems.size(), "" if problems.size() == 1 else "s"]
		_node._banner(text, warning)
	_queue_menu_refresh()


static func _queue_menu_refresh() -> void:
	if not _menu_queued:
		_menu_queued = true
		_refresh_menu.call_deferred()


static func _refresh_menu() -> void:
	_menu_queued = false
	if not is_instance_valid(menu):
		return
	var list := menu.get_node_or_null(MENU_LIST)
	var template := list.get_node_or_null(MENU_TEMPLATE) if list else null
	if template == null:
		push_warning("[snapticbase] menu layout not recognised, skipping buttons")
		return
	for entry in _menu_entries:
		if is_instance_valid(entry.get("button")):
			continue
		var button: Button = template.duplicate(Node.DUPLICATE_SCRIPTS)
		button.name = entry.label
		button.text = entry.label
		button.pressed.connect(AudioManager.play_sound_effect.bind(SFX.Name.MENU_SELECT))
		button.mouse_entered.connect(AudioManager.play_sound_effect.bind(SFX.Name.MENU_HOVER))
		button.pressed.connect(entry.callback)
		list.add_child(button)
		entry["button"] = button
	var order := _menu_order(list)
	for i in order.size():
		list.move_child(order[i], i)


static func _add_menu_entry(label: String, callback: Callable, anchor: String, above: bool) -> void:
	_boot()
	_menu_entries.append({"label": label, "callback": callback, "anchor": anchor, "above": above})
	_queue_menu_refresh()


static func _menu_order(list: Node) -> Array:
	var native: Array[Node] = []
	var own: Dictionary = {}
	for entry in _menu_entries:
		own[entry.button] = entry
	for child in list.get_children():
		if not own.has(child):
			native.append(child)

	var known := {}
	for n in native:
		known[n.name.to_lower()] = true
		known[str(n.get("text")).to_lower()] = true
	for entry in _menu_entries:
		known[entry.label.to_lower()] = true
	for entry in _menu_entries:
		if not known.has(entry.anchor.to_lower()):
			entry.anchor = DEFAULT_ANCHOR
			entry.above = false

	var order: Array = []
	var placed := {}
	for n in native:
		_place(n, [n.name, n.get("text")], order, placed)
	for entry in _menu_entries:
		if not placed.has(entry):
			order.append(entry.button)
	return order


static func _place(node: Node, names: Array, order: Array, placed: Dictionary) -> void:
	var lowered := names.map(func(n): return str(n).to_lower())
	_place_group(true, lowered, order, placed)
	order.append(node)
	_place_group(false, lowered, order, placed)


static func _place_group(above: bool, anchors: Array, order: Array, placed: Dictionary) -> void:
	var group: Array = []
	for entry in _menu_entries:
		if not placed.has(entry) and entry.above == above and entry.anchor.to_lower() in anchors:
			group.append(entry)
	group.sort_custom(func(a, b): return a.label.to_lower() < b.label.to_lower())
	for entry in group:
		if not placed.has(entry):
			placed[entry] = true
			_place(entry.button, [entry.label], order, placed)


static func _show_mods() -> void:
	if not is_instance_valid(_mods_menu):
		var entries: Array = []
		for m in mods:
			entries.append({
				"id": m.id, "dir": m.dir, "name": m.get("name", m.id),
				"version": m.get("version", ""), "authors": m.get("authors", []),
				"description": m.get("description", ""),
				"website": m.get("website", ""),
			})
		entries.sort_custom(func(a, b) -> bool:
			if (a.id == "snapticbase") != (b.id == "snapticbase"):
				# good ux trust me im the ux master
				return b.id == "snapticbase"
			return a.name.naturalnocasecmp_to(b.name) < 0)
		_mods_menu = load(_dir + "mods_menu.gd").new()
		_mods_menu.setup(entries)
	_mods_menu.open()


static func _log(msg: String) -> void:
	print("[snapticbase] ", msg)


static func _wav(bytes: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	var pos := 12
	var found := false
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size := bytes.decode_u32(pos + 4)
		if id == "fmt ":
			if bytes.decode_u16(pos + 8) != 1 or bytes.decode_u16(pos + 22) != 16:
				push_error("[snapticbase] wav must be 16 bit pcm")
				return null
			stream.stereo = bytes.decode_u16(pos + 10) == 2
			stream.mix_rate = bytes.decode_u32(pos + 12)
			stream.format = AudioStreamWAV.FORMAT_16_BITS
		elif id == "data":
			stream.data = bytes.slice(pos + 8, pos + 8 + size)
			found = true
		pos += 8 + size + (size & 1)
	return stream if found else null


func _banner(mods_text: String, warning: String = "") -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.05, 0.07, 0.55)
	box.set_corner_radius_all(6)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", box)
	panel.position = Vector2(16, 16)
	panel.modulate.a = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	row.add_child(_label("snaptic base |", Color(0.94, 0.94, 0.96)))
	row.add_child(_label(mods_text, Color(0.65, 0.89, 0.75)))
	if warning != "":
		row.add_child(_label("|", Color(0.94, 0.94, 0.96)))
		row.add_child(_label(warning, Color(0.95, 0.45, 0.45)))

	layer.add_child(panel)
	add_child(layer)
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.4)
	tween.tween_interval(3.5)
	tween.tween_property(panel, "modulate:a", 0.0, 0.8)
	tween.tween_callback(layer.queue_free)


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	return label
