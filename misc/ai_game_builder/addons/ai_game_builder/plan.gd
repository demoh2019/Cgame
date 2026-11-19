@tool
extends RefCounted

# Generated files are new, confined to this directory, and never overwrite existing files.
const OUTPUT_ROOT = "res://ai_generated/"
const MAX_FILES = 16
const MAX_FILE_CHARS = 90000
const MAX_TOTAL_CHARS = 300000
const EXTENSIONS = ["gd", "tscn", "tres", "gdshader", "json", "md"]


static func parse_response(response: String) -> Dictionary:
	var source := response.strip_edges()
	if source.begins_with("```"):
		var newline := source.find("\n")
		if newline < 0:
			return _failure("Incomplete JSON code block.")
		source = source.substr(newline + 1).strip_edges()
		if source.ends_with("```"):
			source = source.substr(0, source.length() - 3).strip_edges()

	var decoded: Variant = JSON.parse_string(source)
	if typeof(decoded) != TYPE_DICTIONARY:
		return _failure("The model must return a JSON object with 'summary' and 'files'.")
	return validate(decoded)


static func validate(plan: Dictionary) -> Dictionary:
	var raw_files: Variant = plan.get("files")
	if typeof(raw_files) != TYPE_ARRAY:
		return _failure("'files' must be an array.")
	if raw_files.is_empty() or raw_files.size() > MAX_FILES:
		return _failure("A plan must contain between 1 and %d files." % MAX_FILES)

	var summary: Variant = plan.get("summary", "")
	if typeof(summary) != TYPE_STRING:
		return _failure("'summary' must be a string.")

	var seen := {}
	var files: Array[Dictionary] = []
	var total_size := 0
	for entry in raw_files:
		if typeof(entry) != TYPE_DICTIONARY:
			return _failure("Each file must be an object.")
		var path: Variant = entry.get("path")
		var content: Variant = entry.get("content")
		if typeof(path) != TYPE_STRING or typeof(content) != TYPE_STRING:
			return _failure("Each file needs string 'path' and 'content' fields.")
		var problem := path_error(path)
		if not problem.is_empty():
			return _failure(problem)
		if content.is_empty() or content.length() > MAX_FILE_CHARS:
			return _failure("File content is empty or too large: %s" % path)
		total_size += content.length()
		if total_size > MAX_TOTAL_CHARS:
			return _failure("Generated content exceeds the size limit.")
		if seen.has(path):
			return _failure("Duplicate file path: %s" % path)
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
			return _failure("Existing files cannot be overwritten: %s" % path)
		seen[path] = true
		files.append({"path": path, "content": content})

	return {"ok": true, "summary": summary.left(1500), "files": files}


static func path_error(path: String) -> String:
	if not path.begins_with(OUTPUT_ROOT):
		return "All paths must start with %s" % OUTPUT_ROOT
	if path.contains("\\"):
		return "Invalid path: %s" % path
	var relative := path.substr(OUTPUT_ROOT.length())
	if relative.is_empty() or relative.contains("//") or relative.contains(":"):
		return "Invalid relative path: %s" % path

	var allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
	for segment in relative.split("/"):
		if segment.is_empty() or segment == "." or segment == ".." or segment.begins_with("."):
			return "Unsafe path component: %s" % path
		for i in range(segment.length()):
			if not allowed.contains(segment[i]):
				return "Unsupported path character: %s" % path
		var stem := segment.get_basename().to_upper()
		if stem in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "LPT1", "LPT2", "LPT3"]:
			return "Reserved device name in path: %s" % path

	if not (path.get_extension().to_lower() in EXTENSIONS):
		return "Unsupported file extension: %s" % path
	return ""


static func apply(plan: Dictionary) -> Dictionary:
	# Revalidate at the moment of writing, not just when previewing.
	var checked := validate(plan)
	if not checked["ok"]:
		return checked

	var created: Array[String] = []
	for entry in checked["files"]:
		var path: String = entry["path"]
		if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
			_rollback(created)
			return _failure("Failed to create directory for: %s" % path)
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
			_rollback(created)
			return _failure("A file appeared while applying: %s" % path)

		var handle := FileAccess.open(path, FileAccess.WRITE)
		if handle == null:
			_rollback(created)
			return _failure("Failed to create: %s" % path)
		handle.store_string(entry["content"])
		var write_error := handle.get_error()
		handle.close()
		if write_error != OK:
			DirAccess.remove_absolute(path)
			_rollback(created)
			return _failure("Failed to write: %s" % path)
		created.append(path)
	return {"ok": true, "paths": created}


static func _rollback(paths: Array[String]) -> void:
	for path in paths:
		DirAccess.remove_absolute(path)


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
