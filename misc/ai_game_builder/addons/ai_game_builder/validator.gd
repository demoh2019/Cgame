@tool
extends RefCounted

# Constrain all output to a generated area. Never overwrite existing files.
const OUTPUT_PREFIX := "res://ai_generated/"
const MAX_FILES := 16
const MAX_FILE_BYTES := 65536
const MAX_TOTAL_BYTES := 262144
const ALLOWED_EXTENSIONS := ["gd", "tscn", "tres", "gdshader", "json", "md", "txt"]


static func parse(raw: String) -> Dictionary:
	var decoder := JSON.new()
	if decoder.parse(raw) != OK:
		return _failure("The model did not return valid JSON (line %d)." % decoder.get_error_line())
	return validate(decoder.data)


static func validate(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return _failure("The response must be a JSON object.")
	var raw_plan: Dictionary = data
	var raw_files: Variant = raw_plan.get("files")
	if typeof(raw_files) != TYPE_ARRAY:
		return _failure("Missing 'files' array.")
	if raw_files.is_empty() or raw_files.size() > MAX_FILES:
		return _failure("A plan must contain 1 to %d files." % MAX_FILES)

	var summary: Variant = raw_plan.get("summary", "")
	if typeof(summary) != TYPE_STRING or summary.length() > 800:
		return _failure("'summary' must be a short string.")

	var cleaned_files: Array[Dictionary] = []
	var seen_paths := {}
	var total_bytes := 0

	for raw_file in raw_files:
		if typeof(raw_file) != TYPE_DICTIONARY:
			return _failure("Every file must be an object.")
		var file: Dictionary = raw_file
		var raw_path: Variant = file.get("path")
		var raw_content: Variant = file.get("content")
		if typeof(raw_path) != TYPE_STRING or typeof(raw_content) != TYPE_STRING:
			return _failure("Every file needs string 'path' and 'content' fields.")

		var relative_path: String = raw_path
		var content: String = raw_content
		if not _safe_relative_path(relative_path):
			return _failure("Unsafe file path: %s" % relative_path)
		if not ALLOWED_EXTENSIONS.has(relative_path.get_extension().to_lower()):
			return _failure("Unsupported extension: %s" % relative_path)
		var canonical_path := relative_path.to_lower()
		if seen_paths.has(canonical_path):
			return _failure("Duplicate file: %s" % relative_path)
		seen_paths[canonical_path] = true

		var byte_count := content.to_utf8_buffer().size()
		if byte_count == 0 or byte_count > MAX_FILE_BYTES:
			return _failure("File must contain 1 to %d UTF-8 bytes: %s" % [MAX_FILE_BYTES, relative_path])
		if content.find("\u0000") != -1:
			return _failure("NUL bytes are not allowed: %s" % relative_path)
		total_bytes += byte_count
		if total_bytes > MAX_TOTAL_BYTES:
			return _failure("Combined file size exceeds %d bytes." % MAX_TOTAL_BYTES)
		cleaned_files.append({"path": relative_path, "content": content})

	return {"ok": true, "plan": {"summary": summary, "files": cleaned_files}}


static func _safe_relative_path(path: String) -> bool:
	if path.is_empty() or path.length() > 160 or path.begins_with("/") or path.contains("\\"):
		return false
	var safe_characters := RegEx.new()
	if safe_characters.compile("^[A-Za-z0-9_./-]+\\z") != OK or safe_characters.search(path) == null:
		return false
	for part in path.split("/", true):
		if part.is_empty() or part == "." or part == ".." or part.begins_with(".") or part.ends_with("."):
			return false
		# Windows interprets reserved device names before their extension, even
		# when additional extensions are appended (e.g. CON.backup.gd).
		var stem: String = part.get_slice(".", 0).to_upper()
		if ["CON", "PRN", "AUX", "NUL"].has(stem):
			return false
		if stem.length() == 4 and (stem.begins_with("COM") or stem.begins_with("LPT")):
			var digit := stem.unicode_at(3)
			if digit >= 49 and digit <= 57:
				return false
	return true


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
