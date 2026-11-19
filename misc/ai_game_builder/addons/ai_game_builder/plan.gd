@tool
extends RefCounted

## Validate untrusted model output before previewing or applying it.
## All generated files are isolated under res://ai_generated/.
const ROOT := "res://ai_generated/"
const MAX_FILES := 20
const MAX_FILE_CHARS := 100000
const MAX_TOTAL_CHARS := 400000
const ALLOWED_EXTENSIONS := ["gd", "tscn", "tres", "gdshader", "json", "csv", "md", "txt", "cfg", "svg"]


static func parse_message(message: String) -> Dictionary:
	var parser := JSON.new()
	var error := parser.parse(message.strip_edges())
	if error != OK:
		return _failure("Invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
	return validate(parser.data)


static func validate(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	var files: Array[Dictionary] = []
	if not (raw is Dictionary):
		return _failure("The response must be a JSON object.")

	var source_files: Variant = raw.get("files", null)
	if not (source_files is Array):
		return _failure("The response needs a files array.")
	if source_files.is_empty() or source_files.size() > MAX_FILES:
		return _failure("Provide between 1 and %d files." % MAX_FILES)

	var seen := {}
	var total_chars := 0
	var tool_pattern := RegEx.create_from_string(r'(?m)^\s*@tool\b')
	for i in range(source_files.size()):
		var entry: Variant = source_files[i]
		if not (entry is Dictionary):
			errors.append("File %d must be an object." % (i + 1))
			continue

		var path_value: Variant = entry.get("path", null)
		var content_value: Variant = entry.get("content", null)
		var operation: Variant = entry.get("operation", "create")
		if not (path_value is String) or not _safe_path(path_value):
			errors.append("File %d has an unsafe path or an unsupported extension." % (i + 1))
			continue
		if not (content_value is String):
			errors.append("File %d content must be a string." % (i + 1))
			continue
		if operation != "create" and operation != "update":
			errors.append("File %d has an invalid operation." % (i + 1))
			continue
		if seen.has(path_value):
			errors.append("Duplicate destination: %s" % path_value)
			continue

		seen[path_value] = true
		if path_value.get_extension().to_lower() == "gd" and tool_pattern.search(content_value) != null:
			errors.append("%s: @tool scripts are not accepted because they can execute in the editor." % path_value)
			continue
		if content_value.is_empty() or content_value.length() > MAX_FILE_CHARS:
			errors.append("File %d must contain 1 to %d characters." % [i + 1, MAX_FILE_CHARS])
			continue
		total_chars += content_value.length()
		if total_chars > MAX_TOTAL_CHARS:
			errors.append("The proposed changes exceed the total size limit.")
			break
		files.append({"path": path_value, "content": content_value, "operation": operation})

	var summary_value: Variant = raw.get("summary", "")
	var summary := summary_value if summary_value is String else ""
	return {"ok": errors.is_empty(), "errors": errors, "files": files, "summary": summary}


static func apply(raw: Variant) -> Dictionary:
	var plan := validate(raw)
	if not plan["ok"]:
		return {"ok": false, "error": "; ".join(PackedStringArray(plan["errors"])), "written": []}

	# Preflight every file before changing anything. No silent overwrites.
	var originals := {}
	for item in plan["files"]:
		var path: String = item["path"]
		if _has_unsafe_links(path):
			return {"ok": false, "error": "Refusing to follow a symbolic link: %s" % path, "written": []}
		var exists := FileAccess.file_exists(path)
		if item["operation"] == "create" and exists:
			return {"ok": false, "error": "File already exists: %s" % path, "written": []}
		if item["operation"] == "update" and not exists:
			return {"ok": false, "error": "Cannot update a missing file: %s" % path, "written": []}
		if exists:
			var original := FileAccess.open(path, FileAccess.READ)
			if original == null:
				return {"ok": false, "error": "Cannot read original: %s" % path, "written": []}
			originals[path] = original.get_as_text()
		else:
			originals[path] = null

	var written: Array[String] = []
	for item in plan["files"]:
		var path: String = item["path"]
		var dir_path := ProjectSettings.globalize_path(path.get_base_dir())
		if DirAccess.make_dir_recursive_absolute(dir_path) != OK:
			_rollback(written, originals)
			return {"ok": false, "error": "Cannot create directory for: %s" % path, "written": []}
		if _has_unsafe_links(path):
			_rollback(written, originals)
			return {"ok": false, "error": "Refusing to follow a symbolic link: %s" % path, "written": []}

		var output := FileAccess.open(path, FileAccess.WRITE)
		if output == null:
			_rollback(written, originals)
			return {"ok": false, "error": "Cannot write file: %s" % path, "written": []}
		# Include the current file in rollback even if writing it fails.
		written.append(path)
		output.store_string(item["content"])
		output.flush()
		var write_error := output.get_error()
		output.close()
		if write_error != OK:
			_rollback(written, originals)
			return {"ok": false, "error": "Write failed: %s" % path, "written": []}

	return {"ok": true, "error": "", "written": written}


static func _rollback(written: Array[String], originals: Dictionary) -> void:
	written.reverse()
	for path in written:
		var previous: Variant = originals[path]
		if previous == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var restore := FileAccess.open(path, FileAccess.WRITE)
			if restore != null:
				restore.store_string(previous)
				restore.flush()
				restore.close()


static func _has_unsafe_links(path: String) -> bool:
	var root := DirAccess.open("res://")
	if root == null:
		return true
	var relative := path.trim_prefix("res://")
	var partial := ""
	for component in relative.split("/"):
		partial = partial.path_join(component)
		if root.is_link(partial):
			return true
	return false


static func _safe_path(path: String) -> bool:
	if not path.begins_with(ROOT) or path.length() > 240:
		return false
	var relative := path.substr(ROOT.length())
	if relative.is_empty() or relative.contains("\\") or relative.contains(":"):
		return false
	if relative.contains("\n") or relative.contains("\r") or relative.contains("\t"):
		return false
	for segment in relative.split("/"):
		if segment.is_empty() or segment.begins_with("."):
			return false
	return path.get_extension().to_lower() in ALLOWED_EXTENSIONS


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message], "files": [], "summary": ""}
