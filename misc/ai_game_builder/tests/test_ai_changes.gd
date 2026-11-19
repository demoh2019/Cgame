extends SceneTree

const Changes = preload("res://addons/ai_game_builder/ai_changes.gd")
const Protocol = preload("res://addons/ai_game_builder/ai_protocol.gd")
var failures := 0


func _initialize() -> void:
	_run_tests()
	if failures:
		printerr("%d AI Game Builder tests failed" % failures)
		quit(1)
	else:
		print("AI Game Builder validation tests passed")
		quit(0)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func _proposal(path: String, content: Variant = "extends Node\n") -> Dictionary:
	return {"summary": "Sample", "files": [{"path": path, "content": content}], "main_scene": ""}


func _run_tests() -> void:
	var good := Changes.validate_response(_proposal("res://scripts/player.gd"))
	_assert_true(good["ok"], "normal gd path accepted")
	for bad in ["user://temp.gd", "res://../escape.gd", "res://folder/../../escape.gd", "res://.godot/file.gd", "res://folder//file.gd", "res:///absolute.gd", "res://script.exe", "res://folder\\file.gd", "res://folder/./file.gd", "res://file.gd\n"]:
		_assert_true(not Changes.is_safe_path(bad), "reject path: " + bad)
	_assert_true(Changes.is_safe_path("res://сцены/уровень.tscn"), "unicode filename accepted")
	_assert_true(not Changes.validate_response(_proposal("res://player.gd", 42))["ok"], "non-string content rejected")
	_assert_true(not Changes.validate_response({"files": []})["ok"], "empty file set rejected")
	_assert_true(not Changes.validate_response({"files": [null]})["ok"], "null file rejected")
	_assert_true(not Changes.validate_response({"files": [{"path": "res://a.gd", "content": "a"}, {"path": "res://a.gd", "content": "b"}]})["ok"], "duplicate rejected")
	_assert_true(not Changes.validate_response(_proposal("res://large.txt", "x".repeat(262145)))["ok"], "oversized generation rejected")
	_assert_true(not Changes.validate_response({"files": [{"path": "res://a.gd", "content": "x"}], "main_scene": "res://a.gd"})["ok"], "main scene must be tscn")
	_assert_true(not Changes.validate_response({"files": [{"path": "res://a.gd", "content": "x"}], "main_scene": 1})["ok"], "main scene type validated")
	var raw := JSON.stringify({"choices": [{"message": {"content": JSON.stringify(_proposal("res://main.gd"))}}]})
	_assert_true(Changes.parse_chat_completion(raw)["ok"], "valid OpenAI response")
	var fenced := JSON.stringify({"choices": [{"message": {"content": "```json\n" + JSON.stringify(_proposal("res://main.gd")) + "\n```"}}]})
	_assert_true(Changes.parse_chat_completion(fenced)["ok"], "Markdown fenced response")
	_assert_true(not Changes.parse_chat_completion("{bad")["ok"], "invalid server JSON rejected")
	_assert_true(not Changes.parse_chat_completion(JSON.stringify({"choices": []}))["ok"], "missing choices rejected")
	_assert_true(not Changes.parse_chat_completion(JSON.stringify({"error": {"message": "bad key"}}))["ok"], "provider errors surfaced")
	_assert_true(Protocol.is_allowed_endpoint("https://api.openai.com/v1/chat/completions"), "TLS permitted")
	_assert_true(Protocol.is_allowed_endpoint("http://localhost:11434/v1/chat/completions"), "Ollama permitted")
	_assert_true(not Protocol.is_allowed_endpoint("http://remote-host:1234/v1/chat/completions"), "remote plaintext refused")
	var request: Variant = JSON.parse_string(Protocol.request_body("test-model", "Make a game", ""))
	_assert_true(request is Dictionary and request["model"] == "test-model", "request construction")
