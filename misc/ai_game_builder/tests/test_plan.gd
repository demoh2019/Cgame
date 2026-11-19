extends SceneTree
## Run: godot --headless --path misc/ai_game_builder --script res://tests/test_plan.gd

const PLAN = preload("res://addons/ai_game_builder/plan.gd")
const WRITER = preload("res://addons/ai_game_builder/writer.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_paths()
	_test_manifest()
	_test_response()
	_test_writer()
	print("AI Game Builder: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _valid_plan(path: String = "res://ai_generated/main.tscn", content: String = "[gd_scene format=3]\n\n[node name=\"Game\" type=\"Node2D\"]\n") -> Dictionary:
	return {"summary": "Game prototype", "main_scene": path, "files": [{"path": path, "content": content}]}


func _test_paths() -> void:
	_check(PLAN.path_error_message("res://ai_generated/main.tscn") == "", "Simple scene is valid")
	_check(PLAN.path_error_message("res://ai_generated/scenes/level_one.tscn") == "", "Nested scene is valid")
	for bad in [
		"res://project.godot",
		"res://addons/plugin.gd",
		"res://ai_generated/../project.godot",
		"res://ai_generated/foo/../../private.gd",
		"res://ai_generated//game.gd",
		"res://ai_generated/.godot/cache.gd",
		"res://ai_generated/.hidden.gd",
		"res://ai_generated/test\\file.gd",
		"res://ai_generated/main.exe",
		"res://ai_generated/main.sh",
		"res://ai_generated/C:/test.gd",
		"res://ai_generated/sub/CON.gd",
		"res://ai_generated/sub/a*.gd",
		"res://ai_generated/sub/",
		"res://ai_generated/foo.gd ",
		"res://ai_generated/.",
		"/tmp/malicious.gd"
	]:
		_check(not PLAN.path_error_message(bad).is_empty(), "Reject unsafe path: " + bad)


func _test_manifest() -> void:
	_check(PLAN.validate(_valid_plan()).ok, "Valid minimal scene")
	_check(not PLAN.validate([]).ok, "Reject non-object")
	_check(not PLAN.validate({}).ok, "Reject missing files")
	_check(not PLAN.validate({"files": []}).ok, "Reject zero files")
	_check(not PLAN.validate({"files": ["bad"]}).ok, "Reject non-file entry")
	_check(not PLAN.validate({"files": [{"path": 3, "content": "ok"}]}).ok, "Reject non-string path")
	_check(not PLAN.validate({"files": [{"path": "res://ai_generated/a.gd", "content": 1}]}).ok, "Reject non-string content")
	_check(not PLAN.validate({"summary": 4, "files": [{"path": "res://ai_generated/a.gd", "content": "pass"}]}).ok, "Reject non-string summary")
	var duplicate := _valid_plan()
	duplicate["files"].append({"path": "res://ai_generated/MAIN.tscn", "content": "another"})
	_check(not PLAN.validate(duplicate).ok, "Reject case-insensitive duplicate")
	var bad_main := _valid_plan()
	bad_main["main_scene"] = "res://ai_generated/absent.tscn"
	_check(not PLAN.validate(bad_main).ok, "Main scene must be generated")
	bad_main["main_scene"] = "res://ai_generated/main.gd"
	_check(not PLAN.validate(bad_main).ok, "Main scene must have .tscn extension")
	var tool := {"files": [{"path": "res://ai_generated/helper.gd", "content": "@tool\nextends Node\n"}]}
	_check(not PLAN.validate(tool).ok, "Reject executable tool script")
	tool["files"][0]["content"] = "# harmless @tool comment\nextends Node\n"
	_check(PLAN.validate(tool).ok, "Allow harmless comment")
	var huge := _valid_plan("res://ai_generated/main.tscn", "a".repeat(PLAN.MAX_FILE_BYTES + 1))
	_check(not PLAN.validate(huge).ok, "Reject oversized file")
	var too_many := {"files": []}
	for i in range(PLAN.MAX_FILES + 1):
		too_many["files"].append({"path": "res://ai_generated/%02d.gd" % i, "content": "pass"})
	_check(not PLAN.validate(too_many).ok, "Reject excess files")
	var too_big := {"files": []}
	for i in range(5):
		too_big["files"].append({"path": "res://ai_generated/%d.gd" % i, "content": "a".repeat(120000)})
	_check(not PLAN.validate(too_big).ok, "Reject total byte limit")


func _test_response() -> void:
	var valid := JSON.stringify(_valid_plan())
	_check(PLAN.parse_response(valid).ok, "Parse JSON directly")
	_check(PLAN.parse_response("```json\n" + valid + "\n```").ok, "Parse fenced JSON")
	_check(not PLAN.parse_response("this is not json").ok, "Reject invalid JSON")
	_check(not PLAN.parse_response("```json\n{" ).ok, "Reject incomplete code fence")


func _test_writer() -> void:
	const PATH := "res://ai_generated/ai_game_builder_regression.tscn"
	# Cleanup only the known disposable test file, not user files.
	var plan := _valid_plan(PATH)
	if FileAccess.file_exists(PATH):
		push_warning("Skipping writer test because fixture already exists: " + PATH)
		return
	_check(WRITER.preflight(plan).ok, "Preflight new scene")
	var result: Dictionary = WRITER.apply(plan, false)
	_check(result.ok, "Create new scene")
	_check(FileAccess.file_exists(PATH), "Output exists")
	var contents := FileAccess.get_file_as_string(PATH)
	_check(contents == plan["files"][0]["content"], "Output matches plan")
	_check(not WRITER.preflight(plan).ok, "Refuse overwrite in preflight")
	_check(not WRITER.apply(plan, false).ok, "Refuse overwrite in apply")
	_check(FileAccess.get_file_as_string(PATH) == contents, "Existing scene unchanged")
	_check(not FileAccess.file_exists(PATH + ".ai_tmp"), "No leftover stage file")
	var removed := DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	_check(removed == OK, "Clean up scene fixture")
