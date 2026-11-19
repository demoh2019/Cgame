@tool
extends RefCounted

# Cheap, deterministic checks before displaying/applying generated code.
# These are not a substitute for headless import or gameplay tests.
const OUTPUT_ROOT = "res://ai_generated/"
const RESOURCE_FIELD = "path=\""


static func inspect_files(files: Array[Dictionary]) -> String:
	var paths := {}
	for entry in files:
		paths[str(entry["path"])] = true

	for entry in files:
		var path: String = entry["path"]
		var content: String = entry["content"]
		if path.ends_with(".gd"):
			for line in content.split("\n"):
				if line.strip_edges().begins_with("@tool"):
					return "Editor-executed @tool scripts are not allowed: %s" % path

		if path.ends_with(".json"):
			var parser := JSON.new()
			if parser.parse(content) != OK:
				return "Malformed JSON in %s: %s" % [path, parser.get_error_message()]

		if path.ends_with(".tscn") or path.ends_with(".tres"):
			var error := _validate_resource_paths(path, content, paths)
			if not error.is_empty():
				return error

	return ""


static func _validate_resource_paths(path: String, content: String, paths: Dictionary) -> String:
	var offset := 0
	while true:
		var found := content.find(RESOURCE_FIELD, offset)
		if found < 0:
			return ""
		var start := found + RESOURCE_FIELD.length()
		var end := content.find("\"", start)
		if end < 0:
			return "Unterminated path property in: %s" % path
		var referenced: String = content.substr(start, end - start)
		offset = end + 1
		if referenced.begins_with(OUTPUT_ROOT) and not paths.has(referenced) and not FileAccess.file_exists(referenced):
			return "Missing generated resource %s (referenced by %s)" % [referenced, path]
	return ""
