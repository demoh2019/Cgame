extends SceneTree

const Plan = preload("res://addons/ai_game_builder/plan.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run_validation_tests()
	_run_write_tests()
	print("AI Builder tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)


func _sample(path: String = "scenes/main.tscn", content: String = "[gd_scene format=3]\n\n[node name=\"Main\" type=\"Node2D\"]\n") -> Dictionary:
	return {
		"summary": "Simple scene",
		"main_scene": "scenes/main.tscn" if path == "scenes/main.tscn" else "",
		"files": [{"path": path, "content": content}]
	}


func _run_validation_tests() -> void:
	_expect(Plan.validate_path("scenes/player.gd").is_empty(), "basic nested path")
	_expect(Plan.validate_path("world/data/map.csv").is_empty(), "csv path")
	var bad_paths := [
		"", "/tmp/file.gd", "../escape.gd", "folder/../escape.gd",
		"./file.gd", "folder//name.gd", "folder\\name.gd", "C:/file.gd",
		"res://file.gd", ".env", ".git/config.gd", ".godot/cache.gd",
		"addons/evil/plugin.gd", "ADDONS/evil/plugin.gd",
		"folder/.hidden.gd", "folder/ending./file.gd",
		"file.exe", "project.godot", "override.cfg", "export_presets.cfg", "script.gd\nother.gd",
		"script.gd\rother.gd", "file.txt/", "a/./main.gd"
	]
	for path in bad_paths:
		_expect(not Plan.validate_path(path).is_empty(), "reject unsafe path: " + path)

	_expect(not Plan.validate_plan({})["ok"], "reject missing files")
	_expect(not Plan.validate_plan({"files": 10})["ok"], "reject non-array")
	_expect(not Plan.validate_plan({"files": []})["ok"], "reject empty plan")
	_expect(not Plan.validate_plan({"files": [1]})["ok"], "reject non-object file")
	_expect(not Plan.validate_plan({"files": [{"path": "a.gd"}]})["ok"], "reject missing content")
	_expect(not Plan.validate_plan({"files": [{"path": 1, "content": "x"}]})["ok"], "reject non-string path")
	_expect(not Plan.validate_plan({"files": [{"path": "a.gd", "content": 1}]})["ok"], "reject non-string content")
	_expect(Plan.validate_plan(_sample())["ok"], "valid playable scene plan")
	_expect(Plan.validate_plan(_sample("scripts/player.gd", "extends Node\n"))["ok"], "valid script plan")
	_expect(not Plan.validate_plan(_sample("../escape.gd"))["ok"], "plan rejects traversal")

	var duplicates := _sample("scripts/player.gd", "extends Node\n")
	duplicates["files"].append({"path": "scripts/PLAYER.gd", "content": "extends Node2D\n"})
	_expect(not Plan.validate_plan(duplicates)["ok"], "reject duplicate paths case-insensitively")

	var too_many := {"files": []}
	for i in range(25):
		too_many["files"].append({"path": "data/%d.txt" % i, "content": "x"})
	_expect(not Plan.validate_plan(too_many)["ok"], "reject more than 24 files")

	var oversized := _sample("data/large.txt", "x".repeat(Plan.MAX_FILE_BYTES + 1))
	_expect(not Plan.validate_plan(oversized)["ok"], "reject oversized file")

	var total := {"files": []}
	for i in range(5):
		total["files"].append({"path": "data/%d.txt" % i, "content": "x".repeat(230000)})
	_expect(not Plan.validate_plan(total)["ok"], "reject total size limit")

	var wrong_main := _sample()
	wrong_main["main_scene"] = "scenes/missing.tscn"
	_expect(not Plan.validate_plan(wrong_main)["ok"], "reject main scene not in files")
	wrong_main["main_scene"] = "Scenes/main.tscn"
	_expect(not Plan.validate_plan(wrong_main)["ok"], "require exact-case main scene path")
	wrong_main["main_scene"] = 42
	_expect(not Plan.validate_plan(wrong_main)["ok"], "reject non-string main scene")
	wrong_main["main_scene"] = "scenes/main.tscn"
	_expect(Plan.validate_plan(wrong_main)["ok"], "accept referenced main scene")
	var wrong_extension := _sample("scripts/main.gd", "extends Node\n")
	wrong_extension["main_scene"] = "scripts/main.gd"
	_expect(not Plan.validate_plan(wrong_extension)["ok"], "main scene must be tscn")

	var wrong_summary := _sample()
	wrong_summary["summary"] = 50
	_expect(not Plan.validate_plan(wrong_summary)["ok"], "reject non-string summary")
	_expect(not Plan.validate_plan(_sample("data/nul.txt", "a\u0000b"))["ok"], "reject embedded NUL")
	_expect(not Plan.validate_plan(_sample("scripts/unsafe.gd", "@tool\\nextends EditorPlugin\\n"))["ok"], "reject @tool editor scripts")

	var valid_json := JSON.stringify(_sample())
	_expect(Plan.parse_response(valid_json)["ok"], "parse plain JSON")
	var fence := String.chr(96).repeat(3)
	_expect(Plan.parse_response(fence + "json\n" + valid_json + "\n" + fence)["ok"], "parse fenced JSON")
	_expect(not Plan.parse_response("not a JSON response")["ok"], "reject malformed JSON")
	_expect(not Plan.parse_response(fence + "json\n{\"files\":[]}")["ok"], "reject incomplete fence")
	_expect(not Plan.parse_response("[1, 2, 3]")["ok"], "reject JSON array")


func _run_write_tests() -> void:
	var relative := "tests/_ai_builder_generated.txt"
	var absolute := "res://" + relative
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)

	var initial := _sample(relative, "original")
	var first := Plan.apply_plan(initial, false)
	_expect(first["ok"], "write new file")
	_expect(FileAccess.file_exists(absolute), "new file exists")
	if FileAccess.file_exists(absolute):
		_expect(FileAccess.get_file_as_string(absolute) == "original", "content is correct")
	_expect(not Plan.apply_plan(initial, false)["ok"], "refuse overwrite by default")

	var replacement := _sample(relative, "changed")
	var second := Plan.apply_plan(replacement, true)
	_expect(second["ok"], "explicit overwrite succeeds")
	if second["ok"]:
		_expect(FileAccess.get_file_as_string(absolute) == "changed", "replacement content is correct")
		var backup: String = second["backup_root"].path_join(relative)
		_expect(FileAccess.file_exists(backup), "backup exists")
		if FileAccess.file_exists(backup):
			_expect(FileAccess.get_file_as_string(backup) == "original", "backup retains original data")


	# Preflight is all-or-nothing even when the last destination already exists.
	var two := {
		"files": [
			{"path": "tests/_ai_builder_first.txt", "content": "first"},
			{"path": relative, "content": "must not overwrite"}
		]
	}
	_expect(not Plan.apply_plan(two, false)["ok"], "preflight rejects conflicts before writing")
	_expect(not FileAccess.file_exists("res://tests/_ai_builder_first.txt"), "preflight created no partial new file")

	# Exercise best-effort rollback with both an overwritten and a new file.
	var added_path := "tests/_ai_builder_rollback_new.txt"
	var old_path := "tests/_ai_builder_rollback_old.txt"
	var old_file := FileAccess.open("res://" + old_path, FileAccess.WRITE)
	if old_file != null:
		old_file.store_string("before")
		old_file.close()
	var backup_dir := "user://ai_game_builder_test_rollback"
	DirAccess.make_dir_recursive_absolute(backup_dir.path_join("tests"))
	_expect(DirAccess.copy_absolute("res://" + old_path, backup_dir.path_join(old_path)) == OK, "prepare overwrite backup")
	var replaced_file := FileAccess.open("res://" + old_path, FileAccess.WRITE)
	if replaced_file != null:
		replaced_file.store_string("after")
		replaced_file.close()
	var new_file := FileAccess.open("res://" + added_path, FileAccess.WRITE)
	if new_file != null:
		new_file.store_string("new")
		new_file.close()
	var writes: Array[String] = [old_path, added_path]
	var overwritten: Array[String] = [old_path]
	var recovery := Plan._write_failed("Injected test failure", writes, overwritten, backup_dir)
	_expect(not recovery["ok"], "injected failure is reported")
	_expect(recovery["rolled_back"], "rollback reports restored state")
	_expect(FileAccess.get_file_as_string("res://" + old_path) == "before", "rollback restored original content")
	_expect(not FileAccess.file_exists("res://" + added_path), "rollback removed new file")
	DirAccess.remove_absolute("res://" + old_path)
	DirAccess.remove_absolute(backup_dir.path_join(old_path))
	DirAccess.remove_absolute(backup_dir.path_join("tests"))
	DirAccess.remove_absolute(backup_dir)
	DirAccess.remove_absolute(absolute)
