extends SceneTree

const Plan = preload("res://addons/ai_game_builder/plan.gd")
const Validator = preload("res://addons/ai_game_builder/validator.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	_test_valid_plan()
	_test_rejections()
	_test_json_parsing()
	_test_file_lifecycle()
	_test_diagnostics()
	_test_symlink_guard()
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
	_check(not Plan.validate({"files": [_file("res://ai_generated/editor.gd", "@tool\nextends Node\n")]})["ok"], "rejects executing editor scripts")
	_check(Plan.validate({"files": [_file("res://ai_generated/comment.gd", "# @tool is only a comment\nextends Node\n")]})["ok"], "allows @tool in comments")
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


func _test_diagnostics() -> void:
	var main_path := "res://ai_generated/main.tscn"
	var hero_path := "res://ai_generated/hero.gd"
	var scene := '[gd_scene load_steps=2 format=3]' + "\n" + \
			'[ext_resource type="Script" path="res://ai_generated/hero.gd" id="1_script"]' + "\n" + \
			'[node name="Game" type="Node2D"]' + "\n" + \
			'script = ExtResource("1_script")' + "\n"
	var correct := Validator.analyze_plan({"files": [
		_file(main_path, scene),
		_file(hero_path, "extends Node2D\n")
	]})
	_check(correct["ok"], "valid scene can refer to a script created in the same plan")
	_check(correct["errors"].is_empty(), "valid plan has no reference errors")
	_check(correct["warnings"].is_empty(), "valid plan with entry scene has no warnings")
	_check(correct["files"] == 2, "analyzer counts files")

	var missing := Validator.analyze_plan({"files": [_file(main_path, scene)]})
	_check(not missing["ok"], "missing scene reference is an error")
	_check(missing["errors"].size() == 1, "missing scene reference is reported once")
	_check(Validator.format_report(missing).contains("missing referenced resource"), "formatted error includes cause")
	_check(Validator.format_report(missing).contains("main.tscn:2:"), "error includes exact line number")

	var missing_main := Validator.analyze_plan({"files": [_file(hero_path, "extends Node2D\n")]})
	_check(missing_main["ok"], "a missing main scene is a warning, not an error")
	_check(missing_main["warnings"].size() == 1, "missing main scene is warned about")
	_check(Validator.format_report(missing_main).contains("WARNING:"), "warnings appear in report")

	var malformed_scene := Validator.analyze_plan({"files": [_file(main_path, "[node name=\"Game\" type=\"Node2D\"]\n")]})
	_check(not malformed_scene["ok"], "detects missing scene header")
	var malformed_resource := Validator.analyze_plan({"files": [_file("res://ai_generated/r.tres", "Resource\n")]})
	_check(not malformed_resource["ok"], "detects missing resource header")
	var malformed_json := Validator.analyze_plan({"files": [_file("res://ai_generated/data.json", "{invalid")]})
	_check(not malformed_json["ok"], "detects invalid JSON")
	var good_json := Validator.analyze_plan({"files": [_file("res://ai_generated/data.json", "{\"ok\":true}")]})
	_check(good_json["ok"], "accepts valid JSON")

	var script_ref := Validator.analyze_plan({"files": [
		_file(hero_path, 'extends Node2D' + "\n" + 'const UI = preload("res://ai_generated/missing_ui.tscn")' + "\n")
	]})
	_check(not script_ref["ok"], "detects missing GDScript preload target")
	var dynamic_ref := Validator.analyze_plan({"files": [
		_file(hero_path, 'extends Node2D' + "\n" + 'var item = load("res://ai_generated/missing_item.tres")' + "\n")
	]})
	_check(not dynamic_ref["ok"], "detects missing GDScript load target")
	var repeated_ref := Validator.analyze_plan({"files": [
		_file(hero_path, 'extends Node2D' + "\n" +
			'var a = load("res://ai_generated/missing_item.tres")' + "\n" +
			'var b = load("res://ai_generated/missing_item.tres")' + "\n")
	]})
	_check(repeated_ref["errors"].size() == 1, "deduplicates repeated references in one file")

	var risky := Validator.analyze_plan({"files": [
		_file(hero_path, 'extends Node' + "\n" + 'func go(): OS.execute("something", [])' + "\n")
	]})
	_check(risky["ok"], "risky call produces a warning but not an error")
	_check(risky["warnings"].size() >= 1, "OS.execute call produces a review warning")
	var shader := Validator.analyze_plan({"files": [_file("res://ai_generated/a.gdshader", "void fragment() {}\n")]})
	_check(not shader["warnings"].is_empty(), "shader without shader_type is warned about")
	var rejected := Validator.analyze_plan({"files": [_file(hero_path, "@tool\nextends Node\n")]})
	_check(not rejected["ok"], "static inspection rejects editor scripts")

	var on_disk_path := "res://ai_generated/ai_validator_disk_test.gd"
	if FileAccess.file_exists(on_disk_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(on_disk_path))
	var created := Plan.apply({"files": [_file(on_disk_path, "extends Node\n")]})
	_check(created["ok"], "creates a resource for disk reference tests")
	var disk_scene := '[gd_scene format=3]' + "\n" + \
			'[ext_resource type="Script" path="' + on_disk_path + '" id="1"]' + "\n" + \
			'[node name="Root" type="Node"]' + "\n"
	var file_exists_report := Validator.analyze_plan({"files": [_file(main_path, disk_scene)]})
	_check(file_exists_report["ok"], "references to unchanged resources on disk are accepted")
	var saved := Validator.analyze_saved()
	_check(saved["files"] >= 1, "static inspection reads real generated files")
	_check(saved["ok"], "saved known-good GDScript passes static inspection")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(on_disk_path))


func _test_symlink_guard() -> void:
	# The generated directory must not be able to escape through a symlink.
	# Link creation can be unavailable on some platforms; CI verifies Linux.
	var root := DirAccess.open("res://")
	_check(root != null, "project root can be opened for link checks")
	if root == null:
		return
	var link_path := "res://ai_generated/ai_builder_link_test"
	var global_link := ProjectSettings.globalize_path(link_path)
	if root.create_link(ProjectSettings.globalize_path("res://"), global_link) != OK:
		print("SKIP symlink test: creating links is unavailable.")
		return
	var result := Plan.apply({"files": [
		_file(link_path + "/escaped.gd", "extends Node\n")
	]})
	_check(not result["ok"], "refuses to write through a directory symlink")
	_check(not FileAccess.file_exists("res://escaped.gd"), "symlink guard prevented outside file creation")
	DirAccess.remove_absolute(global_link)
