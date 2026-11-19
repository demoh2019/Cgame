@tool
extends RefCounted

# An explicit, bounded find/replace edit to ONE user-approved existing file.
# This module never accepts full-file rewrites or model-provided permissions.
const Context = preload("res://addons/ai_game_builder/project_context.gd")
const QualityGate = preload("res://addons/ai_game_builder/quality_gate.gd")
const MAX_EDITS = 8
const MAX_SNIPPET_CHARS = 12000
const MAX_SOURCE_CHARS = 100000
const BACKUP_SUFFIX = ".ai_builder_backup"


static func parse_response(response: String, approved_paths: PackedStringArray) -> Dictionary:
	var text := response.strip_edges()
	if text.begins_with("```"):
		var first_newline := text.find("\n")
		if first_newline < 0:
			return _failure("Incomplete JSON block.")
		text = text.substr(first_newline + 1).strip_edges()
		if text.ends_with("```"):
			text = text.substr(0, text.length() - 3).strip_edges()
	var decoded: Variant = JSON.parse_string(text)
	return validate(decoded, approved_paths)


static func validate(raw: Variant, approved_paths: PackedStringArray) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("The response must be a JSON object.")
	var summary: Variant = raw.get("summary", "")
	var edits: Variant = raw.get("edits")
	if typeof(summary) != TYPE_STRING or typeof(edits) != TYPE_ARRAY:
		return _failure("Expected string 'summary' and array 'edits'.")
	if edits.is_empty() or edits.size() > MAX_EDITS:
		return _failure("Provide 1 to %d targeted edits." % MAX_EDITS)

	var approved := {}
	for path in approved_paths:
		if Context._is_selected_path_safe(path) and FileAccess.file_exists(path):
			approved[path] = true

	var seen := {}
	var changes: Array[Dictionary] = []
	for entry in edits:
		if typeof(entry) != TYPE_DICTIONARY:
			return _failure("Each edit must be an object.")
		var path: Variant = entry.get("path")
		var find: Variant = entry.get("find")
		var replacement: Variant = entry.get("replace")
		if typeof(path) != TYPE_STRING or typeof(find) != TYPE_STRING or typeof(replacement) != TYPE_STRING:
			return _failure("Every edit requires string path/find/replace.")
		if not approved.has(path) or not Context._is_selected_path_safe(path):
			return _failure("Editing an unapproved or unsafe file is forbidden: %s" % path)
		if seen.has(path.to_lower()):
			return _failure("Only one edit per file is allowed: %s" % path)
		seen[path.to_lower()] = true
		if find.is_empty() or find == replacement:
			return _failure("Find text must be nonempty and replacement must change it: %s" % path)
		if find.length() > MAX_SNIPPET_CHARS or replacement.length() > MAX_SNIPPET_CHARS:
			return _failure("Edit snippet exceeds the size limit: %s" % path)
		var before := FileAccess.get_file_as_string(path)
		if before.is_empty() or before.length() > MAX_SOURCE_CHARS:
			return _failure("Source file is empty, too large, or unreadable: %s" % path)
		if before.count(find) != 1:
			return _failure("Find text must match exactly once: %s" % path)
		var after := before.replace(find, replacement)
		if after.length() > MAX_SOURCE_CHARS:
			return _failure("Resulting source is too large: %s" % path)
		var inspection: String = QualityGate.inspect_files([{"path": path, "content": after}])
		if not inspection.is_empty():
			return _failure(inspection)
		changes.append({
			"path": path,
			"find": find,
			"replace": replacement,
			"before_hash": before.sha256_text(),
			"before": before,
			"after": after,
		})

	return {"ok": true, "summary": summary.left(1500), "edits": changes, "approved_paths": approved_paths}


static func apply(preview: Dictionary) -> Dictionary:
	if not preview.get("ok", false):
		return _failure("No approved edit plan.")
	var approved_paths: Variant = preview.get("approved_paths")
	if typeof(approved_paths) != TYPE_PACKED_STRING_ARRAY:
		return _failure("Missing original approved paths.")
	var edits: Variant = preview.get("edits")
	if typeof(edits) != TYPE_ARRAY:
		return _failure("Missing proposed edits.")

	# Before touching any file, check every source is still identical to the preview.
	var checked := validate({"summary": preview.get("summary", ""), "edits": edits}, approved_paths)
	if not checked["ok"]:
		return checked
	for index in range(checked["edits"].size()):
		if checked["edits"][index]["before_hash"] != edits[index].get("before_hash", ""):
			return _failure("File changed after review; generate a new edit: %s" % edits[index]["path"])
		var backup: String = checked["edits"][index]["path"] + BACKUP_SUFFIX
		if FileAccess.file_exists(backup) or DirAccess.dir_exists_absolute(backup):
			return _failure("Backup already exists, no files changed: %s" % backup)

	var backups: Array[String] = []
	for change in checked["edits"]:
		var path: String = change["path"]
		var backup := path + BACKUP_SUFFIX
		if not Context._is_selected_path_safe(path):
			_restore_backups(backups)
			return _failure("Source path became unsafe: %s" % path)
		if FileAccess.get_file_as_string(path).sha256_text() != change["before_hash"]:
			_restore_backups(backups)
			return _failure("Source changed during application: %s" % path)
		if DirAccess.copy_absolute(path, backup) != OK:
			_restore_backups(backups)
			return _failure("Could not create backup: %s" % path)
		backups.append(path)

		var handle := FileAccess.open(path, FileAccess.WRITE)
		if handle == null:
			_restore_backups(backups)
			return _failure("Could not write edit: %s" % path)
		handle.store_string(change["after"])
		var write_status := handle.get_error()
		handle.close()
		if write_status != OK or FileAccess.get_file_as_string(path) != change["after"]:
			_restore_backups(backups)
			return _failure("Write verification failed, restored backups: %s" % path)

	for path in backups:
		if DirAccess.remove_absolute(path + BACKUP_SUFFIX) != OK:
			return _failure("Edit written, but unable to remove backup for %s; inspect files." % path)
	var changed: Array[String] = []
	for edit in checked["edits"]:
		changed.append(edit["path"])
	return {"ok": true, "edited_paths": changed}


static func _restore_backups(paths: Array[String]) -> void:
	for path in paths:
		var backup := path + BACKUP_SUFFIX
		# Preserve backup on disk if restoring the original fails.
		if DirAccess.copy_absolute(backup, path) == OK:
			DirAccess.remove_absolute(backup)


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
