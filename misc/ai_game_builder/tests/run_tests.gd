extends SceneTree

const Plan = preload("res://addons/ai_game_builder/plan.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	_test_valid_plan()
	_test_rejections()
	_test_json_parsing()
	_test_file_lifecycle()
	if failures > 0:
		printerr("%d of %d AI Game Builder checks failed." % [failures, checks])
		quit(1)
	else:
		print("Passed %d AI Game Builder checks." % checks)
		quit(0)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func _file(path: String, content: Variant = "extends Node\n", operation: String = "create") -> Dictionary:
	return {"path": path, "content": content, "operation": operation}


func _test_valid_plan() -> void:
	var v := Plan.validate({"summary": "one file", "files": [_file("res://ai_generated/main.tscn", "[gd_scene format=3]\n")]})
	_check(v["ok"], "accepts a valid scene")
	_check(v["files"].size() == 1, "keeps accepted files")
	_check(v["summary"] == "one file", "preserves summary")


func _test_rejections() -> void:
	_check(not Plan.validate([])["ok"], "rejects non-object plans")
	_check(not Plan.validate({})["ok"], "rejects missing file list")
	_check(not Plan.validate({"files": []})["ok"], "rejects empty file list")
	_check(not Plan.validate({"files": [_file("res://evil.gd")]})["ok"], "rejects files outside generated namespace")
	_check(not Plan.validate({"files": [_file("res://ai_generated/../addons/evil.gd")]})["ok"], "rejects parent traversal")
	_check(not Plan.validate({"files": [_file("res://ai_generated/.hidden.gd")]})["ok"], "rejects hidden files")
	_check(not Plan.validate({"files": [_file("res://ai_generated/folder//bad.gd")]})["ok"], "rejects empty path components")
	_check(not Plan.validate({"files": [_file("res://ai_generated/back\\slash.gd")]})["ok"], "rejects backslashes")
	_check(not Plan.validate({"files": [_file("res://ai_generated/a.gd\nx")]})["ok"], "rejects control characters")
	_check(not Plan.validate({"files": [_file("res://ai_generated/image.exe")]})["ok"], "rejects executable extension")
	_check(not Plan.validate({"files": [_file("res://ai_generated/a.gd", 123)]})["ok"], "rejects non-string content")
	_check(not Plan.validate({"files": [_file("res://ai_generated/a.gd", "")]})["ok"], "rejects empty file")
	_check(not Plan.validate({"files": [_file("res://ai_generated/a.gd", "x".repeat(100001))]})["ok"], "rejects oversized file")
	_check(not Plan.validate({"files": [_file("res://ai_generated/a.gd", "a", "delete")]})["ok"], "rejects unknown operation")
	_check(not Plan.validate({"files": [_file("res://ai_generated/a.gd"), _file("res://ai_generated/a.gd")]})["ok"], "rejects duplicate paths")
	var many := []
	for i in 21:
		many.append(_file("res://ai_generated/file_%d.gd" % i))
	_check(not Plan.validate({"files": many})["ok"], "rejects more than 20 files")
	var large := []
	for i in 5:
		large.append(_file("res://ai_generated/large_%d.gd" % i, "x".repeat(90000)))
	_check(not Plan.validate({"files": large})["ok"], "rejects excessive total size")


func _test_json_parsing() -> void:
	var proposal := {"summary": "test", "files": [_file("res://ai_generated/example.gd")]}
	_check(Plan.parse_message(JSON.stringify(proposal))["ok"], "parses model JSON")
	_check(not Plan.parse_message("not json")["ok"], "rejects malformed JSON")
	_check(not Plan.parse_message("[]")["ok"], "rejects JSON arrays")


func _test_file_lifecycle() -> void:
	var path := "res://ai_generated/ai_builder_test.gd"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var create_plan := {"files": [_file(path, "extends Node\n")]}
	var created := Plan.apply(create_plan)
	_check(created["ok"], "creates files")
	_check(FileAccess.file_exists(path), "created file exists")
	_check(not Plan.apply(create_plan)["ok"], "refuses to overwrite on create")
	var updated := Plan.apply({"files": [_file(path, "extends Node2D\n", "update")]})
	_check(updated["ok"], "updates an existing generated file")
	var read := FileAccess.open(path, FileAccess.READ)
	_check(read != null and read.get_as_text() == "extends Node2D\n", "update preserves exact text")
	if read != null:
		read.close()
	_check(not Plan.apply({"files": [_file("res://ai_generated/missing_update.gd", "x", "update")]})["ok"], "rejects missing update target")
	var rejected_batch := Plan.apply({"files": [_file("res://ai_generated/should_not_exist.gd"), _file(path)]})
	_check(not rejected_batch["ok"], "preflight fails before a partial batch")
	_check(not FileAccess.file_exists("res://ai_generated/should_not_exist.gd"), "preflight made no changes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
