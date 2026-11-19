@tool
extends RefCounted
## Transactional best-effort creation of *new* AI-generated files.
## Existing files are never overwritten, including temporary staging files.

const PLAN = preload("res://addons/ai_game_builder/plan.gd")


static func preflight(plan: Dictionary) -> Dictionary:
	var verdict: Dictionary = PLAN.validate(plan)
	if not verdict.ok:
		return verdict
	for entry in plan["files"]:
		var path: String = entry["path"]
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			return {"ok": false, "error": "Already exists (no overwrite): " + path}
		if FileAccess.file_exists(path + ".ai_tmp"):
			return {"ok": false, "error": "Temporary file already exists: " + path}
	return {"ok": true, "error": ""}


static func apply(plan: Dictionary, set_main_scene: bool = false) -> Dictionary:
	var verdict := preflight(plan)
	if not verdict.ok:
		return verdict
	var staged: Array[String] = []
	var created: Array[String] = []
	for entry in plan["files"]:
		var path: String = entry["path"]
		var abs_path := ProjectSettings.globalize_path(path)
		var err := DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
		if err != OK:
			return _rollback(staged, created, "Could not create folder for: " + path)
		var temporary := path + ".ai_tmp"
		var output := FileAccess.open(temporary, FileAccess.WRITE)
		if output == null:
			return _rollback(staged, created, "Could not stage: " + path)
		staged.append(temporary)
		output.store_string(entry["content"])
		output.flush()
		var write_error := output.get_error()
		output.close()
		if write_error != OK:
			return _rollback(staged, created, "Could not write: " + path)

	# Recheck destinations before any staged file is committed.
	for entry in plan["files"]:
		var path: String = entry["path"]
		if FileAccess.file_exists(path):
			return _rollback(staged, created, "Created concurrently: " + path)

	for entry in plan["files"]:
		var path: String = entry["path"]
		var temporary := path + ".ai_tmp"
		if FileAccess.file_exists(path):
			return _rollback(staged, created, "Created concurrently: " + path)
		var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
		if err != OK:
			return _rollback(staged, created, "Could not commit: " + path)
		staged.erase(temporary)
		created.append(path)

	if set_main_scene and not plan.get("main_scene", "").is_empty():
		var previous: Variant = ProjectSettings.get_setting("application/run/main_scene", "")
		ProjectSettings.set_setting("application/run/main_scene", plan["main_scene"])
		var save_error := ProjectSettings.save()
		if save_error != OK:
			ProjectSettings.set_setting("application/run/main_scene", previous)
			# Generated files remain available: a project settings failure should not
			# silently undo the completed file operation.
			return {"ok": false, "error": "Files created, but project.godot could not be saved.", "created": created}

	return {"ok": true, "error": "", "created": created}


static func _rollback(staged: Array[String], created: Array[String], message: String) -> Dictionary:
	for path in staged:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for path in created:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return {"ok": false, "error": message, "created": []}
