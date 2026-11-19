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
	_test("reject CON device file", not Validator.is_safe_relative_path("CON.gd"))
	_test("reject mixed-case Windows device name", not Validator.is_safe_relative_path("scenes/cOn.tscn"))
	_test("reject device directory", not Validator.is_safe_relative_path("AUX/scripts/player.gd"))
	_test("reject NUL device name", not Validator.is_safe_relative_path("nul.json"))
	_test("reject COM serial port name", not Validator.is_safe_relative_path("scripts/COM1.gd"))
	_test("reject LPT parallel port name", not Validator.is_safe_relative_path("LPT9.md"))
	_test("allow non-device prefix", Validator.is_safe_relative_path("scripts/COM10.gd"))
	_test("allow device-like ordinary basename", Validator.is_safe_relative_path("scripts/console.gd"))
	_test("reject file-as-parent", not Validator.validate_payload({"files": [
		{"path": "scripts/player.gd", "content": "extends Node"},
		{"path": "scripts/player.gd/child.gd", "content": "extends Node"},
	]})["ok"])
	_test("reject reversed file-as-parent", not Validator.validate_payload({"files": [
		{"path": "scripts/player.gd/child.gd", "content": "extends Node"},
		{"path": "scripts/player.gd", "content": "extends Node"},
	]})["ok"])
	_test("reject case-insensitive file-parent collision", not Validator.validate_payload({"files": [
		{"path": "scripts/Player.gd/child.gd", "content": "extends Node"},
		{"path": "scripts/player.GD", "content": "extends Node"},
	]})["ok"])
	_test("allow siblings in same folder", Validator.validate_payload({"files": [
		{"path": "scenes/main.tscn", "content": "[gd_scene format=3]\n[node name=\"Main\" type=\"Node\"]"},
		{"path": "scenes/menu.tscn", "content": "[gd_scene format=3]\n[node name=\"Menu\" type=\"Node\"]"},
	]})["ok"])
	_test("do not confuse prefix with a directory", Validator.validate_payload({"files": [
		{"path": "scripts/player.gd", "content": "extends Node"},
		{"path": "scripts/player.gdbackup/child.gd", "content": "extends Node"},
	]})["ok"])
	_test("reject oversize file", not Validator.validate_payload({"files": [{"path": "big.gd", "content": "a".repeat(Validator.MAX_FILE_BYTES + 1)}]})["ok"])

	var response := {"choices": [{"message": {"content": JSON.stringify(_valid())}}]}
	_test("parse valid completion", Validator.parse_model_response(JSON.stringify(response))["ok"])
	_test("reject invalid completion", not Validator.parse_model_response("{}")["ok"])
	_test("reject provider error", not Validator.parse_model_response(JSON.stringify({"error": {"message": "Bad key"}}))["ok"])
	_test("reject non-JSON completion content", not Validator.parse_model_response(JSON.stringify({"choices": [{"message": {"content": "garbage"}}]}))["ok"])
	_test("reject invalid API body", not Validator.parse_model_response("garbage")["ok"])


	_test("accept uppercase extension", Validator.is_safe_relative_path("scripts/Player.GD"))
	_test("reject dot segment", not Validator.is_safe_relative_path("scripts/./player.gd"))
	_test("reject hidden path", not Validator.is_safe_relative_path("files/.settings/file.gd"))
	_test("reject Unicode path", not Validator.is_safe_relative_path("мир.tscn"))
	_test("reject excessively long path", not Validator.is_safe_relative_path("a".repeat(180) + ".gd"))
	_test("reject empty path", not Validator.is_safe_relative_path(""))
	_test("reject unsupported binary", not Validator.is_safe_relative_path("sound.wav"))
	_test("reject missing content field", not Validator.validate_payload({"files": [{"path": "x.gd"}]})["ok"])
	_test("reject non-string content", not Validator.validate_payload({"files": [{"path": "x.gd", "content": 10}]})["ok"])
	_test("reject non-array files", not Validator.validate_payload({"files": {"path": "a.gd"}})["ok"])
	_test("reject invalid summary length", not Validator.validate_payload({"files": _valid()["files"], "summary": "x".repeat(4001)})["ok"])
	_test("reject malformed choice", not Validator.parse_model_response(JSON.stringify({"choices": ["x"]}))["ok"])
	_test("reject missing message", not Validator.parse_model_response(JSON.stringify({"choices": [{}]}))["ok"])
	_test("reject non-string message", not Validator.parse_model_response(JSON.stringify({"choices": [{"message": {"content": []}}]}))["ok"])
	_test("reject embedded traversal in path", not Validator.validate_payload({"files": [{"path": "scenes/../../secret.gd", "content": "extends Node"}]})["ok"])
	_test("no missing references", Validator.find_missing_generated_references(_valid()["files"]).is_empty())
	_test("references to generated files accepted", Validator.validate_payload({"files": [
		{"path": "scripts/child.gd", "content": "extends Node"},
		{"path": "scenes/main.tscn", "content": "[gd_scene load_steps=2 format=3]\n[ext_resource type=\"Script\" path=\"res://ai_generated/scripts/child.gd\" id=\"1_a\"]\n[node name=\"Main\" type=\"Node\"]\nscript = ExtResource(\"1_a\")"},
	]})["ok"])
	_test("missing generated dependency rejected", not Validator.validate_payload({"files": [
		{"path": "scripts/player.gd", "content": "extends Node\nconst CHILD = preload(\"res://ai_generated/scripts/missing.gd\")"},
	]})["ok"])
	_test("missing script dependency reported", Validator.find_missing_generated_references([
		{"path": "scripts/player.gd", "content": "const CHILD = preload(\"res://ai_generated/scripts/missing.gd\")"},
	]).size() == 1)
	_test("ignore README resource mentions", Validator.validate_payload({"files": [
		{"path": "README.md", "content": "Open res://ai_generated/scenes/main.tscn when ready."},
	]})["ok"])

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
