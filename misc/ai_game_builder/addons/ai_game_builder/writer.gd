@tool
extends RefCounted

const PlanValidator = preload("res://addons/ai_game_builder/validator.gd")


static func apply(plan: Dictionary) -> Dictionary:
	# Revalidate at the write boundary, not just at the UI boundary.
	var inspected := PlanValidator.validate(plan)
	if not inspected.ok:
		return inspected
	var files: Array = inspected.plan.files

	# Fail the entire operation if any target exists. Never silently overwrite.
	for item in files:
		var target := PlanValidator.OUTPUT_PREFIX + String(item.path)
		if _path_has_symlink(target):
			return {"ok": false, "error": "Symlink detected in generated output path: %s" % target}
		if FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target)):
			return {"ok": false, "error": "Refusing to overwrite existing path: %s" % target}

	var created: Array[String] = []
	for item in files:
		var target := PlanValidator.OUTPUT_PREFIX + String(item.path)
		var absolute_dir := ProjectSettings.globalize_path(target.get_base_dir())
		var directory_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
		if directory_error != OK:
			_rollback(created)
			return {"ok": false, "error": "Unable to create output directory for %s." % target}
		# Filesystem contents can change between the full-plan preflight and
		# each write. Recheck here to avoid ordinary concurrent collisions.
		# This is not atomic against a malicious racing process.
		if _path_has_symlink(target) or FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target)):
			_rollback(created)
			return {"ok": false, "error": "Output path changed since preflight: %s" % target}
		var output := FileAccess.open(target, FileAccess.WRITE)
		if output == null:
			_rollback(created)
			return {"ok": false, "error": "Unable to create %s." % target}
		output.store_string(String(item.content))
		var write_error := output.get_error()
		output.close()
		if write_error != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
			_rollback(created)
			return {"ok": false, "error": "Unable to finish writing %s." % target}
		created.append(target)
	return {"ok": true, "paths": created}


static func _rollback(created: Array[String]) -> void:
	for target in created:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(target))


# Protect against a pre-existing directory (or file) symlink redirecting the
# otherwise valid res://ai_generated/ path outside the project. This cannot
# defeat malicious concurrent filesystem changes; use a sandbox if untrusted.
static func _path_has_symlink(resource_path: String) -> bool:
	var directory := DirAccess.open("res://")
	if directory == null:
		return true
	var relative_path := resource_path.trim_prefix("res://")
	for component in relative_path.split("/", false):
		if directory.is_link(component):
			return true
		if directory.dir_exists(component):
			if directory.change_dir(component) != OK:
				return true
		else:
			return false
	return false
