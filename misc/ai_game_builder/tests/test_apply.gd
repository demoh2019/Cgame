extends SceneTree

const Changes = preload("res://addons/ai_game_builder/ai_changes.gd")
var failures := 0


func _initialize() -> void:
	_run()
	if failures > 0:
		printerr("%d AI file-apply tests failed" % failures)
		quit(1)
	else:
		print("AI Game Builder filesystem tests passed")
		quit(0)


func _expect(value: bool, why: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + why)


func _make_set(path: String, value: String, scene: String = "") -> Dictionary:
	return {"summary": "test", "main_scene": scene, "files": [{"path": path, "content": value}]}


func _run() -> void:
	var target := "res://tests/generated_ai_test.txt"
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	var first := Changes.apply_changes(_make_set(target, "new text"))
	_expect(first.get("ok", false), "new file can be applied")
	_expect(FileAccess.get_file_as_string(target) == "new text", "new file contents")
	_expect(first.get("backup_dir", "") == "", "new file needs no backup")

	var second := Changes.apply_changes(_make_set(target, "updated text"))
	_expect(second.get("ok", false), "existing file can be overwritten")
	_expect(FileAccess.get_file_as_string(target) == "updated text", "overwritten contents")
	var backup: String = second.get("backup_dir", "")
	_expect(not backup.is_empty(), "existing file was backed up")
	_expect(FileAccess.get_file_as_string(backup.path_join("tests/generated_ai_test.txt")) == "new text", "backup preserves original bytes")

	var snapshot := Changes.preview_snapshot(_make_set(target, "model changes"))
	_expect(snapshot["ok"], "preview snapshot generated")
	var manual := FileAccess.open(target, FileAccess.WRITE)
	manual.store_string("manual edit")
	manual.close()
	var conflict := Changes.apply_changes(_make_set(target, "model changes"), snapshot["states"])
	_expect(not conflict.get("ok", true), "concurrent edits must stop apply")
	_expect(FileAccess.get_file_as_string(target) == "manual edit", "manual edits survive stale proposal")

	var invalid := Changes.apply_changes(_make_set("res://../outside.txt", "never"))
	_expect(not invalid.get("ok", true), "unsafe proposal cannot be applied")

	var old_scene: Variant = ProjectSettings.get_setting("application/run/main_scene", "")
	var scene_path := "res://tests/generated_ai_scene.tscn"
	var scene_text := "[gd_scene format=3]\n\n[node name=\"Root\" type=\"Node\"]\n"
	var scene_result := Changes.apply_changes(_make_set(scene_path, scene_text, scene_path))
	_expect(scene_result.get("ok", false), "generating a main scene")
	_expect(ProjectSettings.get_setting("application/run/main_scene", "") == scene_path, "startup scene updated")
	ProjectSettings.set_setting("application/run/main_scene", old_scene)
	ProjectSettings.save()

	DirAccess.remove_absolute(target)
	DirAccess.remove_absolute(scene_path)
