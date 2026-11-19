@tool
extends RefCounted

# All writes are intentionally restricted to text assets inside res://.
const MAX_FILES := 24
const MAX_BYTES := 262144
const EXTENSIONS := ["gd", "tscn", "tres", "gdshader", "json", "txt", "md", "csv", "svg", "cfg"]


static func is_safe_path(path: String) -> bool:
	if not path.begins_with("res://"):
		return false
	var relative := path.trim_prefix("res://")
	if relative.is_empty() or relative.length() > 240:
		return false
	if relative.contains("\\") or relative.contains(":") or relative.contains("\n") or relative.contains("\r"):
		return false
	for part in relative.split("/"):
		if part.is_empty() or part == "." or part == ".." or part.begins_with("."):
			return false
	if not EXTENSIONS.has(relative.get_extension().to_lower()):
		return false
	return true


static func validate_response(payload: Variant) -> Dictionary:
	if not payload is Dictionary:
		return {"ok": false, "error": "Model response is not a JSON object."}
	if not payload.get("files") is Array:
		return {"ok": false, "error": "Missing files array."}
	var files: Array = payload["files"]
	if files.is_empty() or files.size() > MAX_FILES:
		return {"ok": false, "error": "Expected 1 to %d files." % MAX_FILES}
	var unique := {}
	var output: Array[Dictionary] = []
	var total_bytes := 0
	for entry in files:
		if not entry is Dictionary or not entry.get("path") is String or not entry.get("content") is String:
			return {"ok": false, "error": "Every file needs a string path and content."}
		var path: String = entry["path"]
		var content: String = entry["content"]
		if not is_safe_path(path):
			return {"ok": false, "error": "Unsafe or unsupported file path: " + path}
		if unique.has(path):
			return {"ok": false, "error": "Duplicate path: " + path}
		unique[path] = true
		total_bytes += content.to_utf8_buffer().size()
		if total_bytes > MAX_BYTES:
			return {"ok": false, "error": "Generated content exceeds the %d-byte limit." % MAX_BYTES}
		output.append({"path": path, "content": content})
	var main_scene: Variant = payload.get("main_scene", "")
	if not main_scene is String:
		return {"ok": false, "error": "main_scene must be a string."}
	if not main_scene.is_empty() and (not is_safe_path(main_scene) or not main_scene.ends_with(".tscn")):
		return {"ok": false, "error": "Invalid main_scene path."}
	var summary: Variant = payload.get("summary", "")
	if not summary is String:
		summary = ""
	return {"ok": true, "summary": summary, "files": output, "main_scene": main_scene}


static func parse_chat_completion(response_body: String) -> Dictionary:
	var body: Variant = JSON.parse_string(response_body)
	if not body is Dictionary:
		return {"ok": false, "error": "Server returned invalid JSON."}
	if body.has("error"):
		return {"ok": false, "error": "Provider error: " + JSON.stringify(body["error"]).left(500)}
	var choices: Variant = body.get("choices", [])
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:
		return {"ok": false, "error": "No chat completion choices returned."}
	var message: Variant = choices[0].get("message", {})
	if not message is Dictionary or not message.get("content") is String:
		return {"ok": false, "error": "Assistant returned no text content."}
	var content: String = message["content"].strip_edges()
	# Some OpenAI-compatible providers wrap the JSON in Markdown fences.
	if content.begins_with("```"):
		var first_line_end := content.find("\n")
		if first_line_end < 0 or not content.ends_with("```"):
			return {"ok": false, "error": "Malformed Markdown JSON fence."}
		content = content.substr(first_line_end + 1, content.length() - first_line_end - 4).strip_edges()
	return validate_response(JSON.parse_string(content))


static func has_symlink(path: String) -> bool:
	var directory := DirAccess.open("res://")
	if directory == null:
		return true
	var current := "res://"
	for part in path.trim_prefix("res://").split("/"):
		current = current.path_join(part)
		if directory.is_link(current):
			return true
	return false


static func apply_changes(change_set: Dictionary) -> Dictionary:
	# Revalidate even when the caller already showed a preview.
	var checked := validate_response(change_set)
	if not checked["ok"]:
		return checked
	var files: Array = checked["files"]
	var scene: String = checked["main_scene"]
	if not scene.is_empty() and not FileAccess.file_exists(scene):
		var in_proposal := false
		for entry in files:
			if entry["path"] == scene:
				in_proposal = true
		if not in_proposal:
			return {"ok": false, "error": "Main scene does not exist and is not generated."}

	var originals := {}
	for entry in files:
		var path: String = entry["path"]
		if has_symlink(path):
			return {"ok": false, "error": "Symlink or junction refused: " + path}
		if DirAccess.dir_exists_absolute(path):
			return {"ok": false, "error": "Target is a directory: " + path}
		if FileAccess.file_exists(path):
			var source := FileAccess.open(path, FileAccess.READ)
			if source == null:
				return {"ok": false, "error": "Unable to read existing file: " + path}
			originals[path] = source.get_buffer(source.get_length())

	var backup_dir := "user://ai_game_builder/backups/%d" % Time.get_ticks_usec()
	for path in originals:
		var backup_path: String = backup_dir.path_join(path.trim_prefix("res://"))
		if DirAccess.make_dir_recursive_absolute(backup_path.get_base_dir()) != OK:
			return {"ok": false, "error": "Could not prepare backups."}
		var backup := FileAccess.open(backup_path, FileAccess.WRITE)
		if backup == null:
			return {"ok": false, "error": "Could not write backups."}
		backup.store_buffer(originals[path])
		backup.flush()
		if backup.get_error() != OK:
			return {"ok": false, "error": "Backup write failed."}

	var written: Array[String] = []
	for entry in files:
		var path: String = entry["path"]
		if has_symlink(path):
			_rollback(written, originals)
			return {"ok": false, "error": "Symlink appeared during apply: " + path}
		if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
			_rollback(written, originals)
			return {"ok": false, "error": "Cannot create folder for " + path}
		var target := FileAccess.open(path, FileAccess.WRITE)
		if target == null:
			_rollback(written, originals)
			return {"ok": false, "error": "Cannot write " + path}
		written.append(path)
		target.store_string(entry["content"])
		target.flush()
		if target.get_error() != OK:
			target.close()
			_rollback(written, originals)
			return {"ok": false, "error": "Incomplete write: " + path}
		target.close()

	if not scene.is_empty():
		var old_scene: Variant = ProjectSettings.get_setting("application/run/main_scene", "")
		ProjectSettings.set_setting("application/run/main_scene", scene)
		if ProjectSettings.save() != OK:
			ProjectSettings.set_setting("application/run/main_scene", old_scene)
			_rollback(written, originals)
			return {"ok": false, "error": "Failed to save project main scene."}
	return {"ok": true, "written": written.size(), "backup_dir": backup_dir if not originals.is_empty() else ""}


static func _rollback(written: Array[String], originals: Dictionary) -> void:
	for path in written:
		if originals.has(path):
			var target := FileAccess.open(path, FileAccess.WRITE)
			if target != null:
				target.store_buffer(originals[path])
				target.close()
		else:
			DirAccess.remove_absolute(path)
