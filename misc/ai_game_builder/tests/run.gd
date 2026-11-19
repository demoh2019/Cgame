extends SceneTree

const Validator = preload("res://addons/ai_game_builder/validator.gd")
const Planner = preload("res://addons/ai_game_builder/planner.gd")
const Writer = preload("res://addons/ai_game_builder/writer.gd")

var _total := 0
var _failed := 0


func _initialize() -> void:
	_run()
	print("AI Game Builder: %d tests, %d failed" % [_total, _failed])
	quit(0 if _failed == 0 else 1)


func _plan(path: String = "main.tscn", content: String = "[gd_scene format=3]\n") -> Dictionary:
	return {"summary": "demo", "files": [{"path": path, "content": content}]}


func _check(condition: bool, description: String) -> void:
	_total += 1
	if not condition:
		_failed += 1
		printerr("FAIL: " + description)


func _accept(value: Variant, description: String) -> void:
	_check(Validator.validate(value).ok, description)


func _reject(value: Variant, description: String) -> void:
	_check(not Validator.validate(value).ok, description)


func _run() -> void:
	_accept(_plan(), "simple scene")
	_accept(_plan("levels/first/level_01.tscn"), "nested path")
	_accept(_plan("shader.gdshader", "shader_type canvas_item;"), "shader allowed")
	_accept(_plan("data.json", "{}"), "JSON allowed")
	_accept(_plan("README.md", "text"), "Markdown allowed")
	_accept(_plan("note.txt", "text"), "text allowed")
	_accept(_plan("scripts/player.gd", "extends Node\n"), "script allowed")
	_accept(_plan("a.tres", "[gd_resource type=\"Resource\" format=3]\n"), "resource allowed")

	_reject(null, "null plan")
	_reject([], "array plan")
	_reject({}, "files missing")
	_reject({"files": []}, "no files")
	_reject({"files": "bad"}, "files not array")
	_reject({"files": ["bad"]}, "file not dictionary")
	_reject({"files": [{"path": "a.gd"}]}, "content missing")
	_reject({"files": [{"content": "x"}]}, "path missing")
	_reject({"files": [{"path": 3, "content": "x"}]}, "path nonstring")
	_reject({"files": [{"path": "a.gd", "content": 3}]}, "content nonstring")
	_reject(_plan("../escape.gd"), "parent traversal")
	_reject(_plan("a/../escape.gd"), "nested traversal")
	_reject(_plan("./bad.gd"), "dot segment")
	_reject(_plan("/abs.gd"), "absolute path")
	_reject(_plan("res://outside.gd"), "resource path rejected")
	_reject(_plan("C:/windows.gd"), "drive path rejected")
	_reject(_plan("folder\\bad.gd"), "backslash rejected")
	_reject(_plan("double//slash.gd"), "empty segment rejected")
	_reject(_plan("hidden/.config.gd"), "hidden path rejected")
	_reject(_plan(".env"), "hidden secret file rejected")
	_reject(_plan("spaces are bad.gd"), "spaces rejected")
	_reject(_plan("café.gd"), "non-ASCII path rejected")
	_reject(_plan("a.png"), "binary extension rejected")
	_reject(_plan("evil.exe"), "executable extension rejected")
	_reject(_plan("bad.gd\n"), "trailing newline rejected")
	_reject(_plan("a\n/b.gd"), "embedded newline rejected")
	_reject(_plan("file.gd", ""), "empty content rejected")
	_reject(_plan("file.gd", "x".repeat(Validator.MAX_FILE_BYTES + 1)), "oversized file rejected")
	_reject(_plan("file.gd", "hi\u0000there"), "embedded NUL rejected")
	_reject({"summary": 5, "files": _plan().files}, "nonstring summary")
	_reject({"summary": "x".repeat(801), "files": _plan().files}, "oversized summary")
	_reject(_plan("a".repeat(161) + ".gd"), "long path rejected")
	_accept(_plan("file.gd", "x".repeat(Validator.MAX_FILE_BYTES)), "file at size limit")

	var duplicates := {"files": [{"path": "Level.tscn", "content": "a"}, {"path": "level.tscn", "content": "b"}]}
	_reject(duplicates, "case-insensitive duplicates")
	var too_many: Array = []
	for index in range(Validator.MAX_FILES + 1):
		too_many.append({"path": "f%d.gd" % index, "content": "x"})
	_reject({"files": too_many}, "too many files")
	var oversized_total: Array = []
	for index in range(5):
		oversized_total.append({"path": "f%d.gd" % index, "content": "x".repeat(Validator.MAX_FILE_BYTES)})
	_reject({"files": oversized_total}, "total byte limit")
	var at_limit: Array = []
	for index in range(4):
		at_limit.append({"path": "f%d.gd" % index, "content": "x".repeat(Validator.MAX_FILE_BYTES)})
	_accept({"files": at_limit}, "total byte limit accepted")

	_check(not Validator.parse("{broken").ok, "invalid JSON rejected")
	_check(Validator.parse(JSON.stringify(_plan())).ok, "valid JSON parsed")
	_check(not Planner.read_response("{}").ok, "empty provider response")
	_check(not Planner.read_response("invalid").ok, "invalid provider response")
	_check(not Planner.read_response("{\"choices\": [null]}").ok, "invalid choice")
	_check(not Planner.read_response("{\"choices\": [{}]}").ok, "missing message")
	_check(not Planner.read_response("{\"choices\": [{\"message\": {}}]}").ok, "missing content")
	var response := JSON.stringify({"choices": [{"message": {"content": JSON.stringify(_plan())}}]})
	_check(Planner.read_response(response).ok, "valid provider response")
	var fence := "\u0060\u0060\u0060"
	var fenced := JSON.stringify({"choices": [{"message": {"content": fence + "json\n" + JSON.stringify(_plan()) + "\n" + fence}}]})
	_check(Planner.read_response(fenced).ok, "fenced JSON response")
	var payload: Variant = JSON.parse_string(Planner.make_request("test-model", "Build a game"))
	_check(typeof(payload) == TYPE_DICTIONARY and payload.model == "test-model", "request format")
	_check(payload.messages.size() == 2, "system and user prompts")

	# Writer integration runs only in the disposable test project.
	var output := "res://ai_generated/tests/generated.txt"
	var absolute := ProjectSettings.globalize_path(output)
	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(absolute)
	var result := Writer.apply(_plan("tests/generated.txt", "generated"))
	_check(result.ok, "writer creates file")
	_check(FileAccess.file_exists(output), "writer file exists")
	if FileAccess.file_exists(output):
		_check(FileAccess.get_file_as_string(output) == "generated", "writer preserves content")
		var conflict := Writer.apply(_plan("tests/generated.txt", "replacement"))
		_check(not conflict.ok, "writer refuses overwrite")
		_check(FileAccess.get_file_as_string(output) == "generated", "existing content unchanged")
		DirAccess.remove_absolute(absolute)
	_check(not Writer.apply(_plan("../escape.gd")).ok, "writer revalidates paths")
