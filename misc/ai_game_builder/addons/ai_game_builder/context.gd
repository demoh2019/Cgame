@tool
extends RefCounted

## Only explicitly named, small, non-sensitive project text files can be shared.
## No project-wide scan is performed and context sharing is off by default.

const Validator = preload("res://addons/ai_game_builder/validator.gd")

const MAX_CONTEXT_FILES := 8
const MAX_CONTEXT_FILE_BYTES := 16384
const MAX_CONTEXT_TOTAL_BYTES := 65536
const BLOCKED_WORDS := ["secret", "password", "credential", "api_key", "token", "private_key"]


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "paths": [], "files": []}


static func parse_paths(raw_paths: String) -> Dictionary:
	var result: Array[String] = []
	var seen := {}
	for raw_line in raw_paths.split("\n"):
		var path := raw_line.strip_edges()
		if path.is_empty():
			continue
		if path.begins_with("res://"):
			path = path.trim_prefix("res://")
		if not Validator.is_safe_relative_path(path):
			return _fail("Invalid context path: %s" % path)
		if path == "project.godot" or path.begins_with("addons/") or path.begins_with("ai_generated/"):
			return _fail("Context path is restricted: %s" % path)
		var lower_path := path.to_lower()
		for blocked in BLOCKED_WORDS:
			if lower_path.contains(blocked):
				return _fail("Possible credential file was blocked: %s" % path)
		if seen.has(lower_path):
			return _fail("Duplicate context path: %s" % path)
		seen[lower_path] = true
		result.append(path)
		if result.size() > MAX_CONTEXT_FILES:
			return _fail("Too many context files (maximum %d)." % MAX_CONTEXT_FILES)
	if result.is_empty():
		return _fail("Enter at least one file path, or disable project context.")
	return {"ok": true, "error": "", "paths": result, "files": []}


static func has_symlink_components(relative_path: String) -> bool:
	# Every component, including directories, must stay within res://.
	var directory := DirAccess.open("res://")
	if directory == null:
		return true
	var prefix := ""
	for part in relative_path.split("/"):
		prefix += part if prefix.is_empty() else "/" + part
		if directory.is_link(prefix):
			return true
	return false


static func read_selected_paths(raw_paths: String) -> Dictionary:
	var parsed := parse_paths(raw_paths)
	if not parsed["ok"]:
		return parsed
	var selected: Array[Dictionary] = []
	var total_bytes := 0
	for path in parsed["paths"]:
		if has_symlink_components(path):
			return _fail("Symlinks are not allowed in shared context: %s" % path)
		var resource_path: String = "res://" + path
		if not FileAccess.file_exists(resource_path):
			return _fail("Context file does not exist: %s" % path)
		var file := FileAccess.open(resource_path, FileAccess.READ)
		if file == null:
			return _fail("Cannot read context file: %s" % path)
		var file_bytes := file.get_length()
		if file_bytes > MAX_CONTEXT_FILE_BYTES:
			file.close()
			return _fail("Context file is too large: %s" % path)
		var content := file.get_as_text()
		file.close()
		if content.contains("\u0000"):
			return _fail("Context file must contain text: %s" % path)
		total_bytes += content.to_utf8_buffer().size()
		if total_bytes > MAX_CONTEXT_TOTAL_BYTES:
			return _fail("Project context exceeds %d bytes." % MAX_CONTEXT_TOTAL_BYTES)
		selected.append({"path": path, "content": content})
	return {"ok": true, "error": "", "paths": parsed["paths"], "files": selected}
