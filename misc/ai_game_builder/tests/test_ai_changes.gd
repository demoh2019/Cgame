extends SceneTree

const Changes = preload("res://addons/ai_game_builder/ai_changes.gd")
const Protocol = preload("res://addons/ai_game_builder/ai_protocol.gd")
const Preflight = preload("res://addons/ai_game_builder/ai_preflight.gd")
const Repair = preload("res://addons/ai_game_builder/ai_repair.gd")
const Diagnostics = preload("res://addons/ai_game_builder/ai_diagnostics.gd")
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
	_assert_true(not Protocol.is_allowed_endpoint("http://localhost:11434@evil.example/v1/chat/completions"), "userinfo host injection refused")
	_assert_true(not Protocol.is_allowed_endpoint("http://localhost:70000/v1/chat/completions"), "out of range port refused")
	_assert_true(not Protocol.is_allowed_endpoint("http://localhost:1234?evil=1"), "query-only authority refused")
	_assert_true(Protocol.is_allowed_endpoint("http://127.0.0.1:11434/v1/chat/completions"), "IPv4 loopback allowed")
	_assert_true(Protocol.is_allowed_endpoint("http://[::1]:11434/v1/chat/completions"), "IPv6 loopback allowed")
	var request: Variant = JSON.parse_string(Protocol.request_body("test-model", "Make a game", ""))
	_assert_true(request is Dictionary and request["model"] == "test-model", "request construction")
	_assert_true(Preflight.check(_proposal("res://example.gd"))["ok"], "script preflight passes")
	_assert_true(not Preflight.check(_proposal("res://editor.gd", "@tool\nextends Node"))["ok"], "@tool scripts blocked")
	_assert_true(not Preflight.check(_proposal("res://example.gd", ""))["ok"], "empty script rejected")
	_assert_true(Preflight.check(_proposal("res://data.json", JSON.stringify({"ok": true})))["ok"], "valid json accepted")
	_assert_true(not Preflight.check(_proposal("res://data.json", "{broken}"))["ok"], "invalid json rejected")
	_assert_true(Preflight.check(_proposal("res://game.tscn", "[gd_scene format=3]\\n"))["ok"], "valid scene header")
	_assert_true(not Preflight.check(_proposal("res://game.tscn", "not a scene"))["ok"], "invalid scene header")
	_assert_true(not Preflight.check(_proposal("res://asset.gdshader", "bad shader"))["ok"], "invalid shader rejected")
	var repair_request: Variant = JSON.parse_string(Protocol.repair_request_body("model", "Make game", "Parser Error at line 3", "(no files)"))
	_assert_true(repair_request is Dictionary and repair_request["messages"][1]["content"].contains("Parser Error"), "repair request includes diagnostics")
	var no_paths: Array[String] = []
	_assert_true(Repair.collect_context(no_paths).contains("No eligible"), "empty repair context")
	var cmd := Diagnostics.command_arguments("/tmp/godot sample project", "/tmp/godot-validation.log")
	_assert_true(cmd.find("--headless") >= 0, "headless argument")
	_assert_true(cmd.find("--import") >= 0, "import-only check")
	_assert_true(cmd.find("--recovery-mode") >= 0, "check uses recovery mode")
	_assert_true(cmd[cmd.find("--path") + 1] == "/tmp/godot sample project", "path kept as single argument")
	_assert_true(not cmd.has("--script"), "no dynamic script execution")
	_assert_true(Diagnostics.has_errors("SCRIPT ERROR: Parse Error"), "Godot parser failure recognized")
	_assert_true(Diagnostics.has_errors("ERROR: Failed to load scene"), "asset load error recognized")
	_assert_true(not Diagnostics.has_errors("Godot Engine editor started."), "successful log not considered error")
	_assert_true(Diagnostics.result_label(1, false, "").contains("code 1"), "non-zero exit handled")
	_assert_true(Diagnostics.result_label(-1, true, "").contains("timed out"), "timeout reported")
	_assert_true(Diagnostics.result_label(0, false, "").contains("inconclusive"), "empty output is inconclusive")
	var log_path := "user://ai_game_builder/tests/diagnostic_tail_%d.log" % Time.get_ticks_usec()
	_assert_true(Diagnostics.read_log(log_path).is_empty(), "missing diagnostic log returns empty")
	_assert_true(DirAccess.make_dir_recursive_absolute(log_path.get_base_dir()) == OK, "diagnostics test folder created")
	var log_file := FileAccess.open(log_path, FileAccess.WRITE)
	_assert_true(log_file != null, "diagnostics test log opened")
	if log_file != null:
		log_file.store_string("A".repeat(Diagnostics.MAX_LOG_BYTES + 100) + "ERROR: test failure")
		log_file.close()
		var captured := Diagnostics.read_log(log_path)
		_assert_true(captured.length() <= Diagnostics.MAX_LOG_BYTES, "large logs are bounded")
		_assert_true(captured.contains("ERROR: test failure"), "tail retains latest error")
		_assert_true(Diagnostics.has_errors(captured), "captured error detected")
		DirAccess.remove_absolute(log_path)

	var state := Changes.preview_snapshot(_proposal("res://tests/newfile_never_created_123.gd"))
	_assert_true(state["ok"] and state["states"]["res://tests/newfile_never_created_123.gd"] == "__missing__", "snapshot records absent files")

