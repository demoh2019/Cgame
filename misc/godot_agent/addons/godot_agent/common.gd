extends RefCounted
## Shared helpers for the agent tools. Everything here is static and side-effect free.

const MAX_OUT := 6000


## Normalises a user supplied path to "res://..." or returns "" when it is unsafe
## (absolute, escaping the project, or inside hidden folders such as .godot/.git).
static func res_path(p: String) -> String:
	var s := p.strip_edges()
	if s.begins_with("res://"):
		s = s.substr(6)
	elif s.begins_with("/") or s.contains(":") or s.contains("\\"):
		return ""
	s = s.simplify_path()
	if s.is_empty() or s == "." or s.begins_with("..") or s.contains("/../"):
		return ""
	for part in s.split("/"):
		if part.begins_with("."):
			return ""
	return "res://" + s


static func trunc(text: String, limit: int = MAX_OUT) -> String:
	if text.length() <= limit:
		return text
	return text.substr(0, limit) + "\n...(+%d chars)" % (text.length() - limit)


## Short, single-line representation of a value for reports.
static func fmt(v: Variant, limit: int = 40) -> String:
	var s: String
	if v is Resource and not (v as Resource).resource_path.is_empty() and not (v as Resource).resource_path.contains("::"):
		s = (v as Resource).resource_path
	elif v is Object:
		s = "<%s>" % (v as Object).get_class()
	else:
		s = var_to_str(v)
	s = s.replace("\n", " ").replace("\t", " ")
	while s.contains("  "):
		s = s.replace("  ", " ")
	if s.length() > limit:
		s = s.substr(0, limit - 1) + "…"
	return s


## Splits a line on whitespace, keeping quoted strings and (), [], {} groups together.
static func tokenize(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var depth := 0
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			cur += c
			if c == "\\" and i + 1 < line.length():
				i += 1
				cur += line[i]
			elif c == quote:
				quote = ""
		elif c == '"' or c == "'":
			quote = c
			cur += c
		elif c == "(" or c == "[" or c == "{":
			depth += 1
			cur += c
		elif c == ")" or c == "]" or c == "}":
			depth = maxi(0, depth - 1)
			cur += c
		elif (c == " " or c == "\t") and depth == 0:
			if cur != "":
				out.append(cur)
				cur = ""
		else:
			cur += c
		i += 1
	if cur != "":
		out.append(cur)
	return out


## Parses "key=value" into [key, value]. Returns [] when there is no '='.
static func split_kv(tok: String) -> Array:
	var eq := tok.find("=")
	if eq <= 0:
		return []
	return [tok.substr(0, eq), tok.substr(eq + 1)]


## Generic value parser: Godot literals (Vector2(1,2), 3, true, [1,2]) or a plain string.
static func parse_value(raw: String) -> Variant:
	var s := raw.strip_edges()
	if s == "null":
		return null
	var v: Variant = str_to_var(s)
	if v == null:
		return s
	return v


## Property metadata lookup by name for any object.
static func prop_info(obj: Object, name: String) -> Dictionary:
	for info in obj.get_property_list():
		if info.name == name:
			return info
	return {}


## Converts a compact textual value to the type expected by the given property.
## Shorthands: "10,20" for vectors, "#ff0000"/"red" for colors, enum names, res:// paths,
## "new:ClassName" for fresh resources. Returns [ok, value_or_error].
static func coerce(info: Dictionary, raw: String) -> Array:
	var t: int = info.get("type", TYPE_NIL)
	var s := raw.strip_edges()
	match t:
		TYPE_BOOL:
			var l := s.to_lower()
			if l in ["true", "1", "yes", "on"]:
				return [true, true]
			if l in ["false", "0", "no", "off"]:
				return [true, false]
			return [false, "expected bool, got '%s'" % s]
		TYPE_INT:
			if s.is_valid_int():
				return [true, s.to_int()]
			if int(info.get("hint", 0)) == PROPERTY_HINT_ENUM or int(info.get("hint", 0)) == PROPERTY_HINT_FLAGS:
				var idx := 0
				for item in String(info.get("hint_string", "")).split(","):
					var kv := item.split(":")
					var val := idx
					if kv.size() > 1 and kv[1].is_valid_int():
						val = kv[1].to_int()
					if kv[0].strip_edges().to_lower() == s.to_lower():
						return [true, val]
					idx = val + 1
				return [false, "unknown enum '%s' (%s)" % [s, info.get("hint_string", "")]]
			return [false, "expected int, got '%s'" % s]
		TYPE_FLOAT:
			if s.is_valid_float():
				return [true, s.to_float()]
			return [false, "expected float, got '%s'" % s]
		TYPE_STRING:
			if s.length() >= 2 and (s.begins_with('"') or s.begins_with("'")):
				var parsed: Variant = str_to_var(s)
				if parsed is String:
					return [true, parsed]
			return [true, s]
		TYPE_STRING_NAME:
			return [true, StringName(s)]
		TYPE_NODE_PATH:
			return [true, NodePath(s)]
		TYPE_COLOR:
			if s.begins_with("Color("):
				return [true, str_to_var(s)]
			var col := Color.from_string(s, Color(0, 0, 0, -1))
			if col.a < 0.0:
				return [false, "bad color '%s'" % s]
			return [true, col]
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I:
			if not s.contains("("):
				var parts := s.split(",")
				var f: Array[float] = []
				for part in parts:
					if not part.strip_edges().is_valid_float():
						return [false, "bad vector '%s'" % s]
					f.append(part.strip_edges().to_float())
				match t:
					TYPE_VECTOR2:
						if f.size() == 2: return [true, Vector2(f[0], f[1])]
					TYPE_VECTOR2I:
						if f.size() == 2: return [true, Vector2i(int(f[0]), int(f[1]))]
					TYPE_VECTOR3:
						if f.size() == 3: return [true, Vector3(f[0], f[1], f[2])]
					TYPE_VECTOR3I:
						if f.size() == 3: return [true, Vector3i(int(f[0]), int(f[1]), int(f[2]))]
					TYPE_VECTOR4:
						if f.size() == 4: return [true, Vector4(f[0], f[1], f[2], f[3])]
					TYPE_VECTOR4I:
						if f.size() == 4: return [true, Vector4i(int(f[0]), int(f[1]), int(f[2]), int(f[3]))]
				return [false, "wrong component count in '%s'" % s]
			return [true, str_to_var(s)]
		TYPE_OBJECT:
			if s == "null":
				return [true, null]
			if s.begins_with("res://"):
				if not ResourceLoader.exists(s):
					return [false, "missing resource " + s]
				return [true, load(s)]
			if s.begins_with("new:"):
				var cls := s.substr(4)
				if not ClassDB.class_exists(cls) or not ClassDB.can_instantiate(cls):
					return [false, "cannot instantiate " + cls]
				return [true, ClassDB.instantiate(cls)]
			return [false, "expected res:// path, null or new:Class, got '%s'" % s]
		_:
			return [true, parse_value(s)]
