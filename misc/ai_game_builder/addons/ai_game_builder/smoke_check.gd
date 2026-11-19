extends SceneTree

# Explicitly launched by the editor after the user approves file creation.
# This process loads resources to test compilation and scene parsing but NEVER
# instantiates the scene or runs a game loop. Loading resources can still have
# side effects; only use on projects whose generated source has been reviewed.
const SmokeGate = preload("res://addons/ai_game_builder/smoke_gate.gd")
const REPORT_PREFIX := "user://ai_game_builder/"


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4 or args[0] != "--report" or args[2] != "--paths":
		printerr("Usage: -- --report user://ai_game_builder/report.json --paths <JSON array>")
		quit(2)
		return
	var report_path: String = args[1]
	if not _safe_report_path(report_path):
		printerr("Refusing a report path outside user://ai_game_builder.")
		quit(2)
		return

	var raw_paths: Variant = JSON.parse_string(args[3])
	var report := SmokeGate.check(raw_paths)
	var folder := ProjectSettings.globalize_path(REPORT_PREFIX)
	var dir_error := DirAccess.make_dir_recursive_absolute(folder)
	if dir_error != OK:
		printerr("Could not create headless check output directory.")
		quit(2)
		return
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not create headless check output file.")
		quit(2)
		return
	file.store_string(JSON.stringify(report))
	file.close()
	var reported_errors: Array = report.get("errors", [])
	print("AI Game Builder headless check: %d resources, %d errors" % [
		int(report.get("checked", 0)), reported_errors.size()
	])
	quit(0 if report.ok else 1)


static func _safe_report_path(path: String) -> bool:
	if not path.begins_with(REPORT_PREFIX):
		return false
	var leaf := path.trim_prefix(REPORT_PREFIX)
	if leaf.is_empty() or leaf.begins_with(".") or leaf.length() > 70 or not leaf.ends_with(".json"):
		return false
	if leaf.contains("/") or leaf.contains("\\") or leaf.contains(".."):
		return false
	for i in range(leaf.length()):
		var code := leaf.unicode_at(i)
		var allowed := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95 or code == 45 or code == 46
		if not allowed:
			return false
	return true
