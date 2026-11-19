@tool
extends RefCounted

# Only text resources; nothing is written without preview approval.
const MAX_FILES := 24
const MAX_FILE_BYTES := 262144
const MAX_TOTAL_BYTES := 1048576
const ALLOWED_EXTENSIONS := ["gd", "tscn", "tres", "gdshader", "shader", "json", "md", "txt", "cfg", "csv"]


static func parse_response(text: String) -> Dictionary:
	var raw := text.strip_edges()
	var fence := String.chr(96).repeat(3)
	if raw.begins_with(fence):
		var start := raw.find("\n")
		var end := raw.rfind(fence)
		if start < 0 or end <= start:
			return _error("Incomplete JSON code block.")
		raw = raw.substr(start + 1, end - start - 1).strip_edges()
	var decoded: Variant = JSON.parse_string(raw)
	if decoded == null:
		return _error("Model returned invalid JSON.")
	return validate_plan(decoded)


static func validate_plan(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return _error("Expected a JSON object.")
	if typeof(raw.get("files")) != TYPE_ARRAY:
		return _error("Expected a files array.")
	var files: Array = raw["files"]
	if files.is_empty() or files.size() > MAX_FILES:
		return _error("A plan must contain 1-%d files." % MAX_FILES)

	var seen := {}
	var clean_files: Array[Dictionary] = []
	var total_bytes := 0
	for item in files:
		if typeof(item) != TYPE_DICTIONARY:
			return _error("Each file must be an object.")
		if typeof(item.get("path")) != TYPE_STRING or typeof(item.get("content")) != TYPE_STRING:
			return _error("Each file needs string path and content.")
		var path: String = item["path"]
		var problem := validate_path(path)
		if not problem.is_empty():
			return _error("%s: %s" % [path, problem])
		var identity := path.to_lower()
		if seen.has(identity):
			return _error("Duplicate path: " + path)
		seen[identity] = true
		var file_content: String = item["content"]
		var bytes := file_content.to_utf8_buffer().size()
		if bytes > MAX_FILE_BYTES or file_content.contains("\u0000"):
			return _error("File too large or contains NUL: " + path)
		if path.get_extension().to_lower() == "gd" and file_content.contains("@tool"):
			return _error("Generated editor-executed @tool scripts are not supported: " + path)
		total_bytes += bytes
		if total_bytes > MAX_TOTAL_BYTES:
			return _error("Plan exceeds the 1 MiB size limit.")
		clean_files.append({"path": path, "content": file_content})

	var main_scene: Variant = raw.get("main_scene", "")
	if typeof(main_scene) != TYPE_STRING:
		return _error("main_scene must be a path string.")
	if not main_scene.is_empty():
		var main_found := false
		for item in clean_files:
			if item["path"] == main_scene:
				main_found = true
				break
		if main_scene.get_extension().to_lower() != "tscn" or not main_found:
			return _error("main_scene must point to an exact generated .tscn path.")

	var summary: Variant = raw.get("summary", "")
	if typeof(summary) != TYPE_STRING:
		return _error("summary must be a string.")
	return {
		"ok": true,
		"summary": (summary as String).substr(0, 1500),
		"main_scene": main_scene,
		"files": clean_files,
		"total_bytes": total_bytes
	}


static func validate_path(path: String) -> String:
	if path.is_empty() or path.length() > 180:
		return "Path is empty or too long."
	if path.begins_with("/") or path.contains("\\") or path.contains(":"):
		return "Absolute paths, backslashes and colons are forbidden."
	if path.contains("\n") or path.contains("\r"):
		return "Newlines in paths are forbidden."
	if path.to_lower().begins_with("addons/"):
		return "Writing editor addons is not supported."
	if path.get_file().to_lower() in ["override.cfg", "export_presets.cfg"]:
		return "Overriding project or export settings is not supported."
	for segment in path.split("/"):
		if segment.is_empty() or segment == "." or segment == "..":
			return "Empty, dot and parent segments are forbidden."
		if segment.begins_with(".") or segment.ends_with("."):
			return "Hidden and trailing-dot names are forbidden."
	if not ALLOWED_EXTENSIONS.has(path.get_extension().to_lower()):
		return "Unsupported file extension."
	return ""


static func apply_plan(raw: Variant, allow_overwrite: bool = false) -> Dictionary:
	# Revalidate at the write boundary, including symlink checks.
	var plan := validate_plan(raw)
	if not plan["ok"]:
		return plan

	var files: Array = plan["files"]
	var replaced: Array[String] = []
	for item in files:
		var relative: String = item["path"]
		var destination := "res://" + relative
		if _is_symlink_path(relative):
			return _error("Refusing to write through a symbolic link: " + relative)
		if DirAccess.dir_exists_absolute(destination):
			return _error("A directory already occupies: " + relative)
		if FileAccess.file_exists(destination):
			if not allow_overwrite:
				return _error("File already exists (enable overwrite): " + relative)
			replaced.append(relative)

	var backup_root := ""
	if not replaced.is_empty():
		backup_root = "user://ai_game_builder_backups/%d_%d" % [
			int(Time.get_unix_time_from_system()), Time.get_ticks_usec()
		]
		for relative in replaced:
			var backup := backup_root.path_join(relative)
			if DirAccess.make_dir_recursive_absolute(backup.get_base_dir()) != OK:
				return _error("Cannot create backup directory.")
			if DirAccess.copy_absolute("res://" + relative, backup) != OK:
				return _error("Cannot back up: " + relative)

	# Create parents first to limit partially written plans.
	for item in files:
		var dir_path: String = ("res://" + item["path"]).get_base_dir()
		if DirAccess.make_dir_recursive_absolute(dir_path) != OK:
			return _error("Cannot create folder: " + dir_path)
		if _is_symlink_path(item["path"]):
			return _error("Directory changed into a symlink: " + item["path"])

	var written: Array[String] = []
	for item in files:
		var path: String = item["path"]
		var destination := "res://" + path
		# Recheck after every preceding write in case the filesystem changed.
		if _is_symlink_path(path):
			return _write_failed(path + " became a symlink", written, replaced, backup_root)
		if FileAccess.file_exists(destination) and not replaced.has(path):
			return _write_failed(path + " appeared unexpectedly", written, replaced, backup_root)
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			return _write_failed("Cannot open " + path, written, replaced, backup_root)
		written.append(path)
		file.store_string(item["content"])
		file.flush()
		var write_error := file.get_error()
		file.close()
		if write_error != OK:
			return _write_failed("Cannot finish writing " + path, written, replaced, backup_root)
	return {"ok": true, "written": written, "backup_root": backup_root}


static func _write_failed(reason: String, written: Array[String], replaced: Array[String], backup_root: String) -> Dictionary:
	var restored := true
	for path in written:
		var destination := "res://" + path
		if replaced.has(path):
			var backup := backup_root.path_join(path)
			if DirAccess.copy_absolute(backup, destination) != OK:
				restored = false
		elif FileAccess.file_exists(destination) and DirAccess.remove_absolute(destination) != OK:
			restored = false
	return {
		"ok": false,
		"error": reason + (". Files restored." if restored else ". ROLLBACK INCOMPLETE: restore from backups."),
		"rolled_back": restored,
		"written": ([] if restored else written),
		"backup_root": backup_root
	}

static func _is_symlink_path(relative: String) -> bool:
	var directory := DirAccess.open("res://")
	if directory == null:
		return true
	for segment in relative.split("/"):
		if directory.is_link(segment):
			return true
		if directory.dir_exists(segment):
			if directory.change_dir(segment) != OK:
				return true
		else:
			break
	return false


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
