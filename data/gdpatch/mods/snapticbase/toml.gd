extends RefCounted

const BARE_KEY := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"

var _s := ""
var _i := 0
var _failed := false
var _path := ""
var _defined := {}


static func parse_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var reader := new()
	reader._path = path
	reader._s = FileAccess.get_file_as_string(path)
	return reader._parse()


static func parse(text: String) -> Dictionary:
	var reader := new()
	reader._s = text
	return reader._parse()

# adapted from an library this is probably passing the toml spec who knows it works
func _assign(from: Dictionary, keys: Array, value: Variant) -> void:
	var target := _open_table(from, keys.slice(0, keys.size() - 1), false)
	if _failed:
		return
	var last: String = keys[keys.size() - 1]
	if target.has(last):
		_fail("duplicate key `%s`" % last)
		return
	target[last] = value

func _parse() -> Dictionary:
	var root := {}
	var table := root
	while not _failed:
		_skip_blank()
		if _i >= _s.length():
			break

		if _s[_i] == "[":
			var is_array := _s.substr(_i, 2) == "[["
			_i += 2 if is_array else 1
			var keys := _read_keys()
			_expect("]")
			if is_array:
				_expect("]")
			if is_array:
				for defined in _defined.keys():
					if defined.slice(0, keys.size()) == keys:
						_defined.erase(defined)
			elif _defined.has(keys):
				_fail("duplicate key `%s`" % ".".join(keys))
				break
			else:
				_defined[keys] = true
			table = _open_table(root, keys, is_array)
		else:
			var keys := _read_keys()
			_expect("=")
			var value = _read_value()
			if _failed:
				break
			_assign(table, keys, value)
	return root


func _open_table(from: Dictionary, keys: Array, is_array: bool) -> Dictionary:
	var current := from
	for n in keys.size():
		var key: String = keys[n]
		if is_array and n == keys.size() - 1:
			if current.has(key) and not current[key] is Array:
				_fail("duplicate key `%s`" % key)
				return {}
			if not current.has(key):
				current[key] = []
			var fresh := {}
			current[key].append(fresh)
			return fresh
		var next = current.get(key)
		if next is Array and not next.is_empty():
			next = next[next.size() - 1]
		if current.has(key) and not next is Dictionary:
			_fail("duplicate key `%s`" % key)
			return {}
		if not next is Dictionary:
			next = {}
			current[key] = next
		current = next
	return current


func _read_keys() -> Array:
	var keys := []
	while true:
		_skip_inline()
		if _i >= _s.length():
			_fail("unexpected end of file in key")
			break
		var c := _s[_i]
		if c == "\"" or c == "'":
			keys.append(_read_string())
		else:
			var start := _i
			while _i < _s.length() and BARE_KEY.contains(_s[_i]):
				_i += 1
			if _i == start:
				_fail("expected a key")
				break
			keys.append(_s.substr(start, _i - start))
		_skip_inline()
		if _i < _s.length() and _s[_i] == ".":
			_i += 1
			continue
		break
	if keys.is_empty():
		keys.append("")
	return keys


func _read_value() -> Variant:
	_skip_inline()
	if _i >= _s.length():
		_fail("missing value")
		return null

	var c := _s[_i]
	match c:
		"\"", "'":
			return _read_string()
		"[":
			return _read_array()
		"{":
			return _read_inline_table()

	var start := _i
	while _i < _s.length() and not _s[_i] in [",", "]", "}", "#", "\n", "\r", " ", "\t"]:
		_i += 1
	var token := _s.substr(start, _i - start)
	if token == "true":
		return true
	if token == "false":
		return false
	var number := token.replace("_", "")
	if number.is_valid_int():
		return number.to_int()
	if number.is_valid_float():
		return number.to_float()
	if number.is_valid_hex_number(true):
		return number.hex_to_int()
	_fail("missing value" if token == "" else "invalid value `%s`" % token)
	return null


func _read_string() -> String:
	var quote := _s[_i]
	if _s.substr(_i, 3) == quote.repeat(3):
		return _read_multiline_string(quote)
	_i += 1
	var start := _i
	while _i < _s.length() and _s[_i] != quote and _s[_i] != "\n":
		if quote == "\"" and _s[_i] == "\\":
			_i += 1
		_i += 1
	if _i >= _s.length() or _s[_i] != quote:
		_fail("unterminated string")
		return ""
	var raw := _s.substr(start, _i - start)
	_i += 1
	if quote == "'":
		return raw
	var decoded = JSON.parse_string("\"" + raw + "\"")
	return decoded if decoded is String else raw

func _read_multiline_string(quote: String) -> String:
	var delimiter := quote.repeat(3)
	_i += 3
	if _s.substr(_i, 2) == "\r\n":
		_i += 2
	elif _s.substr(_i, 1) == "\n":
		_i += 1
	var start := _i
	while _i < _s.length() and _s.substr(_i, 3) != delimiter:
		if quote == "\"" and _s[_i] == "\\":
			_i += 1
		_i += 1
	if _i >= _s.length():
		_fail("unterminated multiline string")
		return ""
	var extra := 0
	while extra < 2 and _s.substr(_i + 3, 1) == quote:
		_i += 1
		extra += 1
	var raw := _s.substr(start, _i - start).replace("\r\n", "\n")
	_i += 3
	if quote == "'":
		return raw

	var json := ""
	var n := 0
	while n < raw.length():
		var ch := raw[n]
		if ch == "\\":
			var m := n + 1
			while m < raw.length() and (raw[m] == " " or raw[m] == "\t"):
				m += 1
			if m < raw.length() and raw[m] == "\n":
				while m < raw.length() and raw[m] in [" ", "\t", "\n"]:
					m += 1
				n = m
			else:
				json += raw.substr(n, 2)
				n += 2
			continue
		match ch:
			"\n":
				json += "\\n"
			"\t":
				json += "\\t"
			"\"":
				json += "\\\""
			_:
				json += ch
		n += 1
	var decoded = JSON.parse_string("\"" + json + "\"")
	return decoded if decoded is String else raw

func _read_array() -> Array:
	_i += 1
	var items := []
	while not _failed:
		_skip_blank()
		if _i >= _s.length():
			_fail("unterminated array")
			break
		if _s[_i] == "]":
			_i += 1
			break
		items.append(_read_value())
		_skip_blank()
		if _i < _s.length() and _s[_i] == ",":
			_i += 1
	return items


func _read_inline_table() -> Dictionary:
	_i += 1
	var table := {}
	while not _failed:
		_skip_blank()
		if _i >= _s.length():
			_fail("unterminated inline table")
			break
		if _s[_i] == "}":
			_i += 1
			break
		var keys := _read_keys()
		_expect("=")
		var value = _read_value()
		_assign(table, keys, value)
		_skip_blank()
		if _i < _s.length() and _s[_i] == ",":
			_i += 1
	return table


func _expect(c: String) -> void:
	_skip_inline()
	if _i < _s.length() and _s[_i] == c:
		_i += 1
		return
	_fail("expected '%s'" % c)


func _skip_inline() -> void:
	while _i < _s.length() and (_s[_i] == " " or _s[_i] == "\t"):
		_i += 1


func _skip_blank() -> void:
	while _i < _s.length():
		var c := _s[_i]
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			_i += 1
		elif c == "#":
			while _i < _s.length() and _s[_i] != "\n":
				_i += 1
		else:
			break


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	var line := _s.substr(0, _i).count("\n") + 1
	push_error("[[snapticbase] toml %s:%d: %s" % [_path, line, message])