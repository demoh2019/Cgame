extends SceneTree

const Validator = preload("res://addons/ai_game_builder/validator.gd")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_test("valid payload", Validator.validate_payload(_valid())["ok"])
	_test("nested safe path", Validator.is_safe_relative_path("scenes/level_01.tscn"))
	_test("reject traversal", not Validator.is_safe_relative_path("../secrets.gd"))
	_test("reject nested traversal", not Validator.is_safe_relative_path("a/../b.gd"))
	_test("reject absolute path", not Validator.is_safe_relative_path("/tmp/x.gd"))
	_test("reject res URI", not Validator.is_safe_relative_path("res://scripts/x.gd"))
	_test("reject Windows path", not Validator.is_safe_relative_path("C:\\temp\\x.gd"))
	_test("reject hidden files", not Validator.is_safe_relative_path(".godot/config.gd"))
	_test("reject disallowed extension", not Validator.is_safe_relative_path("shell.sh"))
	_test("reject double slash", not Validator.is_safe_relative_path("scenes//x.tscn"))
	_test("reject whitespace", not Validator.is_safe_relative_path("bad name.gd"))
	_test("reject newline", not Validator.is_safe_relative_path("x\nname.gd"))
	_test("reject file with empty content", not Validator.validate_payload({"files": [{"path": "x.gd", "content": ""}]})["ok"])
	_test("reject non-object payload", not Validator.validate_payload("not object")["ok"])
	_test("reject missing files", not Validator.validate_payload({})["ok"])
	_test("reject wrong summary type", not Validator.validate_payload({"files": _valid()["files"], "summary": 10})["ok"])
	_test("reject duplicate paths", not Validator.validate_payload({"files": [{"path": "x.gd", "content": "pass"}, {"path": "X.gd", "content": "pass"}]})["ok"])
	_test("reject @tool", not Validator.validate_payload({"files": [{"path": "scripts/x.gd", "content": "@tool\nextends Node"}]})["ok"])
	_test("reject too many files", not Validator.validate_payload(_many_files())["ok"])
	_test("reject oversize file", not Validator.validate_payload({"files": [{"path": "big.gd", "content": "a".repeat(Validator.MAX_FILE_BYTES + 1)}]})["ok"])

	var response := {"choices": [{"message": {"content": JSON.stringify(_valid())}}]}
	_test("parse valid completion", Validator.parse_model_response(JSON.stringify(response))["ok"])
	_test("reject invalid completion", not Validator.parse_model_response("{}")["ok"])
	_test("reject provider error", not Validator.parse_model_response(JSON.stringify({"error": {"message": "Bad key"}}))["ok"])
	_test("reject non-JSON completion content", not Validator.parse_model_response(JSON.stringify({"choices": [{"message": {"content": "garbage"}}]}))["ok"])
	_test("reject invalid API body", not Validator.parse_model_response("garbage")["ok"])

	print("AI Game Builder validator tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _valid() -> Dictionary:
	return {
		"summary": "A small prototype",
		"files": [
			{"path": "scenes/main.tscn", "content": "[gd_scene format=3]\n\n[node name=\"Main\" type=\"Node2D\"]\n"},
			{"path": "scripts/player.gd", "content": "extends Node2D\n"},
		],
	}


func _many_files() -> Dictionary:
	var files := []
	for i in range(Validator.MAX_FILES + 1):
		files.append({"path": "file%d.gd" % i, "content": "extends Node\n"})
	return {"files": files}


func _test(label: String, successful: bool) -> void:
	if successful:
		_passed += 1
	else:
		_failed += 1
		push_error("FAILED: %s" % label)
